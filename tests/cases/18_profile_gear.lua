-- Tests: profiles that carry gear (Keystance's own items, or an ItemRack set).
---------------------------------------------------------------------------
-- A stand-in for ItemRack 4.50: sets per character in ItemRackUser.Sets, EquipSet (which
-- here puts the set's items straight on), IsSetEquipped and EndSetSwap. `sets` is
-- { [name] = { [slot] = itemID } }.
function fakeItemRack(sets)
    ItemRackUser = { Sets = { ["~Unequip"] = { equip = {} }, ["~CombatQueue"] = { equip = {} } } }
    for name, equip in pairs(sets) do ItemRackUser.Sets[name] = { equip = equip, icon = 132341 } end
    ItemRack = { calls = {} }
    function ItemRack.EquipSet(name)
        ItemRack.calls[#ItemRack.calls + 1] = name
        if ItemRack.broken then error("ItemRack broke") end
        for slot, id in pairs(ItemRackUser.Sets[name].equip) do
            -- Swapped in from the bags, the worn item taking its place.
            for i = 1, wow.bags[0].size do
                if wow.idOf(wow.bags[0][i]) == id then
                    wow.bags[0][i] = wow.inventory[slot]
                    wow.inventory[slot] = id
                    wow.fire("PLAYER_EQUIPMENT_CHANGED", slot, false)
                    break
                end
            end
        end
        ItemRackUser.CurrentSet = name
        ItemRack.EndSetSwap(name)
    end
    function ItemRack.IsSetEquipped(name) return ItemRackUser.CurrentSet == name end
    function ItemRack.EndSetSwap() end
end

-- Vespera logged in (ItemRack loaded first when `sets` is given), on her own keybinds,
-- wearing a one-hander and a shield, with a two-hander and a helm in her bags.
function gearLogin(sets)
    local ns = wow.load(FILES)
    paladinSetup()
    if sets then fakeItemRack(sets) end
    wow.login(nil)
    wow.fire("PLAYER_ENTERING_WORLD", true, false)
    wow.runTimers()
    table.insert(wow.spellbook[1].spells, { 264, "Blessings", flyout = true })
    wow.itemCount[6948] = 1
    wow.bindingSet = 2
    wow.inventory[16], wow.inventory[17], wow.inventory[1] = 2132, 2129, 1101
    wow.bags[0] = { size = 6, 1680, 1100 }
    return KeystanceDB.chars["Vespera Ashward"], ns
end

function settleGear()
    for _ = 1, 50 do
        if #wow.timers == 0 then return end
        wow.runTimers()
    end
end

local function gearString(id) return "item:" .. id .. ":0:0:0:0:0:0:0:20" end

test("a profile's own gear goes on with its bars, and Undo puts the old gear back", function()
    local c, ns = gearLogin()
    wow.slots[1] = { kind = "spell", id = 647 }
    ns.SaveProfile("Ret")
    ns.SetProfileGear("Ret", { [16] = gearString(1680), [1] = gearString(1100) })
    wow.slots[1] = { kind = "spell", id = 1866 }
    ns.ApplyProfile("Ret")
    settleGear()
    eq(wow.inventory[16], 1680, "the two-hander")
    eq(wow.inventory[17], nil, "the shield went to the bags")
    eq(wow.idOf(wow.inventory[1]), 1100)
    eq(slotId(1), 647, "and the bars")
    assert(printed():find("Gear: 2 items put on.", 1, true), printed())
    eq(c.lastChange.gear[16], gearString(2132), "the gear it replaced, for Undo")
    eq(c.lastChange.gear[1], gearString(1101))
    eq(c.lastChange.gear[17], gearString(2129), "the shield the two-hander displaced, recorded too")

    ns.Undo()
    settleGear()
    eq(wow.inventory[16], 2132)
    eq(wow.idOf(wow.inventory[17]), 2129, "and the shield back on")
    eq(wow.idOf(wow.inventory[1]), 1101)
    eq(slotId(1), 1866)
    -- A second Undo puts the profile's gear on again.
    ns.Undo()
    settleGear()
    eq(wow.inventory[16], 1680)
    eq(slotId(1), 647)
end)

test("gear alone counts as a change: Apply asks, and Undo can take it back", function()
    local c, ns = gearLogin()
    ns.SaveProfile("Helm")
    ns.SetProfileGear("Helm", { [1] = gearString(1100) })
    ns.ConfirmApply("Helm")
    eq(wow.popup.which, "KEYSTANCE_APPLY")
    eq(wow.popup.text, "Helm")
    ns.ApplyProfile("Helm", nil, true)
    settleGear()
    eq(wow.idOf(wow.inventory[1]), 1100)
    eq(ns.UndoLabel(), "applying Helm")
    wow.popup = nil
    wow.printed = {}
    ns.ConfirmApply("Helm")
    eq(wow.popup, nil)
    assert(printed():find("Helm is already in place.", 1, true), printed())
end)

test("the apply question names the gear with the slots and keys", function()
    local c, ns = gearLogin()
    ns.SaveProfile("Ret")
    ns.SetProfileGear("Ret", { [1] = gearString(1100) })
    wow.slots[1] = { kind = "spell", id = 647 }
    local shown
    StaticPopup_Show = function(which, text1, text2) shown = text2 end
    ns.ConfirmApply("Ret")
    eq(shown, "1 slots and your gear")
end)

test("with ItemRack as the gear source, Update keeps a profile's gear; Copy copies it", function()
    local c, ns = gearLogin({ Dps = { [16] = 1680 } })
    ns.SaveProfile("Ret")
    ns.SetProfileGear("Ret", { [1] = gearString(1100) })
    ns.SetProfileItemRack("Ret", "Dps")
    eq(ns.UpdateSaves("Ret"), "bars and keys")
    ns.SaveProfile("Ret", true)
    eq(c.profiles.Ret.gear[1], gearString(1100), "not the helm worn now")
    eq(c.profiles.Ret.itemrack, "Dps")
    ns.DuplicateProfile("Ret", "Ret 2")
    eq(c.profiles["Ret 2"].gear[1], gearString(1100))
    ns.SetProfileGear("Ret", nil)
    eq(c.profiles.Ret.gear, nil)
    eq(c.profiles["Ret 2"].gear[1], gearString(1100), "the copy is its own")
end)

test("with Keystance's own gear, Update saves the gear worn now in the profile's slots", function()
    local c, ns = gearLogin()
    ns.SaveProfile("Ret")
    ns.SetProfileGear("Ret", { [16] = gearString(1680), [1] = gearString(1100) })
    ns.SetProfileItemRack("Ret", "Dps")
    local shown
    StaticPopup_Show = function(which, text1, text2) shown = text2 end
    ns.ConfirmUpdate("Ret")
    eq(shown, "bars, keys and gear", "the question says the gear is saved too")
    -- Worn now: one-hander 2132, shield 2129, helm 1101; a ring the profile has no slot for.
    wow.inventory[11] = 1000
    ns.SaveProfile("Ret", true)
    local gear = c.profiles.Ret.gear
    eq(gear[16], gearString(2132), "the main hand worn now")
    eq(gear[17], gearString(2129), "and the off hand that goes with it")
    eq(gear[1], gearString(1101))
    eq(gear[11], nil, "a slot the profile left alone stays alone")
    eq(c.profiles.Ret.itemrack, "Dps", "its ItemRack set is kept for when ItemRack is the source")

    -- A slot worn empty now drops out.
    wow.inventory[1] = nil
    ns.SaveProfile("Ret", true)
    eq(c.profiles.Ret.gear[1], nil)
    eq(c.profiles.Ret.gear[16], gearString(2132))
end)

test("Update doesn't give gear to a profile without any, and keeps the old gear if items haven't loaded", function()
    local c, ns = gearLogin()
    ns.SaveProfile("Ret")
    eq(ns.UpdateSaves("Ret"), "bars and keys")
    ns.SaveProfile("Ret", true)
    eq(c.profiles.Ret.gear, nil, "no gear: stays without")

    ns.SetProfileGear("Ret", { [1] = gearString(1100) })
    wow.linksNotReady = true
    wow.printed = {}
    eq(ns.SaveProfile("Ret", true), "Ret", "the bars still update")
    wow.linksNotReady = nil
    eq(c.profiles.Ret.gear[1], gearString(1100), "the old gear stays")
    assert(printed():find("Gear not saved", 1, true), printed())
end)

test("a rule switching profiles leaves gear alone: the player just chose it", function()
    local c, ns = gearLogin()
    ns.SaveProfile("Ret")
    wow.slots[1] = { kind = "spell", id = 647 }
    ns.SaveProfile("Prot")
    ns.SetProfileGear("Prot", { [1] = gearString(1100) })
    wow.slots[1] = { kind = "spell", id = 1866 }
    c.active = "Ret"
    ns.AddRule({ when = "twohand", profile = "Prot" })
    wow.inventory[16] = 1680
    wow.fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
    wow.runTimers()
    settleGear()
    eq(c.active, "Prot")
    eq(slotId(1), 647)
    eq(wow.idOf(wow.inventory[1]), 1101, "the helm stays as the player has it")
end)

test("Keystance's own gear changes don't set off rules", function()
    local c, ns = gearLogin()
    wow.clock = 50
    ns.SaveProfile("Ret")
    ns.SetProfileGear("Ret", { [16] = gearString(1680) })
    wow.slots[1] = { kind = "spell", id = 647 }
    ns.SaveProfile("Prot")
    ns.AddRule({ when = "twohand", profile = "Prot" })
    ns.ApplyProfile("Ret")
    settleGear()
    eq(wow.inventory[16], 1680)
    eq(c.active, "Ret", "the two-hander Ret put on didn't switch to Prot")
    wow.clock = nil
end)

test("in combat, gear and bars both wait for combat to end", function()
    local c, ns = gearLogin()
    ns.SaveProfile("Helm")
    ns.SetProfileGear("Helm", { [1] = gearString(1100) })
    wow.enterCombat()
    ns.ApplyProfile("Helm")
    settleGear()
    eq(wow.idOf(wow.inventory[1]), 1101)
    eq(#wow.blocked, 0)
    wow.leaveCombat()
    settleGear()
    eq(wow.idOf(wow.inventory[1]), 1100)
end)

test("with ItemRack loaded, a profile's gear is its ItemRack set", function()
    local c, ns = gearLogin({ Tank = { [1] = 1100 }, Dps = { [16] = 1680 } })
    eq(ns.GearSource(), "itemrack")
    eq(table.concat(ns.ItemRackSets(), ","), "Dps,Tank", "its own ~ sets are left out")
    eq(ns.ItemRackSetIcon("Tank"), 132341)
    ns.SaveProfile("Prot")
    ns.SetProfileItemRack("Prot", "Tank")
    ns.SetProfileGear("Prot", { [16] = gearString(1680) }) -- Keystance's own, not used now
    ns.ApplyProfile("Prot")
    settleGear()
    eq(table.concat(ItemRack.calls, ","), "Tank")
    eq(wow.idOf(wow.inventory[1]), 1100)
    eq(wow.inventory[16], 2132, "Keystance's own gear for it isn't used")
    assert(printed():find("Gear: ItemRack is putting on Tank.", 1, true), printed())
    eq(c.lastChange.gear[1], gearString(1101), "everything worn before, for Undo")
    -- Already on: nothing to do.
    eq(ns.ProfileGearChanges(c.profiles.Prot), 0)
    -- Undo puts back what was worn, with Keystance's own swapping.
    ns.Undo()
    settleGear()
    eq(wow.idOf(wow.inventory[1]), 1101)
end)

test("the player can choose Keystance's own gear with ItemRack loaded", function()
    local c, ns = gearLogin({ Tank = { [1] = 1100 } })
    KeystanceDB.settings.gearSource = "keystance"
    eq(ns.GearSource(), "keystance")
    ns.SaveProfile("Prot")
    ns.SetProfileItemRack("Prot", "Tank")
    ns.SetProfileGear("Prot", { [16] = gearString(1680) })
    ns.ApplyProfile("Prot")
    settleGear()
    eq(#ItemRack.calls, 0)
    eq(wow.inventory[16], 1680)
end)

test("without ItemRack, choosing it falls back to Keystance's own gear", function()
    local c, ns = gearLogin()
    KeystanceDB.settings.gearSource = "itemrack"
    eq(ns.GearSource(), "keystance")
    eq(#ns.ItemRackSets(), 0)
end)

test("an ItemRack that fails still lets the bars change, and says so", function()
    local c, ns = gearLogin({ Tank = { [1] = 1100 } })
    ItemRack.broken = true
    wow.slots[1] = { kind = "spell", id = 647 }
    ns.SaveProfile("Prot")
    ns.SetProfileItemRack("Prot", "Tank")
    wow.slots[1] = { kind = "spell", id = 1866 }
    ns.ApplyProfile("Prot")
    eq(slotId(1), 647)
    assert(printed():find("ItemRack couldn't put on Tank.", 1, true), printed())
    eq(#wow.errors, 0)
end)

test("a set equipped through ItemRack by Keystance doesn't set off rules", function()
    local c, ns = gearLogin({ Dps = { [16] = 1680 } })
    wow.clock = 10
    ns.SaveProfile("Ret")
    ns.SetProfileItemRack("Ret", "Dps")
    wow.slots[1] = { kind = "spell", id = 647 }
    ns.SaveProfile("Prot")
    ns.AddRule({ when = "twohand", profile = "Prot" })
    ns.ApplyProfile("Ret")
    wow.runTimers()
    eq(c.active, "Ret")
    wow.clock = nil
end)

test("a rule can watch an ItemRack set: equipping it in ItemRack switches the profile", function()
    local c, ns = gearLogin({ Tank = { [1] = 1100 } })
    ns.SaveProfile("Ret")
    wow.slots[1] = { kind = "spell", id = 647 }
    ns.SaveProfile("Prot")
    wow.slots[1] = { kind = "spell", id = 1866 }
    c.active = "Ret"
    local page = rulesPage()
    click(choice(page.when, "a set"))
    eq(page.set.text, "Set: Tank (ItemRack)")
    click(page.add)
    eq(c.rules[1].set, "Tank")
    eq(c.rules[1].from, "itemrack")
    eq(ns.RuleText(c.rules[1]), "When the ItemRack set Tank is equipped, use Prot.")
    ItemRack.EquipSet("Tank") -- the player, in ItemRack
    wow.runTimers()
    eq(c.active, "Prot")
    eq(slotId(1), 647)
end)

test("ItemRack finishing a set checks the rules again, after its slower swaps", function()
    local c, ns = gearLogin({ Tank = { [1] = 1100 } })
    ns.SaveProfile("Ret")
    wow.slots[1] = { kind = "spell", id = 647 }
    ns.SaveProfile("Prot")
    c.active = "Ret"
    ns.AddRule({ when = "set", set = "Tank", from = "itemrack", profile = "Prot" })
    ItemRackUser.CurrentSet = "Tank" -- already on, with no gear event of its own
    ItemRack.EndSetSwap("Tank")
    wow.runTimers()
    eq(c.active, "Prot")
end)

test("a set ItemRack never finishes counts as Keystance's only until its deadline", function()
    local c, ns = gearLogin({ Tank = { [1] = 1100 } })
    wow.clock = 100
    ItemRack.EquipSet = function() end -- deferred, and never done
    eq(ns.ItemRackEquip("Tank"), true)
    eq(ns.GearBusy(), true)
    wow.clock = 111
    eq(ns.GearBusy(), false, "the player's own ItemRack swaps count again")
    wow.clock = nil
end)

test("gear stays as it is when the game hasn't loaded item links yet, so Undo can't lose it", function()
    local c, ns = gearLogin()
    ns.SaveProfile("Ret")
    ns.SetProfileGear("Ret", { [1] = gearString(1100) })
    wow.slots[1] = { kind = "spell", id = 647 }
    wow.linksNotReady = true
    ns.ApplyProfile("Ret")
    settleGear()
    wow.linksNotReady = nil
    eq(wow.idOf(wow.inventory[1]), 1101, "gear unchanged")
    assert(printed():find("Gear not changed", 1, true), printed())
    eq(slotId(1), 1866, "the bars still change")
end)

test("a rule's switch leaves gear alone even through the shared-keybinds question", function()
    local c, ns = gearLogin()
    wow.bindingSet = 1
    ns.SaveProfile("Ret")
    wow.slots[1] = { kind = "spell", id = 647 }
    wow.bindings.F7 = "ACTIONBUTTON2"
    ns.SaveProfile("Prot")
    ns.SetProfileGear("Prot", { [1] = gearString(1100) })
    wow.bindings.F7 = nil
    wow.slots[1] = { kind = "spell", id = 1866 }
    c.active = "Ret"
    ns.AddRule({ when = "twohand", profile = "Prot" })
    wow.inventory[16] = 1680
    wow.fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
    wow.runTimers()
    eq(wow.popup.which, "KEYSTANCE_SHARED_KEYS")
    StaticPopupDialogs.KEYSTANCE_SHARED_KEYS.OnAccept(nil, wow.popup.data)
    settleGear()
    eq(c.active, "Prot")
    eq(wow.idOf(wow.inventory[1]), 1101, "the helm stays as the player has it")
end)
