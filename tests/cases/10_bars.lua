-- Tests: the Bars tab.
---------------------------------------------------------------------------
function barsPage()
    slash("")
    click(tabNamed("Bars"))
    return pageFor("bars")
end

-- Blizzard's bars: the main bar and the bottom-left bar showing, the rest hidden.
function blizzardBars()
    CreateFrame("Frame", "MainActionBar")
    CreateFrame("Frame", "MultiBarBottomLeft")
    local hidden = CreateFrame("Frame", "MultiBarRight")
    hidden:Hide()
    for i = 1, 12 do
        CreateFrame("Button", "ActionButton" .. i).action = i
        CreateFrame("Button", "MultiBarBottomLeftButton" .. i).action = 60 + i
    end
end

test("Blizzard's bars: each shown bar with its slots' icons and keys", function()
    loginWithSetup(nil)
    blizzardBars()
    local page = barsPage()
    eq(page.source.text, "Blizzard's action bars")
    eq(page.rows[1].label.text, "Main bar")
    eq(page.rows[2].label.text, "Bottom left")
    eq(page.rows[3], nil, "hidden bars aren't listed")
    local first = page.rows[1].slots[1]
    eq(first.slot, 1); eq(first.icon:IsShown(), true); eq(first.keyText.text, "1")
    eq(page.rows[1].slots[3].keyText.text, "s1")
    eq(page.rows[1].slots[4].icon:IsShown(), false, "empty slot")
    eq(page.rows[2].slots[1].slot, 61); eq(page.rows[2].slots[1].keyText.text, "Q")
    first.scripts.OnEnter(first)
    eq(GameTooltip.action, 1)
end)

test("EllesmereUI's bars: its slot layout and binding commands", function()
    loginWithSetup(nil)
    CreateFrame("Frame", "EABBar_MainBar")
    CreateFrame("Frame", "EABBar_Bar2")
    local off = CreateFrame("Frame", "EABBar_Bar3")
    off:Hide()
    for _, first in ipairs({ 1, 61 }) do
        for i = 0, 11 do CreateFrame("Button", "EABButton" .. (first + i)):SetAttribute("action", first + i) end
    end
    local page = barsPage()
    eq(page.source.text, "EllesmereUI's action bars")
    eq(page.rows[1].label.text, "Bar 1"); eq(page.rows[2].label.text, "Bar 2"); eq(page.rows[3], nil)
    eq(page.rows[2].slots[1].slot, 61); eq(page.rows[2].slots[1].keyText.text, "Q")
end)

test("ElvUI's bars: each button's own slot and binding", function()
    loginWithSetup(nil)
    CreateFrame("Frame", "ElvUI_Bar1")
    for i = 1, 12 do
        local b = CreateFrame("Button", "ElvUI_Bar1Button" .. i)
        b._state_action, b.keyBoundTarget = i, "ACTIONBUTTON" .. i
    end
    local page = barsPage()
    eq(page.source.text, "ElvUI's action bars")
    eq(page.rows[1].slots[2].slot, 2); eq(page.rows[1].slots[2].keyText.text, "2")
end)

test("a bar change while the tab is open shows at once", function()
    loginWithSetup(nil)
    blizzardBars()
    local page = barsPage()
    eq(page.rows[1].slots[4].icon:IsShown(), false)
    wow.slots[4] = { kind = "spell", id = 647 }
    wow.fire("ACTIONBAR_SLOT_CHANGED", 4)
    wow.runTimers()
    eq(page.rows[1].slots[4].icon:IsShown(), true)
end)

test("with no bars showing, the tab says so", function()
    loginWithSetup(nil)
    local page = barsPage()
    eq(page.empty:IsShown(), true)
end)

