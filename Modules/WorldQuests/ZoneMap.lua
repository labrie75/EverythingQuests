-- Modules/WorldQuests/ZoneMap.lua
-- Per-zone world quest list. Stacks below the Summary widget when the
-- player views a Zone-type map (mapType == 3). Each row shows the reward
-- icon, quest title, and time-left. Click → super-track. Right-click →
-- track/untrack via the same WQWatchPersist API the pin uses.
--
-- Design choices:
--   • Hides on continent / cosmic maps so it doesn't dwarf the Summary
--     widget when there are 50+ quests across a continent.
--   • Reads the SHADOW canvas's pin pool (same as Summary) so it stays in
--     lock-step with what's actually rendered — filters automatically apply.
--   • Sorts by time-remaining ascending so urgent WQs surface first.

local _, ns = ...

local Z = ns:RegisterSubsystem("WQZoneMap", {})

local PANEL_W      = 240
local PAD          = 6
local HEADER_H     = 18
local ROW_H        = 32
local ROW_GAP      = 2
local ICON_SIZE    = 26
local PIN_TEMPLATE = "EQWorldQuestPinTemplate"

Z.rowPool   = {}
Z.activeRows = {}

-- Shared WQ time helpers — single source of truth in Core/Util.lua.
local Util = ns.Util

local function questTitle(questID)
    if C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID then
        local t = C_TaskQuest.GetQuestInfoByQuestID(questID)
        if t and t ~= "" then return t end
    end
    return "World Quest"
end

-- ─── Row pool ──────────────────────────────────────────────────────────
local function buildRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ICON_SIZE, ICON_SIZE)
    r.icon:SetPoint("LEFT", PAD, 0)

    r.title = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.title:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, -2)
    r.title:SetPoint("RIGHT", -PAD, 0)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)
    r.title:SetTextColor(1.0, 0.82, 0.0)

    r.timeText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.timeText:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 6, 2)
    r.timeText:SetJustifyH("LEFT")

    r:SetScript("OnEnter", function(self)
        if not self.questID then return end
        local Tooltip = ns:GetSubsystem("WQTooltip")
        if Tooltip and Tooltip.Show then Tooltip:Show(self, self.questID) end
    end)
    r:SetScript("OnLeave", function()
        local Tooltip = ns:GetSubsystem("WQTooltip")
        if Tooltip and Tooltip.Hide then Tooltip:Hide() end
    end)
    r:SetScript("OnClick", function(self, button)
        if not self.questID then return end
        if button == "RightButton" then
            if MenuUtil and MenuUtil.CreateContextMenu then
                local Watch = ns:GetSubsystem("WQWatchPersist")
                local tracked = Watch and Watch.IsTracked and Watch:IsTracked(self.questID)
                MenuUtil.CreateContextMenu(self, function(_, root)
                    root:CreateTitle(questTitle(self.questID))
                    if tracked then
                        root:CreateButton("Untrack Quest", function()
                            if Watch and Watch.Untrack then Watch:Untrack(self.questID) end
                        end)
                    else
                        root:CreateButton("Track Quest", function()
                            if Watch and Watch.Track then Watch:Track(self.questID) end
                        end)
                    end
                    root:CreateButton("Super-track (follow arrow)", function()
                        if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
                            C_SuperTrack.SetSuperTrackedQuestID(self.questID)
                        end
                    end)
                end)
            end
        else
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
                C_SuperTrack.SetSuperTrackedQuestID(self.questID)
            end
        end
    end)

    return r
end

local function acquireRow(parent)
    local r = tremove(Z.rowPool)
    if not r then r = buildRow(parent) end
    r:SetParent(parent)
    r:Show()
    Z.activeRows[#Z.activeRows + 1] = r
    return r
end

local function releaseAll()
    for i = #Z.activeRows, 1, -1 do
        local r = Z.activeRows[i]
        r:Hide()
        r:ClearAllPoints()
        r.icon:SetTexture(nil)
        r.icon:SetTexCoord(0, 1, 0, 1)
        r.title:SetText("")
        r.timeText:SetText("")
        r.questID = nil
        Z.rowPool[#Z.rowPool + 1] = r
        Z.activeRows[i] = nil
    end
end

-- ─── Build / refresh ───────────────────────────────────────────────────
function Z:Build()
    if self.frame then return end
    if not WorldMapFrame then return end

    local f = CreateFrame("Frame", "EQZoneQuestList", WorldMapFrame, "BackdropTemplate")
    f:SetSize(PANEL_W, 80)

    local Summary = ns:GetSubsystem("WQSummary")
    if Summary and Summary.frame then
        f:SetPoint("TOPLEFT",  Summary.frame, "BOTTOMLEFT",  0, -8)
        f:SetPoint("TOPRIGHT", Summary.frame, "BOTTOMRIGHT", 0, -8)
    else
        f:SetPoint("TOPLEFT", WorldMapFrame, "TOPRIGHT", 8, -300)
    end

    f:SetFrameStrata("HIGH")
    if WorldMapFrame.GetFrameLevel then
        f:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 100)
    end

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.65)

    local function edge()
        local t = f:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.43, 0.02, 0.0, 0.9)
        return t
    end
    local top = edge(); top:SetHeight(1); top:SetPoint("TOPLEFT");    top:SetPoint("TOPRIGHT")
    local bot = edge(); bot:SetHeight(1); bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT")
    local lt  = edge(); lt:SetWidth(1);   lt:SetPoint("TOPLEFT");     lt:SetPoint("BOTTOMLEFT")
    local rt  = edge(); rt:SetWidth(1);   rt:SetPoint("TOPRIGHT");    rt:SetPoint("BOTTOMRIGHT")

    f.header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.header:SetPoint("TOP", 0, -PAD)
    f.header:SetTextColor(1.0, 0.82, 0)

    self.frame = f
