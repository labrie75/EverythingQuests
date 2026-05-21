-- Modules/Tracker/DragDrop.lua
-- Manual reorder via drag-and-drop. Active only when sort mode == "manual";
-- silently no-ops otherwise so the user doesn't accidentally lose their
-- "by zone" ordering with a stray drag.
--
-- Design: we never move the dragged block frame itself (it's anchored to the
-- scroll content; StartMoving would unanchor it and Refresh would reposition
-- it back, producing a snap-back jitter). Instead we display two helpers:
--
--   GHOST     — a small frame that follows the cursor with the dragged
--               quest's title. Owned by the subsystem; reused across drags.
--   INDICATOR — a 2px horizontal yellow line that hovers in the gap between
--               two blocks (or above the first / below the last) showing
--               where the drop will land.
--
-- On drop we walk the currently-rendered block list, compute a sequential
-- ordinal map with the dragged quest inserted at the target index, and write
-- it back to db.profile.tracker.manualOrder. The next Refresh re-sorts
-- visibly. Pool consists of one ghost + one indicator — the cheapest possible.

local _, ns = ...

local DD = ns:RegisterSubsystem("TrackerDragDrop", {})

DD.dragQuestID = nil
DD.dropIndex   = nil

-- Canonical "throttled OnUpdate" pattern for the addon. WoW fires OnUpdate
-- every visual frame (60+/s on modern hardware), but most per-frame work
-- only needs to run a handful of times per second to look smooth. We
-- accumulate `elapsed` into a file-scope counter and only run the real
-- handler when the accumulator crosses the throttle threshold — one
-- number, zero per-frame allocation, no closures created in the hot path.
-- 30 Hz is below the visible cursor-lag threshold for dragging.
local GHOST_THROTTLE_S = 1/30
local _ghostAccum      = 0

-- Hoisted to module scope: defining `function() DD:UpdateDragVisuals() end`
-- inside OnBlockDragStart would allocate a fresh closure per drag-start.
-- One handler reused across every drag instead.
local function ghostOnUpdate(_, elapsed)
    _ghostAccum = _ghostAccum + elapsed
    if _ghostAccum < GHOST_THROTTLE_S then return end
    _ghostAccum = 0
    DD:UpdateDragVisuals()
end

-- ─── Ghost / indicator factories ───────────────────────────────────────
local function ensureGhost()
    if DD.ghost then return DD.ghost end
    local g = CreateFrame("Frame", nil, UIParent)
    g:SetSize(220, 24)
    g:SetFrameStrata("TOOLTIP")
    g:Hide()

    local bg = g:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.92, 0.72, 0.02, 0.55)              -- yellow translucent

    local border = g:CreateTexture(nil, "BORDER")
    border:SetAllPoints()
    border:SetColorTexture(0.43, 0.02, 0.0, 1)              -- EQ red 1px outline (drawn behind bg)

    g.text = g:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    g.text:SetPoint("LEFT",  4, 0)
    g.text:SetPoint("RIGHT", -4, 0)
    g.text:SetJustifyH("LEFT")
    g.text:SetWordWrap(false)
    g.text:SetTextColor(1, 1, 1, 1)

    DD.ghost = g
    return g
end

local function ensureIndicator()
    if DD.indicator then return DD.indicator end
    local i = CreateFrame("Frame", nil, UIParent)
    i:SetHeight(2)
    i:SetFrameStrata("TOOLTIP")
    i:Hide()
    local t = i:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints()
    t:SetColorTexture(0.92, 0.72, 0.02, 1)                  -- bright yellow drop line
    DD.indicator = i
    return i
end

-- ─── Drag lifecycle ────────────────────────────────────────────────────
local function isManualMode()
    local DB = ns:GetSubsystem("DB")
    return DB and DB.db.profile.tracker.sortMode == "manual"
end

function DD:OnBlockDragStart(block)
    if not isManualMode() then return end
    if not block.questID then return end

    self.dragQuestID = block.questID

    local Cache = ns:GetSubsystem("Cache")
    local q = Cache and Cache:Get(block.questID)
    local title = (q and q.title) or ("Quest #" .. tostring(block.questID))

    local g = ensureGhost()
    g.text:SetText(title)
    g:Show()

    ensureIndicator():Show()

    -- Throttled OnUpdate (see GHOST_THROTTLE_S comment up top). Reset the
    -- accumulator so the first tick of this drag fires promptly.
    _ghostAccum = 0
    g:SetScript("OnUpdate", ghostOnUpdate)
end