test("a closed window does no work when bars or modifiers change", function()
    loginWithSetup(nil)
    blizzardBars()
    barsPage()
    slash("") -- closed
    wow.timers = {}
    wow.fire("ACTIONBAR_SLOT_CHANGED", 4)
    wow.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
    wow.fire("UPDATE_BINDINGS")
    eq(#wow.timers, 0, "nothing scheduled")
end)

---------------------------------------------------------------------------
-- Keybind mode
function bindModeLogin(shared)
    local c, ns = profileLogin(shared)
    blizzardBars()
    local page = barsPage()
    return page, ns
end

function hover(b) b.scripts.OnEnter(b) end

test("keybind mode: hover a slot and press a key to put it there", function()
    local page, ns = bindModeLogin()
    click(page.bindButton)
    eq(page.catcher.keyboard, true, "key presses come to Keystance")
    eq(page.bindNote:IsShown(), true)
    eq(page.bindButton.text, "Done")
    hover(page.rows[1].slots[4])
    page.catcher.scripts.OnKeyDown(page.catcher, "E")
    eq(GetBindingAction("E"), "ACTIONBUTTON4")
    wow.mods.shift = true
    page.catcher.scripts.OnKeyDown(page.catcher, "LSHIFT")
    page.catcher.scripts.OnKeyDown(page.catcher, "E")
    wow.mods.shift = false
    eq(GetBindingAction("SHIFT-E"), "ACTIONBUTTON4", "with the modifier held")
    eq(ns.UndoLabel(), "putting slot 4 on SHIFT-E")
end)

test("keybind mode: a key used for something else says what it was", function()
    local page = bindModeLogin()
    click(page.bindButton)
    hover(page.rows[1].slots[1])
    page.catcher.scripts.OnKeyDown(page.catcher, "W")
    eq(GetBindingAction("W"), "ACTIONBUTTON1")
    assert(printed():find("(W was Move Forward.)", 1, true), printed())
end)

test("keybind mode: mouse buttons, the wheel and controller buttons bind too; right-click clears", function()
    local page = bindModeLogin()
    click(page.bindButton)
    local s2 = page.rows[1].slots[2]
    hover(s2)
    click(s2, "Button4")
    eq(GetBindingAction("BUTTON4"), "ACTIONBUTTON2")
    s2.scripts.OnMouseWheel(s2, 1)
    eq(GetBindingAction("MOUSEWHEELUP"), "ACTIONBUTTON2")
    page.catcher.scripts.OnGamePadButtonDown(page.catcher, "PAD1")
    eq(GetBindingAction("PAD1"), "ACTIONBUTTON2")
    click(s2, "RightButton")
    eq(GetBindingAction("BUTTON4"), ""); eq(GetBindingAction("2"), "")
    eq(wow.popup, nil, "no remove question in keybind mode")
end)

test("keybind mode ends with Escape, in combat, and when the tab closes", function()
    local page = bindModeLogin()
    click(page.bindButton)
    page.catcher.scripts.OnKeyDown(page.catcher, "ESCAPE")
    eq(page.catcher.keyboard, false)
    click(page.bindButton)
    wow.enterCombat()
    eq(page.catcher.keyboard, false, "combat")
    wow.leaveCombat()
    click(page.bindButton)
    click(tabNamed("Keyboard"))
    eq(page.catcher.keyboard, false, "another tab")
end)

test("keybind mode with shared keybinds asks first and gives the character its own", function()
    local page = bindModeLogin(true)
    click(page.bindButton)
    eq(page.catcher.keyboard, false, "not started yet")
    eq(wow.popup.which, "KEYSTANCE_BIND_MODE")
    StaticPopupDialogs.KEYSTANCE_BIND_MODE.OnAccept(nil, wow.popup.data)
    eq(GetCurrentBindingSet(), 2)
    eq(page.catcher.keyboard, true)
end)

test("keybind mode can't start in combat", function()
    local page = bindModeLogin()
    wow.enterCombat()
    click(page.bindButton)
    eq(page.catcher.keyboard, false)
    wow.leaveCombat()
end)
