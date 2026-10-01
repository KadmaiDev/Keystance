-- Tests: moving the hand one key right or left. Every keybind in the left-hand block moves
-- with the movement keys, in every modifier layer; the column pushed off the edge wraps
-- round to the freed left edge; profiles' saved keys move too; Undo puts it all back.

-- The paladin on WASD with a few more keys bound, on her own keybinds.
local function shiftLogin()
    local c, ns = loginWithSetup(nil)
    wow.bindings.A, wow.bindings.S, wow.bindings.D = "STRAFELEFT", "MOVEBACKWARD", "STRAFERIGHT"
    wow.bindings.TAB = "TARGETNEARESTENEMY"
    wow.bindings.Y = "TOGGLEAUTORUN"           -- the edge: wraps round to Tab
    wow.bindings["CTRL-E"] = "ACTIONBUTTON5"
    wow.bindings.M = "TOGGLEWORLDMAP"          -- the right side: stays
    wow.bindings.F1 = "TARGETSELF"             -- the function row: stays
    wow.bindingSet = 2
    wow.fire("UPDATE_BINDINGS")
    return c, ns
end

-- The shift question's Move button.
local function accept()
    local def = StaticPopupDialogs[wow.popup.which]
    def.OnAccept(nil, wow.popup.data)
end

test("the map moves each left-hand key one to the right, the edge column wrapping to the left", function()
    local c, ns = shiftLogin()
    local to = ns.HandShiftMap("ansi", 1)
    eq(to.W, "E"); eq(to.A, "S"); eq(to.S, "D"); eq(to.D, "F")
    eq(to.Q, "W"); eq(to.TAB, "Q"); eq(to.CAPSLOCK, "A"); eq(to.Z, "X"); eq(to["`"], "1")
    eq(to.Y, "TAB", "the edge wraps round"); eq(to.H, "CAPSLOCK"); eq(to.N, "Z"); eq(to["7"], "`")
    eq(to.U, nil, "beyond the edge: untouched"); eq(to.M, nil); eq(to.F1, nil); eq(to.SPACE, nil)
    -- One key left from E S D F is its exact opposite.
    local back = ns.HandShiftMap("ansi", -1, "F")
    for from, dest in pairs(to) do eq(back[dest], from, dest) end
end)

test("moving right puts movement on E S D F and every bind with it, in every layer", function()
    local c, ns = shiftLogin()
    ns.AskShiftHand(1)
    assert(wow.popup.text:find("E S D F", 1, true), wow.popup.text)
    accept()
    eq(GetBindingAction("E"), "MOVEFORWARD"); eq(GetBindingAction("S"), "STRAFELEFT")
    eq(GetBindingAction("D"), "MOVEBACKWARD"); eq(GetBindingAction("F"), "STRAFERIGHT")
    eq(GetBindingAction("W"), "MULTIACTIONBAR1BUTTON1", "what was on Q")
    eq(GetBindingAction("Q"), "TARGETNEARESTENEMY", "what was on Tab")
    eq(GetBindingAction("TAB"), "TOGGLEAUTORUN", "Y wrapped round")
    eq(GetBindingAction("2"), "ACTIONBUTTON1"); eq(GetBindingAction("3"), "ACTIONBUTTON2")
    eq(GetBindingAction("SHIFT-2"), "ACTIONBUTTON3", "the Shift layer too")
    eq(GetBindingAction("CTRL-R"), "ACTIONBUTTON5", "and Ctrl")
    eq(GetBindingAction("1"), "", "freed")
    eq(GetBindingAction("A"), "", "freed")
    eq(GetBindingAction("M"), "TOGGLEWORLDMAP", "the right side stays")
    eq(GetBindingAction("F1"), "TARGETSELF")
    eq(GetBindingAction("NUMPAD1"), "ACTIONBUTTON2")
    eq(ns.ReachMap("ansi").keys.forward, "E", "the heat map follows")
end)

