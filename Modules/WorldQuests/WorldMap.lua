-- Modules/WorldQuests/WorldMap.lua
-- Data provider that paints world-quest pins on the world map. Mirrors the
-- shape of Modules/MapPOI/Provider.lua (registers a pin template type in
-- OnAdded, removes-then-acquires in RefreshAllData), but pulls from
-- C_TaskQuest instead of C_QuestLog and uses the WQ-specific pin template
-- with reward-icon visuals.
--
-- Same taint-isolation pattern: provider is registered through
-- LibMapPinHandler's shadow canvas, not WorldMapFrame:AddDataProvider.

local _, ns = ...

local M = ns:RegisterSubsystem("WQWorldMap", {})

local PIN_TEMPLATE = "EQWorldQuestPinTemplate"

-- Max reward-data preload attempts per quest before we give up counting it
-- as "pending". Some WQs never return reward data (cross-faction, transient
-- API gaps); without a cap one stuck quest keeps the adaptive retry firing
-- the full pin walk every 2s for the life of the open map.
local MAX_LOAD_ATTEMPTS = 3

-- Try the modern API first, fall back to the older shape. Either returns
-- WorldQuestInfo[]; field names sometimes differ (`questId` vs `questID`),
-- so we normalize when we read.
local function getWorldQuests(mapID)
    if C_TaskQuest then
        if C_TaskQuest.GetQuestsOnMap          then return C_TaskQuest.GetQuestsOnMap(mapID)          end
        if C_TaskQuest.GetQuestsForPlayerByMapID then return C_TaskQuest.GetQuestsForPlayerByMapID(mapID) end
    end
    return nil
end

-- An expired world quest can't be accepted, completed, or turned in, so it
-- has no value to surface. It only lingers because it's still momentarily in
-- GetQuestsOnMap (or a stale watch entry). C_TaskQuest.IsActive is the
-- canonical "still up" check; the time guard catches the window where the
-- timer has drained but the quest hasn't been culled yet.
local function isExpiredWQ(questID)
    if not C_TaskQuest then return false end
    if C_TaskQuest.IsActive and not C_TaskQuest.IsActive(questID) then
        return true
    end
    -- A live world quest ALWAYS has positive time remaining. nil (the API no
    -- longer tracks it — stale watch entry / drained) or <= 0 both mean it
    -- can't be completed, so it has no value to show. Seconds, not minutes:
    -- a WQ with <60s left reports 0 minutes and would be culled wrongly.
    if C_TaskQuest.GetQuestTimeLeftSeconds then
        local s = C_TaskQuest.GetQuestTimeLeftSeconds(questID)
        if not s or s <= 0 then return true end
    elseif C_TaskQuest.GetQuestTimeLeftMinutes then
        local m = C_TaskQuest.GetQuestTimeLeftMinutes(questID)
        if not m or m <= 0 then return true end
    end
    return false
end

local providerMixin = CreateFromMixins(MapCanvasDataProviderMixin)

function providerMixin:OnAdded(mapCanvas)
    MapCanvasDataProviderMixin.OnAdded(self, mapCanvas)
    mapCanvas:SetPinTemplateType(PIN_TEMPLATE, "BUTTON")
end

function providerMixin:RemoveAllData()
    if self:GetMap() then
        self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
    end
end

