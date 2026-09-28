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
    eq(KeystanceMinimapButton, nil, "not even made")
    slash("minimap")
    eq(KeystanceMinimapButton:IsShown(), true, "turned back on: made now")
end)

test("hiding and showing the button goes through Hide and Show, which EllesmereUI's tray hooks", function()
    start(nil)
    local b = KeystanceMinimapButton
    local calls = {}
    local hide, show = b.Hide, b.Show
    b.Hide = function(self) calls[#calls + 1] = "Hide"; return hide(self) end
    b.Show = function(self) calls[#calls + 1] = "Show"; return show(self) end
    b.SetShown = function() error("SetShown skips EllesmereUI's Show/Hide hooks") end
    slash("minimap")
    slash("minimap")
    eq(table.concat(calls, ","), "Hide,Show")
    eq(b:IsShown(), true)
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
    slash("options")
    eq(KeystanceOptionsPanel.logo.texture, "Interface\\AddOns\\Keystance\\media\\logo.tga")
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
