-- Modules/Tracker/Blocks.lua
-- Per-quest block renderer. Pools block frames so we don't churn frames on
-- every Refresh(). Each block lays out as:
--
--   [icon] Title text
--          0/4 objective one     <- progress numbers colored by state
--          1/3 objective two
--          1/1 objective three   <- complete (green)
--
-- Visual conventions match Blizzard's modern tracker as closely as we can
-- without shipping art assets: atlas icons per quest type (with safe
-- texture-path fallbacks), difficulty-colored title, in-line color escapes
-- on the X/Y progress prefix (KT pattern — one FontString, mixed colors).

local _, ns = ...

local Blocks = ns:RegisterSubsystem("TrackerBlocks", {})

Blocks.pool = {}
Blocks.active = {}

local PAD_X, PAD_Y       = 6, 4
local TITLE_TO_CAT_GAP   = 1     -- title → category subtitle
local CAT_TO_SUB_GAP     = 2     -- category → first objective
local TITLE_TO_SUB_GAP   = 2     -- title → objectives when no category present
local ICON_SIZE          = 26    -- matches KT's POI button visual (31×31 frame, ~24-26 actual icon)
local ICON_TITLE_GAP     = 4
local CATEGORY_COLOR     = { 0.42, 0.69, 1.00 }   -- KT-style light blue zone subtitle

-- Try an atlas first; if the client doesn't ship it, fall back to the given
-- texture path. Some atlases (Campaign-QuestLog-LoreBook, QuestDaily, etc.)
-- have shifted across patches; the fallback keeps the icon rendering as
-- something even if the atlas name is wrong on a given build.
local function safeSetAtlas(tex, atlas, fallbackTexture, fallbackTexCoord)
    if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        tex:SetAtlas(atlas, false)
        return true
    end
    tex:SetTexture(fallbackTexture or "Interface\\GossipFrame\\AvailableQuestIcon")
    if fallbackTexCoord then
        tex:SetTexCoord(unpack(fallbackTexCoord))
    else
        tex:SetTexCoord(0, 1, 0, 1)
    end
    return false
end

-- Resolve quest classification → POI icon atlas. KT (per their POIButton.lua)
-- uses Blizzard's native UI-QuestPoi-* atlas family, NOT the small
-- "QuestNormal" / "QuestDaily" atlases (those are minimap pin sizes; rendered
-- at 26px they look like tiny rectangles). The OuterGlow atlas family
-- contains the round colored rings + center symbols the player recognizes
-- from Blizzard's tracker — blue for recurring, purple for campaign, etc.
--
-- Note: QuestUtil.GetQuestClassificationAtlas() returns the *number* atlas
-- (UI-QuestPoi-QuestNumber), which is the small yellow rectangle a previous
-- iteration of this code used. Wrong helper for our use case.
local OUTER_GLOW = {}
local CENTER_FACE = {}
local CENTER_TURNIN = {}
do
    local QC = (Enum and Enum.QuestClassification) or {}
    local NORMAL = QC.Normal or -1

    -- Outer glow ring (drawn on BACKGROUND layer)
    OUTER_GLOW[NORMAL]                 = "UI-QuestPoi-OuterGlow"
    OUTER_GLOW[QC.Questline  or -2]    = "UI-QuestPoi-OuterGlow"
    OUTER_GLOW[QC.Campaign   or -3]    = "UI-QuestPoiCampaign-OuterGlow"
    OUTER_GLOW[QC.Calling    or -4]    = "UI-QuestPoiCampaign-OuterGlow"
    OUTER_GLOW[QC.Important  or -5]    = "UI-QuestPoiImportant-OuterGlow"
    OUTER_GLOW[QC.Legendary  or -6]    = "UI-QuestPoiLegendary-OuterGlow"
    OUTER_GLOW[QC.Recurring  or -7]    = "UI-QuestPoiRecurring-OuterGlow"
    OUTER_GLOW[QC.Meta       or -8]    = "UI-QuestPoiWrapper-OuterGlow"

    CENTER_FACE[NORMAL]                = "UI-QuestPoi-QuestNumber"
    CENTER_FACE[QC.Questline or -2]    = "UI-QuestPoi-QuestNumber"
    CENTER_FACE[QC.Campaign  or -3]    = "UI-QuestPoiCampaign-QuestNumber"
    CENTER_FACE[QC.Calling   or -4]    = "UI-QuestPoiCampaign-QuestNumber"
    CENTER_FACE[QC.Important or -5]    = "UI-QuestPoiImportant-QuestNumber"
    CENTER_FACE[QC.Legendary or -6]    = "UI-QuestPoiLegendary-QuestNumber"
    CENTER_FACE[QC.Recurring or -7]    = "UI-QuestPoiRecurring-QuestNumber"
    CENTER_FACE[QC.Meta      or -8]    = "UI-QuestPoiWrapper-QuestNumber"

    CENTER_TURNIN[NORMAL]              = "UI-QuestIcon-TurnIn-Normal"
    CENTER_TURNIN[QC.Questline or -2]  = "UI-QuestIcon-TurnIn-Normal"
    CENTER_TURNIN[QC.Campaign  or -3]  = "UI-QuestPoiCampaign-QuestBangTurnIn"
    CENTER_TURNIN[QC.Calling   or -4]  = "UI-DailyQuestPoiCampaign-QuestBangTurnIn"
    CENTER_TURNIN[QC.Important or -5]  = "UI-QuestPoiImportant-QuestBangTurnIn"
    CENTER_TURNIN[QC.Legendary or -6]  = "UI-QuestPoiLegendary-QuestBangTurnIn"
    CENTER_TURNIN[QC.Recurring or -7]  = "UI-QuestPoiRecurring-QuestBangTurnIn"
    CENTER_TURNIN[QC.Meta      or -8]  = "UI-QuestPoiWrapper-QuestBangTurnIn"
