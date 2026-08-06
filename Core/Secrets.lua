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

-- Equality that never raises: two values only count as equal when both are
-- readable. Unreadable input reports "unknown" rather than guessing.
function ns.SameValue(a, b)
    if not ns.CanCompute(a) or not ns.CanCompute(b) then
        return nil
    end
    return a == b
end
