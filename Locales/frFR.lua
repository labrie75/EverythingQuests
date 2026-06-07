-- Locales/frFR.lua
-- French (frFR) translations for Everything Quests.
--
-- Bundled translations live below as `L["key"] = "value"` lines
-- (contributed by the community). Untranslated phrases simply fall back
-- to English via the metatable in Locales/enUS.lua.
--
-- NOTE: do NOT add a --@localization@ packager token here. CurseForge
-- localization is not enabled on this project, so the BigWigs packager's
-- localization export step fails the release build (errorCode 1002 "You do not
-- have permission to manage localization on this project"). Translations are
-- bundled directly as the L["..."] lines below instead.
-- To add another language, copy this file, rename it to the locale code
-- (e.g. deDE.lua), change the locale code below, and add it to the .toc.
--
-- GENERATED: produced by docs/_merge_frfr.py (additive). Re-run after each
-- translation batch; ordering mirrors Locales/enUS.lua.

if GetLocale() ~= "frFR" then return end

local _, ns = ...
local L = ns.L


-- ─── Options/TabGeneral.lua ───
L["General"] = "Général"
L["Show quest pins on the world map  |cffaaaaaa(EQ's red \"!\" / \"?\" rings)|r"] = "Montrer les marqueurs de quête sur la carte du monde  |cffaaaaaa(Anneaux rouges \"!\" / \"?\" de EQ)|r"
L["These are the round red markers Everything Quests puts on the big world map for quests you've already picked up (the ones in your quest log). A red \"!\" means \"go here for this quest's next step.\" A red \"?\" means \"this quest is done \226\128\148 go here to turn it in.\" Quests you haven't accepted yet keep the game's own yellow \"!\" markers; EQ does not change those. Uncheck this box and all of EQ's red markers go away."] = "Ce sont les marqueurs ronds rouges qu'Everything Quests indique sur la carte du monde pour les quêtes déjà présentes dans votre journal de quêtes. Un \"!\" rouge signifie \"Allez ici pour la prochaine étape de la quête.\" Un \"?\" rouge signifie \"cette quête est accomplie \226\128\148 venez ici pour la rendre.\" Les quêtes que vous n'avez pas encore accepté conservent le marqueur \"!\" jaune du jeu; EQ ne les change pas. Décochez cette case pour désactiver tous les marqueurs rouges d'EQ."
L["Lock tracker  |cffaaaaaa(disable drag-to-move and resize)|r"] = "Verrouiller le module de suivi  |cffaaaaaa(Désactive le glisser-déposer et le recadrage)|r"
L["Hide tracker in combat"] = "Cacher le module de suivi pendant le combat"
L["Hide tracker in instances  |cffaaaaaa(raids, dungeons, delves)|r"] = "Cacher le module de suivi en instances  |cffaaaaaa(raids, donjons, gouffres)|r"
L["Hide tracker when world map is open"] = "Cacher le module de suivi quand la carte du monde est ouverte"
L["Auto-track accepted quests  |cffaaaaaa(matches Blizzard's default)|r"] = "Suivre automatiquement les quêtes acceptées  |cffaaaaaa(correspond au choix par défaut de Blizzard)|r"
L["Auto-accept quests  |cffaaaaaa(hold Alt to pause)|r"] = "Accepter les quêtes automatiquement"
L["Auto-turn-in quests  |cffaaaaaa(skips reward-choice screens)|r"] = "Rendre les quêtes automatiquement"
L["Keep focused quest after relog  |cffaaaaaa(restores the waypoint arrow)|r"] = "Conserver la quête suivie à la reconnexion  |cffaaaaaa(restaure la flêche directionnelle)|r"
L["Quest icons on nameplates  |cffaaaaaa(shows the \"!\" + count on objective mobs)|r"] = "Icônes de quête sur les cartes de nom  |cffaaaaaa(montre le \"!\" + décompte sur les pnj liés à l'objectif)|r"
L["Show minimap button"] = "Afficher le boûton de la mini-carte"
L["Reset all settings"] = "Réinitialiser les réglages"
L["Reset every Everything Quests setting to defaults?"] = "Réinitialiser tous les réglages de Everything Quest par défaut?"
L["Reset"] = "Réinitialiser"
L["Cancel"] = "Annuler"
L["Profiles"] = "Profils"
L["Active profile"] = "Activer Profil"
L["New Profile"] = "Nouveau Profil"
L["Profile name:"] = "Nom de Profil"
L["Create"] = "Créer"
L["Switching profiles reloads the UI. Profiles are shared across characters; use them to keep different setups (e.g. raid vs solo). |cffEBB706New Profile|r prompts for a name and creates it on the spot."] = "Changer de profil recharge l'IU. Les profils sont partagés par tous vos personnages; utilisez-les pour conserver différents modèles (comme raid ou solo). |cffEBB706Nouveau profil|r demande un nom et crée le profil dans la foulée."
L["Slash commands"] = "Commandes slash"
L["/eqs\n/everythingquests\n\n|cff999999Both open this options window.|r\n\n/eqs whatsnew\n\n|cff999999Show what's new in the latest update.|r\n\n/eqs session\n\n|cff999999Show a recap of your current play session.|r"] = "/eqs\n/everythingquests\n\n|cff999999Ces deux commandes ouvre la fenêtre de configuration actuelle|r\n\n/eqs whatsnew\n\n|cff999999Show nouveautés de la dernière mise-à-jour.|r\n\n/eqs session\n\n|cff999999Show un récapitulatif de votre session de jeu actuelle.|r"

-- ─── Options/TabTracker.lua ───
L["Zone"] = "Zone"
L["Status"] = "Statut"
L["Type"] = "Type"
L["Level"] = "Niveau"
L["Distance"] = "Distance"
L["Recent"] = "Récent"
L["Manual"] = "Manuel"
L["Normal quests"] = "Quête normale"
L["Daily quests"] = "Quête journalière"
L["Weekly quests"] = "Quête hebdomadaire"
L["Campaign quests"] = "Quête de Campagne"
L["World quests"] = "Quête du monde ouvert"
L["Show only quests in current zone"] = "Montrer uniquement les quêtes dans la zone actuelle"
L["Tracker"] = "Module"
L["On-Screen Tracker"] = "Module de suivi"
L["Show only watched quests  |cffaaaaaa(matches Blizzard's default tracker)|r"] = "Montrer uniquement les quêtes visibles  |cffaaaaaa(correspond au réglage par défaut de Blizzard)|r"
L["Simplify Mode  |cffaaaaaa(show only the first incomplete objective per quest)|r"] = "Mode simplifié  |cffaaaaaa(montre uniquement les premiers objectifs incomplets de chaque quête)|r"
L["Sort Order"] = "Ordre de tri"
L["|cffaaaaaaDrag and drop the quests in the tracker to reorder them however you like.|r"] = "|cffaaaaaaGlisser-déposer les quêtes dans le module de suivi pour les réorganiser comme vous le souhaitez.|r"
L["Filters"] = "Filtres"
L["Reset filters to defaults"] = "Réinitialiser les filtres par défaut"
L["Options"] = "Options"
L["Quest Title Color By Difficulty"] = "Coloriser les noms de quête en fonction de la difficulté"
L["Show quest level prefix  |cffaaaaaa(e.g. [60] Title)|r"] = "Montrer le préfixe du niveau de quête  |cffaaaaaa(par exemple, un titre [60])|r"
L["Show zone label under quest titles"] = "Montrer le nom de la zone sous le nom de la quête"
L["Show objective progress numbers  |cffaaaaaa(0/4, 1/1, etc.)|r"] = "Affichage numérique du progrès des quêtes  |cffaaaaaa(0/4, 1/1, etc.)|r"
L["Show quest ID  |cffaaaaaa(useful for bug reports)|r"] = "Affiche l'ID de la quête  |cffaaaaaa(utile pour signaler les bugs)|r"
L["Show tracked / total on the Quests & Campaign headers  |cffaaaaaa(e.g. 3/9)|r"] = "Affiche suivi / total pour les Quêtes & Campagne  |cffaaaaaa(par exemple 3/9)|r"
L["Show usable quest item buttons  |cffaaaaaa(click to use the quest's item)|r"] = "Affiche les objets de quête utilisables  |cffaaaaaa(cliquez pour utiliser l'objet de quête)|r"
L["Hide scroll bar  |cffaaaaaa(scroll with the mouse wheel instead)|r"] = "Cacher la barre de défilement  |cffaaaaaa(le défilement par la molette de la souris reste activé)|r"
L["Show Quest Discovered popups  |cffaaaaaa(boxes for newly discovered / completed quests)|r"] = "Affiche les alertes de découverte  |cffaaaaaa(popups pour les quêtes récemment découvertes / complétées)|r"
L["Show NEW tag on recently accepted quests  |cffaaaaaa(for about an hour after accepting)|r"] = "Affiche NOUVEAU sur les quêtes récemment acceptées  |cffaaaaaa(dure environ une heure)|r"
L["Split quest click  |cffaaaaaa(click the icon to focus, click the title to open the quest log)|r"] = "Séparer les clics sur les quêtes  |cffaaaaaa(cliquer sur l'icône pour suivre la quête, cliquer sur le nom de la quête pour l'ouvrir dans le journal de quête)|r"
L["Quest Sound  |cffaaaaaa(plays when a quest is ready to turn in)|r"] = "Son de quête  |cffaaaaaa(joue quand une quête est prête à être rendue)|r"
L["Quest Complete Sound"] = "Son pour Quête Complétée"
L["Tracker Visibility"] = "Visibilité du module de suivi"
L["Profession section"] = "Section profession"
L["Achievements section  |cffaaaaaa(achievements you're tracking)|r"] = "Section Hauts-faits  |cffaaaaaa(hauts-faits suivis)|r"
L["World Quests section"] = "Section Quêtes du Monde ouvert"
L["Auto-list current-zone world quests  |cffaaaaaa(lists every WQ in your zone without tracking each)|r"] = "Lister automatiquement les quêtes de monde ouvert pour la zone actuelle  |cffaaaaaa(Liste les quêtes de la zone sans les suivre)|r"
L["Changes apply immediately to the on-screen tracker."] = "Les changements s'appliquent immédiatement sur le module de suivi"

-- ─── Options/TabWorldQuests.lua ───
L["Gold"] = "Or"
L["Gear / Items"] = "Équipement / Objets"
L["Reputation tokens"] = "Réputation"
L["Resources / Currencies"] = "Ressources / Monnaies"
L["Artifact Power"] = "Puissance d'Artéfact"
L["Profession quests"] = "Quêtes de profession"
L["PvP"] = "JcJ"
L["Pet battles"] = "Combat de Mascottes"
L["Other / Uncategorized"] = "Autres / Sans catégorie"
L["Classic"] = "Classique"
L["The Burning Crusade"] = "The Burning Crusade"
L["Wrath of the Lich King"] = "Wrath of the Lich King"
L["Cataclysm"] = "Cataclysm"
L["Mists of Pandaria"] = "Mists of Pandaria"
L["Warlords of Draenor"] = "Warlords of Draenor"
L["Legion"] = "Legion"
L["Battle for Azeroth"] = "Battle for Azeroth"
L["Shadowlands"] = "Shadowlands"
L["Dragonflight"] = "Dragonflight"
L["The War Within"] = "The War Within"
L["Midnight"] = "Midnight"
L["Other"] = "Autres"
L["World Quests"] = "Quêtes du Monde Ouvert"
L["Enable World Quests map features  |cffaaaaaa(pins, summary, zone list)|r"] = "Activer les fonctionnalitées pour les quêtes du monde ouvert  |cffaaaaaa(marqueurs, résumé, liste de la zone)|r"
L["Off: Everything Quests stops putting World Quests on the map — no world-map pins, no reward summary box, no zone quest list. The boxes below do nothing while this is off. This switch is ONLY for World Quests. It does NOT remove the red \"!\" / \"?\" quest rings — those are your normal quests, and you turn them off on the General tab. It also does NOT change the World Quests list in your tracker (that's on the Tracker tab)."] = "Désactivé: Everything Quests arrête d'afficher les quêtes du monde ouvert sur la carte — pas de marqueurs, pas de résumé des récompenses, pas de liste des quêtes de la zone. Les cases ci-dessous ne servent à rien quand cette fonctionnalité est désactivée. Cette case ne fonctionne QUE pour les quêtes du Monde ouvert. Cela ne retire PAS les anneaux de quête \"!\" / \"?\" — Ceux-ci concernent vos quêtes normales, et vous pouvez les désactiver dans l'onglet Général. Cela ne change PAS non plus la liste des quêtes du monde ouvert (Cela se passe dans l'onglet Module)."
L["Show world quest pins on the world map"] = "Affiche les marqueurs des quêtes du Monde ouvert sur la carte du monde"
L["Show zone quest list on zone maps"] = "Affiche la liste des quêtes de la zone sur la carte de la zone"
L["Filters by reward type"] = "Filtrer par type de récompense"
L["Enable All"] = "Tout activer"
L["Disable All"] = "Tout désactiver"
L["Filter by faction"] = "Filtrer par faction"
L["Uncheck a faction to hide its world quests on the map."] = "Décochez une faction pour cacher ses quêtes sur la carte du monde"
L["No major factions unlocked on this character yet."] = "Aucune faction majeure n'a encore été débloquée pour ce personnage."
L["%s  |cffaaaaaa(Renown %d)|r"] = "%s  |cffaaaaaa(Renom %d)|r"
L["Faction %d"] = "Faction %d"
L["Display"] = "Affichage"
L["Time left"] = "Temps restant"
L["Reward"] = "Récompense"
L["Faction"] = "Faction"
L["A-Z"] = "A-Z"
L["Sort zone quest list by"] = "Trier la liste des quêtes de la zone par"
L["World map pin scale"] = "Échelle des marqueurs sur la carte du monde"
L["Filters apply immediately when the world map is open."] = "Les filtres s'appliquent immédiatement quand la carte du monde est ouverte"

-- ─── Options/TabChainGuide.lua ───
L["Chain Guide"] = "Guide des suites de quête"
L["Chain Guide (Storylines)"] = "Guide des suites (Histoires)"
L["Open Chain Guide"] = "Ouvrir le guide des suites"
L["Open Chain Guide on login"] = "Ouvrir le guide des suites de quête à la connexion"
L["Show unrouted questlines  |cffaaaaaa(API discoveries not in our routing table)|r"] = "Montrer suites non-répertoriées  |cffaaaaaa(Découvertes API en dehors de notre table)|r"
L["Window scale"] = "Échelle de la fenêtre"
L["Character cache"] = "Cache du personnage"
L["Per-character chain progress is cached account-wide so alts can browse what your other characters have completed. Clearing the cache removes that cross-character data; live completions stay (Blizzard tracks those)."] = "Le cache pour la progression dans les suites de quêtes est partagé entre vos personnages. Vider le cache efface ces données partagées; la complétion en direct continue (Blizzard assure le suivi) "
L["Clear chain cache"] = "Nettoyer le cache"
L["Clear all cached chain-completion data across every character?"] = "Nettoyer le cache pour le suivi des suites de quêtes pour tous vos personnages?"
L["Clear"] = "Nettoyer"
L["Cached: |cffffffff%d|r characters, |cffffffff%d|r waypoint locations\n|cffffffff%d|r chains across |cffffffff%d|r categories"] = "En cache: |cffffffff%d|r personnages, |cffffffff%d|r points de passage\n|cffffffff%d|r suites de quêtes sur |cffffffff%d|r catégories"
L["today"] = "aujourd'hui"
L["1 day ago"] = "hier"
L["%d days ago"] = "il y a %d jours"
L["\n|cffaaaaaaLast pruned: %s|r"] = "\n|cffaaaaaaDernier Nettoyage: %s|r"
L["Prune stale entries now"] = "Nettoyer les entrées obsolètes maintenante"
L["|cffEBB706EQ|r: pruned |cffffffff%d|r stale character record(s) and |cffffffff%d|r waypoint(s)."] = "|cffEBB706EQ|r: nettoyage de |cffffffff%d|r données de personnage obsolètes et |cffffffff%d|r point(s) de passage."

-- ─── Options/TabAppearance.lua ───
L["Appearance"] = "Apparence"
L["Font"] = "Police"
L["Font Size"] = "Taille de police"
L["None"] = "Aucun"
L["Outline"] = "Contour"
L["Thick"] = "Épais"
L["Mono"] = "Mono"
L["Mono Outline"] = "Mono contour"
L["Mono Thick"] = "Mono épais"
L["Font Outline"] = "Contour de police"
L["Background"] = "Arrière-plan"
L["Background Color"] = "Couleur d'arrière-plan"
L["Scroll Bar Background"] = "Arrière-plan de la barre de défilement"
L["Scroll Bar Color"] = "Couleur de la barre de défilement"
L["Border"] = "Bordure"
L["Border Color"] = "Couleur de bordure"
L["Border Thickness"] = "Épaisseur de bordure"
L["Colors & Dimensions"] = "Couleurs & dimensions"
L["Quest Title Color Override"] = "Couleur titres de quêtes"
L["When cleared, falls back to difficulty coloring or default yellow."] = "Quand nettoyé, retourne à la couleur de difficulté ou à la couleur par défaut"
L["Use title color for completed quests  |cffaaaaaa(instead of green)|r"] = "Utiliser la couleur des titres pour les quêtes complétées  |cffaaaaaa(au lieu du vert)|r"
L["Section Header Color"] = "Couleur nom de section"
L["Tracker Scale"] = "Échelle du module de suivi"
L["Block Spacing"] = "Espacement des blocs"

-- ─── Options/TabHistory.lua ───
L["History"] = "Historique"
L["Quest History"] = "Historique des quêtes"
L["Record completed quests"] = "Enregistrer les quêtes complétées"
L["When on, Everything Quests writes an entry to your account-wide quest history every time you turn in a quest. The data is shared across all of your characters; the history window can filter by character."] = "Si activé, Everything Quests enregistre une entrée pour votre historique de quête lié au compte chaque fois que vous rendez une quête. Les données sont partagées entre tous vos personnages; la fenêtre Historique peut filter par personnage."
L["Maximum entries kept"] = "Maximum d'entrées conservées"
L["When the history grows past this many entries, the oldest ones are dropped. Set higher if you want a longer record, lower to save disk space. 5000 entries is enough for several months of heavy questing."] = "Quand le nombre d'entrée dépasse ce nombre, les entrées les plus anciennes sont effacées. Augmenter le chiffre rallonge la taille du journal, le diminuer réduit l'espace disque. 5000 entrées suffisent pour plusieurs mois de quêtes intensives."
L["Open Quest History"] = "Ouvrir l'Historique"
L["Populate from past completions"] = "Remplir par d'anciennes complétions"
L["this character"] = "ce personnage"
L["|cffEBB706EQ History:|r added %d past completion%s for |cffffffff%s|r (no dates)."] = "|cffEBB706EQ Historique:|r ajoute de %d complétion%s ancienne pour |cffffffff%s|r (pas de dates)."
L["One-time per character: walks the list of quests this character has completed (according to the game's own record) and adds any that aren't already in your history. Entries created this way have no date — the game doesn't tell us when they happened."] = "Une fois par personnage: parcourt la liste des quêtes que ce personnage a complété (d'après les données propres du jeu) et ajoute celles qui ne sont pas encore dans l'historique. Les entrées ajoutées de cette manière n'ont pas de date - le jeu ne nous dit pas quand elles ont été complétées."
L["Re-scan for quest names"] = "Re-scanner les noms de quête"
L["|cffEBB706EQ History:|r requested %d quest name%s from the server. Names will fill in over the next minute or two."] = "|cffEBB706EQ Historique:|r recherche de %d nom%s de quête depuis le serveur. Les noms se rempliront d'ici une ou deux minutes."
L["|cffEBB706EQ History:|r nothing left to look up — every entry that can be resolved already is."] = "|cffEBB706EQ Historique:|r rien de plus à rechercher - toutes les entrées qui pouvaient être résolues l'ont été."
L["Some quests in the backfilled history show up as \"Quest #12345\" because Blizzard hasn't sent the client their name yet. This button asks the server for every missing one. Quests the server flatly has no data for (retired or internal IDs) will keep their numeric placeholder."] = "Certaines quêtes anciennes sont affichées comme \"Quest #12345\" parce que Blizzard n'a pas encore envoyé leur nom au client. Ce boûton demande chaque nom manquant au serveur. Les quêtes pour lesquelles le serveur n'a simplement pas de nom (obsolète ou ID interne) conserveront leur identifiant numérique."
L["Restore history from backup"] = "Restaurer l'historique depuis un point de restauration"
L["|cffEBB706EQ History:|r no backup yet — one is saved automatically each time you log out."] = "|cffEBB706EQ Historique:|r pas encore de point de restauration — créé automatiquement chaque fois que vous vous déconnetez."
L["Restore quest history from the backup taken %s (%d entries)? This replaces the current history."] = "Restaurer l'historique depuis la point de restauration %s (%d entries)? Cela remplacera l'historique actuel."
L["Restore"] = "Rastaurer"
L["|cffEBB706EQ History:|r restored %d entr%s from backup."] = "|cffEBB706EQ Historique:|r restauration de %d entr%s depuis le point de restauration."
L["Everything Quests saves a rolling backup of your history when you log out, and automatically restores it if your history is ever found empty or missing a character on load. Use this button to restore manually."] = "Everything Quests sauvegarde une backup de votre historique quand vous vous déconnectez, et le restaure automatiquement si jamais votre historique apparaît vide ou manquant un personnage au chargement. Utilisez ce boûton pour le restaurer manuellement."
L["Wipe history"] = "Supprimer l'historique"
L["Delete ALL recorded quest history (every character)? This cannot be undone."] = "Supprimer TOUS les historiques enregistrés (pour tout vos personnages)? Cette actione est irréversible."
L["Wipe"] = "Supprimer"
L["|cffEBB706EQ History:|r wiped."] = "|cffEBB706EQ Historique:|r supprimé."

-- ─── Options/Frame.lua ───
L["Join our Discord!"] = "Rejoignez-nous sur Discord!"
L["Join our Discord"] = "Nous rejoindre sur Discord"
L["Version %s"] = "Version %s"
L["Everything Quests opens its full options in a dedicated window. Click the button below, or type |cffEBB706/eqs|r in chat."] = "Everything Quests ouvre son menu complet de configuration dans une fenêtre dédiée. Cliquez sur le boûton ci-dessous, ou tapez |cffEBB706/eqs|r dans la fenêtre de discussion."
L["Open Everything Quests Options"] = "Ouvrir les options de Everything Quests"
L["|cffEBB706Everything Quests|r: couldn't open Options \226\128\148 %s"] = "|cffEBB706Everything Quests|r: impossible d'ouvrir les Options \226\128\148 %s"

-- ─── Core/Init.lua ───

-- ─── Modules/ChainGuide/ChainView.lua ───

-- ─── Modules/ChainGuide/Frame.lua ───

-- ─── Modules/ChainGuide/QuestMapButton.lua ───

-- ─── Modules/Tracker/AutoComplete.lua ───

-- ─── Modules/Tracker/AutoQuestPopup.lua ───

-- ─── Modules/Tracker/Events.lua ───

-- ─── Modules/Tracker/Frame.lua ───

-- ─── Modules/Tracker/Scenario.lua ───

-- ─── Modules/Tracker/ZoneProgress.lua ───

-- ─── Modules/WhatsNew.lua ───
