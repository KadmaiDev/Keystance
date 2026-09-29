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
-- While the bank is open, its items can be taken too (bags first), swapping places with
-- what was worn, as the game does when an item is dragged from the bank.
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
local TICK = 0.1       -- seconds between passes
local MAX_WAITS = 40   -- passes spent waiting on the game (4 s) before giving up
local MAX_PASSES = 60  -- a safety net: a swap that hasn't settled by then stops
local ITEMRACK_WAIT = 10 -- seconds a set asked of ItemRack counts as Keystance's, unless it says it's done
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
ns.IsTwoHandItem = IsTwoHand

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


---------------------------------------------------------------------------
-- Where things are: gear slots 1-19, and bag slots as 1000 * (the bag's place in BAGS) + slot
---------------------------------------------------------------------------
-- The bags carried (not the keyring or reagent bag: no gear goes there), then the bank's
-- tabs (an unbought tab has no slots), by the game's own numbers for them.
local BagIndex = Enum and Enum.BagIndex or {}
local BAGS = {}
for i, name in ipairs({ "Backpack", "Bag_1", "Bag_2", "Bag_3", "Bag_4" }) do BAGS[i] = BagIndex[name] or (i - 1) end
local CARRIED = #BAGS
for i = 1, 9 do BAGS[#BAGS + 1] = BagIndex["CharacterBankTab_" .. i] end
local BANK_LOC = (CARRIED + 1) * 1000 -- places from here on are in the bank

local function BagLoc(i, slot) return i * 1000 + slot end
local function LocBag(loc) return BAGS[math.floor(loc / 1000)], loc % 1000 end
local function InBank(loc) return loc >= BANK_LOC end
ns.GearLocInBank = InBank

-- The bank's items can be read only while it's open (outside that its tabs look empty), so
-- what was there on the last visit is remembered for the character (c.bankSeen, a set of
-- item Keys), to say "in your bank" about gear that isn't on the character.
local bankOpen = false
function ns.BankOpen() return bankOpen end
-- Remember is below, once Key and the bag list are defined.
local Remember
local function BankShown(shown)
    return function()
        bankOpen = shown
        if shown then Remember() end
        ns.RequestRefresh("profiles") -- the gear editor's list of items
    end
end
ns.On("BANKFRAME_OPENED", BankShown(true))
ns.On("BANKFRAME_CLOSED", BankShown(false))
-- The client announces the banker through the interaction manager too.
local BANKER = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Banker
if BANKER then
    local opened, closed = BankShown(true), BankShown(false)
    ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(kind) if kind == BANKER then opened() end end)
    ns.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(kind) if kind == BANKER then closed() end end)
end

-- Every item worn, in the bags, and in the bank while it's open: { [loc] = item string },
-- the places locked (the game hasn't finished a move yet, or the item sits in a trade or
-- mail window), and true if some item's details haven't loaded yet (right after login).
local function Scan()
    local where, locked, loading = {}, {}, false
    for slot = 1, 19 do
        where[slot] = Worn(slot)
        if IsInventoryItemLocked(slot) then locked[slot] = true end
        if not where[slot] then
            local id = GetInventoryItemID("player", slot)
            if id and not Secret(id) then loading = true end
        end
    end
    for i = 1, bankOpen and #BAGS or CARRIED do
        local bag = BAGS[i]
        for slot = 1, bag and C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                local loc = BagLoc(i, slot)
                where[loc] = ItemString(info.hyperlink)
                if not where[loc] then loading = true end
                if info.isLocked then locked[loc] = true end
            end
        end
    end
    return where, locked, loading
end

-- What's in the bank now, remembered for the character (only while the bank is open).
Remember = function()
    local c = ns.char
    if not (c and bankOpen) then return end
    local seen = {}
    for i = CARRIED + 1, #BAGS do
        local bag = BAGS[i]
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local s = info and ItemString(info.hyperlink)
            if s then seen[Key(s)] = true end
        end
    end
    c.bankSeen = seen
end
ns.On("BAG_UPDATE_DELAYED", function() if bankOpen then Remember() end end)

-- True if the item (this copy, or another of the same item) was in the bank last visit.
local function SeenInBank(item)
    local seen = ns.char and ns.char.bankSeen
    if not (seen and item) then return false end
    if seen[Key(item)] then return true end
    local id = ns.ItemStringID(item)
    for key in pairs(seen) do
        if ns.ItemStringID(key) == id then return true end
    end
    return false
end

-- An empty slot in a carried bag that holds anything (not a quiver or ammo pouch), not in
-- `avoid`.
local function FreeBagSlot(where, avoid)
    for i = CARRIED, 1, -1 do
        local bag = BAGS[i]
        local _, family = C_Container.GetContainerNumFreeSlots(bag)
        if family == 0 or family == nil then
            for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
                local loc = BagLoc(i, slot)
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

