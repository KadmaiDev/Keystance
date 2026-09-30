-- Tests: reach (Ergonomics.lua) and the Keyboard tab's heat map.

-- Movement on the given keys (forward, back, left, right), and the reach map re-read.
local function moveOn(f, b, l, r)
    for key, command in pairs(wow.bindings) do
        if command == "MOVEFORWARD" or command == "MOVEBACKWARD" or command == "STRAFELEFT" or command == "STRAFERIGHT" then
            wow.bindings[key] = nil
        end
    end
    wow.bindings[f], wow.bindings[b], wow.bindings[l], wow.bindings[r] = "MOVEFORWARD", "MOVEBACKWARD", "STRAFELEFT", "STRAFERIGHT"
    wow.fire("UPDATE_BINDINGS")
end

local function level(ns, key, prefix)
    local _, name = ns.ReachLevel(ns.KeyReach("ansi", key, prefix or ""))
    return name
end

test("with WASD, keys by the movement keys are easy and those far from them aren't", function()
    local c, ns = loginWithSetup(nil)
    moveOn("W", "S", "A", "D")
    for _, key in ipairs({ "Q", "E", "R", "F", "Z", "X", "C", "2", "3", "SPACE", "BUTTON4", "BUTTON5" }) do
        eq(level(ns, key), "Easy to reach", key)
    end
    for _, key in ipairs({ "1", "4", "5", "T", "G", "V", "TAB" }) do eq(level(ns, key), "Fine", key) end
    for _, key in ipairs({ "6", "B", "F1" }) do eq(level(ns, key), "A stretch", key) end
    for _, key in ipairs({ "Y", "H", "U", "P", "F12", "NUMPAD1", "HOME" }) do eq(level(ns, key), "Far", key) end
    local map = ns.ReachMap("ansi")
    eq(map.fromBinds, true)
    eq(map.movement.W and map.movement.A and map.movement.S and map.movement.D, true)
end)

test("reach follows the movement keys where they are: E S D F moves everything one key right", function()
    local c, ns = loginWithSetup(nil)
    moveOn("E", "D", "S", "F")
    eq(level(ns, "G"), "Easy to reach")
    eq(level(ns, "T"), "Easy to reach")
    eq(level(ns, "H"), "Fine")
    eq(ns.ReachMap("ansi").movement.W, nil)
end)

test("movement on the arrows: reach is measured from W A S D, and the legend says so", function()
    local c, ns = loginWithSetup(nil)
    moveOn("UP", "DOWN", "LEFT", "RIGHT")
    local map = ns.ReachMap("ansi")
    eq(map.fromBinds, false)
    eq(map.keys.forward, "W")
    assert(ns.ReachLegend("ansi"):find("aren't on this keyboard", 1, true), ns.ReachLegend("ansi"))
end)

test("Shift, Ctrl and Alt each cost a little reach; less on the mouse", function()
    local c, ns = loginWithSetup(nil)
    moveOn("W", "S", "A", "D")
    local e = ns.KeyReach("ansi", "E", "")
    assert(ns.KeyReach("ansi", "E", "SHIFT-") < e)
    assert(ns.KeyReach("ansi", "E", "CTRL-") < ns.KeyReach("ansi", "E", "SHIFT-"))
    assert(ns.KeyReach("ansi", "E", "ALT-CTRL-SHIFT-") < ns.KeyReach("ansi", "E", "CTRL-"))
    local m = ns.KeyReach("ansi", "BUTTON4", "")
    eq(m - ns.KeyReach("ansi", "BUTTON4", "CTRL-"), 8, "half of Ctrl's 16")
end)

test("the Heat map button colours each key by its reach, and remembers", function()
    local c, ns = loginWithSetup(nil)
    moveOn("W", "S", "A", "D")
    local page = keyboardPage()
    eq(page.heat:IsShown(), true)
    eq(page.legend:IsShown(), false)
    local e = capFor(page, "E")
    eq(e.bg.fill[1], 0.1, "plain while off")
    click(page.heat)
    eq(KeystanceDB.settings.heatmap, true)
    eq(page.legend:IsShown(), true)
    assert(page.legend.text:find("Reach from W A S D:", 1, true), page.legend.text)
    local _, _, r, g, b = ns.ReachLevel(ns.KeyReach("ansi", "E", ""))
    eq(e.bg.fill[1], r); eq(e.bg.fill[2], g); eq(e.bg.fill[3], b)
    local y = capFor(page, "Y")
    eq(y.bg.fill[1], ns.REACH_LEVELS[4][3], "far keys red")
    local r2, g2, b2 = ns.MovementColour()
    eq(capFor(page, "W").bg.fill[3], b2, "movement keys in their own colour")
    eq(capFor(page, "1").inset, 4, "a bound key's icon sits in, framed by its colour")
    click(page.heat)
    eq(KeystanceDB.settings.heatmap, nil)
    eq(e.bg.fill[1], 0.1)
    eq(capFor(page, "1").inset, 2)
end)

test("every key's tooltip says how easy it is to reach, heat map or not", function()
    local c, ns = loginWithSetup(nil)
    moveOn("W", "S", "A", "D")
    local page = keyboardPage()
    local e = capFor(page, "E")
    e.scripts.OnEnter(e)
    local found
    for _, line in ipairs(GameTooltip.lines) do
        if line[1] == "Reach" then found = line[2] end
    end
    eq(found, ("Easy to reach (%d)"):format(ns.KeyReach("ansi", "E", "")))
    local w = capFor(page, "W")
    w.scripts.OnEnter(w)
    found = nil
    for _, line in ipairs(GameTooltip.lines) do
        if line[1] == "Reach" then found = line[2] end
    end
    eq(found, "a movement key")
end)

test("moving the movement keys redraws the heat map from the new place", function()
    local c, ns = loginWithSetup(nil)
    moveOn("W", "S", "A", "D")
    KeystanceDB.settings.heatmap = true
    local page = keyboardPage()
    eq(level(ns, "G"), "Fine")
    moveOn("E", "D", "S", "F")
    wow.runTimers()
    eq(level(ns, "G"), "Easy to reach")
    assert(page.legend.text:find("Reach from E S D F:", 1, true), page.legend.text)
end)

test("no heat map on the controller view", function()
    local c, ns = loginWithSetup(nil)
    KeystanceDB.settings.heatmap = true
    KeystanceDB.settings.layout = "pad"
    local page = keyboardPage()
    eq(page.heat:IsShown(), false)
    eq(page.legend:IsShown(), false)
    for _, cap in ipairs(page.board.caps) do eq(cap.reach, nil) end
end)

test("movement on the right-hand side (I J K L) isn't modelled: reach is from W A S D", function()
    local c, ns = loginWithSetup(nil)
    moveOn("I", "K", "J", "L")
    eq(ns.ReachMap("ansi").fromBinds, false)
    eq(level(ns, "E"), "Easy to reach")
end)
