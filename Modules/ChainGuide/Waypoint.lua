local _, ns = ...

local W = ns:RegisterSubsystem("ChainGuideWaypoint", {})

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
        e.lastSeen = time()
        return e.m, e.x, e.y
    end
end

local function cacheSet(questID, mapID, x, y)
    if not (questID and mapID and x and y) then return end
    local t = cacheTable()
    if t then t[questID] = { m = mapID, x = x, y = y, lastSeen = time() } end
end

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

function W:Resolve(questID, chain)
    if not questID then return nil end

    local m, x, y = cacheGet(questID)
    if m then return m, x, y end

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

-- Retargeting the world map (OpenWorldMap / SetMapID) makes every map data
-- provider re-acquire its pins. When EQ drives that from an insecure click the
-- refresh runs tainted, blowing up AreaPOI "secret value" arithmetic on hover
-- and tripping QuestDataProvider's protected SetPassThroughButtons. C_Timer
-- does NOT launder the taint — a closure from insecure code re-taints its
-- callback. Guard: if the map is already on this mapID, skip the retarget.
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

function W:ResolveForPin(questID, chain)
    if not questID then return nil end
    local inLog = C_QuestLog and C_QuestLog.GetLogIndexForQuestID
                  and C_QuestLog.GetLogIndexForQuestID(questID) ~= nil
    if inLog then
        local m, x, y = liveWaypoint(questID)
        if m and x and y then return m, x, y, true end
    end
    local m, x, y = self:Resolve(questID, chain)
    if m and x and y then return m, x, y, inLog or false end
    return nil
