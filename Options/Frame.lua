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

local TAB_BG_ACTIVE   = { 0.43, 0.02, 0.00, 1.00 }
local TAB_BG_INACTIVE = { 0.10, 0.10, 0.10, 0.85 }
local FRAME_BG        = { 0.00, 0.00, 0.00, 0.95 }
local HEADER_RED      = { 0.43, 0.02, 0.00 }
local YELLOW          = { 0.92, 0.72, 0.02 }
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
    f:SetSize(900, 600)
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
    bg:SetColorTexture(unpack(FRAME_BG))

    -- Title
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -14)
    f.title:SetText("Everything Quests")
    f.title:SetTextColor(unpack(HEADER_RED))

    -- Version label
    f.version = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.version:SetPoint("TOPRIGHT", -34, -14)
    f.version:SetText("v" .. (ns.VERSION or "1.0.0"))
    f.version:SetTextColor(unpack(YELLOW))

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
function Options:CreateRadioGroup(parent, label, options, getter, setter)
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

    local x, rowAnchor = 0, labelFS or container
    local rowOffsetY = labelFS and -4 or 0
    for _, opt in ipairs(options) do
        local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
        btn:SetHeight(24)
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        txt:SetPoint("CENTER")
        txt:SetText(opt.label)
        btn:SetWidth(math.max(40, txt:GetStringWidth() + 18))
        btn:SetPoint("TOPLEFT", rowAnchor, labelFS and "BOTTOMLEFT" or "TOPLEFT", x, rowOffsetY)
        btn.bg, btn.txt, btn.value = bg, txt, opt.value
        btn:SetScript("OnClick", function(b)
            if setter then setter(b.value) end
            paint(b.value)
        end)
        x = x + btn:GetWidth() + 4
        buttons[#buttons + 1] = btn
    end

    paint(getter and getter())
    container:SetSize(x, 50)
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
            if file then row.text:SetFont(file, 13, "") end
            row:SetScript("OnClick", function()
                if setter then setter(opt.value) end
                popup:Hide()
                setCurrentLabel()
            end)
            row:Show()
        end
        scrollChild:SetSize(1, math.max(1, #options * ROW_H))
    end

    btn:SetScript("OnClick", function()
        if popup:IsShown() then popup:Hide(); return end
        rebuildRows()
        popup:ClearAllPoints()
        popup:SetPoint("TOPLEFT",  btn, "BOTTOMLEFT",  0, -2)
        popup:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -2)
        local visible = math.min(#options, MAX_VISIBLE)
        popup:SetHeight(visible * ROW_H + 8)
        popup:Show()
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
                a = 1 - (OpacitySliderFrame and OpacitySliderFrame:GetValue() or 0)
            else
                r, g, b, a = c.r, c.g, c.b, c.a
            end
            if setter then setter({ r = r, g = g, b = b, a = a }) end
            paint()
        end
        if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = c.r or 0, g = c.g or 0, b = c.b or 0,
                opacity = 1 - (c.a or 1), hasOpacity = true,
                swatchFunc = function() applyColor() end,
                opacityFunc = function() applyColor() end,
                cancelFunc  = function(prev) applyColor(prev) end,
            })
        end
    end)

    container.button = btn
    container.paint  = paint
    return container
end

-- Slash to open
SLASH_EQ1 = "/eq"
SLASH_EQ2 = "/everythingquests"
SlashCmdList["EQ"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "chain" then
        local CG = ns:GetSubsystem("ChainGuide"); if CG then CG:Toggle() end
    elseif msg:match("^discover") then
        local hint = msg:match("^discover%s+(.+)$")
        local QLS = ns:GetSubsystem("ChainGuideQuestLineSource")
        if QLS and QLS.PrintCurrentZone then QLS:PrintCurrentZone(hint) end
    elseif msg == "wqdebug" then
        Options:DumpWorldQuestSources()
    else
        Options:Toggle()
    end
end

-- /eq wqdebug — surfaces every data source the World Quests tracker
-- section consults, so we can tell which API a missing quest *is* in
-- (and route the new bug fix at it).
function Options:DumpWorldQuestSources()
    local function info(line) print("|cffEBB706EQL WQ:|r " .. line) end
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