test("profiles' saved keys move too, and the original setup doesn't", function()
    local c, ns = shiftLogin()
    ns.SaveProfile("Ret")
    eq(c.profiles.Ret.binds.ACTIONBUTTON1[1], "1")
    local snapshotKey = c.snapshot.binds.ACTIONBUTTON1[1]
    ns.AskShiftHand(1)
    accept()
    eq(c.profiles.Ret.binds.ACTIONBUTTON1[1], "2")
    eq(c.profiles.Ret.binds.ACTIONBUTTON3[1], "SHIFT-2")
    eq(c.snapshot.binds.ACTIONBUTTON1[1], snapshotKey, "Restore still goes all the way back")
    -- Applying the profile afterwards keeps the new place.
    ns.ApplyProfile("Ret")
    eq(GetBindingAction("2"), "ACTIONBUTTON1")
end)

test("Undo puts every key and every profile back; a second Undo moves them again", function()
    local c, ns = shiftLogin()
    ns.SaveProfile("Ret")
    local before = {}
    for k, v in pairs(wow.bindings) do before[k] = v end
    ns.AskShiftHand(1)
    accept()
    ns.Undo()
    for k, v in pairs(before) do eq(GetBindingAction(k), v, k) end
    eq(GetBindingAction("E"), "", "E free again")
    eq(c.profiles.Ret.binds.ACTIONBUTTON1[1], "1")
    ns.Undo()
    eq(GetBindingAction("E"), "MOVEFORWARD")
    eq(c.profiles.Ret.binds.ACTIONBUTTON1[1], "2")
end)

test("one key left from E S D F is the exact way back", function()
    local c, ns = shiftLogin()
    local before = {}
    for k, v in pairs(wow.bindings) do before[k] = v end
    ns.AskShiftHand(1)
    accept()
    ns.AskShiftHand(-1)
    assert(wow.popup.text:find("W A S D", 1, true), wow.popup.text)
    accept()
    for k, v in pairs(before) do eq(GetBindingAction(k), v, k) end
    local count = 0
    for _ in pairs(wow.bindings) do count = count + 1 end
    local was = 0
    for _ in pairs(before) do was = was + 1 end
    eq(count, was, "nothing added or lost")
end)

test("no further than the edge: not left of W A S D, not when movement isn't on the keyboard", function()
    local c, ns = shiftLogin()
    eq(ns.CanShiftHand(-1), false)
    eq(ns.CanShiftHand(1), true)
    wow.bindings.W, wow.bindings.UP = nil, "MOVEFORWARD"
    wow.fire("UPDATE_BINDINGS")
    eq(ns.CanShiftHand(1), false)
end)

test("on shared keybinds it says so, and gives the character its own before moving anything", function()
    local c, ns = shiftLogin()
    wow.bindingSet = 1
    ns.AskShiftHand(1)
    assert(wow.popup.text:find("shared", 1, true), wow.popup.text)
    eq(GetBindingAction("E"), "", "nothing yet")
    accept()
    eq(wow.bindingSet, 2, "own keybinds first")
    eq(GetBindingAction("E"), "MOVEFORWARD")
end)

test("in combat the move waits until combat ends, with nothing blocked", function()
    local c, ns = shiftLogin()
    ns.AskShiftHand(1)
    wow.enterCombat()
    accept()
    eq(GetBindingAction("E"), "")
    eq(#wow.blocked, 0)
    wow.leaveCombat()
    eq(GetBindingAction("E"), "MOVEFORWARD")
end)

test("the heat map's buttons move the hand, and say where it can't go", function()
    local c, ns = shiftLogin()
    KeystanceDB.settings.heatmap = true
    local page = keyboardPage()
    eq(page.handRight:IsShown(), true)
    eq(page.handLeft:IsEnabled(), false, "not left of W A S D")
    click(page.handRight)
    eq(wow.popup.which, "KEYSTANCE_SHIFT_HAND")
    accept()
    wow.runTimers()
    eq(page.handLeft:IsEnabled(), true)
    KeystanceDB.settings.heatmap = nil
    ns.RefreshWindow()
    eq(page.handRight:IsShown(), false, "with the heat map only")
end)
