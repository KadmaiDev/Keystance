-- Keystance spell ranks: when the character learns a new rank of a spell, the rank it was
-- using until then (the previous highest) is replaced on the bars by the new one. Lower
-- ranks stay: players down-rank on purpose (a cheap low rank of a heal), which is why the
-- game itself doesn't upgrade spells. It runs 3 seconds after learning (after the
-- spellbook has updated, and after anything the game itself does to the bars, which the
-- phase 0 probe watches at 1.5 s), waits for combat to end, and can be undone.
-- The "New spell ranks" setting (Settings tab and Options page; on by default, /kst ranks)
-- turns it off. Profiles keep the
-- rank they saved; applying one with a rank the character no longer has uses the highest.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Keystance is running (Core.lua)
local L = ns.L

local pairs = pairs

local WAIT = 3
local learned, scheduled = {}, false

function ns.RanksOn()
    return not ns.db.settings.ranksOff
end

-- Replaces lower ranks of the spells just learned. Returns how many slots it changed.
local function Upgrade()
    local book = ns.ScanBook()
    local state = ns.CurrentState()
    local changed, names, later = 0, {}, false
    for id in pairs(learned) do
        local name = C_Spell.GetSpellName(id)
        local ranks = name and book.byName[name] -- highest first
        local best = ranks and ranks[1]
        -- The spellbook hasn't listed the new rank yet: without it, "the rank in use until
        -- now" would be the wrong one (a lower, down-ranked one). Tried again shortly.
        if not book.known[id] then
            best, later = nil, true
        end
        -- What gets replaced: the ranks just learned below the best (several bought at once),
        -- and the highest rank known before them, the one in use until now. Not lower ones.
        local replace = {}
        if ranks then
            for i = 2, #ranks do
                replace[ranks[i]] = true
                if not learned[ranks[i]] then break end -- the previous highest: stop here
            end
        end
        if best then
            local n = 0
            for slot = 1, ns.MANAGED_SLOTS do
                local a = state.slots[slot]
                if a and a.t == "spell" and a.name == name and replace[a.id] then
                    state.slots[slot] = { t = "spell", id = best, name = name, rank = C_Spell.GetSpellSubtext(best) }
                    n = n + 1
                end
            end
            if n > 0 then
                changed = changed + n
                names[#names + 1] = L["%s to %s"]:format(name, C_Spell.GetSpellSubtext(best) or "?")
            end
        end
    end
    for id in pairs(learned) do
        if book.known[id] or not later then learned[id] = nil end
    end
    if later then ns.RanksRetry() end
    if changed == 0 then return 0 end
    ns.ApplyChange(state, { keys = false }, L["Upgraded %s"]:format(table.concat(names, ", ")),
        L["the rank upgrade"])
    return changed
end

local function Run()
    scheduled = false
    if not ns.RanksOn() then
        for id in pairs(learned) do learned[id] = nil end
        return
    end
    ns.OutOfCombat("ranks", Upgrade)
end

-- The spellbook hadn't listed a new rank yet: another look shortly, a few times at most.
local retries = 0
function ns.RanksRetry()
    retries = retries + 1
    if retries > 5 then
        retries = 0
        for id in pairs(learned) do learned[id] = nil end
        return
    end
    if not scheduled then
        scheduled = true
        C_Timer.After(WAIT, Run)
    end
end

ns.On("LEARNED_SPELL_IN_SKILL_LINE", function(spellID)
    if type(spellID) ~= "number" or (issecretvalue and issecretvalue(spellID)) then return end
    learned[spellID] = true
    if not scheduled then
        scheduled = true
        C_Timer.After(WAIT, Run)
    end
end)

ns.AddCommand("ranks", function()
    ns.db.settings.ranksOff = ns.RanksOn() or nil
    ns.Print(ns.RanksOn() and L["New spell ranks replace lower ranks on your bars."]
        or L["New spell ranks no longer replace lower ranks on your bars."])
end)
