-- A small fake of the WoW: Forever client API, just enough to load Keystance outside the
-- game. It checks the addon's logic and wiring, not how anything looks on screen, and it
-- encodes what we believe the client does: measured facts are noted as such.
local M = {}

-- A secret value. issecretvalue() is true for it; comparing or adding it is a test bug.
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
M.SECRET = SECRET

-- Events this fake client knows; registering anything else throws, like Forever does.
local KNOWN_EVENTS = {
    ADDON_LOADED = true, PLAYER_LOGIN = true, PLAYER_LOGOUT = true, PLAYER_ENTERING_WORLD = true,
    PLAYER_REGEN_DISABLED = true, PLAYER_REGEN_ENABLED = true,
    ADDON_ACTION_BLOCKED = true, ADDON_ACTION_FORBIDDEN = true,
    ACTIONBAR_SLOT_CHANGED = true, UPDATE_BINDINGS = true, CURSOR_CHANGED = true,
    MODIFIER_STATE_CHANGED = true, UPDATE_MACROS = true, GLOBAL_MOUSE_DOWN = true,
    EQUIPMENT_SWAP_FINISHED = true, EQUIPMENT_SETS_CHANGED = true, ACTIONBAR_PAGE_CHANGED = true, UPDATE_BONUS_ACTIONBAR = true,
    SPELLS_CHANGED = true, LEARNED_SPELL_IN_SKILL_LINE = true,
    PLAYER_EQUIPMENT_CHANGED = true, UNIT_INVENTORY_CHANGED = true,
    ITEM_LOCK_CHANGED = true, BAG_UPDATE_DELAYED = true,
    BANKFRAME_OPENED = true, BANKFRAME_CLOSED = true,
    PLAYER_INTERACTION_MANAGER_FRAME_SHOW = true, PLAYER_INTERACTION_MANAGER_FRAME_HIDE = true,
}

