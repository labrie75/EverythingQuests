-- Core/Events.lua
-- Single event dispatcher. Modules subscribe via Events:On("EVENT_NAME", handler).
-- Avoids each module owning its own frame and re-registering the same events.

local _, ns = ...

local Events = ns:RegisterSubsystem("Events", {})
local frame = CreateFrame("Frame")
local listeners = {}

function Events:On(event, fn)
    local list = listeners[event]
    if not list then
        list = {}
        listeners[event] = list
        frame:RegisterEvent(event)
    end
    list[#list + 1] = fn
end

function Events:Off(event, fn)
    local list = listeners[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == fn then tremove(list, i) end
    end
    if #list == 0 then
        listeners[event] = nil
        frame:UnregisterEvent(event)
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = listeners[event]
    if not list then return end
    for i = 1, #list do list[i](event, ...) end
end)

-- ── Combat-deferral primitive ─────────────────────────────────────────
-- Protected / secure-frame operations (creating, reparenting or
-- reanchoring a SecureActionButton, setting secure attributes) are
-- FORBIDDEN while InCombatLockdown(). RunWhenOutOfCombat runs fn now when
-- safe, otherwise coalesces it by key (latest wins — a button reanchored
-- 50x mid-fight replays only once) and flushes on PLAYER_REGEN_ENABLED.
-- Shared so KT-style usable item buttons (and anything else) don't each
-- reinvent the flag+replay. Allocation-free when idle and on flush
-- (reused scratch); a throwing deferred op can't eat the rest of the queue.
local _deferred   = {}
local _flushKeys  = {}
local _flushArmed = false

local function flushDeferred()
    local n = 0
    for key in pairs(_deferred) do n = n + 1; _flushKeys[n] = key end
    for i = 1, n do
        local key = _flushKeys[i]
        local fn  = _deferred[key]
        _deferred[key]  = nil
        _flushKeys[i]   = nil
        if fn then
            local ok, err = pcall(fn)
            if not ok then geterrorhandler()(err) end
        end
    end
end

function Events:InCombat()
    return InCombatLockdown() and true or false
end

-- key: any value identifying this logical op (repeats during one combat
-- coalesce to the latest). fn: zero-arg closure doing the protected work.
-- Returns true if it ran immediately, false if deferred to combat-end.
function Events:RunWhenOutOfCombat(key, fn)
    if not InCombatLockdown() then
        fn()
        return true
    end
    _deferred[key] = fn
    if not _flushArmed then
        _flushArmed = true
        self:On("PLAYER_REGEN_ENABLED", flushDeferred)
    end
    return false
end

-- ── Leading-edge throttle with trailing coalesce ──────────────────────
-- Events:Throttle(key, delay, fn) — fires fn() immediately if no window
-- is open for this key, otherwise coalesces into ONE trailing call when
-- the window expires. Leading-edge response + per-window collapse is the
-- right shape for "update on each event but never more than every Nms"
-- (visible reactivity without bursty re-renders).
--
-- Compare with the trailing-only debounce idiom (one timer, drop later
-- calls, run once at the end): that's strictly less responsive — useful
-- when the leading fire would itself be wasted work (e.g. a render that
-- depends on state still being mutated). Pick the right one per site.
--
-- Allocation: per-key scratch + tick closure are memoized once and reused
-- forever, so subsequent Throttle(key, ...) calls allocate nothing. Pass
-- a HOISTED or memoized `fn` (not a fresh closure each call) from hot
-- paths or you'll defeat the win.
--
-- Returns true if it ran immediately (leading), false if coalesced.
local _throttle = {}                 -- [key] = { armed, retry, fn, delay }
local _tickFns  = {}                 -- [key] = memoized C_Timer.After closure

local function throttleTick(key)
    local t = _throttle[key]
    if not t then return end
    if t.retry then
        local rfn = t.fn
        t.retry = false
        t.fn    = nil
        if rfn then
            -- Re-arm BEFORE firing so any Throttle(same key) inside rfn
            -- correctly coalesces into the next window instead of seeing
            -- an unarmed slot and firing a second leading call.
            C_Timer.After(t.delay, _tickFns[key])
            rfn()
        else
            t.armed = false
        end
    else
        t.armed = false
    end
end

local function getTickFn(key)
    local fn = _tickFns[key]
    if not fn then
        fn = function() throttleTick(key) end
        _tickFns[key] = fn
    end
    return fn
end

function Events:Throttle(key, delay, fn)
    local t = _throttle[key]
    if t and t.armed then
        t.retry = true
        t.fn    = fn                 -- latest call wins for the trailing fire
        t.delay = delay
        return false
    end

    if not t then t = {}; _throttle[key] = t end
    t.armed = true
    t.retry = false
    t.fn    = nil
    t.delay = delay

    fn()                             -- leading-edge fire
    C_Timer.After(delay, getTickFn(key))
    return true
end

-- ── Trailing-edge debounce (coalesce a burst into ONE delayed call) ────
-- Events:Debounce(key, delay, fn) — schedules fn() to run `delay` seconds
-- after the FIRST call that opened the window. Further Debounce(key, ...)
-- calls while the window is open are coalesced: they do NOT reschedule (so
-- the call fires at a bounded latency, not "delay after the LAST call"), but
-- the latest fn wins for the trailing fire. This is the "one timer, drop the
-- reschedules, run once at the end" idiom the modules previously hand-rolled
-- with a `pending` boolean + an inline C_Timer.After closure.
--
-- Contrast Events:Throttle (leading-edge + trailing coalesce): Debounce never
-- fires on the leading edge — reach for it when the leading call would be
-- wasted work (a render that depends on state still being mutated by the rest
-- of the burst). The trailing fn is pcall-guarded so a throw surfaces via the
-- error handler instead of eating later flushes.
--
-- Allocation: the per-key tick closure is memoized once and reused, so a
-- steady-state burst that passes a HOISTED fn allocates nothing.
local _debounce   = {}               -- [key] = { armed, fn }
local _debTickFns = {}               -- [key] = memoized C_Timer.After closure

local function debounceTick(key)
    local d = _debounce[key]
    if not d then return end
    local fn = d.fn
    d.armed = false
    d.fn    = nil
    if fn then
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
end

local function getDebTickFn(key)
    local fn = _debTickFns[key]
    if not fn then
        fn = function() debounceTick(key) end
        _debTickFns[key] = fn
    end
    return fn
end

-- Returns true if this call opened a new window (scheduled the timer), false
-- if it coalesced into an already-open one.
function Events:Debounce(key, delay, fn)
    local d = _debounce[key]
    if d and d.armed then
        d.fn = fn                    -- coalesce: latest fn wins, no reschedule
        return false
    end
    if not d then d = {}; _debounce[key] = d end
    d.armed = true
    d.fn    = fn
    C_Timer.After(delay, getDebTickFn(key))
    return true
end

ns.Events = Events
