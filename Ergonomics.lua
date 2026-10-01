-- Keystance reach: how easy each key is to press while your hand rests on your movement
-- keys, as a comfort score from 0 (far) to 100 (easy), for the Keyboard tab's heat map.
-- No UI here: the scores come from the keyboard layouts (Layouts.lua) and your movement
-- keybinds, and are worked out again only when either changes.
--
-- The model: fingers rest on the movement keys (read from your bindings; WASD if they
-- aren't on the drawn keyboard): the index finger on strafe right, the middle finger on
-- forward and back, the ring finger on strafe left, the pinky one key further left. A
-- key's effort is its distance from the nearest finger, weighted by how strong that finger
-- is (the pinky least), plus a cost for keys the hand has to leave the movement keys to
-- reach, and for the function row. Shift, Ctrl and Alt add their own cost. Mouse side
-- buttons are easy; the right side of the keyboard, the arrows and the numpad are far
-- (that hand is on the mouse). Worded as comfort and reach, never "bad keybinds".
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)
local L = ns.L

local ipairs, pairs, math = ipairs, pairs, math
local GetBindingKey = GetBindingKey

-- Tuning, in key units.
local FINGERS = {             -- weight per unit of distance: stronger fingers cost less
    { "index", 1.0 }, { "middle", 1.15 }, { "ring", 1.45 }, { "pinky", 1.7 },
}
local REACH = 2.5             -- right of the index finger by more than this, the hand leaves movement
local LEAVE_COST = 1.0        -- per key unit beyond that
local UP = 0.85               -- reaching up a row is a little easier than across
local FROW_COST = 0.6         -- the function row, a little apart from the rest
local FREE = 0.5              -- effort this small is as easy as it gets
local PER_UNIT = 26           -- comfort lost per unit of effort beyond FREE
local MOD_COST = { SHIFT = 8, CTRL = 16, ALT = 11 }
local MOUSE = { BUTTON4 = 92, BUTTON5 = 88, BUTTON3 = 72, MOUSEWHEELUP = 82, MOUSEWHEELDOWN = 82 }
local FAR = 5                 -- the navigation block and numpad: the mouse hand's side

-- The levels the heat map shows, easiest first: the lowest score in each, a name, a colour.
ns.REACH_LEVELS = {
    { 75, L["Easy to reach"], 0.2, 0.72, 0.3 },
    { 55, L["Fine"], 0.72, 0.72, 0.2 },
    { 35, L["A stretch"], 0.9, 0.5, 0.15 },
    { 0, L["Far"], 0.78, 0.2, 0.2 },
}
local MOVEMENT_COLOUR = { 0.3, 0.45, 0.8 }

-- Where each key sits, in key units from the top-left, and its row: { [key] = { x, y } }.
-- The left-most copy of a key drawn twice (Shift, Ctrl, Alt).
local positions = {}
local function Positions(layoutKey)
    local pos = positions[layoutKey]
    if pos then return pos end
    pos = {}
    local layout = ns.LAYOUTS[layoutKey]
    for r, row in ipairs(layout.rows or {}) do
        local x = 0
        local y = (r - 1) + (r > 1 and 0.25 or 0) -- the function row sits apart
        for _, info in ipairs(row) do
            x = x + (info.gap or 0)
            local w = info.w or 1
            if info[1] ~= "" and not pos[info[1]] then pos[info[1]] = { x + w / 2, y, row = r } end
            x = x + w
        end
    end
    positions[layoutKey] = pos
    return pos
end

-- The movement keys: forward, back, left and right, from the bindings (strafing, or turning
-- if the character turns with the keys), on the drawn keyboard. Nil if they aren't there.
local MOVES = {
    forward = { "MOVEFORWARD" }, back = { "MOVEBACKWARD" },
    left = { "STRAFELEFT", "TURNLEFT" }, right = { "STRAFERIGHT", "TURNRIGHT" },
}
local function BoundKeyOn(pos, commands)
    for _, command in ipairs(commands) do
        local keys = { GetBindingKey(command) }
        for _, key in ipairs(keys) do
            if type(key) == "string" and pos[key] and not key:find("-", 2, true) then return key end
        end
    end
