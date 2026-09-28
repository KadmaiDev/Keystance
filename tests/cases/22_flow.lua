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

-- The guide bar's step title, or nil when it's hidden.
local function guideStep()
    local bar = KeystanceGuideBar
    if not (bar and bar:IsShown()) then return nil end
    return bar.title.text
end

test("a new player is walked through, step by step, each ticked off by doing it", function()
    local c, ns = loginWithSetup(nil)
    wow.bindingSet = 1 -- shared keybinds, as for most players
    slash("")
    eq(guideStep(), "Give this character its own keybinds", "the backup is already done")
    eq(KeystanceGuideBar.step.text, "Step 2 of 6")
    click(KeystanceGuideBar.actions[1])
    eq(wow.bindingSet, 2)
    eq(guideStep(), "Save your first profile")
    click(KeystanceGuideBar.actions[1])
    eq(wow.popup.which, "KEYSTANCE_NAME")
    ns.SaveProfile("Ret")
    eq(guideStep(), "Set up another role")
    click(KeystanceGuideBar.actions[1])
    eq(shownPage(), "keyboard")
    wow.slots[1] = { kind = "spell", id = 647 }
    ns.SaveProfile("Prot")
    eq(guideStep(), "Choose how to switch")
    ns.AddRule({ when = "shield", profile = "Prot" })
    eq(guideStep(), "Gear too (optional)", "a rule counts at once")
    eq(KeystanceGuideBar.actions[2].text, "Skip")
    click(KeystanceGuideBar.actions[2])
    eq(guideStep(), "You're all set")
    click(KeystanceGuideBar.actions[1])
    eq(guideStep(), nil)
    eq(c.guide.finished, true)
end)

test("steps already done are skipped: a returning player starts where they are", function()
    local c, ns = profileLogin() -- own keybinds
    ns.SaveProfile("Ret")
    wow.slots[1] = { kind = "spell", id = 647 }
    ns.SaveProfile("Prot")
    ns.SetProfileKey("Prot", "F2")
    slash("")
    eq(guideStep(), "Gear too (optional)")
end)

test("the guide can be hidden, and /kst guide brings it back", function()
    local c, ns = profileLogin()
    slash("")
    assert(guideStep())
    click(KeystanceGuideBar.close)
    eq(guideStep(), nil)
    assert(printed():find("/kst guide brings it back", 1, true))
    slash("") -- closed
    slash("guide")
    assert(guideStep(), "back")
end)

test("Getting started on the Profiles tab lists every step, done ones ticked", function()
    local c, ns = profileLogin()
    ns.SaveProfile("Ret")
    local page = profilesPage()
    click(page.guide)
    local view = page.guideView
    eq(view:IsShown(), true)
    eq(page.list:IsShown(), false)
    eq(view.rows[1].done, true, "backed up")
    eq(view.rows[2].done, true, "own keybinds")
    eq(view.rows[3].done, true, "a profile")
    eq(view.rows[4].done, false)
    eq(view.rows[4].number.text, 4)
    eq(view.rows[3].buttons[1]:IsShown(), false, "no button for what's done")
    click(view.rows[4].buttons[1]) -- Keyboard
    eq(shownPage(), "keyboard")
    click(tabNamed("Profiles"))
    click(view.back)
    eq(page.list:IsShown(), true)
end)

test("a new character is told once where to start", function()
    local c, ns = loginWithSetup(nil)
    assert(printed():find("Type /kst", 1, true), printed())
    wow.printed = {}
    wow.fire("PLAYER_ENTERING_WORLD", false, true)
    wow.runTimers()
    assert(not printed():find("Type /kst", 1, true), "once")
end)

test("the guide's text stops before its buttons, whichever are showing", function()
    local c, ns = profileLogin()
    ns.SaveProfile("Ret")
    slash("")
    local bar = KeystanceGuideBar
    eq(bar.title.text, "Set up another role")
    eq(bar.text.point[1], "RIGHT")
    eq(bar.text.point[2], bar.actions[2], "two buttons: before the second (leftmost)")
    ns.ToggleWindow() -- closed
    wow.slots[1] = { kind = "spell", id = 647 }
    ns.SaveProfile("Prot")
    ns.SetProfileKey("Prot", "F2")
    slash("")
    eq(bar.title.text, "Gear too (optional)")
    eq(bar.text.point[2], bar.actions[2], "Gear and Skip")
    click(bar.actions[2])
    eq(bar.text.point[2], bar.actions[1], "one button: before it")
end)

test("the strip along the bottom has its own band, clear of the pages above it", function()
    profileLogin()
    slash("")
    local strip = KeystanceFrame.status
    local stripTop = strip.point[5] + 22 -- its bottom offset plus its height
    for _, page in ipairs(KeystanceFrame.pages) do
        eq(page.point[1], "BOTTOMRIGHT")
        assert(page.point[5] - stripTop >= 10, "10 px or more between a page and the strip")
    end
    -- And in from the sides as far as the pages' content (pages 8 px in, content 16 more).
    assert(strip.point[4] <= -(8 + 16), "right side")
end)
