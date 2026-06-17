-- Data/QuestChains/_Overlays_Harandar.lua
-- GENERATED DRAFT Harandar zone overlays - verify in-game, then graduate
-- the verified ones into _Overlays.lua and drop them from here. Topology is
-- from authored reference data; layout is auto-laid to the centred-tree
-- convention. Only chains whose draft positions every LIVE quest (coverage-
-- clean per the dump) are emitted, so these should render without
-- stragglers - the open question per chain is purely whether the layout reads
-- well. Regenerate: python docs/_check_coverage.py docs/_zonedump_harandar.txt --emit
local _, ns = ...
ns.CHAINGUIDE_OVERLAYS = ns.CHAINGUIDE_OVERLAYS or {}

    -- The Legend of Aln'sharan  (questline 5909, Harandar)
    ns.CHAINGUIDE_OVERLAYS[5909] = {
        layout = {
            [90467] = { x = 0, y = 0  },
            [90468] = { x = 2, y = 0  },
            [90469] = { x = 1, y = 1  },
            [90470] = { x = 1, y = 2  },
            [90474] = { x = 1, y = 3  },
        },
        connections = {
            [90469] = { 90467, 90468 },
            [90470] = { 90469 },
            [90474] = { 90470 },
        },
    }

    -- The Grudge Pit  (questline 5910, Harandar)
    ns.CHAINGUIDE_OVERLAYS[5910] = {
        layout = {
            [90615] = { x = 1, y = 0  },
            [90616] = { x = 1, y = 1  },
            [90617] = { x = 1, y = 2  },
            [90619] = { x = 1, y = 3  },
            [91450] = { x = 1, y = 4  },
            [91270] = { x = 1, y = 5  },
            [90620] = { x = 1, y = 6  },
            [90621] = { x = 1, y = 7  },
            [92616] = { x = 0, y = 8  },
            [92617] = { x = 1, y = 8  },
            [92618] = { x = 2, y = 8  },
            [90622] = { x = 1, y = 9  },
        },
        connections = {
            [90616] = { 90615 },
            [90617] = { 90616 },
            [90619] = { 90617 },
            [91450] = { 90619 },
            [91270] = { 91450 },
            [90620] = { 91270 },
            [90621] = { 90620 },
            [92616] = { 90621 },
            [92617] = { 90621 },
            [92618] = { 90621 },
            [90622] = { 92616, 92617, 92618 },
        },
    }

    -- Trials of the Shulka  (questline 5932, Harandar)
    ns.CHAINGUIDE_OVERLAYS[5932] = {
        layout = {
            [90824] = { x = 1, y = 0  },
            [90826] = { x = 0, y = 1  },
            [90827] = { x = 2, y = 1  },
            [90829] = { x = 1, y = 2  },
            [90830] = { x = 0, y = 3  },
            [90831] = { x = 2, y = 3  },
            [90832] = { x = 1, y = 4  },
            [90833] = { x = 1, y = 5  },
            [90834] = { x = 1, y = 6  },
        },
        connections = {
            [90826] = { 90824 },
            [90827] = { 90824 },
            [90829] = { 90826, 90827 },
            [90830] = { 90829 },
            [90831] = { 90829 },
            [90832] = { 90830, 90831 },
            [90833] = { 90832 },
            [90834] = { 90833 },
        },
    }

    -- Late Bloomers  (questline 5935, Harandar)
    ns.CHAINGUIDE_OVERLAYS[5935] = {
        layout = {
            [90537] = { x = 1, y = 0  },
            [90540] = { x = 0, y = 1  },
            [90569] = { x = 2, y = 1  },
            [90963] = { x = 1, y = 2  },
            [90601] = { x = 0, y = 3  },
            [90602] = { x = 2, y = 3  },
        },
        connections = {
            [90540] = { 90537 },
            [90569] = { 90537 },
            [90963] = { 90540, 90569 },
            [90601] = { 90963 },
            [90602] = { 90963 },
        },
    }

    -- Peril Among Petals  (questline 5944, Harandar)
    ns.CHAINGUIDE_OVERLAYS[5944] = {
        layout = {
            [91063] = { x = 1, y = 0  },
            [91065] = { x = 0, y = 1  },
            [91085] = { x = 1, y = 1  },
            [91086] = { x = 2, y = 1  },
            [91088] = { x = 1, y = 2  },
            [91136] = { x = 1, y = 3  },
        },
        connections = {
            [91065] = { 91063 },
            [91085] = { 91063 },
            [91086] = { 91063 },
            [91088] = { 91065, 91085, 91086 },
            [91136] = { 91088 },
        },
    }

    -- The Greenspeaker's Vigil  (questline 5952, Harandar)
    ns.CHAINGUIDE_OVERLAYS[5952] = {
        layout = {
            [91346] = { x = 1, y = 0  },
            [91359] = { x = 0, y = 1  },
            [91360] = { x = 2, y = 1  },
            [91361] = { x = 1, y = 2  },
        },
        connections = {
            [91359] = { 91346 },
            [91360] = { 91346 },
            [91361] = { 91359, 91360 },
        },
    }

    -- Haranir Never Say Die  (questline 5960, Harandar)
    ns.CHAINGUIDE_OVERLAYS[5960] = {
        layout = {
            [91550] = { x = 1, y = 0  },
            [91551] = { x = 0, y = 1  },
            [91552] = { x = 2, y = 1  },
            [91553] = { x = 1, y = 2  },
        },
        connections = {
            [91551] = { 91550 },
            [91552] = { 91550 },
            [91553] = { 91551, 91552 },
        },
    }

    -- Harandar's Kitchen  (questline 5966, Harandar)
    ns.CHAINGUIDE_OVERLAYS[5966] = {
        layout = {
            [91585] = { x = 0, y = 0  },
            [91586] = { x = 1, y = 0  },
            [91587] = { x = 2, y = 0  },
            [91588] = { x = 1, y = 1  },
            [91589] = { x = 1, y = 2  },
        },
        connections = {
            [91588] = { 91585, 91586, 91587 },
            [91589] = { 91588 },
        },
    }

    -- Bloomtown  (questline 6032, Harandar)
    ns.CHAINGUIDE_OVERLAYS[6032] = {
        layout = {
            [92732] = { x = 1, y = 0  },
            [92736] = { x = 1, y = 1  },
            [92737] = { x = 0, y = 2  },
            [92738] = { x = 2, y = 2  },
            [92739] = { x = 1, y = 3  },
        },
        connections = {
            [92736] = { 92732 },
            [92737] = { 92736 },
            [92738] = { 92736 },
            [92739] = { 92737, 92738 },
        },
    }

    -- Silence at Fungara Village  (questline 6036, Harandar)
    ns.CHAINGUIDE_OVERLAYS[6036] = {
        layout = {
            [91375] = { x = 1, y = 0  },
            [91376] = { x = 0, y = 1  },
            [91377] = { x = 2, y = 1  },
            [91378] = { x = 0, y = 3  },
            [91379] = { x = 2, y = 3  },
            [91381] = { x = 1, y = 4  },
        },
        connections = {
            [91376] = { 91375 },
            [91377] = { 91375 },
            [91378] = { 91376, 91377 },
            [91379] = { 91376, 91377 },
            [91381] = { 91378, 91379 },
        },
    }

    -- Predator Reintroduction  (questline 6040, Harandar)
    ns.CHAINGUIDE_OVERLAYS[6040] = {
        layout = {
            [92864] = { x = 0, y = 0  },
            [92865] = { x = 2, y = 0  },
            [92866] = { x = 1, y = 1  },
        },
        connections = {
            [92866] = { 92864, 92865 },
        },
    }

