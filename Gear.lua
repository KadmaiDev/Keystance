-- Keystance gear: the gear a profile puts on. Two sources, the player's choice:
--   * ItemRack's sets, when ItemRack is loaded (the profile names a set; ItemRack equips it)
--   * Keystance's own: the items a profile saved, equipped here.
-- Equipping works like ItemRack (which swaps gear this way on Forever): pick an item up from
-- the bags or another gear slot and put it in its slot, which swaps the two, so no bag space
-- is needed. Each pass plans from the gear as it is now, does every move that doesn't touch
-- a place an earlier move of the same pass touched, then waits until the game has finished
-- moving (nothing locked) and plans again. Two identical rings or trinkets are kept apart
-- (each place is claimed once); a two-hander first puts the off hand in a free bag slot;
-- missing items are named; a slot the game refuses is reported once and not retried.
-- Nothing here runs in combat: callers go through ns.OutOfCombat, and a swap that meets
-- combat halfway waits for it to end.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)
local L = ns.L

local pairs, ipairs, type, tonumber = pairs, ipairs, type, tonumber
local GetInventoryItemLink, GetInventoryItemID = GetInventoryItemLink, GetInventoryItemID
local IsInventoryItemLocked, PickupInventoryItem = IsInventoryItemLocked, PickupInventoryItem
local CursorHasItem, ClearCursor, GetCursorInfo = CursorHasItem, ClearCursor, GetCursorInfo
local InCombatLockdown, UnitIsDeadOrGhost, GetTime = InCombatLockdown, UnitIsDeadOrGhost, GetTime

local MAIN_HAND, OFF_HAND = 16, 17
local FIRST_BAG, LAST_BAG = 0, NUM_BAG_SLOTS or 4
local TICK = 0.1       -- seconds between passes
local MAX_WAITS = 40   -- passes spent waiting on the game (4 s) before giving up
local QUIET = 1        -- seconds after Keystance's own gear changes that rules ignore gear events

-- The gear slots, in the order they're equipped (weapons first, so a two-hander clears the
-- off hand before anything goes there) and their names.
ns.GEAR_ORDER = { 16, 17, 18, 1, 2, 3, 15, 5, 4, 19, 9, 10, 6, 7, 8, 11, 12, 13, 14 }
ns.GEAR_SLOT_NAMES = {
    [1] = L["Head"], [2] = L["Neck"], [3] = L["Shoulders"], [4] = L["Shirt"], [5] = L["Chest"], [6] = L["Waist"],
    [7] = L["Legs"], [8] = L["Feet"], [9] = L["Wrists"], [10] = L["Hands"], [11] = L["Ring 1"], [12] = L["Ring 2"],
    [13] = L["Trinket 1"], [14] = L["Trinket 2"], [15] = L["Back"], [16] = L["Main hand"], [17] = L["Off hand"],
    [18] = L["Ranged"], [19] = L["Tabard"],
}

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
local function Secret(v) return issecretvalue and issecretvalue(v) end

-- "item:12345:0:..." out of an item link, or nil.
local function ItemString(link)
    if type(link) ~= "string" or Secret(link) then return nil end
    return link:match("item:[^|]+")
end
ns.ItemString = ItemString

function ns.ItemStringID(s) return type(s) == "string" and tonumber(s:match("^item:(%d+)")) or nil end

-- What makes two copies of an item the same one: the ID, enchant, gems, suffix and unique
-- ID (the first eight fields, as ItemRack compares). Later fields change with the player's
-- level, so they're left out.
local function Key(s)
    return s and (s:match("^(item:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*)") or s:match("^[^|]*"))
end

local function IsTwoHand(s)
    if not s then return false end
    local _, _, _, loc = C_Item.GetItemInfoInstant(s)
    return loc == "INVTYPE_2HWEAPON"
end

-- The item in a gear slot now, as an item string (nil if empty or not known yet).
local function Worn(slot)
    return ItemString(GetInventoryItemLink("player", slot))
end
ns.WornItem = Worn

