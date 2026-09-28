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

function ns.ShowOptionsMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return ns.ShowHelp() end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Keystance")
        if not ns.WindowShown() then
            root:CreateButton(L["Open Keystance"], OpenWindow)
        end
        root:CreateButton(L["Settings"], OpenOptions)
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
    if not ns.MinimapButtonOn() then b:Hide() end
end

-- EllesmereUI's minimap tray learns whether we want the button only from hooks on its Show
-- and Hide (EllesmereUIMinimap.lua, HideMinimapChild):
--  * SetShown doesn't reach those hooks, so a button hidden that way came back the next
--    time the tray rebuilt its grid (seen 2026-09-28);
--  * but while the tray's grid is open its Hide hook shows the button again at once.
-- So we hide with Hide() and, if the open grid undid it, try again every half second until
-- it sticks: the grid closes on the next click anywhere else. Without EllesmereUI the first
-- Hide() simply works.
local RETRIES, RETRY_WAIT = 40, 0.5
local retrying = false
local function EnsureHidden(tries)
    retrying = false
    if not mmButton or ns.MinimapButtonOn() or not mmButton:IsShown() then return end
    mmButton:Hide()
    if mmButton:IsShown() and tries < RETRIES then
        retrying = true
        C_Timer.After(RETRY_WAIT, function() EnsureHidden(tries + 1) end)
    end
end

-- EllesmereUI's tray puts a button back in its grid only when it rebuilds (after an addon
-- loads, or a reload); until then a shown button stays invisible (seen in game 2026-09-28,
-- and a reload brought it back). Its only rebuild hook for other addons would also re-show
-- buttons other addons have hidden, so we offer a reload instead.
local function EllesmereTray()
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("EllesmereUIMinimap") or false
end

function ns.SetMinimapButton(on)
    local was = ns.MinimapButtonOn()
    ns.db.settings.minimapHidden = not on or nil
    ns.CreateMinimapButton()
    if not mmButton then return end
    if on then
        mmButton:Show()
        if not was and EllesmereTray() then
            ns.AskReload(L["EllesmereUI's minimap tray shows the Keystance button again after the interface reloads. Reload now?"],
                L["Type /reload to see the minimap button again."])
        end
    elseif not retrying then
        EnsureHidden(0)
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
