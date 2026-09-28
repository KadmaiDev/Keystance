-- Keystance spell panel: everything to put on bars and keys in one place, in four tabs.
--  * Spells: every class spell, so bars can be set up without paging through the
--    spellbook. The spellbook's sections as headers that fold away; each spell at its
--    highest rank, whether it's on a bar, and what's still to learn ("next at 22").
--    Right-click shows its other ranks; Shift-click links it in chat.
--  * Macros: the account's and the character's macros.
--  * Raid markers: markers are keybindings, not actions, so clicking one waits for a key
--    in the Keyboard tab (Drops.lua); each shows the key it's on.
--  * Profiles: each profile's switch (and Next profile), held and put on a key the same way.
-- Search as you type; filters for what's on a bar, not on a bar, or still to learn. Drag or
-- click a spell or macro to pick it up, then drop it on a bar or a key in the Keyboard tab.
-- It sits against the Keystance window when both are open, unless it's been moved.
-- Built on first open; refreshed only while shown. Picking up is blocked in combat.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)
local L = ns.L

local ipairs, pairs, CreateFrame = ipairs, pairs, CreateFrame

local WIDTH, HEIGHT = 330, 520
local ROWS, ROW_HEIGHT = 13, 27
local BANK = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
local CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready"

local panel
local items = {} -- the visible list, flattened: { kind = "header"|"spell"|"rank", ... }
local offset = 0
local expanded = {} -- [spell name] = true while its ranks are shown

local function Settings() return ns.db.settings end
local function Kind() return Settings().spellKind or "spells" end

-- The raid markers, in the game's order, with their binding commands.
local MARKERS = {
    { 1, L["Star"] }, { 2, L["Circle"] }, { 3, L["Diamond"] }, { 4, L["Triangle"] },
    { 5, L["Moon"] }, { 6, L["Square"] }, { 7, L["Cross"] }, { 8, L["Skull"] },
}
local MARKER_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"
local PROFILE_ICON = "Interface\\AddOns\\" .. ADDON .. "\\media\\icon.tga"

---------------------------------------------------------------------------
-- Picking up
---------------------------------------------------------------------------
local function Pickup(entry, rankID)
    if ns.InCombat() then return ns.Print(L["Spells can't be picked up in combat."]) end
    ns.CancelBinding() -- one thing held at a time
    if not entry.known then
        return ns.Print(L["%s is learned at level %s."]:format(entry.name, tostring(entry.level or "?")))
    end
    if entry.flyout then
        C_SpellBook.PickupSpellBookItem(entry.flyout, BANK)
    else
        C_Spell.PickupSpell(rankID or entry.id)
    end
end

local function PickupMacroAt(index)
    if ns.InCombat() then return ns.Print(L["Macros can't be picked up in combat."]) end
    ns.CancelBinding()
    PickupMacro(index)
end

local function Link(id)
    local link = id and C_Spell.GetSpellLink and C_Spell.GetSpellLink(id)
    if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------
local function Matches(entry, search, filter)
    if search ~= "" and not entry.lower:find(search, 1, true) then return false end
    if filter == "missing" then return entry.known and not entry.onBar end
    if filter == "onbar" then return entry.onBar end
    if filter == "later" then return not entry.known or entry.nextRank ~= nil end
    return true
end

