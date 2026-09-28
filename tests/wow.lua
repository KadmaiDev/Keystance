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
    MODIFIER_STATE_CHANGED = true, ACTIONBAR_PAGE_CHANGED = true, UPDATE_BONUS_ACTIONBAR = true,
    SPELLS_CHANGED = true, LEARNED_SPELL_IN_SKILL_LINE = true,
    PLAYER_EQUIPMENT_CHANGED = true, UNIT_INVENTORY_CHANGED = true,
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
    M.itemCount = {}   -- [itemID] = count in bags

    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    issecretvalue = function(v) return v == SECRET end
    M.now = nil
    time = function(t) if t then return os.time(t) end return M.now or os.time() end
    GetTime = function() return M.clock or 0 end
    GetLocale = function() return M.locale or "enUS" end
    date = os.date
    print = function(msg) M.printed[#M.printed + 1] = msg end
    SlashCmdList = {}
    Enum = {
        SpellBookSpellBank = { Player = 0, Pet = 1 },
        SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 },
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
    function frameMethods:SetShown(v) if v then self:Show() else self:Hide() end end
    function frameMethods:IsShown() return self.shown end
    function frameMethods:IsVisible() return self.shown end
    function frameMethods:SetTexture(t) self.texture = t end
    function frameMethods:SetText(text) self.text = text end
    function frameMethods:GetText() return self.text end
    function frameMethods:SetID(id) self.id = id end
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

    -- Modifier keys held (M.mods.shift...), the bar page and the stance/form bar offset.
    M.mods = { shift = false, ctrl = false, alt = false }
    IsShiftKeyDown = function() return M.mods.shift end
    IsControlKeyDown = function() return M.mods.ctrl end
    IsAltKeyDown = function() return M.mods.alt end
    M.page, M.bonus = 1, 0
    GetActionBarPage = function() return M.page end
    GetBonusBarOffset = function() return M.bonus end

    -- Protected calls: in combat they're blocked (recorded, event fired, no effect).
    local function protect(name, fn)
        return function(...)
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
    ClearCursor = function() M.cursor = nil end
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
    C_Item = {
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
            if spellInBook(id) then M.cursor = { "spell", 1, "spell", id } end
        end),
        GetSpellName = function(id) local s = spellInBook(id) return s and s[2] or M.spellNames[id] end,
        GetSpellSubtext = function(id) local s = spellInBook(id) return s and s[3] or nil end,
        GetSpellTexture = function(id) return 200000 + id end,
        GetOverrideSpell = function(id) return id end,
    }
    IsSpellKnown = function(id) return spellInBook(id) ~= nil end
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
            return s and { itemType = s.flyout and 4 or 1, spellID = not s.flyout and s[1] or nil,
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
    M.reloads = 0
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
                frame:Hide() -- a registered canvas stays hidden until its page is opened
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
    KeystanceMinimapButton, KeystanceFrame, KeystanceRunning = nil, nil, nil
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
