-- Options/TabTracker.lua
-- On-screen tracker settings: simplify mode, sort order, and per-type filters.
-- Each control writes straight to db.profile.tracker[...] and triggers
-- Tracker:Refresh so the on-screen tracker repaints immediately. No Apply
-- button by design — instant feedback while the user is tweaking.

local _, ns = ...

local Options = ns:GetSubsystem("Options")

-- Build a get/set pair backed by db.profile.tracker[key]. Setter pokes
-- Tracker:Refresh so the tracker repaints the moment a setting changes.
local function trackerSetting(key)
    return
        function()
            local DB = ns:GetSubsystem("DB")
            return DB and DB.db.profile.tracker[key]
        end,
        function(value)
            local DB = ns:GetSubsystem("DB")
            if DB then DB.db.profile.tracker[key] = value end
            local Tracker = ns:GetSubsystem("Tracker")
            if Tracker then Tracker:Refresh() end
        end
end

-- Same shape but for filters (one level deeper inside db.profile.tracker.filters).
local function filterSetting(key)
    return
        function()
            local DB = ns:GetSubsystem("DB")
            return DB and DB.db.profile.tracker.filters[key]
        end,
        function(value)
            local DB = ns:GetSubsystem("DB")
            if DB then DB.db.profile.tracker.filters[key] = value end
            local Tracker = ns:GetSubsystem("Tracker")
            if Tracker then Tracker:Refresh() end
        end
end

local SORT_OPTIONS = {
    { value = "zone",     label = "Zone"     },
    { value = "status",   label = "Status"   },
    { value = "type",     label = "Type"     },
    { value = "level",    label = "Level"    },
    { value = "distance", label = "Distance" },
    { value = "manual",   label = "Manual"   },
}

local FILTER_ROWS = {
    { key = "showNormal",      label = "Normal quests"   },
    { key = "showDaily",       label = "Daily quests"    },
    { key = "showWeekly",      label = "Weekly quests"   },
    { key = "showCampaign",    label = "Campaign quests" },
    { key = "showWorld",       label = "World quests"    },
    { key = "onlyCurrentZone", label = "Show only quests in current zone" },
}

