---------------------------------------------------------------------------
-- Death.lua - what killed you, and what could have prevented it
--
-- The owner's ask, in his words: when you die, a window with a quick
-- analysis - what came in, with numbers; which defensives were AVAILABLE;
-- whether a healthstone or a potion was sitting in the bags; and a way to
-- share the short version in chat.
--
-- WHERE THE DATA COMES FROM, because on this patch that is the whole design:
-- the combat log is gone and auras are secret, but Blizzard now runs its own
-- damage meter and death recap and lets an addon READ them -
-- C_DamageMeter.GetCombatSessionFromType lists the deaths of the current
-- fight, each carrying a deathRecapID, and C_DeathRecap.GetRecapEvents turns
-- that into the last events before the death: timestamp, amount, the health
-- you had left after each, overkill on the killing blow. The AMOUNTS ARE
-- REAL NUMBERS - EllesmereUIDamageMeters divides and compares them in
-- shipping code, which is how this was established. The spell NAME may be a
-- secret: displayable, but not comparable and never allowed into a chat
-- string. Every name in here goes through SafeName first.
--
-- "Was it available" is ns.History's estimate - own casts plus base
-- cooldown - because the client will not answer the question directly. The
-- window says "by our own clock" and means it.
---------------------------------------------------------------------------
local _, ns = ...

local Death = {}
ns.Death = Death

local UI -- ns.UI, taken late: Widgets loads after this file

-- The deaths of this session, oldest first, capped - the owner asked to
-- page through "the last 10 or so". Session only, not saved variables: an
-- analysis is read in the minutes after dying, not archived across days.
-- Death.snapshot stays the NEWEST entry, because half the wiring asks
-- "did the last capture find anything" and that question has one answer.
Death.log = {}
Death.snapshot = nil

-- Ten by default, the owner's number, and his to change: some evenings are
-- worth keeping and some keys are worth forgetting. The bounds are ours -
-- below three there is nothing to page through, and above fifty the saved
-- variables grow for a list nobody reads to the end of.
local DEATHS_KEPT = 10
local KEEP_MIN, KEEP_MAX = 3, 50

function Death.KeepCount()
    local want = ns.db and ns.db.death and ns.db.death.keep
    if type(want) ~= "number" then return DEATHS_KEPT end
    return math.max(KEEP_MIN, math.min(KEEP_MAX, math.floor(want + 0.5)))
end

Death.KEEP_MIN, Death.KEEP_MAX, Death.KEEP_DEFAULT =
    KEEP_MIN, KEEP_MAX, DEATHS_KEPT

-- How far back the quick analysis looks, in seconds. The recap itself
-- decides how many events it hands over; this only bounds OUR arithmetic.
local WINDOW = 10
-- Exported, because the replay window reads the same ten seconds and two
-- files each carrying their own copy of "ten" is how they end up disagreeing.
Death.WINDOW = WINDOW

