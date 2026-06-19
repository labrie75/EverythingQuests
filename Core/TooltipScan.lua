local _, ns = ...

local TS = ns:RegisterSubsystem("TooltipScan", {})

function TS:ScanItem(link)
    if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink and link) then return nil end
    local data = C_TooltipInfo.GetHyperlink(link)
    return data and data.lines or nil
end

function TS:ScanItemByID(itemID)
    if not (C_TooltipInfo and C_TooltipInfo.GetItemByID and itemID) then return nil end
    local data = C_TooltipInfo.GetItemByID(itemID)
    return data and data.lines or nil
end

function TS:ScanSpell(spellID)
    if not (C_TooltipInfo and C_TooltipInfo.GetSpellByID and spellID) then return nil end
    local data = C_TooltipInfo.GetSpellByID(spellID)
    return data and data.lines or nil
end

function TS:ScanQuest(questID)
    if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink and questID) then return nil end
    local data = C_TooltipInfo.GetHyperlink("quest:" .. questID)
    return data and data.lines or nil
end
