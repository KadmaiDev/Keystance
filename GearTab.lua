-- Keystance gear editor: what a profile puts on, shown in the Profiles tab in place of the
-- list (its row's Gear button). With ItemRack as the gear source, the profile picks one of
-- the character's ItemRack sets; with Keystance's own, it shows the gear slots like a
-- character sheet: click a slot to fly out what you have that fits it (worn, in the bags,
-- and in the bank while it's open) and pick one, drop an item from the bags on it, or
-- right-click to leave that slot alone. An item held over a slot it can't go in turns the
-- slot's highlight red. Built the first time it's opened.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)
local L = ns.L

local ipairs, pairs, pcall, type, CreateFrame = ipairs, pairs, pcall, type, CreateFrame
local GetCursorInfo, ClearCursor = GetCursorInfo, ClearCursor

-- The slots in three columns, as on the character sheet: armour down the left, hands to
-- trinkets down the middle, weapons on the right.
local COLUMNS = { { 1, 2, 3, 15, 5, 4, 19, 9 }, { 10, 6, 7, 8, 11, 12, 13, 14 }, { 16, 17, 18 } }
local SLOT_FRAMES = {
    [1] = "HeadSlot", [2] = "NeckSlot", [3] = "ShoulderSlot", [4] = "ShirtSlot", [5] = "ChestSlot", [6] = "WaistSlot",
    [7] = "LegsSlot", [8] = "FeetSlot", [9] = "WristSlot", [10] = "HandsSlot", [11] = "Finger0Slot",
    [12] = "Finger1Slot", [13] = "Trinket0Slot", [14] = "Trinket1Slot", [15] = "BackSlot", [16] = "MainHandSlot",
    [17] = "SecondaryHandSlot", [18] = "RangedSlot", [19] = "TabardSlot",
}
local ICON, ROW, COLUMN_W, TOP = 28, 31, 222, -104
local SETS_PER_COLUMN, SET_W = 8, 216
local FLY_COLUMNS, FLY_ROWS, FLY_SIZE, FLY_GAP = 6, 5, 32, 4
local HIGHLIGHT = "Interface\\Buttons\\ButtonHilight-Square"

-- The empty-slot picture the character sheet uses.
local function EmptyIcon(slot)
    local ok, _, texture = pcall(GetInventorySlotInfo, SLOT_FRAMES[slot])
    return ok and texture or 136511
end

local function Profile(view) return ns.char and ns.char.profiles[view.profile] end

-- The item on the cursor, as an item string (nil if it isn't an item).
local function CursorItem()
    local kind, _, link = GetCursorInfo()
    if kind == "item" then return ns.ItemString(link) end
end

-- Sets a slot of the profile's gear. A two-hander leaves no off hand: putting one in the main
-- hand takes the saved off hand out (and says so), and an off hand is refused while the
-- saved main hand is a two-hander (swapping would never settle).
local function SetSlot(view, slot, item)
    local p = Profile(view)
    local gear = p and p.gear
    if item and slot == 17 and gear and ns.IsTwoHandItem(gear[16]) then
        return ns.Print(L["No off hand with %s: it's a two-hander."]:format(ns.GearItemName(gear[16])))
    end
    if item and slot == 16 and ns.IsTwoHandItem(item) and gear and gear[17] then
        ns.SetGearSlot(view.profile, 17, nil)
        ns.Notify(L["%s is a two-hander, so the off hand is left out."]:format(ns.GearItemName(item)))
    end
    ns.SetGearSlot(view.profile, slot, item)
end

local function SlotTooltip(b)
    local p = Profile(b.view)
    local item = p and p.gear and p.gear[b.slot]
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    -- Holding an item: red if it can't go here (the usual highlight looks like it can).
    local held = CursorItem()
    local fits, why = true, nil
    if held then fits, why = ns.ItemFitsSlot(held, b.slot) end
    if fits then b.hl:SetVertexColor(1, 1, 1) else b.hl:SetVertexColor(1, 0.1, 0.1) end
    if not fits then
        GameTooltip:AddLine(ns.GEAR_SLOT_NAMES[b.slot])
        GameTooltip:AddLine(why, 1, 0.3, 0.3, true)
        return GameTooltip:Show()
    end
    if item then
        GameTooltip:SetHyperlink(item)
    else
        GameTooltip:AddLine(ns.GEAR_SLOT_NAMES[b.slot])
        GameTooltip:AddLine(L["Not part of this profile's gear: whatever you wear there stays on."], 1, 1, 1, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Click: choose from what you have that fits."], 0.6, 0.8, 1, true)
    GameTooltip:AddLine(L["Drop an item from your bags here to use that."], 0.6, 0.8, 1, true)
    if item then GameTooltip:AddLine(L["Right-click: leave this slot alone."], 0.6, 0.8, 1, true) end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- The flyout: what you have that fits a slot, as a grid of icons under it. The one worn
-- there comes first; bank items (only while the bank is open) have a blue border.
---------------------------------------------------------------------------
local function FlyoutTooltip(cell)
    if not cell.item then return end
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(cell.item)
    GameTooltip:AddLine(" ")
    if cell.worn then
        GameTooltip:AddLine(L["You're wearing this."], 0.6, 0.8, 1, true)
    elseif cell.bank then
        GameTooltip:AddLine(L["In your bank: put on while the bank is open, or move it to your bags first."], 0.3, 0.6, 1, true)
    end
    GameTooltip:Show()
end

local function FlyoutCell(fly, i)
    local b = CreateFrame("Button", nil, fly)
    b:SetSize(FLY_SIZE, FLY_SIZE)
    local c, r = (i - 1) % FLY_COLUMNS, math.floor((i - 1) / FLY_COLUMNS)
    b:SetPoint("TOPLEFT", fly, "TOPLEFT", 8 + c * (FLY_SIZE + FLY_GAP), -26 - r * (FLY_SIZE + FLY_GAP))
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetPoint("TOPLEFT", -2, 2)
    b.border:SetPoint("BOTTOMRIGHT", 2, -2)
    b.border:SetColorTexture(0.25, 0.55, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.chosen = b:CreateTexture(nil, "OVERLAY")
    b.chosen:SetPoint("TOPLEFT", -3, 3)
    b.chosen:SetPoint("BOTTOMRIGHT", 3, -3)
    b.chosen:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    b.chosen:SetBlendMode("ADD")
    b:SetHighlightTexture(HIGHLIGHT, "ADD")
    b:SetScript("OnClick", function(self)
        if not self.item then return end
        fly:Hide()
        SetSlot(fly.view, fly.slot, self.item)
    end)
    b:SetScript("OnEnter", FlyoutTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function RefreshFlyout(fly)
    local p = Profile(fly.view)
    if not p then return fly:Hide() end
    local saved = p.gear and p.gear[fly.slot]
    local list = ns.GearChoices(fly.slot)
    local max = FLY_COLUMNS * FLY_ROWS
    local first = fly.offset * FLY_COLUMNS
    for i = 1, math.min(#list - first, max) do
        fly.cells[i] = fly.cells[i] or FlyoutCell(fly, i)
    end
    for i, cell in ipairs(fly.cells) do
        local entry = list[first + i]
        if entry and i <= max then
            cell.item, cell.worn, cell.bank = entry.item, entry.worn, entry.bank
            cell.icon:SetTexture(C_Item.GetItemIconByID(ns.ItemStringID(entry.item)))
            cell.border:SetShown(entry.bank == true)
            cell.chosen:SetShown(saved ~= nil and ns.ItemStringID(saved) == ns.ItemStringID(entry.item))
            cell:Show()
        else
            cell.item, cell.worn, cell.bank = nil, nil, nil
            cell:Hide()
        end
    end
    local shown = math.max(1, math.min(#list - first, max))
    local rows = math.ceil(shown / FLY_COLUMNS)
    local note = #list == 0 and L["Nothing you have fits here."] or ""
    if #list > max then note = L["Scroll for more (%d items)."]:format(#list) end
    if not ns.BankOpen() then
        note = (note ~= "" and (note .. " ") or "") .. L["Open your bank to see what's in it too."]
    end
    fly.note:SetText(note)
    fly.title:SetText(ns.GEAR_SLOT_NAMES[fly.slot])
    local width = FLY_COLUMNS * (FLY_SIZE + FLY_GAP) - FLY_GAP + 16
    fly:SetSize(width, 26 + rows * (FLY_SIZE + FLY_GAP) + (note ~= "" and 34 or 6))
end

local function MakeFlyout(view)
    local fly = CreateFrame("Frame", nil, view.items, "BackdropTemplate")
    fly.view, fly.cells, fly.offset, fly.texts = view, {}, 0, {}
    if fly.SetBackdrop then
        pcall(fly.SetBackdrop, fly, {
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        if fly.SetBackdropColor then fly:SetBackdropColor(0.05, 0.05, 0.05, 0.95) end
    end
    fly:SetFrameLevel(view.items:GetFrameLevel() + 20)
    fly:SetClampedToScreen(true)
    fly:EnableMouse(true) -- clicks between its icons don't reach the slots under it
    fly:EnableMouseWheel(true)
    fly:SetScript("OnMouseWheel", function(self, delta)
        local total = #ns.GearChoices(self.slot)
        local most = math.max(0, math.ceil(total / FLY_COLUMNS) - FLY_ROWS)
        local offset = math.max(0, math.min(most, self.offset - delta))
        if offset ~= self.offset then
            self.offset = offset
            RefreshFlyout(self)
        end
    end)
    fly.title = fly:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fly.title:SetPoint("TOPLEFT", 10, -8)
    fly.note = fly:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fly.note:SetPoint("BOTTOMLEFT", 10, 8)
    fly.note:SetPoint("BOTTOMRIGHT", -10, 8)
    fly.note:SetJustifyH("LEFT")
    fly.texts[1], fly.texts[2] = fly.title, fly.note
    ns.SkinWindow(fly)
    fly:Hide()
    -- It closes with the editor (Back, another tab, the window closing), and on a click
    -- anywhere but on it or a gear slot (a slot's own click moves or closes it). It listens
    -- for clicks only while it's open.
    view:HookScript("OnHide", function() fly:Hide() end)
    fly:SetScript("OnShow", function(self) pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
    fly:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
    fly:SetScript("OnEvent", function(self)
        local foci = GetMouseFoci and GetMouseFoci()
        local target = type(foci) == "table" and foci[1] or nil
        while target do
            if target == self or target.isGearSlot then return end
            target = target:GetParent()
        end
        self:Hide()
    end)
    return fly
end

-- Opens the flyout under a slot, or closes it if it's already open there.
local function ToggleFlyout(b)
    local view = b.view
    view.flyout = view.flyout or MakeFlyout(view)
    local fly = view.flyout
    if fly:IsShown() and fly.slot == b.slot then return fly:Hide() end
    fly.slot, fly.offset = b.slot, 0
    fly:ClearAllPoints()
    fly:SetPoint("TOPLEFT", b.icon, "BOTTOMLEFT", 0, -2)
    fly:Show()
    RefreshFlyout(fly)
end

local function MakeSlot(view, f, slot, x, y)
    local b = CreateFrame("Button", nil, view.items)
    b:SetSize(COLUMN_W - 8, ICON)
    b:SetPoint("TOPLEFT", view.items, "TOPLEFT", x, y)
    b.view, b.slot, b.isGearSlot = view, slot, true
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON, ICON)
    icon:SetPoint("LEFT")
    b.icon = icon
    local name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    name:SetPoint("RIGHT", b, "RIGHT", 0, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    b.name = name
    f.texts[#f.texts + 1] = name
    ns.SkinText(name)
    -- Its own highlight texture, so it can turn red under an item that can't go here.
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetTexture(HIGHLIGHT)
    b.hl:SetBlendMode("ADD")
    b.hl:SetVertexColor(1, 1, 1)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local function Drop(self)
        local item = CursorItem()
        if item then
            -- Only where it can be worn (boots in Feet, not Legs); a wrong one stays on the
            -- cursor, as on the character sheet, and says where it goes.
            local fits, why = ns.ItemFitsSlot(item, self.slot)
            if not fits then
                ns.Print(why)
                return true
            end
            ClearCursor() -- back to its bag
            SetSlot(self.view, self.slot, item)
            return true
        end
    end
    b:SetScript("OnReceiveDrag", Drop)
    b:SetScript("OnClick", function(self, button)
        if self.view.flyout and button == "RightButton" then self.view.flyout:Hide() end
        if button == "RightButton" then return SetSlot(self.view, self.slot, nil) end
        if Drop(self) then return end
        if GetCursorInfo() then return end -- a spell or macro held: not for a gear slot
        ToggleFlyout(self)
    end)
    b:SetScript("OnEnter", SlotTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function SetButton(view, i)
    local b = CreateFrame("Button", nil, view.sets, "UIPanelButtonTemplate")
    b:SetSize(SET_W, 24)
    local column, row = math.floor((i - 1) / SETS_PER_COLUMN), (i - 1) % SETS_PER_COLUMN
    b:SetPoint("TOPLEFT", view.sets, "TOPLEFT", 16 + column * (SET_W + 8), TOP - row * 30)
    local icon = b:CreateTexture(nil, "OVERLAY")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", 4, 0)
    b.icon = icon
    b:SetScript("OnClick", function(self) ns.SetProfileItemRack(view.profile, self.set) end)
    ns.SkinButton(b)
    return b
end

function ns.BuildGearView(view, f, back)
    view.window = f
    -- The profile's icon, to choose another.
    local icon = CreateFrame("Button", nil, view)
    icon:SetSize(28, 28)
    icon:SetPoint("TOPLEFT", 16, -8)
    icon.tex = icon:CreateTexture(nil, "ARTWORK")
    icon.tex:SetAllPoints()
    icon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    icon:SetScript("OnClick", function(self) ns.PickProfileIcon(view.profile, self) end)
    view.icon = icon
    local title = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    view.title = title
    local backButton = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    backButton:SetSize(90, 22)
    backButton:SetPoint("TOPRIGHT", view, "TOPRIGHT", -16, -10)
    backButton:SetText(L["Back"])
    backButton:SetScript("OnClick", back)
    view.back = backButton

    -- Where the gear comes from, when ItemRack is there to choose.
    local from = view:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    from:SetPoint("TOPLEFT", 16, -48)
    from:SetText(L["Gear from:"])
    view.from = from
    local source = ns.ChoiceRow(f, view, { { "itemrack", L["ItemRack"] }, { "keystance", L["Keystance"] } },
        function() return ns.GearSource() end,
        function(value)
            ns.db.settings.gearSource = value
            ns.ProfilesChanged() -- automatic icons can follow the source
        end, 90)
    source:SetPoint("LEFT", from, "RIGHT", 10, 0)
    view.source = source

    local help = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", 16, -74)
    help:SetWidth(660)
    help:SetJustifyH("LEFT")
    view.help = help

    -- Keystance's own: the slots, and buttons to fill or empty them all.
    view.items = CreateFrame("Frame", nil, view)
    view.items:SetAllPoints()
    view.slots = {}
    for c, column in ipairs(COLUMNS) do
        for r, slot in ipairs(column) do
            view.slots[slot] = MakeSlot(view, f, slot, 16 + (c - 1) * COLUMN_W, TOP - (r - 1) * ROW)
        end
    end
    view.wearing = CreateFrame("Button", nil, view.items, "UIPanelButtonTemplate")
    view.wearing:SetSize(170, 22)
    view.wearing:SetPoint("TOPRIGHT", view, "TOPRIGHT", -16, -44)
    view.wearing:SetText(L["Take what I'm wearing"])
    view.wearing:SetScript("OnClick", function()
        local items, why = ns.CaptureGear()
        if not items then return ns.Print(why) end
        ns.SetProfileGear(view.profile, items)
    end)
    view.none = CreateFrame("Button", nil, view.items, "UIPanelButtonTemplate")
    view.none:SetSize(90, 22)
    view.none:SetPoint("RIGHT", view.wearing, "LEFT", -6, 0)
    view.none:SetText(L["No gear"])
    view.none:SetScript("OnClick", function() ns.SetProfileGear(view.profile, nil) end)

    -- ItemRack: one button per set, and None.
    view.sets = CreateFrame("Frame", nil, view)
    view.sets:SetAllPoints()
    view.setButtons = {}

    for _, fs in ipairs({ title, from, help }) do
        f.texts[#f.texts + 1] = fs
        ns.SkinText(fs)
    end
    for _, b in ipairs({ backButton, view.wearing, view.none }) do ns.SkinButton(b) end
    for _, b in ipairs(source.buttons) do ns.SkinButton(b) end
end

local function RefreshItems(view, p)
    for slot, b in pairs(view.slots) do
        local item = p.gear and p.gear[slot]
        if item then
            b.icon:SetTexture(C_Item.GetItemIconByID(ns.ItemStringID(item)))
            b.icon:SetDesaturated(false)
            b.icon:SetAlpha(1)
            -- Saved in a slot it can't go in (before this was checked): shown in red.
            local fits = ns.ItemFitsSlot(item, slot)
            b.wrong = not fits or nil
            b.name:SetText(fits and ns.GearItemName(item) or L["%s (wrong slot)"]:format(ns.GearItemName(item)))
            if fits then b.name:SetTextColor(1, 1, 1) else b.name:SetTextColor(1, 0.3, 0.3) end
        else
            b.icon:SetTexture(EmptyIcon(slot))
            b.icon:SetDesaturated(true)
            b.icon:SetAlpha(0.5)
            b.name:SetText(ns.GEAR_SLOT_NAMES[slot])
            b.name:SetTextColor(0.5, 0.5, 0.5)
        end
    end
end

local function RefreshSets(view, p)
    local names = ns.ItemRackSets()
    local choices = { false }
    for _, name in ipairs(names) do choices[#choices + 1] = name end
    local max = SETS_PER_COLUMN * 3
    for i, set in ipairs(choices) do
        if i > max then break end
        local b = view.setButtons[i] or SetButton(view, i)
        view.setButtons[i] = b
        b.set = set or nil
        local on = (p.itemrack or false) == set
        b:SetText(set and ("      " .. set) or L["No gear"])
        b.icon:SetTexture(set and ns.ItemRackSetIcon(set) or nil)
        b.chosen = on
        if on then b:LockHighlight() else b:UnlockHighlight() end
        local text = b:GetFontString()
        if text then text:SetTextColor(on and 1 or 0.75, on and 0.82 or 0.75, on and 0 or 0.75) end
        b:Show()
    end
    for i = #choices + 1, #view.setButtons do view.setButtons[i]:Hide() end
    if #choices > max then
        view.help:SetText(view.help:GetText() .. "\n" .. L["Only the first %d sets fit here."]:format(max - 1))
    end
end

function ns.RefreshGearView(view, name)
    view.profile = name
    local p = Profile(view)
    if not p then return end
    view.title:SetText(L["Gear for %s"]:format(name))
    local icon, crop = ns.ProfileIcon(p)
    view.icon.tex:SetTexture(icon)
    if crop then view.icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) else view.icon.tex:SetTexCoord(0, 1, 0, 1) end
    local itemRack = ns.ItemRackReady()
    view.from:SetShown(itemRack)
    view.source:SetShown(itemRack)
    view.source:Refresh()
    local source = ns.GearSource()
    view.items:SetShown(source == "keystance")
    view.sets:SetShown(source == "itemrack")
    if source == "itemrack" then
        view.help:SetText(L["Applying %s asks ItemRack to put this set on. Make and change sets in ItemRack."]:format(name))
        RefreshSets(view, p)
    else
        view.help:SetText(L["Applying %s puts these on first. Click a slot to choose from what you have (your bank too while it's open), drop an item from your bags on it, or right-click to leave that slot alone."]:format(name))
        RefreshItems(view, p)
        if view.flyout and view.flyout:IsShown() then RefreshFlyout(view.flyout) end
    end
end

-- Keep the editor current while gear and bags change (a closed window costs one check);
-- the bank opening and closing asks too (Gear.lua).
ns.On("PLAYER_EQUIPMENT_CHANGED", function() ns.RequestRefresh("profiles") end)
ns.On("BAG_UPDATE_DELAYED", function() ns.RequestRefresh("profiles") end)
