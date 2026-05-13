-- Modules/Tracker/Filters.lua
-- Decides whether a given quest should appear in the on-screen tracker.
-- The decision blends user preferences (db.profile.tracker.filters) with
-- per-quest character state (db.char.pinned).
--
-- Returns true (visible) or false (hidden). Pinned quests bypass everything
-- — pinning is the user's explicit "always show me this".

local _, ns = ...

local Filters = ns:RegisterSubsystem("TrackerFilters", {})

-- QuestFrequency enum has been around as both LE_QUEST_FREQUENCY_* and
-- Enum.QuestFrequency.*. Capture both at file-scope so we don't pay the
-- lookup cost on every quest, every refresh.
local DAILY_FREQ  = (Enum and Enum.QuestFrequency and Enum.QuestFrequency.Daily)  or LE_QUEST_FREQUENCY_DAILY  or 2
local WEEKLY_FREQ = (Enum and Enum.QuestFrequency and Enum.QuestFrequency.Weekly) or LE_QUEST_FREQUENCY_WEEKLY or 3

local function currentZoneName()
    return GetZoneText and GetZoneText() or nil
end

-- showAllInLog: opt-in flag for the QuestLog book's List which wants to
-- surface every quest in the player's log so the user can right-click to
-- recover or change watch state. Bypasses the watched and hidden filters;
-- type/zone filters still apply. The on-screen Tracker calls without the
-- flag, so unwatched / hidden quests stay off the tracker.
function Filters:Visible(questID, q, showAllInLog)
    if not q then return false end

    local DB = ns:GetSubsystem("DB")
    if not DB then return true end
    local profile = DB.db.profile.tracker
    local f       = profile.filters
    local char    = DB.char

    -- Hidden (legacy explicit-hide flag) is the strongest signal — kept
    -- around for power users / saved-variable migration but no longer has
    -- a UI exposure. Mutex with pinned at toggle time historically.
    if not showAllInLog and char.hidden and char.hidden[questID] then return false end

    -- Pinned wins over watch/type/zone filters: users have explicitly
    -- chosen to keep these quests on screen regardless of any preference.
    if char.pinned and char.pinned[questID] then return true end

    -- Watched gate — this is the primary visibility mechanism that mirrors
    -- Blizzard's default tracker. When showOnlyWatched is on (default),
    -- unwatched quests don't appear in the tracker. The book bypasses this
    -- via showAllInLog so it always shows the full log.
    if not showAllInLog and profile.showOnlyWatched and not q.isWatched then
        return false
    end

    -- Type-by-type visibility. A quest is matched by ONE category in this
    -- priority order: campaign > daily > weekly > normal. World quests live
    -- in C_TaskQuest, not C_QuestLog, so they never reach this predicate —
    -- the WorldQuests module handles their visibility on its own track.
    if q.isCampaign then
        if not f.showCampaign then return false end
    elseif q.frequency == DAILY_FREQ then
        if not f.showDaily then return false end
    elseif q.frequency == WEEKLY_FREQ then
        if not f.showWeekly then return false end
    else
        if not f.showNormal then return false end
    end

    -- Optional zone restriction. q.zone comes from the quest log header
    -- (which Blizzard groups by zone), GetZoneText() is the player's actual
    -- location — they line up for the common case. Quests with no header
    -- (rare; usually account-wide tracking quests) are kept visible since
    -- there's no meaningful zone to compare against.
    if f.onlyCurrentZone and q.zone then
        if q.zone ~= currentZoneName() then return false end
    end

    return true
end
