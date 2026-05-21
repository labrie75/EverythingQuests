-- Core/Profiler.lua
-- Opt-in CPU / memory profiler for hot-path investigation. Wrap any code
-- region with:
--     Profiler:Start("tag")  ... work ...  Profiler:Stop("tag")
-- Stats accumulate across many Start/Stop pairs on the same tag and are
-- printed via `/eqs profile show`.
--
-- CPU timing is always recorded (debugprofilestop, microsecond resolution,
-- effectively free). Memory delta is recorded only when memory mode is
-- enabled via `/eqs profile mem on`; it forces collectgarbage("collect")
-- at the boundaries so the delta reflects actual allocation rather than
-- pending-to-be-collected garbage. That forced collection is EXPENSIVE —
-- leave memory mode off during normal play; toggle it on only while
-- investigating a regression.
--
-- Caveat: collectgarbage("count") is process-global (all Lua memory, not
-- per-addon). Synchronous hot-path tags reflect EQ's own allocation
-- accurately; async / multi-frame tags can be polluted by other addons
-- allocating in the same window.

local _, ns = ...

local Profiler = ns:RegisterSubsystem("Profiler", {})

Profiler.stats   = {}                -- [tag] = { cpuTotal, cpuCount, cpuMax, memTotal, memCount, memMax }
Profiler.memMode = false             -- toggled by `/eqs profile mem on|off`

-- Per-tag scratch for Start→Stop handoff. Allocated once per tag, reused.
local _active = {}                   -- [tag] = { cpu = startMs, mem = startKB or nil }

local function getActive(tag)
    local a = _active[tag]
    if not a then a = {}; _active[tag] = a end
    return a
end

local function getStats(tag)
    local s = Profiler.stats[tag]
    if not s then
        s = { cpuTotal = 0, cpuCount = 0, cpuMax = 0,
              memTotal = 0, memCount = 0, memMax = 0 }
        Profiler.stats[tag] = s
    end
    return s
end

function Profiler:SetMemoryMode(on)
    self.memMode = on and true or false
end

function Profiler:Start(tag)
    local a = getActive(tag)
    if self.memMode then
        collectgarbage("collect")
        a.mem = collectgarbage("count")
    else
        a.mem = nil
    end
    a.cpu = debugprofilestop()
end

function Profiler:Stop(tag)
    local a = _active[tag]
    if not (a and a.cpu) then return end
    local cpuDelta = debugprofilestop() - a.cpu
    local memDelta
    if a.mem then
        collectgarbage("collect")
        memDelta = collectgarbage("count") - a.mem
    end
    a.cpu = nil
    a.mem = nil

    local s = getStats(tag)
    s.cpuTotal = s.cpuTotal + cpuDelta
    s.cpuCount = s.cpuCount + 1
    if cpuDelta > s.cpuMax then s.cpuMax = cpuDelta end
    if memDelta then
        s.memTotal = s.memTotal + memDelta
        s.memCount = s.memCount + 1
        if math.abs(memDelta) > math.abs(s.memMax) then s.memMax = memDelta end
    end
end

function Profiler:Reset()
    wipe(self.stats)
    -- Intentionally do NOT wipe _active — an in-flight Start/Stop pair on
    -- another thread of control would lose its start sample and silently
    -- be ignored by Stop (the `a.cpu` nil-check).
end

-- ── Auto-instrument: wrap subsystem methods in place ──────────────────
-- `Profiler:Wrap("Tracker", "Render")` replaces Tracker.Render with a
-- function that does Start("Tracker:Render"), calls the original, then
-- Stop("Tracker:Render"). Idempotent — wrapping the same method twice is
-- a no-op. AutoInstrument(true) wraps everything in HOT_PATHS at once;
-- AutoInstrument(false) restores every original.
--
-- The `done(original(...))` trick passes through arbitrary return values
-- (including nils) intact, which `{ original(...) }` + `unpack` would
-- mangle. If the wrapped method errors, Stop is skipped and the error
-- bubbles unchanged; the next Start on that tag simply overwrites the
-- abandoned sample, so the profiler self-heals without try/catch noise.

Profiler._wrapped = {}                   -- [key] = { tbl, method, original }

