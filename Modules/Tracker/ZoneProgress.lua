-- Modules/Tracker/ZoneProgress.lua
-- Optional per-zone quest progress bar for the on-screen tracker. Shows the
-- player's "lifetime" questline completion for their current zone, e.g.
--   Eversong Woods          12 / 47
--   [#########----------------------]
--
-- WHY THIS IS BUILT THE WAY IT IS:
-- WoW has no API for "all quests in a zone", and C_QuestLine.GetAvailableQuestLines
-- DROPS completed questlines — so a live scan gives an empty bar on a character
-- who has finished the zone (i.e. most players' main). v1.14.0 tried to persist
-- a discovered set to work around that; it failed exactly there, because a
-- completed main never discovers anything to persist.
--
-- The denominator therefore comes from ChainGuide's AUTHORED routing table
-- (ns.QUESTLINE_ROUTING), which lists every questline in a zone regardless of
-- completion — that table exists for precisely this reason (see
-- Data/QuestChains/_QuestLineRouting.lua). Flow:
--   1. zoneRoot() → the player's current Zone-type uiMapID.
--   2. _ResolveCategory() maps that uiMapID to a ChainGuide category. Resolution
--      is locale-safe: a learned account-wide uiMapID→catID cache first, then an
--      English name match, then a majority vote of any live-available questlines
--      against the routing table (which also seeds the cache for other locales /
--      future completed visits).
--   3. The category's routed questlines ARE the denominator. Each questline's
--      quest list comes from C_QuestLine.GetQuestLineQuests (static game data,
--      NOT completion-filtered), cached account-wide in qlQuests with an async
--      retry for lists Blizzard hasn't loaded yet.
--   4. Completion is PER-CHARACTER, computed LIVE (IsQuestFlaggedCompleted),
--      never persisted. So every toon sees its own count against the same
--      complete, stable denominator — instantly, no discovery, no cross-char
--      dependency, no hoops.
--
-- Account-wide caches in ns.db.global.zoneProgress:
--   * qlQuests[questLineID] = { questID, ... }   -- static quest lists, monotonic
--   * zoneCat[uiMapID]      = catID              -- learned zone→category map
--
-- The whole subsystem is gated behind db.profile.tracker.showZoneProgressBar
-- (OFF by default). Every event handler and Render early-returns when the flag
-- is off, so there is zero ongoing cost for users who don't opt in.
--
-- Coverage = zones present in the routing data (current-content Midnight zones).
-- An unresolved zone hides the bar; "/eqs zonebar debug" prints the unresolved
-- uiMapID so a new zone can be added to routing.

local _, ns = ...

local ZP = ns:RegisterSubsystem("TrackerZoneProgress", {})

local RECOMPUTE_KEY   = "eq.zoneprogress.recompute"
local ZONE_KEY        = "eq.zoneprogress.zone"
local DEBOUNCE_DELAY  = 0.25
local RETRY_DELAY     = 0.3        -- mirrors ChainGuide EnsureChainItems
local MAX_HOPS        = 5          -- parent-map climb safety cap

-- Bar visuals mirror the proven StatusBar widget in Modules/Tracker/Scenario.lua.
local BAR_H       = 12
local ROW_PAD_TOP = 2
local ROW_PAD_BOT = 4

ZP._countCache     = {}   -- [zoneRootID] = { completed=, total=, name= }
ZP._retryScheduled = {}   -- [questLineID] = true (one in-flight retry per line)
ZP._seen           = {}   -- reused scratch for union dedupe (wipe()'d each Recompute)
ZP._scratchMaps    = {}   -- reused scratch for the map + children list
ZP._voteTally      = {}   -- reused scratch for category majority vote

-- ── small accessors ──────────────────────────────────────────────────────

local function DBsub() return ns:GetSubsystem("DB") end

local function enabled()
    local db = DBsub()
    local p = db and db.db and db.db.profile and db.db.profile.tracker
    return (p and p.showZoneProgressBar == true) or false
end

-- "tracker" (a section on the on-screen tracker) or "floating" (standalone
-- movable frame). Defaults to floating.
local function location()
    local db = DBsub()
    local p = db and db.db and db.db.profile and db.db.profile.tracker
    return (p and p.zoneProgressLocation) or "floating"
end

-- Floating-frame state sub-table (position / scale / lock).
local function barState()
    local db = DBsub()
    local p = db and db.db and db.db.profile and db.db.profile.tracker
    if not p then return nil end
    p.zoneProgressBar = p.zoneProgressBar or {}
    return p.zoneProgressBar
end

-- Account-wide questline -> quest-list cache (static game data).
local function qlQuestStore()
    local db = DBsub()
    if not (db and db.db and db.db.global) then return nil end
    local zp = db.db.global.zoneProgress
    if not zp then zp = {}; db.db.global.zoneProgress = zp end
    zp.qlQuests = zp.qlQuests or {}
    return zp.qlQuests
end

-- Account-wide learned uiMapID -> ChainGuide catID map. Locale-independent
-- (keyed by mapID, valued by our own category constant), so a localized client
-- that once saw available questlines in a zone keeps resolving it after the
-- character completes the zone — and every other character reuses it.
local function zoneCatStore()
    local db = DBsub()
    if not (db and db.db and db.db.global) then return nil end
    local zp = db.db.global.zoneProgress
    if not zp then zp = {}; db.db.global.zoneProgress = zp end
    zp.zoneCat = zp.zoneCat or {}
    return zp.zoneCat
end

-- Case-insensitive zone-name -> ChainGuide catID. Works out of the box on an
-- English client (category names are authored in English); other locales fall
-- back to the live majority vote in _VoteCategory. Mirrors ChainGuide's own
-- matchCategoryByName: exact match wins, else substring either direction.
local function categoryByName(name)
    if not name or name == "" then return nil end
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    if not (Database and Database.categories) then return nil end
    local lower = name:lower()
    for id, cat in pairs(Database.categories) do
        if (cat.name or ""):lower() == lower then return id end
    end
    for id, cat in pairs(Database.categories) do
        local cn = (cat.name or ""):lower()
        if cn ~= "" and (lower:find(cn, 1, true) or cn:find(lower, 1, true)) then
            return id
        end
    end
    return nil
end

-- uiMapID -> ChainGuide catID via the category's authored mapIDs (seeded in
-- Data/QuestChains/_Index.lua) plus any per-character /eqs discover overrides.
-- Locale-INDEPENDENT and works on a completed main, so this is the strongest
-- signal — tried before name matching.
local function categoryByMapID(rootID)
    if not rootID then return nil end
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    if not (Database and Database.categories) then return nil end
    -- Per-character override list (cg.zoneMapIDs[catID] = { mapID, ... }), the
    -- same table /eqs discover appends to for the chain guide.
    local db = DBsub()
    local overrides = db and db.db and db.db.profile and db.db.profile.chainGuide
                      and db.db.profile.chainGuide.zoneMapIDs
    for id, cat in pairs(Database.categories) do
        if cat.mapID == rootID then return id end
        local mids = cat.mapIDs
        if type(mids) == "table" then
            for i = 1, #mids do if mids[i] == rootID then return id end end
        end
        local ov = overrides and overrides[id]
        if type(ov) == "table" then
            for i = 1, #ov do if ov[i] == rootID then return id end end
        elseif type(ov) == "number" and ov == rootID then
            return id
        end
    end
    return nil
end

-- Climb parentMapID until the first Zone-type ancestor, so a player standing
-- in a building/city sub-map (Micro/Dungeon) resolves to the surrounding zone
-- and sees one consistent bar. Returns rootID, name (nil if no map / instanced
-- area where GetBestMapForUnit gives nothing useful).
local function zoneRoot()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or mapID <= 0 then return nil end
    local id = mapID
    for _ = 1, MAX_HOPS do
        local info = C_Map.GetMapInfo(id)
        if not info then break end
        if info.mapType == Enum.UIMapType.Zone then
            return id, info.name
        end
        local parent = info.parentMapID
        if not parent or parent <= 0 then break end
        id = parent
    end
    -- No Zone ancestor (orphan/instanced map): fall back to the raw map.
    local info = C_Map.GetMapInfo(mapID)
    return mapID, info and info.name or nil
end

-- ── discovery + quest-list caching ─────────────────────────────────────────

-- Cache a questline's quest list (account-wide, monotonic). An empty result
-- means Blizzard hasn't loaded the data yet; schedule a single retry + a
-- recompute, exactly like ChainGuide's EnsureChainItems. Guarded so a flood of
-- renders can't stack duplicate timers.
function ZP:EnsureQuests(qlID)
    if not (qlID and C_QuestLine and C_QuestLine.GetQuestLineQuests) then return end
    local store = qlQuestStore()
    if not store then return end

    local quests = C_QuestLine.GetQuestLineQuests(qlID)
    if not quests or #quests == 0 then
        if not self._retryScheduled[qlID] then
            self._retryScheduled[qlID] = true
            C_Timer.After(RETRY_DELAY, function()
                self._retryScheduled[qlID] = nil
                self:EnsureQuests(qlID)
                self:ScheduleRecompute()   -- a newly-loaded list changes the count
            end)
        end
        return
    end

    -- Monotonic: never shrink a cached list. A partial async re-fetch could
    -- return fewer quests and wobble the denominator between sessions.
    local existing = store[qlID]
    if not existing or #quests >= #existing then
        store[qlID] = quests
    end
end

-- ── zone → category resolution ──────────────────────────────────────────────

-- Lazily-built reverse index of the routing table: catID -> { questLineID, ... }.
-- Rebuilt only if the routing table identity changes (a data patch), so it costs
-- one pass per session.
function ZP:_CategoryQuestLines(catID)
    local routing = ns.QUESTLINE_ROUTING
    if not (routing and catID) then return nil end
    if self._catIndexFor ~= routing then
        local idx = {}
        for qlID, entry in pairs(routing) do
            local c = (type(entry) == "table") and entry.cat or entry
            if c then
                local list = idx[c]
                if not list then list = {}; idx[c] = list end
                list[#list + 1] = qlID
            end
        end
        self._catIndex    = idx
        self._catIndexFor = routing
    end
    return self._catIndex[catID]
end

-- Majority vote: scan live-available questlines on this zone (and child maps)
-- and return the category most of them route to. Locale-independent (uses
-- questline IDs, not names). A character who has COMPLETED the zone gets nothing
-- here — which is why _ResolveCategory tries the cache and the name match first.
function ZP:_VoteCategory(rootID)
    if not (rootID and C_QuestLine and C_QuestLine.GetAvailableQuestLines and ns.QUESTLINE_ROUTING) then
        return nil
    end
    local maps = self._scratchMaps
    wipe(maps)
    maps[1] = rootID
    if C_Map and C_Map.GetMapChildrenInfo then
        local kids = C_Map.GetMapChildrenInfo(rootID, nil, true)
        if kids then
            for i = 1, #kids do
                if kids[i] and kids[i].mapID then maps[#maps + 1] = kids[i].mapID end
            end
        end
    end

    local routing = ns.QUESTLINE_ROUTING
    local tally = self._voteTally
    wipe(tally)
    local bestCat, bestN = nil, 0
    for m = 1, #maps do
        local lines = C_QuestLine.GetAvailableQuestLines(maps[m])
        if lines then
            for i = 1, #lines do
                local info = lines[i]
                local qlID = info and info.questLineID
                local entry = qlID and routing[qlID]
                local c = entry and ((type(entry) == "table") and entry.cat or entry)
                if c then
                    local n = (tally[c] or 0) + 1
                    tally[c] = n
                    if n > bestN then bestN, bestCat = n, c end
                end
            end
        end
    end
    return bestCat
end

-- Locale-independent fallback: majority-vote a zone's PREVIOUSLY discovered
-- questlines against the routing table. The discovery may have been captured on
-- another character (or an earlier build) while the questlines were still
-- available, so this resolves a completed main with zero live data. Reads the
-- interim account-wide set (global.zoneProgress.discovered) and the legacy
-- per-character set (char.zoneProgress.questlines), both written by v1.14.0/the
-- discovery-based builds.
function ZP:_CategoryFromHistory(rootID)
    local routing = ns.QUESTLINE_ROUTING
    if not (rootID and routing) then return nil end
    local db = DBsub()
    if not db then return nil end

    local tally = self._voteTally
    wipe(tally)
    local bestCat, bestN = nil, 0
    local function tallySet(set)
        if type(set) ~= "table" then return end
        for qlID in pairs(set) do
            local entry = routing[qlID]
            local c = entry and ((type(entry) == "table") and entry.cat or entry)
            if c then
                local n = (tally[c] or 0) + 1
                tally[c] = n
                if n > bestN then bestN, bestCat = n, c end
            end
        end
    end

    local g = db.db and db.db.global and db.db.global.zoneProgress
    if g and g.discovered then tallySet(g.discovered[rootID]) end
    local ch = db.char and db.char.zoneProgress and db.char.zoneProgress.questlines
    if ch then tallySet(ch[rootID]) end
    return bestCat
end

-- Resolve a zone-root uiMapID to a ChainGuide category, caching any hit
-- account-wide. Priority, strongest signal first:
--   1. learned cache (account-wide, locale-independent),
--   2. authored category mapIDs (locale-independent, works on a completed main),
--   3. English zone-name match,
--   4. previously-discovered questlines (locale-independent, completed-safe),
--   5. live majority vote of currently-available questlines.
function ZP:_ResolveCategory(rootID, name)
    if not rootID then return nil end
    local cache = zoneCatStore()
    if cache and cache[rootID] then return cache[rootID] end

    local catID = categoryByMapID(rootID)
                  or categoryByName(name)
                  or self:_CategoryFromHistory(rootID)
                  or self:_VoteCategory(rootID)
    if catID and cache then cache[rootID] = catID end
    return catID
end

-- ── counting ───────────────────────────────────────────────────────────────

-- Count unique quests across this zone's AUTHORED questlines (from routing);
-- completed = those flagged complete for THIS character. Allocation-free
-- (reused _seen scratch + integer counters). Result cached per zone root; a
-- nil category (zone not in routing) yields total 0 → the bar hides.
function ZP:Recompute(rootID, name)
    if not rootID then return end
    local store = qlQuestStore()
    if not store then return end

    local catID = self:_ResolveCategory(rootID, name)
    local lines = catID and self:_CategoryQuestLines(catID)

    local seen = self._seen
    wipe(seen)
    local total, completed = 0, 0

    if lines then
        local flagged = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
        for li = 1, #lines do
            local qlID  = lines[li]
            local quests = store[qlID]
            if not quests then
                self:EnsureQuests(qlID)        -- async load; retry re-recomputes
                quests = store[qlID]
            end
            if quests then
                for i = 1, #quests do
                    local qid = quests[i]
                    if qid and not seen[qid] then
                        seen[qid] = true
                        total = total + 1
                        if flagged and flagged(qid) then
                            completed = completed + 1
                        end
                    end
                end
            end
        end
    end

    local cache = self._countCache[rootID]
    if not cache then cache = {}; self._countCache[rootID] = cache end
    cache.total     = total
    cache.completed = completed
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(rootID)
    cache.name = (info and info.name) or name or cache.name

    if total == 0 and not catID then self:_DebugUnresolved(rootID, name) end
end

-- Optional chat hint (off unless "/eqs zonebar debug" set the flag) naming the
-- uiMapID we couldn't map to routing, so a new zone can be added to the table.
function ZP:_DebugUnresolved(rootID, name)
    if not ns.zoneBarDebug then return end
    if not self._debugSeen then self._debugSeen = {} end
    if self._debugSeen[rootID] then return end
    self._debugSeen[rootID] = true
    print(("|cffEBB706EQ ZoneBar:|r no routing for zone |cffffffff%s|r (uiMapID %d). Add it to _QuestLineRouting.lua.")
        :format(name or "?", rootID))
end

-- "/eqs zonebar" report: current zone, the category it resolved to, and the
-- live count. Forces a fresh Recompute so the numbers are current.
function ZP:PrintStatus()
    local rootID, name = zoneRoot()
    if not rootID then
        print("|cffEBB706EQ ZoneBar:|r no current zone (instanced / no map).")
        return
    end
    self:Recompute(rootID, name)
    local catID = self:_ResolveCategory(rootID, name)
    local cat
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    if catID and Database and Database.categories then cat = Database.categories[catID] end
    local c = self._countCache[rootID]
    print(("|cffEBB706EQ ZoneBar:|r zone |cffffffff%s|r (uiMapID %d) → %s, %d/%d complete.")
        :format(name or "?", rootID,
                cat and ("category |cffffffff" .. (cat.name or "?") .. "|r")
                     or "|cffff5555no routing match|r",
                (c and c.completed) or 0, (c and c.total) or 0))
end

-- Debounced "recompute current zone + repaint", shared by the quest events and
-- the questline-load retry. Trailing-edge is correct: quest-complete flags
-- settle after the event fires.
function ZP:ScheduleRecompute()
    if not enabled() then return end
    local Events = ns:GetSubsystem("Events")
    if not Events then return end
    if not self._recomputeThunk then
        self._recomputeThunk = function()
            local rootID, name = zoneRoot()
            if rootID then ZP:Recompute(rootID, name) end
            ZP:_Repaint()
        end
    end
    Events:Debounce(RECOMPUTE_KEY, DEBOUNCE_DELAY, self._recomputeThunk)
end

-- Repaint whichever surface is active: the tracker section and/or the floating
-- frame. Both are cheap and self-gating, so calling both is fine.
function ZP:_Repaint()
    local Tracker = ns:GetSubsystem("Tracker")
    if Tracker and Tracker.Refresh then Tracker:Refresh() end
    self:UpdateFrame()
end

-- ── lifecycle ───────────────────────────────────────────────────────────────

function ZP:OnEnable()
    local Events = ns:GetSubsystem("Events")
    if not Events then return end

    self._zoneThunk = function()
        if not enabled() then return end
        local rootID, name = zoneRoot()
        if not rootID then return end
        ZP:Recompute(rootID, name)
        ZP:_Repaint()
    end

    local function onZone()
        if not enabled() then return end
        Events:Debounce(ZONE_KEY, DEBOUNCE_DELAY, ZP._zoneThunk)
    end
    local function onQuest()
        if not enabled() then return end
        ZP:ScheduleRecompute()
    end

    Events:On("ZONE_CHANGED_NEW_AREA", onZone)
    Events:On("PLAYER_ENTERING_WORLD", onZone)
    Events:On("QUEST_TURNED_IN",       onQuest)
    Events:On("QUEST_REMOVED",         onQuest)

    -- The denominator is authored (routing), so a completed main no longer needs
    -- a live scan. But on a localized client the zone→category resolution may
    -- still fall back to a majority vote of live-available questlines, and
    -- GetAvailableQuestLines is ASYNC (empty on the first call, delivered later
    -- via QUESTLINE_UPDATE). Re-resolve when that data lands so the cache learns
    -- the mapping. enabled()-gated, so it's free when the feature is off.
    Events:On("QUESTLINE_UPDATE", onZone)
end

-- Called by the options checkbox so toggling ON paints the bar immediately
-- (rather than waiting for the next zone change), and toggling OFF drops the
-- cached counts so no stale bar can linger.
function ZP:SetEnabled(on)
    if on then
        local rootID, name = zoneRoot()
        if rootID then
            self:Recompute(rootID, name)
        end
    else
        wipe(self._countCache)
        if self.frame then self.frame:Hide() end
    end
    self:_Repaint()
end

-- ── standalone movable frame ─────────────────────────────────────────────────
-- Used when zoneProgressLocation == "floating": a small backdrop frame the
-- user can drag anywhere, scale (Appearance tab), and lock (right-click menu).
-- Created lazily — users who never enable floating mode pay nothing.

local FRAME_W       = 220
local FRAME_BAR_H   = 12

-- Apply saved position, scale, and lock chrome. Unlocked shows a brand-red
-- border as a "you can grab this" affordance; locked hides it.
function ZP:ApplySettings()
    local f = self.frame
    if not f then return end
    local st = barState() or {}
    f:ClearAllPoints()
    f:SetPoint(st.point or "CENTER", UIParent, st.relPoint or st.point or "CENTER",
               st.x or 0, st.y or 220)
    f:SetScale(st.scale or 1.0)

    -- Background fill (the dark panel behind the bar). Slightly more opaque when
    -- unlocked so the grab target reads clearly. Off → fully transparent.
    if st.showBackground == false then
        f:SetBackdropColor(0, 0, 0, 0)
    else
        f:SetBackdropColor(0, 0, 0, st.locked and 0.40 or 0.55)
    end

    -- Border. Shown whenever the Border option is on, in the user's chosen color
    -- (default brand red #6D0501). Off → hidden in every state. Previously the
    -- border was a lock affordance (hidden when locked); the colour option
    -- supersedes that so a picked colour is actually visible during normal locked
    -- use. The background-alpha shift above still hints at lock state.
    if st.showBorder == false then
        f:SetBackdropBorderColor(0, 0, 0, 0)
    else
        local bc = st.borderColor
        if bc then f:SetBackdropBorderColor(bc.r, bc.g, bc.b, bc.a or 1)
        else       f:SetBackdropBorderColor(0.635, 0.000, 0.039, 1) end   -- brand red #a2000a
    end
end

function ZP:_SavePosition()
    local f, st = self.frame, barState()
    if not (f and st) then return end
    local point, _, relPoint, x, y = f:GetPoint()
    st.point, st.relPoint, st.x, st.y = point, relPoint, x, y
end

function ZP:_ContextMenu()
    if not (MenuUtil and MenuUtil.CreateContextMenu and self.frame) then return end
    MenuUtil.CreateContextMenu(self.frame, function(_, root)
        root:CreateTitle(ns.L["Zone Progress Bar"])
        local st = barState() or {}
        root:CreateButton(st.locked and ns.L["Unlock (allow moving)"] or ns.L["Lock position"],
            function()
                local s = barState(); if s then s.locked = not s.locked end
                ZP:ApplySettings()
            end)
        root:CreateButton(ns.L["Reset position"], function()
            local s = barState()
            if s then s.point, s.relPoint, s.x, s.y = "CENTER", "CENTER", 0, 220 end
            ZP:ApplySettings()
        end)
        root:CreateDivider()
        root:CreateButton(ns.L["Cancel"], function() end)
    end)
end

function ZP:_AcquireFrame()
    if self.frame then return self.frame end
    local f = CreateFrame("Frame", "EverythingQuestsZoneProgressBar", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W, 38)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s)
        local st = barState()
        if st and st.locked then return end
        s:StartMoving()
    end)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        ZP:_SavePosition()
    end)
    f:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then ZP:_ContextMenu() end
    end)

    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 6, -4)
    f.title:SetJustifyH("LEFT")
    f.title:SetTextColor(0.93, 0.32, 0.10)        -- section-header color

    f.count = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.count:SetPoint("TOPRIGHT", -6, -5)
    f.count:SetTextColor(0.92, 0.72, 0.02)

    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetPoint("BOTTOMLEFT", 6, 5)
    bar:SetPoint("BOTTOMRIGHT", -6, 5)
    bar:SetHeight(FRAME_BAR_H)
    bar:SetMinMaxValues(0, 100)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.26, 0.42, 1.0)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0.04, 0.07, 0.18, 0.9)
    bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.label:SetPoint("CENTER")
    f.bar = bar

    self.frame = f
    self:ApplySettings()
    return f
