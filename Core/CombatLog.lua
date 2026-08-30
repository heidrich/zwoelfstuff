---------------------------------------------------------------------------
-- CombatLog.lua - what happened in the whole fight, not only in its last ten
-- seconds
--
-- The owner's ask, 2026-08-29: "ich moechte einen combat log haben, der mit
-- Warcraft logs vergleichbar ist. Auch mit dmg graphen und und ... was ist
-- mir passiert, was habe ich gemacht, was hat mich gekillt. mit zeitstrahl.
-- abspielen und und" - and, in the same breath, the shape it should take:
-- "sprich man koennte da auch einen erheblich besseren dmg meter draus
-- machen, also immer last fight!"
--
-- WHAT IS ALREADY TRUE, AND WHAT IS NOT. Three roads were named; two of them
-- are shut, and saying so up front is cheaper than finding out in the middle
-- of building on one.
--
--   1. THE EVENT IS CLOSED TO US - WHICH IS NOT THE SAME AS THE DATA BEING
--      GONE. Measured 2026-08-16 on 12.1.0 with `/zs route events` in a
--      dungeon: registering COMBAT_LOG_EVENT_UNFILTERED is refused outright
--      with ADDON_ACTION_FORBIDDEN - the refusal happens inside
--      RegisterEvent, raises no Lua error a pcall can catch, and merely
--      loses the function name. RaiderIO's own source carries the same note.
--
--      "So there is no per-hit stream to read, from us or from anybody" is
--      what stood here first, and it was wrong by one word. BLIZZARD'S OWN
--      combat log addon may register the event, and it does: the owner's
--      screenshot, 2026-08-29, is their Combat Log chat tab, full of
--      "Heavyweight Golem Melee hit You 143,954 Physical. (Critical)" and
--      "Your Crimson Vial healed You 45,577 Nature." Per hit, incoming and
--      outgoing, heals included.
--
--      So the honest statement is narrower: WE cannot register the event.
--      Whether their rendering of it is readable - as text off the chat
--      frame, or better, as the structured payload through a hook on the
--      function that formats it - is a live question, and CombatLog:Chat
--      below is what asks it. Nothing is built on either answer until that
--      dump comes back.
--
--   2. ADVANCED COMBAT LOGGING WRITES A FILE WE CAN NEVER READ. LoggingCombat
--      is what fills Logs/WoWCombatLog.txt, and that is exactly how Warcraft
--      Logs works - but the reader is their DESKTOP UPLOADER, not an addon.
--      An addon has no file I/O at all: it can start the recording and never
--      see a byte of it. ~~Worth offering as a convenience one day~~ - it
--      WAS offered, as a button in the corner, and came out again on
--      2026-08-30: "die funktion und button fuer den advanced combat log
--      kannste rausnehmen, da wir den ja eh nicht verwenden." Useless as a
--      source, and a switch nobody presses is a control that only has to be
--      kept working. The probe still dumps whether the client offers it,
--      because that is a fact about the client and not a feature here.
--
--   3. WHAT IS OPEN IS FAR MORE THAN THIS FILE FIRST ASSUMED, and the proof
--      was in the owner's own AddOns folder rather than in any reasoning.
--
--      The owner, 2026-08-29: "also es muss ja alles gehen. dmg meter liest
--      die daten aus." He was right, and the reason is worth writing down:
--      Blizzard did not simply close the combat log, they REPLACED it with a
--      structured API - and this file was designing around a corner of it
--      because that corner was all the death log happened to use.
--
--      EllesmereUIDamageMeters is installed, runs on 12.1, and registers NO
--      combat log event at all. Read off its source:
--
--        C_DamageMeter.GetAvailableCombatSessions()      -- past fights, by id
--        C_DamageMeter.GetCombatSessionFromID(id, type)
--        C_DamageMeter.GetCombatSessionFromType(session, type)
--        C_DamageMeter.GetCombatSessionSourceFromID(id, type, guid, creature)
--        C_DamageMeter.GetCombatSessionSourceFromType(...)
--        C_DamageMeter.GetSessionDurationSeconds(session)
--        C_DamageMeter.ResetAllCombatSessions()
--
--      Enum.DamageMeterType is not three values but at least eight:
--      DamageDone, HealingDone, DamageTaken, AvoidableDamageTaken,
--      EnemyDamageTaken, Deaths, Dispels, Interrupts.
--
--      And a SOURCE carries its spells: `srcData.combatSpells` is a list,
--      each entry with `totalAmount` and a `combatSpellDetails` table. That
--      is the per-spell breakdown, from the client, structured.
--
--      WHAT A SOURCE ROW ACTUALLY CARRIES, read off the same file 2026-08-30
--      and none of it used here yet:
--
--        isLocalPlayer      "this row is you" - documented NEVER SECRET, so
--                           it beats matching names, which is what this addon
--                           does and which fails across realms and whenever
--                           the client withholds the name
--        specIconID         the spec's own icon, not just the class
--        amountPerSecond    per second, computed by the CLIENT
--        deathTimeSeconds   when in the fight that source died
--        deathRecapID       also NEVER SECRET - and C_DeathRecap.GetRecapEvents
--                           takes a plain id, so ANY death in the group can be
--                           read hit by hit, from the client, with nobody else
--                           running this addon
--
--      AND WHAT IS IN combatSpellDetails - the "last unknown" this file names
--      a hundred lines down. It is answered:
--
--        unitName, unitClassFilename, specIconID
--
--      i.e. WHO the spell belongs to. On EnemyDamageTaken that is which
--      player hit the enemy; on DamageTaken it should be who hit you, which
--      is the one thing the owner asked for that this window cannot answer
--      today. Worth one probe run in a real fight before anything is built
--      on it: read off a source is good enough to act on, not good enough to
--      write down as fact.
--
--      GetAvailableCombatSessions() returns entries with sessionID, name and
--      durationSeconds - so the CLIENT keeps a list of past fights, named.
--      This addon's own recorder exists because that was assumed not to be
--      the case; see the Note in the 4.95.0 changelog, which is wrong.
--
--      Three events push the changes instead of us polling blind:
--      DAMAGE_METER_CURRENT_SESSION_UPDATED,
--      DAMAGE_METER_COMBAT_SESSION_UPDATED, DAMAGE_METER_RESET.
--
--      Beside it: UNIT_SPELLCAST_* for the player (ns.History already keeps
--      every press with its clock), UNIT_AURA, UNIT_HEALTH, and
--      C_DeathRecap around a fall.
--
-- WHAT IS STILL SAMPLED, AND WHAT IS NOT. The API answers with TOTALS, not
-- with a time series - so a curve is still built by reading repeatedly and
-- differencing. What changed is that the reads are driven by the client's
-- own update event rather than by a blind timer, and that every read is a
-- structured, per-spell, per-source number instead of one lump.
--
-- The honest ceiling is therefore not "aggregate only" - it is TIME
-- RESOLUTION: as fine as the meter updates, not per hit to the millisecond.
-- Warcraft Logs gets that from the FILE, read by their desktop uploader.
--
-- WHAT THIS FILE IS TODAY: the window, and the probe that came before it.
--
-- THE WINDOW IS BUILT ON WHAT MAY BE SHOWN, NOT ON WHAT MAY BE READ - which
-- is why it could be built before the outstanding measurements came back.
-- Three doors, and the page only ever goes through them:
--
--   * A NUMBER is drawn with SetFormattedText, the one setter that declares
--     a secret argument. It is never concatenated, compared or added.
--   * A BAR is a StatusBar. SetMinMaxValues and SetValue hand both numbers
--     to the engine and the engine does the division - a bar drawn in Lua
--     would BE the division, and division is the forbidden operation.
--   * THE ORDER comes from the client, which returns its list already
--     ranked. Reading rank off the ORDER costs nothing; reading it off the
--     values would be a comparison.
--
-- So the page is correct whether the amounts turn out to be secret or plain,
-- and neither answer to the outstanding probe can invalidate it.
--
-- WHAT THE REST OF THE EVENING THEN BOUGHT, because this paragraph used to
-- end by listing them as deliberately withheld and that stopped being true
-- the same night: the per-spell breakdown IS here (CombatLog.SourceSpells,
-- CombatLog.MySpells) and so is the percentage (CombatLog.Share), both off
-- the owner's own screenshot showing a readable 24.46M after the pull. What
-- is still NOT here is a curve over time - that one needs a per-hit stream,
-- which is what /zs combat chat is for.
--
--   /zs combat            - the window
--   /zs combat probe      - what the damage meter hands over, in full
--   /zs combat chat       - what Blizzard's own combat log is holding
--   /zs combat cleu       - re-measure whether the event itself is shut
---------------------------------------------------------------------------
local _, ns = ...

local CombatLog = {}
ns.CombatLog = CombatLog

---------------------------------------------------------------------------
-- Printing what a value IS, without ever printing a secret
--
-- The same three-way verdict the death probe uses - absent, secret, or the
-- value - because a probe that prints "nil" for a withheld field would send
-- the reader looking for a missing feature instead of a closed door. Tables
-- answer with their length: the address says nothing, but "there are eleven
-- entries in here" is often the whole answer.
---------------------------------------------------------------------------
-- WHOSE ROW THIS IS. The rule lives in RaidDeaths and has been checked
-- against a real client's list; a second copy of it here would be a second
-- thing to get wrong.
local function RaidDeathsIsYou(row)
    if not (ns.RaidDeaths and ns.RaidDeaths.IsYou) then return false end
    return ns.RaidDeaths.IsYou(row)
end

