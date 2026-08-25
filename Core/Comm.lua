---------------------------------------------------------------------------
-- Comm - the addon channel, so a request can be ANSWERED and not just read.
--
-- Owner, 2026-08-10: "wenn ich zum beispiel nach einem external cd frage
-- [...] lässt beim spieler die fähigkeit aufläuchten, man kann klicken und
-- das addon nimmt den spieler ins target und castet."
--
-- HALF OF THAT IS POSSIBLE AND HALF IS NOT, and the line runs exactly here:
--
--   reading, recognising,      YES. This is what the trade-chat addons do,
--   lighting something up      and an ADDON MESSAGE is the better door than
--                              chat - invisible to players, structured, and
--                              it does not depend on the wording of a
--                              sentence the user is allowed to edit.
--   casting on the click       ONLY through a SecureActionButton, whose
--                              spell and target are set OUT OF COMBAT. The
--                              player presses it; the addon never casts.
--
-- The owner's answer to that: "ja, also der spieler muss schon klicken" - and
-- "ja ist klar. alle brauchen das addon". Both limits accepted, both written
-- on the settings page rather than left to be discovered.
--
-- THE VISIBLE CHAT LINE STAYS. Everybody who does not run this addon still
-- gets the sentence; this channel is what turns it into a button for the
-- people who do.
---------------------------------------------------------------------------
local _, ns = ...

local Comm = {}
ns.Comm = Comm

-- Sixteen characters is the limit on a prefix, and the SelfTest pins it: over
-- it, RegisterAddonMessagePrefix quietly refuses and nothing is ever received
-- while everything looks like it is being sent.
Comm.PREFIX = "ZwoelfStuff"

-- The first field of every message. A newer major version is DROPPED rather
-- than parsed - that is what the field is for, and the one thing that must
-- never happen is an older client acting on a message shape it half
-- understands.
Comm.VERSION = 1

Comm.REQUEST = "REQ"
Comm.ACK = "ACK"

-- THE OWNER'S IDEA, and it is the one that unlocks the thing this addon has
-- been saying was impossible since 4.58.0:
--
--   "damit wir wissen wann dem heiler seine cds fertig sind, müsste der
--   heiler [...] automatisch einmal in chat schreiben lay on hands cd rdy
--   oder so. Und lay on hands used. dann kann unser addon auslesen, ist rdy
--   oder used [...] damit sehe ich als tank, ob der cd rdy oder used ist."
--
-- READING somebody else's cooldown is impossible on 12.0 - the combat log is
-- closed and a foreign instant is not announced. But every client knows its
-- OWN cooldowns perfectly, and it is allowed to say so. So the number does
-- not have to be observed; it can be REPORTED. That is not a workaround, it
-- is a better source: it is the truth from the machine that holds it.
--
-- ONE CORRECTION TO THE IDEA, and it matters: "die cds sind ja fest" is not
-- quite true. Talents move them - Lay on Hands is ten minutes, or eight with
-- Unbreakable Spirit. So the DURATION travels with the message rather than
-- being assumed from a table, because the healer's own client knows the real
-- one and a table would be confidently wrong for exactly the people who took
-- the talent.
--
-- It is an ADDON message, not a chat line: same information, invisible,
-- structured, and it does not fill the party window with "lay on hands rdy"
-- every ten minutes.
Comm.USED = "USED"     -- spell, and how long until it is back
Comm.READY = "READY"   -- it is back
Comm.HELLO = "HELLO"   -- I am here, and this is what I have

-- What is being asked for. Two kinds, because they are answered differently:
-- an external names the spell the OTHER person casts, a taunt does not - the
-- other tank presses their own.
Comm.EXTERNAL = "EXT"
Comm.TAUNT = "TAUNT"

