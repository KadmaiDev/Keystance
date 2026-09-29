-- Keystance rules: apply a profile automatically when gear changes. A rule is
--   { when = "shield" }, { when = "twohand" }, { when = "item", id = itemID } or
--   { when = "set", set = "Healing" } (an equipment set; from = "itemrack" for one of
--   ItemRack's), each with profile = "Prot".
-- The first matching rule wins (the player orders them). Gear swaps fire several events,
-- so it checks once, 0.3 s after the last one. It acts only when the profile the rules want
-- changes (equipping a shield), not on every gear change: a profile the player picked by
-- hand, an Undo, or "Stay" to the question isn't overridden by swapping a trinket later.
-- Applying goes through ns.ApplyProfile, so in combat it waits for combat to end, and
-- shared keybinds are asked about first; a switch the player queued in combat isn't
-- replaced. Off with /kst auto off; "Ask before switching" makes each switch a question.
-- Gear changes Keystance makes itself (Gear.lua) are ignored, and a switch leaves the new
-- profile's gear alone.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)
local L = ns.L

local ipairs, type = ipairs, type
local GetInventoryItemID, GetTime = GetInventoryItemID, GetTime

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

-- False for a rule that can't match: one watching an ItemRack set while ItemRack isn't
-- loaded (disabled) or has no set of that name. Such rules are skipped, and shown in red.
-- Allocates nothing: it runs on gear events.
local function Usable(rule)
    if rule.when ~= "set" or rule.from ~= "itemrack" then return true end
    return ns.ItemRackReady() and type(ItemRackUser.Sets[rule.set]) == "table"
end

-- Why a rule is ignored ("ItemRack isn't loaded"), or nil if it isn't.
function ns.RuleProblem(rule)
    if Usable(rule) then return nil end
    if not ns.ItemRackReady() then return L["ItemRack isn't loaded"] end
    return L["ItemRack has no set called %s"]:format(tostring(rule.set))
end

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
        if test and Usable(rule) and ns.FindProfile(rule.profile) and test(rule) then return rule end
    end
end

-- The player (or ItemRack) changed gear, so the profile's own gear stays off.
local function Switch(key)
    ns.ApplyProfile(key, nil, nil, true)
end

local function AskSwitch(rule, key)
    ns.Dialog("KEYSTANCE_SWITCH", {
        text = L["%s: switch to %s?"],
        button1 = L["Switch"],
        button2 = L["Stay"],
        OnAccept = function(_, data) Switch(data) end,
    })
    local reason = ns.RuleCondition(rule)
    StaticPopup_Show("KEYSTANCE_SWITCH", reason:sub(1, 1):upper() .. reason:sub(2), key, key)
end

local scheduled, lastEvent, scheduledAt = false, 0, 0
local lastWanted -- the profile the rules wanted at the last check
local Evaluate
Evaluate = function()
    -- Another gear event came in meanwhile: wait until the gear has been still for WAIT.
    if lastEvent > scheduledAt then
        scheduledAt = lastEvent
        return C_Timer.After(WAIT, Evaluate)
    end
    scheduled = false
    local c = Char()
    if not (c and ns.AutoOn()) then return end
    local rule = ns.MatchingRule()
    local want = rule and ns.FindProfile(rule.profile)
    -- Gear Keystance put on itself (a profile's gear, or Undo) isn't the player's choice:
    -- what it matches is simply where things stand now.
    if ns.GearQuiet() or ns.GearBusy() then
        lastWanted = want
        return
    end
    if want == lastWanted then return end -- nothing the rules care about changed
    lastWanted = want
    if not want or want == c.active then return end
    if ns.pendingProfile then return end -- the player's own queued switch comes first
    if ns.AskFirst() then return AskSwitch(rule, want) end
    local reason = ns.RuleCondition(rule)
    ns.Notify(L["%s: switching to %s."]:format(reason:sub(1, 1):upper() .. reason:sub(2), want))
    Switch(want)
end

local function GearChanged()
    lastEvent = GetTime()
    if scheduled then return end
    scheduled, scheduledAt = true, lastEvent
    C_Timer.After(WAIT, Evaluate)
end
ns.On("PLAYER_EQUIPMENT_CHANGED", GearChanged)
ns.On("EQUIPMENT_SWAP_FINISHED", GearChanged)
-- ItemRack swaps one item at a time; it says when a whole set is on (Gear.lua hooks it).
ns.GearSetFinished = GearChanged

ns.AddCommand("auto", function(arg)
    arg = (arg or ""):lower()
    local on
    if arg == "on" then on = true elseif arg == "off" then on = false else on = not ns.AutoOn() end
    ns.db.settings.autoOff = not on or nil
    ns.Print(on and L["Automatic switching is on: your rules pick the profile when your gear changes."]
        or L["Automatic switching is off."])
    ns.ProfilesChanged()
end)
