-- Options/Frame.lua
-- Custom options window matching the "Everything…" addon-suite style:
--   - Black background ~75% opacity
--   - Red (#6D0501) active tab fill, white tab text
--   - Yellow (#EBB706) buttons / stat values
--   - Red section headers
-- Tabs are registered by Options/Tab*.lua files via Options:AddTab(id, label, builder).

local _, ns = ...

local Options = ns:RegisterSubsystem("Options", {})
Options.tabs = {}
Options.tabOrder = {}

local TAB_BG_ACTIVE   = ns.Util.color.tabActive    -- #6D0501
local TAB_BG_INACTIVE = ns.Util.color.tabInactive
local FRAME_BG        = ns.Util.color.optionsBg
local HEADER_RED      = ns.Util.color.headerRed    -- #6D0501
local YELLOW          = ns.Util.color.buttonYellow -- #EBB706
local TAB_HEIGHT      = 28
local TAB_PADDING_X   = 18

function Options:AddTab(id, label, builder)
    self.tabs[id] = { id = id, label = label, builder = builder }
    self.tabOrder[#self.tabOrder + 1] = id
end

local function styleTabButton(btn, active)
    local c = active and TAB_BG_ACTIVE or TAB_BG_INACTIVE
    btn.bg:SetColorTexture(c[1], c[2], c[3], c[4])
    btn.text:SetTextColor(1, 1, 1, 1)
end

function Options:Build()
    if self.frame then return end
    local f = CreateFrame("Frame", "EQOptionsFrame", UIParent, "BackdropTemplate")
    -- 1020 wide (was 900): the right "Options" column starts at header+460 and
    -- several checkbox hint strings ("…/ completed quests)", "…after accepting)")
    -- ran off the right edge at 900. Labels are left-aligned, so the extra room
    -- just reads as normal ragged-right whitespace. Everything is anchored to
    -- the left, the top-right, or both sides, so only right-side room is added.
    f:SetSize(1020, 600)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:Hide()

    -- Flat near-black fill + thin 1px red (#6D0501) border, matching the
    -- Everything-suite frame style (see EverythingDelves UI/MainFrame.lua).
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(unpack(FRAME_BG))
    f:SetBackdropBorderColor(0.427, 0.020, 0.004, 1.0)   -- #6D0501

    -- Title
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -14)
    f.title:SetText("Everything Quests")
    f.title:SetTextColor(unpack(HEADER_RED))
    f.title:SetFont(f.title:GetFont(), 25, "OUTLINE")   -- match sibling addon titles

    -- Version label
    f.version = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.version:SetPoint("TOPRIGHT", -34, -14)
    f.version:SetText("v" .. (ns.VERSION or "1.11.0"))
    f.version:SetTextColor(unpack(YELLOW))

    -- Discord link, top-left — mirrors the version label on the right and
    -- flanks the centered title so it reads as a deliberate call-out. A small
    -- Discord-blurple chip (#5865F2) sits before the text as a brand accent.
    -- Click pops a copyable invite (ns:ShowDiscord) — WoW can't open a browser.
    f.discord = CreateFrame("Button", nil, f)
    f.discord.icon = f.discord:CreateTexture(nil, "OVERLAY")
    f.discord.icon:SetSize(16, 16)
    f.discord.icon:SetPoint("LEFT", 0, 0)
    -- Official Discord symbol (white, 64x64 TGA with alpha) at
    -- Media\Textures\discord.tga. If the file is ever missing, WoW draws a
    -- placeholder square — replace the asset, don't recolor the logo.
    f.discord.icon:SetTexture("Interface\\AddOns\\EverythingQuests\\Media\\Textures\\discord.tga")
    f.discord.text = f.discord:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.discord.text:SetPoint("LEFT", f.discord.icon, "RIGHT", 5, 0)
    f.discord.text:SetText("Join our Discord!")
    f.discord.text:SetTextColor(unpack(YELLOW))
    f.discord:SetSize(16 + 5 + f.discord.text:GetStringWidth() + 4, 18)
    f.discord:SetPoint("TOPLEFT", 14, -15)
    f.discord:SetScript("OnClick", function() ns:ShowDiscord() end)
    f.discord:SetScript("OnEnter", function(s)
        s.text:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Join our Discord", YELLOW[1], YELLOW[2], YELLOW[3])
        GameTooltip:AddLine("Click to copy the invite link.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    f.discord:SetScript("OnLeave", function(s)
        s.text:SetTextColor(unpack(YELLOW))
        GameTooltip:Hide()
    end)

    -- Close button (X) — yellow text in a small dark square (matches screenshot)
    local close = CreateFrame("Button", nil, f)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -8, -10)
    local closeBg = close:CreateTexture(nil, "BACKGROUND")
    closeBg:SetAllPoints()
    closeBg:SetColorTexture(0, 0, 0, 0.9)
    local closeText = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeText:SetPoint("CENTER")
    closeText:SetText("X")
    closeText:SetTextColor(1, 1, 1, 1)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Tab strip
    f.tabStrip = CreateFrame("Frame", nil, f)
    f.tabStrip:SetPoint("TOPLEFT", 12, -44)
    f.tabStrip:SetPoint("TOPRIGHT", -12, -44)
    f.tabStrip:SetHeight(TAB_HEIGHT)

    f.tabButtons = {}
    f.tabContent = CreateFrame("Frame", nil, f)
    f.tabContent:SetPoint("TOPLEFT", 12, -44 - TAB_HEIGHT - 6)
    f.tabContent:SetPoint("BOTTOMRIGHT", -12, 12)

    self.frame = f
    self:RebuildTabs()
end

function Options:RebuildTabs()
    local f = self.frame
    if not f then return end
    -- Hide existing
    for _, b in pairs(f.tabButtons) do b:Hide() end

    local x = 0
    for _, id in ipairs(self.tabOrder) do
        local tab = self.tabs[id]
        local btn = f.tabButtons[id]
        if not btn then
            btn = CreateFrame("Button", nil, f.tabStrip)
            btn:SetHeight(TAB_HEIGHT)
            btn.bg = btn:CreateTexture(nil, "BACKGROUND")
            btn.bg:SetAllPoints()
            btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            btn.text:SetPoint("CENTER")
            btn:SetScript("OnClick", function() Options:SelectTab(id) end)
            f.tabButtons[id] = btn
        end
        btn.text:SetText(tab.label)
        btn:SetWidth(btn.text:GetStringWidth() + TAB_PADDING_X * 2)
        btn:ClearAllPoints()
        btn:SetPoint("LEFT", f.tabStrip, "LEFT", x, 0)
        x = x + btn:GetWidth() + 4
        styleTabButton(btn, false)
        btn:Show()
    end
    -- Restore last-active tab, falling back to the first tab if the saved
    -- one no longer exists (e.g. a tab was removed in an update).
    local DB = ns:GetSubsystem("DB")
    local saved = DB and DB.char.lastOptionsTab
    local active = (saved and self.tabs[saved]) and saved or self.tabOrder[1]
    if self.tabs[active] then self:SelectTab(active) end
end

function Options:SelectTab(id)
    local f = self.frame
    if not f then return end
    for tabId, btn in pairs(f.tabButtons) do
        styleTabButton(btn, tabId == id)
    end
    -- Clear content
    if self.activeContent then self.activeContent:Hide() end
    local tab = self.tabs[id]
    if tab and tab.builder then
        if not tab.contentFrame then
            tab.contentFrame = CreateFrame("Frame", nil, f.tabContent)
            tab.contentFrame:SetAllPoints()
            tab.builder(tab.contentFrame)
        end
        tab.contentFrame:Show()
        self.activeContent = tab.contentFrame
    end
    local DB = ns:GetSubsystem("DB")
    if DB then DB.char.lastOptionsTab = id end
end

function Options:Toggle()
    self:Build()
    if self.frame:IsShown() then self.frame:Hide() else self.frame:Show() end
end

function Options:Show()
    self:Build()
    self.frame:Show()
end

-- Register a small proxy panel in Blizzard's Options > AddOns list. Our real
-- options live in the standalone EQOptionsFrame window, so this entry just
-- carries the name/version and a button that opens it (the modern Settings
-- canvas can't host our fixed-size, draggable window cleanly). Without this
-- the addon simply doesn't appear in that list. Settings.* exists on all
-- supported clients; the guard keeps us safe if Blizzard ever renames it.
function Options:RegisterBlizzardCategory()
    if self._blizzCategory then return end
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        return
    end

    local panel = CreateFrame("Frame")

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Everything Quests")
    title:SetTextColor(unpack(HEADER_RED))

    local ver = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    ver:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    ver:SetText("Version " .. (ns.VERSION or ""))
    ver:SetTextColor(unpack(YELLOW))

    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", ver, "BOTTOMLEFT", 0, -18)
    desc:SetWidth(560)
    desc:SetJustifyH("LEFT")
    desc:SetText("Everything Quests opens its full options in a dedicated window. "
        .. "Click the button below, or type |cffEBB706/eqs|r in chat.")

    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btn:SetSize(240, 26)
    btn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -18)
    btn:SetText("Open Everything Quests Options")
    btn:SetScript("OnClick", function()
        -- Get out of the Settings window first so our DIALOG-strata window
        -- isn't stacked behind it.
        if SettingsPanel and SettingsPanel.IsShown and SettingsPanel:IsShown() then
            HideUIPanel(SettingsPanel)
        end
        Options:Show()
    end)

    local category = Settings.RegisterCanvasLayoutCategory(panel, "Everything Quests")
    Settings.RegisterAddOnCategory(category)
    self._blizzCategory = category
end

function Options:OnEnable()
    self:RegisterBlizzardCategory()
end

-- Helper exposed to TabXxx files for consistent header style.
function Options:CreateSectionHeader(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetTextColor(unpack(HEADER_RED))
    fs:SetText(text)
    return fs
end

-- Helper for yellow-text buttons matching the screenshot.
function Options:CreateYellowButton(parent, label, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(160, 28)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.10, 0.10, 0.10, 0.9)
    local txt = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    txt:SetPoint("CENTER")
    txt:SetText(label)
    txt:SetTextColor(unpack(YELLOW))
    b.text = txt
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- White-text checkbox using Blizzard's UICheckButtonTemplate. The template
-- already provides the box artwork; we layer our own label so it matches the
-- rest of the options panel (white text, GameFontNormal). `getter`/`setter`
-- callbacks read/write the underlying setting; setter is called immediately
-- on click, so any side-effect (Tracker:Refresh, etc.) lives there.
function Options:CreateCheckbox(parent, label, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)

    local txt = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    txt:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    txt:SetText(label)
    txt:SetTextColor(1, 1, 1)
    cb.label = txt

    cb:SetChecked((getter and getter()) or false)
    cb:SetScript("OnClick", function(btn)
        if setter then setter(btn:GetChecked() and true or false) end
    end)
    return cb
end

-- Horizontal radio group: a row of buttons where the active option is filled
-- with EQ red (#6D0501) + white text, and inactive options are dark with
-- yellow (#EBB706) text. Picks up the suite brand language without needing
-- Blizzard's heavier UIDropDownMenu plumbing.
--
-- options: array of { value=string|number, label=string }
-- Setter is called on each click; visual state updates locally so callers
-- don't have to re-render the group.
function Options:CreateRadioGroup(parent, label, options, getter, setter, maxWidth, pad)
    local container = CreateFrame("Frame", nil, parent)

    local labelFS
    if label then
        labelFS = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        labelFS:SetPoint("TOPLEFT")
        labelFS:SetText(label)
        labelFS:SetTextColor(1, 1, 1)
    end

    local buttons = {}
    local function paint(active)
        for _, b in ipairs(buttons) do
            local isActive = (b.value == active)
            if isActive then
                b.bg:SetColorTexture(0.43, 0.02, 0.0, 1)         -- EQ red
                b.txt:SetTextColor(1, 1, 1, 1)
            else
                b.bg:SetColorTexture(0.10, 0.10, 0.10, 0.9)
                b.txt:SetTextColor(0.92, 0.72, 0.02, 1)          -- yellow
            end
        end
    end

    -- Lay buttons left-to-right. When maxWidth is given, wrap to a new row
    -- once the next button would overflow it — keeps a long option list (e.g.
    -- the tracker's 7 sort modes) from spilling into the adjacent column.
    local BTN_H, ROW_GAP, BTN_GAP = 24, 4, 4
    -- Horizontal text padding per button. Default 18; callers with a tight,
    -- many-option row (the tracker's 7 sort modes) can pass a smaller value so
    -- the row fits one line at wider stock fonts instead of orphaning the last
    -- button onto a second row.
    local PAD = pad or 18
    local rowAnchor  = labelFS or container
    local rowOffsetY = labelFS and -4 or 0
    local x, y, maxX = 0, 0, 0
    for _, opt in ipairs(options) do
        local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
        btn:SetHeight(BTN_H)
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        txt:SetPoint("CENTER")
        txt:SetText(opt.label)
        local w = math.max(40, txt:GetStringWidth() + PAD)
        btn:SetWidth(w)
        if maxWidth and x > 0 and (x + w) > maxWidth then   -- wrap to next row
            x, y = 0, y + BTN_H + ROW_GAP
        end
        btn:SetPoint("TOPLEFT", rowAnchor, labelFS and "BOTTOMLEFT" or "TOPLEFT", x, rowOffsetY - y)
        btn.bg, btn.txt, btn.value = bg, txt, opt.value
        btn:SetScript("OnClick", function(b)
            if setter then setter(b.value) end
            paint(b.value)
        end)
        x = x + w + BTN_GAP
        if x > maxX then maxX = x end
        buttons[#buttons + 1] = btn
    end

    paint(getter and getter())
    -- Keep the original single-row height (50); add one row's worth per wrap so
    -- anything anchored to the container's BOTTOMLEFT clears the last row.
    container:SetSize(maxWidth or maxX, 50 + y)
    return container
end

-- Dropdown: a button labeled with the current selection that opens a menu
-- of choices via MenuUtil.CreateContextMenu. options is an array of
-- { value=any, label=string }; getter returns the current value, setter is
-- called when the user picks a new value.
-- `options` may be either a static table { {value, label, ...}, ... } or a
-- function returning one. The function form is re-evaluated each time the
-- menu opens so callers like the profile picker can show newly created
-- entries without rebuilding the whole dropdown widget.
--
-- An optional `onItemRender(button, opt)` callback runs after each menu
-- entry is created — used by the font dropdown to render each font's name
-- in its own typeface so the user can preview before picking.
function Options:CreateDropdown(parent, label, options, getter, setter, onTest, onItemRender)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(220, 44)

    local function resolveOptions()
        return (type(options) == "function") and (options() or {}) or options
    end

    local labelFS = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelFS:SetPoint("TOPLEFT")
    labelFS:SetText(label)
    labelFS:SetTextColor(1, 1, 1)

    local speaker
    if onTest then
        speaker = CreateFrame("Button", nil, container)
        speaker:SetSize(20, 20)
        speaker:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", 0, -4)
        local sicon = speaker:CreateTexture(nil, "ARTWORK")
        sicon:SetAllPoints()
        sicon:SetTexture("Interface\\Common\\VoiceChat-Speaker")
        speaker:SetHighlightTexture("Interface\\Common\\VoiceChat-Speaker", "ADD")
        speaker:SetScript("OnClick", function()
            onTest(getter and getter())
        end)
    end

    local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
    btn:SetHeight(22)
    if speaker then
        btn:SetPoint("TOPLEFT", speaker, "TOPRIGHT", 4, 0)
    else
        btn:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", 0, -4)
    end
    btn:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -22)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.10, 0.10, 0.10, 0.95)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.text:SetPoint("LEFT", 6, 0)
    btn.text:SetTextColor(unpack(YELLOW))
    btn.arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.arrow:SetPoint("RIGHT", -6, 0)
    btn.arrow:SetText("v")
    btn.arrow:SetTextColor(unpack(YELLOW))

    local function syncLabel()
        local current = getter and getter()
        for _, opt in ipairs(resolveOptions()) do
            if opt.value == current then btn.text:SetText(opt.label); return end
        end
        btn.text:SetText(tostring(current or ""))
    end

    btn:SetScript("OnClick", function(b)
        if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
        MenuUtil.CreateContextMenu(b, function(_, root)
            for _, opt in ipairs(resolveOptions()) do
                local entry = root:CreateButton(opt.label, function()
                    if setter then setter(opt.value) end
                    syncLabel()
                end)
                if onItemRender and entry and entry.AddInitializer then
                    entry:AddInitializer(function(buttonFrame)
                        onItemRender(buttonFrame, opt)
                    end)
                end
            end
        end)
    end)

    syncLabel()
    container.button = btn
    container.sync   = syncLabel
    return container
end

-- Font-picking dropdown with per-entry preview. Each menu row renders its
-- label in the font that row would select, so the user sees what they're
-- choosing before they commit.
--
-- Built as a fully custom popup (not MenuUtil) because MenuUtil's entry
-- widget shape varies between WoW builds and reliably re-applying a
-- per-row font through it has been brittle. Owning the rows directly is
-- ~80 lines and just works.
function Options:CreateFontDropdown(parent, label, options, getter, setter)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(220, 44)

    local labelFS = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelFS:SetPoint("TOPLEFT")
    labelFS:SetText(label)
    labelFS:SetTextColor(1, 1, 1)

    local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
    btn:SetHeight(22)
    btn:SetPoint("TOPLEFT",  labelFS, "BOTTOMLEFT", 0, -4)
    btn:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -22)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.10, 0.10, 0.10, 0.95)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.text:SetPoint("LEFT",  6, 0)
    btn.text:SetPoint("RIGHT", -22, 0)
    btn.text:SetJustifyH("LEFT")
    btn.text:SetWordWrap(false)
    btn.text:SetTextColor(unpack(YELLOW))
    btn.arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.arrow:SetPoint("RIGHT", -6, 0)
    btn.arrow:SetText("v")
    btn.arrow:SetTextColor(unpack(YELLOW))

    -- Popup: scrollable list of font rows, parented to UIParent so it can
    -- float above the Options window without clipping inside the tab.
    local ROW_H, MAX_VISIBLE = 22, 10
    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:Hide()
    local pbg = popup:CreateTexture(nil, "BACKGROUND")
    pbg:SetAllPoints()
    pbg:SetColorTexture(0.04, 0.04, 0.04, 0.98)
    local border = popup:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.30, 0.30, 0.30, 1)

    local scroll = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -24, 4)
    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(1, 1)
    scroll:SetScrollChild(scrollChild)

    local rows = {}
    local function setCurrentLabel()
        local current = getter and getter()
        for _, opt in ipairs(options) do
            if opt.value == current then btn.text:SetText(opt.label); return end
        end
        btn.text:SetText(tostring(current or ""))
    end

    local function rebuildRows()
        local Media = ns:GetSubsystem("Media")
        for _, row in ipairs(rows) do row:Hide() end
        for i, opt in ipairs(options) do
            local row = rows[i]
            if not row then
                row = CreateFrame("Button", nil, scrollChild)
                row:SetHeight(ROW_H)
                local hl = row:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.10)
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row.text:SetPoint("LEFT",  6, 0)
                row.text:SetPoint("RIGHT", -6, 0)
                row.text:SetJustifyH("LEFT")
                row.text:SetWordWrap(false)
                rows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  scrollChild, "TOPLEFT",  0, -(i - 1) * ROW_H)
            row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -(i - 1) * ROW_H)
            row.text:SetText(opt.label)
            row.text:SetTextColor(unpack(YELLOW))
            local file = Media and Media.GetFontFile and Media:GetFontFile(opt.value)
            if file then
                local ok = pcall(row.text.SetFont, row.text, file, 13, "")
                if not ok then row.text:SetFont(STANDARD_TEXT_FONT, 13, "") end
            end
            row:SetScript("OnClick", function()
                if setter then setter(opt.value) end
                popup:Hide()
                setCurrentLabel()
            end)
            row:Show()
        end
        scrollChild:SetSize(math.max(1, scroll:GetWidth()), math.max(1, #options * ROW_H))
    end

    btn:SetScript("OnClick", function()
        if popup:IsShown() then popup:Hide(); return end
        popup:ClearAllPoints()
        popup:SetPoint("TOPLEFT",  btn, "BOTTOMLEFT",  0, -2)
        popup:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -2)
        local visible = math.min(#options, MAX_VISIBLE)
        popup:SetHeight(visible * ROW_H + 8)
        popup:Show()
        rebuildRows()
    end)

    -- Click-outside closes the popup. Hooked via a global on UIParent so
    -- we don't have to track which other frames the user might click.
    popup:SetScript("OnShow", function(self)
        self._closer = self._closer or CreateFrame("Button", nil, UIParent)
        self._closer:SetAllPoints(UIParent)
        self._closer:SetFrameStrata("FULLSCREEN")
        self._closer:RegisterForClicks("AnyDown")
        self._closer:SetScript("OnClick", function() self:Hide() end)
        self._closer:Show()
    end)
    popup:SetScript("OnHide", function(self)
        if self._closer then self._closer:Hide() end
    end)

    setCurrentLabel()
    container.button = btn
    container.sync   = setCurrentLabel
    return container
end

-- Slider: integer or float slider with a value label. min/max/step define the
-- range; getter/setter read and write the value.
function Options:CreateSlider(parent, label, min, max, step, getter, setter)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(220, 44)

    local labelFS = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelFS:SetPoint("TOPLEFT")
    labelFS:SetText(label)
    labelFS:SetTextColor(1, 1, 1)

    local valueFS = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueFS:SetPoint("TOPRIGHT")
    valueFS:SetTextColor(unpack(YELLOW))

    -- Pick a printf format that matches the step's precision. Without this
    -- the slider would render 0.95 as "0.94999998807907" because of binary
    -- float artifacts.
    local function chooseFormat(s)
        if not s or s >= 1 then return "%d" end
        local decimals = math.max(1, math.ceil(-math.log10(s)))
        return "%." .. decimals .. "f"
    end
    local valueFmt = chooseFormat(step)
    local function formatValue(v)
        return valueFmt:format(v)
    end

    local slider = CreateFrame("Slider", nil, container, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", 0, -8)
    slider:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -22)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step or 1)
    slider:SetObeyStepOnDrag(true)
    if slider.Low  then slider.Low:SetText("")  end
    if slider.High then slider.High:SetText("") end
    if slider.Text then slider.Text:SetText("") end

    slider:SetValue(getter and getter() or min)
    valueFS:SetText(formatValue(slider:GetValue()))

    slider:SetScript("OnValueChanged", function(_, v)
        local stepped = step and (math.floor((v - min) / step + 0.5) * step + min) or v
        valueFS:SetText(formatValue(stepped))
        if setter then setter(stepped) end
    end)

    container.slider = slider
    return container
end

-- Color picker: a label + swatch button. Click opens Blizzard's ColorPickerFrame.
-- getter/setter exchange { r, g, b, a } tables (a optional, defaults to 1).
function Options:CreateColorPicker(parent, label, getter, setter)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(220, 22)

    local labelFS = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelFS:SetPoint("LEFT")
    labelFS:SetText(label)
    labelFS:SetTextColor(1, 1, 1)

    local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
    btn:SetSize(44, 20)
    btn:SetPoint("LEFT", labelFS, "RIGHT", 8, 0)
    local border = btn:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.92, 0.72, 0.02, 1)         -- yellow #EBB706
    local underlay = btn:CreateTexture(nil, "BORDER")
    underlay:SetPoint("TOPLEFT", 2, -2)
    underlay:SetPoint("BOTTOMRIGHT", -2, 2)
    underlay:SetColorTexture(0, 0, 0, 1)                 -- opaque black so transparent picks read black, not yellow
    local swatch = btn:CreateTexture(nil, "ARTWORK")
    swatch:SetPoint("TOPLEFT", 2, -2)
    swatch:SetPoint("BOTTOMRIGHT", -2, 2)

    local function paint()
        local c = getter and getter() or { r = 1, g = 1, b = 1, a = 1 }
        swatch:SetColorTexture(c.r or 0, c.g or 0, c.b or 0, c.a or 1)
    end
    paint()

    btn:SetScript("OnClick", function()
        local c = getter and getter() or { r = 1, g = 1, b = 1, a = 1 }
        local function applyColor(restore)
            local r, g, b, a
            if restore then
                r, g, b, a = restore.r, restore.g, restore.b, restore.a
            elseif ColorPickerFrame and ColorPickerFrame.GetColorRGB then
                r, g, b = ColorPickerFrame:GetColorRGB()
                -- Modern ColorPickerFrame (10.0+) exposes alpha directly via
                -- GetColorAlpha (1 = opaque). OpacitySliderFrame was removed
                -- in 10.0 — without this the alpha read was always 1, so the
                -- fade slider never took effect live.
                if ColorPickerFrame.GetColorAlpha then
                    a = ColorPickerFrame:GetColorAlpha()
                elseif OpacitySliderFrame then
                    a = 1 - OpacitySliderFrame:GetValue()
                else
                    a = c.a or 1
                end
            else
                r, g, b, a = c.r, c.g, c.b, c.a
            end
            if setter then setter({ r = r, g = g, b = b, a = a }) end
            paint()
        end
        if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = c.r or 0, g = c.g or 0, b = c.b or 0,
                opacity = c.a or 1, hasOpacity = true,
                swatchFunc = function() applyColor() end,
                opacityFunc = function() applyColor() end,
                cancelFunc  = function(prev) applyColor(prev) end,
            })
        end
    end)

    container.button = btn
    container.label  = labelFS
    container.paint  = paint
    return container
