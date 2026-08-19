---------------------------------------------------------------------------
-- CASTS ON YOU - what the mob in front of you is casting, and at whom.
--
-- WHAT THIS PATCH ALLOWS, AND WHAT IT DOES NOT. Since 12.0 the spell a
-- hostile unit is casting arrives as a SECRET VALUE: the id, the name and
-- the icon may be handed to a widget setter, which is why every nameplate in
-- the game still draws the cast - and may NOT be compared, looked up in a
-- table or used as a key. So this module can never say "Shield Slam is
-- coming"; nothing on this patch can. LittleWigs' own Midnight trash module
-- says so in as many words - `SecretMessage(key, color, spellId)`, "the
-- secret spellId from which the icon and text are derived" - and its 33-38
-- named trash warnings per War Within dungeon are ZERO for Midnight, replaced
-- by one generic "a mob is casting" split by mob rank. BigWigs identifies
-- boss abilities by the ROUNDED DURATION of Blizzard's timeline event;
-- EXBoss keeps a hand-kept duration table per boss and an inference engine
-- for trash. Both are guesses that drift with every hotfix, and neither is
-- something a tank needs to be told.
--
-- WHAT A TANK ACTUALLY NEEDS is the other half, and every part of it is
-- readable in plain Lua:
--
--   * that a cast is happening       UnitCastingInfo / UnitChannelInfo
--   * how far along it is            UnitCastingDuration (a duration object,
--                                    handed to the bar, never read)
--   * how dangerous the caster is    UnitLevel: standard / lieutenant / boss
--   * whether it can be kicked       notInterruptible - SECRET, and drawn by
--                                     SetVertexColorFromBoolean
--   * whether it has a target at all UnitShouldDisplaySpellTargetName, plain
--   * WHETHER IT IS AIMED AT YOU     PlayerIsSpellTarget - SECRET, and drawn
--                                     by SetAlphaFromBoolean
--   * roughly who else               the target's role and class, WHEN the
--                                     game hands them over - see Aim() below
--
-- THE TWO HALVES OF "AT YOU", and they must not be confused. The engine
-- knows and will DRAW it: PlayerIsSpellTarget(unit) hands back a secret
-- boolean that SetAlphaFromBoolean turns into a mark on the bar, which is
-- exactly how EXBoss marks its own (Modules/Tools/MythicCast.lua:844). Lua
-- may never TEST it. So the bar can say "ON YOU" with certainty while a
-- rule cannot be written on it.
--
-- What a rule can use is the best-effort read EXBoss also keeps
-- (Modules/Tools/TargetIdentityState.lua:199-213): the mob's target unit is
-- asked for `UnitGroupRolesAssigned` and `UnitClass`, and "tank:WARRIOR"
-- names a party member whenever that pair is unique in the group. Inside an
-- instance those can be withheld too, so both go through ns.CanCompute and a
-- withheld answer becomes `unknown` - its own state, never rounded into
-- "nobody" and never into "you".
---------------------------------------------------------------------------
local _, ns = ...

local Casts = {}
ns.Casts = Casts

-- How many nameplates the client will ever hand out.
local MAX_PLATES = 40

-- THE TOKENS, BUILT ONCE. `"nameplate" .. index` inside the scan is a fresh
-- string forty times a walk and the walk runs ten times a second - four
-- hundred strings a second, for ever, while nothing is happening. Owner's
-- rule: what counts is the RESTING state, and garbage per frame never stops.
-- Same for the target token, which is the other half of the same sentence.
local PLATE_UNITS, PLATE_TARGETS = {}, {}
for index = 1, MAX_PLATES do
    PLATE_UNITS[index] = "nameplate" .. index
    PLATE_TARGETS[index] = "nameplate" .. index .. "target"
end

-- Mob ranks, by level, on this expansion. LittleWigs names the same three
-- (LittleWigs/Midnight/Trash.lua: `STANDARD_LEVEL, LIEUTENANT_LEVEL,
-- BOSS_LEVEL = 90, 91, 92`) and reads them off UnitLevel exactly like this.
-- Levels are numbers, never secret.
local STANDARD_LEVEL, LIEUTENANT_LEVEL, BOSS_LEVEL = 90, 91, 92

Casts.RANKS = {
    { key = "standard",   text = "Ordinary mobs",
      note = "The rank-and-file of a pull." },
    { key = "lieutenant", text = "Lieutenants",
      note = "The named ones between bosses." },
    { key = "boss",       text = "Bosses",
      note = "Dungeon and raid bosses." },
}

