-- Keystance guide: a new player's first steps, one at a time. A bar under the window says
-- the next step with a button that does it; the Profiles tab's "Getting started" shows
-- them all. Steps tick themselves off from what's already true (a backup exists, the
-- character has its own keybinds, profiles, keys or rules, gear), so a player who already
-- did something is never asked to again. Per character (an alt with no profiles gets its
-- own guide); hidden with the bar's close button and back with /kst guide.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)
local L = ns.L

local ipairs, pairs, next, CreateFrame = ipairs, pairs, next, CreateFrame

local function Char() return ns.char end

local function CountProfiles(c)
    local n = 0
    for _ in pairs(c.profiles) do n = n + 1 end
    return n
end

-- True if a profile can be switched to without the window: a profile key, Next profile,
-- or a rule.
local function HasSwitch(c)
    if #c.rules > 0 or GetBindingKey("KEYSTANCE_NEXT") then return true end
    for name in pairs(c.profiles) do
        if ns.ProfileKey(name) then return true end
    end
    return false
end

local function HasGear(c)
    for _, p in pairs(c.profiles) do
        if p.itemrack or (p.gear and next(p.gear)) then return true end
    end
    return false
end

-- Opens the gear editor for the profile in use (or the first).
local function OpenGear()
    local c = Char()
    ns.ShowTab("profiles")
    local name = c.active or ns.ProfileNames()[1]
    if name then ns.ShowGearFor(name) end
end

-- The steps: what to do, what's true once done, a check, and buttons { label, fn }.
ns.GUIDE_STEPS = {
    { key = "backup", title = L["Your setup is backed up"],
        todo = L["Keystance is saving your bars and keys as they are now, so you can always go back to them."],
        done = L["Your bars and keys from before Keystance are saved. Restore original setup (Profiles tab) puts them back any time; use it before uninstalling."],
        check = function(c) return c.snapshot ~= nil end },
    { key = "ownkeys", title = L["Give this character its own keybinds"],
        todo = L["Your keybinds are shared by all your characters, so a profile's keys would change them everywhere. This gives this character its own copy; nothing changes on screen."],
        done = L["This character has its own keybinds."],
        check = function() return not ns.SharedKeybinds() end,
        actions = { { L["Own keybinds"], function() ns.UseOwnKeybinds() end } } },
    { key = "first", title = L["Save your first profile"],
        todo = L["A profile is your bars and keys for one role. Save them as they are now, named after the role (Ret, Prot, Holy...)."],
        done = L["You have a profile."],
        check = function(c) return next(c.profiles) ~= nil end,
        actions = { { L["Save as profile"], function() ns.NewProfile() end } } },
    { key = "second", title = L["Set up another role"],
        todo = L["Set up your bars for another role: drag spells from the Actions panel onto the Bars tab, then give them keys with Keybind mode (or on the Keyboard tab). Then save that as a second profile."],
        done = L["You have profiles to switch between."],
        check = function(c) return CountProfiles(c) >= 2 end,
        actions = { { L["Bars"], function() ns.ShowTab("bars") end },
            { L["Save as profile"], function() ns.NewProfile() end } } },
    { key = "switch", title = L["Choose how to switch"],
        todo = L["Give each profile a key (the key button on its row), or add a rule so your gear switches for you, like a shield switching to Prot."],
        done = L["You can switch without opening Keystance."],
        check = HasSwitch,
        actions = { { L["Set keys"], function() ns.ShowTab("profiles") end },
            { L["Add a rule"], function() ns.ShowTab("rules") end } } },
    { key = "gear", optional = true, title = L["Gear too (optional)"],
        todo = L["A profile can change your gear as well: its Gear button picks an ItemRack set or saves what you're wearing."],
        done = L["A profile changes your gear."],
        check = HasGear,
        actions = { { L["Gear"], OpenGear } } },
}

local function State(c)
    c.guide = c.guide or {}
    return c.guide
end

function ns.GuideStepDone(c, step)
    return step.check(c) or (step.optional and State(c).skipped and State(c).skipped[step.key]) or false
end

-- The first step not done, and its number; nil when every step is.
function ns.GuideNext(c)
    for i, step in ipairs(ns.GUIDE_STEPS) do
        if not ns.GuideStepDone(c, step) then return step, i end
    end
end

-- Whether the bar under the window should show.
function ns.GuideShown()
    local c = Char()
    if not c then return false end
    local g = State(c)
    return not g.hidden and not g.finished
end

function ns.HideGuide()
    local c = Char()
    if not c then return end
    State(c).hidden = true
    ns.Print(L["Guide hidden. /kst guide brings it back."])
    ns.ProfilesChanged()
end

