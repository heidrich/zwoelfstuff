---------------------------------------------------------------------------
-- Profiles.lua - which settings a character is using
--
-- WHAT CHANGED, AND WHAT DELIBERATELY DID NOT.
--
-- Before this file, a profile WAS a character: everything you set was stored
-- under "Name - Realm" and there was no way to say "this alt uses what I
-- built over there" except copying it once and letting the two drift apart
-- from that moment on.
--
-- The owner's rule from dbVersion 7 still holds and is still the DEFAULT: a
-- change belongs to the character that made it. Nothing about a fresh login
-- behaves differently, and nobody who never opens this page will notice it
-- exists. What is new is that a profile now has a NAME of its own, and a
-- character POINTS at one - so two characters may point at the same name, and
-- then they really are the same settings rather than two copies of them.
--
--   ZwoelfStuffDB
--     profiles     [name]              = the settings themselves
--     charProfile  ["Name - Realm"]    = which name that character uses
--     account                          = the measurements, unchanged
--
-- The migration names each existing profile after the character that owned
-- it and points that character at it. So the first login after this update
-- produces exactly the arrangement that was there before, and the feature is
-- something you opt into by pressing a button rather than something that
-- happens to your bars.
---------------------------------------------------------------------------
local _, ns = ...

local Profiles = {}
ns.Profiles = Profiles

---------------------------------------------------------------------------
-- Getting to the store
--
-- Every function here goes through this, so there is exactly one place that
-- knows the shape of the saved variable and exactly one place to look when
-- it changes again.
---------------------------------------------------------------------------
local function Store()
    ZwoelfStuffDB = ZwoelfStuffDB or {}
    return ZwoelfStuffDB
end

---------------------------------------------------------------------------
-- THE MIGRATIONS, oldest first, and each one runs at most once.
--
-- Both are shaped the same way: look for the OLD shape, and only if it is
-- there, move it. A migration keyed off a version number instead would run
-- against a database that never had the old shape at all - which is what a
-- fresh install is.
---------------------------------------------------------------------------
-- Exported for the test, and only for the test. This is the one function in
-- the addon that MOVES somebody's saved settings from one place to another,
-- and the failure it can produce is the worst one there is: bars that were
-- there yesterday and are not there now, with the old copy already deleted.
-- It is asserted against a made-up store rather than trusted.
function Profiles.Migrate(store)
    -- 1. Before profiles existed at all: everything sat at the root and
    --    belonged to whoever was playing. This was already here; it is kept
    --    because a database from that era can still be sitting in somebody's
    --    WTF folder, and losing their bars on the update they installed for
    --    profiles would be a poor joke.
    if store.chars == nil and store.profiles == nil then
        local old = {}
        for key, value in pairs(store) do
            old[key] = value
            store[key] = nil
        end

        store.account = {}
        for key in pairs(ns.ACCOUNT_DEFAULTS) do
            store.account[key] = old[key]
            old[key] = nil
        end

        store.chars = {}
        local key = ns.CharacterKey()
        if key and next(old) then store.chars[key] = old end
    end

    -- 2. Characters become names. Each character's settings keep their place
    --    and gain a name; the character is pointed at it. Nothing moves as
    --    far as the person is concerned.
    if store.chars then
        store.profiles = store.profiles or {}
        store.charProfile = store.charProfile or {}

        for key, profile in pairs(store.chars) do
            if type(profile) == "table" then
                -- A name collision cannot happen here - the old keys were
                -- unique per character and they become the names - but a
                -- SECOND run of this could overwrite a profile somebody has
                -- since edited. Hence: never overwrite, and delete the old
                -- table only once it is safely somewhere else.
                if store.profiles[key] == nil then
                    store.profiles[key] = profile
                end
                if store.charProfile[key] == nil then
                    store.charProfile[key] = key
                end
            end
        end

        store.chars = nil
    end

    store.profiles = store.profiles or {}
    store.charProfile = store.charProfile or {}
end

