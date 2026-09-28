-- Keystance spell list: the character's class spells as data for the spell panel, grouped
-- by the spellbook's sections (General, then the class's), one entry per spell at its
-- highest known rank, with its other ranks, whether it's on a bar, and the spells (and
-- ranks) still to learn with the level they come at. Passive abilities are left out.
-- Built when the panel needs it; marked stale when spells or bars change.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)
local L = ns.L

local pairs, ipairs, type = pairs, ipairs, type

local BANK = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
local SPELL, FUTURE, FLYOUT = 1, 2, 4
if Enum and Enum.SpellBookItemType then
    local t = Enum.SpellBookItemType
    SPELL, FUTURE, FLYOUT = t.Spell or 1, t.FutureSpell or 2, t.Flyout or 4
end

local function LevelLearned(id)
    local level = C_Spell.GetSpellLevelLearned and C_Spell.GetSpellLevelLearned(id)
    return type(level) == "number" and level > 0 and level or nil
end

-- Sections, in spellbook order: { name = "Holy", entries = { entry, ... } }. An entry:
--   { name, id (highest known rank, nil if not yet learned), icon, ranks = { { id, rank } lowest first },
--     known = true|false, level (for one not yet learned), nextRank = { rank, level } (a
--     higher rank still to learn), onBar = true|false, flyout = spellbook index (a spell group) }
local sections, stale = nil, true

function ns.SpellListStale() stale = true end

local function Build()
    local onBar = {}
    for slot = 1, ns.MANAGED_SLOTS do
        local a = ns.DescribeSlot(slot)
        if a and a.name and (a.t == "spell" or a.t == "flyout") then onBar[a.name] = true end
        if a and a.t == "flyout" then onBar["flyout:" .. tostring(a.id)] = true end
    end
    local result = {}
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local li = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if li and not li.shouldHide and not li.isGuild then
            local section = { name = li.name, entries = {} }
            local byName = {}
            for i = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
                local info = C_SpellBook.GetSpellBookItemInfo(i, BANK)
                if info and not info.isPassive then
                    local e = byName[info.name]
                    if not e then
                        e = { name = info.name, icon = info.iconID, ranks = {}, known = false }
                        byName[info.name] = e
                        section.entries[#section.entries + 1] = e
                    end
                    if info.itemType == FLYOUT then
                        e.known, e.flyout, e.flyoutID = true, i, info.actionID
                        e.onBar = onBar["flyout:" .. tostring(info.actionID)] or false
                    elseif info.itemType == SPELL and info.spellID then
                        e.known = true
                        e.id = info.spellID -- ranks come lowest first, so the last is highest
                        e.ranks[#e.ranks + 1] = { id = info.spellID, rank = info.subName }
                        e.icon = e.icon or info.iconID
                    elseif info.itemType == FUTURE and info.spellID then
                        local level = LevelLearned(info.spellID)
                        if e.known or e.id then
                            if not e.nextRank then e.nextRank = { rank = info.subName, level = level, id = info.spellID } end
                        else
                            e.futureID = e.futureID or info.spellID
                            e.level = e.level or level
                        end
                    end
                end
            end
            for _, e in ipairs(section.entries) do
                if e.onBar == nil then e.onBar = onBar[e.name] or false end
                e.lower = e.name:lower()
            end
            if #section.entries > 0 then result[#result + 1] = section end
        end
    end
    return result
end

function ns.SpellSections()
    if stale or not sections then
        sections = Build()
        stale = false
    end
    return sections
end

-- The spells change when learned; whether they're on a bar changes with the bars.
for _, event in ipairs({ "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "ACTIONBAR_SLOT_CHANGED" }) do
    ns.On(event, function() stale = true end)
end