-- Functions the client blocks for addons in combat (measured 2026-09-28 with the phase 0
-- probe for the placing and binding ones; the rest by retail's rules). In combat they do
-- nothing, fire ADDON_ACTION_BLOCKED and are recorded in M.blocked.
local PROTECTED = {
    "PickupAction", "PlaceAction", "SetBinding", "SetBindingClick", "SetBindingSpell",
    "SetBindingItem", "SetBindingMacro", "SaveBindings", "LoadBindings",
    "SetOverrideBinding", "SetOverrideBindingClick", "ClearOverrideBindings",
    "PickupMacro", "EditMacro", "CreateMacro", "DeleteMacro",
    "C_Spell.PickupSpell", "C_SpellBook.PickupSpellBookItem", "C_ActionBar.PutActionInSlot",
    "SetActionBarToggles", -- assumed: it shows and hides Blizzard's bars (secure frames)
}

local function copy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = copy(v) end
    return c
end

-- Resets every global and loads the addon files fresh. Returns the addon namespace.
function M.load(files)
    -- Named frames from the previous load are gone, as after a /reload.
    for _, f in ipairs(M.frames or {}) do
        if f.name and _G[f.name] == f then _G[f.name] = nil end
    end
    M.frames = {}
    M.printed = {}
    M.player = { name = "Vespera Ashward", class = "PALADIN", level = 20 }
    M.combat = false
    M.blocked = {}     -- protected calls made in combat: { name, ... }
    M.slots = {}       -- [actionSlot] = { kind, id, subType } ("spell", 19834, "spell")
    M.macros = {}      -- [macroIndex] = { name = ..., body = ..., icon = ... }
    M.macroSpell = {}  -- [macroIndex] = spell ID the macro shows (#showtooltip)
    M.cursor = nil     -- { kind, ... } as GetCursorInfo returns it
    M.bindings = {}    -- [key] = command, in the current set
    M.bindingSet = 1   -- 1 account-wide, 2 character-specific
    M.savedSets = {}   -- [set] = copy of the bindings saved to it
    -- The spellbook: skill lines in order, each a list of { spellID, name, subName, passive? }.
    M.spellbook = {}
    M.spellNames = {}  -- [spellID] = name (filled from the spellbook too)
    M.otherSpells = {} -- [spellID] = true: known, but not in the class spellbook (First Aid...)
    M.itemCount = {}   -- [itemID] = count in bags
    -- Items are an item ID, or an item string ("item:1000:15") for a particular copy.
    M.inventory = {}   -- [inventory slot] = item equipped (16 main hand, 17 off hand)
    -- Bags: M.bags[bag] = { size = n, [slot] = item }; the backpack (0) has 16 slots.
    M.bags = { [0] = { size = 16 }, [1] = { size = 0 }, [2] = { size = 0 }, [3] = { size = 0 }, [4] = { size = 0 } }
    -- Bank tabs (bags 6-14; unbought ones have no slots). Their items can be read and
    -- picked up only while the bank is open (wow.openBank / wow.closeBank).
    for bag = 6, 14 do M.bags[bag] = { size = 0 } end
    M.bankOpen = false
    M.bagFamily = {}   -- [bag] = family (0, or e.g. 1 for a quiver)
    M.locked = {}      -- places the game is still moving: [slot] or ["bag:slot"] = true
    M.lockMoves = false -- true: every move locks its places until wow.unlock()
    M.dead = false
    M.equipLoc = { [2129] = "INVTYPE_SHIELD", [1680] = "INVTYPE_2HWEAPON", [2132] = "INVTYPE_WEAPON",
        [1000] = "INVTYPE_FINGER", [1001] = "INVTYPE_FINGER", [1100] = "INVTYPE_HEAD", [1101] = "INVTYPE_HEAD",
        [1200] = "INVTYPE_TRINKET", [1300] = "INVTYPE_FEET" }
    M.itemNames = { [2129] = "Large Round Shield", [1680] = "Headchopper", [2132] = "Short Cutlass", [6948] = "Hearthstone",
        [1000] = "Band of Flesh", [1001] = "Seal of Wrynn", [1100] = "Lionheart Helm", [1101] = "Coif", [1200] = "Lucky Charm",
        [1300] = "Stompers" }
    M.sets = {}        -- { { name = "Healing", equipped = true }, ... }

    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    issecretvalue = function(v) return v == SECRET end
    M.now = nil
    time = function(t) if t then return os.time(t) end return M.now or os.time() end
    GetTime = function() return M.clock or 0 end
    GetLocale = function() return M.locale or "enUS" end
    date = os.date
    M.chat, M.onScreen = {}, {}
    print = function(msg)
        M.printed[#M.printed + 1] = msg
        M.chat[#M.chat + 1] = msg
    end
    -- The game's notices at the top of the screen, which fade after a few seconds.
    UIErrorsFrame = { AddMessage = function(_, msg)
        M.printed[#M.printed + 1] = msg
        M.onScreen[#M.onScreen + 1] = msg
    end }
    SlashCmdList = {}
    Enum = {
        SpellBookSpellBank = { Player = 0, Pet = 1 },
        SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 },
        -- Forever's bags: the values are retail's (not measured on Forever, so the addon
        -- mustn't depend on them beyond reading them from here).
        BagIndex = { Keyring = -1, Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5,
            CharacterBankTab_1 = 6, CharacterBankTab_2 = 7, CharacterBankTab_3 = 8, CharacterBankTab_4 = 9,
            CharacterBankTab_5 = 10, CharacterBankTab_6 = 11, CharacterBankTab_7 = 12, CharacterBankTab_8 = 13,
            CharacterBankTab_9 = 14 },
        PlayerInteractionType = { Banker = 8, Merchant = 5 },
    }

    -- Frames: real behaviour for events, scripts, text and visibility; any other widget
    -- method (sizing, anchoring, fonts...) is accepted and ignored.
    local frameMethods = {}
    local function ignored(self) return self end
    -- Child elements a template may or may not provide are nil unless set.
    local CHILDREN = { TitleText = true, CloseButton = true, Inset = true }
    -- Widget methods are capitalised (SetText, Show); lower-case names are our own fields,
    -- which are nil unless set, as in the game.
    local frameMeta = { __index = function(_, k)
        if CHILDREN[k] or type(k) ~= "string" or not k:match("^%u") then return nil end
        return frameMethods[k] or ignored
    end }
    local function newObject(kind, name)
        local f = setmetatable({ kind = kind, events = {}, scripts = {}, shown = true }, frameMeta)
        if name then _G[name] = f end
        return f
    end
    function frameMethods:RegisterEvent(event)
        if not KNOWN_EVENTS[event] then error("Attempt to register unknown event \"" .. event .. "\"") end
        self.events[event] = true
    end
    function frameMethods:UnregisterEvent(event) self.events[event] = nil end
    function frameMethods:IsEventRegistered(event) return self.events[event] == true end
    function frameMethods:SetScript(script, fn)
        self.scripts[script] = fn
        -- In game, giving a frame a key handler switches its keyboard input on.
        if fn and (script == "OnKeyDown" or script == "OnKeyUp") then self.keyboard = true end
        if fn and script == "OnGamePadButtonDown" then self.gamepad = true end
        if script == "OnEvent" then self.onEvent = fn end
    end
    function frameMethods:GetScript(script) return self.scripts[script] end
    function frameMethods:HookScript(script, fn)
        local prev = self.scripts[script]
        self.scripts[script] = function(...)
            if prev then prev(...) end
            fn(...)
        end
    end
    function frameMethods:GetParent() return self.parent end
    function frameMethods:SetParent(p) self.parent = p end
    function frameMethods:GetPoint() if self.point then return unpack(self.point) end end
    function frameMethods:ClearAllPoints() self.point = nil end
    function frameMethods:Show()
        local was = self.shown
        self.shown = true
        if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function frameMethods:Hide()
        local was = self.shown
        self.shown = false
        if was and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    -- A separate function in game, not a call to Show or Hide (hooks on those don't see it).
    function frameMethods:SetShown(v)
        if v then frameMethods.Show(self) else frameMethods.Hide(self) end
    end
    function frameMethods:IsShown() return self.shown end
    -- Shown, and every parent shown too (as in game).
    function frameMethods:IsVisible()
        local f = self
        while f do
            if not f.shown then return false end
            f = f.parent
        end
        return true
    end
    function frameMethods:SetTexture(t) self.texture = t end
    function frameMethods:SetText(text) self.text = text end
    function frameMethods:GetText() return self.text end
    function frameMethods:SetID(id) self.id = id end
    function frameMethods:SetSize(w, h) self.width, self.height = w, h end
    function frameMethods:SetWidth(w) self.width = w end
    function frameMethods:GetWidth() return self.width or 0 end
    function frameMethods:SetAlpha(a) self.alpha = a end
    function frameMethods:SetFrameLevel(n) self.level = n end
    function frameMethods:GetFrameLevel() return self.level or 1 end
    -- Colours reuse their table, so they don't count as the addon's garbage in perf.lua.
    function frameMethods:SetVertexColor(r, g, b, a)
        local t = self.vertex or {}
        t[1], t[2], t[3], t[4] = r, g, b, a
        self.vertex = t
    end
    function frameMethods:SetTextColor(r, g, b)
        local t = self.color or {}
        t[1], t[2], t[3] = r, g, b
        self.color = t
    end
    function frameMethods:SetTexCoord(...) self.texCoord = { ... } end
    function frameMethods:IsProtected() return false end
    function frameMethods:EnableKeyboard(on) self.keyboard = on end
    function frameMethods:EnableGamePadButton(on) self.gamepad = on end
    function frameMethods:GetAlpha() return self.alpha or 1 end
    function frameMethods:GetID() return self.id end
    function frameMethods:SetAttribute(k, v) self.attributes = self.attributes or {}; self.attributes[k] = v end
    function frameMethods:GetAttribute(k) return self.attributes and self.attributes[k] end
    function frameMethods:SetPoint(point, rel, relPoint, x, y) self.point = { point, rel, relPoint, x, y } end
    function frameMethods:LockHighlight() self.highlightLocked = true end
    function frameMethods:UnlockHighlight() self.highlightLocked = false end
    function frameMethods:CreateFontString()
        local fs = newObject("FontString")
        self.regions = self.regions or {}
        self.regions[#self.regions + 1] = fs
        return fs
    end
    function frameMethods:GetRegions() return unpack(self.regions or {}) end
    function frameMethods:GetObjectType() return self.kind end
    function frameMethods:CreateTexture() return newObject("Texture") end
    function frameMethods:CreateLine()
        local line = newObject("Line")
        self.lines = self.lines or {}
        self.lines[#self.lines + 1] = line
        return line
    end
    function frameMethods:SetStartPoint(point, rel, x, y) self.from = { point, rel, x, y } end
    function frameMethods:SetEndPoint(point, rel, x, y) self.to = { point, rel, x, y } end
    M.missingTemplates = {}
    CreateFrame = function(kind, name, parent, template)
        if template and M.missingTemplates[template] then error("Couldn't find inherited node \"" .. template .. "\"") end
        local f = newObject(kind, name)
        f.template, f.parent, f.name = template, parent, name
        M.frames[#M.frames + 1] = f
        return f
    end
    -- Blizzard's tab helpers: they only mark which tab is selected.
    PanelTemplates_SelectTab = function(tab) tab.selectedTab = true end
    PanelTemplates_DeselectTab = function(tab) tab.selectedTab = false end

    UIParent = newObject("Frame", "UIParent")
    UIParent.GetEffectiveScale = function() return 1 end
    Minimap = newObject("Frame", "Minimap")
    Minimap.GetWidth = function() return 140 end
    Minimap.GetCenter = function() return 1000, 600 end
    Minimap.GetEffectiveScale = function() return 1 end
    M.mouse = { 1000, 600 }
    GetCursorPosition = function() return M.mouse[1], M.mouse[2] end
    UISpecialFrames = {}
    GameTooltip = M.tooltip()

    -- The character: like build 70009, first name and surname as two values.
    UnitName = function()
        local first, surname = M.player.name:match("^(%S+) (.+)$")
        if first then return first, surname end
        return M.player.name
    end
    UnitClass = function() return "Paladin", M.player.class end
    UnitLevel = function() return M.player.level end
    UpdateAddOnMemoryUsage = function() end
    GetAddOnMemoryUsage = function() return 12.5 end
    C_Timer = { After = function(_, fn) M.timers[#M.timers + 1] = fn end }
    M.timers = {}

    -- Combat.
    InCombatLockdown = function() return M.combat end

    -- Console settings (GetCVar) and a game controller (M.pad = true while one is in use).
    M.cvars = {}
    GetCVar = function(name) return M.cvars[name] end
    M.pad = false
    IsUsingGamepad = function() return M.pad end
    C_GamePad = {
        IsEnabled = function() return M.pad end,
        GetActiveDeviceID = function() return M.pad and 1 or nil end,
    }

    -- Modifier keys held (M.mods.shift...), the bar page and the stance/form bar offset.
    M.mods = { shift = false, ctrl = false, alt = false }
    IsShiftKeyDown = function() return M.mods.shift end
    IsControlKeyDown = function() return M.mods.ctrl end
    IsAltKeyDown = function() return M.mods.alt end
    M.page, M.bonus = 1, 0
    GetActionBarPage = function() return M.page end
    GetBonusBarOffset = function() return M.bonus end

    -- Protected calls: in combat they're blocked (recorded, event fired, no effect).
    M.calls = {} -- every protected call made (out of combat too), by name
    local function protect(name, fn)
        return function(...)
            M.calls[#M.calls + 1] = name
            if M.combat then
                M.blocked[#M.blocked + 1] = name
                M.fire("ADDON_ACTION_BLOCKED", M.addonName, "UNKNOWN()")
                return
            end
            return fn(...)
        end
    end

    -- Action slots and the cursor. Placing onto a filled slot puts the old action on the
    -- cursor (measured). A macro slot reports the spell the macro shows, not the macro's
    -- index (measured): "macro", <spellID>, "spell".
    local function slotChanged(slot) M.fire("ACTIONBAR_SLOT_CHANGED", slot) end
    local function cursorFrom(action)
        if not action then return nil end
        if action.kind == "spell" then return { "spell", 1, "spell", action.id } end
        if action.kind == "macro" then return { "macro", action.macro } end
        if action.kind == "item" then return { "item", action.id } end
        return { action.kind, action.id }
    end
    local function actionFrom(cursor)
        if not cursor then return nil end
        if cursor[1] == "spell" then return { kind = "spell", id = cursor[4] } end
        if cursor[1] == "macro" then return { kind = "macro", macro = cursor[2] } end
        return { kind = cursor[1], id = cursor[2] }
    end
    HasAction = function(slot) return M.slots[slot] ~= nil end
    GetActionInfo = function(slot)
        local a = M.slots[slot]
        if not a then return nil end
        if a.kind == "macro" then return "macro", M.macroSpell[a.macro] or 0, "spell" end
        return a.kind, a.id, a.kind == "spell" and "spell" or nil
    end
    GetActionText = function(slot)
        local a = M.slots[slot]
        return a and a.kind == "macro" and M.macros[a.macro] and M.macros[a.macro].name or nil
    end
    GetActionTexture = function(slot) return M.slots[slot] and 134400 or nil end
    GetCursorInfo = function() if M.cursor then return unpack(M.cursor) end end
    -- Not blocked in combat (measured: the probe cleared an item off the cursor in combat).
    ClearCursor = function() M.cursor, M.held = nil, nil end
    PickupAction = protect("PickupAction", function(slot)
        local old = M.slots[slot]
        M.slots[slot] = actionFrom(M.cursor)
        M.cursor = cursorFrom(old)
        slotChanged(slot)
    end)
    PlaceAction = protect("PlaceAction", function(slot)
        if not M.cursor then return end
        local old = M.slots[slot]
        M.slots[slot] = actionFrom(M.cursor)
        M.cursor = cursorFrom(old)
        slotChanged(slot)
    end)
    C_ActionBar = {
        PutActionInSlot = protect("C_ActionBar.PutActionInSlot", function(slot) PlaceAction(slot) end),
        GetActionBarPage = function() return 1 end,
        GetBonusBarOffset = function() return 0 end,
        HasAction = function(slot) return HasAction(slot) end,
        GetActionTexture = function(slot) return GetActionTexture(slot) end,
    }
    PickupMacro = protect("PickupMacro", function(index)
        if M.macros[index] then M.cursor = { "macro", index } end
    end)
    -- Gear and bags. Picking an item up leaves it in place (locked, in game) until it's put
    -- down; putting it on a filled place swaps the two; ClearCursor puts it back. An item
    -- goes only in a gear slot its equip location allows, and a two-hander in the main hand
    -- sends the off hand to a free bag slot (or fails if there's none).
    local function idOf(item)
        if type(item) == "number" then return item end
        if type(item) == "string" then return tonumber(item:match("item:(%d+)")) end
    end
    M.idOf = idOf
    local function linkOf(item)
        if not item then return nil end
        local s = type(item) == "number" and ("item:" .. item .. ":0:0:0:0:0:0:0:20") or item
        return "|cffffffff|H" .. s .. "|h[" .. tostring(M.itemNames[idOf(item)]) .. "]|h|r"
    end
    local FITS = {
        INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 }, INVTYPE_CHEST = { 5 },
        INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
        INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
        INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
        INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
        INVTYPE_TABARD = { 19 },
    }
    local function fits(item, slot)
        for _, s in ipairs(FITS[M.equipLoc[idOf(item)] or ""] or {}) do if s == slot then return true end end
        return false
    end
    -- A place: { "inv", slot } or { "bag", bag, slot }.
    local function get(place)
        if place[1] == "inv" then return M.inventory[place[2]] end
        return M.bags[place[2]][place[3]]
    end
    local function set(place, item)
        if place[1] == "inv" then
            M.inventory[place[2]] = item
        else
            M.bags[place[2]][place[3]] = item
        end
    end
    local function lockKey(place) return place[1] == "inv" and place[2] or (place[2] .. ":" .. place[3]) end
    local function freeBagPlace(avoid)
        for bag = 4, 0, -1 do
            if (M.bagFamily[bag] or 0) == 0 then
                for slot = 1, M.bags[bag].size do
                    if not M.bags[bag][slot] and lockKey({ "bag", bag, slot }) ~= avoid then return { "bag", bag, slot } end
                end
            end
        end
    end
    M.held = nil -- the place the item on the cursor came from
    local function BankBag(bag) return bag >= 6 and bag <= 14 end
    local function pickupAt(place)
        if M.cursor and M.cursor[1] ~= "item" then return end
        if place[1] == "bag" and BankBag(place[2]) and not M.bankOpen then return end
        if not M.held then
            local item = get(place)
            if item and not M.locked[lockKey(place)] then
                M.held = place
                M.cursor = { "item", idOf(item), linkOf(item) }
            end
            return
        end
        -- Putting down what's held.
        local from = M.held
        local item, there = get(from), get(place)
        if lockKey(from) == lockKey(place) then M.held, M.cursor = nil, nil; return end
        if place[1] == "inv" and not fits(item, place[2]) then return end
        if from[1] == "inv" and there and not fits(there, from[2]) then return end
        if place[1] == "inv" and place[2] == 16 and M.equipLoc[idOf(item)] == "INVTYPE_2HWEAPON" and M.inventory[17]
            and not (from[1] == "inv" and from[2] == 17) then
            local free = freeBagPlace(lockKey(from))
            if not free then return end -- "Inventory is full"
            set(free, M.inventory[17])
            M.inventory[17] = nil
        end
        set(place, item)
        set(from, there)
        M.held, M.cursor = nil, nil
        if M.lockMoves then M.locked[lockKey(from)], M.locked[lockKey(place)] = true, true end
        for _, p in ipairs({ from, place }) do
            if p[1] == "inv" then M.fire("PLAYER_EQUIPMENT_CHANGED", p[2], get(p) == nil) end
        end
    end
    -- Talking to a banker, and walking away (the interaction manager's events come too).
    function M.openBank()
        M.bankOpen = true
        M.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.Banker)
        M.fire("BANKFRAME_OPENED")
    end
    function M.closeBank()
        M.bankOpen = false
        M.fire("BANKFRAME_CLOSED")
        M.fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", Enum.PlayerInteractionType.Banker)
    end
    function M.unlock()
        M.locked = {}
        M.fire("ITEM_LOCK_CHANGED")
    end
    -- The game's switches for Blizzard's extra bars, as Options > Action Bars sets them:
    -- bottom left, bottom right, right, right 2, bars 6-8. Setting them only stores them
    -- (measured 2026-09-29); Blizzard's MultiActionBar_Update then shows or hides each bar
    -- frame, unless M.togglesWork is false (as if the game ignored it).
    M.barToggles = { false, false, false, false, false, false, false }
    M.togglesWork, M.toggleCalls = true, nil
    local TOGGLE_FRAMES = { "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
        "MultiBar5", "MultiBar6", "MultiBar7" }
    GetActionBarToggles = function() return unpack(M.barToggles) end
    SetActionBarToggles = protect("SetActionBarToggles", function(...)
        M.barToggles = { ... }
        M.toggleCalls = (M.toggleCalls or 0) + 1
    end)
    MultiActionBar_Update = function()
        if not M.togglesWork then return end
        for i, name in ipairs(TOGGLE_FRAMES) do
            local f = _G[name]
            if f then f:SetShown(M.barToggles[i] and true or false) end
        end
    end
    GetInventoryItemID = function(_, slot) return idOf(M.inventory[slot]) end
    GetInventoryItemLink = function(_, slot)
        if M.linksNotReady then return nil end
        return linkOf(M.inventory[slot])
    end
    IsInventoryItemLocked = function(slot) return M.locked[slot] == true end
    PickupInventoryItem = function(slot) pickupAt({ "inv", slot }) end
    CursorHasItem = function() return M.cursor ~= nil and M.cursor[1] == "item" end
    UnitIsDeadOrGhost = function() return M.dead end
    M.dualWield = true
    CanDualWield = function() return M.dualWield end
    C_Container = {
        GetContainerNumSlots = function(bag) return M.bags[bag] and M.bags[bag].size or 0 end,
        GetContainerNumFreeSlots = function(bag)
            local b, n = M.bags[bag], 0
            if not b then return 0, 0 end
            for slot = 1, b.size do if not b[slot] then n = n + 1 end end
            return n, M.bagFamily[bag] or 0
        end,
        GetContainerItemInfo = function(bag, slot)
            if BankBag(bag) and not M.bankOpen then return nil end -- read as empty, as in game
            local item = M.bags[bag] and M.bags[bag][slot]
            if not item then return nil end
            return { itemID = idOf(item), hyperlink = linkOf(item), isLocked = M.locked[bag .. ":" .. slot] == true,
                stackCount = 1 }
        end,
        GetContainerItemLink = function(bag, slot) return linkOf(M.bags[bag] and M.bags[bag][slot]) end,
        PickupContainerItem = function(bag, slot) pickupAt({ "bag", bag, slot }) end,
    }
    C_EquipmentSet = {
        GetEquipmentSetIDs = function()
            local ids = {}
            for i in ipairs(M.sets) do ids[i] = i end
            return ids
        end,
        GetEquipmentSetInfo = function(id)
            local s = M.sets[id]
            if s then return s.name, 1, id, s.equipped or false end
        end,
    }
    C_Item = {
        GetItemInfoInstant = function(item)
            local id = idOf(item)
            return id, nil, nil, M.equipLoc[id], 100000 + (id or 0)
        end,
        GetItemNameByID = function(id) return M.itemNames[id] end,
        PickupItem = function(id) if (M.itemCount[id] or 0) > 0 then M.cursor = { "item", id } end end,
        GetItemCount = function(id) return M.itemCount[id] or 0 end,
        GetItemIconByID = function(id) return 100000 + id end,
    }

    -- Spells.
    local function spellInBook(id)
        for _, line in ipairs(M.spellbook) do
            for _, s in ipairs(line.spells) do if s[1] == id then return s end end
        end
    end
    C_Spell = {
        PickupSpell = protect("C_Spell.PickupSpell", function(id)
            local s = spellInBook(id)
            if (s and not s.future) or M.otherSpells[id] then M.cursor = { "spell", 1, "spell", id } end
        end),
        GetSpellName = function(id) local s = spellInBook(id) return s and s[2] or M.spellNames[id] end,
        GetSpellSubtext = function(id) local s = spellInBook(id) return s and s[3] or nil end,
        GetSpellTexture = function(id) return 200000 + id end,
        GetOverrideSpell = function(id) return id end,
    }
    IsSpellKnown = function(id) local s = spellInBook(id) return s ~= nil and not s.future end
    IsPlayerSpell = function(id) return M.otherSpells[id] == true or IsSpellKnown(id) end
    -- Spells still to learn are in the spellbook with future = true and the level they come at.
    C_Spell.GetSpellLevelLearned = function(id) local s = spellInBook(id) return s and s.level or 0 end
    C_Spell.GetSpellLink = function(id) return "|Hspell:" .. id .. "|h[" .. tostring(C_Spell.GetSpellName(id)) .. "]|h" end
    M.links = {}
    ChatEdit_InsertLink = function(link) M.links[#M.links + 1] = link end
    -- The frames under the mouse (GetMouseFoci) and the mouse pointer's picture.
    M.mouseFoci = {}
    GetMouseFoci = function() return M.mouseFoci end
    M.pointer = nil
    SetCursor = function(texture) M.pointer = texture end
    ResetCursor = function() M.pointer = nil end
    M.modifiedClick = false
    IsModifiedClick = function() return M.modifiedClick end
    GetNumMacros = function()
        local account, perChar = 0, 0
        for index in pairs(M.macros) do
            if index <= 120 then account = account + 1 else perChar = perChar + 1 end
        end
        return account, perChar
    end
    local function bookItem(index)
        local n = 0
        for _, line in ipairs(M.spellbook) do
            for _, s in ipairs(line.spells) do
                n = n + 1
                if n == index then return s end
            end
        end
    end
    C_SpellBook = {
        GetNumSpellBookSkillLines = function() return #M.spellbook end,
        GetSpellBookSkillLineInfo = function(i)
            local offset = 0
            for j = 1, i - 1 do offset = offset + #M.spellbook[j].spells end
            local line = M.spellbook[i]
            return line and { name = line.name, itemIndexOffset = offset, numSpellBookItems = #line.spells }
        end,
        GetSpellBookItemInfo = function(index)
            local s = bookItem(index)
            return s and { itemType = s.flyout and 4 or s.future and 2 or 1, spellID = not s.flyout and s[1] or nil,
                iconID = 300000 + s[1],
                actionID = s[1], name = s[2], subName = s[3] or "", isPassive = s.passive or false }
        end,
        PickupSpellBookItem = protect("C_SpellBook.PickupSpellBookItem", function(index)
            local s = bookItem(index)
            if s then M.cursor = { "spell", index, "spell", s[1] } end
        end),
    }

    -- Keybindings: one live set; SaveBindings(set) writes it and makes that set current
    -- (measured: SaveBindings(2) alone switches to character keybinds, keeping every bind).
    -- Override bindings (what EllesmereUI and ElvUI set), seen when asked to check them.
    M.overrides = {}
    GetBindingAction = function(key, checkOverride)
        if checkOverride and M.overrides[key] then return M.overrides[key] end
        return M.bindings[key] or ""
    end
    -- The game's list of binding commands: every command bound here, in name order.
    local function commands()
        local list, seen = {}, {}
        for _, cmd in pairs(M.bindings) do
            if not seen[cmd] then seen[cmd] = true; list[#list + 1] = cmd end
        end
        table.sort(list)
        return list
    end
    GetNumBindings = function() return #commands() end
    GetBinding = function(i)
        local cmd = commands()[i]
        if cmd then return cmd, "category", GetBindingKey(cmd) end
    end
    -- Names from the game's Key Bindings list (M.bindingNames), else the command itself.
    -- GetBindingText returns what it's given (in game it gave raw commands back).
    M.bindingNames = { MOVEFORWARD = "Move Forward", TOGGLEAUTORUN = "Toggle Autorun" }
    GetBindingName = function(command) return M.bindingNames[command] or command end
    GetBindingText = function(text) return text end
    GetMacroInfo = function(nameOrIndex)
        for index, m in pairs(M.macros) do
            if index == nameOrIndex or m.name == nameOrIndex then return m.name, m.icon or 134400, m.body end
        end
    end
    -- The game's icon lists for macros: they add file IDs to the table given.
    GetMacroIcons = function(t) for i = 1, 60 do t[#t + 1] = 700000 + i end end
    GetMacroItemIcons = function(t) for i = 1, 20 do t[#t + 1] = 800000 + i end end
    GetMacroIndexByName = function(name)
        for index, m in pairs(M.macros) do if m.name == name then return index end end
        return 0
    end
    GetBindingKey = function(command)
        local keys = {}
        for key, cmd in pairs(M.bindings) do if cmd == command then keys[#keys + 1] = key end end
        table.sort(keys)
        return unpack(keys)
    end
    SetBinding = protect("SetBinding", function(key, command)
        M.bindings[key] = command
        M.fire("UPDATE_BINDINGS")
        return true
    end)
    GetCurrentBindingSet = function() return M.bindingSet end
    SaveBindings = protect("SaveBindings", function(set)
        M.bindingSet = set
        M.savedSets[set] = copy(M.bindings)
    end)
    LoadBindings = protect("LoadBindings", function(set)
        if M.savedSets[set] then M.bindings = copy(M.savedSets[set]) end
        M.bindingSet = set
        M.fire("UPDATE_BINDINGS")
    end)
    for _, name in ipairs(PROTECTED) do
        if not name:find("%.") and not _G[name] then _G[name] = protect(name, function() end) end
    end

    -- Blizzard's context menus: the last menu built is kept in M.menu, its items in order as
    -- { kind, text, fn / isSelected, setSelected, enabled }.
    M.menu = nil
    MenuUtil = { CreateContextMenu = function(owner, generator)
        local root = { owner = owner, items = {} }
        local function add(kind, text, a, b)
            local item = { kind = kind, text = text, fn = a, isSelected = a, setSelected = b, enabled = true }
            function item:SetEnabled(v) self.enabled = v end
            root.items[#root.items + 1] = item
            return item
        end
        function root:CreateTitle(text) return add("title", text) end
        function root:CreateButton(text, fn) return add("button", text, fn) end
        function root:CreateCheckbox(text, isSelected, setSelected) return add("checkbox", text, isSelected, setSelected) end
        function root:CreateRadio(text, isSelected, setSelected) return add("radio", text, isSelected, setSelected) end
        generator(owner, root)
        M.menu = root
        return root
    end }

    -- Confirmation pop-ups: the last one shown.
    M.popup = nil
    StaticPopupDialogs = {}
    StaticPopup_Show = function(which, text1, text2, data) M.popup = { which = which, text = text1, data = data } end
    -- Errors passed to the error handler (BugGrabber in game).
    M.errors = {}
    -- One handler, as the game keeps one (a new function per call would be garbage the
    -- addon doesn't make in game).
    local errorHandler = function(err) M.errors[#M.errors + 1] = err end
    geterrorhandler = function() return errorHandler end
    hooksecurefunc = function(t, name, fn)
        if type(t) == "string" then t, name, fn = _G, t, name end
        local orig = t[name]
        t[name] = function(...)
            local r = { orig(...) }
            fn(...)
            return unpack(r)
        end
    end
    M.reloads = 0
    -- Sounds played, and the game's sound names (as listed on Forever).
    M.sounds = {}
    SOUNDKIT = { IG_ABILITY_ICON_DROP = 838, UI_CURSOR_PICKUP_OBJECT = 688, UI_CURSOR_DROP_OBJECT = 689,
        IG_PLAYER_INVITE_DECLINE = 882 }
    PlaySound = function(id) M.sounds[#M.sounds + 1] = id end
    -- Other addons loaded (M.loadedAddons["EllesmereUIMinimap"] = true...).
    M.loadedAddons = {}
    C_AddOns = { IsAddOnLoaded = function(name) return M.loadedAddons[name] == true end }
    ReloadUI = function() M.reloads = M.reloads + 1 end
    YES, NO = "Yes", "No"

    -- The game's Options panel: addon pages are canvases (our own frames) that it shows when
    -- their category is opened. M.withoutSettings leaves the Settings API out.
    M.settingsCategories, M.openedCategory, M.hiddenPanels = {}, nil, {}
    SettingsPanel = CreateFrame("Frame", "SettingsPanel")
    SettingsPanel:Hide()
    HideUIPanel = function(f)
        M.hiddenPanels[#M.hiddenPanels + 1] = f
        f:Hide()
    end
    Settings = nil
    if not M.withoutSettings then
        Settings = {
            RegisterCanvasLayoutCategory = function(frame, name)
                -- The game doesn't hide the frame: a new frame counts as shown, so showing
                -- it later fires no OnShow unless the addon hid it (Alts Forever, 2026-09-28).
                return { frame = frame, name = name, GetID = function() return "cat:" .. name end }
            end,
            RegisterAddOnCategory = function(cat) M.settingsCategories[#M.settingsCategories + 1] = cat end,
            OpenToCategory = function(id)
                for _, cat in ipairs(M.settingsCategories) do
                    if cat:GetID() == id then
                        SettingsPanel:Show()
                        cat.frame:Show()
                        M.openedCategory = id
                        return true
                    end
                end
            end,
        }
    end
    M.withoutSettings = nil

    KeystanceDB = nil
    ItemRack, ItemRackUser = nil, nil
    -- EllesmereUI's skinning API, only if a test asked for it (wow.withEllesmere) before
    -- loading. The callback is kept in M.skinCallback; the facade records every call.
    EllesmereUI, M.skinCallback, M.skinned = nil, nil, {}
    if M.withEllesmere then
        M.withEllesmere = nil
        EllesmereUI = { RegisterSkin = function(name, fn) M.skinName, M.skinCallback = name, fn end }
        M.skinFacade = {}
        for _, fname in ipairs({ "Shell", "CloseButton", "Inset", "Font", "Button", "StateButtonLabel", "Tab",
            "Panel", "SquareIcon", "Checkbox", "Dropdown", "ScrollBar" }) do
            M.skinFacade[fname] = function(obj) M.skinned[#M.skinned + 1] = { fname, obj } end
        end
        M.skinFacade.OnLooksChanged = function(fn) M.looksChanged = fn end
    end
    -- ElvUI, only if a test asked for it (wow.withElvUI): its engine (M.elv, initialised as at
    -- login), its Skins module and the toolkit methods it adds to every widget.
    ElvUI = nil
    if M.withElvUI then
        M.withElvUI = nil
        local S = {}
        for _, fname in ipairs({ "HandleFrame", "HandleButton", "HandleTab", "HandleCheckBox", "HandleScrollBar" }) do
            S[fname] = function(_, obj) M.skinned[#M.skinned + 1] = { fname, obj } end
        end
        local E = { Initialized = true }
        function E:GetModule(name) return name == "Skins" and S or nil end
        M.elv, M.elvSkins = E, S
        ElvUI = { E, {}, {}, {}, {} }
        for _, fname in ipairs({ "FontTemplate", "CreateBackdrop", "StyleButton", "SetTexCoords" }) do
            frameMethods[fname] = function(obj) M.skinned[#M.skinned + 1] = { fname, obj } end
        end
    end
    -- Globals the addon defines; cleared so a previous load is freed.
    Keystance_OnAddonCompartmentClick, Keystance_OnAddonCompartmentEnter = nil, nil
    Keystance_OnAddonCompartmentLeave = nil
    Keystance_Binding, BINDING_HEADER_KEYSTANCE, BINDING_NAME_KEYSTANCE_NEXT, BINDING_NAME_KEYSTANCE_TOGGLE = nil, nil, nil, nil
    for i = 1, 6 do _G["BINDING_NAME_KEYSTANCE_PROFILE" .. i] = nil end
    KeystanceMinimapButton, KeystanceFrame, KeystanceRunning = nil, nil, nil
    -- EllesmereUI's minimap tray list and regrid function, only if a test makes them.
    _EBS_AddonVisible, _EMIN_RefreshFlyout, OtherAddonMinimapButton = nil, nil, nil
    SLASH_KEYSTANCE1, SLASH_KEYSTANCE2 = nil, nil

    M.addonName = "Keystance"
    local ns = {}
    for _, file in ipairs(files) do
        assert(loadfile(file))("Keystance", ns)
    end
    return ns
end

function M.tooltip()
    return {
        lines = {},
        AddLine = function(self, text) self.lines[#self.lines + 1] = { text } end,
        AddDoubleLine = function(self, l, r) self.lines[#self.lines + 1] = { l, r } end,
        SetAction = function(self, slot) self.action = slot; self.lines[#self.lines + 1] = { "action:" .. slot } end,
        SetSpellByID = function(self, id) self.spell = id; self.lines[#self.lines + 1] = { "spell:" .. id } end,
        SetHyperlink = function(self, link) self.lines[#self.lines + 1] = { link } end,
        SetOwner = function(self, owner) self.owner, self.lines, self.shown, self.action = owner, {}, false, nil end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown, self.owner = false, nil end,
        IsShown = function(self) return self.shown end,
    }
end

function M.fire(event, ...)
    for _, f in ipairs(M.frames) do
        if f.events[event] and f.onEvent then f.onEvent(f, event, ...) end
    end
end

function M.login(saved)
    KeystanceDB = saved
    M.fire("ADDON_LOADED", "Keystance")
    M.fire("PLAYER_LOGIN")
end

-- Runs the C_Timer callbacks waiting (the next frame).
function M.runTimers()
    local waiting = M.timers
    M.timers = {}
    for _, fn in ipairs(waiting) do fn() end
end

function M.enterCombat()
    M.combat = true
    M.fire("PLAYER_REGEN_DISABLED")
end

function M.leaveCombat()
    M.combat = false
    M.fire("PLAYER_REGEN_ENABLED")
end

-- The item with this text in the last menu built.
function M.menuItem(text)
    for _, item in ipairs(M.menu and M.menu.items or {}) do
        if item.text == text then return item end
    end
end

return M
