-- Data/QuestChains/_QuestLineRouting.lua
-- Authoritative list of every questline we expose, plus its category and
-- display name. The chain guide registers a chain for every entry here
-- regardless of whether the player has completed it — Blizzard's
-- C_QuestLine.GetAvailableQuestLines only returns *available* questlines,
-- so we couldn't surface completed storylines without this list.
--
-- Loaded AFTER _Index.lua so ns.CAT.* is available.

local _, ns = ...

ns.QUESTLINE_ROUTING = {
    -- Eversong Woods
    [5719] = { cat = ns.CAT.EVERSONG_WOODS, name = "Whispers in the Twilight" },
    [5720] = { cat = ns.CAT.EVERSONG_WOODS, name = "Shadowfall" },
    [5721] = { cat = ns.CAT.EVERSONG_WOODS, name = "Ripple Effects" },
    [5931] = { cat = ns.CAT.EVERSONG_WOODS, name = "Fear and Fel" },
    [6020] = { cat = ns.CAT.EVERSONG_WOODS, name = "Flowers for Amalthea" },
    [5949] = { cat = ns.CAT.EVERSONG_WOODS, name = "Sunbath, Take Me Away" },
    [5805] = { cat = ns.CAT.EVERSONG_WOODS, name = "Port Detective" },
    [5812] = { cat = ns.CAT.EVERSONG_WOODS, name = "Lesser Evil" },
    [5898] = { cat = ns.CAT.EVERSONG_WOODS, name = "One Adventurous Hatchling" },
    [5969] = { cat = ns.CAT.EVERSONG_WOODS, name = "Far Striding" },
    [5989] = { cat = ns.CAT.EVERSONG_WOODS, name = "Tailor Troubles" },
    [6018] = { cat = ns.CAT.EVERSONG_WOODS, name = "Blinding Sun" },
    [5993] = { cat = ns.CAT.EVERSONG_WOODS, name = "Runestone Rumbles" },
    [5908] = { cat = ns.CAT.EVERSONG_WOODS, name = "Paladin Rescue" },
    [5937] = { cat = ns.CAT.EVERSONG_WOODS, name = "How to Train Your Protege" },
    [6030] = { cat = ns.CAT.EVERSONG_WOODS, name = "Scootin' Through Silvermoon" },
    [5781] = { cat = ns.CAT.EVERSONG_WOODS, name = "Aspiring Academic" },
    [5784] = { cat = ns.CAT.EVERSONG_WOODS, name = "The Drinking Debt" },
    [5804] = { cat = ns.CAT.EVERSONG_WOODS, name = "Theft Tracking" },
    [5958] = { cat = ns.CAT.EVERSONG_WOODS, name = "Daggerspine Landing" },
    -- Zul'Aman
    [5722] = { cat = ns.CAT.ZULAMAN, name = "Dis Was Our Land" },
    [5723] = { cat = ns.CAT.ZULAMAN, name = "Path of De Hashey" },
    [5938] = { cat = ns.CAT.ZULAMAN, name = "Where War Slumbers" },
    [5724] = { cat = ns.CAT.ZULAMAN, name = "De Amani Never Die" },
    [5778] = { cat = ns.CAT.ZULAMAN, name = "Healing the Spirit" },
    [6048] = { cat = ns.CAT.ZULAMAN, name = "Sawdust to Sawdust" },
    [5981] = { cat = ns.CAT.ZULAMAN, name = "Between Two Trolls" },
    [5901] = { cat = ns.CAT.ZULAMAN, name = "Sorrowing Kin" },
    [5905] = { cat = ns.CAT.ZULAMAN, name = "Unlikely Friends" },
    [5971] = { cat = ns.CAT.ZULAMAN, name = "The Voice of Nalorakk" },
    [6011] = { cat = ns.CAT.ZULAMAN, name = "Reclaiming De Honor" },
    [5939] = { cat = ns.CAT.ZULAMAN, name = "Vengeance for Tolbani" },
    [5988] = { cat = ns.CAT.ZULAMAN, name = "The Loa of Murlocs" },
    [5999] = { cat = ns.CAT.ZULAMAN, name = "No Fear" },
    [6042] = { cat = ns.CAT.ZULAMAN, name = "Bitter Honor" },
    [6055] = { cat = ns.CAT.ZULAMAN, name = "The Sound of Her Voice" },
    [5950] = { cat = ns.CAT.ZULAMAN, name = "A Venomous History" },
    [6044] = { cat = ns.CAT.ZULAMAN, name = "Beyond the Walls" },
    [5975] = { cat = ns.CAT.ZULAMAN, name = "Something Vile This Way Comes" },
    [6045] = { cat = ns.CAT.ZULAMAN, name = "River Walkers of the Prowl" },
    [6052] = { cat = ns.CAT.ZULAMAN, name = "Bloodstains" },
    -- Voidstorm
    [5728] = { cat = ns.CAT.VOIDSTORM, name = "Into the Abyss" },
    [5729] = { cat = ns.CAT.VOIDSTORM, name = "The Night's Veil" },
    [5730] = { cat = ns.CAT.VOIDSTORM, name = "Dawn of Reckoning" },
    [6010] = { cat = ns.CAT.VOIDSTORM, name = "The Void Peers Back" },
    [5943] = { cat = ns.CAT.VOIDSTORM, name = "Shadow Puppets" },
    [5933] = { cat = ns.CAT.VOIDSTORM, name = "The Nethersent" },
    [5962] = { cat = ns.CAT.VOIDSTORM, name = "The Nightbreaker" },
    [6028] = { cat = ns.CAT.VOIDSTORM, name = "Pathogenic Problem" },
    [6013] = { cat = ns.CAT.VOIDSTORM, name = "A Voice Inside" },
    [5987] = { cat = ns.CAT.VOIDSTORM, name = "Shadowguard's Shadow" },
    [6019] = { cat = ns.CAT.VOIDSTORM, name = "A Gift Given Freely" },
    [5964] = { cat = ns.CAT.VOIDSTORM, name = "Breaking the Triad" },
    [6022] = { cat = ns.CAT.VOIDSTORM, name = "Go Low, Go Loud" },
    [6017] = { cat = ns.CAT.VOIDSTORM, name = "Secrets in the Dark" },
    [6014] = { cat = ns.CAT.VOIDSTORM, name = "Oaths to Family" },
    [5961] = { cat = ns.CAT.VOIDSTORM, name = "To Be Changed" },
    [5936] = { cat = ns.CAT.VOIDSTORM, name = "A Dance with the Devil" },
    [6012] = { cat = ns.CAT.VOIDSTORM, name = "A Domanaar's Best Friend" },
    [6001] = { cat = ns.CAT.VOIDSTORM, name = "A More Potent Foe" },
    -- Harandar
    [5725] = { cat = ns.CAT.HARANDAR, name = "Of Caves and Cradles" },
    [5726] = { cat = ns.CAT.HARANDAR, name = "Call of the Goddess" },
    [5907] = { cat = ns.CAT.HARANDAR, name = "A Goblin in Harandar" },
    [5909] = { cat = ns.CAT.HARANDAR, name = "The Legend of Aln'sharan" },
    [5935] = { cat = ns.CAT.HARANDAR, name = "Late Bloomers" },
    [5952] = { cat = ns.CAT.HARANDAR, name = "The Greenspeaker's Vigil" },
    [5944] = { cat = ns.CAT.HARANDAR, name = "Peril Among Petals" },
    [5960] = { cat = ns.CAT.HARANDAR, name = "Haranir Never Say Die" },
    [5966] = { cat = ns.CAT.HARANDAR, name = "Harandar's Kitchen" },
    [6036] = { cat = ns.CAT.HARANDAR, name = "Silence at Fungara Village" },
    [5977] = { cat = ns.CAT.HARANDAR, name = "Cultivating Hope" },
    [6039] = { cat = ns.CAT.HARANDAR, name = "Hunter's Rights" },
    [6038] = { cat = ns.CAT.HARANDAR, name = "A Palette of Feelings" },
    [6040] = { cat = ns.CAT.HARANDAR, name = "Predator Reintroduction" },
    [6032] = { cat = ns.CAT.HARANDAR, name = "Bloomtown" },
    [5910] = { cat = ns.CAT.HARANDAR, name = "The Grudge Pit" },
    [5932] = { cat = ns.CAT.HARANDAR, name = "Trials of the Shulka" },
    -- Arator
    [5750] = { cat = ns.CAT.ARATOR, name = "The Path of Light" },
    [5751] = { cat = ns.CAT.ARATOR, name = "Regrets of the Past" },
    -- Revelations (patch 12.0.7): post-campaign saga gated behind Voidstorm's
    -- Dawn of Reckoning. 6050 "Legacy of the Amani" has an authored branching
    -- overlay (_Overlays_Revelations.lua); 6229-6232 (the March on Quel'Danas
    -- raid lead-up) have no reference topology yet → render as linear API spines.
    [6050] = { cat = ns.CAT.REVELATIONS, name = "Legacy of the Amani" },
    [6229] = { cat = ns.CAT.REVELATIONS, name = "An Island of Fangs" },
    [6230] = { cat = ns.CAT.REVELATIONS, name = "Ghosts of the Past" },
    [6231] = { cat = ns.CAT.REVELATIONS, name = "Original Sin" },
    [6232] = { cat = ns.CAT.REVELATIONS, name = "The Battle for Atal'Utek" },
    -- Midnight Campaign: intentionally NOT routed here. The campaign spine
    -- is sourced live from Blizzard's campaign API in
    -- Modules/ChainGuide/CampaignSource.lua (C_CampaignInfo → 17 ordered
    -- chapters), so it always matches the player's real in-game campaign.
    -- The previous hand-picked list here was wrong: verified in-game,
    -- 5792/5793/5795/5797/5798 (Foothold, The Voidspire, Gathering of the
    -- Elves, March on Quel'Danas, Dawn of a New Well) are NOT chapters of
    -- campaign 270, and chapter 5727 "Emergence" was missing entirely.
    -- 5811 "The Light's Summons" / 5979 "The Darkening Sky" ARE chapters
    -- (1 and 17) and now come from the API.
}
