local _, ns = ...

local Q = ns:RegisterSubsystem("TrackerQuestSound", {})

Q.lastComplete = {}
Q.armed = false

-- ── Per-title dedup so a regular quest doesn't double-fire when both
-- the Cache-diff path AND the CHAT_MSG_SYSTEM parser see the same
-- completion. Window is short (2 s) because the two events fire within
-- the same frame burst; anything longer than that is a separate event.
local DEDUP_WINDOW_S = 2
local _recentTitles = {}                 -- [title] = expireTime

local function isRecent(title)
    if not title or title == "" then return false end
    local exp = _recentTitles[title]
    if not exp then return false end
    if exp > GetTime() then return true end
    _recentTitles[title] = nil
    return false
end

local function recordRecent(title)
    if title and title ~= "" then
        _recentTitles[title] = GetTime() + DEDUP_WINDOW_S
    end
end

local function shouldPlay()
    local DB = ns:GetSubsystem("DB")
    if not DB then return false end
    return DB.db.profile.tracker.questSoundEnabled ~= false
end

local function chosenSound()
    local DB = ns:GetSubsystem("DB")
    return DB and DB.db.profile.tracker.questCompleteSound or "EQ: Work Complete"
end

local function playSound()
    if not (shouldPlay() and PlaySoundFile) then return end
    local Media = ns:GetSubsystem("Media")
    local file = Media and Media.GetSoundFile and Media:GetSoundFile(chosenSound())
    if file then PlaySoundFile(file, "Master") end
end

-- ── Cache-diff path (regular quests in the log) ───────────────────────
-- Reused scratch so detectTransitions never allocates on a batch.
local _readyTitles = {}

local function detectTransitions()
    local Cache = ns:GetSubsystem("Cache")
    if not (Cache and Cache.All) then return end
    local quests = Cache:All()

    -- Skip the very first pass after login: every already-complete quest
    -- would otherwise fire a sound the moment we initialize.
    if not Q.armed then
        for id, q in pairs(quests) do
            Q.lastComplete[id] = q.isComplete or false
        end
        Q.armed = true
        return
    end

    local n = 0
    for id, q in pairs(quests) do
        local was = Q.lastComplete[id]
        local now = q.isComplete and true or false
        if now and not was then
            n = n + 1
            _readyTitles[n] = q.title or ""
        end
        Q.lastComplete[id] = now
    end
    -- Drop entries for quests no longer in the log.
    for id in pairs(Q.lastComplete) do
        if not quests[id] then Q.lastComplete[id] = nil end
    end

    -- One sound for the batch (back-to-back fires would be unpleasant), but
    -- record EVERY newly-ready title so the matching CHAT_MSG_SYSTEM lines
    -- that arrive next frame are deduped away.
    if n > 0 then
        for i = 1, n do
            recordRecent(_readyTitles[i])
            _readyTitles[i] = nil
        end
        playSound()
    end
end

-- ── Chat-text path (catches "instant" completions that never enter the
-- quest log: some dailies, callings, scenario step turn-ins, etc.) ────
-- Build a Lua pattern from Blizzard's localized format string. The format
-- uses %s where the quest title goes; everything else is literal and must
-- have its Lua-pattern specials escaped. Sentinel-swap so the escape pass
-- doesn't touch the placeholder.
local _completePattern
local function getCompletePattern()
    if _completePattern then return _completePattern end
    local fmt = ERR_QUEST_COMPLETE_S
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local SENTINEL = "\1"
    _completePattern = "^" .. fmt
        :gsub("%%s", SENTINEL)
        :gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
        :gsub(SENTINEL, "(.+)")
        .. "$"
    return _completePattern
end

local function onSystemChat(_, msg)
    if type(msg) ~= "string" then return end
    local p = getCompletePattern()
    if not p then return end
    local title = msg:match(p)
    if not title or title == "" then return end
    if isRecent(title) then return end          -- Cache-diff path already fired
    recordRecent(title)
    playSound()
end

function Q:OnEnable()
    local Events = ns:GetSubsystem("Events")
    Events:On("QUEST_LOG_UPDATE", detectTransitions)
    Events:On("CHAT_MSG_SYSTEM",  onSystemChat)
end