-- WHO A CAST IS AIMED AT, as far as this patch will say - and the fifth one
-- is the honest one. On 12.x the cast target's name and class are secret
-- ALWAYS (UnitSpellTargetName/UnitSpellTargetClass are SecretReturns), and
-- the target unit's role and class are withheld inside instances. So "who"
-- has three readable answers, one measured-unknown, and one nobody:
--
--   me / tank / group   the group could be told apart this time
--   unknown             something is targeted and the game would not say who
--   nobody              the caster has no target at all (plainly readable)
--
-- `unknown` is a state of its own and never rounded into `nobody` or into
-- `me`: a warning you did not get because a value was withheld is the worst
-- of the three outcomes, so the default alert below fires on it.
--
-- ON YOU is still ANSWERED - just not to Lua. PlayerIsSpellTarget(unit)
-- returns a secret boolean that SetAlphaFromBoolean draws, which is how
-- EXBoss marks its own bars (Modules/Tools/MythicCast.lua:844). The bar
-- shows it; no rule may branch on it.
Casts.AIMS = {
    { key = "me",      text = "At you" },
    { key = "tank",    text = "At another tank" },
    { key = "group",   text = "At somebody else" },
    { key = "unknown", text = "At somebody the game will not name" },
    { key = "nobody",  text = "At nothing in particular" },
}

local RANK_BY_LEVEL = {
    [STANDARD_LEVEL]   = "standard",
    [LIEUTENANT_LEVEL] = "lieutenant",
    [BOSS_LEVEL]       = "boss",
}

-- Dangerous first, wherever a list of ranks is sorted.
local RANK_ORDER = { standard = 1, lieutenant = 2, boss = 3 }

---------------------------------------------------------------------------
-- Pure rules. Everything here is a function of its arguments, so the self
-- test can ask it the questions the client cannot be asked at a desk.
---------------------------------------------------------------------------
local Rules = {}
Casts.Rules = Rules
ns.CastRules = Rules

-- LEVEL -> RANK, and anything else is a rank of its own rather than a
-- silent "standard": a level this expansion does not use is a mob we know
-- nothing about, and calling it ordinary is the display guessing.
function Rules.Rank(level)
    if not ns.CanCompute(level) or type(level) ~= "number" then return nil end
    if level < 0 then return "boss" end          -- -1 is the client's "??"
    return RANK_BY_LEVEL[level]
end

-- ROLE + CLASS -> the identity string a party member is matched on. Both
-- halves are readable on this patch; either missing means "cannot tell",
-- which must never be rounded into a match.
function Rules.Identity(role, classFile)
    if type(role) ~= "string" or role == "" then return nil end
    if type(classFile) ~= "string" or classFile == "" then return nil end
    return role:upper() .. ":" .. classFile:upper()
end

-- THE ROSTER, FOLDED BY IDENTITY. An identity two people share cannot name
-- either of them, so it is dropped rather than resolved to the first one -
-- "the warrior tank" is a person only while there is one.
--
-- `members` is a list of { unit, role, class, isPlayer } (ns.Roster()'s
-- shape). Returns unique = { [identity] = member }, duplicates = { [id] }.
function Rules.Fold(members)
    local unique, duplicates = {}, {}
    for _, member in ipairs(members or {}) do
        local identity = Rules.Identity(member.role, member.class)
        if identity then
            if duplicates[identity] then
                -- already known to be shared
            elseif unique[identity] then
                unique[identity] = nil
                duplicates[identity] = true
            else
                unique[identity] = member
            end
        end
    end
    return unique, duplicates
end

-- WHAT A CAST IS AIMED AT, given the folded roster and the target's role and
-- class. `hasTarget` is the plain boolean the game does answer (UnitExists on the
-- target token, or UnitShouldDisplaySpellTargetName): with a target present
-- and no readable identity the answer is `unknown`, not `nobody`.
function Rules.Aim(unique, role, classFile, playerIdentity, hasTarget)
    local identity = Rules.Identity(role, classFile)
    if not identity then
        return hasTarget and "unknown" or "nobody"
    end
    local member = unique and unique[identity]
    if not member then
        -- A pair two people share, or somebody outside the group: the cast
        -- has a target we cannot name.
        return "unknown"
    end
    if playerIdentity and identity == playerIdentity then return "me" end
    if member.isPlayer then return "me" end
    if (role or ""):upper() == "TANK" then return "tank" end
    return "group"
