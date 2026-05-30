-- Modules/History/Frame.lua
-- Standalone Quest History window. Three tabs across the top:
--   1. Quests — searchable, character-filterable list of completed quests
--   2. Streak — daily-streak summary (current / best / total)
--   3. Chain Timeline — chains the player has completed quests in, with
--      per-quest dates from history
--
-- Built lazily on first Toggle()/Open(); subsequent calls just show/hide.
-- Modeled on Modules/ChainGuide/Frame.lua's structure (same row-pool
-- pattern, same brand-yellow accent).

local _, ns = ...

local HF = ns:RegisterSubsystem("HistoryFrame", {})

local TITLE_BAR_H = 22
local TAB_BAR_H   = 28
local TOOLBAR_H   = 30
local ROW_H       = 36                  -- title (~15) + 2px gap + meta (~11) + padding

-- Activity heatmap layout (7 rows × 13 cols = 91 days). Most-recent day
-- lands at the bottom-right; render walks oldest → newest along columns.
local HEATMAP_DAYS = 91
local HEATMAP_ROWS = 7
local HEATMAP_COLS = 13
local CELL_SIZE    = 16
local CELL_GAP     = 3

local YELLOW      = ns.Util.color.buttonYellow   -- #EBB706
local HEADER_RED  = ns.Util.color.brandRed        -- #6D0501 (was drifted to {0.42,0.02,0.02})
local MUTED       = ns.Util.color.muted
local DIM         = ns.Util.color.dim

-- Arial Narrow is a Blizzard-bundled font noticeably thinner than the
-- default Friz Quadrata used by GameFont* objects. We keep each
-- FontString's inherited size + outline flags and just swap the font
-- file, so colors / sizes / shadow flags stay consistent.
local FONT_FILE = "Fonts\\ARIALN.TTF"
local function thin(fs)
    if not (fs and fs.GetFont and fs.SetFont) then return end
    local _, sz, fl = fs:GetFont()
    fs:SetFont(FONT_FILE, sz or 12, fl or "")
end

-- ─── Date formatting ──────────────────────────────────────────────────
-- A backfilled entry has t=0 — Blizzard tells us the player has done the
-- quest but not when, so we surface that honestly rather than guess.
local function fmtTime(t)
    if not t or t == 0 then return "(before tracking)" end
    return date("%Y-%m-%d %H:%M", t)
end

-- ─── Row pool ──────────────────────────────────────────────────────────
HF._rowPool   = {}
HF._rowActive = {}

local function buildRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(ROW_H)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)

    -- Title pinned to the top half of the row with explicit height so it
    -- never grows into the meta area; meta then anchors BELOW the title
    -- with a small gap. This is the stacked layout that prevents the two
    -- text lines from colliding regardless of font size.
    r.title = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.title:SetHeight(15)
    r.title:SetPoint("TOPLEFT",  6, -5)
    r.title:SetPoint("TOPRIGHT", -160, -5)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)

    r.meta = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.meta:SetHeight(11)
    r.meta:SetPoint("TOPLEFT",  r.title, "BOTTOMLEFT",  0, -2)
    r.meta:SetPoint("TOPRIGHT", r.title, "BOTTOMRIGHT", 0, -2)
    r.meta:SetJustifyH("LEFT")
    r.meta:SetWordWrap(false)

    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.right:SetPoint("RIGHT", -8, 0)
    r.right:SetJustifyH("RIGHT")
    r.right:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])

    thin(r.title); thin(r.meta); thin(r.right)
    return r
end

