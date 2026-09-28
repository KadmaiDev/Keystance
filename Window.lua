-- Keystance main window: tabs across the top (Keyboard, Bars, Profiles, Rules, Settings)
-- and a header strip for the active profile and combat notes. Built the first time it's
-- opened and only refreshed while shown, so a closed window costs nothing.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)
local L = ns.L

local ipairs, pcall, CreateFrame = ipairs, pcall, CreateFrame

local WIDTH, HEIGHT = 720, 460
local frame

local TABS = {
    { key = "keyboard", name = L["Keyboard"], blurb = L["Your keyboard, showing what every key does. Coming soon."] },
    { key = "bars", name = L["Bars"], blurb = L["Your action bars and their keys. Coming soon."] },
    { key = "profiles", name = L["Profiles"], blurb = L["Save your bars and keys per role, and switch with one click. Coming soon."] },
    { key = "rules", name = L["Rules"], blurb = L["Switch profiles automatically when you equip a shield, a two-hander or a set. Coming soon."] },
    { key = "settings", name = L["Settings"] },
}

local LOOK_NAMES = {
    auto = L["Automatic"], classic = L["Classic"], ellesmere = "EllesmereUI", elvui = "ElvUI",
}

local function Tooltip(owner, title, text)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title)
    if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
    GameTooltip:Show()
end

local function Button(f, parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 160, 24)
    b:SetText(text)
    f.buttons[#f.buttons + 1] = b
    return b
end

local function Text(f, parent, template, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    if text then fs:SetText(text) end
    f.texts[#f.texts + 1] = fs
    return fs
end

---------------------------------------------------------------------------
-- Refresh: what the header and the open page show
---------------------------------------------------------------------------
local function RefreshSettings(page)
    page.look:SetText(L["Look: %s"]:format(LOOK_NAMES[ns.db.settings.skin] or ns.db.settings.skin))
    page.lookNote:SetText(L["In use now: %s. A change applies after /reload."]:format(LOOK_NAMES[ns.SkinName()]))
    page.minimap:SetText(ns.MinimapButtonOn() and L["Minimap button: shown"] or L["Minimap button: hidden"])
end

local function Refresh()
    if not frame or not frame:IsShown() then return end
    frame.combat:SetShown(ns.InCombat())
    local page = frame.pages[frame.selected]
    if page and page.Refresh then page:Refresh() end
end
ns.RefreshWindow = Refresh

local function SelectTab(i)
    frame.selected = i
    ns.db.settings.tab = TABS[i].key
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
local function LookMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(L["Look"])
        for _, choice in ipairs({ "auto", "classic", "ellesmere", "elvui" }) do
            root:CreateRadio(LOOK_NAMES[choice],
                function() return ns.db.settings.skin == choice end,
                function()
                    ns.SetSkin(choice)
                    ns.Print(L["Look set to %s. It applies after /reload."]:format(LOOK_NAMES[choice]))
                    Refresh()
                end)
        end
    end)
end

local function SettingsPage(f, page)
    local title = Text(f, page, "GameFontNormalLarge", L["Settings"])
    title:SetPoint("TOPLEFT", 16, -16)
    local look = Button(f, page, "", 200)
    look:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -16)
    look:SetScript("OnClick", LookMenu)
    look:SetScript("OnEnter", function(self)
        Tooltip(self, L["Look"], L["Automatic matches EllesmereUI or ElvUI when you use one, and Blizzard's look otherwise."])
    end)
    look:SetScript("OnLeave", function() GameTooltip:Hide() end)
    page.look = look
    local note = Text(f, page, "GameFontDisableSmall")
    note:SetPoint("LEFT", look, "RIGHT", 12, 0)
    page.lookNote = note
    local minimap = Button(f, page, "", 200)
    minimap:SetPoint("TOPLEFT", look, "BOTTOMLEFT", 0, -10)
    minimap:SetScript("OnClick", function()
        ns.RunCommand("minimap")
        Refresh()
    end)
    page.minimap = minimap
    page.Refresh = RefreshSettings
end

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
    combat:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -34)
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
        if info.blurb then
            local fs = Text(f, page, "GameFontHighlightMedium", info.blurb)
            fs:SetPoint("CENTER")
        end
        f.pages[i] = page
    end
    SettingsPage(f, f.pages[#TABS])

    f.credit = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.credit:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 10)
    f.credit:SetText(L["Keystance by Kadmai"])

    ns.SkinWindow(f)
    f:SetScript("OnShow", Refresh)
    -- Escape closes it, like Blizzard's own windows.
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "KeystanceFrame" end
    f:Hide()

    local first = 1
    for i, info in ipairs(TABS) do
        if info.key == ns.db.settings.tab then first = i end
    end
    SelectTab(first)
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
