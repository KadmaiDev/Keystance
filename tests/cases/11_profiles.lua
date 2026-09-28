-- Tests: profiles, applying them, undo and restore (the first code that changes bars and keys).
---------------------------------------------------------------------------
-- Vespera with her flyout and hearthstone available, on character keybinds unless `shared`.
function profileLogin(shared)
    local c, ns = loginWithSetup(nil)
    table.insert(wow.spellbook[1].spells, { 264, "Blessings", flyout = true })
    wow.itemCount[6948] = 1
    if not shared then wow.bindingSet = 2 end
    wow.calls = {}
    return c, ns
end

function countCalls(name)
    local n = 0
    for _, c in ipairs(wow.calls) do if c == name then n = n + 1 end end
    return n
end

-- Rearranges the bars and keys, as a player would between saving and applying.
function shuffle()
    wow.slots[1] = { kind = "spell", id = 647 }
    wow.slots[2] = nil
    wow.slots[5] = { kind = "spell", id = 19834 }
    wow.bindings["1"] = "ACTIONBUTTON2"
    wow.bindings.E = "ACTIONBUTTON5"
    wow.bindings.Q = nil
end

function slotId(slot) return wow.slots[slot] and (wow.slots[slot].id or wow.slots[slot].macro) end

test("a profile saves slots 1-180 and only the keys of bar buttons", function()
    local c, ns = profileLogin()
    eq(ns.SaveProfile("Prot"), "Prot")
    local p = c.profiles.Prot
    eq(p.slots[1].id, 1866); eq(p.slots[3].name, "Attack"); eq(p.slots[62].t, "flyout")
    eq(p.slots[197], nil, "slots above 180 mirror the main bar and aren't managed")
    eq(p.binds.ACTIONBUTTON1[1], "1"); eq(p.binds.MULTIACTIONBAR1BUTTON1[1], "Q")
    eq(p.binds.MOVEFORWARD, nil, "movement and other keys are never part of a profile")
    eq(p.nSlots, 5)
end)

test("profile names: tidied, unique ignoring case, and not replaced without asking", function()
    local c, ns = profileLogin()
    eq(ns.SaveProfile("  Holy  "), "Holy")
    local ok, why = ns.SaveProfile("holy")
    eq(ok, nil); assert(why:find("already", 1, true))
    eq(select(2, ns.SaveProfile("   ")), "A profile needs a name.")
    eq(ns.SaveProfile("HOLY", true), "HOLY", "replaced when asked")
    eq(c.profiles.Holy, nil)
end)

test("applying a profile puts every slot and bar key back as saved", function()
    local c, ns = profileLogin()
    ns.SaveProfile("Ret")
    shuffle()
    ns.ApplyProfile("Ret")
    eq(slotId(1), 1866); eq(slotId(2), 647); eq(wow.slots[5], nil, "emptied, as in the profile")
    eq(GetBindingAction("1"), "ACTIONBUTTON1"); eq(GetBindingAction("Q"), "MULTIACTIONBAR1BUTTON1")
    eq(GetBindingAction("E"), "", "a bar key the profile doesn't have is unbound")
    eq(GetBindingAction("W"), "MOVEFORWARD", "other keys untouched")
    eq(c.active, "Ret")
    eq(countCalls("SaveBindings"), 1, "keybindings saved once")
    eq(wow.cursor, nil, "nothing left on the cursor")
end)

