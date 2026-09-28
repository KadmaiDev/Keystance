-- Test runner. From the addon folder: luajit tests/run.lua
package.path = "tests/?.lua;" .. package.path
wow = require("wow")

FILES = { "Locales.lua", "Core.lua", "Skins.lua", "Actions.lua", "Snapshot.lua", "Apply.lua", "Profiles.lua", "Layouts.lua", "Window.lua",
    "Keyboard.lua", "Bars.lua", "ProfilesTab.lua", "Options.lua", "Minimap.lua" }
tests, passed, failed = {}, 0, 0

function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

function eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

-- Loads the addon and logs in; returns the namespace.
function start(saved)
    local ns = wow.load(FILES)
    wow.login(saved)
    return ns
end

function slash(msg) SlashCmdList.KEYSTANCE(msg or "") end

-- Everything printed so far, as one string.
function printed() return table.concat(wow.printed, "\n") end

-- The tests themselves, by area. Top-level helpers are shared between files, so no name
-- may be defined in two of them: checked before loading.
CASES = {
    "01_core.lua",
    "02_combat.lua",
    "03_window.lua",
    "04_skins.lua",
    "05_minimap.lua",
    "06_files.lua",
    "07_options.lua",
    "08_snapshot.lua",
    "09_keyboard.lua",
    "10_bars.lua",
    "11_profiles.lua",
    "12_profiles_tab.lua",
}
do
    local where = {}
    for _, file in ipairs(CASES) do
        for line in io.lines("tests/cases/" .. file) do
            local name = line:match("^function ([%w_]+)") or line:match("^([%a_][%w_]*) =")
            if name then
                assert(not where[name] or where[name] == file,
                    "helper '" .. name .. "' is defined in both " .. tostring(where[name]) .. " and " .. file)
                where[name] = file
            end
        end
    end
end
for _, file in ipairs(CASES) do
    assert(loadfile("tests/cases/" .. file))()
end

---------------------------------------------------------------------------
for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then
        passed = passed + 1
        io.write("  ok    ", t.name, "\n")
    else
        failed = failed + 1
        io.write("  FAIL  ", t.name, "\n        ", tostring(err), "\n")
    end
end
io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
