-- Data/QuestChains/_Overlays_Voidstorm.lua
-- GENERATED DRAFT Voidstorm zone overlays - verify in-game, then graduate
-- the verified ones into _Overlays.lua and drop them from here. Topology is
-- from authored reference data; layout is auto-laid to the centred-tree
-- convention. Only chains whose draft positions every LIVE quest (coverage-
-- clean per the dump) are emitted, so these should render without
-- stragglers - the open question per chain is purely whether the layout reads
-- well. Regenerate: python docs/_check_coverage.py docs/_zonedump_voidstorm.txt --emit
local _, ns = ...
ns.CHAINGUIDE_OVERLAYS = ns.CHAINGUIDE_OVERLAYS or {}

    -- The Nethersent  (questline 5933, Voidstorm)
    ns.CHAINGUIDE_OVERLAYS[5933] = {
        layout = {
            [90782] = { x = 1, y = 0  },
            [90866] = { x = 1, y = 1  },
            [90872] = { x = 1, y = 2  },
            [90873] = { x = 0, y = 3  },
            [90874] = { x = 2, y = 3  },
            [90875] = { x = 1, y = 4  },
        },
        connections = {
            [90866] = { 90782 },
            [90872] = { 90866 },
            [90873] = { 90872 },
            [90874] = { 90872 },
            [90875] = { 90873, 90874 },
        },
    }

    -- A Dance with the Devil  (questline 5936, Voidstorm)
    ns.CHAINGUIDE_OVERLAYS[5936] = {
        layout = {
            [90914] = { x = 1, y = 0  },
            [90915] = { x = 1, y = 1  },
            [90916] = { x = 1, y = 2  },
            [90917] = { x = 0, y = 3  },
            [90918] = { x = 2, y = 3  },
            [90919] = { x = 1, y = 4  },
            [90920] = { x = 1, y = 5  },
            [90923] = { x = 0, y = 6  },
            [90922] = { x = 2, y = 6  },
            [90924] = { x = 1, y = 7  },
        },
        connections = {
            [90915] = { 90914 },
            [90916] = { 90915 },
            [90917] = { 90916 },
            [90918] = { 90916 },
            [90919] = { 90917, 90918 },
            [90920] = { 90919 },
            [90923] = { 90920 },
            [90922] = { 90920 },
            [90924] = { 90923, 90922 },
        },
    }

    -- Shadow Puppets  (questline 5943, Voidstorm)  [tail auto-appended: 92641 - verify]
    ns.CHAINGUIDE_OVERLAYS[5943] = {
        layout = {
            [91145] = { x = 1, y = 0  },
            [91146] = { x = 0, y = 1  },
            [91147] = { x = 2, y = 1  },
            [91148] = { x = 1, y = 2  },
            [91149] = { x = 1, y = 3  },
            [92641] = { x = 1, y = 4  },
        },
        connections = {
            [91146] = { 91145 },
            [91147] = { 91145 },
            [91148] = { 91146, 91147 },
            [91149] = { 91148 },
            [92641] = { 91149 },
        },
    }

    -- To Be Changed  (questline 5961, Voidstorm)
    ns.CHAINGUIDE_OVERLAYS[5961] = {
        layout = {
            [91533] = { x = 1, y = 0  },
            [91535] = { x = 0, y = 1  },
            [91536] = { x = 2, y = 1  },
            [91537] = { x = 1, y = 2  },
            [91541] = { x = 1, y = 3  },
            [91542] = { x = 1, y = 4  },
            [91544] = { x = 0, y = 5  },
            [91543] = { x = 1, y = 5  },
            [91963] = { x = 2, y = 5  },
            [91545] = { x = 1, y = 6  },
            [91546] = { x = 1, y = 7  },
        },
        connections = {
            [91535] = { 91533 },
            [91536] = { 91533 },
            [91537] = { 91535, 91536 },
            [91541] = { 91537 },
            [91542] = { 91541 },
            [91544] = { 91542 },
            [91543] = { 91542 },
            [91963] = { 91542 },
            [91545] = { 91544, 91543, 91963 },
            [91546] = { 91545 },
        },
    }

    -- The Nightbreaker  (questline 5962, Voidstorm)
    ns.CHAINGUIDE_OVERLAYS[5962] = {
        layout = {
            [90910] = { x = 1, y = 0  },
            [91339] = { x = 0, y = 1  },
            [91340] = { x = 2, y = 1  },
            [91341] = { x = 1, y = 2  },
            [91343] = { x = 1, y = 3  },
        },
        connections = {
            [91339] = { 90910 },
            [91340] = { 90910 },
            [91341] = { 91339, 91340 },
            [91343] = { 91341 },
        },
    }

    -- Breaking the Triad  (questline 5964, Voidstorm)
    ns.CHAINGUIDE_OVERLAYS[5964] = {
        layout = {
            [91565] = { x = 1, y = 0  },
            [91566] = { x = 1, y = 0  },
            [91583] = { x = 0, y = 1  },
            [94845] = { x = 0, y = 1  },
            [91597] = { x = 2, y = 1  },
            [94844] = { x = 2, y = 1  },
            [91598] = { x = 0, y = 3  },
            [94848] = { x = 0, y = 3  },
            [91599] = { x = 2, y = 3  },
            [94849] = { x = 2, y = 3  },
            [91600] = { x = 1, y = 4  },
            [94855] = { x = 1, y = 4  },
            [91603] = { x = 0, y = 5  },
            [91605] = { x = 2, y = 5  },
            [91606] = { x = 1, y = 6  },
            [91694] = { x = 1, y = 7  },
        },
        connections = {
            [91583] = { 91566, 91565 },
            [94845] = { 91566, 91565 },
            [91597] = { 91566, 91565 },
            [94844] = { 91566, 91565 },
            [91598] = { 94845, 91583, 94844, 91597 },
            [94848] = { 94845, 91583, 94844, 91597 },
            [91599] = { 94845, 91583, 94844, 91597 },
            [94849] = { 94845, 91583, 94844, 91597 },
            [91600] = { 94848, 91598, 94849, 91599 },
            [94855] = { 94848, 91598, 94849, 91599 },
            [91603] = { 94855, 91600 },
            [91605] = { 94855, 91600 },
            [91606] = { 91603, 91605 },
            [91694] = { 91606 },
        },
    }

    -- A More Potent Foe  (questline 6001, Voidstorm)
    ns.CHAINGUIDE_OVERLAYS[6001] = {
        layout = {
            [92505] = { x = 1, y = 0  },
            [92506] = { x = 1, y = 1  },
            [92507] = { x = 1, y = 2  },
            [92508] = { x = 0, y = 3  },
            [92509] = { x = 2, y = 3  },
            [92510] = { x = 1, y = 4  },
            [92511] = { x = 1, y = 5  },
            [92512] = { x = 1, y = 6  },
        },
        connections = {
            [92506] = { 92505 },
            [92507] = { 92506 },
            [92508] = { 92507 },
            [92509] = { 92507 },
            [92510] = { 92508, 92509 },
            [92511] = { 92510 },
            [92512] = { 92511 },
        },
    }

    -- The Void Peers Back  (questline 6010, Voidstorm)
    ns.CHAINGUIDE_OVERLAYS[6010] = {
        layout = {
            [88755] = { x = 1, y = 0  },
            [87388] = { x = 0, y = 1  },
            [87391] = { x = 2, y = 1  },
            [88653] = { x = 0, y = 3  },
            [87672] = { x = 2, y = 3  },
            [88708] = { x = 1, y = 4  },
        },
        connections = {
            [87388] = { 88755 },
            [87391] = { 88755 },
            [88653] = { 87388, 87391 },
            [87672] = { 87388, 87391 },
            [88708] = { 88653, 87672 },
        },
    }

    -- Oaths to Family  (questline 6014, Voidstorm)
    ns.CHAINGUIDE_OVERLAYS[6014] = {
        layout = {
            [90838] = { x = 1, y = 0  },
            [90844] = { x = 0, y = 1  },
            [90845] = { x = 2, y = 1  },
            [90847] = { x = 1, y = 2  },
            [90848] = { x = 1, y = 3  },
            [90851] = { x = 0, y = 4  },
            [90852] = { x = 2, y = 4  },
            [93396] = { x = 1, y = 5  },
            [90858] = { x = 1, y = 6  },
            [90860] = { x = 1, y = 7  },
        },
        connections = {
            [90844] = { 90838 },
            [90845] = { 90838 },
            [90847] = { 90844, 90845 },
            [90848] = { 90847 },
            [90851] = { 90848 },
            [90852] = { 90848 },
            [93396] = { 90851, 90852 },
            [90858] = { 93396 },
            [90860] = { 90858 },
        },
    }

    -- A Gift Given Freely  (questline 6019, Voidstorm)
    ns.CHAINGUIDE_OVERLAYS[6019] = {
        layout = {
            [92603] = { x = 1, y = 0  },
            [92604] = { x = 0, y = 1  },
            [92605] = { x = 2, y = 1  },
            [92606] = { x = 1, y = 2  },
            [92607] = { x = 1, y = 3  },
        },
        connections = {
            [92604] = { 92603 },
            [92605] = { 92603 },
            [92606] = { 92604, 92605 },
            [92607] = { 92606 },
        },
    }

    -- Go Low, Go Loud  (questline 6022, Voidstorm)
    ns.CHAINGUIDE_OVERLAYS[6022] = {
        layout = {
            [92657] = { x = 1, y = 0  },
            [92658] = { x = 0, y = 1  },
            [92659] = { x = 2, y = 1  },
            [92660] = { x = 0, y = 3  },
            [92661] = { x = 2, y = 3  },
            [92662] = { x = 1, y = 4  },
        },
        connections = {
            [92658] = { 92657 },
            [92659] = { 92657 },
            [92660] = { 92658, 92659 },
            [92661] = { 92658, 92659 },
            [92662] = { 92660, 92661 },
        },
    }

    -- Pathogenic Problem  (questline 6028, Voidstorm)
    ns.CHAINGUIDE_OVERLAYS[6028] = {
        layout = {
            [91557] = { x = 1, y = 0  },
            [91558] = { x = 0, y = 1  },
            [91559] = { x = 2, y = 1  },
            [91560] = { x = 0, y = 3  },
            [93801] = { x = 2, y = 3  },
            [91561] = { x = 1, y = 4  },
        },
        connections = {
            [91558] = { 91557 },
            [91559] = { 91557 },
            [91560] = { 91558, 91559 },
            [93801] = { 91558, 91559 },
            [91561] = { 91560, 93801 },
        },
    }

