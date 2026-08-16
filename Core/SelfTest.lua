---------------------------------------------------------------------------
-- SelfTest - /zs test
--
-- WHY AN ADDON SHIPS ITS OWN TEST SUITE.
--
-- Nothing in here can be run outside the game. There is no WoW without a
-- client, so a rule about arrangement geometry either gets checked where the
-- code actually runs or it gets checked by a person squinting at a screenshot
-- and reporting "sieht strange aus". This file is the first option.
--
-- It answers the questions a screenshot cannot: does switching pattern and
-- switching back give you what you had, does the Columns slider lose a spell,
-- does the editor's explanation agree with the rule the renderer applies.
-- Every one of those has been a real bug in this addon.
--
-- IT NEVER TOUCHES YOUR SETTINGS.
--
-- Every model test runs on a throwaway config it builds itself, so a suite
-- cannot leave anything behind in your profile. The checks against YOUR
-- data are read-only and say so.
---------------------------------------------------------------------------
local _, ns = ...

local Test = {}
ns.SelfTest = Test

local passed, failed, notes

local function Check(name, ok, detail)
    if ok then
        passed = passed + 1
        return true
    end
    failed[#failed + 1] = detail and (name .. "  |cff888888" .. detail .. "|r")
        or name
    return false
end

-- Something the test could not judge either way. Reported separately, because
-- a suite that silently skips is a suite that reports green while covering
-- nothing.
local function Skip(name, why)
    notes[#notes + 1] = name .. "  |cff888888" .. why .. "|r"
end

local function Near(a, b, tolerance)
    return math.abs((a or 0) - (b or 0)) <= (tolerance or 0.01)
end

local function Finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

-- SOMETHING THAT CAN BE SHOWN OR HIDDEN, and nothing more than that.
--
-- It used to be a throwaway BAR, filled from the bar defaults. The rules
-- outlived the bars: a reminder carries the same show block, which is why
-- Visibility is still here at all. So the fixture is written out rather than
-- taken from a defaults table - it says what the rule engine actually reads,
-- and it cannot quietly gain a field the engine never asked about.
-- PRETENDING TO BE A SPECIALISATION, in one place.
--
-- Settings that belong to the spec are checked in three suites now, and every
-- one of them has to answer the same three questions: this spec, another spec
-- of the same class, and the moment after login where the client has not said
-- yet. Written out eight times, the third case is the one that gets forgotten
-- - and it is the case that loses data.
--
-- Returns what was there before, so a suite can put the real one back.
local function PretendSpec(key, known)
    local was = ns.SpecKey
    ns.SpecKey = function() return key, known ~= false end
    return was
end

---------------------------------------------------------------------------
-- A PROFILE THAT IS NOT HIS, FOR EVERYTHING THAT WRITES
--
-- Owner's client, 2026-08-15: eight red checks that were all green on the
-- desk, and one cause under every one of them.
--
-- A setting that belongs to the spec is not a value on the profile any more,
-- it is a VIEW: ns.Externals.Config() re-points cfg.cells at the table for
-- the spec being played, on every single call. So the old opening move -
-- "remember cfg.cells, put an empty one there, do the test, put the
-- remembered one back" - stopped working the day the slots moved. The empty
-- table was thrown away by the next reader, and every Pick, SetSlot and
-- ClearSlot after it went into HIS panel. The restore at the end could not
-- notice: what it saved and what it wrote through had become the same table.
-- It cost him a spell out of slot 3.
--
-- The fix is not a more careful restore. It is not writing there at all.
--
-- `body` runs against a profile built for it, with the defaults applied and
-- a spec that is ANSWERED - so the per-spec path is exercised rather than
-- skipped, which is the other half of what went wrong: the desk harness has
-- no specialisation, ns.SpecStore returns nil out there, and none of this
-- code ran until it reached a real client.
--
-- Wrapped in pcall on purpose. An error escaping with ns.db still swapped
-- would leave the running game pointed at a fixture - the one failure this
-- helper must not be able to cause.
---------------------------------------------------------------------------
local function OnStandInProfile(externals, body)
    local realDB, realKey = ns.db, ns.SpecKey
    local stand = { externals = externals or {} }
    ns.ApplyDefaults(stand, ns.DEFAULTS)
    ns.db = stand
    ns.SpecKey = function() return "DEATHKNIGHT:250", true end

    local ok, err = pcall(body, stand)

    ns.db, ns.SpecKey = realDB, realKey
    -- The panel on screen was drawn from the stand-in while that ran; this
    -- puts his own back on it.
    if ns.Externals and ns.Externals.Refresh then ns.Externals.Refresh() end

    if not ok then Check("The stand-in profile ran to the end", false, tostring(err)) end
    return ok
end

local function Fresh(overrides)
    local cfg = {
        enabled = true,
        show = {
            mode    = "always",
            combat  = "any",
            target  = "any",
            group   = "any",
            resting = "any",
            where   = { none = true, party = true, raid = true,
                        scenario = true, pvp = true, arena = true },
            specs   = {},
        },
    }
    for key, value in pairs(overrides or {}) do cfg[key] = value end
    return cfg
end

---------------------------------------------------------------------------
-- The slider's arithmetic
--
-- Extracted from the control on purpose. The harness CANNOT see a geometry
-- bug - its frame stub answers GetWidth with a fixed number whatever was set,
-- so a track built at the wrong width tests exactly like a right one. What it
-- CAN see is the arithmetic, so the arithmetic stands on its own and is
-- checked here.
---------------------------------------------------------------------------
local function TestSliderMaths()
    local Snap, Frac, At = ns.UI.SliderSnap, ns.UI.SliderFraction, ns.UI.SliderValueAt

    -- The ends hold, from both directions and from nonsense.
    Check("Below the range comes back as the minimum", Snap(0, 100, 1, -40) == 0)
    Check("Above the range comes back as the maximum", Snap(0, 100, 1, 900) == 100)
    Check("A non-number is the minimum, not an error", Snap(16, 100, 2, nil) == 16)

    -- ROUNDING TO THE NEAREST STEP CAN LAND PAST THE END. 0..1 by .4 rounds a
    -- typed 1 up to 1.2, and the old code clamped only BEFORE snapping - so it
    -- handed back a value its own track had no room to draw. This is the check
    -- that goes red if the second clamp is ever taken out again.
    Check("A step that does not divide the range still ends at the maximum",
        Snap(0, 1, 0.4, 1) <= 1, tostring(Snap(0, 1, 0.4, 1)))

    -- Snapping accumulates float noise, and the box shows this number.
    Check("Twenty steps of .05 from 0 is exactly 1", Snap(0, 1, 0.05, 1) == 1)
    Check("A value between steps takes the nearer one", Snap(0, 100, 10, 24) == 20)
    Check("Exactly halfway rounds up", Snap(0, 100, 10, 25) == 30)

    -- Value and fraction have to be each other's inverse, or the knob sits
    -- somewhere the number does not.
    Check("The minimum is the left end", Near(Frac(0.4, 2.5, 0.4), 0))
    Check("The maximum is the right end", Near(Frac(0.4, 2.5, 2.5), 1))
    Check("Halfway is halfway", Near(Frac(0, 100, 50), 0.5))
    Check("A fraction outside 0..1 is pulled in", Frac(0, 100, -20) == 0
        and Frac(0, 100, 300) == 1)

    -- A range with no span must not divide by zero - it happens whenever a
    -- setting is temporarily pinned to one value.
    Check("A range of nothing answers 0 rather than throwing", Frac(5, 5, 5) == 0)

    local roundTrip = true
    for _, value in ipairs({ 16, 30, 44, 68, 100 }) do
        if At(16, 100, 2, Frac(16, 100, value)) ~= value then roundTrip = false end
    end
    Check("A value survives the trip through its own fraction", roundTrip)

    Check("Dragging past either end stays inside", At(0, 1, 0.05, -3) == 0
        and At(0, 1, 0.05, 4) == 1)

    ---------------------------------------------------------------------
    -- The rail still holds every entry
    --
    -- This is the sum that stops a page being added and the LAST rail entry
    -- quietly disappearing behind the foot. It is not hypothetical: it
    -- happened while that column was being drawn, and a rail that clips looks
    -- exactly like a rail that is simply full.
    --
    -- It replaces the old RailArtHeight check. That one asked how much room
    -- was LEFT OVER for the lit cap; the cap is gone (owner: "lass den
    -- verlauf weg") and the question that was actually worth asking is this
    -- one.
    ---------------------------------------------------------------------
    local Fits = ns.UI.RailFits

    -- The real window: rail 758, head 62, foot 38, and the block of outward
    -- links between the nav and that foot.
    --
    -- TAIL IS ASKED FOR, NOT TYPED. It was a copy - one nav row plus air -
    -- and it stayed that number while the window grew to three shorter rows,
    -- so this check was quietly agreeing with a layout that no longer
    -- existed. ns.Options.RailTail is what the window itself lays out to.
    local TAIL = ns.Options.RailTail()
    local navNow = ns.UI.NAV_ITEM_H * (#ns.Options.PAGES + 1) + 4 * 38

    -- THE RAIL IS THE WINDOW LESS ITS OWN EDGE, and it is asked for rather
    -- than typed. It was 758 in four places here while UI.WINDOW_H said 760,
    -- and the raid bar wave then made the window taller - at which point four
    -- correct numbers would all have been wrong at once, and this check would
    -- have gone on agreeing with a window that no longer existed. That is the
    -- exact fault the TAIL line above was written to fix.
    local RAIL = ns.UI.WINDOW_H - 2

    Check("Today's rail holds every entry", Fits(RAIL, 62, 38, TAIL, navNow),
        string.format("nav %d of %d", navNow, RAIL - 62 - 38 - TAIL))

    -- The sum rather than a number: the first draft of the check this replaces
    -- guessed 700 and went red against correct code.
    local room = RAIL - 62 - 38 - TAIL
    Check("A nav that fills the column exactly still fits",
        Fits(RAIL, 62, 38, TAIL, room))
    Check("One row more than fits is reported as not fitting",
        not Fits(RAIL, 62, 38, TAIL, room + 1))

    -- The margin is worth naming, because it is what a new page spends. Two
    -- more pages must still fit, or the next feature lands on a broken rail
    -- and nobody finds out until a screenshot arrives.
    --
    -- IT HAS ALREADY EARNED ITS KEEP ONCE: the raid bar and the invite tool
    -- took the spare down to 8 pixels, which is what made the window taller.
    Check("There is room for two more pages",
        Fits(RAIL, 62, 38, TAIL, navNow + 2 * ns.UI.NAV_ITEM_H),
        string.format("%d spare", room - navNow))
end

---------------------------------------------------------------------------
-- Which noise, for which spell
--
-- HIS RULE: "bei den requests auch je nach spell nicht slot und beim cmd
-- auch." A key belongs to the place, a sound belongs to the spell.
--
-- Four links in the chain and one check per link, in order, each naming the
-- LINK rather than the value - the shape Locale.Resolve's suite uses. The
-- default arm is checked twice on purpose: an unknown value and no value at
-- all are different code paths, and a resolver that copied the default at
-- write time passes the first and fails the second.
---------------------------------------------------------------------------
local function TestSounds()
    local S = ns.Sounds
    if not Check("There is a sound model", S ~= nil) then return end

    ---------------------------------------------------------------------
    -- The chain, driven on a book this test made itself
    ---------------------------------------------------------------------
    local book = {
        request  = { any = "Whistle", spells = { [33206] = "Bell" } },
        ready    = { any = nil,       spells = {} },
        asked    = { any = "None",    spells = { [6940] = "" } },
        reminder = { spells = {} },
    }

    Check("A spell's own sound wins",
        S.Choice(book, "request", 33206) == "Bell",
        tostring(S.Choice(book, "request", 33206)))
    Check("A spell with none of its own follows the event",
        S.Choice(book, "request", 47788) == "Whistle",
        tostring(S.Choice(book, "request", 47788)))
    Check("No spell at all follows the event",
        S.Choice(book, "request", nil) == "Whistle")
    Check("An event with nothing set answers nothing",
        S.Choice(book, "ready", 12345) == nil,
        tostring(S.Choice(book, "ready", 12345)))
    Check("An event nobody has ever touched answers nothing",
        S.Choice(book, "reminder", 12345) == nil)
    Check("An event this addon does not have answers nothing",
        S.Choice(book, "nonsense", 12345) == nil)

    -- THE EMPTY STRING IS WHAT A PICKER WRITES FOR "no answer of my own", so
    -- it has to fall THROUGH. "None" must not: it is the answer "silence",
    -- and the two being confused is how a chime becomes unsilenceable.
    Check("An empty choice falls through to the event",
        S.Choice(book, "asked", 6940) == "None",
        tostring(S.Choice(book, "asked", 6940)))
    Check("'None' is an answer, not the absence of one",
        S.Choice(book, "asked", nil) == "None")

    ---------------------------------------------------------------------
    -- What ships. Two of three silent, and the third is the chime that was
    -- already playing - an update that starts making a noise nobody asked
    -- for is an update people switch off.
    --
    -- FOUR AGAIN. It was three while the bars were out - "when a cooldown
    -- comes back" is played by them and by nothing else - and the number is
    -- asserted rather than left open because the failure it catches is a row
    -- in the options that can never make a sound. It caught the other half of
    -- this too, from the desk: Effects played `ready` for a whole build
    -- before anything declared it as a moment.
    ---------------------------------------------------------------------
    Check("Four moments can make a noise", #S.EVENTS == 4,
        tostring(#S.EVENTS))
    for _, event in ipairs(S.EVENTS) do
        Check("'" .. tostring(event.key) .. "' is a known event",
            S.IsEvent(event.key))
        Check("'" .. tostring(event.key) .. "' has something to call it",
            type(event.text) == "string" and event.text ~= "")
    end
    Check("The answer chime is still the answer chime",
        S.BuiltIn("asked") == 8959, tostring(S.BuiltIn("asked")))
    for _, key in ipairs({ "request", "ready", "reminder" }) do
        Check("Nothing new makes a noise on its own: " .. key,
            S.BuiltIn(key) == nil, tostring(S.BuiltIn(key)))
    end

    ---------------------------------------------------------------------
    -- THE PICKER HAS SOMETHING TO OFFER.
    --
    -- A MediaPicker builds its menu when it is CLICKED, so the check that
    -- every menu on every page can be drawn cannot see this one - it would
    -- open blank on the page and nowhere else. That is the failure the
    -- widget's own header calls the worst kind: a control that is silently
    -- unusable. Media.List falls back to { Media.DEFAULT[kind] }, so this
    -- is really asking whether that entry exists at all.
    ---------------------------------------------------------------------
    local list = ns.Media.List("sound")
    Check("The sound picker has something in it", #list > 0,
        string.format("%d entries", #list))
    Check("...and silence is one of the answers",
        ns.Media.DEFAULT.sound == "None", tostring(ns.Media.DEFAULT.sound))

    -- The same hole existed for backgrounds and nobody had opened that
    -- picker yet. Every kind a picker can be pointed at, in one loop.
    for _, kind in ipairs({ "font", "statusbar", "border", "background",
        "sound" }) do
        Check("The " .. kind .. " picker has a floor to fall back to",
            ns.Media.DEFAULT[kind] ~= nil)
    end

    ---------------------------------------------------------------------
    -- SWITCHING A WHOLE PACK OUT OF THE LIST
    --
    -- Owner: "die exwind sounds muessen alle raus oder geblockt werden, das
    -- sind 1000." Two packs on his machine register 188 entries each. Driven
    -- against whatever is really registered here rather than against a made
    -- up one, because registering a fake pack would leave it in the shared
    -- registry for every other addon for the rest of the session.
    ---------------------------------------------------------------------
    local counts, order = ns.Media.Providers("sound")
    local before = #ns.Media.List("sound")

    if #order > 0 then
        local biggest = order[1]
        ns.Sounds.SetMuted(biggest, true)
        local after = #ns.Media.List("sound")
        Check("Switching a pack off takes it out of the picker",
            after == before - counts[biggest],
            string.format("%d - %d gave %d", before, counts[biggest], after))
        Check("...and the pack knows it is off", ns.Sounds.IsMuted(biggest))

        -- EVERY PACK OFF STILL LEAVES SOMETHING TO CLICK. A dropdown with no
        -- rows is the one state a control must never be in, and it would
        -- take away the "None" that means silence.
        for _, who in ipairs(order) do ns.Sounds.SetMuted(who, true) end
        local bare = ns.Media.List("sound")
        Check("With every pack off the picker is still not empty",
            #bare > 0, tostring(#bare))

        for _, who in ipairs(order) do ns.Sounds.SetMuted(who, false) end
        Check("Switching them back on restores the list",
            #ns.Media.List("sound") == before,
            string.format("%d, expected %d", #ns.Media.List("sound"), before))
    else
        Skip("Switching a sound pack out of the picker",
            "no addon here has registered any sounds")
    end

    -- A CHOICE OUTLIVES ITS PACK BEING HIDDEN. The filter decides what is
    -- OFFERED; it must not reach into what was already chosen, or switching
    -- a pack off would silently change what four moments sound like.
    Check("A sound already chosen is not un-chosen by hiding its pack",
        ns.Sounds.Choice({ ready = { any = "[Pack]One", spells = {} } },
            "ready") == "[Pack]One")

    -- "None" is a name, and the sink has to refuse it rather than hand a
    -- number to the client and call it a path.
    Check("Silence is never played", ns.Media.PlaySound("None") == false)
    Check("Nothing at all is never played", ns.Media.PlaySound(nil) == false)
    Check("An empty choice is never played", ns.Media.PlaySound("") == false)

    ---------------------------------------------------------------------
    -- The throttle. Pure, with its own clock, because the alternative is
    -- a test that waits - and because a whole bar can come back at once.
    ---------------------------------------------------------------------
    Check("The first one always plays", S.MayPlay(100, nil))
    Check("A second one in the same tick does not",
        S.MayPlay(100.1, 100) == false)
    Check("A moment later it plays again", S.MayPlay(101, 100))
    Check("The gap can be asked for", S.MayPlay(100.2, 100, 0.1))

    ---------------------------------------------------------------------
    -- Reading and writing, against the real store
    ---------------------------------------------------------------------
    if ns.db then
        local before = ns.db.sounds
        ns.db.sounds = nil

        Check("A profile with no sounds still answers",
            S.Get("request", 33206) == "" and not S.HasAny("request"))

        S.Set("request", nil, "Whistle")
        Check("An event sound is written", S.Get("request") == "Whistle")
        Check("...and the spell that has none reads it as its own nothing",
            S.Get("request", 33206) == "",
            "Get reports what is SET, the chain is Choice's job")
        Check("Something is set now", S.HasAny("request"))

        S.Set("request", 33206, "Bell")
        Check("A spell sound is written", S.Get("request", 33206) == "Bell")
        Check("...and its neighbour is untouched",
            S.Get("request", 47788) == "")
        Check("...and the event's own is untouched",
            S.Get("request") == "Whistle")

        -- Clearing means "follow again", which is how a picker hands a
        -- setting back. The empty string must not survive as a value.
        S.Set("request", 33206, "")
        Check("Clearing a spell goes back to following",
            S.Get("request", 33206) == ""
            and S.Choice(S.Config(), "request", 33206) == "Whistle")

        S.Set("request", nil, "")
        Check("Clearing the event leaves nothing set",
            not S.HasAny("request"))

        ns.db.sounds = before
    else
        Skip("The sound store reads and writes", "no profile is open")
    end
end

---------------------------------------------------------------------------
-- The command list, which two readers share
--
-- The About page draws ns.COMMANDS and the chat help prints it. Before this
-- they were two hand-typed lists, and the second had gone stale: it still
-- advertised /zs text and had never heard of build, modules, report, skin,
-- test, taunt or death. Checked here so it cannot drift apart again.
---------------------------------------------------------------------------
local function TestCommandList()
    local commands = ns.COMMANDS or {}

    Check("There is a command list at all", #commands > 0,
        string.format("%d entries", #commands))

    -- An entry is a HEADING or a COMMAND. One that is both would be drawn
    -- twice, and one that is neither is an empty row nobody can see.
    local shaped, described = true, true
    for _, entry in ipairs(commands) do
        local isGroup = entry.group ~= nil
        local isCommand = entry.cmd ~= nil
        if isGroup == isCommand then shaped = false end
        if isCommand and (entry.text == nil or entry.text == "") then
            described = false
        end
    end
    Check("Every entry is either a heading or a command", shaped)
    Check("Every command says what it does", described)

    -- WHAT THE SLASH HANDLER ACTUALLY ANSWERS TO. A list that names a command
    -- with no handler behind it is worse than a short list - that is why
    -- /zs route came out when Routes was parked, and went back in with its
    -- handler when Routes returned (4.84.0).
    local handled = {
        [""] = true, unlock = true, lock = true, build = true, minimap = true,
        cdm = true, skin = true, text = true, numbers = true, watch = true,
        tanks = true, route = true, routes = true,
        cotanks = true, modules = true, module = true, welcome = true,
        externals = true, external = true, taunt = true, taunts = true,
        reminders = true, reminder = true, death = true, test = true,
        report = true, auras = true, bars = true, reset = true,
        raidbar = true, raid = true, check = true, invite = true,
        invites = true, loca = true, language = true,
        specs = true, spec = true,
        sounds = true, sound = true,
        chat = true, news = true, whatsnew = true,
    }

    local unknown
    for _, entry in ipairs(commands) do
        if entry.cmd then
            -- "/zs auras forget <glowID>" -> "auras"; "/zs" -> "".
            local word = entry.cmd:match("^/zs%s*(%S*)") or ""
            if not handled[word:lower()] then unknown = entry.cmd end
        end
    end
    Check("Every command listed has a handler behind it", unknown == nil,
        unknown and ("no handler for " .. unknown) or nil)

    ---------------------------------------------------------------------
    -- Cutting it into two columns
    ---------------------------------------------------------------------
    local cut = ns.Options.SplitCommands(commands)

    Check("The cut leaves something in both columns",
        cut >= 1 and cut < #commands, string.format("cut after %d of %d",
            cut, #commands))

    -- A heading is a promise that entries follow it. Ending the left column
    -- on one puts the heading at the bottom of one column and everything it
    -- names at the top of the other.
    Check("The left column does not end on a heading",
        commands[cut] ~= nil and commands[cut].group == nil)

    -- Degenerate input must answer rather than throw: an empty list has no
    -- cut, and a single entry cannot be split at all.
    Check("An empty list answers without throwing",
        ns.Options.SplitCommands({}) == 0)
    Check("One entry stays in one column",
        ns.Options.SplitCommands({ { cmd = "/zs", text = "open" } }) == 1)

    ---------------------------------------------------------------------
    -- The in-game changelog, which is the OTHER hand-typed list
    --
    -- CHANGELOG.md is the source of truth and changelog.py renders the page
    -- and the Discord post from it. ns.CHANGELOG is written by hand on top of
    -- that, so it can drift the same way the command list did - and the way
    -- it drifts is the worst one available: shipping a version whose own
    -- Changelog page has never heard of it. The page marks entry 1 as the one
    -- you are running, so if that is not true it says so out loud to every
    -- player who opens it.
    ---------------------------------------------------------------------
    local newest = ns.CHANGELOG and ns.CHANGELOG[1]

    Check("The changelog names the version being shipped",
        newest ~= nil and newest.version == ns.version,
        newest and ("newest entry " .. tostring(newest.version)
            .. ", running " .. tostring(ns.version)) or "no changelog at all")

    -- Newest first is what the page assumes; an entry inserted in the wrong
    -- place puts "installed" on somebody else's release.
    local ordered, empty = true, nil
    local function Rank(version)
        local major, minor, patch = tostring(version):match("(%d+)%.(%d+)%.(%d+)")
        if not major then return -1 end
        return tonumber(major) * 1000000 + tonumber(minor) * 1000 + tonumber(patch)
    end
    for index, entry in ipairs(ns.CHANGELOG or {}) do
        if index > 1 and Rank(entry.version)
            >= Rank(ns.CHANGELOG[index - 1].version) then
            ordered = false
        end
        if not entry.lines or #entry.lines == 0 then empty = entry.version end
    end
    Check("The changelog runs newest first", ordered)
    Check("No release in it is silent", empty == nil,
        empty and (tostring(empty) .. " has no lines") or nil)
end

---------------------------------------------------------------------------
-- Which spell a frame stands for
--
-- Every one of these is a bug that was reported as "it tracks the wrong
-- thing" or "the list makes no sense". They are written so that they do not
-- depend on which class is logged in: the fabricated info tables are plain
-- arguments, and the family checks assert the shape rather than the contents.
---------------------------------------------------------------------------
local function TestSpellIdentity()
    local CDM = ns.CDM
    if not CDM then
        Skip("Spell identity", "the Cooldown Manager layer is not loaded")
        return
    end

    local Usable = CDM.UsableSpellID
    Check("A spell ID has to be a positive whole number",
        Usable(12345) and not Usable(0) and not Usable(-3)
        and not Usable(1.5) and not Usable("12345") and not Usable(nil))

    -- The stale-override guard. 99999999 is not a spell anybody has, so a
    -- resolver that trusts overrideSpellID blindly returns it and the cell
    -- shows an empty icon with no name.
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        Check("An override the player does not have is ignored",
            CDM:InfoSpellID({ overrideSpellID = 99999999, spellID = 12345 }) == 12345)
    else
        Skip("An override the player does not have is ignored",
            "this client cannot answer whether a spell is known")
    end

    Check("A missing override falls through to the spell",
        CDM:InfoSpellID({ spellID = 12345 }) == 12345)
    Check("An override of zero is not an override",
        CDM:InfoSpellID({ overrideSpellID = 0, spellID = 12345 }) == 12345)
    Check("A linked ID is better than nothing",
        CDM:InfoSpellID({ linkedSpellIDs = { 12345 } }) == 12345)
    Check("Nothing usable resolves to nothing",
        CDM:InfoSpellID({}) == nil and CDM:InfoSpellID(nil) == nil)

    -- The family is what lets a stored spell survive its own transform.
    local family = CDM:VariantFamily(12345)
    local hasSelf, clean, duplicate = false, true, false
    local seen = {}
    for _, id in ipairs(family) do
        if id == 12345 then hasSelf = true end
        if not Usable(id) then clean = false end
        if seen[id] then duplicate = true end
        seen[id] = true
    end
    Check("A spell is a member of its own family", hasSelf)
    Check("Every member of a family is a real ID", clean)
    Check("A family lists nothing twice", not duplicate)
    Check("Nothing usable has no family", #CDM:VariantFamily(nil) == 0)

    Check("A spell is the same spell as itself", CDM:SameSpell(12345, 12345))
    -- Two IDs no client has, so "unrelated" is true on every client rather
    -- than true until somebody logs in as the wrong class.
    Check("Two unrelated spells are not the same",
        not CDM:SameSpell(99999998, 99999999))
    Check("Nothing is never the same as something",
        not CDM:SameSpell(nil, 12345) and not CDM:SameSpell(12345, nil))

    -- The rule the whole family exists for, asserted against whatever this
    -- client actually reports rather than an ID picked in advance.
    local transformed = CDM:OverrideSpell(12345) or CDM:BaseSpell(12345)
    if transformed then
        Check("A spell and its other form are the same spell",
            CDM:SameSpell(12345, transformed)
            and CDM:SameSpell(transformed, 12345))
    else
        Skip("A spell and its other form are the same spell",
            "this client reports no other form for the test ID")
    end

    -- The bands. This is what stopped Cooldowns and Utility interleaving.
    local ranks = {}
    for index, viewer in ipairs(CDM.VIEWERS) do
        ranks[index] = CDM:ViewerRank(viewer.key)
    end
    local ascending = true
    for index = 2, #ranks do
        if ranks[index] <= ranks[index - 1] then ascending = false end
    end
    Check("The viewers rank in the order they are listed", ascending)
    Check("The first viewer ranks first", ranks[1] == 0)
    Check("An unknown viewer ranks last",
        CDM:ViewerRank("no such viewer") >= #CDM.VIEWERS)

    -- A band is ten thousand wide, so a viewer would have to show ten
    -- thousand cooldowns before it could reach into the next one.
    local first  = ranks[1] * 10000 + 9999
    local second = ranks[2] and (ranks[2] * 10000) or math.huge
    Check("A viewer's band cannot reach into the next one", first < second)

    -- WHICH HEADING AN ENTRY IS LISTED UNDER.
    --
    -- Above the live check on purpose. Everything below this block needs a
    -- running Cooldown Manager and is skipped on a desktop, which is where
    -- "the picker groups the viewers" has been going unchecked - so the one
    -- part of the answer that is a pure decision is asserted here, where it
    -- runs every time.
    local GroupKeyFor = ns.SpellPane and ns.SpellPane.GroupKeyFor
    if GroupKeyFor then
        -- The spells Blizzard's Cooldown Manager knows but is not currently
        -- displaying. They used to carry a heading of their own that called
        -- them "Not shown by Blizzard", which described Blizzard's settings
        -- panel rather than the spell. They are this spec's cooldowns and
        -- they are listed with the rest.
        Check("Spells Blizzard is not displaying list under Cooldowns",
            GroupKeyFor(CDM.HIDDEN_KEY) == "essential",
            GroupKeyFor(CDM.HIDDEN_KEY))

        -- And every real viewer still keeps its own, or the line above would
        -- have swallowed the whole list into one heading.
        for _, viewer in ipairs(CDM.VIEWERS) do
            Check("Viewer " .. viewer.key .. " keeps its own heading",
                GroupKeyFor(viewer.key) == viewer.key,
                GroupKeyFor(viewer.key))
        end

        -- The catch-all, both ways in. A viewer key a later patch renames must
        -- cost one "Other" row, never a spell that quietly disappears.
        Check("An unknown viewer falls through to Other",
            GroupKeyFor("no such viewer") == "other")
        Check("An entry with no viewer at all falls through to Other",
            GroupKeyFor(nil) == "other")
    end

    -- READ-ONLY, against whatever the Cooldown Manager is holding right now.
    -- The reported symptom was groups interleaving, so the catalogue is asked
    -- whether it ever returns to a viewer it has already left behind.
    if not CDM:IsAvailable() then
        Skip("The picker groups the viewers", "the Cooldown Manager is not up")
        return
    end

    local catalogue = CDM:Catalogue()
    if #catalogue == 0 then
        Skip("The picker groups the viewers", "the catalogue is empty")
        return
    end

    local visited, current, revisited = {}, nil, nil
    local ordered = true
    local previous
    for _, entry in ipairs(catalogue) do
        if entry.viewer ~= current then
            if visited[entry.viewer] then revisited = entry.viewer end
            visited[entry.viewer] = true
            current = entry.viewer
        end
        local order = entry.order
        if order and previous and order < previous then ordered = false end
        if order then previous = order end
    end

    Check("The picker groups the viewers", not revisited,
        revisited and ("comes back to " .. tostring(revisited)) or nil)
    Check("The picker never goes backwards through Blizzard's order", ordered)

    -- BOTH SOURCES RUN, AND NEITHER REPEATS THE OTHER.
    --
    -- The walk used to stop after the arranged source, so every spell the
    -- Cooldown Manager only pools situationally was absent from the picker on
    -- every class. Now the static sets fill in behind it - which is only safe
    -- if a cooldown the arranged pass already spoke for cannot come back
    -- through the second one. Handed the same cooldownID twice, the picker
    -- would list the spell once anyway (it keys by spell) and quietly award it
    -- two positions, so this is the only place the fault is visible.
    local emitted, twice, count = {}, nil, 0
    local arranged, extra, hidden = CDM:ForEachCatalogued(function(cooldownID)
        if emitted[cooldownID] then twice = cooldownID end
        emitted[cooldownID] = true
        count = count + 1
    end)
    Check("No cooldown is catalogued twice", not twice,
        twice and ("cooldown " .. tostring(twice)) or nil)

    -- NOTHING THE WALK SEES IS DROPPED ON THE FLOOR.
    --
    -- The counters and the callback have to agree, and this is the check that
    -- would have caught the real fault: cooldowns Blizzard is not displaying
    -- were COUNTED and never handed over, so a picker with nine entries sat
    -- next to a Cooldown Manager settings panel listing seventy-four. Every
    -- one of the three numbers is now something the caller was told about.
    Check("Every catalogued cooldown reaches the caller",
        count == arranged + extra + hidden,
        string.format("%d handed over, %d+%d+%d counted",
            count, arranged, extra, hidden))
    Check("The catalogue walk reports what each source gave",
        type(arranged) == "number" and type(extra) == "number"
        and type(hidden) == "number")

    -- Not an assertion: with no arrangement read, everything legitimately
    -- comes from the static set, and a fresh login before Blizzard's settings
    -- have been opened is exactly that. It is worth SAYING, because "0 extra"
    -- next to a short list is the signature of the bug this replaced.
    Skip("Catalogue sources", string.format(
        "%d arranged, %d situational, %d not displayed",
        arranged, extra, hidden))
end

---------------------------------------------------------------------------
-- Custom active states
--
-- A window the player declared, for the things Blizzard only shows as a
-- cooldown. Runs on the real account store and puts back what it found, so
-- it is safe against saved data - `restore` may be nil, and writing nil back
-- is the restore, not a skipped one.
--
-- THIS SUITE WAS CUT BY ACCIDENT and that is worth recording. It tests the
-- aura layer and touches no bar, but it sat between two bar suites, so it
-- went out with them - and with the page that wrote the setting gone at the
-- same time, nothing was left pointing at Auras:SetActiveState in either
-- direction. The setting is back on the death log page; this is the guard
-- that says so out loud the next time somebody counts callers.
---------------------------------------------------------------------------
local function TestActiveStates()
    if not (ns.Auras and ns.Auras.SetActiveState) then
        Skip("Active states", "the aura layer is not loaded")
        return
    end

    local store = ns.Auras:ActiveStates()
    local restore = store[12345]

    ns.Auras:SetActiveState(12345, 20)
    Check("A declared window is remembered", ns.Auras:ActiveStateFor(12345) == 20)

    Check("A spell with no window has none", ns.Auras:ActiveStateFor(12346) == nil
        or ns.CDM:SameSpell(12345, 12346))

    -- The whole reason the lookup is variant-aware: the game reports the form
    -- you actually cast, which is not always the form you set the window on.
    local other = ns.CDM:OverrideSpell(12345) or ns.CDM:BaseSpell(12345)
    if other then
        Check("The window follows the spell into its other form",
            ns.Auras:ActiveStateFor(other) == 20)
    else
        Skip("The window follows the spell into its other form",
            "this client reports no other form for the test ID")
    end

    ns.Auras:SetActiveState(12345, 0)
    Check("Zero switches the window off",
        ns.Auras:ActiveStateFor(12345) == nil and store[12345] == nil,
        "an absent key, not a stored zero")

    ns.Auras:SetActiveState(12345, 15)
    ns.Auras:SetActiveState(12345, 30)
    Check("Changing the number takes effect at once",
        ns.Auras:ActiveStateFor(12345) == 30,
        "the variant cache has to be dropped on every write")

    Check("Nothing usable is never given a window",
        ns.Auras:ActiveStateFor(nil) == nil)

    -- AND THE REPLAY ACTUALLY READS IT, which is the half the old suite did
    -- not cover and the half that broke. A number the player states is only
    -- worth storing if the thing that draws the bar asks for it first - so
    -- the guard is on the reader, not on the store.
    if ns.Replay and ns.Replay.DurationOf then
        ns.Auras:SetActiveState(12345, 42)
        local seconds, source = ns.Replay.DurationOf(12345)
        Check("The replay takes the stated window before anything else",
            seconds == 42 and source == "set",
            "got " .. tostring(seconds) .. " from " .. tostring(source))
    end

    store[12345] = restore
    ns.ForgetActiveStates()
    Check("The test put the real store back",
        ns.Auras:ActiveStates()[12345] == restore)
end

---------------------------------------------------------------------------
-- The visibility rules
---------------------------------------------------------------------------
local function TestVisibility()
    local cfg = Fresh()
    Check("A fresh bar is visible", ns.Visibility:Evaluate(cfg))
    Check("A visible bar has nothing to explain",
        ns.Visibility:Explain(cfg) == nil)

    local never = Fresh()
    never.show.mode = "never"
    Check("'Never' hides", not ns.Visibility:Evaluate(never))
    Check("'Never' says why", ns.Visibility:Explain(never) ~= nil)

    local off = Fresh({ enabled = false })
    Check("A switched-off bar is hidden", not ns.Visibility:Evaluate(off))

    -- THE INVARIANT: the editor's explanation and the renderer's decision are
    -- the same answer. They were not, for instance types this addon has never
    -- heard of - the editor named a reason the renderer did not apply.
    local agree = true
    for _, mode in ipairs({ "always", "rules", "never" }) do
        for _, combat in ipairs({ "any", "in", "out" }) do
            for _, group in ipairs({ "any", "solo", "party", "raid" }) do
                local probe = Fresh()
                probe.show.mode, probe.show.combat, probe.show.group =
                    mode, combat, group
                local visible = ns.Visibility:Evaluate(probe)
                local why = ns.Visibility:Explain(probe)
                if visible == (why ~= nil) then agree = false end
            end
        end
    end
    Check("Every rule explains itself the way it is applied", agree)

    -- WHAT THE LIST IS ALLOWED TO SAY.
    --
    -- The card in the bar list carries a badge for a bar that is not on
    -- screen, and that list is redrawn when you change something in it - not
    -- when you pull, take a target or zone in. So Fixed may only hand back
    -- reasons that outlive the moment, and it may not word them itself.
    Check("A switched-off bar says so in the list",
        ns.Visibility:Fixed(off) ~= nil)
    Check("The list and the panel word it the same way",
        ns.Visibility:Fixed(off) == ns.Visibility:Explain(off))
    Check("'Never' is settled enough for the list",
        ns.Visibility:Fixed(never) ~= nil)

    -- WAITING FOR THE COMBAT STATE WE ARE NOT IN. Written as a literal "in"
    -- it asserted the world: run during a fight, a bar waiting for combat IS
    -- on screen, Explain answers nil, and the check went red on a healthy
    -- client - his paste, five reds, all of them combat. The fixture now
    -- waits for whichever state is not the current one, which is the same
    -- claim in both worlds.
    local pull = Fresh()
    pull.show.mode = "rules"
    pull.show.combat = (InCombatLockdown and InCombatLockdown()) and "out" or "in"
    Check("A bar waiting for combat is explained but not badged",
        ns.Visibility:Explain(pull) ~= nil and ns.Visibility:Fixed(pull) == nil)

    -- And the badge cannot lie: everything it appears on really is off screen.
    local honest = true
    for _, probe in ipairs({ cfg, off, never, pull }) do
        if ns.Visibility:Fixed(probe) and ns.Visibility:Evaluate(probe) then
            honest = false
        end
    end
    Check("Nothing badged as hidden is on screen", honest)

    -- Alpha follows the answer, and the ghost setting is honoured.
    local ghost = Fresh()
    ghost.show.mode = "never"
    ghost.show.hiddenAlpha = 0.3
    Check("A hidden bar uses its own faded alpha",
        Near(ns.Visibility:Factor(ghost), 0.3))
end

---------------------------------------------------------------------------
-- Media
--
-- Every name this addon puts in the shared registry has to come back out of
-- it. That is exactly the failure that shipped once: twenty textures were
-- registered and the files were written outside the addon folder, so the list
-- was full of names pointing at nothing.
--
-- What this CANNOT check is whether the file itself loads - there is no way
-- to ask the client that from Lua. Said out loud rather than implied.
---------------------------------------------------------------------------
local function TestMedia()
    local missing = 0
    local count = 0

    for _, name in ipairs(ns.Media.List("statusbar")) do
        if name:sub(1, 3) == "ZS " then
            count = count + 1
            local path = ns.Media.Statusbar(name)
            if type(path) ~= "string" or not path:find("ZwoelfStuff") then
                missing = missing + 1
            end
        end
    end

    Check("Every shipped bar texture is in the registry", missing == 0,
        string.format("%d of %d resolve to nothing", missing, count))
    Check("The shipped textures are actually registered", count >= 20,
        string.format("found %d", count))

    Skip("Whether each texture FILE loads",
        "the client does not answer that question - look at the picker")
end

---------------------------------------------------------------------------
-- Your own bars. Read-only.
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Cast history - the estimate the death window
-- colour their answers with. The rule has one trap worth pinning: nil and 0
-- are different answers ("cannot tell" against "ready"), and a caller that
-- collapses them calls every unknown spell ready.
---------------------------------------------------------------------------
local function TestHistory()
    local History = ns.History
    if not History then
        Skip("Cast history", "History.lua did not load")
        return
    end

    Check("Still cooling is the seconds left",
        History.Remaining(100, 60, 130) == 30)
    Check("Elapsed answers exactly 0", History.Remaining(100, 60, 160) == 0)
    Check("Long past stays 0, never negative",
        History.Remaining(100, 60, 1000) == 0)
    Check("Never cast answers nil, not 0",
        History.Remaining(nil, 60, 130) == nil)
    Check("No known cooldown answers nil, not 0",
        History.Remaining(100, nil, 130) == nil)
    Check("A zero-length cooldown answers nil - there is nothing to estimate",
        History.Remaining(100, 0, 130) == nil)

    local last, casts = {}, {}
    for i = 1, 7 do History.Push(last, casts, 100 + i, i, 5) end
    Check("The ring keeps the cap and no more", #casts == 5)
    Check("The oldest fall out, the newest stay",
        casts[1].spellID == 103 and casts[5].spellID == 107)
    History.Push(last, casts, 103, 99, 5)
    Check("The map remembers only the newest cast of a spell",
        last[103] == 99)

    -----------------------------------------------------------------------
    -- HOW LONG A DEFENSIVE WAS UP, measured. The replay drew every press
    -- as a stub because its only source was a number nobody types in. So
    -- the window between a tracked buff going up and going down is
    -- recorded while it happens - our own clock over a value this patch
    -- withholds, exactly as the proc recorder works.
    -----------------------------------------------------------------------
    local windows = {}
    Check("A window shorter than a flicker is not a reading",
        History.PushActive(windows, 871, 100, 100.2, 10) == false
            and #windows == 0)
    Check("A window that never closed is not a reading either",
        History.PushActive(windows, 871, 100, 400, 10) == false)
    Check("A real window is kept",
        History.PushActive(windows, 871, 100, 108, 10) == true
            and windows[1].from == 100 and windows[1].to == 108)

    Check("The press finds the window it opened",
        (function()
            local from, to = History.WindowFor(windows, {}, 871, 99.8)
            return from == 100 and to == 108
        end)())
    Check("A window from another fight is not that press's window",
        History.WindowFor(windows, {}, 871, 60) == nil)
    Check("Another spell's window is never borrowed",
        History.WindowFor(windows, {}, 12345, 99.8) == nil)
    Check("A talented form of the same spell still finds it",
        (function()
            local from = History.WindowFor(windows, {}, 12345, 99.8, { 871 })
            return from == 100
        end)())

    -- Pressed twice in one fight: each press gets ITS window, not both the
    -- first one - the reason the search runs newest first.
    History.PushActive(windows, 871, 200, 209, 10)
    Check("Two presses of one spell keep their own windows",
        (function()
            local from = History.WindowFor(windows, {}, 871, 199.9)
            return from == 200
        end)())

    Check("A buff still up answers with no end, which means 'to the death'",
        (function()
            local from, to = History.WindowFor({}, { [871] = 300 }, 871, 299.8)
            return from == 300 and to == nil
        end)())

    local measured = {}
    History.NoteMeasured(measured, 871, 8.04)
    Check("A measured length is kept to a tenth", measured[871] == 8)
    History.NoteMeasured(measured, 871, 5)
    Check("A shorter reading never shortens what was already seen",
        measured[871] == 8)
    History.NoteMeasured(measured, 871, 12)
    Check("A longer reading wins - a window can be cut short, never grown",
        measured[871] == 12)
    History.NoteMeasured(measured, 871, 999)
    Check("A reading that never closed is not stored", measured[871] == 12)

    -----------------------------------------------------------------------
    -- THE NUMBER IN THE TOOLTIP. The owner: "viele def cds haben FESTE
    -- zeiten, die auch so in den tooltips stehen". Reading it is asking the
    -- client, not guessing - but the WORD for "seconds" has to come from
    -- the client as well, or this works in English and nowhere else. He
    -- plays German.
    -----------------------------------------------------------------------
    local words = ns.DurationWords({ "%d |4Sekunde:Sekunden;", "%d |4Sek.:Sek.;" })
    Check("Both forms of the word come out of the client's own format",
        (function()
            local found = {}
            for _, word in ipairs(words) do found[word] = true end
            return found["sekunde"] and found["sekunden"] and found["sek."]
        end)())
    Check("The longest word is tried first, so a short one cannot cut it off",
        #words[1] >= #words[#words])

    Check("A German description answers in seconds",
        ns.DurationInText("Umgibt Euch 5 Sek. lang mit einer Hülle.",
            words) == 5)
    Check("An English one does too",
        ns.DurationInText("Reduces damage taken for 8 sec.",
            ns.DurationWords({ "%d sec" })) == 8)
    Check("Minutes are converted, not read as seconds",
        ns.DurationInText("Lasts 2 min.", ns.DurationWords({ "%d min" }), 60)
            == 120)
    Check("A dot in the word is a dot, not 'any character'",
        ns.DurationInText("12 Sekx", ns.DurationWords({ "%d |4Sek.:Sek.;" }))
            == nil)
    Check("A description with no duration in it says so",
        ns.DurationInText("Erhöht Euren Schaden um 30%.", words) == nil)
    Check("Text that is not text is not parsed",
        ns.DurationInText(nil, words) == nil)
end

---------------------------------------------------------------------------
-- Death analysis - pure rules over a made-up recap. The capture path makes
-- every field readable before this runs, so the analysis owes no guards -
-- what it owes is the right sentence for each shape of death.
---------------------------------------------------------------------------
local function TestDeath()
    local Death = ns.Death
    if not Death then
        Skip("Death analysis", "Death.lua did not load")
        return
    end

    -- One big hit out of small ones: the verdict names it, with the share
    -- of health it took.
    local oneShot = Death.Analyse({
        { t = 4.0, amount = 50000,  heal = false, name = "Scratch" },
        { t = 1.2, amount = 900000, heal = false, name = "Crushing Blow" },
        { t = 0.0, amount = 60000,  heal = false, name = "Scratch" },
    }, 2000000, {}, {})
    Check("The biggest hit is found",
        oneShot.biggest and oneShot.biggest.amount == 900000)
    Check("Its share of max health is computed",
        oneShot.biggest.pct and math.abs(oneShot.biggest.pct - 0.45) < 0.001)
    Check("A hit worth 40% or more is called out by name",
        oneShot.lines[1] ~= nil
            and oneShot.lines[1]:find("Crushing Blow", 1, true) ~= nil)

    -- Death by a thousand cuts: no single hit is named.
    local chip = Death.Analyse({
        { t = 6, amount = 100000, heal = false, name = "Chip" },
        { t = 4, amount = 100000, heal = false, name = "Chip" },
        { t = 2, amount = 100000, heal = false, name = "Chip" },
    }, 2000000, {}, {})
    Check("Small hits are summed, not blamed one by one",
        chip.lines[1] ~= nil and chip.lines[1]:find("No single killer", 1, true) ~= nil)

    -- Heals count to their own total and the drought is measured.
    local healed = Death.Analyse({
        { t = 8.0, amount = 300000, heal = true,  name = "Heal" },
        { t = 1.0, amount = 500000, heal = false, name = "Hit" },
    }, 2000000, {}, {})
    Check("A heal lands in the healed total, not the taken total",
        healed.totalHealed == 300000 and healed.totalIn == 500000)
    Check("A heal drought over 3s gets its own sentence",
        (function()
            for _, line in ipairs(healed.lines) do
                if line:find("last heal", 1, true) then return true end
            end
            return false
        end)())

    -- Availability: ready by our clock is listed, unknown is not called
    -- ready, and a CONSUMABLE is judged in the same list as the spells -
    -- "what could have saved you" is one question and used to have two
    -- answers on one window.
    local avail = Death.Analyse({},  nil, {
        { spellID = 1, name = "Icebound Fortitude", remaining = 0 },
        { spellID = 2, name = "Vampiric Blood",     remaining = 25 },
        { spellID = 3, name = "Lichborne",          remaining = nil, why = "not cast since login" },
        { itemID = 5512, name = "Healthstone", count = 1, remaining = 0 },
    }, {})
    Check("Ready and unused is listed by name",
        #avail.readyDefensives == 2
            and avail.readyDefensives[1].name == "Icebound Fortitude")
    -- The id travels with the name everywhere, because only the id can
    -- produce an icon and a tooltip - and this game shows both, always.
    Check("A named spell carries its id for the icon and the tooltip",
        avail.readyDefensives[1].spellID == 1)
    -- A consumable carries an ITEM id and is judged with the spells: a
    -- healthstone in the bag is the same verdict as a defensive off cooldown.
    Check("A consumable is judged as a defensive, by its item id",
        avail.readyDefensives[2].itemID == 5512)
    Check("Cannot-tell is never promoted to ready",
        #avail.unknownDefensives == 1
            and avail.unknownDefensives[1].name == "Lichborne")

    ---------------------------------------------------------------------
    -- The verdict is the judgement alone; the lists went to the panel.
    ---------------------------------------------------------------------
    local judged = Death.Analyse({
        { t = 3, amount = 500000, name = "Smash", hp = 100 },
    }, 1000000, {
        { spellID = 1, name = "Icebound Fortitude", remaining = 0 },
    }, {
        { t = 5, spellID = 9, name = "Death Strike" },
        { t = 4, spellID = 7, itemID = 5512, name = "Use Healthstone",
          defensive = true },
    })
    local function Has(list, prefix)
        for _, line in ipairs(list) do
            if tostring(line):find(prefix, 1, true) == 1 then return true end
        end
        return false
    end
    Check("The full story still carries the lists, for chat",
        Has(judged.lines, "Defensives used: ")
            and Has(judged.lines, "Your casts: ")
            and Has(judged.lines, "Ready and unused"))
    Check("The verdict carries the judgement and none of the lists",
        #judged.verdict > 0
            and not Has(judged.verdict, "Defensives used: ")
            and not Has(judged.verdict, "Your casts: ")
            and not Has(judged.verdict, "Ready and unused"))
    Check("The window reads the verdict off a new analysis",
        Death.VerdictLines(judged) == judged.verdict)
    Check("and sorts an OLD one by what its lines begin with",
        #Death.VerdictLines({ lines = { "One hit did most of it.",
            "Defensives used: x.", "Your casts: y.",
            "Ready and unused (by our own clock): z." } }) == 1)
    Check("A used consumable is pictured as the ITEM in the story",
        judged.defensivesUsed[1].itemID == 5512)

    ---------------------------------------------------------------------
    -- Which cast was an item. Two doors: the spell the client says the
    -- item casts, and the item's name inside the cast's name - because a
    -- Healthstone on this patch fires "Use Healthstone" (462156), which
    -- is not the spell GetItemSpell names. Read off the owner's log.
    ---------------------------------------------------------------------
    local map = Death.DefensiveMap({ [48792] = true },
        { [5512] = true, [212263] = true },
        function(itemID) return itemID == 5512 and 6262 or 1234768 end,
        function(itemID)
            return itemID == 5512 and "Healthstone" or "Silvermoon Health Potion"
        end)
    Check("A picked spell is a defensive", Death.CastItem(map, 48792) == nil
        and map[48792] == true)
    Check("The item's own spell names the item",
        Death.CastItem(map, 6262, "Healthstone") == 5512)
    Check("So does the item's name inside a stranger spell's name",
        Death.CastItem(map, 462156, "Use Healthstone") == 5512)
    Check("A cast that is neither is nothing",
        Death.CastItem(map, 49998, "Death Strike") == nil)
    Check("The potion by its spell",
        Death.CastItem(map, 1234768, "Silvermoon Health Potion") == 212263)

    -- An OLD death, brought up to date: the stone becomes a defensive with
    -- its item, the potion gets its bottle, a spell is left alone, and a
    -- second pass changes nothing.
    local old = {
        casts = {
            { t = 5, spellID = 49998, name = "Death Strike" },
            { t = 4, spellID = 462156, name = "Use Healthstone" },
            { t = 2, spellID = 1234768, name = "Silvermoon Health Potion",
              defensive = true },
        },
        analysis = { defensivesUsed = {
            { spellID = 1234768, name = "Silvermoon Health Potion" },
        } },
    }
    Check("An old death's presses get their items back",
        Death.Upgrade(old, map) == 2
            and old.casts[2].itemID == 5512 and old.casts[2].defensive == true
            and old.casts[3].itemID == 212263
            and old.casts[1].itemID == nil and old.casts[1].defensive == nil)
    Check("and so does the story's own list of what was used",
        old.analysis.defensivesUsed[1].itemID == 212263)
    Check("A second pass finds nothing to do", Death.Upgrade(old, map) == 0)

    ---------------------------------------------------------------------
    -- The panel's rows: used, unused, the rest - and a used one does not
    -- also stand in the unused list with its cooldown.
    ---------------------------------------------------------------------
    local rows = Death.PanelEntries({
        casts = {
            { t = 2, spellID = 9, name = "Death Strike" },
            { t = 6, spellID = 7, itemID = 5512, name = "Use Healthstone",
              defensive = true },
            { t = 4, spellID = 48792, name = "Icebound Fortitude",
              defensive = true },
        },
        avail = {
            { spellID = 48792, name = "Icebound Fortitude", remaining = 25 },
            { spellID = 55233, name = "Vampiric Blood", remaining = 0 },
            { itemID = 5512, name = "Healthstone", count = 1, remaining = 0 },
            { itemID = 212263, name = "Silvermoon Health Potion", count = 0 },
        },
    })
    local heads, items = {}, {}
    for _, row in ipairs(rows) do
        if row.kind == "head" then
            heads[#heads + 1] = row.text
            items[row.text] = {}
        elseif row.kind == "item" then
            local list = items[heads[#heads]]
            list[#list + 1] = row
        end
    end
    Check("Three headings, in the order they are read",
        heads[1] == "Defensives used" and heads[2] == "Unused defensives"
            and heads[3] == "Your casts")
    Check("Used, oldest first, with how long before the end",
        #items["Defensives used"] == 2
            and items["Defensives used"][1].name == "Use Healthstone"
            and items["Defensives used"][1].suffix == "-6.0s"
            and items["Defensives used"][2].name == "Icebound Fortitude")
    Check("Unused leaves out what was pressed - by id and by name",
        #items["Unused defensives"] == 2
            and items["Unused defensives"][1].name == "Vampiric Blood"
            and items["Unused defensives"][2].name == "Silvermoon Health Potion")
    Check("and says ready, or none in the bags",
        items["Unused defensives"][1].suffix:find("ready", 1, true) ~= nil
            and items["Unused defensives"][2].suffix:find("none", 1, true) ~= nil)
    Check("The rest of the casts are their own list",
        #items["Your casts"] == 1 and items["Your casts"][1].name == "Death Strike")
    -- Nothing picked is a door: one button per empty half, to the page
    -- where they are picked. Somebody with spells and no potions gets one.
    local function Buttons(snap)
        local found = {}
        for _, row in ipairs(Death.PanelEntries(snap)) do
            if row.kind == "button" then found[#found + 1] = row.text end
        end
        return found
    end
    local none = Buttons({ casts = {}, avail = {} })
    Check("Nothing picked offers both doors",
        #none == 2 and none[1] == "Set up your defensives"
            and none[2] == "Set up your consumables")
    local spellsOnly = Buttons({ casts = {},
        avail = { { spellID = 1, name = "IBF", remaining = 0 } } })
    Check("Spells picked and no potions offers the potion door alone",
        #spellsOnly == 1 and spellsOnly[1] == "Set up your consumables")
    local both = Buttons({ casts = {}, avail = {
        { spellID = 1, name = "IBF", remaining = 0 },
        { itemID = 5512, name = "Healthstone", count = 1, remaining = 0 } } })
    Check("Both picked, no door", #both == 0)
    Check("A button row names the page it opens",
        (function()
            for _, row in ipairs(Death.PanelEntries({ casts = {}, avail = {} })) do
                if row.kind == "button" and row.page ~= "deaths" then return false end
            end
            return true
        end)())

    -- THE GUIDE'S TILE KEEPS ITS SHAPE: a frame narrower than the tile's
    -- own 296:101 shows the middle of it at full height, a wider one the
    -- middle band at full width.
    -- The art is the top-left 190x92 of a 256x128 file (Raider.IO's
    -- region); nothing outside it is ever shown.
    do
        local AX0, AX1, AY0, AY1 = 4 / 256, 190 / 256, 4 / 128, 92 / 128
        local x0, x1, y0, y1 = Death.TileCoords(64, 46)
        Check("A tall frame crops the sides and keeps the art's height",
            math.abs(y0 - AY0) < 0.001 and math.abs(y1 - AY1) < 0.001
                and x0 > AX0 and x1 < AX1)
        local wx0, wx1, wy0, wy1 = Death.TileCoords(400, 40)
        Check("A wide frame keeps the art's width and crops top and bottom",
            math.abs(wx0 - AX0) < 0.001 and math.abs(wx1 - AX1) < 0.001
                and wy0 > AY0 and wy1 < AY1)
        local ex0, ex1, ey0, ey1 = Death.TileCoords(186, 88)
        Check("The art's own shape is the whole art and nothing outside it",
            math.abs(ex0 - AX0) < 0.001 and math.abs(ex1 - AX1) < 0.001
                and math.abs(ey0 - AY0) < 0.001 and math.abs(ey1 - AY1) < 0.001)
    end

    Check("A snapshot with nothing readable says so in the panel",
        (function()
            local out = Death.PanelEntries({ reason = "The recap was empty." })
            for _, row in ipairs(out) do
                if row.kind == "none" and row.text == "The recap was empty." then
                    return true
                end
            end
            return false
        end)())


    -- CONSUMABLES ARE PICKED, NOT SHIPPED - and this check used to prove it
    -- by DELETING his list and leaving it deleted. Every /zs test threw away
    -- what he had chosen, and the next look re-seeded the starter items, so
    -- it read as "the addon does not save my consumables". The file's own
    -- header promises it never touches your settings; now it does not.
    --
    -- Put back byte for byte, including the case where there was nothing
    -- there: nil and an empty table are different answers.
    if ns.db then
        local keptItems = ns.db.rescueItemsBySpec
        local keptLegacy = ns.db.rescueItems
        ns.db.rescueItemsBySpec, ns.db.rescueItems = nil, nil

        local fresh = Death.PickedItems()
        local count = 0
        for _ in pairs(fresh) do count = count + 1 end
        Check("A spec that has never picked anything starts empty", count == 0)

        -- WITH A SPECIALISATION THE CLIENT WILL NAME. Faked, because out
        -- here there is no character - and this is the half that matters:
        -- the same call twice has to hand back the SAME table, or a pick
        -- goes into a throwaway and the window looks like it forgot.
        local realKey = PretendSpec("WARRIOR:73")

        local mine = Death.PickedItems()
        mine[5512] = true
        Check("And what it picks is there on the next look",
            Death.PickedItems()[5512] == true)

        -- The other spec of the same class is a different list.
        PretendSpec("WARRIOR:71")
        Check("The other spec of the same class has its own list",
            Death.PickedItems()[5512] == nil)

        -- AND AN UNANSWERED SPEC WRITES NOTHING. "WARRIOR:0" is a bin
        -- nobody reads; a pick made in that second has to be dropped rather
        -- than filed where it can never be found again.
        PretendSpec("WARRIOR:0", false)
        local limbo = Death.PickedItems()
        limbo[5512] = true
        Check("A pick made before the client names the spec is not filed",
            Death.PickedItems()[5512] == nil)

        ns.SpecKey = realKey

        ns.db.rescueItemsBySpec, ns.db.rescueItems = keptItems, keptLegacy
        Check("The self test gave his own list back untouched",
            ns.db.rescueItemsBySpec == keptItems
            and ns.db.rescueItems == keptLegacy)
    end

    -- Nothing readable at all still answers with a sentence.
    local empty = Death.Analyse(nil, nil, {}, {})
    Check("An empty recap still gets an honest sentence", #empty.lines == 1)

    -- The row filter. The first live death drew hits from five minutes
    -- earlier under a subtitle promising ten seconds - the recap hands over
    -- more history than its name says.
    local recent, stale = Death.RecentEvents({
        { t = 309.8 }, { t = 2.1 }, { t = 0 },
    }, 10)
    Check("Events older than the window are kept off the rows",
        #recent == 2 and stale == false)
    local old, oldStale = Death.RecentEvents({ { t = 300 } }, 10)
    Check("A recap with only old events comes back whole, and flagged",
        #old == 1 and oldStale == true)
    local none, noneStale = Death.RecentEvents(nil, 10)
    Check("No events at all is an empty list, flagged",
        #none == 0 and noneStale == true)

    -- The mob's name in the verdict, when the recap gave one.
    local named = Death.Analyse({
        { t = 1, amount = 900000, heal = false, name = "Melee",
          who = "Heavyweight Golem" },
    }, 1000000, {}, {})
    Check("The killer's name lands in the sentence",
        named.lines[1]:find("from Heavyweight Golem", 1, true) ~= nil)

    -- The session log. One rule, three promises: a new death is appended,
    -- the cap drops the oldest, and a RETRY replaces instead of appending -
    -- or one fall would sit in the pager twice.
    local log = {}
    for i = 1, 12 do Death.Remember(log, { n = i }, 10) end
    Check("The log keeps the cap and no more", #log == 10)
    Check("The oldest deaths fall out, the newest stay",
        log[1].n == 3 and log[10].n == 12)
    Death.Remember(log, { n = 99 }, 10, true)
    Check("A replace overwrites the newest rather than appending",
        #log == 10 and log[10].n == 99)
    local fresh = {}
    Death.Remember(fresh, { n = 1 }, 10, true)
    Check("A replace on an empty log still records the death",
        #fresh == 1 and fresh[1].n == 1)

    -- SafeName: the fallback words come from the event type.
    Check("A withheld melee name says Melee",
        Death.SafeName(nil, "SWING_DAMAGE") == "Melee")
    Check("A withheld heal name says a heal",
        Death.SafeName(nil, "SPELL_HEAL") == "a heal")
    Check("A readable name passes through",
        Death.SafeName("Crushing Blow", "SPELL_DAMAGE") == "Crushing Blow")

    -- The share is built from analysed lines only, and leads with totals.
    local lines = Death.ShareLines({
        when = "20:15:01",
        where = "M+12 - Ara-Kara - Avanoxx",
        analysis = Death.Analyse({
            { t = 1, amount = 500000, heal = false, name = "Hit" },
        }, 1000000, {}, {}),
    })
    Check("The share leads with the totals line",
        lines and lines[1] ~= nil and lines[1]:find("Death 20:15:01", 1, true) ~= nil)
    Check("Where it happened travels with the share",
        lines and lines[1]:find("M+12 - Ara-Kara", 1, true) ~= nil)
    Check("The verdict lines travel with it", lines and #lines >= 2)

    ---------------------------------------------------------------------
    -- Where it happened. Every argument is one the client may withhold,
    -- so the label has to degrade a word at a time rather than fail.
    ---------------------------------------------------------------------
    local key, keyShort = Death.WhereLabel("party", "Ara-Kara, City of Echoes",
        "Mythic Keystone", 12, nil, nil)
    Check("A keystone level makes the dungeon an M+",
        key == "M+12 - Ara-Kara, City of Echoes" and keyShort == "M+12")

    local dungeon = Death.WhereLabel("party", "Ara-Kara", "Heroic", nil, nil, nil)
    Check("A dungeon without a key keeps its difficulty",
        dungeon == "Dungeon - Ara-Kara (Heroic)")

    local raid, raidShort = Death.WhereLabel("raid", "Nerub-ar Palace", "Heroic",
        nil, "Queen Ansurek", nil)
    Check("A raid boss is named after the raid and its difficulty",
        raid == "Raid - Nerub-ar Palace (Heroic) - Queen Ansurek")
    Check("The boss wins the short word outright", raidShort == "Queen Ansurek")

    local open, openShort = Death.WhereLabel("none", nil, nil, nil, nil, "Duskwood")
    Check("Outside an instance the zone is the place",
        open == "Open world - Duskwood" and openShort == "Open world")
    Check("A withheld zone still answers something",
        Death.WhereLabel(nil, nil, nil, nil, nil, nil) == "Open world")

    ---------------------------------------------------------------------
    -- Where a share goes. The rule is separate from the group state so
    -- this can be asked on a desktop with nobody around.
    ---------------------------------------------------------------------
    Check("Auto prefers the instance group over the raid",
        Death.ShareTarget("AUTO", { inInstance = true, inRaid = true,
            inParty = true }) == "INSTANCE_CHAT")
    Check("Auto falls back to the raid, then the party",
        Death.ShareTarget("AUTO", { inRaid = true, inParty = true }) == "RAID"
            and Death.ShareTarget(nil, { inParty = true }) == "PARTY")
    Check("Auto alone answers nobody, with a reason",
        select(1, Death.ShareTarget("AUTO", {})) == nil
            and select(2, Death.ShareTarget("AUTO", {})) ~= nil)
    Check("A chosen channel that is not there never silently posts",
        select(1, Death.ShareTarget("RAID", { inParty = true })) == nil)
    Check("A chosen channel that IS there is taken literally",
        Death.ShareTarget("RAID", { inRaid = true }) == "RAID"
            and Death.ShareTarget("GUILD", { inGuild = true }) == "GUILD")
    Check("Say and yell need no group at all",
        Death.ShareTarget("SAY", {}) == "SAY"
            and Death.ShareTarget("YELL", {}) == "YELL")

    ---------------------------------------------------------------------
    -- How many are kept, and which slice of them the side column shows.
    ---------------------------------------------------------------------
    Check("Ten is the number when nobody has said otherwise",
        Death.KEEP_DEFAULT == 10)
    Check("The bounds are real bounds", Death.KEEP_MIN >= 1
        and Death.KEEP_MAX > Death.KEEP_MIN)

    -- The side column shows twelve of up to fifty, so the slice has to
    -- follow the selection or the list stops answering "where am I".
    Check("The newest death sits at the top with nothing scrolled",
        Death.ScrollTo(30, 30, 0, 12) == 0)
    Check("Walking past the bottom edge scrolls by exactly one",
        Death.ScrollTo(18, 30, 0, 12) == 1)
    Check("Walking back up above the top edge scrolls back",
        Death.ScrollTo(30, 30, 5, 12) == 0)
    Check("A selection already in view does not move the list",
        Death.ScrollTo(25, 30, 3, 12) == 3)
    Check("The list never scrolls past its own end",
        Death.ScrollTo(1, 30, 99, 12) == 18)
    Check("A list shorter than the column never scrolls",
        Death.ScrollTo(1, 4, 0, 12) == 0)

    -- Clearing empties the list it is handed, and only that one.
    local mine = { { n = 1 }, { n = 2 } }
    Death.ClearLog(mine)
    Check("Clearing the list leaves nothing behind", #mine == 0)

    ---------------------------------------------------------------------
    -- Surviving a reload. The owner reloaded to test a build and the
    -- skull went with the list, so the last ten are written to the saved
    -- variables - which is only safe if nothing secret can get in.
    ---------------------------------------------------------------------
    local kept = Death.Persist({
        when = "16:10:54", day = "2026-08-09",
        where = "M+12 - Ara-Kara", whereShort = "M+12",
        killer = "Heavyweight Golem",
        killerArt = { creatureID = 213333 },
        maxHP = 2000000,
        events = {
            { t = 2.0, amount = 81600, hp = 40000, name = "Melee",
              who = "Heavyweight Golem", spellID = 195181,
              art = { creatureID = 213333 } },
        },
        avail = { { spellID = 48792, name = "Icebound Fortitude", remaining = 0 } },
        items = { { name = "Healthstone", count = 1 } },
        casts = { { t = 6, spellID = 48792, name = "Icebound Fortitude",
                    defensive = true, lasted = 8, stillUp = true } },
        analysis = { lines = { "derived, and not stored" } },
    })
    Check("A death worth keeping is kept whole",
        kept ~= nil and kept.killer == "Heavyweight Golem"
            and kept.where == "M+12 - Ara-Kara"
            and kept.killerArt.creatureID == 213333
            and #kept.events == 1 and kept.events[1].amount == 81600)
    Check("The verdict is NOT stored - it is derived on the way back",
        kept.analysis == nil)
    -- Each hit keeps its own face, or a reload turns twenty mobs back into
    -- one, which is the whole reason the faces are per hit.
    Check("Every hit keeps the face that belongs to it",
        kept.events[1].art ~= nil and kept.events[1].art.creatureID == 213333)
    -- And each press keeps the length that was measured for it, or the bar
    -- silently changes size after a reload.
    Check("A measured press keeps its length across a reload",
        kept.casts[1].lasted == 8 and kept.casts[1].stillUp == true)
    Check("A face with no numbers behind it is not stored as an empty box",
        Death.Persist({ events = { { t = 0, amount = 1, art = {} } } })
            .events[1].art == nil)
    Check("A death nothing was readable out of is not stored at all",
        Death.Persist({ when = "16:11:00", events = nil }) == nil)

    local back = Death.Restore({ kept })
    Check("Restoring rebuilds the verdict from the stored events",
        #back == 1 and back[1].analysis ~= nil and #back[1].analysis.lines > 0)
    Check("A stored entry with no events is dropped on the way back",
        #Death.Restore({ { when = "x" }, kept }) == 1)
    Check("Restoring an empty store is an empty list",
        #Death.Restore(nil) == 0)

    -- Nothing but a plain readable value of the right type gets in. A
    -- secret cannot be forged from Lua to test with directly, but it dies
    -- at the same gate as a wrong type does - one function, one rule, and
    -- this is the half of it that can be asked on a desktop.
    local dirty = Death.Persist({
        when = { "not a string" },
        killer = 12345,
        events = { { t = 0, amount = 100, name = {}, who = 7, spellID = "no" } },
        avail = {}, items = {},
    })
    Check("Only plain values of the right type reach the saved variables",
        dirty ~= nil and dirty.when == nil and dirty.killer == nil
            and dirty.events[1].name == nil and dirty.events[1].who == nil
            and dirty.events[1].spellID == nil
            and dirty.events[1].amount == 100)

    ---------------------------------------------------------------------
    -- The bar behind a row: two pieces of ONE health bar, which together
    -- are the health you had before the event landed.
    ---------------------------------------------------------------------
    local wasLeft, took = Death.RowSpans(
        { amount = 400000, hp = 600000 }, 1000000)
    Check("A hit draws what was left and what it took, side by side",
        math.abs(wasLeft - 0.6) < 0.001 and math.abs(took - 0.4) < 0.001)

    local healBefore, given = Death.RowSpans(
        { amount = 300000, hp = 800000, heal = true }, 1000000)
    Check("A heal draws the health BEFORE it and the piece it gave",
        math.abs(healBefore - 0.5) < 0.001 and math.abs(given - 0.3) < 0.001)

    local none, killing = Death.RowSpans(
        { amount = 3000000, hp = 0 }, 1000000)
    Check("An overkill cannot draw past the end of the row",
        none == 0 and math.abs(killing - 1) < 0.001)
    Check("With no maximum health there is no bar to draw",
        select(2, Death.RowSpans({ amount = 100, hp = 50 }, nil)) == 0)

    ---------------------------------------------------------------------
    -- One story out of two lists, and where a replay stands in it.
    ---------------------------------------------------------------------
    local story = Death.Storyline(
        { { t = 4.0, amount = 100, name = "First hit" },
          { t = 0.0, amount = 900, name = "Killing blow" } },
        { { t = 2.0, spellID = 48792, name = "Icebound Fortitude",
            defensive = true } })
    Check("What hit you and what you pressed become one order",
        #story == 3 and story[1].name == "First hit"
            and story[2].name == "Icebound Fortitude"
            and story[3].name == "Killing blow")
    Check("A press is marked as yours and keeps its defensive flag",
        story[2].cast == true and story[2].defensive == true)
    Check("A story with nothing in it is empty rather than nil",
        #Death.Storyline(nil, nil) == 0)

    -- A press landing in the same instant as the hit it answers reads
    -- before it: you pressed, then it landed.
    local tie = Death.Storyline({ { t = 2.0, name = "Hit" } },
        { { t = 2.0, name = "Press" } })
    Check("A press and a hit in the same instant read press first",
        tie[1].name == "Press")

    local rows = { { t = 4, hp = 900 }, { t = 2, hp = 500 }, { t = 0, hp = 0 } }
    Check("Before anything lands the bar is still full",
        select(2, Death.ReplayAt(rows, 9, 1000)) == 1000)
    Check("Mid-replay the health is the last landed event's",
        select(2, Death.ReplayAt(rows, 3, 1000)) == 900)
    local landed = Death.ReplayAt(rows, 1.5, 1000)
    Check("The count of what has landed follows the clock", landed == 2)
    Check("At the end everything has landed",
        Death.ReplayAt(rows, 0, 1000) == 3)

    ---------------------------------------------------------------------
    -- The replay window's own rules.
    ---------------------------------------------------------------------
    local Replay = ns.Replay
    if Replay then
        Check("The plot reaches past the oldest thing in the story",
            Replay.Span({ { t = 8 }, { t = 2 } }) > 8)
        Check("An empty story still has a plot to draw on",
            Replay.Span({}) >= 1)
        Check("The death sits at the right-hand end of the axis",
            math.abs(Replay.Fraction(0, 10, 0) - 1) < 0.001)
        Check("The oldest moment shown sits at the left-hand end",
            math.abs(Replay.Fraction(10, 10, 0)) < 0.001)
        -- NOT clamped, on purpose: a mark two seconds off the left edge
        -- must not pile up against the border pretending it is at it.
        -- Replay.Visible is what decides whether it is drawn at all.
        Check("A moment off the plot answers off the plot",
            Replay.Fraction(20, 10, 0) < 0 and Replay.Fraction(-5, 10, 0) > 1)
        Check("What is on screen and what is not is its own question",
            Replay.Visible(5, 10, 0) and not Replay.Visible(12, 10, 0)
                and not Replay.Visible(-1, 10, 0))
        -- The scrub is the inverse of the fraction: a hand at the left
        -- edge is the oldest moment shown, at the right edge the death,
        -- and off the plot it is clamped to the edge it went past.
        Check("The scrub is the inverse of the fraction",
            math.abs(Replay.Scrub(Replay.Fraction(3, 10, 0), 10, 0) - 3) < 0.001)
        Check("The left edge is the oldest moment shown",
            math.abs(Replay.Scrub(0, 10, 4) - 10) < 0.001)
        Check("The right edge is the newest",
            math.abs(Replay.Scrub(1, 10, 4) - 4) < 0.001)
        Check("Off the plot is clamped to the edge",
            math.abs(Replay.Scrub(-2, 10, 0) - 10) < 0.001
                and math.abs(Replay.Scrub(7, 10, 0)) < 0.001)

        -- THE DAMAGE GRAPH'S BUCKETS: oldest on the left, the death in the
        -- last column, heals skipped, overkill carried, peak returned.
        local buckets, peak = Replay.Buckets({
            { t = 9.5, amount = 100 },
            { t = 9.2, amount = 50 },
            { t = 5.0, amount = 20, heal = true },
            { t = 0.0, amount = 300, overkill = 200 },
        }, 10, 0, 10)
        Check("Ten columns across ten seconds", #buckets == 10)
        Check("Two hits in the same second add up in the first column",
            buckets[1].damage == 150 and buckets[2].damage == 0)
        Check("The death itself lands in the last column, overkill with it",
            buckets[10].damage == 300 and buckets[10].overkill == 200)
        Check("A heal is not damage", buckets[5].damage == 0 and buckets[6].damage == 0)
        Check("The peak is the tallest column", peak == 300)
        Check("Each column knows its newest edge, for the playhead",
            math.abs(buckets[1].t - 10) < 0.001
                and math.abs(buckets[10].t - 1) < 0.001)
        Check("An empty band draws nothing and does not divide by nought",
            select(2, Replay.Buckets({}, 5, 5, 4)) == 0)

        -- The view: zoom 1 is everything, and zooming in follows a centre
        -- without ever running off either end of the story.
        local from, to = Replay.View(10, 1, nil)
        Check("At rest the plot shows the whole death",
            from == 10 and to == 0)
        from, to = Replay.View(10, 2, 5)
        Check("Zoomed in, it shows a window round where you are looking",
            math.abs(from - 7.5) < 0.001 and math.abs(to - 2.5) < 0.001)
        from, to = Replay.View(10, 2, 9.9)
        Check("It cannot scroll past the beginning",
            math.abs(from - 10) < 0.001 and math.abs(to - 5) < 0.001)
        from, to = Replay.View(10, 2, 0)
        Check("It cannot scroll past the death",
            math.abs(to) < 0.001 and math.abs(from - 5) < 0.001)

        -- What a source's face says on hover, summed from the events we
        -- already read. There is no client call for "what can this NPC do"
        -- and a dungeon mob withholds even its name, so this is what IT
        -- did to YOU rather than a page from a database.
        local facts = Replay.SourceSummary({
            { t = 4, amount = 50000, name = "Scratch", who = "Golem" },
            { t = 2, amount = 900000, name = "Melee", who = "Golem" },
            { t = 1, amount = 300000, heal = true, name = "Heal",
              who = "Healyboi" },
            { t = 0, amount = 10000, name = "Melee", who = "Someone else" },
        }, "Golem")
        Check("A face counts only what that source did",
            facts.hits == 2 and facts.total == 950000)
        Check("It names its biggest hit", facts.biggest == 900000)
        -- Each ability is {spellID, name} rather than a bare name, so the
        -- enemy tip can draw it with its icon - the rule everywhere else in
        -- this addon. Still once each.
        Check("It lists what it used, once each",
            #facts.spells == 2 and facts.spells[1].name == "Scratch"
            and facts.spells[2].name == "Melee")
        Check("A heal is never counted as something it did to you",
            facts.total == 950000)
        Check("No named source is an empty summary, not an error",
            Replay.SourceSummary({ { t = 1, amount = 5 } }, nil).hits == 0)

        -----------------------------------------------------------------
        -- HOW LONG A BAR IS, and where that length came from. The owner
        -- watched presses draw as stubs and said so: "die cd bars muessen
        -- so weit gehen wie sie aktiv sind". The fix was not to invent a
        -- length - it was to measure one and to keep saying which is which.
        -----------------------------------------------------------------
        local lasted, source = Replay.BarLength({ spellID = 1, t = 6,
            lasted = 8 })
        Check("A press draws the window it actually opened",
            lasted == 8 and source == "window")
        lasted, source = Replay.BarLength({ spellID = 1, t = 6, lasted = 6,
            stillUp = true })
        Check("A buff still up when you died says so",
            lasted == 6 and source == "open")
        Check("A press with no window measured gets no invented length",
            Replay.BarLength({ spellID = 99999901 }) == nil)
        Check("A bar with no length is called a mark, not a bar",
            Replay.LengthNote(nil, nil):find("mark", 1, true) ~= nil)
        Check("A tooltip length says it came off the tooltip",
            Replay.LengthNote("tooltip", 8):find("tooltip", 1, true) ~= nil)
        Check("A measured window says it was measured",
            Replay.LengthNote("window", 8):find("measured", 1, true) ~= nil)
        Check("A still-running buff is worded as still running",
            Replay.LengthNote("open", 6):find("Still up", 1, true) ~= nil)

        Check("A speed outside what is watchable is pulled back in",
            Replay.ClampSpeed(0.01) > 0 and Replay.ClampSpeed(0.01) <= 1
                and Replay.ClampSpeed(50) <= 10)
        Check("A speed inside the range is left alone",
            Replay.ClampSpeed(1.5) == 1.5)
        Check("A speed that is not a number answers real time",
            Replay.ClampSpeed(nil) == 1 and Replay.ClampSpeed("fast") == 1)

        Check("A hit worth half your health draws half a column",
            math.abs(Replay.ColumnHeight(500, 1000)
                - Replay.ColumnHeight(1000, 1000) / 2) < 0.01)
        Check("A tiny hit still draws a visible mark",
            Replay.ColumnHeight(1, 1000000) >= 6)
        Check("Without a maximum health there is nothing to scale by",
            Replay.ColumnHeight(500, nil) == 6)
        Check("The speed label does not invent precision",
            Replay.SpeedLabel(1) == "1x"
                and Replay.SpeedLabel(0.25) == "0.25x")

        -- Play at the end must mean "again". Un-pausing a clock that has
        -- already run out changes nothing on screen, and a live-looking
        -- button that changes nothing is read as broken.
        Check("Play in the middle of a replay pauses and resumes",
            Replay.PlayAction(4) == "toggle")
        Check("Play at the end starts it over instead of doing nothing",
            Replay.PlayAction(0) == "restart"
                and Replay.PlayAction(-1) == "restart")
    else
        Skip("The replay window", "Replay.lua did not load")
    end

    ---------------------------------------------------------------------
    -- What you pressed, in the verdict. This is the line the whole
    -- feature is for: anybody reading it can see nothing was pressed.
    ---------------------------------------------------------------------
    local nothing = Death.Analyse(
        { { t = 1, amount = 900000, name = "Melee" } }, 1000000, {}, {})
    Check("Pressing nothing at all is said out loud",
        (function()
            for _, line in ipairs(nothing.lines) do
                if line:find("pressed nothing", 1, true) then return true end
            end
            return false
        end)())

    local wrongOnes = Death.Analyse(
        { { t = 1, amount = 900000, name = "Melee" } }, 1000000, {},
        { { name = "Death Strike" }, { name = "Heart Strike" } })
    -- The judgement and the evidence are two lines, not one sentence: a
    -- rotation of seven abilities wrapped the old one over three lines and
    -- the verdict disappeared into the middle of a list.
    Check("Pressing no defensive is its own sentence",
        (function()
            for _, line in ipairs(wrongOnes.lines) do
                if line == "No defensive was used." then return true end
            end
            return false
        end)())
    Check("What you did cast is listed on a line of its own",
        (function()
            for _, line in ipairs(wrongOnes.lines) do
                local plain = Death.PlainText(line)
                if plain:find("Your casts:", 1, true)
                    and plain:find("Death Strike", 1, true) then return true end
            end
            return false
        end)())

    local rightOne = Death.Analyse(
        { { t = 1, amount = 900000, name = "Melee" } }, 1000000, {},
        { { spellID = 48792, name = "Icebound Fortitude", defensive = true },
          { name = "Death Strike" } })
    Check("A defensive that WAS used is credited on its own",
        #rightOne.defensivesUsed == 1
            and rightOne.defensivesUsed[1].name == "Icebound Fortitude")
    Check("And it carries its id, so the chip can draw an icon",
        rightOne.defensivesUsed[1].spellID == 48792)

    ---------------------------------------------------------------------
    -- ICON AND TOOLTIP, ALWAYS. The owner's rule, in his words: "immer
    -- wenn eine faehigkeit oder was auch immer einen tooltip und icon hat,
    -- muss das angezeigt werden. egal bei was". A wrapped sentence cannot
    -- hold a hover target, so the verdict carries the icon inline - and
    -- chat, which would show the escape sequence as punctuation or drop it
    -- outright, gets it taken back out on the way through.
    ---------------------------------------------------------------------
    Check("A spell with no icon behind it still reads as its name",
        Death.SpellText(nil, "Shield Wall") == "Shield Wall")
    Check("A list of spells reads as an enumeration",
        Death.PlainText(Death.SpellList({
            { spellID = 1, name = "A" }, { spellID = 2, name = "B" },
        })) == "A, B")
    Check("An inline icon never reaches the chat",
        Death.PlainText("Defensives used: |T123:14:14|t Shield Wall.")
            == "Defensives used: Shield Wall.")
    Check("Text with no icons in it is handed back untouched",
        Death.PlainText("nothing to strip") == "nothing to strip")

    -- The clock in the list. Today it is a time; older, the day goes first.
    Check("A death from today reads as a clock",
        Death.WhenLabel({ when = "16:10:54", day = "2026-08-09" },
            "2026-08-09") == "16:10:54")
    Check("A death from another day carries its date",
        Death.WhenLabel({ when = "16:10:54", day = "2026-08-07" },
            "2026-08-09") == "07.08.  16:10:54")
    Check("A death with no day recorded still reads",
        Death.WhenLabel({ when = "16:10:54" }, "2026-08-09") == "16:10:54")

    -----------------------------------------------------------------------
    -- WHAT THE BAG SCAN OFFERS
    --
    -- Owner, 2026-08-09: "der erkennt die silvermoon health potion nicht".
    -- It recognised nothing at all, ever: the class id is the SIXTH return of
    -- GetItemInfoInstant, four values were discarded and the fifth taken -
    -- the ICON - and a texture file id was then compared against 0.
    --
    -- This runs against YOUR bags, so it cannot expect particular items. What
    -- it can do is re-derive the answer independently and require the filter
    -- to have agreed: every item offered as a consumable must really be one,
    -- and must really have something to press. The exact-contents test lives
    -- in the desktop harness, which owns a bag it made up.
    -----------------------------------------------------------------------
    if C_Item and C_Item.GetItemInfoInstant and C_Container then
        local offered = Death.BagConsumables()
        Check("The bag scan answers with a list", type(offered) == "table")

        local wrongClass, noUse = 0, 0
        for _, itemID in ipairs(offered or {}) do
            local ok, class = pcall(function()
                return select(6, C_Item.GetItemInfoInstant(itemID))
            end)
            if not ok or class ~= 0 then wrongClass = wrongClass + 1 end

            local okSpell, _, spellID = pcall(C_Item.GetItemSpell, itemID)
            if not (okSpell and spellID) then noUse = noUse + 1 end
        end
        Check("Everything offered as a consumable really is one",
            wrongClass == 0, wrongClass .. " were not")
        Check("Everything offered has something to press",
            noUse == 0, noUse .. " had no use effect")

        -- The count is reported rather than judged: an empty bag is a fact
        -- about your character, not a failure. Reported, though, because
        -- "nothing usable in your bags" and "the scan is broken again" look
        -- identical from the outside, and this is the line that tells them
        -- apart.
        if #offered == 0 then
            Skip("What the bag scan found",
                "nothing usable in your bags right now")
        end
    else
        Skip("The bag scan", "this client has no container API")
    end
end

---------------------------------------------------------------------------
-- Everybody ELSE's deaths
--
-- The rows below are the four his client actually handed over on 2026-08-14,
-- typed in as they came rather than rounded into tidy examples. That matters
-- for exactly one reason: two of the four died in the SAME SECOND, which is
-- the case a made-up list would never have contained and the one where the
-- ordering has to fall back on something other than the clock.
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- WHAT CHANGED SINCE YOU LAST PLAYED
--
-- The two rules with teeth are the version comparison - "4.9.0" is newer
-- than "4.81.0" as a STRING and older as a version - and the fresh install,
-- which must be shown nothing at all rather than a year of history.
---------------------------------------------------------------------------
local function TestNews()
    local N = ns.News

    Check("A version is compared as numbers, not as text",
        N.Newer("4.81.0", "4.9.0") and not N.Newer("4.9.0", "4.81.0"))
    Check("...and a version is not newer than itself",
        not N.Newer("4.81.0", "4.81.0"))
    Check("...a missing part counts as zero",
        N.Newer("4.81.1", "4.81") and not N.Newer("4.81", "4.81.0"))
    Check("...and anything is news to somebody who has seen nothing",
        N.Newer("1.0.0", nil) and N.Newer("1.0.0", ""))

    local log = {
        { version = "4.83.0", lines = { "c" } },
        { version = "4.82.0", lines = { "b" } },
        { version = "4.81.0", lines = { "a" } },
    }
    local shown, dropped = N.Since(log, "4.81.0", 4)
    Check("Only what came after the version you last read is shown",
        #shown == 2 and shown[1].version == "4.83.0" and dropped == 0)
    Check("...and nothing at all when you are up to date",
        #N.Since(log, "4.83.0", 4) == 0)
    Check("...while a long absence is capped and SAYS how many it dropped",
        select(1, N.Since(log, "0.0.0", 2)) ~= nil
        and #(select(1, N.Since(log, "0.0.0", 2))) == 2
        and select(2, N.Since(log, "0.0.0", 2)) == 1)
    Check("...and the footer repeats that number rather than hiding it",
        N.FootLine(shown, 1):find("1 older", 1, true) ~= nil
        and N.FootLine(shown, 0):find("older", 1, true) == nil)
    Check("A window with nothing to say has no footer",
        N.FootLine({}, 0) == "")

    -- A LINE IS STILL A PLAIN STRING. Six hundred of them are, and a
    -- renderer that only understood the new shape would draw a blank for
    -- every one of them.
    Check("A plain changelog line still reads as a line",
        N.LineText("just words") == "just words"
        and N.LineLink("just words") == nil)
    Check("...and one carrying a link answers both halves", (function()
        local line = { text = "a thing", link = { label = "Open", page = "deaths" } }
        return N.LineText(line) == "a thing"
            and (N.LineLink(line) or {}).page == "deaths"
    end)())
    Check("...a link with nowhere to go is not a link",
        N.LineLink({ text = "x", link = { label = "Open" } }) == nil
        and N.LineLink({ text = "x", link = { page = "deaths" } }) == nil)

    -- A BUTTON THAT OPENS NOTHING IS WORSE THAN NO BUTTON, so a link naming
    -- something that has been renamed away is left off the window.
    Check("A link is only drawn when it can be followed",
        N.CanFollow({ label = "x", open = "raiddeaths" })
        and not N.CanFollow({ label = "x", open = "nosuchwindow" }))

    ---------------------------------------------------------------------
    -- THE BOXES. Owner: "unterteil das mal schoen mit boxen zu features
    -- und bug fixes und neuen zeug." Which box a line lands in is read off
    -- its own opening word, and that is only allowed because this changelog
    -- has opened every fix with "Fixed:" and every addition with "New:" for
    -- its whole life. An explicit `kind` always wins.
    ---------------------------------------------------------------------
    Check("A fix sorts itself into the fixes",
        N.KindOf("|cffffd100Fixed: something|r") == "fix"
        and N.KindOf("Fixed: no colour on it either") == "fix")
    Check("...an addition into the new things",
        N.KindOf("|cffffd100New: a window|r") == "new")
    Check("...and everything else is an improvement",
        N.KindOf("|cffffd100A saved bar now holds the whole bar|r") == "change"
        and N.KindOf("") == "change")
    Check("A line that SAYS which it is wins over its opening word",
        N.KindOf({ text = "Fixed: actually a feature", kind = "new" }) == "new")
    Check("...and a kind nobody knows falls back rather than inventing a box",
        N.KindOf({ text = "New: a thing", kind = "nonsense" }) == "new")

    local sections = N.Sections({ lines = {
        "|cffffd100New: one|r", "|cffffd100Fixed: two|r",
        "Something better", "|cffffd100New: three|r",
    } })
    Check("The boxes come out new, improved, fixed - in that order",
        #sections == 3 and sections[1].key == "new"
        and sections[2].key == "change" and sections[3].key == "fix")
    Check("...each holding its own lines, in the order they were written",
        #sections[1].lines == 2
        and N.LineText(sections[1].lines[1]):find("one", 1, true) ~= nil
        and N.LineText(sections[1].lines[2]):find("three", 1, true) ~= nil)
    Check("...and a box with nothing in it is not drawn at all",
        #N.Sections({ lines = { "just an improvement" } }) == 1)
    Check("A version with no lines has no boxes", #N.Sections({}) == 0)

    ---------------------------------------------------------------------
    -- A HEADLINE AND A PARAGRAPH. Owner: "GELB als Ueberschrift, darunter
    -- der text." The split is at the FIRST |r, never the last: a body may
    -- carry colour of its own and a greedy match swallows the paragraph
    -- into the heading.
    ---------------------------------------------------------------------
    local head, body = N.Split("|cffffd100New: a thing.|r And what it does.")
    Check("The yellow clause becomes the heading",
        head == "New: a thing." and body == "And what it does.")
    local head2, body2 = N.Split(
        "|cffffd100Fixed: one.|r See |cffffd100/zs chat|r for the rest.")
    Check("...and colour inside the paragraph does not extend it",
        head2 == "Fixed: one."
        and body2 == "See |cffffd100/zs chat|r for the rest.")
    local head3, body3 = N.Split("no colour at all")
    Check("...a line with no yellow is all paragraph",
        head3 == nil and body3 == "no colour at all")
    local head4, body4 = N.Split("|cffffd100All of it is the heading.|r")
    Check("...and one that is nothing but yellow has no paragraph",
        head4 == "All of it is the heading." and body4 == "")

    ---------------------------------------------------------------------
    -- AND THE PICTURE, when there is an honest one. A number is a spell and
    -- the client owns the art; a string is a path. Anything else draws
    -- nothing - an icon invented for a line is decoration.
    ---------------------------------------------------------------------
    -- A NUMBER IS ASKED OF THE CLIENT, and whether the client ANSWERS is
    -- the client's business - a desk with no spell art has none for any id,
    -- and a check that demanded one would be asserting the world rather
    -- than the code. So: does it delegate, and does it delegate to the
    -- right place.
    Check("A spell id is asked of the client, not invented",
        N.IconFor({ text = "x", icon = 10060 }) == ns.SpellTexture(10060))
    Check("...a path is taken as it is",
        N.IconFor({ text = "x", icon = "Interface\\Icons\\thing" })
            == "Interface\\Icons\\thing")
    Check("...and a line with none draws none",
        N.IconFor({ text = "x" }) == nil
        and N.IconFor("a plain line") == nil
        and N.IconFor({ text = "x", icon = {} }) == nil)

    -- WHAT THE CLIENT ACTUALLY HAS ART FOR, reported rather than asserted.
    -- A spell id that stops existing leaves a hole beside a headline, and
    -- this is the line that would say so on a real client.
    local named, drawn = 0, 0
    for _, entry in ipairs(ns.CHANGELOG or {}) do
        for _, line in ipairs(entry.lines or {}) do
            if type(line) == "table" and line.icon ~= nil then
                named = named + 1
                if N.IconFor(line) then drawn = drawn + 1 end
            end
        end
    end
    Skip("Icons in the changelog the client can draw",
        string.format("%d of %d named", drawn, named))

    -- Every link the shipped changelog carries, checked. This is the one
    -- that catches a page key renamed six months from now.
    local broken
    for _, entry in ipairs(ns.CHANGELOG or {}) do
        for _, line in ipairs(entry.lines or {}) do
            local link = N.LineLink(line)
            if link and not N.CanFollow(link) then
                broken = (entry.version or "?") .. ": " .. link.label
            end
        end
    end
    Check("Every hot link in the changelog goes somewhere", broken == nil,
        tostring(broken))
end

local function TestRaidDeaths()
    local R = ns.RaidDeaths
    if not R then
        Skip("Raid deaths", "the module is not loaded")
        return
    end

    -- Newest first, which is the order the client hands them over.
    local function Recorded()
        return {
            { name = "Meredy Huntswell", classFilename = "MAGE",
              deathRecapID = 40, deathTimeSeconds = 87, isLocalPlayer = false },
            { name = "Austin Huxworth", classFilename = "HUNTER",
              deathRecapID = 39, deathTimeSeconds = 65, isLocalPlayer = false },
            { name = "Crenna Earth-Daughter", classFilename = "DRUID",
              deathRecapID = 38, deathTimeSeconds = 62, isLocalPlayer = false },
            { name = "Shuja Grimaxe", classFilename = "SHAMAN",
              deathRecapID = 37, deathTimeSeconds = 62, isLocalPlayer = false },
        }
    end

    local rows = R.Rows(Recorded(), "Zwoelf")
    Check("Every death in the list is read", #rows == 4,
        string.format("%d of 4", #rows))

    local order, timed = R.Timeline(rows)
    Check("The Current session's clock is usable", timed)
    Check("They come out in the order they fell",
        order[1].short == "Shuja Grimaxe"
        and order[2].short == "Crenna Earth-Daughter"
        and order[3].short == "Austin Huxworth"
        and order[4].short == "Meredy Huntswell",
        order[1] and order[1].short)

    -- The two at 62 are the whole reason there is a second sort key: the
    -- clock cannot separate them and the recap id can, because it counts up.
    Check("Two deaths in one second are split by the recap id",
        order[1].recapID == 37 and order[2].recapID == 38)

    Check("The gap to the one before is what tells a wipe from bad luck",
        order[1].gap == nil and order[2].gap == 0
        and order[3].gap == 3 and order[4].gap == 22,
        tostring(order[4] and order[4].gap))

    -- Overall answers -1 for every death. That is "there is no clock in
    -- here", not "he died at second zero", and a timeline drawn off it would
    -- put four people on the same tick.
    local blind = Recorded()
    for _, row in ipairs(blind) do row.deathTimeSeconds = -1 end
    local noClock, stillTimed = R.Timeline(R.Rows(blind, "Zwoelf"))
    Check("Overall's -1 is refused as a time", not stillTimed)
    Check("...and they still come out oldest first, by recap id",
        noClock[1].short == "Shuja Grimaxe"
        and noClock[4].short == "Meredy Huntswell")

    -- And with neither, the order the client listed them in is the last
    -- thing left - reversed, because that list arrives newest first.
    local bare = Recorded()
    for _, row in ipairs(bare) do
        row.deathTimeSeconds, row.deathRecapID = -1, nil
    end
    local reversed = R.Timeline(R.Rows(bare, "Zwoelf"))
    Check("With no clock and no id the list order becomes the order",
        reversed[1].short == "Shuja Grimaxe"
        and reversed[4].short == "Meredy Huntswell")

    local broken = Recorded()
    broken[2].name = nil
    Check("A row that cannot even be named is dropped, not drawn empty",
        #R.Rows(broken, "Zwoelf") == 3)

    -- The damage meter lists creatures as readily as people, and a creature's
    -- own name may have a hyphen in it. Cutting at the first one listed her
    -- as "Crenna Earth", which looks like a truncation bug and is not.
    Check("A creature whose own name has a hyphen keeps all of it",
        R.Rows({ { name = "Crenna Earth-Daughter", deathRecapID = 38 } },
            "Zwoelf")[1].short == "Crenna Earth-Daughter")
    Check("...and a player's realm half still comes off",
        ns.Death.StripRealm("Zwoelf-Destromath") == "Zwoelf")

    ---------------------------------------------------------------------
    -- Whose row it is
    ---------------------------------------------------------------------
    Check("The client's own isLocalPlayer decides, name or no name",
        R.IsYou({ isLocalPlayer = true, name = "Meredy Huntswell" }, "Zwoelf")
        and not R.IsYou({ isLocalPlayer = false, name = "Zwoelf" }, "Zwoelf"))
    Check("...and without the flag the name answers, realm half dropped",
        R.IsYou({ name = "Zwoelf-Destromath" }, "Zwoelf")
        and not R.IsYou({ name = "Meredy Huntswell" }, "Zwoelf"))

    ---------------------------------------------------------------------
    -- What ended each one
    ---------------------------------------------------------------------
    -- Death.ReadRecap hands events over OLDEST first, so the last one is the
    -- one that landed last. The amounts are his: 31829 with 28483 of it
    -- wasted on a corpse.
    local events = {
        { name = "Spirit Rend", who = "Tormented Shade", amount = 4000 },
        { name = "Spirit Rend", who = "Tormented Shade", amount = 31829,
          overkill = 28483, spellID = 1259255 },
    }
    local blow = R.Blow(events)
    Check("The killing blow is the last event, not the first",
        blow ~= nil and blow.amount == 31829 and blow.overkill == 28483)
    Check("...and it names the source of the hit",
        blow ~= nil and blow.who == "Tormented Shade"
        and blow.spellID == 1259255)

    -- A heal can be the newest thing in a recap - somebody was still trying.
    -- Taking the newest event blindly would print the healer as the killer.
    events[#events + 1] = { name = "a heal", who = "A Friend",
        heal = true, amount = 9000 }
    local past = R.Blow(events)
    Check("A heal after the killing blow does not become the killer",
        past ~= nil and past.who == "Tormented Shade" and past.amount == 31829)

    Check("A recap with nothing in it has no killing blow",
        R.Blow({}) == nil and R.Blow(nil) == nil)

    local counted = R.Culprits({
        { blow = { who = "Tormented Shade", spell = "Spirit Rend" } },
        { blow = { who = "Tormented Shade", spell = "Spirit Rend" } },
        { blow = { who = "Tormented Shade", spell = "Void Bolt" } },
        { blowWhy = "the recap is empty" },
    })
    Check("What did the killing is counted per ABILITY, not per mob",
        #counted == 2 and counted[1].count == 2
        and counted[1].spell == "Spirit Rend",
        string.format("%d kinds", #counted))
    Check("A death whose recap said nothing counts towards nothing",
        counted[1].count + counted[2].count == 3)

    ---------------------------------------------------------------------
    -- How the line reads
    ---------------------------------------------------------------------
    Check("A class the colour table knows is coloured",
        R.Coloured("Zwoelf", "DEATHKNIGHT"):find("|cff", 1, true) == 1)
    Check("...and one it has never heard of is still a readable name",
        R.Coloured("Meredy", "SOMETHINGNEW") == "Meredy")
    Check("The clock reads the way a fight is talked about",
        R.Clock(121) == "2:01" and R.Clock(62) == "1:02"
        and R.Clock(0) == "0:00" and R.Clock(nil) == "--:--")

    local line = R.Line({ short = "Shuja Grimaxe", class = "SHAMAN", at = 62,
        gap = 3, blow = { who = "Tormented Shade", spell = "Spirit Rend",
            amount = 31829, overkill = 28483 } }, true)
    Check("A line says when, who and to what",
        line:find("1:02", 1, true) and line:find("Shuja", 1, true)
        and line:find("Tormented Shade", 1, true)
        and line:find("Spirit Rend", 1, true), line)
    local silent = R.Line({ short = "Shuja Grimaxe",
        blowWhy = "the recap is empty" }, false)
    Check("...and a death whose recap refused says so instead of nothing",
        silent:find("the recap is empty", 1, true) ~= nil, silent)

    ---------------------------------------------------------------------
    -- Keeping the fight, because the Current session does not wait
    ---------------------------------------------------------------------
    Check("A pull is named by its FIRST death, which is its lowest id",
        R.FightKey({ { recapID = 40 }, { recapID = 37 }, { recapID = 38 } })
        == 37)
    Check("...and a list with no ids in it has no name",
        R.FightKey({}) == nil and R.FightKey({ {} }) == nil)

    local log = {}
    R.Remember(log, { key = 37, mark = "first read" }, 3)
    R.Remember(log, { key = 37, mark = "second read" }, 3)
    Check("The same pull read twice is one entry, not two",
        #log == 1 and log[1].mark == "second read")
    R.Remember(log, { key = 44 }, 3)
    Check("A pull with a different first death is a new entry", #log == 2)
    R.Remember(log, { key = 51 }, 3)
    R.Remember(log, { key = 58 }, 3)
    Check("The oldest drops out when the cap is reached",
        #log == 3 and log[1].key == 44,
        string.format("%d kept, oldest %s", #log, tostring(log[1].key)))

    ---------------------------------------------------------------------
    -- THE GAME'S OWN VERDICT
    --
    -- The recap marks damage the client itself considers avoidable. It is
    -- the most valuable field in the whole thing and the easiest to report
    -- dishonestly: a client that withholds it must not make a raid look
    -- blameless. Three answers, never two.
    ---------------------------------------------------------------------
    local function Died(flag)
        return { blow = { who = "A", spell = "B", avoidable = flag } }
    end
    local yes, no, unknown = R.Avoidable({ Died(true), Died(true),
        Died(false), Died(nil), { blowWhy = "empty" } })
    Check("Avoidable, not avoidable and NOT SAID are three answers",
        yes == 2 and no == 1 and unknown == 2,
        string.format("%d yes, %d no, %d not said", yes, no, unknown))

    Check("A pull with an avoidable death says so and counts it",
        R.Verdict({ { at = 0, blow = { avoidable = true } },
                    { at = 4, blow = { avoidable = false } } }, {})
            :find("1 of 2 to damage the game calls avoidable", 1, true) ~= nil)
    Check("...and one where the client said nothing claims NOTHING",
        R.Verdict({ { at = 0, blow = {} }, { at = 4, blow = {} } }, {})
            :find("avoidable", 1, true) == nil)
    Check("...while all-clear is only said when the client said it every time",
        R.Verdict({ { at = 0, blow = { avoidable = false } },
                    { at = 4, blow = { avoidable = false } } }, {})
            :find("none of it was avoidable", 1, true) ~= nil)

    Check("The verdict leads with the thing that killed more than one",
        R.Verdict({ { at = 0 }, { at = 2 } },
            { { who = "Shade", spell = "Grim Ward", count = 2 } })
            :find("Grim Ward killed 2 of them", 1, true) == 1)
    Check("...and says how long the dying took",
        R.Verdict({ { at = 10 }, { at = 16 } }, {})
            :find("2 deaths in 6s", 1, true) ~= nil)
    Check("A pull nobody died in has no verdict at all",
        R.Verdict({}, {}) == "")

    ---------------------------------------------------------------------
    -- The hit that mattered, which is rarely the one that finished them
    ---------------------------------------------------------------------
    -- Oldest first, the way ReadRecap hands them over. The last event is
    -- 31829 with 28483 of it wasted on a corpse, so it only LANDED 3346 -
    -- the 20000 two events earlier is the one worth talking about.
    local story = {
        { name = "Melee", who = "Shade", amount = 5000 },
        { name = "Grim Ward", who = "Shade", amount = 20000, spellID = 7 },
        { name = "a heal", who = "A Friend", amount = 90000, heal = true },
        { name = "Spirit Rend", who = "Shade", amount = 31829,
          overkill = 28483 },
    }
    local real = R.RealBlow(story)
    Check("The hit that mattered is the one that TOOK the most",
        real ~= nil and real.spell == "Grim Ward" and real.landed == 20000,
        real and real.spell)
    Check("...and a heal is never it", real ~= nil and real.who ~= "A Friend")
    Check("...and when the killing blow IS the biggest, nothing is claimed",
        R.RealBlow({ { name = "Small", who = "X", amount = 10 },
                     { name = "Big", who = "X", amount = 900 } }) == nil)
    Check("A recap of one event has no earlier hit to name",
        R.RealBlow({ { name = "Only", who = "X", amount = 10 } }) == nil)

    ---------------------------------------------------------------------
    -- The enemy tip, which three windows share
    ---------------------------------------------------------------------
    local summary = ns.Death.SourceSummary({
        { who = "Shade", name = "Melee", amount = 5000 },
        { who = "Shade", name = "Spirit Rend", amount = 31829, spellID = 7 },
        { who = "Shade", name = "Melee", amount = 4000 },
        { who = "Somebody Else", name = "Cleave", amount = 999 },
        { who = "Shade", name = "a heal", amount = 90000, heal = true },
    }, "Shade")
    Check("The tip counts only what THIS thing did",
        summary.hits == 3 and summary.total == 40829
        and summary.biggest == 31829,
        string.format("%d hits, %d total", summary.hits, summary.total))
    Check("...and names each ability once, with its id for the icon",
        #summary.spells == 2 and summary.spells[1].name == "Melee"
        and summary.spells[2].spellID == 7)

    Check("What it did reads as a sentence",
        ns.Death.EnemyFacts(summary):find("3 hits", 1, true) ~= nil)
    Check("...and one hit is not \"1 hits\"",
        ns.Death.EnemyFacts({ hits = 1, total = 500, spells = {} })
            :find("One hit", 1, true) ~= nil)
    Check("A source nothing is known about says nothing at all",
        ns.Death.EnemyFacts(nil) == "" and ns.Death.EnemySpells(nil) == "")
    Check("The ability line carries every ability",
        ns.Death.EnemySpells(summary):find("Spirit Rend", 1, true) ~= nil)

    -- It goes to disk with the pull, because the recap is gone by the time
    -- anybody points at the row.
    local stored = R.PlainSummary(summary)
    Check("The tip's facts survive a reload",
        stored ~= nil and stored.hits == 3 and #stored.spells == 2
        and stored.spells[2].spellID == 7)
    Check("...and a summary of nothing is not written",
        R.PlainSummary(nil) == nil and R.PlainSummary({}) == nil)

    ---------------------------------------------------------------------
    -- What goes to chat
    ---------------------------------------------------------------------
    local lines = R.ShareLines({
        { short = "Shuja", at = 62,
          blow = { who = "Grim Skirmisher", spell = "Melee" } },
        { short = "Meredy", at = 87, blowWhy = "the recap is empty" },
    }, { timed = true, where = "M+7 - Ara-Kara", duration = 121,
         culprits = {} })
    Check("A share names the place and the count first",
        lines ~= nil and lines[1]:find("Ara-Kara", 1, true) ~= nil
        and lines[1]:find("2 died", 1, true) ~= nil, lines and lines[1])
    Check("...and one line per death, with the time on it",
        #lines >= 3 and lines[#lines]:find("Meredy", 1, true) ~= nil
        and lines[#lines - 1]:find("1:02", 1, true) ~= nil)
    -- An inline icon is an escape sequence. It either arrives at the other
    -- end as raw punctuation or not at all, so it is stripped - Death's rule
    -- and Death's own function.
    Check("...with no inline icons in it",
        table.concat(lines, " "):find("|T", 1, true) == nil)
    Check("A pull with nobody dead has nothing to share",
        R.ShareLines({}, {}) == nil and R.ShareLines(nil, nil) == nil)

    ---------------------------------------------------------------------
    -- Surviving a reload
    --
    -- A new saved-variable schema, so the two rules are checked rather than
    -- commented: only what is READABLE goes in, copied field by field, and a
    -- fight nothing could be read out of is not kept.
    ---------------------------------------------------------------------
    local fight = {
        key = 37, when = "21:14", where = "M+7 - Ara-Kara",
        whereShort = "M+7", instance = "Ara-Kara, City of Echoes",
        journal = 1271, duration = 121, at = 99999,
        entries = {
            { name = "Shuja Grimaxe", short = "Shuja Grimaxe",
              class = "SHAMAN", at = 62, seq = 1, recapID = 37, you = false,
              blow = { who = "Grim Skirmisher", spell = "Melee",
                       amount = 39900, overkill = 8300,
                       art = { creatureID = 214390 },
                       summary = { hits = 2, total = 44000, biggest = 39900,
                           spells = { { name = "Melee" } } } } },
            { name = "Meredy Huntswell", short = "Meredy Huntswell",
              class = "MAGE", at = 87, seq = 4, recapID = 40, you = false,
              blowWhy = "the recap is empty" },
        },
    }

    local saved = R.Persist(fight)
    Check("A pull is written field by field",
        saved ~= nil and saved.key == 37 and #saved.entries == 2
            and saved.whereShort == "M+7")
    -- The side column's third line and its tile come out of these two, and
    -- for an evening they were written by the session copy and NOT by this
    -- one - so the tile lived until the next /reload.
    Check("...and the place and its guide id survive the reload",
        saved.instance == "Ara-Kara, City of Echoes" and saved.journal == 1271)
    -- And a pull saved before they did takes them from the evening's copy
    -- of the same pull - by key, never by position.
    do
        local log = { { key = 5 }, { key = 6, instance = "Kept", journal = 1 } }
        R.Mend(log, { fights = {
            { key = 6, instance = "Other", journal = 2 },
            { key = 5, instance = "Murder Row", journal = 1304 } } })
        Check("A pull without its place takes it from the evening's copy, by key",
            log[1].instance == "Murder Row" and log[1].journal == 1304
            and log[2].instance == "Kept" and log[2].journal == 1)
        Check("...and nothing happens without a copy to read from",
            #R.Mend({ { key = 1 } }, nil) == 1 and R.Mend(nil, nil) == nil)
    end
    -- `at` is a GetTime stamp and GetTime restarts with the client, so a
    -- stored one would be a time in a clock that no longer exists.
    Check("...and the GetTime stamp is deliberately NOT written",
        saved.at == nil)
    Check("...and the killer's face travels with it",
        saved.entries[1].blow ~= nil
        and saved.entries[1].blow.art.creatureID == 214390)
    -- The RULE for reducing a summary is checked on its own further up. This
    -- checks that Persist actually CALLS it - the recap is gone after a
    -- reload, so a tip with no facts on disk is a tip with no facts at all.
    Check("...and so does what that mob did, for the enemy tip",
        saved.entries[1].blow.summary ~= nil
        and saved.entries[1].blow.summary.hits == 2
        and #saved.entries[1].blow.summary.spells == 1)
    Check("...and a death whose recap said nothing keeps the reason",
        saved.entries[2].blowWhy == "the recap is empty"
        and saved.entries[2].blow == nil)

    fight.entries[1].junk = { "a field nobody whitelisted" }
    Check("A field nobody named never reaches the disk",
        R.Persist(fight).entries[1].junk == nil)
    fight.entries[1].junk = nil

    local back = R.Restore({ saved })
    Check("It reads back as one pull with both deaths",
        #back == 1 and #back[1].entries == 2
        and back[1].entries[1].short == "Shuja Grimaxe")
    -- Derived on the way in, not stored: a better count written next month
    -- applies to the pulls already on disk.
    Check("...with the killing counted afresh rather than stored",
        back[1].culprits ~= nil and #back[1].culprits == 1
        and back[1].culprits[1].who == "Grim Skirmisher")

    Check("A pull with nothing readable in it is not kept",
        R.Persist({ entries = {} }) == nil and R.Persist(nil) == nil
        and #R.Restore({ { entries = {} } }) == 0)
    Check("...and neither is a death that cannot even be named",
        #R.Persist({ entries = { { name = 5 },
            { name = "Real Person" } } }).entries == 1)

    ---------------------------------------------------------------------
    -- What the footer says
    ---------------------------------------------------------------------
    Check("A count where nothing repeats is not worth printing",
        not R.WorthCounting({ { count = 1 }, { count = 1 } })
        and R.WorthCounting({ { count = 1 }, { count = 2 } }))
    Check("...so four deaths to four things say it in one sentence",
        R.FootLine({ { who = "A", spell = "B", count = 1 } }, 4)
            :find("each to something different", 1, true) ~= nil)
    Check("...and something that killed three is named and counted",
        R.FootLine({ { who = "Shade", spell = "Rend", count = 3 } }, 3)
            :find("3x Shade", 1, true) ~= nil)
    Check("A fight nobody died in has no footer at all",
        R.FootLine({}, 0) == "")
    Check("The footer offers the click only when something can be opened",
        R.FootLine({}, 4, true):find("last 10 seconds", 1, true) ~= nil
        and R.FootLine({}, 4, false):find("last 10 seconds", 1, true) == nil)
    -- The same sentence as pieces: names carry the tip, abilities the icon.
    local pieces = R.FootPieces({ { who = "Shade", spell = "Rend", count = 3,
        spellID = 5 } }, 3, true, {})
    local sawWho, sawSpell, sawHint = false, false, false
    for _, piece in ipairs(pieces) do
        if piece.who == "Shade" then sawWho = true end
        if piece.spell == "Rend" and piece.spellID == 5 then sawSpell = true end
        if piece.text and piece.text:find(R.FOOT_HINT, 1, true) then sawHint = true end
    end
    Check("The footer's pieces carry the mob and the ability apart",
        sawWho and sawSpell and sawHint)
    -- The face rides inside the name piece, never as a piece of its own:
    -- a lone face piece stood in front of "Killed by" instead of the mob,
    -- and with no picture it printed the name twice.
    do
        local lines = R.DetailLines({
            blow = { who = "Primal Serpent", spell = "Piercing Hiss",
                spellID = 9, amount = 100, overkill = 10 },
            real = { who = "Primal Serpent", spell = "Piercing Hiss",
                spellID = 9, landed = 90 },
            events = {},
        })
        local lone, named, order = false, 0, true
        for _, line in ipairs(lines) do
            for index, piece in ipairs(line.pieces) do
                if piece.face then lone = true end
                if piece.who then
                    named = named + 1
                    -- The name follows the words, and the ability follows it.
                    if not (line.pieces[index - 1] and line.pieces[index - 1].text
                        and line.pieces[index + 2] and line.pieces[index + 2].spell) then
                        order = false
                    end
                end
            end
        end
        Check("A detail line names the mob once, after the words, with no lone face piece",
            #lines == 2 and not lone and named == 2 and order)
        -- And a mob this death kept no picture of wears the face another
        -- kept pull has for it - the same fallback the footer uses.
        local log = { { entries = { { blow = { who = "Primal Serpent",
            art = { creatureID = 77 } } } } } }
        local borrowed = R.DetailLines({
            blow = { who = "Primal Serpent", spell = "Hiss", amount = 1 },
            events = {} }, log)
        local face
        for _, piece in ipairs(borrowed[1].pieces) do
            if piece.who then face = piece.art end
        end
        Check("A detail line borrows the mob's face from another kept pull",
            face ~= nil and face.creatureID == 77)
        local foot = R.FootPieces({ { who = "Primal Serpent", spell = "Hiss",
            count = 2 } }, 2, false, {}, log)
        local footFace
        for _, piece in ipairs(foot) do
            if piece.who then footFace = piece.art end
        end
        Check("...and so does the footer", footFace ~= nil and footFace.creatureID == 77)
    end
    -- The evening's tally finds a mob's face in whichever kept pull has it.
    Check("The mob's face is found across the kept pulls",
        R.ArtForWho({ { entries = { { blow = { who = "A" } } } },
            { entries = { { events = { { who = "Shade", art = { creatureID = 7 } } } } } } },
            "Shade").creatureID == 7
        and R.ArtForWho({}, "Shade") == nil
        and R.ArtForWho(nil, nil) == nil)
    -- The replay's title names the killer as a piece with its face and
    -- its summary, after the words - and is just "Replay" without one.
    do
        local pieces = ns.Replay.TitlePieces({ killer = "Shade",
            killerArt = { creatureID = 3 },
            events = { { who = "Shade", amount = 10, t = 1 } } })
        Check("The replay's title carries the killer with its face and tip",
            #pieces == 2 and pieces[1].text == "Replay - killed by "
            and pieces[2].who == "Shade" and pieces[2].art.creatureID == 3
            and type(pieces[2].summary) == "table")
        Check("...and is only the word without a killer",
            ns.Replay.TitlePieces({})[1].text == "Replay"
            and #ns.Replay.TitlePieces(nil) == 1)
    end
    Check("The evening's fallen carry their spec, for the icon",
        R.Fallen({ fights = { { entries = { { name = "Zed", class = "DEATHKNIGHT",
            spec = 250 } } } } })[1].spec == 250)
    Check("...and none for a fight nobody died in", #R.FootPieces({}, 0) == 0)

    ---------------------------------------------------------------------
    -- ONE DEATH, KEPT WHOLE AND OPENED
    ---------------------------------------------------------------------
    local story = {
        { t = 8.2, amount = 4000, hp = 30000, name = "Melee",
            who = "Grim Skirmisher", avoidable = false },
        { t = 5.0, amount = 12000, hp = 18000, name = "Grim Ward",
            who = "Grim Skirmisher", spellID = 1234, avoidable = true },
        { t = 2.0, amount = 9000, hp = 27000, name = "Renew", heal = true },
        { t = 0.0, amount = 31829, overkill = 28483, name = "Spirit Rend",
            who = "Tormented Shade", spellID = 1259255,
            art = { creatureID = 220003 } },
    }

    local kept, dropped = R.PlainEvents(story)
    -- The face rides every hit, not only the killing blow - the opened
    -- death draws it in front of each row.
    Check("...and each hit keeps the face of what did it",
        kept[4].art ~= nil and kept[4].art.creatureID == 220003
        and kept[1].art == nil)
    Check("A recap's hits are kept, field by field",
        kept ~= nil and #kept == 4 and dropped == 0
        and kept[4].overkill == 28483 and kept[2].spellID == 1234)
    Check("...a heal stays marked as one",
        kept[3].heal == true and kept[1].heal == false)
    Check("...and avoidable survives as a boolean, nil included",
        kept[2].avoidable == true and kept[1].avoidable == false
        and kept[4].avoidable == nil)

    -- The cap, and it must keep the END of the story: the hits nearest the
    -- death are the ones the window is opened for.
    local long = {}
    for i = 1, R.EVENTS_KEPT + 6 do
        long[i] = { t = 30 - i * 0.1, amount = i, name = "Hit " .. i }
    end
    local trimmed, cut = R.PlainEvents(long)
    Check("A very long death is trimmed from the OLD end",
        trimmed ~= nil and #trimmed == R.EVENTS_KEPT and cut == 6
        and trimmed[#trimmed].name == "Hit " .. #long)
    Check("...and nothing readable at all keeps nothing",
        R.PlainEvents({ { t = "secret", amount = 1 } }) == nil
        and R.PlainEvents("not a list") == nil)

    -- THE GAME'S OWN VERDICT over the hits, three answers and never two.
    local yes, no, unknown = R.AvoidableHits(kept)
    Check("Avoidable hits are counted, and heals are not damage",
        yes == 1 and no == 1 and unknown == 1)
    local _, cleanNo, cleanUnknown = R.AvoidableHits({
        { amount = 1, avoidable = false }, { amount = 2, avoidable = false } })
    Check("...a clean bill needs the game to have answered every time",
        R.DetailVerdict({ { amount = 1, avoidable = false } })
            :find("None of this", 1, true) ~= nil
        and cleanNo == 2 and cleanUnknown == 0)
    Check("...and one unanswered hit takes the clean bill away",
        R.DetailVerdict({ { amount = 1, avoidable = false },
            { amount = 2 } }) == "")
    Check("...while one it DID call avoidable is counted out loud",
        R.DetailVerdict(kept):find("1 of these hits is", 1, true) ~= nil)

    Check("A death with nothing kept cannot be opened",
        not R.Openable(nil) and not R.Openable({ name = "X" })
        and not R.Openable({ events = {} }) and R.Openable({ events = kept }))

    local entry = {
        name = "Meredy Huntswell", short = "Meredy",
        class = "PRIEST", at = 87, you = false,
        events = kept, maxHP = 41000, dropped = 6,
        blow = { who = "Tormented Shade", spell = "Spirit Rend",
            amount = 31829, overkill = 28483 },
        real = { who = "Grim Skirmisher", spell = "Grim Ward", landed = 12000 },
    }
    Check("The opened death names who fell and when",
        R.DetailTitle(entry, true):find("Meredy", 1, true) ~= nil
        and R.DetailTitle(entry, true):find("1:27", 1, true) ~= nil)
    Check("...and says nothing about a clock it does not have",
        R.DetailTitle(entry, false):find(":", 1, true) == nil)
    local line = R.DetailLine(entry)
    Check("...what ended them, and what actually dropped them",
        line:find("Tormented Shade", 1, true) ~= nil
        and line:find("overkill", 1, true) ~= nil
        and line:find("The hit that mattered", 1, true) ~= nil)
    Check("...and a death whose recap said nothing says that instead",
        R.DetailLine({ blowWhy = "the recap gave nothing" })
            == "the recap gave nothing")
    Check("What was cut off is said out loud, never silently",
        R.DetailNote(entry, false, 10):find("6 older hits", 1, true) ~= nil
        and R.DetailNote({}, false, 10):find("older", 1, true) == nil)
    Check("...and so is a recap that reaches back past the window",
        R.DetailNote({}, true, 10):find("all the recap gave", 1, true) ~= nil)

    -- ACROSS THE DISK. The story is the whole point of the feature and it is
    -- read after a reload more often than before one.
    local rebuilt = R.Persist({ entries = { entry } })
    local back = rebuilt and rebuilt.entries[1]
    Check("The last seconds survive being written and read back",
        back ~= nil and back.events ~= nil and #back.events == #kept
        and back.maxHP == 41000
        and back.events[4].overkill == 28483)
    Check("...including the three-way avoidable answer",
        back.events[2].avoidable == true
        and back.events[1].avoidable == false
        and back.events[4].avoidable == nil)
    Check("...and the count of what was never kept is not lost on the way",
        back.dropped == 6)

    ---------------------------------------------------------------------
    -- THE PULL COLUMN FITS THE WINDOW
    --
    -- Raising the row count is one word, and the rows that do not fit are
    -- drawn straight through the buttons at the bottom - which nothing on a
    -- desk can SEE. The sum can be done, though, and it is the whole of what
    -- went wrong the first time the evening's row was added to the top of
    -- that column.
    ---------------------------------------------------------------------
    local L = R.LAYOUT
    local room = L.height - (ns.UI.HEADER_H + L.top) - L.bottom
    local needed = L.title + (L.sideRows + L.extra) * (L.sideRowH + L.sideGap)
    Check("Every row of the pull column fits inside the window",
        needed <= room,
        string.format("%d needed, %d there", needed, room))
    -- And it is not wasting half a column either: a window with room for
    -- four more rows than it draws is a list that was never re-counted after
    -- the window grew.
    Check("...and does not leave a row's worth of empty column",
        room - needed < (L.sideRowH + L.sideGap),
        string.format("%d spare", room - needed))

    ---------------------------------------------------------------------
    -- THE WHOLE EVENING, which no single pull can answer
    ---------------------------------------------------------------------
    local function Pull(key, when, dead)
        local fight = { key = key, when = when, whereShort = "M+7",
            entries = {} }
        for _, one in ipairs(dead) do
            fight.entries[#fight.entries + 1] = {
                name = one[1] .. "-Realm", short = one[1], class = "PRIEST",
                blow = { who = one[2], spell = one[3], avoidable = one[4] },
            }
        end
        return fight
    end

    local light = R.Light(Pull(10, "20:41", {
        { "Ana", "Skirmisher", "Grim Ward", true },
        { "Bo", "Skirmisher", "Grim Ward", false },
    }))
    Check("A pull is reduced to the line a tally reads",
        light ~= nil and #light.entries == 2 and light.key == 10
        and light.entries[1].who == "Skirmisher"
        and light.entries[1].avoidable == true
        and light.entries[2].avoidable == false)
    Check("...and it carries no hits, which is the whole point",
        light.entries[1].events == nil and light.entries[1].blow == nil)
    Check("...a fight nothing could be named out of is not kept",
        R.Light({ entries = { { name = 7 } } }) == nil
        and R.Light(nil) == nil)

    local session = { day = "2026-08-14", fights = {} }
    R.RememberSession(session, light, "2026-08-14", 60)
    R.RememberSession(session, R.Light(Pull(10, "20:42", {
        { "Ana", "Skirmisher", "Grim Ward", true },
        { "Bo", "Skirmisher", "Grim Ward", false },
        { "Cy", "Shade", "Spirit Rend", nil },
    })), "2026-08-14", 60)
    Check("The same pull captured again REPLACES its line",
        #session.fights == 1 and #session.fights[1].entries == 3)

    R.RememberSession(session, R.Light(Pull(20, "21:05", {
        { "Ana", "Skirmisher", "Grim Ward", true },
        { "Cy", "Golem", "Slam", false },
    })), "2026-08-14", 60)
    Check("...and the next pull is a new line",
        #session.fights == 2)

    local killers = R.Repeat(session)
    Check("What keeps killing us is counted across pulls",
        #killers == 3 and killers[1].spell == "Grim Ward"
        and killers[1].deaths == 3 and killers[1].pulls == 2)
    Check("...and a thing that killed twice on ONE pull is not a pattern",
        R.RepeatLine(killers[1]):find("across 2 pulls", 1, true) ~= nil
        and R.RepeatLine({ deaths = 2, pulls = 1 })
            :find("on one pull", 1, true) ~= nil)

    local fallen = R.Fallen(session)
    Check("Who is falling is counted, most first",
        #fallen == 3 and fallen[1].short == "Ana" and fallen[1].deaths == 2
        and fallen[1].pulls == 2 and fallen[1].avoidable == 2)
    -- Cy fell twice as well, so the tie breaks on the name and Cy is second.
    -- One of those deaths the game called not avoidable and about the other
    -- it said nothing, and the two must not be added together.
    Check("...and a death the game said nothing about is held apart",
        fallen[2].short == "Cy" and fallen[2].deaths == 2
        and fallen[2].avoidable == 0 and fallen[2].unknown == 1)
    Check("...so the line about a person claims only what was answered",
        R.FallenLine(fallen[1]):find("2 to avoidable", 1, true) ~= nil
        and R.FallenLine(fallen[2]):find("avoidable", 1, true) == nil)

    Check("The evening's one line counts pulls and deaths",
        R.SessionLine(session):find("2 pulls, 5 deaths", 1, true) ~= nil
        and R.SessionLine({ fights = {} }) == "")

    local told = R.SessionShareLines(session)
    Check("...and it can be said in chat, worst thing first",
        told ~= nil and #told >= 2
        and told[1]:find("Tonight", 1, true) ~= nil
        and told[2]:find("Grim Ward", 1, true) ~= nil)
    Check("...with nothing to say when nothing was kept",
        R.SessionShareLines({ fights = {} }) == nil)

    -- A NEW DAY IS A NEW EVENING, on both roads: the one that keeps a pull
    -- and the one that reads the disk. "Third wipe tonight" must never be a
    -- number from a raid two days ago.
    R.RememberSession(session, light, "2026-08-15", 60)
    Check("A pull on a new day starts the evening over",
        #session.fights == 1 and session.day == "2026-08-15")
    Check("...and yesterday's tally is not loaded under the word tonight",
        #R.RestoreSession({ day = "2026-08-14",
            fights = { light } }, "2026-08-15").fights == 0
        and #R.RestoreSession({ day = "2026-08-15",
            fights = { light } }, "2026-08-15").fights == 1)

    local capped = { day = "d", fights = {} }
    for i = 1, 8 do
        R.RememberSession(capped, R.Light(Pull(i, "20:00",
            { { "Ana", "X", "Y", nil } })), "d", 5)
    end
    Check("...and the evening does not grow without end",
        #capped.fights == 5 and capped.fights[1].key == 4)

    ---------------------------------------------------------------------
    -- THE WIRING, not the rule. Everything above is arithmetic on tables
    -- this file typed out. This asks the client the addon will actually ask,
    -- and reports what came back rather than asserting a fight is running.
    ---------------------------------------------------------------------
    local entries, why, info = R.Collect()
    if not (entries and info) then
        Skip("Reading the deaths the client is holding", why or "?")
        return
    end

    Check("The client's own list comes back ordered",
        #entries > 0 and (not info.timed
            or entries[1].at <= entries[#entries].at),
        string.format("%d deaths, %s", #entries,
            info.timed and "timed" or "no clock"))

    local read, refused = 0, 0
    for _, entry in ipairs(entries) do
        if entry.blow then read = read + 1
        elseif entry.blowWhy then refused = refused + 1 end
    end
    Check("Every death either read its recap or said why it could not",
        read + refused == #entries,
        string.format("%d read, %d refused", read, refused))

    Skip("What the client is holding right now", string.format(
        "%d deaths in %s%s, %d recaps read", #entries, info.label,
        info.duration and (" of " .. R.Clock(info.duration)) or "", read))

    -- WHICH DOOR THE FACES TOOK, and this is REPORTED rather than asserted.
    -- The flat portrait needs a display id, the recap hands over an npc id,
    -- and the only route between them is a model saying so after it has
    -- loaded. None of that can be proven at a desk with no game in it, so
    -- the addon counts what actually happened and this line reads it back.
    -- If `flat` is 0 after a window has been open, the 2D door never opened
    -- on this client and the head-shot models are what is on screen.
    local faces = ns.Death.faceStats or {}
    Skip("How the mob faces were drawn", string.format(
        "%d flat portraits, %d models, %d had no art at all",
        faces.flat or 0, faces.model or 0, faces.none or 0))

    local named = 0
    for _, entry in ipairs(entries) do
        if entry.spec then named = named + 1 end
    end
    Skip("How many of the dead had a readable spec", string.format(
        "%d of %d - the rest wear their class icon", named, #entries))

    -- And the capture, driven against whatever the client has. A fight with
    -- no clock on it must NOT be kept: that is Overall, and keeping it would
    -- overwrite a good capture with a worse one.
    local before = R.log
    R.log = {}
    local fight = R.Capture()
    if not fight then
        Skip("Keeping the fight", info.timed
            and "the client had a timed session but nothing was kept"
            or "no timed session right now, so there is nothing to keep")
    else
        Check("A timed fight is kept whole",
            #R.log == 1 and #fight.entries > 0 and fight.key ~= nil,
            string.format("%d deaths, pull %s", #fight.entries,
                tostring(fight.key)))
        R.Capture()
        Check("...and reading the same pull again replaces it",
            #R.log == 1, string.format("%d fights kept", #R.log))
    end
    R.log = before
end

---------------------------------------------------------------------------
-- Running it
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- The design system
--
-- Colour and type are not usually worth a test, and these are not tests of
-- taste. They are the three rules the palette is BUILT on - if one of them
-- gets tuned away the window still renders, still passes every other check,
-- and quietly stops working the way it was drawn.
---------------------------------------------------------------------------
local function TestDesignSystem()
    local UI = ns.UI
    local C = UI.C

    ---------------------------------------------------------------------
    -- A ROW'S TEXT STOPS BEFORE ITS CONTROL - BOTH LINES OF IT
    --
    -- The owner photographed the welcome window with a module's blurb drawn
    -- straight through the NEW badge beside it. The label had been stopped at
    -- the control since this widget was written and the SUBLABEL never was:
    -- it got one anchor, top-left, and ran the full width of the row.
    --
    -- Invisible for as long as every blurb was short enough, and every page
    -- in the addon uses this row.
    --
    -- The rule is checkable without a screen because it is not about pixels:
    -- a piece of text with ONE anchor has no right-hand edge at all. Two
    -- anchors is what "stops somewhere" means, in game and out here alike.
    ---------------------------------------------------------------------
    local sampleParent = CreateFrame("Frame", nil, UIParent)
    local sample = UI.Row(sampleParent, "Label", {
        sublabel = "A second line long enough to run under a control",
        controlWidth = 96,
    })

    Check("A row's label stops before its control",
        sample.label and sample.label:GetNumPoints() >= 2,
        sample.label and tostring(sample.label:GetNumPoints()) or "no label")

    Check("A row's second line stops before its control too",
        sample.sub and sample.sub:GetNumPoints() >= 2,
        sample.sub and tostring(sample.sub:GetNumPoints()) or "no sublabel")

    -- And a row WITHOUT one still has exactly the label. Written because the
    -- fix above is one `if row.sub`, and an `if` that is wrong in the other
    -- direction throws on every ordinary row in the addon.
    local plain = UI.Row(sampleParent, "Label", { controlWidth = 96 })
    Check("A row with no second line is still built",
        plain.label ~= nil and plain.sub == nil)

    local names = {
        "canvasBg", "windowBg", "sidebarBg", "well", "surface", "control",
        "controlHi", "separator", "edge", "overlayEdge", "accent", "accentSoft",
        "accentCool", "accentCoolSoft", "inUse", "inUseSoft", "danger",
        "warning", "text", "textBody", "textDim", "textFaint", "textGhost",
        -- Derived rather than designed, and referenced in two dozen places.
        "surfaceHi", "accentDim",
    }
    local complete, broken = true, nil
    for _, name in ipairs(names) do
        local colour = C[name]
        if type(colour) ~= "table" or #colour < 3 then
            complete, broken = false, name
            break
        end
        for channel = 1, 3 do
            local v = colour[channel]
            if type(v) ~= "number" or v < 0 or v > 1 then
                complete, broken = false, name
                break
            end
        end
        if not complete then break end
    end
    Check("Every colour the window asks for exists", complete,
        broken and ("missing or out of range: " .. broken))

    -- EVERY MEASUREMENT THE WINDOW IS BUILT FROM.
    --
    -- This check exists because it was earned. Re-tuning the palette dropped
    -- UI.HEADER_H with the block it happened to sit in; nothing caught it -
    -- the static check sees a field, not a missing one, and no model test
    -- opens a window - and the first thing that noticed was the client, with
    -- "attempt to perform arithmetic on a nil value" and no window at all.
    -- One constant read at file scope by three files is worth one loop.
    local metrics = {
        "HEADER_H", "ROW_H", "ROW_GAP", "SECTION_H", "COL_GAP",
        "WINDOW_W", "WINDOW_H", "RAIL_W", "INSPECTOR_W", "CONTENT_W",
        "CARD_HEAD_H", "NAV_ITEM_H", "CONTROL_H", "BUTTON_H", "SLIDER_H",
        "PAD", "GAP", "RADIUS",
    }
    local measured, missing = true, nil
    for _, name in ipairs(metrics) do
        if type(UI[name]) ~= "number" then
            measured, missing = false, name
            break
        end
    end
    Check("Every measurement the window is built from exists", measured,
        missing and ("UI." .. missing .. " is " .. type(UI[missing])))

    -- The three columns add up to the window. A change to one of them that
    -- forgets the others leaves a stripe of nothing down the middle.
    Check("The three columns add up to the window",
        UI.RAIL_W + UI.CONTENT_W + UI.INSPECTOR_W == UI.WINDOW_W,
        string.format("%d + %d + %d vs %d", UI.RAIL_W, UI.CONTENT_W,
            UI.INSPECTOR_W, UI.WINDOW_W))

    -- The inversion the whole redesign turns on. The side columns used to be
    -- LIGHTER than the window, which put the content in a trench.
    local function Lum(c) return c[1] + c[2] + c[3] end
    Check("The side columns are darker than the window",
        Lum(C.sidebarBg) < Lum(C.windowBg),
        string.format("sidebar %.3f vs window %.3f", Lum(C.sidebarBg),
            Lum(C.windowBg)))

    -- There are no shadows here, so an overlay can only say it is on top by
    -- being outlined brighter than anything the page can draw.
    Check("An overlay outlines brighter than the page does",
        Lum(C.overlayEdge) > Lum(C.edge),
        string.format("overlay %.3f vs edge %.3f", Lum(C.overlayEdge),
            Lum(C.edge)))

    -- Five sizes, each clearly apart from the next. Two sizes one point apart
    -- are not a hierarchy, they are a mistake nobody can see.
    local ladder = { UI.FS.title, UI.FS.card, UI.FS.row, UI.FS.meta,
        UI.FS.eyebrow }
    local descends = true
    for i = 2, #ladder do
        if not (ladder[i] and ladder[i - 1] and ladder[i] < ladder[i - 1]) then
            descends = false
            break
        end
    end
    Check("The five text sizes descend", descends,
        table.concat({ tostring(ladder[1]), tostring(ladder[2]),
            tostring(ladder[3]), tostring(ladder[4]), tostring(ladder[5]) }, " "))

    -- TWO CHANNELS ON ONE BUTTON, AND THEY ARE NOT THE SAME QUESTION.
    --
    -- "This is the current mode" is a bed; "you cannot press this" is a dimmed
    -- label. They were the same channel once, on edit mode's Move/Build pair,
    -- where the mode that was simply not current read as a dead button.
    --
    -- The colour cannot be read back out here - the harness has no pixels - so
    -- what this checks is that both channels still exist and still take a
    -- call. A button that lost SetActive throws in the one place that has no
    -- test of its own: the overlay, in combat, with no window open.
    local probe = UI.Button(UIParent, "Probe", 80, nil)
    local channels = type(probe.SetActive) == "function"
        and type(probe.SetEnabled) == "function"
    if channels then
        channels = pcall(function()
            probe:SetActive(true)
            probe:SetEnabled(false)
            probe:SetEnabled(true)
            probe:SetActive(false)
        end)
    end
    Check("A button can say it is the one that is on", channels)

    -- An item with no tab is on every tab; a page with no tabs shows all of
    -- them. Both nil cases are decisions, and both were wrong once.
    Check("A row with no tab shows on every tab",
        UI.OnTab(nil, "Look") and UI.OnTab(nil, nil))
    Check("A page with no tabs shows every row",
        UI.OnTab("Look", nil) and UI.OnTab("Reuse", nil))
    Check("A row shows only on its own tab",
        UI.OnTab("Look", "Look") and not UI.OnTab("Look", "Reuse"))

    -- Every icon named in a DATA table has to resolve to a file.
    --
    -- An unknown name does not throw and does not draw nothing: UI.Glyph falls
    -- back to four rectangles in the shape of a grid. So a typo, or a file
    -- dropped from Media/icons, ships as the wrong mark and looks deliberate -
    -- which is exactly the failure that started this whole redesign.
    --
    -- The lists are walked rather than copied. A second list of names here
    -- would be a list that goes stale the first time one is added.
    -- Edit mode reads its working habits through one function that fills in
    -- anything a profile is missing. That function used to carry its OWN list
    -- of four keys next to the seven the profile declares, and `snapToGrid`
    -- was in one list and not the other - so grid snapping was permanently off
    -- on any profile older than the key, with nothing on screen saying why.
    --
    -- It fills from ns.DEFAULTS.editMode now. This is the check that the keys
    -- the panel reads are all actually in there.
    for _, key in ipairs({ "grid", "gridStep", "snapDistance",
        "snapToGrid", "dim", "showCoords" }) do
        Check("Edit mode default: " .. key,
            ns.DEFAULTS.editMode[key] ~= nil)
    end

    -- Arrangement, Fill order and Across left with the bars. Each one was a
    -- list of choices for a page that no longer exists, and this check was
    -- the only thing left reading them - a guard standing over a menu nobody
    -- can open. The lists went; this is what remains, and every one of them
    -- is drawn by a page you can still reach.
    local marked = {
        { "Down", ns.GROW_Y },
        { "Fill", ns.FILL_DIRECTIONS },
        { "Places", ns.SHOW_WHERE },
    }
    for _, pair in ipairs(marked) do
        local label, list = pair[1], pair[2]
        local bad
        for _, entry in ipairs(list or {}) do
            if not (entry.icon and UI.HasIcon(entry.icon)) then
                bad = entry.icon or (entry.text or entry.key or "?")
                break
            end
        end
        Check(label .. " marks all resolve to a file", not bad, bad)
    end

    -----------------------------------------------------------------------
    -- WHICH CUT OF A MARK GETS LOADED
    --
    -- Every mark in the window was soft for months because this decision was
    -- one comparison against `UIParent:GetEffectiveScale() > 1.25` - a number
    -- that is never above 1.25 on a real machine, so the smallest file was
    -- loaded every time and then stretched. A rule that is a screen
    -- measurement cannot be checked by reading it, which is why it is pure
    -- now and checked here.
    --
    -- THE ONE THING THAT MUST HOLD: never upscale by more than the slack.
    -----------------------------------------------------------------------
    local CUTS = ns.UI.ICON_CUTS
    Check("There are four cuts of every mark", #CUTS == 4, tostring(#CUTS))

    for _, canvas in ipairs({ 16, 32 }) do
        for _, perUnit in ipairs({ 0.75, 1, 1.33, 1.5, 1.79, 2, 2.5, 4 }) do
            local cut = ns.UI.IconCutFor(canvas, perUnit)
            local wanted = canvas * perUnit
            local biggest = CUTS[#CUTS]
            -- Never stretched further than the design's own 14-into-16, and
            -- the only permitted exception is a screen denser than the
            -- largest file we ship, where there is nothing better to load.
            local ok = cut >= wanted * ns.UI.ICON_SLACK or cut == biggest
            Check(string.format("A %d box at %.2f px/unit is not stretched",
                canvas, perUnit), ok,
                string.format("picked %d for %.1f px", cut, wanted))
        end
    end

    -- And it must not reach for a bigger file than it needs: that is a
    -- download and a texture load for nothing.
    Check("A 16 box at 1:1 takes the 14 cut",
        ns.UI.IconCutFor(16, 1) == 14, tostring(ns.UI.IconCutFor(16, 1)))
    Check("A 16 box on a dense screen takes the 22 cut",
        ns.UI.IconCutFor(16, 1.33) == 22, tostring(ns.UI.IconCutFor(16, 1.33)))
    Check("A 32 box at 1:1 takes the 28 cut",
        ns.UI.IconCutFor(32, 1) == 28, tostring(ns.UI.IconCutFor(32, 1)))
    Check("Nothing bigger than the biggest cut exists",
        ns.UI.IconCutFor(32, 99) == CUTS[#CUTS])

    -----------------------------------------------------------------------
    -- A WHEEL OVER A LIST THAT CANNOT SCROLL
    --
    -- EnableMouseWheel swallows the gesture whether or not there is anything
    -- to move. In the death window that wheel is how you page between
    -- deaths, and the event list covers most of the window - so a death with
    -- three hits would have eaten the gesture over the area you are most
    -- likely to be pointing at. The escape hatch is a contract of the
    -- widget, so it is checked on the widget.
    -----------------------------------------------------------------------
    do
        local host = CreateFrame("Frame", nil, UIParent)
        host:SetSize(200, 100)
        host:Hide()
        local scroll, content = ns.UI.ScrollArea(host, 200, 8)
        -- One unit tall: there is nothing to scroll, by construction.
        content:SetHeight(1)

        local passed_ = false
        scroll.OnIdleWheel = function(delta) passed_ = (delta == -1) end

        local handler = scroll:GetScript("OnMouseWheel")
        Check("A scrolling area answers the wheel", handler ~= nil)
        if handler then
            handler(scroll, -1)
            Check("A wheel a list cannot use is handed back, not swallowed",
                passed_)
        end
    end

    -----------------------------------------------------------------------
    -- WHAT A DRAG BETWEEN TWO PLACES MEANS
    --
    -- Owner, 2026-08-13: "ich haette gern das alle spells, icons what ever im
    -- addon drag and drop bar sind ... also auch plaetze tauschen, reinziehen,
    -- rausziehen etc. ueberall wo man sachen adden kann."
    --
    -- The rule is checked here and the hands are not, and that split is
    -- forced: the harness answers GetCursorPosition with a constant 0,0 and
    -- IsVisible with false, so every hit test comes back nil out here. A check
    -- driven through the real widgets would prove the stub refuses drops.
    -----------------------------------------------------------------------
    do
        local What = ns.UI.DragOutcome

        Check("Dragging nothing is not a gesture",
            What({ kind = "spell" }, { kind = "spell" }) == "none")

        Check("Let go over open air and it comes off",
            What({ kind = "spell", payload = 42 }, nil) == "clear")

        Check("Let go over an empty place and it goes there",
            What({ kind = "spell", payload = 42 },
                 { kind = "spell" }) == "drop")

        Check("Let go over a full place and the two change places",
            What({ kind = "spell", payload = 42 },
                 { kind = "spell", payload = 99 }) == "swap")

        Check("Let go over where it started and nothing happens",
            What({ kind = "spell", payload = 42 },
                 { kind = "spell", payload = 42, same = true }) == "none")

        -- THE ONE THAT STOPS A SILENT CORRUPTION. One list holds every grid in
        -- the window, so a raid bar place - which holds the word "mark3" - is
        -- a neighbour of a cooldown cell, which holds a number. Written into
        -- each other they draw an empty square and say nothing about why.
        Check("A marker may not be dropped into a cooldown bar",
            What({ kind = "raidbar", payload = "mark3" },
                 { kind = "spell", payload = 42 }) == "refused")

        Check("A cooldown may not be dropped onto the raid bar",
            What({ kind = "spell", payload = 42 },
                 { kind = "raidbar" }) == "refused")

        -- Squares that are a VIEW of a set rather than an arrangement: the
        -- death log sorts its defensives by name and rebuilds them every
        -- refresh, so a swap would take both out, put both back and change
        -- nothing - which reads as broken rather than as refused.
        Check("A place that is not a position cannot be swapped with",
            What({ kind = "defensive", payload = 42 },
                 { kind = "defensive", payload = 99, ordered = false })
                == "refused")

        -- ...but taking one OUT of that set is exactly what those squares can
        -- say, so it must still work.
        Check("An unordered place can still be dragged out of",
            What({ kind = "defensive", payload = 42 }, nil) == "clear")

        -- And a spell may still land in an EMPTY unordered square: that is
        -- adding it to the set, which is the whole point of the page.
        Check("An empty unordered place still takes a drop",
            What({ kind = "defensive", payload = 42 },
                 { kind = "defensive", ordered = false }) == "drop")
    end

    -----------------------------------------------------------------------
    -- ONE PRESS, ONE RUN
    --
    -- Owner, 2026-08-13: "der raid check, der geht nur auf wenn man den
    -- button gedrueckt haellt ... bitte so einstellen, das bei klick fenster
    -- aufgeht und auch stehen bleibt."
    --
    -- A place is registered for both directions - a secure one has to be - so
    -- every press arrives at the script twice. Toggle on the way down opened
    -- the window, Toggle on the way up shut it, and the only way to see it
    -- was to keep holding the mouse down. The pull timer and the ready check
    -- fired twice as well and simply did not look wrong.
    --
    -- The gate cannot be pressed out here: the stub has no mouse. It is a
    -- pure function for that reason, and the DELIVERY ORDER is the thing
    -- being checked - including the two lopsided ones, because a keyboard
    -- binding and a scripted Click() do not deliver the same pair a mouse
    -- does.
    -----------------------------------------------------------------------
    do
        local Gate = ns.RaidBar.PressGate

        -- A mouse: down, then up. One run, on the first edge.
        local run, pressed = Gate(nil, "LeftButton", true)
        Check("A press acts on the way down", run and pressed == "LeftButton")
        run, pressed = Gate(pressed, "LeftButton", false)
        Check("The release of that same press does nothing",
            not run and pressed == nil)

        -- A scripted Click() and any client that only ever hands over the up
        -- edge: that up IS the press, and it must not be swallowed.
        run, pressed = Gate(nil, "LeftButton", false)
        Check("A lone release is a press of its own", run)

        -- Slide off the button and let go somewhere else: the up never comes.
        -- The stale memory may not eat the NEXT press.
        run, pressed = Gate(nil, "LeftButton", true)
        run, pressed = Gate(pressed, "LeftButton", true)
        Check("A press whose release went missing does not eat the next one",
            run and pressed == "LeftButton")

        -- Right-click cancels the pull timer while the left is still held.
        -- A different button is a different press.
        run, pressed = Gate("LeftButton", "RightButton", false)
        Check("The other button is its own press, and the first is remembered",
            run and pressed == "LeftButton")

        -- Two presses, four edges, two runs - the whole point, counted.
        --
        -- (The aura-binding block below is the other half of today's lesson:
        -- a rule with a test, and a wiring with one.)
        local runs = 0
        local memory = nil
        for _, edge in ipairs({ true, false, true, false }) do
            local acts
            acts, memory = Gate(memory, "LeftButton", edge)
            if acts then runs = runs + 1 end
        end
        Check("Two presses run the thing twice, not four times", runs == 2)
    end

    -----------------------------------------------------------------------
    -- CLOSING THE GAPS A HIDDEN CELL LEAVES
    --
    -- An off-by-one here does not raise. It puts the wrong icon in the wrong
    -- square and looks exactly like a working display - which is why the
    -- arithmetic is separate from the drawing and checked on its own.
    --
    -- Two ways to close, and they are different answers rather than a better
    -- and a worse: "all" repacks the lot, "line" closes each row within
    -- itself so a grid keeps its shape and "the second row is my defensives"
    -- stays true.
    -----------------------------------------------------------------------
    do
        local Compact = ns.Layout.Compact

        -- Off is the identity, so no caller needs a branch around it.
        local place, used = Compact({ [2] = true }, 4, nil, 4)
        Check("Switched off, every cell keeps its own slot",
            place[1] == 1 and place[2] == 2 and place[3] == 3 and used == 4)

        -- "all": everything shuffles down and the bar gets shorter.
        place, used = Compact({ [2] = true }, 4, "all")
        Check("Repacking moves everything after the gap down",
            place[1] == 1 and place[2] == nil and place[3] == 2
            and place[4] == 3)
        Check("Repacking shortens the bar", used == 3)

        place, used = Compact({ [1] = true, [2] = true }, 4, "all")
        Check("Two gaps at the front pull the rest to the front",
            place[3] == 1 and place[4] == 2 and used == 2)

        Check("Everything hidden leaves nothing to draw",
            select(2, Compact({ true, true, true }, 3, "all")) == 0)

        -- "line": a 3x2 grid, one gone from the FIRST row. The second row
        -- must not move up - that is the whole difference.
        local grid = { [2] = true }
        place, used = Compact(grid, 6, "line", 3)
        Check("A row closes up within itself",
            place[1] == 1 and place[2] == nil and place[3] == 2)
        Check("The row below keeps its place",
            place[4] == 4 and place[5] == 5 and place[6] == 6)
        Check("The box still covers the furthest row", used == 6)

        -- A gap in the LAST row shortens the box; a gap above it does not.
        place, used = Compact({ [5] = true }, 6, "line", 3)
        Check("A gap in the last row does shorten it",
            place[6] == 5 and used == 5)

        -- A whole row gone in the middle leaves its space empty rather than
        -- pulling the row below up into it - the price of keeping the grid,
        -- and it is the point of the mode rather than a defect.
        place, used = Compact({ [4] = true, [5] = true, [6] = true }, 9, "line", 3)
        Check("An empty middle row stays empty",
            place[7] == 7 and place[8] == 8 and used == 9)

        -- A line of one is every cell on its own line, which must not become
        -- a division by zero or a silent repack.
        place, used = Compact({ [1] = true }, 3, "line", 1)
        Check("A line of one still answers", place[2] == 2 and used == 3)

        Check("No cells at all is not an error",
            select(2, Compact({}, 0, "all")) == 0)
    end

    -----------------------------------------------------------------------
    -- THE AURA BINDS ITSELF
    --
    -- Owner: "das muss auch ohne mich gehen, die sachen sind doch alle im
    -- spiel." He is right about the second half and it does not follow from
    -- it: there is no call that says which buff an ability lights up for -
    -- EllesmereUI is fully on 12.1 and keeps exactly ONE such pairing, by
    -- hand. So it is watched instead, and the watching is what must not need
    -- a person.
    --
    -- A proc's glow rises with the buff and falls when it is spent, so the
    -- buff is in the aura list at SHOW and gone at HIDE. The flask, the food
    -- and the raid buffs are in both and cancel. What survives across
    -- several procs is the aura.
    -----------------------------------------------------------------------
    do
        local Narrow = ns.Auras.NarrowAura

        -- One proc never decides. Three things ended together and any of
        -- them could be the one.
        local cand, bound = Narrow(nil, { [10] = true, [20] = true }, 3)
        Check("One proc is a shortlist, not an answer", bound == nil)
        Check("Both of them are still standing", cand[10] == 1 and cand[20] == 1)

        -- The second proc drops the coincidence. Still not enough: alone is
        -- not the same as confirmed.
        cand, bound = Narrow(cand, { [10] = true }, 3)
        Check("What did not happen again falls out", cand[20] == nil)
        Check("Alone after two is still not confirmed", bound == nil)

        cand, bound = Narrow(cand, { [10] = true }, 3)
        Check("Alone and agreed three times is the aura", bound == 10)
        Check("The shortlist is dropped once it is decided", cand == nil)

        -- THE ONE THAT STOPS A WRONG BINDING. Three agreements while two ids
        -- are still standing does not say which - and a wrong auraID drives
        -- the caption and the timing of a real bar.
        local two = { [10] = true, [20] = true }
        local both = Narrow(Narrow(Narrow(nil, two, 3), two, 3), two, 3)
        Check("Three agreements on two ids still binds nothing",
            select(2, Narrow(both, two, 3)) == nil)

        -- A moment the client would not answer for - inside a dungeon - must
        -- not throw away what was learned outside it.
        local kept = Narrow({ [10] = 2 }, {}, 3)
        Check("A reading with nothing in it changes nothing",
            kept and kept[10] == 2)
        Check("So does no reading at all", Narrow({ [10] = 2 }, nil, 3)[10] == 2)

        -- Everything disagreed: the recorder starts again from what it just
        -- saw rather than sitting on an empty set for ever.
        local restarted = Narrow({ [10] = 2 }, { [30] = true }, 3)
        Check("A total disagreement starts over instead of dying",
            restarted[30] == 1 and restarted[10] == nil)
    end

    -----------------------------------------------------------------------
    -- A PREVIEW DRAWS WHAT THE THING IS
    --
    -- Owner, with a screenshot of the raid bar page: "die icons sind einfach
    -- zu gross in der vorschau." The page had copied the externals page's
    -- SLOT = 40 - a number that is exactly right THERE, because 40 is the
    -- externals panel's own default cell size, and 54% too big here, because
    -- the raid bar's button is 26.
    --
    -- So the rule is checked rather than the number: what the player set is
    -- what gets drawn, the lattice may only ever shrink to fit the page, and
    -- the floor that keeps a slot clickable may not push it back up past what
    -- was asked for.
    -----------------------------------------------------------------------
    do
        local Size = ns.UI.PreviewSize

        -- The raid bar at its defaults: 26, one row of twelve, on the 722 the
        -- page actually has. Nothing binds, so it draws what the bar draws.
        Check("A preview draws the size the bar is set to",
            Size(26, 1, 12, 722, 200, 2, 22) == 26,
            tostring(Size(26, 1, 12, 722, 200, 2, 22)))

        -- The externals page passes its own constant and must not move: this
        -- is the case its four existing checks pin.
        Check("A page that asks for 40 still gets 40",
            Size(40, 1, 6, 722, 200, 8, 22) == 40,
            tostring(Size(40, 1, 6, 722, 200, 8, 22)))

        -- Sixteen columns of 48 need 16*48 + 15*2 = 798 and there are 722, so
        -- it comes down to floor((722 - 30)/16) = 43.
        Check("A lattice too wide for the page shrinks",
            Size(48, 1, 16, 722, 200, 2, 22) == 43,
            tostring(Size(48, 1, 16, 722, 200, 2, 22)))

        -- The other axis, and it is the one the band cares about: four rows of
        -- 48 in a band 120 tall is (120 - 3*2)/4 = 28.5, so 28.
        Check("A lattice too tall for the band shrinks",
            Size(48, 4, 4, 722, 120, 2, 22) == 28,
            tostring(Size(48, 4, 4, 722, 120, 2, 22)))

        -- ...and at the band's real 200 it does NOT shrink, which is worth
        -- pinning too: (200 - 6)/4 = 48.5, so the four-row raid bar at maximum
        -- icon size still draws true.
        Check("Four rows at the band's real height still draw true",
            Size(48, 4, 4, 722, 200, 2, 22) == 48,
            tostring(Size(48, 4, 4, 722, 200, 2, 22)))

        Check("It never shrinks past being clickable",
            Size(48, 4, 12, 200, 60, 2, 22) >= 22,
            tostring(Size(48, 4, 12, 200, 60, 2, 22)))

        -- THE ONE THE OLD VERSION GOT WRONG IN THE OTHER DIRECTION. Somebody
        -- who sets 16 gets 16 drawn - small and true. A floor of 22 applied to
        -- a deliberate choice is the same lie as the 40, in miniature.
        Check("A player who asks for smaller than the floor gets what they asked for",
            Size(16, 1, 12, 722, 200, 2, 22) == 16,
            tostring(Size(16, 1, 12, 722, 200, 2, 22)))

        -- And it never grows: a page with room to spare does not get to make
        -- the preview a nicer size than the thing it is previewing.
        Check("A preview never grows past what was asked for",
            Size(26, 1, 2, 722, 200, 2, 22) == 26,
            tostring(Size(26, 1, 2, 722, 200, 2, 22)))

        -- AND THE PAGE ITSELF IS ASKED, not just the arithmetic under it. The
        -- fault was never in the sum: it was a page handing it a constant 40
        -- over a bar drawn at 26, and a check that only exercises UI.PreviewSize
        -- would have gone green through the whole mistake.
        local Geometry = ns.OptionsRaidBar and ns.OptionsRaidBar.PreviewGeometry
        if Geometry then
            local cfg = ns.RaidBar.Config()
            local keepSize, keepGap = cfg.size, cfg.gap

            cfg.size, cfg.gap = 26, 2
            local drawn, air = Geometry(750)
            Check("The raid bar preview draws the bar's own size", drawn == 26,
                tostring(drawn))
            Check("...with the bar's own air between two buttons", air == 2,
                tostring(air))

            cfg.size = 48
            Check("...and follows the icon size when it is changed",
                (Geometry(750)) == 48, tostring((Geometry(750))))

            cfg.size, cfg.gap = keepSize, keepGap
        end
    end

    -----------------------------------------------------------------------
    -- WHICH LINES OF A LIST ARE IN THE COLUMN
    --
    -- The spell picker held one frame per spell for the session. It builds
    -- what fits now and re-uses it as you scroll, and THIS is the arithmetic
    -- that decides which lines those are - so it is checked here rather than
    -- through the window: the harness answers GetHeight with a constant, so a
    -- check that went through the real column would be asking the stub.
    --
    -- The list is deliberately MIXED - headings are 26 and rows are 32 - which
    -- is the case a "divide by the row height" version gets wrong the moment
    -- a group boundary is on screen.
    -----------------------------------------------------------------------
    do
        local Range = ns.UI.VisibleRange

        local function Lines(heights)
            local items, y = {}, 0
            for _, height in ipairs(heights) do
                items[#items + 1] = { y = y, h = height }
                y = y + height
            end
            return items
        end

        -- 26, then eight rows of 32: 26, 58, 90, 122, 154, 186, 218, 250, 282
        local mixed = Lines({ 26, 32, 32, 32, 32, 32, 32, 32, 32 })

        local first, last = Range(mixed, 0, 100)
        Check("The top of a list starts at its first line", first == 1)
        Check("A 100 tall column holds a heading and three rows", last == 4,
            string.format("%d..%d", first, last))

        -- Offset 90 is exactly the bottom edge of the third line, so the
        -- third is GONE and the fourth is the first one drawn. The off-by-one
        -- here is a real one: `<=` rather than `<` is the difference between
        -- a line that has just left the column and one that is still in it.
        first, last = Range(mixed, 90, 100)
        Check("A line whose bottom edge is the top of the column is out",
            first == 4, tostring(first))
        -- The window ends at 190 and the seventh line starts at 186: four
        -- pixels of it are showing, and it is drawn.
        Check("A line four pixels into the column is in", last == 7,
            tostring(last))

        -- The one that decides whether a saving is real: the answer has to be
        -- a HANDFUL out of a long list, not a share of it.
        local long = {}
        do
            local y = 0
            for index = 1, 400 do
                long[index] = { y = y, h = 32 }
                y = y + 32
            end
        end
        first, last = Range(long, 0, 384)
        Check("Four hundred lines in a 384 column are twelve", last - first + 1 == 12,
            string.format("%d", last - first + 1))

        first, last = Range(long, 32 * 399, 384)
        Check("The end of a list is reachable", last == 400, tostring(last))

        -- THE THREE EMPTY ANSWERS, and all three have to be first > last
        -- rather than 1..1: a column with no height yet is the state every
        -- one of these frames is in before it is laid out, and drawing "the
        -- first line" then would put a spell nobody asked for on screen.
        first, last = Range({}, 0, 100)
        Check("An empty list draws nothing", first > last)

        first, last = Range(long, 0, 0)
        Check("A column with no height draws nothing", first > last)

        first, last = Range(long, 32 * 500, 384)
        Check("Scrolled past the end, nothing is drawn", first > last)

        -- Negative scroll is not a state the client produces, but the sum
        -- that produces it here is `y - height` and that one has been
        -- negative before.
        first, last = Range(mixed, -50, 100)
        Check("A scroll above the top starts at the top", first == 1)
    end

    -----------------------------------------------------------------------
    -- A HUNDRED SPELLS, A DOZEN FRAMES
    --
    -- The picker was the most expensive thing this addon builds. The check
    -- is not "is it smaller" - nothing here can weigh a frame - it is the
    -- CONTRACT that makes it smaller: the list knows every line, and only
    -- the ones in the column exist as frames.
    --
    -- It has to hold a catalogue up to the pane, because the desktop client
    -- has no Cooldown Manager and the real one comes back empty out here -
    -- which is exactly how "the picker costs 2.4 MB" went unmeasured for a
    -- version: the harness was building a list of nothing and reporting a
    -- number that was all the OTHER panes.
    -----------------------------------------------------------------------
    do
        local realCDM, realAuras = ns.CDM.Catalogue, ns.Auras.Catalogue

        local many = {}
        for index = 1, 200 do
            many[index] = {
                spellID = 900000 + index,
                name = string.format("Test spell %d", index),
                viewer = "essential",
                order = index,
                known = true,
            }
        end

        ns.CDM.Catalogue = function() return many end
        ns.Auras.Catalogue = function() return {} end

        local host = CreateFrame("Frame", nil, UIParent)
        host:Hide()

        local pane = ns.SpellPane:Build(host, 380, {
            Used = function() return {} end,
            Assign = function() end,
        })
        pane.Fill()

        ns.CDM.Catalogue, ns.Auras.Catalogue = realCDM, realAuras

        -- 200 spells and the heading over them.
        Check("Every spell is in the list", pane.LineCount() == 201,
            tostring(pane.LineCount()))

        -- The harness's column answers 200 tall, so seven rows fit and one
        -- more is the slack below the fold. The number is not the point; the
        -- ORDER OF MAGNITUDE is, and 200 rows would sail past this.
        Check("Two hundred spells do not build two hundred rows",
            pane.RowCount() > 0 and pane.RowCount() <= 24,
            tostring(pane.RowCount()))
    end

    -----------------------------------------------------------------------
    -- A SLOT TAKES WHAT IS ON THE CURSOR
    --
    -- The owner asked for it - "kann man das so machen, das man die sachen da
    -- reinziehen kann" - and it is the gesture the game's own action bars
    -- use. Two doors, because the client offers two: releasing a drag fires
    -- OnReceiveDrag, and clicking a target while carrying something fires
    -- OnClick with the item still on the cursor. A slot that wires only the
    -- first works for drag and silently ignores click-to-place.
    -----------------------------------------------------------------------
    do
        local host = CreateFrame("Frame", nil, UIParent)
        host:Hide()

        local plain = ns.UI.SpellSlot(host, { size = 40, get = function() end })
        Check("A slot with nothing to drop into it takes no drag",
            plain:GetScript("OnReceiveDrag") == nil)

        local dropped
        local taker = ns.UI.SpellSlot(host, {
            size = 40,
            get = function() end,
            onDropItem = function(itemID) dropped = itemID end,
        })
        Check("A slot that accepts items answers a drag",
            taker:GetScript("OnReceiveDrag") ~= nil)
        Check("It also answers a click, for click-to-place",
            taker:GetScript("OnClick") ~= nil)
        -- Nothing is on the cursor in a test, so the handler must decline
        -- quietly rather than raise - and must NOT swallow the click, or an
        -- empty slot would stop opening its menu.
        local ok = pcall(taker:GetScript("OnReceiveDrag"), taker)
        Check("A drag with nothing on the cursor is declined, not raised", ok)
        Check("Nothing was picked up out of an empty cursor", dropped == nil)
    end

    -- The screen measurement itself. It cannot be predicted out here, but it
    -- can be required to be a usable number - EllesmereUI's own comment says
    -- GetPhysicalScreenSize answers 0 or nil during a display-mode change,
    -- and a 0 would make every mark ask for the 14 cut.
    local perUnit = ns.UI.PixelsPerUnit()
    Check("Pixels per unit is a sane number",
        Finite(perUnit) and perUnit > 0 and perUnit < 8, tostring(perUnit))
end

---------------------------------------------------------------------------
-- Co-tanks
--
-- The arithmetic first, because it is the part that can be wrong without
-- looking wrong: a strip whose second line stacks the wrong way draws over
-- the health bar, and a colour ramp that passes through grey-brown at half
-- reads as a broken addon rather than as a tank at half.
---------------------------------------------------------------------------
local function TestCoTanks()
    local Layout = ns.Layout

    -- THE PREVIEW CARD SHOWS EXACTLY ONE ROW, whatever else is switched on.
    -- Five of them at their real size made the card shrink the whole panel to
    -- fit, and then nothing on it could be read - so this is checked with test
    -- mode ON, which is the setting that used to win.
    local ctdb = ns.db.coTanks
    local hosted, testing, rows = ns.CoTanks.hosted, ctdb.testMode, ctdb.maxRows
    -- Cleared, not just saved. Run /zs test with the options window open on
    -- the Co-tanks page and the panel is genuinely hosted, so the first check
    -- below would read 1 and report a failure about a panel behaving exactly
    -- as designed. A check has to state the conditions it needs, not inherit
    -- whichever window happens to be open.
    ns.CoTanks.hosted = nil
    ctdb.testMode, ctdb.maxRows = true, 5
    Check("Test mode fills the panel", ns.CoTanks:RowCount() == 5,
        tostring(ns.CoTanks:RowCount()))
    ns.CoTanks.hosted = true
    Check("The preview card shows one tank", ns.CoTanks:RowCount() == 1,
        tostring(ns.CoTanks:RowCount()))
    -- The card invents its tank whether or not test mode is on, or the two
    -- sections that set up the aura strips preview as empty space - PaintStrip
    -- refuses to draw an invented aura on anything claiming to be a real
    -- player, and on a normal evening there is no real tank to be.
    ctdb.testMode = false
    Check("The preview card invents its tank either way",
        ns.CoTanks:Invented() == true)
    ns.CoTanks.hosted = nil
    Check("Off the card it does not", ns.CoTanks:Invented() == false)

    ns.CoTanks.hosted, ctdb.testMode, ctdb.maxRows = hosted, testing, rows

    -- Slot 1 is always the anchor corner itself. Everything else is measured
    -- from there, so an offset on the first icon means the whole strip has
    -- moved and nothing on screen says which end it moved from.
    local dx, dy = Layout.StripSlot(1, 20, 2, 4, "right", "BOTTOMLEFT")
    Check("The first icon of a strip sits on the anchor",
        dx == 0 and dy == 0, dx .. "," .. dy)

    dx = Layout.StripSlot(3, 20, 2, 4, "right", "BOTTOMLEFT")
    Check("Icons step by size plus spacing", dx == 44, tostring(dx))

    dx = Layout.StripSlot(3, 20, 2, 4, "left", "BOTTOMRIGHT")
    Check("Growing left steps the other way", dx == -44, tostring(dx))

    -- The wrap, and the direction the second line takes. A strip hung under
    -- the bar must overflow DOWNWARDS; upwards it draws across the health.
    dx, dy = Layout.StripSlot(5, 20, 2, 4, "right", "BOTTOMLEFT")
    Check("The fifth of four per row starts a new line", dx == 0, tostring(dx))
    Check("A bottom-anchored strip overflows downwards", dy == 22, tostring(dy))

    dx, dy = Layout.StripSlot(5, 20, 2, 4, "right", "TOPLEFT")
    Check("A top-anchored strip overflows upwards", dy == -22, tostring(dy))

    -- THE CORNER FLIP. A strip attached to the row's bottom-left hangs its
    -- TOP-left there, so it falls away from the health bar instead of sitting
    -- on it. Same corner both ends and a 22px icon covers a 26px row.
    Check("A bottom strip hangs by its top",
        Layout.StripCorner("BOTTOMLEFT") == "TOPLEFT",
        Layout.StripCorner("BOTTOMLEFT"))
    Check("A top strip hangs by its bottom",
        Layout.StripCorner("TOPRIGHT") == "BOTTOMRIGHT",
        Layout.StripCorner("TOPRIGHT"))
    Check("The side never changes, only the top and bottom",
        Layout.StripCorner("BOTTOMRIGHT") == "TOPRIGHT",
        Layout.StripCorner("BOTTOMRIGHT"))

    -- Which edge the shield hangs off - the one the clock moves. Hard-coded
    -- to RIGHT it sits at the wrong end of a right-to-left bar and across the
    -- middle of a vertical one, which is the fault the spark had for months.
    local edge, vertical = Layout.FillEdge("HORIZONTAL", false)
    Check("A left-to-right bar leads on the right",
        edge == "RIGHT" and vertical == false, tostring(edge))
    edge = Layout.FillEdge("HORIZONTAL", true)
    Check("A right-to-left bar leads on the left", edge == "LEFT", tostring(edge))
    edge, vertical = Layout.FillEdge("VERTICAL", false)
    Check("A bottom-to-top bar leads at the top",
        edge == "TOP" and vertical == true, tostring(edge))
    edge = Layout.FillEdge("VERTICAL", true)
    Check("A top-to-bottom bar leads at the bottom", edge == "BOTTOM", tostring(edge))

    local w, h = Layout.StripSize(4, 20, 2, 4)
    Check("Four in a row measure four icons and three gaps", w == 86, tostring(w))
    Check("One line is one icon tall", h == 20, tostring(h))

    w, h = Layout.StripSize(5, 20, 2, 4)
    Check("Five over two lines are still four wide", w == 86, tostring(w))
    Check("Two lines are two icons and one gap tall", h == 42, tostring(h))

    w = Layout.StripSize(0, 20, 2, 4)
    Check("An empty strip takes no room", w == 0, tostring(w))

    -- The ramp. Two straight halves, and the ends are exactly the colours
    -- that were picked rather than something near them.
    local high, mid, low = { 0, 1, 0 }, { 1, 1, 0 }, { 1, 0, 0 }
    local r, g, b = Layout.HealthTint(1, high, mid, low)
    Check("Full health is exactly the full colour",
        r == 0 and g == 1 and b == 0, r .. "," .. g .. "," .. b)

    r, g, b = Layout.HealthTint(0, high, mid, low)
    Check("Empty is exactly the empty colour",
        r == 1 and g == 0 and b == 0, r .. "," .. g .. "," .. b)

    r, g, b = Layout.HealthTint(0.5, high, mid, low)
    Check("Half is exactly the middle colour",
        r == 1 and g == 1 and b == 0, r .. "," .. g .. "," .. b)

    -- Above maximum is a real state during an absorb, and below zero should
    -- not be reachable but must not produce a colour outside the ramp.
    r = Layout.HealthTint(1.4, high, mid, low)
    Check("Over-full clamps to the full colour", r == 0, tostring(r))
    r = Layout.HealthTint(-1, high, mid, low)
    Check("Under-empty clamps to the empty colour", r == 1, tostring(r))

    -- The text, and the one case that matters most: a number this client
    -- will not let an addon compute on must produce NOTHING, not a zero.
    local CoTanks = ns.CoTanks
    Check("Percent reads as a percent",
        CoTanks:HealthText("percent", 500, 1000) == "50%",
        tostring(CoTanks:HealthText("percent", 500, 1000)))
    Check("A full bar shows no deficit",
        CoTanks:HealthText("deficit", 1000, 1000) == "",
        tostring(CoTanks:HealthText("deficit", 1000, 1000)))
    Check("An unreadable health gives no text at all",
        CoTanks:HealthText("percent", nil, 1000) == nil)
    Check("A zero maximum gives no text rather than dividing by it",
        CoTanks:HealthText("percent", 0, 0) == nil)

    -- Cutting a name. The limit is in CHARACTERS, and a name shorter than the
    -- limit comes back whole rather than padded or truncated to it.
    Check("Zero keeps the whole name",
        CoTanks:CutName("Sunwarden", 0) == "Sunwarden")
    Check("A short name is left alone",
        CoTanks:CutName("Zwoelf", 10) == "Zwoelf")
    local cut = CoTanks:CutName("Sunwarden", 4)
    Check("A long name is cut to the limit", cut == "Sunw", tostring(cut))

    -- THE LIMIT IS IN CHARACTERS, NOT BYTES, and on a European realm that is
    -- the difference between a name and a name with a box on the end. The
    -- first version stepped one byte per pass while counting to a limit in
    -- characters: four letters of "Grimtusk" came back as four bytes of a name
    -- whose first letter is two bytes long.
    local wide = "\195\150lrunn"           -- "Oelrunn" with an O-umlaut: 7 chars, 8 bytes
    cut = CoTanks:CutName(wide, 3)
    Check("A two-byte letter counts as one", cut == "\195\150lr", cut)
    Check("A cut never ends mid-letter",
        not strlenutf8 or strlenutf8(cut) == 3,
        tostring(strlenutf8 and strlenutf8(cut)))
    Check("A name shorter than the limit comes back whole",
        CoTanks:CutName(wide, 20) == wide)

    -- Every setting the panel reads has a default. Two lists of the same
    -- thing drift - that is written down in this file already, from the time
    -- it cost a whole feature - so this walks the defaults rather than a
    -- second hand-typed list.
    local defaults = ns.DEFAULTS.coTanks
    for _, key in ipairs({
        "enabled", "testMode", "includeSelf", "onlyInGroup", "onlyInInstance",
        "width", "rowHeight", "spacing", "scale", "maxRows", "growth", "sortBy",
        "healthTexture", "healthColor", "healthCustom", "healthAlpha",
        "healthGradient", "healthHigh", "healthMid", "healthLow",
        "bgColor", "bgAlpha", "bgGradient", "trackAlpha",
        "borderSize", "borderColor", "borderTexture", "borderGradient",
        "absorbShow", "absorbColor", "healAbsorbShow",
        "name", "health", "debuffs", "buffs",
        "targetBorder", "absorbTexture", "healAbsorbTexture",
        "deadFade", "offlineFade", "rangeFade", "rangeAlpha",
    }) do
        Check("Co-tanks default for '" .. key .. "'", defaults[key] ~= nil)
    end

    -- THE INDICATORS ARE WALKED, not listed a second time. Every one has to
    -- carry the same five fields, because the panel generates the same five
    -- controls for all of them off this very table - a mark missing one is a
    -- control that reads nil and writes into a table nothing looks at.
    Check("There are indicators to check", #ns.COTANK_INDICATORS >= 4,
        tostring(#ns.COTANK_INDICATORS))
    for _, entry in ipairs(ns.COTANK_INDICATORS) do
        local mark = defaults[entry.key]
        Check("Indicator '" .. entry.key .. "' has a default table",
            type(mark) == "table", type(mark))
        if type(mark) == "table" then
            for _, field in ipairs({ "show", "size", "anchor", "x", "y" }) do
                Check("Indicator '" .. entry.key .. "' has " .. field,
                    mark[field] ~= nil)
            end
            -- Every anchor the panel offers must be one SetPoint accepts, or
            -- the mark lands on a point that does not exist and throws in a
            -- repaint.
            local vertical = ns.Layout.LabelVertical(mark.anchor)
            Check("Indicator '" .. entry.key .. "' anchors to a real point",
                vertical == "" or vertical == "TOP" or vertical == "BOTTOM",
                tostring(mark.anchor))
        end
        Check("Indicator '" .. entry.key .. "' has a label",
            type(entry.label) == "string" and #entry.label > 0)
    end

    -- The target border is the fifth mark and does NOT have the same shape -
    -- it is a border, so it carries a thickness and a colour instead of a
    -- position. Checked separately rather than bent into the list above.
    Check("The target border has a thickness",
        type(defaults.targetBorder.size) == "number")
    Check("The target border has a colour",
        type(defaults.targetBorder.color) == "table")

    -- The old flat keys are GONE, not merely unused. A leftover default is a
    -- setting somebody will wire a control to by accident in six months.
    for _, dead in ipairs({ "raidMarker", "raidMarkerSize", "leaderIcon",
        "leaderIconSize", "roleIcon", "roleIconSize", "targetHighlight",
        "targetColor" }) do
        Check("The old indicator key '" .. dead .. "' is gone",
            defaults[dead] == nil)
    end

    -- AND A PROFILE THAT STILL CARRIES THEM IS CARRIED OVER, not thrown away.
    -- Run on a throwaway table, so nothing the player owns is touched.
    local old = {
        raidMarker = false, raidMarkerSize = 22,
        leaderIcon = false, leaderIconSize = 9,
        roleIcon = true, roleIconSize = 20,
        targetHighlight = false, targetColor = { 0.1, 0.2, 0.3 },
    }
    ns.CoTanks:Migrate(old)
    Check("A switched-off marker stays switched off",
        old.marker and old.marker.show == false, tostring(old.marker))
    Check("Its size comes with it", old.marker.size == 22,
        tostring(old.marker.size))
    Check("A switched-on role mark stays on",
        old.role and old.role.show == true)
    Check("The target border keeps its colour",
        old.targetBorder and old.targetBorder.color[3] == 0.3)
    Check("The target border keeps its switch",
        old.targetBorder.show == false)
    for _, dead in ipairs({ "raidMarker", "raidMarkerSize", "leaderIcon",
        "leaderIconSize", "roleIcon", "roleIconSize", "targetHighlight",
        "targetColor" }) do
        Check("Migration removes '" .. dead .. "' from the profile",
            old[dead] == nil)
    end

    -- Twice is the same as once: it runs on every login and must not undo
    -- what the user changed after the first one.
    old.marker.show = true
    ns.CoTanks:Migrate(old)
    Check("Migrating again changes nothing", old.marker.show == true)

    -- The two text elements carry the same seven fields, because the panel
    -- generates the same seven controls for both. One missing field is a
    -- control that reads nil and writes into a table nothing else looks at.
    for _, key in ipairs({ "name", "health" }) do
        for _, field in ipairs({ "show", "font", "size", "color", "outline",
            "anchor", "x", "y" }) do
            Check("Co-tank text '" .. key .. "' has " .. field,
                defaults[key][field] ~= nil)
        end
        -- Every anchor the panel offers has to be one LabelAnchor understands,
        -- or SetPoint is called with a point that does not exist.
        local point = ns.Layout.LabelVertical(defaults[key].anchor)
        Check("Co-tank text '" .. key .. "' anchors to a real point",
            point == "" or point == "TOP" or point == "BOTTOM", point)
    end

    for _, key in ipairs({ "debuffs", "buffs" }) do
        for _, field in ipairs({ "show", "max", "size", "spacing", "perRow",
            "anchor", "growth", "x", "y", "borderSize", "borderColor",
            "countdown", "stacks" }) do
            Check("Co-tank strip '" .. key .. "' has " .. field,
                defaults[key][field] ~= nil)
        end
    end

    -- WHERE THE STRIPS SIT is checked in its own suite now - see "Co-tank
    -- strips" below.
    --
    -- What stood here asserted the opposite of what is true: "the two strips
    -- grow apart, not into each other", which is what opposite growth
    -- directions on the SAME edge look like in a comment and never was on a
    -- screen. Eight icons at 22 is 183 of a 240 row, so they met in the
    -- middle and drew on top of each other from the fifth icon on.
    --
    -- It is worth the extra lines to say why: this check went RED the moment
    -- the arrangement was fixed. A test that restates the design instead of
    -- the requirement reports a correct change as a regression, and the
    -- cheapest way past a red test is to undo the fix.

    -- The gradients the co-tank frame offers are the same three the bars
    -- offer, for the same reason: those are the three the engine can draw.
    for _, key in ipairs({ "healthGradient", "bgGradient", "borderGradient" }) do
        Check("Co-tank " .. key .. " starts off", defaults[key].on == false)
        Check("Co-tank " .. key .. " carries a direction",
            type(defaults[key].direction) == "string")
    end

    -- A row's block is the bar PLUS whatever hangs off it, or every row's
    -- aura strips draw across the next row down. Checked against the setting
    -- rather than a fixed number, because it is the relationship that matters.
    local db = ns.db.coTanks
    local extent, above, below = ns.CoTanks:RowExtent(db)
    Check("A row's block is at least its bar", extent >= db.rowHeight,
        tostring(extent))
    Check("The block is the bar plus what hangs off it",
        extent == db.rowHeight + above + below,
        string.format("%d vs %d+%d+%d", extent, db.rowHeight, above, below))

    -- With both strips switched off the block IS the bar, and with one on it
    -- is taller. A block that ignored its strips would pass the first of
    -- those and fail this one.
    local saved = { db.debuffs.show, db.buffs.show }
    db.debuffs.show, db.buffs.show = false, false
    local bare = ns.CoTanks:RowExtent(db)
    Check("With no strips the block is exactly the bar", bare == db.rowHeight,
        tostring(bare))
    db.debuffs.show = true
    local withStrip = ns.CoTanks:RowExtent(db)
    Check("A strip makes the block taller", withStrip > bare,
        withStrip .. " vs " .. bare)
    db.debuffs.show, db.buffs.show = saved[1], saved[2]

    -- And it can actually be built and painted. Test mode invents its own
    -- roster, so this runs the whole renderer without a group, a raid or a
    -- second player - which is the entire point of test mode existing.
    if ns.CoTanks.Create then
        local ok, err = pcall(function()
            ns.CoTanks:Create()
            local was = ns.db.coTanks.testMode
            ns.db.coTanks.testMode = true
            ns.CoTanks:ApplyLayout()
            ns.CoTanks:Refresh()
            ns.db.coTanks.testMode = was
            ns.CoTanks:Refresh()
        end)
        Check("The co-tank panel builds and paints", ok, tostring(err))
    end

    -- A PAGE MUST BE BUILT AT THE WIDTH IT IS SHOWN AT.
    --
    -- This is the only check in this file that exists because the HARNESS
    -- cannot help: its frame stub answers GetWidth with a fixed number
    -- whatever was set, so a page built four hundred units too wide for the
    -- column it lives in builds, paints, and passes every check - while every
    -- control on it sits off the side of the window. It shipped exactly that
    -- way, on two pages, and only a screenshot found it.
    local NARROW, WIDE = 750, 1150
    local carried = 0
    for _, entry in ipairs(ns.Options.PAGES) do
        -- THE ADDON'S OWN PREDICATE, not a copy of it. This line used to list
        -- the flags again, so adding a page that carried a third column made
        -- the check assert the opposite of the rule and fail a correct page.
        local third = ns.Options.HasThirdColumn(entry)
        local width = ns.Options.PageWidth(entry, NARROW, WIDE)
        if third then
            carried = carried + 1
            Check("Page '" .. entry.key .. "' carries a third column, so it is "
                .. "built narrow", width == NARROW, tostring(width))
        else
            Check("Page '" .. entry.key .. "' has the middle to itself",
                width == WIDE, tostring(width))
        end
    end
    -- If nothing declares a third column the loop above asserts nothing, and
    -- would go green on a PAGES table that had lost the flags entirely.
    Check("Some page does carry a third column", carried >= 2, tostring(carried))

    -- THE RAIL AND THE PAGES, AGAINST EACH OTHER, BOTH WAYS.
    --
    -- Neither direction throws on its own, and that is the whole reason for
    -- checking. A rail entry naming a page that is gone gets nil back from
    -- the lookup, falls back to the empty label and calls ShowPage(nil): a
    -- blank row you can click that does nothing. A page nobody names is the
    -- opposite - it builds, it works, and there is no way in.
    --
    -- Removing the Bars entry was one edit away from each of those, which is
    -- why this is here rather than in the list of things to remember.
    local inPages, inRail = {}, {}
    for _, entry in ipairs(ns.Options.PAGES) do inPages[entry.key] = true end
    for _, entry in ipairs(ns.Options.NAV) do
        if entry.page then
            inRail[entry.page] = true
            Check("The rail entry '" .. entry.page .. "' opens a page that exists",
                inPages[entry.page] == true,
                "no such key in Options.PAGES - a blank row that clicks nowhere")
        end
    end
    for _, entry in ipairs(ns.Options.PAGES) do
        Check("The page '" .. entry.key .. "' has a way in from the rail",
            inRail[entry.key] == true,
            "it builds and nothing opens it")
    end

    -- The rail's own mark. PAGES names icons and was NOT among the data
    -- tables this file walks - which is the same gap that let four wrong
    -- icons ship, because an unknown name never throws: it falls back to four
    -- rectangles in the shape of a grid and looks like a deliberate choice.
    for _, glyph in ipairs({ "grid", "move", "sliders", "pulse", "info", "log",
        "tanks" }) do
        Check("The rail mark '" .. glyph .. "' resolves to a file",
            ns.UI.HasIcon(glyph))
    end

    -- Why the aura strips are empty, when they are. It must always be a
    -- sentence or nothing - never a nil that the panel would concatenate.
    local reason = ns.CoTanks:AuraReason()
    Check("The aura reason is a sentence or nothing",
        reason == nil or (type(reason) == "string" and #reason > 0),
        tostring(reason))
end

---------------------------------------------------------------------------
-- The menu filter
--
-- Pure, for the same reason the snapping arithmetic is: the rule that is easy
-- to get wrong - a group heading kept only when something under it survived -
-- is invisible in a screenshot and obvious in a test.
---------------------------------------------------------------------------
local function TestMenuFilter()
    local Filter = ns.UI.FilterMenuItems

    local items = {
        { heading = true, text = "Shipped with ZwoelfStuff" },
        { text = "ZS Flat" }, { text = "ZS Smooth" },
        { heading = true, text = "From your other addons" },
        { text = "Blizzard" }, { text = "Details Flat" },
    }

    Check("No filter returns everything", #Filter(items, nil) == 6)
    Check("An empty filter returns everything", #Filter(items, "") == 6)

    -- Two hits, in two different groups, so both headings stay.
    local flat = Filter(items, "flat")
    Check("It matches anywhere in the name, not just the start",
        #flat == 4, tostring(#flat))
    Check("Both groups keep their heading",
        flat[1].heading and flat[3].heading)

    -- One hit, in the SECOND group: the first heading must not survive on its
    -- own. This is the case that looks fine until you try it.
    local one = Filter(items, "blizz")
    Check("A group with no survivors loses its heading",
        #one == 2 and one[1].text == "From your other addons",
        tostring(#one) .. " " .. tostring(one[1] and one[1].text))

    Check("Filtering is case-insensitive", #Filter(items, "ZS ") == 3)
    Check("No hits at all is an empty list", #Filter(items, "zzz") == 0)
    Check("A nil list is not a crash", #Filter(nil, "flat") == 0)
end

---------------------------------------------------------------------------
-- The text elements
--
-- The charge count split off from the stack count, and a split like that has
-- three ways to go wrong that nothing on screen would show you: the new
-- element never reaching the renderer, the migration not carrying the old
-- look over, and the two ending up sharing one colour table so that editing
-- either edits both.
--
-- ns.TextOffset is checked here rather than in the design suite because it is
-- the ONE piece of arithmetic both renderers run. A drawn cell and an adopted
-- icon sitting on the same bar disagreeing about where "bottom right" is, is
-- exactly the class of bug this addon keeps finding by eye.
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- THE REMINDERS.
--
-- Three things are worth checking without a screen, and they are the three
-- that would be silent faults:
--
--   The trigger, which is one word turning into a decision. Getting it
--   backwards means a message that shows exactly when nothing is wrong, and
--   nothing about that looks like a bug from the code.
--
--   "Cannot answer" is not "not active". A spell the Cooldown Manager does
--   not track has to make the reminder SILENT, or every mistyped spell sits
--   on screen forever insisting a buff is gone.
--
--   The flash, whose whole job is to never reach nothing. A message that
--   vanishes and comes back is one you have to catch.
--
-- The geometry is a pure function for the usual reason: the harness answers
-- GetStringWidth with a stub, so the arithmetic is checked here and the
-- drawing is checked by a pair of eyes.
---------------------------------------------------------------------------
local function TestReminders()
    local Reminders = ns.Reminders

    -----------------------------------------------------------------------
    -- ONE LIST PER SPECIALISATION, at the owner's word: "reminders auch".
    --
    -- Driven through the real store rather than through ns.SpecStore
    -- directly, because the question is not whether the helper works - it is
    -- whether the reminders ASK it. That is the half that was wrong when the
    -- death log's own copy of this existed.
    -----------------------------------------------------------------------
    if ns.db then
        local keptBySpec, keptFlat = ns.db.remindersBySpec, ns.db.reminders
        local realKey = ns.SpecKey
        ns.db.remindersBySpec, ns.db.reminders = nil, nil

        PretendSpec("PALADIN:66")
        local prot = Reminders:All()
        prot[1] = { spellID = 31850 }
        Check("A reminder list belongs to the spec that made it",
            #Reminders:All() == 1)

        PretendSpec("PALADIN:70")
        Check("The other spec of the same character starts with none",
            #Reminders:All() == 0)

        ns.SpecKey = realKey
        ns.db.remindersBySpec, ns.db.reminders = keptBySpec, keptFlat
        Check("And the check put the real lists back",
            ns.db.remindersBySpec == keptBySpec
            and ns.db.reminders == keptFlat)
    end

    -----------------------------------------------------------------------
    -- THE INDEX A REMINDER READS HAS TO BE FILLED BY SOMETHING.
    --
    -- It used to be rebuilt once per render pass by the cooldown bars. When
    -- they were removed its only writer went with them, and nothing threw:
    -- the table stayed empty all session, so every reminder answered
    -- "Blizzard is not showing this spell" - our hole, blamed on Blizzard's
    -- settings. An audit found it, no check did.
    --
    -- Asked as a WIRING question, because the model half is fine either way:
    -- does a plain read - no `fresh` - come back with the index built.
    -----------------------------------------------------------------------
    if ns.CDM then
        ns.CDM.indexBuilt = nil
        ns.CDM:ItemForSpell(48792)
        Check("A plain read builds the item index if nobody has",
            ns.CDM.indexBuilt == true)

        ns.CDM.indexBuilt = nil
        ns.CDM:NotifyChanged()
        Check("And the Cooldown Manager rebuilds it when it says it changed",
            ns.CDM.indexBuilt == true)
    end

    -- The trigger, all four combinations.
    Check("'Not active' fires when it is idle",
        Reminders.Fires("missing", "idle") == true)
    Check("'Not active' stays quiet while it is up",
        Reminders.Fires("missing", "active") == false)
    Check("'While active' fires while it is up",
        Reminders.Fires("active", "active") == true)
    Check("'While active' stays quiet when it is idle",
        Reminders.Fires("active", "idle") == false)

    -- AN UNANSWERABLE STATE IS SILENT, both ways round. This is the one that
    -- matters: nil is not false.
    Check("An unknown state fires nothing (missing)",
        Reminders.Fires("missing", nil) == false)
    Check("An unknown state fires nothing (active)",
        Reminders.Fires("active", nil) == false)

    -- Every trigger in the vocabulary is one the evaluator answers. A word in
    -- the dropdown that Fires has never heard of would silently behave like
    -- "missing".
    for _, entry in ipairs(ns.REMINDER_TRIGGERS) do
        local onActive = Reminders.Fires(entry.value, "active")
        local onIdle = Reminders.Fires(entry.value, "idle")
        Check("Trigger '" .. entry.value .. "' tells the two states apart",
            onActive ~= onIdle, tostring(onActive) .. "/" .. tostring(onIdle))
    end

    -- The flash never reaches nothing, and it does come back to full.
    local floor = 0.25
    local lowest, highest = 1, 0
    for step = 0, 40 do
        local alpha = Reminders.FlashAlpha(step / 40, 1, floor)
        if alpha < lowest then lowest = alpha end
        if alpha > highest then highest = alpha end
        if alpha < floor - 0.001 or alpha > 1.001 then
            Check("The flash stays inside its range", false,
                string.format("%.3f at %d", alpha, step))
        end
    end
    Check("The flash reaches full brightness", highest > 0.99,
        string.format("%.3f", highest))
    Check("The flash dims to the floor", Near(lowest, floor, 0.02),
        string.format("%.3f", lowest))
    Check("A flash rate of nothing is a steady message",
        Reminders.FlashAlpha(1.7, 0, 0.25) == 1)

    -- The box is measured, and the icon has to be inside it.
    local wide, tall = Reminders.Extent(120, 30, "left", 40, 8)
    Check("The icon widens the box", wide == 168, tostring(wide))
    Check("A tall icon raises the box", tall == 40, tostring(tall))
    local plainW, plainH = Reminders.Extent(120, 30, "none", 40, 8)
    Check("No icon, no extra width", plainW == 120, tostring(plainW))
    Check("No icon, the text's own height", plainH == 30, tostring(plainH))
    local zeroW, zeroH = Reminders.Extent(0, 0, "none", 0, 8)
    Check("An empty reminder still has a size", zeroW >= 1 and zeroH >= 1)

    -- The store, and the label that must never be empty.
    local before = Reminders:Count()
    local index = Reminders:Add()
    Check("A new reminder is added", index ~= nil and Reminders:Count() == before + 1)
    if index then
        local cfg = Reminders:Get(index)
        Check("A brand new reminder still has a name",
            (Reminders:Label(cfg, index) or "") ~= "")
        Check("It waits for combat by default", cfg.show.combat == "in",
            tostring(cfg.show.combat))
        -- WITH NO SPELL it cannot answer, and therefore must not show.
        Check("With nothing to watch it stays off the screen",
            Reminders:ShouldShow(cfg) == false)
        Check("And it says why", (Reminders:Explain(cfg) or "") ~= "")

        cfg.text = "  BONE SHIELD  \nsecond line"
        Check("The name comes off the first line of the text",
            Reminders:Label(cfg, index) == "BONE SHIELD",
            Reminders:Label(cfg, index))

        Reminders:Remove(index)
    end
    Check("A removed reminder is gone", Reminders:Count() == before,
        tostring(Reminders:Count()))
end

---------------------------------------------------------------------------
-- The game menu entry
--
-- Our button hangs under the LAST of Blizzard's, and both halves of working
-- that out fail silently: pick the wrong two and it sits in the middle of the
-- menu, get the gap backwards and it lands on the entry above it. Neither
-- throws, and both need the pause menu open to look at - which is exactly the
-- shape of the snapping bug that was misdiagnosed three times by reading.
---------------------------------------------------------------------------
local function TestGameMenu()
    local Menu = ns.GameMenu
    local function Bottom(item) return item.y end

    -- Deliberately out of order: the menu's pool does not enumerate in
    -- layout order, and code that assumed it did would pass a sorted fixture.
    local buttons = {
        { name = "options", y = 400 },
        { name = "editmode", y = 100 },
        { name = "addons",  y = 200 },
        { name = "shop",    y = 300 },
    }

    local lowest, second = Menu.TwoLowest(buttons, Bottom)
    Check("The bottom-most button is found whatever the order",
        lowest and lowest.name == "editmode", lowest and lowest.name or "nil")
    Check("And the one directly above it",
        second and second.name == "addons", second and second.name or "nil")

    -- A button the menu is not showing is not in the running. Hanging ours
    -- under a hidden one puts it in empty space below the frame.
    local hidden = Menu.TwoLowest({
        { name = "shown", y = 300 },
        { name = "hidden", y = 100, gone = true },
    }, function(item) return not item.gone and item.y or nil end)
    Check("A hidden button is not the anchor",
        hidden and hidden.name == "shown", hidden and hidden.name or "nil")

    Check("An empty menu has no anchor at all", Menu.TwoLowest({}, Bottom) == nil)
    Check("One button alone has no partner to measure against",
        select(2, Menu.TwoLowest({ { y = 1 } }, Bottom)) == nil)

    -- The gap: the bottom of the button ABOVE, minus the top of the one below
    -- it. Backwards, this is negative and the entry lands on its neighbour.
    Check("The gap is measured between the two edges that face each other",
        Menu.GapBetween(100, 112) == 12, tostring(Menu.GapBetween(100, 112)))
    Check("A different spacing is followed rather than assumed",
        Menu.GapBetween(100, 104) == 4, tostring(Menu.GapBetween(100, 104)))

    -- Everything the arithmetic cannot make sense of falls back rather than
    -- producing a number: a menu laid out some other way is not something to
    -- guess at.
    Check("Overlapping buttons fall back", Menu.GapBetween(100, 90) == 12)
    Check("An absurd gap falls back", Menu.GapBetween(0, 5000) == 12)
    Check("A missing partner falls back", Menu.GapBetween(100, nil) == 12)
    Check("A missing measurement falls back", Menu.GapBetween(nil, nil) == 12)
end

---------------------------------------------------------------------------
-- Anchors that were wrong on screen and right-looking in the source
--
-- The spark was drawn with no height for its whole life, and the spell name
-- ignored its position outright. Neither throws, neither shows up in a static
-- check, and both need a bar on screen with a running cooldown on it to see.
-- So the naming is done by functions that take strings and return strings,
-- and those are what is checked here.
---------------------------------------------------------------------------
local function TestAnchors()
    -- THE SPARK rides the end the fill GROWS TOWARDS. On the other end it
    -- never moves, and a spark that does not move is not a spark.
    local Edge = ns.Layout.SparkEdge
    Check("A left-to-right fill carries it on the right",
        Edge("HORIZONTAL", false) == "RIGHT", Edge("HORIZONTAL", false))
    Check("A right-to-left fill carries it on the left",
        Edge("HORIZONTAL", true) == "LEFT", Edge("HORIZONTAL", true))
    Check("A bottom-to-top fill carries it on the top",
        Edge("VERTICAL", false) == "TOP", Edge("VERTICAL", false))
    Check("A top-to-bottom fill carries it on the bottom",
        Edge("VERTICAL", true) == "BOTTOM", Edge("VERTICAL", true))

    -- The four answers must be four DIFFERENT edges. Two directions sharing
    -- one is how a spark ends up parked on the fixed end of half the bars.
    local edges = {}
    for _, orientation in ipairs({ "HORIZONTAL", "VERTICAL" }) do
        for _, reverse in ipairs({ true, false }) do
            local edge = Edge(orientation, reverse)
            Check("'" .. edge .. "' is claimed only once", not edges[edge],
                orientation .. " " .. tostring(reverse))
            edges[edge] = true
        end
    end

    -- And a horizontal spark must never ride a horizontal edge - that is the
    -- axis the fill runs along, so it would lie ALONG the bar rather than
    -- across it. The mistake the charge marks made in 4.27.0, one file over.
    Check("A horizontal fill's edge is a side, not a top or a bottom",
        Edge("HORIZONTAL", false):find("LEFT")
            or Edge("HORIZONTAL", false):find("RIGHT"))
    Check("A vertical fill's edge is a top or a bottom, not a side",
        Edge("VERTICAL", false):find("TOP")
            or Edge("VERTICAL", false):find("BOTTOM"))

    -- THE SPELL NAME. Nine positions, and the middle of the middle is the one
    -- that breaks: the vertical part is empty there, and an empty string is
    -- not a point - SetPoint("") is an error at layout time on every bar.
    -- The nine, written out. They used to come from ns.TEXT_ANCHORS, which
    -- the bars published; the co-tank page carries its own copy of the same
    -- list, and neither is a place this file can reach. Nine values that have
    -- not changed in the game's history are safe to name here - and if one
    -- ever did, LabelAnchor would be the thing under test either way.
    local TEXT_ANCHORS = {
        { value = "TOPLEFT",     text = "Top left" },
        { value = "TOP",         text = "Top" },
        { value = "TOPRIGHT",    text = "Top right" },
        { value = "LEFT",        text = "Left" },
        { value = "CENTER",      text = "Centre" },
        { value = "RIGHT",       text = "Right" },
        { value = "BOTTOMLEFT",  text = "Bottom left" },
        { value = "BOTTOM",      text = "Bottom" },
        { value = "BOTTOMRIGHT", text = "Bottom right" },
    }
    for _, entry in ipairs(TEXT_ANCHORS) do
        local point, side, justify, vertical = ns.Layout.LabelAnchor(entry.value)

        -- The vertical half is a PREFIX, and the label hangs from both edges
        -- of the band by concatenating it: vertical .. "LEFT" and
        -- vertical .. "RIGHT". An unexpected value there is SetPoint on a
        -- point that does not exist, which is an error at layout time on
        -- every bar rather than something you notice later.
        Check("'" .. entry.text .. "' has a usable vertical half",
            vertical == "" or vertical == "TOP" or vertical == "BOTTOM",
            tostring(vertical))
        Check("'" .. entry.text .. "' spans the band from both edges",
            (vertical .. "LEFT"):find("LEFT") ~= nil
                and (vertical .. "RIGHT"):find("RIGHT") ~= nil)
        Check("'" .. entry.text .. "' names a real point",
            type(point) == "string" and point ~= "", tostring(point))
        Check("'" .. entry.text .. "' reads in a real direction",
            justify == "LEFT" or justify == "RIGHT" or justify == "CENTER",
            tostring(justify))
        -- The inset only belongs to the two columns that have an edge to be
        -- inset from. A centred name pushed in by the icon gap is off centre.
        Check("'" .. entry.text .. "' insets only where there is an edge",
            (side == nil) == (not entry.value:find("LEFT")
                and not entry.value:find("RIGHT")))
    end

    Check("The centre of the centre is CENTER",
        ns.Layout.LabelAnchor("CENTER") == "CENTER")
    Check("Top centre is a point of its own",
        ns.Layout.LabelAnchor("TOP") == "TOP")
    Check("A corner keeps both halves",
        ns.Layout.LabelAnchor("BOTTOMRIGHT") == "BOTTOMRIGHT")
    Check("Nothing at all falls back to the left",
        ns.Layout.LabelAnchor(nil) == "LEFT")

    -- The three rows, spelled out. These are the strings the label's two
    -- points are built from, so a wrong one is an invalid SetPoint.
    Check("The middle row has no vertical part",
        ns.Layout.LabelVertical("RIGHT") == ""
            and ns.Layout.LabelVertical("CENTER") == "")
    Check("The top row prefixes TOP",
        ns.Layout.LabelVertical("TOPRIGHT") == "TOP")
    Check("The bottom row prefixes BOTTOM",
        ns.Layout.LabelVertical("BOTTOM") == "BOTTOM")

    -- The band the name lives in, beside the icon.
    local left, right = ns.Layout.LabelBand("left", 22)
    Check("An icon on the left pushes the name past it",
        left == 27 and right == 5, left .. "/" .. right)

    left, right = ns.Layout.LabelBand("right", 22)
    Check("An icon on the right keeps the name off it",
        left == 5 and right == 27, left .. "/" .. right)

    left, right = ns.Layout.LabelBand("hidden", 0)
    Check("No icon leaves the whole width", left == 5 and right == 5)
end

---------------------------------------------------------------------------
-- The two aura strips on a co-tank row
--
-- They shipped drawing on top of each other and nothing here noticed, because
-- nothing here asked. The old arrangement was two strips on the SAME edge
-- growing towards each other, which reads as "away from each other" and is
-- not: eight icons at 22 is 183 of a 240 row, so they met in the middle.
--
-- The rule that replaces it is one a test can hold: the two strips live on
-- DIFFERENT vertical edges. That is true at any icon count, any size and any
-- row width, which the old arrangement never was at any of them.
---------------------------------------------------------------------------
local function TestCoTankStrips()
    local defaults = ns.DEFAULTS and ns.DEFAULTS.coTanks
    if not defaults then
        Skip("Co-tank strips", "no co-tank defaults")
        return
    end

    local function Edge(anchor)
        return tostring(anchor):find("TOP") and "top" or "bottom"
    end

    Check("The two strips do not share an edge",
        Edge(defaults.debuffs.anchor) ~= Edge(defaults.buffs.anchor),
        defaults.debuffs.anchor .. " / " .. defaults.buffs.anchor)
    Check("Debuffs sit on the top edge", defaults.debuffs.anchor == "TOPLEFT")
    Check("Buffs sit on the bottom edge", defaults.buffs.anchor == "BOTTOMLEFT")
    Check("Both strips read left to right",
        defaults.debuffs.growth == "right" and defaults.buffs.growth == "right")

    -- THE ARITHMETIC THAT WAS NEVER DONE. Kept as a check rather than a
    -- comment: if somebody widens the strips or narrows the row later, the
    -- old arrangement stops being merely wrong and starts being wrong again.
    local width = defaults.debuffs.perRow * defaults.debuffs.size
        + (defaults.debuffs.perRow - 1) * defaults.debuffs.spacing
    Check("A full strip is wider than half the row - which is why one edge each",
        width > defaults.width / 2, width .. " of " .. defaults.width)

    ---------------------------------------------------------------------
    -- The migration off the overlapping pair
    ---------------------------------------------------------------------
    local old = {
        debuffs = { anchor = "BOTTOMLEFT", growth = "right" },
        buffs   = { anchor = "BOTTOMRIGHT", growth = "left" },
    }
    ns.CoTanks:Migrate(old)
    Check("An untouched panel is moved off the overlap",
        old.debuffs.anchor == "TOPLEFT" and old.buffs.anchor == "BOTTOMLEFT"
            and old.buffs.growth == "right")

    -- AND THE ONE THAT MUST NOT MOVE. A setting that changes itself back
    -- after somebody has fixed it is worse than the fault it is fixing.
    local chosen = {
        debuffs = { anchor = "BOTTOMLEFT", growth = "right" },
        buffs   = { anchor = "TOPRIGHT",  growth = "left" },
    }
    ns.CoTanks:Migrate(chosen)
    Check("A panel somebody has already moved is left alone",
        chosen.debuffs.anchor == "BOTTOMLEFT" and chosen.buffs.anchor == "TOPRIGHT"
            and chosen.buffs.growth == "left")

    local bare = {}
    ns.CoTanks:Migrate(bare)
    Check("A profile with no strips yet is not invented", bare.debuffs == nil)
end

---------------------------------------------------------------------------
-- Moving somebody's settings from one shape to another
--
-- THE ONE FUNCTION IN THIS ADDON THAT CAN LOSE WORK. Everything else that
-- goes wrong costs a reload; this one deletes the old copy after writing the
-- new one, so a mistake here is bars that were there yesterday and are not
-- there now. It runs once, on a login, against data nobody can hand back.
--
-- Asserted against a made-up store rather than trusted, and the case that
-- matters most is the second run: a migration that is not idempotent has
-- already worked once by the time anybody could notice.
---------------------------------------------------------------------------
local function TestProfileMigration()
    local Profiles = ns.Profiles
    if not (Profiles and Profiles.Migrate) then
        Skip("Profile migration", "Profiles.lua did not load")
        return
    end

    local key = ns.CharacterKey()
    if not key then
        Skip("Profile migration", "the client will not name this character")
        return
    end

    ---------------------------------------------------------------------
    -- A file written before profiles existed at all: everything sat at the
    -- root and belonged to whoever was playing.
    ---------------------------------------------------------------------
    local ancient = {
        bars = { { id = 1 } },
        font = "Friz Quadrata TT",
        procs = { [195181] = 10 },
    }
    Profiles.Migrate(ancient)

    Check("An ancient file keeps its bars",
        ancient.profiles and ancient.profiles[key]
            and #ancient.profiles[key].bars == 1)
    Check("An ancient file keeps its settings",
        ancient.profiles[key].font == "Friz Quadrata TT")
    Check("The character is pointed at its own profile",
        ancient.charProfile and ancient.charProfile[key] == key)
    Check("The measurements are lifted out to the account",
        ancient.account and ancient.account.procs
            and ancient.account.procs[195181] == 10)
    Check("A measurement does not ALSO stay in the profile",
        ancient.profiles[key].procs == nil)
    Check("Nothing is left loose at the root", ancient.bars == nil)

    ---------------------------------------------------------------------
    -- The shape before this update: settings under a character key.
    ---------------------------------------------------------------------
    local chars = {
        chars = {
            ["Zwoelf - Destromath"] = { bars = { { id = 1 }, { id = 2 } } },
            ["Alt - Destromath"]    = { bars = { { id = 9 } } },
        },
        account = { procs = {} },
    }
    Profiles.Migrate(chars)

    Check("Every character becomes a profile named after it",
        chars.profiles["Zwoelf - Destromath"] and chars.profiles["Alt - Destromath"])
    Check("Each one keeps its own bars",
        #chars.profiles["Zwoelf - Destromath"].bars == 2
            and #chars.profiles["Alt - Destromath"].bars == 1)
    Check("Each character points at its own",
        chars.charProfile["Zwoelf - Destromath"] == "Zwoelf - Destromath"
            and chars.charProfile["Alt - Destromath"] == "Alt - Destromath")
    Check("The old shape is gone once it is safely moved", chars.chars == nil)

    -- THE COPY PATH AND THE MIGRATION MUST AGREE ABOUT WHERE BARS LIVE.
    -- CopyLayoutFrom read the pre-migration shape for a whole version -
    -- store.chars, which the migration deletes - so every "Take a layout
    -- from" answered "that character has no bars" while the dropdown listed
    -- them. This asks the migrated store through the same lookup the copy
    -- uses now.
    local lifted = ns.Profiles:BarsOfCharacter("Alt - Destromath", chars)
    Check("The copy path finds a migrated character's bars",
        lifted ~= nil and #lifted == 1 and lifted[1].id == 9)
    Check("The copy path does not resurrect the deleted shape",
        ns.Profiles:BarsOfCharacter("Alt - Destromath",
            { chars = { ["Alt - Destromath"] = { bars = { { id = 9 } } } } }) == nil)

    ---------------------------------------------------------------------
    -- RUN IT AGAIN. This is the one that would go unnoticed: a migration
    -- that is not idempotent has already succeeded once by the time anybody
    -- could see it fail.
    ---------------------------------------------------------------------
    Profiles.Migrate(chars)
    Check("Migrating twice changes nothing",
        #chars.profiles["Zwoelf - Destromath"].bars == 2
            and chars.charProfile["Alt - Destromath"] == "Alt - Destromath")

    ---------------------------------------------------------------------
    -- A name that is already taken must never be written over. The old
    -- table is deleted right after, so an overwrite here is not a clash -
    -- it is the other profile being gone.
    ---------------------------------------------------------------------
    local clash = {
        chars = { ["Zwoelf - Destromath"] = { bars = { { id = 1 } } } },
        profiles = { ["Zwoelf - Destromath"] = { bars = { { id = 7 }, { id = 8 } } } },
        charProfile = {},
    }
    Profiles.Migrate(clash)
    Check("A profile that already has the name is not written over",
        #clash.profiles["Zwoelf - Destromath"].bars == 2
            and clash.profiles["Zwoelf - Destromath"].bars[1].id == 7)

    ---------------------------------------------------------------------
    -- A fresh install has nothing to move and must not invent anything.
    ---------------------------------------------------------------------
    local fresh = { profiles = {}, charProfile = {}, account = {} }
    Profiles.Migrate(fresh)
    Check("A fresh file is left empty rather than seeded",
        next(fresh.profiles) == nil and next(fresh.charProfile) == nil)

    ---------------------------------------------------------------------
    -- Names people type
    ---------------------------------------------------------------------
    Check("A name is trimmed", Profiles.CleanName("  Raid  ") == "Raid")
    Check("A name of only spaces is refused", Profiles.CleanName("   ") == nil)
    Check("An empty name is refused", Profiles.CleanName("") == nil)
    Check("A non-string is refused", Profiles.CleanName(nil) == nil)
    Check("A very long name is cut rather than refused",
        #Profiles.CleanName(string.rep("x", 200)) == 64)
end

---------------------------------------------------------------------------
-- Sharing
--
-- The one part of this addon whose output goes to a STRANGER. Everything else
-- that breaks costs the person who broke it a reload; a string that packs
-- wrong is pasted into a Discord and fails on somebody else's machine, where
-- nobody can see what happened. So the round trip is asserted here rather
-- than trusted, and so is every refusal - a wrong error message sends the
-- reader to a bug report when the real problem was a truncated paste.
---------------------------------------------------------------------------
local function TestShare()
    local Share = ns.Share
    if not Share then
        Skip("Sharing", "Share.lua did not load")
        return
    end

    -- THE LIBRARIES, first and by name. Everything below is meaningless if
    -- these are absent, and "nothing failed" while nothing ran is the exact
    -- shape of a check more generous than the thing it checks.
    local haveSerialize = LibStub and LibStub("LibSerialize", true) and true or false
    local haveDeflate   = LibStub and LibStub("LibDeflate", true) and true or false
    Check("LibSerialize is loaded", haveSerialize)
    Check("LibDeflate is loaded", haveDeflate)
    if not (haveSerialize and haveDeflate) then return end

    ---------------------------------------------------------------------
    -- Out and back
    ---------------------------------------------------------------------
    local payload = {
        stamp = { class = "DEATHKNIGHT", spec = 250, specName = "Blood" },
        label = "Zwoelf M+",
        parts = {
            bars = {
                { id = 3, rows = 2, cols = 4, cells = { [1] = 49028, [2] = 55233 },
                  colour = { 0.1, 0.2, 0.3, 1 }, anchor = { to = 7, point = "TOP" } },
                { id = 7, rows = 1, cols = 6, cells = {} },
            },
            reminders = { { text = "Bone Shield", spellID = 195181, trigger = "missing" } },
            presets = { ["My look"] = { barWidth = 210, gap = 3 } },
        },
    }

    local text, err = Share.Encode(payload)
    Check("A profile packs into a string", type(text) == "string", err)

    if type(text) == "string" then
        Check("The string carries the format in its prefix",
            text:sub(1, #Share.PREFIX) == Share.PREFIX, text:sub(1, 8))

        -- Printable in the sense the name promises: this gets pasted into a
        -- chat window, and one byte the client eats takes the whole string.
        Check("The string is printable text",
            not text:find("[%z\1-\31\127]"), "control character in the string")

        local back, backErr = Share.Decode(text)
        Check("The string unpacks again", type(back) == "table", backErr)

        if type(back) == "table" then
            Check("The format version survives", back.v == Share.FORMAT)
            Check("The label survives", back.label == "Zwoelf M+")
            Check("The class stamp survives", back.stamp and back.stamp.class == "DEATHKNIGHT")
            Check("Both bars survive", back.parts.bars and #back.parts.bars == 2)

            local first = back.parts.bars and back.parts.bars[1]
            Check("A bar's grid survives", first and first.rows == 2 and first.cols == 4)
            Check("A spell in a cell survives", first and first.cells and first.cells[1] == 49028)
            Check("A colour survives to the decimal",
                first and first.colour and first.colour[1] == 0.1 and first.colour[4] == 1)
            Check("An attachment survives", first and first.anchor and first.anchor.to == 7)
            Check("A reminder survives",
                back.parts.reminders and back.parts.reminders[1]
                and back.parts.reminders[1].spellID == 195181)
            Check("A saved look survives by its name",
                back.parts.presets and back.parts.presets["My look"]
                and back.parts.presets["My look"].barWidth == 210)
        end

        -- Whitespace at either end is what a forum and a chat window add, and
        -- it is far more common than real corruption.
        local padded = Share.Decode("  \n" .. text .. "\n  ")
        Check("A string pasted with spaces around it still opens", type(padded) == "table")
    end

    ---------------------------------------------------------------------
    -- Every refusal, in its own words
    ---------------------------------------------------------------------
    local function Refuses(name, input, wanted)
        local got, why = Share.Decode(input)
        local ok = got == nil and type(why) == "string" and why:find(wanted, 1, true) ~= nil
        Check(name, ok, why or "it was ACCEPTED")
    end

    Refuses("Nothing pasted in says so", "", "nothing pasted in")
    Refuses("Only spaces says the same", "   \n ", "nothing pasted in")
    Refuses("Somebody else's string names ours", "!EUI_abcdef", "not a ZwoelfStuff string")
    Refuses("Plain typing is not a string", "hello", "not a ZwoelfStuff string")

    -- The one that matters most: a FUTURE format has to read as "update the
    -- addon", not as "damaged". They are different problems and only one of
    -- them is the reader's to fix.
    Refuses("A newer format asks for an update", "!ZS9_abcdef", "newer ZwoelfStuff")

    Refuses("A cut-short string says it was cut short",
        Share.PREFIX .. "!!!!not printable at all!!!!", "cut short")

    if type(text) == "string" then
        -- Half a string. The prefix is intact and the payload is not, which is
        -- exactly what a chat window's length limit produces.
        Refuses("Half a string is reported as damaged",
            text:sub(1, math.floor(#text / 2)), "damaged")
    end

    -- A valid string holding nothing is not an error in the format; it is an
    -- empty export, and saying "damaged" would send somebody looking for a
    -- corruption that is not there.
    local empty = Share.Encode({ parts = {} })
    Refuses("An empty export says it is empty", empty, "nothing in it")

    ---------------------------------------------------------------------
    -- A PART THIS BUILD DOES NOT KNOW must cost that part and nothing else.
    -- The alternative is that adding a sixth part in a later version makes
    -- every string from it unopenable in this one.
    ---------------------------------------------------------------------
    local mixed = Share.Encode({
        parts = { bars = { { id = 1 } }, somethingNewer = { 1, 2, 3 } },
    })
    local got = mixed and Share.Decode(mixed)
    Check("An unknown part is dropped, not refused",
        type(got) == "table" and got.parts.bars ~= nil and got.parts.somethingNewer == nil)
    Check("The dropped part is reported",
        type(got) == "table" and got.dropped and got.dropped[1] == "somethingNewer")

    local allNew = Share.Encode({ parts = { somethingNewer = { 1 } } })
    Refuses("A string of nothing BUT unknown parts says so", allNew, "newer version")

    ---------------------------------------------------------------------
    -- Whose spells these are
    ---------------------------------------------------------------------
    local mine = { class = "DEATHKNIGHT" }
    Check("The same class fits",
        Share.SpellsFit({ class = "DEATHKNIGHT" }, mine) == true)
    Check("A different class does not fit",
        Share.SpellsFit({ class = "PALADIN" }, mine) == false)

    -- THREE ANSWERS, NOT TWO. An unstamped string used to read as a match,
    -- which is the same silent yes as a real one and the more dangerous of
    -- the two - it puts uncastable spells on a bar and says nothing.
    Check("An unstamped string answers 'cannot tell'",
        Share.SpellsFit(nil, mine) == nil)
    Check("A stamp with no class answers 'cannot tell'",
        Share.SpellsFit({ spec = 250 }, mine) == nil)

    ---------------------------------------------------------------------
    -- Taking somebody else's bars
    ---------------------------------------------------------------------
    local counter = 100
    local function NextID() counter = counter + 1 return counter end

    local source = {
        { id = 1, cells = { 49028 }, cellsBySpec = { [250] = { 49028 } },
          parked = { 55233 }, rows = 1, cols = 3 },
        { id = 2, anchor = { to = 1, point = "TOP" } },
        { id = 3, anchor = { to = 99, point = "TOP" } },  -- target never travels
    }

    local taken = Share.AdoptBars(source, NextID, false)
    Check("Every bar comes across", #taken == 3)
    Check("Every bar gets a new id",
        taken[1].id == 101 and taken[2].id == 102 and taken[3].id == 103)
    Check("An attachment follows its bar to the new id", taken[2].anchor.to == 101)
    Check("An attachment to a bar that did not travel is dropped",
        taken[3].anchor == nil)

    Check("Without the spells, the cells arrive empty",
        taken[1].cells and next(taken[1].cells) == nil)
    Check("Without the spells, the per-spec cells are gone too",
        taken[1].cellsBySpec == nil)
    Check("Without the spells, the parked ones are gone as well",
        taken[1].parked and next(taken[1].parked) == nil)
    Check("The grid still comes across",
        taken[1].rows == 1 and taken[1].cols == 3)

    -- THE SOURCE MUST NOT MOVE. It is somebody's live profile on the copy
    -- path, and a shallow copy here would have edited their bars while
    -- claiming to read them.
    Check("Adopting does not touch what it read from",
        source[1].cells[1] == 49028 and source[3].anchor ~= nil
            and source[1].id == 1)

    counter = 200
    local kept = Share.AdoptBars(source, NextID, true)
    Check("With the spells, the cells arrive filled", kept[1].cells[1] == 49028)
    Check("With the spells, the per-spec cells arrive too",
        kept[1].cellsBySpec and kept[1].cellsBySpec[250]
            and kept[1].cellsBySpec[250][1] == 49028)
    Check("With the spells, the ids are still re-issued", kept[1].id == 201)

    Check("Nothing to adopt is not an error", select(2, Share.AdoptBars({}, NextID, false)) == 0)
    Check("Adopting a non-table is not an error", select(2, Share.AdoptBars(nil, NextID, false)) == 0)

    ---------------------------------------------------------------------
    -- Packing up what is ticked, and writing one in
    ---------------------------------------------------------------------
    local db = {
        bars = { { id = 1, rows = 1, cols = 2, cells = { 49028 } },
                 { id = 2, rows = 1, cols = 2, cells = { 55233 } } },
        lastBarID = 2,
        reminders = { { text = "Bone Shield", spellID = 195181 } },
        coTanks = { enabled = true, width = 240 },
        barPresets = { Main = { barWidth = 200 } },
        font = "Friz Quadrata TT",
    }

    local all = Share.Gather(db, {
        bars = true, reminders = true, coTanks = true,
        presets = true, settings = true,
    })
    Check("Everything ticked packs every part",
        all.bars and all.reminders and all.coTanks and all.presets and all.settings)

    -- lastBarID must NOT be a part. It is dropped as unknown on arrival, and
    -- the receiver re-issues ids from its own counter anyway.
    Check("The id counter is not packed as a part", all.lastBarID == nil)
    Check("The id counter is not packed as a setting",
        all.settings and all.settings.lastBarID == nil)
    Check("The file's shape version does not travel",
        all.settings and all.settings.dbVersion == nil)
    Check("A loose setting travels without being listed anywhere",
        all.settings and all.settings.font == "Friz Quadrata TT")

    local one = Share.Gather(db, { bars = true, barIDs = { [2] = false } })
    Check("A bar left unticked stays behind", one.bars and #one.bars == 1)
    Check("The bar that travelled is the ticked one", one.bars[1].id == 1)
    Check("Nothing else comes along uninvited",
        one.reminders == nil and one.coTanks == nil and one.settings == nil)

    -- A ticked part with nothing in it is left out. Otherwise the import
    -- window promises reminders and none arrive.
    local bare = Share.Gather({ bars = {} }, { bars = true, reminders = true })
    Check("A ticked part with nothing in it is left out",
        bare.bars == nil and bare.reminders == nil)

    -- WRITING IN: added, never substituted. There is no undo here, and
    -- pasting a stranger's string must not be able to delete an evening.
    local target = {
        bars = { { id = 40, cells = { 999 } } },
        reminders = { { text = "already here" } },
        barPresets = { Main = { barWidth = 111 } },
    }
    local nextFreeID = 500
    local applied = Share.Apply(target, { parts = all }, {
        nextID = function() nextFreeID = nextFreeID + 1 return nextFreeID end,
        keepSpells = true,
    })

    Check("Imported bars are ADDED to the ones you have", #target.bars == 3)
    Check("The bar you already had is untouched", target.bars[1].id == 40)
    Check("Imported bars get ids from YOUR counter",
        target.bars[2].id == 501 and target.bars[3].id == 502)
    Check("Imported reminders are added too", #target.reminders == 2)
    Check("The panel is a single thing, so it does replace",
        target.coTanks and target.coTanks.width == 240)
    Check("A look with a name you already use keeps BOTH",
        target.barPresets.Main.barWidth == 111
            and target.barPresets["Main (imported)"] ~= nil)
    Check("Applying reports what it did",
        applied.bars == 2 and applied.reminders == 1 and applied.presets == 1)

    -- Without the spells: the writing survives, the spell does not.
    local other = { reminders = {} }
    Share.Apply(other, { parts = { reminders = all.reminders } }, {
        nextID = function() return 1 end, keepSpells = false,
    })
    Check("A reminder crossing classes keeps its words",
        other.reminders[1].text == "Bone Shield")
    Check("A reminder crossing classes loses its spell",
        other.reminders[1].spellID == nil)

    ---------------------------------------------------------------------
    -- What the import window says before it writes anything
    ---------------------------------------------------------------------
    local lines = Share.Describe(payload)
    Check("The preview lists one line per part", #lines == 3)
    Check("The preview counts the bars",
        lines[1].label == "Bars" and lines[1].detail == "2 bars")
    Check("The preview counts one reminder in the singular",
        lines[2].detail == "1 reminder")
    Check("The preview counts saved looks, which have no order",
        lines[3].detail == "1 look")
    Check("The preview of nothing is empty", #Share.Describe(nil) == 0)
end

---------------------------------------------------------------------------
-- Modules
--
-- The switches that decide which features run at all. Three kinds of check,
-- and the first two are the ones that would ship a silent hole:
--
--   the REGISTRY agrees with the pages - a module with no page is a feature
--   you can switch off and never find again, and a page naming a module that
--   does not exist greys itself out forever
--
--   the DEFAULTS say on - ApplyDefaults fills these into every existing
--   profile on the first login after an update, and any other value here
--   means the update switched somebody's bars off for them
--
--   WelcomeDue, which is pure and therefore testable without a profile: the
--   rule for when the first-run window opens, including the case that only
--   showed up while writing it - a generation bumped with no new module must
--   not open a window in anybody's face.
---------------------------------------------------------------------------
local function TestModules()
    local Modules = ns.Modules
    Check("There is a module registry", Modules ~= nil)
    if not Modules then return end

    local list = Modules:All()

    -- Not a fixed number. This said "four" and went red the day a fifth was
    -- added, which is a test failing at the exact moment the code was right -
    -- the count is not the rule. The rule is that the registry and the
    -- window's page list agree, and that is checked below in both directions.
    Check("There are modules registered", #list >= 4, tostring(#list))

    local seen = {}
    for _, entry in ipairs(list) do
        Check("Module '" .. tostring(entry.key) .. "' has a key that is a word",
            type(entry.key) == "string" and entry.key ~= "")
        Check("Module '" .. tostring(entry.key) .. "' is named",
            type(entry.title) == "string" and entry.title ~= "")
        -- The welcome window and the greyed page both print this. Empty, they
        -- offer a switch with nothing said about what it does.
        Check("Module '" .. tostring(entry.key) .. "' says what it is for",
            type(entry.blurb) == "string" and #entry.blurb > 20)
        Check("Module '" .. tostring(entry.key) .. "' has a mark that resolves",
            entry.glyph and ns.UI.HasGlyph(entry.glyph), tostring(entry.glyph))
        Check("Module key '" .. tostring(entry.key) .. "' is used once",
            not seen[entry.key])
        seen[entry.key] = true
    end

    -- The registry and the window's page list, in both directions.
    local pageByModule = {}
    for _, page in ipairs(ns.Options.PAGES) do
        if page.module then
            Check("Page '" .. page.key .. "' names a module that exists",
                Modules:Get(page.module) ~= nil, tostring(page.module))
            pageByModule[page.module] = page.key
        end
    end
    for _, entry in ipairs(list) do
        if entry.hidden then
            -- Hidden is "als wenn es nicht drin waere" (owner, 2026-08-16):
            -- no page, no rail row, no welcome row. A page for it would be
            -- a door to a room the house pretends not to have.
            Check("Module '" .. entry.key .. "' is hidden and has NO page",
                pageByModule[entry.key] == nil)
        else
            Check("Module '" .. entry.key
                .. "' has a page to be switched on from",
                pageByModule[entry.key] ~= nil)
        end
    end


    -- The defaults. Read from ns.DEFAULTS rather than from a live profile:
    -- this is the table an existing character gets filled in from.
    --
    -- EVERY MODULE HAS AN ANSWER HERE, and that is the rule - not "everything
    -- is on". A module missing from this table is filled in as nil, which
    -- Modules:IsOn reads as ON, so a feature that was meant to arrive quietly
    -- would switch itself on for everybody with no line anywhere saying so.
    --
    -- WHICH answer is a per-module decision and it is written at the entry.
    -- The six that draw or record something default on, because for those an
    -- update that switched them off would be an update that broke somebody's
    -- screen. The raid bar and the invite tool default OFF: one puts a row of
    -- buttons on the screen and the other acts in your name at people who are
    -- not in the room, and neither should start because somebody updated an
    -- addon. The welcome window is what offers them - which is what
    -- Modules.GENERATION exists for, and it is checked below.
    for _, entry in ipairs(list) do
        Check("Module '" .. entry.key .. "' has a default",
            ns.DEFAULTS.modules
                and type(ns.DEFAULTS.modules[entry.key]) == "boolean",
            "missing means nil, and nil reads as ON")
    end

    Check("A module that acts on its own is off until it is asked for",
        ns.DEFAULTS.modules.raidbar == false
            and ns.DEFAULTS.modules.invites == false)

    -- AND THE OTHER FIVE ARE STILL ON. Written out rather than "every other
    -- entry", because the list of features that may arrive switched on is a
    -- decision and not a default: the next module added has to be argued for
    -- in one of the two directions rather than inheriting whichever way this
    -- loop happened to be written.
    for _, key in ipairs({ "cotanks", "reminders", "externals",
        "answers", "deaths" }) do
        Check("Module '" .. key .. "' still defaults to ON",
            ns.DEFAULTS.modules[key] == true)
    end

    -- EVERY DEFAULT NAMES A MODULE THAT EXISTS, and this is the check the
    -- list above could never be. `cooldowns = true` shipped in the defaults
    -- for a version after the cooldown bars were removed, and the loop above
    -- asserted it - two dead things agreeing with each other, green the whole
    -- time. Nothing was wrong with either statement; the fault was that
    -- neither of them asked Modules.
    local known = {}
    for _, entry in ipairs(ns.Modules:All()) do known[entry.key] = true end
    for key in pairs(ns.DEFAULTS.modules) do
        Check("The default for '" .. key .. "' names a real module",
            known[key] == true,
            "Modules:All() has no such key - a switch for nothing")
    end
    Check("The welcome flag is NOT in the defaults",
        ns.DEFAULTS.welcomeSeen == nil,
        "a default would answer the question before it was asked")

    -- An unknown key answers YES. A typo in a gate has to leave the feature
    -- running, not switch it off for everybody.
    Check("An unknown module counts as running", Modules:IsOn("nonesuch"))

    -- The switch itself, on the live profile, put back immediately. The one
    -- test in this file that writes to your settings, and it writes one
    -- boolean it already knows the value of.
    if ns.db then
        ns.db.modules = ns.db.modules or {}
        local was = ns.db.modules.deaths
        local ok, err = pcall(function()
            ns.db.modules.deaths = false
            Check("A module switched off reads as off", not Modules:IsOn("deaths"))
            ns.db.modules.deaths = true
            Check("A module switched on reads as on", Modules:IsOn("deaths"))
            ns.db.modules.deaths = nil
            Check("A module nobody has answered for counts as on",
                Modules:IsOn("deaths"))
        end)
        ns.db.modules.deaths = was
        if not ok then error(err) end
    else
        Skip("The module switch on a live profile", "no profile open")
    end

    ---------------------------------------------------------------------
    -- WelcomeDue
    ---------------------------------------------------------------------
    local FAKE = {
        { key = "old", since = 1 },
        { key = "new", since = 2 },
    }

    local due, fresh, first = Modules.WelcomeDue(nil, 2, FAKE)
    Check("Never asked: the window is due", due)
    Check("Never asked: it is a first run", first)
    Check("Never asked: nothing is singled out as new", #fresh == 0)

    due = Modules.WelcomeDue(2, 2, FAKE)
    Check("Already asked about everything: not due", not due)

    due = Modules.WelcomeDue(3, 2, FAKE)
    Check("Asked about MORE than we ship: not due", not due,
        "a downgrade must not re-ask")

    due, fresh, first = Modules.WelcomeDue(1, 2, FAKE)
    Check("A new module makes it due again", due)
    Check("Only the new module is singled out",
        #fresh == 1 and fresh[1] == "new",
        table.concat(fresh, ","))
    Check("A second visit is not a first run", not first)

    -- The case that is easy to get wrong: the number moved, the list did not.
    due = Modules.WelcomeDue(1, 2, { { key = "old", since = 1 } })
    Check("A generation bump with no new module opens nothing", not due)

    due = Modules.WelcomeDue("yes", 2, FAKE)
    Check("A nonsense flag does not open the window every login", not due)

    -- AND THEN THE PAIR WE ACTUALLY SHIP.
    --
    -- Everything above runs on a made-up list. The one that goes wrong in a
    -- release is the real one: a module is added with `since = 4` and the
    -- generation stays at 3, so every character is asked "have you seen
    -- generation 3" - yes - and the new module is never offered to anybody.
    -- Silent, and it looks exactly like a module nobody wanted.
    local highest = 0
    for _, entry in ipairs(Modules:All()) do
        highest = math.max(highest, entry.since or 1)
    end
    Check("The generation we ship covers every module in it",
        Modules.GENERATION >= highest,
        string.format("generation %d, newest module since %d",
            Modules.GENERATION, highest))

    -- The two sentences that say how many features there are do not type the
    -- number any more; this is the list they count - minus what is hidden,
    -- because a sentence promising a switch nobody can see is the stale-copy
    -- fault with extra steps.
    local visible = 0
    for _, entry in ipairs(Modules:All()) do
        if not entry.hidden then visible = visible + 1 end
    end
    Check("The module count is the list's own visible length",
        Modules:Count() == visible,
        string.format("%d vs %d", Modules:Count(), visible))

    -- The memory tile on Diagnostics. The client answers in KB, and the whole
    -- point of the tile is that somebody can read it at a glance - "13312 KB"
    -- is the failure it exists to avoid.
    local Text = ns.Options.MemoryText
    Check("Memory under a megabyte reads in KB", Text(512) == "512 KB")
    Check("13312 KB reads as 13.0 MB", Text(13312) == "13.0 MB")
    Check("A megabyte exactly is already MB", Text(1024) == "1.0 MB")
    Check("Nothing to report is not an error", Text(nil) == "0 KB")
end

---------------------------------------------------------------------------
-- External cooldowns
--
-- The rule that decides WHO a click whispers, and it is the whole feature: a
-- panel that asks the wrong person is worse than no panel, because you spend
-- the two seconds you had believing help is coming.
--
-- Pure, and it takes the roster as a plain list - which is the only way this
-- can ever be tested. A five-man with two paladins in it, one of them a
-- healer, is not something a self test can arrange in the game.
---------------------------------------------------------------------------
local function TestExternals()
    -----------------------------------------------------------------------
    -- THE SLOTS BELONG TO THE SPEC, the panel does not.
    --
    -- Owner: "eigentlich requests auch". What a protection warrior asks other
    -- people for is not what the same character asks for as fury. Where the
    -- panel SITS, how many columns it has and which channels it uses stay on
    -- the profile - a request panel that jumps across the screen on a spec
    -- change would be a worse bug than the one this fixes.
    -----------------------------------------------------------------------
    -- ON A PROFILE OF ITS OWN, and the version before this one is the reason
    -- why. It emptied his real per-spec store, ran the checks and put the
    -- store back - honest enough - and then asked "is the other spec's first
    -- slot empty" against the LEGACY list, which is his and is not empty.
    -- Green on an empty desk, red in his client, and the check was asking
    -- about the world rather than about the code. A fixture states what the
    -- old list held, so the answer cannot depend on who runs it.
    OnStandInProfile({ cells = { [1] = 6940 }, rows = 2, columns = 5, x = 120 },
    function()
        PretendSpec("WARRIOR:73")
        local mine = ns.Externals.Config()
        Check("A spec nobody has played yet starts from the old list",
            mine.cells[1] == 6940, tostring(mine.cells[1]))

        mine.cells[1] = 97462
        local wasX, wasColumns = mine.x, mine.columns

        PretendSpec("WARRIOR:72")
        local other = ns.Externals.Config()
        Check("The other spec asks for its own cooldowns",
            other.cells[1] == 6940, tostring(other.cells[1]))
        Check("And the panel itself did not move with the spec",
            other.x == wasX and other.columns == wasColumns)

        PretendSpec("WARRIOR:73")
        Check("Coming back finds what this spec picked",
            ns.Externals.Config().cells[1] == 97462)
    end)

    local X = ns.Externals
    Check("The externals list exists", X ~= nil)
    if not X then return end

    ---------------------------------------------------------------------
    -- KEYS ON THE SLOTS
    --
    -- Owner, 2026-08-10: "das sollte standard sein, das haben fast alle
    -- addons". The binding presses into the SHOWN list, which is the same
    -- list the panel draws from - a key that hits the third slot while your
    -- eyes are on a different third slot is worse than no key.
    ---------------------------------------------------------------------
    Check("Every slot key has a name the game can show",
        X.BindingName(3) == "ZWOELFSTUFF_EXTERNAL_3", X.BindingName(3))
    Check("And a label under it",
        _G["BINDING_NAME_" .. X.BindingName(3)] ~= nil)
    Check("Eight of them", X.KEYS == 8, tostring(X.KEYS))

    -- The drawn list is never longer than what was picked, and it drops
    -- exactly what nobody present can cast.
    Check("What is shown is a subset of what is picked",
        #X.Shown() <= #X.Picked(), #X.Shown() .. " of " .. #X.Picked())

    -- A KEY PRESSED AT AN EMPTY PLACE MUST SAY SO, not throw and not go
    -- quiet. Alone, with nobody to ask, every slot is empty - so this is the
    -- press that happens most often while nothing is going on.
    Check("A key at a place with nothing in it is harmless",
        select(1, pcall(X.AskSlot, 99)) == true)

    Check("Every external names a spell and a class", (function()
        for _, entry in ipairs(X.SPELLS) do
            if type(entry.spellID) ~= "number" or type(entry.class) ~= "string" then
                return false
            end
        end
        return #X.SPELLS > 0
    end)())

    -- No duplicates: the panel keys its assignment table by spell id, and two
    -- entries with one id would share an assignment silently.
    local seen, twice = {}, nil
    for _, entry in ipairs(X.SPELLS) do
        if seen[entry.spellID] then twice = entry.spellID end
        seen[entry.spellID] = true
    end
    Check("No external is listed twice", twice == nil, tostring(twice))

    local sacrifice = X.Get(6940)
    Check("Blessing of Sacrifice is in the list", sacrifice ~= nil)
    Check("It belongs to the paladin",
        sacrifice and sacrifice.class == "PALADIN")

    -- THE NUMBERS THAT WERE LOOKED UP, GUARDED.
    --
    -- Owner asked for lust and a battle res; every id was read out of an
    -- installed, maintained addon rather than remembered, because a spell
    -- number recalled from memory has been wrong here twice. A test is the
    -- only thing that keeps a later edit from quietly putting a wrong one
    -- back - nothing else in this addon would notice: a bad id draws a
    -- question-mark icon and whispers somebody about a spell they do not have.
    --
    -- The CLASS is checked with the id, because that is what decides who gets
    -- whispered. A right id under the wrong class asks the wrong person.
    local researched = {
        { 2825,   "SHAMAN"      },   -- Bloodlust
        { 32182,  "SHAMAN"      },   -- Heroism
        { 80353,  "MAGE"        },   -- Time Warp
        { 264667, "HUNTER"      },   -- Primal Rage
        { 390386, "EVOKER"      },   -- Fury of the Aspects
        { 20484,  "DRUID"       },   -- Rebirth
        { 61999,  "DEATHKNIGHT" },   -- Raise Ally
        { 391054, "PALADIN"     },   -- Intercession
        { 20707,  "WARLOCK"     },   -- Soulstone
    }
    -- Asked of the TRANSLATION and of the offer list rather than of the
    -- table: what matters is that a player of that class ends up with that
    -- spell on their bar, and that it answers the slot the asker pressed. A
    -- test that walked `covers` itself would be the table written twice and
    -- would go on passing while the feature was broken.
    for _, want in ipairs(researched) do
        local offered = false
        for _, offer in ipairs(ns.Answers.Offers(want[2])) do
            if offer.spellID == want[1] then offered = true end
        end
        Check("A " .. want[2] .. " is offered " .. want[1], offered)
    end

    -- The five lusts are ONE question and the four battle resses are another,
    -- and the two are not the same question. Stated as the relationship
    -- rather than as "spell X sits in slot Y", which would only be the table
    -- copied out a second time.
    Check("Every lust answers the same slot", (function()
        for _, id in ipairs({ 32182, 80353, 264667, 390386 }) do
            if not X.SameSlot(id, 2825) then return false end
        end
        return true
    end)())
    Check("Every battle res answers the same slot", (function()
        for _, id in ipairs({ 61999, 391054, 20707 }) do
            if not X.SameSlot(id, 20484) then return false end
        end
        return true
    end)())
    Check("And lust is not a battle res", not X.SameSlot(2825, 20484))
    Check("Nor is an ordinary external either of them",
        not X.SameSlot(6940, 2825) and not X.SameSlot(6940, 20484))

    ---------------------------------------------------------------------
    -- ONE SLOT, SEVERAL SPELLS
    --
    -- Owner: "sprich das waere ein Lust command und Bres". The whole feature
    -- is a round trip between two clients that never agree about which spell
    -- "lust" is, so the round trip is what is checked.
    ---------------------------------------------------------------------
    local lust = X.Get(2825)
    Check("Lust is one slot, not five", lust ~= nil and lust.covers ~= nil)
    Check("It is called Lust rather than Bloodlust",
        X.Label(2825) == "Lust", tostring(X.Label(2825)))
    Check("Bres is one slot too", (X.Get(20484) or {}).covers ~= nil)
    Check("It is called Bres", X.Label(20484) == "Bres")

    -- An ordinary spell is untouched by either translation - that is what
    -- lets every other caller in the file stay as it was.
    Check("An ordinary spell is its own slot", X.SlotFor(6940) == 6940)

    ---------------------------------------------------------------------
    -- POWER INFUSION, the one entry that is not a defensive
    --
    -- Owner asked for it by name. The numbers come out of LibOpenRaid's
    -- Midnight file, and the two mistakes worth guarding are the ones that
    -- would look right in the table and be wrong in a group: a spec
    -- restriction (the source lists ALL THREE priest specs, so restricting
    -- it hides the priest most likely to have it) and a healer flag (it is
    -- not a healer's spell, and the healer is often the wrong priest).
    ---------------------------------------------------------------------
    local pi = X.Get(10060)
    Check("Power Infusion is in the request list", pi ~= nil)
    Check("...as the priest's, at two minutes",
        pi and pi.class == "PRIEST" and pi.cooldown == 120,
        pi and tostring(pi.cooldown) or "missing")
    Check("...asked of ANY priest, because all three specs have it",
        pi and pi.specIndex == nil and pi.healer ~= true)
    Check("...and it is its own slot, not folded into another",
        X.SlotFor(10060) == 10060 and (pi or {}).covers == nil)

    -- The shadow priest is a right answer and the rule must not skip past
    -- them. A healer-flagged entry would have, silently.
    Check("A group whose only priest is shadow can still be asked", (function()
        local roster = {
            { name = "Me",     class = "WARRIOR", role = "TANK", isPlayer = true },
            { name = "Schatten", class = "PRIEST", role = "DAMAGER" },
            { name = "Baum",   class = "DRUID",   role = "HEALER" },
        }
        local target = X.Whom(pi, roster, nil)
        return target ~= nil and target.name == "Schatten"
    end)())

    -- THE ROUND TRIP. The asker's panel holds the slot; the mage answers with
    -- his own spell; the ACK coming back has to land on the slot again, or
    -- the asker's cell never goes quiet.
    Check("A mage's Time Warp lands back on the Lust slot",
        X.SlotFor(80353) == 2825)
    Check("A warlock's Soulstone lands back on the Bres slot",
        X.SlotFor(20707) == 20484)

    -- Two groups claiming one spell would make SlotFor answer at random,
    -- depending on which entry was written last.
    Check("No spell is covered by two slots", (function()
        local seen = {}
        for _, entry in ipairs(X.SPELLS) do
            for _, sub in ipairs(entry.covers or {}) do
                if seen[sub.spellID] then return false end
                seen[sub.spellID] = true
            end
        end
        return true
    end)())

    -- WHO A GROUPED SLOT WOULD ASK: anybody holding a version of it, not the
    -- class the slot happens to be stored under.
    Check("The Lust slot would ask the mage in the group", (function()
        local roster = {
            { name = "Me",   class = "WARRIOR", isPlayer = true },
            { name = "Mage", class = "MAGE" },
        }
        local target = X.Whom(lust, roster, nil)
        return target ~= nil and target.name == "Mage"
    end)())
    Check("A group with nobody who can lust has nobody to ask", (function()
        local roster = {
            { name = "Me",     class = "WARRIOR", isPlayer = true },
            { name = "Sneaky", class = "ROGUE" },
        }
        return X.Whom(lust, roster, nil) == nil
    end)())

    -- A CLASS TOKEN, not a class name. "Death Knight" and "DEATHKNIGHT" look
    -- equally right in a table and only one of them ever matches a roster
    -- entry, which compares against UnitClass's second return.
    Check("Every external names a real class token", (function()
        local tokens = {}
        for _, token in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE",
            "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK",
            "DRUID", "DEMONHUNTER", "EVOKER" }) do
            tokens[token] = true
        end
        for _, entry in ipairs(X.SPELLS) do
            if not tokens[entry.class] then return false end
        end
        return true
    end)())

    ---------------------------------------------------------------------
    -- Who gets asked
    ---------------------------------------------------------------------
    local ROSTER = {
        { name = "Zwoelf",  class = "DEATHKNIGHT", role = "TANK",   isPlayer = true },
        { name = "Heiler",  class = "PALADIN",     role = "HEALER" },
        { name = "Schaden", class = "PALADIN",     role = "DAMAGER" },
        { name = "Baum",    class = "DRUID",       role = "HEALER" },
    }

    local who = X.Whom(sacrifice, ROSTER)
    Check("The healing paladin is asked, not the other one",
        who and who.name == "Heiler", who and who.name or "nobody")

    local named, why = X.Whom(sacrifice, ROSTER, "Schaden")
    Check("A name you assigned wins over the rule",
        named and named.name == "Schaden", named and named.name or "nobody")
    Check("And it says it was an assignment", why == "assigned", tostring(why))

    -- The assigned player left the group. Falling back is right; silently
    -- whispering somebody else without saying so would not be.
    local gone, goneWhy = X.Whom(sacrifice, ROSTER, "Somebody Else")
    Check("An assignment to somebody who left falls back",
        gone and gone.name == "Heiler", gone and gone.name or "nobody")
    Check("And the fallback does not claim to be the assignment",
        goneWhy ~= "assigned", tostring(goneWhy))

    Check("Nobody of that class means nobody is asked",
        X.Whom(X.Get(116849), ROSTER) == nil)   -- Life Cocoon, no monk here

    -- THE PLAYER IS NEVER ASKED. A paladin tank whispering himself for a
    -- Blessing of Sacrifice is the panel answering its own question.
    local SELF_ONLY = {
        { name = "Zwoelf", class = "PALADIN", role = "TANK", isPlayer = true },
    }
    Check("You are never a candidate for your own external",
        X.Whom(sacrifice, SELF_ONLY) == nil)
    Check("And that leaves no candidates at all",
        #X.Candidates(sacrifice, SELF_ONLY) == 0)

    Check("An unknown spell has no candidates",
        #X.Candidates(nil, ROSTER) == 0)

    ---------------------------------------------------------------------
    -- WHICH SPEC, which is the owner's priest bug
    --
    -- "wenn ich einen priester in der gruppe habe, werden fuer beide heiler
    -- specs die icons angezeigt." Pain Suppression is Discipline's and
    -- Guardian Spirit is Holy's, and a class check cannot tell them apart.
    --
    -- THE NUMBERS BELOW ARE THE GAME'S, not ours. The test asks
    -- Specs.Table() what a priest's specs actually are and builds its roster
    -- out of that, so it is checking the rule rather than agreeing with the
    -- assumption the rule is built on.
    ---------------------------------------------------------------------
    local S = ns.Specs

    Check("Unknown spec keeps the icon", S and X.SpecFits({ spec = nil }, 42))
    Check("A matching spec keeps it", S and X.SpecFits({ spec = 42 }, 42))
    Check("A different spec loses it", S and not X.SpecFits({ spec = 43 }, 42))
    Check("No restriction keeps everybody",
        S and X.SpecFits({ spec = 43 }, nil))

    -- The role guard, on a table we control: an index that points at the
    -- wrong KIND of spec must produce nothing rather than a wrong filter.
    local FAKE = { PRIEST = {
        [1] = { id = 111, name = "One",   role = "HEALER" },
        [2] = { id = 222, name = "Two",   role = "HEALER" },
        [3] = { id = 333, name = "Three", role = "DAMAGER" },
    } }
    Check("A spec index resolves to the game's id",
        S and S.Resolve(FAKE, "PRIEST", 2, "HEALER") == 222)
    Check("An index whose role is wrong resolves to nothing",
        S and S.Resolve(FAKE, "PRIEST", 3, "HEALER") == nil)
    Check("An index past the end resolves to nothing",
        S and S.Resolve(FAKE, "PRIEST", 9, "HEALER") == nil)
    Check("A class the game does not know resolves to nothing",
        S and S.Resolve(FAKE, "TINKER", 1, "HEALER") == nil)

    -- The throttle. Pure, with its own clock, because the alternative is a
    -- test that waits thirty seconds.
    Check("A fresh guid may be asked about", S and S.MayAsk(100, nil, nil))
    Check("Not twice within the gap", S and not S.MayAsk(100, 99.5, nil))
    Check("And not again straight after a failure",
        S and not S.MayAsk(100, nil, 90))
    Check("But it is worth another try later",
        S and S.MayAsk(200, nil, 100))

    ---------------------------------------------------------------------
    -- AGAINST THE REAL TABLE. In game this is the check that matters: every
    -- index the catalogue claims has to point at a spec of the role it says,
    -- on THIS client. It cannot catch two specs of one class with the same
    -- role swapped - /zs specs prints the names for that - but it does catch
    -- the whole family of "the order moved".
    ---------------------------------------------------------------------
    local list = S and S.Table() or {}
    Check("The game answered about specialisations", next(list) ~= nil)

    if next(list) then
        local bad
        for _, entry in ipairs(X.SpecRestrictions()) do
            if not S.Resolve(list, entry.class, entry.index, entry.role) then
                bad = string.format("%s %s %d", tostring(entry.name),
                    entry.class, entry.index)
            end
        end
        Check("Every spec the catalogue names is the role it says",
            bad == nil, bad)

        -- TWO LISTS, ONE WORD, TWO MEANINGS is how a drag rule rejected
        -- every drop in silence three days ago. Taunts.SPELLS carries a spec
        -- ID under `spec`; the externals carry an INDEX under `specIndex`.
        -- Neither list may grow the other's field.
        local crossed
        for _, entry in ipairs(X.SPELLS) do
            if entry.spec then crossed = "an external carries `spec`" end
        end
        for _, entry in ipairs(ns.Taunts.SPELLS) do
            if entry.specIndex then crossed = "a taunt carries `specIndex`" end
        end
        Check("The two spell lists do not swap each other's spec field",
            crossed == nil, crossed)

        -- AND THE ID THAT WAS ALREADY THERE, checked at last. Taunts has
        -- carried spec = 250 for Death Grip since the day it was written, on
        -- the word of another addon's table. The game can settle it now: it
        -- has to be a real specialisation OF THAT CLASS.
        --
        -- ONLY AGAINST A CLIENT. The desk harness invents its spec ids on
        -- purpose - baking the real ones into a stub would turn this into the
        -- assumption agreeing with itself, which is not a check.
        if __FAKE_SPECS then
            Skip("The taunt list's spec ids are real",
                "the harness invents them - a client has to answer this")
        else
            local wrong
            for _, entry in ipairs(ns.Taunts.SPELLS) do
                if entry.spec then
                    local found
                    for _, spec in pairs(list[entry.class] or {}) do
                        if spec.id == entry.spec then found = true end
                    end
                    if not found then
                        wrong = string.format("%s has no spec %d",
                            entry.class, entry.spec)
                    end
                end
            end
            Check("Every spec id the taunt list names belongs to its class",
                wrong == nil, wrong)
        end

        -- THE BUG ITSELF, end to end. Two priest slots, one priest, and the
        -- panel must offer exactly the one he can actually cast.
        local priest = list.PRIEST
        local disc = priest and priest[1] and priest[1].id
        local holy = priest and priest[2] and priest[2].id
        if disc and holy and disc ~= holy then
            local WITH_DISC = {
                { name = "Zwoelf", class = "DEATHKNIGHT", isPlayer = true },
                { name = "Prister", class = "PRIEST", role = "HEALER",
                  spec = disc },
            }
            Check("A discipline priest is offered Pain Suppression",
                #X.Candidates(X.Get(33206), WITH_DISC) == 1)
            Check("And is NOT offered Guardian Spirit",
                #X.Candidates(X.Get(47788), WITH_DISC) == 0)

            local UNREAD = {
                { name = "Zwoelf", class = "DEATHKNIGHT", isPlayer = true },
                { name = "Prister", class = "PRIEST", role = "HEALER" },
            }
            Check("A priest nobody has read yet is offered both",
                #X.Candidates(X.Get(33206), UNREAD) == 1
                and #X.Candidates(X.Get(47788), UNREAD) == 1)
        end
    end

    ---------------------------------------------------------------------
    -- What the whisper says
    ---------------------------------------------------------------------
    local cfg = X.Config()
    local was = cfg.message

    cfg.message = nil
    Check("The default message names the spell",
        X.Message("Ironbark"):find("Ironbark", 1, true) ~= nil,
        X.Message("Ironbark"))

    cfg.message = "%s jetzt bitte"
    Check("A message you wrote is used",
        X.Message("Ironbark") == "Ironbark jetzt bitte", X.Message("Ironbark"))

    -- The case somebody will create by deleting the placeholder: the spell
    -- has to be named anyway, or every slot sends one sentence and nobody
    -- knows which of four buttons is being asked for.
    cfg.message = "HILFE"
    Check("A message with no placeholder still names the spell",
        X.Message("Ironbark"):find("Ironbark", 1, true) ~= nil,
        X.Message("Ironbark"))

    -- %n, the person. Worth having in party chat, where "Ironbark bitte!"
    -- asks nobody in particular.
    cfg.message = "%n, %s bitte"
    Check("The name is written into the message",
        X.Message("Ironbark", "Baum") == "Baum, Ironbark bitte",
        X.Message("Ironbark", "Baum"))

    -- Nobody resolved: the placeholder comes OUT rather than being read as
    -- "%n" by somebody mid-pull, and the space it sat in goes with it.
    Check("With nobody to name, the placeholder is removed",
        X.Message("Ironbark", nil):find("%%n") == nil,
        X.Message("Ironbark", nil))
    Check("And no hole is left where the name was",
        X.Message("Ironbark", nil) == ", Ironbark bitte"
            or X.Message("Ironbark", nil) == "Ironbark bitte"
            or X.Message("Ironbark", nil):find("  ") == nil,
        X.Message("Ironbark", nil))

    -- A percent sign in a spell name would otherwise be read as a capture by
    -- the NEXT gsub. Nothing in this list has one today, which is exactly why
    -- it is worth a test rather than a memory.
    cfg.message = "%s bitte"
    Check("A percent in a name survives",
        X.Message("100%% Mana", nil):find("Mana", 1, true) ~= nil,
        X.Message("100%% Mana", nil))

    cfg.message = was

    ---------------------------------------------------------------------
    -- WHICH CHANNEL IT ACTUALLY GOES ON
    --
    -- The one that would have shipped broken: /p is NOT the party channel in
    -- a dungeon from the group finder. That group talks on INSTANCE_CHAT, and
    -- a message sent to PARTY there arrives NOWHERE - silently, which is the
    -- worst way for a "tell the healer" button to fail.
    ---------------------------------------------------------------------
    local R = X.ResolveChannel
    Check("A whisper is a whisper anywhere", R("WHISPER") == "WHISPER")
    Check("Say needs no group", R("SAY", false) == "SAY")

    Check("A group message alone goes nowhere, and says so",
        R("GROUP", false) == nil)
    Check("In a party it is PARTY",
        R("GROUP", true, false, false) == "PARTY")
    Check("In a raid it is RAID",
        R("GROUP", true, true, false) == "RAID")
    Check("IN A DUNGEON FROM THE FINDER IT IS INSTANCE_CHAT",
        R("GROUP", true, false, true) == "INSTANCE_CHAT",
        tostring(R("GROUP", true, false, true)))
    Check("An instance raid is instance chat too",
        R("GROUP", true, true, true) == "INSTANCE_CHAT")

    -- The raid warning, and its two ways of not being available. Neither
    -- refuses to send: the message still wants to arrive.
    Check("A raid warning as lead is a raid warning",
        R("RAID_WARNING", true, true, false, true) == "RAID_WARNING")
    local fallback, why2 = R("RAID_WARNING", true, true, false, false)
    Check("Without assist it falls back to raid chat", fallback == "RAID")
    Check("And it says why", type(why2) == "string" and #why2 > 0)
    Check("Outside a raid it goes to the group instead",
        R("RAID_WARNING", true, false, false, false) == "PARTY")
    Check("In an instance group, to instance chat",
        R("RAID_WARNING", true, false, true, false) == "INSTANCE_CHAT")

    ---------------------------------------------------------------------
    -- SEVERAL CHANNELS AT ONCE
    --
    -- The de-duplication is the part worth a test: "Raid warning" and "Party
    -- or raid" both come out as RAID for somebody without assist, and sending
    -- one sentence to one channel twice is a person spamming their own group
    -- because of a setting they thought was two different things.
    ---------------------------------------------------------------------
    local function Names(list)
        local out = {}
        for _, entry in ipairs(list) do out[#out + 1] = entry.channel end
        return table.concat(out, ",")
    end

    Check("One channel goes to one place",
        Names(X.SendingTo({ WHISPER = true }, true, false, false, false))
            == "WHISPER")

    Check("A whisper and the group are two messages",
        Names(X.SendingTo({ WHISPER = true, GROUP = true },
            true, false, false, false)) == "WHISPER,PARTY",
        Names(X.SendingTo({ WHISPER = true, GROUP = true },
            true, false, false, false)))

    -- Both resolve to RAID without assist. One message, not two.
    Check("Two choices that come out the same are sent once",
        Names(X.SendingTo({ GROUP = true, RAID_WARNING = true },
            true, true, false, false)) == "RAID",
        Names(X.SendingTo({ GROUP = true, RAID_WARNING = true },
            true, true, false, false)))

    -- With assist they are genuinely two channels, and both are wanted.
    Check("With assist they are two different channels",
        Names(X.SendingTo({ GROUP = true, RAID_WARNING = true },
            true, true, false, true)) == "RAID,RAID_WARNING",
        Names(X.SendingTo({ GROUP = true, RAID_WARNING = true },
            true, true, false, true)))

    Check("Solo, a group-only choice sends nowhere",
        #X.SendingTo({ GROUP = true }, false, false, false, false) == 0)
    Check("But Say still goes out solo",
        Names(X.SendingTo({ GROUP = true, SAY = true },
            false, false, false, false)) == "SAY")

    -- The last one cannot be switched off. A button that sends nowhere is not
    -- a setting, and the click that emptied it is the one nobody notices.
    local keptChannels = X.Config().channels
    X.Config().channels = { WHISPER = true }
    X.ToggleChannel("WHISPER")
    Check("Switching off the last channel leaves one on",
        next(X.Config().channels) ~= nil)
    X.Config().channels = keptChannels

    ---------------------------------------------------------------------
    -- THE LOOK, UNDER THE BAR'S OWN KEY NAMES
    --
    -- The point of the naming is that ns.PaintSurface and ns.PaintBorder can
    -- read this table without knowing what a panel is. If a key is ever
    -- renamed here, the painters keep working on the DEFAULTS and the setting
    -- silently stops doing anything - which is the failure this catches.
    ---------------------------------------------------------------------
    local style = X.Style()
    for _, key in ipairs({ "borderSize", "borderColor", "borderTexture",
        "backdrop", "backdropColor", "backdropAlpha", "backdropTexture",
        "iconZoom" }) do
        Check("The panel's style carries '" .. key .. "'", style[key] ~= nil)
    end
    Check("Its border thickness is a number", type(style.borderSize) == "number")
    Check("Its border colour is three numbers",
        type(style.borderColor) == "table" and #style.borderColor >= 3)
    Check("A negative thickness cannot get through",
        (function()
            local keptSize = X.Config().borderSize
            X.Config().borderSize = -5
            local clamped = X.Style().borderSize
            X.Config().borderSize = keptSize
            return clamped >= 0
        end)())

    -- The style-key spelling check went with the bars. It compared these
    -- names against ns.BAR_STYLE_KEYS - two renderers, one vocabulary -
    -- and there is no second renderer left to disagree with. The names
    -- themselves are unchanged; nothing can cross-check them any more.

    ---------------------------------------------------------------------
    -- Slots
    --
    -- Every check below writes, so all of it runs on a stand-in profile
    -- (see OnStandInProfile). It used to run on HIS, and emptying cfg.cells
    -- first stopped being enough the day the slots became per-spec.
    ---------------------------------------------------------------------
    OnStandInProfile({ cells = {}, rows = 1, columns = 4 }, function()
        Check("An empty panel has nothing on it", #X.Picked() == 0)

        local landed = X.Pick(6940)
        Check("A spell lands in the first free slot", landed == 1,
            tostring(landed))
        Check("And it is on the panel", X.IsPicked(6940))

        landed = X.Pick(102342, 3)
        Check("A marked slot is used when there is one", landed == 3,
            tostring(landed))
        Check("The slot between them is still empty", X.SpellAt(2) == nil)

        -- One spell, one slot. A second copy would whisper twice for one
        -- click.
        X.SetSlot(2, 6940)
        Check("Putting a spell somewhere else MOVES it", X.SpellAt(1) == nil)
        Check("And it is in its new place", X.SpellAt(2) == 6940)

        -- What falls off the end stays put. The same rule a shrunk bar
        -- follows.
        X.SetColumns(2)
        Check("A slot outside the lattice keeps what is in it",
            X.SpellAt(3) == 102342)
        Check("But it is not on the panel", #X.Picked() == 1)
        X.SetColumns(4)
        Check("Making the lattice bigger gives it back", #X.Picked() == 2)

        X.ClearSlot(2)
        Check("Clearing a slot empties it", X.SpellAt(2) == nil)

        -----------------------------------------------------------------
        -- ROWS AND COLUMNS, the shape itself
        --
        -- Owner: "anzahl rows fehlt! wie die cdm einstellungen, reihe und
        -- spalten anzahl." So the count is not a setting any more - it is
        -- what the two of them multiply to, and there is no third number
        -- that can disagree.
        -----------------------------------------------------------------
        X.SetRows(3)
        X.SetColumns(4)
        Check("Rows times columns is how many places there are",
            X.Count() == 12, tostring(X.Count()))

        X.SetRows(0)
        Check("Neither ever goes below one", X.Rows() == 1)
        X.SetColumns(999)
        Check("And neither past its ceiling", X.Columns() == X.MAX_COLUMNS)
    end)

    -- WHERE EACH SLOT SITS. Pure, and the same answer the panel and the
    -- preview both draw from - a preview that disagrees with the screen is
    -- worse than no preview.
    local function At(index, rows, columns, down)
        local column, row = X.Cell(index, rows, columns, down)
        return column .. "," .. row
    end
    Check("The first slot is the top left corner", At(1, 2, 4) == "0,0")
    Check("Across, the fourth is at the end of the first row",
        At(4, 2, 4) == "3,0", At(4, 2, 4))
    Check("Across, the fifth wraps to the next row", At(5, 2, 4) == "0,1",
        At(5, 2, 4))
    Check("Down, the second is UNDER the first",
        At(2, 2, 4, true) == "0,1", At(2, 2, 4, true))
    Check("Down, the third starts a new column",
        At(3, 2, 4, true) == "1,0", At(3, 2, 4, true))

    -- HOW BIG THE DRAWN PANEL IS. What nobody can cast is not drawn at all,
    -- so three usable spells in a lattice of twelve is three icons wide -
    -- the owner's "verschwindet ganz", measured.
    local function Extent(shown, rows, columns, down)
        local wide, tall = X.Extent(shown, rows, columns, down)
        return wide .. "x" .. tall
    end
    Check("Nothing to show is no size at all", Extent(0, 2, 4) == "0x0")
    Check("Three of twelve are three across and one down",
        Extent(3, 3, 4) == "3x1", Extent(3, 3, 4))
    Check("Five of twelve wrap onto a second row",
        Extent(5, 3, 4) == "4x2", Extent(5, 3, 4))
    Check("Growing downwards, three are one column of three",
        Extent(3, 3, 4, true) == "1x3", Extent(3, 3, 4, true))
    Check("A full lattice is exactly its own shape",
        Extent(12, 3, 4) == "4x3", Extent(12, 3, 4))

    ---------------------------------------------------------------------
    -- THE OLD SHAPE IS READ ONCE AND DROPPED
    --
    -- A profile written before the lattice carries a count and a line width.
    -- This is the migration everybody who updates runs exactly once, and
    -- getting it wrong means somebody's arranged panel comes back as a
    -- default - which is the same thing as losing it.
    ---------------------------------------------------------------------
    -- Each shape gets a profile of its own rather than one profile being bent
    -- back into an older shape between the two: a migration is something that
    -- happens ONCE to a profile, and a fixture that has already run one of
    -- them is not the thing being tested.
    OnStandInProfile({ count = 12, perLine = 4 }, function(stand)
        local cfg = X.Config()
        Check("An old count of twelve in lines of four is 3 x 4",
            cfg.rows == 3 and cfg.columns == 4,
            tostring(cfg.rows) .. "x" .. tostring(cfg.columns))
        Check("And the two old keys are gone rather than kept in step",
            cfg.count == nil and cfg.perLine == nil)
        Check("And it is the profile's own table that was rewritten",
            stand.externals == cfg)
    end)

    -- THE OLDEST PROFILE OF ALL: an ordered `picked` list AND a count. Both
    -- migrations run in one call, and reading them in the wrong order threw
    -- on login - the lattice one deletes cfg.count, and the list one was
    -- doing arithmetic on it afterwards.
    --
    -- A profile that old has no record of the pre-spec slots either, because
    -- there were none: cellsWere is written the first time Config runs on a
    -- profile that HAS slots. Setting it here would be a fixture that could
    -- not exist, and it would hide the migration behind it.
    --
    -- THE HAND-OFF IS PART OF THE MIGRATION NOW, and this is where his client
    -- said so: what the list migration writes lands in cfg.cells, and the
    -- last thing Config does is re-point cfg.cells at the table for the spec
    -- being played. If those two are the wrong way round, the migration runs,
    -- succeeds, and is thrown away in the same call - and nobody sees it,
    -- because the desk has no spec and never reaches the hand-off.
    OnStandInProfile({ count = 6, perLine = 6, picked = { 6940, 102342 } },
    function()
        local ok, cfg = pcall(X.Config)
        Check("A profile from before the slots still opens", ok, tostring(cfg))
        cfg = ok and cfg or {}
        Check("And its spells are in the first two slots",
            (cfg.cells or {})[1] == 6940 and (cfg.cells or {})[2] == 102342)
        Check("And it has a lattice big enough to hold them",
            (cfg.rows or 0) * (cfg.columns or 0) >= 2)
        Check("And the ordered list is gone rather than read twice",
            cfg.picked == nil)
    end)

    ---------------------------------------------------------------------
    -- WHAT A LOGIN DOES TO A PANEL SOMEBODY HAS ARRANGED
    --
    -- Owner, 2026-08-09: "nach rl ist mein preset von meinen external cds
    -- immer weg." What he was actually looking at was a preview that did not
    -- draw - but "the login path keeps what I arranged" is worth pinning down
    -- rather than believing, because ApplyDefaults runs over every profile
    -- before anything reads it and it is the one thing that could.
    --
    -- Run on a stand-in profile, so this can never touch his own.
    ---------------------------------------------------------------------
    local realDB = ns.db
    local saved = {
        externals = {
            cells = { [1] = 6940, [3] = 102342 },
            assigned = { [6940] = "Heiler" },
            rows = 2, columns = 5,
            -- Whisper switched OFF and Say switched on. Stored by being
            -- MISSING, which is the shape ApplyDefaults would undo.
            channels = { SAY = true },
            message = "%s bitte!",
        },
    }
    ns.ApplyDefaults(saved, ns.DEFAULTS)
    ns.db = saved
    local after = X.Config()
    ns.db = realDB

    Check("A login keeps the spells you put in your slots",
        after.cells[1] == 6940 and after.cells[3] == 102342)
    Check("And the lattice you arranged them in",
        after.rows == 2 and after.columns == 5,
        tostring(after.rows) .. "x" .. tostring(after.columns))
    Check("And who you assigned them to", after.assigned[6940] == "Heiler")
    Check("A CHANNEL YOU SWITCHED OFF STAYS OFF over a login",
        after.channels.WHISPER == nil and after.channels.SAY == true)

    ---------------------------------------------------------------------
    -- THE PREVIEW FITS THE PAGE
    --
    -- The band does not scroll, so the lattice has to be drawn at whatever
    -- size fits both ways. This is the rule that stops twelve columns running
    -- off the edge of the settings page - which is not something the desktop
    -- harness can see, because every frame out here answers 400 wide.
    ---------------------------------------------------------------------
    local P = ns.OptionsExternals and ns.OptionsExternals.PreviewSize
    if P then
        Check("A small lattice is drawn at the design's own size",
            P(1, 6, 730, 200) == 40, tostring(P(1, 6, 730, 200)))
        Check("Twelve columns still fit across the page",
            P(1, 12, 730, 200) * 12 + 11 * 8 <= 730,
            tostring(P(1, 12, 730, 200)))
        Check("Six rows still fit inside the band",
            P(6, 6, 730, 200) * 6 + 5 * 8 <= 200, tostring(P(6, 6, 730, 200)))
        Check("It never shrinks past being clickable", P(6, 12, 200, 60) >= 22,
            tostring(P(6, 12, 200, 60)))
    end

    -- Nothing to put back. The three lines that used to stand here saved
    -- cfg.cells, cfg.rows and cfg.columns at the top of this suite and wrote
    -- them again down here - and the first of the three had become a no-op:
    -- what it saved was the per-spec table itself, so it handed back the very
    -- table the checks had been editing. A restore that cannot fail is worth
    -- less than no restore, because it reads like a promise.
end

---------------------------------------------------------------------------
-- THE TAUNT ANNOUNCE (roadmap 6)
--
-- Every rule that decides anything here is pure and takes the world as an
-- argument, because none of these states can be arranged in game: a raid with
-- two other tanks, a party where you have no assist, a second press half a
-- second after the first.
---------------------------------------------------------------------------
local function TestTaunts()
    local T = ns.Taunts
    Check("The taunt list exists", T ~= nil)
    if not T then return end

    Check("Every taunt names a spell and a class", (function()
        for _, entry in ipairs(T.SPELLS) do
            if type(entry.spellID) ~= "number" or type(entry.class) ~= "string" then
                return false
            end
        end
        return #T.SPELLS > 0
    end)())

    -- The six classes that have one. Read out of NorthernSkyRaidTools rather
    -- than remembered - if this ever goes red, check THAT list first.
    Check("A warrior's Taunt is one", T.IsTaunt(355))
    Check("Dark Command is one", T.IsTaunt(56222))
    Check("Hand of Reckoning is one", T.IsTaunt(62124))
    Check("Provoke is one", T.IsTaunt(115546))
    Check("Growl is one", T.IsTaunt(6795))
    Check("Torment is one", T.IsTaunt(185245))
    Check("A Death Strike is not", T.IsTaunt(49998) == false)

    -- DEATH GRIP TAUNTS IN BLOOD AND ONLY IN BLOOD. A frost death knight
    -- pressing it is pulling something, not taking it, and announcing a swap
    -- there tells the other tank something untrue.
    Check("Death Grip counts for Blood", T.IsTaunt(49576, 250))
    Check("But not for Frost", T.IsTaunt(49576, 251) == false)
    Check("With no spec known it still counts", T.IsTaunt(49576, nil))

    ---------------------------------------------------------------------
    -- Who the other tank is
    ---------------------------------------------------------------------
    local ROSTER = {
        { name = "Zwoelf", class = "DEATHKNIGHT", role = "TANK", isPlayer = true },
        { name = "Krieger", class = "WARRIOR",    role = "TANK" },
        { name = "Heiler",  class = "PRIEST",     role = "HEALER" },
        { name = "Zweit",   class = "DRUID",      role = "TANK" },
    }

    local other = T.CoTank(ROSTER)
    Check("The other tank is the one who is not you",
        other and other.name == "Krieger", other and other.name or "nobody")

    local named, why = T.CoTank(ROSTER, "Zweit")
    Check("A tank you named wins over the rule",
        named and named.name == "Zweit", named and named.name or "nobody")
    Check("And it says it was an assignment", why == "assigned", tostring(why))

    local gone = T.CoTank(ROSTER, "Somebody Else")
    Check("Naming somebody who left falls back to the rule",
        gone and gone.name == "Krieger", gone and gone.name or "nobody")

    Check("Tanking alone, there is nobody to tell",
        T.CoTank({ { name = "Zwoelf", role = "TANK", isPlayer = true } }) == nil)
    Check("YOU are never the other tank",
        T.CoTank({ { name = "Zwoelf", role = "TANK", isPlayer = true } },
            "Zwoelf") == nil)

    ---------------------------------------------------------------------
    -- What it says
    ---------------------------------------------------------------------
    Check("The default names what you taunted",
        T.Message(nil, "Dark Command", "Golem"):find("Golem", 1, true) ~= nil,
        T.Message(nil, "Dark Command", "Golem"))
    Check("The taunt itself can be in it too",
        T.Message("%s -> %t", "Dark Command", "Golem")
            == "Dark Command -> Golem",
        T.Message("%s -> %t", "Dark Command", "Golem"))
    Check("And the other tank",
        T.Message("%n, ich hab ihn", nil, nil, "Krieger") == "Krieger, ich hab ihn",
        T.Message("%n, ich hab ihn", nil, nil, "Krieger"))

    -- Nothing to fill it with: the placeholder comes OUT rather than being
    -- read out as "%t" by somebody mid-pull.
    Check("An unfilled placeholder is removed",
        T.Message("Taunt: %t", "Dark Command", nil):find("%%t") == nil,
        T.Message("Taunt: %t", "Dark Command", nil))
    Check("And no hole is left where it was",
        T.Message("Taunt: %t", "Dark Command", nil) == "Taunt:",
        T.Message("Taunt: %t", "Dark Command", nil))

    -- ONE PASS. A mob called "%n the Devourer" must not be read as a
    -- placeholder by a second substitution, because there is no second one.
    Check("A placeholder inside a NAME is left alone",
        T.Message("Taunt: %t", nil, "%n the Devourer", "Krieger")
            == "Taunt: %n the Devourer",
        T.Message("Taunt: %t", nil, "%n the Devourer", "Krieger"))

    ---------------------------------------------------------------------
    -- Whether it speaks at all
    --
    -- OFF UNTIL ASKED FOR is the load-bearing one: an addon that starts
    -- writing in party chat after an update is the worst surprise it could
    -- hand somebody, and this is the check that keeps that promise.
    ---------------------------------------------------------------------
    ---------------------------------------------------------------------
    -- Whether the BUTTON is on the screen - the same pure shape.
    --
    -- "Only in a raid" is the newest gate and the one that would silently
    -- undo the one above it if it defaulted on: a fresh profile in a
    -- dungeon would switch the button on and see nothing.
    ---------------------------------------------------------------------
    local B = T.ButtonWanted
    Check("No button asked for, no button", B({}, true, true) == false)
    Check("Asked for, in a group: shown",
        B({ button = true }, true, false) == true)
    Check("Asked for, alone: hidden by the group gate that defaults on",
        B({ button = true }, false, false) == false)
    Check("The group gate can be switched off",
        B({ button = true, buttonOnlyInGroup = false }, false, false) == true)
    Check("The raid gate defaults OFF - a dungeon group still gets it",
        B({ button = true }, true, false) == true)
    Check("Raid gate on, in a dungeon: hidden",
        B({ button = true, buttonOnlyInRaid = true }, true, false) == false)
    Check("Raid gate on, in a raid: shown",
        B({ button = true, buttonOnlyInRaid = true }, true, true) == true)

    local S = T.ShouldAnnounce
    Check("Switched off, it says nothing", S({}, true, true) == false)
    Check("Switched on in a group, it speaks",
        S({ announce = true }, true, true) == true)
    Check("Alone, it stays quiet",
        S({ announce = true }, false, false) == false)
    Check("Alone is allowed when you asked for it",
        S({ announce = true, onlyInGroup = false }, false, false) == true)
    Check("Set to instances only, the open world is quiet",
        S({ announce = true, onlyInInstance = true }, true, false) == false)
    Check("And a dungeon is not",
        S({ announce = true, onlyInInstance = true }, true, true) == true)

    -- TWO PRESSES IN A SECOND ARE ONE ANNOUNCE. A taunt that misses is
    -- pressed again straight away, and a tank who spams his own group over it
    -- switches the feature off and never comes back.
    Check("The first press always speaks", T.MaySpeak(100, nil))
    Check("A second one straight after does not",
        T.MaySpeak(100.5, 100) == false)
    Check("Two seconds later it does again", T.MaySpeak(102.5, 100))

    ---------------------------------------------------------------------
    -- The channels are the SAME rules the externals panel uses
    --
    -- Not a copy of them. This is the check that catches somebody growing a
    -- second answer to "which channel am I in" - the one thing the handoff
    -- said not to do before this feature was written.
    ---------------------------------------------------------------------
    ---------------------------------------------------------------------
    -- THE THREE WAYS TO ASK
    --
    -- A button, a keybinding and a macro, and all three have to run the same
    -- line - three ways in is a feature, three implementations is a bug
    -- waiting for one of them to drift.
    ---------------------------------------------------------------------
    Check("The keybinding has something to call",
        type(_G.ZwoelfStuff_TauntAsk) == "function")
    Check("And the game has a name to show for it",
        type(_G.BINDING_NAME_ZWOELFSTUFF_TAUNT_ASK) == "string"
        and type(_G.BINDING_HEADER_ZWOELFSTUFF) == "string")

    -- SIXTEEN CHARACTERS is the limit on a macro name. Over it, the macro is
    -- created under a truncated name, GetMacroIndexByName never finds it
    -- again, and every press of "Make the macro" makes another one.
    Check("The macro name fits in a macro name", #T.MACRO_NAME <= 16,
        T.MACRO_NAME)
    Check("And its body is the command that exists",
        T.MACRO_BODY == "/zs taunt ask", T.MACRO_BODY)

    -- The button is painted by the BAR's painters, under the bar's key names,
    -- exactly as the externals panel is. Renaming one here would leave the
    -- painters quietly using their defaults while the setting looks live.
    local style = T.Style()
    -- The style-key spelling check went with the bars. It compared these
    -- names against ns.BAR_STYLE_KEYS - two renderers, one vocabulary -
    -- and there is no second renderer left to disagree with. The names
    -- themselves are unchanged; nothing can cross-check them any more.

    -- THE ICON PICKER'S PAGING. Pure, and it is the pair of off-by-ones that
    -- only shows up on the last page of four thousand icons.
    Check("The first page starts at one",
        select(1, ns.UI.IconPage(400, 1, 80)) == 1)
    Check("The last page stops at the end",
        select(2, ns.UI.IconPage(400, 5, 80)) == 400)
    Check("A page past the end is clamped to the last one",
        select(3, ns.UI.IconPage(400, 99, 80)) == 5)
    Check("A page before the first is clamped too",
        select(3, ns.UI.IconPage(400, 0, 80)) == 1)
    Check("A short last page does not run past the list",
        select(2, ns.UI.IconPage(85, 2, 80)) == 85,
        tostring(select(2, ns.UI.IconPage(85, 2, 80))))
    Check("An empty list is still one page",
        select(4, ns.UI.IconPage(0, 1, 80)) == 1)

    ---------------------------------------------------------------------
    -- A YES OR NO THAT CANNOT THROW
    --
    -- 12.0 hands back SECRET booleans from some unit queries, and testing one
    -- RAISES. It took the co-tank panel and Edit Mode down on somebody else's
    -- machine while working perfectly here, because WHICH values are withheld
    -- depends on where you are standing.
    ---------------------------------------------------------------------
    Check("A plain true is true", ns.Truth(true, false) == true)
    Check("A plain false is false", ns.Truth(false, true) == false)
    Check("Nothing at all takes the fallback", ns.Truth(nil, true) == true)
    Check("And the fallback is used as given",
        ns.Truth(nil, false) == false)

    ---------------------------------------------------------------------
    -- THE NAME A MACRO CAN ADDRESS
    --
    -- `/cast [@Akui]` reaches nobody when Akui is on another realm, and the
    -- click does nothing at all - no target, no cast, no error. Which is
    -- exactly what the first live test of this looked like.
    ---------------------------------------------------------------------
    local mate
    for _, member in ipairs(ns.Roster()) do
        if not member.isPlayer then mate = member end
    end
    if mate then
        Check("Everybody in the roster has a name a macro can address",
            type(mate.fullName) == "string" and #mate.fullName > 0,
            tostring(mate.fullName))
    else
        Skip("Whether a group-mate keeps its realm", "you are on your own")
    end

    Check("There is one set of channel rules", ns.Chat ~= nil)
    if ns.Chat then
        Check("And the externals panel uses it",
            ns.Externals.ResolveChannel == ns.Chat.ResolveChannel)
        Check("And so does everything that sends",
            ns.Externals.SendingTo == ns.Chat.SendingTo)
    end
end

---------------------------------------------------------------------------
-- THE ADDON CHANNEL, and the bar at the other end of it
--
-- Every rule here is about data from ANOTHER MACHINE, which is the one kind
-- this addon can never inspect while it is happening. So the wire is pure
-- both ways and the answering rules take the world as arguments: a group with
-- two tanks, a message from a version that does not exist yet, a request for
-- a spell your class does not have.
---------------------------------------------------------------------------
local function TestComm()
    local C = ns.Comm
    Check("The addon channel exists", C ~= nil)
    if not C then return end

    -- SIXTEEN CHARACTERS is the limit on a prefix. Over it,
    -- RegisterAddonMessagePrefix refuses and NOTHING is ever received, while
    -- everything on the sending side looks perfectly healthy.
    Check("The prefix fits in a prefix", #C.PREFIX <= 16, C.PREFIX)

    ---------------------------------------------------------------------
    -- The wire
    ---------------------------------------------------------------------
    local wire = C.Encode(C.REQUEST, C.EXTERNAL, 6940)
    local back = C.Decode(wire)
    Check("A request survives the wire",
        back and back.what == C.REQUEST and back.kind == C.EXTERNAL
        and back.spellID == 6940, wire)

    local used = C.Decode(C.Encode(C.USED, C.EXTERNAL, 633, 480))
    Check("A cooldown carries its own length", used and used.value == 480,
        used and tostring(used.value))

    local taunt = C.Decode(C.Encode(C.REQUEST, C.TAUNT))
    Check("A taunt request names no spell",
        taunt and taunt.kind == C.TAUNT and taunt.spellID == nil)

    -- EVERYTHING THAT IS NOT UNDERSTOOD IS DROPPED. This is data somebody
    -- else's machine sent; the only safe thing to do with a shape this
    -- version does not know is nothing.
    Check("A message from a newer version is dropped",
        C.Decode("9|REQ|EXT|6940|0") == nil)
    Check("A message from another addon is dropped",
        C.Decode("hello everybody") == nil)
    Check("An unknown verb is dropped", C.Decode("1|WAT|EXT|6940|0") == nil)
    Check("An unknown kind is dropped", C.Decode("1|REQ|XXX|6940|0") == nil)
    Check("An external with no spell is dropped",
        C.Decode("1|REQ|EXT|0|0") == nil)
    Check("Nothing at all is dropped", C.Decode(nil) == nil)

    -- A version behind sends four fields. Dropping those would make an addon
    -- that only works when both sides updated on the same evening.
    Check("A message without the number still arrives",
        (C.Decode("1|REQ|EXT|6940") or {}).spellID == 6940)

    ---------------------------------------------------------------------
    -- Which channel it goes on
    ---------------------------------------------------------------------
    Check("Alone, an addon message goes nowhere", C.Channel(false) == nil)
    Check("In a party it is PARTY", C.Channel(true, false, false) == "PARTY")
    Check("In a raid it is RAID", C.Channel(true, true, false) == "RAID")
    Check("IN A DUNGEON FROM THE FINDER IT IS INSTANCE_CHAT",
        C.Channel(true, false, true) == "INSTANCE_CHAT")

    Check("The first message goes out", C.MaySend("x", 100, nil))
    Check("The same one again straight after does not",
        C.MaySend("x", 100.2, 100) == false)
end

local function TestAnswers()
    local A, C = ns.Answers, ns.Comm
    Check("The answering side exists", A ~= nil)
    if not A then return end

    ---------------------------------------------------------------------
    -- What a class can be asked for
    ---------------------------------------------------------------------
    local paladin = A.Offers("PALADIN")
    Check("A paladin can be asked for several things", #paladin >= 5,
        tostring(#paladin))

    local hasTaunt = false
    for _, offer in ipairs(paladin) do
        if offer.kind == C.TAUNT then hasTaunt = true end
    end
    Check("And one of them is his taunt", hasTaunt)

    Check("A rogue can be asked for nothing", #A.Offers("ROGUE") == 0)
    Check("With no class there is nothing to offer", #A.Offers(nil) == 0)

    -- DEATH GRIP IS NOT OFFERED. It taunts in Blood only, and a cell that
    -- taunts nothing is worse than no cell: it is a promise to a tank.
    for _, offer in ipairs(A.Offers("DEATHKNIGHT")) do
        Check("Death Grip is not on the answer bar", offer.spellID ~= 49576)
    end

    -- A spell switched off is not built, so nobody can ask for it.
    local fewer = A.Offers("PALADIN", { [6940] = false })
    Check("Switching one off takes it off the bar", #fewer == #paladin - 1)

    ---------------------------------------------------------------------
    -- A GROUPED SLOT REACHES EVERY CLASS THAT HAS A VERSION OF IT
    --
    -- Owner: "und answering muesste das dann fuer jede klasse entsprechend
    -- anders wiedergeben". The request side collapses five spells into one
    -- slot; this side has to expand it again, per class. A mage had NOTHING
    -- on his answer bar before lust existed, so this is also the check that
    -- the expansion happens at all.
    ---------------------------------------------------------------------
    local function Offered(class, spellID, chosen, known)
        for _, offer in ipairs(A.Offers(class, chosen, known)) do
            if offer.spellID == spellID then return true end
        end
        return false
    end

    Check("A mage is offered Time Warp", Offered("MAGE", 80353))
    Check("A hunter is offered Primal Rage", Offered("HUNTER", 264667))
    Check("An evoker is offered Fury of the Aspects", Offered("EVOKER", 390386))
    Check("A warlock is offered Soulstone", Offered("WARLOCK", 20707))
    Check("A death knight is offered Raise Ally", Offered("DEATHKNIGHT", 61999))

    -- Both spellings reach the shaman, and the spellbook decides which one
    -- survives - the same filter that keeps a holy priest from being offered
    -- Pain Suppression. Faction is not something this addon should guess at.
    Check("A shaman is offered both lusts",
        Offered("SHAMAN", 2825) and Offered("SHAMAN", 32182))
    Check("And the spellbook drops the one he has not got",
        Offered("SHAMAN", 2825, nil, function(id) return id ~= 32182 end)
        and not Offered("SHAMAN", 32182, nil,
            function(id) return id ~= 32182 end))

    -- A mage is not handed the shaman's spelling, which is what a careless
    -- expansion - offering every covered spell to everybody - would do.
    Check("A mage is not offered Bloodlust", not Offered("MAGE", 2825))
    Check("A rogue is still offered nothing", #A.Offers("ROGUE") == 0)

    -- OFF AND BACK ON, through the real setter.
    --
    -- Owner, 2026-08-10: "wenn ich den button auf aus schalte [...] kann ich
    -- ihn nicht mehr anschalten." It was written `on and nil or false`, and
    -- that NEVER yields nil - `true and nil` is nil, nil is false, so `or
    -- false` takes over whichever way the switch went. Stored false either
    -- way; off exactly once and never back.
    --
    -- Through SetOffering rather than by writing the table, because the table
    -- was never the part that was broken.
    local keptOffers = A.Config().offers
    A.Config().offers = {}
    Check("A spell nobody has touched is offered", A.Offering(6940))
    A.SetOffering(6940, false)
    Check("Switching it off sticks", A.Offering(6940) == false)
    A.SetOffering(6940, true)
    Check("AND IT CAN BE SWITCHED BACK ON", A.Offering(6940) == true)
    A.Config().offers = keptOffers

    ---------------------------------------------------------------------
    -- Who might ask
    ---------------------------------------------------------------------
    local ROSTER = {
        { name = "Heiler",  class = "PALADIN", role = "HEALER", isPlayer = true },
        { name = "Zwoelf",  class = "DEATHKNIGHT", role = "TANK" },
        { name = "Zweit",   class = "WARRIOR", role = "TANK" },
        { name = "Schaden", class = "MAGE",    role = "DAMAGER" },
    }
    local TANKS = { who = A.WHO_TANKS, rows = 3, rowNames = {} }
    local askers = A.Askers(ROSTER, TANKS)
    Check("Both tanks could ask", #askers == 2, tostring(#askers))
    Check("You are never one of them", (function()
        for _, member in ipairs(askers) do
            if member.isPlayer then return false end
        end
        return true
    end)())
    Check("Nobody tanking means no cells at all", #A.Askers({}, TANKS) == 0)

    -- THE OTHER TWO ANSWERS TO "WHO".
    --
    -- Owner, 2026-08-10: "man kann keine spieler auswaehlen". The automatic
    -- one is right until the group never set its roles, and then it is an
    -- empty bar that explains nothing.
    Check("Everybody means everybody but you",
        #A.Askers(ROSTER, { who = A.WHO_GROUP, rows = 6 }) == 3,
        tostring(#A.Askers(ROSTER, { who = A.WHO_GROUP, rows = 6 })))

    Check("The row count is a ceiling",
        #A.Askers(ROSTER, { who = A.WHO_GROUP, rows = 2 }) == 2)

    local picked = A.Askers(ROSTER, { who = A.WHO_CHOSEN, rows = 3,
        rowNames = { "Schaden", "Zwoelf" } })
    Check("Picked people come in the order they were picked",
        #picked == 2 and picked[1].name == "Schaden"
            and picked[2].name == "Zwoelf",
        #picked > 0 and picked[1].name or "none")

    Check("Naming somebody who left leaves no row",
        #A.Askers(ROSTER, { who = A.WHO_CHOSEN, rows = 3,
            rowNames = { "Weg" } }) == 0)

    -- Two rows aimed at one person light up together and answer nothing
    -- extra, so it is one row.
    Check("Naming the same person twice is ONE row",
        #A.Askers(ROSTER, { who = A.WHO_CHOSEN, rows = 3,
            rowNames = { "Zwoelf", "Zwoelf" } }) == 1)

    Check("You cannot pick yourself",
        #A.Askers(ROSTER, { who = A.WHO_CHOSEN, rows = 3,
            rowNames = { "Heiler" } }) == 0)

    ---------------------------------------------------------------------
    -- ONLY WHAT YOU ACTUALLY HAVE
    --
    -- A class list is not a spellbook: Pain Suppression is on the priest list
    -- and a holy priest cannot cast it.
    ---------------------------------------------------------------------
    local full = A.Offers("PRIEST")
    local half = A.Offers("PRIEST", nil, function(id) return id ~= 33206 end)
    Check("A spell you do not have is not offered", #half == #full - 1,
        #half .. " of " .. #full)
    Check("And it says how many it took out", A.hidden == 1,
        tostring(A.hidden))

    -- THE FILTER MUST NOT BE ABLE TO EMPTY THE BAR. The spellbook is not
    -- readable for a moment at every login and every talent swap, and an
    -- empty bar for a paladin is a worse wrong answer than one extra cell.
    local none = A.Offers("PALADIN", nil, function() return false end)
    Check("A filter that removes EVERYTHING is refused", #none == #paladin,
        tostring(#none))

    ---------------------------------------------------------------------
    -- THE MACRO - the one string the whole feature is
    --
    -- Three separate reasons for a click that cast nothing have now been
    -- found by reading code, and every one of them is a wrong string here.
    -- None of them said anything on screen.
    ---------------------------------------------------------------------
    local tank = { name = "Akui", fullName = "Akui-Gilneas", unit = "party2" }

    Check("An external is cast on whoever asked",
        A.Macro(C.EXTERNAL, "Lay on Hands", tank)
            == "/cast [@Akui-Gilneas] Lay on Hands",
        tostring(A.Macro(C.EXTERNAL, "Lay on Hands", tank)))

    -- A TAUNT GOES ON WHAT HE IS FIGHTING. Not on him - that is a taunt on a
    -- friendly player, which does nothing and says nothing - and not on your
    -- own target either, which in a pull with adds is a different creature.
    -- Owner: "bei spott müsste das target von akui anvisiert werden".
    Check("A taunt is cast on the ASKER'S target",
        A.Macro(C.TAUNT, "Dark Command", tank)
            == "/cast [@party2target,harm][] Dark Command",
        tostring(A.Macro(C.TAUNT, "Dark Command", tank)))

    Check("And it never names the tank himself",
        A.Macro(C.TAUNT, "Dark Command", tank):find("Akui") == nil)

    -- The empty clause: if what he is on cannot be taunted, your own target
    -- is used rather than the press doing nothing at all.
    Check("A taunt falls back to your own target",
        A.Macro(C.TAUNT, "Dark Command", tank):find("[]", 1, true) ~= nil)

    -- Without a token there is no way to say "his target" at all.
    Check("With no unit to reach him by, it is your own target",
        A.Macro(C.TAUNT, "Dark Command", { name = "Akui" })
            == "/cast Dark Command")

    Check("The realm travels with the name",
        A.Macro(C.EXTERNAL, "Ironbark", tank):find("Akui-Gilneas", 1, true)
            ~= nil)

    Check("Taking the target as well is a second line",
        A.Macro(C.EXTERNAL, "Ironbark", tank, true)
            == "/target Akui-Gilneas\n/cast [@Akui-Gilneas] Ironbark")

    -- And with the switch on it takes HIS target, not him: after a swap you
    -- are the one holding that creature, so being on it is the point.
    Check("With the switch on, a taunt takes what he is fighting",
        A.Macro(C.TAUNT, "Taunt", tank, true)
            == "/target party2target\n/cast [@party2target,harm][] Taunt",
        tostring(A.Macro(C.TAUNT, "Taunt", tank, true)))

    -- A stand-in cell must cast NOTHING: there is nobody called "Tank".
    Check("The stand-in cell gets no macro at all",
        A.Macro(C.EXTERNAL, "Taunt", { name = "Tank", preview = true })
            == nil)

    -- "Spell 633" is a fine thing to draw and a catastrophic thing to cast.
    Check("A spell the client cannot name gets no macro",
        A.Macro(C.EXTERNAL, nil, tank) == nil)
    Check("Nor an empty one", A.Macro(C.EXTERNAL, "", tank) == nil)

    ---------------------------------------------------------------------
    -- THE KEY IN THE CORNER
    ---------------------------------------------------------------------
    Check("Each cell has its own binding",
        A.BindingName(2) == "CLICK ZwoelfStuffAnswer2:LeftButton",
        A.BindingName(2))
    Check("And the game knows what to call it",
        _G["BINDING_NAME_" .. A.BindingName(2)] ~= nil)
    Check("SHIFT-F1 fits in a corner", A.ShortKey("SHIFT-F1") == "sF1",
        tostring(A.ShortKey("SHIFT-F1")))
    Check("So does a mouse button", A.ShortKey("BUTTON4") == "M4",
        tostring(A.ShortKey("BUTTON4")))
    Check("No key is no text", A.ShortKey(nil) == nil)
    Check("One shortener, read by both panels",
        A.ShortKey == ns.ShortKey and ns.Externals.Key ~= nil)
    Check("Eight cells can carry one", A.KEYS == 8, tostring(A.KEYS))

    -- THE KEY YOU PRESS, AS THE GAME NAMES IT. A modifier held down is a
    -- prefix; a modifier pressed ALONE is half a binding, and taking it as a
    -- whole one would make every combination impossible to enter - the shift
    -- always lands first.
    Check("A plain key is itself", ns.UI.Chord("F9") == "F9")
    Check("A modifier on its own is not a key", ns.UI.Chord("LSHIFT") == nil)
    Check("Nor is nothing at all", ns.UI.Chord(nil) == nil)

    ---------------------------------------------------------------------
    -- SETTING A KEY IS A MODE, NOT A LIST
    --
    -- Owner, 2026-08-10, having been handed eight rows: "du machst da einen
    -- keybind button, dann grauen die buttons aus und du kannst auf den
    -- button klicken und einen key belegen." A key belongs to a place on the
    -- screen, and the screen is right there.
    ---------------------------------------------------------------------
    Check("There is a key mode", ns.Keys ~= nil)
    -- NOT DURING A FIGHT. Every line below moves real bindings, and the game
    -- refuses that in combat - Keys.Bind answers nil, SetActive stands down,
    -- and four checks went red on a healthy client (his paste). A test that
    -- can only pass out of combat says so instead of failing.
    if ns.Keys and InCombatLockdown and InCombatLockdown() then
        Skip("Binding a key to a place",
            "in combat - the game does not allow a key to move during a fight")
    elseif ns.Keys then
        local binding = ns.Externals.BindingName(1)
        local kept = ns.Keys.Current(binding)
        ns.Keys.Clear(binding)

        Check("A key can be bound to a place", ns.Keys.Bind(binding, "F9")
            and ns.Keys.Current(binding) == "F9",
            tostring(ns.Keys.Current(binding)))

        -- One key, one command. Announced when it is taken from something
        -- else, never left on both.
        SetBinding("F9", A.BindingName(1))
        ns.Keys.Bind(binding, "F9")
        Check("One key answers to one thing", ns.Keys.Current(A.BindingName(1))
            == nil and ns.Keys.Current(binding) == "F9")

        ns.Keys.Clear(binding)
        Check("And it can be taken off again",
            ns.Keys.Current(binding) == nil)

        -- THERE IS A WAY OUT THAT YOU CAN SEE. Owner, 2026-08-10: "man kommt
        -- nicht mehr aus dem modus." Escape was handled on the SQUARE, and a
        -- square only listens while it is waiting for a key - so standing in
        -- the mode without having clicked one, nothing was listening at all.
        ns.Keys:SetActive(true)
        Check("The key mode opens", ns.Keys.active)
        Check("And its window is one the game closes on Escape", (function()
            for _, name in ipairs(UISpecialFrames or {}) do
                if name == "ZwoelfStuffKeysBanner" then return true end
            end
            return false
        end)())
        ns.Keys:SetActive(false)
        Check("And it closes again", ns.Keys.active == false)

        if kept then ns.Keys.Bind(binding, kept) end
    end

    ---------------------------------------------------------------------
    -- THE QUICK MENU ON THE BAR
    --
    -- Owner, 2026-08-10: "kann man das als button an die answer bar hauen,
    -- damit man das dort schnell einstellen kann?" - and the reason is WHEN
    -- this decision happens: the group forms, and the options window is on a
    -- different part of the screen from the bar you are looking at.
    ---------------------------------------------------------------------
    local keptWho, keptRows = A.Config().who, A.Config().rowNames
    local keptCount = A.Config().rows
    A.Config().rowNames = {}

    A.SetWho(A.WHO_GROUP)
    Check("The menu switches the mode", A.Config().who == A.WHO_GROUP)

    Check("Nobody is picked to begin with", A.Picked("Zwoelf") == false)
    A.TogglePicked("Zwoelf")
    Check("Picking somebody picks them", A.Picked("Zwoelf"))
    -- Picking a person and then not being in the mode that reads the list
    -- would be a click that did nothing.
    Check("And puts you in the mode that reads it",
        A.Config().who == A.WHO_CHOSEN)
    A.TogglePicked("Zwoelf")
    Check("Clicking again takes them off", A.Picked("Zwoelf") == false)

    -- More names than rows: the extra one is REFUSED out loud rather than
    -- dropped, which would read as a click that never registered.
    A.Config().rows = 1
    A.TogglePicked("Einer")
    A.TogglePicked("Zweiter")
    Check("A name with no row left is not silently swallowed",
        A.Picked("Einer") and A.Picked("Zweiter") == false)

    local items = A.MenuItems()
    Check("The menu offers the modes and the people", #items >= 3,
        tostring(#items))

    A.Config().rowNames, A.Config().who = keptRows, keptWho
    A.Config().rows = keptCount

    ---------------------------------------------------------------------
    -- Which cell answers which request
    --
    -- The rule the whole feature turns on: the right one lights up and the
    -- others do not.
    ---------------------------------------------------------------------
    local cell = { who = "Zwoelf", kind = C.EXTERNAL, spellID = 6940 }
    Check("The cell for that spell on that tank matches",
        A.Matches(cell, { from = "Zwoelf", kind = C.EXTERNAL, spellID = 6940 }))
    Check("The same spell for the OTHER tank does not",
        A.Matches(cell, { from = "Zweit", kind = C.EXTERNAL, spellID = 6940 })
            == false)
    Check("A different spell for the same tank does not",
        A.Matches(cell, { from = "Zwoelf", kind = C.EXTERNAL, spellID = 1022 })
            == false)

    -- A taunt request names no spell: any taunt of yours answers it.
    local tauntCell = { who = "Zwoelf", kind = C.TAUNT, spellID = 355 }
    Check("Any taunt answers a taunt request",
        A.Matches(tauntCell, { from = "Zwoelf", kind = C.TAUNT }))

    ---------------------------------------------------------------------
    -- What is waiting, and for how long
    ---------------------------------------------------------------------
    local list = {}
    A.Remember(list, { fromShort = "Zwoelf", kind = C.EXTERNAL, spellID = 6940 }, 100)
    Check("A request is remembered", #list == 1)

    A.Remember(list, { fromShort = "Zwoelf", kind = C.EXTERNAL, spellID = 6940 }, 101)
    Check("Asking twice is ONE row, not two", #list == 1)
    Check("And the clock restarts", list[1].at == 101, tostring(list[1].at))

    A.Remember(list, { fromShort = "Zweit", kind = C.EXTERNAL, spellID = 6940 }, 101)
    Check("Two people asking is two rows", #list == 2)

    Check("A cell knows the one that is its own",
        A.Waiting(list, cell, 102, 8) ~= nil)
    Check("And ignores one that is not",
        A.Waiting(list, { who = "Nobody", kind = C.EXTERNAL, spellID = 6940 },
            102, 8) == nil)

    A.Prune(list, 130, 8)
    Check("An old request stops shouting", #list == 0)
end

---------------------------------------------------------------------------
-- THE PANEL MOVERS
--
-- Owner, 2026-08-09, with a screenshot of the externals mover: "hier fehlt
-- noch das zahnrad fuer einstellungen und das lock item!" A bar's mover had
-- both and a panel's had neither, which is the sort of gap nobody notices
-- while writing the second one.
--
-- Skipped rather than failed when edit mode has never been opened: the movers
-- are made on the first refresh, and "not built yet" is not "built wrong".
---------------------------------------------------------------------------
local function TestPanelMovers()
    ---------------------------------------------------------------------
    -- EDIT MODE GIVES BACK WHAT IT TOOK
    --
    -- Owner, 2026-08-10, in one breath: "wenn ich aus dem addon in den edit
    -- mode gehe und den edit mode verlasse, sollte das addon wieder aufgehen"
    -- and "wenn ich nur rechtsklick auf dem minimap icon mache [...] kein
    -- addon öffnen". Two sentences, one rule - a window it hid, it puts back;
    -- a window that was never open stays shut. Which makes the minimap and
    -- /zs unlock need no case of their own, and that is the point.
    ---------------------------------------------------------------------
    local wasOpen = ns.Options.frame and ns.Options.frame:IsShown()
    if ns.Options.frame then ns.Options.frame:Hide() end

    ns.EditMode:SetUnlocked(true)
    Check("Coming in from the minimap, there is nothing to hand back",
        ns.EditMode.cameFromWindow == false)
    ns.EditMode:SetUnlocked(false)
    Check("And leaving opens nothing",
        not (ns.Options.frame and ns.Options.frame:IsShown()))

    if wasOpen and ns.Options.frame then ns.Options.frame:Show() end

    ---------------------------------------------------------------------
    -- THE TOOL PANEL, BACK - the screen half of it. It went out whole with
    -- the cooldown bars and the owner noticed: "im edit mode fehlen die
    -- tools, wie grid groessen anpassen, snapping und und." Five screen
    -- settings kept their defaults and their reader the whole time; this
    -- is the check that they have their CONTROL again, and that every
    -- named setter the rows call really reaches the profile.
    ---------------------------------------------------------------------
    local panel = ns.EditMode.toolsPanel
    Check("Unlocking builds the tool panel", panel ~= nil)
    if panel then
        Check("with the five screen settings and the grid switch on it",
            #panel.rows == 6, tostring(#panel.rows))
    end

    local prefs = ns.db.editMode or {}
    local keptStep, keptSnap = prefs.gridStep, prefs.snapToGrid
    local keptCatch, keptDim = prefs.snapDistance, prefs.dim
    local keptCoords = prefs.showCoords

    ns.EditMode:SetGridStep(24)
    Check("Grid step reaches the profile", prefs.gridStep == 24,
        tostring(prefs.gridStep))
    ns.EditMode:SetSnapToGrid(false)
    Check("Snap-to-grid reaches the profile", prefs.snapToGrid == false)
    ns.EditMode:SetSnapCatch(7)
    Check("The snap catch reaches the profile", prefs.snapDistance == 7)
    ns.EditMode:SetDim(0.4)
    Check("The dim reaches the profile", prefs.dim == 0.4)
    ns.EditMode:SetCoordsShown(true)
    Check("Coordinates reach the profile", prefs.showCoords == true)

    prefs.gridStep, prefs.snapToGrid = keptStep, keptSnap
    prefs.snapDistance, prefs.dim = keptCatch, keptDim
    prefs.showCoords = keptCoords

    if not ns.EditMode.PanelMovers then
        Check("Edit mode can name its panel movers", false)
        return
    end

    local movers = ns.EditMode:PanelMovers()
    local any = false

    -- FOUR PANELS ARE PLACED IN EDIT MODE, and every one of them has to be in
    -- the list that OnUpdate drags. The taunt button shipped in 4.64.0 with a
    -- mover, a cog and a padlock and no way to move it, because the drag was
    -- a hand-written pair of lines beside a hand-written list. They are one
    -- list now, and this is the check that says so out loud.
    local named = 0
    for _ in pairs(movers) do named = named + 1 end
    Check("Every placed panel is in the mover list", named >= 4,
        tostring(named))

    for name, mover in pairs(movers) do
        any = true
        Check("The " .. name .. " mover has a cog", mover.cog ~= nil)
        Check("The " .. name .. " mover has a padlock", mover.lock ~= nil)
        Check("And it knows how to draw the padlock",
            type(mover.RefreshLock) == "function")
        Check("And it carries what its cog needs",
            mover.spec ~= nil and mover.spec.page ~= nil
            and mover.spec.module ~= nil and type(mover.spec.apply) == "function")

        -- EVERY FIELD A ROW OWES, and the reason this is a loop rather than
        -- four lines about one panel: a surface is a ROW in PANEL_MOVERS now,
        -- so adding a sixth is adding a row - and a row missing one field
        -- fails in its own quiet way. No label draws a nameless box; no
        -- origin means the coordinates read 0,0 for ever; no config means the
        -- padlock cannot find `pinned` and every drag goes through.
        Check("The " .. name .. " row says what to call it",
            type(mover.spec.label) == "string" and mover.spec.label ~= "",
            tostring(mover.spec and mover.spec.label))
        Check("The " .. name .. " row can say where it is",
            type(mover.spec.origin) == "function"
            and select(1, mover.spec.origin()) ~= nil)
        Check("The " .. name .. " row can find its own settings",
            type(mover.spec.config) == "function"
            and mover.spec.config() ~= nil)

        -- THE TWO KEYS HAVE TO NAME REAL THINGS. Both are strings handed to
        -- something that looks them up and quietly does nothing when it does
        -- not find them: Options:Open walks its page list and falls off the
        -- end, Modules:Set returns. A cog entry that silently does nothing is
        -- indistinguishable from a cog entry that is broken.
        if mover.spec then
            local page = false
            for _, entry in ipairs(ns.Options.PAGES or {}) do
                if entry.key == mover.spec.page then page = true break end
            end
            Check("Its cog opens a page that exists", page,
                tostring(mover.spec.page))
            Check("And names a module that exists",
                ns.Modules:Get(mover.spec.module) ~= nil,
                tostring(mover.spec.module))
        end

        -- PINNED MEANS IT DOES NOT MOVE, and that is the whole feature. Run
        -- through the real handler rather than restating the rule: a test that
        -- re-implements what it is checking passes the day the rule changes.
        --
        -- The same block runs over the REMINDER movers below, because "it has
        -- a padlock" and "the padlock does something" are two questions and
        -- the reminders had neither answer for five days.
        local cfg = mover.spec.config()
        if cfg then
            local was = cfg.pinned
            local start = mover:GetScript("OnDragStart")

            cfg.pinned = true
            mover.grab = nil
            if start then start(mover) end
            Check("A pinned " .. name .. " panel refuses to be dragged",
                mover.grab == nil)

            cfg.pinned = false
            mover.grab = nil
            if start then start(mover) end
            Check("An unpinned one takes the drag", mover.grab ~= nil)

            -- Never left holding one. Edit mode's OnUpdate reads this every
            -- frame, and a grab nobody asked for would move his panel.
            mover.grab = nil
            cfg.pinned = was
            mover:RefreshLock()
        end
    end

    ---------------------------------------------------------------------
    -- AND THE REMINDERS, WHICH ARE MOVERS TOO
    --
    -- Owner, with a screenshot of one: "mein reminder hat kein zahnrad oder
    -- lock". He had said the same sentence about the externals mover five
    -- days earlier - and the answer then went into the PANEL builder, which
    -- the reminders do not use. Nothing could see the difference, because
    -- the reminder movers were a local nothing could reach.
    ---------------------------------------------------------------------
    local reminders = ns.EditMode.ReminderMovers
        and ns.EditMode:ReminderMovers() or {}

    -- SAY SO WHEN THERE IS NOTHING TO LOOK AT. A loop over an empty list is
    -- a suite that reports green about nothing, and that is exactly how this
    -- gap survived: nothing could reach the reminder movers, so nothing said
    -- they were missing anything.
    if #reminders == 0 then
        Skip("Whether the reminder movers carry a cog and a padlock",
            "no reminder is placed, so no mover was built")
    else
        for index, mover in ipairs(reminders) do
            local who = "reminder " .. index
            Check("The " .. who .. " mover has a cog", mover.cog ~= nil)
            Check("The " .. who .. " mover has a padlock", mover.lock ~= nil)
            Check("And it knows how to draw the padlock",
                type(mover.RefreshLock) == "function")
            Check("And it carries what its cog needs",
                mover.spec ~= nil and mover.spec.page ~= nil
                and type(mover.spec.apply) == "function"
                and type(mover.spec.config) == "function")

            -- THE PADLOCK HAS TO DO SOMETHING. It is not enough that it is
            -- drawn: the reminder drag never read `pinned` at all until it
            -- was given one, so a padlock there would have been a picture.
            local cfg = mover.spec and mover.spec.config()
            if cfg then
                local was = cfg.pinned
                local start = mover:GetScript("OnDragStart")

                cfg.pinned = true
                mover.grab = nil
                if start then start(mover) end
                Check("A pinned " .. who .. " refuses to be dragged",
                    mover.grab == nil)

                cfg.pinned = false
                mover.grab = nil
                if start then start(mover) end
                Check("An unpinned " .. who .. " takes the drag",
                    mover.grab ~= nil)

                mover.grab = nil
                cfg.pinned = was
                mover:RefreshLock()
            end
        end
    end

    ---------------------------------------------------------------------
    -- AND THE COOLDOWN BARS, WHICH ARE MOVERS TOO
    --
    -- THE THIRD SURFACE, and the first two both shipped without a cog and a
    -- padlock for the same reason: the builder that grew the tools was not
    -- the builder that made the box. The owner said "mein reminder hat kein
    -- zahnrad oder lock" five days after saying it about the externals mover.
    --
    -- So the bars get the same walk on the day they get their movers, rather
    -- than on the day he photographs one.
    ---------------------------------------------------------------------
    local barMovers = ns.EditMode.BarMovers and ns.EditMode:BarMovers() or {}

    if #barMovers == 0 then
        Skip("Whether the bar movers carry a cog and a padlock",
            "no bar is on screen, so no mover was built")
    else
        for index, mover in ipairs(barMovers) do
            local who = "bar " .. index
            Check("The " .. who .. " mover has a cog", mover.cog ~= nil)
            Check("The " .. who .. " mover has a padlock", mover.lock ~= nil)
            Check("And it knows how to draw the padlock",
                type(mover.RefreshLock) == "function")
            Check("And it carries what its cog needs",
                mover.spec ~= nil and mover.spec.page ~= nil
                and type(mover.spec.apply) == "function"
                and type(mover.spec.config) == "function")

            -- IT HAS TO KNOW WHICH BAR IT IS FOR, and that is the one thing
            -- these movers can get wrong that the other two cannot: they are
            -- pooled by position and the bars are sorted by id, so a mover
            -- that closed over the id it was built with would start dragging
            -- somebody else's bar the moment a bar above it was deleted.
            Check("The " .. who .. " mover names the bar it drags",
                mover.dkBarID ~= nil and mover.spec.config() ~= nil,
                tostring(mover.dkBarID))

            local cfg = mover.spec and mover.spec.config()
            if cfg then
                Check("And its settings are the bar with that id",
                    cfg.id == mover.dkBarID,
                    string.format("%s vs %s", tostring(cfg.id),
                        tostring(mover.dkBarID)))

                local was = cfg.pinned
                local start = mover:GetScript("OnDragStart")

                cfg.pinned = true
                mover.grab = nil
                if start then start(mover) end
                Check("A pinned " .. who .. " refuses to be dragged",
                    mover.grab == nil)

                cfg.pinned = false
                mover.grab = nil
                if start then start(mover) end
                Check("An unpinned " .. who .. " takes the drag",
                    mover.grab ~= nil)

                mover.grab = nil
                cfg.pinned = was
                mover:RefreshLock()
            end
        end
    end

    if not any then
        Skip("Whether the panel movers carry a cog and a padlock",
            "edit mode has not been opened this session")
    end
end

---------------------------------------------------------------------------
-- The language
--
-- WHAT CAN ACTUALLY GO WRONG HERE, because it is not what it looks like. A
-- missing translation is harmless by design - the key IS the English string,
-- so it comes back as itself. The three things that are NOT harmless:
--
--   a key that is in a translation and not in enUS   a word nothing asks for.
--                                                    It is a typo, and it
--                                                    shows as English forever
--                                                    while looking translated
--                                                    in the file.
--   a translation that loses a placeholder            "%d features" becoming
--                                                    "Funktionen" drops the
--                                                    number silently, or
--                                                    throws inside format.
--   a lookup at FILE SCOPE                            answered in English
--                                                    before the profile is
--                                                    open, then frozen for
--                                                    the session.
---------------------------------------------------------------------------
local function TestLocale()
    local Locale = ns.Locale
    local L = ns.L

    Check("There is a language engine", Locale ~= nil and L ~= nil)
    if not Locale then return end

    ---------------------------------------------------------------------
    -- Which language, given what
    ---------------------------------------------------------------------
    Check("A chosen language wins over the client",
        Locale.Resolve("frFR", "deDE") == "frFR")
    Check("auto follows the client",
        Locale.Resolve("auto", "deDE") == "deDE")
    Check("Nothing chosen follows the client",
        Locale.Resolve(nil, "ruRU") == "ruRU")
    -- The British client is the American strings, and nobody ships a separate
    -- enGB. Without this line every British player gets the raw keys back -
    -- which happens to be English, so it works by luck rather than by rule.
    Check("enGB is enUS", Locale.Resolve("auto", "enGB") == "enUS")
    Check("A language we do not ship falls back to English",
        Locale.Resolve("xxXX", "xxXX") == "enUS")
    Check("No client at all falls back to English",
        Locale.Resolve(nil, nil) == "enUS")

    ---------------------------------------------------------------------
    -- The tables
    ---------------------------------------------------------------------
    local master = Locale.TABLES.enUS
    Check("There is a master list", type(master) == "table")

    local masterCount = 0
    for _ in pairs(master or {}) do masterCount = masterCount + 1 end
    Check("The master list has something in it", masterCount > 50,
        tostring(masterCount) .. " strings")

    for _, entry in ipairs(Locale.LANGUAGES) do
        Check("Language " .. entry.code .. " has a table",
            type(Locale.TABLES[entry.code]) == "table")
        -- IN ITS OWN LANGUAGE. Somebody looking for their language in a list
        -- is looking for the word they use for it, which may not be a word
        -- they would recognise in English.
        Check("Language " .. entry.code .. " names itself",
            type(entry.native) == "string" and entry.native ~= "")
    end

    -- A KEY THAT IS NOT IN THE MASTER. See the header: it is a typo that
    -- cannot be seen, because the screen shows English and the file shows a
    -- translation.
    local stray, strayIn
    for _, entry in ipairs(Locale.LANGUAGES) do
        if entry.code ~= "enUS" then
            for key in pairs(Locale.TABLES[entry.code] or {}) do
                if master[key] == nil then
                    stray, strayIn = key, entry.code
                end
            end
        end
    end
    Check("Every translated key is one the addon asks for", stray == nil,
        stray and (strayIn .. ": " .. stray) or nil)

    -- PLACEHOLDERS SURVIVE TRANSLATION. %d and %s carry the numbers, and a
    -- translation that drops one prints a sentence with the fact missing -
    -- or throws inside string.format, which takes the page down.
    local function Marks(text)
        local count = 0
        for _ in tostring(text):gmatch("%%[%a]") do count = count + 1 end
        return count
    end

    local lost, lostIn
    for _, entry in ipairs(Locale.LANGUAGES) do
        for key, value in pairs(Locale.TABLES[entry.code] or {}) do
            if type(value) == "string" and Marks(key) ~= Marks(value) then
                lost, lostIn = key, entry.code
            end
        end
    end
    Check("No translation loses a placeholder", lost == nil,
        lost and (lostIn .. ": " .. lost) or nil)

    ---------------------------------------------------------------------
    -- The lookup
    ---------------------------------------------------------------------
    local was = ns.db and ns.db.language
    local restore = Locale.active

    Locale:Use("enUS")
    Check("English answers with the key itself", L["Ready check"] == "Ready check")
    Check("A string nobody has translated answers with itself",
        L["a sentence that is in no table anywhere"]
            == "a sentence that is in no table anywhere")

    Locale:Use("deDE")
    Check("A translated string comes back translated",
        L["Settings"] == "Einstellungen")
    Check("An untranslated one still answers in English",
        L["a sentence that is in no table anywhere"]
            == "a sentence that is in no table anywhere")

    -- The formatting door. A translation with a broken placeholder must not
    -- take the caller down with it - see the pcall in Locale.lua.
    Check("A formatted string fills in", L("%d of %d answered", 3, 5)
        == "3 von 5 haben geantwortet")
    Check("A formatted string with no arguments is the string",
        L("Settings") == "Einstellungen")

    Locale:Use(restore)
    if ns.db then ns.db.language = was end

    -- READ-ONLY. A translation assigned at runtime would put one language's
    -- word into every later session of another one, and it would be found
    -- weeks later.
    Check("The table refuses to be written to",
        not pcall(function() ns.L["Ready check"] = "nope" end))

    ---------------------------------------------------------------------
    -- Coverage, which the Settings list and /zs loca both print
    ---------------------------------------------------------------------
    local done, total = Locale.Coverage("enUS")
    Check("English is complete by definition", done == total and total > 0)

    local germanDone, germanTotal = Locale.Coverage("deDE")
    -- The file says German is finished. Held to it here, because "complete"
    -- in a comment is a claim and this is the same claim as a number.
    Check("German is complete", germanDone == germanTotal,
        string.format("%d of %d", germanDone, germanTotal))

    for _, entry in ipairs(Locale.LANGUAGES) do
        local hit, all = Locale.Coverage(entry.code)
        Check("Coverage for " .. entry.code .. " is a real fraction",
            hit >= 0 and hit <= all and all == masterCount)
    end

    Check("What is missing is listed",
        #Locale.Missing("koKR") == masterCount - select(1, Locale.Coverage("koKR")))

    ---------------------------------------------------------------------
    -- The window's own strings resolve
    --
    -- Every page title and every module name goes through L when it is drawn.
    -- A title that is not a string would come back as a table address on a
    -- button, which is the sort of thing that only shows up in a screenshot.
    ---------------------------------------------------------------------
    local titles = true
    for _, page in ipairs(ns.Options.PAGES) do
        if type(L[page.title]) ~= "string" or L[page.title] == "" then
            titles = false
        end
    end
    Check("Every page title resolves to a string", titles)

    local moduleNames = true
    for _, entry in ipairs(ns.Modules:All()) do
        if type(L[entry.title]) ~= "string" or type(L[entry.blurb]) ~= "string" then
            moduleNames = false
        end
    end
    Check("Every module name and blurb resolves to a string", moduleNames)
end

---------------------------------------------------------------------------
-- The raid bar
--
-- WHAT THE DESKTOP CAN AND CANNOT SEE HERE, and the split decides the whole
-- suite. It cannot press a secure button, and it cannot know whether the game
-- accepted the macro. What it CAN check is the two things that actually break
-- a marks bar: the text of the macro each place is given, and the arithmetic
-- that decides which place is which.
--
-- A macro with the wrong word in it is a button that does nothing in a raid,
-- silently, for one language's players only. That is the failure this suite
-- exists for.
---------------------------------------------------------------------------
local function TestRaidBar()
    local RaidBar = ns.RaidBar
    Check("There is a raid bar", RaidBar ~= nil)
    if not RaidBar then return end

    ---------------------------------------------------------------------
    -- What can go on it
    ---------------------------------------------------------------------
    local keys, kinds = {}, {}
    local duplicate, artless, nameless
    for _, entry in ipairs(RaidBar.ACTIONS) do
        if keys[entry.key] then duplicate = entry.key end
        keys[entry.key] = true
        kinds[entry.kind] = (kinds[entry.kind] or 0) + 1
        -- EVERY BUTTON IS A PICTURE. A place with no art is a black square on
        -- the bar, and the picker beside it is a list of blank rows.
        -- A PATH OR A FILE ID, and both are real. The pull timer is drawn
        -- with 134376, the number BigWigs uses for its own timer bars; a
        -- check that insisted on a string would go red against correct code.
        -- Anything else - a table, a boolean, a nil - is a place that draws
        -- nothing.
        local art = entry.texture or entry.atlas
        if not (type(art) == "string" or type(art) == "number") then
            artless = entry.key
        end
        if type(entry.label) ~= "string" or entry.label == "" then
            nameless = entry.key
        end
    end

    Check("Every button has its own key", duplicate == nil, duplicate)
    Check("Every button has a picture", artless == nil, artless)
    Check("Every button has a name", nameless == nil, nameless)

    Check("There are eight markers and a clear", kinds.marker == 9,
        tostring(kinds.marker))
    Check("There are eight world markers and a clear", kinds.worldmarker == 9,
        tostring(kinds.worldmarker))
    Check("There are four pings", kinds.ping == 4, tostring(kinds.ping))
    Check("Three buttons run in the addon", kinds.call == 3,
        tostring(kinds.call))

    ---------------------------------------------------------------------
    -- WHAT A PRESS SENDS
    --
    -- The slash commands are the CLIENT'S, because they are translated on
    -- some clients - MRT carries a special case for exactly the four
    -- languages where "/wm" is not "/wm". Passed in here rather than read,
    -- so both halves are executed.
    ---------------------------------------------------------------------
    Check("A marker toggles rather than sets",
        RaidBar.MarkerMacro(3, false, "/tm") == "/tm !3")
    Check("The clear button clears every marker",
        RaidBar.MarkerMacro(0, true, "/tm") == "/tm 0")
    Check("A marker macro follows a translated command",
        RaidBar.MarkerMacro(5, false, "/marcador") == "/marcador !5")

    Check("A world marker is placed",
        RaidBar.WorldMarkerMacro(2, false, "/wm", "/cwm") == "/wm 2")
    Check("A world marker is taken away",
        RaidBar.WorldMarkerMacro(2, true, "/wm", "/cwm"):find("/cwm") == 1)
    Check("The world clear takes them all",
        RaidBar.WorldMarkerMacro(0, false, "/wm", "/cwm"):find("/cwm") == 1)

    Check("A ping is aimed at the target",
        RaidBar.PingMacro("attack", "/ping", "Attack")
            == "/ping [@target] Attack")

    ---------------------------------------------------------------------
    -- The lattice, which is now shared with the externals panel
    ---------------------------------------------------------------------
    local sameAsExternals = true
    for index = 1, 12 do
        local ax, ay = ns.LatticeCell(index, 2, 6, false)
        local bx, by = ns.Externals.Cell(index, 2, 6, false)
        if ax ~= bx or ay ~= by then sameAsExternals = false end
    end
    Check("Both panels place a place the same way", sameAsExternals)

    local x, y = ns.LatticeCell(7, 2, 6, false)
    Check("The seventh of six across starts the second row", x == 0 and y == 1)
    x, y = ns.LatticeCell(3, 2, 6, true)
    Check("Running down fills a column first", x == 1 and y == 0)

    local wide, tall = ns.LatticeExtent(3, 2, 6, false)
    Check("Three of twelve is three wide and one tall", wide == 3 and tall == 1)
    Check("Nothing shown takes no room",
        select(1, ns.LatticeExtent(0, 2, 6, false)) == 0)

    ---------------------------------------------------------------------
    -- The bar's own settings, on a copy of the profile's
    --
    -- Put back at the end. This is the one part of the suite that writes, and
    -- it writes to the live raid bar - so it is wrapped the way the module
    -- switch test is.
    ---------------------------------------------------------------------
    if not ns.db then
        Skip("The raid bar's settings", "no profile open")
        return
    end

    local kept = ns.db.raidBar
    local ok, err = pcall(function()
        ns.db.raidBar = nil

        local cfg = RaidBar.Config()
        Check("A fresh bar is seeded", cfg.cells[1] ~= nil and cfg.seeded)
        Check("The seed is a marks bar", cfg.cells[1] == "mark1"
            and cfg.cells[9] == "markclear")

        -- SEEDED ONCE. A migration that runs twice puts back the place
        -- somebody has just emptied, and it does it at every login.
        RaidBar.ClearSlot(1)
        RaidBar.Config()
        Check("Emptying a place survives the next read",
            RaidBar.Config().cells[1] == nil)

        RaidBar.SetSlot(1, "mark1")
        Check("A button goes where it is put",
            RaidBar.ActionAt(1) == "mark1")

        -- ONE BUTTON, ONE PLACE. Two Skulls on a bar is two places doing one
        -- job and a key bound to whichever of them you did not mean.
        RaidBar.SetSlot(4, "mark1")
        Check("Putting a button somewhere else moves it",
            RaidBar.ActionAt(1) == nil and RaidBar.ActionAt(4) == "mark1")

        Check("An unknown button is refused",
            (RaidBar.Pick("nonesuch") == nil) and not RaidBar.IsPicked("nonesuch"))

        -- Into the marked place, not the first free one.
        RaidBar.ClearSlot(2)
        Check("A button lands in the place you marked",
            RaidBar.Pick("pingattack", 2) == 2)

        RaidBar.SetRows(1)
        RaidBar.SetColumns(2)
        Check("Rows times columns is the count", RaidBar.Count() == 2)

        RaidBar.SetColumns(RaidBar.MAX_COLUMNS + 5)
        Check("Columns are clamped",
            RaidBar.Columns() == RaidBar.MAX_COLUMNS)
        RaidBar.SetRows(0)
        Check("Rows are clamped", RaidBar.Rows() == 1)

        -- WHAT FALLS OFF THE END STAYS PUT. Taking the bar down and back up
        -- has to give you what you had - the same rule a cooldown bar's cells
        -- follow.
        RaidBar.SetRows(1)
        RaidBar.SetColumns(12)
        RaidBar.SetSlot(12, "readycheck")
        RaidBar.SetColumns(4)
        RaidBar.SetColumns(12)
        Check("A button off the end comes back",
            RaidBar.ActionAt(12) == "readycheck")
    end)
    ns.db.raidBar = kept
    if not ok then error(err) end

    ---------------------------------------------------------------------
    -- The two calls the game may refuse
    ---------------------------------------------------------------------
    local may, why = RaidBar.MayLead()
    if IsInGroup and IsInGroup() then
        Skip("Leading refused when alone", "you are in a group")
    else
        Check("Alone, there is nobody to ready-check",
            may == false and why == "not in a group")
    end

    ---------------------------------------------------------------------
    -- The keys
    --
    -- The NAME shape, which is the half that can be checked in game: a
    -- binding this addon names has to be the CLICK form, because a line of
    -- Lua may not press a protected button. Whether Bindings.xml carries
    -- twelve of them is checked by the desktop harness, which can read files.
    ---------------------------------------------------------------------
    Check("A raid bar key presses the button itself",
        RaidBar.BindingName(3) == "CLICK ZwoelfStuffRaidBar3:LeftButton")
    Check("There are keys for the first twelve places",
        RaidBar.KEYS == 12)

    local reads = true
    for index = 1, RaidBar.KEYS do
        if not pcall(RaidBar.Key, index) then reads = false end
    end
    Check("Reading a bound key never throws", reads)
end

---------------------------------------------------------------------------
-- The raid check
--
-- The window cannot be judged out here, but everything that DECIDES what it
-- draws can: what this client says about itself, what travels, and what
-- arrives. The wire is the part worth guarding - it is read from another
-- machine, and a decoder that trusts what it is handed is a decoder that can
-- be handed a table key.
---------------------------------------------------------------------------
local function TestRaidCheck()
    local RaidCheck = ns.RaidCheck
    local Comm = ns.Comm
    Check("There is a raid check", RaidCheck ~= nil)
    if not RaidCheck then return end

    ---------------------------------------------------------------------
    -- The buffs, and the bits they travel as
    ---------------------------------------------------------------------
    local bits, spells = {}, 0
    for _, buff in ipairs(RaidCheck.BUFFS) do
        Check("Buff " .. buff.key .. " has a bit of its own", not bits[buff.bit])
        bits[buff.bit] = true
        for _ in pairs(buff.spells) do spells = spells + 1 end
    end
    Check("There are six group buffs", #RaidCheck.BUFFS == 6)
    Check("Every buff names at least one spell", spells >= #RaidCheck.BUFFS)

    local all = 0
    for _, buff in ipairs(RaidCheck.BUFFS) do all = all + buff.bit end
    local everyBit, noBit = true, false
    for _, buff in ipairs(RaidCheck.BUFFS) do
        if not RaidCheck.HasBuff(all, buff) then everyBit = false end
        if RaidCheck.HasBuff(0, buff) then noBit = true end
    end
    Check("Every bit reads back out of a full mask", everyBit)
    Check("An empty mask has nothing in it", not noBit)
    Check("A mask that is not a number is not a buff",
        not RaidCheck.HasBuff(nil, RaidCheck.BUFFS[1]))

    -- One bit set and the others clear, which is the case a bad shift gets
    -- wrong while a full mask still looks right.
    local second = RaidCheck.BUFFS[2]
    Check("One buff alone reads as that buff",
        RaidCheck.HasBuff(second.bit, second)
            and not RaidCheck.HasBuff(second.bit, RaidCheck.BUFFS[1]))

    ---------------------------------------------------------------------
    -- What this client says about itself
    ---------------------------------------------------------------------
    local mine = RaidCheck.Read()
    Check("The reading is a table", type(mine) == "table")

    if GetInventoryItemDurability then
        local worst = RaidCheck.Durability()
        -- THE LOWEST, NOT THE AVERAGE. A raid leader asking about durability
        -- is asking whether somebody's weapon is about to fall apart, and an
        -- average hides exactly that.
        Check("Durability is the worst piece worn",
            worst == nil or (worst >= 0 and worst <= 100),
            tostring(worst))
    end

    if RaidCheck.AurasReadable() then
        -- WHETHER YOU ARE FED IS NOT A PROPERTY OF THIS CODE.
        --
        -- These three lines used to read `mine.fo == 1`, `mine.fl == 1` and
        -- "buff six is not up" - which is not a test of the reader, it is a
        -- test of what the player happens to be carrying at the moment they
        -- type /zs test. Written during a raid, they passed; run in the guild
        -- city the next afternoon they reported TWO FAILURES against code
        -- that was working perfectly. A check that fails on a true negative
        -- teaches you to ignore the report, which costs more than the check
        -- was ever worth.
        --
        -- The desk could not catch it either: out there AurasReadable() is
        -- false and the whole block is skipped, so this only ever ran on a
        -- client - and only ever agreed with whoever was holding a flask.
        --
        -- WHAT IS ACTUALLY OURS TO GET WRONG is the SHAPE of the reading,
        -- and there are two real faults in here that the old lines could not
        -- tell apart from an empty stomach:
        --   the client says auras are readable and the read gives NOTHING
        --   the read gives something that is not a flag
        local flags = { fo = "food", fl = "flask", ru = "rune" }
        local missing, malformed
        for key, what in pairs(flags) do
            if mine[key] == nil then
                missing = missing or what
            elseif mine[key] ~= 0 and mine[key] ~= 1 then
                malformed = string.format("%s = %s", what, tostring(mine[key]))
            end
        end

        Check("Your own auras can be read at all", missing == nil,
            missing and ("no " .. missing .. " reading came back, though this "
                .. "client says auras are readable"))
        Check("Each consumable reads as a yes or a no", malformed == nil,
            malformed)
        Check("The buff mask is a number", type(mine.bf) == "number",
            type(mine.bf))

        -- Every bit in the mask has to belong to a buff we know. A stray one
        -- means the mask and the BUFFS table have drifted apart, which IS
        -- ours - and unlike "are you flasked", it is true whatever you are
        -- standing in.
        if type(mine.bf) == "number" then
            local known = 0
            for _, buff in ipairs(RaidCheck.BUFFS) do known = known + buff.bit end
            Check("The mask claims no buff this addon does not know",
                mine.bf >= 0 and mine.bf <= known
                and math.floor(mine.bf) == mine.bf, tostring(mine.bf))
        end

        -- AND THEN SAY WHAT IT FOUND, rather than have an opinion about it.
        -- This is the half that was worth having: if he is sitting there with
        -- a flask up and this line says no, THAT is the bug - and now it is
        -- one line to read instead of a red check that cries wolf every time
        -- somebody tests outside a raid.
        local carried = {}
        for _, buff in ipairs(RaidCheck.BUFFS) do
            if RaidCheck.HasBuff(mine.bf, buff) then
                carried[#carried + 1] = buff.label
            end
        end
        Skip("What you are carrying right now", string.format(
            "food %s, flask %s, rune %s, buffs: %s",
            mine.fo == 1 and "yes" or "no",
            mine.fl == 1 and "yes" or "no",
            mine.ru == 1 and "yes" or "no",
            #carried > 0 and table.concat(carried, ", ") or "none"))
    else
        Skip("Reading your own consumables", "this client keeps auras secret")
    end

    ---------------------------------------------------------------------
    -- The wire
    ---------------------------------------------------------------------
    local wire = Comm.EncodeCheck({ il = 639, du = 94, fo = 1, fl = 1, ru = 0,
        bf = 63 })
    local back = Comm.DecodeCheck(wire)
    Check("A reading survives the trip", back ~= nil and back.fields
        and back.fields.il == 639 and back.fields.du == 94
        and back.fields.bf == 63)

    -- WRITTEN IN A FIXED ORDER, so the same facts are the same string.
    Check("The same facts encode the same way",
        Comm.EncodeCheck({ bf = 1, il = 2 })
            == Comm.EncodeCheck({ il = 2, bf = 1 }))

    local ask = Comm.DecodeCheck(Comm.EncodeCheckAsk())
    Check("An ask decodes as an ask", ask ~= nil and ask.ask == true)

    -- THE TWO WIRE FORMS MUST NOT READ EACH OTHER. This is the whole reason
    -- the check form was shaped the way it was: an older client runs
    -- Comm.Decode alone, and it has to come back with nothing rather than
    -- with a spell it half understood.
    Check("The old decoder rejects a raid check", Comm.Decode(wire) == nil)
    Check("The old decoder rejects an ask",
        Comm.Decode(Comm.EncodeCheckAsk()) == nil)
    Check("The check decoder rejects a cooldown message",
        Comm.DecodeCheck(Comm.Encode(Comm.USED, Comm.EXTERNAL, 1022, 300))
            == nil)

    -- DATA FROM ANOTHER MACHINE IS NOT TRUSTED. A key nobody knows and a
    -- number wider than its field are both dropped rather than kept.
    local dirty = Comm.DecodeCheck("1|CHECK|il=639,zz=1,du=99999")
    Check("An unknown field is dropped",
        dirty ~= nil and dirty.fields.zz == nil)
    Check("A number too wide for its field is dropped",
        dirty ~= nil and dirty.fields.du == nil and dirty.fields.il == 639)
    Check("A message with nothing usable in it is nil",
        Comm.DecodeCheck("1|CHECK|zz=1") == nil)
    Check("Another version's check is not read",
        Comm.DecodeCheck("9|CHECK|il=1") == nil)
    Check("Rubbish is not a check", Comm.DecodeCheck("hello") == nil
        and Comm.DecodeCheck(nil) == nil)

    ---------------------------------------------------------------------
    -- The columns
    ---------------------------------------------------------------------
    local buffColumns = 0
    for _, column in ipairs(RaidCheck.COLUMNS) do
        if column.kind == "bit" then buffColumns = buffColumns + 1 end
    end
    Check("Every group buff has a column of its own",
        buffColumns == #RaidCheck.BUFFS)
    Check("The window is as wide as its columns", RaidCheck.Width() > 400)
    Check("The first column is the name", RaidCheck.COLUMNS[1].key == "name")
end

---------------------------------------------------------------------------
-- The invite tool
--
-- EVERY RULE IN HERE IS ONE STRING COMPARISON, and getting it wrong is either
-- a raid nobody can join or a raid that invites everybody who says hello.
-- None of it needs a group, which is the point of writing it as pure
-- functions in the first place.
---------------------------------------------------------------------------
local function TestInvites()
    local Invites = ns.Invites
    Check("There is an invite tool", Invites ~= nil)
    if not Invites then return end

    ---------------------------------------------------------------------
    -- The keywords
    ---------------------------------------------------------------------
    local set, order = Invites.Keywords("inv\nINVITE\n  1  \ninv\n\n")
    Check("Keywords are lower-cased and trimmed",
        set.inv and set.invite and set["1"])
    Check("A repeated keyword is kept once", #order == 3,
        table.concat(order, ","))
    Check("Empty lines are not keywords", set[""] == nil)
    Check("Commas separate too", select(2, Invites.Keywords("inv, invite"))[2]
        == "invite")
    -- The brackets are load-bearing: Keywords answers TWO values, and
    -- `next(a, b)` reads the second as a key to start from - which threw
    -- "invalid key to 'next'" rather than answering.
    Check("No keywords at all is an empty set",
        next((Invites.Keywords(""))) == nil)

    ---------------------------------------------------------------------
    -- The match
    ---------------------------------------------------------------------
    Check("The exact word invites", Invites.Matches("inv", set, false))
    Check("Case does not matter", Invites.Matches("INV", set, false))
    Check("Trailing punctuation does not matter",
        Invites.Matches("inv!", set, false) and Invites.Matches("inv.", set, false))
    Check("Space around it does not matter",
        Invites.Matches("  inv  ", set, false))

    -- STRICT IS STRICT. This is the half that keeps a raid leader from
    -- inviting somebody who was talking about something else.
    Check("A sentence containing the word does not invite",
        not Invites.Matches("inv please", set, false))
    Check("A sentence containing the word invites when asked to",
        Invites.Matches("inv please", set, true))
    -- AND THE COST OF LOOSE, which is on the page in as many words.
    Check("Loose matching finds it in a refusal too",
        Invites.Matches("I cannot inv you sorry", set, true))
    Check("An empty message never matches",
        not Invites.Matches("", set, true) and not Invites.Matches("  ", set, true))
    Check("Something that is not a message never matches",
        not Invites.Matches(nil, set, true))

    ---------------------------------------------------------------------
    -- Who gets in
    ---------------------------------------------------------------------
    Check("With no filters anybody gets in",
        Invites.MayInvite({}, false, false))
    Check("Guild only keeps a stranger out",
        not Invites.MayInvite({ guildOnly = true }, false, false))
    Check("Guild only lets a guild member in",
        Invites.MayInvite({ guildOnly = true }, true, false))
    Check("Friends only lets a friend in",
        Invites.MayInvite({ friendsOnly = true }, false, true))
    -- GUILD COUNTS AS FRIEND, and it is deliberate rather than sloppy: a
    -- guild member is somebody you have already said yes to once.
    Check("Friends only lets a guild member in",
        Invites.MayInvite({ friendsOnly = true }, true, false))
    Check("A refusal says why",
        select(2, Invites.MayInvite({ guildOnly = true }, false, false))
            == "not in your guild")

    ---------------------------------------------------------------------
    -- Being invited
    ---------------------------------------------------------------------
    Check("Nothing is accepted while the switch is off",
        not Invites.ShouldAccept({}, true, true))
    Check("A friend's invitation is accepted",
        Invites.ShouldAccept({ autoAccept = true }, true, false))
    Check("A guild member's invitation is accepted",
        Invites.ShouldAccept({ autoAccept = true }, false, true))
    Check("A stranger's invitation is not",
        not Invites.ShouldAccept({ autoAccept = true }, false, false))

    ---------------------------------------------------------------------
    -- Ranks, which count the wrong way round
    ---------------------------------------------------------------------
    Check("Any rank passes when none is set",
        Invites.RankAllowed(4, nil))
    Check("The guild master passes every filter",
        Invites.RankAllowed(0, 3))
    Check("A rank below the line is kept out",
        not Invites.RankAllowed(5, 3))
    Check("The line itself is in", Invites.RankAllowed(3, 3))
    Check("A rank that is not a number is out",
        not Invites.RankAllowed(nil, 3))

    ---------------------------------------------------------------------
    -- Promotion
    ---------------------------------------------------------------------
    Check("A named player is promoted",
        Invites.ShouldPromote("Zwoelf", "zwoelf\nakui"))
    Check("A name with a realm on it still matches",
        Invites.ShouldPromote("Akui-Gilneas", "akui"))
    Check("Nobody else is promoted",
        not Invites.ShouldPromote("Somebody", "zwoelf\nakui"))
    Check("An empty list promotes nobody",
        not Invites.ShouldPromote("Zwoelf", ""))

    ---------------------------------------------------------------------
    -- The listener, which must do nothing until it is switched on
    ---------------------------------------------------------------------
    if not ns.db then
        Skip("The invite listener", "no profile open")
        return
    end

    local keptModules = ns.db.modules and ns.db.modules.invites
    local keptInvites = ns.db.invites
    local ok, err = pcall(function()
        ns.db.modules = ns.db.modules or {}
        ns.db.invites = { keywords = "inv" }

        ns.db.modules.invites = false
        Check("A switched-off module does not invite",
            not Invites.OnMessage("inv", "Somebody", "WHISPER"))

        ns.db.modules.invites = true
        Check("Nothing happens until the switch is on",
            not Invites.OnMessage("inv", "Somebody", "WHISPER"))

        ns.db.invites.onWhisper = true
        Check("Say and yell are ignored until asked for",
            not Invites.OnMessage("inv", "Somebody", "SAYYELL"))

        -- YOUR OWN MESSAGE COMES BACK TO YOU on some channels, and inviting
        -- yourself is a refusal in the client and a puzzled line in chat.
        Check("Your own message is not an invitation",
            not Invites.OnMessage("inv", UnitName("player"), "WHISPER"))

        Check("Something that is not a word is not a request",
            not Invites.OnMessage("hello", "Somebody", "WHISPER"))

        -- A NAME THE CLIENT WITHHELD. Comparing it raises; the guard is the
        -- only reason this does not take the chat handler down with it.
        Check("A withheld name is not invited",
            not Invites.OnMessage("inv", __SECRET, "WHISPER"))

        ns.db.invites.guildOnly = true
        Check("Guild only keeps a stranger out of the group",
            not Invites.OnMessage("inv", "Somebody", "WHISPER"))
    end)
    ns.db.invites = keptInvites
    if ns.db.modules then ns.db.modules.invites = keptModules end
    if not ok then error(err) end
end

---------------------------------------------------------------------------
-- THE FRAME CONTRACT'S ONE PIECE OF CODE
--
-- Rule 3 says our data never goes onto a frame Blizzard owns, and the reason
-- that needs a table rather than a comment is that the obvious way to
-- remember "this icon is in cell 4" is `frame.zsCell = 4`.
--
-- The property worth testing is the one that is easy to get wrong and
-- impossible to see: the keys are WEAK. Blizzard's viewers recycle item
-- frames through a pool across spec changes and reloads, and a strong table
-- would hold every frame the session ever saw - then hand back last spec's
-- note for a frame that has since been re-issued to a different spell. The
-- old implementation had a "rival check" for exactly that symptom.
--
-- A desk guard cannot see this: __mode is a runtime property. So it is asked
-- here, where there is a real collector, and the collect is affordable
-- because /zs test is something a person types.
---------------------------------------------------------------------------
local function TestFrameContract()
    local C = ns.Cooldowns
    if not C then
        Skip("The frame contract", "Cooldowns/Contract.lua is not loaded")
        return
    end

    -- Stand-ins, not real frames: the question is about the TABLE, and a real
    -- item frame is held by Blizzard's pool and would never be collected no
    -- matter what __mode says - which would make the last check pass for the
    -- wrong reason.
    local one, two = {}, {}

    local first = C.Record(one)
    Check("A frame gets a note on first ask", type(first) == "table")
    Check("And the same note on the second", C.Record(one) == first)
    Check("A different frame gets a different note", C.Record(two) ~= first)

    first.cell = 4
    Check("What we remember is on OUR table, not theirs",
        C.Record(one).cell == 4 and one.cell == nil)

    Check("Known answers without inventing one", C.Known({}) == nil)
    Check("And answers with the one that exists", C.Known(one) == first)

    C.Forget(one)
    Check("Forget drops it", C.Known(one) == nil)

    Check("A nil frame is answered, not raised",
        C.Record(nil) == nil and C.Known(nil) == nil)
    Check("And forgetting nothing is not an error",
        pcall(C.Forget, nil) == true)

    -- THE ONE THAT MATTERS. Drop the only reference and collect: a strong
    -- table keeps the count, a weak one lets it go.
    local held = C.Held()
    do
        local doomed = {}
        C.Record(doomed)
        Check("Held counts what we are holding", C.Held() == held + 1)
    end
    collectgarbage("collect")
    Check("A frame nobody holds any more takes its note with it",
        C.Held() == held,
        "the keys are not weak - notes will outlive the frames they describe")

    C.Forget(two)
end

---------------------------------------------------------------------------
-- WHO ELSE SAYS THEY MANAGE COOLDOWNS
--
-- The rule reads what every installed addon says about ITSELF, so its whole
-- worth is in where it draws the line. That line was drawn against 97 real
-- addons and it is one word wide: matching "cooldown" on its own reports
-- ProfessionShoppingList, whose description reads "Track recipes, reagents,
-- cooldowns, patron orders" and which has never touched a cooldown frame.
--
-- Those two sentences are in here verbatim for that reason. A first-run
-- warning that fires on a quiet neighbour is one people learn to click away,
-- and by the time anybody notices it has been crying wolf for a month there
-- is nothing left to check it against - the addon that caused it will have
-- been updated. So the calibration is nailed down where it can fail loudly.
---------------------------------------------------------------------------
local function TestRivals()
    local R = ns.Cooldowns and ns.Cooldowns.Rivals
    if not R then
        Skip("Other cooldown addons", "Cooldowns/Rivals.lua is not loaded")
        return
    end

    -- The one it MUST find. EllesmereUI Cooldown Manager, v8.8.7, both lines
    -- copied out of its own TOC.
    Check("A title that names the Cooldown Manager is found",
        R.Claims("|cff0cd29fEllesmereUI|r Cooldown Manager") == true)
    Check("And a description that says CDM replacement",
        R.Claims("A CDM replacement focused on performance, customizations "
            .. "and alerts.") == true)

    -- The one it MUST NOT find, and the reason the rule is not one word
    -- shorter. Straight out of ProfessionShoppingList's TOC.
    Check("A description that merely mentions cooldowns is not",
        R.Claims("Track recipes, reagents, cooldowns, patron orders, and more")
            == false,
        "matching on the word 'cooldown' alone reports this addon")

    -- CDM as a word, not as three letters inside one.
    Check("CDM has to stand on its own", R.Claims("cdmanager toolkit") == false)
    Check("Punctuation around it still counts", R.Claims("(CDM)") == true)

    -- THE FOLDER NAME ON ITS OWN, because four of the five addons known to
    -- collide with a cooldown manager say what they are there and nowhere
    -- else.
    Check("A folder name alone is enough",
        R.Claims("BetterCooldownManager") == true
        and R.Claims("CooldownManagerCentered") == true
        and R.Claims("SkironCooldownManager") == true)

    -- AN UNDERSCORE IS NOT A WORD CHARACTER TO %w - it is to %a plus digits
    -- and nothing else - so "ayije_cdm" has a frontier right where it is
    -- needed. That is worth a check of its own rather than a comment: the
    -- rule reads as though it would fail here, and the folder that depends on
    -- it belongs to the one rival another addon calls a client crash.
    Check("Ayije_CDM is found across the underscore",
        R.Claims("Ayije_CDM") == true)

    Check("Case does not matter",
        R.Claims("COOLDOWN MANAGER") == true
        and R.Claims("cooldown manager") == true)
    Check("Nothing to read is not a match",
        R.Claims(nil) == false and R.Claims("") == false)

    -- The scan itself. Out here there is no client to enumerate, so this asks
    -- the one thing that must hold either way: it answers a list rather than
    -- nil, and it never names US.
    local others = R.Others()
    Check("The scan answers a list", type(others) == "table")
    local named = false
    for _, entry in ipairs(others) do
        if entry.folder == "ZwoelfStuff" then named = true end
    end
    Check("And never reports this addon as its own rival", named == false)

    local clash, list = R.Any()
    Check("Any agrees with the list it hands back",
        clash == (#list > 0))

    -- WHAT WOULD BREAK IF THAT ADDON WENT AWAY. Answering a list for a name
    -- that is nothing is the case a caller hits first, and it must not raise
    -- on the way to the button that reads it.
    Check("Nothing depends on nothing", #R.Dependents(nil) == 0)
    Check("And the answer is always a list", type(R.Dependents("")) == "table")

    -- THE GUARD PATHS OF Disable, AND ONLY THOSE.
    --
    -- Nothing here may pass a real addon name. Disable switches an addon off
    -- and writes to the profile, and a test that did that would be the third
    -- time this suite reached into somebody's settings and left them changed.
    -- The two refusals are what a caller has to be able to trust; the rest of
    -- that function is proved on the desk, where the page is built with a
    -- stand-in rival and the button is really pressed.
    local okNil, whyNil = R.Disable(nil)
    Check("Switching off nothing is refused, not attempted",
        okNil == false and type(whyNil) == "string")
    Check("And so is an empty name", (R.Disable("")) == false)
end

---------------------------------------------------------------------------
-- THE COOLDOWN LATTICE
--
-- Every number in here is worked out by hand in the comment beside it. That
-- is the point of a pure model: an off-by-one in cell placement raises no
-- error - it puts the right icon in the wrong square, which looks exactly
-- like a working bar and is only ever found by somebody staring at a screen.
--
-- The defaults the arithmetic below assumes: size 32, spacing 4, so one step
-- is 36 on both axes.
---------------------------------------------------------------------------
local function TestCooldownModel()
    local M = ns.Cooldowns and ns.Cooldowns.Model
    if not M then
        Skip("The cooldown lattice", "Cooldowns/Model.lua is not loaded")
        return
    end

    local four = { columns = 4 }

    -- Cell 1 is the origin. Everything else is measured from it, so if this
    -- is not nought the whole bar is offset and every other check still passes.
    local x, y, w, h = M.Slot(1, four, 4)
    Check("Cell 1 sits at the origin", x == 0 and y == 0)
    Check("And is one cell big", w == 32 and h == 32)

    -- Cell 5 of a four-wide bar is the first of the second row: straight
    -- below cell 1, one step down. +y is UP, so down is negative.
    x, y = M.Slot(5, four, 8)
    Check("The fifth cell of a four-wide bar starts the second row",
        x == 0 and y == -36, string.format("%s,%s", x, y))

    -- Growing upwards flips only the y. It is the case that reads correctly
    -- in the source either way round and is upside down on screen.
    x, y = M.Slot(5, { columns = 4, growY = "up" }, 8)
    Check("Growing up puts the second row above the first",
        x == 0 and y == 36, string.format("%s,%s", x, y))

    -- Growing left flips only the x, and cell 1 stays at nought.
    x = M.Slot(2, { columns = 4, growX = "left" }, 4)
    Check("Growing left puts the second cell to the left", x == -36)

    ---------------------------------------------------------------------
    -- READING ORDER, which is not the same question as growth
    ---------------------------------------------------------------------
    local row, column = M.Cell(6, 4, "rows")
    Check("Along rows: the sixth cell is row 1, column 1",
        row == 1 and column == 1, string.format("%s,%s", row, column))

    -- Eight cells four wide is two rows tall, so filling downwards puts the
    -- second cell UNDER the first and the third at the top of column two.
    row, column = M.Cell(2, 4, "columns", 8)
    Check("Down columns: the second cell is under the first",
        row == 1 and column == 0, string.format("%s,%s", row, column))
    row, column = M.Cell(3, 4, "columns", 8)
    Check("And the third starts the second column",
        row == 0 and column == 1, string.format("%s,%s", row, column))

    ---------------------------------------------------------------------
    -- THE PROPERTY THE WHOLE MODEL EXISTS FOR
    --
    -- A flat list re-flows when the width changes; a stored grid position
    -- scrambles. Cell 6 is on the second row at three wide and on the third
    -- at two wide, and it is still the sixth thing on the bar either way.
    ---------------------------------------------------------------------
    local _, sixAtThree = M.Cell(6, 3, "rows")
    local rowAtTwo = M.Cell(6, 2, "rows")
    Check("Narrowing the bar re-flows rather than scrambles",
        M.Cell(6, 3, "rows") == 1 and sixAtThree == 2 and rowAtTwo == 2)

    ---------------------------------------------------------------------
    -- STAGGER, on the row and not on the cell
    ---------------------------------------------------------------------
    local staggered = { columns = 4, layout = "staggered" }
    x = M.Slot(1, staggered, 8)
    Check("A staggered bar does not move its first row", x == 0)
    x = M.Slot(5, staggered, 8)
    Check("It shifts the second row by half a step", x == 18, tostring(x))
    x = M.Slot(9, staggered, 12)
    Check("And leaves the third alone again", x == 0, tostring(x))

    ---------------------------------------------------------------------
    -- THE BOX, measured off the slots rather than from a formula
    ---------------------------------------------------------------------
    local width, height = M.Extent(4, four)
    Check("Four cells in a row are four cells and three gaps wide",
        width == 140 and height == 32,
        string.format("%sx%s", width, height))

    width, height = M.Extent(8, four)
    Check("Two rows are two cells and one gap tall",
        width == 140 and height == 68, string.format("%sx%s", width, height))

    -- THE ONE A FORMULA WOULD GET WRONG. A staggered bar is half a step wider
    -- than the same cells in a grid, and a box computed as columns*step would
    -- crop the last icon of the shifted row - one layout, one row, and it
    -- reads as a texture fault.
    width = M.Extent(8, staggered)
    Check("A staggered bar is half a step wider than a straight one",
        width == 158, tostring(width))

    Check("Nothing at all has no size", (M.Extent(0, four)) == 0)

    ---------------------------------------------------------------------
    -- COMPOSED WITH THE GAP-CLOSING RULE, which lives in Layout and is
    -- called rather than copied
    ---------------------------------------------------------------------
    local places, used = M.Places(4, four, { [2] = true }, "all")
    Check("A hidden cell is absent from the places", places[2] == nil)
    Check("And the ones after it move up a slot",
        places[3] and places[3].slot == 2 and places[3].x == 36,
        places[3] and tostring(places[3].x) or "missing")
    Check("The bar knows it only needs three slots", used == 3)

    -- Switched off, nothing moves. The identity case is the one every caller
    -- is in most of the time.
    places = M.Places(4, four, {}, nil)
    Check("With closing off, cell 4 stays in slot 4",
        places[4] and places[4].slot == 4 and places[4].x == 108)
end

---------------------------------------------------------------------------
-- READING A STORED BAR
--
-- Every fixture in here is the SHAPE his own file actually has, taken off
-- disk rather than off the defaults table - including the two things that
-- would have been got wrong by writing against the defaults: a cell list with
-- holes in it, and a stagger stored as a percentage.
---------------------------------------------------------------------------
local function TestCooldownStore()
    local S = ns.Cooldowns and ns.Cooldowns.Store
    if not S then
        Skip("Reading a stored bar", "Cooldowns/Store.lua is not loaded")
        return
    end

    -- HIS SHAPE. A hole at slot 2 is a bar somebody arranged, not a broken
    -- one, and `#` on this table may legally answer 1.
    local bar = {
        id = 3, name = "Cooldowns", rows = 1, columns = 5,
        iconSize = 40, spacing = 4, staggerOffset = 50,
        layout = "grid", flow = "rows", growX = "right", growY = "down",
        cells = { 1044, nil, 102342, 633, 47788 },
    }

    Check("A hole in the middle does not shorten the bar",
        S.Capacity(bar) == 5, tostring(S.Capacity(bar)))

    -- THE ONE HIS FILE ACTUALLY HAS: a bar declaring five columns in one row
    -- and a cell list twelve long. Trusting the declared number drops seven
    -- of his picks, silently.
    local wide = { rows = 1, columns = 5, cells = {} }
    for index = 1, 12 do wide.cells[index] = 1000 + index end
    Check("A cell past the declared width still counts",
        S.Capacity(wide) == 12, tostring(S.Capacity(wide)))

    -- And the other direction: a bar with room and nothing in it is still
    -- that big, or the editor has nowhere to drop a spell.
    Check("An empty bar is as big as it says it is",
        S.Capacity({ rows = 2, columns = 5 }) == 10)
    Check("Nothing at all is nothing", S.Capacity(nil) == 0)

    -- HOW MANY PLACES, SAID OUTRIGHT.
    --
    -- rows x columns can only ever describe a RECTANGLE - six across is six,
    -- twelve or eighteen, never seven - and his own 4.82.0 bars already carry
    -- the real number under `freeCount`. Owner, 2026-08-15: "feste cells und
    -- rows sollte man einstellen koennen."
    Check("A bar that says how many places it has is believed",
        S.Capacity({ rows = 1, columns = 6, cellCount = 7 }) == 7,
        tostring(S.Capacity({ rows = 1, columns = 6, cellCount = 7 })))
    Check("And it may be smaller than one full line",
        S.Capacity({ rows = 1, columns = 6, cellCount = 4 }) == 4)

    -- A DECLARED COUNT IS A LIMIT, AND THIS REVERSES WHAT THIS FILE ASSERTED.
    --
    -- It used to check that a pick past the declared end RAISED the count -
    -- Capacity answered with the largest of what was declared and what was
    -- referenced. Owner, 2026-08-15, with a photograph of a bar he could not
    -- get down to one line: "ich muss auf eine reihe begrenzen koennen." He
    -- could not, and this was why: a bar carrying twelve picks went on drawing
    -- twelve however low Rows was set, because the picks outvoted the setting.
    -- A limit a stored value can overrule is not a limit.
    Check("A declared count is a limit and not a suggestion",
        S.Capacity({ columns = 6, cellCount = 3,
            cells = { [9] = 1044 } }) == 3)

    -- AND THE PICK IS STILL THERE, which is the half that keeps the old
    -- promise true. Nothing is deleted; it is counted and the page says the
    -- number out loud, which is what the generous answer was trying to do by
    -- inflating the bar instead.
    Check("The pick past the end is kept and counted",
        S.Parked({ columns = 6, cellCount = 3, cells = { [9] = 1044 } }) == 1)
    Check("A bar with room for everything parks nothing",
        S.Parked({ columns = 6, cellCount = 9, cells = { [9] = 1044 } }) == 0)

    -- A bar written before this key existed answers exactly as it did, which
    -- is the whole of "Store translates, it does not migrate".
    Check("A bar with no count at all is still rows times columns",
        S.Capacity({ rows = 3, columns = 4 }) == 12)

    ---------------------------------------------------------------------
    -- THE UNIT CONVERSION, which is the one silent failure in this file
    ---------------------------------------------------------------------
    local opts = S.Lattice(bar)
    Check("The stagger comes across as a fraction of a step",
        opts.stagger == 0.5, tostring(opts.stagger))
    Check("iconSize becomes the model's size", opts.size == 40)
    Check("And the words that already agree are passed straight through",
        opts.layout == "grid" and opts.flow == "rows"
        and opts.growX == "right" and opts.growY == "down")

    -- Proved end to end rather than by inspection: fifty read as fifty
    -- STEPS would put the second row a screen and a half to the right.
    local M = ns.Cooldowns.Model
    if M then
        local shifted = S.Lattice(bar)
        shifted.layout = "staggered"
        local x = M.Slot(6, shifted, 10)
        Check("A staggered row moves half a cell, not fifty",
            x == 22, tostring(x))
    end

    ---------------------------------------------------------------------
    -- THE THREE AN AUDIT AGAINST HIS OWN BARS FOUND, all of which drew
    -- something rather than failing
    ---------------------------------------------------------------------

    -- HIS SECOND BAR: column gap 2, row gap 4. One number for both axes is
    -- right on one of his four bars by coincidence.
    local twoGaps = S.Lattice({ columns = 5, iconSize = 36,
        spacing = 2, lineSpacing = 4 })
    Check("A bar's row gap is not its column gap",
        twoGaps.spacing == 2 and twoGaps.lineSpacing == 4)
    if M then
        -- step across = 36+2 = 38, step down = 36+4 = 40
        local x, y = M.Slot(6, twoGaps, 10)
        Check("And the model uses each on its own axis",
            x == 0 and y == -40, string.format("%s,%s", x, y))
    end

    -- HIS THIRD BAR, "Bars 2": kind="bar", 250 by 24, carrying an untouched
    -- iconSize of 40. Reading iconSize and never kind hands the model four
    -- forty-pixel squares for a bar a quarter of the screen wide.
    local statusBar = S.Lattice({ kind = "bar", rows = 3, columns = 1,
        barWidth = 250, barHeight = 24, iconSize = 40, spacing = 3 })
    Check("A bar-kind cell is as wide as the bar, not as wide as an icon",
        statusBar.width == 250 and statusBar.size == 24,
        string.format("%sx%s", tostring(statusBar.width),
            tostring(statusBar.size)))
    local icons = S.Lattice({ kind = "icon", iconSize = 40 })
    Check("And an icon cell stays square",
        icons.size == 40 and icons.width == nil)

    -- THE VALUE RENAME. 4.82.0 stored "stagger"; this model says "staggered".
    -- None of his bars is staggered, so nothing would have said a word until
    -- somebody imported one from a shared string.
    Check("A bar stored as 'stagger' is still staggered",
        S.Lattice({ layout = "stagger" }).layout == "staggered")
    Check("And a word we do not know is passed through, not swallowed",
        S.Lattice({ layout = "free" }).layout == "free")

    ---------------------------------------------------------------------
    -- WHAT NOTHING READS YET, reported rather than assumed dead
    ---------------------------------------------------------------------
    local waves, unknown = S.Survey(bar)
    Check("Keys that are read today are named as such",
        waves.now and #waves.now > 0)
    Check("A bar of his has no unclaimed keys", #unknown == 0,
        table.concat(unknown, ", "))

    local invented = { id = 1, somethingNobodyDeclared = true }
    local _, strange = S.Survey(invented)
    Check("A key no wave claims is reported, not swallowed",
        #strange == 1 and strange[1] == "somethingNobodyDeclared")

    ---------------------------------------------------------------------
    -- ONE PLACE'S OWN STYLING, AND THE ONE RESOLVER THAT DECIDES IT
    --
    -- Out of his real saved variables: "Buff Bar" carries a RED fillColor,
    -- its first place carries GREEN and its second MAGENTA. He set the red
    -- and two places ignored him in silence. Both readers were right and
    -- there were TWO of them - Look's own and Fill's - each with a header
    -- saying it must move here rather than gain a third. This is that move,
    -- so this is where the precedence is asked.
    ---------------------------------------------------------------------
    local styled = {
        cells = { 1044, 102342 },
        fillColor = "bar", showSpark = true, chargeMarks = true,
        cellOpts = { [1] = { look = { fillColor = "slot" } } },
        cellLook = { [1044] = { fillColor = "spell" } },
    }

    Check("A place with nothing of its own wears the bar's answer",
        S.Option(styled, 2, "showSpark") == true)
    Check("The place's own styling wins over the bar's",
        S.Option({ cells = { 1044 }, fillColor = "bar",
            cellOpts = { [1] = { look = { fillColor = "slot" } } } },
            1, "fillColor") == "slot")
    -- AND THE SPELL'S OWN WINS OVER THE SLOT'S. Both exist on place 1 here,
    -- which is the only arrangement that can tell the two apart.
    Check("and what is keyed to the SPELL wins over what is keyed to the slot",
        S.Option(styled, 1, "fillColor") == "spell",
        tostring(S.Option(styled, 1, "fillColor")))
    Check("With no place named at all, the bar answers",
        S.Option(styled, nil, "fillColor") == "bar")

    -- THE WHOLE REASON IT IS KEYED BY SPELL. `cellOpts` is keyed by SLOT, so
    -- moving a spell one along leaves its styling behind for whatever lands
    -- there next - which is what actually happens when he rearranges a bar.
    local moved = {
        cells = { 102342, 1044 },
        fillColor = "bar",
        cellOpts = { [1] = { look = { fillColor = "slot" } } },
        cellLook = { [1044] = { fillColor = "spell" } },
    }
    Check("A spell moved to another place takes its styling with it",
        S.Option(moved, 2, "fillColor") == "spell",
        tostring(S.Option(moved, 2, "fillColor")))
    Check("and the slot it left keeps only what was keyed to the slot",
        S.Option(moved, 1, "fillColor") == "slot",
        tostring(S.Option(moved, 1, "fillColor")))

    -- FALSE HAS TO SURVIVE ALL THREE LEVELS. "No spark on this one" is the
    -- answer a per-place editor exists to give, and `x and y or z` cannot
    -- carry it - the idiom that has already cost this addon two settings
    -- nobody could switch off.
    Check("A place that says false is not read as 'said nothing'",
        S.Option({ cells = { 1044 }, showSpark = true,
            cellLook = { [1044] = { showSpark = false } } },
            1, "showSpark") == false)
    Check("and the same at slot level",
        S.Option({ cells = { 1044 }, chargeMarks = true,
            cellOpts = { [1] = { look = { chargeMarks = false } } } },
            1, "chargeMarks") == false)

    -- HIS THREE STORED ENTRIES ARE READ AND NEVER REWRITTEN. They were
    -- written by 4.82.0 and they are real settings of his; a resolver that
    -- "upgraded" them into the new shape would be a migration, and Store
    -- translates rather than migrates.
    S.Option(styled, 1, "fillColor")
    S.Overridden(styled, 1)
    Check("Resolving a place never rewrites what 4.82.0 stored",
        styled.cellOpts[1].look.fillColor == "slot"
            and styled.cellLook[1044].fillColor == "spell")

    ---------------------------------------------------------------------
    -- AND WHETHER A PLACE CARRIES ANYTHING AT ALL
    --
    -- Owner: "wo sehe ich denn, wenn ich einzelne bars oder icons style? ich
    -- sehe da keinen indikator." This is the answer a mark is drawn from, and
    -- there is one of it so the preview cell and the block being edited
    -- cannot disagree.
    ---------------------------------------------------------------------
    -- AND PER KEY, WHICH IS WHAT A MARK AND A "FOLLOW THE BAR AGAIN" NEED.
    -- Two returns, because `false` is a real answer: a single one cannot tell
    -- "this place switched the spark off" from "this place says nothing", and
    -- those two want opposite marks.
    local off, carried = S.Own({ cells = { 1044 }, showSpark = true,
        cellLook = { [1044] = { showSpark = false } } }, 1, "showSpark")
    Check("A place that switched something off is carrying an answer",
        off == false and carried == true,
        string.format("%s/%s", tostring(off), tostring(carried)))

    local _, quiet = S.Own(styled, 2, "showSpark")
    Check("and one that never said anything is not",
        quiet == false, tostring(quiet))

    Check("A place with styling of its own says so", S.Overridden(styled, 1))
    Check("and one without says so too", S.Overridden(styled, 2) == false)
    -- AN EMPTY TABLE IS NOT AN OVERRIDE. The editor writes one the moment it
    -- touches a place, and a mark that appears for a place carrying nothing
    -- is a mark that means nothing.
    Check("An empty override table is not styling",
        S.Overridden({ cells = { 1044 }, cellLook = { [1044] = {} } }, 1)
            == false)
    Check("Nor is a per-spell table with no entry for this spell",
        S.Overridden({ cells = { 1044 }, cellLook = { [999] = { alpha = 1 } } },
            1) == false)

    ---------------------------------------------------------------------
    -- AND THE WRITER, which lives in Bars because Store rewrites nothing
    --
    -- The rules above are the READ. These are what the per-place editor
    -- actually does when a control is moved, driven through the same two
    -- calls the page makes - so "the resolver is right" and "the page can
    -- reach it" are two answers rather than one assumed from the other.
    ---------------------------------------------------------------------
    local B = ns.Cooldowns and ns.Cooldowns.Bars
    if not B then
        Skip("Styling one place", "Cooldowns/Bars.lua is not loaded")
        return
    end

    -- ON A PROFILE OF ITS OWN. Store.Cells reads through ns.SpecStore, so
    -- these writes need a spec that is ANSWERED - and they must not go
    -- anywhere near his bars.
    local realKey = PretendSpec("DEATHKNIGHT:250")

    local mine = { cells = { 1044, 102342 }, fillColor = "bar",
        cellOpts = { [1] = { look = { showSpark = "his" } } } }

    Check("Styling a place writes under its SPELL, not under its slot",
        B.SetPlaceLook(mine, 1, "fillColor", "ours") == true
            and mine.cellLook ~= nil and mine.cellLook[1044] ~= nil
            and mine.cellLook[1044].fillColor == "ours")
    Check("and the bar itself is not touched by it",
        mine.fillColor == "bar")
    Check("and the resolver answers with it",
        S.Option(mine, 1, "fillColor") == "ours")

    -- THE ONE THING THAT MUST NEVER HAPPEN TO HIS FILE: his 4.82.0 settings
    -- were written by a version that is not running any more, and nothing
    -- here may rewrite or delete them.
    Check("His older per-slot settings are left exactly where they were",
        mine.cellOpts[1].look.showSpark == "his"
            and S.Option(mine, 1, "showSpark") == "his")

    -- A PLACE WITH NOTHING ON IT CANNOT CARRY STYLING, and it is refused with
    -- a reason rather than filed under nil - the crash this addon has already
    -- shipped once is a key that should never have been one.
    local ok, why = B.SetPlaceLook(mine, 5, "fillColor", "nowhere")
    Check("An empty place cannot be styled, and says why", ok == false
        and type(why) == "string" and why ~= "", tostring(why))

    -- CLEARING ONE KEY IS "FOLLOW THE BAR" FOR ONE ROW, and it must leave
    -- nothing behind: an empty table is not styling, but it IS a table his
    -- profile would carry for every place he ever clicked on.
    B.SetPlaceLook(mine, 1, "fillColor", nil)
    Check("Clearing the last key takes the place's whole entry with it",
        mine.cellLook == nil, type(mine.cellLook))
    Check("and the resolver falls back through to the bar",
        S.Option(mine, 1, "fillColor") == "bar")

    -- Clearing what was never there is the state that was asked for, not a
    -- failure: the place already follows the bar.
    Check("Clearing a place that carries nothing is not an error",
        B.SetPlaceLook(mine, 1, "fillColor", nil) == true)

    -- AND THE BUTTON: everything OURS on this place, gone, and nothing else.
    B.SetPlaceLook(mine, 1, "fillColor", "ours")
    B.SetPlaceLook(mine, 1, "borderSize", 4)
    Check("Following the bar again clears what this page wrote",
        B.ClearPlaceLook(mine, 1) == true and mine.cellLook == nil)
    Check("and leaves the older version's settings alone",
        mine.cellOpts[1].look.showSpark == "his")

    ---------------------------------------------------------------------
    -- WHICH PLACE THE ROWS ARE POINTED AT
    --
    -- THE SELECTION IS THE SWITCH. There was a "whole bar / this place"
    -- dropdown here for one wave, and the owner named what was wrong with it
    -- from a screenshot: the card had a highlight, the place had a ring and
    -- the menu had an answer, so three things claimed to say what he was
    -- editing and two of them could disagree. "Jetzt wird immer beides
    -- angewählt und man weiss nicht was man editiert."
    --
    -- So there is one field, Page.cell - the same one the spell picker has
    -- always used - and everything else reads it: the stripe on the card, the
    -- ring on the place, and every control in the four style blocks.
    ---------------------------------------------------------------------
    local page = ns.OptionsCooldowns
    if page then
        local savedBars, savedID = ns.db.bars, page.barID
        local savedCell = page.cell

        ns.db.bars = { { id = 9401, name = "desk", cells = { 1044, nil },
            rows = 1, columns = 2 } }
        page.barID = 9401

        page.cell = nil
        Check("With no place picked, the rows mean the whole bar",
            page.Place() == nil)

        page.cell = 1
        Check("Picking a place is what points them at it",
            page.Place() == 1, tostring(page.Place()))

        -- AN EMPTY PLACE HAS NOTHING TO KEY BY. Styling is filed under the
        -- SPELL so that it travels when the spell moves, so clicking an empty
        -- place selects it for the picker - which is what that click has
        -- always meant - and leaves the settings on the bar. Any other answer
        -- would offer a target its own writer refuses.
        page.cell = 2
        Check("An empty place is never what the rows are pointed at",
            page.Place() == nil)

        -- AND A SELECTION THAT HAS GONE OUT OF RANGE. A bar narrowed since the
        -- click leaves a number pointing at a place that no longer exists.
        ns.db.bars[1].columns = 1
        page.cell = 2
        Check("Nor is a place past the end of a bar that has been narrowed",
            page.Place() == nil)

        -- AND THE TWO MARKS ARE NEVER LIT TOGETHER, which is the whole of his
        -- report. The card's stripe is drawn from this same answer - "the
        -- settings are editing the WHOLE bar" - so one press moves both.
        --
        -- Asked as the condition the card is drawn from rather than by reading
        -- a texture: the stripe is a region on a pooled frame in a column this
        -- suite does not build, and a check that walked to it would be testing
        -- the layout rather than the rule.
        ns.db.bars[1].columns = 2
        page.cell = nil
        local wholeBar = page.Place() == nil
        page.cell = 1
        local onePlace = page.Place() == 1
        Check("The bar and one of its places are never both what you edit",
            wholeBar and onePlace, string.format("%s / %s", tostring(wholeBar),
                tostring(onePlace)))

        ns.db.bars, page.barID = savedBars, savedID
        page.cell = savedCell
    else
        Skip("Which place the rows are pointed at",
            "the cooldowns page is not loaded")
    end

    ns.SpecKey = realKey
end

---------------------------------------------------------------------------
-- CLAIMING A FRAME AND LETTING GO OF IT
--
-- THE ONE THING WAVE 2 IS MEASURED BY. The implementation this replaces
-- recorded nothing before it stripped a decoration, so releasing a frame left
-- every one of them pinned at zero for the rest of the session: Blizzard's
-- own Cooldown Manager left permanently stripped by an addon that had just
-- said it let go. Nothing caught it, because from the inside a frame we no
-- longer hold and a frame we handed back damaged look identical.
--
-- So this suite does not check that Strip strips. It checks that GIVE PUTS
-- EVERY SINGLE THING BACK, and it gives each decoration a DIFFERENT alpha
-- first - a restore that simply set them all to 1 would pass a test written
-- the lazy way, and 1 is what most of them happen to be.
--
-- The frames are ours, built here. Nothing in this suite touches a frame
-- Blizzard owns, which is what makes it safe to run in his client.
---------------------------------------------------------------------------
local function TestCooldownClaim()
    local Claim = ns.Cooldowns and ns.Cooldowns.Claim
    if not Claim then
        Skip("Claiming and letting go", "Cooldowns/Claim.lua is not loaded")
        return
    end

    -- A STAND-IN FOR ONE OF BLIZZARD'S ITEM FRAMES, built out of the parts
    -- the stripper actually reaches for. Every alpha is a different number on
    -- purpose - see the header.
    local item = CreateFrame("Frame")
    item.Icon = item:CreateTexture()
    item.Cooldown = CreateFrame("Frame", nil, item)

    -- AN ALPHA IS A BYTE, SO NOTHING HERE COMPARES ONE EXACTLY.
    --
    -- The client stores 256 steps and hands the value back as a 32-bit float:
    -- SetAlpha(0.9) reads back as 0.90196084976196, which is 230 times a
    -- float32 reciprocal of 255. The first version of this suite compared
    -- against the number it had PASSED IN, which is true out on the desk and
    -- false in his client - five checks failed at once on a round trip that
    -- was working perfectly.
    --
    -- Half a step is the widest a correct answer can be wrong by, and the
    -- harness now quantises the same way, so this is a belt on top of braces
    -- rather than the only thing holding it up.
    local ALPHA_STEP = 1 / 510

    local function Same(got, wanted)
        return math.abs((got or -1) - (wanted or -1)) <= ALPHA_STEP
    end

    -- DebuffBorder is deliberately NOT in this list - see below.
    local before = {
        Border = 0.90, Shadow = 0.35, IconShadow = 0.62,
        CooldownFlash = 0.44,
    }
    for key, alpha in pairs(before) do
        item[key] = item:CreateTexture()
        item[key]:SetAlpha(alpha)
        item[key]:Show()
        -- WHAT THE CLIENT ACTUALLY HOLDS, read back rather than assumed.
        -- "The alpha it HAD" is what GetAlpha says, and that is exactly what
        -- Claim records - so this is the number the restore owes us.
        before[key] = item[key]:GetAlpha()
    end
    item.SpellActivationAlert = CreateFrame("Frame", nil, item)
    item.SpellActivationAlert:SetAlpha(0.8)
    item.SpellActivationAlert:Show()
    local alertAlpha = item.SpellActivationAlert:GetAlpha()

    -- THE CHROME, matched by atlas prefix rather than by name - which is how
    -- the out-of-range veil was found on his client at all. One that must go
    -- and one that must not, so a matcher that dims everything is caught.
    local veil = item:CreateTexture()
    veil:SetAtlas("UI-CooldownManager-OORshadow")
    veil:SetAlpha(0.5)
    veil:Show()
    local veilAlpha = veil:GetAlpha()

    local stranger = item:CreateTexture()
    stranger:SetAtlas("SomebodyElses-Decoration")
    stranger:SetAlpha(0.7)
    stranger:Show()
    local strangerAlpha = stranger:GetAlpha()

    -- The rounded corners. The mask belongs to the TEXTURE it masks, so it
    -- has to come off the icon rather than be redefined - measured with
    -- /zs skin, and the reason a whole release of icons stayed round.
    local mask = item:CreateMaskTexture()
    item.Icon:AddMaskTexture(mask)

    Check("An icon starts out wearing Blizzard's mask",
        item.Icon:GetNumMaskTextures() == 1)

    -- A DECORATION THIS TEMPLATE DOES NOT HAVE. Blizzard's item templates are
    -- not one shape - CooldownFlash is on some and not others - so "absent"
    -- is the ordinary case rather than the broken one and has to cost exactly
    -- nothing. No fixture covered it until it was written down.
    --
    -- ASSERTED BY BEHAVIOUR RATHER THAN BY `== nil`, because out on the desk
    -- the harness cannot tell a Blizzard FIELD from a method: every unread
    -- PascalCase key answers with a function there, and in the client it
    -- answers nil. Both are things that are not a region, which is the only
    -- distinction this code makes and therefore the only one worth asking
    -- about.

    ---------------------------------------------------------------------
    -- Taking it
    ---------------------------------------------------------------------
    Claim.Strip(item)

    Check("Every named decoration goes quiet",
        item.Border:GetAlpha() == 0 and item.Shadow:GetAlpha() == 0
        and item.IconShadow:GetAlpha() == 0
        and item.CooldownFlash:GetAlpha() == 0)
    Check("A decoration this template does not have costs nothing",
        pcall(Claim.Strip, item) and item.Border:GetAlpha() == 0)
    Check("And the alert is hidden as well as silenced",
        item.SpellActivationAlert:GetAlpha() == 0
        and not item.SpellActivationAlert:IsShown())
    Check("The out-of-range veil goes with them, matched by its atlas",
        veil:GetAlpha() == 0)
    Check("Somebody else's texture is left exactly alone",
        Same(stranger:GetAlpha(), strangerAlpha), tostring(stranger:GetAlpha()))
    Check("The mask comes OFF the icon, not redefined",
        item.Icon:GetNumMaskTextures() == 0)

    -- BLIZZARD WRITES THE ALPHA BACK. The out-of-range veil is driven by
    -- range, so a single SetAlpha(0) returns the moment you walk anywhere.
    -- This is the one hook that cannot be checked by reading the source.
    item.Border:SetAlpha(0.9)
    Check("A decoration Blizzard turns back on goes quiet again",
        item.Border:GetAlpha() == 0, tostring(item.Border:GetAlpha()))

    ---------------------------------------------------------------------
    -- Holding it where we put it
    ---------------------------------------------------------------------
    local slot = CreateFrame("Frame")

    -- HOW MANY WERE PLACED BEFORE THIS SUITE PLACED ONE.
    --
    -- Claim.Placed() counts EVERY frame this addon is holding an anchor for,
    -- across the whole session - not the ones this test made. On the desk
    -- nothing else is running and it answered 1 and then 0, so `== 1` and
    -- `== 0` looked like statements about this frame. In HIS client the bars
    -- are up and drawing while /zs test runs, so it counts his cells too, and
    -- both lines went red on a Claim that is working perfectly.
    --
    -- That is a test asserting THE WORLD rather than the code, and it is the
    -- second time in this file: `mine.fo == 1` once meant "you happen to have
    -- food up". The rule from it is the fix here - measure the DELTA the code
    -- caused, never the absolute the client happens to be at.
    local placedBefore = Claim.Placed()

    Claim.Place(item, { "CENTER", slot, "CENTER", 0, 0 }, 40, 40)
    Claim.Reveal(item)

    local point, relativeTo = item:GetPoint(1)
    Check("A claimed frame sits on the slot we gave it",
        point == "CENTER" and relativeTo == slot)
    Check("At the size we asked for", item:GetWidth() == 40)
    Check("And it is on screen", item:GetAlpha() == 1)
    Check("One frame more is placed than was", Claim.Placed() == placedBefore + 1,
        string.format("%s, was %s", tostring(Claim.Placed()),
            tostring(placedBefore)))

    -- BLIZZARD'S OWN LAYOUT PASS. There is no event for it and no polling
    -- either - the hook re-asserts from inside their own SetPoint, and this
    -- assertion is the whole mechanism wave 2 stands on.
    --
    -- CLEARED FIRST, exactly as their layout pass does, and the first draft of
    -- this line did not - so it appended a second anchor, GetPoint(1) went on
    -- answering with OUR one, and the check passed with the hook removed
    -- entirely. A check that cannot fail is not a check; this was proved by
    -- putting the no-op hook back and watching this line stay green.
    item:ClearAllPoints()
    item:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 500, -500)
    point, relativeTo = item:GetPoint(1)
    Check("A relayout by Blizzard does not move it",
        point == "CENTER" and relativeTo == slot, tostring(point))

    item:SetSize(999, 999)
    Check("And nor does a resize", item:GetWidth() == 40,
        tostring(item:GetWidth()))

    Claim.Veil(item)
    item:SetAlpha(0.5)
    Check("A veiled frame stays veiled", item:GetAlpha() == 0)

    ---------------------------------------------------------------------
    -- THE ONE REGION ON THE FRAME THAT HAS NO NAME
    --
    -- Blizzard's countdown number is a FontString the Cooldown owns and does
    -- not publish. Text.lua reaches it by walking GetRegions and changes
    -- three things about it - font, colour and where it sits - and Claim.Give
    -- walked a list of NAMED parts, so none of the three was coming back.
    -- Rule 4 held for everything with a name and quietly did not for this.
    ---------------------------------------------------------------------
    local counter = item.Cooldown:CreateFontString(nil, "OVERLAY")
    counter:SetFont([[Fonts\FRIZQT__.TTF]], 14, "OUTLINE")
    counter:SetTextColor(1, 1, 1, 1)
    counter:ClearAllPoints()
    counter:SetPoint("CENTER", item.Cooldown, "CENTER", 0, 0)

    Claim.Set(counter, "SetFont", [[Fonts\ARIALN.TTF]], 22, "")
    Claim.Set(counter, "SetTextColor", 1, 0, 0, 1)
    Claim.Anchor(counter, "BOTTOMRIGHT", item, "BOTTOMRIGHT", -3, 3)

    -- A FONT SIZE DOES NOT COME BACK AS THE NUMBER YOU GAVE IT.
    --
    -- The same lesson as ALPHA_STEP above, on a second value, and it cost the
    -- same thing: two checks red in his client against a round trip that was
    -- working. A FontString's size goes through the UI scale and is kept as a
    -- 32-bit float, so it comes back a rounding error away. Measured, from his
    -- own log rather than reasoned about:
    --
    --     SetFont(..., 22, ...)  ->  GetFont() = 22.000001907349
    --     SetFont(..., 14, ...)  ->  GetFont() = 13.999999046326
    --
    -- The desk CANNOT reproduce this - its stub has no UI scale and hands back
    -- exactly what it was given - so unlike the alpha case there is no braces
    -- under this belt, and the tolerance is the whole of it. Near's default is
    -- a hundredth, which is six thousand times the error above and still
    -- nowhere near 14 against 22.
    local _, styledSize = counter:GetFont()
    local styledPoint = counter:GetPoint(1)
    Check("A counter takes our font and our place",
        Near(styledSize, 22) and styledPoint == "BOTTOMRIGHT",
        tostring(styledSize) .. " " .. tostring(styledPoint))

    ---------------------------------------------------------------------
    -- LETTING GO. Everything above, undone.
    ---------------------------------------------------------------------
    Check("Giving a frame back reports that it had one", Claim.Give(item))

    -- Near FOR THE SIZE, exactly as the styled check above and for the
    -- reason the long comment above it measures out. That comment documented
    -- 13.999999046326 FROM HIS LOG and the line under it still said `== 14`
    -- - the first check got the tolerance when he reported it, its twin five
    -- lines down did not, and his client duly went red on the twin a week
    -- later. The harness models the UI-scale rounding now, so the desk goes
    -- red on an `==` here before he can.
    local _, counterSize = counter:GetFont()
    local counterRed = counter:GetTextColor()
    Check("An unnamed counter gets its font, colour and place back too",
        Near(counterSize, 14) and Same(counterRed, 1)
        and (counter:GetPoint(1)) == "CENTER",
        string.format("size %s, red %s, point %s", tostring(counterSize),
            tostring(counterRed), tostring((counter:GetPoint(1)))))

    local restored = true
    for key, alpha in pairs(before) do
        if not Same(item[key]:GetAlpha(), alpha) then restored = false end
    end
    Check("Every decoration comes back at the alpha it HAD, not at 1",
        restored, string.format("border %s, wanted %s",
            tostring(item.Border:GetAlpha()), tostring(before.Border)))
    Check("The alert is shown again too",
        Same(item.SpellActivationAlert:GetAlpha(), alertAlpha)
        and item.SpellActivationAlert:IsShown())
    Check("So does the out-of-range veil", Same(veil:GetAlpha(), veilAlpha))
    Check("The rounded corners go back on", item.Icon:GetNumMaskTextures() == 1)
    Check("The frame is visible again", item:GetAlpha() == 1)
    Check("This one is not placed any more", Claim.Placed() == placedBefore,
        string.format("%s, was %s", tostring(Claim.Placed()),
            tostring(placedBefore)))
    Check("And we hold no record of it", ns.Cooldowns.Known(item) == nil)

    -- THE HOOKS CANNOT BE REMOVED, so the proof that letting go is real is
    -- that they no longer DO anything. Blizzard drives the frame again.
    item.Border:SetAlpha(0.25)
    Check("A released decoration is Blizzard's to drive again",
        Same(item.Border:GetAlpha(), 0.25), tostring(item.Border:GetAlpha()))

    -- CLEARED FIRST, because SetPoint ADDS a point rather than replacing one -
    -- in the client and in the harness alike. Asserting on GetPoint(1) after a
    -- bare SetPoint reads the anchor that was already there and would pass
    -- against a frame that is still being re-asserted, which is the opposite
    -- of what this line is for.
    item:ClearAllPoints()
    item:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 7, 7)
    Check("And a released frame can be moved by anyone",
        (item:GetPoint(1)) == "TOPLEFT", tostring((item:GetPoint(1))))

    Check("Giving back something we never held says so",
        Claim.Give(CreateFrame("Frame")) == false)
end

---------------------------------------------------------------------------
-- PLACING A WHOLE BAR
--
-- The three files in one pass: Store reads the bar, Model says where each
-- cell goes, Claim writes it. Run against a Cooldown Manager built here out
-- of frames of ours.
--
-- NOT RUN IN HIS CLIENT, and that is a safety rule rather than a limitation.
-- Faking the viewers means writing four globals that Blizzard owns, and a
-- suite that threw halfway would leave his Cooldown Manager replaced by a
-- stub for the rest of the session. Where the real ones exist, the real ones
-- win and this says so.
---------------------------------------------------------------------------
local function TestCooldownRender()
    local Render = ns.Cooldowns and ns.Cooldowns.Render
    if not Render then
        Skip("Placing a bar", "Cooldowns/Render.lua is not loaded")
        return
    end

    for _, viewer in ipairs(ns.CDM.VIEWERS) do
        if _G[viewer.global] then
            Skip("Placing a bar", "the real Cooldown Manager is up - a fake "
                .. "one would have to overwrite it")
            return
        end
    end

    -- THE WORLD, built and taken down again. Three spells; the middle one has
    -- no frame, which is the case that has to leave a HOLE rather than close
    -- up - a fixed grid means a spell is always in the same place.
    -- Icon AND Cooldown, because Blizzard's item template carries both and
    -- the stripper reaches for both. A fixture missing one is a fixture that
    -- proves the code survives a frame nobody has.
    local function FakeItem(spellID)
        local item = CreateFrame("Frame")
        item.GetSpellID = function() return spellID end
        item.Icon = item:CreateTexture()
        item.Cooldown = CreateFrame("Frame", nil, item)
        return item
    end

    local first, third, spare = FakeItem(1022), FakeItem(31850), FakeItem(642)

    local pool = { items = { first, third, spare } }
    function pool:EnumerateActive()
        local index = 0
        return function()
            index = index + 1
            return self.items[index]
        end
    end

    local viewer = CreateFrame("Frame")
    viewer.itemFramePool = pool
    viewer:Show()

    local saved = {
        bars = ns.db.bars,
        module = ns.db.modules and ns.db.modules.cooldowns,
        takeover = ns.db.takeOverCDM,
        available = ns.CDM.available,
        built = ns.CDM.indexBuilt,
        started = Render.started,
    }

    _G[ns.CDM.VIEWERS[1].global] = viewer
    ns.db.modules = ns.db.modules or {}
    ns.db.modules.cooldowns = true
    ns.db.takeOverCDM = true
    ns.CDM.available = nil
    -- AND THE INDEX HAS TO BE INVALIDATED, which is the whole reason the
    -- first run of this suite reported that a three-cell bar found nothing.
    -- ItemForSpell rebuilds on the FIRST read and then trusts itself, and by
    -- the time this suite runs an earlier one has already marked it built -
    -- against a world with no viewers in it. A stale empty index and a spell
    -- Blizzard genuinely is not showing are the same answer.
    ns.CDM.indexBuilt = nil

    -- HIS OWN BAR'S SHAPE: three across, 40px icons, a gap of 4.
    ns.db.bars = { {
        id = 9001, name = "desk", enabled = true,
        rows = 1, columns = 3, kind = "icon",
        iconSize = 40, spacing = 4, lineSpacing = 4,
        layout = "grid", flow = "rows", growX = "right", growY = "down",
        point = "CENTER", relPoint = "CENTER", x = 0, y = -200, scale = 1,
        cells = { 1022, 86659, 31850 },
    } }

    local ok, err = pcall(function()
        local drawn = Render.Refresh()
        Check("Two of the three cells found a live frame", drawn == 2,
            tostring(drawn))

        local container = Render.Containers()[9001]
        Check("The bar got a container", container ~= nil)
        if not container then return end

        -- 3 cells of 40 with two gaps of 4 = 128 wide.
        Check("Sized to what the model measured, not to a formula",
            container:GetWidth() == 128 and container:GetHeight() == 40,
            string.format("%sx%s", tostring(container:GetWidth()),
                tostring(container:GetHeight())))

        local point, relativeTo, _, x, y = container:GetPoint(1)
        Check("And placed where the profile says",
            point == "CENTER" and relativeTo == UIParent and x == 0
            and y == -200)

        -- Cell 1 sits 44 left of the box centre, cell 3 sits 44 right.
        local _, _, _, x1 = container.cells[1]:GetPoint(1)
        local _, _, _, x3 = container.cells[3]:GetPoint(1)
        Check("The first and last cell straddle the centre evenly",
            x1 == -44 and x3 == 44,
            string.format("%s and %s", tostring(x1), tostring(x3)))

        -- THE HOLE. Its spell has no frame, and the cell stays exactly where
        -- it was: closing the gap is a setting, and it belongs to the wave
        -- that owns the setting.
        local _, _, _, x2 = container.cells[2]:GetPoint(1)
        Check("A cell with no frame leaves a hole rather than closing up",
            x2 == 0, tostring(x2))

        local anchored, onCell = first:GetPoint(1)
        Check("Blizzard's frame is anchored to OUR cell",
            onCell == container.cells[1], tostring(anchored))
        Check("At an offset of zero, which is the same in every scale",
            select(4, first:GetPoint(1)) == 0)
        Check("Sized to the slot", first:GetWidth() == 40)
        Check("The claimed frames are on screen",
            first:GetAlpha() == 1 and third:GetAlpha() == 1)

        -- THE TAKEOVER. A frame the user never placed is veiled, never
        -- hidden - hiding one is what taints it.
        Check("A cooldown nobody placed is veiled, not hidden",
            spare:GetAlpha() == 0 and spare:IsShown() == false
                or spare:GetAlpha() == 0)
        Check("Three frames are held", ns.Cooldowns.Held() == 3)

        ---------------------------------------------------------------
        -- SWITCHING IT OFF, which is the release condition again
        ---------------------------------------------------------------
        ns.db.modules.cooldowns = false
        Render.Refresh()

        Check("Switching the module off hands every frame back",
            ns.Cooldowns.Held() == 0, tostring(ns.Cooldowns.Held()))
        Check("Including the ones it had only veiled",
            spare:GetAlpha() == 1, tostring(spare:GetAlpha()))
        Check("And our own scaffolding leaves the screen",
            container:IsShown() == false)

        ---------------------------------------------------------------
        -- AND THE MOVER, IN THE SAME WORLD
        --
        -- Its own suite skips on this desk and skips in his client too
        -- unless a bar happens to be on screen - and a check that never runs
        -- is not a lenient check, it is an absent one. There is a bar on
        -- screen right here, built two paragraphs up, so this is the one
        -- place the question can actually be asked without a client.
        ---------------------------------------------------------------
        ns.db.modules.cooldowns = true
        Render.Refresh()

        local wasUnlocked = ns.EditMode:IsUnlocked()
        ns.EditMode:SetUnlocked(true)
        ns.EditMode:Refresh()

        local movers = ns.EditMode.BarMovers and ns.EditMode:BarMovers() or {}
        Check("A bar on screen gets a mover", #movers == 1, tostring(#movers))

        local mover = movers[1]
        if mover then
            Check("The mover has the cog and the padlock every other one has",
                mover.cog ~= nil and mover.lock ~= nil
                and type(mover.RefreshLock) == "function")
            -- POOLED BY POSITION, PAIRED BY ID. This is the one thing these
            -- movers can get wrong that the panels cannot: delete the bar
            -- above and mover 3 is now bar 4's, so anything that closed over
            -- an id at build time would drag the wrong bar.
            Check("And it names the bar it drags", mover.dkBarID == 9001,
                tostring(mover.dkBarID))

            local cfg = mover.spec and mover.spec.config()
            Check("Its settings are that bar", cfg ~= nil and cfg.id == 9001)

            if cfg then
                local start = mover:GetScript("OnDragStart")
                cfg.pinned = true
                mover.grab = nil
                if start then start(mover) end
                Check("A pinned bar refuses to be dragged", mover.grab == nil)

                cfg.pinned = false
                mover.grab = nil
                if start then start(mover) end
                Check("An unpinned one takes the drag", mover.grab ~= nil)
                mover.grab = nil

                -- AND THE DRAG WRITES WHERE THE BAR IS. The mover existing
                -- and the drag doing something are two questions, and the
                -- taunt button shipped a whole release answering only the
                -- first.
                mover.spec.apply(120, -340)
                Check("Moving it writes the bar's position",
                    cfg.x == 120 and cfg.y == -340,
                    string.format("%s,%s", tostring(cfg.x), tostring(cfg.y)))
            end
        end

        ns.EditMode:SetUnlocked(wasUnlocked)
        ns.db.modules.cooldowns = false
        Render.Refresh()
    end)

    -- PUT THE WORLD BACK WHATEVER HAPPENED. A suite that throws halfway and
    -- leaves a fake viewer in a global is the "a test that writes must put it
    -- back" lesson with a Blizzard frame on the end of it.
    --
    -- Render.Stop is itself pcall'd, and that is not belt and braces: it was
    -- the FIRST line here, it threw on a fixture of mine, and every line below
    -- it - the fake viewer, his bars, his module switch - was never reached.
    -- The profile guard caught it and said "db.modules.cooldowns: true became
    -- false", which is a settings change left behind by a test. Cleanup that
    -- can throw has to be cleanup that cannot stop the rest of the cleanup.
    pcall(Render.Stop)
    _G[ns.CDM.VIEWERS[1].global] = nil
    ns.db.bars = saved.bars
    if ns.db.modules then ns.db.modules.cooldowns = saved.module end
    ns.db.takeOverCDM = saved.takeover
    ns.CDM.available = saved.available
    ns.CDM.indexBuilt = saved.built
    Render.started = saved.started

    if not ok then error(err, 0) end
end

---------------------------------------------------------------------------
-- A TAB YOU HAVE NOT PRESSED IS NOT BUILT
--
-- Written because the red proof found two holes that every guard in the
-- window was blind to, and both are the kind a user meets on the first click:
--
--   * a tab that BUILDS and is never REFRESHED shows every control at its
--     build-time value instead of yours. Nothing about that looks like a
--     refresh problem - it looks like the addon forgetting your settings.
--   * a page whose FIRST tab is deferred opens empty. No current page does
--     that, because the tab on screen is built at once - and "no caller
--     exercises it" is exactly the state a rule is in the day before somebody
--     writes the caller.
--
-- Driven through the real calls rather than through a page, so the rule is
-- proved once here and every page that uses it inherits the proof.
---------------------------------------------------------------------------
local function TestLazyTabs()
    if not (ns.UI and ns.UI.Page) then
        Skip("Deferred tabs", "the widget layer is not loaded")
        return
    end

    local host = CreateFrame("Frame", nil, UIParent)
    host:SetWidth(400)
    host:Hide()

    local grid = ns.UI.Page(host, 400, { single = true })
    if type(grid.LazyTab) ~= "function" then
        Skip("Deferred tabs", "Grid:LazyTab is not there")
        return
    end

    local first, second, refreshed = 0, 0, 0

    -- THE FIRST TAB IS THE ONE ON SCREEN, so it is built at once. A page that
    -- opens on an empty tab is worth more than the frames it would save.
    grid:LazyTab("One", function(g)
        first = first + 1
        g:Tab("One")
        g.widgets[#g.widgets + 1] = {
            Refresh = function() refreshed = refreshed + 1 end,
        }
    end)
    Check("The tab a page opens on is built at once, never left empty",
        first == 1, tostring(first))

    grid:LazyTab("Two", function(g)
        second = second + 1
        g:Tab("Two")
    end)
    Check("A tab nobody has pressed is not built at all", second == 0,
        tostring(second))

    refreshed = 0
    grid:ShowTab("Two")
    Check("Pressing it builds it", second == 1, tostring(second))

    -- AND EVERYTHING ON THE PAGE IS REFRESHED. A control created this second
    -- carries whatever its constructor gave it; the value it should show is
    -- in the profile, and only a refresh goes and reads that.
    Check("and the page is refreshed, so no control shows a build-time value",
        refreshed > 0, tostring(refreshed))

    grid:ShowTab("One")
    grid:ShowTab("Two")
    Check("Pressing it again does not build a second copy of it",
        second == 1, tostring(second))

    -- AND THE BOOKKEEPING SURVIVES IT. RealiseTabs is what the desk uses to
    -- get the whole window back before it audits anything, and a tab already
    -- built must not count - a number that never falls to nought is a number
    -- nobody can read.
    Check("Nothing is left to realise once every tab has been pressed",
        grid:RealiseTabs() == 0)
end

---------------------------------------------------------------------------
-- THE PLACES WE DRAW OURSELVES
--
-- Wave 6's whole claim is that a bar-shaped place is OURS again, and the one
-- thing that has to be true about it is the one that was got wrong twice with
-- Blizzard's frame: THE FILL IS THE CELL MINUS THE ICON. Not a height taken
-- once, not a rectangle straddling two frames - four edges, all four of them
-- the cell's own, so "Bar height" reaches the coloured bar because the
-- coloured bar IS the cell.
--
-- BOTH TIMES IT WAS WRONG THE OPTIONS PREVIEW AGREED WITH ITSELF, which is
-- why this is a check and not a screenshot: the preview draws the icon and the
-- fill out of ONE rectangle and the screen has two, so a fill hung between
-- them looks right in exactly one of the two pictures.
---------------------------------------------------------------------------
local function TestCooldownOwn()
    local Own = ns.Cooldowns and ns.Cooldowns.Own
    local Render = ns.Cooldowns and ns.Cooldowns.Render
    if not (Own and Render) then
        Skip("Places we draw ourselves", "Cooldowns/Own.lua is not loaded")
        return
    end

    ---------------------------------------------------------------------
    -- THE GEOMETRY, WITHOUT A FRAME
    ---------------------------------------------------------------------
    local square = Own.Parts({ w = 40, h = 40 }, "left")
    Check("A square place is all icon and has no band",
        square.wide == false and square.fill == nil and square.band == nil
            and square.icon.size == 40)

    local left = Own.Parts({ w = 200, h = 24 }, "left")
    Check("A bar keeps its icon SQUARE at the bar's height",
        left.icon.side == "LEFT" and left.icon.size == 24,
        tostring(left.icon and left.icon.size))
    -- THE SEAM. The fill starting anywhere but the icon's far edge is either a
    -- gap nobody asked for or a fill drawn under the picture.
    Check("and the fill takes exactly what the icon leaves",
        left.fill.left == left.icon.size and left.fill.right == 0,
        string.format("%s/%s", tostring(left.fill.left),
            tostring(left.fill.right)))
    Check("and the name's band starts where the icon ends", left.band == 24)

    local right = Own.Parts({ w = 200, h = 24 }, "right")
    Check("An icon on the right pushes the fill the other way",
        right.icon.side == "RIGHT" and right.fill.left == 0
            and right.fill.right == 24)

    -- A HIDDEN ICON IS STILL A BAR WITH A NAME ON IT. Reading "no icon" as "no
    -- band" is what took the name off every bar whose owner had switched the
    -- icon off - and it is a one-character difference in the guard.
    local none = Own.Parts({ w = 200, h = 24 }, "hidden")
    Check("A hidden icon leaves the whole cell to the fill",
        none.icon == nil and none.fill.left == 0 and none.fill.right == 0)
    Check("and the name still has a band to sit in", none.band == 0)

    ---------------------------------------------------------------------
    -- THE NUMBER RULE, AND THE BRANCH WAVE 6 WOULD HAVE BROKEN
    --
    -- On a place we draw, Blizzard's own counter frame is still SHOWN in the
    -- sense the API means and is at alpha 0 in the sense the user means.
    -- Deferring to it there empties the corner - which is exactly the number
    -- the owner asked for three times.
    ---------------------------------------------------------------------
    ---------------------------------------------------------------------
    -- A COUNTER THAT WILL NOT SAY WHETHER IT IS SHOWN
    --
    -- His client, four times in one pass, on a bar that was drawing:
    --
    --     CDM.lua:1103: attempt to perform boolean test on local 'shown'
    --     (a secret boolean value, while execution tainted by 'ZwoelfStuff')
    --
    -- IsShown can hand back a SECRET boolean - a counter whose visibility was
    -- decided from a stack count we may not read is itself unreadable - and
    -- the pcall around the CALL does nothing for what happens to the ANSWER.
    -- It threw out of a reader whose whole promise is that it never does, and
    -- took the listener that called it with it.
    --
    -- ASKED AT RUNTIME rather than only in the source. The desk guard reads
    -- shapes and is what found this one; this hands a real secret to the real
    -- function and asks what it answers. It can only run at all because the
    -- harness now has issecretvalue - without it CanCompute says yes to
    -- everything out here and this check cannot fail.
    ---------------------------------------------------------------------
    if _G.__SECRET and issecretvalue and issecretvalue(_G.__SECRET) then
        local coy = CreateFrame("Frame")
        coy.Applications = CreateFrame("Frame", nil, coy)
        coy.Applications.IsShown = function() return _G.__SECRET end

        local said = ns.CDM:CounterShown(coy, "Applications")
        Check("A counter that will not say is answered with 'cannot tell'",
            said == nil, tostring(said))

        -- AND THE THIRD ANSWER REACHES THE DECISION IT WAS MADE FOR: nil is
        -- not false. False is Blizzard saying it looked at a count and decided
        -- it was not worth a number - final. Nil is nobody having said
        -- anything, and on a place we draw that means we judge it ourselves,
        -- which is the number he asked for three times.
        Check("and a place we draw still writes its own number",
            ns.Cooldowns.Text.StackToShow(said, 3, true) == 3)
    else
        Skip("A counter that will not say", "this client cannot make a secret")
    end

    -- THE `ours` BRANCH, WHICH WENT OUT ONCE AND TOOK THE NUMBERS WITH IT.
    -- On a place we draw, Blizzard's counter frame is "shown" in the API
    -- sense and invisible in the user's - the item under it is veiled, and
    -- the engine does not feed a veiled item's counter even when the string
    -- is told to ignore the alpha. So "shown" may not stand our own number
    -- down there; the count goes out through us.
    local Text = ns.Cooldowns.Text
    Check("On a borrowed place we leave Blizzard's number alone",
        Text.StackToShow(true, 3) == nil)
    Check("On one we draw, that same number is ours to write",
        Text.StackToShow(true, 3, true) == 3,
        tostring(Text.StackToShow(true, 3, true)))
    -- AND THE HALF THAT MUST NOT MOVE. `false` is Blizzard saying it looked at
    -- a count we may not look at and decided it was not worth a number. That
    -- is the only legal comparison on this patch and it is final on both kinds.
    Check("Blizzard deciding a count is not worth showing is still final",
        Text.StackToShow(false, 3, true) == nil)
    Check("and with no counter frame at all we judge it ourselves",
        Text.StackToShow(nil, 3, true) == 3
            and Text.StackToShow(nil, 1, true) == nil)

    ---------------------------------------------------------------------
    -- A FLAT FILL IS A RAMP OF ONE COLOUR
    --
    -- It used to be white at both ends, on the reasoning that white
    -- multiplies to one. SetGradient REPLACES the vertex colour, so every
    -- flat bar in the addon drew pure white - and the first evidence was a
    -- photograph of one, because there is no GetGradient to ask.
    ---------------------------------------------------------------------
    local Fill = ns.Cooldowns.Fill
    local _, near, far, opacity = Fill.Ramp({ 1, 0, 0 }, 0.85, nil)
    Check("A flat fill puts its own colour at BOTH ends, never white",
        near[1] == 1 and near[2] == 0 and far[1] == 1 and far[2] == 0,
        string.format("%s,%s,%s to %s,%s,%s", tostring(near[1]),
            tostring(near[2]), tostring(near[3]), tostring(far[1]),
            tostring(far[2]), tostring(far[3])))
    Check("and carries the alpha it was given", opacity == 0.85,
        tostring(opacity))

    local orientation, one, two = Fill.Ramp({ 1, 0, 0 }, 1,
        { on = true, color = { 0, 0, 1 }, direction = "right" })
    Check("A real ramp still runs from the fill colour to the second one",
        one[1] == 1 and two[3] == 1 and orientation == "HORIZONTAL",
        string.format("%s -> %s", tostring(one[1]), tostring(two[3])))

    -- AND THE SWAP IS A SWAP OF THE PAIR, not of the orientation only: a ramp
    -- that runs the other way is the same two colours in the other order.
    local _, back, front = Fill.Ramp({ 1, 0, 0 }, 1,
        { on = true, color = { 0, 0, 1 }, direction = "left" })
    Check("and the other direction is the same pair, reversed",
        back[3] == 1 and front[1] == 1,
        string.format("%s -> %s", tostring(back[3]), tostring(front[1])))

    ---------------------------------------------------------------------
    -- THE TROUGH BEHIND THE FILL
    --
    -- Owner, with the Fill tab open: "wir brauchen hier eine bg farbe fuer den
    -- bar fill." OFF for a bar that never said, and that is the half worth a
    -- check: every bar he has arranged looks the way it does because the empty
    -- part shows the cell's backdrop, and a default of ON would have repainted
    -- all nine of them for a setting nobody chose.
    ---------------------------------------------------------------------
    Check("A bar that never asked for a trough does not get one",
        Fill.Paint({}, 1).back.on == false)

    local trough = Fill.Paint({ fillBack = true, fillBackColor = { 0, 0, 1 },
        fillBackAlpha = 0.4 }, 1).back
    Check("One that did gets its own colour and opacity",
        trough.on == true and trough.color[3] == 1 and trough.alpha == 0.4,
        string.format("%s %s", tostring(trough.color[3]),
            tostring(trough.alpha)))

    -- AND THE CELL'S OWN ANSWER WINS, like every other key on this tab. His
    -- "Bars 2" carries five look keys on cell 1 alone, so a reader that only
    -- looked at bar level would throw away styling he set by hand.
    local perCell = Fill.Paint({ fillBack = false,
        cellOpts = { [2] = { look = { fillBack = true } } } }, 2).back
    Check("and a place with its own answer keeps it", perCell.on == true)

    -- THE WIRING, NOT THE RULE. Store.Option's own suite proves the three
    -- levels and their order; these two prove that the two things which
    -- actually paint go THROUGH it. That has been a different answer twice in
    -- this file's history - a rule green on its own while nothing asked it.
    local bySpell = Fill.Paint({ cells = { 77535 }, fillColor = { 1, 0, 0 },
        cellLook = { [77535] = { fillColor = { 0, 0, 1 } } } }, 1)
    Check("The fill's paint reads the place's own colour, keyed by spell",
        bySpell.color[3] == 1 and bySpell.color[1] == 0,
        string.format("%s,%s,%s", tostring(bySpell.color[1]),
            tostring(bySpell.color[2]), tostring(bySpell.color[3])))

    local lookBySpell = ns.Cooldowns.Look.Style({ cells = { 77535 },
        borderSize = 2,
        cellLook = { [77535] = { borderSize = 6 } } }, 1)
    Check("and the look resolver does the same for its eighteen keys",
        lookBySpell.borderSize == 6, tostring(lookBySpell.borderSize))

    ---------------------------------------------------------------------
    -- AND NOW ONE, DRAWN, THROUGH THE WHOLE RENDER PASS
    ---------------------------------------------------------------------
    for _, viewer in ipairs(ns.CDM.VIEWERS) do
        if _G[viewer.global] then
            Skip("A bar-shaped place, drawn", "the real Cooldown Manager is "
                .. "up - a fake one would have to overwrite it")
            return
        end
    end

    -- BLIZZARD'S TRACKED BAR, AS FAR AS THIS ADDON READS ONE: a frame with a
    -- StatusBar in it, and TWO nameless font strings in that - the first the
    -- spell's name and the second the timer. That order is Blizzard's and the
    -- mirror counts on it, so the fixture reproduces it rather than naming it.
    local mirror
    local function FakeBar(spellID)
        local item = CreateFrame("Frame")
        item.GetSpellID = function() return spellID end
        item.Icon = item:CreateTexture()
        item.Bar = CreateFrame("StatusBar", nil, item)
        item.Bar:CreateFontString()
        local timer = item.Bar:CreateFontString()
        timer:SetText("12.3")
        item.Bar:SetMinMaxValues(0, 30)
        item.Bar:SetValue(18)
        -- A stack count Blizzard would draw and cannot be seen drawing. The
        -- FRAME carries a STRING inside it, exactly as the client's does -
        -- CDM:CounterText walks the regions to find it, and a bare frame
        -- here left the relay path unreachable at the desk.
        item.Applications = CreateFrame("Frame", nil, item)
        item.Applications:CreateFontString(nil, "OVERLAY")
        item.Applications:Show()
        item.auraDataCached = { applications = 3 }
        -- IT ANSWERS IsActive, AND THAT IS A FIXTURE DETAIL WITH TEETH.
        --
        -- It used to model "the buff is up" by being SHOWN, because
        -- CDM:ItemIsActive fell back to IsShown for a frame with no IsActive.
        -- That fallback is gone - IsShown is Blizzard's answer to "is this
        -- usable on your target", not to "is the buff up", and reading one
        -- for the other is what greyed his icons the moment he clicked a mob.
        --
        -- So the fixture answers the question a real buff-bar item answers.
        -- Keeping the old shape would have been a fixture proving a path the
        -- addon no longer takes, which is worse than no fixture: it passes.
        item.hxUp = true
        item.IsActive = function(this) return this.hxUp and true or false end
        item:Show()
        mirror = item.Bar
        return item
    end

    local bars = FakeBar(77535)

    -- A POOL THAT HANDS OUT ITS ITEMS WITHOUT BUILDING ANYTHING TO DO IT.
    --
    -- The first version returned a fresh closure per call, and a check that
    -- measures how much a loop allocates then measured the FIXTURE: the buff
    -- sweep below reported 25.4 KB over 200 polls against code that allocates
    -- nothing. Third time this exact shape has fooled a resource check here.
    --
    -- Blizzard's own is `return pairs(self.activeObjects)` - a shared iterator
    -- and no allocation - so this is closer to the client as well as quieter.
    -- The index lives on the pool, which is what lets the iterator be one
    -- function rather than one per enumeration.
    local function NextActive(this)
        this.index = this.index + 1
        return this.items[this.index]
    end

    local pool = { items = { bars }, index = 0 }
    function pool:EnumerateActive()
        self.index = 0
        return NextActive, self
    end

    -- THE FOURTH VIEWER, which is the one whose kind is "bar". Own.Wanted asks
    -- the item's SHAPE and the shape comes from the viewer it was found in, so
    -- putting the fixture anywhere else would test the icon path under a name
    -- that says otherwise.
    local viewerFrame = CreateFrame("Frame")
    viewerFrame.itemFramePool = pool
    viewerFrame:Show()

    local saved = {
        bars = ns.db.bars,
        module = ns.db.modules and ns.db.modules.cooldowns,
        takeover = ns.db.takeOverCDM,
        available = ns.CDM.available,
        built = ns.CDM.indexBuilt,
        started = Render.started,
    }

    _G[ns.CDM.VIEWERS[4].global] = viewerFrame
    ns.db.modules = ns.db.modules or {}
    ns.db.modules.cooldowns = true
    ns.db.takeOverCDM = true
    ns.CDM.available = nil
    ns.CDM.indexBuilt = nil

    ns.db.bars = { {
        id = 9101, name = "desk bar", enabled = true,
        kind = "bar", rows = 1, columns = 1,
        barWidth = 200, barHeight = 24, iconPlacement = "left",
        spacing = 4, lineSpacing = 4,
        layout = "grid", flow = "rows", growX = "right", growY = "down",
        point = "CENTER", relPoint = "CENTER", x = 0, y = -300, scale = 1,
        -- A COLOUR NOTHING ELSE IN THE FIXTURE IS, so "did the colour arrive"
        -- and "did anything at all arrive" are different answers.
        fillColor = { 1, 0, 0 }, fillAlpha = 0.85,
        fillTexture = "ZS Flat",
        cells = { 77535 },
        -- BOTH CLOCKS ARMED, and that is what makes the two cost checks below
        -- mean anything. A bar with no effect switched on is never watched and
        -- a bar with no stack band is never fed, so the fixture as it stood
        -- measured two loops that were walking nothing at all - which is the
        -- shape of a guard that reads one line and reports green.
        effects = { readyGlow = true },
        stackThresholds = { { value = 3, color = { 0, 1, 0 }, alpha = 1 } },
        -- ON, so the two things he reported about it on 2026-08-16 can be
        -- asked at a desk: where it sits, and whether it goes out.
        showSpark = true,
    } }

    local ok, err = pcall(function()
        Check("Blizzard's own frame for it is bar-shaped",
            ns.CDM:ItemShape(ns.CDM:ItemForSpell(77535)) == "bar")
        Check("so it is one we draw ourselves",
            Own.Wanted(ns.CDM:ItemForSpell(77535)) == true)

        local drawn = Render.Refresh()
        Check("The pass drew it", drawn == 1, tostring(drawn))

        local container = Render.Containers()[9101]
        local cell = container and container.cells[1]
        Check("The place got a cell of the size the profile asks for",
            cell ~= nil and cell:GetWidth() == 200 and cell:GetHeight() == 24)
        if not cell then return end

        local own = cell.own
        Check("and a widget of ours on it", own ~= nil)
        if not own then return end

        -----------------------------------------------------------------
        -- THE FILL IS THE CELL MINUS THE ICON, and this is the check the
        -- whole file exists for.
        -----------------------------------------------------------------
        Check("The fill hangs from two corners rather than being given a size",
            own.fill:GetNumPoints() == 2,
            tostring(own.fill:GetNumPoints()))

        local p1, to1, rel1, x1, y1 = own.fill:GetPoint(1)
        local p2, to2, rel2, x2, y2 = own.fill:GetPoint(2)
        Check("Both of them are the CELL's own corners, never the icon's",
            to1 == cell and to2 == cell,
            string.format("%s and %s", tostring(to1), tostring(to2)))
        Check("Top left to top left, bottom right to bottom right",
            p1 == "TOPLEFT" and rel1 == "TOPLEFT"
                and p2 == "BOTTOMRIGHT" and rel2 == "BOTTOMRIGHT",
            string.format("%s/%s and %s/%s", tostring(p1), tostring(rel1),
                tostring(p2), tostring(rel2)))
        -- WHICH IS WHAT MAKES BAR HEIGHT REACH THE BAR: no vertical inset on
        -- either corner, so the fill is exactly as tall as the cell.
        Check("with no vertical inset, so its height IS the cell's",
            y1 == 0 and y2 == 0,
            string.format("%s and %s", tostring(y1), tostring(y2)))
        Check("and it starts exactly where the icon ends",
            x1 == own.icon:GetWidth() and x2 == 0,
            string.format("%s vs %s", tostring(x1),
                tostring(own.icon:GetWidth())))

        Check("The icon is square at the bar's height",
            own.icon:GetWidth() == 24 and own.icon:IsShown() == true,
            tostring(own.icon:GetWidth()))

        -----------------------------------------------------------------
        -- THE ICON'S OPACITY IS THE ICON'S
        --
        -- Owner, with the Look tab open: "wenn ich hier while inactive die
        -- opacity ändere, ändert sich der bar bg und das icon ... das sollten
        -- wir hier trennen, denn die option heisst ja icon." Both sliders sat
        -- under a heading that said "The icon" and faded the whole place -
        -- plate, fill, border, name and numbers - because they were spent as
        -- one SetAlpha on the cell.
        --
        -- Every other part of a place already had its own: backdropAlpha,
        -- fillAlpha, fillBackAlpha, and a colour per text element. The icon
        -- was the one that did not.
        --
        -- The fixture bar asks for no opacity at all, so both are at their
        -- defaults - which is exactly the state where "it went on the wrong
        -- object" is invisible, and why this asks the two SEPARATELY.
        -----------------------------------------------------------------
        Check("The cell itself is not what the icon's opacity dims",
            cell:GetAlpha() == 1, tostring(cell:GetAlpha()))

        local wasAlpha = ns.db.bars[1].alpha
        ns.db.bars[1].alpha = 0.4
        Render.Refresh()
        Check("The icon's opacity reaches the icon",
            math.abs(own.icon:GetAlpha() - 0.4) < 0.01,
            tostring(own.icon:GetAlpha()))
        Check("and the place around it stays where it was",
            cell:GetAlpha() == 1, tostring(cell:GetAlpha()))
        ns.db.bars[1].alpha = wasAlpha
        Render.Refresh()

        -----------------------------------------------------------------
        -- AND BLIZZARD'S FRAME RIDES THE CELL, ALIVE AND SILENT
        --
        -- It used to be veiled whole - alpha 0, unanchored - and that is
        -- the one state the engine stops feeding: counter text arrived
        -- blank with the stacks plainly up, by two different mechanisms.
        -- The working reference (EllesmereUI) keeps its child claimed,
        -- anchored, alpha 1, with the PARTS silenced one by one - so ours
        -- does too now. Alive to the engine, invisible to the user.
        -----------------------------------------------------------------
        Check("Blizzard's frame is placed on our cell, alive",
            (select(2, bars:GetPoint(1))) == cell,
            tostring(select(2, bars:GetPoint(1))))
        Check("at alpha 1, so the engine keeps feeding it",
            bars:GetAlpha() == 1 and bars:IsShown() ~= false,
            tostring(bars:GetAlpha()))
        Check("with its picture parts silenced one by one",
            (bars.Icon == nil or bars.Icon:GetAlpha() == 0)
                and (bars.Bar == nil or bars.Bar:GetAlpha() == 0)
                and (bars.Applications == nil
                    or bars.Applications:GetAlpha() == 0),
            string.format("icon %s bar %s counter %s",
                tostring(bars.Icon and bars.Icon:GetAlpha()),
                tostring(bars.Bar and bars.Bar:GetAlpha()),
                tostring(bars.Applications and bars.Applications:GetAlpha())))

        -----------------------------------------------------------------
        -- THE THREE THINGS HE SAID USED TO WORK ON A BAR
        -- "da konnte ich NAME, aufladung und restzeit anzeigen"
        -----------------------------------------------------------------
        Check("The spell name is on the bar",
            cell.caption ~= nil and cell.caption:IsShown() == true)
        -----------------------------------------------------------------
        -- THE NUMBERS ON A PLACE WE DRAW ARE OURS, and this rule has now
        -- been paid for three times. The relay copied Blizzard's string off
        -- the veiled frame and it arrived blank ("es wird nix angezeigt") -
        -- the engine writes no text into a counter nobody can see. The
        -- veil-piercing then made the counter itself visible
        -- (SetIgnoreParentAlpha, anchored onto our cell) and the engine
        -- STILL fed it nothing ("die aufladungen bei den bars jetzt auch
        -- weg") - its updates key on the item, not on the string. So we
        -- write our own, from sources this addon can hold, which is the
        -- mechanism that worked before either detour.
        -----------------------------------------------------------------
        Check("The stack count is drawn by us, and reads what Blizzard has",
            cell.stackCount ~= nil and cell.stackCount:GetText() == "3",
            cell.stackCount and cell.stackCount:GetText() or "no string")

        -- AND BLIZZARD'S OWN COUNTER IS LEFT ENTIRELY ALONE - not pierced,
        -- not moved onto our cell. A pierced counter the engine never feeds
        -- is an empty string floating on the bar, and the moment the engine
        -- DID feed it there would be two numbers in one corner.
        local counter = ns.CDM:Counter(bars, "Applications")
        Check("The veiled item's counter is not made to ignore the veil",
            counter ~= nil and counter:IsIgnoringParentAlpha() == false)
        Check("and it is not anchored onto our cell",
            counter ~= nil and (select(2, counter:GetPoint(1))) ~= cell,
            tostring(counter and select(2, counter:GetPoint(1))))

        -----------------------------------------------------------------
        -- AND THE CHARGES, WIRED AND NOT JUST THE RULE. The harness had no
        -- charge API at all, so Text.ChargesUp returned at its first guard
        -- and the whole path had never run out here - which is how the
        -- `not ours` gate could go out and take the charges on his bars
        -- with it while every desk light stayed green. 47568 is Empowered
        -- Rune Weapon in the harness: two charges, one spent.
        -----------------------------------------------------------------
        local Txt = ns.Cooldowns.Text
        local styleC = Txt.Style(ns.db.bars[1], 24)
        local itemC = CreateFrame("Frame")
        itemC.ChargeCount = CreateFrame("Frame", nil, itemC)
        itemC.ChargeCount:Show()

        local cellC = CreateFrame("Frame")
        Txt.Count(cellC, itemC, styleC, 47568, true)
        Check("A place we draw writes the charge count itself",
            cellC.chargeCount ~= nil and cellC.chargeCount:GetText() == "1"
                and cellC.chargeCount:IsShown() == true,
            cellC.chargeCount and tostring(cellC.chargeCount:GetText())
                or "no string")

        -- The other half of the same gate: on an adopted place Blizzard's
        -- counter is genuinely visible, and ours would be the second number.
        local cellD = CreateFrame("Frame")
        Txt.Count(cellD, itemC, styleC, 47568)
        Check("and beside Blizzard's visible one it stands down",
            cellD.chargeCount == nil or cellD.chargeCount:IsShown() == false,
            cellD.chargeCount and tostring(cellD.chargeCount:GetText())
                or "none")

        -----------------------------------------------------------------
        -- THE RELAY, on the state his items are actually in: our count
        -- reader DRY, Blizzard's counter shown, its string carrying the
        -- number. With the item ALIVE on the cell the engine feeds that
        -- string - that is the whole point of Claim.Quiet - and the bar
        -- hands it on exactly as it hands on the timer.
        -----------------------------------------------------------------
        local cached = bars.auraDataCached
        bars.auraDataCached = nil

        local counterString = ns.CDM:CounterText(bars, "Applications")
        Check("The fixture's counter has a string to relay",
            counterString ~= nil)
        if counterString then
            counterString:SetText("2")

            Txt.Count(cell, bars, Txt.Style(ns.db.bars[1], 24), 77535, true)
            Check("A dry count reader relays Blizzard's own string",
                cell.stackCount:GetText() == "2"
                    and cell.stackCount:IsShown() == true,
                tostring(cell.stackCount:GetText()))

            -- BLANK RELAYS AS BLANK: the buff down, the counter frame still
            -- shown, nothing in it. A relay that invented a mark here would
            -- draw noise on every empty bar all evening.
            counterString:SetText("")
            Txt.Count(cell, bars, Txt.Style(ns.db.bars[1], 24), 77535, true)
            Check("and a blank string relays as nothing visible",
                (cell.stackCount:GetText() or "") == "",
                tostring(cell.stackCount:GetText()))

            -- AND A SECRET STRING GOES THROUGH UNTOUCHED - the engine
            -- formatted it where the count was readable; == nil and SetText
            -- are the only two things that may happen to it on the way.
            if _G.__SECRET and issecretvalue and issecretvalue(_G.__SECRET) then
                counterString:SetText(_G.__SECRET)
                local ok = pcall(Txt.Count, cell, bars,
                    Txt.Style(ns.db.bars[1], 24), 77535, true)
                Check("A protected count string is relayed without a raise",
                    ok and cell.stackCount:GetText() == _G.__SECRET,
                    tostring(ok))
            end

            counterString:SetText("")
        end

        bars.auraDataCached = cached
        Txt.Count(cell, bars, Txt.Style(ns.db.bars[1], 24), 77535, true)
        Check("With the reader wet again, our own number wins over the relay",
            cell.stackCount:GetText() == "3",
            tostring(cell.stackCount:GetText()))

        -- AND THE WATCH CAN DESCRIBE THIS CELL. /zs watch is the film
        -- version of /zs text; Glance is its one reading, exported so the
        -- desk can hold it still. It must never touch what it describes.
        local glance = Txt.Glance(bars)
        Check("The watch reads this cell in one plain line",
            type(glance) == "string"
                and glance:find("active true", 1, true) ~= nil
                and glance:find("stacks", 1, true) ~= nil,
            tostring(glance))
        Check("and a non-frame gives it nothing to say",
            Txt.Glance(nil) == nil and Txt.Glance(7) == nil)
        Check("The remaining time is Blizzard's own, copied across",
            own.timer:GetText() == "12.3", own.timer:GetText())

        -- THE CLOCK ITSELF, mirrored rather than computed. Nothing on this
        -- path may divide one number by another - both can be secret - so the
        -- only honest check is that ours reads exactly what theirs does.
        Check("and the fill is Blizzard's value, passed straight through",
            own.fill:GetValue() == 18, tostring(own.fill:GetValue()))
        local low, high = own.fill:GetMinMaxValues()
        Check("against Blizzard's own scale",
            low == 0 and high == 30,
            string.format("%s..%s", tostring(low), tostring(high)))

        -- AND THE COLOUR REALLY LANDED ON THE TEXTURE.
        --
        -- The rule above is asked of the pure function and holds everywhere.
        -- This asks the WIRING - that Paint actually hands that pair to the
        -- texture - and it can only be asked at a desk, because this API has
        -- no way to read a gradient back. Skipped rather than quietly passed
        -- in his client: "the rule is right" and "the rule reached the screen"
        -- have been different answers twice in this file's history.
        -- WHETHER THIS CLIENT CAN BE ASKED IS PROBED, NOT ASSUMED.
        --
        -- The first draft read the ramp back and skipped when there was none,
        -- and the red proof caught it: a Paint that wrote NO gradient at all
        -- printed the same "cannot ask" as a client with no way to read one.
        -- Absent and passing again, which is the fault this whole file keeps
        -- being written against.
        --
        -- So a texture of ours is given a known ramp first. If that reads
        -- back, an empty answer on the fill means NOTHING WAS WRITTEN and is a
        -- failure. Kept on the cell rather than made per run: nothing in this
        -- API destroys a texture, and the cell comes back from Render's own
        -- pool on every later run.
        local probe = cell.dkProbe
        if not probe then
            probe = cell:CreateTexture()
            cell.dkProbe = probe
        end
        if probe.SetGradient then
            pcall(probe.SetGradient, probe, "HORIZONTAL",
                { r = 1, g = 0, b = 0, a = 1 }, { r = 1, g = 0, b = 0, a = 1 })
        end

        if type(rawget(probe, "hxGradient")) == "table" then
            local painted = own.fill:GetStatusBarTexture()
            local ramp = type(painted) == "table"
                and rawget(painted, "hxGradient") or nil

            Check("The fill was given a ramp at all", ramp ~= nil)
            if ramp then
                Check("with the fill's colour at BOTH ends rather than white",
                    ramp.from[1] == 1 and ramp.from[2] == 0
                        and ramp.from[3] == 0
                        and ramp.to[1] == 1 and ramp.to[2] == 0,
                    string.format("%s,%s,%s", tostring(ramp.from[1]),
                        tostring(ramp.from[2]), tostring(ramp.from[3])))
                Check("and the fill's own alpha on it", ramp.from[4] == 0.85,
                    tostring(ramp.from[4]))
            end
        else
            Skip("The fill colour reaches the texture",
                "this client cannot read a gradient back")
        end

        -----------------------------------------------------------------
        -- NOTHING IS ALLOCATED PER FRAME
        --
        -- Owner, on the game's own memory list: "wenn das addon offen ist
        -- sollte das weniger ein problem sein, schlimm waere es nur, wenn im
        -- zu zustand so viele ressourcen verbraucht werden." He is right
        -- about which half matters, and it is the half no other check here
        -- can see: a window opened once is HELD and then stops growing, while
        -- a table or a closure built per frame never stops.
        --
        -- This mirror is the addon's only sixty-times-a-second job, and its
        -- first version wrapped its four calls in `pcall(function() ... end)`
        -- - one closure per frame per bar, which on four bars is two hundred
        -- and forty a second for as long as the addon is on screen. It cost
        -- nothing measurable in a single frame and everything over an evening,
        -- which is exactly the shape that gets shipped.
        --
        -- CALIBRATED ON THE DEFECT rather than on a round number: 200 ticks
        -- of the closure version allocate about 14 KB, and the version
        -- without it allocates none at all. Two KB is comfortably below the
        -- one and comfortably above the other.
        -----------------------------------------------------------------
        local tick = own.fill:GetScript("OnUpdate")
        if type(tick) == "function" then
            -- Warmed first: the FIRST call through a path can legitimately
            -- build something it then keeps, and a guard that counts that
            -- would be measuring startup rather than steady state.
            tick(own.fill)
            collectgarbage("collect")
            collectgarbage("collect")

            local before = collectgarbage("count")
            for _ = 1, 200 do tick(own.fill) end
            local grew = collectgarbage("count") - before

            Check("The mirror allocates nothing per frame", grew < 2,
                string.format("%.1f KB over 200 ticks", grew))

            -------------------------------------------------------------
            -- AND THE RATE LIMIT LETS GO AGAIN
            --
            -- Emptying the bar writes four setters, and writing them sixty
            -- times a second to keep saying nought is the same waste the
            -- closure above was - a buff bar is DOWN for most of an evening,
            -- so that is the branch the clock actually lives in. So it writes
            -- once per fall and then goes quiet.
            --
            -- The cheap half of a rate limit is setting the latch. The half
            -- that gets forgotten is CLEARING it, and forgetting it here does
            -- not look like a memory fix gone wrong - it looks like a bar
            -- that stops working after the first time the buff drops, for the
            -- rest of the session. The red proof found this exact hole with
            -- one line deleted and nothing out here noticed.
            -------------------------------------------------------------
            -- DOWN, UP, DOWN AGAIN - and the third step is the one that
            -- matters. The first draft of this stopped after two and passed
            -- against the broken version, because the latch only gates the
            -- EMPTYING: with it stuck on, the bar still fills perfectly well
            -- and simply never empties again. A check that cannot fail is
            -- worth exactly nothing, and this one could not until it went
            -- round twice.
            -- THE BUFF FALLS OFF BY ANSWERING SO, not by being hidden. See
            -- FakeBar: hiding a frame is Blizzard saying it is not usable on
            -- your target, which is a different question and was the bug.
            bars.hxUp = false
            tick(own.fill)
            Check("A buff that fell off empties the bar",
                own.fill:GetValue() == 0, tostring(own.fill:GetValue()))

            -- AND THE ICON WENT WITH IT, on the tick rather than waiting for
            -- a render pass. "wie du siehst ist Rime aktive, aber das icon
            -- leuchtet nicht" - the fill runs on its own script and the icon
            -- was only repainted when Blizzard notified us about something,
            -- so the two could disagree for as long as nothing did.
            Check("and the icon dimmed with it, without a render pass",
                own.icon:GetAlpha() < 1, tostring(own.icon:GetAlpha()))

            bars.hxUp = true
            tick(own.fill)
            Check("and one that came back fills it again",
                own.fill:GetValue() == 18, tostring(own.fill:GetValue()))
            Check("and the icon came back up with it",
                own.icon:GetAlpha() == 1, tostring(own.icon:GetAlpha()))

            bars.hxUp = false
            tick(own.fill)
            Check("and it empties on the SECOND fall as well",
                own.fill:GetValue() == 0, tostring(own.fill:GetValue()))

            -- THE TARGET HAS NOTHING TO DO WITH IT, and this is the check
            -- that says so. Owner: "wenn ich kein target anwaehle, wird das
            -- icon nicht mehr ausgegraut" - Blizzard hides an item it thinks
            -- is not usable on what you have selected, and IsShown was being
            -- read as "is the buff up". Hiding the frame must now change
            -- nothing about the picture.
            bars.hxUp = true
            tick(own.fill)
            local litAlpha = own.icon:GetAlpha()
            bars:Hide()
            tick(own.fill)
            Check("A frame Blizzard stops showing does not dim a live buff",
                own.icon:GetAlpha() == litAlpha
                    and ns.CDM:ItemIsActive(bars) == true,
                string.format("%s, active %s", tostring(own.icon:GetAlpha()),
                    tostring(ns.CDM:ItemIsActive(bars))))
            Check("and that IS a different question, still askable",
                ns.CDM:ItemIsShown(bars) == false,
                tostring(ns.CDM:ItemIsShown(bars)))
            bars:Show()

            bars.hxUp = false
            tick(own.fill)

            -----------------------------------------------------------
            -- THE SPARK, AND BOTH OF THE THINGS HE SAW ON 2026-08-16
            --
            -- "rechts von den bars ist immer noch ein weisser border" and
            -- "wenn die bar leer ist, ist der spark immer noch zu sehen"
            -- are ONE object: a twelve-pixel ADD-blended line that hung by
            -- its CENTRE on the fill's leading edge and was never taken
            -- down. Six of those pixels stood outside the bar, always on
            -- the same side, which is the shape of a border.
            --
            -- ASKED HERE, ON THE EMPTY STEP, because that is the state the
            -- second report is about and the fixture is already in it.
            -----------------------------------------------------------
            local spark = Fill.Spark(bars)
            Check("The bar asked for a spark and got one", spark ~= nil)
            if spark then
                -- ITS OWN EDGE ON THE FILL'S EDGE. A CENTRE anchor is the
                -- bug: half the line lands outside whatever it is hung on.
                local point, _, relPoint = spark:GetPoint(1)
                Check("and it hangs by an edge rather than by its centre",
                    point ~= "CENTER" and point == relPoint,
                    string.format("%s -> %s", tostring(point),
                        tostring(relPoint)))
                -- AND IT RIDES THE TEXTURE, NOT THE FRAME. That `or fill`
                -- fallback is what put a bright line on the cell's own edge
                -- that never moved - "der spark ist nicht am ende der roten
                -- bar" and "der rechte border ist immer noch white" are the
                -- same six pixels photographed twice.
                local _, anchoredTo = spark:GetPoint(1)
                Check("and it is hung on the fill's texture, not on the frame",
                    anchoredTo ~= own.fill
                        and anchoredTo == own.fill:GetStatusBarTexture())

                Check("and there is nothing for it to lead on an empty bar",
                    spark:IsShown() == false)

                -----------------------------------------------------
                -- AND THE STATE HIS BARS ARE ACTUALLY IN: everything
                -- below the mirror unreadable, the WIDTH included.
                --
                -- Two designs died here, in his client and not at the
                -- desk. The first asked the fill's VALUE - secret on
                -- every frame, and "cannot say counts as lit" was the
                -- only branch that ever ran. The second asked the
                -- TEXTURE's drawn width - and the engine's output
                -- inherits the protection: 22 raises of `attempt to
                -- compare local 'size' (a secret number value)`.
                --
                -- The harness now stores a secret SetValue as itself
                -- AND sizes the texture with the sentinel, so any
                -- future reader of either raises right here instead
                -- of in his combat log. These checks hold the fill in
                -- exactly that state and drive the spark through the
                -- only legal door - being TOLD.
                -----------------------------------------------------
                if _G.__SECRET and issecretvalue
                    and issecretvalue(_G.__SECRET) then
                    local barTex = own.fill:GetStatusBarTexture()
                    own.fill:SetValue(_G.__SECRET)
                    Check("The fill can hold a value nobody may read",
                        ns.CanCompute(own.fill:GetValue()) == false)
                    Check("and the width the engine drew from it is "
                        .. "just as protected",
                        ns.CanCompute(barTex:GetWidth()) == false)

                    Fill.Lead(bars, false)
                    Check("told the buff is down, the spark goes out "
                        .. "with the width unreadable",
                        spark:IsShown() == false)

                    Fill.Lead(bars, true)
                    Check("told it is up, it lights the same way",
                        spark:IsShown() == true)

                    -- Readable again for everything that runs after.
                    own.fill:SetValue(18)
                end
            end

            bars.hxUp = true
            tick(own.fill)
            if spark then
                -- THE HALF THAT GETS FORGOTTEN. A spark that goes out on the
                -- first fall and never comes back reads exactly like the
                -- line above passing.
                Check("and it is lit again the moment the bar refills",
                    spark:IsShown() == true)
            end
        else
            Skip("The mirror allocates nothing per frame",
                "the bar has no clock to run")
        end

        -- THE TROUGH IS A TEXTURE, NOT A SETTING. The fixture bar does not
        -- ask for one, so there must not be one behind its fill: a switch
        -- that draws whatever it is set to is the other half of the same
        -- check, and this is the half that catches a trough painted always.
        Check("A bar that did not ask for a trough has none behind its fill",
            Fill.Trough(bars) == nil or Fill.Trough(bars):IsShown() == false)

            -----------------------------------------------------------------
        -- "KANN ES SEIN DAS DU EIN RANGE CHECK BEI DEN BARS MIT DRIN HAST?"
        --
        -- No. What he was looking at is CDM:ItemIsActive's THIRD answer.
        -- `IsShown` can hand back a secret boolean on this patch, and whether
        -- it does depends on where you are standing - so an unchanged,
        -- inactive spell was greyed on the frames the client answered and
        -- bright on the frames it did not. One state, two pictures.
        --
        -- ItemLooksActive keeps the last answer it was GIVEN rather than
        -- rounding a refusal into the flattering one. This is asked against
        -- a made-up frame rather than the fixture's: the point is the
        -- transition from an answer to a refusal, and a real frame cannot be
        -- made to refuse on cue.
        -----------------------------------------------------------------
        local coy = { hxAnswer = false }
        coy.IsActive = function(this)
            if this.hxAnswer == nil then return _G.__SECRET end
            return this.hxAnswer
        end

        if _G.__SECRET and issecretvalue and issecretvalue(_G.__SECRET) then
            Check("A frame that answers is taken at its word",
                ns.CDM:ItemLooksActive(coy) == false)

            coy.hxAnswer = nil
            Check("and one that has gone quiet keeps the answer it gave",
                ns.CDM:ItemLooksActive(coy) == false,
                tostring(ns.CDM:ItemLooksActive(coy)))
            Check("which the raw reader still reports as unanswerable",
                ns.CDM:ItemIsActive(coy) == nil
                    and ns.CDM:ItemActiveIsRemembered(coy) == true)

            coy.hxAnswer = true
            Check("and a new answer replaces the remembered one",
                ns.CDM:ItemLooksActive(coy) == true)
            coy.hxAnswer = nil
            Check("and it is THAT one that is kept from then on",
                ns.CDM:ItemLooksActive(coy) == true)

            -- A FRAME NOBODY HAS EVER HAD AN ANSWER FOR STILL SAYS SO.
            -- Remembering is not the same as inventing, and a first sight
            -- has nothing to remember.
            local stranger = { IsActive = function() return _G.__SECRET end }
            Check("but a frame nobody has ever read still answers nil",
                ns.CDM:ItemLooksActive(stranger) == nil,
                tostring(ns.CDM:ItemLooksActive(stranger)))

            -----------------------------------------------------------
            -- AND THE FRAME THE BUG ACTUALLY LIVED ON: one with NO
            -- IsActive at all.
            --
            -- This is the shape every fixture in this file was missing, and
            -- it is why the defect survived a suite this size. IsActive
            -- answers on a buff-bar item, so the IsShown fallback under it
            -- never ran in any test - it only ran on the frames that have
            -- no IsActive, out in his client, where `IsShown` means "would
            -- the Cooldown Manager put this on screen for your current
            -- target". Reading that as "is the buff up" is what greyed an
            -- icon the moment he clicked a mob and lit it again when he
            -- deselected.
            --
            -- Restoring the fallback has to turn THIS red and nothing else,
            -- which is the whole reason it is written as its own frame
            -- rather than folded into the fixture above.
            -----------------------------------------------------------
            local noAnswer = { IsShown = function() return false end }
            Check("A frame with no IsActive cannot say whether a buff is up",
                ns.CDM:ItemIsActive(noAnswer) == nil,
                tostring(ns.CDM:ItemIsActive(noAnswer)))
            Check("and being hidden is a DIFFERENT question with its own name",
                ns.CDM:ItemIsShown(noAnswer) == false)
            -- The point of all of it: nothing downstream may dim on this.
            Check("so nothing dims on it - unknown stays lit",
                ns.CDM:ItemLooksActive(noAnswer) == nil)
        else
            Skip("A picture that will not sit still",
                "the harness has no secret value to refuse with")
        end

        -- AND FILL.LUA IS DRESSING OURS, not looking for one of theirs. The
        -- whole reason this file draws no texture and no spark of its own.
        Check("Fill's one finder answers with our StatusBar",
            ns.Cooldowns.Fill.Bar(bars) == own.fill)
        Check("while Blizzard's is still reachable for the mirror",
            ns.Cooldowns.Fill.Blizzard(bars) == mirror)

        -----------------------------------------------------------------
        -- THE OTHER TWO CLOCKS COST NOTHING PER TICK EITHER
        --
        -- The mirror above was measured on the wave that wrote it. These two
        -- are older, they run in the same state - bars on screen, window shut,
        -- which is the half the owner said matters - and NOTHING HAD EVER
        -- WALKED THEM OUT HERE. Effects.Step's own header says it is exported
        -- so the desk can drive it, and no test called it; Fill's tick was
        -- local, which is worse, because there was nothing to call.
        --
        -- BOTH ARE ASSERTED TO BE WALKING SOMETHING FIRST. An empty loop
        -- allocates nothing and answers this question with a green line that
        -- means nothing at all - and the first draft of this measured exactly
        -- that: no bar has effects switched on by default and none has a stack
        -- band, so the fixture ran both clocks over zero entries. The fixture
        -- carries `effects` and `stackThresholds` because of this paragraph.
        --
        -- CALIBRATED ON THE DEFECT, both of them measured by putting it back:
        --
        --   effects  one closure per cell per tick     45.7 KB / 200 ticks
        --            what it does now                   0.4 KB
        --   fill     two fresh lists per tick          21.5 KB / 200 ticks
        --            what it does now                   0.2 KB
        --
        -- Two KB sits comfortably above both floors and an order of magnitude
        -- below either defect.
        -----------------------------------------------------------------
        local FX = ns.Cooldowns.Effects
        local walked = FX.Step(GetTime(), false, 0.06)
        Check("The effects ticker is actually walking this cell", walked == 1,
            tostring(walked) .. " cells")

        collectgarbage("collect")
        collectgarbage("collect")
        local before = collectgarbage("count")
        for _ = 1, 200 do FX.Step(GetTime(), false, 0.06) end
        local grew = collectgarbage("count") - before
        Check("and allocates nothing while it does", grew < 2,
            string.format("%.1f KB over 200 ticks", grew))

        -----------------------------------------------------------------
        -- THE FILL TICKER, AND THE COUNT REALLY REACHING THE BAND
        --
        -- The cost check needs this one beside it, and not as a nicety: a tick
        -- that returned at its first guard would allocate nothing and pass the
        -- line below on its own. What proves the loop is doing its job is the
        -- stack count arriving in the overlay - the band is a StatusBar whose
        -- range is (value-1, value), so the count going in is the whole
        -- mechanism, and it is the one thing no other test asks.
        --
        -- The overlay is reached as the fill's only child frame rather than
        -- through a new export: the trough, the spark and the charge marks are
        -- all textures, so a band is the only thing that can answer here.
        -----------------------------------------------------------------
        Check("The fill ticker has this bar on its list", Fill.Watching() == 1,
            tostring(Fill.Watching()))

        Fill.Tick()
        local band = own.fill:GetChildren()
        Check("A stack band was built for the threshold", band ~= nil)
        if band then
            Check("and the tick pushed the live count into it",
                band:GetValue() == 3, tostring(band:GetValue()))
            local low, high = band:GetMinMaxValues()
            Check("against the range that does the comparing for us",
                low == 2 and high == 3,
                string.format("%s..%s", tostring(low), tostring(high)))
        end

        collectgarbage("collect")
        collectgarbage("collect")
        before = collectgarbage("count")
        for _ = 1, 200 do Fill.Tick() end
        grew = collectgarbage("count") - before
        Check("and it allocates nothing per tick", grew < 2,
            string.format("%.1f KB over 200 ticks", grew))

        -- AND IT STILL HAS ITS CLIENT AFTERWARDS. A tick that quietly dropped
        -- the bar off its own list would go silent, cost nothing for ever and
        -- read exactly like the line above passing.
        Check("and it still has the bar after two hundred of them",
            Fill.Watching() == 1, tostring(Fill.Watching()))

        -----------------------------------------------------------------
        -- AND THE LONGEST-RUNNING LOOP IN THE ADDON
        --
        -- History's buff sweep is armed at file scope, so it polls ten times a
        -- second from login to logout whatever is switched on - no window, no
        -- bar, nothing. It is asked HERE rather than in the cast-history suite
        -- because it needs a live buff viewer with an item in it to walk, and
        -- this fixture is the only one in the file that has one. A second copy
        -- of that fixture would be a second thing to keep true.
        --
        -- It used to build a `seen` table, the two-word list it walks and a
        -- closure per viewer on every poll: forty objects a second, for ever.
        -- Measured with those put back: 39.0 KB over 200 polls against 0.4.
        -----------------------------------------------------------------
        local sweeps = ns.History
        if sweeps and type(sweeps.Sweep) == "function" then
            sweeps.Sweep()
            Check("The buff sweep sees the fixture's own bar",
                sweeps.openActives[77535] ~= nil,
                "nothing opened")

            collectgarbage("collect")
            collectgarbage("collect")
            before = collectgarbage("count")
            for _ = 1, 200 do sweeps.Sweep() end
            grew = collectgarbage("count") - before
            Check("and it allocates nothing per poll", grew < 2,
                string.format("%.1f KB over 200 polls", grew))

            -- ITS OWN STATE PUT BACK. The sweep opened a window for the
            -- fixture's spell, and the suite's promise is that it leaves
            -- nothing behind.
            sweeps.openActives[77535] = nil
        else
            Skip("The buff sweep costs nothing per poll",
                "History.Sweep is not exported")
        end

        -----------------------------------------------------------------
        -- SWITCHING IT OFF
        -----------------------------------------------------------------
        ns.db.modules.cooldowns = false
        Render.Refresh()
        Check("Switching the module off takes our own widget down too",
            own.fill:IsShown() == false and own.icon:IsShown() == false)
        Check("and gives Blizzard's frame its brightness back",
            bars:GetAlpha() == 1, tostring(bars:GetAlpha()))

        -- AND THE COUNTER STILL OBEYS ITS PARENT'S ALPHA. Nothing pierces
        -- the veil any more - the engine never fed a pierced counter - but
        -- the Claim UNDO entry for SetIgnoreParentAlpha stays, and so does
        -- this: an addon that released a frame and left its counter ignoring
        -- the parent's alpha would leave one bright number floating over
        -- Blizzard's own display for the rest of the session.
        local pierced = ns.CDM:Counter(bars, "Applications")
        Check("and its counter obeys its parent's alpha after release",
            pierced ~= nil and pierced:IsIgnoringParentAlpha() == false,
            tostring(pierced and pierced:IsIgnoringParentAlpha()))
    end)

    -- PUT THE WORLD BACK WHATEVER HAPPENED, and put it back in an order that
    -- survives a throw halfway - the lesson TestCooldownRender carries above.
    pcall(Render.Stop)
    _G[ns.CDM.VIEWERS[4].global] = nil
    ns.db.bars = saved.bars
    if ns.db.modules then ns.db.modules.cooldowns = saved.module end
    ns.db.takeOverCDM = saved.takeover
    ns.CDM.available = saved.available
    ns.CDM.indexBuilt = saved.built
    Render.started = saved.started

    if not ok then error(err, 0) end
end

---------------------------------------------------------------------------
-- WHAT THE STYLING LAYER DOES WITHOUT A SCREEN
--
-- Waves 4 and 5 are four files and about three thousand lines, and almost all
-- of it draws. What CAN be asked at a desk is the half each of them split out
-- on purpose: the arithmetic and the rules. That half is also where the
-- silent failures live - an off-by-one in a glow's position does not raise,
-- it puts a dot in the wrong corner; a rule that folds `false` into `true`
-- gives somebody a switch that cannot be switched off.
--
-- THE THREE-VALUED ANSWERS ARE THE POINT OF THIS SUITE. Everything in these
-- files that reads the client can answer "I could not tell", and every one of
-- those has to fall back to the behaviour of the FEATURE SWITCHED OFF. An
-- icon that disappears because a secret could not be tested is
-- indistinguishable from a bug, and it takes the spell with it.
---------------------------------------------------------------------------
local function TestCooldownStyling()
    local C = ns.Cooldowns
    if not (C and C.Effects and C.Look and C.Text and C.Fill) then
        Skip("The styling layer", "waves 4 and 5 are not loaded")
        return
    end

    local Effects, Look, Text, Fill = C.Effects, C.Look, C.Text, C.Fill

    ---------------------------------------------------------------------
    -- `x and y or z` CANNOT CARRY FALSE, and half these defaults are true
    ---------------------------------------------------------------------
    Check("A stored false survives a default of true",
        Effects.Option({ readyGlowCombatOnly = false }, "readyGlowCombatOnly")
        == false)
    Check("And an absent key still answers with the default",
        Effects.Option({}, "readyGlowCombatOnly") == true)
    Check("A bar with no effects table at all answers the defaults",
        Effects.Option(nil, "readyFlash") == false)

    ---------------------------------------------------------------------
    -- UNKNOWN IS NEVER ROUNDED INTO THE FLATTERING ANSWER
    ---------------------------------------------------------------------
    Check("A cooldown the client will not talk about is never hidden",
        Effects.HiddenByState({ hideWhen = "cooling" }, nil) == false)
    Check("One it WILL talk about still is",
        Effects.HiddenByState({ hideWhen = "cooling" }, false) == true)
    Check("And a bar hiding nothing hides nothing",
        Effects.HiddenByState({ hideWhen = "never" }, false) == false)

    -- The inverse rule was taken out rather than left unlisted, and a profile
    -- that still carries it must give the bar BACK rather than empty it.
    Check("A rule this build no longer has hides nothing",
        Effects.HiddenByState({ hideWhen = "ready" }, true) == false)

    ---------------------------------------------------------------------
    -- FIVE ANSWERS, AND THE OLD TWO STILL MEAN WHAT THEY MEANT
    --
    -- Owner: "ich kann es aber nicht einstellen im addon! das sind noch alte
    -- regeln." The rule was welded shut - one behaviour and a switch. Every
    -- state below was already ANSWERABLE and none could be ASKED for.
    ---------------------------------------------------------------------
    Check("A bar written in 4.82.0 reads as the rule it was given",
        Effects.ShowWhen({ hideWhen = "cooling" }) == "usable",
        tostring(Effects.ShowWhen({ hideWhen = "cooling" })))
    Check("And one with neither key is always on screen",
        Effects.ShowWhen({}) == "always")
    Check("An explicit choice beats the old key",
        Effects.ShowWhen({ hideWhen = "cooling", showWhen = "ready" })
            == "ready")
    Check("Nonsense in the profile is not a sixth rule",
        Effects.ShowWhen({ showWhen = "sideways" }) == "always")

    local function Kept(rule, state)
        return Effects.HiddenByState({ showWhen = rule }, state) == false
    end
    Check("Always keeps every state",
        Kept("always", "ready") and Kept("always", "active")
        and Kept("always", "cooling"))
    Check("Ready keeps only the ready one",
        Kept("ready", "ready") and not Kept("ready", "active")
        and not Kept("ready", "cooling"))
    Check("Working keeps only the one whose buff is running",
        Kept("working", "active") and not Kept("working", "ready")
        and not Kept("working", "cooling"))
    Check("Recharging keeps only the one that is recharging",
        Kept("cooling", "cooling") and not Kept("cooling", "ready")
        and not Kept("cooling", "active"))
    Check("Usable keeps the two that earn their square",
        Kept("usable", "ready") and Kept("usable", "active")
        and not Kept("usable", "cooling"))

    -- UNKNOWN IS NEVER ROUNDED, WHATEVER THE RULE. Every one of the five.
    local everyRuleKeepsUnknown = true
    for _, rule in ipairs({ "always", "usable", "ready", "working", "cooling" }) do
        if not Kept(rule, nil) then everyRuleKeepsUnknown = false end
    end
    Check("No rule hides a place the client will not answer for",
        everyRuleKeepsUnknown)

    -- THE PROBE THAT WOULD HAVE BROKEN. Effects.Pass used to ask whether a
    -- rule hides anything by handing it `true` and then `false`. With five
    -- answers that is wrong: "only while its buff runs" hides neither of
    -- those under the old encoding, so the probe would have reported "this
    -- rule hides nothing", skipped the entire per-cell walk, and the setting
    -- would have done nothing at all while every test above passed.
    Check("A rule that hides something says so before the walk",
        Effects.CanHide({ showWhen = "working" }) == true)
    Check("And the default says it does not",
        Effects.CanHide({}) == false)
    Check("An old stored rule still says it does",
        Effects.CanHide({ hideWhen = "cooling" }) == true)

    -- EVERY MENU ENTRY IS A RULE, and every rule is in the menu. The list the
    -- dropdown is built from and the table the arithmetic reads are the same
    -- five keys, which is what stops a sixth choice being added to one.
    local menu = 0
    for _, entry in ipairs(ns.CD_SHOW_WHEN or {}) do
        menu = menu + 1
        if Effects.ShowWhen({ showWhen = entry.value }) ~= entry.value then
            menu = -1000
        end
    end
    Check("Every answer in the menu is an answer the rule knows",
        menu == 5, tostring(menu))

    Check("A glow lights when the client will not say what you can afford",
        Effects.GlowAllowed({ readyGlow = true, readyGlowUsableOnly = true },
            true, nil) == true)
    Check("And stays dark when it says you cannot",
        Effects.GlowAllowed({ readyGlow = true, readyGlowUsableOnly = true },
            true, false) == false)
    Check("A spell that is not ready never glows",
        Effects.GlowAllowed({ readyGlow = true }, false, true) == false)

    ---------------------------------------------------------------------
    -- THE TICKER IS ARMED BY WHAT IS ASKED FOR, NOT BY WHAT IS DRAWN
    --
    -- 4.82.0 asked only about the visuals, so somebody who chose a sound and
    -- left every visual off was watched by nothing and heard nothing - and a
    -- sound that never comes is indistinguishable from a broken sound file.
    ---------------------------------------------------------------------
    Check("A bar with everything off wants no ticker",
        Effects.Wanted({ hideWhen = "never" }, false) == false)
    Check("A sound alone is enough to arm it",
        Effects.Wanted({ hideWhen = "never" }, true) == true)
    Check("So is a rule that only hides things",
        Effects.Wanted({ hideWhen = "cooling" }, false) == true)
    Check("And so is the nag on its own",
        Effects.Wanted({ hideWhen = "never", reminderAfter = 5 }, false) == true)

    ---------------------------------------------------------------------
    -- WALKING THE OUTLINE, which is the only way a running glow is provable
    ---------------------------------------------------------------------
    local w, h = 40, 40
    local x0, y0 = Effects.PerimeterPoint(0, w, h)
    local x1, y1 = Effects.PerimeterPoint(1, w, h)
    Check("The walk comes back to where it started",
        math.abs(x0 - x1) < 0.001 and math.abs(y0 - y1) < 0.001,
        string.format("%.2f,%.2f vs %.2f,%.2f", x0, y0, x1, y1))

    local xWrap, yWrap = Effects.PerimeterPoint(1.25, w, h)
    local xQuarter, yQuarter = Effects.PerimeterPoint(0.25, w, h)
    Check("And it wraps, so a caller may add without thinking",
        math.abs(xWrap - xQuarter) < 0.001
        and math.abs(yWrap - yQuarter) < 0.001)

    -- EVERY POINT IS ON THE EDGE. Eight dots that drift inside the rectangle
    -- is a glow that reads as a smudge, and no arithmetic error large enough
    -- to see would fail a check of the corners alone.
    local strayed = 0
    for step = 0, 31 do
        local x, y = Effects.PerimeterPoint(step / 32, w, h)
        local onEdge = math.abs(x) < 0.001 or math.abs(x - w) < 0.001
            or math.abs(y) < 0.001 or math.abs(y - h) < 0.001
        if not onEdge then strayed = strayed + 1 end
    end
    Check("Every one of thirty-two points is on the outline", strayed == 0,
        tostring(strayed) .. " strayed inside")

    ---------------------------------------------------------------------
    -- RULE 4 FOLDED INTO ONE NUMBER
    ---------------------------------------------------------------------
    local full = Look.Style({ alpha = 1, inactiveAlpha = 0.55 }, 1)
    Check("A cell that is up is at the alpha you set",
        Look.Opacity(full, true) == 1)
    Check("One that is down is dimmed by the inactive share",
        math.abs(Look.Opacity(full, false) - 0.55) < 0.001,
        tostring(Look.Opacity(full, false)))
    -- The whole of the three-valued rule, in the one place it decides whether
    -- something is on screen at all.
    Check("And one the client will not talk about is NOT dimmed",
        Look.Opacity(full, nil) == 1)

    local off = Look.Style({ alpha = 1, inactiveAlpha = 0 }, 1)
    Check("Zero is still reachable, so Blizzard's own behaviour is offerable",
        Look.Opacity(off, false) == 0)

    ---------------------------------------------------------------------
    -- HIS OWN BARS' LOOK, read back rather than assumed
    ---------------------------------------------------------------------
    local bare = Look.Style({}, 1)
    Check("A bar with no look keys at all still resolves to numbers",
        type(bare.borderSize) == "number" and type(bare.iconZoom) == "number"
        and type(bare.backdropColor) == "table")
    Check("And zero really is a border size, not a missing one",
        Look.Style({ borderSize = 0 }, 1).borderSize == 0)

    ---------------------------------------------------------------------
    -- THE TEXT OFFSETS, which are the corner-clipping fix
    ---------------------------------------------------------------------
    ---------------------------------------------------------------------
    -- THE STACK NUMBER, AND WHO IS ALLOWED TO MAKE THE COMPARISON
    --
    -- Owner, twice: "stack count wird immer noch nicht bei den buffs
    -- angezeigt." Every control on the block was correct and wrote onto a
    -- frame Blizzard had never made, so the Show switch could only ever hide.
    -- This is the rule that decides whether we draw one ourselves.
    ---------------------------------------------------------------------
    Check("Blizzard drawing its own number means we draw none",
        Text.StackToShow(true, 5) == nil)
    Check("And Blizzard deciding NOT to is its comparison, not ours",
        Text.StackToShow(false, 5) == nil)
    Check("With no counter frame at all, a readable count above one shows",
        Text.StackToShow(nil, 5) == 5)
    Check("A single application is not worth a corner",
        Text.StackToShow(nil, 1) == nil)
    Check("Nor is nought", Text.StackToShow(nil, 0) == nil)
    Check("And nothing to read is nothing to draw",
        Text.StackToShow(nil, nil) == nil)

    -- THE ARM THAT COST A RELEASE IN 4.82.0. A secret may not be compared, so
    -- with no counter frame to ask instead it is SHOWN - guessing that a
    -- protected count is 1 hides a real stack count for a whole fight. The
    -- desk has no secrets, so this pins the shape rather than the value: a
    -- count that is neither computable nor displayable draws nothing.
    Check("Something that is neither readable nor showable draws nothing",
        Text.StackToShow(nil, {}) == nil)

    ---------------------------------------------------------------------
    -- WHERE THE WINDOW OPENS
    --
    -- Owner: "ich lande beim oeffnen immer in den settings." Remembered by
    -- KEY and never by index - PAGES is reordered whenever a page is added,
    -- so a stored number points somewhere else after a release and looks
    -- exactly like it worked.
    ---------------------------------------------------------------------
    do
        -- (The "else Cooldowns" landing preference went with the benched
        -- feature - a fresh install lands on the first live page now.)
        local PAGES = {
            { key = "settings" },
            { key = "deaths", module = "deaths" },
        }
        Check("A remembered page is where it opens",
            ns.Options.Landing(PAGES, "deaths") == 2)
        Check("With nothing remembered it opens on the first page",
            ns.Options.Landing(PAGES, nil) == 1)
        Check("A page that no longer exists falls back to the first",
            ns.Options.Landing(PAGES, "gone") == 1)

        -- THE FALLBACK THAT MATTERS. A remembered page whose module has been
        -- switched off is one the rail no longer shows, and landing on it is
        -- a blank window with nothing selected in the list.
        local was = ns.db.modules and ns.db.modules.deaths
        ns.db.modules = ns.db.modules or {}
        ns.db.modules.deaths = false
        Check("A remembered page whose module is off is not landed on",
            ns.Options.Landing(PAGES, "deaths") == 1)
        ns.db.modules.deaths = was
    end

    local x, y = Text.Offset({ anchor = "BOTTOMRIGHT" })
    Check("A corner-anchored number is pushed off both edges",
        x < 0 and y > 0, string.format("%s,%s", tostring(x), tostring(y)))
    x, y = Text.Offset({ anchor = "CENTER" })
    Check("A centred one is not pushed anywhere", x == 0 and y == 0)
    x = Text.Offset({ anchor = "BOTTOMRIGHT", x = 10 })
    Check("And what you nudged it by is added, not replaced", x == -2 + 10,
        tostring(x))

    ---------------------------------------------------------------------
    -- WHICH WAY A FILL RUNS - four answers, two mechanisms
    --
    -- Shipping these as one setting was a real bug: "Fill up" was wired to
    -- SetReverseFill, which moves the fill to the other END rather than
    -- making it grow. And up and down are unreachable without the
    -- orientation, because reverse only ever flips a horizontal bar.
    ---------------------------------------------------------------------
    -- ONE ENTRY, not two returns: the direction is a row of
    -- ns.FILL_DIRECTIONS, so the orientation and the reverse cannot be read
    -- apart and cannot drift from the words on the page.
    local way = Fill.Direction({ fillDirection = "right" }, 1)
    Check("Left to right is horizontal and not reversed",
        way.orientation == "HORIZONTAL" and not way.reverse)
    way = Fill.Direction({ fillDirection = "left" }, 1)
    Check("Right to left is the same bar, reversed",
        way.orientation == "HORIZONTAL" and way.reverse == true)
    way = Fill.Direction({ fillDirection = "up" }, 1)
    Check("Upwards needs the other orientation entirely",
        way.orientation == "VERTICAL" and not way.reverse)
    way = Fill.Direction({ fillDirection = "down" }, 1)
    Check("And downwards is that one reversed",
        way.orientation == "VERTICAL" and way.reverse == true)
    way = Fill.Direction({}, 1)
    Check("A bar that never said falls back to left-to-right",
        way.value == "right")

    -- THE OLD KEY IS STILL READ. `fillSide` is what a profile written before
    -- the four-answer setting carries, and a bar that loses its direction on
    -- an update is a bar that silently starts draining the wrong way.
    way = Fill.Direction({ fillSide = true }, 1)
    Check("A profile that predates the setting keeps its direction",
        way.value == "left", tostring(way.value))

    -- AND THE OTHER READER OF THE SAME SETTING AGREES.
    --
    -- Look.Style resolved this key on its own and knew nothing about
    -- `fillSide`, so a bar written in 4.82.0 - which is every bar he made -
    -- ran the way he set it on screen and left-to-right in the style table.
    -- Two readers of one setting, disagreeing on exactly the bars that carry
    -- the old key, which is the quietest way for a setting to half-work.
    --
    -- Asked of BOTH, on the same bar, rather than of the shared function they
    -- now both call: what broke was not the translation, it was one of them
    -- not asking for it.
    local old = { fillSide = true }
    Check("The look resolver reads the old key the same way the fill does",
        ns.Cooldowns.Look.Style(old, 1).fillDirection.value
            == Fill.Direction(old, 1).value,
        tostring(ns.Cooldowns.Look.Style(old, 1).fillDirection.value))

    -- AND A PLACE'S OWN DIRECTION REACHES BOTH, which is what makes it a
    -- per-place setting rather than one that happens to live on the bar.
    local perPlace = { cells = { 1044 }, fillDirection = "right",
        cellLook = { [1044] = { fillDirection = "up" } } }
    Check("and a place that runs its own way is read that way by both",
        Fill.Direction(perPlace, 1).value == "up"
            and ns.Cooldowns.Look.Style(perPlace, 1).fillDirection.value
                == "up")

    ---------------------------------------------------------------------
    -- THE THRESHOLDS ARE SORTED BECAUSE THE ORDER IS THE DRAW ORDER
    --
    -- The count they are compared against is a SECRET on this patch, so the
    -- highest crossed one cannot be chosen with an `if` here at all - it has
    -- to be painted last. Which makes the sort load-bearing rather than tidy.
    ---------------------------------------------------------------------
    local sorted = Fill.Thresholds({ stackThresholds = {
        { value = 5, color = { 1, 0, 0 } },
        { value = 2, color = { 0, 1, 0 } },
        { value = 9, color = { 0, 0, 1 } },
    } }, 1)
    -- A BAND'S OWN RAMP, WHICH HAD A READER AND NO WRITER. Fill.Thresholds has
    -- always handed `entry.gradient` to ns.Tint and no row on the page wrote
    -- one, so this half was paintable and unreachable - the same defect as a
    -- setting that is stored and never painted, from the other end. The rows
    -- exist now; this is the reader they have to agree with.
    local ramped = Fill.Thresholds({ stackThresholds = {
        { value = 3, color = { 1, 0, 0 },
          gradient = { on = true, color = { 0, 0, 1 }, direction = "up" } },
    } }, 1)
    Check("A band carries a ramp of its own, and it is not the fill's",
        ramped[1] and ramped[1].gradient.on == true
            and ramped[1].gradient.color[3] == 1
            and ramped[1].gradient.direction == "up",
        ramped[1] and tostring(ramped[1].gradient.direction) or "no band")

    Check("Thresholds come back lowest first",
        #sorted == 3 and sorted[1].value == 2 and sorted[3].value == 9,
        string.format("%s,%s,%s", tostring(sorted[1] and sorted[1].value),
            tostring(sorted[2] and sorted[2].value),
            tostring(sorted[3] and sorted[3].value)))
    Check("A bar with none has none", #Fill.Thresholds({}, 1) == 0)

    -- HIS OWN THREE, AND THEY HAVE NEVER PAINTED. All three thresholds in his
    -- file carry value 0, which the renderer discards because a threshold of
    -- zero is crossed by an aura that is merely present. The panel wrote rows
    -- the renderer throws away, and nothing said so - so the count DROPPED
    -- comes back as a second answer rather than being swallowed, which is
    -- what lets the page fix its writer instead of somebody loosening this.
    local kept, dropped = Fill.Thresholds({ stackThresholds = {
        { value = 0, color = { 1, 0, 0 } },
        { value = 0, color = { 1, 0, 0 } },
        { value = 4, color = { 1, 0, 0 } },
    } }, 1)
    Check("A threshold of zero is dropped and SAID, not silently kept",
        #kept == 1 and dropped == 2,
        string.format("kept %d, dropped %s", #kept, tostring(dropped)))

    -- A hand-edited profile is not a reason to raise three lines later.
    local rubbish = Fill.Thresholds({ stackThresholds = {
        { value = 3 }, "nonsense", { color = {} } } }, 1)
    Check("And an entry that is not a threshold is dropped, not drawn",
        #rubbish == 1, tostring(#rubbish))

    -- SOMETHING CAN READ A STACK COUNT AT ALL, which is the question every
    -- band above depends on and none of them could ask.
    --
    -- Fill.CanFeed tests for ns.CDM.ItemStacks by name. For one wave that
    -- function was gone, so it answered false on every client - Fill.Overlays
    -- was handed an empty list whatever was stored, the ticker gave up before
    -- it started, and not one band painted on a bar he had already set three of
    -- them on. Every test above passed throughout: they check that a threshold
    -- SURVIVES the filter, which says nothing about whether anything downstream
    -- can ever feed it. The band arriving at a real overlay is asked where the
    -- ticker is walked, in "Places we draw ourselves".
    Check("A stack count can be read off a frame at all",
        Fill.CanFeed() == true,
        "ns.CDM.ItemStacks is " .. type(ns.CDM and ns.CDM.ItemStacks))
end

---------------------------------------------------------------------------
-- THE HOUSE LOOK: one surface, one face, one floor.
--
-- Owner, 2026-08-16: "standard BG farben bei allem -> 100% 1a1a1a ... also
-- icons, bars, border. ueberall im addon", "standard Fonts ausserhalb von der
-- addon font ist expressway mit outline und minimum 10 pixel", "nimm das
-- automatisch bitte raus."
--
-- WHY THIS SUITE IS LONGER THAN THE CHANGE LOOKS. The colour was written out
-- fourteen times in fourteen files before this, which is the shape of a
-- decision that cannot be changed - and putting it in one place only helps
-- for as long as nobody writes a fifteenth. The walk below is what stops
-- that: it asks every default the addon ships whether it wears the house
-- colour, so a new module that types { 0, 0, 0 } goes red on the first run
-- rather than on somebody's screenshot in a month.
--
-- AND THE HALF THAT ACTUALLY MOVES SOMEBODY'S DATA gets asserted hardest.
-- ns.ApplyHouseLook writes into a saved profile. It has exactly two ways to
-- be wrong: leaving a colour the owner picked alone is the whole promise, and
-- running twice must not be different from running once.
---------------------------------------------------------------------------

-- The keys the walker cares about, and the one place a colour of that name
-- is meaning rather than surface. Written out HERE rather than read from
-- Init.lua on purpose: a test that imports the list it is checking agrees
-- with the code by construction and would pass with the list empty.
local HOUSE_COLORS = {
    backdropColor = true, borderColor = true,
    bgColor = true, fillBackColor = true,
}
local HOUSE_ALPHAS = { backdropAlpha = true, bgAlpha = true }
local MEANING_NOT_SURFACE = { debuffs = true, buffs = true }

---------------------------------------------------------------------------
-- ROUTES - the pure rules of the experiment (4.84.0). The client-facing half
-- is measured in a dungeon by /zs route probe; these are the rules that do
-- not need one, and they were checked before the file was parked in 4.42.
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- WHEN TO SHOW IT, the third customer: the answer bar's rule (4.84.0), the
-- role rule that came with it, and the builder's two pure helpers.
---------------------------------------------------------------------------
local function TestWhenBlock()
    local V, W, A = ns.Visibility, ns.OptionsWhen, ns.Answers
    if not (V and W and A) then
        Skip("When to show it", "a module is not loaded")
        return
    end
    -- The vocabulary names three roles, keyed as the client returns them.
    local keys = {}
    for _, entry in ipairs(ns.SHOW_ROLES or {}) do keys[entry.key] = true end
    Check("The role rule knows the three roles the client returns",
        keys.TANK and keys.HEALER and keys.DAMAGER and #ns.SHOW_ROLES == 3)
    Check("...and the defaults allow every one of them",
        ns.SHOW_DEFAULTS.roles and ns.SHOW_DEFAULTS.roles.TANK
        and ns.SHOW_DEFAULTS.roles.HEALER and ns.SHOW_DEFAULTS.roles.DAMAGER)

    -- The evaluator against the sampled role: a rule that leaves the
    -- current role out hides, one that lists it shows, none at all shows.
    local role = V:State().role
    if role then
        local out = {}
        for _, entry in ipairs(ns.SHOW_ROLES) do
            out[entry.key] = (entry.key ~= role)
        end
        Check("A role rule that leaves your role out hides the thing",
            V:Evaluate({ show = { mode = "rules", roles = out } }) == false
            and V:Explain({ show = { mode = "rules", roles = out } }) ~= nil)
        Check("...and one that names it shows it",
            V:Evaluate({ show = { mode = "rules", roles = { [role] = true } } }) == true
            and V:Evaluate({ show = { mode = "rules" } }) == true)
    else
        Skip("The role rule against your role", "the client named no role here")
    end

    -- The builder's helpers: a seed names every key; a missing list allows.
    local seed = W.SeedAll(ns.SHOW_WHERE)
    local all = true
    for _, place in ipairs(ns.SHOW_WHERE) do
        if seed[place.key] ~= true then all = false end
    end
    Check("The seed names every place, so the first untick hides one and not five", all)
    Check("A missing list allows, a false forbids, an unknown key allows",
        W.Allowed(nil, "raid") == true and W.Allowed({ raid = false }, "raid") == false
        and W.Allowed({ party = true }, "raid") == true)

    -- The old switch becomes the rule it meant: everywhere but the world.
    local rule = A.RuleFromOnlyInInstance()
    Check("'Only in dungeons and raids' becomes a rule for every place but the world",
        rule.mode == "rules" and rule.where.none == false and rule.where.party == true
        and rule.where.raid == true and rule.where.scenario == true)
    -- And Config folds it in once: the key goes, the rule stays, and a rule
    -- somebody already has is never overwritten.
    do
        local keep = ns.db.answers
        ns.db.answers = { onlyInInstance = true }
        local cfg = A.Config()
        local folded = cfg.onlyInInstance == nil and type(cfg.show) == "table"
            and cfg.show.where.none == false
        ns.db.answers = { onlyInInstance = true, show = { mode = "always" } }
        local cfg2 = A.Config()
        local kept = cfg2.onlyInInstance == nil and cfg2.show.mode == "always"
        ns.db.answers = keep
        Check("Config folds the old switch into the rule once, and keeps a rule that is there",
            folded and kept)
    end
    -- The bar's alpha follows the rule, and placing wins over it.
    Check("The bar's factor is the rule's, and 1 while it is being placed",
        A.Factor({ show = { mode = "never" } }) == 0
        and A.Factor({ show = { mode = "always" } }) == 1
        and A.Factor({ show = { mode = "never", hiddenAlpha = 0.3 } }) == 0.3)
    do
        local was = A.placing
        A.placing = true
        local placed = A.Factor({ show = { mode = "never" } }) == 1
        A.placing = was
        Check("...and 1 while it is being placed", placed)
    end
end

local function TestRoutes()
    local R = ns.Routes
    if not R then
        Skip("Routes", "the file is not loaded")
        return
    end
    Check("A mob in the pull you are on wears 'current', the next 'next', the rest nothing",
        R.Standing(3, 3) == "current" and R.Standing(4, 3) == "next"
        and R.Standing(5, 3) == nil and R.Standing(2, 3) == nil
        and R.Standing(nil, 3) == nil)
    local frac, shape = R.ParseForces("91/591")
    Check("The forces counter reads as a fraction",
        shape == "fraction" and math.abs(frac - 91 / 591) < 1e-9)
    local pct, pshape = R.ParseForces("15.40%")
    local ger, gshape = R.ParseForces("15,40%")
    Check("...and as a percentage, with a German comma too",
        pshape == "percent" and math.abs(pct - 0.154) < 1e-9
        and gshape == "percent" and math.abs(ger - 0.154) < 1e-9)
    Check("...and says nothing for a string it does not know",
        R.ParseForces("soon") == nil and R.ParseForces(nil) == nil)
    Check("The npc id is field six of a creature GUID, and a player has none",
        R.NpcFromGUID("Creature-0-4234-2662-1234-214390-00001A2B3C") == 214390
        and R.NpcFromGUID("Player-1096-0A1B2C3D") == nil
        and R.NpcFromGUID(nil) == nil)
    Check("The routes defaults are on the profile, and the experiment is off",
        type(ns.DEFAULTS.routes) == "table" and ns.DEFAULTS.routes.enabled == false)
    Check("/zs route is listed with a handler and asks nothing of a client without MDT",
        R:Available() == false or type(R:Available()) == "boolean")
end

local function TestHouseLook()
    local v = ns.SURFACE

    ---------------------------------------------------------------------
    -- THE TOKEN
    ---------------------------------------------------------------------
    Check("The surface colour is #1a1a1a",
        math.abs(v - 26 / 255) < 0.0005,
        string.format("%.4f, wanted %.4f", v, 26 / 255))

    -- A SHARED TABLE WOULD BE ONE COLOUR PICKER MOVING TWO PANELS, and it
    -- would only show up on the second character somebody made - half this
    -- addon writes its fallback straight into the profile.
    local first, second = ns.SurfaceColor(), ns.SurfaceColor()
    first[1] = 0.5
    Check("Each surface colour is a table of its own", second[1] ~= 0.5,
        tostring(second[1]))

    local r, g, b, a = ns.SurfaceRGB()
    Check("The four-number form is the same colour and opaque",
        r == v and g == v and b == v and a == 1,
        string.format("%.3f %.3f %.3f %.3f", r, g, b, a))

    local _, _, _, faded = ns.SurfaceRGB(0.4)
    Check("and it still takes an alpha when something asks for one",
        faded == 0.4, tostring(faded))

    ---------------------------------------------------------------------
    -- EVERY DEFAULT THE ADDON SHIPS
    ---------------------------------------------------------------------
    local wrong = {}

    local function Walk(tbl, path, guarded)
        for key, value in pairs(tbl) do
            local where = path .. "." .. tostring(key)
            if HOUSE_COLORS[key] and not guarded then
                local ok = type(value) == "table"
                    and math.abs((tonumber(value[1]) or -1) - v) < 0.005
                    and math.abs((tonumber(value[2]) or -1) - v) < 0.005
                    and math.abs((tonumber(value[3]) or -1) - v) < 0.005
                if not ok then wrong[#wrong + 1] = where end
            elseif HOUSE_ALPHAS[key] then
                if value ~= 1 then
                    wrong[#wrong + 1] = where .. "=" .. tostring(value)
                end
            elseif type(value) == "table" then
                Walk(value, where,
                    guarded or MEANING_NOT_SURFACE[key] or false)
            end
        end
    end

    Walk(ns.DEFAULTS, "DEFAULTS", false)
    Walk(ns.GROUP_DEFAULTS, "GROUP_DEFAULTS", false)
    if ns.Answers and ns.Answers.DEFAULTS then
        Walk(ns.Answers.DEFAULTS, "Answers", false)
    end
    if ns.Taunts and ns.Taunts.BUTTON_DEFAULTS then
        Walk(ns.Taunts.BUTTON_DEFAULTS, "Taunts", false)
    end

    Check("Every background and border the addon ships is #1a1a1a and opaque",
        #wrong == 0, table.concat(wrong, ", "))

    -- AND THE ONE PAIR THAT IS DELIBERATELY NOT GREY. Red for a debuff and
    -- green for a buff is the only thing that says which strip you are
    -- looking at, so a walk that turned those grey would be this rule eating
    -- the one place it does not belong.
    local strips = ns.DEFAULTS.coTanks
    Check("The co-tank trough ships solid rather than as a faded bar",
        ns.DEFAULTS.coTanks and ns.DEFAULTS.coTanks.trackAlpha == 1,
        tostring(ns.DEFAULTS.coTanks and ns.DEFAULTS.coTanks.trackAlpha))
    Check("but a debuff strip keeps its red edge",
        strips and strips.debuffs and strips.debuffs.borderColor[1] > 0.5,
        strips and strips.debuffs
            and tostring(strips.debuffs.borderColor[1]) or "absent")
    Check("and a buff strip keeps its green one",
        strips and strips.buffs and strips.buffs.borderColor[2] > 0.4,
        strips and strips.buffs
            and tostring(strips.buffs.borderColor[2]) or "absent")

    -- A bar-shaped place resolved through the real reader, not the table.
    local Look = ns.Cooldowns and ns.Cooldowns.Look
    if Look then
        local style = Look.Style({}, nil)
        Check("A bar with nothing set on it wears the house plate",
            math.abs(style.backdropColor[1] - v) < 0.005
                and style.backdropAlpha == 1,
            string.format("%.3f at %s", style.backdropColor[1],
                tostring(style.backdropAlpha)))
        -- The cooldown sweep is NOT a surface: it is drawn over the picture
        -- to say how much is left, and a grey veil makes a ready icon and a
        -- spent one look more alike.
        Check("but the cooldown sweep keeps its black",
            style.swipeColor[1] == 0, tostring(style.swipeColor[1]))
    end

    ---------------------------------------------------------------------
    -- THE FACE AND THE FLOOR
    ---------------------------------------------------------------------
    local kept = ns.db and ns.db.font
    if ns.db then ns.db.font = nil end
    Check("With nothing chosen the screen is set in Expressway",
        ns.ScreenFontName() == "Expressway", tostring(ns.ScreenFontName()))
    if ns.db then
        ns.db.font = ""
        Check("An empty choice is not a choice", ns.ScreenFontName()
            == ns.SCREEN_FONT)
        ns.db.font = "Friz Quadrata TT"
        Check("but a face the user picked still wins",
            ns.ScreenFontName() == "Friz Quadrata TT")
        ns.db.font = kept
    end

    local Text = ns.Cooldowns and ns.Cooldowns.Text
    if Text then
        -- A 24px bar: the worked-out name size is 24 * 0.45 = 10.8, which is
        -- above the floor, and the stacks want 7.2, which is not.
        local auto = Text.Style({}, 24)
        Check("A worked-out size never comes out under ten",
            auto.stacks.size >= ns.FONT_FLOOR
                and auto.charges.size >= ns.FONT_FLOOR
                and auto.countdown.size >= ns.FONT_FLOOR
                and auto.spellName.size >= ns.FONT_FLOOR,
            string.format("%.1f/%.1f/%.1f/%.1f", auto.countdown.size,
                auto.stacks.size, auto.charges.size, auto.spellName.size))

        -- HIS OWN PROFILE CARRIES A NINE. The rail's minimum moved, which
        -- stops a new one being made; a stored one is clamped where it is
        -- READ, so nothing reaches into a saved setting to do it.
        local typed = Text.Style({ countdown = { size = 6 } }, 40)
        Check("and a size typed before the rail moved is clamped, not obeyed",
            typed.countdown.size == ns.FONT_FLOOR,
            tostring(typed.countdown.size))

        -- THE ONE ELEMENT THAT SHIPPED WITH NO OUTLINE AT ALL, which is why
        -- it was the one that disappeared over a bright floor.
        Check("The spell name is outlined like everything else on screen",
            auto.spellName.outline == ns.SCREEN_OUTLINE,
            "\"" .. tostring(auto.spellName.outline) .. "\"")

        Check("and an element with no face of its own takes the screen's",
            auto.stacks.font == ns.ScreenFontName(),
            tostring(auto.stacks.font))
    end

    -- A NAME THE CLIENT CANNOT LOAD FALLS THROUGH THE HOUSE CHAIN. Straight
    -- to Blizzard's serif was a DIFFERENT DESIGN rather than one substituted
    -- face, and every band width in this addon is measured against a narrow
    -- grotesk.
    if ns.Media and ns.Media.ScreenFont then
        local named = ns.Media.Font("no such font is registered anywhere")
        Check("An unknown face falls through to a narrow grotesk",
            named == ns.Media.Font(ns.Media.ScreenFont()),
            tostring(named))
    end

    -- THE FLOOR IS IN ONE PLACE, so eleven call sites cannot each forget it.
    local asked = {}
    local fake = { SetFont = function(_, path, size, flags)
        asked = { path = path, size = size, flags = flags }
        return true
    end }
    ns.StyleFont(fake, 6)
    Check("The screen face clamps a six to the floor and outlines it",
        asked.size == ns.FONT_FLOOR and asked.flags == ns.SCREEN_OUTLINE,
        string.format("%s %s", tostring(asked.size), tostring(asked.flags)))

    ---------------------------------------------------------------------
    -- MOVING SOMEBODY'S SAVED SETTINGS
    ---------------------------------------------------------------------
    local Profiles = ns.Profiles
    if not (Profiles and Profiles.HouseLook) then
        Skip("Putting the house look on an old profile",
            "Core/Profiles.lua is not loaded")
        return
    end

    local function OldProfile()
        return {
            dbVersion = 7,
            font = "Arial Narrow",
            borderColor = { 0, 0, 0 },
            backdropColor = { 0, 0, 0 },
            backdropAlpha = 0.9,
            bars = {
                { name = "one", backdropColor = { 0, 0, 0 },
                  backdropAlpha = 0.9,
                  -- PICKED. The whole promise of the automatic step.
                  borderColor = { 0.9, 0.2, 0.2 },
                  spellName = { size = 9, outline = "", font = "" } },
            },
            coTanks = {
                bgColor = { 0.05, 0.05, 0.06 }, bgAlpha = 0.85,
                trackAlpha = 0.12,
                debuffs = { borderColor = { 0.75, 0.15, 0.15 } },
                buffs = { borderColor = { 0.25, 0.55, 0.30 } },
            },
            -- The same key name, a different design: a tracking group's
            -- trough IS the bar's own colour faded, and it stays.
            groups = { { trackAlpha = 0.08 } },
        }
    end

    local old = OldProfile()
    local moved = Profiles.HouseLook(old)
    Check("An old profile gets the house look on the version it lands on",
        moved > 0 and old.dbVersion == 8,
        string.format("%d moved, version %s", moved, tostring(old.dbVersion)))
    Check("Its plates and lines are #1a1a1a and opaque now",
        math.abs(old.backdropColor[1] - v) < 0.005
            and old.backdropAlpha == 1
            and math.abs(old.bars[1].backdropColor[1] - v) < 0.005,
        string.format("%.3f at %s", old.backdropColor[1],
            tostring(old.backdropAlpha)))
    Check("The panel's near-black plate joins them",
        math.abs(old.coTanks.bgColor[1] - v) < 0.005
            and old.coTanks.bgAlpha == 1,
        string.format("%.3f", old.coTanks.bgColor[1]))
    -- THE TROUGH IS THE ONE SETTING MOVED BY NAME rather than by the walk,
    -- because `trackAlpha` means two different designs in two places.
    Check("and so does the trough behind the fill",
        old.coTanks.trackAlpha == 1, tostring(old.coTanks.trackAlpha))
    Check("but a tracking group's ghost-of-itself trough is left alone",
        old.groups[1].trackAlpha == 0.08,
        tostring(old.groups[1].trackAlpha))
    Check("The screen face moves off the window's",
        old.font == ns.SCREEN_FONT, tostring(old.font))
    Check("A name with no outline gets one",
        old.bars[1].spellName.outline == ns.SCREEN_OUTLINE,
        "\"" .. tostring(old.bars[1].spellName.outline) .. "\"")

    -- THE PROMISE. Anything else here would be the addon overwriting a
    -- decision somebody made and never telling them.
    Check("but a colour he PICKED is left exactly where it was",
        old.bars[1].borderColor[1] == 0.9,
        tostring(old.bars[1].borderColor[1]))
    Check("and a size he typed is not rewritten either",
        old.bars[1].spellName.size == 9,
        tostring(old.bars[1].spellName.size))
    Check("and the two strips keep the colours that tell them apart",
        old.coTanks.debuffs.borderColor[1] > 0.5
            and old.coTanks.buffs.borderColor[2] > 0.4)

    -- ONCE PER PROFILE, EVER. Without the stamp this would move a colour back
    -- every login and the person who wants pure black would fight the addon
    -- once a session without ever finding out why.
    old.backdropColor = { 0, 0, 0 }
    Check("A second login does not do it again", Profiles.HouseLook(old) == 0
        and old.backdropColor[1] == 0, tostring(old.backdropColor[1]))

    -- A PROFILE FROM BEFORE dbVersion EXISTED IS OLD, NOT NEW - which is only
    -- true because this runs BEFORE ApplyDefaults stamps it.
    local ancient = OldProfile()
    ancient.dbVersion = nil
    Check("A profile with no version at all counts as old",
        Profiles.HouseLook(ancient) > 0 and ancient.dbVersion == 8)

    -- THE BUTTON. The same rule with force, which is what "put it all back"
    -- has to mean - including the colour the automatic step promised to leave
    -- alone.
    local pressed = OldProfile()
    pressed.dbVersion = 8
    local forced = ns.ApplyHouseLook(pressed, true)
    Check("The Standard look button reaches even a colour that was picked",
        forced > 0 and math.abs(pressed.bars[1].borderColor[1] - v) < 0.005,
        string.format("%d moved, %.3f", forced, pressed.bars[1].borderColor[1]))
    Check("and it still leaves the two strips their meaning",
        pressed.coTanks.debuffs.borderColor[1] > 0.5
            and pressed.coTanks.buffs.borderColor[2] > 0.4)
    Check("and pressing it twice is the same as pressing it once",
        ns.ApplyHouseLook(pressed, true) == 0,
        tostring(ns.ApplyHouseLook(pressed, true)))

    ---------------------------------------------------------------------
    -- VERSION 9: THE BARS STAND DOWN, ON THE OWNER'S WORD
    --
    -- The one migration that switches a feature off over a saved yes
    -- ("bitte abschalten", 2026-08-16). It may take the switch and NOTHING
    -- else: every bar, cell and look stays, so turning it back on finds
    -- the room as it was left.
    ---------------------------------------------------------------------
    local benched = OldProfile()
    benched.dbVersion = 8
    benched.modules = { cooldowns = true, cotanks = true }
    Check("Version 9 takes the cooldown switch off over a saved yes",
        Profiles.Bench(benched) == true
            and benched.modules.cooldowns == false
            and benched.dbVersion == 9,
        string.format("%s at version %s",
            tostring(benched.modules.cooldowns),
            tostring(benched.dbVersion)))
    Check("and touches nothing else on the way",
        benched.modules.cotanks == true and benched.bars[1] ~= nil
            and benched.bars[1].name == "one")
    Check("A second login does not repeat it",
        Profiles.Bench(benched) == false)
    benched.modules.cooldowns = true
    Check("so a yes given AFTER the update is kept",
        Profiles.Bench(benched) == false
            and benched.modules.cooldowns == true)
    local unversioned = OldProfile()
    unversioned.dbVersion = nil
    Check("A profile with no version at all is benched too",
        Profiles.Bench(unversioned) == true
            and unversioned.modules.cooldowns == false)

    ---------------------------------------------------------------------
    -- Version 10: the trough step version 8 missed
    --
    -- THE OWNER'S OWN PROFILE is the fixture: stamped 9, trough still 0.12,
    -- because the trough joined the house look one commit after his profile
    -- had been stamped 8. A step under a consumed number runs for nobody
    -- who was there first - it needs a number of its own.
    ---------------------------------------------------------------------
    local trough = OldProfile()
    trough.dbVersion = 9
    trough.coTanks = { trackAlpha = 0.12, width = 235 }
    Check("Version 10 moves a 0.12 trough that version 8 left behind",
        Profiles.Trough(trough) == 1
            and trough.coTanks.trackAlpha == 1
            and trough.dbVersion == 10,
        string.format("%s at version %s",
            tostring(trough.coTanks.trackAlpha), tostring(trough.dbVersion)))
    Check("and touches nothing else on the way",
        trough.coTanks.width == 235 and trough.bars[1].name == "one")
    Check("A second login does not repeat it",
        Profiles.Trough(trough) == 0)
    local chosen = OldProfile()
    chosen.dbVersion = 9
    chosen.coTanks = { trackAlpha = 0.5 }
    Check("A trough somebody chose is left alone, and still stamped",
        Profiles.Trough(chosen) == 0
            and chosen.coTanks.trackAlpha == 0.5
            and chosen.dbVersion == 10)
    local bare = OldProfile()
    bare.dbVersion = 9
    bare.coTanks = nil
    Check("A profile without a panel table is stamped and nothing breaks",
        Profiles.Trough(bare) == 0 and bare.dbVersion == 10)
end

function Test:Run()
    passed, failed, notes = 0, {}, {}

    local suites = {
        { "Modules",       TestModules },
        { "Language",      TestLocale },
        { "Raid bar",      TestRaidBar },
        { "Raid check",    TestRaidCheck },
        { "Invites",       TestInvites },
        { "CD request",    TestExternals },
        { "Spell identity", TestSpellIdentity },
        { "Active states", TestActiveStates },
        { "Design system",  TestDesignSystem },
        { "Menu filter",   TestMenuFilter },
        { "Co-tanks",      TestCoTanks },
        { "Co-tank strips", TestCoTankStrips },
        { "Reminders",     TestReminders },
        { "Game menu",     TestGameMenu },
        { "Anchors",       TestAnchors },
        { "Visibility",    TestVisibility },
        { "Media",         TestMedia },
        { "Profile migration", TestProfileMigration },
        { "Sharing",       TestShare },
        { "Cast history",  TestHistory },
        { "Death analysis", TestDeath },
        { "Raid deaths",   TestRaidDeaths },
        { "What's new",   TestNews },
        { "Panel movers",  TestPanelMovers },
        { "Taunts",        TestTaunts },
        { "Addon channel", TestComm },
        { "CD answer",     TestAnswers },
        { "Slider maths",  TestSliderMaths },
        { "Lists with two readers", TestCommandList },
        { "Sounds",        TestSounds },
        { "Frame contract", TestFrameContract },
        { "Other cooldown addons", TestRivals },
        { "Cooldown lattice", TestCooldownModel },
        { "Reading a stored bar", TestCooldownStore },
        { "Claiming and letting go", TestCooldownClaim },
        { "Placing a bar", TestCooldownRender },
        { "Places we draw ourselves", TestCooldownOwn },
        { "The house look", TestHouseLook },
        { "Routes",         TestRoutes },
        { "When to show it", TestWhenBlock },
        { "Deferred tabs",  TestLazyTabs },
        { "The styling layer", TestCooldownStyling },
    }

    for _, suite in ipairs(suites) do
        -- One suite that throws must not take the other seven with it. The
        -- throw is itself a failure and is reported as one.
        -- xpcall rather than pcall: the message alone says "attempt to index
        -- a nil value" and not WHERE, which is a whole afternoon of guessing
        -- on a suite that spans three files.
        local ok, err = pcall(suite[2])
        if not ok then
            failed[#failed + 1] = suite[1] .. " threw  |cff888888"
                .. tostring(err) .. "|r"
        end
    end

    ns.Print(string.format("|cffffd100self test|r  %d passed, %s",
        passed, #failed == 0 and "|cff40ff40nothing failed|r"
            or ("|cffff4040" .. #failed .. " FAILED|r")))

    for _, line in ipairs(failed) do
        ns.Print("  |cffff4040x|r " .. line)
    end

    for _, line in ipairs(notes) do
        ns.Print("  |cff888888- not checked:|r " .. line)
    end

    if #failed == 0 then
        ns.Print("|cff888888Green here means the model and the rules behave. "
            .. "It says nothing about how it LOOKS - that is still a pair of "
            .. "eyes on a screen.|r")
    end

    return #failed
end
