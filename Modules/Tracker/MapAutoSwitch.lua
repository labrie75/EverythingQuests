-- Modules/Tracker/MapAutoSwitch.lua
-- Optional: when the world map opens, switch the displayed map to the
-- super-tracked quest's zone so the player doesn't have to navigate. Opt-in
-- via db.profile.general.autoZoomToTrackedQuest (default OFF).
--
-- Guards:
--   • No super-tracked quest (or no waypoint for it) → no-op.
--   • Already on the right map → no-op (no SetMapID storm).
--   • Player on a taxi → no-op (they're actively flying somewhere; the
--     auto-switch would fight the taxi-map UX).

local _, ns = ...

local MA = ns:RegisterSubsystem("TrackerMapAutoSwitch", {})

local function enabled()
    local DB = ns:GetSubsystem("DB")
    return DB and DB.db.profile.general
           and DB.db.profile.general.autoZoomToTrackedQuest == true
end

local function trackedMapID()
    if not (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
            and C_QuestLog and C_QuestLog.GetNextWaypoint) then return nil end
    local qid = C_SuperTrack.GetSuperTrackedQuestID()
    if not qid or qid == 0 then return nil end
    local wm = C_QuestLog.GetNextWaypoint(qid)
    return wm
end

local function maybeSwitch()
    if not enabled() then return end
    if UnitOnTaxi and UnitOnTaxi("player") then return end

    local target = trackedMapID()
    if not target then return end

    if not (WorldMapFrame and WorldMapFrame.GetMapID
            and WorldMapFrame.SetMapID) then return end
    if WorldMapFrame:GetMapID() == target then return end
    WorldMapFrame:SetMapID(target)
end

function MA:OnEnable()
    if WorldMapFrame and WorldMapFrame.HookScript then
        WorldMapFrame:HookScript("OnShow", maybeSwitch)
    end
end
