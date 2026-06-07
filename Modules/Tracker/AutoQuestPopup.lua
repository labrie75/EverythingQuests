-- Modules/Tracker/AutoQuestPopup.lua
-- "Quest Discovered!" / "Quest Complete!" popup boxes for the on-screen
-- tracker. Blizzard's engine maintains a list of auto-quest popups (quests
-- offered/auto-accepted by proximity, and quests that auto-complete in the
-- world); its default tracker renders them as bordered callout boxes. EQ
-- replaces the Blizzard tracker, so without this module those boxes are gone.
--
-- The popup list is engine-maintained and independent of ObjectiveTrackerFrame
-- (which EQ hides), so the APIs keep working. Confirmed live via /eqs autopopup
-- that these are GLOBAL functions on this client (not C_QuestLog.*):
--   GetNumAutoQuestPopUps(), GetAutoQuestPopUp(i) -> questID, "OFFER"|"COMPLETE",
--   RemoveAutoQuestPopUp(questID), ShowQuestOffer(id), ShowQuestComplete(id).
-- All are insecure (no taint), but their signatures drift between builds, so
-- every call is guarded.

local _, ns = ...
local L = ns.L

local S = ns:RegisterSubsystem("TrackerAutoQuestPopup", {})

local PAD        = 7
local LINE_GAP   = 2
local BOX_GAP    = 6                              -- gap between stacked boxes
local ICON_SIZE  = 34
local RED_BORDER = { 0.427, 0.020, 0.004, 1 }     -- #6D0501 (suite border)
local HILITE     = { 0.92, 0.72, 0.02, 1 }        -- yellow hover border

S.pool   = {}
S.active = {}

-- Reused scratch passed to Blocks:ApplyQuestIcon so the per-box icon render
-- doesn't allocate a table each pass. Single-threaded, rewritten per box.
local _iconQ = {}

local function getNum()
    return (GetNumAutoQuestPopUps and GetNumAutoQuestPopUps()) or 0
end

local function popupTitle(questID)
    return ns.Util.QuestTitle(questID, true)
end

-- Clicking a box mirrors Blizzard's own action: open the offer / turn-in
-- dialog, then drop the popup from the engine list. Guarded so a build that
-- renamed any of these can't error out of the click.
local function onBoxClick(box)
    local questID, ptype = box.questID, box.popUpType
    if not questID then return end
    if ptype == "COMPLETE" then
        if ShowQuestComplete then pcall(ShowQuestComplete, questID) end
    else
        if ShowQuestOffer then pcall(ShowQuestOffer, questID) end
    end
    if RemoveAutoQuestPopUp then pcall(RemoveAutoQuestPopUp, questID) end
    local Tracker = ns:GetSubsystem("Tracker")
    if Tracker and Tracker.Refresh then Tracker:Refresh() end
end

