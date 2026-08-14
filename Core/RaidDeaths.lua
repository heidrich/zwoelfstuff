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
            }
        end
    end
    return nil
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

-- The whole picture: the timeline, each entry's killing blow, and what the
-- fight adds up to. Kept apart from Read so the ordering can be exercised at
-- a desk with no recap API in the room.
function RaidDeaths.Collect(me)
    local rows, why, duration, label = RaidDeaths.Read(me)
    if not rows then return nil, why end

    local entries, timed = RaidDeaths.Timeline(rows)
    for _, entry in ipairs(entries) do
        if entry.recapID then
            local events, _, readWhy, _, art = ns.Death.ReadRecap(entry.recapID)
            entry.blow = events and RaidDeaths.Blow(events) or nil
            if entry.blow then
                -- The face belongs to whichever event carried one; the recap's
                -- own answer is the fallback, never the row's own creature id,
                -- which is the dead one - see the header.
                entry.blow.art = entry.blow.art or art
            else
                entry.blowWhy = readWhy or "the recap gave nothing"
            end
        else
            entry.blowWhy = "no recap id on this death"
        end
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
            entry.blow, entry.blowWhy = was.blow, was.blowWhy
            entry.tries = was.tries
        elseif entry.recapID then
            local events, _, readWhy, _, art = ns.Death.ReadRecap(entry.recapID)
            entry.blow = events and RaidDeaths.Blow(events) or nil
            if entry.blow then
                entry.blow.art = entry.blow.art or art
            else
                entry.blowWhy = readWhy or "the recap gave nothing"
            end
            entry.tries = ((was and was.tries) or 0) + 1
        else
            entry.blowWhy = "no recap id on this death"
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
local Plain = function(...) return ns.Death.Plain(...) end

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
            out.entries[#out.entries + 1] = {
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
        if not (GameTooltip and row.entry) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        onEnter(row.entry)
        GameTooltip:Show()
    end)
    hit:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    return hit
end

local function BuildRow(parent)
    local UI, C = ns.UI, ns.UI.C
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)

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
    row.killerHit = HoverOver(row, row.killer, function(entry)
        local blow = entry.blow
        GameTooltip:ClearLines()
        GameTooltip:AddLine((blow and blow.who) or "?", 1, 1, 1)
        local killed = entry.killedHere or 1
        GameTooltip:AddLine(killed == 1 and "Killed one of you this pull"
            or string.format("Killed %d of you this pull", killed),
            0.61, 0.64, 0.69)
        if blow and blow.art and blow.art.creatureID then
            GameTooltip:AddLine("The picture beside the row is this one.",
                0.61, 0.64, 0.69, true)
        end
    end)

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

    row.when = UI.Label(row, "", UI.FS.meta, C.text)
    row.when:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -3)

    row.count = UI.Label(row, "", UI.FS.meta, C.textFaint)
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
    listHost:SetPoint("TOPLEFT", frame.where, "BOTTOMLEFT", 0, -8)
    listHost:SetPoint("BOTTOMRIGHT", side, "BOTTOMLEFT", -18, 0)

    local _, content = UI.ScrollArea(listHost,
        WIDTH - SIDE_W - UI.PAD * 2 - 18, 6)
    frame.content = content
    frame.rows = {}

    frame.foot = UI.Label(frame, "", UI.FS.meta, C.textFaint)
    frame.foot:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", UI.PAD, 14)
    frame.foot:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -UI.PAD, 14)
    frame.foot:SetJustifyH("LEFT")

    table.insert(UISpecialFrames, "ZwoelfStuffRaidDeaths")
    return frame
end

-- The footer sentence, pure so the wording is checkable without a frame.
function RaidDeaths.FootLine(culprits, count)
    if count == 0 then return "" end
    if not RaidDeaths.WorthCounting(culprits) then
        return string.format("%d deaths, each to something different.", count)
    end
    local parts = {}
    for index = 1, min(#culprits, CULPRITS_SHOWN) do
        local culprit = culprits[index]
        parts[#parts + 1] = string.format("%dx %s - %s",
            culprit.count, culprit.who, culprit.spell)
    end
    local line = "What did the killing: " .. table.concat(parts, ", ")
    if #culprits > CULPRITS_SHOWN then
        line = line .. string.format(", and %d more",
            #culprits - CULPRITS_SHOWN)
    end
    return line
end

function RaidDeaths:Refresh()
    if not (frame and frame:IsShown()) then return end
    local C = ns.UI.C

    local entries, info, source = RaidDeaths.Best()
    entries = entries or {}

    frame.title:SetText("Deaths in the group")

    if not info then
        frame.where:SetText(tostring(source))
    else
        local where = info.where or info.label or ""
        if info.duration then
            where = where .. "  -  " .. RaidDeaths.Clock(info.duration)
        end
        if source == "kept" then
            where = where .. "  -  the last pull"
        elseif source == "session" then
            where = where .. "  -  no clock left on these"
        end
        frame.where:SetText(where)
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
        -- arrives, not at the moment they were made.
        row.entry = entry

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
    end

    frame.content:SetHeight(math.max(1, #entries * (ROW_H + 2)))
    frame.foot:SetText(RaidDeaths.FootLine(
        (info and info.culprits) or {}, #entries))

    RaidDeaths.PaintSideList()
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
            row.count:SetText(string.format("%d", #(fight.entries or {})))
            local where = fight.whereShort or "?"
            if fight.duration then
                where = where .. "  -  " .. RaidDeaths.Clock(fight.duration)
            end
            row.where:SetText(where)

            local isOn = index == selected
            row.bg:SetShown(isOn)
            if isOn then
                row.bg:SetColorTexture(C.control[1], C.control[2],
                    C.control[3], 1)
            end
            row:Show()
        end
    end

    if total == 0 then
        frame.sideTitle:SetText("No pull kept yet")
    elseif total > SIDE_ROWS then
        frame.sideTitle:SetText(string.format("%d pulls - scroll for more",
            total))
    else
        frame.sideTitle:SetText(total == 1 and "1 pull kept"
            or string.format("%d pulls kept", total))
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
