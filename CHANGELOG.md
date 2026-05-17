# Changelog

All notable changes to Everything Quests will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
