-- Modules/Tracker/Frame.lua
-- On-screen quest tracker. Replaces Blizzard's ObjectiveTrackerFrame.
-- Renders a scrollable list of quest blocks pulled from Core/Cache.
-- Visual style: native Blizzard (per project_eq_style memory).

local _, ns = ...

local Tracker = ns:RegisterSubsystem("Tracker", {})

local CONTENT_PAD      = 4    -- inset between block column and scrollframe edges
local REFRESH_THROTTLE = 0.25 -- coalesce bursty events into one redraw.
                              -- The Cache rebuilds itself from scratch on
                              -- every Refresh, so a longer window means
                              -- noticeably less garbage during active play
                              -- (quest accepts, watch toggles, zone changes
                              -- all fire QUEST_LOG_UPDATE in quick succession).
                              -- 0.25s still feels responsive in practice.
local DRAG_HANDLE_H    = 14   -- invisible draggable strip at top of frame
local GRIP_SIZE        = 14   -- bottom-right resize grip

-- Module-scoped scratch tables reused by _RenderQuestsSection on every
-- refresh. Wiped at the start of each render instead of being allocated
-- fresh — for a 50-quest log this saves ~100 small table allocations per
-- pass, plus the GC work to reclaim them.
local _popupSet = {}
local _visible  = {}
local SECTION_H        = 22   -- "Quests" section header band
local MIN_W, MIN_H     = 200, 100
local MAX_W, MAX_H     = 600, 1000

-- Header text color — fallback used when the DB hasn't loaded yet. Once
-- the DB is available, getHeaderColor() returns the user-customizable
-- value from db.profile.tracker.headerColor.
local HEADER_COLOR = { 0.93, 0.32, 0.10 }

local function getHeaderColor()
    local DB = ns:GetSubsystem("DB")
    if DB and DB.db.profile.tracker and DB.db.profile.tracker.headerColor then
        local c = DB.db.profile.tracker.headerColor
        return c.r or HEADER_COLOR[1], c.g or HEADER_COLOR[2], c.b or HEADER_COLOR[3]
    end
    return HEADER_COLOR[1], HEADER_COLOR[2], HEADER_COLOR[3]
end

local function getBlockGap()
    local DB = ns:GetSubsystem("DB")
    if DB and DB.db.profile.tracker and DB.db.profile.tracker.blockSpacing then
        return DB.db.profile.tracker.blockSpacing
    end
    return 4
end

local function disableBlizzardTracker()
    if not ObjectiveTrackerFrame then return end
    ObjectiveTrackerFrame:UnregisterAllEvents()
    ObjectiveTrackerFrame:Hide()
    if not Tracker._hookedBlizz then
        ObjectiveTrackerFrame:HookScript("OnShow", function(f) f:Hide() end)
        Tracker._hookedBlizz = true
    end
end

-- Restore position from saved values. Symmetric with the save path:
-- we record the exact anchor + offsets that GetPoint() returned after the
-- drag, and re-apply them verbatim. No coordinate conversion, no corner
-- snapping — just whatever Blizzard's StartMoving/StopMovingOrSizing left
-- on the frame after the user dropped it. Bulletproof.
function Tracker:_ApplyPosition(anchor, relativePoint, xOffset, yOffset)
    local f = self.frame
    if not f then return end
    f:ClearAllPoints()
    f:SetPoint(anchor or "CENTER", UIParent, relativePoint or anchor or "CENTER",
               xOffset or 0, yOffset or 0)
end

-- Persist current position+size by reading the frame's live SetPoint values
-- and saving them as-is. This avoids the unit-conversion footgun that
-- comes with computing GetLeft/Top + Set Point manually (Get* return in
-- UIParent units, SetPoint x/y are in the frame's units; mixing them
-- causes the frame to snap when scales differ).
function Tracker:PersistPositionAndSize()
    local DB = ns:GetSubsystem("DB")
    local cfg = DB.db.profile.tracker
    local f = self.frame
    if not f then return end

    cfg.width     = math.floor(f:GetWidth())
    cfg.maxHeight = math.floor(f:GetHeight())

    local point, _, relativePoint, x, y = f:GetPoint()
    if not point then return end

    cfg.anchor        = point
    cfg.relativePoint = relativePoint or point
    cfg.xOffset       = math.floor((x or 0) + 0.5)
    cfg.yOffset       = math.floor((y or 0) + 0.5)

    -- No-op re-apply: this is the EXACT same SetPoint Blizzard left us
    -- with after StopMovingOrSizing. Keeping it here so a future /reload's
    -- _ApplyPosition reproduces the same pixel position.
    self:_ApplyPosition(cfg.anchor, cfg.relativePoint, cfg.xOffset, cfg.yOffset)
