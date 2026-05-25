-- Core/Cache.lua
-- Single quest-state cache shared by all modules. Avoids each module spamming
-- C_QuestLog APIs every frame.
--
-- Two-tier invalidation. QUEST_LOG_UPDATE fires constantly in WoW (objective
-- progress, idle ticks, zone updates) — wiping and rebuilding the whole
-- cache on every fire was the addon's largest source of GC churn (~800
-- fresh tables/sec for a 50-quest log). So:
--
--   • dirtyAll        — set on quest add/remove/turn-in events that change
--                       the *set* of quests. Triggers a full wipe + rebuild.
--   • dirtyObjectives — set on QUEST_LOG_UPDATE / QUEST_WATCH_LIST_CHANGED.
--                       Refreshes objectives + isComplete + isWatched on
--                       existing entries in place, without recreating them
--                       (objectives only for watched quests). Also re-
--                       derives isCampaign every pass so a cold-start
--                       miscategorization self-heals as campaign data
--                       loads — no structural rebuild needed.
--
-- Net effect: full rebuild fires only on real structural changes (a few
-- times per minute at most), and the cheap refresh skips most of the log.

local _, ns = ...

local Cache = ns:RegisterSubsystem("Cache", {})

Cache.quests          = {}     -- [questID] = { ... }
Cache.headerOrder     = {}     -- ordered list of header titles
Cache.dirtyAll        = true   -- needs full rebuild
Cache.dirtyObjectives = false  -- needs lightweight objectives/state refresh

-- Per-quest "first cached" timestamp (epoch secs). Persists across full
-- rebuilds (fullRebuild wipes Cache.quests but NOT this), so a quest keeps
-- its original firstSeen; pruned to the live quest set each rebuild so it
-- can't grow unbounded. Enables a future "recently added" sort/highlight at
-- zero hot-path cost — one extra number field on tables we already build.
local firstSeen = {}

-- isCampaign source. On a COLD client start C_QuestLog.GetInfo's
-- campaignID isn't populated yet at the first cache build, so a campaign
-- quest would wrongly land in the regular Quests section until a
-- structural event (accept / turn-in / abandon) forced a rebuild.
-- C_CampaignInfo is the authoritative live source and fills in as quest
-- data loads — consult it first, fall back to GetInfo's campaignID when
-- present. Numbers/booleans only, no allocation.
local function deriveIsCampaign(id, info)
    if C_CampaignInfo and C_CampaignInfo.GetCampaignID then
        local cid = C_CampaignInfo.GetCampaignID(id)
        if cid and cid > 0 then return true end
    end
    return (info and info.campaignID and info.campaignID > 0) and true or false
end

-- Fallback "objectives" line for quests with no trackable leaderboard
-- objectives (e.g. "speak to X" / ready-to-turn-in quests). Such quests would
-- otherwise render as a bare title; the tracker shows this summary/turn-in
-- direction instead (see Blocks.buildSubText). The text is the quest log's
-- objectivesText, which is selection-based (GetQuestLogQuestText reads the
-- SELECTED quest), so we save and restore the player's selection around the
-- read. It never changes for a quest, so cache it for the session and fetch
-- each quest at most once — keeping the selection mutation off the hot path.
local objTextCache = {}
local function getObjectivesText(id)
    local cached = objTextCache[id]
    if cached ~= nil then return cached end
    local text = ""
    if C_QuestLog and C_QuestLog.SetSelectedQuest and _G.GetQuestLogQuestText then
        local saved = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
        C_QuestLog.SetSelectedQuest(id)
        local _, objText = _G.GetQuestLogQuestText()
        text = objText or ""
        if saved and saved ~= 0 then C_QuestLog.SetSelectedQuest(saved) end
    end
    objTextCache[id] = text
    return text
end

