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
