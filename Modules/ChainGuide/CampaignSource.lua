-- Modules/ChainGuide/CampaignSource.lua
-- Sources the "Midnight Campaign" category live from Blizzard's campaign API
-- (C_CampaignInfo) instead of a hand-maintained questline list.
--
-- Why this exists: the rest of the Chain Guide is questline-based, but
-- Blizzard's campaign is a cross-zone construct that does NOT line up with
-- any single questline category — a campaign quest's questline is filed
-- under its zone (e.g. "Whispers in the Twilight" → Eversong Woods), so a
-- questline-routed "Campaign" category can never reflect the real campaign.
--
-- C_CampaignInfo.GetChapterIDs returns the campaign's chapters in story
-- order. Verified in-game on Midnight (12.0): campaign 270 "Midnight" has
-- 17 chapters, and each chapter ID doubles as a questline ID — every
-- chapter's C_QuestLine.GetQuestLineQuests(chapterID) returned its quest
-- list. So we register each chapter as a chain with questlineID = chapterID
-- and the existing pipeline (QuestLineSource:EnsureChainItems →
-- C_QuestLine.GetQuestLineQuests, Characters:ChainProgress) populates and
-- scores it with no special-casing.
--
-- Chains carry `_campaignOrder` (1..N) so Frame.lua renders the chapter
-- spine in story order instead of alphabetically.

local _, ns = ...

local CS = ns:RegisterSubsystem("ChainGuideCampaignSource", {})

-- Disjoint from QuestLineSource's 5000000 offset (and from hand-authored
-- low IDs) so a questline that is BOTH a campaign chapter and zone content
-- (e.g. 5719 "Whispers in the Twilight" → Eversong Woods zone chain AND
-- Campaign chapter 2) gets two independent chain entries keyed by distinct
-- chainIDs instead of one silently clobbering the other in Database.chains.
local CAMPAIGN_CHAIN_OFFSET = 6000000

CS._discovered = {}        -- [categoryID] = true (one successful pass)

-- Drop everything we sourced so a global rediscover (QuestLineSource:Reset)
-- also refreshes the campaign spine.
function CS:Reset()
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    if Database then
        for chainID, chain in pairs(Database.chains) do
            if chain._campaignSourced then Database.chains[chainID] = nil end
        end
    end
    self._discovered = {}
    self._chapterSet = nil
end

-- True if `qlID` is a chapter of ANY registered campaign category. Used by
-- QuestLineSource to keep a campaign-chapter questline out of its zone
-- category — it lives solely under its campaign (the authoritative,
-- story-ordered spine), instead of being listed twice. Set is built once
-- (lazily, memoized) from every category def that carries a campaignID,
-- so it's correct regardless of which category the user opens first.
function CS:IsChapterQuestline(qlID)
    if self._chapterSet == nil then
        local set = false
        if C_CampaignInfo and C_CampaignInfo.GetChapterIDs then
            local Database = ns:GetSubsystem("ChainGuideDatabase")
            if Database then
                set = {}
                for _, cat in pairs(Database.categories) do
                    if cat.campaignID then
                        local ch = C_CampaignInfo.GetChapterIDs(cat.campaignID)
                        if ch then
                            for _, id in ipairs(ch) do set[id] = true end
                        end
                    end
                end
            end
        end
        self._chapterSet = set
    end
    return (self._chapterSet and self._chapterSet[qlID]) or false
end

-- Resolve the campaign ID for a category. Primary: the static `campaignID`
-- on the category def (Data/QuestChains/_Index.lua) — a stable WoW-global
-- ID, the same convention as the hardcoded questline IDs already littering
-- the data files. Fallback: the player's active campaign, found by scanning
-- the quest log for the first quest C_CampaignInfo flags as a campaign
-- quest (keeps working if Blizzard ever renumbers the campaign).
local function resolveCampaignID(cat)
    if cat and cat.campaignID then return cat.campaignID end
    if not (C_CampaignInfo and C_CampaignInfo.GetCampaignID
            and C_CampaignInfo.IsCampaignQuest and C_QuestLog
            and C_QuestLog.GetNumQuestLogEntries) then
        return nil
    end
    local n = C_QuestLog.GetNumQuestLogEntries() or 0
    for i = 1, n do
        local info = C_QuestLog.GetInfo and C_QuestLog.GetInfo(i)
        local qid  = info and (not info.isHeader) and info.questID
        if qid and C_CampaignInfo.IsCampaignQuest(qid) then
            local cid = C_CampaignInfo.GetCampaignID(qid)
            if cid and cid > 0 then return cid end
        end
    end
    return nil
end

-- Register every chapter of the category's campaign as a chain, in the
-- order C_CampaignInfo returns them. No-op after the first successful pass
-- for a category (guarded by _discovered, like QuestLineSource).
function CS:EnsureCampaignChains(catID)
    if self._discovered[catID] then return end
    if not (C_CampaignInfo and C_CampaignInfo.GetChapterIDs) then return end

    local Database = ns:GetSubsystem("ChainGuideDatabase")
    local cat = Database and Database.categories[catID]
    if not cat then return end

    local campaignID = resolveCampaignID(cat)
    if not campaignID then return end

    local chapters = C_CampaignInfo.GetChapterIDs(campaignID)
    if not chapters or #chapters == 0 then return end

    for i = 1, #chapters do
        local chapterID = chapters[i]
        local chainID   = CAMPAIGN_CHAIN_OFFSET + chapterID
        if not Database.chains[chainID] then
            local ci = C_CampaignInfo.GetCampaignChapterInfo
                       and C_CampaignInfo.GetCampaignChapterInfo(chapterID)
            Database:RegisterChain(chainID, {
                category         = catID,
                name             = (ci and ci.name) or ("Chapter " .. i),
                -- On 12.0 a campaign chapter ID *is* a questline ID;
                -- QuestLineSource:EnsureChainItems fills items[] from
                -- C_QuestLine.GetQuestLineQuests(questlineID).
                questlineID      = chapterID,
                items            = {},
                _campaignSourced = true,
                _campaignOrder   = i,
            })
        end
    end

    self._discovered[catID] = true
end