end

-- Refresh the floating frame: show only when enabled AND floating AND the
-- current zone has data; otherwise hide. Reads the same cached counts the
-- tracker section uses.
function ZP:UpdateFrame()
    local show = enabled() and location() == "floating"
    if not show then
        if self.frame then self.frame:Hide() end
        return
    end
    local rootID, zname = zoneRoot()
    if not rootID then
        if self.frame then self.frame:Hide() end
        return
    end
    local cache = self._countCache[rootID]
    if not cache then
        self:Recompute(rootID, zname)
        cache = self._countCache[rootID]
    end
    local total = (cache and cache.total) or 0
    local f = self:_AcquireFrame()
    if total <= 0 then f:Hide(); return end
    local completed = (cache and cache.completed) or 0

    local pct = (completed / total) * 100
    f.title:SetText((cache and cache.name) or zname or "")
    f.count:SetText(completed .. "/" .. total)
    f.bar:SetValue(pct)
    f.bar.label:SetText(("%d%%"):format(math.floor(pct + 0.5)))

    -- Header + count text colors: user overrides (Appearance → Zone Bar) or the
    -- built-in defaults (section-header red / gold).
    local st = barState() or {}
    local hc = st.headerColor
    if hc then f.title:SetTextColor(hc.r, hc.g, hc.b, hc.a or 1)
    else       f.title:SetTextColor(0.93, 0.32, 0.10) end
    local cc = st.countColor
    if cc then f.count:SetTextColor(cc.r, cc.g, cc.b, cc.a or 1)
    else       f.count:SetTextColor(0.92, 0.72, 0.02) end

    -- Font: the bar's own typeface override (nil = follow the tracker font);
    -- size and outline still come from the tracker's settings.
    local Media = ns:GetSubsystem("Media")
    if Media and Media.ApplyTrackerFont then
        local bf = st.font
        Media:ApplyTrackerTitleFont(f.title, bf)
        Media:ApplyTrackerFont(f.count, -2, bf)
        Media:ApplyTrackerFont(f.bar.label, -2, bf)
    end

    f:Show()
