local _, ns = ...

local Filters = ns:RegisterSubsystem("TrackerFilters", {})

local DAILY_FREQ  = (Enum and Enum.QuestFrequency and Enum.QuestFrequency.Daily)  or LE_QUEST_FREQUENCY_DAILY  or 2
local WEEKLY_FREQ = (Enum and Enum.QuestFrequency and Enum.QuestFrequency.Weekly) or LE_QUEST_FREQUENCY_WEEKLY or 3

local function currentZoneName()
    return GetZoneText and GetZoneText() or nil
end

function Filters:Visible(questID, q, showAllInLog)
    if not q then return false end

    local DB = ns:GetSubsystem("DB")
    if not DB then return true end
    local profile = DB.db.profile.tracker
    local f       = profile.filters
    local char    = DB.char

    if not showAllInLog and char.hidden and char.hidden[questID] then return false end

    if char.pinned and char.pinned[questID] then return true end

    if not showAllInLog and profile.showOnlyWatched and not q.isWatched then
        return false
    end

    if q.isCampaign then
        if not f.showCampaign then return false end
    elseif q.frequency == DAILY_FREQ then
        if not f.showDaily then return false end
    elseif q.frequency == WEEKLY_FREQ then
        if not f.showWeekly then return false end
    else
        if not f.showNormal then return false end
    end

    if f.onlyCurrentZone and q.zone then
        if q.zone ~= currentZoneName() then return false end
    end

    return true
end