function DD:UpdateDragVisuals()
    if not self.dragQuestID then return end
    local g = self.ghost
    if not g then return end

    -- Position ghost at cursor (cursor coords are in screen pixels; divide
    -- by effective scale to express in UIParent units).
    local cx, cy = GetCursorPosition()
    local s = g:GetEffectiveScale()
    g:ClearAllPoints()
    g:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx / s + 12, cy / s - 24)

    -- Find drop target: the first active block whose top edge is BELOW the
    -- cursor (cursor is above its top → would insert before it). If none,
    -- insertion is at the end.
    local Blocks = ns:GetSubsystem("TrackerBlocks")
    if not (Blocks and Blocks.active) then return end

    local active = Blocks.active
    local n = #active
    -- Hit-test in the BLOCKS' coordinate space, not the ghost's. Blocks sit
    -- under EQTrackerFrame (user "Tracker Scale"), so their effective scale
    -- differs from the ghost's (parented to UIParent). GetTop() pairs with
    -- a frame's OWN effective scale, so the cursor must be divided by the
    -- blocks' scale — dividing by the ghost's was the constant drop-line
    -- offset. Falls back to the ghost scale only when there are no blocks
    -- (loop doesn't run then anyway).
    local blockScale = (n > 0 and active[1]:GetEffectiveScale()) or s
    local cursorScreenY = cy / blockScale
    local targetIndex = n + 1                                -- default: insert at end
    for i = 1, n do
        local b = active[i]
        local top = b:GetTop()
        if top and cursorScreenY > top - (b:GetHeight() * 0.5) then
            -- Cursor is in the upper half of this block → insert ABOVE it
            targetIndex = i
            break
        end
    end
    self.dropIndex = targetIndex

    -- Position the insertion indicator
    local ind = self.indicator
    if not ind then return end
    ind:ClearAllPoints()
    if n == 0 then
        ind:Hide()
        return
    end
    if targetIndex <= n then
        local tgt = active[targetIndex]
        ind:SetPoint("BOTTOMLEFT",  tgt, "TOPLEFT",  0, 1)
        ind:SetPoint("BOTTOMRIGHT", tgt, "TOPRIGHT", 0, 1)
    else
        local last = active[n]
        ind:SetPoint("TOPLEFT",  last, "BOTTOMLEFT",  0, -1)
        ind:SetPoint("TOPRIGHT", last, "BOTTOMRIGHT", 0, -1)
    end
end

function DD:OnBlockDragStop()
    if self.ghost then
        self.ghost:Hide()
        self.ghost:SetScript("OnUpdate", nil)
    end
    if self.indicator then self.indicator:Hide() end

    if self.dragQuestID and self.dropIndex then
        self:Commit(self.dragQuestID, self.dropIndex)
    end
    self.dragQuestID, self.dropIndex = nil, nil
end

-- ─── Commit ────────────────────────────────────────────────────────────
-- Compute the new manualOrder map by walking the currently-active blocks in
-- their CURRENT visible order, removing the dragged quest, then splicing it
-- back in at dropIndex. Sequential ordinals (1..N) — gaps would let other
-- entries (filtered-out quests) collide ambiguously.
function DD:Commit(draggedQuestID, dropIndex)
    local DB = ns:GetSubsystem("DB")
    local Blocks = ns:GetSubsystem("TrackerBlocks")
    if not (DB and Blocks and Blocks.active) then return end

    -- Collect visible questIDs in current order, excluding the dragged one.
    local seq = {}
    for i = 1, #Blocks.active do
        local qid = Blocks.active[i].questID
        if qid and qid ~= draggedQuestID then seq[#seq + 1] = qid end
    end

    -- Splice the dragged quest back in. dropIndex was computed against the
    -- pre-removal list, so a drop "at" index N is identical to inserting at
    -- the same position in the post-removal list since we removed one item.
    local insertAt = math.min(math.max(dropIndex, 1), #seq + 1)
    table.insert(seq, insertAt, draggedQuestID)

    -- Replace manualOrder. Filtered-out quests lose their ordinal and will
    -- sort to the bottom (default 99999) when they re-appear; re-drag once
    -- to position them. Acceptable v1 trade-off — full preservation across
    -- filter changes is a polish item.
    local order = {}
    for i = 1, #seq do order[seq[i]] = i end
    DB.db.profile.tracker.manualOrder = order

    local Tracker = ns:GetSubsystem("Tracker")
    if Tracker then Tracker:Refresh() end
end

-- Called by Blocks.lua's buildBlock to wire up the drag-start/stop scripts
-- once per pooled block. The block's questID is read fresh at drag time.
function DD:WireBlock(block)
    block:RegisterForDrag("LeftButton")
    block:SetScript("OnDragStart", function(b) DD:OnBlockDragStart(b) end)
    block:SetScript("OnDragStop",  function()  DD:OnBlockDragStop()    end)
end
