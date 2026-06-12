-- Core/QuestRewards.lua
-- Shared quest-tooltip content builder: objectives + rewards, with an inline
-- "is this gear an upgrade?" comparison for every equippable reward (including
-- each option of a pick-one-of-N choice). Used by both the World Quest tooltip
-- (Modules/WorldQuests/Tooltip.lua) and the regular-quest tracker tooltip
-- (Modules/Tracker/RewardTooltip.lua) so the reward rendering lives in one place.
--
-- Reward APIs (GetQuestLogRewardInfo / GetNumQuestLogChoices / GetQuestLogItemLink)
-- all accept a trailing questID, so they work for any quest whose reward data the
-- client has loaded — not just the selection-stateful "current" quest. Every read
-- degrades gracefully: a missing reward link or uncached item level simply skips
-- that comparison line (the item name still shows), and a re-hover picks it up
-- once the data has streamed in.

local _, ns = ...

local QR = ns:RegisterSubsystem("QuestRewards", {})

local L = ns.L

-- INVTYPE_* (item equipLoc) -> the inventory slot name(s) GetInventorySlotInfo
-- resolves to a numeric slotID. Two-slot types (rings, trinkets, one-hand
-- weapons) list both candidates; we compare the reward against the LOWER-ilvl
-- equipped piece, since that's the one a player would actually replace.
-- Cosmetic slots (shirt/tabard) are intentionally absent: they have no
-- meaningful item level, so "is it an upgrade?" is meaningless for them.
local EQUIP_SLOTS = {
    INVTYPE_HEAD           = { "HEADSLOT" },
    INVTYPE_NECK           = { "NECKSLOT" },
    INVTYPE_SHOULDER       = { "SHOULDERSLOT" },
    INVTYPE_CLOAK          = { "BACKSLOT" },
    INVTYPE_CHEST          = { "CHESTSLOT" },
    INVTYPE_ROBE           = { "CHESTSLOT" },
    INVTYPE_WAIST          = { "WAISTSLOT" },
    INVTYPE_LEGS           = { "LEGSSLOT" },
    INVTYPE_FEET           = { "FEETSLOT" },
    INVTYPE_WRIST          = { "WRISTSLOT" },
    INVTYPE_HAND           = { "HANDSSLOT" },
    INVTYPE_FINGER         = { "FINGER0SLOT", "FINGER1SLOT" },
    INVTYPE_TRINKET        = { "TRINKET0SLOT", "TRINKET1SLOT" },
    INVTYPE_WEAPON         = { "MAINHANDSLOT", "SECONDARYHANDSLOT" },
    INVTYPE_2HWEAPON       = { "MAINHANDSLOT" },
    INVTYPE_WEAPONMAINHAND = { "MAINHANDSLOT" },
    INVTYPE_WEAPONOFFHAND  = { "SECONDARYHANDSLOT" },
    INVTYPE_RANGED         = { "MAINHANDSLOT" },
    INVTYPE_RANGEDRIGHT    = { "MAINHANDSLOT" },
    INVTYPE_SHIELD         = { "SECONDARYHANDSLOT" },
    INVTYPE_HOLDABLE       = { "SECONDARYHANDSLOT" },
}

-- Resolved slotID cache keyed by the slot name string. GetInventorySlotInfo is
-- stable for the life of the client, so resolve each name once.
local _slotID = {}
local function slotID(name)
    local id = _slotID[name]
    if id == nil then
        id = (GetInventorySlotInfo and GetInventorySlotInfo(name)) or false
        _slotID[name] = id
    end
    return id or nil
end

-- Synchronous equipLoc lookup (no async item-load race) — mirrors Rewards.lua's
-- defensive C_Item-or-global pattern.
local function equipLocOf(itemID)
    if not itemID then return nil end
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not instant then return nil end
    return select(4, instant(itemID))
end

-- Effective (upgraded/scaled) item level of an item link, or nil if the client
-- hasn't cached it yet. Equipped items are always cached; a reward link may not
-- be, in which case we simply skip its comparison line.
local function detailedIlvl(link)
    if not (link and C_Item and C_Item.GetDetailedItemLevelInfo) then return nil end
    return C_Item.GetDetailedItemLevelInfo(link)
