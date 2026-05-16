-- Modules/WorldQuests/Pin.lua
-- Pin mixin used by Pin.xml's EQWorldQuestPinTemplate. The pin's job is to
-- show ONE world quest at a glance: reward icon centered, ring colored by
-- reward category, time-left text below. Hover -> tooltip with title +
-- reward + time. Click -> super-track. Right-click -> dismiss the world map.

local _, _ns = ...   -- ns retained (renamed to _ns) in case future tooltip/click logic needs subsystem lookups

EQWorldQuestPinMixin = CreateFromMixins(MapCanvasPinMixin)
local Pin = EQWorldQuestPinMixin

-- Ring color per reward category. Picked to be readable on the world-map
-- background while staying loosely consistent with what players already
-- associate (gold = yellow, gear = blue, etc.).
local RING_COLORS = {
    gold     = { 1.00, 0.82, 0.00 },
    gear     = { 0.00, 0.44, 0.87 },
    rep      = { 0.78, 0.40, 0.78 },
    resource = { 0.40, 0.85, 0.40 },
    ap       = { 0.90, 0.45, 0.10 },
    profession = { 0.65, 0.65, 0.40 },
    pvp      = { 0.85, 0.20, 0.20 },
    pet      = { 0.50, 0.85, 0.85 },
    other    = { 0.70, 0.70, 0.70 },
}

local function fmtTime(mins)
    if not mins or mins <= 0 then return "" end
    if mins < 60   then return mins .. "m" end
    if mins < 1440 then return math.floor(mins / 60) .. "h" end
    return math.floor(mins / 1440) .. "d"
end

-- Color the time-left text by urgency:
-- > 4h = green, 1-4h = white, 30-60m = yellow, < 30m = red.
local function timeColor(mins)
    if not mins then return 1, 1, 1 end
    if mins <= 30   then return 1.00, 0.30, 0.30 end
    if mins <= 60   then return 1.00, 0.82, 0.20 end
    if mins <= 240  then return 1.00, 1.00, 1.00 end
    return 0.40, 1.00, 0.40
end

function Pin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_QUEST_PING")
    self:SetScalingLimits(1, 0.6, 1.4)
    self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
end

-- Required empty stub — newer canvas iterates pins and calls this; missing
-- it trips the assertion at MapCanvas.lua:280 (same trap we hit on the
-- regular quest pin earlier in the project).
function Pin:CheckMouseButtonPassthrough() end

function Pin:OnAcquired(questID, x, y, reward)
    self.questID = questID
    self.reward  = reward
    self:SetPosition(x, y)

    -- Apply user pin scale from Options. Map canvas pin scale is bounded
    -- by SetScalingLimits (set in OnLoad: 0.6 - 1.4). The user slider keys
    -- to a 0.5-2.0 range; we clamp via SetScale on the pin frame itself.
    local DB = _ns:GetSubsystem("DB")
    if DB and DB.db.profile.worldQuests and DB.db.profile.worldQuests.pinScale then
        local s = math.max(0.5, math.min(2.0, DB.db.profile.worldQuests.pinScale))
        self:SetScale(s)
    end

    self.ring:SetAtlas("worldquest-emissary-ring")

    local Rewards = _ns:GetSubsystem("WQRewards")
    if Rewards and Rewards.ApplyToTexture then
        Rewards:ApplyToTexture(self.icon, reward)
    end

    -- Time left text + color
    local mins = C_TaskQuest and C_TaskQuest.GetQuestTimeLeftMinutes
                 and C_TaskQuest.GetQuestTimeLeftMinutes(questID)
    self.timeText:SetText(fmtTime(mins))
    self.timeText:SetTextColor(timeColor(mins))

    -- Apply selection visual based on whether this quest is super-tracked.
    -- Sets ring color + size — the un-selected branch handles the default
    -- "ring tinted by reward category" style, so we don't double-set it above.
    local superID = (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
                     and C_SuperTrack.GetSuperTrackedQuestID()) or 0
    self:UpdateSelectionVisual(questID == superID)

    self:Show()
end

-- Re-skin the pin to indicate "this is the currently super-tracked quest".
-- Called by both OnAcquired (initial paint) and the provider's
-- UpdateSelections sweep when SUPER_TRACKING_CHANGED fires. Cheap — only
-- touches size/color, no frame creation.
function Pin:UpdateSelectionVisual(isSelected)
    self.isSelected = isSelected
    if isSelected then
        self:SetSize(42, 42)
        self.ring:SetSize(42, 42)
        self.icon:SetSize(28, 28)
        -- Bright yellow ring overrides the category color so the active
        -- quest pops out regardless of which reward type it is.
        self.ring:SetVertexColor(1.00, 1.00, 0.30, 1)
    else
        self:SetSize(34, 34)
        self.ring:SetSize(34, 34)
        self.icon:SetSize(22, 22)
        local rc = (self.reward and RING_COLORS[self.reward.category]) or RING_COLORS.other
        self.ring:SetVertexColor(rc[1], rc[2], rc[3], 1)
    end
end

function Pin:OnReleased()
    self.questID, self.reward = nil, nil
    self.icon:SetTexture(nil)
    self.timeText:SetText("")
end

function Pin:OnMouseEnter()
    if not self.questID then return end
    local Tooltip = _ns:GetSubsystem("WQTooltip")
    if Tooltip and Tooltip.Show then
        Tooltip:Show(self, self.questID)
    end
end

function Pin:OnMouseLeave()
    local Tooltip = _ns:GetSubsystem("WQTooltip")
    if Tooltip and Tooltip.Hide then
        Tooltip:Hide()
    else
        GameTooltip:Hide()
    end
end

local function pinContextMenu(pin)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    local questID = pin.questID
    local Watch = _ns:GetSubsystem("WQWatchPersist")
    local tracked = Watch and Watch.IsTracked and Watch:IsTracked(questID)
    if not tracked and C_QuestLog and C_QuestLog.GetQuestWatchType then
        tracked = C_QuestLog.GetQuestWatchType(questID) ~= nil
    end

    local title = (C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID
                   and C_TaskQuest.GetQuestInfoByQuestID(questID))
                  or ("World Quest #" .. tostring(questID))

    MenuUtil.CreateContextMenu(pin, function(_owner, root)
        root:CreateTitle(title)

        if tracked then
            root:CreateButton("Untrack Quest", function()
                if Watch and Watch.Untrack then Watch:Untrack(questID) end
            end)
        else
            root:CreateButton("Track Quest", function()
                if Watch and Watch.Track then Watch:Track(questID) end
            end)
        end

        root:CreateButton("Super-track (follow arrow)", function()
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
                C_SuperTrack.SetSuperTrackedQuestID(questID)
            end
        end)

        root:CreateDivider()
        root:CreateButton("Cancel", function() end)
    end)
end

function Pin:OnClick(button)
    if not self.questID then return end
    if button == "RightButton" then
        pinContextMenu(self)
    else
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
            C_SuperTrack.SetSuperTrackedQuestID(self.questID)
        end
    end
end
