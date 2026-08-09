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
-- Two consumers, one recorder: the Timeline panel colours its defensive
-- strip with it, and the death capture asks it what was STILL READY when
-- you died - the question the owner asked for in as many words.
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
local CASTS_CAP = 50

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

local function Sweep()
    if not (ns.CDM and ns.CDM.ForEachItem) then return end
    local now = GetTime()
    local seen = {}

    for _, key in ipairs({ "buffIcon", "buffBar" }) do
        pcall(ns.CDM.ForEachItem, ns.CDM, key, function(item)
            local spellID = ns.CDM:ItemSpellID(item)
            -- A secret id never reaches a table key: that is the crash this
            -- addon has already shipped once.
            if not (spellID and ns.CanCompute(spellID)
                and type(spellID) == "number") then
                return
            end
            if ns.CDM:ItemIsActive(item) then
                seen[spellID] = true
                if not openSince[spellID] then openSince[spellID] = now end
            end
        end)
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
    Sweep()
end)
