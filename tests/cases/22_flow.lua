-- Tests: the window's flow: the status strip (profile in use, changed since saved, a
-- button per profile) and the getting-started guide.

test("the strip along the bottom names the profile in use, with its icon", function()
    local c, ns = profileLogin()
    slash("")
    local s = KeystanceFrame.status
    eq(s.text.text, "No profiles yet")
    eq(s.update:IsShown(), false)
    ns.SaveProfile("Ret")
    eq(s.text.text, "No profile in use")
    slash("apply Ret")
    eq(s.text.text, "In use: Ret")
    eq(s.icon.texture, 201866)
    eq(s.changed:IsShown(), false)
end)

test("changing the bars shows 'changed since saved', and Update saves them into the profile", function()
    local c, ns = profileLogin()
    slash("")
    ns.SaveProfile("Ret")
    slash("apply Ret")
    local s = KeystanceFrame.status
    eq(s.changed:IsShown(), false)
    wow.slots[7] = { kind = "spell", id = 647 }
    wow.fire("ACTIONBAR_SLOT_CHANGED", 7)
    wow.runTimers()
    eq(s.changed:IsShown(), true)
    eq(s.update:IsShown(), true)
    click(s.update)
    eq(wow.popup.which, "KEYSTANCE_UPDATE")
    StaticPopupDialogs.KEYSTANCE_UPDATE.OnAccept(nil, wow.popup.data)
    eq(s.changed:IsShown(), false, "saved: matches again")
    eq(c.profiles.Ret.slots[7].id, 647)
end)

test("a button per profile switches to it; in combat they give way to the combat note", function()
    local c, ns = profileLogin()
    ns.SaveProfile("Ret")
    wow.slots[1] = { kind = "spell", id = 647 }
    ns.SaveProfile("Prot")
    wow.slots[1] = { kind = "spell", id = 1866 }
    slash("")
    local s = KeystanceFrame.status
    eq(s.quick[1].profile, "Prot")
    eq(s.quick[2].profile, "Ret")
    eq(s.quick[3]:IsShown(), false)
    click(s.quick[1])
    eq(wow.popup.which, "KEYSTANCE_APPLY")
    StaticPopupDialogs.KEYSTANCE_APPLY.OnAccept(nil, wow.popup.data)
    eq(c.active, "Prot")
    eq(s.quick[1].ring:IsShown(), true)
    eq(s.quick[2].ring:IsShown(), false)
    wow.enterCombat()
    eq(s.quickFrame:IsShown(), false)
    eq(KeystanceFrame.combat:IsShown(), true)
    wow.leaveCombat()
    eq(s.quickFrame:IsShown(), true)
end)
