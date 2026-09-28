-- Keystance minimap button (no library) and the minimap's addon compartment entry.
-- Click: open the window. Right-click: options menu. Drag: move around the minimap edge.
-- EllesmereUI's minimap collects named buttons on the minimap into its tray, so the button
-- is made as soon as our saved data loads, before that scan at login.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)
local L = ns.L

-- Our logo without its outer gold ring (media/minimap.tga): the ring around the button
-- comes from the minimap border or EllesmereUI's tray, and two rings show any small
-- misalignment between them. Built from the folder name, so the dev copy finds its own.
-- (The addon list uses the full logo, media/icon.tga, via the .toc.)
local ICON = "Interface\\AddOns\\" .. ADDON .. "\\media\\minimap.tga"
local DEFAULT_ANGLE = 200
local mmButton

---------------------------------------------------------------------------
-- Options menu (right-click on the button or the compartment entry)
---------------------------------------------------------------------------
-- Every menu action returns nothing: the menu reads a returned value as a MenuResponse,
-- and a true kept Alts Forever's menu open (2026-09-28). A test checks each one.
local function MinimapSelected() return ns.MinimapButtonOn() end
local function ToggleMinimap() ns.SetMinimapButton(not ns.MinimapButtonOn()) end
local function OpenWindow() ns.ToggleWindow(true) end
local function OpenOptions() ns.OpenOptions() end
local function ShowMemory() ns.RunCommand("mem") end
local function AutoSelected() return ns.AutoOn() end
local function ToggleAuto() ns.RunCommand("auto", ns.AutoOn() and "off" or "on") end

function ns.ShowOptionsMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return ns.ShowHelp() end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Keystance")
        if not ns.WindowShown() then
            root:CreateButton(L["Open Keystance"], OpenWindow)
        end
        root:CreateButton(L["Settings"], OpenOptions)
        root:CreateCheckbox(L["Switch profiles automatically"], AutoSelected, ToggleAuto)
        root:CreateCheckbox(L["Show minimap button"], MinimapSelected, ToggleMinimap)
        root:CreateButton(L["Memory use"], ShowMemory)
    end)
end

---------------------------------------------------------------------------
-- The button
---------------------------------------------------------------------------
function ns.MinimapButtonOn()
    return not ns.db.settings.minimapHidden
end

local function Place(angle)
    local rad = math.rad(angle)
    local radius = Minimap:GetWidth() / 2 + 10
    mmButton:ClearAllPoints()
    mmButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
end

-- Runs only while the button is being dragged.
local function FollowCursor()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    ns.db.settings.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
    Place(ns.db.settings.minimapAngle)
end

local function ButtonTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Keystance")
    GameTooltip:AddLine(L["Click: open Keystance"], 1, 1, 1)
    GameTooltip:AddLine(L["Right-click: options"], 1, 1, 1)
    GameTooltip:AddLine(L["Drag: move around the minimap"], 1, 1, 1)
    GameTooltip:Show()
end

-- Made at load even when the player has hidden it: EllesmereUI's minimap tray only collects
-- buttons that exist at its login scan, so one made later sat loose on the minimap.
function ns.CreateMinimapButton()
    if mmButton or not Minimap then return end
    local b = CreateFrame("Button", "KeystanceMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    -- Pinned to all four edges with an even margin, so it stays centred when EllesmereUI's
    -- minimap tray resizes the button.
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", b, "TOPLEFT", 4, -4)
    bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 4)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", b, "TOPLEFT", 5, -5)
    icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -5, 5)
    icon:SetTexture(ICON) -- round with transparent corners: no cropping needed
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b.icon = icon
    b:SetScript("OnClick", function(self, button)
        -- The menu belongs to UIParent, not the button: EllesmereUI's minimap tray hides
        -- itself (and this button) on any left press outside it, and a menu closes with its
        -- owner, so every click on the menu only closed it (found in Alts Forever,
        -- 2026-09-28). It opens at the cursor.
        if button == "RightButton" then ns.ShowOptionsMenu(UIParent) else ns.ToggleWindow() end
    end)
    b:SetScript("OnEnter", ButtonTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", FollowCursor) end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    mmButton = b
    Place(ns.db.settings.minimapAngle or DEFAULT_ANGLE)
    -- Hidden before EllesmereUI's scan, which then records it as not wanted.
    if not ns.MinimapButtonOn() then b:SetShown(false) end
end

-- Shown and hidden with SetShown, as Alts Forever does: EllesmereUI's minimap tray hooks
-- the button's Show and Hide, and those hooks fight us (Show from us made the button
-- invisible until the tray rebuilt; Hide while its grid was open was undone at once).
-- SetShown doesn't reach them, so the button appears and disappears right away. The tray
-- also keeps its own list of which buttons are wanted, which SetShown doesn't update, so a
-- hidden button came back whenever the tray rebuilt its grid (after opening Options). We
-- update that list too: EllesmereUI publishes it as _EBS_AddonVisible (for its own options
-- screen; unofficial, so only used when it's there and a table). Seen in game 2026-09-28.
local function TrayList()
    local list = _G._EBS_AddonVisible
    return type(list) == "table" and list or nil
end

-- True when EllesmereUI's tray manages our button: its scan recorded it in the list.
local function InTray()
    local list = TrayList()
    return list ~= nil and list[mmButton] ~= nil
end

-- Makes the tray lay its grid out again, now if it's open or else when it next opens, so a
-- button it left out (ours, when hidden at login) takes its place in the grid instead of
-- sitting loose on the minimap. _EMIN_RefreshFlyout is EllesmereUI's own (unofficial,
-- guarded), and it also shows every button in its grid, other addons' hidden ones
-- included, so those are put back exactly as they were afterwards.
local function RegridTray()
    local refresh, list = _G._EMIN_RefreshFlyout, TrayList()
    if type(refresh) ~= "function" or not list or InCombatLockdown() then return end
    local hidden = {}
    for btn, wanted in pairs(list) do
        if btn ~= mmButton and type(btn) == "table" and btn.IsShown and not btn:IsShown() then
            hidden[#hidden + 1] = { btn, wanted, btn:GetAlpha() }
        end
    end
    pcall(refresh)
    for _, h in ipairs(hidden) do
        local btn = h[1]
        if btn:IsShown() and not (btn.IsProtected and btn:IsProtected()) then btn:SetShown(false) end
        btn:SetAlpha(h[3])
        list[btn] = h[2]
    end
end

function ns.SetMinimapButton(on)
    ns.db.settings.minimapHidden = not on or nil
    ns.CreateMinimapButton()
    if not mmButton then return end
    if not InTray() then
        -- On the minimap itself (no EllesmereUI tray).
        mmButton:SetShown(on)
        if on then mmButton:SetAlpha(1) end
        return
    end
    TrayList()[mmButton] = on
    if on then
        -- The tray shows it, in its grid, when it lays the grid out.
        RegridTray()
    else
        mmButton:SetShown(false)
    end
end

---------------------------------------------------------------------------
-- Minimap addon compartment (functions named in the .toc)
---------------------------------------------------------------------------
function Keystance_OnAddonCompartmentClick(_, button, frame)
    if button == "RightButton" then
        ns.ShowOptionsMenu(frame)
    else
        ns.ToggleWindow()
    end
end

function Keystance_OnAddonCompartmentEnter(_, frame)
    GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
    GameTooltip:AddLine("Keystance")
    GameTooltip:AddLine(L["Click: open Keystance"], 1, 1, 1)
    GameTooltip:AddLine(L["Right-click: options"], 1, 1, 1)
    GameTooltip:Show()
end

function Keystance_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
