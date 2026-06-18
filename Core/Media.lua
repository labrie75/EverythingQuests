local _, ns = ...

local Media = ns:RegisterSubsystem("Media", {})

-- Quest-complete sound roster — standard WoW voice/UI sound file IDs so the
-- options are familiar. Default ("Work Complete") is the peon "Work
-- complete" voice line.
local SOUNDS = {
    { name = "EQ: Work Complete",   file = 558132 },   -- PeonBuildingComplete1.ogg
    { name = "EQ: BloodElf (M)",    file = 539400 },
    { name = "EQ: BloodElf (F)",    file = 539175 },
    { name = "EQ: Draenei (M)",     file = 539661 },
    { name = "EQ: Draenei (F)",     file = 539676 },
    { name = "EQ: Dwarf (M)",       file = 540042 },
    { name = "EQ: Dwarf (F)",       file = 539981 },
    { name = "EQ: Gnome (M)",       file = 540512 },
    { name = "EQ: Gnome (F)",       file = 540432 },
    { name = "EQ: Goblin (M)",      file = 542005 },
    { name = "EQ: Goblin (F)",      file = 541735 },
    { name = "EQ: Human (M)",       file = 540703 },
    { name = "EQ: Human (F)",       file = 540654 },
    { name = "EQ: NightElf (M)",    file = 541085 },
    { name = "EQ: NightElf (F)",    file = 541031 },
    { name = "EQ: Orc (M)",         file = 541401 },
    { name = "EQ: Orc (F)",         file = 541317 },
    { name = "EQ: Pandaren (M)",    file = 630070 },
    { name = "EQ: Pandaren (F)",    file = 636419 },
    { name = "EQ: Tauren (M)",      file = 561484 },
    { name = "EQ: Tauren (F)",      file = 542997 },
    { name = "EQ: Troll (M)",       file = 543307 },
    { name = "EQ: Troll (F)",       file = 543273 },
    { name = "EQ: Undead (M)",      file = 542775 },
    { name = "EQ: Undead (F)",      file = 542684 },
    { name = "EQ: Worgen (M)",      file = 542228 },
    { name = "EQ: Worgen (F)",      file = 542028 },
}