---------------------------------------------------------------------------
-- Opening up
--
-- Called from ADDON_LOADED, and again by hand every time the active profile
-- changes. Everything after it in the boot sequence reads ns.db, so this has
-- to leave ns.db pointing at the right table before any of it runs.
---------------------------------------------------------------------------
function ns.OpenProfile()
    local store = Store()
    Profiles.Migrate(store)

    store.account = ns.ApplyDefaults(store.account or {}, ns.ACCOUNT_DEFAULTS)
    ns.account = store.account

    local key = ns.CharacterKey() or "unknown"

    -- A character nobody has assigned gets a profile named after itself. That
    -- is the old behaviour restated: your settings are yours until you say
    -- otherwise.
    local name = store.charProfile[key]
    if type(name) ~= "string" or store.profiles[name] == nil then
        name = key
        store.charProfile[key] = name
    end
    store.profiles[name] = store.profiles[name] or {}

    -- BEFORE ApplyDefaults, never after. A migration that runs afterwards is
    -- overwritten by the default it was meant to replace on the very next
    -- login, which is the class of bug that eats a saved setting in silence.
    if ns.CoTanks and ns.CoTanks.Migrate then
        pcall(ns.CoTanks.Migrate, ns.CoTanks, store.profiles[name].coTanks)
    end

    ns.db = ns.ApplyDefaults(store.profiles[name], ns.DEFAULTS)
    ns.profileKey = key
    ns.profileName = name

    -- THE LANGUAGE IS PART OF OPENING A PROFILE, not part of booting a
    -- feature. It is stored per profile, so switching profile can change it -
    -- and every lookup after this line answers in the new one. Anything drawn
    -- BEFORE it is in English, which is why nothing in this addon looks a
    -- string up at file scope.
    if ns.Locale then ns.Locale:Apply() end
end

---------------------------------------------------------------------------
-- What there is
---------------------------------------------------------------------------

-- Every profile, sorted, each with what is in it and who is using it. Built
-- on demand and never cached: another character's assignment appears the
-- moment they log out, and a list made at login would never show it.
function Profiles:List()
    local store = Store()
    local out = {}

    local users = {}
    for charKey, name in pairs(store.charProfile or {}) do
        if type(name) == "string" then
            users[name] = users[name] or {}
            table.insert(users[name], charKey)
        end
    end

    for name, profile in pairs(store.profiles or {}) do
        if type(profile) == "table" then
            local by = users[name] or {}
            table.sort(by)
            out[#out + 1] = {
                name = name,
                bars = #(profile.bars or {}),
                reminders = #(profile.reminders or {}),
                users = by,
                active = name == ns.profileName,
            }
        end
    end

    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- The other CHARACTERS, which is not the same question as the other
-- profiles. Kept because "take a layout from" asks it, and because a
-- character is what somebody remembers - they think "my paladin", not "the
-- profile my paladin happens to point at".
function ns.OtherProfiles()
    local store = Store()
    local out = {}

    for charKey, name in pairs(store.charProfile or {}) do
        local profile = type(name) == "string" and store.profiles[name]
        -- A character POINTING AT THE PROFILE IN USE is left off the list.
        -- Its layout is the one you are looking at, so there is nothing to
        -- copy - and taking it would not be nothing: the copy empties every
        -- cell on the way over, so it would strip the spells off your own
        -- bars. CopyLayoutFrom refuses it too; this just keeps the refusal
        -- out of the menu.
        if charKey ~= ns.profileKey and name ~= ns.profileName
            and type(profile) == "table" then
            out[#out + 1] = {
                key = charKey, name = name, bars = #(profile.bars or {}),
            }
        end
    end

    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

-- The bars belonging to a character, by character key. One place, so the
-- copy path does not have to know that a character is a pointer now.
--
-- It went unused for one whole version: CopyLayoutFrom kept reading the
-- pre-migration shape directly and answered "no bars" for every character.
-- The store can be handed in so the self test can assert, against a made-up
-- one, that this and the migration agree about where bars live.
function Profiles:BarsOfCharacter(charKey, store)
    store = store or Store()
    local name = store.charProfile and store.charProfile[charKey]
    local profile = type(name) == "string" and store.profiles
        and store.profiles[name]
    return type(profile) == "table" and profile.bars or nil
end

---------------------------------------------------------------------------
-- Changing what is in use
--
-- All four of these end in Reload, because every one of them changes what
-- ns.db points at or what is inside it, and nothing on screen re-reads that
-- by itself.
---------------------------------------------------------------------------

