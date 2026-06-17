-- Modules/ChainGuide/Frame.lua
-- Standalone Chain Guide window. Three panes:
--   1. Categories (left)        — list of zones registered in the database
--   2. Chains (middle)          — chains in the selected category, with progress
--   3. Detail   (right)         — quests in the selected chain, with status
--
-- Navigation uses ChainGuideHistory so Back/Forward work like a browser.
-- Frame is built lazily on first Toggle(); subsequent toggles just show/hide.
--
-- Why a separate window (not a tab in the Quest Log book): the chain guide
-- is reference material the user dips into out-of-game-flow. Embedding it
-- into the quest log would cramp the existing layout and tangle two
-- unrelated workflows.

local _, ns = ...
local L = ns.L

local CG = ns:RegisterSubsystem("ChainGuide", {})

local PANE_GAP        = 6
local TITLE_BAR_H     = 22
local NAV_BAR_H       = 28
local RAIL_W          = 250          -- the single drill-down navigation rail
local ROW_H           = 22
local MIN_W           = 760          -- smallest the resizable window may get
local MIN_H           = 460
local DEFAULT_W       = 1160
local DEFAULT_H       = 720
-- Y of the panes' top edge (below title bar + nav bar + one gap). Shared by
-- Build and the rail-collapse re-anchor so they can't drift.
local PANES_TOP       = -(TITLE_BAR_H + NAV_BAR_H + PANE_GAP)

-- The navigation rail shows EITHER categories OR a category's chains (drill-
-- down), never both at once, so one pooled row set serves both lists.
CG.railRowPool = {}; CG.railRowsActive = {}

-- Static row scripts. Wired ONCE per pooled row in buildListRow and reused
-- across every render — the per-row click/tooltip data rides on frame fields
-- (row.navKind / row.navID / row._ttTitle / row._ttSub) that each render
-- overwrites, instead of allocating a fresh capturing closure per row per
-- render. (These renders are on-demand, not per-frame, so this is hygiene
-- rather than a hot-path win — but it keeps the pattern consistent with the
-- tracker's build-time wiring.)
local function onRowClick(self)
    if self.navKind == "cat" then
        CG:NavigateCategory(self.navID)
    elseif self.navKind == "chain" then
        CG:NavigateChain(self.navID)
    end
end
local function onRowEnter(self)
    if not self._ttTitle then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self._ttTitle, 1, 0.82, 0, 1, true)
    if self._ttSub and self._ttSub ~= "" then
        GameTooltip:AddLine(self._ttSub, 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end
local function onRowLeave() GameTooltip:Hide() end

-- ─── Row factories ────────────────────────────────────────────────────
-- Categories and chain-list rows share the same look — small clickable
-- buttons with a hover highlight and a yellow-tinted active state.
local function buildListRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    local sel = r:CreateTexture(nil, "BACKGROUND")
    sel:SetAllPoints()
    sel:SetColorTexture(0.92, 0.72, 0.02, 0.18)
    sel:Hide()
    r.selectedTex = sel

    r.title = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.title:SetPoint("LEFT", 8, 0)
    r.title:SetPoint("RIGHT", -50, 0)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)

    r.suffix = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.suffix:SetPoint("RIGHT", -8, 0)
    r.suffix:SetJustifyH("RIGHT")
    r.suffix:SetTextColor(0.92, 0.72, 0.02)

    -- Atlas check shown to the left of the suffix when the chain is fully
    -- completed; placed left-of-suffix so the text stays flush right.
    r.completeIcon = r:CreateTexture(nil, "OVERLAY")
    r.completeIcon:SetSize(12, 12)
    r.completeIcon:SetPoint("RIGHT", r.suffix, "LEFT", -4, 0)
    r.completeIcon:Hide()

    -- Static scripts wired once; per-row data set at render time.
    r:SetScript("OnClick", onRowClick)
    r:SetScript("OnEnter", onRowEnter)
    r:SetScript("OnLeave", onRowLeave)
    return r
end

local function acquireRow(pool, active, parent)
    return ns.Util.AcquirePooled(pool, active, parent, buildListRow)
end

