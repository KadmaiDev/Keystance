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
-- A game controller, drawn like one: `x`, `y` in key units. Button names measured on
-- Forever (C_GamePad.ButtonIndexToBinding, 2026-09-28); labels come from GetBindingText,
-- which gives the connected controller's own button icons. Stick directions (usually
-- movement) aren't drawn; bound ones show under "Also bound".
ns.LAYOUTS.pad = {
    name = L["Controller"], pad = true,
    keys = {
        { "PADLTRIGGER", x = 1, y = 0, w = 2 }, { "PADRTRIGGER", x = 12, y = 0, w = 2 },
        { "PADLSHOULDER", x = 1, y = 1, w = 2 }, { "PADRSHOULDER", x = 12, y = 1, w = 2 },
        { "PADLSTICK", x = 2, y = 2.4 },
        { "PADBACK", x = 6, y = 2 }, { "PADSYSTEM", x = 7, y = 1.6 }, { "PADFORWARD", x = 8, y = 2 },
        { "PADSOCIAL", x = 7, y = 2.8 },
        { "PAD4", x = 12, y = 2.4 }, { "PAD3", x = 11, y = 3.4 }, { "PAD2", x = 13, y = 3.4 }, { "PAD1", x = 12, y = 4.4 },
        { "PAD5", x = 14.2, y = 2.4 }, { "PAD6", x = 14.2, y = 4.4 },
        { "PADDUP", x = 5, y = 3.6 }, { "PADDLEFT", x = 4, y = 4.6 }, { "PADDRIGHT", x = 6, y = 4.6 },
        { "PADDDOWN", x = 5, y = 5.6 },
        { "PADRSTICK", x = 9.5, y = 4.8 },
        { "PADPADDLE1", x = 3, y = 6.8 }, { "PADPADDLE2", x = 4, y = 6.8 },
        { "PADPADDLE3", x = 10, y = 6.8 }, { "PADPADDLE4", x = 11, y = 6.8 },
    },
}
ns.LAYOUT_ORDER = { "ansi", "iso", "pad" }

-- The controller buttons set to act as Shift, Ctrl and Alt (the game's GamePadEmulate
-- settings): { [button] = "SHIFT"|"CTRL"|"ALT" }.
local padMods = {}
function ns.PadModifiers()
    for k in pairs(padMods) do padMods[k] = nil end
    if not GetCVar then return padMods end
    for _, m in ipairs({ { "GamePadEmulateShift", "SHIFT" }, { "GamePadEmulateCtrl", "CTRL" }, { "GamePadEmulateAlt", "ALT" } }) do
        local ok, button = pcall(GetCVar, m[1])
        if ok and type(button) == "string" and button ~= "" and button ~= "none" then padMods[button] = m[2] end
    end
    return padMods
end

-- True while a controller is in use.
local function PadActive()
    if not (C_GamePad and C_GamePad.IsEnabled) then return false end
    local ok, enabled = pcall(C_GamePad.IsEnabled)
    if not (ok and enabled) then return false end
    local okID, id = pcall(C_GamePad.GetActiveDeviceID)
    return okID and id ~= nil
end

