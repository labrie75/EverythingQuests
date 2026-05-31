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

local CV = ns:RegisterSubsystem("ChainGuideView", {})

local PAD            = 10
local HEADER_H       = 44
local CELL_W         = 200
local CELL_H         = 52
local CELL_GAP_X     = 14
local CELL_GAP_Y     = 14
local STATUS_ICON_PX = 16
local CONNECTOR_PX   = 2

-- Scratch tables reused across every Render call. wipe()d at the start of
-- each use so the table identity stays constant but contents reset. This
-- is cheaper than allocating new tables and letting them turn into garbage
-- every time the user clicks a chain or hits Back/Forward.
local _metaParts = {}
local _nodes     = {}
local _resolved  = {}                            -- [i] = variation-resolved item
local _statuses  = {}                            -- [i] = status key
local _revConn   = {}                            -- [i] = list of items that depend on i

local STATUS = {
    complete = { atlas = "common-icon-checkmark",                color = { 0.55, 0.55, 0.55 } },
    turnin   = { atlas = "QuestTurnin",                          color = { 1.00, 1.00, 1.00 } },
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

-- Watches QUEST_DATA_LOAD_RESULT. Each successful load fires once, so a
-- fresh chain detail view typically generates one event per uncached quest;
-- we batch-debounce re-renders so a 16-quest chain causes one refresh, not
-- sixteen. The chain guide handles the "is it open" check itself.
function CV:OnEnable()
    local Events = ns:GetSubsystem("Events")
    if not Events then return end
    local pending
    Events:On("QUEST_DATA_LOAD_RESULT", function()
        if pending then return end
        pending = true
        C_Timer.After(0.15, function()
            pending = false
            local CG = ns:GetSubsystem("ChainGuide")
            if CG and CG.frame and CG.frame:IsShown() and CG.RenderCurrent then
                CG:RenderCurrent()
            end
        end)
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

    b.statusIcon = b:CreateTexture(nil, "OVERLAY")
    b.statusIcon:SetSize(STATUS_ICON_PX, STATUS_ICON_PX)
    b.statusIcon:SetPoint("TOPLEFT", 4, -4)

    b.title = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.title:SetPoint("TOPLEFT", STATUS_ICON_PX + 8, -6)
    b.title:SetPoint("BOTTOMRIGHT", -6, 18)
    b.title:SetJustifyH("LEFT")
    b.title:SetJustifyV("TOP")
    b.title:SetWordWrap(true)
    b.title:SetMaxLines(2)

    b.subtitle = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.subtitle:SetPoint("BOTTOMLEFT", 6, 4)
    b.subtitle:SetPoint("BOTTOMRIGHT", -6, 4)
    b.subtitle:SetJustifyH("LEFT")
    b.subtitle:SetWordWrap(false)

    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.06)

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
        b:SetScript("OnEnter", nil)
        b:SetScript("OnLeave", nil)
        b:SetScript("OnClick", nil)
        b.statusIcon:SetTexture(nil)
        b.statusIcon:SetVertexColor(1, 1, 1, 1)
        b.border:SetColorTexture(0.20, 0.20, 0.20, 1)
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
        GameTooltip:AddLine("Completed", 0.5, 1, 0.5)
    elseif statusKey == "turnin" then
        GameTooltip:AddLine("Ready to turn in", 1, 0.82, 0)
    elseif statusKey == "active" then
        GameTooltip:AddLine("In your quest log", 1, 1, 1)
    elseif statusKey == "skipped" then
        GameTooltip:AddLine("Skipped", 1.0, 0.65, 0.0)
        GameTooltip:AddLine("A later quest in this chain has already passed this one.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("May be worth going back to pick up.", 0.7, 0.7, 0.7, true)
    else
        GameTooltip:AddLine("Not started", 0.7, 0.7, 0.7)
    end
    GameTooltip:AddLine("ID: " .. tostring(item.id), 0.5, 0.5, 0.5)

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
                GameTooltip:AddLine("Completed (before tracking)", 0.55, 0.85, 0.55)
            end
        end
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Shift-click to link in chat", 0.6, 0.6, 0.6)
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
function CV:Render(pane, chain)
    self:_ensureUI(pane)
    releaseNodes()
    releaseLines()

    if not chain then
        pane._cvHeader:SetText("")
        pane._cvMeta:SetText("Pick a chain on the left to view its quests.")
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
            _metaParts[#_metaParts + 1] = ("Level %d–%d"):format(chain.range[1], chain.range[2])
        end
        if total > 0 then
            _metaParts[#_metaParts + 1] = ("%d/%d done"):format(complete, total)
            if active > 0 then _metaParts[#_metaParts + 1] = ("%d active"):format(active) end
        end
        pane._cvMeta:SetText(table.concat(_metaParts, "  •  "))
        pane._cvMeta:SetTextColor(0.75, 0.75, 0.75)
        pane._cvCanvas:SetSize(1, 1)
        pane._cvEmpty:Show()
        return
    end
    pane._cvEmpty:Hide()

    local cols, rows, maxCol, maxRow = computeLayout(items)
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
        if _statuses[i] == "pending" and not _resolved[i].breadcrumb then
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
        _metaParts[#_metaParts + 1] = ("Level %d–%d"):format(chain.range[1], chain.range[2])
    end
    if total > 0 then
        _metaParts[#_metaParts + 1] = ("%d/%d done"):format(complete, total)
        if active > 0 then _metaParts[#_metaParts + 1] = ("%d active"):format(active) end
        if skippedCount > 0 then
            _metaParts[#_metaParts + 1] = ("|cffff9933%d skipped|r"):format(skippedCount)
        end
    end
    pane._cvMeta:SetText(table.concat(_metaParts, "  •  "))
    pane._cvMeta:SetTextColor(0.75, 0.75, 0.75)

    -- Place nodes. _nodes is a module-scoped scratch array mapping
    -- items[] index → node frame, used by the connector loop below to
    -- look up endpoints. Wiped instead of reallocated each render.
    wipe(_nodes)
    local nodes = _nodes
    for i = 1, #items do
        local resolved = _resolved[i]
        local node = acquireNode(pane._cvCanvas)
        node:SetPoint("TOPLEFT", pane._cvCanvas, "TOPLEFT",
            cols[i] * (CELL_W + CELL_GAP_X),
            -(rows[i] * (CELL_H + CELL_GAP_Y)))

        local statusKey, title, subtitle
        if resolved.type == "chain" then
            local sub = Database.chains[resolved.id]
            title    = (sub and sub.name) or ("Chain #" .. tostring(resolved.id))
            subtitle = "View chain >"
            statusKey = "chainnav"
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
            node.subtitle:SetText("(optional)")
        end

        -- Hover & click
        local itemRef, statusRef = resolved, statusKey
        if itemRef.type == "chain" then
            node:SetScript("OnEnter", function()
                local sub = Database.chains[itemRef.id]
                GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR_RIGHT")
                GameTooltip:SetText((sub and sub.name) or ("Chain #" .. tostring(itemRef.id)), 0.92, 0.72, 0.02)
                if sub and sub.range then
                    GameTooltip:AddLine(("Level %d–%d"):format(sub.range[1], sub.range[2]), 0.7, 0.7, 0.7)
                end
                GameTooltip:AddLine("Click to open this chain", 1, 1, 1)
                GameTooltip:Show()
            end)
            node:SetScript("OnLeave", function() GameTooltip:Hide() end)
            node:SetScript("OnClick", function() onNodeClickChain(itemRef) end)
        else
            node:SetScript("OnEnter", function() buildQuestTooltip(itemRef, statusRef) end)
            node:SetScript("OnLeave", function() GameTooltip:Hide() end)
            node:SetScript("OnClick", function() onNodeClickQuest(itemRef, chain) end)
        end

        nodes[i] = node
    end

    -- Draw connectors (prereq → child). Color reflects the *prereq's* status:
    -- a completed prereq paints its outgoing edge green, otherwise gray.
    for i = 1, #items do
        local it = items[i]
        if it.connections then
            for _, src in ipairs(it.connections) do
                local from, to = nodes[src], nodes[i]
                if from and to then
                    local line = acquireLine(pane._cvCanvas)
                    line:SetStartPoint("BOTTOM",  from, 0, 0)
                    line:SetEndPoint(  "TOP",     to,   0, 0)
                    local prereq = items[src]
                    if prereq.type ~= "chain"
                       and Characters:IsQuestCompleted((Database:GetVariation(prereq, char)).id) then
                        line:SetColorTexture(0.30, 0.85, 0.30, 0.95)
                    else
                        line:SetColorTexture(0.55, 0.55, 0.55, 0.85)
                    end
                end
            end
        end
    end

    -- Size the canvas to fit the laid-out grid so the parent ScrollFrame can
    -- show scrollbars when the chain overflows the visible pane.
    local canvasW = (maxCol + 1) * CELL_W + maxCol * CELL_GAP_X
    local canvasH = (maxRow + 1) * CELL_H + maxRow * CELL_GAP_Y
    pane._cvCanvas:SetSize(math.max(canvasW, 1), math.max(canvasH, 1))
end

-- Lazy build of the per-pane UI scaffolding (header + scroll + canvas + empty
-- state). Done on first Render so callers don't have to know to call Build.
function CV:_ensureUI(pane)
    if pane._cvBuilt then return end
    pane._cvBuilt = true

    pane._cvHeader = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    pane._cvHeader:SetPoint("TOPLEFT",  PAD, -PAD)
    pane._cvHeader:SetPoint("TOPRIGHT", -PAD, -PAD)
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

    local canvas = CreateFrame("Frame", nil, scroll)
    canvas:SetSize(1, 1)
    scroll:SetScrollChild(canvas)
    pane._cvCanvas = canvas

    -- Anchored to the pane (not the scroll child) so it stays visible even
    -- when the canvas is sized to 1x1 for chains with no items.
    pane._cvEmpty = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pane._cvEmpty:SetPoint("TOPLEFT", scroll, "TOPLEFT", PAD, -PAD)
    pane._cvEmpty:SetTextColor(0.55, 0.55, 0.55)
    pane._cvEmpty:SetText("(no quests defined for this chain yet)")
    pane._cvEmpty:Hide()
end