local function acquireRow(parent)
    local r = tremove(HF._rowPool) or buildRow(parent)
    r:SetParent(parent)
    r:Show()
    HF._rowActive[#HF._rowActive + 1] = r
    return r
end

local function releaseAllRows()
    for i = #HF._rowActive, 1, -1 do
        local r = HF._rowActive[i]
        r:Hide()
        r:ClearAllPoints()
        r.title:SetText("")
        r.meta:SetText("")
        r.right:SetText("")
        HF._rowPool[#HF._rowPool + 1] = r
        HF._rowActive[i] = nil
    end
end

-- ─── Window build ──────────────────────────────────────────────────────
function HF:Build()
    if self.frame then return end

    local f = CreateFrame("Frame", "EQHistoryFrame", UIParent, "BackdropTemplate")
    f:SetSize(700, 460)
    f:SetPoint("CENTER")
    -- FULLSCREEN_DIALOG (one above the Options frame's DIALOG strata) so the
    -- History window pops OVER the Options window when opened from the
    -- History tab's "Open History" button. Without this, History rendered
    -- behind Options and was easy to miss entirely.
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()

    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.02, 0.02, 0.02, 0.95)
    f:SetBackdropBorderColor(HEADER_RED[1], HEADER_RED[2], HEADER_RED[3], 1)

    -- Title bar
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 12, -10)
    f.title:SetText("Quest History")
    f.title:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
    thin(f.title)

    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", -4, -4)
    f.close:SetScript("OnClick", function() f:Hide() end)

    -- Title-bar action buttons (right-aligned, growing left from the X).
    -- One helper so they share size + visual style.
    local function makeTitleButton(label, width, onClick)
        local b = CreateFrame("Button", nil, f, "BackdropTemplate")
        b:SetSize(width, 20)
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.10, 0.10, 0.10, 0.95)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.text:SetPoint("CENTER")
        b.text:SetText(label)
        b.text:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
        thin(b.text)
        b:SetScript("OnClick", onClick)
        return b
    end

    f.export = makeTitleButton("Export", 70, function() HF:_openExportPopup() end)
    f.export:SetPoint("RIGHT", f.close, "LEFT", -2, 0)

    -- "Re-scan names" right next to Export. Same call the Options-tab button
    -- makes — placed here too because the user is most likely to notice
    -- nil-name entries while looking at the History window, not while
    -- digging through Options.
    f.rescan = makeTitleButton("Re-scan names", 110, function()
        local R = ns:GetSubsystem("History")
        if not R then return end
        local queued = R:RequestMissingTitles() or 0
        if queued > 0 then
            print(("|cffEBB706EQ History:|r requested %d quest name%s from the server. Names will fill in over the next minute or two."):format(
                queued, queued == 1 and "" or "s"))
        else
            print("|cffEBB706EQ History:|r nothing left to look up \226\128\148 every entry that can be resolved already is.")
        end
    end)
    f.rescan:SetPoint("RIGHT", f.export, "LEFT", -4, 0)
    f.rescan:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Re-scan for quest names", 1, 0.82, 0, 1, true)
        GameTooltip:AddLine("Asks the server for the name of any \"Quest #12345\" entries. They'll fill in over the next minute or two as responses arrive.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    f.rescan:SetScript("OnLeave", GameTooltip_Hide)

    -- Tab bar
    local tabRow = CreateFrame("Frame", nil, f)
    tabRow:SetPoint("TOPLEFT",  10, -(TITLE_BAR_H + 14))
    tabRow:SetPoint("TOPRIGHT", -10, -(TITLE_BAR_H + 14))
    tabRow:SetHeight(TAB_BAR_H)
    f._tabRow = tabRow

    self._tabs = {}
    local function makeTab(id, label)
        local b = CreateFrame("Button", nil, tabRow)
        b:SetSize(125, TAB_BAR_H - 4)                                          -- 125px × 5 tabs + gaps fits 700px window
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints()
        b.bg:SetColorTexture(0, 0, 0, 0.5)
        b.hl = b:CreateTexture(nil, "HIGHLIGHT")
        b.hl:SetAllPoints()
        b.hl:SetColorTexture(1, 1, 1, 0.08)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.text:SetPoint("CENTER")
        b.text:SetText(label)
        thin(b.text)
        b:SetScript("OnClick", function() HF:SwitchTab(id) end)
        b._id = id
        return b
    end
    self._tabs.quests   = makeTab("quests",   "Quests")
    self._tabs.streak   = makeTab("streak",   "Streak")
    self._tabs.timeline = makeTab("timeline", "Chain Timeline")
    self._tabs.activity = makeTab("activity", "Activity")
    self._tabs.totals   = makeTab("totals",   "Totals")
    self._tabs.quests:SetPoint("LEFT", tabRow, "LEFT", 0, 0)
    self._tabs.streak:SetPoint("LEFT", self._tabs.quests, "RIGHT", 4, 0)
    self._tabs.timeline:SetPoint("LEFT", self._tabs.streak, "RIGHT", 4, 0)
    self._tabs.activity:SetPoint("LEFT", self._tabs.timeline, "RIGHT", 4, 0)
    self._tabs.totals:SetPoint("LEFT", self._tabs.activity, "RIGHT", 4, 0)

    -- Content area shared by all tabs
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT",     10, -(TITLE_BAR_H + 14 + TAB_BAR_H + 4))
    content:SetPoint("BOTTOMRIGHT", -10, 10)
    f._content = content

    self.frame = f
    self:_buildPanes(content)
    self:SwitchTab("quests")
end

-- Each pane is a child frame of `content`; SwitchTab toggles visibility.
function HF:_buildPanes(content)
    self._panes = {
        quests   = self:_buildQuestsPane(content),
        streak   = self:_buildStreakPane(content),
        timeline = self:_buildTimelinePane(content),
        activity = self:_buildHeatmapPane(content),
        totals   = self:_buildTotalsPane(content),
    }
end

function HF:SwitchTab(id)
    if not self._panes then return end
    for k, pane in pairs(self._panes) do
        if k == id then pane:Show() else pane:Hide() end
    end
    -- Tab visual highlight
    for k, b in pairs(self._tabs) do
        if k == id then
            b.bg:SetColorTexture(HEADER_RED[1], HEADER_RED[2], HEADER_RED[3], 0.85)
            b.text:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
        else
            b.bg:SetColorTexture(0, 0, 0, 0.5)
            b.text:SetTextColor(0.85, 0.85, 0.85)
        end
    end
    self._activeTab = id
    self:Render()
end

-- ─── Pane: Quests ──────────────────────────────────────────────────────
function HF:_buildQuestsPane(parent)
    local pane = CreateFrame("Frame", nil, parent)
    pane:SetAllPoints()
    pane:Hide()

    local Options = ns:GetSubsystem("Options")

    -- ── Toolbar row 1: search + character dropdown + result count.
    local row1 = CreateFrame("Frame", nil, pane)
    row1:SetPoint("TOPLEFT", 0, 0)
    row1:SetPoint("TOPRIGHT", 0, 0)
    row1:SetHeight(TOOLBAR_H)

    local search = CreateFrame("EditBox", nil, row1, "SearchBoxTemplate")
    search:SetSize(220, 20)
    search:SetPoint("LEFT", row1, "LEFT", 6, 0)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function(eb, userInput)
        if SearchBoxTemplate_OnTextChanged then SearchBoxTemplate_OnTextChanged(eb) end
        if userInput then HF:Render() end
    end)
    pane._search = search

    local charLabel = row1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    charLabel:SetPoint("LEFT", search, "RIGHT", 14, 0)
    charLabel:SetText("Character:")
    thin(charLabel)

    local charDD
    if Options and Options.CreateDropdown then
        local function listFn()
            local R = ns:GetSubsystem("History")
            local out = { { value = "all", label = "All characters" } }
            if R then
                local chars = R:GetCharacters()
                for i = 1, #chars do
                    out[#out + 1] = { value = chars[i], label = chars[i] }
                end
            end
            return out
        end
        local function curFn() return HF._charFilter or "all" end
        local function setFn(v) HF._charFilter = v; HF:Render() end
        charDD = Options:CreateDropdown(row1, nil, listFn, curFn, setFn)
        charDD:SetPoint("LEFT", charLabel, "RIGHT", 4, 0)
        charDD:SetWidth(180)
    end
    pane._charDD = charDD

    pane._count = row1:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pane._count:SetPoint("RIGHT", row1, "RIGHT", -6, 0)
    pane._count:SetText("")
    thin(pane._count)

    -- ── Toolbar row 2: date range + classification + hide-undated.
    local row2 = CreateFrame("Frame", nil, pane)
    row2:SetPoint("TOPLEFT",  row1, "BOTTOMLEFT",  0, -2)
    row2:SetPoint("TOPRIGHT", row1, "BOTTOMRIGHT", 0, -2)
    row2:SetHeight(TOOLBAR_H)

    local dateLabel = row2:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dateLabel:SetPoint("LEFT", row2, "LEFT", 6, 0)
    dateLabel:SetText("Date:")
    thin(dateLabel)

    local DATE_OPTIONS = {
        { value = "all",   label = "All time" },
        { value = "today", label = "Today" },
        { value = "7d",    label = "Past 7 days" },
        { value = "30d",   label = "Past 30 days" },
    }
    local dateDD
    if Options and Options.CreateDropdown then
        local function listFn() return DATE_OPTIONS end
        local function curFn()  return HF._dateFilter or "all" end
        local function setFn(v) HF._dateFilter = v; HF:Render() end
        dateDD = Options:CreateDropdown(row2, nil, listFn, curFn, setFn)
        dateDD:SetPoint("LEFT", dateLabel, "RIGHT", 4, 0)
        dateDD:SetWidth(130)
    end
    pane._dateDD = dateDD

    local typeLabel = row2:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    typeLabel:SetPoint("LEFT", dateDD or dateLabel, "RIGHT", 14, 0)
    typeLabel:SetText("Type:")
    thin(typeLabel)

    local CLASS_OPTIONS = {
        { value = "all",        label = "All types"   },
        { value = "campaign",   label = "Campaign"    },
        { value = "questline",  label = "Questline"   },
        { value = "calling",    label = "Calling"     },
        { value = "recurring",  label = "Recurring"   },
        { value = "worldquest", label = "World Quest" },
        { value = "other",      label = "Other"       },
    }
    local classDD
    if Options and Options.CreateDropdown then
        local function listFn() return CLASS_OPTIONS end
        local function curFn()  return HF._classFilter or "all" end
        local function setFn(v) HF._classFilter = v; HF:Render() end
        classDD = Options:CreateDropdown(row2, nil, listFn, curFn, setFn)
        classDD:SetPoint("LEFT", typeLabel, "RIGHT", 4, 0)
        classDD:SetWidth(150)
    end
    pane._classDD = classDD

    if Options and Options.CreateCheckbox then
        local function get() return HF._hideBackfilled and true or false end
        local function set(v) HF._hideBackfilled = v and true or false; HF:Render() end
        local hideCB = Options:CreateCheckbox(row2,
            "Hide undated  |cffaaaaaa(backfilled)|r",
            get, set)
        hideCB:SetPoint("LEFT", classDD or typeLabel, "RIGHT", 14, 0)
        pane._hideCB = hideCB
    end

    -- ── Scroll list of entries (starts below both toolbar rows).
    local listTop = TOOLBAR_H * 2 + 4
    local scroll = CreateFrame("ScrollFrame", nil, pane, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     0, -listTop)
    scroll:SetPoint("BOTTOMRIGHT", -22, 0)
    pane._scroll = scroll

    local canvas = CreateFrame("Frame", nil, scroll)
    canvas:SetSize(1, 1)
    scroll:SetScrollChild(canvas)
    pane._canvas = canvas

    pane._empty = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pane._empty:SetPoint("CENTER")
    pane._empty:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
    pane._empty:SetText("(no matching quests)")
    pane._empty:Hide()
    thin(pane._empty)

    return pane
end

-- Reverse lookup: which chain contains this questID? Walks the live chain
-- database after warming it up so questline + campaign chains are present
-- (mirrors the warmup the Chain Timeline tab and the "Find in Chain Guide"
-- button on the tracker already do). Returns chainID or nil.
local function findChainForQuest(questID)
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    local QLS      = ns:GetSubsystem("ChainGuideQuestLineSource")
    local CS       = ns:GetSubsystem("ChainGuideCampaignSource")
    if not (Database and Database.chains) then return nil end

    if Database.categories then
        for catID in pairs(Database.categories) do
            if QLS and QLS.EnsureZoneChains    then QLS:EnsureZoneChains(catID)    end
            if CS  and CS.EnsureCampaignChains then CS:EnsureCampaignChains(catID) end
        end
    end
    if QLS and QLS.EnsureChainItems then
        for _, chain in pairs(Database.chains) do QLS:EnsureChainItems(chain) end
    end

    for chainID, chain in pairs(Database.chains) do
        local items = chain.items
        if items then
            for i = 1, #items do
                local it = items[i]
                if it and it.type == "quest" and it.id == questID then
                    return chainID
                end
            end
        end
    end
    return nil
end

function HF:_renderQuests()
    local pane = self._panes.quests
    local R = ns:GetSubsystem("History")
    releaseAllRows()
    if not R then return end

    local searchText = pane._search and pane._search:GetText() or ""
    -- Blizzard's SearchBoxTemplate stores its placeholder in the text when
    -- unfocused; strip the "Search" placeholder so we don't filter on it.
    if searchText == SEARCH then searchText = "" end

    local entries = R:Query({
        search         = searchText,
        char           = HF._charFilter,
        dateRange      = HF._dateFilter,
        classification = HF._classFilter,
        hideBackfilled = HF._hideBackfilled,
    })

    local n = #entries
    if pane._count then pane._count:SetText(("%d entries"):format(n)) end

    if n == 0 then
        pane._empty:Show()
        pane._canvas:SetSize(1, 1)
        return
    end
    pane._empty:Hide()

    -- Cap visible rows for huge result sets to keep the scroll child sane.
    -- Real product would virtualize; cap is enough for v1.
    local MAX = 500
    local shown = math.min(n, MAX)
    local canvasW = pane._scroll:GetWidth() or 600
    pane._canvas:SetSize(canvasW, shown * (ROW_H + 2))

    for i = 1, shown do
        local e = entries[i]
        local row = acquireRow(pane._canvas)
        row:SetPoint("TOPLEFT",  pane._canvas, "TOPLEFT",  0, -((i - 1) * (ROW_H + 2)))
        row:SetPoint("TOPRIGHT", pane._canvas, "TOPRIGHT", 0, -((i - 1) * (ROW_H + 2)))

        row.title:SetText(e.n or ("Quest #" .. tostring(e.q)))
        if e.t and e.t == 0 then
            row.title:SetTextColor(DIM[1], DIM[2], DIM[3])
        else
            row.title:SetTextColor(1, 1, 1)
        end

        local meta = e.c or ""
        if e.z and e.z ~= "" then meta = meta .. "  •  " .. e.z end
        row.meta:SetText(meta)
        row.right:SetText(fmtTime(e.t))

        -- Right-click → open this quest's chain in the Chain Guide. Mirrors
        -- the Chain Timeline tab's affordance so users can jump in either
        -- direction. Tooltip surfaces the affordance + the quest's full
        -- name (which is otherwise truncated for wide-name rows).
        row:EnableMouse(true)
        row._questID = e.q
        row._fullName = e.n
        row:SetScript("OnMouseUp", function(rowFrame, button)
            if button ~= "RightButton" then return end
            local chainID = findChainForQuest(rowFrame._questID)
            if chainID then
                local CG = ns:GetSubsystem("ChainGuide")
                if CG then
                    if CG.Open          then CG:Open()                end
                    if CG.NavigateChain then CG:NavigateChain(chainID) end
                end
            else
                print(("|cffEBB706EQ History|r: |cffffffff%s|r isn't part of any chain in the Chain Guide."):format(
                    rowFrame._fullName or ("Quest #" .. tostring(rowFrame._questID))))
            end
        end)
        row:SetScript("OnEnter", function(rowFrame)
            GameTooltip:SetOwner(rowFrame, "ANCHOR_CURSOR_RIGHT")
            GameTooltip:SetText(rowFrame._fullName or ("Quest #" .. tostring(rowFrame._questID)), 1, 1, 1, 1, true)
            GameTooltip:AddLine("Right-click to open in the Chain Guide", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
    end

    if n > MAX then
        pane._count:SetText(("%d entries (showing newest %d)"):format(n, MAX))
    end
end

-- ─── Pane: Streak ──────────────────────────────────────────────────────
function HF:_buildStreakPane(parent)
    local pane = CreateFrame("Frame", nil, parent)
    pane:SetAllPoints()
    pane:Hide()

    local function bigStat(yOffset)
        local label = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", 30, yOffset)
        label:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
        thin(label)

        local value = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        value:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
        value:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
        thin(value)
        return label, value
    end

    pane._currentLabel, pane._currentValue = bigStat(-20)
    pane._currentLabel:SetText("Current daily streak")

    pane._bestLabel, pane._bestValue = bigStat(-80)
    pane._bestLabel:SetText("Best daily streak")

    pane._totalLabel, pane._totalValue = bigStat(-140)
    pane._totalLabel:SetText("Total quests recorded with a date")

    pane._note = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pane._note:SetPoint("TOPLEFT", 30, -210)
    pane._note:SetPoint("TOPRIGHT", -30, -210)
    pane._note:SetJustifyH("LEFT")
    pane._note:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
    pane._note:SetText(
        "Streak counts consecutive days (server time) with at least one quest turn-in across any character on the account. " ..
        "Today or yesterday keeps the streak alive — you don't lose it until a whole day passes with no activity.")
    thin(pane._note)

    return pane
end

function HF:_renderStreak()
    local pane = self._panes.streak
    local R = ns:GetSubsystem("History")
    if not R then return end
    local s = R:Streak()
    pane._currentValue:SetText(("%d days"):format(s.current))
    pane._bestValue:SetText(("%d days"):format(s.best))
    pane._totalValue:SetText(("%d"):format(s.total))
end

-- ─── Pane: Chain Timeline ──────────────────────────────────────────────
function HF:_buildTimelinePane(parent)
    local pane = CreateFrame("Frame", nil, parent)
    pane:SetAllPoints()
    pane:Hide()

    pane._intro = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pane._intro:SetPoint("TOPLEFT", 6, -4)
    pane._intro:SetPoint("TOPRIGHT", -22, -4)
    pane._intro:SetJustifyH("LEFT")
    pane._intro:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
    pane._intro:SetText(
        "Chains where you have at least one completed quest. Click a chain to expand and see per-quest completion dates.")
    thin(pane._intro)

    local scroll = CreateFrame("ScrollFrame", nil, pane, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     0, -28)
    scroll:SetPoint("BOTTOMRIGHT", -22, 0)
    pane._scroll = scroll
    local canvas = CreateFrame("Frame", nil, scroll)
    canvas:SetSize(1, 1)
    scroll:SetScrollChild(canvas)
    pane._canvas = canvas

    pane._empty = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pane._empty:SetPoint("CENTER")
    pane._empty:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
    pane._empty:SetText("(no chain quests recorded yet)")
    pane._empty:Hide()
    thin(pane._empty)

    -- Persistent expansion state across re-renders within a session.
    HF._timelineOpen = HF._timelineOpen or {}
    return pane
end

-- Expand/collapse + completion markers used in the Chain Timeline rows.
-- These render via texture escapes (|T...|t / |A...|a) so they work in
-- any font — the row title FontString uses Arial Narrow, which is
-- missing the ▶/▼ Unicode glyphs the previous version relied on and
-- showed empty squares instead.
local MARKER_COLLAPSED = "|TInterface\\Buttons\\UI-PlusButton-Up:14:14|t "
local MARKER_EXPANDED  = "|TInterface\\Buttons\\UI-MinusButton-Up:14:14|t "
local MARKER_COMPLETE  = "|A:common-icon-checkmark:14:14|a "

-- A timeline row renders either a chain header or a quest under that header.
-- We use the same row pool as Quests pane — fields adapt by usage.
function HF:_renderTimeline()
    local pane = self._panes.timeline
    local R         = ns:GetSubsystem("History")
    local Database  = ns:GetSubsystem("ChainGuideDatabase")
    local QLS       = ns:GetSubsystem("ChainGuideQuestLineSource")
    local CS        = ns:GetSubsystem("ChainGuideCampaignSource")
    releaseAllRows()
    if not (R and Database) then return end

    -- Trigger discovery of all chains so campaign + questline chains are
    -- in Database.chains. Same warmup the "Find in Chain Guide" button uses.
    if Database.categories then
        for catID in pairs(Database.categories) do
            if QLS and QLS.EnsureZoneChains    then QLS:EnsureZoneChains(catID)    end
            if CS  and CS.EnsureCampaignChains then CS:EnsureCampaignChains(catID) end
        end
    end
    if QLS and QLS.EnsureChainItems then
        for _, chain in pairs(Database.chains) do QLS:EnsureChainItems(chain) end
    end

    local completion = R:CompletionMap()

    -- Score each chain: number of completed quests in it + the latest date
    -- among them (for sorting "most recently progressed first").
    local sorted = {}
    for chainID, chain in pairs(Database.chains) do
        local items = chain.items
        if items and #items > 0 then
            local doneN, latest = 0, 0
            for i = 1, #items do
                local it = items[i]
                if it and it.type == "quest" then
                    local t = completion[it.id]
                    if t and t ~= nil then
                        doneN = doneN + 1
                        if t > latest then latest = t end
                    end
                end
            end
            if doneN > 0 then
                sorted[#sorted + 1] = { id = chainID, chain = chain, doneN = doneN, latest = latest, total = #items }
            end
        end
    end

    if #sorted == 0 then
        pane._empty:Show()
        pane._canvas:SetSize(1, 1)
        return
    end
    pane._empty:Hide()

    -- Most recently progressed chain first; ties broken by name.
    table.sort(sorted, function(a, b)
        if a.latest ~= b.latest then return a.latest > b.latest end
        return (a.chain.name or "") < (b.chain.name or "")
    end)

    local canvasW = pane._scroll:GetWidth() or 600
    local y = 0
    for i = 1, #sorted do
        local rec = sorted[i]
        local chain = rec.chain
        local row = acquireRow(pane._canvas)
        row:SetPoint("TOPLEFT",  pane._canvas, "TOPLEFT",  0, -y)
        row:SetPoint("TOPRIGHT", pane._canvas, "TOPRIGHT", 0, -y)
        local marker  = HF._timelineOpen[rec.id] and MARKER_EXPANDED or MARKER_COLLAPSED
        local check   = (rec.doneN >= rec.total) and MARKER_COMPLETE or ""
        row.title:SetText(marker .. check .. (chain.name or ("Chain #" .. tostring(rec.id))))
        row.title:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
        row.meta:SetText(("%d of %d quests recorded"):format(rec.doneN, rec.total))
        row.right:SetText(fmtTime(rec.latest))
        row:EnableMouse(true)
        row:SetScript("OnMouseUp", function(_, button)
            if button == "RightButton" then
                local CG = ns:GetSubsystem("ChainGuide")
                if CG then
                    if CG.Open          then CG:Open()              end
                    if CG.NavigateChain then CG:NavigateChain(rec.id) end
                end
                return
            end
            HF._timelineOpen[rec.id] = not HF._timelineOpen[rec.id]
            HF:_renderTimeline()
        end)
        -- Hover hint so the right-click affordance is discoverable.
        row:SetScript("OnEnter", function(rowFrame)
            GameTooltip:SetOwner(rowFrame, "ANCHOR_CURSOR_RIGHT")
            GameTooltip:SetText(chain.name or "Chain", 1, 0.82, 0)
            GameTooltip:AddLine("Click to expand", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("Right-click to open in the Chain Guide", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        y = y + ROW_H + 2

        if HF._timelineOpen[rec.id] then
            for j = 1, #chain.items do
                local it = chain.items[j]
                if it and it.type == "quest" then
                    local sub = acquireRow(pane._canvas)
                    sub:SetPoint("TOPLEFT",  pane._canvas, "TOPLEFT",  24, -y)
                    sub:SetPoint("TOPRIGHT", pane._canvas, "TOPRIGHT", 0, -y)
                    local t = completion[it.id]
                    local title = ns.Util.QuestTitle(it.id) or it.name or ("Quest #" .. tostring(it.id))
                    sub.title:SetText(title)
                    sub.meta:SetText("ID " .. tostring(it.id))
                    if t and t ~= nil then
                        sub.title:SetTextColor(1, 1, 1)
                        sub.right:SetText(fmtTime(t))
                    else
                        sub.title:SetTextColor(DIM[1], DIM[2], DIM[3])
                        sub.right:SetText("—")
                        sub.right:SetTextColor(DIM[1], DIM[2], DIM[3])
                    end
                    y = y + ROW_H + 2
                end
            end
        end
    end
    pane._canvas:SetSize(canvasW, math.max(y, 1))
end

-- ─── Pane: Activity heatmap ────────────────────────────────────────────
function HF:_buildHeatmapPane(parent)
    local pane = CreateFrame("Frame", nil, parent)
    pane:SetAllPoints()
    pane:Hide()

    pane._intro = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pane._intro:SetPoint("TOPLEFT",  30, -12)
    pane._intro:SetPoint("TOPRIGHT", -30, -12)
    pane._intro:SetJustifyH("LEFT")
    pane._intro:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
    pane._intro:SetText(("Quest turn-ins per day over the last %d days. Brighter = busier. Hover a cell for the date and count. The bottom-right cell is today."):format(HEATMAP_DAYS - 1))
    thin(pane._intro)

    local gridW = HEATMAP_COLS * (CELL_SIZE + CELL_GAP) - CELL_GAP
    local gridH = HEATMAP_ROWS * (CELL_SIZE + CELL_GAP) - CELL_GAP
    pane._grid = CreateFrame("Frame", nil, pane)
    pane._grid:SetSize(gridW, gridH)
    pane._grid:SetPoint("TOP", 0, -56)

    pane._cells = {}
    for i = 1, HEATMAP_DAYS do
        local cell = CreateFrame("Frame", nil, pane._grid)
        cell:SetSize(CELL_SIZE, CELL_SIZE)
        cell:EnableMouse(true)
        local col = math.floor((i - 1) / HEATMAP_ROWS)
        local row = (i - 1) % HEATMAP_ROWS
        cell:SetPoint("TOPLEFT", col * (CELL_SIZE + CELL_GAP), -(row * (CELL_SIZE + CELL_GAP)))

        cell.bg = cell:CreateTexture(nil, "ARTWORK")
        cell.bg:SetAllPoints()
        cell.bg:SetColorTexture(0.15, 0.15, 0.15, 1)

        cell:SetScript("OnEnter", function(cf)
            if not cf._day then return end
            GameTooltip:SetOwner(cf, "ANCHOR_CURSOR_RIGHT")
            GameTooltip:SetText(date("%A, %Y-%m-%d", cf._day * 86400), 1, 1, 1)
            local c = cf._count or 0
            GameTooltip:AddLine(("%d quest%s turned in"):format(c, c == 1 and "" or "s"),
                YELLOW[1], YELLOW[2], YELLOW[3])
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", GameTooltip_Hide)
        pane._cells[i] = cell
    end

    -- Color-scale legend below the grid.
    local legend = CreateFrame("Frame", nil, pane)
    legend:SetSize(180, CELL_SIZE)
    legend:SetPoint("TOP", pane._grid, "BOTTOM", 0, -18)

    local lessLabel = legend:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    lessLabel:SetText("Less")
    lessLabel:SetPoint("LEFT")
    thin(lessLabel)

    local swatches = {}
    for i = 1, 5 do
        local sw = legend:CreateTexture(nil, "ARTWORK")
        sw:SetSize(CELL_SIZE - 2, CELL_SIZE - 2)
        local prev = (i == 1) and lessLabel or swatches[i - 1]
        sw:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        local intensity = (i - 1) / 4
        sw:SetColorTexture(
            0.15 + (YELLOW[1] - 0.15) * intensity,
            0.15 + (YELLOW[2] - 0.15) * intensity,
            0.15 + (YELLOW[3] - 0.15) * intensity,
            1)
        swatches[i] = sw
    end
    local moreLabel = legend:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    moreLabel:SetText("More")
    moreLabel:SetPoint("LEFT", swatches[5], "RIGHT", 4, 0)
    thin(moreLabel)

    -- Summary stats below the legend: total + busiest day.
    pane._totalValue = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    pane._totalValue:SetPoint("TOP", legend, "BOTTOM", 0, -28)
    pane._totalValue:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
    thin(pane._totalValue)

    pane._totalLabel = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pane._totalLabel:SetPoint("TOP", pane._totalValue, "BOTTOM", 0, -2)
    pane._totalLabel:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
    pane._totalLabel:SetText(("total turn-ins in the last %d days"):format(HEATMAP_DAYS - 1))
    thin(pane._totalLabel)

    pane._busiestValue = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pane._busiestValue:SetPoint("TOP", pane._totalLabel, "BOTTOM", 0, -12)
    pane._busiestValue:SetTextColor(0.85, 0.85, 0.85)
    thin(pane._busiestValue)

    return pane
end

function HF:_renderHeatmap()
    local pane = self._panes.activity
    local R = ns:GetSubsystem("History")
    if not (pane and R and R.DayCounts) then return end

    local counts, today = R:DayCounts(HEATMAP_DAYS - 1)
    local maxCount, total, busiestDay, busiestCount = 0, 0, nil, 0
    for d, c in pairs(counts) do
        total = total + c
        if c > maxCount then maxCount = c end
        if c > busiestCount then busiestCount = c; busiestDay = d end
    end

    for i = 1, HEATMAP_DAYS do
        local cell = pane._cells[i]
        local day = today - (HEATMAP_DAYS - i)
        local count = counts[day] or 0
        cell._day   = day
        cell._count = count

        local intensity
        if count == 0 then
            intensity = 0                                                     -- dark grey baseline
        else
            -- Scale against the busiest day; floor non-zero so even one
            -- quest is visibly brighter than an empty day.
            intensity = math.max(0.25, math.min(1.0, count / math.max(maxCount, 1)))
        end
        cell.bg:SetColorTexture(
            0.15 + (YELLOW[1] - 0.15) * intensity,
            0.15 + (YELLOW[2] - 0.15) * intensity,
            0.15 + (YELLOW[3] - 0.15) * intensity,
            1)
    end

    pane._totalValue:SetText(tostring(total))
    if busiestDay and busiestCount > 0 then
        pane._busiestValue:SetText(
            ("Busiest day: %s (%d quests)"):format(date("%Y-%m-%d", busiestDay * 86400), busiestCount))
    else
        pane._busiestValue:SetText(" ")
    end
end

-- ─── Pane: Totals ──────────────────────────────────────────────────────
-- Format copper into a "Ng Xs Yc" string using Blizzard's icon-bearing
-- helper when available so the gold/silver/copper icons render inline.
-- Even 0 is routed through GetCoinTextureString so the slot reads as a
-- coin icon rather than a bare unlabeled "0".
local function fmtMoney(copper)
    copper = copper or 0
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    return ("%dg %ds %dc"):format(g, s, c)
end

local function fmtBigNumber(n)
    if not n then return "0" end
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return tostring(n)
end

function HF:_buildTotalsPane(parent)
    local pane = CreateFrame("Frame", nil, parent)
    pane:SetAllPoints()
    pane:Hide()

    pane._intro = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pane._intro:SetPoint("TOPLEFT",  30, -12)
    pane._intro:SetPoint("TOPRIGHT", -30, -12)
    pane._intro:SetJustifyH("LEFT")
    pane._intro:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
    pane._intro:SetText("Account-wide quest rewards. Totals count only quests turned in while reward tracking was on; older entries didn't capture XP or gold.")
    thin(pane._intro)

    -- Helper to make a "Label \n Value" pair stacked vertically.
    local function pairBlock(yOffset, labelText, big)
        local label = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", 30, yOffset)
        label:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
        label:SetText(labelText)
        thin(label)

        local value = pane:CreateFontString(nil, "OVERLAY",
            big and "GameFontNormalLarge" or "GameFontHighlight")
        value:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
        value:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
        thin(value)
        return value
    end

    pane._totalQuests = pairBlock(-44,  "Total quests with reward data", true)
    pane._totalGold   = pairBlock(-94,  "Total gold earned",             true)
    pane._totalXP     = pairBlock(-144, "Total XP earned",               true)

    -- Per-character section header.
    local h2 = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h2:SetPoint("TOPLEFT", 30, -200)
    h2:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
    h2:SetText("By character")
    thin(h2)
    pane._charHeader = h2

    -- Per-character rows — created on demand and reused across renders.
    -- Cap at 8 visible rows so the Top-rewards section pinned to the bottom
    -- of the pane never collides with the char list above it.
    pane._charRows = {}

    -- Top rewards section pinned to the BOTTOM of the pane. Anchoring from
    -- BOTTOMLEFT (rather than absolute TOPLEFT offsets) keeps the section
    -- visible regardless of pane height, so a smaller window or future
    -- layout tweak doesn't push it off the bottom edge again.
    pane._topXP = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pane._topXP:SetPoint("BOTTOMLEFT",  30,   8)
    pane._topXP:SetPoint("BOTTOMRIGHT", -30,  8)
    pane._topXP:SetJustifyH("LEFT")
    pane._topXP:SetTextColor(1, 1, 1)
    thin(pane._topXP)

    pane._topGold = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pane._topGold:SetPoint("BOTTOMLEFT",  pane._topXP, "TOPLEFT",  0, 4)
    pane._topGold:SetPoint("BOTTOMRIGHT", pane._topXP, "TOPRIGHT", 0, 4)
    pane._topGold:SetJustifyH("LEFT")
    pane._topGold:SetTextColor(1, 1, 1)
    thin(pane._topGold)

    local h3 = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h3:SetPoint("BOTTOMLEFT", pane._topGold, "TOPLEFT", 0, 6)
    h3:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
    h3:SetText("Top single-quest rewards")
    thin(h3)
    pane._topHeader = h3

    return pane
end

local function ensureCharRow(pane, idx)
    local r = pane._charRows[idx]
    if r then return r end
    r = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r:SetTextColor(0.92, 0.92, 0.92)
    r:SetJustifyH("LEFT")
    r:SetPoint("TOPLEFT",  40, -222 - (idx - 1) * 14)
    r:SetPoint("TOPRIGHT", -30, -222 - (idx - 1) * 14)
    thin(r)
    pane._charRows[idx] = r
    return r
end

function HF:_renderTotals()
    local pane = self._panes.totals
    local R = ns:GetSubsystem("History")
    if not (pane and R and R.Totals) then return end
    local t = R:Totals()

    pane._totalQuests:SetText(fmtBigNumber(t.totalCount))
    pane._totalGold:SetText(fmtMoney(t.totalMoney))
    pane._totalXP:SetText(fmtBigNumber(t.totalXP) .. " XP")

    -- Per-character list, sorted by turn-in count desc.
    local chars = {}
    for k, v in pairs(t.byChar) do
        chars[#chars + 1] = { key = k, rec = v }
    end
    table.sort(chars, function(a, b) return a.rec.count > b.rec.count end)

    local MAX_VISIBLE = 8
    local shown = math.min(#chars, MAX_VISIBLE)
    for i = 1, shown do
        local row = ensureCharRow(pane, i)
        local c = chars[i]
        row:SetText(("%s  \194\183  %s quests  \194\183  %s  \194\183  %s XP"):format(
            c.key,
            fmtBigNumber(c.rec.count),
            fmtMoney(c.rec.money),
            fmtBigNumber(c.rec.xp)))
        row:Show()
    end
    -- Hide any leftover rows from a prior render with more characters.
    for i = shown + 1, #pane._charRows do
        pane._charRows[i]:Hide()
    end

    if t.topGold then
        pane._topGold:SetText(("Biggest gold:  |cffffffff%s|r  \194\183  %s"):format(
            t.topGold.n or ("Quest #" .. tostring(t.topGold.q)),
            fmtMoney(t.topGold.m)))
    else
        pane._topGold:SetText("Biggest gold:  (none yet)")
    end
    if t.topXP then
        pane._topXP:SetText(("Biggest XP:    |cffffffff%s|r  \194\183  %s XP"):format(
            t.topXP.n or ("Quest #" .. tostring(t.topXP.q)),
            fmtBigNumber(t.topXP.xp)))
    else
        pane._topXP:SetText("Biggest XP:    (none yet)")
    end
end

-- ─── Dispatch ──────────────────────────────────────────────────────────
function HF:Render()
    if not self.frame or not self.frame:IsShown() then return end
    local t = self._activeTab
    if t == "quests"   then self:_renderQuests() end
    if t == "streak"   then self:_renderStreak() end
    if t == "timeline" then self:_renderTimeline() end
    if t == "activity" then self:_renderHeatmap() end
    if t == "totals"   then self:_renderTotals() end
end

function HF:Toggle()
    self:Build()
    if self.frame:IsShown() then self.frame:Hide() else self:Open() end
end

function HF:Open()
    self:Build()
    self.frame:Show()
    -- Kick off async title fetches for any entries we still don't have
    -- names for (returning users, recent backfills). Results trickle in
    -- via QUEST_DATA_LOAD_RESULT and re-render the window automatically.
    local R = ns:GetSubsystem("History")
    if R and R.RequestMissingTitles then R:RequestMissingTitles() end
    self:Render()
end

-- ─── Export to clipboard ──────────────────────────────────────────────
-- Per-tab text builders. Each returns a plain-text block suitable for
-- pasting into Discord, a spreadsheet, etc. Output is built once on
-- click; not a hot path so allocating fresh tables is fine.

local function fmtMoneyText(copper)
    copper = copper or 0
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then return ("%dg %ds %dc"):format(g, s, c) end
    if s > 0 then return ("%ds %dc"):format(s, c) end
    return ("%dc"):format(c)
end

function HF:_exportQuests()
    local R = ns:GetSubsystem("History")
    if not R then return "(history unavailable)" end
    local pane = self._panes.quests
    local searchText = pane._search and pane._search:GetText() or ""
    if searchText == SEARCH then searchText = "" end
    local entries = R:Query({
        search         = searchText,
        char           = HF._charFilter,
        dateRange      = HF._dateFilter,
        classification = HF._classFilter,
        hideBackfilled = HF._hideBackfilled,
    })
    local lines = { ("# Quest History — %d entries"):format(#entries) }
    lines[#lines + 1] = "# date | character | quest | type | zone"
    for i = 1, #entries do
        local e = entries[i]
        local d = (e.t and e.t > 0) and date("%Y-%m-%d %H:%M", e.t) or "(before tracking)"
        lines[#lines + 1] = ("%s | %s | %s | %s | %s"):format(
            d, e.c or "?", e.n or ("Quest #" .. tostring(e.q)), e.k or "?", e.z or "")
    end
    return table.concat(lines, "\n")
end

function HF:_exportStreak()
    local R = ns:GetSubsystem("History")
    if not R then return "(history unavailable)" end
    local s = R:Streak()
    return ("Quest History — Streak\n\nCurrent daily streak: %d days\nBest daily streak: %d days\nTotal dated entries: %d"):format(
        s.current, s.best, s.total)
end

function HF:_exportTimeline()
    local R        = ns:GetSubsystem("History")
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    if not (R and Database) then return "(history or chain guide unavailable)" end
    local completion = R:CompletionMap()
    local sorted = {}
    for chainID, chain in pairs(Database.chains) do
        if chain.items and #chain.items > 0 then
            local doneN, latest = 0, 0
            for i = 1, #chain.items do
                local it = chain.items[i]
                if it and it.type == "quest" and completion[it.id] then
                    doneN = doneN + 1
                    if completion[it.id] > latest then latest = completion[it.id] end
                end
            end
            if doneN > 0 then
                sorted[#sorted + 1] = { id = chainID, chain = chain, doneN = doneN, latest = latest }
            end
        end
    end
    table.sort(sorted, function(a, b) return a.latest > b.latest end)
    local lines = { "# Chain Timeline — chains with at least one recorded completion" }
    for _, rec in ipairs(sorted) do
        lines[#lines + 1] = ("## %s — %d of %d quests"):format(
            rec.chain.name or ("Chain #" .. tostring(rec.id)), rec.doneN, #rec.chain.items)
        for j = 1, #rec.chain.items do
            local it = rec.chain.items[j]
            if it and it.type == "quest" then
                local t = completion[it.id]
                local title = ns.Util.QuestTitle(it.id) or it.name or ("Quest #" .. tostring(it.id))
                local when = t and ((t > 0 and date("%Y-%m-%d", t)) or "(before tracking)") or "—"
                lines[#lines + 1] = ("  - %s [%s]"):format(title, when)
            end
        end
    end
    return table.concat(lines, "\n")
end

function HF:_exportActivity()
    local R = ns:GetSubsystem("History")
    if not (R and R.DayCounts) then return "(history unavailable)" end
    local counts, today = R:DayCounts(HEATMAP_DAYS - 1)
    local lines = { ("# Activity — last %d days"):format(HEATMAP_DAYS) }
    lines[#lines + 1] = "# date | turn-ins"
    for i = HEATMAP_DAYS, 1, -1 do
        local day = today - (i - 1)
        lines[#lines + 1] = ("%s | %d"):format(date("%Y-%m-%d", day * 86400), counts[day] or 0)
    end
    return table.concat(lines, "\n")
end

function HF:_exportTotals()
    local R = ns:GetSubsystem("History")
    if not (R and R.Totals) then return "(history unavailable)" end
    local t = R:Totals()
    local lines = {
        "Quest History — Totals",
        "",
        ("Total quests with reward data: %d"):format(t.totalCount),
        ("Total gold earned: %s"):format(fmtMoneyText(t.totalMoney)),
        ("Total XP earned: %d"):format(t.totalXP),
        "",
        "By character:",
    }
    local chars = {}
    for k, v in pairs(t.byChar) do chars[#chars + 1] = { key = k, rec = v } end
    table.sort(chars, function(a, b) return a.rec.count > b.rec.count end)
    for _, c in ipairs(chars) do
        lines[#lines + 1] = ("  %s — %d quests, %s, %d XP"):format(
            c.key, c.rec.count, fmtMoneyText(c.rec.money), c.rec.xp)
    end
    if t.topGold then
        lines[#lines + 1] = ""
        lines[#lines + 1] = ("Biggest single gold reward: %s (%s)"):format(
            t.topGold.n or ("Quest #" .. tostring(t.topGold.q)), fmtMoneyText(t.topGold.m))
    end
    if t.topXP then
        lines[#lines + 1] = ("Biggest single XP reward: %s (%d XP)"):format(
            t.topXP.n or ("Quest #" .. tostring(t.topXP.q)), t.topXP.xp)
    end
    return table.concat(lines, "\n")
end

function HF:_exportForTab(tabId)
    if tabId == "quests"   then return self:_exportQuests()   end
    if tabId == "streak"   then return self:_exportStreak()   end
    if tabId == "timeline" then return self:_exportTimeline() end
    if tabId == "activity" then return self:_exportActivity() end
    if tabId == "totals"   then return self:_exportTotals()   end
    return "(nothing to export)"
end

-- Lazy-built popup containing a multi-line edit box with the export text
-- pre-selected so the user can hit Ctrl+C immediately. Same popup reused
-- across tabs — opening it again just replaces the text.
function HF:_buildExportPopup()
    if self._exportPopup then return self._exportPopup end

    local p = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    p:SetSize(540, 380)
    p:SetPoint("CENTER")
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:SetMovable(true)
    p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop",  p.StopMovingOrSizing)
    p:SetClampedToScreen(true)
    p:Hide()
    p:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    p:SetBackdropColor(0.02, 0.02, 0.02, 0.97)
    p:SetBackdropBorderColor(HEADER_RED[1], HEADER_RED[2], HEADER_RED[3], 1)

    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    p.title:SetPoint("TOPLEFT", 12, -10)
    p.title:SetText("Export")
    p.title:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
    thin(p.title)

    p.hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.hint:SetPoint("TOPLEFT", 12, -32)
    p.hint:SetText("Press Ctrl+A to select all, then Ctrl+C to copy.")
    thin(p.hint)

    p.close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
    p.close:SetPoint("TOPRIGHT", -4, -4)
    p.close:SetScript("OnClick", function() p:Hide() end)

    local scroll = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -52)
    scroll:SetPoint("BOTTOMRIGHT", -32, 12)
    p._scroll = scroll

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(scroll:GetWidth())
    edit:SetScript("OnEscapePressed", function() p:Hide() end)
    scroll:SetScrollChild(edit)
    p._edit = edit

    self._exportPopup = p
    return p
end

function HF:_openExportPopup()
    local p = self:_buildExportPopup()
    local text = self:_exportForTab(self._activeTab) or ""
    p._edit:SetText(text)
    p._edit:HighlightText()                                                  -- pre-select so a single Ctrl+C copies everything
    p._edit:SetFocus()
    p:Show()
end
