---------------------------------------------------------------------------
-- RaidDeaths.lua - who else died, when, and to what
--
-- His ask: a timeline of who died, when, and to what - "sollte man aus dem
-- dmg meter ablesen koennen." He was right, and Death.OwnRecapID had been
-- reading that very list for weeks and throwing away every row but his own.
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
    -- a different thing from "he died at second zero".
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

-- What did the killing, counted. This is the row of mobs and abilities he
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
-- His ask after the first live run: a death in the list should open the way
-- his own does - the last ten seconds of the person who fell. The recap says
-- all of it and always did; this file was keeping the last line and throwing
-- the story away.
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
-- His first live run: "4 in this session, 27:39 long (no clock)" and `--:--`
-- on every line. Nothing was broken - he typed the command AFTER the pull,
-- and by then the Current session had been reset and only Overall was left,
-- which answers -1 for every death. The whole point of the feature is when
-- each person fell, and that number exists only while the fight is running.
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
function RaidDeaths.Remember(log, fight, cap)
    local last = log[#log]
    if last and fight.key and last.key == fight.key then
        log[#log] = fight
    else
        log[#log + 1] = fight
        while #log > (cap or FIGHTS_KEPT) do table.remove(log, 1) end
    end
    return fight
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

-- Read what the client is holding and keep it if it is worth keeping. Only a
-- TIMED list is captured: an untimed one is Overall, which is not a fight and
-- would overwrite a good capture with a worse one.
function RaidDeaths.Capture()
    local rows, _, duration = RaidDeaths.Read()
    if not rows or #rows == 0 then return nil end

    local entries, timed = RaidDeaths.Timeline(rows)
    if not timed then return nil end

    local key = RaidDeaths.FightKey(entries)
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

    local where, whereShort = ns.Death.Where()
    local fight = RaidDeaths.Remember(RaidDeaths.log, {
        key = key,
        at = GetTime(),
        when = date("%H:%M:%S"),
        where = where,
        whereShort = whereShort,
        duration = duration,
        entries = entries,
        culprits = RaidDeaths.Culprits(entries),
    }, FIGHTS_KEPT)

    -- Every tick rather than at the end of the pull. Saved variables only
    -- reach the disk at logout, so this is not about crashes - it is about
    -- the in-memory copy being CURRENT when he types /reload in the middle
    -- of a fight, which is when he types it.
    RaidDeaths.Save()
    return fight
end

function RaidDeaths.Newest()
    return RaidDeaths.log[#RaidDeaths.log]
end

---------------------------------------------------------------------------
-- Surviving a reload
--
-- The same argument the own-death log made, and it is stronger here: a
-- reload happens after every settings change and every error, and the side
-- list is a list of PULLS. One that empties itself every time he presses
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

local function Store()
    if not ns.account then return nil end
    ns.account.raidDeaths = ns.account.raidDeaths or {}
    return ns.account.raidDeaths
end

function RaidDeaths.Save()
    local store, key = Store(), ns.CharacterKey()
    if not (store and key) then return end
    local out = {}
    for _, fight in ipairs(RaidDeaths.log) do
        local kept = RaidDeaths.Persist(fight)
        if kept then out[#out + 1] = kept end
    end
    store[key] = out
end

function RaidDeaths.Load()
    local store, key = Store(), ns.CharacterKey()
    if not (store and key) then return end
    RaidDeaths.log = RaidDeaths.Restore(store[key])
    RaidDeaths.showing = nil
    RaidDeaths.RefreshIcon()
end

-- WHICH PULL IS BEING LOOKED AT. `showing` is an index into the log and nil
-- means the newest, exactly like Death.showing. Clamped rather than wrapped:
-- paging past the oldest and landing on the newest reads as the list
-- jumping, not as an edge.
function RaidDeaths.Selected()
    local total = #RaidDeaths.log
    if total == 0 then return nil end
    local index = RaidDeaths.showing or total
    if index < 1 then index = 1 end
    if index > total then index = total end
    RaidDeaths.showing = index
    return RaidDeaths.log[index], index
end

-- WHAT TO SHOW: the pull that is selected, or - when nothing has been
-- captured at all - whatever the client still has lying about with no clock
-- on it. Returns entries, an info table and which of the two answered, so
-- the window says where its numbers came from rather than implying.
function RaidDeaths.Best()
    local fight = RaidDeaths.Selected()
    if fight then
        return fight.entries, {
            timed = true,
            duration = fight.duration,
            label = fight.whereShort and (fight.whereShort .. ", " .. fight.when)
                or fight.when,
            where = fight.where,
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
local ROW_H, FACE = 26, 22
-- 820 is the width of the options window, so two of this addon's windows
-- open on top of each other rather than beside each other.
local WIDTH, HEIGHT = 820, 470
local SIDE_W, SIDE_ROW_H, SIDE_ROWS = 196, 34, 9

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

    row.when = UI.Label(row, "", UI.FS.meta, C.textFaint)
    row.when:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.when:SetWidth(52)
    row.when:SetJustifyH("LEFT")

    -- A model frame is not free, so it is built with the row and simply
    -- hidden when a death has no readable face - the rows are reused.
    row.face = CreateFrame("PlayerModel", nil, row)
    row.face:SetSize(FACE, FACE)
    row.face:SetPoint("LEFT", row.when, "RIGHT", 2, 0)
    row.face:Hide()

    row.who = UI.Label(row, "", UI.FS.row, C.text)
    row.who:SetPoint("LEFT", row.face, "RIGHT", 6, 0)
    row.who:SetWidth(150)
    row.who:SetJustifyH("LEFT")
    row.who:SetWordWrap(false)

    row.killer = UI.Label(row, "", UI.FS.meta, C.textDim)
    row.killer:SetPoint("LEFT", row.who, "RIGHT", 6, 0)
    row.killer:SetWidth(150)
    row.killer:SetJustifyH("LEFT")
    row.killer:SetWordWrap(false)

    row.spell = UI.Label(row, "", UI.FS.meta, C.textDim)
    row.spell:SetPoint("LEFT", row.killer, "RIGHT", 6, 0)
    row.spell:SetPoint("RIGHT", row, "RIGHT", -62, 0)
    row.spell:SetJustifyH("LEFT")
    row.spell:SetWordWrap(false)

    row.amount = UI.Label(row, "", UI.FS.meta, C.textDim)
    row.amount:SetPoint("RIGHT", row, "RIGHT", 0, 0)
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

    -- And the face itself, which is the thing he actually points at.
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

-- ONE PULL IN THE SIDE LIST: when it was, where, and how many fell.
local function BuildSideRow(parent, slot)
    local UI, C = ns.UI, ns.UI.C
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(SIDE_ROW_H)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:Hide()

    -- The accent bar on the left edge marks the one being read, exactly as
    -- the death window's list does. A fill alone reads as hover on a list
    -- you can also hover.
    row.mark = row:CreateTexture(nil, "ARTWORK")
    row.mark:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.mark:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.mark:SetWidth(2)
    row.mark:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    row.mark:Hide()

    row.when = UI.Label(row, "", UI.FS.meta, C.text)
    row.when:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -3)

    -- Where, in the cool accent and on the right, which is where the death
    -- window puts "M+18". The count moves down to the second line with it.
    row.count = UI.Label(row, "", UI.FS.eyebrow, C.accentCool)
    row.count:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -3)
    row.count:SetJustifyH("RIGHT")

    row.where = UI.Label(row, "", UI.FS.meta, C.textFaint)
    row.where:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 4)
    row.where:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 4)
    row.where:SetJustifyH("LEFT")
    row.where:SetWordWrap(false)

    row:SetScript("OnClick", function(self)
        if not self.index then return end
        RaidDeaths.showing = self.index
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

function RaidDeaths:Create()
    if frame then return frame end
    local UI, C = ns.UI, ns.UI.C

    frame = CreateFrame("Frame", "ZwoelfStuffRaidDeaths", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
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

    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(C.separator[1], C.separator[2], C.separator[3], 1)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -UI.HEADER_H)
    rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -UI.HEADER_H)

    -- Where the numbers came from, said out loud. A list that is quietly the
    -- last pull rather than this one is the kind of thing somebody reads
    -- wrongly once and never trusts again.
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

    frame.headWhen = UI.Eyebrow(head, "When")
    frame.headWhen:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 0, 0)
    frame.headWho = UI.Eyebrow(head, "Who died")
    frame.headWho:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 80, 0)
    frame.headKiller = UI.Eyebrow(head, "Killed by")
    frame.headKiller:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 236, 0)
    frame.headWhat = UI.Eyebrow(head, "With what")
    frame.headWhat:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 392, 0)
    frame.headAmount = UI.Eyebrow(head, "Damage")
    frame.headAmount:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", 0, 0)

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
        -(UI.HEADER_H + 8))
    side:SetPoint("BOTTOM", frame, "BOTTOM", 0, 40)
    frame.side = side

    frame.sideTitle = UI.Label(side, "", UI.FS.meta, C.textFaint)
    frame.sideTitle:SetPoint("TOPLEFT", side, "TOPLEFT", 8, 0)

    local sideRule = frame:CreateTexture(nil, "ARTWORK")
    sideRule:SetColorTexture(C.separator[1], C.separator[2], C.separator[3], 1)
    sideRule:SetWidth(1)
    sideRule:SetPoint("TOPRIGHT", side, "TOPLEFT", -8, 0)
    sideRule:SetPoint("BOTTOMRIGHT", side, "BOTTOMLEFT", -8, 0)

    frame.sideRows = {}
    for slot = 1, SIDE_ROWS do
        local row = BuildSideRow(side, slot)
        if slot == 1 then
            row:SetPoint("TOPLEFT", frame.sideTitle, "BOTTOMLEFT", -8, -6)
        else
            row:SetPoint("TOPLEFT", frame.sideRows[slot - 1],
                "BOTTOMLEFT", 0, -2)
        end
        row:SetPoint("RIGHT", side, "RIGHT", 0, 0)
        frame.sideRows[slot] = row
    end

    -- The wheel pages the side list, the way the death window's does. A list
    -- longer than nine with no way down is a list that lies about its length.
    side:EnableMouseWheel(true)
    side:SetScript("OnMouseWheel", function(_, delta)
        local total = #RaidDeaths.log
        if total <= SIDE_ROWS then return end
        local offset = (RaidDeaths.sideOffset or 0) - delta
        RaidDeaths.sideOffset = math.max(0, math.min(total - SIDE_ROWS, offset))
        RaidDeaths:Refresh()
    end)

    local listHost = CreateFrame("Frame", nil, frame)
    listHost:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -8)
    listHost:SetPoint("BOTTOMRIGHT", side, "BOTTOMLEFT", -18, 26)
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
    local detail = CreateFrame("Frame", nil, frame)
    detail:SetPoint("TOPLEFT", head, "TOPLEFT", 0, 14)
    detail:SetPoint("BOTTOMRIGHT", listHost, "BOTTOMRIGHT", 0, 0)
    detail:Hide()
    frame.detail = detail

    detail.back = UI.Button(detail, "Back to the pull", 140,
        function() RaidDeaths:CloseReading() end)
    detail.back:SetPoint("TOPLEFT", detail, "TOPLEFT", 0, 0)

    detail.title = UI.Label(detail, "", UI.FS.card, C.text)
    detail.title:SetPoint("LEFT", detail.back, "RIGHT", 12, 0)

    detail.sub = UI.Label(detail, "", UI.FS.meta, C.textDim)
    detail.sub:SetPoint("TOPLEFT", detail.back, "BOTTOMLEFT", 0, -10)
    detail.sub:SetPoint("RIGHT", detail, "RIGHT", 0, 0)
    detail.sub:SetJustifyH("LEFT")

    detail.verdict = UI.Label(detail, "", UI.FS.meta, C.accentCool)
    detail.verdict:SetPoint("TOPLEFT", detail.sub, "BOTTOMLEFT", 0, -4)

    detail.note = UI.Label(detail, "", UI.FS.meta, C.textFaint)
    detail.note:SetPoint("TOPLEFT", detail.verdict, "BOTTOMLEFT", 0, -4)

    -- The same head the death window puts over its own last ten seconds,
    -- out of the same function - one table in two windows.
    detail.head = ns.Death.BuildEventHead(detail, MAIN_W - 8,
        "What hit them")
    detail.head:SetPoint("TOPLEFT", detail.note, "BOTTOMLEFT", 0, -12)

    local detailHost = CreateFrame("Frame", nil, detail)
    detailHost:SetPoint("TOPLEFT", detail.head, "BOTTOMLEFT", 0, -8)
    detailHost:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", 0, 0)
    local _, detailContent = UI.ScrollArea(detailHost, MAIN_W - 8, 8)
    detail.content = detailContent
    detail.rows = {}

    frame.foot = UI.Label(frame, "", UI.FS.meta, C.textFaint)
    frame.foot:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", UI.PAD, 46)
    frame.foot:SetPoint("RIGHT", side, "LEFT", -18, 0)
    frame.foot:SetJustifyH("LEFT")

    -----------------------------------------------------------------------
    -- The same two buttons the death window carries, in the same corner.
    -----------------------------------------------------------------------
    local share = UI.Button(frame, "Share in chat", 130,
        function() RaidDeaths:Share() end, "primary")
    share:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", UI.PAD, 14)
    frame.share = share

    local clear = UI.Button(frame, "Clear list", 100, function()
        RaidDeaths.log = {}
        RaidDeaths.showing = nil
        RaidDeaths.sideOffset = 0
        RaidDeaths.Save()
        RaidDeaths:Refresh()
        RaidDeaths.RefreshIcon()
    end)
    clear:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -UI.PAD, 14)
    frame.clear = clear

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

