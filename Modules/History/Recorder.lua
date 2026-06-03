-- Modules/History/Recorder.lua
-- Quest history data layer. Records turn-ins on QUEST_TURNED_IN into a
-- single account-wide SavedVariable (`EverythingQuestsHistory`), tagged
-- with the recording character so cross-character views can pivot.
--
-- Entries use short field names to keep SV size down (a fully-cap'd 5000
-- entries is still under ~500 KB):
--     q = questID         (number)
--     t = epoch seconds   (server time; 0 means "unknown" — backfilled)
--     n = quest title     (cached at record-time; may be nil on backfill)
--     c = "Name-Realm"    (character that turned it in)
--     z = zone name       (player's zone at turn-in; nil on backfill)
--     k = classification  (Enum.QuestClassification; nil if unknown)
--
-- Retention: rolling window per the configured cap (default 5000). When
-- the array overflows, oldest entries are shifted out. 0 = unlimited.
--
-- Backfill is opt-in via the "Populate from past completions" button on
-- the History options tab. Backfilled entries carry t=0 so the UI can
-- show them as "(date unknown)".

local _, ns = ...

local R = ns:RegisterSubsystem("History", {})

-- Cached "Name-Realm" key for the current character. Realm names with
-- spaces (e.g. "Wyrmrest Accord") survive untouched — we don't strip them.
local _charKey
local function charKey()
    if _charKey then return _charKey end
    local name  = UnitName and UnitName("player") or "?"
    local realm = GetRealmName and GetRealmName() or "?"
    _charKey = name .. "-" .. realm
    return _charKey
end

local function ensureSV()
    _G.EverythingQuestsHistory = _G.EverythingQuestsHistory or {}
    local sv = _G.EverythingQuestsHistory
    sv.entries        = sv.entries        or {}
    sv.charBackfilled = sv.charBackfilled or {}
    -- All-source gold ledger: goldDaily[charKey][dayNumber] = copper EARNED
    -- that day (positive PLAYER_MONEY deltas only). Separate from the quest
    -- entries because it isn't tied to a quest; used by the Stats → Trends
    -- "Gold" metric. Not snapshotted into the history backups (it's
    -- regenerated forward from live play, never restored).
    sv.goldDaily      = sv.goldDaily      or {}
    return sv
end

-- ─── Safety net storage ────────────────────────────────────────────────
-- Backups live in their OWN top-level SavedVariable so a logical reset of
-- the main history table (a stray `EverythingQuestsHistory = {}`, or a
-- failed write that loads empty) can't take the safety copies with it. WoW
-- writes both into the same physical file, so this guards against logical
-- loss, not whole-file corruption. Registered in the .toc SavedVariables.
local MAX_SNAPSHOTS = 3
local function ensureBackupSV()
    _G.EverythingQuestsHistoryBackups = _G.EverythingQuestsHistoryBackups or {}
    local b = _G.EverythingQuestsHistoryBackups
    b.snapshots      = b.snapshots      or {}   -- newest first, capped at MAX_SNAPSHOTS
    b.lastKnownCount = b.lastKnownCount or 0     -- total entries at last non-empty save
    b.lastCounts     = b.lastCounts     or {}    -- [charKey] = entries that character had
    return b
end

-- Entries are flat scalar-only records; copy each into a fresh table so a
-- snapshot never shares table identity with the live history (a later wipe
-- or in-place mutation of the live data must not touch the backup).
local function copyEntries(src)
    local out = {}
    for i = 1, #src do
        local e = src[i]
        out[i] = { q = e.q, t = e.t, n = e.n, c = e.c, z = e.z, k = e.k, xp = e.xp, m = e.m }
    end
    return out
end

local function copySet(src)
    local out = {}
    if src then for k, v in pairs(src) do out[k] = v end end
    return out
end

-- Count entries belonging to one character (account-wide history pivots by c).
local function countForChar(entries, key)
    local n = 0
    for i = 1, #entries do
        if entries[i].c == key then n = n + 1 end
    end
    return n
end

local function enabled()
    local DB = ns:GetSubsystem("DB")
    return not DB or DB.db.profile.history.enabled ~= false
end

local function retention()
    local DB = ns:GetSubsystem("DB")
    local n = DB and DB.db.profile.history.retention
    return tonumber(n) or 5000                                            -- 0 = unlimited
end

function R:OnInitialize()
    self.sv = ensureSV()
    self.backups = ensureBackupSV()

    -- Data-loss guard: if history loaded empty (or THIS character's entries
    -- vanished) while a non-empty backup exists, restore before anything
    -- reads the data. The notice is surfaced in OnEnable (we aren't fully
    -- logged in yet). A deliberate Wipe clears the backups, so it can never
    -- be silently undone here.
    self._loadNotice = self:_guardOnLoad()

    -- Runtime "questID → latest timestamp" cache for fast lookups (chain
    -- guide tooltip calls this on hover). Built once at init, updated
    -- incrementally on Record / Backfill / Wipe so it never needs a full
    -- SV walk after warmup.
    self._completion = {}
    local entries = self.sv.entries
    for i = 1, #entries do
        self:_updateCompletion(entries[i].q, entries[i].t or 0)
    end
    -- Runtime "Blizzard told us no data exists" set. QUEST_DATA_LOAD_RESULT
    -- with success=false means the server has no data for this questID on
    -- this client (retired/internal/promotional IDs); requesting it again
    -- just wastes a slot in the throttled load burst. Session-scoped only:
    -- a /reload re-tries everything in case the player has logged into a
    -- character that does have access to those quests.
    self._giveUp = {}
end

-- Title resolver: the full multi-API fallback chain (GetTitleForQuestID ->
-- QuestUtils_GetQuestName -> C_TaskQuest, covering world quests, partially-
-- cached entries, and races where data loaded before the title promoted to
-- the lookup table) now lives in Core/Util.lua. Kept as a thin local + the
-- R._resolveTitle alias for the existing call sites / dev tooling. Returns
-- nil when every source comes up empty.
local function resolveTitle(qid)
    return ns.Util.QuestTitle(qid)
end
R._resolveTitle = resolveTitle                                                -- exposed for tests / dev tooling

function R:_updateCompletion(qid, t)
    if not qid then return end
    local cur = self._completion[qid]
    -- Latest real timestamp wins; a real time replaces a t=0 backfill;
    -- a t=0 backfill only fills if there's no entry at all.
    if not cur or (t > 0 and t > cur) or (cur == 0 and t > 0) then
        self._completion[qid] = t
    end
end

-- O(1) lookup for the Chain Guide tooltip and other cross-references.
-- Returns nil if the quest isn't in history, 0 if it's backfilled
-- (no date known), or a positive epoch if it has a real completion time.
function R:GetCompletionTime(questID)
    return self._completion and self._completion[questID]
end

function R:OnEnable()
    local Events = ns:GetSubsystem("Events")
    if not Events then return end
    Events:On("QUEST_TURNED_IN", function(_, questID, xpReward, moneyReward)
        if not enabled() then return end
        self:Record(questID, xpReward, moneyReward)
    end)

    -- All-source gold tracking. PLAYER_MONEY fires on any balance change; we
    -- diff GetMoney() against a runtime baseline and bank positive deltas
    -- (loot, vendor, quest rewards — everything) into the per-day ledger.
    -- The baseline is seeded from the CURRENT balance each session, so a
    -- /reload records nothing spurious and offline mail/AH changes are never
    -- attributed to a day we can't actually know.
    self._moneyBaseline = (GetMoney and GetMoney()) or 0
    Events:On("PLAYER_MONEY", function()
        self:RecordMoney()
    end)
    -- Async title-fill: whenever Blizzard returns data for a quest we
    -- asked about, look for any history entry missing its title and fill
    -- it in. Re-render is debounced so a batch of fills coalesces into
    -- one paint. success=false means the server has no data for this
    -- questID — mark it so we don't re-queue it on the next Open.
    Events:On("QUEST_DATA_LOAD_RESULT", function(_, questID, success)
        if success then
            self:_fillTitle(questID)
        elseif questID then
            self._giveUp[questID] = true
        end
    end)

    -- Persist a rolling backup at logout so a future empty/short load can be
    -- detected and restored. _snapshotToBackup never overwrites good data
    -- with an empty history, so the last good state always survives.
    Events:On("PLAYER_LOGOUT", function()
        self:_snapshotToBackup()
    end)

    -- If the load guard recovered data, tell the user once the login noise
    -- has settled (a silent restore would be as unsettling as the loss).
    if self._loadNotice then
        local msg = self._loadNotice
        self._loadNotice = nil
        C_Timer.After(5, function()
            print("|cffEBB706EQ History:|r " .. msg)
        end)
    end

    -- First time EQ ever sees a character (with recording on), backfill its
    -- past completions so an alt is never silently empty. One-shot per
    -- character; deferred so the quest-completion data is loaded first.
    C_Timer.After(8, function()
        if not enabled() then return end
        local key = charKey()
        if self.sv.charBackfilled[key] then return end          -- already backfilled
        if countForChar(self.sv.entries, key) > 0 then          -- already has live data
            self.sv.charBackfilled[key] = true
            return
        end
        local added = self:Backfill()                            -- sets charBackfilled[key]
        if added > 0 then
            self:RequestMissingTitles()
            print(("|cffEBB706EQ History:|r first time seeing |cffffffff%s|r — added %d past completion%s (no dates; future turn-ins are dated)."):format(
                key, added, added == 1 and "" or "s"))
        end
    end)
end

-- ─── Data-loss safety net ──────────────────────────────────────────────
-- Highest-entry-count snapshot (the safest to restore from), or nil.
function R:_bestSnapshot()
    local snaps = self.backups and self.backups.snapshots
    if not snaps then return nil end
    local best
    for i = 1, #snaps do
        local s = snaps[i]
        if s and s.entries and #s.entries > 0
           and (not best or #s.entries > #best.entries) then
            best = s
        end
    end
    return best
end

-- Restore the live history from a snapshot and rebuild the completion cache.
local function applySnapshot(self, snap)
    self.sv.entries        = copyEntries(snap.entries)
    self.sv.charBackfilled = copySet(snap.charBackfilled)
    self._completion = {}
    local entries = self.sv.entries
    for i = 1, #entries do
        self:_updateCompletion(entries[i].q, entries[i].t or 0)
    end
    return #entries
end

-- Run once on load (OnInitialize). Returns a notice string if it restored,
-- else nil. _completion is (re)built by the caller / applySnapshot.
function R:_guardOnLoad()
    local b = self.backups
    local entries = self.sv.entries
    local loaded = #entries
    local best = self:_bestSnapshot()
    if not best then return nil end                              -- nothing to restore from

    -- Full loss: we recorded a non-empty history before, it loaded empty.
    if (b.lastKnownCount or 0) > 0 and loaded == 0 then
        local n = applySnapshot(self, best)
        return ("Quest history loaded empty; restored a backup from %s (%d entries)."):format(
            date("%Y-%m-%d %H:%M", best.ts or 0), n)
    end

    -- Per-character loss: THIS character had entries last session but none
    -- now, and a backup that still contains them exists. Restore the whole
    -- account snapshot (it carries every character's data).
    local key = charKey()
    local hadBefore = (b.lastCounts and b.lastCounts[key]) or 0
    if hadBefore > 0
       and countForChar(entries, key) == 0
       and countForChar(best.entries, key) > 0 then
        local n = applySnapshot(self, best)
        return ("Quest history for %s was missing; restored a backup from %s (%d entries)."):format(
            key, date("%Y-%m-%d %H:%M", best.ts or 0), n)
    end

    return nil
end

-- Snapshot the live history into the rolling backup (called on logout).
-- NEVER snapshots an empty history and NEVER zeroes the known-counts when
-- empty — so if the data vanished mid-session, the prior non-empty counts +
-- snapshots survive and the next load detects the drop and restores.
function R:_snapshotToBackup()
    local b = self.backups
    if not b then return end
    local entries = self.sv.entries
    local n = #entries
    if n == 0 then return end                                    -- preserve prior good state

    b.lastKnownCount = n
    local counts = {}
    for i = 1, n do
        local c = entries[i].c
        if c then counts[c] = (counts[c] or 0) + 1 end
    end
    b.lastCounts = counts

    tinsert(b.snapshots, 1, {
        ts             = (GetServerTime and GetServerTime()) or time(),
        count          = n,
        entries        = copyEntries(entries),
        charBackfilled = copySet(self.sv.charBackfilled),
    })
    for i = #b.snapshots, MAX_SNAPSHOTS + 1, -1 do
        b.snapshots[i] = nil
    end
end

-- Manual restore (Options button): replace live history with the best
-- backup. Returns the count restored (0 if no backup exists).
function R:RestoreFromBackup()
    local best = self:_bestSnapshot()
    if not best then return 0 end
    return applySnapshot(self, best)
end

-- Best-backup summary for the Options UI: { count, ts } or nil.
function R:BackupInfo()
    local best = self:_bestSnapshot()
    if not best then return nil end
    return { count = #best.entries, ts = best.ts or 0 }
end

-- Look up the now-cached title for a quest and patch every history entry
-- that's missing one. Debounced re-render keeps a flood of QUEST_DATA_
-- LOAD_RESULT events from re-rendering the History window per fill.
-- Title lookup uses resolveTitle so it tries every available API, not just
-- the primary one — fixes a class of "data loaded but GetTitleForQuestID
-- still nil" races that otherwise leave entries blank forever.
function R:_fillTitle(questID)
    local title = resolveTitle(questID)
    if not title then return end
    local touched = false
    local entries = self.sv.entries
    for i = 1, #entries do
        local e = entries[i]
        if e.q == questID and (not e.n or e.n == "") then
            e.n = title
            touched = true
        end
    end
    if touched then
        -- Coalesce a flood of QUEST_DATA_LOAD_RESULT fills into one History
        -- re-render via the shared trailing-debounce primitive (Core/Events.lua).
        local Events = ns:GetSubsystem("Events")
        if Events and Events.Debounce then
            local thunk = self._rerenderThunk
            if not thunk then
                thunk = function()
                    local HF = ns:GetSubsystem("HistoryFrame")
                    if HF and HF.Render then HF:Render() end
                end
                self._rerenderThunk = thunk
            end
            Events:Debounce("eq.history.fillrender", 0.5, thunk)
        end
    end
end

-- Final sweep: walk every nil-name entry and try resolveTitle once more.
-- Catches data that arrived between requests (e.g. from QUEST_LOG_UPDATE
-- triggered by an unrelated quest action) but whose questIDs we never
-- explicitly waited on. Cheap (~O(N) scan, no allocations beyond the
-- render flag), and only fires when there's something to sweep.
function R:SweepTitles()
    local entries = self.sv.entries
    local touched = false
    for i = 1, #entries do
        local e = entries[i]
        if e.q and (not e.n or e.n == "") then
            local t = resolveTitle(e.q)
            if t then e.n = t; touched = true end
        end
    end
    if touched then
        local HF = ns:GetSubsystem("HistoryFrame")
        if HF and HF.Render then HF:Render() end
    end
    return touched
end

-- Title-load queue. Backfilled (and some long-ago) entries arrive with no
-- title because Blizzard hasn't cached the quest data on this client yet.
-- We ask the server to load each missing one — throttled to avoid a
-- spammy burst when a fresh backfill produces hundreds at once. The
-- responses flow back through QUEST_DATA_LOAD_RESULT → _fillTitle.
local _titleQueue = {}
local _titleTimer

function R:RequestMissingTitles()
    if not (C_QuestLog and C_QuestLog.RequestLoadQuestByID) then return 0 end
    -- Before queuing new requests, sweep with resolveTitle — many entries
    -- now have data in the client cache (loaded for unrelated reasons) and
    -- can be filled without spending a server round-trip slot.
    self:SweepTitles()
    wipe(_titleQueue)
    local seen = {}
    local entries = self.sv.entries
    for i = 1, #entries do
        local e = entries[i]
        if e.q and (not e.n or e.n == "")
           and not seen[e.q] and not self._giveUp[e.q] then
            seen[e.q] = true
            _titleQueue[#_titleQueue + 1] = e.q
        end
    end
    local n = #_titleQueue
    if n > 0 then self:_pumpTitles() end
    return n
end

-- Throttled batch loader. Burst rate was originally 25 per 0.25s (~100/s);
-- Blizzard's quest-data load API silently drops requests under that kind
-- of pressure, leaving entries unresolved forever. 10 per 0.3s (~33/s) is
-- well under any observed drop threshold and still drains 2-3K entries in
-- well under two minutes.
function R:_pumpTitles()
    if not (C_QuestLog and C_QuestLog.RequestLoadQuestByID) then return end
    local BATCH = 10
    local fired = 0
    while #_titleQueue > 0 and fired < BATCH do
        local qid = tremove(_titleQueue)
        C_QuestLog.RequestLoadQuestByID(qid)
        fired = fired + 1
    end
    if #_titleQueue > 0 then
        if not _titleTimer then
            _titleTimer = C_Timer.NewTimer(0.3, function()
                _titleTimer = nil
                self:_pumpTitles()
            end)
        end
    else
        -- Queue drained. Give the in-flight QUEST_DATA_LOAD_RESULT events
        -- a few seconds to land, then sweep one more time so any data
        -- that arrived for IDs we'd already burned through gets picked up.
        C_Timer.After(3, function() self:SweepTitles() end)
    end
end

function R:Record(questID, xpReward, moneyReward)
    if not questID then return end
    local entry = {
        q = questID,
        t = (GetServerTime and GetServerTime()) or time(),
        n = resolveTitle(questID),
        c = charKey(),
        z = (GetZoneText and GetZoneText()) or nil,
        k = (C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification
             and C_QuestInfoSystem.GetQuestClassification(questID))
            or (C_QuestLog and C_QuestLog.GetQuestClassification
                and C_QuestLog.GetQuestClassification(questID)) or nil,
    }
    -- Reward fields — added in the reward-tracking pass. Stored only when
    -- non-zero so SV stays compact and old/backfilled entries that lack
    -- this data simply don't have the keys.
    if xpReward    and xpReward    > 0 then entry.xp = xpReward    end
    if moneyReward and moneyReward > 0 then entry.m  = moneyReward end

    local entries = self.sv.entries
    entries[#entries + 1] = entry
    self:_updateCompletion(entry.q, entry.t)
    self:_enforceRetention()
end

-- All-source gold ledger. Banks positive PLAYER_MONEY deltas into
-- goldDaily[charKey][today]. Spending (negative delta) only re-baselines.
-- Days beyond the retention window are pruned once per new day so the table
-- stays bounded (a few hundred small ints per character at most).
local GOLD_RETENTION_DAYS = 400

function R:RecordMoney()
    if not GetMoney then return end
    local cur   = GetMoney()
    local delta = cur - (self._moneyBaseline or cur)
    self._moneyBaseline = cur
    if not enabled() then return end                  -- history off → don't bank
    if delta <= 0 then return end                     -- income only, not spending

    local key   = charKey()
    local today = math.floor(((GetServerTime and GetServerTime()) or time()) / 86400)
    local ledger = self.sv.goldDaily
    local days = ledger[key]
    if not days then days = {}; ledger[key] = days end

    local isNewDay = days[today] == nil
    days[today] = (days[today] or 0) + delta

    if isNewDay then
        local cutoff = today - GOLD_RETENTION_DAYS
        for d in pairs(days) do
            if d < cutoff then days[d] = nil end
        end
    end

    -- Live-refresh only while the user is actually watching the Trends view.
    local HF = ns:GetSubsystem("HistoryFrame")
    if HF and HF.frame and HF.frame:IsShown()
       and HF._activeTab == "totals" and HF._statsView == "trends" then
        HF:Render()
    end
end

-- Drop oldest entries when over the cap. Append-only writes keep oldest
-- at index 1, so we just shift the tail down.
function R:_enforceRetention()
    local cap = retention()
    if cap <= 0 then return end
    local entries = self.sv.entries
    local n = #entries
    if n <= cap then return end
    local drop = n - cap
    for i = 1, cap do
        entries[i] = entries[i + drop]
    end
    for i = cap + 1, n do
        entries[i] = nil
    end
end

-- Walk Blizzard's "all completed quests" API and record what we don't
-- already have for this character. Used by the manual "Populate from past
-- completions" button. Backfilled entries carry t=0; we never overwrite
-- a real recorded entry. Returns the count added.
function R:Backfill()
    local key = charKey()
    local got
    if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
        got = C_QuestLog.GetAllCompletedQuestIDs()
    end
    if not got then return 0 end

    -- Build a seen-set of this character's existing questIDs to avoid
    -- duplicates from a prior backfill or new turn-ins since.
    local seen = {}
    local entries = self.sv.entries
    for i = 1, #entries do
        local e = entries[i]
        if e.c == key then seen[e.q] = true end
    end

    local added = 0
    for i = 1, #got do
        local qid = got[i]
        if not seen[qid] then
            entries[#entries + 1] = {
                q = qid,
                t = 0,
                n = resolveTitle(qid),
                c = key,
            }
            self:_updateCompletion(qid, 0)
            added = added + 1
        end
    end
    self.sv.charBackfilled[key] = true
    self:_enforceRetention()
    return added
end

function R:IsBackfilled()
    return self.sv.charBackfilled[charKey()] == true
end

function R:Wipe()
    self.sv.entries        = {}
    self.sv.charBackfilled = {}
    self._completion       = {}
    -- A deliberate wipe must not be auto-undone by the load guard, so clear
    -- the safety backups too. (The guard keys off lastKnownCount/lastCounts,
    -- which we zero here.)
    if self.backups then
        self.backups.snapshots      = {}
        self.backups.lastKnownCount = 0
        self.backups.lastCounts     = {}
    end
end

function R:CurrentCharacter()
    return charKey()
end

-- Unique character keys present in history, sorted alphabetically.
function R:GetCharacters()
    local set = {}
    local entries = self.sv.entries
    for i = 1, #entries do set[entries[i].c] = true end
    local list = {}
    for k in pairs(set) do list[#list + 1] = k end
    table.sort(list)
    return list
end

-- Map Enum.QuestClassification → short bucket name. Anything not in the
-- table buckets as "other". Built once at file load; defensive against
-- builds where a particular Enum entry is missing.
local CLASS_BUCKET = {}
do
    local QC = Enum and Enum.QuestClassification or {}
    if QC.Campaign   then CLASS_BUCKET[QC.Campaign]   = "campaign"   end
    if QC.Questline  then CLASS_BUCKET[QC.Questline]  = "questline"  end
    if QC.Calling    then CLASS_BUCKET[QC.Calling]    = "calling"    end
    if QC.Recurring  then CLASS_BUCKET[QC.Recurring]  = "recurring"  end
    if QC.WorldQuest then CLASS_BUCKET[QC.WorldQuest] = "worldquest" end
end
local function bucketOf(k)
    return (k and CLASS_BUCKET[k]) or "other"
end

-- Filter shape (all fields optional):
--   search          : substring of title (case-insensitive)
--   char            : "Name-Realm" | "all" | nil
--   dateRange       : "all" | "today" | "7d" | "30d"
--   classification  : "all" | "campaign" | "questline" | "calling"
--                       | "recurring" | "worldquest" | "other"
--   hideBackfilled  : true to exclude entries with t == 0
--   sortBy          : "date" (default) | "name" | "type"
--   sortDir         : "desc" (default) | "asc"
-- Returns array of entries matching filter, sorted per sortBy/sortDir.
-- Default (date / desc) is newest-first. Undated (t == 0, backfilled) entries
-- have no real date, so they ALWAYS sink to the bottom regardless of
-- direction. Allocates one fresh result table per call (click-driven; not a
-- hot path).
--
-- Bucket display order for the "type" sort — mirrors the Type filter
-- dropdown in Modules/History/Frame.lua so the grouping reads the same.
local SORT_BUCKET_ORDER = {
    campaign = 1, questline = 2, calling = 3,
    recurring = 4, worldquest = 5, other = 6,
}
function R:Query(filter)
    local entries = self.sv.entries
    local out = {}

    local search = filter and filter.search
    if search and search ~= "" then search = search:lower() else search = nil end
    local wantChar = filter and filter.char
    if wantChar == "all" or wantChar == "" then wantChar = nil end
    local hideBackfilled = filter and filter.hideBackfilled and true or false
    local wantClass = filter and filter.classification
    if wantClass == "all" or wantClass == "" or wantClass == nil then wantClass = nil end

    -- Date range → min acceptable timestamp.
    local minTime = 0
    local dateRange = filter and filter.dateRange
    if dateRange and dateRange ~= "all" then
        local now = (GetServerTime and GetServerTime()) or time()
        if dateRange == "today" then
            minTime = math.floor(now / 86400) * 86400      -- UTC midnight today
        elseif dateRange == "7d" then
            minTime = now - 7  * 86400
        elseif dateRange == "30d" then
            minTime = now - 30 * 86400
        end
    end

    for i = #entries, 1, -1 do
        local e = entries[i]
        local ok = true
        if wantChar and e.c ~= wantChar then ok = false end
        if ok and search then
            local n = e.n
            if not (n and n:lower():find(search, 1, true)) then ok = false end
        end
        if ok and hideBackfilled and (not e.t or e.t == 0) then ok = false end
        if ok and minTime > 0 then
            if not e.t or e.t < minTime then ok = false end
        end
        if ok and wantClass then
            if bucketOf(e.k) ~= wantClass then ok = false end
        end
        if ok then out[#out + 1] = e end
    end

    -- Sort the result. `out` was collected newest-first (reverse insertion),
    -- but we now order it explicitly so the toolbar's Sort dropdown + caret
    -- control it. Undated entries (t == 0) always go last.
    local asc    = filter and filter.sortDir == "asc"
    local sortBy = filter and filter.sortBy or "date"
    if sortBy == "name" then
        table.sort(out, function(a, b)
            local na, nb = (a.n or ""):lower(), (b.n or ""):lower()
            if na ~= nb then
                if asc then return na < nb else return na > nb end
            end
            return (a.q or 0) < (b.q or 0)
        end)
    elseif sortBy == "type" then
        table.sort(out, function(a, b)
            local ba = SORT_BUCKET_ORDER[bucketOf(a.k)] or 99
            local bb = SORT_BUCKET_ORDER[bucketOf(b.k)] or 99
            if ba ~= bb then
                if asc then return ba < bb else return ba > bb end
            end
            -- Within a type: newest first, undated last, then questID for a
            -- stable total order.
            local ta, tb = a.t or 0, b.t or 0
            if (ta == 0) ~= (tb == 0) then return tb == 0 end
            if ta ~= tb then return ta > tb end
            return (a.q or 0) < (b.q or 0)
        end)
    else -- "date"
        table.sort(out, function(a, b)
            local ta, tb = a.t or 0, b.t or 0
            -- Dated entries always precede undated, both directions.
            if (ta == 0) ~= (tb == 0) then return tb == 0 end
            if ta ~= tb then
                if asc then return ta < tb else return ta > tb end
            end
            return (a.q or 0) < (b.q or 0)
        end)
    end
    return out
end

-- Account-wide daily streak: consecutive UTC-day numbers ending at today
-- (today OR yesterday counts as "still alive" since a player may not have
-- played yet today). Backfilled entries (t=0) are excluded — they have no
-- day to attribute. Returns { current, best, total } where total = entries
-- with a real timestamp.
function R:Streak()
    local entries = self.sv.entries
    if #entries == 0 then return { current = 0, best = 0, total = 0 } end

    local days = {}
    local datedCount = 0
    for i = 1, #entries do
        local t = entries[i].t
        if t and t > 0 then
            local d = math.floor(t / 86400)
            if not days[d] then days[d] = true end
            datedCount = datedCount + 1
        end
    end

    -- Sorted descending
    local list = {}
    for d in pairs(days) do list[#list + 1] = d end
    table.sort(list, function(a, b) return a > b end)
    if #list == 0 then return { current = 0, best = 0, total = datedCount } end

    local today = math.floor(((GetServerTime and GetServerTime()) or time()) / 86400)

    -- Current run, anchored at today or yesterday.
    local current = 0
    if list[1] == today or list[1] == today - 1 then
        current = 1
        local prev = list[1]
        for i = 2, #list do
            if list[i] == prev - 1 then
                current = current + 1
                prev = list[i]
            else
                break
            end
        end
    end

    -- Best run anywhere in history.
    local best, run = 0, 1
    for i = 2, #list do
        if list[i] == list[i - 1] - 1 then
            run = run + 1
        else
            if run > best then best = run end
            run = 1
        end
    end
    if run > best then best = run end
    if current > best then best = current end

    return { current = current, best = best, total = datedCount }
end

-- Returns the runtime completion map { [questID] = epoch (0 if backfilled) }
-- built and maintained at OnInitialize / Record / Backfill / Wipe. Callers
-- MUST NOT mutate the returned table.
function R:CompletionMap()
    return self._completion
end

function R:EntryCount()
    return #self.sv.entries
end

-- Reward aggregates for the Totals tab. Single O(N) walk that fills:
--   totalCount  — every entry counts, even old/backfilled ones
--   totalXP     — sum of xp across entries that have it
--   totalMoney  — sum of money (copper) across entries that have it
--   byChar      — [Name-Realm] = { count, xp, money } per character
--   topGold     — entry with the largest single-quest money reward
--   topXP       — entry with the largest single-quest XP reward
-- Allocates fresh result tables per call (click-driven; not hot).
function R:Totals()
    local entries = self.sv.entries
    local totalCount, totalXP, totalMoney = 0, 0, 0
    local byChar = {}
    local topGold, topXP

    for i = 1, #entries do
        local e = entries[i]
        totalCount = totalCount + 1

        local c = e.c or "?"
        local rec = byChar[c]
        if not rec then
            rec = { count = 0, xp = 0, money = 0 }
            byChar[c] = rec
        end
        rec.count = rec.count + 1

        local xp = e.xp
        if xp and xp > 0 then
            totalXP = totalXP + xp
            rec.xp  = rec.xp  + xp
            if not topXP or xp > (topXP.xp or 0) then topXP = e end
        end
        local m = e.m
        if m and m > 0 then
            totalMoney = totalMoney + m
            rec.money  = rec.money  + m
            if not topGold or m > (topGold.m or 0) then topGold = e end
        end
    end

    return {
        totalCount = totalCount,
        totalXP    = totalXP,
        totalMoney = totalMoney,
        byChar     = byChar,
        topGold    = topGold,
        topXP      = topXP,
    }
end

-- Day-bucketed counts for the Activity heatmap. Returns:
--   counts  — { [dayNumber] = quests turned in that day }
--   today   — today's day number (UTC-day = epoch / 86400, floored)
--   minDay  — oldest day in the window (today - daysBack + 1)
-- Backfilled entries (t == 0) are excluded — they have no day to attribute.
function R:DayCounts(daysBack)
    daysBack = daysBack or 90
    local now = (GetServerTime and GetServerTime()) or time()
    local today = math.floor(now / 86400)
    local minDay = today - daysBack + 1
    local counts = {}
    local entries = self.sv.entries
    for i = 1, #entries do
        local t = entries[i].t
        if t and t > 0 then
            local d = math.floor(t / 86400)
            if d >= minDay and d <= today then
                counts[d] = (counts[d] or 0) + 1
            end
        end
    end
    return counts, today, minDay
end

-- Period-bucketed XP / gold / quest-count for the Stats → Trends view.
-- granularity: "weekly" → twelve rolling 7-day windows; anything else → the
-- last 30 days, one bucket per day. Buckets are returned OLDEST→NEWEST so a
-- chart draws left (old) → right (new), and the last bucket is the current
-- day/week. Only entries with a real timestamp (t>0) contribute. xp/gold come
-- from the optional reward fields (xp / m), which only exist on turn-ins
-- recorded after reward tracking shipped — so a period can show quests with
-- little or no xp/gold. Returns:
--   periods     — array of { label, day0, day1, xp, gold, count } oldest→newest
--   maxXP/maxGold/maxCount — peak across periods (bar scaling; 0-safe)
--   granularity — "daily" | "weekly" (echoed back)
-- charFilter: a "Name-Realm" key restricts to that character; nil / "all" /
-- "" means account-wide (every character that pivots through e.c).
function R:Trends(granularity, charFilter)
    local weekly   = (granularity == "weekly")
    local wantChar = charFilter
    if wantChar == "all" or wantChar == "" then wantChar = nil end
    local now      = (GetServerTime and GetServerTime()) or time()
    local today    = math.floor(now / 86400)
    local nBuckets = weekly and 12 or 30
    local span     = weekly and 7 or 1

    -- Pre-create buckets oldest→newest. Bucket i covers the inclusive day
    -- range [hiDay - span + 1, hiDay], where hiDay walks forward to today.
    local periods = {}
    for i = 1, nBuckets do
        local hiDay = today - span * (nBuckets - i)
        periods[i] = { day0 = hiDay - span + 1, day1 = hiDay, xp = 0, gold = 0, count = 0 }
    end
    local oldestDay = periods[1].day0

    local function bucketIndex(day)
        if day < oldestDay or day > today then return nil end
        if weekly then return nBuckets - math.floor((today - day) / 7) end
        return nBuckets - (today - day)
    end

    -- Quests + quest XP come from recorded turn-ins.
    local entries = self.sv.entries
    for k = 1, #entries do
        local e = entries[k]
        local t = e.t
        if t and t > 0 and (not wantChar or e.c == wantChar) then
            local idx = bucketIndex(math.floor(t / 86400))
            if idx then
                local p = periods[idx]
                p.count = p.count + 1
                if e.xp and e.xp > 0 then p.xp = p.xp + e.xp end
            end
        end
    end

    -- Gold is ALL-source income from the per-day money ledger (loot, vendor,
    -- quest rewards — everything), not just quest-reward coin.
    local ledger = self.sv.goldDaily
    if ledger then
        for ckey, days in pairs(ledger) do
            if not wantChar or ckey == wantChar then
                for day, copper in pairs(days) do
                    if copper and copper > 0 then
                        local idx = bucketIndex(day)
                        if idx then periods[idx].gold = periods[idx].gold + copper end
                    end
                end
            end
        end
    end

    local maxXP, maxGold, maxCount = 0, 0, 0
    for i = 1, nBuckets do
        local p = periods[i]
        if p.xp    > maxXP    then maxXP    = p.xp    end
        if p.gold  > maxGold  then maxGold  = p.gold  end
        if p.count > maxCount then maxCount = p.count end
        p.label = date("%b %d", p.day0 * 86400)        -- bucket start; weekly = window start
    end

    return {
        periods     = periods,
        maxXP       = maxXP,
        maxGold     = maxGold,
        maxCount    = maxCount,
        granularity = weekly and "weekly" or "daily",
    }
end