-- Real refresh work. Public RefreshAllData below throttles into this.
-- Tracks a `_pendingCount` so M:Refresh can tell whether a delayed retry is
-- worth it (we only retry when at least one quest had unloaded reward data
-- this pass — no more wasted refreshes when everything classified clean).
function providerMixin:_DoRefresh()
    self:RemoveAllData()
    self._pendingCount = 0

    -- Skip the whole walk when the world map isn't visible. Events like
    -- QUEST_LOG_UPDATE / TASK_PROGRESS_UPDATE were re-running the full
    -- WQ classification pass even while the player had the map closed —
    -- WQRewards:Classify allocates a fresh result table per quest, and
    -- Azeroth-level maps return 70+ entries, so this was significant
    -- garbage for no visible benefit.
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end

    local map = self:GetMap()
    if not map then return end
    local mapID = map:GetMapID()
    if not mapID then return end

    local DB = ns:GetSubsystem("DB")
    -- Master WQ switch off, or the world-map toggle off → no WQ pins.
    if not (DB and DB.db.profile.worldQuests.enabled ~= false
            and DB.db.profile.worldQuests.showOnWorldMap) then return end

    local quests = getWorldQuests(mapID)
    if not quests then return end

    local Rewards = ns:GetSubsystem("WQRewards")
    local filters = DB.db.profile.worldQuests.filters
    local factionFilters = DB.db.profile.worldQuests.factionFilters or {}

    -- Per-quest reward-load attempt counter, scoped to the current map.
    -- Wiped (not realloc'd) on map change so revisiting a map gives quests
    -- a fresh budget and the table never grows past one map's quest set.
    if self._loadAttemptsMapID ~= mapID then
        self._loadAttemptsMapID = mapID
        if self._loadAttempts then wipe(self._loadAttempts) else self._loadAttempts = {} end
    end
    local loadAttempts = self._loadAttempts

    for i = 1, #quests do
        local info = quests[i]
        local questID = info and (info.questID or info.questId)
        if questID and not isExpiredWQ(questID) then
            -- Pre-flight: when reward data isn't loaded, request a preload
            -- and count this quest as pending so the adaptive retry fires.
            -- Pins still render (FALLBACK visuals) so the quest is visible;
            -- the retry repaints once HaveQuestRewardData turns true.
            -- Capped per quest (MAX_LOAD_ATTEMPTS): after the budget is
            -- spent we stop counting it pending so a permanently-unloadable
            -- quest can't keep the 2s retry — and its full pin walk —
            -- running for the life of the open map.
            if HaveQuestRewardData and not HaveQuestRewardData(questID) then
                local n = (loadAttempts[questID] or 0) + 1
                loadAttempts[questID] = n
                if n <= MAX_LOAD_ATTEMPTS then
                    self._pendingCount = self._pendingCount + 1
                    if C_TaskQuest.RequestPreloadRewardData then
                        C_TaskQuest.RequestPreloadRewardData(questID)
                    end
                end
            elseif loadAttempts[questID] then
                -- Loaded — drop the counter so the table stays minimal and
                -- a later re-request (rare) gets a fresh attempt budget.
                loadAttempts[questID] = nil
            end

            local x, y = info.x, info.y
            if (not x or not y) and C_TaskQuest.GetQuestLocation then
                x, y = C_TaskQuest.GetQuestLocation(questID, mapID)
            end

            if type(x) == "number" and type(y) == "number" then
                local reward = Rewards:Classify(questID)
                local categoryAllowed = filters[reward.category] ~= false
                local factionAllowed  = true
                if categoryAllowed then
                    -- Resolve the WQ's faction. Global GetQuestInfoByQuestID
                    -- (the global, not the C_TaskQuest variant) returns
                    -- (title, factionID, ...) and works for un-accepted world
                    -- quests where C_QuestLog.GetQuestFactionID returns 0/nil.
                    local fid
                    if GetQuestInfoByQuestID then
                        local _t
                        _t, fid = GetQuestInfoByQuestID(questID)
                    end
                    if fid and fid > 0 and factionFilters[fid] == false then
                        factionAllowed = false
                    end
                    -- Backup pass: walk every disabled faction and ask whether
                    -- the WQ rewards rep with it. Catches quests whose primary
                    -- factionID resolves to 0 but still award rep with one of
                    -- our filtered factions (chain quests, faction assaults).
                    if factionAllowed and C_QuestLog and C_QuestLog.DoesQuestAwardReputationWithFaction then
                        for filterFid, val in pairs(factionFilters) do
                            if val == false and C_QuestLog.DoesQuestAwardReputationWithFaction(questID, filterFid) then
                                factionAllowed = false
                                break
                            end
                        end
                    end
                end
                if categoryAllowed and factionAllowed then
                    map:AcquirePin(PIN_TEMPLATE, questID, x, y, reward)
                end
            end
        end
    end

    -- Pins are now in their final state for this map — let the summary widget
    -- recount. Done here (not via shared event) so the summary never reads
    -- stale pin data; events fire to all listeners in undefined order.
    local Summary = ns:GetSubsystem("WQSummary")
    if Summary and Summary.Refresh then Summary:Refresh() end
    local ZoneList = ns:GetSubsystem("WQZoneMap")
    if ZoneList and ZoneList.Refresh then ZoneList:Refresh() end
end

-- Same throttle pattern as MapPOI/Provider — coalesces the burst of canvas
-- events fired on map open into one refresh. 50ms keeps it imperceptible.
function providerMixin:RefreshAllData()
    if self._refreshPending then return end
    self._refreshPending = true
    C_Timer.After(0.05, function()
        self._refreshPending = false
        self:_DoRefresh()
    end)
end

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

-- Cheap re-skin of just the selection visual on every active pin. Avoids the
-- full RefreshAllData walk (re-acquire all pins) when the only thing that
-- changed is which quest is super-tracked.
function M:UpdateSelections()
    if not (self.shadow and self.shadow.EnumeratePinsByTemplate) then return end
    local superID = (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
                     and C_SuperTrack.GetSuperTrackedQuestID()) or 0
    for pin in self.shadow:EnumeratePinsByTemplate(PIN_TEMPLATE) do
        if pin.UpdateSelectionVisual then
            pin:UpdateSelectionVisual(pin.questID == superID)
        end
    end
end

-- Public refresh used by the options tab (and potentially other modules) so
-- toggling a filter or visibility setting can repaint pins immediately.
-- Cheap when the world map is closed (early-out).
function M:Refresh()
    if not (self.provider and WorldMapFrame and WorldMapFrame:IsShown()) then return end
    self.provider:RefreshAllData()
    -- Adaptive retry: only schedule when this refresh found at least one
    -- quest with unloaded reward data. The throttled refresh writes
    -- _pendingCount on the provider; if it's zero, we don't burn a tick.
    -- Pending count is read on the next frame because RefreshAllData defers.
    if not self._retryPending then
        self._retryPending = true
        C_Timer.After(0.10, function()
            local pending = (self.provider and self.provider._pendingCount) or 0
            if pending > 0 then
                C_Timer.After(2.0, function()
                    self._retryPending = false
                    if self.provider and WorldMapFrame and WorldMapFrame:IsShown() then
                        self.provider:RefreshAllData()
                    end
                end)
            else
                self._retryPending = false
            end
        end)
    end
end

-- 60-second ticker keeps the per-pin time-left text fresh while the world
-- map is open. Started on map show, cancelled on map hide so it costs zero
-- when the user isn't looking at the map. Without this, the time text on
-- pins drifts as the player keeps the map open.
function M:StartTicker()
    if self._ticker then return end
    self._ticker = C_Timer.NewTicker(60, function()
        if WorldMapFrame and WorldMapFrame:IsShown() then
            self:Refresh()
        end
    end)
end

function M:StopTicker()
    if self._ticker then
        self._ticker:Cancel()
        self._ticker = nil
    end
end

function M:OnEnable()
    local Events = ns:GetSubsystem("Events")
    Events:On("PLAYER_ENTERING_WORLD", function()
        attach(self)
        if WorldMapFrame then
            WorldMapFrame:HookScript("OnShow", function() self:StartTicker() end)
            WorldMapFrame:HookScript("OnHide", function() self:StopTicker() end)
            if WorldMapFrame:IsShown() then self:StartTicker() end
        end
    end)

    local function refresh() self:Refresh() end
    -- Refresh on the events that change WQ availability/state.
    Events:On("WORLD_QUEST_COMPLETED_BY_SPELL",        refresh)
    Events:On("QUEST_LOG_UPDATE",                      refresh)
    Events:On("QUEST_TURNED_IN",                       refresh)
    Events:On("TASK_PROGRESS_UPDATE",                  refresh)

    -- Selection change is much cheaper than a refresh: only two pins flip
    -- visual state (the old super-tracked one + the new one). Walk them
    -- in-place rather than re-acquiring everything.
    Events:On("SUPER_TRACKING_CHANGED", function()
        if WorldMapFrame and WorldMapFrame:IsShown() then self:UpdateSelections() end
    end)
end
