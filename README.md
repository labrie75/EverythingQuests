<h1 align="center">Everything Quests</h1>
<p align="center">
  <strong>A unified replacement for the Blizzard quest experience — tracker, world map overlays, and a Midnight chain guide.</strong>
</p>
<p align="center">
  <a href="https://github.com/wheelbarrel00/EverythingQuests/releases"><img src="https://img.shields.io/github/v/release/wheelbarrel00/EverythingQuests?color=6D0501&label=Version" alt="Version" /></a>
  <img src="https://img.shields.io/badge/WoW-Midnight%2012.0-8B0000?style=flat-square" alt="WoW Version" />
  <img src="https://img.shields.io/badge/Interface-120005-333333?style=flat-square" alt="Interface" />
  <a href="LICENSE"><img src="https://img.shields.io/github/license/wheelbarrel00/EverythingQuests?style=flat-square&color=333333" alt="License" /></a>
</p>

---

## Overview

Everything Quests is a complete replacement for Blizzard's quest tracking and quest log experience for **World of Warcraft: Midnight**. It bundles four major features into one addon:

1. A custom on-screen **Quest Tracker** that replaces the default ObjectiveTrackerFrame
2. Interactive **World Quest pins** on the world map and zone maps
3. A standalone **Chain Guide** window for browsing Midnight quest chains
4. Branded **Quest POI** overlays on zone maps

Open Options with **`/eq`** or the minimap button. Right-click the minimap button to jump straight to Options.

---

## Features

### Quest Tracker
A native-feeling, draggable, resizable on-screen quest list that replaces Blizzard's ObjectiveTrackerFrame.

- **Filtering** — Per-quest-type toggles (Normal, Daily, Weekly, Campaign, World Quests) and a "current zone only" mode
- **Sorting** — Six modes: Zone, Status, Type, Level, Distance, or Manual (drag-to-reorder)
- **Visibility rules** — Optionally hide in combat, in instances (raids, dungeons, delves), or when the world map is open
- **Simplify mode** — Toggleable compact display
- **Watched vs all** — Show only quests you've watched (Blizzard default) or every quest in your log
- **Auto-track** — Automatically watch newly accepted quests (toggleable)
- **Quest sound notifications** — Optional sound on quest completion
- **Position lock** — Disable drag-to-move once you've placed the tracker

### World Quest Pins
Replaces Blizzard's world quest icons with custom pins on both the world map and zone maps.

- **Reward-category rings** — Gold (yellow), Gear (blue), Reputation (purple), Resources (green), Artifact Power (orange), Profession (tan), PvP (red), Pet (cyan), Other (gray)
- **Time-urgency coloring** — Green (>4h), white (1–4h), yellow (30–60m), red (<30m)
- **Hover tooltip** — Quest title, reward type, time remaining
- **Click to super-track**, right-click to dismiss
- **Per-reward filters** — Toggle each reward category independently
- **Per-faction filters** — Grouped by expansion
- **Persistent watch list** — Manually watched world quests survive login
- **Account-wide completion cache** — Shared across characters

### Chain Guide
A standalone three-pane window for browsing hand-authored quest chains.

- **Layout** — Categories (left), Chains (middle), Quest Details (right)
- **Browser navigation** — Back / Forward buttons with full history
- **Hand-authored data** — Prerequisite branching overrides Blizzard's API chains where the API is incomplete
- **Cross-character completion** — Tracks completion of every chain across every character on your account
- **Lazy-built** — The window is constructed on first toggle to keep load times minimal

Currently covers the Midnight expansion: **Eversong Woods**, **Zul'Aman**, **Harandar**, **Voidstorm**, **Arator**, plus the Midnight campaign storyline.

