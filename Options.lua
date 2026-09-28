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
    page.snapshot:SetText(snap and L["Your bars and keys as they were before Keystance were saved on %s (%d slots, %d keys). Restore puts them back; before uninstalling Keystance, use it to get your original setup back."]
        :format(date("%d %b %Y", snap.at), snap.nSlots, snap.nBinds)
        or L["Keystance saves your bars and keys as they are now, shortly after you log in, so you can always get them back."])
    local combat = ns.InCombat()
    page.restore:SetEnabled(snap ~= nil and not combat)
    local shared = ns.SharedKeybinds and ns.SharedKeybinds()
    page.ownKeys:SetShown(shared)
    page.ownKeysNote:SetShown(shared)
    page.ownKeys:SetEnabled(not combat)
end

local function RefreshAll()
    for _, page in ipairs(pages) do
        if page:IsShown() then RefreshPage(page) end
    end
end
ns.RefreshSettings = RefreshAll

-- Asks to reload now, saying why (`message`); `later` is printed if the reload doesn't
-- happen. The pop-up is added to Blizzard's StaticPopupDialogs only the first time it's
-- needed, and never by assigning the global itself (that taints it). ReloadUI works from a
-- click (confirmed in game 2026-09-28); an addon can't reload on its own.
local laterText
local function ReloadLater() ns.Print(laterText) end
function ns.AskReload(message, later)
    if not (StaticPopup_Show and StaticPopupDialogs) then return ns.Print(later) end
    laterText = later
    if not StaticPopupDialogs.KEYSTANCE_RELOAD then
        StaticPopupDialogs.KEYSTANCE_RELOAD = {
            text = "%s",
            button1 = L["Reload now"],
            button2 = L["Later"],
            OnAccept = function()
                -- A refused call doesn't throw (it fires an event), so if we're still here a
                -- moment later, the reload didn't happen.
                C_Timer.After(1, ReloadLater)
                ReloadUI()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    StaticPopup_Show("KEYSTANCE_RELOAD", message)
end

-- Saves a look; if it differs from the one in use, offers to reload.
function ns.ChooseSkin(choice)
    if not ns.SetSkin(choice) then return false end
    if ns.SkinNameFor(choice) ~= ns.SkinName() then
        ns.AskReload(L["Keystance's new look shows after the interface reloads. Reload now?"],
            L["Type /reload to see the new look."])
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
    local restore = Button(owner, page, L["Restore original setup"])
    restore:SetPoint("TOPLEFT", snapshot, "BOTTOMLEFT", 0, -8)
    restore:SetScript("OnClick", function() ns.ConfirmRestore() end)
    page.restore = restore
    local ownKeys = Button(owner, page, L["Give this character its own keybinds"], 260)
    ownKeys:SetPoint("TOPLEFT", restore, "BOTTOMLEFT", 0, -16)
    ownKeys:SetScript("OnClick", function() ns.UseOwnKeybinds() end)
    page.ownKeys = ownKeys
    local ownKeysNote = Text(owner, page, "GameFontDisableSmall")
    ownKeysNote:SetPoint("TOPLEFT", ownKeys, "BOTTOMLEFT", 0, -4)
    ownKeysNote:SetWidth(460)
    ownKeysNote:SetJustifyH("LEFT")
    ownKeysNote:SetText(L["Recommended: your keybinds are shared by all your characters, so a profile's keys would change them everywhere. Nothing changes on screen, and your other characters keep theirs."])
    page.ownKeysNote = ownKeysNote
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
    -- Hidden until the Options window shows it: a new frame counts as shown, so without this
    -- the first visit fired no OnShow and the page stayed blank (found in Alts Forever).
    f:Hide()
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
-- It opens a frame later: from a menu's click the menu is still closing, and opening the
-- Options window inside that did nothing in game (Alts Forever, 2026-09-28). A failure
-- is reported to the error handler (BugGrabber shows it), not hidden.
local function OpenCategory()
    local ok, err = pcall(Settings.OpenToCategory, category:GetID())
    if not ok and geterrorhandler then geterrorhandler()(err) end
end

function ns.OpenOptions()
    if category and Settings.OpenToCategory then
        C_Timer.After(0, OpenCategory)
        return
    end
    ns.ToggleWindow(true)
    ns.ShowTab("settings")
end

function ns.OptionsPanel() return canvas end
