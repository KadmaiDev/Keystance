-- Keystance Bars tab: the action bars on screen (Blizzard's, EllesmereUI's or ElvUI's),
-- each slot with its icon and key. Hovering shows the action's tooltip. Read-only.
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
        b:SetScript("OnEnter", SlotTooltip)
        -- Something dragged here goes in this slot, as on the real bars.
        local function Drop(self)
            if self.slot and GetCursorInfo() then ns.DropOnSlot(self.slot) end
        end
        b:SetScript("OnReceiveDrag", Drop)
        b:SetScript("OnClick", Drop)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.slots[i] = b
    end
    return row
end

local function Refresh(page)
    local bars, n = ns.ShownBars()
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
                b.slot, b.key = slot, key
                local texture = slot and GetActionTexture(slot)
                b.icon:SetTexture(texture)
                b.icon:SetShown(texture ~= nil)
                b.keyText:SetText(ns.ShortKey(key) or "")
            end
            row:Show()
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
    page.Refresh = Refresh
end

ns.pageBuilders.bars = Build
