local _, ns = ...

local Cache = ns:RegisterSubsystem("Cache", {})

Cache.quests          = {}
Cache.headerOrder     = {}
Cache.dirtyAll        = true
Cache.dirtyObjectives = false

local firstSeen = {}

local baselined = false

-- Session "primed" guard for the cold-login empty-cache race. The cache is
-- built lazily on the first Cache:All()/Cache:Get(), which on login happens in
-- the tracker's first render ~0.25s after PLAYER_LOGIN. On a COLD start the
-- server may not have sent quest data yet, so C_QuestLog.GetNumQuestLogEntries()
-- returns 0 and fullRebuild() produces an EMPTY cache. The cheap
-- QUEST_LOG_UPDATE refresh (refreshDynamicFields) only updates quests already
-- in the cache, so it can never ADD the quests that load a moment later — the
-- regular Quests/Campaign sections would then stay empty until a structural
-- quest event or a /reload, while the World Quests section (which rebuilds from
-- scratch every pass) renders normally. Until the cache has captured a
-- populated log this session, QUEST_LOG_UPDATE stays on the FULL-rebuild path
-- so the empty build self-heals the instant quest data arrives; once primed it
-- downgrades to the cheap path — the GC-churn win the two-tier cache exists for.
local primed = false

local function deriveIsCampaign(id, info)
    if C_CampaignInfo and C_CampaignInfo.GetCampaignID then
        local cid = C_CampaignInfo.GetCampaignID(id)
        if cid and cid > 0 then return true end
    end
    return (info and info.campaignID and info.campaignID > 0) and true or false
end

local objTextCache = {}
local function getObjectivesText(id)
    local cached = objTextCache[id]
    if cached ~= nil then return cached end
    local text = ""
    if C_QuestLog and C_QuestLog.SetSelectedQuest and _G.GetQuestLogQuestText then
        local saved = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
        C_QuestLog.SetSelectedQuest(id)
        local _, objText = _G.GetQuestLogQuestText()
        text = objText or ""
        if saved and saved ~= 0 then C_QuestLog.SetSelectedQuest(saved) end
    end
    objTextCache[id] = text
    return text
end

local function fullRebuild()
    wipe(Cache.quests)
    wipe(Cache.headerOrder)

    local currentHeader = nil
    local n = C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0
    for i = 1, n do
        local info = C_QuestLog.GetInfo and C_QuestLog.GetInfo(i)
        if info then
            if info.isHeader then
                currentHeader = info.title
            elseif info.isHidden then
            else
                local id = info.questID
                local fs = firstSeen[id]
                if not fs then
                    fs = baselined and time() or 0
                    firstSeen[id] = fs
                end
                local q = {
                    questID        = id,
                    firstSeen      = fs,
                    title          = info.title or (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)),
                    level          = info.level,
                    zone           = currentHeader,
                    frequency      = info.frequency,
                    isComplete     = C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) or false,
                    isOnMap        = info.isOnMap,
                    isCampaign     = deriveIsCampaign(id, info),
                    isAutoComplete = info.isAutoComplete,
                    isWatched      = C_QuestLog.GetQuestWatchType
                                     and C_QuestLog.GetQuestWatchType(id) ~= nil,
                    classification = (C_QuestInfoSystem
                                      and C_QuestInfoSystem.GetQuestClassification
                                      and C_QuestInfoSystem.GetQuestClassification(id))
                                  or (C_QuestLog
                                      and C_QuestLog.GetQuestClassification
                                      and C_QuestLog.GetQuestClassification(id)),
                    objectives     = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id) or {},
                }
                if #q.objectives == 0 then
                    q.fallbackText = getObjectivesText(id)
                end
                Cache.quests[id] = q
            end
        end
    end
    for qid in pairs(firstSeen) do
        if not Cache.quests[qid] then firstSeen[qid] = nil end
    end
    if next(Cache.quests) ~= nil then
        primed    = true
        baselined = true
    end
    Cache.dirtyAll        = false
    Cache.dirtyObjectives = false
end

local function refreshDynamicFields()
    for id, q in pairs(Cache.quests) do
        local watched = C_QuestLog.GetQuestWatchType
                        and C_QuestLog.GetQuestWatchType(id) ~= nil
        q.isWatched = watched
        q.isCampaign = deriveIsCampaign(id)
        if watched then
            if C_QuestLog.GetQuestObjectives then
                q.objectives = C_QuestLog.GetQuestObjectives(id) or q.objectives
            end
            if C_QuestLog.IsComplete then
                q.isComplete = C_QuestLog.IsComplete(id) or false
            end
            if q.objectives and #q.objectives == 0 and not q.fallbackText then
                q.fallbackText = getObjectivesText(id)
            end
        end
    end
    Cache.dirtyObjectives = false
end

local function refresh()
    if Cache.dirtyAll then
        fullRebuild()
    elseif Cache.dirtyObjectives then
        refreshDynamicFields()
    end
end

function Cache:Get(questID)
    refresh()
    return self.quests[questID]
end

function Cache:All()
    refresh()
    return self.quests
end

function Cache:Invalidate()
    self.dirtyAll = true
end

function Cache:OnInitialize()
    local Events = ns:GetSubsystem("Events")

    local function dirtyAll() Cache.dirtyAll = true end
    Events:On("QUEST_ACCEPTED",   dirtyAll)
    Events:On("QUEST_REMOVED",    dirtyAll)
    Events:On("QUEST_TURNED_IN",  dirtyAll)

    local function dirtyDynamic()
        if not primed then
            Cache.dirtyAll = true
        else
            Cache.dirtyObjectives = true
        end
    end
    Events:On("QUEST_LOG_UPDATE",         dirtyDynamic)
    Events:On("QUEST_WATCH_LIST_CHANGED", dirtyDynamic)
end