-- The item's name, from its string (for messages).
function ns.GearItemName(s)
    local id = ns.ItemStringID(s)
    return id and C_Item.GetItemNameByID(id) or L["item %d"]:format(id or 0)
end

---------------------------------------------------------------------------
-- Saving
---------------------------------------------------------------------------
-- The gear worn now, as { [slot] = item string }: every slot, or only those in `slots`.
-- Returns nil and why if the game hasn't loaded the items yet (right after login it knows
-- item IDs before links).
function ns.CaptureGear(slots)
    local items = {}
    for slot = 1, 19 do
        if not slots or slots[slot] then
            local id = GetInventoryItemID("player", slot)
            local s = Worn(slot)
            if id and not Secret(id) and not s then return nil, L["Your gear hasn't loaded yet; try again in a moment."] end
            items[slot] = s
        end
    end
    return items
end

-- How many of the items aren't worn in their slots now.
function ns.GearChanges(items)
    local n = 0
    for slot, want in pairs(items or {}) do
        if Key(Worn(slot)) ~= Key(want) then n = n + 1 end
    end
    return n
end

---------------------------------------------------------------------------
-- Where things are: gear slots 1-19, and bag slots as (bag + 1) * 100 + slot
---------------------------------------------------------------------------
local function BagLoc(bag, slot) return (bag + 1) * 100 + slot end
local function LocBag(loc) return math.floor(loc / 100) - 1, loc % 100 end

