-- Tests: the bank panel. A Keystance button on the bank window opens a panel listing the
-- profiles with Keystance's own gear; Get moves a profile's gear from the bank to the bags,
-- Put stores it in the bank, keeping what another profile uses and what's worn.

local function gearString(id) return "item:" .. id .. ":0:0:0:0:0:0:0:20" end

-- Blizzard's bank window, as the game makes it on the first visit.
local function blizzardBank()
    CreateFrame("Frame", "BankFrame", UIParent)
    CreateFrame("EditBox", "BankItemSearchBox", BankFrame)
end

-- Vespera with a Prot profile (helm and shield) and a Ret profile (two-hander and the same
-- helm), wearing a one-hander and a shield; bank tab 1 has 6 slots.
local function bankLogin()
    local c, ns = gearLogin()
    wow.inventory[1] = nil
    wow.bags[0] = { size = 6, 1680, 1100 }
    wow.bags[6] = { size = 6 }
    ns.SaveProfile("Prot")
    ns.SetProfileGear("Prot", { [1] = gearString(1100), [17] = gearString(2129) })
    ns.SaveProfile("Ret")
    ns.SetProfileGear("Ret", { [16] = gearString(1680), [1] = gearString(1100) })
    blizzardBank()
    return c, ns
end

local function bagsHold(id)
    for slot = 1, wow.bags[0].size do
        if wow.idOf(wow.bags[0][slot]) == id then return true end
    end
    return false
end

local function bankHolds(id)
    for slot = 1, wow.bags[6].size do
        if wow.idOf(wow.bags[6][slot]) == id then return true end
    end
    return false
end

local function openPanel(ns)
    wow.openBank()
    wow.runTimers()
    local button = ns.BankButtons().BankFrame
    click(button)
    return KeystanceBankPanel, button
end

local function rowFor(panel, name)
    for _, row in ipairs(panel.rows) do
        if row:IsShown() and row.profile == name then return row end
    end
end

test("the bank window gets a Keystance button that opens the panel beside it", function()
    local c, ns = bankLogin()
    local panel, button = openPanel(ns)
    eq(button.parent, BankFrame)
    eq(panel:IsShown(), true)
    eq(panel.point[2], BankFrame, "docked to the bank")
    eq(rowFor(panel, "Prot") ~= nil, true)
    eq(rowFor(panel, "Ret") ~= nil, true)
    click(button)
    eq(panel:IsShown(), false, "the button toggles it")
    click(button)
    eq(panel.events.BAG_UPDATE_DELAYED, true, "follows the bags while open")
    wow.closeBank()
    eq(panel:IsShown(), false, "closes with the bank")
    eq(panel.events.BAG_UPDATE_DELAYED, nil, "and stops listening")
end)

test("next to Alts Forever's own bank button when it's loaded, not on top of it", function()
    local c, ns = bankLogin()
    wow.loadedAddons = { AltsForever = true }
    wow.openBank()
    wow.runTimers()
    local x = ns.BankButtons().BankFrame.point[4]
    eq(x < -30, true, "left of Alts Forever's")
end)

test("Put stores a profile's gear in the bank, keeping shared and worn items; Get brings it back", function()
    local c, ns = bankLogin()
    local panel = openPanel(ns)
    -- Ret: the two-hander is Ret's alone; the helm is Prot's too.
    local ret = rowFor(panel, "Ret")
    assert(ret.status.text:find("2 in bags", 1, true), ret.status.text)
    click(ret.put)
    settleGear()
    eq(bankHolds(1680), true, "the two-hander went in the bank")
    eq(bagsHold(1100), true, "the shared helm stayed in the bags")
    assert(printed():find("Ret: 1 item put in the bank.", 1, true), printed())
    assert(printed():find("1 stayed in your bags: another profile uses it.", 1, true), printed())
    ret = rowFor(panel, "Ret")
    assert(ret.status.text:find("1 in bank", 1, true), ret.status.text)
    -- Prot: the shield is worn, so it stays on.
    click(rowFor(panel, "Prot").put)
    settleGear()
    eq(wow.idOf(wow.inventory[17]), 2129)
    -- Get brings Ret's back.
    click(rowFor(panel, "Ret").get)
    settleGear()
    eq(bagsHold(1680), true)
    eq(bankHolds(1680), false)
    assert(printed():find("Ret: 1 item moved to your bags.", 1, true), printed())
end)

