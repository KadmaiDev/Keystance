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

local pairs, ipairs, type, tonumber, next = pairs, ipairs, type, tonumber, next
local GetInventoryItemLink, GetInventoryItemID = GetInventoryItemLink, GetInventoryItemID
local IsInventoryItemLocked, PickupInventoryItem = IsInventoryItemLocked, PickupInventoryItem
local CursorHasItem, ClearCursor, GetCursorInfo = CursorHasItem, ClearCursor, GetCursorInfo
local InCombatLockdown, UnitIsDeadOrGhost, GetTime = InCombatLockdown, UnitIsDeadOrGhost, GetTime
local GetMacroInfo = GetMacroInfo

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
-- Which slot an item goes in (its equip location), as the character sheet allows
---------------------------------------------------------------------------
local FITS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 }, INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
    INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
    INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 }, INVTYPE_TABARD = { 19 },
}

-- True if the item can go in that gear slot; else false and why ("Stompers can't go in
-- Legs: it goes in Feet."). A one-hander in the off hand needs dual wield. An equip
-- location this list doesn't know is allowed (the game still has the last word).
function ns.ItemFitsSlot(item, slot)
    local _, _, _, loc = C_Item.GetItemInfoInstant(item)
    local name = ns.GearItemName(item)
    if type(loc) ~= "string" or loc == "" or loc == "INVTYPE_NON_EQUIP_IGNORE" or loc == "INVTYPE_AMMO"
        or loc == "INVTYPE_BAG" then
        return false, L["%s isn't something you wear."]:format(name)
    end
    local slots = FITS[loc]
    if not slots then return true end
    for _, s in ipairs(slots) do
        if s == slot then
            if slot == OFF_HAND and loc == "INVTYPE_WEAPON" and CanDualWield and not CanDualWield() then
                return false, L["%s can't go in your off hand: you can't dual wield yet."]:format(name)
            end
            return true
        end
    end
    return false, L["%s can't go in %s: it goes in %s."]:format(name, ns.GEAR_SLOT_NAMES[slot], ns.GEAR_SLOT_NAMES[slots[1]])
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

---------------------------------------------------------------------------
-- ItemRack: its sets, when it's loaded (4.50 supports Forever). Nothing it offers is a
-- documented API, so every call is checked and pcall'd; a broken ItemRack just means
-- Keystance's own gear is used.
---------------------------------------------------------------------------
function ns.ItemRackReady()
    return type(ItemRack) == "table" and type(ItemRack.EquipSet) == "function"
        and type(ItemRackUser) == "table" and type(ItemRackUser.Sets) == "table"
end

-- The character's ItemRack sets, sorted (its own internal sets start with "~").
function ns.ItemRackSets()
    local names = {}
    if ns.ItemRackReady() then
        for name in pairs(ItemRackUser.Sets) do
            if type(name) == "string" and name:sub(1, 1) ~= "~" then names[#names + 1] = name end
        end
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

function ns.ItemRackSetIcon(name)
    local set = ns.ItemRackReady() and ItemRackUser.Sets[name]
    return type(set) == "table" and set.icon or nil
end

-- True if the ItemRack set is what's worn.
function ns.ItemRackEquipped(name)
    if not ns.ItemRackReady() then return false end
    if type(ItemRack.IsSetEquipped) == "function" then
        local ok, equipped = pcall(ItemRack.IsSetEquipped, name)
        if ok then return equipped and true or false end
    end
    return ItemRackUser.CurrentSet == name
end

-- Asks ItemRack to put a set on. Rules stay quiet until it has finished (its EndSetSwap).
local itemRackPending = false
function ns.ItemRackEquip(name)
    if not (ns.ItemRackReady() and ItemRackUser.Sets[name]) then return false end
    itemRackPending = true
    Quiet(3)
    local ok = pcall(ItemRack.EquipSet, name)
    if not ok then itemRackPending = false end
    return ok
end

-- ItemRack says when a set has gone on; ours keeps rules quiet a moment longer.
ns.On("PLAYER_LOGIN", function()
    if ns.ItemRackReady() and type(ItemRack.EndSetSwap) == "function" then
        hooksecurefunc(ItemRack, "EndSetSwap", function()
            if itemRackPending then
                itemRackPending = false
                Quiet()
            end
        end)
    end
end)

---------------------------------------------------------------------------
-- Which gear a profile puts on
---------------------------------------------------------------------------
-- "itemrack" or "keystance": the player's choice (settings.gearSource), ItemRack by default
-- when it's loaded. Choosing ItemRack without it loaded falls back to Keystance's own.
function ns.GearSource()
    local want = ns.db and ns.db.settings.gearSource
    if want == "keystance" or not ns.ItemRackReady() then return "keystance" end
    return "itemrack"
end

-- What applying the profile puts on: "itemrack", set name; "items", { [slot] = item };
-- or nil.
function ns.ProfileGear(p)
    if not p then return nil end
    if ns.GearSource() == "itemrack" then
        if p.itemrack then return "itemrack", p.itemrack end
    elseif p.gear and next(p.gear) then
        return "items", p.gear
    end
end

---------------------------------------------------------------------------
-- A profile's picture: the one the player chose (p.icon), or automatic
---------------------------------------------------------------------------
ns.LOGO_ICON = "Interface\\AddOns\\" .. ADDON .. "\\media\\icon.tga"

-- The icon of a saved slot action ({ t = "spell", id = ... }), or nil.
local function ActionIcon(a)
    if a.t == "spell" then return C_Spell.GetSpellTexture(a.id) end
    if a.t == "item" then return C_Item.GetItemIconByID(a.id) end
    if a.t == "macro" and a.name then
        local _, icon = GetMacroInfo(a.name)
        return icon
    end
end

-- Automatic: its ItemRack set's icon (with ItemRack as the source), else its main-hand
-- weapon, else the first action on its bars, else Keystance's logo.
function ns.AutoProfileIcon(p)
    if p.itemrack and ns.GearSource() == "itemrack" then
        local icon = ns.ItemRackSetIcon(p.itemrack)
        if icon then return icon end
    end
    local weapon = p.gear and ns.ItemStringID(p.gear[16])
    if weapon then return C_Item.GetItemIconByID(weapon) or ns.LOGO_ICON end
    for slot = 1, ns.MANAGED_SLOTS do
        local a = p.slots and p.slots[slot]
        local icon = a and ActionIcon(a)
        if icon then return icon end
    end
    return ns.LOGO_ICON
end

-- The profile's icon, and whether it's a game icon (with a border to crop) rather than the logo.
function ns.ProfileIcon(p)
    local icon = p.icon or ns.AutoProfileIcon(p)
    return icon, icon ~= ns.LOGO_ICON
end

-- The icons a profile itself suggests, for the picker: its gear, its ItemRack set, then
-- the actions on its bars.
function ns.ProfileIcons(p)
    local list = {}
    for _, slot in ipairs(ns.GEAR_ORDER) do
        local id = p.gear and ns.ItemStringID(p.gear[slot])
        local icon = id and C_Item.GetItemIconByID(id)
        if icon then list[#list + 1] = icon end
    end
    local set = p.itemrack and ns.ItemRackSetIcon(p.itemrack)
    if set then list[#list + 1] = set end
    for slot = 1, ns.MANAGED_SLOTS do
        local a = p.slots and p.slots[slot]
        local icon = a and ActionIcon(a)
        if icon then list[#list + 1] = icon end
    end
    return list
end

-- How many gear slots applying it would change (an ItemRack set counts as one).
function ns.ProfileGearChanges(p)
    local kind, data = ns.ProfileGear(p)
    if kind == "items" then return ns.GearChanges(data) end
    if kind == "itemrack" then return ns.ItemRackEquipped(data) and 0 or 1 end
    return 0
end

-- Starts putting on a profile's gear. Returns the gear it replaces ({ [slot] = item }, for
-- Undo) and true if anything is changing.
function ns.StartProfileGear(p)
    if GetCursorInfo() then return nil, false end -- applying stops too; say it once, there
    local kind, data = ns.ProfileGear(p)
    if kind == "items" then
        if ns.GearChanges(data) == 0 then return nil, false end
        local slots = {}
        for slot in pairs(data) do slots[slot] = true end
        local before = ns.CaptureGear(slots)
        local ok, why = ns.EquipGear(data, ns.GearReport)
        if not ok then
            ns.Print(L["Gear not changed: %s."]:format(why))
            return nil, false
        end
        return before, true
    elseif kind == "itemrack" then
        if ns.ItemRackEquipped(data) then return nil, false end
        local before = ns.CaptureGear()
        if not ns.ItemRackEquip(data) then
            ns.Print(L["ItemRack couldn't put on %s."]:format(data))
            return nil, false
        end
        ns.Print(L["Gear: ItemRack is putting on %s."]:format(data))
        return before, true
    end
    return nil, false
end