Options:AddTab("tracker", "Tracker", function(content)
    -- ─── On-Screen Tracker section ──────────────────────────────────────
    local header = Options:CreateSectionHeader(content, "On-Screen Tracker")
    header:SetPoint("TOPLEFT", 8, -8)

    -- Show only watched quests (Blizzard-parity). When ON (default), only
    -- quests in Blizzard's watch list show in the on-screen tracker. When
    -- OFF, every quest in the player's log shows ("firehose mode").
    local watchedGet, watchedSet = trackerSetting("showOnlyWatched")
    local watched = Options:CreateCheckbox(
        content,
        "Show only watched quests  |cffaaaaaa(matches Blizzard's default tracker)|r",
        watchedGet, watchedSet)
    watched:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -16)

    local simplifyGet, simplifySet = trackerSetting("simplifyMode")
    local simplify = Options:CreateCheckbox(
        content,
        "Simplify Mode  |cffaaaaaa(show only the first incomplete objective per quest)|r",
        simplifyGet, simplifySet)
    simplify:SetPoint("TOPLEFT", watched, "BOTTOMLEFT", 0, -2)

    local sortGet, sortSet = trackerSetting("sortMode")
    local manualHint
    local function syncManualHint(value)
        if not manualHint then return end
        if value == "manual" then manualHint:Show() else manualHint:Hide() end
    end
    local sort = Options:CreateRadioGroup(
        content, "Sort Order",
        SORT_OPTIONS, sortGet,
        function(v) sortSet(v); syncManualHint(v) end)
    sort:SetPoint("TOPLEFT", simplify, "BOTTOMLEFT", 0, -20)

    manualHint = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    manualHint:SetPoint("TOPLEFT", sort, "BOTTOMLEFT", 0, -2)
    manualHint:SetTextColor(0.92, 0.72, 0.02)
    manualHint:SetText("|cffaaaaaaManual mode: drag and drop quests in the on-screen tracker to reorder them however you like.|r")
    syncManualHint(sortGet())

    -- ─── Filters section ────────────────────────────────────────────────
    local filtersHeader = Options:CreateSectionHeader(content, "Filters")
    filtersHeader:SetPoint("TOPLEFT", sort, "BOTTOMLEFT", 0, -24)

    local prev = filtersHeader
    local filterCheckboxes = {}
    for i, row in ipairs(FILTER_ROWS) do
        local get, set = filterSetting(row.key)
        local cb = Options:CreateCheckbox(content, row.label, get, set)
        cb:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", i == 1 and 0 or 0, i == 1 and -8 or -2)
        filterCheckboxes[#filterCheckboxes + 1] = { row = row, cb = cb }
        prev = cb
    end

    -- Reset button: restores every type filter + showOnlyWatched to defaults.
    -- Offered because "I unchecked something and now quests are missing" is a
    -- common confused-user state that's annoying to recover from manually.
    local resetFilters = Options:CreateYellowButton(content, "Reset filters to defaults", function()
        local DB = ns:GetSubsystem("DB")
        if not DB then return end
        local f = DB.db.profile.tracker.filters
        f.showNormal      = true
        f.showDaily       = true
        f.showWeekly      = true
        f.showCampaign    = true
        f.showWorld       = true
        f.onlyCurrentZone = false
        DB.db.profile.tracker.showOnlyWatched = true
        for _, entry in ipairs(filterCheckboxes) do
            entry.cb:SetChecked(f[entry.row.key] and true or false)
        end
        local V = ns:GetSubsystem("TrackerVisibility")
        if V and V.Apply then V:Apply() end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker and Tracker.Refresh then Tracker:Refresh() end
    end)
    resetFilters:SetSize(180, 24)
    resetFilters:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -10)

    -- ─── Options section (right column, parallel to On-Screen Tracker) ──
    local optionsHeader = Options:CreateSectionHeader(content, "Options")
    optionsHeader:SetPoint("TOPLEFT", header, "TOPLEFT", 460, 0)

    local diffGet, diffSet = trackerSetting("colorByDifficulty")
    local diff = Options:CreateCheckbox(
        content,
        "Quest Title Color By Difficulty",
        diffGet, diffSet)
    diff:SetPoint("TOPLEFT", optionsHeader, "BOTTOMLEFT", 0, -10)

    local lvlGet, lvlSet = trackerSetting("showLevelInTracker")
    local lvl = Options:CreateCheckbox(content,
        "Show quest level prefix  |cffaaaaaa(e.g. [60] Title)|r",
        lvlGet, lvlSet)
    lvl:SetPoint("TOPLEFT", diff, "BOTTOMLEFT", 0, -2)

    local zoneGet, zoneSet = trackerSetting("showZoneTag")
    local zoneCheck = Options:CreateCheckbox(content,
        "Show zone label under quest titles", zoneGet, zoneSet)
    zoneCheck:SetPoint("TOPLEFT", lvl, "BOTTOMLEFT", 0, -2)

    local objGet, objSet = trackerSetting("showObjectiveNumbers")
    local objCheck = Options:CreateCheckbox(content,
        "Show objective progress numbers  |cffaaaaaa(0/4, 1/1, etc.)|r",
        objGet, objSet)
    objCheck:SetPoint("TOPLEFT", zoneCheck, "BOTTOMLEFT", 0, -2)

    local qidGet, qidSet = trackerSetting("showQuestID")
    local qidCheck = Options:CreateCheckbox(content,
        "Show quest ID  |cffaaaaaa(useful for bug reports)|r",
        qidGet, qidSet)
    qidCheck:SetPoint("TOPLEFT", objCheck, "BOTTOMLEFT", 0, -2)

    local Media = ns:GetSubsystem("Media")
    local soundGet, soundSet = trackerSetting("questSoundEnabled")
    local soundCheck = Options:CreateCheckbox(
        content,
        "Quest Sound  |cffaaaaaa(plays when a quest is ready to turn in)|r",
        soundGet, soundSet)
    soundCheck:SetPoint("TOPLEFT", qidCheck, "BOTTOMLEFT", 0, -8)

    local soundList = (Media and Media.GetSoundList and Media:GetSoundList()) or {}
    local sndChoiceGet, sndChoiceSet = trackerSetting("questCompleteSound")
    local function playSound(value)
        local f = Media and Media.GetSoundFile and Media:GetSoundFile(value)
        if f and PlaySoundFile then
            PlaySoundFile(f, "Master")
        end
    end
    local soundDD = Options:CreateDropdown(content, "Quest Complete Sound", soundList, sndChoiceGet, function(value)
        sndChoiceSet(value)
        playSound(value)
    end, playSound)
    soundDD:SetPoint("TOPLEFT", soundCheck, "BOTTOMLEFT", 0, -8)
    soundDD:SetWidth(280)

    -- ─── Tracker Visibility section ─────────────────────────────────────
    -- Per-section show/hide toggles for the on-screen tracker. Separate
    -- from Filters (which hide individual quests by type) because these
    -- hide whole tracker sections, which is a different mental model.
    local visHeader = Options:CreateSectionHeader(content, "Tracker Visibility")
    visHeader:SetPoint("TOPLEFT", soundDD, "BOTTOMLEFT", 0, -24)

    local profGet, profSet = trackerSetting("showProfessionSection")
    local profCheck = Options:CreateCheckbox(content, "Profession section", profGet, profSet)
    profCheck:SetPoint("TOPLEFT", visHeader, "BOTTOMLEFT", 0, -8)

    local wqGet, wqSet = trackerSetting("showWorldQuestsSection")
    local wqCheck = Options:CreateCheckbox(content, "World Quests section", wqGet, wqSet)
    wqCheck:SetPoint("TOPLEFT", profCheck, "BOTTOMLEFT", 0, -2)

    -- Helper hint at the bottom — no Apply button by design, so call out
    -- the live-update behavior so the user knows changes are taking effect.
    local hint = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 8, 8)
    hint:SetText("Changes apply immediately to the on-screen tracker.")
end)