local function buildBox()
    local box = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
    box:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    box:SetBackdropColor(0, 0, 0, 0.85)
    box:SetBackdropBorderColor(RED_BORDER[1], RED_BORDER[2], RED_BORDER[3], RED_BORDER[4])
    box:RegisterForClicks("LeftButtonUp")
    box:SetScript("OnClick", onBoxClick)
    box:SetScript("OnEnter", function(b) b:SetBackdropBorderColor(HILITE[1], HILITE[2], HILITE[3], HILITE[4]) end)
    box:SetScript("OnLeave", function(b) b:SetBackdropBorderColor(RED_BORDER[1], RED_BORDER[2], RED_BORDER[3], RED_BORDER[4]) end)

    -- Layered POI icon (glow + face + bang), identical to a quest row's icon
    -- via Blocks:ApplyQuestIcon — high-res atlases, so it matches the rows
    -- below crisply instead of the old upscaled low-res texture.
    box.iconHolder = CreateFrame("Frame", nil, box)
    box.iconHolder:SetSize(ICON_SIZE, ICON_SIZE)
    box.iconHolder:SetPoint("LEFT", box, "LEFT", 10, 0)

    box.iconGlow = box.iconHolder:CreateTexture(nil, "BACKGROUND")
    box.iconGlow:SetSize(44, 44)
    box.iconGlow:SetPoint("CENTER")
    box.iconGlow:SetBlendMode("ADD")
    box.iconGlow:SetAlpha(0.5)

    box.icon = box.iconHolder:CreateTexture(nil, "ARTWORK", nil, 0)
    box.icon:SetSize(30, 30)
    box.icon:SetPoint("CENTER")

    box.iconBang = box.iconHolder:CreateTexture(nil, "ARTWORK", nil, 1)
    box.iconBang:SetSize(30, 30)
    box.iconBang:SetPoint("CENTER")

    -- The POI face is just the empty badge; its symbol normally comes from the
    -- state bang ("..."/"?"), and there's no "!" bang in that atlas set. So we
    -- draw the "!" as a font overlay on the badge — crisp at any scale and
    -- unambiguously "new quest" (never a "?" that reads as turn-in).
    box.bang = box.iconHolder:CreateFontString(nil, "OVERLAY")
    box.bang:SetPoint("CENTER", box.icon, "CENTER", 0, 0)
    box.bang:SetFont(STANDARD_TEXT_FONT, 22, "OUTLINE")
    box.bang:SetTextColor(1, 0.82, 0)             -- gold
    box.bang:SetText("!")

    box.header = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    box.header:SetJustifyH("CENTER")
    box.header:SetTextColor(0.92, 0.72, 0.02)     -- yellow callout

    box.title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    box.title:SetJustifyH("CENTER")
    box.title:SetTextColor(1, 1, 1)

    box.hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    box.hint:SetJustifyH("CENTER")
    box.hint:SetText(L["Click to view quest"])

    -- Centered three-line stack (matches Blizzard/ElvUI), icon floating left.
    box.header:SetPoint("TOP", box, "TOP", 0, -PAD)
    box.title:SetPoint("TOP", box.header, "BOTTOM", 0, -LINE_GAP)
    box.hint:SetPoint("TOP", box.title, "BOTTOM", 0, -LINE_GAP)

    return box
end

local function acquire(parent)
    return ns.Util.AcquirePooled(S.pool, S.active, parent, buildBox)
end

function S:ReleaseAll()
    for i = #S.active, 1, -1 do
        local box = S.active[i]
        box:Hide()
        box:ClearAllPoints()
        box.questID   = nil
        box.popUpType = nil
        S.pool[#S.pool + 1] = box
        S.active[i] = nil
    end
end

-- Render every active auto-quest popup as a box stacked into `content`,
-- starting at yStart. Returns total height consumed (0 when there are none),
-- so the caller can offset the quest sections below.
function S:Render(content, contentWidth, yStart)
    self:ReleaseAll()
    if not content then return 0 end
    local n = getNum()
    if n == 0 then return 0 end

    local textW = math.max(40, (contentWidth or 0) - 16)
    local y = yStart or 0
    local startY = y

    local Blocks = ns:GetSubsystem("TrackerBlocks")
    for i = 1, n do
        local questID, popUpType
        if GetAutoQuestPopUp then questID, popUpType = GetAutoQuestPopUp(i) end
        if questID then
            local box = acquire(content)
            box.questID   = questID
            box.popUpType = popUpType

            box.header:SetText(popUpType == "COMPLETE" and L["Quest Complete!"] or L["Quest Discovered!"])
            box.title:SetText(popupTitle(questID))

            -- Crisp, high-res "!" badge: the normal-classification glow + face
            -- (the available-quest "!") with the state bang suppressed, so a
            -- popup always reads as "new quest" and never shows a "?" that
            -- could be mistaken for a different state. nil classification ->
            -- the normal yellow face/ring inside Blocks:ApplyQuestIcon.
            _iconQ.classification = nil
            _iconQ.isComplete     = false
            _iconQ.noBang         = true
            if Blocks and Blocks.ApplyQuestIcon then
                Blocks:ApplyQuestIcon(box.iconGlow, box.icon, box.iconBang, _iconQ, false)
            end

            box.header:SetWidth(textW)
            box.title:SetWidth(textW)
            box.hint:SetWidth(textW)

            local h = PAD + box.header:GetStringHeight()
                      + LINE_GAP + box.title:GetStringHeight()
                      + LINE_GAP + box.hint:GetStringHeight() + PAD
            if h < ICON_SIZE + PAD * 2 then h = ICON_SIZE + PAD * 2 end
            box:SetHeight(h)
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -y)
            box:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)

            y = y + h + BOX_GAP
        end
    end

    return y - startY
end
