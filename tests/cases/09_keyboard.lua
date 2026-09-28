-- Tests: the Keyboard tab.
---------------------------------------------------------------------------
function keyboardPage()
    slash("")
    click(tabNamed("Keyboard"))
    return pageFor("keyboard")
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

test("a key bound to a raid marker shows the marker's picture, uncropped", function()
    loginWithSetup(nil)
    wow.bindings.E = "RAIDTARGET8"
    wow.bindings.R = "ACTIONBUTTON1"
    local page = keyboardPage()
    local e = capFor(page, "E")
    eq(e.icon:IsShown(), true)
    assert(e.icon.texture:find("UI%-RaidTargetingIcon_8"), e.icon.texture)
    eq(e.name.text, "", "the picture instead of the words")
    eq(e.icon.texCoord[2], 1, "the whole picture")
    eq(capFor(page, "R").icon.texCoord[1], 0.08, "a spell icon keeps its border trimmed")
end)

test("the controller view lists only controller buttons it doesn't draw, and a keyboard view no controller buttons", function()
    loginWithSetup(nil)
    wow.bindings.PADLSTICKUP = "MOVEFORWARD"
    local page = keyboardPage()
    assert(page.others.text:find("NUMPAD1", 1, true))
    assert(not page.others.text:find("PADLSTICKUP", 1, true), "no controller buttons in a keyboard view")
    click(choice(page.layoutRow, "Controller"))
    assert(page.others.text:find("PADLSTICKUP", 1, true), page.others.text)
    assert(not page.others.text:find("NUMPAD1", 1, true), "no keyboard keys in the controller view")
end)

test("a long list of other keys stops after 24 with how many more", function()
    loginWithSetup(nil)
    for i = 1, 30 do wow.bindings["F" .. (20 + i)] = "ACTIONBUTTON1" end
    local page = keyboardPage()
    assert(page.others.text:find(", and 7 more", 1, true), page.others.text)
end)

test("the Controller layout is a diagram: a drawing, and each button's binding beside it with a line", function()
    loginWithSetup(nil)
    wow.bindings.PAD1 = "ACTIONBUTTON1"
    wow.bindings.PADDUP = "JUMP"
    local page = keyboardPage()
    click(choice(page.layoutRow, "Controller"))
    eq(page.board.drawing.texture, "Interface\\AddOns\\Keystance\\media\\controller.tga")
    local pad1 = capFor(page, "PAD1")
    eq(pad1.badge.texture, "Interface\\AddOns\\Keystance\\media\\circle.tga")
    eq(pad1.label.point[2], pad1.badge, "the symbol sits on the badge, off the icon")
    eq(pad1.callout, "right")
    eq(pad1.name.text, "Holy Strike", "the spell's name beside its icon")
    eq(pad1.name.point[1], "LEFT", "right-hand names read away from the drawing")
    eq(capFor(page, "PADDUP").callout, "left")
    eq(capFor(page, "PADDUP").name.point[1], "RIGHT")
    eq(capFor(page, "PADDUP").name.text, "JUMP", "a command with no action slot: its name (the fake names it by command)")
    assert(capFor(page, "PADLTRIGGER").name.text:find("Not bound", 1, true))
    -- Every drawn button has a line from its cap to its spot on the drawing, which ends there.
    for _, cap in ipairs(page.board.caps) do
        assert(cap.lines and #cap.lines >= 2, cap.key)
        local last = cap.lines[#cap.lines].to
        eq(cap.dot.point[4], last[3], cap.key .. " dot x")
        eq(cap.dot.point[5], last[4], cap.key .. " dot y")
    end
    eq(#capFor(page, "PAD3").lines, 3, "X bends around A")
    eq(capFor(page, "Q"), nil)
    loginWithSetup(nil)
    page = keyboardPage()
    eq(capFor(page, "Q").badge, nil, "keyboard keys keep their name in the corner")
    eq(capFor(page, "Q").callout, nil)
end)

test("the controller diagram fits the window without widening it", function()
    local _, ns = loginWithSetup(nil)
    local page = keyboardPage()
    click(choice(page.layoutRow, "Controller"))
    assert(page.board.width <= 720 - 32, page.board.width)
    assert(page.board.height <= 280, page.board.height)
    for _, side in ipairs({ "left", "right" }) do
        for _, info in ipairs(ns.LAYOUTS.pad[side]) do
            assert(info.at[1] >= 0 and info.at[1] <= ns.PAD_W and info.at[2] >= 0 and info.at[2] <= ns.PAD_H, info[1])
        end
    end
end)

test("Automatic shows the keyboard while the controller is merely switched on, not in use", function()
    loginWithSetup(nil)
    wow.pad = false
    local page = keyboardPage()
    eq(page.layoutKey ~= "pad", true)
end)

test("the controller drawing and round cap ship with the addon, in a format the game loads", function()
    for file, size in pairs({ ["media/controller.tga"] = { 512, 512 }, ["media/circle.tga"] = { 64, 64 } }) do
        local header = readFile(file):sub(1, 18)
        eq(header:byte(3), 2, file .. " uncompressed")
        eq(header:byte(13) + header:byte(14) * 256, size[1], file .. " width")
        eq(header:byte(15) + header:byte(16) * 256, size[2], file .. " height")
        eq(header:byte(17), 32, file .. " 32-bit")
    end
end)

test("a layer toggled on the controller doesn't carry over to the keyboard, nor back", function()
    loginWithSetup(nil)
    local page = keyboardPage()
    click(choice(page.layoutRow, "Controller"))
    click(page.toggles[1]) -- Shift, on the controller
    eq(page.toggles[1].highlightLocked, true)
    eq(capFor(page, "PAD1").fullKey, "SHIFT-PAD1")
    click(choice(page.layoutRow, "US"))
    eq(page.toggles[1].highlightLocked, false, "the keyboard's Shift is still off")
    eq(capFor(page, "Q").fullKey, "Q")
    click(page.toggles[3]) -- Alt, on the keyboard
    click(choice(page.layoutRow, "Controller"))
    eq(page.toggles[1].highlightLocked, true, "the controller kept its Shift")
    eq(page.toggles[3].highlightLocked, false, "and didn't get the keyboard's Alt")
    eq(capFor(page, "PAD1").fullKey, "SHIFT-PAD1")
end)
