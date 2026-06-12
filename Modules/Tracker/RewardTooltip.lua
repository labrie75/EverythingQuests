-- Modules/Tracker/RewardTooltip.lua
-- Hover tooltip for regular (non-WQ) tracker quest rows: title, objectives, and
-- the full reward list with an inline "is this gear an upgrade?" comparison.
-- World Quest rows already get this via Modules/WorldQuests/Tooltip.lua; this
-- brings the same content (minus the WQ-only faction/time-left) to ordinary
-- quest blocks, which previously had no hover tooltip at all.
--
-- Drawn on EQ's private PinTooltip rather than the shared GameTooltip: under
-- Midnight's "secret value" system, leaving EQ's taint on the shared tooltip can
-- make the NEXT tooltip (e.g. a Blizzard AreaPOI hover) throw during layout. The
-- private frame keeps us off the shared singleton entirely. See Util.PinTooltip.

local _, ns = ...

local RT = ns:RegisterSubsystem("TrackerRewardTooltip", {})

local Util = ns.Util

-- Anchor the tooltip on whichever side of the row has room. The tracker is
-- commonly parked against the right edge of the screen, where ANCHOR_RIGHT would
-- run the tooltip off-screen; flip to the left there. Positions are converted to
-- true screen pixels (× effective scale) so the tracker's own scale doesn't skew
-- the comparison.
local function pickAnchor(owner)
    local cx = owner.GetCenter and select(1, owner:GetCenter())
    if not cx then return "ANCHOR_RIGHT" end
    local ownerPx  = cx * (owner:GetEffectiveScale() or 1)
    local screenMid = (UIParent:GetWidth() * (UIParent:GetEffectiveScale() or 1)) / 2
    return ownerPx > screenMid and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
end

-- Show the reward tooltip for `questID`, anchored to `owner` (a quest block).
function RT:Show(owner, questID)
    if not (owner and questID) then return end
    local tip = Util.PinTooltip()
    if not tip then return end

    local QR = ns:GetSubsystem("QuestRewards")
    if not QR then return end

    tip:SetOwner(owner, pickAnchor(owner))
    tip:SetText(Util.QuestTitle(questID, true) or "", 1.0, 0.82, 0.0, 1, true)

    QR:RenderObjectives(tip, questID)
    QR:RenderRewards(tip, questID)

    tip:Show()
end

function RT:Hide()
    local tip = Util.PinTooltip()
    if tip then tip:Hide() end
end
