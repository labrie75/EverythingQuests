local _, ns = ...
local L = ns.L

local T = ns:RegisterSubsystem("WQTab", {})

local PIN_TEMPLATE = "EQWorldQuestPinTemplate"
local TAB_W, TAB_H = 26, 64

-- The popout panels (Summary + zone list) both read their data from the
-- WQWorldMap provider's pins, so "is there anything to show" == "are there any
-- world-quest pins on the current map".
local function hasWorldQuestContent()
    local WQ = ns:GetSubsystem("WQWorldMap")
    if not (WQ and WQ.shadow and WQ.shadow.EnumeratePinsByTemplate) then return false end
    for _ in WQ.shadow:EnumeratePinsByTemplate(PIN_TEMPLATE) do
        return true
    end
    return false
end

function T:Build()
    if self.tab then return end
    if not WorldMapFrame then return end

    local f = CreateFrame("Button", "EQWorldQuestTab", WorldMapFrame)
    f:SetSize(TAB_W, TAB_H)
    f:SetPoint("TOPLEFT", WorldMapFrame, "TOPRIGHT", 8, -180)
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
    local rt  = edge(); rt:SetWidth(1);   rt:SetPoint("TOPRIGHT");    rt:SetPoint("BOTTOMRIGHT")

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(18, 18)
    f.icon:SetPoint("TOP", 0, -7)
    f.icon:SetAtlas("Worldquest-icon")

    f.arrow = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.arrow:SetPoint("BOTTOM", 0, 6)
    f.arrow:SetTextColor(1, 0.82, 0)

    local hl = f:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.10)

    f:SetScript("OnClick", function() T:Toggle() end)
    f:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        local DB = ns:GetSubsystem("DB")
        local open = DB and DB.db.profile.worldQuests.popoutOpen
        GameTooltip:SetText(L["World Quests"], 1, 0.82, 0)
        GameTooltip:AddLine(open and L["Click to hide the World Quests list."]
                                  or L["Click to show the World Quests list."], 0.82, 0.82, 0.82, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.tab = f
    self:UpdateVisual()
end

function T:UpdateVisual()
    if not self.tab then return end
    local DB = ns:GetSubsystem("DB")
    local open = DB and DB.db.profile.worldQuests.popoutOpen
    -- Popout opens to the RIGHT of the tab: ">" invites expand, "<" invites collapse.
    self.tab.arrow:SetText(open and "<" or ">")
end

function T:Toggle()
    local DB = ns:GetSubsystem("DB")
    if not DB then return end
    local wq = DB.db.profile.worldQuests
    wq.popoutOpen = not wq.popoutOpen

    local Summary = ns:GetSubsystem("WQSummary")
    if Summary and Summary.Refresh then Summary:Refresh() end
    local ZoneList = ns:GetSubsystem("WQZoneMap")
    if ZoneList and ZoneList.Refresh then ZoneList:Refresh() end
    self:UpdateVisual()
end

function T:Refresh()
    self:Build()
    if not self.tab then return end

    local DB = ns:GetSubsystem("DB")
    local wq = DB and DB.db.profile.worldQuests
    local mapOpen = WorldMapFrame and WorldMapFrame:IsShown()
    if not (wq and wq.enabled ~= false and mapOpen and hasWorldQuestContent()) then
        self.tab:Hide()
        return
    end
    self.tab:Show()
    self:UpdateVisual()
end
