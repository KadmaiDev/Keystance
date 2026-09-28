-- Keystance rules: apply a profile automatically when gear changes. A rule is
--   { when = "shield" }, { when = "twohand" }, { when = "item", id = itemID } or
--   { when = "set", set = "Healing" } (an equipment set; from = "itemrack" for one of
--   ItemRack's), each with profile = "Prot".
-- The first matching rule wins (the player orders them). Gear swaps fire several events,
-- so it checks once, 0.3 s after the last one, and only switches when a different profile
-- is wanted. Applying goes through ns.ApplyProfile, so in combat it waits for combat to
-- end, and shared keybinds are asked about first. Off with /kst auto off; "Ask before
-- switching" makes each switch a question. Gear changes Keystance makes itself (Gear.lua)
-- are ignored, and a switch leaves the new profile's gear alone.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)
local L = ns.L

local ipairs, type = ipairs, type
local GetInventoryItemID = GetInventoryItemID

local MAIN_HAND, OFF_HAND = 16, 17
local WAIT = 0.3

local function Char() return ns.char end

function ns.AutoOn() return not ns.db.settings.autoOff end
function ns.AskFirst() return ns.db.settings.askSwitch and true or false end

---------------------------------------------------------------------------
-- What's equipped
---------------------------------------------------------------------------
local function Equipped(slot)
    local id = GetInventoryItemID("player", slot)
    if type(id) == "number" and not (issecretvalue and issecretvalue(id)) then return id end
end

local function ItemKind(id)
    if not id then return nil end
    local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(id)
    return equipLoc, classID, subclassID
end

local TESTS = {
    -- A shield in the off hand (equip location, or armour class 4 subclass 6).
    shield = function()
        local loc, class, sub = ItemKind(Equipped(OFF_HAND))
        return loc == "INVTYPE_SHIELD" or (class == 4 and sub == 6)
    end,
    twohand = function()
        return ItemKind(Equipped(MAIN_HAND)) == "INVTYPE_2HWEAPON"
    end,
    item = function(rule)
        for slot = 1, 19 do
            if rule.id and Equipped(slot) == rule.id then return true end
        end
        return false
    end,
    set = function(rule)
        if rule.from == "itemrack" then return ns.ItemRackEquipped(rule.set) end
        if not (C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs) then return false end
        for _, id in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
            local name, _, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(id)
            if name == rule.set and isEquipped then return true end
        end
        return false
    end,
}

-- The equipment sets' names, for the Rules tab.
function ns.EquipmentSetNames()
    local names = {}
    if C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs then
        for _, id in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
            local name = C_EquipmentSet.GetEquipmentSetInfo(id)
            if name then names[#names + 1] = name end
        end
    end
    table.sort(names)
    return names
end

---------------------------------------------------------------------------
-- Rules as sentences
---------------------------------------------------------------------------
local function ItemName(id)
    return (C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or L["item %d"]:format(id or 0)
end

-- "a shield is equipped", "Lionheart Helm is equipped"...
function ns.RuleCondition(rule)
    if rule.when == "shield" then return L["a shield is equipped"] end
    if rule.when == "twohand" then return L["a two-handed weapon is equipped"] end
    if rule.when == "item" then return L["%s is equipped"]:format(ItemName(rule.id)) end
    if rule.when == "set" and rule.from == "itemrack" then
        return L["the ItemRack set %s is equipped"]:format(tostring(rule.set))
    end
    if rule.when == "set" then return L["the %s set is equipped"]:format(tostring(rule.set)) end
    return tostring(rule.when)
end

-- "When a shield is equipped, use Prot."
function ns.RuleText(rule)
    local missing = not ns.FindProfile(rule.profile)
    return L["When %s, use %s."]:format(ns.RuleCondition(rule), tostring(rule.profile))
        .. (missing and ("  |cffff5555" .. L["(no such profile)"] .. "|r") or "")
end

---------------------------------------------------------------------------
-- Editing
---------------------------------------------------------------------------
function ns.AddRule(rule)
    local c = Char()
    if not c then return nil, L["Not logged in yet."] end
    if not ns.FindProfile(rule.profile) then return nil, L["No profile called %s."]:format(tostring(rule.profile)) end
    if rule.when == "item" and not rule.id then return nil, L["Choose the item first."] end
    if rule.when == "set" and not rule.set then return nil, L["Choose the equipment set first."] end
    c.rules[#c.rules + 1] = rule
    ns.ProfilesChanged()
    return rule
end

function ns.MoveRule(i, delta)
    local rules = Char().rules
    local j = i + delta
    if not rules[i] or not rules[j] then return end
    rules[i], rules[j] = rules[j], rules[i]
    ns.ProfilesChanged()
end

function ns.DeleteRule(i)
    table.remove(Char().rules, i)
    ns.ProfilesChanged()
end

---------------------------------------------------------------------------
-- Checking
---------------------------------------------------------------------------
-- The first rule that matches the gear now and names an existing profile.
function ns.MatchingRule()
    local c = Char()
    if not c then return nil end
    for _, rule in ipairs(c.rules) do
        local test = TESTS[rule.when]
        if test and ns.FindProfile(rule.profile) and test(rule) then return rule end
    end
end

-- The player (or ItemRack) changed gear, so the profile's own gear stays off.
local function Switch(key)
    ns.ApplyProfile(key, nil, nil, true)
end

local function AskSwitch(rule, key)
    if not StaticPopupDialogs.KEYSTANCE_SWITCH then
        StaticPopupDialogs.KEYSTANCE_SWITCH = {
            text = L["%s: switch to %s?"],
            button1 = L["Switch"],
            button2 = L["Stay"],
            OnAccept = function(_, data) Switch(data) end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
    end
    local reason = ns.RuleCondition(rule)
    StaticPopup_Show("KEYSTANCE_SWITCH", reason:sub(1, 1):upper() .. reason:sub(2), key, key)
end

local scheduled = false
local function Evaluate()
    scheduled = false
    local c = Char()
    if not (c and ns.AutoOn()) then return end
    -- Gear Keystance put on itself (a profile's gear, or Undo) isn't the player's choice.
    if ns.GearQuiet() or ns.GearBusy() then return end
    local rule = ns.MatchingRule()
    if not rule then return end
    local key = ns.FindProfile(rule.profile)
    if not key or key == c.active then return end
    if ns.AskFirst() then return AskSwitch(rule, key) end
    local reason = ns.RuleCondition(rule)
    ns.Print(L["%s: switching to %s."]:format(reason:sub(1, 1):upper() .. reason:sub(2), key))
    Switch(key)
end
ns.EvaluateRules = Evaluate

local function GearChanged()
    if scheduled then return end
    scheduled = true
    C_Timer.After(WAIT, Evaluate)
end
ns.On("PLAYER_EQUIPMENT_CHANGED", GearChanged)
ns.On("EQUIPMENT_SWAP_FINISHED", GearChanged)
-- ItemRack swaps one item at a time; it says when a whole set is on.
ns.On("PLAYER_LOGIN", function()
    if ns.ItemRackReady() and type(ItemRack.EndSetSwap) == "function" then
        hooksecurefunc(ItemRack, "EndSetSwap", GearChanged)
    end
end)

ns.AddCommand("auto", function(arg)
    arg = (arg or ""):lower()
    local on
    if arg == "on" then on = true elseif arg == "off" then on = false else on = not ns.AutoOn() end
    ns.db.settings.autoOff = not on or nil
    ns.Print(on and L["Automatic switching is on: your rules pick the profile when your gear changes."]
        or L["Automatic switching is off."])
    ns.ProfilesChanged()
end)
