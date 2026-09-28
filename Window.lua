-- Keystance main window: tabs across the top (Profiles, Keyboard, Bars, Rules, Settings)
-- and a header strip for the active profile and combat notes. Built the first time it's
-- opened and only refreshed while shown, so a closed window costs nothing.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)
local L = ns.L

local ipairs, pcall, CreateFrame = ipairs, pcall, CreateFrame

local WIDTH, HEIGHT = 720, 460
local frame

-- Profiles first: it's home (a new player's first steps are there), and Keyboard and Bars
-- are where a profile's bars and keys are edited.
local TABS = {
    { key = "profiles", name = L["Profiles"] },
    { key = "keyboard", name = L["Keyboard"] },
    { key = "bars", name = L["Bars"] },
    { key = "rules", name = L["Rules"] },
    { key = "settings", name = L["Settings"] },
}

local function Text(f, parent, template, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    if text then fs:SetText(text) end
    f.texts[#f.texts + 1] = fs
    return fs
end

-- A row of buttons, one per choice, with the chosen one lit. Used for settings instead of
-- Blizzard's pop-up menus: opening one from our window once crashed the beta client inside
-- Blizzard's menu code (2026-09-28, AGENTS.md). choices = { { value, label }, ... };
-- get() returns the chosen value and set(value) chooses one. row:Refresh() relights it.
function ns.ChoiceRow(owner, parent, choices, get, set, width)
    width = width or 90
    local row = CreateFrame("Frame", nil, parent)
    row.buttons = {}
    for i, choice in ipairs(choices) do
        local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        b:SetSize(width, 22)
        b:SetPoint("LEFT", row, "LEFT", (i - 1) * (width + 4), 0)
        b:SetText(choice[2])
        b.value = choice[1]
        b:SetScript("OnClick", function() set(choice[1]) end)
        owner.buttons[#owner.buttons + 1] = b
        row.buttons[i] = b
    end
    row:SetSize(#choices * (width + 4) - 4, 22)
    function row:Refresh()
        local chosen = get()
        for _, b in ipairs(self.buttons) do
            local on = b.value == chosen
            b.chosen = on
            if on then b:LockHighlight() else b:UnlockHighlight() end
            local text = b:GetFontString()
            if text then text:SetTextColor(on and 1 or 0.75, on and 0.82 or 0.75, on and 0 or 0.75) end
        end
    end
    return row
end

---------------------------------------------------------------------------
-- Refresh: what the header and the open page show
---------------------------------------------------------------------------
local function Refresh()
    if not frame or not frame:IsShown() then return end
    frame.combat:SetShown(ns.InCombat())
    local page = frame.pages[frame.selected]
    if page and page.Refresh then page:Refresh() end
end
ns.RefreshWindow = Refresh

-- Refreshes the open window soon, once however many events asked (a bar change fires one
-- event per slot). With a tab key, only if that tab is showing. A closed window costs a check.
local pending = false
local function RunPending()
    pending = false
    Refresh()
end
function ns.RequestRefresh(key)
    if pending or not frame or not frame:IsShown() then return end
    if key and TABS[frame.selected].key ~= key then return end
    pending = true
    C_Timer.After(0.05, RunPending)
end

local function SelectTab(i)
    frame.selected = i
    ns.db.settings.tab = TABS[i].key
    -- Only the keyboard (with the numpad) needs more width; it asks again when shown.
    frame:SetWidth(WIDTH)
    frame.pages[i].boardKey = nil
    -- The spell panel is for Keyboard and Bars, where things are dragged from it.
    ns.SpellPanelForTab(TABS[i].key)
    for j, tab in ipairs(frame.tabs) do
        local on = j == i
        if tab.topTab and PanelTemplates_SelectTab then
            pcall(on and PanelTemplates_SelectTab or PanelTemplates_DeselectTab, tab)
        elseif on then
            tab:LockHighlight()
        else
            tab:UnlockHighlight()
        end
        frame.pages[j]:SetShown(on)
    end
    Refresh()
end

---------------------------------------------------------------------------
-- Building the window
---------------------------------------------------------------------------
local function CreateWindow()
    local ok, f = pcall(CreateFrame, "Frame", "KeystanceFrame", UIParent, "BasicFrameTemplateWithInset")
    if not ok then
        -- Plain fallback if this client lacks the template: a dialog backdrop and a close button.
        f = CreateFrame("Frame", "KeystanceFrame", UIParent, "BackdropTemplate")
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
    end
    frame = f
    f.buttons, f.tabs, f.texts, f.pages = {}, {}, {}, {}
    f:SetSize(WIDTH, HEIGHT)
    local pos = ns.db.settings.window
    if pos then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        f:SetPoint("CENTER")
    end
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if point then ns.db.settings.window = { point, relPoint, x, y } end
    end)

    local title = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if not f.TitleText then title:SetPoint("TOP", 0, -6) end
    title:SetText("Keystance")

    -- Header strip: the combat note (the active profile joins it with profiles).
    local combat = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    combat:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 10)
    combat:SetTextColor(1, 0.5, 0.25)
    combat:SetText(L["In combat: changes wait until combat ends"])
    combat:Hide()
    f.combat = combat

    -- Tabs: Blizzard's top tabs where the client has them, plain buttons otherwise.
    for i, info in ipairs(TABS) do
        local okTab, tab = pcall(CreateFrame, "Button", "KeystanceFrameTab" .. i, f, "PanelTopTabButtonTemplate")
        if okTab then
            tab.topTab = true
        else
            tab = CreateFrame("Button", "KeystanceFrameTab" .. i, f, "UIPanelButtonTemplate")
            tab:SetSize(100, 24)
        end
        tab:SetText(info.name)
        tab:SetID(i)
        if i == 1 then
            tab:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -28)
        else
            tab:SetPoint("LEFT", f.tabs[i - 1], "RIGHT", 4, 0)
        end
        tab:SetScript("OnClick", function() SelectTab(i) end)
        f.tabs[i] = tab

        local page = CreateFrame("Frame", nil, f)
        page:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -60)
        page:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 30)
        page:Hide()
        page.key = info.key
        local build = ns.pageBuilders[info.key]
        if build then
            build(page, f)
        elseif info.blurb then
            local fs = Text(f, page, "GameFontHighlightMedium", info.blurb)
            fs:SetPoint("CENTER")
        end
        f.pages[i] = page
    end
    local settings = f.pages[#TABS]
    local heading = Text(f, settings, "GameFontNormalLarge", L["Settings"])
    heading:SetPoint("TOPLEFT", 16, -16)
    ns.BuildSettings(settings, f, heading)

    f.credit = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.credit:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 10)

    -- The spell panel, which sits against this window.
    local spells = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    spells:SetSize(90, 22)
    spells:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -30)
    spells:SetText(L["Spells"])
    spells:SetScript("OnClick", function() ns.ToggleSpellPanel() end)
    spells:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Spells"])
        GameTooltip:AddLine(L["All your class's spells in one list, to drag onto your bars or onto a key."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    spells:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.spellsButton = spells
    f.buttons[#f.buttons + 1] = spells
    f.credit:SetText(L["Keystance by Kadmai"])

    ns.SkinWindow(f)
    f:SetScript("OnShow", function()
        Refresh()
        ns.WindowOpened(TABS[f.selected].key) -- the spell panel opens beside it (SpellPanel.lua)
    end)
    f:SetScript("OnHide", function() ns.WindowClosed() end)
    -- Escape closes it, like Blizzard's own windows.
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "KeystanceFrame" end
    f:Hide()

    local first = 1
    for i, info in ipairs(TABS) do
        if info.key == ns.db.settings.tab then first = i end
    end
    SelectTab(first)
end

-- Widens the window for what a tab draws (the keyboard with the numpad), or back to normal.
function ns.SetWindowWidth(width)
    if frame then frame:SetWidth(width or WIDTH) end
end

-- Shows the tab with this key ("settings"...), if the window is open.
function ns.ShowTab(key)
    if not frame then return end
    for i, info in ipairs(TABS) do
        if info.key == key then SelectTab(i) end
    end
end

-- Opens or closes the window; `open` only ever opens it (menus).
function ns.ToggleWindow(open)
    if not frame then CreateWindow() end
    if frame:IsShown() and not open then frame:Hide() else frame:Show() end
end

function ns.WindowShown()
    return frame and frame:IsShown() or false
end

-- The combat note follows combat while the window is open.
ns.On("PLAYER_REGEN_DISABLED", Refresh)
ns.On("PLAYER_REGEN_ENABLED", Refresh)
-- What's on the bars and which page they show.
for _, event in ipairs({ "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR" }) do
    ns.On(event, function() ns.RequestRefresh() end)
end
