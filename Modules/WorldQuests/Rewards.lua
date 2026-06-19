local _, ns = ...

local R = ns:RegisterSubsystem("WQRewards", {})

R.FILTER = {
    GOLD            = "gold",
    GEAR            = "gear",
    REPUTATION      = "rep",
    RESOURCE        = "resource",
    ARTIFACT_POWER  = "ap",
    PROFESSION      = "profession",
    PVP             = "pvp",
    PET_BATTLE      = "pet",
    OTHER           = "other",
}

local FALLBACK = {
    category   = R.FILTER.OTHER,
    atlas      = "worldquest-questmarker-questbang",
    text       = "",
}

function R:ApplyToTexture(texture, reward)
    if not texture then return end
    if not reward then
        texture:SetAtlas(FALLBACK.atlas)
        texture:SetTexCoord(0, 1, 0, 1)
        return
    end
    if reward.atlas then
        texture:SetAtlas(reward.atlas)
        texture:SetTexCoord(0, 1, 0, 1)
    elseif reward.icon then
        texture:SetTexture(reward.icon)
        if reward.iconCoords then
            texture:SetTexCoord(reward.iconCoords[1], reward.iconCoords[2],
                                reward.iconCoords[3], reward.iconCoords[4])
        else
            texture:SetTexCoord(0, 1, 0, 1)
        end
    else
        texture:SetAtlas(FALLBACK.atlas)
        texture:SetTexCoord(0, 1, 0, 1)
    end
end

local function looksLikeReputationCurrency(name)
    if not name then return false end
    return name:find("Reputation") or name:find("Renown") or name:find("[Rr]ep[utation]*$")
end

local function looksLikeArtifactPower(name)
    if not name then return false end
    return name:find("Anima") or name:find("Resonance") or name:find("Artifact Power")
end

local function tagCategory(questID)
    local info = C_QuestLog and C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(questID)
    local wqType = info and info.worldQuestType
    local T      = Enum and Enum.QuestTagType
    if not (wqType and T) then return nil end
    if wqType == T.PvP        then return R.FILTER.PVP end
    if wqType == T.PetBattle  then return R.FILTER.PET_BATTLE end
    if wqType == T.Profession then return R.FILTER.PROFESSION end
    return nil
end

local function classifyItem(questID, name, texture, count, quality)
    local itemID = select(6, GetQuestLogRewardInfo(1, questID))
    local category = R.FILTER.GEAR

    if itemID then
        if C_Item and C_Item.IsAnimaItemByID and C_Item.IsAnimaItemByID(itemID) then
            category = R.FILTER.ARTIFACT_POWER
        elseif looksLikeArtifactPower(name) then
            category = R.FILTER.ARTIFACT_POWER
        else
            -- Guard with an `if`, not `and`: `f and f(x)` truncates a
            -- multi-return to one value, nil-ing equipLoc/classID.
            local equipLoc, classID
            local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
            if instant then
                local _, _, _, el, _, cid = instant(itemID)
                equipLoc, classID = el, cid
            end
            local TG = Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods
            if equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP" then
                category = R.FILTER.GEAR
            elseif TG and classID == TG then
                category = R.FILTER.RESOURCE
            elseif count and count > 1 then
                category = R.FILTER.RESOURCE
            else
                category = R.FILTER.GEAR
            end
        end
    end

    local label = name
    if count and count > 1 then label = label .. " ×" .. count end
    return {
        category   = category,
        icon       = texture,
        iconCoords = { 0.08, 0.92, 0.08, 0.92 },
        quality    = quality,
        text       = label,
    }
end

local function classify(questID)
    if not questID then return FALLBACK end

    local tagCat = tagCategory(questID)

    local money = GetQuestLogRewardMoney and GetQuestLogRewardMoney(questID) or 0
    if money and money > 0 then
        return {
            category   = tagCat or R.FILTER.GOLD,
            icon       = "Interface\\MoneyFrame\\UI-MoneyIcons",
            iconCoords = { 0, 0.25, 0, 1 },
            text       = (GetCoinTextureString and GetCoinTextureString(money)) or tostring(money),
        }
    end

    local numItems = GetNumQuestLogRewards and GetNumQuestLogRewards(questID) or 0
    if numItems and numItems > 0 then
        local name, texture, count, quality = GetQuestLogRewardInfo(1, questID)
        if name and texture then
            local r = classifyItem(questID, name, texture, count, quality)
            if tagCat then r.category = tagCat end
            return r
        end
    end

    local numCur = GetNumQuestLogRewardCurrencies and GetNumQuestLogRewardCurrencies(questID) or 0
    if numCur and numCur > 0 then
        local name, texture, count = GetQuestLogRewardCurrencyInfo(1, questID)
        if name then
            local label = name
            if count and count > 1 then label = label .. " ×" .. count end
            local cat = R.FILTER.RESOURCE
            if looksLikeArtifactPower(name)         then cat = R.FILTER.ARTIFACT_POWER
            elseif looksLikeReputationCurrency(name) then cat = R.FILTER.REPUTATION end
            return {
                category   = tagCat or cat,
                icon       = texture or FALLBACK.icon,
                iconCoords = { 0.08, 0.92, 0.08, 0.92 },
                text       = label,
            }
        end
    end

    if tagCat then
        return { category = tagCat, atlas = FALLBACK.atlas, text = "" }
    end
    return FALLBACK
end

local resultCache = {}

local function rewardDataReady(questID)
    if not HaveQuestRewardData then return true end
    return HaveQuestRewardData(questID) and true or false
end

function R:Classify(questID)
    if not questID then return FALLBACK end

    local cached = resultCache[questID]
    if cached then return cached end

    local result = classify(questID)

    -- Only memoize a fully-resolved reward. Before the client has the
    -- reward data, classify() returns the FALLBACK placeholder (or a
    -- tag-only stub); caching that would freeze the pin on the yellow
    -- "!" forever. Re-classifying an un-loaded quest each refresh is
    -- cheap and self-corrects the instant the data arrives.
    if result ~= FALLBACK and rewardDataReady(questID) then
        resultCache[questID] = result
    end
    return result
end

function R:Invalidate(questID)
    if questID then
        resultCache[questID] = nil
    else
        wipe(resultCache)
    end
end

function R:OnInitialize()
    local Events = ns:GetSubsystem("Events")
    if Events then
        -- A finished/abandoned quest's ID can be recycled by a future
        -- quest; clear it so the next quest under that ID re-parses.
        local function drop(_, questID)
            if questID then resultCache[questID] = nil end
        end
        Events:On("QUEST_TURNED_IN", drop)
        Events:On("QUEST_REMOVED",   drop)
    end

    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(600, function() wipe(resultCache) end)
    end
end
