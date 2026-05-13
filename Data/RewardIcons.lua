-- Data/RewardIcons.lua
-- texture path -> reward category. Built from observed WQ rewards in Midnight.
-- Add entries as new currencies/icons appear (Midnight expansion may introduce
-- new tokens; track in CHANGELOG when extending this table).

local _, ns = ...

ns.RewardIcons = {
    -- Resource icons (zone currencies)
    resources = {
        -- ["Interface\\Icons\\inv_misc_questionmark"] = "exampleResource",
    },
    -- Reputation token icons
    reputation = {},
    -- Trade-skill / crafting material icons
    tradeskill = {},
}
