-- Data/QuestChains/_Overlays_Revelations.lua
-- Patch 12.0.7 "Revelations" saga overlays (category ns.CAT.REVELATIONS).
--
-- 6050 "Legacy of the Amani" — HAND-AUTHORED from the reference topology
-- (decoded from its relative-forward-offset connections): a linear spine into
-- two back-to-back diamonds, then a linear tail to the finale (93012 "Dead End").
--   spine  92897→92895→92899→92900→92901→92904→92907→92955
--   diamond 92955 → {92957, 92958} → 92952
--   diamond 92952 → {92953, 92951} → 92954
--   tail   92954 → 93010 → 93011 → 93012
-- Laid out to the centred-tree convention (spine x=1, branch pairs x=0/2).
--
-- 6229-6232 (An Island of Fangs / Ghosts of the Past / Original Sin / The
-- Battle for Atal'Utek) have NO authored topology in the reference yet
-- (items = {}), so they get NO overlay and render as the linear API spine.
local _, ns = ...
ns.CHAINGUIDE_OVERLAYS = ns.CHAINGUIDE_OVERLAYS or {}

    -- Legacy of the Amani  (questline 6050, Revelations 12.0.7 — Zul'Aman)
    ns.CHAINGUIDE_OVERLAYS[6050] = {
        layout = {
            [92897] = { x = 1, y = 0  },
            [92895] = { x = 1, y = 1  },
            [92899] = { x = 1, y = 2  },
            [92900] = { x = 1, y = 3  },
            [92901] = { x = 1, y = 4  },
            [92904] = { x = 1, y = 5  },
            [92907] = { x = 1, y = 6  },
            [92955] = { x = 1, y = 7  },
            [92957] = { x = 0, y = 8  },
            [92958] = { x = 2, y = 8  },
            [92952] = { x = 1, y = 9  },
            [92953] = { x = 0, y = 10 },
            [92951] = { x = 2, y = 10 },
            [92954] = { x = 1, y = 11 },
            [93010] = { x = 1, y = 12 },
            [93011] = { x = 1, y = 13 },
            [93012] = { x = 1, y = 14 },
        },
        connections = {
            [92895] = { 92897 },
            [92899] = { 92895 },
            [92900] = { 92899 },
            [92901] = { 92900 },
            [92904] = { 92901 },
            [92907] = { 92904 },
            [92955] = { 92907 },
            [92957] = { 92955 },
            [92958] = { 92955 },
            [92952] = { 92957, 92958 },
            [92953] = { 92952 },
            [92951] = { 92952 },
            [92954] = { 92953, 92951 },
            [93010] = { 92954 },
            [93011] = { 93010 },
            [93012] = { 93011 },
        },
    }

-- ─── Curated quest names (fallback) ────────────────────────────────────
-- Patch 12.0.7 is FUTURE content (the saga begins ~Jul 2026): the client has
-- the questline membership for 6050 but C_QuestLog.RequestLoadQuestByID can't
-- return TITLES for quests that aren't active yet, so nodes render as bare
-- "Quest #<id>". Util.QuestTitle uses this table only as a LAST resort — the
-- live API name always wins when available — so once 12.0.7 goes live these
-- become dead weight but never override real (localized) titles. Names are the
-- authoritative reference strings (English); they're replaced by the localized
-- API title the moment the client has it.
ns.CURATED_QUEST_NAMES = ns.CURATED_QUEST_NAMES or {}
local names = ns.CURATED_QUEST_NAMES
-- 6050 Legacy of the Amani
names[92897] = "The Preparations Are Complete"
names[92895] = "Hagar's Invitation"
names[92899] = "History Lesson"
names[92900] = "A Favor for Kinduru"
names[92901] = "Revisionist History"
names[92904] = "Return to Zul'Aman"
names[92907] = "Amani Answers"
names[92955] = "The Tablets of Numazon"
names[92957] = "There's the Rub"
names[92958] = "Brain Drain"
names[92952] = "Mission to Maisara"
names[92953] = "Memories of Malacrass"
names[92951] = "Digging Deeper"
names[92954] = "Maisara Caverns: Master of Souls"
names[93010] = "The Serpent Shrine"
names[93011] = "Legacy of the Amani"
names[93012] = "Dead End"
-- 6229-6232 boundary quests (the only ones the reference catalogs for these
-- raid-lead-up chains; their full questlines aren't in the client yet)
names[90690] = "Charge of the Vanguard"
names[88709] = "The Voidspire"
names[92520] = "Wake of the Darkwell"
names[88920] = "The Kaldorei"
names[88942] = "The Elves are Going to War"
names[88769] = "The Battle of the Bridge"
names[90748] = "Quel'Danas"
names[88710] = "March on Quel'Danas"

-- ─── Curated items (provisional, fallback only) ────────────────────────
-- 6229-6232 are the March on Quel'Danas raid lead-up — future 12.0.7 content
-- the client has no questline data for yet (GetQuestLineQuests = 0) and the
-- reference has no topology for either (items = {}). All that's authoritatively
-- known is each chain's start/end quests, so we list those as a PROVISIONAL
-- LINEAR chain. QuestLineSource:EnsureChainItems uses this ONLY when the live
-- API returns nothing; the moment Blizzard's client has the real questline, the
-- live data replaces this on the next load. Order is reference active→completed
-- (narratively start→end); 6229's two openers (90690/88709) are a best-effort
-- order (user-accepted) since the reference lists them as alternatives.
ns.CHAINGUIDE_CURATED_ITEMS = ns.CHAINGUIDE_CURATED_ITEMS or {}
ns.CHAINGUIDE_CURATED_ITEMS[6229] = { 90690, 88709, 92520 }  -- An Island of Fangs
ns.CHAINGUIDE_CURATED_ITEMS[6230] = { 88920, 88942 }         -- Ghosts of the Past
ns.CHAINGUIDE_CURATED_ITEMS[6231] = { 88769 }                -- Original Sin
ns.CHAINGUIDE_CURATED_ITEMS[6232] = { 90748, 88710 }         -- The Battle for Atal'Utek
