-- Tests: the spell panel (Spells, Macros and Raid markers tabs).
---------------------------------------------------------------------------
-- Vespera, with spells still to learn and a passive one.
function panelLogin()
    local c, ns = profileLogin()
    local holy = wow.spellbook[2].spells
    table.insert(holy, 1, { 635, "Holy Light", "Rank 1" })
    table.insert(holy, 2, { 639, "Holy Light", "Rank 2" })
    holy[#holy + 1] = { 1026, "Holy Light", "Rank 4", future = true, level = 22 }
    holy[#holy + 1] = { 26573, "Consecration", "Rank 1", future = true, level = 20 }
    holy[#holy + 1] = { 20138, "Improved Devotion", "", passive = true }
    ns.SpellListStale()
    return c, ns
end

function openPanel()
    SlashCmdList.KEYSTANCE("spells")
    return KeystanceSpellPanel
end

-- The rows showing now, as "kind:name".
function panelRows()
    local out = {}
    for _, row in ipairs(KeystanceSpellPanel.rows) do
        local item = row.item
        if item then
            local name = item.name or item.entry and item.entry.name or item.rank and item.rank.rank
            out[#out + 1] = item.kind .. ":" .. tostring(item.kind == "rank" and item.rank.rank or name)
        end
    end
    return table.concat(out, ",")
end

function rowNamed(name)
    for _, row in ipairs(KeystanceSpellPanel.rows) do
        local item = row.item
        if item and (item.name == name or item.entry and item.entry.name == name) then return row end
    end
end

function search(text)
    KeystanceSpellPanel.search:SetText(text)
    KeystanceSpellPanel.search.scripts.OnTextChanged(KeystanceSpellPanel.search)
end

test("the panel lists every class spell by spellbook section, known first, passives left out", function()
    panelLogin()
    openPanel()
    eq(panelRows(), "header:Retribution,spell:Blessing of Might,spell:Holy Strike,spell:Blessings,"
        .. "header:Holy,spell:Holy Light,spell:Consecration")
end)

test("each spell shows its highest rank, what's still to learn, and whether it's on a bar", function()
    panelLogin()
    openPanel()
    local hl = rowNamed("Holy Light")
    eq(hl.item.entry.id, 647, "highest known rank")
    assert(hl.detail.text:find("Rank 3", 1, true), hl.detail.text)
    assert(hl.detail.text:find("next at 22", 1, true), hl.detail.text)
    eq(hl.check:IsShown(), true, "on slot 2")
    local cons = rowNamed("Consecration")
    eq(cons.item.entry.known, false)
    eq(cons.detail.text, "level 20")
    eq(rowNamed("Blessing of Might").check:IsShown(), false)
end)

test("search filters as you type, across sections", function()
    panelLogin()
    openPanel()
    search("bless")
    eq(panelRows(), "header:Retribution,spell:Blessing of Might,spell:Blessings")
    search("zzz")
    eq(KeystanceSpellPanel.empty:IsShown(), true)
end)

test("filters: not on bars, on bars, and to learn", function()
    panelLogin()
    local p = openPanel()
    click(choice(p.filters, "Not on bars"))
    eq(panelRows(), "header:Retribution,spell:Blessing of Might")
    click(choice(p.filters, "On bars"))
    eq(panelRows(), "header:Retribution,spell:Holy Strike,spell:Blessings,header:Holy,spell:Holy Light")
    click(choice(p.filters, "To learn"))
    eq(panelRows(), "header:Holy,spell:Holy Light,spell:Consecration")
    eq(KeystanceDB.settings.spellFilter, "later", "remembered")
end)

test("a section folds away when its header is clicked", function()
    panelLogin()
    openPanel()
    click(rowNamed("Retribution"))
    eq(panelRows(), "header:Retribution,header:Holy,spell:Holy Light,spell:Consecration")
end)

test("clicking or dragging a spell picks up its highest rank; one still to learn can't be", function()
    panelLogin()
    openPanel()
    local hl = rowNamed("Holy Light")
    hl.scripts.OnDragStart(hl)
    eq(wow.cursor[4], 647)
    ClearCursor()
    click(rowNamed("Consecration"))
    eq(wow.cursor, nil)
    assert(printed():find("Consecration is learned at level 20.", 1, true))
end)

test("right-click shows a spell's other ranks, and a lower rank can be picked up", function()
    panelLogin()
    openPanel()
    click(rowNamed("Holy Light"), "RightButton")
    eq(panelRows(), "header:Retribution,spell:Blessing of Might,spell:Holy Strike,spell:Blessings,"
        .. "header:Holy,spell:Holy Light,rank:Rank 3,rank:Rank 2,rank:Rank 1,spell:Consecration")
    local rank1 = KeystanceSpellPanel.rows[9]
    click(rank1)
    eq(wow.cursor[4], 635)
end)

test("a spell group (flyout) is picked up from the spellbook", function()
    panelLogin()
    openPanel()
    click(rowNamed("Blessings"))
    eq(wow.cursor[1], "spell")
end)

test("Shift-click links the spell in chat", function()
    panelLogin()
    openPanel()
    wow.modifiedClick = true
    click(rowNamed("Holy Light"))
    eq(wow.links[1], "|Hspell:647|h[Holy Light]|h")
    eq(wow.cursor, nil)
end)

test("in combat nothing is picked up, and the panel says so", function()
    panelLogin()
    local p = openPanel()
    wow.enterCombat()
    wow.runTimers()
    click(rowNamed("Holy Light"))
    eq(wow.cursor, nil)
    eq(#wow.blocked, 0)
    eq(p.combat:IsShown(), true)
    wow.leaveCombat()
end)

test("the panel sits against the Keystance window, until it's moved", function()
    panelLogin()
    slash("")
    local p = openPanel()
    local point, rel = p:GetPoint()
    eq(point, "TOPLEFT"); eq(rel, KeystanceFrame)
    p:SetPoint("CENTER", UIParent, "CENTER", 10, 20)
    p.scripts.OnDragStop(p)
    eq(p.dock:IsShown(), true, "offers to go back")
    click(p.dock)
    point, rel = p:GetPoint()
    eq(rel, KeystanceFrame)
end)

test("the window's Spells button and the minimap menu open the panel", function()
    panelLogin()
    slash("")
    click(KeystanceFrame.spellsButton)
    eq(KeystanceSpellPanel:IsShown(), true)
    click(KeystanceFrame.spellsButton)
    eq(KeystanceSpellPanel:IsShown(), false)
    Keystance_OnAddonCompartmentClick("Keystance", "RightButton", UIParent)
    wow.menuItem("Spells").fn()
    eq(KeystanceSpellPanel:IsShown(), true)
end)

---------------------------------------------------------------------------
-- Macros
test("the Macros tab lists account and character macros; they can be picked up", function()
    panelLogin()
    wow.macros[1] = { name = "Assist", body = "/assist" }
    local p = openPanel()
    click(choice(p.kinds, "Macros"))
    eq(panelRows(), "header:Account macros,macro:Assist,header:Vespera Ashward's macros,macro:Attack")
    eq(rowNamed("Attack").check:IsShown(), true, "on slot 3")
    eq(p.filters.buttons[4]:IsShown(), false, "no To learn filter for macros")
    click(rowNamed("Assist"))
    eq(wow.cursor[1], "macro"); eq(wow.cursor[2], 1)
end)

---------------------------------------------------------------------------
-- Raid markers
test("the Raid markers tab lists the eight markers with their keys", function()
    panelLogin()
    wow.bindings.END = "RAIDTARGET7"
    local p = openPanel()
    click(choice(p.kinds, "Raid markers"))
    eq(#p.rows[1].item.name > 0, true)
    eq(rowNamed("Cross").detail.text, "END")
    eq(rowNamed("Skull").item.command, "RAIDTARGET8")
    eq(p.filters:IsShown(), false)
end)

test("clicking a marker, then a key, puts the marker on that key (undoable)", function()
    local c, ns = panelLogin()
    local p = openPanel()
    click(choice(p.kinds, "Raid markers"))
    click(rowNamed("Skull"))
    eq(shownPage(), "keyboard", "the Keyboard tab opens")
    local page = KeystanceFrame.pages[1]
    eq(page.binding:IsShown(), true)
    local e = capFor(page, "E")
    click(e)
    eq(GetBindingAction("E"), "RAIDTARGET8")
    eq(page.binding:IsShown(), false)
    eq(ns.UndoLabel(), "putting Skull on E")
    ns.Undo()
    eq(GetBindingAction("E"), "")
end)

test("a key that already does something asks first; right-click cancels waiting for a key", function()
    panelLogin()
    local p = openPanel()
    click(choice(p.kinds, "Raid markers"))
    click(rowNamed("Skull"))
    local page = KeystanceFrame.pages[1]
    click(capFor(page, "W"))
    eq(wow.popup.which, "KEYSTANCE_BIND_COMMAND")
    assert(wow.popup.text:find("W is Move Forward", 1, true), wow.popup.text)
    eq(GetBindingAction("W"), "MOVEFORWARD", "not until confirmed")
    StaticPopupDialogs.KEYSTANCE_BIND_COMMAND.OnAccept()
    eq(GetBindingAction("W"), "RAIDTARGET8")
    click(rowNamed("Cross"))
    click(capFor(page, "E"), "RightButton")
    eq(page.binding:IsShown(), false)
    eq(GetBindingAction("E"), "")
end)
