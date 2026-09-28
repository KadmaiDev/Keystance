-- Tests: the Profiles tab and the Settings buttons for restore and own keybinds.
---------------------------------------------------------------------------
function profilesPage()
    slash("")
    click(tabNamed("Profiles"))
    return pageFor("profiles")
end

-- A dialog as Blizzard shows it, with `typed` in its box.
function dialogWith(typed)
    return { editBox = { GetText = function() return typed end } }
end

-- Accepts the pop-up showing now, typing `typed` if it has a box.
function accept(typed)
    local which = wow.popup.which
    StaticPopupDialogs[which].OnAccept(dialogWith(typed), wow.popup.data)
end

test("with no profiles the tab says how to make one", function()
    profileLogin()
    local page = profilesPage()
    eq(page.empty:IsShown(), true)
    eq(page.title.text, "Profiles for Vespera Ashward")
end)

test("New profile asks for a name and lists the profile with what it holds", function()
    profileLogin()
    local page = profilesPage()
    click(page.new)
    eq(wow.popup.which, "KEYSTANCE_NAME")
    accept("Prot")
    local row = page.rows[1]
    eq(row.profile, "Prot")
    eq(row.name.text, "Prot")
    assert(row.detail.text:find("5 slots, 5 keys", 1, true), row.detail.text)
    eq(page.empty:IsShown(), false)
end)

test("Apply shows what will change first, then applies; the profile in use is marked", function()
    profileLogin()
    local page = profilesPage()
    slash("save Ret")
    shuffle()
    wow.runTimers()
    click(page.rows[1].apply)
    eq(wow.popup.which, "KEYSTANCE_APPLY")
    eq(wow.popup.text, "Ret")
    eq(slotId(1), 647, "not before it's confirmed")
    accept()
    eq(slotId(1), 1866)
    eq(KeystanceFrame.status.text.text, "In use: Ret")
    eq(page.rows[1].name.text, "|cff55ff55Ret|r")
end)

test("Apply when nothing would change just says so", function()
    profileLogin()
    local page = profilesPage()
    slash("save Ret")
    wow.popup = nil
    click(page.rows[1].apply)
    eq(wow.popup, nil)
    assert(printed():find("Ret is already in place.", 1, true))
end)

test("the Undo button names what it undoes, and works", function()
    profileLogin()
    local page = profilesPage()
    slash("save Ret")
    shuffle()
    slash("apply Ret")
    wow.runTimers()
    eq(page.undo.text, "Undo applying Ret")
    click(page.undo)
    eq(slotId(1), 647)
    eq(page.undo.text, "Undo the undo")
end)

test("Update, Rename, Copy and Delete from a profile's row", function()
    local c = profileLogin()
    local page = profilesPage()
    slash("save Ret")
    wow.slots[9] = { kind = "spell", id = 647 }
    click(page.rows[1].update)
    accept()
    eq(c.profiles.Ret.slots[9].id, 647, "updated from the current setup")
    click(page.rows[1].rename)
    accept("Retribution")
    eq(c.profiles.Retribution ~= nil, true)
    click(page.rows[1].copy)
    accept("Ret 2")
    eq(c.profiles["Ret 2"] ~= nil, true)
    click(page.rows[1].delete) -- rows are in name order: "Ret 2" first
    accept()
    eq(c.profiles["Ret 2"], nil)
end)

test("with shared keybinds the tab says so and offers the switch; afterwards it's gone", function()
    profileLogin(true)
    local page = profilesPage()
    eq(page.shared:IsShown(), true)
    click(page.ownKeys)
    wow.runTimers()
    eq(GetCurrentBindingSet(), 2)
    eq(page.shared:IsShown(), false)
    eq(page.ownKeys:IsShown(), false)
end)

test("Restore original setup asks first", function()
    profileLogin()
    local page = profilesPage()
    shuffle()
    click(page.restore)
    eq(wow.popup.which, "KEYSTANCE_RESTORE")
    accept()
    eq(slotId(1), 1866)
end)

test("Settings has Restore, and the own-keybinds button while keybinds are shared", function()
    profileLogin(true)
    slash("")
    click(tabNamed("Settings"))
    local page = pageFor("settings")
    eq(page.ownKeys:IsShown(), true)
    click(page.restore)
    eq(wow.popup.which, "KEYSTANCE_RESTORE")
    click(page.ownKeys)
    wow.runTimers()
    eq(page.ownKeys:IsShown(), false)
end)

test("in combat, every profile button and dialog makes no protected call", function()
    profileLogin()
    local page = profilesPage()
    slash("save Ret")
    shuffle()
    wow.enterCombat()
    for _, b in ipairs(KeystanceFrame.buttons) do
        if b.scripts.OnClick then
            wow.popup = nil
            b.scripts.OnClick(b, "LeftButton")
            if wow.popup then
                local d = StaticPopupDialogs[wow.popup.which]
                if d.OnAccept then d.OnAccept(dialogWith("X"), wow.popup.data) end
            end
        end
    end
    eq(#wow.blocked, 0, table.concat(wow.blocked, ","))
    wow.leaveCombat()
end)