end

-- DOES THIS CAST GET A LINE, given a config and what we found out. The
-- config's ranks and aims are sets: an absent set means "everything", the
-- same convention ns.Visibility uses for its places.
function Rules.Wanted(cfg, rank, aim)
    if type(cfg) ~= "table" then return false end
    if rank == nil then return false end
    local ranks = cfg.ranks
    if type(ranks) == "table" and not ranks[rank] then return false end
    local aims = cfg.aims
    if type(aims) == "table" and not aims[aim or "nobody"] then return false end
    return true
end

-- AND THE ONE FILTER THAT CAN NAME SOMETHING. The spell is secret; the
-- CASTER is not - UnitName reads mobs fine on this patch, measured and
-- written down at the top of Core/Taunts.lua. So "only these mobs" is a
-- filter this addon may actually offer, and it is what the right-hand column
-- of the page fills in.
--
-- An empty or absent set means every mob, never none: a list nobody has
-- filled in yet must not silence the alert it belongs to.
function Rules.MobWanted(mobs, mob)
    if type(mobs) ~= "table" then return true end
    if next(mobs) == nil then return true end
    if type(mob) ~= "string" or mob == "" then return false end
    return mobs[mob] == true
end

-- THE WORDS. Three tokens, and every one of them is something we may read:
--   %rank   ordinary mob / lieutenant / boss
--   %who    you / a tank / the group / nobody
--   %mob    the caster's name (UnitName is readable for mobs on 12.x -
--           measured, see Core/Taunts.lua)
-- The spell's NAME is deliberately not a token: it is secret, and a token
-- that silently prints nothing is worse than no token.
local RANK_WORDS = {
    standard   = "A mob",
    lieutenant = "A lieutenant",
    boss       = "The boss",
}

local AIM_WORDS = {
    me      = "you",
    tank    = "your co-tank",
    group   = "the group",
    unknown = "somebody",
    nobody  = "nobody in particular",
}

function Rules.Words(text, rank, aim, mob)
    local out = type(text) == "string" and text or ""
    out = out:gsub("%%rank", RANK_WORDS[rank or ""] or "Something")
    out = out:gsub("%%who", AIM_WORDS[aim or "nobody"] or "somebody")
    out = out:gsub("%%mob", (type(mob) == "string" and mob ~= "" and mob)
        or "something")
    return out
end

---------------------------------------------------------------------------
-- Reading the client. Everything below this line touches the API; the desk
-- reaches it through the same doors the client does, which is why each one
-- is its own small function.
---------------------------------------------------------------------------

