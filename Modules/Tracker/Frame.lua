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
local _popups   = {}
local SECTION_H        = 26   -- "Quests" section header band (fits the larger header text)
local HEADER_FONT_DELTA = 4   -- section headers render this many points larger
                              -- than quest titles so the hierarchy reads right
local WQ_PIN_FRACTION  = 0.40 -- fallback cap for the pinned World Quests
                              -- region (DB worldQuestsPinnedMaxFraction
                              -- overrides once loaded)
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

    -- Optional border. f is a BackdropTemplate frame and f.background is
    -- SetAllPoints(f), so a backdrop EDGE on f wraps the background region
    -- exactly. Set the edge once here with NO bgFile (the border must not
    -- add its own fill — f.background owns the fill); Tracker:Render
    -- applies the user's color/visibility, mirroring how f.background is
    -- created hidden here and shown/colored in Render. The edge auto-
    -- tracks frame size on resize via BackdropTemplate.
    f._borderSize = math.max(1, cfg.borderSize or 1)
    f:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = f._borderSize })
    f:SetBackdropColor(0, 0, 0, 0)
    f:SetBackdropBorderColor(0, 0, 0, 0)

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
    drag:SetScript("OnEnter", function()
        dragHint:SetColorTexture(1, 1, 1, 0.15)
        local DBs = ns:GetSubsystem("DB")
        local locked = DBs and DBs.db.profile.general and DBs.db.profile.general.lockTracker
        GameTooltip:SetOwner(drag, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Everything Quests", 0.92, 0.72, 0.02)
        if locked then
            GameTooltip:AddLine("Position locked", 1, 0.3, 0.3)
            GameTooltip:AddLine('Uncheck "Lock tracker position" in /eqs \226\134\146 General.', 0.8, 0.8, 0.8, true)
        else
            GameTooltip:AddLine("Drag to move the tracker", 1, 1, 1)
            GameTooltip:AddLine("/eqs for options", 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)
    drag:SetScript("OnLeave", function()
        dragHint:SetColorTexture(1, 1, 1, 0)
        GameTooltip:Hide()
    end)
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
    -- The scenario banner grows/shrinks without firing a quest event, so
    -- the pinned-WQ height cap (computed from available space in Render)
    -- would go stale. A throttled Refresh on its resize keeps it correct.
    scenarioContainer:SetScript("OnSizeChanged", function() self:Refresh() end)

    -- World Quests region: the always-visible "World Quests" header plus
    -- its own internally-scrolling list. Its TOP anchors flush to the
    -- BOTTOM of the main scroll (set after `scroll` is created below), so
    -- it sits directly beneath the quest content and slides down as
    -- quests populate — no dead gap. The main scroll is sized to its
    -- content (capped) in Render(); once quests overflow, the scroll hits
    -- its cap and this region lands at the bottom with quests scrolling
    -- above. Height set every frame by _RenderPinnedEvents (1 + Hidden
    -- when there are none).
    local eventsRegion = CreateFrame("Frame", "EQTrackerEventsRegion", f)
    eventsRegion:SetHeight(1)
    eventsRegion:Hide()
    f.eventsRegion = eventsRegion

    local eventsScroll = CreateFrame("ScrollFrame", "EQTrackerEventsScroll", eventsRegion, "UIPanelScrollFrameTemplate")
    -- Below the pinned header (SECTION_H + 2, matching the header gap the
    -- main loop uses); fills the rest of the region.
    eventsScroll:SetPoint("TOPLEFT",     eventsRegion, "TOPLEFT",  0, -(SECTION_H + 2))
    eventsScroll:SetPoint("BOTTOMRIGHT", eventsRegion, "BOTTOMRIGHT", 0, 0)
    local eventsContent = CreateFrame("Frame", nil, eventsScroll)
    eventsContent:SetSize(cfg.width - 26, 1)
    eventsScroll:SetScrollChild(eventsContent)
    f.eventsScroll  = eventsScroll
    f.eventsContent = eventsContent

    -- Scroll-bar background for the events list, mirroring f.scrollBarBG.
    local eBg = f:CreateTexture(nil, "BORDER")
    local eBar = eventsScroll.ScrollBar or eventsScroll.scrollBar
    if eBar then
        eBg:SetPoint("TOPLEFT",     eBar, "TOPLEFT",    -1, 0)
        eBg:SetPoint("BOTTOMRIGHT", eBar, "BOTTOMRIGHT", 1, 0)
    else
        eBg:SetPoint("TOPLEFT",     eventsScroll, "TOPRIGHT",    0, 1)
        eBg:SetPoint("BOTTOMRIGHT", eventsRegion, "BOTTOMRIGHT", -2, 0)
    end
    eBg:Hide()
    f.eventsScrollBarBG = eBg

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    -- Only the TOP edge is anchored (under the scenario banner). Width +
    -- height are set every frame in Render(): height = the quest content
    -- height, capped so the pinned WQ region still fits. This is what
    -- makes the scroll grow downward with the quests instead of always
    -- filling the whole frame and leaving a dead gap above World Quests.
    scroll:SetPoint("TOPLEFT", scenarioContainer, "BOTTOMLEFT", 0, -2)

    -- WQ region sits flush against the scroll's bottom edge, so it tracks
    -- the quest content. (Deferred here because it needs `scroll`.)
    eventsRegion:SetPoint("TOPLEFT",  scroll, "BOTTOMLEFT",  0, -2)
    eventsRegion:SetPoint("TOPRIGHT", scroll, "BOTTOMRIGHT", 0, -2)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(cfg.width - 26, 1)
    scroll:SetScrollChild(content)

    -- Content width should track the frame as it resizes so blocks reflow.
    f:SetScript("OnSizeChanged", function() self:Refresh() end)

    -- Background strip directly behind the scroll bar so the low-contrast
    -- bar is easy to see. Anchored to the bar widget itself (not the gutter
    -- geometry) so it always sits *under* the bar instead of beside it. On
    -- `f` at BORDER layer so the bar — a child of `scroll` — renders on top.
    -- Colour/visibility applied in Render().
    local sbBG = f:CreateTexture(nil, "BORDER")
    local sBar = scroll.ScrollBar or scroll.scrollBar
    if sBar then
        sbBG:SetPoint("TOPLEFT",     sBar, "TOPLEFT",    -1, 0)
        sbBG:SetPoint("BOTTOMRIGHT", sBar, "BOTTOMRIGHT", 1, 0)
    else
        sbBG:SetPoint("TOPLEFT",     scroll, "TOPRIGHT",    0, 1)
        sbBG:SetPoint("BOTTOMRIGHT", f,      "BOTTOMRIGHT", -2, GRIP_SIZE + 2)
    end
    sbBG:Hide()
    f.scrollBarBG = sbBG

    f.scroll = scroll
    f.content = content

    -- Mouse-wheel scrolling for both lists. Always on, so the tracker still
    -- scrolls when the scroll bar is hidden (Tracker Options > Hide scroll
    -- bar). No-op when the content fits (vertical range 0), and it leaves the
    -- bar's own dragging untouched when the bar is visible.
    local WHEEL_STEP = 24
    local function wheelScroll(sf, delta)
        local range = sf:GetVerticalScrollRange() or 0
        if range <= 0 then return end
        local new = (sf:GetVerticalScroll() or 0) - delta * WHEEL_STEP
        if new < 0 then new = 0 elseif new > range then new = range end
        sf:SetVerticalScroll(new)
    end
    for _, sf in ipairs({ scroll, eventsScroll }) do
        sf:EnableMouseWheel(true)
        sf:SetScript("OnMouseWheel", wheelScroll)
    end

    f.drag    = drag
    f.grip    = grip
    self.frame = f

    self:BuildSectionHeaders(content)
end

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

    local sections = {
        -- Campaign quests are split out of "Quests" into their own section
        -- (Blizzard surfaces the campaign prominently too). Same header
        -- style/code path as every other section — see _RenderQuestGroup.
        { id = "campaign",   title = "Campaign" },
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

    -- The World Quests ("events") section is pinned to the bottom of the
    -- tracker in its own region rather than scrolling inline. Reparent its
    -- header into that region so it stays visible above the (internally
    -- scrolling) WQ list. Same header object & style as every other
    -- section — only the parent/anchor changes.
    local eh = self.sectionFrames["events"]
    if eh and self.frame and self.frame.eventsRegion then
        eh:SetParent(self.frame.eventsRegion)
        eh:ClearAllPoints()
        eh:SetPoint("TOPLEFT",  self.frame.eventsRegion, "TOPLEFT",  0, 0)
        eh:SetPoint("TOPRIGHT", self.frame.eventsRegion, "TOPRIGHT", 0, 0)
    end
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

-- Shared renderer for the Campaign + general Quests sections. They are the
-- same surface, split only by campaign membership, so they go through ONE
-- code path — identical block/popup rendering and identical formatting by
-- construction. `wantCampaign` selects which group this call renders.
--
-- The Blocks/AC pools are reset ONCE per frame in Render() (not here):
-- Campaign renders before Quests, so releasing inside the Quests pass
-- would clobber the Campaign group's live blocks.
function Tracker:_RenderQuestGroup(content, contentWidth, yStart, collapsed, wantCampaign)
    local DB      = ns:GetSubsystem("DB")
    local Cache   = ns:GetSubsystem("Cache")
    local Filters = ns:GetSubsystem("TrackerFilters")
    local Sort    = ns:GetSubsystem("TrackerSort")
    local Blocks  = ns:GetSubsystem("TrackerBlocks")
    local AC      = ns:GetSubsystem("TrackerAutoComplete")

    local profile = DB.db.profile.tracker
    local quests  = Cache:All()

    -- Active "click to complete" popups. Build the FULL questID set so the
    -- block loop in BOTH groups excludes a quest that's showing as a popup,
    -- but only this group's matching popups get rendered/counted here.
    local allPopups = (AC and AC:GetActivePopups()) or {}
    wipe(_popupSet)
    for i = 1, #allPopups do _popupSet[allPopups[i].questID] = true end

    wipe(_popups)
    local popups, pcount = _popups, 0
    for i = 1, #allPopups do
        local pq = quests[allPopups[i].questID]
        local pIsCampaign = (pq and pq.isCampaign) and true or false
        if pIsCampaign == wantCampaign then
            pcount = pcount + 1
            popups[pcount] = allPopups[i]
        end
    end

    wipe(_visible)
    local visible, count, total = _visible, 0, 0
    for questID, q in pairs(quests) do
        if (q.isCampaign and true or false) == wantCampaign then
            -- total = every quest of THIS category in the log (tracked
            -- or not); count = the ones actually shown in the section.
            total = total + 1
            if not _popupSet[questID] and Filters:Visible(questID, q) then
                count = count + 1
                visible[count] = q
            end
        end
    end

    if collapsed then return 0, count + pcount, total end

    table.sort(visible, Sort.For(profile.sortMode, profile.manualOrder))

    local y = yStart

    local gap = getBlockGap()
    if AC then
        for i = 1, pcount do
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
        local b = Blocks:AcquireFor(content, q.questID)
        b:SetWidth(contentWidth)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        Blocks:RenderQuest(b, q, profile.simplifyMode)
        y = y + b:GetHeight() + gap
    end

    return y - yStart, count + pcount, total
end

-- Campaign quests only (q.isCampaign — set in Core/Cache.lua from the
-- quest's campaignID). Header auto-hides when the player has none, via
-- the zero-count branch in Render().
function Tracker:_RenderCampaignSection(content, contentWidth, yStart, collapsed)
    return self:_RenderQuestGroup(content, contentWidth, yStart, collapsed, true)
end

-- Everything that is NOT a campaign quest (campaign quests now live in
-- their own section above).
function Tracker:_RenderQuestsSection(content, contentWidth, yStart, collapsed)
    return self:_RenderQuestGroup(content, contentWidth, yStart, collapsed, false)
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
    campaign   = "_RenderCampaignSection",
    quests     = "_RenderQuestsSection",
    profession = "_RenderProfessionSection",
    endeavors  = "_RenderEndeavorsSection",
    events     = "_RenderEventsSection",
}

-- Stable, allocation-free closure for the combat-deferred tracker rescale
-- (SetScale is protected once the tracker has secure item-button
-- descendants). Re-reads live state so a deferred combat-end apply is
-- correct even if the scale changed again meanwhile.
local function applyTrackerScale()
    local DB      = ns:GetSubsystem("DB")
    local Tracker = ns:GetSubsystem("Tracker")
    local fr = Tracker and Tracker.frame
    local sc = DB and DB.db.profile.tracker.scale
    if fr and sc and sc > 0 and fr:GetScale() ~= sc and not InCombatLockdown() then
        fr:SetScale(sc)
    end
end

-- Hide or restore a scroll frame's bar. UIPanelScrollFrameTemplate auto-shows
-- its bar whenever the scroll range changes, so a one-off Hide() won't stick;
-- a one-time OnShow guard re-hides it while `_eqHidden` is set. On restore we
-- can't rely on the template re-showing the bar (it only reacts to a range
-- *change*, which a settings toggle doesn't produce), so we set its shown
-- state directly from the current scroll range. Must be called after sizing.
local function setScrollBarHidden(sf, hidden)
    if not sf then return end
    local bar = sf.ScrollBar or sf.scrollBar
    if not bar then return end
    bar._eqHidden = hidden
    if not bar._eqShowHook then
        bar._eqShowHook = true
        bar:HookScript("OnShow", function(b) if b._eqHidden then b:Hide() end end)
    end
    if hidden then
        if bar:IsShown() then bar:Hide() end
    else
        bar:SetShown((sf:GetVerticalScrollRange() or 0) > 0.5)
    end
end

function Tracker:Render()
    local f = self.frame
    if not f then return end
    local content = f.content
    if not content then return end

    -- Reset the shared Blocks/AC pools ONCE per frame, before any section
    -- renders. The Campaign and Quests sections both draw from these pools
    -- and Campaign renders first — releasing inside the Quests renderer
    -- (where this used to live) would wipe the Campaign group's live rows.
    local _Blocks = ns:GetSubsystem("TrackerBlocks")
    -- Open the block render pass: resolves font + render cfg once for the
    -- whole pass and marks every live block as a sweep candidate. Blocks
    -- are reused across passes by questID and the unused ones are freed by
    -- _Blocks:Sweep() at the very end of this function.
    if _Blocks and _Blocks.BeginRenderPass then _Blocks:BeginRenderPass() end
    local _AC = ns:GetSubsystem("TrackerAutoComplete")
    if _AC and _AC.ReleaseAll then _AC:ReleaseAll() end

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
        -- Border wraps the same rect as f.background, independent of
        -- whether the background fill is shown. Transparent = "off".
        -- SetBackdrop is relatively heavy and the only way to change edge
        -- thickness, so re-apply it ONLY when the size actually changed
        -- (initial set is in BuildFrame); per-pass cost stays just the
        -- cheap SetBackdropBorderColor below.
        local bsz = math.max(1, cfg.borderSize or 1)
        if f._borderSize ~= bsz then
            f._borderSize = bsz
            f:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = bsz })
            f:SetBackdropColor(0, 0, 0, 0)
        end
        if cfg.showBorder then
            local bc = cfg.borderColor or { r = 0.427, g = 0.020, b = 0.004, a = 1 }
            f:SetBackdropBorderColor(bc.r or 0, bc.g or 0, bc.b or 0, bc.a or 1)
        else
            f:SetBackdropBorderColor(0, 0, 0, 0)
        end
        -- The bar BG strip only makes sense behind a visible bar, so it's
        -- suppressed when the bar is hidden. (The bars themselves are toggled
        -- AFTER sizing, below, where the scroll range is accurate.)
        local hideBar = cfg.hideScrollBar == true
        if f.scrollBarBG then
            if cfg.scrollBarBg ~= false and not hideBar then
                local s = cfg.scrollBarBgColor or { r = 0.60, g = 0.60, b = 0.65, a = 0.25 }
                f.scrollBarBG:SetColorTexture(s.r or 0.60, s.g or 0.60, s.b or 0.65, s.a or 0.25)
                f.scrollBarBG:Show()
            else
                f.scrollBarBG:Hide()
            end
        end
        -- SetScale is a PROTECTED frame method: with secure item-button
        -- descendants, calling it in combat is blocked
        -- (ADDON_ACTION_BLOCKED). Apply out of combat; if a change is
        -- pending mid-combat, defer to combat-end so it still takes
        -- effect. (Also set by BuildFrame + the Appearance slider, so this
        -- only matters on a profile switch.)
        if cfg.scale and cfg.scale > 0 and f:GetScale() ~= cfg.scale then
            local Ev = ns:GetSubsystem("Events")
            if Ev and Ev.InCombat and Ev:InCombat() then
                Ev:RunWhenOutOfCombat("trackerSetScale", applyTrackerScale)
            else
                f:SetScale(cfg.scale)
            end
        end
    end

    local contentWidth = content:GetWidth()
    if contentWidth <= 0 then contentWidth = 280 end

    local hr, hg, hb = getHeaderColor()
    local gap = getBlockGap()

    local y = 0
    local sections = self.sectionList or {}

    -- Per-section visibility toggles. The user can hide entire sections
    -- (Profession, World Quests) if they don't use those features. When a
    -- section is hidden we skip both its renderer and its header.
    local DB = ns:GetSubsystem("DB")
    local cfg = DB and DB.db.profile.tracker
    local sectionVisible = {
        campaign   = true,
        quests     = true,
        endeavors  = true,
        profession = not cfg or cfg.showProfessionSection  ~= false,
        events     = not cfg or cfg.showWorldQuestsSection ~= false,
    }

    -- Max on-screen height for the pinned World Quests region. Available
    -- inner height = frame height minus the top drag strip, the live
    -- scenario banner, the main scroll's -2 top gap, and the bottom grip
    -- reservation. The region is capped at a fraction of that.
    local scenarioH = (f.scenarioContainer and f.scenarioContainer:GetHeight()) or 1
    local available = (f:GetHeight() or 0) - DRAG_HANDLE_H - scenarioH - 2 - (GRIP_SIZE + 2)
    if available < 1 then available = 1 end
    local fraction  = (cfg and cfg.worldQuestsPinnedMaxFraction) or WQ_PIN_FRACTION
    local eventsCap = math.floor(available * fraction)

    for _, def in ipairs(sections) do
      -- "events" (World Quests) is pinned to the bottom of the tracker in
      -- its own capped, internally-scrolling region; it is rendered after
      -- this loop by _RenderPinnedEvents instead of inline in the main
      -- scroll, so skip it here.
      if def.id ~= "events" then
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
            local sectionCollapsed = self:IsSectionCollapsed(def.id)

            local probeY = y + SECTION_H + 2
            local sectionHeight, sectionCount, sectionTotal = 0, 0, nil
            if rendererName and self[rendererName] then
                sectionHeight, sectionCount, sectionTotal = self[rendererName](self, content, contentWidth, probeY, sectionCollapsed)
            end

            if sectionCount and sectionCount > 0 then
                headerFrame:Show()
                headerFrame:ClearAllPoints()
                headerFrame:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -y)
                headerFrame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
                -- Count display. Campaign & Quests show "shown / total of
                -- that category" (e.g. 3/9) when the toggle is on —
                -- sectionTotal is the per-category total returned by
                -- _RenderQuestGroup. Sections with no meaningful
                -- per-category total (Profession/Endeavors) show the plain
                -- count. Every count renders in the section-header color
                -- at the quest-description font size for one consistent
                -- look.
                local _M = ns:GetSubsystem("Media")
                if (def.id == "campaign" or def.id == "quests")
                   and type(sectionTotal) == "number"
                   and (not cfg or cfg.showQuestTotal ~= false) then
                    headerFrame.count:SetText(sectionCount .. "/" .. sectionTotal)
                else
                    headerFrame.count:SetText(tostring(sectionCount))
                end
                if _M and _M.ApplyTrackerFont then
                    _M:ApplyTrackerFont(headerFrame.count, -2)   -- = subText size
                end
                headerFrame.count:SetTextColor(hr, hg, hb)       -- match header
                headerFrame.collapse:SetText(sectionCollapsed and "+" or "–")
                -- Live-update header font + colors from the user's chosen
                -- font/size/headerColor (Appearance tab). Headers render in
                -- the user's font HEADER_FONT_DELTA points larger than quest
                -- titles so the section hierarchy reads correctly. Cheap to
                -- redo every frame.
                local Media = ns:GetSubsystem("Media")
                if headerFrame.text then
                    if Media and Media.ApplyTrackerFont then
                        Media:ApplyTrackerFont(headerFrame.text, HEADER_FONT_DELTA)
                    end
                    headerFrame.text:SetTextColor(hr, hg, hb)
                end
                if headerFrame.collapse then headerFrame.collapse:SetTextColor(hr, hg, hb) end
                y = y + SECTION_H + 2 + sectionHeight + gap
            else
                headerFrame:Hide()
            end
        end
      end
    end

    local questContentH = y
    content:SetHeight(math.max(1, questContentH))

    -- Render the WQ region; it returns its own height so we can size the
    -- main scroll to the quest content but no taller than the room left
    -- above the WQ region. Net effect: WQ sits flush under the quests
    -- (no gap) until the quests would overflow, then the scroll caps and
    -- the quests scroll above a bottom-resting WQ region.
    local wqRegionH = self:_RenderPinnedEvents(eventsCap) or 0

    if f.scroll then
        local scrollW = math.max(1, (f:GetWidth() or 0) - 26)
        local scrollH = math.min(questContentH, available - wqRegionH)
        if scrollH < 1 then scrollH = 1 end
        f.scroll:SetSize(scrollW, scrollH)
        if f.scroll.UpdateScrollChildRect then f.scroll:UpdateScrollChildRect() end
    end

    -- Toggle the scroll bars AFTER both scroll frames are sized (the WQ list
    -- is sized inside _RenderPinnedEvents above), so GetVerticalScrollRange is
    -- accurate when we decide whether to restore a bar.
    do
        local DB2 = ns:GetSubsystem("DB")
        local hideBar = DB2 and DB2.db.profile.tracker.hideScrollBar == true
        setScrollBarHidden(f.scroll, hideBar)
        setScrollBarHidden(f.eventsScroll, hideBar)
    end

    -- SWEEP: free every block not re-acquired this pass (quest turned in,
    -- abandoned, filtered out, moved to a popup, or its section
    -- collapsed). Done here, after ALL sections AND the pinned WQ region,
    -- so a quest moving between the Campaign and Quests sections is never
    -- falsely swept. _RenderPinnedEvents uses a separate pool.
    if _Blocks and _Blocks.Sweep then _Blocks:Sweep() end

    -- Usable quest-item buttons track block positions; reposition them
    -- AFTER Sweep so Blocks.byID reflects exactly this pass's quests.
    local _IB = ns:GetSubsystem("TrackerItemButtons")
    if _IB and _IB.Reposition then _IB:Reposition() end