function ns.ShowGuideBar()
    local c = Char()
    if not c then return end
    local g = State(c)
    g.hidden, g.finished = nil, nil
    ns.ToggleWindow(true)
    ns.ProfilesChanged()
end

-- The guide is done with: it doesn't come back (/kst guide still shows it). `quiet` when the
-- window is closing anyway.
function ns.FinishGuide(quiet)
    local c = Char()
    if not c then return end
    State(c).finished = true
    if not quiet then ns.ProfilesChanged() end
end

function ns.SkipGuideStep(key)
    local g = State(Char())
    g.skipped = g.skipped or {}
    g.skipped[key] = true
    ns.ProfilesChanged()
end

ns.AddCommand("guide", function() ns.ShowGuideBar() end)

---------------------------------------------------------------------------
-- The bar under the window
---------------------------------------------------------------------------
local bar

local function ActionButton(parent, i)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(110, 22)
    b:SetScript("OnClick", function(self) if self.fn then self.fn() end end)
    ns.SkinButton(b)
    return b
end

-- A small window of its own under the main one, built like it (Blizzard's framed window
-- with a title bar, inset and close button, so the Classic look matches; EllesmereUI and
-- ElvUI restyle it with the main window).
local function BuildBar(window)
    local ok, f = pcall(CreateFrame, "Frame", "KeystanceGuideBar", window, "BasicFrameTemplateWithInset")
    if not ok then
        f = CreateFrame("Frame", "KeystanceGuideBar", window, "BackdropTemplate")
        if f.SetBackdrop then
            pcall(f.SetBackdrop, f, {
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 24,
                insets = { left = 6, right = 6, top = 6, bottom = 6 },
            })
        end
    end
    if not f.CloseButton then -- the template brings one; a plain frame gets its own
        f.CloseButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        f.CloseButton:SetPoint("TOPRIGHT", -2, -2)
    end
    bar = f
    f.buttons, f.texts = {}, {}
    f:SetPoint("TOPLEFT", window, "BOTTOMLEFT", 0, -2)
    f:SetPoint("TOPRIGHT", window, "BOTTOMRIGHT", 0, -2)
    f:SetHeight(100) -- the title bar, then the step and up to three lines beside the buttons
    -- The title bar: "Getting started", and which step on its left.
    local heading = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if not f.TitleText then heading:SetPoint("TOP", 0, -8) end
    heading:SetText(L["Getting started"])
    f.heading = heading
    f.step = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.step:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -6)
    -- The step, and what to do, with room from the edges.
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -32)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -5)
    f.text:SetJustifyV("TOP")
    f.text:SetJustifyH("LEFT")
    f.close = f.CloseButton -- where EllesmereUI and ElvUI look for a window's X to restyle it
    f.close:SetScript("OnClick", function()
        -- Closing "You're all set" is being done with it, not hiding a guide still under way.
        if f.allSet then return ns.FinishGuide() end
        ns.HideGuide()
    end)
    -- Once "You're all set" has been seen, closing the window ends the guide too: it's shown
    -- once, not every time (the owner's report, 2026-09-29).
    window:HookScript("OnHide", function()
        if f.allSet and f:IsShown() then ns.FinishGuide(true) end
    end)
    f.all = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.all:SetSize(80, 22)
    f.all:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 12)
    f.all:SetText(L["All steps"])
    f.all:SetScript("OnClick", function() ns.ShowGuideSteps() end)
    ns.SkinButton(f.all)
    f.actions = { ActionButton(f, 1), ActionButton(f, 2) }
    f.actions[1]:SetPoint("RIGHT", f.all, "LEFT", -6, 0)
    f.actions[2]:SetPoint("RIGHT", f.actions[1], "LEFT", -4, 0)
    for _, fs in ipairs({ heading, f.step, f.title, f.text }) do
        f.texts[#f.texts + 1] = fs
        ns.SkinText(fs)
    end
    ns.SkinWindow(f)
end

-- Shows the next step (or "all set") while the window is open. Called when profiles,
-- bars or keys change, not on every redraw.
function ns.RefreshGuide(window)
    local c = Char()
    if not ns.GuideShown() then
        if bar then bar:Hide() end
        return
    end
    if not bar then BuildBar(window) end
    local step, i = ns.GuideNext(c)
    for _, b in ipairs(bar.actions) do b:Hide() end
    bar.allSet = step == nil
    if step then
        bar.step:SetText(L["Step %d of %d"]:format(i, #ns.GUIDE_STEPS))
        bar.title:SetText(step.title)
        bar.text:SetText(step.todo)
        for n, a in ipairs(step.actions or {}) do
            local b = bar.actions[n]
            b:SetText(a[1])
            b.fn = a[2]
            b:Show()
        end
        if step.optional then
            local b = bar.actions[#(step.actions or {}) + 1]
            b:SetText(L["Skip"])
            b.fn = function() ns.SkipGuideStep(step.key) end
            b:Show()
        end
    else
        bar.step:SetText("")
        bar.title:SetText(L["You're all set"])
        bar.text:SetText(L["Switch with your keys, rules or the buttons along the bottom. Undo and Restore are on the Profiles tab; /kst guide shows this again."])
        local b = bar.actions[1]
        b:SetText(L["Got it"])
        b.fn = function() ns.FinishGuide() end
        b:Show()
    end
    -- The text stops before the leftmost button, however wide the window is (the Keyboard
    -- tab widens it for the numpad; it ran under the buttons at the normal width).
    local leftmost = bar.all
    for _, b in ipairs(bar.actions) do
        if b:IsShown() then leftmost = b end
    end
    bar.text:ClearAllPoints()
    bar.text:SetPoint("TOPLEFT", bar.title, "BOTTOMLEFT", 0, -5)
    bar.text:SetPoint("RIGHT", leftmost, "LEFT", -12, 0)
    bar:Show()
end

---------------------------------------------------------------------------
-- Every step, on the Profiles tab (in place of the list, like the gear editor)
---------------------------------------------------------------------------
local ROW = 52

function ns.BuildGuideView(view, f, back)
    view.window = f
    local title = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText(L["Getting started"])
    local backButton = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    backButton:SetSize(90, 22)
    backButton:SetPoint("TOPRIGHT", view, "TOPRIGHT", -16, -10)
    backButton:SetText(L["Back"])
    backButton:SetScript("OnClick", back)
    view.back = backButton
    view.toggle = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    view.toggle:SetSize(150, 22)
    view.toggle:SetPoint("RIGHT", backButton, "LEFT", -6, 0)
    view.toggle:SetScript("OnClick", function()
        if ns.GuideShown() then ns.HideGuide() else ns.ShowGuideBar() end
    end)
    view.rows = {}
    for i, step in ipairs(ns.GUIDE_STEPS) do
        local row = CreateFrame("Frame", nil, view)
        row:SetSize(680, ROW - 4)
        row:SetPoint("TOPLEFT", view, "TOPLEFT", 16, -44 - (i - 1) * ROW)
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0.06)
        row.mark = row:CreateTexture(nil, "ARTWORK")
        row.mark:SetSize(18, 18)
        row.mark:SetPoint("TOPLEFT", 8, -6)
        row.number = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.number:SetPoint("CENTER", row.mark, "CENTER")
        row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.title:SetPoint("TOPLEFT", 34, -6)
        row.title:SetText(step.title)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
        row.text:SetWidth(430)
        row.text:SetJustifyH("LEFT")
        row.buttons = {}
        local x = -6
        for n = #(step.actions or {}), 1, -1 do
            local a = step.actions[n]
            local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            b:SetSize(100, 22)
            b:SetPoint("RIGHT", row, "RIGHT", x, 0)
            b:SetText(a[1])
            b:SetScript("OnClick", function() a[2]() end)
            ns.SkinButton(b)
            row.buttons[n] = b
            x = x - 104
        end
        for _, fs in ipairs({ row.number, row.title, row.text }) do
            f.texts[#f.texts + 1] = fs
            ns.SkinText(fs)
        end
        view.rows[i] = row
    end
    f.texts[#f.texts + 1] = title
    ns.SkinText(title)
    ns.SkinButton(backButton)
    ns.SkinButton(view.toggle)
end

function ns.RefreshGuideView(view)
    local c = Char()
    if not c then return end
    for i, step in ipairs(ns.GUIDE_STEPS) do
        local row = view.rows[i]
        local done = ns.GuideStepDone(c, step)
        row.done = done
        row.mark:SetTexture(done and "Interface\\RaidFrame\\ReadyCheck-Ready" or nil)
        row.number:SetText(done and "" or i)
        row.text:SetText(done and step.done or step.todo)
        row.title:SetTextColor(done and 0.5 or 1, done and 0.8 or 0.82, done and 0.5 or 0)
        for _, b in ipairs(row.buttons) do b:SetShown(not done) end
    end
    view.toggle:SetText(ns.GuideShown() and L["Hide the guide bar"] or L["Show the guide bar"])
end

-- A new character is told once where to start (and that its setup is safe).
ns.On("PLAYER_ENTERING_WORLD", function()
    local c = Char()
    if not c or State(c).welcomed then return end
    State(c).welcomed = true
    C_Timer.After(5, function()
        ns.Print(L["Keystance is ready. Type /kst (or click the minimap button) to get started."])
    end)
end)
