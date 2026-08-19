---------------------------------------------------------------------------
-- WHICH SPECIALISATION SOMEBODY IS PLAYING
--
-- Owner, on the external cooldown panel: "es wird nicht geprueft in welchen
-- spec die klassen sind, wenn ich einen priester in der gruppe habe, werden
-- fuer beide heiler specs die icons angezeigt."
--
-- He is right, and the first answer this session gave him - that a group
-- mate's spec is not readable - was WRONG. It is readable, every damage
-- meter and every raid frame does it, and the reason no synchronous call
-- exists is that the answer travels over the wire: you ASK the server for a
-- player's inspect data and it arrives later, as an event.
--
--     CanInspect(unit)               may I, and is he close enough
--     NotifyInspect(unit)            ask the server
--     INSPECT_READY(guid)            it answered, for THIS guid
--     GetInspectSpecialization(unit) now the number is there
--
-- That is MRT's route (MRT/Inspect.lua) and it is everybody's, because it is
-- the only one. What this file adds around it is the part that makes it
-- usable: one question in flight at a time, a queue, a cache by GUID rather
-- than by unit token (party3 is a different person after somebody leaves),
-- and a cooldown on re-asking so a group standing in a city does not spend
-- the evening inspecting itself.
--
-- IT FAILS OPEN, EVERYWHERE. An unknown spec means "show it anyway", which
-- is exactly the behaviour this addon had before this file existed. Somebody
-- out of range, an inspect the server never answers, a client that renamed
-- one of these functions - all of them land on "I do not know", and not
-- knowing must never make help disappear off the panel. Hiding the wrong
-- icon is a nuisance; hiding the right one costs a wipe.
---------------------------------------------------------------------------
local _, ns = ...

local Specs = {}
ns.Specs = Specs

-- Two seconds between questions. The server throttles inspects itself and an
-- addon that ignores that gets its requests dropped, which looks exactly like
-- a spec that cannot be read. Slow and answered beats fast and refused.
local ASK_GAP = 2

-- How long a failed attempt sits before it is worth another try. Somebody out
-- of range stays out of range for a while; somebody who just zoned in will be
-- picked up by the roster event long before this matters.
local RETRY_AFTER = 30

---------------------------------------------------------------------------
-- REACHING THE GAME'S OWN FUNCTIONS
--
-- Every one of these has moved into a C_ table at some point in the last few
-- expansions and several exist in both places. Asking for the namespace
-- first and the global second means this file does not care which patch it
-- is running on, and a client that has neither leaves us with nil - which
-- the callers below already treat as "I do not know".
---------------------------------------------------------------------------
local function Reach(name)
    local space = C_SpecializationInfo
    if space and type(space[name]) == "function" then return space[name] end
    if type(_G[name]) == "function" then return _G[name] end
    return nil
end

local ROLES = { TANK = true, HEALER = true, DAMAGER = true }

---------------------------------------------------------------------------
-- EVERY CLASS'S SPECS, ASKED OF THE GAME
--
-- The mapping "index 2 of a priest is Holy" is knowledge, and knowledge
-- written from memory is how this project has been wrong before. So the
-- NUMBERS are never written down: the class ids come from the game, the spec
-- ids come from the game, and the only thing a spell carries is an index
-- plus the role that index must have. If the game disagrees about the role,
-- the restriction is dropped rather than applied - see IdFor.
--
-- Built once, on first use, because it needs nothing but static data and
-- calling it at file scope would run before the client is ready to answer.
---------------------------------------------------------------------------
local byClass

