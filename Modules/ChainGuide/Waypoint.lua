-- Modules/ChainGuide/Waypoint.lua
-- Clicking a quest in the Chain Guide drops a waypoint (TomTom if present,
-- else Blizzard's user waypoint) and opens the world map there.
--
-- Resolver priority (best "where do I go to get this" first):
--   1. Cache       — prior resolves + passively harvested quest-giver
--                     coords. Account-wide, survives sessions.
--   2. Coord table — the bundled quest-giver coordinate table
--                     (ns.CHAINGUIDE_QUEST_COORDS); broad coverage.
--   3. Questline API — C_QuestLine.GetQuestLineInfo gives the same map
--                     position WoW uses for questline map dots.
--   4. Log waypoint — C_QuestLog.GetNextWaypoint, only when the quest is
--                     active; points at the next objective (last resort).

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

    if C_QuestLog and C_QuestLog.GetNextWaypoint
       and C_QuestLog.GetLogIndexForQuestID
       and C_QuestLog.GetLogIndexForQuestID(questID) then
        local wm, wx, wy = C_QuestLog.GetNextWaypoint(questID)
        if wm and wx and wy then
            cacheSet(questID, wm, wx, wy)
            return wm, wx, wy
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
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
        return true
    end
    return false
end

local function openMap(mapID)
    if OpenWorldMap then
        OpenWorldMap(mapID)
    elseif WorldMapFrame then
        if ShowUIPanel then ShowUIPanel(WorldMapFrame) end
        if WorldMapFrame.SetMapID then WorldMapFrame:SetMapID(mapID) end
    end
end

-- ─── Public: go to a quest ─────────────────────────────────────────────
function W:GoTo(questID, chain)
    local title = ns.Util.QuestTitle(questID, true)

    local mapID, x, y = self:Resolve(questID, chain)
    if mapID and x and y then
        self:SetWaypoint(mapID, x, y, title)
        openMap(mapID)
        return true
    end

    -- No coordinates yet. Super-track if it's in the log so the player at
    -- least gets the in-game arrow, open the chain's zone if we can guess
    -- it, and say so rather than dead-clicking.
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID
       and C_QuestLog and C_QuestLog.GetLogIndexForQuestID
       and C_QuestLog.GetLogIndexForQuestID(questID) then
        C_SuperTrack.SetSuperTrackedQuestID(questID)
    end
    local maps = candidateMaps(chain)
    if maps[1] then openMap(maps[1]) end
    print(("|cffEBB706EQ|r: no precise location for |cffffffff%s|r yet — it'll be saved automatically the first time you pick it up."):format(title))
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