local function releaseAllRows(pool, active)
    for i = #active, 1, -1 do
        local r = active[i]
        r:Hide()
        r:ClearAllPoints()
        -- Scripts stay attached (static, set in buildListRow). Clear only the
        -- per-row data so a pooled row can't carry stale click/tooltip state.
        r.navKind, r.navID = nil, nil
        r._ttTitle, r._ttSub = nil, nil
        r.selectedTex:Hide()
        r.suffix:SetText("")
        r.suffix:SetTextColor(0.92, 0.72, 0.02)
        if r.completeIcon then r.completeIcon:Hide() end
        pool[#pool + 1] = r
        active[i] = nil
    end
end

-- Try a Blizzard atlas; fall back to a Blizzard texture so a renamed atlas
-- in a future patch leaves us with *something* visible instead of blank.
local function setCheckAtlas(tex)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("common-icon-checkmark") then
        tex:SetAtlas("common-icon-checkmark", false)
    else
        tex:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        tex:SetTexCoord(0, 1, 0, 1)
    end
end

-- Hover tooltip showing the row's FULL name (+ optional second line). The
-- list panes are narrow and some names are long ("The War of Light and
-- Shadow", long questline titles); the row text is clipped with no wrap,
-- so hovering is the clean, zero-layout-risk way to read the whole thing.
local function setRowTooltip(row, title, sub)
    row._ttTitle = title
    row._ttSub   = sub
end

-- ─── Build window ──────────────────────────────────────────────────────
function CG:Build()
    if self.frame then return end

    local f = CreateFrame("Frame", "EQChainGuideFrame", UIParent, "BackdropTemplate")
    f:SetSize(1160, 720)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:Hide()

    -- Match the Main UI (Options) chrome exactly: same flat near-black fill at
    -- the same opacity + a 1px #a2000a red border. Reuses ns.Util.color.optionsBg
    -- so the two windows can't drift apart. (Was a lighter, more transparent
    -- standalone texture with no border.)
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(unpack(ns.Util.color.optionsBg))
    f:SetBackdropBorderColor(0.635, 0.000, 0.039, 1.0)   -- #a2000a

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetHeight(TITLE_BAR_H)
    -- 1px inset so the frame's red top border isn't painted over by this
    -- (child frames render above the parent backdrop, incl. its border).
    titleBar:SetPoint("TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", -1, -1)
    local tbg = titleBar:CreateTexture(nil, "ARTWORK")
    tbg:SetAllPoints()
    tbg:SetColorTexture(0, 0, 0, 0.85)
    f.title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("LEFT", 12, 0)
    f.title:SetText(L["Chain Guide"])
    f.title:SetTextColor(1.0, 0.82, 0.0)
    local close = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    close:SetPoint("RIGHT", -2, 0)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Nav bar (Back / Forward / Home)
    local nav = CreateFrame("Frame", nil, f)
    nav:SetHeight(NAV_BAR_H)
    nav:SetPoint("TOPLEFT", 0, -TITLE_BAR_H)
    nav:SetPoint("TOPRIGHT", 0, -TITLE_BAR_H)
    local nbg = nav:CreateTexture(nil, "BACKGROUND")
    nbg:SetAllPoints()
    nbg:SetColorTexture(0, 0, 0, 0.4)

    local Options = ns:GetSubsystem("Options")
    local function navBtn(label, onClick)
        local b = Options:CreateYellowButton(nav, label, onClick)
        b:SetSize(70, 22)
        return b
    end
    -- Collapse the nav rail so the graph fills the whole window. ASCII glyphs
    -- ("<<"/">>") so they render in every locale font — Friz Quadrata tofus
    -- many Unicode arrows (see the v1.8.1 arrow-glyph fix).
    f.collapseBtn = navBtn("<<", function() self:SetRailCollapsed(not self._railCollapsed) end)
    f.collapseBtn:SetSize(30, 22)
    Options:AttachTooltip(f.collapseBtn, L["Hide the navigation panel"],
        L["Collapse the category and chain list so the graph fills the whole window. Click again to bring it back."])

    f.backBtn = navBtn(L["Back"],    function() self:Back()    end)
    f.fwdBtn  = navBtn(L["Forward"], function() self:Forward() end)
    f.homeBtn = navBtn(L["Home"],    function() self:NavigateHome() end)
    f.collapseBtn:SetPoint("LEFT", 8, 0)
    f.backBtn:SetPoint("LEFT", f.collapseBtn, "RIGHT", 6, 0)
    f.fwdBtn:SetPoint("LEFT", f.backBtn, "RIGHT", 4, 0)
    f.homeBtn:SetPoint("LEFT", f.fwdBtn, "RIGHT", 4, 0)

    -- Right-aligned shortcut back to the Chain Guide options (the guide is a
    -- standalone reference panel with no menu bar, so this is the only in-window
    -- way back to settings without re-typing /eqs).
    f.optionsBtn = navBtn(L["Options"], function()
        Options:Show()
        Options:SelectTab("chainGuide")
    end)
    f.optionsBtn:SetPoint("RIGHT", -8, 0)

    -- Quest search. Accepts EITHER a quest ID or a (partial) quest NAME and
    -- jumps to the chain that contains it. Quest IDs are universal across
    -- locales — a player reading an English Wowhead guide can punch the ID in
    -- regardless of client language (requested by Sparta | Phrenic) — while
    -- name search is the natural path for players who know the title.
    local searchLabel = nav:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    searchLabel:SetText(L["Find quest"])
    searchLabel:SetTextColor(0.92, 0.72, 0.02)
    searchLabel:SetPoint("LEFT", f.homeBtn, "RIGHT", 20, 0)

    local search = CreateFrame("EditBox", nil, nav, "InputBoxTemplate")
    search:SetSize(150, 18)               -- wide enough for quest titles
    search:SetPoint("LEFT", searchLabel, "RIGHT", 10, 0)
    search:SetAutoFocus(false)
    search:SetMaxLetters(64)              -- fits the longest quest titles
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.searchBox = search
    Options:AttachTooltip(search, L["Find quest"],
        L["Type a quest name or its ID to jump to the chain that contains it."])

    -- Route input: a pure-integer string → ID search; anything else → name
    -- search. Defined once (Build runs a single time), so this is not a
    -- per-render closure; the Enter key and the Go button share it.
    local function runSearch()
        local text = search:GetText()
        text = text and text:match("^%s*(.-)%s*$")     -- trim surrounding space
        search:ClearFocus()
        if not text or text == "" then return end
        search:SetText("")
        if text:match("^%d+$") then
            CG:SearchByQuestID(tonumber(text))
        else
            CG:SearchByName(text)
        end
    end
    search:SetScript("OnEnterPressed", runSearch)

    local goBtn = navBtn(L["Go"], runSearch)
    goBtn:SetSize(40, 22)
    goBtn:SetPoint("LEFT", search, "RIGHT", 8, 0)

    -- Two panes below the nav bar: a single navigation RAIL (categories OR the
    -- selected category's chains — drill-down) and the graph detail pane. The
    -- old layout spent a SECOND list column here; folding both lists into one
    -- rail hands that width to the graph, which is what actually needs it.
    local function makePane()
        local p = CreateFrame("Frame", nil, f, "BackdropTemplate")
        local pbg = p:CreateTexture(nil, "BACKGROUND")
        pbg:SetAllPoints()
        pbg:SetColorTexture(0, 0, 0, 0.4)
        return p
    end
    f.railPane   = makePane()
    f.detailPane = makePane()

    f.railPane:SetPoint("TOPLEFT",    PANE_GAP, PANES_TOP)
    f.railPane:SetPoint("BOTTOMLEFT", PANE_GAP, PANE_GAP)
    f.railPane:SetWidth(RAIL_W)

    -- detailPane is re-anchored by SetRailCollapsed (to railPane's right edge
    -- when expanded, to the window's left edge when the rail is collapsed), so
    -- only its BOTTOMRIGHT is pinned here.
    f.detailPane:SetPoint("BOTTOMRIGHT", -PANE_GAP, PANE_GAP)

    -- Section headers (red, matching Options style — the Chain Guide is a
    -- reference panel, so the brand palette is appropriate here.)
    local function header(parent, text)
        local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        h:SetPoint("TOPLEFT", 8, -6)
        h:SetTextColor(0.635, 0.0, 0.039)   -- #a2000a brand red
        h:SetText(text)
        return h
    end

    -- The rail scrolls (a campaign can carry ~17 chapters). Breadcrumb, header
    -- and rows all live in the scroll child so they share one scrollbar.
    local railScroll = CreateFrame("ScrollFrame", nil, f.railPane, "UIPanelScrollFrameTemplate")
    railScroll:SetPoint("TOPLEFT",     0, 0)
    railScroll:SetPoint("BOTTOMRIGHT", -22, 0)
    local railContent = CreateFrame("Frame", nil, railScroll)
    railContent:SetSize(RAIL_W - 22, 1)
    railScroll:SetScrollChild(railContent)
    f.railScroll  = railScroll
    f.railContent = railContent

    -- "< Categories" breadcrumb: the explicit up-one-level affordance (the
    -- toolbar Back does the same via history). Shown only while the rail is
    -- listing a category's chains; hidden at the categories root.
    local crumb = CreateFrame("Button", nil, railContent)
    crumb:SetHeight(16)
    crumb:SetPoint("TOPLEFT",  8, -6)
    crumb:SetPoint("TOPRIGHT", -8, -6)
    local crumbHL = crumb:CreateTexture(nil, "HIGHLIGHT")
    crumbHL:SetAllPoints()
    crumbHL:SetColorTexture(1, 1, 1, 0.08)
    crumb.text = crumb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    crumb.text:SetPoint("LEFT", 2, 0)
    crumb.text:SetText("< " .. L["Categories"])
    crumb.text:SetTextColor(0.92, 0.72, 0.02)
    crumb:SetScript("OnClick", function() self:NavigateHome() end)
    crumb:Hide()
    f.railCrumb = crumb

    f.railHeader = header(railContent, L["Categories"])

    -- Bottom-right resize grip — the window is resizable so the player can make
    -- the graph as big as they like; the chosen size is saved to the profile.
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(MIN_W, MIN_H) end
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    -- Sits over the detail pane's bottom-right corner; lift it above the graph
    -- canvas/scrollbar so the click always lands on the grip, not the graph.
    grip:SetFrameLevel((f:GetFrameLevel() or 0) + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrip-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrip-Highlight")
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        local DB  = ns:GetSubsystem("DB")
        local cfg = DB and DB.db and DB.db.profile and DB.db.profile.chainGuide
        if cfg then cfg.width, cfg.height = f:GetWidth(), f:GetHeight() end
        -- Re-render so the graph's centering math picks up the new viewport.
        self:RenderCurrent()
    end)
    f.resizeGrip = grip

    self.frame = f

    -- Restore the saved window size + rail-collapse state before the first
    -- render so the player's layout survives a relog. SetRailCollapsed sets the
    -- detailPane's TOPLEFT anchor, so it must run before NavigateHome renders.
    do
        local DB  = ns:GetSubsystem("DB")
        local cfg = DB and DB.db and DB.db.profile and DB.db.profile.chainGuide
        local w = (cfg and cfg.width)  or DEFAULT_W
        local h = (cfg and cfg.height) or DEFAULT_H
        f:SetSize(math.max(w, MIN_W), math.max(h, MIN_H))
        self:SetRailCollapsed(cfg and cfg.railCollapsed or false)
    end

    self:NavigateHome()
end

-- ─── Settings hook ─────────────────────────────────────────────────────
-- Applied on Build() and whenever the user changes Options > Chain Guide.
function CG:ApplySettings()
    if not self.frame then return end
    local DB = ns:GetSubsystem("DB")
    local cfg = DB and DB.db and DB.db.profile and DB.db.profile.chainGuide
    if cfg and cfg.scale then self.frame:SetScale(cfg.scale) end
end

function CG:OnEnable()
    -- Open-on-login is honored once when the player logs in. We defer it a
    -- frame so other subsystems finish their own OnEnable first; otherwise
    -- the window pops up before the tracker has even drawn.
    local DB = ns:GetSubsystem("DB")
    local cfg = DB and DB.db and DB.db.profile and DB.db.profile.chainGuide
    if cfg and cfg.showOnLogin then
        C_Timer.After(0.5, function() self:Open() end)
    end
end

-- ─── Navigation ────────────────────────────────────────────────────────
function CG:Toggle()
    self:Build()
    self:ApplySettings()
    if self.frame:IsShown() then self.frame:Hide() else self.frame:Show() end
end

function CG:Open()
    self:Build()
    self:ApplySettings()
    if not self.frame:IsShown() then self.frame:Show() end
end

-- Collapse / expand the navigation rail. Collapsed = the graph fills the whole
-- window; expanded = the rail sits to its left. Re-anchors the detailPane's
-- TOPLEFT, flips the toolbar glyph, persists the choice, and re-renders the
-- graph so its horizontal centering uses the new viewport width.
function CG:SetRailCollapsed(collapsed)
    local f = self.frame
    if not f then return end
    self._railCollapsed = collapsed and true or false

    f.detailPane:ClearAllPoints()
    if self._railCollapsed then
        f.railPane:Hide()
        f.detailPane:SetPoint("TOPLEFT",     f, "TOPLEFT",     PANE_GAP, PANES_TOP)
        f.detailPane:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PANE_GAP, PANE_GAP)
        if f.collapseBtn then f.collapseBtn.text:SetText(">>") end
    else
        f.railPane:Show()
        f.detailPane:SetPoint("TOPLEFT",     f.railPane, "TOPRIGHT", PANE_GAP, 0)
        f.detailPane:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PANE_GAP, PANE_GAP)
        if f.collapseBtn then f.collapseBtn.text:SetText("<<") end
    end

    local DB  = ns:GetSubsystem("DB")
    local cfg = DB and DB.db and DB.db.profile and DB.db.profile.chainGuide
    if cfg then cfg.railCollapsed = self._railCollapsed end

    self:RenderDetail(self._activeChainID, self._activeHighlight)
end

function CG:NavigateHome()
    local H = ns:GetSubsystem("ChainGuideHistory")
    H:Push({ type = "home" })
    self:RenderCurrent()
end

function CG:NavigateCategory(catID)
    local H = ns:GetSubsystem("ChainGuideHistory")
    H:Push({ type = "category", id = catID })
    self:RenderCurrent()
end

function CG:NavigateChain(chainID, highlightQuestID)
    local H = ns:GetSubsystem("ChainGuideHistory")
    H:Push({ type = "chain", id = chainID, highlight = highlightQuestID })
    self:RenderCurrent()
end

-- ─── Quest-ID search ───────────────────────────────────────────────────
-- Walk every known chain's items for a quest matching `questID` (base id or
-- any per-character variation id). Returns the chain id, or nil. Discovery +
-- item population are memoized, so this is cheap on repeat calls.
function CG:FindChainForQuest(questID)
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    local QLS      = ns:GetSubsystem("ChainGuideQuestLineSource")
    if not Database then return nil end

    -- Make sure every category's chains are discovered and their quest lists
    -- populated before we scan (authored chains already carry items; API/
    -- campaign chains get filled in here).
    if QLS then
        for id in pairs(Database.categories) do QLS:EnsureZoneChains(id) end
    end
    for _, chain in pairs(Database.chains) do
        Database:NormalizeChain(chain)
        -- pcall: chains are sourced live from Blizzard's questline/campaign
        -- APIs, so one malformed entry (e.g. a campaign chapter whose ID isn't
        -- actually a questline) must not throw and silently abort the whole
        -- scan — that would kill the search for every quest after it.
        if QLS then pcall(QLS.EnsureChainItems, QLS, chain) end
        local items = chain.items
        if items then
            for i = 1, #items do
                local it = items[i]
                if it and it.type ~= "chain" then
                    if it.id == questID then return chain.id end
                    if it.variations then
                        for v = 1, #it.variations do
                            if it.variations[v].id == questID then return chain.id end
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- How long SearchByQuestID keeps re-scanning while Blizzard streams in the
-- questline data the first scan triggered (see the comment in the function).
local SEARCH_MAX_ATTEMPTS = 6
local SEARCH_RETRY_DELAY  = 0.4

