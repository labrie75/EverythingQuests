local _, ns = ...

local S = ns:RegisterSubsystem("TrackerScenario", {})

local SUBHEADER_H      = 26   -- matches Frame.lua SECTION_H so the Delves
                              -- header band sizes like the other sections
local BANNER_GAP       = 6
local CRITERIA_LINE_GAP = 4
local BAR_H            = 16
local BAR_W_RATIO      = 0.85

local HEADER_COLOR = { 0.93, 0.32, 0.10 }

S.criteriaPool   = {}
S.activeCriteria = {}

local TEXTURE_KIT_OFFSETS = {
    ["evergreen-scenario"]   = { nx = 0,  ny = 0, fx = -4, fy = 2 },
    ["thewarwithin-scenario"]= { nx = 0,  ny = 0, fx = 3,  fy = -2 },
    ["delves-scenario"]      = { nx = -2, ny = 1, fx = -2, fy = 1 },
}
local DEFAULT_OFFSETS = { nx = 0, ny = 0, fx = -10, fy = 3 }

local function pickAtlases(textureKit)
    local kit = textureKit or "evergreen-scenario"
    local normal = kit .. "-trackerheader"
    local final  = kit .. "-trackerheader-final-filigree"

    local hasNormal = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(normal)
    if not hasNormal then
        normal = "evergreen-scenario-trackerheader"
        final  = "evergreen-scenario-trackerheader-final-filigree"
        kit    = "evergreen-scenario"
    elseif not (C_Texture.GetAtlasInfo(final)) then
        final = nil
    end

    return normal, final, kit
end

local function categoryLabel(scenarioType, textureKit, scenarioName)
    -- scenarioType 8 = Delves. Verified live via C_Scenario.GetInfo /
    -- C_ScenarioInfo.GetScenarioInfo inside a Midnight delve; the legacy
    -- textureKit return is nil there, which is why a kit-name check alone
    -- always fell through to the generic "Scenario" label.
    if scenarioType == 8 then return "Delves" end
    if textureKit and textureKit:lower():find("delve") then return "Delves" end
    if scenarioType == 1 then return "Mythic+" end
    if scenarioType == 5 then return "Dungeon" end
    if scenarioType == 7 then return "Warfront" end
    if scenarioType == 2 then return "Proving Grounds" end
    -- Midnight world events report scenarioType 0 / textureKit
    -- "midnight-scenario"; the name is the only reliable signal, so match
    -- it directly rather than the kit (other Midnight scenarios may share
    -- the kit and should keep the generic label).
    if scenarioName then
        local n = scenarioName:lower()
        if n:find("void incursion") or n:find("void assault") then
            return "Void Incursion"
        end
    end
    return "Scenario"
end

-- Unreleased / PTR scenario steps sometimes return an internal developer
-- string as the criteria description, e.g. "12.0.5 Void Assaults - Eversong
-- - Major Attack - Scenario 01 - Step 02 Completion (JTL)". Player-facing
-- text never starts with a game version or carries "- Step NN" build
-- markers, so detect those and show the bar alone instead.
local function looksInternal(s)
    if not s or s == "" then return false end
    if s:find("^%s*%d+%.%d+%.%d+") then return true end   -- leading "12.0.5"
    if s:find("%-%s*Step%s+%d+") then return true end      -- "- Step 02"
    if s:find("Scenario%s+%d%d") then return true end      -- "Scenario 01"
    return false
end

local function buildCriteriaRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(BAR_H + 14)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(12, 12)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetJustifyH("LEFT")
    row.text:SetTextColor(1, 0.82, 0)

    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetHeight(BAR_H)
    row.bar:SetMinMaxValues(0, 100)
    row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    row.bar:SetStatusBarColor(0.26, 0.42, 1.0)

    row.bar.bg = row.bar:CreateTexture(nil, "BACKGROUND")
    row.bar.bg:SetAllPoints()
    row.bar.bg:SetColorTexture(0.04, 0.07, 0.18, 0.9)

    row.bar.border = CreateFrame("Frame", nil, row.bar, "BackdropTemplate")
    row.bar.border:SetPoint("TOPLEFT", -1, 1)
    row.bar.border:SetPoint("BOTTOMRIGHT", 1, -1)
    row.bar.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    row.bar.border:SetBackdropBorderColor(0, 0, 0, 0.9)

    row.bar.label = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.bar.label:SetPoint("CENTER", row.bar, "CENTER", 0, 0)

    return row
