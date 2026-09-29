-- Keystance bank panel: a small Keystance button on the bank window (Blizzard's,
-- EllesmereUI's or ElvUI's) opens a panel beside it, one row per profile with Keystance's
-- own gear: where its items are, Get (bank to bags) and Put (bags to bank; what another
-- profile uses and what's worn stay out). Built the first time the button is clicked; it
-- closes with the bank.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)
local L = ns.L

local ipairs, pairs, pcall, CreateFrame = ipairs, pairs, pcall, CreateFrame

local ICON = "Interface\\AddOns\\" .. ADDON .. "\\media\\minimap.tga"
-- The logo with its gold ring, like EllesmereUI's own round header buttons.
local RINGED = "Interface\\AddOns\\" .. ADDON .. "\\media\\logo.tga"
local ROWS, ROW_H, WIDTH = 8, 30, 380

local panel
local buttons = {} -- the bank window's name -> our button on it

-- Alts Forever puts its own button in the same places; ours goes just left of it then.
local function AltsForever()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
    if not loaded then return false end
    return (loaded("AltsForever") or loaded("AltsForeverDev")) and true or false
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------
-- One of two messages by count ("1 item", "3 items"), filled with the rest.
local function Plural(n, one, many, ...) return (n == 1 and one or many):format(...) end

