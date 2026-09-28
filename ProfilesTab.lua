-- Keystance Profiles tab: the character's profiles, each with Apply, Update, Rename, Copy and
-- Delete; New profile from the current setup; Undo; Restore original setup; and, while the
-- character shares the account's keybinds, a note with the one-click switch. Anything
-- that would change bars or keys is greyed out in combat.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)
local L = ns.L

local ipairs, CreateFrame = ipairs, CreateFrame

local ROWS, ROW_HEIGHT = 6, 34

-- Apply from the tab: says what will change first (the shared-keybinds question covers it).
function ns.ConfirmApply(name)
    local c = ns.char
    local key = ns.FindProfile(name)
    if not (c and key) then return end
    local slots, keys = ns.CountChanges(c.profiles[key], "bars")
    if slots + keys == 0 then return ns.Print(L["%s is already in place."]:format(key)) end
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
    local what = keys == 0 and L["%d slots"]:format(slots) or slots == 0 and L["%d keys"]:format(keys)
        or L["%d slots and %d keys"]:format(slots, keys)
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
    local row = CreateFrame("Frame", nil, page)
    row:SetSize(680, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -112 - (i - 1) * ROW_HEIGHT)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0.06)
    local name = Text(f, row, "GameFontNormal")
    name:SetPoint("TOPLEFT", 8, -4)
    name:SetWidth(250)
    name:SetJustifyH("LEFT")
    row.name = name
    local detail = Text(f, row, "GameFontDisableSmall")
    detail:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
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
    row.apply = RowButton(L["Apply"], 64, ns.ConfirmApply)
    row.update:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Update"])
        GameTooltip:AddLine(L["Replace this profile with your bars and keys as they are now."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row.update:SetScript("OnLeave", function() GameTooltip:Hide() end)
    for _, b in ipairs({ row.delete, row.copy, row.rename, row.update, row.apply }) do ns.SkinButton(b) end
    ns.SkinText(name)
    ns.SkinText(detail)
    return row
end

local function Refresh(page)
    local c = ns.char
    if not c then return end
    local combat = ns.InCombat()
    page.title:SetText(L["Profiles for %s"]:format(ns.charKey or "?"))
    page.active:SetText(c.active and L["In use: %s"]:format(c.active) or "")
    page.shared:SetShown(ns.SharedKeybinds())
    page.ownKeys:SetShown(ns.SharedKeybinds())
    page.ownKeys:SetEnabled(not combat)
    local undo = ns.UndoLabel()
    page.undo:SetText(undo and L["Undo %s"]:format(undo) or L["Undo"])
    page.undo:SetEnabled(undo ~= nil and not combat)
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
            row.name:SetText(name == c.active and ("|cff55ff55" .. name .. "|r") or name)
            row.detail:SetText(L["%d slots, %d keys, saved %s"]:format(p.nSlots or 0, p.nBinds or 0,
                date("%d %b %Y", p.updated or p.created or 0)))
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
    local title = Text(f, page, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    page.title = title
    local active = Text(f, page, "GameFontHighlight")
    active:SetPoint("TOPRIGHT", page, "TOPRIGHT", -16, -16)
    page.active = active

    page.new = Button(f, page, L["New profile from current setup"], 230, function() ns.NewProfile() end)
    page.new:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    page.undo = Button(f, page, L["Undo"], 200, function() ns.Undo() end)
    page.undo:SetPoint("LEFT", page.new, "RIGHT", 8, 0)
    page.restore = Button(f, page, L["Restore original setup"], 190, function() ns.ConfirmRestore() end)
    page.restore:SetPoint("LEFT", page.undo, "RIGHT", 8, 0)
    page.restore:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Restore original setup"])
        GameTooltip:AddLine(L["Puts your bars and every keybind back as they were before Keystance. Before uninstalling Keystance, click this to get your original setup back."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    page.restore:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local shared = Text(f, page, "GameFontHighlightSmall")
    shared:SetPoint("TOPLEFT", page.new, "BOTTOMLEFT", 0, -12)
    shared:SetWidth(430)
    shared:SetJustifyH("LEFT")
    shared:SetText(L["Your keybinds are shared by all your characters. Give this character its own, so profiles change only its keys."])
    page.shared = shared
    page.ownKeys = Button(f, page, L["Give it its own keybinds"], 200, function() ns.UseOwnKeybinds() end)
    page.ownKeys:SetPoint("LEFT", shared, "RIGHT", 12, 0)

    local empty = Text(f, page, "GameFontHighlight")
    empty:SetPoint("TOP", page, "TOP", 0, -140)
    empty:SetWidth(520)
    empty:SetText(L["No profiles yet. Set up your bars and keys the way you like them for a role, then click New profile from current setup."])
    page.empty = empty
    local more = Text(f, page, "GameFontDisableSmall")
    more:SetPoint("TOPLEFT", page, "TOPLEFT", 24, -112 - ROWS * ROW_HEIGHT - 6)
    page.more = more
    page.Refresh = Refresh
end

ns.pageBuilders.profiles = Build
