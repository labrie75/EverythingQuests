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
-- on the X/Y progress prefix (one FontString, mixed inline colors).

local _, ns = ...

local Blocks = ns:RegisterSubsystem("TrackerBlocks", {})

Blocks.pool = {}
-- active: blocks shown in the CURRENT pass, in acquire (visual top-to-
-- bottom) order. Rebuilt every pass. DragDrop walks this for hit-testing
-- and manual-order commit, so this ordering contract MUST be preserved.
Blocks.active = {}
-- byID: questID -> block, for O(1) reuse across passes. A block stays here
-- until a pass doesn't re-acquire it (mark/sweep), then it's pooled.
Blocks.byID = {}

-- Reused scratch for buildSubText's objective lines. Single-threaded and
-- never re-entrant (called once per block, sequentially, inside the render
-- loop), and table.concat below uses an explicit 1..count range so leftover
-- entries from a longer previous quest are never read — so no wipe needed.
local _subLines = {}

-- Per-pass resolution + change-detection generations.
--   _fontGen   : bumped when the resolved tracker font changes; gates the
--                per-block SetFont calls (font is quest-independent).
--   _renderGen : bumped when ANY global that affects a block's rendered
--                content changes (font OR the render-affecting cfg).
--                RenderQuest forces a full rebuild on any block whose
--                stored gen != this, so an options change repaints all.
-- Resolving font + cfg ONCE per pass here (not per block) was the hot-path
-- win; the gens + per-quest snapshot let unchanged blocks skip the rebuild.
Blocks._fontGen     = 0
Blocks._renderGen   = 0
Blocks._fontFile    = nil
Blocks._fontSize    = nil
Blocks._fontOutline = nil

-- Reused scratch for Sweep so it never allocates while collecting the
-- questIDs to free (can't safely delete from byID mid-pairs otherwise).
local _sweepScratch = {}

-- Called once per Tracker:Render, before any section renders. Resolves
-- font + render cfg for the whole pass, advances the generations on
-- change, then opens the MARK phase: every live block becomes a sweep
-- candidate and `active` is rebuilt fresh this pass (AcquireFor re-marks
-- survivors; Blocks:Sweep() at the end frees the rest).
function Blocks:BeginRenderPass()
    local DB    = ns:GetSubsystem("DB")
    local t     = DB and DB.db.profile.tracker
    local dirty = false

    -- Sampled once per pass for the "Recently Added" recency check, so
    -- RenderQuest doesn't call time() per block.
    self._nowTs = time()

    local file, size, outline
    if t then
        local Media = ns:GetSubsystem("Media")
        file    = Media and Media.GetFontFile and Media:GetFontFile(t.font)
        size    = t.fontSize or 12
        outline = t.fontOutline or ""
    end
    if file ~= self._fontFile or size ~= self._fontSize or outline ~= self._fontOutline then
        self._fontFile, self._fontSize, self._fontOutline = file, size, outline
        self._fontGen = self._fontGen + 1
        dirty = true
    end

    -- Render-affecting cfg (what RenderQuest reads from cfg that is NOT
    -- per-quest). Compared field-by-field — allocation-free.
    local cL  = t and t.showLevelInTracker     and true or false
    local cQI = t and t.showQuestID            and true or false
    local cZT = (not t) or t.showZoneTag        ~= false
    local cON = (not t) or t.showObjectiveNumbers ~= false
    local cCB = (not t) or t.colorByDifficulty  ~= false
    local cOG = (not t) or t.overrideCompleteGreen ~= false
    local tco = t and t.titleColorOverride
    local tr, tg, tb = tco and tco.r, tco and tco.g, tco and tco.b
    if cL ~= self._cL or cQI ~= self._cQI or cZT ~= self._cZT
       or cON ~= self._cON or cCB ~= self._cCB or cOG ~= self._cOG
       or tr ~= self._cTr or tg ~= self._cTg or tb ~= self._cTb then
        self._cL, self._cQI, self._cZT, self._cON, self._cCB = cL, cQI, cZT, cON, cCB
        self._cOG = cOG
        self._cTr, self._cTg, self._cTb = tr, tg, tb
        dirty = true
    end

    if dirty then self._renderGen = self._renderGen + 1 end

    -- MARK: every live block is a sweep candidate until re-acquired; the
    -- ordered `active` view is rebuilt this pass (preserves DragDrop).
    for _, b in pairs(self.byID) do b._used = false end
    wipe(self.active)
end

local PAD_X, PAD_Y       = 6, 2
local TITLE_TO_CAT_GAP   = 1     -- title → category subtitle
local CAT_TO_SUB_GAP     = 2     -- category → first objective
local TITLE_TO_SUB_GAP   = 2     -- title → objectives when no category present
local ICON_SIZE          = 26    -- reads like a Blizzard POI button (~24-26 actual icon)
local ICON_TITLE_GAP     = 4
local CATEGORY_COLOR     = { 0.42, 0.69, 1.00 }   -- light blue zone subtitle

-- "Recently Added" tag. A quest first cached within NEW_WINDOW seconds (and not
-- at login — see the firstSeen baseline in Core/Cache.lua) gets a "NEW" title
-- prefix. Prefix, not suffix, so it survives word-wrap and reads at a glance,
-- matching the pinned-star convention. Category-blue, no emoji.
local NEW_WINDOW = 3600
local NEW_TAG    = "|cff6BAFFFNEW|r "

-- Try an atlas first; if the client doesn't ship it, fall back to the given
-- texture path. Some atlases (Campaign-QuestLog-LoreBook, QuestDaily, etc.)
-- have shifted across patches; the fallback keeps the icon rendering as
-- something even if the atlas name is wrong on a given build.
-- Whether an atlas exists is constant for the session/build, but
-- safeSetAtlas runs ~3x per block per refresh. Memoize the
-- C_Texture.GetAtlasInfo result per atlas name instead of re-querying the
-- C API every render. nil / "" never resolve (treated as missing).
local _atlasOK = {}
local function atlasExists(atlas)
    if not atlas or atlas == "" then return false end
    local ok = _atlasOK[atlas]
    if ok == nil then
        ok = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)) and true or false
        _atlasOK[atlas] = ok
    end
    return ok
