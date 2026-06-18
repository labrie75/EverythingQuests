-- Options/TabAppearance.lua
-- Visual customization for the in-world UI: font, font size, background
-- texture/alpha, color overrides. Pulls fonts/textures from LibSharedMedia.

local _, ns = ...
local L = ns.L

ns:GetSubsystem("Options"):AddTab("appearance", L["Appearance"], function(content)
    local Options = ns:GetSubsystem("Options")

    -- Snap a colour picker's swatch into the same X column as `ref` (another
    -- picker in this column), keeping its label flush-left of the swatch. Each
    -- picker is laid out as [label][8px][swatch], so without this a swatch lands
    -- at label.left + labelWidth + 8 — meaning swatches with different-width
    -- labels (Shadow Color vs Background Color, Thumb Color vs Scroll Bar Color,
    -- Section Header Color vs Quest Title Color Override) don't line up. This is
    -- the same re-anchor the Border row already uses to sit under Background. The
    -- picker keeps whatever vertical position its own anchor gave it.
    local function alignSwatchTo(picker, ref)
        picker.button:ClearAllPoints()
        picker.button:SetPoint("TOP",  picker, "TOP", 0, -1)
        picker.button:SetPoint("LEFT", ref.button, "LEFT", 0, 0)
        picker.label:ClearAllPoints()
        picker.label:SetPoint("RIGHT", picker.button, "LEFT", -8, 0)
    end

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

    -- Like trackerSetting, but the scenario-banner shadow only affects the
    -- scenario surface, so it re-applies that banner's shadow directly instead
    -- of refreshing (and re-laying-out) the whole tracker.
    local function scenarioSetting(key)
        return
            function()
                local DB = ns:GetSubsystem("DB")
                return DB and DB.db.profile.tracker[key]
            end,
            function(value)
                local DB = ns:GetSubsystem("DB")
                if DB then DB.db.profile.tracker[key] = value end
                local S = ns:GetSubsystem("TrackerScenario")
                if S and S.ApplyBannerShadow then S:ApplyBannerShadow() end
            end
    end

    local h = Options:CreateSectionHeader(content, L["Appearance"])
    h:SetPoint("TOPLEFT", 8, -8)

    local Media = ns:GetSubsystem("Media")
    local fontList = (Media and Media.GetFontList and Media:GetFontList()) or {}
    local fontGet, fontSet = trackerSetting("font")
    -- Use the custom font dropdown so each row's label renders in its own
    -- typeface. The generic dropdown's MenuUtil entries don't reliably
    -- accept per-row font overrides.
    local fontDD = Options:CreateFontDropdown(content, L["Font"], fontList, fontGet, fontSet)
    fontDD:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -16)
    fontDD:SetWidth(280)

    local sizeGet, sizeSet = trackerSetting("fontSize")
    local sizeSlider = Options:CreateSlider(content, L["Font Size"], 8, 24, 1, sizeGet, sizeSet)
    sizeSlider:SetPoint("TOPLEFT", fontDD, "BOTTOMLEFT", 0, -16)
    sizeSlider:SetWidth(280)

    -- Independent TITLE size: an offset added to the base Font Size for quest /
    -- achievement / etc. titles only (objective text keeps the base size). 0 =
    -- titles match the base font; raise for bigger titles, lower for smaller.
    local titleSizeGet, titleSizeSet = trackerSetting("titleSizeDelta")
    local titleSizeSlider = Options:CreateSlider(content, L["Title Size Offset"], -6, 12, 1, titleSizeGet, titleSizeSet)
    titleSizeSlider:SetPoint("TOPLEFT", sizeSlider, "BOTTOMLEFT", 0, -16)
    titleSizeSlider:SetWidth(280)
    Options:AttachTooltip(titleSizeSlider, L["Title Size Offset"],
        L["Sizes quest and achievement titles separately from the objective text. This value is added to the Font Size above: 0 keeps titles the same size as the base font, positive makes them larger, negative smaller."])

    -- Outline flags passed directly to FontString:SetFont. WoW accepts a
    -- comma-joined combo (e.g. "MONOCHROME, OUTLINE") and ignores tokens
    -- it doesn't recognize, so an empty string == no outline.
    local OUTLINE_OPTIONS = {
        { value = "",                          label = L["None"] },
        { value = "OUTLINE",                   label = L["Outline"] },
        { value = "THICKOUTLINE",              label = L["Thick"] },
        { value = "MONOCHROME",                label = L["Mono"] },
        { value = "MONOCHROME, OUTLINE",       label = L["Mono Outline"] },
        { value = "MONOCHROME, THICKOUTLINE",  label = L["Mono Thick"] },
    }
    local outlineGet, outlineSet = trackerSetting("fontOutline")
    local outlineDD = Options:CreateDropdown(content, L["Font Outline"],
        OUTLINE_OPTIONS, outlineGet, outlineSet)
    outlineDD:SetPoint("TOPLEFT", titleSizeSlider, "BOTTOMLEFT", 0, -16)
    outlineDD:SetWidth(280)

    -- Drop-shadow behind tracker text for legibility over bright/busy
    -- backdrops. Toggle + colour, matching the Background row's layout.
    local shadowGet, shadowSet = trackerSetting("textShadow")
    local shadowCheck = Options:CreateCheckbox(content, L["Text Shadow"], shadowGet, shadowSet,
        L["Draws a soft drop-shadow behind all tracker text so it stays readable over bright or busy backgrounds. Use Shadow Color to tint it and Shadow Size to set how far it's cast."])
    shadowCheck:SetPoint("TOPLEFT", outlineDD, "BOTTOMLEFT", 0, -16)

    local function shadowColorGet()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.textShadowColor or { r = 0, g = 0, b = 0, a = 1 }
    end
    local function shadowColorSet(c)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.textShadowColor = c end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker then Tracker:Refresh() end
    end
    local shadowPicker = Options:CreateColorPicker(content, L["Shadow Color"], shadowColorGet, shadowColorSet)
    shadowPicker:SetPoint("LEFT", shadowCheck, "RIGHT", 120, 0)

    -- Shadow size (offset distance) slider, directly under the Text Shadow row.
    -- "Less" keeps the shadow tight to the letters; "more" casts it further out
    -- for a bigger, more pronounced drop-shadow. The Shadow Color picker above
    -- controls its tint + opacity; this controls reach. Live-previews via the
    -- trackerSetting setter's Tracker:Refresh (Render re-applies the font/shadow).
    local shStrengthGet, shStrengthSet = trackerSetting("textShadowStrength")
    local shadowSizeSlider = Options:CreateSlider(content, L["Shadow Size"], 1, 6, 1, shStrengthGet, shStrengthSet)
    shadowSizeSlider:SetPoint("TOPLEFT", shadowCheck, "BOTTOMLEFT", 0, -14)
    shadowSizeSlider:SetWidth(280)
    Options:AttachTooltip(shadowSizeSlider, L["Shadow Size"],
        L["How far the text drop-shadow is cast behind the letters. Higher values give a larger, more pronounced shadow; lower values keep it tight. Only applies while Text Shadow is on."])

    -- ─── Scenario banner shadow (SEPARATE from the main tracker text) ───────
    -- The scenario / delve banner (the Stage + name lines) is distinct chrome
    -- that mimics Blizzard's native scenario header, so it carries its OWN
    -- drop-shadow controls instead of following the Text Shadow above. Same
    -- toggle + colour + size trio; the tooltip spells out that it's separate.
    local scenarioHeader = Options:CreateSectionHeader(content, L["Scenario"])
    scenarioHeader:SetPoint("TOPLEFT", shadowSizeSlider, "BOTTOMLEFT", 0, -16)

    local scShadowGet, scShadowSet = scenarioSetting("scenarioTextShadow")
    local scShadowCheck = Options:CreateCheckbox(content, L["Text Shadow"], scShadowGet, scShadowSet,
        L["Draws a drop-shadow behind the scenario / delve banner text (the Stage and name lines). This is SEPARATE from the Text Shadow above, which affects only the quest and objective text — the banner is styled on its own."])
    scShadowCheck:SetPoint("TOPLEFT", scenarioHeader, "BOTTOMLEFT", 0, -10)

    local function scShadowColorGet()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.scenarioTextShadowColor or { r = 0, g = 0, b = 0, a = 1 }
    end
    local function scShadowColorSet(c)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.scenarioTextShadowColor = c end
        local S = ns:GetSubsystem("TrackerScenario")
        if S and S.ApplyBannerShadow then S:ApplyBannerShadow() end
    end
    local scShadowPicker = Options:CreateColorPicker(content, L["Shadow Color"], scShadowColorGet, scShadowColorSet)
    scShadowPicker:SetPoint("LEFT", scShadowCheck, "RIGHT", 120, 0)

    local scStrGet, scStrSet = scenarioSetting("scenarioTextShadowStrength")
    local scShadowSizeSlider = Options:CreateSlider(content, L["Shadow Size"], 1, 6, 1, scStrGet, scStrSet)
    scShadowSizeSlider:SetPoint("TOPLEFT", scShadowCheck, "BOTTOMLEFT", 0, -14)
    scShadowSizeSlider:SetWidth(280)
    Options:AttachTooltip(scShadowSizeSlider, L["Shadow Size"],
        L["How far the scenario banner's drop-shadow is cast. Higher values give a larger, more pronounced shadow; lower values keep it tight. Only applies while the Scenario Text Shadow above is on."])

    -- "Tracker" section header over the main tracker's Background / Border
    -- controls (distinguishing them from the Scenario block above and the Zone
    -- Bar Appearance group in the right column). Same red CreateSectionHeader
    -- style as every other header; L["Tracker"] is already a translated key.
    local trackerHeader = Options:CreateSectionHeader(content, L["Tracker"])
    trackerHeader:SetPoint("TOPLEFT", scShadowSizeSlider, "BOTTOMLEFT", 0, -16)

    local bgGet, bgSet = trackerSetting("showBackground")
    local bgCheck = Options:CreateCheckbox(content, L["Background"], bgGet, bgSet)
    bgCheck:SetPoint("TOPLEFT", trackerHeader, "BOTTOMLEFT", 0, -10)

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
    local bgPicker = Options:CreateColorPicker(content, L["Background Color"], bgColorGet, bgColorSet)
    bgPicker:SetPoint("LEFT", bgCheck, "RIGHT", 120, 0)
    -- Shadow Color (main) and the Scenario Shadow Color both sit above this row;
    -- snap their swatches into Background Color's column so the whole left-column
    -- colour stack lines up cleanly.
    alignSwatchTo(shadowPicker, bgPicker)
    alignSwatchTo(scShadowPicker, bgPicker)

    -- Optional border around the tracker (wraps the background region).
    -- Off by default; the color picker carries the same Class/Default
    -- options as every other EQ picker. Sits directly under Background so the
    -- swatch stays in the shared colour column with Background Color.
    local borderGet, borderSet = trackerSetting("showBorder")
    local borderCheck = Options:CreateCheckbox(content, L["Border"], borderGet, borderSet)
    borderCheck:SetPoint("TOPLEFT", bgCheck, "BOTTOMLEFT", 0, -10)

    local function borderColorGet()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.borderColor or { r = 0.635, g = 0.000, b = 0.039, a = 1 }
    end
    local function borderColorSet(c)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.borderColor = c end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker then Tracker:Refresh() end
    end
    local borderPicker = Options:CreateColorPicker(content, L["Border Color"], borderColorGet, borderColorSet)
    borderPicker:SetPoint("TOPLEFT", bgPicker, "BOTTOMLEFT", 0, -8)
    alignSwatchTo(borderPicker, bgPicker)

    local bThickGet, bThickSet = trackerSetting("borderSize")
    local borderThickSlider = Options:CreateSlider(content, L["Border Thickness"], 1, 5, 1, bThickGet, bThickSet)
    borderThickSlider:SetPoint("TOPLEFT", borderCheck, "BOTTOMLEFT", 0, -20)
    borderThickSlider:SetWidth(280)

    -- ─── Tracker Skins: scroll-bar styling ──────────────────────────────
    -- All scroll-bar appearance in one place (requested by Fostot): the faint
    -- background strip behind the bar (toggle + colour), an opt-in solid-colour
    -- thumb block (colour + width), and hiding the up/down arrow buttons. The
    -- thumb + arrow options drive the ScrollBar skin in Tracker/Frame.lua.
    -- NOTE: this whole Tracker Skins block is created here but POSITIONED in the
    -- RIGHT column, beneath Zone Bar Appearance. skinsHeader is anchored at the
    -- END of this builder (once zbHeaderPicker exists); every control below
    -- anchors to skinsHeader, so the whole block follows it into the right column.
    local skinsHeader = Options:CreateSectionHeader(content, L["Tracker Skins"])

    -- Background strip behind the bar (toggle + colour).
    local sbGet, sbSet = trackerSetting("scrollBarBg")
    local sbCheck = Options:CreateCheckbox(content, L["Scroll Bar Background"], sbGet, sbSet)
    sbCheck:SetPoint("TOPLEFT", skinsHeader, "BOTTOMLEFT", 0, -10)

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
    local sbPicker = Options:CreateColorPicker(content, L["Scroll Bar Color"], sbColorGet, sbColorSet)
    sbPicker:SetPoint("LEFT", sbCheck, "RIGHT", 170, 0)

    -- Solid-colour thumb (the draggable block). Opt-in: off = the stock
    -- textured Blizzard bar. Colour + width apply only while this is on.
    local thumbSkinGet, thumbSkinSet = trackerSetting("skinScrollBar")
    local thumbSkinCheck = Options:CreateCheckbox(content, L["Solid color thumb"],
        thumbSkinGet, thumbSkinSet,
        L["Replaces the tracker scroll bar's textured thumb (the draggable block) with a flat single-colour block. Use the Thumb Color and Thumb Width controls to style it. Off restores the stock Blizzard bar."])
    thumbSkinCheck:SetPoint("TOPLEFT", sbCheck, "BOTTOMLEFT", 0, -12)

    local function thumbColorGet()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.scrollBarThumbColor or { r = 0.60, g = 0.60, b = 0.65, a = 0.90 }
    end
    local function thumbColorSet(c)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.scrollBarThumbColor = c end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker then Tracker:Refresh() end
    end
    local thumbColorPicker = Options:CreateColorPicker(content, L["Thumb Color"], thumbColorGet, thumbColorSet)
    thumbColorPicker:SetPoint("LEFT", thumbSkinCheck, "RIGHT", 170, 0)
    -- "Thumb Color" is a shorter label than "Scroll Bar Color", so snap its
    -- swatch into the Scroll Bar Color column above so the two line up.
    alignSwatchTo(thumbColorPicker, sbPicker)

    local twGet, twSet = trackerSetting("scrollBarThumbWidth")
    local thumbWidthSlider = Options:CreateSlider(content, L["Thumb Width"], 4, 16, 1, twGet, twSet)
    thumbWidthSlider:SetPoint("TOPLEFT", thumbSkinCheck, "BOTTOMLEFT", 0, -14)
    thumbWidthSlider:SetWidth(280)

    local hideArrowsGet, hideArrowsSet = trackerSetting("hideScrollArrows")
    local hideArrowsCheck = Options:CreateCheckbox(content, L["Hide scroll bar arrows"],
        hideArrowsGet, hideArrowsSet,
        L["Hides the up and down arrow buttons at the ends of the tracker scroll bar. The bar still scrolls by dragging the thumb or using the mouse wheel."])
    hideArrowsCheck:SetPoint("TOPLEFT", thumbWidthSlider, "BOTTOMLEFT", 0, -14)

    -- ─── RIGHT COLUMN: colors + dimensions ──────────────────────────────
    local colorsHeader = Options:CreateSectionHeader(content, L["Colors & Dimensions"])
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
    local titlePicker = Options:CreateColorPicker(content, L["Quest Title Color Override"], titleColorGet, titleColorSet)
    titlePicker:SetPoint("TOPLEFT", colorsHeader, "BOTTOMLEFT", 0, -16)

    local clearBtn = Options:CreateYellowButton(content, L["Clear"], clearTitleColor)
    clearBtn:SetSize(60, 18)
    clearBtn:SetPoint("LEFT", titlePicker, "RIGHT", 8, 0)

    Options:AttachTooltip(titlePicker, L["Quest Title Color Override"],
        L["When cleared, falls back to difficulty coloring or default yellow."])

    -- Use the chosen title color for completed quests instead of the default
    -- "ready to turn in" green (recolors the title + completed objective lines;
    -- the checkmark still marks them done). On by default, but only takes
    -- effect once a title color is set above — with no color chosen there's
    -- nothing to override green with, so completed quests stay green.
    local recolorGet, recolorSet = trackerSetting("overrideCompleteGreen")
    local recolorCheck = Options:CreateCheckbox(content,
        L["Use title color for completed quests"],
        recolorGet, recolorSet,
        L["Instead of green."])
    recolorCheck:SetPoint("TOPLEFT", titlePicker, "BOTTOMLEFT", 0, -10)

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
    local headerPicker = Options:CreateColorPicker(content, L["Section Header Color"], headerColorGet, headerColorSet)
    headerPicker:SetPoint("TOPLEFT", recolorCheck, "BOTTOMLEFT", 0, -16)
    -- "Section Header Color" is a shorter label than "Quest Title Color
    -- Override", so snap its swatch into the title-override column above.
    alignSwatchTo(headerPicker, titlePicker)

    -- Tracker scale 0.7 - 1.5
    local function scaleGet()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.scale or 1.0
    end
    local function scaleSet(value)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.scale = value end
        local Tracker = ns:GetSubsystem("Tracker")
        if not Tracker then return end
        -- SetScale is protected once the tracker has secure item-button
        -- descendants. Out of combat: apply now (responsive slider). In
        -- combat: just save + Refresh — Render applies it combat-safely
        -- (deferred to combat-end) via the single guarded code path.
        if not InCombatLockdown() and Tracker.frame then
            Tracker.frame:SetScale(value)
        elseif Tracker.Refresh then
            Tracker:Refresh()
        end
    end
    local scaleSlider = Options:CreateSlider(content, L["Tracker Scale"], 0.7, 1.5, 0.05, scaleGet, scaleSet)
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
    local spacingSlider = Options:CreateSlider(content, L["Block Spacing"], 0, 12, 1, spacingGet, spacingSet)
    spacingSlider:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", 0, -16)
    spacingSlider:SetWidth(280)

    -- Zone progress bar scale (only the floating bar; the tracker-section
    -- variant follows the tracker's own scale). 0.5 - 2.0.
    local function zbScaleGet()
        local DB = ns:GetSubsystem("DB")
        local st = DB and DB.db.profile.tracker.zoneProgressBar
        return (st and st.scale) or 1.0
    end
    local function zbScaleSet(value)
        local ZP = ns:GetSubsystem("TrackerZoneProgress")
        if ZP and ZP.SetScale then
            ZP:SetScale(value)
        else
            local DB = ns:GetSubsystem("DB")
            local st = DB and DB.db.profile.tracker.zoneProgressBar
            if st then st.scale = value end
        end
    end
    local zbScaleSlider = Options:CreateSlider(content, L["Zone Bar Scale"], 0.5, 2.0, 0.05, zbScaleGet, zbScaleSet)
    zbScaleSlider:SetPoint("TOPLEFT", spacingSlider, "BOTTOMLEFT", 0, -16)
    zbScaleSlider:SetWidth(280)

    -- ─── Zone Bar appearance (floating bar only) ────────────────────────
    -- Mirrors the floating frame's chrome: background + border toggles, a font
    -- override (typeface only — size/outline follow the tracker), and the header
    -- + count text colors. The tracker-docked variant is unaffected (it uses the
    -- tracker's own section header + font). All writes go through ZoneProgress
    -- setters so the change previews live on a visible bar.
    local function zbState()
        local DB = ns:GetSubsystem("DB")
        local p = DB and DB.db.profile.tracker
        if not p then return nil end
        p.zoneProgressBar = p.zoneProgressBar or {}
        return p.zoneProgressBar
    end
    local function zbZP() return ns:GetSubsystem("TrackerZoneProgress") end

    local zbHeader = Options:CreateSectionHeader(content, L["Zone Bar Appearance"])
    zbHeader:SetPoint("TOPLEFT", zbScaleSlider, "BOTTOMLEFT", 0, -20)

    -- Background + Border toggles (checked = shown), side by side.
    local zbBgGet = function() local st = zbState(); return not (st and st.showBackground == false) end
    local zbBgSet = function(v)
        local st = zbState(); if st then st.showBackground = v end
        local ZP = zbZP(); if ZP and ZP.SetShowBackground then ZP:SetShowBackground(v) end
    end
    local zbBgCheck = Options:CreateCheckbox(content, L["Background"], zbBgGet, zbBgSet)
    zbBgCheck:SetPoint("TOPLEFT", zbHeader, "BOTTOMLEFT", 0, -12)

    local zbBorderGet = function() local st = zbState(); return not (st and st.showBorder == false) end
    local zbBorderSet = function(v)
        local st = zbState(); if st then st.showBorder = v end
        local ZP = zbZP(); if ZP and ZP.SetShowBorder then ZP:SetShowBorder(v) end
    end
    local zbBorderCheck = Options:CreateCheckbox(content, L["Border"], zbBorderGet, zbBorderSet)
    zbBorderCheck:SetPoint("LEFT", zbBgCheck, "LEFT", 150, 0)

    -- Border color sits right of the Border toggle (default brand red).
    local function zbBorderColorGet()
        local st = zbState()
        return (st and st.borderColor) or { r = 0.635, g = 0.000, b = 0.039, a = 1 }
    end
    local function zbBorderColorSet(c)
        local st = zbState(); if st then st.borderColor = c end
        local ZP = zbZP(); if ZP and ZP.SetBorderColor then ZP:SetBorderColor(c) end
    end
    local zbBorderColorPicker = Options:CreateColorPicker(content, L["Border Color"], zbBorderColorGet, zbBorderColorSet)
    zbBorderColorPicker:SetPoint("LEFT", zbBorderCheck, "LEFT", 90, 0)

    -- Font typeface override. "" = follow the tracker font (the default row).
    local zbFontList = { { value = "", label = L["Same as tracker font"] } }
    do
        local base = (Media and Media.GetFontList and Media:GetFontList()) or {}
        for i = 1, #base do zbFontList[#zbFontList + 1] = base[i] end
    end
    local zbFontGet = function() local st = zbState(); return (st and st.font) or "" end
    local zbFontSet = function(v)
        local st = zbState(); if st then st.font = (v ~= "" and v) or nil end
        local ZP = zbZP(); if ZP and ZP.SetBarFont then ZP:SetBarFont(v) end
    end
    local zbFontDD = Options:CreateFontDropdown(content, L["Font"], zbFontList, zbFontGet, zbFontSet)
    zbFontDD:SetPoint("TOPLEFT", zbBgCheck, "BOTTOMLEFT", 0, -14)
    zbFontDD:SetWidth(280)

    -- Header (zone name) + count (x/x) text colors, side by side.
    local function zbHeaderColorGet()
        local st = zbState()
        return (st and st.headerColor) or { r = 0.93, g = 0.32, b = 0.10, a = 1 }
    end
    local function zbHeaderColorSet(c)
        local st = zbState(); if st then st.headerColor = c end
        local ZP = zbZP(); if ZP and ZP.SetHeaderColor then ZP:SetHeaderColor(c) end
    end
    local zbHeaderPicker = Options:CreateColorPicker(content, L["Header Color"], zbHeaderColorGet, zbHeaderColorSet)
    zbHeaderPicker:SetPoint("TOPLEFT", zbFontDD, "BOTTOMLEFT", 0, -16)

    local function zbCountColorGet()
        local st = zbState()
        return (st and st.countColor) or { r = 0.92, g = 0.72, b = 0.02, a = 1 }
    end
    local function zbCountColorSet(c)
        local st = zbState(); if st then st.countColor = c end
        local ZP = zbZP(); if ZP and ZP.SetCountColor then ZP:SetCountColor(c) end
    end
    local zbCountPicker = Options:CreateColorPicker(content, L["Count Color"], zbCountColorGet, zbCountColorSet)
    zbCountPicker:SetPoint("TOPLEFT", zbHeaderPicker, "TOPRIGHT", 40, 0)

    -- Tracker Skins (built up in the left-column code) is positioned HERE, in the
    -- right column beneath Zone Bar Appearance. Anchoring its header now — after
    -- zbHeaderPicker exists — pulls the whole block (created earlier) into place.
    skinsHeader:SetPoint("TOPLEFT", zbHeaderPicker, "BOTTOMLEFT", 0, -20)
end)
