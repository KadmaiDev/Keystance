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
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\media\\"
local CIRCLE = MEDIA .. "circle.tga" -- a white disc: the dark backing of a controller button's badge
local ROW_GAP = 8 -- extra space under the function row
local NUMPAD_WIDTH = 830 -- the window's width while the numpad is drawn (keys stay full size)

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

local function MakeCap(f, board, info, x, y, unit)
    unit = unit or U
    local w = info.w or 1
    local cap = CreateFrame("Button", nil, board)
    cap:SetSize(unit * w - 3, unit * (info.h or 1) - 3)
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
    cap.icon, cap.whole = icon, false
    local label = cap:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", 3, -2)
    label:SetText(ns.KeyLabel(info[1]))
    cap.label = label
    if info[1]:sub(1, 3) == "PAD" then
        -- A controller button: its symbol as a badge on the icon's top-left corner, half
        -- outside it, on a dark disc, so the spell icon stays clear.
        local badge = cap:CreateTexture(nil, "OVERLAY", nil, 6)
        badge:SetTexture(CIRCLE)
        badge:SetVertexColor(0.05, 0.05, 0.07, 0.95)
        badge:SetSize(20, 20)
        badge:SetPoint("CENTER", cap, "TOPLEFT", 3, -3)
        label:ClearAllPoints()
        label:SetPoint("CENTER", badge, "CENTER", 0, 0)
        label:SetDrawLayer("OVERLAY", 7)
        cap.badge = badge
    end
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
        if button == "RightButton" then
            -- Right-click: remove what's on the key (after asking), unless that right-click
            -- just dropped a held raid marker.
            if ns.HoldJustEnded() then return end
            if self.fullKey and not GetCursorInfo() then ns.AskRemove(self.fullKey, self.slot, self.command) end
            return
        end
        Drop(self)
    end)
    -- Dragging a key picks up its action, as dragging off a real bar does.
    cap:RegisterForDrag("LeftButton")
    cap:SetScript("OnDragStart", function(self)
        if self.slot then ns.PickupFromSlot(self.slot, self.fullKey, self.command) end
    end)
    cap:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cap.key, cap.mod, cap.blank = info[1], info.mod, info[1] == ""
    cap.isKeyCap = true -- a raid marker dragged from the spell panel looks for this under the mouse
    -- The full key name for each layer ("SHIFT-1"...), made once.
    cap.full = {}
    for i, prefix in ipairs(PREFIXES) do cap.full[i] = prefix .. info[1] end
    return cap
end

