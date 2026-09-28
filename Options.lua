-- Keystance settings: the controls shown on the window's Settings tab and on our page in
-- the game's Options > AddOns list (both built by ns.BuildSettings, so they never differ).
-- The Options page is a "canvas": Blizzard's panel only hosts our own frame. It uses none
-- of Blizzard's setting objects (RegisterProxySetting and friends), so our values never
-- run through Blizzard's secure settings code (a test keeps it that way). The page is
-- registered at login but only builds its contents the first time it's shown.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)
local L = ns.L

local ipairs, pcall, CreateFrame = ipairs, pcall, CreateFrame

local LOOK_NAMES = {
    auto = L["Automatic"], classic = L["Classic"], ellesmere = "EllesmereUI", elvui = "ElvUI",
}

local function Tooltip(owner, title, text)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title)
    if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
    GameTooltip:Show()
end

local function Button(owner, parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 200, 24)
    b:SetText(text)
    owner.buttons[#owner.buttons + 1] = b
    return b
end

local function Text(owner, parent, template, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    if text then fs:SetText(text) end
    owner.texts[#owner.texts + 1] = fs
    return fs
end

---------------------------------------------------------------------------
-- The controls
---------------------------------------------------------------------------
local pages = {} -- every built copy, so a change made in one shows in the other

local function RefreshPage(page)
    page.lookRow:Refresh()
    local inUse, chosen = ns.SkinName(), ns.SkinNameFor(ns.db.settings.skin)
    page.lookNote:SetText(inUse == chosen and L["In use: %s."]:format(LOOK_NAMES[inUse])
        or L["In use: %s until you reload."]:format(LOOK_NAMES[inUse]))
    page.minimap:SetText(ns.MinimapButtonOn() and L["Minimap button: shown"] or L["Minimap button: hidden"])
    local snap = ns.char and ns.char.snapshot
    page.snapshot:SetText(snap and L["Your bars and keys as they were before Keystance were saved on %s (%d slots, %d keys). You'll be able to put them back from here."]
        :format(date("%d %b %Y", snap.at), snap.nSlots, snap.nBinds)
        or L["Keystance saves your bars and keys as they are now, shortly after you log in, so you can always get them back."])
end

local function RefreshAll()
    for _, page in ipairs(pages) do
        if page:IsShown() then RefreshPage(page) end
    end
end
ns.RefreshSettings = RefreshAll

-- Asks to reload now. The pop-up is added to Blizzard's StaticPopupDialogs only the first
-- time it's needed, and never by assigning the global itself (that taints it).
-- ReloadUI works from a click (ElvUI's pop-ups do the same on this client); an addon
-- can't reload on its own, and if the game refuses, the player is told to type /reload.
local function AskReload()
    if not (StaticPopup_Show and StaticPopupDialogs) then return end
    if not StaticPopupDialogs.KEYSTANCE_RELOAD then
        StaticPopupDialogs.KEYSTANCE_RELOAD = {
            text = L["Keystance's new look shows after the interface reloads. Reload now?"],
            button1 = L["Reload now"],
            button2 = L["Later"],
            OnAccept = function()
                -- A refused call doesn't throw (it fires an event), so if we're still here a
                -- moment later, the reload didn't happen.
                C_Timer.After(1, function() ns.Print(L["Type /reload to see the new look."]) end)
                ReloadUI()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    StaticPopup_Show("KEYSTANCE_RELOAD")
end

-- Saves a look; if it differs from the one in use, offers to reload.
function ns.ChooseSkin(choice)
    if not ns.SetSkin(choice) then return false end
    if ns.SkinNameFor(choice) ~= ns.SkinName() then
        AskReload()
    else
        ns.Print(L["Look set to %s."]:format(LOOK_NAMES[choice]))
    end
    RefreshAll()
    return true
end

-- Builds the settings controls into `page`, below `top` (a region to sit under, or nil for
-- the page's top). Widgets are listed in owner.buttons and owner.texts for skinning.
function ns.BuildSettings(page, owner, top)
    local label = Text(owner, page, "GameFontNormal", L["Look"])
    if top then
        label:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -16)
    else
        label:SetPoint("TOPLEFT", 16, -16)
    end
    local row = ns.ChoiceRow(owner, page, {
        { "auto", LOOK_NAMES.auto }, { "classic", LOOK_NAMES.classic },
        { "ellesmere", LOOK_NAMES.ellesmere }, { "elvui", LOOK_NAMES.elvui },
    }, function() return ns.db.settings.skin end, ns.ChooseSkin, 96)
    row:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
    row.buttons[1]:SetScript("OnEnter", function(self)
        Tooltip(self, L["Automatic"], L["Matches EllesmereUI or ElvUI when you use one, and Blizzard's look otherwise."])
    end)
    row.buttons[1]:SetScript("OnLeave", function() GameTooltip:Hide() end)
    page.lookRow = row
    local note = Text(owner, page, "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -6)
    page.lookNote = note
    local minimap = Button(owner, page, "")
    minimap:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -14)
    minimap:SetScript("OnClick", function()
        ns.RunCommand("minimap")
        RefreshAll()
    end)
    page.minimap = minimap
    local snapshot = Text(owner, page, "GameFontHighlightSmall")
    snapshot:SetPoint("TOPLEFT", minimap, "BOTTOMLEFT", 0, -16)
    snapshot:SetWidth(460)
    snapshot:SetJustifyH("LEFT")
    page.snapshot = snapshot
    page.Refresh = RefreshPage
    pages[#pages + 1] = page
end

---------------------------------------------------------------------------
-- Our page in Options > AddOns
---------------------------------------------------------------------------
local category, canvas

-- Opens the window from the Options page. Blizzard's panel closes first and the window
-- opens a frame later (as EllesmereUI does), so nothing of ours runs inside its closing.
local function OpenWindowFromOptions()
    -- In combat Blizzard's panel is left alone (its panel code isn't ours to run then).
    if not InCombatLockdown() and SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
    C_Timer.After(0, function() ns.ToggleWindow(true) end)
end

local function BuildCanvas(f)
    f.buttons, f.texts = {}, {}
    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(56, 56)
    logo:SetPoint("TOPLEFT", 16, -16)
    logo:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\media\\logo.tga") -- the full badge, big enough here
    f.logo = logo
    local title = Text(f, f, "GameFontNormalLarge", "Keystance")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -4)
    local by = Text(f, f, "GameFontDisableSmall", L["Keybinds and action bars, by Kadmai"])
    by:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    local open = Button(f, f, L["Open Keystance"])
    open:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -16)
    open:SetScript("OnClick", OpenWindowFromOptions)
    f.open = open
    ns.BuildSettings(f, f, open)
    local help = Text(f, f, "GameFontHighlightSmall", L["Type /kst help for every command."])
    help:SetPoint("TOPLEFT", f.snapshot, "BOTTOMLEFT", 0, -16)
    for _, b in ipairs(f.buttons) do ns.SkinButton(b) end
    for _, fs in ipairs(f.texts) do ns.SkinText(fs) end
end

local function RegisterCanvas()
    if category or not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local f = CreateFrame("Frame", "KeystanceOptionsPanel")
    f:SetScript("OnShow", function(self)
        if not self.built then
            self.built = true
            BuildCanvas(self)
        end
        RefreshPage(self)
    end)
    local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, f, "Keystance")
    if not ok or not cat then return end
    if not pcall(Settings.RegisterAddOnCategory, cat) then return end
    category, canvas = cat, f
end

ns.On("PLAYER_LOGIN", RegisterCanvas)

-- Opens the game's Options at our page (falls back to the window's Settings tab).
function ns.OpenOptions()
    if category and Settings.OpenToCategory and pcall(Settings.OpenToCategory, category:GetID()) then return end
    ns.ToggleWindow(true)
    ns.ShowTab("settings")
end

function ns.OptionsPanel() return canvas end
