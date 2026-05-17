-- Modules/ChainGuide/QuestLineSource.lua
-- Pulls chain content live from Blizzard's questline API:
--   C_QuestLine.GetAvailableQuestLines(uiMapID)  → questlines visible in a map
--   C_QuestLine.GetQuestLineQuests(questLineID) → ordered quest list per chain
--
-- A category aggregates questlines from every uiMapID it covers. Zones often
-- span multiple sub-maps (e.g. Eversong Woods + Silvermoon City), so the
-- resolver returns a *list* of mapIDs and discovery walks all of them.
--
-- Sources, in priority order:
--   1. Hand-authored chains in Data/QuestChains/* (full graphs).
--      A hand-authored chain with `questlineID = N` suppresses the API's
--      duplicate of N for the same category.
--   2. Saved-variable overrides in db.profile.chainGuide.zoneMapIDs.
--      Built up at runtime by /eqs discover.
--   3. Seed mapIDs in Data/QuestChains/_Index.lua (cat.mapIDs / cat.mapID).

local _, ns = ...

local QLS = ns:RegisterSubsystem("ChainGuideQuestLineSource", {})

QLS._discovered     = {}        -- [categoryID] = true
QLS._populated      = {}        -- [chainID]   = true
QLS._registered     = {}        -- [questLineID] = true (cross-category dedup)
QLS._retryScheduled = {}        -- [chainID]   = true (item-load retry inflight)

-- Scratch tables for /eqs discover printout dedup. Reused across invocations
-- instead of being allocated fresh — minor but consistent with the rest of
-- the addon's allocation discipline.
local _discoverSeen   = {}
local _discoverUnique = {}

-- Wipe everything we sourced from the API so a settings change can
-- re-trigger discovery from scratch (toggling showUnroutedChains, etc.).
function QLS:Reset()
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    for chainID, chain in pairs(Database.chains) do
        if chain._apiSourced then Database.chains[chainID] = nil end
    end
    self._discovered = {}
    self._populated  = {}
    self._registered = {}
    -- Campaign chains live in their own source/reset bucket.
    local CS = ns:GetSubsystem("ChainGuideCampaignSource")
    if CS and CS.Reset then CS:Reset() end
end

local CHAIN_ID_OFFSET = 5000000 -- keep API-derived IDs disjoint from hand-authored ones

local function showUnrouted()
    local DB = ns:GetSubsystem("DB")
    local cg = DB and DB.db and DB.db.profile and DB.db.profile.chainGuide
    if cg and cg.showUnroutedChains ~= nil then return cg.showUnroutedChains end
    return false                  -- default: clean, routed-only list
end

-- Routing entries are { cat = categoryID, name = "..." }. Older callers
-- want just the category, so accept either shape.
local function routedEntry(questLineID)
    local map = ns.QUESTLINE_ROUTING
    if not map then return nil end
    local v = map[questLineID]
    if type(v) == "table" then return v end
    if type(v) == "number" then return { cat = v } end
    return nil
end
local function routedCategory(questLineID)
    local e = routedEntry(questLineID)
    return e and e.cat
end

local function authoredQuestlinesInCategory(catID)
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    local set = {}
    for _, chain in pairs(Database.chains) do
        if chain.category == catID and chain.questlineID and not chain._apiSourced then
            set[chain.questlineID] = true
        end
    end
    return set
end

-- Returns the saved override list for a category, normalizing legacy single-
-- value entries (number) into one-element arrays so callers don't care which
-- shape the saved variable holds.
local function getOverrideList(catID)
    local DB = ns:GetSubsystem("DB")
    local map = DB and DB.db and DB.db.profile and DB.db.profile.chainGuide
                and DB.db.profile.chainGuide.zoneMapIDs
    if not map then return nil end
    local v = map[catID]
    if type(v) == "number" then return { v } end
    if type(v) == "table"  then return v   end
    return nil
end

-- All mapIDs the discoverer should query for `catID`: union of seed (from
-- _Index.lua) and saved overrides, deduplicated, in seed-then-override order.
local function resolveMapIDs(cat, catID)
    local out, seen = {}, {}
    local function push(m)
        if m and not seen[m] then seen[m] = true; out[#out + 1] = m end
    end
    if cat then
        if cat.mapIDs then for _, m in ipairs(cat.mapIDs) do push(m) end end
        push(cat.mapID)                       -- legacy single-value seed
    end
    local list = getOverrideList(catID)
    if list then for _, m in ipairs(list) do push(m) end end
    return out
end

-- Append a discovered mapID to a category's saved override list, deduped.
local function appendMapIDOverride(catID, mapID)
    local DB = ns:GetSubsystem("DB")
    if not (DB and DB.db) then return end
    local cg = DB.db.profile.chainGuide
    cg.zoneMapIDs = cg.zoneMapIDs or {}
    local cur = cg.zoneMapIDs[catID]
    -- Migrate legacy single-number entry into an array as a side effect.
    if type(cur) == "number" then cur = { cur }; cg.zoneMapIDs[catID] = cur end
    if type(cur) ~= "table" then cur = {}; cg.zoneMapIDs[catID] = cur end
    for i = 1, #cur do
        if cur[i] == mapID then return end
    end
    cur[#cur + 1] = mapID
end

-- Best-effort name → category. Exact case-insensitive match wins over
-- substring; substring catches cases like "Eversong Woods (Midnight)" or
-- the user typing "eversong" as a hint.
local function matchCategoryByName(name)
    if not name or name == "" then return nil end
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    local lower = name:lower()
    for id, cat in pairs(Database.categories) do
        if (cat.name or ""):lower() == lower then return id end
    end
    for id, cat in pairs(Database.categories) do
        local cn = (cat.name or ""):lower()
        if cn ~= "" and (lower:find(cn, 1, true) or cn:find(lower, 1, true)) then
            return id
        end
    end
    return nil
end

-- Stub-register every chain we know exists in this category. The routing
-- table is the source of truth — it carries questlines whether the player
-- has them, hasn't started them, or finished them. The API is consulted
-- *additionally* to surface any unrouted questlines (only shown when the
-- showUnroutedChains toggle is on) and to keep us forward-compatible with
-- patches that introduce questlines not yet in our routing.
function QLS:EnsureZoneChains(catID)
    if self._discovered[catID] then return end

    local Database = ns:GetSubsystem("ChainGuideDatabase")
    local cat = Database.categories[catID]
    if not cat then return end

    -- Campaign categories are sourced live from Blizzard's campaign API
    -- (C_CampaignInfo chapter spine), not the static questline routing —
    -- the campaign is cross-zone and never matched a questline category.
    -- Mark discovered and bail so the static routing/API-map walk below
    -- never re-files campaign questlines under their zone.
    if cat.campaignID then
        local CS = ns:GetSubsystem("ChainGuideCampaignSource")
        if CS then CS:EnsureCampaignChains(catID) end
        self._discovered[catID] = true
        return
    end

    local skip = authoredQuestlinesInCategory(catID)

    local function registerChain(qlID, destCat, name)
        if self._registered[qlID] or skip[qlID] then return end
        -- A campaign-chapter questline lives ONLY under its campaign
        -- category (CampaignSource owns it). Don't also file it under its
        -- zone — that was the "Whispers in the Twilight shows twice" case.
        -- registerChain only ever runs for non-campaign categories (the
        -- campaign categories bail to CampaignSource above), so this is an
        -- unconditional skip.
        local CS = ns:GetSubsystem("ChainGuideCampaignSource")
        if CS and CS.IsChapterQuestline and CS:IsChapterQuestline(qlID) then
            return
        end
        local chainID = CHAIN_ID_OFFSET + qlID
        if not Database.chains[chainID] then
            Database:RegisterChain(chainID, {
                category    = destCat,
                name        = name or ("Questline " .. qlID),
                questlineID = qlID,
                items       = {},
                _apiSourced = true,
            })
        end
        self._registered[qlID] = true
    end

    -- 1. Register every routed questline whose category == catID. This is
    --    the path that surfaces COMPLETED questlines: GetAvailableQuestLines
    --    drops them, but our routing table doesn't.
    local routing = ns.QUESTLINE_ROUTING or {}
    for qlID, entry in pairs(routing) do
        local destCat = (type(entry) == "table") and entry.cat or entry
        local name    = (type(entry) == "table") and entry.name or nil
        if destCat == catID then registerChain(qlID, destCat, name) end
    end

    -- 2. Also walk the API for this category's mapIDs. Routed questlines
    --    (handled above) are skipped via _registered; unrouted questlines
    --    are routed elsewhere if known, dropped if unknown unless the
    --    user has opted in via showUnroutedChains.
    if C_QuestLine and C_QuestLine.GetAvailableQuestLines then
        local mapIDs = resolveMapIDs(cat, catID)
        local includeUnrouted = showUnrouted()
        for _, mapID in ipairs(mapIDs) do
            local lines = C_QuestLine.GetAvailableQuestLines(mapID) or {}
            for i = 1, #lines do
                local info = lines[i]
                local qlID = info and info.questLineID
                if qlID and not info.isHidden then
                    local routedCat = routedCategory(qlID)
                    local destCat = routedCat or (includeUnrouted and catID or nil)
                    if destCat then
                        registerChain(qlID, destCat,
                            (info.questLineName ~= "" and info.questLineName) or nil)
                    end
                end
            end
        end
    end

    self._discovered[catID] = true
end

-- Build items[] from the questline's quest list. No-op if the chain already
-- has authored items, no questlineID, or we've populated it before.
function QLS:EnsureChainItems(chain)
    if not chain or self._populated[chain.id] then return end
    if not chain.questlineID then return end
    if chain.items and #chain.items > 0 then
        self._populated[chain.id] = true
        return
    end
    if not (C_QuestLine and C_QuestLine.GetQuestLineQuests) then return end

    local quests = C_QuestLine.GetQuestLineQuests(chain.questlineID)
    if not quests or #quests == 0 then
        -- Blizzard's questline data isn't loaded yet for this chain. The
        -- player would otherwise have to click the chain a second (or
        -- third) time before its quests showed up — schedule a one-shot
        -- retry + re-render so the next pass picks up the loaded data
        -- automatically. Guarded by _retryScheduled so a flood of renders
        -- can't queue up duplicate timers.
        if not self._retryScheduled[chain.id] then
            self._retryScheduled[chain.id] = true
            C_Timer.After(0.3, function()
                self._retryScheduled[chain.id] = nil
                self:EnsureChainItems(chain)
                local CG = ns:GetSubsystem("ChainGuide")
                if CG and CG.frame and CG.frame:IsShown() and CG.RenderCurrent then
                    CG:RenderCurrent()
                end
            end)
        end
        return
    end

    local items = {}
    for i = 1, #quests do
        items[i] = {
            type        = "quest",
            id          = quests[i],
            x           = 0,
            y           = i - 1,
            connections = (i > 1) and { i - 1 } or nil,
        }
    end
    chain.items = items
    chain._normalized = true
    self._populated[chain.id] = true
end

-- /eqs discover [<hint>]
--   No hint: auto-match the player's current zone name to a category.
--   With hint: assign current mapID to whichever category fuzzy-matches the
--   hint (e.g. "/eqs discover eversong" while in Silvermoon City).
function QLS:PrintCurrentZone(hint)
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then
        print("|cffEBB706EQ|r: could not resolve player's map.")
        return
    end
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    local zoneName = info and info.name or "?"
    print(("|cffEBB706EQ|r: |cffffffff%s|r — uiMapID |cff66ccff%d|r"):format(zoneName, mapID))

    local catID
    if hint and hint ~= "" then
        catID = matchCategoryByName(hint)
        if not catID then
            print(("  No category matches |cffffffff%s|r."):format(hint))
        end
    else
        catID = matchCategoryByName(zoneName)
        if not catID then
            print("  No category name match. Use |cffEBB706/eqs discover <category>|r to assign manually (e.g. \"/eqs discover eversong\").")
        end
    end

    if catID then
        local Database = ns:GetSubsystem("ChainGuideDatabase")
        local cat = Database.categories[catID]
        appendMapIDOverride(catID, mapID)
        self._discovered[catID] = nil      -- force a re-discover with the new mapID list
        print(("  Added to category |cffffffff%s|r."):format(cat and cat.name or tostring(catID)))
        local CG = ns:GetSubsystem("ChainGuide")
        if CG and CG.frame and CG.frame:IsShown() and CG.RenderCurrent then
            CG:RenderCurrent()
        end
    end

    if not (C_QuestLine and C_QuestLine.GetAvailableQuestLines) then
        print("  (C_QuestLine API unavailable on this build)")
        return
    end
    local lines = C_QuestLine.GetAvailableQuestLines(mapID) or {}
    if #lines == 0 then
        print("  No questlines reported by the API yet (move around the zone and retry).")
        return
    end
    -- The API repeats a questline once per entry-point quest; dedupe by ID
    -- so the printout matches what the chain guide will actually display.
    wipe(_discoverSeen)
    wipe(_discoverUnique)
    for i = 1, #lines do
        local q = lines[i]
        if q.questLineID and not _discoverSeen[q.questLineID] then
            _discoverSeen[q.questLineID] = true
            _discoverUnique[#_discoverUnique + 1] = q
        end
    end
    print(("  |cffEBB706%d unique questline(s):|r"):format(#_discoverUnique))
    for i = 1, #_discoverUnique do
        local q = _discoverUnique[i]
        print(("    [%d] %s%s"):format(
            q.questLineID or 0,
            q.questLineName or "?",
            q.isHidden and " |cff999999(hidden)|r" or ""
        ))
    end
end
