# Changelog

All notable changes to Everything Quests will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
