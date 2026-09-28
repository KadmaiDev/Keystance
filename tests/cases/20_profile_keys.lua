-- Tests: keybinds that switch profiles (Bindings.xml).

-- Three profiles, Holy, Prot and Ret, differing in slot 1.
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

-- The binding commands and the Lua each runs, from Bindings.xml.
local function bindings()
    local list = {}
    for name, body in readFile("Bindings.xml"):gmatch('<Binding name="([%w_]+)"[^>]*>(.-)</Binding>') do
        list[#list + 1] = { name, body }
    end
    return list
end

test("Profile 1-6 keybinds apply profiles in name order, as the Profiles tab lists them", function()
    local c, ns = threeProfiles()
    Keystance_Binding(2)
    eq(c.active, "Prot")
    eq(slotId(1), 647)
    Keystance_Binding(1)
    eq(c.active, "Holy")
    Keystance_Binding(5)
    assert(printed():find("No profile 5 yet", 1, true), printed())
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
    wow.enterCombat()
    Keystance_Binding(2)
    eq(slotId(1), 1866)
    eq(#wow.blocked, 0)
    wow.leaveCombat()
    eq(slotId(1), 647)
end)

test("Key Bindings names each numbered keybind after its profile, and follows changes", function()
    local c, ns = threeProfiles()
    eq(BINDING_HEADER_KEYSTANCE, "Keystance")
    eq(BINDING_NAME_KEYSTANCE_PROFILE1, "Profile 1: Holy")
    eq(BINDING_NAME_KEYSTANCE_PROFILE3, "Profile 3: Ret")
    eq(BINDING_NAME_KEYSTANCE_PROFILE4, "Profile 4")
    ns.RenameProfile("Holy", "Tank")
    eq(BINDING_NAME_KEYSTANCE_PROFILE1, "Profile 1: Prot")
    eq(BINDING_NAME_KEYSTANCE_PROFILE3, "Profile 3: Tank")
    ns.DeleteProfile("Tank")
    eq(BINDING_NAME_KEYSTANCE_PROFILE3, "Profile 3")
end)

test("every keybind in Bindings.xml has a name and runs", function()
    local c, ns = threeProfiles()
    local list = bindings()
    eq(#list, 8)
    for _, b in ipairs(list) do
        assert(_G["BINDING_NAME_" .. b[1]], "no name for " .. b[1])
        assert(loadstring(b[2]))()
    end
    eq(c.active, "Ret", "the last profile keybind (Profile 6) had no profile; Next went round to Ret")
    eq(KeystanceFrame:IsShown(), true, "Open Keystance opened the window")
end)

test("a profile's row shows the key that switches to it", function()
    local c, ns = threeProfiles()
    wow.bindings.F2 = "KEYSTANCE_PROFILE2"
    local page = profilesPage()
    assert(page.rows[2].detail.text:find("; switch with F2", 1, true), page.rows[2].detail.text)
    assert(not page.rows[1].detail.text:find("switch with", 1, true))
end)

test("the keybinds file ships with the addon and the dev copy", function()
    assert(readFile("tools/release.py"):find('"Bindings.xml"', 1, true))
    assert(readFile("tools/install_dev.py"):find('"Bindings.xml"', 1, true))
end)
