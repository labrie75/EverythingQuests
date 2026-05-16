local _, ns = ...

local Media = ns:RegisterSubsystem("Media", {})

-- Quest-complete sound roster — IDs sourced from KalielsTracker's Media.lua
-- so the user gets the same options they're used to. Default ("Work Complete")
-- is the peon "Work complete" voice line.
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

-- Bundled fonts. Files live in Media/Fonts/ and ship with the addon so the
-- default typeface works with zero external dependencies. The registered
-- name must match the DB default (Core/DB.lua tracker.font) exactly — LSM
-- lookups are case- and space-sensitive.
local FONTS = {
    { name = "GothamNarrow Black", file = [[Interface\AddOns\EverythingQuests\Media\Fonts\GothamNarrow-Black.ttf]] },
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
    local LSM = self.LSM
    if not LSM then
        out[#out + 1] = { value = "Friz Quadrata TT", label = "Friz Quadrata TT" }
        return out
    end
    local fonts = LSM:HashTable("font")
    local names = {}
    for k in pairs(fonts) do names[#names + 1] = k end
    table.sort(names)
    for _, name in ipairs(names) do
        out[#out + 1] = { value = name, label = name }
    end
    return out
end

function Media:GetFontFile(name)
    local LSM = self.LSM
    if LSM then
        local f = LSM:Fetch("font", name or "Friz Quadrata TT")
        if f then return f end
    end
    return STANDARD_TEXT_FONT
end

-- Apply the user's tracker font to a FontString. sizeDelta is added to the
-- configured size (e.g., -2 for sub-text, -3 for category labels).
function Media:ApplyTrackerFont(fontstring, sizeDelta)
    if not fontstring then return end
    local DB = ns:GetSubsystem("DB")
    if not DB then return end
    local cfg = DB.db.profile.tracker
    local file = self:GetFontFile(cfg.font)
    local size = math.max(8, (cfg.fontSize or 12) + (sizeDelta or 0))
    local outline = cfg.fontOutline or ""
    if file then fontstring:SetFont(file, size, outline) end
end
