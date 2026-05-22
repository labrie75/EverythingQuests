-- Modules/Tracker/SuperTrackPersist.lua
-- Blizzard restores the previously super-tracked quest on login, which
-- revives the in-game waypoint arrow (and TomTom's, when installed —
-- TomTom hooks C_SuperTrack.SetSuperTrackedQuestID and renders an arrow
-- following whatever quest is restored). When the player has not asked
-- for that persistence (the default), we clear the super-track shortly
-- after a FRESH login so the session starts clean.
--
-- Critically, this must only fire on a genuine login / client restart —
-- NOT on a /reload. A reload is a mid-session refresh; the player still
-- has a quest focused and expects it to stay focused. We tell the two
-- apart with PLAYER_ENTERING_WORLD's isInitialLogin arg (true only on a
-- real login, false on /reload and on zone changes). Clearing in OnEnable
-- instead — which runs on every PLAYER_LOGIN, and /reload fires
-- PLAYER_LOGIN too — was the bug that wiped super-tracking on every reload.
--
-- Gated by db.profile.general.restoreSuperTrackOnLogin (default false =
-- clear on fresh login). The clear runs on a small delay so Blizzard's
-- own restore (which lands around login) has settled first.

local _, ns = ...

local STP = ns:RegisterSubsystem("TrackerSuperTrackPersist", {})

local function shouldRestore()
    local DB = ns:GetSubsystem("DB")
    return DB and DB.db.profile.general
           and DB.db.profile.general.restoreSuperTrackOnLogin == true
end

function STP:OnEnable()
    if not (C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID) then return end
    local Events = ns:GetSubsystem("Events")
    if not Events then return end

    Events:On("PLAYER_ENTERING_WORLD", function(_, isInitialLogin)
        -- Only a fresh login / client restart. /reload (isInitialLogin
        -- false) and zone changes must leave the player's current
        -- super-track untouched.
        if not isInitialLogin then return end
        if shouldRestore() then return end
        C_Timer.After(0.5, function()
            C_SuperTrack.SetSuperTrackedQuestID(0)
        end)
    end)
end