function RaidDeaths:Share()
    local entries, info = RaidDeaths.Best()
    local lines = RaidDeaths.ShareLines(entries, info)
    if not lines then
        ns.Print("No pull with deaths in it yet.")
        return
    end

    local channel, why = ns.Death.ShareTarget(
        ns.db and ns.db.death and ns.db.death.channel, ns.Death.GroupState())
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    for _, line in ipairs(lines) do
        if channel then
            send("ZwoelfStuff: " .. line, channel)
        else
            ns.Print(line)
        end
    end
    if not channel then
        -- Death's rule, and it is not negotiable: a chosen channel that is
        -- not there must SAY so. Printing to your own frame while you believe
        -- it went to the raid is the one failure a share is not allowed.
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
        line = "What did the killing: " .. table.concat(parts, ", ")
        if #culprits > CULPRITS_SHOWN then
            line = line .. string.format(", and %d more",
                #culprits - CULPRITS_SHOWN)
        end
    end
    if openable then
        line = line .. "   -   click a death for their last ten seconds"
    end
    return line
end

---------------------------------------------------------------------------
-- ONE DEATH, OPENED
--
-- His own death window answers "what happened to me"; this answers the same
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

-- What ended them, and - when the killing blow was mostly wasted on a corpse
-- - which hit actually did the work.
function RaidDeaths.DetailLine(entry)
    if type(entry) ~= "table" then return "" end
    local blow = entry.blow
    if not blow then return entry.blowWhy or "nothing readable" end

    local line = string.format("Killed by %s - %s", blow.who or "?",
        ns.Death.PlainText(blow.spell or "?"))
    if type(blow.amount) == "number" and blow.amount > 0 then
        line = line .. " for " .. ns.ShortNumber(blow.amount)
    end
    if type(blow.overkill) == "number" and blow.overkill > 0 then
        line = line .. ", " .. ns.ShortNumber(blow.overkill) .. " of it overkill"
    end
    line = line .. "."

    if type(entry.real) == "table" then
        line = line .. string.format("  The hit that mattered: %s - %s for %s.",
            entry.real.who or "?",
            ns.Death.PlainText(entry.real.spell or "?"),
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

    if not info then
        frame.where:SetText(tostring(source))
        frame.verdict:SetText("")
    else
        -- The death window's header shape: the time and the killer on one
        -- line, the place under it. Here the place carries the clock.
        local where = info.when and (info.when .. "  -  ") or ""
        where = where .. (info.where or info.label or "")
        if info.duration then
            where = where .. "  -  " .. RaidDeaths.Clock(info.duration)
        end
        if source == "session" then
            where = where .. "  -  no clock left on these"
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

        ns.Death.PaintArt(row.face, entry.blow and entry.blow.art)

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
            row.killer:SetText(blow.who or "?")
            row.killer:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
            -- The ability gets its icon, which is the rule everywhere in this
            -- addon: a name says what hit, a picture says which one it was.
            row.spell:SetText(ns.Death.SpellText(blow.spellID, blow.spell))
            row.spell:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
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
    frame.foot:SetText(RaidDeaths.FootLine(
        (info and info.culprits) or {}, #entries, anyOpenable))

    -- WHICH DEATH IS BEING READ, checked against the list that is actually
    -- on screen. A kept index survives a repaint, and a repaint can come
    -- from a capture two seconds later with one fewer readable death in it.
    local reading = RaidDeaths.reading and entries[RaidDeaths.reading] or nil
    if not RaidDeaths.Openable(reading) then
        reading = nil
        RaidDeaths.reading = nil
    end
    RaidDeaths.PaintDetail(reading, info)

    RaidDeaths.PaintSideList()
end

-- One person's last seconds, in the space the list was using. Nil closes it
-- and gives the list its room back.
function RaidDeaths.PaintDetail(entry, info)
    if not (frame and frame.detail) then return end
    local detail = frame.detail
    local open = entry ~= nil

    frame.head:SetShown(not open)
    frame.listHost:SetShown(not open)
    -- The footer counts the whole pull. Left standing under one person's
    -- hits it reads as being about them.
    frame.foot:SetShown(not open)
    detail:SetShown(open)

    if not open then
        for _, row in ipairs(detail.rows) do
            row.ev = nil
            row:Hide()
        end
        return
    end

    local timed = info and info.timed
    detail.title:SetText(RaidDeaths.DetailTitle(entry, timed))
    detail.sub:SetText(RaidDeaths.DetailLine(entry))

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
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", detail.content, "TOPLEFT", 0,
            -((index - 1) * (EVENT_H + 2)))
        ns.Death.PaintEventRow(row, ev, entry.maxHP)
    end
    for index = #events + 1, #detail.rows do
        detail.rows[index].ev = nil
        detail.rows[index]:Hide()
    end

    detail.content:SetHeight(math.max(1, #events * (EVENT_H + 2)))
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

-- The side list, repainted whole. Newest at the top.
function RaidDeaths.PaintSideList()
    if not frame then return end
    local C = ns.UI.C
    local log = RaidDeaths.log
    local total = #log
    local _, selected = RaidDeaths.Selected()

    local offset = math.max(0, math.min(math.max(0, total - SIDE_ROWS),
        RaidDeaths.sideOffset or 0))
    RaidDeaths.sideOffset = offset

    for slot = 1, SIDE_ROWS do
        local row = frame.sideRows[slot]
        local index = total - (offset + slot - 1)
        local fight = index >= 1 and log[index] or nil
        if not fight then
            row.index = nil
            row:Hide()
        else
            row.index = index
            row.when:SetText(fight.when or "")
            row.count:SetText(fight.whereShort or "")

            -- The second line is what the pull WAS, the way the death
            -- window's second line names the killer: how many fell and to
            -- what, not a repeat of the header.
            local dead = #(fight.entries or {})
            local worst = (fight.culprits or {})[1]
            local line = string.format("%d dead", dead)
            if worst and worst.count > 1 then
                line = line .. "  -  " .. (worst.spell or worst.who or "?")
            elseif fight.duration then
                line = line .. "  -  " .. RaidDeaths.Clock(fight.duration)
            end
            row.where:SetText(line)

            local isOn = index == selected
            row.bg:SetShown(isOn)
            row.mark:SetShown(isOn)
            if isOn then
                row.bg:SetColorTexture(C.control[1], C.control[2],
                    C.control[3], 1)
            end
            row:Show()
        end
    end

    -- The death window's own wording, so the two lists read as one idea.
    if total == 0 then
        frame.sideTitle:SetText("This session - no pull kept yet")
    elseif total > SIDE_ROWS then
        frame.sideTitle:SetText(string.format("%d pulls - scroll for more",
            total))
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
-- His ask: "mach doch ein zweites death log item, mit 3 kleinen sculls, aber
-- genauso gross wie das normale und dock das direkt an das andere icon".
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
    -- the word he used. Standing alone - a wipe this character walked out of
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

    if moduleOff or count == 0 or cfg.show == false then
        if raidIcon then raidIcon:Hide() end
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
    raidIcon.count:SetText(tostring(count))
    raidIcon:Show()

    -- The window behind it, if it happens to be open, is looking at the same
    -- three-way answer and has to move with it.
    RaidDeaths:Refresh()
end
