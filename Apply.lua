-- Keystance's writer: makes the action bars and keybindings match a saved state (a profile,
-- the "Before Keystance" snapshot, or an undo record). It changes only what differs, never
-- empties a slot it can't fill (the slot is left as it was and reported), never removes an
-- action it couldn't put back (an equipment set, a mount), and never runs in combat
-- (callers go through ns.OutOfCombat). The snapshot is taken before its first write. Drops
-- (Drops.lua) place single actions with the game's own pick-up and place, as a player does.
--
-- A state is { slots = { [slot] = action from ns.DescribeSlot }, binds = { [command] = { keys } } }.
-- Slots 1-180 are managed; 181 and above mirror the main bar (seen in a snapshot) and are
-- left alone.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)
local L = ns.L

local pairs, ipairs = pairs, ipairs
local GetCursorInfo, ClearCursor = GetCursorInfo, ClearCursor
local PickupAction, PlaceAction, GetBindingAction = PickupAction, PlaceAction, GetBindingAction

ns.MANAGED_SLOTS = 180

local BANK = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
local SPELL, FLYOUT = 1, 4
if Enum and Enum.SpellBookItemType then
    SPELL, FLYOUT = Enum.SpellBookItemType.Spell or 1, Enum.SpellBookItemType.Flyout or 4
end

-- A command that fires an action slot (a bar button); profiles manage only these keys.
function ns.IsBarCommand(command)
    return ns.CommandSlot(command) ~= nil
end

---------------------------------------------------------------------------
-- The spellbook, for finding a spell's known rank and a flyout's index
---------------------------------------------------------------------------
-- { byName = { [name] = { ids, highest first } }, known = { [id] = true }, flyouts = { [id] = index } }
local function ScanBook()
    local book = { byName = {}, known = {}, flyouts = {} }
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local li = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if li then
            for i = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
                local info = C_SpellBook.GetSpellBookItemInfo(i, BANK)
                if info and info.itemType == FLYOUT then
                    book.flyouts[info.actionID] = i
                elseif info and info.itemType == SPELL and info.spellID then
                    book.known[info.spellID] = true
                    local ids = book.byName[info.name]
                    if not ids then
                        ids = {}
                        book.byName[info.name] = ids
                    end
                    -- The spellbook lists ranks lowest first (measured), so the last is highest.
                    table.insert(ids, 1, info.spellID)
                end
            end
        end
    end
    return book
end
ns.ScanBook = ScanBook

---------------------------------------------------------------------------
-- Slots
---------------------------------------------------------------------------
-- True if the slot already holds this action.
local function Same(want, have)
    if not want or not have then return want == have end
    if want.t ~= have.t then return false end
    if want.t == "macro" then return want.name == have.name end
    return want.id == have.id
end
ns.SameAction = Same

-- The kinds of action Keystance can put in a slot (Pickup below). Anything else in a slot
-- (an equipment set, a mount, a companion) is left alone: removed, it couldn't come back.
local PLACEABLE = { spell = true, macro = true, item = true, flyout = true }

-- A macro's index by name: the character's own or the account's, as saved (two can share a
-- name); either if the saved kind has gone.
local function MacroIndex(want)
    if want.perChar ~= nil and GetMacroInfo then
        local account = MAX_ACCOUNT_MACROS or 120
        local first = want.perChar and account + 1 or 1
        local last = want.perChar and account + (MAX_CHARACTER_MACROS or 18) or account
        for i = first, last do
            if GetMacroInfo(i) == want.name then return i end
        end
    end
    return GetMacroIndexByName(want.name)
end

