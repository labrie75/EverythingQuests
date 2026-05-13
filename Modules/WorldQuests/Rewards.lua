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

function R:Classify(questID)
    if not questID then return FALLBACK end

    -- 1. Money — most common WQ reward, cheap to read.
    local money = GetQuestLogRewardMoney and GetQuestLogRewardMoney(questID) or 0
    if money and money > 0 then
        return {
            category   = R.FILTER.GOLD,
            icon       = "Interface\\MoneyFrame\\UI-MoneyIcons",
            iconCoords = { 0, 0.25, 0, 1 },               -- gold-coin slice of the money atlas
            text       = (GetCoinTextureString and GetCoinTextureString(money)) or tostring(money),
        }
    end

    -- 2. Items — gear, conduits, profession mats. Take the first item only;
    --    most WQs only offer one.
    local numItems = GetNumQuestLogRewards and GetNumQuestLogRewards(questID) or 0
    if numItems and numItems > 0 then
        local name, texture, count, quality = GetQuestLogRewardInfo(1, questID)
        if name and texture then
            local label = name
            if count and count > 1 then label = label .. " ×" .. count end
            return {
                category   = R.FILTER.GEAR,
                icon       = texture,
                iconCoords = { 0.08, 0.92, 0.08, 0.92 },  -- crop standard icon border
                quality    = quality,
                text       = label,
            }
        end
    end

    -- 3. Currencies — zone resources, faction tokens, etc.
    local numCur = GetNumQuestLogRewardCurrencies and GetNumQuestLogRewardCurrencies(questID) or 0
    if numCur and numCur > 0 then
        local name, texture, count = GetQuestLogRewardCurrencyInfo(1, questID)
        if name then
            local label = name
            if count and count > 1 then label = label .. " ×" .. count end
            return {
                category   = looksLikeReputationCurrency(name) and R.FILTER.REPUTATION or R.FILTER.RESOURCE,
                icon       = texture or FALLBACK.icon,
                iconCoords = { 0.08, 0.92, 0.08, 0.92 },
                text       = label,
            }
        end
    end

    return FALLBACK
end
