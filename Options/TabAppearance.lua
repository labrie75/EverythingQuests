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

    -- Scroll bar background: a strip behind the tracker's scroll bar so the
    -- low-contrast bar is easy to see. Toggle + colour.
    local sbGet, sbSet = trackerSetting("scrollBarBg")
    local sbCheck = Options:CreateCheckbox(content, "Scroll Bar Background", sbGet, sbSet)
    sbCheck:SetPoint("TOPLEFT", bgCheck, "BOTTOMLEFT", 0, -10)

    local function sbColorGet()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.scrollBarBgColor or { r = 0.60, g = 0.60, b = 0.65, a = 0.25 }
    end
    local function sbColorSet(c)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.scrollBarBgColor = c end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker then Tracker:Refresh() end
    end
    -- Align the Scroll Bar Color *box* directly under the Background Color
    -- box. The picker positions its swatch relative to its own label, and
    -- "Scroll Bar Color" is a different width than "Background Color", so
    -- anchoring the containers alone leaves the boxes a few px out of line.
    -- Re-anchor the swatch to bgPicker's swatch (shared X column, own row)
    -- and tuck this picker's label to the swatch's left.
    local sbPicker = Options:CreateColorPicker(content, "Scroll Bar Color", sbColorGet, sbColorSet)
    sbPicker:SetPoint("TOPLEFT", bgPicker, "BOTTOMLEFT", 0, -8)
    sbPicker.button:ClearAllPoints()
    sbPicker.button:SetPoint("TOP",  sbPicker, "TOP", 0, -1)
    sbPicker.button:SetPoint("LEFT", bgPicker.button, "LEFT", 0, 0)
    sbPicker.label:ClearAllPoints()
    sbPicker.label:SetPoint("RIGHT", sbPicker.button, "LEFT", -8, 0)

    -- Optional border around the tracker (wraps the background region).
    -- Off by default; the color picker carries the same Class/Default
    -- options as every other EQ picker. Mirrors the scroll-bar row's
    -- anchoring so the swatch stays in the shared color column.
    local borderGet, borderSet = trackerSetting("showBorder")
    local borderCheck = Options:CreateCheckbox(content, "Border", borderGet, borderSet)
    borderCheck:SetPoint("TOPLEFT", sbCheck, "BOTTOMLEFT", 0, -10)

    local function borderColorGet()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.borderColor or { r = 0.427, g = 0.020, b = 0.004, a = 1 }
    end
    local function borderColorSet(c)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.borderColor = c end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker then Tracker:Refresh() end
    end
    local borderPicker = Options:CreateColorPicker(content, "Border Color", borderColorGet, borderColorSet)
    borderPicker:SetPoint("TOPLEFT", sbPicker, "BOTTOMLEFT", 0, -8)
    borderPicker.button:ClearAllPoints()
    borderPicker.button:SetPoint("TOP",  borderPicker, "TOP", 0, -1)
    borderPicker.button:SetPoint("LEFT", bgPicker.button, "LEFT", 0, 0)
    borderPicker.label:ClearAllPoints()
    borderPicker.label:SetPoint("RIGHT", borderPicker.button, "LEFT", -8, 0)

    local bThickGet, bThickSet = trackerSetting("borderSize")
    local borderThickSlider = Options:CreateSlider(content, "Border Thickness", 1, 5, 1, bThickGet, bThickSet)
    borderThickSlider:SetPoint("TOPLEFT", borderCheck, "BOTTOMLEFT", 0, -20)
    borderThickSlider:SetWidth(280)

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