end

function Z:Refresh()
    self:Build()
    if not self.frame then return end

    local DB = ns:GetSubsystem("DB")
    -- Master WQ switch off, or the zone-map toggle off → no zone list.
    if not (DB and DB.db.profile.worldQuests.enabled ~= false
            and DB.db.profile.worldQuests.showOnZoneMap) then
        self.frame:Hide()
        return
    end
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then
        self.frame:Hide()
        return
    end

    local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    if not (mapID and mapID > 0) then self.frame:Hide(); return end

    local mapInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    local zoneType = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
    if not (mapInfo and mapInfo.mapType == zoneType) then
        self.frame:Hide()
        return
    end

    local WQ = ns:GetSubsystem("WQWorldMap")
    if not (WQ and WQ.shadow and WQ.shadow.EnumeratePinsByTemplate) then
        self.frame:Hide()
        return
    end

    local pins = {}
    for pin in WQ.shadow:EnumeratePinsByTemplate(PIN_TEMPLATE) do
        if pin.questID then
            pins[#pins + 1] = pin
        end
    end

    if #pins == 0 then
        self.frame:Hide()
        return
    end

    local sortMode = (DB and DB.db.profile.worldQuests.zoneListSort) or "time"
    table.sort(pins, function(a, b)
        if sortMode == "alpha" then
            return (questTitle(a.questID) or "") < (questTitle(b.questID) or "")
        elseif sortMode == "type" then
            local ca = (a.reward and a.reward.category) or "z"
            local cb = (b.reward and b.reward.category) or "z"
            if ca ~= cb then return ca < cb end
            return (questTitle(a.questID) or "") < (questTitle(b.questID) or "")
        elseif sortMode == "faction" then
            local fa = (C_QuestLog.GetQuestFactionID and C_QuestLog.GetQuestFactionID(a.questID)) or 0
            local fb = (C_QuestLog.GetQuestFactionID and C_QuestLog.GetQuestFactionID(b.questID)) or 0
            if fa ~= fb then return fa < fb end
            return (questTitle(a.questID) or "") < (questTitle(b.questID) or "")
        else
            local ta = C_TaskQuest and C_TaskQuest.GetQuestTimeLeftMinutes
                       and C_TaskQuest.GetQuestTimeLeftMinutes(a.questID) or 0
            local tb = C_TaskQuest and C_TaskQuest.GetQuestTimeLeftMinutes
                       and C_TaskQuest.GetQuestTimeLeftMinutes(b.questID) or 0
            return ta < tb
        end
    end)

    releaseAll()
    self.frame:Show()
    self.frame.header:SetFormattedText("%s — %d quest%s", mapInfo.name, #pins, #pins == 1 and "" or "s")

    local y = HEADER_H + PAD
    for i = 1, #pins do
        local pin = pins[i]
        local row = acquireRow(self.frame)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  self.frame, "TOPLEFT",  PAD, -y)
        row:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -PAD, -y)
        row.questID = pin.questID

        local Rewards = ns:GetSubsystem("WQRewards")
        if Rewards and Rewards.ApplyToTexture then
            Rewards:ApplyToTexture(row.icon, pin.reward)
        end

        row.title:SetText(questTitle(pin.questID))

        local mins = C_TaskQuest and C_TaskQuest.GetQuestTimeLeftMinutes
                     and C_TaskQuest.GetQuestTimeLeftMinutes(pin.questID)
        row.timeText:SetText(Util.WQTimeLong(mins))
        row.timeText:SetTextColor(Util.WQTimeColor(mins))

        y = y + ROW_H + ROW_GAP
    end

    self.frame:SetHeight(y + PAD)
end