-- Every item worn or in the bags: { [loc] = item string }, and whether anything is locked
-- (the game hasn't finished a move yet).
local function Scan()
    local where, locked = {}, false
    for slot = 1, 19 do
        where[slot] = Worn(slot)
        if IsInventoryItemLocked(slot) then locked = true end
    end
    for bag = FIRST_BAG, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                where[BagLoc(bag, slot)] = ItemString(info.hyperlink)
                if info.isLocked then locked = true end
            end
        end
    end
    return where, locked
end

-- An empty slot in a bag that holds anything (not a quiver or ammo pouch), not in `avoid`.
local function FreeBagSlot(where, avoid)
    for bag = LAST_BAG, FIRST_BAG, -1 do
        local _, family = C_Container.GetContainerNumFreeSlots(bag)
        if family == 0 or family == nil then
            for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
                local loc = BagLoc(bag, slot)
                if not where[loc] and not avoid[loc] then return loc end
            end
        end
    end
end

local function Pickup(loc)
    if loc < 100 then
        PickupInventoryItem(loc)
    else
        C_Container.PickupContainerItem(LocBag(loc))
    end
end

-- Where to find `want` for `slot`: the same copy first (by Key), then any of that item.
-- Places already claimed (kept or taken this plan) are skipped, as is the slot itself.
local function Find(where, want, slot, claimed)
    local key, id = Key(want), ns.ItemStringID(want)
    local byID
    for loc, have in pairs(where) do
        if loc ~= slot and not claimed[loc] then
            if Key(have) == key then return loc end
            if not byID and ns.ItemStringID(have) == id then byID = loc end
        end
    end
    return byID
end

-- The moves that would put `items` on: { { slot, from }, ... } in equip order, and the
-- slots whose item isn't anywhere.
local function Plan(where, items, skip)
    local claimed, moves, missing = {}, {}, {}
    for slot, want in pairs(items) do
        if Key(where[slot]) == Key(want) then claimed[slot] = true end
    end
    for _, slot in ipairs(ns.GEAR_ORDER) do
        local want = items[slot]
        if want and not claimed[slot] and not skip[slot] then
            local from = Find(where, want, slot, claimed)
            if from then
                claimed[from] = true
                moves[#moves + 1] = { slot, from }
            else
                missing[#missing + 1] = slot
            end
        end
    end
    return moves, missing
end

---------------------------------------------------------------------------
-- Equipping
---------------------------------------------------------------------------
local job -- the swap in progress: { items, done, failed = {slot = why}, waits, moved, gen }
local gen = 0

-- True for a moment after Keystance changed gear, so rules don't treat it as the player's.
function ns.GearQuiet()
    return ns.gearQuietUntil ~= nil and GetTime() < ns.gearQuietUntil
end
local function Quiet(seconds) ns.gearQuietUntil = GetTime() + (seconds or QUIET) end
ns.QuietGear = Quiet

function ns.GearBusy() return job ~= nil end

local function Finish(result)
    local done = job.done
    result.items = job.items
    job = nil
    Quiet()
    if done then done(result) end
end

local Pass
local function Next()
    local mine = gen
    C_Timer.After(TICK, function() if job and job.gen == mine then Pass() end end)
end

Pass = function()
    if InCombatLockdown() then
        -- Armour can't change in combat: carry on when it ends.
        return ns.OutOfCombat("gear", function() if job then Pass() end end)
    end
    Quiet()
    if CursorHasItem() or GetCursorInfo() then
        return Finish({ moved = job.moved, missing = {}, failed = job.failed, why = L["something is on your cursor"] })
    end
    local where, locked = Scan()
    if locked then
        job.waits = job.waits + 1
        if job.waits > MAX_WAITS then
            return Finish({ moved = job.moved, missing = {}, failed = job.failed, why = L["the game didn't finish moving items"] })
        end
        return Next()
    end
    local moves, missing = Plan(where, job.items, job.failed)
    if #moves == 0 then return Finish({ moved = job.moved, missing = missing, failed = job.failed }) end
    local touched = {}
    for _, move in ipairs(moves) do
        local slot, from = move[1], move[2]
        if not touched[slot] and not touched[from] then
            touched[slot], touched[from] = true, true
            if slot == MAIN_HAND and IsTwoHand(where[from]) and where[OFF_HAND] and not job.items[OFF_HAND] then
                -- A two-hander: the off hand goes to a free bag slot first; the weapon next pass.
                touched[OFF_HAND] = true
                local space = FreeBagSlot(where, touched)
                if not space then
                    job.failed[slot] = L["no bag space for your off hand"]
                else
                    touched[space] = true
                    PickupInventoryItem(OFF_HAND)
                    Pickup(space)
                    if CursorHasItem() then
                        ClearCursor()
                        job.failed[slot] = L["your off hand wouldn't come off"]
                    end
                end
            else
                Pickup(from)
                PickupInventoryItem(slot)
                if CursorHasItem() then
                    ClearCursor() -- back where it came from
                    job.failed[slot] = L["the game wouldn't equip it"]
                else
                    job.moved = job.moved + 1
                end
            end
        end
    end
    job.waits = 0
    Next()
end

-- Puts on `items` ({ [slot] = item string }), then calls done(result) with
-- { moved = n, missing = { slots }, failed = { [slot] = why }, why = reason it stopped }.
-- Replaces a swap already under way. Returns false and why if it can't start.
function ns.EquipGear(items, done)
    if UnitIsDeadOrGhost("player") then return false, L["you can't change gear while dead"] end
    if CursorHasItem() then return false, L["something is on your cursor"] end
    gen = gen + 1
    job = { items = items, done = done, failed = {}, waits = 0, moved = 0, gen = gen }
    Quiet()
    local now = ns.OutOfCombat("gear", function() if job then Pass() end end)
    return true, not now
end

-- "Gear: 3 items put on." plus what couldn't be, for chat.
function ns.GearReport(result)
    if result.why then ns.Print(L["Gear stopped: %s."]:format(result.why)) end
    if result.moved > 0 then ns.Print(L["Gear: %d items put on."]:format(result.moved)) end
    for _, slot in ipairs(result.missing or {}) do
        ns.Print(L["Gear: %s isn't in your bags (%s)."]:format(ns.GearItemName(result.items and result.items[slot]),
            ns.GEAR_SLOT_NAMES[slot]))
    end
    for slot, why in pairs(result.failed or {}) do
        ns.Print(L["Gear: %s: %s."]:format(ns.GEAR_SLOT_NAMES[slot], why))
    end
end
