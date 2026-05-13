-- Modules/MapPOI/Provider.lua
-- MapCanvasDataProvider that paints quest POIs on the world map for every
-- quest in the player's log. Supplements (does NOT replace) Blizzard's
-- built-in quest POI provider — removing Blizzard's has historically caused
-- taint, so we layer our pins on top.
--
-- Registration goes through LibMapPinHandler (a parallel "shadow canvas"),
-- not WorldMapFrame:AddDataProvider directly. Direct registration causes the
-- canvas's secureexecuterange iteration to assert on the addon-tainted
-- provider entry (Blizzard_MapCanvas.lua:280: assertion failed!). The shadow
-- canvas keeps our provider in a parallel list and dispatches to it via
-- hooked canvas methods — Blizzard's secureexecuterange only ever sees its
-- own clean list. See Libs/LibMapPinHandler/LibMapPinHandler.lua for details.
--
-- We register on PLAYER_ENTERING_WORLD rather than PLAYER_LOGIN because
-- WorldMapFrame isn't always fully initialized at PLAYER_LOGIN, and the
-- canonical pattern (BtWQuests.lua:987-993) uses PEW.

local _, ns = ...

local M = ns:RegisterSubsystem("MapPOIProvider", {})

local PIN_TEMPLATE = "EQLQuestPinTemplate"

-- ─── Data provider mixin ──────────────────────────────────────────────
local providerMixin = CreateFromMixins(MapCanvasDataProviderMixin)

-- The canvas must be told which frame TYPE backs each pin template name,
-- otherwise AcquirePin trips an assertion when it tries to instantiate a pin
-- from an unregistered template. SetPinTemplateType only takes effect for the
-- *current* canvas, so we register here in OnAdded.
function providerMixin:OnAdded(mapCanvas)
    MapCanvasDataProviderMixin.OnAdded(self, mapCanvas)
    mapCanvas:SetPinTemplateType(PIN_TEMPLATE, "BUTTON")
end

function providerMixin:RemoveAllData()
    if self:GetMap() then
        self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
    end
end

-- Module-scope scratch table reused across every _DoRefresh call. Tracks
-- which questIDs the primary source already covered so the secondary
-- (Cache-walked) source doesn't double-pin them. wipe()d at the top of
-- _DoRefresh — never allocated fresh.
local _seenQids = {}

-- The actual refresh work. Public RefreshAllData below throttles into
-- this. Two-source coverage:
--   1. Blizzard's POI API for the obvious quests on this map.
--   2. Walk the player's quest log Cache; any quest with a waypoint on
--      this map but no POI flag gets pinned too (campaign quests,
--      super-tracked-only quests, etc. that slip through GetQuestsOnMap).
-- The previous version returned a `{qid -> {x,y}}` table and iterated
-- it to AcquirePin — that allocated one fresh sub-table per pin plus
-- the wrapper table on every refresh. Now we AcquirePin inline and use
-- a single reused _seenQids set for dedup.
function providerMixin:_DoRefresh()
    self:RemoveAllData()

    -- Early-out when the world map isn't visible. Without this, every
    -- QUEST_LOG_UPDATE while the map is closed still ran the full walk
    -- and discarded the result — meaningful waste during active play.
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end

    local map = self:GetMap()
    if not map then return end
    local mapID = map:GetMapID()
    if not mapID then return end

    local Cache = ns:GetSubsystem("Cache")
    wipe(_seenQids)

    local primary = C_QuestLog.GetQuestsOnMap and C_QuestLog.GetQuestsOnMap(mapID)
    if primary then
        for i = 1, #primary do
            local info = primary[i]
            local qid  = info and info.questID
            if qid then
                local x, y = info.x, info.y
                if (not x or not y) and C_QuestLog.GetNextWaypointForMap then
                    x, y = C_QuestLog.GetNextWaypointForMap(qid, mapID)
                end
                if type(x) == "number" and type(y) == "number" then
                    _seenQids[qid] = true
                    local q = Cache:Get(qid)
                    if q then
                        map:AcquirePin(PIN_TEMPLATE, qid, x, y, q.isComplete)
                    end
                end
            end
        end
    end

    if Cache and C_QuestLog.GetNextWaypointForMap then
        for qid, q in pairs(Cache:All()) do
            if not _seenQids[qid] then
                local x, y = C_QuestLog.GetNextWaypointForMap(qid, mapID)
                if type(x) == "number" and type(y) == "number" then
                    map:AcquirePin(PIN_TEMPLATE, qid, x, y, q.isComplete)
                end
            end
        end
    end
end

-- Throttle: Blizzard's canvas fires several events on map open (OnShow,
-- OnMapChanged, RefreshAllDataProviders, ReapplyPinFrameLevels, etc.) and
-- without coalescing we'd run _DoRefresh multiple times in the same frame
-- burst. 50ms is below human-perceptible delay and easily covers the burst.
function providerMixin:RefreshAllData()
    if self._refreshPending then return end
    self._refreshPending = true
    C_Timer.After(0.05, function()
        self._refreshPending = false
        self:_DoRefresh()
    end)
end

-- Provider's OnMapChanged is what the shadow canvas dispatches via
-- secureexecuterange when Blizzard's canvas fires OnMapChanged. Default
-- behavior: refresh pins for the new map.
function providerMixin:OnMapChanged()
    self:RefreshAllData()
end

-- ─── Subsystem lifecycle ───────────────────────────────────────────────
local function attach(self)
    if self.attached then return end
    if not WorldMapFrame then return end
    local Lib = LibStub("LibMapPinHandler-1.0", true)
    if not Lib then return end
    local shadow = Lib:GetShadowCanvas(WorldMapFrame)
    if not shadow then return end

    self.provider = CreateFromMixins(providerMixin)
    shadow:AddDataProvider(self.provider)
    self.shadow   = shadow
    self.attached = true
end

function M:OnEnable()
    local Events = ns:GetSubsystem("Events")

    -- Lazy attachment: PLAYER_ENTERING_WORLD fires after PLAYER_LOGIN once the
    -- world is fully loaded. This is the canonical timing per BtWQuests; trying
    -- to attach at PLAYER_LOGIN can race against WorldMapFrame initialization.
    Events:On("PLAYER_ENTERING_WORLD", function() attach(self) end)

    -- Repaint when the player's quest log changes. The shadow canvas already
    -- handles OnMapChanged dispatch for free; we just need quest-state events.
    local function refresh()
        if self.provider and WorldMapFrame and WorldMapFrame:IsShown() then
            self.provider:RefreshAllData()
        end
    end
    Events:On("QUEST_LOG_UPDATE",       refresh)
    Events:On("QUEST_ACCEPTED",         refresh)
    Events:On("QUEST_REMOVED",          refresh)
    Events:On("QUEST_TURNED_IN",        refresh)
    Events:On("SUPER_TRACKING_CHANGED", refresh)
end