end

-- Option-tab setters.
function ZP:SetLocation(loc)
    local db = DBsub()
    if db and db.db then db.db.profile.tracker.zoneProgressLocation = loc end
    self:_Repaint()
end

function ZP:SetScale(v)
    local st = barState()
    if st then st.scale = v end
    self:ApplySettings()
end

function ZP:SetLocked(b)
    local st = barState()
    if st then st.locked = b end
    self:ApplySettings()
end

-- Live-apply an appearance change from the Appearance tab. ApplySettings repaints
-- the backdrop (border/background); UpdateFrame repaints text/font/colors. Both
-- no-op safely when the floating frame hasn't been built yet.
function ZP:RefreshAppearance()
    self:ApplySettings()
    self:UpdateFrame()
end

function ZP:SetShowBorder(b)
    local st = barState(); if st then st.showBorder = b and true or false end
    self:RefreshAppearance()
end

function ZP:SetShowBackground(b)
    local st = barState(); if st then st.showBackground = b and true or false end
    self:RefreshAppearance()
end

-- nil c → fall back to the default brand red. Applied via ApplySettings (backdrop).
function ZP:SetBorderColor(c)
    local st = barState(); if st then st.borderColor = c end
    self:ApplySettings()
end

-- name == "" / nil → follow the tracker font; otherwise an LSM font name.
function ZP:SetBarFont(name)
    local st = barState(); if st then st.font = (name ~= "" and name) or nil end
    self:UpdateFrame()
