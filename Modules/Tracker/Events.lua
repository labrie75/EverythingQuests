local _, ns = ...
local L = ns.L

local V = ns:RegisterSubsystem("TrackerEvents", {})

local HEADER_H     = 30        -- compact WQ title row (fits the 32px medallion)
local LINE_H       = 14
local ROW_GAP      = 2
local ICON_SIZE    = 26        -- match Blocks.lua so WQ rows visually align
local ICON_PAD     = 4
local LABEL_PAD    = 6
local LINE_INDENT  = ICON_PAD + ICON_SIZE + LABEL_PAD
local TICKER_INTERVAL = 30
-- Stock WQ marker sizes. The brown medallion is the background; the gold star
-- (or type icon) sits centered on it. The star is kept well under the medallion
-- so the brown rim reads clearly at tracker scale (a near-equal star buries it).
-- The medallion swaps to its gold "selected" frame when focused.
local WQ_RING_SIZE = 33
local WQ_STAR_SIZE = 18


V.headerPool   = {}
V.linePool     = {}
V.activeHeaders = {}
V.activeLines   = {}

-- Quests we've already asked Blizzard to load this session, keyed by
-- questID. Stops the WQ Render path from spamming RequestLoadQuestByID
-- on every refresh, which on some builds bounces back as QUEST_DATA_LOAD_RESULT
-- and creates an event-driven refresh loop.
V._requestedLoad = {}

