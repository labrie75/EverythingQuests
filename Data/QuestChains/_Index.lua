-- Data/QuestChains/_Index.lua
-- Registers the Midnight expansion + its zone categories with the
-- ChainGuideDatabase. Each per-zone file (EversongWoods.lua, etc.) registers
-- its own chains and references these category IDs.
--
-- The `mapID` on each category is the uiMapID used by
-- C_QuestLine.GetAvailableQuestLines to discover chains live from Blizzard's
-- own questline database. uiMapIDs change between expansions and revamps;
-- run "/eqs discover" while standing in a zone to print the active uiMapID
-- and update the values below.
--
-- Loaded BEFORE the per-zone data files so registration order is deterministic.

local _, ns = ...

local DBmod = ns:GetSubsystem("ChainGuideDatabase")

ns.EXP_MIDNIGHT = 11

DBmod:RegisterExpansion(ns.EXP_MIDNIGHT, {
    name = "Midnight",
    icon = nil,
    minLevel = 80,
    maxLevel = 90,
})

ns.CAT = {
    CAMPAIGN       = 1100,
    EVERSONG_WOODS = 1101,
    ZULAMAN        = 1102,
    HARANDAR       = 1103,
    VOIDSTORM      = 1104,
    ARATOR         = 1105,
}

-- A category may pull questlines from multiple uiMapIDs (a zone + its city,
-- a continent + its sub-zones, etc.). Seeds are best-effort; runtime
-- /eqs discover appends to a per-character override list that takes
-- priority and persists across sessions.
--
-- The CAMPAIGN category has no mapIDs of its own — its chains are
-- expansion-spanning storylines that get routed in via _QuestLineRouting.lua
-- regardless of which zone surfaced them.
DBmod:RegisterCategory(ns.CAT.CAMPAIGN,       { expansion = ns.EXP_MIDNIGHT, name = "Midnight Campaign", mapIDs = {} })
DBmod:RegisterCategory(ns.CAT.EVERSONG_WOODS, { expansion = ns.EXP_MIDNIGHT, name = "Eversong Woods", mapIDs = {} })
DBmod:RegisterCategory(ns.CAT.ZULAMAN,        { expansion = ns.EXP_MIDNIGHT, name = "Zul'Aman",       mapIDs = {} })
DBmod:RegisterCategory(ns.CAT.HARANDAR,       { expansion = ns.EXP_MIDNIGHT, name = "Harandar",       mapIDs = {} })
DBmod:RegisterCategory(ns.CAT.VOIDSTORM,      { expansion = ns.EXP_MIDNIGHT, name = "Voidstorm",      mapIDs = {} })
DBmod:RegisterCategory(ns.CAT.ARATOR,         { expansion = ns.EXP_MIDNIGHT, name = "Arator",         mapIDs = {} })
