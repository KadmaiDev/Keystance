-- Keystance drops: what the cursor holds (a spell from the spell panel or the spellbook, a
-- macro, an item, an action dragged off a bar) dropped on a key in the Keyboard tab or a
-- slot in the Bars tab. Never in combat; every drop can be undone.
--  * On a slot, or a key that triggers one: placed as the game's own bars do, so whatever
--    was in the slot comes onto the cursor rather than being lost.
--  * On a key that isn't a bar button: the first empty slot on a bar on screen gets it and
--    the key is bound to that slot's button. Taking the key from another command (Move
--    Forward, the bags...) is asked first, as is changing shared keybinds; the cursor
--    keeps what it holds until then, so cancelling loses nothing. With no empty slot on
--    screen nothing changes and the player is told.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)
local L = ns.L

local GetCursorInfo, HasAction, PlaceAction = GetCursorInfo, HasAction, PlaceAction

-- A name for what the cursor holds ("Consecration", "Attack", "Hearthstone").
local function CursorLabel()
    local kind, a, _, c = GetCursorInfo()
    local name
    if kind == "spell" then
        name = C_Spell.GetSpellName(c or a)
    elseif kind == "macro" then
        name = GetMacroInfo(a)
    elseif kind == "item" then
        name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(a)
    end
    return name or L["it"]
end

local function Refused(why)
    ns.Print(why)
    return false
end

-- Puts what the cursor holds into a slot; the slot's old action comes onto the cursor.
function ns.DropOnSlot(slot)
    if not GetCursorInfo() then return false end
    if ns.InCombat() then return Refused(L["Not in combat: drop it again when combat ends."]) end
    local label = CursorLabel()
    local before = ns.CurrentState()
    PlaceAction(slot)
    ns.RecordChange(before, L["placing %s"]:format(label))
    ns.Print(L["%s placed in slot %d."]:format(label, slot))
    ns.RefreshWindow()
    return true
end

-- The first empty slot on a bar on screen, with its button's command, bar name and position.
local function FreeSlot()
    local bars, n = ns.ShownBars()
    for i = 1, n do
        for b, btn in ipairs(bars[i].buttons) do
            local slot = ns.BarButtonSlot(btn)
            if slot and slot <= ns.MANAGED_SLOTS and not HasAction(slot) and btn.command then
                return slot, btn.command, bars[i].name, b
            end
        end
    end
end

-- Places the cursor's action in a free slot and binds the key to that slot's button.
local function PlaceAndBind(key)
    if not GetCursorInfo() then return Refused(L["Nothing is held on the cursor any more."]) end
    if ns.InCombat() then return Refused(L["Not in combat: drop it again when combat ends."]) end
    local slot, command, barName, index = FreeSlot()
    if not slot then
        return Refused(L["No empty slot on your bars: make room, or drop it on a key that already casts something."])
    end
    local label = CursorLabel()
    local before = ns.CurrentState()
    PlaceAction(slot) -- an empty slot, so nothing comes back onto the cursor
    local state = ns.CurrentState()
    for cmd, keys in pairs(state.binds) do
        for i = #keys, 1, -1 do
            if keys[i] == key then table.remove(keys, i) end
        end
        if #keys == 0 then state.binds[cmd] = nil end
    end
    state.binds[command] = state.binds[command] or {}
    table.insert(state.binds[command], key)
    ns.ApplyState(state, { scope = "all" })
    ns.RecordChange(before, L["placing %s on %s"]:format(label, key))
    ns.Print(L["%s placed in %s, slot %d, on %s."]:format(label, barName, index, key))
    ns.RefreshWindow()
    return true
end

