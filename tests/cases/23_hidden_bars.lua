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
    local row = rows[1]
    click(page.hiddenFold)
    eq(row:IsShown(), false)
    eq(#page.hiddenRows, 0)
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

test("Hide takes a Blizzard bar off screen with the game's switch; its spells stay; the main bar has no Hide", function()
    loginWithSetup(nil)
    blizzardBars()
    wow.barToggles = { true, false, false, false, false, false, false }
    wow.slots[62] = { kind = "spell", id = 647 }
    local page = barsPage()
    eq(page.rows[1].hide:IsShown(), false, "the main bar can't be hidden")
    eq(page.rows[2].hide:IsShown(), true)
    click(page.rows[2].hide)
    eq(wow.barToggles[1], false)
    wow.runTimers()
    assert(printed():find("Bottom left is hidden now. It keeps its spells and keys", 1, true), printed())
    wow.runTimers()
    eq(page.rows[2]:IsShown(), false, "no longer among the shown bars")
    eq(page.hiddenFold.text:find("Hidden bars (2)", 1, true) ~= nil, true)
    eq(wow.slots[62].id, 647, "its spells stay")
    -- And back again.
    local rows = openFold(page)
    eq(rows[1].label.text, "Bottom left")
    click(rows[1].show)
    wow.runTimers()
    wow.runTimers()
    eq(page.rows[2].label.text, "Bottom left")
end)

test("Hide on EllesmereUI's bars opens its settings; its main bar has no Hide", function()
    loginWithSetup(nil)
    CreateFrame("Frame", "EABBar_MainBar")
    CreateFrame("Frame", "EABBar_Bar2")
    CreateFrame("Button", "EABButton1"):SetAttribute("action", 1)
    local opened
    EllesmereUI = { ShowModule = function(_, module) opened = module end }
    local page = barsPage()
    eq(page.rows[1].hide:IsShown(), false)
    click(page.rows[2].hide)
    eq(opened, "EllesmereUIActionBars")
    assert(printed():find("Switch Bar 2 off in EllesmereUI's Action Bars settings.", 1, true), printed())
    EllesmereUI = nil
end)

test("Hide waits out combat too", function()
    loginWithSetup(nil)
    blizzardBars()
    wow.barToggles = { true, false, false, false, false, false, false }
    local page = barsPage()
    wow.enterCombat()
    click(page.rows[2].hide)
    eq(wow.toggleCalls, nil)
    eq(#wow.blocked, 0)
    wow.leaveCombat()
end)

-- A stand-in for EllesmereUI's action bars: bar settings in its profile, its Visibility
-- helper and its refreshes, which show or hide each bar frame by its Visibility (out of
-- combat, as now). `bars` is { [key] = settings }.
local function fakeEllesmere(bars)
    local frames = {}
    for key in pairs(bars) do frames[key] = CreateFrame("Frame", "EABBar_" .. key) end
    CreateFrame("Button", "EABButton1"):SetAttribute("action", 1)
    local eab = { db = { profile = { bars = bars } }, calls = {}, VisibilityCompat = {} }
    function eab.VisibilityCompat.ApplyMode(set, mode)
        set.barVisibility, set.alwaysHidden = mode, mode == "never"
        return mode
    end
    function eab:RefreshRuntimeVisibility()
        self.calls[#self.calls + 1] = "RefreshRuntimeVisibility"
        for key, set in pairs(bars) do
            local mode = set.barVisibility or "always"
            frames[key]:SetShown(set.enabled ~= false and mode ~= "never" and mode ~= "in_combat")
        end
    end
    function eab:RefreshMouseover() self.calls[#self.calls + 1] = "RefreshMouseover" end
    function eab:ApplyCombatVisibility() self.calls[#self.calls + 1] = "ApplyCombatVisibility" end
    local opened
    EllesmereUI = { Lite = { GetAddon = function(name) return name == "EllesmereUIActionBars" and eab or nil end },
        ShowModule = function(_, module) opened = module end }
    eab:RefreshRuntimeVisibility()
    eab.calls = {}
    return eab, frames, function() return opened end
end

test("EllesmereUI bars shown only in combat or on mouseover count as in use, with a note", function()
    loginWithSetup(nil)
    fakeEllesmere({ MainBar = {}, Bar2 = { barVisibility = "mouseover" }, Bar4 = { barVisibility = "in_combat" },
        Bar5 = { barVisibility = "never" }, Bar6 = { enabled = false } })
    local page = barsPage()
    eq(page.rows[1].label.text, "Bar 1")
    eq(page.rows[1].note:IsShown(), false, "always shown: no note")
    eq(page.rows[2].note.text, "mouseover")
    eq(page.rows[3].label.text, "Bar 4", "hidden now, but in use")
    eq(page.rows[3].note.text, "in combat")
    eq(page.hiddenFold.text, "+ Hidden bars (2)", "Never and switched off")
    EllesmereUI = nil
end)

test("Hide sets an EllesmereUI bar's Visibility to Never, and Show puts back what it was", function()
    loginWithSetup(nil)
    local bars = { MainBar = {}, Bar2 = { barVisibility = "mouseover" } }
    local eab, frames, opened = fakeEllesmere(bars)
    local page = barsPage()
    click(page.rows[2].hide)
    eq(bars.Bar2.barVisibility, "never")
    eq(KeystanceDB.settings.euiVisibility.Bar2, "mouseover", "remembered")
    eq(table.concat(eab.calls, ","), "RefreshRuntimeVisibility,RefreshMouseover,ApplyCombatVisibility",
        "the refreshes its own Visibility control runs")
    eq(frames.Bar2:IsShown(), false)
    eq(opened(), nil, "no settings page needed")
    wow.runTimers()
    assert(printed():find("Bar 2 is hidden now (its Visibility is Never in EllesmereUI)", 1, true), printed())
    wow.runTimers()
    local rows = openFold(page)
    eq(rows[1].label.text, "Bar 2")
    click(rows[1].show)
    eq(bars.Bar2.barVisibility, "mouseover", "as it was")
    eq(KeystanceDB.settings.euiVisibility.Bar2, nil)
    wow.runTimers()
    assert(printed():find("Bar 2 is back (mouseover).", 1, true), printed())
    EllesmereUI = nil
end)

test("an EllesmereUI bar Keystance didn't hide comes back as always shown", function()
    loginWithSetup(nil)
    local bars = { MainBar = {}, Bar3 = { barVisibility = "never" } }
    fakeEllesmere(bars)
    local page = barsPage()
    click(openFold(page)[1].show)
    eq(bars.Bar3.barVisibility, "always")
    wow.runTimers()
    assert(printed():find("Bar 3 is back (always shown).", 1, true), printed())
    EllesmereUI = nil
end)

test("a bar switched off entirely, or EllesmereUI without its pieces: its settings page opens instead", function()
    loginWithSetup(nil)
    local bars = { MainBar = {}, Bar6 = { enabled = false } }
    local eab, _, opened = fakeEllesmere(bars)
    local page = barsPage()
    click(openFold(page)[1].show)
    eq(opened(), "EllesmereUIActionBars")
    eq(bars.Bar6.enabled, false, "not touched")
    EllesmereUI = nil
end)

test("if EllesmereUI lacks a piece Keystance needs (after an update), its page opens and nothing changes", function()
    loginWithSetup(nil)
    local bars = { MainBar = {}, Bar2 = {} }
    local eab, _, opened = fakeEllesmere(bars)
    eab.RefreshMouseover = nil
    local page = barsPage()
    click(page.rows[2].hide)
    eq(opened(), "EllesmereUIActionBars")
    eq(bars.Bar2.barVisibility, nil, "not touched")
    assert(printed():find("Switch Bar 2 off in EllesmereUI's Action Bars settings.", 1, true), printed())
    EllesmereUI = nil
end)

test("more bars than fit: the tab scrolls, so every bar and hidden bar can be reached", function()
    loginWithSetup(nil)
    local bars = {}
    for i = 1, 9 do bars[i == 1 and "MainBar" or ("Bar" .. i)] = {} end
    bars.Bar10 = { barVisibility = "never" }
    local eab = { db = { profile = { bars = bars } }, VisibilityCompat = {} }
    for key in pairs(bars) do
        local f = CreateFrame("Frame", "EABBar_" .. key)
        f:SetShown(bars[key].barVisibility ~= "never")
    end
    CreateFrame("Button", "EABButton1"):SetAttribute("action", 1)
    EllesmereUI = { Lite = { GetAddon = function() return eab end } }
    local page = barsPage()
    click(page.hiddenFold) -- nine bars and the fold fill the ten rows; unfolding adds Bar 10
    eq(page.scroll:IsShown(), true)
    eq(page.hiddenFold.point[5], -40 - 9 * 33 - 2, "the fold is on row 10")
    page.scripts.OnMouseWheel(page, -1) -- down one
    eq(page.offset, 1)
    eq(page.rows[1].label.text, "Bar 2")
    eq(page.rows[10].label.text, "Bar 10", "the hidden bar, now in reach")
    eq(page.rows[10].show:IsShown(), true)
    eq(page.rows[10].alpha, 0.55)
    page.scripts.OnMouseWheel(page, -5)
    eq(page.offset, 1, "no further than the end")
    page.scroll.scripts.OnValueChanged(page.scroll, 0)
    eq(page.rows[1].label.text, "Bar 1")
    click(page.hiddenFold)
    eq(page.scroll:IsShown(), false, "everything fits again")
    EllesmereUI = nil
end)
