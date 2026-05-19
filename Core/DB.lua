-- Core/DB.lua
-- Saved-variable layout. Per-character only (per scope decision).
--
--   EverythingQuestsDB        - account-wide settings (visual, filter prefs, manual sort order)
--   EverythingQuestsCharDB    - per-character state (favorites, watched, minimap pos, last tab)
--   EverythingQuestsChainCache - cross-character chain-completion cache for ChainGuide

local _, ns = ...

local DB = ns:RegisterSubsystem("DB", {})

DB.defaults = {
    profile = {
        general = {
            lockTracker      = false,
            hideInCombat     = false,
            hideInInstances  = false,
            hideOnMapOpen    = false,
            autoTrackAccepted = true,
        },
        tracker = {
            anchor = "TOPRIGHT",
            xOffset = -85,
            yOffset = -200,
            width = 305,
            maxHeight = 600,
            scale = 1.0,
            simplifyMode = false,
            sortMode = "zone",        -- zone|status|type|level|distance|manual
            manualOrder = {},         -- [questID] = ordinal int
            -- Match Blizzard's default tracker visibility: only show quests
            -- in the watch list. Disable to firehose all quests in the log.
            showOnlyWatched = true,
            showBackground = false,
            backgroundColor = { r = 0, g = 0, b = 0, a = 0.6 },
            -- Optional 1px border wrapping the tracker background region.
            -- Off by default; color is user-set (the picker carries the
            -- Class option). Default = suite brand red #6D0501.
            showBorder = false,
            borderColor = { r = 0.427, g = 0.020, b = 0.004, a = 1 },
            borderSize  = 1,                                                      -- edge thickness in px (Appearance slider, 1-5)
            -- Default font. Bundled with the addon and registered with
            -- LibSharedMedia in Core/Media.lua, so this resolves for every
            -- user with no external dependency. Must match the LSM-
            -- registered name exactly (see Media.lua FONTS).
            font = "GothamXNarrow Black",
            fontSize = 15,
            -- Font outline flags passed to FontString:SetFont. "OUTLINE"
            -- gives a thin black stroke that keeps the tracker text
            -- readable over bright/busy in-world backdrops. WoW accepts
            -- comma-joined combos like "MONOCHROME, OUTLINE"; empty string
            -- disables the outline entirely.
            fontOutline = "OUTLINE",
            colorByDifficulty = true,
            questSoundEnabled = true,
            questCompleteSound = "EQ: Work Complete",
            -- Phase 2 additions
            showLevelInTracker   = false,
            showZoneTag          = false,
            showObjectiveNumbers = true,
            showQuestID          = false,
            -- Quests & Campaign section headers show "shown / total of
            -- that category" (e.g. 3/9) instead of just the count. On by
            -- default; toggled on the Tracker options tab. Other sections
            -- have no meaningful per-category total, so they keep a plain
            -- count (still recolored to match the header).
            showQuestTotal       = true,
            titleColorOverride   = nil,                                          -- {r,g,b,a} when set; nil = use difficulty/yellow
            headerColor          = { r = 0.93, g = 0.32, b = 0.10, a = 1 },     -- section header text color
            blockSpacing         = 2,                                            -- vertical gap between blocks
            scrollBarBg          = true,                                         -- background strip behind the scroll bar
            scrollBarBgColor     = { r = 0.60, g = 0.60, b = 0.65, a = 0.25 },    -- pale grey, low alpha: barely visible but hints the bar is there
            -- Type-by-type visibility filters. All on by default — the user
            -- opts INTO hiding categories rather than opting in to seeing them.
            filters = {
                showNormal      = true,    -- non-special player quests
                showDaily       = true,
                showWeekly      = true,
                showCampaign    = true,
                showWorld       = true,
                onlyCurrentZone = false,   -- restrict to the player's current zone
            },
            -- Section visibility. Sections still render their data; these
            -- flags hide the section header + rows entirely. Quests &
            -- Endeavors stay always-on (they're the core surface and have
            -- no obvious off-switch); Profession and World Quests can be
            -- toggled because some players never use them.
            showProfessionSection = true,
            showWorldQuestsSection = true,
            -- World Quests are pinned to the bottom of the tracker and
            -- always visible; this caps that region at a fraction of the
            -- tracker's inner height so a big WQ load can't swallow the
            -- whole tracker (it scrolls internally past the cap).
            worldQuestsPinnedMaxFraction = 0.40,
        },
        worldQuests = {
            -- Master switch for the World Quests MAP features (everything
            -- the World Quests options tab governs). When false, EQ draws
            -- no WQ world-map pins, no WQ summary box, and no WQ zone
            -- list — for players who want the tracker but none of the WQ
            -- map overlays. Does NOT touch the tracker's own World Quests
            -- section (that stays controlled by tracker.showWorldQuests-
            -- Section). Overrides the WQ map options below (they still
            -- save, just inert until this is re-enabled).
            enabled = true,
            showOnWorldMap = true,
            showOnZoneMap = true,
            filters = {
                gold = true, gear = true, rep = true, resource = true,
                ap = true, profession = true, pvp = true, pet = true, other = true,
            },
            factionFilters = {},        -- [factionID] = false to hide; absent = show
            zoneListSort = "time",      -- "time" | "type" | "faction" | "alpha"
            pinScale     = 1.0,
        },
        -- Non-WQ map overlays EQ draws on the world map.
        map = {
            -- The EQ-red ringed quest pins (the "red circles": "!" for
            -- available / "?" for turn-in) drawn from the player's quest
            -- log. false = EQ draws none of them on the world map.
            showQuestPins = true,
        },
        chainGuide = {
            scale = 1.0,
            showOnLogin = false,
            -- Per-category uiMapID overrides discovered at runtime via /eqs
            -- discover. These take priority over the seeds in _Index.lua so
            -- patch-revamped zones don't require editing the data file.
            zoneMapIDs = {},
            -- When true, API-discovered questlines that aren't in our
            -- routing table are shown in the discovering category. Default
            -- false for a clean curated-feeling list.
            showUnroutedChains = false,
        },
        appearance = {
            optionsAlpha = 0.95,
        },
    },
    char = {
        favorites = {},               -- [questID] = true
        pinned = {},                  -- [questID] = true (forces visibility past filters)
        hidden = {},                  -- [questID] = true (forces invisibility regardless of filters; mutex with pinned)
        trackedWorldQuests = {},      -- [questID] = true (persistent WQ watches; restored on login)
        collapsedHeaders = {},        -- [headerKey] = true (reserved for multi-section future use)
        trackerCollapsed = false,     -- whole on-screen tracker collapsed to just the header
        minimap = { hide = false, minimapPos = 220 },
        lastOptionsTab = "general",
    },
}

function DB:OnInitialize()
    local AceDB = LibStub("AceDB-3.0")
    self.db = AceDB:New("EverythingQuestsDB", self.defaults, true)
    _G.EverythingQuestsCharDB = _G.EverythingQuestsCharDB or {}
    self.char = _G.EverythingQuestsCharDB
    for k, v in pairs(self.defaults.char) do
        if self.char[k] == nil then
            self.char[k] = (type(v) == "table") and CopyTable(v) or v
        end
    end
    _G.EverythingQuestsChainCache = _G.EverythingQuestsChainCache or {}
    self.chainCache = _G.EverythingQuestsChainCache
    ns.db = self.db

    -- Harden the saved manual sort order against corruption: a non-numeric
    -- ordinal from a damaged SavedVariables would crash the tracker's
    -- manual-sort comparator. Done once here (Commit always writes clean
    -- 1..N, so only the disk-loaded value needs sanitizing).
    local Util = ns.Util
    local t = self.db and self.db.profile and self.db.profile.tracker
    if Util and Util.ReconcileOrder and t then
        t.manualOrder = Util.ReconcileOrder(t.manualOrder)
    end
end
