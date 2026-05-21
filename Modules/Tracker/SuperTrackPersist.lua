-- Modules/Tracker/SuperTrackPersist.lua
-- Blizzard restores the previously super-tracked quest on login, which
-- revives the in-game waypoint arrow (and TomTom's, when installed —
-- TomTom hooks C_SuperTrack.SetSuperTrackedQuestID and renders an arrow
-- following whatever quest is restored). When the player has not asked
-- for that persistence (the default), we clear the super-track shortly
-- after login so the session starts clean.
--
-- Gated by db.profile.general.restoreSuperTrackOnLogin. The clear runs
-- on a small delay so Blizzard's own restore (which happens around
-- PLAYER_LOGIN, before our OnEnable returns) has settled — clearing
-- before the restore lands would silently no-op.

local _, ns = ...

local STP = ns:RegisterSubsystem("TrackerSuperTrackPersist", {})

local function shouldRestore()
    local DB = ns:GetSubsystem("DB")
    return DB and DB.db.profile.general
           and DB.db.profile.general.restoreSuperTrackOnLogin == true
end

function STP:OnEnable()
    if shouldRestore() then return end
    if not (C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID) then return end
    C_Timer.After(0.5, function()
        C_SuperTrack.SetSuperTrackedQuestID(0)
    end)
end