end

local function acquireCriteria(parent)
    local row = tremove(S.criteriaPool)
    if not row then row = buildCriteriaRow(parent) end
    row:SetParent(parent)
    row:Show()
    S.activeCriteria[#S.activeCriteria + 1] = row
    return row
end

local function releaseAllCriteria()
    for i = #S.activeCriteria, 1, -1 do
        local row = S.activeCriteria[i]
        row:Hide()
        row:ClearAllPoints()
        row.bar:Hide()
        row.icon:Hide()
        row.icon:ClearAllPoints()
        row.text:ClearAllPoints()
        row.text:SetText("")
        S.criteriaPool[#S.criteriaPool + 1] = row
        S.activeCriteria[i] = nil
    end
end

function S:Build()
    if self.banner then return end
    local Tracker = ns:GetSubsystem("Tracker")
    local container = Tracker and Tracker.frame and Tracker.frame.scenarioContainer
    if not container then return end
    self.frame = container

    local subHeader = CreateFrame("Frame", nil, container)
    subHeader:SetHeight(SUBHEADER_H)
    subHeader:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    subHeader:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)

    subHeader.text = subHeader:CreateFontString(nil, "OVERLAY", "ObjectiveTrackerHeaderFont")
    if not subHeader.text:GetFont() then subHeader.text:SetFontObject("GameFontNormalLarge") end
    subHeader.text:SetPoint("LEFT", 8, 0)
    subHeader.text:SetTextColor(HEADER_COLOR[1], HEADER_COLOR[2], HEADER_COLOR[3])

    local banner = CreateFrame("Frame", nil, container)
    banner:SetPoint("TOP", subHeader, "BOTTOM", 0, -BANNER_GAP)

    banner.NormalBG = banner:CreateTexture(nil, "BACKGROUND")
    banner.ThemeOverlay = banner:CreateTexture(nil, "BACKGROUND", nil, 1)
    banner.ThemeOverlay:SetBlendMode("ADD")
    banner.FinalBG = banner:CreateTexture(nil, "BORDER")

    banner.Stage = banner:CreateFontString(nil, "ARTWORK", "Game18Font")
    banner.Stage:SetSize(172, 18)
    banner.Stage:SetJustifyH("LEFT")
    banner.Stage:SetTextColor(1, 0.914, 0.682)
    banner.Stage:SetShadowOffset(1, -1)
    banner.Stage:SetShadowColor(0, 0, 0, 1)

    banner.Name = banner:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    banner.Name:SetSize(172, 28)
    banner.Name:SetJustifyH("LEFT")
    banner.Name:SetJustifyV("TOP")
    banner.Name:SetSpacing(2)
    banner.Name:SetTextColor(1, 0.831, 0.380)
    banner.Name:SetPoint("TOPLEFT", banner.Stage, "BOTTOMLEFT", 0, -4)

    banner.WidgetContainer = CreateFrame("Frame", nil, banner, "UIWidgetContainerTemplate")
    banner.WidgetContainer.verticalAnchorPoint     = "TOP"
    banner.WidgetContainer.verticalRelativePoint   = "TOP"
    banner.WidgetContainer:SetPoint("TOP", banner, "TOP")
    banner.WidgetContainer:Hide()

    self.subHeader = subHeader
    self.banner    = banner
end

function S:Refresh()
    self:Build()
    local container = self.frame
    local banner    = self.banner
    local subHeader = self.subHeader
    if not (container and banner and subHeader) then return end

    local scenarioName, currentStage, numStages, scenarioType, textureKit
    if C_Scenario and C_Scenario.GetInfo then
        scenarioName, currentStage, numStages, _, _, _, _, _, _, scenarioType, _, textureKit = C_Scenario.GetInfo()
    end

    local inScenario = scenarioName and numStages and numStages > 0 and currentStage and currentStage > 0
    if not inScenario then
        releaseAllCriteria()
        subHeader:Hide()
        banner:Hide()
        if banner.WidgetContainer.UnregisterForWidgetSet then
            banner.WidgetContainer:UnregisterForWidgetSet()
        end
        container:SetHeight(1)
        return
    end

    subHeader:Show()
    subHeader.text:SetText(categoryLabel(scenarioType, textureKit, scenarioName))
    -- Match the other section headers: user font, +4 over quest titles
    -- (mirrors Frame.lua HEADER_FONT_DELTA so "Delves" sizes like "Quests").
    local Media = ns:GetSubsystem("Media")
    if Media and Media.ApplyTrackerFont then
        Media:ApplyTrackerFont(subHeader.text, 4)
    end
    banner:Show()

    local stageName, numCriteria, widgetSetID
    if C_Scenario.GetStepInfo then
        stageName, _, numCriteria, _, _, _, _, _, _, _, _, widgetSetID = C_Scenario.GetStepInfo()
    end

    local normalAtlas, finalAtlas, resolvedKit = pickAtlases(textureKit)
    local offsets = TEXTURE_KIT_OFFSETS[resolvedKit] or DEFAULT_OFFSETS

    local bw, bh = 201, 83
    banner:SetSize(bw, bh)

    banner.NormalBG:SetAtlas(normalAtlas, true)
    banner.NormalBG:ClearAllPoints()
    banner.NormalBG:SetPoint("TOPLEFT", banner, "TOPLEFT", offsets.nx, offsets.ny)
    banner.NormalBG:Show()

    if finalAtlas and currentStage == numStages and numStages > 1 then
        banner.FinalBG:SetAtlas(finalAtlas, true)
        banner.FinalBG:ClearAllPoints()
        banner.FinalBG:SetPoint("TOPLEFT", banner, "TOPLEFT", offsets.fx, offsets.fy)
        banner.FinalBG:Show()
    else
        banner.FinalBG:Hide()
    end

    local displayInfo = C_ScenarioInfo and C_ScenarioInfo.GetDisplayInfo and C_ScenarioInfo.GetDisplayInfo()
    if displayInfo and displayInfo.themeColor then
        banner.ThemeOverlay:SetAtlas("themed-scenario-trackerheader-add", true)
        banner.ThemeOverlay:ClearAllPoints()
        banner.ThemeOverlay:SetPoint("BOTTOM", banner.NormalBG, "BOTTOM", 0, 0)
        local r, g, b = displayInfo.themeColor:GetRGB()
        banner.ThemeOverlay:SetVertexColor(r, g, b)
        banner.ThemeOverlay:Show()
    else
        banner.ThemeOverlay:Hide()
    end

    if widgetSetID and widgetSetID > 0 then
        banner.WidgetContainer:RegisterForWidgetSet(widgetSetID)
        banner.WidgetContainer:Show()
        banner.Name:Hide()
        banner.Stage:Hide()
        banner.NormalBG:Hide()
        banner.ThemeOverlay:Hide()
        banner.FinalBG:Hide()
    else
        if banner.WidgetContainer.UnregisterForWidgetSet then
            banner.WidgetContainer:UnregisterForWidgetSet()
        end
        banner.WidgetContainer:Hide()

        banner.Stage:ClearAllPoints()
        banner.Stage:SetPoint("TOPLEFT", banner, "TOPLEFT", 15, -10)
        if currentStage == numStages and numStages > 1 then
            banner.Stage:SetText("Final Stage")
        elseif numStages > 1 then
            banner.Stage:SetFormattedText("Stage %d", currentStage)
        else
            banner.Stage:SetText("")
        end
        banner.Stage:Show()
        banner.Name:SetText(stageName or "")
        banner.Name:Show()
    end

    releaseAllCriteria()
    local prev, prevAnchor = banner, "BOTTOM"
    local barWidth = math.floor(container:GetWidth() * BAR_W_RATIO)
    local rowWidth = container:GetWidth() - 16
    for i = 1, (numCriteria or 0) do
        local info = C_ScenarioInfo and C_ScenarioInfo.GetCriteriaInfo and C_ScenarioInfo.GetCriteriaInfo(i)
        if info then
            local row = acquireCriteria(container)
            row:ClearAllPoints()
            row:SetPoint("TOP", prev, prevAnchor, 0, -CRITERIA_LINE_GAP)

            if info.isWeightedProgress and not info.completed then
                row:SetWidth(barWidth)
                row.icon:Hide()

                local desc = info.description or ""
                local showText = desc ~= "" and not looksInternal(desc)

                local pct = math.max(0, math.min(100, info.quantity or 0))
                row.bar:Show()
                row.bar:ClearAllPoints()
                row.bar:SetWidth(barWidth)
                row.bar:SetValue(pct)
                row.bar.label:SetFormattedText("%d%%", pct)

                row.text:ClearAllPoints()
                if showText then
                    row.text:SetPoint("TOP", row, "TOP", 0, 0)
                    row.text:SetJustifyH("CENTER")
                    row.text:SetText(desc)
                    row.text:SetTextColor(1, 0.82, 0)
                    row.bar:SetPoint("TOP", row.text, "BOTTOM", 0, -2)
                    row:SetHeight(row.text:GetStringHeight() + 2 + BAR_H)
                else
                    row.text:SetText("")
                    row.bar:SetPoint("TOP", row, "TOP", 0, 0)
                    row:SetHeight(BAR_H)
                end
            else
                row:SetWidth(rowWidth)
                row.bar:Hide()

                row.icon:Show()
                row.icon:ClearAllPoints()
                row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
                if info.completed then
                    row.icon:SetAtlas("ui-questtracker-tracker-check", false)
                else
                    row.icon:SetAtlas("ui-questtracker-objective-nub", false)
                end

                row.text:ClearAllPoints()
                row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                row.text:SetJustifyH("LEFT")

                local desc = info.description or ""
                local label = desc
                -- Default Blizzard pattern: drop the X/Y prefix on completed
                -- criteria. The green check already communicates "done", so
                -- "100/200 Cultists purged" simplifies to "Cultists purged".
                if not info.isFormatted and not info.completed
                   and info.totalQuantity and info.totalQuantity > 0 then
                    label = ("%d/%d %s"):format(info.quantity or 0, info.totalQuantity, desc)
                end
                row.text:SetText(label)
                if info.completed then
                    row.text:SetTextColor(0.27, 1.0, 0.27)
                else
                    row.text:SetTextColor(0.85, 0.85, 0.85)
                end
                row:SetHeight(math.max(row.text:GetStringHeight(), 14))
            end

            prev = row
            prevAnchor = "BOTTOM"
        end
    end

    local h = SUBHEADER_H + BANNER_GAP + bh
    for i = 1, #self.activeCriteria do
        h = h + CRITERIA_LINE_GAP + self.activeCriteria[i]:GetHeight()
    end
    h = h + 6
    container:SetHeight(math.max(1, h))
end

function S:OnEnable()
    local Events = ns:GetSubsystem("Events")
    local function refresh() self:Refresh() end

    Events:On("SCENARIO_UPDATE",                  refresh)
    Events:On("SCENARIO_CRITERIA_UPDATE",         refresh)
    Events:On("SCENARIO_SPELL_UPDATE",            refresh)
    Events:On("SCENARIO_CRITERIA_SHOW_STATE_UPDATE", refresh)
    Events:On("SCENARIO_COMPLETED",               refresh)
    Events:On("ACTIVE_DELVE_DATA_UPDATE",         refresh)
    Events:On("PLAYER_ENTERING_WORLD",            refresh)

    self:Refresh()
end