-- Bundled fonts. Files live in Media/Fonts/ (alongside their OFL / Ubuntu
-- licence .txt files) and ship with the addon so every user gets the full
-- selection with zero external dependencies. Registered names are what the
-- user sees in the Appearance font dropdown. The first entry is the DB
-- default (Core/DB.lua tracker.font) and must match it exactly — LSM
-- lookups are case- and space-sensitive.
local FONT_PATH = [[Interface\AddOns\EverythingQuests\Media\Fonts\]]
local FONTS = {
    { name = "GothamXNarrow Black",      file = FONT_PATH .. "GothamXNarrow-Black.ttf" },  -- DB default
    { name = "Avquest",                  file = FONT_PATH .. "Avquest.ttf" },
    { name = "Barlow Condensed",         file = FONT_PATH .. "BarlowCondensed-Regular.ttf" },
    { name = "Barlow Condensed Medium",  file = FONT_PATH .. "BarlowCondensed-Medium.ttf" },
    { name = "Barlow Condensed SemiBold",file = FONT_PATH .. "BarlowCondensed-SemiBold.ttf" },
    { name = "Barlow Condensed Bold",    file = FONT_PATH .. "BarlowCondensed-Bold.ttf" },
    { name = "Beep",                     file = FONT_PATH .. "Beep-Regular.otf" },
    { name = "Beep Medium",              file = FONT_PATH .. "Beep-Medium.otf" },
    { name = "Beep Bold",                file = FONT_PATH .. "Beep-Bold.otf" },
    { name = "Exo 2 ExtraBold",          file = FONT_PATH .. "Exo2-ExtraBold.ttf" },
    { name = "GoodBrush",                file = FONT_PATH .. "GoodBrush.ttf" },
    { name = "Gotham Narrow Black",      file = FONT_PATH .. "GothamNarrowBlack.ttf" },
    { name = "Inter",                    file = FONT_PATH .. "Inter-Regular.ttf" },
    { name = "Inter SemiBold",           file = FONT_PATH .. "Inter-SemiBold.ttf" },
    { name = "Inter Bold",               file = FONT_PATH .. "Inter-Bold.ttf" },
    { name = "Josefin Sans Bold",        file = FONT_PATH .. "JosefinSans-Bold.ttf" },
    { name = "Kimberley",                file = FONT_PATH .. "Kimberley.ttf" },
    { name = "Lemon",                    file = FONT_PATH .. "Lemon-Regular.ttf" },
    { name = "Metal Lord",               file = FONT_PATH .. "Metal-Lord.ttf" },
    { name = "Montserrat",               file = FONT_PATH .. "Montserrat-Regular.ttf" },
    { name = "Montserrat Medium",        file = FONT_PATH .. "Montserrat-Medium.ttf" },
    { name = "Montserrat SemiBold",      file = FONT_PATH .. "Montserrat-SemiBold.ttf" },
    { name = "Montserrat Bold",          file = FONT_PATH .. "Montserrat-Bold.ttf" },
    { name = "Neuropol X",               file = FONT_PATH .. "neuropolxrg.ttf" },
    { name = "Noto Sans",                file = FONT_PATH .. "NotoSans-Regular.ttf" },
    { name = "Noto Sans SemiBold",       file = FONT_PATH .. "NotoSans-SemiBold.ttf" },
    { name = "Noto Sans Bold",           file = FONT_PATH .. "NotoSans-Bold.ttf" },
    { name = "Optimus Princeps",         file = FONT_PATH .. "OptimusPrinceps.ttf" },
    { name = "Oswald Light",             file = FONT_PATH .. "Oswald-Light.ttf" },
    { name = "Oswald",                   file = FONT_PATH .. "Oswald-Regular.ttf" },
    { name = "Oswald Bold",              file = FONT_PATH .. "Oswald-Bold.ttf" },
    { name = "Pepsi",                    file = FONT_PATH .. "Pepsi-Cyr-Lat.ttf" },
    { name = "Pricedown",                file = FONT_PATH .. "pricedown.ttf" },
    { name = "Reckoner",                 file = FONT_PATH .. "Reckoner.ttf" },
    { name = "Reckoner Bold",            file = FONT_PATH .. "Reckoner_Bold.ttf" },
    { name = "RingLink Medium",          file = FONT_PATH .. "RingLink-Medium.otf" },
    { name = "RingLink Bold",            file = FONT_PATH .. "RingLink-Bold.otf" },
    { name = "Roboto Bold",              file = FONT_PATH .. "Roboto-Bold.ttf" },
    { name = "Simply Sans",              file = FONT_PATH .. "SimplySans-Book.ttf" },
    { name = "Simply Sans Bold",         file = FONT_PATH .. "SimplySans-Bold.ttf" },
    { name = "Ubuntu Medium",            file = FONT_PATH .. "Ubuntu-Medium.ttf" },
    { name = "Ubuntu Bold",              file = FONT_PATH .. "Ubuntu-Bold.ttf" },
}

-- WoW's own built-in fonts, for users who want the stock look. "WoW Default"
-- points at STANDARD_TEXT_FONT so it stays locale-correct (the client swaps in
-- the right Friz Quadrata glyphs for Cyrillic/Korean/etc.). LSM already ships
-- locale-aware registrations for some of these names; LSM:Register is a no-op
-- when a name already exists, so listing them here is harmless either way.
local WOW_FONTS = {
    { name = "WoW Default (Friz Quadrata)", file = STANDARD_TEXT_FONT or [[Fonts\FRIZQT__.TTF]] },
    { name = "WoW Arial Narrow",            file = [[Fonts\ARIALN.TTF]] },
    { name = "WoW Morpheus",                file = [[Fonts\MORPHEUS.TTF]] },
}

function Media:OnInitialize()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return end
    for _, s in ipairs(SOUNDS) do
        LSM:Register("sound", s.name, s.file)
    end
    for _, f in ipairs(FONTS) do
        LSM:Register("font", f.name, f.file)
    end
    for _, f in ipairs(WOW_FONTS) do
        LSM:Register("font", f.name, f.file)
    end
    self.LSM = LSM
end

