-- Data/QuestChains/_Overlays.lua
-- Authored graph OVERLAYS for API-/campaign-sourced chains.
--
-- The Chain Guide sources most chains live from Blizzard's questline API,
-- which only ever hands back a FLAT ordered quest list — so those chains
-- render as a straight vertical spine. An overlay lets us lay a hand-authored
-- node graph (explicit columns/rows, prerequisite branching, optional/side
-- steps, embedded chain-nav nodes) ON TOP of that live quest list WITHOUT
-- giving up the automatic, always-current quest data underneath. This is the
-- middle ground between "fully API-sourced (flat)" and "fully hand-authored
-- (a whole separate chain definition that goes stale)".
--
-- Keyed by `questlineID` (the same key the API and the campaign chapter
-- spine use — a campaign chapter's chapterID *is* its questlineID), so an
-- overlay matches whether the chain came from C_QuestLine or C_CampaignInfo.
-- A fully hand-authored chain can also be overlaid by its chainID.
--
-- Apply step: Modules/ChainGuide/Database.lua  DBmod:ApplyOverlay(chain) —
-- idempotent, runs once after a chain's items[] are populated. It maps the
-- live items by quest ID, applies the authored layout, and TRANSLATES the
-- authored connections (which reference STABLE quest IDs) into the items[]
-- INDICES the renderer consumes. Authoring by quest ID (not array index)
-- means the overlay survives Blizzard reordering the questline.
--
-- Overlay shape:
--   ns.CHAINGUIDE_OVERLAYS[questlineID] = {
--     -- per-quest layout overrides (only the fields you set are applied):
--     layout = {
--       [questID] = { x = col, y = row, optional = true?, breadcrumb = true? },
--       ...
--     },
--     -- explicit prerequisite edges, BY QUEST ID (translated to indices):
--     connections = {
--       [questID] = { prereqQuestID1, prereqQuestID2, ... },
--       ...
--     },
--     -- extra chain-navigation nodes to splice in (jump to another chain):
--     embed = {
--       { chainID = N, x = col, y = row, connections = { prereqQuestID, ... } },
--       ...
--     },
--   }
--
-- Quest IDs in an overlay that aren't present in the live list (Blizzard
-- dropped/renamed a quest) are skipped silently — the overlay degrades to
-- the API spine for anything it can't match, so a stale entry never breaks
-- the chain. NO GUESSING: only author layout/branches you have verified
-- (Wowhead questline map + in-game), per the rebuild rules.

local _, ns = ...

ns.CHAINGUIDE_OVERLAYS = ns.CHAINGUIDE_OVERLAYS or {}

-- ─── The Light's Summons (Midnight campaign opener, questline 5811) ──────
-- The flagship hand-laid graph. The API hands this back as a flat list; the real
-- topology is a linear opener → a 3-wide branching section that converges → a
-- 2-wide branching section → a linear finish. Quest IDs + prerequisite topology
-- were verified against the questline's structure and confirmed in-game via
-- /eqs chaindump.
--
-- Layout convention: a CENTRED top-down tree drawn with straight diagonal lines.
-- The main spine sits on the centre column (x = 1); a parallel tier spreads
-- symmetrically around it on the SAME row, on integer columns (3-wide = 0/1/2,
-- 2-wide = the outer 0/2). A simple fan-out/fan-in radiates from / converges on
-- one node, forming a clean diamond. An ALL-TO-ALL gate (every quest of a tier
-- gates every quest of the next) has no single convergence node, so we leave an
-- EMPTY ROW between those two tiers: the renderer drops a junction dot on that
-- middle row, and the lines converge on it then fan back out (so the gate reads
-- as one clean diamond instead of a crossing mesh). y grows downward; the gaps
-- of 2 at the gates (y3→y5, y8→y10) are deliberate. connections = prerequisite
-- quest IDs (the apply step translates them to item indices); a quest not in the
-- live list is skipped and keeps the API spine, so this degrades gracefully if
-- Blizzard reorders it.
ns.CHAINGUIDE_OVERLAYS[5811] = {
    layout = {
        [91281] = { x = 1, y = 0  },   -- Midnight                  (spine)
        [88719] = { x = 1, y = 1  },   -- A Voice from the Light    (spine)
        [86769] = { x = 1, y = 2  },   -- Last Bastion of the Light (spine)
        [86770] = { x = 0, y = 3  },   -- Champions of Quel'Danas   (3-wide: left)
        [89271] = { x = 1, y = 3  },   -- My Son                    (3-wide: centre)
        [86780] = { x = 2, y = 3  },   -- Where Heroes Hold         (3-wide: right)
        -- gate: 3 → 2 (junction dot lands on the empty row y4)
        [86805] = { x = 0, y = 5  },   -- The Hour of Need          (2-wide: left)
        [89012] = { x = 2, y = 5  },   -- A Safe Path               (2-wide: right)
        [86806] = { x = 1, y = 6  },   -- Luminous Wings            (spine)
        [86807] = { x = 1, y = 7  },   -- The Gate                  (spine)
        [91274] = { x = 0, y = 8  },   -- Severing the Void         (2-wide: left)
        [86834] = { x = 2, y = 8  },   -- Voidborn Banishing        (2-wide: right)
        -- gate: 2 → 2 (junction dot lands on the empty row y9)
        [86811] = { x = 0, y = 10 },   -- Ethereal Eradication      (2-wide: left)
        [86848] = { x = 2, y = 10 },   -- Light's Arsenal           (2-wide: right)
        [86849] = { x = 1, y = 11 },   -- Wrath Unleashed           (spine)
        [86850] = { x = 1, y = 12 },   -- Broken Sun                (spine)
        [86852] = { x = 1, y = 13 },   -- Light's Last Stand        (spine)
    },
    connections = {
        [88719] = { 91281 },                  -- A Voice ← Midnight
        [86769] = { 88719 },                  -- Last Bastion ← A Voice
        [86770] = { 86769 },                  -- Champions ← Last Bastion
        [89271] = { 86769 },                  -- My Son ← Last Bastion
        [86780] = { 86769 },                  -- Where Heroes Hold ← Last Bastion
        [86805] = { 86770, 89271, 86780 },    -- Hour of Need ← all three
        [89012] = { 86770, 89271, 86780 },    -- A Safe Path ← all three
        [86806] = { 86805, 89012 },           -- Luminous Wings ← Hour of Need + A Safe Path
        [86807] = { 86806 },                  -- The Gate ← Luminous Wings
        [91274] = { 86807 },                  -- Severing the Void ← The Gate
        [86834] = { 86807 },                  -- Voidborn Banishing ← The Gate
        [86811] = { 91274, 86834 },           -- Ethereal Eradication ← both
        [86848] = { 91274, 86834 },           -- Light's Arsenal ← both
        [86849] = { 86811, 86848 },           -- Wrath Unleashed ← both
        [86850] = { 86849 },                  -- Broken Sun ← Wrath Unleashed
        [86852] = { 86850 },                  -- Light's Last Stand ← Broken Sun
    },
}