end
local WASD = { forward = "W", back = "S", left = "A", right = "D" }
local function Movement(pos)
    local found = {}
    for part, commands in pairs(MOVES) do
        found[part] = BoundKeyOn(pos, commands)
        if not found[part] then return WASD, false end
    end
    -- Only a left-hand cluster: movement on the arrows or the right side isn't modelled.
    if pos[found.right][1] > 8 then return WASD, false end
    return found, true
end

-- From a finger's home to a key: rows above cost a little less than the same distance across.
-- Where a key sits: { x, y } in key units, or nil.
function ns.KeyPosition(layoutKey, key) return Positions(layoutKey)[key] end

local function Distance(key, home)
    local dx, dy = key[1] - home[1], key[2] - home[2]
    if dy < 0 then dy = dy * UP end
    return math.sqrt(dx * dx + dy * dy)
end

-- Every key's comfort on its own (no modifier), for a layout: { scores = { [key] = 0-100 },
-- movement = { [key] = true }, keys = the movement keys, fromBinds = true if read from the
-- bindings }. Cached until bindings change.
local cache = {}
function ns.ReachMap(layoutKey)
    local map = cache[layoutKey]
    if map then return map end
    local pos = Positions(layoutKey)
    local keys, fromBinds = Movement(pos)
    local left, right = pos[keys.left], pos[keys.right]
    local homes = {
        index = { right }, middle = { pos[keys.forward], pos[keys.back] }, ring = { left },
        pinky = { { left[1] - 1, left[2] } },
    }
    local scores, movement = {}, {}
    for _, part in pairs({ "forward", "back", "left", "right" }) do movement[keys[part]] = true end
    for key, p in pairs(pos) do
        local effort = math.huge
        for _, f in ipairs(FINGERS) do
            for _, home in ipairs(homes[f[1]]) do
                effort = math.min(effort, Distance(p, home) * f[2])
            end
        end
        local beyond = p[1] - right[1] - REACH
        if beyond > 0 then effort = effort + beyond * LEAVE_COST end
        if p.row == 1 then effort = effort + FROW_COST end
        if key == "SPACE" then effort = 0 end -- the thumb's own key
        scores[key] = math.max(0, math.min(100, math.floor(100 - math.max(0, effort - FREE) * PER_UNIT + 0.5)))
    end
    for key, score in pairs(MOUSE) do scores[key] = score end
    for _, list in ipairs({ ns.NAV_KEYS, ns.NUMPAD_KEYS }) do
        for _, info in ipairs(list) do scores[info[1]] = FAR end
    end
    map = { scores = scores, movement = movement, keys = keys, fromBinds = fromBinds }
    cache[layoutKey] = map
    return map
end

-- A key's comfort in a modifier layer ("SHIFT-", "CTRL-SHIFT-"...): nil for a key the map
-- doesn't know. Mouse buttons pay half for a modifier (the other hand holds it).
function ns.KeyReach(layoutKey, key, prefix)
    local base = ns.ReachMap(layoutKey).scores[key]
    if not base then return nil end
    local cost = 0
    if prefix ~= "" then
        for mod, c in pairs(MOD_COST) do
            if prefix:find(mod, 1, true) then cost = cost + c end
        end
        if MOUSE[key] then cost = cost / 2 end
    end
    return math.max(0, base - math.floor(cost + 0.5))
end

-- The level for a score: its index in REACH_LEVELS, name and colour.
function ns.ReachLevel(score)
    for i, level in ipairs(ns.REACH_LEVELS) do
        if score >= level[1] then return i, level[2], level[3], level[4], level[5] end
    end
end

function ns.MovementColour() return MOVEMENT_COLOUR[1], MOVEMENT_COLOUR[2], MOVEMENT_COLOUR[3] end

