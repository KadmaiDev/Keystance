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

-- The window's page for a tab ("profiles", "keyboard"...).
function pageFor(key)
    for _, page in ipairs(KeystanceFrame.pages) do
        if page.key == key then return page end
    end
end

-- The button labelled `text` in a row of choices.
function choice(row, text)
    for _, b in ipairs(row.buttons) do
        if b.text == text then return b end
    end
end

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
    eq(table.concat(names, ","), "Profiles,Bars,Keyboard,Rules,Settings")
    eq(shownPage(), "profiles", "home: where a new player starts")
    click(tabNamed("Keyboard"))
    eq(shownPage(), "keyboard")
    eq(tabNamed("Keyboard").selectedTab, true)
    eq(tabNamed("Profiles").selectedTab, false)
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

test("Settings: the look buttons save the choice, offer to reload and say what's in use", function()
    wow.withElvUI = true
    start(nil)
    slash("")
    click(tabNamed("Settings"))
    local page = pageFor("settings")
    eq(choice(page.lookRow, "Automatic").chosen, true)
    eq(page.lookNote.text, "In use: ElvUI.")
    click(choice(page.lookRow, "Classic"))
    eq(KeystanceDB.settings.skin, "classic")
    eq(choice(page.lookRow, "Classic").chosen, true)
    eq(choice(page.lookRow, "Automatic").chosen, false)
    eq(page.lookNote.text, "In use: ElvUI until you reload.")
    eq(wow.popup.which, "KEYSTANCE_RELOAD")
    eq(wow.menu, nil, "no pop-up menu: they once crashed the beta client")
end)

test("Settings: the minimap button can be hidden and shown", function()
    start(nil)
    slash("")
    click(tabNamed("Settings"))
    local page = pageFor("settings")
    eq(choice(page.minimapRow, "Shown").chosen, true)
    click(choice(page.minimapRow, "Hidden"))
    eq(KeystanceMinimapButton:IsShown(), false)
    eq(choice(page.minimapRow, "Hidden").chosen, true)
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

-- True if the frame and every parent are shown.
local function onScreen(f)
    while f do
        if not f.shown then return false end
        f = f.parent
    end
    return true
end

test("the open window never takes the keyboard (Esc, Enter...) unless it's waiting for a key", function()
    local c, ns = profileLogin()
    ns.SaveProfile("Ret")
    slash("")
    for _, tab in ipairs(KeystanceFrame.tabs) do
        click(tab)
        for _, f in ipairs(wow.frames) do
            if (f.keyboard or f.gamepad) and onScreen(f) then
                error("a shown frame takes the keyboard on the " .. tab.text .. " tab")
            end
        end
    end
    -- Waiting for a profile's key: it does, and lets go after.
    click(tabNamed("Profiles"))
    local page = pageFor("profiles")
    click(page.rows[1].key)
    eq(page.catcher.keyboard and onScreen(page.catcher), true)
    page.catcher.scripts.OnKeyDown(page.catcher, "ESCAPE")
    eq(onScreen(page.catcher), false)
    eq(page.catcher.keyboard, false)
end)
