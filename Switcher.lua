-- Keystance profile switcher: an optional row of profile buttons that stays on screen (off
-- by default; Settings, the minimap menu or /kst switcher). A click switches to that
-- profile at once (no question: it's a quick switcher; Undo still works); in combat it
-- queues until combat ends, shown by a pulsing border, and another click changes or (on the
-- profile in use) cancels it. Right-click opens Keystance. It can be dragged anywhere while
-- "On", and "Locked" stops that. Built the first time it's shown; it works on events only.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)
local L = ns.L

local ipairs, pcall, CreateFrame, GetBindingKey = ipairs, pcall, CreateFrame, GetBindingKey

local SIZE, GAP, PAD = 28, 4, 5

local bar

local function Settings() return ns.db.settings end

-- "hidden" (default), "shown" (movable) or "locked".
function ns.SwitcherMode() return Settings().switcher or "hidden" end

---------------------------------------------------------------------------
-- The buttons
---------------------------------------------------------------------------
local function Tooltip(b)
    GameTooltip:SetOwner(b, "ANCHOR_TOP")
    GameTooltip:AddLine(b.profile)
    local key = ns.ProfileKey(b.profile)
    if key then GameTooltip:AddDoubleLine(L["Key"], key, 0.6, 0.6, 0.6, 1, 1, 1) end
    local c = ns.char
    if ns.pendingProfile == b.profile then
        GameTooltip:AddLine(L["Switches when combat ends. Click the profile in use to cancel."], 1, 0.82, 0, true)
    elseif c and c.active == b.profile then
        GameTooltip:AddLine(L["In use."], 0.6, 0.8, 1)
    else
        GameTooltip:AddLine(ns.InCombat() and L["Click: switch to it when combat ends."] or L["Click: switch to it."], 0.6, 0.8, 1)
    end
    GameTooltip:AddLine(L["Right-click: open Keystance."], 0.6, 0.8, 1)
    if ns.SwitcherMode() == "shown" then GameTooltip:AddLine(L["Drag to move it (lock it in Settings)."], 0.6, 0.8, 1) end
    GameTooltip:Show()
end

local function SavePosition()
    local point, _, relPoint, x, y = bar:GetPoint()
    if point then Settings().switcherPos = { point, relPoint, x, y } end
end

local function MakeButton(i)
    local b = CreateFrame("Button", nil, bar)
    b:SetSize(SIZE, SIZE)
    b:SetPoint("LEFT", bar, "LEFT", PAD + (i - 1) * (SIZE + GAP), 0)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    -- The profile in use.
    b.ring = b:CreateTexture(nil, "OVERLAY")
    b.ring:SetPoint("TOPLEFT", -4, 4)
    b.ring:SetPoint("BOTTOMRIGHT", 4, -4)
    b.ring:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    b.ring:SetBlendMode("ADD")
    -- Waiting for combat to end: a gold border that pulses (the game animates it, no Lua).
    b.queued = b:CreateTexture(nil, "OVERLAY", nil, 1)
    b.queued:SetPoint("TOPLEFT", -3, 3)
    b.queued:SetPoint("BOTTOMRIGHT", 3, -3)
    b.queued:SetColorTexture(1, 0.8, 0.1, 0.45)
    b.queued:SetBlendMode("ADD")
    local pulse = b.queued:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.2)
    fade:SetDuration(0.6)
    b.pulse = pulse
    b.key = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    b.key:SetPoint("BOTTOMRIGHT", -1, 2)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then return ns.ToggleWindow(true) end
        if self.profile then ns.SwitchTo(self.profile) end
    end)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function()
        if ns.SwitcherMode() == "shown" then bar:StartMoving() end
    end)
    b:SetScript("OnDragStop", function()
        bar:StopMovingOrSizing()
        SavePosition()
    end)
    b:SetScript("OnEnter", Tooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar.buttons[i] = b
    return b
end

local function Build()
    local ok, f = pcall(CreateFrame, "Frame", "KeystanceSwitcher", UIParent, "BackdropTemplate")
    if not ok then f = CreateFrame("Frame", "KeystanceSwitcher", UIParent) end
    bar = f
    f.buttons = {}
    if f.SetBackdrop then
        pcall(f.SetBackdrop, f, {
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        pcall(f.SetBackdropColor, f, 0.05, 0.05, 0.07, 0.8)
    end
    f:SetHeight(SIZE + PAD * 2)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    -- Its place is Keystance's to keep (settings.switcherPos), not the game's layout cache too.
    if f.SetDontSavePosition then pcall(f.SetDontSavePosition, f, true) end
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    local pos = Settings().switcherPos
    if pos then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, -220)
    end
    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.empty:SetPoint("CENTER")
    f.empty:SetText(L["No profiles yet"])
    ns.SkinWindow(f)
end

---------------------------------------------------------------------------
-- Keeping it current
---------------------------------------------------------------------------
-- In use and waiting, on the buttons as they are (combat starting or ending): no garbage.
local function RefreshState()
    if not (bar and bar:IsShown()) then return end
    local c = ns.char
    for _, b in ipairs(bar.buttons) do
        if b.profile then
            b.ring:SetShown(c ~= nil and c.active == b.profile)
            local waiting = ns.pendingProfile == b.profile
            b.queued:SetShown(waiting)
            if waiting then b.pulse:Play() else b.pulse:Stop() end
        end
    end
end

-- Everything: which profiles, their icons and keys (profiles changed), and whether it shows.
function ns.RefreshSwitcher()
    if ns.SwitcherMode() == "hidden" or not ns.char then
        if bar then bar:Hide() end
        return
    end
    if not bar then Build() end
    local names = ns.ProfileNames()
    for i, name in ipairs(names) do
        local b = bar.buttons[i] or MakeButton(i)
        b.profile = name
        local icon, crop = ns.ProfileIcon(ns.char.profiles[name])
        b.icon:SetTexture(icon)
        if crop then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else b.icon:SetTexCoord(0, 1, 0, 1) end
        local n = ns.ProfileSlot(name)
        local key = n and GetBindingKey(ns.ProfileSlotCommand(n))
        b.key:SetText(key and ns.ShortKey(key) or "")
        b:Show()
    end
    for i = #names + 1, #bar.buttons do
        bar.buttons[i].profile = nil
        bar.buttons[i]:Hide()
    end
    bar.empty:SetShown(#names == 0)
    bar:SetWidth(#names == 0 and 120 or (PAD * 2 + #names * SIZE + (#names - 1) * GAP))
    bar:Show()
    RefreshState()
end

-- Switches from the switcher: at once, or queued in combat. Clicking the profile in use
-- while another waits cancels the wait.
function ns.SwitchTo(name)
    local c = ns.char
    if not c then return end
    if ns.pendingProfile and name == c.active then return ns.CancelPendingProfile() end
    if name == c.active and not ns.pendingProfile then return ns.Notify(L["%s is in use."]:format(name)) end
    ns.ApplyProfile(name)
end

function ns.SetSwitcherMode(mode)
    Settings().switcher = mode ~= "hidden" and mode or nil
    ns.RefreshSwitcher()
    if ns.RefreshSettings then ns.RefreshSettings() end -- an open settings page follows
end

ns.On("PLAYER_LOGIN", function() ns.RefreshSwitcher() end)
ns.On("PLAYER_REGEN_DISABLED", RefreshState)
ns.On("PLAYER_REGEN_ENABLED", RefreshState)
-- Keys change in bursts (applying a profile sets many): the labels, once, a moment later.
local keysPending = false
local function RefreshKeys()
    keysPending = false
    if not (bar and bar:IsShown()) then return end
    for _, b in ipairs(bar.buttons) do
        if b.profile then
            local n = ns.ProfileSlot(b.profile)
            local key = n and GetBindingKey(ns.ProfileSlotCommand(n))
            b.key:SetText(key and ns.ShortKey(key) or "")
        end
    end
end
ns.On("UPDATE_BINDINGS", function()
    if keysPending or not (bar and bar:IsShown()) then return end
    keysPending = true
    C_Timer.After(0.1, RefreshKeys)
end)

ns.AddCommand("switcher", function(arg)
    arg = (arg or ""):lower()
    local mode = arg == "on" and "shown" or arg == "off" and "hidden" or arg == "lock" and "locked"
        or (ns.SwitcherMode() == "hidden" and "shown" or "hidden")
    ns.SetSwitcherMode(mode)
    ns.Print(mode == "hidden" and L["Profile switcher hidden. /kst switcher shows it again."]
        or mode == "locked" and L["Profile switcher shown and locked."]
        or L["Profile switcher shown: drag it where you like; /kst switcher lock locks it."])
    ns.RefreshWindow()
end)
