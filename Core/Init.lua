-- Core/Init.lua
-- Addon namespace + subsystem registry. Modules call EQ:RegisterSubsystem(name, tbl)
-- and Init.lua wires them up in dependency order on PLAYER_LOGIN.

local addonName, ns = ...

_G.EverythingQuests = ns
ns.NAME = addonName
ns.VERSION = "1.22.0"

-- Community Discord. WoW can't open a browser, so ns:ShowDiscord() pops a
-- copyable invite via EQ's own Dialog (never a Blizzard StaticPopup — see
-- Core/Dialog.lua for the taint reason). Used by the Options title bar link
-- and the What's New popup.
ns.DISCORD_URL = "https://discord.gg/vm8K2WfQUE"

function ns:ShowDiscord()
    local D = self:GetSubsystem("Dialog")
    if not D then return end
    local L = ns.L
    D:Show({
        title       = L["Everything Quests Discord"],
        text        = L["Join the community for help, feedback, and updates.\nCopy the invite below (it's pre-selected — just press Ctrl+C):"],
        button1     = L["Close"],
        hasEditBox  = true,
        editBoxText = self.DISCORD_URL,
        highlightEditBox = true,
    })
end

-- Generic copyable-URL popup. WoW can't open a web browser, so every external
-- link (the About tab, etc.) routes through here: a Dialog with the URL
-- pre-selected so the user copies it with one Ctrl+C. Uses EQ's own Dialog
-- rather than a Blizzard StaticPopup for the same taint reason as ShowDiscord.
function ns:ShowURL(url)
    local D = self:GetSubsystem("Dialog")
    if not (D and url) then return end
    local L = ns.L
    D:Show({
        title       = "Everything Quests",
        text        = L["Copy the link below (it's pre-selected — just press Ctrl+C):"],
        button1     = L["Close"],
        hasEditBox  = true,
        editBoxText = url,
        highlightEditBox = true,
    })
end

ns.subsystems = {}
ns.subsystemOrder = {}

function ns:RegisterSubsystem(name, tbl)
    if self.subsystems[name] then
        error(("EQ: subsystem %q already registered"):format(name))
    end
    self.subsystems[name] = tbl
    self.subsystemOrder[#self.subsystemOrder + 1] = name
    return tbl
end

function ns:GetSubsystem(name)
    return self.subsystems[name]
end

-- Localized labels for Bindings.xml (must be plain globals, not in ns).
_G.BINDING_HEADER_EVERYTHINGQUESTS              = "Everything Quests"
_G.BINDING_NAME_EVERYTHINGQUESTS_TOGGLE_OPTIONS = "Toggle Options"
_G.BINDING_NAME_EVERYTHINGQUESTS_TOGGLE_CHAINGUIDE = "Toggle Chain Guide"

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    for _, name in ipairs(ns.subsystemOrder) do
        local sub = ns.subsystems[name]
        if sub.OnInitialize then sub:OnInitialize() end
    end
    for _, name in ipairs(ns.subsystemOrder) do
        local sub = ns.subsystems[name]
        if sub.OnEnable then sub:OnEnable() end
    end
end)
