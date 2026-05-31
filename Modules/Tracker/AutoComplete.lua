-- Modules/Tracker/AutoComplete.lua
-- "Click to complete quest" popup widgets in the on-screen tracker.
-- Auto-complete quests don't have an NPC turn-in — when their objectives
-- finish, Blizzard fires QUEST_AUTOCOMPLETE and exposes them through
-- GetNumAutoQuestPopUps() / GetAutoQuestPopUp(). The intended UX is a
-- prominent button at the top of the tracker reading "Click to complete
-- quest" — clicking it calls ShowQuestComplete(questID) to open the
-- completion dialog.
--
-- Without this widget, our previous renderer showed these as regular
-- "ready-to-turn-in" blocks with a stuck green checkmark — the player
-- has no way to actually finish them.
--
-- The widget pool is its own — separate from the regular Blocks pool —
-- because the visual is different (large icon, two-line text, yellow
-- callout) and reusing Blocks would mean conditional layout. Pooling is
-- almost always 0–1 active widgets at a time.

local _, ns = ...

local AC = ns:RegisterSubsystem("TrackerAutoComplete", {})

local PAD          = 8
local ICON_SIZE    = 36
local ICON_GAP     = 8
local CTA_TO_TITLE = 1
local PAD_Y        = 6

AC.pool   = {}
AC.active = {}

-- ─── Widget factory ────────────────────────────────────────────────────
local function buildPopup()
    local p = CreateFrame("Button")
    p:SetHeight(ICON_SIZE + PAD_Y * 2)

    -- Subtle dark background so the popup reads as its own band.
    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.20, 0.15, 0.05, 0.55)

    -- 1px yellow outline (drawn via four edge textures so it stays crisp at
    -- any size; SetBackdrop is heavier and templated).
    local function edge()
        local t = p:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.92, 0.72, 0.02, 0.9)
        return t
    end
    local top  = edge(); top:SetHeight(1);  top:SetPoint("TOPLEFT");    top:SetPoint("TOPRIGHT")
    local bot  = edge(); bot:SetHeight(1);  bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT")
    local left = edge(); left:SetWidth(1);  left:SetPoint("TOPLEFT");   left:SetPoint("BOTTOMLEFT")
    local rt   = edge(); rt:SetWidth(1);    rt:SetPoint("TOPRIGHT");    rt:SetPoint("BOTTOMRIGHT")

    -- Hover highlight — clearer than the border alone that this is clickable.
    local hl = p:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)

    -- Big "?" icon at the left.
    p.icon = p:CreateTexture(nil, "ARTWORK")
    p.icon:SetSize(ICON_SIZE, ICON_SIZE)
    p.icon:SetPoint("LEFT", PAD, 0)

    -- "Click to complete quest" — small yellow CTA above the title.
    p.cta = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.cta:SetPoint("TOPLEFT",  p.icon, "TOPRIGHT", ICON_GAP, -2)
    p.cta:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PAD, -2)
    p.cta:SetJustifyH("LEFT")
    p.cta:SetText("Click to complete quest")
    p.cta:SetTextColor(0.92, 0.72, 0.02)

    -- Quest title — wrap so multi-line titles flow inside the widget.
    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.title:SetPoint("TOPLEFT",  p.cta, "BOTTOMLEFT",  0, -CTA_TO_TITLE)
    p.title:SetPoint("TOPRIGHT", p.cta, "BOTTOMRIGHT", 0, -CTA_TO_TITLE)
    p.title:SetJustifyH("LEFT")
    p.title:SetWordWrap(true)
    p.title:SetTextColor(1, 1, 1)

    -- Click → open the standard completion dialog. ShowQuestComplete is the
    -- canonical Blizzard helper and works for both regular and auto-complete
    -- quests.
    p:SetScript("OnClick", function(self)
        if self.questID and ShowQuestComplete then
            ShowQuestComplete(self.questID)
        end
    end)

    return p
end

function AC:Acquire(parent)
    return ns.Util.AcquirePooled(self.pool, self.active, parent, buildPopup)
end

function AC:ReleaseAll()
    for i = #self.active, 1, -1 do
        local p = self.active[i]
        p:Hide()
        p:ClearAllPoints()
        p:SetParent(nil)
        p.questID = nil
        self.pool[#self.pool + 1] = p
        self.active[i] = nil
    end
end

-- Render a popup widget for a single auto-complete quest.
function AC:Render(popup, questID, questTitle)
    popup.questID = questID
    popup.title:SetText(questTitle or ("Quest #" .. tostring(questID)))

    -- Auto-complete uses the standard "?" turn-in icon, white-tinted so the
    -- yellow border stays the dominant accent.
    if popup.icon.SetAtlas and C_Texture and C_Texture.GetAtlasInfo
        and C_Texture.GetAtlasInfo("QuestTurnin") then
        popup.icon:SetAtlas("QuestTurnin", false)
    else
        popup.icon:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
    end
    popup.icon:SetVertexColor(1, 1, 1, 1)

    -- Auto-fit height to wrapped title — Click target grows with the text.
    local h = math.max(ICON_SIZE, popup.cta:GetStringHeight() + CTA_TO_TITLE
                                  + popup.title:GetStringHeight()) + PAD_Y * 2
    popup:SetHeight(h)
end

-- Returns array of {questID, title} for every quest with an active
-- "COMPLETE" auto-popup. The OFFER popups (new-quest popups) we don't
-- handle here; those would be a different widget.
function AC:GetActivePopups()
    local out = {}
    if not GetNumAutoQuestPopUps then return out end
    for i = 1, GetNumAutoQuestPopUps() do
        local qid, popType = GetAutoQuestPopUp(i)
        if qid and popType == "COMPLETE" then
            local title = ns.Util.QuestTitle(qid, true)
            out[#out + 1] = { questID = qid, title = title }
        end
    end
    return out
end
