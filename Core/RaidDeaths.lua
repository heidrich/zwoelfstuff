---------------------------------------------------------------------------
-- RaidDeaths.lua - who else died, when, and to what
--
-- The owner's ask: a timeline of who died, when, and to what - "sollte man aus
-- dem dmg meter ablesen koennen." The owner was right, and Death.OwnRecapID
-- had been reading that very list for weeks and throwing away every row but
-- their own.
--
-- WHAT THE CLIENT ACTUALLY HANDS OVER. Measured 2026-08-14 by `/zs death
-- probe` after a wipe, not reasoned about. Every claim below is from that
-- dump; where something is an inference it says so in as many words.
--
--   A session carries:  combatSources (the list), durationSeconds,
--                       maxAmount, totalAmount.
--   Session types the client declares: Overall, Current, Expired.
--   A death row carries: name, classFilename, deathRecapID,
--                       deathTimeSeconds, isLocalPlayer, sourceGUID,
--                       sourceCreatureID, sourceDisplayType, classification,
--                       totalAmount, amountPerSecond.
--
-- THE ANSWER THE WHOLE FEATURE HUNG ON: C_DeathRecap.GetRecapEvents ANSWERS
-- FOR SOMEBODY ELSE'S ID. Recap 40 belonged to a group member and gave ten
-- full events - source name, spell, amount, overkill, the health that was
-- left. So this can say WHAT killed each person and not merely who fell.
--   The honest limit: the four dead in that dump carried `Vehicle-` GUIDs,
--   not `Player-` ones. Proven for a non-player group member. It is the same
--   store and the same call for a player, so it very probably holds - but it
--   is not measured yet, and everything here degrades to "who and when"
--   without complaining when a recap refuses.
--
-- TWO TRAPS IN THAT DATA, either of which would have shipped as a bug:
--   * A row's sourceGUID and sourceCreatureID are THE ONE WHO DIED, not the
--     one who killed them. Row 1 was Meredy Huntswell and carried her own
--     creature id 209059, while her recap named `Tormented Shade` - 249036.
--     "Source" there means the subject of a damage-meter row. A killer's
--     portrait taken from that field would be a picture of the victim.
--   * totalAmount and amountPerSecond are 0 on every row of every session.
--     They are not the damage that killed anybody, so nothing here reads them.
--
-- AND ONE FIELD THAT IS ONLY HALF PRESENT: deathTimeSeconds is real in the
-- Current session - 87, 65, 62, 62 seconds into a fight of 121 - and -1 in
-- Overall. So the clock comes from Current, and Overall is still orderable:
-- deathRecapID counts UP with time (40, 39, 38, 37 arriving newest first),
-- which is the ordering this file falls back on when the clock is withheld.
--
-- Names are not laundered here because they arrive laundered: every string
-- that reaches a caller has already been through Death.SafeName inside
-- Death.ReadRecap, and the row fields are checked with ns.CanCompute one at
-- a time. A secret never leaves this file.
---------------------------------------------------------------------------
local _, ns = ...

local RaidDeaths = {}
ns.RaidDeaths = RaidDeaths

local floor, min = math.floor, math.min

-- ONE FIELD, VERIFIED AND COPIED. Death's rule for everything that is held
-- past the moment it was read: a value goes on only if it is readable and of
-- the type it claims. Up here rather than beside the persistence, because
-- the recap is trimmed to the same rule the second it arrives - a secret
-- kept in memory for a minute is a secret this addon carried.
local Plain = function(...) return ns.Death.Plain(...) end

---------------------------------------------------------------------------
-- Reading a row - pure, and every field guarded on its own
---------------------------------------------------------------------------

-- Whose row this is. isLocalPlayer is the client's own answer and stood on
-- every row of the dump; the name match is the older road, kept for a client
-- that withholds the flag. `me` is a parameter so this can be tested without
-- a character logged in.
function RaidDeaths.IsYou(src, me)
    if type(src) ~= "table" then return false end

    local flag = src.isLocalPlayer
    if ns.CanCompute(flag) and type(flag) == "boolean" then return flag end

    if me == nil then me = UnitName("player") end
    if not (ns.CanCompute(me) and type(me) == "string") then return false end
    local name = src.name
    if not (ns.CanCompute(name) and type(name) == "string") then return false end
    return ns.Death.StripRealm(name) == me
end

-- One raw row reduced to what can be trusted, or nil when it cannot even be
-- named. `seq` is the chronological position the caller worked out from the
-- list order - see Rows below.
function RaidDeaths.Row(src, seq, me)
    if type(src) ~= "table" then return nil end

    local name = src.name
    if not (ns.CanCompute(name) and type(name) == "string" and name ~= "") then
        return nil
    end

    local recapID = src.deathRecapID
    if not (ns.CanCompute(recapID) and type(recapID) == "number"
        and recapID > 0) then
        recapID = nil
    end

    -- -1 is the Overall session saying "there is no clock in here", which is
    -- a different thing from "they died at second zero".
    local at = src.deathTimeSeconds
    if not (ns.CanCompute(at) and type(at) == "number" and at >= 0) then
        at = nil
    end

    local class = src.classFilename
    if not (ns.CanCompute(class) and type(class) == "string" and class ~= "") then
        class = nil
    end

    return {
        name = name,
        short = ns.Death.StripRealm(name),
        class = class,
        -- WHAT THEY WERE PLAYING, asked while they are still in the group.
        -- The meter says "MAGE" and nothing more; the picture beside the name
        -- should say Frost. It is read here rather than when the window
        -- opens, because by then the pull is over and half the group may have
        -- left - and an inspect answer is not something we can ask for about
        -- somebody who is gone. nil stays nil: the class icon is the fallback
        -- and it is never wrong, only less exact.
        spec = ns.Specs and ns.Specs.OfName(name) or nil,
        at = at,
        recapID = recapID,
        you = RaidDeaths.IsYou(src, me),
        seq = seq or 0,
    }
end

-- Every readable row of a session's list. The list arrives NEWEST FIRST, so
-- the reversed index is the chronological one - that is the last-resort
-- ordering key for a client that withholds both the clock and the recap id.
function RaidDeaths.Rows(list, me)
    local rows = {}
    if type(list) ~= "table" then return rows end
    local count = #list
    for index = 1, count do
        local row = RaidDeaths.Row(list[index], count - index + 1, me)
        if row then rows[#rows + 1] = row end
    end
    return rows
end

---------------------------------------------------------------------------
-- The order they fell in - pure
---------------------------------------------------------------------------

-- Oldest first, plus whether the clock could be trusted. Copies rather than
-- sorts in place: a caller that hands the same rows to two views should not
-- have the first one reorder them under the second.
function RaidDeaths.Timeline(rows)
    local out = {}
    if type(rows) ~= "table" then return out, false end
    for index = 1, #rows do
        local row = rows[index]
        out[index] = {
            name = row.name, short = row.short, class = row.class,
            at = row.at, recapID = row.recapID, you = row.you, seq = row.seq,
        }
    end

    -- The clock is usable only when EVERY row has one. Half a list ordered by
    -- time and half by id is not a timeline, it is two lists interleaved.
    local timed = #out > 0
    for _, row in ipairs(out) do
        if not row.at then
            timed = false
            break
        end
    end

    -- Three keys, each a total order on its own, so the sort is deterministic
    -- however much the client withheld: the clock, then the recap id, then
    -- the position in the list the client handed over.
    table.sort(out, function(a, b)
        if timed and a.at ~= b.at then return a.at < b.at end
        if a.recapID and b.recapID and a.recapID ~= b.recapID then
            return a.recapID < b.recapID
        end
        return a.seq < b.seq
    end)

    -- The gap to the one before is the part that tells a wipe from four
    -- unlucky pulls. Only where the clock is real.
    for index = 2, #out do
        if timed then out[index].gap = out[index].at - out[index - 1].at end
    end
    return out, timed
end

---------------------------------------------------------------------------
-- What ended each one - pure
---------------------------------------------------------------------------

-- The killing blow out of a recap's events. Death.ReadRecap hands them over
-- OLDEST first, so the last one is the one that landed last; heals are
-- skipped because dying to a heal is not a thing and a heal in the last slot
-- would name the healer as the killer.
function RaidDeaths.Blow(events)
    if type(events) ~= "table" then return nil end
    for index = #events, 1, -1 do
        local ev = events[index]
        if type(ev) == "table" and not ev.heal then
            return {
                who = ev.who,
                spell = ev.name,
                spellID = ev.spellID,
                amount = ev.amount,
                overkill = ev.overkill,
                art = ev.art,
                avoidable = ev.avoidable,
            }
        end
    end
    return nil
end

-- WHAT ACTUALLY DROPPED THEM, which is a different question from what
-- finished them and usually a more useful one. Meredy's killing blow was
-- 31.8k with 28.5k of it wasted on a corpse: the hit that mattered landed
-- earlier. The biggest hit of the last seconds is the one to talk about.
--
-- Returns nil when the killing blow IS the biggest, because then there is
-- nothing extra to say and a line saying it anyway is noise.
function RaidDeaths.RealBlow(events)
    if type(events) ~= "table" or #events < 2 then return nil end

    local biggest, last
    for index = 1, #events do
        local ev = events[index]
        if type(ev) == "table" and not ev.heal and type(ev.amount) == "number" then
            -- What the hit actually TOOK, not what it was rolled for.
            local landed = ev.amount - (ev.overkill or 0)
            if not biggest or landed > biggest.landed then
                biggest = { ev = ev, landed = landed, index = index }
            end
            last = index
        end
    end

    if not (biggest and last) or biggest.index == last then return nil end
    return {
        who = biggest.ev.who,
        spell = biggest.ev.name,
        spellID = biggest.ev.spellID,
        amount = biggest.ev.amount,
        landed = biggest.landed,
        avoidable = biggest.ev.avoidable,
    }
end

-- HOW MANY OF THEM WALKED INTO IT. Three answers, not two: yes, no, and the
-- client did not say - because a client that withholds the flag would
-- otherwise report a whole raid as blameless, which is the flattering
-- reading and therefore the one to refuse.
function RaidDeaths.Avoidable(entries)
    local yes, no, unknown = 0, 0, 0
    for _, entry in ipairs(entries or {}) do
        local flag = entry.blow and entry.blow.avoidable
        if flag == true then yes = yes + 1
        elseif flag == false then no = no + 1
        else unknown = unknown + 1 end
    end
    return yes, no, unknown
end

-- What did the killing, counted. This is the row of mobs and abilities they
-- asked for along the top: which thing, with which ability, ended the most
-- people. Ties break by name so two runs of the same fight print the same
-- order.
function RaidDeaths.Culprits(entries)
    local byKey, order = {}, {}
    for _, entry in ipairs(entries or {}) do
        local blow = entry.blow
        if blow and blow.who then
            local spell = blow.spell or "?"
            local key = blow.who .. "\0" .. spell
            local seen = byKey[key]
            if not seen then
                seen = {
                    who = blow.who, spell = spell,
                    spellID = blow.spellID, count = 0,
                }
                byKey[key] = seen
                order[#order + 1] = seen
            end
            seen.count = seen.count + 1
        end
    end
    table.sort(order, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        if a.who ~= b.who then return a.who < b.who end
        return a.spell < b.spell
    end)
    return order
end

---------------------------------------------------------------------------
-- Asking the client
---------------------------------------------------------------------------

-- The deaths the client is holding right now: rows, or nil and the reason.
-- Current first because it is the only session with a clock in it; Overall
-- is the fallback and the label says which one answered.
function RaidDeaths.Read(me)
    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType
        and Enum and Enum.DamageMeterType and Enum.DamageMeterSessionType) then
        return nil, "this client has no damage meter API"
    end

    local function SessionOf(sessionType)
        if type(sessionType) ~= "number" then return nil end
        local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType,
            sessionType, Enum.DamageMeterType.Deaths)
        if not ok or type(session) ~= "table" then return nil end
        -- combatSources, one name and no fallback. Death.OwnRecapID still
        -- carries an `or session.sources` from the days when the field was a
        -- guess; the probe dumped every key of both sessions and there is no
        -- such field, so a second door here would only be somewhere for a
        -- future rename to hide.
        local list = session.combatSources
        if type(list) ~= "table" or #list == 0 then return nil end
        return session, list
    end

    local label = "this fight"
    local session, list = SessionOf(Enum.DamageMeterSessionType.Current)
    if not (session and list) then
        label = "this session"
        session, list = SessionOf(Enum.DamageMeterSessionType.Overall)
    end
    if not (session and list) then
        return nil, "the damage meter lists no deaths yet"
    end

    local duration = session.durationSeconds
    if not (ns.CanCompute(duration) and type(duration) == "number"
        and duration > 0) then
        duration = nil
    end

    return RaidDeaths.Rows(list, me), nil, duration, label
end

---------------------------------------------------------------------------
-- ONE DEATH'S RECAP, READ ONCE AND KEPT WHOLE
--
-- The owner's ask after the first live run: a death in the list should open
-- the way their own does - the last ten seconds of the person who fell. The
-- recap says all of it and always did; this file was keeping the last line and
-- throwing the story away.
--
-- So the events are kept. Not because they might be useful later: BECAUSE
-- THE RECAP IS GONE by the time anybody clicks the row. C_DeathRecap answers
-- for a death of the current fight, and the window is read after the wipe,
-- from a list that survived a reload. Whatever is not taken here cannot be
-- asked for again.
--
-- One place, called from both roads in - the live read and the capture tick.
-- Two copies of "what a recap has to say" is the one that grows a field and
-- the one that does not.
---------------------------------------------------------------------------

-- How many hits of one death are kept. The 2026-08-14 probe handed over ten
-- for a full death and the window shows the last ten seconds of them, so
-- this is roughly double what has ever been seen - a ceiling, not a budget.
-- Anything cut off is COUNTED and said out loud in the window; a list that
-- quietly starts in the middle is a list that lies about where it starts.
local EVENTS_KEPT = 24
RaidDeaths.EVENTS_KEPT = EVENTS_KEPT

-- A recap's events, reduced to what may be held and written to disk, newest
-- END kept: the hits nearest the death are the ones the window is opened
-- for. Returns the list and how many older ones were dropped.
function RaidDeaths.PlainEvents(events)
    if type(events) ~= "table" then return nil, 0 end
    local out, dropped = {}, 0
    local first = 1
    if #events > EVENTS_KEPT then
        first = #events - EVENTS_KEPT + 1
        dropped = first - 1
    end
    for index = first, #events do
        local ev = events[index]
        if type(ev) == "table" then
            local t = Plain(ev.t, "number")
            local amount = Plain(ev.amount, "number")
            if t and amount then
                out[#out + 1] = {
                    t = t,
                    amount = amount,
                    hp = Plain(ev.hp, "number"),
                    overkill = Plain(ev.overkill, "number"),
                    name = Plain(ev.name, "string"),
                    who = Plain(ev.who, "string"),
                    spellID = Plain(ev.spellID, "number"),
                    heal = ev.heal == true,
                    -- Strictly a boolean, so "the client did not say" comes
                    -- back off the disk as itself and not as "not avoidable".
                    avoidable = Plain(ev.avoidable, "boolean"),
                    -- WHOSE FACE GOES IN FRONT OF THE ROW. It was dropped
                    -- here and the killing blow alone kept its art - so the
                    -- opened death drew ten rows with the face column empty
                    -- while the death window's rows had theirs (owner,
                    -- 2026-08-16). Same shape the death window keeps.
                    art = ns.Death.PlainArt(ev.art),
                }
            end
        end
    end
    if #out == 0 then return nil, 0 end
    return out, dropped
end

-- HOW MANY OF THESE HITS THE GAME ITSELF CALLS AVOIDABLE. The same three
-- answers the whole-pull verdict gives, for the reason: a person whose
-- client withheld the flag must not read as a person who did nothing wrong.
function RaidDeaths.AvoidableHits(events)
    local yes, no, unknown = 0, 0, 0
    for _, ev in ipairs(events or {}) do
        if not ev.heal then
            if ev.avoidable == true then yes = yes + 1
            elseif ev.avoidable == false then no = no + 1
            else unknown = unknown + 1 end
        end
    end
    return yes, no, unknown
end

-- Everything one death's recap has to say, onto the entry. The fields it
-- writes are the fields Reuse below carries forward and Persist writes out;
-- all three are one list and are meant to be edited together.
function RaidDeaths.Resolve(entry)
    if not entry then return entry end
    if not entry.recapID then
        entry.blowWhy = "no recap id on this death"
        return entry
    end

    local events, maxHP, readWhy, _, art = ns.Death.ReadRecap(entry.recapID)
    entry.blow = events and RaidDeaths.Blow(events) or nil
    if not entry.blow then
        entry.blowWhy = readWhy or "the recap gave nothing"
        return entry
    end

    -- The face belongs to whichever event carried one; the recap's own
    -- answer is the fallback, never the row's own creature id, which is the
    -- dead one - see the header.
    entry.blow.art = entry.blow.art or art
    entry.real = RaidDeaths.RealBlow(events)
    -- Everything this thing did to THIS person, summed while the events are
    -- still in hand.
    entry.blow.summary = ns.Death.SourceSummary(events, entry.blow.who)
    entry.maxHP = (type(maxHP) == "number" and maxHP > 0) and maxHP or nil
    entry.events, entry.dropped = RaidDeaths.PlainEvents(events)
    if entry.dropped == 0 then entry.dropped = nil end
    return entry
end

-- What a settled answer hands to the next capture of the same pull. One list,
-- next to Resolve, so a new field cannot be written by one and lost by the
-- other two ticks later.
local function Reuse(entry, was)
    entry.blow, entry.blowWhy = was.blow, was.blowWhy
    entry.real, entry.tries = was.real, was.tries
    entry.events, entry.dropped, entry.maxHP =
        was.events, was.dropped, was.maxHP
    return entry
end

-- The whole picture: the timeline, each entry's killing blow, and what the
-- fight adds up to. Kept apart from Read so the ordering can be exercised at
-- a desk with no recap API in the room.
function RaidDeaths.Collect(me)
    local rows, why, duration, label = RaidDeaths.Read(me)
    if not rows then return nil, why end

    local entries, timed = RaidDeaths.Timeline(rows)
    for _, entry in ipairs(entries) do
        RaidDeaths.Resolve(entry)
    end

    return entries, nil, {
        timed = timed,
        duration = duration,
        label = label,
        culprits = RaidDeaths.Culprits(entries),
    }
end

---------------------------------------------------------------------------
-- Keeping the fight, because the clock does not wait
--
-- The owner's first live run: "4 in this session, 27:39 long (no clock)" and
-- `--:--` on every line. Nothing was broken - they typed the command AFTER the
-- pull, and by then the Current session had been reset and only Overall was
-- left, which answers -1 for every death. The whole point of the feature is
-- when each person fell, and that number exists only while the fight is
-- running.
--
-- So it is captured while it is still there. This is the same lesson the
-- own-death log learned about reloading, one step earlier: the data is not
-- lost at logout, it is lost at the end of the pull.
--
-- Each recap is read ONCE per fight. A capture reuses the blow it already
-- resolved for a recap id, so the two-second tick below costs one list read
-- and nothing else once everybody's recap has been opened.
---------------------------------------------------------------------------

-- Fights kept, oldest first. Five, because the question is "what happened on
-- that pull" and the answer stops being asked after a few.
local FIGHTS_KEPT = 5
RaidDeaths.FIGHTS_KEPT = FIGHTS_KEPT
RaidDeaths.log = {}

-- WHICH PLACES ARE FOLDED SHUT, keyed by the place. Kept in memory and not
-- on disk on purpose: it is a reading gesture, not a setting, and a column
-- that came back after a reload with a place shut looks exactly like a
-- column that lost its pulls. Unfolded is the answer nobody has to undo.
RaidDeaths.collapsed = {}
-- AND WHICH FIGHTS ON THE EVENING'S PAGE ARE FOLDED. A separate table from
-- the column's, on purpose: the two are keyed by different things - a place
-- and a run there, a fight of the night here - and one shared table would
-- have a fold in one window close a row in the other that only looks alike.
RaidDeaths.overCollapsed = {}

-- Which fight a set of rows belongs to. Recap ids count up and are never
-- reused within a session, so the LOWEST one in the list is the first death
-- of this fight and names it. Pure, and the whole of "is this the same pull
-- I captured two seconds ago".
function RaidDeaths.FightKey(entries)
    local lowest
    for _, entry in ipairs(entries or {}) do
        if entry.recapID and (not lowest or entry.recapID < lowest) then
            lowest = entry.recapID
        end
    end
    return lowest
end

-- Where a fight goes in the log: onto the end, or over the top of the last
-- one when it is the same pull still running. Pure and exported for the same
-- reason Death.Remember is - it is the one rule about how the list grows.
-- WHAT A LATER CAPTURE OF THE SAME PULL MUST NOT UNLEARN.
--
-- The same pull is read again every two seconds and once more when combat
-- drops, and the client answers FEWER questions each time: the encounter has
-- ended and taken its name, the group has left and taken the instance, the
-- guide has stopped answering. The later read replaces the fight whole, so
-- anything it could not answer is taken from the copy it replaces.
--
-- Only fields that cannot change WITHIN one pull are on this list. A pull
-- has one key, and a key cannot walk into a different dungeon.
local CARRIED = {
    "boss", "bossID", "kind", "instance", "journal", "where", "whereShort",
    "stamp",
}