test("applying the same profile twice changes nothing the second time", function()
    local c, ns = profileLogin()
    ns.SaveProfile("Ret")
    shuffle()
    ns.ApplyProfile("Ret")
    wow.calls = {}
    ns.ApplyProfile("Ret")
    eq(#wow.calls, 0, table.concat(wow.calls, ","))
end)

test("a spell that can't be placed leaves its slot as it was, and is reported", function()
    local c, ns = profileLogin()
    ns.SaveProfile("Holy")
    c.profiles.Holy.slots[7] = { t = "spell", id = 26573, name = "Consecration" } -- not trained
    wow.slots[7] = { kind = "spell", id = 647 }
    ns.ApplyProfile("Holy")
    eq(slotId(7), 647, "not emptied")
    assert(printed():find("Consecration isn't known", 1, true), printed())
end)

test("a rank the character no longer has becomes the highest rank of that spell", function()
    local c, ns = profileLogin()
    ns.SaveProfile("Holy")
    c.profiles.Holy.slots[2] = { t = "spell", id = 639, name = "Holy Light", rank = "Rank 2" }
    wow.slots[2] = nil
    ns.ApplyProfile("Holy")
    eq(slotId(2), 647)
end)

test("macros are placed by name; a missing macro is reported and its slot left alone", function()
    local c, ns = profileLogin()
    ns.SaveProfile("Ret")
    wow.slots[3] = nil
    ns.ApplyProfile("Ret")
    eq(wow.slots[3].macro, 121)
    wow.macros[121] = nil
    wow.slots[3] = { kind = "spell", id = 647 }
    ns.ApplyProfile("Ret")
    eq(slotId(3), 647)
    assert(printed():find("macro 'Attack' not found", 1, true), printed())
end)

test("a key taken over from another command comes back with Undo, and Undo restores exactly", function()
    local c, ns = profileLogin()
    local before = ns.CurrentState()
    wow.bindings.W = "ACTIONBUTTON4"
    ns.SaveProfile("Odd")
    wow.bindings.W = "MOVEFORWARD"
    shuffle()
    local shuffled = ns.CurrentState()
    ns.ApplyProfile("Odd")
    eq(GetBindingAction("W"), "ACTIONBUTTON4", "the profile's key, even from another command")
    eq(ns.UndoLabel(), "applying Odd")
    ns.Undo()
    eq(GetBindingAction("W"), "MOVEFORWARD")
    for slot = 1, 180 do
        local a, b = shuffled.slots[slot], ns.DescribeSlot(slot)
        eq(a and (a.id or a.name), b and (b.id or b.name), "slot " .. slot)
    end
    for key, cmd in pairs(wow.bindings) do eq(cmd, (function()
        for command, keys in pairs(shuffled.binds) do
            for _, k in ipairs(keys) do if k == key then return command end end
        end
    end)(), key) end
    assert(before)
end)

test("in combat nothing is changed; the profile applies when combat ends", function()
    local c, ns = profileLogin()
    ns.SaveProfile("Ret")
    shuffle()
    wow.enterCombat()
    ns.ApplyProfile("Ret")
    eq(#wow.blocked, 0, "no protected call in combat")
    eq(slotId(1), 647, "not yet")
    assert(printed():find("Ret will apply when combat ends.", 1, true))
    wow.leaveCombat()
    eq(slotId(1), 1866)
end)

test("nothing happens while something is held on the cursor", function()
    local c, ns = profileLogin()
    ns.SaveProfile("Ret")
    shuffle()
    wow.cursor = { "item", 6948 }
    ns.ApplyProfile("Ret")
    eq(slotId(1), 647)
    eq(wow.cursor[2], 6948, "still holding it")
    assert(printed():find("put down what you're holding", 1, true), printed())
end)

test("slots above 180 are never touched", function()
    local c, ns = profileLogin()
    ns.SaveProfile("Ret")
    wow.slots[197] = { kind = "spell", id = 647 }
    ns.ApplyProfile("Ret")
    eq(slotId(197), 647)
end)

---------------------------------------------------------------------------
-- Shared (account-wide) keybinds: ask first (owner's decision)
test("with shared keybinds, a profile that changes keys asks first; nothing changes until answered", function()
    local c, ns = profileLogin(true)
    ns.SaveProfile("Ret")
    shuffle()
    ns.ApplyProfile("Ret")
    eq(wow.popup.which, "KEYSTANCE_SHARED_KEYS")
    eq(slotId(1), 647, "nothing yet")
    StaticPopupDialogs.KEYSTANCE_SHARED_KEYS.OnAccept(nil, wow.popup.data)
    eq(GetCurrentBindingSet(), 2, "own keybinds first")
    eq(slotId(1), 1866); eq(GetBindingAction("1"), "ACTIONBUTTON1")
end)

test("with shared keybinds, Bars only changes the bars and leaves every key alone", function()
    local c, ns = profileLogin(true)
    ns.SaveProfile("Ret")
    shuffle()
    ns.ApplyProfile("Ret")
    StaticPopupDialogs.KEYSTANCE_SHARED_KEYS.OnAlt(nil, wow.popup.data)
    eq(slotId(1), 1866)
    eq(GetBindingAction("1"), "ACTIONBUTTON2", "keys unchanged")
    eq(GetCurrentBindingSet(), 1)
    eq(countCalls("SaveBindings"), 0)
end)

test("with shared keybinds, a profile that changes no keys applies without asking", function()
    local c, ns = profileLogin(true)
    ns.SaveProfile("Ret")
    wow.slots[1] = { kind = "spell", id = 647 }
    ns.ApplyProfile("Ret")
    eq(wow.popup, nil)
    eq(slotId(1), 1866)
end)

test("giving a character its own keybinds keeps every key", function()
    local c, ns = profileLogin(true)
    local keys = ns.ReadBindings()
    slash("ownkeys")
    eq(GetCurrentBindingSet(), 2)
    for cmd, list in pairs(keys) do eq(table.concat(list, ","), table.concat(ns.ReadBindings()[cmd], ","), cmd) end
end)

---------------------------------------------------------------------------
-- Restore
test("Restore puts back the original bars and every key, after asking, and can be undone", function()
    local c, ns = profileLogin()
    shuffle()
    wow.bindings.W = "ACTIONBUTTON6"
    slash("restore")
    eq(wow.popup.which, "KEYSTANCE_RESTORE")
    eq(slotId(1), 647, "nothing until confirmed")
    StaticPopupDialogs.KEYSTANCE_RESTORE.OnAccept()
    eq(slotId(1), 1866); eq(slotId(2), 647); eq(wow.slots[5], nil)
    eq(GetBindingAction("1"), "ACTIONBUTTON1"); eq(GetBindingAction("Q"), "MULTIACTIONBAR1BUTTON1")
    eq(GetBindingAction("W"), "MOVEFORWARD", "every key, not only bar keys")
    ns.Undo()
    eq(slotId(1), 647, "undone")
    eq(GetBindingAction("W"), "ACTIONBUTTON6")
end)

---------------------------------------------------------------------------
-- Managing profiles
test("rename, duplicate and delete (after asking); the active profile follows a rename", function()
    local c, ns = profileLogin()
    ns.SaveProfile("Ret")
    ns.ApplyProfile("Ret")
    eq(ns.RenameProfile("ret", "Retribution"), "Retribution")
    eq(c.active, "Retribution")
    eq(ns.DuplicateProfile("Retribution", "Ret PvP"), "Ret PvP")
    assert(c.profiles["Ret PvP"].slots ~= c.profiles.Retribution.slots, "a real copy")
    ns.ConfirmDelete("Ret PvP")
    eq(c.profiles["Ret PvP"] ~= nil, true, "not until confirmed")
    StaticPopupDialogs.KEYSTANCE_DELETE.OnAccept(nil, wow.popup.data)
    eq(c.profiles["Ret PvP"], nil)
end)

test("slash commands: save, apply, profiles, undo", function()
    local c, ns = profileLogin()
    slash("save Holy")
    assert(printed():find("Saved your bars and keys as Holy.", 1, true))
    shuffle()
    slash("apply holy")
    eq(slotId(1), 1866)
    slash("profiles")
    assert(printed():find("Profiles: Holy", 1, true))
    slash("undo")
    eq(slotId(1), 647)
    slash("apply Nope")
    assert(printed():find("No profile called Nope", 1, true))
end)
