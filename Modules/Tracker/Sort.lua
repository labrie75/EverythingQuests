local _, ns = ...

local Sort = ns:RegisterSubsystem("TrackerSort", {})

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

local function cmpRecent(a, b)
    local fa, fb = a.firstSeen or 0, b.firstSeen or 0
    if fa ~= fb then return fa > fb end
    return byTitleThenID(a, b)
end

local EMPTY = {}
local activeOrder = EMPTY
local function cmpManual(a, b)
    return (activeOrder[a.questID] or 99999) < (activeOrder[b.questID] or 99999)
end

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
