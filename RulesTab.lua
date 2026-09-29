-- Keystance Rules tab: automatic switching on or off, "ask before switching", the rules as
-- sentences ("When a shield is equipped, use Prot.") with Up, Down and Delete, and a line
-- to add one: what to watch for (a shield, a two-hander, an item, an equipment set) and
-- which profile to use. An item is chosen by dropping it on the item button (from the bags
-- or the character sheet); sets and profiles are chosen by clicking through them.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)
local L = ns.L

local ipairs, CreateFrame = ipairs, CreateFrame

local ROWS, ROW_HEIGHT = 6, 30

local function Button(f, parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    f.buttons[#f.buttons + 1] = b
    return b
end

local function Text(f, parent, template, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    if text then fs:SetText(text) end
    f.texts[#f.texts + 1] = fs
    return fs
end

-- The sets a rule can watch: the game's equipment sets by name, then ItemRack's as
-- "itemrack:Name".
local ITEMRACK = "itemrack:"
local function SetChoices()
    local list = ns.EquipmentSetNames()
    for _, name in ipairs(ns.ItemRackSets()) do list[#list + 1] = ITEMRACK .. name end
    return list
end
local function SetLabel(choice)
    if choice:sub(1, #ITEMRACK) == ITEMRACK then return L["%s (ItemRack)"]:format(choice:sub(#ITEMRACK + 1)) end
    return choice
end

-- The next item of a list after `current` (wrapping), for the click-through buttons.
local function Has(list, value)
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end

local function NextOf(list, current)
    for i, v in ipairs(list) do
        if v == current then return list[i % #list + 1] end
    end
    return list[1]
end

local function MakeRow(page, f, i)
    local row = CreateFrame("Frame", nil, page)
    row:SetSize(680, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -150 - (i - 1) * ROW_HEIGHT)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0.06)
    local text = Text(f, row, "GameFontHighlight")
    text:SetPoint("LEFT", 8, 0)
    text:SetPoint("RIGHT", row, "RIGHT", -200, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    row.text = text
    -- The whole sentence (and why it's ignored), in case it doesn't fit.
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        local rule = ns.char and ns.char.rules[self.index]
        if not rule then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ns.RuleText(rule), 1, 1, 1, true)
        if self.problem then
            GameTooltip:AddLine(L["Ignored: %s. It works again when it can."]:format(self.problem), 1, 0.3, 0.3, true)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.delete = Button(f, row, L["Delete"], 60, function() ns.DeleteRule(row.index) end)
    row.delete:SetPoint("RIGHT", -4, 0)
    row.down = Button(f, row, L["Down"], 56, function() ns.MoveRule(row.index, 1) end)
    row.down:SetPoint("RIGHT", row.delete, "LEFT", -4, 0)
    row.up = Button(f, row, L["Up"], 56, function() ns.MoveRule(row.index, -1) end)
    row.up:SetPoint("RIGHT", row.down, "LEFT", -4, 0)
    for _, b in ipairs({ row.delete, row.down, row.up }) do ns.SkinButton(b) end
    ns.SkinText(text)
    return row
end

local function Refresh(page)
    local c = ns.char
    if not c then return end
    page.auto:Refresh()
    page.ask:Refresh()
    -- The new rule's controls.
    -- "a set" only when there are sets to watch (the game's, or ItemRack's while it's loaded).
    local sets = SetChoices()
    local setButton = page.when.buttons[4]
    setButton:SetShown(#sets > 0)
    page.when:SetWidth(#sets > 0 and page.whenWidth or (page.whenWidth - setButton:GetWidth() - 4))
    if #sets == 0 and page.new.when == "set" then page.new.when = "shield" end
    page.when:Refresh()
    local when = page.new.when
    page.item:SetShown(when == "item")
    page.set:SetShown(when == "set")
    if page.new.item then
        page.item.icon:SetTexture(C_Item.GetItemIconByID(page.new.item))
        page.item:SetText("      " .. ((C_Item.GetItemNameByID and C_Item.GetItemNameByID(page.new.item)) or L["item %d"]:format(page.new.item)))
    else
        page.item.icon:SetTexture(nil)
        page.item:SetText(L["Drop an item here"])
    end
    if page.new.set and not Has(sets, page.new.set) then page.new.set = nil end
    page.new.set = page.new.set or sets[1]
    page.set:SetText(page.new.set and L["Set: %s"]:format(SetLabel(page.new.set)) or L["No equipment sets"])
    local profiles = ns.ProfileNames()
    if page.new.profile and not ns.FindProfile(page.new.profile) then page.new.profile = nil end
    page.new.profile = page.new.profile or profiles[1]
    page.profile:SetText(page.new.profile and L["Use: %s"]:format(page.new.profile) or L["No profiles yet"])
    page.add:SetEnabled(page.new.profile ~= nil)
    -- The rules: six at a time, scrolling with the mouse wheel past that.
    local max = math.max(0, #c.rules - ROWS)
    if page.offset > max then page.offset = max end
    for r = 1, ROWS do
        local i = page.offset + r
        local rule = c.rules[i]
        local row = page.rows[r]
        if rule then
            if not row then
                row = MakeRow(page, page.window, r)
                page.rows[r] = row
            end
            row.index = i
            -- A rule that can't match (ItemRack disabled, say) is red, says why, and is skipped.
            local problem = ns.RuleProblem(rule)
            row.problem = problem
            if problem then
                row.text:SetText(i .. ".  " .. ns.RuleText(rule) .. "  " .. L["(ignored: %s)"]:format(problem))
                row.text:SetTextColor(1, 0.3, 0.3)
            else
                row.text:SetText(i .. ".  " .. ns.RuleText(rule))
                row.text:SetTextColor(1, 1, 1)
            end
            row.up:SetEnabled(i > 1)
            row.down:SetEnabled(c.rules[i + 1] ~= nil)
            row:Show()
        elseif row then
            row:Hide()
        end
    end
    page.empty:SetShown(#c.rules == 0)
    page.more:SetShown(max > 0)
    if max > 0 then page.more:SetText(L["%d rules: scroll to see them all."]:format(#c.rules)) end
end

local function Build(page, f)
    page.window, page.rows, page.offset = f, {}, 0
    page:EnableMouseWheel(true)
    page:SetScript("OnMouseWheel", function(_, delta)
        local c = ns.char
        local max = c and math.max(0, #c.rules - ROWS) or 0
        local to = math.max(0, math.min(max, page.offset - delta))
        if to ~= page.offset then
            page.offset = to
            ns.RefreshWindow()
        end
    end)
    page.new = { when = "shield" }
    local title = Text(f, page, "GameFontNormalLarge", L["Switch profiles automatically"])
    title:SetPoint("TOPLEFT", 16, -14)

    page.auto = ns.ChoiceRow(f, page, { { true, L["On"] }, { false, L["Off"] } },
        function() return ns.AutoOn() end,
        function(on) ns.RunCommand("auto", on and "on" or "off") end, 60)
    page.auto:SetPoint("LEFT", title, "RIGHT", 16, 0)
    page.ask = ns.ChoiceRow(f, page, { { true, L["Ask before switching"] } },
        function() return ns.AskFirst() end,
        function() ns.db.settings.askSwitch = not ns.db.settings.askSwitch or nil; ns.RefreshWindow() end, 170)
    page.ask:SetPoint("LEFT", page.auto, "RIGHT", 16, 0)

    local newLabel = Text(f, page, "GameFontNormal", L["New rule: when"])
    newLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -18)
    page.when = ns.ChoiceRow(f, page, {
        { "shield", L["a shield"] }, { "twohand", L["a two-hander"] }, { "item", L["an item"] }, { "set", L["a set"] },
    }, function() return page.new.when end, function(value)
        page.new.when = value
        ns.RefreshWindow()
    end, 96)
    page.when:SetPoint("LEFT", newLabel, "RIGHT", 10, 0)
    page.whenWidth = page.when:GetWidth()
    local equipped = Text(f, page, "GameFontNormal", L["is equipped,"])
    equipped:SetPoint("LEFT", page.when, "RIGHT", 10, 0)

    -- The item: dropped here from the bags or the character sheet (it goes back at once).
    local item = Button(f, page, "", 220, nil)
    item:SetPoint("TOPLEFT", newLabel, "BOTTOMLEFT", 0, -14)
    local icon = item:CreateTexture(nil, "OVERLAY")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", 6, 0)
    item.icon = icon
    local function TakeItem()
        local kind, id = GetCursorInfo()
        if kind ~= "item" then return end
        page.new.item = id
        ClearCursor() -- an item from the bags goes back to its bag
        ns.RefreshWindow()
    end
    item:SetScript("OnReceiveDrag", TakeItem)
    item:SetScript("OnClick", TakeItem)
    item:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Pick up an item from your bags or character sheet and drop it here."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    item:SetScript("OnLeave", function() GameTooltip:Hide() end)
    page.item = item
    page.set = Button(f, page, "", 220, function()
        page.new.set = NextOf(SetChoices(), page.new.set)
        ns.RefreshWindow()
    end)
    page.set:SetPoint("TOPLEFT", newLabel, "BOTTOMLEFT", 0, -14)
    page.profile = Button(f, page, "", 180, function()
        page.new.profile = NextOf(ns.ProfileNames(), page.new.profile)
        ns.RefreshWindow()
    end)
    page.profile:SetPoint("LEFT", page.item, "RIGHT", 12, 0)
    page.add = Button(f, page, L["Add rule"], 100, function()
        local n = page.new
        local rule = { when = n.when, profile = n.profile, id = n.when == "item" and n.item or nil,
            set = n.when == "set" and n.set or nil }
        if rule.set and rule.set:sub(1, #ITEMRACK) == ITEMRACK then
            rule.set, rule.from = rule.set:sub(#ITEMRACK + 1), "itemrack"
        end
        local ok, why = ns.AddRule(rule)
        if not ok then ns.Print(why) end
    end)
    page.add:SetPoint("LEFT", page.profile, "RIGHT", 8, 0)

    local empty = Text(f, page, "GameFontHighlight",
        L["No rules yet. For example: when a shield is equipped, use your Prot profile."])
    empty:SetPoint("TOPLEFT", page, "TOPLEFT", 24, -160)
    page.empty = empty
    local more = Text(f, page, "GameFontDisableSmall")
    more:SetPoint("TOPLEFT", page, "TOPLEFT", 24, -150 - ROWS * ROW_HEIGHT - 6)
    page.more = more
    local note = Text(f, page, "GameFontDisableSmall",
        L["The first rule that matches wins. In combat, the switch waits until combat ends."])
    note:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 16, 8)
    page.Refresh = Refresh
end

ns.pageBuilders.rules = Build

-- Equipment sets and gear change what can be chosen.
for _, event in ipairs({ "EQUIPMENT_SETS_CHANGED", "PLAYER_EQUIPMENT_CHANGED" }) do
    ns.On(event, function() ns.RequestRefresh("rules") end)
end
