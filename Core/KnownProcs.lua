---------------------------------------------------------------------------
-- KnownProcs - the spell database that ships with the addon.
--
-- WHAT THIS IS.
--
-- Some auras are invisible to addons on patch 12.0: aura fields are secret
-- values, so a buff cannot be identified by ID, name or icon, and the ones
-- outside Blizzard's Cooldown Manager data set have no frame to borrow
-- either. What IS readable is the glow on the ability the aura empowers.
--
-- So each entry answers one question: "when THIS spell's button lights up,
-- which buff is running, what should it look like, and how long does it
-- last?" There is no API that answers it. It has to be observed once.
--
--   [class:specID] = {
--       [spellID that lights up] = {
--           display  = spellID,   the icon and name to show - a CHOICE
--           auraID   = spellID,   the buff itself - drives the 12.1 route
--           duration = seconds,   MEASURED, never assumed
--       },
--   }
--
-- WHY IT SHIPS, AND WHY IT IS SAFE TO SHIP.
--
-- A glow set belongs to a class and a spec, not to a player. Blood Death
-- Knights all have the same procs. So one person playing one spec once is
-- enough for everybody who plays it - the recording goes in here and every
-- installation gets it on the next update, with nothing to configure.
--
-- HOW TO ADD TO IT.
--
--   1. Play the spec. Every proc raises itself into the list, per class and
--      spec, with no learn mode and nothing to press.
--   2. Let each proc run out ON ITS OWN at least once, without casting the
--      ability - that is the only reading that measures the real duration.
--      Until then the number is a floor, shown orange with a >.
--   3. /zs auras export, and paste the block in here.
--
-- WHAT MUST NOT HAPPEN.
--
-- Nothing in this file may be written from memory or from a database site.
-- Two wrong spell IDs have already cost this project a day. Every line here
-- was observed on a live character, and the comment says by whom and when.
--
-- A user's own recordings always win over what is written here, so a wrong
-- entry costs one wrong caption until it is corrected, never a broken bar.
-- /zs auras forget <glowID> hides one of these for good on that account.
---------------------------------------------------------------------------
local _, ns = ...

ns.KNOWN_PROCS = {
    -- Blood Death Knight. Boiling Point empowers Blood Boil; observed on
    -- Zwölf, EU Destromath, 2026-08-05. The aura and the icon are the same
    -- spell here, which is common but not guaranteed.
    ["DEATHKNIGHT:250"] = {
        [50842] = { display = 1265968, auraID = 1265968, duration = 15 },
    },
}
