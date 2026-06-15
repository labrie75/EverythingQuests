-- Modules/WhatsNew.lua
-- One-time "What's New" popup shown to every player on first login after a
-- major release. The popup is account-wide (single dismiss covers every
-- character) and version-gated against FEATURE_POPUP_VERSION — bump that
-- constant + rewrite POPUP_BODY for the next big release and a fresh
-- popup will show one more time. Patch releases that keep the same
-- FEATURE_POPUP_VERSION stay silent.

local _, ns = ...
local L = ns.L

local WN = ns:RegisterSubsystem("WhatsNew", {})

-- ─── Edit these two values together when drafting a new release popup ─
-- 1.19.0: start of the multi-phase Chain Guide overhaul — Phase 1 (next-step
-- guidance + Continue button, ON QUEST tags, rich hover tooltips, name search)
-- plus Russian (ruRU) + updated French. Sets expectations for the frequent
-- updates to come and recaps the plan (see the release-comms strategy).
-- Bumping the version re-shows the popup once to everyone. Bump this constant +
-- rewrite POPUP_BODY for the next release and a fresh popup shows once more.
-- Reopen anytime with /eqs whatsnew.
local FEATURE_POPUP_VERSION = "1.19.0"
local POPUP_TITLE           = "What's New in Everything Quests v1.19.0"

local POPUP_BODY = [[
|cffEBB706We're rebuilding the Chain Guide|r
Over the next few updates we're overhauling the Chain Guide in three phases:
|cffffffff1.|r Make it actionable — tell you what to do next  |cff999999(this update)|r
|cffffffff2.|r A real branching graph you can drag and explore
|cffffffff3.|r Map integration — quest-giver pins and auto-advancing waypoints

Because of that, updates will land more often than usual for a little while. Sorry in advance for the extra What's New popups — each one will recap what's already shipped, so it's easy to catch up if you miss one.

|cffEBB706Phase 1: the guide now guides you|r
Open any chain and it highlights your |cffffffffnext step|r with a gold border and a |cffffffffContinue|r button that sets your course straight to it. Quests already in your log are tagged |cff4db8ffON QUEST|r, and opening a chain scrolls to where you are.

|cffEBB706Richer quest info, no clicking|r
Hover any quest in a chain to see its level, objectives, and rewards — including whether a piece of reward gear is an upgrade over what you're wearing. Each quest also shows its level and ID, and a quest that's ready to turn in is highlighted.

|cffEBB706Search by name or ID|r
The Chain Guide's find box now accepts a quest |cffffffffname|r as well as an ID — type either and it jumps to the chain that contains it.

|cffEBB706Also in this update|r
Everything Quests is now available in |cffffffffRussian|r, with updated French. (Translations for the new Chain Guide text will follow once the overhaul is finished.)

|cffEBB706Thanks for your patience|r
Join our Discord with the button below to follow along, suggest features, or report anything that looks off.

|cffEBB706Want to see this again?|r Type |cffffffff/eqs whatsnew|r anytime to reopen this summary.
]]
-- ──────────────────────────────────────────────────────────────────────

local YELLOW     = ns.Util.color.buttonYellow   -- #EBB706
local HEADER_RED = ns.Util.color.brandRed        -- #6D0501 (was drifted to {0.42,0.02,0.02})
local MUTED      = ns.Util.color.muted

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
    f.openBtn.text:SetText(L["Open Options"])
    f.openBtn.text:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
    f.openBtn:SetScript("OnClick", function()
        dismiss()
        local O = ns:GetSubsystem("Options")
        if O and O.Show then O:Show() end
    end)

    f.gotBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    f.gotBtn:SetSize(120, 28)
    f.gotBtn:SetPoint("BOTTOMRIGHT", -16, 12)
    local gotBg = f.gotBtn:CreateTexture(nil, "BACKGROUND")
    gotBg:SetAllPoints()
    gotBg:SetColorTexture(HEADER_RED[1], HEADER_RED[2], HEADER_RED[3], 0.95)
    f.gotBtn.text = f.gotBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.gotBtn.text:SetPoint("CENTER")
    f.gotBtn.text:SetText(L["Got it"])
    f.gotBtn.text:SetTextColor(1, 1, 1)
    f.gotBtn:SetScript("OnClick", dismiss)

    -- "Join our Discord!" between the two buttons — same look as the Options
    -- title-bar link (logo chip + yellow text). Does NOT dismiss/mark-seen,
    -- so the user can copy the invite and keep reading. Opens the same
    -- copyable invite popup (ns:ShowDiscord).
    f.discordBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    f.discordBtn:SetHeight(28)
    f.discordBtn:SetPoint("BOTTOM", 0, 12)
    local dBg = f.discordBtn:CreateTexture(nil, "BACKGROUND")
    dBg:SetAllPoints()
    dBg:SetColorTexture(0.10, 0.10, 0.10, 0.95)
    f.discordBtn.icon = f.discordBtn:CreateTexture(nil, "OVERLAY")
    f.discordBtn.icon:SetSize(16, 16)
    f.discordBtn.icon:SetPoint("LEFT", 10, 0)
    f.discordBtn.icon:SetTexture("Interface\\AddOns\\EverythingQuests\\Media\\Textures\\discord.tga")
    f.discordBtn.text = f.discordBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.discordBtn.text:SetPoint("LEFT", f.discordBtn.icon, "RIGHT", 6, 0)
    f.discordBtn.text:SetText(L["Join our Discord!"])
    f.discordBtn.text:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
    f.discordBtn:SetWidth(10 + 16 + 6 + f.discordBtn.text:GetStringWidth() + 12)
    f.discordBtn:SetScript("OnClick", function() ns:ShowDiscord() end)

    -- Standard X close in the corner. Same dismiss path (marks seen too)
    -- so the user can't bypass the one-shot flag by clicking the X.
    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", -4, -4)
    f.close:SetScript("OnClick", dismiss)

    -- Subtle hint that this popup is one-shot, so the user isn't worried
    -- it'll start nagging on every login.
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("BOTTOM", 0, 44)
    f.hint:SetText(L["(This message shows once and won't appear again.)"])
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
