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

ns.Events = Events