function RaidDeaths.Remember(log, fight, cap)
    local last = log[#log]
    if last and fight.key and last.key == fight.key then
        for _, field in ipairs(CARRIED) do
            if fight[field] == nil then fight[field] = last[field] end
        end
        log[#log] = fight
    else
        log[#log + 1] = fight
        while #log > (cap or FIGHTS_KEPT) do table.remove(log, 1) end
    end
    return fight
end

---------------------------------------------------------------------------
-- THE WHOLE EVENING, WHICH IS A DIFFERENT QUESTION FROM THE LAST PULL
--
-- "Third wipe to Grim Ward tonight" is the sentence that changes what a
-- group does next, and no single pull can say it. Neither can the log above:
-- it keeps five, because it keeps the WHOLE of each one - every hit of every
-- death - and twenty of those on disk is a saved-variables file nobody
-- asked for.
--
-- So the evening is kept SEPARATELY and thin. One line per death: who, what
-- killed them, and whether the game called it avoidable. No hits, no
-- portraits, no summaries - the things that make a pull heavy are exactly
-- the things a tally does not read. Sixty pulls of that is smaller than one
-- pull of the other list.
--
-- It follows the same replace-by-key rule, because the capture tick rewrites
-- the running pull every two seconds and a tally that ADDED each time would
-- report a two-minute fight as thirty wipes.
---------------------------------------------------------------------------
local SESSION_KEPT = 60
RaidDeaths.SESSION_KEPT = SESSION_KEPT
RaidDeaths.session = { fights = {} }

---------------------------------------------------------------------------
-- WHAT A PULL WAS, AND HOW THE COLUMN IS ARRANGED
--
-- Owner, 2026-08-25: "in der zeile von der instanz, eine trennlinie, dann
-- steht da pulls 11 ... dann ein chevron zum ausfahren nachn unten, da geht
-- nach unten die liste mit den Pulls auf, 1, 2, 3, bei Trash steht trash
-- pull da, beim boss pull, dann boss."
--
-- Both pure. The column paints whatever SideItems returns and knows nothing
-- about instances, runs or pull numbers - which is the only way any of this
-- arithmetic can be checked without a screen in front of it.
---------------------------------------------------------------------------

-- WHEN A PULL HAPPENED, in the client's own format. Pure: the caller reads
-- the setting and hands it over, so both formats can be checked here.
--
-- `military` false is the twelve-hour clock, and the leading zero goes:
-- "09:34:24 AM" is a clock face, not a sentence. A fight from before the
-- moment was recorded keeps the words it was captured with - nothing else
-- knows what hour they meant, and inventing one would be worse than
-- printing what was written down.
function RaidDeaths.PullTime(fight, military)
    if type(fight) ~= "table" then return "" end
    local stamp = Plain(fight.stamp, "number")
    if not stamp then return Plain(fight.when, "string") or "" end
    if military == false then
        return (date("%I:%M:%S %p", stamp):gsub("^0", ""))
    end
    return date("%H:%M:%S", stamp)
end

-- Which clock the client is set to. Its own answer, and the same question
-- every other addon on this machine asks.
function RaidDeaths.Military()
    if not GetCVar then return true end
    local ok, value = pcall(GetCVar, "timeMgrUseMilitaryTime")
    if not ok then return true end
    return value == "1"
end

-- The boss, or trash. Recorded at capture from ENCOUNTER_START, so this is
-- what the game said rather than a word picked out of a label. No boss is a
-- real answer and not a missing one: it was trash.
function RaidDeaths.PullLabel(fight)
    local boss = type(fight) == "table" and Plain(fight.boss, "string") or nil
    return boss or "Trash pull", boss ~= nil
end

-- WHAT A PULL COST, in the words a narrow column has room for: how many
-- fell, and then the ONE thing worth saying beside that - the mechanic that
-- took more than one of them, or failing that how long the pull lasted.
--
-- Pulled out of the painter so the desk can read it. It was four branches
-- inside a loop that also moved anchors and set colours, which is where a
-- sentence like "1 dead" quietly becomes "1 dead  -  " with nothing after
-- the dash and nobody notices for a version.
function RaidDeaths.PullLine(fight)
    if type(fight) ~= "table" then return "" end
    local line = string.format("%d dead", #(fight.entries or {}))
    local worst = (fight.culprits or {})[1]
    if worst and (worst.count or 0) > 1 and (worst.spell or worst.who) then
        return line .. "  -  " .. ns.UI.HarmText(worst.spell or worst.who)
    end
    if fight.duration then
        return line .. "  -  " .. RaidDeaths.Clock(fight.duration)
    end
    return line
end

-- WHAT TOOK MOST OF THEM, on its own - the count moved to a column of its
-- own when the row became two of them, and a sentence carrying both would
-- have said "12 dead" twice.
--
-- Falling back to how long the pull lasted: a pull where everybody died to
-- something different has no one mechanic to name, and saying nothing at all
-- leaves a blank line under the clock.
--
-- Returns the ABILITY'S ID as well, and only when the word IS the ability:
-- the id draws the icon in front of it and opens the client's tooltip, and
-- a mob's name or a clock has neither. Owner, 2026-08-29: "kannst du in der
-- rechten spalte die kill spells verlinken und das icon davor packen?"
function RaidDeaths.PullMechanic(fight)
    if type(fight) ~= "table" then return "" end
    local worst = (fight.culprits or {})[1]
    if worst and (worst.count or 0) > 1 and (worst.spell or worst.who) then
        if worst.spell then return worst.spell, worst.spellID end
        return worst.who
    end
    if fight.duration then return RaidDeaths.Clock(fight.duration) end
    return ""
end

-- WHICH PAGE OF THE ADVENTURE GUIDE A BOSS IS ON.
--
-- The mapping itself moved to Death.lua, beside Death.OpenJournal: it is
-- about places and bosses rather than about the group's pulls, and BOTH
-- columns ask it now that the own log's fight rows link their boss too.
-- Forwarded rather than aliased at file scope, so the load order cannot
-- decide whether this name exists.
function RaidDeaths.BossPage(journalID, bossID, name)
    return ns.Death.BossPage(journalID, bossID, name)
end

-- WHO DID MOST OF THE KILLING ON ONE PULL, and its face.
--
-- The right-hand column of a pull row, so it reads exactly like the own
-- death log's rows do - owner, 2026-08-29: "dann muesste das layout im
-- normalen death log naklar genauso sein wie beim group death log". There
-- the right column names the mob that landed the blow; here it names the one
-- that landed the most of them.
function RaidDeaths.PullCulprit(fight, log)
    if type(fight) ~= "table" then return nil end
    local worst = (fight.culprits or {})[1]
    local who = worst and worst.who
    if not who then return nil end
    for _, entry in ipairs(fight.entries or {}) do
        local art = RaidDeaths.ArtFor(entry, who)
        if art then return who, art end
    end
    -- A PULL OUT OF THE TALLY CARRIES NO PICTURES, and the same mob is very
    -- likely still in one of the newest five that do. The same fallback the
    -- evening's page uses; without it the column draws a face on the pulls
    -- that still have their hits and a hole on every row above them, for
    -- the same mob under the same name.
    local kept = RaidDeaths.ArtForWho(log, who)
    if kept then return who, kept end
    -- Named without a picture is still an answer; the row simply draws no
    -- face, the way a pull whose recap kept no art always has.
    return who, nil
end

-- THE BOSS'S FACE, and the guide is asked only when nobody died to it.
--
-- The recap first: a mob somebody actually died to carries its art, it is
-- the model the client has already drawn once, and it is right even where
-- the guide has no page at all. The guide's own portrait is the fallback,
-- and it lives in Death.lua with the rest of the mapping - on a fight whose
-- adds do the killing, NOBODY has ever been killed by the boss, so the
-- recap has no picture of it and the header over the block sat blank.
function RaidDeaths.BossArt(journalID, bossID, name)
    local art = RaidDeaths.ArtForWho(RaidDeaths.log, name)
    if art then return art end
    return ns.Death.GuideFace(journalID, bossID, name)
end

-- THE COLUMN AS A LIST OF THINGS TO DRAW, three levels deep: the place, the
-- fight inside it, and the pulls inside that.
--
-- The rule itself is ns.Death.GroupItems, shared with the own-death window.
-- Owner, 2026-08-25, about a column with the same dungeon in it four times:
-- "wenn wir das pro instant / raid sortieren, dann hast du rechts auch nicht
-- 3 mal rubi stehen" - and 2026-08-29, about the level under it: "wir
-- brauchen also noch eine sortierung NACH bossen, in DER die pull counts
-- sind."
--
-- A pull row keeps `fight` as well as `entry`, because everything that reads
-- this column asks a fight for its clock, its dead and its culprits.
--
-- `pulls` is the MERGED list from RaidDeaths.Pulls - the evening's sixty,
-- with the newest five carrying their hits - and not the log. The column and
-- the selection have to be counting the same rows or an index taken from one
-- names a different pull in the other.
function RaidDeaths.SideItems(pulls, collapsed)
    local items = ns.Death.GroupItems(pulls, collapsed, "pull")
    for _, item in ipairs(items) do
        if item.kind == "pull" then
            item.fight = item.entry
            item.label, item.bossPull = RaidDeaths.PullLabel(item.entry)
            item.dead = #((item.entry and item.entry.entries) or {})
        end
    end
    return items
end

-- A fight, reduced to what a tally reads. Pure.
function RaidDeaths.Light(fight)
    if type(fight) ~= "table" or type(fight.entries) ~= "table" then
        return nil
    end
    local out = {
        key = Plain(fight.key, "number"),
        when = Plain(fight.when, "string"),
        where = Plain(fight.where, "string"),
        whereShort = Plain(fight.whereShort, "string"),
        instance = Plain(fight.instance, "string"),
        journal = Plain(fight.journal, "number"),
        boss = Plain(fight.boss, "string"),
        kind = Plain(fight.kind, "string"),
        bossID = Plain(fight.bossID, "number"),
        stamp = Plain(fight.stamp, "number"),
        duration = Plain(fight.duration, "number"),
        entries = {},
    }
    for _, entry in ipairs(fight.entries) do
        local name = Plain(entry.name, "string")
        if name then
            local blow = type(entry.blow) == "table" and entry.blow or nil
            local spellID
            -- WRITTEN OUT RATHER THAN GUARDED WITH `and ... or`, and this is
            -- the second time in one evening: `blow and Plain(x) or nil`
            -- turns a readable FALSE into nil, so "the game says this was not
            -- avoidable" would be filed as "the game did not say" - and the
            -- tally would then report a whole night as unanswered. The idiom
            -- holds two answers and this field has three.
            local who, spell, avoidable
            if blow then
                who = Plain(blow.who, "string")
                spell = Plain(blow.spell, "string")
                avoidable = Plain(blow.avoidable, "boolean")
                -- AND THE ABILITY'S ID, one number, so a pull the log no
                -- longer holds still draws the icon in front of the name
                -- and still opens the client's tooltip on it. Without it
                -- the newest five would carry an icon and every row above
                -- them a bare word, for the same ability.
                spellID = Plain(blow.spellID, "number")
            end
            out.entries[#out.entries + 1] = {
                name = name,
                short = Plain(entry.short, "string") or name,
                class = Plain(entry.class, "string"),
                spec = Plain(entry.spec, "number"),
                you = entry.you == true,
                who = who,
                spell = spell,
                spellID = spellID,
                avoidable = avoidable,
            }
        end
    end
    if #out.entries == 0 then return nil end
    return out
end

---------------------------------------------------------------------------
-- THE EVENING AND THE LOG, READ AS ONE LIST
--
-- Owner, 2026-08-28, given the choice between raising the log's five and
-- feeding the column out of the tally: the tally. Measured before it was
-- asked rather than guessed - twenty full pulls came to 862 KB of saved
-- variables against 304 KB for sixty thin ones, so the thin sixty is both
-- the longer memory and the smaller file.
--
-- So the column draws SIXTY pulls and the hit-by-hit recordings stay at
-- five. A pull that has fallen out of the log is still a row, still counts
-- its dead, still names what did most of the killing and still opens; what
-- it no longer has is the seconds before each death, and the page says so
-- rather than looking like a pull whose recap refused every question.
---------------------------------------------------------------------------

-- The evening's thin copy, put back into the shape the window reads.
--
-- The alternative was to teach every reader about two shapes - the table,
-- the detail, the culprit count, the faces, the verdict - and every one of
-- those would have been a place where the thin one was forgotten. One shape
-- goes through the window instead, and `thin` is the single field that says
-- what is not in it.
--
-- Memoised ON the thin table, which is safe for the one reason that matters:
-- RememberSession REPLACES a running pull's thin copy with a new table every
-- capture, so the memo dies with the table it was written on instead of
-- going stale. `Light` copies field by name, so it never reaches the disk.
function RaidDeaths.Thick(light)
    if not (type(light) == "table" and type(light.entries) == "table") then
        return nil
    end
    if type(light.thick) == "table" then return light.thick end

    local out = {
        key = Plain(light.key, "number"),
        when = Plain(light.when, "string"),
        where = Plain(light.where, "string"),
        whereShort = Plain(light.whereShort, "string"),
        instance = Plain(light.instance, "string"),
        journal = Plain(light.journal, "number"),
        boss = Plain(light.boss, "string"),
        kind = Plain(light.kind, "string"),
        bossID = Plain(light.bossID, "number"),
        stamp = Plain(light.stamp, "number"),
        duration = Plain(light.duration, "number"),
        -- WHAT IS NOT IN HERE, SAID OUT LOUD. Every "is this the reduced
        -- copy" question asks this one field rather than sniffing for
        -- something missing: "it has no events" is also true of a full pull
        -- whose recaps all refused, and those two must not read alike.
        thin = true,
        entries = {},
    }

    for _, entry in ipairs(light.entries) do
        -- The tally flattened the killing blow into three fields on the
        -- death; this folds them back up. A death whose recap said nothing
        -- has none of the three and gets no blow at all - which is exactly
        -- the shape an unanswered death has in a full pull.
        local blow
        if entry.who or entry.spell then
            blow = {
                who = Plain(entry.who, "string"),
                spell = Plain(entry.spell, "string"),
                spellID = Plain(entry.spellID, "number"),
                avoidable = Plain(entry.avoidable, "boolean"),
            }
        end
        out.entries[#out.entries + 1] = {
            name = Plain(entry.name, "string"),
            short = Plain(entry.short, "string")
                or Plain(entry.name, "string"),
            class = Plain(entry.class, "string"),
            spec = Plain(entry.spec, "number"),
            you = entry.you == true,
            blow = blow,
        }
    end

    -- DERIVED, not carried: the tally never stored a culprit count, and the
    -- rule for one is the same rule the full pulls use - so a better rule
    -- written next month applies to these as well.
    out.culprits = RaidDeaths.Culprits(out.entries)
    light.thick = out
    return out
end

-- ONE LIST OF PULLS OUT OF THE TWO, oldest first, each pull exactly once.
--
-- A pull that is in both comes out as the FULL one: it is the same pull with
-- more in it. The two lists can hold different pulls, which is why this is a
-- merge and not a concatenation - the log keeps its five across days while
-- the tally is emptied when the date turns over, so after midnight the log
-- has pulls the evening does not.
--
-- Ordered by the moment each was captured. A pull saved before that moment
-- was recorded has no stamp of its own and takes the last one seen in its
-- own list, which puts it where it belongs instead of at one end - and, un-
-- like falling back to "whichever list it came from", it leaves every row
-- with a NUMBER to sort on. A comparator that switches between two keys is
-- not transitive, and table.sort throws on those rather than mis-sorting.
function RaidDeaths.Pulls(log, session)
    local seen, rows = {}, {}

    local function Take(list, make)
        local carried = 0
        for _, item in ipairs(list or {}) do
            if type(item) == "table" then
                local key = Plain(item.key, "number")
                local stamp = Plain(item.stamp, "number")
                if stamp then carried = stamp end
                if not (key and seen[key]) then
                    local fight = make(item)
                    if fight then
                        if key then seen[key] = true end
                        rows[#rows + 1] = { fight = fight,
                            stamp = stamp or carried, order = #rows }
                    end
                end
            end
        end
    end

    -- The full pulls first, so a pull that is in both lists is taken as the
    -- one with the hits in it and its thin twin is never even built.
    Take(log, function(fight) return fight end)
    Take((session or {}).fights, RaidDeaths.Thick)

    table.sort(rows, function(a, b)
        if a.stamp ~= b.stamp then return a.stamp < b.stamp end
        return a.order < b.order
    end)

    local out = {}
    for _, row in ipairs(rows) do out[#out + 1] = row.fight end
    return out
end

-- A DAY IS THE UNIT. Yesterday's wipes are not tonight's, and a tally that
-- carries them over answers "third wipe tonight" with a number from a raid
-- two days ago. The client's own date, so it turns over when their does.
function RaidDeaths.Today()
    local ok, today = pcall(date, "%Y-%m-%d")
    if ok and type(today) == "string" then return today end
    return nil
end

function RaidDeaths.RememberSession(session, light, today, cap)
    if not (type(session) == "table" and light) then return session end
    if session.day ~= today then
        session.day = today
        session.fights = {}
    end
    local fights = session.fights
    for index = #fights, 1, -1 do
        if fights[index].key and fights[index].key == light.key then
            fights[index] = light
            return session
        end
    end
    fights[#fights + 1] = light
    while #fights > (cap or SESSION_KEPT) do table.remove(fights, 1) end
    return session
end

-- WHAT KEEPS KILLING US. The same mob and ability across the evening, with
-- the number of PULLS beside the number of deaths - because four deaths to
-- one thing on one pull is a mechanic that went wrong once, and four deaths
-- to it across four pulls is a mechanic nobody has learned.
--
-- Ties break by name so two readings of the same evening print the same
-- order.
function RaidDeaths.Repeat(session)
    return RaidDeaths.RepeatIn(session and session.fights)
end

-- THE SAME RULE OVER A LIST OF PULLS RATHER THAN OVER THE EVENING.
--
-- Split out when the page grew a boss layer: the block under one boss asks
-- exactly the question the page asks of the night, of its own three pulls.
-- Two copies of this loop would be two places for a better rule to be
-- written into one of them.
function RaidDeaths.RepeatIn(fights)
    local byKey, out = {}, {}
    for _, fight in ipairs(fights or {}) do
        local seenThisPull = {}
        for _, entry in ipairs(fight.entries or {}) do
            if entry.who then
                local key = entry.who .. "\1" .. (entry.spell or "?")
                local row = byKey[key]
                if not row then
                    row = { who = entry.who, spell = entry.spell or "?",
                        deaths = 0, pulls = 0 }
                    byKey[key] = row
                    out[#out + 1] = row
                end
                row.deaths = row.deaths + 1
                if not seenThisPull[key] then
                    seenThisPull[key] = true
                    row.pulls = row.pulls + 1
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.deaths ~= b.deaths then return a.deaths > b.deaths end
        if a.pulls ~= b.pulls then return a.pulls > b.pulls end
        if a.who ~= b.who then return a.who < b.who end
        return a.spell < b.spell
    end)
    return out
end

-- WHO IS FALLING. Deaths, in how many pulls, and how many of them the game
-- itself called avoidable - kept apart from the ones it said nothing about,
-- because a person whose client withheld the flag must not read as a person
-- who did nothing wrong.
function RaidDeaths.Fallen(session)
    return RaidDeaths.FallenIn(session and session.fights)
end

function RaidDeaths.FallenIn(fights)
    local byName, out = {}, {}
    for _, fight in ipairs(fights or {}) do
        local seenThisPull = {}
        for _, entry in ipairs(fight.entries or {}) do
            local row = byName[entry.name]
            if not row then
                row = { name = entry.name, short = entry.short or entry.name,
                    class = entry.class, spec = entry.spec,
                    you = entry.you == true,
                    deaths = 0, pulls = 0, avoidable = 0, unknown = 0 }
                byName[entry.name] = row
                out[#out + 1] = row
            end
            row.deaths = row.deaths + 1
            if entry.avoidable == true then
                row.avoidable = row.avoidable + 1
            elseif entry.avoidable ~= false then
                row.unknown = row.unknown + 1
            end
            if not seenThisPull[entry.name] then
                seenThisPull[entry.name] = true
                row.pulls = row.pulls + 1
            end
        end
    end
    table.sort(out, function(a, b)
        if a.deaths ~= b.deaths then return a.deaths > b.deaths end
        return a.name < b.name
    end)
    return out
end

---------------------------------------------------------------------------
-- THE EVENING, BROKEN AT THE BOSSES
--
-- Owner, 2026-08-29, about a page that answered "what keeps killing us" with
-- one list for a whole raid night: it wants the boss layer the column
-- already has. A night that reads "Cosmic Singularity  9 deaths across 4
-- pulls" and nothing else has thrown away the one thing that makes it
-- actionable - WHICH FIGHT that was on.
--
-- A BOSS IS A BUCKET HERE, AND A RUN IN THE COLUMN, and that is not an
-- inconsistency: they answer two questions. The column answers WHERE IN THE
-- EVENING a pull sat, so its trash breaks into blocks and the trash before a
-- boss is a different row from the trash after it. This page answers WHAT
-- KEEPS HAPPENING, and three attempts at one boss with a trash pull between
-- them are three attempts at one boss. Splitting them here would give the
-- same mechanic two rows and halve both of its counts - which is the exact
-- pattern the page exists to make visible.
--
-- Ordered by the FIRST time the evening met each of them, so the page reads
-- as the night in the order it happened rather than as a leaderboard. The
-- leaderboard is one sentence at the top instead.
---------------------------------------------------------------------------

-- WHAT MAKES ONE BLOCK: the place, and the fight in it. The same two fields
-- the column keys on (ns.Death.FightKeyOf), so a night that groups one way
-- there cannot group another way here.
function RaidDeaths.BossKey(fight)
    if type(fight) ~= "table" then return "" end
    local place = Plain(fight.instance, "string")
        or Plain(fight.whereShort, "string") or ""
    return place .. "\1" .. (Plain(fight.boss, "string") or "")
end

function RaidDeaths.Bosses(session)
    local byKey, out = {}, {}
    for _, fight in ipairs((session and session.fights) or {}) do
        if type(fight) == "table" and type(fight.entries) == "table" then
            local key = RaidDeaths.BossKey(fight)
            local block = byKey[key]
            if not block then
                local boss = Plain(fight.boss, "string")
                block = {
                    id = "tonight#" .. key,
                    boss = boss,
                    -- TRASH IS THE WORD IN BOTH WINDOWS. The column already
                    -- writes it over a block with no boss on it, and two
                    -- pages calling one thing two names is a reader
                    -- wondering whether they are the same thing.
                    label = boss or "Trash",
                    pulls = 0, deaths = 0, avoidable = 0, fights = {},
                }
                byKey[key] = block
                out[#out + 1] = block
            end

            block.fights[#block.fights + 1] = fight
            block.pulls = block.pulls + 1
            block.deaths = block.deaths + #fight.entries

            -- HOW MANY OF THEM THE GAME ITSELF CALLED AVOIDABLE, and only
            -- those: a death whose client withheld the flag is counted
            -- nowhere rather than rounded into the flattering answer.
            for _, entry in ipairs(fight.entries) do
                if entry.avoidable == true then
                    block.avoidable = block.avoidable + 1
                end
            end

            -- The clock of a block is its first pull and its last. A pull
            -- saved before the field was kept has neither, so both are taken
            -- as they turn up instead of assumed to be there.
            local when = Plain(fight.when, "string")
            if when then
                if not block.first then block.first = when end
                block.last = when
            end

            -- THESE CAN ARRIVE ON ANY PULL OF THE BLOCK, not only its first:
            -- a fall recorded before ENCOUNTER_START ever named the fight
            -- carries no id and no guide page, and the pull after it does.
            if block.bossID == nil then
                block.bossID = Plain(fight.bossID, "number")
            end
            if block.journal == nil then
                block.journal = Plain(fight.journal, "number")
            end
            if block.instance == nil then
                block.instance = Plain(fight.instance, "string")
            end
            if block.tag == nil then
                block.tag = Plain(fight.kind, "string")
            end
        end
    end

    for _, block in ipairs(out) do
        block.killers = RaidDeaths.RepeatIn(block.fights)
        block.fallen = RaidDeaths.FallenIn(block.fights)
    end
    return out
end

-- What a block cost, in the two numbers and the words the column already
-- uses for them.
function RaidDeaths.BossNote(block)
    if type(block) ~= "table" then return "" end
    local pulls, dead = block.pulls or 0, block.deaths or 0
    return string.format("%d pull%s, %d dead",
        pulls, pulls == 1 and "" or "s", dead)
end

-- When it happened. One clock for a block that is one pull, two for more -
-- and NOTHING at all for pulls saved before the clock was kept, rather than
-- a dash that reads like a value the page failed to find.
function RaidDeaths.BossWhen(block)
    if type(block) ~= "table" or not block.first then return "" end
    if not block.last or block.last == block.first then return block.first end
    return block.first .. " - " .. block.last
end

-- HOW MANY OF THIS FIGHT'S DEATHS THE GAME CALLED AVOIDABLE. Spoken only
-- when there were some: "0 to avoidable damage" under a fight whose client
-- answered nothing would be a clean bill nobody issued.
function RaidDeaths.BossAvoidable(block)
    if type(block) ~= "table" or (block.avoidable or 0) == 0 then return "" end
    return string.format("%d to avoidable damage", block.avoidable)
end

-- WHO FELL ON THIS FIGHT, on one line. The evening's own table names
-- everybody once, over the whole night; this says who it was HERE, which is
-- the question somebody asks between two pulls of the same boss.
local FELL_NAMED = 4
RaidDeaths.FELL_NAMED = FELL_NAMED

function RaidDeaths.FellLine(fallen, named)
    fallen = type(fallen) == "table" and fallen or {}
    if #fallen == 0 then return "" end
    named = named or FELL_NAMED
    local parts = {}
    for index = 1, min(#fallen, named) do
        local person = fallen[index]
        parts[#parts + 1] = string.format("%s %dx",
            person.short or person.name or "?", person.deaths or 0)
    end
    local line = table.concat(parts, ", ")
    if #fallen > named then
        line = line .. string.format(" and %d more", #fallen - named)
    end
    return line
end

-- THE ONE SENTENCE AT THE TOP: which fight of the night cost the most.
--
-- Said only when there is something to compare and one clear answer. A
-- single block IS the evening and says nothing by being its own worst; a tie
-- would name one of two while the page shows both, and a page that picks a
-- winner out of a draw is a page inventing a fact.
function RaidDeaths.NightVerdict(blocks)
    blocks = type(blocks) == "table" and blocks or {}
    if #blocks < 2 then return "" end
    local total, best, most, second = 0, nil, -1, -1
    for _, block in ipairs(blocks) do
        local dead = block.deaths or 0
        total = total + dead
        if dead > most then
            second = most
            best, most = block, dead
        elseif dead > second then
            second = dead
        end
    end
    if not best or most <= second or most <= 0 then return "" end
    return string.format("%s cost the most - %d of %d.",
        best.label or "?", most, total)
end

-- The one line at the top of the evening. Pure, so the wording is checkable.
function RaidDeaths.SessionLine(session)
    local fights = (session and session.fights) or {}
    if #fights == 0 then return "" end
    local deaths = 0
    for _, fight in ipairs(fights) do
        deaths = deaths + #(fight.entries or {})
    end
    local line = string.format("%d pull%s, %d death%s",
        #fights, #fights == 1 and "" or "s",
        deaths, deaths == 1 and "" or "s")
    local first, last = fights[1], fights[#fights]
    if first.when and last.when and first.when ~= last.when then
        line = line .. string.format("  -  %s to %s", first.when, last.when)
    end
    return line
end

-- The sentence about one repeat offender, which is the whole reason for the
-- page: the number of PULLS is what makes it a pattern rather than a moment.
function RaidDeaths.RepeatLine(row)
    if type(row) ~= "table" then return "" end
    if (row.pulls or 0) > 1 then
        return string.format("%d death%s across %d pulls",
            row.deaths, row.deaths == 1 and "" or "s", row.pulls)
    end
    return string.format("%d death%s on one pull",
        row.deaths, row.deaths == 1 and "" or "s")
end

-- And the one about a person. The avoidable count is only spoken when the
-- game answered; "3 deaths" with nothing after it means it did not.
function RaidDeaths.FallenLine(row)
    if type(row) ~= "table" then return "" end
    local line = string.format("%d death%s in %d pull%s",
        row.deaths, row.deaths == 1 and "" or "s",
        row.pulls, row.pulls == 1 and "" or "s")
    if (row.avoidable or 0) > 0 then
        line = line .. string.format(", %d to avoidable damage", row.avoidable)
    end
    return line
end

-- HOW OFTEN A RECAP THAT SAID NOTHING IS ASKED AGAIN.
--
-- Once more, and then never. A recap is written when the death happens, so
-- one that is empty two seconds later is almost certainly empty for good -
-- asking it again every two seconds for the rest of the pull is twenty reads
-- for an answer that will not change, and nothing on screen would look wrong.
-- The one case worth a second chance is the race: the row turning up in the
-- list a moment before its recap is written. That costs exactly one retry.
local RETRIES = 2
RaidDeaths.RETRIES = RETRIES

-- What this pull has already been asked, by recap id.
local function Asked(fight)
    local previous = {}
    if not fight then return previous end
    for _, entry in ipairs(fight.entries or {}) do
        if entry.recapID then previous[entry.recapID] = entry end
    end
    return previous
end

-- Whether that answer is final: it worked, or it has been asked enough.
function RaidDeaths.Settled(entry)
    if not entry then return false end
    if entry.blow then return true end
    return (entry.tries or 0) >= RETRIES
end

-- The key of the fight the meter is holding RIGHT NOW, kept by nobody.
-- What Clear writes down and Capture then refuses.
function RaidDeaths.HoldingKey()
    local rows = RaidDeaths.Read()
    if not rows or #rows == 0 then return nil end
    local entries, timed = RaidDeaths.Timeline(rows)
    if not timed then return nil end
    return RaidDeaths.FightKey(entries)
end

-- Read what the client is holding and keep it if it is worth keeping. Only a
-- TIMED list is captured: an untimed one is Overall, which is not a fight and
-- would overwrite a good capture with a worse one.
function RaidDeaths.Capture()
    local rows, _, duration = RaidDeaths.Read()
    if not rows or #rows == 0 then return nil end

    local entries, timed = RaidDeaths.Timeline(rows)
    if not timed then return nil end

    local key = RaidDeaths.FightKey(entries)

    -- THE FIGHT A CLEAR DISMISSED STAYS DISMISSED for as long as the meter
    -- holds it. The meter cannot be emptied by an addon, so without this
    -- mark the very next capture - the window opening, the combat tick,
    -- the end of a fight - put the cleared pull straight back (owner,
    -- 2026-08-24: "todays list ... kann man nicht clearen"). A DIFFERENT
    -- fight lifts the mark: recap ids are reused within a session, and a
    -- mark that outlived its fight would eat a later pull.
    if key and key == RaidDeaths.dismissed then return nil end
    RaidDeaths.dismissed = nil

    local last = RaidDeaths.log[#RaidDeaths.log]
    local previous = Asked(last and last.key == key and last or nil)

    for _, entry in ipairs(entries) do
        local was = entry.recapID and previous[entry.recapID]
        if RaidDeaths.Settled(was) then
            Reuse(entry, was)
        else
            RaidDeaths.Resolve(entry)
            if entry.recapID then
                entry.tries = ((was and was.tries) or 0) + 1
            end
        end
    end

    local where, whereShort, instance, journal, boss, kind, bossID =
        ns.Death.Where()
    local fight = RaidDeaths.Remember(RaidDeaths.log, {
        key = key,
        at = GetTime(),
        when = date("%H:%M:%S"),
        -- THE MOMENT, beside the words. `when` is a string fixed at capture
        -- and cannot be re-read in another format; this can, and a list
        -- drawn half in one format and half in the other is worse than
        -- either. Both are kept: a fight saved before this existed has only
        -- the words, and they still say the right thing.
        stamp = time(),
        where = where,
        whereShort = whereShort,
        instance = instance,
        journal = journal,
        -- WHICH BOSS, or nil for trash. Read from ENCOUNTER_START rather
        -- than from the label above, which holds either a boss or a
        -- difficulty and cannot say which.
        boss = boss,
        -- AND THE DIFFICULTY, for the same reason from the other side. The
        -- header over eleven pulls of one key has to say "M+11", and every
        -- one of those pulls may have been a boss - in which case not one
        -- of them has the word left in `whereShort`.
        kind = kind,
        -- AND THE FIGHT'S OWN ID, which is what finds the boss's page in the
        -- Adventure Guide. The name alone would only work in one language.
        bossID = bossID,
        duration = duration,
        entries = entries,
        culprits = RaidDeaths.Culprits(entries),
    }, FIGHTS_KEPT)

    -- The evening's thin copy, by the same rule and in the same breath: a
    -- pull that is in one list and not the other is the bug this would
    -- otherwise grow.
    RaidDeaths.RememberSession(RaidDeaths.session, RaidDeaths.Light(fight),
        RaidDeaths.Today(), SESSION_KEPT)

    -- Every tick rather than at the end of the pull. Saved variables only
    -- reach the disk at logout, so this is not about crashes - it is about
    -- the in-memory copy being CURRENT when they type /reload in the middle
    -- of a fight, which is when they type it.
    RaidDeaths.Save()
    return fight
end

-- EMPTYING WHICHEVER LIST IS BEING READ - and refusing its resurrection.
-- One method rather than button-body code, so the desk can press it.
-- BOTH LISTS, from either page. They used to be two things a button could
-- empty separately, and the reason that was right died the moment the column
-- started drawing the evening: emptying only the log left sixty rows
-- standing in a column the button had just claimed to clear, and emptying
-- only the tally left five.
function RaidDeaths:Clear()
    RaidDeaths.session = { day = RaidDeaths.Today(), fights = {} }
    RaidDeaths.log = {}
    RaidDeaths.showing = nil
    RaidDeaths.sideOffset = 0
    -- AND WHAT WAS FOLDED IS FORGOTTEN WITH IT. The keys name places,
    -- not pulls, so one left standing would fold the next visit to the
    -- same dungeon shut - a column that opens closed for a reason nobody
    -- on screen can see.
    RaidDeaths.collapsed = {}
    RaidDeaths.overCollapsed = {}
    RaidDeaths.reading = nil
    RaidDeaths.dismissed = RaidDeaths.HoldingKey()
    RaidDeaths.Save()
    RaidDeaths:Refresh()
    RaidDeaths.RefreshIcon()
end

function RaidDeaths.Newest()
    return RaidDeaths.log[#RaidDeaths.log]
end

---------------------------------------------------------------------------
-- Surviving a reload
--
-- The same argument the own-death log made, and it is stronger here: a
-- reload happens after every settings change and every error, and the side
-- list is a list of PULLS. One that empties itself every time they press
-- /reload is a list of one thing.
--
-- The two rules are Death's, and so are the two functions that enforce them:
-- only what is READABLE goes in, copied field by field rather than the table
-- being handed over whole, and a fight nothing could be read out of is not
-- kept. `at` is deliberately dropped - it is a GetTime stamp, and GetTime
-- restarts with the client.
---------------------------------------------------------------------------

-- What a mob did, reduced to what may be written to disk. Same rule as every
-- other field down here: copied by name, verified, never handed over whole -
-- and the ability list is a list of TABLES, so each one is walked too.
function RaidDeaths.PlainSummary(summary)
    if type(summary) ~= "table" then return nil end
    local out = {
        hits = Plain(summary.hits, "number"),
        total = Plain(summary.total, "number"),
        biggest = Plain(summary.biggest, "number"),
        spells = {},
    }
    if not out.hits then return nil end
    for _, spell in ipairs(summary.spells or {}) do
        local name = Plain(spell.name, "string")
        if name then
            out.spells[#out.spells + 1] =
                { name = name, spellID = Plain(spell.spellID, "number") }
        end
    end
    return out
end

function RaidDeaths.Persist(fight)
    if not (type(fight) == "table" and type(fight.entries) == "table"
        and #fight.entries > 0) then
        return nil
    end

    local out = {
        key = Plain(fight.key, "number"),
        when = Plain(fight.when, "string"),
        where = Plain(fight.where, "string"),
        whereShort = Plain(fight.whereShort, "string"),
        -- The instance's name and its guide id, for the side column's third
        -- line and its tile. They were recorded and shown for an evening
        -- and gone after every reload, because THIS list did not carry them
        -- while Light's did (owner, 2026-08-16: "auf der rechten seite fehlt
        -- das dungeon bild"): a field a save whitelists in one copy and not
        -- the other lives exactly until the next /reload.
        instance = Plain(fight.instance, "string"),
        journal = Plain(fight.journal, "number"),
        boss = Plain(fight.boss, "string"),
        kind = Plain(fight.kind, "string"),
        bossID = Plain(fight.bossID, "number"),
        stamp = Plain(fight.stamp, "number"),
        duration = Plain(fight.duration, "number"),
        entries = {},
    }

    for _, entry in ipairs(fight.entries) do
        local name = Plain(entry.name, "string")
        if name then
            local blow = type(entry.blow) == "table" and entry.blow or nil
            -- The story of the last seconds, trimmed by the same function
            -- that trimmed it on the way in. Running it twice drops nothing
            -- the first pass kept, and the count of what WAS dropped is
            -- carried rather than recomputed - a save and a load must not
            -- quietly turn "6 older hits are not here" into silence.
            local events, cut = RaidDeaths.PlainEvents(entry.events)
            local dropped = (Plain(entry.dropped, "number") or 0) + cut
            out.entries[#out.entries + 1] = {
                events = events,
                dropped = dropped > 0 and dropped or nil,
                maxHP = Plain(entry.maxHP, "number"),
                name = name,
                short = Plain(entry.short, "string") or name,
                class = Plain(entry.class, "string"),
                spec = Plain(entry.spec, "number"),
                at = Plain(entry.at, "number"),
                gap = Plain(entry.gap, "number"),
                recapID = Plain(entry.recapID, "number"),
                you = entry.you == true,
                seq = Plain(entry.seq, "number") or 0,
                blowWhy = Plain(entry.blowWhy, "string"),
                blow = blow and {
                    who = Plain(blow.who, "string"),
                    spell = Plain(blow.spell, "string"),
                    spellID = Plain(blow.spellID, "number"),
                    amount = Plain(blow.amount, "number"),
                    overkill = Plain(blow.overkill, "number"),
                    art = ns.Death.PlainArt(blow.art),
                    -- A boolean, and only a boolean: nil has to stay nil so
                    -- "the client did not say" survives the disk as itself
                    -- rather than coming back as "not avoidable".
                    avoidable = Plain(blow.avoidable, "boolean"),
                    summary = RaidDeaths.PlainSummary(blow.summary),
                } or nil,
                real = type(entry.real) == "table" and {
                    who = Plain(entry.real.who, "string"),
                    spell = Plain(entry.real.spell, "string"),
                    spellID = Plain(entry.real.spellID, "number"),
                    amount = Plain(entry.real.amount, "number"),
                    landed = Plain(entry.real.landed, "number"),
                    avoidable = Plain(entry.real.avoidable, "boolean"),
                } or nil,
            }
        end
    end

    if #out.entries == 0 then return nil end
    return out
end

function RaidDeaths.Restore(stored)
    local log = {}
    if type(stored) ~= "table" then return log end
    for _, fight in ipairs(stored) do
        local kept = RaidDeaths.Persist(fight)
        if kept then
            -- The count is DERIVED rather than stored, so a better rule
            -- written next month applies to the fights already on disk. Same
            -- reason Death.Restore re-runs its analysis.
            kept.culprits = RaidDeaths.Culprits(kept.entries)
            log[#log + 1] = kept
        end
    end
    while #log > FIGHTS_KEPT do table.remove(log, 1) end
    return log
end

-- The evening, read back off the disk. Every fight goes through Light again
-- rather than being trusted - it is the same function that put it there, and
-- a saved-variables file is a text file anybody can edit. A tally from
-- ANOTHER DAY is dropped here rather than shown under the word "tonight".
function RaidDeaths.RestoreSession(stored, today)
    local session = { day = today, fights = {} }
    if type(stored) ~= "table" then return session end
    if type(stored.day) ~= "string" or stored.day ~= today then return session end
    for _, fight in ipairs(stored.fights or {}) do
        local kept = RaidDeaths.Light(fight)
        if kept then session.fights[#session.fights + 1] = kept end
    end
    while #session.fights > SESSION_KEPT do table.remove(session.fights, 1) end
    return session
end

-- TWO STORES, because they are two different things. The log is a handful of
-- pulls in full and is rewritten every two seconds during a fight; the tally
-- is one thin line per pull for one day. Folding the second into the first
-- would have meant a migration of everything already on their disk to add a
-- field, for no gain.
local function Store()
    if not ns.account then return nil end
    ns.account.raidDeaths = ns.account.raidDeaths or {}
    return ns.account.raidDeaths
end

local function SessionStore()
    if not ns.account then return nil end
    ns.account.raidSession = ns.account.raidSession or {}
    return ns.account.raidSession
end

function RaidDeaths.Save()
    local key = ns.CharacterKey()
    if not key then return end

    local store = Store()
    if store then
        local out = {}
        for _, fight in ipairs(RaidDeaths.log) do
            local kept = RaidDeaths.Persist(fight)
            if kept then out[#out + 1] = kept end
        end
        store[key] = out
    end

    local sessions = SessionStore()
    if sessions then
        local session = RaidDeaths.session or {}
        local out = { day = Plain(session.day, "string"), fights = {} }
        for _, fight in ipairs(session.fights or {}) do
            local kept = RaidDeaths.Light(fight)
            if kept then out.fights[#out.fights + 1] = kept end
        end
        sessions[key] = out
    end
end

-- THE PLACE, MENDED FROM THE OTHER COPY. Pulls saved before Persist
-- carried the instance and its guide id have neither, while the evening's
-- thin copy of the same pull - same key - has had both from the start.
-- Read back together, the full log takes them from there, so the pulls they
-- already has get their tile too instead of only the pulls from now on.
-- Pure; the log is changed in place and returned.
function RaidDeaths.Mend(log, session)
    local byKey = {}
    for _, light in ipairs((session and session.fights) or {}) do
        if light.key then byKey[light.key] = light end
    end
    for _, fight in ipairs(log or {}) do
        local light = fight.key and byKey[fight.key]
        if light then
            if fight.instance == nil then fight.instance = light.instance end
            if fight.journal == nil then fight.journal = light.journal end
        end
    end
    return log
end

function RaidDeaths.Load()
    local key = ns.CharacterKey()
    if not key then return end
    local store = Store()
    if store then RaidDeaths.log = RaidDeaths.Restore(store[key]) end
    local sessions = SessionStore()
    if sessions then
        RaidDeaths.session = RaidDeaths.RestoreSession(sessions[key],
            RaidDeaths.Today())
    end
    RaidDeaths.Mend(RaidDeaths.log, RaidDeaths.session)
    RaidDeaths.showing = nil
    RaidDeaths.RefreshIcon()
end

-- WHICH PULL IS BEING LOOKED AT, named by the pull's own id rather than by
-- where it sits in the list.
--
-- It used to be a position, and a position is only a name for as long as
-- nothing joins or leaves. Both happen: the evening drops its oldest at
-- sixty, and until it does, every new pull pushes the numbering along - so a
-- window left open on the third wipe of the night was quietly showing the
-- fourth an hour later. The id survives both, and it survives the capture
-- tick REPLACING the running pull's table every two seconds, which a
-- reference to the table itself would not.
--
-- Nil means the newest, exactly like Death.showing. A pull whose recap never
-- gave an id cannot be named this way; there is nothing about such a fight
-- that a second one could not share, so it falls back to the newest rather
-- than being given a mechanism of its own to go wrong.
function RaidDeaths.Pick(pulls, showing)
    pulls = type(pulls) == "table" and pulls or {}
    local total = #pulls
    if total == 0 then return nil, nil end
    if showing ~= nil then
        for index = 1, total do
            if pulls[index].key == showing then return pulls[index], index end
        end
    end
    return pulls[total], total
end

-- The chosen pull, its position in the merged list, and the list itself -
-- the column needs all three, and building it twice per paint would be two
-- answers to one question.
function RaidDeaths.Selected()
    local pulls = RaidDeaths.Pulls(RaidDeaths.log, RaidDeaths.session)
    local fight, index = RaidDeaths.Pick(pulls, RaidDeaths.showing)
    -- A CHOICE THAT NAMES NOTHING IS DROPPED rather than kept: an id nobody
    -- answers to sits there until the meter hands the SAME id to a later
    -- pull - recap ids are reused within a session - and that pull would
    -- then open itself.
    if not fight then
        RaidDeaths.showing = nil
        return nil, nil, pulls
    end
    if RaidDeaths.showing ~= nil and fight.key ~= RaidDeaths.showing then
        RaidDeaths.showing = nil
    end
    return fight, index, pulls
end

-- WHAT TO SHOW: the pull that is selected, or - when nothing has been
-- captured at all - whatever the client still has lying about with no clock
-- on it. Returns entries, an info table and which of the two answered, so
-- the window says where its numbers came from rather than implying.
function RaidDeaths.Best()
    local fight = RaidDeaths.Selected()
    if fight then
        return fight.entries, {
            -- NOT FOR A PULL OUT OF THE TALLY. The clock on this page is
            -- per DEATH - "fell at 0:41" - and the thin copy keeps the
            -- pull's length but not the moment inside it. Read through
            -- Clock, a nil would print a time that was never measured.
            timed = fight.thin ~= true,
            thin = fight.thin == true,
            duration = fight.duration,
            label = fight.whereShort and (fight.whereShort .. ", " .. fight.when)
                or fight.when,
            where = fight.where,
            instance = fight.instance,
            journal = fight.journal,
            when = fight.when,
            culprits = fight.culprits or RaidDeaths.Culprits(fight.entries),
        }, "kept"
    end

    local live, why, info = RaidDeaths.Collect()
    if live and info then return live, info, "session" end
    return nil, nil, why or "nothing has died yet"
end

---------------------------------------------------------------------------
-- Watching for the end of a pull
--
-- Two doors, because neither is enough on its own. The tick catches a fight
-- that never formally ends - a long trash pull, a key where combat never
-- drops - and leaving combat catches the last few seconds the tick would
-- have missed. Both are cheap: the recaps are read once each.
---------------------------------------------------------------------------
local TICK = 2
local ticker

local function StartWatching()
    if ticker then return end
    ticker = C_Timer.NewTicker(TICK, function()
        if not UnitAffectingCombat("player") then return end
        RaidDeaths.Capture()
    end)
end

local function StopWatching()
    if ticker then ticker:Cancel() end
    ticker = nil
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:RegisterEvent("ENCOUNTER_END")
watcher:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        StartWatching()
        return
    end
    StopWatching()
    -- One last read on the way out: the deaths of the final seconds are the
    -- ones a wipe is actually about.
    RaidDeaths.Capture()
    RaidDeaths.RefreshIcon()
end)

---------------------------------------------------------------------------
-- Saying it in chat
---------------------------------------------------------------------------

-- Minutes and seconds, the way a fight is talked about.
function RaidDeaths.Clock(seconds)
    if type(seconds) ~= "number" or seconds < 0 then return "--:--" end
    local whole = floor(seconds + 0.5)
    return string.format("%d:%02d", floor(whole / 60), whole % 60)
end

-- A name in its class colour. The colour table is the client's own and may
-- be missing a class we were handed, so a plain name is the fallback rather
-- than a nil concatenation.
function RaidDeaths.Coloured(short, class)
    local colour = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if type(colour) ~= "table" or not colour.r then return short end
    return string.format("|cff%02x%02x%02x%s|r",
        floor(colour.r * 255 + 0.5), floor(colour.g * 255 + 0.5),
        floor(colour.b * 255 + 0.5), short)
end

-- One line about one death, without touching the client. Pure so the shape
-- of the line is checkable; the printer below only chooses what to feed it.
function RaidDeaths.Line(entry, timed)
    local when = timed and RaidDeaths.Clock(entry.at) or " --:--"
    if entry.gap and entry.gap > 0 then
        when = when .. string.format(" |cff888888+%ds|r", floor(entry.gap + 0.5))
    end

    local who = RaidDeaths.Coloured(entry.short, entry.class)
    if entry.you then who = who .. " |cffffd100(you)|r" end

    local what
    local blow = entry.blow
    if blow then
        what = (blow.who or "?") .. " - " .. (blow.spell or "?")
        if type(blow.amount) == "number" and blow.amount > 0 then
            what = what .. "  " .. ns.ShortNumber(blow.amount)
        end
        if type(blow.overkill) == "number" and blow.overkill > 0 then
            what = what .. string.format("  |cffe06c5e%s over|r",
                ns.ShortNumber(blow.overkill))
        end
    else
        what = "|cff888888" .. (entry.blowWhy or "nothing readable") .. "|r"
    end

    return string.format("  %s  %s  %s", when, who, what)
end

-- How many culprits the summary prints before it says how many it left out.
local CULPRITS_SHOWN = 5

-- THE ONE SENTENCE A RAID LEADER WANTS, built from what the client itself
-- says rather than from anything this addon guessed.
--
-- Three parts, each dropped when it has nothing to add: what the wipe was
-- (something that killed more than one person), how fast it happened, and
-- how many of them the GAME calls avoidable. The last one is the reason to
-- open this window at all - it is Blizzard's own verdict on whether somebody
-- stood in it, and it is worth more than every number beside it.
--
-- "The client did not say" is never rounded into "not avoidable". A window
-- that reports a raid as blameless because a field was withheld is worse
-- than one that says nothing.
function RaidDeaths.Verdict(entries, culprits)
    entries = entries or {}
    if #entries == 0 then return "" end

    local parts = {}

    local worst = (culprits or {})[1]
    if worst and worst.count > 1 then
        parts[#parts + 1] = string.format("%s killed %d of them",
            worst.spell or worst.who or "?", worst.count)
    end

    -- How long the dying took. Four in two seconds is a mechanic; four over
    -- a minute is four separate stories.
    local first, last = entries[1], entries[#entries]
    if #entries > 1 and first.at and last.at then
        local span = last.at - first.at
        parts[#parts + 1] = string.format("%d deaths in %ds",
            #entries, floor(span + 0.5))
    end

    local yes, no, unknown = RaidDeaths.Avoidable(entries)
    if yes > 0 then
        parts[#parts + 1] = string.format(
            "%d of %d to damage the game calls avoidable", yes, #entries)
    elseif no > 0 and unknown == 0 then
        parts[#parts + 1] = "none of it was avoidable damage"
    end

    if #parts == 0 then return "" end
    return table.concat(parts, ".  ") .. "."
end

-- WHETHER THE COUNT IS WORTH PRINTING. Four deaths to four different things
-- listed four times as "1 x" is the same four lines again, one word shorter.
-- The summary earns its space only when something killed more than one.
function RaidDeaths.WorthCounting(culprits)
    for _, culprit in ipairs(culprits or {}) do
        if culprit.count > 1 then return true end
    end
    return false
end

function RaidDeaths:Dump()
    local entries, info, source = RaidDeaths.Best()
    if not (entries and info) then
        ns.Print("|cffffd100raid deaths|r - " .. tostring(source))
        return
    end

    local header = string.format("|cffffd100raid deaths|r - %d in %s",
        #entries, info.label)
    if info.duration then
        header = header .. ", " .. RaidDeaths.Clock(info.duration)
            .. (source == "session" and " of session" or " long")
    end
    if source == "kept" then
        header = header .. " |cff888888(the last pull, kept - the game forgets "
            .. "it when the next one starts)|r"
    elseif not info.timed then
        header = header .. " |cff888888(no clock left on these - ordered by "
            .. "recap id)|r"
    end
    ns.Print(header)

    for _, entry in ipairs(entries) do
        ns.Print(RaidDeaths.Line(entry, info.timed))
    end

    local culprits = info.culprits
    if not RaidDeaths.WorthCounting(culprits) then return end
    ns.Print("  |cff7ec6d4what did the killing|r:")
    for index = 1, min(#culprits, CULPRITS_SHOWN) do
        local culprit = culprits[index]
        ns.Print(string.format("    %d x %s - %s",
            culprit.count, culprit.who, culprit.spell))
    end
    if #culprits > CULPRITS_SHOWN then
        ns.Print(string.format("    |cff888888and %d more|r",
            #culprits - CULPRITS_SHOWN))
    end
end

-- Exported so the window shows the same number of culprits as the chat line
-- does, rather than each carrying its own idea of "a few".
RaidDeaths.CULPRITS_SHOWN = CULPRITS_SHOWN

---------------------------------------------------------------------------
-- The window
--
-- One row per death, in the order they fell: when, the killer's face, who
-- died, and what ended them. Deliberately NOT a second page of the death
-- window - that one is about ONE fall in detail, this is about a pull, and
-- the two answer different questions from different sides.
---------------------------------------------------------------------------
local frame
-- The row got taller because the two pictures on it got bigger: a face drawn
-- into 22 pixels was a smudge, and the whole reason for putting one beside a
-- name is that you can tell it apart from the next one.
local ROW_H, FACE, SPEC = 30, 26, 20
-- The magnifier column in front of the clock: it is the only thing on the row
-- that says "there is more behind this one".
local GLASS, COL_WHEN = 14, 20
-- BIGGER THAN THE OPTIONS WINDOW NOW. It used to be 820 to match it exactly,
-- so two of this addon's windows would stack rather than sit beside each
-- other - a tidy idea that cost the thing its room. Owner, with a photograph
-- of the detail page: "paar layout fehler, mach das fenster ruhig groesser
-- hoeher etc." This holds a table of ten hits with four columns and a list of
-- pulls beside it; matching another window's width was never worth a squeeze.
-- 640 and 232, from 580 and 196 (owner, 2026-08-16): every pull in the
-- side column carries a third line now - the instance's name with the
-- guide's tile beside it - and the column had to be wider and the rows
-- taller for it. Eight pulls fit at 50; the desk does the sum below.
-- BIGGER AGAIN. Owner, 2026-08-25: "wir koennen das death log auch groesser
-- machen, und seiten ein ausklappbar, kann sich jeder anzeigen was er will."
-- The height buys rows of dead in the table; the width buys the column its
-- second line back, now that a pull says what killed people as well as how
-- many fell.
local WIDTH, HEIGHT = 1096, 724
-- THE SAME WIDTH IN BOTH WINDOWS. It lives on ns.Death because that file
-- loads first and owns the other column; two numbers for one measurement is
-- how they drifted to 264 and 232 in the first place.
local SIDE_W = ns.Death.SIDE_W

-- TWO ROW HEIGHTS, because the column has two kinds of row now: a place, and
-- a pull under it. The place is the taller of the two - it carries the
-- guide's tile - and the pull is indented under it.
local SIDE_RUN_H, SIDE_BOSS_H, SIDE_PULL_H, SIDE_SESSION_H = 46, 30, 40, 40
local SIDE_ART_W, SIDE_ART_H = 52, 32
-- The boss's face on a pull row: as tall as one of its two lines, so a row
-- with a picture is the same height as one without.
local SIDE_FACE = 22
-- How far a pull sits in from the edge its place header starts at, and where
-- the header's own text starts - to the right of the chevron.
-- THE INDENT LADDER, one rung per level, and BOTH numbers are written down.
--
-- It used to be one number per level with the text placed at "+8" and the
-- chevron at "-5", and those two sums did not know that a glyph is fourteen
-- pixels wide: the fight's chevron ran under the first letter of its own
-- name (owner, 2026-08-29: "das chevron vor Trash ist zu nah dran"). Where
-- the mark sits and where the words start are two facts, so they are two
-- numbers, and the gap between them is visible here rather than implied.
local L_PLACE_CHEV, L_PLACE_TEXT = 6, 26
local L_FIGHT_CHEV, L_FIGHT_TEXT = 18, 38
local L_LEAF_NUM, L_LEAF_TEXT = 22, 42
local SIDE_TOP, SIDE_BOTTOM = 8, 40
local SIDE_TITLE, SIDE_TITLE_GAP, SIDE_GAP = 18, 6, 2

-- THE NUMBERS THE COLUMN IS BUILT FROM, exported so the arithmetic can be
-- checked without a screen.
--
-- It used to carry a row COUNT, and the check on it was that eight rows of
-- fifty fit between the header and the buttons. There is no count any more:
-- how many rows are on screen depends on how many places the evening had and
-- which of them are folded away. So the numbers here are the ones the rows
-- are DRAWN with, the room is derived from them in one place below, and how
-- many fit is asked of the list itself.
--
--   top     where the column starts, under the window's header
--   bottom  the room the two buttons keep for themselves
--   title   the "N pulls in 2 places" line above the rows
--   session the evening's own row, which is not one of the items
RaidDeaths.LAYOUT = {
    width = WIDTH, height = HEIGHT, sideW = SIDE_W,
    runH = SIDE_RUN_H, bossH = SIDE_BOSS_H, pullH = SIDE_PULL_H,
    session = SIDE_SESSION_H,
    sideGap = SIDE_GAP, top = SIDE_TOP, bottom = SIDE_BOTTOM,
    title = SIDE_TITLE, titleGap = SIDE_TITLE_GAP,
}

-- HOW TALL ONE ITEM OF THE COLUMN IS. Handed to the fit arithmetic rather
-- than written into it, so there is one answer to this question and the
-- painter and the sum cannot disagree about a row's height.
function RaidDeaths.SideHeight(item)
    local L = RaidDeaths.LAYOUT
    local kind = type(item) == "table" and item.kind or nil
    if kind == "run" then return L.runH end
    if kind == "boss" then return L.bossH end
    return L.pullH
end

-- THE ROOM THE COLUMN'S ROWS HAVE, from the window's own numbers.
--
-- Not from `side:GetHeight()`, though the frame knows it: that answer only
-- exists once the client has laid the window out, and the whole point of
-- keeping these numbers here is that the sum can be done on a desk with no
-- screen attached - which is where the eight-rows-of-fifty overflow was
-- caught the last three times.
function RaidDeaths.SideRoom()
    local L = RaidDeaths.LAYOUT
    local headerH = (ns.UI and ns.UI.HEADER_H) or 0
    return L.height - headerH - L.top - L.bottom
        - L.title - L.titleGap - L.session - L.sideGap
end
-- One line of the evening's two tables.
local TALLY_ROW_H = 24
local TALLY_PIC, TALLY_PIC_X = 18, 56  -- the picture column on a tally row
-- How many of each are drawn before the page says how many it left out. No
-- silent caps: a list that stops at eight and does not say so reads as a
-- list of eight.
local TALLY_SHOWN = 8

-- THE FIGHT HEADER ON THE EVENING'S PAGE. Taller than a tally row because it
-- is a different KIND of thing rather than a bigger one - the same reason the
-- column's place header carries a ground of its own.
local BOSS_ROW_H = 26
local BOSS_ROW_GAP = 2
-- The chevron's column, the portrait's, and where the name starts once a
-- portrait is in front of it. Written once and read by both the builder and
-- the painter: two sums for one column is how a name ends up on top of a face.
local BOSS_CHEV_X, BOSS_PIC_X = 6, 22
local BOSS_TEXT_X = BOSS_PIC_X + TALLY_PIC + 6
-- HOW MANY ABILITIES ARE NAMED UNDER ONE FIGHT. Fewer than the evening's
-- eight: a night with five bosses would otherwise be forty rows of mechanic
-- and the shape of the page - which fight cost what - would be gone.
local BLOCK_SHOWN = 4
RaidDeaths.BLOCK_SHOWN = BLOCK_SHOWN

-- A hover target over a font string. A string cannot take the mouse itself,
-- and the two things worth asking about here - the mob and the ability - sit
-- side by side in one line, so one tooltip for the whole row would have to
-- guess which of them was meant.
local function HoverOver(row, label, onEnter)
    local hit = CreateFrame("Frame", nil, row)
    hit:SetAllPoints(label)
    hit:EnableMouse(true)
    hit:SetScript("OnEnter", function(self)
        if row.Lit then row.Lit(true) end
        if not (GameTooltip and row.entry) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        onEnter(row.entry)
        GameTooltip:Show()
    end)
    hit:SetScript("OnLeave", function()
        if row.Lit then row.Lit(false) end
        if GameTooltip then GameTooltip:Hide() end
    end)
    -- The click belongs to the ROW; this frame is only sitting on top of it
    -- for the sake of a tooltip.
    hit:SetScript("OnMouseUp", function()
        if row.Open then row.Open() end
    end)
    return hit
end

local function BuildRow(parent)
    local UI, C = ns.UI, ns.UI.C
    -- A BUTTON, because the row opens the story behind it. The three hover
    -- targets that sit on top of it - the face, the killer, the ability -
    -- take the mouse for their own tooltips, so each of them forwards the
    -- click and the highlight rather than swallowing them. Without that,
    -- two thirds of the row would be dead to a click and nothing would say
    -- why.
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)

    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints(row)
    row.hover:SetColorTexture(C.control[1], C.control[2], C.control[3], 0.7)
    row.hover:Hide()

    -- Lit only when there is something behind the row to open.
    local function Lit(on)
        row.hover:SetShown(on and RaidDeaths.Openable(row.entry) or false)
    end
    row.Lit = Lit

    local function Open()
        if row.index then RaidDeaths:Open(row.index) end
    end
    row.Open = Open

    row:SetScript("OnClick", Open)
    row:SetScript("OnEnter", function() Lit(true) end)
    row:SetScript("OnLeave", function() Lit(false) end)

    -- THE MAGNIFIER, and it is the whole affordance. The owner's ask: "damit
    -- man sieht das es Details gibt." Shown ONLY on a row that can be opened,
    -- so the column answers "which of these have a story" at a glance instead
    -- of being a decoration in front of every line.
    row.glass = row:CreateTexture(nil, "ARTWORK")
    row.glass:SetSize(GLASS, GLASS)
    row.glass:SetPoint("LEFT", row, "LEFT", 1, 0)
    row.glass:Hide()

    -- THE TWO COLUMNS THAT SAY WHAT IT COST, both in the harm red: when it
    -- happened and how much it was. The two in between say what to point at
    -- and wear the orange. Nothing on the row is decoration.
    row.when = UI.Label(row, "", UI.FS.meta, C.harm)
    row.when:SetPoint("LEFT", row, "LEFT", COL_WHEN, 0)
    row.when:SetWidth(46)
    row.when:SetJustifyH("LEFT")

    -- WHAT THEY WERE PLAYING, in front of their name. The owner's ask, and it
    -- is the one thing a name alone never says: "Grauertiger died" reads
    -- completely differently depending on whether that was the tank.
    row.spec = row:CreateTexture(nil, "ARTWORK")
    row.spec:SetSize(SPEC, SPEC)
    row.spec:SetPoint("LEFT", row.when, "RIGHT", 2, 0)
    row.spec:Hide()

    row.who = UI.Label(row, "", UI.FS.row, C.text)
    row.who:SetPoint("LEFT", row.spec, "RIGHT", 6, 0)
    row.who:SetWidth(150)
    row.who:SetJustifyH("LEFT")
    row.who:SetWordWrap(false)

    -- AND THE MOB IN FRONT OF ITS OWN NAME, which is where they moved it: a
    -- face sitting in the WHEN column belonged to nothing on the line.
    row.face = ns.Death.CreateFace(row, FACE)
    row.face:SetPoint("LEFT", row.who, "RIGHT", 6, 0)

    row.killer = UI.Label(row, "", UI.FS.meta, C.hot)
    row.killer:SetPoint("LEFT", row.face, "RIGHT", 6, 0)
    row.killer:SetWidth(140)
    row.killer:SetJustifyH("LEFT")
    row.killer:SetWordWrap(false)

    row.spell = UI.Label(row, "", UI.FS.meta, C.hot)
    row.spell:SetPoint("LEFT", row.killer, "RIGHT", 6, 0)
    row.spell:SetPoint("RIGHT", row, "RIGHT", -70, 0)
    row.spell:SetJustifyH("LEFT")
    row.spell:SetWordWrap(false)

    -- EIGHT IN FROM THE EDGE, like the clock on the left: the hover bed
    -- ran exactly to the last digit and stopped there (owner, 2026-08-16:
    -- "die hintergrundfarbe geht genau bis zu den zahlen"), so the row
    -- read as cut off on the right. The head's caption sits on the same 8.
    row.amount = UI.Label(row, "", UI.FS.meta, C.harm)
    row.amount:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.amount:SetJustifyH("RIGHT")

    -- THE MOB. There is no client API that turns a creature id into a
    -- tooltip - SetUnit wants a unit token and the thing is long dead - so
    -- this says what we actually know about it, which is more than the row
    -- shows: what it did here, and how many of them it did it to.
    -- THE MOB, as the big tip: the picture at a size you can recognise, and
    -- everything it did to this person in these seconds. The same tip the
    -- replay's marks and the death window's portrait show.
    local function ShowEnemy(self)
        -- The row underneath stays lit while the mouse is over one of its
        -- own hover targets: the highlight follows the ROW, not whichever
        -- frame happens to be on top of it.
        Lit(true)
        local entry = row.entry
        local blow = entry and entry.blow
        if not (blow and blow.who) then return end
        local killed = entry.killedHere or 1
        ns.Death.ShowEnemyTip(self, {
            who = blow.who,
            art = blow.art,
            summary = blow.summary,
            note = killed > 1
                and string.format("It killed %d of the group on this pull.",
                    killed) or nil,
        })
    end
    local function HideEnemy()
        Lit(false)
        ns.Death.HideEnemyTip()
    end

    row.killerHit = CreateFrame("Frame", nil, row)
    row.killerHit:SetAllPoints(row.killer)
    row.killerHit:EnableMouse(true)
    row.killerHit:SetScript("OnEnter", ShowEnemy)
    row.killerHit:SetScript("OnLeave", HideEnemy)
    row.killerHit:SetScript("OnMouseUp", Open)

    -- And the face itself, which is the thing they actually point at.
    row.face:EnableMouse(true)
    row.face:SetScript("OnEnter", ShowEnemy)
    row.face:SetScript("OnLeave", HideEnemy)
    row.face:SetScript("OnMouseUp", Open)

    -- THE ABILITY, through the client's own tooltip. A melee swing has no
    -- spell to ask about, so the row says what it knows itself rather than
    -- showing an empty frame - the death window's rule, and the same code
    -- shape, because a tooltip that silently shows nothing is worse than no
    -- tooltip at all.
    row.spellHit = HoverOver(row, row.spell, function(entry)
        local blow = entry.blow
        local shown = false
        if blow and blow.spellID then
            shown = pcall(GameTooltip.SetSpellByID, GameTooltip, blow.spellID)
        end
        if not shown then
            GameTooltip:ClearLines()
            GameTooltip:AddLine((blow and blow.spell) or "?", 1, 1, 1)
        end
        if blow and blow.amount then
            GameTooltip:AddLine(ns.ShortNumber(blow.amount) .. " on the blow "
                .. "that finished them", 0.61, 0.64, 0.69, true)
        end
        if blow and blow.overkill then
            GameTooltip:AddLine(ns.ShortNumber(blow.overkill)
                .. " of it was overkill", 0.61, 0.64, 0.69)
        end

        -- WHAT ACTUALLY DROPPED THEM. With most of the killing blow wasted
        -- on a corpse, the hit worth talking about landed earlier, and this
        -- is the line that says which one.
        if entry.real then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string.format(
                "The hit that mattered: %s - %s for %s",
                entry.real.who or "?",
                ns.Death.PlainText(entry.real.spell or "?"),
                ns.ShortNumber(entry.real.landed or 0)), 1, 0.82, 0, true)
        end

        -- THE GAME'S OWN VERDICT, and only when the game gave one. Silence
        -- when it did not: "the client withheld it" must never be drawn as
        -- "nobody stood in anything".
        local flag = blow and blow.avoidable
        if flag == true then
            GameTooltip:AddLine("The game calls this avoidable damage.",
                0.88, 0.42, 0.36, true)
        elseif flag == false then
            GameTooltip:AddLine("The game does not call this avoidable.",
                0.61, 0.64, 0.69, true)
        end
    end)

    return row
end

-- ONE LINE OF THE EVENING'S TABLES: how many, of what, and the note that
-- makes it a pattern rather than a moment.
local function BuildTallyRow(parent, width)
    local UI, C = ns.UI, ns.UI.C
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, TALLY_ROW_H)

    row.count = UI.Label(row, "", UI.FS.row, C.accent)
    row.count:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.count:SetWidth(44)
    row.count:SetJustifyH("LEFT")

    -- THE PICTURE COLUMN between the count and the name: the mob's face on
    -- a killer's row, the spec icon on a fallen player's - the same two
    -- pictures the pull list under this page carries (owner, 2026-08-16:
    -- "in der tonight uebersicht fehlen die klassen icons"). One slot,
    -- always the same width, so the names line up whether or not the
    -- client had a picture for that row.
    row.face = ns.Death.CreateFace(row, TALLY_PIC)
    row.face:SetPoint("LEFT", row, "LEFT", TALLY_PIC_X, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(TALLY_PIC, TALLY_PIC)
    row.icon:SetPoint("LEFT", row, "LEFT", TALLY_PIC_X, 0)
    row.icon:Hide()

    row.main = UI.Label(row, "", UI.FS.row, C.text)
    row.main:SetPoint("LEFT", row, "LEFT", TALLY_PIC_X + TALLY_PIC + 8, 0)
    row.main:SetPoint("RIGHT", row, "RIGHT", -220, 0)
    row.main:SetJustifyH("LEFT")
    row.main:SetWordWrap(false)

    row.note = UI.Label(row, "", UI.FS.meta, C.textDim)
    row.note:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.note:SetJustifyH("RIGHT")
    row.note:SetWordWrap(false)

    row:Hide()
    return row
end

---------------------------------------------------------------------------
-- THE FIGHT HEADER ON THE EVENING'S PAGE
--
-- One line, and it carries the same three things the column's fight row
-- does: a chevron that folds it, a portrait that opens the Adventure Guide,
-- and a name that is orange ONLY when there is a page behind it. "A boss is
-- a link, trash is a fact" is the column's rule, and a second page breaking
-- it would teach this addon's orange to mean nothing.
--
-- TWO CLICK TARGETS, SPATIALLY APART. The row folds; the name opens the
-- guide. The invisible button over the name is shown only on a boss - over
-- "Trash" it would swallow the click that folds and answer with nothing.
--
-- EVERY LABEL IS ANCHORED HERE, not only in the painter. An unanchored
-- region is not drawn at all, so a branch of the painter that forgets one
-- leaves a blank strip rather than a misplaced word.
---------------------------------------------------------------------------
local function BuildBossRow(parent, width)
    local UI, C = ns.UI, ns.UI.C
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(width, BOSS_ROW_H)

    -- Its own ground, under everything else on the row: this says "a
    -- different kind of thing", which is not what a hover says.
    row.band = row:CreateTexture(nil, "BACKGROUND", nil, -2)
    row.band:SetAllPoints(row)
    row.band:SetColorTexture(C.surface[1], C.surface[2], C.surface[3], 1)

    row.chev = UI.Glyph(row, "caretDOWN", 10, C.textFaint)
    row.chev:SetPoint("LEFT", row, "LEFT", BOSS_CHEV_X, 0)

    row.face = ns.Death.CreateFace(row, TALLY_PIC)
    row.face:SetPoint("LEFT", row, "LEFT", BOSS_PIC_X, 0)
    row.face:EnableMouse(true)
    row.face:Hide()

    row.lead = ns.UI.Label(row, "", UI.FS.row, C.text)
    row.lead:SetPoint("LEFT", row, "LEFT", BOSS_TEXT_X, 0)
    row.lead:SetJustifyH("LEFT")
    row.lead:SetWordWrap(false)

    -- The difficulty, and never in the orange: that colour is this addon's
    -- promise that a word can be pointed at.
    row.tag = ns.UI.Label(row, "", UI.FS.meta, C.textFaint)
    row.tag:SetPoint("LEFT", row.lead, "RIGHT", 8, 0)
    row.tag:SetJustifyH("LEFT")
    row.tag:SetWordWrap(false)

    -- TWO RIGHT-HAND COLUMNS, and the order is fixed right to left so they
    -- cannot overlap however long either of them turns out to be.
    row.note = ns.UI.Label(row, "", UI.FS.meta, C.textDim)
    row.note:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.note:SetJustifyH("RIGHT")
    row.note:SetWordWrap(false)

    row.when = ns.UI.Label(row, "", UI.FS.meta, C.textFaint)
    row.when:SetPoint("RIGHT", row.note, "LEFT", -14, 0)
    row.when:SetJustifyH("RIGHT")
    row.when:SetWordWrap(false)

    row.hit = CreateFrame("Button", nil, row)
    row.hit:Hide()

    local function Enter(self)
        if not row.faceName then return end
        ns.Death.ShowEnemyTip(self, {
            who = row.faceName,
            art = row.faceArt,
            note = row.facePage
                and "Click to open it in the Adventure Guide" or nil,
        })
    end
    local function Leave()
        ns.Death.HideEnemyTip()
    end
    local function Open()
        if not row.facePage then return end
        ns.Death.OpenJournal(row.faceJournal, row.facePage.journal)
    end
    row.face:SetScript("OnEnter", Enter)
    row.face:SetScript("OnLeave", Leave)
    row.face:SetScript("OnMouseUp", Open)
    row.hit:SetScript("OnEnter", Enter)
    row.hit:SetScript("OnLeave", Leave)
    row.hit:SetScript("OnClick", Open)

    -- THE ROW ITSELF FOLDS. Written out rather than as `x and y or z`: what
    -- is stored is a boolean and that idiom cannot carry a false through it.
    row:SetScript("OnClick", function(self)
        if not self.blockID then return end
        if RaidDeaths.overCollapsed[self.blockID] == true then
            RaidDeaths.overCollapsed[self.blockID] = nil
        else
            RaidDeaths.overCollapsed[self.blockID] = true
        end
        RaidDeaths:Refresh()
    end)

    row:Hide()
    return row
end

-- The header, dressed for the fight it names. Split out of the paint loop so
-- the boss branch and the trash branch stand beside each other and can be
-- read against one another.
local function PaintBossRow(row, block, shut)
    local C = ns.UI.C
    row.blockID = block.id
    row.chev:SetKind(shut and "caretRIGHT" or "caretDOWN")

    row.lead:SetText(block.label or "")
    row.tag:SetText(block.tag or "")
    row.note:SetText(RaidDeaths.BossNote(block))
    row.when:SetText(RaidDeaths.BossWhen(block))

    row.lead:ClearAllPoints()
    if block.boss then
        row.lead:SetTextColor(C.hot[1], C.hot[2], C.hot[3])
        row.faceName = block.label
        row.faceJournal = block.journal
        row.faceArt = RaidDeaths.BossArt(block.journal, block.bossID,
            block.label)
        row.facePage = RaidDeaths.BossPage(block.journal, block.bossID,
            block.label)
        if ns.Death.PaintFace(row.face, row.faceArt) then
            row.face:Show()
            row.lead:SetPoint("LEFT", row, "LEFT", BOSS_TEXT_X, 0)
        else
            row.lead:SetPoint("LEFT", row, "LEFT", BOSS_PIC_X, 0)
        end
        row.hit:ClearAllPoints()
        row.hit:SetAllPoints(row.lead)
        row.hit:Show()
    else
        row.lead:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
        row.faceName, row.facePage, row.faceArt = nil, nil, nil
        ns.Death.PaintFace(row.face, nil)
        row.face:Hide()
        row.lead:SetPoint("LEFT", row, "LEFT", BOSS_PIC_X, 0)
        row.hit:Hide()
    end
end

-- ONE PULL IN THE SIDE LIST: when it was, where, and how many fell.
---------------------------------------------------------------------------
-- ONE ROW OF THE COLUMN, IN EITHER OF ITS TWO SHAPES
--
-- ONE WIDGET, NOT TWO POOLS. A place header and a pull look nothing alike,
-- and the tempting answer is a builder for each - but they are stacked in
-- ONE chain, every row hung off the bottom of the one above it, and two
-- pools cannot interleave in a single chain without an ordering rule nobody
-- could read six months from now. So every part is built once and the
-- painter says which of them this row is wearing.
--
-- The fields are named for their POSITION rather than their contents, since
-- the contents differ: `lead` is the first line's left, `tag` its right,
-- `note` the second line. A field called `when` would be the clock on a pull
-- and the name of a dungeon on the header above it.
---------------------------------------------------------------------------
local function BuildSideRow(parent, slot)
    local UI, C = ns.UI, ns.UI.C
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(SIDE_PULL_H)

    -- THE PLACE HEADER'S GROUND. Owner, 2026-08-28: "gib dem header mal
    -- einen schoenen bg". A heading over a list with no ground is a line of
    -- text somebody has to be told is a heading; with one, the eye finds the
    -- next place without reading a word.
    --
    -- Under `bg`, which is hover and selection: those two are about ONE row
    -- answering the mouse, this is about a row being a different KIND of
    -- thing, and a hover has to still be visible on top of it.
    row.band = row:CreateTexture(nil, "BACKGROUND", nil, -2)
    row.band:SetAllPoints(row)
    row.band:SetColorTexture(C.surface[1], C.surface[2], C.surface[3], 1)
    row.band:Hide()

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:Hide()

    -- THE BLUE EDGE DOWN A PLACE, and the orange one below marks the pull
    -- being read. Two marks that mean two different things, so they are two
    -- colours - the blue is the same one the place's name wears.
    row.edge = row:CreateTexture(nil, "ARTWORK")
    row.edge:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.edge:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.edge:SetWidth(2)
    row.edge:SetColorTexture(C.accentCool[1], C.accentCool[2],
        C.accentCool[3], 1)
    row.edge:Hide()

    -- THE LINE ABOVE A PLACE. Owner, 2026-08-25: "in der zeile von der
    -- instanz, eine trennlinie". It belongs to the header rather than
    -- sitting between every pair of rows, because what it separates is one
    -- place from the one before it - the pulls in between must not get one.
    row.rule = row:CreateTexture(nil, "ARTWORK")
    row.rule:SetColorTexture(C.separator[1], C.separator[2], C.separator[3], 1)
    row.rule:SetHeight(1)
    row.rule:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.rule:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    row.rule:Hide()

    -- The accent bar on the left edge marks the one being read, exactly as
    -- the death window's list does. A fill alone reads as hover on a list
    -- you can also hover.
    row.mark = row:CreateTexture(nil, "ARTWORK")
    row.mark:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.mark:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.mark:SetWidth(2)
    row.mark:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    row.mark:Hide()

    -- THE CHEVRON. Owner: "dann ein chevron zum ausfahren nachn unten /
    -- open". It points DOWN while the pulls are under it and RIGHT while
    -- they are folded away - the direction the list would move, which is
    -- what every tree in this client means by those two shapes.
    row.chev = UI.Glyph(row, "caretDOWN", 10, C.textFaint)
    row.chev:SetPoint("LEFT", row, "LEFT", 5, 0)
    row.chev:Hide()

    -- WHICH PULL OF THE PLACE. Owner: "da geht nach unten die liste mit den
    -- Pulls auf, 1, 2, 3". Counted from the oldest, so pull 1 is still pull
    -- 1 after four more have happened on top of it.
    row.num = UI.Label(row, "", UI.FS.eyebrow, C.textFaint)
    row.num:SetJustifyH("RIGHT")
    row.num:SetWidth(16)

    -- THE BOSS'S FACE. Owner, 2026-08-28: "ggf bei den bossen noch einen
    -- avatar". Taken from whichever kept pull recorded the mob's art, which
    -- is the same door the detail page and the evening's tables use - so a
    -- boss nobody has died to yet simply has no picture, rather than a box.
    row.face = ns.Death.CreateFace(row, SIDE_FACE)
    row.face:EnableMouse(true)
    row.face:Hide()

    -- AND THE NAME IS THE LINK. Owner: "denk dran, bei bossen, dann richtig
    -- linken". A font string cannot take the mouse, so this sits on top of
    -- it - the same trick the pull table uses for its two hoverable words.
    -- Only shown on a boss: an invisible click target over "Trash pull"
    -- would swallow the click that chooses the pull.
    row.tagHit = CreateFrame("Button", nil, row)
    row.tagHit:Hide()

    -- THE GUIDE'S TILE, down the right of a place header and row-high. It
    -- opens the guide; the row underneath still folds the place. Sized to
    -- the header rather than left at its default, which is taller than this
    -- row and would hang out of both ends of it.
    row.art = ns.Death.CreatePlaceArt(row, SIDE_ART_W, SIDE_ART_H)
    row.art:SetPoint("RIGHT", row, "RIGHT", -4, 0)

    -- ANCHORED HERE, NOT ONLY IN THE PAINTER.
    --
    -- The painter sets them again for whichever shape the row is wearing,
    -- and every row that goes through it was fine - but the evening's row is
    -- painted by hand and never does. Its three labels had text and no
    -- position, which is not a misplaced label: an unanchored region is not
    -- drawn at all, and the top of the column was a blank strip.
    --
    -- THE SECOND LINE HANGS OFF THE FIRST, not off the row's bottom edge.
    -- Measuring both from opposite ends of a 34-pixel row is an arithmetic
    -- with the font's height in it, and that height is the client's to know:
    -- the two lines overlapped by the difference. Anchored to each other,
    -- the client does the sum and they cannot cross whatever the font does.
    row.lead = UI.Label(row, "", UI.FS.meta, C.text)
    row.lead:SetJustifyH("LEFT")
    row.lead:SetWordWrap(false)
    row.lead:SetPoint("TOPLEFT", row, "TOPLEFT", L_LEAF_TEXT, -5)

    row.tag = UI.Label(row, "", UI.FS.meta, C.hot)
    row.tag:SetJustifyH("RIGHT")
    row.tag:SetWordWrap(false)
    row.tag:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -5)

    row.note = UI.Label(row, "", UI.FS.meta, C.textFaint)
    row.note:SetJustifyH("LEFT")
    row.note:SetWordWrap(false)
    row.note:SetPoint("TOPLEFT", row.lead, "BOTTOMLEFT", 0, -3)
    row.note:SetPoint("RIGHT", row, "RIGHT", -8, 0)

    -- THE RIGHT-HAND COLUMN. Owner, 2026-08-29: "mach 2 table." What a row
    -- cost lives here, away from what it was - so a column of numbers can be
    -- read down without the words in between.
    row.right = UI.Label(row, "", UI.FS.meta, C.harm)
    row.right:SetJustifyH("RIGHT")
    row.right:SetWordWrap(false)
    row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -5)

    -- Hover lights the row it is over, unless that row is already the one
    -- being read - two different fills meaning two different things would be
    -- one fill meaning neither.
    local function Lit(on)
        if row.selected then return end
        if not on then
            row.bg:Hide()
            return
        end
        -- A place already sits on `surface`, so hovering it has to go one
        -- step further up the ladder or the row answers the mouse with the
        -- colour it already had.
        local fill = C.surface
        if row.band:IsShown() then fill = C.control end
        row.bg:SetColorTexture(fill[1], fill[2], fill[3], 1)
        row.bg:Show()
    end
    row:SetScript("OnEnter", function() Lit(true) end)
    row:SetScript("OnLeave", function() Lit(false) end)

    -- THE MECHANIC UNDER THE CLOCK OPENS THE CLIENT'S OWN TOOLTIP. Owner,
    -- 2026-08-29: "kannst du in der rechten spalte die kill spells verlinken
    -- und das icon davor packen? haste ja schon in der mitte." The icon
    -- rides inside the string; this is the half that answers the mouse.
    row.noteHit = CreateFrame("Frame", nil, row)
    row.noteHit:SetAllPoints(row.note)
    row.noteHit:EnableMouse(true)
    row.noteHit:SetScript("OnEnter", function(self)
        Lit(true)
        if not (GameTooltip and row.noteSpell) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local shown = row.noteSpellID
            and pcall(GameTooltip.SetSpellByID, GameTooltip, row.noteSpellID)
        if not shown then
            GameTooltip:ClearLines()
            GameTooltip:AddLine(row.noteSpell, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    row.noteHit:SetScript("OnLeave", function()
        Lit(false)
        if GameTooltip then GameTooltip:Hide() end
    end)
    -- The click belongs to the ROW; this frame is only sitting on top of it
    -- for the sake of a tooltip.
    row.noteHit:SetScript("OnMouseUp", function()
        local press = row:GetScript("OnClick")
        if press then press(row) end
    end)
    row.noteHit:Hide()

    -- WHAT THE FACE AND THE NAME BOTH DO. The tooltip is the addon's own
    -- enemy tip - the same one the pull table shows for a mob - with the
    -- line about the guide under it, so the promise the orange makes is
    -- spelled out rather than left to be discovered.
    -- WHAT THE FACE AND THE NAME DO, on whichever row is wearing them: a
    -- fight header wears its boss, a pull wears whatever did most of the
    -- killing. Only the first of those has a page behind it, and the tip
    -- says so rather than promising a click that does nothing.
    local function BossEnter(self)
        Lit(true)
        if not row.faceName then return end
        ns.Death.ShowEnemyTip(self, {
            who = row.faceName,
            art = row.faceArt,
            note = row.facePage
                and "Click to open it in the Adventure Guide" or nil,
        })
    end
    local function BossLeave()
        Lit(false)
        ns.Death.HideEnemyTip()
    end
    local function BossClick()
        if not row.facePage then return end
        ns.Death.OpenJournal(row.faceJournal, row.facePage.journal)
    end
    row.face:SetScript("OnEnter", BossEnter)
    row.face:SetScript("OnLeave", BossLeave)
    row.face:SetScript("OnMouseUp", BossClick)
    row.tagHit:SetScript("OnEnter", BossEnter)
    row.tagHit:SetScript("OnLeave", BossLeave)
    row.tagHit:SetScript("OnClick", BossClick)

    row:SetScript("OnClick", function(self)
        -- A PLACE FOLDS, A PULL IS CHOSEN, and which of the two this row is
        -- was decided by the painter. Written out rather than as one
        -- `x and y or z`: what is being stored is a boolean, and that idiom
        -- cannot carry a false through it.
        if self.place then
            if RaidDeaths.collapsed[self.place] == true then
                RaidDeaths.collapsed[self.place] = nil
            else
                RaidDeaths.collapsed[self.place] = true
            end
            RaidDeaths:Refresh()
            return
        end
        if not self.index then return end
        -- CHOSEN BY THE PULL'S OWN ID. The row knows where it sat when it
        -- was painted, and where it sat is not a name: a pull arriving
        -- underneath, or the evening trimming its oldest, moves every
        -- position in the column while naming the same pulls.
        RaidDeaths.showing = self.pullKey
        -- Choosing a pull leaves the evening's page, or the click would
        -- select something the window is not showing.
        RaidDeaths.overview = false
        -- A death that was open belonged to the PULL that was open. Carrying
        -- the index across would open whoever happens to be third in the
        -- next pull, which is a different person's death under the name of
        -- the one that was being read.
        RaidDeaths.reading = nil
        RaidDeaths:Refresh()
    end)
    row.slot = slot
    return row
end

-- ONE ROW, DRESSED FOR WHAT IT IS.
--
-- Split out of the paint loop so the two shapes stand side by side and can
-- be read against each other. Every anchor is cleared and set again here,
-- because a row that was a pull a moment ago is a place header now and an
-- anchor left over from its last life is the kind of fault that only shows
-- up after a fold.
local function PaintSideRow(row, item, selected, military)
    local C = ns.UI.C
    row:SetHeight(RaidDeaths.SideHeight(item))
    row.lead:ClearAllPoints()
    row.tag:ClearAllPoints()
    row.note:ClearAllPoints()
    row.num:ClearAllPoints()
    row.right:ClearAllPoints()
    row.face:ClearAllPoints()
    row.tagHit:ClearAllPoints()

    ---------------------------------------------------------------------
    -- THE PLACE. One row however often the evening walked back into it.
    ---------------------------------------------------------------------
    if item.kind == "run" then
        row.place, row.index, row.selected = item.id, nil, false
        row.pullKey = nil
        row.level = "place"
        row.rule:Show()
        row.band:Show()
        row.edge:Show()
        row.chev:Show()
        row.chev:SetKind(item.open and "caretDOWN" or "caretRIGHT")
        row.chev:ClearAllPoints()
        row.chev:SetPoint("LEFT", row, "LEFT", L_PLACE_CHEV, 0)
        row.num:SetText("")
        row.right:SetText("")
        row.bg:Hide()
        row.mark:Hide()
        row.face:Hide()
        row.tagHit:Hide()
        row.noteHit:Hide()
        row.faceName, row.facePage = nil, nil

        local drawn = row.art.Paint(item.journal)
        local edge, corner, side = row, "TOPRIGHT", "RIGHT"
        if drawn then edge, corner, side = row.art, "TOPLEFT", "LEFT" end

        row.lead:SetText(item.instance or item.tag or "Somewhere")
        row.lead:SetTextColor(C.accentCool[1], C.accentCool[2],
            C.accentCool[3])
        row.lead:SetPoint("TOPLEFT", row, "TOPLEFT", L_PLACE_TEXT, -6)

        -- The difficulty, and NOT in the orange it used to wear: that colour
        -- is this addon's promise that a word can be pointed at.
        row.tag:SetText(item.tag or "")
        row.tag:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
        row.tag:SetPoint("TOPRIGHT", edge, corner, -6, -6)
        row.lead:SetPoint("RIGHT", row.tag, "LEFT", -6, 0)

        local note = string.format("%d %s", item.leaves,
            item.leaves == 1 and "pull" or "pulls")
        if (item.dead or 0) > 0 then
            note = note .. "  -  " .. string.format("%d dead", item.dead)
        end
        row.note:SetText(note)
        row.note:SetTextColor(C.textFaint[1], C.textFaint[2], C.textFaint[3])
        row.note:SetPoint("TOPLEFT", row.lead, "BOTTOMLEFT", 0, -3)
        row.note:SetPoint("RIGHT", edge, side, -6, 0)
        return
    end

    ---------------------------------------------------------------------
    -- THE FIGHT INSIDE IT: a boss, or a run of trash. Owner, 2026-08-29:
    -- "so kann man auch schoen sehen, ah, das war trash zwischen den
    -- bossen." One line, because it is a divider with a name on it.
    ---------------------------------------------------------------------
    if item.kind == "boss" then
        row.place, row.index, row.selected = item.id, nil, false
        row.pullKey = nil
        row.level = "fight"
        row.rule:Hide()
        row.band:Hide()
        row.edge:Hide()
        row.chev:Show()
        row.chev:SetKind(item.open and "caretDOWN" or "caretRIGHT")
        row.chev:ClearAllPoints()
        row.chev:SetPoint("LEFT", row, "LEFT", L_FIGHT_CHEV, 0)
        row.num:SetText("")
        row.note:SetText("")
        row.art.Paint(nil)
        row.bg:Hide()
        row.mark:Hide()
        row.noteHit:Hide()

        row.lead:SetText(item.label or "")
        row.tag:SetText("")
        row.right:SetText(string.format("%d %s", item.leaves,
            item.leaves == 1 and "pull" or "pulls"))
        row.right:SetTextColor(C.textFaint[1], C.textFaint[2], C.textFaint[3])
        row.right:SetPoint("RIGHT", row, "RIGHT", -8, 0)

        -- A BOSS IS A LINK, TRASH IS A FACT. The orange and the face and the
        -- click all say the same thing - there is a page behind this word -
        -- and trash has none of the three.
        -- A BOSS GETS A FACE; TRASH GETS NONE. Owner, 2026-08-29: "beim
        -- group death log fehlt der boss avatar, bei trash mach einfach kein
        -- icon."
        if item.boss then
            row.lead:SetTextColor(C.hot[1], C.hot[2], C.hot[3])
            row.faceName = item.label
            row.faceJournal = item.journal
            row.faceArt = RaidDeaths.BossArt(item.journal, item.bossID,
                item.label)
            row.facePage = RaidDeaths.BossPage(item.journal, item.bossID,
                item.label)
            if ns.Death.PaintFace(row.face, row.faceArt) then
                row.face:SetPoint("LEFT", row, "LEFT", L_FIGHT_TEXT, 0)
                row.face:Show()
                row.lead:SetPoint("LEFT", row.face, "RIGHT", 6, 0)
            else
                row.lead:SetPoint("LEFT", row, "LEFT", L_FIGHT_TEXT, 0)
            end
            row.tagHit:SetAllPoints(row.lead)
            row.tagHit:Show()
        else
            row.lead:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
            row.lead:SetPoint("LEFT", row, "LEFT", L_FIGHT_TEXT, 0)
            row.faceName, row.facePage, row.faceArt = nil, nil, nil
            row.face:Hide()
            row.tagHit:Hide()
        end
        row.lead:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
        return
    end

    ---------------------------------------------------------------------
    -- ONE PULL, AS TWO COLUMNS. Owner, 2026-08-29: "links pull nummer,
    -- zeit / zeile darunter was hat mich gekillt - rechte spalte ...
    -- darunter schaden (der muss ja in rot sein)".
    --
    --   9  23:29:06                          12 dead
    --      Dreadful Presence
    ---------------------------------------------------------------------
    row.place, row.index = nil, item.index
    -- WHICH PULL THIS IS, as opposed to where it is. The index paints the
    -- accent bar (it is compared against a position in the same list this
    -- row came out of); the id is what a click stores, because that outlives
    -- the list being rebuilt.
    row.pullKey = nil
    if type(item.fight) == "table" then row.pullKey = item.fight.key end
    row.level = "pull"
    row.rule:Hide()
    row.band:Hide()
    row.edge:Hide()
    row.chev:Hide()
    row.art.Paint(nil)
    row.tagHit:Hide()
    row.facePage = nil

    row.num:SetText(tostring(item.number or ""))
    row.num:SetPoint("TOPLEFT", row, "TOPLEFT", L_LEAF_NUM, -5)

    -- WHEN IT HAPPENED, in the client's own format - read once per paint and
    -- handed down, not asked per row.
    row.lead:SetText(RaidDeaths.PullTime(item.fight, military))
    row.lead:SetTextColor(C.textBody[1], C.textBody[2], C.textBody[3])
    row.lead:SetPoint("TOPLEFT", row, "TOPLEFT", L_LEAF_TEXT, -5)

    -- WHO DID MOST OF IT, top right with its face - which is where the own
    -- death log puts the mob that landed the blow. Same shape, same reading.
    local who, art = RaidDeaths.PullCulprit(item.fight, RaidDeaths.log)
    row.tag:SetText(who or "")
    row.tag:SetTextColor(C.hot[1], C.hot[2], C.hot[3])
    row.tag:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -5)
    row.faceName, row.faceArt = who, art

    if who and ns.Death.PaintFace(row.face, art) then
        row.face:SetPoint("RIGHT", row.tag, "LEFT", -5, 0)
        row.face:Show()
        row.lead:SetPoint("RIGHT", row.face, "LEFT", -6, 0)
    else
        row.face:Hide()
        row.lead:SetPoint("RIGHT", row.tag, "LEFT", -6, 0)
    end

    -- WHAT IT COST, under the name and in the harm colour: a number that
    -- already happened, not a word to point at.
    row.right:SetText(string.format("%d dead", item.dead or 0))
    row.right:SetTextColor(C.harm[1], C.harm[2], C.harm[3])
    row.right:SetPoint("TOPRIGHT", row.tag, "BOTTOMRIGHT", 0, -3)

    -- AND WHAT DID IT, under the clock.
    --
    -- An ABILITY wears its icon and opens the client's own tooltip, the way
    -- the pull table below the header always has - and with that it wears
    -- the ORANGE, which in this addon is the promise that a word answers
    -- the mouse. A mob's name or a clock keeps the red: red is what the
    -- pull cost, and neither of those two has a page behind it.
    local mechanic, mechanicID = RaidDeaths.PullMechanic(item.fight)
    row.noteSpell, row.noteSpellID = nil, nil
    if mechanicID then
        row.note:SetText(ns.Death.SpellText(mechanicID, mechanic))
        row.note:SetTextColor(C.hot[1], C.hot[2], C.hot[3])
        row.noteSpell, row.noteSpellID = mechanic, mechanicID
    else
        row.note:SetText(mechanic)
        row.note:SetTextColor(C.harm[1], C.harm[2], C.harm[3])
    end
    row.note:SetPoint("TOPLEFT", row.lead, "BOTTOMLEFT", 0, -3)
    row.note:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    row.noteHit:SetShown(row.noteSpell ~= nil)

    local isOn = selected ~= nil and item.index == selected
    row.selected = isOn
    row.mark:SetShown(isOn)
    row.bg:SetShown(isOn)
    if isOn then
        row.bg:SetColorTexture(C.control[1], C.control[2], C.control[3], 1)
    end
end

function RaidDeaths:Create()
    if frame then return frame end
    local UI, C = ns.UI, ns.UI.C

    frame = CreateFrame("Frame", "ZwoelfStuffRaidDeaths", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
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

    frame.title = UI.Label(frame, "", UI.FS.card, C.text)
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", UI.PAD, -18)

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -UI.PAD, -14)
    local cross = UI.Glyph(close, "ui-close", 12, C.textDim)
    cross:SetPoint("CENTER", close, "CENTER", 0, 0)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame.close = close

    -- THE WAY OUT OF A ROW, in the window's header rather than inside the page
    -- it leaves. The owner's ask, and it is the right corner: this is a WINDOW
    -- action - it changes which page the window shows - and it now sits beside
    -- the other one, which closes the window entirely.
    --
    -- Inside the page it also cost the first line its left edge: the head
    -- was hung off the BUTTON, and every line under the head off the head,
    -- so the whole page lined up on a control instead of on the window.
    --
    -- It belongs to the frame now, so hiding the detail no longer hides it
    -- with it. The painter is the one place that says when it is on screen.
    -- THE COLUMN FOLDS AWAY, and the table takes the room. Owner,
    -- 2026-08-25: "wir koennen das death log auch groesser machen, und
    -- seiten ein ausklappbar, kann sich jeder anzeigen was er will."
    frame.fold = UI.Button(frame, "Hide the pulls", 118, function()
        RaidDeaths.sideShut = not (RaidDeaths.sideShut == true)
        frame.Widen()
        RaidDeaths:Refresh()
    end)
    frame.fold:SetPoint("RIGHT", close, "LEFT", -10, 0)

    frame.back = UI.Button(frame, "Back to the pull", 140,
        function() RaidDeaths:CloseReading() end)
    frame.back:SetPoint("RIGHT", frame.fold, "LEFT", -10, 0)
    frame.back:Hide()

    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(C.separator[1], C.separator[2], C.separator[3], 1)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -UI.HEADER_H)
    rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -UI.HEADER_H)

    -- Where the numbers came from, said out loud. A list that is quietly the
    -- last pull rather than this one is the kind of thing somebody reads
    -- wrongly once and never trusts again.
    -- No guide tile in front of this line. It stood there for an evening
    -- and, because the verdict, the heads and the whole table hang off this
    -- label, it pushed the table over with it (owner, 2026-08-16: "das
    -- dungeon bild kann da auch oben raus, dann rutscht die table wieder
    -- nach links"). The side column shows the tile on every pull.
    frame.where = UI.Label(frame, "", UI.FS.meta, C.textFaint)
    frame.where:SetPoint("TOPLEFT", frame, "TOPLEFT", UI.PAD,
        -(UI.HEADER_H + 8))

    -- THE VERDICT, where the death window puts its analysis: right under the
    -- header, in body text, because it is the sentence somebody reads out
    -- loud to the group.
    frame.verdict = UI.Label(frame, "", UI.FS.row, C.text)
    frame.verdict:SetPoint("TOPLEFT", frame.where, "BOTTOMLEFT", 0, -8)

    -- THE COLUMN HEADS, in the death window's own language: upper case,
    -- small, over a rule. Without them "39.9" at the end of a line is a
    -- number nobody can name.
    local head = CreateFrame("Frame", nil, frame)
    head:SetPoint("TOPLEFT", frame.verdict, "BOTTOMLEFT", 0, -12)
    head:SetHeight(14)
    frame.head = head

    -- The same magnifier over the column of them, so the mark in the rows
    -- has something naming it rather than being a mystery icon.
    frame.headGlass = head:CreateTexture(nil, "ARTWORK")
    frame.headGlass:SetSize(GLASS, GLASS)
    frame.headGlass:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 1, 0)
    UI.PaintSearchIcon(frame.headGlass)
    frame.headGlass:SetAlpha(0.5)

    frame.headWhen = UI.Eyebrow(head, "When")
    frame.headWhen:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", COL_WHEN, 0)
    frame.headWho = UI.Eyebrow(head, "Who died")
    frame.headWho:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 94, 0)
    -- 80 = when(52) + gap(2) + spec(20) + gap(6); 268 adds the name column
    -- and the mob's face; 414 adds the killer column. The head reads the same
    -- arithmetic the cells do or it is a decoration that drifts.
    frame.headKiller = UI.Eyebrow(head, "Killed by")
    frame.headKiller:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 282, 0)
    frame.headWhat = UI.Eyebrow(head, "With what")
    frame.headWhat:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 428, 0)
    frame.headAmount = UI.Eyebrow(head, "Damage")
    frame.headAmount:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", -8, 0)

    local headRule = head:CreateTexture(nil, "ARTWORK")
    headRule:SetColorTexture(C.separator[1], C.separator[2], C.separator[3], 1)
    headRule:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 0, -3)
    headRule:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", 0, -3)
    headRule:SetHeight(1)

    -----------------------------------------------------------------------
    -- THE SIDE LIST: one line per pull, newest at the top, which is the one
    -- being asked about nine times in ten. Same shape as the death window's,
    -- because they are the same question asked about two different things.
    -----------------------------------------------------------------------
    local side = CreateFrame("Frame", nil, frame)
    side:SetWidth(SIDE_W)
    side:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -UI.PAD,
        -(UI.HEADER_H + SIDE_TOP))
    side:SetPoint("BOTTOM", frame, "BOTTOM", 0, SIDE_BOTTOM)
    frame.side = side

    -- EVERYTHING IN THE COLUMN HANGS OFF ONE CHILD, so folding it away is
    -- one Show and not a walk over a list of rows that grows while it is
    -- being walked. The column frame itself stays: what the table to its
    -- left is anchored to is its EDGE, and an edge that disappears takes
    -- the table's right-hand side with it.
    local body = CreateFrame("Frame", nil, side)
    body:SetAllPoints(side)
    frame.sideBody = body

    frame.sideTitle = UI.Label(body, "", UI.FS.meta, C.textFaint)
    frame.sideTitle:SetPoint("TOPLEFT", body, "TOPLEFT", 8, 0)

    local sideRule = frame:CreateTexture(nil, "ARTWORK")
    sideRule:SetColorTexture(C.separator[1], C.separator[2], C.separator[3], 1)
    sideRule:SetWidth(1)
    sideRule:SetPoint("TOPRIGHT", side, "TOPLEFT", -8, 0)
    sideRule:SetPoint("BOTTOMRIGHT", side, "BOTTOMLEFT", -8, 0)
    frame.sideRule = sideRule

    -- THE WHOLE EVENING, at the top of the list of pulls, where "all" belongs
    -- in a list of parts. Same row shape as a pull, because it is the same
    -- kind of choice - one of these is what the page shows.
    local sessionRow = BuildSideRow(body, 0)
    -- Two lines, and no place to picture: the evening was in several.
    sessionRow:SetHeight(SIDE_SESSION_H)
    sessionRow:SetPoint("TOPLEFT", frame.sideTitle, "BOTTOMLEFT", -8,
        -SIDE_TITLE_GAP)
    sessionRow:SetPoint("RIGHT", body, "RIGHT", 0, 0)
    sessionRow:SetScript("OnClick", function()
        RaidDeaths.overview = true
        RaidDeaths.reading = nil
        RaidDeaths:Refresh()
    end)
    frame.sessionRow = sessionRow

    -- BUILT AS THE COLUMN NEEDS THEM. The pool used to be eight rows made at
    -- creation, which was right while every row was the same height and the
    -- count was a constant. Neither is true now - what is on screen depends
    -- on how many places the evening had and which are folded - and building
    -- for the worst case would build frames nobody ever sees.
    frame.sideRows = {}

    -- The wheel pages the column, the way the death window's does. How far it
    -- may go is whatever the last paint worked out; a list that cannot move
    -- must not eat the gesture.
    side:EnableMouseWheel(true)
    side:SetScript("OnMouseWheel", function(_, delta)
        local far = RaidDeaths.sideMax or 0
        if far <= 0 then return end
        local offset = (RaidDeaths.sideOffset or 0) - delta
        if offset < 0 then offset = 0 end
        if offset > far then offset = far end
        if offset == RaidDeaths.sideOffset then return end
        RaidDeaths.sideOffset = offset
        RaidDeaths:Refresh()
    end)

    local listHost = CreateFrame("Frame", nil, frame)
    listHost:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -8)
    -- THE BOTTOM IS SET ONCE THE FOOTER EXISTS, forty lines down. It used to
    -- be a number here - 26 above the window - and the footer sits at 46 and
    -- grows UPWARD as it wraps, so the two were given the same strip.
    frame.listHost = listHost

    local MAIN_W = WIDTH - SIDE_W - UI.PAD * 2 - 18
    local _, content = UI.ScrollArea(listHost, MAIN_W, 6)
    frame.content = content
    frame.rows = {}
    head:SetPoint("TOPRIGHT", side, "TOPLEFT", -18, 0)

    -----------------------------------------------------------------------
    -- ONE DEATH, OPENED: the last ten seconds of whoever the row names.
    --
    -- It takes over the same rectangle the list sits in rather than opening
    -- a second window: this is a step INTO a row, and a person reading a
    -- pull should not end up with three windows on top of each other to say
    -- one thing. The pull list down the right stays where it is, so the
    -- other pulls are still one click away.
    --
    -- A MODE NEEDS A VISIBLE EXIT, which is what the button is for. Escape
    -- closes the whole window, and a person who has just stepped into a row
    -- is not looking to close the window.
    -----------------------------------------------------------------------
    -- ANCHORED UNDER THE PLACE LINE, not to the column head.
    --
    -- It hung off the head with fourteen pixels of lift, which put its first
    -- row - a 34-pixel portrait centred on a 26-pixel button - straight
    -- through the verdict sentence above it. That was visible in their
    -- screenshot as a face sitting in the middle of a line of text.
    --
    -- The place line is the one thing above this that belongs to BOTH pages:
    -- which pull, and when. Everything below it is the detail's own room.
    local detail = CreateFrame("Frame", nil, frame)
    detail:SetPoint("TOPLEFT", frame.where, "BOTTOMLEFT", 0, -12)
    detail:SetPoint("BOTTOMRIGHT", listHost, "BOTTOMRIGHT", 0, 0)
    detail:Hide()
    frame.detail = detail

    -- WHOSE DEATH THIS IS, in a picture. The owner's ask: the detail head
    -- should carry their avatar and their spec icon again. A page about one
    -- person that names them only in text makes you read the name to know who
    -- you stepped into.
    --
    -- A person's portrait needs a UNIT, not an id - the client draws it for
    -- somebody it can still see - so a group mate who has left since is
    -- shown by name and spec alone. That is honest: we cannot picture
    -- somebody who is not there.
    --
    -- ONE ROW, PINNED TO THE PAGE, and everything in it hung off that row.
    -- It used to be a chain that started at the button - portrait off the
    -- button, icon off the portrait, name off the icon, and the sentence
    -- below reaching back left by a HAND-COUNTED fifty-four to find the
    -- edge again. The count was wrong by the width of the button, so the
    -- whole page stood indented and the table with it. The edge everything
    -- has to line up on is this frame; it can simply be pointed at.
    local who = CreateFrame("Frame", nil, detail)
    who:SetPoint("TOPLEFT", detail, "TOPLEFT", 0, 0)
    who:SetPoint("RIGHT", detail, "RIGHT", 0, 0)
    who:SetHeight(38)
    detail.who = who

    detail.face = who:CreateTexture(nil, "ARTWORK")
    detail.face:SetSize(38, 38)
    detail.face:SetPoint("LEFT", who, "LEFT", 0, 0)
    detail.face:Hide()

    -- Placed by LayoutWho, because where they go depends on what is
    -- actually there to draw: a portrait the client cannot give us must
    -- cost nothing rather than leave a hole with the name pushed out of it.
    detail.spec = who:CreateTexture(nil, "ARTWORK")
    detail.spec:SetSize(24, 24)
    detail.spec:Hide()

    detail.title = UI.Label(who, "", UI.FS.card, C.text)

    -- THE TWO LINES ABOUT WHAT KILLED THEM, each a rich line: the words,
    -- the mob's face in front of its name with the enemy tip on both, the
    -- ability with its icon in front and the client's tooltip on it. Owner,
    -- 2026-08-16: "das spell icon vor den spell namen ... und der name
    -- braucht noch einen tooltip." See Death.BuildRichLine.
    detail.blow = ns.Death.BuildRichLine(detail)
    detail.blow:SetPoint("TOPLEFT", who, "BOTTOMLEFT", 0, -12)
    detail.blow:SetPoint("RIGHT", detail, "RIGHT", 0, 0)
    detail.real = ns.Death.BuildRichLine(detail)
    detail.real:SetPoint("TOPLEFT", detail.blow, "BOTTOMLEFT", 0, -2)
    detail.real:SetPoint("RIGHT", detail, "RIGHT", 0, 0)

    detail.verdict = UI.Label(detail, "", UI.FS.meta, C.accentCool)
    detail.verdict:SetPoint("TOPLEFT", detail.real, "BOTTOMLEFT", 0, -4)

    detail.note = UI.Label(detail, "", UI.FS.meta, C.textFaint)
    detail.note:SetPoint("TOPLEFT", detail.verdict, "BOTTOMLEFT", 0, -4)

    -- The same head the death window puts over its own last ten seconds,
    -- out of the same function - one table in two windows.
    -- ANCHORED ON BOTH SIDES, not given a width and hoped for.
    --
    -- The owner's screenshot showed "Health left" drawn over the list of
    -- pulls. The head was sized from an arithmetic - window minus side column
    -- minus two pads minus a gutter - and an arithmetic that is out by
    -- anything at all puts a right-aligned caption outside the window it
    -- belongs to. The rectangle it has to fit is right there and can simply be
    -- pointed at.
    --
    -- The rows below get the same treatment, so the columns and their
    -- captions cannot come out of two different sums.
    detail.head = ns.Death.BuildEventHead(detail, MAIN_W - 8,
        "What hit them")
    detail.head:SetPoint("TOPLEFT", detail.note, "BOTTOMLEFT", 0, -12)
    detail.head:SetPoint("RIGHT", detail, "RIGHT", -8, 0)

    local detailHost = CreateFrame("Frame", nil, detail)
    detailHost:SetPoint("TOPLEFT", detail.head, "BOTTOMLEFT", 0, -8)
    detailHost:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", 0, 0)
    local _, detailContent = UI.ScrollArea(detailHost, MAIN_W - 8, 8)
    detail.content = detailContent
    detail.rows = {}

    -----------------------------------------------------------------------
    -- THE WHOLE EVENING, in the same rectangle again.
    --
    -- Two tables, and the order is the order the questions get asked: what
    -- keeps killing us, and then who keeps falling. The second one names
    -- people, so it goes UNDER the mechanic - a page that opens on a list of
    -- who died most is a page about blame, and the useful answer is nearly
    -- always the thing at the top of the other table.
    -----------------------------------------------------------------------
    local over = CreateFrame("Frame", nil, frame)
    over:SetPoint("TOPLEFT", head, "TOPLEFT", 0, 14)
    over:SetPoint("BOTTOMRIGHT", listHost, "BOTTOMRIGHT", 0, 0)
    over:Hide()
    frame.overviewFrame = over

    over.title = UI.Label(over, "", UI.FS.card, C.text)
    over.title:SetPoint("TOPLEFT", over, "TOPLEFT", 0, -4)

    over.sub = UI.Label(over, "", UI.FS.meta, C.textFaint)
    over.sub:SetPoint("TOPLEFT", over.title, "BOTTOMLEFT", 0, -4)

    local overHost = CreateFrame("Frame", nil, over)
    overHost:SetPoint("TOPLEFT", over.sub, "BOTTOMLEFT", 0, -14)
    overHost:SetPoint("BOTTOMRIGHT", over, "BOTTOMRIGHT", 0, 0)
    local _, overContent = UI.ScrollArea(overHost, MAIN_W - 8, 8)
    over.content = overContent
    over.rows = {}
    -- A SECOND POOL, because a fight header and a tally row are two shapes.
    -- One pool of mixed shapes would mean every reader of over.rows[3] has
    -- to know what kind of row that happens to be today.
    over.bossRows = {}
    over.width = MAIN_W - 8

    over.headKill = UI.Eyebrow(overContent, "What keeps killing us")
    over.headWho = UI.Eyebrow(overContent, "Who is falling")
    over.empty = UI.Label(overContent, "", UI.FS.row, C.textFaint)
    -- The one sentence about the night. Its own label rather than a line in
    -- the sub-heading: the sub-heading counts, this one judges, and a reader
    -- should be able to tell those apart without reading the words.
    over.verdict = UI.Label(overContent, "", UI.FS.row, C.textBody)

    -- A rich line, not a label: names with the enemy tip, abilities with
    -- their icons and tooltips (owner, 2026-08-16). Grows upward from its
    -- foot as it wraps, so two lines sit clear of the buttons.
    frame.foot = ns.Death.BuildRichLine(frame)
    frame.foot:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", UI.PAD, 46)
    frame.foot:SetPoint("RIGHT", side, "LEFT", -18, 0)

    -- WHERE THE LIST STOPS, and it is the footer rather than a number.
    -- Owner, 2026-08-25, with a picture: "im gruppen death log fehlt unten
    -- der footer bg, der inhalt scrollt hinter den bg info". A pull with
    -- enough dead in it filled the list to a fixed bottom edge while the
    -- footer wrapped to two lines and grew up into the same place - so the
    -- sentence and the last rows were drawn through each other. Anchored to
    -- the footer, the arithmetic belongs to the client and it stays right
    -- however much the footer ends up naming.
    listHost:SetPoint("BOTTOMRIGHT", frame.foot, "TOPRIGHT", 0, 10)

    -- AND THE FOOTER IS OPAQUE. The anchor above is what keeps a row out of
    -- this strip; the plate is what makes sure nothing is SEEN through it if
    -- one ever gets there again - the list is a sibling frame and it draws
    -- over this one, so "nothing behind it" cannot be left to the layout
    -- alone. Same colour as the window, so it reads as the window.
    UI.Fill(frame.foot, "BACKGROUND", C.windowBg)
    frame.foot:SetFrameLevel(listHost:GetFrameLevel() + 5)

    -----------------------------------------------------------------------
    -- The same two buttons the death window carries, in the same corner.
    -----------------------------------------------------------------------
    local share = UI.Button(frame, "Share in chat", 130,
        function() RaidDeaths:Share() end, "primary")
    share:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", UI.PAD, 14)
    frame.share = share

    -- IT CLEARS THE EVENING, which is the only list there is: the column
    -- draws the tally and the newest five of it carry their hits, so a
    -- button that emptied one of the two would leave the other standing in
    -- the column it had just claimed to clear.
    local clear = UI.Button(frame, "Clear tonight", 110, function()
        RaidDeaths:Clear()
    end)
    clear:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -UI.PAD, 14)
    frame.clear = clear

    -----------------------------------------------------------------------
    -- WHAT THE FOLD ACTUALLY DOES: it takes the column's WIDTH away, not the
    -- column. The head, the footer and - through the footer - the list are
    -- all anchored to the column's left edge, so moving that edge hands the
    -- room to the table with no number recomputed anywhere. Hiding the frame
    -- would leave the edge exactly where it was and the room unused.
    --
    -- The scrolling contents are the exception, because a scroll child has a
    -- width of its own rather than an anchor - and so is a tally row, which
    -- is built at a width. Both are set from ONE sum here; two sums for one
    -- width is how a right-aligned caption ends up outside its window.
    -----------------------------------------------------------------------
    frame.Widen = function()
        local shut = RaidDeaths.sideShut == true
        -- One pixel, not zero: a frame with no width has no left edge for
        -- everything else to be measured from.
        side:SetWidth(shut and 1 or SIDE_W)
        body:SetShown(not shut)
        sideRule:SetShown(not shut)

        local w = WIDTH - (shut and 1 or SIDE_W) - UI.PAD * 2 - 18
        content:SetWidth(w)
        detailContent:SetWidth(w - 8)
        overContent:SetWidth(w - 8)
        over.width = w - 8
        -- The rows already built keep the width they were built at, and a
        -- tally row is a fixed rectangle rather than a pair of anchors.
        for _, one in ipairs(over.rows) do one:SetWidth(over.width) end
        for _, one in ipairs(over.bossRows) do one:SetWidth(over.width) end

        frame.fold.label:SetText(shut and "Show the pulls"
            or "Hide the pulls")
    end
    frame.Widen()

    table.insert(UISpecialFrames, "ZwoelfStuffRaidDeaths")
    return frame
end

-- The pull, in the four lines somebody would actually say out loud. Pure, so
-- the wording is checkable and so the chat share and any later Discord post
-- are one text rather than two that drift.
function RaidDeaths.ShareLines(entries, info)
    if not (entries and #entries > 0) then return nil end
    local lines = {}
    lines[#lines + 1] = string.format("%s - %d died%s",
        (info and (info.where or info.label)) or "this pull", #entries,
        (info and info.duration)
            and (" in " .. RaidDeaths.Clock(info.duration)) or "")

    local verdict = RaidDeaths.Verdict(entries, info and info.culprits)
    if verdict ~= "" then lines[#lines + 1] = verdict end

    for _, entry in ipairs(entries) do
        local blow = entry.blow
        lines[#lines + 1] = string.format("%s%s: %s",
            (info and info.timed) and (RaidDeaths.Clock(entry.at) .. "  ") or "",
            entry.short,
            blow and ((blow.who or "?") .. " - "
                .. ns.Death.PlainText(blow.spell or "?"))
                or (entry.blowWhy or "nothing readable"))
    end
    return lines
end

-- HOW MANY FIGHTS A SHARE NAMES. A chat window is not a page: a night of
-- eleven fights posted in full is eleven lines nobody reads, and the ones
-- left out are said out loud rather than trimmed away in silence.
local SHARE_BLOCKS = 5
RaidDeaths.SHARE_BLOCKS = SHARE_BLOCKS

-- The evening in the few lines somebody would read out. Pure, next to the
-- pull's version, so the two say the same kind of thing in the same shape.
function RaidDeaths.SessionShareLines(session)
    local summary = RaidDeaths.SessionLine(session)
    if summary == "" then return nil end

    local lines = { "Tonight - " .. summary }

    -- IT SENDS WHAT IS ON THE SCREEN, and the screen is broken at the
    -- bosses now. A share that still read the night as one flat list would
    -- put a sentence in the raid chat that nobody could find on the page it
    -- came from - and there is no taking a raid message back.
    local blocks = RaidDeaths.Bosses(session)
    local verdict = RaidDeaths.NightVerdict(blocks)
    if verdict ~= "" then lines[#lines + 1] = verdict end

    for index = 1, min(#blocks, SHARE_BLOCKS) do
        local block = blocks[index]
        local worst = block.killers and block.killers[1]
        lines[#lines + 1] = string.format("%s - %s%s",
            block.label, RaidDeaths.BossNote(block),
            worst and string.format(": %s %dx",
                ns.Death.PlainText(worst.spell), worst.deaths) or "")
    end
    if #blocks > SHARE_BLOCKS then
        lines[#lines + 1] = string.format("and %d more",
            #blocks - SHARE_BLOCKS)
    end

    local fallen = RaidDeaths.Fallen(session)
    local worst = fallen[1]
    if worst and worst.deaths > 1 then
        lines[#lines + 1] = string.format("%s: %s",
            worst.short, RaidDeaths.FallenLine(worst))
    end
    return lines
end

function RaidDeaths:Share()
    -- IT SENDS WHAT IS ON THE SCREEN. A button that shares the last pull
    -- while somebody is reading the evening has sent the wrong thing to the
    -- raid, and there is no taking that back.
    if RaidDeaths.overview then
        local evening = RaidDeaths.SessionShareLines(RaidDeaths.session)
        if not evening then
            ns.Print("Nothing has been kept today yet.")
            return
        end
        RaidDeaths.Send(evening)
        return
    end

    local entries, info = RaidDeaths.Best()
    local lines = RaidDeaths.ShareLines(entries, info)
    if not lines then
        ns.Print("No pull with deaths in it yet.")
        return
    end

    RaidDeaths.Send(lines)
end

-- Out of the window and into the chat, one place for both pages. Death's
-- rule, and it is not negotiable: a chosen channel that is not there must
-- SAY so. Printing to your own frame while you believe it went to the raid
-- is the one failure a share is not allowed.
function RaidDeaths.Send(lines)
    local channel, why = ns.Death.ShareTarget(
        ns.db and ns.db.death and ns.db.death.channel, ns.Death.GroupState())
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    for _, line in ipairs(lines or {}) do
        if channel then
            send("ZwoelfStuff: " .. line, channel)
        else
            ns.Print(line)
        end
    end
    if not channel then
        ns.Print("|cff888888" .. (why or "not in a group")
            .. " - printed here instead.|r")
    end
end

-- The footer sentence, pure so the wording is checkable without a frame. The
-- hint is only offered when there is something to open: an instruction for a
-- click that does nothing is worse than no instruction.
function RaidDeaths.FootLine(culprits, count, openable)
    if count == 0 then return "" end
    local line
    if not RaidDeaths.WorthCounting(culprits) then
        line = string.format("%d deaths, each to something different.", count)
    else
        local parts = {}
        for index = 1, min(#culprits, CULPRITS_SHOWN) do
            local culprit = culprits[index]
            parts[#parts + 1] = string.format("%dx %s - %s",
                culprit.count, culprit.who, culprit.spell)
        end
        -- "Killing blow:" - their words (2026-08-16), for the line that
        -- counts them: it IS the killing blows, tallied.
        line = "Killing blow: " .. table.concat(parts, ", ")
        if #culprits > CULPRITS_SHOWN then
            line = line .. string.format(", and %d more",
                #culprits - CULPRITS_SHOWN)
        end
    end
    if openable then
        line = line .. "   -   " .. RaidDeaths.FOOT_HINT
    end
    return line
end

-- The owner's words (2026-08-16): "click on details for their last 10
-- seconds".
RaidDeaths.FOOT_HINT = "click on details for their last 10 seconds"

-- The same sentence as pieces for the rich line: every mob's name with
-- the enemy tip, every ability with its icon and tooltip.
function RaidDeaths.FootPieces(culprits, count, openable, entries, log)
    if count == 0 then return {} end
    local out = {}
    if not RaidDeaths.WorthCounting(culprits) then
        out[#out + 1] = { text = string.format(
            "%d deaths, each to something different.", count) }
    else
        out[#out + 1] = { text = "Killing blow: " }
        for index = 1, min(#culprits, CULPRITS_SHOWN) do
            local culprit = culprits[index]
            if index > 1 then out[#out + 1] = { text = ", " } end
            out[#out + 1] = { text = string.format("%dx ", culprit.count) }
            local art, summary
            for _, entry in ipairs(entries or {}) do
                if entry.blow and entry.blow.who == culprit.who then
                    art = art or entry.blow.art
                    summary = summary or entry.blow.summary
                end
            end
            -- This pull's own picture first, any kept pull's failing that.
            art = art or RaidDeaths.ArtForWho(log, culprit.who)
            out[#out + 1] = { who = culprit.who, art = art, summary = summary }
            out[#out + 1] = { text = " - " }
            out[#out + 1] = { spell = culprit.spell, spellID = culprit.spellID }
        end
        if #culprits > CULPRITS_SHOWN then
            out[#out + 1] = { text = string.format(", and %d more",
                #culprits - CULPRITS_SHOWN) }
        end
    end
    if openable then
        out[#out + 1] = { text = "   -   " .. RaidDeaths.FOOT_HINT }
    end
    return out
end

---------------------------------------------------------------------------
-- ONE DEATH, OPENED
--
-- Their own death window answers "what happened to me"; this answers the same
-- question about whoever the row names, out of the same recap and with the
-- same four columns. The wording lives here, apart from the frame, so it can
-- be read back in a check without a window in the room.
---------------------------------------------------------------------------

-- Whether this death has a story to open. Nothing kept means the recap said
-- nothing - the row still shows who and when, and clicking it does nothing
-- rather than opening an empty page.
function RaidDeaths.Openable(entry)
    return type(entry) == "table" and type(entry.events) == "table"
        and #entry.events > 0
end

function RaidDeaths.DetailTitle(entry, timed)
    if type(entry) ~= "table" then return "" end
    local who = RaidDeaths.Coloured(entry.short or "?", entry.class)
    if entry.you then who = who .. " |cffffd100(you)|r" end
    if timed and entry.at then
        return who .. "  -  fell at " .. RaidDeaths.Clock(entry.at)
    end
    return who
end

-- THE FACE FOR A NAME IN THIS DEATH: the killing blow's own art when it is
-- the same mob, else the first hit from that source that carried one. A
-- death saved before every hit kept its art still has the blow's.
function RaidDeaths.ArtFor(entry, who)
    if not (type(entry) == "table" and who) then return nil end
    local blow = entry.blow
    if blow and blow.who == who and blow.art then return blow.art end
    for _, ev in ipairs(entry.events or {}) do
        if ev.who == who and ev.art then return ev.art end
    end
    return nil
end

-- The same, across every kept pull: the first face any death in the log
-- still holds for this mob. The evening's tally names mobs out of the thin
-- session copy, which carries no art; the full pulls beside it do.
function RaidDeaths.ArtForWho(log, who)
    if not who then return nil end
    for _, fight in ipairs(log or {}) do
        for _, entry in ipairs(fight.entries or {}) do
            local art = RaidDeaths.ArtFor(entry, who)
            if art then return art end
        end
    end
    return nil
end

-- The opened death's two lines, as data: what ended them, and - when the
-- killing blow was mostly wasted on a corpse - which hit actually did the
-- work. Each carries the mob (for its face and the enemy tip) and the
-- spell (for its icon and the client's tooltip); DetailLine below is the
-- same two lines as one sentence, for chat. Owner, 2026-08-16: "hier fehlt
-- auch der avatar und das spell icon mit hover."
function RaidDeaths.DetailLines(entry, log)
    if type(entry) ~= "table" then return {} end
    -- This death's own art first; failing that, the same mob's face off any
    -- other kept pull (owner, 2026-08-16: "hier fehlt der gegner avatar ...
    -- vor dem primal serpent" - a hit that mattered from a mob this entry
    -- never kept a picture of, while the pull before it did).
    local function Art(who)
        return RaidDeaths.ArtFor(entry, who) or RaidDeaths.ArtForWho(log, who)
    end
    local blow = entry.blow
    if not blow then
        return { { text = entry.blowWhy or "nothing readable",
            pieces = { { text = entry.blowWhy or "nothing readable" } } } }
    end
    local out = {}
    local tail = ""
    if type(blow.amount) == "number" and blow.amount > 0 then
        tail = tail .. " for " .. ns.ShortNumber(blow.amount)
    end
    if type(blow.overkill) == "number" and blow.overkill > 0 then
        tail = tail .. ", " .. ns.ShortNumber(blow.overkill)
            .. " of it overkill"
    end
    tail = tail .. "."
    local art = Art(blow.who)
    out[1] = {
        text = string.format("Killed by %s - %s%s",
            ns.UI.HotText(blow.who or "?"),
            ns.UI.HotText(ns.Death.PlainText(blow.spell or "?")), tail),
        who = blow.who, art = art, spellID = blow.spellID, spell = blow.spell,
        summary = blow.summary,
        -- The words, the mob - its face in front of its name, the tip on
        -- both - the ability with its icon in front of it, the numbers.
        pieces = {
            { text = "Killed by " },
            { who = blow.who or "?", art = art, summary = blow.summary },
            { text = " - " },
            { spell = blow.spell or "?", spellID = blow.spellID },
            { text = tail },
        },
    }
    if type(entry.real) == "table" then
        local realArt = Art(entry.real.who)
        local summary = entry.real.who
            and ns.Death.SourceSummary(entry.events, entry.real.who) or nil
        out[2] = {
            text = string.format("The hit that mattered: %s - %s for %s.",
                ns.UI.HotText(entry.real.who or "?"),
                ns.UI.HotText(ns.Death.PlainText(entry.real.spell or "?")),
                ns.ShortNumber(entry.real.landed or 0)),
            who = entry.real.who, art = realArt,
            spellID = entry.real.spellID, spell = entry.real.spell,
            summary = summary,
            pieces = {
                { text = "The hit that mattered: " },
                { who = entry.real.who or "?", art = realArt, summary = summary },
                { text = " - " },
                { spell = entry.real.spell or "?", spellID = entry.real.spellID },
                { text = " for " .. ns.ShortNumber(entry.real.landed or 0) .. "." },
            },
        }
    end
    return out
end

-- What ended them, and - when the killing blow was mostly wasted on a corpse
-- - which hit actually did the work. One sentence, for chat and the desk.
function RaidDeaths.DetailLine(entry)
    if type(entry) ~= "table" then return "" end
    local blow = entry.blow
    if not blow then return entry.blowWhy or "nothing readable" end

    -- The mob and the ability are the two words in this line that answer the
    -- mouse on the row it came from, so they carry the same orange there.
    local line = string.format("Killed by %s - %s",
        ns.UI.HotText(blow.who or "?"),
        ns.UI.HotText(ns.Death.PlainText(blow.spell or "?")))
    if type(blow.amount) == "number" and blow.amount > 0 then
        line = line .. " for " .. ns.ShortNumber(blow.amount)
    end
    if type(blow.overkill) == "number" and blow.overkill > 0 then
        line = line .. ", " .. ns.ShortNumber(blow.overkill) .. " of it overkill"
    end
    line = line .. "."

    if type(entry.real) == "table" then
        line = line .. string.format("  The hit that mattered: %s - %s for %s.",
            ns.UI.HotText(entry.real.who or "?"),
            ns.UI.HotText(ns.Death.PlainText(entry.real.spell or "?")),
            ns.ShortNumber(entry.real.landed or 0))
    end
    return line
end

-- THE GAME'S OWN VERDICT over these seconds. Three answers as everywhere
-- else: how many it calls avoidable, a clean bill only when it answered
-- EVERY time, and silence when it did not.
function RaidDeaths.DetailVerdict(events)
    local yes, no, unknown = RaidDeaths.AvoidableHits(events)
    if yes > 0 then
        return string.format("%d of these hits %s damage the game calls "
            .. "avoidable.", yes, yes == 1 and "is" or "are")
    end
    if no > 0 and unknown == 0 then
        return "None of this was damage the game calls avoidable."
    end
    return ""
end

-- WHAT THIS LIST IS NOT SHOWING, said out loud. Both halves are real: the
-- recap hands over more history than ten seconds, and a very long death is
-- trimmed on the way into memory. A list that quietly starts in the middle
-- reads as the whole story.
function RaidDeaths.DetailNote(entry, stale, window)
    local parts = {}
    if stale then
        parts[#parts + 1] = string.format(
            "Nothing here falls inside the last %d seconds, so this is all "
            .. "the recap gave.", window or ns.Death.WINDOW)
    else
        parts[#parts + 1] = string.format("The last %d seconds.",
            window or ns.Death.WINDOW)
    end
    local dropped = type(entry) == "table" and entry.dropped
    if type(dropped) == "number" and dropped > 0 then
        parts[#parts + 1] = string.format(
            "%d older hit%s the recap gave %s not kept.",
            dropped, dropped == 1 and "" or "s", dropped == 1 and "is" or "are")
    end
    return table.concat(parts, "  ")
end

function RaidDeaths:Refresh()
    if not (frame and frame:IsShown()) then return end
    local C = ns.UI.C

    local entries, info, source = RaidDeaths.Best()
    entries = entries or {}

    frame.title:SetText("Deaths in the group")

    -- The evening's page carries its own head. The pull's would be answering
    -- a question the page is not asking.
    if RaidDeaths.overview then
        frame.where:SetText("")
        frame.verdict:SetText("")
    elseif not info then
        frame.where:SetText(tostring(source))
        frame.verdict:SetText("")
    else
        -- The death window's header shape: the time and the killer on one
        -- line, the place under it. Here the place carries the clock - and
        -- the PLACE is the blue half, the colour every place name in the
        -- addon wears now (owner, 2026-08-16).
        local where = info.when and (info.when .. "  -  ") or ""
        where = where .. ns.UI.CoolText(info.where or info.label or "")
        if info.duration then
            where = where .. "  -  " .. RaidDeaths.Clock(info.duration)
        end
        if source == "session" then
            where = where .. "  -  no clock left on these"
        end
        -- A PULL FROM EARLIER IN THE EVENING is a tally line rather than a
        -- recording: who fell and to what, and nothing underneath. Said
        -- here, because the page otherwise looks like a pull whose recap
        -- refused every death - which is a fault, and this is not.
        if info.thin then
            where = where .. "  -  no hits kept this far back"
        end
        frame.where:SetText(where)
        frame.verdict:SetText(RaidDeaths.Verdict(entries, info.culprits))
    end

    local timed = info and info.timed
    local killCounts = RaidDeaths.KillCounts(info and info.culprits)
    for index, entry in ipairs(entries) do
        entry.killedHere = entry.blow and entry.blow.who
            and killCounts[entry.blow.who] or nil
        local row = frame.rows[index]
        if not row then
            row = BuildRow(frame.content)
            frame.rows[index] = row
            if index == 1 then
                row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, 0)
            else
                row:SetPoint("TOPLEFT", frame.rows[index - 1],
                    "BOTTOMLEFT", 0, -2)
            end
            row:SetPoint("RIGHT", frame.content, "RIGHT", 0, 0)
        end

        row.when:SetText(timed and RaidDeaths.Clock(entry.at) or "--:--")

        -- ASKED AGAIN AT PAINT TIME, and their own run is why.
        --
        -- `/zs test` in game reported "0 of 17 had a readable spec". The
        -- capture happens DURING the fight, and an inspect is throttled to
        -- one question every two seconds and often refused outright in
        -- combat - so the answer nearly always lands after the row that
        -- wanted it. Read once and frozen, the icon could then never become
        -- the right one, no matter how long the window stayed open.
        --
        -- So a row with no spec asks again while it is being drawn, and what
        -- comes back is written onto the entry: by the time somebody opens
        -- this window the inspects have long since answered. A spec already
        -- captured WINS - that person may have left the group since, and the
        -- answer taken while they were still here is the better one.
        if not entry.spec and ns.Specs then
            entry.spec = ns.Specs.OfName(entry.name)
        end
        -- The hint only where it is true. A magnifier over a death whose
        -- recap said nothing would promise a page that does not exist.
        if RaidDeaths.Openable(entry) then
            ns.UI.PaintSearchIcon(row.glass)
        else
            row.glass:Hide()
        end

        ns.UI.PaintSpecIcon(row.spec, entry.spec, entry.class)
        ns.Death.PaintFace(row.face, entry.blow and entry.blow.art)

        local colour = entry.class and RAID_CLASS_COLORS
            and RAID_CLASS_COLORS[entry.class]
        row.who:SetText(entry.short .. (entry.you and " (you)" or ""))
        if type(colour) == "table" and colour.r then
            row.who:SetTextColor(colour.r, colour.g, colour.b)
        else
            row.who:SetTextColor(C.text[1], C.text[2], C.text[3])
        end

        -- The row keeps the death it is drawing, because the two hover
        -- targets are built once and read it at the moment the mouse
        -- arrives, not at the moment they were made. The index goes with it:
        -- a click has to name WHICH death, and the pool's slot number is not
        -- that once the list is repainted.
        row.entry = entry
        row.index = index

        local blow = entry.blow
        if blow then
            -- ORANGE MEANS THIS ANSWERS THE MOUSE. Both of these open
            -- something when you point at them - the mob its big tip, the
            -- ability the client's own tooltip - and nothing else on the row
            -- does.
            row.killer:SetText(blow.who or "?")
            row.killer:SetTextColor(C.hot[1], C.hot[2], C.hot[3])
            -- The ability gets its icon, which is the rule everywhere in this
            -- addon: a name says what hit, a picture says which one it was.
            row.spell:SetText(ns.Death.SpellText(blow.spellID, blow.spell))
            row.spell:SetTextColor(C.hot[1], C.hot[2], C.hot[3])
            if type(blow.amount) == "number" and blow.amount > 0 then
                row.amount:SetText(ns.ShortNumber(blow.amount))
            else
                row.amount:SetText("")
            end
        else
            row.killer:SetText("")
            row.spell:SetText(entry.blowWhy or "nothing readable")
            row.spell:SetTextColor(C.textFaint[1], C.textFaint[2],
                C.textFaint[3])
            row.amount:SetText("")
        end
        row:Show()
    end

    for index = #entries + 1, #frame.rows do
        frame.rows[index]:Hide()
        frame.rows[index].entry = nil
        frame.rows[index].index = nil
    end

    frame.content:SetHeight(math.max(1, #entries * (ROW_H + 2)))

    local anyOpenable = false
    for _, entry in ipairs(entries) do
        if RaidDeaths.Openable(entry) then anyOpenable = true break end
    end
    frame.foot.Paint(RaidDeaths.FootPieces(
        (info and info.culprits) or {}, #entries, anyOpenable, entries,
        RaidDeaths.log))

    -- WHICH DEATH IS BEING READ, checked against the list that is actually
    -- on screen. A kept index survives a repaint, and a repaint can come
    -- from a capture two seconds later with one fewer readable death in it.
    local reading = RaidDeaths.reading and entries[RaidDeaths.reading] or nil
    if not RaidDeaths.Openable(reading) then
        reading = nil
        RaidDeaths.reading = nil
    end
    RaidDeaths.PaintDetail(reading, info)

    -- ONE LIST, ONE NAME. The column IS the evening now, so the button says
    -- so on both pages rather than offering two words for one thing - and
    -- the share still sends whichever page is being read.
    frame.clear.label:SetText("Clear tonight")

    RaidDeaths.PaintSideList()
end

-- THE HEAD OF THE PAGE, ordered by what is actually there to draw.
--
-- The portrait is a maybe: the client only draws a face for somebody it can
-- still see, so a group mate who has since left is name and spec alone. A
-- missing picture must cost its own width and nothing else - laid out
-- blind, it leaves a 46-pixel hole with the name shunted out of line, which
-- is exactly what their screenshot showed.
--
-- Anchors rather than a running x: each thing sits on the last thing that
-- IS there, and the first of them sits on the row itself.
function RaidDeaths.LayoutWho(detail, hasFace, hasSpec)
    if not (detail and detail.who) then return end
    local left, edge, gap = detail.who, "LEFT", 0

    if hasFace then left, edge, gap = detail.face, "RIGHT", 8 end

    detail.spec:ClearAllPoints()
    detail.spec:SetPoint("LEFT", left, edge, gap, 0)
    if hasSpec then left, edge, gap = detail.spec, "RIGHT", 10 end

    detail.title:ClearAllPoints()
    detail.title:SetPoint("LEFT", left, edge, gap, 0)
end

-- One person's last seconds, in the space the list was using. Nil closes it
-- and gives the list its room back.
function RaidDeaths.PaintDetail(entry, info)
    if not (frame and frame.detail) then return end
    local detail = frame.detail
    local open = entry ~= nil
    -- THREE THINGS CAN BE IN THIS RECTANGLE and exactly one of them is: the
    -- pull, one death out of it, or the whole evening. Decided here, in one
    -- place, because two functions each hiding "their" frame is how two of
    -- them end up drawn on top of each other.
    local over = (not open) and RaidDeaths.overview == true

    frame.head:SetShown(not open and not over)
    frame.listHost:SetShown(not open and not over)
    -- The footer counts the whole pull. Left standing under one person's
    -- hits it reads as being about them.
    frame.foot:SetShown(not open and not over)
    -- AND SO DOES THE VERDICT. "None of it was avoidable damage" is a
    -- sentence about the PULL, and the detail carries its own about the
    -- person - two verdicts one under the other, one of them answering a
    -- question the page is not asking. It was also the line the portrait was
    -- drawn through.
    frame.verdict:SetShown(not open)
    detail:SetShown(open)
    -- The way out lives in the header now, so it is no longer hidden along
    -- with the page it leaves. Said here, where the page is chosen.
    frame.back:SetShown(open)
    frame.overviewFrame:SetShown(over)
    if over then RaidDeaths.PaintOverview() end

    if not open then
        for _, row in ipairs(detail.rows) do
            row.ev = nil
            row:Hide()
        end
        return
    end

    local timed = info and info.timed
    -- The face is a maybe and the spec icon never is: the class is on the
    -- row whatever happens, so the second picture is always there even when
    -- the first one cannot be.
    local hasFace = ns.Death.PaintUnitFace(detail.face, entry.name)
    if not entry.spec and ns.Specs then
        entry.spec = ns.Specs.OfName(entry.name)
    end
    local hasSpec = ns.UI.PaintSpecIcon(detail.spec, entry.spec, entry.class)
    RaidDeaths.LayoutWho(detail, hasFace, hasSpec)
    detail.title:SetText(RaidDeaths.DetailTitle(entry, timed))
    local lines = RaidDeaths.DetailLines(entry, RaidDeaths.log)
    detail.blow.Paint(lines[1] and lines[1].pieces or {})
    if lines[2] then
        detail.real.Paint(lines[2].pieces)
        detail.real:Show()
    else
        detail.real.Paint({})
        detail.real:SetHeight(1)
        detail.real:Hide()
    end

    -- The same ten seconds the death window promises, out of the same
    -- function - including its answer for a recap that reaches back further
    -- than that and has nothing inside the window.
    local events, stale = ns.Death.RecentEvents(entry.events, ns.Death.WINDOW)
    detail.verdict:SetText(RaidDeaths.DetailVerdict(events))
    detail.note:SetText(RaidDeaths.DetailNote(entry, stale, ns.Death.WINDOW))

    local width = detail.head:GetWidth()
    local EVENT_H = ns.Death.EVENT_ROW_H
    for index, ev in ipairs(events) do
        local row = detail.rows[index]
        if not row then
            row = ns.Death.BuildEventRow(detail.content, width)
            detail.rows[index] = row
        end
        -- A death saved before every hit kept its art: the killing blow's
        -- face stands in for every hit from the same mob, and any kept
        -- pull's picture of it after that.
        if not ev.art then
            ev.art = RaidDeaths.ArtFor(entry, ev.who)
                or RaidDeaths.ArtForWho(RaidDeaths.log, ev.who)
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", detail.content, "TOPLEFT", 0,
            -((index - 1) * (EVENT_H + 2)))
        row:SetPoint("RIGHT", detail.content, "RIGHT", 0, 0)
        ns.Death.PaintEventRow(row, ev, entry.maxHP, events)
    end
    for index = #events + 1, #detail.rows do
        detail.rows[index].ev = nil
        detail.rows[index]:Hide()
    end

    detail.content:SetHeight(math.max(1, #events * (EVENT_H + 2)))
end

-- THE EVENING, DRAWN. Two tables in one scrolling area, laid out against a
-- running cursor rather than anchored to each other: the first table's
-- length is not known until it is drawn, and a second table anchored to a
-- fixed row would sit on top of it the moment a ninth mob turned up.
function RaidDeaths.PaintOverview()
    if not (frame and frame.overviewFrame) then return end
    local C = ns.UI.C
    local over = frame.overviewFrame
    local session = RaidDeaths.session

    over.title:SetText("Tonight")
    over.sub:SetText(RaidDeaths.SessionLine(session))

    local blocks = RaidDeaths.Bosses(session)
    local fallen = RaidDeaths.Fallen(session)
    local used, bossUsed, y = 0, 0, 0

    local function Row()
        used = used + 1
        local row = over.rows[used]
        if not row then
            row = BuildTallyRow(over.content, over.width)
            over.rows[used] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", over.content, "TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", over.content, "RIGHT", 0, 0)
        y = y + TALLY_ROW_H
        row:Show()
        return row
    end

    local function BossRow()
        bossUsed = bossUsed + 1
        local row = over.bossRows[bossUsed]
        if not row then
            row = BuildBossRow(over.content, over.width)
            over.bossRows[bossUsed] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", over.content, "TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", over.content, "RIGHT", 0, 0)
        y = y + BOSS_ROW_H + BOSS_ROW_GAP
        row:Show()
        return row
    end

    -- What was left out, in a row of its own. A table that stops at four and
    -- says nothing reads as a table of four.
    local function More(total, shown)
        if total <= shown then return end
        local row = Row()
        row.count:SetText("")
        ns.Death.PaintFace(row.face, nil)
        row.icon:Hide()
        row.main:SetText(string.format("and %d more", total - shown))
        row.main:SetTextColor(C.textFaint[1], C.textFaint[2], C.textFaint[3])
        row.note:SetText("")
    end

    over.empty:Hide()
    over.headKill:Hide()
    over.headWho:Hide()
    over.verdict:Hide()

    if #blocks == 0 then
        over.empty:ClearAllPoints()
        over.empty:SetPoint("TOPLEFT", over.content, "TOPLEFT", 6, 0)
        over.empty:SetText("Nothing has been kept today yet. A pull with "
            .. "deaths in it turns up here on its own.")
        over.empty:Show()
    else
        local verdict = RaidDeaths.NightVerdict(blocks)
        if verdict ~= "" then
            over.verdict:ClearAllPoints()
            over.verdict:SetPoint("TOPLEFT", over.content, "TOPLEFT", 6, -y)
            over.verdict:SetText(verdict)
            over.verdict:Show()
            y = y + 24
        end

        over.headKill:ClearAllPoints()
        over.headKill:SetPoint("TOPLEFT", over.content, "TOPLEFT", 6, -y)
        over.headKill:Show()
        y = y + 20

        -- WHO FELL, PER FIGHT, ONLY WHEN THERE IS MORE THAN ONE FIGHT.
        -- With a single block that line would name exactly the people the
        -- evening's own table names four rows below it - the same list
        -- twice, and the copy without the avoidable counts.
        local perFight = #blocks > 1

        for _, block in ipairs(blocks) do
            local shut = RaidDeaths.overCollapsed[block.id] == true
            PaintBossRow(BossRow(), block, shut)
            if not shut then
                for index = 1, min(#block.killers, BLOCK_SHOWN) do
                    local killer = block.killers[index]
                    local row = Row()
                    row.count:SetText(killer.deaths .. "x")
                    -- The mob's face, out of whichever kept pull still has
                    -- it.
                    ns.Death.PaintFace(row.face,
                        RaidDeaths.ArtForWho(RaidDeaths.log, killer.who))
                    row.icon:Hide()
                    row.main:SetText(string.format("%s  %s",
                        ns.Death.PlainText(killer.spell), killer.who))
                    row.main:SetTextColor(C.hot[1], C.hot[2], C.hot[3])
                    row.note:SetText(RaidDeaths.RepeatLine(killer))
                end
                More(#block.killers, BLOCK_SHOWN)

                if perFight then
                    local line = RaidDeaths.FellLine(block.fallen)
                    if line ~= "" then
                        local row = Row()
                        row.count:SetText("")
                        ns.Death.PaintFace(row.face, nil)
                        row.icon:Hide()
                        row.main:SetText(line)
                        row.main:SetTextColor(C.textDim[1], C.textDim[2],
                            C.textDim[3])
                        row.note:SetText(RaidDeaths.BossAvoidable(block))
                    end
                end
                y = y + 8
            end
        end

        y = y + 8
        over.headWho:ClearAllPoints()
        over.headWho:SetPoint("TOPLEFT", over.content, "TOPLEFT", 6, -y)
        over.headWho:Show()
        y = y + 20

        for index = 1, min(#fallen, TALLY_SHOWN) do
            local person = fallen[index]
            local row = Row()
            row.count:SetText(person.deaths .. "x")
            ns.Death.PaintFace(row.face, nil)
            ns.UI.PaintSpecIcon(row.icon, person.spec, person.class)
            row.main:SetText(RaidDeaths.Coloured(person.short, person.class)
                .. (person.you and " |cffffd100(you)|r" or ""))
            row.main:SetTextColor(C.text[1], C.text[2], C.text[3])
            row.note:SetText(RaidDeaths.FallenLine(person))
        end
        More(#fallen, TALLY_SHOWN)
    end

    for index = used + 1, #over.rows do over.rows[index]:Hide() end
    for index = bossUsed + 1, #over.bossRows do
        over.bossRows[index]:Hide()
    end
    over.content:SetHeight(math.max(1, y))
end

-- STEPPING INTO A DEATH, and back out. Both go through Refresh rather than
-- painting directly: the detail is one of two things the same rectangle can
-- show, and only the painter knows which of them is on.
function RaidDeaths:Open(index)
    local entries = RaidDeaths.Best()
    if not RaidDeaths.Openable(entries and entries[index]) then return end
    RaidDeaths.reading = index
    RaidDeaths:Refresh()
end

function RaidDeaths:CloseReading()
    RaidDeaths.reading = nil
    RaidDeaths:Refresh()
end

-- How many of the group each killer accounted for, keyed the way the rows
-- ask for it. Pure, so the tooltip's one number does not have to walk the
-- culprit list every time the mouse moves.
function RaidDeaths.KillCounts(culprits)
    local counts = {}
    for _, culprit in ipairs(culprits or {}) do
        if culprit.who then
            counts[culprit.who] = (counts[culprit.who] or 0) + culprit.count
        end
    end
    return counts
end

-- ONE MORE ROW OF THE COLUMN, made the first time it is needed and kept.
-- Recursive so that asking for slot seven builds one to six on the way: the
-- rows are a chain, each hung off the bottom of the one above, and a chain
-- with a hole in it is a row anchored to nothing.
local function SideRow(slot)
    local row = frame.sideRows[slot]
    if row then return row end
    row = BuildSideRow(frame.sideBody, slot)
    if slot == 1 then
        row:SetPoint("TOPLEFT", frame.sessionRow, "BOTTOMLEFT", 0, -SIDE_GAP)
    else
        row:SetPoint("TOPLEFT", SideRow(slot - 1), "BOTTOMLEFT", 0, -SIDE_GAP)
    end
    row:SetPoint("RIGHT", frame.sideBody, "RIGHT", 0, 0)
    frame.sideRows[slot] = row
    return row
end

-- The side list, repainted whole: a row per PLACE, and the pulls under it
-- while it is open. Newest at the top throughout.
function RaidDeaths.PaintSideList()
    if not frame then return end
    local C = ns.UI.C
    local _, selected, pullList = RaidDeaths.Selected()

    -- THE EVENING'S OWN ROW. It counts pulls this DAY, which is a bigger
    -- number than the log beside it holds - and that difference is the whole
    -- reason it exists, so it says both.
    local over = RaidDeaths.overview == true
    local sessionRow = frame.sessionRow
    local pulls = #((RaidDeaths.session or {}).fights or {})
    sessionRow.lead:SetText("Tonight")
    sessionRow.lead:SetTextColor(C.text[1], C.text[2], C.text[3])
    sessionRow.tag:SetText(pulls > 0 and (pulls .. " pulls") or "")
    sessionRow.note:SetText(pulls > 0
        and RaidDeaths.SessionLine(RaidDeaths.session)
        or "nothing kept today yet")
    sessionRow.selected = over
    sessionRow.bg:SetShown(over)
    sessionRow.mark:SetShown(over)
    if over then
        sessionRow.bg:SetColorTexture(C.control[1], C.control[2],
            C.control[3], 1)
    end

    RaidDeaths.collapsed = RaidDeaths.collapsed or {}
    local items = RaidDeaths.SideItems(pullList, RaidDeaths.collapsed)
    -- HOW MANY FIT IS ASKED, NOT COUNTED. Two row heights and a fold mean
    -- the answer changes with the contents, and the same function answers it
    -- for the own-death window's column.
    local first, count, far = ns.Death.ListWindow(items,
        RaidDeaths.sideOffset, RaidDeaths.SideRoom(),
        RaidDeaths.SideHeight, SIDE_GAP)
    RaidDeaths.sideOffset = first - 1
    RaidDeaths.sideMax = far

    -- Nothing in this column is selected while the evening's page is open:
    -- two accent bars would claim the window is showing both. Written out,
    -- because the index may legitimately be nil and `and ... or` would then
    -- be answering a different question.
    local pick
    if not over then pick = selected end
    local military = RaidDeaths.Military()

    -- The pool is read BEFORE the loop: SideRow appends to it, and a loop
    -- bounded by a list it is growing is a loop that decides how long it
    -- runs while it runs.
    local pool = #frame.sideRows
    for slot = 1, math.max(count, pool) do
        local item
        if slot <= count then item = items[first + slot - 1] end
        if item then
            local row = SideRow(slot)
            PaintSideRow(row, item, pick, military)
            row:Show()
        else
            local row = frame.sideRows[slot]
            if row then
                row.index, row.place, row.selected = nil, nil, false
                row.pullKey = nil
                row.level = nil
                row:Hide()
            end
        end
    end

    -- WHAT THE COLUMN HOLDS, and it now has two numbers to say: the pulls,
    -- and how many places they were spread over. No silent caps - a column
    -- that stops at the window's edge and does not say so reads as a column
    -- with nothing more in it.
    local total = #pullList
    local places = 0
    for _, item in ipairs(items) do
        if item.kind == "run" then places = places + 1 end
    end
    if total == 0 then
        frame.sideTitle:SetText("This session - no pull kept yet")
    elseif far > 0 then
        frame.sideTitle:SetText(string.format(
            "%d pulls in %d places - scroll for more", total, places))
    elseif places > 1 then
        frame.sideTitle:SetText(string.format("%d pulls in %d places",
            total, places))
    else
        frame.sideTitle:SetText(total == 1 and "This session - 1 pull"
            or string.format("This session - %d pulls", total))
    end
end

-- The frame itself, for the checks. `frame` is a local, and a local is
-- invisible to every test in the addon - which is exactly how the reminder
-- movers went two versions without a cog and nothing noticed.
function RaidDeaths.Window()
    return frame
end

function RaidDeaths:Show()
    if not ns.UI then return end
    -- One read on the way in, so opening the window during a pull shows that
    -- pull rather than the state of the last tick.
    RaidDeaths.Capture()
    -- And it opens on the PULL. A window that comes back on one person's
    -- last seconds hides the list it is the list of.
    RaidDeaths.reading = nil
    RaidDeaths:Create()
    frame:Show()
    -- To the front on opening, not only on the next click.
    frame:Raise()
    RaidDeaths:Refresh()
end

function RaidDeaths:Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
        return
    end
    RaidDeaths:Show()
end

---------------------------------------------------------------------------
-- The icon, docked to the death one
--
-- The owner's ask: "mach doch ein zweites death log item, mit 3 kleinen
-- sculls, aber genauso gross wie das normale und dock das direkt an das andere
-- icon".
--
-- Anchored to the death icon's FRAME rather than to its saved numbers, so it
-- travels WITH it during a drag instead of catching up when the mouse is
-- released. Its parent is UIParent and not that button, because the two have
-- different reasons to be on screen: you can survive a wipe that killed four
-- other people, and then there is a group log to read and no own death at
-- all. A child would have been hidden along with its parent.
---------------------------------------------------------------------------
local raidIcon

local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
-- Three of them: one over two, which reads as a group at this size where a
-- row of three reads as a smudge. Sized and placed against the 30x30 box the
-- death icon already is - same box, different mark.
local SKULLS = {
    { size = 13, x = 0, y = 5 },
    { size = 13, x = -6, y = -5 },
    { size = 13, x = 6, y = -5 },
}

local function BuildRaidIcon()
    local C = ns.UI.C

    raidIcon = CreateFrame("Button", "ZwoelfStuffRaidDeathIcon", UIParent)
    raidIcon:SetSize(30, 30)
    raidIcon:SetFrameStrata("MEDIUM")
    raidIcon:RegisterForDrag("LeftButton")
    raidIcon:Hide()

    local bg = raidIcon:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(raidIcon)
    bg:SetColorTexture(C.windowBg[1], C.windowBg[2], C.windowBg[3], 0.85)

    local edge = ns.CreateBorder(raidIcon, 1, "BORDER")
    edge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)

    for _, spot in ipairs(SKULLS) do
        local skull = raidIcon:CreateTexture(nil, "ARTWORK")
        skull:SetSize(spot.size, spot.size)
        skull:SetPoint("CENTER", raidIcon, "CENTER", spot.x, spot.y)
        skull:SetTexture(SKULL)
    end

    raidIcon.count = raidIcon:CreateFontString(nil, "OVERLAY")
    ns.Media.ApplyFont(raidIcon.count, nil, 10, "OUTLINE")
    raidIcon.count:SetPoint("BOTTOMRIGHT", raidIcon, "BOTTOMRIGHT", -1, 1)

    raidIcon:SetScript("OnClick", function() RaidDeaths:Toggle() end)

    -- ONE SAVED POSITION, AND WHOEVER IS LEFTMOST SITS ON IT.
    --
    -- Docked, this drags the death icon: it owns the position, and moving
    -- the anchored one would tear the pair apart, which is the opposite of
    -- the word they used. Standing alone - a wipe this character walked out of
    -- - it drags itself and writes the same position back, so the death icon
    -- reappears exactly where the pair was left.
    raidIcon:SetScript("OnDragStart", function(self)
        if ns.Death.IconLocked() then return end
        if self.docked then
            ns.Death.DragIcon(true)
        else
            self:StartMoving()
        end
    end)
    raidIcon:SetScript("OnDragStop", function(self)
        if self.docked then
            ns.Death.DragIcon(false)
            return
        end
        self:StopMovingOrSizing()
        ns.Death.SaveIconAt(self)
        ns.Death.RefreshIcon()
    end)

    raidIcon:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        local entries, _, source = RaidDeaths.Best()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(string.format("Deaths in the group: %d",
            entries and #entries or 0), 1, 1, 1)
        if source == "kept" then
            GameTooltip:AddLine("From the last pull - the game forgets it "
                .. "when the next one starts.", 0.6, 0.63, 0.69, true)
        elseif source == "session" then
            GameTooltip:AddLine("No clock left on these - only the order.",
                0.6, 0.63, 0.69, true)
        end
        GameTooltip:AddLine("Click to open. Drag to move both icons.",
            0.6, 0.63, 0.69, true)
        GameTooltip:Show()
    end)
    raidIcon:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
end

-- Same reason as Window above: a check cannot press what it cannot reach.
function RaidDeaths.Icon()
    return raidIcon
end

-- How many deaths the icon is offering, and therefore whether it is offered
-- at all. Pure: the same three-way answer the window's header gives.
function RaidDeaths.IconCount()
    local entries = RaidDeaths.Best()
    return entries and #entries or 0
end

function RaidDeaths.RefreshIcon()
    if not ns.UI then return end
    local cfg = (ns.db and ns.db.death and ns.db.death.icon) or {}
    local moduleOff = ns.Modules and not ns.Modules:IsOn("deaths")
    local count = RaidDeaths.IconCount()

    if moduleOff or cfg.show == false then
        if raidIcon then raidIcon:Hide() end
        -- The one behind it docks to THIS one when it is up, so it has to be
        -- told the moment it is not.
        if ns.CombatLog then ns.CombatLog.RefreshIcon() end
        return
    end
    if not raidIcon then BuildRaidIcon() end

    -- Docked only when there is something to dock TO. Standing alone it takes
    -- the pair's own position, so the two never sit 34 pixels apart with
    -- nothing in between.
    local anchor = ns.Death.EnsureIcon()
    local docked = anchor ~= nil and ns.Death.IconShown()
    raidIcon.docked = docked
    raidIcon:SetMovable(not docked)

    raidIcon:ClearAllPoints()
    if docked then
        raidIcon:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
    else
        raidIcon:SetPoint("CENTER", UIParent, "CENTER",
            cfg.x or 320, cfg.y or -180)
    end
    -- WITH NOTHING IN IT, NO BADGE - and the icon stays. Owner, 2026-08-29:
    -- all three are always on screen now. A "0" in the corner would be a
    -- count of nothing dressed as a count.
    raidIcon.count:SetText(count > 0 and tostring(count) or "")
    raidIcon:Show()

    -- The third one hangs off this one, so it is refreshed after this has
    -- decided whether it is on screen and not before.
    if ns.CombatLog then ns.CombatLog.RefreshIcon() end

    -- The window behind it, if it happens to be open, is looking at the same
    -- three-way answer and has to move with it.
    RaidDeaths:Refresh()
end
