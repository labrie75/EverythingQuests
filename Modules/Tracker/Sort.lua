-- Modules/Tracker/Sort.lua
-- Sort comparators by mode. Sort.For(mode) returns a comparator usable with
-- table.sort. Distance mode is throttled by Tracker:Refresh, not here.

local _, ns = ...

local Sort = ns:RegisterSubsystem("TrackerSort", {})

-- Final tiebreak shared by every comparator. Without a unique backstop, two
-- quests with an equal primary key (same zone / frequency / level / distance)
-- leave table.sort free to order them arbitrarily, so they visibly shuffle
-- between refreshes. Title gives a friendly alphabetical secondary order;
-- questID is the unique backstop that guarantees a TOTAL, stable ordering.
-- Static + allocation-free so it stays safe to call inside table.sort.
local function byTitleThenID(a, b)
    local ta, tb = a.title or "", b.title or ""
    if ta ~= tb then return ta < tb end
    return (a.questID or 0) < (b.questID or 0)
end

local function cmpZone(a, b)
    local za, zb = a.zone or "~", b.zone or "~"
    if za ~= zb then return za < zb end
    return byTitleThenID(a, b)
end

local function cmpStatus(a, b)
    if a.isComplete ~= b.isComplete then return a.isComplete end
    return byTitleThenID(a, b)
end

local function cmpType(a, b)
    local fa, fb = a.frequency or 0, b.frequency or 0
    if fa ~= fb then return fa > fb end
    return byTitleThenID(a, b)
end

local function cmpLevel(a, b)
    local la, lb = a.level or 0, b.level or 0
    if la ~= lb then return la < lb end
    return byTitleThenID(a, b)
end

-- Recently-added mode: newest firstSeen first, then title. q.firstSeen rides on
-- every cache record (Core/Cache.lua); a 0 means "present at login" (see the
-- baseline there), so those sink together and fall to the title tiebreak.
-- Static + allocation-free like the others.
local function cmpRecent(a, b)
    local fa, fb = a.firstSeen or 0, b.firstSeen or 0
    if fa ~= fb then return fa > fb end
    return byTitleThenID(a, b)
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

-- Distance mode mirrors the manual pattern exactly: a module-scope distKey
-- ref ([questID] = squared distance) is swapped in by Sort.SetDistances right
-- before the sort, so cmpDistance stays a single static, allocation-free
-- function that NEVER calls a C API (the O(n log n) comparator must not — the
-- distances are harvested once per render in Tracker:_UpdateDistanceSort).
--
-- INF sinks any quest with no resolvable distance (off-continent, no POI yet,
-- world/warband quests the client can't place, or the API missing entirely)
-- to the bottom, where the zone tiebreak orders them among themselves. The
-- comparator's strict-weak-ordering safety RELIES on distKey containing only
-- finite numbers or INF — never NaN (NaN ~= NaN would break table.sort with
-- "invalid order function"). _UpdateDistanceSort guarantees this by filtering
-- with `distSq == distSq` before storing. Two INF entries compare equal
-- (INF ~= INF is false), so they fall through to the deterministic zone
-- tiebreak rather than ever evaluating INF < INF.
local INF = math.huge
local distKey = EMPTY
local function cmpDistance(a, b)
    local da = distKey[a.questID] or INF
    local db = distKey[b.questID] or INF
    if da ~= db then return da < db end
    local za, zb = a.zone or "~", b.zone or "~"
    if za ~= zb then return za < zb end
    return byTitleThenID(a, b)
end

-- Swap in the per-render distance map (or clear to EMPTY). Called from
-- Tracker:_UpdateDistanceSort right before the sort, mirroring the activeOrder
-- swap. Passing nil releases the reference (used when not in distance mode or
-- the API is unavailable), so cmpDistance degrades to a pure zone sort.
function Sort.SetDistances(map)
    distKey = map or EMPTY
end

function Sort.For(mode, orderMap)
    if mode == "zone"     then return cmpZone end
    if mode == "status"   then return cmpStatus end
    if mode == "type"     then return cmpType end
    if mode == "level"    then return cmpLevel end
    if mode == "recent"   then return cmpRecent end
    if mode == "manual"   then activeOrder = orderMap or EMPTY; return cmpManual end
    if mode == "distance" then return cmpDistance end
    return cmpZone
end
