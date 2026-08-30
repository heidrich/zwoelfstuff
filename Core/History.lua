---------------------------------------------------------------------------
-- History.lua - what YOU cast, and what that says about what is ready
--
-- The one combat fact this client still hands an addon in full is the
-- player's own casts: UNIT_SPELLCAST_SUCCEEDED fires for "player" with a
-- readable spell id, on 12.0.5 explicitly so ("only for the player itself").
-- Everything else - cooldown remaining, charges, aura time - is a secret or
-- a display-only handle.
--
-- So readiness is ESTIMATED, never read: last cast plus the spell's base
-- cooldown. That is the same philosophy as the recorded procs - our own
-- clock over a value the client withholds - and it is honest about being an
-- estimate: cooldown resets, charges and haste-scaled cooldowns are not in
-- it, and every answer carries its source so a caller can say "about".
--
-- One consumer: the death capture, which asks it what was STILL READY when
-- you died - the question the owner asked for in as many words. There were
-- two until 4.54.0, when the Timeline panel that drew the other strip was
-- taken out; the estimate outlived it because the death window is what the
-- question was always for.
---------------------------------------------------------------------------
local _, ns = ...

local History = {}
ns.History = History

-- spellID -> GetTime() of the last successful cast. A plain map, not a ring:
-- "when did I last press it" is the only question asked, and the newest
-- answer is the only one that matters.
History.last = {}

-- The last N casts in order, for the death window's "what you pressed"
-- column. Capped so an evening of playing does not become a table with ten
-- thousand rows nobody will ever scroll.
History.casts = {}
-- HOW FAR BACK THE PRESS LIST REACHES.
--
-- Fifty was enough for the death log, which only ever reads the last ten
-- seconds of a fall. The combat log reads a WHOLE PULL - owner, 2026-08-29:
-- "wir sollten die liste auch scrollen koennen, von fight start zum ende" -
-- and fifty presses is about six seconds of a rotation, so the log covered
-- the last six seconds of a fourteen-minute session and looked broken.
--
-- Five hundred is roughly eight minutes of one press a second. The cost is a
-- table of two fields per press and one shift-by-one when the cap is reached;
-- nothing walks this list per frame - the cooldown estimate reads a map, and
-- the death log walks it once per fall.
local CASTS_CAP = 500

-- HOW LONG A DEFENSIVE WAS ACTUALLY UP, measured.
--
-- The owner asked for the replay's press bars to run their real length -
-- "man soll visuell sehen wie lange die cds da laufen" - and they were
-- drawing as stubs, because the only source was the number a person can
-- type in on the Auras page and nobody types it in.
--
-- This addon has one rule about durations and it is MEASURED, NEVER
-- ASSUMED. On this patch the aura itself may not be read, so the reading
-- comes from the one place that already knows: Blizzard's Cooldown Manager
-- puts an item frame in its BUFF viewers while a tracked buff is up, and
-- that frame answers IsActive. The window between it going active and
-- going inactive IS the duration - our own clock over a value the client
-- withholds, the same trick the proc recorder plays with the glow events.
--
-- Only the buff viewers are watched, deliberately. An icon in the cooldown
-- viewers is "active" for reasons of its own, and a Shield Wall drawn
-- three minutes long because its COOLDOWN was running would be a confident
-- lie - worse than the stub it replaced.
History.actives = {}
local ACTIVES_CAP = 60

---------------------------------------------------------------------------
-- WHAT WAS ON YOU, AND WHEN
--
-- Owner, 2026-08-31: "oder wann ich debuffs oder so bekommen habe?"
--
-- And THIS one is answerable in full, which almost nothing about incoming
-- damage is. Auras are not the combat log: the client answers them the same
-- way it answers them for every raid frame on screen, so a debuff's id, its
-- icon and its tooltip are all readable. What was missing was only the
-- CLOCK - and the clock is ours to keep.
--
-- ARRIVAL AND DEPARTURE, NOT REFRESHES. A debuff reapplied while it was
-- still on you is the same debuff still on you. A row per refresh would turn
-- one twelve-second curse into six rows and bury the single fact worth
-- having, which is how long you wore it.
---------------------------------------------------------------------------
History.debuffs = {}            -- finished windows: {spellID, from, to}
local DEBUFFS_CAP = 120
History.onYou = {}              -- spellID -> GetTime() it landed

-- Longer than this is not a defensive window, it is a reading that got
-- stuck - a buff that survived a zone change, a frame recycled behind our
-- back. Dropped rather than stored.
local ACTIVE_MAX = 120