end

function Tracker:BuildFrame()
    local DB = ns:GetSubsystem("DB")
    local cfg = DB.db.profile.tracker

    local f = CreateFrame("Frame", "EQTrackerFrame", UIParent, "BackdropTemplate")
    f:SetSize(cfg.width, cfg.maxHeight)
    f:SetScale(cfg.scale)
    self.frame = f
    self:_ApplyPosition(cfg.anchor, cfg.relativePoint or cfg.anchor,
                        cfg.xOffset, cfg.yOffset)
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    end
    f:SetClampedToScreen(true)

    f.background = f:CreateTexture(nil, "BACKGROUND")
    f.background:SetAllPoints()
    f.background:Hide()

    -- Top drag handle: invisible strip across the top edge. Brightens slightly
    -- on hover so users discover it without it cluttering the UI when idle.
    local drag = CreateFrame("Frame", nil, f)
    drag:SetPoint("TOPLEFT")
    drag:SetPoint("TOPRIGHT")
    drag:SetHeight(DRAG_HANDLE_H)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    local dragHint = drag:CreateTexture(nil, "OVERLAY")
    dragHint:SetAllPoints()
    dragHint:SetColorTexture(1, 1, 1, 0)
    drag:SetScript("OnEnter",     function() dragHint:SetColorTexture(1, 1, 1, 0.06) end)
    drag:SetScript("OnLeave",     function() dragHint:SetColorTexture(1, 1, 1, 0)     end)
    drag:SetScript("OnDragStart", function()
        local DBs = ns:GetSubsystem("DB")
        if DBs and DBs.db.profile.general and DBs.db.profile.general.lockTracker then return end
        f:StartMoving()
    end)
    drag:SetScript("OnDragStop", function() f:StopMovingOrSizing(); self:PersistPositionAndSize() end)

    -- Bottom-right resize grip: three short white lines forming a diagonal,
    -- drawn with SetColorTexture so we don't depend on a specific texture
    -- path that might shift between client patches.
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(GRIP_SIZE, GRIP_SIZE)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    for i, len in ipairs({ 12, 8, 4 }) do
        local g = grip:CreateTexture(nil, "OVERLAY")
        g:SetColorTexture(1, 1, 1, 0.5)
        g:SetSize(len, 1)
        g:SetPoint("BOTTOMRIGHT", -2, 2 + (i - 1) * 3)
    end
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT")                  end)
    grip:SetScript("OnMouseUp",   function() f:StopMovingOrSizing(); self:PersistPositionAndSize() end)

    -- Scenario container — anchored just below the drag strip. Stays at
    -- height 1 when no scenario is active; the Scenario subsystem grows it
    -- when the player enters a delve / dungeon / scenario / M+ run. The
    -- Quests banner anchors to its bottom, so growing/shrinking this frame
    -- automatically pushes the rest of the tracker down/up.
    local scenarioContainer = CreateFrame("Frame", nil, f)
    scenarioContainer:SetPoint("TOPLEFT",  CONTENT_PAD, -DRAG_HANDLE_H)
    scenarioContainer:SetPoint("TOPRIGHT", -CONTENT_PAD, -DRAG_HANDLE_H)
    scenarioContainer:SetHeight(1)
    f.scenarioContainer = scenarioContainer

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     scenarioContainer, "BOTTOMLEFT",  0, -2)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -22, GRIP_SIZE + 2)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(cfg.width - 26, 1)
    scroll:SetScrollChild(content)

    -- Content width should track the frame as it resizes so blocks reflow.
    f:SetScript("OnSizeChanged", function() self:Refresh() end)

    f.scroll = scroll
    f.content = content
    f.drag    = drag
    f.grip    = grip
    self.frame = f

    self:BuildSectionHeaders(content)