end

function ZP:SetHeaderColor(c)
    local st = barState(); if st then st.headerColor = c end
    self:UpdateFrame()
end

function ZP:SetCountColor(c)
    local st = barState(); if st then st.countColor = c end
    self:UpdateFrame()
end

-- ── header + render ─────────────────────────────────────────────────────────

-- Frame.lua's render loop calls this for the "zoneprogress" section header to
-- show the live zone name + "<done>/<total>" instead of the static title.
function ZP:HeaderInfo()
    local rootID, name = zoneRoot()
    if not rootID then return nil end
    local c = self._countCache[rootID]
    if not c then return name end
    return (c.name or name), (c.completed or 0) .. "/" .. (c.total or 0)
end

-- Lazily build the single StatusBar (one zone bar, not a pooled list). Copies
-- the widget recipe from Modules/Tracker/Scenario.lua:122-153.
function ZP:_AcquireBar(parent)
    local bar = self.bar
    if bar then
        if bar:GetParent() ~= parent then bar:SetParent(parent) end
        return bar
    end
    bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(BAR_H)
    bar:SetMinMaxValues(0, 100)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.26, 0.42, 1.0)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0.04, 0.07, 0.18, 0.9)

    bar.border = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    bar.border:SetPoint("TOPLEFT", -1, 1)
    bar.border:SetPoint("BOTTOMRIGHT", 1, -1)
    bar.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    bar.border:SetBackdropBorderColor(0, 0, 0, 0.9)

    bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.label:SetPoint("CENTER", bar, "CENTER", 0, 0)

    self.bar = bar
    return bar