---------------------------------------------------------------------------
-- Pure rules, exported for the self test
---------------------------------------------------------------------------

-- Seconds still to wait, or 0 when it is ready, or nil when there is nothing
-- to estimate FROM - never cast, or no known cooldown. nil is deliberately
-- not 0: "I cannot tell" and "it is ready" must stay different answers, or
-- the death window would call every spell it knows nothing about "ready".
function History.Remaining(castAt, baseCD, now)
    if type(castAt) ~= "number" or type(baseCD) ~= "number" or baseCD <= 0 then
        return nil
    end
    local left = (castAt + baseCD) - now
    if left <= 0 then return 0 end
    return left
end

-- Record one cast into both stores. Split out and pure-ish (tables in, no
-- client calls) so the self test can drive it without a client.
function History.Push(last, casts, spellID, at, cap)
    last[spellID] = at
    casts[#casts + 1] = { spellID = spellID, at = at }
    while #casts > (cap or CASTS_CAP) do
        table.remove(casts, 1)
    end
end

-- One finished active window. Nothing shorter than half a second and
-- nothing longer than ACTIVE_MAX: the first is a flicker as a frame is
-- recycled, the second is a reading that never closed.
function History.PushActive(list, spellID, from, to, cap)
    if not (spellID and from and to) then return false end
    local lasted = to - from
    if lasted < 0.5 or lasted > ACTIVE_MAX then return false end
    list[#list + 1] = { spellID = spellID, from = from, to = to }
    while #list > (cap or ACTIVES_CAP) do
        table.remove(list, 1)
    end
    return true
end

-- One finished debuff window, kept the way a buff window is.
--
-- NOTHING SHORTER THAN A FIFTH OF A SECOND: an aura that appears and is gone
-- between two events is a flicker as the client rebuilds a list, not
-- something that happened to you.
function History.PushDebuff(list, spellID, from, to, cap)
    if not (spellID and from and to) then return false end
    if to - from < 0.2 then return false end
    list[#list + 1] = { spellID = spellID, from = from, to = to }
    while #list > (cap or DEBUFFS_CAP) do
        table.remove(list, 1)
    end
    return true
end

-- WHAT WAS ON YOU INSIDE A STRETCH OF TIME, in the shape a pull records and
-- the replay draws: how long before the end it landed, and how long it held.
--
-- THE ONES STILL ON YOU ARE IN IT. A debuff that outlived the fight is
-- exactly the one worth seeing, and dropping it because it never closed
-- would lose it at the moment it mattered most.
--
-- Sorted newest first, on (ago, spellID) - a total order, because `onYou` is
-- walked with pairs and two debuffs that landed in the same instant would
-- otherwise come back in a different order every time.
function History.DebuffsWithin(endedAt, window, list, open)
    local out = {}
    if type(endedAt) ~= "number" then return out end

    local function Add(spellID, from, to, still)
        if not (type(spellID) == "number" and type(from) == "number") then
            return
        end
        local ago = endedAt - from
        if ago < 0 then return end

        -- WHAT IS OUTSIDE THE STRETCH IS WHAT ENDED BEFORE IT BEGAN, and
        -- nothing else.
        --
        -- This used to drop anything that STARTED before the window, which
        -- was harmless while the window was the whole fight and became a
        -- real hole the moment it could be shorter: a curse you wore from
        -- the pull to the wipe starts before any window worth setting, and
        -- the record would say it was never there at all.
        --
        -- Clamped to the edge instead. It WAS on you for the part that is
        -- kept, and a bar across the whole stretch is exactly what happened;
        -- the length below is worked out from the clamped start, so the row
        -- says how long it was on you INSIDE the stretch rather than
        -- claiming a window that reaches off the plot.
        local ended = to or endedAt
        if window and (endedAt - ended) > window then return end
        if window and ago > window then ago = window end

        local held = ago - (endedAt - ended)
        out[#out + 1] = {
            spellID = spellID, ago = ago,
            held = held > 0 and held or nil,
            stillOn = still or nil,
        }
    end

    for _, one in ipairs(list or History.debuffs or {}) do
        Add(one.spellID, one.from, one.to)
    end
    for spellID, from in pairs(open or History.onYou or {}) do
        Add(spellID, from, nil, true)
    end
    table.sort(out, function(a, b)
        if a.ago ~= b.ago then return a.ago < b.ago end
        return a.spellID < b.spellID
    end)
    return out
end

-- WHICH WINDOW BELONGS TO WHICH PRESS.
--
-- A buff that went up a quarter of a second after you pressed the button is
-- that button's buff; one that went up eight seconds earlier is not. The
-- window is generous on the late side (the aura lands after the cast, and
-- a global cooldown of lag is normal) and nearly closed on the early one.
--
-- Returns from, to - with `to` nil when the buff was STILL UP at `now`,
-- which is the case the replay most wants: it means the bar runs all the
-- way to the death rather than stopping at a guess.
local MATCH_EARLY, MATCH_LATE = 0.5, 2.0

function History.WindowFor(list, open, spellID, castAt, family)
    if not (spellID and castAt) then return nil end

    local wanted = { [spellID] = true }
    for _, variant in ipairs(family or {}) do wanted[variant] = true end

    -- Newest first: pressing the same defensive twice inside one fight must
    -- pair each press with its OWN window, not both with the first.
    local best, bestFrom
    for i = #(list or {}), 1, -1 do
        local entry = list[i]
        if wanted[entry.spellID]
            and entry.from >= castAt - MATCH_EARLY
            and entry.from <= castAt + MATCH_LATE
            and (not bestFrom or entry.from > bestFrom) then
            best, bestFrom = entry, entry.from
        end
    end
    if best then return best.from, best.to end

    -- Nothing finished. Is it still running?
    for id in pairs(wanted) do
        local startedAt = open and open[id]
        if startedAt and startedAt >= castAt - MATCH_EARLY
            and startedAt <= castAt + MATCH_LATE then
            return startedAt, nil
        end
    end
    return nil
end

-- The longest window ever measured for a spell on this spec, kept so a
-- death restored from the saved variables - which has no live window
-- behind it - can still draw a bar of a length somebody actually observed.
-- The longest, because a window can be cut short (you died, it was
-- dispelled, the frame was recycled) and never lengthened.
function History.NoteMeasured(store, spellID, seconds)
    if not (store and spellID and seconds) then return end
    if seconds < 0.5 or seconds > ACTIVE_MAX then return end
    local rounded = math.floor(seconds * 10 + 0.5) / 10
    if (store[spellID] or 0) < rounded then store[spellID] = rounded end
end

---------------------------------------------------------------------------
-- Client questions
---------------------------------------------------------------------------

-- Base cooldown in SECONDS, or nil. C_Spell.GetSpellBaseCooldown answers in
-- milliseconds and is the UNhasted value - which is exactly right for an
-- estimate that promises no more than "about". Wrapped in pcall because on
-- this patch any spell question may decide to throw for a secret, and a
-- readiness colour is never worth an error box mid-pull.
function History.BaseCooldown(spellID)
    if not (C_Spell and C_Spell.GetSpellBaseCooldown) then return nil end
    local ok, ms = pcall(C_Spell.GetSpellBaseCooldown, spellID)
    if not ok or type(ms) ~= "number" or ms <= 0 then return nil end
    return ms / 1000
end

-- Seconds until spellID is ready by our own clock: 0 = ready as far as we
-- can tell, nil = cannot tell. Second return says WHY it cannot.
function History:Estimate(spellID, now)
    now = now or GetTime()
    local castAt = self.last[spellID]
    if not castAt then
        -- Never seen it cast: since login it has not been pressed, so unless
        -- the session just started it is very likely ready. Still nil - the
        -- caller words that as "not pressed since login", not as "ready".
        return nil, "not cast since login"
    end
    local baseCD = History.BaseCooldown(spellID)
    if not baseCD then return nil, "no known cooldown" end
    return History.Remaining(castAt, baseCD, now), nil
end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------
local listener = CreateFrame("Frame")
-- pcall, exactly as Auras.lua wraps the same call: the desktop harness's
-- frame stub has RegisterEvent and not the unit-filtered form.
pcall(listener.RegisterUnitEvent, listener, "UNIT_SPELLCAST_SUCCEEDED", "player")
listener:SetScript("OnEvent", function(_, _, unit, _, spellID)
    -- The id of the player's own cast is readable on this patch; guard it
    -- anyway, because a secret reaching a table key is the crash this addon
    -- has already shipped once. CanCompute is asked BEFORE type(), so a
    -- secret is dropped without ever being touched.
    if unit ~= "player" then return end
    if not ns.CanCompute(spellID) then return end
    if type(spellID) ~= "number" then return end
    History.Push(History.last, History.casts, spellID, GetTime())
end)

---------------------------------------------------------------------------
-- The debuff clock
--
-- NO ALLOCATION PER EVENT. UNIT_AURA fires several times a second in a
-- fight and never stops for the rest of the evening. The scratch set is
-- wiped and refilled rather than replaced, the walk hands back numbers
-- rather than tables, and the handler is a named function at file scope so
-- there is no closure per registration either.
---------------------------------------------------------------------------
local onYou = History.onYou
local scratch = {}

-- A CLIENT THAT WILL NOT SAY IS NOT A CLIENT SAYING "NOTHING ON YOU".
-- Closing every open window on a refusal would file a pile of debuffs that
-- all ended in the same instant, which is a picture of something that did
-- not happen. So a refusal changes nothing at all.
-- ONE FUNCTION, NOT ONE PER CALL. This was written inline and a closure is
-- built every time a closure literal is EVALUATED - so this recorder, which
-- runs on every UNIT_AURA, allocated one per event and then dropped it. The
-- owner's rule is about the resting state, and a raid night is mostly
-- resting state.
local function Note(spellID)
    scratch[spellID] = true
end

-- HOW OFTEN THIS MAY ACTUALLY RUN.
--
-- Owner, 2026-08-30: "das frisst zu viel performance."
--
-- UNIT_AURA on the player fires several times a second in a fight and a
-- great many times during one raid pull, and each run walks up to sixty aura
-- slots - each of which hands back a fresh table. Sixty tables per event,
-- for ever, is the shape of cost that never appears in a screenshot.
--
-- THE FLOOR AND THE THROTTLE ARE THE SAME NUMBER, and that is the whole
-- argument for it: PushDebuff already refuses a window shorter than this as
-- a flicker, so nothing this skips could have been KEPT. A throttle chosen
-- for comfort would be a guess about what is worth losing; this one cannot
-- lose anything.
local SWEEP_EVERY = 0.2
local sweptAt = 0

local function SweepDebuffs(force)
    if not ns.EachOwnAura then return false end
    local at = GetTime and GetTime() or 0
    if not force and at - sweptAt < SWEEP_EVERY then return false end
    sweptAt = at
    for id in pairs(scratch) do scratch[id] = nil end
    local read = ns.EachOwnAura("player", "HARMFUL", Note)
    if not read then return false end

    local now = GetTime and GetTime() or 0
    for spellID in pairs(scratch) do
        if onYou[spellID] == nil then onYou[spellID] = now end
    end
    -- Clearing the key the loop is standing on is allowed and is the whole
    -- reason this is one pass rather than a list of ids to delete after.
    for spellID, from in pairs(onYou) do
        if not scratch[spellID] then
            onYou[spellID] = nil
            History.PushDebuff(History.debuffs, spellID, from, now)
        end
    end
    return true
end

-- EXPORTED, because a handler nobody can call is a loop nobody runs. The
-- health sampler in CombatLog shipped un-run for exactly this reason and the
-- owner found it by looking at an empty bar.
History.SweepDebuffs = SweepDebuffs

-- AND ONLY WHILE THERE IS A FIGHT TO RECORD IT FOR.
--
-- This clock exists for one reader: the combat log's recorder, which copies
-- it when combat drops. Out of combat there is nothing to copy it into, and
-- UNIT_AURA fires all day in a city, on a flight path, standing in Dornogal.
-- Switching the combat log off stops it entirely.
--
-- ONE MORE SWEEP AT THE START OF A FIGHT, forced past the throttle: what you
-- walked in wearing is part of the fight, and waiting for the next aura event
-- would file it at whatever second that happened to be.
local recording = false
local auras = CreateFrame("Frame")
-- pcall for the same reason the cast listener uses one: the desk's frame
-- stub has RegisterEvent and not the unit-filtered form.
pcall(auras.RegisterUnitEvent, auras, "UNIT_AURA", "player")
pcall(auras.RegisterEvent, auras, "PLAYER_REGEN_DISABLED")
pcall(auras.RegisterEvent, auras, "PLAYER_REGEN_ENABLED")
auras:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_REGEN_DISABLED" then
        if ns.Modules and not ns.Modules:IsOn("combatlog") then return end
        -- FROM EMPTY. What is still open belongs to the pull before this
        -- one, and the recorder has already taken its copy of that.
        --
        -- Done HERE rather than when combat drops, on purpose: the recorder
        -- reads this store on PLAYER_REGEN_ENABLED and two frames' handlers
        -- have no order between them. Clearing at the START cannot race it.
        for id in pairs(onYou) do onYou[id] = nil end
        recording = true
        SweepDebuffs(true)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        recording = false
        return
    end
    if not recording then return end
    if unit ~= nil and unit ~= "player" then return end
    SweepDebuffs()
end)

---------------------------------------------------------------------------
-- Watching the buff viewers
--
-- Ten frames a second over the handful of item frames Blizzard's buff
-- viewers have active. It is a poll and not an event because there is no
-- event: the viewers refresh themselves and say nothing to anybody.
---------------------------------------------------------------------------
local openSince = {}     -- spellID -> GetTime() it went active
History.openActives = openSince

local POLL = 0.1
local since = 0

-- Where the measured lengths live: per spec, because a talent changes them
-- and a reading taken as Protection means nothing as Fury.
function History:Measured()
    if not ns.account then return {} end
    ns.account.activeMeasured = ns.account.activeMeasured or {}
    local key = ns.SpecKey and ns.SpecKey() or "?"
    ns.account.activeMeasured[key] = ns.account.activeMeasured[key] or {}
    return ns.account.activeMeasured[key]
end

-- Seconds, or nil. Variant-aware for the same reason every other lookup in
-- this addon is: a talent that replaces a spell changes the id it reports.
function History:MeasuredFor(spellID)
    if not (spellID and ns.CanCompute(spellID)) then return nil end
    local store = self:Measured()
    if store[spellID] then return store[spellID] end
    if ns.CDM and ns.CDM.VariantFamily then
        for _, variant in ipairs(ns.CDM:VariantFamily(spellID)) do
            if store[variant] then return store[variant] end
        end
    end
    return nil
end

-- The window that belongs to one press, in client terms.
function History:ActiveWindow(spellID, castAt)
    local family = (ns.CDM and ns.CDM.VariantFamily)
        and ns.CDM:VariantFamily(spellID) or nil
    return History.WindowFor(History.actives, openSince, spellID, castAt, family)
end

-- EVERY PART OF THE SWEEP THAT IS NOT THE SWEEP, MADE ONCE.
--
-- This is the most unconditional loop in the addon: it is armed at file scope,
-- so it runs ten times a second from login for the rest of the session, with no
-- window open, no bar on screen and nothing switched on. It used to build a
-- fresh `seen` table, a fresh two-word list to walk and a fresh closure per
-- viewer on every single one of those - forty objects a second, for ever.
--
-- The two viewer keys are a constant. `seen` is emptied at the top of each
-- sweep rather than replaced; it only ever holds spell ids, which are numbers,
-- so nothing is pinned by keeping it. And the body is a named function at file
-- scope, which is what takes the closure out - the one thing it needed from the
-- outside was the timestamp, and that is a file-local written the line before.
--
-- Same shape as the mirror's `pcall(function() ... end)` and the fill ticker's
-- two lists: invisible in one tick, endless over an evening.
local BUFF_VIEWERS = { "buffIcon", "buffBar" }
local seen = {}
local sweepNow = 0

local function NoteActive(item)
    local spellID = ns.CDM:ItemSpellID(item)
    -- A secret id never reaches a table key: that is the crash this addon has
    -- already shipped once.
    if not (spellID and ns.CanCompute(spellID)
        and type(spellID) == "number") then
        return
    end
    if ns.CDM:ItemIsActive(item) then
        seen[spellID] = true
        if not openSince[spellID] then openSince[spellID] = sweepNow end
    end
end

-- EXPORTED for the same reason Effects.Step and Fill.Tick are: the desk does
-- not dispatch OnUpdate, so a local one is a loop no check can walk even once -
-- and this is the loop that runs the longest of any in the addon.
function History.Sweep()
    if not (ns.CDM and ns.CDM.ForEachItem) then return end
    local now = GetTime()
    sweepNow = now
    wipe(seen)

    for _, key in ipairs(BUFF_VIEWERS) do
        pcall(ns.CDM.ForEachItem, ns.CDM, key, NoteActive)
    end

    -- Anything that was up and is not any more closed its window.
    for spellID, from in pairs(openSince) do
        if not seen[spellID] then
            openSince[spellID] = nil
            if History.PushActive(History.actives, spellID, from, now) then
                History.NoteMeasured(History:Measured(), spellID, now - from)
            end
        end
    end
end

listener:SetScript("OnUpdate", function(_, elapsed)
    since = since + (elapsed or 0)
    if since < POLL then return end
    since = 0
    History.Sweep()
end)

---------------------------------------------------------------------------
-- WHY IS THERE NO BAR - the diagnostic, and it reports the SWITCH first
--
-- The owner looked at a replay with no bars under the presses and could not
-- tell why, and neither could I from a screenshot. There are four different
-- reasons for the same symptom and only the client can say which:
--
--   1. the Cooldown Manager is not up at all
--   2. its BUFF viewers have no items - nothing to watch, so no window is
--      ever recorded, and nothing will change however long they play
--   3. the items are there but their spell ids are secret
--   4. everything works and the death they are looking at is simply OLDER than
--      this recorder, so it carries no windows and never will
--
-- Four causes, one symptom - that is the case that has cost this project
-- the most time, and the rule from it is: build the diagnostic instead of
-- reading the code again. /zs death cds.
---------------------------------------------------------------------------
function History:Dump()
    ns.Print("|cffffd100defensive durations|r - where the bars come from.")

    -- THE SWITCH FIRST, and then everything else anyway. A diagnostic that
    -- stops at the first thing it finds wrong prints one line and leaves
    -- the other three questions unanswered - and on a desktop, where there
    -- is no Cooldown Manager at all, it would never exercise its own body.
    local up = ns.CDM and ns.CDM.IsAvailable and ns.CDM:IsAvailable()
    if not up then
        ns.Print("  |cffff4040The Cooldown Manager is not up|r: "
            .. ((ns.CDM and ns.CDM:UnavailableReason()) or "no CDM module")
            .. ". Nothing new can be measured until it is.")
    else
        -- The buff viewers ARE the source. If they hold nothing, no amount
        -- of playing will ever produce a window, and that is worth knowing
        -- at once rather than after an evening.
        local watched = 0
        for _, key in ipairs({ "buffIcon", "buffBar" }) do
            local shown, secret, active = 0, 0, 0
            pcall(ns.CDM.ForEachItem, ns.CDM, key, function(item)
                shown = shown + 1
                local spellID = ns.CDM:ItemSpellID(item)
                if not (spellID and ns.CanCompute(spellID)) then
                    secret = secret + 1
                elseif ns.CDM:ItemIsActive(item) then
                    active = active + 1
                end
            end)
            watched = watched + shown
            ns.Print(string.format("  %s: |cff40ff40%d|r tracked, %d up now%s",
                key, shown, active,
                secret > 0
                    and (", |cffff8040" .. secret .. " with a secret id|r")
                    or ""))
        end
        if watched == 0 then
            ns.Print("  |cffff8040Both buff viewers are empty.|r Switch the "
                .. "buff section on in Edit Mode, or no defensive window can "
                .. "be measured.")
        end
    end

    local windows = History.actives
    ns.Print(string.format("  windows recorded this session: |cff40ff40%d|r",
        #windows))
    for i = math.max(1, #windows - 5), #windows do
        local entry = windows[i]
        ns.Print(string.format("    %s  |cff9ba3af%.1fs|r",
            ns.SpellName(entry.spellID) or ("Spell " .. entry.spellID),
            entry.to - entry.from))
    end

    local open = 0
    for spellID in pairs(openSince) do
        open = open + 1
        ns.Print("    up RIGHT NOW: "
            .. (ns.SpellName(spellID) or ("Spell " .. spellID)))
    end
    if open == 0 and #windows == 0 then
        ns.Print("    |cff888888Nothing yet. Press a defensive and wait for "
            .. "it to fall off, then run this again.|r")
    end

    local store, count = self:Measured(), 0
    for spellID, seconds in pairs(store) do
        count = count + 1
        ns.Print(string.format("    measured: %s = |cff40ff40%.1fs|r",
            ns.SpellName(spellID) or ("Spell " .. spellID), seconds))
    end
    if count == 0 then
        ns.Print("    |cff888888No lengths measured on this spec yet.|r")
    end

    -- And the death actually on screen, which is the other half: a death
    -- captured before this recorder existed carries no windows and cannot
    -- be given any afterwards.
    local snapshot = ns.Death and ns.Death.log
        and ns.Death.log[ns.Death.showing or #ns.Death.log]
    if not (snapshot and snapshot.casts) then
        ns.Print("  No death on screen to check against.")
        return
    end
    ns.Print("  the death on screen, press by press:")
    for _, cast in ipairs(snapshot.casts) do
        local length, source
        if ns.Replay then length, source = ns.Replay.BarLength(cast) end
        ns.Print(string.format("    %s: %s", cast.name or "?",
            length and string.format("|cff40ff40%.1fs|r (%s)", length,
                source or "?")
                or "|cffff8040no length - draws as a mark|r"))
    end
end
