-- Keystance actions: what's in each action slot, which slot a binding command triggers, and
-- which bars are on screen, for Blizzard's bars, EllesmereUI's and ElvUI's. Read-only.
-- Slot numbers and binding commands were measured with the phase 0 probe (AGENTS.md).
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)
local L = ns.L

local type, tonumber, pcall = type, tonumber, pcall
local issecretvalue = issecretvalue or function() return false end
local HasAction, GetActionInfo, GetActionText = HasAction, GetActionInfo, GetActionText

-- Slots above 180 exist on Forever (the probe found 181-184, 197 and 200 in use); nothing
-- is known to use slots beyond this.
ns.MAX_SLOT = 300

-- MULTIACTIONBAR<n>BUTTON<i> triggers slot MULTI_BASE[n] + i.
local MULTI_BASE = { 60, 48, 24, 36, 144, 156, 168 }

-- The slot a bar button shows: LibActionButton's state (ElvUI), the action field
-- (Blizzard) or the action attribute (EllesmereUI).
local function ButtonSlot(b)
    if type(b) ~= "table" then return nil end
    local s = b._state_action or b.action
    if s == nil and b.GetAttribute then s = b:GetAttribute("action") end
    if type(s) == "number" and not issecretvalue(s) then return s end
    return nil
end
ns.ButtonSlot = ButtonSlot

-- The main bar's slot for its button n: bar page (Shift+number), then stance and form
-- paging (bonus bar offset k shows page 6 + k), else page 1.
function ns.MainSlot(n)
    local page = GetActionBarPage and GetActionBarPage() or 1
    if type(page) == "number" and page > 1 then return (page - 1) * 12 + n end
    local offset = GetBonusBarOffset and GetBonusBarOffset() or 0
    if type(offset) == "number" and offset > 0 then return (5 + offset) * 12 + n end
    return n
end

-- Parsed binding commands, cached: kind and numbers never change for a command.
local cmdKind, cmdA, cmdB = {}, {}, {}
local function Parse(cmd)
    local kind = cmdKind[cmd]
    if kind then return kind end
    local n = cmd:match("^ACTIONBUTTON(%d+)$")
    if n then
        kind, cmdA[cmd] = "main", tonumber(n)
    else
        local bar, b = cmd:match("^MULTIACTIONBAR(%d)BUTTON(%d+)$")
        if bar and MULTI_BASE[tonumber(bar)] then
            kind, cmdA[cmd] = "fixed", MULTI_BASE[tonumber(bar)] + tonumber(b)
        else
            n = cmd:match("^EUI_BAR9_BUTTON(%d+)$")
            local n10 = cmd:match("^EUI_BAR10_BUTTON(%d+)$")
            local ebar, eb = cmd:match("^ELVUIBAR(%d+)BUTTON(%d+)$")
            local click = cmd:match("^CLICK ([^:]+)")
            if n then
                kind, cmdA[cmd] = "fixed", 12 + tonumber(n)
            elseif n10 then
                kind, cmdA[cmd] = "fixed", 108 + tonumber(n10)
            elseif ebar then
                kind, cmdA[cmd], cmdB[cmd] = "elvui", tonumber(ebar), tonumber(eb)
            elseif click then
                kind, cmdA[cmd] = "click", click
            else
                kind = "other"
            end
        end
    end
    cmdKind[cmd] = kind
    return kind
end

-- The action slot a binding command triggers, or nil if it isn't an action button.
function ns.CommandSlot(cmd)
    if type(cmd) ~= "string" or cmd == "" then return nil end
    local kind = Parse(cmd)
    if kind == "main" then
        -- EllesmereUI's main bar pages its own buttons; the button knows its slot best.
        return ButtonSlot(_G["EABButton" .. cmdA[cmd]]) or ns.MainSlot(cmdA[cmd])
    elseif kind == "fixed" then
        return cmdA[cmd]
    elseif kind == "elvui" then
        local k, i = cmdA[cmd], cmdB[cmd]
        return ButtonSlot(_G["ElvUI_Bar" .. k .. "Button" .. i]) or (k - 1) * 12 + i
    elseif kind == "click" then
        return ButtonSlot(_G[cmdA[cmd]])
    end
    return nil
end

-- A picture for a binding command that isn't an action: the raid markers' own icons.
-- Returns the texture and whether it's a full picture (not an icon to crop).
local MARKER_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
local markerIcons = {}
function ns.CommandIcon(command)
    if type(command) ~= "string" then return nil end
    local icon = markerIcons[command]
    if icon == nil then
        local n = command:match("^RAIDTARGET(%d)$")
        icon = n and (MARKER_ICON .. n) or (command == "RAIDTARGETNONE" and "Interface\\Buttons\\UI-GroupLoot-Pass-Up") or false
        markerIcons[command] = icon
    end
    return icon or nil
