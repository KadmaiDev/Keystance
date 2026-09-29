-- Tests: dropping spells, macros and items on keys (Keyboard tab) and slots (Bars tab).
---------------------------------------------------------------------------
-- Vespera with Blizzard's main bar showing, so there are free slots on screen.
function dropLogin(shared)
    local c, ns = profileLogin(shared)
    CreateFrame("Frame", "MainActionBar")
    for i = 1, 12 do CreateFrame("Button", "ActionButton" .. i).action = i end
    return c, ns
end

function holding(id) wow.cursor = { "spell", 1, "spell", id } end

test("dropped on a key that casts a slot, the spell goes in that slot and the old one onto the cursor", function()
    local c, ns = dropLogin()
    local page = keyboardPage()
    holding(19834)
    local one = capFor(page, "1")
    one.scripts.OnReceiveDrag(one)
    eq(wow.slots[1].id, 19834)
    eq(wow.cursor[4], 1866, "Holy Strike, as the real bars do")
    eq(ns.UndoLabel(), "placing Blessing of Might")
end)

test("dropped on an unbound key, it goes in the first empty slot on screen and the key is bound to it", function()
    local c, ns = dropLogin()
    local page = keyboardPage()
    holding(19834)
    local e = capFor(page, "E")
    click(e)
    eq(wow.slots[4].id, 19834, "slot 4: the main bar's first empty button")
    eq(GetBindingAction("E"), "ACTIONBUTTON4")
    eq(wow.cursor, nil)
    assert(printed():find("Blessing of Might went on Main bar, button 4, with the key E. Move it on the Bars tab", 1, true), printed())
    ns.Undo()
    eq(wow.slots[4], nil); eq(GetBindingAction("E"), "")
end)

test("a key used for something else asks first, and cancelling keeps the spell on the cursor", function()
    dropLogin()
    local page = keyboardPage()
    holding(19834)
    click(capFor(page, "W"))
    eq(wow.popup.which, "KEYSTANCE_BIND_KEY")
    assert(wow.popup.text:find("W is Move Forward", 1, true), wow.popup.text)
    eq(wow.cursor[4], 19834, "still held while asking")
    wow.popup = nil -- Cancel: the pop-up just closes
    eq(GetBindingAction("W"), "MOVEFORWARD")
    eq(wow.cursor[4], 19834, "nothing lost")
    click(capFor(page, "W"))
    StaticPopupDialogs.KEYSTANCE_BIND_KEY.OnAccept(nil, wow.popup.data)
    eq(GetBindingAction("W"), "ACTIONBUTTON4")
end)

test("with shared keybinds, binding a key asks and gives the character its own keybinds first", function()
    dropLogin(true)
    local page = keyboardPage()
    holding(19834)
    click(capFor(page, "E"))
    eq(wow.popup.which, "KEYSTANCE_BIND_KEY")
    StaticPopupDialogs.KEYSTANCE_BIND_KEY.OnAccept(nil, wow.popup.data)
    eq(GetCurrentBindingSet(), 2)
    eq(GetBindingAction("E"), "ACTIONBUTTON4")
end)

test("with no empty slot on screen nothing changes, and the player is told", function()
    dropLogin()
    for i = 1, 12 do wow.slots[i] = wow.slots[i] or { kind = "spell", id = 647 } end
    local page = keyboardPage()
    holding(19834)
    click(capFor(page, "E"))
    eq(GetBindingAction("E"), "")
    eq(wow.cursor[4], 19834)
    assert(printed():find("No empty slot on your bars", 1, true))
end)

test("dropped on a slot in the Bars tab, it goes there", function()
    local c, ns = dropLogin()
    local page = barsPage()
    holding(19834)
    local slot4 = page.rows[1].slots[4]
    slot4.scripts.OnReceiveDrag(slot4)
    eq(wow.slots[4].id, 19834)
    eq(wow.cursor, nil)
end)

