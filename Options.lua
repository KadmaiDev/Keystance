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
    page.minimapRow:Refresh()
    page.switcherRow:Refresh()
    page.messagesRow:Refresh()
    page.ranksRow:Refresh()
    local snap = ns.char and ns.char.snapshot
    page.snapshot:SetText(snap and L["Your bars and keys as they were before Keystance, saved %s (%d slots, %d keys). Restore puts them back; use it before uninstalling Keystance."]
        :format(date("%d %b %Y", snap.at), snap.nSlots, snap.nBinds)
        or L["Keystance saves your bars and keys as they are now, shortly after you log in, so you can always get them back."])
    local combat = ns.InCombat()
    page.restore:SetEnabled(snap ~= nil and not combat)
    local shared = ns.SharedKeybinds()
    page.ownKeys:SetShown(shared)
    page.ownKeysNote:SetShown(shared)
    page.ownKeys:SetEnabled(not combat)
    if page.help then
        -- Under the last thing shown, never behind a button.
        page.help:ClearAllPoints()
        page.help:SetPoint("TOPLEFT", shared and page.ownKeysNote or page.restore, "BOTTOMLEFT", 0, -16)
    end
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
    ns.Dialog("KEYSTANCE_RELOAD", {
        text = "%s",
        button1 = L["Reload now"],
        button2 = L["Later"],
        OnAccept = function()
            -- A refused call doesn't throw (it fires an event), so if we're still here a
            -- moment later, the reload didn't happen.
            C_Timer.After(1, ReloadLater)
            ReloadUI()
        end,
    })
    StaticPopup_Show("KEYSTANCE_RELOAD", message)
end

-- Saves a look; if it differs from the one in use, offers to reload.
function ns.ChooseSkin(choice)
    if not ns.SetSkin(choice) then return false end
    if ns.SkinNameFor(choice) ~= ns.SkinName() then
        ns.AskReload(L["Keystance's new look shows after the interface reloads. Reload now?"],
            L["Type /reload to see the new look."])
    else
        ns.Notify(L["Look set to %s."]:format(LOOK_NAMES[choice]))
    end
    RefreshAll()
    return true
end

