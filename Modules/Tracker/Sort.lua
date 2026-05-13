-- Modules/Tracker/Sort.lua
-- Sort comparators by mode. Sort.For(mode) returns a comparator usable with
-- table.sort. Distance mode is throttled by Tracker:Refresh, not here.

local _, ns = ...

local Sort = ns:RegisterSubsystem("TrackerSort", {})

local function cmpZone(a, b)
    return (a.zone or "~") < (b.zone or "~")
end

local function cmpStatus(a, b)
    if a.isComplete ~= b.isComplete then return a.isComplete end
    return (a.title or "") < (b.title or "")
end

local function cmpType(a, b)
    return (a.frequency or 0) > (b.frequency or 0)
end

local function cmpLevel(a, b)
    return (a.level or 0) < (b.level or 0)
end

local function cmpManual(orderMap)
    return function(a, b)
        return (orderMap[a.questID] or 99999) < (orderMap[b.questID] or 99999)
    end
end

function Sort.For(mode, orderMap)
    if mode == "zone"     then return cmpZone end
    if mode == "status"   then return cmpStatus end
    if mode == "type"     then return cmpType end
    if mode == "level"    then return cmpLevel end
    if mode == "manual"   then return cmpManual(orderMap or {}) end
    if mode == "distance" then return cmpZone end -- TODO: real distance sort
    return cmpZone
end