local function tableHasMethod(tbl, name)
    return tbl and type(tbl[name]) == "function"
end

function Profiler:Wrap(subsystemName, methodName)
    local tbl = ns:GetSubsystem(subsystemName)
    if not tableHasMethod(tbl, methodName) then return false end

    local key = subsystemName .. "." .. methodName
    if self._wrapped[key] then return true end                              -- already wrapped

    local original = tbl[methodName]
    local tag      = subsystemName .. ":" .. methodName
    local prof     = self
    tbl[methodName] = function(...)
        prof:Start(tag)
        local function done(...) prof:Stop(tag); return ... end
        return done(original(...))
    end
    self._wrapped[key] = { tbl = tbl, method = methodName, original = original }
    return true
end

function Profiler:Unwrap(subsystemName, methodName)
    local key = subsystemName .. "." .. methodName
    local rec = self._wrapped[key]
    if not rec then return false end
    rec.tbl[rec.method] = rec.original
    self._wrapped[key]  = nil
    return true
end

-- Curated list of subsystem methods worth measuring. Picked for being
-- on a frequently-traveled rebuild path (Tracker render, WQ refresh,
-- Chain Guide render, History query/render). Refreshing this list is
-- the right knob to expose more or fewer measurements at once; manual
-- Profiler:Start/Stop pairs in code still work alongside this.
Profiler.HOT_PATHS = {
    { "Tracker",         "Render"        },
    { "Tracker",         "Refresh"       },
    { "TrackerBlocks",   "RenderQuest"   },
    { "TrackerBlocks",   "Sweep"         },
    { "TrackerScenario", "Refresh"       },
    { "WQSummary",       "Refresh"       },
    { "WQWorldMap",      "Refresh"       },
    { "WQZoneMap",       "Refresh"       },
    { "ChainGuide",      "RenderCurrent" },
    { "ChainGuideView",  "Render"        },
    { "HistoryFrame",    "Render"        },
    { "History",         "Query"         },
    { "History",         "Totals"        },
}

