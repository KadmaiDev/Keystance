-- Tests: saved data, character identity, slash commands. Loaded by tests/run.lua, which
-- provides test, eq, wow, FILES and the other shared helpers.
---------------------------------------------------------------------------
-- Saved data
test("a first login starts fresh saved data with the default settings", function()
    local ns = start(nil)
    eq(KeystanceDB, ns.db)
    eq(KeystanceDB.v, 1)
    eq(KeystanceDB.settings.skin, "auto")
    eq(type(KeystanceDB.chars), "table")
end)

test("the player's own settings and data are kept; only missing settings are filled in", function()
    local saved = { v = 1, settings = { skin = "elvui", minimapHidden = true },
        chars = { ["Vespera Ashward"] = { class = "PALADIN", profiles = { Prot = { slots = {} } } } } }
    start(saved)
    eq(KeystanceDB.settings.skin, "elvui")
    eq(KeystanceDB.settings.minimapHidden, true)
    assert(KeystanceDB.chars["Vespera Ashward"].profiles.Prot, "profile kept")
end)

test("saved data is repaired in place, never thrown away", function()
    -- Broken pieces are replaced; everything else survives.
    start({ v = 1, settings = "junk", chars = { ["Vespera Ashward"] = { class = "PALADIN", profiles = "junk" } },
        extra = { keep = true } })
    eq(KeystanceDB.settings.skin, "auto")
    eq(KeystanceDB.extra.keep, true)
    eq(type(KeystanceDB.chars["Vespera Ashward"].profiles), "table")
end)

test("data saved by a newer version is left as it is", function()
    start({ v = 7, settings = { skin = "classic" }, chars = {}, future = 1 })
    eq(KeystanceDB.v, 7)
    eq(KeystanceDB.future, 1)
end)

test("the character is keyed by full name, joining UnitName's two values", function()
    local ns = start(nil)
    eq(ns.charKey, "Vespera Ashward")
    eq(KeystanceDB.chars["Vespera Ashward"].class, "PALADIN")
    eq(ns.char, KeystanceDB.chars["Vespera Ashward"])
end)

---------------------------------------------------------------------------
-- Slash commands
test("/kst and /keystance open the window; unknown commands show help", function()
    start(nil)
    eq(SLASH_KEYSTANCE1, "/kst"); eq(SLASH_KEYSTANCE2, "/keystance")
    slash("")
    eq(KeystanceFrame:IsShown(), true)
    slash("")
    eq(KeystanceFrame:IsShown(), false)
    slash("nonsense")
    assert(printed():find("by Kadmai", 1, true), printed())
end)

test("every command is listed in /kst help", function()
    start(nil)
    slash("help")
    for _, cmd in ipairs({ "options", "minimap", "skin", "mem" }) do
        assert(printed():find(cmd, 1, true), cmd .. " missing from help")
    end
end)

test("/kst mem reports memory use", function()
    start(nil)
    slash("mem")
    assert(printed():find("12.5 KB", 1, true), printed())
end)
