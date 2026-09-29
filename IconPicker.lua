-- Keystance icon picker: chooses the picture a profile shows (its row, the spell panel's
-- Profiles tab). First "Automatic" (ns.AutoProfileIcon: its ItemRack set, main-hand weapon
-- or first spell), then the profile's own icons (its gear and the actions on its bars),
-- then every icon the game offers for macros. A grid with a scrollbar; built the first
-- time it's opened, and the game's icon list is read then too.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)
local L = ns.L

local ipairs, pairs, pcall, CreateFrame = ipairs, pairs, pcall, CreateFrame

local COLUMNS, ROWS, SIZE, GAP = 8, 7, 32, 4
local AUTO = "auto"

local picker
local list = {}   -- what the grid shows: AUTO, then icons (file IDs or paths)
local offset = 0  -- the first row shown
local allIcons    -- every macro icon, read on first open

-- The game's macro icons (spells, then items), as its macro window lists them.
local function AllIcons()
    if not allIcons then
        allIcons = {}
        for _, fn in ipairs({ GetMacroIcons, GetMacroItemIcons }) do
            if type(fn) == "function" then pcall(fn, allIcons) end
        end
    end
    return allIcons
end

local function Rebuild(p)
    for i = #list, 1, -1 do list[i] = nil end
    list[1] = AUTO
    local seen = {}
    for _, icon in ipairs(ns.ProfileIcons(p)) do
        if not seen[icon] then
            seen[icon] = true
            list[#list + 1] = icon
        end
    end
    for _, icon in ipairs(AllIcons()) do
        if not seen[icon] then list[#list + 1] = icon end
    end
end

local function MaxOffset()
    return math.max(0, math.ceil(#list / COLUMNS) - ROWS)
end

local function Refresh()
    local p = ns.char and ns.char.profiles[picker.profile]
    if not p then return picker:Hide() end
    picker.title:SetText(L["Icon for %s"]:format(picker.profile))
    local max = MaxOffset()
    if offset > max then offset = max end
    picker.scroll:SetMinMaxValues(0, max)
    picker.scroll:SetValue(offset)
    picker.scroll:SetShown(max > 0)
    for i, b in ipairs(picker.cells) do
        local entry = list[offset * COLUMNS + i]
        b.entry = entry
        if entry then
            b.icon:SetTexture(entry == AUTO and ns.AutoProfileIcon(p) or entry)
            b.auto:SetShown(entry == AUTO)
            local chosen = (entry == AUTO and not p.icon) or entry == p.icon
            b.chosen = chosen
            b.border:SetShown(chosen)
            b:Show()
        else
            b:Hide()
        end
    end
end

local function Cell(f, i)
    local b = CreateFrame("Button", nil, f.grid)
    b:SetSize(SIZE, SIZE)
    local c, r = (i - 1) % COLUMNS, math.floor((i - 1) / COLUMNS)
    b:SetPoint("TOPLEFT", f.grid, "TOPLEFT", c * (SIZE + GAP), -r * (SIZE + GAP))
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetPoint("TOPLEFT", -3, 3)
    b.border:SetPoint("BOTTOMRIGHT", 3, -3)
    b.border:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    b.border:SetBlendMode("ADD")
    b.auto = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.auto:SetPoint("BOTTOM", 0, 1)
    b.auto:SetText(L["Auto"])
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnClick", function(self)
        if not self.entry then return end
        ns.SetProfileIcon(picker.profile, self.entry ~= AUTO and self.entry or nil)
        picker:Hide()
    end)
    b:SetScript("OnEnter", function(self)
        if self.entry ~= AUTO then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Automatic"])
        GameTooltip:AddLine(L["Its ItemRack set's icon, else its main-hand weapon, else the first spell on its bars."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function Create()
    local ok, f = pcall(CreateFrame, "Frame", "KeystanceIconPicker", UIParent, "BasicFrameTemplateWithInset")
    if not ok then
        f = CreateFrame("Frame", "KeystanceIconPicker", UIParent, "BackdropTemplate")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
        f.CloseButton = close -- restyled with the window by EllesmereUI and ElvUI
    end
    picker = f
    f.buttons, f.texts, f.cells = {}, {}, {}
    local gridW, gridH = COLUMNS * (SIZE + GAP) - GAP, ROWS * (SIZE + GAP) - GAP
    f:SetSize(gridW + 44, gridH + 76)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    local title = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if not f.TitleText then title:SetPoint("TOP", 0, -6) end
    f.title = title
    local note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 16, -32)
    note:SetText(L["Automatic, then this profile's own, then every icon."])
    f.texts[#f.texts + 1] = note
    f.grid = CreateFrame("Frame", nil, f)
    f.grid:SetSize(gridW, gridH)
    f.grid:SetPoint("TOPLEFT", 16, -54)
    f.grid:EnableMouseWheel(true)
    f.grid:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, math.min(MaxOffset(), offset - delta * 2))
        Refresh()
    end)
    for i = 1, COLUMNS * ROWS do f.cells[i] = Cell(f, i) end
    local scroll = CreateFrame("Slider", nil, f)
    scroll:SetOrientation("VERTICAL")
    scroll:EnableMouse(true) -- so its thumb can be dragged
    scroll:SetSize(6, gridH)
    scroll:SetPoint("TOPLEFT", f.grid, "TOPRIGHT", 6, 0)
    local thumb = scroll:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(0.7, 0.7, 0.7, 0.6)
    thumb:SetSize(6, 40)
    scroll:SetThumbTexture(thumb)
    scroll:SetValueStep(1)
    scroll:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        if value ~= offset then
            offset = value
            Refresh()
        end
    end)
    f.scroll = scroll
    ns.SkinWindow(f)
    -- Escape closes it, like Blizzard's own windows, and it closes with the window.
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "KeystanceIconPicker" end
    if KeystanceFrame then KeystanceFrame:HookScript("OnHide", function() f:Hide() end) end
    f:Hide()
end

-- Opens the picker for a profile, beside `anchor` (the icon clicked).
function ns.PickProfileIcon(name, anchor)
    local key = ns.FindProfile(name)
    if not key then return end
    if not picker then Create() end
    picker.profile, offset = key, 0
    Rebuild(ns.char.profiles[key])
    picker:ClearAllPoints()
    if anchor then
        picker:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
    else
        picker:SetPoint("CENTER")
    end
    picker:Show()
    Refresh()
end
