-- Tests: the profile switcher on screen.

-- Vespera with Ret and Prot (Ret in use), on her own keybinds.
local function twoProfiles()
    local c, ns = profileLogin()
    ns.SaveProfile("Ret")
    wow.slots[1] = { kind = "spell", id = 647 }
    ns.SaveProfile("Prot")
    wow.slots[1] = { kind = "spell", id = 1866 }
    c.active = "Ret"
    return c, ns
end

-- The switcher's button for a profile.
local function switchButton(name)
    for _, b in ipairs(KeystanceSwitcher.buttons) do
        if b.profile == name and b:IsShown() then return b end
    end
end

test("the switcher is off by default, and isn't even built", function()
    twoProfiles()
    eq(KeystanceSwitcher, nil)
end)

test("turned on in Settings, it shows a button per profile, the one in use ringed", function()
    local c, ns = twoProfiles()
    slash("")
    click(tabNamed("Settings"))
    click(choice(pageFor("settings").switcherRow, "On"))
    eq(KeystanceDB.settings.switcher, "shown")
    eq(KeystanceSwitcher:IsShown(), true)
    eq(switchButton("Prot").icon.texture, 200647, "its icon")
    eq(switchButton("Ret").ring:IsShown(), true)
    eq(switchButton("Prot").ring:IsShown(), false)
    eq(KeystanceSwitcher.width, 5 * 2 + 2 * 28 + 4, "sized to its buttons")
end)

test("a click switches at once, no question asked, and the ring follows", function()
    local c, ns = twoProfiles()
    ns.SetSwitcherMode("shown")
    click(switchButton("Prot"))
    eq(c.active, "Prot")
    eq(slotId(1), 647)
    eq(wow.popup, nil)
    eq(switchButton("Prot").ring:IsShown(), true)
    eq(switchButton("Ret").ring:IsShown(), false)
end)

test("in combat a click queues the switch, shown until combat ends; another click changes it", function()
    local c, ns = twoProfiles()
    ns.SetSwitcherMode("shown")
    wow.enterCombat()
    click(switchButton("Prot"))
    eq(c.active, "Ret", "not yet")
    eq(#wow.blocked, 0)
    eq(ns.pendingProfile, "Prot")
    eq(switchButton("Prot").queued:IsShown(), true, "waiting, and says so")
    ns.SaveProfile("Holy")
    click(switchButton("Holy"))
    eq(switchButton("Holy").queued:IsShown(), true, "changed my mind")
    eq(switchButton("Prot").queued:IsShown(), false)
    wow.leaveCombat()
    eq(c.active, "Holy")
    eq(ns.pendingProfile, nil)
    eq(switchButton("Holy").queued:IsShown(), false)
    eq(switchButton("Holy").ring:IsShown(), true)
end)

test("clicking the profile in use while a switch waits cancels it", function()
    local c, ns = twoProfiles()
    ns.SetSwitcherMode("shown")
    wow.enterCombat()
    click(switchButton("Prot"))
    click(switchButton("Ret"))
    eq(ns.pendingProfile, nil)
    assert(printed():find("Switching to Prot cancelled.", 1, true), printed())
    wow.leaveCombat()
    eq(c.active, "Ret", "nothing happened")
    eq(slotId(1), 1866)
end)

test("dragging moves it while On, not while Locked; the place is remembered", function()
    local c, ns = twoProfiles()
    ns.SetSwitcherMode("shown")
    local moved = false
    KeystanceSwitcher.StartMoving = function() moved = true end
    local b = switchButton("Prot")
    b.scripts.OnDragStart(b)
    eq(moved, true)
    KeystanceSwitcher:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -50)
    b.scripts.OnDragStop(b)
    eq(KeystanceDB.settings.switcherPos[3], 100)
    moved = false
    ns.SetSwitcherMode("locked")
    b.scripts.OnDragStart(b)
    eq(moved, false, "locked")
end)

test("right-click opens Keystance; /kst switcher and the minimap menu turn it on and off", function()
    local c, ns = twoProfiles()
    slash("switcher")
    eq(KeystanceSwitcher:IsShown(), true)
    click(switchButton("Prot"), "RightButton")
    eq(KeystanceFrame:IsShown(), true)
    eq(c.active, "Ret", "right-click doesn't switch")
    slash("switcher off")
    eq(KeystanceSwitcher:IsShown(), false)
    Keystance_OnAddonCompartmentClick("Keystance", "RightButton", UIParent)
    wow.menuItem("Show profile switcher").setSelected()
    eq(KeystanceSwitcher:IsShown(), true)
end)

test("it follows profiles being added, renamed and given keys", function()
    local c, ns = twoProfiles()
    ns.SetSwitcherMode("shown")
    ns.RenameProfile("Prot", "Tank")
    eq(switchButton("Tank") ~= nil, true)
    ns.SetProfileKey("Tank", "F2")
    wow.runTimers() -- key labels follow a keybinding change a moment later
    eq(switchButton("Tank").key.text, "F2")
    ns.DeleteProfile("Ret")
    eq(switchButton("Ret"), nil)
end)

test("saved as shown, it comes back at login", function()
    local ns = wow.load(FILES)
    paladinSetup()
    wow.login({ version = 1, settings = { switcher = "locked" }, chars = {} })
    eq(KeystanceSwitcher:IsShown(), true)
end)
