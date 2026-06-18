-- Modules/ChainGuide/Characters.lua
-- Per-character chain-progress cache. Persisted account-wide in
-- EverythingQuestsChainCache so an alt can browse "what quests has my main
-- finished in this chain" without re-scraping the quest log.
--
-- Authoritative source for "have I completed this quest" is Blizzard's own
-- C_QuestLog.IsQuestFlaggedCompleted (account-flagged completion). We cache
-- on top so cross-character queries don't have to switch characters.

local _, ns = ...

local C = ns:RegisterSubsystem("ChainGuideCharacters", {})

local function charKey()
    local name  = UnitName  and UnitName("player")  or "?"
    local realm = GetRealmName and GetRealmName()   or "?"
    return name .. "-" .. realm
end

function C:OnInitialize()
    local DB = ns:GetSubsystem("DB")
    self.cache = DB.chainCache
    self.charKey = charKey()
    -- UnitClass returns (localizedName, classFile, classID); we persist the
    -- locale-independent classFile ("WARRIOR"). The old one-liner
    -- `local _, classFile = (UnitClass and UnitClass("player")) or nil, nil`
    -- truncated the call to its FIRST return via the parens/`or`, so
    -- classFile was ALWAYS nil and the cached class never persisted.
    local _, classFile
    if UnitClass then _, classFile = UnitClass("player") end
    local rec = self.cache[self.charKey]
    if not rec then
        rec = {
            name      = UnitName and UnitName("player"),
            class     = classFile,
            faction   = UnitFactionGroup and UnitFactionGroup("player"),
            completed = {},
        }
        self.cache[self.charKey] = rec
    elseif not rec.class then
        rec.class = classFile          -- self-heal entries written before the fix
    end
    rec.lastSeen = time()              -- stamp the current char each login so PruneStaleRecords spares it
    self.char = rec
end

function C:OnEnable()
    local Events = ns:GetSubsystem("Events")
    Events:On("QUEST_TURNED_IN", function(_, questID)
        if questID and self.char then
            self.char.completed[questID] = true
        end
    end)
end

-- Prune whole character records not seen within `ttl` seconds (deleted or
-- long-abandoned alts), never the current character. Safe because
-- IsQuestCompleted checks the live API first and only falls back to the CURRENT
-- char's set — no other record is read today. We drop WHOLE records, not
-- individual quest entries: per-quest pruning is wrong-granularity and would
-- erode the current char's turn-in fallback and the latent cross-char browse. A
-- record with no lastSeen is stamped this pass (grace) instead of dropped.
-- Called from DB:MaybePruneChainCache (throttled). time() is epoch.
function C:PruneStaleRecords(now, ttl)
    if not self.cache then return 0 end
    local removed = 0
    for k, v in pairs(self.cache) do
        -- Only real character records: a table carrying `completed`. This skips
        -- the sibling questCoords table and the lastPrune number that share
        -- this account-wide cache. Never touch the current character.
        if type(v) == "table" and v.completed ~= nil and k ~= self.charKey then
            if not v.lastSeen then
                v.lastSeen = now
            elseif now - v.lastSeen > ttl then
                self.cache[k] = nil
                removed = removed + 1
            end
        end
    end
    return removed
end

-- Has this character ever completed `questID`? Prefer the live Blizzard flag
-- (account-wide); fall back to our cached completion set. The cache only
-- catches turn-ins that happened while the addon was loaded — the live flag
-- is authoritative for everything else.
function C:IsQuestCompleted(questID)
    if not questID then return false end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
        and C_QuestLog.IsQuestFlaggedCompleted(questID) then
        return true
    end
    return self.char and self.char.completed and self.char.completed[questID] == true
end

-- Is the quest currently in the player's quest log (active)?
function C:IsQuestActive(questID)
    if not (questID and C_QuestLog and C_QuestLog.GetLogIndexForQuestID) then
        return false
    end
    return C_QuestLog.GetLogIndexForQuestID(questID) ~= nil
end

-- A chain is "complete" when its final quest is flagged completed. This
-- handles questlines with branching/optional quests where the strict
-- count-completed/count-total ratio never hits 100% — Blizzard's questline
-- DB lists every possible quest, but a single character only follows one
-- branch. The last item in the API-returned quest list is reliably the
-- climactic turn-in for these flat storylines.
function C:IsChainComplete(chain)
    if not chain or not chain.items or #chain.items == 0 then return false end
    local DB = ns:GetSubsystem("ChainGuideDatabase")
    -- Skim from the end and skip chain-nav nodes / breadcrumbs.
    for i = #chain.items, 1, -1 do
        local raw = chain.items[i]
        if raw.type ~= "chain" and not raw.breadcrumb then
            local item = DB:GetVariation(raw)
            return self:IsQuestCompleted(item.id)
        end
    end
    return false
end

-- Aggregate progress for a chain: returns (completed, active, total).
-- Walks the normalized items[] array, resolves variations per character, and
-- excludes nested "chain" items + breadcrumbs from the totals so the displayed
-- "X/Y" reflects quest progress only, not navigation nodes.
--
-- Same-cell collapse: a faction-paired step is carried as TWO items sharing one
-- overlay cell (e.g. Paved in Ash — 86735 Horde / 86736 Alliance, both at x1,y2).
-- The off-faction half can never complete, so counting both would inflate the
-- denominator AND keep the chain from ever reading 100%. We count each cell once
-- (status = the best of its members), matching ChainView's display collapse and
-- nextActionableStep. Reused scratch keeps the walk allocation-free.
local _cpStatus = {}   -- [cellKey] = 0 pending | 1 active | 2 complete (max seen)
local _cpKeys   = {}   -- distinct cell keys, for the tally pass
function C:ChainProgress(chain)
    if not chain then return 0, 0, 0 end
    local DB = ns:GetSubsystem("ChainGuideDatabase")
    DB:NormalizeChain(chain)
    local items = chain.items
    if not items or #items == 0 then return 0, 0, 0 end
    local char = DB:CurrentCharacter()
    local complete, active, total = 0, 0, 0
    wipe(_cpStatus)
    local nKeys = 0
    for i = 1, #items do
        local raw = items[i]
        if raw.type ~= "chain" and not raw.breadcrumb then
            local item = DB:GetVariation(raw, char)
            local s = self:IsQuestCompleted(item.id) and 2
                      or (self:IsQuestActive(item.id) and 1 or 0)
            local key = (raw.x and raw.y) and (raw.y * 4096 + raw.x) or nil
            if key then
                -- Defer counting to the tally pass; keep the best member status.
                local prev = _cpStatus[key]
                if prev == nil then
                    nKeys = nKeys + 1
                    _cpKeys[nKeys] = key
                    _cpStatus[key] = s
                elseif s > prev then
                    _cpStatus[key] = s
                end
            else
                -- Unpositioned item (linear chain): its own unit, count inline.
                total = total + 1
                if s == 2 then complete = complete + 1
                elseif s == 1 then active = active + 1 end
            end
        end
    end
    for k = 1, nKeys do
        total = total + 1
        local s = _cpStatus[_cpKeys[k]]
        if s == 2 then complete = complete + 1
        elseif s == 1 then active = active + 1 end
    end
    return complete, active, total
end
