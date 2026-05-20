-- Modules/QuestAuto.lua
-- Auto-accept and auto-turn-in for quest dialogs. All APIs used here are
-- INSECURE (no taint risk): the gossip / quest-frame handlers are standard
-- globals and C_GossipInfo entry points.
--
-- Two independent toggles in db.profile.general:
--   autoAcceptQuests  — accept the offered quest on QUEST_DETAIL
--   autoTurnInQuests  — continue on QUEST_PROGRESS and finish on
--                       QUEST_COMPLETE *only* when there is at most one
--                       reward choice. Multi-choice reward screens are
--                       left open so the player picks.
--
-- Pause gates (either suppresses auto-action for the firing event):
--   Hold ALT during the interaction — handler reads IsAltKeyDown at the
--   moment the event fires. Useful when the player wants to read the
--   dialog or decline.
--   Recent DeclineQuest — hooksecurefunc on DeclineQuest sets a 10s
--   lockout. If the player just turned a quest down, the next gossip
--   won't re-accept it.

local _, ns = ...

local QA = ns:RegisterSubsystem("QuestAuto", {})

local DECLINE_LOCKOUT_S = 10
local _declineLockUntil = 0

local function autoAcceptOn()
    local DB = ns:GetSubsystem("DB")
    return DB and DB.db.profile.general.autoAcceptQuests == true
end
local function autoTurnInOn()
    local DB = ns:GetSubsystem("DB")
    return DB and DB.db.profile.general.autoTurnInQuests == true
end
local function paused()
    if IsAltKeyDown and IsAltKeyDown() then return true end
    return GetTime() < _declineLockUntil
end

-- ── Modern gossip path (NPCs with a gossip menu) ──────────────────────
local function onGossipShow()
    if paused() then return end
    if not C_GossipInfo then return end

    -- Turn-ins first — if the player has a completed quest with this NPC,
    -- closing the loop is higher priority than starting a new one.
    if autoTurnInOn() and C_GossipInfo.GetActiveQuests then
        local active = C_GossipInfo.GetActiveQuests()
        if active then
            for i = 1, #active do
                local q = active[i]
                if q and q.isComplete and q.questID then
                    C_GossipInfo.SelectActiveQuest(q.questID)
                    return                       -- one action per event; next event picks up the chain
                end
            end
        end
    end

    if autoAcceptOn() and C_GossipInfo.GetAvailableQuests then
        local avail = C_GossipInfo.GetAvailableQuests()
        if avail and avail[1] and avail[1].questID then
            C_GossipInfo.SelectAvailableQuest(avail[1].questID)
        end
    end
end

-- ── Old multi-quest greeting frame (NPCs without a gossip menu) ───────
local function onQuestGreeting()
    if paused() then return end

    if autoTurnInOn() and GetNumActiveQuests then
        local n = GetNumActiveQuests() or 0
        for i = 1, n do
            local _, isComplete = GetActiveTitle(i)
            if isComplete then
                SelectActiveQuest(i)
                return
            end
        end
    end

    if autoAcceptOn() and GetNumAvailableQuests then
        local n = GetNumAvailableQuests() or 0
        if n >= 1 then SelectAvailableQuest(1) end
    end
end

-- ── Quest detail (accept screen) ──────────────────────────────────────
local function onQuestDetail()
    if paused() then return end
    if autoAcceptOn() and AcceptQuest then AcceptQuest() end
end

-- ── Quest progress (the "have you done it?" continue screen) ──────────
local function onQuestProgress()
    if paused() then return end
    if not autoTurnInOn() then return end
    if IsQuestCompletable and IsQuestCompletable() and CompleteQuest then
        CompleteQuest()
    end
end

-- ── Quest complete (reward screen) ────────────────────────────────────
local function onQuestComplete()
    if paused() then return end
    if not autoTurnInOn() then return end
    if not GetQuestReward then return end

    local n = GetNumQuestChoices and GetNumQuestChoices() or 0
    if n <= 1 then
        -- 0 choices = no item reward (or fixed reward) — index 0 finishes it.
        -- 1 choice = take the only option.
        GetQuestReward(n == 1 and 1 or 0)
    end
    -- n > 1: leave the screen open. Picking the wrong loot is a real
    -- mistake; let the player decide.
end

function QA:OnEnable()
    local Events = ns:GetSubsystem("Events")
    Events:On("GOSSIP_SHOW",    onGossipShow)
    Events:On("QUEST_GREETING", onQuestGreeting)
    Events:On("QUEST_DETAIL",   onQuestDetail)
    Events:On("QUEST_PROGRESS", onQuestProgress)
    Events:On("QUEST_COMPLETE", onQuestComplete)

    -- Player-driven decline arms a brief lockout: declining means "I don't
    -- want this auto-flow right now", and the next gossip on the same NPC
    -- shouldn't immediately re-offer it.
    if hooksecurefunc and _G.DeclineQuest then
        hooksecurefunc("DeclineQuest", function()
            _declineLockUntil = GetTime() + DECLINE_LOCKOUT_S
        end)
    end
end
