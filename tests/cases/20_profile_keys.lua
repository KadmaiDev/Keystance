-- Tests: keys that switch profiles (Bindings.xml), set from the Profiles tab.

-- Three profiles, Holy, Prot and Ret, differing in slot 1; Ret in use.
local function threeProfiles()
    local c, ns = profileLogin()
    for _, p in ipairs({ { "Ret", 1866 }, { "Prot", 647 }, { "Holy", 19834 } }) do
        wow.slots[1] = { kind = "spell", id = p[2] }
        ns.SaveProfile(p[1])
    end
    wow.slots[1] = { kind = "spell", id = 1866 }
    c.active = "Ret"
    return c, ns
end

-- The row for a profile on the Profiles tab.
local function rowFor(page, name)
    for _, row in ipairs(page.rows) do
        if row.profile == name and row:IsShown() then return row end
    end
end

-- Sets a profile's key from its row: click the key button, press `key` (with `mods`).
local function setKey(page, name, key, mods)
    click(rowFor(page, name).key)
    for m in pairs(mods or {}) do wow.mods[m] = true end
    page.catcher.scripts.OnKeyDown(page.catcher, key)
    wow.mods = {}
end

-- The binding commands and the Lua each runs, from Bindings.xml.
local function bindings()
    local list = {}
    for name, body in readFile("Bindings.xml"):gmatch('<Binding name="([%w_]+)"[^>]*>(.-)</Binding>') do
        list[#list + 1] = { name, body }
    end
    return list
end

test("a profile's key is set from its row: click, press a key, and that key switches to it", function()
    local c, ns = threeProfiles()
    local page = profilesPage()
    local row = rowFor(page, "Prot")
    assert(row.key.text:find("Set key", 1, true), row.key.text)
    click(row.key)
    assert(row.key.text:find("Press a key", 1, true), row.key.text)
    eq(page.catcher.keyboard, true, "the keyboard goes to Keystance while it waits")
    page.catcher.scripts.OnKeyDown(page.catcher, "LSHIFT") -- a modifier alone is waited past
    eq(page.capturing, "Prot")
    wow.mods.shift = true
    page.catcher.scripts.OnKeyDown(page.catcher, "F2")
    wow.mods = {}
    eq(page.capturing, nil)
    eq(page.catcher.keyboard, false)
    eq(GetBindingAction("SHIFT-F2"), "KEYSTANCE_PROFILE1")
    eq(row.key.text, "SHIFT-F2")
    assert(printed():find("Prot is now on SHIFT-F2.", 1, true), printed())
    Keystance_Binding(1)
    eq(c.active, "Prot")
    eq(slotId(1), 647)
end)

test("a profile keeps its key when profiles are added, renamed or deleted", function()
    local c, ns = threeProfiles()
    local page = profilesPage()
    setKey(page, "Ret", "F3")
    ns.SaveProfile("Arms") -- sorts first; Ret's key doesn't move
    eq(ns.ProfileKey("Ret"), "F3")
    eq(ns.ProfileKey("Arms"), nil)
    ns.RenameProfile("Ret", "Retri")
    eq(ns.ProfileKey("Retri"), "F3")
    eq(BINDING_NAME_KEYSTANCE_PROFILE1, "Profile 1: Retri")
    ns.DeleteProfile("Retri")
    eq(BINDING_NAME_KEYSTANCE_PROFILE1, "Profile 1")
    Keystance_Binding(1)
    assert(printed():find("No profile is on this key yet", 1, true))
    -- The freed keybind goes to the next profile given a key, without the old key.
    setKey(page, "Holy", "F4")
    eq(ns.ProfileSlot("Holy"), 1)
    eq(GetBindingAction("F3"), "", "the deleted profile's key doesn't carry over")
    eq(GetBindingAction("F4"), "KEYSTANCE_PROFILE1")
end)

test("a new key replaces the profile's old one; a taken key says what it was; Undo puts it back", function()
    local c, ns = threeProfiles()
    local page = profilesPage()
    wow.bindings.F5 = "TOGGLEAUTORUN"
    setKey(page, "Prot", "F6")
    setKey(page, "Prot", "F5")
    eq(GetBindingAction("F6"), "", "one key per profile")
    eq(GetBindingAction("F5"), "KEYSTANCE_PROFILE1")
    assert(printed():find("(F5 was Toggle Autorun.)", 1, true), printed())
    ns.Undo()
    eq(GetBindingAction("F5"), "TOGGLEAUTORUN")
    eq(GetBindingAction("F6"), "KEYSTANCE_PROFILE1")
end)

test("right-click takes a profile's key off; Esc stops waiting without changing anything", function()
    local c, ns = threeProfiles()
    local page = profilesPage()
    setKey(page, "Prot", "F2")
    click(rowFor(page, "Prot").key)
    page.catcher.scripts.OnKeyDown(page.catcher, "ESCAPE")
    eq(page.capturing, nil)
    eq(GetBindingAction("F2"), "KEYSTANCE_PROFILE1")
    click(rowFor(page, "Prot").key, "RightButton")
    eq(GetBindingAction("F2"), "")
    eq(ns.ProfileSlot("Prot"), nil)
    assert(rowFor(page, "Prot").key.text:find("Set key", 1, true))
end)

test("in combat a profile's key can't be set, and nothing is attempted", function()
    local c, ns = threeProfiles()
    local page = profilesPage()
    wow.enterCombat()
    eq(ns.SetProfileKey("Prot", "F2"), false)
    click(rowFor(page, "Prot").key)
    eq(page.capturing, nil)
    eq(#wow.blocked, 0)
    wow.leaveCombat()
end)

test("with shared keybinds, setting a key asks to give the character its own first", function()
    local c, ns = threeProfiles()
    wow.bindingSet = 1
    local page = profilesPage()
    click(rowFor(page, "Prot").key)
    eq(wow.popup.which, "KEYSTANCE_PROFILE_KEY")
    eq(page.capturing, nil)
    StaticPopupDialogs.KEYSTANCE_PROFILE_KEY.OnAccept(nil, wow.popup.data)
    eq(wow.bindingSet, 2)
    eq(page.capturing, "Prot")
end)

test("six profiles can have keys; a seventh is told why not", function()
    local c, ns = threeProfiles()
    for _, name in ipairs({ "A", "B", "C", "D" }) do ns.SaveProfile(name) end
    for i, name in ipairs({ "A", "B", "C", "D", "Holy", "Prot" }) do eq(ns.SetProfileKey(name, "F" .. i), true) end
    eq(ns.SetProfileKey("Ret", "F7"), false)
    assert(printed():find("Up to 6 profiles can have keys", 1, true), printed())
end)

test("keys bound before profiles owned them stay with the profiles they pointed at", function()
    local c, ns = threeProfiles()
    c.keySlots = nil -- as saved before this change: Profile N was the Nth in name order
    wow.bindings.F2 = "KEYSTANCE_PROFILE2"
    ns.NameBindings()
    eq(c.keySlots[2], "Prot")
    eq(c.keySlots[1], nil, "no key, no owner")
    eq(ns.ProfileKey("Prot"), "F2")
end)

test("Next profile goes round the profiles in name order", function()
    local c, ns = threeProfiles()
    Keystance_Binding("next")
    eq(c.active, "Holy", "after Ret, round to the first")
    Keystance_Binding("next")
    eq(c.active, "Prot")
    c.active = nil
    Keystance_Binding("next")
    eq(c.active, "Holy", "none in use: the first")
end)

test("a profile keybind in combat waits for combat to end", function()
    local c, ns = threeProfiles()
    ns.SetProfileKey("Prot", "F2")
    wow.enterCombat()
    Keystance_Binding(1)
    eq(slotId(1), 1866)
    eq(#wow.blocked, 0)
    wow.leaveCombat()
    eq(slotId(1), 647)
end)

test("every keybind in Bindings.xml has a name and runs", function()
    local c, ns = threeProfiles()
    eq(BINDING_HEADER_KEYSTANCE, "Keystance")
    local list = bindings()
    eq(#list, 8)
    for _, b in ipairs(list) do
        assert(_G["BINDING_NAME_" .. b[1]], "no name for " .. b[1])
        assert(loadstring(b[2]))()
    end
    eq(KeystanceFrame:IsShown(), true, "Open Keystance opened the window")
end)

test("the keybinds file ships with the addon and the dev copy", function()
    assert(readFile("tools/release.py"):find('"Bindings.xml"', 1, true))
    assert(readFile("tools/install_dev.py"):find('"Bindings.xml"', 1, true))
end)

test("the Actions panel's Commands tab holds a profile's switch; clicking a key gives it that key", function()
    local c, ns = threeProfiles()
    ns.ToggleSpellPanel()
    local panel = KeystanceSpellPanel
    click(choice(panel.kinds, "Commands"))
    eq(panel.rows[2].item.name, "Holy")
    eq(panel.rows[5].item.name, "Next profile")
    click(rowNamed("Prot"))
    eq(ns.HeldBinding().profile, "Prot")
    ns.BindHeld("F7", "")
    eq(GetBindingAction("F7"), "KEYSTANCE_PROFILE1")
    eq(ns.ProfileKey("Prot"), "F7")
    panel:Refresh()
    eq(rowNamed("Prot").detail.text, "F7")
    -- Held again and put on a key that does something: asked first, then moved.
    wow.bindings.F8 = "TOGGLEAUTORUN"
    click(rowNamed("Prot"))
    ns.BindHeld("F8", "TOGGLEAUTORUN")
    eq(wow.popup.which, "KEYSTANCE_BIND_COMMAND")
    StaticPopupDialogs.KEYSTANCE_BIND_COMMAND.OnAccept()
    eq(GetBindingAction("F8"), "KEYSTANCE_PROFILE1")
    eq(GetBindingAction("F7"), "", "still one key per profile")
    -- Next profile is a plain keybind.
    click(rowNamed("Next profile"))
    ns.BindHeld("F9", "")
    eq(GetBindingAction("F9"), "KEYSTANCE_NEXT")
end)
