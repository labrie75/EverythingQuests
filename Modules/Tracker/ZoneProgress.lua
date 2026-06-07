-- Modules/Tracker/ZoneProgress.lua
-- Optional per-zone quest progress bar for the on-screen tracker. Shows the
-- player's "lifetime" questline completion for their current zone, e.g.
--   Eversong Woods          12 / 47
--   [#########----------------------]
--
-- WHY THIS IS BUILT THE WAY IT IS:
-- WoW has no API for "all quests in a zone". The only source is
-- C_QuestLine.GetAvailableQuestLines(uiMapID), which DROPS completed
-- questlines (so a naive live count has a shrinking denominator as you finish
-- content) and repeats each questline once per entry-point quest. We therefore
-- PERSIST discovery so the total stays stable:
--   * ns.db.global.zoneProgress.qlQuests[questLineID] = { questID, ... }
--       a questline's quest list. Static game data, identical for every
--       character, so it is cached ACCOUNT-WIDE. Stored MONOTONICALLY (never
--       replaced by a shorter async re-fetch) so the denominator never wobbles.
--   * DB.char.zoneProgress.questlines[zoneRootID] = { [questLineID] = true }
--       the discovered SET that drives the denominator. PER-CHARACTER: a
--       faction/class/race-locked questline discovered on one alt must not
--       inflate another alt's total forever.
-- Completion is per-character and computed LIVE (IsQuestFlaggedCompleted),
-- never persisted.
--
-- The whole subsystem is gated behind db.profile.tracker.showZoneProgressBar
-- (OFF by default). Every event handler and Render early-returns when the flag
-- is off, so there is zero ongoing cost for users who don't opt in.
--
-- Coverage is APPROXIMATE: it only knows questlines this character has seen
-- available in the zone (and only questline quests). Best in current-content
-- zones the player actually quests through; documented in the option tooltip.

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

-- Per-character discovered-questline set, keyed by zone-root mapID.
local function discoveredStore()
    local db = DBsub()
    if not (db and db.char) then return nil end
    db.char.zoneProgress = db.char.zoneProgress or {}
    db.char.zoneProgress.questlines = db.char.zoneProgress.questlines or {}
    return db.char.zoneProgress.questlines
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

-- Query the API for questlines available on `rootID` (and its descendant
-- sub-maps) and add any new ones to this character's discovered set, caching
-- each questline's quest list. Deduping is implicit: questLineIDs are keys.
function ZP:Discover(rootID)
    if not (rootID and C_QuestLine and C_QuestLine.GetAvailableQuestLines) then return end
    local set = discoveredStore()
    if not set then return end
    local zoneSet = set[rootID]
    if not zoneSet then zoneSet = {}; set[rootID] = zoneSet end

    local maps = self._scratchMaps
    wipe(maps)
    maps[1] = rootID
    if C_Map and C_Map.GetMapChildrenInfo then
        local kids = C_Map.GetMapChildrenInfo(rootID, nil, true)   -- all descendants
        if kids then
            for i = 1, #kids do
                if kids[i] and kids[i].mapID then maps[#maps + 1] = kids[i].mapID end
            end
        end
    end

    for m = 1, #maps do
        local lines = C_QuestLine.GetAvailableQuestLines(maps[m])
        if lines then
            for i = 1, #lines do
                local info = lines[i]
                local qlID = info and info.questLineID
                if qlID and not info.isHidden then
                    zoneSet[qlID] = true
                    self:EnsureQuests(qlID)
                end
            end
        end
    end
end

-- ── counting ───────────────────────────────────────────────────────────────

-- Count unique quests across this zone's discovered questlines; completed =
-- those flagged complete for THIS character. Allocation-free (reused _seen
-- scratch + integer counters). Result cached per zone root.
function ZP:Recompute(rootID)
    if not rootID then return end
    local set   = discoveredStore()
    local store = qlQuestStore()
    if not (set and store) then return end

    local seen = self._seen
    wipe(seen)
    local total, completed = 0, 0

    local zoneSet = set[rootID]
    if zoneSet then
        local flagged = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
        for qlID in pairs(zoneSet) do
            local quests = store[qlID]
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
    cache.name = (info and info.name) or cache.name
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
            local rootID = zoneRoot()
            if rootID then ZP:Recompute(rootID) end
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
        local rootID = zoneRoot()
        if not rootID then return end
        ZP:Discover(rootID)
        ZP:Recompute(rootID)
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
end

-- Called by the options checkbox so toggling ON paints the bar immediately
-- (rather than waiting for the next zone change), and toggling OFF drops the
-- cached counts so no stale bar can linger.
function ZP:SetEnabled(on)
    if on then
        local rootID = zoneRoot()
        if rootID then
            self:Discover(rootID)
            self:Recompute(rootID)
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
    if st.locked then
        f:SetBackdropBorderColor(0, 0, 0, 0)
        f:SetBackdropColor(0, 0, 0, 0.40)
    else
        f:SetBackdropBorderColor(0.427, 0.020, 0.004, 1)   -- brand red #6D0501
        f:SetBackdropColor(0, 0, 0, 0.55)
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
        self:Discover(rootID)
        self:Recompute(rootID)
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

    local Media = ns:GetSubsystem("Media")
    if Media and Media.ApplyTrackerFont then
        Media:ApplyTrackerFont(f.title, 0)
        Media:ApplyTrackerFont(f.count, -2)
        Media:ApplyTrackerFont(f.bar.label, -2)
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

    local rootID = zoneRoot()
    if not rootID then return self:_hideBar() end

    local cache = self._countCache[rootID]
    if not cache then
        -- First paint for this zone with the feature on: discover + count now
        -- so the bar appears on this pass (e.g. right after enabling).
        self:Discover(rootID)
        self:Recompute(rootID)
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
