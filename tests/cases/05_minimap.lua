-- Tests: minimap button, addon compartment and options menu.
---------------------------------------------------------------------------
test("a minimap button is made as soon as saved data loads (before login)", function()
    wow.load(FILES)
    wow.fire("ADDON_LOADED", "Keystance")
    local b = KeystanceMinimapButton
    assert(b, "made before PLAYER_LOGIN, so EllesmereUI's minimap can collect it")
    wow.fire("PLAYER_LOGIN")
    b.scripts.OnClick(b, "LeftButton")
    eq(KeystanceFrame:IsShown(), true)
    b.scripts.OnClick(b, "RightButton")
    eq(wow.menu.items[1].text, "Keystance", "right-click: options menu")
    eq(wow.menu.owner, UIParent, "not the button: EllesmereUI's tray hides it on a click, closing the menu")
    b.scripts.OnEnter(b)
    eq(GameTooltip.lines[1][1], "Keystance")
end)

test("dragging moves the button around the minimap edge, and the position is kept", function()
    start(nil)
    local b = KeystanceMinimapButton
    b.scripts.OnDragStart(b)
    assert(b.scripts.OnUpdate, "follows the cursor while dragging")
    wow.mouse = { 1100, 600 } -- straight right of the minimap's centre
    b.scripts.OnUpdate(b)
    eq(KeystanceDB.settings.minimapAngle, 0)
    eq(b.point[4], 80); eq(b.point[5], 0, "on the edge: radius 70 + 10")
    b.scripts.OnDragStop(b)
    eq(b.scripts.OnUpdate, nil, "nothing runs once dropped")
end)

test("the minimap button can be hidden from the menu, and stays hidden next session", function()
    start(nil)
    Keystance_OnAddonCompartmentClick("Keystance", "RightButton", UIParent)
    local box = wow.menuItem("Show minimap button")
    eq(box.isSelected(), true)
    box.setSelected()
    eq(KeystanceMinimapButton:IsShown(), false)
    eq(KeystanceDB.settings.minimapHidden, true)
    local saved = KeystanceDB
    start(saved)
    eq(KeystanceMinimapButton:IsShown(), false, "made hidden")
    slash("minimap")
    eq(KeystanceMinimapButton:IsShown(), true, "turned back on")
end)

-- EllesmereUI's tray, as its code behaves: hooks on Show and Hide that fight us (Show
-- fades the button to alpha 0 while its grid is closed; Hide while the grid is open shows
-- it again), and its published list of wanted buttons, _EBS_AddonVisible.
function ellesmereTray(b)
    local tray = { open = false }
    _EBS_AddonVisible = {}
    local show, hide = b.Show, b.Hide
    b.Show = function(self)
        show(self)
        _EBS_AddonVisible[self] = true
        if not tray.open then self:SetAlpha(0) end
    end
    b.Hide = function(self)
        hide(self)
        if tray.open then show(self) else _EBS_AddonVisible[self] = false end
    end
    return tray
end

test("with EllesmereUI's tray, hiding and showing work at once, grid open or not", function()
    start(nil)
    local b = KeystanceMinimapButton
    local tray = ellesmereTray(b)
    for _, open in ipairs({ true, false }) do
        tray.open = open
        slash("minimap")
        eq(b:IsShown(), false, "hidden at once")
        eq(_EBS_AddonVisible[b], false, "the tray's list says not wanted, so a rebuild won't bring it back")
        b:SetAlpha(0) -- a rebuild while it's hidden tucks it away (HideMinimapChild)
        slash("minimap")
        eq(b:IsShown(), true, "shown at once")
        eq(b:GetAlpha(), 1, "and visible, with no reload")
        eq(_EBS_AddonVisible[b], true)
    end
    eq(wow.popup, nil, "never asks to reload")
end)

test("without EllesmereUI, the button just hides and shows", function()
    start(nil)
    slash("minimap")
    eq(KeystanceMinimapButton:IsShown(), false)
    slash("minimap")
    eq(KeystanceMinimapButton:IsShown(), true)
    eq(wow.popup, nil)
end)

test("a hidden button is still made at load (hidden), so EllesmereUI's tray collects it", function()
    wow.load(FILES)
    KeystanceDB = { v = 1, settings = { minimapHidden = true }, chars = {} }
    wow.fire("ADDON_LOADED", "Keystance")
    assert(KeystanceMinimapButton, "made before the tray's login scan")
    eq(KeystanceMinimapButton:IsShown(), false)
end)

test("the addon compartment entry opens the window, and its tooltip says how", function()
    start(nil)
    Keystance_OnAddonCompartmentClick("Keystance", "LeftButton", UIParent)
    eq(KeystanceFrame:IsShown(), true)
    Keystance_OnAddonCompartmentEnter("Keystance", UIParent)
    eq(GameTooltip.lines[1][1], "Keystance")
    Keystance_OnAddonCompartmentLeave()
    eq(GameTooltip:IsShown(), false)
end)

test("the options menu offers to open Keystance only while it's closed", function()
    start(nil)
    Keystance_OnAddonCompartmentClick("Keystance", "RightButton", UIParent)
    wow.menuItem("Open Keystance").fn()
    eq(KeystanceFrame:IsShown(), true)
    Keystance_OnAddonCompartmentClick("Keystance", "RightButton", UIParent)
    eq(wow.menuItem("Open Keystance"), nil)
end)

test("the minimap button and addon list use our logo, shipped with the addon", function()
    start(nil)
    eq(KeystanceMinimapButton.icon.texture, "Interface\\AddOns\\Keystance\\media\\minimap.tga")
    local toc = readFile("Keystance.toc")
    assert(toc:find("## IconTexture: Interface\\AddOns\\Keystance\\media\\icon.tga", 1, true), "addon list icon")
    for file, size in pairs({ ["media/icon.tga"] = 64, ["media/minimap.tga"] = 64, ["media/logo.tga"] = 128 }) do
        -- Uncompressed 32-bit TGA with a power-of-two size: what the game loads.
        local header = readFile(file):sub(1, 18)
        eq(header:byte(3), 2, file .. " uncompressed")
        eq(header:byte(13) + header:byte(14) * 256, size, file .. " width")
        eq(header:byte(15) + header:byte(16) * 256, size, file .. " height")
        eq(header:byte(17), 32, file .. " 32-bit")
    end
end)

test("the Options page shows the full logo, not the small icon stretched", function()
    start(nil)
    openOptions()
    eq(KeystanceOptionsPanel.logo.texture, "Interface\\AddOns\\Keystance\\media\\logo.tga")
end)

test("no menu action returns a value (the menu would read it as a response and stay open)", function()
    start(nil)
    Keystance_OnAddonCompartmentClick("Keystance", "RightButton", UIParent)
    local n = 0
    for _, item in ipairs(wow.menu.items) do
        local fn = item.kind == "checkbox" and item.setSelected or item.kind == "button" and item.fn
        if fn then
            n = n + 1
            eq(select("#", fn()), 0, item.text)
        end
    end
    assert(n >= 3, "checked the buttons and the checkbox")
end)

test("every menu option has a slash command listed in /kst help", function()
    start(nil)
    slash("help")
    -- Settings: /kst options; Show minimap button: /kst minimap; Memory use: /kst mem; Open: /kst.
    assert(printed():find("options", 1, true))
    assert(printed():find("minimap", 1, true))
    assert(printed():find("mem", 1, true))
    assert(printed():find("/kst opens Keystance", 1, true))
end)
