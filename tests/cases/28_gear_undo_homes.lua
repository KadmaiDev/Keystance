-- Tests: Undo puts gear back where it came from. An item a profile put into an empty slot
-- goes back to the bank or bag slot it was taken from (the bank only while it's open; else
-- the bags, saying so), and a slot that was empty before is emptied again.

local function gearString(id) return "item:" .. id .. ":0:0:0:0:0:0:0:20" end

-- Vespera wearing a two-hander and nothing in her off hand.
local function twoHanderLogin()
    local c, ns = gearLogin()
    wow.inventory[16], wow.inventory[17] = 1680, nil
    wow.bags[0] = { size = 6, 1100 }
    wow.slots[1] = { kind = "spell", id = 647 }
    return c, ns
end

test("the owner's case: a one-hander and shield from the bank, then Undo at the bank, puts both back in the bank", function()
    local c, ns = twoHanderLogin()
    wow.bags[6] = { size = 4, 2132, nil, 2129 }
    ns.SaveProfile("Prot")
    ns.SetProfileGear("Prot", { [16] = gearString(2132), [17] = gearString(2129) })
    wow.openBank()
    ns.ApplyProfile("Prot")
    settleGear()
    eq(wow.idOf(wow.inventory[16]), 2132)
    eq(wow.idOf(wow.inventory[17]), 2129)
    eq(wow.idOf(wow.bags[6][1]), 1680, "the two-hander swapped into the bank")
    eq(wow.bags[6][3], nil, "the shield's bank slot is empty now")
    eq(c.lastChange.gear[17], false, "the off hand was empty before")
    ns.Undo()
    settleGear()
    eq(wow.idOf(wow.inventory[16]), 1680, "the two-hander is back on")
    eq(wow.inventory[17], nil)
    eq(wow.idOf(wow.bags[6][1]), 2132, "the one-hander is back in the bank")
    eq(wow.idOf(wow.bags[6][3]), 2129, "and the shield, in the very slot it came from")
    for slot = 1, wow.bags[0].size do
        assert(wow.idOf(wow.bags[0][slot]) ~= 2129, "not in the bags")
    end
end)

test("with the bank closed by then, the bank's item goes to the bags and Undo says so", function()
    local c, ns = twoHanderLogin()
    wow.bags[0] = { size = 6, 1100, 2132 }
    wow.bags[6] = { size = 4, 2129 }
    ns.SaveProfile("Prot")
    ns.SetProfileGear("Prot", { [16] = gearString(2132), [17] = gearString(2129) })
    wow.openBank()
    ns.ApplyProfile("Prot")
    settleGear()
    wow.closeBank()
    ns.Undo()
    settleGear()
    eq(wow.idOf(wow.inventory[16]), 1680)
    eq(wow.inventory[17], nil)
    local inBags = false
    for slot = 1, wow.bags[0].size do
        if wow.idOf(wow.bags[0][slot]) == 2129 then inBags = true end
    end
    eq(inBags, true)
    assert(printed():find("Large Round Shield came from your bank; it's in your bags now.", 1, true), printed())
end)

test("a slot that was empty before is emptied by Undo, the item back in the bag slot it came from", function()
    local c, ns = gearLogin()
    wow.inventory[1] = nil
    wow.bags[0] = { size = 6, 1680, nil, nil, 1100 }
    wow.slots[1] = { kind = "spell", id = 647 }
    ns.SaveProfile("Prot")
    ns.SetProfileGear("Prot", { [1] = gearString(1100) })
    ns.ApplyProfile("Prot")
    settleGear()
    eq(wow.idOf(wow.inventory[1]), 1100)
    eq(c.lastChange.gear[1], false)
    ns.Undo()
    settleGear()
    eq(wow.inventory[1], nil, "no helm, as before")
    eq(wow.idOf(wow.bags[0][4]), 1100, "back in its own bag slot")
    -- A second Undo puts it on again, and a third takes it off again.
    ns.Undo()
    settleGear()
    eq(wow.idOf(wow.inventory[1]), 1100)
    ns.Undo()
    settleGear()
    eq(wow.inventory[1], nil, "the redo's record knew the slot was empty too")
    eq(wow.idOf(wow.bags[0][4]), 1100)
end)

test("taking an item off with no room in the bags leaves it on and says why", function()
    local c, ns = gearLogin()
    wow.inventory[1] = nil
    wow.bags[0] = { size = 1, 1100 }
    wow.slots[1] = { kind = "spell", id = 647 }
    ns.SaveProfile("Prot")
    ns.SetProfileGear("Prot", { [1] = gearString(1100) })
    ns.ApplyProfile("Prot")
    settleGear()
    wow.bags[0][1] = 1300 -- the bags filled up meanwhile
    ns.Undo()
    settleGear()
    eq(wow.idOf(wow.inventory[1]), 1100, "still on")
    assert(printed():find("Gear: Head: no bag space to take it off.", 1, true), printed())
end)

test("Take what I'm wearing saves worn slots only, never 'empty'", function()
    local c, ns = gearLogin()
    wow.inventory[1] = nil
    local items = ns.CaptureGear()
    eq(items[1], nil)
    for _, v in pairs(items) do eq(type(v), "string") end
end)
