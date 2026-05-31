-- Modules/Tracker/ItemButtons.lua
-- Usable quest-item buttons. For each visible quest that has a usable
-- special item (GetQuestLogSpecialItemInfo) we show a clickable
-- SecureActionButton beside its tracker block.
--
-- TAINT MODEL — the whole reason this is careful:
--   Creating, parenting, SetPoint, SetAttribute, Show or Hide on a SECURE
--   frame is FORBIDDEN while InCombatLockdown(). So every one of those is
--   routed through Events:RunWhenOutOfCombat (the shared combat-deferral
--   primitive). The closure re-reads live state, so a deferred (combat-end)
--   apply is still correct. Non-secure visuals (icon / count / cooldown)
--   are plain children and update any time.
--
-- Buttons are pooled per questID and parented to the scroll CONTENT (the
-- same frame the blocks live in), so they scroll and clip with their block
-- and the Blocks mark/sweep never touches them. Per-quest defer closures
-- are memoized so combat deferral allocates nothing after warmup.

local _, ns = ...

local IB = ns:RegisterSubsystem("TrackerItemButtons", {})

local BTN = 20                       -- button size (px), square
local RANGE_THROTTLE = 0.25          -- seconds between in-range polls (no event exists)

IB.buttons   = {}                    -- [questID] = secure button (live)
local pool   = {}                    -- free secure buttons (built out of combat)
local deferFns = {}                  -- [questID] = memoized defer closure
local wanted = {}                    -- reused scratch: questID -> true (this pass)
local stale  = {}                    -- reused scratch: array of questIDs to drop
local container                      -- frame parented to scroll content

local function getContainer()
    if container then return container end
    local Tracker = ns:GetSubsystem("Tracker")
    local content = Tracker and Tracker.frame and Tracker.frame.content
    if not content then return nil end
    container = CreateFrame("Frame", nil, content)
    container:SetAllPoints(content)
    -- Sit above the blocks (same strata, higher level) so the item button
    -- reliably receives the click instead of the block it overlaps.
    container:SetFrameLevel((content:GetFrameLevel() or 0) + 20)
    return container
end

-- questID -> link, icon, charges, logIndex when the quest has a usable
-- special item; nil otherwise. Pure read, no allocation.
local function itemInfo(questID)
    if not (C_QuestLog and C_QuestLog.GetLogIndexForQuestID
            and GetQuestLogSpecialItemInfo) then return nil end
    local idx = C_QuestLog.GetLogIndexForQuestID(questID)
    if not idx then return nil end
    local link, icon, charges = GetQuestLogSpecialItemInfo(idx)
    if link and icon then return link, icon, charges, idx end
    return nil
end

-- Range-aware icon tint. WoW exposes no "out of range" event so we poll;
-- throttled to ~4Hz with all-C internals (no allocations). OnUpdate only
-- fires while the frame is :IsShown(), so hidden / pooled buttons are free.
-- IsQuestLogSpecialItemInRange returns 0 = out, 1 = in, nil = item with no
-- range concept (treat as normal).
local function onRangeUpdate(self, elapsed)
    local t = (self._rangeTimer or 0) - elapsed
    if t > 0 then self._rangeTimer = t; return end
    self._rangeTimer = RANGE_THROTTLE

    local qid = self._questID
    if not (qid and IsQuestLogSpecialItemInRange
            and C_QuestLog and C_QuestLog.GetLogIndexForQuestID) then return end
    local idx = C_QuestLog.GetLogIndexForQuestID(qid)
    if not idx then return end
    if IsQuestLogSpecialItemInRange(idx) == 0 then
        self.icon:SetVertexColor(1.0, 0.3, 0.3)         -- red, out of range
    else
        self.icon:SetVertexColor(1.0, 1.0, 1.0)         -- normal
    end
end

-- Build a secure button. MUST be called out of combat (callers guarantee).
local function buildButton()
    local b = CreateFrame("Button", nil, container, "SecureActionButtonTemplate")
    b:SetSize(BTN, BTN)
    -- Must register BOTH down and up: a SecureActionButton registered only
    -- for "AnyUp" frequently won't fire its secure /use on click (depends on
    -- the client's down/up click-handling state). Both is the proven
    -- Blizzard pattern.
    b:RegisterForClicks("AnyDown", "AnyUp")
    b:SetAttribute("type", "item")

    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetPoint("TOPLEFT", -1, 1)
    b.bg:SetPoint("BOTTOMRIGHT", 1, -1)
    b.bg:SetColorTexture(0.43, 0.02, 0.0, 1)             -- brand-red 1px frame

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", -1, 1)

    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints()

    b:SetScript("OnUpdate", onRangeUpdate)
    b:Hide()
    return b
end