local function BuildTable()
    if byClass then return byClass end
    byClass = {}

    local classInfo = C_CreatureInfo and C_CreatureInfo.GetClassInfo
    local howMany = Reach("GetNumSpecializationsForClassID")
    local infoFor = Reach("GetSpecializationInfoForClassID")
    if not (classInfo and howMany and infoFor) then return byClass end

    -- No MAX_CLASSES here: it is a global that may or may not be set, and a
    -- loop that stops early would silently lose a class. Walking past the end
    -- costs a handful of nils once per session.
    for classID = 1, 30 do
        local info = classInfo(classID)
        local file = info and info.classFile
        if type(file) == "string" then
            local specs = {}
            for index = 1, (howMany(classID) or 0) do
                local id, name, _, _, role = infoFor(classID, index)
                if type(id) == "number" and id > 0 then
                    if not ROLES[role] then
                        local byId = Reach("GetSpecializationRoleByID")
                        role = byId and byId(id) or nil
                    end
                    specs[index] = { id = id, name = name, role = role }
                end
            end
            if next(specs) then byClass[file] = specs end
        end
    end
    return byClass
end

function Specs.Table() return BuildTable() end

-- Only for the self test, which needs to run this rule twice with different
-- data and cannot do that against a table built once and kept.
function Specs.ForgetTable() byClass = nil end

---------------------------------------------------------------------------
-- ONE AUTHORED RESTRICTION, RESOLVED
--
-- Pure apart from the lookup table, and separated out because it is the one
-- piece here that can be wrong in a way nobody notices: an index off by one
-- points at a different spec, and a panel that hides the right healer looks
-- exactly like a panel that is working.
--
-- The role is the check. Priest 1 must be a HEALER; if the game says the
-- first priest spec is a damage spec, the number moved and we say nothing at
-- all rather than filtering on it. It cannot catch a swap between two specs
-- of the SAME role - Discipline against Holy is exactly that case - which is
-- why /zs specs prints the game's own names next to what we assumed.
---------------------------------------------------------------------------
function Specs.Resolve(list, classFile, index, expectedRole)
    local specs = list and list[classFile]
    local entry = specs and specs[index]
    if not entry then return nil, "no such spec" end
    if expectedRole and entry.role and entry.role ~= expectedRole then
        return nil, "role is " .. tostring(entry.role)
    end
    return entry.id, entry.name
end

function Specs.IdFor(classFile, index, expectedRole)
    if not (classFile and index) then return nil end
    return Specs.Resolve(BuildTable(), classFile, index, expectedRole)
end

---------------------------------------------------------------------------
-- WHAT WE KNOW, AND ASKING FOR WHAT WE DO NOT
---------------------------------------------------------------------------
local known = {}     -- guid -> specID
local tried = {}     -- guid -> when we last asked
local pending = {}   -- guid -> unit token, the queue
local lastAsk = 0
local ticker

local function Now()
    return (GetTime and GetTime()) or 0
end

---------------------------------------------------------------------------
-- WHOSE CHANNEL IS IT
--
-- b9ty, on CurseForge: opening Blizzard's inspect window on somebody in the
-- group showed EVERY equipment slot blank while the 3D model still wore the
-- gear. No Lua error, and it looked intermittent. It was us.
--
-- THE CLIENT KEEPS ONE INSPECT TARGET. NotifyInspect moves it and
-- ClearInspectPlayer throws away the answer sitting in it, so either call,
-- made while the player has that window open, takes the window's data out
-- from under it. The two-second ticker below turned that into a coin flip:
-- land between his click and the window's read and the slots come back
-- empty. Nothing in here was ever worth that - the spec cache is a
-- convenience, his inspect window is what he actually asked for, and when
-- the two want the same wire he wins.
--
-- TWO SIGNALS, because neither one covers it alone:
--
--   * the window being SHOWN, which covers the whole time it is open.
--   * the player having just ASKED, which covers the moment before it shows.
--     The request goes out first, and out of range the window never shows at
--     all. hooksecurefunc on InspectUnit is that signal and it EXPIRES, so
--     nothing here can get stuck holding the queue shut.
--
-- InspectFrame.unit was the other candidate and it is deliberately not used.
-- It would answer both questions - but only for as long as Blizzard keeps
-- clearing it when the window hides, and a guard that never lets go is worse
-- than the bug it fixes: it would silently stop every spec being learned for
-- the rest of the session, and this file's whole promise is that not knowing
-- is temporary. IsShown cannot get stuck, and neither can a clock.
---------------------------------------------------------------------------
local USER_GRACE = 3

