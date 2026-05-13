-- Modules/Minimap/Minimap.lua
-- Minimap launcher button via LibDBIcon (so it works in Titan Panel,
-- ElvUI's data-broker bar, ChocolateBar, etc. — not a custom button).

local _, ns = ...

local M = ns:RegisterSubsystem("Minimap", {})

function M:OnInitialize()
    local LDB = LibStub("LibDataBroker-1.1", true)
    local LDBI = LibStub("LibDBIcon-1.0", true)
    if not (LDB and LDBI) then return end

    self.dataObject = LDB:NewDataObject("EverythingQuests", {
        type = "launcher",
        text = "EQ",
        icon = "Interface\\Icons\\INV_Misc_Book_09",
        OnClick = function(_, button)
            if button == "RightButton" then
                local Options = ns:GetSubsystem("Options")
                if Options then Options:Toggle() end
            elseif IsShiftKeyDown and IsShiftKeyDown() then
                local CG = ns:GetSubsystem("ChainGuide")
                if CG then CG:Toggle() end
            elseif ToggleQuestLog then
                -- Defer to Blizzard's quest log map frame; we no longer
                -- ship our own quest log window.
                ToggleQuestLog()
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("Everything Quests")
            tt:AddLine("|cffEBB706Left-click|r: Open Quest Log", 1, 1, 1)
            tt:AddLine("|cffEBB706Shift-Left-click|r: Open Chain Guide", 1, 1, 1)
            tt:AddLine("|cffEBB706Right-click|r: Options", 1, 1, 1)
        end,
    })

    local DB = ns:GetSubsystem("DB")
    LDBI:Register("EverythingQuests", self.dataObject, DB.char.minimap)
end
