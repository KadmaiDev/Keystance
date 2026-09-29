-- Tests: looks (classic, EllesmereUI, ElvUI).
---------------------------------------------------------------------------
function skinnedWith(fname, obj)
    for _, call in ipairs(wow.skinned) do
        if call[1] == fname and call[2] == obj then return true end
    end
    return false
end

function countSkinned(fname)
    local n = 0
    for _, call in ipairs(wow.skinned) do if call[1] == fname then n = n + 1 end end
    return n
end

test("without a UI addon nothing is skinned: the classic look stays", function()
    local ns = start(nil)
    slash("")
    eq(#wow.skinned, 0)
    eq(ns.SkinName(), "classic")
end)

test("with EllesmereUI, the window, its tabs, buttons and text take its look", function()
    wow.withEllesmere = true
    local ns = wow.load(FILES)
    eq(wow.skinName, "Keystance", "registered under the addon's folder name")
    wow.login(nil)
    wow.skinCallback(wow.skinFacade) -- EllesmereUI calls this at login
    eq(ns.SkinName(), "ellesmere")
    slash("")
    assert(skinnedWith("Shell", KeystanceFrame), "backdrop")
    eq(countSkinned("Tab"), 5)
    assert(skinnedWith("Button", pageFor("settings").lookRow.buttons[1]), "buttons")
    assert(skinnedWith("Font", KeystanceFrame.status.text), "window text")
    assert(countSkinned("Font") > 5, "page text too")
end)

test("a window built before EllesmereUI's callback is skinned when it arrives", function()
    wow.withEllesmere = true
    wow.load(FILES)
    wow.login(nil)
    slash("")
    eq(#wow.skinned, 0)
    wow.skinCallback(wow.skinFacade)
    assert(skinnedWith("Shell", KeystanceFrame))
    eq(countSkinned("Tab"), 5)
end)

test("if the player turned our skinning off in EllesmereUI, the classic look stays", function()
    wow.withEllesmere = true
    wow.load(FILES)
    wow.login(nil)
    slash("") -- EllesmereUI never calls back when its third-party skinning is off for us
    eq(#wow.skinned, 0)
end)

test("with ElvUI, the window, its tabs and buttons take its look", function()
    wow.withElvUI = true
    local ns = start(nil)
    eq(ns.SkinName(), "elvui")
    slash("")
    assert(skinnedWith("HandleFrame", KeystanceFrame))
    eq(countSkinned("HandleTab"), 5)
    assert(skinnedWith("HandleButton", pageFor("settings").lookRow.buttons[1]))
    assert(skinnedWith("FontTemplate", KeystanceFrame.status.text))
end)

test("before ElvUI has initialised the classic look is used", function()
    wow.withElvUI = true
    local ns = wow.load(FILES)
    wow.elv.Initialized = nil
    wow.login(nil)
    eq(ns.SkinName(), "classic")
end)

test("an error inside ElvUI's skinning never stops the window opening", function()
    wow.withElvUI = true
    wow.load(FILES)
    for _, fname in ipairs({ "HandleFrame", "HandleButton", "HandleTab" }) do
        wow.elvSkins[fname] = function() error("changed API") end
    end
    wow.login(nil)
    slash("")
    eq(KeystanceFrame:IsShown(), true)
end)

test("with both installed, EllesmereUI wins on Automatic; ElvUI can still be chosen", function()
    wow.withEllesmere, wow.withElvUI = true, true
    local ns = start(nil)
    wow.skinCallback(wow.skinFacade)
    eq(ns.SkinName(), "ellesmere")
    slash("")
    assert(skinnedWith("Shell", KeystanceFrame))
    eq(skinnedWith("HandleFrame", KeystanceFrame), false)

    wow.withEllesmere, wow.withElvUI = true, true
    ns = start({ v = 1, settings = { skin = "elvui" }, chars = {} })
    wow.skinCallback(wow.skinFacade)
    eq(ns.SkinName(), "elvui")
end)

test("choosing Classic keeps Blizzard's look even with a UI addon installed", function()
    wow.withEllesmere, wow.withElvUI = true, true
    local ns = start({ v = 1, settings = { skin = "classic" }, chars = {} })
    wow.skinCallback(wow.skinFacade)
    slash("")
    eq(ns.SkinName(), "classic")
    eq(#wow.skinned, 0)
end)

test("a choice whose addon isn't installed falls back to classic", function()
    local ns = start({ v = 1, settings = { skin = "ellesmere" }, chars = {} })
    eq(ns.SkinName(), "classic")
end)

test("/kst skin changes the setting and offers to reload, since the look changes then", function()
    wow.withElvUI = true
    local ns = start(nil)
    slash("skin classic")
    eq(KeystanceDB.settings.skin, "classic")
    eq(ns.SkinName(), "elvui", "unchanged until the reload")
    eq(wow.popup.which, "KEYSTANCE_RELOAD")
    StaticPopupDialogs.KEYSTANCE_RELOAD.OnAccept()
    eq(wow.reloads, 1, "Reload now reloads")
    wow.runTimers() -- still here a moment later: the game refused
    assert(printed():find("Type /reload", 1, true))
    slash("skin shiny")
    eq(KeystanceDB.settings.skin, "classic")
    assert(printed():find("Unknown look 'shiny'", 1, true))
    slash("skin")
    assert(printed():find("Look: classic (in use: elvui)", 1, true), printed())
end)

test("choosing a look that changes nothing doesn't ask to reload", function()
    wow.withElvUI = true
    start(nil)
    slash("skin elvui") -- Automatic already gives ElvUI
    eq(wow.popup, nil)
    assert(printed():find("Look set to ElvUI.", 1, true), printed())
    slash("skin ellesmere") -- not installed: classic, which isn't in use
    eq(wow.popup.which, "KEYSTANCE_RELOAD")
end)

test("the reload pop-up is added without assigning Blizzard's StaticPopupDialogs", function()
    start(nil)
    local dialogs = StaticPopupDialogs
    slash("skin classic")
    eq(StaticPopupDialogs, dialogs, "same table")
    eq(dialogs.KEYSTANCE_RELOAD, nil, "classic is already in use: no pop-up needed")
    wow.withElvUI = true
    start(nil)
    dialogs = StaticPopupDialogs
    slash("skin classic")
    eq(StaticPopupDialogs, dialogs)
    assert(dialogs.KEYSTANCE_RELOAD, "added on first use")
end)

test("the guide bar under the window takes the look too, its X like the window's", function()
    wow.withEllesmere = true
    local ns = wow.load(FILES)
    wow.login(nil)
    wow.skinCallback(wow.skinFacade)
    slash("")
    assert(KeystanceGuideBar:IsShown(), "a new character sees the guide")
    assert(skinnedWith("Shell", KeystanceGuideBar), "backdrop")
    assert(skinnedWith("CloseButton", KeystanceGuideBar.close), "its X, as the window's")
end)

test("an error inside EllesmereUI's skinning never stops the window opening", function()
    wow.withEllesmere = true
    wow.load(FILES)
    wow.login(nil)
    wow.skinFacade.Shell = function() error("EllesmereUI broke") end
    wow.skinFacade.Button = function() error("EllesmereUI broke") end
    wow.skinCallback(wow.skinFacade)
    slash("")
    eq(KeystanceFrame:IsShown(), true)
end)
