-- Keystance profiles: a character's bars and bar keys saved under a name ("Ret", "Prot",
-- "Holy"), applied on request, with one-step undo and a way back to the "Before Keystance"
-- snapshot. Profiles belong to one character (spells differ by class). A profile can also
-- carry gear (Gear.lua): an ItemRack set (p.itemrack) or items of its own (p.gear), which go
-- on first; Undo puts the previous gear back.
--
-- A profile holds action slots 1-180 and the keys of bar buttons (commands that fire an
-- action slot); movement, windows and every other key are never part of it. Applying
-- changes only what differs; anything that can't be set is reported and its slot is left
-- as it was. Every change first records the whole setup, so Undo puts all of it back.
-- In combat, changes wait for combat to end.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)
local L = ns.L

local pairs, ipairs, type, time, next = pairs, ipairs, type, time, next
local GetCursorInfo = GetCursorInfo

local MAX_NAME = 24

local function Print(msg) ns.Print(msg) end

local function Copy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = Copy(v) end
    return c
end

local function Char() return ns.char end

-- A tidy profile name, or nil and why not.
function ns.CleanProfileName(name)
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil, L["A profile needs a name."] end
    if #name > MAX_NAME then return nil, L["Profile names can be up to %d letters."]:format(MAX_NAME) end
    return name
end

