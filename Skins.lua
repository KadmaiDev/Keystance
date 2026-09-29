-- Keystance looks. Every widget is styled through here, so the window matches the
-- player's UI:
--  * EllesmereUI (with its third-party skinning on for us): through its public skinning API
--    (EllesmereUI/SKINNING_API.md), kept in sync by EllesmereUI when they change theme.
--  * ElvUI: through its Skins module, the helpers ElvUI uses on Blizzard's own windows.
--  * Classic: Blizzard's templates, untouched.
-- The setting (ns.db.settings.skin) is "auto" (EllesmereUI, then ElvUI, then classic) or a
-- fixed choice; a choice whose addon isn't running falls back to classic. The look is
-- fixed when the window is first built, so a change applies after /reload.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)

local ipairs, select, pcall, type = ipairs, select, pcall, type

local euiSkin -- EllesmereUI's skinning facade, once it hands it to us

-- ElvUI's engine and Skins module, once ElvUI has initialised (it does at login, before
-- our window can be opened).
local elvS
local function Elv()
    if elvS then return elvS end
    local engine = _G.ElvUI
    local E = type(engine) == "table" and engine[1]
    if type(E) ~= "table" or not E.Initialized or type(E.GetModule) ~= "function" then return nil end
    local ok, S = pcall(E.GetModule, E, "Skins", true)
    if not (ok and type(S) == "table" and S.HandleFrame) then return nil end
    elvS = S
    return S
end

local CHOICES = { auto = true, classic = true, ellesmere = true, elvui = true }

-- The setting as it was when first read this session: a change waits for /reload, so one
-- window never mixes two looks.
local choice
local function Choice()
    return choice or "auto"
end
-- Core's handler runs first, so the saved data is ready.
ns.On("ADDON_LOADED", function(name)
    if name == ADDON then choice = ns.db.settings.skin end
end)

-- The look a setting gives with the UI addons running now: "ellesmere", "elvui" or "classic".
function ns.SkinNameFor(want)
    if (want == "auto" or want == "ellesmere") and euiSkin then return "ellesmere" end
    if (want == "auto" or want == "elvui") and Elv() then return "elvui" end
    return "classic"
end

-- The look in use this session.
function ns.SkinName()
    return ns.SkinNameFor(Choice())
end

function ns.SetSkin(choice)
    if not CHOICES[choice] then return false end
    ns.db.settings.skin = choice
    return true
end

-- ElvUI's font and outline at the text's own size (our layout is sized for it).
local function ElvFont(fs)
    if not fs.FontTemplate then return end
    local size = fs.GetFont and select(2, fs:GetFont())
    fs:FontTemplate(nil, type(size) == "number" and size or nil)
end

local function EachFontString(frame, fn)
    for i = 1, select("#", frame:GetRegions()) do
        local region = select(i, frame:GetRegions())
        if region and region.GetObjectType and region:GetObjectType() == "FontString" then fn(region) end
    end
end

-- EllesmereUI's skin functions, guarded like ElvUI's: an error in one must never stop our
-- window from opening (its API is public, but a mistake there shouldn't cost us the window).
local function Eui(fn, obj)
    if type(fn) == "function" then pcall(fn, obj) end
end

-- Text in the player's chosen font. A no-op in the classic look.
function ns.SkinText(fs)
    if not fs then return end
    local look = ns.SkinName()
    if look == "ellesmere" then
        Eui(euiSkin.Font, fs)
    elseif look == "elvui" then
        pcall(ElvFont, fs)
    end
end

-- A push button (UIPanelButtonTemplate).
function ns.SkinButton(b)
    if not b then return end
    local look = ns.SkinName()
    if look == "ellesmere" then
        Eui(euiSkin.Button, b)
        Eui(euiSkin.StateButtonLabel, b)
    elseif look == "elvui" then
        pcall(elvS.HandleButton, elvS, b)
    end
end

-- A tab along the top of the window.
function ns.SkinTab(tab)
    if not tab then return end
    local look = ns.SkinName()
    if look == "ellesmere" then
        Eui(euiSkin.Tab, tab)
    elseif look == "elvui" then
        pcall(elvS.HandleTab, elvS, tab)
    end
end

-- A whole window: themed backdrop and border, its close button and inset, its own text,
-- and the widgets it lists in f.buttons, f.tabs and f.texts (inside its pages). Widgets
-- made later call the functions above themselves.
local windows = {}
local function SkinParts(f)
    for _, b in ipairs(f.buttons or {}) do ns.SkinButton(b) end
    for _, t in ipairs(f.tabs or {}) do ns.SkinTab(t) end
    for _, fs in ipairs(f.texts or {}) do ns.SkinText(fs) end
end
function ns.SkinWindow(f)
    if not f then return end
    local seen = false
    for _, w in ipairs(windows) do if w == f then seen = true end end
    if not seen then windows[#windows + 1] = f end
    local look = ns.SkinName()
    if look == "ellesmere" then
        Eui(euiSkin.Shell, f)
        if f.CloseButton then Eui(euiSkin.CloseButton, f.CloseButton) end
        if f.Inset then Eui(euiSkin.Inset, f.Inset) end
        EachFontString(f, function(fs) Eui(euiSkin.Font, fs) end)
        SkinParts(f)
    elseif look == "elvui" then
        -- Guarded: a change in ElvUI must never stop our window from opening.
        pcall(function()
            elvS:HandleFrame(f)
            EachFontString(f, ElvFont)
        end)
        SkinParts(f)
    end
end

-- A window framed like Blizzard's own (title bar, inset, close button). Where this client
-- lacks that template: a dialog-bordered frame with a close button of its own. Either way
-- f.CloseButton is its X, which EllesmereUI and ElvUI restyle with the window.
function ns.FramedWindow(name, parent)
    parent = parent or UIParent
    local ok, f = pcall(CreateFrame, "Frame", name, parent, "BasicFrameTemplateWithInset")
    if not ok then
        f = CreateFrame("Frame", name, parent, "BackdropTemplate")
        if f.SetBackdrop then
            pcall(f.SetBackdrop, f, {
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 24,
                insets = { left = 6, right = 6, top = 6, bottom = 6 },
            })
        end
    end
    if not f.CloseButton then
        f.CloseButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        f.CloseButton:SetPoint("TOPRIGHT", -2, -2)
    end
    return f
end

if EllesmereUI and EllesmereUI.RegisterSkin then
    EllesmereUI.RegisterSkin(ADDON, function(S)
        euiSkin = S
        -- Runs at login, normally before our window exists; skin any already built.
        for _, f in ipairs(windows) do ns.SkinWindow(f) end
    end)
end