function CG:SearchByQuestID(questID, _attempt)
    _attempt = _attempt or 1

    -- Nudge Blizzard to load the title so the chat confirmation can name it
    -- (it resolves to the player's own locale — German, French, etc.).
    if C_QuestLog and C_QuestLog.RequestLoadQuestByID then
        C_QuestLog.RequestLoadQuestByID(questID)
    end

    local chainID = self:FindChainForQuest(questID)
    if chainID then
        self:NavigateChain(chainID, questID)
        local name = ns.Util.QuestTitle(questID)
        print((L["|cffEBB706EQ Chain Guide:|r found quest |cffffffff%d|r%s — jumping to its chain."])
            :format(questID, name and (" (" .. name .. ")") or ""))
        return
    end

    -- Not found yet. Every chain is sourced live: the scan above is also the
    -- FIRST request for each chain's quest list, and C_QuestLine.GetQuestLineQuests
    -- returns empty on first touch, filling in a few hundred ms later. So on a
    -- cold search most chains are still empty and the quest legitimately can't
    -- be found on pass 1. Retry a few times to let that data arrive before
    -- declaring it unrouted — this is what lets the majority of quests resolve
    -- instead of silently doing nothing.
    if _attempt < SEARCH_MAX_ATTEMPTS then
        C_Timer.After(SEARCH_RETRY_DELAY, function()
            -- Stop retrying (and re-scanning / re-requesting quest data) once the
            -- guide is closed — frame is only hidden, never nil'd, so check shown.
            if self.frame and self.frame:IsShown() then self:SearchByQuestID(questID, _attempt + 1) end
        end)
        return
    end

    local name = ns.Util.QuestTitle(questID)
    print((L["|cffEBB706EQ Chain Guide:|r quest |cffffffff%d|r%s isn't in any chain I know about."])
        :format(questID, name and (" (" .. name .. ")") or ""))
    print(("  Wowhead: https://www.wowhead.com/quest=%d"):format(questID))
end

-- ─── Name search ───────────────────────────────────────────────────────
-- Walk every known chain's quests and return the first chain whose quest title
-- CONTAINS `needle` (case-insensitive substring), plus the matching quest id so
-- the detail view can ring it. Returns nil when nothing matches. Shares the
-- memoized discovery FindChainForQuest uses, so repeat calls are cheap. A title
-- only resolves for a quest the client has cached; for any uncached title we
-- fire RequestLoadQuestByID so the SearchByName retry loop can match it once the
-- data streams in — the same async pattern the ID search relies on for the
-- quest LIST. (Deliberately a sibling of FindChainForQuest rather than a shared
-- core, to avoid touching the just-shipped Quest-ID search path.)
function CG:FindChainByName(needle)
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    local QLS      = ns:GetSubsystem("ChainGuideQuestLineSource")
    if not (Database and needle and needle ~= "") then return nil end
    needle = needle:lower()

    if QLS then
        for id in pairs(Database.categories) do QLS:EnsureZoneChains(id) end
    end

    -- Pass 1: match the chain (questline) NAME itself. These are exactly the
    -- names shown in the middle list, they're always loaded (no async, no
    -- per-quest cache dependency), and a player typing "nightbreaker" means the
    -- chain "The Nightbreaker". This is why a chain whose quests aren't cached
    -- yet (0/N done) is still findable — the earlier quest-title-only scan
    -- couldn't see it. Returns the chain with no specific quest to ring.
    for _, chain in pairs(Database.chains) do
        if chain.name and chain.name:lower():find(needle, 1, true) then
            return chain.id
        end
    end

    -- Pass 2: match a quest TITLE within a chain (async/best-effort — titles
    -- only resolve once cached; for misses we prime RequestLoadQuestByID so a
    -- retry can match). This scan touches every quest; localize the hot globals.
    local QuestTitle = ns.Util.QuestTitle
    local reqLoad    = C_QuestLog and C_QuestLog.RequestLoadQuestByID

    for _, chain in pairs(Database.chains) do
        Database:NormalizeChain(chain)
        if QLS then pcall(QLS.EnsureChainItems, QLS, chain) end
        local items = chain.items
        if items then
            for i = 1, #items do
                local it = items[i]
                if it and it.type ~= "chain" then
                    local title = it.id and QuestTitle(it.id)
                    if title then
                        if title:lower():find(needle, 1, true) then return chain.id, it.id end
                    elseif reqLoad and it.id then
                        reqLoad(it.id)               -- uncached: prime for a retry
                    end
                    if it.variations then
                        for v = 1, #it.variations do
                            local vid = it.variations[v].id
                            local vt  = vid and QuestTitle(vid)
                            if vt then
                                if vt:lower():find(needle, 1, true) then return chain.id, vid end
                            elseif reqLoad and vid then
                                reqLoad(vid)
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