local function fullRebuild()
    wipe(Cache.quests)
    wipe(Cache.headerOrder)

    -- Walk the indexed quest log so we capture zone headers (which
    -- GetAllQuests omits). Headers are interleaved entries — track the
    -- most recent one and attach it to each quest as its zone label.
    local currentHeader = nil
    local n = C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0
    for i = 1, n do
        local info = C_QuestLog.GetInfo and C_QuestLog.GetInfo(i)
        if info then
            if info.isHeader then
                currentHeader = info.title
            elseif info.isHidden then
                -- Skip Blizzard-hidden tracking quests: they're system bookkeeping
                -- (world-quest pings, account flags) that the default quest log
                -- excludes and the player cannot abandon.
            else
                local id = info.questID
                local fs = firstSeen[id]
                if not fs then fs = time(); firstSeen[id] = fs end
                local q = {
                    questID        = id,
                    firstSeen      = fs,                                           -- epoch secs first cached; survives rebuilds
                    title          = info.title or (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)),
                    level          = info.level,
                    zone           = currentHeader,
                    frequency      = info.frequency,
                    isComplete     = C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) or false,
                    isOnMap        = info.isOnMap,
                    isCampaign     = deriveIsCampaign(id, info),
                    isAutoComplete = info.isAutoComplete,
                    -- Blizzard's quest watch state — non-nil means the quest
                    -- is currently in the player's watch list (the checkbox
                    -- in Blizzard's quest log). Drives the showOnlyWatched
                    -- filter; matches the default tracker's visibility.
                    isWatched      = C_QuestLog.GetQuestWatchType
                                     and C_QuestLog.GetQuestWatchType(id) ~= nil,
                    -- Modern classification enum drives the per-quest icon
                    -- (Recurring/Campaign/Calling/Meta/Important/Questline/etc).
                    -- The canonical API in Midnight retail is
                    -- C_QuestInfoSystem.GetQuestClassification — the
                    -- canonical source. C_QuestLog also has
                    -- a similarly-named function on some builds, kept here as
                    -- a fallback in case the InfoSystem one isn't shipped.
                    classification = (C_QuestInfoSystem
                                      and C_QuestInfoSystem.GetQuestClassification
                                      and C_QuestInfoSystem.GetQuestClassification(id))
                                  or (C_QuestLog
                                      and C_QuestLog.GetQuestClassification
                                      and C_QuestLog.GetQuestClassification(id)),
                    objectives     = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id) or {},
                }
                -- Quests with no leaderboard objectives get a fallback summary
                -- line so the tracker block isn't a bare title (see Blocks).
                if #q.objectives == 0 then
                    q.fallbackText = getObjectivesText(id)
                end
                Cache.quests[id] = q
            end
        end
    end
    -- Bound the persistent firstSeen map: drop quests no longer in the log
    -- (setting an existing field to nil mid-pairs is well-defined in Lua).
    for qid in pairs(firstSeen) do
        if not Cache.quests[qid] then firstSeen[qid] = nil end
    end
    Cache.dirtyAll        = false
    Cache.dirtyObjectives = false
end

-- Cheap path: refresh just the fields that change on QUEST_LOG_UPDATE
-- (objectives + isComplete) and QUEST_WATCH_LIST_CHANGED (isWatched).
-- Skips unwatched quests — they aren't visible in the tracker, so their
-- objectives don't need to be fresh until they're watched (which fires
-- QUEST_WATCH_LIST_CHANGED and re-marks the cache dirty).
local function refreshDynamicFields()
    for id, q in pairs(Cache.quests) do
        local watched = C_QuestLog.GetQuestWatchType
                        and C_QuestLog.GetQuestWatchType(id) ~= nil
        q.isWatched = watched
        -- Self-heal cold-start campaign miscategorization: re-derive every
        -- pass (for ALL quests, not just watched — section placement
        -- applies regardless of watch state). See deriveIsCampaign.
        q.isCampaign = deriveIsCampaign(id)
        if watched then
            if C_QuestLog.GetQuestObjectives then
                q.objectives = C_QuestLog.GetQuestObjectives(id) or q.objectives
            end
            if C_QuestLog.IsComplete then
                q.isComplete = C_QuestLog.IsComplete(id) or false
            end
            -- A quest that now has no objectives (e.g. just became ready to
            -- turn in) needs the fallback summary line too. Cached per quest,
            -- so this is a no-op after the first fetch.
            if q.objectives and #q.objectives == 0 and not q.fallbackText then
                q.fallbackText = getObjectivesText(id)
            end
        end
    end
    Cache.dirtyObjectives = false
end

local function refresh()
    if Cache.dirtyAll then
        fullRebuild()
    elseif Cache.dirtyObjectives then
        refreshDynamicFields()
    end
end

function Cache:Get(questID)
    refresh()
    return self.quests[questID]
end

function Cache:All()
    refresh()
    return self.quests
end

-- Public API: external callers can still force a full rebuild if they need
-- absolute freshness. Internally the events route to the right tier.
function Cache:Invalidate()
    self.dirtyAll = true
end

function Cache:OnInitialize()
    local Events = ns:GetSubsystem("Events")

    -- Structural changes need a full rebuild — the quest set is different.
    local function dirtyAll() Cache.dirtyAll = true end
    Events:On("QUEST_ACCEPTED",   dirtyAll)
    Events:On("QUEST_REMOVED",    dirtyAll)
    Events:On("QUEST_TURNED_IN",  dirtyAll)

    -- High-frequency events only mark the cheaper refresh path. dirtyAll
    -- takes priority — if both flags end up set in the same window, we
    -- still do the full rebuild and skip the dynamic refresh on top.
    local function dirtyDynamic() Cache.dirtyObjectives = true end
    Events:On("QUEST_LOG_UPDATE",         dirtyDynamic)
    Events:On("QUEST_WATCH_LIST_CHANGED", dirtyDynamic)
end