-- "2 in bank · 3 in bags · 1 worn"
local function StatusText(places)
    local parts = {}
    if places.bank > 0 then parts[#parts + 1] = L["%d in bank"]:format(places.bank) end
    if places.bags > 0 then parts[#parts + 1] = L["%d in bags"]:format(places.bags) end
    if places.worn > 0 then parts[#parts + 1] = L["%d worn"]:format(places.worn) end
    if places.missing > 0 then parts[#parts + 1] = L["%d missing"]:format(places.missing) end
    return table.concat(parts, " · ")
end

local function Report(name, dir, before)
    return function(result)
        local problem = result.why or result.full > 0 or result.refused > 0
        if result.moved > 0 and dir == "get" then
            ns.Notify(Plural(result.moved, L["%s: %d item moved to your bags."], L["%s: %d items moved to your bags."],
                name, result.moved))
        elseif result.moved > 0 then
            ns.Notify(Plural(result.moved, L["%s: %d item put in the bank."], L["%s: %d items put in the bank."],
                name, result.moved))
        end
        if result.full > 0 then
            ns.Print(dir == "get" and L["%d didn't fit: your bags are full."]:format(result.full)
                or L["%d didn't fit: your bank is full."]:format(result.full))
        end
        if result.refused > 0 then ns.Print(L["%d couldn't be moved: the game wouldn't put it there."]:format(result.refused)) end
        if result.why then ns.Print(L["Stopped: %s."]:format(result.why)) end
        if dir == "put" and before then
            if before.shared > 0 then
                ns.Notify(Plural(before.shared, L["%d stayed in your bags: another profile uses it."],
                    L["%d stayed in your bags: other profiles use them."], before.shared))
            end
            if before.worn > 0 then
                ns.Notify(Plural(before.worn, L["%d stayed on: you're wearing it."], L["%d stayed on: you're wearing them."],
                    before.worn))
            end
        end
        if problem then ns.Sound({ "IG_QUEST_LOG_ABANDON_QUEST" }) end
        ns.RefreshBankPanel()
        ns.RequestRefresh("profiles")
    end
end

local function Move(row, dir)
    if not row.profile then return end
    local before = ns.ProfileGearPlaces(row.profile)
    local ok, why = ns.MoveProfileGear(row.profile, dir, Report(row.profile, dir, before))
    if not ok then ns.Print(L["Gear not moved: %s."]:format(why)) end
    ns.RefreshBankPanel()
end

local function RowTooltip(b, text)
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:AddLine(text, 1, 1, 1, true)
    GameTooltip:Show()
end

local function MakeRow(f, i)
    local row = CreateFrame("Frame", nil, f)
    row:SetSize(WIDTH - 32, ROW_H)
    row:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -52 - (i - 1) * ROW_H)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(24, 24)
    row.icon:SetPoint("LEFT")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -132, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.status:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 0)
    row.put = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.put:SetSize(60, 22)
    row.put:SetPoint("RIGHT")
    row.put:SetText(L["Put"])
    row.put:SetScript("OnClick", function() Move(row, "put") end)
    row.put:SetScript("OnEnter", function(self)
        RowTooltip(self, L["Put this profile's gear in the bank. What another profile uses, and what you're wearing, stays out."])
    end)
    row.put:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.get = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.get:SetSize(60, 22)
    row.get:SetPoint("RIGHT", row.put, "LEFT", -4, 0)
    row.get:SetText(L["Get"])
    row.get:SetScript("OnClick", function() Move(row, "get") end)
    row.get:SetScript("OnEnter", function(self) RowTooltip(self, L["Move this profile's gear from the bank to your bags."]) end)
    row.get:SetScript("OnLeave", function() GameTooltip:Hide() end)
    for _, fs in ipairs({ row.name, row.status }) do
        f.texts[#f.texts + 1] = fs
        ns.SkinText(fs)
    end
    for _, b in ipairs({ row.get, row.put }) do ns.SkinButton(b) end
    return row
end

function ns.RefreshBankPanel()
    if not (panel and panel:IsShown()) then return end
    local c = ns.char
    local names = {}
    for _, name in ipairs(ns.ProfileNames()) do
        local kind = ns.ProfileGear(c.profiles[name])
        if kind == "items" then names[#names + 1] = name end
    end
    local busy = ns.BankMoveBusy() or ns.GearBusy()
    for i = 1, math.min(#names, ROWS) do
        panel.rows[i] = panel.rows[i] or MakeRow(panel, i)
    end
    for i, row in ipairs(panel.rows) do
        local name = names[i]
        row.profile = name
        if name then
            local p = c.profiles[name]
            local icon, crop = ns.ProfileIcon(p)
            row.icon:SetTexture(icon)
            if crop then row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else row.icon:SetTexCoord(0, 1, 0, 1) end
            row.name:SetText(name)
            local places = ns.ProfileGearPlaces(name)
            row.status:SetText(StatusText(places))
            row.get:SetEnabled(not busy and #places.toBags > 0)
            row.put:SetEnabled(not busy and #places.toBank > 0)
            row:Show()
        else
            row:Hide()
        end
    end
    panel.empty:SetShown(#names == 0)
    if #names == 0 then
        panel.empty:SetText(ns.GearSource() == "itemrack"
            and L["Your profiles use ItemRack's sets. ItemRack has its own bank buttons."]
            or L["No profile has Keystance's own gear yet. Set it from a profile's Gear button."])
    end
    local shown = math.max(1, math.min(#names, ROWS))
    panel.more:SetShown(#names > ROWS)
    if #names > ROWS then panel.more:SetText(L["%d more on the Profiles tab."]:format(#names - ROWS)) end
    panel:SetHeight(52 + shown * ROW_H + (#names > ROWS and 20 or 0) + 52)
end

local function Create()
    local f = ns.FramedWindow("KeystanceBankPanel")
    panel = f
    f.buttons, f.texts, f.rows = {}, {}, {}
    f:SetSize(WIDTH, 200)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    local title = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if not f.TitleText then title:SetPoint("TOP", 0, -6) end
    title:SetText(L["Keystance: gear and the bank"])
    local empty = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    empty:SetPoint("TOPLEFT", 16, -52)
    empty:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    empty:SetJustifyH("LEFT")
    f.empty = empty
    local more = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    more:SetPoint("BOTTOMLEFT", 16, 44)
    f.more = more
    local note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("BOTTOMLEFT", 16, 12)
    note:SetPoint("BOTTOMRIGHT", -16, 12)
    note:SetJustifyH("LEFT")
    note:SetText(L["Get takes a profile's gear out of the bank. Put stores it, keeping what another profile uses in your bags."])
    for _, fs in ipairs({ empty, more, note }) do f.texts[#f.texts + 1] = fs end
    -- While it's open, follow the bags (a closed panel costs nothing).
    f:SetScript("OnShow", function(self) pcall(self.RegisterEvent, self, "BAG_UPDATE_DELAYED") end)
    f:SetScript("OnHide", function(self) self:UnregisterEvent("BAG_UPDATE_DELAYED") end)
    f:SetScript("OnEvent", function() ns.RefreshBankPanel() end)
    ns.SkinWindow(f)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "KeystanceBankPanel" end
    f:Hide()
end

-- Opens the panel beside the bank window `anchor`, or closes it.
local function TogglePanel(anchor)
    if not panel then Create() end
    if panel:IsShown() then return panel:Hide() end
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
    panel:Show()
    ns.RefreshBankPanel()
end

---------------------------------------------------------------------------
-- The button on the bank window
---------------------------------------------------------------------------
-- round: EllesmereUI's style, the ringed logo slightly dimmed, brightening on hover (no
-- square highlight on a round button).
local function Button(parent, bankFrame, size, round)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(round and RINGED or ICON)
    if round then
        b.rest = 0.9
        b.icon:SetAlpha(b.rest)
    else
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.15)
    end
    b:SetScript("OnClick", function() TogglePanel(bankFrame) end)
    b:SetScript("OnEnter", function(self)
        if self.rest then self.icon:SetAlpha(1) end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Keystance")
        GameTooltip:AddLine(L["Move your profiles' gear in and out of the bank."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        if self.rest then self.icon:SetAlpha(self.rest) end
        GameTooltip:Hide()
    end)
    return b
end

-- The left end of a header's row of buttons: from `start` (the search box), each next
-- button is the shown one anchored by its RIGHT to the previous one's LEFT (EllesmereUI:
-- sort, then Show Bags, then anything another addon chained on, such as Alts Forever's).
-- Following the anchors rather than fixed offsets keeps working when EllesmereUI adds,
-- hides or moves a button, and whichever of Keystance and Alts Forever comes second goes
-- to the left of the other (Alts Forever does the same).
local function RowEnd(start)
    local parent, current = start:GetParent(), start
    for _ = 1, 20 do
        local found
        for _, child in ipairs({ parent:GetChildren() }) do
            if child ~= current and child:IsShown() and child.GetPoint then
                for i = 1, (child.GetNumPoints and child:GetNumPoints() or 1) do
                    local point, rel, relPoint = child:GetPoint(i)
                    if point == "RIGHT" and rel == current and relPoint == "LEFT" then found = child end
                end
            end
        end
        if not found then return current end
        current = found
    end
    return current
end

-- Where each bank window gets its button (Blizzard's and ElvUI's beside where Alts Forever
-- places its own, which is then to our right). Each returns the button, or nil if the
-- window isn't there yet. EllesmereUI's fields are not its official API: they're checked
-- before use.
local PLACES = {
    -- Blizzard's bank: in the title area, left of the search box.
    BankFrame = function(af)
        local search = _G.BankItemSearchBox
        if not (_G.BankFrame and search) then return end
        local b = Button(_G.BankFrame, _G.BankFrame, 22)
        b:SetPoint("RIGHT", search, "LEFT", af and -38 or -10, 0)
        return b
    end,
    -- ElvUI: its header buttons are all on the right; the top-left corner is free.
    ElvUI_BankContainerFrame = function(af)
        local f = _G.ElvUI_BankContainerFrame
        if not f then return end
        local b = Button(f, f, 20)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", af and 32 or 6, -6)
        return b
    end,
    -- EllesmereUI: at the left end of its header row (left of sort, Show Bags and any
    -- other addon's button there).
    EUI_BankFrame = function()
        local f = _G.EUI_BankFrame
        local search = f and f._searchBox
        if not (search and search.GetParent) then return end
        local anchor = RowEnd(search)
        local b = Button(search:GetParent(), f, 24, true)
        b:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
        return b
    end,
}

local function Attach()
    local af = AltsForever()
    for name, place in pairs(PLACES) do
        if not buttons[name] then buttons[name] = place(af) end
    end
end

function ns.BankButtons() return buttons end

local function Closed()
    if panel then panel:Hide() end
end

-- The bank windows may be made on the first visit, and a frame later.
local function Opened()
    Attach()
    C_Timer.After(0, Attach)
end
ns.On("BANKFRAME_OPENED", Opened)
ns.On("BANKFRAME_CLOSED", Closed)
local BANKER = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Banker
if BANKER then
    ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(kind) if kind == BANKER then Opened() end end)
    ns.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(kind) if kind == BANKER then Closed() end end)
end