local function Search()
    return ((panel.search:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The macros: account-wide first, then this character's, each marked if it's on a bar.
local function CollectMacros(search, filter)
    local onBar = {}
    for slot = 1, ns.MANAGED_SLOTS do
        if HasAction(slot) and GetActionInfo(slot) == "macro" then
            local name = GetActionText(slot)
            if name then onBar[name] = true end
        end
    end
    local account, perChar = GetNumMacros()
    local groups = {
        { L["Account macros"], 1, account or 0 },
        { L["%s's macros"]:format(ns.charKey or "?"), (MAX_ACCOUNT_MACROS or 120) + 1, perChar or 0 },
    }
    for _, g in ipairs(groups) do
        local header = { kind = "header", name = g[1], count = 0 }
        local start = #items + 1
        items[start] = header
        for index = g[2], g[2] + g[3] - 1 do
            local name, icon, body = GetMacroInfo(index)
            if name then
                local on = onBar[name] or false
                local keep = (search == "" or name:lower():find(search, 1, true))
                    and (filter ~= "missing" or not on) and (filter ~= "onbar" or on)
                if keep then
                    header.count = header.count + 1
                    items[#items + 1] = { kind = "macro", index = index, name = name, icon = icon, body = body, onBar = on }
                end
            end
        end
        if header.count == 0 then items[start] = nil end
    end
end

local function CollectMarkers(search)
    for _, m in ipairs(MARKERS) do
        if search == "" or m[2]:lower():find(search, 1, true) then
            local command = "RAIDTARGET" .. m[1]
            items[#items + 1] = { kind = "marker", command = command, name = m[2], icon = MARKER_ICON:format(m[1]),
                key = GetBindingKey(command) }
        end
    end
    local clear = L["Remove marker"]
    if search == "" or clear:lower():find(search, 1, true) then
        items[#items + 1] = { kind = "marker", command = "RAIDTARGETNONE", name = clear,
            icon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up", key = GetBindingKey("RAIDTARGETNONE") }
    end
end

-- Each profile (its ItemRack set's picture, or Keystance's), then Next profile.
local function CollectProfiles(search)
    local c = ns.char
    for _, name in ipairs(ns.ProfileNames()) do
        if search == "" or name:lower():find(search, 1, true) then
            local p = c.profiles[name]
            local n = ns.ProfileSlot(name)
            local icon, crop = ns.ProfileIcon(p)
            items[#items + 1] = { kind = "profile", name = name, icon = icon, crop = crop,
                key = n and GetBindingKey(ns.ProfileSlotCommand(n)) }
        end
    end
    local nextName = L["Next profile"]
    if search == "" or nextName:lower():find(search, 1, true) then
        items[#items + 1] = { kind = "marker", command = "KEYSTANCE_NEXT", name = nextName, icon = PROFILE_ICON,
            key = GetBindingKey("KEYSTANCE_NEXT") }
    end
end

-- Rebuilds `items` from the tab, the search and the filter.
local function Collect()
    for i = #items, 1, -1 do items[i] = nil end
    local search = Search()
    local filter = Settings().spellFilter or "all"
    local kind = Kind()
    if kind == "macros" then return CollectMacros(search, filter == "later" and "all" or filter) end
    if kind == "markers" then return CollectMarkers(search) end
    if kind == "profiles" then return CollectProfiles(search) end
    local collapsed = Settings().spellCollapsed or {}
    for _, section in ipairs(ns.SpellSections()) do
        local header = { kind = "header", name = section.name, count = 0 }
        local start = #items + 1
        items[start] = header
        -- Known spells first, then those still to learn by level.
        local later = {}
        for _, e in ipairs(section.entries) do
            if Matches(e, search, filter) then
                header.count = header.count + 1
                if e.known then
                    if not collapsed[section.name] or search ~= "" then
                        items[#items + 1] = { kind = "spell", entry = e }
                        if expanded[e.name] and #e.ranks > 1 then
                            for r = #e.ranks, 1, -1 do items[#items + 1] = { kind = "rank", entry = e, rank = e.ranks[r] } end
                        end
                    end
                else
                    later[#later + 1] = e
                end
            end
        end
        table.sort(later, function(a, b) return (a.level or 99) < (b.level or 99) end)
        if not collapsed[section.name] or search ~= "" then
            for _, e in ipairs(later) do items[#items + 1] = { kind = "spell", entry = e } end
        end
        if header.count == 0 then items[start] = nil end
        header.collapsed = collapsed[section.name] and search == ""
    end
end

local function RowTooltip(row)
    local item = row.item
    if not item or item.kind == "header" then return end
    if item.kind == "macro" then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(item.name)
        if item.body then GameTooltip:AddLine(item.body, 1, 1, 1, true) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Drag onto a bar, or onto a key in Keystance's Keyboard tab."], 0.6, 0.8, 1, true)
        return GameTooltip:Show()
    elseif item.kind == "marker" or item.kind == "profile" then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(item.kind == "profile" and L["Switch to %s"]:format(item.name) or item.name)
        GameTooltip:AddLine(item.key and L["On %s."]:format(item.key) or L["Not on a key."], 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Click to pick it up, then click a key in Keystance's Keyboard tab. Right-click drops it."], 0.6, 0.8, 1, true)
        return GameTooltip:Show()
    end
    local e = item.entry
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local id = item.kind == "rank" and item.rank.id or e.id or e.futureID
    if id and GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(id) else GameTooltip:AddLine(e.name) end
    GameTooltip:AddLine(" ")
    if e.known then
        GameTooltip:AddLine(L["Drag onto a bar, or onto a key in Keystance's Keyboard tab."], 0.6, 0.8, 1, true)
        if #e.ranks > 1 and item.kind == "spell" then GameTooltip:AddLine(L["Right-click: its other ranks."], 0.6, 0.8, 1) end
        GameTooltip:AddLine(L["Shift-click: link it in chat."], 0.6, 0.8, 1)
    else
        GameTooltip:AddLine(L["Learned at level %s."]:format(tostring(e.level or "?")), 1, 0.82, 0)
    end
    GameTooltip:Show()
end

local function RowClick(row, button)
    local item = row.item
    if not item then return end
    if item.kind == "header" then
        local collapsed = Settings().spellCollapsed or {}
        Settings().spellCollapsed = collapsed
        collapsed[item.name] = not collapsed[item.name] or nil
        return panel:Refresh()
    end
    if item.kind == "macro" then return PickupMacroAt(item.index) end
    if item.kind == "marker" then return ns.StartBinding(item.command, item.name, item.icon) end
    if item.kind == "profile" then return ns.StartBinding(nil, item.name, item.icon, item.name) end
    local e = item.entry
    local id = item.kind == "rank" and item.rank.id or e.id
    if IsModifiedClick and IsModifiedClick("CHATLINK") then return Link(id or e.futureID) end
    if button == "RightButton" and item.kind == "spell" then
        if #e.ranks > 1 then
            expanded[e.name] = not expanded[e.name] or nil
            panel:Refresh()
        end
        return
    end
    Pickup(e, item.kind == "rank" and id or nil)
end

-- A raid marker is held like a spell on the cursor (Drops.lua): clicking or dragging it
-- picks it up. Let go of a drag over a key in the Keyboard tab and it goes there; let go
-- anywhere else and it stays held, as a spell does, until a key is clicked or a
-- right-click drops it.
local draggingMarker = false
local function RowDragStop()
    if not draggingMarker then return end
    draggingMarker = false
    local foci = GetMouseFoci and GetMouseFoci()
    local target = type(foci) == "table" and foci[1]
    if target and target.isKeyCap and target.fullKey and ns.HeldBinding() then
        ns.BindHeld(target.fullKey, target.command)
    end
end

local function RowDrag(row)
    local item = row.item
    if item and (item.kind == "marker" or item.kind == "profile") then
        ns.StartBinding(item.command, item.name, item.icon, item.kind == "profile" and item.name or nil)
        draggingMarker = ns.HeldBinding() ~= nil
        return
    end
    if not item or item.kind == "header" then return end
    if item.kind == "macro" then return PickupMacroAt(item.index) end
    Pickup(item.entry, item.kind == "rank" and item.rank.id or nil)
end

local function MakeRow(f, list, i)
    local row = CreateFrame("Button", nil, list)
    row:SetSize(WIDTH - 44, ROW_HEIGHT - 2)
    row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:RegisterForDrag("LeftButton")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("LEFT", 2, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = icon
    local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    name:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    name:SetPoint("RIGHT", row, "RIGHT", -96, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    row.name = name
    local detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    detail:SetPoint("RIGHT", row, "RIGHT", -22, 0)
    detail:SetJustifyH("RIGHT")
    row.detail = detail
    local check = row:CreateTexture(nil, "OVERLAY")
    check:SetSize(14, 14)
    check:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    check:SetTexture(CHECK)
    row.check = check
    f.texts[#f.texts + 1] = name
    f.texts[#f.texts + 1] = detail
    row:SetScript("OnClick", RowClick)
    row:SetScript("OnDragStart", RowDrag)
    row:SetScript("OnDragStop", RowDragStop)
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function ShowRow(row, item, combat)
    row.item = item
    if not item then return row:Hide() end
    row:Show()
    row.check:Hide()
    if item.kind == "header" then
        row.icon:SetTexture(item.collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
        row.icon:SetTexCoord(0, 1, 0, 1)
        row.icon:SetDesaturated(false)
        row.name:SetText("|cffffd100" .. item.name .. "|r")
        row.detail:SetText(item.count)
        return
    end
    if item.kind == "macro" then
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.icon:SetTexture(item.icon)
        row.icon:SetDesaturated(combat)
        row.name:SetText(item.name)
        row.detail:SetText("")
        row.check:SetShown(item.onBar)
        return
    elseif item.kind == "marker" or item.kind == "profile" then
        if item.crop then row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else row.icon:SetTexCoord(0, 1, 0, 1) end
        row.icon:SetTexture(item.icon)
        row.icon:SetDesaturated(false)
        row.name:SetText(item.name)
        row.detail:SetText(item.key and ns.ShortKey(item.key) or ("|cff9d9d9d" .. L["no key"] .. "|r"))
        return
    end
    local e = item.entry
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if item.kind == "rank" then
        row.icon:SetTexture(e.icon)
        row.icon:SetDesaturated(combat)
        row.name:SetText("    " .. (item.rank.rank ~= "" and item.rank.rank or e.name))
        row.detail:SetText(item.rank.id == e.id and L["highest"] or "")
        return
    end
    row.icon:SetTexture(e.icon)
    row.icon:SetDesaturated(combat or not e.known)
    if e.known then
        row.name:SetText(e.name)
        local top = e.ranks[#e.ranks]
        local rank = top and top.rank ~= "" and top.rank:match("(%d+)") and L["Rank %s"]:format(top.rank:match("(%d+)")) or ""
        if e.nextRank and e.nextRank.level then
            rank = rank .. (rank ~= "" and "  " or "") .. "|cff9d9d9d" .. L["next at %d"]:format(e.nextRank.level) .. "|r"
        end
        row.detail:SetText(rank)
        row.check:SetShown(e.onBar)
    else
        row.name:SetText("|cff9d9d9d" .. e.name .. "|r")
        row.detail:SetText(L["level %s"]:format(tostring(e.level or "?")))
    end
end

local function Refresh(self)
    if not self:IsShown() then return end
    Collect()
    local combat = ns.InCombat()
    local maxOffset = math.max(0, #items - ROWS)
    if offset > maxOffset then offset = maxOffset end
    self.scroll:SetMinMaxValues(0, maxOffset)
    self.scroll:SetValue(offset)
    self.scroll:SetShown(maxOffset > 0)
    for i, row in ipairs(self.rows) do ShowRow(row, items[offset + i], combat) end
    self.kinds:Refresh()
    self.filters:Refresh()
    local kind = Kind()
    self.filters:SetShown(kind ~= "markers" and kind ~= "profiles")
    self.keysOnly:SetShown(kind == "markers" or kind == "profiles")
    self.filters.buttons[4]:SetShown(kind == "spells")
    self.combat:SetShown(combat)
    self.empty:SetShown(#items == 0)
    self.dock:SetShown(not self.docked and ns.WindowShown())
end

---------------------------------------------------------------------------
-- Position: against the Keystance window unless moved
---------------------------------------------------------------------------
local function Place()
    panel:ClearAllPoints()
    local s = Settings()
    if not s.spellPanelPos and KeystanceFrame and KeystanceFrame:IsShown() then
        panel:SetPoint("TOPLEFT", KeystanceFrame, "TOPRIGHT", 4, 0)
        panel.docked = true
    elseif s.spellPanelPos then
        local p = s.spellPanelPos
        panel:SetPoint(p[1], UIParent, p[2], p[3], p[4])
        panel.docked = false
    else
        panel:SetPoint("RIGHT", UIParent, "RIGHT", -60, 0)
        panel.docked = false
    end
end

local function Create()
    local ok, f = pcall(CreateFrame, "Frame", "KeystanceSpellPanel", UIParent, "BasicFrameTemplateWithInset")
    if not ok then
        f = CreateFrame("Frame", "KeystanceSpellPanel", UIParent, "BackdropTemplate")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
    end
    panel = f
    f.buttons, f.texts, f.rows = {}, {}, {}
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if point then Settings().spellPanelPos = { point, relPoint, x, y } end
        self.docked = false
        self:Refresh()
    end)
    local title = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if not f.TitleText then title:SetPoint("TOP", 0, -6) end
    title:SetText(L["Spells"])

    f.kinds = ns.ChoiceRow(f, f, { { "spells", L["Spells"] }, { "macros", L["Macros"] }, { "markers", L["Markers"] },
        { "profiles", L["Profiles"] } },
        Kind, function(value)
            Settings().spellKind = value
            offset = 0
            f:Refresh()
        end, 73)
    f.kinds:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -30)

    local okBox, search = pcall(CreateFrame, "EditBox", "KeystanceSpellSearch", f, "SearchBoxTemplate")
    if not okBox then search = CreateFrame("EditBox", "KeystanceSpellSearch", f, "InputBoxTemplate") end
    search:SetSize(WIDTH - 36, 20)
    search:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -60)
    search:SetAutoFocus(false)
    search:HookScript("OnTextChanged", function()
        offset = 0
        f:Refresh()
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.search = search

    f.filters = ns.ChoiceRow(f, f, {
        { "all", L["All"] }, { "missing", L["Not on bars"] }, { "onbar", L["On bars"] }, { "later", L["To learn"] },
    }, function() return Settings().spellFilter or "all" end, function(value)
        Settings().spellFilter = value
        offset = 0
        f:Refresh()
    end, 72)
    f.filters:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -4, -8)
    -- Markers and profile switches are keybindings, not actions: where the filters would be,
    -- they say so (they can't go on a bar).
    local keysOnly = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    keysOnly:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -2, -6)
    keysOnly:SetWidth(WIDTH - 40)
    keysOnly:SetJustifyH("LEFT")
    keysOnly:SetTextColor(0.6, 0.8, 1)
    keysOnly:SetText(L["These go on keys, not on bars. Pick one up, then click a key on the Keyboard tab."])
    keysOnly:Hide()
    f.keysOnly = keysOnly
    f.texts[#f.texts + 1] = keysOnly

    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -118)
    list:SetSize(WIDTH - 40, ROWS * ROW_HEIGHT)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, math.min(math.max(0, #items - ROWS), offset - delta * 3))
        f:Refresh()
    end)
    for i = 1, ROWS do f.rows[i] = MakeRow(f, list, i) end

    local scroll = CreateFrame("Slider", nil, f)
    scroll:SetOrientation("VERTICAL")
    scroll:SetSize(6, ROWS * ROW_HEIGHT)
    scroll:SetPoint("TOPLEFT", list, "TOPRIGHT", 4, 0)
    local thumb = scroll:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(0.7, 0.7, 0.7, 0.6)
    thumb:SetSize(6, 40)
    scroll:SetThumbTexture(thumb)
    scroll:SetValueStep(1)
    scroll:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        if value ~= offset then
            offset = value
            f:Refresh()
        end
    end)
    f.scroll = scroll

    local empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOP", list, "TOP", 0, -40)
    empty:SetText(L["Nothing matches."])
    f.empty = empty
    f.texts[#f.texts + 1] = empty

    local combat = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    combat:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 12)
    combat:SetTextColor(1, 0.5, 0.25)
    combat:SetText(L["In combat: spells can be picked up again when it ends."])
    f.combat = combat

    local dock = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    dock:SetSize(150, 22)
    dock:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 8)
    dock:SetText(L["Next to Keystance"])
    dock:SetScript("OnClick", function()
        Settings().spellPanelPos = nil
        Place()
        f:Refresh()
    end)
    f.dock = dock
    f.buttons[#f.buttons + 1] = dock

    f.Refresh = Refresh
    ns.SkinWindow(f)
    f:SetScript("OnShow", function(self)
        Settings().spellPanelHidden = nil
        Place()
        self:Refresh()
    end)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "KeystanceSpellPanel" end
    f:Hide()
    -- Closed by the player while the Keystance window is open: remembered, so opening the
    -- window doesn't bring it back until the Spells button does. (Closing with the window,
    -- or with Escape after the window, isn't the player turning it off.)
    f:SetScript("OnHide", function(self)
        if not self.closingWithWindow and ns.WindowShown() then Settings().spellPanelHidden = true end
        self.closingWithWindow = nil
    end)
end

-- Opens or closes the spell panel; `open` only ever opens it.
function ns.RefreshSpellPanel()
    if panel and panel:IsShown() then panel:Refresh() end
end

function ns.ToggleSpellPanel(open)
    if not panel then Create() end
    if panel:IsShown() and not open then panel:Hide() else panel:Show() end
end

-- The panel opens with the Keystance window (docked beside it) unless the player closed it,
-- and a docked panel closes with the window.
-- Tabs where the panel belongs: things are dragged from it onto keys and bars.
local PANEL_TABS = { keyboard = true, bars = true }

function ns.WindowOpened(tab)
    if PANEL_TABS[tab] and not Settings().spellPanelHidden then ns.ToggleSpellPanel(true) end
end

-- Follows the window's tab: opens on Keyboard and Bars (unless the player closed it), and a
-- docked panel steps aside on the others without counting as closed.
function ns.SpellPanelForTab(tab)
    if not ns.WindowShown() then return end
    if PANEL_TABS[tab] then
        ns.WindowOpened(tab)
    elseif panel and panel:IsShown() and panel.docked then
        panel.closingWithWindow = true
        panel:Hide()
    end
end
function ns.WindowClosed()
    if panel and panel:IsShown() and panel.docked then
        panel.closingWithWindow = true
        panel:Hide()
    end
end

function ns.SpellPanelShown() return panel and panel:IsShown() or false end

-- Kept current while shown: spells learned, bars changed, combat.
local pending = false
local function RunRefresh()
    pending = false
    if panel then panel:Refresh() end
end
local function Changed()
    if pending or not (panel and panel:IsShown()) then return end
    pending = true
    C_Timer.After(0.1, RunRefresh)
end
for _, event in ipairs({ "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "ACTIONBAR_SLOT_CHANGED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UPDATE_BINDINGS", "UPDATE_MACROS" }) do
    ns.On(event, Changed)
end

ns.AddCommand("spells", function() ns.ToggleSpellPanel() end)
