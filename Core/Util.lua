-- Core/Util.lua
-- Shared helpers: color tokens, time formatting, money formatting, table ops.

local _, ns = ...

local Util = ns:RegisterSubsystem("Util", {})

-- Style tokens (options-UI palette). Reference: project_eq_style memory.
Util.color = {
    optionsBg     = { 0.00, 0.00, 0.00, 0.95 },
    tabActive     = { 0.43, 0.02, 0.00, 1.00 },                         -- #6D0501
    tabText       = { 1.00, 1.00, 1.00, 1.00 },
    headerRed     = { 0.43, 0.02, 0.00, 1.00 },
    buttonYellow  = { 0.92, 0.72, 0.02, 1.00 },                         -- #EBB706
    statYellow    = { 0.92, 0.72, 0.02, 1.00 },
}

-- Format an integer count as "1.2k" / "12.3k" / "1.2m" once it gets big.
function Util.AbbrevNumber(n)
    if not n then return "" end
    if n >= 1000000 then return ("%.1fm"):format(n / 1000000) end
    if n >= 10000   then return ("%.1fk"):format(n / 1000) end
    return tostring(n)
end

-- Format seconds-remaining as "12m" / "3h" / "2d".
function Util.FmtTimeShort(secs)
    if not secs or secs <= 0 then return "" end
    if secs < 3600  then return ("%dm"):format(secs / 60) end
    if secs < 86400 then return ("%dh"):format(secs / 3600) end
    return ("%dd"):format(secs / 86400)
end

-- ── World-quest time-left (single source of truth) ───────────────────
-- All WQ surfaces (map pin, zone list, tooltip) take minutes from
-- C_TaskQuest.GetQuestTimeLeftMinutes and MUST agree on urgency color and
-- formatting — otherwise the same quest looks differently urgent depending
-- on where you read it. One ramp here; callers pick Short (compact pin
-- label) or Long (roomy list/tooltip) for text.

-- Urgency color by minutes remaining: <30 red, <2h orange, <12h yellow,
-- else green. nil / expired → a distinct red.
function Util.WQTimeColor(mins)
    if not mins or mins <= 0 then return 1.00, 0.10, 0.10 end
    if mins < 30  then return 1.00, 0.25, 0.25 end
    if mins < 120 then return 1.00, 0.65, 0.10 end
    if mins < 720 then return 1.00, 1.00, 0.40 end
    return 0.50, 1.00, 0.50
end

-- Compact, for the space-constrained map-pin label: "" / "45m" / "3h" / "2d".
function Util.WQTimeShort(mins)
    if not mins or mins <= 0 then return "" end
    if mins < 60   then return ("%dm"):format(mins) end
    if mins < 1440 then return ("%dh"):format(math.floor(mins / 60)) end
    return ("%dd"):format(math.floor(mins / 1440))
end

-- Verbose, for the zone list and tooltip: "Expired" / "45m" / "3h 5m".
function Util.WQTimeLong(mins)
    if not mins or mins <= 0 then return "Expired" end
    local h = math.floor(mins / 60)
    local m = mins - h * 60
    if h > 0 then return ("%dh %dm"):format(h, m) end
    return ("%dm"):format(m)
end

-- RGB hex string -> {r,g,b,a}. "6D0501" or "#6D0501".
function Util.HexToRGBA(hex, alpha)
    hex = hex:gsub("^#", "")
    local r = tonumber(hex:sub(1, 2), 16) / 255
    local g = tonumber(hex:sub(3, 4), 16) / 255
    local b = tonumber(hex:sub(5, 6), 16) / 255
    return r, g, b, alpha or 1
end

-- Sanitize a saved manual-order map ({ [questID] = ordinal }) loaded from
-- SavedVariables. A corrupt non-numeric ordinal would crash the tracker's
-- manual-sort comparator (it does `number < value`); stale / duplicate /
-- gappy ordinals are merely untidy. Returns a FRESH compact map: only
-- numeric questID -> numeric ordinal entries survive, re-sequenced 1..N
-- preserving their relative order. Cold path (login only), so the small
-- temp tables are fine; GC-neutral at runtime.
function Util.ReconcileOrder(orderMap)
    if type(orderMap) ~= "table" then return {} end
    local list = {}
    for qid, ord in pairs(orderMap) do
        if type(qid) == "number" and type(ord) == "number" then
            list[#list + 1] = { qid, ord }
        end
    end
    table.sort(list, function(a, b) return a[2] < b[2] end)
    local clean = {}
    for i = 1, #list do clean[list[i][1]] = i end
    return clean
end

ns.Util = Util