-- Builds the settings controls into `page`, below `top` (a region to sit under, or nil for
-- the page's top), as a form: each setting's name in a left column and its choices lined up
-- to its right, a note under the choices where one helps. Widgets are listed in
-- owner.buttons and owner.texts for skinning.
local LABEL_WIDTH = 150

function ns.BuildSettings(page, owner, top)
    local form = CreateFrame("Frame", nil, page)
    if top then
        form:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -14)
    else
        form:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -16)
    end
    form:SetSize(650, 300)
    page.form = form
    local y = 0
    -- A setting's row: its name on the left, `control` to its right; `gap` below it.
    local function Row(name, control, gap)
        local label = Text(owner, form, "GameFontNormal", name)
        label:SetPoint("TOPLEFT", form, "TOPLEFT", 0, -y - 4)
        label:SetWidth(LABEL_WIDTH - 10)
        label:SetJustifyH("LEFT")
        control:SetPoint("TOPLEFT", form, "TOPLEFT", LABEL_WIDTH, -y)
        y = y + (gap or 30)
        return label
    end
    -- A small grey note under a row's choices.
    local function Note(text)
        local note = Text(owner, form, "GameFontDisableSmall", text)
        note:SetPoint("TOPLEFT", form, "TOPLEFT", LABEL_WIDTH, -y + 4)
        note:SetWidth(470)
        note:SetJustifyH("LEFT")
        y = y + 16
        return note
    end
    local function Hint(button, title, text)
        button:SetScript("OnEnter", function(self) Tooltip(self, title, text) end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- Look.
    local look = ns.ChoiceRow(owner, form, {
        { "auto", LOOK_NAMES.auto }, { "classic", LOOK_NAMES.classic },
        { "ellesmere", LOOK_NAMES.ellesmere }, { "elvui", LOOK_NAMES.elvui },
    }, function() return ns.db.settings.skin end, ns.ChooseSkin, 96)
    Row(L["Look"], look, 26)
    Hint(look.buttons[1], L["Automatic"], L["Matches EllesmereUI or ElvUI when you use one, and Blizzard's look otherwise."])
    page.lookRow = look
    page.lookNote = Note("")
    y = y + 6

    -- Minimap button.
    local minimap = ns.ChoiceRow(owner, form, { { true, L["Shown"], 80 }, { false, L["Hidden"], 80 } },
        function() return ns.MinimapButtonOn() end,
        function(on)
            ns.SetMinimapButton(on)
            RefreshAll()
        end)
    Row(L["Minimap button"], minimap)
    page.minimapRow = minimap

    -- The profile switcher on screen: off (default), on (movable) or locked.
    local switcher = ns.ChoiceRow(owner, form, { { "hidden", L["Off"], 80 }, { "shown", L["On"], 80 },
        { "locked", L["Locked"], 80 } },
        function() return ns.SwitcherMode() end,
        function(mode)
            ns.SetSwitcherMode(mode)
            RefreshAll()
        end)
    Row(L["Profile switcher"], switcher)
    Hint(switcher.buttons[1], L["Profile switcher"], L["A row of your profiles that stays on screen: click one to switch (in combat it switches when combat ends). On: drag it where you like. Locked: it stays put."])
    page.switcherRow = switcher

    -- Where everyday messages go (problems always go to chat).
    local messages = ns.ChoiceRow(owner, form, { { "screen", L["On screen"], 96 }, { "chat", L["Chat"], 80 },
        { "quiet", L["Off"], 80 } },
        function() return ns.MessagesMode() end,
        function(mode)
            ns.db.settings.messages = mode ~= "screen" and mode or nil
            RefreshAll()
        end)
    Row(L["Messages"], messages, 26)
    page.messagesRow = messages
    Hint(messages.buttons[1], L["Messages"], L["Where Keystance says what it did (a profile applied, gear put on, a key set). On screen: briefly, at the top of the screen. Chat: in your chat window. Off: not at all. Problems always go to chat."])
    Note(L["Problems, and answers to /kst commands, always go to chat."])
    y = y + 6

    -- New spell ranks: upgrade the bars (the rank in use until now) or leave them.
    local ranks = ns.ChoiceRow(owner, form, { { true, L["Upgrade my bars"], 130 }, { false, L["Leave them"], 100 } },
        function() return ns.RanksOn() end,
        function(on)
            ns.db.settings.ranksOff = not on or nil
            RefreshAll()
        end)
    Row(L["New spell ranks"], ranks, 26)
    page.ranksRow = ranks
    Note(L["A new rank replaces the one you were using; lower ranks you placed on purpose stay."])

    -- The original setup, and Restore.
    local line = form:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.1)
    line:SetPoint("TOPLEFT", form, "TOPLEFT", 0, -y - 6)
    line:SetSize(620, 1)
    y = y + 16
    local snapshot = Text(owner, form, "GameFontHighlightSmall")
    Row(L["Original setup"], snapshot, 0)
    snapshot:SetWidth(470)
    snapshot:SetJustifyH("LEFT")
    page.snapshot = snapshot
    local restore = Button(owner, form, L["Restore original setup"], 200)
    restore:SetPoint("TOPLEFT", snapshot, "BOTTOMLEFT", 0, -8)
    restore:SetScript("OnClick", function() ns.ConfirmRestore() end)
    page.restore = restore

    -- Own keybinds, while this character shares the account's.
    local ownKeys = Button(owner, form, L["Give this character its own keybinds"], 260)
    ownKeys:SetPoint("TOPLEFT", restore, "BOTTOMLEFT", 0, -14)
    ownKeys:SetScript("OnClick", function() ns.UseOwnKeybinds() end)
    page.ownKeys = ownKeys
    local ownKeysNote = Text(owner, form, "GameFontDisableSmall")
    ownKeysNote:SetPoint("TOPLEFT", ownKeys, "BOTTOMLEFT", 0, -4)
    ownKeysNote:SetWidth(470)
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
    f.help = Text(f, f, "GameFontHighlightSmall", L["Type /kst help for every command."]) -- placed by RefreshPage
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
    -- Blizzard's Options window isn't opened in combat: the window's Settings tab instead.
    if category and Settings.OpenToCategory and not ns.InCombat() then
        C_Timer.After(0, OpenCategory)
        return
    end
    ns.ToggleWindow(true)
    ns.ShowTab("settings")
end

