local _, ns = ...
local L = ns.L

local WN = ns:RegisterSubsystem("WhatsNew", {})

local FEATURE_POPUP_VERSION = "1.28.0"
local POPUP_TITLE           = "What's New in Everything Quests v1.28.0"

local POPUP_BODY = [[
|cffEBB706Missed the last update?|r
If you skipped a version, every release's full notes live right inside the addon — type |cffffffff/eqs|r, open the |cffffffffAbout|r tab, and read the changelog there. This popup only covers the latest release.

|cffEBB706New look: a fresh icon|r
Everything Quests has a new icon — the minimap button, Titan Panel, and AddOns list now show a gold crest in place of the old book. Same addon, new badge.

|cffEBB706New chain: The Sunstrider Omnium|r
The Chain Guide now includes |cffffffffThe Sunstrider Omnium|r — the Magisters' Terrace questline that unlocks the Omnium Folio — as its own zone, with the full chain mapped out like the rest of the Midnight content.

|cffEBB706Map pins for more chains|r
Quest-giver map pins now show for the |cffffffffSunstrider Omnium|r and |cffffffffVoid Acropolis|r chains, so you can find each step on the world map. Void Acropolis had none before.

|cffEBB706Fixed: tracker sections crowding together|r
When you had a lot of quests, achievements, and world quests tracked at once, a section's header could appear with its contents cut off. The quest list now keeps its sections intact, and the World Quests area gives up space and scrolls instead.

|cffEBB706Fixed: "Ritual Site" label|r
Ritual Sites like |cffffffffBroken Throne|r now read |cffffffffRitual Site|r in the tracker instead of |cffffffffDelves|r. They run on the delve system under the hood, so the game reported them as delves — the tracker now matches Blizzard's own wording.

|cffEBB706Fixed: a combat error in Ritual Sites|r
Entering a Ritual Site or scenario while in combat (with a usable quest item tracked) could throw an "action blocked" error. The tracker now waits until combat ends to resize, so it no longer fires.

|cffEBB706Thanks for your patience|r
There have been a lot of updates lately while the Midnight content gets filled in — sorry for the frequency, and thanks for sticking with it.

|cffEBB706Found a bug? Please tell me|r
If anything looks off, let me know on |cffffffffDiscord|r (button below) or in the |cffffffffCurseForge comments|r.

|cffEBB706Want to see this again?|r Type |cffffffff/eqs whatsnew|r anytime to reopen this summary.
]]

local YELLOW     = ns.Util.color.buttonYellow
local HEADER_RED = ns.Util.color.brandRed
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

    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", -4, -4)
    f.close:SetScript("OnClick", dismiss)

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
    C_Timer.After(2, function()
        if alreadySeen() then return end
        self:Show()
    end)
end
