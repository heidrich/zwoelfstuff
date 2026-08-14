---------------------------------------------------------------------------
-- Sounds - the noise four moments make, chosen per SPELL.
--
-- HIS WORDS, AND THE ASYMMETRY IN THEM: "bei requests, reminder und cmd,
-- sounds einstellen koennen. bei den requests auch je nach spell nicht slot
-- und beim cmd auch."
--
-- A KEY BELONGS TO THE PLACE. A SOUND BELONGS TO THE SPELL.
--
-- That is not a detail, it is the whole shape of this file. A keybind is
-- muscle memory for a POSITION - the third button on the panel is F3 whatever
-- is sitting in it today. A sound is recognition of a THING - asking for Pain
-- Suppression and asking for a battle res have to sound different, and which
-- slot they happen to occupy has nothing to do with it. So the panel's keys
-- are stored by slot index and everything here is stored by spell id, and
-- moving a spell to another slot keeps its sound and changes its key.
--
-- THE CHAIN, and every link is a separate check in the self test:
--
--   1. the spell's own sound          sounds[event].spells[spellID]
--   2. the event's sound              sounds[event].any
--   3. the one this addon ships with  BUILT_IN[event], a SoundKit id
--   4. silence
--
-- "None" ANYWHERE STOPS THE CHAIN. It is a real answer - "I do not want a
-- noise here" - and not the absence of one, which is the only way to silence
-- the answer chime that has been playing since 4.60.0 without switching the
-- whole feature off.
--
-- NOTHING NEW MAKES A NOISE ON ITS OWN. Three of the four events ship with no
-- built-in at all, so an existing profile sounds exactly as it did before
-- this file existed. The fourth is the chime Answers has always played, and
-- it is named here rather than buried in that file so all four are in one
-- list. An update that starts making a noise nobody asked for is an update
-- people switch off.
---------------------------------------------------------------------------
local _, ns = ...

local Sounds = {}
ns.Sounds = Sounds

-- The four moments. One list, so the options page and the resolver cannot
-- disagree about what exists - the same argument as ns.LAYOUTS.
--
-- `text` is English on purpose and looked up through L at DRAW time, never
-- here: at file scope the profile is not open yet and the answer would be
-- English and then frozen for the session. See the top of Core/Locale.lua.
Sounds.EVENTS = {
    { key = "request",  text = "When you ask for a cooldown" },
    { key = "asked",    text = "When somebody asks you" },
    { key = "ready",    text = "When a cooldown comes back" },
    { key = "reminder", text = "When a reminder appears" },
}

-- What plays when nothing has been chosen. A SoundKit id, not a file - these
-- are the client's own and exist on every machine whatever else is installed.
--
-- ONLY ONE ENTRY, and it is deliberate. 8959 is the raid-warning chime
-- Core/Answers.lua has always played when a request arrives; it moved here so
-- that all four events are described in one place and so that "None" can
-- silence it. The other three are absent, which is what makes this file
-- inaudible until somebody picks something.
local BUILT_IN = {
    asked = 8959,
}

-- Which channel. "Master" so it is heard with the game's sound effects turned
-- down, which is how most people play - a warning nobody hears is not a
-- warning. Blizzard's own raid warnings do the same.
local CHANNEL = "Master"

---------------------------------------------------------------------------
-- The store
--
-- NOT IN ns.DEFAULTS, and the comment in Core/Init.lua about the externals
-- channels says why: this is a per-spell table, and ApplyDefaults fills in
-- whatever is MISSING. A seeded entry would be poured back in at every login
-- over a sound somebody deliberately cleared, and no amount of clicking would
-- keep it off. So it is seeded here, once, the way Answers.Config does it.
---------------------------------------------------------------------------
function Sounds.Config()
    if not ns.db then return nil end

    local cfg = ns.db.sounds
    if type(cfg) ~= "table" then
        cfg = {}
        ns.db.sounds = cfg
    end

    for _, event in ipairs(Sounds.EVENTS) do
        local entry = cfg[event.key]
        if type(entry) ~= "table" then
            entry = {}
            cfg[event.key] = entry
        end
        if type(entry.spells) ~= "table" then entry.spells = {} end
    end

    return cfg
end

function Sounds.IsEvent(event)
    for _, entry in ipairs(Sounds.EVENTS) do
        if entry.key == event then return true end
    end
    return false
end

function Sounds.BuiltIn(event)
    return BUILT_IN[event]
end

---------------------------------------------------------------------------
-- The chain
--
-- PURE, and it takes the book rather than reading ns.db, so the self test can
-- drive every link with a table it made itself. Same reason Locale.Resolve
-- takes the client's locale instead of asking for it.
--
-- Returns the CHOSEN NAME or nil, and never the built-in: what a name means
-- is this function's business and what a missing one means is Play's. Two
-- jobs in one return value is how a resolver starts lying about which link
-- answered.
---------------------------------------------------------------------------
function Sounds.Choice(book, event, spellID)
    local entry = book and book[event]
    if not entry then return nil end

    -- An empty string is what a picker writes for "no answer of my own", so
    -- it has to fall through rather than count as a choice. "None" does NOT
    -- fall through - it is the answer "silence".
    local own = spellID and entry.spells and entry.spells[spellID]
    if own and own ~= "" then return own end

    local any = entry.any
    if any and any ~= "" then return any end

    return nil
end

