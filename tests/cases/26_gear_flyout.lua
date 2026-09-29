-- Tests: the gear editor's flyout (what you have that fits a slot: worn, in the bags, and in
-- the bank while it's open), the gear engine taking items from an open bank, and the red
-- highlight on a slot an item held on the cursor can't go in.

local function gearString(id) return "item:" .. id .. ":0:0:0:0:0:0:0:20" end

local function cursorItem(id)
    wow.cursor = { "item", id, "|cffffffff|H" .. gearString(id) .. "|h[" .. wow.itemNames[id] .. "]|h|r" }
end

-- The items the open flyout shows, as IDs ("1101,1100"), a bank one marked "1102 bank".
local function flyoutItems(view)
    local out = {}
    for _, cell in ipairs(view.flyout.cells) do
        if cell:IsShown() then out[#out + 1] = wow.idOf(cell.item) .. (cell.bank and " bank" or "") end
    end
    return table.concat(out, ",")
end

local function colour(t) return table.concat(t.vertex or { "none" }, ",") end

-- A helm in the first bank tab, which has 4 slots.
local function bankHelm()
    wow.itemNames[1102], wow.equipLoc[1102] = "Bank Helm", "INVTYPE_HEAD"
    wow.bags[6] = { size = 4, 1102 }
end

test("clicking a slot flies out what fits it: worn first, then the bags; picking one saves it", function()
    local c, ns = gearLogin()
    ns.SaveProfile("Prot")
    local view = gearView("Prot")
    click(view.slots[1])
    eq(view.flyout:IsShown(), true)
    eq(view.flyout.slot, 1)
    eq(flyoutItems(view), "1101,1100", "the worn Coif, then the Lionheart Helm from the bags")
    eq(view.flyout.cells[1].worn, true)
    eq(c.profiles.Prot.gear, nil, "opening it changes nothing")
    click(view.flyout.cells[2])
    eq(c.profiles.Prot.gear[1], gearString(1100))
    eq(view.flyout:IsShown(), false, "closed once picked")
    eq(view.slots[1].name.text, "Lionheart Helm")
end)

test("the flyout lists only what can go in that slot, each item once", function()
    local c, ns = gearLogin()
    ns.SaveProfile("Prot")
    wow.bags[0] = { size = 6, 1680, 1100, 1100, 1300 }
    local view = gearView("Prot")
    click(view.slots[1])
    eq(flyoutItems(view), "1101,1100", "two identical helms show once; no boots or weapons")
    click(view.slots[17])
    eq(view.flyout.slot, 17, "another slot moves the flyout")
    eq(flyoutItems(view), "2129,2132", "the worn shield, then the one-hander from the main hand; no two-hander")
    wow.dualWield = false
    click(view.slots[17])
    eq(view.flyout:IsShown(), false, "the same slot again closes it")
    click(view.slots[17])
    eq(flyoutItems(view), "2129", "without dual wield, no one-hander in the off hand")
    click(view.back)
    eq(view.flyout:IsShown(), false, "closes with the editor")
end)

test("a slot nothing fits says so, and says the bank isn't counted while it's closed", function()
    local c, ns = gearLogin()
    ns.SaveProfile("Prot")
    local view = gearView("Prot")
    click(view.slots[19]) -- tabard
    eq(flyoutItems(view), "")
    assert(view.flyout.note.text:find("Nothing you have fits here.", 1, true), view.flyout.note.text)
    assert(view.flyout.note.text:find("Open your bank", 1, true), view.flyout.note.text)
end)

test("with the bank open, its gear is in the flyout too, marked as the bank's", function()
    local c, ns = gearLogin()
    ns.SaveProfile("Prot")
    bankHelm()
    local view = gearView("Prot")
    click(view.slots[1])
    eq(flyoutItems(view), "1101,1100", "bank closed: its items can't be read")
    wow.openBank()
    wow.runTimers()
    eq(flyoutItems(view), "1101,1100,1102 bank", "the open flyout follows the bank opening")
    assert(not view.flyout.note.text:find("Open your bank", 1, true), view.flyout.note.text)
    click(view.flyout.cells[3])
    eq(c.profiles.Prot.gear[1], gearString(1102))
    wow.closeBank()
    wow.runTimers()
    click(view.slots[1])
    eq(flyoutItems(view), "1101,1100", "bank closed again")
end)

test("the gear engine takes an item from the bank while it's open, and from the bags first", function()
    local c, ns = gearLogin()
    bankHelm()
    ns.SaveProfile("Prot")
    ns.SetProfileGear("Prot", { [1] = gearString(1102) })
    ns.ApplyProfile("Prot")
    settleGear()
    eq(wow.inventory[1], 1101, "bank closed: the helm can't be reached")
    assert(printed():find("Bank Helm", 1, true), printed())
    wow.openBank()
    ns.ApplyProfile("Prot")
    settleGear()
    eq(wow.idOf(wow.inventory[1]), 1102, "put on from the bank")
    eq(wow.idOf(wow.bags[6][1]), 1101, "the Coif took its place, as the game swaps them")
    -- The same helm in the bags and the bank: the bags' one is used.
    wow.inventory[1], wow.bags[6][1] = 1101, 1102
    wow.bags[0][3] = 1102
    ns.SetProfileGear("Prot", { [1] = gearString(1102) })
    ns.ApplyProfile("Prot")
    settleGear()
    eq(wow.idOf(wow.inventory[1]), 1102)
    eq(wow.idOf(wow.bags[0][3]), 1101, "swapped with the bags' copy")
    eq(wow.idOf(wow.bags[6][1]), 1102, "the bank's copy stays in the bank")
    -- Neither is the saved copy (both enchanted since): still the bags' one.
    wow.inventory[1] = 1101
    wow.bags[0][3], wow.bags[6][1] = "item:1102:5:0:0:0:0:0:0:20", "item:1102:7:0:0:0:0:0:0:20"
    ns.ApplyProfile("Prot")
    settleGear()
    eq(wow.inventory[1], "item:1102:5:0:0:0:0:0:0:20", "the bags' copy")
    eq(wow.bags[6][1], "item:1102:7:0:0:0:0:0:0:20", "the bank's stays")
end)

test("an item held over a slot it can't go in highlights red and says why; one that fits, normally", function()
    local c, ns = gearLogin()
    ns.SaveProfile("Prot")
    local view = gearView("Prot")
    local legs, feet = view.slots[7], view.slots[8]
    legs.scripts.OnEnter(legs)
    eq(colour(legs.hl), "1,1,1", "nothing held: the usual highlight")
    cursorItem(1300) -- boots
    legs.scripts.OnEnter(legs)
    eq(colour(legs.hl), "1,0.1,0.1", "red over Legs")
    local lines = {}
    for _, line in ipairs(GameTooltip.lines) do lines[#lines + 1] = line[1] end
    assert(table.concat(lines, "\n"):find("Stompers can't go in Legs: it goes in Feet.", 1, true), table.concat(lines, "\n"))
    feet.scripts.OnEnter(feet)
    eq(colour(feet.hl), "1,1,1", "Feet: the usual highlight")
    wow.cursor = nil
    legs.scripts.OnEnter(legs)
    eq(colour(legs.hl), "1,1,1", "back to normal once the item is put down")
end)