-- Draws a layout (once) and returns its caps and the set of keys it has. With `numpad`, the
-- navigation block and the numpad sit to the right (the window widens to fit), and the
-- mouse keys move to a row underneath.
local function BuildBoard(page, f, layoutKey, numpad)
    local u = U
    local board = CreateFrame("Frame", nil, page)
    board:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -48)
    local caps, drawn = {}, {}
    local function Add(info, x, y)
        local cap = MakeCap(f, board, info, x, y, u)
        caps[#caps + 1] = cap
        if cap.blank then cap:Hide() end
        drawn[info[1]] = true
    end
    local function RowY(r) return (r - 1) * u + (r > 1 and ROW_GAP or 0) end
    local layout = ns.LAYOUTS[layoutKey]
    if layout.pad then
        -- A controller: its buttons on a drawing of one (media/controller.tga, drawn in these
        -- units by tools/make_controller.py); no mouse, no numpad.
        local drawing = board:CreateTexture(nil, "BACKGROUND")
        drawing:SetAllPoints()
        drawing:SetTexture(MEDIA .. "controller.tga")
        board.drawing = drawing
        for _, info in ipairs(layout.keys) do Add(info, info.x * u, info.y * u) end
        board:SetSize(15.5 * u, 8 * u)
        board.caps, board.drawn = caps, drawn
        return board
    end
    for r, row in ipairs(layout.rows) do
        local x = 0
        for _, info in ipairs(row) do
            x = x + (info.gap or 0) * u
            Add(info, x, RowY(r))
            x = x + (info.w or 1) * u
        end
    end
    local mouse = board:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    mouse:SetText(L["Mouse"])
    f.texts[#f.texts + 1] = mouse
    if numpad then
        for _, block in ipairs({ { ns.NAV_KEYS, 15.5 }, { ns.NUMPAD_KEYS, 19 } }) do
            for _, info in ipairs(block[1]) do Add(info, (block[2] + info.x) * u, RowY(info.row)) end
        end
        -- The mouse, in a row under the keyboard.
        local y = RowY(6) + u + 10
        mouse:SetPoint("TOPLEFT", board, "TOPLEFT", 0, -y)
        for i, key in ipairs(ns.MOUSE_KEYS) do Add({ key }, (i + 1) * u, y) end
        board:SetSize(23 * u, y + u)
    else
        -- The mouse, to the right of the keyboard.
        for i, key in ipairs(ns.MOUSE_KEYS) do
            Add({ key }, 15 * u + 20 + ((i - 1) % 2) * u, u + ROW_GAP + math.floor((i - 1) / 2) * u)
        end
        mouse:SetPoint("BOTTOMLEFT", board, "TOPLEFT", 15 * u + 20, -(u + ROW_GAP) + 2)
        board:SetSize(15 * u + 20 + 2 * u, 6 * u + ROW_GAP)
    end
    board.caps, board.drawn = caps, drawn
    return board
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local function Tint(cap, r, g, b, a)
    cap.bg:SetColorTexture(r, g, b, a)
end

local function RefreshCaps(page, layer, padMods)
    for _, cap in ipairs(page.board.caps) do
        -- A modifier: Shift, Ctrl or Alt, or the controller button set to act as one.
        local modAs = cap.mod and cap.key or (padMods and padMods[cap.key])
        if modAs then
            local on = (modAs == "SHIFT" and (layer - 1) % 2 == 1) or (modAs == "CTRL" and math.floor((layer - 1) / 2) % 2 == 1)
                or (modAs == "ALT" and layer > 4)
            cap.icon:Hide()
            -- A controller button acting as one says so (a keyboard's Shift key already does).
            cap.name:SetText(cap.mod and "" or (modAs == "SHIFT" and L["Shift"] or modAs == "CTRL" and L["Ctrl"] or L["Alt"]))
            Tint(cap, on and 0.45 or 0.1, on and 0.35 or 0.1, on and 0.1 or 0.12, 0.9)
            cap.fullKey, cap.command, cap.slot = nil, nil, nil
        elseif not cap.blank then
            local full = cap.full[layer]
            local command = GetBindingAction(full, true)
            local slot = ns.CommandSlot(command)
            local texture = slot and GetActionTexture(slot)
            cap.fullKey, cap.command, cap.slot = full, command, slot
            -- A raid marker shows its own picture, uncropped (spell icons have a border to trim).
            local picture = not texture and ns.CommandIcon(command)
            if texture or picture then
                local whole = picture and true or false
                if cap.whole ~= whole then -- only when it changes: redraws stay allocation-free
                    cap.whole = whole
                    if whole then cap.icon:SetTexCoord(0, 1, 0, 1) else cap.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
                end
                cap.icon:SetTexture(texture or picture)
                cap.icon:Show()
                cap.name:SetText("")
            else
                cap.icon:Hide()
                cap.name:SetText(slot and "" or (CommandName(command) or ""))
            end
            Tint(cap, 0.1, 0.1, 0.12, (command ~= "") and 0.9 or 0.45)
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
        local picture = ns.CommandIcon(command)
        part = KeyName(key) .. ": " .. (picture and ("|T" .. picture .. ":14|t ") or "") .. (CommandName(command) or command)
        byCommand[command] = part
    end
    return part
end

local otherParts = {}
-- Bound keys of this kind of device (keyboard and mouse, or controller) that aren't drawn,
-- in this layer: at most MAX_OTHERS of them, then "and N more", so the list never runs
-- past the tab. A controller view doesn't list keyboard keys, nor a keyboard view
-- controller buttons.
local MAX_OTHERS = 24
local function RefreshOthers(page, layer, pad)
    local prefix = PREFIXES[layer]
    local drawn = page.board.drawn
    local n, extra = 0, 0
    for _, e in ipairs(BoundKeys()) do
        local p, base = ns.SplitKey(e[1])
        if p == prefix and not drawn[base] and (base:sub(1, 3) == "PAD") == (pad and true or false) then
            if n < MAX_OTHERS then
                n = n + 1
                otherParts[n] = Part(e[1], e[2])
            else
                extra = extra + 1
            end
        end
    end
    for i = n + 1, #otherParts do otherParts[i] = nil end
    local text = n > 0 and (L["Also bound: "] .. table.concat(otherParts, ", ")) or ""
    if extra > 0 then text = text .. L[", and %d more"]:format(extra) end
    page.others:SetText(text)
end

local padButton = {} -- [SHIFT/CTRL/ALT] = the controller button acting as it (reused)
local function Refresh(page)
    local key = ns.LayoutKey(ns.db.settings.layout)
    local pad = ns.LAYOUTS[key].pad
    local numpad = not pad and ns.db.settings.numpad and true or false
    local boardKey = key .. (numpad and "+numpad" or "")
    if page.boardKey ~= boardKey then
        if page.board then page.board:Hide() end
        page.boards[boardKey] = page.boards[boardKey] or BuildBoard(page, page.window, key, numpad)
        page.board = page.boards[boardKey]
        page.board:Show()
        page.layoutKey, page.boardKey = key, boardKey
        ns.SetWindowWidth(numpad and NUMPAD_WIDTH or nil)
        page.others:ClearAllPoints()
        page.others:SetPoint("TOPLEFT", page.board, "BOTTOMLEFT", 0, -12)
        page.others:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -16, 36) -- above the layout buttons
        for _, fs in ipairs(page.window.texts) do ns.SkinText(fs) end
    end
    page.numpad:SetShown(not pad)
    if numpad then page.numpad:LockHighlight() else page.numpad:UnlockHighlight() end
    -- On a controller, the layer buttons say which controller button is Shift, Ctrl or Alt.
    local padMods = pad and ns.PadModifiers() or nil
    for k in pairs(padButton) do padButton[k] = nil end
    if padMods then for button, mod in pairs(padMods) do padButton[mod] = button end end
    page.numpad:SetText((numpad and "|cffffd100" or "") .. L["Numpad"] .. (numpad and "|r" or ""))
    local layer, live = CurrentLayer()
    for _, t in ipairs(page.toggles) do
        local on = toggles[t.mod]
        if on then t:LockHighlight() else t:UnlockHighlight() end
        local button = padButton[t.mod:upper()]
        local title = button and (t.title .. " " .. ns.KeyLabel(button)) or t.title
        t:SetText((on and "|cffffd100" or "") .. title .. (on and "|r" or ""))
    end
    page.layerText:SetText(LAYER_NAMES[layer] .. (live and L[" (held)"] or ""))
    page.layoutRow:Refresh()
    local held = ns.HeldBinding()
    page.binding:SetShown(held ~= nil)
    if held then page.binding:SetText(L["Click a key for %s (right-click drops it)"]:format(held.label)) end
    RefreshCaps(page, layer, padMods)
    RefreshOthers(page, layer, pad)
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
    local row = ns.ChoiceRow(f, page, { { "auto", L["Automatic"] }, { "ansi", L["US"] }, { "iso", L["UK"] },
        { "pad", L["Controller"] } },
        function() return ns.db.settings.layout or "auto" end,
        function(value)
            ns.db.settings.layout = value
            ns.RefreshWindow()
        end, 76)
    row:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -16, 8)
    page.layoutRow = row
    -- Also draw the navigation block (Insert, Home, arrows...) and the numpad.
    local numpad = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    numpad:SetSize(76, 22)
    numpad:SetPoint("RIGHT", row, "LEFT", -10, 0)
    numpad:SetScript("OnClick", function()
        ns.db.settings.numpad = not ns.db.settings.numpad or nil
        ns.RefreshWindow()
    end)
    page.numpad = numpad
    f.buttons[#f.buttons + 1] = numpad
    local binding = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    binding:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -36)
    binding:SetTextColor(0.4, 0.8, 1)
    binding:Hide()
    page.binding = binding
    f.texts[#f.texts + 1] = binding
    local others = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- Anchored under whichever keyboard is drawn (Refresh).
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
