-- Modules/ChainGuide/Database.lua
-- Resolves chain definitions from Data/QuestChains/* into runtime structures.
-- Owns: schema normalization, per-character variation/restriction resolution.
--
-- Chain shape (post-normalization):
--   { name, category, range = {min,max},
--     items = {
--       { type="quest"|"chain", id=int, x=int, y=int,
--         connections = { itemIndex, ... },         -- prereq edges (by items[] index)
--         variations  = { { id=..., type=..., restrictions={faction=,race=,class=} }, ... },
--         breadcrumb  = bool?,                       -- visual de-emphasis, excluded from progress
--         optional    = bool?,                       -- dashed connector to this node
--       },
--       ...
--     }
--   }
--
-- Legacy chains using `quests = { id1, id2, ... }` are auto-converted to a
-- linear items array on first access — old data keeps rendering, new data
-- can lay out arbitrary graphs.

local _, ns = ...

local DBmod = ns:RegisterSubsystem("ChainGuideDatabase", {})

DBmod.expansions = {}
DBmod.categories = {}
DBmod.chains = {}

function DBmod:RegisterExpansion(id, def) self.expansions[id] = def end
function DBmod:RegisterCategory(id, def)  self.categories[id]  = def end
function DBmod:RegisterChain(id, def)
    def.id = id
    self.chains[id] = def
end

-- ─── Character snapshot ────────────────────────────────────────────────
-- Used for restriction matching when picking item variations. Built lazily
-- and cached for the lifetime of the session; faction is the only field
-- that can change in-session (war-mode aside) and we accept that staleness.
function DBmod:CurrentCharacter()
    if self._char then return self._char end
    local _, classFile = UnitClass and UnitClass("player")
    local _, raceFile  = UnitRace and UnitRace("player")
    self._char = {
        faction = UnitFactionGroup and UnitFactionGroup("player"),
        class   = classFile,
        race    = raceFile,
    }
    return self._char
end

-- ─── Schema normalization ──────────────────────────────────────────────
-- Idempotent. Old chains with `quests = {...}` get an auto-built items array
-- so the renderer only ever has to deal with one shape.
function DBmod:NormalizeChain(chain)
    if not chain or chain._normalized then return chain end
    chain._normalized = true
    if not chain.items then
        local items = {}
        local quests = chain.quests or {}
        for i = 1, #quests do
            items[i] = {
                type = "quest",
                id   = quests[i],
                x    = 0,
                y    = i - 1,
                connections = (i > 1) and { i - 1 } or nil,
            }
        end
        chain.items = items
    end
    return chain
end

-- Walk `item.variations` and return the first variant whose restrictions match
-- the character. If none match (or no variations exist), the base item is
-- returned unchanged so the renderer always gets something to draw.
function DBmod:GetVariation(item, character)
    if not item.variations then return item end
    character = character or self:CurrentCharacter()
    for i = 1, #item.variations do
        local v = item.variations[i]
        if self:RestrictionsMatch(v.restrictions, character) then
            return {
                type        = v.type or item.type,
                id          = v.id   or item.id,
                name        = v.name or item.name,
                x           = item.x,
                y           = item.y,
                connections = item.connections,
                breadcrumb  = item.breadcrumb,
                optional    = item.optional,
                _variant    = true,
            }
        end
    end
    return item
end

function DBmod:RestrictionsMatch(r, c)
    if not r then return true end
    if r.faction and r.faction ~= c.faction then return false end
    if r.race    and r.race    ~= c.race    then return false end
    if r.class   and r.class   ~= c.class   then return false end
    return true
end
