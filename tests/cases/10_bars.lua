-- Tests: the Bars tab.
---------------------------------------------------------------------------
function barsPage()
    slash("")
    click(tabNamed("Bars"))
    return KeystanceFrame.pages[2]
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