function Profiler:AutoInstrument(on)
    if on then
        local wrapped, missing = 0, 0
        for _, p in ipairs(self.HOT_PATHS) do
            if self:Wrap(p[1], p[2]) then wrapped = wrapped + 1 else missing = missing + 1 end
        end
        return wrapped, missing
    else
        local unwrapped = 0
        -- Snapshot keys first; Unwrap mutates _wrapped during iteration.
        local keys = {}
        for k in pairs(self._wrapped) do keys[#keys + 1] = k end
        for _, k in ipairs(keys) do
            local rec = self._wrapped[k]
            if rec then
                rec.tbl[rec.method] = rec.original
                self._wrapped[k]    = nil
                unwrapped = unwrapped + 1
            end
        end
        return unwrapped, 0
    end
end

function Profiler:IsAutoInstrumented()
    return next(self._wrapped) ~= nil
end

function Profiler:ListWrapped()
    local out = {}
    for k in pairs(self._wrapped) do out[#out + 1] = k end
    table.sort(out)
    return out
end

function Profiler:Show()
    local title = "|cffEBB706Everything Quests Profile|r"
    print(title .. (self.memMode and " (memory mode ON)" or ""))

    -- Sort by total CPU descending so the biggest costs show first.
    local keys = {}
    for tag in pairs(self.stats) do keys[#keys + 1] = tag end
    if #keys == 0 then
        print("  (no samples — wrap code with Profiler:Start/Stop, then run this again)")
        return
    end
    table.sort(keys, function(a, b)
        return self.stats[a].cpuTotal > self.stats[b].cpuTotal
    end)

    for _, tag in ipairs(keys) do
        local s = self.stats[tag]
        local avgCpu = s.cpuCount > 0 and (s.cpuTotal / s.cpuCount) or 0
        local line = ("  %s — n=%d cpu avg=%.2fms max=%.2fms total=%.2fms"):format(
            tag, s.cpuCount, avgCpu, s.cpuMax, s.cpuTotal)
        if s.memCount > 0 then
            local avgMem = s.memTotal / s.memCount
            line = line .. ("  | mem avg=%+.2fKB max=%+.2fKB"):format(avgMem, s.memMax)
        end
        print(line)
    end
end

-- ── In-game memory-hog meter ──────────────────────────────────────────
-- A small on-screen widget that reports EQ's addon memory + the rolling
-- kB/s allocation rate, sampled once per second. Catches allocation
-- spikes the moment they happen (open a map, accept a quest) so you can
-- correlate them with player actions. Off by default — toggle via
-- `/eqs profile memhog`.
--
-- UpdateAddOnMemoryUsage is documented as relatively expensive; sampling
-- once per second is fine, per-frame would not be. The frame is hidden
-- when off, so OnUpdate doesn't fire and the meter costs nothing.

local MEMHOG_INTERVAL_S = 1.0          -- seconds between samples
local MEMHOG_BUFFER_N   = 5            -- rolling samples for the kB/s average

Profiler.memhog = {
    active      = false,
    frame       = nil,
    label       = nil,
    lastMem     = 0,                   -- KB at last sample
    lastTime    = 0,                   -- GetTime() at last sample
    accumulated = 0,                   -- OnUpdate elapsed-sum accumulator
    buf         = {},                  -- ring of recent kB/s samples
    bufHead     = 1,                   -- next write index (1-based)
    bufLen      = 0,                   -- entries valid in `buf` (until ring fills)
}

local _UpdateMem = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or UpdateAddOnMemoryUsage
local _GetMem    = (C_AddOns and C_AddOns.GetAddOnMemoryUsage)    or GetAddOnMemoryUsage

local function memhogTick(_, elapsed)
    local mh = Profiler.memhog
    mh.accumulated = mh.accumulated + elapsed
    if mh.accumulated < MEMHOG_INTERVAL_S then return end
    mh.accumulated = 0

    if not (_UpdateMem and _GetMem and mh.label) then return end
    _UpdateMem()
    local mem = _GetMem("EverythingQuests") or 0
    local now = GetTime()
    local dt  = now - mh.lastTime
    if mh.lastTime > 0 and dt > 0 then
        local rate = (mem - mh.lastMem) / dt
        mh.buf[mh.bufHead] = rate
        mh.bufHead = (mh.bufHead % MEMHOG_BUFFER_N) + 1
        if mh.bufLen < MEMHOG_BUFFER_N then mh.bufLen = mh.bufLen + 1 end

        local sum = 0
        for i = 1, mh.bufLen do sum = sum + (mh.buf[i] or 0) end
        local avg = sum / mh.bufLen
        -- IDE can't infer the deferred FontString assignment in
        -- ensureMemHogFrame; the nil-guard above this loop already runs.
        local label = mh.label                                                  ---@type any
        if mem >= 1024 then
            label:SetText(("EQ %+.1f kB/s | %.2f MB"):format(avg, mem / 1024))
        else
            label:SetText(("EQ %+.1f kB/s | %.0f KB"):format(avg, mem))
        end
    end
    mh.lastMem  = mem
    mh.lastTime = now
end

local function ensureMemHogFrame()
    local mh = Profiler.memhog
    if mh.frame then return mh.frame end

    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(190, 26)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)

    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.80)

    mh.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mh.label:SetPoint("CENTER")
    mh.label:SetText("EQ memhog: starting...")

    f:SetScript("OnUpdate", memhogTick)
    mh.frame = f
    return f
end

function Profiler:StartMemHog()
    if self.memhog.active then return end
    local f = ensureMemHogFrame()
    if not f then return end                                                -- defensive; ensureMemHogFrame always succeeds in practice
    -- Reset state so the very first sample is "now" (no spurious huge
    -- delta on the first tick).
    if _UpdateMem and _GetMem then
        _UpdateMem()
        self.memhog.lastMem = _GetMem("EverythingQuests") or 0
    end
    self.memhog.lastTime    = GetTime()
    self.memhog.accumulated = 0
    self.memhog.bufLen      = 0
    self.memhog.bufHead     = 1
    f:Show()
    self.memhog.active = true
end

function Profiler:StopMemHog()
    if not self.memhog.active then return end
    local f = self.memhog.frame
    if f then f:Hide() end
    self.memhog.active = false
end

function Profiler:ToggleMemHog()
    if self.memhog.active then self:StopMemHog() else self:StartMemHog() end
end
