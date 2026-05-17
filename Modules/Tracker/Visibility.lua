-- Modules/Tracker/Visibility.lua
-- Implements General-tab visibility toggles for the on-screen tracker:
--   • lockTracker      → block drag-to-move
--   • hideInCombat     → hide while PLAYER_REGEN_DISABLED, show on _ENABLED
--   • hideInInstances  → hide whenever IsInInstance() is true
--   • hideOnMapOpen    → hide when WorldMapFrame:IsShown()
--   • autoTrackAccepted → on QUEST_ACCEPTED, force the watch state to match
--                         the setting. ON (default): explicitly add the
--                         watch (Blizzard never auto-watches campaign
--                         quests — its default tracker shows them via a
--                         separate campaign module, so GetQuestWatchType
--                         stays nil and EQ's showOnlyWatched filter would
--                         hide them). OFF: strip the watch Blizzard added.

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

    -- Auto-track-accepted hook. Force the watch state to match the setting
    -- rather than trusting Blizzard's auto-watch (which does NOT add a
    -- watch entry for campaign quests — its default tracker surfaces those
    -- through a dedicated campaign module, leaving GetQuestWatchType nil,
    -- so EQ's showOnlyWatched filter hid freshly accepted campaign quests
    -- until the user re-ticked them in the quest log).
    Events:On("QUEST_ACCEPTED", function(_, questID)
        local cfg = getCfg()
        if not (cfg and questID and C_QuestLog) then return end

        -- World/task quests have their own watch channel
        -- (AddWorldQuestWatch, owned by WorldQuests/WatchPersist.lua).
        -- Don't touch them with the normal-quest watch API.
        if C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(questID) then
            return
        end

        local watched = C_QuestLog.GetQuestWatchType
                         and C_QuestLog.GetQuestWatchType(questID) ~= nil

        if cfg.autoTrackAccepted == false then
            -- Opted out: strip any watch so it never reaches the tracker.
            if watched and C_QuestLog.RemoveQuestWatch then
                C_QuestLog.RemoveQuestWatch(questID)
            end
        elseif not watched then
            -- Auto-track ON (default): add the watch ourselves (Manual,
            -- same as ticking the quest-log checkbox) so every accepted
            -- quest — campaign included — lands in the tracker at once.
            if C_QuestLog.AddQuestWatch then
                C_QuestLog.AddQuestWatch(questID)
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
