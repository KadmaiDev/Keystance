-- Tests: hidden bars on the Bars tab, and putting them on screen.

local function openFold(page)
    click(page.hiddenFold)
    return page.hiddenRows
end

test("hidden bars are folded under the shown ones, dimmed, with their slots and keys", function()
    loginWithSetup(nil)
    blizzardBars() -- the right bar is hidden
    wow.slots[25] = { kind = "spell", id = 647 }
    wow.bindings.F5 = "MULTIACTIONBAR3BUTTON1"
    local page = barsPage()
    eq(page.rows[3], nil, "not among the shown bars")
    eq(page.hiddenFold:IsShown(), true)
    eq(page.hiddenFold.text, "+ Hidden bars (1)")
    eq(page.hiddenRows[1], nil, "folded")
    local rows = openFold(page)
    eq(KeystanceDB.settings.hiddenBarsOpen, true, "remembered")
    eq(page.hiddenFold.text, "- Hidden bars (1)")
    eq(rows[1].label.text, "Right")
    eq(rows[1].alpha, 0.55, "dimmed")
    eq(rows[1].slots[1].slot, 25)
    eq(rows[1].slots[1].icon:IsShown(), true, "what's in its slots")
    eq(rows[1].slots[1].keyText.text, "F5")
    eq(rows[1].point[5], -40 - 3 * 33, "under the two shown bars and the fold")
    click(page.hiddenFold)
    eq(rows[1]:IsShown(), false)
end)

test("a hidden bar's slots take spells like any other", function()
    loginWithSetup(nil)
    blizzardBars()
    local page = barsPage()
    local rows = openFold(page)
    wow.cursor = { "spell", 1, "spell", 19834 }
    click(rows[1].slots[2])
    eq(wow.slots[26].id, 19834)
end)

test("Show puts a Blizzard bar on screen with the game's own switch, keeping the others", function()
    loginWithSetup(nil)
    blizzardBars()
    wow.barToggles = { true, false, false, false, false, false, false } -- bottom left on
    local page = barsPage()
    local rows = openFold(page)
    click(rows[1].show)
    eq(wow.barToggles[3], true, "the right bar's switch")
    eq(wow.barToggles[1], true, "the bottom left bar's kept")
    eq(wow.barToggles[2], false)
    wow.runTimers()
    assert(printed():find("Right is on screen now.", 1, true), printed())
    wow.runTimers()
    eq(page.rows[3].label.text, "Right", "now among the shown bars")
    eq(page.rows[3].slots[1].slot, 25)
    eq(page.hiddenFold:IsShown(), false, "no hidden bars left")
end)

test("if the game's switch doesn't bring the bar up, it says where to switch it on", function()
    loginWithSetup(nil)
    blizzardBars()
    wow.togglesWork = false
    local page = barsPage()
    click(openFold(page)[1].show)
    wow.runTimers()
    assert(printed():find("Right didn't appear: switch it on in the game's Options, under Action Bars.", 1, true), printed())
end)

test("Show waits out combat: nothing is switched in combat", function()
    loginWithSetup(nil)
    blizzardBars()
    local page = barsPage()
    local rows = openFold(page)
    wow.enterCombat()
    click(rows[1].show)
    eq(wow.toggleCalls, nil)
    eq(#wow.blocked, 0)
    assert(printed():find("Not in combat", 1, true))
    wow.leaveCombat()
end)

test("EllesmereUI's hidden bars: Show opens its Action Bars settings, and doesn't change them itself", function()
    loginWithSetup(nil)
    CreateFrame("Frame", "EABBar_MainBar")
    local off = CreateFrame("Frame", "EABBar_Bar3")
    off:Hide()
    CreateFrame("Button", "EABButton1"):SetAttribute("action", 1)
    local opened
    EllesmereUI = { ShowModule = function(_, module) opened = module end }
    local page = barsPage()
    local rows = openFold(page)
    eq(rows[1].label.text, "Bar 3")
    eq(rows[1].slots[1].slot, 49, "EllesmereUI's Bar 3 is slots 49-60")
    click(rows[1].show)
    eq(opened, "EllesmereUIActionBars")
    eq(wow.toggleCalls, nil, "the game's switches aren't touched")
    assert(printed():find("Switch Bar 3 on in EllesmereUI's Action Bars settings", 1, true), printed())
    -- Switched on there: the tab follows at once.
    off:Show()
    wow.runTimers()
    eq(page.rows[2].label.text, "Bar 3")
    EllesmereUI = nil
end)

test("ElvUI's hidden bars: Show opens its action bar options", function()
    loginWithSetup(nil)
    CreateFrame("Frame", "ElvUI_Bar1")
    local off = CreateFrame("Frame", "ElvUI_Bar3")
    off:Hide()
    CreateFrame("Button", "ElvUI_Bar1Button1")
    local opened
    ElvUI = { { ToggleOptions = function(_, msg) opened = msg end } }
    local page = barsPage()
    local rows = openFold(page)
    eq(rows[1].label.text, "Bar 3")
    eq(rows[1].slots[12].slot, 36, "bar 3 shows page 3: slots 25-36")
    click(rows[1].show)
    eq(opened, "actionbar")
    assert(printed():find("Switch Bar 3 on in ElvUI's Action Bars settings", 1, true), printed())
    ElvUI = nil
end)
