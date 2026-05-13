-- Options/TabAppearance.lua
-- Visual customization for the in-world UI: font, font size, background
-- texture/alpha, color overrides. Pulls fonts/textures from LibSharedMedia.

local _, ns = ...

ns:GetSubsystem("Options"):AddTab("appearance", "Appearance", function(content)
    local Options = ns:GetSubsystem("Options")

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

    local h = Options:CreateSectionHeader(content, "Appearance")
    h:SetPoint("TOPLEFT", 8, -8)

    local Media = ns:GetSubsystem("Media")
    local fontList = (Media and Media.GetFontList and Media:GetFontList()) or {}
    local fontGet, fontSet = trackerSetting("font")
    -- Use the custom font dropdown so each row's label renders in its own
    -- typeface. The generic dropdown's MenuUtil entries don't reliably
    -- accept per-row font overrides.
    local fontDD = Options:CreateFontDropdown(content, "Font", fontList, fontGet, fontSet)
    fontDD:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -16)
    fontDD:SetWidth(280)

    local sizeGet, sizeSet = trackerSetting("fontSize")
    local sizeSlider = Options:CreateSlider(content, "Font Size", 8, 24, 1, sizeGet, sizeSet)
    sizeSlider:SetPoint("TOPLEFT", fontDD, "BOTTOMLEFT", 0, -16)
    sizeSlider:SetWidth(280)

    -- Outline flags passed directly to FontString:SetFont. WoW accepts a
    -- comma-joined combo (e.g. "MONOCHROME, OUTLINE") and ignores tokens
    -- it doesn't recognize, so an empty string == no outline.
    local OUTLINE_OPTIONS = {
        { value = "",                          label = "None" },
        { value = "OUTLINE",                   label = "Outline" },
        { value = "THICKOUTLINE",              label = "Thick" },
        { value = "MONOCHROME",                label = "Mono" },
        { value = "MONOCHROME, OUTLINE",       label = "Mono Outline" },
        { value = "MONOCHROME, THICKOUTLINE",  label = "Mono Thick" },
    }
    local outlineGet, outlineSet = trackerSetting("fontOutline")
    local outlineDD = Options:CreateDropdown(content, "Font Outline",
        OUTLINE_OPTIONS, outlineGet, outlineSet)
    outlineDD:SetPoint("TOPLEFT", sizeSlider, "BOTTOMLEFT", 0, -16)
    outlineDD:SetWidth(280)

    local bgGet, bgSet = trackerSetting("showBackground")
    local bgCheck = Options:CreateCheckbox(content, "Background", bgGet, bgSet)
    bgCheck:SetPoint("TOPLEFT", outlineDD, "BOTTOMLEFT", 0, -16)

    local function bgColorGet()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.backgroundColor or { r = 0, g = 0, b = 0, a = 0.6 }
    end
    local function bgColorSet(c)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.backgroundColor = c end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker then Tracker:Refresh() end
    end
    local bgPicker = Options:CreateColorPicker(content, "Background Color", bgColorGet, bgColorSet)
    bgPicker:SetPoint("LEFT", bgCheck, "RIGHT", 120, 0)

    -- ─── RIGHT COLUMN: colors + dimensions ──────────────────────────────
    local colorsHeader = Options:CreateSectionHeader(content, "Colors & Dimensions")
    colorsHeader:SetPoint("TOPLEFT", h, "TOPLEFT", 460, 0)

    -- Quest title color override: when set, overrides difficulty / yellow.
    local function titleColorGet()
        local DB = ns:GetSubsystem("DB")
        local c = DB and DB.db.profile.tracker.titleColorOverride
        return c or { r = 1, g = 0.82, b = 0, a = 1 }
    end
    local function titleColorSet(c)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.titleColorOverride = c end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker then Tracker:Refresh() end
    end
    local function clearTitleColor()
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.titleColorOverride = nil end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker then Tracker:Refresh() end
    end
    local titlePicker = Options:CreateColorPicker(content, "Quest Title Color Override", titleColorGet, titleColorSet)
    titlePicker:SetPoint("TOPLEFT", colorsHeader, "BOTTOMLEFT", 0, -16)

    local clearBtn = Options:CreateYellowButton(content, "Clear", clearTitleColor)
    clearBtn:SetSize(60, 18)
    clearBtn:SetPoint("LEFT", titlePicker, "RIGHT", 8, 0)

    local titleHint = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    titleHint:SetPoint("TOPLEFT", titlePicker, "BOTTOMLEFT", 0, -2)
    titleHint:SetWidth(380)
    titleHint:SetJustifyH("LEFT")
    titleHint:SetText("When cleared, falls back to difficulty coloring or default yellow.")

    -- Section header color — overrides the default orange-red.
    local function headerColorGet()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.headerColor or { r = 0.93, g = 0.32, b = 0.10, a = 1 }
    end
    local function headerColorSet(c)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.headerColor = c end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker then Tracker:Refresh() end
    end
    local headerPicker = Options:CreateColorPicker(content, "Section Header Color", headerColorGet, headerColorSet)
    headerPicker:SetPoint("TOPLEFT", titleHint, "BOTTOMLEFT", 0, -16)

    -- Tracker scale 0.7 - 1.5
    local function scaleGet()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.scale or 1.0
    end
    local function scaleSet(value)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.scale = value end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker and Tracker.frame then Tracker.frame:SetScale(value) end
    end
    local scaleSlider = Options:CreateSlider(content, "Tracker Scale", 0.7, 1.5, 0.05, scaleGet, scaleSet)
    scaleSlider:SetPoint("TOPLEFT", headerPicker, "BOTTOMLEFT", 0, -32)
    scaleSlider:SetWidth(280)

    -- Block spacing 0 - 12
    local function spacingGet()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.blockSpacing or 4
    end
    local function spacingSet(value)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.blockSpacing = value end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker then Tracker:Refresh() end
    end
    local spacingSlider = Options:CreateSlider(content, "Block Spacing", 0, 12, 1, spacingGet, spacingSet)
    spacingSlider:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", 0, -16)
    spacingSlider:SetWidth(280)
end)
