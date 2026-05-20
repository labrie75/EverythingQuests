-- Core/TooltipScan.lua
-- Structured tooltip reader. Wraps Blizzard's C_TooltipInfo so callers
-- get back a clean array of TooltipLineData ({ leftText, rightText, type,
-- ... }) per tooltip — no transient tooltip frames, no hidden FontStrings
-- to scan, no conflicts with other tooltip mods.
--
-- Read-only, no side effects, allocation-free at this layer (the data
-- table is what C_TooltipInfo itself produces and returns). Pair with the
-- Profiler if you're investigating allocation in a tooltip-heavy feature.
--
-- Typical use:
--     local TS    = ns:GetSubsystem("TooltipScan")
--     local lines = TS:ScanItem(itemLink)
--     if lines then
--         for i = 1, #lines do
--             local ln = lines[i]
--             -- ln.leftText, ln.rightText, ln.type, ln.wrapText, etc.
--         end
--     end

local _, ns = ...

local TS = ns:RegisterSubsystem("TooltipScan", {})

-- Returns the lines array for an item hyperlink (e.g. "|cffa335ee|Hitem:...|h").
function TS:ScanItem(link)
    if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink and link) then return nil end
    local data = C_TooltipInfo.GetHyperlink(link)
    return data and data.lines or nil
end

-- Returns the lines array for an item ID directly (no hyperlink needed).
function TS:ScanItemByID(itemID)
    if not (C_TooltipInfo and C_TooltipInfo.GetItemByID and itemID) then return nil end
    local data = C_TooltipInfo.GetItemByID(itemID)
    return data and data.lines or nil
end

-- Returns the lines array for a spell.
function TS:ScanSpell(spellID)
    if not (C_TooltipInfo and C_TooltipInfo.GetSpellByID and spellID) then return nil end
    local data = C_TooltipInfo.GetSpellByID(spellID)
    return data and data.lines or nil
end

-- Returns the lines array for a quest by ID. Uses a "quest:ID" synthetic
-- hyperlink — the path Blizzard accepts on retail for quest tooltips.
function TS:ScanQuest(questID)
    if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink and questID) then return nil end
    local data = C_TooltipInfo.GetHyperlink("quest:" .. questID)
    return data and data.lines or nil
end