function CG:SearchByName(text, _attempt)
    _attempt = _attempt or 1
    local chainID, questID = self:FindChainByName(text)
    if chainID then
        self:NavigateChain(chainID, questID)
        -- Label: the matched quest's title, else the matched chain's name
        -- (chain-name match has no questID), else the raw text typed.
        local Database = ns:GetSubsystem("ChainGuideDatabase")
        local label = (questID and ns.Util.QuestTitle(questID))
                      or (Database and Database.chains[chainID] and Database.chains[chainID].name)
                      or text
        print((L["|cffEBB706EQ Chain Guide:|r found |cffffffff%s|r — jumping to its chain."])
            :format(label))
        return
    end

    -- Titles (and the quest LIST itself) stream in asynchronously, so a cold
    -- search can legitimately miss on the first pass. Retry a few times to let
    -- the data arrive before giving up — mirrors SearchByQuestID.
    if _attempt < SEARCH_MAX_ATTEMPTS then
        C_Timer.After(SEARCH_RETRY_DELAY, function()
            -- Same shown-check as SearchByQuestID: don't keep scanning/requesting
            -- quest data after the user has closed the guide mid-search.
            if self.frame and self.frame:IsShown() then self:SearchByName(text, _attempt + 1) end
        end)
        return
    end

    print((L["|cffEBB706EQ Chain Guide:|r no chain quest matches |cffffffff%s|r."])
        :format(text))
