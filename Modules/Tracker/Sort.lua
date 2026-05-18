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

-- Manual mode reads its order from this module-scope ref so the comparator
-- stays a single static function — Sort.For runs inside table.sort on every
-- tracker Render, so a per-call closure (or `or {}` table) would be steady
-- garbage in manual mode. Lua is single-threaded and table.sort runs to
-- completion synchronously right after Sort.For, so swapping the ref just
-- before the sort is safe (no re-entrancy). EMPTY is never mutated.
local EMPTY = {}
local activeOrder = EMPTY
local function cmpManual(a, b)
    return (activeOrder[a.questID] or 99999) < (activeOrder[b.questID] or 99999)
end

function Sort.For(mode, orderMap)
    if mode == "zone"     then return cmpZone end
    if mode == "status"   then return cmpStatus end
    if mode == "type"     then return cmpType end
    if mode == "level"    then return cmpLevel end
    if mode == "manual"   then activeOrder = orderMap or EMPTY; return cmpManual end
    if mode == "distance" then return cmpZone end -- TODO: real distance sort
    return cmpZone
end
