-- Locales/enUS.lua
-- Default locale + source-of-truth phrase list for Everything Quests.
--
-- ns.L["English string"] returns the localized text for the player's client
-- (per GetLocale()), or the English string itself when no translation exists
-- (the metatable __index below). So EVERY wrapped string is safe to use even
-- with zero translations loaded -- untranslated text simply renders in English.
--
-- Translations are crowd-sourced on CurseForge. The keys listed below ARE the
-- base phrases: paste this list into the project's Localization page so the
-- frFR (and future) translators have something to translate. At build time the
-- packager injects their work via the --@localization@ token in the other
-- Locales/*.lua files (an inert comment in raw git checkouts).
--
-- Pattern: the English string IS the key (no semantic IDs). Keep keys in sync
-- with the code -- if you reword an English string, update it here too or the
-- existing translation orphans (and the new text falls back to English).
--
-- GENERATED FILE: produced by docs/_gen_enus.py from the L[...] usages in the
-- code. Do not hand-edit; re-run the generator after an extraction pass.


local _, ns = ...

ns.L = setmetatable({}, { __index = function(_, k) return k end })
local L = ns.L

-- ─── Options/TabGeneral.lua ───
L["General"] = true
L["Show quest pins on the world map  |cffaaaaaa(EQ's red \"!\" / \"?\" rings)|r"] = true
L["These are the round red markers Everything Quests puts on the big world map for quests you've already picked up (the ones in your quest log). A red \"!\" means \"go here for this quest's next step.\" A red \"?\" means \"this quest is done \226\128\148 go here to turn it in.\" Quests you haven't accepted yet keep the game's own yellow \"!\" markers; EQ does not change those. Uncheck this box and all of EQ's red markers go away."] = true
L["Lock tracker  |cffaaaaaa(disable drag-to-move and resize)|r"] = true
L["Hide tracker in combat"] = true
L["Hide tracker in instances  |cffaaaaaa(raids, dungeons, delves)|r"] = true
L["Hide tracker when world map is open"] = true
L["Auto-track accepted quests  |cffaaaaaa(matches Blizzard's default)|r"] = true
L["Auto-accept quests  |cffaaaaaa(hold Alt to pause)|r"] = true
L["Auto-turn-in quests  |cffaaaaaa(skips reward-choice screens)|r"] = true
L["Keep focused quest after relog  |cffaaaaaa(restores the waypoint arrow)|r"] = true
L["Quest icons on nameplates  |cffaaaaaa(shows the \"!\" + count on objective mobs)|r"] = true
L["Show minimap button"] = true
L["Reset all settings"] = true
L["Reset every Everything Quests setting to defaults?"] = true
L["Reset"] = true
L["Cancel"] = true
L["Profiles"] = true
L["Active profile"] = true
L["New Profile"] = true
L["Profile name:"] = true
L["Create"] = true
L["Switching profiles reloads the UI. Profiles are shared across characters; use them to keep different setups (e.g. raid vs solo). |cffEBB706New Profile|r prompts for a name and creates it on the spot."] = true
L["Slash commands"] = true
L["/eqs\n/everythingquests\n\n|cff999999Both open this options window.|r\n\n/eqs whatsnew\n\n|cff999999Show what's new in the latest update.|r\n\n/eqs session\n\n|cff999999Show a recap of your current play session.|r"] = true

-- ─── Options/TabTracker.lua ───
L["Zone"] = true
L["Status"] = true
L["Type"] = true
L["Level"] = true
L["Distance"] = true
L["Recent"] = true
L["Manual"] = true
L["Normal quests"] = true
L["Daily quests"] = true
L["Weekly quests"] = true
L["Campaign quests"] = true
L["World quests"] = true
L["Show only quests in current zone"] = true
L["Tracker"] = true
L["On-Screen Tracker"] = true
L["Show only watched quests  |cffaaaaaa(matches Blizzard's default tracker)|r"] = true
L["Simplify Mode  |cffaaaaaa(show only the first incomplete objective per quest)|r"] = true
L["Sort Order"] = true
L["|cffaaaaaaDrag and drop the quests in the tracker to reorder them however you like.|r"] = true
L["Filters"] = true
L["Reset filters to defaults"] = true
L["Options"] = true
L["Quest Title Color By Difficulty"] = true
L["Show quest level prefix  |cffaaaaaa(e.g. [60] Title)|r"] = true
L["Show zone label under quest titles"] = true
L["Show objective progress numbers  |cffaaaaaa(0/4, 1/1, etc.)|r"] = true
L["Show quest ID  |cffaaaaaa(useful for bug reports)|r"] = true
L["Show tracked / total on the Quests & Campaign headers  |cffaaaaaa(e.g. 3/9)|r"] = true
L["Show usable quest item buttons  |cffaaaaaa(click to use the quest's item)|r"] = true
L["Hide scroll bar  |cffaaaaaa(scroll with the mouse wheel instead)|r"] = true
L["Show Quest Discovered popups  |cffaaaaaa(boxes for newly discovered / completed quests)|r"] = true
L["Show NEW tag on recently accepted quests  |cffaaaaaa(for about an hour after accepting)|r"] = true
L["Split quest click  |cffaaaaaa(click the icon to focus, click the title to open the quest log)|r"] = true
L["Quest Sound  |cffaaaaaa(plays when a quest is ready to turn in)|r"] = true
L["Quest Complete Sound"] = true
L["Tracker Visibility"] = true
L["Profession section"] = true
L["Achievements section  |cffaaaaaa(achievements you're tracking)|r"] = true
L["World Quests section"] = true
L["Auto-list current-zone world quests  |cffaaaaaa(lists every WQ in your zone without tracking each)|r"] = true
L["Zone Progress Bar"] = true
L["Show zone progress bar  |cffaaaaaa(approximate questline progress)|r"] = true
L["Float as a movable bar  |cffaaaaaa(drag to move; right-click to lock or reset)|r"] = true
L["Changes apply immediately to the on-screen tracker."] = true

-- ─── Options/TabWorldQuests.lua ───
L["Gold"] = true
L["Gear / Items"] = true
L["Reputation tokens"] = true
L["Resources / Currencies"] = true
L["Artifact Power"] = true
L["Profession quests"] = true
L["PvP"] = true
L["Pet battles"] = true
L["Other / Uncategorized"] = true
L["Classic"] = true
L["The Burning Crusade"] = true
L["Wrath of the Lich King"] = true
L["Cataclysm"] = true
L["Mists of Pandaria"] = true
L["Warlords of Draenor"] = true
L["Legion"] = true
L["Battle for Azeroth"] = true
L["Shadowlands"] = true
L["Dragonflight"] = true
L["The War Within"] = true
L["Midnight"] = true
L["Other"] = true
L["World Quests"] = true
L["Enable World Quests map features  |cffaaaaaa(pins, summary, zone list)|r"] = true
L["Off: Everything Quests stops putting World Quests on the map — no world-map pins, no reward summary box, no zone quest list. The boxes below do nothing while this is off. This switch is ONLY for World Quests. It does NOT remove the red \"!\" / \"?\" quest rings — those are your normal quests, and you turn them off on the General tab. It also does NOT change the World Quests list in your tracker (that's on the Tracker tab)."] = true
L["Show world quest pins on the world map"] = true
L["Show zone quest list on zone maps"] = true
L["Filters by reward type"] = true
L["Enable All"] = true
L["Disable All"] = true
L["Filter by faction"] = true
L["Uncheck a faction to hide its world quests on the map."] = true
L["No major factions unlocked on this character yet."] = true
L["%s  |cffaaaaaa(Renown %d)|r"] = true
L["Faction %d"] = true
L["Display"] = true
L["Time left"] = true
L["Reward"] = true
L["Faction"] = true
L["A-Z"] = true
L["Sort zone quest list by"] = true
L["World map pin scale"] = true
L["Filters apply immediately when the world map is open."] = true

-- ─── Options/TabChainGuide.lua ───
L["Chain Guide"] = true
L["Chain Guide (Storylines)"] = true
L["Open Chain Guide"] = true
L["Open Chain Guide on login"] = true
L["Show unrouted questlines  |cffaaaaaa(API discoveries not in our routing table)|r"] = true
L["Window scale"] = true
L["Character cache"] = true
L["Per-character chain progress is cached account-wide so alts can browse what your other characters have completed. Clearing the cache removes that cross-character data; live completions stay (Blizzard tracks those)."] = true
L["Clear chain cache"] = true
L["Clear all cached chain-completion data across every character?"] = true
L["Clear"] = true
L["Cached: |cffffffff%d|r characters, |cffffffff%d|r waypoint locations\n|cffffffff%d|r chains across |cffffffff%d|r categories"] = true
L["today"] = true
L["1 day ago"] = true
L["%d days ago"] = true
L["\n|cffaaaaaaLast pruned: %s|r"] = true
L["Prune stale entries now"] = true
L["|cffEBB706EQ|r: pruned |cffffffff%d|r stale character record(s) and |cffffffff%d|r waypoint(s)."] = true

-- ─── Options/TabAppearance.lua ───
L["Appearance"] = true
L["Font"] = true
L["Font Size"] = true
L["None"] = true
L["Outline"] = true
L["Thick"] = true
L["Mono"] = true
L["Mono Outline"] = true
L["Mono Thick"] = true
L["Font Outline"] = true
L["Background"] = true
L["Background Color"] = true
L["Scroll Bar Background"] = true
L["Scroll Bar Color"] = true
L["Border"] = true
L["Border Color"] = true
L["Border Thickness"] = true
L["Colors & Dimensions"] = true
L["Quest Title Color Override"] = true
L["When cleared, falls back to difficulty coloring or default yellow."] = true
L["Use title color for completed quests  |cffaaaaaa(instead of green)|r"] = true
L["Section Header Color"] = true
L["Tracker Scale"] = true
L["Block Spacing"] = true
L["Zone Bar Scale"] = true

-- ─── Options/TabHistory.lua ───
L["History"] = true
L["Quest History"] = true
L["Record completed quests"] = true
L["When on, Everything Quests writes an entry to your account-wide quest history every time you turn in a quest. The data is shared across all of your characters; the history window can filter by character."] = true
L["Maximum entries kept"] = true
L["When the history grows past this many entries, the oldest ones are dropped. Set higher if you want a longer record, lower to save disk space. 5000 entries is enough for several months of heavy questing."] = true
L["Open Quest History"] = true
L["Populate from past completions"] = true
L["this character"] = true
L["|cffEBB706EQ History:|r added %d past completion%s for |cffffffff%s|r (no dates)."] = true
L["One-time per character: walks the list of quests this character has completed (according to the game's own record) and adds any that aren't already in your history. Entries created this way have no date — the game doesn't tell us when they happened."] = true
L["Re-scan for quest names"] = true
L["|cffEBB706EQ History:|r requested %d quest name%s from the server. Names will fill in over the next minute or two."] = true
L["|cffEBB706EQ History:|r nothing left to look up — every entry that can be resolved already is."] = true
L["Some quests in the backfilled history show up as \"Quest #12345\" because Blizzard hasn't sent the client their name yet. This button asks the server for every missing one. Quests the server flatly has no data for (retired or internal IDs) will keep their numeric placeholder."] = true
L["Restore history from backup"] = true
L["|cffEBB706EQ History:|r no backup yet — one is saved automatically each time you log out."] = true
L["Restore quest history from the backup taken %s (%d entries)? This replaces the current history."] = true
L["Restore"] = true
L["|cffEBB706EQ History:|r restored %d entr%s from backup."] = true
L["Everything Quests saves a rolling backup of your history when you log out, and automatically restores it if your history is ever found empty or missing a character on load. Use this button to restore manually."] = true
L["Wipe history"] = true
L["Delete ALL recorded quest history (every character)? This cannot be undone."] = true
L["Wipe"] = true
L["|cffEBB706EQ History:|r wiped."] = true

-- ─── Options/Frame.lua ───
L["Join our Discord!"] = true
L["Join our Discord"] = true
L["Version %s"] = true
L["Everything Quests opens its full options in a dedicated window. Click the button below, or type |cffEBB706/eqs|r in chat."] = true
L["Open Everything Quests Options"] = true
L["|cffEBB706Everything Quests|r: couldn't open Options \226\128\148 %s"] = true

-- ─── Core/Init.lua ───
L["Everything Quests Discord"] = true
L["Join the community for help, feedback, and updates.\nCopy the invite below (it's pre-selected — just press Ctrl+C):"] = true
L["Close"] = true

-- ─── Modules/ChainGuide/ChainView.lua ───
L["Completed"] = true
L["Ready to turn in"] = true
L["In your quest log"] = true
L["Skipped"] = true
L["A later quest in this chain has already passed this one."] = true
L["May be worth going back to pick up."] = true
L["Not started"] = true
L["Completed (before tracking)"] = true
L["Shift-click to link in chat"] = true
L["Pick a chain on the left to view its quests."] = true
L["(optional)"] = true
L["Level %d–%d"] = true
L["Click to open this chain"] = true
L["(no quests defined for this chain yet)"] = true

-- ─── Modules/ChainGuide/Frame.lua ───
L["Pick a category"] = true

-- ─── Modules/ChainGuide/QuestMapButton.lua ───
L["Chain"] = true
L["Find this quest in EQ's Chain Guide"] = true
L["Falls back to a Wowhead link in chat if EQ doesn't have a chain for this quest yet."] = true

-- ─── Modules/History/Frame.lua ───
L["|cffEBB706EQ History|r: |cffffffff%s|r isn't part of any chain in the Chain Guide."] = true
L["Right-click to open in the Chain Guide"] = true
L["Click to expand"] = true
L["Export"] = true
L["Re-scan names"] = true
L["Asks the server for the name of any \"Quest #12345\" entries. They'll fill in over the next minute or two as responses arrive."] = true
L["Character:"] = true
L["All characters"] = true
L["Date:"] = true
L["All time"] = true
L["Today"] = true
L["Past 7 days"] = true
L["Past 30 days"] = true
L["Type:"] = true
L["All types"] = true
L["Campaign"] = true
L["Questline"] = true
L["Calling"] = true
L["Recurring"] = true
L["World Quest"] = true
L["Sort:"] = true
L["Date"] = true
L["Name"] = true
L["Sort direction"] = true
L["Click to flip ascending / descending."] = true
L["Hide undated  |cffaaaaaa(backfilled)|r"] = true
L["(no matching quests)"] = true
L["%d entries"] = true
L["first"] = true
L["oldest"] = true
L["newest"] = true
L["%d entries (showing %s %d)"] = true
L["Current daily streak"] = true
L["Best daily streak"] = true
L["Total quests recorded with a date"] = true
L["Streak counts consecutive days (server time) with at least one quest turn-in across any character on the account. Today or yesterday keeps the streak alive — you don't lose it until a whole day passes with no activity."] = true
L["%d days"] = true
L["Chains where you have at least one completed quest. Click a chain to expand and see per-quest completion dates."] = true
L["(no chain quests recorded yet)"] = true
L["%d of %d quests recorded"] = true
L["Quest turn-ins per day over the last %d days. Brighter = busier. Hover a cell for the date and count. The bottom-right cell is today."] = true
L["%d quest%s turned in"] = true
L["Less"] = true
L["More"] = true
L["total turn-ins in the last %d days"] = true
L["Busiest day: %s (%d quests)"] = true
L["%dg %ds %dc"] = true
L["Totals"] = true
L["Trends"] = true
L["Account-wide quest rewards. Totals count only quests turned in while reward tracking was on; older entries didn't capture XP or gold."] = true
L["Total quests with reward data"] = true
L["Total gold earned"] = true
L["Total XP earned"] = true
L["By character"] = true
L["Top single-quest rewards"] = true
L["%s  \194\183  %s quests  \194\183  %s  \194\183  %s XP"] = true
L["Biggest gold:  |cffffffff%s|r  \194\183  %s"] = true
L["Biggest gold:  (none yet)"] = true
L["Biggest XP:    |cffffffff%s|r  \194\183  %s XP"] = true
L["Biggest XP:    (none yet)"] = true
L["Daily"] = true
L["Weekly"] = true
L["Show:"] = true
L["XP"] = true
L["Quests"] = true
L["Gold is all income (loot, vendor, rewards) tracked forward from when this version was installed \226\128\148 past periods may read 0. XP and quest counts come from quest turn-ins."] = true
L["This week"] = true
L["last week"] = true
L["yesterday"] = true
L["%s \226\128\148 %s"] = true
L["%s vs %s"] = true
L["Your quest activity this play session. A session starts when you log in and continues across /reload; it resets the next time you log in fresh."] = true
L["Played this session"] = true
L["Quests completed"] = true
L["Quest XP earned"] = true
L["Quest gold earned"] = true
L["Level-ups"] = true
L["   |cffaaaaaa(%.1f / hour)|r"] = true
L["%d   |cffaaaaaa(%d to %d)|r"] = true
L["Press Ctrl+A to select all, then Ctrl+C to copy."] = true

-- ─── Modules/Tracker/AutoComplete.lua ───
L["Click to complete quest"] = true

-- ─── Modules/Tracker/AutoQuestPopup.lua ───
L["Click to view quest"] = true
L["Quest Complete!"] = true
L["Quest Discovered!"] = true

-- ─── Modules/Tracker/Events.lua ───
L["Find Group"] = true
L["Open the Premade Group Finder for this quest."] = true

-- ─── Modules/Tracker/Frame.lua ───
L["Tracker locked"] = true
L["Move and resize are off. Uncheck \"Lock tracker\" in /eqs > General."] = true
L["Drag to move the tracker"] = true
L["/eqs for options"] = true
L["Profession"] = true
L["Endeavors"] = true
L["Achievements"] = true
L["Drag the top edge of the tracker to move it.\n\nType |cffEBB706/eqs|r for options."] = true

-- ─── Modules/Tracker/Scenario.lua ───
L["Final Stage"] = true
L["Stage %d"] = true

-- ─── Modules/Tracker/ZoneProgress.lua ───
L["Unlock (allow moving)"] = true
L["Lock position"] = true
L["Reset position"] = true

-- ─── Modules/WhatsNew.lua ───
L["Open Options"] = true
L["Got it"] = true
L["(This message shows once and won't appear again.)"] = true

-- Convert the `true` sentinels to their key (the self-keyed English default).
for k, v in pairs(L) do if v == true then L[k] = k end end