end

-- Slash handler. Options:Toggle() is pcall-guarded so a failure surfaces a
-- one-line error in chat instead of silently doing nothing; success is
-- silent (the window appearing is the feedback).
local function eqSlashHandler(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "chain" then
        local CG = ns:GetSubsystem("ChainGuide"); if CG then CG:Toggle() end
        return
    elseif msg == "history" then
        local HF = ns:GetSubsystem("HistoryFrame")
        if HF and HF.Toggle then HF:Toggle() end
        return
    elseif msg == "session" then
        local Sess = ns:GetSubsystem("Session")
        if Sess and Sess.Print then Sess:Print() end
        return
    elseif msg == "whatsnew" or msg == "changes" then
        -- Re-open the "What's New" popup on demand (it otherwise auto-shows
        -- once per major release). Always shows, regardless of the one-shot
        -- seen flag, since the user explicitly asked for it.
        local WN = ns:GetSubsystem("WhatsNew")
        if WN and WN.Show then WN:Show() end
        return
    elseif msg:match("^discover") then
        local hint = msg:match("^discover%s+(.+)$")
        local QLS = ns:GetSubsystem("ChainGuideQuestLineSource")
        if QLS and QLS.PrintCurrentZone then QLS:PrintCurrentZone(hint) end
        return
    elseif msg == "wqdebug" then
        Options:DumpWorldQuestSources()
        return
    elseif msg == "scenario" then
        Options:DumpScenarioInfo()
        return
    elseif msg == "questobj" then
        Options:DumpQuestObjectives()
        return
    elseif msg == "autopopup" then
        Options:DumpAutoQuestPopups()
        return
    elseif msg == "dir" then
        Options:DumpDirections()
        return
    elseif msg:match("^profile") then
        -- /eqs profile [show|reset|mem on|mem off]
        local rest = msg:match("^profile%s*(.*)$") or ""
        local Profiler = ns:GetSubsystem("Profiler")
        if not Profiler then return end
        if rest == "" or rest == "show" then
            Profiler:Show()
        elseif rest == "reset" then
            Profiler:Reset()
            print("|cffEBB706EQ Profile|r reset")
        elseif rest:match("^memhog") then
            Profiler:ToggleMemHog()
            print("|cffEBB706EQ Profile|r memhog "
                  .. (Profiler.memhog and Profiler.memhog.active and "ON" or "OFF"))
        elseif rest:match("^mem%s+on") then
            Profiler:SetMemoryMode(true)
            print("|cffEBB706EQ Profile|r memory mode ON — collectgarbage forced at boundaries (expensive; toggle off when done)")
        elseif rest:match("^mem%s+off") then
            Profiler:SetMemoryMode(false)
            print("|cffEBB706EQ Profile|r memory mode OFF")
        elseif rest:match("^auto%s+on") then
            local wrapped, missing = Profiler:AutoInstrument(true)
            print(("|cffEBB706EQ Profile|r auto-instrument ON \194\183 wrapped %d hot path%s%s"):format(
                wrapped, wrapped == 1 and "" or "s",
                missing > 0 and (", " .. missing .. " missing (subsystem not loaded)") or ""))
            print("  Use /eqs profile show after playing for a few minutes; /eqs profile auto off to unwrap")
        elseif rest:match("^auto%s+off") then
            local n = Profiler:AutoInstrument(false)
            print(("|cffEBB706EQ Profile|r auto-instrument OFF \194\183 unwrapped %d method%s"):format(
                n, n == 1 and "" or "s"))
        elseif rest:match("^auto%s+list") or rest == "auto" then
            local list = Profiler:ListWrapped()
            if #list == 0 then
                print("|cffEBB706EQ Profile|r auto-instrument is OFF (nothing wrapped)")
            else
                print(("|cffEBB706EQ Profile|r currently wrapped (%d):"):format(#list))
                for _, k in ipairs(list) do print("  " .. k) end
            end
        else
            print("|cffEBB706EQ Profile|r usage: /eqs profile [show | reset | mem on | mem off | memhog | auto on | auto off | auto list]")
        end
        return
    end
    local ok, err = pcall(function() Options:Toggle() end)
    if not ok then
        print("|cffEBB706Everything Quests|r: couldn't open Options \226\128\148 " .. tostring(err))
    end
end

-- Slash commands. The short alias is "/eqs", NOT "/eq": IsSecureCmd("/EQ")
-- is true because "/eq" is Blizzard's built-in *secure* shorthand for
-- "/equip" (equip an item by name). WoW's chat parser dispatches secure
-- commands before it ever consults SlashCmdList, so a "/eq" handler is
-- unreachable, and overriding Blizzard's secure command would break
-- equipping items and risk taint. "/eqs" and the full "/everythingquests"
-- are not secure, so both route here through the normal slash path.
SLASH_EVERYTHINGQUESTS1 = "/eqs"
SLASH_EVERYTHINGQUESTS2 = "/everythingquests"
SlashCmdList["EVERYTHINGQUESTS"] = eqSlashHandler

-- /eqs scenario — print everything Blizzard tells us about the current
-- scenario/dungeon/raid. When the Tracker labels something as the
-- generic "Scenario", running this from inside the instance gives us
-- the scenarioType / textureKit / instanceType combo needed to add a
-- proper label in Modules/Tracker/Scenario.lua's categoryLabel().
function Options:DumpScenarioInfo()
    local function line(label, value) print(("|cffEBB706EQ Scenario|r %s: %s"):format(label, tostring(value))) end

    if C_Scenario and C_Scenario.GetInfo then
        local name, currentStage, numStages, _, _, _, _, _, _, scenarioType, _, textureKit = C_Scenario.GetInfo()
        line("scenarioName", name or "(nil)")
        line("scenarioType", scenarioType or "(nil)")
        line("textureKit",   textureKit or "(nil)")
        line("stage",        tostring(currentStage or "?") .. " / " .. tostring(numStages or "?"))
    else
        line("C_Scenario.GetInfo", "unavailable")
    end

    if C_Scenario and C_Scenario.GetStepInfo then
        local stepName = C_Scenario.GetStepInfo()
        line("stepName", stepName or "(nil)")
    end

    -- C_ScenarioInfo.GetScenarioInfo() returns a struct; its .name is a
    -- separate candidate for the specific instance/delve name and sometimes
    -- differs from C_Scenario.GetInfo's first return.
    if C_ScenarioInfo and C_ScenarioInfo.GetScenarioInfo then
        local si = C_ScenarioInfo.GetScenarioInfo()
        line("GetScenarioInfo.name", (si and si.name) or "(nil)")
    end

    if GetInstanceInfo then
        local instName, instType, diffID, diffName = GetInstanceInfo()
        line("instance name",  instName or "(nil)")
        line("instance type",  instType or "(nil)")
        line("difficulty",     tostring(diffName) .. " (id " .. tostring(diffID) .. ")")
    end

    -- Which field would Step 2's resolveName() pick as the two-tier name
    -- line? Hypothesis order: instance name -> GetScenarioInfo.name ->
    -- scenarioName. This line lets us confirm the choice live before wiring it.
    do
        local instName = GetInstanceInfo and select(1, GetInstanceInfo()) or nil
        local si = C_ScenarioInfo and C_ScenarioInfo.GetScenarioInfo and C_ScenarioInfo.GetScenarioInfo()
        local sName = C_Scenario and C_Scenario.GetInfo and select(1, C_Scenario.GetInfo()) or nil
        local proposed = (instName and instName ~= "" and instName)
                         or (si and si.name)
                         or sName
        line("<- proposed name line", proposed or "(none)")
    end

    if C_Map and C_Map.GetBestMapForUnit then
        local mapID = C_Map.GetBestMapForUnit("player")
        local info = mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        line("map", ((info and info.name) or "?") .. " (id " .. tostring(mapID) .. ")")
    end
end

-- /eqs questobj — for every watched quest, dumps what the objective APIs
-- return. The point is the empty case: some quests render with no sub-text
-- because C_QuestLog.GetQuestObjectives() is an empty table (e.g. "go talk to
-- X" quests). This surfaces the candidate fallback sources so we can see what
-- Blizzard/ElvUI show in their place (the user reports ElvUI shows "Quest
-- Discovered") and wire the matching text without guessing.
function Options:DumpQuestObjectives()
    local function p(s) print("|cffEBB706EQ QuestObj|r " .. s) end
    if not C_QuestLog then p("C_QuestLog unavailable"); return end

    local num     = (C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries()) or 0
    local savedID = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
    local getText = _G.GetQuestLogQuestText   -- selection-based global; guarded
    local shown   = 0

    for i = 1, num do
        local info = C_QuestLog.GetInfo and C_QuestLog.GetInfo(i)
        if info and not info.isHeader then
            local id      = info.questID
            local watched = C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(id) ~= nil
            if watched then
                local objs     = (C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id)) or {}
                local complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(id)
                local ready    = C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(id)
                p(("[%d] %s | obj=%d complete=%s ready=%s"):format(
                    id, info.title or "?", #objs, tostring(complete), tostring(ready)))
                for j = 1, #objs do
                    local o = objs[j]
                    p(("    obj%d type=%s finished=%s text=%q"):format(
                        j, tostring(o.type), tostring(o.finished), tostring(o.text)))
                end
                if #objs == 0 then
                    -- Candidate fallback sources for the empty case.
                    local compText = C_QuestLog.GetQuestLogCompletionText
                                     and C_QuestLog.GetQuestLogCompletionText(id)
                    p(("    completionText=%q"):format(tostring(compText)))
                    if getText and C_QuestLog.SetSelectedQuest then
                        C_QuestLog.SetSelectedQuest(id)
                        local _, objText = getText()
                        p(("    objectivesText=%q"):format(tostring(objText)))
                    end
                end
                shown = shown + 1
            end
        end
    end

    -- Restore the player's selected quest (we mutated it to read objectivesText).
    if savedID and savedID ~= 0 and C_QuestLog.SetSelectedQuest then
        C_QuestLog.SetSelectedQuest(savedID)
    end
    if shown == 0 then p("no watched quests found") end
end

-- /eqs dir — diagnoses "Get Directions". Prints every coordinate source the
-- Chain Guide waypoint resolver consults for the super-tracked (or first
-- watched) quest, each as map + normalized coords + straight-line yards from
-- the player, then the source Resolve() actually picks. Tells us at a glance
-- whether the waypoint lands wrong because the quest isn't seen as active, a
-- stale harvested giver coord is winning, or GetNextWaypoint itself points far.
function Options:DumpDirections()
    local function p(s) print("|cffEBB706EQ Dir|r " .. s) end
    if not C_Map then p("C_Map unavailable"); return end

    local pMap   = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pPos   = pMap and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(pMap, "player")
    local ppx, ppy
    if pPos then ppx, ppy = pPos:GetXY() end
    local pCont, pWorld
    if pPos and C_Map.GetWorldPosFromMapPos then
        pCont, pWorld = C_Map.GetWorldPosFromMapPos(pMap, pPos)
    end

    -- Straight-line yards from the player to a (mapID, x, y); nil when the
    -- target is on a different continent or world pos is unavailable.
    local function yards(mapID, x, y)
        if not (pWorld and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
        local c, w = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
        if not w or c ~= pCont then return nil end
        local wx, wy = w:GetXY()
        local px, py = pWorld:GetXY()
        local dx, dy = px - wx, py - wy
        return math.sqrt(dx * dx + dy * dy)
    end

    local function line(label, mapID, x, y)
        if not (mapID and x and y) then
            p(("  %-20s |cffff5555none|r"):format(label))
            return
        end
        local d = yards(mapID, x, y)
        p(("  %-20s map %d  %.1f, %.1f%s"):format(
            label, mapID, x * 100, y * 100,
            d and ("  |cff88ff88%.0f yds|r"):format(d) or "  |cff888888(off-continent)|r"))
    end

    -- Diagnose the super-tracked quest first, else the first watched quest.
    local questID = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
                    and C_SuperTrack.GetSuperTrackedQuestID()
    if (not questID or questID == 0) and C_QuestLog and C_QuestLog.GetQuestIDForQuestWatchIndex
       and C_QuestLog.GetNumQuestWatches and C_QuestLog.GetNumQuestWatches() > 0 then
        questID = C_QuestLog.GetQuestIDForQuestWatchIndex(1)
    end
    if not questID or questID == 0 then
        p("no super-tracked or watched quest — super-track the quest you're testing, then re-run")
        return
    end

    local title = (ns.Util and ns.Util.QuestTitle and ns.Util.QuestTitle(questID, true)) or tostring(questID)
    p(("|cffffffff%s|r (id %d)"):format(title, questID))
    p(("  %-20s map %s  %.1f, %.1f"):format("player at", tostring(pMap), (ppx or 0) * 100, (ppy or 0) * 100))

    local logIdx = C_QuestLog and C_QuestLog.GetLogIndexForQuestID
                   and C_QuestLog.GetLogIndexForQuestID(questID)
    p("  active in log:       " .. (logIdx and "YES (live objective wins)" or "no (giver coords only)"))

    if C_QuestLog and C_QuestLog.GetNextWaypoint then
        line("GetNextWaypoint", C_QuestLog.GetNextWaypoint(questID))
    end
    if pMap and C_QuestLog and C_QuestLog.GetNextWaypointForMap then
        local fx, fy = C_QuestLog.GetNextWaypointForMap(questID, pMap)
        line("NextWaypointForMap", pMap, fx, fy)
    end

    local st = ns.CHAINGUIDE_QUEST_COORDS and ns.CHAINGUIDE_QUEST_COORDS[questID]
    line("bundled coords", st and st.m, st and st.x, st and st.y)

    local DB = ns:GetSubsystem("DB")
    local ce = DB and DB.chainCache and DB.chainCache.questCoords and DB.chainCache.questCoords[questID]
    line("harvested cache", ce and ce.m, ce and ce.x, ce and ce.y)

    -- Turn-in probes. When GetNextWaypoint is empty (a complete quest) these
    -- are the candidate sources for a hand-in coordinate we could feed TomTom.
    local complete = C_QuestLog and C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID)
    local ready    = C_QuestLog and C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(questID)
    p(("  state:               complete=%s readyForTurnIn=%s"):format(tostring(complete), tostring(ready)))

    local poiFn = _G["QuestPOIGetIconInfo"]   -- legacy global; string index so the
    if poiFn then                             -- linter doesn't flag a maybe-absent field
        local _, px, py = poiFn(questID)
        line("QuestPOIGetIconInfo", px and pMap, px, py)   -- posX/posY are on the current map
    else
        p("  QuestPOIGetIconInfo  |cff888888(API absent)|r")
    end

    if C_QuestLog and C_QuestLog.GetQuestsOnMap and pMap then
        local hit
        for _, e in ipairs(C_QuestLog.GetQuestsOnMap(pMap) or {}) do
            if e.questID == questID then hit = e; break end
        end
        if hit then line("GetQuestsOnMap", pMap, hit.x, hit.y)
        else p("  GetQuestsOnMap       |cff888888(quest not listed on this map)|r") end
    else
        p("  GetQuestsOnMap       |cff888888(API absent)|r")
    end

    local W = ns:GetSubsystem("ChainGuideWaypoint")
    if logIdx then
        p("  => WINNER:           super-track the quest -> Blizzard's live objective / turn-in POI"
          .. (TomTom and " (+ TomTom pin at the live objective, or turn-in via GetQuestsOnMap)" or ""))
    elseif W and W.Resolve then
        line("=> WINNER", W:Resolve(questID))
    end
end

-- /eqs autopopup — confirms the auto-quest-popup API surface ("Quest
-- Discovered!" / "Quest Complete!" boxes) before we build the tracker module
-- for it. Midnight relocates engine globals into C_ namespaces, so this checks
-- which functions actually exist in this client and what GetAutoQuestPopUp
-- returns (questID + popUpType) so the module is built on the real surface.
function Options:DumpAutoQuestPopups()
    local function p(s) print("|cffEBB706EQ AutoPopup|r " .. s) end

    -- Function-surface probe: print which candidate APIs exist. _G lookups so
    -- a missing/renamed global is reported, not a Lua error.
    local function has(name) return _G[name] and "yes" or "no" end
    p(("API: GetNumAutoQuestPopUps=%s GetAutoQuestPopUp=%s RemoveAutoQuestPopUp=%s"):format(
        has("GetNumAutoQuestPopUps"), has("GetAutoQuestPopUp"), has("RemoveAutoQuestPopUp")))
    p(("API: ShowQuestOffer=%s ShowQuestComplete=%s"):format(
        has("ShowQuestOffer"), has("ShowQuestComplete")))
    p(("API (C_): C_QuestLog.GetNumAutoQuestPopUps=%s"):format(
        (C_QuestLog and C_QuestLog.GetNumAutoQuestPopUps) and "yes" or "no"))

    local getNum = _G.GetNumAutoQuestPopUps
                   or (C_QuestLog and C_QuestLog.GetNumAutoQuestPopUps)
    local getPop = _G.GetAutoQuestPopUp
                   or (C_QuestLog and C_QuestLog.GetAutoQuestPopUp)
    if not (getNum and getPop) then
        p("no usable GetNumAutoQuestPopUps/GetAutoQuestPopUp — engine API moved or unavailable")
        return
    end

    local n = getNum() or 0
    p(("active popups: %d"):format(n))
    for i = 1, n do
        local questID, popUpType = getPop(i)
        local title = questID and (
            (C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID))
            or (QuestUtils_GetQuestName and QuestUtils_GetQuestName(questID)))
        p(("  [%d] questID=%s type=%q title=%q"):format(
            i, tostring(questID), tostring(popUpType), tostring(title or "?")))
    end
    if n == 0 then
        p("none right now — run this while a 'Quest Discovered!'/'Quest Complete!' box is up")
    end
end

-- /eqs wqdebug — surfaces every data source the World Quests tracker
-- section consults, so we can tell which API a missing quest *is* in
-- (and route the new bug fix at it).
function Options:DumpWorldQuestSources()
    local function info(line) print("|cffEBB706EQ WQ:|r " .. line) end
    local function quest(qid, suffix)
        local title = (C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID
                       and C_TaskQuest.GetQuestInfoByQuestID(qid))
                      or (C_QuestLog and C_QuestLog.GetTitleForQuestID
                          and C_QuestLog.GetTitleForQuestID(qid))
                      or "?"
        return ("    [%d] %s%s"):format(qid, title, suffix or "")
    end

    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local mapInfo = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    info(("player map: %s (id %s)"):format(mapInfo and mapInfo.name or "?", tostring(mapID)))

    -- 1. World-quest watch list (manual + Blizzard auto-watches).
    if C_QuestLog and C_QuestLog.GetNumWorldQuestWatches then
        local n = C_QuestLog.GetNumWorldQuestWatches() or 0
        info(("GetNumWorldQuestWatches: %d"):format(n))
        for i = 1, n do
            local qid = C_QuestLog.GetQuestIDForWorldQuestWatchIndex(i)
            if qid then print(quest(qid)) end
        end
    end

    -- 2. WatchPersist's combined view (db + runtime).
    local Watch = ns:GetSubsystem("WQWatchPersist")
    if Watch and Watch.GetTrackedQuests then
        local list = Watch:GetTrackedQuests() or {}
        info(("WQWatchPersist:GetTrackedQuests: %d"):format(#list))
        for _, qid in ipairs(list) do print(quest(qid)) end
    end

    -- 3. C_TaskQuest map query for current + parent maps. The function was
    -- renamed from GetQuestsForPlayerByMapID → GetQuestsOnMap; try the new
    -- name first and fall back. The field on the returned struct switched
    -- from questId to questID at the same time, so accept either.
    local taskFn = C_TaskQuest and (C_TaskQuest.GetQuestsOnMap or C_TaskQuest.GetQuestsForPlayerByMapID)
    info(("TaskQuest API: %s"):format(
        (C_TaskQuest and C_TaskQuest.GetQuestsOnMap and "GetQuestsOnMap")
        or (C_TaskQuest and C_TaskQuest.GetQuestsForPlayerByMapID and "GetQuestsForPlayerByMapID (deprecated)")
        or "none available"))
    if taskFn and mapID then
        local m, depth = mapID, 0
        while m and depth < 5 do
            local list = taskFn(m) or {}
            local mi = C_Map.GetMapInfo and C_Map.GetMapInfo(m)
            info(("TaskQuest@map %d (%s): %d entries"):format(m, mi and mi.name or "?", #list))
            for i = 1, #list do
                local q = list[i]
                local qid = q and (q.questId or q.questID)
                if qid then
                    print(quest(qid, q.inProgress and "  |cff44ff44(inProgress)|r" or "  |cff666666(idle)|r"))
                    -- For inProgress quests, surface what GetQuestObjectives
                    -- actually returns right now. An empty list means the
                    -- quest's data hasn't loaded yet — the tracker won't be
                    -- able to show objectives until QUEST_DATA_LOAD_RESULT
                    -- fires and we re-render.
                    if q.inProgress and C_QuestLog and C_QuestLog.GetQuestObjectives then
                        local objs = C_QuestLog.GetQuestObjectives(qid) or {}
                        if #objs == 0 then
                            print("        |cff999999(no objectives loaded yet)|r")
                        else
                            for k = 1, #objs do
                                local o = objs[k]
                                print(("        - %s%s"):format(
                                    o.text or "?",
                                    o.finished and "  |cff44ff44[done]|r" or ""))
                            end
                        end
                    end
                end
            end
            m = mi and mi.parentMapID
            depth = depth + 1
        end
    end

    -- 4. Player quest log: task / bounty / world-quest flagged entries.
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        local n = C_QuestLog.GetNumQuestLogEntries() or 0
        info(("QuestLog entries: %d"):format(n))
        for i = 1, n do
            local qi = C_QuestLog.GetInfo(i)
            if qi and qi.questID and not qi.isHeader and not qi.isHidden then
                local flags = {}
                if qi.isTask    then flags[#flags + 1] = "task"    end
                if qi.isBounty  then flags[#flags + 1] = "bounty"  end
                if qi.isOnMap   then flags[#flags + 1] = "onMap"   end
                if QuestUtils_IsQuestWorldQuest and QuestUtils_IsQuestWorldQuest(qi.questID) then
                    flags[#flags + 1] = "wq"
                end
                if C_QuestLog.GetQuestWatchType
                   and C_QuestLog.GetQuestWatchType(qi.questID) then
                    flags[#flags + 1] = "watched"
                end
                if #flags > 0 then
                    print(("    [%d] %s  |cff5c9eff{%s}|r"):format(
                        qi.questID, qi.title or "?", table.concat(flags, ",")))
                end
            end
        end
    end

    -- 5. Threat / on-map quests via dedicated helpers.
    if C_QuestLog and C_QuestLog.GetActiveThreatMaps then
        local maps = C_QuestLog.GetActiveThreatMaps() or {}
        info(("GetActiveThreatMaps: %d"):format(#maps))
        for _, m in ipairs(maps) do print("    map " .. tostring(m)) end
    end
end