end

local MASTER_H = 24
local MASTER_GAP = 4

-- Tracker headers: flat text with a single hairline beneath, no boxed
-- backgrounds. Modeled on ElvUI's clean tracker look. Icons + per-quest
-- block rendering live in Blocks.lua and stay untouched.
--
-- All hairlines render at identical thickness *and* alpha so the master
-- and section headers look uniformly weighted; using a different alpha for
-- master vs section made the master line read as visibly thicker even
-- though both are 1px tall.
local HAIRLINE_ALPHA  = 0.85
local HAIRLINE_HEIGHT = 2
local function buildHairline(parent)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.92, 0.72, 0.02, HAIRLINE_ALPHA)
    line:SetHeight(HAIRLINE_HEIGHT)
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    return line
end

local function makeMasterHeader(parent, onToggle)
    local h = CreateFrame("Button", nil, parent)
    h:SetHeight(MASTER_H)
    h:RegisterForClicks("LeftButtonUp")

    buildHairline(h)

    h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    h.text:SetPoint("LEFT", 4, 0)
    h.text:SetText("All Objectives")
    h.text:SetTextColor(0.92, 0.72, 0.02)

    -- Collapse marker is a plain FontString — no boxed background.
    h.collapse = h:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    h.collapse:SetPoint("RIGHT", -4, 0)
    h.collapse:SetTextColor(0.92, 0.72, 0.02)

    h:SetScript("OnClick", onToggle)
    return h
end

local function makeSectionHeader(parent, id, title, onToggle)
    local h = CreateFrame("Button", nil, parent)
    h:SetHeight(SECTION_H)
    h:RegisterForClicks("LeftButtonUp")

    buildHairline(h)

    h.text = h:CreateFontString(nil, "OVERLAY", "ObjectiveTrackerHeaderFont")
    if not h.text:GetFont() then h.text:SetFontObject("GameFontNormalLarge") end
    h.text:SetPoint("LEFT", 4, 0)
    h.text:SetText(title)
    h.text:SetTextColor(HEADER_COLOR[1], HEADER_COLOR[2], HEADER_COLOR[3])

    h.collapse = h:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    h.collapse:SetPoint("RIGHT", -4, 0)
    h.collapse:SetTextColor(HEADER_COLOR[1], HEADER_COLOR[2], HEADER_COLOR[3])

    h.count = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    h.count:SetPoint("RIGHT", h.collapse, "LEFT", -6, 0)
    h.count:SetTextColor(0.92, 0.72, 0.02)

    h:SetScript("OnClick", onToggle)
    h.sectionID = id
    return h
end

function Tracker:BuildSectionHeaders(content)
    self.sectionFrames = {}

    self.masterHeader = makeMasterHeader(content, function()
        self:ToggleAllCollapsed()
    end)

    local sections = {
        { id = "quests",     title = "Quests" },
        { id = "profession", title = "Profession" },
        { id = "endeavors",  title = "Endeavors" },
        -- The "events" section is wholly populated by TrackerEvents which
        -- pulls watched world quests via C_TaskQuest. Display label reflects
        -- what's actually shown so it lines up with Blizzard's own naming.
        { id = "events",     title = "World Quests" },
    }
    self.sectionList = sections

    for _, def in ipairs(sections) do
        local sid = def.id
        local h = makeSectionHeader(content, sid, def.title, function()
            self:ToggleSectionCollapsed(sid)
        end)
        self.sectionFrames[sid] = h
    end
end

function Tracker:IsAllCollapsed()
    local DB = ns:GetSubsystem("DB")
    if not DB then return false end
    return DB.char.allCollapsed == true
end

function Tracker:ToggleAllCollapsed()
    local DB = ns:GetSubsystem("DB")
    if not DB then return end
    DB.char.allCollapsed = not self:IsAllCollapsed()
    self:Render()
end

function Tracker:IsSectionCollapsed(id)
    local DB = ns:GetSubsystem("DB")
    if not DB then return false end
    DB.char.sectionsCollapsed = DB.char.sectionsCollapsed or {}
    if id == "quests" and DB.char.trackerCollapsed ~= nil and DB.char.sectionsCollapsed.quests == nil then
        return DB.char.trackerCollapsed
    end
    return DB.char.sectionsCollapsed[id] == true
