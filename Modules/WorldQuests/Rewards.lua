-- Modules/WorldQuests/Rewards.lua
-- Classifies a world quest by its primary reward.
--
-- Returns a flat result table with the fields the pin renderer + tooltip
-- need: category (matches DB filter keys), icon texture/coords, display
-- text. We pick ONE primary reward per quest — most WQs have a single
-- meaningful drop and stacking visual indicators per pin gets noisy.
--
-- Reward APIs (GetQuestLogRewardMoney / GetNumQuestLogRewards / etc.) are
-- selection-stateful in their classic form, but their per-questID variants
-- (passing questID as the trailing arg) work for any quest the client has
-- loaded reward data for. C_TaskQuest.RequestPreloadRewardData is the
-- handshake that triggers the load — the provider calls it before reading.

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

-- Default visuals used when the reward returns nothing recognisable. Keeps
-- the pin from rendering as a black square if data hasn't preloaded yet.
-- Atlas instead of `Interface\Icons\...` because retail no longer ships the
-- loose icon files; atlases are bundled in the client data files and always
-- resolve. `worldquest-questmarker-questbang` is the yellow ! that Blizzard
-- uses for available world quests — clean, readable, never broken.
local FALLBACK = {
    category   = R.FILTER.OTHER,
    atlas      = "worldquest-questmarker-questbang",
    text       = "",
}

-- Apply a classified reward's visual onto a Texture frame. Prefers atlas
-- (always resolves) over icon path (may not ship on minimal installs).
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

-- Heuristic: many faction-rep tokens have "Reputation" in the name. The
-- canonical way is to inspect currencyID against a known faction-token list,
-- but that list shifts every patch — the name check covers the common case
-- without hard-coding IDs that go stale.
local function looksLikeReputationCurrency(name)
    if not name then return false end
    return name:find("Reputation") or name:find("Renown") or name:find("[Rr]ep[utation]*$")
end

-- Anima / resonance / artifact-style "power" currencies and items. Name-based
-- because the canonical currency IDs rotate every patch; the words are stable.
local function looksLikeArtifactPower(name)
    if not name then return false end
    return name:find("Anima") or name:find("Resonance") or name:find("Artifact Power")
end

-- Quest-tag classification (PvP / Pet Battle / Profession). These are
-- authoritative regardless of the reward, so they win over reward parsing.
-- Dungeon/Raid/Invasion fall through — the reward is the more useful signal
-- and we have no dedicated category for them.
local function tagCategory(questID)
    local info = C_QuestLog and C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(questID)
    local wqt  = info and info.worldQuestType
    local T    = Enum and Enum.QuestTagType
    if not (wqt and T) then return nil end
    if wqt == T.PvP        then return R.FILTER.PVP end
    if wqt == T.PetBattle  then return R.FILTER.PET_BATTLE end
    if wqt == T.Profession then return R.FILTER.PROFESSION end
    return nil
end

-- Equippable gear vs. stacked trade goods vs. anima/AP item. Uses the
-- synchronous GetItemInfoInstant (no async load race) for equip slot/class.
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
                category = R.FILTER.RESOURCE        -- profession / trade materials
            elseif count and count > 1 then
                category = R.FILTER.RESOURCE        -- stacked = consumable/mats
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
        iconCoords = { 0.08, 0.92, 0.08, 0.92 },     -- crop standard icon border
        quality    = quality,
        text       = label,
    }
end

function R:Classify(questID)
    if not questID then return FALLBACK end

    -- 1. Quest tag — PvP / Pet Battle / Profession are definitive.
    local tagCat = tagCategory(questID)

    -- 2. Money — most common WQ reward, cheap to read.
    local money = GetQuestLogRewardMoney and GetQuestLogRewardMoney(questID) or 0
    if money and money > 0 then
        return {
            category   = tagCat or R.FILTER.GOLD,
            icon       = "Interface\\MoneyFrame\\UI-MoneyIcons",
            iconCoords = { 0, 0.25, 0, 1 },               -- gold-coin slice of the money atlas
            text       = (GetCoinTextureString and GetCoinTextureString(money)) or tostring(money),
        }
    end

    -- 3. Items — gear, anima, profession mats. First item only; most WQs
    --    offer one. classifyItem distinguishes equip / trade / AP.
    local numItems = GetNumQuestLogRewards and GetNumQuestLogRewards(questID) or 0
    if numItems and numItems > 0 then
        local name, texture, count, quality = GetQuestLogRewardInfo(1, questID)
        if name and texture then
            local r = classifyItem(questID, name, texture, count, quality)
            if tagCat then r.category = tagCat end
            return r
        end
    end

    -- 4. Currencies — AP/anima, faction tokens, zone resources.
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

    -- 5. No reward parsed. If the tag still told us something, honour it
    --    rather than dumping to "other".
    if tagCat then
        return { category = tagCat, atlas = FALLBACK.atlas, text = "" }
    end
    return FALLBACK
end
