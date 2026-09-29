-- Tests: the gear editor, opened from a profile's row on the Profiles tab.

-- The gear editor for `name`, from the Profiles tab.
function gearView(name)
    local page = profilesPage()
    for _, row in ipairs(page.rows) do
        if row.profile == name and row:IsShown() then click(row.gear) end
    end
    return page.gearView, page
end

local function gearString(id) return "item:" .. id .. ":0:0:0:0:0:0:0:20" end

test("a profile's Gear button swaps the list for its gear editor; Back returns", function()
    local c, ns = gearLogin()
    ns.SaveProfile("Prot")
    local view, page = gearView("Prot")
    eq(view:IsShown(), true)
    eq(page.list:IsShown(), false)
    eq(view.title.text, "Gear for Prot")
    eq(view.from:IsShown(), false, "no source to choose without ItemRack")
    eq(view.items:IsShown(), true)
    click(view.back)
    eq(view:IsShown(), false)
    eq(page.list:IsShown(), true)
end)

test("slots: click takes what's worn, a dropped item is used, right-click leaves it alone", function()
    local c, ns = gearLogin()
    ns.SaveProfile("Prot")
    local view = gearView("Prot")
    click(view.slots[1])
    eq(c.profiles.Prot.gear[1], gearString(1101), "the worn helm")
    eq(view.slots[1].name.text, "Coif")
    wow.cursor = { "item", 1100, "|cffffffff|H" .. gearString(1100) .. "|h[Lionheart Helm]|h|r" }
    view.slots[1].scripts.OnReceiveDrag(view.slots[1])
    eq(c.profiles.Prot.gear[1], gearString(1100))
    eq(wow.cursor, nil, "the item went back to its bag")
    click(view.slots[1], "RightButton")
    eq(c.profiles.Prot.gear, nil, "no slots left: no gear")
    eq(view.slots[1].name.text, "Head")
    click(view.slots[5])
    eq(c.profiles.Prot.gear, nil, "nothing worn there: nothing taken")
end)

test("Take what I'm wearing fills every worn slot; No gear empties them; the row says so", function()
    local c, ns = gearLogin()
    ns.SaveProfile("Prot")
    local view, page = gearView("Prot")
    click(view.wearing)
    eq(c.profiles.Prot.gear[16], gearString(2132))
    eq(c.profiles.Prot.gear[17], gearString(2129))
    eq(c.profiles.Prot.gear[1], gearString(1101))
    click(view.back)
    assert(page.rows[1].name.text:find("3 items", 1, true), page.rows[1].name.text)
    assert(not page.rows[1].detail.text:find("items", 1, true), "the second line stays short")
    click(page.rows[1].gear)
    click(view.none)
    eq(c.profiles.Prot.gear, nil)
end)

test("with ItemRack, the editor lists its sets to choose from, and the source can be switched", function()
    local c, ns = gearLogin({ Tank = { [1] = 1100 }, Dps = { [16] = 1680 } })
    ns.SaveProfile("Prot")
    local view, page = gearView("Prot")
    eq(view.from:IsShown(), true)
    eq(choice(view.source, "ItemRack").chosen, true)
    eq(view.sets:IsShown(), true)
    eq(view.items:IsShown(), false)
    eq(view.setButtons[1].text, "No gear")
    eq(view.setButtons[1].chosen, true)
    eq(view.setButtons[3].set, "Tank")
    click(view.setButtons[3])
    eq(c.profiles.Prot.itemrack, "Tank")
    eq(view.setButtons[3].chosen, true)
    click(view.back)
    assert(page.rows[1].name.text:find("ItemRack: Tank", 1, true), page.rows[1].name.text)
    click(page.rows[1].gear)
    click(view.setButtons[1])
    eq(c.profiles.Prot.itemrack, nil)
    click(choice(view.source, "Keystance"))
    eq(KeystanceDB.settings.gearSource, "keystance")
    eq(view.items:IsShown(), true)
    eq(view.sets:IsShown(), false)
end)

test("the editor goes back to the list if its profile is deleted", function()
    local c, ns = gearLogin()
    ns.SaveProfile("Prot")
    local view, page = gearView("Prot")
    ns.DeleteProfile("Prot")
    eq(page.list:IsShown(), true)
    eq(view:IsShown(), false)
end)

local function cursorItem(id)
    wow.cursor = { "item", id, "|cffffffff|H" .. gearString(id) .. "|h[" .. wow.itemNames[id] .. "]|h|r" }
end

test("an item only goes in a slot it can be worn in; a wrong one stays on the cursor and says where it goes", function()
    local c, ns = gearLogin()
    ns.SaveProfile("Prot")
    local view = gearView("Prot")
    cursorItem(1300) -- boots
    view.slots[7].scripts.OnReceiveDrag(view.slots[7]) -- Legs
    eq(c.profiles.Prot.gear, nil, "not saved")
    eq(wow.cursor[2], 1300, "still on the cursor")
    assert(printed():find("Stompers can't go in Legs: it goes in Feet.", 1, true), printed())
    view.slots[8].scripts.OnReceiveDrag(view.slots[8]) -- Feet
    eq(c.profiles.Prot.gear[8], gearString(1300))
    eq(wow.cursor, nil)
    -- Rings go in either ring slot; a one-hander in the off hand only with dual wield.
    cursorItem(1000)
    click(view.slots[12])
    eq(c.profiles.Prot.gear[12], gearString(1000))
    wow.dualWield = false
    cursorItem(2132)
    click(view.slots[17])
    eq(c.profiles.Prot.gear[17], nil)
    assert(printed():find("can't go in your off hand: you can't dual wield yet", 1, true), printed())
    wow.dualWield = true
    click(view.slots[17])
    eq(c.profiles.Prot.gear[17], gearString(2132))
    -- Something you can't wear at all.
    cursorItem(6948) -- Hearthstone
    click(view.slots[1])
    assert(printed():find("Hearthstone isn't something you wear.", 1, true), printed())
    wow.cursor = nil
end)

test("an item saved in the wrong slot before this check is shown in red", function()
    local c, ns = gearLogin()
    ns.SaveProfile("Prot")
    c.profiles.Prot.gear = { [7] = gearString(1300) }
    local view = gearView("Prot")
    eq(view.slots[7].wrong, true)
    eq(view.slots[7].name.text, "Stompers (wrong slot)")
end)
