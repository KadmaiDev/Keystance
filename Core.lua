-- Keystance core: saved data, character identity, event dispatch, the combat queue and
-- slash commands.
local ADDON, ns = ...
local L = ns.L

-- Only one copy of Keystance may run (e.g. the CurseForge copy and a dev copy both
-- enabled). Addons load one at a time, so a copy that finds another already running stays
-- off: every file stops here, before touching any global, event or hook, and it says so at
-- login. Both copies keep their data in the same global, KeystanceDB, so the running copy
-- also puts its own data back when the other copy's saved data replaces it (below).
if KeystanceRunning then
    ns.disabled = true
    local running = KeystanceRunning
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        print("|cff66ccffKeystance|r: " .. L["two copies are enabled (%s and %s). Only %s is running; disable one of them in the AddOns list."]
            :format(running, ADDON, running))
    end)
    return
end
KeystanceRunning = ADDON

local DB_VERSION = 1

-- Builders for the window's tabs, by tab key: fn(page, window). Filled by the tab files.
ns.pageBuilders = {}

local pcall, type, pairs, ipairs, print = pcall, type, pairs, ipairs, print
local issecretvalue = issecretvalue or function() return false end
local UnitName, UnitClass, InCombatLockdown = UnitName, UnitClass, InCombatLockdown

---------------------------------------------------------------------------
-- Events: one frame dispatches to every handler registered for an event
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}

-- Registering an event this client doesn't know throws on Forever, so guard it.
-- Several handlers can listen to one event; they run in the order added, each on its own:
-- an error in one is reported (BugGrabber) and doesn't stop the others.
function ns.On(event, fn)
    if not pcall(frame.RegisterEvent, frame, event) then return false end
    local list = handlers[event]
    if not list then
        list = {}
        handlers[event] = list
    end
    list[#list + 1] = fn
    return true
end

-- Removes every handler for the event.
function ns.Off(event)
    handlers[event] = nil
    frame:UnregisterEvent(event)
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do xpcall(list[i], geterrorhandler(), ...) end
end)

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
-- Settings every account starts with. Missing ones are filled in at load; a player's own
-- choices are never replaced.
local DEFAULTS = {
    skin = "auto", -- "auto" (EllesmereUI, then ElvUI, then classic), "classic", "ellesmere", "elvui"
    layout = "auto", -- keyboard drawn: "auto" (UK for an English (UK) client, else US), "ansi", "iso"
}

-- UPGRADES[v] turns version v data into version v + 1 in place. Saved data is repaired,
-- never reset: players' profiles and snapshots must survive every update.
local UPGRADES = {}

function ns.InitDB(saved)
    if type(saved) ~= "table" then saved = {} end
    saved.v = saved.v or DB_VERSION
    while saved.v < DB_VERSION and UPGRADES[saved.v] do
        UPGRADES[saved.v](saved)
        saved.v = saved.v + 1
    end
    if type(saved.settings) ~= "table" then saved.settings = {} end
    for k, v in pairs(DEFAULTS) do
        if saved.settings[k] == nil then saved.settings[k] = v end
    end
    if type(saved.chars) ~= "table" then saved.chars = {} end
    return saved
end

-- The logged-in character's full name. Build 70009 returns it as UnitName's two values
-- ("Vespera", "Ashward"); earlier builds returned the full name as the first value.
function ns.PlayerName()
    local first, surname = UnitName("player")
    if surname and not issecretvalue(surname) and surname ~= "" then
        return first .. " " .. surname
    end
    return first
end

-- Characters are keyed by full name ("First Last"), which is unique: Forever has no realms.
function ns.InitChar(db, name, class)
    local c = db.chars[name]
    if type(c) ~= "table" then
        c = {}
        db.chars[name] = c
    end
    c.class = class
    if type(c.profiles) ~= "table" then c.profiles = {} end
    if type(c.rules) ~= "table" then c.rules = {} end
    return c
end

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then
        -- Another copy's saved data just loaded into the shared global: keep ours.
        if ns.db and KeystanceDB ~= ns.db then KeystanceDB = ns.db end
        return
    end
    KeystanceDB = ns.InitDB(KeystanceDB)
    ns.db = KeystanceDB
    -- Before login, so EllesmereUI's minimap finds it when it collects addon buttons.
    ns.CreateMinimapButton()
end)

ns.On("PLAYER_LOGIN", function()
    ns.Off("PLAYER_LOGIN")
    local _, class = UnitClass("player")
    ns.charKey = ns.PlayerName()
    ns.char = ns.InitChar(ns.db, ns.charKey, class)
end)

---------------------------------------------------------------------------
-- Combat: changing bars and keys is blocked in combat (it fires ADDON_ACTION_BLOCKED, which
-- players see as an error), so such work never runs then. It waits here and runs as soon
-- as combat ends, in the order it was asked for.
---------------------------------------------------------------------------
local queued, order = {}, {}