local userAskedAt

if type(hooksecurefunc) == "function" and type(InspectUnit) == "function" then
    hooksecurefunc("InspectUnit", function()
        userAskedAt = Now()
    end)
end

-- PURE, and kept apart from Busy for the same reason MayAsk is kept apart
-- from Sweep: a rule with a clock inside it is a rule nobody can test.
function Specs.ChannelBusy(now, askedAt, shown)
    if shown then return true end
    if askedAt and now - askedAt < USER_GRACE then return true end
    return false
end

-- The same question, asked of the real client. InspectFrame does not exist
-- until Blizzard_InspectUI loads, which is why every reach at it is guarded.
function Specs.Busy()
    local frame = InspectFrame
    local shown = false
    if frame and type(frame.IsShown) == "function" then
        shown = ns.Truth(frame:IsShown(), false)
    end
    return Specs.ChannelBusy(Now(), userAskedAt, shown)
end

-- Only for the self test, which has to be able to run both sides of a guard
-- whose other side is a clock.
function Specs.ForgetUserAsk() userAskedAt = nil end

-- The player never travels over the wire. His own spec is a plain call and
-- it is always available, which also makes him the one member of the group
-- the panel can filter correctly from the first second of a fight.
function Specs.Own()
    local which = Reach("GetSpecialization")
    local info = Reach("GetSpecializationInfo")
    if not (which and info) then return nil end
    local index = which()
    if type(index) ~= "number" then return nil end
    local id = info(index)
    return (type(id) == "number" and id > 0) and id or nil
end

-- PURE, and the reason the queue is testable at all: when may this guid be
-- asked about again? Everything time-dependent about the throttle lives here
-- and the self test hands it its own clock.
function Specs.MayAsk(now, lastAt, triedAt)
    if lastAt and now - lastAt < ASK_GAP then return false end
    if triedAt and now - triedAt < RETRY_AFTER then return false end
    return true
end

---------------------------------------------------------------------------
-- SAYING SO WHEN AN ANSWER LANDS
--
-- THE WHOLE FEATURE HANGS ON THIS and it is the part that would have been
-- missed. An inspect answers seconds after the roster event that asked for
-- it - so a panel that only redraws on GROUP_ROSTER_UPDATE would have the
-- rule right, the number right, and the wrong icon still on the screen until
-- somebody left the group. Three times this week the rule was fine and the
-- WIRING was the bug; this is the wire.
---------------------------------------------------------------------------
local listeners = {}

