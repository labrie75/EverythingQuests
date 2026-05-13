-- Core/Events.lua
-- Single event dispatcher. Modules subscribe via Events:On("EVENT_NAME", handler).
-- Avoids each module owning its own frame and re-registering the same events.

local _, ns = ...

local Events = ns:RegisterSubsystem("Events", {})
local frame = CreateFrame("Frame")
local listeners = {}

function Events:On(event, fn)
    local list = listeners[event]
    if not list then
        list = {}
        listeners[event] = list
        frame:RegisterEvent(event)
    end
    list[#list + 1] = fn
end

function Events:Off(event, fn)
    local list = listeners[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == fn then tremove(list, i) end
    end
    if #list == 0 then
        listeners[event] = nil
        frame:UnregisterEvent(event)
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = listeners[event]
    if not list then return end
    for i = 1, #list do list[i](event, ...) end
end)

ns.Events = Events
