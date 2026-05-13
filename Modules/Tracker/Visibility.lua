-- Modules/Tracker/Visibility.lua
-- Implements General-tab visibility toggles for the on-screen tracker:
--   • lockTracker      → block drag-to-move
--   • hideInCombat     → hide while PLAYER_REGEN_DISABLED, show on _ENABLED
--   • hideInInstances  → hide whenever IsInInstance() is true
--   • hideOnMapOpen    → hide when WorldMapFrame:IsShown()
--   • autoTrackAccepted → mirror Blizzard's auto-track on QUEST_ACCEPTED;
--                         if user turned this off, immediately remove the
--                         watch Blizzard added.

local _, ns = ...

local V = ns:RegisterSubsystem("TrackerVisibility", {})

local function getCfg()
    local DB = ns:GetSubsystem("DB")
    return DB and DB.db.profile.general or nil
end

-- Hide rules combine with OR: any active rule hides the frame.
local function shouldHide()
    local cfg = getCfg()
    if not cfg then return false end
    if cfg.hideInCombat and InCombatLockdown and InCombatLockdown() then return true end
    if cfg.hideInInstances and IsInInstance and (IsInInstance()) then return true end
    if cfg.hideOnMapOpen and WorldMapFrame and WorldMapFrame:IsShown() then return true end
    return false
end

function V:Apply()
    local Tracker = ns:GetSubsystem("Tracker")
    if not (Tracker and Tracker.frame) then return end
    if shouldHide() then
        Tracker.frame:Hide()
    else
        Tracker.frame:Show()
    end
end

function V:OnEnable()
    local Events = ns:GetSubsystem("Events")
    local function apply() self:Apply() end

    Events:On("PLAYER_REGEN_DISABLED", apply)   -- entered combat
    Events:On("PLAYER_REGEN_ENABLED",  apply)   -- left combat
    Events:On("PLAYER_ENTERING_WORLD", apply)   -- entered/left instance

    -- Auto-track-accepted hook. Blizzard auto-watches new quests by default;
    -- when the user disables that setting, remove the watch right after
    -- accept so it never appears in the tracker.
    Events:On("QUEST_ACCEPTED", function(_, questID)
        local cfg = getCfg()
        if not (cfg and questID) then return end
        if cfg.autoTrackAccepted == false then
            if C_QuestLog and C_QuestLog.RemoveQuestWatch then
                C_QuestLog.RemoveQuestWatch(questID)
            end
        end
    end)

    -- Watch WorldMapFrame for hide-on-map-open. Hooked once after frame
    -- exists; PLAYER_ENTERING_WORLD guarantees that.
    Events:On("PLAYER_ENTERING_WORLD", function()
        if WorldMapFrame and not V._mapHooked then
            V._mapHooked = true
            WorldMapFrame:HookScript("OnShow", apply)
            WorldMapFrame:HookScript("OnHide", apply)
        end
        apply()
    end)
end
