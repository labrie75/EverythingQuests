-- Options/TabTracker.lua
-- On-screen tracker settings: simplify mode, sort order, and per-type filters.
-- Each control writes straight to db.profile.tracker[...] and triggers
-- Tracker:Refresh so the on-screen tracker repaints immediately. No Apply
-- button by design — instant feedback while the user is tweaking.

local _, ns = ...
local L = ns.L

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
    { value = "zone",     label = L["Zone"]     },
    { value = "status",   label = L["Status"]   },
    { value = "type",     label = L["Type"]     },
    { value = "level",    label = L["Level"]    },
    { value = "distance", label = L["Distance"] },
    { value = "recent",   label = L["Recent"]   },
    { value = "manual",   label = L["Manual"]   },
}

local FILTER_ROWS = {
    { key = "showNormal",      label = L["Normal quests"]   },
    { key = "showDaily",       label = L["Daily quests"]    },
    { key = "showWeekly",      label = L["Weekly quests"]   },
    { key = "showCampaign",    label = L["Campaign quests"] },
    { key = "showWorld",       label = L["World quests"]    },
    { key = "onlyCurrentZone", label = L["Show only quests in current zone"] },
}

Options:AddTab("tracker", L["Tracker"], function(content)
    -- ─── On-Screen Tracker section ──────────────────────────────────────
    local header = Options:CreateSectionHeader(content, L["On-Screen Tracker"])
    header:SetPoint("TOPLEFT", 8, -8)

    -- Show only watched quests (Blizzard-parity). When ON (default), only
    -- quests in Blizzard's watch list show in the on-screen tracker. When
    -- OFF, every quest in the player's log shows ("firehose mode").
    local watchedGet, watchedSet = trackerSetting("showOnlyWatched")
    local watched = Options:CreateCheckbox(
        content,
        L["Show only watched quests"],
        watchedGet, watchedSet,
        L["Matches Blizzard's default tracker."])
    watched:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -16)

    local simplifyGet, simplifySet = trackerSetting("simplifyMode")
    local simplify = Options:CreateCheckbox(
        content,
        L["Simplify Mode"],
        simplifyGet, simplifySet,
        L["Show only the first incomplete objective per quest."])
    simplify:SetPoint("TOPLEFT", watched, "BOTTOMLEFT", 0, -2)

    local sortGet, sortSet = trackerSetting("sortMode")
    -- Forward-declared so syncManualHint can re-anchor the Filters section. The
    -- manual-mode hint is width-capped to the left column, so it may wrap to two
    -- lines — when it's visible the Filters header anchors to the hint's bottom
    -- (adapting to its actual height); when hidden it tucks back under the sort
    -- row. Keeps the hint from ever crowding the header or bleeding into Options.
    local manualHint, filtersHeader, sort
    local function syncManualHint(value)
        local manual = (value == "manual")
        if manualHint then
            if manual then manualHint:Show() else manualHint:Hide() end
        end
        if filtersHeader and sort then
            filtersHeader:ClearAllPoints()
            if manual and manualHint then
                filtersHeader:SetPoint("TOPLEFT", manualHint, "BOTTOMLEFT", 0, -10)
            else
                filtersHeader:SetPoint("TOPLEFT", sort, "BOTTOMLEFT", 0, -14)
            end
        end
    end
    sort = Options:CreateRadioGroup(
        content, L["Sort Order"],
        SORT_OPTIONS, sortGet,
        function(v) sortSet(v); syncManualHint(v) end,
        440, 14)   -- maxWidth 440 = wrap before the right "Options" column (starts at
                   -- header+460). pad 14 (vs default 18) + the short "Recent" label keep
                   -- all 7 sort modes on ONE row even at the wider stock UI font, instead
                   -- of orphaning "Manual" onto a lonely second row.
    sort:SetPoint("TOPLEFT", simplify, "BOTTOMLEFT", 0, -12)

    manualHint = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    manualHint:SetPoint("TOPLEFT", sort, "BOTTOMLEFT", 0, -2)
    manualHint:SetWidth(440)        -- bound to the left column so it can't bleed into Options
    manualHint:SetJustifyH("LEFT")
    manualHint:SetTextColor(0.92, 0.72, 0.02)
    manualHint:SetText(L["|cffaaaaaaDrag and drop the quests in the tracker to reorder them however you like.|r"])

    -- ─── Filters section ────────────────────────────────────────────────
    filtersHeader = Options:CreateSectionHeader(content, L["Filters"])
    syncManualHint(sortGet())   -- positions filtersHeader for the current sort mode

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
    local resetFilters = Options:CreateYellowButton(content, L["Reset filters to defaults"], function()
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
    local optionsHeader = Options:CreateSectionHeader(content, L["Options"])
    optionsHeader:SetPoint("TOPLEFT", header, "TOPLEFT", 460, 0)

    local diffGet, diffSet = trackerSetting("colorByDifficulty")
    local diff = Options:CreateCheckbox(
        content,
        L["Quest Title Color By Difficulty"],
        diffGet, diffSet)
    diff:SetPoint("TOPLEFT", optionsHeader, "BOTTOMLEFT", 0, -10)

    local lvlGet, lvlSet = trackerSetting("showLevelInTracker")
    local lvl = Options:CreateCheckbox(content,
        L["Show quest level prefix"],
        lvlGet, lvlSet,
        L["For example, [60] Title."])
    lvl:SetPoint("TOPLEFT", diff, "BOTTOMLEFT", 0, -2)

    local zoneGet, zoneSet = trackerSetting("showZoneTag")
    local zoneCheck = Options:CreateCheckbox(content,
        L["Show zone label under quest titles"], zoneGet, zoneSet)
    zoneCheck:SetPoint("TOPLEFT", lvl, "BOTTOMLEFT", 0, -2)

    local objGet, objSet = trackerSetting("showObjectiveNumbers")
    local objCheck = Options:CreateCheckbox(content,
        L["Show objective progress numbers"],
        objGet, objSet,
        L["For example, 0/4, 1/1, etc."])
    objCheck:SetPoint("TOPLEFT", zoneCheck, "BOTTOMLEFT", 0, -2)

    local qidGet, qidSet = trackerSetting("showQuestID")
    local qidCheck = Options:CreateCheckbox(content,
        L["Show quest ID"],
        qidGet, qidSet,
        L["Useful for bug reports."])
    qidCheck:SetPoint("TOPLEFT", objCheck, "BOTTOMLEFT", 0, -2)

    local qtotalGet, qtotalSet = trackerSetting("showQuestTotal")
    local qtotalCheck = Options:CreateCheckbox(content,
        L["Show tracked / total on the Quests & Campaign headers"],
        qtotalGet, qtotalSet,
        L["For example, 3/9."])
    qtotalCheck:SetPoint("TOPLEFT", qidCheck, "BOTTOMLEFT", 0, -2)

    local itemBtnGet, itemBtnSet = trackerSetting("showItemButtons")
    local itemBtnCheck = Options:CreateCheckbox(content,
        L["Show usable quest item buttons"],
        itemBtnGet, itemBtnSet,
        L["Click to use the quest's item."])
    itemBtnCheck:SetPoint("TOPLEFT", qtotalCheck, "BOTTOMLEFT", 0, -2)

    local hideBarGet, hideBarSet = trackerSetting("hideScrollBar")
    local hideBarCheck = Options:CreateCheckbox(content,
        L["Hide scroll bar"],
        hideBarGet, hideBarSet,
        L["Scroll with the mouse wheel instead."])
    hideBarCheck:SetPoint("TOPLEFT", itemBtnCheck, "BOTTOMLEFT", 0, -2)

    local popupGet, popupSet = trackerSetting("showQuestPopups")
    local popupCheck = Options:CreateCheckbox(content,
        L["Show Quest Discovered popups"],
        popupGet, popupSet,
        L["Boxes for newly discovered / completed quests."])
    popupCheck:SetPoint("TOPLEFT", hideBarCheck, "BOTTOMLEFT", 0, -2)

    local newTagGet, newTagSet = trackerSetting("showRecentlyAddedTag")
    local newTagCheck = Options:CreateCheckbox(content,
        L["Show NEW tag on recently accepted quests"],
        newTagGet, newTagSet,
        L["For about an hour after accepting."])
    newTagCheck:SetPoint("TOPLEFT", popupCheck, "BOTTOMLEFT", 0, -2)

    local splitGet, splitSet = trackerSetting("splitQuestClick")
    local splitCheck = Options:CreateCheckbox(content,
        L["Split quest click"],
        splitGet, splitSet,
        L["Click the icon to focus, click the title to open the quest log."])
    splitCheck:SetPoint("TOPLEFT", newTagCheck, "BOTTOMLEFT", 0, -2)

    local Media = ns:GetSubsystem("Media")
    local soundGet, soundSet = trackerSetting("questSoundEnabled")
    local soundCheck = Options:CreateCheckbox(
        content,
        L["Quest Sound"],
        soundGet, soundSet,
        L["Plays when a quest is ready to turn in."])
    soundCheck:SetPoint("TOPLEFT", splitCheck, "BOTTOMLEFT", 0, -8)

    local soundList = (Media and Media.GetSoundList and Media:GetSoundList()) or {}
    local sndChoiceGet, sndChoiceSet = trackerSetting("questCompleteSound")
    local function playSound(value)
        local f = Media and Media.GetSoundFile and Media:GetSoundFile(value)
        if f and PlaySoundFile then
            PlaySoundFile(f, "Master")
        end
    end
    local soundDD = Options:CreateDropdown(content, L["Quest Complete Sound"], soundList, sndChoiceGet, function(value)
        sndChoiceSet(value)
        playSound(value)
    end, playSound)
    soundDD:SetPoint("TOPLEFT", soundCheck, "BOTTOMLEFT", 0, -8)
    soundDD:SetWidth(280)

    -- ─── Tracker Visibility section ─────────────────────────────────────
    -- Per-section show/hide toggles for the on-screen tracker. Separate
    -- from Filters (which hide individual quests by type) because these
    -- hide whole tracker sections, which is a different mental model.
    -- Lives in the LEFT column beneath the Filters/Reset block: the right
    -- "Options" column is already full-height, so a 5th toggle here would
    -- overflow the panel. The left column has ample room below Reset.
    local visHeader = Options:CreateSectionHeader(content, L["Tracker Visibility"])
    visHeader:SetPoint("TOPLEFT", resetFilters, "BOTTOMLEFT", 0, -10)

    local profGet, profSet = trackerSetting("showProfessionSection")
    local profCheck = Options:CreateCheckbox(content, L["Profession section"], profGet, profSet)
    profCheck:SetPoint("TOPLEFT", visHeader, "BOTTOMLEFT", 0, -8)

    local achGet, achSet = trackerSetting("showAchievementsSection")
    local achCheck = Options:CreateCheckbox(content, L["Achievements section"], achGet, achSet,
        L["Achievements you're tracking."])
    achCheck:SetPoint("TOPLEFT", profCheck, "BOTTOMLEFT", 0, -2)

    local wqGet, wqSet = trackerSetting("showWorldQuestsSection")
    local wqCheck = Options:CreateCheckbox(content, L["World Quests section"], wqGet, wqSet)
    wqCheck:SetPoint("TOPLEFT", achCheck, "BOTTOMLEFT", 0, -2)

    -- Auto-list current-zone WQs. Custom setter: besides the usual save +
    -- Tracker:Refresh, it marks the World Quests section's active list dirty
    -- so toggling it repopulates immediately instead of waiting for a zone
    -- change (the active list is cached and only rebuilds on dirty).
    local autoWQGet = function()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.autoListZoneWorldQuests
    end
    local autoWQSet = function(value)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.autoListZoneWorldQuests = value end
        local Events = ns:GetSubsystem("TrackerEvents")
        if Events and Events.MarkActiveDirty then Events:MarkActiveDirty() end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker then Tracker:Refresh() end
    end
    local autoWQCheck = Options:CreateCheckbox(content,
        L["Auto-list current-zone world quests"],
        autoWQGet, autoWQSet,
        L["Lists every WQ in your zone without tracking each."])
    autoWQCheck:SetPoint("TOPLEFT", wqCheck, "BOTTOMLEFT", 0, -2)

    -- ─── Zone Progress Bar section ──────────────────────────────────────
    -- Lives in the RIGHT column beneath the sound dropdown (which is now the
    -- bottom of the Options column). Its own group because it can render as a
    -- tracker section OR a standalone movable frame — see ZoneProgress.lua.
    local zpHeader = Options:CreateSectionHeader(content, L["Zone Progress Bar"])
    zpHeader:SetPoint("TOPLEFT", soundDD, "BOTTOMLEFT", 0, -16)

    -- Master enable. Custom setter calls ZoneProgress:SetEnabled so toggling
    -- ON discovers + paints the current zone immediately (and OFF clears the
    -- cache + hides the frame). Off by default — questline-based (approximate)
    -- and slightly heavier.
    local zpEnableGet = function()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.showZoneProgressBar
    end
    local zpEnableSet = function(value)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.showZoneProgressBar = value end
        local ZP = ns:GetSubsystem("TrackerZoneProgress")
        if ZP and ZP.SetEnabled then
            ZP:SetEnabled(value)
        else
            local Tracker = ns:GetSubsystem("Tracker")
            if Tracker then Tracker:Refresh() end
        end
    end
    local zpEnable = Options:CreateCheckbox(content,
        L["Show zone progress bar"],
        zpEnableGet, zpEnableSet,
        L["Approximate questline progress."])
    zpEnable:SetPoint("TOPLEFT", zpHeader, "BOTTOMLEFT", 0, -8)

    -- Placement: floating standalone frame vs a section on the tracker.
    local zpFloatGet = function()
        local DB = ns:GetSubsystem("DB")
        return DB and (DB.db.profile.tracker.zoneProgressLocation or "floating") == "floating"
    end
    local zpFloatSet = function(value)
        local ZP = ns:GetSubsystem("TrackerZoneProgress")
        if ZP and ZP.SetLocation then ZP:SetLocation(value and "floating" or "tracker") end
    end
    local zpFloat = Options:CreateCheckbox(content,
        L["Float as a movable bar"],
        zpFloatGet, zpFloatSet,
        L["Drag to move; right-click to lock or reset."])
    zpFloat:SetPoint("TOPLEFT", zpEnable, "BOTTOMLEFT", 0, -2)

    -- Helper hint — no Apply button by design, so call out the live-update
    -- behavior. Pinned to the bottom-RIGHT: the Tracker Visibility toggles now
    -- fill the bottom-left column, and the right "Options" column ends higher
    -- up (at the sound dropdown), leaving the bottom-right corner clear.
    Options:AttachTooltip(header, L["On-Screen Tracker"],
        L["Changes apply immediately to the on-screen tracker."])
end)
