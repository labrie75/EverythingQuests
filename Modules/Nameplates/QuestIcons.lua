-- Modules/Nameplates/QuestIcons.lua
-- Quest icons on NPC nameplates: a "!" (skull for kill objectives, a chat
-- bubble for talk-to objectives, the quest's item icon for use-item ones)
-- plus the REMAINING count or percent. Lets you see quest objectives out in
-- the 3D world instead of guessing which mob counts.
--
-- This mirrors ElvUI's nameplate quest icons but is built independently. It
-- defaults OFF when ElvUI is loaded (ElvUI shows its own, so we'd double up);
-- otherwise ON. Toggle on the General options tab.
--
-- DETECTION (two-source join, the model ElvUI uses):
--   1. activeQuests cache — rebuilt from C_QuestLog on quest-log changes.
--      Objectives are keyed by their DISPLAY TEXT -> { value, type, isPercent,
--      itemTexture }. value is REMAINING (numRequired - numFulfilled), or
--      (100 - progress) for progressbar/area objectives. Finished objectives
--      are skipped so completed steps show nothing.
--   2. Per-unit tooltip scan via C_TooltipInfo.GetUnit — walk the lines by
--      Enum.TooltipDataLineType (QuestPlayer / QuestTitle / QuestObjective) to
--      learn which of MY quests/objectives this specific NPC belongs to, then
--      look the objective text up in the cache. The objective text is the join
--      key (identical between the tooltip and C_QuestLog on retail).
-- The tooltip scan result is cached per unit GUID, so we only re-scan when a
-- new mob appears on a plate or the quest log changes — never per frame.

local _, ns = ...

local QI = ns:RegisterSubsystem("NameplateQuestIcons", {})

local ICON_SIZE = 24
local SPACING   = 3

-- Tooltip line-type enum (numeric fallback from a live /eqs autopopup-style
-- probe of ElvUI: 17 = QuestTitle, 8 = QuestObjective, 18 = QuestPlayer).
local LT = Enum and Enum.TooltipDataLineType
local QUEST_TITLE     = (LT and LT.QuestTitle)     or 17
local QUEST_OBJECTIVE = (LT and LT.QuestObjective) or 8
local QUEST_PLAYER    = (LT and LT.QuestPlayer)    or 18

-- Midnight can hand back "secret values" from restricted APIs that error if
-- indexed/compared. Guard tooltip text + GUID reads through this.
local _issecret = _G.issecretvalue
local function ok(v)
    if _issecret then return not _issecret(v) end
    return true
end

-- enUS objective-verb classification (icon choice only; the COUNT never
-- depends on this). Other locales fall through to the generic "!".
local KILL_WORDS = { "slain", "slay", "kill", "defeat", "destroy", "eliminat", "wound" }
local CHAT_WORDS = { "speak", "talk" }
local function objType(text, hasItem)
    if hasItem then return "ITEM" end
    if not text then return "DEFAULT" end
    local l = text:lower()
    for i = 1, #KILL_WORDS do if l:find(KILL_WORDS[i], 1, true) then return "KILL" end end
    for i = 1, #CHAT_WORDS do if l:find(CHAT_WORDS[i], 1, true) then return "CHAT" end end
    return "DEFAULT"
end

local function elvUILoaded()
    local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G["IsAddOnLoaded"]
    return (f and f("ElvUI")) and true or false
end

-- ── Quest objective cache ─────────────────────────────────────────────
-- [questTitle] = { [objectiveText] = { value, type, isPercent, itemTexture } }
local activeQuests = {}

local function rebuildCache()
    wipe(activeQuests)
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetQuestObjectives) then
        return
    end
    local n = C_QuestLog.GetNumQuestLogEntries() or 0
    for i = 1, n do
        local info = C_QuestLog.GetInfo and C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID and info.title then
            local objectives = C_QuestLog.GetQuestObjectives(info.questID)
            if objectives then
                local itemTexture
                if GetQuestLogSpecialItemInfo then
                    local _, tex = GetQuestLogSpecialItemInfo(i)   -- index-based; tex = icon
                    itemTexture = tex
                end
                local objMap
                for _, o in ipairs(objectives) do
                    local text = (not o.finished) and o.text
                    if text and text ~= "" then
                        local entry
                        if o.type == "progressbar" then
                            local p = tonumber(text:match("([%d%.]+)%%"))
                            if p and p <= 100 then
                                entry = { value = math.ceil(100 - p), isPercent = true }
                            end
                        else
                            local need, have = o.numRequired, o.numFulfilled
                            if need and have then
                                local diff = math.floor(need - have)
                                if diff > 0 then entry = { value = diff, isPercent = false } end
                            end
                        end
                        if entry then
                            entry.type        = objType(text, itemTexture)
                            entry.itemTexture = itemTexture
                            objMap = objMap or {}
                            objMap[text] = entry
                        end
                    end
                end
                if objMap then activeQuests[info.title] = objMap end
            end
        end
    end
end

-- ── Per-unit tooltip scan ─────────────────────────────────────────────
-- Fills `out` (reused per plate, no per-scan allocation) with references to
-- the cache entries this unit matches. Returns the count.
local function scanInto(unit, out)
    wipe(out)
    if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return 0 end
    local data = C_TooltipInfo.GetUnit(unit)
    local lines = data and data.lines
    if not lines then return 0 end

    local count, notMine, objMap = 0, false, nil
    for i = 2, #lines do
        local line = lines[i]
        local text = line and line.leftText
        if ok(text) and text and text ~= "" then
            local lt = line.type
            if lt == QUEST_PLAYER then
                notMine = (text ~= QI.playerName)
            elseif not notMine then
                if lt == QUEST_TITLE then
                    objMap = activeQuests[text]
                elseif lt == QUEST_OBJECTIVE and objMap then
                    local entry = objMap[text]
                    if entry then
                        count = count + 1
                        out[count] = entry
                    end
                end
            end
        end
    end
    return count
end

-- ── Icon frame per nameplate ──────────────────────────────────────────
local TEX = {
    DEFAULT = { atlas = "SmallQuestBang" },
    KILL    = { tex   = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull" },
    CHAT    = { tex   = "Interface\\WorldMap\\ChatBubble_64.PNG", coord = { 0, 0.5, 0.5, 1 } },
    ITEM    = { item  = true },
}

local function buildSlot(frame)
    local ic = frame:CreateTexture(nil, "OVERLAY")
    ic:SetSize(ICON_SIZE, ICON_SIZE)
    ic:Hide()
    ic.text = frame:CreateFontString(nil, "OVERLAY")
    ic.text:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
    ic.text:SetTextColor(1, 0.94, 0.6)
    -- Anchored just to the right of the icon, vertically centered, in render().
    ic.text:SetPoint("LEFT", ic, "RIGHT", 2, 0)
    ic.text:Hide()
    return ic
end

local function getIconFrame(plate)
    local f = plate.EQQuestIcons
    if f then return f end
    f = CreateFrame("Frame", nil, plate)
    f:SetFrameStrata("HIGH")
    f:SetSize(ICON_SIZE, ICON_SIZE)
    -- Just to the right of the nameplate, vertically centered on it. The count
    -- then sits just to the right of the icon (see render).
    f:SetPoint("LEFT", plate, "RIGHT", 4, 0)
    f.slots = { buildSlot(f), buildSlot(f), buildSlot(f), buildSlot(f) }
    plate.EQQuestIcons = f
    return f
end

local function hideFrame(plate)
    local f = plate and plate.EQQuestIcons
    if not f then return end
    for i = 1, #f.slots do f.slots[i]:Hide(); f.slots[i].text:SetText(""); f.slots[i].text:Hide() end
    f:Hide()
    f.guid = nil
end

local function render(plate, list, count)
    local f = getIconFrame(plate)
    for i = 1, #f.slots do
        f.slots[i]:Hide()
        f.slots[i].text:SetText("")
        f.slots[i].text:Hide()
    end
    if not count or count == 0 then f:Hide(); return end

    -- Lay icons out left -> right starting at the plate's right edge; each
    -- icon's count sits just to its right, and the next icon clears it.
    local x, shown = 0, 0
    for i = 1, count do
        local q = list[i]
        if q and (q.isPercent or (q.value and q.value > 0)) then
            local ic = f.slots[shown + 1]
            if not ic then break end          -- cap at the pre-built slot count
            shown = shown + 1

            local def = TEX[q.type] or TEX.DEFAULT
            if def.atlas then
                ic:SetAtlas(def.atlas); ic:SetTexCoord(0, 1, 0, 1)
            elseif def.item and q.itemTexture then
                ic:SetTexture(q.itemTexture); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            elseif def.tex then
                ic:SetTexture(def.tex)
                if def.coord then ic:SetTexCoord(unpack(def.coord)) else ic:SetTexCoord(0, 1, 0, 1) end
            else
                ic:SetAtlas("SmallQuestBang"); ic:SetTexCoord(0, 1, 0, 1)
            end

            ic:ClearAllPoints()
            ic:SetPoint("LEFT", f, "LEFT", x, 0)
            ic:Show()

            local advance = ICON_SIZE
            -- Count shown only when >1 (or a percent); never on chat (talk)
            -- objectives. Matches Blizzard/ElvUI so single-kill mobs don't read "1".
            if q.type ~= "CHAT" and (q.isPercent or (q.value and q.value > 1)) then
                ic.text:SetText(q.isPercent and (q.value .. "%") or q.value)
                ic.text:Show()
                advance = advance + 2 + math.ceil(ic.text:GetStringWidth())
            end
            x = x + advance + SPACING
        end
    end

    if shown > 0 then
        f:SetWidth(math.max(1, x - SPACING))
        f:Show()
    else
        f:Hide()
    end
end

-- ── Update flow ───────────────────────────────────────────────────────
local activePlates = {}   -- [unitToken] = true (visible nameplates)

local function updatePlate(unit, event)
    if not (QI.enabled and unit) then return end
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end
    if UnitIsPlayer(unit) then hideFrame(plate); return end

    local guid = UnitGUID(unit)
    if not ok(guid) then return end

    local f = getIconFrame(plate)
    f.list = f.list or {}
    local count
    if f.guid ~= guid then
        f.guid = guid                       -- new mob on this plate → scan
        count = scanInto(unit, f.list)
        f.count = count
    elseif event == "QUEST_LOG_UPDATE" then
        count = scanInto(unit, f.list)       -- progress may have changed → re-scan
        f.count = count
    else
        count = f.count                      -- same mob, cosmetic event → reuse
    end
    render(plate, f.list, count)
end

local function refreshAllPlates(event)
    for unit in pairs(activePlates) do updatePlate(unit, event) end
end

-- Coalesce the (potentially bursty) quest-log refresh: rebuild the cache once,
-- then re-scan visible plates. Hoisted so Events:Throttle reuses it.
local function questLogRefresh()
    rebuildCache()
    refreshAllPlates("QUEST_LOG_UPDATE")
end

-- Event handlers (file-scope so Enable/Disable can On/Off the exact refs).
local function onPlateAdded(_, unit)
    if not unit then return end
    activePlates[unit] = true
    updatePlate(unit, "NAME_PLATE_UNIT_ADDED")
end
local function onPlateRemoved(_, unit)
    if not unit then return end
    activePlates[unit] = nil
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    hideFrame(plate)
end
local function onQuestLogUpdate()
    local Events = ns:GetSubsystem("Events")
    if Events and Events.Throttle then
        Events:Throttle("nameplateQuestIcons", 0.2, questLogRefresh)
    else
        questLogRefresh()
    end
end

local REGISTERED = {
    NAME_PLATE_UNIT_ADDED   = onPlateAdded,
    NAME_PLATE_UNIT_REMOVED = onPlateRemoved,
    QUEST_LOG_UPDATE        = onQuestLogUpdate,
    QUEST_ACCEPTED          = onQuestLogUpdate,
    QUEST_REMOVED           = onQuestLogUpdate,
}

function QI:IsEnabled()
    local DB = ns:GetSubsystem("DB")
    local v = DB and DB.db.profile.general.questNameplateIcons
    if v == nil then return not elvUILoaded() end   -- auto: on unless ElvUI present
    return v and true or false
end

function QI:ApplyEnabled()
    local on = self:IsEnabled()
    if on == self.enabled then return end
    self.enabled = on

    local Events = ns:GetSubsystem("Events")
    if not Events then return end
    if on then
        for event, fn in pairs(REGISTERED) do Events:On(event, fn) end
        rebuildCache()
        -- Pick up nameplates already on screen (toggled on mid-session).
        if C_NamePlate and C_NamePlate.GetNamePlates then
            for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
                local unit = plate.namePlateUnitToken
                if unit then activePlates[unit] = true end
            end
        end
        refreshAllPlates("ENABLE")
    else
        for event, fn in pairs(REGISTERED) do Events:Off(event, fn) end
        for unit in pairs(activePlates) do
            local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
            hideFrame(plate)
        end
        wipe(activePlates)
    end
end

-- One-time conflict prompt for ElvUI users. ElvUI shows its own nameplate
-- quest icons, so rather than silently defaulting ours off (and leaving the
-- user unaware the feature exists), we ask once which they'd like. Shown only
-- while the setting is still "auto" (nil) and ElvUI is loaded; choosing either
-- button writes an explicit value so it never asks again. Ignoring it leaves
-- the safe default (ours off, ElvUI's untouched).
StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["EQ_NAMEPLATE_ELVUI"] = {
    text = "|cffEBB706Everything Quests|r\n\nEQ can show quest icons (the \"!\" + remaining count) on enemy nameplates.\n\nElvUI is installed and already offers this, so EQ's version is currently OFF to avoid showing two of each icon. Which would you like to use?",
    button1 = "Everything Quests",
    button2 = "Keep ElvUI's",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,   -- avoid tainting the default StaticPopup slot
    OnAccept = function()
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.general.questNameplateIcons = true end
        QI:ApplyEnabled()
    end,
    OnCancel = function()
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.general.questNameplateIcons = false end
        QI:ApplyEnabled()
    end,
}

function QI:OnEnable()
    self.playerName = UnitName and UnitName("player")
    self.enabled = false
    self:ApplyEnabled()

    -- Ask ElvUI users once (deferred so it lands after the loading screen).
    local DB = ns:GetSubsystem("DB")
    local g  = DB and DB.db.profile.general
    if g and g.questNameplateIcons == nil and not g.npConflictAsked and elvUILoaded() then
        g.npConflictAsked = true
        C_Timer.After(4, function()
            if StaticPopup_Show then StaticPopup_Show("EQ_NAMEPLATE_ELVUI") end
        end)
    end
end
