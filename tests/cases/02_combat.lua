-- Tests: the combat queue, and the fake client's rules for bars and keys (later phases rely
-- on them matching what the phase 0 probe measured).
---------------------------------------------------------------------------
-- Combat queue
test("out of combat, work runs at once", function()
    local ns = start(nil)
    local ran = 0
    eq(ns.OutOfCombat("apply", function() ran = ran + 1 end), true)
    eq(ran, 1)
    eq(ns.Waiting(), false)
end)

test("in combat, work waits and runs when combat ends, in the order asked", function()
    local ns = start(nil)
    local ran = {}
    wow.enterCombat()
    eq(ns.OutOfCombat("apply", function() ran[#ran + 1] = "apply" end), false)
    ns.OutOfCombat("ranks", function() ran[#ran + 1] = "ranks" end)
    eq(#ran, 0)
    eq(ns.Waiting("apply"), true)
    wow.leaveCombat()
    eq(table.concat(ran, ","), "apply,ranks")
    eq(ns.Waiting(), false)
end)

test("asking again in combat replaces the earlier request but keeps its place", function()
    local ns = start(nil)
    local ran = {}
    wow.enterCombat()
    ns.OutOfCombat("apply", function() ran[#ran + 1] = "Prot" end)
    ns.OutOfCombat("ranks", function() ran[#ran + 1] = "ranks" end)
    ns.OutOfCombat("apply", function() ran[#ran + 1] = "Ret" end)
    wow.leaveCombat()
    eq(table.concat(ran, ","), "Ret,ranks")
end)

test("work queued while the queue runs waits for the next end of combat if combat started again", function()
    local ns = start(nil)
    local ran = {}
    wow.enterCombat()
    ns.OutOfCombat("a", function()
        ran[#ran + 1] = "a"
        wow.combat = true -- a new fight starts before the rest runs
    end)
    ns.OutOfCombat("b", function() ran[#ran + 1] = "b" end)
    wow.leaveCombat()
    eq(table.concat(ran, ","), "a")
    eq(ns.Waiting("b"), true)
    wow.leaveCombat()
    eq(table.concat(ran, ","), "a,b")
end)

---------------------------------------------------------------------------
-- Nothing Keystance does in combat calls a protected function (players would see an error)
test("in combat, using every part of Keystance makes no protected call", function()
    start(nil)
    wow.enterCombat()
    for _, cmd in ipairs({ "", "help", "minimap", "minimap", "skin", "skin classic", "mem", "" }) do slash(cmd) end
    slash("")
    for _, tab in ipairs(KeystanceFrame.tabs) do tab.scripts.OnClick(tab) end
    for _, b in ipairs(KeystanceFrame.buttons) do
        if b.scripts.OnClick then b.scripts.OnClick(b) end
    end
    for _, item in ipairs(wow.menu and wow.menu.items or {}) do
        if item.setSelected then item.setSelected() elseif item.fn then item.fn() end
    end
    Keystance_OnAddonCompartmentClick("Keystance", "RightButton", UIParent)
    for _, item in ipairs(wow.menu.items) do
        if item.setSelected then item.setSelected() elseif item.fn then item.fn() end
    end
    wow.leaveCombat()
    eq(#wow.blocked, 0, table.concat(wow.blocked, ", "))
end)

---------------------------------------------------------------------------
-- The fake client's rules (measured with the phase 0 probe, 2026-09-28)
test("fake client: placing onto a filled slot puts the old action on the cursor", function()
    start(nil)
    wow.spellbook = { { name = "Holy", spells = { { 635, "Holy Light", "Rank 1" }, { 19750, "Flash of Light", "Rank 1" } } } }
    C_Spell.PickupSpell(635); PlaceAction(5)
    C_Spell.PickupSpell(19750); PlaceAction(5)
    eq(select(2, GetActionInfo(5)), 19750)
    local kind, _, _, id = GetCursorInfo()
    eq(kind, "spell"); eq(id, 635)
end)

test("fake client: in combat, placing and binding are blocked with an event and no change", function()
    start(nil)
    wow.spellbook = { { name = "Holy", spells = { { 635, "Holy Light", "Rank 1" } } } }
    local events = 0
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_ACTION_BLOCKED")
    f:SetScript("OnEvent", function() events = events + 1 end)
    wow.enterCombat()
    C_Spell.PickupSpell(635); PlaceAction(5); SetBinding("CTRL-SHIFT-F12", "ACTIONBUTTON12")
    eq(HasAction(5), false)
    eq(GetBindingAction("CTRL-SHIFT-F12"), "")
    eq(events, 3)
    eq(table.concat(wow.blocked, ","), "C_Spell.PickupSpell,PlaceAction,SetBinding")
end)

test("fake client: a macro slot reports the spell it shows; its name comes from GetActionText", function()
    start(nil)
    wow.macros[1] = { name = "Attack", body = "#showtooltip Attack\n/startattack" }
    wow.macroSpell[1] = 6603
    PickupMacro(1); PlaceAction(7)
    local kind, id = GetActionInfo(7)
    eq(kind, "macro"); eq(id, 6603)
    eq(GetActionText(7), "Attack")
end)

test("fake client: SaveBindings(2) switches to character keybinds and keeps every bind", function()
    start(nil)
    wow.bindings = { ["1"] = "ACTIONBUTTON1", Q = "MULTIACTIONBAR1BUTTON1" }
    SaveBindings(2)
    eq(GetCurrentBindingSet(), 2)
    eq(GetBindingAction("Q"), "MULTIACTIONBAR1BUTTON1")
end)
