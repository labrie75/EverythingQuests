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
