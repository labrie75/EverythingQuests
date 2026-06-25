local _, ns = ...
local L = ns.L

local T = ns:RegisterSubsystem("WQTab", {})

-- Native quest-map side-tab dimensions (Blizzard's LargeSideTabButtonTemplate).
local TAB_W, TAB_H = 43, 55
-- Sit in the lower-middle of the map's right edge, clear of Blizzard's own
-- button column (filters / tracking / Adventure Guide) which clusters up top.
local TAB_Y = -110
-- Fallback dock if the native quest-map tabs aren't available: lower-right edge.
local PANEL_EDGE_X = 28

-- Line the World Quests tab up as a 4th tab directly under the native quest-map
-- tabs by copying the Map Legend tab's own stacking anchor (so the gap and x match
-- exactly). Anchoring our frame to a Blizzard frame is read-only — no taint.
local function anchorTab(f)
    f:ClearAllPoints()
    local mlt = QuestMapFrame and QuestMapFrame.MapLegendTab
    if mlt and mlt.GetNumPoints and mlt:GetNumPoints() > 0 then
        local point, _, relPoint, x, y = mlt:GetPoint(1)
        if point then
            f:SetPoint(point, mlt, relPoint, x or 0, y or 0)
            local w, h = mlt:GetSize()
            if w and w > 0 and h and h > 0 then f:SetSize(w, h) end
            return
        end
    end
    f:SetPoint("RIGHT", WorldMapFrame, "RIGHT", PANEL_EDGE_X, TAB_Y)
end

-- Match the native quest-map tabs' look. When ElvUI has reskinned them (its
-- backdrop appears on the Map Legend tab), drop our Blizzard atlas chrome and give
-- the tab ElvUI's flat backdrop so the 4th tab matches the other three and follows
-- the user's ElvUI media. Gating on the native tab's actual backdrop (not just
-- "is ElvUI loaded") keeps us Blizzard-styled when ElvUI's quest skin is off.
-- Defensive throughout: any miss leaves the native Blizzard look untouched.
local function applyElvUISkin(f)
    if f._elvui then return true end
    local mlt = QuestMapFrame and QuestMapFrame.MapLegendTab
    if not (_G.ElvUI and mlt and mlt.backdrop and f.CreateBackdrop) then return false end

    if f.bg       then f.bg:Hide()       end
    if f.selected then f.selected:Hide() end
    if f.hl       then f.hl:Hide()       end

    local ok = pcall(function() if not f.backdrop then f:CreateBackdrop() end end)
    if not (ok and f.backdrop) then return false end

    f.icon:ClearAllPoints()
    f.icon:SetPoint("TOPLEFT",     f, "TOPLEFT",      4, -4)
    f.icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4,  4)

    f._elvui = true
    return true
end

function T:Build()
    if self.tab then return end
    if not WorldMapFrame then return end

    local f = CreateFrame("Button", "EQWorldQuestTab", WorldMapFrame)
    f:SetSize(TAB_W, TAB_H)
    anchorTab(f)
    f:SetFrameStrata("HIGH")
    if WorldMapFrame.GetFrameLevel then
        f:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 100)
    end

    -- Replicate Blizzard's LargeSideTabButtonTemplate art (atlases verified from
    -- QuestMapFrame's QuestsTab/EventsTab) so the World Quests tab reads as a native
    -- quest-map side tab. Replicated, not inherited, to avoid the template's
    -- SidePanelTabButtonMixin (its tab-group coupling) on a map-parented frame.
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAtlas("questlog-tab-side", true)
    f.bg:SetPoint("CENTER")

    f.selected = f:CreateTexture(nil, "OVERLAY")
    f.selected:SetAtlas("QuestLog-Tab-side-Glow-select", true)
    f.selected:SetPoint("CENTER")
    f.selected:Hide()

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(26, 26)
    f.icon:SetAtlas("Worldquest-icon")
    f.icon:SetPoint("CENTER", -2, 0)

    f.hl = f:CreateTexture(nil, "HIGHLIGHT")
    f.hl:SetAtlas("QuestLog-Tab-side-Glow-hover", true)
    f.hl:SetPoint("CENTER")

    applyElvUISkin(f)

    f:SetScript("OnClick", function() T:Toggle() end)
    -- Private tooltip, not the shared GameTooltip: a map-parented frame drawing on
    -- the singleton can leave EQ taint that trips the next AreaPOI hover (see
    -- Util.PinTooltip / ChainGuide QuestMapButton).
    f:SetScript("OnEnter", function(s)
        local tip = ns.Util.PinTooltip()
        tip:SetOwner(s, "ANCHOR_LEFT")
        local DB = ns:GetSubsystem("DB")
        local open = DB and DB.db.profile.worldQuests.popoutOpen
        tip:SetText(L["World Quests"], 1, 0.82, 0)
        tip:AddLine(open and L["Click to hide the World Quests list."]
                          or L["Click to show the World Quests list."], 0.82, 0.82, 0.82, true)
        tip:Show()
    end)
    f:SetScript("OnLeave", function() ns.Util.PinTooltip():Hide() end)

    self.tab = f
    self:UpdateVisual()
end

function T:UpdateVisual()
    local f = self.tab
    if not f then return end
    local DB = ns:GetSubsystem("DB")
    local open = DB and DB.db.profile.worldQuests.popoutOpen
    if f._elvui and f.backdrop then
        -- ElvUI mode: mark the active tab by colouring the backdrop border gold,
        -- otherwise restore ElvUI's own border colour.
        if open then
            f.backdrop:SetBackdropBorderColor(0.92, 0.72, 0.02)
        else
            local E = _G.ElvUI and _G.ElvUI[1]
            local bc = E and E.media and E.media.bordercolor
            if bc then
                f.backdrop:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
            else
                f.backdrop:SetBackdropBorderColor(0, 0, 0, 1)
            end
        end
    elseif f.selected then
        -- Native: the Blizzard "selected" glow marks the tab active while open.
        f.selected:SetShown(open and true or false)
    end
end

function T:Toggle()
    local DB = ns:GetSubsystem("DB")
    if not DB then return end
    local wq = DB.db.profile.worldQuests
    wq.popoutOpen = not wq.popoutOpen

    local Panel = ns:GetSubsystem("WQPanel")
    if Panel and Panel.Refresh then Panel:Refresh() end
    self:UpdateVisual()
end

function T:Refresh()
    self:Build()
    if not self.tab then return end

    local DB = ns:GetSubsystem("DB")
    local wq = DB and DB.db.profile.worldQuests
    local mapOpen = WorldMapFrame and WorldMapFrame:IsShown()
    local Panel = ns:GetSubsystem("WQPanel")
    local hasContent = Panel and Panel.HasContent and Panel:HasContent()
    if not (wq and wq.enabled ~= false and mapOpen and hasContent) then
        self.tab:Hide()
        return
    end
    self.tab:Show()
    anchorTab(self.tab)
    applyElvUISkin(self.tab)
    self:UpdateVisual()
end
