-- Core/Util.lua
-- Shared helpers: color tokens, time formatting, money formatting, table ops.

local _, ns = ...

local Util = ns:RegisterSubsystem("Util", {})

-- Style tokens (the Everything-suite palette). SINGLE SOURCE OF TRUTH — wire
-- modules to these instead of re-declaring the literals (which had drifted:
-- two files shipped #6D0501 as {0.42,0.02,0.02}, a visibly purpler red).
-- The brand red is exactly #6D0501 = 109/255, 5/255, 1/255 = 0.427,0.020,0.004
-- (matches Core/DB.lua's borderColor default and Core/Dialog.lua).
Util.color = {
    optionsBg     = { 0.00,  0.00,  0.00,  0.95 },
    tabActive     = { 0.427, 0.020, 0.004, 1.00 },                      -- #6D0501
    tabInactive   = { 0.10,  0.10,  0.10,  0.85 },
    tabText       = { 1.00,  1.00,  1.00,  1.00 },
    brandRed      = { 0.427, 0.020, 0.004, 1.00 },                      -- #6D0501 canonical
    headerRed     = { 0.427, 0.020, 0.004, 1.00 },                      -- = brandRed (section headers)
    buttonYellow  = { 0.92,  0.72,  0.02,  1.00 },                      -- #EBB706
    statYellow    = { 0.92,  0.72,  0.02,  1.00 },                      -- = buttonYellow
    muted         = { 0.70,  0.70,  0.70,  1.00 },                      -- secondary label grey
    dim           = { 0.50,  0.50,  0.50,  1.00 },                      -- tertiary / disabled grey
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

-- Format an elapsed duration as "1h 47m" / "47m" / "30s" (e.g. play-session
-- length). Unlike FmtTimeShort this keeps the minutes alongside the hours.
function Util.FmtDuration(secs)
    secs = math.max(0, math.floor(secs or 0))
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h > 0 then return ("%dh %dm"):format(h, m) end
    if m > 0 then return ("%dm"):format(m) end
    return ("%ds"):format(secs)
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

-- ── Objective "X/Y" progress colorization (single source of truth) ───
-- The tracker's quest blocks (Blocks.lua) and the World Quests section
-- (Tracker/Events.lua) both color the have/need count identically: red at
-- zero, amber in progress, green when complete. This lived as two hand-synced
-- copies — and the Events one allocated a fresh gsub closure per objective
-- line. One implementation here, with a hoisted replacer that captures no
-- upvalues (reused, so no per-call closure), keeps both surfaces identical
-- and allocation-light on the render hot path.
local function progressRepl(have, need)
    local h, n = tonumber(have), tonumber(need)
    if not (h and n) then return have .. "/" .. need end
    local color
    if h == 0    then color = "|cffff5050"
    elseif h < n then color = "|cffeeaa00"
    else              color = "|cff44ff44"
    end
    return color .. have .. "/" .. need .. "|r"
end

function Util.ColorizeProgress(text)
    if not text or text == "" then return text end
    return (text:gsub("(%d+)%s*/%s*(%d+)", progressRepl))
end

-- Strip a leading "X/Y" count from RAW objective text (used when the user
-- hides objective numbers). Leading-anchored, and meant to run BEFORE any
-- color escapes are added so it can never eat into a |cAARRGGBB..|r code.
function Util.StripLeadingCount(text)
    return (text:gsub("^%s*%d+%s*/%s*%d+%s*", ""))
end

-- ── Quest title resolver (single source of truth) ────────────────────
-- Quest titles come from different APIs depending on quest kind and load
-- state: C_QuestLog.GetTitleForQuestID covers normal log quests, while
-- QuestUtils_GetQuestName and C_TaskQuest.GetQuestInfoByQuestID fill in
-- world/task quests and quests whose data is still streaming in. Several call
-- sites only consulted GetTitleForQuestID and showed a bare "Quest #<id>" for
-- everything else — this is the shared resolver they should all use.
--   withNumberFallback truthy -> returns "Quest #<id>" when nothing resolves
--   withNumberFallback falsy  -> returns nil (so the caller can chain its own
--                                fallback, e.g. a curated item.name)
function Util.QuestTitle(questID, withNumberFallback)
    if questID then
        if C_QuestLog and C_QuestLog.GetTitleForQuestID then
            local t = C_QuestLog.GetTitleForQuestID(questID)
            if t and t ~= "" then return t end
        end
        if QuestUtils_GetQuestName then
            local n = QuestUtils_GetQuestName(questID)
            if n and n ~= "" then return n end
        end
        if C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID then
            local t = C_TaskQuest.GetQuestInfoByQuestID(questID)
            if t and t ~= "" then return t end
        end
    end
    if withNumberFallback then return "Quest #" .. tostring(questID) end
    return nil
end

-- ── Frame-pool acquire (single source of truth) ──────────────────────
-- A dozen surfaces (Chain Guide, History, World Quests, and the tracker's
-- scenario / profession / event / endeavor sections, auto-complete and
-- auto-quest popups) keep a free-list `pool` of reusable frames plus an
-- `active` list of the ones currently shown, and re-acquire them every
-- render. The acquire half was copy-pasted identically: pop from the pool,
-- build a fresh one via factory(parent) on a miss, reparent, show, and
-- record it in `active`. This is that half, lifted to one place. The release
-- half stays per-module (each surface resets different fields on its rows).
function Util.AcquirePooled(pool, active, parent, factory)
    local f = tremove(pool)
    if not f then f = factory(parent) end
    f:SetParent(parent)
    f:Show()
    active[#active + 1] = f
    return f
end

ns.Util = Util