end

local function safeSetAtlas(tex, atlas, fallbackTexture, fallbackTexCoord)
    if atlasExists(atlas) then
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

-- Resolve quest classification → POI icon atlas. Use Blizzard's native
-- UI-QuestPoi-* atlas family, NOT the small
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

    -- q.noBang: render the bare face (the available-quest "!") with no
    -- in-progress / turn-in overlay. Used by the auto-quest popup boxes so
    -- "Quest Discovered!" always shows a "!", never a "?" that reads as a
    -- different state.
    if q.noBang then
        iconBang:SetTexture(nil)
        return
    end

    local bangAtlas
    if q.isComplete then
        bangAtlas = lookupClassification(CENTER_TURNIN, q.classification)
    else
        bangAtlas = "Quest-In-Progress-Icon-yellow"
    end
    local bangSet = safeSetAtlas(iconBang, bangAtlas, "")
    if not bangSet then iconBang:SetTexture(nil) end
end

-- Public wrapper so other tracker pieces (the auto-quest popup boxes) can
-- render the SAME crisp layered POI icon as a quest row. `q` only needs
-- .classification and .isComplete.
function Blocks:ApplyQuestIcon(iconGlow, icon, iconBang, q, focused)
    applyQuestIcon(iconGlow, icon, iconBang, q, focused)
end

-- Objective "X/Y" colorization + leading-count stripping now live in
-- Core/Util.lua (Util.ColorizeProgress / Util.StripLeadingCount) so the
-- tracker blocks and the World Quests section (Tracker/Events.lua) share ONE
-- implementation instead of two hand-synced copies. Localized here so the hot
-- render path keeps a plain local call (no per-line table lookup).
local colorizeProgress  = ns.Util.ColorizeProgress
local stripLeadingCount = ns.Util.StripLeadingCount

