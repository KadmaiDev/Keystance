-- Tests: new spell ranks replace lower ranks on the bars.
---------------------------------------------------------------------------
-- Sabine the warlock: Demon Skin Rank 1 on two slots, a macro and Shadow Bolt elsewhere.
function warlockLogin()
    local ns = wow.load(FILES)
    wow.player = { name = "Sabine Blackthorn", class = "WARLOCK", level = 20 }
    wow.spellbook = { { name = "Demonology", spells = { { 687, "Demon Skin", "Rank 1" }, { 686, "Shadow Bolt", "Rank 1" } } } }
    wow.slots[60] = { kind = "spell", id = 687 }
    wow.slots[12] = { kind = "spell", id = 687 }
    wow.slots[1] = { kind = "spell", id = 686 }
    wow.bindings = { ["1"] = "ACTIONBUTTON1" }
    wow.bindingSet = 2
    wow.login(nil)
    return ns
end

-- Training a new rank at the trainer.
function learn(id, name, rank)
    table.insert(wow.spellbook[1].spells, { id, name, rank })
    wow.fire("LEARNED_SPELL_IN_SKILL_LINE", id, 1, false)
end

test("learning a new rank replaces the lower rank on every bar slot, a few seconds later", function()
    warlockLogin()
    learn(696, "Demon Skin", "Rank 2")
    eq(wow.slots[60].id, 687, "not at once: the game's own change comes first")
    wow.runTimers()
    eq(wow.slots[60].id, 696); eq(wow.slots[12].id, 696)
    eq(wow.slots[1].id, 686, "other spells untouched")
    assert(printed():find("Upgraded Demon Skin to Rank 2", 1, true), printed())
    eq(GetBindingAction("1"), "ACTIONBUTTON1", "keys untouched")
end)

test("the upgrade can be undone", function()
    local ns = warlockLogin()
    learn(696, "Demon Skin", "Rank 2")
    wow.runTimers()
    eq(ns.UndoLabel(), "the rank upgrade")
    ns.Undo()
    eq(wow.slots[60].id, 687)
end)

test("learned in combat, the upgrade waits for combat to end", function()
    warlockLogin()
    wow.enterCombat()
    learn(696, "Demon Skin", "Rank 2")
    wow.runTimers()
    eq(wow.slots[60].id, 687)
    eq(#wow.blocked, 0)
    wow.leaveCombat()
    eq(wow.slots[60].id, 696)
end)

test("if the game already upgraded the bar, nothing more happens", function()
    warlockLogin()
    learn(696, "Demon Skin", "Rank 2")
    wow.slots[60] = { kind = "spell", id = 696 }
    wow.slots[12] = { kind = "spell", id = 696 }
    wow.calls = {}
    wow.runTimers()
    eq(#wow.calls, 0)
end)

test("a brand new spell (no lower rank on the bars) changes nothing", function()
    warlockLogin()
    wow.calls = {}
    learn(1454, "Life Tap", "Rank 1")
    wow.runTimers()
    eq(#wow.calls, 0)
end)

test("/kst ranks turns it off, and back on", function()
    warlockLogin()
    slash("ranks")
    learn(696, "Demon Skin", "Rank 2")
    wow.runTimers()
    eq(wow.slots[60].id, 687)
    slash("ranks")
    assert(printed():find("New spell ranks replace lower ranks on your bars.", 1, true))
end)
