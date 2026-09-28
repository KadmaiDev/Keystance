-- Memory and garbage measurements, run outside the game against the fake API.
-- From the addon folder:  luajit tests/perf.lua
-- LuaJIT's numbers are close to, not the same as, WoW's Lua 5.1; use /kst mem in game for
-- the real figure.
package.path = "tests/?.lua;" .. package.path
local wow = require("wow")
local FILES = { "Locales.lua", "Core.lua", "Skins.lua", "Actions.lua", "Snapshot.lua", "Apply.lua", "Profiles.lua", "Layouts.lua", "Window.lua",
    "Keyboard.lua", "Bars.lua", "ProfilesTab.lua", "Options.lua", "Minimap.lua" }

local function out(fmt, ...) io.write(fmt:format(...), "\n") end
local function settle()
    collectgarbage("collect")
    collectgarbage("collect")
    return collectgarbage("count")
end

-- Bytes of garbage per call of fn, averaged over n calls, with the collector stopped.
local function garbage(name, n, fn)
    fn(1) -- warm caches
    settle()
    collectgarbage("stop")
    local before = collectgarbage("count")
    for i = 1, n do fn(i) end
    local used = (collectgarbage("count") - before) * 1024 / n
    collectgarbage("restart")
    out("  %-44s %6.0f bytes/call", name, used)
end

-- Loads the addon into a fresh fake API and returns the memory it added. LuaJIT grows its
-- tables in steps, so take the median of several. (The window isn't measured yet: with only
-- placeholder pages its size is lost in LuaJIT's noise.)
local function measure()
    wow.load({})
    local before = settle()
    local ns = {}
    for _, file in ipairs(FILES) do assert(loadfile(file))("Keystance", ns) end
    wow.fire("ADDON_LOADED", "Keystance")
    wow.fire("PLAYER_LOGIN")
    return settle() - before
end

local function median(list)
    table.sort(list)
    return list[(#list + 1) / 2 - ((#list + 1) / 2) % 1], list[1], list[#list]
end
local loaded = {}
measure() -- warm up
for i = 1, 9 do loaded[i] = measure() end

out("Memory (median of 9, with range; /kst mem in game is the real figure)")
out("  addon, logged in, window never opened:  %6.1f KB  (%.0f-%.0f)", median(loaded))

out("")
out("Garbage per call (only allocations by the addon itself)")
-- A full setup: 60 slots in use and 40 keys bound, logged in with the snapshot taken.
local function setup()
    wow.spellbook = { { name = "Class", spells = {} } }
    for i = 1, 60 do
        wow.spellbook[1].spells[i] = { 1000 + i, "Spell " .. i, "Rank 1" }
        wow.slots[i] = { kind = "spell", id = 1000 + i }
    end
    local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "Q", "E", "R", "T", "F", "G", "Z", "X", "C", "V" }
    for i, key in ipairs(keys) do
        wow.bindings[key] = "ACTIONBUTTON" .. ((i - 1) % 12 + 1)
        wow.bindings["SHIFT-" .. key] = "MULTIACTIONBAR1BUTTON" .. ((i - 1) % 12 + 1)
    end
end
wow.load({})
setup()
local ns = {}
for _, file in ipairs(FILES) do assert(loadfile(file))("Keystance", ns) end
-- Blizzard's main bar and bottom-left bar on screen.
CreateFrame("Frame", "MainActionBar")
CreateFrame("Frame", "MultiBarBottomLeft")
for i = 1, 12 do
    CreateFrame("Button", "ActionButton" .. i).action = i
    CreateFrame("Button", "MultiBarBottomLeftButton" .. i).action = 60 + i
end
wow.fire("ADDON_LOADED", "Keystance")
wow.fire("PLAYER_LOGIN")
wow.fire("PLAYER_ENTERING_WORLD", true, false)
wow.runTimers()
wow.timers = {}

-- The fake API allocates where the real one doesn't (GetBindingKey builds and sorts a
-- list); make it free first so only the addon's own garbage is counted.
local firstKey = {}
for key, cmd in pairs(wow.bindings) do
    if not firstKey[cmd] or key < firstKey[cmd] then firstKey[cmd] = key end
end
GetBindingKey = function(cmd) return firstKey[cmd] end

out(" window closed (what runs while you play):")
garbage("  entering and leaving combat", 5000, function() wow.enterCombat() wow.leaveCombat() end)
garbage("  a modifier key pressed", 5000, function() wow.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1) end)
garbage("  an action bar slot changed", 5000, function() wow.fire("ACTIONBAR_SLOT_CHANGED", 1) end)
garbage("  keybindings changed", 5000, function() wow.fire("UPDATE_BINDINGS") end)

out(" window open:")
SlashCmdList.KEYSTANCE("")
ns.ShowTab("keyboard")
garbage("  Keyboard tab redrawn (74 keys)", 2000, function() ns.RefreshWindow() end)
ns.ShowTab("bars")
garbage("  Bars tab redrawn (2 bars)", 2000, function() ns.RefreshWindow() end)
