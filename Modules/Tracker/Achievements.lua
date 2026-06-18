-- Modules/Tracker/Achievements.lua
-- Tracked-achievement section for the on-screen tracker, mirroring Blizzard's
-- objective tracker: each achievement the player is tracking shows as a header
-- (icon + name) with its criteria listed beneath — a checkmark for finished
-- criteria, a colorized "X/Y" prefix for measured progress, and grey text for
-- the rest. Pure display: tracking/untracking still happens in the Achievement
-- UI. Same pooled, count-returning Render contract as Endeavors/Profession so
-- the Frame.lua section dispatch treats it identically.

local _, ns = ...
local L = ns.L

local A = ns:RegisterSubsystem("TrackerAchievements", {})

local HEADER_H     = 18
local LINE_H       = 14
local ROW_GAP      = 2
local LABEL_PAD    = 6
local LINE_INDENT  = 14
-- Safety cap so a tracked achievement with a huge criteria list (e.g. a big
-- exploration or dungeon meta) can't flood the whole tracker.
local MAX_CRITERIA = 12

-- Bit in GetAchievementCriteriaInfo's `flags` (return #7) marking a PROGRESS-BAR
-- criterion (Blizzard's EVALUATION_TREE_FLAG_PROGRESS_BAR). These criteria
-- ("61/100"-style meters — the delve puzzle achievement, Brann/Buddy System
-- tiers, etc.) carry their progress in quantity/reqQuantity but have an EMPTY
-- criteriaString, so they need detecting separately from named-counter criteria.
local PROGRESS_BAR_FLAG = 0x1

A.headerPool    = {}
A.linePool      = {}
A.activeHeaders = {}
A.activeLines   = {}

-- Achievement tracking moved to the unified content-tracking system; the
-- legacy GetTrackedAchievements() still exists as a fallback for older
-- clients. Resolve the enum once.
local ACH_TYPE    = (Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Achievement)
local STOP_MANUAL = (Enum and Enum.ContentTrackingStopType and Enum.ContentTrackingStopType.Manual) or 2

-- Achievement header rows are clickable: LEFT opens Blizzard's achievement
-- window to this achievement (OpenAchievementFrameToAchievement is Blizzard's
-- own objective-tracker handler — it loads Blizzard_AchievementUI on demand,
-- shows the frame, and scrolls to the id), RIGHT untracks it via the modern
-- content-tracking API (StopTracking is AllowedWhenUntainted, so combat-safe).
-- The tracker's achievement section is NON-secure, so these clicks add no taint
-- to the secure quest-item-button chain. [[reference-tracker-secure-taint]]
-- Static file-scope handlers (wired once in buildHeader); the row carries its
-- id/name in _achID/_achName, cleared on pool release.
local function headerOnMouseUp(self, button)
    local id = self._achID
    if not id then return end
    if button == "RightButton" then
        if C_ContentTracking and C_ContentTracking.StopTracking and ACH_TYPE then
            C_ContentTracking.StopTracking(ACH_TYPE, id, STOP_MANUAL)
        elseif RemoveTrackedAchievement then
            RemoveTrackedAchievement(id)   -- legacy fallback (older clients)
        end
        -- CONTENT_TRACKING_UPDATE / TRACKED_ACHIEVEMENT_LIST_CHANGED fires and
        -- refreshes this section; no manual Refresh needed.
    elseif button == "LeftButton" then
        if OpenAchievementFrameToAchievement then
            OpenAchievementFrameToAchievement(id)
        end
    end
end

local function headerOnEnter(self)
    if not self._achID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self._achName then GameTooltip:AddLine(self._achName, 1, 0.82, 0) end
    GameTooltip:AddLine(L["Left-click to open, right-click to untrack."], 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function headerOnLeave()
    GameTooltip:Hide()
end

local function buildHeader(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(HEADER_H)
    r.title = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.title:SetPoint("LEFT", LABEL_PAD, 0)
    r.title:SetPoint("RIGHT", -4, 0)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)
    r.title:SetTextColor(1.0, 0.82, 0.0)
    r:EnableMouse(true)
    r:SetScript("OnMouseUp", headerOnMouseUp)
    r:SetScript("OnEnter",   headerOnEnter)
    r:SetScript("OnLeave",   headerOnLeave)
    return r
end

local function buildLine(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(LINE_H)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", LINE_INDENT, 0)
    r.text:SetPoint("RIGHT", -4, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    return r
end

local function acquireHeader(parent)
    return ns.Util.AcquirePooled(A.headerPool, A.activeHeaders, parent, buildHeader)
end

local function acquireLine(parent)
    return ns.Util.AcquirePooled(A.linePool, A.activeLines, parent, buildLine)
end

local function releaseAll()
    for i = #A.activeHeaders, 1, -1 do
        local r = A.activeHeaders[i]
        r:Hide()
        r:ClearAllPoints()
        r._achID = nil
        r._achName = nil
        A.headerPool[#A.headerPool + 1] = r
        A.activeHeaders[i] = nil
    end
    for i = #A.activeLines, 1, -1 do
        local r = A.activeLines[i]
        r:Hide()
        r:ClearAllPoints()
        r.text:SetText("")
        A.linePool[#A.linePool + 1] = r
        A.activeLines[i] = nil
    end
end

local function getTrackedAchievements()
    local out = {}
    if C_ContentTracking and C_ContentTracking.GetTrackedIDs and ACH_TYPE then
        local ids = C_ContentTracking.GetTrackedIDs(ACH_TYPE)
        if ids then
            for i = 1, #ids do
                if ids[i] then out[#out + 1] = ids[i] end
            end
        end
    end
    if #out == 0 and GetTrackedAchievements then
        -- Legacy varargs API: returns up to MAX_TRACKED_ACHIEVEMENTS ids.
        local t = { GetTrackedAchievements() }
        for i = 1, #t do
            if t[i] and t[i] ~= 0 then out[#out + 1] = t[i] end
        end
    end
    return out
end

local colorizeProgress = ns.Util.ColorizeProgress

function A:Render(content, contentWidth, yStart, collapsed)
    local ids = getTrackedAchievements()
    local count = #ids

    releaseAll()

    if collapsed or count == 0 then return 0, count end
    if not GetAchievementInfo then return 0, 0 end

    local Media = ns:GetSubsystem("Media")

    -- Follow the user's tracker color scheme exactly like the Quests / World
    -- Quests sections: the achievement name uses the title-color override when
    -- one is set (else Blizzard yellow), and completed criteria use that same
    -- color when "override complete green" is on (else green). Computed ONCE
    -- per render, not per row — this path is GC-sensitive.
    local DB = ns:GetSubsystem("DB")
    local t  = DB and DB.db and DB.db.profile and DB.db.profile.tracker
    local ov = t and t.titleColorOverride
    local simplify = t and t.simplifyAchievements   -- #4: show only incomplete criteria
    local doneHex = "44ff44"
    if t and t.overrideCompleteGreen ~= false and ov and ov.r then
        doneHex = ("%02x%02x%02x"):format(
            math.floor(ov.r * 255 + 0.5),
            math.floor(ov.g * 255 + 0.5),
            math.floor(ov.b * 255 + 0.5))
    end

    local shownCount = 0
    local y = yStart
    for i = 1, count do
        local id = ids[i]
        local _, name, _, _, _, _, _, _, _, icon = GetAchievementInfo(id)
        if name then
            shownCount = shownCount + 1
            local row = acquireHeader(content)
            row:SetWidth(contentWidth)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            -- Inline achievement icon (|T...:0|t auto-sizes to the line) so
            -- the row reads at a glance without an extra anchored texture.
            local label = name
            if icon then label = "|T" .. icon .. ":0|t " .. name end
            row.title:SetText(label)
            row._achID   = id
            row._achName = name
            -- Pooled rows always reset color, so set both branches explicitly.
            if ov and ov.r then
                row.title:SetTextColor(ov.r, ov.g, ov.b)
            else
                row.title:SetTextColor(1.0, 0.82, 0.0)
            end
            if Media and Media.ApplyTrackerTitleFont then Media:ApplyTrackerTitleFont(row.title) end
            y = y + HEADER_H + ROW_GAP

            local num = (GetAchievementNumCriteria and GetAchievementNumCriteria(id)) or 0
            local shownCrit = 0
            for c = 1, num do
                if shownCrit >= MAX_CRITERIA then break end
                local critString, _, critDone, quantity, reqQuantity, _, critFlags =
                    GetAchievementCriteriaInfo(id, c)
                -- A PROGRESS-BAR criterion (the "61/100"-style meter behind the
                -- delve puzzle achievement, Brann/Buddy System tiers, etc.) has an
                -- EMPTY criteriaString but real quantity/reqQuantity, so the old
                -- "critString ~= ''" gate dropped it — only simple named-counter
                -- achievements ("Complete 500 delves") ever showed an X/Y. Detect
                -- it via the engine flag and render its X/Y too.
                local hasText      = critString and critString ~= ""
                local isProgressBar = critFlags and bit.band(critFlags, PROGRESS_BAR_FLAG) ~= 0
                local hasMeter      = reqQuantity and reqQuantity > 1
                if (hasText or isProgressBar) and not (simplify and critDone) then
                    local line
                    if critDone then
                        -- Completed: checkmark + the criterion name, or the
                        -- "X/Y" for a (now full) progress bar with no name.
                        local critLabel = (hasText and critString)
                                       or (hasMeter and (quantity .. "/" .. reqQuantity))
                        if critLabel then
                            line = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t |cff"
                                   .. doneHex .. critLabel .. "|r"
                        end
                    elseif hasMeter then
                        -- Measured / progress-bar criterion: colorize the "X/Y"
                        -- prefix like the Quests/World Quests sections. Append the
                        -- criterion name when it has one (progress bars don't, so
                        -- they read as a clean "X/Y").
                        local suffix = hasText and (" " .. critString) or ""
                        line = "- " .. colorizeProgress(quantity .. "/" .. reqQuantity .. suffix)
                    elseif hasText then
                        line = "|cff999999- " .. critString .. "|r"
                    end
                    if line then
                        local lr = acquireLine(content)
                        lr:SetWidth(contentWidth)
                        lr:ClearAllPoints()
                        lr:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                        lr.text:SetText(line)
                        if Media and Media.ApplyTrackerFont then Media:ApplyTrackerFont(lr.text, -2) end
                        shownCrit = shownCrit + 1
                        y = y + LINE_H + ROW_GAP
                    end
                end
            end
        end
    end

    return y - yStart, shownCount
end

function A:OnEnable()
    local Events = ns:GetSubsystem("Events")
    local function refresh()
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker and Tracker.Refresh then Tracker:Refresh() end
    end
    Events:On("TRACKED_ACHIEVEMENT_LIST_CHANGED", refresh)
    Events:On("TRACKED_ACHIEVEMENT_UPDATE",       refresh)
    Events:On("CONTENT_TRACKING_UPDATE",          refresh)
    Events:On("ACHIEVEMENT_EARNED",               refresh)
    Events:On("PLAYER_ENTERING_WORLD",            refresh)
end
