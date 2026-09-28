-- Tests: the main window.
---------------------------------------------------------------------------
function tabNamed(name)
    for _, tab in ipairs(KeystanceFrame.tabs) do
        if tab.text == name then return tab end
    end
end

function shownPage()
    for _, page in ipairs(KeystanceFrame.pages) do
        if page:IsShown() then return page.key end
    end
end

function click(b, button) b.scripts.OnClick(b, button or "LeftButton") end

test("the window is only built when first opened", function()
    start(nil)
    eq(KeystanceFrame, nil)
    slash("")
    assert(KeystanceFrame, "built on first open")
    eq(KeystanceFrame:IsShown(), true)
end)

test("the window has the five tabs, and each shows its own page", function()
    start(nil)
    slash("")
    local names = {}
    for i, tab in ipairs(KeystanceFrame.tabs) do names[i] = tab.text end
    eq(table.concat(names, ","), "Keyboard,Bars,Profiles,Rules,Settings")
    eq(shownPage(), "keyboard", "the first tab by default")
    click(tabNamed("Profiles"))
    eq(shownPage(), "profiles")
    eq(tabNamed("Profiles").selectedTab, true)
    eq(tabNamed("Keyboard").selectedTab, false)
end)

test("the last tab used and the window position are remembered next session", function()
    start(nil)
    slash("")
    click(tabNamed("Settings"))
    KeystanceFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -80)
    KeystanceFrame.scripts.OnDragStop(KeystanceFrame)
    local saved = KeystanceDB
    start(saved)
    slash("")
    eq(shownPage(), "settings")
    local point, rel, relPoint, x, y = KeystanceFrame:GetPoint()
    eq(point, "TOPLEFT"); eq(rel, UIParent); eq(relPoint, "TOPLEFT"); eq(x, 100); eq(y, -80)
end)

test("Escape closes the window, like Blizzard's own", function()
    start(nil)
    slash("")
    slash("")
    slash("")
    local n = 0
    for _, name in ipairs(UISpecialFrames) do if name == "KeystanceFrame" then n = n + 1 end end
    eq(n, 1, "added once")
end)

test("in combat the window says changes wait until combat ends", function()
    start(nil)
    slash("")
    eq(KeystanceFrame.combat:IsShown(), false)
    wow.enterCombat()
    eq(KeystanceFrame.combat:IsShown(), true)
    wow.leaveCombat()
    eq(KeystanceFrame.combat:IsShown(), false)
end)

test("Settings: the look menu saves the choice, offers to reload and says what's in use", function()
    wow.withElvUI = true
    start(nil)
    slash("")
    click(tabNamed("Settings"))
    local page = KeystanceFrame.pages[5]
    eq(page.look.text, "Look: Automatic")
    eq(page.lookNote.text, "In use: ElvUI.")
    click(page.look)
    wow.menuItem("Classic").setSelected()
    eq(KeystanceDB.settings.skin, "classic")
    eq(page.look.text, "Look: Classic")
    eq(page.lookNote.text, "In use: ElvUI until you reload.")
    eq(wow.popup.which, "KEYSTANCE_RELOAD")
    eq(wow.menuItem("Classic").isSelected(), true)
end)

test("Settings: the minimap button can be hidden and shown", function()
    start(nil)
    slash("")
    click(tabNamed("Settings"))
    local page = KeystanceFrame.pages[5]
    eq(page.minimap.text, "Minimap button: shown")
    click(page.minimap)
    eq(KeystanceMinimapButton:IsShown(), false)
    eq(page.minimap.text, "Minimap button: hidden")
end)

test("without Blizzard's window and tab templates the window still opens", function()
    wow.load(FILES)
    wow.missingTemplates = { BasicFrameTemplateWithInset = true, PanelTopTabButtonTemplate = true }
    wow.login(nil)
    slash("")
    eq(KeystanceFrame:IsShown(), true)
    click(tabNamed("Bars"))
    eq(shownPage(), "bars")
    eq(tabNamed("Bars").highlightLocked, true)
end)
