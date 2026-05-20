# Changelog

All notable changes to Everything Quests will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.12] - 2026-05-19

### New Features

- **Auto-accept and auto-turn-in quests** — Two new toggles on the General tab let Everything Quests click through quest dialogs for you. Auto-accept accepts offered quests; auto-turn-in finishes quests whenever there's no reward to choose between (multi-choice reward screens stay open so you pick the item yourself). Hold **Alt** while talking to a quest-giver to pause automation for that interaction, or decline a quest manually to pause everything for 10 seconds.
- **"Chain" button on the world map's quest details** — A small button next to Abandon: click it and the Chain Guide opens directly to that quest's chain, highlighting it. If the quest isn't in any chain Everything Quests knows about yet, a Wowhead link is printed in chat instead so the click is never dead.
- **Flight master highlight** — Open a flight master and the taxi node closest to your focused quest's destination now glows gold, so you can spot the right one at a glance.
- **Auto-zoom map** — Optional toggle on the General tab (off by default): opening the world map automatically switches it to your focused quest's zone. Stays put while you're already on a flight path.
- **Skipped-quest markers in the Chain Guide** — If you've moved past a quest in a chain without finishing it, the Chain Guide flags it with an orange marker and a red ✕, plus a "N skipped" count at the top of the chain. Hover the marked quest for an explanation. Optional breadcrumb quests aren't flagged.

### Bug Fixes

- **Completion sound now fires for instant-complete quests** — Some quests (certain dailies, scenario step turn-ins, a few Midnight callings) finish without ever entering your quest log, so the completion sound was silently skipped. They're now caught from the chat message and play the sound like any other quest.

### Improvements

- **Live memory meter** — New `/eqs profile memhog` slash command opens a small draggable panel showing Everything Quests' current memory use and how fast that's changing in kB/s. Useful for the curious or for spotting allocation spikes during play. Type the same command again to hide it.
- **Under-the-hood polish** — Tighter cleanup when tracker quest entries are recycled (invisible during play, but keeps memory healthier) and a new internal tooltip-reading helper for future features.

## [1.3.11] - 2026-05-19

### Improvements

- **Developer tooling** — New `/eqs profile` slash command for diagnosing CPU and memory hot spots (`show`, `reset`, `mem on/off`), plus a shared event-throttler primitive for upcoming features. Under-the-hood groundwork — no visible change for typical play.

## [1.3.10] - 2026-05-19

### Bug Fixes

- **Quest item buttons are now clickable** — The new tracker item buttons added in 1.3.9 wouldn't actually use the item when clicked. They now work as intended (out of combat).

### Improvements

- **Out-of-range tint** — Quest item buttons in the tracker now tint red when their item is out of range, and return to normal as soon as you're close enough to use it.

## [1.3.9] - 2026-05-18

### New Features

