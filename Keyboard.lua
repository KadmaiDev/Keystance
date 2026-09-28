-- Keystance Keyboard tab: a keyboard and mouse showing what each key does, with the
-- spell, macro or item icon of the action slot it triggers. Toggles show the Shift, Ctrl
-- and Alt layers (and combinations); holding a real modifier switches the view live.
-- Bound keys the drawn keyboard doesn't have are listed underneath. Read-only.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)
local L = ns.L

local ipairs, pairs, CreateFrame = ipairs, pairs, CreateFrame
local GetBindingAction, GetActionTexture, HasAction = GetBindingAction, GetActionTexture, HasAction
local IsShiftKeyDown, IsControlKeyDown, IsAltKeyDown = IsShiftKeyDown, IsControlKeyDown, IsAltKeyDown

local U = 34 -- one key unit, in pixels
local ROW_GAP = 8 -- extra space under the function row

-- The eight modifier layers, in the game's prefix order.
local PREFIXES = { "", "SHIFT-", "CTRL-", "CTRL-SHIFT-", "ALT-", "ALT-SHIFT-", "ALT-CTRL-", "ALT-CTRL-SHIFT-" }
local LAYER_NAMES = {
    L["Keys on their own"], L["Keys with Shift"], L["Keys with Ctrl"], L["Keys with Ctrl + Shift"],
    L["Keys with Alt"], L["Keys with Alt + Shift"], L["Keys with Alt + Ctrl"], L["Keys with Alt + Ctrl + Shift"],
}
local function LayerIndex(shift, ctrl, alt)
    return 1 + (shift and 1 or 0) + (ctrl and 2 or 0) + (alt and 4 or 0)
end

local toggles = { shift = false, ctrl = false, alt = false }

-- The layer shown: the real modifiers while any is held, else the toggles.
local function CurrentLayer()
    local shift, ctrl, alt = IsShiftKeyDown(), IsControlKeyDown(), IsAltKeyDown()
    if shift or ctrl or alt then return LayerIndex(shift, ctrl, alt), true end
    return LayerIndex(toggles.shift, toggles.ctrl, toggles.alt), false
end

---------------------------------------------------------------------------
-- Every bound key, for the "also bound" list (rebuilt when bindings change)
---------------------------------------------------------------------------
local bound, boundStale = {}, true -- { { key, command }, ... }
local function BoundKeys()
    if boundStale then
        boundStale = false
        local n = 0
        for command, keys in pairs((ns.ReadBindings())) do
            for _, key in ipairs(keys) do
                n = n + 1
                local e = bound[n] or {}
                bound[n] = e
                e[1], e[2] = key, command
            end
        end
        for i = n + 1, #bound do bound[i] = nil end
        table.sort(bound, function(a, b) return a[1] < b[1] end)
    end
    return bound
end

-- A command's name as the game's Key Bindings list shows it ("Toggle World Map" for
-- TOGGLEWORLDMAP). GetBindingText(command, "BINDING_NAME_") gave the raw command in game.
local function CommandName(command)
    if not command or command == "" then return nil end
    local text = GetBindingName and GetBindingName(command)
    if type(text) == "string" and text ~= "" then return text end
    return command
end

ns.CommandName = CommandName

-- A key's name as the game shows it ("Num Pad 1" for NUMPAD1).
local function KeyName(key)
    local text = GetBindingText and GetBindingText(key)
    if type(text) == "string" and text ~= "" then return text end
    return key
end