end

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
    local wm, wx, wy = liveWaypoint(questID)
    if TomTom and TomTom.AddWaypoint and wm and wx and wy then
        self:SetWaypoint(wm, wx, wy, title)
    end
    openMap(wm or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")))
    return true
end

function W:_goToGiver(questID, chain, title)
    local mapID, x, y = self:Resolve(questID, chain)
    if mapID and x and y then
        self:SetWaypoint(mapID, x, y, title)
        openMap(mapID)
        return true
    end
    return false
end

local _stepCellDone  = {}
local _stepCellInLog = {}

local function stepCellKey(raw)
    if raw.x and raw.y then return raw.y * 4096 + raw.x end
    return nil
end

local function nextActionableStep(chain)
    if not chain then return nil end
    local Database   = ns:GetSubsystem("ChainGuideDatabase")
    local Characters = ns:GetSubsystem("ChainGuideCharacters")
    if not (Database and Characters) then return nil end
    local QLS = ns:GetSubsystem("ChainGuideQuestLineSource")
    if QLS and QLS.EnsureChainItems then QLS:EnsureChainItems(chain) end
    Database:NormalizeChain(chain)
    local items = chain.items
    if not items then return nil end
    local char = Database:CurrentCharacter()

    -- Pre-pass: a faction-paired step (e.g. Paved in Ash — 86735 Horde / 86736
    -- Alliance, both at overlay cell x1,y2) is two items in one cell, and the
    -- off-faction one can NEVER be completed. A plain "first incomplete item"
    -- scan would lock onto it forever and stall the chain (the reported "Paved
    -- in Ash is next" bug). So collapse by cell: a cell is DONE if ANY member is
    -- completed, and we remember a member that's in the player's log (their own
    -- accepted quest) so we point at it rather than its off-faction twin.
    wipe(_stepCellDone)
    wipe(_stepCellInLog)
    for i = 1, #items do
        local raw = items[i]
        if raw.type ~= "chain" and not raw.breadcrumb then
            local key = stepCellKey(raw)
            if key then
                local item = Database:GetVariation(raw, char)
                local qid  = item and item.id
                if qid then
                    if Characters:IsQuestCompleted(qid) then
                        _stepCellDone[key] = true
                    elseif C_QuestLog and C_QuestLog.GetLogIndexForQuestID
                           and C_QuestLog.GetLogIndexForQuestID(qid) then
                        _stepCellInLog[key] = item
                    end
                end
            end
        end
    end

    for i = 1, #items do
        local raw = items[i]
        if raw.type ~= "chain" and not raw.breadcrumb then
            local item = Database:GetVariation(raw, char)
            if item and item.id and not Characters:IsQuestCompleted(item.id) then
                local key = stepCellKey(raw)
                if not (key and _stepCellDone[key]) then
                    if key and _stepCellInLog[key] then return _stepCellInLog[key] end
                    return item
                end
            end
        end
    end
    return nil
end

function W:NextActionableStep(chain)
    return nextActionableStep(chain)
end

function W:AdvanceWaypoint(chain)
    local step = nextActionableStep(chain)
    if not (step and step.id) then return nil end
    local id = step.id
    local inLog = C_QuestLog and C_QuestLog.GetLogIndexForQuestID
                  and C_QuestLog.GetLogIndexForQuestID(id)
    if inLog then
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
            local cur = C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
            if cur ~= id then C_SuperTrack.SetSuperTrackedQuestID(id) end
        end
        if TomTom and TomTom.AddWaypoint then
            local wm, wx, wy = liveWaypoint(id)
            if wm and wx and wy then self:SetWaypoint(wm, wx, wy, ns.Util.QuestTitle(id, true)) end
        end
    elseif TomTom and TomTom.AddWaypoint then
        local m, x, y = self:Resolve(id, chain)
        if m and x and y then self:SetWaypoint(m, x, y, ns.Util.QuestTitle(id, true)) end
    end
    return step
end

function W:GoTo(questID, chain)
    local title = ns.Util.QuestTitle(questID, true)

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

    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID
       and C_QuestLog.GetLogIndexForQuestID(navID) then
        return self:_goToInLog(navID, navTitle)
    end

    if self:_goToGiver(navID, chain, navTitle) then
        return true
    end

    local maps = candidateMaps(chain)
    if maps[1] then openMap(maps[1]) end
    print(("|cffEBB706EQ|r: no precise location for |cffffffff%s|r yet — it'll be saved automatically the first time you pick it up."):format(navTitle))
    return false
end

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

local function questBelongsToChain(chain, questID)
    if not (chain and chain.items and questID) then return false end
    for i = 1, #chain.items do
        local raw = chain.items[i]
        if raw and raw.type ~= "chain" then
            if raw.id == questID then return true end
            if raw.variations then
                for j = 1, #raw.variations do
                    if raw.variations[j].id == questID then return true end
                end
            end
        end
    end
    return false
end

function W:OnEnable()
    local Events = ns:GetSubsystem("Events")
    if not Events then return end
    Events:On("QUEST_DETAIL", function()
        if GetQuestID then harvest(GetQuestID()) end
    end)
    Events:On("QUEST_ACCEPTED", function(_, a, b)
        harvest(b or a)
    end)

    Events:On("QUEST_TURNED_IN", function(_, questID)
        local CG = ns:GetSubsystem("ChainGuide")
        local chain = CG and CG.GetTrackedChain and CG:GetTrackedChain()
        if not chain then return end
        local QLS = ns:GetSubsystem("ChainGuideQuestLineSource")
        if QLS and QLS.EnsureChainItems then QLS:EnsureChainItems(chain) end
        local Database = ns:GetSubsystem("ChainGuideDatabase")
        if Database then Database:NormalizeChain(chain) end
        if not questBelongsToChain(chain, questID) then return end
        -- IsQuestFlaggedCompleted can lag one frame behind QUEST_TURNED_IN, so
        -- defer the next-step recompute a frame for fresh data. The deferred
        -- work only super-tracks / feeds TomTom (no map retarget, no user
        -- waypoint), so it carries no new taint despite the timer closure.
        C_Timer.After(0, function()
            local step = self:AdvanceWaypoint(chain)
            if not step and chain.items and #chain.items > 0 then
                if CG.ClearTrackedChainID then CG:ClearTrackedChainID() end
                print(("|cffEBB706EQ|r: |cffffffff%s|r complete — no longer following it."):format(chain.name or "This chain"))
            end
        end)
    end)
end
