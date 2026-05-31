-- Options/TabGeneral.lua
-- Top-level toggles: tracker behavior, minimap button, slash commands,
-- profile management, reset button.

local _, ns = ...

ns:GetSubsystem("Options"):AddTab("general", "General", function(content)
    local Options = ns:GetSubsystem("Options")

    local function generalSetting(key)
        return
            function()
                local DB = ns:GetSubsystem("DB")
                return DB and DB.db.profile.general[key]
            end,
            function(value)
                local DB = ns:GetSubsystem("DB")
                if DB then DB.db.profile.general[key] = value end
                local V = ns:GetSubsystem("TrackerVisibility")
                if V and V.Apply then V:Apply() end
            end
    end

    -- ─── LEFT COLUMN: behavior toggles ───────────────────────────────────
    local h = Options:CreateSectionHeader(content, "General")
    h:SetPoint("TOPLEFT", 8, -8)

    -- Top-level toggle for EQ's own world-map quest pins (the red rings).
    -- Lives in db.profile.map.showQuestPins; refresh the live provider so
    -- the change shows immediately if the world map is open.
    local function questPinsGet()
        local DB = ns:GetSubsystem("DB")
        return not DB or not DB.db.profile.map
               or DB.db.profile.map.showQuestPins ~= false
    end
    local function questPinsSet(v)
        local DB = ns:GetSubsystem("DB")
        if DB then
            DB.db.profile.map = DB.db.profile.map or {}
            DB.db.profile.map.showQuestPins = v and true or false
        end
        local P = ns:GetSubsystem("MapPOIProvider")
        if P and P.provider and P.provider.RefreshAllData then
            P.provider:RefreshAllData()
        end
    end
    local qpins = Options:CreateCheckbox(content,
        "Show quest pins on the world map  |cffaaaaaa(EQ's red \"!\" / \"?\" rings)|r",
        questPinsGet, questPinsSet)
    qpins:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -16)

    local qpinsHint = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    qpinsHint:SetPoint("TOPLEFT", qpins, "BOTTOMLEFT", 0, -2)
    qpinsHint:SetWidth(430)
    qpinsHint:SetJustifyH("LEFT")
    qpinsHint:SetText("These are the round red markers Everything Quests puts on the big world map for quests you've already picked up (the ones in your quest log). A red \"!\" means \"go here for this quest's next step.\" A red \"?\" means \"this quest is done \226\128\148 go here to turn it in.\" Quests you haven't accepted yet keep the game's own yellow \"!\" markers; EQ does not change those. Uncheck this box and all of EQ's red markers go away.")

    -- Lock = no drag-to-move AND no resize. Dedicated setter (not the shared
    -- generalSetting) so it also reconciles the resize grip: ApplyLockState
    -- hides + disables it when locked. The grip's own OnMouseDown re-checks
    -- this flag live too, so resize is blocked even before the next repaint.
    local function lockGet()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.general.lockTracker
    end
    local function lockSet(value)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.general.lockTracker = value and true or false end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker and Tracker.ApplyLockState then Tracker:ApplyLockState() end
    end
    local lock = Options:CreateCheckbox(content,
        "Lock tracker  |cffaaaaaa(disable drag-to-move and resize)|r",
        lockGet, lockSet)
    lock:SetPoint("TOPLEFT", qpinsHint, "BOTTOMLEFT", 0, -12)

    local combatGet, combatSet = generalSetting("hideInCombat")
    local combat = Options:CreateCheckbox(content,
        "Hide tracker in combat",
        combatGet, combatSet)
    combat:SetPoint("TOPLEFT", lock, "BOTTOMLEFT", 0, -2)

    local instGet, instSet = generalSetting("hideInInstances")
    local inst = Options:CreateCheckbox(content,
        "Hide tracker in instances  |cffaaaaaa(raids, dungeons, delves)|r",
        instGet, instSet)
    inst:SetPoint("TOPLEFT", combat, "BOTTOMLEFT", 0, -2)

    local mapGet, mapSet = generalSetting("hideOnMapOpen")
    local mapHide = Options:CreateCheckbox(content,
        "Hide tracker when world map is open",
        mapGet, mapSet)
    mapHide:SetPoint("TOPLEFT", inst, "BOTTOMLEFT", 0, -2)

    local autoGet, autoSet = generalSetting("autoTrackAccepted")
    local auto = Options:CreateCheckbox(content,
        "Auto-track accepted quests  |cffaaaaaa(matches Blizzard's default)|r",
        autoGet, autoSet)
    auto:SetPoint("TOPLEFT", mapHide, "BOTTOMLEFT", 0, -2)

    local autoAccGet, autoAccSet = generalSetting("autoAcceptQuests")
    local autoAcc = Options:CreateCheckbox(content,
        "Auto-accept quests  |cffaaaaaa(hold Alt to pause)|r",
        autoAccGet, autoAccSet)
    autoAcc:SetPoint("TOPLEFT", auto, "BOTTOMLEFT", 0, -2)

    local autoTIGet, autoTISet = generalSetting("autoTurnInQuests")
    local autoTI = Options:CreateCheckbox(content,
        "Auto-turn-in quests  |cffaaaaaa(skips reward-choice screens)|r",
        autoTIGet, autoTISet)
    autoTI:SetPoint("TOPLEFT", autoAcc, "BOTTOMLEFT", 0, -2)

    local zoomGet, zoomSet = generalSetting("autoZoomToTrackedQuest")
    local zoom = Options:CreateCheckbox(content,
        "Zoom world map to focused quest's zone  |cffaaaaaa(when you open the map)|r",
        zoomGet, zoomSet)
    zoom:SetPoint("TOPLEFT", autoTI, "BOTTOMLEFT", 0, -2)

    local restoreGet, restoreSet = generalSetting("restoreSuperTrackOnLogin")
    local restore = Options:CreateCheckbox(content,
        "Keep focused quest after relog  |cffaaaaaa(restores the waypoint arrow)|r",
        restoreGet, restoreSet)
    restore:SetPoint("TOPLEFT", zoom, "BOTTOMLEFT", 0, -2)

    -- Nameplate quest icons. Custom get/set: the stored value is nil until the
    -- user touches it, which resolves to ON unless ElvUI is loaded (ElvUI shows
    -- its own, so we avoid doubling up). Toggling writes an explicit bool and
    -- applies live through the module.
    local function npGet()
        local QI = ns:GetSubsystem("NameplateQuestIcons")
        return QI and QI.IsEnabled and QI:IsEnabled()
    end
    local function npSet(value)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.general.questNameplateIcons = value and true or false end
        local QI = ns:GetSubsystem("NameplateQuestIcons")
        if QI and QI.ApplyEnabled then QI:ApplyEnabled() end
    end
    local nameplates = Options:CreateCheckbox(content,
        "Quest icons on nameplates  |cffaaaaaa(shows the \"!\" + count on objective mobs)|r",
        npGet, npSet)
    nameplates:SetPoint("TOPLEFT", restore, "BOTTOMLEFT", 0, -2)

    -- Minimap button — uses LibDBIcon's hide flag stored in db.char.minimap.
    local function mmGet()
        local DB = ns:GetSubsystem("DB")
        return DB and not DB.char.minimap.hide
    end
    local function mmSet(value)
        local DB = ns:GetSubsystem("DB")
        if not DB then return end
        DB.char.minimap.hide = not value
        local LDBI = LibStub and LibStub("LibDBIcon-1.0", true)
        if LDBI then
            if value then LDBI:Show("EverythingQuests") else LDBI:Hide("EverythingQuests") end
        end
    end
    local mm = Options:CreateCheckbox(content, "Show minimap button", mmGet, mmSet)
    mm:SetPoint("TOPLEFT", nameplates, "BOTTOMLEFT", 0, -2)

    -- ─── Reset profile button ───────────────────────────────────────────
    local reset = Options:CreateYellowButton(content, "Reset all settings", function()
        local Dialog = ns:GetSubsystem("Dialog")
        if not Dialog then return end
        Dialog:Show({
            title   = "Everything Quests",
            text    = "Reset every Everything Quests setting to defaults?",
            button1 = "Reset",
            button2 = "Cancel",
            onAccept = function()
                local DB = ns:GetSubsystem("DB")
                if DB and DB.db and DB.db.ResetProfile then DB.db:ResetProfile() end
                ReloadUI()
            end,
        })
    end)
    reset:SetSize(160, 24)
    reset:SetPoint("TOPLEFT", mm, "BOTTOMLEFT", 0, -16)

    -- ─── RIGHT COLUMN: profiles + slash command list ────────────────────
    local profilesHeader = Options:CreateSectionHeader(content, "Profiles")
    profilesHeader:SetPoint("TOPLEFT", h, "TOPLEFT", 460, 0)

    -- profileList is passed as a function (not a static table) so the
    -- dropdown re-fetches each time it opens — newly created profiles
    -- show up without rebuilding the widget.
    local function profileList()
        local DB = ns:GetSubsystem("DB")
        local out = {}
        if not (DB and DB.db and DB.db.GetProfiles) then return out end
        for _, name in ipairs(DB.db:GetProfiles()) do
            out[#out + 1] = { value = name, label = name }
        end
        return out
    end
    local function currentProfile()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db and DB.db:GetCurrentProfile() or "Default"
    end
    local function setProfile(name)
        local DB = ns:GetSubsystem("DB")
        if DB and DB.db and DB.db.SetProfile then
            DB.db:SetProfile(name)
            ReloadUI()
        end
    end

    -- Create a new profile that carries the current profile's settings
    -- over instead of starting from defaults — matches the user expectation
    -- of "make a copy of what I have under a new name".
    local function createProfileCopiedFromCurrent(name)
        local DB = ns:GetSubsystem("DB")
        if not (DB and DB.db) then return end
        local source = DB.db:GetCurrentProfile()
        DB.db:SetProfile(name)                  -- creates + switches to the new profile
        if source and source ~= name and DB.db.CopyProfile then
            DB.db:CopyProfile(source, true)     -- silent = true: no confirmation popup
        end
        ReloadUI()
    end
    local profDD = Options:CreateDropdown(content, "Active profile",
        profileList, currentProfile, setProfile)
    profDD:SetPoint("TOPLEFT", profilesHeader, "BOTTOMLEFT", 0, -16)
    profDD:SetWidth(280)

    -- New Profile button — AceDB's SetProfile creates the profile on
    -- demand if it doesn't already exist, so we just need a name from
    -- the user. Empty input is rejected; existing name is treated as
    -- "switch to that profile".
    local function promptNewProfile()
        local Dialog = ns:GetSubsystem("Dialog")
        if not Dialog then return end
        Dialog:Show({
            title      = "New Profile",
            text       = "Profile name:",
            hasEditBox = true,
            maxLetters = 32,
            button1    = "Create",
            button2    = "Cancel",
            onAccept = function(text)
                local name = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
                if name == "" then return end
                createProfileCopiedFromCurrent(name)
            end,
        })
    end
    local newProfileBtn = Options:CreateYellowButton(content, "New Profile", promptNewProfile)
    newProfileBtn:SetSize(120, 22)
    newProfileBtn:SetPoint("LEFT", profDD.button, "RIGHT", 6, 0)

    local profHint = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profHint:SetPoint("TOPLEFT", profDD, "BOTTOMLEFT", 0, -4)
    profHint:SetWidth(380)
    profHint:SetJustifyH("LEFT")
    profHint:SetTextColor(0.65, 0.65, 0.65)
    profHint:SetText("Switching profiles reloads the UI. Profiles are shared across characters; use them to keep different setups (e.g. raid vs solo). |cffEBB706New Profile|r prompts for a name and creates it on the spot.")

    local slashHeader = Options:CreateSectionHeader(content, "Slash commands")
    slashHeader:SetPoint("TOPLEFT", profHint, "BOTTOMLEFT", 0, -24)

    local slashText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    slashText:SetPoint("TOPLEFT", slashHeader, "BOTTOMLEFT", 0, -8)
    slashText:SetJustifyH("LEFT")
    slashText:SetTextColor(0.92, 0.72, 0.02)
    slashText:SetText("/eqs\n/everythingquests\n\n|cff999999Both open this options window.|r")
end)
