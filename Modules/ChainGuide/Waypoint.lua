-- Modules/ChainGuide/Waypoint.lua
-- "Get Directions" for a quest, from the Chain Guide or the tracker menu.
--
-- Two cases, because they want opposite things:
--
-- A. Quest is in your log (active OR complete). Blizzard already tracks its
--    live objective — or, once complete, its TURN-IN — and draws that POI on
--    the map. We just super-track the quest and hand navigation to Blizzard.
--    We must NOT drop our own waypoint here: our coords point at the quest
--    GIVER (where it was picked up), which is the wrong place mid-quest or at
--    hand-in, and SetUserWaypoint would also hijack Blizzard's super-track.
--
-- B. Quest is NOT in your log (a future quest browsed in the Chain Guide).
--    Blizzard can't navigate to a quest you don't have, so we resolve the
--    quest-GIVER location ("where do I go to pick this up"), best source first:
--      1. Cache       — prior resolves + passively harvested giver coords.
--                       Account-wide, survives sessions.
--      2. Coord table — the bundled quest-giver coordinate table
--                       (ns.CHAINGUIDE_QUEST_COORDS); broad coverage.
--      3. Questline API — C_QuestLine.GetQuestLineInfo gives the same map
--                       position WoW uses for questline map dots.
--    …then drop a waypoint (TomTom if present, else Blizzard's user waypoint)
--    and open the world map there.

local _, ns = ...

local W = ns:RegisterSubsystem("ChainGuideWaypoint", {})

-- ─── Coordinate cache ──────────────────────────────────────────────────
-- Stored on the account-wide chain cache so it's shared across characters
-- (a quest giver is in the same place for everyone).
local function cacheTable()
    local DB = ns:GetSubsystem("DB")
    if not (DB and DB.chainCache) then return nil end
    DB.chainCache.questCoords = DB.chainCache.questCoords or {}
    return DB.chainCache.questCoords
end

local function cacheGet(questID)
    local t = cacheTable()
    local e = t and t[questID]
    if e and e.m and e.x and e.y then
        e.lastSeen = time()   -- last-used stamp keeps actively-used coords fresh against the prune
        return e.m, e.x, e.y
    end
end

local function cacheSet(questID, mapID, x, y)
    if not (questID and mapID and x and y) then return end
    local t = cacheTable()
    if t then t[questID] = { m = mapID, x = x, y = y, lastSeen = time() } end
end

-- Prune coordinate entries not used within `ttl` seconds. Coords are always
-- re-derivable (static table → C_QuestLine → GetNextWaypoint → re-harvest on
-- the next accept), so dropping a stale entry is invisible to the player. A
-- legacy entry with no lastSeen is stamped on this pass (grace) rather than
-- wiped, so a player's hand-harvested coords aren't cleared wholesale the first
-- time the prune runs after updating. Called from DB:MaybePruneChainCache
-- (throttled, off the login spike). time() is epoch — persists across reboots.
function W:PruneStaleCoords(now, ttl)
    local t = cacheTable()
    if not t then return 0 end
    local removed = 0
    for questID, e in pairs(t) do
        if type(e) == "table" then
            if not e.lastSeen then
                e.lastSeen = now
            elseif now - e.lastSeen > ttl then
                t[questID] = nil
                removed = removed + 1
            end
        end
    end
    return removed
end

-- ─── Candidate maps for a chain ────────────────────────────────────────
-- C_QuestLine.GetQuestLineInfo needs the uiMapID the quest sits on. We try
-- the player's current map first (usually right when questing the zone),
-- then the chain category's seed/override maps.
local _cand = {}
local function candidateMaps(chain)
    wipe(_cand)
    local seen = {}
    local function push(m)
        if m and m > 0 and not seen[m] then seen[m] = true; _cand[#_cand + 1] = m end
    end

    if C_Map and C_Map.GetBestMapForUnit then
        push(C_Map.GetBestMapForUnit("player"))
    end

    local catID = chain and chain.category
    if catID then
        local Database = ns:GetSubsystem("ChainGuideDatabase")
        local cat = Database and Database.categories[catID]
        if cat then
            if cat.mapIDs then for _, m in ipairs(cat.mapIDs) do push(m) end end
            push(cat.mapID)
        end
        local DB = ns:GetSubsystem("DB")
        local ov = DB and DB.db and DB.db.profile and DB.db.profile.chainGuide
                   and DB.db.profile.chainGuide.zoneMapIDs
                   and DB.db.profile.chainGuide.zoneMapIDs[catID]
        if type(ov) == "number" then push(ov)
        elseif type(ov) == "table" then for _, m in ipairs(ov) do push(m) end end
    end
    return _cand
end

-- ─── Resolve questID → mapID, x, y ─────────────────────────────────────
-- Resolves the quest-GIVER location only — used for quests NOT in the log
-- (case B). For a quest you already have, GoTo super-tracks it instead of
-- calling this, so the live objective / turn-in comes straight from Blizzard.
function W:Resolve(questID, chain)
    if not questID then return nil end

    local m, x, y = cacheGet(questID)
    if m then return m, x, y end

    -- Primary broad-coverage source: the bundled quest-giver coordinate
    -- table. Cached on first hit so a later harvest of the player's own
    -- observed giver position can still override it.
    local static = ns.CHAINGUIDE_QUEST_COORDS and ns.CHAINGUIDE_QUEST_COORDS[questID]
    if static and static.m and static.x and static.y then
        cacheSet(questID, static.m, static.x, static.y)
        return static.m, static.x, static.y
    end

    if C_QuestLine and C_QuestLine.GetQuestLineInfo then
        local maps = candidateMaps(chain)
        for i = 1, #maps do
            local info = C_QuestLine.GetQuestLineInfo(questID, maps[i])
            if info and info.x and info.y and (info.x ~= 0 or info.y ~= 0) then
                cacheSet(questID, maps[i], info.x, info.y)
                return maps[i], info.x, info.y
            end
        end
    end

    return nil
end

-- ─── Set the waypoint ──────────────────────────────────────────────────
function W:SetWaypoint(mapID, x, y, title)
    if TomTom and TomTom.AddWaypoint then
        TomTom:AddWaypoint(mapID, x, y, { title = title, from = "Everything Quests" })
        return true
    end
    -- No TomTom: we deliberately do NOT write Blizzard's user waypoint here.
    -- C_Map.SetUserWaypoint + C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    -- seed addon taint into Blizzard's shared super-track/user-waypoint state,
    -- which the world-map data providers and AreaPOI tooltip widgets read later.
    -- That is the sticky-taint source behind the "secret value" arithmetic
    -- crash on an AreaPOI tooltip (textHeight) and contributes to the
    -- QuestDataProvider SetPassThroughButtons block. Instead, openMap (below)
    -- takes the player to the right zone and we print the exact coords so they
    -- can still find the spot. TomTom users keep the navigation arrow above.
    print(("|cffEBB706EQ|r: |cffffffff%s|r is at |cff66ccff%.1f, %.1f|r — opening the map there."):format(
        title or "Quest", (x or 0) * 100, (y or 0) * 100))
    return false
end

-- Open the world map at mapID, but only retarget it when it isn't already
-- there. Retargeting (OpenWorldMap / SetMapID) makes EVERY map data provider —
-- Blizzard's QuestDataProvider AND AreaPOIDataProvider — re-acquire its pins.
-- When EQ drives that from an insecure click, the refresh runs tainted: the
-- provider caches tainted pin/widget state, which is what later blows up an
-- AreaPOI tooltip's "secret value" arithmetic on hover and trips
-- QuestDataProvider's protected SetPassThroughButtons. (Deferring this with
-- C_Timer does NOT help — a closure created by insecure code stays tainted and
-- re-taints the timer's callback when it runs; verified against the taint
-- model. The only real mitigation is to not trigger the refresh needlessly.)
-- So: if the map is already on this mapID, do nothing — that single guard is
-- what actually keeps the providers clean for the common "already here" case.
-- The actual map open/retarget, split out so the combat guard can defer JUST
-- this protected work to PLAYER_REGEN_ENABLED.
local function doOpenMap(mapID)
    if OpenWorldMap then
        OpenWorldMap(mapID)
    elseif WorldMapFrame then
        if ShowUIPanel then ShowUIPanel(WorldMapFrame) end
        if WorldMapFrame.SetMapID then WorldMapFrame:SetMapID(mapID) end
    end
end

local function openMap(mapID)
    if mapID and WorldMapFrame and WorldMapFrame:IsShown()
       and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID() == mapID then
        return
    end
    -- In COMBAT, retargeting the world map from our (insecure) click taints
    -- Blizzard's map data providers — FlightPointDataProvider et al. call the
    -- PROTECTED SetPropagateMouseClicks when they re-acquire pins after SetMapID,
    -- which throws ADDON_ACTION_BLOCKED during combat lockdown. The quest's
    -- super-track already ran (it isn't protected), so the on-screen objective
    -- arrow still guides the player; we only need to hold the map OPEN itself
    -- until combat ends. Never call doOpenMap while in combat. Fixed key →
    -- latest target wins if several directions are requested mid-fight.
    if InCombatLockdown() then
        local Events = ns:GetSubsystem("Events")
        if Events then
            Events:RunWhenOutOfCombat("chainGuideOpenMap", function() doOpenMap(mapID) end)
        end
        return
    end
    doOpenMap(mapID)
end

-- ─── Live coordinate for an in-log quest ───────────────────────────────
-- The best on-the-ground point for a quest you already have: the next
-- objective while in progress (GetNextWaypoint), or — once complete —
-- the quest's POI on the current map, which is the TURN-IN marker.
-- GetNextWaypoint returns nil for a complete quest, so without the
-- GetQuestsOnMap fallback TomTom would get no hand-in pin (confirmed via
-- /eqs dir: GetNextWaypoint none, GetQuestsOnMap returns the turn-in coord).
-- Only used to feed TomTom — non-TomTom users get the same point straight
-- from Blizzard's quest super-track, which needs no coordinate from us.
local function liveWaypoint(questID)
    if C_QuestLog and C_QuestLog.GetNextWaypoint then
        local m, x, y = C_QuestLog.GetNextWaypoint(questID)
        if m and x and y and (x ~= 0 or y ~= 0) then return m, x, y end
    end
    if C_QuestLog and C_QuestLog.GetQuestsOnMap
       and C_Map and C_Map.GetBestMapForUnit then
        local pm = C_Map.GetBestMapForUnit("player")
        local list = pm and C_QuestLog.GetQuestsOnMap(pm)
        if list then
            for i = 1, #list do
                local e = list[i]
                if e.questID == questID and e.x and e.y and (e.x ~= 0 or e.y ~= 0) then
                    return pm, e.x, e.y
                end
            end
        end
    end
    return nil
end

-- ─── Navigate to an in-log quest (Case A) ──────────────────────────────
-- The quest is in your log. Blizzard already tracks its live objective — or
-- its TURN-IN once complete — and draws that POI on your map, so we super-
-- track the quest and let Blizzard guide you. We do NOT drop our own giver
-- waypoint: the giver coord is the wrong spot mid-quest or at hand-in, and
-- SetUserWaypoint would hijack the super-track to it — the original
-- "directions point back where I was standing" bug.
function W:_goToInLog(questID, title)
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
        -- Drop any user-waypoint super-track first, but ONLY if one exists — a
        -- needless SetSuperTrackedUserWaypoint(false) still fires
        -- SUPER_TRACKING_CHANGED, and each such event makes Blizzard's
        -- QuestDataProvider re-acquire its pins on our tainted stack. Fewer
        -- redundant events = fewer tainted refreshes (the real mitigation;
        -- deferral can't launder the taint).
        if C_SuperTrack.SetSuperTrackedUserWaypoint
           and C_Map and C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() then
            C_SuperTrack.SetSuperTrackedUserWaypoint(false)
        end
        -- Skip re-super-tracking a quest we're already tracking — same
        -- redundant-event reasoning.
        local cur = C_SuperTrack.GetSuperTrackedQuestID
                    and C_SuperTrack.GetSuperTrackedQuestID()
        if cur ~= questID then
            C_SuperTrack.SetSuperTrackedQuestID(questID)
        end
    end
    -- TomTom draws its arrow from a real coord, so feed it the best live point:
    -- the next objective while in progress, or the turn-in once complete (see
    -- liveWaypoint). SetWaypoint's TomTom branch returns before anything else,
    -- so this is a no-op for non-TomTom users — the super-track above already
    -- shows Blizzard's objective marker.
    local wm, wx, wy = liveWaypoint(questID)
    if TomTom and TomTom.AddWaypoint and wm and wx and wy then
        self:SetWaypoint(wm, wx, wy, title)
    end
    openMap(wm or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")))
    return true
end

-- ─── Navigate to a not-in-log quest's giver (Case B) ───────────────────
-- Resolve where the quest is picked up and drop a waypoint there. Returns
-- false when no location is known so the caller can fall back to a hint.
function W:_goToGiver(questID, chain, title)
    local mapID, x, y = self:Resolve(questID, chain)
    if mapID and x and y then
        self:SetWaypoint(mapID, x, y, title)
        openMap(mapID)
        return true
    end
    return false
end

-- ─── The chain's next actionable step ──────────────────────────────────
-- The earliest quest in the chain the player hasn't completed: their active
-- quest mid-chain, or the next pickup. Skips chain-nav nodes and breadcrumbs
-- (declared optional). Walks items in authored/story order, so for the linear
-- campaign questlines this is exactly "the next thing to do."
--
-- Used to redirect a click on a still-LOCKED future step. The giver coords for
-- a future quest mark where it will *eventually* be offered — useless now,
-- because it isn't given until the earlier steps are done. For a hub-based
-- storyline every such giver also clusters right where you're standing, so the
-- redirect turns "pin at my feet, nothing to accept" into "go do your real
-- next step."
local function nextActionableStep(chain)
    if not chain then return nil end
    local Database   = ns:GetSubsystem("ChainGuideDatabase")
    local Characters = ns:GetSubsystem("ChainGuideCharacters")
    if not (Database and Characters) then return nil end
    -- Defensive: ensure items are sourced + normalized. Both are idempotent;
    -- by click time a render has usually already done this.
    local QLS = ns:GetSubsystem("ChainGuideQuestLineSource")
    if QLS and QLS.EnsureChainItems then QLS:EnsureChainItems(chain) end
    Database:NormalizeChain(chain)
    local items = chain.items
    if not items then return nil end
    local char = Database:CurrentCharacter()
    for i = 1, #items do
        local raw = items[i]
        if raw.type ~= "chain" and not raw.breadcrumb then
            local item = Database:GetVariation(raw, char)
            if item and item.id and not Characters:IsQuestCompleted(item.id) then
                return item
            end
        end
    end
    return nil
end

-- Public wrapper around the local nextActionableStep, so the chain-view
-- renderer can highlight the chain's next step and the "Continue" button can
-- route to it — both reading the SAME source of truth (no logic drift between
-- the badge and the button). Returns the resolved item ({id, ...}) or nil.
function W:NextActionableStep(chain)
    return nextActionableStep(chain)
end

-- ─── Public: go to a quest ─────────────────────────────────────────────
function W:GoTo(questID, chain)
    local title = ns.Util.QuestTitle(questID, true)

    -- Work out what to actually navigate to. Usually it's the clicked quest —
    -- but a click on a still-LOCKED future step (not in your log, not yet
    -- completed, and not the chain's next actionable quest) redirects to that
    -- next step: the thing you can act on right now. Without this, every future
    -- quest in a hub-based storyline drops a giver pin where you're standing
    -- that won't offer the quest until you've cleared the earlier steps.
    local navID, navTitle = questID, title
    local clickedInLog = C_QuestLog and C_QuestLog.GetLogIndexForQuestID
                         and C_QuestLog.GetLogIndexForQuestID(questID) ~= nil
    if chain and not clickedInLog then
        local Characters = ns:GetSubsystem("ChainGuideCharacters")
        if Characters and not Characters:IsQuestCompleted(questID) then
            local step = nextActionableStep(chain)
            if step and step.id and step.id ~= questID then
                navID    = step.id
                navTitle = ns.Util.QuestTitle(step.id, true) or navTitle
                print(("|cffEBB706EQ|r: |cffffffff%s|r comes later in |cffffffff%s|r — directions set to your next step, |cffffffff%s|r."):format(
                    title, chain.name or "this chain", navTitle))
            end
        end
    end

    -- In your log → super-track the live objective / turn-in.
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID
       and C_QuestLog.GetLogIndexForQuestID(navID) then
        return self:_goToInLog(navID, navTitle)
    end

    -- Not in your log → resolve the giver so you know where to pick it up.
    if self:_goToGiver(navID, chain, navTitle) then
        return true
    end

    -- Nothing known yet — open the chain's best-guess zone and say so rather
    -- than dead-clicking. It'll be saved automatically on first pickup.
    local maps = candidateMaps(chain)
    if maps[1] then openMap(maps[1]) end
    print(("|cffEBB706EQ|r: no precise location for |cffffffff%s|r yet — it'll be saved automatically the first time you pick it up."):format(navTitle))
    return false
end

-- ─── Passive harvest ───────────────────────────────────────────────────
-- When the player opens a quest giver's dialog or accepts a quest, the
-- giver is right there: record the player's exact position. This is the
-- most accurate "where to go" source and permanently fills cache gaps.
local function harvest(questID)
    if not (questID and questID > 0) then return end
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return end
    local m = C_Map.GetBestMapForUnit("player")
    if not m then return end
    local pos = C_Map.GetPlayerMapPosition(m, "player")
    if not pos then return end
    local x, y = pos:GetXY()
    if x and y and (x ~= 0 or y ~= 0) then
        cacheSet(questID, m, x, y)
    end
end

function W:OnEnable()
    local Events = ns:GetSubsystem("Events")
    if not Events then return end
    -- The Core/Events dispatcher calls handlers as (event, ...), so the
    -- first param is the event name; real payload starts at the second.
    Events:On("QUEST_DETAIL", function()
        if GetQuestID then harvest(GetQuestID()) end
    end)
    Events:On("QUEST_ACCEPTED", function(_, a, b)
        -- Retail fires (questID); older builds (questLogIndex, questID).
        harvest(b or a)
    end)
end
