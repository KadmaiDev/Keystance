-- Keystance Profiles tab: the character's profiles, each with its key (click, then press
-- the key that switches to it), Apply, Gear, Update, Rename, Copy and Delete; New profile from the current setup; Undo; Restore original setup; and,
-- while the character shares the account's keybinds, a note with the one-click switch.
-- Anything that would change bars or keys is greyed out in combat. A profile's Gear button
-- swaps the list for its gear editor (GearTab.lua) until Back.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)
local L = ns.L

local ipairs, pairs, pcall, CreateFrame = ipairs, pairs, pcall, CreateFrame
local IsAltKeyDown, IsControlKeyDown, IsShiftKeyDown = IsAltKeyDown, IsControlKeyDown, IsShiftKeyDown

local ROWS, ROW_HEIGHT = 6, 34
local TEXT_WIDTH = 160 -- a row's text stops short of its buttons (cut off, never under them)
local ICON = 26
local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true, UNKNOWN = true }

---------------------------------------------------------------------------
-- Setting a profile's key: click its key button, press a key (Esc cancels)
---------------------------------------------------------------------------
-- The pressed key with the modifiers held, in the game's order ("ALT-CTRL-SHIFT-Q").
local function FullKey(key)
    return (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
        .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
end

local function StopCapture(page)
    if not page.capturing then return end
    page.capturing = nil
    page.catcher:EnableKeyboard(false)
    if page.catcher.EnableGamePadButton then pcall(page.catcher.EnableGamePadButton, page.catcher, false) end
    page.catcher:Hide()
    ns.RefreshWindow()
end

local function StartCapture(page, name)
    if ns.InCombat() then return ns.Print(L["Not in combat: try again when combat ends."]) end
    page.capturing = name
    page.catcher:Show()
    page.catcher:EnableKeyboard(true)
    if page.catcher.EnableGamePadButton then pcall(page.catcher.EnableGamePadButton, page.catcher, true) end
    ns.RefreshWindow()
end

local function Pressed(page, key)
    local name = page.capturing
    StopCapture(page)
    if name then ns.SetProfileKey(name, FullKey(key)) end
end

-- With the account's shared keybinds, a key set here would be every character's: the
-- character gets its own keybinds first (owner's decision: ask).
local capturePage
local function AskCapture(page, name)
    if not ns.SharedKeybinds() then return StartCapture(page, name) end
    capturePage = page
    if not StaticPopupDialogs.KEYSTANCE_PROFILE_KEY then
        StaticPopupDialogs.KEYSTANCE_PROFILE_KEY = {
            text = L["Your keybinds are shared by all your characters, so a key set here would change them for everyone.\n\nGive this character its own keybinds first? Nothing changes on screen, and your other characters keep theirs."],
            button1 = L["Own keybinds"],
            button2 = CANCEL or "Cancel",
            OnAccept = function(_, data)
                ns.UseOwnKeybinds()
                if capturePage then StartCapture(capturePage, data) end
            end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
    end
    StaticPopup_Show("KEYSTANCE_PROFILE_KEY", nil, nil, name)
end

local function KeyTooltip(b)
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["Key for %s"]:format(b.profile or ""))
    GameTooltip:AddLine(L["Click, then press the key (with Shift, Ctrl or Alt if you like) that switches to this profile. Esc cancels; right-click takes the key off."], 1, 1, 1, true)
    GameTooltip:Show()
end

-- Apply from the tab: says what will change first (the shared-keybinds question covers it).
function ns.ConfirmApply(name)
    local c = ns.char
    local key = ns.FindProfile(name)
    if not (c and key) then return end
    local slots, keys = ns.CountChanges(c.profiles[key], "bars")
    local gear = ns.ProfileGearChanges(c.profiles[key])
    if slots + keys + gear == 0 then return ns.Notify(L["%s is already in place."]:format(key)) end
    if keys > 0 and ns.SharedKeybinds() then return ns.AskSharedKeybinds(key) end
    if not StaticPopupDialogs.KEYSTANCE_APPLY then
        StaticPopupDialogs.KEYSTANCE_APPLY = {
            text = L["Apply %s? %s will change. You can undo it."],
            button1 = L["Apply"],
            button2 = CANCEL or "Cancel",
            OnAccept = function(_, data) ns.ApplyProfile(data, nil, true) end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
    end
    local parts = {}
    if slots > 0 then parts[#parts + 1] = L["%d slots"]:format(slots) end
    if keys > 0 then parts[#parts + 1] = L["%d keys"]:format(keys) end
    if gear > 0 then parts[#parts + 1] = L["your gear"] end
    local what = #parts == 1 and parts[1] or (table.concat(parts, ", ", 1, #parts - 1) .. L[" and "] .. parts[#parts])
    StaticPopup_Show("KEYSTANCE_APPLY", key, what, key)
end

local function Button(f, parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    f.buttons[#f.buttons + 1] = b
    return b
end

local function Text(f, parent, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    f.texts[#f.texts + 1] = fs
    return fs
end

local function MakeRow(page, f, i)
    local row = CreateFrame("Frame", nil, page.list)
    row:SetSize(680, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -112 - (i - 1) * ROW_HEIGHT)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0.06)
    -- The profile's icon: click to choose another (IconPicker.lua).
    local icon = CreateFrame("Button", nil, row)
    icon:SetSize(ICON, ICON)
    icon:SetPoint("LEFT", 6, 0)
    icon.tex = icon:CreateTexture(nil, "ARTWORK")
    icon.tex:SetAllPoints()
    icon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    icon:SetScript("OnClick", function(self) ns.PickProfileIcon(row.profile, self) end)
    icon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Click to choose this profile's icon."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.icon = icon
    local name = Text(f, row, "GameFontNormal")
    name:SetPoint("TOPLEFT", ICON + 12, -4)
    name:SetWidth(TEXT_WIDTH)
    name:SetWordWrap(false)
    name:SetJustifyH("LEFT")
    row.name = name
    local detail = Text(f, row, "GameFontDisableSmall")
    detail:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
    detail:SetWidth(TEXT_WIDTH)
    detail:SetJustifyH("LEFT")
    detail:SetWordWrap(false)
    row.detail = detail
    local x = -4
    local function RowButton(text, width, fn)
        local b = Button(f, row, text, width, function() fn(row.profile) end)
        b:SetPoint("RIGHT", row, "RIGHT", x, 0)
        x = x - width - 4
        return b
    end
    row.delete = RowButton(L["Delete"], 60, ns.ConfirmDelete)
    row.copy = RowButton(L["Copy"], 56, ns.AskDuplicate)
    row.rename = RowButton(L["Rename"], 64, ns.AskRename)
    row.update = RowButton(L["Update"], 64, ns.ConfirmUpdate)
    row.gear = RowButton(L["Gear"], 56, function(name) ns.ShowGear(page, name) end)
    row.apply = RowButton(L["Apply"], 64, ns.ConfirmApply)
    row.key = RowButton("", 84, function() end)
    row.key:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.key:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            StopCapture(page)
            return ns.ClearProfileKey(row.profile)
        end
        if page.capturing == row.profile then return StopCapture(page) end
        AskCapture(page, row.profile)
    end)
    row.key:SetScript("OnEnter", function(self)
        self.profile = row.profile
        KeyTooltip(self)
    end)
    row.key:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.update:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Update"])
        GameTooltip:AddLine(L["Replace this profile with your bars and keys as they are now."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row.update:SetScript("OnLeave", function() GameTooltip:Hide() end)
    for _, b in ipairs({ row.delete, row.copy, row.rename, row.update, row.gear, row.apply, row.key }) do
        ns.SkinButton(b)
    end
    ns.SkinText(name)
    ns.SkinText(detail)
    return row
end

-- A grey note after a profile's name: its gear ("ItemRack: Tank" or "12 items"), or "".
local function Note(p)
    local parts = {}
    local kind, data = ns.ProfileGear(p)
    if kind == "itemrack" then
        parts[#parts + 1] = L["ItemRack: %s"]:format(data)
    elseif kind == "items" then
        local n = 0
        for _ in pairs(data) do n = n + 1 end
        parts[#parts + 1] = L["%d items"]:format(n)
    end
    if #parts == 0 then return "" end
    return "  |cff9d9d9d" .. table.concat(parts, "  ·  ") .. "|r"
end

-- Shows a profile's gear editor in place of the list (nil: back to the list).
local profilesPage
function ns.ShowGear(page, name)
    page.gearFor, page.guideOpen = name, nil
    if name and not page.gearView then
        page.gearView = CreateFrame("Frame", nil, page)
        page.gearView:SetAllPoints()
        ns.BuildGearView(page.gearView, page.window, function() ns.ShowGear(page, nil) end)
    end
    ns.RefreshWindow()
end

-- The gear editor for a profile, from elsewhere (the guide).
function ns.ShowGearFor(name)
    if profilesPage then ns.ShowGear(profilesPage, name) end
end

-- Every getting-started step, in place of the list (Guide.lua).
function ns.ShowGuideSteps()
    ns.ToggleWindow(true)
    ns.ShowTab("profiles")
    local page = profilesPage
    if not page then return end
    page.guideOpen, page.gearFor = true, nil
    if not page.guideView then
        page.guideView = CreateFrame("Frame", nil, page)
        page.guideView:SetAllPoints()
        ns.BuildGuideView(page.guideView, page.window, function()
            page.guideOpen = nil
            ns.RefreshWindow()
        end)
    end
    ns.RefreshWindow()
end

local function Refresh(page)
    local c = ns.char
    if not c then return end
    local gearFor = page.gearFor and ns.FindProfile(page.gearFor)
    page.gearFor = gearFor
    local guide = page.guideOpen and not gearFor
    page.list:SetShown(not gearFor and not guide)
    if page.gearView then page.gearView:SetShown(gearFor ~= nil) end
    if page.guideView then page.guideView:SetShown(guide or false) end
    if guide then return ns.RefreshGuideView(page.guideView) end
    if gearFor then return ns.RefreshGearView(page.gearView, gearFor) end
    local combat = ns.InCombat()
    page.title:SetText(L["Profiles for %s"]:format(ns.charKey or "?"))
    page.shared:SetShown(ns.SharedKeybinds())
    page.ownKeys:SetShown(ns.SharedKeybinds())
    page.ownKeys:SetEnabled(not combat)
    page.restore:SetEnabled(c.snapshot ~= nil and not combat)
    local names = ns.ProfileNames()
    for i = 1, ROWS do
        local row = page.rows[i]
        local name = names[i]
        if name then
            if not row then
                row = MakeRow(page, page.window, i)
                page.rows[i] = row
            end
            local p = c.profiles[name]
            row.profile = name
            row.name:SetText((name == c.active and ("|cff55ff55" .. name .. "|r") or name) .. Note(p))
            local icon, crop = ns.ProfileIcon(p)
            row.icon.tex:SetTexture(icon)
            if crop then row.icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) else row.icon.tex:SetTexCoord(0, 1, 0, 1) end
            local key = ns.ProfileKey(name)
            row.key:SetText(page.capturing == name and ("|cff66ccff" .. L["Press a key"] .. "|r")
                or key or ("|cff9d9d9d" .. L["Set key"] .. "|r"))
            row.key:SetEnabled(not combat)
            row.detail:SetText(L["%d slots, %d keys, saved %s"]:format(p.nSlots or 0, p.nBinds or 0,
                date("%d %b", p.updated or p.created or 0)))
            row.apply:SetEnabled(not combat)
            row:Show()
        elseif row then
            row:Hide()
        end
    end
    page.empty:SetShown(#names == 0)
    page.more:SetShown(#names > ROWS)
    if #names > ROWS then
        page.more:SetText(L["and %d more: /kst profiles lists them, /kst apply Name applies one."]:format(#names - ROWS))
    end
end

local function Build(page, f)
    page.window, page.rows = f, {}
    profilesPage = page
    local list = CreateFrame("Frame", nil, page)
    list:SetAllPoints()
    page.list = list
    local title = Text(f, list, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    page.title = title
    -- The steps for new players (Guide.lua); the profile in use is in the window's strip.
    page.guide = Button(f, list, L["Getting started"], 130, function() ns.ShowGuideSteps() end)
    page.guide:SetPoint("TOPRIGHT", page, "TOPRIGHT", -16, -10)

    page.new = Button(f, list, L["New profile from current setup"], 230, function() ns.NewProfile() end)
    page.new:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    -- Undo is on the window's strip, shown when there's something to undo (Window.lua).
    page.restore = Button(f, list, L["Restore original setup"], 190, function() ns.ConfirmRestore() end)
    page.restore:SetPoint("LEFT", page.new, "RIGHT", 8, 0)
    page.restore:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Restore original setup"])
        GameTooltip:AddLine(L["Puts your bars and every keybind back as they were before Keystance. Before uninstalling Keystance, click this to get your original setup back."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    page.restore:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local shared = Text(f, list, "GameFontHighlightSmall")
    shared:SetPoint("TOPLEFT", page.new, "BOTTOMLEFT", 0, -12)
    shared:SetWidth(430)
    shared:SetJustifyH("LEFT")
    shared:SetText(L["Your keybinds are shared by all your characters. Give this character its own, so profiles change only its keys."])
    page.shared = shared
    page.ownKeys = Button(f, list, L["Give it its own keybinds"], 200, function() ns.UseOwnKeybinds() end)
    page.ownKeys:SetPoint("LEFT", shared, "RIGHT", 12, 0)

    local empty = Text(f, list, "GameFontHighlight")
    empty:SetPoint("TOP", page, "TOP", 0, -140)
    empty:SetWidth(520)
    empty:SetText(L["No profiles yet. Set up your bars and keys the way you like them for a role, then click New profile from current setup."])
    page.empty = empty
    local more = Text(f, list, "GameFontDisableSmall")
    more:SetPoint("TOPLEFT", page, "TOPLEFT", 24, -112 - ROWS * ROW_HEIGHT - 6)
    page.more = more
    -- Takes the key press while a profile's key is being set.
    local catcher = CreateFrame("Frame", nil, list)
    catcher:SetAllPoints()
    catcher:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then return StopCapture(page) end
        if MODIFIER_KEYS[key] then return end
        Pressed(page, key)
    end)
    catcher:SetScript("OnGamePadButtonDown", function(_, button) Pressed(page, button) end)
    -- Setting a key handler switches the frame's keyboard on (in game), so it's switched off
    -- after, and the frame stays hidden unless it's waiting for a key: a shown catcher took
    -- every key (Esc, Enter...) while the window was open (2026-09-28).
    catcher:EnableKeyboard(false)
    if catcher.EnableGamePadButton then pcall(catcher.EnableGamePadButton, catcher, false) end
    catcher:Hide()
    page.catcher = catcher
    page:HookScript("OnHide", function() StopCapture(page) end)
    ns.On("PLAYER_REGEN_DISABLED", function() StopCapture(page) end)
    page.Refresh = Refresh
end

ns.pageBuilders.profiles = Build