---------------------------------------------------------------------------
-- THE SECOND WIRE FORM: a raid check
--
-- Everything above names a SPELL. A raid check names none - it is "here is
-- what I am carrying", a handful of numbers about one player - and forcing it
-- into five fields built for a cooldown would have meant a spellID of 0 with
-- a meaning written down somewhere else.
--
-- WHY IT IS SENT AT ALL, rather than read: on this patch another player's
-- auras are secret, so their flask is not knowable from here. Their OWN
-- client knows it exactly. That is the same door LibDurability walks through
-- for durability, and it is the honest one - what is reported is a fact from
-- the machine that holds it, and somebody without this addon reports nothing
-- and is drawn as nothing rather than as a guess.
--
-- IT IS DELIBERATELY A SHAPE THE OLD DECODER REJECTS. Decode's third field is
-- %u+ and this one carries "il=639,du=94" - so a client one version behind
-- drops it silently, which is exactly what a client that cannot understand a
-- message should do. That is why the VERSION is not bumped: bumping it would
-- make the two clients ignore each other's COOLDOWNS as well.
Comm.CHECK = "CHECK"
Comm.CHECK_ASK = "ASK"

-- Which fields may travel, and every one of them is a small non-negative
-- integer. An allowlist rather than a parse: this is data from another
-- machine, and a reader that accepts whatever arrives is a reader that can be
-- handed a table key.
Comm.CHECK_FIELDS = {
    il = 4,   -- item level, whole numbers
    du = 3,   -- durability, percent
    fo = 1,   -- food
    fl = 1,   -- flask
    ru = 1,   -- augment rune
    bf = 3,   -- the raid buffs, as a bitmask
}

