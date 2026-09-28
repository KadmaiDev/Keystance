-- Memory and garbage measurements, run outside the game against the fake API.
-- From the addon folder:  luajit tests/perf.lua
-- LuaJIT's numbers are close to, not the same as, WoW's Lua 5.1; use /kst mem in game for
-- the real figure.
package.path = "tests/?.lua;" .. package.path
local wow = require("wow")
local FILES = { "Locales.lua", "Core.lua", "Skins.lua", "Window.lua", "Options.lua", "Minimap.lua" }

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
garbage("entering and leaving combat, window closed", 5000, function()
    wow.enterCombat() wow.leaveCombat()
end)
SlashCmdList.KEYSTANCE("")
garbage("entering and leaving combat, window open", 5000, function()
    wow.enterCombat() wow.leaveCombat()
end)
