-- Keystance's own gear sets: saving what's worn, and putting it back on like ItemRack does.

-- Runs the waiting timers until the swap finishes (or `max` rounds pass).
local function settle(max)
    for _ = 1, max or 50 do
        if #wow.timers == 0 then return end
        wow.runTimers()
    end
end

-- Equips and returns the result once the swap has finished.
local function equip(ns, items)
    local result
    local ok, why = ns.EquipGear(items, function(r) result = r end)
    settle()
    return result, ok, why
end

local function item(id, enchant) return "item:" .. id .. ":" .. (enchant or 0) .. ":0:0:0:0:0:0:20" end

test("saving gear keeps each worn item's own string; not before the game has the links", function()
    local _, ns = loginWithSetup(nil)
    wow.inventory[1] = 1100
    wow.inventory[11] = "item:1000:15:0:0:0:0:0:0:20"
    local items = ns.CaptureGear()
    eq(items[1], "item:1100:0:0:0:0:0:0:0:20")
    eq(items[11], "item:1000:15:0:0:0:0:0:0:20")
    eq(items[2], nil)
    eq(ns.CaptureGear({ [1] = true })[11], nil, "only the slots asked for")
    wow.linksNotReady = true
    local none, why = ns.CaptureGear()
    eq(none, nil)
    assert(why:find("loaded"), why)
    wow.linksNotReady = nil
end)