-- The navigation block and the numpad, drawn with the Numpad option. Keys are placed by
-- row (as the main keyboard's rows) and column `x` in key units within their block; `h` is
-- a key two rows tall. Most names were seen bound in game (NUMPAD0, NUMPAD5, NUMLOCK,
-- NUMPADDIVIDE, NUMPADMINUS, NUMPADPLUS, PRINTSCREEN, INSERT, DELETE, HOME, END, PAGEUP,
-- PAGEDOWN, UP, DOWN, LEFT, RIGHT); NUMPADMULTIPLY, NUMPADDECIMAL and NUMPADENTER aren't
-- confirmed (a wrong one just shows under "Also bound").
ns.NAV_KEYS = {
    { "PRINTSCREEN", row = 1, x = 0 }, { "SCROLLLOCK", row = 1, x = 1 }, { "PAUSE", row = 1, x = 2 },
    { "INSERT", row = 2, x = 0 }, { "HOME", row = 2, x = 1 }, { "PAGEUP", row = 2, x = 2 },
    { "DELETE", row = 3, x = 0 }, { "END", row = 3, x = 1 }, { "PAGEDOWN", row = 3, x = 2 },
    { "UP", row = 5, x = 1 },
    { "LEFT", row = 6, x = 0 }, { "DOWN", row = 6, x = 1 }, { "RIGHT", row = 6, x = 2 },
}
ns.NUMPAD_KEYS = {
    { "NUMLOCK", row = 2, x = 0 }, { "NUMPADDIVIDE", row = 2, x = 1 }, { "NUMPADMULTIPLY", row = 2, x = 2 },
    { "NUMPADMINUS", row = 2, x = 3 },
    { "NUMPAD7", row = 3, x = 0 }, { "NUMPAD8", row = 3, x = 1 }, { "NUMPAD9", row = 3, x = 2 },
    { "NUMPADPLUS", row = 3, x = 3, h = 2 },
    { "NUMPAD4", row = 4, x = 0 }, { "NUMPAD5", row = 4, x = 1 }, { "NUMPAD6", row = 4, x = 2 },
    { "NUMPAD1", row = 5, x = 0 }, { "NUMPAD2", row = 5, x = 1 }, { "NUMPAD3", row = 5, x = 2 },
    { "NUMPADENTER", row = 5, x = 3, h = 2 },
    { "NUMPAD0", row = 6, x = 0, w = 2 }, { "NUMPADDECIMAL", row = 6, x = 2 },
}

-- The mouse: middle button, side buttons and the wheel.
ns.MOUSE_KEYS = { "BUTTON3", "BUTTON4", "BUTTON5", "MOUSEWHEELUP", "MOUSEWHEELDOWN" }

-- The layout for the setting: "auto" picks the controller while one is in use, else UK for
-- an English (UK) game client, else US.
function ns.LayoutKey(setting)
    if ns.LAYOUTS[setting] then return setting end
    if PadActive() then return "pad" end
    return GetLocale() == "enGB" and "iso" or "ansi"
end

-- Short labels for key caps and bar buttons.
local SHORT = {
    ESCAPE = "Esc", BACKSPACE = "Bksp", CAPSLOCK = "Caps", ENTER = "Enter", SPACE = "Space", TAB = "Tab",
    SHIFT = "Shift", CTRL = "Ctrl", ALT = "Alt", BUTTON3 = "M3", BUTTON4 = "M4", BUTTON5 = "M5",
    MOUSEWHEELUP = "WhUp", MOUSEWHEELDOWN = "WhDn",
    PRINTSCREEN = "PrtSc", SCROLLLOCK = "ScrLk", PAUSE = "Pause", INSERT = "Ins", HOME = "Home",
    PAGEUP = "PgUp", DELETE = "Del", END = "End", PAGEDOWN = "PgDn", UP = "Up", DOWN = "Down",
    LEFT = "Left", RIGHT = "Right", NUMLOCK = "Num", NUMPADDIVIDE = "N/", NUMPADMULTIPLY = "N*",
    NUMPADMINUS = "N-", NUMPADPLUS = "N+", NUMPADENTER = "NEnt", NUMPADDECIMAL = "N.",
    NUMPAD0 = "N0", NUMPAD1 = "N1", NUMPAD2 = "N2", NUMPAD3 = "N3", NUMPAD4 = "N4", NUMPAD5 = "N5",
    NUMPAD6 = "N6", NUMPAD7 = "N7", NUMPAD8 = "N8", NUMPAD9 = "N9",
}
function ns.KeyLabel(key)
    if SHORT[key] then return SHORT[key] end
    -- A controller button: the game's own icon for it.
    if key:sub(1, 3) == "PAD" and GetBindingText then
        local text = GetBindingText(key)
        if type(text) == "string" and text ~= "" then return text end
    end
    return key
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
