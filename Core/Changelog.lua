-- Core/Changelog.lua
-- Embedded, condensed changelog rendered by the About tab (Options/TabAbout.lua).
-- Add-ons can't read CHANGELOG.md at runtime, so the recent history lives here
-- as a Lua table. Newest first; older versions are on CurseForge.
--
-- ⚠ MAINTENANCE: this is the SECOND home of the changelog. Every release, update
--   BOTH CHANGELOG.md and this table (add the new version at the TOP, trim the
--   tail to ~10 entries). This is part of the "git sequence" release routine.

local _, ns = ...

ns.Changelog = {
    {
        version = "1.19.0", date = "2026-06-14",
        sections = {
            { head = "New Features", items = {
                "Chain Guide overhaul, Phase 1 of 3 — the guide now shows your NEXT step (gold border + a Continue button that routes you there) and tags quests already in your log as ON QUEST. Opening a chain scrolls to where you are.",
                "Rich Chain Guide tooltips — hover a quest for its level, objectives, and rewards, including the gear-upgrade comparison.",
                "Search the Chain Guide by quest name, not just ID (questline names match too).",
            } },
            { head = "Improvements", items = {
                "Chain nodes show each quest's level and ID; a quest ready to turn in is highlighted gold.",
                "Now available in Russian (ruRU), with updated French (frFR). New Chain Guide text will be translated once the overhaul is complete.",
            } },
            { head = "Bug Fixes", items = {
                "Getting directions from the Chain Guide in combat no longer trips an action-blocked error — the map open waits until you leave combat (the quest is still super-tracked immediately).",
            } },
        },
    },
    {
        version = "1.18.0", date = "2026-06-13",
        sections = {
            { head = "New Features", items = {
                "Search the Chain Guide by Quest ID — jumps to the chain containing it and rings the quest, so a non-English client can follow an English guide without translating names. (Sparta || Phrenic)",
                "Tracker Skins (Appearance tab): give the scroll bar a flat single-color thumb with its own color and width, or hide the up/down arrows. (Fostot)",
                "New About tab with links, slash commands, credits, and the changelog (/eqs about).",
            } },
            { head = "Improvements", items = {
                "The tracker background now wraps just your visible quests and hides when empty, instead of a tall empty box. (Spydawg2233)",
                "Every option's grey description moved into a hover tooltip for cleaner panels.",
                "Brightened the brand red used for headers, borders, and accents.",
            } },
            { head = "Bug Fixes", items = {
                "Newly accepted quests now track reliably (a stable manual watch instead of an evictable automatic one).",
            } },
        },
    },
    {
        version = "1.17.0", date = "2026-06-12",
        sections = {
            { head = "New Features", items = {
                "Quest reward gear comparison — hovering a quest in the tracker (and World Quest tooltips) shows each equippable reward's item level versus what you have equipped, and whether it's an upgrade.",
            } },
            { head = "Improvements", items = {
                "The tracker can stretch much taller — its maximum height was roughly doubled. (Spydawg2233)",
            } },
        },
    },
    {
        version = "1.16.0", date = "2026-06-08",
        sections = {
            { head = "New Features", items = {
                "Customize the floating zone progress bar — toggle its background/border, pick a border color, choose its font, and set the header and count colors.",
            } },
            { head = "Improvements", items = {
                "More of the interface displays in French (History tabs, Chain Guide nav and counts). (Zox)",
                "Lighter Chain Guide rendering.",
            } },
        },
    },
    {
        version = "1.15.0", date = "2026-06-07",
        sections = {
            { head = "New Features", items = {
                "Options button in the Chain Guide's navigation bar, opening settings straight to the Chain Guide tab. (Zox)",
            } },
            { head = "Improvements", items = {
                "More of the interface is translatable, plus a round of French refinements. (Zox)",
            } },
        },
    },
    {
        version = "1.14.1", date = "2026-06-06",
        sections = {
            { head = "Bug Fixes", items = {
                "The zone progress bar now shows up reliably on every character, including fully-completed zones.",
            } },
            { head = "Improvements", items = {
                "French translation complete — the whole interface displays in French on a French client. (Zox)",
            } },
        },
    },
    {
        version = "1.14.0", date = "2026-06-06",
        sections = {
            { head = "New Features", items = {
                "French translation (frFR) and localization support — untranslated text falls back to English. (Zox)",
                "Zone progress bar — an optional bar showing approximate questline progress for your current zone.",
            } },
        },
    },
    {
        version = "1.13.1", date = "2026-06-05",
        sections = {
            { head = "Bug Fixes", items = {
                "Fewer \"secret value\" Lua errors from the world map — EQ now draws its map pin tooltips on its own private tooltip.",
            } },
        },
    },
    {
        version = "1.13.0", date = "2026-06-03",
        sections = {
            { head = "New Features", items = {
                "Tracked achievements now appear in their own tracker section. (LightsBeacon)",
                "WoW's built-in fonts added to the Appearance font picker. (Zox)",
                "Auto-list current-zone world quests, and click a world quest map pin to track it. (Zox)",
            } },
            { head = "Improvements", items = {
                "World Quest icons in the tracker, plus an optional Blizzard-style split quest click. (Zox)",
            } },
        },
    },
    {
        version = "1.12.0", date = "2026-06-03",
        sections = {
            { head = "New Features", items = {
                "Sort your Quest History by Date, Name, or Type with a direction toggle.",
            } },
            { head = "Bug Fixes", items = {
                "Manual tracker order no longer loses hidden quests; color pickers keep transparency on Cancel.",
            } },
        },
    },
    {
        version = "1.11.0", date = "2026-06-01",
        sections = {
            { head = "New Features", items = {
                "Stats tab with Trends — chart your quests, XP, and gold over time.",
                "Real (all-source) gold tracking, and a community Discord link.",
            } },
        },
    },
}