---------------------------------------------------------------------------
-- The throttle
--
-- Five cells on a bar can come back within the same tick, and five copies of
-- one chime is a noise nobody keeps switched on. Per EVENT rather than per
-- sound: what is being throttled is "this kind of thing happened", and two
-- different sounds landing together is the same racket as two of one.
--
-- Pure, with its clock handed in, because the alternative is a test that
-- waits. Same shape as Taunts.MaySpeak - see the note there.
---------------------------------------------------------------------------
Sounds.GAP = 0.35

function Sounds.MayPlay(now, previous, gap)
    if not previous then return true end
    return (now - previous) >= (gap or Sounds.GAP)
end

local lastAt = {}

---------------------------------------------------------------------------
-- Playing it
--
-- The one sink. Everything above is arithmetic on names; this is the only
-- place that makes a noise, so there is one answer to "which channel", one
-- guard for a client that has no PlaySoundFile, and one throttle.
---------------------------------------------------------------------------
function Sounds.Play(event, spellID)
    local book = Sounds.Config()
    if not book then return false end

    local name = Sounds.Choice(book, event, spellID)

    -- SILENCE IS AN ANSWER. Asked for explicitly, it beats the built-in -
    -- which is the only way to turn the answer chime off without turning the
    -- answers off with it.
    if name == "None" then return false end

    local now = GetTime and GetTime() or 0
    if not Sounds.MayPlay(now, lastAt[event]) then return false end

    local played = false
    if name then
        played = ns.Media.PlaySound(name, CHANNEL)
    else
        local kit = BUILT_IN[event]
        if kit and PlaySound then
            played = pcall(PlaySound, kit, CHANNEL) and true or false
        end
    end

    -- Only a sound that actually went out starts the clock. A name pointing
    -- at a file from an addon that has since been uninstalled must not
    -- silence the next four seconds as well.
    if played then lastAt[event] = now end
    return played
end

-- The picker's preview: play it now, whatever the throttle thinks. Somebody
-- clicking through a list of sounds is asking to hear each one.
function Sounds.Preview(name)
    if not name or name == "" or name == "None" then return false end
    return ns.Media.PlaySound(name, CHANNEL)
end

---------------------------------------------------------------------------
-- What the options page writes
--
-- Reading and writing both go through here so no page has to know that an
-- empty string means "follow" and that an empty table has to be tidied away.
---------------------------------------------------------------------------
function Sounds.Get(event, spellID)
    local book = Sounds.Config()
    local entry = book and book[event]
    if not entry then return "" end
    if spellID then return entry.spells[spellID] or "" end
    return entry.any or ""
end

function Sounds.Set(event, spellID, name)
    local book = Sounds.Config()
    local entry = book and book[event]
    if not entry then return false end

    if name == "" then name = nil end

    if spellID then
        entry.spells[spellID] = name
    else
        entry.any = name
    end
    return true
end

---------------------------------------------------------------------------
-- WHAT IS ACTUALLY IN THE REGISTRY, and what each moment resolves to.
--
-- Worth a command of its own, because the answer is not knowable from here:
-- LibSharedMedia registers exactly ONE sound by itself - "None" - and
-- everything else in the list arrives from whatever OTHER addons are
-- installed. So a picker that looks empty is usually a correct picker on a
-- machine with nothing in it, and telling those two apart by looking at the
-- dropdown is impossible. Measured at a desk: a client with only this addon
-- offers one entry.
--
-- This addon deliberately ships no sound files of its own. The argument is
-- the one at the top of Core/Media.lua: a registry is not a design, and a
-- second unfamiliar set of noises is not what somebody who already has
-- BigWigs wants. What it owes them instead is to SAY so.
---------------------------------------------------------------------------
function Sounds:Dump()
    local say = ns.Print or print
    local list = ns.Media.List("sound")

    say(string.format("|cffffd100%d sounds|r in the shared registry.",
        #list))
    for _, name in ipairs(list) do
        local path = ns.Media.Sound(name)
        say(string.format("   %s  |cff888888%s|r", tostring(name),
            type(path) == "string" and path or "the game's own"))
    end

    if #list <= 1 then
        say("|cffffd100Only the empty one.|r Sounds come from whatever other "
            .. "addons you have - BigWigs, Northern Sky and WeakAuras all "
            .. "register theirs. This addon ships none on purpose.")
    end

    say(" ")
    for _, event in ipairs(Sounds.EVENTS) do
        local chosen = Sounds.Choice(Sounds.Config(), event.key)
        local kit = BUILT_IN[event.key]
        local answer
        if chosen == "None" then
            answer = "|cff888888silent, on purpose|r"
        elseif chosen then
            answer = "|cff40ff40" .. chosen .. "|r"
        elseif kit then
            answer = string.format("the built-in chime (%d)", kit)
        else
            answer = "|cff888888nothing|r"
        end
        say(string.format("%-34s %s", event.text, answer))

        local entry = Sounds.Config() and Sounds.Config()[event.key]
        for spellID, name in pairs(entry and entry.spells or {}) do
            say(string.format("     %s |cff888888(%d)|r -> %s",
                ns.SpellName(spellID) or "?", spellID, tostring(name)))
        end
    end
end

-- Is anything set at all? Drives whether a page offers "clear them all",
-- so it is not a button that does nothing on a profile nobody has touched.
function Sounds.HasAny(event)
    local book = Sounds.Config()
    local entry = book and book[event]
    if not entry then return false end
    if entry.any and entry.any ~= "" then return true end
    return next(entry.spells) ~= nil
end