-- Where to find `want` for `slot`: the same copy first (by Key), then any of that item;
-- each worn or in the bags before the bank. Places already claimed (kept or taken this
-- plan) are skipped, as is the slot itself.
local function Find(where, want, slot, claimed)
    local key, id = Key(want), ns.ItemStringID(want)
    local exactBank, byID, byIDBank
    for loc, have in pairs(where) do
        if loc ~= slot and not claimed[loc] then
            local bank = InBank(loc)
            if Key(have) == key then
                if not bank then return loc end
                exactBank = exactBank or loc
            elseif ns.ItemStringID(have) == id then
                if bank then byIDBank = byIDBank or loc else byID = byID or loc end
            end
        end
    end
    return exactBank or byID or byIDBank
end

-- True if an unclaimed place holds this very copy of the item (by Key).
local function ExactCopy(where, want, claimed)
    local key = Key(want)
    for loc, have in pairs(where) do
        if not claimed[loc] and Key(have) == key then return true end
    end
    return false
end

-- The moves that would put `items` on: { { slot, from }, ... } in equip order, and the
-- slots whose item isn't anywhere.
local NONE = {}
local function Plan(where, items, skip)
    local claimed, moves, missing = {}, {}, {}
    for slot, want in pairs(items) do
        if Key(where[slot]) == Key(want) then claimed[slot] = true end
    end
    -- Worn, but changed since it was saved (enchanted, say), and that exact copy is nowhere:
    -- it's the one. (Otherwise it counted as missing, and two such copies in the two hands
    -- swapped with each other forever.)
    for slot, want in pairs(items) do
        if not claimed[slot] and where[slot] and ns.ItemStringID(where[slot]) == ns.ItemStringID(want)
            and not ExactCopy(where, want, claimed) then
            claimed[slot] = true
        end
    end
    -- A two-hander leaves no off hand: a profile saved with both would swap them forever.
    local noOffHand = items[MAIN_HAND] and IsTwoHand(items[MAIN_HAND])
    for _, slot in ipairs(ns.GEAR_ORDER) do
        local want = items[slot]
        if slot == OFF_HAND and noOffHand then want = nil end
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

-- How many of the items aren't on now (to move, or not to be found): the plan a swap
-- would make, so "already worn" means the same everywhere.
function ns.GearChanges(items)
    if not items or not next(items) then return 0 end
    local moves, missing = Plan(Scan(), items, NONE)
    return #moves + #missing
end

-- The items that aren't on the character (not worn, not in the bags, not in the bank while
-- it's open): { [slot] = "bank" (there on the last bank visit) or "missing" }, empty if
-- all are there, or nil while the game is still loading item details.
function ns.GearStatus(items)
    local status = {}
    if not items or not next(items) then return status end
    local where, _, loading = Scan()
    if loading then return nil end
    local _, missing = Plan(where, items, NONE)
    for _, slot in ipairs(missing) do
        status[slot] = SeenInBank(items[slot]) and "bank" or "missing"
    end
    return status
end

-- The gear slots a swap to `items` changes, for Undo: the items' own, and the off hand
-- whenever the main hand changes (a two-hander sends the off hand to the bags).
function ns.GearSlotsOf(items)
    local slots = {}
    for slot in pairs(items) do slots[slot] = true end
    if slots[MAIN_HAND] then slots[OFF_HAND] = true end
    return slots
end