end

function Tracker:ToggleSectionCollapsed(id)
    local DB = ns:GetSubsystem("DB")
    if not DB then return end
    DB.char.sectionsCollapsed = DB.char.sectionsCollapsed or {}
    DB.char.sectionsCollapsed[id] = not self:IsSectionCollapsed(id)
    if id == "quests" then
        DB.char.trackerCollapsed = DB.char.sectionsCollapsed[id]
    end
    self:Render()
end

-- Coalesce QUEST_LOG_UPDATE / ZONE_CHANGED bursts into a single redraw.
function Tracker:Refresh()
    if not self.frame then return end
    if self._refreshPending then return end
    self._refreshPending = true
    C_Timer.After(REFRESH_THROTTLE, function()
        self._refreshPending = false
        self:Render()
    end)
end

-- Toggle the section's collapsed state. Persisted per-character so the user
-- doesn't have to redo it after a /reload. Triggers a Render to actually
-- show or hide the blocks.
function Tracker:ToggleCollapsed()
    local DB = ns:GetSubsystem("DB")
    if not DB then return end
    DB.char.trackerCollapsed = not DB.char.trackerCollapsed
    self:Render()
end

-- Toggle Blizzard's watch state for a quest from outside the menu (used by
-- Blocks.lua's Shift+left-click handler — Blizzard's QUESTWATCHTOGGLE
-- modifier). Same effect as right-click → Track Quest / Untrack Quest in
-- the context menu. QUEST_WATCH_LIST_CHANGED fires after, the cache
-- invalidates, and the tracker refreshes — no manual refresh needed.
function Tracker:ToggleHidden(questID)
    if not (questID and C_QuestLog) then return end
    local watched = C_QuestLog.GetQuestWatchType
                    and C_QuestLog.GetQuestWatchType(questID) ~= nil
    if watched and C_QuestLog.RemoveQuestWatch then
        C_QuestLog.RemoveQuestWatch(questID)
    elseif (not watched) and C_QuestLog.AddQuestWatch then
        C_QuestLog.AddQuestWatch(questID)
    end
end

function Tracker:_RenderQuestsSection(content, contentWidth, yStart, collapsed)
    local DB      = ns:GetSubsystem("DB")
    local Cache   = ns:GetSubsystem("Cache")
    local Filters = ns:GetSubsystem("TrackerFilters")
    local Sort    = ns:GetSubsystem("TrackerSort")
    local Blocks  = ns:GetSubsystem("TrackerBlocks")
    local AC      = ns:GetSubsystem("TrackerAutoComplete")

    local profile = DB.db.profile.tracker
    local quests  = Cache:All()

    local popups = (AC and AC:GetActivePopups()) or {}
    wipe(_popupSet)
    for i = 1, #popups do _popupSet[popups[i].questID] = true end

    wipe(_visible)
    local visible, count = _visible, 0
    for questID, q in pairs(quests) do
        if not _popupSet[questID] and Filters:Visible(questID, q) then
            count = count + 1
            visible[count] = q
        end
    end

    Blocks:ReleaseAll()
    if AC then AC:ReleaseAll() end

    if collapsed then return 0, count + #popups end

    table.sort(visible, Sort.For(profile.sortMode, profile.manualOrder))

    local y = yStart

    local gap = getBlockGap()
    if AC then
        for i = 1, #popups do
            local p = AC:Acquire(content)
            p:SetWidth(contentWidth)
            p:ClearAllPoints()
            p:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            AC:Render(p, popups[i].questID, popups[i].title)
            y = y + p:GetHeight() + gap
        end
    end

    for i = 1, count do
        local q = visible[i]
        local b = Blocks:Acquire(content)
        b:SetWidth(contentWidth)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        Blocks:RenderQuest(b, q, profile.simplifyMode)
        y = y + b:GetHeight() + gap
    end

    return y - yStart, count + #popups
end

function Tracker:_RenderProfessionSection(content, contentWidth, yStart, collapsed)
    local Profession = ns:GetSubsystem("TrackerProfession")
    if not Profession or not Profession.Render then return 0, 0 end
    return Profession:Render(content, contentWidth, yStart, collapsed)
end

