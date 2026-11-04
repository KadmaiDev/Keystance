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
-- True if the slot already holds this action. Two macros of one name are the same unless
-- both say whose they are (the account's or the character's) and differ.
local function Same(want, have)
    if not want or not have then return want == have end
    if want.t ~= have.t then return false end
    if want.t == "macro" then
        if want.name ~= have.name then return false end
        -- The slot holds one of two macros of that name, and which can't be read: the saved
        -- one is put there to be sure.
        if want.perChar ~= nil and have.ambiguous then return false end
        return want.perChar == nil or have.perChar == nil or want.perChar == have.perChar
    end
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
        -- Saved without saying whose (two of that name existed, or a save from before this was
        -- kept) while two share the name now: which one belongs here can't be told.
        if want.perChar == nil and select(2, ns.MacroKind(want.name)) then
            return L["two macros are called %s, so Keystance can't tell which one goes here"]:format(want.name)
        end
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

-- Makes slots 1-180 (or only those in `only`) match state.slots. Returns how many changed;
-- adds to the list of failures and the set of slots written.
local function ApplySlots(state, failures, only, written)
    local book = ScanBook()
    local changed = 0
    for slot = 1, ns.MANAGED_SLOTS do
        local want, have = state.slots[slot], (not only or only[slot]) and ns.DescribeSlot(slot)
        if only and not only[slot] then
            -- not part of this change
        elseif only and want and want.t == "macro" and want.ambiguous and Same(want, have) then
            -- Undoing a slot that held one of two macros of one name: which one can't be told.
            failures[#failures + 1] = L["slot %d (%s): %s"]:format(slot, Describe(want),
                L["two macros are called %s, so Keystance can't tell which one goes here"]:format(want.name))
        elseif not Same(want, have) and have and not PLACEABLE[have.t] then
            failures[#failures + 1] = L["slot %d holds %s, which Keystance couldn't put back, so it's left as it is"]
                :format(slot, Describe(have))
        elseif not Same(want, have) then
            if not want then
                PickupAction(slot)
                ClearCursor()
                changed = changed + 1
                written[slot] = true
            else
                local why = Pickup(want, book)
                if why then
                    ClearCursor()
                    failures[#failures + 1] = L["slot %d (%s): %s"]:format(slot, Describe(want), why)
                else
                    PlaceAction(slot)
                    ClearCursor() -- placing onto a filled slot puts the old action on the cursor
                    changed = changed + 1
                    written[slot] = true
                end
            end
        end
    end
    return changed
end

---------------------------------------------------------------------------
-- Keys: worked out first as a list of writes ({ key, command or false to unbind }), so
-- nothing is written when the change can't go ahead.
---------------------------------------------------------------------------
-- Makes the bindings match state.binds for the commands in scope ("bars": bar buttons
-- only; "all": every command). A wanted key bound elsewhere is taken over.
local function PlanBinds(state, scope, writes)
    local inScope = scope == "all" and function() return true end or ns.IsBarCommand
    local want = {} -- [key] = command
    for command, keys in pairs(state.binds) do
        if inScope(command) then
            for _, key in ipairs(keys) do want[key] = command end
        end
    end
    local planned = {}
    -- Keys now bound in scope that the state doesn't bind to the same command.
    for command, keys in pairs(ns.ReadBindings()) do
        if inScope(command) then
            for _, key in ipairs(keys) do
                if want[key] ~= command and not planned[key] then
                    writes[#writes + 1] = { key, want[key] or false }
                    planned[key] = true
                end
            end
        end
    end
    -- Keys the state binds that aren't bound that way yet.
    for key, command in pairs(want) do
        if not planned[key] and GetBindingAction(key) ~= command then
            writes[#writes + 1] = { key, command }
            planned[key] = true
        end
    end
end

-- Puts back only these keys as the state had them (bound to its command, or unbound):
-- an undo touches the keys its change touched, nothing else.
local function PlanKeys(state, keys, writes)
    local was = {}
    for command, list in pairs(state.binds) do
        for _, key in ipairs(list) do was[key] = command end
    end
    for key in pairs(keys) do
        local want, now = was[key], GetBindingAction(key)
        if (want or "") ~= (now or "") then writes[#writes + 1] = { key, want or false } end
    end
end

---------------------------------------------------------------------------
-- Checking saved data before it's used: a profile, snapshot or undo record damaged in the
-- saved file (or by another addon) is refused whole, before anything changes, and left as
-- it is in the save.
---------------------------------------------------------------------------
local function BadAction(a)
    if type(a) ~= "table" or type(a.t) ~= "string" then return true end
    if a.t == "macro" then
        return type(a.name) ~= "string" or (a.perChar ~= nil and type(a.perChar) ~= "boolean")
    end
    if a.t == "spell" then return type(a.id) ~= "number" or (a.name ~= nil and type(a.name) ~= "string") end
    if a.t == "item" or a.t == "flyout" then return type(a.id) ~= "number" end
    return false -- other kinds are never placed, only left alone
end

-- True if `binds` is { [command] = { key, ... } }; else false and what's wrong.
function ns.CheckBinds(binds)
    if type(binds) ~= "table" then return false, L["its keys"] end
    for command, keys in pairs(binds) do
        if type(command) ~= "string" or type(keys) ~= "table" then
            return false, L["the keys of %s"]:format(tostring(command))
        end
        for i, key in pairs(keys) do
            if type(i) ~= "number" or type(key) ~= "string" then
                return false, L["the keys of %s"]:format(command)
            end
        end
    end
    return true
end

-- True if the state can be applied (keys too, with `needBinds`); else false and what part
-- of it is damaged.
function ns.CheckState(state, needBinds)
    if type(state) ~= "table" or type(state.slots) ~= "table" then return false, L["its action bars"] end
    for slot, a in pairs(state.slots) do
        if type(slot) ~= "number" or BadAction(a) then return false, L["slot %s"]:format(tostring(slot)) end
    end
    if needBinds or state.binds ~= nil then return ns.CheckBinds(state.binds) end
    return true
end

-- Whether a change can go ahead now (combat, the cursor, the state itself, and the "Before
-- Keystance" snapshot, which comes before Keystance's first change: until the game has
-- loaded the bars and keys it can't be taken, so nothing changes yet). ok, or false and why.
function ns.CanChange(state, needBinds)
    if InCombatLockdown() then return false, L["in combat"] end
    if GetCursorInfo() then return false, L["put down what you're holding on the cursor first"] end
    if state ~= nil then
        local ok, where = ns.CheckState(state, needBinds)
        if not ok then return false, L["the saved setup is damaged (%s), so it was left alone"]:format(where) end
    end
    if not ns.TakeSnapshot() then return false, L["your bars and keys haven't loaded yet; try again in a moment"] end
    return true
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
-- of slots and onlyKeys = a set of keys limit it to those (an undo). Keys shared by the
-- whole account are never written: with ownKeys the character gets its own keybinds first
-- (nothing changes on screen, the others keep theirs), else nothing changes and the third
-- value is "shared". Returns ok, slotsChanged, keysChanged, failures, the set of slots
-- written; ok is false (with a reason) if it didn't start.
function ns.ApplyState(state, options)
    options = options or {}
    local ok, why = ns.CanChange(state, options.keys ~= false)
    if not ok then return false, why end
    local writes = {}
    if options.onlyKeys then
        PlanKeys(state, options.onlyKeys, writes)
    elseif options.keys ~= false then
        PlanBinds(state, options.scope or "bars", writes)
    end
    if #writes > 0 and ns.SharedKeybinds() then
        if not options.ownKeys then return false, L["your keybinds are shared by all your characters"], "shared" end
        SaveBindings(2) -- this character's own keybinds, a copy of the shared ones (measured)
    end
    local failures, written = {}, {}
    local slots = ApplySlots(state, failures, options.only, written)
    for _, w in ipairs(writes) do
        if w[2] then SetBinding(w[1], w[2]) else SetBinding(w[1]) end
    end
    if #writes > 0 then SaveBindings(GetCurrentBindingSet()) end
    return true, slots, #writes, failures, written
end

-- How many slots and keys applying the state would change (for the preview). A damaged
-- state changes nothing (applying it is refused).
function ns.CountChanges(state, scope)
    if not ns.CheckState(state, true) then return 0, 0 end
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
