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

local CG = ns:RegisterSubsystem("ChainGuide", {})

local PANE_GAP        = 6
local TITLE_BAR_H     = 22
local NAV_BAR_H       = 28
local CAT_PANE_W      = 250
local CHAIN_PANE_W    = 300
local ROW_H           = 22

CG.catRowPool   = {}; CG.catRowsActive   = {}
CG.chainRowPool = {}; CG.chainRowsActive = {}

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
        r:SetScript("OnClick", nil)
        r:SetScript("OnEnter", nil)
        r:SetScript("OnLeave", nil)
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
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 0.82, 0, 1, true)
        if sub and sub ~= "" then GameTooltip:AddLine(sub, 0.7, 0.7, 0.7) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
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

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.92)

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetHeight(TITLE_BAR_H)
    titleBar:SetPoint("TOPLEFT")
    titleBar:SetPoint("TOPRIGHT")
    local tbg = titleBar:CreateTexture(nil, "ARTWORK")
    tbg:SetAllPoints()
    tbg:SetColorTexture(0, 0, 0, 0.85)
    f.title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("LEFT", 12, 0)
    f.title:SetText("Chain Guide")
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
    f.backBtn = navBtn("Back",    function() self:Back()    end)
    f.fwdBtn  = navBtn("Forward", function() self:Forward() end)
    f.homeBtn = navBtn("Home",    function() self:NavigateHome() end)
    f.backBtn:SetPoint("LEFT", 8, 0)
    f.fwdBtn:SetPoint("LEFT", f.backBtn, "RIGHT", 4, 0)
    f.homeBtn:SetPoint("LEFT", f.fwdBtn, "RIGHT", 4, 0)

    -- Three panes below the nav bar.
    local function makePane()
        local p = CreateFrame("Frame", nil, f, "BackdropTemplate")
        local pbg = p:CreateTexture(nil, "BACKGROUND")
        pbg:SetAllPoints()
        pbg:SetColorTexture(0, 0, 0, 0.4)
        return p
    end
    f.catPane    = makePane()
    f.chainPane  = makePane()
    f.detailPane = makePane()

    local panesTop = -(TITLE_BAR_H + NAV_BAR_H + PANE_GAP)
    f.catPane:SetPoint("TOPLEFT",     PANE_GAP, panesTop)
    f.catPane:SetPoint("BOTTOMLEFT",  PANE_GAP, PANE_GAP)
    f.catPane:SetWidth(CAT_PANE_W)

    f.chainPane:SetPoint("TOPLEFT",    f.catPane, "TOPRIGHT", PANE_GAP, 0)
    f.chainPane:SetPoint("BOTTOMLEFT", f.catPane, "BOTTOMRIGHT", PANE_GAP, 0)
    f.chainPane:SetWidth(CHAIN_PANE_W)

    f.detailPane:SetPoint("TOPLEFT",     f.chainPane, "TOPRIGHT", PANE_GAP, 0)
    f.detailPane:SetPoint("BOTTOMRIGHT", -PANE_GAP, PANE_GAP)

    -- Section headers (red, matching Options style — these are "in-window UI"
    -- but the Chain Guide is a reference panel, not gameplay UI, so the brand
    -- palette is appropriate here.)
    local function header(parent, text)
        local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        h:SetPoint("TOPLEFT", 8, -6)
        h:SetTextColor(0.43, 0.02, 0.0)
        h:SetText(text)
        return h
    end
    f.catHeader   = header(f.catPane, "Categories")

    -- Chain pane gets an inner scroll so long chain lists don't get clipped.
    -- The scroll child grows to fit all rows; a UIPanelScrollFrame scrollbar
    -- appears automatically when the content exceeds the visible height.
    local chainScroll = CreateFrame("ScrollFrame", nil, f.chainPane, "UIPanelScrollFrameTemplate")
    chainScroll:SetPoint("TOPLEFT",     0, 0)
    chainScroll:SetPoint("BOTTOMRIGHT", -22, 0)
    local chainContent = CreateFrame("Frame", nil, chainScroll)
    chainContent:SetSize(CHAIN_PANE_W - 22, 1)
    chainScroll:SetScrollChild(chainContent)
    f.chainScroll  = chainScroll
    f.chainContent = chainContent
    f.chainHeader  = header(chainContent, "Chains")

    self.frame = f
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