### Map POI Overlays
Custom 22×22 quest pins on zone maps with the Everything-suite branded red ring (#6D0501) around the standard quest icon (gold `?` for turn-ins, white `!` for in-progress). Clicks super-track; right-click dismisses. Layered above Blizzard's own quest POIs.

### Minimap Launcher
LibDataBroker-powered launcher compatible with Titan Panel, ChocolateBar, ElvUI's data-broker bar, and any other LibDataBroker display.

| Click | Action |
|---|---|
| **Left-click** | Open the Blizzard quest log |
| **Shift+Left-click** | Open the Chain Guide |
| **Right-click** | Open Options |
| **Drag** | Reposition around the minimap |

---

## Slash Commands

| Command | Action |
|---|---|
| `/eq` | Toggle Options |
| `/everythingquests` | Toggle Options (alias) |

---

## Keybindings

Bindable from **Esc → Options → Key Bindings → AddOns → Everything Quests**:

| Action | Default |
|---|---|
| Toggle Options | (unbound) |
| Toggle Chain Guide | (unbound) |

---

## Options

| Tab | Settings |
|---|---|
| **General** | Lock tracker position, hide in combat, hide in instances, hide when world map open, auto-track accepted quests, show/hide minimap button |
| **Tracker** | Simplify mode, sort order, per-type filters, current-zone-only mode, watched-only mode, background visibility |
| **World Quests** | Show/hide pins, per-reward filters, per-faction filters |
| **Appearance** | Font picker (LibSharedMedia), font size (8–24pt), background texture picker, background alpha, header color, block spacing |
| **Chain Guide** | (in progress) |

---

## Installation

### From CurseForge
1. Install via the [CurseForge app](https://www.curseforge.com/) or download manually
2. The addon will be placed automatically in your AddOns folder

### Manual Install
1. Download the latest release from the [Releases](https://github.com/wheelbarrel00/EverythingQuests/releases) page
2. Extract the `EverythingQuests` folder into:
   ```
   World of Warcraft/_retail_/Interface/AddOns/
   ```
3. Restart WoW or type `/reload` if already in-game
4. Enable **Everything Quests** at the character select screen

---

## Dependencies

**Required:** None — Everything Quests is fully standalone. All libraries are bundled.

**Optional:**
- [TitanClassic](https://www.curseforge.com/wow/addons/titan-panel-classic), [ChocolateBar](https://www.curseforge.com/wow/addons/chocolatebar), or [ElvUI](https://www.tukui.org/) — display the minimap button on a data-broker bar instead of around the minimap

### Bundled Libraries

LibStub, CallbackHandler-1.0, AceDB-3.0, AceEvent-3.0, AceTimer-3.0, LibSharedMedia-3.0, LibDataBroker-1.1, LibDBIcon-1.0, LibMapPinHandler.

---

## Technical Details

| Metric | Value |
|---|---|
| Interface version | 120001, 120005, 120000 (Midnight 12.0) |
| SavedVariables | `EverythingQuestsDB` (account), `EverythingQuestsCharDB` (character), `EverythingQuestsChainCache` (account) |
| API compliance | Display-only — no taint, no automation |

### Architecture
```
EverythingQuests/
├── EverythingQuests.toc              # Addon manifest, module load order
├── Bindings.xml                      # Keybinding declarations
├── Core/                             # Init, DB, Events, Cache, Util, Media
├── Locales/                          # enUS (full) + 10 stub locales
├── Libs/                             # Bundled libraries
├── Modules/
│   ├── Minimap/                      # LibDataBroker launcher
│   ├── Tracker/                      # Custom quest tracker (12 files)
│   ├── WorldQuests/                  # World/zone map pins (9 files)
│   ├── ChainGuide/                   # Chain browser window (6 files)
│   └── MapPOI/                       # Quest POI overlays (3 files)
├── Data/
│   ├── RewardIcons.lua               # World-quest reward icon mapping
│   └── QuestChains/                  # Hand-authored Midnight chain data
└── Options/                          # General, Tracker, World Quests, Appearance, Chain Guide tabs
```

Modules register into Core subsystems at load time and listen for events through a shared callback dispatcher, so multiple modules can safely react to the same WoW event without stepping on each other.

---

## Localization

Currently shipping enUS with comprehensive strings and stub files for deDE, esES, esMX, frFR, itIT, koKR, ptBR, ruRU, zhCN, and zhTW. Translation contributions welcome — see [Contributing](#contributing).

---

## Contributing

Contributions are welcome! If you'd like to help:

1. **Fork** the repo
2. **Create a branch** for your feature (`git checkout -b feature/my-feature`)
3. **Commit** your changes (`git commit -m "Add my feature"`)
4. **Push** to your branch (`git push origin feature/my-feature`)
5. Open a **Pull Request**

### Reporting Bugs

Please use the [GitHub Issues](https://github.com/wheelbarrel00/EverythingQuests/issues) tab. Include:
- Your WoW client version and region
- Steps to reproduce
- Any error messages from `/console scriptErrors 1`
- Screenshot if applicable

---

## Roadmap

- [ ] Full chain coverage beyond Midnight (TWW, Dragonflight, older expansions)
- [ ] Complete localization for non-enUS locales
- [ ] Chain Guide options tab buildout
- [ ] WoWInterface and Wago publishing

---

## License

This project is licensed under the [MIT License](LICENSE).

---

## Acknowledgments

- Built by Wheelbarrel00
- Packaged and deployed with **[BigWigsMods/packager](https://github.com/BigWigsMods/packager)**
- Minimap button powered by **[LibDBIcon](https://www.curseforge.com/wow/addons/libdbicon-1-0)** and **[LibDataBroker](https://www.curseforge.com/wow/addons/libdatabroker-1-1)**
- Font/texture picker powered by **[LibSharedMedia](https://www.curseforge.com/wow/addons/libsharedmedia-3-0)**
- WoW API references from **[Warcraft Wiki](https://warcraft.wiki.gg)**

---

<p align="center">
  <sub>Made for the Midnight expansion · 2026</sub>
</p>
