-- Options/TabWorldQuests.lua
-- World quest visibility toggles + per-reward-type filters + per-faction
-- filters. Two-column layout: visibility & reward filters on the left, a
-- scrollable expansion-grouped faction list on the right.

local _, ns = ...

local Options = ns:GetSubsystem("Options")

local function refreshWQ()
    local WQ = ns:GetSubsystem("WQWorldMap")
    if WQ and WQ.Refresh then WQ:Refresh() end
end

local function wqSetting(key)
    return
        function()
            local DB = ns:GetSubsystem("DB")
            return DB and DB.db.profile.worldQuests[key]
        end,
        function(value)
            local DB = ns:GetSubsystem("DB")
            if DB then DB.db.profile.worldQuests[key] = value end
            refreshWQ()
        end
end

local function filterSetting(key)
    return
        function()
            local DB = ns:GetSubsystem("DB")
            return DB and DB.db.profile.worldQuests.filters[key]
        end,
        function(value)
            local DB = ns:GetSubsystem("DB")
            if DB then DB.db.profile.worldQuests.filters[key] = value end
            refreshWQ()
        end
end

local FILTER_ROWS = {
    { key = "gold",       label = "Gold",                   icon = "Interface\\MoneyFrame\\UI-MoneyIcons", coords = { 0, 0.25, 0, 1 } },
    { key = "gear",       label = "Gear / Items",           icon = "Interface\\Icons\\INV_Helmet_06" },
    { key = "rep",        label = "Reputation tokens",      icon = "Interface\\Icons\\Achievement_Reputation_01" },
    { key = "resource",   label = "Resources / Currencies", icon = "Interface\\Icons\\Trade_Mining" },
    { key = "ap",         label = "Artifact Power",         icon = "Interface\\Icons\\INV_7XP_Inscription_TalentTome01" },
    { key = "profession", label = "Profession quests",      icon = "Interface\\Icons\\Trade_Engineering" },
    { key = "pvp",        label = "PvP",                    icon = "Interface\\Icons\\Achievement_Bg_TopDmg" },
    { key = "pet",        label = "Pet battles",            icon = "Interface\\Icons\\INV_Pet_Achievement_CaptureAPet" },
    { key = "other",      label = "Other / Uncategorized",  icon = "Interface\\Icons\\INV_Misc_QuestionMark" },
}

-- Map LE_EXPANSION_* IDs to human names. Blizzard ships these as numeric
-- enums; the names here are the canonical marketing names so users
-- recognize them. Any expansionID we don't know about lands in "Other".
local EXPANSION_NAMES = {
    [0]  = "Classic",
    [1]  = "The Burning Crusade",
    [2]  = "Wrath of the Lich King",
    [3]  = "Cataclysm",
    [4]  = "Mists of Pandaria",
    [5]  = "Warlords of Draenor",
    [6]  = "Legion",
    [7]  = "Battle for Azeroth",
    [8]  = "Shadowlands",
    [9]  = "Dragonflight",
    [10] = "The War Within",
    [11] = "Midnight",
}

local function setAllFilters(value)
    local DB = ns:GetSubsystem("DB")
    if not DB then return end
    for _, row in ipairs(FILTER_ROWS) do
        DB.db.profile.worldQuests.filters[row.key] = value
    end
    refreshWQ()
end

local function factionGet(fid)
    local DB = ns:GetSubsystem("DB")
    if not DB then return true end
    return DB.db.profile.worldQuests.factionFilters[fid] ~= false
end
local function factionSet(fid, value)
    local DB = ns:GetSubsystem("DB")
    if not DB then return end
    if value then
        DB.db.profile.worldQuests.factionFilters[fid] = nil
    else
        DB.db.profile.worldQuests.factionFilters[fid] = false
    end
    refreshWQ()
end

