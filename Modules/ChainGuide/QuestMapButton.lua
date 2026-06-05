-- Modules/ChainGuide/QuestMapButton.lua
-- Tiny button on QuestMapFrame.DetailsFrame that opens EQ's Chain Guide
-- focused on the currently-viewed quest. If the quest isn't in EQ's chain
-- data (yet), falls back to a Wowhead URL in chat so the click is never
-- dead. Pure surface — no events, no allocation per render.

local _, ns = ...
local QMB = ns:RegisterSubsystem("ChainGuideQuestMapButton", {})

-- Walk the chain database for an item (or item-variation) matching the
-- given questID; return its chainID, or nil if no chain owns this quest.
--
-- Chain definitions are populated LAZILY — questline-derived and campaign-
-- derived chains aren't in Database.chains until the user opens their
-- category in the Chain Guide. To find quests anywhere, we have to walk
-- the discovery + item-population pipeline ourselves before searching.
-- Both layers are guarded by per-key idempotency flags inside the source
-- modules, so the cost is paid once per session.
local function findChainFor(questID)
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    if not (Database and Database.chains and questID) then return nil end

    local QLS = ns:GetSubsystem("ChainGuideQuestLineSource")
    local CS  = ns:GetSubsystem("ChainGuideCampaignSource")

    if Database.categories then
        for catID in pairs(Database.categories) do
            if QLS and QLS.EnsureZoneChains    then QLS:EnsureZoneChains(catID)    end
            if CS  and CS.EnsureCampaignChains then CS:EnsureCampaignChains(catID) end
        end
    end
    if QLS and QLS.EnsureChainItems then
        for _, chain in pairs(Database.chains) do
            QLS:EnsureChainItems(chain)
        end
    end

    for chainID, chain in pairs(Database.chains) do
        Database:NormalizeChain(chain)
        local items = chain.items
        if items then
            for i = 1, #items do
                local it = items[i]
                if it then
                    if it.type == "quest" and it.id == questID then
                        return chainID
                    end
                    -- Variations are faction/race/class-specific swaps —
                    -- the actual log entry for this character might be one
                    -- of them rather than the base item id.
                    local vars = it.variations
                    if vars then
                        for j = 1, #vars do
                            if vars[j].id == questID then return chainID end
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- Resolve the questID currently shown in the world-map details pane.
-- GetQuestID() (the global) is the *NPC* quest-frame helper and returns
-- 0 / nil for QuestMapFrame.DetailsFrame — try the frame-local paths
-- first, then global helpers, then the generic GetQuestID as a last
-- resort.
local function currentDetailQuestID()
    if QuestMapFrame and QuestMapFrame.DetailsFrame then
        local df = QuestMapFrame.DetailsFrame
        if df.GetCurrentQuestID then
            local q = df:GetCurrentQuestID()
            if q and q > 0 then return q end
        end
        if df.questID and df.questID > 0 then return df.questID end
    end
    if QuestMapFrame_GetDetailQuestID then
        local q = QuestMapFrame_GetDetailQuestID()
        if q and q > 0 then return q end
    end
    if GetQuestID then
        local q = GetQuestID()
        if q and q > 0 then return q end
    end
    return nil
end

local function onClick()
    local qid = currentDetailQuestID()
    if not qid then
        -- Should be rare — DetailsFrame is visible (button is parented to
        -- it) but no questID resolver returned a value. Tell the player
        -- instead of failing silently so they can re-open the details.
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffEBB706EQ Chain:|r couldn't read the displayed quest. Try clicking the quest in the list again.")
        return
    end

    local chainID = findChainFor(qid)
    if chainID then
        local CG = ns:GetSubsystem("ChainGuide")
        if CG then
            if CG.Open          then CG:Open()                end
            if CG.NavigateChain then CG:NavigateChain(chainID) end
        end
        return
    end

    -- No chain in EQ's data yet — show the Wowhead reference so the click
    -- still gives the player something useful (cmnd-/ctrl-click to select
    -- the URL in chat to copy).
    local title = ns.Util.QuestTitle(qid, true)
    local url = "https://www.wowhead.com/quest=" .. tostring(qid)
    DEFAULT_CHAT_FRAME:AddMessage(
        ("|cffEBB706EQ:|r no chain yet for |cffffffff%s|r — |cffaaccff%s|r")
        :format(title, url))
end

-- ── Button build ─────────────────────────────────────────────────────
local _button
local function ensureButton()
    if _button then return _button end
    if not (QuestMapFrame and QuestMapFrame.DetailsFrame) then return nil end

    local parent = QuestMapFrame.DetailsFrame
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(54, 20)
    -- Prefer to dock immediately left of the Abandon button (where it's
    -- visually grouped with Blizzard's own quest actions). Fall back to
    -- TOPRIGHT with an offset that clears the standard action-button row
    -- if AbandonButton isn't where we expect it.
    local abandon = parent.AbandonButton
    if abandon then
        b:SetPoint("RIGHT", abandon, "LEFT", -4, 0)
    else
        b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -36)
    end
    b:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 0) + 20)

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)

    local border = b:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.43, 0.02, 0.0, 1)                              -- brand-red 1px outline

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.10)

    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText("Chain")
    b.text:SetTextColor(0.92, 0.72, 0.02)                                   -- EQ yellow

    b:SetScript("OnClick", onClick)
    -- This button lives on the world map's DetailsFrame, so its hover is a
    -- map-side draw on the shared GameTooltip — exactly what can leave EQ taint
    -- on that singleton and trip the next AreaPOI tooltip under Midnight's
    -- secret-value rules. Use EQ's private tooltip instead (see Util.PinTooltip).
    b:SetScript("OnEnter", function(self)
        local tip = ns.Util.PinTooltip()
        tip:SetOwner(self, "ANCHOR_TOPLEFT")
        tip:SetText("Find this quest in EQ's Chain Guide", 1, 1, 1)
        tip:AddLine(
            "Falls back to a Wowhead link in chat if EQ doesn't have a chain for this quest yet.",
            0.7, 0.7, 0.7, true)
        tip:Show()
    end)
    b:SetScript("OnLeave", function() ns.Util.PinTooltip():Hide() end)

    _button = b
    return b
end

function QMB:OnEnable()
    if ensureButton() then return end
    -- DetailsFrame wasn't ready at PLAYER_LOGIN; retry once on the first
    -- world-map open. One-shot — if it still fails we give up silently
    -- (would mean a substantially refactored Blizzard quest UI).
    if WorldMapFrame and WorldMapFrame.HookScript then
        local tried
        WorldMapFrame:HookScript("OnShow", function()
            if tried then return end
            tried = true
            ensureButton()
        end)
    end
end