- **Usable quest item buttons** — Quests that come with a usable item now show a clickable button right on their tracker entry, so you can use it without opening the quest log. On by default; toggle it on the Tracker tab. (Items become clickable for quests you already had when you entered combat — the game doesn't allow setting these up during a fight.)

### Bug Fixes

- **No more "action blocked" message in combat** — With the new item buttons present, changing the tracker scale (or having a pending scale change) during combat could trigger a Blizzard "action blocked" message. Scale changes are now applied safely, deferred until combat ends if needed.

## [1.3.8] - 2026-05-18

### Bug Fixes

- **Drag-and-drop drop line** — When reordering quests by dragging (manual sort mode), the yellow "drop here" line could land a couple of quests below the cursor, especially with a non-default Tracker Scale. It now tracks the cursor exactly at any scale.

### Improvements

- **Hardier saved settings** — Your manual quest order is now cleaned up when it loads, so a corrupted saved value can't break the tracker's sorting. Also includes some under-the-hood groundwork for upcoming features. No visible change from these.

## [1.3.7] - 2026-05-18

### Bug Fixes

- **Campaign quests after a game restart** — After fully restarting the game client (not a UI reload), campaign quests could appear under the regular "Quests" section instead of "Campaign" until you turned in a quest. They now move into the Campaign section on their own, within a few seconds of logging in.
- **Hidden objective numbers** — With "Show objective numbers" turned off, some objective lines could show a stray color code as text (e.g. `44ff44Apprentice…`). Objective text is now clean when numbers are hidden.

## [1.3.6] - 2026-05-18

### New Features

- **Tracker border** — Optional border around the quest tracker, off by default. Turn it on in the Appearance tab, pick any color (including your class color via the picker's **Class** button), and set how thick it is with the new **Border Thickness** slider. The border wraps cleanly around the tracker whether or not the background is enabled. Thanks to **Spydawg2233** for the suggestion!

## [1.3.5] - 2026-05-17

### Improvements

- **Much lighter quest tracker** — The tracker now reuses each quest's display and only redraws a quest when something about it actually changes, instead of rebuilding every quest from scratch on every update. This sharply cuts memory churn (steady tracker memory is well below previous versions) and keeps the tracker smooth even with a full quest log — with no change to how it looks or behaves.

## [1.3.4] - 2026-05-17

### Improvements

- **Lighter, smoother tracker** — The quest tracker now does far less repeated work each time it updates: it remembers your font instead of re-applying it to every quest on every refresh, reuses internal scratch space instead of creating throwaway work, and stops re-checking icon art it has already looked up. The result is noticeably less memory churn with a full quest log, with no change to how the tracker looks or behaves.

## [1.3.3] - 2026-05-17

### Improvements

- **Consistent world quest timers** — The time-left countdown on a world quest now uses the same colors and the same format everywhere it appears: the map pin, the zone list, and the tooltip. Before, the same quest could look more or less urgent depending on where you read it, and the tooltip spelled the time out differently. Now it's one clear scale — green when there's plenty of time, down through yellow and orange to red as it runs out.
- **Lighter quest sorting** — Sorting the tracker's quest list no longer creates throwaway work every time it refreshes, shaving off a bit more memory churn.

## [1.3.2] - 2026-05-17

### Improvements

- **Clearer explanation of the red map markers** — The General options tab now plainly describes Everything Quests' red `!` / `?` world-map markers: they're for quests you've already picked up (a red `!` means "go here for this quest's next step," a red `?` means "this one's done, go turn it in"). Quests you haven't accepted yet keep the game's normal yellow markers.
- **Lighter and smoother world quests** — World quest pins now remember each quest's reward instead of working it out again every time the map refreshes, and the addon no longer keeps retrying quests whose reward never loads. The result is less memory use and a smoother world map, especially in zones packed with world quests.

## [1.3.1] - 2026-05-17

### Bug Fixes

- **Font picker could spam errors** — Opening the Appearance font dropdown could throw a stream of "Invalid font file asset" errors when another addon had registered a font whose file was missing or mispathed (e.g. a media pack with absent files). The picker now lists only the fonts bundled with Everything Quests, so every entry is guaranteed valid, and font previews fall back to the default font instead of erroring.
- **Internal developer text showed in scenario steps** — On some scenarios (notably Void Incursion), a step could display a raw Blizzard placeholder string such as "12.0.5 Void Assaults - Eversong - Major Attack - Scenario 01 - Step 02 Completion (JTL)" where its description should be. These build-marker strings are now detected and hidden, leaving just the clean progress bar and stage banner.

### Improvements

- **Void Incursion label** — Void Incursion events now show "Void Incursion" as the scenario tracker's section header instead of the generic "Scenario". Other scenario types are unaffected.

## [1.3.0] - 2026-05-16

### New Features

- **Chain Guide now follows the real campaign** — The "Midnight Campaign" category is sourced live from Blizzard's campaign data instead of a hand-maintained list, so it mirrors your actual in-game campaign: all 17 chapters, in story order, with live per-chapter progress. Previously the category showed a mostly-wrong fixed set of questlines and your real campaign quests never appeared there.
- **New "The War of Light and Shadow" category** — The max-level campaign (Foothold, The Voidspire, Gathering of the Elves, The Battle of the Bridge, March on Quel'Danas, Dawn of a New Well) now has its own category, sourced the same live way, so you can track that endgame storyline before and as you unlock it.

### Improvements

- **Categories grouped sensibly** — The Chain Guide category list is now ordered campaigns-first (leveling, then max-level) then zones in Midnight progression order, instead of an alphabetical jumble.
- **Bigger Chain Guide window** — Larger window and wider list panes; long category names (e.g. "The War of Light and Shadow") are no longer clipped, and hovering any category or chain shows its full name (plus quest progress for chains).
- **No more duplicate storylines** — A questline that is a campaign chapter now appears only under its campaign, not also under its zone. Categories left with no chains of their own are hidden rather than shown as empty.

## [1.2.1] - 2026-05-16

### Bug Fixes

- **Campaign quests vanished from the tracker when accepted** — Accepting a campaign quest in the field left it untracked, forcing you to open the quest log and re-track it every time. EQ's tracker shows watched quests, but Blizzard surfaces campaign quests through a separate system that never adds them to the watch list, so they stayed hidden. With auto-track on (the default), EQ now adds the watch itself the moment a quest is accepted, so campaign quests appear in the tracker immediately. World quests are unaffected (they keep their own tracking).

### Improvements

- **Clearer options wording** — The General tab's "Show quest pins on the world map" description is rewritten in plain language explaining exactly what the red `!` / `?` markers are. The World Quests tab's master switch now states explicitly that it does **not** control those red quest rings (those live on the General tab) and does **not** affect the tracker's World Quests list.

## [1.2.0] - 2026-05-16

### New Features

- **Campaign section** — Campaign quests now have their own "Campaign" header, split out of the general "Quests" section (same header style and behavior). It only appears when you have campaign quests.
- **World Quests pinned to the bottom** — The World Quests section is now fixed at the bottom of the tracker and always visible, with its own height cap and internal scroll, while everything above it scrolls. It sits flush beneath your quests (no dead gap) until they grow enough to need scrolling.
- **Hide quest map pins** — New General-tab option to turn off EQ's red `!`/`?` quest pins on the world map (Blizzard's own pins are unaffected).
- **Disable World Quest map features** — New World Quests-tab master switch that turns off all WQ map overlays (world-map pins, summary box, zone list) without affecting the tracker — for players who only want the tracker and Chain Guide.
- **Tracked / total counts** — The Quests and Campaign headers can show "shown / category total" (e.g. `3/9`), toggleable on the Tracker tab (on by default).

### Improvements

- **Left-click focuses a quest** — Left-clicking a tracked quest now super-tracks it (waypoint/arrow) instead of opening the quest log; the quest log / details moved to right-click.
- **Group Finder accuracy** — The Find Group eye and elite rosette now show only on elite world quests, not on the many ordinary WQs that merely had a premade-group activity.
- **Softer icon glow** — The classification glow behind quest icons is now ~50% lighter.
- **Consistent header counts** — Every section's count renders in the Section Header Color at the quest-description font size.
- **World Quests options layout** — Reorganized so the pin-scale slider and sort options no longer run off the window.
- **Interface versions** — TOC updated to include the upcoming patch build for forward compatibility.

## [1.1.3] - 2026-05-16

### Fixed

- **CurseForge releases** — Automated builds now publish to CurseForge. The CurseForge project ID was missing from the TOC, so the packager only ever created the GitHub release and skipped CurseForge entirely. No in-game changes from 1.1.2.

## [1.1.2] - 2026-05-16

### Bug Fixes

- **`/eq` did nothing** — `/eq` is Blizzard's own built-in command for equipping items, so the game intercepted it before the addon ever received it. The short command to open Options is now **`/eqs`**; `/everythingquests` still works as before. All in-game hints, tooltips, the move-the-tracker popup, and the README were updated to match.
- **Scroll bar background misaligned** — The scroll-bar backdrop sat to the left of the scroll bar instead of directly behind it. It is now anchored to the bar itself, so it always lines up.

### Improvements

- **Subtler scroll bar background** — The default backdrop is now a faint, barely-there grey that just hints the bar is present (still fully adjustable in Appearance), and the same backdrop was added to the World Quests options tab.
- **Options layout** — The Scroll Bar Color picker now lines up in the same column as the Background Color picker.

## [1.1.0] - 2026-05-16

### New Features

- **Chain Guide waypoints** — Clicking any quest in a chain now drops a waypoint (TomTom if installed, otherwise Blizzard's user waypoint + super-track) and opens the world map to it. Ships with quest-giver coordinates for the Midnight chains, with a live questline-API lookup and passive harvesting as fallbacks so coverage keeps improving as you play.
- **Bundled font selection** — A large set of fonts now ships with the addon and is registered with LibSharedMedia, so every user has the full font list in Appearance with no external addon required. Default is GothamXNarrow Black.
- **Move-the-tracker discovery** — A one-time popup on first load explains how to reposition the tracker, and the (previously invisible) top drag strip now highlights and shows a tooltip on hover, with a lock-aware message.

### Bug Fixes

- **"Find Group" eye on solo quests** — The group-finder eye no longer appears on regular quests; it is shown only on elite/group world quests, matching Blizzard's tracker.
- **Expired world quests** — Expired WQs (no time remaining / no longer active) are now filtered out of the world-quest list, summary, and pins instead of lingering as stale "Expired" rows.
- **Delve section labeled "Scenario"** — The tracker now correctly labels Delves as "Delves" (detected via scenario type, since the legacy texture-kit signal is absent in Midnight).
- **Background opacity slider** — Dragging the tracker background fade now updates live; it previously relied on a UI global removed in 10.0, so the alpha was always read as fully opaque.

### Improvements

- **World-quest reward classification** — Rewritten to a tag → money → item → currency pipeline: far fewer rewards fall to "Other", artifact power / trade goods / equipment are distinguished, and the "Other" summary icon is no longer a question mark.
- **Section header hierarchy** — Section headers now render in the user's font a few points larger than quest titles (and live-update with the Appearance settings), so the layout reads correctly.
- **Cleaner tracker** — Removed the "All Objectives" master header (each section has its own) and the boxed background behind the Delves header.

## [1.0.1] - 2026-05-15

### Bug Fixes

- **Font dropdown was unusable** — The Appearance tab's font picker rendered an empty list because the scroll content frame was hardcoded to 1px wide, collapsing every row. Font rows now size to the scroll width and display each font as a live preview.
- **World quest shown twice** — A watched/quest-log task quest (e.g. "Nulling Nullaeus") could render in both the Quests and World Quests sections. The "already in the Quests section" exclusion is now applied to all world-quest sources, not just in-zone task quests.
- **Rename leftovers** — Cleaned up internal `EQL` identifiers left over from the EverythingQuestLog → Everything Quests rename: frame names, the map-pin mixin/template, and user-visible chat prefixes are now `EQ`.

### New Features

- **Find Group button** — Group-eligible world quests (elite world quests, raid bosses) now show a Find Group eye button in the tracker that opens the Premade Group Finder for that quest, plus the gold elite rosette icon — matching Blizzard's own tracker.
- **No-sound option** — "None" is now the first choice in the Quest Complete Sound dropdown, so the completion sound can be disabled directly from the picker.
- **Bundled font** — GothamNarrow Black now ships with the addon and is registered with LibSharedMedia, so the default typeface works with no external dependency.

### Improvements

- **Condensed tracker** — Layout tightened to match Blizzard's compact tracker: the zone subtitle is off by default, block padding and spacing are reduced, and world-quest rows are shorter.
- **Blizzard-style objectives** — In-progress objectives use a `- ` dash prefix; completed objectives show a checkmark.
- **Default appearance** — Default font is GothamNarrow Black at size 15 with an outline.
- **Options window styling** — The Options window now has the Everything-suite red (#6D0501) border and a larger outlined title, matching the sibling addons.

## [1.0.0] - 2026-05-12

### New Features

- Initial stable release — out of beta.
- **Quest Tracker** — Custom on-screen tracker replacing the default Blizzard ObjectiveTrackerFrame. Draggable, resizable, with per-type filters (Normal, Daily, Weekly, Campaign, World Quests), six sort modes, and manual drag-to-reorder.
- **World Quest Pins** — Custom pins on world and zone maps with colored rings by reward category, time-urgency coloring, hover tooltips, and per-reward / per-faction filtering.
- **Chain Guide** — Standalone three-pane window for browsing hand-authored Midnight quest chains across Eversong Woods, Zul'Aman, Harandar, Voidstorm, and Arator, with cross-character completion tracking.
- **Map POI overlays** — Branded quest pins (red ring, #6D0501) on zone maps with super-track and dismiss support.
- **Minimap launcher** — LibDataBroker integration compatible with Titan Panel, ChocolateBar, and ElvUI. Left-click opens the Blizzard quest log, shift-click opens the Chain Guide, right-click opens Options.
- **Options panel** — Tabs for General, Tracker, World Quests, Appearance, and Chain Guide settings. Font and texture pickers powered by LibSharedMedia.
- Localization stubs for deDE, esES, esMX, frFR, itIT, koKR, ptBR, ruRU, zhCN, zhTW. Full enUS strings.