-- One rule for how a capture enters the log, pure and tested. `replace` is
-- the retry and the Blizzard-recap hook speaking: the SAME death got a
-- better answer, and pushing it again would show one fall twice in the
-- pager. A plain push is a new death; the cap drops the oldest.
function Death.Remember(log, snapshot, cap, replace)
    if replace and #log > 0 then
        log[#log] = snapshot
    else
        log[#log + 1] = snapshot
        while #log > (cap or DEATHS_KEPT) do
            table.remove(log, 1)
        end
    end
    return snapshot
end

---------------------------------------------------------------------------
-- Names, made safe
---------------------------------------------------------------------------

-- A name that is safe to compute with, concatenate, and send to chat - or a
-- fallback word derived from the event type, which is always ours. This is
-- the only door a recap string passes through.
function Death.SafeName(name, eventType)
    if type(name) == "string" and name ~= "" and ns.CanCompute(name) then
        return name
    end
    if eventType == "SWING_DAMAGE" then return "Melee" end
    if eventType == "SPELL_HEAL" or eventType == "SPELL_PERIODIC_HEAL" then
        return "a heal"
    end
    return "a spell"
end

---------------------------------------------------------------------------
-- Where it happened, and where a share goes - pure, exported, tested
---------------------------------------------------------------------------

-- The place a death happened, said the way a player says it: "M+7 -
-- Ara-Kara", "Raid - Nerub-ar Palace (Heroic) - Queen Ansurek", "Open
-- world - Duskwood". Every input may be nil - each one comes off an API
-- the client is allowed to withhold - and the label degrades a word at a
-- time instead of failing.
-- Two answers: the full line for the window header and the share, and one
-- SHORT word for the list down the side, where 180 pixels have to say what
-- kind of evening this was.
function Death.WhereLabel(instanceType, instanceName, difficultyName,
        keyLevel, encounterName, zoneText)
    local place, short
    if instanceType == "party" then
        if keyLevel and keyLevel > 0 then
            short = "M+" .. keyLevel
            place = string.format("M+%d - %s", keyLevel,
                instanceName or "a dungeon")
        else
            short = "Dungeon"
            place = "Dungeon - " .. (instanceName or "?")
            if difficultyName and difficultyName ~= "" then
                place = place .. " (" .. difficultyName .. ")"
            end
        end
    elseif instanceType == "raid" then
        short = "Raid"
        place = "Raid - " .. (instanceName or "?")
        if difficultyName and difficultyName ~= "" then
            place = place .. " (" .. difficultyName .. ")"
        end
    elseif instanceType == "pvp" then
        short = "Battleground"
        place = "Battleground - " .. (instanceName or "?")
    elseif instanceType == "arena" then
        short = "Arena"
        place = "Arena - " .. (instanceName or "?")
    elseif instanceType == "scenario" then
        short = "Scenario"
        place = "Scenario - " .. (instanceName or "?")
    else
        short = "Open world"
        place = (zoneText and zoneText ~= "")
            and ("Open world - " .. zoneText) or "Open world"
    end
    -- A boss is the most specific thing that can be true about a place, so
    -- it wins the short word outright: "Avanoxx" says more than "M+12".
    if encounterName and encounterName ~= "" then
        place = place .. " - " .. encounterName
        short = encounterName
    end
    return place, short
end

-- Which channel a share goes to. choice is the Deaths-page setting; state
-- says which groups are actually around. "AUTO" is the group around you,
-- instance first - the behaviour before there was a setting. An explicit
-- choice that is not available answers nil and why, and the caller prints
-- to the own chat frame instead: a share must never silently go nowhere.
function Death.ShareTarget(choice, state)
    state = state or {}
    if not choice or choice == "AUTO" then
        if state.inInstance then return "INSTANCE_CHAT" end
        if state.inRaid then return "RAID" end
        if state.inParty then return "PARTY" end
        return nil, "not in a group"
    end
    if choice == "PARTY" and not state.inParty then
        return nil, "not in a party"
    end
    if choice == "RAID" and not state.inRaid then
        return nil, "not in a raid"
    end
    if choice == "INSTANCE_CHAT" and not state.inInstance then
        return nil, "not in an instance group"
    end
    if choice == "GUILD" and not state.inGuild then
        return nil, "not in a guild"
    end
    return choice
end

-- Wiping a GIVEN list, so the test can clear its own and never touches the
-- session's real one - /zs test in game must not eat the player's deaths.
function Death.ClearLog(log)
    for i = #log, 1, -1 do log[i] = nil end
    return log
end

---------------------------------------------------------------------------
-- Surviving a reload
--
-- The list was session-only and the skull with it, so the owner reloaded to
-- test the new build and both were gone. A /reload is not a new evening: it
-- happens after every settings change, every addon update and every error.
-- Losing the analysis of the pull you just wiped on to one is a defect, not
-- a design.
--
-- So the last ten are written to the saved variables, PER CHARACTER, and
-- read back at login. Two rules make that safe:
--
--   1. Only what is READABLE goes in. A secret value in a saved variable is
--      an error at logout, i.e. at the one moment nobody is watching. Every
--      field is copied by name and verified rather than the table being
--      handed over whole.
--   2. A death nothing could be read out of is not kept. It says "not
--      enough was readable" today and it will say the same next week, and
--      keeping it would let the recap hook mistake it for a fresh fall.
---------------------------------------------------------------------------

-- Exported: the raid death log writes its fights to the same disk under the
-- same two rules, and a second copy of "is this safe to save" is how one of
-- them ends up letting a secret through.
function Death.Plain(value, kind)
    if value == nil or not ns.CanCompute(value) then return nil end
    if type(value) ~= kind then return nil end
    return value
end
local Plain = Death.Plain

-- A face, reduced to the two numbers that can draw it. Same rule as every
-- other field down here: copied by name, verified, never handed over whole.
function Death.PlainArt(art)
    if type(art) ~= "table" then return nil end
    local creatureID = Plain(art.creatureID, "number")
    local displayID = Plain(art.displayID, "number")
    if not (creatureID or displayID) then return nil end
    return { creatureID = creatureID, displayID = displayID }
end
local PlainArt = Death.PlainArt

-- The whitelist. The analysis is NOT stored: it is derived from the events
-- and re-run on the way back in, so a better verdict written next month
-- applies to the deaths already on disk.
function Death.Persist(snapshot)
    if not (snapshot and snapshot.events and #snapshot.events > 0) then
        return nil
    end

    local events = {}
    for _, ev in ipairs(snapshot.events) do
        events[#events + 1] = {
            t = Plain(ev.t, "number") or 0,
            amount = Plain(ev.amount, "number") or 0,
            hp = Plain(ev.hp, "number"),
            heal = ev.heal and true or nil,
            name = Plain(ev.name, "string"),
            who = Plain(ev.who, "string"),
            spellID = Plain(ev.spellID, "number"),
            overkill = Plain(ev.overkill, "number"),
            art = PlainArt(ev.art),
        }
    end

    local avail = {}
    for _, entry in ipairs(snapshot.avail or {}) do
        avail[#avail + 1] = {
            spellID = Plain(entry.spellID, "number"),
            -- Consumables ride the same list; the id says which kind it is.
            itemID = Plain(entry.itemID, "number"),
            count = Plain(entry.count, "number"),
            name = Plain(entry.name, "string") or "?",
            remaining = Plain(entry.remaining, "number"),
            why = Plain(entry.why, "string"),
        }
    end

    local casts = {}
    for _, cast in ipairs(snapshot.casts or {}) do
        casts[#casts + 1] = {
            t = Plain(cast.t, "number") or 0,
            spellID = Plain(cast.spellID, "number"),
            itemID = Plain(cast.itemID, "number"),
            name = Plain(cast.name, "string") or "?",
            defensive = cast.defensive and true or nil,
            -- The measured window, so a bar drawn today is the same length
            -- after a reload. Without it the press would fall back to a
            -- generic reading and quietly change length on disk.
            lasted = Plain(cast.lasted, "number"),
            stillUp = cast.stillUp and true or nil,
        }
    end

    local art = snapshot.killerArt
    return {
        when = Plain(snapshot.when, "string"),
        day = Plain(snapshot.day, "string"),
        where = Plain(snapshot.where, "string"),
        whereShort = Plain(snapshot.whereShort, "string"),
        instance = Plain(snapshot.instance, "string"),
        journal = Plain(snapshot.journal, "number"),
        killer = Plain(snapshot.killer, "string"),
        killerArt = PlainArt(art),
        maxHP = Plain(snapshot.maxHP, "number"),
        events = events,
        avail = avail,
        casts = casts,
    }
end

-- Back out again, verdict rebuilt. `at` is deliberately absent: it is a
-- GetTime stamp, and GetTime restarts with the client - a stored one would
-- be a lie about how long ago this was.
function Death.Restore(stored)
    local log = {}
    for _, entry in ipairs(stored or {}) do
        if type(entry) == "table" and type(entry.events) == "table" then
            entry.analysis = Death.Analyse(entry.events, entry.maxHP,
                entry.avail, entry.casts)
            log[#log + 1] = entry
        end
    end
    return log
end

-- How a death's time reads. Today it is a clock; older than that, the day
-- goes in front of it - "16:10:54" on its own is a lie about last Tuesday.
function Death.WhenLabel(snapshot, today)
    local when = snapshot.when or ""
    local day = snapshot.day
    if day and today and day ~= today and #day == 10 then
        return day:sub(9, 10) .. "." .. day:sub(6, 7) .. ".  " .. when
    end
    return when
end

---------------------------------------------------------------------------
-- The analysis - pure, exported, tested
--
-- events: oldest first, each { t, amount, hp, heal, name, overkill }
--         with t in seconds before death (0 = the killing blow), every
--         field already readable - Capture below guarantees that.
-- avail:  { { spellID | itemID, name, remaining, why, count } } - remaining
--         0 = ready, nil = cannot tell (why says why). Spells and
--         consumables in one list: "what could have saved you" is one
--         question, and it had two answers on one window before.
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- NAMING A SPELL, the way this game names spells
--
-- The owner's rule, and it is a rule now: "immer wenn eine faehigkeit oder
-- was auch immer einen tooltip und icon hat, muss das angezeigt werden.
-- egal bei was". Nobody reads spell names in this game - they read icons.
--
-- A wrapped sentence cannot hold a hover target, so the verdict gets the
-- icon INLINE, which every font string in this client understands. The
-- places with room for real widgets - the replay's legend, the settings
-- rows - get an icon and a tooltip, which is the fuller form of the same
-- rule.
--
-- And the chat share gets neither: the escape sequence would either arrive
-- as raw punctuation at the other end or not arrive at all, so it is
-- stripped on the way out. One function, one place, no drift.
---------------------------------------------------------------------------

-- entry may be a spell id, or a table carrying spellID or itemID. A
-- consumable is named and pictured exactly like a spell, because to the
-- person reading the window it is the same kind of thing: something you
-- could have pressed.
function Death.SpellText(spellID, name, itemID)
    name = name or (spellID and ("Spell " .. tostring(spellID)))
        or (itemID and ("Item " .. tostring(itemID))) or "?"
    local texture
    if itemID and C_Item and C_Item.GetItemIconByID then
        local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
        if ok then texture = icon end
    end
    texture = texture
        or (spellID and ns.SpellTexture and ns.SpellTexture(spellID))
    if type(texture) == "number" then texture = string.format("%d", texture) end
    if type(texture) ~= "string" or texture == "" then return name end
    -- HEIGHT AND WIDTH BOTH ZERO, which means "as tall as the line". A
    -- fixed 14 pixels was the first attempt and it stood clear of the text
    -- it belonged to - a font string's line box is the font's height, and
    -- an icon taller than it hangs out of the top of it. Zero is the idiom
    -- for an icon that sits IN a sentence.
    --
    -- The texel numbers stay: that is the trimmed crop every drawn icon in
    -- this addon uses, so an inline icon and a drawn one are one picture.
    return "|T" .. texture .. ":0:0:0:0:64:64:5:59:5:59|t " .. name
end

-- A list of { spellID, name } as one readable enumeration. Plain strings
-- are accepted so a caller with nothing but a name still gets a sentence.
function Death.SpellList(entries, separator)
    local parts = {}
    for _, entry in ipairs(entries or {}) do
        if type(entry) == "table" then
            parts[#parts + 1] = Death.SpellText(entry.spellID, entry.name,
                entry.itemID)
        else
            parts[#parts + 1] = tostring(entry)
        end
    end
    return table.concat(parts, separator or ", ")
end

-- The same text with every inline icon taken back out, for chat.
function Death.PlainText(text)
    if type(text) ~= "string" then return text end
    return (text:gsub("|T.-|t%s*", ""))
end

function Death.Analyse(events, maxHP, avail, casts)
    local out = {
        totalIn = 0, totalHealed = 0, hits = 0,
        biggest = nil,          -- { amount, name, pct }
        lastHealAgo = nil,      -- seconds before death the last heal landed
        verdict = {},           -- the judgement lines alone - see below
        readyDefensives = {},   -- { spellID, name }, ready and unpressed
        unknownDefensives = {}, -- { spellID, name } we cannot judge
        lines = {},             -- the verdict, one sentence per line
    }

    for _, ev in ipairs(events or {}) do
        if ev.t <= WINDOW then
            if ev.heal then
                out.totalHealed = out.totalHealed + (ev.amount or 0)
                if not out.lastHealAgo or ev.t < out.lastHealAgo then
                    out.lastHealAgo = ev.t
                end
            else
                out.totalIn = out.totalIn + (ev.amount or 0)
                out.hits = out.hits + 1
                if not out.biggest or (ev.amount or 0) > out.biggest.amount then
                    out.biggest = {
                        amount = ev.amount or 0, name = ev.name, who = ev.who,
                    }
                end
            end
        end
    end

    if out.biggest and maxHP and maxHP > 0 then
        out.biggest.pct = out.biggest.amount / maxHP
    end

    for _, entry in ipairs(avail or {}) do
        -- The ID travels with the name, always. A spell named in this UI
        -- without its icon and its tooltip is unfinished to the people who
        -- play this game, and only the ID can produce either.
        local named = {
            spellID = entry.spellID, itemID = entry.itemID, name = entry.name,
        }
        if entry.remaining == 0 then
            out.readyDefensives[#out.readyDefensives + 1] = named
        elseif entry.remaining == nil then
            out.unknownDefensives[#out.unknownDefensives + 1] = named
        end
    end

    -- The verdict. Written as observations, not accusations - the person
    -- reading this just died and the addon was not there.
    local lines = out.lines

    if out.hits > 0 then
        if out.biggest and out.biggest.pct and out.biggest.pct >= 0.4 then
            -- The mob's name belongs in the sentence when the recap gave
            -- one: "Melee for 109k" answers what, "Melee from Heavyweight
            -- Golem" answers what AND who.
            local hit = out.biggest.name or "a spell"
            if out.biggest.who then
                hit = hit .. " from " .. out.biggest.who
            end
            lines[#lines + 1] = string.format(
                "One hit did most of it: %s for %s - %d%% of your health.",
                hit, ns.ShortNumber(out.biggest.amount),
                math.floor(out.biggest.pct * 100 + 0.5))
        else
            lines[#lines + 1] = string.format(
                "No single killer: %d hits for %s over %ds.",
                out.hits, ns.ShortNumber(out.totalIn), WINDOW)
        end
    end

    if out.lastHealAgo and out.lastHealAgo > 3 then
        lines[#lines + 1] = string.format(
            "The last heal landed %.1fs before the end.", out.lastHealAgo)
    end

    -- WHAT YOU PRESSED, which is the half of a death log every other line
    -- here is only the setup for. The casts are the player's own, off
    -- UNIT_SPELLCAST_SUCCEEDED - not the combat log, which is closed on
    -- this patch, but a live event that survived it.
    local pressed, defensives = {}, {}
    for _, cast in ipairs(casts or {}) do
        -- The item id rides along when the press was a consumable, so the
        -- line is pictured with the ITEM's icon - the potion you drank -
        -- and not the generic icon of the spell the drink casts. The chips
        -- at the bottom always read the item; the sentence at the top did
        -- not, and the two showed two different potions for one press.
        local named = { spellID = cast.spellID, itemID = cast.itemID,
            name = cast.name, t = cast.t }
        pressed[#pressed + 1] = named
        if cast.defensive then defensives[#defensives + 1] = named end
    end
    out.pressed, out.defensivesUsed = pressed, defensives

    -- THE VERDICT AND THE LISTS ARE TWO THINGS. `lines` is the whole story
    -- in sentences - what chat gets, what the snapshot keeps. `verdict` is
    -- the judgement alone: the window shows THAT over the table, and the
    -- lists go down the panel on the left as rows with icons, where six
    -- inline icons cannot wrap a name onto the next line without one.
    local verdict = out.verdict
    for _, line in ipairs(lines) do verdict[#verdict + 1] = line end

    if out.hits > 0 then
        if #pressed == 0 then
            lines[#lines + 1] = "You pressed nothing in those seconds."
            verdict[#verdict + 1] = lines[#lines]
        elseif #defensives == 0 then
            lines[#lines + 1] = "No defensive was used."
            verdict[#verdict + 1] = lines[#lines]
        else
            lines[#lines + 1] = "Defensives used: "
                .. Death.SpellList(defensives) .. "."
        end

        -- EVERYTHING you cast, on a line of its own. It used to be the tail
        -- of the verdict - "No defensive was used - you cast ..." - and a
        -- rotation of seven abilities wrapped that sentence over three
        -- lines, so the verdict and the list read as one paragraph. They
        -- are two different statements: one is the judgement, the other is
        -- the evidence.
        if #pressed > 0 then
            lines[#lines + 1] = "Your casts: " .. Death.SpellList(pressed) .. "."
        end
    end

    if #out.readyDefensives > 0 then
        lines[#lines + 1] = "Ready and unused (by our own clock): "
            .. Death.SpellList(out.readyDefensives) .. "."
    end

    if #lines == 0 then
        lines[#lines + 1] = "Not enough was readable to say anything useful."
        verdict[#verdict + 1] = lines[#lines]
    end

    return out
end

-- A SNAPSHOT WRITTEN BEFORE PRESSES CARRIED AN ITEM ID, brought up to date
-- in place: the item is worked out again from the spell and the name, the
-- same two doors a fresh press goes through, and a press that turns out to
-- be a picked consumable becomes a defensive. Idempotent and cheap, so it
-- runs every time a death is shown or replayed rather than once at load -
-- item names are not always loaded when the log is (owner, 2026-08-16:
-- "bei den bestehenden logs sind die heal potion bilder immer noch nicht
-- korrekt und der healthstone ist immer noch auf der schadensleiste").
-- Returns how many presses it changed.
function Death.Upgrade(snapshot, map)
    if type(snapshot) ~= "table" then return 0 end
    map = map or Death.DefensiveMap(Death.Defensives(), Death.PickedItems(),
        function(itemID)
            if not (C_Item and C_Item.GetItemSpell) then return nil end
            local ok, _, spellID = pcall(C_Item.GetItemSpell, itemID)
            return ok and spellID or nil
        end,
        Death.ItemName)
    local moved = 0
    for _, cast in ipairs(snapshot.casts or {}) do
        if not cast.itemID then
            local itemID = Death.CastItem(map, cast.spellID, cast.name)
            if itemID then
                cast.itemID = itemID
                cast.defensive = true
                moved = moved + 1
            end
        end
    end
    -- The story's own copy of the used list, so the verdict line and the
    -- replay agree with the panel about which press was the potion.
    local used = snapshot.analysis and snapshot.analysis.defensivesUsed
    if moved > 0 and type(used) == "table" then
        for _, entry in ipairs(used) do
            if not entry.itemID then
                entry.itemID = Death.CastItem(map, entry.spellID, entry.name)
            end
        end
    end
    return moved
end

-- The judgement lines alone, for the window. A snapshot written before the
-- lists moved to the panel carries no `verdict`; its lines are sorted by
-- what they begin with, which is how those lines were always told apart.
function Death.VerdictLines(analysis)
    if type(analysis) ~= "table" then return {} end
    if type(analysis.verdict) == "table" then return analysis.verdict end
    local out = {}
    for _, line in ipairs(analysis.lines or {}) do
        local plain = tostring(line)
        if not (plain:find("^Defensives used: ")
            or plain:find("^Your casts: ")
            or plain:find("^Ready and unused")) then
            out[#out + 1] = line
        end
    end
    return out
end

-- THE BAR BEHIND A ROW, as two pieces of one health bar: what you still
-- had after the event, and the piece the event moved. Together they are the
-- health you had BEFORE it - which is the thing a person actually reads off
-- a death log, and what a single "health left" fill could never show.
--
-- Damage: [ left ][ taken ]  - the two add up to the health before the hit.
-- Heal:   [ before ][ given ] - the same shape, the other direction, so a
--         heal row reads as the bar growing rather than as an odd colour.
--
-- Both come back as fractions of the maximum, clamped so an overkill that
-- ran to twice your health cannot draw past the end of the row.
function Death.RowSpans(ev, maxHP)
    if not (maxHP and maxHP > 0 and ev) then return 0, 0 end

    local amount = math.max(0, ev.amount or 0)
    local base
    if ev.heal then
        base = math.max(0, (ev.hp or 0) - amount)
    else
        base = math.max(0, ev.hp or 0)
    end

    local left = math.min(1, base / maxHP)
    local chunk = math.min(1 - left, amount / maxHP)
    return left, chunk
end

-- ONE STORY out of two lists: what hit you, and what you pressed, in the
-- order it happened. Both carry `t` - seconds before the death - so the
-- merge is a sort and nothing more. Oldest first, the way the table reads.
--
-- Kept apart until this point on purpose: the analysis totals damage, and
-- a cast folded into the events list early would have to be excluded from
-- every sum in it. One list for arithmetic, one for the eye.
function Death.Storyline(events, casts)
    local out = {}
    for _, ev in ipairs(events or {}) do out[#out + 1] = ev end
    for _, cast in ipairs(casts or {}) do
        out[#out + 1] = {
            t = cast.t, name = cast.name, spellID = cast.spellID,
            itemID = cast.itemID,
            cast = true, defensive = cast.defensive,
        }
    end
    -- Descending t IS oldest first. A stable tie-break on the cast flag
    -- puts your press before the hit it answered when both land in the
    -- same instant, which is the order that reads correctly.
    table.sort(out, function(a, b)
        if a.t ~= b.t then return a.t > b.t end
        return (a.cast and 1 or 0) > (b.cast and 1 or 0)
    end)
    return out
end

-- Which slice of the list the side column shows, given the death being
-- read. The list holds up to fifty and shows twelve, and a selection that
-- scrolls out of sight while the wheel walks through deaths is a list that
-- has stopped answering "where am I".
--
-- `index` counts from the OLDEST death; the column draws newest-first, so
-- position from the top is total - index.
function Death.ScrollTo(index, total, offset, visible)
    local pos = total - index
    offset = offset or 0
    if pos < offset then offset = pos end
    if pos > offset + visible - 1 then offset = pos - visible + 1 end
    return math.max(0, math.min(math.max(0, total - visible), offset))
end

-- WHERE A REPLAY STANDS at a given moment. `now` counts DOWN, in seconds
-- before the death, the same clock the rows are labelled with: it starts
-- above the oldest event and ends at 0, the killing blow.
--
-- Returns how many events have landed by then and the health you had at
-- that moment - which is the health after the last landed event, or the
-- full bar before anything has happened.
function Death.ReplayAt(events, now, maxHP)
    local landed, hp = 0, maxHP
    for index, ev in ipairs(events or {}) do
        if ev.t >= now then
            landed = index
            if ev.hp then hp = ev.hp end
        end
    end
    return landed, hp
end

-- The events inside the promised window, oldest first - what the row list
-- shows. Its own function because the first live death displayed rows from
-- FIVE MINUTES earlier: the recap hands over more history than its name
-- says, and a window subtitled "the last 10 seconds" showing -309.8s is
-- lying about one of the two. When nothing falls inside the window the full
-- list comes back rather than an empty frame - with a flag, so the caller
-- can re-title instead of quietly breaking the same promise again.
function Death.RecentEvents(events, window)
    local out = {}
    for _, ev in ipairs(events or {}) do
        if ev.t <= window then out[#out + 1] = ev end
    end
    if #out > 0 then return out, false end
    return events or {}, true
end

---------------------------------------------------------------------------
-- Finding our own recap
---------------------------------------------------------------------------

-- The realm half of a name, gone. The damage meter names people with realm,
-- UnitName("player") answers without one.
--
-- A SPACE MEANS IT IS NOT A PLAYER, and that is the whole guard. A player's
-- name is one word with no hyphen in it, so a hyphen in a name that has a
-- space in it belongs to the name: "Crenna Earth-Daughter" is a creature,
-- and cutting at her hyphen listed her as "Crenna Earth" in the raid death
-- log. It read as a truncation bug rather than as this. The damage meter
-- lists creatures as readily as people, so this function had never been
-- handed one until that list stopped being thrown away.
local function StripRealm(name)
    if type(name) ~= "string" then return name end
    if name:find(" ", 1, true) then return name end
    local short = name:match("^(.-)%-")
    return short or name
end

-- Exported because the raid death log names EVERYBODY off the same list and
-- has the same realm halves to drop. Two copies of this would be two rules.
Death.StripRealm = StripRealm

-- The deathRecapID of OUR latest death in the current fight, or nil and why.
-- Read the way EllesmereUIDamageMeters reads it: the Deaths list of the
-- damage meter's current session, matched by name. Every step may be absent
-- or secret on this patch, so every step is guarded and names its failure.
function Death.OwnRecapID()
    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType
        and Enum and Enum.DamageMeterType and Enum.DamageMeterSessionType) then
        return nil, "this client has no damage meter API"
    end

    -- combatSources, because that is the field EllesmereUI's shipping code
    -- iterates. The first in-game death was reported "no deaths this fight"
    -- while Blizzard's own recap stood open showing the killer: the field
    -- here was guessed as .sources, the guess answered nil, and the empty
    -- fallback made a wrong name read as an empty fight. Current first,
    -- Overall as the fallback - a training dummy kill landed in one and not
    -- the other on the owner's screen.
    local function SourcesOf(sessionType)
        local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType,
            sessionType, Enum.DamageMeterType.Deaths)
        if not ok or type(session) ~= "table" then return nil end
        local list = session.combatSources or session.sources
        if type(list) ~= "table" or #list == 0 then return nil end
        return list
    end

    local sources = SourcesOf(Enum.DamageMeterSessionType.Current)
        or SourcesOf(Enum.DamageMeterSessionType.Overall)
    if not sources then
        return nil, "the damage meter lists no deaths yet"
    end

    local me = UnitName("player")
    if not ns.CanCompute(me) then
        return nil, "the client withheld your own name"
    end

    -- Newest wins: iterate to the end, keep the last match. Dying twice in
    -- one fight lists two rows, and the one being asked about is always the
    -- one that just happened.
    local found
    for _, src in ipairs(sources) do
        local name = src.name
        if ns.CanCompute(name) and StripRealm(name) == me then
            local rid = src.deathRecapID
            if ns.CanCompute(rid) and type(rid) == "number" and rid > 0 then
                found = rid
            end
        end
    end
    if not found then
        return nil, "your death carries no readable recap id"
    end
    return found
end

---------------------------------------------------------------------------
-- Capture
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- CONSUMABLES ARE DEFENSIVES
--
-- The owner: "wir brauchen zudem noch neben spells consumables wie traenke
-- oder healthstones, das sind auch def cds". He is right, and it is the
-- same verdict either way: a potion that stayed in the bag and a defensive
-- that stayed off cooldown are one sentence, not two.
--
-- So they live in ONE list with the spells - each entry carries a spellID
-- or an itemID and nothing downstream cares which. The old shape had a
-- second list for "what was in the bags", which meant the same question got
-- two answers in two places on one window.
--
-- BOTH LISTS BELONG TO THE SPECIALISATION.
--
-- Owner: "die sachen muessen beide also auch die defensives pro spec und
-- nicht pro klasse gespeichert werden". A protection warrior and a fury
-- warrior share a profile and share almost none of their defensives; one
-- list for both means half of it is spells the current spec cannot cast.
--
-- AND THEY START EMPTY. Owner: "auch sollte da per default alles leer sein,
-- das verwirrt irgendwie die leute" - a slot that is already filled reads as
-- a decision somebody made for you, and the first thing you do is work out
-- whether you agree with it.
--
-- The pre-spec keys (db.defensives, db.rescueItems) are read once to carry
-- what you already picked into the spec you are standing in, and then left
-- exactly where they are: the version before this one still reads them.
---------------------------------------------------------------------------

-- Through ns.SpecStore, which is where this used to live in private before
-- the request panel and the reminders wanted the same thing. It hands back
-- nil while the client has not said which spec this is - writing under
-- "WARRIOR:0" files a pick in a bin nobody reads - so both callers below
-- fall back to a throwaway table for that moment.
function Death.PickedItems()
    return ns.SpecStore("rescueItemsBySpec", "rescueItems") or {}
end

-- The spells side of the same question, through one door for the same
-- reason: two readers of one setting is how they end up disagreeing.
function Death.Defensives()
    return ns.SpecStore("defensivesBySpec", "defensives") or {}
end

-- The name the client knows it by, or nothing. An item whose data has not
-- loaded yet answers nil and is asked to load, so the next look succeeds.
function Death.ItemName(itemID)
    if not (C_Item and itemID) then return nil end
    local get = C_Item.GetItemNameByID
    if get then
        local ok, name = pcall(get, itemID)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    if C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
    return nil
end

-- Seconds until it can be used again, 0 when it is ready, nil when the
-- client will not say. Unlike a spell this one IS readable on this patch -
-- item cooldowns were never made secret - so it is a fact, not an estimate.
function Death.ItemReady(itemID)
    local get = (C_Item and C_Item.GetItemCooldown)
        or (C_Container and C_Container.GetItemCooldown)
    if not (get and itemID) then return nil end
    local ok, start, duration = pcall(get, itemID)
    if not (ok and type(start) == "number" and type(duration) == "number") then
        return nil
    end
    if start == 0 or duration == 0 then return 0 end
    return math.max(0, (start + duration) - GetTime())
end

-- How many are actually carried. Zero is an answer worth having: a potion
-- you do not have is a different sentence from one you did not drink.
function Death.ItemCount(itemID)
    if not (C_Item and C_Item.GetItemCount) then return 0 end
    local ok, count = pcall(C_Item.GetItemCount, itemID)
    if ok and type(count) == "number" then return count end
    return 0
end
local ItemCount = Death.ItemCount

function Death.ItemIcon(itemID)
    if not (C_Item and C_Item.GetItemIconByID and itemID) then return nil end
    local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
    if ok then return icon end
    return nil
end

-- WHAT IS OFFERED TO PICK FROM: whatever is in the bags right now that can
-- be used at all. Not a shipped list of item ids - those go out of date
-- every patch, and the three seeded above are already one expansion's worth
-- of guessing. An item with no use-spell is not a defensive by any reading.
--
-- Consumables only: GetItemInfoInstant answers the class id without waiting
-- for the item to load, and 0 is Consumable in every locale because it is a
-- number rather than a word.
local CONSUMABLE_CLASS = 0

function Death.BagConsumables()
    local out, seen = {}, {}
    local container = C_Container
    if not (container and container.GetContainerNumSlots
        and container.GetContainerItemID and C_Item) then
        return out
    end

    for bag = 0, 5 do
        local okSlots, slots = pcall(container.GetContainerNumSlots, bag)
        if okSlots and type(slots) == "number" then
            for slot = 1, slots do
                local okID, itemID = pcall(container.GetContainerItemID,
                    bag, slot)
                if okID and type(itemID) == "number" and not seen[itemID] then
                    seen[itemID] = true

                    -- THE SIXTH RETURN, and it was reading the fifth.
                    --
                    -- GetItemInfoInstant answers, in order: itemID, type,
                    -- subType, equipLoc, ICON, classID, subclassID. pcall
                    -- puts its own `ok` in front of all of them, so four
                    -- discards landed on the icon - and this then compared a
                    -- texture file id against 0 and threw every potion in the
                    -- bags away. Owner: "der erkennt die silvermoon health
                    -- potion nicht". Every installed addon that wants this
                    -- writes `select(6, ...)`, which is the version that
                    -- cannot be miscounted.
                    local classID
                    if C_Item.GetItemInfoInstant then
                        local ok, class = pcall(function()
                            return select(6, C_Item.GetItemInfoInstant(itemID))
                        end)
                        if ok then classID = class end
                    end

                    local usable = false
                    if C_Item.GetItemSpell then
                        local ok, _, spellID = pcall(C_Item.GetItemSpell, itemID)
                        usable = ok and spellID ~= nil
                    end

                    if usable and classID == CONSUMABLE_CLASS then
                        out[#out + 1] = itemID
                        -- Asked to load, so the NAME is there by the time
                        -- the list is drawn rather than one frame late.
                        Death.ItemName(itemID)
                    end
                end
            end
        end
    end
    return out
end

-- WHERE it happened. The owner asked for it in as many words: open world,
-- dungeon, raid, boss, M+. Every call here is one the client may refuse, so
-- each is guarded on its own and the label is built from whatever survived.
--
-- The encounter name comes from ENCOUNTER_START rather than from any lookup:
-- it is the only thing that knows a BOSS is what you are standing in front
-- of, and it arrives readable (BigWigs drives its whole engage logic off it).
Death.encounter = nil

local function KeyLevel()
    if not (C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.GetActiveKeystoneInfo) then
        return nil
    end
    local okActive, active = pcall(C_ChallengeMode.IsChallengeModeActive)
    if not okActive or not active then return nil end
    local okLevel, level = pcall(C_ChallengeMode.GetActiveKeystoneInfo)
    if okLevel and ns.CanCompute(level) and type(level) == "number"
        and level > 0 then
        return level
    end
    return nil
end

local function Readable(value)
    if ns.CanCompute(value) and type(value) == "string" and value ~= "" then
        return value
    end
    return nil
end

---------------------------------------------------------------------------
-- THE PLACE'S OWN PICTURE, out of the Adventure Guide.
--
-- Owner, 2026-08-16: "ich moechte gern dass der dungeon / raid name
-- geschrieben wird und das dungeon / raid bild dahinter klein zu sehen ist,
-- das hilft gemein! ... bei klick auf das bild oeffnet sich das dungeon
-- journal zu dem dungeon. die bilder bekommst du aus dem dungeon journal."
--
-- The journal knows an instance by its own id, reached from the map you are
-- standing in (EJ_GetInstanceForMap), and answers with the tile the guide
-- draws on its own buttons (EJ_GetInstanceInfo's buttonImage). Both are
-- core API, no Blizzard addon needs loading to ASK; opening the guide does
-- load Blizzard_EncounterJournal, once, on the click. All three doors are
-- guarded: a desk without them, or a client that answers nothing, gets nil
-- and draws no picture rather than an empty square.
---------------------------------------------------------------------------
function Death.Journal()
    if not (C_Map and C_Map.GetBestMapForUnit and EJ_GetInstanceForMap) then
        return nil
    end
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not (ok and type(mapID) == "number") then return nil end
    local ok2, id = pcall(EJ_GetInstanceForMap, mapID)
    if ok2 and type(id) == "number" and id > 0 then return id end
    return nil
end

local journalArt = {}
-- The tile and the name for a journal id, cached: it is asked for every
-- row of the side list on every repaint.
function Death.JournalArt(journalID)
    if not (type(journalID) == "number" and journalID > 0) then return nil end
    local hit = journalArt[journalID]
    if hit ~= nil then return hit or nil end
    if not EJ_GetInstanceInfo then return nil end
    local ok, name, _, _, button1, _, button2 = pcall(EJ_GetInstanceInfo,
        journalID)
    local art = ok and (button1 or button2) or nil
    if art and art ~= 0 and art ~= "" then
        journalArt[journalID] = { texture = art, name = name }
        return journalArt[journalID]
    end
    journalArt[journalID] = false
    return nil
end

-- Open the Adventure Guide on that instance. Loads the Blizzard addon on
-- first use - it is load-on-demand - then goes through Blizzard's own door.
function Death.OpenJournal(journalID)
    if not (type(journalID) == "number" and journalID > 0) then return false end
    if not EncounterJournal_OpenJournal then
        local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
        if load then pcall(load, "Blizzard_EncounterJournal") end
    end
    if not EncounterJournal_OpenJournal then return false end
    local ok = pcall(EncounterJournal_OpenJournal, nil, journalID)
    return ok and true or false
end

-- THE PICTURE AS A BUTTON: the guide's tile, cropped to the shape it is
-- given rather than squashed into it, and a click opens the guide on that
-- instance. One builder for the death window's rows and header and the
-- group log's rows.
--
-- THE PICTURE IS A REGION OF THE FILE, NOT THE FILE. The guide's button
-- textures are 256 by 128 with the art in their top-left 190 by 92 and
-- padding beyond - the first version drew the whole file and showed the
-- padding as black bands (owner, 2026-08-16: "nur verzerrt und etwas zu
-- klein"). The region is the one Raider.IO's inline tiles have used for
-- years (|T...:256:128:4:190:4:92|t) - read off their code, not guessed.
-- Within that region a frame narrower than the art shows its middle at
-- full height; a frame wider shows its middle band at full width.
local ART_X0, ART_X1 = 4 / 256, 190 / 256
local ART_Y0, ART_Y1 = 4 / 128, 92 / 128
local TILE_RATIO = ((ART_X1 - ART_X0) * 256) / ((ART_Y1 - ART_Y0) * 128)
Death.PLACE_ART_W, Death.PLACE_ART_H = 64, 46
function Death.TileCoords(width, height)
    local want = (width or 1) / math.max(1, height or 1)
    local spanX, spanY = ART_X1 - ART_X0, ART_Y1 - ART_Y0
    if want < TILE_RATIO then
        local keep = want / TILE_RATIO
        local trim = spanX * (1 - keep) / 2
        return ART_X0 + trim, ART_X1 - trim, ART_Y0, ART_Y1
    end
    local keep = TILE_RATIO / want
    local trim = spanY * (1 - keep) / 2
    return ART_X0, ART_X1, ART_Y0 + trim, ART_Y1 - trim
end

function Death.CreatePlaceArt(parent, width, height)
    width = width or Death.PLACE_ART_W
    height = height or Death.PLACE_ART_H
    local art = CreateFrame("Button", nil, parent)
    art:SetSize(width, height)
    art.tex = art:CreateTexture(nil, "ARTWORK")
    art.tex:SetAllPoints(art)
    art.tex:SetTexCoord(Death.TileCoords(width, height))
    art.edge = ns.CreateBorder(art, 1, "OVERLAY")
    art:SetScript("OnClick", function(self)
        Death.OpenJournal(self.journal)
    end)
    art:SetScript("OnEnter", function(self)
        if not (GameTooltip and self.journal) then return end
        local info = Death.JournalArt(self.journal)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(info and info.name or "", 1, 1, 1)
        GameTooltip:AddLine("Click to open it in the Adventure Guide",
            0.61, 0.64, 0.69)
        GameTooltip:Show()
    end)
    art:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    art.Paint = function(journalID)
        art.journal = journalID
        local info = Death.JournalArt(journalID)
        if not info then
            art:Hide()
            return false
        end
        art.tex:SetTexture(info.texture)
        local C = ns.UI.C
        art.edge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)
        art:Show()
        return true
    end
    art:Hide()
    return art
end

function Death.Where()
    local instanceName, instanceType, difficultyName
    if GetInstanceInfo then
        local ok, name, kind, _, diffName = pcall(GetInstanceInfo)
        if ok then
            instanceName = Readable(name)
            instanceType = Readable(kind)
            difficultyName = Readable(diffName)
        end
    end

    local zone
    if GetRealZoneText then
        local ok, text = pcall(GetRealZoneText)
        if ok then zone = Readable(text) end
    end
    if not zone and GetZoneText then
        local ok, text = pcall(GetZoneText)
        if ok then zone = Readable(text) end
    end

    local place, short = Death.WhereLabel(instanceType, instanceName,
        difficultyName, KeyLevel(), Death.encounter, zone)
    -- The instance's own name and its journal id ride along, for the side
    -- lists: "Altar of Fangs" and its tile, not only "Dungeon". Only inside
    -- one - the open world has no page in the guide.
    local inside = instanceType == "party" or instanceType == "raid"
        or instanceType == "scenario"
    return place, short, inside and instanceName or nil,
        inside and Death.Journal() or nil
end

-- WHAT YOU PRESSED in the seconds before it, off ns.History - the player's
-- own casts, recorded from UNIT_SPELLCAST_SUCCEEDED. Not the combat log:
-- that is closed to addons on this patch. This is a live event about your
-- own character, and the client still answers it readably.
--
-- `diedAt` is the moment PLAYER_DEAD fired, not the moment of the capture -
-- the capture runs the better part of a second later, and offsetting every
-- cast by that would put your last press after the hit that killed you.
-- WHICH SPELL IDS COUNT AS A DEFENSIVE PRESS.
--
-- The picked spells, plus the spell each picked CONSUMABLE casts. Drinking
-- a potion is a cast like any other on this patch - UNIT_SPELLCAST_SUCCEEDED
-- fires with the item's own spell - so without this the potion showed up in
-- the rotation row as an unnamed press instead of as the defensive it is.
--
-- A picked spell maps to `true`; a picked ITEM maps to its item id, so the
-- press can be pictured as the item. Two doors for the item: the spell the
-- client says it casts, and - because a Healthstone on this patch fires
-- "Use Healthstone" (462156), which is not the spell GetItemSpell names -
-- the item's own name inside the cast's name. Read off the owner's saved
-- deaths: the stone sat in the rotation row twice while the log called it
-- ready and unused. Pure below the API line, so the desk can walk it.
function Death.DefensiveMap(spells, items, itemSpell, itemName)
    local out, names = {}, {}
    for spellID in pairs(spells or {}) do out[spellID] = true end
    for itemID in pairs(items or {}) do
        local spellID = itemSpell and itemSpell(itemID)
        if type(spellID) == "number" then out[spellID] = itemID end
        local name = itemName and itemName(itemID)
        if type(name) == "string" and name ~= "" then
            names[#names + 1] = { name = name:lower(), itemID = itemID }
        end
    end
    -- Longest item name first, so "Greater Healthstone" wins over
    -- "Healthstone" when both are picked and the cast says the longer one.
    table.sort(names, function(a, b) return #a.name > #b.name end)
    out.byName = names
    return out
end

-- Which item a cast was, if any: the id door first, then the name door.
function Death.CastItem(map, spellID, castName)
    local hit = map[spellID]
    if type(hit) == "number" then return hit end
    if hit == true then return nil end
    if type(castName) == "string" then
        local lower = castName:lower()
        for _, entry in ipairs(map.byName or {}) do
            if lower:find(entry.name, 1, true) then return entry.itemID end
        end
    end
    return nil
end

local function DefensiveSpells()
    return Death.DefensiveMap(Death.Defensives(), Death.PickedItems(),
        function(itemID)
            if not (C_Item and C_Item.GetItemSpell) then return nil end
            local ok, _, spellID = pcall(C_Item.GetItemSpell, itemID)
            return ok and spellID or nil
        end,
        Death.ItemName)
end

local function CastsBefore(diedAt, window)
    local out = {}
    if not (ns.History and diedAt) then return out end
    local picked = DefensiveSpells()
    for _, cast in ipairs(ns.History.casts or {}) do
        local ago = diedAt - cast.at
        if ago >= 0 and ago <= window then
            local name = ns.SpellName(cast.spellID)
                or ("Spell " .. cast.spellID)
            local itemID = Death.CastItem(picked, cast.spellID, name)
            local entry = {
                t = ago,
                spellID = cast.spellID,
                itemID = itemID,
                name = name,
                defensive = (itemID or picked[cast.spellID]) and true or nil,
            }

            -- HOW LONG IT WAS ACTUALLY UP, for this press, measured while
            -- it happened - see History.lua. Not a duration looked up in a
            -- table: the window this very press opened. A buff still up
            -- when you died runs to the end of the plot and says so.
            local from, to = ns.History:ActiveWindow(cast.spellID, cast.at)
            if from then
                local endsAt = to and math.max(0, diedAt - to) or 0
                local lasted = ago - endsAt
                if lasted > 0 then
                    entry.lasted = lasted
                    entry.stillUp = (to == nil) or nil
                end
            end

            out[#out + 1] = entry
        end
    end
    return out
end

-- What was still ready: the defensives picked on this page, spells and
-- consumables in ONE list. A spell's readiness is our own estimate - the
-- client withholds live cooldowns - while an item's is a fact the client
-- still answers, which is why the entries carry different fields and the
-- window says "about" only where it has to.
local function Availability(now)
    local out = {}
    for spellID in pairs(Death.Defensives()) do
        local name = ns.SpellName(spellID) or ("Spell " .. spellID)
        local remaining, why = ns.History:Estimate(spellID, now)
        out[#out + 1] = {
            spellID = spellID, name = name,
            remaining = remaining, why = why,
        }
    end

    for itemID in pairs(Death.PickedItems()) do
        local count = ItemCount(itemID)
        out[#out + 1] = {
            itemID = itemID,
            name = Death.ItemName(itemID) or ("Item " .. itemID),
            count = count,
            -- Carrying none is not "on cooldown" and must not read as it:
            -- the count says the rest, and the verdict words it.
            remaining = (count > 0) and Death.ItemReady(itemID) or nil,
            why = (count == 0) and "none in the bags" or nil,
        }
    end

    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Reads the recap into OUR shape, with every field made safe at the door.
-- After this function nothing downstream needs a guard, which is the only
-- way the pure analysis can stay pure.
function Death.ReadRecap(recapID)
    if not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then
        return nil, nil, "this client has no death recap API"
    end
    local ok, raw = pcall(C_DeathRecap.GetRecapEvents, recapID)
    if not ok or type(raw) ~= "table" or #raw == 0 then
        return nil, nil, "the recap is empty"
    end

    local maxHP
    if C_DeathRecap.GetRecapMaxHealth then
        local ok2, hp = pcall(C_DeathRecap.GetRecapMaxHealth, recapID)
        if ok2 and type(hp) == "number" and hp > 0 then maxHP = hp end
    end

    -- Newest first in the API; ours is oldest first with t = seconds before
    -- death, because that is the order a person reads a story in.
    local deathAt
    for i = 1, #raw do
        local ts = raw[i].timestamp
        if ns.CanCompute(ts) and type(ts) == "number" then
            deathAt = ts
            break
        end
    end

    -- WHO. The recap names sources readably - "killed by Heavyweight Golem"
    -- stood on the owner's screen off this very loop - so every event gets
    -- its who, not just the window title. Three candidate field names until
    -- a probe dump settles which one is real; the first readable wins.
    local function WhoOf(ev)
        for _, key in ipairs({ "sourceName", "casterName", "caster" }) do
            local who = ev[key]
            if ns.CanCompute(who) and type(who) == "string" and who ~= "" then
                return who
            end
        end
        return nil
    end

    -- The killer is the newest event's readable source - raw arrives newest
    -- first, so the first hit of this loop is the one that landed last.
    local killer
    for i = 1, #raw do
        killer = WhoOf(raw[i])
        if killer then break end
    end

    -- The killer's PICTURE. Blizzard's own recap draws the model, so the
    -- client holds one; what it hands an addon is what the probe is for.
    -- Two doors, both proven in shipping code: a creature id goes into
    -- PlayerModel:SetCreature - MDT points its enemy tooltips at raw npc
    -- ids that way - and a display id into SetDisplayInfo. A readable GUID
    -- is the third door: an npc id is the sixth field of one, and outside a
    -- dungeon the recap's GUIDs are not withheld. Whichever answers first
    -- wins; none answering means no portrait, not an empty box.
    local function NumberFrom(ev, keys)
        for _, key in ipairs(keys) do
            local value = ev[key]
            if ns.CanCompute(value) and type(value) == "number" and value > 0 then
                return value
            end
        end
        return nil
    end

    local function CreatureFromGUID(ev)
        for _, key in ipairs({ "sourceGUID", "casterGUID", "guid" }) do
            local guid = ev[key]
            if ns.CanCompute(guid) and type(guid) == "string" then
                local kind, npcID = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
                if npcID and (kind == "Creature" or kind == "Vehicle"
                    or kind == "Pet" or kind == "GameObject") then
                    return tonumber(npcID)
                end
            end
        end
        return nil
    end

    local function ArtOf(ev)
        local creature = NumberFrom(ev, {
            "sourceCreatureID", "creatureID", "npcID", "sourceNpcID",
        }) or CreatureFromGUID(ev)
        local display = NumberFrom(ev, {
            "displayID", "sourceDisplayID", "creatureDisplayID",
        })
        if creature or display then
            return { creatureID = creature, displayID = display }
        end
        return nil
    end

    -- ONE FACE PER HIT, not one face for the death. The owner's reason is
    -- the right one: "wenn du 10 gegner hast, kannst das sonst nicht
    -- zuordnen" - a single portrait in the corner claims the whole picture
    -- for one of twenty things that were hitting you.
    --
    -- Keyed by the source's NAME as well, because only some events carry a
    -- readable id: two hits from the same named mob are the same mob, so
    -- the face found on one of them belongs on the other. That is an
    -- inference about identity, not about art - it never invents a model.
    local artByWho = {}
    for i = 1, #raw do
        local who = WhoOf(raw[i])
        if who and not artByWho[who] then
            local found = ArtOf(raw[i])
            if found then artByWho[who] = found end
        end
    end

    local art
    for i = 1, #raw do
        art = ArtOf(raw[i])
        if art then break end
    end
    if not art and killer then art = artByWho[killer] end

    -- THE ONE FIELD THAT `x and y or z` CANNOT CARRY, and it took a check
    -- driving the real tooltip to notice. Written as
    -- `(readable and type == "boolean") and ev.avoidable or nil`, a recorded
    -- `avoidable = false` evaluates to false, falls through the `or`, and
    -- comes out as nil - so "the game says this was NOT avoidable" was being
    -- filed as "the game did not say". Every clean bill in the addon was
    -- unreachable and nothing looked wrong.
    --
    -- Three answers need three branches. The idiom has room for two.
    local function AvoidableOf(ev)
        local flag = ev.avoidable
        if not ns.CanCompute(flag) then return nil end
        if type(flag) ~= "boolean" then return nil end
        return flag
    end

    local events = {}
    for i = #raw, 1, -1 do
        local ev = raw[i]
        local amount = ev.amount
        local hp = ev.currentHP
        local ts = ev.timestamp
        local overkill = ev.overkill
        local kind = ns.CanCompute(ev.event) and ev.event or ""
        local who = WhoOf(ev)
        events[#events + 1] = {
            -- Whose face belongs over this hit: its own id when the recap
            -- gave one, otherwise the one found on another hit from the
            -- same named source.
            art = ArtOf(ev) or (who and artByWho[who]) or nil,
            t = (deathAt and ns.CanCompute(ts) and type(ts) == "number")
                and math.max(0, deathAt - ts) or 0,
            amount = (ns.CanCompute(amount) and type(amount) == "number")
                and math.abs(amount) or 0,
            hp = (ns.CanCompute(hp) and type(hp) == "number") and hp or nil,
            -- Anything with HEAL in its name, not two guessed constants.
            -- SPELL_HEAL and SPELL_PERIODIC_HEAL were written from memory;
            -- if the recap says SPELL_HEAL_ABSORBED or anything else in
            -- that family, a heal would have been drawn as damage and
            -- counted into the wrong total. The word is the rule.
            heal = kind:find("HEAL", 1, true) ~= nil,
            name = Death.SafeName(ev.spellName, kind),
            who = who,
            spellID = (ns.CanCompute(ev.spellId) and type(ev.spellId) == "number"
                and ev.spellId > 0) and ev.spellId or nil,
            overkill = (ns.CanCompute(overkill) and type(overkill) == "number"
                and overkill > 0) and overkill or nil,

            -- THE GAME'S OWN VERDICT, and it is the most valuable field in
            -- the whole recap. Blizzard marks damage its own death recap
            -- considers avoidable - a puddle you stood in, a swirl you did
            -- not move out of - and it arrived readable in the 2026-08-14
            -- probe dump, `avoidable = false` on a periodic tick.
            --
            -- Read strictly as a boolean, never as truthiness: a client that
            -- withheld it would make every death look unavoidable, which is
            -- the flattering answer and therefore the dangerous one. nil
            -- means "the client did not say", and it says that out loud.
            avoidable = AvoidableOf(ev),
        }
    end
    return events, maxHP, nil, killer, art
end

function Death:Capture(overrideID, replace)
    local now = GetTime()
    local recapID, why
    if overrideID then
        -- Handed straight from Blizzard's own recap window opening - no
        -- searching, no name matching, the id is by definition ours.
        recapID = overrideID
    else
        recapID, why = Death.OwnRecapID()
    end

    local events, maxHP, readWhy, killer, art
    if recapID then
        events, maxHP, readWhy, killer, art = Death.ReadRecap(recapID)
    end

    local avail = Availability(now)
    local where, whereShort, instance, journal = Death.Where()
    local casts = CastsBefore(Death.diedAt or now, WINDOW)

    self.snapshot = Death.Remember(self.log, {
        at = now,
        when = date("%H:%M:%S"),
        day = date("%Y-%m-%d"),
        where = where,
        whereShort = whereShort,
        instance = instance,
        journal = journal,
        events = events,
        maxHP = maxHP,
        killer = killer,
        killerArt = art,
        avail = avail,
        casts = casts,
        reason = events == nil and (readWhy or why) or nil,
        analysis = Death.Analyse(events, maxHP, avail, casts),
    }, Death.KeepCount(), replace)

    -- The pager may be standing on an older death; a new one must not yank
    -- it. Only a view of the newest follows the newest.
    if self.showing and not replace then self.showing = nil end
    Death.RefreshIcon()
    Death.Save()
    return self.snapshot
end

-- The store, per character. Deaths are a character's - they happened to
-- that tank, in that spec, with those defensives - so they live under the
-- character key rather than in the profile, which two characters may share.
local function Store()
    if not ns.account then return nil end
    ns.account.deaths = ns.account.deaths or {}
    return ns.account.deaths
end

function Death.Save()
    local store = Store()
    local key = ns.CharacterKey()
    if not (store and key) then return end

    local out = {}
    for _, snapshot in ipairs(Death.log) do
        local kept = Death.Persist(snapshot)
        if kept then out[#out + 1] = kept end
    end
    store[key] = out
end

function Death.Load()
    local store = Store()
    local key = ns.CharacterKey()
    if not (store and key) then return end

    Death.log = Death.Restore(store[key])
    -- A list read back from disk may be longer than what is being kept now:
    -- the setting can have been lowered on another character, or between
    -- sessions. The cap is applied on the way in, not only on the way out.
    local keep = Death.KeepCount()
    while #Death.log > keep do table.remove(Death.log, 1) end
    Death.snapshot = Death.log[#Death.log]
    Death.showing = nil
    Death.sideOffset = 0
    Death.RefreshIcon()
end

---------------------------------------------------------------------------
-- Chat
---------------------------------------------------------------------------

-- Which groups are around, as plain booleans - the state half of the rule
-- above, kept apart from it so the rule itself stays testable on a desktop.
function Death.GroupState()
    return {
        inInstance = IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) or false,
        inRaid = IsInRaid and IsInRaid() or false,
        inParty = IsInGroup and IsInGroup() or false,
        inGuild = IsInGuild and IsInGuild() or false,
    }
end

-- The short version, built ONLY from lines the analysis already made safe.
function Death.ShareLines(snapshot)
    if not snapshot then return nil end
    local a = snapshot.analysis
    local lines = {}
    -- The killer is in the lead line when the recap named one readably -
    -- it is the first thing the group asks, so it goes first. The place
    -- follows it: "in an M+7" is the difference between a pull that was
    -- always going to hurt and one that should not have.
    local by = snapshot.killer and (" by " .. snapshot.killer) or ""
    local at = snapshot.where and (" [" .. snapshot.where .. "]") or ""
    if a.hits > 0 then
        lines[#lines + 1] = string.format("Death %s%s%s: %s in %ds (%d hits).",
            snapshot.when or "", by, at,
            ns.ShortNumber(a.totalIn), WINDOW, a.hits)
    else
        lines[#lines + 1] = string.format("Death %s%s%s.",
            snapshot.when or "", by, at)
    end
    for _, line in ipairs(a.lines) do
        -- Without the icons: an escape sequence in a chat message is either
        -- punctuation or nothing at the other end. See Death.SpellText.
        lines[#lines + 1] = Death.PlainText(line)
    end
    return lines
end

function Death:Share()
    -- The death being LOOKED AT, not blindly the newest: sharing while
    -- paged back to an earlier one must post the one on screen.
    local snapshot = self.log[self.showing or #self.log]
    if not snapshot then
        ns.Print("No death recorded yet this session.")
        return
    end
    local lines = Death.ShareLines(snapshot) or {}
    local channel, why = Death.ShareTarget(
        ns.db and ns.db.death and ns.db.death.channel, Death.GroupState())
    -- C_ChatInfo is the living call on this client (BigWigs' Loader uses
    -- it); the bare global is deprecated and only kept as the fallback.
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    for _, line in ipairs(lines) do
        if channel then
            send("ZwoelfStuff: " .. line, channel)
        else
            ns.Print(line)
        end
    end
    if not channel then
        -- A chosen channel that is not there must SAY so. Printing the
        -- analysis to your own frame while you believe it went to the raid
        -- is the one failure a share feature is not allowed to have.
        ns.Print("|cff888888" .. (why or "not in a group")
            .. " - printed here instead.|r")
    end
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local frame

-- Declared here because the side list's wheel handler is wired while the
-- window is built and the painter is written further down.
local PaintSideList

-- One row of the event list: time, name, a health bar behind the amount.
-- The bar IS the graph - each row's fill is the health you still had after
-- that event, so reading down the list is watching the health drain.
local ROW_H = 22

-- THE ROWS ARE NARROWER THAN THE COLUMN THEY SIT IN, by exactly the room the
-- scroll rail needs. Without it the right-hand numbers - the ones the whole
-- table is read for - are the pixels the rail sits on top of.
local LIST_GUTTER = 8

-- The window is two columns: the analysis of ONE death on the left, and the
-- session's deaths down the right so you can walk them without paging. The
-- numbers are the left column's content width and the side list's width;
-- everything else is measured off them.
-- The gutter is the same on both sides of the divider. It was not, and the
-- verdict, the Close button and the availability footer all ran right up
-- against the line while the list had air to spare.
local MAIN_W = 510
local LIST_W = MAIN_W - LIST_GUTTER
-- 232, up from 186 (owner, 2026-08-16: "du kannst dafuer ruhig das rechte
-- panel verbreitern"): the third line of every row is the instance's name
-- with the guide's tile beside it.
local SIDE_W = 232
local GUTTER = 16

-- THE THIRD COLUMN, DOWN THE LEFT. Owner, 2026-08-16, looking at the header
-- of this window: "das ist alles sehr gedrungen und zusammengeklatscht. ich
-- wuerde LINKS eine Liste (panel) wie rechts einbauen, wo man das schoen
-- auflisten kann." The lists - what you pressed, what you still had, what
-- else you cast - used to be sentences with icons in them over the table
-- and a strip of chips under it. They are rows down the left now, one
-- thing a line with its icon and its number, the way the session's deaths
-- are rows down the right. Same width as that column, so the window is
-- symmetrical about the analysis in the middle.
local PANEL_W = SIDE_W
local MAIN_X = 16 + PANEL_W + GUTTER + GUTTER
local DIVIDER_X = MAIN_X + MAIN_W + GUTTER
local SIDE_X = DIVIDER_X + GUTTER
-- THREE LINES A ROW: when and the kind, the killer, the place with its
-- picture. All at 11 - the two lines under the clock were 10 and read as
-- a different list (owner, 2026-08-16: "die text fonts sollten gleich
-- gross sein").
local SIDE_ROW_H = 50
-- How many rows FIT beside the analysis. The list may hold fifty now, so
-- the pool is sized to the window and the rest is scrolled to - a pool
-- sized to the setting would build fifty frames to show twelve. Nine of
-- fifty at the taller row, in a window that grew to 580 for them.
local SIDE_ROWS = 9
local HEADER_BOTTOM = 82
-- How small and how large this window may be dragged. Below 60% the event
-- rows stop being readable at arm's length; above 140% it outgrows a 1080p
-- screen, which is the size it would be wanted at least of all.
local SCALE_MIN, SCALE_MAX = 0.6, 1.4

-- The four columns of the event table, measured from the row's left edge.
-- The header labels and the cells read the SAME numbers, or a header is a
-- decoration that drifts away from what it names.
-- THE MOB'S FACE IN FRONT OF THE ROW, before WHEN (owner, 2026-08-16:
-- "da fehlt vor dem when das gegner avatar und hover infos - also von wem
-- kam der spell / hit. dann ist das auch konsistent mit den anderen
-- fenstern"). The same face and the same hover tip the group log's rows
-- and the replay's marks carry.
local COL_FACE = 4
local FACE_W = 18
local COL_WHEN = COL_FACE + FACE_W + 8
local COL_ICON = 52 + COL_WHEN - 6
local COL_WHAT = 74 + COL_WHEN - 6
local COL_WHAT_W = 180
local COL_AMOUNT_R = -132
local COL_LEFT_R = -6
local COL_LEFT_W = 118

---------------------------------------------------------------------------
-- ONE EVENT ROW, BUILT AND PAINTED IN ONE PLACE
--
-- The group log shows a dead person's last seconds with these same four
-- columns, because it is the same question asked about somebody else. Two
-- copies of a table that is meant to look identical is the second-copy trap:
-- one of them gets the next improvement and the other quietly becomes the
-- old design. So the row, its header and its painter live here, and both
-- windows call them.
--
-- Everything is measured off the width handed in rather than off LIST_W: the
-- group log's column is wider than this one, and a row that hard-codes the
-- window it was born in cannot move house.
---------------------------------------------------------------------------

-- The head over the columns. Same offsets as the cells below it, from the
-- same constants, which is the only way a header stays over what it names.
function Death.BuildEventHead(parent, width, whatLabel)
    local UI, C = ns.UI, ns.UI.C
    local head = CreateFrame("Frame", nil, parent)
    head:SetSize(width, 16)

    head.when = UI.Eyebrow(head, "When")
    head.when:SetPoint("LEFT", head, "LEFT", COL_WHEN, 0)
    head.what = UI.Eyebrow(head, whatLabel or "What hit you")
    head.what:SetPoint("LEFT", head, "LEFT", COL_WHAT, 0)
    head.amount = UI.Eyebrow(head, "Damage")
    head.amount:SetPoint("RIGHT", head, "RIGHT", COL_AMOUNT_R, 0)
    head.left = UI.Eyebrow(head, "Health left")
    head.left:SetPoint("RIGHT", head, "RIGHT", COL_LEFT_R, 0)

    local rule = head:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(C.separator[1], C.separator[2], C.separator[3], 1)
    rule:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 0, -2)
    rule:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", 0, -2)
    rule:SetHeight(1)

    return head
end

-- The height of one of these rows, for a caller that has to stack them.
Death.EVENT_ROW_H = ROW_H

function Death.BuildEventRow(parent, width)
    local UI, C = ns.UI, ns.UI.C
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, ROW_H)
    -- The width the bars are drawn against, kept on the row: the painter is
    -- shared and must not assume which window called it.
    row.dkWidth = width

    -- Two pieces of one health bar: what was left, and what the event
    -- moved, drawn end to end. See Death.RowSpans.
    row.fill = row:CreateTexture(nil, "BACKGROUND")
    row.fill:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.fill:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)

    row.chunk = row:CreateTexture(nil, "BACKGROUND")
    row.chunk:SetPoint("TOPLEFT", row.fill, "TOPRIGHT", 0, 0)
    row.chunk:SetPoint("BOTTOMLEFT", row.fill, "BOTTOMRIGHT", 0, 0)

    -- THE MARK ON THE EDGE: this hit is damage THE GAME ITSELF calls
    -- avoidable. It was built for a press of your own and never shown once -
    -- the row list holds hits, and your presses are drawn in the replay -
    -- so it goes to the one flag in the whole recap worth marking down a
    -- column: the swirl somebody stood in. Silence when the client did not
    -- say, which is not the same as a clean bill.
    row.tick = row:CreateTexture(nil, "ARTWORK")
    row.tick:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.tick:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.tick:SetWidth(3)
    row.tick:SetColorTexture(0.88, 0.42, 0.36, 1)
    row.tick:Hide()

    -- WHEN AND HOW MUCH, both in the harm red - the two columns that say
    -- what this row cost. A HEAL is painted back to the neutral text colour
    -- in the painter below, because a heal drawn in the damage colour is the
    -- one thing this table must never say.
    -- The face of whatever did this, and the enemy tip on it. Hidden when
    -- the recap gave no art for the source; the WHEN column stays where it
    -- is either way, so the rows line up whoever hit you.
    row.face = Death.CreateFace(row, FACE_W)
    row.face:SetPoint("LEFT", row, "LEFT", COL_FACE, 0)
    row.face:EnableMouse(true)
    row.face:SetScript("OnEnter", function(self)
        local ev = row.ev
        if not (ev and ev.who) then return end
        Death.ShowEnemyTip(self, {
            who = ev.who,
            art = ev.art,
            summary = Death.SourceSummary(row.events, ev.who),
        })
    end)
    row.face:SetScript("OnLeave", Death.HideEnemyTip)

    row.when = UI.Label(row, "", 11, C.harm)
    row.when:SetPoint("LEFT", row, "LEFT", COL_WHEN, 0)

    -- The spell's icon, when the recap names a readable id. EllesmereUI
    -- resolves recap icons exactly this way in shipping code.
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", row, "LEFT", COL_ICON, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.what = UI.Label(row, "", 12, C.hot)
    row.what:SetPoint("LEFT", row, "LEFT", COL_WHAT, 0)
    row.what:SetWidth(COL_WHAT_W)
    row.what:SetJustifyH("LEFT")
    row.what:SetWordWrap(false)

    row.amount = UI.Label(row, "", 12, C.harm)
    row.amount:SetPoint("RIGHT", row, "RIGHT", COL_AMOUNT_R, 0)
    row.amount:SetJustifyH("RIGHT")

    -- What was left afterwards, in its own column rather than only in the
    -- hover: the row is read while the healer is asking, and a number you
    -- have to point at is a number nobody quotes.
    row.left = UI.Label(row, "", 12, C.textDim)
    row.left:SetPoint("RIGHT", row, "RIGHT", COL_LEFT_R, 0)
    row.left:SetWidth(COL_LEFT_W)
    row.left:SetJustifyH("RIGHT")
    row.left:SetWordWrap(false)

    -- The client's own spell tooltip on hover, which is the whole point: a
    -- name tells you what hit, the tooltip tells you what it does. A melee
    -- swing has no spell to ask about, so the row says what it knows itself
    -- rather than showing an empty frame.
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        local ev = self.ev
        if not (ev and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local shown = false
        if ev.spellID then
            shown = pcall(GameTooltip.SetSpellByID, GameTooltip, ev.spellID)
        end
        if not shown then
            GameTooltip:ClearLines()
            GameTooltip:AddLine(ev.name or "", 1, 1, 1)
        end
        if ev.who then
            GameTooltip:AddLine("from " .. ev.who, 0.61, 0.64, 0.69)
        end
        GameTooltip:AddLine(string.format("%s%s  -  %.1fs before the end",
            ev.heal and "+" or "-", ns.ShortNumber(ev.amount), ev.t),
            0.61, 0.64, 0.69)
        if ev.overkill then
            GameTooltip:AddLine(ns.ShortNumber(ev.overkill)
                .. " of it was overkill", 0.61, 0.64, 0.69)
        end
        if ev.hp then
            GameTooltip:AddLine("Health left afterwards: "
                .. ns.ShortNumber(ev.hp), 0.61, 0.64, 0.69)
        end
        -- THE GAME'S OWN VERDICT, and only when the game gave one. A
        -- withheld flag says nothing here rather than saying "clean".
        if ev.avoidable == true then
            GameTooltip:AddLine("The game calls this avoidable damage.",
                0.88, 0.42, 0.36, true)
        elseif ev.avoidable == false then
            GameTooltip:AddLine("The game does not call this avoidable.",
                0.61, 0.64, 0.69, true)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    row:Hide()
    return row
end

-- One event drawn into one row. The row keeps the event it is showing,
-- because these frames are pooled across every death in the list and a
-- closure would answer for the one it was built with.
function Death.PaintEventRow(row, ev, maxHP, events)
    if not (row and ev) then return end
    row.ev = ev
    -- The whole list, for the face's tip: "12 hits from it, 900k in total".
    row.events = events
    Death.PaintFace(row.face, ev.art)
    -- THE WIDTH IT REALLY HAS, not the one it was born with. A row anchored
    -- on both sides follows the window it is in, and a bar drawn against the
    -- build-time number would stop short of the row or run past it. The
    -- birth width is the fallback for a row that has only one anchor.
    local width = row:GetWidth()
    if not (type(width) == "number" and width > 0) then
        width = row.dkWidth or 0
    end

    row.when:SetText(string.format("-%.1fs", ev.t))

    -- A melee hit carries no spell id, and Blizzard's own recap draws a
    -- sword for it rather than a hole. 135274 is the fallback icon
    -- EllesmereUI's recap tooltip ships with, for the same case.
    local icon = ev.spellID and ns.SpellTexture(ev.spellID)
    row.icon:SetTexture(icon or 135274)
    row.icon:Show()

    -- What, then who: "Melee  Heavyweight Golem". BOTH IN ORANGE, because
    -- both are what this row answers about when the mouse arrives - the
    -- ability through the client's own tooltip, the mob through the big tip
    -- everywhere else in the addon. The numbers keep their own weight, so
    -- the column still reads as a name beside an amount.
    if ev.who then
        row.what:SetText((ev.name or "") .. "  " .. ev.who)
    else
        row.what:SetText(ev.name or "")
    end

    -- The damage, and what share of the whole health bar it was. The number
    -- alone means nothing without the pool it came out of - "107.9k" is a
    -- scratch on one tank and a third of another.
    local sign = ev.heal and "+" or "-"
    local share = (maxHP and maxHP > 0)
        and string.format("  |cff9ba3af%d%%|r",
            math.floor(ev.amount / maxHP * 100 + 0.5))
        or ""
    row.amount:SetText(sign .. ns.ShortNumber(ev.amount) .. share)
    -- The colour follows the DIRECTION, not the column: damage is the harm
    -- red the whole table reads in, and a heal must not be painted as one.
    local C2 = ns.UI.C
    if ev.heal then
        row.amount:SetTextColor(C2.text[1], C2.text[2], C2.text[3])
    else
        row.amount:SetTextColor(C2.harm[1], C2.harm[2], C2.harm[3])
    end

    -- What was left afterwards. On the killing blow there is nothing left,
    -- so the column says what went past zero instead - that is the number
    -- worth knowing about a hit nobody was surviving.
    if ev.overkill then
        row.left:SetText("0  |cffe06c5e" .. ns.ShortNumber(ev.overkill)
            .. " over|r")
    elseif ev.hp then
        local leftShare = (maxHP and maxHP > 0)
            and string.format("  |cff626a76%d%%|r",
                math.floor(ev.hp / maxHP * 100 + 0.5))
            or ""
        row.left:SetText(ns.ShortNumber(ev.hp) .. leftShare)
    else
        row.left:SetText("")
    end

    -- The bar IS a health bar: the slate piece is what was still there, the
    -- coloured piece is what this event moved, and the two together are the
    -- health before it landed. Read down the column and the slate shrinks -
    -- that is the pull going wrong, drawn.
    local left, chunk = Death.RowSpans(ev, maxHP)
    row.fill:SetWidth(math.max(1, width * left))
    row.fill:SetColorTexture(0.20, 0.26, 0.34, 0.85)
    row.chunk:SetWidth(math.max(1, width * chunk))
    if ev.heal then
        row.chunk:SetColorTexture(0.12, 0.42, 0.16, 0.85)
    else
        row.chunk:SetColorTexture(0.55, 0.11, 0.11, 0.85)
    end
    row.chunk:SetShown(chunk > 0)

    row.tick:SetShown(ev.avoidable == true)
    row:Show()
end

---------------------------------------------------------------------------
-- THE DEFENSIVES PANEL - the column down the left of this window and of
-- the replay. One builder, two windows, so the two cannot drift apart a
-- row at a time.
--
-- Three lists, each a heading and rows: what you pressed that was a
-- defensive (with how long before the end), what you still had and did
-- not press (with ready / seconds left / none in the bags), and everything
-- else you cast. Rows, not sentences: an inline icon in a wrapping line
-- strands a name on the next line without its picture, and a strip of
-- chips under the table grew into the table when there were many.
---------------------------------------------------------------------------
local PANEL_HEAD_H = 24
local PANEL_ROW_H = 20
local PANEL_BUTTON_H = 30
local PANEL_GAP = 10          -- air above the second and third heading

-- WHAT THE PANEL SHOWS, as a flat list of rows. Pure - the desk walks it.
--
--   { kind = "head", text }
--   { kind = "item", spellID, itemID, name, suffix, t }
--   { kind = "none", text }         one dim line where a list is empty
function Death.PanelEntries(snapshot)
    local out = {}
    if type(snapshot) ~= "table" then return out end

    local used, others = {}, {}
    for _, cast in ipairs(snapshot.casts or {}) do
        if cast.defensive then used[#used + 1] = cast
        else others[#others + 1] = cast end
    end
    -- Oldest first, the way the table reads: t is seconds BEFORE the end.
    local function oldestFirst(a, b) return (a.t or 0) > (b.t or 0) end
    table.sort(used, oldestFirst)
    table.sort(others, oldestFirst)

    local function Ago(t)
        return string.format("-%.1fs", math.max(0, t or 0))
    end

    -- GREEN FOR WHAT WAS PRESSED, RED FOR WHAT WAS NOT (owner, 2026-08-16):
    -- the two headings answer the one question the window is opened for,
    -- and the colour says which is the good half before the word does.
    out[#out + 1] = { kind = "head", text = "Defensives used", tone = "good" }
    if #used == 0 then
        out[#out + 1] = { kind = "none", text = "None" }
    end
    for _, cast in ipairs(used) do
        out[#out + 1] = { kind = "item", spellID = cast.spellID,
            itemID = cast.itemID, name = cast.name, suffix = Ago(cast.t),
            t = cast.t }
    end

    -- WHAT WAS NOT PRESSED. Owner, 2026-08-16: rename "What you had, by our
    -- own clock" to "not used defensives" - and then it must not list the
    -- ones you DID use, which the old footer did (with their cooldown, as
    -- if the press had never happened). Matched by id and by name: a
    -- snapshot written before presses carried an item id still names the
    -- potion the same way in both lists.
    out[#out + 1] = { kind = "head", text = "Unused defensives", tone = "harm" }
    if snapshot.reason then
        out[#out + 1] = { kind = "none", text = snapshot.reason }
    else
        local usedBy = {}
        for _, cast in ipairs(used) do
            if cast.spellID then usedBy["s" .. cast.spellID] = true end
            if cast.itemID then usedBy["i" .. cast.itemID] = true end
            if type(cast.name) == "string" then
                usedBy["n" .. cast.name:lower()] = true
            end
        end
        local shown = 0
        for _, entry in ipairs(snapshot.avail or {}) do
            local pressed = (entry.spellID and usedBy["s" .. entry.spellID])
                or (entry.itemID and usedBy["i" .. entry.itemID])
                or (type(entry.name) == "string"
                    and usedBy["n" .. entry.name:lower()])
            if not pressed then
                -- ONLY WHAT WE ACTUALLY KNOW gets written after the name.
                -- "no known cooldown" and "not cast since login" are this
                -- addon saying it cannot tell, and a column of non-answers
                -- is worse than a bare name.
                local suffix
                if entry.remaining == 0 then
                    suffix = "|cff67c971ready|r"
                elseif entry.remaining then
                    suffix = string.format("|cff9ba3af%ds|r",
                        math.floor(entry.remaining + 0.5))
                elseif entry.itemID and (entry.count or 0) == 0 then
                    -- A potion you were not carrying is not "cannot tell"
                    -- - it is a plain no, and the one case worth writing.
                    suffix = "|cff626a76none|r"
                end
                shown = shown + 1
                out[#out + 1] = { kind = "item", spellID = entry.spellID,
                    itemID = entry.itemID, name = entry.name,
                    suffix = suffix }
            end
        end
        if shown == 0 then
            out[#out + 1] = { kind = "none",
                text = #(snapshot.avail or {}) == 0
                    and "Nothing picked yet."
                    or "None - you used them all." }
        end
        -- NOTHING PICKED IS A DOOR, NOT A SENTENCE. Owner, 2026-08-16:
        -- "wenn ich das death log aufmache und ich hab im addon KEINE DEF
        -- und consumables eingestellt, sollte dort ein button sein, setup
        -- your consumables und setup your defensives mit link zu dem
        -- modul." One for each half that is empty - the spells and the
        -- items are picked on the same page, but somebody with defensives
        -- and no potions is told about the potions, not both.
        local spells, items = 0, 0
        for _, entry in ipairs(snapshot.avail or {}) do
            if entry.itemID then items = items + 1
            elseif entry.spellID then spells = spells + 1 end
        end
        if spells == 0 then
            out[#out + 1] = { kind = "button", text = "Set up your defensives",
                page = "deaths" }
        end
        if items == 0 then
            out[#out + 1] = { kind = "button", text = "Set up your consumables",
                page = "deaths" }
        end
    end

    out[#out + 1] = { kind = "head", text = "Your casts" }
    if #others == 0 then
        out[#out + 1] = { kind = "none", text = "None" }
    end
    for _, cast in ipairs(others) do
        out[#out + 1] = { kind = "item", spellID = cast.spellID,
            itemID = cast.itemID, name = cast.name, suffix = Ago(cast.t),
            t = cast.t }
    end

    return out
end

-- The icon for a row: the ITEM's when the row is one, else the spell's.
function Death.PanelIcon(entry)
    if entry.itemID then
        local icon = Death.ItemIcon(entry.itemID)
        if icon then return icon end
    end
    return entry.spellID and ns.SpellTexture and ns.SpellTexture(entry.spellID)
        or nil
end

function Death.BuildDefensivePanel(parent, width)
    local UI, C = ns.UI, ns.UI.C
    local host = CreateFrame("Frame", nil, parent)
    host:SetWidth(width)

    -- The same caption weight as "This session" over the column on the
    -- right, so the two columns read as a pair.
    host.title = UI.Label(host, "Your defensives", 11, C.textDim)
    host.title:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -2)

    local area = CreateFrame("Frame", nil, host)
    area:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -24)
    area:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    local GUT = 8
    host.scroll, host.content = UI.ScrollArea(area, width - GUT, GUT)
    host.rows = {}
    local rowWidth = width - GUT

    local function Tip(self)
        local entry = self.entry
        if not (entry and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local shown = false
        if entry.itemID and GameTooltip.SetItemByID then
            shown = pcall(GameTooltip.SetItemByID, GameTooltip, entry.itemID)
        end
        if not shown and entry.spellID then
            shown = pcall(GameTooltip.SetSpellByID, GameTooltip, entry.spellID)
        end
        if not shown then
            GameTooltip:ClearLines()
            GameTooltip:AddLine(entry.name or "", 1, 1, 1)
        end
        if entry.t then
            GameTooltip:AddLine(string.format("%.1fs before the end", entry.t),
                0.61, 0.64, 0.69)
        end
        GameTooltip:Show()
    end

    local function Build()
        local row = CreateFrame("Frame", nil, host.content)
        row:SetSize(rowWidth, PANEL_ROW_H)

        -- A tick larger than an eyebrow (owner, 2026-08-16), still upper
        -- case; the tone is painted per heading below.
        row.head = UI.Label(row, "", 12, C.textDim)
        row.head:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 4)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row.suffix = UI.Label(row, "", 11, C.textDim)
        row.suffix:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.suffix:SetJustifyH("RIGHT")

        row.name = UI.Label(row, "", 11, C.text)
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.name:SetPoint("RIGHT", row.suffix, "LEFT", -6, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)

        row.none = UI.Label(row, "", 11, C.textFaint)
        row.none:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.none:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.none:SetJustifyH("LEFT")
        row.none:SetWordWrap(false)

        -- The door to the Deaths page, for a list with nothing picked.
        row.button = UI.Button(row, "", rowWidth - 8, function()
            local entry = row.pageEntry
            if entry and ns.Options then ns.Options:Open(entry.page) end
        end)
        row.button:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.button:Hide()

        row:EnableMouse(true)
        row:SetScript("OnEnter", Tip)
        row:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        return row
    end

    host.Paint = function(snapshot)
        local entries = Death.PanelEntries(snapshot)
        local y, heads = 0, 0
        for index, entry in ipairs(entries) do
            local row = host.rows[index]
            if not row then
                row = Build()
                host.rows[index] = row
            end
            row.entry = (entry.kind == "item") and entry or nil
            row.head:SetShown(entry.kind == "head")
            row.icon:SetShown(entry.kind == "item")
            row.name:SetShown(entry.kind == "item")
            row.suffix:SetShown(entry.kind == "item")
            row.none:SetShown(entry.kind == "none")
            row.button:SetShown(entry.kind == "button")
            row.pageEntry = (entry.kind == "button") and entry or nil
            row:EnableMouse(entry.kind == "item")

            local height = PANEL_ROW_H
            if entry.kind == "button" then
                height = PANEL_BUTTON_H
                row.button.label:SetText(entry.text or "")
            elseif entry.kind == "head" then
                heads = heads + 1
                if heads > 1 then y = y + PANEL_GAP end
                height = PANEL_HEAD_H
                row.head:SetText((entry.text or ""):upper())
                local tone = (entry.tone == "good" and C.inUse)
                    or (entry.tone == "harm" and C.harm) or C.textDim
                row.head:SetTextColor(tone[1], tone[2], tone[3])
            elseif entry.kind == "item" then
                row.icon:SetTexture(Death.PanelIcon(entry) or 134400)
                row.name:SetText(entry.name or "?")
                row.suffix:SetText(entry.suffix or "")
            else
                row.none:SetText(entry.text or "")
            end
            row:SetHeight(height)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", host.content, "TOPLEFT", 0, -y)
            row:Show()
            y = y + height
        end
        for index = #entries + 1, #host.rows do
            host.rows[index].entry = nil
            host.rows[index]:Hide()
        end
        host.content:SetHeight(math.max(1, y))
        if host.scroll.Update then host.scroll.Update() end
        return #entries
    end

    return host
end

local function BuildWindow()
    UI = ns.UI
    local C = UI.C

    frame = CreateFrame("Frame", "ZwoelfStuffDeathFrame", UIParent)
    frame:SetSize(SIDE_X + SIDE_W + 16, 580)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    frame:SetFrameStrata("DIALOG")
    -- See Replay.lua: the two windows share a strata and lie on each other,
    -- so whichever is clicked has to come forward. Without it this window's
    -- buttons drew through the replay standing in front of it.
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    UI.Fill(frame, "BACKGROUND", C.windowBg)
    local edge = ns.CreateBorder(frame, 1, "BORDER")
    edge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)

    -- The killer's portrait. A PlayerModel pointed at a creature id, which
    -- is how MDT draws the mob in its enemy tooltips - the same call, on
    -- the same kind of id. It is Hidden until one actually renders: an
    -- empty black square where a face should be is worse than no square.
    frame.portrait = Death.CreateFace(frame, 54)
    frame.portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", MAIN_X, -12)

    -- The killer's face at 54 pixels is a silhouette. Pointing at it gives
    -- the big one, with everything it did to you in these seconds - the same
    -- tip the replay's marks and the group log's rows show.
    frame.portrait:EnableMouse(true)
    frame.portrait:SetScript("OnEnter", function(self)
        local snapshot = Death.Showing()
        if not (snapshot and snapshot.killer) then return end
        Death.ShowEnemyTip(self, {
            who = snapshot.killer,
            art = snapshot.killerArt,
            summary = Death.SourceSummary(snapshot.events, snapshot.killer),
        })
    end)
    frame.portrait:SetScript("OnLeave", Death.HideEnemyTip)

    local portraitEdge = ns.CreateBorder(frame.portrait, 1, "OVERLAY")
    portraitEdge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)

    frame.title = UI.Label(frame, "You died", 16, C.text)
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", MAIN_X, -14)

    frame.sub = UI.Label(frame, "", 11, C.textFaint)
    frame.sub:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -3)

    -- Where it happened, on its own line: the owner asked for it by name,
    -- and "M+12 - Ara-Kara - Avanoxx" is a different story from the same
    -- numbers taken in the open world.
    frame.place = UI.Label(frame, "", 11, C.accentCool)
    frame.place:SetPoint("TOPLEFT", frame.sub, "BOTTOMLEFT", 0, -2)
    frame.place:SetWidth(MAIN_W - 70)
    frame.place:SetWordWrap(false)

    -- The guide's tile after the place, in the header too ("ggf auch oben
    -- im header"). Placed by Show, after the words, at their measured width;
    -- two lines tall so it keeps its shape beside an 11-point line.
    frame.placeArt = Death.CreatePlaceArt(frame, 40, 26)

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
    local closeMark = UI.Glyph(close, "ui-close", 12, C.textDim)
    closeMark:SetPoint("CENTER", close, "CENTER", 0, 0)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- The pager arrows that stood here in 4.45.0 are gone: the list down
    -- the right side IS the pager now, and it shows where you are instead
    -- of counting for you. The wheel still steps, because a wheel over a
    -- list of things costs no pixels.
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        Death:Show((Death.showing or #Death.log) + delta)
    end)

    -- The verdict block, above the event rows: the analysis is the point of
    -- the window, so it does not sit under a scroll.
    frame.verdict = UI.Label(frame, "", 12, C.text)
    frame.verdict:SetPoint("TOPLEFT", frame, "TOPLEFT", MAIN_X, -HEADER_BOTTOM)
    frame.verdict:SetWidth(MAIN_W)
    frame.verdict:SetJustifyH("LEFT")
    frame.verdict:SetJustifyV("TOP")
    frame.verdict:SetSpacing(3)

    -----------------------------------------------------------------------
    -- THE EVENT LIST, IN ITS OWN SCROLLING AREA.
    --
    -- Owner, 2026-08-09: "die liste links muss scrollbar sein" - and the
    -- screenshot showed the other half of the same fault: with a four-line
    -- verdict and ten hits, the availability footer was drawn straight
    -- across the killing blow. Both come from the rows having been placed at
    -- absolute offsets inside a window of fixed height, with a hard cap of
    -- twelve to keep them from running off the bottom. A cap is not a
    -- layout: it silently drops hits from the very deaths that have the most
    -- to say.
    --
    -- Now the list has an AREA. Its top follows the verdict, its bottom sits
    -- on the footer, and whatever does not fit is scrolled to rather than
    -- thrown away or drawn over something else.
    -----------------------------------------------------------------------
    frame.listHost = CreateFrame("Frame", nil, frame)
    frame.list, frame.listContent = UI.ScrollArea(frame.listHost, LIST_W,
        LIST_GUTTER)

    -- The wheel still pages between deaths when the list has nothing to
    -- scroll - see UI.ScrollArea. Losing that over the biggest part of the
    -- window would be a worse trade than the scrolling is worth.
    frame.list.OnIdleWheel = function(delta)
        Death:Show((Death.showing or #Death.log) + delta)
    end

    -- Event rows, POOLED and built on demand. Twelve were built up front
    -- when twelve was also the ceiling; now a quiet death builds three and a
    -- messy one builds as many as it needs, once.
    frame.rows = {}
    frame.BuildRow = function()
        return Death.BuildEventRow(frame.listContent, LIST_W)
    end

    -----------------------------------------------------------------------
    -- The table's head. Two lines: what the table IS, and what its columns
    -- are. Without it the fill behind each row is a mystery bar and the
    -- rightmost number could be anything.
    -----------------------------------------------------------------------
    frame.tableNote = UI.Label(frame, "", 11, C.textFaint)
    frame.tableNote:SetWidth(MAIN_W)
    frame.tableNote:SetJustifyH("LEFT")
    frame.tableNote:SetWordWrap(false)

    -- The replay is its own window - Core/Replay.lua. It was inline here
    -- for one revision, as a bar that drained where this note sits; a
    -- timeline with the incoming above it and your own presses below is a
    -- different picture and it needs the room.

    -- The head is as wide as the ROWS, not as the column: its labels sit over
    -- their columns, and a head eight pixels wider puts every right-aligned
    -- caption eight pixels off the number under it. Built by the same
    -- function the group log's head comes out of, so the two tables cannot
    -- drift apart a column at a time.
    frame.head = Death.BuildEventHead(frame, LIST_W, "What hit you")
    frame.head:Hide()

    -----------------------------------------------------------------------
    -- The list down the side: every death this session, newest first.
    -- The owner asked for it in as many words, and it replaces the arrows -
    -- a list you can see beats a counter you have to walk.
    -----------------------------------------------------------------------
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(C.edge[1], C.edge[2], C.edge[3], 1)
    divider:SetPoint("TOPLEFT", frame, "TOPLEFT", DIVIDER_X, -14)
    divider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", DIVIDER_X, 14)
    divider:SetWidth(1)

    frame.sideTitle = UI.Label(frame, "This session", 11, C.textDim)
    frame.sideTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE_X, -16)

    -- The rows live in an area of their own so the wheel over the LIST
    -- scrolls the list, while the wheel over the analysis still steps
    -- through deaths. Two gestures, two places, neither guessing.
    frame.sideArea = CreateFrame("Frame", nil, frame)
    frame.sideArea:SetSize(SIDE_W, SIDE_ROWS * SIDE_ROW_H)
    frame.sideArea:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE_X, -40)
    frame.sideArea:EnableMouseWheel(true)
    frame.sideArea:SetScript("OnMouseWheel", function(_, delta)
        Death.sideOffset = math.max(0, math.min(
            math.max(0, #Death.log - SIDE_ROWS),
            (Death.sideOffset or 0) - delta))
        PaintSideList()
    end)

    frame.sideRows = {}
    for i = 1, SIDE_ROWS do
        local row = CreateFrame("Button", nil, frame.sideArea)
        row:SetSize(SIDE_W, SIDE_ROW_H)
        row:SetPoint("TOPLEFT", frame.sideArea, "TOPLEFT", 0,
            -((i - 1) * SIDE_ROW_H))

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints(row)
        row.bg:Hide()

        -- The accent bar on the left edge marks the one being read. A
        -- fill alone reads as hover on a list you can also hover.
        row.mark = row:CreateTexture(nil, "ARTWORK")
        row.mark:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        row.mark:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        row.mark:SetWidth(2)
        row.mark:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        row.mark:Hide()

        row.when = UI.Label(row, "", 11, C.text)
        row.when:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -4)

        -- The place and the killer both in the orange this addon now uses
        -- for a word that answers: the whole row is a button, and these two
        -- are what it is a button ABOUT.
        -- THE GUIDE'S TILE, A COLUMN OF ITS OWN down the right of the row,
        -- as tall as the row and in its true shape - a button that opens the
        -- Adventure Guide on that instance; the row underneath still opens
        -- the death. The three text lines stop where it starts.
        row.art = Death.CreatePlaceArt(row)
        row.art:SetPoint("RIGHT", row, "RIGHT", -4, 0)

        row.where = UI.Label(row, "", 11, C.hot)
        row.where:SetPoint("TOPRIGHT", row.art, "TOPLEFT", -6, -2)
        row.where:SetJustifyH("RIGHT")
        row.where:SetWidth(96)
        row.where:SetWordWrap(false)

        row.who = UI.Label(row, "", 11, C.hot)
        row.who:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -19)
        row.who:SetPoint("RIGHT", row.art, "LEFT", -6, 0)
        row.who:SetJustifyH("LEFT")
        row.who:SetWordWrap(false)

        -- The place, named, in the blue every instance name in the addon
        -- wears now (owner: "die dungeon namen sollten wir in blau
        -- einfaerben").
        row.place = UI.Label(row, "", 11, C.accentCool)
        row.place:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 6)
        row.place:SetPoint("RIGHT", row.art, "LEFT", -6, 0)
        row.place:SetJustifyH("LEFT")
        row.place:SetWordWrap(false)

        row:SetScript("OnEnter", function(self)
            if self.index ~= Death.showing then
                row.bg:SetColorTexture(C.surface[1], C.surface[2], C.surface[3], 1)
                row.bg:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            if self.index ~= Death.showing then row.bg:Hide() end
        end)
        row:SetScript("OnClick", function(self)
            if self.index then Death:Show(self.index) end
        end)

        row:Hide()
        frame.sideRows[i] = row
    end

    -- Clearing the list. Two steps, like every other irreversible button in
    -- this addon: there is no undo, and a mis-click during a wipe would
    -- take the analysis you were about to read.
    local clearArmed, clear = false, nil
    clear = UI.Button(frame, "Clear list", 100, function()
        if not clearArmed then
            clearArmed = true
            clear.label:SetText("Sure?")
            return
        end
        clearArmed = false
        clear.label:SetText("Clear list")
        Death:Clear()
    end)
    clear:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", SIDE_X, 12)
    frame.disarmClear = function()
        clearArmed = false
        clear.label:SetText("Clear list")
    end
    frame:SetScript("OnHide", function() frame.disarmClear() end)

    -- THE PANEL DOWN THE LEFT: what you pressed, what you still had, what
    -- else you cast. It replaced the availability footer that used to grow
    -- upward from the buttons - a strip of chips under the table, with the
    -- other two lists written as sentences over it. Built by the one
    -- function the replay's panel comes out of; see BuildDefensivePanel.
    local leftDivider = frame:CreateTexture(nil, "ARTWORK")
    leftDivider:SetColorTexture(C.edge[1], C.edge[2], C.edge[3], 1)
    leftDivider:SetPoint("TOPLEFT", frame, "TOPLEFT", MAIN_X - GUTTER, -14)
    leftDivider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", MAIN_X - GUTTER, 14)
    leftDivider:SetWidth(1)

    frame.panel = Death.BuildDefensivePanel(frame, PANEL_W)
    frame.panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
    frame.panel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 14)

    local share = UI.Button(frame, "Share in chat", 130, function()
        Death:Share()
    end, "primary")
    share:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", MAIN_X, 12)
    frame.share = share

    -- The replay. The owner's words: "du kannst das live nachvollziehen".
    local replay = UI.Button(frame, "Replay", 90, function()
        ns.Replay:Open(Death.log[Death.showing or #Death.log])
    end)
    replay:SetPoint("LEFT", share, "RIGHT", 8, 0)
    frame.replayButton = replay

    -- The size, on the window rather than in a settings page: the moment
    -- you want this smaller is the moment it is in front of you. A slider
    -- rather than a button walking six steps - the owner asked, and he is
    -- right that dragging to a size beats clicking past four of them.
    local scaleRow = UI.Row(frame, "Size", { controlWidth = 110 })
    scaleRow:SetPoint("LEFT", replay, "RIGHT", 12, 0)
    scaleRow.rule:Hide()
    UI.Slider(scaleRow, {
        get = function() return (ns.db.death and ns.db.death.scale) or 1 end,
        set = function(value)
            ns.db.death = ns.db.death or {}
            ns.db.death.scale = value
        end,
        min = SCALE_MIN, max = SCALE_MAX, step = 0.05,
        -- scale: the box shows and takes PERCENT. Without it a typed "80"
        -- would be stored as eighty and paint this window over four screens.
        scale = 100,
        silent = true,
        format = function(v)
            return string.format("%d%%", math.floor((v or 1) * 100 + 0.5))
        end,
        apply = function() Death.ApplyScale() end,
    })
    -- Sized to the slider that is actually in it. See UI.FitRow: the slot was
    -- 110 and the slider is 156, so it hung out of the left of its own slot
    -- and drew over the word "Size".
    UI.FitRow(scaleRow)
    frame.scaleRow = scaleRow

    -- NO "CLOSE" BUTTON. The X in the corner already closes this window, and
    -- so does Escape. Owner: "den close button kannsten auch bei allen
    -- fenstern rausnehmen, wir haben ja das X" - and it is the right call
    -- twice over, because the ninety pixels it took are what the slider
    -- beside it needed.
end

-- The window the replay reads. It shows ONE death - whichever is on
-- screen - and Core/Replay.lua opens on that snapshot.
function Death.Showing()
    return Death.log[Death.showing or #Death.log]
end

function Death.ApplyScale()
    if not frame then return end
    frame:SetScale((ns.db and ns.db.death and ns.db.death.scale) or 1)
end

-- A FACE ON A MODEL, or nothing at all. Two doors, both guarded: a creature
-- id through SetCreature - MDT's enemy tooltip does exactly this with a raw
-- npc id - and a display id through SetDisplayInfo. Neither answering means
-- the caller hides its block rather than showing an empty one.
--
-- Exported because there are three of these now: the death window's header,
-- the replay's marks, and the raid death log's rows. It was copied once and
-- about to be copied twice; the same six branches in three files is how one
-- of them quietly stops matching the other two.
function Death.PaintArt(model, art)
    if not (model and art and (art.creatureID or art.displayID)) then
        if model then model:Hide() end
        return false
    end
    local ok = false
    if art.creatureID and model.SetCreature then
        ok = pcall(model.SetCreature, model, art.creatureID)
    end
    if not ok and art.displayID and model.SetDisplayInfo then
        ok = pcall(model.SetDisplayInfo, model, art.displayID)
    end
    if not ok then
        model:Hide()
        return false
    end
    pcall(model.SetPosition, model, 0, 0, 0)
    pcall(model.SetFacing, model, 0.4)
    -- A HEAD SHOT, not a figure standing in a box. This is what Blizzard's
    -- own unit portraits do with the same widget, and it is the half of
    -- "2d avatare head shots" that does not depend on a display id ever
    -- being handed over: even when the flat portrait never happens, what is
    -- on screen is a face rather than a silhouette in the middle distance.
    if model.SetPortraitZoom then
        pcall(model.SetPortraitZoom, model, 1)
    else
        pcall(model.SetCamDistanceScale, model, 1.35)
    end
    model:Show()
    return true
end

---------------------------------------------------------------------------
-- A CREATURE'S FACE AS A PICTURE, NOT A PUPPET
--
-- Owner, 2026-08-14: "mach statt die 3d model die 2d avatare head shots da
-- rein! bei allen 3 fenstern ... dann werden die groesser und man kann das
-- besser erkennen." He is right about the reason. A whole body drawn into
-- twenty-two pixels is a dark smudge, and every smudge looks like every
-- other one - which defeats the entire point of putting a face beside a name.
--
-- TWO DOORS, because the recap does not hand over what the 2D call wants.
-- SetPortraitTextureFromCreatureDisplayID needs a DISPLAY id, and the probe
-- dump of 2026-08-14 shows a recap event carries no id of any kind: the only
-- one we ever get is an NPC id parsed out of the source GUID. So
--
--   1. a display id, if one is ever handed over - straight to the portrait.
--   2. an npc id - the model is asked to load it and its display id read back
--      off it with GetDisplayInfo, which is the only route the client offers
--      from one to the other. It answers a frame or two later, so the model
--      is what is on screen until it does. The answer is cached by npc id, so
--      the second row with the same mob is free and instant.
--
-- AND THE MODEL IS A HEAD SHOT EITHER WAY. SetPortraitZoom is what Blizzard's
-- own unit frames use, and it is the half of the ask that does not depend on
-- any of the above working - so even a client that never answers (2) gets a
-- face instead of a silhouette.
--
-- Which door answered is COUNTED and reported by the self test rather than
-- assumed, because none of this can be proven at a desk with no game in it.
---------------------------------------------------------------------------
local displayOf = {}
Death.faceStats = { flat = 0, model = 0, none = 0 }

local function PortraitCall()
    return SetPortraitTextureFromCreatureDisplayID
end

-- The display id for a creature, if it is already known. Pure lookup.
function Death.DisplayFor(art)
    if type(art) ~= "table" then return nil end
    if art.displayID then return art.displayID end
    return art.creatureID and displayOf[art.creatureID] or nil
end

-- Remembered so the next row showing the same mob takes the fast door. Its
-- own function so a check can seed it without a model in the room.
function Death.RememberDisplay(creatureID, displayID)
    if type(creatureID) == "number" and type(displayID) == "number"
        and displayID > 0 then
        displayOf[creatureID] = displayID
        return true
    end
    return false
end

-- A face: one texture and one model, and exactly one of them is ever shown.
function Death.CreateFace(parent, size)
    local face = CreateFrame("Frame", nil, parent)
    face:SetSize(size, size)

    face.flat = face:CreateTexture(nil, "ARTWORK")
    face.flat:SetAllPoints(face)
    face.flat:Hide()

    face.model = CreateFrame("PlayerModel", nil, face)
    face.model:SetAllPoints(face)
    face.model:Hide()

    -- The model answers with its display id once it has loaded, and that is
    -- the moment the 2D door opens for every row after this one.
    face.model:SetScript("OnModelLoaded", function(self)
        local art = face.art
        if not (art and art.creatureID and self.GetDisplayInfo) then return end
        local ok, id = pcall(self.GetDisplayInfo, self)
        if ok and Death.RememberDisplay(art.creatureID, id) then
            Death.PaintFace(face, art)
        end
    end)

    face:Hide()
    return face
end

function Death.PaintFace(face, art)
    if not face then return false end
    face.art = art
    if not (type(art) == "table" and (art.creatureID or art.displayID)) then
        face.flat:Hide()
        face.model:Hide()
        face:Hide()
        Death.faceStats.none = Death.faceStats.none + 1
        return false
    end

    local display = Death.DisplayFor(art)
    local paint = PortraitCall()
    if display and type(paint) == "function" then
        local ok = pcall(paint, face.flat, display)
        if ok then
            face.model:Hide()
            face.flat:Show()
            face:Show()
            Death.faceStats.flat = Death.faceStats.flat + 1
            return true
        end
    end

    -- The older road, and it is not a failure - it is what is on screen while
    -- the display id is still coming back, and forever on a client that never
    -- answers with one.
    --
    -- UNLESS THE FACE IS FLAT-ONLY. The hover tip's picture is (owner,
    -- 2026-08-16: "entferne den 3d avatar beim hover und ersetze ihn durch
    -- den 2d avatar"): the model is still asked to load, because that is
    -- the only road to the display id the flat portrait needs - but it
    -- loads at alpha nought and the portrait takes its place the moment
    -- OnModelLoaded answers. The square is reserved either way, so the
    -- text beside it does not jump when the picture arrives.
    face.flat:Hide()
    face.model:SetAlpha(face.flatOnly and 0 or 1)
    if Death.PaintArt(face.model, art) then
        face:Show()
        Death.faceStats.model = Death.faceStats.model + 1
        return true
    end
    face:Hide()
    Death.faceStats.none = Death.faceStats.none + 1
    return false
end

-- A PERSON'S FACE, which is a different question from a creature's: the
-- client draws a portrait for a unit it can still see, and there is no id to
-- look one up by. So it is a unit token or nothing, and "nothing" is honest -
-- somebody who left the group is somebody we cannot picture.
--
-- One copy, because the replay's marks ask exactly the same question and its
-- own version compared only the full name, so anybody on our own realm never
-- matched it.
function Death.PaintUnitFace(texture, name)
    if not texture then return false end
    local unit = ns.Specs and ns.Specs.UnitForName(name)
    if not (unit and SetPortraitTexture) then
        texture:Hide()
        return false
    end
    -- The round crop Blizzard's own portraits use, so a face reads as a
    -- portrait and not as a screenshot of one.
    texture:SetTexCoord(0.15, 0.85, 0.15, 0.85)
    local ok = pcall(SetPortraitTexture, texture, unit)
    texture:SetShown(ok and true or false)
    return ok and true or false
end

local function PaintPortrait(art)
    return Death.PaintFace(frame.portrait, art)
end

---------------------------------------------------------------------------
-- THE ENEMY TIP - one big tooltip, everywhere a mob's face is drawn
--
-- His ask: "wenn ich mit der maus über den gegner fahre, bitte größeres
-- tooltip mit größerem bild und fähigkeiten etc. das bitte überall in allen
-- fenstern wo gegner bilder zu sehen sind."
--
-- WHAT IS HONESTLY IN IT, and the limit was measured months ago rather than
-- assumed now: there is NO client call that lists an arbitrary NPC's
-- abilities, and inside a dungeon a mob withholds its name, its health and
-- its creature type outright. The Encounter Journal knows bosses and nothing
-- about trash. So this cannot be a wiki page.
--
-- What it is instead is better for the question being asked: what this thing
-- did HERE, in these seconds, with which abilities - summed from the recap
-- events we have already read. "It hit you nine times for 416k, biggest 59.8k,
-- with Curse of Torment and Melee" is what you want at the moment you are
-- pointing at its face, and no database has it.
--
-- Its own frame rather than GameTooltip, because the whole point is the big
-- picture and a 3D model inside the client's tooltip fights its autosizing.
---------------------------------------------------------------------------
local FACE = 116
local TIP_W = 300

local enemyTip

local function BuildEnemyTip()
    local UI, C = ns.UI, ns.UI.C

    enemyTip = CreateFrame("Frame", "ZwoelfStuffEnemyTip", UIParent)
    enemyTip:SetWidth(TIP_W)
    enemyTip:SetFrameStrata("TOOLTIP")
    enemyTip:SetClampedToScreen(true)
    enemyTip:Hide()

    UI.Fill(enemyTip, "BACKGROUND", C.well)
    local edge = ns.CreateBorder(enemyTip, 1, "BORDER")
    edge:SetColor(C.overlayEdge[1], C.overlayEdge[2], C.overlayEdge[3], 1)
    UI.Shadow(enemyTip, 16, 0.6)

    -- THE FLAT PORTRAIT, not the turning model. Owner, 2026-08-16. Same
    -- face the rows wear, four times the size; see Death.CreateFace.
    enemyTip.face = Death.CreateFace(enemyTip, FACE)
    enemyTip.face.flatOnly = true
    enemyTip.face:SetPoint("TOPLEFT", enemyTip, "TOPLEFT", 12, -12)

    enemyTip.name = UI.Label(enemyTip, "", UI.FS.card, C.text)
    enemyTip.name:SetPoint("TOPLEFT", enemyTip.face, "TOPRIGHT", 12, -2)
    enemyTip.name:SetPoint("RIGHT", enemyTip, "RIGHT", -12, 0)
    enemyTip.name:SetJustifyH("LEFT")

    enemyTip.facts = UI.Label(enemyTip, "", UI.FS.meta, C.textDim)
    enemyTip.facts:SetPoint("TOPLEFT", enemyTip.name, "BOTTOMLEFT", 0, -6)
    enemyTip.facts:SetPoint("RIGHT", enemyTip, "RIGHT", -12, 0)
    enemyTip.facts:SetJustifyH("LEFT")
    enemyTip.facts:SetWordWrap(true)

    -- The abilities, under the picture and across the full width - a long
    -- name has the whole box rather than the column beside the model.
    enemyTip.what = UI.Eyebrow(enemyTip, "What it used here")
    enemyTip.what:SetPoint("TOPLEFT", enemyTip.face, "BOTTOMLEFT", 0, -10)

    enemyTip.spells = UI.Label(enemyTip, "", UI.FS.meta, C.textBody)
    enemyTip.spells:SetPoint("TOPLEFT", enemyTip.what, "BOTTOMLEFT", 0, -5)
    enemyTip.spells:SetPoint("RIGHT", enemyTip, "RIGHT", -12, 0)
    enemyTip.spells:SetJustifyH("LEFT")
    enemyTip.spells:SetWordWrap(true)

    enemyTip.note = UI.Label(enemyTip, "", UI.FS.meta, C.textFaint)
    enemyTip.note:SetPoint("TOPLEFT", enemyTip.spells, "BOTTOMLEFT", 0, -8)
    enemyTip.note:SetPoint("RIGHT", enemyTip, "RIGHT", -12, 0)
    enemyTip.note:SetJustifyH("LEFT")
    enemyTip.note:SetWordWrap(true)
    return enemyTip
end

-- WHAT IT DID HERE, as one sentence. Pure and exported: three windows show
-- this and one wording is the whole point.
function Death.EnemyFacts(summary)
    if not (summary and summary.hits and summary.hits > 0) then return "" end
    if summary.hits == 1 then
        return string.format("One hit, %s.", ns.ShortNumber(summary.total or 0))
    end
    return string.format("%d hits for %s, biggest %s.",
        summary.hits, ns.ShortNumber(summary.total or 0),
        ns.ShortNumber(summary.biggest or 0))
end

-- The abilities as one readable line, each with its icon, which is the rule
-- everywhere in this addon.
function Death.EnemySpells(summary)
    local list = summary and summary.spells
    if not (list and #list > 0) then return "" end
    return Death.SpellList(list, "   ")
end

function Death.ShowEnemyTip(owner, spec)
    if not (ns.UI and ns.UI.C and owner and spec and spec.who) then return end
    if not enemyTip then BuildEnemyTip() end

    enemyTip.name:SetText(spec.who)
    enemyTip.facts:SetText(Death.EnemyFacts(spec.summary))

    local spells = Death.EnemySpells(spec.summary)
    enemyTip.spells:SetText(spells)
    enemyTip.what:SetShown(spells ~= "")
    enemyTip.note:SetText(spec.note or "")

    local drawn = Death.PaintFace(enemyTip.face, spec.art)
    -- No picture is not an empty box: the text slides up into its place.
    enemyTip.name:ClearAllPoints()
    enemyTip.name:SetPoint("RIGHT", enemyTip, "RIGHT", -12, 0)
    if drawn then
        enemyTip.name:SetPoint("TOPLEFT", enemyTip.face, "TOPRIGHT", 12, -2)
        enemyTip.what:SetPoint("TOPLEFT", enemyTip.face, "BOTTOMLEFT", 0, -10)
    else
        enemyTip.name:SetPoint("TOPLEFT", enemyTip, "TOPLEFT", 12, -12)
        enemyTip.what:SetPoint("TOPLEFT", enemyTip.facts, "BOTTOMLEFT", 0, -10)
    end

    -- As tall as what is in it. A fixed height leaves a mob with one ability
    -- sitting in half a box of nothing.
    local height = (drawn and (FACE + 24) or 56)
        + (spells ~= "" and 40 or 0)
        + ((spec.note and spec.note ~= "") and 34 or 0)
    enemyTip:SetHeight(height)

    enemyTip:ClearAllPoints()
    enemyTip:SetPoint("BOTTOMLEFT", owner, "TOPRIGHT", 6, 6)
    enemyTip:Show()
end

function Death.HideEnemyTip()
    if enemyTip then enemyTip:Hide() end
end

-- For the checks: a local frame is invisible to every one of them.
function Death.EnemyTipFrame()
    return enemyTip
end

-- WHAT A SOURCE DID, summed out of the events we already hold. Lives here
-- rather than in Replay because three windows ask it now and the recap is
-- Death's to read; Replay keeps the name it has always called it by.
--
-- The spells are carried as {spellID, name} rather than as bare names, so
-- the tip can draw each one with its icon.
function Death.SourceSummary(events, who)
    local out = { hits = 0, total = 0, biggest = 0, spells = {} }
    if not who then return out end
    local seen = {}
    for _, ev in ipairs(events or {}) do
        if ev.who == who and not ev.heal then
            out.hits = out.hits + 1
            out.total = out.total + (ev.amount or 0)
            if (ev.amount or 0) > out.biggest then out.biggest = ev.amount end
            local name = ev.name
            if name and not seen[name] then
                seen[name] = true
                out.spells[#out.spells + 1] =
                    { name = name, spellID = ev.spellID }
            end
        end
    end
    return out
end

-- The side list, repainted whole. Newest at the top, because that is the
-- one being asked about nine times in ten.
function PaintSideList()
    local total = #Death.log
    local today = date("%Y-%m-%d")
    local offset = math.max(0, math.min(math.max(0, total - SIDE_ROWS),
        Death.sideOffset or 0))
    Death.sideOffset = offset
    for slot = 1, SIDE_ROWS do
        local row = frame.sideRows[slot]
        local index = total - (offset + slot - 1)
        local snapshot = index >= 1 and Death.log[index] or nil
        if not snapshot then
            row.index = nil
            row:Hide()
        else
            row.index = index
            row.when:SetText(Death.WhenLabel(snapshot, today))
            row.where:SetText(snapshot.whereShort or "")
            row.who:SetText(snapshot.killer or "|cff626a76no killer named|r")
            row.place:SetText(snapshot.instance or "")
            -- No tile, no column: the text lines run to the row's edge.
            local drawn = row.art.Paint(snapshot.journal)
            local edge = drawn and row.art or row
            for _, label in ipairs({ row.where, row.who, row.place }) do
                label:ClearAllPoints()
            end
            row.where:SetPoint("TOPRIGHT", edge, drawn and "TOPLEFT" or "TOPRIGHT",
                -6, drawn and -2 or -4)
            row.who:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -19)
            row.who:SetPoint("RIGHT", edge, drawn and "LEFT" or "RIGHT", -6, 0)
            row.place:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 6)
            row.place:SetPoint("RIGHT", edge, drawn and "LEFT" or "RIGHT", -6, 0)
            local selected = index == Death.showing
            row.mark:SetShown(selected)
            if selected then
                local C = ns.UI.C
                row.bg:SetColorTexture(C.control[1], C.control[2], C.control[3], 1)
                row.bg:Show()
            else
                row.bg:Hide()
            end
            row:Show()
        end
    end
    -- The count is also the only hint that there is more below the edge,
    -- so it says so rather than leaving the wheel to be discovered.
    if total > SIDE_ROWS then
        frame.sideTitle:SetText(string.format("%d deaths - scroll for more",
            total))
    else
        frame.sideTitle:SetText(total == 1 and "This session - 1 death"
            or string.format("This session - %d deaths", total))
    end
end

function Death:Show(index)
    if #self.log == 0 then
        ns.Print("No death recorded yet this session.")
        return
    end

    -- Clamped, not wrapped: paging past the oldest death and landing on the
    -- newest reads as the list jumping, not as an edge.
    index = index or self.showing or #self.log
    if index < 1 then index = 1 end
    if index > #self.log then index = #self.log end
    self.showing = index
    local snapshot = self.log[index]

    if not frame then BuildWindow() end
    frame.disarmClear()
    Death.ApplyScale()
    frame.scaleRow.Refresh()
    Death.Upgrade(snapshot)

    -- The killer, when the recap named one readably. The name is already
    -- through SafeName's door or it would not be in the snapshot.
    local when = Death.WhenLabel(snapshot, date("%Y-%m-%d"))
    if snapshot.killer then
        -- ORANGE ON THE KILLER, because that word is the one the portrait
        -- beside it answers for: point at the face and the big tip opens.
        frame.sub:SetText(string.format("%s  -  killed by %s  -  the last %d seconds",
            when, ns.UI.HotText(snapshot.killer), WINDOW))
    else
        frame.sub:SetText(string.format("%s  -  the last %d seconds",
            when, WINDOW))
    end

    -- The place, in the same orange every instance name in the addon wears
    -- now - it is the line somebody reads to know which run this was.
    -- Blue, like every place name in the addon now (owner, 2026-08-16:
    -- "da den dungeon namen auch in blau").
    frame.place:SetText(snapshot.where or "")
    frame.place:SetTextColor(UI.C.accentCool[1], UI.C.accentCool[2],
        UI.C.accentCool[3])
    frame.placeArt:ClearAllPoints()
    frame.placeArt:SetPoint("BOTTOMLEFT", frame.place, "BOTTOMLEFT",
        math.min(frame.place:GetStringWidth() or 0, MAIN_W - 70) + 8, -4)
    frame.placeArt.Paint(snapshot.journal)

    -- The portrait decides where the header starts: with a face, the text
    -- moves out of its way; without one, it keeps the left margin every
    -- other window in this addon uses.
    local hasPortrait = PaintPortrait(snapshot.killerArt)
    frame.title:ClearAllPoints()
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT",
        MAIN_X + (hasPortrait and 66 or 0), -14)

    Death.sideOffset = Death.ScrollTo(index, #self.log,
        Death.sideOffset, SIDE_ROWS)
    PaintSideList()

    -- The judgement over the table; the lists it used to carry are rows
    -- down the panel on the left now.
    frame.verdict:SetText(table.concat(
        Death.VerdictLines(snapshot.analysis), "\n"))

    -- Rows: only what falls inside the promised window - the first live
    -- death showed hits from five minutes earlier under a subtitle saying
    -- ten seconds. The LAST of those win the visible slots, oldest on top.
    local events, stale = Death.RecentEvents(snapshot.events, WINDOW)
    if stale and #events > 0 then
        -- Nothing recent, so the promise is re-worded rather than broken.
        frame.sub:SetText(when
            .. "  -  nothing in the last seconds; the events below are older")
    end
    local shown = 0
    local maxHP = snapshot.maxHP

    -- Anchored under the verdict, which wraps: measured, not guessed.
    local top = HEADER_BOTTOM + (frame.verdict:GetStringHeight() or 0) + 14

    -- The table's head, and the sentence that says what the fill behind the
    -- rows means. Both go with the table: no rows, no head.
    frame.tableNote:ClearAllPoints()
    frame.tableNote:SetPoint("TOPLEFT", frame, "TOPLEFT", MAIN_X, -top)
    frame.head:ClearAllPoints()
    frame.head:SetPoint("TOPLEFT", frame, "TOPLEFT", MAIN_X, -(top + 17))
    if #events > 0 then
        -- His words for the legend (2026-08-16): "grey your health, red
        -- damage income" - two colours, two nouns, and the total.
        frame.tableNote:SetText(maxHP
            and string.format("Oldest first - |cff8d97a6grey|r your health, "
                .. "|cffc45c5cred|r the damage taken - out of %s.",
                ns.ShortNumber(maxHP))
            or "Oldest first - |cff8d97a6grey|r your health, "
                .. "|cffc45c5cred|r the damage taken.")
        frame.head:Show()
    else
        frame.tableNote:SetText("")
        frame.head:Hide()
    end
    top = top + 36

    -- THE AREA THE ROWS LIVE IN. Top under the head, bottom on the footer -
    -- and the footer's own block grows upward with however many defensives
    -- there are to name, so the two can no longer be drawn over each other
    -- whatever either of them contains.
    frame.listHost:ClearAllPoints()
    frame.listHost:SetPoint("TOPLEFT", frame, "TOPLEFT", MAIN_X, -top)
    frame.listHost:SetPoint("TOPRIGHT", frame, "TOPLEFT", MAIN_X + MAIN_W, -top)
    -- BOTTOMLEFT rather than BOTTOM: three points have to describe a
    -- rectangle without arguing about it, and a centre point next to a left
    -- and a right one is a fourth opinion on where the left edge is. On the
    -- buttons now that the footer is gone: the table has the room the
    -- chips used to take.
    frame.listHost:SetPoint("BOTTOMLEFT", frame.share, "TOPLEFT", 0, 12)
    frame.listHost:SetShown(#events > 0)

    for i = 1, #events do
        shown = shown + 1
        local row = frame.rows[shown]
        if not row then
            row = frame.BuildRow()
            frame.rows[shown] = row
        end
        local ev = events[i]

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.listContent, "TOPLEFT", 0,
            -((shown - 1) * (ROW_H + 2)))

        -- The row, its columns and its bars are all painted by the one
        -- function the group log paints its rows with.
        Death.PaintEventRow(row, ev, maxHP, events)
    end
    -- Rows the pool has and this death does not need. It is a POOL, so it
    -- is as long as the messiest death seen this session, not as long as
    -- this one.
    for i = shown + 1, #frame.rows do
        frame.rows[i].ev = nil
        frame.rows[i]:Hide()
    end

    -- What the scrolling area now holds, and where it opens.
    --
    -- AT THE BOTTOM, because the row that matters is the last one - the hit
    -- that killed you. A list of thirty that opens on the oldest hit puts
    -- the answer below the fold.
    --
    -- One frame later, and that is not superstition: the scroll range is
    -- computed by the client from the child's height against the viewport,
    -- and neither is resolved until this window has been laid out once.
    -- Asking now answers 0 on the first death of the session.
    frame.listContent:SetHeight(math.max(1, shown * (ROW_H + 2)))
    C_Timer.After(0, function()
        if not (frame and frame:IsShown()) then return end
        local range = frame.list:GetVerticalScrollRange() or 0
        frame.list:SetVerticalScroll(range > 1 and range or 0)
        if frame.list.Update then frame.list.Update() end
    end)

    -- The panel: what you pressed, what you still had, what else you cast.
    frame.panel.Paint(snapshot)

    frame:Show()
end

-- The list cut down to what is being kept, oldest first out of the door.
-- Called when the setting changes: lowering it from fifty to ten and
-- leaving forty in the list until they fall out one death at a time would
-- be a setting that does nothing for an evening.
function Death.Trim()
    local keep = Death.KeepCount()
    while #Death.log > keep do table.remove(Death.log, 1) end
    Death.snapshot = Death.log[#Death.log]
    if Death.showing and Death.showing > #Death.log then
        Death.showing = #Death.log > 0 and #Death.log or nil
    end
    Death.sideOffset = 0
    Death.Save()
    Death.RefreshIcon()
    if frame and frame:IsShown() then
        if #Death.log == 0 then frame:Hide() else Death:Show(Death.showing) end
    end
end

-- Throwing the session's deaths away. The skull goes with them - it counts
-- what is in the list, and a skull over an empty list is a promise the
-- click cannot keep.
function Death:Clear()
    local had = #self.log
    Death.ClearLog(self.log)
    self.snapshot = nil
    self.showing = nil
    if frame then frame:Hide() end
    Death.RefreshIcon()
    Death.Save()
    ns.Print(had == 1 and "The one death this session is cleared."
        or string.format("%d deaths cleared.", had))
end

---------------------------------------------------------------------------
-- The icon on the screen - the owner's ask in his words: "ein kleines
-- death icon auf dem screen, das wir jederzeit frei bewegen oder locken
-- können. beim klick öffnet sich das dann."
--
-- Deliberately NOT an Edit Mode mover: "jederzeit frei bewegen" is the
-- minimap button's contract, not the bars' - drag it whenever it is not
-- locked, and the lock lives on the Deaths page. It appears with the first
-- death and not before: an always-on skull promising nothing is furniture.
---------------------------------------------------------------------------
local iconButton

local function IconConfig()
    ns.db.death = ns.db.death or {}
    ns.db.death.icon = ns.db.death.icon or {}
    return ns.db.death.icon
end

local function BuildIcon()
    local C = ns.UI.C

    iconButton = CreateFrame("Button", "ZwoelfStuffDeathIcon", UIParent)
    iconButton:SetSize(30, 30)
    iconButton:SetFrameStrata("MEDIUM")
    iconButton:SetClampedToScreen(true)
    iconButton:SetMovable(true)
    iconButton:RegisterForDrag("LeftButton")
    iconButton:Hide()

    local bg = iconButton:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(iconButton)
    bg:SetColorTexture(C.windowBg[1], C.windowBg[2], C.windowBg[3], 0.85)

    local edge = ns.CreateBorder(iconButton, 1, "BORDER")
    edge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)

    -- The client's own skull, shipped since the beginning of time - not a
    -- traced one, for the same reason the Discord row carries no mark.
    local skull = iconButton:CreateTexture(nil, "ARTWORK")
    skull:SetPoint("TOPLEFT", iconButton, "TOPLEFT", 3, -3)
    skull:SetPoint("BOTTOMRIGHT", iconButton, "BOTTOMRIGHT", -3, 3)
    skull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")

    -- How many this session, in the corner. The number is the reason to
    -- click at all after a rough pull.
    iconButton.count = iconButton:CreateFontString(nil, "OVERLAY")
    ns.Media.ApplyFont(iconButton.count, nil, 10, "OUTLINE")
    iconButton.count:SetPoint("BOTTOMRIGHT", iconButton, "BOTTOMRIGHT", -1, 1)

    iconButton:SetScript("OnClick", function() Death:Show() end)

    iconButton:SetScript("OnDragStart", function() Death.DragIcon(true) end)
    iconButton:SetScript("OnDragStop", function() Death.DragIcon(false) end)

    iconButton:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Deaths this session: " .. #Death.log, 1, 1, 1)
        GameTooltip:AddLine(IconConfig().locked
            and "Click to open. The position is locked on the Deaths page."
            or "Click to open. Drag to move it.", 0.6, 0.63, 0.69, true)
        GameTooltip:Show()
    end)
    iconButton:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
end

---------------------------------------------------------------------------
-- ONE POSITION, TWO ICONS.
--
-- The raid death log has a second icon docked to this one. There is still
-- exactly ONE saved position, and whichever icon is leftmost sits on it -
-- so dragging either of them moves the pair, and neither can be stranded.
-- These four are what the other file needs to take part in that without
-- knowing anything about this one's internals.
---------------------------------------------------------------------------

-- The frame, built but never shown from here. It is the anchor the docked
-- icon hangs on, and it has to exist even on a character who has not died.
function Death.EnsureIcon()
    if not (ns.UI and ns.UI.C) then return nil end
    if not iconButton then BuildIcon() end
    return iconButton
end

function Death.IconShown()
    return iconButton ~= nil and iconButton:IsShown()
end

function Death.IconLocked()
    return IconConfig().locked == true
end

-- Where the pair lives, written back in CENTRE terms and reapplied, so the
-- saved numbers and the frame never disagree about what was just dragged.
function Death.SaveIconAt(frame)
    local x, y = frame:GetCenter()
    local px, py = UIParent:GetCenter()
    if not (x and y and px and py) then return end
    local cfg = IconConfig()
    cfg.x = math.floor(x - px + 0.5)
    cfg.y = math.floor(y - py + 0.5)
end

function Death.DragIcon(starting)
    if not iconButton then return end
    if starting then
        if Death.IconLocked() then return end
        iconButton:StartMoving()
        return
    end
    iconButton:StopMovingOrSizing()
    Death.SaveIconAt(iconButton)
    Death.RefreshIcon()
end

function Death.RefreshIcon()
    if not ns.UI then return end
    local cfg = (ns.db and ns.db.death and ns.db.death.icon) or {}
    local moduleOff = ns.Modules and not ns.Modules:IsOn("deaths")
    if moduleOff or #Death.log == 0 or cfg.show == false then
        if iconButton then iconButton:Hide() end
        -- Still refreshed: the group may have lost people on a pull this
        -- character walked out of, and that log is worth an icon of its own.
        if ns.RaidDeaths then ns.RaidDeaths.RefreshIcon() end
        return
    end
    if not iconButton then BuildIcon() end

    iconButton:ClearAllPoints()
    iconButton:SetPoint("CENTER", UIParent, "CENTER",
        cfg.x or 320, cfg.y or -180)
    iconButton.count:SetText(tostring(#Death.log))
    iconButton:Show()
    if ns.RaidDeaths then ns.RaidDeaths.RefreshIcon() end
end

---------------------------------------------------------------------------
-- The probe - every question at once, the way the Routes questions were
-- settled in one trip instead of five. Run it dead, on a corpse, after a
-- wipe: /zs death probe. What it prints decides which window fields stop
-- saying "unknown".
---------------------------------------------------------------------------
local function Verdict(value)
    if value == nil then return "|cff888888absent|r" end
    if not ns.CanCompute(value) then return "|cffff8040SECRET|r" end
    -- A nested table's address answers nothing; its length at least says
    -- "the list you are looking for may live here".
    if type(value) == "table" then
        return string.format("|cff7ec6d4table, %d list entries|r", #value)
    end
    return "|cff40ff40" .. tostring(value) .. "|r"
end

local function DumpTable(label, tbl)
    ns.Print("  " .. label .. ":")
    local keys = {}
    for key in pairs(tbl) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    for _, key in ipairs(keys) do
        ns.Print("    " .. key .. " = " .. Verdict(tbl[key]))
    end
end

function Death:Probe()
    ns.Print("|cffffd100death probe|r - the damage meter first:")
    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType
        and Enum and Enum.DamageMeterType) then
        ns.Print("  C_DamageMeter is |cffff4040not on this client|r.")
        return
    end

    -- EVERY SESSION TYPE THE CLIENT DECLARES, not the two this addon happens
    -- to read. A first run against a live client answered "0 deaths" in both
    -- Current and Overall while somebody had certainly died; walking the enum
    -- costs nothing and rules out "the deaths are in a session we never ask
    -- for" without another trip.
    --
    -- The session's OWN fields are printed before anything in it. The first
    -- in-game run printed "no deaths this fight" because the list sat under a
    -- field this code had guessed wrong - a probe that dumps the parent
    -- cannot be blinded that way.
    local types = {}
    for name, value in pairs(Enum.DamageMeterSessionType or {}) do
        if type(value) == "number" then
            types[#types + 1] = { key = value, label = name }
        end
    end
    table.sort(types, function(a, b) return a.key < b.key end)
    if #types == 0 then
        types = { { key = 0, label = "0 (the enum is empty)" } }
    end

    local me = UnitName("player")
    if not ns.CanCompute(me) then me = nil end

    -- EVERY DEATH, not the first. The whole question behind the raid death
    -- log is what a row about SOMEBODY ELSE carries, and the first row is as
    -- likely as not to be the player. Capped, because a long wipe is a long
    -- list and this goes into a chat frame.
    local foreignID
    for _, sessionType in ipairs(types) do
        local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType,
            sessionType.key, Enum.DamageMeterType.Deaths)
        if not ok or type(session) ~= "table" then
            ns.Print("  " .. sessionType.label .. ": no Deaths session.")
        else
            DumpTable(sessionType.label .. " session, every field", session)
            local list = session.combatSources or session.sources
            for index = 1, math.min(#(list or {}), 6) do
                local row = list[index]
                local name = row and row.name
                local mine = me and ns.CanCompute(name)
                    and type(name) == "string" and StripRealm(name) == me
                DumpTable(string.format("%s death %d, every field%s",
                    sessionType.label, index, mine and " (YOU)" or ""), row)

                -- Keep the first one that is NOT the player, for the single
                -- question that decides whether a raid death log can say what
                -- killed each person.
                if not mine and not foreignID then
                    local rid = row and row.deathRecapID
                    if ns.CanCompute(rid) and type(rid) == "number"
                        and rid > 0 then
                        foreignID = rid
                    end
                end
            end
        end
    end

    ---------------------------------------------------------------------
    -- THE ONE QUESTION THE RAID DEATH LOG HANGS ON
    --
    -- Owner asked for a timeline of who died and to what. Who and when is
    -- already in the list above. WHAT killed them needs the recap of a death
    -- that is not ours - and nothing anywhere says whether the client will
    -- hand that over. Asking is one call; reasoning about it is a guess.
    ---------------------------------------------------------------------
    if foreignID then
        local okOther, other = pcall(C_DeathRecap.GetRecapEvents, foreignID)
        if okOther and type(other) == "table" and other[1] then
            ns.Print(string.format(
                "  |cff40ff40SOMEBODY ELSE'S RECAP READS|r - id %s gave %d events.",
                tostring(foreignID), #other))
            DumpTable("their newest event, every field", other[1])
        else
            ns.Print("  |cffff4040somebody else's recap gave nothing|r - id "
                .. tostring(foreignID)
                .. ". A raid death log can say who and when, not to what.")
        end
    else
        ns.Print("  |cff888888no death by anybody but you in the list|r - run "
            .. "this after a wipe where somebody else died, or the question "
            .. "about reading their recap stays open.")
    end

    local recapID, why = Death.OwnRecapID()
    if not recapID then
        ns.Print("  own recap: |cffff8040" .. (why or "?") .. "|r")
        return
    end
    ns.Print("  own recap id: " .. Verdict(recapID))

    local okEv, raw = pcall(C_DeathRecap.GetRecapEvents, recapID)
    if not okEv or type(raw) ~= "table" then
        ns.Print("  GetRecapEvents |cffff4040threw or answered nothing|r.")
        return
    end
    ns.Print(string.format("  %d recap events. The newest, every field:", #raw))
    if raw[1] then DumpTable("event 1", raw[1]) end

    -- A HEALING event, in full. It is a different shape from a hit and it
    -- carries the two things the replay's bottom lane needs: who cast it,
    -- and whether an absorb or a shield is in there at all. Nothing else
    -- can answer that - the owner asked for shields and the honest reply
    -- until this prints is "we do not know yet".
    local healed
    for i = 1, #raw do
        local kind = raw[i].event
        if ns.CanCompute(kind) and type(kind) == "string"
            and kind:find("HEAL", 1, true) then
            healed = raw[i]
            break
        end
    end
    if healed then
        DumpTable("the newest HEAL event, every field", healed)
    else
        ns.Print("  |cff888888no healing event in this recap to look at|r")
    end

    -- What the header can draw and say, measured rather than assumed.
    local _, _, _, _, art = Death.ReadRecap(recapID)
    if art then
        ns.Print("  portrait: creature "
            .. Verdict(art.creatureID) .. ", display " .. Verdict(art.displayID))
    else
        ns.Print("  portrait: |cffff8040no creature or display id in the recap|r")
    end
    local where, short = Death.Where()
    ns.Print("  where: |cff40ff40" .. where .. "|r  (short: " .. short .. ")")
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------

-- Blizzard's own recap window opened for the owner's death while our first
-- damage-meter search came up empty. The id it opens with is by definition
-- OUR recap, so the opener is hooked and the id kept. Everything here is
-- guarded twice: the frame lives in a load-on-demand Blizzard addon, so the
-- global may not exist yet at our load - hence the second attempt on
-- ADDON_LOADED - and on some client this hook may simply never fire, which
-- costs nothing.
local recapHooked = false
local function TryHookBlizzardRecap()
    if recapHooked then return end
    if not (type(hooksecurefunc) == "function"
        and type(OpenDeathRecapUI) == "function") then
        return
    end
    recapHooked = true
    hooksecurefunc("OpenDeathRecapUI", function(recapID)
        if not (ns.CanCompute(recapID) and type(recapID) == "number"
            and recapID > 0) then
            return
        end
        -- A fresh death whose capture found nothing gets a second chance
        -- with the definitive id - and the window, if it is up showing
        -- "not enough was readable", is repainted rather than left lying.
        local snapshot = Death.snapshot
        if snapshot and snapshot.events == nil
            and (GetTime() - snapshot.at) < 120 then
            -- replace: this is the SAME death getting a better answer, not
            -- a new one for the pager.
            Death:Capture(recapID, true)
            if frame and frame:IsShown() then Death:Show(#Death.log) end
        end
    end)
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_DEAD")
watcher:RegisterEvent("ADDON_LOADED")
-- After every ADDON_LOADED, so the profile store is open and ns.account
-- points at a real table. This is what puts the skull back after a reload.
watcher:RegisterEvent("PLAYER_LOGIN")
-- The only thing that knows a BOSS is what you are standing in front of.
-- BigWigs runs its entire engage logic off this pair, so the name arrives
-- readable; it is still put through the same door as every other string.
watcher:RegisterEvent("ENCOUNTER_START")
watcher:RegisterEvent("ENCOUNTER_END")
watcher:SetScript("OnEvent", function(_, event, _, encounterName)
    if event == "ADDON_LOADED" then
        TryHookBlizzardRecap()
        return
    end

    if event == "PLAYER_LOGIN" then
        Death.Load()
        -- The pulls of the group, off the same disk and the same key. Loaded
        -- from here rather than from its own login handler so the order is
        -- fixed: the raid log's icon docks to this one's frame.
        if ns.RaidDeaths then ns.RaidDeaths.Load() end
        return
    end

    if event == "ENCOUNTER_START" then
        -- The first payload is the encounter id, the second its name.
        Death.encounter = (ns.CanCompute(encounterName)
            and type(encounterName) == "string" and encounterName ~= "")
            and encounterName or nil
        return
    end

    if event == "ENCOUNTER_END" then
        Death.encounter = nil
        return
    end

    -- The moment of the fall, before anything else: the capture runs the
    -- better part of a second later, and every cast offset is measured
    -- from here or your last press lands after the hit that killed you.
    Death.diedAt = GetTime()

    -- The module switch and the page's own "record deaths" switch, in that
    -- order. Both mean the same thing here and both have to be asked: the
    -- first is "I do not use this feature", the second is "not right now".
    if ns.Modules and not ns.Modules:IsOn("deaths") then return end
    if ns.db and ns.db.death and ns.db.death.record == false then return end

    -- The recap needs a moment to exist: capture shortly after the fall,
    -- and once more a little later in case the meter was still writing.
    C_Timer.After(0.8, function()
        local snapshot = Death:Capture()
        local open = not (ns.db and ns.db.death) or ns.db.death.openOnDeath ~= false
        if snapshot.events == nil then
            C_Timer.After(2.0, function()
                -- replace: the same death, asked again once the meter had
                -- time to write - not a second entry in the pager.
                snapshot = Death:Capture(nil, true)
                if open then Death:Show(#Death.log) end
            end)
        elseif open then
            Death:Show(#Death.log)
        end
    end)
end)

TryHookBlizzardRecap()
