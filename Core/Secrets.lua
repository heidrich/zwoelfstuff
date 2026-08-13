---------------------------------------------------------------------------
-- Secret-value discipline (patch 12.0+).
--
-- Since 12.0.0 aura fields arrive as "secret values". Tainted code - which
-- every addon is - may NOT:
--   * use them as table keys        (this is what broke ZwoelfStuff 1.0.0)
--   * compare them or boolean-test them
--   * do arithmetic on them, or take their length
--
-- It MAY store them, pass them on, and hand them to the few widget setters
-- that declare secret arguments. Since 12.0.1 cooldown frames accept secret
-- timing only through SetCooldownFromDurationObject.
--
-- The rule this addon follows: never read a secret at all. Everything is
-- driven by spell IDs we own, and by engine-side accessors that take an
-- auraInstanceID and render the result themselves.
---------------------------------------------------------------------------
local _, ns = ...

-- The fallback keeps the parameter so callers type-check on older clients.
local issecret = issecretvalue or function(_) return false end

-- True when a value is present and Lua logic on it is allowed.
function ns.CanCompute(value)
    return value ~= nil and not issecret(value)
end

-- True when a value may be handed to a font string's SetFormattedText.
--
-- THE ONE PLACE A SECRET IS ALLOWED THROUGH. SetFormattedText declares a
-- secret argument: the engine formats the number and draws it, and addon Lua
-- never sees it. That is how a live charge count can be displayed at all on
-- this patch - `currentCharges` is secret in combat, so every other route
-- (comparing it, concatenating it, .. it into a string) raises.
--
-- Read off EllesmereUICdmBuffBars.lua:4577-4584, which says so in as many
-- words: "the text setter accepts a SECRET live count".
--
-- Deliberately NOT ns.CanCompute: this returns true for exactly the values
-- CanCompute rejects. Anything that passes here may be printed and nothing
-- else - no arithmetic, no comparison, not even a boolean test.
function ns.CanDisplay(value)
    if issecret(value) then return true end
    return type(value) == "number"
end

-- Equality that never raises: two values only count as equal when both are
-- readable. Unreadable input reports "unknown" rather than guessing.
function ns.SameValue(a, b)
    if not ns.CanCompute(a) or not ns.CanCompute(b) then
        return nil
    end
    return a == b
end

---------------------------------------------------------------------------
-- WHAT THIS CLIENT WILL ACTUALLY NAME, right now
--
-- "Auras are secret" is true in the place it matters and not everywhere:
-- WHERE YOU ARE STANDING DECIDES IT. Inside restricted content - a dungeon,
-- a raid - the client withholds them; out in the world it frequently does
-- not. EllesmereUI documents the same edge from the other side, on a buff
-- that was moved onto the withheld list in build 68824: its own read
-- "returns nothing for it in restricted content".
--
-- So this answers for the moment it is asked and never caches. Two callers
-- with one enumeration between them, because two loops over the same sixty
-- slots would be two places to get the guard wrong:
--
--   RaidCheck   which helpful buffs are on me, to report to the group
--   Auras       which buff came and went with a proc's glow
--
-- nil means "the client is not saying", which is a THIRD answer and not an
-- empty list - an empty list would read as "no buffs".
---------------------------------------------------------------------------
function ns.AurasReadable()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldAurasBeSecret)
        if ok and secret then return false end
    end
    return C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and true or false
end

-- ids, icons - both as sets, both nil when the client is withholding.
function ns.OwnAuras(unit, filter)
    if not ns.AurasReadable() then return nil, nil end

    local ids, icons = {}, {}
    for index = 1, 60 do
        -- A secret one is SKIPPED rather than guarded around: reading it is
        -- the thing that raises, and there is nothing to do with it anyway.
        local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex,
            unit or "player", index, filter or "HELPFUL")
        if not ok or not data then break end
        if ns.CanCompute(data.spellId) then ids[data.spellId] = true end
        if ns.CanCompute(data.icon) then icons[data.icon] = true end
    end
    return ids, icons
end
