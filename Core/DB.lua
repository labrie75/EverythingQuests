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
            -- Quest dialog automation (handled by Modules/QuestAuto.lua).
            -- Both default OFF — accepting / turning in quests for the
            -- player is opinionated, so it's strictly opt-in.
            autoAcceptQuests = false,
            autoTurnInQuests = false,
            -- Super-track persistence (Modules/Tracker/SuperTrackPersist).
            -- Blizzard restores the previously super-tracked quest on
            -- login, which also revives the in-game waypoint arrow (and
            -- TomTom's, if installed). ON by default so your focused quest
            -- and its waypoint arrow carry across logins; flip OFF for a
            -- clean start each login.
            restoreSuperTrackOnLogin = true,
            -- questNameplateIcons (Modules/Nameplates/QuestIcons.lua) is
            -- intentionally ABSENT from defaults: nil = "auto", which the
            -- module resolves to ON unless ElvUI is loaded (it shows its own
            -- nameplate quest icons, so we'd double up). Toggling the General-
            -- tab checkbox writes an explicit true/false.
        },
        tracker = {
            anchor = "TOPRIGHT",
            xOffset = -85,
            yOffset = -200,
            width = 305,
            maxHeight = 600,
            scale = 1.0,
            simplifyMode = false,
            sortMode = "zone",        -- zone|status|type|level|distance|recent|manual
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
            showItemButtons = true,                                              -- clickable usable-item button beside quests that have one
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
            overrideCompleteGreen = true,                                        -- when a title color is set, use it for completed quests instead of the "ready to turn in" green
            headerColor          = { r = 0.93, g = 0.32, b = 0.10, a = 1 },     -- section header text color
            blockSpacing         = 2,                                            -- vertical gap between blocks
            scrollBarBg          = true,                                         -- background strip behind the scroll bar
            scrollBarBgColor     = { r = 0.60, g = 0.60, b = 0.65, a = 0.25 },    -- pale grey, low alpha: barely visible but hints the bar is there
            hideScrollBar        = false,                                        -- hide the scroll bar entirely; mouse wheel still scrolls
            showQuestPopups      = true,                                         -- "Quest Discovered!"/"Quest Complete!" auto-quest popup boxes
            showRecentlyAddedTag = true,                                         -- "NEW" tag on quests accepted within the last hour
            -- Blizzard-style split click on tracker quest rows. OFF by
            -- default to preserve EQ's long-standing behavior (a left-click
            -- anywhere on the row focuses/super-tracks). When ON: clicking
            -- the left-side POI icon/circle focuses the quest, while clicking
            -- the title (or anywhere else on the row) opens it in the quest
            -- log. Shift-left-click still toggles watch; right-click still
            -- opens the context menu in both modes.
            splitQuestClick      = false,
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
            showAchievementsSection = true,
            showWorldQuestsSection = true,
            -- Optional per-zone quest progress bar (questline-based,
            -- approximate). OFF by default: it's slightly heavier (questline
            -- discovery + quest-list caching) and not everyone wants it. Can
            -- live as a tracker section OR as its own movable/scalable frame.
            -- See Modules/Tracker/ZoneProgress.lua.
            showZoneProgressBar = false,
            -- "tracker" = a section at the top of the on-screen tracker;
            -- "floating" = a standalone frame the user can drag anywhere.
            -- Defaults to floating so it never crowds the tracker.
            zoneProgressLocation = "floating",
            -- Floating-frame state (position / scale / lock). Position is a
            -- standard point+offset relative to UIParent, saved on drag-stop.
            zoneProgressBar = {
                point = "CENTER", relPoint = "CENTER", x = 0, y = 220,
                scale = 1.0,
                locked = false,
                -- Floating-bar appearance (Appearance tab → Zone Bar section).
                -- Defaults reproduce the original look. headerColor / countColor
                -- / font are intentionally ABSENT (nil): nil header/count colors
                -- fall back to the built-in red/gold, and a nil font follows the
                -- tracker's own font. Only the show* toggles need a stored default.
                showBorder = true,
                showBackground = true,
            },
            -- Auto-list every world quest available in the player's CURRENT
            -- zone in the tracker's World Quests section, without having to
            -- track each one. OFF by default — in WQ-dense zones this can be
            -- a long list. Purely a display source: these rows are NOT added
            -- to the persistent watch list, so they vanish when you leave the
            -- zone. Manually-tracked WQs still show regardless of this.
            autoListZoneWorldQuests = false,
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
        history = {
            -- Quest history recorder (Modules/History/Recorder.lua). Writes
            -- entries to the account-wide `EverythingQuestsHistory` SV on
            -- every QUEST_TURNED_IN. Master switch + rolling-window cap.
            enabled   = true,
            retention = 5000,                                                    -- entries; 0 = unlimited
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
    global = {
        -- Stores the version string of the most recent "What's New" popup
        -- the user has dismissed (Modules/WhatsNew.lua). Account-wide so a
        -- single dismiss covers every character. Compared against the
        -- hard-coded FEATURE_POPUP_VERSION in WhatsNew.lua — when they
        -- don't match, the popup shows once then writes the version here.
        whatsNewSeen = "",
        -- Per-zone progress bar: account-wide cache of each questline's quest
        -- list (static game data, identical for every character). Stored
        -- monotonically by ZoneProgress so the denominator never shrinks.
        zoneProgress = {
            qlQuests = {},            -- [questLineID] = { questID, ... } static lists
            -- Learned, locale-independent zone→category map. The denominator
            -- itself comes from ChainGuide's authored routing table (see
            -- Modules/Tracker/ZoneProgress.lua); this just caches which category
            -- each uiMapID resolved to so completed/localized zones still map.
            zoneCat = {},             -- [uiMapID] = catID
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
        -- LEGACY (v1.14.0): per-character discovered questlines. No longer read
        -- — the Zone Progress denominator now comes from ChainGuide's authored
        -- routing table (see Modules/Tracker/ZoneProgress.lua). Kept so old
        -- SavedVariables still load cleanly; safe to drop in a future cleanup.
        zoneProgress = {
            questlines = {},          -- [zoneRootID] = { [questLineID] = true }
        },
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

-- ─── Chain-cache hygiene ────────────────────────────────────────────────────
-- The account-wide EverythingQuestsChainCache accumulates two unbounded,
-- persisted caches: per-character `completed` records (ChainGuideCharacters)
-- and harvested `questCoords` (ChainGuideWaypoint). Both are re-derivable, so we
-- age out stale entries on a throttled timer. The thresholds are deliberately
-- generous: the record TTL only catches deleted/long-abandoned alts, and coords
-- re-harvest on the next accept. time() is epoch, so the comparison survives
-- client reboots (GetTime() would not).
local PRUNE_INTERVAL = 24 * 60 * 60         -- run at most once per day
local RECORD_TTL     = 180 * 24 * 60 * 60   -- 180 days: abandoned-alt records
local COORD_TTL      = 90 * 24 * 60 * 60    -- 90 days: waypoint coordinates

-- Returns (recordsPruned, coordsPruned). Pass force=true to skip the throttle
-- (the "Prune stale entries now" button in Options uses this).
function DB:MaybePruneChainCache(force)
    local cache = self.chainCache
    if not cache then return 0, 0 end
    local now = time()
    if not force and cache.lastPrune and (now - cache.lastPrune) < PRUNE_INTERVAL then
        return 0, 0
    end

    local nRec, nCoord = 0, 0
    local Chars = ns:GetSubsystem("ChainGuideCharacters")
    if Chars and Chars.PruneStaleRecords then nRec = Chars:PruneStaleRecords(now, RECORD_TTL) or 0 end
    local WP = ns:GetSubsystem("ChainGuideWaypoint")
    if WP and WP.PruneStaleCoords then nCoord = WP:PruneStaleCoords(now, COORD_TTL) or 0 end

    cache.lastPrune = now
    return nRec, nCoord
end

function DB:OnEnable()
    -- Defer the prune off the login spike. By the time it fires, every
    -- subsystem's OnInitialize has run, so the Characters/Waypoint cache refs
    -- exist. Throttled internally to once a day via chainCache.lastPrune.
    if C_Timer and C_Timer.After then
        C_Timer.After(10, function() self:MaybePruneChainCache() end)
    else
        self:MaybePruneChainCache()
    end
end
