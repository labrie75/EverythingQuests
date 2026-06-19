
local _, ns = ...
local L = ns.L

local CS = ns:RegisterSubsystem("ChainGuideCampaignSource", {})

local CAMPAIGN_CHAIN_OFFSET = 6000000
local CAMPAIGN_MAP_OFFSET = 7000000

CS._discovered = {}

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

    local mapItems = {}
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
        mapItems[i] = {
            type        = "chain",
            id          = chainID,
            x           = 0,
            y           = i - 1,
            connections = (i > 1) and { i - 1 } or nil,
        }
    end

    local mapChainID = CAMPAIGN_MAP_OFFSET + campaignID
    if not Database.chains[mapChainID] then
        Database:RegisterChain(mapChainID, {
            category         = catID,
            name             = L["Campaign Map"],
            items            = mapItems,
            _campaignSourced = true,
            _campaignOrder   = 0,
            _campaignMap     = true,
        })
    end

    self._discovered[catID] = true
end
