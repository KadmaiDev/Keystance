-- Keystance Bars tab: the action bars on screen (Blizzard's, EllesmereUI's or ElvUI's),
-- each slot with its icon and key. Hovering shows the action's tooltip; slots take drops,
-- can be dragged, and right-click removes. Keybind mode, as the game's own quick keybind
-- mode: hover a slot and press a key (or a mouse or controller button) to put it there;
-- right-click clears the slot's keys; Escape finishes. While it's on, key presses go to
-- Keystance, not the game; it ends in combat and when the tab or window closes.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)
local L = ns.L

local ipairs, CreateFrame = ipairs, CreateFrame
local GetActionTexture, HasAction = GetActionTexture, HasAction

local SIZE, GAP, ROW = 30, 2, 33
local LABEL_WIDTH = 90
local MAX_ROWS = 10

local SOURCE_NAMES = {
    blizzard = L["Blizzard's action bars"], ellesmere = L["EllesmereUI's action bars"], elvui = L["ElvUI's action bars"],
}

-- Keybind mode.
local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true, UNKNOWN = true }
local MOUSE_BUTTONS = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

local function SlotLabel(b)
    local a = b.slot and ns.DescribeSlot(b.slot)
    return a and a.name or L["slot %d"]:format(b.slot or 0)
end

