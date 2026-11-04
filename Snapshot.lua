-- Keystance's "Before Keystance" snapshot: at a character's first login with Keystance,
-- before Keystance has changed anything, a copy of every action slot, every keybinding and
-- which binding set is in use. Taken once, never overwritten, so a player can always get
-- their original setup back (PLAN.md section 7). Reading only: nothing here changes a
-- bar or a key.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)

local select, time = select, time

-- Every bound command and its keys: { [command] = { "1", "SHIFT-1" } }.
function ns.ReadBindings()
    local binds, count = {}, 0
    for i = 1, GetNumBindings() do
        local command, _, key1 = GetBinding(i)
        if command and key1 then
            binds[command] = { select(3, GetBinding(i)) }
            count = count + 1
        end
    end
    return binds, count
end

-- Bars and keybindings arrive from the game shortly after login, so empty bars mean "not
-- loaded yet" until the tries after entering the world are over; after that they're the
-- player's (a character can have empty bars). Keys always exist once loaded (the game's
-- defaults), so a snapshot is never taken without them: restoring one would unbind every key.
local settled = false

-- Takes the snapshot if this character has none. Returns true once one exists; false means
-- the game hasn't loaded the bars and keys yet, and nothing may change them until it has.
function ns.TakeSnapshot()
    local c = ns.char
    if not c then return false end
    if c.snapshot then return true end
    local slots, nSlots = {}, 0
    for slot = 1, ns.MAX_SLOT do
        local action = ns.DescribeSlot(slot)
        if action then
            slots[slot] = action
            nSlots = nSlots + 1
        end
    end
    local binds, nBinds = ns.ReadBindings()
    if nBinds == 0 or (nSlots == 0 and not settled) then return false end
    c.snapshot = {
        at = time(), set = GetCurrentBindingSet(),
        slots = slots, binds = binds, nSlots = nSlots, nBinds = nBinds,
    }
    -- An open window follows (the guide's first step, Restore), after whatever is running.
    if ns.ProfilesChanged then C_Timer.After(0, ns.ProfilesChanged) end
    return true
end

-- A few tries after entering the world, a few seconds apart.
local TRIES, WAIT = 10, 3
local trying = false
local function Try(n)
    if n >= TRIES then settled = true end
    if ns.TakeSnapshot() or n >= TRIES then
        trying = false
        return
    end
    C_Timer.After(WAIT, function() Try(n + 1) end)
end

ns.On("PLAYER_ENTERING_WORLD", function()
    if trying or (ns.char and ns.char.snapshot) then return end
    trying = true
    C_Timer.After(WAIT, function() Try(1) end)
end)