end

-- Render the always-visible World Quests region pinned at the bottom of
-- the tracker. The "World Quests" header is fixed at the top of the
-- region (never scrolls away); the WQ rows live in an internal scroll
-- frame capped at `eventsCap` px, so a heavy WQ load scrolls in place
-- instead of swallowing the tracker. When there are none / the section
-- is toggled off, the region collapses to 1px + Hide and the main scroll
-- reclaims the space automatically (its bottom is anchored to this
-- region's TOP).
function Tracker:_RenderPinnedEvents(eventsCap)
    local f = self.frame
    if not f then return 0 end
    local region   = f.eventsRegion
    local escroll   = f.eventsScroll
    local econtent = f.eventsContent
    local header   = self.sectionFrames and self.sectionFrames["events"]
    if not (region and escroll and econtent) then return 0 end

    local DB  = ns:GetSubsystem("DB")
    local cfg = DB and DB.db.profile.tracker
    local sectionOn = not cfg or cfg.showWorldQuestsSection ~= false
    local collapsed = self:IsSectionCollapsed("events")
    local Events    = ns:GetSubsystem("TrackerEvents")

    -- WQ row width tracks the events scroll (mirrors how the main path
    -- uses content:GetWidth()), so rows reflow on resize.
    econtent:SetWidth(math.max(1, escroll:GetWidth()))
    local ewidth = econtent:GetWidth()
    if ewidth <= 0 then ewidth = 280 end

    local function collapseRegion()
        if header then header:Hide() end
        escroll:Hide()
        if f.eventsScrollBarBG then f.eventsScrollBarBG:Hide() end
        region:SetHeight(1)
        region:Hide()
    end

    -- Section toggled off: release any pooled WQ rows (parity with the
    -- main loop's hidden-section path) and collapse the region.
    if not sectionOn then
        if Events and Events.Render then Events:Render(econtent, ewidth, 0, true) end
        collapseRegion()
        return 0
    end

    local heightUsed, count = 0, 0
    if Events and Events.Render then
        heightUsed, count = Events:Render(econtent, ewidth, 0, collapsed)
    end

    if not count or count == 0 then
        collapseRegion()
        return 0
    end

    region:Show()

    -- Pinned header — same frame/style as every other section header,
    -- only the parent (eventsRegion) differs. Font/color refreshed each
    -- frame exactly like the main loop does.
    if header then
        header:Show()
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT",  region, "TOPLEFT",  0, 0)
        header:SetPoint("TOPRIGHT", region, "TOPRIGHT", 0, 0)
        header.count:SetText(tostring(count))
        header.collapse:SetText(collapsed and "+" or "–")
        local hr, hg, hb = getHeaderColor()
        local Media = ns:GetSubsystem("Media")
        if header.text then
            if Media and Media.ApplyTrackerFont then
                Media:ApplyTrackerFont(header.text, HEADER_FONT_DELTA)
            end
            header.text:SetTextColor(hr, hg, hb)
        end
        if header.collapse then header.collapse:SetTextColor(hr, hg, hb) end
        -- World Quests has no meaningful per-category total, so it stays
        -- a plain count — but match the header color + description font
        -- so every section's count reads consistently.
        if header.count then
            if Media and Media.ApplyTrackerFont then
                Media:ApplyTrackerFont(header.count, -2)
            end
            header.count:SetTextColor(hr, hg, hb)
        end
    end

    if collapsed then
        escroll:Hide()
        if f.eventsScrollBarBG then f.eventsScrollBarBG:Hide() end
        region:SetHeight(SECTION_H + 2)   -- header band only
        return SECTION_H + 2
    end

    escroll:Show()
    econtent:SetHeight(math.max(1, heightUsed))

    -- Viewport = WQ content height, capped. Always allow ~one row so a
    -- short tracker still shows something scrollable.
    local capViewport = (eventsCap or 0) - (SECTION_H + 2)
    if capViewport < 30 then capViewport = 30 end
    local viewport = math.min(heightUsed, capViewport)
    if viewport < 1 then viewport = 1 end
    region:SetHeight(SECTION_H + 2 + viewport)

    if escroll.UpdateScrollChildRect then escroll:UpdateScrollChildRect() end

    -- Scroll-bar background strip, only when the list actually overflows
    -- the cap (mirrors the main scrollBarBG color/visibility logic).
    if f.eventsScrollBarBG then
        local needsBar = heightUsed > viewport + 0.5
        if needsBar and (not cfg or (cfg.scrollBarBg ~= false and cfg.hideScrollBar ~= true)) then
            local s = (cfg and cfg.scrollBarBgColor) or { r = 0.60, g = 0.60, b = 0.65, a = 0.25 }
            f.eventsScrollBarBG:SetColorTexture(s.r or 0.60, s.g or 0.60, s.b or 0.65, s.a or 0.25)
            f.eventsScrollBarBG:Show()
        else
            f.eventsScrollBarBG:Hide()
        end
    end

    return SECTION_H + 2 + viewport
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

-- One-time onboarding popup: the drag strip is invisible by design, so a
-- first-run dialog tells the player how to move the tracker. preferredIndex 3
-- is the standard guard against tainting the default StaticPopup slot.
StaticPopupDialogs["EVERYTHINGQUESTS_MOVE_HINT"] = {
    text = "|cffEBB706Everything Quests|r\n\nDrag the top edge of the tracker to move it.\n\nType |cffEBB706/eqs|r for options.",
    button1 = OKAY,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    preferredIndex = 3,
}

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

    -- One-time discovery popup. The flag lives in the account-wide chain
    -- cache (a plain saved table that reliably persists — AceDB's .global
    -- scope is never created for this DB, so the previous attempt silently
    -- no-op'd). Set immediately so it never shows twice; deferred so it
    -- clears the loading screen first.
    local DBs   = ns:GetSubsystem("DB")
    local cache = DBs and DBs.chainCache
    if cache and not cache._shownMoveHint then
        cache._shownMoveHint = true
        C_Timer.After(4, function()
            if StaticPopup_Show then StaticPopup_Show("EVERYTHINGQUESTS_MOVE_HINT") end
        end)
    end
end