test("gear from the bags swaps into place, so a full bag is no problem", function()
    local _, ns = loginWithSetup(nil)
    wow.inventory[1] = 1101
    wow.bags[0] = { size = 1, 1100 } -- the only bag slot, full
    local result = equip(ns, { [1] = item(1100) })
    eq(wow.idOf(wow.inventory[1]), 1100)
    eq(wow.bags[0][1], 1101, "the old helm took its place in the bag")
    eq(result.moved, 1)
    eq(#result.missing, 0)
    eq(ns.GearChanges({ [1] = item(1100) }), 0)
end)

test("two copies of a ring: each goes to its own slot, and the right copy stays put", function()
    local _, ns = loginWithSetup(nil)
    wow.inventory[11] = item(1000, 0)
    wow.inventory[12] = item(1000, 15)
    equip(ns, { [11] = item(1000, 15), [12] = item(1000, 0) })
    eq(wow.inventory[11], item(1000, 15))
    eq(wow.inventory[12], item(1000, 0))
    -- Already right: nothing moves.
    local result = equip(ns, { [11] = item(1000, 15), [12] = item(1000, 0) })
    eq(result.moved, 0)
    -- Two of the same ring wanted, one worn and one in the bags: the worn one isn't taken twice.
    wow.inventory[11], wow.inventory[12] = 1001, 1000
    wow.bags[0][3] = 1000
    equip(ns, { [11] = item(1000), [12] = item(1000) })
    eq(wow.idOf(wow.inventory[11]), 1000)
    eq(wow.idOf(wow.inventory[12]), 1000)
    eq(wow.bags[0][3], 1001)
end)

test("a two-hander first puts the off hand in a free bag slot", function()
    local _, ns = loginWithSetup(nil)
    wow.inventory[16], wow.inventory[17] = 2132, 2129
    wow.bags[0] = { size = 3, [2] = 1680 }
    local result = equip(ns, { [16] = item(1680) })
    eq(wow.inventory[16], 1680)
    eq(wow.inventory[17], nil)
    local inBags = {}
    for slot = 1, 3 do if wow.bags[0][slot] then inBags[wow.bags[0][slot]] = true end end
    eq(inBags[2132], true, "the one-hander went to the bag")
    eq(inBags[2129], true, "and the shield")
    eq(next(result.failed), nil)
end)

test("a two-hander with nowhere to put the off hand says so and changes nothing", function()
    local _, ns = loginWithSetup(nil)
    wow.inventory[16], wow.inventory[17] = 2132, 2129
    wow.bags[0] = { size = 1, 1680 }
    local result = equip(ns, { [16] = item(1680) })
    eq(wow.inventory[16], 2132)
    eq(wow.inventory[17], 2129)
    assert(result.failed[16]:find("bag space"), result.failed[16])
    eq(wow.cursor, nil)
end)

test("a missing item is named and the rest still goes on", function()
    local _, ns = loginWithSetup(nil)
    wow.inventory[1] = 1101
    wow.bags[0][1] = 1100
    local result = equip(ns, { [1] = item(1100), [13] = item(1200) })
    eq(wow.idOf(wow.inventory[1]), 1100)
    eq(result.missing[1], 13)
    ns.GearReport(result)
    assert(printed():find("Lucky Charm isn't in your bags (Trinket 1)", 1, true), printed())
end)

test("an item the game won't put in that slot is reported once, not tried forever", function()
    local _, ns = loginWithSetup(nil)
    wow.bags[0][1] = 1100 -- a helm, saved as a ring (bad data)
    local result = equip(ns, { [11] = item(1100) })
    eq(wow.inventory[11], nil)
    assert(result.failed[11], "reported")
    eq(wow.cursor, nil, "the helm went back")
    eq(#wow.timers, 0, "finished")
end)

test("while the game is still moving items, the swap waits, then carries on", function()
    local _, ns = loginWithSetup(nil)
    wow.lockMoves = true
    wow.inventory[16], wow.inventory[17] = 2132, 2129
    wow.bags[0] = { size = 3, [2] = 1680 }
    local result
    ns.EquipGear({ [16] = item(1680) }, function(r) result = r end)
    eq(wow.inventory[17], nil, "the off hand went first")
    eq(wow.inventory[16], 2132)
    for _ = 1, 5 do wow.runTimers() end
    eq(wow.inventory[16], 2132, "still waiting")
    eq(result, nil)
    wow.unlock()
    wow.runTimers()
    eq(wow.inventory[16], 1680)
    wow.unlock()
    settle()
    eq(result.moved, 1)
    wow.lockMoves = false
end)

test("gives up if the game never finishes moving", function()
    local _, ns = loginWithSetup(nil)
    wow.lockMoves = true
    wow.inventory[1] = 1101
    wow.bags[0][1] = 1100
    wow.locked[1] = true
    local result = equip(ns, { [1] = item(1100) })
    assert(result and result.why, "stopped with a reason")
    wow.lockMoves, wow.locked = false, {}
end)

test("gear waits for combat to end; not while dead or holding something", function()
    local _, ns = loginWithSetup(nil)
    wow.inventory[1] = 1101
    wow.bags[0][1] = 1100
    wow.enterCombat()
    local result
    ns.EquipGear({ [1] = item(1100) }, function(r) result = r end)
    settle()
    eq(wow.idOf(wow.inventory[1]), 1101, "nothing in combat")
    eq(#wow.blocked, 0)
    wow.leaveCombat()
    settle()
    eq(wow.idOf(wow.inventory[1]), 1100)
    eq(result.moved, 1)

    wow.dead = true
    local ok, why = ns.EquipGear({ [1] = item(1101) }, function() end)
    eq(ok, false)
    assert(why:find("dead"), why)
    wow.dead = false
    wow.cursor = { "item", 6948 }
    ok, why = ns.EquipGear({ [1] = item(1101) }, function() end)
    eq(ok, false)
    assert(why:find("cursor"), why)
    wow.cursor = nil
end)

test("Keystance's own gear changes keep rules quiet for a moment", function()
    local _, ns = loginWithSetup(nil)
    wow.clock = 100
    eq(ns.GearQuiet(), false)
    wow.bags[0][1] = 1100
    equip(ns, { [1] = item(1100) })
    eq(ns.GearQuiet(), true)
    wow.clock = 102
    eq(ns.GearQuiet(), false)
    wow.clock = nil
end)

test("an item changed since it was saved (enchanted, say) still counts as the one worn", function()
    local _, ns = loginWithSetup(nil)
    wow.inventory[16] = item(2132, 15) -- enchanted since
    eq(ns.GearChanges({ [16] = item(2132) }), 0)
    local result = equip(ns, { [16] = item(2132) })
    eq(result.moved, 0)
    eq(#result.missing, 0, "not reported missing")
end)

test("two such copies in both hands don't swap with each other forever", function()
    local _, ns = loginWithSetup(nil)
    wow.inventory[16], wow.inventory[17] = item(2132, 15), item(2132, 16)
    local result = equip(ns, { [16] = item(2132), [17] = item(2132) })
    eq(result.moved, 0)
    eq(#wow.timers, 0, "finished")
end)

test("a profile saved with a two-hander and an off hand puts the two-hander on and settles", function()
    local _, ns = loginWithSetup(nil)
    wow.inventory[16], wow.inventory[17] = 2132, 2129
    wow.bags[0] = { size = 3, [2] = 1680 }
    local result = equip(ns, { [16] = item(1680), [17] = item(2129) })
    eq(wow.inventory[16], 1680)
    eq(wow.inventory[17], nil, "no off hand with a two-hander")
    eq(#wow.timers, 0, "finished, not swapping back and forth")
    eq(ns.GearChanges({ [16] = item(1680), [17] = item(2129) }), 0, "and counts as on")
end)

test("an item locked elsewhere (in a trade window) doesn't hold the swap up", function()
    local _, ns = loginWithSetup(nil)
    wow.inventory[1] = 1101
    wow.bags[0] = { size = 6, 1100, [5] = 6948 }
    wow.locked["0:5"] = true
    local result = equip(ns, { [1] = item(1100) })
    eq(result.why, nil)
    eq(wow.idOf(wow.inventory[1]), 1100)
    wow.locked = {}
end)