end

-- Short display label per equip slot, shown next to the equipped ilvl. Kept as
-- our own localizable strings rather than relying on Blizzard's INVTYPE_* global
-- strings (whose exact keys vary); an unmapped equipLoc just yields no label.
local SLOT_LABEL = {
    INVTYPE_HEAD           = "Head",
    INVTYPE_NECK           = "Neck",
    INVTYPE_SHOULDER       = "Shoulder",
    INVTYPE_CLOAK          = "Back",
    INVTYPE_CHEST          = "Chest",
    INVTYPE_ROBE           = "Chest",
    INVTYPE_WAIST          = "Waist",
    INVTYPE_LEGS           = "Legs",
    INVTYPE_FEET           = "Feet",
    INVTYPE_WRIST          = "Wrist",
    INVTYPE_HAND           = "Hands",
    INVTYPE_FINGER         = "Finger",
    INVTYPE_TRINKET        = "Trinket",
    INVTYPE_WEAPON         = "Weapon",
    INVTYPE_2HWEAPON       = "Two-Hand",
    INVTYPE_WEAPONMAINHAND = "Main Hand",
    INVTYPE_WEAPONOFFHAND  = "Off Hand",
    INVTYPE_RANGED         = "Ranged",
    INVTYPE_RANGEDRIGHT    = "Ranged",
    INVTYPE_SHIELD         = "Off Hand",
    INVTYPE_HOLDABLE       = "Off Hand",
}
local function slotLabel(equipLoc)
    local s = SLOT_LABEL[equipLoc]
    return s and L[s] or ""
end

