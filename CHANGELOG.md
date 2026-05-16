# Changelog

All notable changes to Everything Quests will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