local combatStarted = false
function ns.InCombat()
    return (combatStarted or InCombatLockdown()) and true or false
end
ns.On("PLAYER_REGEN_DISABLED", function() combatStarted = true end)
ns.On("PLAYER_REGEN_ENABLED", function() combatStarted = false end)

-- Runs fn now if out of combat and returns true; otherwise runs it after combat and returns
-- false. Work queued again under the same key replaces the earlier request (the latest
-- profile asked for wins) but keeps its place.
function ns.OutOfCombat(key, fn)
    if not InCombatLockdown() then
        fn()
        return true
    end
    if not queued[key] then order[#order + 1] = key end
    queued[key] = fn
    return false
end

-- Drops the work waiting under this key (a switch the player changed their mind about).
function ns.CancelWaiting(key)
    if not queued[key] then return false end
    queued[key] = nil
    for i = #order, 1, -1 do
        if order[i] == key then table.remove(order, i) end
    end
    return true
end

-- True while work under this key (or any key, without one) waits for combat to end.
function ns.Waiting(key)
    if key then return queued[key] ~= nil end
    return #order > 0
end

-- Runs the waiting work in order, each job taken off the queue before it runs, so one that
-- fails (reported, not hidden) can't jam the rest. A job may queue more: if combat started
-- again, that waits for the next end.
ns.On("PLAYER_REGEN_ENABLED", function()
    while order[1] and not InCombatLockdown() do
        local key = table.remove(order, 1)
        local fn = queued[key]
        queued[key] = nil
        if fn then xpcall(fn, geterrorhandler()) end
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function Print(msg)
    print("|cff66ccffKeystance|r: " .. msg)
end
ns.Print = Print

-- Adds one of Keystance's pop-ups to Blizzard's StaticPopupDialogs the first time it's
-- needed (never assigning the table itself: that taints it), with the settings they share.
function ns.Dialog(which, def)
    if not StaticPopupDialogs[which] then
        def.timeout, def.whileDead, def.hideOnEscape, def.preferredIndex = 0, true, true, 3
        StaticPopupDialogs[which] = def
    end
    return StaticPopupDialogs[which]
end

-- Where everyday messages go ("Prot applied", "Gear: 3 items put on"): "screen" (the
-- default: briefly at the top of the screen, where the game's own notices fade), "chat" or
-- "quiet". Problems, and answers to /kst commands, always use ns.Print (chat).
function ns.MessagesMode()
    return ns.db and ns.db.settings.messages or "screen"
end

function ns.Notify(msg)
    local mode = ns.MessagesMode()
    if mode == "quiet" then return end
    if mode == "screen" and UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage("Keystance: " .. msg, 1, 0.82, 0)
        return
    end
    Print(msg)
end

local commands = {}

function commands.minimap()
    ns.SetMinimapButton(not ns.MinimapButtonOn())
    Print(ns.MinimapButtonOn() and L["Minimap button shown."] or L["Minimap button hidden. /kst minimap brings it back."])
end

function commands.skin(arg)
    arg = arg:lower()
    if arg == "" then
        return Print(L["Look: %s (in use: %s). Choose with /kst skin auto | classic | ellesmere | elvui"]
            :format(ns.db.settings.skin, ns.SkinName()))
    end
    if not ns.ChooseSkin(arg) then
        return Print(L["Unknown look '%s'. Choose auto, classic, ellesmere or elvui."]:format(arg))
    end
end

function commands.options()
    ns.OpenOptions()
end

function commands.mem()
    UpdateAddOnMemoryUsage()
    Print(L["Memory: %.1f KB"]:format(GetAddOnMemoryUsage(ADDON)))
end

function commands.help()
    Print(L["by Kadmai. /kst opens Keystance. Profiles: /kst save Name | apply Name | undo | restore | profiles | ownkeys | ranks | auto on/off"])
    Print(L["Also: /kst switcher on/off/lock | guide | options | minimap | skin | mem | help"])
    Print(L["Or use the minimap button (right-click for options)."])
end
ns.ShowHelp = commands.help

-- For the menus: runs a slash command by name.
function ns.RunCommand(name, arg)
    commands[name](arg or "")
end

-- Lets other files add a slash command (/kst name args).
function ns.AddCommand(name, fn)
    commands[name] = fn
end

commands[""] = function() ns.ToggleWindow() end

SLASH_KEYSTANCE1, SLASH_KEYSTANCE2 = "/kst", "/keystance"
SlashCmdList.KEYSTANCE = function(msg)
    local cmd, arg = msg:match("^%s*(%S*)%s*(.-)%s*$")
    local fn = commands[cmd:lower()] or commands.help
    fn(arg)
end
