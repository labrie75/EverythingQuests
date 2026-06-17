-- Modules/ChainGuide/ChainView.lua
-- Renders a single chain as a node graph: items laid out on a grid by their
-- (x, y) coords, connector lines drawn between prerequisite edges, and per-
-- item status (complete / active / turn-in / pending) shown as a Blizzard
-- atlas overlay in the node's top-left corner.
--
-- Items without explicit coords get auto-positioned: column index from the
-- node's depth in the connection graph, row index from authored order. This
-- means a legacy linear chain (items auto-built from chain.quests) renders
-- as a vertical stack with no special-casing.
--
-- The canvas lives inside a ScrollFrame so chains can be arbitrarily tall.

local _, ns = ...
local L = ns.L

local CV = ns:RegisterSubsystem("ChainGuideView", {})

local PAD            = 10
local HEADER_H       = 44
local CELL_W         = 210            -- card WIDTH (visual size of a node)
local CELL_H         = 34             -- card HEIGHT
-- GRID pitch. A column is a touch wider than a card so siblings sharing a row
-- in a parallel tier don't overlap; half-column positions (x = 0.5, 1.5) are
-- used to keep an even-width tier centred under the spine. The row pitch leaves
-- a gap below each card for the horizontal connector "bus".
local COL_PITCH      = 224            -- horizontal distance between columns
local ROW_PITCH      = 72             -- vertical distance between rows (gap holds the merge funnel)
local STATUS_ICON_PX = 14
local CONNECTOR_PX   = 3

-- Drag-to-pan tuning. Defined up here (not in the pan-handler section below)
-- because nodeOnClick's flick guard — which sits ABOVE the handlers — needs
-- PAN_CLICK_THRESH_SQ, and WHEEL_STEP keys off the cell metrics just above.
local PAN_CLICK_THRESH    = 5            -- cursor travel (px) that turns a press into a drag
local PAN_CLICK_THRESH_SQ = PAN_CLICK_THRESH * PAN_CLICK_THRESH
local WHEEL_STEP          = ROW_PITCH

-- Scratch tables reused across every Render call. wipe()d at the start of
-- each use so the table identity stays constant but contents reset. This
-- is cheaper than allocating new tables and letting them turn into garbage
-- every time the user clicks a chain or hits Back/Forward.
local _metaParts = {}
local _nodes     = {}
local _resolved  = {}                            -- [i] = variation-resolved item
local _statuses  = {}                            -- [i] = status key
local _revConn   = {}                            -- [i] = list of items that depend on i
local _chainComplete = {}                        -- [i] = true if a chain-nav node's sub-chain is fully done
local _slotLoserOf   = {}                        -- [i] = winner index when item i is a same-cell duplicate (hidden)
local _slotWinner    = {}                        -- [cellKey] = winning item index (scratch, wiped per render)

-- Status priority for the same-cell collapse in Render: keep the card the
-- player actually has (completed / in-log) over an unreachable off-faction
-- duplicate that happens to share the cell.
local function slotRank(s)
    if s == "complete" or s == "turnin" or s == "active" then return 4 end
    if s == "chainnav" then return 3 end
    if s == "pending"  then return 2 end
    return 1   -- skipped / unknown
end

local STATUS = {
    complete = { atlas = "common-icon-checkmark",                color = { 0.55, 0.55, 0.55 } },
    -- Ready to turn in: gold title so it stands out from a merely-active quest
    -- (both keep distinct atlases too — QuestTurnin "?" vs Quest-Available "!").
    turnin   = { atlas = "QuestTurnin",                          color = { 1.00, 0.82, 0.00 } },
    active   = { atlas = "Quest-Available",                      color = { 1.00, 1.00, 1.00 } },
    pending  = { atlas = nil,                                    color = { 0.78, 0.78, 0.78 } },
    -- Skipped breadcrumb: this item is still pending but a quest that
    -- *depends* on it is already active or completed, so the player passed
    -- over it. Orange to draw the eye, no atlas required (a tinted title
    -- + meta-line "N skipped" carry the signal).
    skipped  = { atlas = "common-icon-redx",                     color = { 1.00, 0.65, 0.00 } },
    chainnav = { atlas = "Garr_LevelUpgradeArrow",               color = { 0.92, 0.72, 0.02 } },
    locked   = { atlas = nil,                                    color = { 0.45, 0.45, 0.45 } },
}

CV.nodePool, CV.activeNodes = {}, {}
CV.linePool, CV.activeLines = {}, {}
CV.dotPool,  CV.activeDots  = {}, {}     -- junction-gate merge dots

-- Watches QUEST_DATA_LOAD_RESULT. Each successful load fires once, so a
-- fresh chain detail view typically generates one event per uncached quest;
-- we batch-debounce re-renders so a 16-quest chain causes one refresh, not
-- sixteen. The chain guide handles the "is it open" check itself.
function CV:OnEnable()
    local Events = ns:GetSubsystem("Events")
    if not Events then return end
    -- Coalesce the burst of QUEST_DATA_LOAD_RESULT events a fresh chain view
    -- generates (one per uncached quest) into a single re-render via the
    -- shared trailing-debounce primitive (Core/Events.lua).
    local function rerender()
        local CG = ns:GetSubsystem("ChainGuide")
        if CG and CG.frame and CG.frame:IsShown() and CG.RenderCurrent then
            CG:RenderCurrent()
        end
    end
    Events:On("QUEST_DATA_LOAD_RESULT", function()
        Events:Debounce("eq.chainview.dataload", 0.15, rerender)
    end)
end

-- ─── Atlas helper ──────────────────────────────────────────────────────
-- Mirrors the safeSetAtlas pattern from Modules/Tracker/Blocks.lua so a patch
-- that renames an atlas degrades gracefully instead of leaving a blank icon.
local function safeSetAtlas(tex, atlas)
    if not atlas then tex:SetTexture(nil); return false end
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        tex:SetAtlas(atlas, false)
        return true
    end
    tex:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
    tex:SetTexCoord(0, 1, 0, 1)
    return false
end

-- Static node scripts. Assigned further down (once the tooltip/click helpers
-- exist) and wired ONCE in buildNode; per-render data lives on node fields
-- (_navKind/_ref/_status/_chain), so re-rendering a chain never reallocates a
-- single closure. Forward-declared here because buildNode references them.
local nodeOnEnter, nodeOnLeave, nodeOnClick

