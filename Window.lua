-- Keystance main window: tabs across the top (Profiles, Keyboard, Bars, Rules, Settings)
-- and a strip along the bottom: the profile in use (with "changed since saved" and Update),
-- Undo when there's something to undo, a button per profile to switch, and the combat note. Built the first time it's
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
---------------------------------------------------------------------------
-- The status strip: the profile in use, whether the bars and keys still match it, and a
-- button per profile. Worked out again only when bars, keys or profiles change (statusStale),
-- so redraws stay free of garbage.
---------------------------------------------------------------------------
local MAX_QUICK = 8
local statusStale = true

local function QuickTooltip(b)
    GameTooltip:SetOwner(b, "ANCHOR_TOP")
    GameTooltip:AddLine(b.profile)
    local key = ns.ProfileKey(b.profile)
    if key then GameTooltip:AddDoubleLine(L["Key"], key, 0.6, 0.6, 0.6, 1, 1, 1) end
    GameTooltip:AddLine(b.active and L["In use."] or L["Click to switch to it."], 0.6, 0.8, 1)
    GameTooltip:Show()
end

local function BuildStatus(f)
    local s = CreateFrame("Frame", nil, f)
    s:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 6)
    s:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 6)
    s:SetHeight(22)
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetSize(18, 18)
    s.icon:SetPoint("LEFT")
    s.text = Text(f, s, "GameFontNormal")
    s.text:SetPoint("LEFT", s.icon, "RIGHT", 6, 0)
    s.changed = Text(f, s, "GameFontNormalSmall", L["changed since saved"])
    s.changed:SetTextColor(1, 0.6, 0.2)
    s.changed:SetPoint("LEFT", s.text, "RIGHT", 8, 0)
    s.update = CreateFrame("Button", nil, s, "UIPanelButtonTemplate")
    s.update:SetSize(70, 20)
    s.update:SetPoint("LEFT", s.changed, "RIGHT", 6, 0)
    s.update:SetText(L["Update"])
    s.update:SetScript("OnClick", function()
        if ns.char and ns.char.active then ns.ConfirmUpdate(ns.char.active) end
    end)
    s.update:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Your bars or keys aren't as this profile saved them. Update saves them into it; applying it again puts the saved ones back."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    s.update:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.buttons[#f.buttons + 1] = s.update
    -- One button per profile, from the right.
    s.quickFrame = CreateFrame("Frame", nil, s)
    s.quickFrame:SetAllPoints()
    s.quick = {}
    for i = 1, MAX_QUICK do
        local b = CreateFrame("Button", nil, s.quickFrame)
        b:SetSize(20, 20)
        b:SetPoint("RIGHT", s.quickFrame, "RIGHT", -(i - 1) * 24, 0)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.ring = b:CreateTexture(nil, "OVERLAY")
        b.ring:SetPoint("TOPLEFT", -3, 3)
        b.ring:SetPoint("BOTTOMRIGHT", 3, -3)
        b.ring:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        b.ring:SetBlendMode("ADD")
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnClick", function(self) if self.profile then ns.ConfirmApply(self.profile) end end)
        b:SetScript("OnEnter", QuickTooltip)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        s.quick[i] = b
    end
    -- Undo, beside the profile buttons, when there's a change to undo (its tooltip says which).
    s.undo = CreateFrame("Button", nil, s.quickFrame, "UIPanelButtonTemplate")
    s.undo:SetSize(60, 20)
    s.undo:SetText(L["Undo"])
    s.undo:SetScript("OnClick", function() ns.Undo() end)
    s.undo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(self.label or L["Undo"])
        GameTooltip:AddLine(L["Puts back your bars, keys and gear as they were before it. Undo again to redo."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    s.undo:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.buttons[#f.buttons + 1] = s.undo
    f.status = s
end

local function SetIcon(tex, p)
    local icon, crop = ns.ProfileIcon(p)
    tex:SetTexture(icon)
    if crop then tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) else tex:SetTexCoord(0, 1, 0, 1) end
end

local function RefreshStatus()
    local s, c = frame.status, ns.char
    if not (statusStale and c) then return end
    statusStale = false
    local names = ns.ProfileNames()
    local p = c.active and c.profiles[c.active]
    if p then
        SetIcon(s.icon, p)
        s.icon:Show()
        s.text:SetText(L["In use: %s"]:format(c.active))
        local slots, keys = ns.CountChanges(p, "bars")
        local changed = slots + keys > 0
        s.changed:SetShown(changed)
        s.update:SetShown(changed)
    else
        s.icon:Hide()
        s.text:SetText(#names == 0 and L["No profiles yet"] or L["No profile in use"])
        s.changed:Hide()
        s.update:Hide()
    end
    s.text:ClearAllPoints()
    s.text:SetPoint("LEFT", p and s.icon or s, p and "RIGHT" or "LEFT", p and 6 or 0, 0)
    ns.RefreshGuide(frame) -- the next getting-started step (Guide.lua)
    local shown = 0
    for i, b in ipairs(s.quick) do
        local name = names[i]
        b.profile, b.active = name, name ~= nil and name == c.active
        if name then
            SetIcon(b.icon, c.profiles[name])
            b.ring:SetShown(b.active)
            b:Show()
            shown = i
        else
            b:Hide()
        end
    end
    local undo = ns.UndoLabel()
    s.undo.label = undo and L["Undo %s"]:format(undo)
    s.undo:SetShown(undo ~= nil)
    s.undo:ClearAllPoints()
    s.undo:SetPoint("RIGHT", s.quickFrame, "RIGHT", -shown * 24 - (shown > 0 and 6 or 0), 0)
end

-- Profiles changed (saved, applied, renamed, given an icon...): the strip is worked out again.
function ns.StatusStale() statusStale = true end

local function Refresh()
    if not frame or not frame:IsShown() then return end
    local combat = ns.InCombat()
    frame.combat:SetShown(combat)
    frame.status.quickFrame:SetShown(not combat) -- switching waits in combat; the note says so
    RefreshStatus()
    local page = frame.pages[frame.selected]
    if page and page.Refresh then page:Refresh() end
end
ns.RefreshWindow = Refresh

function ns.ProfilesChanged()
    statusStale = true
    Refresh()
end

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

    BuildStatus(f)

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

    ns.SkinWindow(f)
    f:SetScript("OnShow", function()
        statusStale = true
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
-- Bars and keys changing may make them differ from the profile in use (or match it again).
ns.On("ACTIONBAR_SLOT_CHANGED", function() statusStale = true end)
ns.On("UPDATE_BINDINGS", function()
    statusStale = true
    ns.RequestRefresh()
end)