-- ─── Of Caves and Cradles (Harandar, Midnight campaign chapter, questline 5725) ───
-- The reference's authored prerequisite chain, confirmed against Wowhead's
-- "Series" box for The Council Assembles (86929): the prereq sub-chain runs
-- Rift and the Den → Council Assembles → Den of Echoes → Echoes and Memories →
-- Echo of the Hunt — i.e. Council is EARLY. (Wowhead's flat "Storyline" listing
-- and C_QuestLine's flat order both place Council ~13th, but those are display
-- orderings, not the prerequisite chain a guide should draw.) The chain forks at
-- the end: A Hut → {Tending, Traveling Flowers} → Koozat → {Burning Bitterblooms,
-- Halting Harm, Culling the Spread} → Seeds of the Rift.
-- ⚠ "To Sow the Seed" (86930) is in the LIVE questline but NOT in the reference
-- (added later, or a side quest). Placed as an OPTIONAL side step off The Council
-- Assembles (its live-storyline predecessor) — flagged for a closer look.
ns.CHAINGUIDE_OVERLAYS[5725] = {
    layout = {
        [89402] = { x = 1, y = 0  },                  -- Harandar
        [86899] = { x = 1, y = 1  },                  -- The Root Cause
        [86900] = { x = 1, y = 2  },                  -- To Har'athir
        [86901] = { x = 1, y = 3  },                  -- The Rift and the Den
        [86929] = { x = 1, y = 4  },                  -- The Council Assembles
        [86930] = { x = 2, y = 4, optional = true },  -- To Sow the Seed (not in reference)
        [86907] = { x = 1, y = 5  },                  -- The Den of Echoes
        [86911] = { x = 1, y = 6  },                  -- Echoes and Memories
        [90094] = { x = 1, y = 7  },                  -- Echo of the Hunt
        [90095] = { x = 1, y = 8  },                  -- Echo of the Call
        [86912] = { x = 1, y = 9  },                  -- Down the Rootways
        [86913] = { x = 1, y = 10 },                  -- A Hut in Har'mara
        [86914] = { x = 0, y = 11 },                  -- Tending to Har'mara
        [86956] = { x = 2, y = 11 },                  -- The Traveling Flowers
        [86910] = { x = 1, y = 12 },                  -- Koozat's Trample
        [89034] = { x = 0, y = 13 },                  -- Burning Bitterblooms
        [86973] = { x = 1, y = 13 },                  -- Halting Harm in Har'mara
        [86942] = { x = 2, y = 13 },                  -- Culling the Spread
        [86944] = { x = 1, y = 14 },                  -- Seeds of the Rift
    },
    connections = {
        [86899] = { 89402 },
        [86900] = { 86899 },
        [86901] = { 86900 },
        [86929] = { 86901 },
        [86930] = { 86929 },                  -- To Sow the Seed ← Council Assembles (optional)
        [86907] = { 86929 },
        [86911] = { 86907 },
        [90094] = { 86911 },
        [90095] = { 90094 },
        [86912] = { 90095 },
        [86913] = { 86912 },
        [86914] = { 86913 },
        [86956] = { 86913 },
        [86910] = { 86914, 86956 },
        [89034] = { 86910 },
        [86973] = { 86910 },
        [86942] = { 86910 },
        [86944] = { 89034, 86973, 86942 },
    },
}