-- All SECURE state for one quest's button (create / parent / attribute /
-- point / show / hide). Forbidden in combat — callers defer this whole
-- function via the shared combat-deferral primitive when InCombatLockdown().
-- Reads live state so a deferred run at combat-end is still correct.
function IB:_applySecure(questID)
    if not getContainer() then return end
    local DB    = ns:GetSubsystem("DB")
    local on    = not DB or DB.db.profile.tracker.showItemButtons ~= false
    local link  = on and itemInfo(questID) or nil
    local Blocks = ns:GetSubsystem("TrackerBlocks")
    local block = Blocks and Blocks.byID and Blocks.byID[questID]
    local b     = self.buttons[questID]

    if not (link and block) then
        -- No item / no visible block / feature off → retire the button.
        if b then
            b:Hide()
            b:ClearAllPoints()
            b._questID    = nil
            b._rangeTimer = nil
            self.buttons[questID] = nil
            pool[#pool + 1] = b
        end
        return
    end

    if not b then
        b = tremove(pool) or buildButton()
        self.buttons[questID] = b
    end
    b._questID    = questID                              -- onRangeUpdate reads this
    b._rangeTimer = 0                                    -- force a check on first tick
    b:SetAttribute("item", link)
    b:ClearAllPoints()
    -- Anchor to the CONTAINER at the block's top-right corner, NOT to the
    -- block itself. Anchoring a secure frame onto a block pulls the block into
    -- the button's secure "anchor family", which makes the block combat-
    -- protected — and then Tracker:Render's Show/Hide/SetPoint/SetWidth on
    -- that block get blocked in combat (ADDON_ACTION_BLOCKED on Frame:Show).
    -- The container is never moved/shown/hidden in combat, so it can safely
    -- absorb the protection. container :SetAllPoints(content) and the block is
    -- a child of content, so both share the container's coordinate space; we
    -- offset by the block's position within it. (Re-applied out of combat on
    -- every Reposition, so it re-tracks the block whenever layout settles; in
    -- combat the secure SetPoint is deferred, so the button may briefly lag a
    -- moving block until combat ends — a cosmetic, self-correcting trade for
    -- never tainting the block.)
    local cl, ct = container:GetLeft(), container:GetTop()
    local br, bt = block:GetRight(), block:GetTop()
    if cl and ct and br and bt then
        b:SetPoint("TOPRIGHT", container, "TOPLEFT", (br - cl) - 4, (bt - ct) - 2)
        b:Show()
    else
        -- Block not laid out yet; retry on the next Reposition rather than
        -- risk anchoring to the block.
        b:Hide()
    end
end

-- Non-secure visual refresh (icon / charge count / cooldown). Safe any
-- time, including in combat.
local function paint(b, questID)
    local _, icon, charges, idx = itemInfo(questID)
    if not icon then return end
    b.icon:SetTexture(icon)
    if charges and charges > 1 then
        b.count:SetText(charges); b.count:Show()
    else
        b.count:SetText(""); b.count:Hide()
    end
    if idx and GetQuestLogSpecialItemCooldown then
        local s, d = GetQuestLogSpecialItemCooldown(idx)
        if s and d and d > 0 then b.cd:SetCooldown(s, d) else b.cd:Clear() end
    end
end

local function deferFn(questID)
    local f = deferFns[questID]
    if not f then
        f = function() IB:_applySecure(questID) end
        deferFns[questID] = f
    end
    return f
end

-- Run the secure apply now if safe, else coalesce it to combat-end.
local function applySecure(questID)
    local Events = ns:GetSubsystem("Events")
    if Events and Events.InCombat and Events:InCombat() then
        Events:RunWhenOutOfCombat(questID, deferFn(questID))
    else
        IB:_applySecure(questID)
    end
end

-- True once any secure item button has been built this session (live OR
-- pooled). While true, the tracker frame / scroll / content are PARENT-CHAIN
-- ancestors of a live SecureActionButton, so their SetHeight/SetSize are
-- PROTECTED frame methods and must not be called while InCombatLockdown().
-- Buttons are never destroyed -- retiring one only Hides it and returns it to
-- `pool`, still parented under `content` -- so the protection (and this flag)
-- is one-way: once true it stays true for the session. Tracker:Render reads
-- this to decide whether to defer its content/scroll resize in combat.
function IB:HasSecureButtons()
    return next(self.buttons) ~= nil or #pool > 0
end

-- Called at the very end of Tracker:Render (after Sweep), so Blocks.byID
-- reflects this pass's visible quests. Decides which quests want a button,
-- applies secure changes (now or deferred), and refreshes non-secure
-- visuals on the live ones.
function IB:Reposition()
    local Blocks = ns:GetSubsystem("TrackerBlocks")
    if not (Blocks and Blocks.byID) then return end
    local DB = ns:GetSubsystem("DB")
    local on = not DB or DB.db.profile.tracker.showItemButtons ~= false

    wipe(wanted)
    if on then
        for questID in pairs(Blocks.byID) do
            if itemInfo(questID) then wanted[questID] = true end
        end
    end

    -- Retire buttons whose quest no longer wants one (collect-then-act so
    -- we never mutate self.buttons mid-pairs).
    local n = 0
    for questID in pairs(self.buttons) do
        if not wanted[questID] then n = n + 1; stale[n] = questID end
    end
    for i = 1, n do
        applySecure(stale[i])
        stale[i] = nil
    end

    -- Show / refresh wanted quests.
    for questID in pairs(wanted) do
        applySecure(questID)
        local b = self.buttons[questID]
        if b and b:IsShown() then paint(b, questID) end
    end
end
