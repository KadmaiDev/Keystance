-- Tests: a profile's gear that isn't on the character (not worn, not in the bags) is flagged
-- in the gear editor and on the profile's row, saying "in your bank" when Keystance saw it
-- there on the last bank visit; applying says the same.

local function gearString(id) return "item:" .. id .. ":0:0:0:0:0:0:0:20" end

-- A helm and a ring in the first bank tab (4 slots).
local function bankItems()
    wow.itemNames[1102], wow.equipLoc[1102] = "Bank Helm", "INVTYPE_HEAD"
    wow.bags[6] = { size = 4, 1102, 1001 }
end

local function amber(fs) return fs.color and fs.color[1] == 1 and fs.color[2] > 0.5 and fs.color[3] < 0.5 end

local function rowFor(page, name)
    for _, row in ipairs(page.rows) do
        if row.profile == name and row:IsShown() then return row end
    end
end

test("gear that isn't worn or in the bags is flagged: 'Not found' before a bank visit", function()
    local c, ns = gearLogin()
    bankItems()
    ns.SaveProfile("Prot")
    ns.SetProfileGear("Prot", { [1] = gearString(1102), [16] = gearString(2132), [8] = gearString(1300) })
    local status = ns.GearStatus(c.profiles.Prot.gear)
    eq(status[1], "missing", "the bank's helm: never seen there, so just not found")
    eq(status[16], nil, "worn")
    eq(status[8], "missing", "nowhere at all")
    local view, page = gearView("Prot")
    eq(amber(view.slots[1].name), true)
    eq(view.slots[1].note.text, "Not found")
    eq(view.slots[1].note:IsShown(), true)
    eq(view.slots[16].note:IsShown(), false, "worn: no note")
    click(view.back)
    local row = rowFor(page, "Prot")
    assert(row.name.text:find("3 items · 2 missing", 1, true), row.name.text)
end)

test("after a bank visit, what was there says 'In your bank', here and when applying", function()
    local c, ns = gearLogin()
    bankItems()
    ns.SaveProfile("Prot")
    ns.SetProfileGear("Prot", { [1] = gearString(1102), [11] = gearString(1001) })
    wow.openBank()
    eq(ns.GearStatus(c.profiles.Prot.gear)[1], nil, "bank open: it can be taken from there, so nothing to flag")
    wow.closeBank()
    eq(c.bankSeen ~= nil, true, "what's in the bank is remembered for the character")
    local status = ns.GearStatus(c.profiles.Prot.gear)
    eq(status[1], "bank")
    eq(status[11], "bank")
    local view, page = gearView("Prot")
    eq(view.slots[1].note.text, "In your bank")
    click(view.back)
    assert(rowFor(page, "Prot").name.text:find("2 items · 2 in bank", 1, true), rowFor(page, "Prot").name.text)
    ns.ApplyProfile("Prot")
    settleGear()
    assert(printed():find("Gear: Bank Helm is in your bank (Head).", 1, true), printed())
end)

test("the bank memory follows items taken out while it's open, and is kept across logins", function()
    local c, ns = gearLogin()
    bankItems()
    ns.SaveProfile("Prot")
    ns.SetProfileGear("Prot", { [1] = gearString(1102) })
    wow.openBank()
    -- The helm goes from the bank to the bags.
    wow.bags[0][4], wow.bags[6][1] = 1102, nil
    wow.fire("BAG_UPDATE_DELAYED")
    wow.closeBank()
    eq(ns.GearStatus(c.profiles.Prot.gear)[1], nil, "in the bags now")
    wow.bags[0][4] = nil -- sold, say
    eq(ns.GearStatus(c.profiles.Prot.gear)[1], "missing", "not remembered as in the bank any more")
    -- The saved memory survives a reload.
    wow.bags[6][1] = 1102
    wow.openBank()
    wow.closeBank()
    local saved = KeystanceDB
    wow.load(FILES)
    wow.login(saved)
    eq(ns.GearStatus ~= nil, true)
    eq(KeystanceDB.chars["Vespera Ashward"].bankSeen ~= nil, true)
end)

test("two identical rings saved with one owned: one is flagged", function()
    local c, ns = gearLogin()
    wow.bags[0][3] = 1000
    ns.SaveProfile("Prot")
    ns.SetProfileGear("Prot", { [11] = gearString(1000), [12] = gearString(1000) })
    local status = ns.GearStatus(c.profiles.Prot.gear)
    eq((status[11] and 1 or 0) + (status[12] and 1 or 0), 1)
end)

test("nothing is flagged while the game is still loading item details", function()
    local c, ns = gearLogin()
    ns.SaveProfile("Prot")
    ns.SetProfileGear("Prot", { [1] = gearString(1101), [8] = gearString(1300) })
    wow.linksNotReady = true
    eq(ns.GearStatus(c.profiles.Prot.gear), nil, "unknown yet")
    local view = gearView("Prot")
    eq(view.slots[8].note:IsShown(), false)
    wow.linksNotReady = nil
end)

test("a soft sound plays once when some of a profile's gear can't go on, and not when it all does", function()
    local c, ns = gearLogin()
    ns.SaveProfile("Prot")
    ns.SetProfileGear("Prot", { [1] = gearString(1100) })
    wow.sounds = {}
    ns.ApplyProfile("Prot")
    settleGear()
    eq(#wow.sounds, 0, "the helm was in the bags")
    ns.SetProfileGear("Prot", { [8] = gearString(1300), [11] = gearString(1000), [1] = gearString(1101) })
    ns.ApplyProfile("Prot")
    settleGear()
    eq(#wow.sounds, 1, "two items missing: one sound")
    eq(wow.sounds[1], 846)
    -- A client without that sound stays silent (no error).
    SOUNDKIT.IG_QUEST_LOG_ABANDON_QUEST = nil
    ns.ApplyProfile("Prot")
    settleGear()
    eq(#wow.sounds, 1)
end)