end

function CG:Back()    local H = ns:GetSubsystem("ChainGuideHistory"); H:Back();    self:RenderCurrent() end
function CG:Forward() local H = ns:GetSubsystem("ChainGuideHistory"); H:Forward(); self:RenderCurrent() end

-- ─── Rendering ─────────────────────────────────────────────────────────
function CG:RenderCurrent()
    if not self.frame then return end
    local H = ns:GetSubsystem("ChainGuideHistory")
    local state = H:Current() or { type = "home" }

    self.frame.backBtn:SetEnabled(H:CanBack())
    self.frame.fwdBtn:SetEnabled(H:CanForward())

    local activeCatID, activeChainID
    if state.type == "category" then
        activeCatID = state.id
    elseif state.type == "chain" then
        local Database = ns:GetSubsystem("ChainGuideDatabase")
        local chain = Database.chains[state.id]
        activeCatID   = chain and chain.category
        activeChainID = state.id
    end

    -- Remembered so SetRailCollapsed / the resize grip can re-render the graph
    -- for the current chain without re-reading the history stack.
    self._activeChainID   = activeChainID
    self._activeHighlight = state.highlight

    -- Drill-down: the rail shows the categories at the root, otherwise the
    -- selected category's chains. Exactly one list renders at a time.
    if activeCatID then
        self:RenderChains(activeCatID, activeChainID)
    else
        self:RenderCategories()
    end
    self:RenderDetail(activeChainID, state.highlight)