function CG:NavigateChain(chainID)
    local H = ns:GetSubsystem("ChainGuideHistory")
    H:Push({ type = "chain", id = chainID })
    self:RenderCurrent()
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

    self:RenderCategories(activeCatID)
    self:RenderChains(activeCatID, activeChainID)
    self:RenderDetail(activeChainID)
end

function CG:RenderCategories(activeCatID)
    releaseAllRows(self.catRowPool, self.catRowsActive)
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    local QLS      = ns:GetSubsystem("ChainGuideQuestLineSource")

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

    local prev = self.frame.catHeader
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

    for i = 1, #cats do
        local entry = cats[i]
        -- Skip categories with no chains (see hasChains note above).
        if hasChains[entry.id] then
            local row = acquireRow(self.catRowPool, self.catRowsActive, self.frame.catPane)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  prev, "BOTTOMLEFT",  0, prev == self.frame.catHeader and -4 or -1)
            row:SetPoint("TOPRIGHT", self.frame.catPane, "TOPRIGHT", -8, 0)
            -- Category rows have no suffix/complete-icon, so reclaim the
            -- right-side reservation buildListRow leaves for chain rows and
            -- give the (sometimes long) category name the full width.
            row.title:ClearAllPoints()
            row.title:SetPoint("LEFT", 8, 0)
            row.title:SetPoint("RIGHT", -8, 0)
            local catName = entry.def.name or ("Category " .. entry.id)
            row.title:SetText(catName)
            row.title:SetTextColor(1, 1, 1)
            if entry.id == activeCatID then row.selectedTex:Show() end
            local catID = entry.id
            row:SetScript("OnClick", function() CG:NavigateCategory(catID) end)
            setRowTooltip(row, catName)
            prev = row
        end
    end
end

function CG:RenderChains(activeCatID, activeChainID)
    releaseAllRows(self.chainRowPool, self.chainRowsActive)
    local Database  = ns:GetSubsystem("ChainGuideDatabase")
    local Characters = ns:GetSubsystem("ChainGuideCharacters")
    local QLS = ns:GetSubsystem("ChainGuideQuestLineSource")

    if not activeCatID then
        self.frame.chainHeader:SetText("Pick a category")
        return
    end

    -- Seed any API-discoverable chains for this zone before we build the
    -- list. Cached after first success, so this is a no-op on re-render.
    if QLS then QLS:EnsureZoneChains(activeCatID) end

    local catName = Database.categories[activeCatID] and Database.categories[activeCatID].name
    self.frame.chainHeader:SetText(catName and (catName) or "Chains")

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

    local content = self.frame.chainContent
    local prev = self.frame.chainHeader
    for i = 1, #chains do
        local entry = chains[i]
        local row = acquireRow(self.chainRowPool, self.chainRowsActive, content)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  prev, "BOTTOMLEFT",  0, prev == self.frame.chainHeader and -4 or -1)
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
        local chainID = entry.id
        row:SetScript("OnClick", function() CG:NavigateChain(chainID) end)
        setRowTooltip(row, chainName,
            total > 0 and ("%d / %d quests done"):format(complete, total) or nil)
        prev = row
    end

    -- Size the scroll child so the scrollbar reflects content height.
    -- Header (~22) + leading gap (4) + per-row stride.
    local stride = ROW_H + 1
    local totalH = 22 + 4 + math.max(#chains, 1) * stride + 8
    content:SetHeight(totalH)
end

function CG:RenderDetail(activeChainID)
    local CV = ns:GetSubsystem("ChainGuideView")
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    local chain = activeChainID and Database.chains[activeChainID]
    CV:Render(self.frame.detailPane, chain)
end