end

-- A slot's action as saved data, or nil for an empty slot:
--   { t = "spell", id = 19834, name = "Blessing of Might", rank = "Rank 2" }
--   { t = "macro", name = "Attack", body = "...", icon = 132349, perChar = true, spell = 6603 }
--   { t = "item", id = 6948 }
--   { t = "flyout", id = 264 } and any other kind the same way.
-- A macro slot reports the spell the macro shows, not the macro; its name comes from
-- GetActionText (measured).
function ns.DescribeSlot(slot)
    local ok, has = pcall(HasAction, slot)
    if not ok or not has then return nil end
    local kind, id, sub = GetActionInfo(slot)
    if issecretvalue(kind) or issecretvalue(id) then return { t = "unknown" } end
    if kind == "spell" then
        return { t = "spell", id = id, name = C_Spell.GetSpellName(id), rank = C_Spell.GetSpellSubtext(id) }
    elseif kind == "macro" then
        local name = GetActionText(slot)
        local m = { t = "macro", name = name, spell = id }
        if name and GetMacroInfo then
            local _, icon, body = GetMacroInfo(name)
            m.icon, m.body = icon, body
            local index = GetMacroIndexByName and GetMacroIndexByName(name)
            if type(index) == "number" and index > 0 then m.perChar = index > (MAX_ACCOUNT_MACROS or 120) end
        end
        return m
    elseif kind == "item" then
        return { t = "item", id = id }
    end
    return { t = kind, id = id, sub = sub }
end

---------------------------------------------------------------------------
-- Bars on screen: Blizzard's, EllesmereUI's or ElvUI's. Each bar is
-- { name = "Bar 2", buttons = { { command = "MULTIACTIONBAR1BUTTON1", frame = <button> }, ... } }.
---------------------------------------------------------------------------
local function Shown(name)
    local f = _G[name]
    return type(f) == "table" and f.IsShown and f:IsShown() or false
end

-- EllesmereUI (EllesmereUIActionBars.lua: BAR_SLOT_OFFSETS and BINDING_MAP).
local EUI_BARS = {
    { key = "MainBar", first = 1, command = "ACTIONBUTTON" },
    { key = "Bar2", first = 61, command = "MULTIACTIONBAR1BUTTON" },
    { key = "Bar3", first = 49, command = "MULTIACTIONBAR2BUTTON" },
    { key = "Bar4", first = 25, command = "MULTIACTIONBAR3BUTTON" },
    { key = "Bar5", first = 37, command = "MULTIACTIONBAR4BUTTON" },
    { key = "Bar6", first = 145, command = "MULTIACTIONBAR5BUTTON" },
    { key = "Bar7", first = 157, command = "MULTIACTIONBAR6BUTTON" },
    { key = "Bar8", first = 169, command = "MULTIACTIONBAR7BUTTON" },
    { key = "Bar9", first = 13, command = "EUI_BAR9_BUTTON" },
    { key = "Bar10", first = 109, command = "EUI_BAR10_BUTTON" },
}

-- ElvUI's binding commands per bar (ActionBars.lua: bindButtons; bars 13-15 use
-- ELVUIBAR commands outside retail and MULTIACTIONBAR5-7 on retail, so both are tried).
local ELV_COMMANDS = {
    [1] = "ACTIONBUTTON", [2] = "ELVUIBAR2BUTTON", [3] = "MULTIACTIONBAR3BUTTON", [4] = "MULTIACTIONBAR4BUTTON",
    [5] = "MULTIACTIONBAR2BUTTON", [6] = "MULTIACTIONBAR1BUTTON", [7] = "ELVUIBAR7BUTTON", [8] = "ELVUIBAR8BUTTON",
    [9] = "ELVUIBAR9BUTTON", [10] = "ELVUIBAR10BUTTON", [13] = "MULTIACTIONBAR5BUTTON", [14] = "MULTIACTIONBAR6BUTTON",
    [15] = "MULTIACTIONBAR7BUTTON",
}

-- Blizzard's bars: the bar frame, its buttons' name and their binding command.
local BLIZZARD_BARS = {
    { frame = "MainActionBar", alt = "MainMenuBar", button = "ActionButton", command = "ACTIONBUTTON", name = L["Main bar"] },
    { frame = "MultiBarBottomLeft", button = "MultiBarBottomLeftButton", command = "MULTIACTIONBAR1BUTTON", name = L["Bottom left"] },
    { frame = "MultiBarBottomRight", button = "MultiBarBottomRightButton", command = "MULTIACTIONBAR2BUTTON", name = L["Bottom right"] },
    { frame = "MultiBarRight", button = "MultiBarRightButton", command = "MULTIACTIONBAR3BUTTON", name = L["Right"] },
    { frame = "MultiBarLeft", button = "MultiBarLeftButton", command = "MULTIACTIONBAR4BUTTON", name = L["Right 2"] },
    { frame = "MultiBar5", button = "MultiBar5Button", command = "MULTIACTIONBAR5BUTTON", name = L["Bar 6"] },
    { frame = "MultiBar6", button = "MultiBar6Button", command = "MULTIACTIONBAR6BUTTON", name = L["Bar 7"] },
    { frame = "MultiBar7", button = "MultiBar7Button", command = "MULTIACTIONBAR7BUTTON", name = L["Bar 8"] },
}