function Specs.OnLearned(fn)
    if type(fn) == "function" then listeners[#listeners + 1] = fn end
end

local function Store(guid, id)
    if type(guid) == "string" and type(id) == "number" and id > 0 then
        local news = known[guid] ~= id
        known[guid] = id
        pending[guid] = nil
        if news then
            for _, fn in ipairs(listeners) do fn(guid, id) end
        end
        return true
    end
    return false
end

-- Reading an inspect answer. Kept apart from the event so the harness can
-- drive it without a server: everything that decides anything is in here.
function Specs.Absorb(unit)
    if not unit then return nil end
    local read = Reach("GetInspectSpecialization")
    if not read then return nil end
    local guid = UnitGUID and UnitGUID(unit)
    local id = read(unit)
    if Store(guid, id) then return id end
    return nil
end

-- ONE PASS OVER THE QUEUE. Public because the ticker is not the only thing
-- that should be able to run it: the harness has no clock, and a rule nobody
-- can drive from outside is a rule nobody can test.
--
-- IT SAYS WHAT IT DID - "busy", "asked", "waiting", "swept" or "idle" - and
-- that is not decoration. The guard below is the whole of b9ty's bug, and a
-- guard whose only proof is that somebody read the file is the shape this
-- project has shipped broken before. The word comes back so the self test
-- can drive the real sweep and be told.
function Specs.Sweep()
    -- BLIZZARD'S WINDOW OWNS THE CHANNEL WHILE IT IS OPEN. The queue is left
    -- exactly as it is - the ticker keeps running and simply asks again once
    -- the player closes it, so the only cost is that spec learning pauses
    -- while he is looking at somebody.
    --
    -- `next(pending)` is part of the CONDITION rather than of the guard so an
    -- empty queue still falls through to the cancel at the bottom. Otherwise
    -- a window open at the wrong second would leave a ticker running for the
    -- rest of the session with nothing to do.
    if next(pending) and Specs.Busy() then return "busy" end

    local can = CanInspect
    local ask = NotifyInspect
    local now = Now()

    for guid, unit in pairs(pending) do
        -- He may have left, or the token may now be somebody else entirely.
        if not (UnitExists and UnitExists(unit) and UnitGUID
            and UnitGUID(unit) == guid) then
            pending[guid] = nil
        elseif Specs.Absorb(unit) then
            -- Already cached from somebody else's inspect. Free.
        elseif Specs.MayAsk(now, lastAsk, tried[guid]) then
            if can and ask and can(unit) then
                tried[guid] = now
                lastAsk = now
                ask(unit)
                return "asked"
            end
            -- Out of range or not inspectable. Not an error and not worth a
            -- message: it resolves itself when he walks over.
            tried[guid] = now
            return "waiting"
        end
    end

    if not next(pending) then
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
        return "idle"
    end
    return "swept"
end

local function StartTicker()
    if ticker or not (C_Timer and C_Timer.NewTicker) then return end
    ticker = C_Timer.NewTicker(ASK_GAP, Specs.Sweep)
end

---------------------------------------------------------------------------
-- THE TWO CALLS EVERYTHING ELSE MAKES
---------------------------------------------------------------------------
-- What is this unit playing? nil means "not known yet", never "no spec".
function Specs.Of(unit)
    if not unit then return nil end
    if UnitIsUnit and ns.Truth(UnitIsUnit(unit, "player"), false) then
        return Specs.Own()
    end
    local guid = UnitGUID and UnitGUID(unit)
    return guid and known[guid] or nil
end

-- Put him in the queue if we do not know yet. Called from the roster walk,
-- so every list of who is here is also the list of who is worth asking about.
function Specs.Want(unit)
    if not unit then return nil end
    if UnitIsUnit and ns.Truth(UnitIsUnit(unit, "player"), false) then return end
    local guid = UnitGUID and UnitGUID(unit)
    if not guid or known[guid] then return end
    pending[guid] = unit
    StartTicker()
end

---------------------------------------------------------------------------
-- FINDING SOMEBODY BY NAME
--
-- Every list this addon reads names people rather than handing over unit
-- tokens: the damage meter says "Grauertiger-Destromath", the recap says
-- "Meredy Huntswell". A unit token is what the client wants for nearly
-- everything - a portrait, an inspect, a spec - so the walk from one to the
-- other lives here once instead of in each window.
--
-- Both spellings are compared, because the meter says NAME-REALM and
-- UnitName answers without a realm for anybody on ours.
---------------------------------------------------------------------------
function Specs.UnitForName(name)
    if not (type(name) == "string" and name ~= "" and UnitName) then
        return nil
    end
    local short = ns.Death and ns.Death.StripRealm and ns.Death.StripRealm(name)
        or name

    local function Is(unit)
        local ok, found, realm = pcall(UnitName, unit)
        if not (ok and type(found) == "string") then return false end
        if found == name or found == short then return true end
        if type(realm) == "string" and realm ~= "" then
            return (found .. "-" .. realm) == name
        end
        return false
    end

    if Is("player") then return "player" end
    for index = 1, 4 do
        local unit = "party" .. index
        if UnitExists and UnitExists(unit) and Is(unit) then return unit end
    end
    for index = 1, 40 do
        local unit = "raid" .. index
        if UnitExists and UnitExists(unit) and Is(unit) then return unit end
    end
    return nil
end

-- What that person is playing, by name. nil means "not known", never "no
-- spec" - and it stays nil rather than guessing from the class, because a
-- wrong spec icon beside a name is worse than a class icon that is right.
function Specs.OfName(name)
    local unit = Specs.UnitForName(name)
    return unit and Specs.Of(unit) or nil
end

function Specs.Forget(guid)
    if guid then
        known[guid] = nil
        tried[guid] = nil
    else
        wipe(known)
        wipe(tried)
        wipe(pending)
    end
end

---------------------------------------------------------------------------
-- EVENTS
--
-- Registered at load and passive: nothing here asks the server anything, it
-- only reads answers and throws away what went stale. The asking starts when
-- somebody calls Want, and stops the moment the queue is empty.
---------------------------------------------------------------------------
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("INSPECT_READY")
watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
watcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
-- AN ANSWER LANDED. Kept out of the handler for the same reason Absorb is:
-- an event nobody can fire is a branch nobody can check, and the second half
-- of b9ty's bug lives in here. Says which of the three things it did.
function Specs.Answered(guid)
    local unit = pending[guid]
    if unit then Specs.Absorb(unit) end

    -- CLEARING IS HANDING THE CHANNEL BACK, so only whoever took it may do
    -- it. `unit` is nil for every answer we never asked for - the player's
    -- own inspect window included - and the clear used to happen anyway,
    -- outside this guard, throwing away the payload its owner was about to
    -- read. That is the blank equipment slots.
    if not unit then return "not ours" end
    if Specs.Busy() then return "kept" end
    if ClearInspectPlayer then ClearInspectPlayer() end
    return "cleared"
end

watcher:SetScript("OnEvent", function(_, event, arg1)
    if event == "INSPECT_READY" then
        Specs.Answered(arg1)

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- The arg is a unit, and it is the ONLY signal that somebody
        -- respecced. A cached spec that is a patch old is worse than none.
        local guid = arg1 and UnitGUID and UnitGUID(arg1)
        if guid then Specs.Forget(guid) end

    elseif event == "GROUP_ROSTER_UPDATE" then
        -- Not a wipe: people who are still here have not changed anything.
        -- Only the queue, because its unit tokens have just been reshuffled.
        wipe(pending)
        if ns.Roster then ns.Roster() end
    end
end)

---------------------------------------------------------------------------
-- /zs specs - the one thing that cannot be checked from a desk
--
-- Two questions, both of which take a glance: does index 1 of a priest say
-- Discipline on YOUR client, and what did we manage to read about the people
-- standing next to you.
---------------------------------------------------------------------------
function Specs:Dump()
    local list = BuildTable()
    ns.Print("|cffffd100Specialisations|r")

    if not next(list) then
        ns.Print("  |cffff4040This client did not answer|r - every spec filter is off,")
        ns.Print("  which means the panel shows what it always showed.")
        return
    end

    local restrictions = ns.Externals and ns.Externals.SpecRestrictions
        and ns.Externals.SpecRestrictions() or {}
    if #restrictions == 0 then
        ns.Print("  Nothing is spec-restricted.")
    end
    for _, entry in ipairs(restrictions) do
        local id, why = Specs.Resolve(list, entry.class, entry.index, entry.role)
        if id then
            ns.Print(string.format(
                "  |cff40ff40%-22s|r %s %d -> |cffffd100%s|r (%d)",
                entry.name, entry.class, entry.index, tostring(why), id))
        else
            ns.Print(string.format(
                "  |cffff4040%-22s|r %s %d -> dropped, %s",
                entry.name, entry.class, entry.index, tostring(why)))
        end
    end

    ns.Print("|cffffd100Who is here|r")
    for _, member in ipairs(ns.Roster and ns.Roster() or {}) do
        local specs = list[member.class]
        local name
        if member.spec and specs then
            for _, spec in pairs(specs) do
                if spec.id == member.spec then name = spec.name break end
            end
        end
        ns.Print(string.format("  %-20s %-14s %s", member.name,
            tostring(member.class),
            name or (member.spec and tostring(member.spec))
                or "|cff888888not read yet|r"))
    end
end
