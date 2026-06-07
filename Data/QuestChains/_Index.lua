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
    CAMPAIGN         = 1100,
    EVERSONG_WOODS   = 1101,
    ZULAMAN          = 1102,
    HARANDAR         = 1103,
    VOIDSTORM        = 1104,
    ARATOR           = 1105,
    WAR_LIGHT_SHADOW = 1106,   -- max-level campaign (Blizzard campaign 284)
}

-- A category may pull questlines from multiple uiMapIDs (a zone + its city,
-- a continent + its sub-zones, etc.). Seeds are best-effort; runtime
-- /eqs discover appends to a per-character override list that takes
-- priority and persists across sessions.
--
-- Campaign categories carry a `campaignID` and are sourced live from
-- Blizzard's campaign API (Modules/ChainGuide/CampaignSource.lua), NOT
-- from _QuestLineRouting.lua. campaignIDs are WoW-global stable IDs
-- (same hardcoded-ID convention as the questline IDs), verified in-game
-- via C_CampaignInfo.GetCampaignID on a campaign quest:
--   270 "Midnight"                  → 17 chapters (the leveling campaign)
--   284 "The War of Light and Shadow" → 6 chapters (the max-level campaign)
-- C_CampaignInfo.GetChapterIDs works by ID even for a campaign the
-- character hasn't unlocked yet (284 is queryable at any level), so the
-- max-level spine shows at 0/N before you reach it — that's the point of
-- a guide. CampaignSource falls back to the player's active campaign if
-- a campaignID ever goes stale.
-- `order` drives the Categories pane (Frame.lua sorts by it, then name):
-- the two campaigns first (leveling, then max-level), then the zones in
-- Midnight progression order (Eversong start → … → Voidstorm 88-90),
-- which reads more naturally than an alphabetical jumble.
DBmod:RegisterCategory(ns.CAT.CAMPAIGN,         { expansion = ns.EXP_MIDNIGHT, name = "Midnight Campaign", mapIDs = {}, campaignID = 270, order = 10 })
DBmod:RegisterCategory(ns.CAT.WAR_LIGHT_SHADOW, { expansion = ns.EXP_MIDNIGHT, name = "The War of Light and Shadow", mapIDs = {}, campaignID = 284, order = 20 })
DBmod:RegisterCategory(ns.CAT.EVERSONG_WOODS,   { expansion = ns.EXP_MIDNIGHT, name = "Eversong Woods", mapIDs = { 2393 }, order = 30 })
DBmod:RegisterCategory(ns.CAT.ZULAMAN,          { expansion = ns.EXP_MIDNIGHT, name = "Zul'Aman",       mapIDs = { 2437 }, order = 40 })
DBmod:RegisterCategory(ns.CAT.HARANDAR,         { expansion = ns.EXP_MIDNIGHT, name = "Harandar",       mapIDs = { 2413 }, order = 50 })
-- "Arator's Journey" is a continent-spanning campaign (Light's Hope, Scarlet
-- Monastery, Hammerfall, Blackrock), NOT a zone — so it has no uiMapID to seed
-- and never surfaces a zone-progress bar. Kept as a ChainGuide category only.
DBmod:RegisterCategory(ns.CAT.ARATOR,           { expansion = ns.EXP_MIDNIGHT, name = "Arator",         mapIDs = {}, order = 60 })
DBmod:RegisterCategory(ns.CAT.VOIDSTORM,        { expansion = ns.EXP_MIDNIGHT, name = "Voidstorm",      mapIDs = { 2405 }, order = 70 })
