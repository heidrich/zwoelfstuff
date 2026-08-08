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
