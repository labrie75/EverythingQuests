local _, ns = ...

local V = ns:RegisterSubsystem("TrackerVisibility", {})

local function getCfg()
    local DB = ns:GetSubsystem("DB")
    return DB and DB.db.profile.general or nil
end

local function shouldHide()
    local cfg = getCfg()
    if not cfg then return false end
    if cfg.hideInCombat and InCombatLockdown and InCombatLockdown() then return true end
    if cfg.hideInInstances and IsInInstance and (IsInInstance()) then return true end
    if cfg.hideOnMapOpen and WorldMapFrame and WorldMapFrame:IsShown() then return true end
    return false
end

-- Show/hide the tracker WITHOUT tainting. The tracker frame owns secure
-- item-button descendants (Modules/Tracker/ItemButtons.lua), so Hide()/Show()
-- on it are PROTECTED frame methods, blocked while InCombatLockdown() with an
-- ADDON_ACTION_BLOCKED that names EQ. This module is wired to
-- PLAYER_REGEN_DISABLED, where lockdown is already active, and the
-- hideInCombat rule by definition wants the hide DURING combat — so the
-- usual "defer to PLAYER_REGEN_ENABLED" pattern is inverted here (by then
-- shouldHide() is false and we'd show instead). Out of combat: use the real
-- Hide()/Show() (and undo any in-combat alpha damping). In combat: fall back
-- to a non-protected visual hide (alpha 0); the next out-of-combat Apply()
-- reconciles to the real Shown state.
local function setVisible(frame, visible)
    if InCombatLockdown and InCombatLockdown() then
        frame:SetAlpha(visible and 1 or 0)
        frame._eqCombatHidden = (not visible) or nil
        return
    end
    if frame._eqCombatHidden then
        frame:SetAlpha(1)
        frame._eqCombatHidden = nil
    end
    if visible then frame:Show() else frame:Hide() end
end

function V:Apply()
    local Tracker = ns:GetSubsystem("Tracker")
    if not (Tracker and Tracker.frame) then return end
    setVisible(Tracker.frame, not shouldHide())
end

function V:OnEnable()
    local Events = ns:GetSubsystem("Events")
    local function apply() self:Apply() end

    Events:On("PLAYER_REGEN_DISABLED", apply)
    Events:On("PLAYER_REGEN_ENABLED",  apply)
    Events:On("PLAYER_ENTERING_WORLD", apply)

    Events:On("QUEST_ACCEPTED", function(_, questID)
        local cfg = getCfg()
        if not (cfg and questID and C_QuestLog) then return end

        if C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(questID) then
            return
        end

        if cfg.autoTrackAccepted == false then
            local watched = C_QuestLog.GetQuestWatchType
                             and C_QuestLog.GetQuestWatchType(questID) ~= nil
            if watched and C_QuestLog.RemoveQuestWatch then
                C_QuestLog.RemoveQuestWatch(questID)
            end
        else
            -- Auto-track ON (default): ensure a MANUAL watch (same as ticking
            -- the quest-log checkbox). This is the actual fix for "newly
            -- accepted quests don't always track":
            --   • AddQuestWatch(questID) with no type adds an AUTOMATIC watch,
            --     and the engine silently evicts automatic watches once you
            --     pass its small auto-watch cap — so the Nth accepted quest
            --     would quietly drop out of the tracker.
            --   • When Blizzard's own autoQuestWatch CVar already auto-watched
            --     the quest (as AUTOMATIC), the old `not watched` guard skipped
            --     it, leaving it evictable.
            -- Forcing a MANUAL watch every accept is uncapped and stable, and
            -- still covers campaign quests Blizzard never auto-watches at all.
            if C_QuestLog.AddQuestWatch then
                local manual = Enum and Enum.QuestWatchType and Enum.QuestWatchType.Manual
                C_QuestLog.AddQuestWatch(questID, manual)
            end
        end
    end)

    Events:On("PLAYER_ENTERING_WORLD", function()
        if WorldMapFrame and not V._mapHooked then
            V._mapHooked = true
            WorldMapFrame:HookScript("OnShow", apply)
            WorldMapFrame:HookScript("OnHide", apply)
        end
        apply()
    end)
end