end

local function lookupClassification(table_, classification)
    local QC = (Enum and Enum.QuestClassification) or {}
    return table_[classification] or table_[QC.Normal or -1]
end

local function applyQuestIcon(iconGlow, icon, iconBang, q, focused)
    if not q then return end

    iconGlow:SetVertexColor(1, 1, 1)
    icon:SetVertexColor(1, 1, 1)
    iconBang:SetVertexColor(1, 1, 1)

    local glowAtlas = lookupClassification(OUTER_GLOW, q.classification)
    local faceAtlas = lookupClassification(CENTER_FACE, q.classification)
    if focused and faceAtlas then
        faceAtlas = faceAtlas .. "-SuperTracked"
    end

    local glowSet = safeSetAtlas(iconGlow, glowAtlas, "")
    if not glowSet then iconGlow:SetTexture(nil) end

    local faceSet = safeSetAtlas(icon, faceAtlas, "")
    if not faceSet then icon:SetTexture(nil) end

    local bangAtlas
    if q.isComplete then
        bangAtlas = lookupClassification(CENTER_TURNIN, q.classification)
    else
        bangAtlas = "Quest-In-Progress-Icon-yellow"
    end
    local bangSet = safeSetAtlas(iconBang, bangAtlas, "")
    if not bangSet then iconBang:SetTexture(nil) end
end

local function colorizeProgress(text)
    if not text or text == "" then return text end
    return (text:gsub("(%d+)%s*/%s*(%d+)", function(have, need)
        local h, n = tonumber(have), tonumber(need)
        if not (h and n) then return have .. "/" .. need end
        local color
        if h == 0          then color = "|cffff5050"
        elseif h < n       then color = "|cffeeaa00"
        else                    color = "|cff44ff44"
        end
        return color .. have .. "/" .. need .. "|r"
    end))
end

