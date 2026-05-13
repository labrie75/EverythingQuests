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
    if not self.cache[self.charKey] then
        local _, classFile = (UnitClass and UnitClass("player")) or nil, nil
        self.cache[self.charKey] = {
            name      = UnitName and UnitName("player"),
            class     = classFile,
            faction   = UnitFactionGroup and UnitFactionGroup("player"),
            completed = {},
        }
    end
    self.char = self.cache[self.charKey]
end

function C:OnEnable()
    local Events = ns:GetSubsystem("Events")
    Events:On("QUEST_TURNED_IN", function(_, questID)
        if questID and self.char then
            self.char.completed[questID] = true
        end
    end)
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
function C:ChainProgress(chain)
    if not chain then return 0, 0, 0 end
    local DB = ns:GetSubsystem("ChainGuideDatabase")
    DB:NormalizeChain(chain)
    local items = chain.items
    if not items or #items == 0 then return 0, 0, 0 end
    local char = DB:CurrentCharacter()
    local complete, active, total = 0, 0, 0
    for i = 1, #items do
        local raw = items[i]
        if raw.type ~= "chain" and not raw.breadcrumb then
            local item = DB:GetVariation(raw, char)
            total = total + 1
            if self:IsQuestCompleted(item.id) then
                complete = complete + 1
            elseif self:IsQuestActive(item.id) then
                active = active + 1
            end
        end
    end
    return complete, active, total
end