local pendingKey
local function AskToBind(text)
    if not StaticPopupDialogs.KEYSTANCE_BIND_KEY then
        StaticPopupDialogs.KEYSTANCE_BIND_KEY = {
            text = "%s",
            button1 = L["Use this key"],
            button2 = CANCEL or "Cancel",
            OnAccept = function()
                local key = pendingKey
                pendingKey = nil
                if not key then return end
                if ns.SharedKeybinds() then
                    if ns.InCombat() then return Refused(L["Not in combat: drop it again when combat ends."]) end
                    SaveBindings(2) -- this character's own keybinds first (same as /kst ownkeys)
                end
                PlaceAndBind(key)
            end,
            OnCancel = function() pendingKey = nil end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
    end
    StaticPopup_Show("KEYSTANCE_BIND_KEY", text)
end

---------------------------------------------------------------------------
-- Binding a command that isn't an action (a raid marker) to a key: the panel "holds" the
-- command, and the next click on a key in the Keyboard tab binds it there.
---------------------------------------------------------------------------
local held -- { command = "RAIDTARGET8", label = "Skull", icon = ... } while waiting for a key

function ns.HeldBinding() return held end

function ns.StartBinding(command, label, icon, dragging)
    held = { command = command, label = label, icon = icon }
    ns.ToggleWindow(true)
    ns.ShowTab("keyboard")
    if not dragging then
        ns.Print(L["Click a key in the Keyboard tab to put %s on it. Right-click cancels."]:format(label))
    end
    ns.RefreshWindow()
end

function ns.CancelBinding()
    held = nil
    ns.RefreshWindow()
end

local function Bind(key, command, label)
    if ns.InCombat() then return Refused(L["Not in combat: try again when combat ends."]) end
    if ns.SharedKeybinds() then SaveBindings(2) end -- this character's own keybinds first
    local before = ns.CurrentState()
    local state = ns.CurrentState()
    for cmd, keys in pairs(state.binds) do
        for i = #keys, 1, -1 do
            if keys[i] == key then table.remove(keys, i) end
        end
        if #keys == 0 then state.binds[cmd] = nil end
    end
    state.binds[command] = state.binds[command] or {}
    table.insert(state.binds[command], key)
    local ok, why = ns.ApplyState(state, { scope = "all" })
    if not ok then return Refused(L["Nothing changed: %s."]:format(why)) end
    ns.RecordChange(before, L["putting %s on %s"]:format(label, key))
    ns.Print(L["%s is now on %s."]:format(label, key))
    ns.RefreshWindow()
    return true
end

local pendingBind
local function AskBind(text)
    if not StaticPopupDialogs.KEYSTANCE_BIND_COMMAND then
        StaticPopupDialogs.KEYSTANCE_BIND_COMMAND = {
            text = "%s",
            button1 = L["Use this key"],
            button2 = CANCEL or "Cancel",
            OnAccept = function()
                local p = pendingBind
                pendingBind = nil
                if p then Bind(p.key, p.command, p.label) end
            end,
            OnCancel = function() pendingBind = nil end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
    end
    StaticPopup_Show("KEYSTANCE_BIND_COMMAND", text)
end

-- Binds the held command to `fullKey` (now bound to `current`), asking first if the key
-- already does something or the keybinds are shared.
function ns.BindHeld(fullKey, current)
    local h = held
    if not h then return false end
    held = nil
    if ns.InCombat() then return Refused(L["Not in combat: try again when combat ends."]) end
    if current == h.command then
        ns.Print(L["%s is already on %s."]:format(h.label, fullKey))
        ns.RefreshWindow()
        return true
    end
    local text
    if current and current ~= "" then
        text = L["%s is %s. Use it for %s instead?"]:format(fullKey, ns.CommandName(current), h.label)
    elseif ns.SharedKeybinds() then
        text = L["Put %s on %s?"]:format(h.label, fullKey)
    end
    if not text then return Bind(fullKey, h.command, h.label) end
    if ns.SharedKeybinds() then
        text = text .. "\n\n" .. L["Your keybinds are shared by all your characters, so this character gets its own keybinds first: nothing changes on screen, and your other characters keep theirs."]
    end
    pendingBind = { key = fullKey, command = h.command, label = h.label }
    AskBind(text)
    ns.RefreshWindow()
    return true
end

-- Puts what the cursor holds on a key: `fullKey` with its modifiers, `slot` the slot it
-- triggers now (or nil), `command` what it's bound to now.
function ns.DropOnKey(fullKey, slot, command)
    if not GetCursorInfo() then return false end
    if ns.InCombat() then return Refused(L["Not in combat: drop it again when combat ends."]) end
    if slot then return ns.DropOnSlot(slot) end
    local other = command and command ~= "" and not ns.IsBarCommand(command) and command
    if not other and not ns.SharedKeybinds() then return PlaceAndBind(fullKey) end
    local label = CursorLabel()
    local text = other and L["%s is %s. Use it for %s instead?"]:format(fullKey, ns.CommandName(other), label)
        or L["Put %s on %s?"]:format(label, fullKey)
    if ns.SharedKeybinds() then
        text = text .. "\n\n" .. L["Your keybinds are shared by all your characters, so this character gets its own keybinds first: nothing changes on screen, and your other characters keep theirs."]
    end
    pendingKey = fullKey
    AskToBind(text)
    return true
end