-- Walk all major factions, group by expansionID, sort each group
-- alphabetically. Returns { { expansionID, name, factions = {...} }, ... }
-- ordered with newest expansion first.
local function listFactionsByExpansion()
    local groups = {}
    local groupByExp = {}
    if not (C_MajorFactions and C_MajorFactions.GetMajorFactionIDs) then return groups end

    local ids = C_MajorFactions.GetMajorFactionIDs() or {}
    for _, id in ipairs(ids) do
        local data = C_MajorFactions.GetMajorFactionData and C_MajorFactions.GetMajorFactionData(id)
        if data and data.isUnlocked then
            local exp = data.expansionID or -1
            local g = groupByExp[exp]
            if not g then
                g = { expansionID = exp, name = EXPANSION_NAMES[exp] or "Other", factions = {} }
                groupByExp[exp] = g
                groups[#groups + 1] = g
            end
            g.factions[#g.factions + 1] = data
        end
    end

    -- Newest expansion first.
    table.sort(groups, function(a, b) return (a.expansionID or 0) > (b.expansionID or 0) end)
    -- Alphabetical within each group.
    for _, g in ipairs(groups) do
        table.sort(g.factions, function(a, b) return (a.name or "") < (b.name or "") end)
    end

    return groups
end

Options:AddTab("worldQuests", "World Quests", function(content)
    -- ─── LEFT COLUMN ────────────────────────────────────────────────────
    local header = Options:CreateSectionHeader(content, "World Quests")
    header:SetPoint("TOPLEFT", 8, -8)

    local showWMGet, showWMSet = wqSetting("showOnWorldMap")
    local showWM = Options:CreateCheckbox(
        content, "Show world quest pins on the world map",
        showWMGet, showWMSet)
    showWM:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -16)

    local showZMGet, showZMSet = wqSetting("showOnZoneMap")
    local showZM = Options:CreateCheckbox(
        content, "Show zone quest list on zone maps",
        showZMGet, showZMSet)
    showZM:SetPoint("TOPLEFT", showWM, "BOTTOMLEFT", 0, -2)

    local filtersHeader = Options:CreateSectionHeader(content, "Filters by reward type")
    filtersHeader:SetPoint("TOPLEFT", showZM, "BOTTOMLEFT", 0, -24)

    local allBtn = Options:CreateYellowButton(content, "Enable All", function() setAllFilters(true) end)
    allBtn:SetSize(90, 22)
    allBtn:SetPoint("LEFT", filtersHeader, "RIGHT", 16, 0)

    local noneBtn = Options:CreateYellowButton(content, "Disable All", function() setAllFilters(false) end)
    noneBtn:SetSize(90, 22)
    noneBtn:SetPoint("LEFT", allBtn, "RIGHT", 6, 0)

    local filterCheckboxes = {}
    local prev = filtersHeader
    for i, row in ipairs(FILTER_ROWS) do
        local get, set = filterSetting(row.key)
        local cb = Options:CreateCheckbox(content, row.label, get, set)
        cb:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, i == 1 and -8 or -2)

        local icon = cb:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetPoint("LEFT", cb, "RIGHT", 4, 1)
        icon:SetTexture(row.icon)
        if row.coords then
            icon:SetTexCoord(row.coords[1], row.coords[2], row.coords[3], row.coords[4])
        end
        cb.label:ClearAllPoints()
        cb.label:SetPoint("LEFT", icon, "RIGHT", 6, 0)

        filterCheckboxes[#filterCheckboxes + 1] = cb
        prev = cb
    end

    local function syncCheckboxes()
        local DB = ns:GetSubsystem("DB")
        if not DB then return end
        for i, row in ipairs(FILTER_ROWS) do
            filterCheckboxes[i]:SetChecked(DB.db.profile.worldQuests.filters[row.key] and true or false)
        end
    end
    allBtn:HookScript("OnClick",  syncCheckboxes)
    noneBtn:HookScript("OnClick", syncCheckboxes)

    -- ─── RIGHT COLUMN: faction filter panel (scrollable) ────────────────
    local factionHeader = Options:CreateSectionHeader(content, "Filter by faction")
    factionHeader:SetPoint("TOPLEFT", header, "TOPLEFT", 460, 0)

    local factionHelp = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    factionHelp:SetPoint("TOPLEFT", factionHeader, "BOTTOMLEFT", 0, -4)
    factionHelp:SetWidth(380)
    factionHelp:SetJustifyH("LEFT")
    factionHelp:SetTextColor(0.65, 0.65, 0.65)
    factionHelp:SetText("Uncheck a faction to hide its world quests on the map.")

    local scroll = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", factionHelp, "BOTTOMLEFT", 0, -8)
    scroll:SetSize(380, 440)

    local list = CreateFrame("Frame", nil, scroll)
    list:SetSize(360, 1)
    scroll:SetScrollChild(list)

    -- Background strip behind this list's scroll bar, matching the in-world
    -- tracker treatment so the low-contrast bar reads here too. Honours the
    -- shared Appearance toggle/colour; resolved at build time (the tab is
    -- rebuilt when reopened, so a later toggle takes effect on next open).
    do
        local DB = ns:GetSubsystem("DB")
        local cfg = DB and DB.db.profile.tracker
        local sBar = scroll.ScrollBar or scroll.scrollBar
        if sBar and (not cfg or cfg.scrollBarBg ~= false) then
            local s = (cfg and cfg.scrollBarBgColor) or { r = 0.60, g = 0.60, b = 0.65, a = 0.25 }
            local sbBG = content:CreateTexture(nil, "BORDER")
            sbBG:SetPoint("TOPLEFT",     sBar, "TOPLEFT",    -1, 0)
            sbBG:SetPoint("BOTTOMRIGHT", sBar, "BOTTOMRIGHT", 1, 0)
            sbBG:SetColorTexture(s.r or 0.60, s.g or 0.60, s.b or 0.65, s.a or 0.25)
        end
    end

    local groups = listFactionsByExpansion()
    if #groups == 0 then
        local empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        empty:SetPoint("TOPLEFT", 0, 0)
        empty:SetText("No major factions unlocked on this character yet.")
        list:SetHeight(20)
    else
        local y = 0
        for _, g in ipairs(groups) do
            local groupLabel = list:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            groupLabel:SetPoint("TOPLEFT", 0, -y)
            groupLabel:SetText(g.name)
            groupLabel:SetTextColor(0.92, 0.72, 0.02)
            y = y + 18

            local underline = list:CreateTexture(nil, "ARTWORK")
            underline:SetColorTexture(0.43, 0.02, 0.0, 0.7)
            underline:SetSize(360, 1)
            underline:SetPoint("TOPLEFT", 0, -y + 2)
            y = y + 4

            for _, data in ipairs(g.factions) do
                local fid = data.factionID
                local labelText = ("%s  |cffaaaaaa(Renown %d)|r"):format(
                    data.name or ("Faction " .. fid), data.renownLevel or 0)
                local cb = Options:CreateCheckbox(list, labelText,
                    function() return factionGet(fid) end,
                    function(v) factionSet(fid, v) end)
                cb:SetPoint("TOPLEFT", 6, -y)
                y = y + 22
            end

            y = y + 6
        end
        list:SetHeight(y)
    end

    -- ─── Display section (left column, below filters) ───────────────────
    local displayHeader = Options:CreateSectionHeader(content, "Display")
    displayHeader:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -24)

    local SORT_OPTIONS = {
        { value = "time",    label = "Time left" },
        { value = "type",    label = "Reward"    },
        { value = "faction", label = "Faction"   },
        { value = "alpha",   label = "A-Z"       },
    }
    local sortGet, sortSet = wqSetting("zoneListSort")
    local sortRadio = Options:CreateRadioGroup(content, "Sort zone quest list by",
        SORT_OPTIONS, sortGet, sortSet)
    sortRadio:SetPoint("TOPLEFT", displayHeader, "BOTTOMLEFT", 0, -8)

    local function pinScaleGet()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.worldQuests.pinScale or 1.0
    end
    local function pinScaleSet(value)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.worldQuests.pinScale = value end
        refreshWQ()
    end
    local pinSlider = Options:CreateSlider(content, "World map pin scale",
        0.5, 2.0, 0.05, pinScaleGet, pinScaleSet)
    pinSlider:SetPoint("TOPLEFT", sortRadio, "BOTTOMLEFT", 0, -16)
    pinSlider:SetWidth(280)

    local hint = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", pinSlider, "BOTTOMLEFT", 0, -4)
    hint:SetWidth(440)
    hint:SetJustifyH("LEFT")
    hint:SetText("Filters apply immediately when the world map is open.")
end)
