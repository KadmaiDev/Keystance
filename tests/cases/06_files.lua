-- Tests: the files themselves (.toc, one running copy, no Blizzard globals written).
---------------------------------------------------------------------------
function tocFiles(path)
    local files = {}
    for line in io.lines(path) do
        line = line:gsub("\r$", "")
        if line ~= "" and not line:match("^#") then files[#files + 1] = line end
    end
    return files
end

function readFile(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

test("both .toc files list exactly the files the tests load", function()
    for _, toc in ipairs({ "Keystance.toc", "Keystance_Camelot.toc" }) do
        eq(table.concat(tocFiles(toc), ","), table.concat(FILES, ","), toc)
    end
end)

test("both .toc files are identical", function()
    eq(readFile("Keystance.toc"), readFile("Keystance_Camelot.toc"))
end)

test("the .toc targets Forever and names the compartment functions the addon defines", function()
    start(nil)
    local toc = readFile("Keystance.toc")
    assert(toc:find("## Interface: 16001", 1, true))
    assert(toc:find("## SavedVariables: KeystanceDB", 1, true))
    for fn in toc:gmatch("## AddonCompartmentFunc%w*: (%S+)") do
        eq(type(_G[fn]), "function", fn)
    end
end)

test("only one copy runs: a second copy stays off, and the running copy keeps its own data", function()
    local ns1 = wow.load(FILES)
    KeystanceDB = { v = 1, settings = { skin = "classic" }, chars = {} }
    wow.fire("ADDON_LOADED", "Keystance")
    local mine = KeystanceDB
    eq(mine, ns1.db)
    local slashFn, click = SlashCmdList.KEYSTANCE, Keystance_OnAddonCompartmentClick
    -- A dev copy loads next: its files, then its saved data (into the same global), then
    -- its ADDON_LOADED.
    local ns2 = {}
    for _, file in ipairs(FILES) do assert(loadfile(file))("KeystanceDev", ns2) end
    eq(ns2.disabled, true, "the second copy stays off")
    eq(SlashCmdList.KEYSTANCE, slashFn, "/kst still belongs to the running copy")
    eq(Keystance_OnAddonCompartmentClick, click, "so does the minimap menu")
    KeystanceDB = { v = 1, settings = { skin = "elvui" }, chars = {} }
    wow.fire("ADDON_LOADED", "KeystanceDev")
    eq(KeystanceDB, mine, "the running copy's data is what gets saved")
    wow.fire("PLAYER_LOGIN")
    assert(printed():find("two copies are enabled (Keystance and KeystanceDev)", 1, true), printed())
end)

test("every addon file stops at once in a copy that isn't running", function()
    for _, file in ipairs(FILES) do
        if file ~= "Core.lua" and file ~= "Locales.lua" then
            local after = readFile(file):match("\nlocal [%w_]+, ns = %.%.%.\n([^\n]*)")
            assert(after and after:find("^if ns%.disabled then return end"), file .. ": the guard must follow the ns line")
        end
    end
end)

-- Writing a Blizzard global from addon code, even to itself, taints every secure read of
-- it (it broke Esc in Alts Forever). Only our own globals may be assigned.
local OWN_GLOBALS = {
    KeystanceDB = true, KeystanceRunning = true, SLASH_KEYSTANCE1 = true, SLASH_KEYSTANCE2 = true,
    Keystance_OnAddonCompartmentClick = true, Keystance_OnAddonCompartmentEnter = true,
    Keystance_OnAddonCompartmentLeave = true, Keystance_Binding = true, BINDING_HEADER_KEYSTANCE = true,
    BINDING_NAME_KEYSTANCE_NEXT = true, BINDING_NAME_KEYSTANCE_TOGGLE = true,
    BINDING_NAME_KEYSTANCE_PROFILE1 = true, BINDING_NAME_KEYSTANCE_PROFILE2 = true,
    BINDING_NAME_KEYSTANCE_PROFILE3 = true, BINDING_NAME_KEYSTANCE_PROFILE4 = true,
    BINDING_NAME_KEYSTANCE_PROFILE5 = true, BINDING_NAME_KEYSTANCE_PROFILE6 = true,
}

-- The first global the text assigns that it doesn't own, as "line: name", or nil.
function globalWrite(text)
    local locals = {}
    for names in text:gmatch("local[ \t]+([%w_, \t]-)[ \t]*=") do
        for name in names:gmatch("[%w_]+") do locals[name] = true end
    end
    for name in text:gmatch("local%s+function%s+([%w_]+)") do locals[name] = true end
    for names in text:gmatch("local[ \t]+([%w_, \t]+)\n") do -- declared without a value
        for name in names:gmatch("[%w_]+") do locals[name] = true end
    end
    local n, depth = 0, 0 -- depth: how many table constructors { } are open (fields aren't globals)
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        local code = line:gsub("%-%-.*$", "")
        local bare = code:gsub('"[^"]*"', ""):gsub("'[^']*'", "")
        local inTable = depth > 0
        for c in bare:gmatch("[{}]") do depth = depth + (c == "{" and 1 or -1) end
        if not inTable and not code:match("^%s*local%s") then
            -- "Name =" or "A, B =" at the start of a statement.
            local targets = code:match("^%s*([%a_][%w_%s,]-)%s*=[^=]")
            if targets then
                for name in targets:gmatch("[%a_][%w_]*") do
                    if not (locals[name] or OWN_GLOBALS[name]) and name:match("^%u") then return n .. ": " .. name end
                end
            end
            local fnName = code:match("^%s*function%s+([%a_][%w_]*)%s*%(")
            if fnName and not OWN_GLOBALS[fnName] then return n .. ": function " .. fnName end
            if code:find("_G%s*[%.%[][^=]*=[^=]") then return n .. ": _G" end
        end
    end
end

test("no addon file assigns a global it doesn't own", function()
    for _, file in ipairs(FILES) do
        local bad = globalWrite(readFile(file))
        assert(not bad, file .. ":" .. tostring(bad))
    end
end)

test("the no-globals check catches every kind of write to a Blizzard global", function()
    eq(globalWrite("local ADDON, ns = ...\nStaticPopupDialogs = StaticPopupDialogs or {}\n"), "2: StaticPopupDialogs")
    eq(globalWrite("local x\nx, UISpecialFrames = 1, {}\n"), "2: UISpecialFrames")
    eq(globalWrite("function ToggleGameMenu() end\n"), "1: function ToggleGameMenu")
    eq(globalWrite("_G.GameTooltip = nil\n"), "1: _G")
    eq(globalWrite("_G[\"GameTooltip\"] = nil\n"), "1: _G")
    eq(globalWrite("local Frame = 1\nFrame = 2\nif a == b then end\nKeystanceDB = {}\n"), nil, "locals and our own")
    eq(globalWrite("SlashCmdList.KEYSTANCE = f\nUISpecialFrames[#UISpecialFrames + 1] = 'x'\n"), nil,
        "adding a key to a Blizzard table is allowed")
    eq(globalWrite("t.X = {\n    OnAccept = function()\n    end,\n    Text = '{',\n}\nGameTooltip = nil\n"),
        "6: GameTooltip", "table fields are skipped, and the scan picks up again after the table")
end)

-- A Blizzard pop-up menu opened from our window's layout button crashed the beta client
-- inside Blizzard's menu code (2026-09-28). The window uses rows of buttons instead; only
-- the minimap button's right-click keeps Blizzard's menu (as Alts Forever does, without trouble).
test("only the minimap button opens Blizzard's pop-up menus", function()
    for _, file in ipairs(FILES) do
        local code = readFile(file):gsub("%-%-[^\n]*", "")
        if file ~= "Minimap.lua" then
            assert(not code:find("MenuUtil", 1, true), file .. " opens a Blizzard menu")
        end
    end
end)
