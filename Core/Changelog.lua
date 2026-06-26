local _, ns = ...

ns.Changelog = {
    {
        version = "1.27.0", date = "2026-06-26",
        sections = {
            { head = "New Features", items = {
                "Chain Guide — added the Void Acropolis zone, with its quest chains (Assault and Strike Back: Val, and Umbral Blitz) now mapped out so you can follow them like the rest of the Midnight zones.",
            } },
            { head = "Improvements", items = {
                "The two right-click options on a tracked quest now read more clearly: \"Open in Map & Quest Log\" (the game's quest map) and \"Pop Out Quest Details\" (Everything Quests' own detail panel).",
                "Appearance sliders (font sizes, shadows, border thickness, bar height, and so on) now adjust in finer 0.5 steps for more precise tuning.",
            } },
            { head = "Bug Fixes", items = {
                "The world-quest map panel no longer overlaps its pull-tab — the panel now sits clear of the tab.",
            } },
        },
    },
    {
        version = "1.26.0", date = "2026-06-25",
        sections = {
            { head = "Improvements", items = {
                "World Quest map panel — the world-quest popout on the world map is now a single docked panel (a reward summary plus a scrollable zone list) instead of separate floating boxes, and its pull-tab matches Blizzard's quest-map side tabs, including ElvUI's styling when its quest skin is active. Thanks to Malevi4 for the request.",
            } },
            { head = "Bug Fixes", items = {
                "The quest list now resizes with the tracker when you drag it wider or narrower — it previously stayed at a fixed width — and the scenario / delve banner now lines up with the quest list instead of drifting to the right on a wider tracker. Thanks to Malevi4 for reporting it and helping track down the cause.",
            } },
            { head = "Translations", items = {
                "Korean (koKR) is now fully translated, thanks to labrie75.",
            } },
        },
    },
    {
        version = "1.25.0", date = "2026-06-23",
        sections = {
            { head = "New Features", items = {
                "Header bar styles & soft edges (Appearance tab) — choose Header Bar 1 (a horizontal gradient) or Header Bar 2 (a vertical gradient), and turn on Soft edges to feather the bar's top, left, and right edges so it blends into the UI. An Edge Softness slider tunes how soft the edges are. Thanks to Malevi4 for the requests.",
                "Reset to Defaults (Appearance tab) — restores just the appearance settings (fonts, colours, shadows, header bar, scroll-bar skin, zone-bar look) to defaults, leaving filters, sections, sounds, and the zone bar's position untouched.",
            } },
            { head = "Improvements", items = {
                "The Appearance tab now scrolls inside the Options window, so it no longer runs off the bottom of the screen.",
            } },
            { head = "Bug Fixes", items = {
                "A campaign quest with a ready-to-turn-in popup could appear twice (once under Campaign, once under Quests); it now renders once, in the correct section.",
            } },
            { head = "Translations", items = {
                "Korean (koKR) is now available, thanks to labrie75 — most of the addon is translated, with more on the way.",
                "Russian (ruRU) wording refinements from Malevi4, plus the new strings; French (frFR) updated by Zox.",
            } },
        },
    },
    {
        version = "1.24.0", date = "2026-06-22",
        sections = {
            { head = "New Features", items = {
                "Header bars (Appearance tab) — an optional coloured gradient bar behind each section header (Quests, Campaign, World Quests, and so on) for a look closer to Blizzard's default tracker. Off by default, with Bar Color and Bar Height controls.",
            } },
            { head = "Improvements", items = {
                "The clickable quest-item button moved to the left of the quest icon, where it's easier to reach, and is slightly bigger; its red border was removed so it's just the icon.",
            } },
            { head = "Translations", items = {
                "French (frFR) and Russian (ruRU) are fully up to date again — thanks to Zox and Malevi4.",
            } },
        },
    },
    {
        version = "1.23.0", date = "2026-06-21",
        sections = {
            { head = "New Features", items = {
                "Scenario banner alignment & size (Appearance > Scenario) — move the delve / scenario banner Left, Center, or Right within the tracker, and resize its Stage and name text.",
                "'Search on Wowhead' in the quest right-click menu — opens a copy-ready link to the quest's Wowhead page (also on the world-quest menus).",
                "Nameplate quest-icon position & size (General tab) — place the icon + count Left, Right, Above, or Below the nameplate, with separate icon-size and count-text-size sliders.",
                "World map world-quest list behind a tab — the summary + list tuck behind a world-quest tab on the map's right edge; click to show or hide. The quest pins are unaffected.",
            } },
            { head = "Improvements", items = {
                "The tracker's quest right-click menu (and the world-quest menus) are now fully translatable.",
            } },
        },
    },
    {
        version = "1.22.1", date = "2026-06-18",
        sections = {
            { head = "Translations", items = {
                "Russian (ruRU) updated by Malevi4 and French (frFR) updated by Zox — both languages are now fully up to date with the latest features.",
            } },
            { head = "Other", items = {
                "Some code cleanup.",
            } },
        },
    },
    {
        version = "1.22.0", date = "2026-06-18",
        sections = {
            { head = "New Features", items = {
                "Shadow Size slider (Appearance) — set how far the tracker's text shadow is cast.",
                "A separate Scenario shadow group (Appearance) — the delve / scenario banner gets its own text-shadow toggle, color, and size, apart from the main tracker text.",
                "The world map's world-quest list now scrolls in a compact panel instead of filling the screen in zones with many world quests.",
            } },
            { head = "Improvements", items = {
                "Appearance tab cleanup — the color boxes line up, a new 'Tracker' header sits over the background/border options, and the scroll-bar options moved beside the Zone Bar group.",
                "The Options and Chain Guide windows no longer overlap — opening one closes the other.",
            } },
            { head = "Bug Fixes", items = {
                "Fixed your regular quests sometimes not loading on login (only world quests showing) until a /reload; the tracker now fills in as soon as your quest data arrives.",
                "Fixed an error when untracking a profession recipe from the tracker.",
                "Progress-bar achievements (like '61/100') now show their count in the tracker, not just their title.",
            } },
        },
    },
    {
        version = "1.21.1", date = "2026-06-17",
        sections = {
            { head = "Bug Fixes", items = {
                "Fixed the group-finder eye appearing on every world quest (a v1.21.0 regression); it now shows only on world bosses and group quests, matching Blizzard's own tracker.",
            } },
        },
    },
    {
        version = "1.21.0", date = "2026-06-17",
        sections = {
            { head = "New Features", items = {
                "Chain Guide overhaul, Phase 3 of 3 (map integration) — the overhaul is COMPLETE. Press Track on a chain and its quests pin on your world map (next step in gold) with a waypoint that auto-advances as you turn quests in, even with the guide closed.",
                "New 'Revelations (12.0.7)' chains — Legacy of the Amani and the March on Quel'Danas raid lead-up.",
                "Independent title size + a text-shadow option for the tracker (Appearance tab). (Suggested by tanglies.)",
                "Quick cogwheel + Chain Guide buttons at the top of the tracker, each with its own on/off toggle. (Suggested by tanglies.)",
                "Tracked achievements: a simplify mode (show only what's left), right-click to untrack, left-click to open the Achievement panel. (Suggested by tanglies.)",
            } },
            { head = "Improvements", items = {
                "The group-finder button now appears on every group-listable world boss, not just some.",
                "The Chain Guide resize grip (bottom-right) is bigger and easier to grab; the Track button reads Untrack while following a chain.",
            } },
            { head = "Bug Fixes", items = {
                "Fixed the chain 'next step' sometimes pointing at the opposite faction's version of a quest.",
                "Trimmed war-table / meta quests that aren't part of a storyline, so chains end at their real final quest.",
            } },
        },
    },
    {
        version = "1.20.0", date = "2026-06-16",
        sections = {
            { head = "New Features", items = {
                "Chain Guide overhaul, Phase 2 of 3 — every quest chain in Midnight (all zones and the campaign) now draws as a real branching graph instead of a flat list, so you can see which quests unlock which and where paths split and rejoin.",
                "Drag anywhere on the graph to pan around larger chains.",
                "The Chain Guide window is now resizable (drag the corner; your size is saved) with a button to collapse the side list so the graph fills the whole window.",
            } },
            { head = "Improvements", items = {
                "More compact quest cards so you see more of a chain at a glance.",
                "Scenario and dungeon titles are now centered in their banner.",
            } },
            { head = "Bug Fixes", items = {
                "Opening the options from the Chain Guide no longer leaves the two windows overlapping.",
            } },
        },
    },
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
}
