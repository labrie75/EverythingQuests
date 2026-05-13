-- Data/QuestChains/EversongWoods.lua
-- Hand-authored chain definitions for Eversong Woods.
--
-- Chains in this category are fully populated by the questline routing
-- table (Data/QuestChains/_QuestLineRouting.lua) + Blizzard's questline
-- API. Add a definition here only when you want to *override* the
-- API-sourced chain — e.g. give it a hand-laid-out node graph with
-- prerequisite branching that the API can't expose.
--
-- Schema:
--   id        — globally unique chain ID (use a number outside the
--               5,000,000+ range reserved for API-sourced chains)
--   category  — ns.CAT.EVERSONG_WOODS
--   name      — display name shown in the chain list and chain header
--   range     — { minLevel, maxLevel }
--   questlineID = N  (suppresses the API stub for questline N so this
--                     hand-authored definition is shown instead)
--   items     — node graph; see Modules/ChainGuide/ChainView.lua for the
--               full item shape (type, id, x, y, connections, variations)

local _, ns = ...
local _DBmod = ns:GetSubsystem("ChainGuideDatabase")