function Media:GetSoundList()
    local out = { { value = "NONE", label = "None" } }
    for _, s in ipairs(SOUNDS) do
        out[#out + 1] = { value = s.name, label = s.name:gsub("^EQ: ", "") }
    end
    return out
end

function Media:GetSoundFile(name)
    if name == "NONE" then return nil end
    local LSM = self.LSM
    if LSM then
        local f = LSM:Fetch("sound", name)
        if f then return f end
    end
    for _, s in ipairs(SOUNDS) do
        if s.name == name then return s.file end
    end
    return SOUNDS[1].file
end

function Media:GetFontList()
    local out = {}
    for _, f in ipairs(WOW_FONTS) do
        out[#out + 1] = { value = f.name, label = f.name }
    end
    for _, f in ipairs(FONTS) do
        out[#out + 1] = { value = f.name, label = f.name }
    end
    return out
end

function Media:GetFontFile(name)
    local LSM = self.LSM
    if LSM then
        local f = LSM:Fetch("font", name or "Friz Quadrata TT")
        if f then return f end
    end
    -- LSM missing: resolve our own WoW-font names before the generic fallback.
    for _, f in ipairs(WOW_FONTS) do
        if f.name == name then return f.file end
    end
    return STANDARD_TEXT_FONT
end

-- Drop-shadow behind tracker text (Appearance "Text Shadow"). When enabled,
-- a coloured shadow at a fixed (2,-2) offset; when disabled, the shadow is
-- explicitly cleared (alpha 0 + zero offset) so a font template's inherited
-- shadow never lingers. The 2px offset is deliberate: the tracker font's
-- default OUTLINE draws a ~1px dark border that fully hides a 1px shadow, so
-- the shadow has to sit far enough out to read past the outline. Allocation-free.
local function applyShadow(cfg, fontstring)
    if cfg and cfg.textShadow then
        local c = cfg.textShadowColor
        fontstring:SetShadowColor(c and c.r or 0, c and c.g or 0, c and c.b or 0, c and c.a or 1)
        fontstring:SetShadowOffset(2, -2)
    else
        fontstring:SetShadowColor(0, 0, 0, 0)
        fontstring:SetShadowOffset(0, 0)
    end
end

-- Apply the user's tracker font to a FontString. sizeDelta is added to the
-- configured size (e.g., -2 for sub-text, -3 for category labels). fontOverride
-- (optional) swaps just the typeface — size and outline still come from the
-- tracker config — so a surface can use its own font while honoring the global
-- size/outline (used by the floating Zone Bar's per-bar font option).
function Media:ApplyTrackerFont(fontstring, sizeDelta, fontOverride)
    if not fontstring then return end
    local DB = ns:GetSubsystem("DB")
    if not DB then return end
    local cfg = DB.db.profile.tracker
    local file = self:GetFontFile(fontOverride or cfg.font)
    local size = math.max(8, (cfg.fontSize or 12) + (sizeDelta or 0))
    local outline = cfg.fontOutline or ""
    if file then fontstring:SetFont(file, size, outline) end
    applyShadow(cfg, fontstring)
end

-- Apply the tracker font at the user's independent TITLE size: the base font
-- size plus the Appearance "Title Size Offset" (tracker.titleSizeDelta). Used
-- for quest/achievement/profession/etc. title lines so titles can be sized
-- apart from objective text. fontOverride swaps just the typeface (Zone Bar).
function Media:ApplyTrackerTitleFont(fontstring, fontOverride)
    if not fontstring then return end
    local DB = ns:GetSubsystem("DB")
    if not DB then return end
    local cfg = DB.db.profile.tracker
    self:ApplyTrackerFont(fontstring, cfg.titleSizeDelta or 0, fontOverride)
end

-- Apply only the text-shadow setting to a FontString whose font is set
-- elsewhere — the quest-block path in Tracker/Blocks.lua sets its own font
-- directly (per-pass, change-gated) rather than via ApplyTrackerFont.
function Media:ApplyTextShadow(fontstring)
    if not fontstring then return end
    local DB = ns:GetSubsystem("DB")
    if not DB then return end
    applyShadow(DB.db.profile.tracker, fontstring)
end
