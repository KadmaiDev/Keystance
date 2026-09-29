-- Keystance actions: what's in each action slot, which slot a binding command triggers, and
-- which bars are on screen or hidden, for Blizzard's bars, EllesmereUI's and ElvUI's. Reads
-- only, except ns.SetBarShown, which shows or hides a bar (never touching its slots).
-- Slot numbers and binding commands were measured with the phase 0 probe (AGENTS.md).
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)
local L = ns.L

local type, tonumber, pcall, ipairs, unpack = type, tonumber, pcall, ipairs, unpack
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

-- A picture for a binding command that isn't an action: the raid markers' own icons, a
-- profile's icon for its key, Keystance's logo for Next profile and Open Keystance.
-- Returns the texture and true if it's a game icon with a border to crop.
local MARKER_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
local markerIcons = {}
local PROFILE_COMMANDS = {}
for n = 1, 6 do PROFILE_COMMANDS["KEYSTANCE_PROFILE" .. n] = n end
function ns.CommandIcon(command)
    if type(command) ~= "string" then return nil end
    local n = PROFILE_COMMANDS[command]
    if n then
        local name = ns.char and ns.ProfileKeySlots()[n]
        local p = name and ns.char.profiles[name]
        if p then return ns.ProfileIcon(p) end
        return ns.LOGO_ICON
    end
    if command == "KEYSTANCE_NEXT" or command == "KEYSTANCE_TOGGLE" then return ns.LOGO_ICON end
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

-- Blizzard's bars: the bar frame, its buttons' name and their binding command; for the
-- extra bars, their first action slot and their place in the game's bar switches
-- (GetActionBarToggles: bottom left, bottom right, right, right 2, bars 6-8).
local BLIZZARD_BARS = {
    { frame = "MainActionBar", alt = "MainMenuBar", button = "ActionButton", command = "ACTIONBUTTON", name = L["Main bar"] },
    { frame = "MultiBarBottomLeft", button = "MultiBarBottomLeftButton", command = "MULTIACTIONBAR1BUTTON",
        name = L["Bottom left"], first = 61, toggle = 1 },
    { frame = "MultiBarBottomRight", button = "MultiBarBottomRightButton", command = "MULTIACTIONBAR2BUTTON",
        name = L["Bottom right"], first = 49, toggle = 2 },
    { frame = "MultiBarRight", button = "MultiBarRightButton", command = "MULTIACTIONBAR3BUTTON", name = L["Right"],
        first = 25, toggle = 3 },
    { frame = "MultiBarLeft", button = "MultiBarLeftButton", command = "MULTIACTIONBAR4BUTTON", name = L["Right 2"],
        first = 37, toggle = 4 },
    { frame = "MultiBar5", button = "MultiBar5Button", command = "MULTIACTIONBAR5BUTTON", name = L["Bar 6"],
        first = 145, toggle = 5 },
    { frame = "MultiBar6", button = "MultiBar6Button", command = "MULTIACTIONBAR6BUTTON", name = L["Bar 7"],
        first = 157, toggle = 6 },
    { frame = "MultiBar7", button = "MultiBar7Button", command = "MULTIACTIONBAR7BUTTON", name = L["Bar 8"],
        first = 169, toggle = 7 },
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

local function Exists(name) return type(_G[name]) == "table" end

---------------------------------------------------------------------------
-- EllesmereUI's bar settings (its own, unofficial: every piece is checked, and a missing
-- one means Keystance just opens its settings instead). A bar's Visibility is one of
-- always, mouseover, in_combat, out_of_combat, never (and group modes); "enabled" = false
-- switches a bar off entirely.
---------------------------------------------------------------------------
local function EuiModule()
    local lite = type(EllesmereUI) == "table" and EllesmereUI.Lite
    if type(lite) ~= "table" or type(lite.GetAddon) ~= "function" then return nil end
    local ok, eab = pcall(lite.GetAddon, "EllesmereUIActionBars", true)
    if ok and type(eab) == "table" then return eab end