-- Which bar addon draws the bars: "ellesmere", "elvui" or "blizzard".
function ns.BarSource()
    if _G.EABButton1 and _G.EABBar_MainBar then return "ellesmere" end
    if _G.ElvUI_Bar1Button1 then return "elvui" end
    return "blizzard"
end

-- The names a bar's twelve buttons use, built once per bar the first time it's shown:
-- commands, button frame names and click bindings never change.
local function Names(info, command, button, click)
    if not info.commands then
        info.commands, info.frames, info.clicks = {}, {}, {}
        for b = 1, 12 do
            info.commands[b] = command and command(b)
            info.frames[b] = button(b)
            info.clicks[b] = click and click(b)
        end
    end
    return info
end

-- Bar frame names and labels, made once.
for i, info in ipairs(EUI_BARS) do
    info.barFrame, info.label = "EABBar_" .. info.key, L["Bar %d"]:format(i)
end
local ELV_INFO = {}
for k = 1, 15 do ELV_INFO[k] = { barFrame = "ElvUI_Bar" .. k, label = L["Bar %d"]:format(k) } end

local bars = {} -- reused between calls
local function Bar(i, name)
    local bar = bars[i]
    if not bar then
        bar = { buttons = {} }
        bars[i] = bar
    end
    bar.name = name
    return bar
end

-- The bars on screen now, in order. Reuses its tables: read, don't keep.
function ns.ShownBars()
    local n = 0
    local source = ns.BarSource()
    if source == "ellesmere" then
        for _, info in ipairs(EUI_BARS) do
            if Shown(info.barFrame) then
                n = n + 1
                if not info.commands then
                    Names(info, function(b) return info.command .. b end,
                        function(b) return "EABButton" .. (info.first + b - 1) end,
                        function(b) return "CLICK EABButton" .. (info.first + b - 1) .. ":LeftButton" end)
                end
                local bar = Bar(n, info.label)
                for b = 1, 12 do
                    local btn = bar.buttons[b] or {}
                    bar.buttons[b] = btn
                    btn.command, btn.frame, btn.click = info.commands[b], _G[info.frames[b]], info.clicks[b]
                end
            end
        end
    elseif source == "elvui" then
        for k = 1, 15 do
            local info = ELV_INFO[k]
            if Shown(info.barFrame) then
                n = n + 1
                if not info.commands then
                    Names(info, ELV_COMMANDS[k] and function(b) return ELV_COMMANDS[k] .. b end,
                        function(b) return "ElvUI_Bar" .. k .. "Button" .. b end,
                        function(b) return "CLICK ElvUI_Bar" .. k .. "Button" .. b .. ":LeftButton" end)
                end
                local bar = Bar(n, info.label)
                for b = 1, 12 do
                    local btn = bar.buttons[b] or {}
                    bar.buttons[b] = btn
                    btn.frame = _G[info.frames[b]]
                    -- ElvUI keeps each button's binding command on the button.
                    btn.command = btn.frame and btn.frame.keyBoundTarget or info.commands[b]
                    btn.click = info.clicks[b]
                end
            end
        end
    else
        for _, info in ipairs(BLIZZARD_BARS) do
            if Shown(info.frame) or (info.alt and Shown(info.alt)) then
                n = n + 1
                local bar = Bar(n, info.name)
                if not info.commands then
                    Names(info, function(b) return info.command .. b end, function(b) return info.button .. b end)
                end
                for b = 1, 12 do
                    local btn = bar.buttons[b] or {}
                    bar.buttons[b] = btn
                    btn.command, btn.frame, btn.click = info.commands[b], _G[info.frames[b]], nil
                end
            end
        end
    end
    for i = n + 1, #bars do bars[i] = nil end
    return bars, n
end

-- The slot a bar button shows now.
function ns.BarButtonSlot(btn)
    return ButtonSlot(btn.frame) or ns.CommandSlot(btn.command)
end

-- The first key bound to a bar button: its command's, or a click binding on the button.
function ns.BarButtonKey(btn)
    local key = btn.command and GetBindingKey(btn.command)
    if not key and btn.click then key = GetBindingKey(btn.click) end
    return key
end