-- The character's profiles as a sorted list of names.
function ns.ProfileNames()
    local names = {}
    for name in pairs(Char() and Char().profiles or {}) do names[#names + 1] = name end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

-- Finds a profile by name, ignoring case.
function ns.FindProfile(name)
    name = (name or ""):lower()
    for key in pairs(Char() and Char().profiles or {}) do
        if key:lower() == name then return key end
    end
end

-- The current bars and bar keys as a profile.
local function Capture()
    local state = ns.CurrentState()
    local binds, nBinds = {}, 0
    for command, keys in pairs(state.binds) do
        if ns.IsBarCommand(command) then
            binds[command] = keys
            nBinds = nBinds + #keys
        end
    end
    local nSlots = 0
    for _ in pairs(state.slots) do nSlots = nSlots + 1 end
    local now = time()
    return { slots = state.slots, binds = binds, nSlots = nSlots, nBinds = nBinds, created = now, updated = now }
end

-- Saves the current setup as a profile. Replaces one of that name only if `replace`.
-- Returns the name, or nil and why not.
function ns.SaveProfile(name, replace)
    local c = Char()
    if not c then return nil, L["Not logged in yet."] end
    local clean, why = ns.CleanProfileName(name)
    if not clean then return nil, why end
    local existing = ns.FindProfile(clean)
    if existing and not replace then return nil, L["There's already a profile called %s."]:format(existing) end
    local p = Capture()
    if existing then
        local old = c.profiles[existing]
        p.created, p.gear, p.itemrack = old.created, old.gear, old.itemrack -- Update keeps its gear
        c.profiles[existing] = nil
    end
    c.profiles[clean] = p
    ns.RefreshWindow()
    return clean
end

function ns.RenameProfile(old, new)
    local c = Char()
    local key = ns.FindProfile(old)
    if not key then return nil, L["No profile called %s."]:format(tostring(old)) end
    local clean, why = ns.CleanProfileName(new)
    if not clean then return nil, why end
    local other = ns.FindProfile(clean)
    if other and other ~= key then return nil, L["There's already a profile called %s."]:format(other) end
    c.profiles[clean], c.profiles[key] = c.profiles[key], nil
    if c.active == key then c.active = clean end
    for _, rule in ipairs(c.rules) do
        if rule.profile == key then rule.profile = clean end -- rules follow the rename
    end
    ns.RefreshWindow()
    return clean
end

function ns.DuplicateProfile(name, new)
    local c = Char()
    local key = ns.FindProfile(name)
    if not key then return nil, L["No profile called %s."]:format(tostring(name)) end
    local clean, why = ns.CleanProfileName(new)
    if not clean then return nil, why end
    if ns.FindProfile(clean) then return nil, L["There's already a profile called %s."]:format(ns.FindProfile(clean)) end
    local p = Copy(c.profiles[key])
    p.created, p.updated = time(), time()
    c.profiles[clean] = p
    ns.RefreshWindow()
    return clean
end

-- Sets a profile's gear: items of its own ({ [slot] = item string }, or nil for none), or
-- an ItemRack set by name (nil for none).
function ns.SetProfileGear(name, items)
    local key = ns.FindProfile(name)
    if not key then return nil, L["No profile called %s."]:format(tostring(name)) end
    Char().profiles[key].gear = (items and next(items)) and items or nil
    ns.RefreshWindow()
    return key
end

-- Sets one slot of a profile's own gear (nil: leave that slot alone).
function ns.SetGearSlot(name, slot, item)
    local key = ns.FindProfile(name)
    if not key then return nil, L["No profile called %s."]:format(tostring(name)) end
    local p = Char().profiles[key]
    p.gear = p.gear or {}
    p.gear[slot] = item
    if not next(p.gear) then p.gear = nil end
    ns.RefreshWindow()
    return key
end

function ns.SetProfileItemRack(name, set)
    local key = ns.FindProfile(name)
    if not key then return nil, L["No profile called %s."]:format(tostring(name)) end
    Char().profiles[key].itemrack = set
    ns.RefreshWindow()
    return key
end

function ns.DeleteProfile(name)
    local c = Char()
    local key = ns.FindProfile(name)
    if not key then return nil, L["No profile called %s."]:format(tostring(name)) end
    c.profiles[key] = nil
    if c.active == key then c.active = nil end
    ns.RefreshWindow()
    return key
end

---------------------------------------------------------------------------
-- Applying, undo and restore
---------------------------------------------------------------------------
local function Report(what, slots, keys, failures)
    Print(L["%s (%d slots, %d keys changed)."]:format(what, slots, keys))
    if #failures > 0 then
        Print(L["%d couldn't be set and were left as they were:"]:format(#failures))
        for i = 1, math.min(#failures, 6) do Print("  " .. failures[i]) end
        if #failures > 6 then Print(L["  and %d more."]:format(#failures - 6)) end
    end
end

-- Applies a state now, recording the setup before it for Undo. `done` is said afterwards
-- ("Prot applied"); `undo` names the change for the Undo button ("applying Prot").
-- options.gearChanged says gear is going on too, and options.gearBefore is the gear it
-- replaces, kept for Undo.
local function Change(state, options, done, undo, onDone)
    local c = Char()
    local before = ns.CurrentState()
    local ok, slots, keys, failures = ns.ApplyState(state, options)
    if not ok then
        Print(L["Nothing changed: %s."]:format(slots))
        return false
    end
    if slots + keys > 0 or options.gearChanged then
        c.lastChange = { state = before, gear = options.gearBefore, label = undo, at = time() }
    end
    if onDone then onDone() end
    Report(done, slots, keys, failures)
    ns.RefreshWindow()
    return true
end

ns.ApplyChange = Change

-- Records the setup from before a change made elsewhere (a drop), for Undo.
function ns.RecordChange(before, label)
    local c = Char()
    if c then c.lastChange = { state = before, label = label, at = time() } end
end

-- What the Undo button would undo ("applying Prot"), or nil.
function ns.UndoLabel()
    local c = Char()
    return c and c.lastChange and c.lastChange.label
end

-- Applies a profile, now or after combat: its gear first, then bars and keys. keys = false
-- leaves keys alone ("bars only"); noGear leaves gear alone (a rule switching because the
-- player changed gear mustn't undo that change). While this character shares the account's
-- keybinds, changing keys would change them for every character, so it asks first (owner's
-- decision, PLAN.md) unless `asked`.
function ns.ApplyProfile(name, keys, asked, noGear)
    local c = Char()
    local key = ns.FindProfile(name)
    if not key then return Print(L["No profile called %s. /kst profiles lists them."]:format(tostring(name))) end
    if keys ~= false and not asked and ns.SharedKeybinds() then
        local _, keyChanges = ns.CountChanges(c.profiles[key], "bars")
        if keyChanges > 0 then return ns.AskSharedKeybinds(key) end
    end
    local now = ns.OutOfCombat("apply", function()
        local p = c.profiles[key]
        if not p then return end -- deleted meanwhile
        local gearBefore, gearChanged
        if not noGear then gearBefore, gearChanged = ns.StartProfileGear(p) end
        Change(p, { keys = keys ~= false, scope = "bars", gearBefore = gearBefore, gearChanged = gearChanged },
            L["%s applied"]:format(key), L["applying %s"]:format(key), function() c.active = key end)
    end)
    if not now then Print(L["%s will apply when combat ends."]:format(key)) end
end

-- Puts back the setup from before the last change (a second Undo redoes it).
function ns.Undo()
    local c = Char()
    if not (c and c.lastChange) then return Print(L["Nothing to undo."]) end
    local now = ns.OutOfCombat("apply", function()
        local last = c.lastChange
        if not last then return end
        -- The gear from before goes back on (kept for a second Undo in turn).
        local gearBefore, gearChanged
        if last.gear and ns.GearChanges(last.gear) > 0 and not GetCursorInfo() then
            local slots = {}
            for slot in pairs(last.gear) do slots[slot] = true end
            gearBefore = ns.CaptureGear(slots)
            local ok, why = ns.EquipGear(last.gear, ns.GearReport)
            gearChanged = ok
            if not ok then Print(L["Gear not changed: %s."]:format(why)) end
        end
        Change(last.state, { scope = "all", gearBefore = gearBefore, gearChanged = gearChanged },
            L["Undid %s"]:format(last.label), L["the undo"], function() c.active = nil end)
    end)
    if not now then Print(L["Undo will happen when combat ends."]) end
end

-- Puts back the bars and every key as they were before Keystance (undoable).
function ns.RestoreOriginal()
    local c = Char()
    if not (c and c.snapshot) then return Print(L["Your original setup hasn't been saved yet."]) end
    local now = ns.OutOfCombat("apply", function()
        Change(c.snapshot, { scope = "all" }, L["Your original setup is back"], L["restoring your original setup"],
            function() c.active = nil end)
    end)
    if not now then Print(L["Your original setup will come back when combat ends."]) end
end

---------------------------------------------------------------------------
-- Account-wide keybinds
---------------------------------------------------------------------------
-- True while this character uses the keybinds shared by the whole account.
function ns.SharedKeybinds()
    return GetCurrentBindingSet() == 1
end

-- Gives this character its own keybinds: the current ones are copied, so nothing changes
-- on screen, and the account's set (what other characters use) is left untouched.
-- SaveBindings(2) does this (measured 2026-09-28: every bind kept, survives relog).
function ns.UseOwnKeybinds()
    if not ns.SharedKeybinds() then return Print(L["This character already has its own keybinds."]) end
    local now = ns.OutOfCombat("ownkeys", function()
        SaveBindings(2)
        Print(L["This character now has its own keybinds. Your other characters keep theirs."])
        ns.RefreshWindow()
    end)
    if not now then Print(L["This character gets its own keybinds when combat ends."]) end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
ns.AddCommand("save", function(arg)
    local name, why = ns.SaveProfile(arg)
    if not name and ns.FindProfile(arg) then
        return Print(why .. " " .. L["Use the Profiles tab's Update button to replace it."])
    end
    Print(name and L["Saved your bars and keys as %s."]:format(name) or why)
end)

ns.AddCommand("apply", function(arg) ns.ApplyProfile(arg) end)
ns.AddCommand("undo", function() ns.Undo() end)
ns.AddCommand("restore", function() ns.ConfirmRestore() end)
ns.AddCommand("ownkeys", function() ns.UseOwnKeybinds() end)
ns.AddCommand("profiles", function()
    local names = ns.ProfileNames()
    if #names == 0 then return Print(L["No profiles yet. /kst save Name saves your current bars and keys."]) end
    Print(L["Profiles: %s"]:format(table.concat(names, ", ")))
end)

---------------------------------------------------------------------------
-- Dialogs. Each is added to Blizzard's StaticPopupDialogs the first time it's needed, and
-- never by assigning the global itself (that taints it).
---------------------------------------------------------------------------
local function Dialog(which, def)
    if not StaticPopupDialogs[which] then
        def.timeout, def.whileDead, def.hideOnEscape, def.preferredIndex = 0, true, true, 3
        StaticPopupDialogs[which] = def
    end
end

-- The text typed into a dialog's box (the field's name differs between client versions).
local function Typed(dialog)
    local box = dialog.editBox or dialog.EditBox or (dialog.GetEditBox and dialog:GetEditBox())
    return box and box:GetText() or ""
end

-- Asks what to do when a profile would change keybinds shared by every character.
function ns.AskSharedKeybinds(name)
    Dialog("KEYSTANCE_SHARED_KEYS", {
        text = L["Your keybinds are shared by all your characters, so %s would change them for everyone.\n\nKeystance recommends giving this character its own keybinds first: nothing changes on screen, and your other characters keep theirs."],
        button1 = L["Own keybinds, then apply"],
        button2 = CANCEL or "Cancel",
        button3 = L["Bars only"],
        OnAccept = function(_, data)
            ns.UseOwnKeybinds()
            ns.ApplyProfile(data, nil, true)
        end,
        OnAlt = function(_, data) ns.ApplyProfile(data, false) end,
    })
    StaticPopup_Show("KEYSTANCE_SHARED_KEYS", name, nil, name)
end

-- Asks before putting the original setup back.
function ns.ConfirmRestore()
    local c = Char()
    if not (c and c.snapshot) then return Print(L["Your original setup hasn't been saved yet."]) end
    Dialog("KEYSTANCE_RESTORE", {
        text = L["Put your bars and every keybind back as they were before Keystance (saved %s)?\n\nYou can undo this."],
        button1 = L["Restore"],
        button2 = CANCEL or "Cancel",
        OnAccept = function() ns.RestoreOriginal() end,
    })
    StaticPopup_Show("KEYSTANCE_RESTORE", date("%d %b %Y", c.snapshot.at))
end

function ns.ConfirmDelete(name)
    Dialog("KEYSTANCE_DELETE", {
        text = L["Delete the profile %s? Your bars and keys stay as they are."],
        button1 = DELETE or "Delete",
        button2 = CANCEL or "Cancel",
        OnAccept = function(_, data)
            local ok, why = ns.DeleteProfile(data)
            Print(ok and L["Deleted %s."]:format(ok) or why)
        end,
    })
    StaticPopup_Show("KEYSTANCE_DELETE", name, nil, name)
end

-- Asks for a name, then calls fn(name); `text` says what it's for.
local nameHandler
local function NameAccepted(dialog)
    local fn = nameHandler
    nameHandler = nil
    if fn then fn(Typed(dialog)) end
end
function ns.AskName(text, fn, default)
    Dialog("KEYSTANCE_NAME", {
        text = "%s",
        button1 = OKAY or "OK",
        button2 = CANCEL or "Cancel",
        hasEditBox = true,
        maxLetters = MAX_NAME,
        OnAccept = NameAccepted,
        EditBoxOnEnterPressed = function(box)
            local dialog = box:GetParent()
            NameAccepted(dialog)
            dialog:Hide()
        end,
        EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
        OnShow = function(dialog)
            local box = dialog.editBox or dialog.EditBox or (dialog.GetEditBox and dialog:GetEditBox())
            if box then
                box:SetText(dialog.data or "")
                box:SetFocus()
                box:HighlightText()
            end
        end,
    })
    nameHandler = fn
    StaticPopup_Show("KEYSTANCE_NAME", text, nil, default or "")
end

-- New profile from the current setup: asks for a name; asks before replacing one.
function ns.NewProfile()
    ns.AskName(L["Name the profile (for example Ret, Prot or Holy):"], function(name)
        local saved, why = ns.SaveProfile(name)
        Print(saved and L["Saved your bars and keys as %s."]:format(saved) or why)
    end)
end

function ns.AskRename(name)
    ns.AskName(L["New name for %s:"]:format(name), function(new)
        local ok, why = ns.RenameProfile(name, new)
        Print(ok and L["Renamed %s to %s."]:format(name, ok) or why)
    end, name)
end

function ns.AskDuplicate(name)
    ns.AskName(L["Name for the copy of %s:"]:format(name), function(new)
        local ok, why = ns.DuplicateProfile(name, new)
        Print(ok and L["Copied %s as %s."]:format(name, ok) or why)
    end, name .. " 2")
end

-- Replaces a profile with the current setup, after asking.
function ns.ConfirmUpdate(name)
    Dialog("KEYSTANCE_UPDATE", {
        text = L["Replace %s with your bars and keys as they are now?"],
        button1 = L["Replace"],
        button2 = CANCEL or "Cancel",
        OnAccept = function(_, data)
            local ok, why = ns.SaveProfile(data, true)
            Print(ok and L["Updated %s from your current setup."]:format(ok) or why)
        end,
    })
    StaticPopup_Show("KEYSTANCE_UPDATE", name, nil, name)
end