---------------------------------------------------------------------------
-- Key caps
---------------------------------------------------------------------------
local function CapTooltip(cap)
    if not cap.fullKey then return end
    GameTooltip:SetOwner(cap, "ANCHOR_RIGHT")
    if cap.slot and HasAction(cap.slot) then
        GameTooltip:SetAction(cap.slot)
    else
        GameTooltip:AddLine(CommandName(cap.command) or L["Not bound"])
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(L["Key"], cap.fullKey, 0.6, 0.6, 0.6, 1, 1, 1)
    if cap.command and cap.command ~= "" then
        GameTooltip:AddDoubleLine(L["Binding"], cap.command, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
    end
    if cap.slot then
        GameTooltip:AddDoubleLine(L["Action slot"], cap.slot, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function MakeCap(f, board, info, x, y)
    local w = info.w or 1
    local cap = CreateFrame("Button", nil, board)
    cap:SetSize(U * w - 3, U - 3)
    cap:SetPoint("TOPLEFT", board, "TOPLEFT", x, -y)
    local bg = cap:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.12, 0.9)
    cap.bg = bg
    local icon = cap:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:Hide()
    cap.icon = icon
    local label = cap:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", 3, -2)
    label:SetText(ns.KeyLabel(info[1]))
    cap.label = label
    -- A command's name, in a small font over up to two lines ("Toggle World Map").
    local name = cap:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
    name:SetPoint("BOTTOMLEFT", 1, 2)
    name:SetPoint("BOTTOMRIGHT", -1, 2)
    name:SetHeight(18)
    name:SetWordWrap(true)
    name:SetJustifyV("BOTTOM")
    name:SetJustifyH("CENTER")
    cap.name = name
    f.texts[#f.texts + 1] = label
    f.texts[#f.texts + 1] = name
    cap:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    cap:SetScript("OnEnter", CapTooltip)
    -- Something dragged here (a spell from the spell panel or the spellbook, an action off a
    -- bar) goes on this key; clicking while holding it does the same.
    local function Drop(self)
        if self.fullKey and GetCursorInfo() then ns.DropOnKey(self.fullKey, self.slot, self.command) end
    end
    cap:SetScript("OnReceiveDrag", Drop)
    -- While a raid marker (or another command) waits for a key, a click binds it here and a
    -- right-click cancels.
    cap:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cap:SetScript("OnClick", function(self, button)
        if ns.HeldBinding() then
            if button == "RightButton" then return ns.CancelBinding() end
            if self.fullKey then ns.BindHeld(self.fullKey, self.command) end
            return
        end
        Drop(self)
    end)
    cap:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cap.key, cap.mod, cap.blank = info[1], info.mod, info[1] == ""
    -- The full key name for each layer ("SHIFT-1"...), made once.
    cap.full = {}
    for i, prefix in ipairs(PREFIXES) do cap.full[i] = prefix .. info[1] end
    return cap
end

-- Draws a layout (once) and returns its caps and the set of keys it has.
local function BuildBoard(page, f, layoutKey)
    local board = CreateFrame("Frame", nil, page)
    board:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -48)
    board:SetSize(15 * U + 20 + 2 * U, 6 * U + ROW_GAP)
    local caps, drawn = {}, {}
    for r, row in ipairs(ns.LAYOUTS[layoutKey].rows) do
        local x = 0
        local y = (r - 1) * U + (r > 1 and ROW_GAP or 0)
        for _, info in ipairs(row) do
            x = x + (info.gap or 0) * U
            local cap = MakeCap(f, board, info, x, y)
            caps[#caps + 1] = cap
            if cap.blank then cap:Hide() end
            drawn[info[1]] = true
            x = x + (info.w or 1) * U
        end
    end
    -- The mouse, to the right of the keyboard.
    for i, key in ipairs(ns.MOUSE_KEYS) do
        local cap = MakeCap(f, board, { key }, 15 * U + 20 + ((i - 1) % 2) * U, U + ROW_GAP + math.floor((i - 1) / 2) * U)
        caps[#caps + 1] = cap
        drawn[key] = true
    end
    local mouse = board:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    mouse:SetPoint("BOTTOMLEFT", board, "TOPLEFT", 15 * U + 20, -(U + ROW_GAP) + 2)
    mouse:SetText(L["Mouse"])
    f.texts[#f.texts + 1] = mouse
    board.caps, board.drawn = caps, drawn
    return board
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local function RefreshCaps(page, layer)
    for _, cap in ipairs(page.board.caps) do
        if cap.mod then
            local on = (cap.key == "SHIFT" and (layer - 1) % 2 == 1) or (cap.key == "CTRL" and math.floor((layer - 1) / 2) % 2 == 1)
                or (cap.key == "ALT" and layer > 4)
            cap.bg:SetColorTexture(on and 0.45 or 0.1, on and 0.35 or 0.1, on and 0.1 or 0.12, 0.9)
            cap.fullKey, cap.command, cap.slot = nil, nil, nil
        elseif not cap.blank then
            local full = cap.full[layer]
            local command = GetBindingAction(full, true)
            local slot = ns.CommandSlot(command)
            local texture = slot and GetActionTexture(slot)
            cap.fullKey, cap.command, cap.slot = full, command, slot
            if texture then
                cap.icon:SetTexture(texture)
                cap.icon:Show()
                cap.name:SetText("")
            else
                cap.icon:Hide()
                cap.name:SetText(slot and "" or (CommandName(command) or ""))
            end
            cap.bg:SetColorTexture(0.1, 0.1, 0.12, (command ~= "") and 0.9 or 0.45)
        end
    end
end

-- "NUMPAD1 Holy Light" for the list, cached per key and command.
local partCache = {}
local function Part(key, command)
    local byCommand = partCache[key]
    if not byCommand then
        byCommand = {}
        partCache[key] = byCommand
    end
    local part = byCommand[command]
    if not part then
        part = KeyName(key) .. ": " .. (CommandName(command) or command)
        byCommand[command] = part
    end
    return part
end

local otherParts = {}
local function RefreshOthers(page, layer)
    local prefix = PREFIXES[layer]
    local drawn = page.board.drawn
    local n = 0
    for _, e in ipairs(BoundKeys()) do
        local p, base = ns.SplitKey(e[1])
        if p == prefix and not drawn[base] then
            n = n + 1
            otherParts[n] = Part(e[1], e[2])
        end
    end
    for i = n + 1, #otherParts do otherParts[i] = nil end
    page.others:SetText(n > 0 and (L["Also bound: "] .. table.concat(otherParts, ", ")) or "")
end

local function Refresh(page)
    local key = ns.LayoutKey(ns.db.settings.layout)
    if page.layoutKey ~= key then
        if page.board then page.board:Hide() end
        page.boards[key] = page.boards[key] or BuildBoard(page, page.window, key)
        page.board = page.boards[key]
        page.board:Show()
        page.layoutKey = key
        for _, fs in ipairs(page.window.texts) do ns.SkinText(fs) end
    end
    local layer, live = CurrentLayer()
    for _, t in ipairs(page.toggles) do
        local on = toggles[t.mod]
        if on then t:LockHighlight() else t:UnlockHighlight() end
        t:SetText((on and "|cffffd100" or "") .. t.title .. (on and "|r" or ""))
    end
    page.layerText:SetText(LAYER_NAMES[layer] .. (live and L[" (held)"] or ""))
    page.layoutRow:Refresh()
    local held = ns.HeldBinding()
    page.binding:SetShown(held ~= nil)
    if held then page.binding:SetText(L["Click a key for %s (right-click cancels)"]:format(held.label)) end
    RefreshCaps(page, layer)
    RefreshOthers(page, layer)
end

local function Build(page, f)
    page.window, page.boards, page.toggles = f, {}, {}
    local x = 16
    for _, t in ipairs({ { "shift", L["Shift"] }, { "ctrl", L["Ctrl"] }, { "alt", L["Alt"] } }) do
        local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        b:SetSize(64, 22)
        b:SetPoint("TOPLEFT", page, "TOPLEFT", x, -14)
        b.mod, b.title = t[1], t[2]
        b:SetScript("OnClick", function(self)
            toggles[self.mod] = not toggles[self.mod]
            ns.RefreshWindow()
        end)
        f.buttons[#f.buttons + 1] = b
        page.toggles[#page.toggles + 1] = b
        x = x + 68
    end
    local layerText = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    layerText:SetPoint("LEFT", page.toggles[3], "RIGHT", 12, 0)
    page.layerText = layerText
    f.texts[#f.texts + 1] = layerText
    -- The keyboard drawn: automatic (from the game's language), US or UK.
    local row = ns.ChoiceRow(f, page, { { "auto", L["Automatic"] }, { "ansi", L["US"] }, { "iso", L["UK"] } },
        function() return ns.db.settings.layout or "auto" end,
        function(value)
            ns.db.settings.layout = value
            ns.RefreshWindow()
        end, 76)
    row:SetPoint("TOPRIGHT", page, "TOPRIGHT", -16, -14)
    page.layoutRow = row
    local binding = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    binding:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -36)
    binding:SetTextColor(0.4, 0.8, 1)
    binding:Hide()
    page.binding = binding
    f.texts[#f.texts + 1] = binding
    local others = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    others:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -(48 + 6 * U + ROW_GAP + 12))
    others:SetPoint("RIGHT", page, "RIGHT", -16, 0)
    others:SetJustifyH("LEFT")
    others:SetWordWrap(true)
    page.others = others
    f.texts[#f.texts + 1] = others
    page.Refresh = Refresh
end

ns.pageBuilders.keyboard = Build

-- Keep an open window current; a closed one costs one check.
ns.On("UPDATE_BINDINGS", function()
    boundStale = true
    ns.RequestRefresh()
end)
ns.On("MODIFIER_STATE_CHANGED", function() ns.RequestRefresh("keyboard") end)
