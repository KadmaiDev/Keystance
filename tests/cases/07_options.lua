-- Tests: our page in the game's Options > AddOns list.
---------------------------------------------------------------------------
function optionsPanel() return KeystanceOptionsPanel end

-- /kst options, then the next frame (it opens a frame later).
function openOptions()
    slash("options")
    wow.runTimers()
end

test("the Options page is registered at login but built only when first shown", function()
    start(nil)
    eq(#wow.settingsCategories, 1)
    eq(wow.settingsCategories[1].name, "Keystance")
    eq(optionsPanel().built, nil, "nothing built until the page is opened")
    openOptions()
    eq(wow.openedCategory, "cat:Keystance")
    eq(optionsPanel().built, true)
    eq(choice(optionsPanel().lookRow, "Automatic").chosen, true)
    eq(optionsPanel().minimap.text, "Minimap button: shown")
end)

test("the Options page and the window's Settings tab are the same controls, kept in step", function()
    start(nil)
    openOptions()
    local p = optionsPanel()
    click(p.minimap)
    eq(KeystanceMinimapButton:IsShown(), false)
    eq(p.minimap.text, "Minimap button: hidden")
    slash("")
    click(tabNamed("Settings"))
    eq(KeystanceFrame.pages[5].minimap.text, "Minimap button: hidden")
    click(KeystanceFrame.pages[5].minimap)
    eq(p.minimap.text, "Minimap button: shown", "the Options page follows a change made in the window")
    click(choice(p.lookRow, "Classic"))
    eq(KeystanceDB.settings.skin, "classic")
    click(tabNamed("Settings"))
    eq(choice(KeystanceFrame.pages[5].lookRow, "Classic").chosen, true, "the window's tab follows too")
end)

test("Open Keystance closes the Options panel first, then opens the window a frame later", function()
    start(nil)
    openOptions()
    click(optionsPanel().open)
    eq(SettingsPanel:IsShown(), false)
    eq(KeystanceFrame, nil, "not in the same frame as the panel closing")
    wow.runTimers()
    eq(KeystanceFrame:IsShown(), true)
end)

test("in combat, Open Keystance leaves Blizzard's panel alone", function()
    start(nil)
    openOptions()
    wow.enterCombat()
    click(optionsPanel().open)
    eq(#wow.hiddenPanels, 0)
    wow.runTimers()
    eq(KeystanceFrame:IsShown(), true)
    wow.leaveCombat()
    eq(#wow.blocked, 0)
end)

test("the minimap menu's Settings entry opens the Options page", function()
    start(nil)
    Keystance_OnAddonCompartmentClick("Keystance", "RightButton", UIParent)
    wow.menuItem("Settings").fn()
    eq(wow.openedCategory, nil, "not while the menu is still closing")
    wow.runTimers()
    eq(wow.openedCategory, "cat:Keystance")
end)

test("without the game's Settings API, /kst options opens the window's Settings tab", function()
    wow.withoutSettings = true
    start(nil)
    openOptions()
    eq(KeystanceFrame:IsShown(), true)
    eq(shownPage(), "settings")
end)

test("with ElvUI, the Options page's buttons and text take its look", function()
    wow.withElvUI = true
    start(nil)
    openOptions()
    assert(skinnedWith("HandleButton", optionsPanel().open))
    assert(skinnedWith("HandleButton", optionsPanel().lookRow.buttons[1]))
end)

-- Blizzard's setting objects run our values through its secure settings code; the page is a
-- plain canvas instead (Alts Forever's old page used RegisterProxySetting).
test("no file uses Blizzard's setting objects", function()
    for _, file in ipairs(FILES) do
        local code = readFile(file):gsub("%-%-[^\n]*", "")
        for _, name in ipairs({ "RegisterProxySetting", "RegisterAddOnSetting", "RegisterVerticalLayoutCategory",
            "Settings.RegisterSetting", "CreateSettingsListSectionHeaderInitializer" }) do
            assert(not code:find(name, 1, true), file .. " uses " .. name)
        end
    end
end)

test("if the game refuses to open the Options page, the error is reported, not hidden", function()
    start(nil)
    Settings.OpenToCategory = function() error("refused") end
    openOptions()
    eq(#wow.errors, 1)
    assert(tostring(wow.errors[1]):find("refused", 1, true))
end)
