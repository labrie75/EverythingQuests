-- Core/Init.lua
-- Addon namespace + subsystem registry. Modules call EQ:RegisterSubsystem(name, tbl)
-- and Init.lua wires them up in dependency order on PLAYER_LOGIN.

local addonName, ns = ...

_G.EverythingQuests = ns
ns.NAME = addonName
ns.VERSION = "1.3.6"

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