-- What could go in `slot`, for the gear editor: { { item = item string, worn = true |
-- bank = true }, ... }, each item once (by Key), the one worn there first, then the rest
-- worn, the bags and the bank (while it's open), in that order.
function ns.GearChoices(slot)
    local list, seen = {}, {}
    local where = Scan()
    local function Add(loc)
        local item = where[loc]
        if not item or seen[Key(item)] or not ns.ItemFitsSlot(item, slot) then return end
        seen[Key(item)] = true
        list[#list + 1] = { item = item, worn = loc < 1000 or nil, bank = InBank(loc) or nil }
    end
    Add(slot)
    for s = 1, 19 do if s ~= slot then Add(s) end end
    for i = 1, #BAGS do
        for bagSlot = 1, C_Container.GetContainerNumSlots(BAGS[i]) or 0 do Add(BagLoc(i, bagSlot)) end
    end
    return list
end

---------------------------------------------------------------------------
-- Equipping
---------------------------------------------------------------------------
local job -- the swap in progress: { items, done, failed = {slot = why}, waits, passes, moved, touched, gen }
local gen = 0
local itemRackUntil -- a set asked of ItemRack counts as Keystance's until then (or its EndSetSwap)

-- True for a moment after Keystance changed gear, so rules don't treat it as the player's.
function ns.GearQuiet()
    return ns.gearQuietUntil ~= nil and GetTime() < ns.gearQuietUntil
end
local function Quiet(seconds) ns.gearQuietUntil = GetTime() + (seconds or QUIET) end

-- True while Keystance's own swap, or a set it asked ItemRack for, is under way.
function ns.GearBusy()
    return job ~= nil or (itemRackUntil ~= nil and GetTime() < itemRackUntil)
end

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
    job.passes = job.passes + 1
    if job.passes > MAX_PASSES then
        return Finish({ moved = job.moved, missing = {}, failed = job.failed, why = L["the swap didn't settle"] })
    end
    -- Waits while the game is still moving what this swap touched, or any worn gear. Other
    -- locked items (in a trade or mail window) don't matter.
    local where, locked = Scan()
    local waiting = false
    for slot = 1, 19 do
        if locked[slot] then waiting = true end
    end
    for loc in pairs(job.touched) do
        if locked[loc] then waiting = true end
    end
    if waiting then
        job.waits = job.waits + 1
        if job.waits > MAX_WAITS then
            return Finish({ moved = job.moved, missing = {}, failed = job.failed, why = L["the game didn't finish moving items"] })
        end
        return Next()
    end
    local moves, missing = Plan(where, job.items, job.failed)
    if #moves == 0 then return Finish({ moved = job.moved, missing = missing, failed = job.failed }) end
    local touched = {}
    job.touched = touched
    for _, move in ipairs(moves) do
        local slot, from = move[1], move[2]
        if not touched[slot] and not touched[from] and not locked[from] then
            touched[slot], touched[from] = true, true
            if slot == MAIN_HAND and IsTwoHand(where[from]) and where[OFF_HAND] then
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
-- Replaces a swap already under way. Returns false and why if it can't start. In combat it
-- starts when combat ends.
function ns.EquipGear(items, done)
    if UnitIsDeadOrGhost("player") then return false, L["you can't change gear while dead"] end
    if CursorHasItem() then return false, L["something is on your cursor"] end
    gen = gen + 1
    job = { items = items, done = done, failed = {}, waits = 0, passes = 0, moved = 0, touched = {}, gen = gen }
    Quiet()
    ns.OutOfCombat("gear", function() if job then Pass() end end)
    return true
end

-- "Gear: 3 items put on." plus what couldn't be, for chat.
-- A short, soft sound when some gear didn't go on (the game's "invite declined" tone, else
-- the quest log's), once per swap however many items; the message says which.
local PROBLEM_SOUNDS = { "IG_PLAYER_INVITE_DECLINE", "IG_QUEST_LOG_ABANDON_QUEST" }

function ns.GearReport(result)
    if result.why or next(result.missing or NONE) or next(result.failed or NONE) then ns.Sound(PROBLEM_SOUNDS) end
    if result.why then ns.Print(L["Gear stopped: %s."]:format(result.why)) end
    if result.moved > 0 then ns.Notify(L["Gear: %d items put on."]:format(result.moved)) end
    for _, slot in ipairs(result.missing or {}) do
        local item = result.items and result.items[slot]
        local text = SeenInBank(item) and L["Gear: %s is in your bank (%s)."] or L["Gear: %s isn't in your bags (%s)."]
        ns.Print(text:format(ns.GearItemName(item), ns.GEAR_SLOT_NAMES[slot]))
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

-- Asks ItemRack to put a set on. It counts as Keystance's (rules leave it alone) until
-- ItemRack says it's done (EndSetSwap), or ITEMRACK_WAIT seconds at most: ItemRack may
-- defer a set, or give up on it without saying so.
function ns.ItemRackEquip(name)
    if not (ns.ItemRackReady() and ItemRackUser.Sets[name]) then return false end
    itemRackUntil = GetTime() + ITEMRACK_WAIT
    Quiet(3)
    local ok = pcall(ItemRack.EquipSet, name)
    if not ok then itemRackUntil = nil end
    return ok
end

-- ItemRack says when a set has gone on: one of ours keeps rules quiet a moment longer;
-- one the player chose (from ItemRack) lets the rules look (ns.GearSetFinished, Rules.lua).
ns.On("PLAYER_LOGIN", function()
    if ns.ItemRackReady() and type(ItemRack.EndSetSwap) == "function" then
        hooksecurefunc(ItemRack, "EndSetSwap", function()
            if itemRackUntil then
                itemRackUntil = nil
                Quiet()
            end
            if ns.GearSetFinished then ns.GearSetFinished() end
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
        -- What it replaces, for Undo (the off hand too when the main hand changes). Without
        -- it (item links not loaded yet), gear stays as it is rather than change past Undo.
        local before, why = ns.CaptureGear(ns.GearSlotsOf(data))
        if not before then
            ns.Print(L["Gear not changed: %s"]:format(why))
            return nil, false
        end
        local ok
        ok, why = ns.EquipGear(data, ns.GearReport)
        if not ok then
            ns.Print(L["Gear not changed: %s."]:format(why))
            return nil, false
        end
        return before, true
    elseif kind == "itemrack" then
        if ns.ItemRackEquipped(data) then return nil, false end
        local before, why = ns.CaptureGear()
        if not before then
            ns.Print(L["Gear not changed: %s"]:format(why))
            return nil, false
        end
        if not ns.ItemRackEquip(data) then
            ns.Print(L["ItemRack couldn't put on %s."]:format(data))
            return nil, false
        end
        ns.Notify(L["Gear: ItemRack is putting on %s."]:format(data))
        return before, true
    end
    return nil, false
end