-- The pressed key with the modifiers held, in the game's order ("ALT-CTRL-SHIFT-Q").
local function FullKey(key)
    return (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
        .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
end

local function BindHovered(page, key)
    local b = page.hovered
    if not (b and b.command) then return end
    ns.QuickBind(FullKey(key), b.command, SlotLabel(b))
end

local function SlotTooltip(b)
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    if b.slot and HasAction(b.slot) then
        GameTooltip:SetAction(b.slot)
    else
        GameTooltip:AddLine(L["Empty slot"])
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(L["Key"], b.key or L["none"], 0.6, 0.6, 0.6, 1, 1, 1)
    if b.slot then GameTooltip:AddDoubleLine(L["Action slot"], b.slot, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

local function MakeRow(page, f, r)
    local row = CreateFrame("Frame", nil, page)
    row:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -40 - (r - 1) * ROW)
    row:SetSize(LABEL_WIDTH + 12 * (SIZE + GAP), SIZE)
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", row, "LEFT", 0, 0)
    label:SetWidth(LABEL_WIDTH - 6)
    label:SetJustifyH("LEFT")
    row.label = label
    f.texts[#f.texts + 1] = label
    row.slots = {}
    for i = 1, 12 do
        local b = CreateFrame("Button", nil, row)
        b:SetSize(SIZE, SIZE)
        b:SetPoint("LEFT", row, "LEFT", LABEL_WIDTH + (i - 1) * (SIZE + GAP), 0)
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.1, 0.1, 0.12, 0.9)
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.icon = icon
        local key = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
        key:SetPoint("TOPRIGHT", -1, -2)
        b.keyText = key
        f.texts[#f.texts + 1] = key
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnEnter", function(self)
            if page.bindMode then
                page.hovered = self
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(SlotLabel(self))
                GameTooltip:AddLine(L["Press a key to put it on this slot. Right-click clears its keys."], 1, 1, 1, true)
                return GameTooltip:Show()
            end
            SlotTooltip(self)
        end)
        -- The mouse wheel as a key, in keybind mode.
        b:SetScript("OnMouseWheel", function(self, delta)
            if page.bindMode then BindHovered(page, delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN") end
        end)
        -- Something dragged here goes in this slot, as on the real bars.
        local function Drop(self)
            if self.slot and GetCursorInfo() then ns.DropOnSlot(self.slot) end
        end
        b:SetScript("OnReceiveDrag", Drop)
        b:RegisterForClicks("AnyUp")
        b:SetScript("OnClick", function(self, button)
            if page.bindMode then
                if button == "RightButton" then
                    if self.command then ns.ClearKeys(self.command, SlotLabel(self)) end
                elseif MOUSE_BUTTONS[button] then
                    page.hovered = self
                    BindHovered(page, MOUSE_BUTTONS[button])
                end
                return
            end
            if button == "RightButton" then
                if self.slot and not GetCursorInfo() then ns.AskRemove(nil, self.slot) end
                return
            end
            Drop(self)
        end)
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnDragStart", function(self)
            if self.slot then ns.PickupFromSlot(self.slot, nil, self.command) end
        end)
        b:SetScript("OnLeave", function(self)
            if page.hovered == self then page.hovered = nil end
            GameTooltip:Hide()
        end)
        row.slots[i] = b
    end
    return row
end

local function StopBindMode(page)
    if not page.bindMode then return end
    page.bindMode, page.hovered = false, nil
    page.catcher:EnableKeyboard(false)
    if page.catcher.EnableGamePadButton then pcall(page.catcher.EnableGamePadButton, page.catcher, false) end
    for _, row in ipairs(page.rows) do
        for _, b in ipairs(row.slots) do b:EnableMouseWheel(false) end
    end
    ns.RefreshWindow()
end

local function StartBindMode(page)
    if ns.InCombat() then return ns.Print(L["Not in combat: try again when combat ends."]) end
    page.bindMode = true
    page.catcher:EnableKeyboard(true)
    if page.catcher.EnableGamePadButton then pcall(page.catcher.EnableGamePadButton, page.catcher, true) end
    for _, row in ipairs(page.rows) do
        for _, b in ipairs(row.slots) do b:EnableMouseWheel(true) end
    end
    ns.RefreshWindow()
end

-- Keybind mode changes keys; with the account's shared keybinds, the character gets its own
-- first (owner's decision: ask).
local function AskStart(page)
    if not ns.SharedKeybinds() then return StartBindMode(page) end
    if not StaticPopupDialogs.KEYSTANCE_BIND_MODE then
        StaticPopupDialogs.KEYSTANCE_BIND_MODE = {
            text = L["Your keybinds are shared by all your characters, so keybind mode would change them for everyone.\n\nGive this character its own keybinds first? Nothing changes on screen, and your other characters keep theirs."],
            button1 = L["Own keybinds, then start"],
            button2 = CANCEL or "Cancel",
            OnAccept = function(_, data)
                if ns.InCombat() then return end
                SaveBindings(2)
                StartBindMode(data)
            end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
    end
    StaticPopup_Show("KEYSTANCE_BIND_MODE", nil, nil, page)
end

local function Refresh(page)
    local bars, n = ns.ShownBars()
    page.bindButton:SetText(page.bindMode and L["Done"] or L["Keybind mode"])
    page.bindNote:SetShown(page.bindMode)
    page.source:SetText(SOURCE_NAMES[ns.BarSource()])
    for r = 1, MAX_ROWS do
        local row = page.rows[r]
        local bar = bars[r]
        if bar then
            if not row then
                row = MakeRow(page, page.window, r)
                page.rows[r] = row
                ns.SkinText(row.label)
                for _, b in ipairs(row.slots) do ns.SkinText(b.keyText) end
            end
            row.label:SetText(bar.name)
            for i, b in ipairs(row.slots) do
                local btn = bar.buttons[i]
                local slot = ns.BarButtonSlot(btn)
                local key = ns.BarButtonKey(btn)
                b.slot, b.key, b.command = slot, key, btn.command
                local texture = slot and GetActionTexture(slot)
                b.icon:SetTexture(texture)
                b.icon:SetShown(texture ~= nil)
                b.keyText:SetText(ns.ShortKey(key) or "")
            end
            row:Show()
            for _, b in ipairs(row.slots) do b:EnableMouseWheel(page.bindMode and true or false) end
        elseif row then
            row:Hide()
        end
    end
    page.empty:SetShown(n == 0)
    page.more:SetShown(n > MAX_ROWS)
    if n > MAX_ROWS then page.more:SetText(L["and %d more bars"]:format(n - MAX_ROWS)) end
end

local function Build(page, f)
    page.window, page.rows = f, {}
    local source = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    source:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -16)
    page.source = source
    f.texts[#f.texts + 1] = source
    local empty = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    empty:SetPoint("CENTER")
    empty:SetText(L["No action bars are showing."])
    empty:Hide()
    page.empty = empty
    f.texts[#f.texts + 1] = empty
    local more = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    more:SetPoint("TOPLEFT", page, "TOPLEFT", 16 + LABEL_WIDTH, -40 - MAX_ROWS * ROW)
    more:Hide()
    page.more = more
    f.texts[#f.texts + 1] = more
    -- Keybind mode.
    local bind = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    bind:SetSize(130, 22)
    bind:SetPoint("TOPRIGHT", page, "TOPRIGHT", -16, -10)
    bind:SetScript("OnClick", function()
        if page.bindMode then StopBindMode(page) else AskStart(page) end
    end)
    page.bindButton = bind
    f.buttons[#f.buttons + 1] = bind
    local note = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    note:SetPoint("RIGHT", bind, "LEFT", -12, 0)
    note:SetTextColor(0.4, 0.8, 1)
    note:SetText(L["Hover a slot and press a key. Right-click clears. Esc finishes."])
    note:Hide()
    page.bindNote = note
    f.texts[#f.texts + 1] = note
    -- Takes key presses (and controller buttons) while keybind mode is on.
    local catcher = CreateFrame("Frame", nil, page)
    catcher:SetAllPoints()
    catcher:EnableKeyboard(false)
    catcher:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then return StopBindMode(page) end
        if MODIFIER_KEYS[key] then return end
        BindHovered(page, key)
    end)
    catcher:SetScript("OnGamePadButtonDown", function(_, button) BindHovered(page, button) end)
    page.catcher = catcher
    page:HookScript("OnHide", function() StopBindMode(page) end)
    ns.On("PLAYER_REGEN_DISABLED", function() StopBindMode(page) end)
    page.Refresh = Refresh
end

ns.pageBuilders.bars = Build
