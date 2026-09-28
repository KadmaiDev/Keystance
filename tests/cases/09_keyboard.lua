-- Tests: the Keyboard tab.
---------------------------------------------------------------------------
function keyboardPage()
    slash("")
    click(tabNamed("Keyboard"))
    return KeystanceFrame.pages[1]
end

function capFor(page, key)
    for _, cap in ipairs(page.board.caps) do
        if cap.key == key and not cap.mod then return cap end
    end
end

test("keys show the icon of the action they trigger, and other commands by name", function()
    loginWithSetup(nil)
    local page = keyboardPage()
    local one = capFor(page, "1")
    eq(one.slot, 1); eq(one.icon:IsShown(), true); eq(one.icon.texture, 134400)
    local w = capFor(page, "W")
    eq(w.icon:IsShown(), false); eq(w.name.text, "Move Forward")
    local q = capFor(page, "Q")
    eq(q.slot, 61)
    eq(capFor(page, "E").command, "", "unbound")
end)

test("the Shift, Ctrl and Alt toggles show that layer's keys", function()
    loginWithSetup(nil)
    local page = keyboardPage()
    click(page.toggles[1]) -- Shift
    eq(capFor(page, "1").fullKey, "SHIFT-1")
    eq(capFor(page, "1").slot, 3)
    eq(page.layerText.text, "Keys with Shift")
    click(page.toggles[2]) -- and Ctrl
    eq(capFor(page, "1").fullKey, "CTRL-SHIFT-1")
    eq(page.layerText.text, "Keys with Ctrl + Shift")
    click(page.toggles[1]); click(page.toggles[2])
    eq(page.layerText.text, "Keys on their own")
end)

test("holding a real modifier switches the view while it's held", function()
    loginWithSetup(nil)
    local page = keyboardPage()
    wow.mods.shift = true
    wow.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
    wow.runTimers()
    eq(capFor(page, "1").fullKey, "SHIFT-1")
    eq(page.layerText.text, "Keys with Shift (held)")
    wow.mods.shift = false
    wow.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 0)
    wow.runTimers()
    eq(capFor(page, "1").fullKey, "1")
end)

test("bound keys the keyboard doesn't draw are listed, so nothing is hidden", function()
    loginWithSetup(nil)
    local page = keyboardPage()
    assert(page.others.text:find("NUMPAD1", 1, true), page.others.text)
    assert(not page.others.text:find("MOVEFORWARD", 1, true), "drawn keys aren't repeated")
end)

test("the mouse's side buttons and wheel are drawn", function()
    loginWithSetup(nil)
    wow.bindings.BUTTON4 = "ACTIONBUTTON2"
    local page = keyboardPage()
    eq(capFor(page, "BUTTON4").slot, 2)
    assert(capFor(page, "MOUSEWHEELUP"))
end)

test("override bindings (EllesmereUI, ElvUI) are what the keys show", function()
    loginWithSetup(nil)
    local b = CreateFrame("Button", "EABButton13")
    b:SetAttribute("action", 13)
    wow.slots[13] = { kind = "spell", id = 647 }
    wow.overrides.E = "CLICK EABButton13:LeftButton"
    local page = keyboardPage()
    eq(capFor(page, "E").slot, 13)
end)

test("hovering a key shows its action's tooltip and the key", function()
    loginWithSetup(nil)
    local page = keyboardPage()
    local one = capFor(page, "1")
    one.scripts.OnEnter(one)
    eq(GameTooltip.action, 1)
    local w = capFor(page, "W")
    w.scripts.OnEnter(w)
    eq(GameTooltip.lines[1][1], "Move Forward")
end)

test("the keyboard follows the game's language, and can be chosen", function()
    wow.locale = "enGB"
    loginWithSetup(nil)
    local page = keyboardPage()
    wow.locale = nil
    eq(page.layoutKey, "iso")
    assert(capFor(page, "#"), "UK keyboard")
    eq(choice(page.layoutRow, "Automatic").chosen, true)
    click(choice(page.layoutRow, "US"))
    eq(KeystanceDB.settings.layout, "ansi")
    eq(choice(page.layoutRow, "US").chosen, true)
    eq(page.layoutKey, "ansi")
    eq(capFor(page, "#"), nil)
end)