-- What the heat map's colours mean, and where reach is measured from: "Reach from
-- W A S D: Easy to reach · Fine · A stretch · Far" in their colours. Cached with the map.
local function Hex(r, g, b) return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255) end
function ns.ReachLegend(layoutKey)
    local map = ns.ReachMap(layoutKey)
    if map.legend then return map.legend end
    local k = map.keys
    local parts = {}
    for _, level in ipairs(ns.REACH_LEVELS) do parts[#parts + 1] = Hex(level[3], level[4], level[5]) .. level[2] .. "|r" end
    parts[#parts + 1] = Hex(MOVEMENT_COLOUR[1], MOVEMENT_COLOUR[2], MOVEMENT_COLOUR[3]) .. L["Movement"] .. "|r"
    local from = L["Reach from %s:"]:format(table.concat({ k.forward, k.left, k.back, k.right }, " "))
    if not map.fromBinds then
        from = L["Your movement keys aren't on this keyboard, so reach is from W A S D:"]
    end
    map.legend = from .. " " .. table.concat(parts, " · ")
    return map.legend
end

---------------------------------------------------------------------------
-- Moving the hand: every keybind in the left-hand block one key right (or left), so they
-- all stay where they were for the fingers. Per keyboard row (numbers, Tab, Caps, Shift
-- rows), the keys from the left edge to the hand's reach, plus one: the column pushed off
-- that edge wraps round to the freed left edge, so no keybind is lost. Left from E S D F
-- uses the same block as right from W A S D, so one undoes the other exactly.
---------------------------------------------------------------------------
local SHIFT_ROWS = { 2, 3, 4, 5 } -- the layout rows: numbers, Tab row, Caps row, Shift row
local MOST_RIGHT = 7              -- the strafe-right key no further right than this (G)

-- The block's keys per row, left to right, for a hand whose strafe-right key is at `rightX`.
local function Block(layoutKey, rightX)
    local layout = ns.LAYOUTS[layoutKey]
    local limit = rightX + REACH
    local rows = {}
    for _, r in ipairs(SHIFT_ROWS) do
        local list, x = {}, 0
        for _, info in ipairs(layout.rows[r] or {}) do
            x = x + (info.gap or 0)
            local w = info.w or 1
            if info[1] ~= "" and not info.mod then
                list[#list + 1] = info[1]
                if x + w / 2 > limit then break end -- the edge column, then stop
            end
            x = x + w
        end
        rows[#rows + 1] = list
    end
    return rows
end

-- The key each key's binds move to, one key right (dir 1) or left (dir -1): { [key] = key },
-- or nil and why. `right` is the strafe-right key to move from (the bound one by default).
function ns.HandShiftMap(layoutKey, dir, right)
    local layout = ns.LAYOUTS[layoutKey]
    if not (layout and layout.rows) then return nil, L["only on a keyboard"] end
    local map = ns.ReachMap(layoutKey)
    if not map.fromBinds and not right then return nil, L["your movement keys aren't on the left of this keyboard"] end
    local pos = Positions(layoutKey)
    local at = pos[right or map.keys.right]
    if not at then return nil, L["your movement keys aren't on the left of this keyboard"] end
    if dir > 0 and at[1] > MOST_RIGHT then return nil, L["your hand can't go further right"] end
    if dir < 0 and right == nil then
        -- Not past the left edge: after moving, strafe left still needs a key to its left
        -- for the pinky, so it must have two now (A in E S D F; not A in W A S D).
        local n = 0
        for _, info in ipairs(layout.rows[4]) do
            if info[1] == map.keys.left then break end
            if info[1] ~= "" and not info.mod then n = n + 1 end
        end
        if n < 2 then return nil, L["your hand can't go further left"] end
    end
    -- The same block either way: the one for the hand in its left-hand position.
    local rows = Block(layoutKey, dir > 0 and at[1] or at[1] - 1)
    local to = {}
    for _, list in ipairs(rows) do
        local n = #list
        for i, key in ipairs(list) do
            if dir > 0 then to[key] = list[i % n + 1] else to[key] = list[(i - 2) % n + 1] end
        end
    end
    return to
end

-- True if the hand can move that way (1 right, -1 left) from where the movement keys are
-- now, on the keyboard drawn. Kept with the reach map (redraws make no garbage).
function ns.CanShiftHand(dir)
    local layoutKey = ns.LayoutKey(ns.db.settings.layout)
    if not (ns.LAYOUTS[layoutKey] and ns.LAYOUTS[layoutKey].rows) then return false end
    local map = ns.ReachMap(layoutKey)
    map.canShift = map.canShift or {}
    if map.canShift[dir] == nil then map.canShift[dir] = ns.HandShiftMap(layoutKey, dir) ~= nil end
    return map.canShift[dir]
end

-- Movement keys may have moved.
ns.On("UPDATE_BINDINGS", function()
    for k in pairs(cache) do cache[k] = nil end
end)
