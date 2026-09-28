-- Keystance keyboard layouts, as data. Each row is a list of keys: { key, w = width in key
-- units (default 1), gap = space before it in key units, mod = true for Shift/Ctrl/Alt }.
-- `key` is the game's name for the key (what GetBindingAction takes). The function row
-- sits a little apart from the rest, like on a real keyboard.
-- Keys the game names differently on some keyboards simply don't match; bound keys that
-- aren't drawn are listed under the keyboard, so nothing is ever hidden.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)
local L = ns.L

local FROW = {
    { "ESCAPE" }, { "F1", gap = 1 }, { "F2" }, { "F3" }, { "F4" }, { "F5", gap = 0.5 }, { "F6" }, { "F7" }, { "F8" },
    { "F9", gap = 0.5 }, { "F10" }, { "F11" }, { "F12" },
}
local NUMBERS = {
    { "`" }, { "1" }, { "2" }, { "3" }, { "4" }, { "5" }, { "6" }, { "7" }, { "8" }, { "9" }, { "0" }, { "-" }, { "=" },
    { "BACKSPACE", w = 2 },
}
local BOTTOM = {
    { "CTRL", w = 1.25, mod = true }, { "", w = 1.25 }, { "ALT", w = 1.25, mod = true }, { "SPACE", w = 6.25 },
    { "ALT", w = 1.25, mod = true }, { "", w = 1.25 }, { "", w = 1.25 }, { "CTRL", w = 1.25, mod = true },
}

ns.LAYOUTS = {
    -- US and most of the world.
    ansi = {
        name = L["QWERTY (US)"],
        rows = {
            FROW, NUMBERS,
            { { "TAB", w = 1.5 }, { "Q" }, { "W" }, { "E" }, { "R" }, { "T" }, { "Y" }, { "U" }, { "I" }, { "O" }, { "P" },
                { "[" }, { "]" }, { "\\", w = 1.5 } },
            { { "CAPSLOCK", w = 1.75 }, { "A" }, { "S" }, { "D" }, { "F" }, { "G" }, { "H" }, { "J" }, { "K" }, { "L" },
                { ";" }, { "'" }, { "ENTER", w = 2.25 } },
            { { "SHIFT", w = 2.25, mod = true }, { "Z" }, { "X" }, { "C" }, { "V" }, { "B" }, { "N" }, { "M" }, { "," },
                { "." }, { "/" }, { "SHIFT", w = 2.75, mod = true } },
            BOTTOM,
        },
    },
    -- UK: a # key by Enter and a \ key by the left Shift (their game names aren't verified).
    iso = {
        name = L["QWERTY (UK)"],
        rows = {
            FROW, NUMBERS,
            { { "TAB", w = 1.5 }, { "Q" }, { "W" }, { "E" }, { "R" }, { "T" }, { "Y" }, { "U" }, { "I" }, { "O" }, { "P" },
                { "[" }, { "]" }, { "ENTER", w = 1.5 } },
            { { "CAPSLOCK", w = 1.75 }, { "A" }, { "S" }, { "D" }, { "F" }, { "G" }, { "H" }, { "J" }, { "K" }, { "L" },
                { ";" }, { "'" }, { "#" }, { "", w = 1.25 } },
            { { "SHIFT", w = 1.25, mod = true }, { "\\" }, { "Z" }, { "X" }, { "C" }, { "V" }, { "B" }, { "N" }, { "M" },
                { "," }, { "." }, { "/" }, { "SHIFT", w = 2.75, mod = true } },
            BOTTOM,
        },
    },
}
ns.LAYOUT_ORDER = { "ansi", "iso" }

-- The mouse: middle button, side buttons and the wheel.
ns.MOUSE_KEYS = { "BUTTON3", "BUTTON4", "BUTTON5", "MOUSEWHEELUP", "MOUSEWHEELDOWN" }

-- The layout for the setting: "auto" picks UK for an English (UK) game client.
function ns.LayoutKey(setting)
    if ns.LAYOUTS[setting] then return setting end
    return GetLocale() == "enGB" and "iso" or "ansi"
end

-- Short labels for key caps and bar buttons.
local SHORT = {
    ESCAPE = "Esc", BACKSPACE = "Bksp", CAPSLOCK = "Caps", ENTER = "Enter", SPACE = "Space", TAB = "Tab",
    SHIFT = "Shift", CTRL = "Ctrl", ALT = "Alt", BUTTON3 = "M3", BUTTON4 = "M4", BUTTON5 = "M5",
    MOUSEWHEELUP = "WhUp", MOUSEWHEELDOWN = "WhDn",
}
function ns.KeyLabel(key)
    return SHORT[key] or key
end

-- A bound key as bar buttons show it: modifiers as s, c, a ("SHIFT-1" is "s1"). Cached.
local short = {}
function ns.ShortKey(key)
    if not key then return nil end
    local s = short[key]
    if s then return s end
    local rest = key
    local mods = ""
    for _, m in ipairs({ { "ALT%-", "a" }, { "CTRL%-", "c" }, { "SHIFT%-", "s" } }) do
        local stripped, n = rest:gsub("^" .. m[1], "", 1)
        if n > 0 and stripped ~= "" then mods, rest = mods .. m[2], stripped end
    end
    s = mods .. ns.KeyLabel(rest)
    short[key] = s
    return s
end

-- Splits a bound key into its modifier prefix ("ALT-CTRL-SHIFT-", in the game's order)
-- and its base key. A lone "-" is a key, not a modifier.
-- Cached: keys are few and split every time the keyboard is redrawn.
local MODS = { "ALT-", "CTRL-", "SHIFT-" }
local splitPrefix, splitBase = {}, {}
function ns.SplitKey(key)
    local base = splitBase[key]
    if base then return splitPrefix[key], base end
    local prefix, rest = "", key
    for _, m in ipairs(MODS) do
        if rest:sub(1, #m) == m and #rest > #m then
            prefix, rest = prefix .. m, rest:sub(#m + 1)
        end
    end
    splitPrefix[key], splitBase[key] = prefix, rest
    return prefix, rest
end
