---------------------------------------------------------------------------
-- The frame contract, and the one table that keeps it.
--
-- THE FIRST FILE OF THE REBUILT COOLDOWN MANAGER, and it holds a rule rather
-- than a feature. That is on purpose: the implementation this replaces grew
-- self-healing anchor hooks and a "rival check", and both of those were
-- symptoms of a contract nobody had written down.
--
-- FIVE RULES. Blizzard's Cooldown Manager owns its frames; we mirror and
-- adopt, we never own the state.
--
--   1. Never SetParent, SetScale, Hide or Show a Blizzard frame.
--   2. Never move one off screen to get rid of it.
--   3. Never write one of our keys onto a Blizzard frame's table.
--   4. Unclaimed frames get SetAlpha(0), claimed ones SetAlpha(1). Nothing
--      in between and nothing else.
--   5. Edit Mode settings are enforced ONCE at init, never at runtime - a
--      reapply from addon code triggers SaveLayouts, which taints Blizzard
--      frame properties for the rest of the session.
--
-- Rules 1, 2, 4 and 5 are about what we call. Rule 3 is about where we put
-- things, and it is the only one that needs code, because the natural way to
-- remember "this icon belongs to cell 4" is to write `frame.zsCell = 4` and
-- that is precisely the violation. So the memory lives HERE, keyed BY the
-- frame, and the frame never learns about us.
--
-- Weak keys, and that is load-bearing rather than tidy: Blizzard's viewers
-- recycle item frames through a pool across spec changes and reloads. A
-- strong table would hold every frame the session ever saw and hand back a
-- stale record for a frame that has since been re-issued to a different
-- spell - the exact bug the old implementation had a "rival check" for.
--
-- Enforced from outside by two desk guards, which read this source and fail
-- the build. A rule that is only a comment is a rule with one bad afternoon
-- between it and being broken.
---------------------------------------------------------------------------
local _, ns = ...

local Cooldowns = {}
ns.Cooldowns = Cooldowns

---------------------------------------------------------------------------
-- What we remember about somebody else's frame
---------------------------------------------------------------------------

-- __mode = "k": when Blizzard drops a frame, its record goes with it.
local records = setmetatable({}, { __mode = "k" })

-- Our note about this frame, created on first ask.
--
-- Returns nil for a nil frame rather than raising, because every caller
-- reaches this by way of a viewer that may not exist on this client - CDM.lua
-- answers "unavailable" for a whole client generation and every reader is
-- written to survive that.
function Cooldowns.Record(frame)
    if frame == nil then return nil end
    local record = records[frame]
    if not record then
        record = {}
        records[frame] = record
    end
    return record
end

-- What we know already, without inventing a record for a frame we have never
-- touched. The read that answers "is this one ours".
function Cooldowns.Known(frame)
    if frame == nil then return nil end
    return records[frame]
end

-- Give a frame back. Releasing is OUR bookkeeping only: whatever was actually
-- changed on the frame is put back by the caller BEFORE this is called, and
-- this line is what stops the record outliving the claim.
function Cooldowns.Forget(frame)
    if frame == nil then return end
    records[frame] = nil
end

-- How many frames we are currently holding a note about. For the self test
-- and for /zs cdm - a number that climbs across reloads is rule 3 leaking
-- somewhere else, or the pool handing out frames we never gave back.
function Cooldowns.Held()
    local count = 0
    for _ in pairs(records) do count = count + 1 end
    return count
end
