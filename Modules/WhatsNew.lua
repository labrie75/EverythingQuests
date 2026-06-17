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
-- 1.20.0: Chain Guide overhaul Phase 2 — every Midnight quest chain (all zones
-- and the campaign) now renders as a real branching graph, plus a redesigned,
-- resizable, drag-to-pan window with a collapsible side list and compact cards.
-- Phase 2 of 3 complete; Phase 3 (map integration) is next. Recaps the plan and
-- the cumulative "shipped so far / this update" status (see the release-comms
-- strategy). Bumping the version re-shows the popup once to everyone. Bump this
-- constant + rewrite POPUP_BODY for the next release and a fresh popup shows once
-- more. Reopen anytime with /eqs whatsnew.
local FEATURE_POPUP_VERSION = "1.20.0"
local POPUP_TITLE           = "What's New in Everything Quests v1.20.0"

local POPUP_BODY = [[
|cffEBB706The Chain Guide overhaul — Phase 2 is here|r
This is a big one. We're rebuilding the Chain Guide in three phases:
|cffffffff1.|r Make it actionable — tell you what to do next  |cff999999(done)|r
|cffffffff2.|r A real branching graph you can drag and explore  |cff999999(this update)|r
|cffffffff3.|r Map integration — quest-giver pins and auto-advancing waypoints  |cff999999(coming soon)|r

|cffEBB706Every chain is now a real map|r
Until now a quest chain was drawn as a flat top-to-bottom list. As of this update, |cffffffffevery quest chain in Midnight|r — all of Eversong Woods, Zul'Aman, Harandar, Voidstorm, Arator, and the full campaign — draws as a true branching graph. You can finally see which quests unlock which, where a chain splits into parallel paths, and where those paths rejoin.

|cffEBB706A redesigned window|r
The Chain Guide window is now |cffffffffresizable|r — drag the bottom-right corner to make it as large as you like, and your size is remembered between sessions. |cffffffffDrag anywhere|r on the graph to pan around the bigger chains. The new |cffffffff<<|r button collapses the side list so the graph fills the whole window, and quest cards are more compact so you see more of a chain at a glance.

|cffEBB706What's shipped so far|r
|cffffffffPhase 1|r (last update): your next step highlighted with a Continue button, ON QUEST tags, rich hover tooltips, and search by name or ID.
|cffffffffPhase 2|r (this update): full branching graphs for every chain, plus the redesigned, resizable, drag-to-pan window.
|cffffffffPhase 3|r (next): quest-giver pins on the world map and waypoints that advance as you complete each step.

|cffEBB706A couple of fixes too|r
Scenario and dungeon titles are now centered in their banner, and opening the options from the Chain Guide no longer leaves the two windows overlapping.

|cffEBB706Thanks for your patience|r
These updates have come quickly while the overhaul is underway, and I really appreciate you sticking with it — Phase 3 will round it out. Translations of the new Chain Guide text will follow once all three phases are complete.

|cffEBB706Found a problem? Let me know|r
If anything looks off, please tell me on |cffffffffDiscord|r (button below) or in the |cffffffffCurseForge comments|r — your reports are what make this better.

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
