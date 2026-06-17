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
    -- Lay any authored graph overlay on top of the (now-present) items. For an
    -- API/campaign chain whose items are still empty here (questline data not
    -- loaded yet) this is a no-op that leaves _overlayApplied unset, so it
    -- re-runs once EnsureChainItems populates the real list (see ApplyOverlay).
    self:ApplyOverlay(chain)
    return chain
end

-- ─── Authored overlay ──────────────────────────────────────────────────
-- Lay a hand-authored graph (Data/QuestChains/_Overlays.lua) over a chain's
-- live items[]: apply per-quest x/y/optional/breadcrumb, rewrite connections,
-- and splice in embedded chain-nav nodes. Authored data is keyed by STABLE
-- quest IDs (and embeds by chainID); connections reference quest IDs and are
-- translated here into the items[] INDICES the renderer expects. Idempotent
-- (guarded by chain._overlayApplied) and only ever runs once a chain actually
-- has items — so it allocates nothing per render and re-applies correctly when
-- an empty API chain finally streams in its quest list.
function DBmod:ApplyOverlay(chain)
    if not chain or chain._overlayApplied then return end
    local items = chain.items
    if not items or #items == 0 then return end          -- wait for real items; don't latch the flag
    local overlays = ns.CHAINGUIDE_OVERLAYS
    local overlay  = overlays and (overlays[chain.questlineID] or overlays[chain.id])
    if not overlay then chain._overlayApplied = true; return end   -- nothing to overlay; stop scanning

    -- Map live items by quest ID so authored (id-keyed) data can find them
    -- regardless of the order Blizzard returned the questline in.
    local idIndex = {}
    for i = 1, #items do
        local it = items[i]
        if it and it.id then idIndex[it.id] = i end
    end

    if overlay.layout then
        for qid, lay in pairs(overlay.layout) do
            local idx = idIndex[qid]
            if idx then
                local it = items[idx]
                if lay.x ~= nil then it.x = lay.x end
                if lay.y ~= nil then it.y = lay.y end
                if lay.optional   ~= nil then it.optional   = lay.optional end
                if lay.breadcrumb ~= nil then it.breadcrumb = lay.breadcrumb end
            end
        end
    end

    if overlay.connections then
        for qid, prereqs in pairs(overlay.connections) do
            local idx = idIndex[qid]
            if idx then
                local conn = {}
                for j = 1, #prereqs do
                    local pidx = idIndex[prereqs[j]]
                    if pidx then conn[#conn + 1] = pidx end
                end
                -- Only overwrite when at least one authored prereq resolved. If
                -- NONE did (Blizzard dropped/renamed those quests), leave the
                -- node's existing spine edge alone — that's what "degrades to the
                -- API spine" means; nil-ing it here would orphan the node to the
                -- root column. Matches the embed branch's guard below.
                if #conn > 0 then items[idx].connections = conn end
            end
        end
    end

    if overlay.embed then
        for e = 1, #overlay.embed do
            local em = overlay.embed[e]
            if em and em.chainID then
                local node = { type = "chain", id = em.chainID, x = em.x, y = em.y }
                if em.connections then
                    local conn = {}
                    for j = 1, #em.connections do
                        local pidx = idIndex[em.connections[j]]
                        if pidx then conn[#conn + 1] = pidx end
                    end
                    if #conn > 0 then node.connections = conn end
                end
                items[#items + 1] = node
            end
        end
    end

    chain._overlayApplied = true
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
