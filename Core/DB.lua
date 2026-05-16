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
            titleColorOverride   = nil,                                          -- {r,g,b,a} when set; nil = use difficulty/yellow
            headerColor          = { r = 0.93, g = 0.32, b = 0.10, a = 1 },     -- section header text color
            blockSpacing         = 2,                                            -- vertical gap between blocks
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
        },
        worldQuests = {
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
        chainGuide = {
            scale = 1.0,
            showOnLogin = false,
            -- Per-category uiMapID overrides discovered at runtime via /eq
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
end