test("a key change while the window is open shows at once", function()
    loginWithSetup(nil)
    local page = keyboardPage()
    wow.bindings.E = "ACTIONBUTTON2"
    wow.fire("UPDATE_BINDINGS")
    wow.runTimers()
    eq(capFor(page, "E").slot, 2)
end)

test("short key names for bar buttons", function()
    local ns = start(nil)
    eq(ns.ShortKey("SHIFT-1"), "s1")
    eq(ns.ShortKey("ALT-CTRL-SHIFT-Q"), "acsQ")
    eq(ns.ShortKey("BUTTON4"), "M4")
    eq(ns.ShortKey("SHIFT--"), "s-")
    eq(ns.ShortKey("-"), "-")
    local prefix, base = ns.SplitKey("CTRL--")
    eq(prefix, "CTRL-"); eq(base, "-")
end)

test("the Numpad option draws the navigation block and the numpad; their keys leave the list", function()
    loginWithSetup(nil)
    wow.bindings.INSERT = "PITCHUP"
    wow.bindings.UP = "ACTIONBUTTON2"
    local page = keyboardPage()
    assert(page.others.text:find("NUMPAD1", 1, true), "listed while not drawn")
    eq(capFor(page, "NUMPAD1"), nil)
    click(page.numpad)
    eq(KeystanceDB.settings.numpad, true, "remembered")
    eq(KeystanceFrame.width, 830, "the window widens; the keys keep their size")
    eq(capFor(page, "NUMPAD1").width, 31)
    click(tabNamed("Bars"))
    eq(KeystanceFrame.width, 720, "other tabs keep the normal width")
    click(tabNamed("Keyboard"))
    eq(KeystanceFrame.width, 830)
    eq(capFor(page, "NUMPAD1").slot, 2, "numpad 1 casts Holy Light")
    eq(capFor(page, "UP").slot, 2)
    eq(capFor(page, "INSERT").name.text, "PITCHUP")
    assert(capFor(page, "BUTTON4"), "the mouse is still drawn")
    assert(capFor(page, "Q"), "and the keyboard")
    assert(not page.others.text:find("NUMPAD1", 1, true), page.others.text)
    click(page.numpad)
    eq(capFor(page, "NUMPAD1"), nil)
    eq(KeystanceDB.settings.numpad, nil)
    eq(KeystanceFrame.width, 720, "back to normal")
end)

test("numpad keys are named N1, N2... on bar buttons, so they don't look like the number row", function()
    local ns = start(nil)
    eq(ns.ShortKey("NUMPAD1"), "N1")
    eq(ns.ShortKey("SHIFT-NUMPADPLUS"), "sN+")
end)

test("the Controller layout draws a gamepad's buttons with what they cast", function()
    loginWithSetup(nil)
    wow.bindings.PAD1 = "ACTIONBUTTON1"
    wow.bindings.PADLSHOULDER = "ACTIONBUTTON2"
    local page = keyboardPage()
    click(choice(page.layoutRow, "Controller"))
    eq(page.layoutKey, "pad")
    eq(capFor(page, "PAD1").slot, 1)
    eq(capFor(page, "PADLSHOULDER").slot, 2)
    eq(capFor(page, "Q"), nil, "no keyboard")
    eq(page.numpad:IsShown(), false, "no numpad option for a controller")
end)

test("a controller button set to act as Shift is drawn as a modifier, and names the Shift layer", function()
    loginWithSetup(nil)
    wow.cvars.GamePadEmulateShift = "PADLTRIGGER"
    wow.bindings["SHIFT-PAD1"] = "ACTIONBUTTON2"
    local page = keyboardPage()
    click(choice(page.layoutRow, "Controller"))
    local lt = capFor(page, "PADLTRIGGER")
    eq(lt.name.text, "Shift")
    eq(lt.fullKey, nil, "a modifier, not something to bind")
    eq(page.toggles[1].text, "Shift PADLTRIGGER")
    click(page.toggles[1])
    eq(capFor(page, "PAD1").fullKey, "SHIFT-PAD1")
    eq(capFor(page, "PAD1").slot, 2)
end)

test("Automatic shows the controller while one is in use", function()
    loginWithSetup(nil)
    wow.pad = true
    local page = keyboardPage()
    eq(page.layoutKey, "pad")
end)
