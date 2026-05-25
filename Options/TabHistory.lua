-- Options/TabHistory.lua
-- "History" tab in the Options window. Controls:
--   • Master enable toggle
--   • Retention size slider (0 = unlimited)
--   • "Open Quest History" button — pops the standalone history window
--   • "Populate from past completions" — manual backfill button per char
--   • "Wipe history" — destructive, gated by a static-popup confirmation

local _, ns = ...

ns:GetSubsystem("Options"):AddTab("history", "History", function(content)
    local Options = ns:GetSubsystem("Options")

    local function historySetting(key)
        return
            function()
                local DB = ns:GetSubsystem("DB")
                return DB and DB.db.profile.history[key]
            end,
            function(value)
                local DB = ns:GetSubsystem("DB")
                if DB then DB.db.profile.history[key] = value end
            end
    end

    local h = Options:CreateSectionHeader(content, "Quest History")
    h:SetPoint("TOPLEFT", 8, -8)

    local enaGet, enaSet = historySetting("enabled")
    local ena = Options:CreateCheckbox(content,
        "Record completed quests",
        enaGet, enaSet)
    ena:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -16)

    local enaHint = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    enaHint:SetPoint("TOPLEFT", ena, "BOTTOMLEFT", 0, -2)
    enaHint:SetWidth(440)
    enaHint:SetJustifyH("LEFT")
    enaHint:SetText("When on, Everything Quests writes an entry to your account-wide quest history every time you turn in a quest. The data is shared across all of your characters; the history window can filter by character.")

    -- Retention slider (200..10000 step 200; 0 means unlimited, set via a
    -- separate "unlimited" checkbox below the slider for clarity).
    local function retGet()
        local DB = ns:GetSubsystem("DB")
        return (DB and DB.db.profile.history.retention) or 5000
    end
    local function retSet(value)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.history.retention = value end
    end
    local retLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    retLabel:SetPoint("TOPLEFT", enaHint, "BOTTOMLEFT", 0, -16)
    retLabel:SetText("Maximum entries kept")

    local retSlider
    if Options.CreateSlider then
        retSlider = Options:CreateSlider(content, nil, 200, 10000, 200, retGet, retSet)
        retSlider:SetPoint("TOPLEFT", retLabel, "BOTTOMLEFT", 0, -8)
        retSlider:SetWidth(300)
    end

    local retHint = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    retHint:SetPoint("TOPLEFT", retSlider or retLabel, "BOTTOMLEFT", 0, -8)
    retHint:SetWidth(440)
    retHint:SetJustifyH("LEFT")
    retHint:SetText("When the history grows past this many entries, the oldest ones are dropped. Set higher if you want a longer record, lower to save disk space. 5000 entries is enough for several months of heavy questing.")

    -- ─── Actions ────────────────────────────────────────────────────────
    local openBtn = Options:CreateYellowButton(content, "Open Quest History", function()
        local HF = ns:GetSubsystem("HistoryFrame")
        if HF and HF.Open then HF:Open() end
    end)
    openBtn:SetSize(200, 24)
    openBtn:SetPoint("TOPLEFT", retHint, "BOTTOMLEFT", 0, -20)

    local backfillBtn = Options:CreateYellowButton(content, "Populate from past completions", function()
        local R = ns:GetSubsystem("History")
        if not (R and R.Backfill) then return end
        local added = R:Backfill()
        local name = R.CurrentCharacter and R:CurrentCharacter() or "this character"
        print(("|cffEBB706EQ History:|r added %d past completion%s for |cffffffff%s|r (no dates)."):format(
            added, added == 1 and "" or "s", name))
    end)
    backfillBtn:SetSize(280, 24)
    backfillBtn:SetPoint("TOPLEFT", openBtn, "BOTTOMLEFT", 0, -10)

    local backfillHint = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    backfillHint:SetPoint("TOPLEFT", backfillBtn, "BOTTOMLEFT", 0, -2)
    backfillHint:SetWidth(440)
    backfillHint:SetJustifyH("LEFT")
    backfillHint:SetText("One-time per character: walks the list of quests this character has completed (according to the game's own record) and adds any that aren't already in your history. Entries created this way have no date — the game doesn't tell us when they happened.")

    local rescanBtn = Options:CreateYellowButton(content, "Re-scan for quest names", function()
        local R = ns:GetSubsystem("History")
        if not R then return end
        local queued = R:RequestMissingTitles() or 0
        if queued > 0 then
            print(("|cffEBB706EQ History:|r requested %d quest name%s from the server. Names will fill in over the next minute or two."):format(
                queued, queued == 1 and "" or "s"))
        else
            print("|cffEBB706EQ History:|r nothing left to look up — every entry that can be resolved already is.")
        end
    end)
    rescanBtn:SetSize(280, 24)
    rescanBtn:SetPoint("TOPLEFT", backfillHint, "BOTTOMLEFT", 0, -16)

    local rescanHint = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rescanHint:SetPoint("TOPLEFT", rescanBtn, "BOTTOMLEFT", 0, -2)
    rescanHint:SetWidth(440)
    rescanHint:SetJustifyH("LEFT")
    rescanHint:SetText("Some quests in the backfilled history show up as \"Quest #12345\" because Blizzard hasn't sent the client their name yet. This button asks the server for every missing one. Quests the server flatly has no data for (retired or internal IDs) will keep their numeric placeholder.")

    local wipeBtn = Options:CreateYellowButton(content, "Wipe history", function()
        local Dialog = ns:GetSubsystem("Dialog")
        if not Dialog then return end
        Dialog:Show({
            title   = "Everything Quests",
            text    = "Delete ALL recorded quest history (every character)? This cannot be undone.",
            button1 = "Wipe",
            button2 = "Cancel",
            onAccept = function()
                local R = ns:GetSubsystem("History")
                if R and R.Wipe then R:Wipe() end
                local HF = ns:GetSubsystem("HistoryFrame")
                if HF and HF.Render then HF:Render() end
                print("|cffEBB706EQ History:|r wiped.")
            end,
        })
    end)
    wipeBtn:SetSize(160, 24)
    wipeBtn:SetPoint("TOPLEFT", rescanHint, "BOTTOMLEFT", 0, -16)
end)