local function Verdict(value)
    if value == nil then return "|cff888888absent|r" end
    if not ns.CanCompute(value) then return "|cffff8040SECRET|r" end
    if type(value) == "function" then return "|cff7ec6d4function|r" end
    if type(value) == "table" then
        local count = 0
        for _ in pairs(value) do count = count + 1 end
        return string.format("|cff7ec6d4table, %d list / %d keys|r",
            #value, count)
    end
    return "|cff40ff40" .. tostring(value) .. "|r"
end

-- One table, key by key, sorted so two runs read the same. `depth` walks INTO
-- nested tables, which is the point: a per-spell breakdown would hang under a
-- source row, and a dumper that stops at the top would report the one field
-- that matters as "table" and leave the question open for another pull.
local function Dump(label, tbl, depth, pad)
    pad = pad or "  "
    ns.Print(pad .. label .. ":")
    if type(tbl) ~= "table" then
        ns.Print(pad .. "  " .. Verdict(tbl))
        return
    end
    local keys = {}
    for key in pairs(tbl) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
        local value = tbl[key]
        ns.Print(pad .. "  " .. tostring(key) .. " = " .. Verdict(value))
        -- INTO IT, but only one branch and only a few rows: this goes to a
        -- chat frame, and a raid's worth of sources printed in full is a
        -- wall nobody reads. The FIRST entry of a list is what answers
        -- "what shape are these".
        if depth and depth > 0 and type(value) == "table"
            and ns.CanCompute(value) and #value > 0 then
            Dump(tostring(key) .. "[1] of " .. #value, value[1], depth - 1,
                pad .. "    ")
        end
    end
end

---------------------------------------------------------------------------
-- THE PROBE
--
-- Run it right after a pull, before the client rolls the Current session
-- over. It answers, in one go, every question the module's design hangs on.
---------------------------------------------------------------------------

-- EVERY MEMBER OF AN ENUM, sorted by value. The death probe learned this the
-- hard way: it walked the session types rather than asking for the two the
-- addon happened to know, and that is what ruled out "the deaths are in a
-- session we never ask for" without a second trip.
local function Members(enum)
    local out = {}
    for name, value in pairs(enum or {}) do
        if type(value) == "number" then
            out[#out + 1] = { key = value, label = name }
        end
    end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

function CombatLog:Probe()
    -- WHICH STATE THE READING WAS TAKEN IN, first line and always.
    --
    -- Secret-ness on this patch is CONTEXTUAL - Secrets.lua records that a
    -- charge count is secret "in combat" and plain outside it. So a dump
    -- that does not say whether it ran in combat is a dump whose every
    -- SECRET could mean two different things, and the answer changes what
    -- this whole module can be. Run it twice: once mid-fight, once ten
    -- seconds after.
    local fighting = UnitAffectingCombat and UnitAffectingCombat("player")
    ns.Print(string.format("|cffffd100combat probe|r - taken %s.",
        fighting and "|cffff8040IN COMBAT|r"
            or "|cff40ff40OUT of combat|r"))

    -----------------------------------------------------------------------
    -- WHAT THE METER EVEN OFFERS. This is the cheapest question and the one
    -- most likely to change the design: the death log calls exactly one
    -- function on C_DamageMeter, and nothing has ever looked at what else is
    -- in there. A per-spell call sitting in this table would be worth more
    -- than everything else on this page.
    -----------------------------------------------------------------------
    if type(C_DamageMeter) ~= "table" then
        ns.Print("  C_DamageMeter is |cffff4040not on this client|r - "
            .. "there is no meter to read and the module stops here.")
        return
    end
    Dump("C_DamageMeter, every name in it", C_DamageMeter, 0)

    Dump("Enum.DamageMeterType", Enum and Enum.DamageMeterType, 0)
    Dump("Enum.DamageMeterSessionType", Enum and Enum.DamageMeterSessionType, 0)

    if not (C_DamageMeter.GetCombatSessionFromType and Enum
        and Enum.DamageMeterType and Enum.DamageMeterSessionType) then
        ns.Print("  |cffff8040No session call and no enums|r - the rest of "
            .. "this probe has nothing to ask with.")
        return
    end

    -----------------------------------------------------------------------
    -- EVERY TYPE IN EVERY SESSION. Nine combinations at most, and the ones
    -- that answer nothing are as much of an answer as the ones that do.
    --
    -- TWO ROWS PER COMBINATION, walked one level deep. The question is not
    -- "what did I do last fight" - it is "what SHAPE does the client hand
    -- back", and the second row is there because the first is as likely as
    -- not to be the player and therefore the special case.
    -----------------------------------------------------------------------
    local kinds = Members(Enum.DamageMeterType)
    local sessions = Members(Enum.DamageMeterSessionType)

    for _, kind in ipairs(kinds) do
        for _, session in ipairs(sessions) do
            local where = string.format("%s / %s", kind.label, session.label)
            local ok, got = pcall(C_DamageMeter.GetCombatSessionFromType,
                session.key, kind.key)
            if not ok then
                ns.Print("  " .. where .. ": |cffff4040the call threw|r")
            elseif type(got) ~= "table" then
                ns.Print("  " .. where .. ": " .. Verdict(got))
            else
                Dump(where .. " - the session itself", got, 0)
                local list = got.combatSources
                if type(list) ~= "table" or not ns.CanCompute(list) then
                    ns.Print("    no readable list of sources in it")
                else
                    for index = 1, math.min(#list, 2) do
                        -- ONE LEVEL DEEP. If a source carries its spells,
                        -- they are a table on this row and this is where
                        -- they will show up.
                        Dump(string.format("%s row %d of %d", where, index,
                            #list), list[index], 1, "    ")
                    end
                end
            end
        end
    end

    -----------------------------------------------------------------------
    -- THE PER-SPELL BREAKDOWN, which is the one thing a Warcraft-Logs-shaped
    -- window cannot be built without.
    --
    -- A working meter on this client reads it as
    -- `GetCombatSessionSourceFromType(session, type, guid, creatureID)` and
    -- then walks `srcData.combatSpells`, each entry carrying `totalAmount`
    -- and a `combatSpellDetails` table. What is IN those details is the last
    -- unknown - a spell id there means icons and tooltips for free, and no
    -- name parsing anywhere.
    --
    -- Asked about the PLAYER's own row, because this module is personal
    -- first and because that row is certain to exist while a group mate's
    -- may not.
    -----------------------------------------------------------------------
    if C_DamageMeter.GetCombatSessionSourceFromType and Enum.DamageMeterType
        and Enum.DamageMeterType.DamageDone then
        ns.Print("  |cffffd100your own damage, spell by spell|r:")
        local ok, got = pcall(C_DamageMeter.GetCombatSessionFromType,
            Enum.DamageMeterSessionType.Current,
            Enum.DamageMeterType.DamageDone)
        local mine
        if ok and type(got) == "table" then
            for _, row in ipairs(got.combatSources or {}) do
                if RaidDeathsIsYou(row) then mine = row break end
            end
        end
        if not mine then
            ns.Print("    no row for you in the Current DamageDone session - "
                .. "run this right after a pull")
        else
            Dump("your row in the meter", mine, 0, "    ")
            -- ASKED WITH THE PLAIN OWN GUID. The row's own sourceGUID is
            -- withheld while a fight is running and the getters refuse a
            -- secret argument, so a probe that handed the row's id back
            -- reported "the per-source call answered absent" for the one
            -- reason that is ours to fix.
            local ok2, src = pcall(
                C_DamageMeter.GetCombatSessionSourceFromType,
                Enum.DamageMeterSessionType.Current,
                Enum.DamageMeterType.DamageDone,
                UnitGUID and UnitGUID("player") or mine.sourceGUID, nil)
            if not ok2 or type(src) ~= "table" then
                ns.Print("    the per-source call answered "
                    .. Verdict(ok2 and src or nil))
            else
                Dump("the source detail", src, 0, "    ")
                local spells = src.combatSpells
                if type(spells) ~= "table" then
                    ns.Print("    no combatSpells on it")
                else
                    ns.Print(string.format(
                        "    combatSpells: %d of them", #spells))
                    for index = 1, math.min(#spells, 2) do
                        Dump("spell " .. index, spells[index], 1, "      ")
                    end
                end
            end
        end
    end

    -----------------------------------------------------------------------
    -- THE FIGHTS THE CLIENT ITSELF STILL HAS.
    --
    -- This addon records its own pulls at the moment combat drops, because
    -- the window was built believing the client keeps only the fight that is
    -- running and the evening's total. It does not: GetAvailableCombatSessions
    -- hands over a LIST, and GetCombatSessionFromID reads any of them.
    --
    -- Read off EllesmereUIDamageMeters, 2026-08-30, which is installed here
    -- and offers exactly that as its "Select Segment" menu. What is not read
    -- off anything is how MANY it keeps, whether the names are the boss or
    -- the first mob, whether an id survives a reload, and whether the
    -- amounts in an old one are readable in combat. All four decide whether
    -- our own recorder can retire or has to stay, so all four are asked here
    -- rather than guessed at.
    -----------------------------------------------------------------------
    if C_DamageMeter.GetAvailableCombatSessions then
        ns.Print("  |cffffd100the fights the client still has|r:")
        local ok, list = pcall(C_DamageMeter.GetAvailableCombatSessions)
        if not ok or type(list) ~= "table" then
            ns.Print("    the call answered " .. Verdict(ok and list or nil))
        elseif not ns.CanCompute(list) then
            ns.Print("    the list itself came back withheld")
        else
            ns.Print(string.format("    %d of them", #list))
            -- NEWEST FIRST is a guess about their order, so both ends are
            -- printed and the dump settles it.
            for index = 1, math.min(#list, 3) do
                Dump("session " .. index, list[index], 1, "      ")
            end
            if #list > 3 then
                Dump("the last one", list[#list], 1, "      ")
            end
            -- AND ONE OF THEM READ BY ITS ID, which is the call this window
            -- would have to live on.
            local one = list[#list]
            local id = type(one) == "table" and one.sessionID or nil
            if id ~= nil and C_DamageMeter.GetCombatSessionFromID
                and Enum and Enum.DamageMeterType then
                local ok2, got = pcall(C_DamageMeter.GetCombatSessionFromID,
                    id, Enum.DamageMeterType.DamageDone)
                if not ok2 or type(got) ~= "table" then
                    ns.Print("    reading it by id answered "
                        .. Verdict(ok2 and got or nil))
                else
                    Dump("that session, by id", got, 0, "      ")
                    local rows = got.combatSources
                    if type(rows) == "table" and ns.CanCompute(rows)
                        and rows[1] then
                        Dump("its first source", rows[1], 1, "        ")
                    end
                end
            end
        end
    end

    -----------------------------------------------------------------------
    -- WHO HIT YOU, WHICH IS THE ONE THING THIS WINDOW CANNOT SAY.
    --
    -- Owner, 2026-08-30: "vor den dmg icons brauchen wir die avatar bilder
    -- von gegner oder selbst mit hover links, damit man auch sieht, von wem
    -- hab ich den schaden bekommen." The meter names the ABILITY that hit
    -- you and this window draws that; the caster is not on the row.
    --
    -- It may be one level down. EllesmereUIDamageMeters reads
    -- `spell.combatSpellDetails` and finds `unitName`, `unitClassFilename`
    -- and `specIconID` in it - which on EnemyDamageTaken is which PLAYER hit
    -- the enemy. Whether the same field on DamageTaken names who hit YOU is
    -- the whole question, and it is one dump away.
    -----------------------------------------------------------------------
    if C_DamageMeter.GetCombatSessionSourceFromType and Enum.DamageMeterType
        and Enum.DamageMeterType.DamageTaken then
        ns.Print("  |cffffd100who hit you|r, one level under the ability:")
        local ok, got = pcall(C_DamageMeter.GetCombatSessionFromType,
            Enum.DamageMeterSessionType.Current,
            Enum.DamageMeterType.DamageTaken)
        local mine
        if ok and type(got) == "table" then
            for _, row in ipairs(got.combatSources or {}) do
                if RaidDeathsIsYou(row) then mine = row break end
            end
        end
        if not mine then
            ns.Print("    nothing has hit you in this session yet - "
                .. "run it after taking a few hits")
        else
            local ok2, src = pcall(
                C_DamageMeter.GetCombatSessionSourceFromType,
                Enum.DamageMeterSessionType.Current,
                Enum.DamageMeterType.DamageTaken,
                UnitGUID and UnitGUID("player") or mine.sourceGUID, nil)
            local spells = ok2 and type(src) == "table" and src.combatSpells
            if type(spells) ~= "table" or not ns.CanCompute(spells) then
                ns.Print("    no readable spell list on it")
            else
                for index = 1, math.min(#spells, 2) do
                    local spell = spells[index]
                    Dump("incoming spell " .. index, spell, 1, "      ")
                    if type(spell) == "table" then
                        Dump("its details", spell.combatSpellDetails, 2,
                            "        ")
                    end
                end
            end
        end
    end

    -----------------------------------------------------------------------
    -- HOW DEEP THE ONE SOURCE WITH REAL NUMBERS ACTUALLY GOES.
    --
    -- Owner, 2026-08-29: "wie koennen wir dann den death log lesen, wo wir
    -- auch jeden spell sehen". Because it is a DIFFERENT API. The meter's
    -- amounts are secret; C_DeathRecap's are real - this addon has been
    -- adding, comparing and formatting them for weeks.
    --
    -- Which makes the size of that window the question the module's scope
    -- hangs on. `WINDOW = 10` in Death.lua is OUR trim, not the client's,
    -- and nobody has ever asked how much the client offered before we cut
    -- it. If a recap reaches back thirty seconds, a death-centred combat log
    -- covers most of a wipe with real per-hit numbers.
    -----------------------------------------------------------------------
    if C_DeathRecap and C_DeathRecap.GetRecapEvents then
        ns.Print("  |cffffd100how far back a death recap reaches|r "
            .. "(the one source with real numbers):")
        local id
        local ok, deaths = pcall(C_DamageMeter.GetCombatSessionFromType,
            Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.Deaths)
        if not (ok and type(deaths) == "table") then
            ok, deaths = pcall(C_DamageMeter.GetCombatSessionFromType,
                Enum.DamageMeterSessionType.Overall,
                Enum.DamageMeterType.Deaths)
        end
        for _, row in ipairs((ok and type(deaths) == "table"
            and deaths.combatSources) or {}) do
            local rid = row.deathRecapID
            if ns.CanCompute(rid) and type(rid) == "number" and rid > 0 then
                id = rid
                break
            end
        end
        if not id then
            ns.Print("    no death in the meter's list to ask about - "
                .. "this one needs somebody to have died")
        else
            local okEv, events = pcall(C_DeathRecap.GetRecapEvents, id)
            if not (okEv and type(events) == "table") then
                ns.Print("    recap " .. id .. " answered " .. Verdict(events))
            else
                local oldest, newest, real, secret = nil, nil, 0, 0
                for _, ev in ipairs(events) do
                    -- ASSIGNED, NOT CHAINED. `x and y or nil` boolean-tests
                    -- what the `and` produced, and what it produces here is a
                    -- field off somebody else's table that may be withheld.
                    local t
                    if type(ev) == "table" then t = ev.timestamp end
                    if ns.CanCompute(t) and type(t) == "number" then
                        if not oldest or t < oldest then oldest = t end
                        if not newest or t > newest then newest = t end
                    end
                    local amount
                    if type(ev) == "table" then amount = ev.amount end
                    if ns.CanCompute(amount) then real = real + 1
                    elseif amount ~= nil then secret = secret + 1 end
                end
                ns.Print(string.format(
                    "    recap %d: %d events, %d with a readable amount, "
                    .. "%d secret", id, #events, real, secret))
                if oldest and newest then
                    ns.Print(string.format(
                        "    it reaches back %.1f seconds", newest - oldest))
                else
                    ns.Print("    no readable timestamps on them")
                end
                Dump("the oldest event, every field", events[1], 0, "    ")
            end
        end
    end

    -----------------------------------------------------------------------
    -- THE FILE ROAD, ASKED RATHER THAN ASSUMED. We cannot read what it
    -- writes - an addon has no file I/O - so this can never feed a graph.
    -- It is asked because turning the recording on for somebody who uploads
    -- to Warcraft Logs is a one-line convenience, and a convenience that
    -- turns out to be forbidden is worth knowing about before it is offered.
    -----------------------------------------------------------------------
    ns.Print("  |cffffd100the file road|r (writes Logs\\WoWCombatLog.txt, "
        .. "which no addon can read back):")
    ns.Print("    LoggingCombat = " .. Verdict(LoggingCombat))
    if type(LoggingCombat) == "function" then
        local ok, on = pcall(LoggingCombat)
        ns.Print("    recording right now = "
            .. (ok and Verdict(on) or "|cffff4040the call threw|r"))
    end
    if GetCVar then
        local ok, value = pcall(GetCVar, "advancedCombatLogging")
        ns.Print("    advancedCombatLogging = "
            .. (ok and Verdict(value) or "|cffff4040refused|r"))
    end

    ns.Print("  |cff888888We may not register "
        .. "COMBAT_LOG_EVENT_UNFILTERED - refused with "
        .. "ADDON_ACTION_FORBIDDEN when it was measured on 12.1.0, and "
        .. "|cffffd100/zs combat cleu|r re-measures that. Blizzard's own "
        .. "combat log DOES have the per-hit stream; "
        .. "|cffffd100/zs combat chat|r asks what of it we can read.|r")
end

---------------------------------------------------------------------------
-- WHAT BLIZZARD'S OWN COMBAT LOG WILL SHOW US
--
-- Owner, 2026-08-29, with a screenshot of his Combat Log tab: "das muss
-- gehen, wir haben im chat von blizzard einen eigenen combat log mit was hab
-- ich gemacht und was kommt rein, also auch heal etc." He is right that the
-- data is on his screen. What is NOT yet known is which of three doors is
-- open, and they are worth very different amounts:
--
--   THE GOOD ONE: Blizzard's combat log is a Lua addon. If the function it
--   formats each event through is a global, `hooksecurefunc` on it hands us
--   the STRUCTURED payload - timestamp, event, source, spell id, amount -
--   with no text parsing at all. This is the one worth having.
--
--   THE WORKABLE ONE: the formatted line, read off the chat frame. Every
--   ScrollingMessageFrame answers GetNumMessages and GetMessageInfo, so this
--   dump can print what is ALREADY on his screen and settle the one question
--   that decides how much work it is - does the line carry |Hspell: links
--   (ids, language-proof) or only names (a locale-dependent parse)?
--
--   THE TRAP: those two filter buttons. "My actions" and "What happened to
--   me?" are FILTERS. If they decide what reaches the frame at all, then
--   whatever we read is whatever he happens to have selected - and a log
--   that quietly shows a subset is worse than one that says it cannot see.
--   So the filter settings are dumped too.
--
-- Nothing is hooked here. This looks and reports; the hook is a decision to
-- take once the shape is known.
---------------------------------------------------------------------------

-- WHICH FRAME IS THE COMBAT LOG. Not guessed at ChatFrame2: it is a frame
-- anybody can move, rename or undock. Every chat frame is walked and asked
-- what it is holding, and the answer is whichever one has combat lines in
-- it - which the dump shows rather than decides.
local function ChatFrames()
    local out = {}
    local names = _G.CHAT_FRAMES
    if type(names) == "table" then
        for _, name in ipairs(names) do
            local frame = _G[name]
            if type(frame) == "table" then
                out[#out + 1] = { name = name, frame = frame }
            end
        end
        return out
    end
    -- The list is a global that a broken client could withhold; the frames
    -- themselves are named predictably, so the fallback still finds them.
    for index = 1, 10 do
        local name = "ChatFrame" .. index
        local frame = _G[name]
        if type(frame) == "table" then
            out[#out + 1] = { name = name, frame = frame }
        end
    end
    return out
end

-- One line, made safe to print - and HONEST ABOUT WHAT IT DID.
--
-- The first version printed three blank lines for the combat log's 94
-- messages and left it at that, which reads like "the frame is empty" and is
-- a different fact from "the reader flattened everything away". So the raw
-- length goes out with the text: a line that was 120 characters long and is
-- now nothing is a bug in this function, not an empty frame.
--
-- The escape codes are stripped so the dump does not paint itself, and the
-- markup we are actually LOOKING for - the |H hyperlink that carries a spell
-- id - is reported separately rather than swallowed.
local function Line(text)
    if not ns.CanCompute(text) then return "|cffff8040SECRET|r", false, 0 end
    if type(text) ~= "string" then return Verdict(text), false, 0 end
    local raw = #text
    local linked = text:find("|H", 1, true) ~= nil
    -- The name INSIDE a link is the part worth keeping, so the two tags are
    -- taken off separately rather than with one pattern across the middle.
    local flat = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    flat = flat:gsub("|H[^|]*|h", ""):gsub("|h", "")
    flat = flat:gsub("|T[^|]*|t", "[icon]")
    flat = flat:gsub("|A[^|]*|a", "[atlas]")
    if #flat > 140 then flat = flat:sub(1, 140) .. " ..." end
    if flat == "" then flat = "|cff888888(nothing left after stripping)|r" end
    return flat, linked, raw
end

function CombatLog:Chat()
    ns.Print("|cffffd100combat chat|r - what Blizzard's own combat log is "
        .. "holding, and whether an addon can read it.")

    -----------------------------------------------------------------------
    -- THE STRUCTURED DOOR FIRST, because it is worth more than the other
    -- two put together. If any of these is a function, their addon formats
    -- events through it and a hook gets the payload before it becomes text.
    -----------------------------------------------------------------------
    -----------------------------------------------------------------------
    -- EVERY GLOBAL THEIR ADDON LEFT LYING ABOUT, found by walking rather
    -- than by naming.
    --
    -- The first run asked for six names off the top of my head and two of
    -- them existed. That is the wrong shape of question: the entry point
    -- this needs is whatever THIS build calls it, and a list I wrote from
    -- memory cannot contain a name Blizzard renamed. So the globals are
    -- walked and every CombatLog-ish one is printed with its type - the
    -- functions among them are the candidates for a hook.
    -----------------------------------------------------------------------
    ns.Print("  |cffffd100every CombatLog global on this build|r:")
    do
        local found = {}
        for name, value in pairs(_G) do
            if type(name) == "string"
                and (name:find("CombatLog", 1, true)
                    or name:find("COMBATLOG", 1, true)
                    or name:find("COMBAT_LOG", 1, true)) then
                found[#found + 1] = { name = name, kind = type(value) }
            end
        end
        table.sort(found, function(a, b)
            if a.kind ~= b.kind then return a.kind < b.kind end
            return a.name < b.name
        end)
        ns.Print("    " .. #found .. " of them:")
        for _, one in ipairs(found) do
            ns.Print("      " .. one.kind .. "  " .. one.name)
        end
    end

    ns.Print("  |cffffd100the structured door|r (a hook here would beat "
        .. "parsing text):")
    local doors = {
        "CombatLog_OnEvent", "CombatLog_AddEvent", "CombatLog_Object_IsA",
        "CombatLog_String_GetIcon", "Blizzard_CombatLog_CurrentSettings",
        "Blizzard_CombatLog_Filters", "COMBATLOG", "CombatLogQuickButtonFrame",
        "CombatLogGetCurrentEventInfo", "hooksecurefunc",
    }
    for _, name in ipairs(doors) do
        ns.Print("    " .. name .. " = " .. Verdict(_G[name]))
    end
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, "Blizzard_CombatLog")
        ns.Print("    Blizzard_CombatLog loaded = "
            .. (ok and Verdict(loaded) or "|cffff4040refused|r"))
    end

    -----------------------------------------------------------------------
    -- THE FRAME THAT HEARS THE EVENT.
    --
    -- COMBATLOG came back with 172 keys, which means it is their chat frame
    -- and not a stub. If IT is the frame registered for the combat log
    -- event, then its OnEvent script is the function that receives every
    -- hit - and a wrapper around a script we did not write is a very
    -- different thing from registering an event we are not allowed to.
    -- Whether that wrapper would then SEE the payload is the next question
    -- and this only establishes whether there is a script to wrap.
    -----------------------------------------------------------------------
    local frame = _G.COMBATLOG
    if type(frame) == "table" then
        ns.Print("  |cffffd100the combat log frame itself|r:")
        local name = type(frame.GetName) == "function"
            and select(2, pcall(frame.GetName, frame)) or nil
        ns.Print("    it is called " .. Verdict(name))
        if type(frame.GetScript) == "function" then
            local ok, script = pcall(frame.GetScript, frame, "OnEvent")
            ns.Print("    OnEvent script = "
                .. (ok and Verdict(script) or "|cffff4040refused|r"))
        end
        if type(frame.IsEventRegistered) == "function" then
            for _, event in ipairs({ "COMBAT_LOG_EVENT_UNFILTERED",
                "COMBAT_LOG_EVENT", "COMBAT_TEXT_UPDATE" }) do
                local ok, on = pcall(frame.IsEventRegistered, frame, event)
                ns.Print("    listens to " .. event .. " = "
                    .. (ok and Verdict(on) or "|cffff4040refused|r"))
            end
        end
    end

    -----------------------------------------------------------------------
    -- THE FILTERS, because they decide what is in the frame at all.
    --
    -- The first run answered this: the selected filter is called "My
    -- actions" and its two sub-filters carry an eventList of forty keys.
    -- Forty EVENT NAMES is the list of what reaches the frame, so it is
    -- printed in full - it is the exact ceiling on what a reader could ever
    -- see with that button pressed.
    -----------------------------------------------------------------------
    local settings = _G.Blizzard_CombatLog_CurrentSettings
    if type(settings) == "table" and ns.CanCompute(settings) then
        Dump("the combat log's own settings", settings, 1)
        local filters = settings.filters
        if type(filters) == "table" then
            for index, one in ipairs(filters) do
                local list = type(one) == "table" and one.eventList
                if type(list) == "table" then
                    local names = {}
                    for key in pairs(list) do names[#names + 1] = tostring(key) end
                    table.sort(names)
                    ns.Print(string.format(
                        "    filter %d passes %d events:", index, #names))
                    -- In rows, or forty names is forty lines in his chat.
                    local row = ""
                    for _, one2 in ipairs(names) do
                        row = row .. (row == "" and "" or ", ") .. one2
                        if #row > 90 then ns.Print("      " .. row) row = "" end
                    end
                    if row ~= "" then ns.Print("      " .. row) end
                end
            end
        end
    end
    Dump("every filter the client has", _G.Blizzard_CombatLog_Filters, 1)

    -----------------------------------------------------------------------
    -- AND WHAT IS ACTUALLY ON HIS SCREEN. Three lines per frame is enough
    -- to see which one is the combat log and whether its lines carry ids.
    -----------------------------------------------------------------------
    ns.Print("  |cffffd100every chat frame, and its last few lines|r:")
    for _, entry in ipairs(ChatFrames()) do
        local chat = entry.frame
        local tab = _G[entry.name .. "Tab"]
        local title
        if tab and tab.Text and tab.Text.GetText then
            local ok, text = pcall(tab.Text.GetText, tab.Text)
            if ok and ns.CanCompute(text) then title = text end
        end

        local count
        if type(chat.GetNumMessages) == "function" then
            local ok, got = pcall(chat.GetNumMessages, chat)
            if ok then count = got end
        end

        ns.Print(string.format("    %s (%s): %s messages",
            entry.name, tostring(title or "no tab name"),
            count == nil and "|cffff8040cannot be asked|r" or tostring(count)))

        if type(count) == "number" and count > 0
            and type(chat.GetMessageInfo) == "function" then
            local anyLinked = false
            -- BOTH ENDS. Which end of a scrolling frame index 1 is depends
            -- on the implementation, and the first run read three blanks off
            -- the combat log - "the newest are empty" and "we read the wrong
            -- end" look identical from one sample.
            local want = { 1, 2, count - 1, count }
            local seen = {}
            for _, index in ipairs(want) do
                if index >= 1 and index <= count and not seen[index] then
                    seen[index] = true
                    local ok, text = pcall(chat.GetMessageInfo, chat, index)
                    if ok then
                        local flat, linked, raw = Line(text)
                        anyLinked = anyLinked or linked
                        ns.Print(string.format("        [%d] %d chars: %s",
                            index, raw, flat))
                    else
                        ns.Print(string.format(
                            "        [%d] |cffff4040the call threw|r", index))
                    end
                end
            end
            -- THE QUESTION THAT DECIDES THE WORK. A line with |Hspell: in it
            -- carries an ID and reads the same in every language; a line
            -- without one is a parse against localised words, which is the
            -- kind of thing that ships working and breaks for one person in
            -- French.
            ns.Print("        -> spell links in these lines: "
                .. (anyLinked and "|cff40ff40yes, ids are in the text|r"
                    or "|cffff8040none seen - names only|r"))
        end
    end

    ns.Print("  |cff888888Nothing was hooked. This only looked.|r")
end

---------------------------------------------------------------------------
-- IS THE DOOR STILL SHUT?
--
-- Its own command, because finding out is not free: the refusal pops the
-- client's own "an addon has been blocked" dialog. Nobody should trip that
-- by running a dump.
--
-- ATTRIBUTED, not guessed. A refusal raises no Lua error - pcall catches
-- nothing and the traceback loses the function name, which is how eleven
-- UNKNOWN() reports once turned out to be one event. So a watcher on
-- ADDON_ACTION_FORBIDDEN is armed FIRST, the registration is attempted
-- alone, and the verdict is whatever the watcher heard. The refusal arrives
-- synchronously, inside the RegisterEvent call, so it is already in by the
-- time the next line runs.
---------------------------------------------------------------------------
-- ASKED ONCE, THEN REMEMBERED.
--
-- The registration is refused with ADDON_ACTION_FORBIDDEN, which is the
-- answer we wanted - but the client reports it to every error handler on the
-- machine, and the owner's BugGrabber counted thirteen of them from a
-- diagnostic whose result has been known since 2026-08-16. A measurement that
-- costs an error report every time it is repeated is a measurement that
-- should be repeated on purpose.
function CombatLog:ProbeCLEU(force)
    if not force then
        ns.Print("|cffffd100combat cleu|r - |cffff4040REFUSED|r on 12.1.0, "
            .. "measured 2026-08-16: registering COMBAT_LOG_EVENT_UNFILTERED "
            .. "raises ADDON_ACTION_FORBIDDEN. No per-hit stream; the meter "
            .. "and our own sampling are the sources.")
        ns.Print("  Re-measure with |cffffd100/zs combat cleu force|r - it "
            .. "files an error report with every addon on the machine, which "
            .. "is why it is not the default.")
        return
    end

    ns.Print("|cffffd100combat cleu force|r - asking this client for the "
        .. "combat log. A blocked-action dialog here is the ANSWER, not a "
        .. "bug.")

    local heard
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    watcher:SetScript("OnEvent", function(_, _, addon, what)
        heard = tostring(addon) .. " / " .. tostring(what)
    end)

    local probe = CreateFrame("Frame")
    pcall(probe.RegisterEvent, probe, "COMBAT_LOG_EVENT_UNFILTERED")

    watcher:UnregisterAllEvents()
    watcher:SetScript("OnEvent", nil)
    pcall(probe.UnregisterAllEvents, probe)

    if heard then
        ns.Print("  |cffff4040REFUSED|r - " .. heard
            .. ". No per-hit stream on this build; the meter and our own "
            .. "sampling are the sources.")
    else
        ns.Print("  |cff40ff40It went through.|r That would be new since "
            .. "12.1.0 - worth a second run in a real fight before anything "
            .. "is built on it.")
    end
end


---------------------------------------------------------------------------
-- WHAT THE CLIENT WILL ANSWER, ASKED SAFELY
--
-- Every call into C_DamageMeter in this file goes through Read. The API is
-- new, this addon has exactly one measurement of it, and a window that
-- throws on a client answering differently is worse than one that says it
-- was told nothing.
---------------------------------------------------------------------------

-- The kinds this window offers, in the order it offers them. NAMED rather
-- than walked: the enum carries at least eight, and two of them - Deaths and
-- EnemyDamageTaken - are answers to questions the death logs already ask, so
-- a chip for either would be a second door onto a page that exists.
CombatLog.TYPES = {
    { key = "DamageDone",           label = "Damage",       tone = "out" },
    { key = "HealingDone",          label = "Healing",      tone = "heal" },
    { key = "DamageTaken",          label = "Damage taken", tone = "in" },
    { key = "AvoidableDamageTaken", label = "Avoidable",    tone = "in" },
    { key = "Interrupts",           label = "Interrupts",   tone = "out" },
    { key = "Dispels",              label = "Dispels",      tone = "heal" },
}

-- Owner, 2026-08-29: "also immer last fight". Current IS the last fight -
-- the client rolls it over when the next one starts - and Overall is the
-- evening behind it. Both are proven: the death log has been reading
-- sessions of exactly this shape for weeks.
CombatLog.WHENS = {
    { key = "Current", label = "This fight" },
    { key = "Overall", label = "Since the reset" },
}

-- AND ONE THAT IS NOT A METER KIND AT ALL.
--
-- "What you pressed" sits in the same chip row as the six the client keeps,
-- and that is deliberate: it answers the same question - what does this page
-- show about this pull - so it belongs on the same switch. A second control
-- beside it would be two things answering one question, which is the shape
-- this window already refused once when it dropped its tab strip.
CombatLog.PRESSED = "Pressed"

-- AND ONE THAT IS NOT A KIND EITHER, IN FRONT OF ALL OF THEM.
--
-- Owner, 2026-08-29, looking at a page with a single bar on it: "wo ist denn
-- meine liste mit dem schaden hin ... ich moechte sehen was mache ich an
-- schaden, was bekomme ich, heal etc. alles in einer liste ... im prinzip ist
-- das ja der deathlog, nur halt auf den kampf bezogen."
--
-- The bar list was not broken - it lists one row PER PERSON, and he was alone,
-- so it had one row and was right. What it could not do is the question he
-- actually asked, because the client's own meter cannot do it either: every
-- one of the six kinds is a separate session, so "what did I deal AND take AND
-- heal in this pull" costs six clicks and a memory. This chip answers it on
-- one page, and the six stay exactly where they were - "die sortierungen unter
-- meter behalten wir aber zusaetzlich".
CombatLog.EVERYTHING = "Everything"

-- WHICH OF THOSE THIS CLIENT ACTUALLY HAS. Walked against the enum rather
-- than assumed: the lists above are what we would LIKE to show, and a build
-- without AvoidableDamageTaken must not get a chip that answers nothing when
-- it is pressed.
local function Available(wanted, enum)
    local out = {}
    if type(enum) ~= "table" then return out end
    for _, one in ipairs(wanted) do
        if type(enum[one.key]) == "number" then
            out[#out + 1] = { key = one.key, label = one.label,
                tone = one.tone, value = enum[one.key] }
        end
    end
    return out
end

function CombatLog.Kinds()
    return Available(CombatLog.TYPES, Enum and Enum.DamageMeterType)
end

function CombatLog.Whens()
    return Available(CombatLog.WHENS, Enum and Enum.DamageMeterSessionType)
end

-- ONE READING, AND IT NEVER THROWS. Two returns: the session, or nil and a
-- sentence saying which of the four ways it came to nothing - because "the
-- client has no meter", "this build has no such session", "the call refused"
-- and "nothing has happened yet" send a reader to four different places.
function CombatLog.Read(whenKey, kindKey)
    if type(C_DamageMeter) ~= "table"
        or type(C_DamageMeter.GetCombatSessionFromType) ~= "function" then
        return nil, "This client has no damage meter to read."
    end
    local whens = Enum and Enum.DamageMeterSessionType
    local kinds = Enum and Enum.DamageMeterType
    local when = type(whens) == "table" and whens[whenKey] or nil
    local kind = type(kinds) == "table" and kinds[kindKey] or nil
    if type(when) ~= "number" or type(kind) ~= "number" then
        return nil, "This build of the game does not keep that one."
    end
    local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType,
        when, kind)
    if not ok then
        return nil, "The game refused the question."
    end
    if type(session) ~= "table" then
        return nil, "Nothing has been recorded for this yet."
    end
    return session
end

-- THE ROWS OF ONE SESSION, IN THE ORDER THE CLIENT HANDED THEM OVER.
--
-- Not sorted here, and that is the whole reason this page can exist: the
-- amounts may be secret, and sorting is comparing. The client returns its
-- own list already ranked, so the ranking is taken as given.
--
-- CanCompute BEFORE the length: taking `#` of a secret table is itself the
-- thing that raises, so the guard has to come first rather than wrap the
-- answer.
function CombatLog.Rows(session)
    local out = {}
    local list = type(session) == "table" and session.combatSources or nil
    if type(list) ~= "table" or not ns.CanCompute(list) then return out end
    for index = 1, #list do
        local row = list[index]
        if type(row) == "table" then out[#out + 1] = row end
    end
    return out
end

-- WHAT THE ENEMIES LOOK LIKE, BY NAME.
--
-- The per-ability details name the other party as a STRING and nothing else,
-- and a face needs a creature id. The client has one - on the
-- EnemyDamageTaken list, which carries both side by side. Owner's dump,
-- 2026-08-30:
--
--   EnemyDamageTaken row: name = "Heavyweight Golem",
--                         sourceCreatureID = 243206
--   the incoming ability: combatSpellDetails.unitName = "Heavyweight Golem"
--
-- The same string, so this is a lookup rather than a guess - and the id is
-- all Death.PaintFace needs, which is the same painter both death logs and
-- the replay use. Owner, 2026-08-30: "muss ja gehen, geht ja beim death log
-- auch ... es fehlt nur die mechanik." This is the mechanism.
--
-- WHAT IT CANNOT ANSWER IT LEAVES OUT: a mob that hit you and that nobody
-- hit back is not on that list, and then the row says the name with no
-- picture. A name is already the answer to "who did that to me"; a made-up
-- face would not be.
--
-- BY NAME, AND ONLY WHERE THE NAME CAN BE READ - a secret may not be a table
-- key, which is the fault that broke 1.0.0.
function CombatLog.Casters(whenKey)
    local out = {}
    local snap = CombatLog.Read(whenKey or CombatLog.when, "EnemyDamageTaken")
    for _, src in ipairs(CombatLog.Rows(snap)) do
        local name = src.name
        local creature = src.sourceCreatureID
        if ns.CanCompute(name) and type(name) == "string" and name ~= ""
            and ns.CanCompute(creature) and type(creature) == "number"
            and creature > 0 and out[name] == nil then
            out[name] = creature
        end
    end
    return out
end

-- ONE SESSION, REDUCED TO THE ONE SHAPE THIS WINDOW DRAWS.
--
-- TWO STRICTNESSES, ONE SHAPE - and the difference is not style, it is what
-- the two callers are allowed to do with the result:
--
--   LOOSE, for the page that is live. It keeps a row whose amount the client
--   withheld, because that row can still be SHOWN (SetFormattedText takes a
--   secret) and dropping it would empty the page during exactly the fight
--   somebody is watching.
--   STRICT, for the recorder. What it returns goes into a saved file and is
--   added up later, so a row whose amount cannot be read is not a row - it is
--   a bar with no length pretending to be a fact.
--
-- `total` is only filled when EVERY amount was readable. A sum with a hole in
-- it would make every percentage on the page quietly wrong, and wrong by an
-- amount nobody can see.
-- How many sources are kept per kind. A raid is forty rows and the answer is
-- in the first ten; the rest is weight in a saved-variables file.
local SOURCES_KEPT = 12
CombatLog.SOURCES_KEPT = SOURCES_KEPT

local function Field(value, kind, keepSecret)
    if ns.CanCompute(value) and type(value) == kind then return value end
    if keepSecret and value ~= nil then return value end
    return nil
end

-- SAFE TO HAND BACK TO THE CLIENT. ns.CanCompute answers false for nil, which
-- is right for a value being read and wrong for one being passed on: an absent
-- creature id is not a withheld one. File scope rather than a closure at the
-- call site - the caller runs six times a repaint, four times a second.
local function NotSecret(value)
    return value == nil or ns.CanCompute(value)
end

function CombatLog.Reduce(session, strict, cap)
    local out, total, dropped, whole = {}, 0, 0, true
    for _, src in ipairs(CombatLog.Rows(session)) do
        local amount = src.totalAmount
        local plain = ns.CanCompute(amount) and type(amount) == "number"
        if plain then
            total = total + amount
        else
            whole = false
        end
        -- WHOSE ROW THIS IS, ASKED IN FRONT OF THE CAP RATHER THAN INSIDE
        -- IT. A raid lists forty sources and this keeps twelve, and the
        -- twelve are the client's own top of the list - so in a raid your own
        -- healing row is not among them. Both halves of your own page hang
        -- off this row: the TOTAL line above the table, and the second,
        -- spell-level call that needs a source to ask about. A cap that drops
        -- it empties your half of the window on exactly the fights that have
        -- the most in them.
        local yours = RaidDeathsIsYou(src)
        if plain or not strict then
            if #out < (cap or SOURCES_KEPT) or yours then
                local kept = {
                    name = Field(src.name, "string", not strict),
                    class = Field(src.classFilename, "string", not strict),
                    -- THE SPEC'S OWN ICON, not just the class's. The client
                    -- has carried this on every row all along and nothing
                    -- here read it: two rogues on a list look identical
                    -- until one of them is Subtlety.
                    spec = Field(src.specIconID, "number", false),
                    -- AND PER SECOND, WHICH THE CLIENT COMPUTES. A total is
                    -- a night's work or half of somebody else's; per second
                    -- is the number people actually compare.
                    --
                    -- STRICTLY READABLE OR NOT AT ALL, whichever strictness
                    -- the caller asked for. It is a plain number we would
                    -- otherwise have to divide for, and RaidDeaths measured
                    -- it as a flat 0 on every DEATH row - so a zero is not
                    -- a reading, it is that row not having one.
                    rate = Field(src.amountPerSecond, "number", false),
                    -- ASSIGNED, NEVER CHAINED. This read
                    --
                    --     plain and amount or (not strict and amount or nil)
                    --
                    -- and every branch of it answers `amount` - the block is
                    -- only entered when `plain or not strict` - so the whole
                    -- expression was an elaborate way of writing the line
                    -- below. What it also did was reach the trailing `or`,
                    -- and `or` BOOLEAN-TESTS what came out of the `and`. What
                    -- came out is a meter amount the client is withholding,
                    -- and a boolean test on one of those is the forbidden
                    -- operation.
                    --
                    -- Owner, 2026-08-30, mid-fight: "auch fehlen da wieder
                    -- die schadenszahlen." This is why. Reduce raised on the
                    -- first withheld row, Meters raised under it, and
                    -- PaintReport never reached a single number - four times
                    -- a second, for the length of the pull.
                    amount = amount,
                    you = yours or nil,
                }
                -- ~~WHO THIS ROW IS, so the second call can ask for its
                -- spells.~~ REMOVED 2026-08-30, and found by a mutation that
                -- deleted both lines and stayed GREEN.
                --
                -- The second call may not be made with these at all. They are
                -- withheld for the length of a fight and the getters refuse a
                -- secret argument, so your own spells are asked for with
                -- UnitGUID("player") - see OwnSource - and nobody else's can
                -- be asked for until combat ends. Keeping them carried a
                -- withheld value into a saved pull for a reader that no
                -- longer exists.
                out[#out + 1] = kept
            else
                dropped = dropped + 1
            end
        end
    end
    if #out == 0 then return nil end
    -- THE TOTAL IS OVER EVERY ROW, not over the kept ones: a page that shows
    -- twelve of forty and works its shares out of those twelve would have
    -- them add up to a hundred while naming a third of the raid.
    return { rows = out, total = whole and total or nil, dropped = dropped }
end

-- THE LENGTH THE BARS ARE MEASURED AGAINST: the first row.
--
-- Read off the ORDER the client handed the list over in, not off a
-- comparison - which still matters, because the live page may be holding
-- secrets and comparing those is the forbidden operation. On a recorded pull
-- the numbers are plain and the answer is the same one either way.
function CombatLog.Peak(snap)
    local first = snap and snap.rows and snap.rows[1]
    if type(first) == "table" and ns.CanDisplay(first.amount) then
        return first.amount
    end
    return nil
end

-- WHAT SHARE OF THE WHOLE ONE ROW WAS.
--
-- New since the owner's screenshot of 2026-08-29: it printed "24.46M", and
-- that string can only come out of ns.ShortNumber, which is the branch that
-- runs on a READABLE number. So the amounts are not secret - at least with
-- combat over, which is when the recorder reads - and a percentage is
-- arithmetic we are allowed to do after all.
--
-- nil rather than 0 when there is nothing to divide by: "0%" is a
-- measurement, "no total" is not.
function CombatLog.Share(amount, total)
    if not (type(amount) == "number" and type(total) == "number") then
        return nil
    end
    if total <= 0 then return nil end
    return amount / total
end

---------------------------------------------------------------------------
-- SIX SESSIONS, READ AS ONE TABLE
---------------------------------------------------------------------------

-- EVERY KIND AT ONCE, from whichever of the two sources this page is on.
--
-- One function for both, because a report that reads a recorded pull one way
-- and the live fight another way is two reports that will drift. A kind the
-- client does not keep is simply absent from the result - never an empty
-- session, which would draw as "nobody did any healing".
function CombatLog.Meters(fight, whenKey)
    local out = {}
    for _, kind in ipairs(CombatLog.Kinds()) do
        local snap
        if type(fight) == "table" then
            snap = type(fight.meter) == "table" and fight.meter[kind.key] or nil
        else
            snap = CombatLog.LiveKind(whenKey or CombatLog.when, kind.key)
        end
        if snap then out[kind.key] = snap end
    end
    return out
end

-- ONE ROW PER PERSON, WITH EVERY KIND ON IT.
--
-- THE JOIN IS BY NAME, AND ONLY WHERE THE NAME CAN BE READ. Tainted code may
-- not use a secret as a table key - that is the fault that broke 1.0.0 - so a
-- source the client would not name cannot be matched against its other five
-- rows. It gets a row of its own and is counted, rather than being folded into
-- whoever it happened to stand next to.
--
-- THE ORDER IS ONE NUMBER PER ROW, ASSIGNED ONCE. Sorting by "damage, or
-- healing when there is no damage" is a comparator that switches keys, and
-- table.sort throws on those - so every row is given its rank as it is first
-- seen (damage first, because that is the kind this walk starts on) and the
-- sort reads that single number. Your own row is rank 0: this page is personal
-- before it is a raid tool, and in a raid of forty the alternative is hunting
-- for your own name.
--
-- A LATER KIND MAY ONLY ADD. Whoever was named in damage keeps that name when
-- healing withholds it, and "you" is never unlearned - the poorest reading of
-- a person must not win just because it came last.
function CombatLog.Everyone(meters, kinds)
    kinds = kinds or CombatLog.Kinds()
    local rows, byName = {}, {}
    local unnamed, dropped, rank = 0, 0, 0
    local total, peak = {}, {}

    for _, kind in ipairs(kinds) do
        local snap = type(meters) == "table" and meters[kind.key] or nil
        if snap then
            if type(snap.total) == "number" then total[kind.key] = snap.total end
            peak[kind.key] = CombatLog.Peak(snap)
            if type(snap.dropped) == "number" then
                dropped = dropped + snap.dropped
            end
            for _, entry in ipairs(snap.rows or {}) do
                local key
                if ns.CanCompute(entry.name) and type(entry.name) == "string" then
                    key = entry.name
                end
                local row = key and byName[key] or nil
                if not row then
                    rank = rank + 1
                    row = { name = entry.name, class = entry.class,
                        spec = entry.spec, rate = {},
                        you = entry.you and true or nil,
                        rank = entry.you and 0 or rank, amount = {} }
                    rows[#rows + 1] = row
                    if key then byName[key] = row else unnamed = unnamed + 1 end
                else
                    -- A LATER KIND MAY ONLY ADD, which is why every one of
                    -- these asks whether the field is still empty.
                    if row.name == nil then row.name = entry.name end
                    if row.class == nil then row.class = entry.class end
                    if row.spec == nil then row.spec = entry.spec end
                    if entry.you then row.you, row.rank = true, 0 end
                end
                -- PER SECOND IS PER KIND, the same as the amount beside it:
                -- what you healed per second is not what you dealt per
                -- second, and one field for both would be whichever kind
                -- happened to be walked last.
                if row.rate[kind.key] == nil and entry.rate ~= nil
                    and entry.rate > 0 then
                    row.rate[kind.key] = entry.rate
                end
                if row.amount[kind.key] == nil then
                    row.amount[kind.key] = entry.amount
                end
            end
        end
    end

    table.sort(rows, function(a, b) return a.rank < b.rank end)
    return { rows = rows, total = total, peak = peak,
        unnamed = unnamed, dropped = dropped }
end

-- THE SECOND CALL: ONE SOURCE'S SPELLS.
--
-- The session hands over a list of PEOPLE and nothing else; the abilities live
-- behind a second, source-scoped call that takes the row's own guid and
-- creature id back. Read off EllesmereUIDamageMeters.lua:3865-3890, which is
-- installed on this machine and reads the same API:
--
--   C_DamageMeter.GetCombatSessionSourceFromID(sessionID, meterType, guid, cid)
--   C_DamageMeter.GetCombatSessionSourceFromType(sessionType, meterType, ...)
--       -> { combatSpells = { { spellID, totalAmount, ... }, ... } }
--
-- The list comes back ALREADY SORTED by amount - their comment says so in as
-- many words - which is the same gift the session list is: an order we are
-- allowed to take even when the amounts themselves are secret.
--
-- A spell whose id cannot be read is SKIPPED and counted, not folded into the
-- next one: an id is what this table is keyed by, and a secret may not be a
-- table key.
function CombatLog.SourceSpells(whenKey, kindKey, row)
    if type(C_DamageMeter) ~= "table" or type(row) ~= "table" then return nil end
    local get = C_DamageMeter.GetCombatSessionSourceFromType
    if type(get) ~= "function" then return nil end
    if row.guid == nil and row.creature == nil then return nil end

    -- AND NEVER A SECRET ARGUMENT.
    --
    -- The getters REFUSE one from addon code. Read off
    -- EllesmereUIDamageMeters.lua:1629-1637, installed on this machine and
    -- reading the same API, which says so in as many words: "the getters
    -- refuse secret ARGUMENTS from addon code, but the local player's own
    -- GUID is a plain value -- substitute it and the call is legal."
    --
    -- Mid-combat a source row carries exactly that: sourceGUID and
    -- sourceCreatureID come back withheld. This handed them straight back,
    -- the pcall below swallowed the refusal, and the answer was "this player
    -- has no abilities" - for the whole fight, and in every pull the recorder
    -- filed while one was running. Owner, 2026-08-31, in front of a Combat
    -- log table holding nothing but what he had pressed: "eigener total dmg
    -- fehlt ... man sieht bei der totalen uebersicht keine balken."
    --
    -- Refused here rather than left to the pcall, because the two failures
    -- are different facts and only one of them is ours: see OwnSource, which
    -- is where the caller gets an id it is allowed to pass.
    if not (NotSecret(row.guid) and NotSecret(row.creature)) then return nil end

    local whens = Enum and Enum.DamageMeterSessionType
    local kinds = Enum and Enum.DamageMeterType
    local when = type(whens) == "table" and whens[whenKey] or nil
    local kind = type(kinds) == "table" and kinds[kindKey] or nil
    if type(when) ~= "number" or type(kind) ~= "number" then return nil end

    local ok, source = pcall(get, when, kind, row.guid, row.creature)
    if not ok or type(source) ~= "table" then return nil end

    local list = source.combatSpells
    if type(list) ~= "table" or not ns.CanCompute(list) then return nil end

    local out, blind = {}, 0
    for index = 1, #list do
        local spell = list[index]
        if type(spell) == "table" then
            local id = spell.spellID
            if ns.CanCompute(id) and type(id) == "number" then
                local entry = { spellID = id, amount = spell.totalAmount }
                -- AND WHO WAS AT THE OTHER END OF IT.
                --
                -- MEASURED, not inferred. Owner's dump, 2026-08-30, on an
                -- incoming ability:
                --
                --   combatSpellDetails = { amount = 349674,
                --     classification = "elite", isMob = true, isPet = false,
                --     unitClassFilename = "WARRIOR",
                --     unitName = "Heavyweight Golem" }
                --
                -- A SINGLE RECORD, not a list - the dump counted six keys
                -- and no array entries, and EllesmereUI reads it the same
                -- way (`det.unitName`, AggregateEnemyPlayers:1188).
                --
                -- WHOSE NAME IT IS DEPENDS ON THE LANE, and that is why it
                -- is kept per kind one level up: on what you TOOK it is who
                -- hit you, on what you DEALT it is who you hit. The row
                -- draws whichever lane it is about.
                local det = spell.combatSpellDetails
                if type(det) == "table" then
                    entry.who = Field(det.unitName, "string", false)
                    entry.whoClass = Field(det.unitClassFilename, "string",
                        false)
                    entry.whoRank = Field(det.classification, "string", false)
                    entry.whoMob = det.isMob == true or nil
                end
                out[#out + 1] = entry
            else
                blind = blind + 1
            end
        end
    end
    out.blind = blind
    return out
end

-- YOUR OWN ROW, out of a kind's list. The meter's own answer to "which of
-- these is the player", asked once per kind rather than guessed once here.
function CombatLog.MineIn(snap)
    for _, row in ipairs(snap and snap.rows or {}) do
        if row.you then return row end
    end
    return nil
end

-- EVERY KIND'S SPELLS, JOINED INTO ONE ROW PER ABILITY.
--
-- The same shape and the same three rules as CombatLog.Everyone one level up:
-- the rank is assigned ONCE (damage first, because that is the kind the walk
-- starts on) so the sort reads a single number and cannot throw; a later kind
-- may only ADD; and what could not be read is counted rather than dropped
-- quietly.
--
-- STRICT for the recorder, loose for the page - same division as Reduce, same
-- reason: what goes into a pull's record is added up later.
-- YOUR OWN GUID, IN ONE TABLE THAT IS REUSED.
--
-- The row the client hands over cannot be the thing we ask WITH - mid-combat
-- its ids are withheld and the getters refuse those. UnitGUID("player") is
-- plain at all times, and for your own spells it is not a fallback, it is the
-- right argument.
--
-- ONE TABLE, NOT ONE PER KIND PER REPAINT. This is reached six times a
-- repaint, four times a second, for the length of a fight; a table per call
-- is garbage nobody ever sees and it never stops.
local ownRow = { you = true }

local function OwnSource()
    if type(UnitGUID) ~= "function" then return nil end
    local guid = UnitGUID("player")
    if not (ns.CanCompute(guid) and type(guid) == "string" and guid ~= "") then
        return nil
    end
    ownRow.guid, ownRow.creature = guid, nil
    return ownRow
end

function CombatLog.MySpells(meters, whenKey, kinds, strict)
    kinds = kinds or CombatLog.Kinds()
    local rows, byID = {}, {}
    local rank, blind = 0, 0
    -- THE LARGEST OF EACH KIND, TAKEN OFF THE ORDER RATHER THAN BY COMPARING.
    -- The client hands each kind's spells over already sorted, so the first
    -- one it will show us IS the biggest - and comparing amounts is the one
    -- thing we may not do while they are being withheld. Same gift, and the
    -- same reasoning, as CombatLog.Peak takes for the list of people.
    local peak = {}

    -- ASKED WITH YOUR OWN GUID, GATED ON YOUR OWN ROW. The two are not the
    -- same fact and neither replaces the other: the row is the client saying
    -- it has you in this kind at all, the guid is the only id we are allowed
    -- to hand back. See OwnSource.
    local ask = OwnSource()
    for _, kind in ipairs(kinds) do
        local listed = ask and CombatLog.MineIn(meters and meters[kind.key])
        local spells = listed
            and CombatLog.SourceSpells(whenKey, kind.key, ask)
        if type(spells) == "table" then
            blind = blind + (spells.blind or 0)
            for _, spell in ipairs(spells) do
                local plain = ns.CanCompute(spell.amount)
                    and type(spell.amount) == "number"
                if plain or not strict then
                    local row = byID[spell.spellID]
                    if not row then
                        rank = rank + 1
                        row = { spellID = spell.spellID, rank = rank,
                            amount = {}, who = {} }
                        rows[#rows + 1] = row
                        byID[spell.spellID] = row
                    end
                    if row.amount[kind.key] == nil then
                        row.amount[kind.key] = spell.amount
                    end
                    -- PER KIND, because the name means two different things
                    -- in two of them. One small table per row per kind, and
                    -- only when the client actually named somebody.
                    if spell.who and row.who[kind.key] == nil then
                        row.who[kind.key] = { name = spell.who,
                            class = spell.whoClass, rank = spell.whoRank,
                            mob = spell.whoMob }
                    end
                    if peak[kind.key] == nil
                        and ns.CanDisplay(spell.amount) then
                        peak[kind.key] = spell.amount
                    end
                end
            end
        end
    end

    return { rows = rows, byID = byID, blind = blind, peak = peak }
end

-- AND THE PRESSES FOLDED IN, WHICH IS THE HALF THAT IS OURS.
--
-- The meter knows what every ability did; only this addon knows what you
-- PRESSED and when. A spell that did damage and was never pressed is a proc or
-- a tick; one that was pressed and did nothing is a defensive. Both belong on
-- the page, and neither is answerable from one source alone.
--
-- Press-only rows rank AFTER every ability the meter listed, in the order they
-- were pressed - one number per row again, so the sort stays a sort.
function CombatLog.SpellRows(spells, presses)
    local rows, byID = {}, {}
    local rank = 0

    for _, row in ipairs(spells and spells.rows or {}) do
        rank = math.max(rank, row.rank or 0)
        local copy = { spellID = row.spellID, rank = row.rank,
            amount = row.amount or {}, who = row.who or {} }
        rows[#rows + 1] = copy
        byID[copy.spellID] = copy
    end

    for _, press in ipairs(presses or {}) do
        local id = press.spellID
        if ns.CanCompute(id) and type(id) == "number" then
            local row = byID[id]
            if not row then
                rank = rank + 1
                row = { spellID = id, rank = rank, amount = {}, who = {} }
                rows[#rows + 1] = row
                byID[id] = row
            end
            row.times = (row.times or 0) + 1
            -- The MOST RECENT press wins, and the list arrives newest first.
            if row.last == nil and type(press.ago) == "number" then
                row.last = press.ago
            end
        end
    end

    table.sort(rows, function(a, b) return a.rank < b.rank end)
    return rows
end

-- THE KINDS, WITH THE ONE BEING SORTED BY IN FRONT.
--
-- Owner, 2026-08-30, pointing at the column heads: "mach das sortierbare
-- header draus. button oder so." Which is the right control for this table -
-- but SORTING A METER'S ROWS IS COMPARING AMOUNTS, and comparing one the
-- client is withholding is the forbidden operation. A page that sorts would
-- throw on every press of a head for the length of a fight.
--
-- So this page still compares nothing. The client keeps a SEPARATE LIST PER
-- KIND and hands each one over already in its own order - that is the same
-- gift the session list is, and the reason this window can exist at all. To
-- sort by healing, walk the healing list FIRST and let it hand out the ranks.
-- The order is the client's; the only thing we choose is which of its lists
-- to believe.
function CombatLog.SortedKinds(kinds, sortBy)
    kinds = kinds or CombatLog.Kinds()
    if sortBy == nil then return kinds end
    local out = {}
    for _, one in ipairs(kinds) do
        if one.key == sortBy then out[#out + 1] = one end
    end
    -- A KIND THIS BUILD DOES NOT KEEP leaves the order alone rather than
    -- emptying it.
    if #out == 0 then return kinds end
    for _, one in ipairs(kinds) do
        if one.key ~= sortBy then out[#out + 1] = one end
    end
    return out
end

-- AND THE ONE CASE THAT CANNOT BE ANSWERED THAT WAY.
--
-- A recorded pull carries ONE already-merged table of abilities with the
-- ranks it was given the night it was written, so there is no second list to
-- walk. Those amounts are plain by construction - the recorder keeps no row
-- it could not read - so here a comparison is allowed, and it is the only
-- place in this file where one happens.
--
-- EVERY ROW IS GIVEN ITS NUMBER BEFORE THE SORT STARTS. A comparator that
-- reaches into a table mid-sort and finds something it may not touch raises
-- halfway through, and table.sort leaves the list in pieces when it does.
function CombatLog.ReSort(rows, key)
    if key == nil or type(rows) ~= "table" then return rows end
    local weight = {}
    for _, row in ipairs(rows) do
        local amount = type(row.amount) == "table" and row.amount[key] or nil
        if ns.CanCompute(amount) and type(amount) == "number" then
            weight[row] = -amount
        else
            -- Nothing in this lane goes last, and keeps its own order there.
            weight[row] = math.huge
        end
    end
    table.sort(rows, function(a, b)
        if weight[a] ~= weight[b] then return weight[a] < weight[b] end
        return (a.rank or 0) < (b.rank or 0)
    end)
    return rows
end

-- HOW WIDE EACH NUMBER COLUMN IS, DERIVED FROM WHAT THERE IS TO SHOW.
--
-- Not written down: which kinds exist is decided by the client, and a table
-- built for six columns on a build that keeps four would have two empty lanes
-- and a name column that stops in the middle of nowhere. Returns the columns
-- AND what is left over for the name, so the painter and the header cannot
-- disagree about where a lane begins.
--
-- `right` is the distance from the ROW'S right edge to the column's right
-- edge, which is what a right-anchored font string needs.
function CombatLog.Columns(kinds, width, nameMin)
    local count = #(kinds or {})
    width = type(width) == "number" and width or 0
    nameMin = nameMin or 130
    if count == 0 then return {}, math.max(0, width) end

    local col = math.floor(math.max(0, width - nameMin) / count)
    if col > 96 then col = 96 end
    if col < 40 then col = 40 end

    local out = {}
    for index, kind in ipairs(kinds) do
        out[index] = {
            key = kind.key, label = kind.label, tone = kind.tone,
            width = col, right = (count - index) * col,
        }
    end
    return out, math.max(40, width - col * count)
end

---------------------------------------------------------------------------
-- HOW A SECRET NUMBER BECOMES A BAR, AND A WORD
---------------------------------------------------------------------------

-- IT IS ASKED RATHER THAN ASSUMED. Whether the two StatusBar setters declare
-- a secret argument is not something a desk can know, so the calls are
-- wrapped and the answer is carried back: a client that refuses gets a row
-- with its number and no fill, rather than a window thrown away over a
-- decoration.
--
-- pcall on the METHOD, not on a closure around it: a closure is a table per
-- call, and this runs once per row per repaint.
function CombatLog.Fill(bar, value, most)
    if not bar then return false end
    if not (ns.CanDisplay(value) and ns.CanDisplay(most)) then return false end
    local ok = pcall(bar.SetMinMaxValues, bar, 0, most)
    if ok then ok = pcall(bar.SetValue, bar, value) end
    return ok and true or false
end

-- And an amount. A readable one is shortened the way every other number in
-- this addon is; a secret one goes through the one setter that takes it.
function CombatLog.SayAmount(fontString, value)
    if not fontString then return false end
    if ns.CanCompute(value) and type(value) == "number" then
        fontString:SetText(ns.ShortNumber(value))
        return true
    end
    if value ~= nil and type(fontString.SetFormattedText) == "function"
        and pcall(fontString.SetFormattedText, fontString, "%s", value) then
        return true
    end
    fontString:SetText("")
    return false
end

-- HOW LONG THE FIGHT HAS BEEN, when the client will say. Used to decide how
-- far back the "what you pressed" list reaches, so the two halves of the
-- window are talking about the same stretch of time.
function CombatLog.FightLength(session)
    if type(C_DamageMeter) ~= "table"
        or type(C_DamageMeter.GetSessionDurationSeconds) ~= "function" then
        return nil
    end
    local ok, seconds = pcall(C_DamageMeter.GetSessionDurationSeconds, session)
    if ok and ns.CanCompute(seconds) and type(seconds) == "number"
        and seconds > 0 then
        return seconds
    end
    return nil
end

---------------------------------------------------------------------------
-- WHAT YOU DID, WHICH NEEDS NO METER AT ALL
--
-- Owner, 2026-08-29: "was ist mir passiert, was habe ich gemacht". The
-- second half of that has been recorded since ns.History was written - every
-- successful cast with its clock - and nothing about it is secret. It is
-- read here rather than out of a death's snapshot on purpose: the snapshot
-- is trimmed to the ten seconds before a fall at capture time, and this page
-- is about the fight rather than about the fall.
---------------------------------------------------------------------------

-- NO SILENT CAP. History keeps fifty presses and this says so when it is
-- full, because a list that stops and does not say why reads as "that is
-- everything you did".
function CombatLog.Pressed(casts, now, span, picked)
    local out = {}
    for index = #(casts or {}), 1, -1 do
        local cast = casts[index]
        local at = type(cast) == "table" and cast.at or nil
        if type(at) == "number" then
            local ago = (now or 0) - at
            if ago >= 0 and (not span or ago <= span) then
                out[#out + 1] = {
                    spellID = cast.spellID,
                    at = at,
                    ago = ago,
                    name = ns.SpellName(cast.spellID)
                        or ("Spell " .. tostring(cast.spellID)),
                    defensive = (picked and picked[cast.spellID]) and true
                        or nil,
                }
            end
        end
    end
    return out
end

-- WHAT YOU HAD AND DID NOT PRESS, in three answers rather than two.
--
-- Ready, still on its cooldown, or NOT KNOWN - and the third is not a polite
-- version of the second. An estimate says nothing at all about a spell that
-- has not been cast since login, and rounding that into "ready" would accuse
-- somebody of not pressing a button that may well have been down.
function CombatLog.Ready(now)
    local out = {}
    if not (ns.Death and ns.Death.Defensives and ns.History) then return out end
    for spellID in pairs(ns.Death.Defensives()) do
        local remaining, why = ns.History:Estimate(spellID, now)
        out[#out + 1] = {
            spellID = spellID,
            name = ns.SpellName(spellID) or ("Spell " .. tostring(spellID)),
            remaining = remaining,
            why = why,
        }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- The sentence for one of those three states. Pure, so the wording is
-- checkable and so the page and a future chat share cannot disagree.
function CombatLog.ReadyLine(entry)
    if type(entry) ~= "table" then return "" end
    if entry.remaining == 0 then return "ready" end
    if type(entry.remaining) == "number" then
        return ns.FormatTime(entry.remaining) .. " left"
    end
    return entry.why or "not known"
end

---------------------------------------------------------------------------
-- THE EVENING'S OWN PULL LIST
--
-- Owner, 2026-08-29, after seeing the first version: "wir machen das wie beim
-- deathlog, nach dungons, raids etc, dann wieder gliederung nach pulls ...
-- wenn ich dann auf einen der pulls klicke, komm ich in die details".
--
-- WHY THIS LIST IS ITS OWN AND NOT THE DEATH LOG'S. The death log's pulls are
-- built out of DEATHS - a pull nobody died on has no row there at all. That
-- is right for a death log and wrong here: a clean run is exactly the pull
-- somebody wants to look at. So this records at every combat end, whether or
-- not anybody fell, and then hands the result to the SAME tree the other two
-- windows use (ns.Death.GroupItems reads instance/whereShort/boss/kind/
-- journal off any array, so it does not care whose array it is).
--
-- WHY THE NUMBERS ARE COPIED RATHER THAN LOOKED UP LATER. The client holds
-- two sessions - the one running and the one since the reset - and nothing
-- else. There is no "give me pull 3 again", so a pull's numbers exist only
-- if they were taken while they were still the current ones. That is what
-- makes this a RECORDER and not a reader.
--
-- AND THE MOMENT IS THE RIGHT ONE. Combat ending is precisely when the
-- owner's own screenshot showed the amounts are readable, so the snapshot is
-- taken where the reading is known to work rather than where it would be
-- convenient.
---------------------------------------------------------------------------

-- How many pulls are kept. Forty rather than the tally's sixty: each of these
-- carries six lists of numbers and the other one carries names.
local KEPT = 40
CombatLog.KEPT = KEPT

-- SHORTER THAN THIS IS NOT A PULL. Walking past a critter drops you in and
-- out of combat in under a second, and a list of those is a list nobody can
-- find last night's boss in.
local MIN_FIGHT = 4
CombatLog.MIN_FIGHT = MIN_FIGHT

CombatLog.log = {}

-- EVERY KIND AT ONCE, STRICTLY - the recorder's read. Six walks over a
-- raid's worth of rows, once per pull, at the moment combat drops.
function CombatLog.Snapshot(whenKey)
    local meter, any = {}, false
    for _, kind in ipairs(CombatLog.Kinds()) do
        local snap = CombatLog.Reduce(
            CombatLog.Read(whenKey or "Current", kind.key), true)
        if snap then
            meter[kind.key] = snap
            any = true
        end
    end
    if not any then return nil end
    return meter
end

-- AND ONE KIND, LOOSELY - the live page's read. One walk rather than six,
-- because reading five lists to draw one is five walks on every tick the
-- meter updates; and loose, so a fight whose amounts the client is still
-- withholding has rows on the page instead of a blank rectangle.
function CombatLog.LiveKind(whenKey, kindKey)
    return CombatLog.Reduce(CombatLog.Read(whenKey, kindKey), false)
end

-- HOW LONG THE FIGHT HAS BEEN, ASKED OF A KIND THE CLIENT ACTUALLY KEEPS.
--
-- "What you pressed" is not one of the meter's kinds, and neither is a kind
-- this build happens not to have - so asking the meter how long ITS session
-- has been running answers nothing, and a span of nothing is a list with no
-- fight boundary. That is how presses from two fights ago end up on a page
-- headed with the word "this fight". Found by the desk guard, 2026-08-29.
function CombatLog.NowLength(whenKey)
    for _, kind in ipairs(CombatLog.Kinds()) do
        local length = CombatLog.FightLength(
            CombatLog.Read(whenKey or "Current", kind.key))
        if length then return length end
    end
    return nil
end

-- WHAT WAS PRESSED, FROM WHICHEVER OF THE TWO SOURCES APPLIES - one shape
-- out of both, so the painter never learns that there are two.
--
-- A recorded pull carries its own copy, taken when it ended; the live page
-- reads the store directly. `span` cuts the live list to the fight the meter
-- is timing, so both halves of the window talk about the same stretch.
function CombatLog.PressRows(fight, now, span)
    if type(fight) == "table" then
        return fight.casts or {}
    end
    return CombatLog.Pressed(ns.History and ns.History.casts, now, span)
end

-- WHO WENT DOWN INSIDE A STRETCH OF TIME.
--
-- Read off the death log rather than counted here: that list already knows
-- what killed somebody, has known it for weeks, and a second answer to "what
-- was the killing blow" is a second thing to get wrong. Only the LINE is
-- copied - the name, the amount and the ability - plus `at`, which is what
-- finds the whole hit-by-hit list again while this session lasts.
function CombatLog.Fell(log, now, span)
    local out = {}
    if type(now) ~= "number" then return out end
    for _, snap in ipairs(log or {}) do
        local at = type(snap) == "table" and snap.at or nil
        if type(at) == "number" then
            local ago = now - at
            if ago >= 0 and (not span or ago <= span) then
                local what, amount, spellID
                if ns.Death and ns.Death.DeathBlow then
                    what, amount, spellID = ns.Death.DeathBlow(snap)
                end
                -- THROUGH THE SAME FIELD READER THE METER ROWS USE.
                --
                -- These were written as `type(x) == "number" and x or nil`,
                -- which is the WRONG guard twice over: type() answers
                -- "number" for a withheld one, and the trailing `or` then
                -- boolean-tests it. The name was worse - `what ~= ""`
                -- compares a string that may be withheld.
                local named = Field(what, "string")
                if named == "" then named = nil end
                out[#out + 1] = {
                    at = at, ago = ago,
                    name = named,
                    amount = Field(amount, "number"),
                    spellID = Field(spellID, "number"),
                }
            end
        end
    end
    return out
end

-- The same two doors the presses have, for the same reason: a recorded pull
-- carries its own copy, a live page asks the log. ONE SHAPE out of both.
function CombatLog.FellRows(fight, now, span)
    if type(fight) == "table" then return fight.fell or {} end
    return CombatLog.Fell(ns.Death and ns.Death.log, now, span)
end

-- THE WHOLE FALL BEHIND ONE OF THOSE LINES, or nothing.
--
-- Matched on `at`, which is a GetTime stamp and therefore only meaningful
-- inside the session that wrote it - the same session this window's pull list
-- lives in, so the two die together and there is no dangling half.
function CombatLog.FullDeath(entry, log)
    local at = type(entry) == "table" and entry.at or nil
    if type(at) ~= "number" then return nil end
    for _, snap in ipairs(log or (ns.Death and ns.Death.log) or {}) do
        if type(snap) == "table" and snap.at == at then return snap end
    end
    return nil
end

---------------------------------------------------------------------------
-- THE FIGHT, IN THE SHAPE THE REPLAY WINDOW ALREADY READS
--
-- Owner, 2026-08-31: "DER REPLAY BUTTON IM COMBAT LOG: soll ein replay vom
-- Combat sein, nicht ein link zum death log. es soll nur die mechaniken und
-- ui etc von deathlog uebernehmen ... Jetzt nimmst du den replay vom
-- deathlog und baust damit ein replay fuer den combat log."
--
-- ~~The button opened the last fall~~, which is the death log's subject
-- reached through a second door. This page is about the FIGHT. So the
-- WINDOW is borrowed - the transport, the lanes, the faces, the panel down
-- the left - and the story handed to it is this page's own.
--
-- WHAT A PULL ACTUALLY KNOWS, written down because the window has to be
-- honest about the last line rather than drawing over it:
--   * how long it lasted, and every press you made in it - complete
--   * where you went down - complete
--   * your health, second by second - sampled while the fight runs, see the
--     watcher below. A pull recorded before this existed simply has none.
--   * WHAT HIT YOU, with faces and amounts - only in the ten seconds around
--     a fall. Blizzard's recap is the only door to that and the door opens
--     on a death, so between the falls there is nothing to draw. A plot
--     that filled the gap would be a picture of a quiet fight.
--
-- ONE SHAPE FOR ALL THREE PAGES. The live fight, a recorded pull and a whole
-- run summed onto one clock all arrive here as the same two lists, because
-- PressRows and FellRows already made that true for the timeline above.
function CombatLog.ReplayOf(fight, now, length, log)
    now = type(now) == "number" and now or (GetTime and GetTime() or 0)
    local presses = CombatLog.PressRows(fight, now, length)
    local fell = CombatLog.FellRows(fight, now, length)
    local worn = CombatLog.DebuffRows(fight, now, length)

    -- THE SAME SPAN THE TIMELINE ON THE PAGE IS DRAWN AGAINST, and for the
    -- same reason: they are one fight, and a replay running over a different
    -- stretch than the line above it is a second answer to one question.
    local span = CombatLog.Span(presses, fell, length, worn)
    if not (type(span) == "number" and span > 0) then return nil end

    local out = {
        -- What tells the replay window which of its two subjects this is.
        pull = true,
        span = span,
        casts = {},
        events = {},
        fell = {},
        title = CombatLog.PageTitle(fight),
        sub = CombatLog.ReportSub(fight, length),
        -- WHAT WAS ON YOU, on the fight's own clock. It belongs above the
        -- axis with the rest of what happened TO you.
        worn = {},
    }

    for _, one in ipairs(worn) do
        out.worn[#out.worn + 1] = {
            t = one.ago,
            spellID = one.spellID,
            name = ns.SpellName(one.spellID)
                or ("Spell " .. tostring(one.spellID)),
            held = one.held,
            stillOn = one.stillOn,
        }
    end

    -- THE PRESSES. A live page can ask the store itself and gets the window
    -- each press held open measured on the press; a recorded pull carries
    -- its own copy, taken at the moment combat dropped because the store is
    -- overwritten by the next pull.
    if type(fight) == "table" then
        local picked = (ns.Death and ns.Death.Defensives
            and ns.Death.Defensives()) or {}
        local majors = (ns.Death and ns.Death.Cooldowns
            and ns.Death.Cooldowns()) or {}
        for _, cast in ipairs(fight.casts or {}) do
            local id = cast.spellID
            -- THE SAME ORDER THE LIVE CLASSIFIER USES, and it has to be:
            -- a recorded pull carries ids and nothing else, so the kind is
            -- worked out again here. Defensive beats cooldown beats the
            -- rotation - the other order would put a press that is on both
            -- lists in a different lane than the death log puts it in, for
            -- the same fight.
            local defensive = picked[id] and true or nil
            out.casts[#out.casts + 1] = {
                t = cast.ago,
                spellID = id,
                name = ns.SpellName(id) or ("Spell " .. tostring(id)),
                lasted = cast.lasted,
                stillUp = cast.stillUp,
                defensive = defensive,
                cooldown = (not defensive) and majors[id] and true or nil,
            }
        end
    elseif ns.Death and ns.Death.CastsWithin then
        for _, cast in ipairs(ns.Death.CastsWithin(now, span) or {}) do
            out.casts[#out.casts + 1] = cast
        end
    end

    -- WHERE YOU WENT DOWN, and - where the recap reaches - what was hitting
    -- you at the time, moved onto the fight's clock.
    --
    -- SHALLOW COPIES. The events belong to the death log, several things
    -- read them, and shifting `t` in place would move somebody else's death
    -- to a moment it did not happen at.
    for _, one in ipairs(fell) do
        out.fell[#out.fell + 1] = {
            t = one.ago, name = one.name,
            amount = one.amount, spellID = one.spellID,
            fell = true,
        }
        local snap = CombatLog.FullDeath(one, log)
        if type(snap) == "table" and ns.Death and ns.Death.RecentEvents then
            for _, ev in ipairs(ns.Death.RecentEvents(snap.events,
                ns.Death.WINDOW)) do
                local copy = {}
                for key, value in pairs(ev) do copy[key] = value end
                copy.t = (one.ago or 0) + (ev.t or 0)
                -- The summary is cached ON the event and is about the ten
                -- seconds of ITS death, so the copy must not inherit one
                -- that was worked out for a different window.
                copy.summary = nil
                out.events[#out.events + 1] = copy
            end
            if out.maxHP == nil then out.maxHP = snap.maxHP end
        end
    end
    table.sort(out.events, function(a, b) return (a.t or 0) > (b.t or 0) end)

    -- YOUR HEALTH ACROSS THE WHOLE FIGHT, oldest first. Carried on the pull
    -- for a recorded one; asked of the ring for the fight now running.
    local track
    if type(fight) == "table" then
        track = fight.track
    elseif CombatLog.LiveTrack then
        track = CombatLog.LiveTrack(now)
    end
    if type(track) == "table" and #track > 1 then
        out.track = {}
        -- AND THE ONE READING FROM BEFORE THE PLOT BEGINS COMES WITH THEM.
        --
        -- The span is the oldest press or fall, which is usually LATER than
        -- the first health sample - the fight was running before you pressed
        -- anything. Dropping everything outside the span left the left-hand
        -- end of the line with no reading at all and the health bar blank
        -- until the first sample inside it, which reads as "the addon lost
        -- your health" and is the addon throwing away the answer.
        --
        -- Kept at its own time rather than moved to the edge: it is a
        -- measurement, and a measurement filed at a second it did not
        -- happen at is worse than no measurement.
        local carry
        local function Keep(one)
            out.track[#out.track + 1] = {
                t = one.ago, hp = one.hp, max = one.max,
            }
            if type(one.max) == "number" and one.max > (out.maxHP or 0) then
                out.maxHP = one.max
            end
        end
        for _, one in ipairs(track) do
            if type(one) == "table" and type(one.ago) == "number" then
                if one.ago > span then
                    carry = one
                else
                    if carry then
                        Keep(carry)
                        carry = nil
                    end
                    Keep(one)
                end
            end
        end
        if #out.track < 2 then out.track = nil end
    end

    -- WHAT YOU HAD PICKED, so the panel down the left says it.
    --
    -- Owner, 2026-08-31: "setup your def und consumables sollte er ja
    -- uebernehmen, die sind ja schon gesetzt." The window was offering to
    -- set up defensives that had been set for weeks - because a pull carried
    -- no list at all, and an empty list is indistinguishable from an empty
    -- SETTING once it reaches the panel.
    --
    -- A RECORDED PULL GETS THE NAMES AND NOT THE CLOCKS. Whether a defensive
    -- is ready is true of THIS moment; printing "ready" beside a pull from an
    -- hour ago is this window answering about now under a heading about then.
    -- The live page is now, so it keeps everything.
    if ns.Death and ns.Death.Availability then
        local live = type(fight) ~= "table"
        local avail = {}
        for _, entry in ipairs(ns.Death.Availability(now) or {}) do
            if live then
                avail[#avail + 1] = entry
            else
                avail[#avail + 1] = {
                    spellID = entry.spellID, itemID = entry.itemID,
                    name = entry.name,
                    -- WHICH LIST IT CAME OFF travels even when the clock
                    -- does not: it is a fact about the setting, not about
                    -- this moment, and without it every cooldown lands
                    -- under the defensives heading.
                    cooldown = entry.cooldown,
                }
            end
        end
        if #avail > 0 then out.avail = avail end
    end

    -- A FIGHT WITH NEITHER A PRESS NOR A FALL IN IT is a stretch of time and
    -- nothing else. It gets no window: an empty plot with a clock running
    -- across it says "this is what happened" and shows nothing.
    if #out.casts == 0 and #out.fell == 0 then return nil end
    return out
end

-- WHERE A RING OF SAMPLES BECOMES A LIST, oldest first, timed backwards from
-- the end of the fight.
--
-- Pure, and its own function because the wrap is the only part of a ring
-- buffer that can be wrong and it stays invisible until a fight runs past
-- the cap - which is a fifteen-minute fight, so never on a desk and rarely
-- anywhere else. `head` is the slot the NEWEST sample went into.
function CombatLog.TrackRows(ring, head, count, now, size)
    local out = {}
    if not (type(ring) == "table" and type(head) == "number"
        and type(count) == "number" and type(now) == "number"
        and type(size) == "number" and size > 0) then
        return out
    end
    local held = math.min(count, size)
    for step = 1, held do
        local index = (head - held + step - 1) % size + 1
        local one = ring[index]
        if type(one) == "table" and type(one.at) == "number" then
            out[#out + 1] = { ago = now - one.at, hp = one.hp, max = one.max }
        end
    end
    return out
end

-- AND WHAT WAS ON YOU WHILE IT LASTED, through the same two doors, for the
-- same reason: a recorded pull carries its own copy, a live page asks the
-- store. Owner, 2026-08-31: "oder wann ich debuffs oder so bekommen habe?"
function CombatLog.DebuffRows(fight, now, span)
    if type(fight) == "table" then return fight.debuffs or {} end
    if not (ns.History and ns.History.DebuffsWithin) then return {} end
    return ns.History.DebuffsWithin(now, span)
end

-- WHERE ON THE LINE EACH THING HAPPENED.
--
-- `at` is a fraction of the fight, 0 at the start and 1 at the end, so the
-- painter never has to know how long a second is in pixels. A length of
-- nothing yields no marks at all rather than a pile at zero: a line with no
-- scale is not a timeline, it is a decoration that lies.
function CombatLog.Marks(casts, fell, length, worn)
    local out = {}
    if not (type(length) == "number" and length > 0) then return out end

    local function Add(entry, kind, index)
        local ago = type(entry) == "table" and entry.ago or nil
        if type(ago) ~= "number" or ago < 0 or ago > length then return end
        out[#out + 1] = {
            at = 1 - ago / length, ago = ago, kind = kind,
            spellID = entry.spellID, name = entry.name,
            amount = entry.amount,
            -- WHICH ROW OF THE LOG THIS IS, so a click on the line can put
            -- the list under it. Owner, 2026-08-29: "ich wuerde das anklickbar
            -- machen".
            press = index,
            defensive = entry.defensive and true or nil,
            -- HOW LONG IT WAS ON YOU, for a debuff. The one number a debuff
            -- has that a press does not: a press is a moment, a debuff is a
            -- stretch, and drawing the second as the first throws away the
            -- half somebody opened the window for.
            held = kind == "debuff" and entry.held or nil,
            stillOn = kind == "debuff" and entry.stillOn or nil,
            -- THE FALL ITSELF, so the line can open the replay on it. Only a
            -- reference: the entry belongs to the pull, and copying it would
            -- make a second version of a fact that already has one.
            fell = kind == "death" and entry or nil,
        }
    end

    for index, cast in ipairs(casts or {}) do Add(cast, "cast", index) end
    for _, one in ipairs(fell or {}) do Add(one, "death") end
    for _, one in ipairs(worn or {}) do Add(one, "debuff") end

    -- Lexicographic on (position, kind), which is a total order and safe for
    -- table.sort. A fall drawn after the press that failed to prevent it is
    -- the order that reads correctly when both land in the same instant.
    -- Lexicographic on (position, rank, id), which is a TOTAL order and
    -- therefore safe for table.sort. A fall drawn after the press that
    -- failed to prevent it reads correctly when both land in one instant;
    -- a debuff sits between them, because it is the thing the press was
    -- answering. The id at the end is what makes it total rather than
    -- merely mostly-ordered - two debuffs landing together would otherwise
    -- be a comparator that says neither comes first.
    local function rank(one)
        if one.kind == "death" then return 2 end
        if one.kind == "debuff" then return 1 end
        return 0
    end
    table.sort(out, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        if rank(a) ~= rank(b) then return rank(a) < rank(b) end
        return (a.spellID or 0) < (b.spellID or 0)
    end)
    return out
end

-- HOW LONG A STRETCH THE LINE ACTUALLY COVERS.
--
-- Not the fight: the fight can be a fourteen-minute session the client has
-- not rolled over, while the presses reach back only as far as this addon's
-- own store. Drawn against the fight, every mark then piles into the last
-- half a percent of the line - which is what the owner's screenshot showed.
--
-- So the line is scaled to the OLDEST thing on it, capped at the fight, and
-- the heading says when the two differ. One rule, two correct readings: on a
-- recorded pull the oldest press IS the pull.
function CombatLog.Span(presses, fell, length, worn)
    local oldest = 0
    for _, list in ipairs({ presses or {}, fell or {}, worn or {} }) do
        for _, one in ipairs(list) do
            local ago = type(one) == "table" and one.ago or nil
            if type(ago) == "number" and ago > oldest then oldest = ago end
        end
    end
    if type(length) == "number" and length > 0 then
        if oldest > 0 and oldest < length then return oldest end
        return length
    end
    return oldest > 0 and oldest or nil
end

-- The sub-line of the report, pure so the wording is checkable.
function CombatLog.ReportSub(fight, length)
    if type(fight) == "table" then return CombatLog.PageSub(fight) end
    if type(length) == "number" then
        return string.format("everything at once  -  %s so far",
            ns.FormatTime(length))
    end
    return "everything at once, as the game fills it in"
end

-- WHERE THIS PULL WAS. The same seven answers the death log files a fall
-- under, so the two windows cannot disagree about which dungeon you were in.
function CombatLog.Whereabouts()
    if not (ns.Death and ns.Death.Where) then return {} end
    local place, short, instance, journal, boss, kind, bossID = ns.Death.Where()
    return {
        where = place, whereShort = short, instance = instance,
        journal = journal, boss = boss, kind = kind, bossID = bossID,
    }
end

-- APPENDED, OR REPLACED IF IT IS THE SAME PULL. The second reading a second
-- after combat drops is the same fight with a final tally on it, not a new
-- one - see the watcher below for why there are two.
function CombatLog.Note(log, fight, cap)
    if not (type(log) == "table" and type(fight) == "table" and fight.key) then
        return log
    end
    for index = #log, 1, -1 do
        if log[index].key == fight.key then
            log[index] = fight
            return log
        end
    end
    log[#log + 1] = fight
    while #log > (cap or KEPT) do table.remove(log, 1) end
    return log
end

---------------------------------------------------------------------------
-- THE WATCHER
--
-- TWO READINGS PER PULL, one second apart. The first is taken the moment
-- combat drops, which is the only moment the fight is certainly still the
-- CURRENT session; the second catches a tally the client finished writing
-- after that, and replaces the first because it is the same pull. One
-- reading would be a guess about which of the two the client does.
---------------------------------------------------------------------------
do
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")

    local startedAt

    -----------------------------------------------------------------------
    -- YOUR HEALTH, ONCE A SECOND, FOR AS LONG AS THE FIGHT LASTS
    --
    -- The fight's own shape IS the health line, and until this existed
    -- nothing in the addon knew it except in the ten seconds Blizzard's
    -- recap covers around a death. A replay of a pull without it is a row
    -- of icons over an empty plot.
    --
    -- NO METER READ AT ALL. UnitHealth is plain at all times, so this is two
    -- numbers a second - not a walk over the sessions, and nothing that can
    -- come back secret and poison the arithmetic around it.
    --
    -- A RING, AND THE TABLES IN IT ARE REUSED. A fight left running for a
    -- quarter of an hour would otherwise be nine hundred little tables for
    -- the collector to walk, and a raid night is mostly resting state.
    -----------------------------------------------------------------------
    local TRACK_SIZE = 900
    local ring, ringHead, ringCount = {}, 0, 0
    local ticker

    -- EXPORTED, because otherwise nothing outside can call it and the LIVE
    -- half of the health line is a loop nobody runs. The recorder's half was
    -- covered by firing the two combat events; this half is driven by a
    -- ticker, and a ticker on a desk never fires - so "the health bar is
    -- always empty" was a question the checks could not be asked.
    local function Sample()
        if not (UnitHealth and UnitHealthMax and GetTime) then return end
        local hp, most = UnitHealth("player"), UnitHealthMax("player")
        if not (ns.CanCompute(hp) and ns.CanCompute(most)) then return end
        if not (type(hp) == "number" and type(most) == "number"
            and most > 0) then
            return
        end
        ringHead = ringHead % TRACK_SIZE + 1
        local slot = ring[ringHead]
        if not slot then
            slot = {}
            ring[ringHead] = slot
        end
        slot.at, slot.hp, slot.max = GetTime(), hp, most
        if ringCount < TRACK_SIZE then ringCount = ringCount + 1 end
    end

    CombatLog.SampleHealth = Sample

    local function TrackAt(now)
        return CombatLog.TrackRows(ring, ringHead, ringCount, now, TRACK_SIZE)
    end

    -- THE FIGHT NOW RUNNING has no pull to carry its samples yet, and the
    -- live page's replay is about exactly that fight.
    function CombatLog.LiveTrack(now)
        return TrackAt(type(now) == "number" and now
            or (GetTime and GetTime() or 0))
    end

    -- Named at file scope rather than written as a closure at the call site:
    -- this is handed to C_Timer on every pull, and a closure per pull is
    -- garbage nobody sees.
    local function Finish(key)
        local fight
        for _, one in ipairs(CombatLog.log) do
            if one.key == key then fight = one break end
        end
        if not fight then return end
        local meter = CombatLog.Snapshot("Current")
        if meter then fight.meter = meter end
        -- A PULL JUST CHANGED UNDER A SUMMED PAGE. Neither the log's length
        -- nor its keys moved, so this is the one edit CombatLog.Combined
        -- cannot see for itself.
        CombatLog.revision = (CombatLog.revision or 0) + 1
        if CombatLog.Window() and CombatLog.Window():IsShown() then
            CombatLog:Refresh()
        end
    end

    watcher:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            startedAt = GetTime and GetTime() or nil
            -- FROM EMPTY, and with the opening reading taken at once: a pull
            -- that lasts eight seconds would otherwise start its line at the
            -- first tick and lose the health you went in on.
            ringHead, ringCount = 0, 0
            Sample()
            if ticker then ticker:Cancel() end
            if C_Timer and C_Timer.NewTicker then
                ticker = C_Timer.NewTicker(1, Sample)
            end
            return
        end

        -- THE LAST READING FIRST, then the ticker off. The second the fight
        -- ends is the one the plot ends on, and a ticker cancelled before it
        -- is taken leaves the line stopping wherever the last whole second
        -- happened to fall.
        Sample()
        if ticker then
            ticker:Cancel()
            ticker = nil
        end

        local now = GetTime and GetTime() or nil
        local lasted
        if startedAt and now then lasted = now - startedAt end
        startedAt = nil
        if not lasted or lasted < MIN_FIGHT then return end

        local meter = CombatLog.Snapshot("Current")
        -- A pull the meter said nothing about is still a pull - it happened,
        -- it has a place and a clock, and a list that silently drops it would
        -- have a hole in the evening exactly where the client was quiet.
        CombatLog.nextKey = (CombatLog.nextKey or 0) + 1
        local fight = CombatLog.Whereabouts()
        fight.key = CombatLog.nextKey
        fight.stamp = now
        fight.duration = lasted
        fight.meter = meter
        local clock = date and date("%H:%M")
        if type(clock) == "string" then fight.when = clock end

        -- AND WHAT YOU PRESSED WHILE IT LASTED. Owner, 2026-08-29, about the
        -- pull's own page: "ich sehe dann was ich gemacht habe". History is a
        -- live store of the last fifty presses and it is overwritten by the
        -- next pull, so this is the only moment the answer exists. Only the
        -- id and how long before the end - the name and the icon are looked
        -- up again when it is drawn, and neither belongs in a saved file.
        local casts = {}
        for _, cast in ipairs(CombatLog.Pressed(
            ns.History and ns.History.casts, now, lasted)) do
            local kept = { spellID = cast.spellID, ago = cast.ago }
            -- AND HOW LONG IT WAS ACTUALLY UP, measured on this very press
            -- rather than looked up in a table. Same door the death snapshot
            -- reads (Death.CastsWithin), and taken here for the same reason
            -- everything else on this line is: History is overwritten by the
            -- next pull. Without it every defensive in a recorded pull's
            -- replay draws as a marker instead of a bar.
            if ns.History and ns.History.ActiveWindow
                and type(cast.at) == "number" then
                local from, to = ns.History:ActiveWindow(cast.spellID, cast.at)
                if from then
                    local endsAt = to and math.max(0, now - to) or 0
                    local held = cast.ago - endsAt
                    if held > 0 then
                        kept.lasted = held
                        kept.stillUp = (to == nil) or nil
                    end
                end
            end
            casts[#casts + 1] = kept
        end
        if #casts > 0 then fight.casts = casts end

        -- AND THE FIGHT'S OWN SHAPE. One reading is a dot, not a line.
        local track = TrackAt(now)
        if #track > 1 then fight.track = track end

        -- AND WHAT WAS ON YOU WHILE IT LASTED. Same reason as the presses:
        -- the store is a rolling one and the next pull overwrites it, so
        -- this is the only moment the answer exists. The ones still on you
        -- when it ended are in it and say so.
        local worn = ns.History and ns.History.DebuffsWithin
            and ns.History.DebuffsWithin(now, lasted) or {}
        if #worn > 0 then fight.debuffs = worn end

        -- AND WHO WENT DOWN WHILE IT LASTED, for the same reason and off the
        -- same clock. The death log has its own cap and its own life, so a
        -- pull that merely pointed into it would go blank the day that list
        -- rolls over; the line is copied and the stamp is kept, so the whole
        -- hit-by-hit list is still reachable while the session lasts.
        local fell = CombatLog.Fell(ns.Death and ns.Death.log, now, lasted)
        if #fell > 0 then fight.fell = fell end

        -- AND WHAT EACH ABILITY DID. Taken here for the same reason the
        -- amounts are: the guid this is asked with only means something inside
        -- the running session, so a pull that stored the guid and asked later
        -- would be asking about somebody else's fight.
        local spells = CombatLog.MySpells(meter, "Current", nil, true)
        if #spells.rows > 0 then fight.spells = spells end

        -- AND WHAT THE ENEMIES OF THAT PULL LOOKED LIKE. Taken here for the
        -- same reason as everything else on this line: the list belongs to
        -- the running session, and a pull that asked later would be asking
        -- about somebody else's fight.
        local faces = CombatLog.Casters("Current")
        if next(faces) ~= nil then fight.casters = faces end

        CombatLog.Note(CombatLog.log, fight)
        CombatLog.revision = (CombatLog.revision or 0) + 1

        if C_Timer and C_Timer.After then
            C_Timer.After(1, function() Finish(fight.key) end)
        end
        if CombatLog.Window() and CombatLog.Window():IsShown() then
            CombatLog:Refresh()
        end
    end)
end


---------------------------------------------------------------------------
-- THE WINDOW
--
-- Owner, 2026-08-29, after the first version: "wir machen das wie beim
-- deathlog, nach dungons, raids etc, dann wieder gliederung nach pulls ...
-- wenn ich dann auf einen der pulls klicke, komm ich in die details".
--
-- SO THE COLUMN IS THE SWITCH, AND THERE ARE NO TABS. "Right now" is the top
-- row of the column, exactly as "Tonight" is in the group death log. The
-- alternative - a tab strip above a column - would be two controls answering
-- one question, and this addon has already had to pull two of those apart
-- once. One selection, one place, and the two cannot contradict each other.
--
-- BUILT ONCE AND REPAINTED. The client pushes: three DAMAGE_METER_* events
-- repaint the page, and only while the window is open.
---------------------------------------------------------------------------
-- Owner, 2026-08-29, on putting all six lanes onto every row: "ggf muessen
-- wir das fenster breiter machen, aber das wuerde viel mehr sinn machen." One
-- number, because CombatLog.Columns works the lane widths out of whatever
-- space it is given rather than having them written down.
local WIDTH, HEIGHT = 1180, 700
-- THE SAME COLUMN WIDTH AS BOTH DEATH LOGS, out of the same one number. Three
-- windows with three nearly-equal columns is three chances to be wrong about
-- which of them is right.
local SIDE_W = ns.Death.SIDE_W

local BAR_H, BAR_GAP = 24, 3
local BAR_PIC = 16
-- THE REPORT'S OWN MEASUREMENTS, and they are up here with the others for a
-- reason this file has already paid for twice: a constant written below the
-- function that uses it is arithmetic on nil at load, and the window never
-- opens once.
local HEAD_H = 16          -- a section heading
local PERSON_H = 22        -- one name with all its numbers
local PERSON_GAP = 2
local BLOCK_GAP = 16       -- air between two sections
local TIME_H = 54          -- the whole timeline band
local MARK_W = 3           -- one press on the line, when they are packed
local MARK_PIC = 16        -- one press as its own icon, when they fit
local DEATH_W = 5          -- one fall, which is rarer
-- How many of each the report draws before it says how many it left out. The
-- point of this page is the shape of a pull at a glance; the chips behind it
-- have every row.
local MARKS_SHOWN = 400
-- Owner, 2026-08-29: "wir sollten die liste auch scrollen koennen, von fight
-- start zum ende." The page has always scrolled; what it had to show was ten
-- rows out of a store that only reached six seconds back. Both ends are
-- raised - see CASTS_CAP in History.lua - and what still does not fit is
-- named rather than cut off in silence.
local LOG_SHOWN = 300

-- HOW WIDE THE CLOCK DOWN THE LEFT EDGE OF A HISTORY ROW IS. Wide enough for
-- "10:23" so a long pull does not push the names apart halfway down it.
local STAMP_W = 42
local FELL_SHOWN = 8
CombatLog.LOG_SHOWN = LOG_SHOWN

-- DOWN HERE WITH THE MEASUREMENTS IT USES, and not one line higher.
-- MARK_W is declared in the block above; the first cut of this function
-- sat in the pure-logic section two hundred lines earlier and did
-- arithmetic on a nil. Third time in this file - a constant written
-- below its user is arithmetic on nil at load, and the window never
-- opens once.
-- WHERE EACH MARK SITS ON THE LINE, AND WHETHER IT CAN BE AN ICON.
--
-- Owner, 2026-08-29: "oben beim zeitstrahl, fehlen die spell icons und hover
-- infos." An icon is sixteen pixels and a rotation is dense, so this is not a
-- decision that can be made once and written down - it depends on how many
-- marks there are and how wide the window is.
--
-- Two rules, and they belong together because the second only makes sense
-- under the first:
--   * ICONS ONLY IF THEY ALL FIT side by side. Otherwise they overlap, and
--     overlapping icons are worse than ticks: they hide each other and lie
--     about how many there were.
--   * WHEN THEY FIT, EACH ONE IS NUDGED right until it clears its neighbour.
--     A press half a second after another would otherwise draw on top of it.
--     Ticks are NOT nudged - they are meant to be dense, and moving them
--     would move the one thing they are: a position in time.
function CombatLog.Lay(marks, width, iconW)
    marks = marks or {}
    width = type(width) == "number" and width or 0
    iconW = iconW or 16

    local count = #marks
    local icons = count > 0 and (count * (iconW + 1)) <= width
    local xs, last = {}, nil

    for index, mark in ipairs(marks) do
        local w = icons and iconW or MARK_W
        local want = math.floor((mark.at or 0) * math.max(0, width - w))
        if icons then
            if last and want < last + w + 1 then want = last + w + 1 end
            if want > width - w then want = math.max(0, width - w) end
            last = want
        end
        xs[index] = want
    end
    return xs, icons
end

CombatLog.FELL_SHOWN = FELL_SHOWN

-- THE COLUMN'S NUMBERS, in one table, so the fit arithmetic can be checked on
-- a desk with no screen. Same three row heights the other two columns use -
-- they are the same three kinds of row.
CombatLog.LAYOUT = {
    width = WIDTH, height = HEIGHT, sideW = SIDE_W,
    runH = 46, bossH = 30, pullH = 40, now = 44,
    gap = 2, top = 14, bottom = 46, title = 16, titleGap = 8,
}

-- HOW TALL ONE ITEM OF THE COLUMN IS. Handed to the fit arithmetic rather
-- than written into it, so there is one answer and the painter and the sum
-- cannot disagree.
function CombatLog.RowHeight(item)
    local L = CombatLog.LAYOUT
    local kind = type(item) == "table" and item.kind or nil
    if kind == "run" then return L.runH end
    if kind == "boss" then return L.bossH end
    return L.pullH
end

function CombatLog.Room()
    local L = CombatLog.LAYOUT
    local headerH = (ns.UI and ns.UI.HEADER_H) or 0
    return L.height - headerH - L.top - L.bottom
        - L.title - L.titleGap - L.now - L.gap
end

local frame
local icon

-- WHERE THE PAGE IS POINTED. Kept on the module and not in the profile: it is
-- a reading gesture, not a setting, and a window that came back after a
-- reload on "Dispels" would look broken to whoever left it on damage.
--
-- `showing` is the pull's own KEY, never its position. The oldest drops off
-- at forty and every position under it moves; the key outlives that.
CombatLog.when = "Current"
CombatLog.kind = CombatLog.EVERYTHING
-- WHICH COLUMN THE TABLES ARE ORDERED BY. nil is the first one, which is the
-- order the client hands its lists over in - so "unsorted" is not a state
-- this page can be in.
CombatLog.sortBy = nil
CombatLog.showing = nil
CombatLog.collapsed = {}
CombatLog.sideOffset = 0

-- WHICH PULL IS BEING READ, or nil for the live page. A key that is no longer
-- in the log answers nil rather than the neighbour - a pull that fell off the
-- end must not silently hand the page to whoever took its place.
function CombatLog.Pick(log, key)
    if key == nil then return nil end
    for _, fight in ipairs(log or {}) do
        if fight.key == key then return fight end
    end
    return nil
end

---------------------------------------------------------------------------
-- A WHOLE RUN, OR A WHOLE BOSS, AS ONE PULL
--
-- Owner, 2026-08-31, pointing at "Den of Nalorakk - 16 pulls" in the column:
-- "man muss eigentlich, wenn ich die instanz, wie den of nalorak anklicke,
-- den totalen schaden der instanz sehen, nicht nur per pull."
--
-- NOTHING NEW IS PAINTED FOR IT. The report already takes one pull table and
-- draws it top to bottom, so a run is a pull table that several pulls were
-- added into - one painter, one shape, and a total that cannot disagree with
-- the rows it was summed out of. The whole feature is arithmetic.
--
-- AND THE ARITHMETIC IS LEGAL HERE AND NOWHERE ELSE ON THIS PAGE. A recorded
-- pull is written by the STRICT half of Reduce, so every amount in it was
-- readable at the moment it was filed; the live session is the one holding
-- secrets and it is not in this list. Every field is still checked, because a
-- table that came back out of a saved file is not one to assume the shape of.
--
-- WHAT IS DELIBERATELY NOT SUMMED IS PER SECOND. The client works that out
-- for its own session and knows how long the session ran; adding two of them
-- answers a question nobody asked, and dividing the total by a run's wall
-- clock would call forty minutes of walking part of the fight.
---------------------------------------------------------------------------

-- The item in the outline with this id, whatever is folded. Read with no
-- collapse map on purpose: a group that is being READ must not stop existing
-- because its parent was folded shut.
function CombatLog.Group(log, id)
    if type(id) ~= "string" or not (ns.Death and ns.Death.GroupItems) then
        return nil
    end
    for _, item in ipairs(ns.Death.GroupItems(log, nil, "pull") or {}) do
        if item.id == id and type(item.indices) == "table" then return item end
    end
    return nil
end

-- YOUR OWN DAMAGE ACROSS ONE OF THEM, for its row in the column. The same
-- sentence CombatLog.PullSummary writes for a single pull, and the same
-- reason it is your own number first: this window is personal before it is a
-- raid tool.
function CombatLog.GroupSummary(log, indices)
    local total, any = 0, false
    for _, at in ipairs(indices or {}) do
        local one = type(log) == "table" and log[at] or nil
        local snap = type(one) == "table" and type(one.meter) == "table"
            and one.meter.DamageDone or nil
        for _, row in ipairs(snap and snap.rows or {}) do
            if row.you and type(row.amount) == "number" then
                total = total + row.amount
                any = true
            end
        end
    end
    if not any then return nil end
    return ns.ShortNumber(total) .. " done"
end

function CombatLog.Combine(log, id)
    local item = CombatLog.Group(log, id)
    if not item then return nil end

    local fights = {}
    for _, at in ipairs(item.indices) do
        local one = type(log) == "table" and log[at] or nil
        if type(one) == "table" then fights[#fights + 1] = one end
    end
    if #fights == 0 then return nil end

    -----------------------------------------------------------------------
    -- THE PEOPLE, one row per name per kind.
    -----------------------------------------------------------------------
    local meter = {}
    for _, kind in ipairs(CombatLog.Kinds()) do
        local rows, byName = {}, {}
        local total, whole, dropped, any = 0, true, 0, false
        for _, one in ipairs(fights) do
            local snap = type(one.meter) == "table" and one.meter[kind.key]
                or nil
            if type(snap) == "table" then
                any = true
                if type(snap.total) == "number" then
                    total = total + snap.total
                else
                    -- A SUM WITH A HOLE IN IT would make every share on the
                    -- page quietly wrong, and wrong by an amount nobody can
                    -- see. Same rule as Reduce, one level up.
                    whole = false
                end
                if type(snap.dropped) == "number" then
                    dropped = dropped + snap.dropped
                end
                for _, src in ipairs(snap.rows or {}) do
                    local key
                    if ns.CanCompute(src.name)
                        and type(src.name) == "string" then
                        key = src.name
                    end
                    local into = key and byName[key] or nil
                    if not into then
                        into = { name = src.name, class = src.class,
                            spec = src.spec, you = src.you, amount = 0 }
                        rows[#rows + 1] = into
                        if key then byName[key] = into end
                    else
                        -- A LATER PULL MAY ONLY ADD, and "you" is never
                        -- unlearned: the poorest reading of a person must
                        -- not win just because it came last.
                        if into.class == nil then into.class = src.class end
                        if into.spec == nil then into.spec = src.spec end
                        if src.you then into.you = true end
                    end
                    if type(src.amount) == "number" then
                        into.amount = into.amount + src.amount
                    end
                end
            end
        end
        if any and #rows > 0 then
            -- SORTED HERE, WHICH THE LIVE PAGE MAY NOT DO. Every one of
            -- these is a plain number - it had to be, to be filed at all -
            -- so the order is ours to work out rather than the client's to
            -- lend us. One key, so the comparator stays a comparator.
            table.sort(rows, function(a, b) return a.amount > b.amount end)
            meter[kind.key] = { rows = rows, total = whole and total or nil,
                dropped = dropped }
        end
    end

    -----------------------------------------------------------------------
    -- YOUR ABILITIES, one row per spell across every pull.
    -----------------------------------------------------------------------
    local rows, byID, blind = {}, {}, 0
    for _, one in ipairs(fights) do
        local spells = type(one.spells) == "table" and one.spells or nil
        if spells then
            if type(spells.blind) == "number" then
                blind = blind + spells.blind
            end
            for _, src in ipairs(spells.rows or {}) do
                local spellID = src.spellID
                if ns.CanCompute(spellID) and type(spellID) == "number" then
                    local into = byID[spellID]
                    if not into then
                        into = { spellID = spellID, amount = {} }
                        rows[#rows + 1] = into
                        byID[spellID] = into
                    end
                    for key, value in pairs(src.amount or {}) do
                        if type(value) == "number" then
                            into.amount[key] = (into.amount[key] or 0) + value
                        end
                    end
                end
            end
        end
    end
    local lead = CombatLog.Kinds()[1] and CombatLog.Kinds()[1].key or nil
    table.sort(rows, function(a, b)
        local one = lead and a.amount[lead] or nil
        local two = lead and b.amount[lead] or nil
        if one == two then return (a.spellID or 0) < (b.spellID or 0) end
        -- Nothing in the leading lane goes last and stays there. -1 rather
        -- than a truth test, so a genuine zero still outranks an absence.
        return (one or -1) > (two or -1)
    end)
    local peak = {}
    for index, one in ipairs(rows) do
        one.rank = index
        for key, value in pairs(one.amount) do
            if peak[key] == nil or value > peak[key] then peak[key] = value end
        end
    end

    -----------------------------------------------------------------------
    -- AND THE SEQUENCE, ON ONE CLOCK.
    --
    -- Every pull times its presses backwards from ITS OWN end, so laying two
    -- of them end to end would draw the second dungeon minute on top of the
    -- twentieth. Each one is shifted by how long ago that pull ended, which
    -- puts the whole run on one line - gaps and all, because the gaps are
    -- true and a line that closed them would be a line that lies about when.
    -----------------------------------------------------------------------
    local endAt, startAt
    for _, one in ipairs(fights) do
        local stamp = type(one.stamp) == "number" and one.stamp or nil
        if stamp then
            local began = stamp - (type(one.duration) == "number"
                and one.duration or 0)
            if endAt == nil or stamp > endAt then endAt = stamp end
            if startAt == nil or began < startAt then startAt = began end
        end
    end

    local casts, fell = {}, {}
    if endAt then
        for _, one in ipairs(fights) do
            local stamp = type(one.stamp) == "number" and one.stamp or nil
            if stamp then
                local shift = endAt - stamp
                -- THE TRACK RIDES WITH THEM. It was written with `ago`
                -- rather than `t` for exactly this: three lists timed
                -- backwards from their own pull's end, one shift, one loop.
                -- A fourth reader of the same rule is a fourth place to get
                -- the arithmetic wrong.
                for _, list in ipairs({ "casts", "fell", "track",
                    "debuffs" }) do
                    for _, src in ipairs(one[list] or {}) do
                        if type(src) == "table"
                            and type(src.ago) == "number" then
                            local copy = {}
                            for key, value in pairs(src) do
                                copy[key] = value
                            end
                            copy.ago = src.ago + shift
                            local out = list == "casts" and casts or fell
                            out[#out + 1] = copy
                        end
                    end
                end
            end
        end
    end
    -- NEWEST FIRST, which is the order the live store hands its presses over
    -- in and therefore the order everything downstream was written against.
    table.sort(casts, function(a, b) return a.ago < b.ago end)

    local duration
    if endAt and startAt and endAt > startAt then duration = endAt - startAt end

    -- AND HOW MUCH OF THAT WAS A FIGHT. Two different numbers and both are
    -- wanted: the span is what the timeline is drawn against, this is what
    -- the sub-line says out loud. See CombatLog.PageSub.
    local fighting = 0
    for _, one in ipairs(fights) do
        if type(one.duration) == "number" then
            fighting = fighting + one.duration
        end
    end

    -- EVERY PULL'S ENEMIES, IN ONE MAP. First writer wins, the same rule
    -- the rest of this function uses: a later pull may only ADD.
    local casters = {}
    for _, one in ipairs(fights) do
        if type(one.casters) == "table" then
            for name, creature in pairs(one.casters) do
                if casters[name] == nil then casters[name] = creature end
            end
        end
    end

    local first, last = fights[1], fights[#fights]
    local when
    if type(first.when) == "string" and type(last.when) == "string" then
        if first.when == last.when then
            when = first.when
        else
            when = first.when .. " - " .. last.when
        end
    end

    return {
        key = id,
        pulls = #fights,
        instance = first.instance,
        kind = first.kind,
        boss = item.kind == "boss" and item.bossName or nil,
        bossID = item.bossID,
        journal = item.journal,
        when = when,
        duration = duration,
        fighting = fighting > 0 and fighting or nil,
        stamp = endAt,
        meter = meter,
        spells = { rows = rows, byID = byID, blind = blind, peak = peak },
        casts = casts,
        fell = fell,
        casters = casters,
    }
end

-- BUILT ONCE PER CHANGE, NOT ONCE PER REPAINT.
--
-- Summing sixteen pulls copies every press in all of them, and this page
-- repaints four times a second for the length of a fight. Garbage nobody ever
-- sees does not stop being garbage; the owner's rule about the resting state
-- applies to a window left open on a dungeon just as much as to a bar.
--
-- The mark carries the log's LENGTH and a revision the two writers bump, so
-- a pull that was filed and a pull that was re-read a second later both
-- invalidate it. Nothing else can change a recorded pull.
local combined = {}

function CombatLog.Combined(log, id)
    local mark = tostring(id) .. "#" .. #(type(log) == "table" and log or {})
        .. "#" .. tostring(CombatLog.revision or 0)
    if combined.mark ~= mark then
        combined.mark, combined.fight = mark, CombatLog.Combine(log, id)
    end
    return combined.fight
end


-- THE PAGE'S TITLE AND SUB-LINE, pure, for both of the things it can show.
-- Written here rather than in the painter so the wording is checkable and so
-- the window and a later share cannot drift apart.
function CombatLog.PageTitle(fight)
    if not fight then return "Right now" end
    local name = fight.boss or fight.whereShort or fight.instance or "Trash"
    return name
end

function CombatLog.PageSub(fight, live)
    if not fight then
        return live or "what the game's own meter is holding, this moment"
    end
    local bits = {}
    if fight.instance then bits[#bits + 1] = fight.instance end
    if fight.kind and fight.kind ~= fight.instance then
        bits[#bits + 1] = fight.kind
    end
    -- HOW MANY PULLS, when this is a whole run rather than one of them.
    if type(fight.pulls) == "number" and fight.pulls > 1 then
        bits[#bits + 1] = string.format("%d pulls", fight.pulls)
    end
    if fight.when then bits[#bits + 1] = fight.when end
    -- THE TIME IN COMBAT, NOT THE WALL CLOCK.
    --
    -- A run's own length has the walking between its pulls in it, and this
    -- line would be calling half an hour of that "the fight". `duration`
    -- stays the wall clock because the timeline is drawn against it: the
    -- gaps are real, and a line that closed them would lie about when.
    if type(fight.fighting) == "number" then
        bits[#bits + 1] = ns.FormatTime(fight.fighting) .. " in combat"
    elseif type(fight.duration) == "number" then
        bits[#bits + 1] = ns.FormatTime(fight.duration)
    end
    return table.concat(bits, "  -  ")
end

-- WHAT ONE PULL IS WORTH AT A GLANCE, for its row in the column. Your own
-- damage first, because this window is personal before it is a raid tool;
-- the pull's whole total when the client never named you; and the plain fact
-- that nothing was kept, when nothing was.
function CombatLog.PullSummary(fight)
    if type(fight) ~= "table" then return "" end
    local snap = fight.meter and fight.meter.DamageDone
    if not snap then return "no numbers kept" end
    for _, row in ipairs(snap.rows or {}) do
        if row.you and type(row.amount) == "number" then
            return ns.ShortNumber(row.amount) .. " done"
        end
    end
    if type(snap.total) == "number" then
        return ns.ShortNumber(snap.total) .. " in total"
    end
    return ""
end

---------------------------------------------------------------------------
-- ONE BAR
--
-- THE TEXT LIVES ON THE BAR, NOT ON THE ROW. A child frame draws above every
-- layer of its parent, so a name written on the row would end up underneath
-- the fill that is supposed to sit behind it - and the symptom is that the
-- label disappears exactly when the bar gets long enough to matter.
---------------------------------------------------------------------------
local function BuildBar(parent, width)
    local UI, C = ns.UI, ns.UI.C
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, BAR_H)

    -- The empty track, so a short bar still reads as a row rather than as a
    -- name floating in the dark.
    row.track = row:CreateTexture(nil, "BACKGROUND")
    row.track:SetAllPoints(row)
    row.track:SetColorTexture(C.control[1], C.control[2], C.control[3], 0.55)

    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetAllPoints(row)
    row.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    row.bar:SetMinMaxValues(0, 1)
    row.bar:SetValue(0)


    -- AND THE TEXT ON A FRAME OF ITS OWN, ABOVE BOTH.
    --
    -- Not on the row - it would end up under the fill, which is the trap this
    -- addon already has a name for. And NOT ON THE BAR either, which is the
    -- mistake this widget shipped with: the bar is hidden on every row that
    -- has no length to draw - a press, and a source whose amount the client
    -- withheld - and text parented to a hidden frame is text nobody sees. So
    -- the loose read, whose whole purpose is to still SHOW a withheld row,
    -- would have drawn an empty track.
    row.top = CreateFrame("Frame", nil, row)
    row.top:SetAllPoints(row)
    row.top:SetFrameLevel(row.bar:GetFrameLevel() + 5)
    row.top:Show()

    row.icon = row.top:CreateTexture(nil, "OVERLAY")
    row.icon:SetSize(BAR_PIC, BAR_PIC)
    row.icon:SetPoint("LEFT", row.top, "LEFT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon:Hide()

    row.name = UI.Label(row.top, "", UI.FS.row, C.text)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- TWO RIGHT-HAND COLUMNS, fixed right to left: the amount, and the share
    -- of the whole beside it. The number alone says little - "24.46M" is a
    -- night's work or a tenth of somebody else's - and the share is what
    -- turns it into a reading.
    row.amount = UI.Label(row.top, "", UI.FS.row, C.text)
    row.amount:SetPoint("RIGHT", row.top, "RIGHT", -8, 0)
    row.amount:SetJustifyH("RIGHT")
    row.amount:SetWordWrap(false)

    row.share = UI.Label(row.top, "", UI.FS.meta, C.textFaint)
    row.share:SetPoint("RIGHT", row.amount, "LEFT", -10, 0)
    row.share:SetJustifyH("RIGHT")
    row.share:SetWordWrap(false)
    row.name:SetPoint("RIGHT", row.share, "LEFT", -8, 0)

    -- THE CLIENT'S OWN TOOLTIP, on a frame of its own because a font string
    -- cannot take the mouse. Only a row that names a spell has one to show -
    -- a meter row is a person, and there is nothing behind a person's name
    -- that this window could open.
    row.hit = CreateFrame("Frame", nil, row.top)
    row.hit:SetAllPoints(row.top)
    row.hit:EnableMouse(true)
    row.hit:SetScript("OnEnter", function(self)
        -- SAME TWO ANSWERS AS THE TABLE ROW ABOVE. Written out rather than
        -- shared because this one reads the ROW's spell id and that one
        -- reads the hit frame's - two fields, one behaviour, and the day
        -- they disagree is the day one window grows a card the other has.
        if self.dkFell and CombatLog.Blow and ns.Death.ShowEnemyTip then
            local blow, full = CombatLog.Blow(self.dkFell)
            if blow and blow.who then
                ns.Death.ShowEnemyTip(self, {
                    who = blow.who, art = blow.art, summary = blow.summary,
                    note = full and "Click to replay this death" or nil,
                })
                return
            end
        end
        if not (GameTooltip and row.spellID) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not pcall(GameTooltip.SetSpellByID, GameTooltip, row.spellID) then
            GameTooltip:ClearLines()
            GameTooltip:AddLine(row.name:GetText() or "", 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    row.hit:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
        if ns.Death.HideEnemyTip then ns.Death.HideEnemyTip() end
    end)
    -- AND PRESSING A FALL OPENS ITS REPLAY, the same as pressing it on the
    -- line above. Two ways in for one thing, because both of them are where
    -- somebody is already looking when they want it.
    row.hit:SetScript("OnMouseDown", function(self)
        if not (self.dkFell and ns.Replay and ns.Replay.Open) then return end
        local full = CombatLog.FullDeath(self.dkFell)
        if full then ns.Replay:Open(full) end
    end)

    row:Hide()
    return row
end

-- THE CLIENT'S OWN TOOLTIP FOR A ROW THAT NAMES A SPELL.
--
-- Named at file scope rather than written as a closure per row: these are
-- handed to every row of a pool that is now three hundred deep.
local function SpellTipEnter(self)
    -- A ROW ABOUT SOMEBODY'S DEATH SHOWS THE ENEMY, not the spell.
    --
    -- Owner's standing rule, 2026-08-30: "wir sollten death log und combat
    -- log immer abgleichen ... auch was icons, spell namen, boss namen,
    -- hover infos angeht." The group death log and the replay already hang
    -- this card off a killer's face; this is the same card, reached the same
    -- way, rather than a second one that would drift.
    if self.dkFell and CombatLog.Blow and ns.Death.ShowEnemyTip then
        local blow = CombatLog.Blow(self.dkFell)
        if blow and blow.who then
            ns.Death.ShowEnemyTip(self, {
                who = blow.who, art = blow.art, summary = blow.summary,
            })
            return
        end
    end
    if not (GameTooltip and self.spellID) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if not pcall(GameTooltip.SetSpellByID, GameTooltip, self.spellID) then
        GameTooltip:ClearLines()
        GameTooltip:AddLine(self.label or "", 1, 1, 1)
    end
    GameTooltip:Show()
end

local function SpellTipLeave()
    if ns.Death.HideEnemyTip then ns.Death.HideEnemyTip() end
    if GameTooltip then GameTooltip:Hide() end
end

---------------------------------------------------------------------------
-- ONE NAME WITH ALL OF ITS NUMBERS
--
-- The same anatomy as the bar above it - a track, a fill, and its text on the
-- fill rather than on the row, for the same reason: a child frame draws above
-- every layer of its parent, so a label written on the row would end up under
-- the bar that is meant to sit behind it.
--
-- The cells are made when a column asks for one. How many there are is the
-- client's answer, not ours.
---------------------------------------------------------------------------
local function BuildPerson(parent, width)
    local UI, C = ns.UI, ns.UI.C
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, PERSON_H)

    row.track = row:CreateTexture(nil, "BACKGROUND")
    row.track:SetAllPoints(row)
    row.track:SetColorTexture(C.control[1], C.control[2], C.control[3], 0.40)

    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetAllPoints(row)
    row.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    row.bar:SetMinMaxValues(0, 1)
    row.bar:SetValue(0)


    -- AND THE TEXT ON A FRAME OF ITS OWN, ABOVE BOTH.
    --
    -- Not on the row - it would end up under the fill, which is the trap this
    -- addon already has a name for. And NOT ON THE BAR either, which is the
    -- mistake this widget shipped with: the bar is hidden on every row that
    -- has no length to draw - a press, and a source whose amount the client
    -- withheld - and text parented to a hidden frame is text nobody sees. So
    -- the loose read, whose whole purpose is to still SHOW a withheld row,
    -- would have drawn an empty track.
    row.top = CreateFrame("Frame", nil, row)
    row.top:SetAllPoints(row)
    row.top:SetFrameLevel(row.bar:GetFrameLevel() + 5)
    row.top:Show()

    row.icon = row.top:CreateTexture(nil, "OVERLAY")
    row.icon:SetSize(14, 14)
    row.icon:SetPoint("LEFT", row.top, "LEFT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon:Hide()

    -- WHEN, DOWN THE LEFT EDGE. Owner, 2026-08-31: "bei der history fehlt
    -- links immer noch der timestamp, den haben wir ja auch im replay."
    --
    -- ~~It was already on the row~~ - but out at the right, tucked against
    -- the numbers, where it reads as one more amount rather than as the
    -- clock. A chronological list is read DOWN, and the one column you
    -- follow while doing that has to be the one at the edge you start from.
    -- Same list, same fact, one column over: the replay's own cast panel
    -- has carried it beside the name from the beginning.
    --
    -- Only History turns it on; the log page is totals and has no moment to
    -- put here.
    row.stamp = UI.Label(row.top, "", UI.FS.meta, C.textFaint)
    row.stamp:SetJustifyH("RIGHT")
    row.stamp:SetWordWrap(false)
    row.stamp:SetWidth(STAMP_W)
    row.stamp:SetPoint("LEFT", row.top, "LEFT", 4, 0)
    row.stamp:Hide()

    row.name = UI.Label(row.top, "", UI.FS.row, C.text)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- WHAT ONLY WE KNOW, between the name and the lanes: how often you
    -- pressed it and how long ago. The meter has the amounts and no idea
    -- which of them you asked for; this addon has the presses and no
    -- amounts. The row is the join.
    row.note = UI.Label(row.top, "", UI.FS.meta, C.textFaint)
    row.note:SetJustifyH("RIGHT")
    row.note:SetWordWrap(false)

    -- The client's own tooltip, on a frame because a font string takes no
    -- mouse. Owner asked for the hover to be reused: "auch spell icons, boss
    -- icons, hover infos etc."
    -- AND A HEADING, FOR THE ROW THAT IS ONE.
    --
    -- Owner, 2026-08-30: "setz die auch auf die hoehe von dmg etc. da sparen
    -- wir auch mehr platz." A section heading and the column heads under it
    -- were two rows saying two halves of one thing - what this block is, and
    -- what its lanes mean - so they are one row now, and every block on the
    -- page got its heading's height back.
    --
    -- Its own font string rather than borrowing row.name: the name is 13 and
    -- this is 15, and changing the size of a POOLED label per use is how a
    -- person's row ends up wearing a heading's face.
    row.heading = UI.Label(row.top, "", UI.FS.section, C.textBody)
    row.heading:SetPoint("LEFT", row.top, "LEFT", 2, 0)
    row.heading:SetJustifyH("LEFT")
    row.heading:SetWordWrap(false)
    row.heading:Hide()

    row.hit = CreateFrame("Frame", nil, row.top)
    row.hit:SetAllPoints(row.top)
    row.hit:EnableMouse(true)
    row.hit:SetScript("OnEnter", SpellTipEnter)
    row.hit:SetScript("OnLeave", SpellTipLeave)

    row.cells = {}
    row:Hide()
    return row
end

---------------------------------------------------------------------------
-- THE FIGHT, END TO END
--
-- Owner, 2026-08-29: "[zeit]strahl waere auch super."
--
-- What can honestly be drawn on it is decided by what this addon is allowed
-- to see. COMBAT_LOG_EVENT_UNFILTERED cannot be registered on 12.1, so there
-- is no stream of hits to plot - but there are two things nobody else has:
-- every button this addon watched you press, and every fall the death log
-- read out of the client's own recap. Those two against the fight's length
-- are a real reading of a pull: where the rotation was dense, where you spent
-- a cooldown, and where somebody went down anyway.
--
-- The marks take the mouse, so each one still answers "which spell was that".
-- Its handlers are named at file scope: a closure per mark is a table per
-- mark, and this pool is walked on every repaint.
---------------------------------------------------------------------------
-- A COLUMN HEAD, PRESSED. Named at file scope for the same reason the marks'
-- handlers are: a closure per head is a table per head, and these are rebuilt
-- on every repaint.
local function SortClick(self)
    if not self.dkSortKey then return end
    CombatLog.sortBy = self.dkSortKey
    CombatLog:Refresh()
end

---------------------------------------------------------------------------
-- WHAT KILLED SOMEBODY, AND THE CARD BEHIND IT
--
-- Owner, standing rule, 2026-08-30: "wir sollten death log und combat log
-- immer abgleichen, es macht keinen sinn etwas nicht im combat log zu haben,
-- wenn wir das im deathlog schon koennen. auch was icons, spell namen, boss
-- namen, hover infos und angeht."
--
-- So this is not a second version of the enemy tip - it is the SAME one, the
-- one the group death log and the replay already hang off a killer's face,
-- reached through the same two functions that build what it shows. A second
-- copy would be a second thing to get wrong, and the two windows would drift
-- apart on exactly the day somebody changed one of them.
---------------------------------------------------------------------------
function CombatLog.Blow(entry)
    local full = CombatLog.FullDeath(entry)
    local events = full and type(full.events) == "table" and full.events or nil
    if not (events and ns.RaidDeaths and ns.RaidDeaths.Blow) then return nil end
    local blow = ns.RaidDeaths.Blow(events)
    if not blow then return nil end
    -- The summary is a second call in RaidDeaths too - see its Row builder.
    if ns.Death.SourceSummary then
        blow.summary = ns.Death.SourceSummary(events, blow.who)
    end
    return blow, full
end

-- THE OTHER PARTY'S CARD, off the face on a row. Its own mouse rather than
-- the row's: the row answers with the SPELL's tooltip, and a mob and an
-- ability are two different questions that happen to sit on one line.
local function WhoEnter(self)
    if not (self.dkWho and ns.Death.ShowEnemyTip) then return end
    ns.Death.ShowEnemyTip(self, {
        who = self.dkWho, art = self.dkArt, note = self.dkNote,
    })
end

local function WhoLeave()
    if ns.Death.HideEnemyTip then ns.Death.HideEnemyTip() end
end

-- BUILT THE FIRST TIME A ROW NEEDS ONE, not with the row. A face carries a
-- PlayerModel, and this pool reaches thirty rows on a busy page - thirty
-- models for the two or three that ever show one is a cost nobody sees and
-- everybody pays.
local function FaceOn(row)
    if row.face then return row.face end
    if not (ns.Death and ns.Death.CreateFace) then return nil end
    local face = ns.Death.CreateFace(row.top, 16)
    face:SetPoint("LEFT", row.top, "LEFT", 3, 0)
    face:SetFrameLevel(row.top:GetFrameLevel() + 4)
    face:EnableMouse(true)
    face:SetScript("OnEnter", WhoEnter)
    face:SetScript("OnLeave", WhoLeave)
    face:Hide()
    row.face = face
    return face
end

local function FellEnter(self)
    local blow = self.dkFell and CombatLog.Blow(self.dkFell)
    if not (blow and blow.who and ns.Death.ShowEnemyTip) then return end
    ns.Death.ShowEnemyTip(self, {
        who = blow.who, art = blow.art, summary = blow.summary,
    })
end

local function FellLeave()
    if ns.Death.HideEnemyTip then ns.Death.HideEnemyTip() end
end

local function MarkEnter(self)
    -- A FALL ON THE LINE ANSWERS WITH THE ENEMY'S CARD, the same one the
    -- rows below and both death logs show. Owner's standing rule,
    -- 2026-08-30: "wir sollten death log und combat log immer abgleichen ...
    -- auch was icons, spell namen, boss namen, hover infos angeht."
    if self.dkFell and CombatLog.Blow and ns.Death.ShowEnemyTip then
        local blow, full = CombatLog.Blow(self.dkFell)
        if blow and blow.who then
            ns.Death.ShowEnemyTip(self, {
                who = blow.who, art = blow.art, summary = blow.summary,
                note = full and "Click to replay this death" or nil,
            })
            return
        end
    end
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    local drew = false
    if self.spellID then
        drew = pcall(GameTooltip.SetSpellByID, GameTooltip, self.spellID)
    end
    if not drew then
        GameTooltip:ClearLines()
        GameTooltip:AddLine(self.label or "", 1, 1, 1)
    elseif self.label and self.label ~= "" then
        GameTooltip:AddLine(self.label, 1, 1, 1)
    end
    if self.stamp then
        GameTooltip:AddLine(self.stamp, 0.6, 0.65, 0.7)
    end
    if type(self.scrollTo) == "number" then
        GameTooltip:AddLine("Click to find it in the log below",
            1, 0.478, 0.239)
    end
    GameTooltip:Show()
end

-- A CLICK ON THE LINE PUTS THE LOG UNDER IT - AND ON A FALL IT OPENS THE
-- REPLAY.
--
-- ~~Owner, 2026-08-29: "ich wuerde das anklickbar machen, dann hat man das
-- replay?" - a replay is its own build and needs its own measurements; THIS
-- is the half that is free.~~ OVERTAKEN 2026-08-31, by the owner asking
-- again - "wie beim death log ein extra fenster haben MIT dem Replay, genau
-- wie beim death log? DAS waere episch" - and by the fact that Replay.lua
-- has existed since 2026-08-16. For a FALL there is nothing left to build:
-- the replay takes a death snapshot, and the pull already keeps the line
-- that finds one.
--
-- AND ONLY FOR A FALL, which is not a decision of ours. The replay's upper
-- lane is Blizzard's death recap, and the game writes one when you DIE.
-- Per-moment incoming damage anywhere else does not exist for an addon on
-- this patch: the combat log refuses to be registered (12.1), and the meter
-- keeps per-ability totals with no clock on them. A window drawn for a
-- moment nobody died at would have an empty top half.
local function MarkClick(self)
    if self.dkFell and ns.Replay and ns.Replay.Open then
        local full = CombatLog.FullDeath(self.dkFell)
        if full then
            ns.Replay:Open(full)
            return
        end
    end
    -- THE SEQUENCE LIVES ON HISTORY NOW, so a mark pressed anywhere else
    -- has to take you there first. Owner, 2026-08-30: "das what happened in
    -- order kann im combat log raus" - which leaves the line on a page with
    -- no log under it, and a mark that answers nothing is a mark that lies
    -- about being clickable.
    --
    -- The row it wants does not exist until that page has been painted, so
    -- the press is left on the frame and the painter picks it up on its way
    -- out. One repaint, not two.
    if self.press and CombatLog.kind ~= CombatLog.PRESSED then
        if frame then frame.pendingPress = self.press end
        CombatLog.kind = CombatLog.PRESSED
        CombatLog:Refresh()
        return
    end
    local scroll = self.dkScroll
    if not (scroll and type(self.scrollTo) == "number") then return end
    -- THROUGH THE SCROLL AREA'S OWN DOOR, and that is not tidiness.
    -- SetVerticalScroll takes any number at all: a mark near the end of a
    -- three-hundred-row log lands past the last row, on blank space. Together
    -- with a wheel that had gone dead - see UI.ScrollArea - that was a page
    -- with no way back, which is what the owner hit on 2026-08-30: "ich komm
    -- auch nicht mehr zurueck ich bin stuck in dem fenster."
    scroll.ScrollTo(math.max(0, self.scrollTo))
end

local function MarkLeave()
    if GameTooltip then GameTooltip:Hide() end
    if ns.Death.HideEnemyTip then ns.Death.HideEnemyTip() end
end

local function BuildTimeline(parent, width)
    local UI, C = ns.UI, ns.UI.C
    local band = CreateFrame("Frame", nil, parent)
    band:SetSize(width, TIME_H)

    band.line = band:CreateTexture(nil, "BACKGROUND")
    band.line:SetPoint("TOPLEFT", band, "TOPLEFT", 0, -22)
    band.line:SetPoint("TOPRIGHT", band, "TOPRIGHT", 0, -22)
    band.line:SetHeight(2)
    band.line:SetColorTexture(C.controlHi[1], C.controlHi[2], C.controlHi[3], 1)

    band.startLabel = UI.Label(band, "0:00", UI.FS.meta, C.textFaint)
    band.startLabel:SetPoint("TOPLEFT", band, "TOPLEFT", 0, -36)

    band.endLabel = UI.Label(band, "", UI.FS.meta, C.textFaint)
    band.endLabel:SetPoint("TOPRIGHT", band, "TOPRIGHT", 0, -36)
    band.endLabel:SetJustifyH("RIGHT")

    band.marks = {}
    band:Hide()
    return band
end

---------------------------------------------------------------------------
-- ONE ROW OF THE COLUMN, in whichever of its three shapes
--
-- Its own widget rather than the death log's: that one carries faces,
-- culprits and a two-column pull line, and none of those exist here. What IS
-- shared is the rule that decides the three levels - ns.Death.GroupItems -
-- so the two columns cannot group a night two different ways.
---------------------------------------------------------------------------
-- The face and the tile, at the sizes the other two columns use: a column
-- that reads the same way is the point of copying them at all.
local SIDE_FACE = 22
local SIDE_ART_W, SIDE_ART_H = 52, 32

local function BuildSideRow(parent)
    local UI, C = ns.UI, ns.UI.C
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(CombatLog.LAYOUT.pullH)

    row.band = row:CreateTexture(nil, "BACKGROUND", nil, -2)
    row.band:SetAllPoints(row)
    row.band:SetColorTexture(C.surface[1], C.surface[2], C.surface[3], 1)
    row.band:Hide()

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:Hide()

    row.mark = row:CreateTexture(nil, "ARTWORK")
    row.mark:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.mark:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.mark:SetWidth(2)
    row.mark:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    row.mark:Hide()

    row.rule = row:CreateTexture(nil, "ARTWORK")
    row.rule:SetColorTexture(C.separator[1], C.separator[2], C.separator[3], 1)
    row.rule:SetHeight(1)
    row.rule:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.rule:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    row.rule:Hide()

    row.chev = UI.Glyph(row, "caretDOWN", 10, C.textFaint)
    row.chev:SetPoint("LEFT", row, "LEFT", 5, 0)
    row.chev:Hide()

    row.num = UI.Label(row, "", UI.FS.eyebrow, C.textFaint)
    row.num:SetJustifyH("RIGHT")
    row.num:SetWidth(16)
    row.num:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -6)

    -- THE SAME FURNITURE THE OTHER TWO COLUMNS CARRY.
    --
    -- Owner, 2026-08-30: "auch fehlt auf der rechten seite die komplette
    -- boss avatare, dungeon bilder etc - verlinkungen." Both death logs put
    -- a boss's face and the guide's tile down their column and this one had
    -- neither - the standing rule broken in the window built last: "wir
    -- sollten death log und combat log immer abgleichen ... auch was icons,
    -- spell namen, boss namen, hover infos angeht."
    --
    -- NOTHING NEW WAS NEEDED FOR IT. The items already carry `journal` and
    -- `bossID` - Death.GroupItems has put them there all along, for all
    -- three windows - and both the face and the tile are Death's own
    -- builders. This column simply never drew them.
    --
    -- BORROWED, NOT REBUILT, so a fix to either shows up in all three.
    row.face = ns.Death.CreateFace(row, SIDE_FACE)
    row.face:EnableMouse(true)
    row.face:Hide()

    -- THE GUIDE'S TILE down the right of a place header, sized to the row
    -- rather than left at its default, which is taller than one.
    row.art = ns.Death.CreatePlaceArt(row, SIDE_ART_W, SIDE_ART_H)
    row.art:SetPoint("RIGHT", row, "RIGHT", -4, 0)

    -- THE FACE AND THE NAME ANSWER TOGETHER: the tip says whose page is
    -- behind it, and the click opens it. One pair of handlers for both,
    -- because two would be two places to forget one of them.
    local function FaceEnter(self)
        if not row.faceName then return end
        ns.Death.ShowEnemyTip(self, { who = row.faceName, art = row.faceArt,
            note = row.facePage
                and "Click to open it in the Adventure Guide" or nil })
    end
    local function FaceLeave()
        ns.Death.HideEnemyTip()
    end
    local function FaceClick()
        if not row.facePage then return end
        ns.Death.OpenJournal(row.faceJournal, row.facePage.journal)
    end
    row.face:SetScript("OnEnter", FaceEnter)
    row.face:SetScript("OnLeave", FaceLeave)
    row.face:SetScript("OnMouseUp", FaceClick)

    -- AND SO DOES THE BOSS'S NAME BESIDE IT. Orange in this addon is a
    -- promise that a word can be pointed at, and a name wearing it with
    -- nothing behind it is the promise broken.
    row.tagHit = CreateFrame("Button", nil, row)
    row.tagHit:SetScript("OnEnter", FaceEnter)
    row.tagHit:SetScript("OnLeave", FaceLeave)
    row.tagHit:SetScript("OnClick", FaceClick)
    row.tagHit:Hide()

    -- EVERY LABEL ANCHORED HERE, not only in the painter. An unanchored
    -- region is not drawn at all, so a branch that forgets one leaves a blank
    -- strip rather than a misplaced word.
    row.lead = UI.Label(row, "", UI.FS.meta, C.text)
    row.lead:SetJustifyH("LEFT")
    row.lead:SetWordWrap(false)
    row.lead:SetPoint("TOPLEFT", row, "TOPLEFT", 28, -6)

    row.right = UI.Label(row, "", UI.FS.meta, C.textFaint)
    row.right:SetJustifyH("RIGHT")
    row.right:SetWordWrap(false)
    row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6)
    row.lead:SetPoint("RIGHT", row.right, "LEFT", -8, 0)

    -- THE SECOND LINE HANGS OFF THE FIRST, not off the row's bottom edge.
    -- Measuring both from opposite ends is an arithmetic with the font's
    -- height in it, and that height is the client's to know.
    row.note = UI.Label(row, "", UI.FS.meta, C.textFaint)
    row.note:SetJustifyH("LEFT")
    row.note:SetWordWrap(false)
    row.note:SetPoint("TOPLEFT", row.lead, "BOTTOMLEFT", 0, -3)
    row.note:SetPoint("RIGHT", row, "RIGHT", -8, 0)

    row:SetScript("OnEnter", function(self)
        if self.selected then return end
        self.bg:SetColorTexture(C.controlHi[1], C.controlHi[2],
            C.controlHi[3], 0.35)
        self.bg:Show()
    end)
    row:SetScript("OnLeave", function(self)
        if self.selected then return end
        self.bg:Hide()
    end)

    -- EVERY ROW IS A CHOICE, AT ALL THREE LEVELS.
    --
    -- Owner, 2026-08-31, pointing at "Den of Nalorakk - 16 pulls": "man muss
    -- eigentlich, wenn ich die instanz ... anklicke, den totalen schaden der
    -- instanz sehen, nicht nur per pull." So a press means one thing here -
    -- show me this - and it means the same thing on a place, on a boss and
    -- on a pull.
    --
    -- ~~A place or a fight FOLDS, a pull is chosen.~~ That put two meanings
    -- on one press, and this window has already had to pull two of those
    -- apart twice. Folding gets its own target instead, which is the same
    -- answer the group death log reached: "TWO CLICK TARGETS, SPATIALLY
    -- APART".
    --
    -- ONE FIELD, NOT TWO. `pick` is whatever CombatLog.showing becomes - a
    -- pull's number, or a group's id - and nothing else decides the
    -- selection. Two fields answering "what is chosen" is exactly the shape
    -- that let a page and a chip row disagree here before.
    row:SetScript("OnClick", function(self)
        if self.pick == nil then return end
        CombatLog.showing = self.pick
        CombatLog:Refresh()
    end)

    -- AND THE CHEVRON IS THE FOLD. Written out rather than as one
    -- `x and y or z`: what is stored is a boolean, and that idiom cannot
    -- carry a false through it.
    local foldHit = CreateFrame("Button", nil, row)
    foldHit:SetSize(22, 22)
    foldHit:SetPoint("LEFT", row, "LEFT", 0, 0)
    foldHit:SetScript("OnClick", function(self)
        local id = self:GetParent().foldID
        if id == nil then return end
        if CombatLog.collapsed[id] == true then
            CombatLog.collapsed[id] = nil
        else
            CombatLog.collapsed[id] = true
        end
        CombatLog:Refresh()
    end)
    -- The row's own highlight, handed on. A hover that goes out the moment
    -- the pointer crosses onto the chevron reads as the row flickering.
    foldHit:SetScript("OnEnter", function(self)
        local parent = self:GetParent()
        local enter = parent:GetScript("OnEnter")
        if enter then enter(parent) end
    end)
    foldHit:SetScript("OnLeave", function(self)
        local parent = self:GetParent()
        local leave = parent:GetScript("OnLeave")
        if leave then leave(parent) end
    end)
    foldHit:Hide()
    row.foldHit = foldHit

    row:Hide()
    return row
end

local function PaintSideRow(row, item, chosen)
    local C = ns.UI.C
    row:SetHeight(CombatLog.RowHeight(item))
    row.foldID, row.pick, row.selected = nil, nil, false
    row.chev:Hide()
    row.foldHit:Hide()
    row.rule:Hide()
    row.band:Hide()
    row.mark:Hide()
    row.bg:Hide()
    row.num:SetText("")
    row.note:SetText("")

    -- WIPED BY THE ONE PAINTER, not by each branch. The rows are a shared
    -- pool: what a branch does not set, the row inherits from whatever it
    -- was last time - a boss's face left standing on a pull is not a
    -- misplaced picture, it is the wrong boss.
    row.face:Hide()
    row.tagHit:Hide()
    row.faceName, row.facePage, row.faceArt, row.faceJournal = nil, nil, nil, nil
    row.art.Paint(nil)
    row.lead:ClearAllPoints()
    row.lead:SetPoint("TOPLEFT", row, "TOPLEFT", 28, -6)
    row.right:ClearAllPoints()
    row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6)
    row.note:ClearAllPoints()
    row.note:SetPoint("TOPLEFT", row.lead, "BOTTOMLEFT", 0, -3)
    row.note:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.lead:SetPoint("RIGHT", row.right, "LEFT", -8, 0)

    if item.kind == "run" then
        row.foldID, row.pick = item.id, item.id
        row.rule:Show()
        row.band:Show()
        row.chev:Show()
        row.foldHit:Show()
        row.chev:SetKind(item.open and "caretDOWN" or "caretRIGHT")

        -- THE PLACE'S OWN PICTURE, and the words stop before it. Which edge
        -- they stop at is decided by what was actually DRAWN rather than by
        -- the fact that a dungeon has a journal id: a line indented past an
        -- empty square reads as a missing image.
        local drew = row.art.Paint(item.journal)
        local edge, corner, side = row, "TOPRIGHT", "RIGHT"
        if drew then edge, corner, side = row.art, "TOPLEFT", "LEFT" end
        row.right:ClearAllPoints()
        row.right:SetPoint("TOPRIGHT", edge, corner, -6, -6)
        row.note:ClearAllPoints()
        row.note:SetPoint("TOPLEFT", row.lead, "BOTTOMLEFT", 0, -3)
        row.note:SetPoint("RIGHT", edge, side, -6, 0)
        row.lead:SetPoint("RIGHT", row.right, "LEFT", -6, 0)

        row.lead:SetText(item.instance or item.tag or "Somewhere")
        row.lead:SetTextColor(C.accentCool[1], C.accentCool[2], C.accentCool[3])
        row.right:SetText(item.tag or "")
        -- AND WHAT THE WHOLE RUN CAME TO, beside how many pulls it took.
        -- Owner, 2026-08-31: "den totalen schaden der instanz sehen." One
        -- press opens it; this is the same answer without the press.
        local bits = { string.format("%d pull%s", item.leaves,
            item.leaves == 1 and "" or "s") }
        local worth = CombatLog.GroupSummary(CombatLog.log, item.indices)
        if worth then bits[#bits + 1] = worth end
        row.note:SetText(table.concat(bits, "  -  "))
    elseif item.kind == "boss" then
        row.foldID, row.pick = item.id, item.id
        row.chev:Show()
        row.foldHit:Show()
        row.chev:SetKind(item.open and "caretDOWN" or "caretRIGHT")
        row.lead:SetText(item.label or "")
        -- A BOSS IS A LINK, TRASH IS A FACT - the same three things both
        -- death logs say with this row: the orange, the face, and the
        -- click. Owner, 2026-08-29 about the other pair: "die rechte seite
        -- beim normalen log muesste ja gleich wie beim group sein oder
        -- nicht." It holds for the third window too.
        if item.boss then
            row.lead:SetTextColor(C.hot[1], C.hot[2], C.hot[3])
            row.faceName = item.label
            row.faceJournal = item.journal
            row.faceArt = ns.Death.GuideFace(item.journal, item.bossID,
                item.label)
            row.facePage = ns.Death.BossPage(item.journal, item.bossID,
                item.label)
            if ns.Death.PaintFace(row.face, row.faceArt) then
                row.face:ClearAllPoints()
                row.face:SetPoint("LEFT", row, "LEFT", 28, 0)
                row.face:Show()
                row.lead:ClearAllPoints()
                row.lead:SetPoint("LEFT", row.face, "RIGHT", 6, 0)
                row.lead:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
            end
            row.tagHit:ClearAllPoints()
            row.tagHit:SetAllPoints(row.lead)
            row.tagHit:Show()
        else
            row.lead:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
        end
        row.right:SetText(string.format("%d pull%s", item.leaves,
            item.leaves == 1 and "" or "s"))
    else
        local fight = item.entry
        row.pick = type(fight) == "table" and fight.key or nil
        row.num:SetText(tostring(item.number or ""))
        row.lead:SetText((type(fight) == "table" and fight.when) or "--:--")
        row.lead:SetTextColor(C.textBody[1], C.textBody[2], C.textBody[3])
        row.right:SetText(type(fight) == "table"
            and type(fight.duration) == "number"
            and ns.FormatTime(fight.duration) or "")
        row.note:SetText(CombatLog.PullSummary(fight))
    end

    -- ONE MARK FOR ONE SELECTION, wherever in the three levels it landed.
    -- Painted once at the end rather than in each branch: three copies of
    -- "this is the chosen one" is three chances for two of them to be lit.
    row.selected = row.pick ~= nil and row.pick == chosen
    if row.selected then
        row.bg:SetColorTexture(C.control[1], C.control[2], C.control[3], 1)
        row.bg:Show()
        row.mark:Show()
    end
end

function CombatLog:Create()
    if frame then return frame end
    if not (ns.UI and ns.UI.C) then return nil end
    local UI, C = ns.UI, ns.UI.C

    frame = CreateFrame("Frame", "ZwoelfStuffCombatLog", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    -- ALL THREE WINDOWS SHARE ONE STRATA AND ALL THREE ARE TOP-LEVEL.
    --
    -- Owner, 2026-08-29, with the group death log open over this one: "auch
    -- solltest du die z index anpassen der fenster." Two of them sat on HIGH
    -- and the third on DIALOG, so one was permanently above the other two and
    -- the two peers interleaved by frame level - the far window's chips drawn
    -- over the near window's list, which is what the screenshot showed.
    --
    -- SetToplevel only raises inside ITS OWN strata, so sharing one is what
    -- makes it work at all; with that, whichever you click comes forward.
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:Hide()

    UI.Fill(frame, "BACKGROUND", C.windowBg)
    local edge = ns.CreateBorder(frame, 1, "BORDER")
    edge:SetColor(C.overlayEdge[1], C.overlayEdge[2], C.overlayEdge[3], 1)

    -- THE BOSS'S OWN PORTRAIT, out of the death log's face rather than out
    -- of a second one. Owner, 2026-08-29, listing what to reuse: "auch spell
    -- icons, boss icons, hover infos etc." The column here is this window's
    -- own widget and carries none, so the header is where it goes.
    frame.face = ns.Death.CreateFace(frame, 34)
    frame.face:SetPoint("TOPLEFT", frame, "TOPLEFT", UI.PAD, -14)

    -- Owner named it, 2026-08-29: "ps. das neue modul heisst combat log".
    -- Only ever seen before the first paint - the header then carries the
    -- page's own title, which is a boss or "Right now".
    frame.title = UI.Label(frame, "Combat log", UI.FS.card, C.text)
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", UI.PAD, -18)

    frame.sub = UI.Label(frame, "", UI.FS.meta, C.textFaint)
    frame.sub:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -4)

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -UI.PAD, -14)
    local mark = UI.Glyph(close, "ui-close", 12, C.textDim)
    mark:SetPoint("CENTER", close, "CENTER", 0, 0)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame.close = close

    local rule = UI.Separator(frame)
    rule:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -UI.HEADER_H)
    rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -UI.HEADER_H)

    -----------------------------------------------------------------------
    -- THE COLUMN, on the right, where both death logs keep theirs.
    -----------------------------------------------------------------------
    local L = CombatLog.LAYOUT
    local side = CreateFrame("Frame", nil, frame)
    side:SetWidth(SIDE_W)
    side:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -UI.PAD, -UI.HEADER_H - L.top)
    side:SetPoint("BOTTOM", frame, "BOTTOM", 0, L.bottom)
    frame.side = side

    local sideRule = UI.Separator(frame, false)
    sideRule:SetPoint("TOPRIGHT", side, "TOPLEFT", -12, 0)
    sideRule:SetPoint("BOTTOMRIGHT", side, "BOTTOMLEFT", -12, 0)

    frame.sideTitle = UI.Eyebrow(side, "")
    frame.sideTitle:SetPoint("TOPLEFT", side, "TOPLEFT", 0, 0)

    -- THE LIVE ROW, and it is a row rather than a tab. See the note at the
    -- top of this section.
    local nowRow = BuildSideRow(side)
    nowRow:SetHeight(L.now)
    nowRow:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -L.title - L.titleGap)
    nowRow:SetPoint("RIGHT", side, "RIGHT", 0, 0)
    nowRow:SetScript("OnClick", function()
        CombatLog.showing = nil
        CombatLog:Refresh()
    end)
    nowRow:Show()
    frame.nowRow = nowRow

    local sideBody = CreateFrame("Frame", nil, side)
    sideBody:SetPoint("TOPLEFT", nowRow, "BOTTOMLEFT", 0, -L.gap)
    sideBody:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", 0, 0)
    sideBody:EnableMouseWheel(true)
    sideBody:SetScript("OnMouseWheel", function(_, delta)
        local step = delta > 0 and -1 or 1
        CombatLog.sideOffset = math.max(0,
            math.min(CombatLog.sideMax or 0,
                (CombatLog.sideOffset or 0) + step))
        CombatLog.PaintSideList()
    end)
    frame.sideBody = sideBody
    frame.sideRows = {}

    -----------------------------------------------------------------------
    -- THE PAGE, left of the column.
    -----------------------------------------------------------------------
    local page = CreateFrame("Frame", nil, frame)
    page:SetPoint("TOPLEFT", frame, "TOPLEFT", UI.PAD, -UI.HEADER_H - L.top)
    page:SetPoint("RIGHT", side, "LEFT", -24, 0)
    -- AND DOWN TO THE WINDOW'S OWN FLOOR.
    --
    -- Owner, 2026-08-31: "den footer koennen wir auch weiter runter setzen."
    -- ~~It stopped where the SIDE COLUMN stops~~, forty-six pixels up - and
    -- that number is about the column, which has controls down there. The
    -- page has none, so it was giving away a strip of itself for somebody
    -- else's reason, and the footer sat in the middle of the gap.
    page:SetPoint("BOTTOM", frame, "BOTTOM", 0, 12)
    frame.page = page

    local inner = WIDTH - SIDE_W - UI.PAD * 2 - 24

    -- TWO PAGES, AND THAT IS THE WHOLE SWITCH.
    --
    -- ~~Seven chips for the six meter kinds and History, over two more for
    -- which session.~~ OVERTAKEN by the owner on 2026-08-30, twice in one
    -- evening and both times for the same reason - a control that answers a
    -- question something else already answers:
    --
    --   "dann koennen wir oben die tabs raushauen und haben nur noch 2.
    --    1. combat log (everything) und combat history"
    --   "this fight und since reset kann raus, denn wir haben ja rechts die
    --    sortierung nach pulls!"
    --
    -- The six single-kind pages were a way to see one lane at a time; the
    -- report puts all six lanes on one row, so each of them was a narrower
    -- view of a page that was already open. And WHICH FIGHT is what the
    -- column on the right is for - "Right now" at the top of it and every
    -- recorded pull under it - so a second control for it could disagree
    -- with the column, which is the shape this window has now refused three
    -- times.
    --
    -- What is left is the one question the column cannot answer: totals, or
    -- the order they happened in.
    frame.kindChips = UI.ChipRow(page, inner, {
        chips = {
            { key = CombatLog.EVERYTHING, text = "Combat log" },
            { key = CombatLog.PRESSED,    text = "History" },
        },
        current = function() return CombatLog.kind end,
        onSelect = function(key)
            CombatLog.kind = key
            CombatLog:Refresh()
        end,
    })

    -- AND THE REPLAY, BESIDE THEM.
    --
    -- Owner, 2026-08-31: "mach den replay button rein, neben history, das ist
    -- besser als die lupe ... dann haben wir auch wieder eine wiederkehrende
    -- mechanik wie beim death log."
    --
    -- ~~A lupe on the timeline~~ was the other answer to "ins detail gehen",
    -- and he is right that this one is better: the death log already has a
    -- Replay button in exactly this spot, so a reader who has used one window
    -- has used this one. A control somebody already knows beats a control
    -- that has to be discovered.
    --
    -- A BUTTON, NOT A THIRD CHIP. The chips choose which PAGE is under them;
    -- this opens a window. Two meanings on one row of controls is the shape
    -- this window has already had to pull apart twice.
    --
    -- IT DIMS RATHER THAN DISAPPEARING when the fight has no fall in it. A
    -- control that vanishes takes its own explanation with it, and the same
    -- page says who went down two blocks further on.
    local chips = frame.kindChips.chips or {}
    local replay = UI.Button(page, "Replay", 80, function(self)
        if not (self.dkPlayable and ns.Replay and ns.Replay.Open) then
            return
        end
        local story = CombatLog.ReplayOf(self.dkFight,
            GetTime and GetTime() or 0, self.dkLength)
        -- A story that could not be built opens nothing. Replay's own empty
        -- hands message is about a DEATH, and printing it here would answer
        -- a question nobody on this page asked.
        if story then ns.Replay:Open(story) end
    end)
    if chips[#chips] then
        replay:SetPoint("LEFT", chips[#chips], "RIGHT", 10, 0)
    else
        replay:SetPoint("LEFT", frame.kindChips, "LEFT", 0, 0)
    end
    replay:SetEnabled(false)
    -- AND IT SAYS WHY IT IS DARK.
    --
    -- Owner, 2026-08-31, in front of the finished button: "button ist drin
    -- macht nur nix." He was looking at "Right now", a minute into a fight
    -- nobody had died in - so it was correct, and that is exactly the
    -- problem. Dim is a state, not an explanation, and a control whose only
    -- answer is that it looks slightly greyer has told nobody anything.
    --
    -- HOOKED rather than set: UI.Button already owns OnEnter for its hover
    -- colour, and replacing that would fix one thing by breaking another.
    -- Same shape the cooldowns page uses for its own button.
    replay:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        if self.dkPlayable then
            GameTooltip:AddLine("Play this fight back, second by second",
                1, 1, 1)
            GameTooltip:AddLine("Your health, everything you pressed, and "
                .. "where anybody went down", 0.6, 0.65, 0.7, true)
        else
            GameTooltip:AddLine("Nothing to play back yet", 1, 1, 1)
            GameTooltip:AddLine("This page has no presses and no falls on "
                .. "its clock. Pick a pull you actually fought, or give this "
                .. "one a moment", 0.6, 0.65, 0.7, true)
        end
        GameTooltip:Show()
    end)
    replay:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    frame.replayButton = replay

    local barHost = CreateFrame("Frame", nil, page)
    barHost:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 22)
    local barScroll, barContent = UI.ScrollArea(barHost, inner - 8, 8)
    frame.barHost = barHost
    frame.barScroll = barScroll
    frame.barContent = barContent
    frame.bars = {}
    -- ONE POOL PER SHAPE ON THE REPORT. A shared pool would mean hiding a
    -- leftover of one kind by drawing over it with another, which is the way
    -- a stale row survives a repaint.
    frame.heads = {}
    frame.people = {}
    frame.events = {}
    frame.band = BuildTimeline(barContent, inner - 8)
    frame.barWidth = inner - 8

    frame.pageNote = UI.Label(barContent, "", UI.FS.row, C.textFaint)
    frame.foot = UI.Label(page, "", UI.FS.meta, C.textFaint)
    frame.foot:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 2, 2)
    frame.foot:SetPoint("RIGHT", page, "RIGHT", 0, 0)

    table.insert(UISpecialFrames, "ZwoelfStuffCombatLog")
    return frame
end

---------------------------------------------------------------------------
-- PAINTING
---------------------------------------------------------------------------

-- ONE MORE ROW OF THE COLUMN, made the first time it is needed and kept.
-- Recursive so that asking for slot seven builds one to six on the way: the
-- rows are a chain, each hung off the bottom of the one above, and a chain
-- with a hole in it is a row anchored to nothing.
local function SideRow(slot)
    local row = frame.sideRows[slot]
    if row then return row end
    row = BuildSideRow(frame.sideBody)
    if slot == 1 then
        row:SetPoint("TOPLEFT", frame.sideBody, "TOPLEFT", 0, 0)
    else
        row:SetPoint("TOPLEFT", SideRow(slot - 1), "BOTTOMLEFT", 0,
            -CombatLog.LAYOUT.gap)
    end
    row:SetPoint("RIGHT", frame.sideBody, "RIGHT", 0, 0)
    frame.sideRows[slot] = row
    return row
end

function CombatLog.PaintSideList()
    if not frame then return end
    local C = ns.UI.C

    -- THE LIVE ROW. It counts what the client is holding this moment, which
    -- is a different number from anything in the list under it.
    local live = CombatLog.showing == nil
    local nowRow = frame.nowRow
    nowRow.chev:Hide()
    nowRow.rule:Hide()
    nowRow.band:Hide()
    nowRow.num:SetText("")
    nowRow.lead:SetText("Right now")
    nowRow.lead:SetTextColor(C.text[1], C.text[2], C.text[3])
    nowRow.right:SetText(UnitAffectingCombat
        and UnitAffectingCombat("player") and "in combat" or "")
    nowRow.note:SetText("what the meter is holding this moment")
    nowRow.selected = live
    nowRow.bg:SetShown(live)
    nowRow.mark:SetShown(live)
    if live then
        nowRow.bg:SetColorTexture(C.control[1], C.control[2], C.control[3], 1)
    end

    CombatLog.collapsed = CombatLog.collapsed or {}
    local items = ns.Death.GroupItems(CombatLog.log, CombatLog.collapsed,
        "pull")
    local first, count, far = ns.Death.ListWindow(items,
        CombatLog.sideOffset, CombatLog.Room(), CombatLog.RowHeight,
        CombatLog.LAYOUT.gap)
    CombatLog.sideOffset = first - 1
    CombatLog.sideMax = far

    -- The pool is read BEFORE the loop: SideRow appends to it, and a loop
    -- bounded by a list it is growing decides how long it runs while it runs.
    local pool = #frame.sideRows
    for slot = 1, math.max(count, pool) do
        local item
        if slot <= count then item = items[first + slot - 1] end
        if item then
            local row = SideRow(slot)
            PaintSideRow(row, item, CombatLog.showing)
            row:Show()
        else
            local row = frame.sideRows[slot]
            if row then
                row.foldID, row.pick, row.selected = nil, nil, false
                row.foldHit:Hide()
                row:Hide()
            end
        end
    end

    -- NO SILENT CAP: a column that stops at the window's edge and does not
    -- say so reads as a column with nothing more in it.
    local total = #CombatLog.log
    if total == 0 then
        frame.sideTitle:SetText("No pull recorded yet")
    elseif far > 0 then
        frame.sideTitle:SetText(string.format("%d pulls - scroll for more",
            total))
    else
        frame.sideTitle:SetText(string.format("%d pull%s", total,
            total == 1 and "" or "s"))
    end
end

-- THE FACE ON THE HEADER, and the title moves aside for it.
--
-- The portrait is only there when the guide HAS one, so the anchor is decided
-- by what was actually drawn rather than by the fact that a boss has a name:
-- a title indented past an empty square reads as a missing image.
function CombatLog.PaintHeadFace(fight)
    if not (frame and frame.face and ns.Death.GuideFace) then return end

    local journal, bossID, boss
    if type(fight) == "table" then
        journal, bossID, boss = fight.journal, fight.bossID, fight.boss
    else
        local where = CombatLog.Whereabouts()
        journal, bossID, boss = where.journal, where.bossID, where.boss
    end

    local art = boss and ns.Death.GuideFace(journal, bossID, boss) or nil
    local drew = ns.Death.PaintFace(frame.face, art)

    frame.title:ClearAllPoints()
    if drew then
        frame.title:SetPoint("TOPLEFT", frame.face, "TOPRIGHT", 10, -4)
    else
        frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", ns.UI.PAD, -18)
    end
end


---------------------------------------------------------------------------
-- THE REPORT
--
-- Owner, 2026-08-29: "ich moechte sehen was mache ich an schaden, was bekomme
-- ich, heal etc. alles in einer liste ... wir haben die mechaniken doch alle
-- schon. auch spell icons, boss icons, hover infos etc. im prinzip ist das ja
-- der deathlog, nur halt auf den kampf bezogen."
--
-- So it is built out of what the death log already has, and it reads one pull
-- top to bottom:
--
--   the fight end to end   every press and every fall on one line
--   everyone, everything   one row per person, all six kinds across it
--   who went down          the death log's own hit-by-hit rows, in place
--   what you pressed       the first ten, the chip behind it has all of them
--
-- The second block is the one the client's meter cannot do at all: its six
-- kinds are six separate sessions, so "what did I deal AND take AND heal" is
-- only answerable by clicking through six pages and remembering.
---------------------------------------------------------------------------
function CombatLog.PaintReport(fight, mode)
    local UI, C = ns.UI, ns.UI.C
    -- HISTORY IS THE SAME PAGE WITH TWO BLOCKS LEFT OFF: the group's table and
    -- the death rows are about everybody, and this chip is about you.
    local yours = mode == "history"
    local content, width = frame.barContent, frame.barWidth
    local live = fight == nil
    local now = GetTime and GetTime() or 0

    local length
    if live then
        length = CombatLog.NowLength(CombatLog.when)
    elseif type(fight.duration) == "number" then
        length = fight.duration
    end

    local meters = CombatLog.Meters(fight, CombatLog.when)
    local kinds = CombatLog.Kinds()
    -- WHICHEVER LANE IS BEING SORTED BY GOES FIRST, and that is the whole
    -- sort. See CombatLog.SortedKinds.
    local order = CombatLog.SortedKinds(kinds, CombatLog.sortBy)
    local people = CombatLog.Everyone(meters, order)

    -- AND A LANE WITH NOTHING IN IT IS NOT DRAWN.
    --
    -- Owner, 2026-08-30, offered a control for it: "von mir aus auch ein und
    -- ausblenden". A switch would work; a switch you have to remember to
    -- press does not, and four of these six are empty for most of what this
    -- addon is used for - a rogue alone sees AVOIDABLE, INTERRUPTS and
    -- DISPELS as three columns of dashes on every row. The page can see that
    -- for itself.
    --
    -- MEASURED OFF WHAT IS ACTUALLY ON THIS PAGE, both tables and the falls,
    -- so the log and History can differ - and they should: they are showing
    -- different things.
    local presses = CombatLog.PressRows(fight, now, length)
    local fell = CombatLog.FellRows(fight, now, length)
    local worn = CombatLog.DebuffRows(fight, now, length)

    -- The line is scaled to what is actually on it, not to a session the
    -- client has not rolled over yet. See CombatLog.Span.
    local span = CombatLog.Span(presses, fell, length, worn)
    local marks = CombatLog.Marks(presses, fell, span, worn)

    -- WHAT THE REPLAY BUTTON WOULD PLAY: THIS PAGE'S FIGHT.
    --
    -- Owner, 2026-08-31: "soll ein replay vom Combat sein, nicht ein link
    -- zum death log." ~~It opened the last fall on the page~~, which is the
    -- death log's subject reached sideways - and on a pull nobody died in it
    -- had nothing to open at all, which is most pulls.
    --
    -- ONE SUBJECT WITH THE TIMELINE ABOVE IT: the same two lists over the
    -- same span, so the button plays back exactly the line it sits next to.
    --
    -- THE FIGHT IS REMEMBERED, THE STORY IS BUILT ON THE CLICK. This runs
    -- four times a second for the length of a fight and the story is a copy
    -- of every press in it.
    if frame.replayButton then
        local button = frame.replayButton
        button.dkFight = fight
        button.dkLength = length
        button.dkPlayable = type(span) == "number" and span > 0
            and (#presses > 0 or #fell > 0)
        button:SetEnabled(button.dkPlayable and true or false)
    end

    -- WHAT EACH ABILITY DID, and how often you asked for it. A recorded pull
    -- carries its own copy; the live page asks the meter for its own row's
    -- spells. One shape out of both, the same as everything else here.
    local mine = (fight and fight.spells)
        or CombatLog.MySpells(meters, CombatLog.when, order, false)
    -- AND WHAT THE ENEMIES ON IT LOOK LIKE. A recorded pull carries its own
    -- map, taken while its fight was still the running one.
    local casters = (fight and type(fight.casters) == "table" and fight.casters)
        or CombatLog.Casters(CombatLog.when)
    local spellRows = CombatLog.SpellRows(mine, presses)
    -- A RECORDED PULL HAS NO SECOND LIST TO WALK - see CombatLog.ReSort.
    if fight then CombatLog.ReSort(spellRows, CombatLog.sortBy) end

    -- WHICH LANES THIS PAGE ACTUALLY HAS ANYTHING IN.
    --
    -- BOTH TABLES ARE ASKED, and that is not thoroughness - it is the whole
    -- of it. The group's table can be a single row of damage while your own
    -- abilities carry healing and damage taken as well; a column list read
    -- off the first of them would drop the lanes the second one needs, on
    -- the very page that shows both.
    local kept = {}
    local function Note(amounts)
        for key, value in pairs(amounts or {}) do
            if value ~= nil then kept[key] = true end
        end
    end
    -- YOUR OWN ROW IS THE ONLY PERSON THIS PAGE STILL DRAWS.
    --
    -- ~~Every name the meter listed.~~ OVERTAKEN 2026-08-31 with the group's
    -- table: a lane list read off rows that are no longer painted puts a
    -- column of dashes on the page for every kind SOMEBODY ELSE had something
    -- in - four of them, on a page about you. A counter goes on counting
    -- after the thing it counted moves out, and this file has paid for that
    -- once already on the empty-page test.
    local yourself = CombatLog.MineIn(people)
    if yourself then Note(yourself.amount) end
    for _, spell in ipairs(spellRows) do Note(spell.amount) end
    -- And a fall puts its killing blow in the lane it belongs to.
    for _, one in ipairs(marks) do
        if one.kind == "death" and one.amount ~= nil then
            kept.DamageTaken = true
        end
    end
    local shownKinds = {}
    for _, kind in ipairs(kinds) do
        if kept[kind.key] then shownKinds[#shownKinds + 1] = kind end
    end
    -- A TABLE WITH NO COLUMNS IS A LAYOUT WITH NO WIDTH. Nothing readable on
    -- the page yet is a moment, not a shape.
    if #shownKinds == 0 then shownKinds = kinds end
    local columns, nameW = CombatLog.Columns(shownKinds, width)
    local numbersW = math.max(0, width - nameW)

    frame.sub:SetText(yours
        and (type(length) == "number"
            and string.format("what you did  -  %s so far",
                ns.FormatTime(length))
            or "what you did, as the game fills it in")
        or CombatLog.ReportSub(fight, length))

    local y = 0
    local used = { head = 0, person = 0, event = 0, bar = 0, mark = 0 }
    -- Where each press of the log ended up, keyed the way the marks are.
    local logY = {}

    -----------------------------------------------------------------------
    -- The four things this page stacks, each one row of the scroll.
    -----------------------------------------------------------------------
    local function Heading(text, note)
        used.head = used.head + 1
        local head = frame.heads[used.head]
        if not head then
            head = CreateFrame("Frame", nil, content)
            head:SetHeight(HEAD_H)
            -- NOT UI.Eyebrow, WHICH IS 11 AGAINST A 13 ROW LABEL.
            --
            -- Owner, 2026-08-30: "combat log und what happened in order sind
            -- ja ueberschriften, die sollten von der font size her das auch
            -- widerspiegeln." He is quoting himself: UI.FS.section exists
            -- because of the same complaint about the options pages -
            -- "ueberschriften sind genauso gross wie der rest des textes" -
            -- and UI.Section says NOT UI.Eyebrow in as many words. This
            -- window went and used it anyway.
            head.label = UI.Label(head, "", UI.FS.section, C.textBody)
            head.label:SetPoint("LEFT", head, "LEFT", 0, 0)
            head.note = UI.Label(head, "", UI.FS.meta, C.textFaint)
            head.note:SetPoint("RIGHT", head, "RIGHT", 0, 0)
            head.note:SetJustifyH("RIGHT")
            frame.heads[used.head] = head
        end
        head:SetWidth(width)
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        head.label:SetText(tostring(text or ""):upper())
        head.note:SetText(note or "")
        head:Show()
        y = y + HEAD_H + 6
    end

    local function Person()
        used.person = used.person + 1
        local row = frame.people[used.person]
        if not row then
            row = BuildPerson(content, width)
            frame.people[used.person] = row
        end
        row:SetWidth(width)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        y = y + PERSON_H + PERSON_GAP
        -- EVERY BORROWED ROW IS PUT BACK THE WAY IT WAS BORN. The header row
        -- below turns pieces of this widget off, and a pooled row that
        -- remembered that would draw a person with no ground under them.
        row.track:Show()
        row.bar:Show()
        row.icon:Hide()
        -- AND NO FACE, AND ITS ICON BACK ON THE EDGE. A pooled row that kept
        -- the last mob's picture would put it in front of somebody else's
        -- ability, and one that kept the indent would leave a hole where the
        -- picture used to be.
        if row.face then
            row.face:Hide()
            row.face.dkWho, row.face.dkArt, row.face.dkNote = nil, nil, nil
        end
        -- AND NO STAMP, AND THE ICON BACK ON THE EDGE. A pooled row that
        -- kept the last one would print somebody else's second beside this
        -- ability, and one that kept the indent would leave a gap where the
        -- clock used to be.
        row.stamp:SetText("")
        row.stamp:Hide()
        row.icon:ClearAllPoints()
        row.icon:SetPoint("LEFT", row.top, "LEFT", 4, 0)
        row.note:ClearAllPoints()
        row.note:SetPoint("RIGHT", row.top, "RIGHT", -(numbersW + 8), 0)
        row.note:SetText("")
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.name:SetPoint("RIGHT", row.note, "LEFT", -8, 0)
        row.name:SetTextColor(C.text[1], C.text[2], C.text[3])
        row.hit.spellID = nil
        row.hit.label = nil
        row.hit.dkFell = nil
        -- AND ANY SORT BUTTONS IT WORE AS A HEADING, and the heading
        -- itself. This pool hands the same widget to a heading and to a
        -- person: a person carrying six invisible buttons would answer
        -- clicks meant for the row, and one still wearing the block's title
        -- would print it across its own name.
        for _, one in ipairs(row.sortHits or {}) do one:Hide() end
        row.heading:Hide()
        row:Show()
        return row
    end

    local function Cell(row, index, col)
        local cell = row.cells[index]
        if not cell then
            cell = UI.Label(row.top, "", UI.FS.meta, C.text)
            cell:SetJustifyH("RIGHT")
            cell:SetWordWrap(false)
            row.cells[index] = cell
        end
        cell:ClearAllPoints()
        cell:SetPoint("RIGHT", row.top, "RIGHT", -(col.right + 6), 0)
        cell:SetWidth(math.max(10, col.width - 8))
        cell:Show()
        return cell
    end

    -- THE COLUMN HEADS ARE THE SAME ROW WITH ITS BAR TURNED OFF. One widget
    -- and one function, because two tables share these lanes now and a lane
    -- that sat in one place on the heads and another on the rows would be two
    -- tables disagreeing about what a column means.
    local function Heads(title, note)
        local head = Person()
        head.track:Hide()
        head.bar:Hide()
        head.name:SetText("")
        if title and title ~= "" then
            head.heading:SetText(tostring(title):upper())
            head.heading:Show()
        end
        head.note:SetText(note or "")
        head.sortHits = head.sortHits or {}
        -- WHICH ONE IS DOING THE SORTING. Nothing chosen means the first
        -- column, which is the order the client hands its lists over in
        -- anyway - so the page opens on a sort rather than on "unsorted".
        local by = CombatLog.sortBy or (columns[1] and columns[1].key)
        for index, col in ipairs(columns) do
            local cell = Cell(head, index, col)
            cell:SetText(tostring(col.label or ""):upper())
            if col.key == by then
                cell:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
            else
                cell:SetTextColor(C.textFaint[1], C.textFaint[2],
                    C.textFaint[3])
            end

            -- AND A HEAD YOU CAN PRESS. Owner, 2026-08-30: "mach das
            -- sortierbare header draus. button oder so."
            --
            -- A button rather than a script on the font string, because a
            -- font string takes no clicks at all - and the hit area is grown
            -- a little past the word, because a four-letter heading is a
            -- four-letter target.
            local hit = head.sortHits[index]
            if not hit then
                hit = CreateFrame("Button", nil, head.top)
                hit:SetScript("OnClick", SortClick)
                head.sortHits[index] = hit
            end
            hit.dkSortKey = col.key
            hit:ClearAllPoints()
            hit:SetPoint("TOPLEFT", cell, "TOPLEFT", -6, 6)
            hit:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 6, -6)
            hit:Show()
        end
        for index = #columns + 1, #head.cells do head.cells[index]:Hide() end
        for index = #columns + 1, #head.sortHits do
            head.sortHits[index]:Hide()
        end
        return head
    end

    -- WHO WAS AT THE OTHER END OF A ROW, drawn by the death log's own
    -- painter out of the death log's own art.
    --
    -- Owner, 2026-08-30, on the incoming damage: "vor den dmg icons brauchen
    -- wir die avatar bilder von gegner oder selbst mit hover links, damit man
    -- auch sieht, von wem hab ich den schaden bekommen" - and, when the data
    -- turned up: "muss ja gehen, geht ja beim death log auch ... es fehlt nur
    -- die mechanik."
    --
    -- The NAME is the answer and it is always there; the face is the picture
    -- on top of it and needs a creature id, which only exists for a mob
    -- somebody hit back. No id, no picture, and the name still says who.
    local function Who(row, who)
        if not (who and who.name) then return false end
        local face = FaceOn(row)
        if not face then return false end
        local creature = casters and casters[who.name] or nil
        local art = creature and { creatureID = creature } or nil
        local drew = ns.Death.PaintFace and ns.Death.PaintFace(face, art)
        face.dkWho, face.dkArt, face.dkNote = who.name, art, who.rank
        if drew then
            face:Show()
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT", face, "RIGHT", 4, 0)
        end
        return drew and true or false
    end

    -- WHICH LANE A ROW IS ABOUT, and therefore what colour its bar wears and
    -- what that bar is measured against.
    --
    -- Owner, 2026-08-30: "bei heal - faerbe die leiste also den amount gruen
    -- wie beim eigenen schaden dieses orange. bei dmg income rot. damit wir
    -- die 3 sachen unterscheiden koennen." The NUMBERS have worn those three
    -- colours since the table was built; the bar behind them was orange
    -- whatever the row was about - and worse, a row that only healed had no
    -- bar at all, because it was being measured against a damage column it
    -- has nothing in.
    --
    -- The first column the row has anything in wins, which is the order the
    -- columns already stand in. Nothing is compared: an amount may be
    -- withheld, and comparing those is the forbidden operation.
    local function Lane(amounts)
        for _, col in ipairs(columns) do
            if amounts and amounts[col.key] ~= nil then
                local tone = C.accent
                if col.tone == "in" then tone = C.harm
                elseif col.tone == "heal" then tone = C.inUse end
                return col.key, tone
            end
        end
        return nil, C.accent
    end

    -- ONE ROW'S SIX NUMBERS. Shared for the same reason the heads are.
    local function Numbers(row, amounts)
        for index, col in ipairs(columns) do
            local cell = Cell(row, index, col)
            local value = amounts and amounts[col.key]
            if value == nil then
                -- ABSENT IS NOT ZERO. Nobody healed on a damage page and "0"
                -- would be a measurement this window never took.
                cell:SetText("-")
                cell:SetTextColor(C.textGhost[1], C.textGhost[2],
                    C.textGhost[3])
            else
                local tone = C.text
                if col.tone == "in" then tone = C.harm
                elseif col.tone == "heal" then tone = C.inUse end
                if not CombatLog.SayAmount(cell, value) then
                    cell:SetText("?")
                    tone = C.textGhost
                end
                cell:SetTextColor(tone[1], tone[2], tone[3])
            end
        end
        for index = #columns + 1, #row.cells do row.cells[index]:Hide() end
    end

    local function Bar()
        used.bar = used.bar + 1
        local row = frame.bars[used.bar]
        if not row then
            row = BuildBar(content, width)
            frame.bars[used.bar] = row
        end
        row:SetWidth(width)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        y = y + BAR_H + BAR_GAP
        row.bar:Hide()
        row.share:SetText("")
        -- BORROWED ROWS GIVE THE FALL BACK. A press wearing the last fall's
        -- entry would show the boss that killed somebody else on hover.
        row.hit.dkFell = nil
        row:Show()
        return row
    end

    -----------------------------------------------------------------------
    -- 1. THE FIGHT, END TO END
    -----------------------------------------------------------------------
    local band = frame.band
    if band and #marks > 0 then
        -- WHAT THE LINE COVERS, said out loud whenever it is not the whole
        -- fight. A scale that quietly means something else is worse than no
        -- scale at all.
        local note
        if #marks > MARKS_SHOWN then
            note = string.format("%d of %d marks", MARKS_SHOWN, #marks)
        elseif type(length) == "number" and type(span) == "number"
            and span < length - 1 then
            note = string.format("the last %s of %s", ns.FormatTime(span),
                ns.FormatTime(length))
        end
        Heading("The fight, end to end", note)
        band:SetWidth(width)
        band:ClearAllPoints()
        band:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        band.endLabel:SetText(ns.FormatTime(span))
        band:Show()

        local drawn = math.min(#marks, MARKS_SHOWN)
        local slice = {}
        for index = 1, drawn do slice[index] = marks[index] end
        local xs, asIcons = CombatLog.Lay(slice, width, MARK_PIC)

        for index = 1, drawn do
            local mark = marks[index]
            used.mark = used.mark + 1
            local pin = band.marks[used.mark]
            if not pin then
                pin = CreateFrame("Frame", nil, band)
                pin:EnableMouse(true)
                pin.fill = pin:CreateTexture(nil, "ARTWORK")
                pin.fill:SetAllPoints(pin)
                pin:SetScript("OnEnter", MarkEnter)
                pin:SetScript("OnLeave", MarkLeave)
                pin:SetScript("OnMouseDown", MarkClick)
                band.marks[used.mark] = pin
            end
            pin.dkScroll = frame.barScroll

            local dead = mark.kind == "death"
            local picture = nil
            if asIcons and not dead then
                picture = ns.SpellTexture(mark.spellID) or 135274
            end

            local w, h, top, tone
            if dead then
                w, h, top, tone = DEATH_W, 12, 24, C.harm
            elseif picture then
                -- A DEFENSIVE STANDS TALLER, icon or not: it is the one press
                -- on the line somebody goes looking for.
                w, h = MARK_PIC, MARK_PIC
                top = mark.defensive and 2 or 6
                tone = nil
            elseif mark.defensive then
                w, h, top, tone = MARK_W, 20, 2, C.accent
            else
                w, h, top, tone = MARK_W, 14, 8, C.textDim
            end

            pin:SetSize(w, h)
            pin:ClearAllPoints()
            pin:SetPoint("TOPLEFT", band, "TOPLEFT", xs[index] or 0, -top)
            if picture then
                pin.fill:SetTexture(picture)
                pin.fill:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                if mark.defensive then
                    pin.fill:SetVertexColor(1, 1, 1, 1)
                else
                    pin.fill:SetVertexColor(0.82, 0.82, 0.82, 1)
                end
            else
                pin.fill:SetTexCoord(0, 1, 0, 1)
                pin.fill:SetVertexColor(1, 1, 1, 1)
                pin.fill:SetColorTexture(tone[1], tone[2], tone[3], 1)
            end

            pin.spellID = mark.spellID
            pin.label = dead
                and ("Went down" .. (mark.name and (" - " .. mark.name) or ""))
                or nil
            pin.stamp = string.format("%s into the fight",
                ns.FormatTime(math.max(0, (span or 0) - mark.ago)))
            -- SET ON EVERY PIN, nil included. A shared pool hands the last
            -- fall to whichever press borrows the widget next, and the
            -- symptom is a replay opening on somebody else's death.
            pin.dkFell = mark.fell
            pin.press = mark.press
            -- Filled in once the log below is laid out; a mark that has no
            -- row down there is not clickable and says so by having none.
            pin.scrollTo = nil
            pin:Show()
        end
        y = y + TIME_H + BLOCK_GAP
    end
    if band then
        for index = used.mark + 1, #band.marks do band.marks[index]:Hide() end
        if #marks == 0 then band:Hide() end
    end

    -----------------------------------------------------------------------
    -- ~~2. EVERYONE, EVERYTHING~~  REMOVED 2026-08-31
    --
    -- One row per person with all six kinds across it, and it was the block
    -- the client's own meter cannot do at all. Owner, in front of it with
    -- three names in it - so not the single-row version he had already asked
    -- to lose: "everyone everything kann raus."
    --
    -- What he wanted in its place is on the same page and one line further
    -- down: "eigener total dmg fehlt". This window is personal before it is a
    -- raid tool, and the group's table was answering a question the group
    -- death log answers better. The TOTAL line under the next heading is what
    -- is left of it, and it now carries the share and the per-second that
    -- used to live here.
    -----------------------------------------------------------------------

    -----------------------------------------------------------------------
    -- 2. WHAT YOU DID, ONE ROW PER ABILITY
    --
    -- Owner, 2026-08-29, drawing six arrows from the column heads down onto
    -- the press list: "ich moechte sehen was mache ich an schaden, was bekomme
    -- ich, heal etc. alles in einer liste."
    --
    -- The numbers come from the meter's second, source-scoped call; how often
    -- you PRESSED each one comes from this addon and from nowhere else. A
    -- spell that did damage and was never pressed is a tick or a proc; one
    -- that was pressed and did nothing is a defensive. Both are on the page,
    -- and neither is answerable from one source alone.
    -----------------------------------------------------------------------
    -- NOT ON HISTORY. Owner, 2026-08-30: "history ist eine timeline und
    -- nicht 3 x mal das gedrueckt etc. also das muss eine chronologische
    -- abfolge sein ... das ziel ist, das ich bei der history nachvollziehen
    -- kann, was wann im kampf passiert ist."
    --
    -- A table that says a spell was pressed three times has thrown away the
    -- three moments, which is the only thing History is for. The six other
    -- pages are where the totals live.
    if #spellRows > 0 and #columns > 0 and not yours then
        local note
        if mine and type(mine.blind) == "number" and mine.blind > 0 then
            note = string.format("%d the game would not name", mine.blind)
        end
        -- Owner, 2026-08-30: "nennen um what u did in - combat log um."
        Heads("Combat log", note)

        -- YOUR OWN LINE, ON TOP OF YOUR OWN TABLE.
        --
        -- Owner, 2026-08-30, drawing an arrow from his single "everyone" row
        -- down to the first ability: "pack diese BAR, einfach ueber die erste
        -- DMG leiste, und NENNE die TOTAL. Gib der einfach ein klein wenig
        -- space." It had a heading of its own above a table of one line,
        -- which is a second table for a single row; here it is what it
        -- actually is - the sum of everything under it.
        --
        -- Named rather than found by position: Everyone ranks you 0 so you
        -- come first, but "first" and "you" are two different facts and only
        -- one of them is the one this row claims.
        -- Found by CombatLog.MineIn, which is the meter's own answer to
        -- "which of these is the player" - not by position. Ranking you 0
        -- puts you first, but "first" and "you" are two different facts and
        -- only one of them is what this row claims.
        if yourself then
            local row = Person()
            local lane, tone = Lane(yourself.amount)
            row.bar:SetStatusBarColor(tone[1], tone[2], tone[3], 0.28)
            row.bar:SetShown(lane ~= nil and CombatLog.Fill(row.bar,
                yourself.amount[lane], people.peak[lane]))
            -- AND IT WEARS YOUR SPEC.
            --
            -- The group's table was the only thing drawing this, and taking
            -- it out left the client's specIconID read with nobody to hand
            -- it to - a field read for nothing is a field that quietly stops
            -- being right. It belongs here anyway: this is your row, and two
            -- rogues look identical until one of them is Subtlety.
            --
            -- specIconID IS A TEXTURE, NOT A SPEC. UI.SpecIcon takes a
            -- SPECIALIZATION id - 260, Outlaw - and looks its art up; this
            -- field is the art itself. Handed to the wrong one of the two it
            -- falls through to the class sheet in silence, which is exactly
            -- what the old code drew, so it would have looked like it worked.
            if type(yourself.spec) == "number" and yourself.spec > 0 then
                row.icon:SetTexture(yourself.spec)
                row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                row.icon:Show()
            elseif ns.CanCompute(yourself.class)
                and type(yourself.class) == "string" then
                UI.PaintSpecIcon(row.icon, nil, yourself.class)
            else
                row.icon:Hide()
            end
            row.name:SetText("Total")
            row.name:SetTextColor(C.accent[1], C.accent[2], C.accent[3])

            -- ITS SHARE OF THE WHOLE, AND PER SECOND - the two facts the
            -- group's table carried before it was removed. They are why the
            -- bar behind this line has a length at all: it is measured
            -- against the top of the raid, and without the percentage beside
            -- it a half-long bar has nothing to be half OF.
            --
            -- Per second is the CLIENT'S, never divided here. It knows how
            -- long its own session ran and we would be dividing by a length
            -- we asked a second time for.
            local bits = {}
            local share = CombatLog.Share(lane and yourself.amount[lane],
                lane and people.total[lane])
            if share then
                bits[#bits + 1] = string.format("%d%%",
                    math.floor(share * 100 + 0.5))
            end
            local rate = yourself.rate and lane and yourself.rate[lane]
            if type(rate) == "number" and rate > 0 then
                bits[#bits + 1] = ns.ShortNumber(rate) .. "/s"
            end
            row.note:SetText(table.concat(bits, "  -  "))
            row.hit.spellID = nil
            Numbers(row, yourself.amount)
            -- The little bit of space he asked for, so the sum reads as a
            -- line above the table rather than as its first entry.
            y = y + 8
        end

        local lead = columns[1] and columns[1].key or nil
        -- NO TRAILING `or nil`. `and` hands back its last operand untested, so
        -- this chain already yields nil when a link is missing - but `or`
        -- BOOLEAN-TESTS what came out, and the thing that comes out is a meter
        -- amount the client may be withholding. Written an hour before the
        -- sweep that found it; CombatLog.Peak has always done the same job
        -- correctly with ns.CanDisplay.
        local most
        if mine and mine.rows and mine.rows[1] and mine.rows[1].amount then
            most = mine.rows[1].amount[lead]
        end

        for _, spell in ipairs(spellRows) do
            local row = Person()

            local lane, tone = Lane(spell.amount)
            row.bar:SetStatusBarColor(tone[1], tone[2], tone[3], 0.28)
            row.bar:SetShown(lane ~= nil and CombatLog.Fill(row.bar,
                spell.amount[lane],
                (mine and mine.peak and mine.peak[lane]) or most))

            row.icon:SetTexture(ns.SpellTexture(spell.spellID) or 135274)
            row.icon:Show()
            row.name:SetText(ns.SpellName(spell.spellID)
                or ("Spell " .. tostring(spell.spellID)))
            row.hit.spellID = spell.spellID

            -- WHO IT WAS, AND THE HALF THAT IS OURS.
            --
            -- A row with no press count was never pressed - a tick, a pet, a
            -- proc - and saying so is the point. But an ability that HIT you
            -- was never going to be pressed, and "not pressed" on one of
            -- those was answering a question nobody asked while leaving the
            -- one they did ask - who did that - unanswered.
            local who = lane and spell.who and spell.who[lane] or nil
            Who(row, who)
            local bits = {}
            if who and who.name then bits[#bits + 1] = who.name end
            if type(spell.times) == "number" and spell.times > 0 then
                if type(spell.last) == "number" then
                    bits[#bits + 1] = string.format("%dx  -  %s ago",
                        spell.times, ns.FormatTime(spell.last))
                else
                    bits[#bits + 1] = string.format("%dx", spell.times)
                end
            elseif #bits == 0 then
                bits[#bits + 1] = "not pressed"
            end
            row.note:SetText(table.concat(bits, "  -  "))

            Numbers(row, spell.amount)
        end
        y = y + BLOCK_GAP
    end

    -----------------------------------------------------------------------
    -- 3. WHO WENT DOWN, and the last one hit by hit
    -----------------------------------------------------------------------
    if #fell > 0 and not yours then
        Heading("Who went down", string.format("%d in this pull", #fell))
        for _, one in ipairs(fell) do
            local row = Bar()
            row.hit.dkFell = one
            row.spellID = one.spellID
            row.icon:SetTexture((one.spellID and ns.SpellTexture(one.spellID))
                or 135274)
            row.icon:Show()
            row.name:SetText(one.name or "something not readable")
            row.name:SetTextColor(C.text[1], C.text[2], C.text[3])
            -- ns.ShortNumber DIVIDES, so this needs the full guard and not
            -- a truth test: `if one.amount then` is itself the raise on a
            -- withheld one, and type() would have said "number" anyway.
            if ns.CanCompute(one.amount) and type(one.amount) == "number" then
                row.amount:SetText(ns.ShortNumber(one.amount))
                row.amount:SetTextColor(C.harm[1], C.harm[2], C.harm[3])
            else
                row.amount:SetText("")
            end
        end
        y = y + 6

        -- AND THE WHOLE FALL, DRAWN BY THE DEATH LOG'S OWN PAINTER. Not a
        -- second version of it: this is the same widget the death window
        -- stacks, health bar and all, and it says so by being called rather
        -- than copied.
        local full = CombatLog.FullDeath(fell[#fell])
        local events = full and type(full.events) == "table" and full.events
            or nil
        if events and #events > 0 and ns.Death.BuildEventRow then
            if not frame.eventHead and ns.Death.BuildEventHead then
                frame.eventHead = ns.Death.BuildEventHead(content, width,
                    "What hit you")
            end
            if frame.eventHead then
                frame.eventHead:SetWidth(width)
                frame.eventHead:ClearAllPoints()
                frame.eventHead:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                frame.eventHead:Show()
                y = y + 20
            end

            local rowH = ns.Death.EVENT_ROW_H or 30
            local first = math.max(1, #events - FELL_SHOWN + 1)
            for index = first, #events do
                used.event = used.event + 1
                local row = frame.events[used.event]
                if not row then
                    row = ns.Death.BuildEventRow(content, width)
                    frame.events[used.event] = row
                end
                row:SetWidth(width)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                y = y + rowH
                ns.Death.PaintEventRow(row, events[index], full.maxHP, events)
                row:Show()
            end
            if first > 1 then
                Heading("", string.format("and %d earlier hits - the death "
                    .. "log has the whole fall", first - 1))
            end
        end
        y = y + BLOCK_GAP
    end

    -----------------------------------------------------------------------
    -- 4. THE LOG ITSELF, IN ORDER
    --
    -- Owner, 2026-08-29: "wir sollten die liste auch scrollen koennen, von
    -- fight start zum ende." So it reads OLDEST FIRST and it is timed from the
    -- start of the stretch rather than backwards from now - "1:12" is a place
    -- in the fight, "1:12 ago" is a place in your afternoon.
    --
    -- The cap drops the OLDEST rows, which is the one place that hurts, so it
    -- says how many rather than trailing off. The store behind it reaches five
    -- hundred presses now; see CASTS_CAP.
    -----------------------------------------------------------------------
    --
    -- OUT OF THE SAME LIST THE BAND ABOVE IS DRAWN FROM, and that is the
    -- whole point rather than a saving. The line and this are one sequence
    -- seen from two ends - the line is where it happened, this is what it
    -- was - so a fall that shows on one cannot be missing from the other,
    -- and the order can never drift apart. It also puts the DEATHS in here,
    -- which a list of presses could not: "was wann im kampf passiert ist" is
    -- not answered by a page that leaves out the part where somebody died.
    --
    -- CombatLog.Marks already merged and ordered them, oldest first.
    -- HISTORY ONLY. Owner, 2026-08-30, in front of the whole report: "das
    -- what happened in order kann im combat log raus." The log page is the
    -- totals; this page is the sequence.
    if yours and #marks > 0 and #columns > 0 then
        local shown = math.min(#marks, LOG_SHOWN)
        local hidden = #marks - shown

        -- WHAT THE NUMBERS ARE, SAID ON THE ROWS RATHER THAN OVER THEM.
        --
        -- The game does not publish what a SINGLE press did - the meter
        -- keeps one running total per ability and nothing per moment, and
        -- the event that would carry it cannot be registered at all on 12.1.
        -- So the lanes here are the ability's total for the whole fight, and
        -- seven rows each showing 141.2k would read as seven times that
        -- unless something says otherwise.
        --
        -- ~~A line over the table saying so.~~ Owner, 2026-08-30: "the
        -- numbers are each ... etc die leiste kann raus." It is said on
        -- every row instead, as "3 of 7", which is where somebody reading
        -- the row actually is.
        local bits = {}
        if hidden > 0 then
            bits[#bits + 1] = string.format("%d earlier not drawn", hidden)
        end
        -- Owner, 2026-08-30: "und nenne what happened in order in history
        -- um." The chip above says History and so does the block - one name
        -- for one thing.
        Heads("History", #bits > 0 and table.concat(bits, "  -  ") or nil)

        -- WHAT EACH ABILITY DID, reachable by id. Built here rather than
        -- taken off `mine`, because a recorded pull carries its own copy of
        -- that table and a copy that came back out of a saved file is not
        -- something to assume the shape of.
        local byID = {}
        for _, one in ipairs(spellRows) do byID[one.spellID] = one end

        -- HOW OFTEN EACH ONE WAS PRESSED, and which of those this row is.
        local howMany, sofar = {}, {}
        for _, one in ipairs(marks) do
            if one.kind ~= "death" and one.spellID ~= nil then
                howMany[one.spellID] = (howMany[one.spellID] or 0) + 1
            end
        end

        -- The cap drops the OLDEST, which is the one place it hurts, so the
        -- heading says how many rather than trailing off.
        for index = #marks - shown + 1, #marks do
            local mark = marks[index]
            -- WHERE THIS ROW LANDED, so a click on the line can bring it to
            -- the top. Read before Person(), which moves the cursor on.
            -- Keyed by the press the mark carries, because that is the key
            -- the pin up there was given.
            if mark.press then logY[mark.press] = y end

            local row = Person()
            local dead = mark.kind == "death"
            -- AND WHAT WAS PUT ON YOU. Owner, 2026-08-31: "oder wann ich
            -- debuffs oder so bekommen habe?" - and this is the half of
            -- "what happened to me" the client answers in full, because
            -- auras are not the combat log.
            local worn = mark.kind == "debuff"

            -- WHAT THIS ROW IS WORTH. A fall carries the one number on this
            -- page that really belongs to its own moment: the blow that
            -- killed you, out of the death recap, which is timestamped and
            -- readable even when the meter is withholding everything else.
            -- A DEBUFF HAS NO AMOUNT AT ALL and is not given one: what it
            -- has is a LENGTH, and that is drawn instead of a number.
            local amounts
            if dead then
                amounts = { DamageTaken = mark.amount }
            elseif not worn then
                local known = byID[mark.spellID]
                amounts = known and known.amount or nil
            end

            row.icon:SetTexture((mark.spellID
                and ns.SpellTexture(mark.spellID)) or 135274)
            row.icon:Show()

            -- EVERY BRANCH SETS THE COLOUR AND THE TOOLTIP. These rows come
            -- out of a shared pool: a red name handed on to a press would
            -- say somebody died where nobody did, and a spell id left behind
            -- would put the wrong tooltip on a fall.
            if dead then
                row.name:SetText("Went down"
                    .. (mark.name and ("  -  " .. mark.name) or ""))
                row.name:SetTextColor(C.harm[1], C.harm[2], C.harm[3])
                row.hit.spellID = nil
                row.hit.dkFell = mark
            elseif worn then
                -- ITS OWN NAME AND ITS OWN TOOLTIP, like every other
                -- ability on this page. The word in front is what says it
                -- was done TO you rather than BY you - the icon alone
                -- cannot, a debuff icon looks like any other spell icon.
                row.name:SetText("Debuff  -  " .. (mark.name
                    or ns.SpellName(mark.spellID)
                    or ("Spell " .. tostring(mark.spellID))))
                row.name:SetTextColor(C.text[1], C.text[2], C.text[3])
                row.hit.spellID = mark.spellID
                row.hit.dkFell = nil
            else
                row.name:SetText(ns.SpellName(mark.spellID)
                    or ("Spell " .. tostring(mark.spellID)))
                row.name:SetTextColor(C.text[1], C.text[2], C.text[3])
                row.hit.spellID = mark.spellID
            end

            -- WHEN, DOWN THE LEFT EDGE - and WHICH PRESS of that ability
            -- this one is, which stays beside the numbers because it is
            -- about the amounts and not about the clock.
            local when = type(mark.ago) == "number"
                and ns.FormatTime(math.max(0, (span or 0) - mark.ago)) or ""
            row.stamp:SetText(when)
            row.stamp:Show()
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT", row.stamp, "RIGHT", 8, 0)

            local note = ""
            if worn then
                -- HOW LONG YOU WORE IT, which is the one number it has. One
                -- still on you when the fight ended says so rather than
                -- being given an end it never had.
                note = mark.stillOn and "still on you"
                    or (type(mark.held) == "number"
                        and string.format("%.1fs on you", mark.held)
                        or "on you")
            elseif not dead and mark.spellID ~= nil then
                local many = howMany[mark.spellID] or 1
                sofar[mark.spellID] = (sofar[mark.spellID] or 0) + 1
                if many > 1 then
                    note = string.format("%d of %d", sofar[mark.spellID],
                        many)
                end
            end
            row.note:SetText(note)

            -- AND THE BAR BEHIND IT, the same as on the other page.
            --
            -- ~~No bar: a bar is a share of the biggest, and two rows of the
            -- same ability would draw the same length twice.~~ WRONG, and
            -- the owner said so on 2026-08-30: "bei der dmg table fehlen
            -- wieder die background colors wie im combat log tab." Two rows
            -- of one ability SHOULD look the same - they are the same
            -- ability - and the length is what makes a column of numbers
            -- readable at a glance. The colour is the lane, which is the
            -- other half of what he asked for.
            if worn then
                -- A DEBUFF'S BAR IS ITS LENGTH, not an amount: it is a
                -- stretch of time and the rows around it are moments. The
                -- share is of the FIGHT, so a curse you wore for half the
                -- pull draws half the row - which is the fact somebody
                -- opening this page is looking for.
                row.bar:SetStatusBarColor(C.harm[1], C.harm[2], C.harm[3],
                    0.22)
                row.bar:SetShown(CombatLog.Fill(row.bar,
                    mark.stillOn and span or mark.held, span))
                Numbers(row, nil)
            else
                local lane, tone = Lane(amounts)
                local most
                if dead then
                    most = people.peak and people.peak[lane]
                else
                    most = mine and mine.peak and mine.peak[lane]
                end
                row.bar:SetStatusBarColor(tone[1], tone[2], tone[3], 0.28)
                row.bar:SetShown(lane ~= nil
                    and CombatLog.Fill(row.bar, amounts[lane], most))
                Numbers(row, amounts)
            end
        end
        y = y + BLOCK_GAP
    end

    -----------------------------------------------------------------------
    -- 6. AND WHAT YOU STILL HAVE, on History and only while it is live
    --
    -- Three faces rather than two: ready is green, cooling is plain, and NOT
    -- KNOWN is neither - an estimate that has never seen the spell cast must
    -- not read like a promise that it is up.
    --
    -- A recorded pull never stored which cooldowns were up, and answering
    -- that from today about a fight that is over would be an invention.
    -----------------------------------------------------------------------
    if yours and not fight then
        local ready = CombatLog.Ready(now)
        if #ready > 0 then
            Heading("What you still have", string.format("%d watched",
                #ready))
            for _, entry in ipairs(ready) do
                local row = Bar()
                row.spellID = entry.spellID
                row.icon:SetTexture(ns.SpellTexture(entry.spellID) or 135274)
                row.icon:Show()
                row.name:SetText(entry.name)
                if entry.remaining == 0 then
                    row.name:SetTextColor(C.inUse[1], C.inUse[2], C.inUse[3])
                elseif type(entry.remaining) == "number" then
                    row.name:SetTextColor(C.textDim[1], C.textDim[2],
                        C.textDim[3])
                else
                    row.name:SetTextColor(C.textFaint[1], C.textFaint[2],
                        C.textFaint[3])
                end
                row.amount:SetTextColor(C.textFaint[1], C.textFaint[2],
                    C.textFaint[3])
                row.amount:SetText(CombatLog.ReadyLine(entry))
            end
            y = y + BLOCK_GAP
        end
    end

    -----------------------------------------------------------------------
    -- AND WHEN THERE IS NOTHING AT ALL
    -----------------------------------------------------------------------
    frame.pageNote:ClearAllPoints()
    frame.pageNote:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -4)
    frame.pageNote:SetPoint("RIGHT", content, "RIGHT", -4, 0)
    frame.pageNote:SetWordWrap(true)
    -- NOTHING AT ALL MEANS NOTHING WAS DRAWN, and that has to be asked of
    -- everything this painter can draw rather than of one pool.
    --
    -- It used to read `used.head == 0` - the count of standalone heading
    -- FRAMES - and that stopped meaning "the page is empty" the moment a
    -- block's title moved onto its column-head row on 2026-08-30. Every full
    -- page then reported itself empty and printed "Nothing yet" across its
    -- own first heading, which is what the owner's screenshot showed.
    --
    -- The lesson is the one this addon already has about removals: a counter
    -- that stood for something keeps standing for it in the reader's head
    -- long after the thing it counted moved.
    local drew = used.head + used.person + used.bar + used.event
    if drew == 0 then
        local _, said = CombatLog.Read(CombatLog.when, "DamageDone")
        frame.pageNote:SetText(live
            and (said or "Nothing yet. The game fills this in as the fight "
                .. "goes on.")
            or "Nothing was kept for that pull.")
        frame.pageNote:Show()
        y = y + 40
    else
        frame.pageNote:Hide()
    end

    -- AND NOW THE LINE KNOWS WHERE THE LOG IS. Done here rather than in the
    -- mark loop because the log is drawn after the line, and a mark cannot
    -- point at a row that has not been placed yet.
    if band then
        for _, pin in ipairs(band.marks) do
            if pin.press then pin.scrollTo = logY[pin.press] end
        end
    end

    -- A MARK PRESSED ON THE OTHER PAGE ASKED FOR A ROW THAT DID NOT EXIST
    -- THEN. It does now, so this is where the jump happens - after the log
    -- has been laid out and before anybody has seen the page.
    local wanted = frame.pendingPress
    frame.pendingPress = nil
    if wanted and logY[wanted] and frame.barScroll then
        frame.barScroll.ScrollTo(logY[wanted])
    end

    for index = used.bar + 1, #frame.bars do frame.bars[index]:Hide() end
    for index = used.head + 1, #frame.heads do frame.heads[index]:Hide() end
    for index = used.person + 1, #frame.people do
        frame.people[index]:Hide()
    end
    for index = used.event + 1, #frame.events do frame.events[index]:Hide() end
    if used.event == 0 and frame.eventHead then frame.eventHead:Hide() end
    content:SetHeight(math.max(1, y + 24))

    -- THE FOOT COUNTS NAMES, because the page is a table of them now. The
    -- total behind it is only printed when every amount that went into it was
    -- readable - a sum with a hole in it makes every row above it wrong by an
    -- amount nobody can see.
    local lead = columns[1] and columns[1].key or nil
    local sum = lead and people.total[lead] or nil
    if #people.rows == 0 then
        frame.foot:SetText("")
    elseif type(sum) == "number" then
        frame.foot:SetText(string.format("%d %s  -  %s %s in total",
            #people.rows, #people.rows == 1 and "name" or "names",
            ns.ShortNumber(sum),
            string.lower(columns[1].label or "")))
    else
        frame.foot:SetText(string.format("%d %s", #people.rows,
            #people.rows == 1 and "name" or "names"))
    end
end

function CombatLog.PaintPage()
    if not frame then return end
    local C = ns.UI.C
    local UI = ns.UI

    -- WHAT IS BEING READ. A key that is no longer in the log falls back to
    -- the live page rather than to whoever took its place - and the fallback
    -- CLEARS the key, or the column would keep an accent bar on nothing.
    local fight
    if CombatLog.showing ~= nil then
        -- A NUMBER IS ONE PULL, A STRING IS A WHOLE RUN OR A WHOLE BOSS.
        -- Two shapes on one field on purpose: what is being read is a single
        -- fact, and a second field for it is a second thing that could
        -- disagree with the column.
        if type(CombatLog.showing) == "string" then
            fight = CombatLog.Combined(CombatLog.log, CombatLog.showing)
        else
            fight = CombatLog.Pick(CombatLog.log, CombatLog.showing)
        end
        if not fight then CombatLog.showing = nil end
    end

    frame.kindChips:ClearAllPoints()
    frame.kindChips:SetPoint("TOPLEFT", frame.page, "TOPLEFT", 0, 0)
    frame.barHost:ClearAllPoints()
    frame.barHost:SetPoint("TOPLEFT", frame.kindChips, "BOTTOMLEFT", 0, -10)
    frame.barHost:SetPoint("BOTTOMRIGHT", frame.page, "BOTTOMRIGHT", 0, 22)

    frame.kindChips.Refresh()

    frame.title:SetText(CombatLog.PageTitle(fight))
    CombatLog.PaintHeadFace(fight)

    -- THE REPORT IS ITS OWN PAINTER, and it leaves through the same door.
    --
    -- History goes through the SAME painter rather than a second one. Owner,
    -- 2026-08-29: "bei der history oder live, muesste das genau so aussehen,
    -- nur eben mit live zahlen." Two painters drawing the same table is two
    -- tables that will drift; one painter with a narrower scope is one.
    if CombatLog.kind == CombatLog.EVERYTHING then
        CombatLog.PaintReport(fight)
        return
    end
    if CombatLog.kind == CombatLog.PRESSED then
        CombatLog.PaintReport(fight, "history")
        return
    end
    -- NOTHING ELSE REACHES THIS FAR.
    --
    -- ~~A third page: one meter kind at a time, with each bar's share of the
    -- whole.~~ REMOVED 2026-08-30 with the six chips that were its only way
    -- in - owner: "dann koennen wir oben die tabs raushauen und haben nur
    -- noch 2." Every one of those six was a narrower view of a page that was
    -- already open, and the column heads sort the wide one now.
    --
    -- 140 lines went with them. What is worth remembering is that the page
    -- was UNREACHABLE for a while before it was deleted, and three mutations
    -- proved it: they broke that code and every light on this desk stayed
    -- green. Reachability is not something a count of tests can see.
    CombatLog.PaintReport(fight)
end

function CombatLog:Refresh()
    if not (frame and frame:IsShown()) then return end
    CombatLog.PaintPage()
    CombatLog.PaintSideList()
end

function CombatLog:Show()
    if not ns.UI then return end
    if not CombatLog:Create() then return end
    frame:Show()
    frame:Raise()
    CombatLog:Refresh()
end

function CombatLog:Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
        return
    end
    CombatLog:Show()
end

-- Same reason as the other two windows: a check cannot press what it cannot
-- reach.
function CombatLog.Window()
    return frame
end

---------------------------------------------------------------------------
-- THE CLIENT PUSHES, WE DO NOT POLL
--
-- Three events instead of a timer, and they are only acted on while the
-- window is open. A page nobody is looking at, repainting on every tick of a
-- raid boss, is the kind of cost that never shows up in a screenshot.
---------------------------------------------------------------------------
do
    local watcher = CreateFrame("Frame")
    for _, event in ipairs({
        "DAMAGE_METER_CURRENT_SESSION_UPDATED",
        "DAMAGE_METER_COMBAT_SESSION_UPDATED",
        "DAMAGE_METER_RESET",
    }) do
        -- An event a build has never heard of is refused at registration,
        -- and this file has to load on 12.0 as well as on 12.1.
        pcall(watcher.RegisterEvent, watcher, event)
    end
    -- COALESCED, because the page grew. The log runs to three hundred rows
    -- now and the meter pushes several times a second in a raid; one repaint
    -- per event would be the same page drawn four times for one reading.
    -- Named at file scope so there is one timer callback, not one per event.
    local pending
    local function Flush()
        pending = nil
        if frame and frame:IsShown() then CombatLog:Refresh() end
    end

    watcher:SetScript("OnEvent", function()
        if not (frame and frame:IsShown()) then return end
        if not (C_Timer and C_Timer.After) then
            CombatLog:Refresh()
            return
        end
        if pending then return end
        pending = true
        C_Timer.After(0.25, Flush)
    end)
end

---------------------------------------------------------------------------
-- THE THIRD ICON
--
-- Owner, 2026-08-29: "mit einem neuen icon neben dem death log. und alle 3
-- icons sind jetzt immer da, nicht erst nach tod."
--
-- IT DOCKS TO WHICHEVER OF THE TWO IN FRONT OF IT IS ON SCREEN, rather than
-- to a fixed one. Any of the three can be switched off, and a chain that
-- always hangs off the second would leave this one floating 34 pixels from
-- nothing the moment that one went away.
--
-- Its mark is drawn rather than borrowed: three bars, longest at the top -
-- which is what a meter looks like from across the room, and what no
-- Blizzard icon file says in one glance.
---------------------------------------------------------------------------
local ICON_BARS = { { w = 16, y = 5 }, { w = 12, y = 0 }, { w = 7, y = -5 } }

local function BuildIcon()
    local C = ns.UI.C

    icon = CreateFrame("Button", "ZwoelfStuffCombatLogIcon", UIParent)
    icon:SetSize(30, 30)
    icon:SetFrameStrata("MEDIUM")
    icon:RegisterForDrag("LeftButton")
    icon:Hide()

    local bg = icon:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(icon)
    bg:SetColorTexture(C.windowBg[1], C.windowBg[2], C.windowBg[3], 0.85)

    local edge = ns.CreateBorder(icon, 1, "BORDER")
    edge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)

    for index, spot in ipairs(ICON_BARS) do
        local bar = icon:CreateTexture(nil, "ARTWORK")
        bar:SetSize(spot.w, 3)
        bar:SetPoint("LEFT", icon, "LEFT", 6, spot.y)
        local shade = 1 - (index - 1) * 0.22
        bar:SetColorTexture(C.accent[1] * shade, C.accent[2] * shade,
            C.accent[3] * shade, 1)
    end

    icon:SetScript("OnClick", function() CombatLog:Toggle() end)

    -- ONE SAVED POSITION FOR THE CLUSTER, and whoever is leftmost sits on
    -- it. Docked, this drags the pair by the icon that owns the position;
    -- standing alone it drags itself and writes the same position back.
    icon:SetScript("OnDragStart", function(self)
        if ns.Death.IconLocked() then return end
        if self.docked then
            ns.Death.DragIcon(true)
        else
            self:StartMoving()
        end
    end)
    icon:SetScript("OnDragStop", function(self)
        if self.docked then
            ns.Death.DragIcon(false)
            return
        end
        self:StopMovingOrSizing()
        ns.Death.SaveIconAt(self)
        ns.Death.RefreshIcon()
    end)

    icon:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Combat log", 1, 1, 1)
        GameTooltip:AddLine("What the game's own meter is holding, and what "
            .. "you pressed.", 0.6, 0.63, 0.69, true)
        GameTooltip:AddLine("Click to open. Drag to move all three icons.",
            0.6, 0.63, 0.69, true)
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
end

function CombatLog.Icon()
    return icon
end

-- WHICH ICON THIS ONE HANGS OFF. Pure and separate from the painting, so the
-- chain can be checked without a screen: the answer is the LAST one in front
-- of it that is actually on, and nil when it is the only one left.
function CombatLog.Anchor()
    local raid = ns.RaidDeaths and ns.RaidDeaths.Icon and ns.RaidDeaths.Icon()
    if raid and raid:IsShown() then return raid end
    if ns.Death and ns.Death.IconShown and ns.Death.IconShown() then
        return ns.Death.EnsureIcon()
    end
    return nil
end

function CombatLog.RefreshIcon()
    if not (ns.UI and ns.UI.C) then return end
    local cfg = (ns.db and ns.db.death and ns.db.death.icon) or {}
    local moduleOff = ns.Modules and not ns.Modules:IsOn("deaths")

    -- ONE SWITCH FOR THE CLUSTER. The three icons share a position and a
    -- docking chain; a switch that took two of the three away would leave
    -- that chain with a hole in it and one icon on its own in the middle of
    -- the screen.
    if moduleOff or cfg.show == false then
        if icon then icon:Hide() end
        return
    end
    if not icon then BuildIcon() end

    local anchor = CombatLog.Anchor()
    icon.docked = anchor ~= nil
    icon:SetMovable(anchor == nil)

    icon:ClearAllPoints()
    if anchor then
        icon:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
    else
        icon:SetPoint("CENTER", UIParent, "CENTER",
            cfg.x or 320, cfg.y or -180)
    end
    icon:Show()
end