function Comm.EncodeCheck(fields)
    local parts = {}
    -- Written in a FIXED order rather than pairs order, so the same facts
    -- always produce the same string - which is what makes it testable and
    -- what lets a receiver ignore a repeat cheaply.
    for _, key in ipairs({ "il", "du", "fo", "fl", "ru", "bf" }) do
        local value = fields and fields[key]
        if type(value) == "number" then
            parts[#parts + 1] = key .. "="
                .. tostring(math.max(0, math.floor(value)))
        end
    end
    return table.concat({ tostring(Comm.VERSION), Comm.CHECK,
        table.concat(parts, ",") }, "|")
end

-- The ask has no fields: "everybody say what you have".
function Comm.EncodeCheckAsk()
    return table.concat({ tostring(Comm.VERSION), Comm.CHECK,
        Comm.CHECK_ASK }, "|")
end

function Comm.DecodeCheck(message)
    if type(message) ~= "string" then return nil end

    local version, body = message:match("^(%d+)|" .. Comm.CHECK .. "|(.*)$")
    if not version then return nil end
    if tonumber(version) ~= Comm.VERSION then return nil end

    if body == Comm.CHECK_ASK then
        return { what = Comm.CHECK, ask = true }
    end

    local fields = {}
    for key, value in body:gmatch("(%a%a)=(%d+)") do
        local width = Comm.CHECK_FIELDS[key]
        -- An unknown key is dropped, not kept: a newer version may send more
        -- than this one understands, and half-understanding it is worse than
        -- ignoring it. A number wider than the field allows is a lie or a
        -- mistake; either way it is not shown.
        if width and #value <= width then
            fields[key] = tonumber(value)
        end
    end

    if next(fields) == nil then return nil end
    return { what = Comm.CHECK, fields = fields }
end

-- NAME-REALM, always - the one spelling every store keys by. The channel
-- hands over "Name-Realm" for some senders and "Name" for others, the
-- roster does the same, and two spellings of one person is how an answer
-- lands in the wrong row. Own realm appended when none is named; a client
-- that cannot name its realm leaves the name as it came, on BOTH sides of
-- every lookup, which keeps the keys consistent if not pretty.
function Comm.FullName(name)
    if type(name) ~= "string" or name == "" then return nil end

    local person, realm = name:match("^([^%-]+)%-(.+)$")
    if not person then
        person = name
        realm = GetNormalizedRealmName and GetNormalizedRealmName() or nil
    end
    if type(realm) ~= "string" or realm == "" then return person end

    -- The realm is written the WIRE's way: the channel says
    -- "TwistingNether" where GetUnitName says "Twisting Nether" - one
    -- spelling, or the same person owns two rows again.
    return person .. "-" .. realm:gsub("[%s'%-]", "")
end

---------------------------------------------------------------------------
-- The wire
--
-- Pure both ways, because "my group-mate's addon says nothing" is the least
-- debuggable failure there is: with these two testable, a mismatch is caught
-- on the desktop instead of in a dungeon with somebody else's evening.
---------------------------------------------------------------------------
function Comm.Encode(what, kind, spellID, value)
    return table.concat({
        tostring(Comm.VERSION), what, kind, tostring(spellID or 0),
        tostring(math.floor((value or 0) + 0.5)),
    }, "|")
end

-- Answers nil for anything it does not fully understand. Every field is
-- checked rather than trusted: this is data from another machine, and the
-- only sentence worth writing about that is "it is not to be trusted".
--
-- A FIFTH FIELD WAS ADDED AFTER THE FORMAT SHIPPED, which is why it is
-- optional here: a client one version behind sends four, and dropping its
-- messages outright would make an addon that works only when both sides
-- updated on the same evening. Missing means zero, which is what every
-- reader of it already means by "no number".
function Comm.Decode(message)
    if type(message) ~= "string" then return nil end

    local version, what, kind, spell, value =
        message:match("^(%d+)|(%u+)|(%u+)|(%d*)|?(%d*)$")
    if not version then return nil end

    version = tonumber(version)
    if version ~= Comm.VERSION then return nil end

    local known = {
        [Comm.REQUEST] = true, [Comm.ACK] = true,
        [Comm.USED] = true, [Comm.READY] = true, [Comm.HELLO] = true,
    }
    if not known[what] then return nil end
    if kind ~= Comm.EXTERNAL and kind ~= Comm.TAUNT then return nil end

    local spellID = tonumber(spell) or 0

    -- An external with no spell is not an external. Everything except a
    -- TAUNT request names one.
    if kind == Comm.EXTERNAL and spellID == 0 then return nil end

    return {
        what = what, kind = kind,
        spellID = spellID > 0 and spellID or nil,
        value = tonumber(value) or 0,
    }
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
-- Which channel an ADDON message goes on. Not the same question as a chat
-- message - there is no whisper-the-healer here, the group is the audience -
-- but the same trap: a party formed by the finder is INSTANCE_CHAT and a
-- message sent to PARTY there arrives nowhere. Read from LibDurability, which
-- writes this exact line.
function Comm.Channel(inGroup, inRaid, inInstanceGroup)
    if not inGroup then return nil end
    if inInstanceGroup then return "INSTANCE_CHAT" end
    if inRaid then return "RAID" end
    return "PARTY"
end

local function Sender()
    return C_ChatInfo and C_ChatInfo.SendAddonMessage
end

-- THROTTLED PER KIND. A request is a button somebody presses twice when the
-- first press did not visibly do anything, and the group does not need to
-- carry both.
Comm.QUIET = 1.0
local lastSent = {}

function Comm.MaySend(key, now, previous, quiet)
    if not previous then return true end
    return (now - previous) >= (quiet or Comm.QUIET)
end

function Comm.Send(what, kind, spellID, value)
    local send = Sender()
    if not send then return false, "this client has no addon channel" end

    local channel = Comm.Channel(IsInGroup(), IsInRaid(),
        ns.Chat.InInstanceGroup())
    if not channel then return false, "you are not in a group" end

    -- Throttled per what-and-which-spell rather than per kind: two different
    -- cooldowns coming back in the same second are two facts, and dropping
    -- one of them would leave a slot dark that is actually ready.
    local key = what .. kind .. tostring(spellID or 0)
    local now = GetTime and GetTime() or 0
    if not Comm.MaySend(key, now, lastSent[key]) then
        return false, "just sent it"
    end
    lastSent[key] = now

    local ok = pcall(send, Comm.PREFIX,
        Comm.Encode(what, kind, spellID, value), channel)
    if not ok then return false, "the message would not go out" end
    return true
end

-- THE RAID CHECK'S TWO MESSAGES, on their own door because they are throttled
-- differently and for a different reason. An ask is a button in somebody's
-- hand and the group does not need it twice a second; an answer is a reply to
-- that ask, and forty of them arriving at once is the normal case rather than
-- a flood - so they share one bucket with a longer quiet, keyed by which of
-- the two it is.
Comm.CHECK_QUIET = 3.0

local function SendCheckMessage(message, bucket)
    local send = Sender()
    if not send then return false, "this client has no addon channel" end

    local channel = Comm.Channel(IsInGroup(), IsInRaid(),
        ns.Chat.InInstanceGroup())
    if not channel then return false, "you are not in a group" end

    local now = GetTime and GetTime() or 0
    if not Comm.MaySend(bucket, now, lastSent[bucket], Comm.CHECK_QUIET) then
        return false, "just sent it"
    end
    lastSent[bucket] = now

    local ok = pcall(send, Comm.PREFIX, message, channel)
    if not ok then return false, "the message would not go out" end
    return true
end

function Comm.AskCheck()
    return SendCheckMessage(Comm.EncodeCheckAsk(), "CHECKASK")
end

function Comm.SendCheck(fields)
    return SendCheckMessage(Comm.EncodeCheck(fields), "CHECKSAY")
end

---------------------------------------------------------------------------
-- Receiving
--
-- Listeners rather than a hard-coded call into the answer bar: the bar is a
-- module and can be switched off, and a channel that only works when one
-- particular feature is running is a channel with a hidden dependency.
---------------------------------------------------------------------------
local listeners = {}

function Comm.Listen(fn)
    listeners[#listeners + 1] = fn
end

-- Exposed for the same reason Taunts.OnCast is: the desktop harness cannot
-- fire an event, and a delivery path that has never run is a delivery path
-- that runs for the first time in a dungeon.
function Comm.OnMessage(prefix, message, _, sender)
    if prefix ~= Comm.PREFIX then return end
    if not sender or sender == "" then return end

    -- YOUR OWN MESSAGE COMES BACK TO YOU. Every group channel echoes, and
    -- without this the person asking would light up their own answer bar and
    -- be told they can save themselves. The FULL name decides what is an
    -- echo: a group-mate on another realm may legitimately carry this
    -- character's short name, and dropping their messages would silently
    -- lose every answer they ever send.
    local me = Comm.FullName(UnitName("player"))
    if me and Comm.FullName(sender) == me then return end
    local short = sender:match("^([^%-]+)") or sender

    -- TWO WIRE FORMS, TRIED IN AGE ORDER. The spell form is the one nearly
    -- every message on this channel is; the raid check's is deliberately
    -- shaped so the first decoder rejects it, which is also how a client that
    -- predates it behaves - it simply stops here.
    local packet = Comm.Decode(message) or Comm.DecodeCheck(message)
    if not packet then return end

    packet.from = sender
    packet.fromShort = short

    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, packet)
        if not ok then geterrorhandler()(err) end
    end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("CHAT_MSG_ADDON")
watcher:SetScript("OnEvent", function(_, _, prefix, message, channel, sender)
    Comm.OnMessage(prefix, message, channel, sender)
end)

-- REGISTERED ONCE, AT LOAD. Not from a module's Boot: an unregistered prefix
-- means every message is dropped before any addon code sees it, and a channel
-- that depends on which features somebody switched on is a channel that works
-- for one of you and not the other.
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, Comm.PREFIX)
end
