-- Modules/WorldQuests/Tooltip.lua
-- Rich tooltip for world quest pins and tracker rows: title, faction,
-- objectives, every reward (money / items / currencies / XP), time-left.
-- Built on standard GameTooltip APIs only — no third-party tooltip lib.

local _, ns = ...

local T = ns:RegisterSubsystem("WQTooltip", {})

-- Shared WQ time helpers — single source of truth in Core/Util.lua.
local Util = ns.Util

local function questTitle(questID)
    if C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID then
        local t = C_TaskQuest.GetQuestInfoByQuestID(questID)
        if t and t ~= "" then return t end
    end
    if QuestUtils_GetQuestName then
        local n = QuestUtils_GetQuestName(questID)
        if n and n ~= "" then return n end
    end
    return "World Quest"
end

local function factionName(questID)
    local id
    if C_QuestLog and C_QuestLog.GetQuestFactionID then
        id = C_QuestLog.GetQuestFactionID(questID)
    end
    if not id then return nil end
    if C_FactionInfo and C_FactionInfo.GetFactionDataByID then
        local data = C_FactionInfo.GetFactionDataByID(id)
        return data and data.name or nil
    end
    return nil
end

local function addObjectives(tip, questID)
    if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return end
    local objs = C_QuestLog.GetQuestObjectives(questID)
    if not (objs and #objs > 0) then return end
    for i = 1, #objs do
        local o = objs[i]
        if o and o.text and o.text ~= "" then
            local r, g, b = 0.95, 0.95, 0.95
            if o.finished then r, g, b = 0.40, 0.85, 0.40 end
            tip:AddLine("- " .. o.text, r, g, b, true)
        end
    end
end

local function addRewards(tip, questID)
    local hasReward = false

    -- Money
    local _money = GetQuestLogRewardMoney
    local money = _money and _money(questID) or 0
    if money and money > 0 then
        local txt = (GetCoinTextureString and GetCoinTextureString(money)) or tostring(money)
        tip:AddLine(txt, 1, 1, 1)
        hasReward = true
    end

    -- XP
    local xp = GetQuestLogRewardXP and GetQuestLogRewardXP(questID) or 0
    if xp and xp > 0 then
        tip:AddLine(("%d XP"):format(xp), 1, 1, 1)
        hasReward = true
    end

    -- Items
    local numItems = GetNumQuestLogRewards and GetNumQuestLogRewards(questID) or 0
    for i = 1, numItems do
        local name, _, count, quality = GetQuestLogRewardInfo(i, questID)
        if name then
            local label = name
            if count and count > 1 then label = label .. " ×" .. count end
            local r, g, b = 1, 1, 1
            if quality and GetItemQualityColor then
                r, g, b = GetItemQualityColor(quality)
            end
            tip:AddLine(label, r, g, b)
            hasReward = true
        end
    end

    -- Currencies
    local numCur = GetNumQuestLogRewardCurrencies and GetNumQuestLogRewardCurrencies(questID) or 0
    for i = 1, numCur do
        local name, _, count = GetQuestLogRewardCurrencyInfo(i, questID)
        if name then
            local label = name
            if count and count > 1 then label = label .. " ×" .. count end
            tip:AddLine(label, 0.85, 0.85, 1.0)
            hasReward = true
        end
    end

    return hasReward
end

-- Show tooltip for a world quest. `owner` is the frame to anchor against
-- (typically a pin button or tracker row). Caller is responsible for hiding
-- via GameTooltip:Hide() in OnLeave.
function T:Show(owner, questID)
    if not (owner and questID) then return end
    if not GameTooltip then return end

    if C_TaskQuest and C_TaskQuest.RequestPreloadRewardData then
        C_TaskQuest.RequestPreloadRewardData(questID)
    end

    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")

    GameTooltip:SetText(questTitle(questID), 1.0, 0.82, 0.0, 1, true)

    local fname = factionName(questID)
    if fname then
        GameTooltip:AddLine(fname, 0.7, 0.7, 0.7)
    end

    addObjectives(GameTooltip, questID)

    if addRewards(GameTooltip, questID) then
        GameTooltip:AddLine(" ")
    end

    local mins = C_TaskQuest and C_TaskQuest.GetQuestTimeLeftMinutes
                 and C_TaskQuest.GetQuestTimeLeftMinutes(questID)
    if mins and mins > 0 then
        local r, g, b = Util.WQTimeColor(mins)
        GameTooltip:AddLine("Time Left: " .. Util.WQTimeLong(mins), r, g, b)
    end

    GameTooltip:Show()
end

function T:Hide()
    if GameTooltip then GameTooltip:Hide() end
end