function Tracker:_RenderEndeavorsSection(content, contentWidth, yStart, collapsed)
    local Endeavors = ns:GetSubsystem("TrackerEndeavors")
    if not Endeavors or not Endeavors.Render then return 0, 0 end
    return Endeavors:Render(content, contentWidth, yStart, collapsed)
end

function Tracker:_RenderEventsSection(content, contentWidth, yStart, collapsed)
    local Events = ns:GetSubsystem("TrackerEvents")
    if not Events or not Events.Render then return 0, 0 end
    return Events:Render(content, contentWidth, yStart, collapsed)
end

local SECTION_RENDERERS = {
    quests     = "_RenderQuestsSection",
    profession = "_RenderProfessionSection",
    endeavors  = "_RenderEndeavorsSection",
    events     = "_RenderEventsSection",
}

function Tracker:Render()
    local f = self.frame
    if not f then return end
    local content = f.content
    if not content then return end

    local DB = ns:GetSubsystem("DB")
    if DB and f.background then
        local cfg = DB.db.profile.tracker
        if cfg.showBackground then
            local c = cfg.backgroundColor or { r = 0, g = 0, b = 0, a = 0.6 }
            f.background:SetColorTexture(c.r or 0, c.g or 0, c.b or 0, c.a or 0.6)
            f.background:Show()
        else
            f.background:Hide()
        end
        if cfg.scale and cfg.scale > 0 and f:GetScale() ~= cfg.scale then
            f:SetScale(cfg.scale)
        end
    end

    local contentWidth = content:GetWidth()
    if contentWidth <= 0 then contentWidth = 280 end

    local hr, hg, hb = getHeaderColor()
    local gap = getBlockGap()

    local y = 0
    local sections = self.sectionList or {}
    local allCollapsed = self:IsAllCollapsed()

    if self.masterHeader then
        self.masterHeader:Show()
        self.masterHeader:ClearAllPoints()
        self.masterHeader:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -y)
        self.masterHeader:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
        self.masterHeader.collapse:SetText(allCollapsed and "+" or "–")
        y = y + MASTER_H + MASTER_GAP
    end

    -- Per-section visibility toggles. The user can hide entire sections
    -- (Profession, World Quests) if they don't use those features. When a
    -- section is hidden we skip both its renderer and its header.
    local DB = ns:GetSubsystem("DB")
    local cfg = DB and DB.db.profile.tracker
    local sectionVisible = {
        quests     = true,
        endeavors  = true,
        profession = not cfg or cfg.showProfessionSection  ~= false,
        events     = not cfg or cfg.showWorldQuestsSection ~= false,
    }

    for _, def in ipairs(sections) do
        local headerFrame = self.sectionFrames[def.id]
        if headerFrame and not sectionVisible[def.id] then
            -- Hidden section: still call the renderer with collapsed=true
            -- so it releases any of its pooled rows that might still be on
            -- screen from a previous render. Skip everything else.
            local rendererName = SECTION_RENDERERS[def.id]
            if rendererName and self[rendererName] then
                self[rendererName](self, content, contentWidth, 0, true)
            end
            headerFrame:Hide()
            headerFrame = nil
        end
        if headerFrame then
            local rendererName = SECTION_RENDERERS[def.id]
            local sectionCollapsed = allCollapsed or self:IsSectionCollapsed(def.id)

            local probeY = y + SECTION_H + 2
            local sectionHeight, sectionCount = 0, 0
            if rendererName and self[rendererName] then
                sectionHeight, sectionCount = self[rendererName](self, content, contentWidth, probeY, sectionCollapsed)
            end

            if allCollapsed then
                headerFrame:Hide()
            elseif sectionCount and sectionCount > 0 then
                headerFrame:Show()
                headerFrame:ClearAllPoints()
                headerFrame:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -y)
                headerFrame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
                headerFrame.count:SetText(tostring(sectionCount))
                headerFrame.collapse:SetText(sectionCollapsed and "+" or "–")
                -- Live-update header text colors from the user's chosen
                -- headerColor (Appearance tab). Cheap to redo every frame.
                if headerFrame.text     then headerFrame.text:SetTextColor(hr, hg, hb)     end
                if headerFrame.collapse then headerFrame.collapse:SetTextColor(hr, hg, hb) end
                y = y + SECTION_H + 2 + sectionHeight + gap
            else
                headerFrame:Hide()
            end
        end
    end

    content:SetHeight(math.max(1, y))
