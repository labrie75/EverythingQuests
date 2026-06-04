-- Modules/Tracker/Achievements.lua
-- Tracked-achievement section for the on-screen tracker, mirroring Blizzard's
-- objective tracker: each achievement the player is tracking shows as a header
-- (icon + name) with its criteria listed beneath — a checkmark for finished
-- criteria, a colorized "X/Y" prefix for measured progress, and grey text for
-- the rest. Pure display: tracking/untracking still happens in the Achievement
-- UI. Same pooled, count-returning Render contract as Endeavors/Profession so
-- the Frame.lua section dispatch treats it identically.

local _, ns = ...

local A = ns:RegisterSubsystem("TrackerAchievements", {})

local HEADER_H     = 18
local LINE_H       = 14
local ROW_GAP      = 2
local LABEL_PAD    = 6
local LINE_INDENT  = 14
-- Safety cap so a tracked achievement with a huge criteria list (e.g. a big
-- exploration or dungeon meta) can't flood the whole tracker.
local MAX_CRITERIA = 12

A.headerPool    = {}
A.linePool      = {}
A.activeHeaders = {}
A.activeLines   = {}

-- Achievement tracking moved to the unified content-tracking system; the
-- legacy GetTrackedAchievements() still exists as a fallback for older
-- clients. Resolve the enum once.
local ACH_TYPE = (Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Achievement)

local function buildHeader(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(HEADER_H)
    r.title = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.title:SetPoint("LEFT", LABEL_PAD, 0)
    r.title:SetPoint("RIGHT", -4, 0)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)
    r.title:SetTextColor(1.0, 0.82, 0.0)
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
            -- Pooled rows always reset color, so set both branches explicitly.
            if ov and ov.r then
                row.title:SetTextColor(ov.r, ov.g, ov.b)
            else
                row.title:SetTextColor(1.0, 0.82, 0.0)
            end
            if Media and Media.ApplyTrackerFont then Media:ApplyTrackerFont(row.title, 0) end
            y = y + HEADER_H + ROW_GAP

            local num = (GetAchievementNumCriteria and GetAchievementNumCriteria(id)) or 0
            local shownCrit = 0
            for c = 1, num do
                if shownCrit >= MAX_CRITERIA then break end
                local critString, _, critDone, quantity, reqQuantity =
                    GetAchievementCriteriaInfo(id, c)
                if critString and critString ~= "" then
                    local line
                    if critDone then
                        line = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t |cff" .. doneHex
                               .. critString .. "|r"
                    elseif reqQuantity and reqQuantity > 1 then
                        -- Measured criterion: colorize the "X/Y" prefix the
                        -- same way the Quests/World Quests sections do.
                        line = "- " .. colorizeProgress(quantity .. "/" .. reqQuantity
                               .. " " .. critString)
                    else
                        line = "|cff999999- " .. critString .. "|r"
                    end
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
