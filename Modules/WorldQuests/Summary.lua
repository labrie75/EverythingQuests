local _, ns = ...
local L = ns.L

local S = ns:RegisterSubsystem("WQSummary", {})

local WIDGET_W   = 160
local PAD        = 6
local ROW_H      = 18
local ICON_SIZE  = 14
local HEADER_GAP = 4
local PIN_TEMPLATE = "EQWorldQuestPinTemplate"

S.rowPool   = {}
S.activeRows = {}

local CATEGORY_DISPLAY = {
    gold       = { label = "Gold",            icon = "Interface\\MoneyFrame\\UI-MoneyIcons", iconCoords = { 0, 0.25, 0, 1 } },
    gear       = { label = "Gear",            icon = "Interface\\Icons\\INV_Helmet_06" },
    rep        = { label = "Reputation",      icon = "Interface\\Icons\\Achievement_Reputation_01" },
    resource   = { label = "Resources",       icon = "Interface\\Icons\\Trade_Mining" },
    ap         = { label = "Artifact Power",  icon = "Interface\\Icons\\INV_7XP_Inscription_TalentTome01" },
    profession = { label = "Professions",     icon = "Interface\\Icons\\Trade_Engineering" },
    pvp        = { label = "PvP",             icon = "Interface\\Icons\\Achievement_Bg_TopDmg" },
    pet        = { label = "Pet Battles",     icon = "Interface\\Icons\\INV_Pet_Achievement_CaptureAPet" },
    other      = { label = "Other",           icon = "Interface\\Icons\\INV_Misc_Gift_01" },
}

local CATEGORY_ORDER = {
    "gear", "gold", "rep", "ap", "resource", "profession", "pvp", "pet", "other",
}

local function buildRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(ROW_H)

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ICON_SIZE, ICON_SIZE)
    r.icon:SetPoint("LEFT", PAD, 0)

    r.count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.count:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
    r.count:SetWidth(22)
    r.count:SetJustifyH("LEFT")
    r.count:SetTextColor(0.92, 0.72, 0.02)

    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.label:SetPoint("LEFT",  r.count, "RIGHT", 4, 0)
    r.label:SetPoint("RIGHT", -PAD, 0)
    r.label:SetJustifyH("LEFT")
    r.label:SetWordWrap(false)

    return r
end

local function acquireRow(parent)
    return ns.Util.AcquirePooled(S.rowPool, S.activeRows, parent, buildRow)
end

local function releaseAllRows()
    for i = #S.activeRows, 1, -1 do
        local r = S.activeRows[i]
        r:Hide()
        r:ClearAllPoints()
        S.rowPool[#S.rowPool + 1] = r
        S.activeRows[i] = nil
    end
end

function S:Build()
    if self.frame then return end
    if not WorldMapFrame then return end

    local f = CreateFrame("Frame", "EQWorldQuestSummary", WorldMapFrame, "BackdropTemplate")
    f:SetSize(WIDGET_W, 60)
    f:SetPoint("TOPLEFT", WorldMapFrame, "TOPRIGHT", 8, -200)
    f:SetFrameStrata("HIGH")
    if WorldMapFrame.GetFrameLevel then
        f:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 100)
    end

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.65)

    local function edge()
        local t = f:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.635, 0.0, 0.039, 0.9)
        return t
    end
    local top = edge(); top:SetHeight(1); top:SetPoint("TOPLEFT");    top:SetPoint("TOPRIGHT")
    local bot = edge(); bot:SetHeight(1); bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT")
    local lt  = edge(); lt:SetWidth(1);   lt:SetPoint("TOPLEFT");     lt:SetPoint("BOTTOMLEFT")
    local rt  = edge(); rt:SetWidth(1);   rt:SetPoint("TOPRIGHT");    rt:SetPoint("BOTTOMRIGHT")

    f.header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.header:SetPoint("TOP", 0, -PAD)
    f.header:SetText(L["World Quests"])
    f.header:SetTextColor(1.0, 0.82, 0.0)

    self.frame = f
end

function S:GetCounts()
    local WQ = ns:GetSubsystem("WQWorldMap")
    if not (WQ and WQ.shadow and WQ.shadow.EnumeratePinsByTemplate) then return nil end

    local counts = {}
    for pin in WQ.shadow:EnumeratePinsByTemplate(PIN_TEMPLATE) do
        local cat = pin.reward and pin.reward.category
        if cat then counts[cat] = (counts[cat] or 0) + 1 end
    end
    return counts
end

function S:Refresh()
    self:Build()
    if not self.frame then return end

    local DB = ns:GetSubsystem("DB")
    if not (DB and DB.db.profile.worldQuests.enabled ~= false
            and DB.db.profile.worldQuests.showOnWorldMap) then
        self.frame:Hide()
        return
    end

    local counts = self:GetCounts()
    if not counts then self.frame:Hide(); return end

    local total = 0
    for _, c in pairs(counts) do total = total + c end
    if total == 0 then
        self.frame:Hide()
        return
    end

    self.frame:Show()
    releaseAllRows()

    local prev = self.frame.header
    local rowsShown = 0
    for _, cat in ipairs(CATEGORY_ORDER) do
        local count = counts[cat] or 0
        if count > 0 then
            local display = CATEGORY_DISPLAY[cat] or CATEGORY_DISPLAY.other
            local row = acquireRow(self.frame)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  prev, "BOTTOMLEFT",  0, prev == self.frame.header and -HEADER_GAP or -2)
            row:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 0, 0)

            row.icon:SetTexture(display.icon)
            if display.iconCoords then
                row.icon:SetTexCoord(display.iconCoords[1], display.iconCoords[2],
                                     display.iconCoords[3], display.iconCoords[4])
            else
                row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            row.count:SetText(tostring(count))
            row.label:SetText(display.label)

            prev = row
            rowsShown = rowsShown + 1
        end
    end

    local h = PAD + 14 + HEADER_GAP + (rowsShown * (ROW_H + 2)) + PAD
    self.frame:SetHeight(math.max(40, h))
end