-- Build the multi-line objective string for a quest. Includes BOTH complete
-- and incomplete objectives so the user sees full progress (matches the
-- Blizzard-style tracker the user wants to emulate). Simplify mode shrinks
-- to just the first incomplete line.
local function buildSubText(questData, simplifyMode)
    local objs = questData.objectives
    if not objs or #objs == 0 then return "" end

    if simplifyMode then
        for i = 1, #objs do
            if not objs[i].finished then
                return colorizeProgress(objs[i].text or "")
            end
        end
        return "|cff44ff44" .. (objs[#objs].text or "") .. "|r"
    end

    local lines, count = {}, 0
    for i = 1, #objs do
        local o = objs[i]
        local txt = o.text or ""
        if o.finished then
            txt = "|cff44ff44" .. txt .. "|r"
        else
            txt = colorizeProgress(txt)
        end
        count = count + 1
        lines[count] = txt
    end
    return table.concat(lines, "\n", 1, count)
end

local function buildBlock()
    local b = CreateFrame("Frame")

    b.iconHolder = CreateFrame("Frame", nil, b)
    b.iconHolder:SetSize(ICON_SIZE, ICON_SIZE)

    b.iconGlow = b.iconHolder:CreateTexture(nil, "BACKGROUND")
    b.iconGlow:SetSize(50, 50)
    b.iconGlow:SetPoint("CENTER")
    b.iconGlow:SetBlendMode("ADD")

    b.icon = b.iconHolder:CreateTexture(nil, "ARTWORK", nil, 0)
    b.icon:SetSize(32, 32)
    b.icon:SetPoint("CENTER")

    b.iconBang = b.iconHolder:CreateTexture(nil, "ARTWORK", nil, 1)
    b.iconBang:SetSize(32, 32)
    b.iconBang:SetPoint("CENTER")

    b.title = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.title:SetJustifyH("LEFT")
    b.title:SetWordWrap(true)

    b.category = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.category:SetJustifyH("LEFT")
    b.category:SetWordWrap(false)
    b.category:SetTextColor(CATEGORY_COLOR[1], CATEGORY_COLOR[2], CATEGORY_COLOR[3])

    b.subText = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.subText:SetJustifyH("LEFT")
    b.subText:SetWordWrap(true)
    b.subText:SetTextColor(0.85, 0.85, 0.85)

    b:EnableMouse(true)
    b:SetScript("OnMouseUp", function(self, button)
        local wasDragging = self._wasDragging
        self._wasDragging = nil
        if wasDragging or not self.questID then return end

        if button == "RightButton" then
            local Tracker = ns:GetSubsystem("Tracker")
            if Tracker and Tracker.ShowBlockMenu then
                Tracker:ShowBlockMenu(self, self.questID)
            end
            return
        end

        if button == "LeftButton" then
            local shiftPressed = IsModifiedClick and IsModifiedClick("QUESTWATCHTOGGLE")
            if shiftPressed then
                local Tracker = ns:GetSubsystem("Tracker")
                if Tracker and Tracker.ToggleHidden then
                    Tracker:ToggleHidden(self.questID)
                end
                return
            end

            -- Open Blizzard's quest map frame to this quest's details.
            -- Blizzard_QuestLog is on-demand-loaded, so make sure it's
            -- live before calling QuestMapFrame_OpenToQuestDetails.
            if C_AddOns and C_AddOns.LoadAddOn then
                C_AddOns.LoadAddOn("Blizzard_QuestLog")
            end
            if QuestMapFrame_OpenToQuestDetails then
                QuestMapFrame_OpenToQuestDetails(self.questID)
            elseif ToggleQuestLog then
                ToggleQuestLog()
            end
        end
    end)

    local DD = ns:GetSubsystem("TrackerDragDrop")
    if DD and DD.WireBlock then DD:WireBlock(b) end

    b:HookScript("OnDragStart", function(self) self._wasDragging = true end)

    return b
end

function Blocks:Acquire(parent)
    local b = tremove(self.pool)
    if not b then b = buildBlock() end
    b:SetParent(parent)

    -- Anchor the icon HOLDER (not the textures themselves — they're already
    -- centered inside the holder). Title anchors to the holder's right edge
    -- so layout doesn't shift when atlases of varying native sizes render.
    b.iconHolder:ClearAllPoints()
    b.iconHolder:SetPoint("TOPLEFT", b, "TOPLEFT", PAD_X, -PAD_Y)

    b.title:ClearAllPoints()
    b.title:SetPoint("TOPLEFT",  b.iconHolder, "TOPRIGHT", ICON_TITLE_GAP, 1)
    b.title:SetPoint("TOPRIGHT", b, "TOPRIGHT", -PAD_X, -PAD_Y)

    b.category:ClearAllPoints()
    b.category:SetPoint("TOPLEFT",  b.title, "BOTTOMLEFT",  0, -TITLE_TO_CAT_GAP)
    b.category:SetPoint("TOPRIGHT", b.title, "BOTTOMRIGHT", 0, -TITLE_TO_CAT_GAP)

    b:Show()
    self.active[#self.active + 1] = b
    return b
end

function Blocks:ReleaseAll()
    for i = #self.active, 1, -1 do
        local b = self.active[i]
        b:Hide()
        b:ClearAllPoints()
        b:SetParent(nil)
        self.pool[#self.pool + 1] = b
        self.active[i] = nil
    end
end

function Blocks:RenderQuest(block, questData, simplifyMode)
    block.questID = questData.questID

    local focused = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
                    and C_SuperTrack.GetSuperTrackedQuestID() == questData.questID

    -- Icon: type-driven atlas with safe fallback
    applyQuestIcon(block.iconGlow, block.icon, block.iconBang, questData, focused)

    -- Title: pinned ★ + optional level prefix + title + optional quest ID
    local DB = ns:GetSubsystem("DB")
    local cfg = DB and DB.db.profile.tracker or {}
    local isPinned = DB and DB.char.pinned and DB.char.pinned[questData.questID]
    local titleText = questData.title or ("Quest #" .. tostring(questData.questID))
    if cfg.showLevelInTracker and questData.level and questData.level > 0 then
        titleText = ("[%d] %s"):format(questData.level, titleText)
    end
    if cfg.showQuestID and questData.questID then
        titleText = titleText .. (" |cff666666(#%d)|r"):format(questData.questID)
    end
    if isPinned then titleText = "|cffEBB706★|r " .. titleText end
    block.title:SetText(titleText)

    local colorByDifficulty = cfg.colorByDifficulty ~= false
    local override = cfg.titleColorOverride
    if questData.isComplete then
        block.title:SetTextColor(0.27, 0.85, 0.27)               -- green when ready to turn in
    elseif override and override.r then
        block.title:SetTextColor(override.r, override.g, override.b)
    elseif colorByDifficulty and questData.level and GetQuestDifficultyColor then
        local c = GetQuestDifficultyColor(questData.level)
        block.title:SetTextColor(c.r, c.g, c.b)
    else
        block.title:SetTextColor(0.92, 0.72, 0.02)               -- #EBB706 yellow
    end

    -- Apply user-chosen font + size from the Options panel.
    if DB then
        local Media = ns:GetSubsystem("Media")
        local fontFile = Media and Media.GetFontFile and Media:GetFontFile(DB.db.profile.tracker.font)
        local fontSize = DB.db.profile.tracker.fontSize or 12
        local outline  = DB.db.profile.tracker.fontOutline or ""
        if fontFile then
            block.title:SetFont(fontFile, fontSize, outline)
            block.subText:SetFont(fontFile, math.max(8, fontSize - 2), outline)
            block.category:SetFont(fontFile, math.max(8, fontSize - 3), outline)
        end
    end

    -- Category subtitle: q.zone is the quest log header (e.g. "Silvermoon
    -- City", "Voidstorm", "Meta Quests"). Hide when nil so the block
    -- doesn't show an empty blue gap; re-anchor subText accordingly so
    -- objectives don't end up displaced. Setting cfg.showZoneTag=false also
    -- hides the line entirely.
    local categoryText = (cfg.showZoneTag ~= false) and questData.zone or nil
    block.subText:ClearAllPoints()
    if categoryText and categoryText ~= "" then
        block.category:SetText(categoryText)
        block.category:Show()
        block.subText:SetPoint("TOPLEFT",  block.category, "BOTTOMLEFT",  0, -CAT_TO_SUB_GAP)
        block.subText:SetPoint("TOPRIGHT", block.category, "BOTTOMRIGHT", 0, -CAT_TO_SUB_GAP)
    else
        block.category:SetText("")
        block.category:Hide()
        block.subText:SetPoint("TOPLEFT",  block.title, "BOTTOMLEFT",  0, -TITLE_TO_SUB_GAP)
        block.subText:SetPoint("TOPRIGHT", block.title, "BOTTOMRIGHT", 0, -TITLE_TO_SUB_GAP)
    end

    local subText = buildSubText(questData, simplifyMode)
    -- Strip the "X/Y " progress-number prefix when showObjectiveNumbers is
    -- off. We match the colorized prefix our buildSubText emits and remove
    -- it leaving just the description, mirroring KT's hide-numbers option.
    if cfg.showObjectiveNumbers == false and subText then
        subText = subText:gsub("|c%x%x%x%x%x%x%x%x(%d+)/(%d+)|r%s*", "")
        subText = subText:gsub("(%d+)/(%d+)%s+", "")
    end
    block.subText:SetText(subText)

    -- Force a deterministic wrap width on the multi-line FontStrings.
    -- Without explicit SetWidth, GetStringHeight can return stale values
    -- on the first render after width changes, causing blocks to overlap.
    local blockW = block:GetWidth()
    if blockW and blockW > 0 then
        local titleW   = blockW - (ICON_SIZE + ICON_TITLE_GAP + PAD_X * 2)
        local subTextW = titleW
        if titleW > 0 then
            block.title:SetWidth(titleW)
            block.subText:SetWidth(subTextW)
            if block.category:IsShown() then block.category:SetWidth(titleW) end
        end
    end

    -- Auto-fit height: max(title, icon) + (category line + gap when shown) +
    -- objectives + bottom padding. Title-to-objectives gap is already part
    -- of either CAT_TO_SUB_GAP (with category) or TITLE_TO_SUB_GAP (without).
    local titleH    = math.max(block.title:GetStringHeight(), ICON_SIZE)
    local categoryH = 0
    if block.category:IsShown() then
        categoryH = TITLE_TO_CAT_GAP + block.category:GetStringHeight()
    end
    local subGap = block.category:IsShown() and CAT_TO_SUB_GAP or TITLE_TO_SUB_GAP
    local h = titleH + categoryH + subGap + block.subText:GetStringHeight() + PAD_Y * 2
    block:SetHeight(h)
end