-- ─── Node factory ──────────────────────────────────────────────────────
local function buildNode(parent)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(CELL_W, CELL_H)

    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0.08, 0.08, 0.08, 0.95)

    b.border = b:CreateTexture(nil, "BORDER")
    b.border:SetAllPoints()
    b.border:SetColorTexture(0.20, 0.20, 0.20, 1)

    b.inner = b:CreateTexture(nil, "ARTWORK")
    b.inner:SetPoint("TOPLEFT", 1, -1)
    b.inner:SetPoint("BOTTOMRIGHT", -1, 1)
    b.inner:SetColorTexture(0.05, 0.05, 0.05, 0.95)

    -- Compact two-line card: title line + a small "Lv N • ID M" line, with the
    -- status icon on the title row. The whole box is ~half its old height — the
    -- old layout left a big empty middle band. Both text lines are single-line
    -- (no wrap); long titles clip and the hover tooltip carries the full name.
    b.statusIcon = b:CreateTexture(nil, "OVERLAY")
    b.statusIcon:SetSize(STATUS_ICON_PX, STATUS_ICON_PX)
    b.statusIcon:SetPoint("TOPLEFT", 4, -3)

    b.title = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.title:SetPoint("TOPLEFT",  STATUS_ICON_PX + 7, -3)
    b.title:SetPoint("TOPRIGHT", -6, -3)
    b.title:SetJustifyH("LEFT")
    b.title:SetWordWrap(false)
    b.title:SetMaxLines(1)

    b.subtitle = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.subtitle:SetPoint("BOTTOMLEFT",  6, 4)
    b.subtitle:SetPoint("BOTTOMRIGHT", -6, 4)
    b.subtitle:SetJustifyH("LEFT")
    b.subtitle:SetWordWrap(false)

    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.06)

    -- Gold ring shown when the node is the target of a Quest-ID search. Sits a
    -- few px outside the node (negative-inset BACKGROUND sublevel) so it reads
    -- as an outline rather than a fill. Hidden until a search highlights it.
    b.searchGlow = b:CreateTexture(nil, "BACKGROUND", nil, -2)
    b.searchGlow:SetPoint("TOPLEFT", -3, 3)
    b.searchGlow:SetPoint("BOTTOMRIGHT", 3, -3)
    b.searchGlow:SetColorTexture(0.92, 0.72, 0.02, 0.95)
    b.searchGlow:Hide()

    b:SetScript("OnEnter", nodeOnEnter)
    b:SetScript("OnLeave", nodeOnLeave)
    b:SetScript("OnClick", nodeOnClick)

    -- Let a press that lands on a node ALSO reach the canvas beneath, so a
    -- drag-pan can start from anywhere (not just empty gaps). The node still
    -- gets its own click; nodeOnClick suppresses it when the gesture was a pan.
    if b.SetPropagateMouseClicks then b:SetPropagateMouseClicks(true) end

    return b
end