-- Lowest equipped item level across the candidate slots for an equipLoc, plus
-- whether ANY candidate slot is empty. Comparing against the lowest matches what
-- the player would replace; an empty slot means the reward is a guaranteed fill.
local function equippedComparison(equipLoc)
    local slots = EQUIP_SLOTS[equipLoc]
    if not slots then return nil end          -- not comparable gear

    local lowest, hasEmpty
    for i = 1, #slots do
        local id = slotID(slots[i])
        if id then
            local link = GetInventoryItemLink and GetInventoryItemLink("player", id)
            if link then
                local il = detailedIlvl(link)
                if il and (not lowest or il < lowest) then lowest = il end
            else
                hasEmpty = true
            end
        end
    end
    return { lowest = lowest, hasEmpty = hasEmpty, multi = #slots > 1 }
end

-- Append the comparison sub-lines for an equippable reward. `rewardIlvl` is the
-- character-scaled item level of the reward. Silently no-ops for non-gear or when
-- we don't know the reward's ilvl (better to show nothing than a half-comparison).
local function addComparison(tip, equipLoc, rewardIlvl)
    if not (equipLoc and rewardIlvl and rewardIlvl > 0) then return end
    local cmp = equippedComparison(equipLoc)
    if not cmp then return end

    -- An empty candidate slot means the reward can be equipped for free (it
    -- fills the gap rather than replacing anything) — a strict gain, even if a
    -- paired ring/trinket slot is occupied.
    if cmp.hasEmpty then
        tip:AddLine("    " .. L["Equip — empty slot"], 0.2, 1.0, 0.2)
        return
    end
    if not cmp.lowest then return end          -- couldn't read equipped ilvl

    local label = slotLabel(equipLoc)
    tip:AddLine(("    " .. L["Equipped: ilvl %d"]):format(cmp.lowest)
                .. (label ~= "" and ("  (" .. label .. ")") or ""), 0.7, 0.7, 0.7)

    local delta = rewardIlvl - cmp.lowest
    if delta > 0 then
        tip:AddLine(("    " .. L["+%d ilvl upgrade"]):format(delta), 0.2, 1.0, 0.2)
    elseif delta < 0 then
        tip:AddLine(("    " .. L["%d ilvl lower"]):format(delta), 1.0, 0.3, 0.3)
    else
        tip:AddLine("    " .. L["Same item level"], 1.0, 0.82, 0.0)
    end
end

-- One reward item line: name colored by quality, with its ilvl when equippable,
-- followed by the gear comparison. `kind` is "reward" or "choice" (selects the
-- right GetQuestLogItemLink type). `rewardIlvl` may be passed in (mandatory
-- rewards expose a scaled ilvl directly); otherwise we derive it from the link.
local function addItem(tip, questID, kind, index, name, count, quality, itemID, rewardIlvl)
    local equipLoc = equipLocOf(itemID)
    -- Mandatory rewards already carry a scaled ilvl; only choice rewards need the
    -- link resolved to read theirs.
    if not rewardIlvl then
        local link = GetQuestLogItemLink and GetQuestLogItemLink(kind, index, questID)
        if link then rewardIlvl = detailedIlvl(link) end
    end

    local label = name
    if count and count > 1 then label = label .. " ×" .. count end
    if equipLoc and EQUIP_SLOTS[equipLoc] and rewardIlvl and rewardIlvl > 0 then
        label = label .. ("  |cff999999" .. L["ilvl %d"] .. "|r"):format(rewardIlvl)
    end

    local r, g, b = 1, 1, 1
    if quality and GetItemQualityColor then r, g, b = GetItemQualityColor(quality) end
    tip:AddLine(label, r, g, b)

    addComparison(tip, equipLoc, rewardIlvl)
end

-- Append quest objectives (- bullet per line, green when finished). Returns true
-- if any line was added.
function QR:RenderObjectives(tip, questID)
    if not (tip and questID and C_QuestLog and C_QuestLog.GetQuestObjectives) then return false end
    local objs = C_QuestLog.GetQuestObjectives(questID)
    if not (objs and #objs > 0) then return false end
    local any = false
    for i = 1, #objs do
        local o = objs[i]
        if o and o.text and o.text ~= "" then
            local r, g, b = 0.95, 0.95, 0.95
            if o.finished then r, g, b = 0.40, 0.85, 0.40 end
            tip:AddLine("- " .. o.text, r, g, b, true)
            any = true
        end
    end
    return any
end

-- Append the full rewards block: money, XP, mandatory items (with gear compare),
-- choice items (with gear compare), currencies. Returns true if anything was added.
function QR:RenderRewards(tip, questID)
    if not (tip and questID) then return false end

    -- Nudge the client to load reward data for this quest; harmless if already
    -- loaded or unsupported on the current client.
    if C_TaskQuest and C_TaskQuest.RequestPreloadRewardData then
        C_TaskQuest.RequestPreloadRewardData(questID)
    end

    local hasReward = false

    -- Money
    local money = GetQuestLogRewardMoney and GetQuestLogRewardMoney(questID) or 0
    if money and money > 0 then
        tip:AddLine((GetCoinTextureString and GetCoinTextureString(money)) or tostring(money), 1, 1, 1)
        hasReward = true
    end

    -- XP
    local xp = GetQuestLogRewardXP and GetQuestLogRewardXP(questID) or 0
    if xp and xp > 0 then
        tip:AddLine((L["%d XP"]):format(xp), 1, 1, 1)
        hasReward = true
    end

    -- Mandatory item rewards (everyone gets these). GetQuestLogRewardInfo's 7th
    -- return is the reward's character-scaled item level — exactly what we want
    -- for the comparison, no async link load needed.
    local numItems = GetNumQuestLogRewards and GetNumQuestLogRewards(questID) or 0
    for i = 1, numItems do
        local name, _, count, quality, _, itemID, ilvl = GetQuestLogRewardInfo(i, questID)
        if name then
            addItem(tip, questID, "reward", i, name, count, quality, itemID, ilvl)
            hasReward = true
        end
    end

    -- Choice rewards (pick one). GetQuestLogChoiceInfo doesn't expose a scaled
    -- ilvl, so addItem derives it from the choice's item link.
    local numChoices = GetNumQuestLogChoices and GetNumQuestLogChoices(questID) or 0
    if numChoices and numChoices > 0 then
        tip:AddLine(L["Choose one:"], 0.9, 0.8, 0.3)
        for i = 1, numChoices do
            local name, _, count, quality, _, itemID = GetQuestLogChoiceInfo(i, questID)
            if name then
                addItem(tip, questID, "choice", i, name, count, quality, itemID, nil)
                hasReward = true
            end
        end
    end

    -- Currencies (AP/anima, faction tokens, zone resources).
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
