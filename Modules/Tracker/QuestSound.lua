local _, ns = ...

local Q = ns:RegisterSubsystem("TrackerQuestSound", {})

Q.lastComplete = {}
Q.armed = false

local function shouldPlay()
    local DB = ns:GetSubsystem("DB")
    if not DB then return false end
    return DB.db.profile.tracker.questSoundEnabled ~= false
end

local function chosenSound()
    local DB = ns:GetSubsystem("DB")
    return DB and DB.db.profile.tracker.questCompleteSound or "EQ: Work Complete"
end

local function detectTransitions()
    -- Skip the very first pass after login: every quest already-complete in
    -- the player's log would otherwise fire a sound the moment we initialize.
    local Cache = ns:GetSubsystem("Cache")
    if not (Cache and Cache.All) then return end
    local quests = Cache:All()

    if not Q.armed then
        for id, q in pairs(quests) do
            Q.lastComplete[id] = q.isComplete or false
        end
        Q.armed = true
        return
    end

    local newlyReady = false
    for id, q in pairs(quests) do
        local was = Q.lastComplete[id]
        local now = q.isComplete and true or false
        if now and not was then newlyReady = true end
        Q.lastComplete[id] = now
    end
    -- Drop entries for quests no longer in the log.
    for id in pairs(Q.lastComplete) do
        if not quests[id] then Q.lastComplete[id] = nil end
    end

    if newlyReady and shouldPlay() and PlaySoundFile then
        local Media = ns:GetSubsystem("Media")
        local file = Media and Media.GetSoundFile and Media:GetSoundFile(chosenSound())
        if file then PlaySoundFile(file, "Master") end
    end
end

function Q:OnEnable()
    local Events = ns:GetSubsystem("Events")
    Events:On("QUEST_LOG_UPDATE", detectTransitions)
end
