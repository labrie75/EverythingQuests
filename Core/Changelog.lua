local _, ns = ...

ns.Changelog = {
    {
        version = "1.31.0", date = "2026-07-07",
        sections = {
            { head = "New Features", items = {
                "World Quests height - the World Quests area used to get squeezed down to a line or two when you had a lot of quests. There is now a Set a custom World Quests height option under /eqs > Tracker, with a slider to give it as much room as you want. Off by default. Thanks to TheOneMVP.",
                "Hide tracker in Mythic+ - a new option under /eqs > General tucks the tracker away during an active Mythic+ run and brings it back when the run ends, so it stays out of your way next to the dungeon timer. Off by default. Thanks to TheOneMVP.",
            } },
            { head = "Bug Fixes", items = {
                "The tracker no longer shrinks to a few lines after a relog when you have more quests than fit. The viewport was collapsing to a section boundary; it now fills the height you set and scrolls the overflow. Thanks to ShodanDelacroix for the debug info that pinpointed it.",
                "The quest-completion sound no longer occasionally plays once at login. On a cold login the sound tracker could capture its baseline before the quest log finished syncing, then mistake every already-complete quest for a fresh completion; it now only plays on a real incomplete-to-complete transition.",
                "Fixed a Lua error when opening the flight map with a quest tracked (the taxi-node highlighter misread a map API's return values). Thanks to DrahgunFyre for the report.",
            } },
        },
    },
    {
        version = "1.30.2", date = "2026-07-07",
        sections = {
            { head = "Bug Fixes", items = {
                "The tracker no longer shrinks to a few lines a moment after you log in. With a background or border enabled, the bordered window collapsed to hug the quest content while the resize handle stayed at the full height, leaving a large empty gap below it. The window now fills the full height you size it to. Thanks to ShodanDelacroix for the detailed report.",
            } },
            { head = "Improvements", items = {
                "Russian translation - the Campaign term now uses the WoW-official spelling «Кампания». Thanks to Malevi4.",
            } },
        },
    },
    {
        version = "1.30.1", date = "2026-07-06",
        sections = {
            { head = "Improvements", items = {
                "Translations - French and Russian now cover everything added in the last two updates: the Bonus Objectives HUD, the class-color options, the custom header divider color, and the independent header size from v1.30.0, plus the tracker section order and update-notice options from v1.29.0. Thanks to Zox (French) and Malevi4 (Russian).",
            } },
        },
    },
    {
        version = "1.30.0", date = "2026-07-05",
        sections = {
            { head = "New Features", items = {
                "Bonus Objectives HUD - a new movable on-screen checklist for the bonus objectives you might otherwise miss. In delves it tracks the bonus loot mechanics (Nemesis Strongbox packs and the Sanctified Banner) so you can grab the extra rewards before the boss. Turn it on under /eqs > Tracker > Scenario Bonus Objectives, drag it anywhere, and right-click to lock or reset. Off by default. Thanks to DrahgunFyre for the idea in the Discord.",
                "Class color for titles and headers - new \"Use class color\" toggles under /eqs > Appearance color your quest and achievement titles, and your section headers, with the class color of the character you are logged in on. Off by default. Thanks to ChipW0lf.",
                "Custom header divider color - the thin line under each section header (Quests, Campaign, and so on) is no longer locked to gold; set any color under /eqs > Appearance > Divider Line Color. Thanks to ChipW0lf.",
                "Independent header text size - a new Header Size Offset slider under /eqs > Appearance sizes the section headers separately from the quest text, so they do not get oversized on a low UI scale. Thanks to ChipW0lf.",
            } },
            { head = "Improvements", items = {
                "More fonts - the font pickers now list every font registered through LibSharedMedia, including fonts added by other addons, instead of only the ones bundled with Everything Quests. Thanks to ChipW0lf.",
            } },
            { head = "Bug Fixes", items = {
                "The Clear button next to Quest Title Color Override now resets the color swatch when clicked.",
                "When the zone progress bar is set to \"Same as tracker font\", it now follows the main tracker font, size, outline, and shadow live.",
            } },
        },
    },
    {
        version = "1.29.0", date = "2026-07-03",
        sections = {
            { head = "New Features", items = {
                "Reorder tracker sections — put the tracker's sections in any order under /eqs > Tracker > Section Order, using the up/down arrows to move Campaign, Quests, Profession, Endeavors, Achievements, and the Zone Progress bar. Thanks to DrahgunFyre for suggesting it in the Discord.",
                "World Quests position — a Top / Bottom switch in the same Section Order area moves the World Quests panel above or below your quests; it keeps its own scrollbar and size cap either way.",
                "Quieter update notices — choose how you hear about new features under /eqs > General > After an update: a popup window (the default), a quiet clickable chat link, or nothing at all. The popup also has its own \"Don't show these again\" checkbox.",
            } },
            { head = "Improvements", items = {
                "Setting tooltips on multi-button options (like World Quests position and Nameplate icon position) now appear reliably next to the button you hover.",
            } },
        },
    },
    {
        version = "1.28.0", date = "2026-06-27",
        sections = {
            { head = "New Features", items = {
                "Chain Guide — added The Sunstrider Omnium (the Magisters' Terrace questline that unlocks the Omnium Folio) as its own zone, with its full quest chain mapped out like the rest of the Midnight content.",
                "Chain Guide map pins — quest-giver map pins now show for The Sunstrider Omnium and Void Acropolis chains, so you can find each step on the world map (Void Acropolis had none before).",
            } },
            { head = "Improvements", items = {
                "New addon icon — the minimap button, Titan Panel, and AddOns list now use a new gold crest in place of the old book.",
            } },
            { head = "Bug Fixes", items = {
                "Tracker sections no longer crowd together — with a lot of quests, achievements, and world quests tracked at once, a section's header could appear with its contents cut off. The quest list now keeps its sections intact, and the World Quests area yields space and scrolls instead.",
                "Ritual Sites (such as Broken Throne) now show \"Ritual Site\" in the tracker's scenario header instead of \"Delves\" — they run on the delve system, but the addon now matches Blizzard's own label.",
                "Fixed a combat error (\"action blocked\") that could appear when entering a Ritual Site or scenario while in combat with a usable quest item tracked.",
            } },
        },
    },
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
