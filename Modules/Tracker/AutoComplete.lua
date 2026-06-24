local _, ns = ...

local AC = ns:RegisterSubsystem("TrackerAutoComplete", {})

-- Fills `out` with the questIDs that currently have a COMPLETE auto-quest popup.
-- Those quests render as popup boxes (TrackerAutoQuestPopup) instead of normal
-- blocks, so the tracker uses this set to exclude them from the block list.
function AC:FillCompleteSet(out)
    wipe(out)
    if not GetNumAutoQuestPopUps then return out end
    for i = 1, GetNumAutoQuestPopUps() do
        local qid, popType = GetAutoQuestPopUp(i)
        if qid and popType == "COMPLETE" then out[qid] = true end
    end
    return out
end