local function buildHeader(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(HEADER_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)

    -- Stock Blizzard WQ map-pin visuals: the brown medallion background (the
    -- same Interface/WorldMap/UI-QuestPoi-NumberIcons frame Blizzard's
    -- QuestUtil.SetupWorldQuestButton draws for Common-quality world quests)
    -- with the gold star / type icon centered on it ("Worldquest-icon" and
    -- friends, via QuestUtil.GetWorldQuestAtlasInfo). The medallion swaps to its
    -- gold "super-tracked" frame when the quest is focused. See V:Render.
    r.iconHolder = CreateFrame("Frame", nil, r)
    r.iconHolder:SetSize(ICON_SIZE, ICON_SIZE)
    r.iconHolder:SetPoint("LEFT", ICON_PAD, 0)

    r.ring = r.iconHolder:CreateTexture(nil, "ARTWORK", nil, 0)
    r.ring:SetSize(WQ_RING_SIZE, WQ_RING_SIZE)
    r.ring:SetPoint("CENTER")

    r.icon = r.iconHolder:CreateTexture(nil, "ARTWORK", nil, 1)
    r.icon:SetSize(WQ_STAR_SIZE, WQ_STAR_SIZE)
    r.icon:SetPoint("CENTER")

    r.title = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.title:SetPoint("LEFT", r.iconHolder, "RIGHT", LABEL_PAD, 0)
    r.title:SetPoint("RIGHT", -4, 0)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)
    r.title:SetTextColor(1.0, 0.82, 0.0)

    -- Hidden by default. V:Render shows this only for group-listable world
    -- quests (world boss / elite / dungeon / raid), matching Blizzard's own
    -- objective-tracker eye via C_LFGList.CanCreateQuestGroup — not every WQ
    -- with an LFG activity, since Blizzard exposes premade groups for many
    -- ordinary world quests too.
    r.groupFinder = CreateFrame("Button", nil, r)
    r.groupFinder:SetSize(16, 16)
    r.groupFinder:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.groupFinder.icon = r.groupFinder:CreateTexture(nil, "ARTWORK")
    r.groupFinder.icon:SetAllPoints()
    r.groupFinder.icon:SetAtlas("groupfinder-eye-single")
    r.groupFinder:Hide()
    r.groupFinder:SetScript("OnClick", function(self)
        local qid = self:GetParent().questID
        if qid and LFGListUtil_FindQuestGroup then
            LFGListUtil_FindQuestGroup(qid)
        end
    end)
    r.groupFinder:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L["Find Group"], 1, 1, 1)
        GameTooltip:AddLine(L["Open the Premade Group Finder for this quest."], 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    r.groupFinder:SetScript("OnLeave", function() GameTooltip:Hide() end)

    r:SetScript("OnEnter", function(self)
        if not self.questID then return end
        local Tooltip = ns:GetSubsystem("WQTooltip")
        if Tooltip and Tooltip.Show then Tooltip:Show(self, self.questID) end
    end)
    r:SetScript("OnLeave", function()
        local Tooltip = ns:GetSubsystem("WQTooltip")
        if Tooltip and Tooltip.Hide then Tooltip:Hide() end
    end)
    r:SetScript("OnClick", function(self, button)
        if not self.questID then return end
        if button == "RightButton" then
            if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
            local Watch = ns:GetSubsystem("WQWatchPersist")
            local tracked = Watch and Watch.IsTracked and Watch:IsTracked(self.questID)
            local title = ns.Util.QuestTitle(self.questID) or "World Quest"
            MenuUtil.CreateContextMenu(self, function(_, root)
                root:CreateTitle(title)
                if tracked then
                    root:CreateButton("Untrack Quest", function()
                        if Watch and Watch.Untrack then Watch:Untrack(self.questID) end
                    end)
                else
                    root:CreateButton("Track Quest", function()
                        if Watch and Watch.Track then Watch:Track(self.questID) end
                    end)
                end
                root:CreateButton("Super-track (follow arrow)", function()
                    if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
                        C_SuperTrack.SetSuperTrackedQuestID(self.questID)
                    end
                end)
            end)
        else
            -- Split-click parity with the Quests section. With "Split quest
            -- click" on: clicking the icon focuses (super-tracks), clicking the
            -- title opens the quest's details. We hit-test cursor X against the
            -- icon's right edge (divided by effective scale, same approach as
            -- Blocks.lua) instead of giving the icon its own handler. With the
            -- option off, a left-click anywhere super-tracks as before. World
            -- quests have no floating QuestLogPopupDetailFrame (that's a
            -- normal-quest-only frame), so "details" opens the world map
            -- focused on the quest.
            local DB  = ns:GetSubsystem("DB")
            local cfg = DB and DB.db.profile.tracker
            local overIcon = false
            if cfg and cfg.splitQuestClick then
                local ih = self.iconHolder
                if ih then
                    local mx = GetCursorPosition()
                    mx = mx / (self:GetEffectiveScale() or 1)
                    local iconRight = ih:GetRight()
                    if iconRight and mx <= iconRight then overIcon = true end
                end
            end
            if cfg and cfg.splitQuestClick and not overIcon then
                if C_AddOns and C_AddOns.LoadAddOn then
                    C_AddOns.LoadAddOn("Blizzard_QuestLog")
                end
                if QuestMapFrame_OpenToQuestDetails then
                    QuestMapFrame_OpenToQuestDetails(self.questID)
                elseif OpenWorldMap and C_TaskQuest and C_TaskQuest.GetQuestZoneID then
                    OpenWorldMap(C_TaskQuest.GetQuestZoneID(self.questID))
                end
            elseif C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
                C_SuperTrack.SetSuperTrackedQuestID(self.questID)
            end
        end
    end)

    return r
end

local function buildLine(parent)
    local r = CreateFrame("Frame", nil, parent)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("TOPLEFT", LINE_INDENT, 0)
    r.text:SetPoint("TOPRIGHT", -4, 0)
    r.text:SetJustifyH("LEFT")
    -- Wrap long objectives onto multiple lines instead of truncating them,
    -- matching Blizzard's tracker (where "Quell the restless spirits of
    -- Windrunner Spire" breaks across two lines). Row height gets set
    -- per-render once the string is laid out and the actual height is known.
    r.text:SetWordWrap(true)
    return r
end

