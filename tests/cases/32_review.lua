-- Tests: the 1.0 review's findings. Nothing changes the account's shared keybinds; damaged
-- saved data is refused before anything changes; nothing changes before the "Before
-- Keystance" snapshot exists; Undo puts back everything its change touched (profiles' keys,
-- which profile a key belongs to, gear taken from another gear slot) and stops a gear swap
-- still under way; Update never saves gear halfway through a swap or unreadable; and a slot
-- holding one of two macros of one name is never mistaken for the other.

local function gearString(id) return "item:" .. id .. ":0:0:0:0:0:0:0:20" end

local function copyTable(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

local function acceptPopup()
    StaticPopupDialogs[wow.popup.which].OnAccept(nil, wow.popup.data)
end

---------------------------------------------------------------------------
-- Shared keybinds
---------------------------------------------------------------------------
test("own keybinds then apply, while another switch waits for combat: the account's keys are never written", function()
    local c, ns = profileLogin(true)
    local keys = copyTable(wow.bindings)
    ns.SaveProfile("A")            -- keys as they are: applying it changes no key
    shuffle()
    ns.SaveProfile("B")            -- different keys
    wow.bindings = copyTable(keys)
    wow.enterCombat()
    ns.ApplyProfile("A")           -- waits for combat, no question (no key changes)
    ns.ApplyProfile("B")           -- would change keys: asks
    eq(wow.popup.which, "KEYSTANCE_SHARED_KEYS")
    acceptPopup()                  -- "Own keybinds, then apply"
    wow.leaveCombat()
    eq(wow.savedSets[1], nil, "the account's keybinds were never saved over")
    eq(wow.bindingSet, 2, "the character has its own keybinds")
    eq(GetBindingAction("E"), "ACTIONBUTTON5", "B's keys")
    eq(c.active, "B")
end)

test("a profile queued without a question, whose keys differ by the time it runs, asks then", function()
    local c, ns = profileLogin(true)
    local keys = copyTable(wow.bindings)
    shuffle()
    ns.SaveProfile("B")
    wow.bindings = copyTable(keys)
    wow.popup = nil
    -- Asked while combat makes the keys look the same (as if they matched), runs later.
    local count = ns.CountChanges
    ns.CountChanges = function() return 0, 0 end
    wow.enterCombat()
    ns.ApplyProfile("B")
    ns.CountChanges = count
    wow.leaveCombat()
    eq(wow.popup and wow.popup.which, "KEYSTANCE_SHARED_KEYS", "asked when it ran")
    eq(wow.savedSets[1], nil)
    eq(GetBindingAction("E"), "", "nothing applied without an answer")
end)

test("Restore on shared keybinds gives the character its own first: the account's keys stay", function()
    local c, ns = profileLogin(true)
    eq(c.snapshot.set, 1)
    wow.bindings.E = "ACTIONBUTTON5" -- the account's keys changed since (another character)
    ns.RestoreOriginal()
    eq(wow.savedSets[1], nil, "the account's keys were never saved over")
    eq(wow.bindingSet, 2)
    eq(GetBindingAction("E"), "", "this character's keys are as in the snapshot")
end)

test("Restore's question says the character gets its own keybinds when they're shared", function()
    local c, ns = profileLogin(true)
    ns.ConfirmRestore()
    assert(wow.popup.text:find("gets its own first", 1, true), wow.popup.text)
end)

test("Undo after switching back to the account's keybinds doesn't write them", function()
    local c, ns = profileLogin()
    ns.SaveProfile("Ret")
    shuffle()
    ns.SaveProfile("Shuffled")
    ns.ApplyProfile("Ret")
    wow.bindingSet = 1 -- the player chose the account's keybinds again in the game's settings
    wow.savedSets[1] = nil
    ns.Undo()
    eq(wow.savedSets[1], nil, "the account's keybinds were never saved over")
    eq(wow.bindingSet, 2)
end)

test("the writer itself refuses keys on shared keybinds unless told to give the character its own", function()
    local c, ns = profileLogin(true)
    local state = ns.CurrentState()
    state.binds.ACTIONBUTTON5 = { "E" }
    local ok, why, shared = ns.ApplyState(state, { scope = "all" })
    eq(ok, false); eq(shared, "shared")
    eq(GetBindingAction("E"), "")
    eq(wow.bindingSet, 1)
    assert(ns.ApplyState(state, { scope = "all", ownKeys = true }))
    eq(GetBindingAction("E"), "ACTIONBUTTON5"); eq(wow.bindingSet, 2)
    eq(wow.savedSets[1], nil)
end)

---------------------------------------------------------------------------
-- Damaged saved data
---------------------------------------------------------------------------
test("a profile with a damaged key list changes nothing at all: bars, keys, gear and Undo", function()
    local c, ns = gearLogin()
    wow.slots[1] = { kind = "spell", id = 647 }
    ns.SaveProfile("Ret")
    ns.SetProfileGear("Ret", { [16] = gearString(1680) })
    c.profiles.Ret.binds.ACTIONBUTTON1 = 5
    wow.slots[1] = { kind = "spell", id = 1866 }
    c.lastChange = nil
    ns.ApplyProfile("Ret")
    settleGear()
    eq(slotId(1), 1866, "bars untouched")
    eq(wow.idOf(wow.inventory[16]), 2132, "gear untouched")
    eq(c.lastChange, nil, "no undo record")
    eq(c.profiles.Ret.binds.ACTIONBUTTON1, 5, "the saved profile is left as it was")
    assert(printed():find("damaged", 1, true), printed())
end)

test("a damaged action late in the bars, or no key list, is refused before the first slot changes", function()
    local c, ns = profileLogin()
    ns.SaveProfile("Ret")
    shuffle()
    c.profiles.Ret.slots[170] = { t = "spell" } -- no spell ID
    ns.ApplyProfile("Ret")
    eq(slotId(1), 647, "slot 1 not changed")
    c.profiles.Ret.slots[170] = nil
    c.profiles.Ret.binds = nil
    ns.ApplyProfile("Ret")
    eq(slotId(1), 647, "still not changed")
    eq(GetBindingAction("E"), "ACTIONBUTTON5", "keys not unbound")
    eq(select(1, ns.CountChanges(c.profiles.Ret, "bars")), 0, "a damaged profile counts no changes")
    -- Bars only doesn't need the keys.
    ns.ApplyProfile("Ret", false)
    eq(slotId(1), 1866)
end)

test("a damaged undo record or snapshot is refused and kept", function()
    local c, ns = profileLogin()
    ns.SaveProfile("Ret")
    shuffle()
    ns.ApplyProfile("Ret")
    c.lastChange.gear = { [16] = 12 }
    ns.Undo()
    eq(slotId(1), 1866, "not undone")
    eq(c.lastChange.gear[16], 12, "kept as it was")
    c.lastChange.gear = nil
    c.lastChange.keySlots = { [1] = 7 }
    ns.Undo()
    eq(slotId(1), 1866, "not undone")
    c.snapshot.binds = "oops"
    ns.RestoreOriginal()
    eq(slotId(1), 1866, "not restored")
    eq(c.snapshot.binds, "oops")
end)

test("a damaged save loads: wrong-typed settings and fields go, profiles' contents and the snapshot stay", function()
    local ns = start({ v = "x", settings = { skin = 5, heatmap = "yes", window = { "TOP" }, layout = "iso" },
        chars = { [1] = {}, Junk = 7, ["Vespera Ashward"] = {
            profiles = { Ret = { slots = 5, binds = {}, gear = { [16] = 9, [17] = "item:2129" }, icon = {} }, [2] = {}, Bad = 3 },
            rules = { { when = "shield", profile = "Ret" }, 4, { when = 1 } },
            keySlots = { [1] = "Ret", [2] = 9 }, lastChange = "x", active = 3, snapshot = "kept" } } })
    local db = KeystanceDB
    eq(db.v, 1)
    eq(db.settings.skin, "auto", "back to its default"); eq(db.settings.heatmap, nil); eq(db.settings.window, nil)
    eq(db.settings.layout, "iso", "good settings kept")
    eq(db.chars[1], nil); eq(db.chars.Junk, nil)
    local c = db.chars["Vespera Ashward"]
    eq(c.profiles.Ret.slots, 5, "a profile's slots aren't touched (refused when applied)")
    eq(c.profiles.Ret.gear[16], nil); eq(c.profiles.Ret.gear[17], "item:2129"); eq(c.profiles.Ret.icon, nil)
    eq(c.profiles[2], nil); eq(c.profiles.Bad, nil)
    eq(#c.rules, 1)
    eq(c.keySlots[1], "Ret"); eq(c.keySlots[2], nil)
    eq(c.lastChange, nil); eq(c.active, nil)
    eq(c.snapshot, "kept", "never dropped: a new one would call the current setup 'Before Keystance'")
    -- And the windows open with it.
    ns.ToggleWindow()
    for _, key in ipairs({ "profiles", "keyboard", "bars", "rules", "settings" }) do ns.ShowTab(key) end
    eq(#wow.errors, 0, tostring(wow.errors[1]))
end)

---------------------------------------------------------------------------
-- The "Before Keystance" snapshot comes first
---------------------------------------------------------------------------
test("before the keys have loaded, nothing changes the bars or keys; once they have, the snapshot is the original", function()
    local ns = wow.load(FILES)
    paladinSetup()
    local keys = wow.bindings
    wow.bindings = {}
    wow.login(nil)
    wow.fire("PLAYER_ENTERING_WORLD", true, false)
    wow.runTimers()
    local c = KeystanceDB.chars["Vespera Ashward"]
    eq(c.snapshot, nil)
    wow.cursor = { "spell", 1, "spell", 647 }
    eq(ns.DropOnSlot(5), false); eq(wow.slots[5], nil)
    wow.cursor = nil
    eq(ns.PickupFromSlot(1), false); eq(slotId(1), 1866)
    eq(ns.OwnKeybindsFirst(), false); eq(wow.bindingSet, 1)
    local state = ns.CurrentState()
    state.slots[1] = nil
    eq(ns.ApplyState(state, { keys = false }), false); eq(slotId(1), 1866)
    eq(c.lastChange, nil)
    -- The keys arrive.
    wow.bindings = keys
    for _ = 1, 3 do wow.runTimers() end
    eq(c.snapshot.slots[1].id, 1866, "the original bars")
    eq(c.snapshot.binds.ACTIONBUTTON1[1], "1")
end)

test("bars that stay empty are the player's: after the tries, the snapshot is taken with keys only", function()
    local ns = wow.load(FILES)
    paladinSetup()
    wow.slots = {}
    wow.login(nil)
    wow.fire("PLAYER_ENTERING_WORLD", true, false)
    for _ = 1, 12 do wow.runTimers() end
    local c = KeystanceDB.chars["Vespera Ashward"]
    assert(c.snapshot, "taken")
    eq(c.snapshot.nSlots, 0)
end)

---------------------------------------------------------------------------
-- Undo puts back what else the change touched
---------------------------------------------------------------------------
test("Undo of moving the hand, refused (something on the cursor), leaves the profiles' keys moved too", function()
    local c, ns = loginWithSetup(nil)
    wow.bindings.A, wow.bindings.S, wow.bindings.D = "STRAFELEFT", "MOVEBACKWARD", "STRAFERIGHT"
    wow.bindingSet = 2
    wow.fire("UPDATE_BINDINGS")
    wow.bindings.Q = "ACTIONBUTTON4"
    ns.SaveProfile("Ret")
    ns.AskShiftHand(1)
    acceptPopup()
    eq(GetBindingAction("W"), "ACTIONBUTTON4", "Q's bind moved to W")
    eq(c.profiles.Ret.binds.ACTIONBUTTON4[1], "W")
    wow.cursor = { "spell", 1, "spell", 647 }
    ns.Undo()
    eq(GetBindingAction("W"), "ACTIONBUTTON4", "live keys still moved")
    eq(c.profiles.Ret.binds.ACTIONBUTTON4[1], "W", "and the profile's keys with them")
    wow.cursor = nil
    ns.Undo()
    eq(GetBindingAction("Q"), "ACTIONBUTTON4")
    eq(c.profiles.Ret.binds.ACTIONBUTTON4[1], "Q")
end)

test("Undo of taking a profile's key off gives the key back to that profile", function()
    local c, ns = profileLogin()
    ns.SaveProfile("Ret")
    ns.SetProfileKey("Ret", "F2")
    eq(ns.ProfileSlot("Ret"), 1)
    ns.ClearProfileKey("Ret")
    eq(ns.ProfileSlot("Ret"), nil)
    ns.Undo()
    eq(GetBindingAction("F2"), "KEYSTANCE_PROFILE1")
    eq(ns.ProfileSlot("Ret"), 1, "the key belongs to Ret again")
    eq(BINDING_NAME_KEYSTANCE_PROFILE1, "Profile 1: Ret")
    wow.printed = {}
    Keystance_Binding(1)
    assert(not printed():find("No profile is on this key", 1, true), printed())
    -- And a second Undo takes it off again.
    ns.Undo()
    eq(GetBindingAction("F2"), ""); eq(ns.ProfileSlot("Ret"), nil)
end)

test("Undo of giving a profile its first key frees the slot again", function()
    local c, ns = profileLogin()
    ns.SaveProfile("Ret")
    ns.SetProfileKey("Ret", "F2")
    ns.Undo()
    eq(GetBindingAction("F2"), "")
    eq(ns.ProfileSlot("Ret"), nil, "not kept for Ret")
end)

---------------------------------------------------------------------------
-- Gear
---------------------------------------------------------------------------
-- A two-hander profile, with the helm slot locked (the game still moving it), so the swap
-- waits without moving anything.
local function waitingSwap()
    local c, ns = gearLogin()
    wow.slots[1] = { kind = "spell", id = 647 }
    ns.SaveProfile("Two")
    ns.SetProfileGear("Two", { [16] = gearString(1680) })
    ns.SaveProfile("Bars")
    wow.locked[1] = true
    ns.ApplyProfile("Two")
    wow.runTimers()
    eq(wow.idOf(wow.inventory[16]), 2132, "waiting")
    return c, ns
end

test("Undo while the profile's swap is still waiting stops it: the old gear stays", function()
    local c, ns = waitingSwap()
    ns.Undo()
    wow.unlock()
    settleGear()
    eq(wow.idOf(wow.inventory[16]), 2132, "the one-hander stays")
    eq(wow.idOf(wow.inventory[17]), 2129, "and the shield")
end)

test("another profile while a swap is still waiting stops it, even one with no gear", function()
    local c, ns = waitingSwap()
    ns.ApplyProfile("Bars")
    wow.unlock()
    settleGear()
    eq(wow.idOf(wow.inventory[16]), 2132)
    eq(c.active, "Bars")
end)

test("a ring moved from one ring slot to the other goes back to its own slot on Undo", function()
    local c, ns = gearLogin()
    wow.inventory[11], wow.inventory[12] = nil, 1000
    wow.slots[1] = { kind = "spell", id = 647 }
    ns.SaveProfile("Ring")
    ns.SetProfileGear("Ring", { [11] = gearString(1000) })
    ns.ApplyProfile("Ring")
    settleGear()
    eq(wow.idOf(wow.inventory[11]), 1000); eq(wow.inventory[12], nil)
    eq(c.lastChange.gear[12], gearString(1000), "the slot it came from is in the record")
    ns.Undo()
    settleGear()
    eq(wow.idOf(wow.inventory[12]), 1000, "back in the second ring slot")
    eq(wow.inventory[11], nil)
end)

test("Update halfway through a swap keeps the profile's saved gear", function()
    local c, ns = gearLogin()
    wow.slots[1] = { kind = "spell", id = 647 }
    ns.SaveProfile("Two")
    ns.SetProfileGear("Two", { [16] = gearString(1680), [17] = gearString(2129) })
    wow.lockMoves = true
    ns.ApplyProfile("Two")
    wow.runTimers()
    eq(wow.inventory[17], nil, "the shield went to the bags first")
    eq(wow.idOf(wow.inventory[16]), 2132, "the two-hander isn't on yet")
    ns.SaveProfile("Two", true)
    eq(c.profiles.Two.gear[16], gearString(1680), "the saved weapon is kept")
    eq(c.profiles.Two.gear[17], gearString(2129))
    assert(printed():find("still being changed", 1, true), printed())
end)

test("Update keeps the saved gear while an item is still moving, even with no swap of Keystance's", function()
    local c, ns = gearLogin()
    ns.SaveProfile("Prot")
    ns.SetProfileGear("Prot", { [16] = gearString(2132), [17] = gearString(2129) })
    wow.locked[17] = true
    ns.SaveProfile("Prot", true)
    eq(c.profiles.Prot.gear[17], gearString(2129))
    eq(ns.CaptureGear(nil, true), nil)
end)

test("gear the game won't read (a secret value) is never saved as empty", function()
    local c, ns = gearLogin()
    ns.SaveProfile("Prot")
    ns.SetProfileGear("Prot", { [16] = gearString(2132), [17] = gearString(2129) })
    for _, kind in ipairs({ "id", "link" }) do
        wow.secretSlots = { [17] = kind }
        eq(ns.CaptureGear(nil, false), nil, kind)
        eq(ns.CaptureGear(nil, true), nil, kind .. " (Undo's record)")
        ns.SaveProfile("Prot", true)
        eq(c.profiles.Prot.gear[17], gearString(2129), "Update keeps it (" .. kind .. ")")
    end
    wow.secretSlots = { [17] = "id" }
    eq(ns.GearStatus({ [17] = gearString(2129) }), nil, "not read as missing either")
end)

---------------------------------------------------------------------------
-- Two macros of one name
---------------------------------------------------------------------------
-- An account macro and a character macro both called Buff (macros are packed: the
-- account's from 1, the character's from 121).
local function twoBuffs()
    local c, ns = profileLogin()
    wow.macros[1] = { name = "Buff", body = "/cast A" }
    wow.macros[122] = { name = "Buff", body = "/cast B" }
    return c, ns
end

test("a slot holding one of two macros of one name isn't said to be either", function()
    local c, ns = twoBuffs()
    wow.slots[8] = { kind = "macro", macro = 1 }
    local m = ns.DescribeSlot(8)
    eq(m.perChar, nil); eq(m.ambiguous, true)
    wow.macros[122] = nil
    eq(ns.DescribeSlot(8).perChar, false, "one of that name: the account's")
end)

test("the character's macro saved: applied over the account's of that name, and Undo says it can't tell", function()
    local c, ns = twoBuffs()
    ns.SaveProfile("Ret")
    c.profiles.Ret.slots[8] = { t = "macro", name = "Buff", perChar = true } -- saved when it was the only one
    wow.slots[8] = { kind = "macro", macro = 1 }
    ns.ApplyProfile("Ret")
    eq(wow.slots[8].macro, 122, "the character's goes on")
    eq(c.lastChange.only[8], true, "Undo knows the slot changed")
    wow.printed = {}
    ns.Undo()
    assert(printed():find("two macros are called Buff", 1, true), printed())
    eq(wow.slots[8].macro, 122, "left as it is rather than guessed")
end)

test("a macro saved while two shared its name isn't guessed when applied", function()
    local c, ns = twoBuffs()
    wow.slots[8] = { kind = "macro", macro = 122 }
    ns.SaveProfile("Ret")
    eq(c.profiles.Ret.slots[8].perChar, nil)
    wow.slots[8] = nil
    ns.ApplyProfile("Ret")
    eq(wow.slots[8], nil, "left empty")
    assert(printed():find("two macros are called Buff", 1, true), printed())
end)
