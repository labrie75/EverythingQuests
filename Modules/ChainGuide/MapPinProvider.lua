-- Modules/ChainGuide/MapPinProvider.lua
-- MapCanvasDataProvider that pins the player's TRACKED chain's quests on the
-- world map (Chain Guide Phase 3A). A third EQ provider alongside MapPOIProvider
-- (red log-quest pins) and WQWorldMap (world-quest pins) on the SAME taint-
-- isolating LibMapPinHandler shadow canvas — never WorldMapFrame:AddDataProvider.
--
-- Data source: the tracked chain (ns:GetSubsystem("ChainGuide"):GetTrackedChain).
-- For each quest item we ask ChainGuideWaypoint:ResolveForPin for the right
-- map point (live turn-in/objective for in-log quests, giver coord otherwise)
-- and pin only the ones that fall on the map currently being viewed. We NEVER
-- retarget the map to follow the chain — that is the documented AreaPOI taint
-- hot-spot; pins simply appear on whatever map the player opens.
--
-- Like MapPOIProvider we attach on PLAYER_ENTERING_WORLD (WorldMapFrame isn't
-- reliably ready at PLAYER_LOGIN) and throttle refreshes to coalesce the
-- map-open event burst.

local _, ns = ...

local M = ns:RegisterSubsystem("ChainGuideMapPins", {})

local PIN_TEMPLATE = "EQChainPinTemplate"

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

-- Module-scope scratch reused every refresh — a quest id can appear in items[]
-- more than once (faction/race variations collapse to one id), so dedup before
-- pinning. wipe()d at the top of _DoRefresh, never allocated fresh.
local _seen = {}

function providerMixin:_DoRefresh()
    self:RemoveAllData()

    -- User toggle (Chain Guide tab): hide the chain map pins entirely.
    local DB = ns:GetSubsystem("DB")
    if DB and DB.db.profile.chainGuide and DB.db.profile.chainGuide.showMapPins == false then
        return
    end

    -- Early-out when the world map isn't visible — skip the whole walk on
    -- quest events while the map is closed (mirrors MapPOIProvider).
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end

    local CG = ns:GetSubsystem("ChainGuide")
    local chain = CG and CG.GetTrackedChain and CG:GetTrackedChain()
    if not chain then return end

    local Database   = ns:GetSubsystem("ChainGuideDatabase")
    local Characters = ns:GetSubsystem("ChainGuideCharacters")
    local W          = ns:GetSubsystem("ChainGuideWaypoint")
    if not (Database and Characters and W) then return end

    -- Items stream in asynchronously for API/campaign chains; ensure + normalize
    -- (both idempotent), then re-pin once they arrive if they're not ready yet.
    local QLS = ns:GetSubsystem("ChainGuideQuestLineSource")
    if QLS and QLS.EnsureChainItems then QLS:EnsureChainItems(chain) end
    Database:NormalizeChain(chain)
    local items = chain.items
    if not (items and #items > 0) then
        if not self._itemsRetry then
            self._itemsRetry = true
            C_Timer.After(0.4, function()
                self._itemsRetry = false
                self:RefreshAllData()
            end)
        end
        return
    end

    local map = self:GetMap()
    if not map then return end
    local mapID = map:GetMapID()
    if not mapID then return end

    local char = Database:CurrentCharacter()
    local nextStep = W.NextActionableStep and W:NextActionableStep(chain)
    local nextID = nextStep and nextStep.id

    wipe(_seen)
    for i = 1, #items do
        local raw = items[i]
        if raw and raw.type ~= "chain" and not raw.breadcrumb then
            local item = Database:GetVariation(raw, char)
            local qid  = item and item.id
            if qid and not _seen[qid] then
                local rm, rx, ry, inLog = W:ResolveForPin(qid, chain)
                if rm == mapID and rx and ry then
                    _seen[qid] = true
                    local status
                    if qid == nextID then
                        status = "next"
                    elseif Characters:IsQuestCompleted(qid) then
                        status = "complete"
                    elseif inLog then
                        status = "active"
                    else
                        status = "pending"
                    end
                    map:AcquirePin(PIN_TEMPLATE, qid, rx, ry, status, inLog)
                end
            end
        end
    end
end

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

-- Public repaint, called by CG:OnTrackedChainChanged (track/untrack) and the
-- options toggle. No-ops unless attached and the map is open.
function M:Refresh()
    if self.provider and WorldMapFrame and WorldMapFrame:IsShown() then
        self.provider:RefreshAllData()
    end
end

function M:OnEnable()
    local Events = ns:GetSubsystem("Events")

    Events:On("PLAYER_ENTERING_WORLD", function() attach(self) end)

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
