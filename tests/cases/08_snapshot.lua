-- Tests: reading action slots, which slot a command triggers, and the "Before Keystance"
-- snapshot.
---------------------------------------------------------------------------
-- A paladin's setup: spells, a macro, an item, a flyout and bound keys.
function paladinSetup()
    wow.spellbook = { { name = "Retribution", spells = { { 19834, "Blessing of Might", "Rank 2" }, { 1866, "Holy Strike", "Rank 3" } } },
        { name = "Holy", spells = { { 647, "Holy Light", "Rank 3" } } } }
    wow.slots[1] = { kind = "spell", id = 1866 }
    wow.slots[2] = { kind = "spell", id = 647 }
    wow.slots[3] = { kind = "macro", macro = 121 }
    wow.slots[61] = { kind = "item", id = 6948 }
    wow.slots[62] = { kind = "flyout", id = 264 }
    wow.slots[197] = { kind = "spell", id = 19834 } -- slots above 180 exist on Forever
    wow.macros[121] = { name = "Attack", body = "#showtooltip Attack\n/startattack", icon = 132349 }
    wow.macroSpell[121] = 6603
    wow.bindings = { ["1"] = "ACTIONBUTTON1", ["2"] = "ACTIONBUTTON2", ["SHIFT-1"] = "ACTIONBUTTON3",
        Q = "MULTIACTIONBAR1BUTTON1", W = "MOVEFORWARD", NUMPAD1 = "ACTIONBUTTON2" }
end

-- Logs in and lets the snapshot's first try run.
function loginWithSetup(saved)
    local ns = wow.load(FILES)
    paladinSetup()
    wow.login(saved)
    wow.fire("PLAYER_ENTERING_WORLD", true, false)
    wow.runTimers()
    return KeystanceDB.chars["Vespera Ashward"], ns
end

test("a slot's action is read as data: spells with name and rank, macros by name and body", function()
    local ns = start(nil)
    paladinSetup()
    local s = ns.DescribeSlot(1)
    eq(s.t, "spell"); eq(s.id, 1866); eq(s.name, "Holy Strike"); eq(s.rank, "Rank 3")
    local m = ns.DescribeSlot(3)
    eq(m.t, "macro"); eq(m.name, "Attack"); eq(m.body, "#showtooltip Attack\n/startattack"); eq(m.perChar, true)
    eq(ns.DescribeSlot(61).t, "item"); eq(ns.DescribeSlot(61).id, 6948)
    eq(ns.DescribeSlot(62).t, "flyout"); eq(ns.DescribeSlot(62).id, 264)
    eq(ns.DescribeSlot(4), nil, "empty")
end)

test("binding commands map to the slots measured on Forever", function()
    local ns = start(nil)
    eq(ns.CommandSlot("ACTIONBUTTON5"), 5)
    eq(ns.CommandSlot("MULTIACTIONBAR1BUTTON1"), 61)
    eq(ns.CommandSlot("MULTIACTIONBAR2BUTTON1"), 49)
    eq(ns.CommandSlot("MULTIACTIONBAR3BUTTON1"), 25)
    eq(ns.CommandSlot("MULTIACTIONBAR4BUTTON1"), 37)
    eq(ns.CommandSlot("MULTIACTIONBAR5BUTTON12"), 156)
    eq(ns.CommandSlot("MULTIACTIONBAR7BUTTON1"), 169)
    eq(ns.CommandSlot("EUI_BAR9_BUTTON1"), 13)
    eq(ns.CommandSlot("EUI_BAR10_BUTTON12"), 120)
    eq(ns.CommandSlot("ELVUIBAR7BUTTON2"), 74)
    eq(ns.CommandSlot("MOVEFORWARD"), nil)
    eq(ns.CommandSlot(""), nil)
end)

test("the main bar follows the bar page and stance paging", function()
    local ns = start(nil)
    wow.page = 2
    eq(ns.CommandSlot("ACTIONBUTTON1"), 13)
    wow.page, wow.bonus = 1, 1 -- e.g. a warrior's first stance
    eq(ns.CommandSlot("ACTIONBUTTON1"), 73)
end)

test("buttons of a bar addon tell their own slot (EllesmereUI's paging, ElvUI's pages, click bindings)", function()
    local ns = start(nil)
    local eab = CreateFrame("Button", "EABButton1")
    eab:SetAttribute("action", 85)
    eq(ns.CommandSlot("ACTIONBUTTON1"), 85)
    local elv = CreateFrame("Button", "ElvUI_Bar2Button3")
    elv._state_action = 99
    eq(ns.CommandSlot("ELVUIBAR2BUTTON3"), 99)
    eq(ns.CommandSlot("CLICK ElvUI_Bar2Button3:LeftButton"), 99)
end)

---------------------------------------------------------------------------
-- The snapshot
test("the first login saves every slot, every key and the binding set", function()
    local c = loginWithSetup(nil)
    local snap = c.snapshot
    assert(snap, "taken")
    eq(snap.nSlots, 6); eq(snap.slots[1].name, "Holy Strike"); eq(snap.slots[3].body, "#showtooltip Attack\n/startattack")
    eq(snap.slots[197].id, 19834, "slots above 180 too")
    eq(snap.set, 1)
    eq(snap.nBinds, 5)
    eq(table.concat(snap.binds.ACTIONBUTTON2, ","), "2,NUMPAD1")
    eq(snap.binds.MOVEFORWARD[1], "W")
    assert(type(snap.at) == "number")
end)

test("the snapshot changes nothing and makes no protected call", function()
    loginWithSetup(nil)
    eq(#wow.blocked, 0)
    eq(wow.slots[1].id, 1866)
    eq(GetBindingAction("1"), "ACTIONBUTTON1")
    eq(wow.cursor, nil)
end)

test("the snapshot is never replaced: later logins and changes leave it as it was", function()
    local c = loginWithSetup(nil)
    local first = c.snapshot
    local saved = KeystanceDB
    local ns = wow.load(FILES)
    paladinSetup()
    wow.slots[1] = { kind = "spell", id = 647 }
    wow.login(saved)
    wow.fire("PLAYER_ENTERING_WORLD", false, true)
    wow.runTimers()
    eq(ns.TakeSnapshot(), true, "asked directly, it still keeps the first one")
    eq(KeystanceDB.chars["Vespera Ashward"].snapshot, first)
    eq(first.slots[1].name, "Holy Strike")
end)

test("before bars and keys have loaded it waits, then saves them once they arrive", function()
    start(nil)
    wow.fire("PLAYER_ENTERING_WORLD", true, false)
    wow.runTimers()
    local c = KeystanceDB.chars["Vespera Ashward"]
    eq(c.snapshot, nil, "an empty setup is never saved: restoring it would wipe the bars")
    paladinSetup()
    wow.runTimers()
    assert(c.snapshot, "taken on a later try")
    eq(c.snapshot.nSlots, 6)
end)

test("Settings says when the original setup was saved", function()
    loginWithSetup(nil)
    slash("")
    click(tabNamed("Settings"))
    local text = KeystanceFrame.pages[5].snapshot.text
    assert(text:find("(6 slots, 5 keys)", 1, true), text)
end)
