-- Tests: automatic switching by gear (rules) and the Rules tab.
---------------------------------------------------------------------------
-- Vespera with two profiles that differ in slot 1: Ret (Holy Strike) and Prot (Holy Light).
function rulesLogin()
    local c, ns = profileLogin()
    ns.SaveProfile("Ret")
    wow.slots[1] = { kind = "spell", id = 647 }
    ns.SaveProfile("Prot")
    wow.slots[1] = { kind = "spell", id = 1866 }
    c.active = "Ret"
    return c, ns
end

-- Equips an item (nil empties the slot), as the game reports it.
function equip(slot, id)
    wow.inventory[slot] = id
    wow.fire("PLAYER_EQUIPMENT_CHANGED", slot, id == nil)
end

test("equipping a shield switches to the shield rule's profile, once the gear has settled", function()
    local c, ns = rulesLogin()
    ns.AddRule({ when = "shield", profile = "Prot" })
    equip(17, 2129)
    eq(slotId(1), 1866, "not during the swap")
    wow.runTimers()
    eq(slotId(1), 647)
    eq(c.active, "Prot")
    assert(printed():find("A shield is equipped: switching to Prot.", 1, true), printed())
end)

test("several equipment events at once make one check", function()
    local c, ns = rulesLogin()
    ns.AddRule({ when = "shield", profile = "Prot" })
    equip(16, 2132); equip(17, 2129); wow.fire("EQUIPMENT_SWAP_FINISHED", true)
    eq(#wow.timers, 1)
end)

test("a two-hander switches to its profile; the first matching rule wins", function()
    local c, ns = rulesLogin()
    c.active = "Prot"
    wow.slots[1] = { kind = "spell", id = 647 }
    ns.AddRule({ when = "shield", profile = "Prot" })
    ns.AddRule({ when = "twohand", profile = "Ret" })
    equip(16, 1680); equip(17, nil)
    wow.runTimers()
    eq(c.active, "Ret")
    eq(slotId(1), 1866)
end)

test("nothing happens when the profile the rule wants is already in use", function()
    local c, ns = rulesLogin()
    ns.AddRule({ when = "twohand", profile = "Ret" })
    wow.calls = {}
    equip(16, 1680)
    wow.runTimers()
    eq(#wow.calls, 0)
    assert(not printed():find("switching to", 1, true), "no switch announced")
end)

test("a specific item, and an equipment set, can pick the profile", function()
    local c, ns = rulesLogin()
    ns.AddRule({ when = "item", id = 6948, profile = "Prot" })
    equip(1, 6948)
    wow.runTimers()
    eq(c.active, "Prot")
    c.rules = {}
    ns.AddRule({ when = "set", set = "Swinging", profile = "Ret" })
    wow.sets = { { name = "Swinging", equipped = true } }
    equip(1, nil)
    wow.runTimers()
    eq(c.active, "Ret")
end)

test("in combat the switch waits for combat to end", function()
    local c, ns = rulesLogin()
    ns.AddRule({ when = "shield", profile = "Prot" })
    wow.enterCombat()
    equip(17, 2129)
    wow.runTimers()
    eq(slotId(1), 1866)
    eq(#wow.blocked, 0)
    assert(printed():find("Prot will apply when combat ends.", 1, true))
    wow.leaveCombat()
    eq(slotId(1), 647)
end)

test("switched off, rules do nothing; /kst auto turns them back on", function()
    local c, ns = rulesLogin()
    ns.AddRule({ when = "shield", profile = "Prot" })
    slash("auto off")
    equip(17, 2129)
    wow.runTimers()
    eq(c.active, "Ret")
    slash("auto on")
    equip(17, 2129)
    wow.runTimers()
    eq(c.active, "Prot")
end)

test("with Ask before switching, each switch is a question", function()
    local c, ns = rulesLogin()
    ns.AddRule({ when = "shield", profile = "Prot" })
    KeystanceDB.settings.askSwitch = true
    equip(17, 2129)
    wow.runTimers()
    eq(wow.popup.which, "KEYSTANCE_SWITCH")
    eq(c.active, "Ret", "not until answered")
    StaticPopupDialogs.KEYSTANCE_SWITCH.OnAccept(nil, wow.popup.data)
    eq(c.active, "Prot")
end)

test("renaming a profile keeps its rules; a rule whose profile is gone is skipped and marked", function()
    local c, ns = rulesLogin()
    ns.AddRule({ when = "shield", profile = "Prot" })
    ns.RenameProfile("Prot", "Tank")
    eq(c.rules[1].profile, "Tank")
    ns.DeleteProfile("Tank")
    assert(ns.RuleText(c.rules[1]):find("no such profile", 1, true))
    equip(17, 2129)
    wow.runTimers()
    eq(c.active, "Ret")
end)

---------------------------------------------------------------------------
-- The Rules tab
function rulesPage()
    slash("")
    click(tabNamed("Rules"))
    return pageFor("rules")
end

test("the Rules tab adds rules, shows them as sentences, and reorders and deletes them", function()
    local c = rulesLogin()
    local page = rulesPage()
    eq(page.empty:IsShown(), true)
    click(choice(page.when, "a shield"))
    while page.new.profile ~= "Prot" do click(page.profile) end
    click(page.add)
    eq(page.rows[1].text.text, "1.  When a shield is equipped, use Prot.")
    click(choice(page.when, "a two-hander"))
    click(page.profile) -- to Ret
    click(page.add)
    eq(page.rows[2].text.text, "2.  When a two-handed weapon is equipped, use Ret.")
    click(page.rows[2].up)
    eq(c.rules[1].when, "twohand")
    click(page.rows[1].delete)
    eq(#c.rules, 1)
    eq(c.rules[1].when, "shield")
end)

test("an item rule takes the item dropped on its button (the item goes back)", function()
    local c = rulesLogin()
    local page = rulesPage()
    click(choice(page.when, "an item"))
    eq(page.item:IsShown(), true)
    wow.cursor = { "item", 6948 }
    page.item.scripts.OnReceiveDrag(page.item)
    eq(wow.cursor, nil)
    click(page.add)
    eq(c.rules[1].id, 6948)
    assert(page.rows[1].text.text:find("Hearthstone is equipped", 1, true))
end)

test("the Rules tab's On/Off follows /kst auto and the minimap menu", function()
    rulesLogin()
    local page = rulesPage()
    click(choice(page.auto, "Off"))
    eq(KeystanceDB.settings.autoOff, true)
    Keystance_OnAddonCompartmentClick("Keystance", "RightButton", UIParent)
    wow.menuItem("Switch profiles automatically").setSelected()
    eq(KeystanceDB.settings.autoOff, nil)
    eq(choice(page.auto, "On").chosen, true)
end)

test("rules act when what they want changes, not on every gear change: a hand-picked profile stays", function()
    local c, ns = rulesLogin()
    ns.SaveProfile("Holy")
    ns.AddRule({ when = "shield", profile = "Prot" })
    equip(17, 2129)
    wow.runTimers()
    eq(c.active, "Prot")
    ns.ApplyProfile("Holy") -- the player's choice, shield still on
    eq(c.active, "Holy")
    equip(13, 1200) -- a trinket
    wow.runTimers()
    eq(c.active, "Holy", "not overridden by an unrelated swap")
    -- Taking the shield off and putting it back is a change the rules act on again.
    equip(17, nil)
    wow.runTimers()
    equip(17, 2129)
    wow.runTimers()
    eq(c.active, "Prot")
end)

test("an Undo isn't reversed by the next gear change", function()
    local c, ns = rulesLogin()
    ns.AddRule({ when = "shield", profile = "Prot" })
    equip(17, 2129)
    wow.runTimers()
    eq(c.active, "Prot")
    ns.Undo()
    eq(c.active, nil)
    equip(13, 1200)
    wow.runTimers()
    eq(c.active, nil, "the Undo stands")
end)

test("after Stay, the question isn't asked again until the gear changes what the rules want", function()
    local c, ns = rulesLogin()
    KeystanceDB.settings.askSwitch = true
    ns.AddRule({ when = "shield", profile = "Prot" })
    equip(17, 2129)
    wow.runTimers()
    eq(wow.popup.which, "KEYSTANCE_SWITCH")
    wow.popup = nil -- Stay
    equip(13, 1200)
    wow.runTimers()
    eq(wow.popup, nil, "not asked again")
end)

test("a switch the player queued in combat isn't replaced by a rule", function()
    local c, ns = rulesLogin()
    ns.SaveProfile("Holy")
    ns.AddRule({ when = "shield", profile = "Prot" })
    wow.enterCombat()
    ns.ApplyProfile("Holy") -- queued
    equip(17, 2129)
    wow.runTimers()
    eq(ns.pendingProfile, "Holy")
    wow.leaveCombat()
    eq(c.active, "Holy")
end)

test("a burst of gear events is checked once the gear has been still, not halfway", function()
    local c, ns = rulesLogin()
    ns.AddRule({ when = "twohand", profile = "Prot" })
    wow.clock = 10
    equip(16, 2132) -- the swap begins: a one-hander for a moment
    wow.clock = 10.2
    equip(16, 1680) -- then the two-hander, before the first check
    wow.runTimers() -- the first check sees a later event and waits
    eq(c.active, "Ret", "not decided mid-swap")
    wow.runTimers()
    eq(c.active, "Prot")
    wow.clock = nil
end)

test("more than six rules: the Rules tab scrolls, so every rule can be moved and deleted", function()
    local c, ns = rulesLogin()
    for i = 1, 8 do ns.AddRule({ when = "item", id = 1000 + i, profile = "Prot" }) end
    local page = rulesPage()
    eq(page.more:IsShown(), true)
    page.scripts.OnMouseWheel(page, -2)
    eq(page.offset, 2)
    eq(page.rows[6].index, 8, "the last rule, in reach")
    click(page.rows[6].delete)
    eq(#c.rules, 7)
    eq(page.offset, 1, "no scrolling past the end")
end)
