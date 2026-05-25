-- Options/TabChainGuide.lua
-- Chain Guide settings: scale, open-on-login, cache management, plus a button
-- to actually open the chain guide window from inside Options.

local _, ns = ...

ns:GetSubsystem("Options"):AddTab("chainGuide", "Chain Guide", function(content)
    local Options = ns:GetSubsystem("Options")

    local function chainSetting(key)
        return
            function()
                local DB = ns:GetSubsystem("DB")
                return DB and DB.db.profile.chainGuide[key]
            end,
            function(value)
                local DB = ns:GetSubsystem("DB")
                if DB then DB.db.profile.chainGuide[key] = value end
                local CG = ns:GetSubsystem("ChainGuide")
                if CG and CG.ApplySettings then CG:ApplySettings() end
            end
    end

    -- ─── LEFT COLUMN: behavior + window controls ────────────────────────
    local h = Options:CreateSectionHeader(content, "Chain Guide (Storylines)")
    h:SetPoint("TOPLEFT", 8, -8)

    local openBtn = Options:CreateYellowButton(content, "Open Chain Guide", function()
        -- Hide Options first so the chain guide isn't visually buried
        -- behind it. Both windows live at DIALOG strata; getting them out
        -- of each other's way is cleaner than fighting frame-strata
        -- arithmetic.
        if Options.frame and Options.frame:IsShown() then Options.frame:Hide() end
        local CG = ns:GetSubsystem("ChainGuide"); if CG then CG:Open() end
    end)
    openBtn:SetSize(180, 28)
    openBtn:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -12)

    local loginGet, loginSet = chainSetting("showOnLogin")
    local login = Options:CreateCheckbox(content,
        "Open Chain Guide on login",
        loginGet, loginSet)
    login:SetPoint("TOPLEFT", openBtn, "BOTTOMLEFT", 0, -16)

    -- Toggling this re-runs API discovery so the list updates without /reload.
    local function unroutedGet()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.chainGuide.showUnroutedChains
    end
    local function unroutedSet(value)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.chainGuide.showUnroutedChains = value end
        local QLS = ns:GetSubsystem("ChainGuideQuestLineSource")
        if QLS and QLS.Reset then QLS:Reset() end
        local CG = ns:GetSubsystem("ChainGuide")
        if CG and CG.frame and CG.frame:IsShown() and CG.RenderCurrent then
            CG:RenderCurrent()
        end
    end
    local unrouted = Options:CreateCheckbox(content,
        "Show unrouted questlines  |cffaaaaaa(API discoveries not in our routing table)|r",
        unroutedGet, unroutedSet)
    unrouted:SetPoint("TOPLEFT", login, "BOTTOMLEFT", 0, -2)

    local scaleGet, scaleSet = chainSetting("scale")
    local scale = Options:CreateSlider(content, "Window scale",
        0.6, 1.5, 0.05, scaleGet, scaleSet)
    scale:SetPoint("TOPLEFT", unrouted, "BOTTOMLEFT", 0, -10)
    scale:SetWidth(280)

    -- ─── RIGHT COLUMN: cache + stats ────────────────────────────────────
    local cacheHeader = Options:CreateSectionHeader(content, "Character cache")
    cacheHeader:SetPoint("TOPLEFT", h, "TOPLEFT", 460, 0)

    local cacheHint = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cacheHint:SetPoint("TOPLEFT", cacheHeader, "BOTTOMLEFT", 0, -8)
    cacheHint:SetWidth(380)
    cacheHint:SetJustifyH("LEFT")
    cacheHint:SetTextColor(0.65, 0.65, 0.65)
    cacheHint:SetText("Per-character chain progress is cached account-wide so alts can browse what your other characters have completed. Clearing the cache removes that cross-character data; live completions stay (Blizzard tracks those).")

    local clear = Options:CreateYellowButton(content, "Clear chain cache", function()
        local Dialog = ns:GetSubsystem("Dialog")
        if not Dialog then return end
        Dialog:Show({
            title   = "Everything Quests",
            text    = "Clear all cached chain-completion data across every character?",
            button1 = "Clear",
            button2 = "Cancel",
            onAccept = function()
                _G.EverythingQuestsChainCache = {}
                ReloadUI()
            end,
        })
    end)
    clear:SetSize(180, 24)
    clear:SetPoint("TOPLEFT", cacheHint, "BOTTOMLEFT", 0, -12)

    -- Stats — read straight from the database; refresh-on-show via the
    -- closure so re-opening this tab reflects newly registered chains.
    local stats = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    stats:SetPoint("TOPLEFT", clear, "BOTTOMLEFT", 0, -16)
    stats:SetWidth(380)
    stats:SetJustifyH("LEFT")
    stats:SetTextColor(0.92, 0.72, 0.02)

    local function refreshStats()
        local DB = ns:GetSubsystem("ChainGuideDatabase")
        local nCats, nChains = 0, 0
        if DB then
            for _ in pairs(DB.categories) do nCats = nCats + 1 end
            for _ in pairs(DB.chains)     do nChains = nChains + 1 end
        end
        stats:SetText(("|cffffffff%d|r chains across |cffffffff%d|r categories"):format(nChains, nCats))
    end
    refreshStats()
    content:HookScript("OnShow", refreshStats)
end)
