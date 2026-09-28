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
local function MinimapSelected() return ns.MinimapButtonOn() end
local function ToggleMinimap() ns.SetMinimapButton(not ns.MinimapButtonOn()) end

function ns.ShowOptionsMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return ns.ShowHelp() end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Keystance")
        if not ns.WindowShown() then
            root:CreateButton(L["Open Keystance"], function() ns.ToggleWindow(true) end)
        end
        root:CreateButton(L["Settings"], function() ns.RunCommand("options") end)
        root:CreateCheckbox(L["Show minimap button"], MinimapSelected, ToggleMinimap)
        root:CreateButton(L["Memory use"], function() ns.RunCommand("mem") end)
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

function ns.CreateMinimapButton()
    if mmButton or not Minimap or not ns.MinimapButtonOn() then return end
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
        if button == "RightButton" then ns.ShowOptionsMenu(self) else ns.ToggleWindow() end
    end)
    b:SetScript("OnEnter", ButtonTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", FollowCursor) end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    mmButton = b
    Place(ns.db.settings.minimapAngle or DEFAULT_ANGLE)
end

function ns.SetMinimapButton(on)
    ns.db.settings.minimapHidden = not on or nil
    if on then ns.CreateMinimapButton() end
    if not mmButton then return end
    -- Show() and Hide(), never SetShown: EllesmereUI's minimap tray learns whether an addon
    -- wants its button from hooks on Show and Hide, and SetShown doesn't go through them
    -- (the button stayed in its tray after being hidden, 2026-09-28).
    if on then mmButton:Show() else mmButton:Hide() end
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