end

-- Root of the drill-down: list the categories in the rail. No breadcrumb here
-- (this IS the top level); the header reads "Categories".
function CG:RenderCategories()
    releaseAllRows(self.railRowPool, self.railRowsActive)
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    local QLS      = ns:GetSubsystem("ChainGuideQuestLineSource")

    local content = self.frame.railContent
    self.frame.railCrumb:Hide()
    local hdr = self.frame.railHeader
    hdr:ClearAllPoints()
    hdr:SetPoint("TOPLEFT", 8, -6)
    hdr:SetText(L["Categories"])

    -- Discover every category's chains up front (memoized + cheap: zone
    -- cats have no map seeds so it's just the routing walk, campaign cats
    -- delegate to CampaignSource) so we can HIDE any category left with no
    -- chains. Arator's only storylines are campaign chapters, which now
    -- live solely under the campaign — without this its row would render
    -- as a dead, empty shell.
    if QLS then
        for id in pairs(Database.categories) do QLS:EnsureZoneChains(id) end
    end
    local hasChains = {}
    for _, c in pairs(Database.chains) do hasChains[c.category] = true end

    local prev = hdr
    -- Categories are registered exclusively at file load (Data/QuestChains/
    -- _Index.lua), so the sorted list never changes at runtime. Build it
    -- once and reuse on every subsequent render to avoid the per-render
    -- pairs() walk + table.sort + N {id, def} table allocations.
    if not self._sortedCategories then
        local cats = {}
        for id, c in pairs(Database.categories) do
            cats[#cats + 1] = { id = id, def = c }
        end
        -- Explicit `order` (Data/QuestChains/_Index.lua) first — campaigns
        -- then zones in progression order — falling back to name for any
        -- category that didn't set one.
        table.sort(cats, function(a, b)
            local ao = a.def.order or math.huge
            local bo = b.def.order or math.huge
            if ao ~= bo then return ao < bo end
            return (a.def.name or "") < (b.def.name or "")
        end)
        self._sortedCategories = cats
    end
    local cats = self._sortedCategories

    local shown = 0
    for i = 1, #cats do
        local entry = cats[i]
        -- Skip categories with no chains (see hasChains note above).
        if hasChains[entry.id] then
            local row = acquireRow(self.railRowPool, self.railRowsActive, content)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  prev, "BOTTOMLEFT",  0, prev == hdr and -4 or -1)
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", -8, 0)
            -- Category rows have no suffix/complete-icon, so reclaim the
            -- right-side reservation buildListRow leaves for chain rows and
            -- give the (sometimes long) category name the full width.
            row.title:ClearAllPoints()
            row.title:SetPoint("LEFT", 8, 0)
            row.title:SetPoint("RIGHT", -8, 0)
            local catName = entry.def.name or ("Category " .. entry.id)
            row.title:SetText(catName)
            row.title:SetTextColor(1, 1, 1)
            row.navKind, row.navID = "cat", entry.id
            setRowTooltip(row, catName)
            prev = row
            shown = shown + 1
        end
    end

    -- Size the scroll child so the scrollbar reflects content height.
    local stride = ROW_H + 1
    content:SetHeight(22 + 4 + math.max(shown, 1) * stride + 8)