-- True if the character knows this very spell (a rank, or one outside the class spellbook,
-- like a profession's).
local function Knows(id, book)
    if book.known[id] then return true end
    if IsPlayerSpell then
        local ok, known = pcall(IsPlayerSpell, id)
        if ok and known then return true end
    end
    if IsSpellKnown then
        local ok, known = pcall(IsSpellKnown, id)
        if ok and known then return true end
    end
    return false
end

-- Puts the action on the cursor. Returns nil, or a reason it couldn't.
local function Pickup(want, book)
    if want.t == "spell" then
        local id = want.id
        if not Knows(id, book) then
            -- Not this rank (the player may have trained past it): the highest of that name.
            local ids = book.byName[want.name or ""]
            id = ids and ids[1]
            if not id then return L["%s isn't known"]:format(want.name or ("#" .. tostring(want.id))) end
        end
        C_Spell.PickupSpell(id)
    elseif want.t == "macro" then
        local index = want.name and MacroIndex(want) or 0
        if not index or index == 0 then return L["macro '%s' not found"]:format(tostring(want.name)) end
        PickupMacro(index)
    elseif want.t == "item" then
        C_Item.PickupItem(want.id)
    elseif want.t == "flyout" then
        local index = book.flyouts[want.id]
        if not index then return L["that spell group isn't known"] end
        C_SpellBook.PickupSpellBookItem(index, BANK)
    else
        return L["can't place a %s"]:format(tostring(want.t))
    end
    if not GetCursorInfo() then return L["couldn't pick it up"] end
    return nil
end

local function Describe(want)
    if not want then return L["empty"] end
    return want.name or (tostring(want.t) .. " " .. tostring(want.id))
end

-- Makes slots 1-180 (or only those in `only`) match state.slots. Returns how many changed
-- and a list of failures.
local function ApplySlots(state, failures, only)
    local book = ScanBook()
    local changed = 0
    for slot = 1, ns.MANAGED_SLOTS do
        local want, have = state.slots[slot], (not only or only[slot]) and ns.DescribeSlot(slot)
        if only and not only[slot] then
            -- not part of this change
        elseif not Same(want, have) and have and not PLACEABLE[have.t] then
            failures[#failures + 1] = L["slot %d holds %s, which Keystance couldn't put back, so it's left as it is"]
                :format(slot, Describe(have))
        elseif not Same(want, have) then
            if not want then
                PickupAction(slot)
                ClearCursor()
                changed = changed + 1
            else
                local why = Pickup(want, book)
                if why then
                    ClearCursor()
                    failures[#failures + 1] = L["slot %d (%s): %s"]:format(slot, Describe(want), why)
                else
                    PlaceAction(slot)
                    ClearCursor() -- placing onto a filled slot puts the old action on the cursor
                    changed = changed + 1
                end
            end
        end
    end
    return changed
end

---------------------------------------------------------------------------
-- Keys
---------------------------------------------------------------------------
-- Makes the bindings match state.binds for the commands in scope ("bars": bar buttons
-- only; "all": every command). A wanted key bound elsewhere is taken over. Returns how
-- many keys changed.
local function ApplyBinds(state, scope)
    local inScope = scope == "all" and function() return true end or ns.IsBarCommand
    local want = {} -- [key] = command
    for command, keys in pairs(state.binds or {}) do
        if inScope(command) then
            for _, key in ipairs(keys) do want[key] = command end
        end
    end
    local changed = 0
    -- Keys now bound in scope that the state doesn't bind to the same command.
    for command, keys in pairs(ns.ReadBindings()) do
        if inScope(command) then
            for _, key in ipairs(keys) do
                if want[key] ~= command then
                    if want[key] then SetBinding(key, want[key]) else SetBinding(key) end
                    changed = changed + 1
                end
            end
        end
    end
    -- Keys the state binds that aren't bound that way yet.
    for key, command in pairs(want) do
        if GetBindingAction(key) ~= command then
            SetBinding(key, command)
            changed = changed + 1
        end
    end
    if changed > 0 then SaveBindings(GetCurrentBindingSet()) end
    return changed
end

-- Puts back only these keys as the state had them (bound to its command, or unbound):
-- an undo touches the keys its change touched, nothing else.
local function ApplyKeys(state, keys)
    local was = {}
    for command, list in pairs(state.binds or {}) do
        for _, key in ipairs(list) do was[key] = command end
    end
    local changed = 0
    for key in pairs(keys) do
        local want, now = was[key], GetBindingAction(key)
        if (want or "") ~= (now or "") then
            if want then SetBinding(key, want) else SetBinding(key) end
            changed = changed + 1
        end
    end
    if changed > 0 then SaveBindings(GetCurrentBindingSet()) end
    return changed
end

---------------------------------------------------------------------------
-- The whole state
---------------------------------------------------------------------------
-- The current bars and keys, as a state (for undo).
function ns.CurrentState()
    local slots = {}
    for slot = 1, ns.MANAGED_SLOTS do slots[slot] = ns.DescribeSlot(slot) end
    return { slots = slots, binds = (ns.ReadBindings()) }
end

-- Applies a state now. Must not be called in combat (use ns.OutOfCombat). options:
-- scope = "bars" (default) or "all" for keys; keys = false leaves keys alone; only = a set
-- of slots and onlyKeys = a set of keys limit it to those (an undo). Returns ok,
-- slotsChanged, keysChanged, failures; ok is false (with a reason) if it didn't start.
function ns.ApplyState(state, options)
    options = options or {}
    if InCombatLockdown() then return false, L["in combat"] end
    if GetCursorInfo() then return false, L["put down what you're holding on the cursor first"] end
    ns.TakeSnapshot() -- the "Before Keystance" setup comes before Keystance's first change
    local failures = {}
    local slots = ApplySlots(state, failures, options.only)
    local keys = 0
    if options.onlyKeys then
        keys = ApplyKeys(state, options.onlyKeys)
    elseif options.keys ~= false then
        keys = ApplyBinds(state, options.scope or "bars")
    end
    return true, slots, keys, failures
end

-- How many slots and keys applying the state would change (for the preview).
function ns.CountChanges(state, scope)
    local slots = 0
    for slot = 1, ns.MANAGED_SLOTS do
        if not Same(state.slots[slot], ns.DescribeSlot(slot)) then slots = slots + 1 end
    end
    local inScope = scope == "all" and function() return true end or ns.IsBarCommand
    local want, keys = {}, 0
    for command, list in pairs(state.binds or {}) do
        if inScope(command) then for _, key in ipairs(list) do want[key] = command end end
    end
    for command, list in pairs(ns.ReadBindings()) do
        if inScope(command) then
            for _, key in ipairs(list) do if want[key] ~= command then keys = keys + 1 end end
        end
    end
    -- Keys the state binds that aren't bound that way yet (a key bound to another bar button
    -- was counted above already: applying moves it once).
    for key, command in pairs(want) do
        local now = GetBindingAction(key)
        if now ~= command and not (now ~= "" and inScope(now)) then keys = keys + 1 end
    end
    return slots, keys
end
