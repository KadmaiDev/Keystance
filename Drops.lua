-- Keystance drops: what the cursor holds (a spell from the spell panel or the spellbook, a
-- macro, an item, an action dragged off a bar or off a key) dropped on a key in the
-- Keyboard tab or a slot in the Bars tab, plus picking actions up from those keys and
-- slots, and removing them. Never in combat; every change can be undone.
--  * Picked up from a key or slot here: dropped on a key with no slot, the action stays in
--    its slot and the key binding moves to the new key instead ("Holy Light from 5 to
--    Shift-E"); Undo puts back the whole move.
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

local GetCursorInfo, HasAction, PlaceAction, PickupAction = GetCursorInfo, HasAction, PlaceAction, PickupAction

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

-- A name for what's in a slot.
local function SlotLabel(slot)
    local a = ns.DescribeSlot(slot)
    if not a then return nil end
    return a.name or (a.t == "item" and C_Item.GetItemNameByID and C_Item.GetItemNameByID(a.id)) or L["it"]
end

-- What was picked up from a key or slot here: { before = the setup before, key = the full
-- key it was on (or nil), slot, command = the slot's button command }. Forgotten once used
-- or once the cursor is empty.
local source

-- Picks up the action in `slot` (on `fullKey`, bound to `command`), as the real bars do.
function ns.PickupFromSlot(slot, fullKey, command)
    if ns.InCombat() then return Refused(L["Not in combat: try again when combat ends."]) end
    ns.CancelBinding() -- one thing held at a time
    if GetCursorInfo() or not slot or not HasAction(slot) then return false end
    local before = ns.CurrentState()
    PickupAction(slot)
    if not GetCursorInfo() then return false end
    source = { before = before, key = fullKey, slot = slot, command = command }
    return true
end

ns.On("CURSOR_CHANGED", function()
    if source and not GetCursorInfo() then source = nil end
end)

-- The setup to undo to: from before the pick-up, if this came from here.
local function Before()
    local s = source
    source = nil
    return s and s.before or ns.CurrentState(), s
end

-- Puts what the cursor holds into a slot; the slot's old action comes onto the cursor.
function ns.DropOnSlot(slot)
    if not GetCursorInfo() then return false end
    if ns.InCombat() then return Refused(L["Not in combat: drop it again when combat ends."]) end
    local label = CursorLabel()
    local before, from = Before()
    PlaceAction(slot)
    ns.RecordChange(before, (from and L["moving %s"] or L["placing %s"]):format(label))
    ns.Notify(L["%s placed in slot %d."]:format(label, slot))
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

-- Removes `key` from every command in a state's bindings.
local function Unbind(state, key)
    for cmd, keys in pairs(state.binds) do
        for i = #keys, 1, -1 do
            if keys[i] == key then table.remove(keys, i) end
        end
        if #keys == 0 then state.binds[cmd] = nil end
    end
end

-- Puts the cursor's action on a key with no slot. Picked up from a key or slot here, the
-- action goes back to its slot and the key binding moves; otherwise it goes in the first
-- empty slot on screen and the key is bound to that slot's button.
local function PlaceAndBind(key)
    if not GetCursorInfo() then return Refused(L["Nothing is held on the cursor any more."]) end
    if ns.InCombat() then return Refused(L["Not in combat: drop it again when combat ends."]) end
    local moving = source and source.command and source.slot and not HasAction(source.slot) and source
    local slot, command, barName, index
    if moving then
        slot, command = moving.slot, moving.command
    else
        slot, command, barName, index = FreeSlot()
        if not slot then
            return Refused(L["No empty slot on your bars: make room, or drop it on a key that already casts something."])
        end
    end
    local label = CursorLabel()
    local before = Before()
    PlaceAction(slot) -- an empty slot, so nothing comes back onto the cursor
    local state = ns.CurrentState()
    if moving and moving.key then Unbind(state, moving.key) end
    Unbind(state, key)
    state.binds[command] = state.binds[command] or {}
    table.insert(state.binds[command], key)
    ns.ApplyState(state, { scope = "all" })
    if moving then
        ns.RecordChange(before, L["moving %s to %s"]:format(label, key))
        ns.Notify(L["%s moved to %s."]:format(label, key))
    else
        ns.RecordChange(before, L["placing %s on %s"]:format(label, key))
        -- A key with no bar button yet: the first empty slot on screen took it. Say which,
        -- as it may not be where the player would have put it.
        ns.Notify(L["%s went on %s, button %d, with the key %s. Move it on the Bars tab if you'd like it somewhere else."]
            :format(label, barName, index, key))
    end
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
-- Holding a command that isn't an action (a raid marker), as a spell is held on the
-- cursor: its icon follows the mouse, a left-click on a key in the Keyboard tab puts it
-- there, and a right-click anywhere drops it. The game's cursor can't carry a keybinding
-- (and SetCursor didn't show the icon, in game), so a small frame of our own follows the
-- mouse; its OnUpdate and the right-click listener exist only while something is held.
---------------------------------------------------------------------------
-- The game's own pick-up and drop sounds, looked up by name in SOUNDKIT: a spell icon's
-- first, then the general ones (listed on Forever 2026-09-28: IG_ABILITY_ICON_DROP 838,
-- UI_CURSOR_PICKUP_OBJECT 688, UI_CURSOR_DROP_OBJECT 689).
local PICKUP_SOUNDS = { "IG_ABILITY_ICON_PICKUP", "UI_CURSOR_PICKUP_OBJECT" }
local DROP_SOUNDS = { "IG_ABILITY_ICON_DROP", "UI_CURSOR_DROP_OBJECT" }
local function Sound(names)
    local kit = SOUNDKIT
    if type(kit) ~= "table" or not PlaySound then return end
    for _, name in ipairs(names) do
        local id = kit[name]
        if id then
            PlaySound(id)
            return
        end
    end
end

local held -- { command = "RAIDTARGET8", label = "Skull", icon = ... } while held
local ghost, listener
local endedAt -- when the last hold ended (so the right-click that ended it does nothing more)

function ns.HeldBinding() return held end

-- True for an action button: Blizzard's bars and ElvUI's (LibActionButton) keep `action`
-- (ElvUI also `_state_action`), EllesmereUI's the "action" attribute; or a slot on
-- Keystance's Bars tab.
local function IsActionButton(f)
    if type(f) ~= "table" then return false end
    if f.slot or f.action or f._state_action then return true end
    if f.GetAttribute then
        local ok, action = pcall(f.GetAttribute, f, "action")
        return ok and action ~= nil
    end
    return false
end

-- A marker or profile switch clicked on a bar: it goes on keys, not bars. Said once per hold.
local function HintKeysOnly()
    if not held or held.hinted then return end
    held.hinted = true
    ns.Notify(L["%s goes on a key, not on a bar: click a key on Keystance's Keyboard tab. Right-click drops it."]:format(held.label))
end
ns.HintKeysOnly = HintKeysOnly

local function Follow(self)
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale + 14, y / scale - 14)
end

local function EndHold()
    held = nil
    endedAt = GetTime()
    if ghost then
        ghost:SetScript("OnUpdate", nil)
        ghost:Hide()
    end
    if listener then listener:UnregisterAllEvents() end
    ns.RefreshWindow()
end

-- True just after a hold ended: the right-click that ended it shouldn't also act on a key.
function ns.HoldJustEnded()
    return endedAt ~= nil and GetTime() - endedAt < 0.5
end

-- `profile`: what's held is the switch to that profile (its key is set with
-- ns.SetProfileKey, which gives it one of the Profile 1-6 keybinds).
function ns.StartBinding(command, label, icon, profile)
    if ns.InCombat() then return Refused(L["Not in combat: try again when combat ends."]) end
    if GetCursorInfo() then ClearCursor() end -- one thing held at a time, as with spells
    held = { command = command, label = label, icon = icon, profile = profile }
    if not ghost then
        ghost = CreateFrame("Frame", "KeystanceDragIcon", UIParent)
        ghost:SetSize(28, 28)
        ghost:SetFrameStrata("TOOLTIP")
        ghost:EnableMouse(false) -- so the key under it is what's clicked
        ghost.icon = ghost:CreateTexture(nil, "OVERLAY")
        ghost.icon:SetAllPoints()
        -- What to do with it: it goes on a key (not on a bar, as a spell would).
        ghost.caption = ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ghost.caption:SetPoint("TOP", ghost, "BOTTOM", 0, -2)
        ghost.caption:SetText(L["Click a key"])
    end
    ghost.icon:SetTexture(icon)
    Follow(ghost)
    ghost:Show()
    ghost:SetScript("OnUpdate", Follow)
    Sound(PICKUP_SOUNDS)
    if not listener then
        listener = CreateFrame("Frame")
        listener:SetScript("OnEvent", function(_, _, button)
            if not held then return end
            if button == "RightButton" then return ns.CancelBinding() end
            local foci = GetMouseFoci and GetMouseFoci()
            local target = type(foci) == "table" and foci[1]
            if IsActionButton(target) then HintKeysOnly() end
        end)
    end
    pcall(listener.RegisterEvent, listener, "GLOBAL_MOUSE_DOWN")
    ns.ToggleWindow(true)
    ns.ShowTab("keyboard")
    ns.RefreshWindow()
end

function ns.CancelBinding()
    if held then
        EndHold()
        Sound(DROP_SOUNDS)
    end
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
    Sound(DROP_SOUNDS)
    ns.Notify(L["%s is now on %s."]:format(label, key))
    ns.RefreshWindow()
    return true
end

-- Keybind mode (Bars tab): binds `key` to `command` at once, saying what the key did before.
function ns.QuickBind(key, command, label)
    local was = GetBindingAction(key)
    if was == command then
        ns.Notify(L["%s is already on %s."]:format(label, key))
        return false
    end
    local ok = Bind(key, command, label)
    if ok and was and was ~= "" then ns.Print(L["(%s was %s.)"]:format(key, ns.CommandName(was))) end
    return ok
end

-- Clears every key of a command (a bar button), undoably.
function ns.ClearKeys(command, label)
    if ns.InCombat() then return Refused(L["Not in combat: try again when combat ends."]) end
    local state = ns.CurrentState()
    if not state.binds[command] then
        ns.Notify(L["%s has no key."]:format(label))
        return false
    end
    if ns.SharedKeybinds() then SaveBindings(2) end -- this character's own keybinds first
    state.binds[command] = nil
    return ns.ApplyChange(state, { scope = "all" }, L["%s's keys cleared"]:format(label),
        L["clearing %s's keys"]:format(label))
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
                if p and p.profile then
                    ns.SetProfileKey(p.profile, p.key)
                elseif p then
                    Bind(p.key, p.command, p.label)
                end
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
    EndHold()
    if ns.InCombat() then return Refused(L["Not in combat: try again when combat ends."]) end
    if h.profile then
        local n = ns.ProfileSlot(h.profile)
        h.command = n and ns.ProfileSlotCommand(n) -- nil until it has a key
    end
    if current == h.command then
        ns.Notify(L["%s is already on %s."]:format(h.label, fullKey))
        ns.RefreshWindow()
        return true
    end
    local text
    if current and current ~= "" then
        text = L["%s is %s. Use it for %s instead?"]:format(fullKey, ns.CommandName(current), h.label)
    elseif ns.SharedKeybinds() then
        text = L["Put %s on %s?"]:format(h.label, fullKey)
    end
    if not text then
        if h.profile then return ns.SetProfileKey(h.profile, fullKey) end
        return Bind(fullKey, h.command, h.label)
    end
    if ns.SharedKeybinds() then
        text = text .. "\n\n" .. L["Your keybinds are shared by all your characters, so this character gets its own keybinds first: nothing changes on screen, and your other characters keep theirs."]
    end
    pendingBind = { key = fullKey, command = h.command, label = h.label, profile = h.profile }
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

---------------------------------------------------------------------------
-- Removing: a key's action from its bar slot, or the key's binding
---------------------------------------------------------------------------
local pendingRemove

local function RemoveFromBar(slot)
    if ns.InCombat() then return Refused(L["Not in combat: try again when combat ends."]) end
    local label = SlotLabel(slot)
    if not label then return false end
    local state = ns.CurrentState()
    state.slots[slot] = nil
    return ns.ApplyChange(state, { keys = false }, L["%s removed from its bar"]:format(label),
        L["removing %s"]:format(label))
end

local function UnbindKey(key)
    if ns.InCombat() then return Refused(L["Not in combat: try again when combat ends."]) end
    if ns.SharedKeybinds() then SaveBindings(2) end -- this character's own keybinds first
    local state = ns.CurrentState()
    Unbind(state, key)
    return ns.ApplyChange(state, { scope = "all" }, L["%s unbound"]:format(key), L["unbinding %s"]:format(key))
end

local function Dialog(which, def)
    if not StaticPopupDialogs[which] then
        def.timeout, def.whileDead, def.hideOnEscape, def.preferredIndex = 0, true, true, 3
        def.OnCancel = function() pendingRemove = nil end
        StaticPopupDialogs[which] = def
    end
end

local function TakePending()
    local p = pendingRemove
    pendingRemove = nil
    return p
end

-- Asks what to remove from a key (or a slot, with no key): its action from the bar, or
-- the key's binding. Nothing is removed without asking.
function ns.AskRemove(fullKey, slot, command)
    if ns.InCombat() then return Refused(L["Not in combat: try again when combat ends."]) end
    local label = slot and SlotLabel(slot)
    local bound = fullKey and command and command ~= ""
    if not label and not bound then return false end
    pendingRemove = { key = fullKey, slot = slot }
    local shared = bound and ns.SharedKeybinds() and ("\n\n" .. L["Unbinding gives this character its own keybinds first: your other characters keep theirs."]) or ""
    if label and bound then
        Dialog("KEYSTANCE_REMOVE_BOTH", {
            text = "%s",
            button1 = L["Remove from bar"],
            button3 = L["Unbind key"],
            button2 = CANCEL or "Cancel",
            OnAccept = function() local p = TakePending() if p then RemoveFromBar(p.slot) end end,
            OnAlt = function() local p = TakePending() if p then UnbindKey(p.key) end end,
        })
        StaticPopup_Show("KEYSTANCE_REMOVE_BOTH", L["%s: %s.\n\nRemove it from its bar, or unbind %s so the key does nothing?"]:format(fullKey, label, fullKey) .. shared)
    elseif label then
        Dialog("KEYSTANCE_REMOVE_SLOT", {
            text = "%s",
            button1 = L["Remove from bar"],
            button2 = CANCEL or "Cancel",
            OnAccept = function() local p = TakePending() if p then RemoveFromBar(p.slot) end end,
        })
        StaticPopup_Show("KEYSTANCE_REMOVE_SLOT", L["Remove %s from its bar?"]:format(label))
    else
        Dialog("KEYSTANCE_REMOVE_KEY", {
            text = "%s",
            button1 = L["Unbind key"],
            button2 = CANCEL or "Cancel",
            OnAccept = function() local p = TakePending() if p then UnbindKey(p.key) end end,
        })
        StaticPopup_Show("KEYSTANCE_REMOVE_KEY", L["%s: %s.\n\nUnbind %s so the key does nothing?"]:format(fullKey, ns.CommandName(command), fullKey) .. shared)
    end
    return true
end