test("in combat nothing is dropped, and the spell stays on the cursor", function()
    dropLogin()
    local page = keyboardPage()
    holding(19834)
    wow.enterCombat()
    click(capFor(page, "E"))
    local one = capFor(page, "1")
    one.scripts.OnReceiveDrag(one)
    click(tabNamed("Bars"))
    local bars = pageFor("bars")
    local slot4 = bars.rows[1].slots[4]
    slot4.scripts.OnReceiveDrag(slot4)
    eq(#wow.blocked, 0)
    eq(wow.slots[1].id, 1866)
    eq(wow.slots[4], nil)
    eq(wow.cursor[4], 19834)
    wow.leaveCombat()
end)

test("macros and items can be dropped on keys too", function()
    dropLogin()
    local page = keyboardPage()
    wow.cursor = { "macro", 121 }
    click(capFor(page, "E"))
    eq(wow.slots[4].macro, 121)
    wow.cursor = { "item", 6948 }
    click(capFor(page, "R"))
    eq(wow.slots[5].id, 6948)
    eq(GetBindingAction("R"), "ACTIONBUTTON5")
end)

---------------------------------------------------------------------------
-- Picking up from the keyboard and bars, moving, and removing
test("dragging a key picks up its action, as dragging off a real bar does", function()
    dropLogin()
    local page = keyboardPage()
    local one = capFor(page, "1")
    one.scripts.OnDragStart(one)
    eq(wow.cursor[4], 1866)
    eq(wow.slots[1], nil)
end)

test("moved to a key with no slot, the action stays in its slot and the key binding moves", function()
    local c, ns = dropLogin()
    local page = keyboardPage()
    local one = capFor(page, "1")
    one.scripts.OnDragStart(one)
    click(capFor(page, "E"))
    eq(wow.slots[1].id, 1866, "back in its slot")
    eq(GetBindingAction("E"), "ACTIONBUTTON1")
    eq(GetBindingAction("1"), "", "the old key is free")
    eq(wow.cursor, nil)
    assert(printed():find("Holy Strike moved to E.", 1, true), printed())
    eq(ns.UndoLabel(), "moving Holy Strike to E")
    ns.Undo()
    eq(GetBindingAction("1"), "ACTIONBUTTON1"); eq(GetBindingAction("E"), "")
end)

test("moved onto a key with a slot, it lands there and that slot's action comes onto the cursor", function()
    local c, ns = dropLogin()
    local page = keyboardPage()
    local one = capFor(page, "1")
    one.scripts.OnDragStart(one)
    local two = capFor(page, "2")
    two.scripts.OnReceiveDrag(two)
    eq(wow.slots[2].id, 1866)
    eq(wow.cursor[4], 647, "Holy Light, to drop back on 1 and complete the swap")
    eq(ns.UndoLabel(), "moving Holy Strike")
    ClearCursor() -- Undo, like applying a profile, waits for the cursor to be empty
    ns.Undo()
    eq(wow.slots[1].id, 1866); eq(wow.slots[2].id, 647)
end)

test("something picked up here and dropped elsewhere is forgotten", function()
    dropLogin()
    local page = keyboardPage()
    local one = capFor(page, "1")
    one.scripts.OnDragStart(one)
    ClearCursor() -- dropped on a real bar, or thrown away
    wow.fire("CURSOR_CHANGED", true, 0, 1, 0)
    holding(19834)
    click(capFor(page, "E"))
    eq(wow.slots[1].id, 19834, "a new drop into the first empty slot on screen, not a move")
    eq(GetBindingAction("E"), "ACTIONBUTTON1")
    eq(GetBindingAction("1"), "ACTIONBUTTON1", "the old key keeps its binding: nothing was moved")
end)

test("right-click a key: remove its action from the bar, or unbind it (after asking)", function()
    local c, ns = dropLogin()
    local page = keyboardPage()
    click(capFor(page, "1"), "RightButton")
    eq(wow.popup.which, "KEYSTANCE_REMOVE_BOTH")
    eq(wow.slots[1].id, 1866, "nothing until chosen")
    StaticPopupDialogs.KEYSTANCE_REMOVE_BOTH.OnAccept(nil, wow.popup.data)
    eq(wow.slots[1], nil)
    eq(GetBindingAction("1"), "ACTIONBUTTON1", "the key keeps its binding")
    eq(ns.UndoLabel(), "removing Holy Strike")
    click(capFor(page, "2"), "RightButton")
    StaticPopupDialogs.KEYSTANCE_REMOVE_BOTH.OnAlt(nil, wow.popup.data)
    eq(GetBindingAction("2"), "")
    eq(wow.slots[2].id, 647, "the spell stays on its bar")
    click(capFor(page, "W"), "RightButton")
    eq(wow.popup.which, "KEYSTANCE_REMOVE_KEY", "Move Forward: only unbinding")
    wow.popup = nil
    click(capFor(page, "E"), "RightButton")
    eq(wow.popup, nil, "an empty key: nothing to remove")
end)

test("the Bars tab: drag a slot to pick it up, right-click to remove", function()
    dropLogin()
    local page = barsPage()
    local s1 = page.rows[1].slots[1]
    s1.scripts.OnDragStart(s1)
    eq(wow.cursor[4], 1866)
    PlaceAction(1)
    click(page.rows[1].slots[2], "RightButton")
    eq(wow.popup.which, "KEYSTANCE_REMOVE_SLOT")
    StaticPopupDialogs.KEYSTANCE_REMOVE_SLOT.OnAccept(nil, wow.popup.data)
    eq(wow.slots[2], nil)
end)

test("in combat nothing is picked up or removed", function()
    dropLogin()
    local page = keyboardPage()
    wow.enterCombat()
    local one = capFor(page, "1")
    one.scripts.OnDragStart(one)
    click(one, "RightButton")
    eq(wow.cursor, nil)
    eq(wow.popup, nil)
    eq(#wow.blocked, 0)
    eq(wow.slots[1].id, 1866)
    wow.leaveCombat()
end)

test("markers and profile switches say they go on keys: in the panel, on the held icon, and if clicked on a bar", function()
    local c, ns = profileLogin()
    ns.ToggleSpellPanel()
    local panel = KeystanceSpellPanel
    click(choice(panel.kinds, "Spells"))
    eq(panel.keysOnly:IsShown(), false)
    click(choice(panel.kinds, "Commands"))
    eq(panel.keysOnly:IsShown(), true)
    eq(panel.filters:IsShown(), false)
    click(rowNamed("Skull"))
    eq(KeystanceDragIcon.caption.text, "Click a key")
    -- Clicked on one of the game's action buttons (or a Bars tab slot): told once.
    wow.mouseFoci = { { action = 5 } }
    wow.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    assert(printed():find("Skull goes on a key, not on a bar", 1, true), printed())
    -- EllesmereUI's buttons (an "action" attribute) and ElvUI's (_state_action) too.
    for _, button in ipairs({ { GetAttribute = function(_, k) return k == "action" and 7 or nil end },
        { _state_action = 9 } }) do
        ns.CancelBinding()
        click(rowNamed("Skull"))
        wow.printed = {}
        wow.mouseFoci = { button }
        wow.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
        assert(printed():find("not on a bar", 1, true), "an addon's bar button")
    end
    wow.printed = {}
    wow.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    eq(printed(), "", "once per hold")
    eq(ns.HeldBinding().label, "Skull", "still held")
    -- A click on a key or anywhere else says nothing.
    ns.CancelBinding()
    click(rowNamed("Skull"))
    wow.mouseFoci = { { isKeyCap = true } }
    wow.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    eq(printed(), "")
    wow.mouseFoci = {}
    ns.CancelBinding()
end)

test("two remove questions open at once don't cross: each acts on its own key", function()
    local c, ns = dropLogin()
    local page = keyboardPage()
    click(capFor(page, "1"), "RightButton")
    local first = wow.popup.data
    click(capFor(page, "W"), "RightButton") -- a second question before answering the first
    StaticPopupDialogs.KEYSTANCE_REMOVE_BOTH.OnAlt(nil, first) -- "Unbind key" on the first
    eq(GetBindingAction("1"), "", "key 1 unbound")
    eq(GetBindingAction("W"), "MOVEFORWARD", "not W")
end)

test("a swap between two slots undoes right back to how it started", function()
    local c, ns = dropLogin()
    ns.PickupFromSlot(1) -- Holy Strike
    ns.DropOnSlot(2) -- Holy Light comes onto the cursor
    ns.DropOnSlot(1)
    eq(slotId(1), 647); eq(slotId(2), 1866)
    ns.Undo()
    eq(slotId(1), 1866, "as it started")
    eq(slotId(2), 647)
end)

test("an action picked up here and thrown away can be put back with Undo", function()
    local c, ns = dropLogin()
    ns.PickupFromSlot(1)
    ClearCursor()
    wow.fire("CURSOR_CHANGED")
    eq(ns.UndoLabel(), "removing Holy Strike")
    ns.Undo()
    eq(slotId(1), 1866)
end)

test("a key that triggers a slot is a key, not a bar button, for the keys-only hint", function()
    local c, ns = dropLogin()
    ns.StartBinding("RAIDTARGET8", "Skull", "icon")
    wow.mouseFoci = { { isKeyCap = true, slot = 1 } }
    wow.printed = {}
    wow.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    eq(printed(), "", "no 'not on a bar' hint on a key")
    wow.mouseFoci = {}
    ns.CancelBinding()
end)

test("the right-click that drops a held marker over a Bars slot doesn't also ask to remove it", function()
    local c, ns = dropLogin()
    local page = barsPage()
    ns.StartBinding("RAIDTARGET8", "Skull", "icon")
    wow.fire("GLOBAL_MOUSE_DOWN", "RightButton")
    wow.popup = nil
    click(page.rows[1].slots[1], "RightButton")
    eq(wow.popup, nil)
end)

test("keybind mode: a controller button set to act as Shift is held, not bound", function()
    local c, ns = dropLogin()
    local page = barsPage()
    click(page.bindButton)
    wow.cvars.GamePadEmulateShift = "PADLTRIGGER"
    local b = page.rows[1].slots[4]
    b.scripts.OnEnter(b)
    page.catcher.scripts.OnGamePadButtonDown(page.catcher, "PADLTRIGGER")
    eq(GetBindingAction("PADLTRIGGER"), "")
    page.catcher.scripts.OnGamePadButtonDown(page.catcher, "PAD1")
    eq(GetBindingAction("PAD1"), "ACTIONBUTTON4")
end)

test("keybind mode doesn't start on a tab closed while its question was open", function()
    local c, ns = dropLogin(true)
    local page = barsPage()
    click(page.bindButton)
    eq(wow.popup.which, "KEYSTANCE_BIND_MODE")
    slash("") -- the window closes
    StaticPopupDialogs.KEYSTANCE_BIND_MODE.OnAccept(nil, wow.popup.data)
    eq(page.bindMode, nil)
    eq(page.catcher:IsShown(), false)
end)

test("the combat note shows as combat starts (before the game's lockdown has begun)", function()
    local c, ns = dropLogin()
    slash("")
    wow.fire("PLAYER_REGEN_DISABLED") -- InCombatLockdown is still false at this moment
    eq(KeystanceFrame.combat:IsShown(), true)
    wow.fire("PLAYER_REGEN_ENABLED")
    eq(KeystanceFrame.combat:IsShown(), false)
end)
