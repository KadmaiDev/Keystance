-- Keystance gear editor: what a profile puts on, shown in the Profiles tab in place of the
-- list (its row's Gear button). With ItemRack as the gear source, the profile picks one of
-- the character's ItemRack sets; with Keystance's own, it shows the gear slots like a
-- character sheet: click a slot to take what's worn there now, drop an item from the bags
-- on it, right-click to leave that slot alone. Built the first time it's opened.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)
local L = ns.L

local ipairs, pairs, CreateFrame = ipairs, pairs, CreateFrame
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

local function SetSlot(view, slot, item)
    ns.SetGearSlot(view.profile, slot, item)
end

local function SlotTooltip(b)
    local p = Profile(b.view)
    local item = p and p.gear and p.gear[b.slot]
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    if item then
        GameTooltip:SetHyperlink(item)
    else
        GameTooltip:AddLine(ns.GEAR_SLOT_NAMES[b.slot])
        GameTooltip:AddLine(L["Not part of this profile's gear: whatever you wear there stays on."], 1, 1, 1, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Click: take what you're wearing there now."], 0.6, 0.8, 1, true)
    GameTooltip:AddLine(L["Drop an item from your bags here to use that."], 0.6, 0.8, 1, true)
    if item then GameTooltip:AddLine(L["Right-click: leave this slot alone."], 0.6, 0.8, 1, true) end
    GameTooltip:Show()
end

local function MakeSlot(view, f, slot, x, y)
    local b = CreateFrame("Button", nil, view.items)
    b:SetSize(COLUMN_W - 8, ICON)
    b:SetPoint("TOPLEFT", view.items, "TOPLEFT", x, y)
    b.view, b.slot = view, slot
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
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local function Drop(self)
        local item = CursorItem()
        if item then
            ClearCursor() -- back to its bag
            SetSlot(self.view, self.slot, item)
            return true
        end
    end
    b:SetScript("OnReceiveDrag", Drop)
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then return SetSlot(self.view, self.slot, nil) end
        if Drop(self) then return end
        SetSlot(self.view, self.slot, ns.WornItem(self.slot))
    end)
    b:SetScript("OnEnter", SlotTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function SetButton(view, f, i)
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
    local title = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
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
            ns.RefreshWindow()
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
            b.name:SetText(ns.GearItemName(item))
            b.name:SetTextColor(1, 1, 1)
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
        local b = view.setButtons[i] or SetButton(view, view.window, i)
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
        view.help:SetText(L["Applying %s puts these on first. Click a slot to take what you're wearing there, drop an item from your bags on it, or right-click to leave that slot alone."]:format(name))
        RefreshItems(view, p)
    end
end

-- Keep the editor current while gear changes (a closed window costs one check).
ns.On("PLAYER_EQUIPMENT_CHANGED", function() ns.RequestRefresh("profiles") end)