-- THE CAST ON A UNIT, or nil. Returns a table of carried values, and nearly
-- every one of them is SECRET on this patch: name, texture, spellID and
-- notInterruptible are all withheld for anybody but you and your pet
-- (Blizzard's own docs tag them SecretWhenUnitSpellCastRestricted). They are
-- carried and handed to setters, never inspected; `type(x) ~= "nil"` is the
-- one question Lua may ask of a secret.
--
-- The return ORDER differs between the two calls, which is a real trap:
-- UnitCastingInfo has notInterruptible 8th, UnitChannelInfo 7th. Read off
-- EXBoss/Modules/Tools/MythicCast.lua:1091-1096.
-- ONE TABLE, HANDED BACK EVERY TIME. The caller copies what it wants into
-- its pooled row before the next call, which is the only contract this has:
-- a fresh table per plate per tick is forty a walk and four hundred a second.
local castScratch = {}

local function CastOn(unit)
    if type(UnitCastingInfo) ~= "function" then return nil end
    local name, _, texture, _, _, _, _, notInterruptible, spellID =
        UnitCastingInfo(unit)
    if type(name) ~= "nil" then
        castScratch.name, castScratch.texture = name, texture
        castScratch.isChannel = false
        castScratch.notInterruptible, castScratch.spellID =
            notInterruptible, spellID
        return castScratch
    end
    if type(UnitChannelInfo) ~= "function" then return nil end
    local cname, _, ctexture, _, _, _, cnotInt, cspellID =
        UnitChannelInfo(unit)
    if type(cname) ~= "nil" then
        castScratch.name, castScratch.texture = cname, ctexture
        castScratch.isChannel = true
        castScratch.notInterruptible, castScratch.spellID = cnotInt, cspellID
        return castScratch
    end
    return nil
end

-- HOW LONG IT RUNS, as the engine's own duration object. It is handed
-- straight to a cooldown frame (SetCooldownFromDurationObject) and never
-- read - on this patch the start and end times are secret and arithmetic on
-- them raises, which is what the whole 12.0 wave taught this addon.
local function DurationOn(unit, isChannel)
    if isChannel then
        if type(UnitChannelDuration) == "function" then
            return UnitChannelDuration(unit)
        end
        return nil
    end
    if type(UnitCastingDuration) == "function" then
        return UnitCastingDuration(unit)
    end
    return nil
end

-- IS THE GAME ITSELF CALLING THIS SPELL IMPORTANT. The answer is a secret
-- boolean: it may be given to SetAlphaFromBoolean, which is how EllesmereUI
-- draws its important-cast glow, and it may not be tested. Returns the raw
-- value or nil.
function Casts.Important(spellID)
    if not (C_Spell and C_Spell.IsSpellImportant) then return nil end
    local ok, important = pcall(C_Spell.IsSpellImportant, spellID or 0)
    if not ok then return nil end
    return important
end

-- IS THIS CAST AIMED AT YOU. The engine's own answer, and it is a SECRET
-- boolean: it may be handed to SetAlphaFromBoolean and to nothing else.
-- EXBoss marks its bars with exactly this (MythicCast.lua:844). Returns the
-- raw value or nil when the API is not there.
function Casts.AtMe(unit)
    if type(PlayerIsSpellTarget) ~= "function" then return nil end
    local ok, value = pcall(PlayerIsSpellTarget, unit)
    if not ok then return nil end
    return value
end

-- DOES THIS CAST HAVE A TARGET AT ALL. Plain and branchable - Blizzard's own
-- casting bar branches on it, and so does EXBoss (MythicCast.lua:1115).
local function HasTarget(unit, target)
    if type(UnitShouldDisplaySpellTargetName) == "function" then
        local ok, shown = pcall(UnitShouldDisplaySpellTargetName, unit)
        if ok and ns.CanCompute(shown) then return shown and true or false end
    end
    if type(UnitExists) == "function" and target then
        local ok, exists = pcall(UnitExists, target)
        if ok and ns.CanCompute(exists) then return exists and true or false end
    end
    return false
end

-- THE TARGET OF A CASTER, as role and class - the best-effort half.
--
-- THIS IS THE PART THAT MAY BE WITHHELD. EXBoss reads the same two values
-- off the target token (Modules/Tools/TargetIdentityState.lua:199-213) and
-- reads them bare; inside an instance the identity chain can hand back
-- secrets, and a bare read of one would be a comparison this addon is not
-- allowed to make. Both halves go through ns.CanCompute, and a withheld
-- answer becomes `unknown` - never `nobody`, and never `me`.
local function AimOf(unit, target, unique, playerIdentity)
    if not HasTarget(unit, target) then return "nobody" end

    if type(UnitExists) ~= "function" or not target or not UnitExists(target) then
        return "unknown"
    end
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(target)
    local _, classFile = UnitClass(target)
    if not (ns.CanCompute(role) and ns.CanCompute(classFile)) then
        return "unknown"
    end
    return Rules.Aim(unique, role, classFile, playerIdentity, true)
end

-- WHO I AM, in the same terms. Reads the player's own role off the spec
-- (ns.Visibility already samples it) and falls back to the group's answer.
function Casts.PlayerIdentity()
    local role = ns.Visibility and ns.Visibility:State()
        and ns.Visibility:State().role or nil
    if type(role) ~= "string" or role == "" then
        role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player") or nil
    end
    local _, classFile = UnitClass("player")
    if not ns.CanCompute(classFile) then return nil end
    return Rules.Identity(role, classFile)
end

---------------------------------------------------------------------------
-- The live scan
--
-- ONE WALK OVER nameplate1..40, not a table of event listeners per plate.
-- `namePlateUnitToken` is nil unless you are inside NAME_PLATE_UNIT_ADDED
-- (measured, and written down in the WoW lessons), so the tokens are walked
-- by hand - which is also what makes a test possible: the harness answers
-- for nameplate1..3 and nothing else has to be faked.
---------------------------------------------------------------------------

-- The live picture, rebuilt by Scan(). One entry per casting plate:
--   { unit, rank, aim, mob, name, texture, duration, isChannel, important }
Casts.live = {}
Casts.count = 0

local scratchRoster = {}

-- INVENTED CASTS FOR THE PREVIEW. The same shape Scan produces, so
-- everything downstream - the bar, the alerts, the page - is looking at one
-- kind of thing whether or not there is a dungeon around it.
local TEST_CASTS = {
    { unit = "player", rank = "boss",       aim = "me",
      mob = "Vorasius",        name = "Shadowclaw Slam", texture = 136012 },
    { unit = "player", rank = "lieutenant", aim = "tank",
      mob = "Runed Spellbreaker", name = "Runic Glaive", texture = 135800 },
    { unit = "player", rank = "standard",   aim = "group",
      mob = "Arcane Sentry",   name = "Arcane Beam",    texture = 136096 },
}

function Casts:Testing()
    return self.testing and true or false
end

function Casts:SetTestMode(on)
    self.testing = on and true or false
    self:Scan()
    if ns.CastBar then ns.CastBar:Refresh() end
    if ns.CastAlerts then ns.CastAlerts:Refresh() end
end

-- ONE ROW OF THE LIVE LIST, REUSED. The rows are kept past the end of the
-- list rather than dropped, so a pull that never has more than four casts at
-- once allocates four tables in its whole life. `live` is trimmed with
-- `self.count`, never with `#live` - see Fill below.
local pool = {}

local function Row(index)
    local row = pool[index]
    if not row then
        row = {}
        pool[index] = row
    end
    return row
end

-- EVERY CAST ON SCREEN RIGHT NOW. Returns the count.
--
-- NOTHING IS ALLOCATED WHILE NOTHING IS CASTING, and that is the whole shape
-- of this function: the roster is folded only once a cast has been found,
-- the unit tokens are built once at load, the rows are pooled, and the config
-- is seeded once per profile. A tick that finds an empty screen touches no
-- memory at all.
function Casts:Scan()
    local live = self.live
    local found = 0

    if self.testing then
        local cfg = Casts.Config()
        for _, entry in ipairs(TEST_CASTS) do
            if Rules.Wanted(cfg, entry.rank, entry.aim) then
                found = found + 1
                local row = Row(found)
                row.unit, row.rank, row.aim = entry.unit, entry.rank, entry.aim
                row.mob, row.name, row.texture =
                    entry.mob, entry.name, entry.texture
                row.spellID, row.notInterruptible = nil, nil
                row.isChannel, row.duration = false, nil
                live[found] = row
            end
        end
        for index = found + 1, #live do live[index] = nil end
        self.count = found
        return found
    end

    if type(UnitExists) ~= "function" then
        for index = 1, #live do live[index] = nil end
        self.count = 0
        return 0
    end

    local cfg = Casts.Config()
    local unique, playerIdentity

    for index = 1, MAX_PLATES do
        local unit = PLATE_UNITS[index]
        if UnitExists(unit) then
            local cast = CastOn(unit)
            if cast then
                -- THE GROUP IS ASKED FOR ONCE, AND ONLY ONCE SOMETHING IS
                -- CASTING. ns.Roster() builds a table per member and folding
                -- it builds two more; doing that ten times a second in an
                -- empty corridor is the resting-state cost this rule is
                -- about.
                if not unique then
                    unique = Rules.Fold(ns.Roster and ns.Roster()
                        or scratchRoster)
                    playerIdentity = Casts.PlayerIdentity()
                end

                local rank = Rules.Rank(UnitLevel and UnitLevel(unit) or nil)
                local aim = AimOf(unit, PLATE_TARGETS[index], unique,
                    playerIdentity)

                -- THE MOB'S NAME IS READABLE, and it is the only name in
                -- this whole feature that is: measured on 12.0 and written
                -- down at the top of Core/Taunts.lua. It is what the alerts
                -- may filter on and what the page's right-hand column lists.
                local raw = UnitName and UnitName(unit) or nil
                local mob
                if ns.CanCompute(raw) and type(raw) == "string" and raw ~= "" then
                    mob = raw
                end

                -- Every mob we see casting goes in the ledger, whether or not
                -- this config wants a line about it: the list you pick from
                -- has to fill itself while you play, not only while an alert
                -- happens to be watching.
                Casts.Remember(mob, rank)

                if Rules.Wanted(cfg, rank, aim) then
                    found = found + 1
                    local row = Row(found)
                    row.unit, row.rank, row.aim = unit, rank, aim
                    row.mob, row.name, row.texture = mob, cast.name, cast.texture
                    row.spellID = cast.spellID
                    row.notInterruptible = cast.notInterruptible
                    row.isChannel = cast.isChannel
                    row.duration = DurationOn(unit, cast.isChannel)
                    live[found] = row
                end
            end
        end
    end

    for index = found + 1, #live do live[index] = nil end
    self.count = found
    return found
end

---------------------------------------------------------------------------
-- THE LEDGER - which mobs cast things, where.
--
-- Owner, 2026-08-18, with two screenshots of EXBoss's Trash CD page: "rechte
-- leiste alle mobs und buster nach dungon / raids sortiert. schoen mit
-- icons, namen etc." That page is a hand-kept table of spell ids, and this
-- addon cannot have one - the id of a cast is secret, so a list of ids could
-- never be matched against what is happening in front of you.
--
-- WHAT CAN BE MATCHED IS THE CASTER. UnitName reads mobs fine, so the list
-- writes itself out of what you actually meet: every mob seen casting, filed
-- under the instance you were in. Clicking one on the page adds it to the
-- alert you are editing, and THAT filter works live - which is the whole
-- point of a list, and the part a table of ids could not do on this patch.
--
-- Stored per profile, and only strings and numbers go in: a secret value in
-- SavedVariables is a saved file that cannot be written.
---------------------------------------------------------------------------
local UNKNOWN_PLACE = "Out in the world"

function Casts.Where()
    if type(GetInstanceInfo) ~= "function" then return UNKNOWN_PLACE end
    local ok, name = pcall(GetInstanceInfo)
    if ok and ns.CanCompute(name) and type(name) == "string" and name ~= "" then
        return name
    end
    return UNKNOWN_PLACE
end

function Casts.Seen()
    local cfg = Casts.Config()
    cfg.seen = cfg.seen or {}
    return cfg.seen
end

-- One mob, once. Returns true when it was new here.
function Casts.Remember(mob, rank)
    if type(mob) ~= "string" or mob == "" then return false end
    if not ns.db then return false end

    local seen = Casts.Seen()
    local place = Casts.Where()
    local list = seen[place]
    if not list then
        list = {}
        seen[place] = list
    end

    local entry = list[mob]
    if entry then
        entry.count = (tonumber(entry.count) or 0) + 1
        if rank then entry.rank = rank end
        return false
    end

    list[mob] = { rank = rank, count = 1 }
    return true
end

-- The ledger as a sorted list of places, each with its sorted mobs, which is
-- the shape the page draws. Rebuilt on demand: it is read when a page is
-- open and never in combat.
function Casts.Ledger()
    local out = {}
    for place, mobs in pairs(Casts.Seen()) do
        local rows = {}
        for mob, entry in pairs(mobs) do
            rows[#rows + 1] = {
                mob = mob,
                rank = entry.rank,
                count = tonumber(entry.count) or 0,
            }
        end
        table.sort(rows, function(a, b)
            local aw = RANK_ORDER[a.rank or ""] or 0
            local bw = RANK_ORDER[b.rank or ""] or 0
            if aw ~= bw then return aw > bw end
            return a.mob < b.mob
        end)
        out[#out + 1] = { place = place, mobs = rows }
    end
    table.sort(out, function(a, b) return a.place < b.place end)
    return out
end

function Casts.Forget(place)
    local seen = Casts.Seen()
    if place then
        seen[place] = nil
    else
        for key in pairs(seen) do seen[key] = nil end
    end
end

-- THE ONE THAT MATTERS, for surfaces that show a single line: the cast aimed
-- at you if there is one, else the most dangerous rank on screen. Ties go to
-- the one found first, which is the plate the client listed first.
function Casts.Foremost(live)
    local best
    for _, entry in ipairs(live or {}) do
        if entry.aim == "me" then
            if not (best and best.aim == "me") then best = entry end
        elseif not best or best.aim ~= "me" then
            local mine = RANK_ORDER[entry.rank or ""] or 0
            local theirs = best and (RANK_ORDER[best.rank or ""] or 0) or -1
            if mine > theirs then best = entry end
        end
    end
    return best
end

function Casts:Current()
    return Casts.Foremost(self.live)
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
Casts.DEFAULTS = {
    -- WHICH CASTS COUNT. Both sets start full: a tank who switches this on
    -- wants to see what is being cast, and narrowing it is a decision they
    -- make on the page rather than one made for them.
    ranks = { standard = true, lieutenant = true, boss = true },
    aims  = { me = true, tank = true, unknown = true,
              group = false, nobody = false },

    -- How often the scan runs while something is casting. Ten times a second
    -- is what the co-tank panel polls health at, and a cast bar that lags a
    -- fifth of a second reads as broken.
    interval = 0.1,

    -- The bar itself. Placed like every other panel in this addon.
    bar = {
        enabled = true,
        -- The stripe that says "this one is coming at you". Its width, not
        -- its colour: the colour is the accent, like every other "look at
        -- this" mark in the addon.
        atMeWidth = 4,
        uninterruptibleColor = { 0.45, 0.45, 0.52 },
        width = 260, height = 26, scale = 1.0,
        point = "CENTER", relPoint = "CENTER", x = 0, y = -170,
        texture = "ZS Smooth",
        color = { 0.80, 0.24, 0.20 },
        importantColor = { 1.00, 0.60, 0.10 },
        bgAlpha = 0.85,
        borderSize = 1,
        showIcon = true, iconSize = 26,
        showName = true, showMob = true, showTarget = true,
        font = "", fontSize = 12, outline = "OUTLINE",
        -- Every rule the reminders and the answer bar carry, same builder.
        show = nil,
    },

    -- The voice. Off until somebody picks a pack, because a line spoken by
    -- the client's own text-to-speech voice on every cast is the fastest way
    -- to have a feature switched off for good.
    voice = {
        enabled = false,
        voiceID = nil,
        volume = 100,
        rate = 0,
        -- One line per rank, and %who is the half that matters.
        lines = {
            standard   = "",
            lieutenant = "Lieutenant casting",
            boss       = "Tank hit",
        },
        onlyAtMe = true,
        gap = 2.0,
    },

    -- The alerts, a book of reminders (Core/CastAlerts.lua) - the list lives
    -- here so it travels with the profile like every other list.
    alerts = {},
}

-- SEEDED ONCE PER PROFILE, not ten times a second. The scan asks for the
-- config on every tick, and walking the defaults (two of them nested) on each
-- one is work nobody asked for. The table's own identity is the cache key:
-- switching profiles hands back a different table and the seeding runs again,
-- which is exactly the moment it is needed.
local seeded

function Casts.Config()
    ns.db.casts = ns.db.casts or {}
    local cfg = ns.db.casts
    if seeded == cfg then return cfg end
    for key, value in pairs(Casts.DEFAULTS) do
        if cfg[key] == nil then
            if type(value) == "table" then
                local copy = {}
                for k, v in pairs(value) do
                    if type(v) == "table" then
                        local inner = {}
                        for ik, iv in pairs(v) do inner[ik] = iv end
                        copy[k] = inner
                    else
                        copy[k] = v
                    end
                end
                cfg[key] = copy
            else
                cfg[key] = value
            end
        end
    end
    -- The nested tables gain keys over versions the same way the top level
    -- does; ApplyDefaults never overwrites what is already there.
    ns.ApplyDefaults(cfg.bar, Casts.DEFAULTS.bar)
    ns.ApplyDefaults(cfg.voice, Casts.DEFAULTS.voice)
    cfg.alerts = cfg.alerts or {}
    seeded = cfg
    return cfg
end

---------------------------------------------------------------------------
-- The tick
--
-- One OnUpdate for the whole module. It scans while there is anything to
-- scan and while the module is on, and it hands the result to whoever is
-- drawing - the bar and the alert book. Nothing polls on its own.
---------------------------------------------------------------------------
function Casts:Start()
    if self.ticker then return end

    local ticker = CreateFrame("Frame")
    self.ticker = ticker
    self.accum = 0

    -- WHAT HAPPENS SIXTY TIMES A SECOND IS ONE ADDITION AND ONE COMPARE.
    -- The first draft asked for the config here, which meant a table lookup
    -- into the saved profile on every frame to read a number that changes
    -- when somebody drags a slider. The interval is re-read after each walk
    -- instead - one read per tenth of a second, and a slider still takes
    -- effect immediately.
    self.interval = tonumber(Casts.Config().interval) or 0.1

    ticker:SetScript("OnUpdate", function(_, elapsed)
        local accum = self.accum + elapsed
        if accum < self.interval then
            self.accum = accum
            return
        end
        self.accum = 0
        self.interval = tonumber(Casts.Config().interval) or 0.1

        if not ns.Modules:IsOn("casts") then
            if self.count > 0 then
                self:Scan()
                if ns.CastBar then ns.CastBar:Refresh() end
                if ns.CastAlerts then ns.CastAlerts:Refresh() end
            end
            return
        end

        self:Scan()
        if ns.CastBar then ns.CastBar:Refresh() end
        -- Repaint, not Refresh: the alert's words and icon belong to the cast
        -- that is up, and two casts in a row under one message must not wear
        -- the first one's icon. It restyles only what actually changed.
        if ns.CastAlerts then ns.CastAlerts:Repaint() end
    end)
end

---------------------------------------------------------------------------
-- The voice
--
-- WHY THIS IS NOT text-to-speech BY DEFAULT: the client's own voice reads
-- like a train station, and the owner said so. What plays instead is a VOICE
-- PACK - the .ogg files BigWigs, DBM and their community packs already ship.
-- A pack registers its sounds with LibSharedMedia or lives in a folder we
-- can name, and this addon plays a FILE like every other sound it plays
-- (ns.Media.PlaySound). Text-to-speech stays as the fallback for a line
-- nobody has a recording of.
--
-- The gap is per-voice rather than per-cast: three mobs starting the same
-- cast in one pull is one sentence, not three on top of each other.
---------------------------------------------------------------------------
local lastSpoke = 0

function Casts.MaySpeak(now, previous, gap)
    now = tonumber(now) or 0
    previous = tonumber(previous) or 0
    gap = tonumber(gap) or 0
    if previous <= 0 then return true end
    return (now - previous) >= gap
end

function Casts.Speak(line, cfg)
    if type(line) ~= "string" or line == "" then return false end
    cfg = cfg or Casts.Config().voice
    if not (cfg and cfg.enabled) then return false end

    local now = GetTime and GetTime() or 0
    if not Casts.MaySpeak(now, lastSpoke, cfg.gap or 2.0) then return false end
    lastSpoke = now

    -- A RECORDED LINE FIRST. ns.Media resolves a sound by name across every
    -- pack the client has, so "BigWigs: Tank" and a pack of our own reach
    -- the same door.
    if cfg.sound and cfg.sound ~= "" and cfg.sound ~= "None" then
        if ns.Media and ns.Media.PlaySound then
            return ns.Media.PlaySound(cfg.sound, "Master") and true or false
        end
    end

    -- THE CLIENT'S OWN VOICE, and the argument order is the one live clients
    -- take: (voiceID, text, destination, volume, interrupt). Enum
    -- .VoiceTtsDestination does not exist on live, so the literal 1 (local
    -- playback) is what every addon that does this passes - read off
    -- EllesmereUIQoL_MovementAlert.lua and MRT's Reminder.lua.
    if not (C_VoiceChat and C_VoiceChat.SpeakText) then return false end
    local ok = pcall(C_VoiceChat.SpeakText, cfg.voiceID or 0, line, 1,
        cfg.volume or 100, true)
    return ok and true or false
end

-- The line for a cast, or nil when this rank has none.
function Casts.Line(cfg, entry)
    if not (type(cfg) == "table" and type(entry) == "table") then return nil end
    if cfg.onlyAtMe and entry.aim ~= "me" then return nil end
    local lines = cfg.lines
    local line = type(lines) == "table" and lines[entry.rank or ""] or nil
    if type(line) ~= "string" or line == "" then return nil end
    return Rules.Words(line, entry.rank, entry.aim, entry.mob)
end

---------------------------------------------------------------------------
-- /zs casts - what the scan sees, in words
---------------------------------------------------------------------------
function Casts:Dump()
    if not ns.Modules:IsOn("casts") then
        ns.Print("The cast module is switched off "
            .. "(|cffffd100/zs modules casts|r).")
        return
    end

    self:Scan()
    if self.count == 0 then
        ns.Print("Nothing is casting. "
            .. "|cffffd100/zs casts test|r invents three.")
        return
    end

    ns.Print(string.format("|cffffd100%d cast%s|r", self.count,
        self.count == 1 and "" or "s"))
    for _, entry in ipairs(self.live) do
        local rank = RANK_WORDS[entry.rank or ""] or "Something"
        local aim = AIM_WORDS[entry.aim or "nobody"] or "somebody"
        ns.Print(string.format("  %s %s |cff888888-> %s|r",
            rank, entry.mob and ("(" .. entry.mob .. ")") or "", aim))
    end
    ns.Print("|cff888888The spell itself cannot be named on this patch - "
        .. "its id is a secret value. The icon and the bar are the game's "
        .. "own.|r")
end