-- A name a person typed. Trimmed, and refused when empty - a profile called
-- "   " is one nobody can pick out of a list again.
function Profiles.CleanName(name)
    if type(name) ~= "string" then return nil end
    name = name:match("^%s*(.-)%s*$")
    if name == "" then return nil end
    if #name > 64 then name = name:sub(1, 64) end
    return name
end

function Profiles:Use(name)
    name = Profiles.CleanName(name)
    if not name then return false, "that name is empty" end

    local store = Store()
    if store.profiles[name] == nil then return false, "there is no profile called that" end
    if name == ns.profileName then return false, "that one is already in use" end

    store.charProfile[ns.profileKey] = name
    ns.OpenProfile()
    self:Reload()
    return true
end

-- copyFrom nil means a fresh one at the defaults. Copying is a DEEP copy on
-- purpose: two profiles sharing a table would be one profile with two names,
-- and the second one to be edited would silently change the first.
function Profiles:Create(name, copyFrom)
    name = Profiles.CleanName(name)
    if not name then return false, "that name is empty" end

    local store = Store()
    if store.profiles[name] ~= nil then return false, "there is already one called that" end

    local fresh
    if copyFrom and store.profiles[copyFrom] then
        fresh = ns.Share.DeepCopy(store.profiles[copyFrom])
    else
        fresh = {}
    end
    store.profiles[name] = fresh

    store.charProfile[ns.profileKey] = name
    ns.OpenProfile()
    self:Reload()
    return true
end

function Profiles:Rename(from, to)
    to = Profiles.CleanName(to)
    if not to then return false, "that name is empty" end

    local store = Store()
    if store.profiles[from] == nil then return false, "there is no profile called that" end
    if from == to then return false, "that is the same name" end
    if store.profiles[to] ~= nil then return false, "there is already one called that" end

    store.profiles[to] = store.profiles[from]
    store.profiles[from] = nil

    -- EVERY character pointing at the old name, not just this one. Missing
    -- one would leave an alt pointing at a profile that no longer exists, and
    -- it would silently get a brand new empty one on its next login.
    for charKey, name in pairs(store.charProfile) do
        if name == from then store.charProfile[charKey] = to end
    end

    ns.OpenProfile()
    self:Reload()
    return true
end

function Profiles:Delete(name)
    local store = Store()
    if store.profiles[name] == nil then return false, "there is no profile called that" end

    -- The last one cannot go. Something has to be in use, and an addon that
    -- can be left with no settings at all is one that greets you with an
    -- empty screen and no way back.
    local count = 0
    for _ in pairs(store.profiles) do count = count + 1 end
    if count <= 1 then return false, "this is the only profile there is" end

    store.profiles[name] = nil

    -- Anyone left pointing at it - including possibly this character - is
    -- unassigned, and picks up a profile named after itself on its next
    -- login. Done by clearing rather than by choosing a replacement for
    -- somebody who is not here to be asked.
    for charKey, used in pairs(store.charProfile) do
        if used == name then store.charProfile[charKey] = nil end
    end

    ns.OpenProfile()
    self:Reload()
    return true
end

---------------------------------------------------------------------------
-- PUTTING THE SCREEN BACK TOGETHER after ns.db has moved.
--
-- The same sequence ADDON_LOADED runs, minus the seeding: a profile that was
-- deliberately emptied must not have bars poured back into it. Written once
-- here because /zs reset used to carry its own shorter version of it, and
-- the short version was missing the reminder migration and both spec binds.
---------------------------------------------------------------------------
function Profiles:Reload()
    ns.Bars:Migrate()
    ns.Bars:Prepare()
    if ns.Reminders and ns.Reminders.Migrate then ns.Reminders:Migrate() end

    ns.Bars:BindSpec()
    ns.Bars.boundSpec = nil
    ns.Bars:BindSpec()

    ns.Auras:Invalidate()
    ns.Reminders:Rebuild()

    -- BOTH, and in this order. ApplyLayout moves the rows and re-reads what
    -- each one shows; Refresh fills them in. Calling only the second leaves
    -- the panel the shape the OLD profile gave it.
    ns.CoTanks:ApplyLayout()
    ns.CoTanks:Refresh()

    ns.Bars:Changed()
    if ns.Options and ns.Options.Refresh then ns.Options:Refresh() end
end