local function acquireNode(parent)
    local b = tremove(CV.nodePool)
    if not b then b = buildNode(parent) end
    b:SetParent(parent)
    b:ClearAllPoints()
    b:Show()
    CV.activeNodes[#CV.activeNodes + 1] = b
    return b
end

local function releaseNodes()
    for i = #CV.activeNodes, 1, -1 do
        local b = CV.activeNodes[i]
        b:Hide()
        b:ClearAllPoints()
        b._ref, b._chain = nil, nil          -- drop refs; static scripts stay wired
        b.statusIcon:SetTexture(nil)
        b.statusIcon:SetVertexColor(1, 1, 1, 1)
        b.border:SetColorTexture(0.20, 0.20, 0.20, 1)
        if b.searchGlow then b.searchGlow:Hide() end
        CV.nodePool[#CV.nodePool + 1] = b
        CV.activeNodes[i] = nil
    end
end

-- ─── Connector line factory ────────────────────────────────────────────
-- Uses Frame:CreateLine so we get free diagonal support — drawing connectors
-- with thin colored quads would force us to compute rotations by hand.
local function acquireLine(parent)
    local line = tremove(CV.linePool)
    if not line then
        line = parent:CreateLine(nil, "BACKGROUND")
        line:SetThickness(CONNECTOR_PX)
    else
        line:SetParent(parent)
    end
    line:Show()
    CV.activeLines[#CV.activeLines + 1] = line
    return line
end

local function releaseLines()
    for i = #CV.activeLines, 1, -1 do
        local line = CV.activeLines[i]
        line:Hide()
        line:ClearAllPoints()
        line:SetColorTexture(1, 1, 1, 1)
        CV.linePool[#CV.linePool + 1] = line
        CV.activeLines[i] = nil
    end
end

-- ─── Junction dot factory ──────────────────────────────────────────────
-- A small square marker dropped at the merge point of an all-to-all gate, so
-- the join reads as "these converge here, then split" rather than a flat bar.
local DOT_PX = 9
local function acquireDot(parent)
    local d = tremove(CV.dotPool)
    if not d then
        d = parent:CreateTexture(nil, "ARTWORK")
        d:SetSize(DOT_PX, DOT_PX)
    else
        d:SetParent(parent)
    end
    d:Show()
    CV.activeDots[#CV.activeDots + 1] = d
    return d
end

local function releaseDots()
    for i = #CV.activeDots, 1, -1 do
        local d = CV.activeDots[i]
        d:Hide()
        d:ClearAllPoints()
        CV.dotPool[#CV.dotPool + 1] = d
        CV.activeDots[i] = nil
    end
end

-- ─── Connectors (straight-line tree) ───────────────────────────────────
-- Edges are STRAIGHT lines between node centres, like a hand-drawn tree. A
-- fan-out radiates from one parent and a fan-in converges on one child, so a
-- simple branch forms a clean diamond. A true all-to-all GATE (≥2 parents each
-- feeding ≥2 children) has no single convergence node, so the render routes it
-- through a junction DOT on the midpoint row: the parents converge on the dot
-- and the dot fans out to the children — the same clean diamond shape, just with
-- a visible waist. Lines sit on the BACKGROUND layer (the opaque cards cover the
-- part that runs under them) and come from the pooled factory (no per-edge
-- table allocation); releaseLines reclaims them.

-- Connector colours: completed prereq edges recede (dim green = history); to-do
-- edges sit a touch brighter so the remaining path stands out. On a fully
-- complete chain everything is the calm dim green.
local EDGE_DONE = { 0.22, 0.42, 0.25, 0.55 }   -- completed prereq edge, dimmed
local EDGE_TODO = { 0.52, 0.52, 0.56, 0.70 }   -- not-yet-done prereq edge

local _centerX = 0    -- graph horizontal centre (the gate-dot x); set per render

local function segment(canvas, x1, y1, x2, y2, r, g, b, a)
    local line = acquireLine(canvas)
    line:SetStartPoint("TOPLEFT", canvas, x1, y1)
    line:SetEndPoint(  "TOPLEFT", canvas, x2, y2)
    line:SetColorTexture(r, g, b, a)
end

-- Pixel centre of a grid cell. Row may be fractional (a gate dot sits on the
-- midpoint row between its parent and child tiers).
local function cellCenterX(col) return col * COL_PITCH + CELL_W * 0.5 end
local function cellCenterY(row) return -(row * ROW_PITCH + CELL_H * 0.5) end

-- Is the prerequisite item at `idx` complete? (Reads the module scratch the
-- first render pass filled in; no closure, no per-edge allocation.)
local function prereqComplete(items, idx, Characters)
    if items[idx].type == "chain" then return _chainComplete[idx] end
    return Characters:IsQuestCompleted(_resolved[idx].id)
end

-- ─── Status resolution ─────────────────────────────────────────────────
local function statusForQuestItem(item, Characters)
    if Characters:IsQuestCompleted(item.id) then return "complete" end
    if Characters:IsQuestActive(item.id) then
        if C_QuestLog and C_QuestLog.IsComplete and C_QuestLog.IsComplete(item.id) then
            return "turnin"
        end
        return "active"
    end
    return "pending"
end

-- ─── Node behavior ─────────────────────────────────────────────────────
local function buildQuestTooltip(item, statusKey)
    local title = ns.Util.QuestTitle(item.id) or item.name or ("Quest #" .. tostring(item.id))
    GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR_RIGHT")
    GameTooltip:SetText(title, 1, 0.82, 0)
    if statusKey == "complete" then
        GameTooltip:AddLine(L["Completed"], 0.5, 1, 0.5)
    elseif statusKey == "turnin" then
        GameTooltip:AddLine(L["Ready to turn in"], 1, 0.82, 0)
    elseif statusKey == "active" then
        GameTooltip:AddLine(L["In your quest log"], 1, 1, 1)
    elseif statusKey == "skipped" then
        GameTooltip:AddLine(L["Skipped"], 1.0, 0.65, 0.0)
        GameTooltip:AddLine(L["A later quest in this chain has already passed this one."], 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine(L["May be worth going back to pick up."], 0.7, 0.7, 0.7, true)
    else
        GameTooltip:AddLine(L["Not started"], 0.7, 0.7, 0.7)
    end
    GameTooltip:AddLine("ID: " .. tostring(item.id), 0.5, 0.5, 0.5)

    -- Difficulty level, tinted by difficulty. GetQuestDifficultyLevel returns 0
    -- until the client has cached this quest's data (the node loop already fires
    -- RequestLoadQuestByID for uncached quests and we re-render on
    -- QUEST_DATA_LOAD_RESULT), so we only show it when > 0 — never "Level 0".
    -- GetQuestDifficultyColor is a pure function of level vs the player's level
    -- (no log/cache dependency) and hands back a SHARED, read-only {r,g,b} table.
    if item.id and C_QuestLog and C_QuestLog.GetQuestDifficultyLevel then
        local lvl = C_QuestLog.GetQuestDifficultyLevel(item.id)
        if lvl and lvl > 0 then
            local c = GetQuestDifficultyColor and GetQuestDifficultyColor(lvl)
            if c then
                GameTooltip:AddLine((L["Level %d"]):format(lvl), c.r, c.g, c.b)
            else
                GameTooltip:AddLine((L["Level %d"]):format(lvl), 0.8, 0.8, 0.8)
            end
        end
    end

    -- Narrative classification + content type, both Blizzard-localized and shown
    -- only when present. GetQuestClassificationDetails returns text for Campaign/
    -- Important/Legendary/Meta/Calling/Recurring/Questline (Normal => nil). We
    -- skip Questline: every quest in a chain IS a questline member, so that label
    -- would show on nearly every node and tell the player nothing. The content
    -- type (Dungeon/Raid/Group/Delve/PvP) comes from the quest tag. Neither can
    -- be inverted into a "this is a side quest" signal (per the API verification),
    -- so they're shown as-is, never used to restructure the layout. Same async
    -- caveat as everything else here: resolves once the quest's data is cached.
    if item.id then
        if QuestUtil and QuestUtil.GetQuestClassificationDetails then
            local cls, ctext = QuestUtil.GetQuestClassificationDetails(item.id, true)
            local isPlainStoryline = Enum and Enum.QuestClassification
                                     and cls == Enum.QuestClassification.Questline
            if ctext and ctext ~= "" and not isPlainStoryline then
                GameTooltip:AddLine(ctext, 0.90, 0.78, 0.45)
            end
        end
        if C_QuestLog and C_QuestLog.GetQuestTagInfo then
            local tag = C_QuestLog.GetQuestTagInfo(item.id)
            if tag and tag.tagName and tag.tagName ~= "" then
                GameTooltip:AddLine(tag.tagName, 0.55, 0.75, 0.95)
            end
        end
    end

    -- Cross-link from the Quest History recorder: when did the player
    -- finish this one? Fast lookup; the History subsystem maintains the
    -- map incrementally so this hover doesn't walk the SV.
    local R = ns:GetSubsystem("History")
    if R and R.GetCompletionTime then
        local t = R:GetCompletionTime(item.id)
        if t then
            if t > 0 then
                GameTooltip:AddLine("Completed: " .. date("%Y-%m-%d %H:%M", t), 0.55, 0.85, 0.55)
            else
                GameTooltip:AddLine(L["Completed (before tracking)"], 0.55, 0.85, 0.55)
            end
        end
    end

    -- Objectives + rewards (with the gear-upgrade comparison) via the shared
    -- renderers in Core/QuestRewards.lua — the same content the tracker and WQ
    -- tooltips show. Both degrade gracefully: a quest whose data isn't cached
    -- yet adds no lines, and a re-hover picks them up once the data streams in.
    local QR = ns:GetSubsystem("QuestRewards")
    if QR then
        -- Objectives carry LIVE log progress, which only exists while the quest
        -- is in your log. A completed (turned-in) quest is gone from the log, so
        -- the API reports its objectives as 0/N — which reads as "unfinished"
        -- sitting right under the green "Completed" header. Skip them for a done
        -- quest (its reward block still shows); for an in-log/not-started/skipped
        -- quest the counts are accurate, so keep them.
        if statusKey ~= "complete" then
            local hadObjectives = QR:RenderObjectives(GameTooltip, item.id)
            if hadObjectives then GameTooltip:AddLine(" ") end
        end
        QR:RenderRewards(GameTooltip, item.id)
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Shift-click to link in chat"], 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

-- Tooltip for a chain-navigation node (a "View chain >" stub that jumps to a
-- nested chain). Resolves the database fresh so the hover can be a static,
-- file-scope handler instead of a per-render closure.
local function buildChainNavTooltip(item)
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    local sub = Database and Database.chains[item.id]
    GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR_RIGHT")
    GameTooltip:SetText((sub and sub.name) or ("Chain #" .. tostring(item.id)), 0.92, 0.72, 0.02)
    if sub and sub.range then
        GameTooltip:AddLine((L["Level %d–%d"]):format(sub.range[1], sub.range[2]), 0.7, 0.7, 0.7)
    end
    GameTooltip:AddLine(L["Click to open this chain"], 1, 1, 1)
    GameTooltip:Show()
end

local function onNodeClickQuest(item, chain)
    -- Shift-click → chat link if we know the title. Plain click → drop a
    -- waypoint at the quest and open the map (Modules/ChainGuide/Waypoint).
    if IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink then
        local title = ns.Util.QuestTitle(item.id)
        if title then
            ChatEdit_InsertLink(("[%s]"):format(title))
            return
        end
    end
    local WP = ns:GetSubsystem("ChainGuideWaypoint")
    if WP and WP.GoTo then WP:GoTo(item.id, chain) end
end

local function onNodeClickChain(item)
    local CG = ns:GetSubsystem("ChainGuide")
    if CG and CG.NavigateChain then CG:NavigateChain(item.id) end
end

-- Static node scripts (forward-declared near the top). Each reads the per-render
-- data the render loop stamps onto the node, so no per-node closures allocate.
function nodeOnEnter(self)
    -- Don't pop tooltips while the player is dragging the canvas across nodes.
    local canvas = self:GetParent()
    local pane = canvas and canvas._pane
    if pane and pane._panning then return end
    if self._navKind == "chain" then
        buildChainNavTooltip(self._ref)
    else
        buildQuestTooltip(self._ref, self._status)
    end
end

function nodeOnLeave()
    GameTooltip:Hide()
end

function nodeOnClick(self)
    -- A press that turned into a drag-pan reaches here as a click too (nodes
    -- propagate the press to the canvas). Swallow it so panning across nodes
    -- never fires a stray waypoint / chain-jump. Gate the whole check on
    -- _panning — set by the press that propagated to the canvas and still set
    -- during OnClick (cleared on the following OnMouseUp) — so a stale _panMoved
    -- from a PRIOR gesture can never eat a legitimate click.
    local canvas = self:GetParent()
    local pane = canvas and canvas._pane
    if pane and pane._panning then
        if pane._panMoved then return end
        -- Sub-frame flick: OnUpdate (which sets _panMoved) may not have run
        -- between the press and this click on a heavy frame, so re-check live
        -- cursor travel from the press point (Blizzard order is OnMouseDown ->
        -- OnClick -> OnMouseUp, so _panStartX/Y are still current here).
        if pane._panStartX then
            local scale = canvas:GetEffectiveScale()
            if scale and scale ~= 0 then
                local cx, cy = GetCursorPosition()
                local tx = cx / scale - pane._panStartX
                local ty = cy / scale - pane._panStartY
                if (tx * tx + ty * ty) > PAN_CLICK_THRESH_SQ then return end
            end
        end
    end
    if self._navKind == "chain" then
        onNodeClickChain(self._ref)
    else
        onNodeClickQuest(self._ref, self._chain)
    end
end

-- "Continue" button (detail-pane header). Routes to the chain's next actionable
-- step via the same Waypoint logic a node click uses. Static handler wired once
-- in _ensureUI; the per-render target (id + chain) rides on button fields so no
-- closure allocates per render. Hidden whenever the chain has no next step.
local function onContinueClick(self)
    if not self._nextID then return end
    local WP = ns:GetSubsystem("ChainGuideWaypoint")
    if WP and WP.GoTo then WP:GoTo(self._nextID, self._chain) end
end

-- ─── Drag-to-pan ───────────────────────────────────────────────────────
-- The detail canvas lives in a ScrollFrame (vertical scrollbar only). For a
-- graph chain wider/taller than the viewport we add 2D drag panning that
-- drives SetHorizontalScroll/SetVerticalScroll directly — the widget supports
-- both axes even though UIPanelScrollFrameTemplate only ships a vertical bar.
-- Mechanics mirror Blizzard's MapCanvasScrollControllerMixin: accumulate the
-- frame-to-frame cursor delta and re-stamp the last position each OnUpdate
-- (GetCursorPosition is scale-independent, so divide by the canvas's effective
-- scale). Handlers are file-scope statics wired ONCE on the canvas; per-pane
-- state rides on canvas._pane fields so nothing allocates per render or drag,
-- and OnUpdate is only attached while a drag is live (detached on release).
-- (PAN_CLICK_THRESH / PAN_CLICK_THRESH_SQ / WHEEL_STEP are defined up top.)
local function stopPan(canvas)
    local pane = canvas._pane
    if pane then pane._panning = false end
    canvas:SetScript("OnUpdate", nil)
    if SetCursor then SetCursor(nil) end
end

local function canvasOnUpdate(self)
    local pane = self._pane
    if not (pane and pane._panning) then return end
    -- The button can be released off-frame, where OnMouseUp may never reach us;
    -- the live button state is the authoritative stop signal (Blizzard does the
    -- same in its pan controller).
    if not (IsMouseButtonDown and IsMouseButtonDown("LeftButton")) then stopPan(self); return end

    local scale = self:GetEffectiveScale()
    if not scale or scale == 0 then return end
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    local dx = cx - pane._panLastX
    local dy = cy - pane._panLastY
    pane._panLastX, pane._panLastY = cx, cy

    -- Promote the press to a drag once the cursor travels far enough, so a node
    -- click (little/no movement) still registers as a click (see nodeOnClick).
    -- On the transition, hide any tooltip left over from the pre-drag hover so
    -- it doesn't hang on screen while panning (new ones are suppressed below).
    if not pane._panMoved then
        local tx, ty = cx - pane._panStartX, cy - pane._panStartY
        if (tx * tx + ty * ty) > PAN_CLICK_THRESH_SQ then
            pane._panMoved = true
            if GameTooltip then GameTooltip:Hide() end
        end
    end

    local sc = pane._cvScroll
    if not sc then return end
    -- Grab-and-drag feel: the grabbed canvas point follows the cursor. Cursor
    -- right (dx>0) reveals content to the LEFT → horizontal offset decreases;
    -- cursor up (screen dy>0) reveals content BELOW → vertical offset increases
    -- (scroll Y grows downward while screen Y grows upward — hence the +dy).
    local hmax = sc:GetHorizontalScrollRange() or 0
    local vmax = sc:GetVerticalScrollRange()   or 0
    sc:SetHorizontalScroll(math.max(0, math.min(hmax, (sc:GetHorizontalScroll() or 0) - dx)))
    sc:SetVerticalScroll(  math.max(0, math.min(vmax, (sc:GetVerticalScroll()   or 0) + dy)))
end

local function canvasOnMouseDown(self, button)
    if button ~= "LeftButton" then return end
    local pane = self._pane
    if not pane then return end
    -- Nothing to pan when the content fits the viewport (no scroll range on
    -- either axis): bail so we don't show a grab cursor that can't move anything,
    -- and so a plain click on a small chain passes straight through (no pan, no
    -- click-swallow). Pan engages only on chains taller/wider than the pane.
    local sc = pane._cvScroll
    if not sc then return end
    if (sc:GetHorizontalScrollRange() or 0) <= 0 and (sc:GetVerticalScrollRange() or 0) <= 0 then
        return
    end
    local scale = self:GetEffectiveScale()
    if not scale or scale == 0 then return end
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    pane._panLastX,  pane._panLastY  = cx, cy
    pane._panStartX, pane._panStartY = cx, cy
    pane._panMoved = false
    pane._panning  = true
    self:SetScript("OnUpdate", canvasOnUpdate)
    if SetCursor then SetCursor("UI_MOVE_CURSOR") end
end

local function canvasOnMouseUp(self)
    if self._pane and self._pane._panning then stopPan(self) end
end

-- Safety net: if the window is hidden mid-drag (button still held), the canvas
-- stops getting OnUpdate/OnMouseUp, so the grab cursor would stay stuck globally
-- and _panning would latch. Release the pan on hide.
local function canvasOnHide(self)
    if self._pane and self._pane._panning then stopPan(self) end
end

-- Mouse wheel must be handled here: enabling mouse on the scroll child makes it
-- the mouse-focus frame, so the parent ScrollFrame template's wheel handler no
-- longer sees the event. Plain wheel scrolls vertically (as before); shift+wheel
-- pans horizontally for wide graph chains.
local function canvasOnMouseWheel(self, delta)
    local pane = self._pane
    local sc = pane and pane._cvScroll
    if not sc then return end
    if IsShiftKeyDown and IsShiftKeyDown() then
        local hmax = sc:GetHorizontalScrollRange() or 0
        sc:SetHorizontalScroll(math.max(0, math.min(hmax, (sc:GetHorizontalScroll() or 0) - delta * WHEEL_STEP)))
    else
        local vmax = sc:GetVerticalScrollRange() or 0
        sc:SetVerticalScroll(math.max(0, math.min(vmax, (sc:GetVerticalScroll() or 0) - delta * WHEEL_STEP)))
    end
end

-- ─── Layout ────────────────────────────────────────────────────────────
-- Resolve every item's (col, row): use authored x/y when present, otherwise
-- derive col from longest-prereq-chain depth and row from authored order.
local function computeLayout(items)
    local n = #items
    local cols, rows = {}, {}

    -- Precompute depth via topological walk over the connections graph.
    -- `visiting` is reused across the outer loop instead of being a fresh
    -- table per top-level call: getDepth carefully sets `visiting[i] = true`
    -- and clears it before returning, so the table is empty between calls.
    -- Previously every top-level call allocated a new throwaway table —
    -- O(N) garbage per render, multiplied across every chain-view refresh.
    local depth = {}
    local visiting = {}
    local function getDepth(i)
        if depth[i] then return depth[i] end
        if visiting[i] then return 0 end          -- guard against bad data
        visiting[i] = true
        local it = items[i]
        local d = 0
        if it.connections then
            for _, src in ipairs(it.connections) do
                if items[src] then
                    d = math.max(d, getDepth(src) + 1)
                end
            end
        end
        visiting[i] = nil
        depth[i] = d
        return d
    end
    for i = 1, n do getDepth(i) end

    local rowCursor = {}                          -- next free row per column
    local maxCol, maxRow = 0, 0
    for i = 1, n do
        local it = items[i]
        local col = it.x or depth[i] or 0
        local row = it.y
        if row == nil then
            row = rowCursor[col] or 0
            rowCursor[col] = row + 1
        end
        cols[i], rows[i] = col, row
        if col > maxCol then maxCol = col end
        if row > maxRow then maxRow = row end
    end
    return cols, rows, maxCol, maxRow
end

-- ─── Public render ─────────────────────────────────────────────────────
-- Builds header + scrollable canvas lazily on first call, then on every call
-- repopulates nodes and lines from the chain definition.
function CV:Render(pane, chain, highlightQuestID)
    self:_ensureUI(pane)
    releaseNodes()
    releaseLines()
    releaseDots()

    -- Continue button shows only when a chain has a next actionable step; hide
    -- it up front so the no-chain and empty-chain paths below leave it hidden.
    pane._cvContinue:Hide()
    pane._cvContinue._nextID, pane._cvContinue._chain = nil, nil

    -- Did this render come from a genuine navigation (a different chain, or a
    -- new search highlight), or is it one of the passive re-renders that
    -- QUEST_DATA_LOAD_RESULT fires as quest data streams in? Only the former
    -- should auto-scroll; re-scrolling on a passive re-render (e.g. after a node
    -- click opened the map and loaded data) would yank the player's scroll
    -- position away while they read. Tracked here — before the early returns —
    -- so home/empty states still update the baseline (so navigating away and
    -- back to the same chain scrolls again).
    -- A cold navigation often renders EMPTY first (questline data streams in a
    -- few hundred ms later), then re-renders the SAME chain table with items.
    -- That data-arrival render must still count as a navigation so the auto-
    -- scroll / centering fires — otherwise the chain/highlight identity matches
    -- and the NEXT node can land off-screen. _cvRenderedChain tracks the chain
    -- whose NODES were last actually drawn (set only on the success path below),
    -- so the first non-empty render of a chain always qualifies, while a passive
    -- re-render of an ALREADY-drawn chain does not (preserving the Phase-1 intent
    -- that QUEST_DATA_LOAD_RESULT re-renders never yank the player's scroll).
    local navChanged = (chain ~= pane._cvScrolledChain)
                       or (highlightQuestID ~= pane._cvScrolledHighlight)
                       or (chain ~= pane._cvRenderedChain)
    pane._cvScrolledChain     = chain
    pane._cvScrolledHighlight = highlightQuestID

    if not chain then
        pane._cvHeader:SetText("")
        pane._cvMeta:SetText(L["Pick a chain on the left to view its quests."])
        pane._cvMeta:SetTextColor(0.6, 0.6, 0.6)
        pane._cvEmpty:Hide()
        pane._cvCanvas:SetSize(1, 1)
        return
    end

    local Database   = ns:GetSubsystem("ChainGuideDatabase")
    local Characters = ns:GetSubsystem("ChainGuideCharacters")
    local QLS        = ns:GetSubsystem("ChainGuideQuestLineSource")
    if QLS then QLS:EnsureChainItems(chain) end
    Database:NormalizeChain(chain)

    local items = chain.items
    if not items or #items == 0 then
        pane._cvHeader:SetText(chain.name or "Chain")
        local complete, active, total = Characters:ChainProgress(chain)
        wipe(_metaParts)
        if chain.range then
            _metaParts[#_metaParts + 1] = (L["Level %d–%d"]):format(chain.range[1], chain.range[2])
        end
        if total > 0 then
            _metaParts[#_metaParts + 1] = (L["%d/%d done"]):format(complete, total)
            if active > 0 then _metaParts[#_metaParts + 1] = (L["%d active"]):format(active) end
        end
        pane._cvMeta:SetText(table.concat(_metaParts, "  •  "))
        pane._cvMeta:SetTextColor(0.75, 0.75, 0.75)
        pane._cvCanvas:SetSize(1, 1)
        pane._cvEmpty:Show()
        return
    end
    pane._cvEmpty:Hide()

    local cols, rows, maxCol, maxRow = computeLayout(items)
    -- The central trunk x: the horizontal centre of the laid-out grid, so a
    -- centred layout funnels its connectors straight down the spine.
    _centerX = (maxCol * 0.5) * COL_PITCH + CELL_W * 0.5
    local char = Database:CurrentCharacter()

    -- ── First pass: resolve variations and compute every item's status.
    -- Done up front so we can detect "skipped breadcrumbs" before any node
    -- renders — a status discovered in the second loop would be too late
    -- to influence the meta-line "N skipped" badge.
    wipe(_resolved)
    wipe(_statuses)
    for i = 1, #items do
        local resolved = Database:GetVariation(items[i], char)
        _resolved[i] = resolved
        if resolved.type == "chain" then
            _statuses[i] = "chainnav"
        else
            _statuses[i] = statusForQuestItem(resolved, Characters)
        end
    end

    -- ── Same-cell collapse: an API-sourced questline can carry BOTH faction
    -- versions of one step (e.g. the Horde and Alliance "Paved in Ash"), and an
    -- overlay deliberately positions them on the SAME grid cell. Drawing both
    -- stacks two cards — overlapping titles/IDs and a clashing done/skip icon.
    -- Keep exactly one card per cell (the one the player has, by slotRank) and
    -- mark the rest as losers; the node loop hides them and the connector loop
    -- skips them, so their edges collapse onto the kept node sharing the cell.
    wipe(_slotLoserOf)
    wipe(_slotWinner)
    for i = 1, #items do
        local key = rows[i] * 4096 + cols[i]
        local cur = _slotWinner[key]
        if not cur then
            _slotWinner[key] = i
        elseif slotRank(_statuses[i]) > slotRank(_statuses[cur]) then
            _slotLoserOf[cur] = i
            _slotWinner[key] = i
        else
            _slotLoserOf[i] = cur
        end
    end

    -- ── Skip detection: an item is "skipped" if it's still pending AND
    -- some item that depends on it (i.e. lists it as a prereq via
    -- `connections`) is already active or completed. Breadcrumb-flagged
    -- items are excluded because they're declared optional in the data.
    -- The reverse-connection table is rebuilt per render; cheap for the
    -- size of a single chain and only fires on chain-detail clicks.
    wipe(_revConn)
    for j = 1, #items do
        local jt = items[j]
        if jt.connections then
            for _, src in ipairs(jt.connections) do
                local list = _revConn[src]
                if not list then list = {}; _revConn[src] = list end
                list[#list + 1] = j
            end
        end
    end
    local skippedCount = 0
    for i = 1, #items do
        if _statuses[i] == "pending" and not _resolved[i].breadcrumb and not _slotLoserOf[i] then
            local consumers = _revConn[i]
            if consumers then
                for k = 1, #consumers do
                    local s = _statuses[consumers[k]]
                    if s == "complete" or s == "turnin" or s == "active" then
                        _statuses[i] = "skipped"
                        skippedCount = skippedCount + 1
                        break
                    end
                end
            end
        end
    end

    -- Meta line now that we know the skip count.
    pane._cvHeader:SetText(chain.name or "Chain")
    local complete, active, total = Characters:ChainProgress(chain)
    wipe(_metaParts)
    if chain.range then
        _metaParts[#_metaParts + 1] = (L["Level %d–%d"]):format(chain.range[1], chain.range[2])
    end
    if total > 0 then
        _metaParts[#_metaParts + 1] = (L["%d/%d done"]):format(complete, total)
        if active > 0 then _metaParts[#_metaParts + 1] = (L["%d active"]):format(active) end
        if skippedCount > 0 then
            _metaParts[#_metaParts + 1] = (L["|cffff9933%d skipped|r"]):format(skippedCount)
        end
    end
    pane._cvMeta:SetText(table.concat(_metaParts, "  •  "))
    pane._cvMeta:SetTextColor(0.75, 0.75, 0.75)

    -- The chain's next actionable step (shared source of truth with the
    -- Continue button). Matched against nodes by id, not table identity, since
    -- GetVariation can hand back a fresh table for an item with variations.
    local WP       = ns:GetSubsystem("ChainGuideWaypoint")
    local nextStep = WP and WP.NextActionableStep and WP:NextActionableStep(chain)
    local nextID   = nextStep and nextStep.id

    -- Place nodes. _nodes is a module-scoped scratch array mapping
    -- items[] index → node frame, used by the connector loop below to
    -- look up endpoints. Wiped instead of reallocated each render.
    wipe(_nodes)
    wipe(_chainComplete)
    local nodes = _nodes
    local highlightRow            -- row of the Quest-ID search target, if any
    local nextRow                 -- row of the next-actionable-step node, if any
    local highlightCol, nextCol   -- their columns, for horizontal centering on scroll
    for i = 1, #items do
        local resolved = _resolved[i]
        local node = acquireNode(pane._cvCanvas)
        node:SetPoint("TOPLEFT", pane._cvCanvas, "TOPLEFT",
            cols[i] * COL_PITCH,
            -(rows[i] * ROW_PITCH))

        local statusKey, title, subtitle
        if resolved.type == "chain" then
            local sub = Database.chains[resolved.id]
            title    = (sub and sub.name) or ("Chain #" .. tostring(resolved.id))
            statusKey = "chainnav"
            -- Surface the linked chain's live progress on the node (e.g. the
            -- Campaign overview map showing each chapter's "X/Y done"). A fully
            -- completed sub-chain switches to the grey "complete" look so the
            -- map reads at a glance. Progress is 0/0 until the sub-chain's items
            -- are populated (the category list render already does that on the
            -- way in); a passive re-render fills it once the data streams in.
            if sub then
                local sc, _, st = Characters:ChainProgress(sub)
                if st > 0 then
                    subtitle = (L["%d/%d done"]):format(sc, st)
                    if sc >= st then statusKey = "complete"; _chainComplete[i] = true end
                else
                    subtitle = "View chain >"
                end
            else
                subtitle = "View chain >"
            end
        else
            local cached = ns.Util.QuestTitle(resolved.id)   -- nil if unresolved
            -- For uncached quests, ask Blizzard to load the data; when the
            -- QUEST_DATA_LOAD_RESULT fires we re-render and the proper name
            -- will be available on the second pass.
            if (not cached) and C_QuestLog and C_QuestLog.RequestLoadQuestByID then
                C_QuestLog.RequestLoadQuestByID(resolved.id)
            end
            title = resolved.name or cached or ("Quest #" .. tostring(resolved.id))
            statusKey = _statuses[i]

            -- Subtitle: difficulty level (when cached; GetQuestDifficultyLevel
            -- returns 0 until then, so we fall back to ID-only) + the quest ID,
            -- which the search box and Wowhead guides key off. The chain's next
            -- actionable step gets a gold "NEXT" prefix — the one string concat
            -- here only ever runs for that single node per render.
            -- id is effectively always present for a quest node, but the prior
            -- code path was nil-safe (tostring), so keep that: guard the %d
            -- formats so a stray nil-id item can never throw mid-render.
            local id  = resolved.id
            local lvl = id and C_QuestLog and C_QuestLog.GetQuestDifficultyLevel
                        and C_QuestLog.GetQuestDifficultyLevel(id)
            if lvl and lvl > 0 then
                subtitle = (L["Lv %d  •  ID %d"]):format(lvl, id)
            elseif id then
                subtitle = ("ID %d"):format(id)
            else
                subtitle = ""
            end
            -- Leading tag: a quest in your log reads "ON QUEST" (cyan) so you
            -- can see at a glance what you're currently carrying; the chain's
            -- next not-yet-picked-up step reads "NEXT" (gold). In-log wins when
            -- a node is both — the gold border already marks it as next.
            if statusKey == "active" or statusKey == "turnin" then
                subtitle = "|cff4db8ff" .. L["ON QUEST"] .. "|r  •  " .. subtitle
            elseif id and nextID and id == nextID then
                subtitle = "|cffEBB706" .. L["NEXT"] .. "|r  •  " .. subtitle
            end
        end

        node.title:SetText(title)
        node.title:SetTextColor(unpack(STATUS[statusKey].color))
        node.subtitle:SetText(subtitle or ("ID " .. tostring(resolved.id)))

        if STATUS[statusKey].atlas then
            safeSetAtlas(node.statusIcon, STATUS[statusKey].atlas)
            node.statusIcon:Show()
        else
            node.statusIcon:Hide()
        end

        -- Breadcrumbs are reference-only stubs; render with a softer tint so
        -- the eye skips past them when scanning the main path.
        if resolved.breadcrumb then
            node.title:SetTextColor(0.55, 0.55, 0.40)
            node.subtitle:SetText(L["(optional)"])
        end

        -- Hover & click — the static handlers wired in buildNode read these
        -- fields, so a re-render never allocates a fresh closure per node.
        node._ref     = resolved
        node._status  = statusKey
        node._chain   = chain
        node._navKind = (resolved.type == "chain") and "chain" or "quest"

        -- Quest-ID search target: ring it and remember its row so we can scroll
        -- it into view once the canvas is sized below.
        if highlightQuestID and resolved.type ~= "chain" and resolved.id == highlightQuestID then
            node.searchGlow:Show()
            highlightRow = rows[i]
            highlightCol = cols[i]
        end

        -- Next actionable step: paint the card's border gold so it reads as
        -- "do this next", and remember its row for the auto-scroll below. (The
        -- subtitle already got its gold "NEXT" prefix when it was built above.)
        -- The node-release path resets the border to grey, so this never leaks
        -- to a pooled node.
        if nextID and resolved.type ~= "chain" and resolved.id == nextID then
            node.border:SetColorTexture(0.92, 0.72, 0.02, 1)
            nextRow = rows[i]
            nextCol = cols[i]
        end

        nodes[i] = node

        -- Same-cell duplicate (faction variant): the winning card already owns
        -- this cell, so hide this one and drop it from the connector graph — its
        -- edges resolve onto the kept node, which sits in the same cell.
        if _slotLoserOf[i] then
            node:Hide()
            nodes[i] = nil
        end
    end

    -- Connectors. First CLASSIFY each tier gap (keyed by child row): collect its
    -- distinct parents, its children, the edge count, and whether every prereq is
    -- complete. Then DRAW straight lines — direct parent→child for fans/linear
    -- (clean diamonds), or parent→dot→child through a junction dot for a true
    -- all-to-all gate. These small tables are built per on-demand render (chain
    -- navigation, not per frame), so a few short-lived tables here are fine.
    local canvas = pane._cvCanvas
    local gapParSet, gapParList, gapKidList, gapEdgeN, gapDone = {}, {}, {}, {}, {}
    for i = 1, #items do
        local it = items[i]
        if it.connections then
            local R = rows[i]
            if not gapParSet[R] then
                gapParSet[R] = {}; gapParList[R] = {}; gapKidList[R] = {}
                gapEdgeN[R] = 0; gapDone[R] = true
            end
            local pset = gapParSet[R]
            local counted = false
            for _, src in ipairs(it.connections) do
                if nodes[src] and nodes[i] then
                    if not pset[src] then
                        pset[src] = true
                        local pl = gapParList[R]; pl[#pl + 1] = src
                    end
                    gapEdgeN[R] = gapEdgeN[R] + 1
                    if not prereqComplete(items, src, Characters) then gapDone[R] = false end
                    counted = true
                end
            end
            if counted then local kl = gapKidList[R]; kl[#kl + 1] = i end
        end
    end

    for R, parList in pairs(gapParList) do
        local kidList = gapKidList[R]
        local nP, nC = #parList, #kidList
        if nP >= 2 and nC >= 2 and gapEdgeN[R] == nP * nC then
            -- All-to-all gate → one junction dot on the midpoint row; parents
            -- converge on it, it fans back out to the children.
            local dotRow = (rows[parList[1]] + R) * 0.5
            local dotX, dotY = _centerX, cellCenterY(dotRow)
            for k = 1, nP do
                local p  = parList[k]
                local pc = prereqComplete(items, p, Characters) and EDGE_DONE or EDGE_TODO
                segment(canvas, cellCenterX(cols[p]), cellCenterY(rows[p]), dotX, dotY, pc[1], pc[2], pc[3], pc[4])
            end
            local gc = gapDone[R] and EDGE_DONE or EDGE_TODO
            for k = 1, nC do
                local ch = kidList[k]
                segment(canvas, dotX, dotY, cellCenterX(cols[ch]), cellCenterY(rows[ch]), gc[1], gc[2], gc[3], gc[4])
            end
            local dot = acquireDot(canvas)
            dot:SetPoint("CENTER", canvas, "TOPLEFT", dotX, dotY)
            dot:SetColorTexture(gc[1], gc[2], gc[3], 1)
        else
            -- Fan / linear → direct straight edges, parent centre → child centre.
            for k = 1, nC do
                local ch = kidList[k]
                local cxp, cyp = cellCenterX(cols[ch]), cellCenterY(rows[ch])
                for _, src in ipairs(items[ch].connections) do
                    if nodes[src] and nodes[ch] then
                        local pc = prereqComplete(items, src, Characters) and EDGE_DONE or EDGE_TODO
                        segment(canvas, cellCenterX(cols[src]), cellCenterY(rows[src]), cxp, cyp, pc[1], pc[2], pc[3], pc[4])
                    end
                end
            end
        end
    end

    -- Size the canvas to fit the laid-out grid so the parent ScrollFrame can
    -- show scrollbars when the chain overflows the visible pane.
    -- Canvas spans the grid: last column's left edge + a full card width, last
    -- row's top + a full card height. (Grid pitch is narrower than the card, so
    -- sizing off the pitch alone would clip the rightmost/bottom cards.)
    local canvasW = maxCol * COL_PITCH + CELL_W
    local canvasH = maxRow * ROW_PITCH + CELL_H
    pane._cvCanvas:SetSize(math.max(canvasW, 1), math.max(canvasH, 1))

    -- Surface the Continue button now that we know the chain has a next step.
    -- The static OnClick reads these fields, so no closure allocates per render.
    if nextStep and nextID then
        pane._cvContinue._nextID = nextID
        pane._cvContinue._chain  = chain
        pane._cvContinue:Show()
    end

    -- Scroll the search target — or, absent a search, the next actionable step
    -- — into view, but ONLY on a genuine navigation (navChanged), never on the
    -- passive QUEST_DATA_LOAD_RESULT re-renders (see navChanged above). Deferred
    -- a frame so the scroll range reflects the canvas height we just set. A
    -- search highlight wins (the user explicitly asked for that quest). The
    -- deferred callback is a single per-pane closure built once in _ensureUI, so
    -- this allocates nothing per render (it reads pane._cvScrollY).
    -- Nodes are placed: record that THIS chain actually drew, so the next
    -- (passive) re-render of it won't re-trigger the auto-scroll, but a cold
    -- render that returned empty earlier still counts as a navigation. Only set
    -- on this success path — never in the no-chain / empty-items early returns.
    pane._cvRenderedChain = chain

    local scrollRow = highlightRow or nextRow
    -- Pair the column with whichever row won (a search highlight beats the next
    -- step), so horizontal centering targets the same node we scroll vertically.
    local scrollCol = highlightRow and highlightCol or nextCol
    if scrollRow and navChanged then
        pane._cvScrollY = scrollRow * ROW_PITCH
        pane._cvScrollX = (scrollCol or 0) * COL_PITCH
        C_Timer.After(0, pane._cvDoScroll)
    end
end

-- Lazy build of the per-pane UI scaffolding (header + scroll + canvas + empty
-- state). Done on first Render so callers don't have to know to call Build.
function CV:_ensureUI(pane)
    if pane._cvBuilt then return end
    pane._cvBuilt = true

    -- "Continue" button, top-right of the header band. Created before the
    -- header so the header can reserve room for it. Hidden until a render finds
    -- a next step. Static OnClick (onContinueClick) reads per-render fields.
    local Options = ns:GetSubsystem("Options")
    pane._cvContinue = Options:CreateYellowButton(pane, L["Continue"], onContinueClick)
    pane._cvContinue:SetSize(110, 24)
    pane._cvContinue:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -PAD, -PAD)
    pane._cvContinue:Hide()

    pane._cvHeader = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    pane._cvHeader:SetPoint("TOPLEFT",  PAD, -PAD)
    pane._cvHeader:SetPoint("TOPRIGHT", pane._cvContinue, "TOPLEFT", -8, 0)
    pane._cvHeader:SetJustifyH("LEFT")
    pane._cvHeader:SetWordWrap(false)
    pane._cvHeader:SetTextColor(1.0, 0.82, 0.0)

    pane._cvMeta = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pane._cvMeta:SetPoint("TOPLEFT",  pane._cvHeader, "BOTTOMLEFT",  0, -2)
    pane._cvMeta:SetPoint("TOPRIGHT", pane._cvHeader, "BOTTOMRIGHT", 0, -2)
    pane._cvMeta:SetJustifyH("LEFT")
    pane._cvMeta:SetTextColor(0.7, 0.7, 0.7)

    local scroll = CreateFrame("ScrollFrame", nil, pane, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     PAD, -HEADER_H)
    scroll:SetPoint("BOTTOMRIGHT", -PAD - 20, PAD)         -- reserve room for scrollbar
    pane._cvScroll = scroll

    -- Reusable deferred-scroll callback, built once per pane so Render never
    -- allocates a closure to bring the search target / next step into view. It
    -- reads pane._cvScrollY / pane._cvScrollX, which Render sets just before
    -- C_Timer.After fires. Centers the target horizontally so a wide graph
    -- chain lands the next/searched node in view rather than off the left edge.
    pane._cvDoScroll = function()
        local sc = pane._cvScroll
        if not (sc and sc:IsShown()) then return end
        -- Don't fight a pan the player started in the one-frame gap before this
        -- deferred callback fires (it would yank the view out from under them).
        if pane._panning then return end
        if sc.UpdateScrollChildRect then sc:UpdateScrollChildRect() end
        local maxv = sc:GetVerticalScrollRange() or 0
        sc:SetVerticalScroll(math.min(maxv, math.max(0, (pane._cvScrollY or 0) - 20)))
        local maxh   = sc:GetHorizontalScrollRange() or 0
        local viewW  = sc:GetWidth() or 0
        local targetX = (pane._cvScrollX or 0) - math.max(0, (viewW - CELL_W) * 0.5)
        sc:SetHorizontalScroll(math.min(maxh, math.max(0, targetX)))
    end

    local canvas = CreateFrame("Frame", nil, scroll)
    canvas:SetSize(1, 1)
    scroll:SetScrollChild(canvas)
    pane._cvCanvas = canvas

    -- Drag-to-pan + wheel: enable mouse/wheel on the scroll child and wire the
    -- file-scope static handlers. The back-ref lets those handlers reach this
    -- pane's scroll frame + drag state without per-pane closures.
    canvas._pane = pane
    canvas:EnableMouse(true)
    canvas:EnableMouseWheel(true)
    canvas:SetScript("OnMouseDown",  canvasOnMouseDown)
    canvas:SetScript("OnMouseUp",    canvasOnMouseUp)
    canvas:SetScript("OnMouseWheel", canvasOnMouseWheel)
    canvas:SetScript("OnHide",       canvasOnHide)

    -- Anchored to the pane (not the scroll child) so it stays visible even
    -- when the canvas is sized to 1x1 for chains with no items.
    pane._cvEmpty = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pane._cvEmpty:SetPoint("TOPLEFT", scroll, "TOPLEFT", PAD, -PAD)
    pane._cvEmpty:SetTextColor(0.55, 0.55, 0.55)
    pane._cvEmpty:SetText(L["(no quests defined for this chain yet)"])
    pane._cvEmpty:Hide()
end
