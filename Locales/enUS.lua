-- Locales/enUS.lua
-- Default locale and source-of-truth for translatable strings.
-- Other locale files override these per key when GetLocale() matches.

local _, ns = ...

ns.L = setmetatable({}, { __index = function(_, k) return k end })

local L = ns.L
L["Everything Quests"] = true
L["General"]              = true
L["Tracker"]              = true
L["Quest Log"]            = true
L["World Quests"]         = true
L["Chain Guide"]          = true
L["Appearance"]           = true
L["Open Quest Log"]       = true
L["Options"]              = true
L["Simplify Mode"]        = true
L["Sort by zone"]         = true
L["Sort by status"]       = true
L["Sort by type"]         = true
L["Sort by level"]        = true
L["Sort by distance"]     = true
L["Sort manually (drag)"] = true

-- Convert sentinel `true` values to the key string.
for k, v in pairs(L) do if v == true then L[k] = k end end
