-- Modules/WhatsNew.lua
-- One-time "What's New" popup shown to every player on first login after a
-- major release. The popup is account-wide (single dismiss covers every
-- character) and version-gated against FEATURE_POPUP_VERSION — bump that
-- constant + rewrite POPUP_BODY for the next big release and a fresh
-- popup will show one more time. Patch releases that keep the same
-- FEATURE_POPUP_VERSION stay silent.

local _, ns = ...

local WN = ns:RegisterSubsystem("WhatsNew", {})

-- ─── Edit these two values together when drafting a new release popup ─
local FEATURE_POPUP_VERSION = "1.4.0"
local POPUP_TITLE           = "What's New in Everything Quests v1.4.0"

local POPUP_BODY = [[
|cffEBB706Quest History|r |cffaaaaaa(new feature)|r
A full account-wide quest log going back to whenever you installed EQ, plus a one-time backfill of every quest the game already knows you've completed. Open with |cffEBB706/eqs history|r or via the new |cffffffffHistory|r tab in Options. Five tabs:
    - |cffffffffQuests|r — search and filter by character, date, or type
    - |cffffffffStreak|r — your daily quest streak (current and best)
    - |cffffffffChain Timeline|r — every chain you've made progress in, with per-quest dates
    - |cffffffffActivity|r — 13-week heatmap of your turn-ins
    - |cffffffffTotals|r — gold and XP earned per character

|cffEBB706Chain Guide cross-link|r
Quests you've already completed now show a completion date in the Chain Guide tooltips.

|cffEBB706"Keep focused quest after relog"|r |cffaaaaaa(new option, General tab)|r
OFF by default. When OFF, EQ clears the leftover super-tracked-quest arrow at login so you don't log in to a stale waypoint (or TomTom marker).

|cffEBB706Smarter Scenario labeling|r
The Scenario section header now identifies Follower Dungeons, regular Dungeons, Raids, Battlegrounds, etc. instead of always saying "Scenario".

|cffEBB706Polish|r
    - Quest History Totals tab shows coin icons properly and fits on screen
    - Chain Timeline rows show a green checkmark for fully-completed chains
    - History window pops above the Options window instead of behind it
    - Export any History view to your clipboard (Export button, top right)
    - Right-click any History Quests row to open it in the Chain Guide
]]
-- ──────────────────────────────────────────────────────────────────────

local YELLOW     = { 0.92, 0.72, 0.02 }
local HEADER_RED = { 0.42, 0.02, 0.02 }
local MUTED      = { 0.70, 0.70, 0.70 }

local function alreadySeen()
    return ns.db and ns.db.global and ns.db.global.whatsNewSeen == FEATURE_POPUP_VERSION
end

local function markSeen()
    if ns.db and ns.db.global then
        ns.db.global.whatsNewSeen = FEATURE_POPUP_VERSION
    end
end

function WN:Build()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "EQWhatsNewFrame", UIParent, "BackdropTemplate")
    f:SetSize(560, 480)
    f:SetPoint("CENTER")
    -- Above the Options window's DIALOG strata so the popup isn't hidden
    -- if the player opens Options before reading it.
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
    f:SetBackdropColor(0.02, 0.02, 0.02, 0.97)
    f:SetBackdropBorderColor(HEADER_RED[1], HEADER_RED[2], HEADER_RED[3], 1)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 16, -14)
    f.title:SetText(POPUP_TITLE)
    f.title:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])

    -- Body in a ScrollFrame so a future longer release note still fits.
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     14, -44)
    scroll:SetPoint("BOTTOMRIGHT", -34, 50)

    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(scroll:GetWidth(), 1)
    scroll:SetScrollChild(body)

    f.body = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.body:SetPoint("TOPLEFT",  body, "TOPLEFT",  0, 0)
    f.body:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
    f.body:SetJustifyH("LEFT")
    f.body:SetJustifyV("TOP")
    f.body:SetSpacing(3)
    f.body:SetText(POPUP_BODY)
    body:SetHeight(f.body:GetStringHeight() + 12)

    -- Buttons: "Open Quest History" + "Got it". Either button dismisses the
    -- popup AND marks it seen, so the user can't accidentally leave the
    -- "seen" state unset by closing through one of the two affordances.
    local function dismiss()
        markSeen()
        f:Hide()
    end

    f.openBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    f.openBtn:SetSize(180, 28)
    f.openBtn:SetPoint("BOTTOMLEFT", 16, 12)
    local openBg = f.openBtn:CreateTexture(nil, "BACKGROUND")
    openBg:SetAllPoints()
    openBg:SetColorTexture(0.10, 0.10, 0.10, 0.95)
    f.openBtn.text = f.openBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.openBtn.text:SetPoint("CENTER")
    f.openBtn.text:SetText("Open Quest History")
    f.openBtn.text:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
    f.openBtn:SetScript("OnClick", function()
        dismiss()
        local HF = ns:GetSubsystem("HistoryFrame")
        if HF and HF.Open then HF:Open() end
    end)

    f.gotBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    f.gotBtn:SetSize(120, 28)
    f.gotBtn:SetPoint("BOTTOMRIGHT", -16, 12)
    local gotBg = f.gotBtn:CreateTexture(nil, "BACKGROUND")
    gotBg:SetAllPoints()
    gotBg:SetColorTexture(HEADER_RED[1], HEADER_RED[2], HEADER_RED[3], 0.95)
    f.gotBtn.text = f.gotBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.gotBtn.text:SetPoint("CENTER")
    f.gotBtn.text:SetText("Got it")
    f.gotBtn.text:SetTextColor(1, 1, 1)
    f.gotBtn:SetScript("OnClick", dismiss)

    -- Standard X close in the corner. Same dismiss path (marks seen too)
    -- so the user can't bypass the one-shot flag by clicking the X.
    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", -4, -4)
    f.close:SetScript("OnClick", dismiss)

    -- Subtle hint that this popup is one-shot, so the user isn't worried
    -- it'll start nagging on every login.
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("BOTTOM", 0, 44)
    f.hint:SetText("(This message shows once and won't appear again.)")
    f.hint:SetTextColor(MUTED[1], MUTED[2], MUTED[3])

    self.frame = f
    return f
end

function WN:Show()
    self:Build()
    self.frame:Show()
end

function WN:OnEnable()
    if alreadySeen() then return end
    -- Small delay so the popup doesn't appear in the middle of WoW's
    -- noisy login sequence (addon-loaded toasts, etc.).
    C_Timer.After(2, function()
        if alreadySeen() then return end                                     -- defensive against race with another login event
        self:Show()
    end)
end
