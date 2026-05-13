-- Core/Util.lua
-- Shared helpers: color tokens, time formatting, money formatting, table ops.

local _, ns = ...

local Util = ns:RegisterSubsystem("Util", {})

-- Style tokens (options-UI palette). Reference: project_eql_style memory.
Util.color = {
    optionsBg     = { 0.00, 0.00, 0.00, 0.95 },
    tabActive     = { 0.43, 0.02, 0.00, 1.00 },                         -- #6D0501
    tabText       = { 1.00, 1.00, 1.00, 1.00 },
    headerRed     = { 0.43, 0.02, 0.00, 1.00 },
    buttonYellow  = { 0.92, 0.72, 0.02, 1.00 },                         -- #EBB706
    statYellow    = { 0.92, 0.72, 0.02, 1.00 },
}

-- Format an integer count as "1.2k" / "12.3k" / "1.2m" once it gets big.
function Util.AbbrevNumber(n)
    if not n then return "" end
    if n >= 1000000 then return ("%.1fm"):format(n / 1000000) end
    if n >= 10000   then return ("%.1fk"):format(n / 1000) end
    return tostring(n)
end

-- Format seconds-remaining as "12m" / "3h" / "2d".
function Util.FmtTimeShort(secs)
    if not secs or secs <= 0 then return "" end
    if secs < 3600  then return ("%dm"):format(secs / 60) end
    if secs < 86400 then return ("%dh"):format(secs / 3600) end
    return ("%dd"):format(secs / 86400)
end

-- RGB hex string -> {r,g,b,a}. "6D0501" or "#6D0501".
function Util.HexToRGBA(hex, alpha)
    hex = hex:gsub("^#", "")
    local r = tonumber(hex:sub(1, 2), 16) / 255
    local g = tonumber(hex:sub(3, 4), 16) / 255
    local b = tonumber(hex:sub(5, 6), 16) / 255
    return r, g, b, alpha or 1
end

ns.Util = Util