test("a full bank or full bags stops the move and says how many didn't fit", function()
    local c, ns = bankLogin()
    wow.bags[6] = { size = 1, 1300 } -- full
    local panel = openPanel(ns)
    click(rowFor(panel, "Ret").put)
    settleGear()
    eq(bagsHold(1680), true)
    assert(printed():find("1 didn't fit: your bank is full.", 1, true), printed())
    wow.bags[6] = { size = 2, 1680 }
    wow.bags[0] = { size = 1, 1100 } -- bags full
    ns.RefreshBankPanel()
    click(rowFor(panel, "Ret").get)
    settleGear()
    eq(bankHolds(1680), true)
    assert(printed():find("1 didn't fit: your bags are full.", 1, true), printed())
end)

test("closing the bank partway stops the move", function()
    local c, ns = bankLogin()
    wow.bags[0] = { size = 6, 1680, 1100, 1300 }
    ns.SetProfileGear("Ret", { [16] = gearString(1680), [8] = gearString(1300) })
    local panel = openPanel(ns)
    wow.lockMoves = true
    click(rowFor(panel, "Ret").put)
    wow.closeBank()
    wow.unlock()
    settleGear()
    wow.lockMoves = false
    assert(printed():find("Stopped: the bank closed.", 1, true), printed())
    eq(ns.BankMoveBusy(), false)
end)

test("the panel explains when no profile uses Keystance's own gear", function()
    local c, ns = gearLogin()
    ns.SaveProfile("Prot")
    blizzardBank()
    local panel = openPanel(ns)
    eq(panel.rows[1] == nil or not panel.rows[1]:IsShown(), true)
    eq(panel.empty:IsShown(), true)
    assert(panel.empty.text:find("Gear button", 1, true), panel.empty.text)
end)

-- EllesmereUI's bank header row as its code builds it: the search box, sort anchored to its
-- left, Show Bags to sort's left (Show Bags isn't stored anywhere another addon can reach).
local function euiBank()
    local eui = CreateFrame("Frame", "EUI_BankFrame", UIParent)
    local header = CreateFrame("Frame", nil, eui)
    eui._searchBox = CreateFrame("EditBox", nil, header)
    local sort = CreateFrame("Button", nil, header)
    sort:SetPoint("RIGHT", eui._searchBox, "LEFT", -13, 0)
    local showBags = CreateFrame("Button", nil, header)
    showBags:SetPoint("RIGHT", sort, "LEFT", -6, 0)
    return eui, header, sort, showBags
end

test("on EllesmereUI's bank, the button goes at the left end of the header row", function()
    local c, ns = bankLogin()
    local eui, header, sort, showBags = euiBank()
    wow.openBank()
    wow.runTimers()
    local b = ns.BankButtons().EUI_BankFrame
    eq(b.point[1], "RIGHT")
    eq(b.point[2], showBags, "left of Show Bags, not on top of it")
end)

test("on EllesmereUI's bank, a hidden button is skipped and Alts Forever's is followed", function()
    local c, ns = bankLogin()
    local eui, header, sort, showBags = euiBank()
    showBags:Hide() -- sort switched off in EllesmereUI, say
    local altsForever = CreateFrame("Button", nil, header)
    altsForever:SetPoint("RIGHT", sort, "LEFT", -6, 0)
    wow.openBank()
    wow.runTimers()
    eq(ns.BankButtons().EUI_BankFrame.point[2], altsForever, "left of Alts Forever's, which came first")
end)

test("EllesmereUI's and ElvUI's bank windows get the button too", function()
    local c, ns = bankLogin()
    local eui, header = euiBank()
    CreateFrame("Frame", "ElvUI_BankContainerFrame", UIParent)
    wow.openBank()
    wow.runTimers()
    local buttons = ns.BankButtons()
    eq(buttons.EUI_BankFrame.parent, header)
    assert(buttons.EUI_BankFrame.icon.texture:find("logo.tga", 1, true), "EllesmereUI's round buttons have the gold ring")
    assert(buttons.BankFrame.icon.texture:find("minimap.tga", 1, true), "Blizzard's: the plain logo")
    eq(buttons.ElvUI_BankContainerFrame.parent, ElvUI_BankContainerFrame)
end)

test("the bank panel costs nothing while you play", function()
    local c, ns = bankLogin()
    eq(KeystanceBankPanel, nil, "not built until its button is clicked")
end)

test("a move the game refuses puts the item back and doesn't try again forever", function()
    local c, ns = bankLogin()
    local panel = openPanel(ns)
    wow.refusePlace = true
    click(rowFor(panel, "Ret").put)
    settleGear()
    wow.refusePlace = nil
    eq(wow.cursor, nil, "nothing left on the cursor")
    eq(bagsHold(1680), true)
    eq(ns.BankMoveBusy(), false)
    assert(printed():find("1 couldn't be moved: the game wouldn't put it there.", 1, true), printed())
    assert(not printed():find("Stopped:", 1, true), "tried once, not until the safety limit")
end)