end

-- Allocation-free "nothing to show" return (also hides a previously-shown bar).
function ZP:_hideBar()
    if self.bar then self.bar:Hide() end
    return 0, 0
end

-- Returns (height, count, total). count>0 makes Frame.lua show the header;
-- returning 0 auto-hides the whole section (no zone / no data / disabled).
function ZP:Render(content, contentWidth, yStart, collapsed)
    if not enabled() then return self:_hideBar() end
    -- Only draw the tracker section when the user chose the tracker location;
    -- the floating frame handles the other case (Frame.lua's sectionVisible
    -- gates this too, but be defensive).
    if location() ~= "tracker" then return self:_hideBar() end

    local rootID, name = zoneRoot()
    if not rootID then return self:_hideBar() end

    local cache = self._countCache[rootID]
    if not cache then
        -- First paint for this zone with the feature on: resolve + count now
        -- so the bar appears on this pass (e.g. right after enabling).
        self:Recompute(rootID, name)
        cache = self._countCache[rootID]
    end

    local total = (cache and cache.total) or 0
    if total <= 0 then return self:_hideBar() end
    local completed = (cache and cache.completed) or 0

    -- Collapsed: keep the header (count>0 so it stays clickable to expand) but
    -- draw no bar body.
    if collapsed then
        if self.bar then self.bar:Hide() end
        return 0, 1, total
    end

    local bar = self:_AcquireBar(content)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -(yStart + ROW_PAD_TOP))
    bar:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(yStart + ROW_PAD_TOP))

    local pct = (completed / total) * 100
    bar:SetValue(pct)
    bar.label:SetText(("%d%%"):format(math.floor(pct + 0.5)))

    local Media = ns:GetSubsystem("Media")
    if Media and Media.ApplyTrackerFont then Media:ApplyTrackerFont(bar.label, -2) end

    bar:Show()
    return ROW_PAD_TOP + BAR_H + ROW_PAD_BOT, 1, total
end