end

-- Second level of the drill-down: list the chains in `activeCatID`. The
-- "< Categories" breadcrumb is shown so the player can step back up, and the
-- header reads the category name.
function CG:RenderChains(activeCatID, activeChainID)
    releaseAllRows(self.railRowPool, self.railRowsActive)
    local Database  = ns:GetSubsystem("ChainGuideDatabase")
    local Characters = ns:GetSubsystem("ChainGuideCharacters")
    local QLS = ns:GetSubsystem("ChainGuideQuestLineSource")

    local content = self.frame.railContent
    local crumb = self.frame.railCrumb
    crumb:Show()
    local hdr = self.frame.railHeader
    hdr:ClearAllPoints()
    hdr:SetPoint("TOPLEFT", crumb, "BOTTOMLEFT", 0, -6)

    if not activeCatID then
        hdr:SetText(L["Pick a category"])
        content:SetHeight(60)
        return
    end

    -- Seed any API-discoverable chains for this zone before we build the
    -- list. Cached after first success, so this is a no-op on re-render.
    if QLS then QLS:EnsureZoneChains(activeCatID) end

    local catName = Database.categories[activeCatID] and Database.categories[activeCatID].name
    hdr:SetText(catName or L["Chains"])

    -- Collect chains in this category, sort by name.
    local chains = {}
    for id, c in pairs(Database.chains) do
        if c.category == activeCatID then chains[#chains + 1] = { id = id, def = c } end
    end
    -- Campaign chapters carry `_campaignOrder` (story order from
    -- C_CampaignInfo) and must render Chapter 1→N, not alphabetically.
    -- All other categories sort by name as before.
    table.sort(chains, function(a, b)
        local ao, bo = a.def._campaignOrder, b.def._campaignOrder
        if ao and bo then return ao < bo end
        if ao or bo then return ao ~= nil end
        return (a.def.name or "") < (b.def.name or "")
    end)

    -- Eagerly populate items[] for every chain in this category so the
    -- per-row "X/Y" suffix shows up before the user clicks anything.
    -- Items population is itself cached and idempotent, so the second time
    -- we render this category it's a no-op.
    if QLS then
        for i = 1, #chains do
            QLS:EnsureChainItems(chains[i].def)
        end
    end

    local prev = hdr
    for i = 1, #chains do
        local entry = chains[i]
        local row = acquireRow(self.railRowPool, self.railRowsActive, content)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  prev, "BOTTOMLEFT",  0, prev == hdr and -4 or -1)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", -8, 0)
        local chainName = entry.def.name or ("Chain " .. entry.id)
        row.title:SetText(chainName)
        row.title:SetTextColor(1, 1, 1)
        local complete, _, total = Characters:ChainProgress(entry.def)
        if total > 0 then
            row.suffix:SetText(("%d/%d"):format(complete, total))
            -- Strict completion: green check only when every quest in the
            -- questline is flagged complete. Branching questlines (where a
            -- character can never literally do every quest) stay yellow at
            -- their max-possible ratio. A future enhancement can add a
            -- per-chain "completion signal quest" override for those.
            if complete >= total then
                row.suffix:SetTextColor(0.30, 0.85, 0.30)
                row.title:SetTextColor(0.65, 0.65, 0.65)
                setCheckAtlas(row.completeIcon)
                row.completeIcon:Show()
            end
        end
        if entry.id == activeChainID then row.selectedTex:Show() end
        row.navKind, row.navID = "chain", entry.id
        setRowTooltip(row, chainName,
            total > 0 and (L["%d / %d quests done"]):format(complete, total) or nil)
        prev = row
    end

    -- Size the scroll child so the scrollbar reflects content height.
    -- Breadcrumb band (~28) + header (~22) + leading gap (4) + per-row stride.
    local stride = ROW_H + 1
    local totalH = 28 + 22 + 4 + math.max(#chains, 1) * stride + 8
    content:SetHeight(totalH)
end

function CG:RenderDetail(activeChainID, highlightQuestID)
    local CV = ns:GetSubsystem("ChainGuideView")
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    local chain = activeChainID and Database.chains[activeChainID]
    CV:Render(self.frame.detailPane, chain, highlightQuestID)
end
