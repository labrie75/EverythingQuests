-- Modules/History/Session.lua
-- Per-play-session quest stats: quests completed, quest XP, quest gold, play
-- time, quests/hour, and level-ups since the session began.
--
-- A "session" is one play sitting. It starts on a fresh login and CONTINUES
-- across /reload — state lives in the per-character SavedVariable, and we only
-- reset when PLAYER_ENTERING_WORLD reports isInitialLogin (the same signal
-- Tracker/SuperTrackPersist uses to tell a real login apart from a reload).
--
-- Counts come straight off QUEST_TURNED_IN (the same event History records),
-- so the summary works even when history recording is turned off. Surfaced two
-- ways: `/eqs session` (chat recap) and the "This Session" tab in the History
-- window.

local _, ns = ...

local Session = ns:RegisterSubsystem("Session", {})

-- Per-character session store. DB.char is the raw EverythingQuestsCharDB global
-- (set in DB:OnInitialize, which runs before any module's OnInitialize), so it
-- is available here. Keeping session state under db.char means it survives a
-- /reload; resetting on fresh login is handled explicitly below.
local function store()
    local DB = ns:GetSubsystem("DB")
    if not (DB and DB.char) then return nil end
    DB.char.session = DB.char.session or {}
    return DB.char.session
end

local function now()
    return (GetServerTime and GetServerTime()) or time()
end

-- Begin a fresh session: zero the counters and stamp the start time + level.
function Session:Start()
    local s = store()
    if not s then return end
    s.startTime  = now()
    s.startLevel = (UnitLevel and UnitLevel("player")) or 0
    s.quests     = 0
    s.xp         = 0
    s.gold       = 0
end

function Session:OnInitialize()
    -- Ensure the store exists; do NOT reset here — OnInitialize also runs on
    -- /reload, and a reload must continue the same session. Only when there is
    -- no session at all (first install, or a wiped char DB) do we seed one so
    -- the summary is never nil; a genuine fresh login re-Starts via OnEnable.
    local s = store()
    if s and not s.startTime then self:Start() end
end

function Session:OnEnable()
    local Events = ns:GetSubsystem("Events")
    if not Events then return end

    -- A real fresh login (not a /reload, not a zone change) starts a new
    -- session. isInitialLogin is true only on the first PLAYER_ENTERING_WORLD
    -- after logging in or a client restart.
    Events:On("PLAYER_ENTERING_WORLD", function(_, isInitialLogin)
        if isInitialLogin then self:Start() end
    end)

    -- Quest turn-ins drive the counters. xp/money rewards are 0 on many quests
    -- (and at max level), so only add them when present.
    Events:On("QUEST_TURNED_IN", function(_, _questID, xpReward, moneyReward)
        local s = store()
        if not s then return end
        s.quests = (s.quests or 0) + 1
        if xpReward    and xpReward    > 0 then s.xp   = (s.xp   or 0) + xpReward    end
        if moneyReward and moneyReward > 0 then s.gold = (s.gold or 0) + moneyReward end
        -- Live-refresh the History window only if it's open ON the session tab.
        local HF = ns:GetSubsystem("HistoryFrame")
        if HF and HF.frame and HF.frame:IsShown() and HF._activeTab == "session" then
            HF:Render()
        end
    end)
end

-- Snapshot of the current session (raw numbers; callers format). `played` is
-- seconds since the session started; `levelUps` is current level minus the
-- level the session started at; `perHour` is nil until at least a minute in
-- (a rate over a few seconds is meaningless).
function Session:Summary()
    local s = store() or {}
    local startTime  = s.startTime or now()
    local played     = math.max(0, now() - startTime)
    local quests     = s.quests or 0
    local startLevel = s.startLevel or (UnitLevel and UnitLevel("player")) or 0
    local curLevel   = (UnitLevel and UnitLevel("player")) or startLevel
    return {
        played     = played,
        quests     = quests,
        xp         = s.xp or 0,
        gold       = s.gold or 0,
        startLevel = startLevel,
        curLevel   = curLevel,
        levelUps   = math.max(0, curLevel - startLevel),
        perHour    = (played >= 60) and (quests / (played / 3600)) or nil,
    }
end

-- Chat recap for `/eqs session`.
function Session:Print()
    local sm = self:Summary()
    local Y, W, R = "|cffEBB706", "|cffffffff", "|r"
    local function bignum(n)
        return (BreakUpLargeNumbers and BreakUpLargeNumbers(n)) or tostring(n)
    end
    local function money(c)
        return (GetCoinTextureString and GetCoinTextureString(c or 0)) or (tostring(c or 0) .. "c")
    end
    local perHour = sm.perHour and ("%.1f / hr"):format(sm.perHour) or "\226\128\148"

    print(Y .. "Everything Quests \226\128\148 This Session" .. R)
    print(("  Played:      " .. W .. "%s" .. R):format(ns.Util.FmtDuration(sm.played)))
    print(("  Quests done: " .. W .. "%d" .. R .. "  (%s)"):format(sm.quests, perHour))
    if sm.xp > 0 then
        print(("  Quest XP:    " .. W .. "%s" .. R):format(bignum(sm.xp)))
    end
    if sm.gold > 0 then
        print("  Quest gold:  " .. money(sm.gold))
    end
    if sm.levelUps > 0 then
        print(("  Level-ups:   " .. W .. "%d" .. R .. "  (%d to %d)"):format(
            sm.levelUps, sm.startLevel, sm.curLevel))
    end
end
