local _, ns = ...
local L = ns.L

local CG = ns:RegisterSubsystem("ChainGuide", {})

local PANE_GAP        = 6
local TITLE_BAR_H     = 22
local NAV_BAR_H       = 28
local RAIL_W          = 250
local ROW_H           = 22
local MIN_W           = 760
local MIN_H           = 460
local DEFAULT_W       = 1160
local DEFAULT_H       = 720
local PANES_TOP       = -(TITLE_BAR_H + NAV_BAR_H + PANE_GAP)

CG.railRowPool = {}; CG.railRowsActive = {}

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

    r.completeIcon = r:CreateTexture(nil, "OVERLAY")
    r.completeIcon:SetSize(12, 12)
    r.completeIcon:SetPoint("RIGHT", r.suffix, "LEFT", -4, 0)
    r.completeIcon:Hide()

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

local function setCheckAtlas(tex)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("common-icon-checkmark") then
        tex:SetAtlas("common-icon-checkmark", false)
    else
        tex:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        tex:SetTexCoord(0, 1, 0, 1)
    end
end

local function setRowTooltip(row, title, sub)
    row._ttTitle = title
    row._ttSub   = sub
end

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

    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(unpack(ns.Util.color.optionsBg))
    f:SetBackdropBorderColor(0.635, 0.000, 0.039, 1.0)

    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetHeight(TITLE_BAR_H)
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

    f.optionsBtn = navBtn(L["Options"], function()
        Options:Show()
        Options:SelectTab("chainGuide")
    end)
    f.optionsBtn:SetPoint("RIGHT", -8, 0)

    local searchLabel = nav:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    searchLabel:SetText(L["Find quest"])
    searchLabel:SetTextColor(0.92, 0.72, 0.02)
    searchLabel:SetPoint("LEFT", f.homeBtn, "RIGHT", 20, 0)

    local search = CreateFrame("EditBox", nil, nav, "InputBoxTemplate")
    search:SetSize(150, 18)
    search:SetPoint("LEFT", searchLabel, "RIGHT", 10, 0)
    search:SetAutoFocus(false)
    search:SetMaxLetters(64)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.searchBox = search
    Options:AttachTooltip(search, L["Find quest"],
        L["Type a quest name or its ID to jump to the chain that contains it."])

    local function runSearch()
        local text = search:GetText()
        text = text and text:match("^%s*(.-)%s*$")
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

    f.detailPane:SetPoint("BOTTOMRIGHT", -PANE_GAP, PANE_GAP)

    local function header(parent, text)
        local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        h:SetPoint("TOPLEFT", 8, -6)
        h:SetTextColor(0.635, 0.0, 0.039)
        h:SetText(text)
        return h
    end

    local railScroll = CreateFrame("ScrollFrame", nil, f.railPane, "UIPanelScrollFrameTemplate")
    railScroll:SetPoint("TOPLEFT",     0, 0)
    railScroll:SetPoint("BOTTOMRIGHT", -22, 0)
    local railContent = CreateFrame("Frame", nil, railScroll)
    railContent:SetSize(RAIL_W - 22, 1)
    railScroll:SetScrollChild(railContent)
    f.railScroll  = railScroll
    f.railContent = railContent

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

    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(MIN_W, MIN_H) end
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(20, 20)
    grip:SetPoint("BOTTOMRIGHT", -5, 5)
    grip:SetFrameLevel((f:GetFrameLevel() or 0) + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrip-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrip-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrip-Down")
    grip:SetHitRectInsets(-14, 0, -14, 0)
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        local DB  = ns:GetSubsystem("DB")
        local cfg = DB and DB.db and DB.db.profile and DB.db.profile.chainGuide
        if cfg then cfg.width, cfg.height = f:GetWidth(), f:GetHeight() end
        self:RenderCurrent()
    end)
    grip:SetScript("OnEnter", function(self2)
        GameTooltip:SetOwner(self2, "ANCHOR_LEFT")
        GameTooltip:AddLine(L["Drag to resize"])
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.resizeGrip = grip

    self.frame = f

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

function CG:ApplySettings()
    if not self.frame then return end
    local DB = ns:GetSubsystem("DB")
    local cfg = DB and DB.db and DB.db.profile and DB.db.profile.chainGuide
    if cfg and cfg.scale then self.frame:SetScale(cfg.scale) end
end

function CG:OnEnable()
    local DB = ns:GetSubsystem("DB")
    local cfg = DB and DB.db and DB.db.profile and DB.db.profile.chainGuide
    if cfg and cfg.showOnLogin then
        C_Timer.After(0.5, function() self:Open() end)
    end
end

local function hideOptions()
    local O = ns:GetSubsystem("Options")
    if O and O.frame and O.frame:IsShown() then O.frame:Hide() end
end

function CG:Toggle()
    self:Build()
    self:ApplySettings()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        hideOptions()
        self.frame:Show()
    end
end

function CG:Open()
    self:Build()
    self:ApplySettings()
    if not self.frame:IsShown() then
        hideOptions()
        self.frame:Show()
    end
end

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

function CG:FindChainForQuest(questID)
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    local QLS      = ns:GetSubsystem("ChainGuideQuestLineSource")
    if not Database then return nil end

    if QLS then
        for id in pairs(Database.categories) do QLS:EnsureZoneChains(id) end
    end
    for _, chain in pairs(Database.chains) do
        Database:NormalizeChain(chain)
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

local SEARCH_MAX_ATTEMPTS = 6
local SEARCH_RETRY_DELAY  = 0.4

function CG:SearchByQuestID(questID, _attempt)
    _attempt = _attempt or 1

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

    if _attempt < SEARCH_MAX_ATTEMPTS then
        C_Timer.After(SEARCH_RETRY_DELAY, function()
            if self.frame and self.frame:IsShown() then self:SearchByQuestID(questID, _attempt + 1) end
        end)
        return
    end

    local name = ns.Util.QuestTitle(questID)
    print((L["|cffEBB706EQ Chain Guide:|r quest |cffffffff%d|r%s isn't in any chain I know about."])
        :format(questID, name and (" (" .. name .. ")") or ""))
    print(("  Wowhead: https://www.wowhead.com/quest=%d"):format(questID))
end

function CG:FindChainByName(needle)
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    local QLS      = ns:GetSubsystem("ChainGuideQuestLineSource")
    if not (Database and needle and needle ~= "") then return nil end
    needle = needle:lower()

    if QLS then
        for id in pairs(Database.categories) do QLS:EnsureZoneChains(id) end
    end

    for _, chain in pairs(Database.chains) do
        if chain.name and chain.name:lower():find(needle, 1, true) then
            return chain.id
        end
    end

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
                        reqLoad(it.id)
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
        local Database = ns:GetSubsystem("ChainGuideDatabase")
        local label = (questID and ns.Util.QuestTitle(questID))
                      or (Database and Database.chains[chainID] and Database.chains[chainID].name)
                      or text
        print((L["|cffEBB706EQ Chain Guide:|r found |cffffffff%s|r — jumping to its chain."])
            :format(label))
        return
    end

    if _attempt < SEARCH_MAX_ATTEMPTS then
        C_Timer.After(SEARCH_RETRY_DELAY, function()
            if self.frame and self.frame:IsShown() then self:SearchByName(text, _attempt + 1) end
        end)
        return
    end

    print((L["|cffEBB706EQ Chain Guide:|r no chain quest matches |cffffffff%s|r."])
        :format(text))
end

function CG:Back()    local H = ns:GetSubsystem("ChainGuideHistory"); H:Back();    self:RenderCurrent() end
function CG:Forward() local H = ns:GetSubsystem("ChainGuideHistory"); H:Forward(); self:RenderCurrent() end

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

    self._activeChainID   = activeChainID
    self._activeHighlight = state.highlight

    if activeCatID then
        self:RenderChains(activeCatID, activeChainID)
    else
        self:RenderCategories()
    end
    self:RenderDetail(activeChainID, state.highlight)
end

function CG:GetTrackedChainID()
    local DB = ns:GetSubsystem("DB")
    return DB and DB.char and DB.char.trackedChainID
end

function CG:GetTrackedChain()
    local id = self:GetTrackedChainID()
    if not id then return nil end
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    if not Database then return nil end
    if not Database.chains[id] then
        local QLS = ns:GetSubsystem("ChainGuideQuestLineSource")
        if QLS and QLS.EnsureZoneChains and Database.categories then
            for catID in pairs(Database.categories) do QLS:EnsureZoneChains(catID) end
        end
    end
    return Database.chains[id] or nil, id
end

function CG:IsTrackingChain(chainID)
    return chainID ~= nil and self:GetTrackedChainID() == chainID
end

function CG:SetTrackedChainID(chainID)
    local DB = ns:GetSubsystem("DB")
    if not (DB and DB.char) then return end
    if DB.char.trackedChainID == chainID then return end
    DB.char.trackedChainID = chainID
    self:OnTrackedChainChanged()
end

function CG:ClearTrackedChainID()
    self:SetTrackedChainID(nil)
end

function CG:OnTrackedChainChanged()
    local MP = ns:GetSubsystem("ChainGuideMapPins")
    if MP and MP.Refresh then MP:Refresh() end
    if self.frame and self.frame:IsShown() then self:RenderCurrent() end
end

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

    if QLS then
        for id in pairs(Database.categories) do QLS:EnsureZoneChains(id) end
    end
    local hasChains = {}
    for _, c in pairs(Database.chains) do hasChains[c.category] = true end

    local prev = hdr
    if not self._sortedCategories then
        local cats = {}
        for id, c in pairs(Database.categories) do
            cats[#cats + 1] = { id = id, def = c }
        end
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
        if hasChains[entry.id] then
            local row = acquireRow(self.railRowPool, self.railRowsActive, content)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  prev, "BOTTOMLEFT",  0, prev == hdr and -4 or -1)
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", -8, 0)
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

    local stride = ROW_H + 1
    content:SetHeight(22 + 4 + math.max(shown, 1) * stride + 8)
end

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

    if QLS then QLS:EnsureZoneChains(activeCatID) end

    local catName = Database.categories[activeCatID] and Database.categories[activeCatID].name
    hdr:SetText(catName or L["Chains"])

    local chains = {}
    for id, c in pairs(Database.chains) do
        if c.category == activeCatID then chains[#chains + 1] = { id = id, def = c } end
    end
    table.sort(chains, function(a, b)
        local ao, bo = a.def._campaignOrder, b.def._campaignOrder
        if ao and bo then return ao < bo end
        if ao or bo then return ao ~= nil end
        return (a.def.name or "") < (b.def.name or "")
    end)

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
        row.title:ClearAllPoints()
        row.title:SetPoint("LEFT", 8, 0)
        row.title:SetPoint("RIGHT", -50, 0)
        local chainName = entry.def.name or ("Chain " .. entry.id)
        row.title:SetText(chainName)
        row.title:SetTextColor(1, 1, 1)
        local complete, _, total = Characters:ChainProgress(entry.def)
        if total > 0 then
            row.suffix:SetText(("%d/%d"):format(complete, total))
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