end

-- Canonical Blizzard sequence to abandon a quest from an addon. Routes
-- through Blizzard's ABANDON_QUEST StaticPopup (or ABANDON_QUEST_WITH_ITEMS
-- when the quest hands back items) so the user gets a real confirmation
-- dialog and the actual abandon happens in secure code.
--
-- We save/restore the "selected quest" cursor so other addons reading it
-- (e.g. Blizzard's own QuestMapFrame) don't see our transient mutation.
local function abandonQuest(questID)
    if not (questID and C_QuestLog and C_QuestLog.SetSelectedQuest
        and C_QuestLog.SetAbandonQuest and C_QuestLog.GetAbandonQuest) then
        return
    end
    if InCombatLockdown and InCombatLockdown() then return end

    local oldSelected = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest() or 0
    C_QuestLog.SetSelectedQuest(questID)
    C_QuestLog.SetAbandonQuest()

    -- Abandons are destructive — always route through the StaticPopup
    -- confirmation. The old questLog.confirmAbandon opt-out went away
    -- with the rest of the quest-log book.

    local abandonID = C_QuestLog.GetAbandonQuest()
    local title = (QuestUtils_GetQuestName and QuestUtils_GetQuestName(abandonID))
                  or (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(abandonID))
                  or "this quest"

    local items = C_QuestLog.GetAbandonQuestItems and C_QuestLog.GetAbandonQuestItems()
    if items and #items > 0 and StaticPopupDialogs and StaticPopupDialogs.ABANDON_QUEST_WITH_ITEMS then
        StaticPopup_Show("ABANDON_QUEST_WITH_ITEMS", title, table.concat(items, ", "))
    else
        StaticPopup_Show("ABANDON_QUEST", title)
    end

    -- Restore previous selection cursor regardless of which popup we showed.
    C_QuestLog.SetSelectedQuest(oldSelected or 0)
end

-- Pin is our force-show override. It bypasses the watch filter — pinned
-- quests stay visible in the tracker even when unwatched. Mutex with the
-- legacy hidden flag (preserved in saved vars but no longer has UI).
-- Pinning is our own state, not Blizzard's, so no event fires after — we
-- explicitly refresh both consumers (tracker + book List).
local function setPinned(DB, questID, value)
    DB.char.pinned[questID] = value or nil
    if value then DB.char.hidden[questID] = nil end
    local T = ns:GetSubsystem("Tracker")
    if T and T.Refresh then T:Refresh() end
end

-- Untrack via Blizzard's watch list — the canonical "stop showing this
-- quest in the tracker" mechanism. Equivalent to unticking the box in
-- Blizzard's quest log. QUEST_WATCH_LIST_CHANGED fires after, the cache
-- invalidates, and the tracker refreshes — no manual refresh needed.
local function setWatched(questID, watch)
    if watch then
        if C_QuestLog.AddQuestWatch then
            -- watchType 1 = Manual (what clicking the checkbox does).
            C_QuestLog.AddQuestWatch(questID)   -- defaults to Manual watch type
        end
    elseif C_QuestLog.RemoveQuestWatch then
        C_QuestLog.RemoveQuestWatch(questID)
    end
end

function Tracker:AbandonQuest(questID)
    abandonQuest(questID)
end

function Tracker:SetWatched(questID, watch)
    setWatched(questID, watch)
end

local function openQuestDetailsPopup(questID)
    if not questID then return end

    if C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_QuestLog")
    end

    if QuestMapQuestOptions_OpenQuestDetails then
        QuestMapQuestOptions_OpenQuestDetails(questID)
        return
    end

    if not QuestLogPopupDetailFrame then return end
    local idx = C_QuestLog and C_QuestLog.GetLogIndexForQuestID
                and C_QuestLog.GetLogIndexForQuestID(questID)
    if not idx then return end

    QuestLogPopupDetailFrame.questID = questID
    if C_QuestLog.SetSelectedQuest then
        C_QuestLog.SetSelectedQuest(questID)
    end
    if StaticPopup_Hide then
        StaticPopup_Hide("ABANDON_QUEST")
        StaticPopup_Hide("ABANDON_QUEST_WITH_ITEMS")
    end
    if QuestMapFrame_UpdateQuestDetailsButtons then
        QuestMapFrame_UpdateQuestDetailsButtons()
    end
    if QuestLogPopupDetailFrame_Update then
        QuestLogPopupDetailFrame_Update(true)
    end
    QuestLogPopupDetailFrame:Show()
end

-- Right-click context menu shared by the tracker's blocks AND the Quest
-- Log book's List rows — both need the same actions and toggle the same
-- DB flags. MenuUtil anchors the popup to whichever frame we pass in.
function Tracker:ShowBlockMenu(block, questID)
    if not (block and questID) then return end

    local DB = ns:GetSubsystem("DB")
    if not DB then return end
    local pinned  = DB.char.pinned[questID] == true
    local watched = C_QuestLog and C_QuestLog.GetQuestWatchType
                    and C_QuestLog.GetQuestWatchType(questID) ~= nil
    local focused = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
                    and C_SuperTrack.GetSuperTrackedQuestID() == questID
    local title   = (C_QuestLog and C_QuestLog.GetTitleForQuestID
                     and C_QuestLog.GetTitleForQuestID(questID))
                    or ("Quest #" .. tostring(questID))

    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end

    MenuUtil.CreateContextMenu(block, function(_owner, root)
        root:CreateTitle(title)

        if pinned then
            root:CreateButton("Unpin from tracker", function()
                setPinned(DB, questID, false)
            end)
        else
            root:CreateButton("Pin to tracker", function()
                setPinned(DB, questID, true)
            end)
        end

        -- Untrack / Track via Blizzard's watch list — the canonical
        -- mechanism. The cache invalidates and tracker refreshes
        -- automatically when QUEST_WATCH_LIST_CHANGED fires.
        if watched then
            root:CreateButton("Untrack Quest", function()
                setWatched(questID, false)
            end)
        else
            root:CreateButton("Track Quest", function()
                setWatched(questID, true)
            end)
        end

        if focused then
            root:CreateButton("Unfocus", function()
                if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
                    C_SuperTrack.SetSuperTrackedQuestID(0)
                end
            end)
        else
            root:CreateButton("Focus", function()
                if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
                    C_SuperTrack.SetSuperTrackedQuestID(questID)
                end
            end)
        end

        root:CreateButton("Show in Quest Log", function()
            if C_AddOns and C_AddOns.LoadAddOn then
                C_AddOns.LoadAddOn("Blizzard_QuestLog")
            end
            if QuestMapFrame_OpenToQuestDetails then
                QuestMapFrame_OpenToQuestDetails(questID)
            elseif ToggleQuestLog then
                ToggleQuestLog()
            end
        end)

        root:CreateButton("Open Quest Details", function()
            openQuestDetailsPopup(questID)
        end)

        root:CreateDivider()

        -- Abandon is destructive — color it red and route through Blizzard's
        -- StaticPopup so the user gets a confirmation before anything happens.
        root:CreateButton("|cffff5050Abandon Quest|r", function()
            abandonQuest(questID)
        end)

        root:CreateDivider()
        root:CreateButton("Cancel", function() end)
    end)
end

function Tracker:OnInitialize()
    disableBlizzardTracker()
    self:BuildFrame()
end

function Tracker:OnEnable()
    local Events = ns:GetSubsystem("Events")
    local function refresh() self:Refresh() end
    Events:On("QUEST_LOG_UPDATE",         refresh)
    Events:On("QUEST_ACCEPTED",           refresh)
    Events:On("QUEST_REMOVED",            refresh)
    Events:On("QUEST_TURNED_IN",          refresh)
    Events:On("QUEST_AUTOCOMPLETE",       refresh)   -- auto-complete popup appeared
    Events:On("QUEST_WATCH_LIST_CHANGED", refresh)   -- watched/unwatched flipped
    Events:On("SUPER_TRACKING_CHANGED",   refresh)   -- focus toggle repaints glow
    Events:On("ZONE_CHANGED_NEW_AREA",    refresh)
    Events:On("PLAYER_ENTERING_WORLD",    refresh)
    self:Refresh()
end