local function acquireHeader(parent)
    return ns.Util.AcquirePooled(V.headerPool, V.activeHeaders, parent, buildHeader)
end

local function acquireLine(parent)
    return ns.Util.AcquirePooled(V.linePool, V.activeLines, parent, buildLine)
end

local function releaseAll()
    for i = #V.activeHeaders, 1, -1 do
        local r = V.activeHeaders[i]
        r:Hide()
        r:ClearAllPoints()
        r.icon:SetTexture(nil)
        V.headerPool[#V.headerPool + 1] = r
        V.activeHeaders[i] = nil
    end
    for i = #V.activeLines, 1, -1 do
        local r = V.activeLines[i]
        r:Hide()
        r:ClearAllPoints()
        r.text:SetText("")
        V.linePool[#V.linePool + 1] = r
        V.activeLines[i] = nil
    end
end

local function getWatchedWorldQuests()
    -- Prefer the persistent watch list (which unions Blizzard's runtime
    -- watches with our saved-vars list) so quests stay visible even before
    -- the post-login restore tick re-adds them to Blizzard's tracker.
    local Watch = ns:GetSubsystem("WQWatchPersist")
    if Watch and Watch.GetTrackedQuests then
        return Watch:GetTrackedQuests()
    end
    if not (C_QuestLog and C_QuestLog.GetNumWorldQuestWatches) then return {} end
    local out = {}
    local n = C_QuestLog.GetNumWorldQuestWatches() or 0
    for i = 1, n do
        local qid = C_QuestLog.GetQuestIDForWorldQuestWatchIndex(i)
        if qid then out[#out + 1] = qid end
    end
    return out
end

-- WoW renamed `C_TaskQuest.GetQuestsForPlayerByMapID` to
-- `C_TaskQuest.GetQuestsOnMap`. Try the new name first; fall back to the
-- old one for compatibility with earlier clients.
local function fetchTaskQuestsForMap(mapID)
    if not (C_TaskQuest and mapID) then return {} end
    if C_TaskQuest.GetQuestsOnMap then
        return C_TaskQuest.GetQuestsOnMap(mapID) or {}
    end
    if C_TaskQuest.GetQuestsForPlayerByMapID then
        return C_TaskQuest.GetQuestsForPlayerByMapID(mapID) or {}
    end
    return {}
end

-- Walks task quests for the player's current map all the way up the
-- parent chain (capped at 5 hops). Some bonus objectives — including
-- "To Understand Magic" and other event-style WQs — are registered
-- against the world-level Azeroth map rather than a specific zone, so
-- we have to ascend the whole way to find them.
-- Two filters keep the noise out:
--   • Only `inProgress` quests are collected (Azeroth carries ~74 task
--     quests but only a handful are active for the player).
--   • Quests already in the regular quest log are skipped so the same
--     row doesn't render in both the Quests and World Quests sections.
local function getInZoneActiveTaskQuests()
    if not (C_Map and C_Map.GetBestMapForUnit) then return {} end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or mapID <= 0 then return {} end

    -- A quest already shown in the Quests section shouldn't render here
    -- too. The right test is "is it in the Cache the Quests section reads
    -- from" — not "GetLogIndexForQuestID returns non-nil", because that
    -- API returns non-nil for hidden task quests (like "To Understand
    -- Magic") that the Quests section deliberately skips. Filtering on
    -- the log index excludes them from the WQ section as well, leaving
    -- them invisible everywhere.
    local Cache = ns:GetSubsystem("Cache")
    local function isInQuestsSection(qid)
        return Cache and Cache.Get and Cache:Get(qid) ~= nil
    end

    local out, seenQ, seenM = {}, {}, {}
    local function walk(m)
        if not m or seenM[m] then return end
        seenM[m] = true
        local list = fetchTaskQuestsForMap(m)
        for i = 1, #list do
            local q = list[i]
            local qid = q and (q.questId or q.questID)
            if qid and q.inProgress and not seenQ[qid] and not isInQuestsSection(qid) then
                seenQ[qid] = true
                out[#out + 1] = qid
            end
        end
    end

    local m = mapID
    for _ = 1, 5 do
        if not m then break end
        walk(m)
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(m)
        m = info and info.parentMapID
    end
    return out
end

-- When the user enables "auto-list current-zone world quests"
-- (tracker.autoListZoneWorldQuests), surface EVERY world quest available on
-- the player's CURRENT zone map — not just the ones they've started or
-- watched. Unlike getInZoneActiveTaskQuests this does not require inProgress,
-- and it filters to genuine world quests (skipping plain bonus objectives).
-- Display-only: nothing here is added to the persistent watch list, so the
-- rows drop off on the next ZONE_CHANGED_NEW_AREA rebuild after leaving.
local function isWorldQuest(qid)
    if not qid then return false end
    if C_QuestLog and C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(qid) then
        return true
    end
    if QuestUtils_IsQuestWorldQuest and QuestUtils_IsQuestWorldQuest(qid) then
        return true
    end
    return false
end

local function getZoneWorldQuests()
    local DB = ns:GetSubsystem("DB")
    local t  = DB and DB.db and DB.db.profile and DB.db.profile.tracker
    if not (t and t.autoListZoneWorldQuests) then return {} end
    if not (C_Map and C_Map.GetBestMapForUnit) then return {} end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or mapID <= 0 then return {} end
    local out = {}
    local list = fetchTaskQuestsForMap(mapID)
    for i = 1, #list do
        local q = list[i]
        local qid = q and (q.questId or q.questID)
        if isWorldQuest(qid) then
            out[#out + 1] = qid
        end
    end
    return out
end

-- Pulls task / world-quest / bounty entries straight from the player's
-- quest log. Some bonus objectives end up here without ever appearing in
-- the world-quest watch list or a current-map task query, so this is the
-- catch-net for "the player has progress on this thing right now".
local function getQuestLogTaskQuests()
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries
            and C_QuestLog.GetInfo) then return {} end
    local out = {}
    local n = C_QuestLog.GetNumQuestLogEntries() or 0
    for i = 1, n do
        local info = C_QuestLog.GetInfo(i)
        if info and info.questID and not info.isHeader and not info.isHidden then
            local isTaskish = info.isTask or info.isBounty
                or (QuestUtils_IsQuestWorldQuest and QuestUtils_IsQuestWorldQuest(info.questID))
            if isTaskish then
                out[#out + 1] = info.questID
            end
        end
    end
    return out
end

-- Combined source of truth for the World Quests section: watched quests
-- (manual + persistent) unioned with in-zone in-progress task quests
-- and any task-flagged entries directly in the player's quest log.
--
-- The walk through parent maps + the GetInfo iteration are the addon's
-- single biggest source of allocation churn — Azeroth-level returns ~74
-- task quest tables per call, and we'd previously do this on every
-- Tracker:Refresh (~4×/sec). Now we cache the result and only rebuild on
-- events that can actually change which WQs are visible: structural quest
-- changes, watch flips, and zone changes. QUEST_LOG_UPDATE (objective
-- progress) leaves the list alone — objective text re-fetches per render
-- via C_QuestLog.GetQuestObjectives, which is cheap.
local _activeCache    = {}
local _activeSeen     = {}
local _activeDirty    = true
local function rebuildActiveWorldQuests()
    wipe(_activeCache)
    wipe(_activeSeen)
    -- A quest already shown in the Quests section (i.e. present in the
    -- Cache the Quests section reads from) must not render here too.
    -- Centralized so it applies to ALL sources below — previously only
    -- getInZoneActiveTaskQuests filtered, so a watched/quest-log task
    -- quest like "Nulling Nullaeus" rendered in both sections.
    local Cache = ns:GetSubsystem("Cache")
    local function push(qid)
        if qid and not _activeSeen[qid]
           and not (Cache and Cache.Get and Cache:Get(qid) ~= nil) then
            _activeSeen[qid] = true
            _activeCache[#_activeCache + 1] = qid
        end
    end
    for _, qid in ipairs(getWatchedWorldQuests())     do push(qid) end
    for _, qid in ipairs(getInZoneActiveTaskQuests()) do push(qid) end
    for _, qid in ipairs(getQuestLogTaskQuests())     do push(qid) end
    for _, qid in ipairs(getZoneWorldQuests())        do push(qid) end
    _activeDirty = false
end
local function getActiveWorldQuests()
    if _activeDirty then rebuildActiveWorldQuests() end
    return _activeCache
end

-- Public hook so options (e.g. the auto-list toggle) can force the active WQ
-- list to rebuild on the next render instead of waiting for a zone change.
function V:MarkActiveDirty()
    _activeDirty = true
end

-- "X/Y" prefix turns red while at zero, amber while in progress, green when
-- complete. Shared with Modules/Tracker/Blocks.lua via Core/Util.lua so the
-- WQ section reads identically to the regular Quests section. (This used to
-- be a hand-synced copy that also allocated a fresh gsub closure per
-- objective line on the render path — the shared version is hoisted.)
local colorizeProgress = ns.Util.ColorizeProgress

local function questTitle(questID)
    return ns.Util.QuestTitle(questID, true)
end


function V:Render(content, contentWidth, yStart, collapsed)
    local quests = getActiveWorldQuests()
    local count = #quests

    releaseAll()

    if collapsed or count == 0 then return 0, count end

    local Media = ns:GetSubsystem("Media")

    -- Match the main tracker's "use title color for completed quests" rule for
    -- finished WQ objectives. Computed ONCE per render (not per line) — this
    -- path is GC-sensitive. Defaults to green when no title color is set.
    local doneHex = "44ff44"
    local DB = ns:GetSubsystem("DB")
    local t  = DB and DB.db and DB.db.profile and DB.db.profile.tracker
    local ov = t and t.titleColorOverride
    if t and t.overrideCompleteGreen ~= false and ov and ov.r then
        doneHex = ("%02x%02x%02x"):format(
            math.floor(ov.r * 255 + 0.5),
            math.floor(ov.g * 255 + 0.5),
            math.floor(ov.b * 255 + 0.5))
    end

    -- Drives the "grow when focused" state for the stock WQ marker.
    local superID = (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
                     and C_SuperTrack.GetSuperTrackedQuestID()) or 0

    local y = yStart
    for i = 1, count do
        local qid = quests[i]
        local row = acquireHeader(content)
        row:SetWidth(contentWidth)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        row.questID = qid

        -- Center star / type icon, resolved by Blizzard's own helper so every
        -- type/quality matches the map exactly: normal WQs get the gold
        -- "Worldquest-icon" star, while PvP / dungeon / raid / profession /
        -- boss / etc. each get their own icon. Falls back to the gold star if
        -- the helper or tag info isn't available.
        local tagInfo = C_QuestLog and C_QuestLog.GetQuestTagInfo
                        and C_QuestLog.GetQuestTagInfo(qid)
        local atlas = "Worldquest-icon"
        if QuestUtil and QuestUtil.GetWorldQuestAtlasInfo and tagInfo then
            atlas = QuestUtil.GetWorldQuestAtlasInfo(qid, tagInfo, false) or atlas
        end
        row.icon:SetAtlas(atlas)
        -- Stock brown WQ medallion behind the icon: the Interface/WorldMap/
        -- UI-QuestPoi-NumberIcons frame Blizzard uses for Common-quality world
        -- quests (QuestUtil.SetupWorldQuestButton -> ApplyStandardTexturesToPOI).
        -- Swap to its gold "super-tracked" frame when focused so the whole marker
        -- turns gold. SetTexture + SetTexCoord rather than SetAtlas because this
        -- medallion lives in a fixed-grid texture, not the atlas system.
        row.ring:SetTexture("Interface/WorldMap/UI-QuestPoi-NumberIcons")
        if qid == superID then
            row.ring:SetTexCoord(0.500, 0.625, 0.375, 0.5)   -- selected (gold) frame
        else
            row.ring:SetTexCoord(0.875, 1.000, 0.375, 0.5)   -- normal (brown) frame
        end
        row.iconHolder:Show()
        row.title:ClearAllPoints()
        row.title:SetPoint("LEFT", row.iconHolder, "RIGHT", LABEL_PAD, 0)

        -- Group-listable world quests (world bosses, elite, dungeon / raid WQs)
        -- keep the group-finder eye on the right. The authoritative signal is
        -- C_LFGList.CanCreateQuestGroup(qid): it is the EXACT condition Blizzard's
        -- own objective tracker uses to show its green "find a group" eye (the
        -- QuestUtil.CanCreateQuestGroup wrapper caches that engine call per quest).
        -- v1.21.0 mistakenly gated on C_LFGList.GetActivityIDForQuestID, which
        -- returns an activity ID for ORDINARY world quests too, so the eye showed
        -- up on every WQ. CanCreateQuestGroup returns false for those and true for
        -- the bosses/elites/group WQs Blizzard itself offers premade groups for —
        -- so it both fixes the "eye on everything" regression and catches the world
        -- bosses the old isElite-only gate missed (e.g. WorldBoss-typed quests with
        -- isElite nil). The eye's click opens Blizzard's Premade Group Finder via
        -- LFGListUtil_FindQuestGroup. Prefer the cached QuestUtil wrapper, fall back
        -- to the raw API, and if neither exists hide the eye (never show on all).
        local canGroup
        if QuestUtil and QuestUtil.CanCreateQuestGroup then
            canGroup = QuestUtil.CanCreateQuestGroup(qid)
        elseif C_LFGList and C_LFGList.CanCreateQuestGroup then
            canGroup = C_LFGList.CanCreateQuestGroup(qid)
        end
        if canGroup then
            row.groupFinder:Show()
            row.title:SetPoint("RIGHT", row.groupFinder, "LEFT", -4, 0)
        else
            row.groupFinder:Hide()
            row.title:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        end
        row.title:SetText(questTitle(qid))
        -- Honor the user's chosen title color so World Quests follow the same
        -- color scheme as the main Quests section (Blocks.lua title logic).
        -- Pooled rows always reset the color, so set both branches explicitly.
        if ov and ov.r then
            row.title:SetTextColor(ov.r, ov.g, ov.b)
        else
            row.title:SetTextColor(1.0, 0.82, 0.0)
        end
        if Media and Media.ApplyTrackerTitleFont then Media:ApplyTrackerTitleFont(row.title) end
        y = y + HEADER_H + ROW_GAP

        -- Ask Blizzard to load this task quest's data exactly once per
        -- session. The previous version requested every render, which on
        -- some builds caused Blizzard to fire QUEST_DATA_LOAD_RESULT even
        -- for already-loaded quests — our handler then triggered another
        -- refresh, which requested again, creating a tight feedback loop
        -- that churned several MB/sec of garbage during steady-state play.
        if C_QuestLog and C_QuestLog.RequestLoadQuestByID
           and not V._requestedLoad[qid] then
            V._requestedLoad[qid] = true
            C_QuestLog.RequestLoadQuestByID(qid)
        end

        -- Objectives, mirroring Blizzard's tracker layout. Each objective
        -- prints on its own line with a colorized "X/Y" prefix (red while
        -- at zero, amber while in progress, green when finished). Lines
        -- wrap when the objective text overflows the row width, and each
        -- line's height grows to fit its actual rendered string.
        local objs = (C_QuestLog and C_QuestLog.GetQuestObjectives
                       and C_QuestLog.GetQuestObjectives(qid)) or {}
        for j = 1, #objs do
            local obj = objs[j]
            if obj and obj.text and obj.text ~= "" then
                local lr = acquireLine(content)
                lr:SetWidth(contentWidth)
                lr:ClearAllPoints()
                lr:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                local txt = obj.text
                if obj.finished then
                    -- Inline atlas + green text mirrors Blizzard's tracker:
                    -- a checkmark glyph in front of the completed objective.
                    -- |A:atlas:height:width|a embeds the atlas inline so it
                    -- flows with the wrapped text instead of needing its
                    -- own anchored frame.
                    txt = "|A:common-icon-checkmark:12:12|a |cff" .. doneHex .. txt .. "|r"
                else
                    txt = "- " .. colorizeProgress(txt)
                end
                lr.text:SetText(txt)
                if Media and Media.ApplyTrackerFont then Media:ApplyTrackerFont(lr.text, -2) end
                -- Size the line to whatever the wrapped FontString actually
                -- ended up at; clamp to LINE_H so a single-line objective
                -- still gets a reasonable row height.
                local h = math.max(lr.text:GetStringHeight(), LINE_H)
                lr:SetHeight(h)
                y = y + h + ROW_GAP
            end
        end
    end

    if not self._tickerArmed then
        self._tickerArmed = true
        C_Timer.After(TICKER_INTERVAL, function()
            self._tickerArmed = false
            local Tracker = ns:GetSubsystem("Tracker")
            if Tracker and Tracker.Refresh then Tracker:Refresh() end
        end)
    end

    return y - yStart, count
end

function V:OnEnable()
    local Events = ns:GetSubsystem("Events")
    local function refresh()
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker and Tracker.Refresh then Tracker:Refresh() end
    end
    -- QUEST_LOG_UPDATE / PLAYER_ENTERING_WORLD are already subscribed in
    -- Modules/Tracker/Frame.lua and lead to the same Tracker:Refresh call.
    -- Two subscriptions = two handler calls per event fire (the actual
    -- Refresh is debounced, but the dispatch isn't). Keep only the WQ-
    -- specific events here.
    Events:On("QUEST_WATCH_LIST_CHANGED", refresh)

    -- Mark the WQ active list dirty so the next render rebuilds it. These
    -- are the events that can change *which* WQs are visible (quest set
    -- changes, watch flips, zone changes). QUEST_LOG_UPDATE is deliberately
    -- NOT on this list — it fires constantly and only signals objective
    -- progress, which we re-fetch live per render without rebuilding the
    -- whole active list.
    local function markActiveDirty() _activeDirty = true end
    Events:On("QUEST_ACCEPTED",           markActiveDirty)
    Events:On("QUEST_REMOVED",            markActiveDirty)
    Events:On("QUEST_TURNED_IN",          markActiveDirty)
    Events:On("QUEST_WATCH_LIST_CHANGED", markActiveDirty)
    Events:On("ZONE_CHANGED_NEW_AREA",    markActiveDirty)
    Events:On("PLAYER_ENTERING_WORLD",    markActiveDirty)

    -- Task quest data (objectives included) loads asynchronously after the
    -- first RequestLoadQuestByID. QUEST_LOG_UPDATE doesn't always fire for
    -- those loads — QUEST_DATA_LOAD_RESULT is the dedicated signal.
    -- Debounce (shared primitive, Core/Events.lua) so a chain of loads in
    -- quick succession only triggers one redraw instead of one per quest.
    local function dataLoadFlush()
        -- A data load can also produce a new task entry (the underlying
        -- quest becoming visible), so mark the active list dirty too.
        _activeDirty = true
        refresh()
    end
    Events:On("QUEST_DATA_LOAD_RESULT", function()
        Events:Debounce("eq.wqtracker.dataload", 0.15, dataLoadFlush)
    end)
end
