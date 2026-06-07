-- Options/TabHistory.lua
-- "History" tab in the Options window. Controls:
--   • Master enable toggle
--   • Retention size slider (0 = unlimited)
--   • "Open Quest History" button — pops the standalone history window
--   • "Populate from past completions" — manual backfill button per char
--   • "Wipe history" — destructive, gated by a static-popup confirmation

local _, ns = ...
local L = ns.L

ns:GetSubsystem("Options"):AddTab("history", L["History"], function(content)
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

    local h = Options:CreateSectionHeader(content, L["Quest History"])
    h:SetPoint("TOPLEFT", 8, -8)

    local enaGet, enaSet = historySetting("enabled")
    local ena = Options:CreateCheckbox(content,
        L["Record completed quests"],
        enaGet, enaSet)
    ena:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -16)

    local enaHint = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    enaHint:SetPoint("TOPLEFT", ena, "BOTTOMLEFT", 0, -2)
    enaHint:SetWidth(650)
    enaHint:SetJustifyH("LEFT")
    enaHint:SetText(L["When on, Everything Quests writes an entry to your account-wide quest history every time you turn in a quest. The data is shared across all of your characters; the history window can filter by character."])

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
    retLabel:SetText(L["Maximum entries kept"])

    local retSlider
    if Options.CreateSlider then
        retSlider = Options:CreateSlider(content, nil, 200, 10000, 200, retGet, retSet)
        retSlider:SetPoint("TOPLEFT", retLabel, "BOTTOMLEFT", 0, -8)
        retSlider:SetWidth(300)
    end

    local retHint = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    retHint:SetPoint("TOPLEFT", retSlider or retLabel, "BOTTOMLEFT", 0, -8)
    retHint:SetWidth(650)
    retHint:SetJustifyH("LEFT")
    retHint:SetText(L["When the history grows past this many entries, the oldest ones are dropped. Set higher if you want a longer record, lower to save disk space. 5000 entries is enough for several months of heavy questing."])

    -- ─── Actions ────────────────────────────────────────────────────────
    local openBtn = Options:CreateYellowButton(content, L["Open Quest History"], function()
        local HF = ns:GetSubsystem("HistoryFrame")
        if HF and HF.Open then HF:Open() end
    end)
    openBtn:SetSize(200, 24)
    openBtn:SetPoint("TOPLEFT", retHint, "BOTTOMLEFT", 0, -20)

    local backfillBtn = Options:CreateYellowButton(content, L["Populate from past completions"], function()
        local R = ns:GetSubsystem("History")
        if not (R and R.Backfill) then return end
        local added = R:Backfill()
        local name = R.CurrentCharacter and R:CurrentCharacter() or L["this character"]
        print(L["|cffEBB706EQ History:|r added %d past completion%s for |cffffffff%s|r (no dates)."]:format(
            added, added == 1 and "" or "s", name))
    end)
    backfillBtn:SetSize(280, 24)
    backfillBtn:SetPoint("TOPLEFT", openBtn, "BOTTOMLEFT", 0, -10)

    local backfillHint = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    backfillHint:SetPoint("TOPLEFT", backfillBtn, "BOTTOMLEFT", 0, -2)
    backfillHint:SetWidth(650)
    backfillHint:SetJustifyH("LEFT")
    backfillHint:SetText(L["One-time per character: walks the list of quests this character has completed (according to the game's own record) and adds any that aren't already in your history. Entries created this way have no date — the game doesn't tell us when they happened."])

    local rescanBtn = Options:CreateYellowButton(content, L["Re-scan for quest names"], function()
        local R = ns:GetSubsystem("History")
        if not R then return end
        local queued = R:RequestMissingTitles() or 0
        if queued > 0 then
            print(L["|cffEBB706EQ History:|r requested %d quest name%s from the server. Names will fill in over the next minute or two."]:format(
                queued, queued == 1 and "" or "s"))
        else
            print(L["|cffEBB706EQ History:|r nothing left to look up — every entry that can be resolved already is."])
        end
    end)
    rescanBtn:SetSize(280, 24)
    rescanBtn:SetPoint("TOPLEFT", backfillHint, "BOTTOMLEFT", 0, -16)

    local rescanHint = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rescanHint:SetPoint("TOPLEFT", rescanBtn, "BOTTOMLEFT", 0, -2)
    rescanHint:SetWidth(650)
    rescanHint:SetJustifyH("LEFT")
    rescanHint:SetText(L["Some quests in the backfilled history show up as \"Quest #12345\" because Blizzard hasn't sent the client their name yet. This button asks the server for every missing one. Quests the server flatly has no data for (retired or internal IDs) will keep their numeric placeholder."])

    -- Restore from the automatic logout backup. EQ keeps a few rolling
    -- snapshots of your history and self-restores on load if it ever detects
    -- the data went missing; this button is the manual escape hatch.
    local restoreBtn = Options:CreateYellowButton(content, L["Restore history from backup"], function()
        local R = ns:GetSubsystem("History")
        if not (R and R.BackupInfo) then return end
        local info = R:BackupInfo()
        if not info then
            print(L["|cffEBB706EQ History:|r no backup yet — one is saved automatically each time you log out."])
            return
        end
        local Dialog = ns:GetSubsystem("Dialog")
        if not Dialog then return end
        Dialog:Show({
            title   = "Everything Quests",
            text    = L["Restore quest history from the backup taken %s (%d entries)? This replaces the current history."]:format(
                        date("%Y-%m-%d %H:%M", info.ts), info.count),
            button1 = L["Restore"],
            button2 = L["Cancel"],
            onAccept = function()
                local n = R:RestoreFromBackup()
                local HF = ns:GetSubsystem("HistoryFrame")
                if HF and HF.Render then HF:Render() end
                print(L["|cffEBB706EQ History:|r restored %d entr%s from backup."]:format(n, n == 1 and "y" or "ies"))
            end,
        })
    end)
    restoreBtn:SetSize(280, 24)
    restoreBtn:SetPoint("TOPLEFT", rescanHint, "BOTTOMLEFT", 0, -16)

    local restoreHint = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    restoreHint:SetPoint("TOPLEFT", restoreBtn, "BOTTOMLEFT", 0, -2)
    restoreHint:SetWidth(650)
    restoreHint:SetJustifyH("LEFT")
    restoreHint:SetText(L["Everything Quests saves a rolling backup of your history when you log out, and automatically restores it if your history is ever found empty or missing a character on load. Use this button to restore manually."])

    local wipeBtn = Options:CreateYellowButton(content, L["Wipe history"], function()
        local Dialog = ns:GetSubsystem("Dialog")
        if not Dialog then return end
        Dialog:Show({
            title   = "Everything Quests",
            text    = L["Delete ALL recorded quest history (every character)? This cannot be undone."],
            button1 = L["Wipe"],
            button2 = L["Cancel"],
            onAccept = function()
                local R = ns:GetSubsystem("History")
                if R and R.Wipe then R:Wipe() end
                local HF = ns:GetSubsystem("HistoryFrame")
                if HF and HF.Render then HF:Render() end
                print(L["|cffEBB706EQ History:|r wiped."])
            end,
        })
    end)
    wipeBtn:SetSize(160, 24)
    wipeBtn:SetPoint("TOPLEFT", restoreHint, "BOTTOMLEFT", 0, -16)
end)
