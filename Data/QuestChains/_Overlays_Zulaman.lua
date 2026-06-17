-- Data/QuestChains/_Overlays_Zulaman.lua
-- GENERATED DRAFT Zulaman zone overlays - verify in-game, then graduate
-- the verified ones into _Overlays.lua and drop them from here. Topology is
-- from authored reference data; layout is auto-laid to the centred-tree
-- convention. Only chains whose draft positions every LIVE quest (coverage-
-- clean per the dump) are emitted, so these should render without
-- stragglers - the open question per chain is purely whether the layout reads
-- well. Regenerate: python docs/_check_coverage.py docs/_zonedump_zulaman.txt --emit
local _, ns = ...
ns.CHAINGUIDE_OVERLAYS = ns.CHAINGUIDE_OVERLAYS or {}

    -- Healing the Spirit  (questline 5778, Zul'Aman)
    ns.CHAINGUIDE_OVERLAYS[5778] = {
        layout = {
            [91206] = { x = 1, y = 0  },
            [87254] = { x = 0, y = 1  },
            [87256] = { x = 2, y = 1  },
            [87267] = { x = 1, y = 2  },
            [87268] = { x = 1, y = 3  },
            [87317] = { x = 1, y = 4  },
            [92531] = { x = 1, y = 5  },
        },
        connections = {
            [87254] = { 91206 },
            [87256] = { 91206 },
            [87267] = { 87254, 87256 },
            [87268] = { 87267 },
            [87317] = { 87268 },
            [92531] = { 87317 },
        },
    }

    -- Unlikely Friends  (questline 5905, Zul'Aman)
    ns.CHAINGUIDE_OVERLAYS[5905] = {
        layout = {
            [93667] = { x = 1, y = 0  },
            [90481] = { x = 1, y = 1  },
            [90483] = { x = -0.5, y = 2  },
            [90485] = { x = 0.5, y = 2  },
            [90484] = { x = 1.5, y = 2  },
            [90482] = { x = 2.5, y = 2  },
            [90486] = { x = 1, y = 3  },
            [90568] = { x = 1, y = 4  },
        },
        connections = {
            [90481] = { 93667 },
            [90483] = { 90481 },
            [90485] = { 90481 },
            [90484] = { 90481 },
            [90482] = { 90481 },
            [90486] = { 90482 },
            [90568] = { 90483, 90485, 90484, 90486 },
        },
    }

    -- Vengeance for Tolbani  (questline 5939, Zul'Aman)
    ns.CHAINGUIDE_OVERLAYS[5939] = {
        layout = {
            [94867] = { x = 1, y = 0  },
            [91069] = { x = 0, y = 1  },
            [91070] = { x = 1, y = 1  },
            [91071] = { x = 2, y = 1  },
            [91556] = { x = 1, y = 2  },
        },
        connections = {
            [91069] = { 94867 },
            [91070] = { 94867 },
            [91071] = { 94867 },
            [91556] = { 91069, 91070, 91071 },
        },
    }

    -- A Venomous History  (questline 5950, Zul'Aman)
    ns.CHAINGUIDE_OVERLAYS[5950] = {
        layout = {
            [91406] = { x = 1, y = 0  },
            [91407] = { x = 1, y = 1  },
            [91563] = { x = 1, y = 2  },
            [91403] = { x = 0, y = 3  },
            [91404] = { x = 2, y = 3  },
            [91405] = { x = 1, y = 4  },
            [91408] = { x = 1, y = 5  },
            [91630] = { x = 1, y = 6  },
            [91409] = { x = 1, y = 7  },
            [91411] = { x = 1, y = 8  },
            [91412] = { x = 1, y = 9  },
            [91410] = { x = 1, y = 10 },
        },
        connections = {
            [91407] = { 91406 },
            [91563] = { 91407 },
            [91403] = { 91563 },
            [91404] = { 91563 },
            [91405] = { 91403, 91404 },
            [91408] = { 91405 },
            [91630] = { 91408 },
            [91409] = { 91630 },
            [91411] = { 91409 },
            [91412] = { 91411 },
            [91410] = { 91412 },
        },
    }

    -- The Voice of Nalorakk  (questline 5971, Zul'Aman)
    ns.CHAINGUIDE_OVERLAYS[5971] = {
        layout = {
            [91813] = { x = 1, y = 0  },
            [91747] = { x = 0, y = 1  },
            [91748] = { x = 2, y = 1  },
            [91749] = { x = 1, y = 2  },
            [93734] = { x = 1, y = 3  },
            [91750] = { x = 1, y = 4  },
        },
        connections = {
            [91747] = { 91813 },
            [91748] = { 91813 },
            [91749] = { 91747, 91748 },
            [93734] = { 91749 },
            [91750] = { 93734 },
        },
    }

    -- Something Vile This Way Comes  (questline 5975, Zul'Aman)
    ns.CHAINGUIDE_OVERLAYS[5975] = {
        layout = {
            [91833] = { x = 1, y = 0  },
            [91835] = { x = 0, y = 1  },
            [91836] = { x = 1, y = 1  },
            [91838] = { x = 2, y = 1  },
            [91840] = { x = 1, y = 2  },
            [91839] = { x = 1, y = 3  },
        },
        connections = {
            [91835] = { 91833 },
            [91836] = { 91833 },
            [91838] = { 91833 },
            [91840] = { 91835, 91836, 91838 },
            [91839] = { 91840 },
        },
    }

    -- Between Two Trolls  (questline 5981, Zul'Aman)
    ns.CHAINGUIDE_OVERLAYS[5981] = {
        layout = {
            [89230] = { x = 0, y = 0  },
            [89231] = { x = 2, y = 0  },
            [89233] = { x = 1, y = 1  },
        },
        connections = {
            [89233] = { 89230, 89231 },
        },
    }

    -- The Loa of Murlocs  (questline 5988, Zul'Aman)
    ns.CHAINGUIDE_OVERLAYS[5988] = {
        layout = {
            [92163] = { x = 1, y = 0  },
            [92164] = { x = 0, y = 1  },
            [92165] = { x = 1, y = 1  },
            [92166] = { x = 2, y = 1  },
            [92167] = { x = 1, y = 2  },
        },
        connections = {
            [92164] = { 92163 },
            [92165] = { 92163 },
            [92166] = { 92163 },
            [92167] = { 92164, 92165, 92166 },
        },
    }

    -- Reclaiming De Honor  (questline 6011, Zul'Aman)
    ns.CHAINGUIDE_OVERLAYS[6011] = {
        layout = {
            [92492] = { x = 1, y = 0  },
            [92493] = { x = 0, y = 1  },
            [92495] = { x = 2, y = 1  },
            [92496] = { x = 0, y = 3  },
            [92497] = { x = 2, y = 3  },
            [92499] = { x = 1, y = 4  },
        },
        connections = {
            [92493] = { 92492 },
            [92495] = { 92492 },
            [92496] = { 92493, 92495 },
            [92497] = { 92493, 92495 },
            [92499] = { 92496, 92497 },
        },
    }

    -- Bitter Honor  (questline 6042, Zul'Aman)
    ns.CHAINGUIDE_OVERLAYS[6042] = {
        layout = {
            [93093] = { x = 0, y = 0  },
            [93094] = { x = 2, y = 0  },
            [93095] = { x = 1, y = 1  },
            [93096] = { x = 1, y = 2  },
        },
        connections = {
            [93095] = { 93093, 93094 },
            [93096] = { 93095 },
        },
    }

    -- River Walkers of the Prowl  (questline 6045, Zul'Aman)
    ns.CHAINGUIDE_OVERLAYS[6045] = {
        layout = {
            [93257] = { x = 1, y = 0  },
            [93258] = { x = 1, y = 1  },
            [93259] = { x = 0, y = 2  },
            [93260] = { x = 2, y = 2  },
            [93261] = { x = 1, y = 3  },
        },
        connections = {
            [93258] = { 93257 },
            [93259] = { 93258 },
            [93260] = { 93258 },
            [93261] = { 93259, 93260 },
        },
    }

    -- Sawdust to Sawdust  (questline 6048, Zul'Aman)
    ns.CHAINGUIDE_OVERLAYS[6048] = {
        layout = {
            [88985] = { x = 1, y = 0  },
            [88986] = { x = 0, y = 1  },
            [88987] = { x = 2, y = 1  },
            [88988] = { x = 1, y = 2  },
            [88989] = { x = 1, y = 3  },
        },
        connections = {
            [88986] = { 88985 },
            [88987] = { 88985 },
            [88988] = { 88986, 88987 },
            [88989] = { 88988 },
        },
    }

    -- Bloodstains  (questline 6052, Zul'Aman)
    ns.CHAINGUIDE_OVERLAYS[6052] = {
        layout = {
            [93440] = { x = 1, y = 0  },
            [93432] = { x = 0, y = 1  },
            [93433] = { x = 2, y = 1  },
            [93435] = { x = 0, y = 3  },
            [93436] = { x = 2, y = 3  },
            [93437] = { x = 1, y = 4  },
        },
        connections = {
            [93432] = { 93440 },
            [93433] = { 93440 },
            [93435] = { 93432, 93433 },
            [93436] = { 93432, 93433 },
            [93437] = { 93435, 93436 },
        },
    }