end

-- A bar's settings table in the EllesmereUI profile in use, or nil.
local function EuiSettings(key)
    local eab = EuiModule()
    local db = eab and eab.db
    local bars = type(db) == "table" and type(db.profile) == "table" and db.profile.bars
    local set = type(bars) == "table" and bars[key]
    return type(set) == "table" and set or nil, eab
end

-- Its Visibility, read without writing (EllesmereUI's own Normalize writes it back).
local function EuiMode(set)
    if type(set.barVisibility) == "string" then return set.barVisibility end
    if set.alwaysHidden then return "never" end
    if set.mouseoverEnabled then return "mouseover" end
    if set.combatShowEnabled then return "in_combat" end
    if set.combatHideEnabled then return "out_of_combat" end
    return "always"
end

-- Words for a mode, made once each: "in_combat" -> "in combat".
local MODE_NOTES = { always = false }
local function ModeNote(mode)
    local note = MODE_NOTES[mode]
    if note == nil then
        note = L[mode:gsub("_", " ")]
        MODE_NOTES[mode] = note
    end
    return note or nil
end

-- A bar entry of `list` (reused), with its twelve buttons.
local function Bar(list, i, name)
    local bar = list[i]
    if not bar then
        bar = { buttons = {} }
        list[i] = bar
    end
    bar.name = name
    for b = 1, 12 do bar.buttons[b] = bar.buttons[b] or {} end
    return bar
end

-- The bars on screen (shown = true) or the ones that exist but are hidden (false), in
-- order, into `list`. Each bar also says which addon draws it and how to show it:
-- bar.source, bar.key (Blizzard's toggle, EllesmereUI's bar key, ElvUI's number),
-- bar.frameName. A hidden bar's buttons carry their slot (btn.slot), as a hidden button may
-- not keep its action up to date.
local function Collect(list, shown)
    local n = 0
    local source = ns.BarSource()
    if source == "ellesmere" then
        for _, info in ipairs(EUI_BARS) do
            -- In use unless its Visibility is Never or it's switched off: a bar shown only
            -- in combat (hidden now) is still in use. Without its settings, what's on screen.
            local set = EuiSettings(info.key)
            local mode = set and EuiMode(set)
            local on
            if set then on = set.enabled ~= false and mode ~= "never" else on = Shown(info.barFrame) end
            if Exists(info.barFrame) and on == shown then
                n = n + 1
                if not info.commands then
                    Names(info, function(b) return info.command .. b end,
                        function(b) return "EABButton" .. (info.first + b - 1) end,
                        function(b) return "CLICK EABButton" .. (info.first + b - 1) .. ":LeftButton" end)
                end
                local bar = Bar(list, n, info.label)
                bar.source, bar.key, bar.frameName = source, info.key, info.barFrame
                bar.canHide = info.key ~= "MainBar"
                bar.note = shown and mode and ModeNote(mode) or nil
                for b = 1, 12 do
                    local btn = bar.buttons[b]
                    btn.command, btn.frame, btn.click = info.commands[b], _G[info.frames[b]], info.clicks[b]
                    btn.slot = not shown and (info.first + b - 1) or nil
                end
            end
        end
    elseif source == "elvui" then
        for k = 1, 15 do
            local info = ELV_INFO[k]
            if Exists(info.barFrame) and Shown(info.barFrame) == shown then
                n = n + 1
                if not info.commands then
                    Names(info, ELV_COMMANDS[k] and function(b) return ELV_COMMANDS[k] .. b end,
                        function(b) return "ElvUI_Bar" .. k .. "Button" .. b end,
                        function(b) return "CLICK ElvUI_Bar" .. k .. "Button" .. b .. ":LeftButton" end)
                end
                local bar = Bar(list, n, info.label)
                bar.source, bar.key, bar.frameName = source, k, info.barFrame
                bar.canHide = k ~= 1
                bar.note = nil
                for b = 1, 12 do
                    local btn = bar.buttons[b]
                    btn.frame = _G[info.frames[b]]
                    -- ElvUI keeps each button's binding command on the button.
                    btn.command = btn.frame and btn.frame.keyBoundTarget or info.commands[b]
                    btn.click = info.clicks[b]
                    btn.slot = not shown and ((k - 1) * 12 + b) or nil -- bar k shows page k by default
                end
            end
        end
    else
        for _, info in ipairs(BLIZZARD_BARS) do
            local on = Shown(info.frame) or (info.alt and Shown(info.alt)) or false
            -- A hidden bar is listed only if the game can switch it on (not the main bar).
            if on == shown and (shown or (info.toggle and Exists(info.frame))) then
                n = n + 1
                local bar = Bar(list, n, info.name)
                bar.source, bar.key, bar.frameName = source, info.toggle, info.frame
                bar.canHide = info.toggle ~= nil -- the main bar has no switch
                bar.note = nil
                if not info.commands then
                    Names(info, function(b) return info.command .. b end, function(b) return info.button .. b end)
                end
                for b = 1, 12 do
                    local btn = bar.buttons[b]
                    btn.command, btn.frame, btn.click = info.commands[b], _G[info.frames[b]], nil
                    btn.slot = not shown and info.first and (info.first + b - 1) or nil
                end
            end
        end
    end
    for i = n + 1, #list do list[i] = nil end
    return list, n
end

-- The bars on screen now, in order. Reuses its tables: read, don't keep.
local shownList, hiddenList = {}, {}
function ns.ShownBars() return Collect(shownList, true) end

-- The bars that exist but are hidden (they keep their slots and keys), in order.
function ns.HiddenBars() return Collect(hiddenList, false) end

-- Shows or hides a bar. Blizzard's: the game's own bar switch, then Blizzard's bar update,
-- as ticking it in Options > Action Bars does (measured 2026-09-29: the switch alone is
-- stored but changes nothing on screen until MultiActionBar_Update runs). EllesmereUI's and
-- ElvUI's bars belong to those addons, so their action bar settings open for the player to
-- switch it there (Keystance doesn't change another addon's settings). Never in combat (the
-- bars are secure frames). A hidden bar keeps its spells and keys.
function ns.SetBarShown(bar, on)
    if ns.InCombat() then
        ns.Print(L["Not in combat: try again when combat ends."])
        return false
    end
    local name, frameName = bar.name, bar.frameName
    if bar.source == "ellesmere" and ns.SetEuiBarShown(bar, on) then return true end
    if bar.source == "ellesmere" then
        local ok = type(EllesmereUI) == "table" and type(EllesmereUI.ShowModule) == "function"
            and pcall(EllesmereUI.ShowModule, EllesmereUI, "EllesmereUIActionBars")
        if on then
            ns.Print(ok and L["Switch %s on in EllesmereUI's Action Bars settings; Keystance shows it as soon as it's on."]:format(name)
                or L["Switch %s on in EllesmereUI's settings (/eui, Action Bars)."]:format(name))
        else
            ns.Print(ok and L["Switch %s off in EllesmereUI's Action Bars settings."]:format(name)
                or L["Switch %s off in EllesmereUI's settings (/eui, Action Bars)."]:format(name))
        end
        return ok and true or false
    elseif bar.source == "elvui" then
        local E = type(ElvUI) == "table" and ElvUI[1]
        local ok = type(E) == "table" and type(E.ToggleOptions) == "function" and pcall(E.ToggleOptions, E, "actionbar")
        if on then
            ns.Print(ok and L["Switch %s on in ElvUI's Action Bars settings; Keystance shows it as soon as it's on."]:format(name)
                or L["Switch %s on in ElvUI's settings (/ec, Action Bars)."]:format(name))
        else
            ns.Print(ok and L["Switch %s off in ElvUI's Action Bars settings."]:format(name)
                or L["Switch %s off in ElvUI's settings (/ec, Action Bars)."]:format(name))
        end
        return ok and true or false
    end
    -- Blizzard's: the game's switches, the rest kept as they are, then its bar update.
    local toggles = GetActionBarToggles and { GetActionBarToggles() }
    local ok = bar.key and toggles and #toggles >= bar.key and SetActionBarToggles and true or false
    if ok then
        toggles[bar.key] = on and true or false
        ok = pcall(SetActionBarToggles, unpack(toggles))
        if ok and type(MultiActionBar_Update) == "function" then pcall(MultiActionBar_Update) end
    end
    -- Whether it changed: if not, say where to do it.
    C_Timer.After(0.5, function()
        if ok and Shown(frameName) == on then
            ns.Print(on and L["%s is on screen now."]:format(name)
                or L["%s is hidden now. It keeps its spells and keys; Show brings it back."]:format(name))
        else
            ns.Print(on and L["%s didn't appear: switch it on in the game's Options, under Action Bars."]:format(name)
                or L["%s is still showing: switch it off in the game's Options, under Action Bars."]:format(name))
        end
        ns.RequestRefresh("bars")
    end)
    return ok
end

-- EllesmereUI's bars in one click, as its own Visibility control does (the owner's
-- decision, 2026-09-29): Hide sets Never and remembers what it was; Show puts that back (or
-- Always). Then its three refreshes run, and 0.5 s later the result is checked. Returns
-- false (so its settings page opens instead) when anything needed is missing, or the bar
-- is switched off entirely (only EllesmereUI's full refresh brings that back).
function ns.SetEuiBarShown(bar, on)
    local set, eab = EuiSettings(bar.key)
    local vc = eab and eab.VisibilityCompat
    if not (set and set.enabled ~= false and type(vc) == "table" and type(vc.ApplyMode) == "function"
        and type(eab.RefreshRuntimeVisibility) == "function" and type(eab.RefreshMouseover) == "function"
        and type(eab.ApplyCombatVisibility) == "function") then
        return false
    end
    local saved = ns.db.settings.euiVisibility or {}
    ns.db.settings.euiVisibility = saved
    local was, mode = EuiMode(set), nil
    if on then
        mode = saved[bar.key] or "always"
        if was ~= "never" then return false end -- not hidden by its Visibility: its page decides
    else
        if was == "never" then return false end
        mode = "never"
    end
    if not pcall(vc.ApplyMode, set, mode) then return false end
    if on then saved[bar.key] = nil else saved[bar.key] = was end
    pcall(eab.RefreshRuntimeVisibility, eab)
    pcall(eab.RefreshMouseover, eab)
    pcall(eab.ApplyCombatVisibility, eab)
    local name, frameName = bar.name, bar.frameName
    C_Timer.After(0.5, function()
        local done = EuiMode(set) == mode and (mode ~= "never" or not Shown(frameName))
            and (mode ~= "always" or Shown(frameName))
        if done then
            ns.Print(on and L["%s is back (%s)."]:format(name, mode == "always" and L["always shown"] or ModeNote(mode))
                or L["%s is hidden now (its Visibility is Never in EllesmereUI). It keeps its spells and keys; Show brings it back."]:format(name))
        else
            ns.Print(L["%s didn't change: switch it in EllesmereUI's Action Bars settings (/eui)."]:format(name))
        end
        ns.RequestRefresh("bars")
    end)
    return true
end

function ns.ShowBar(bar) return ns.SetBarShown(bar, true) end
function ns.HideBar(bar) return ns.SetBarShown(bar, false) end

-- The slot a bar button shows now.
function ns.BarButtonSlot(btn)
    return btn.slot or ButtonSlot(btn.frame) or ns.CommandSlot(btn.command)
end

-- The first key bound to a bar button: its command's, or a click binding on the button.
function ns.BarButtonKey(btn)
    local key = btn.command and GetBindingKey(btn.command)
    if not key and btn.click then key = GetBindingKey(btn.click) end
    return key
end
