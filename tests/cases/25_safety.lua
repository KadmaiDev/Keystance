-- Tests: the safety net found in the pre-release review: nothing Keystance can't put back is
-- removed, Undo touches only what its change touched, the snapshot comes first, and one
-- failing job or handler can't stop the rest.

test("an action Keystance couldn't put back (a mount) is left in its slot, and said", function()
    local c, ns = profileLogin()
    ns.SaveProfile("Ret") -- slot 5 empty
    wow.slots[5] = { kind = "summonmount", id = 77 }
    ns.ApplyProfile("Ret")
    eq(wow.slots[5] and wow.slots[5].kind, "summonmount", "not removed")
    assert(printed():find("couldn't put back, so it's left as it is", 1, true), printed())
end)

test("a queued job that fails is reported and doesn't stop the others, then or later", function()
    local c, ns = profileLogin()
    wow.enterCombat()
    local ran = {}
    ns.OutOfCombat("broken", function() error("boom") end)
    ns.OutOfCombat("fine", function() ran[#ran + 1] = "fine" end)
    wow.leaveCombat()
    eq(ran[1], "fine")
    eq(#wow.errors, 1, "the failure is reported (BugGrabber), not hidden")
    eq(ns.Waiting(), false, "nothing left jammed")
    wow.enterCombat()
    ns.OutOfCombat("again", function() ran[#ran + 1] = "again" end)
    wow.leaveCombat()
    eq(ran[2], "again")
end)

test("an event handler that fails doesn't stop the next one", function()
    local c, ns = profileLogin()
    local ran = false
    ns.On("UPDATE_MACROS", function() error("boom") end)
    ns.On("UPDATE_MACROS", function() ran = true end)
    wow.fire("UPDATE_MACROS")
    eq(ran, true)
    eq(#wow.errors, 1)
end)

test("Undo puts back only what its change touched, not changes made since", function()
    local c, ns = profileLogin()
    ns.SaveProfile("Ret")
    wow.slots[1] = { kind = "spell", id = 647 }
    ns.ApplyProfile("Ret") -- slot 1 back to Holy Strike
    eq(slotId(1), 1866)
    -- Since then, by hand: a spell in slot 7 and a key.
    wow.slots[7] = { kind = "spell", id = 19834 }
    wow.bindings.F9 = "ACTIONBUTTON7"
    ns.Undo()
    eq(slotId(1), 647, "the change undone")
    eq(slotId(7), 19834, "the later change kept")
    eq(GetBindingAction("F9"), "ACTIONBUTTON7")
    ns.Undo() -- and redo, the same way
    eq(slotId(1), 1866)
    eq(slotId(7), 19834)
end)

test("the apply preview counts a key moving between bar buttons once", function()
    local c, ns = profileLogin()
    ns.SaveProfile("Ret")
    local p = c.profiles.Ret
    p.binds.ACTIONBUTTON1, p.binds.ACTIONBUTTON2 = nil, { "1", "2", "NUMPAD1" }
    local _, keys = ns.CountChanges(p, "bars")
    eq(keys, 1, "key 1 moves from button 1 to button 2: one change")
    ns.ApplyProfile("Ret")
    assert(printed():find("1 keys changed", 1, true), printed())
end)

test("the Before Keystance snapshot is taken before Keystance's first change, even a quick one", function()
    local c, ns = profileLogin()
    c.snapshot = nil -- as if the first try hasn't happened yet
    local before = slotId(1)
    wow.slots[1] = { kind = "spell", id = 647 }
    ns.SaveProfile("Holy")
    wow.slots[1] = { kind = "spell", id = before }
    ns.ApplyProfile("Holy")
    eq(c.snapshot.slots[1].id, before, "the setup from before the change")
end)

test("a spell outside the class spellbook (a profession's) can be put back", function()
    local c, ns = profileLogin()
    wow.otherSpells[3273] = true
    wow.spellNames[3273] = "First Aid"
    wow.slots[9] = { kind = "spell", id = 3273 }
    ns.SaveProfile("Ret")
    wow.slots[9] = nil
    ns.ApplyProfile("Ret")
    eq(slotId(9), 3273)
end)

test("an account macro and a character macro with one name: the saved one goes back", function()
    local c, ns = profileLogin()
    wow.macros[3] = { name = "Buff", body = "/cast A" }
    wow.macros[121] = { name = "Buff", body = "/cast B" }
    ns.SaveProfile("Ret")
    c.profiles.Ret.slots[8] = { t = "macro", name = "Buff", perChar = true }
    ns.ApplyProfile("Ret")
    eq(wow.slots[8].macro, 121, "the character's")
    c.profiles.Ret.slots[8] = { t = "macro", name = "Buff", perChar = false }
    wow.slots[8] = nil
    ns.ApplyProfile("Ret")
    eq(wow.slots[8].macro, 3, "the account's")
end)

test("Update keeps a profile's chosen icon", function()
    local c, ns = profileLogin()
    ns.SaveProfile("Ret")
    ns.SetProfileIcon("Ret", 12345)
    ns.SaveProfile("Ret", true)
    eq(c.profiles.Ret.icon, 12345)
end)

test("renaming a profile keeps its switch waiting for combat to end", function()
    local c, ns = profileLogin()
    ns.SaveProfile("Ret")
    wow.slots[1] = { kind = "spell", id = 647 }
    ns.SaveProfile("Prot")
    wow.slots[1] = { kind = "spell", id = 1866 }
    wow.enterCombat()
    ns.ApplyProfile("Prot")
    ns.RenameProfile("Prot", "Tank")
    eq(ns.pendingProfile, "Tank")
    wow.leaveCombat()
    eq(c.active, "Tank")
    eq(slotId(1), 647)
end)