-- Build the multi-line objective string for a quest. Includes BOTH complete
-- and incomplete objectives so the user sees full progress (matches the
-- Blizzard-style tracker the user wants to emulate). Simplify mode shrinks
-- to just the first incomplete line.
local function buildSubText(questData, simplifyMode, hideNumbers, completeHex)
    -- Completed objective lines are green by default; completeHex (the chosen
    -- title color, when "use title color for completed quests" is on) recolors
    -- them. The checkmark icon still marks them done regardless of color.
    local done = "|cff" .. (completeHex or "44ff44")
    local objs = questData.objectives
    if not objs or #objs == 0 then
        -- No trackable leaderboard objectives (e.g. a "speak to X" quest, or a
        -- ready-to-turn-in quest with no countable goal). Without a fallback
        -- the block is a bare title with nothing underneath. Mirror Blizzard's
        -- and ElvUI's trackers: show the quest's own summary line (the turn-in
        -- / next-step direction), recolored when the quest is ready to hand in.
        local fb = questData.fallbackText
        if fb and fb ~= "" then
            if questData.isComplete then
                return "- " .. done .. fb .. "|r"
            end
            return "- " .. fb
        end
        return ""
    end

    if simplifyMode then
        for i = 1, #objs do
            if not objs[i].finished then
                local t = objs[i].text or ""
                if hideNumbers then t = stripLeadingCount(t) end
                return "- " .. colorizeProgress(t)
            end
        end
        local last = objs[#objs].text or ""
        if hideNumbers then last = stripLeadingCount(last) end
        return "|A:common-icon-checkmark:12:12|a " .. done .. last .. "|r"
    end

    local count = 0
    for i = 1, #objs do
        local o = objs[i]
        local txt = o.text or ""
        if hideNumbers then txt = stripLeadingCount(txt) end
        if o.finished then
            txt = "|A:common-icon-checkmark:12:12|a " .. done .. txt .. "|r"
        else
            txt = "- " .. colorizeProgress(txt)
        end
        count = count + 1
        _subLines[count] = txt
    end
    return table.concat(_subLines, "\n", 1, count)
end

local function buildBlock()
    local b = CreateFrame("Frame")

    b.iconHolder = CreateFrame("Frame", nil, b)
    b.iconHolder:SetSize(ICON_SIZE, ICON_SIZE)

    b.iconGlow = b.iconHolder:CreateTexture(nil, "BACKGROUND")
    b.iconGlow:SetSize(50, 50)
    b.iconGlow:SetPoint("CENTER")
    b.iconGlow:SetBlendMode("ADD")
    -- Keep the classification glow but at half strength. ADD blend means
    -- alpha scales the added light, so 0.5 = ~50% less glow. Set once
    -- here; applyQuestIcon only touches the atlas + vertex color, never
    -- alpha, so this persists across pooled-block reuse.
    b.iconGlow:SetAlpha(0.5)

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

            -- Plain left-click "focuses" the quest: super-track it so it
            -- gets the on-screen waypoint/arrow and the SuperTracked icon.
            -- Opening the quest log / details now lives on the right-click
            -- context menu (handled above); shift-left-click still toggles
            -- watch (Blizzard's QUESTWATCHTOGGLE, handled above).
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
                C_SuperTrack.SetSuperTrackedQuestID(self.questID)
                local Tracker = ns:GetSubsystem("Tracker")
                if Tracker and Tracker.Refresh then Tracker:Refresh() end
            end
        end
    end)

    local DD = ns:GetSubsystem("TrackerDragDrop")
    if DD and DD.WireBlock then DD:WireBlock(b) end

    b:HookScript("OnDragStart", function(self) self._wasDragging = true end)

    return b
end

-- Get the block for questID, reusing the one from a previous pass if it
-- still exists (the whole point of mark/sweep — its FontStrings/textures
-- survive untouched and RenderQuest can skip the rebuild). Falls back to a
-- pooled or freshly-built block. Always appends to `active` in call order
-- so `active` stays in visual top-to-bottom order for DragDrop.
function Blocks:AcquireFor(parent, questID)
    local b = self.byID[questID]
    if not b then
        b = tremove(self.pool) or buildBlock()
        b:SetParent(parent)
        -- Static child anchors (relative to the block itself; never
        -- change). Set only for a new / freshly-pooled block — a byID-
        -- reused block already has them and keeps them across passes, so
        -- re-anchoring it every refresh would be wasted layout work.
        b.iconHolder:ClearAllPoints()
        b.iconHolder:SetPoint("TOPLEFT", b, "TOPLEFT", PAD_X, -PAD_Y)
        b.title:ClearAllPoints()
        b.title:SetPoint("TOPLEFT",  b.iconHolder, "TOPRIGHT", ICON_TITLE_GAP, 1)
        b.title:SetPoint("TOPRIGHT", b, "TOPRIGHT", -PAD_X, -PAD_Y)
        b.category:ClearAllPoints()
        b.category:SetPoint("TOPLEFT",  b.title, "BOTTOMLEFT",  0, -TITLE_TO_CAT_GAP)
        b.category:SetPoint("TOPRIGHT", b.title, "BOTTOMRIGHT", 0, -TITLE_TO_CAT_GAP)
        self.byID[questID] = b
    elseif b:GetParent() ~= parent then
        b:SetParent(parent)
    end
    b.questID = questID
    b._used   = true
    b:Show()
    self.active[#self.active + 1] = b
    return b
end

-- SWEEP: pool every block not re-acquired this pass (quest turned in,
-- abandoned, filtered out, moved to a popup, or its section collapsed).
-- Collect-then-delete via reused scratch so we never mutate byID mid-pairs
-- and never allocate. Called once at the end of Tracker:Render.
function Blocks:Sweep()
    local s, n = _sweepScratch, 0
    for qid, b in pairs(self.byID) do
        if not b._used then
            n = n + 1
            s[n] = qid
        end
    end
    for i = 1, n do
        local qid = s[i]
        local b   = self.byID[qid]
        b:Hide()
        b:ClearAllPoints()
        b:SetParent(nil)
        -- Selective pool-release contract: keep all child frames + textures
        -- (so the pooled block is ready to repopulate without rebuilding),
        -- but null EVERY quest-data + per-render-snapshot field so a
        -- pooled-then-reused block can't leak prior state into the next
        -- quest's render. Adding a new _r* render-input field to RenderQuest?
        -- Add it to this list too.
        b.questID = nil
        b._used   = false
        b._rID    = nil          -- _rID nil also guarantees a full render
        b._rGen   = nil
        b._rTitle = nil
        b._rDone  = nil
        b._rLevel = nil
        b._rClass = nil
        b._rZone  = nil
        b._rPin   = nil
        b._rNew   = nil
        b._rFoc   = nil
        b._rSimp  = nil
        b._rWidth = nil
        b._rObjN  = nil
        -- _rObjT / _rObjF: kept as scratch arrays. RenderQuest overwrites
        -- indices 1..nObj before they're read; indices past nObj are never
        -- consulted.
        -- _fontGen: kept; tracks the global font generation independent of
        -- which quest this block is currently assigned to.
        self.byID[qid] = nil
        self.pool[#self.pool + 1] = b
        s[i] = nil
    end
end

function Blocks:RenderQuest(block, questData, simplifyMode)
    local qid = questData.questID
    block.questID = qid          -- always current (DragDrop reads this)

    local focused = (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
                     and C_SuperTrack.GetSuperTrackedQuestID() == qid) and true or false

    local DB  = ns:GetSubsystem("DB")
    local cfg = DB and DB.db.profile.tracker or {}
    local isPinned = (DB and DB.char.pinned and DB.char.pinned[qid]) and true or false
    -- "Recently Added": gate the showRecentlyAddedTag option INTO this value so
    -- toggling it flips _rNew and repaints instantly (no _renderGen plumbing).
    local isNew = (cfg.showRecentlyAddedTag and questData.firstSeen and questData.firstSeen > 0
                   and self._nowTs and (self._nowTs - questData.firstSeen) < NEW_WINDOW) and true or false

    -- ── Change detection ─────────────────────────────────────────────
    -- Skip the allocation-heavy content rebuild when nothing this block
    -- renders from has changed since its last full render. The caller
    -- already (re)positioned + SetWidth this block, and an unchanged
    -- block keeps its prior height, so an early return is layout-safe.
    -- Conservative: pooled reuse (_rID miss) or any global font/cfg
    -- change (_renderGen) forces a full render. All compares are
    -- value-based and allocation-free.
    local objs = questData.objectives
    local nObj = objs and #objs or 0
    local curW = block:GetWidth()
    local changed =
           block._rID    ~= qid
        or block._rGen   ~= self._renderGen
        or block._rTitle ~= questData.title
        or block._rDone  ~= (questData.isComplete and true or false)
        or block._rLevel ~= questData.level
        or block._rClass ~= questData.classification
        or block._rZone  ~= questData.zone
        or block._rPin   ~= isPinned
        or block._rNew   ~= isNew
        or block._rFoc   ~= focused
        or block._rSimp  ~= (simplifyMode and true or false)
        or block._rWidth ~= curW
        or block._rObjN  ~= nObj
    if not changed and nObj > 0 then
        local pt, pf = block._rObjT, block._rObjF
        for i = 1, nObj do
            local o = objs[i]
            if pt[i] ~= (o.text or "") or pf[i] ~= (o.finished and true or false) then
                changed = true
                break
            end
        end
    end
    if not changed then return end

    -- ── Full render ──────────────────────────────────────────────────
    -- Icon: type-driven atlas with safe fallback
    applyQuestIcon(block.iconGlow, block.icon, block.iconBang, questData, focused)

    -- Title: pinned ★ + optional level prefix + title + optional quest ID
    local titleText = questData.title or ("Quest #" .. tostring(qid))
    if cfg.showLevelInTracker and questData.level and questData.level > 0 then
        titleText = ("[%d] %s"):format(questData.level, titleText)
    end
    if cfg.showQuestID and qid then
        titleText = titleText .. (" |cff666666(#%d)|r"):format(qid)
    end
    if isPinned then titleText = "|cffEBB706★|r " .. titleText end
    if isNew    then titleText = NEW_TAG .. titleText end
    block.title:SetText(titleText)

    local colorByDifficulty = cfg.colorByDifficulty ~= false
    local override = cfg.titleColorOverride
    -- When a title color is set (e.g. the player's class color), let it win
    -- over the "complete = green" default unless they turn the option off.
    local recolorComplete = (cfg.overrideCompleteGreen ~= false)
                            and override and override.r and true or false
    if questData.isComplete and not recolorComplete then
        block.title:SetTextColor(0.27, 0.85, 0.27)               -- green when ready to turn in
    elseif override and override.r then
        block.title:SetTextColor(override.r, override.g, override.b)
    elseif colorByDifficulty and questData.level and GetQuestDifficultyColor then
        local c = GetQuestDifficultyColor(questData.level)
        block.title:SetTextColor(c.r, c.g, c.b)
    else
        block.title:SetTextColor(0.92, 0.72, 0.02)               -- #EBB706 yellow
    end

    -- Font resolved once per pass in BeginRenderPass; a block restyles only
    -- when the resolved font changed (gen bump) or it hasn't been styled
    -- yet. Font is quest-independent so this stays correct when a pooled
    -- block is reused for a different quest. _fontGen only ever increases,
    -- so a stale block's gen can never falsely match the current one.
    local fontFile = self._fontFile
    if fontFile and block._fontGen ~= self._fontGen then
        local fontSize = self._fontSize
        local outline  = self._fontOutline
        block.title:SetFont(fontFile, fontSize, outline)
        block.subText:SetFont(fontFile, math.max(8, fontSize - 2), outline)
        block.category:SetFont(fontFile, math.max(8, fontSize - 3), outline)
        block._fontGen = self._fontGen
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

    -- Hide objective numbers by omitting the count when buildSubText
    -- assembles the line — on RAW text before any color escapes exist, so
    -- (unlike the old post-hoc regex strip) it can never corrupt a |c..|r
    -- color code. showObjectiveNumbers is in the render-gen cfg snapshot,
    -- so toggling it forces a full re-render of every block.
    -- Completed objectives follow the same recolor rule as the title: the
    -- chosen color when recolorComplete is on, else the default green (nil hex).
    local completeHex
    if recolorComplete then
        completeHex = ("%02x%02x%02x"):format(
            math.floor(override.r * 255 + 0.5),
            math.floor(override.g * 255 + 0.5),
            math.floor(override.b * 255 + 0.5))
    end
    local subText = buildSubText(questData, simplifyMode,
                                 cfg.showObjectiveNumbers == false, completeHex)
    block.subText:SetText(subText)

    -- Force a deterministic wrap width on the multi-line FontStrings.
    -- Without explicit SetWidth, GetStringHeight can return stale values
    -- on the first render after width changes, causing blocks to overlap.
    local blockW = curW
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

    -- ── Snapshot the inputs this full render consumed, so the next pass
    -- can cheaply tell whether anything changed. Scalars overwrite in
    -- place; the two objective arrays are created once per block and
    -- reused (compare/snapshot only ever touch indices 1..nObj).
    block._rID    = qid
    block._rGen   = self._renderGen
    block._rTitle = questData.title
    block._rDone  = questData.isComplete and true or false
    block._rLevel = questData.level
    block._rClass = questData.classification
    block._rZone  = questData.zone
    block._rPin   = isPinned
    block._rNew   = isNew
    block._rFoc   = focused
    block._rSimp  = simplifyMode and true or false
    block._rWidth = curW
    block._rObjN  = nObj
    local pt = block._rObjT; if not pt then pt = {}; block._rObjT = pt end
    local pf = block._rObjF; if not pf then pf = {}; block._rObjF = pf end
    for i = 1, nObj do
        local o = objs[i]
        pt[i] = o.text or ""
        pf[i] = o.finished and true or false
    end
end
