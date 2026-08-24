---------------------------------------------------------------------------
-- DURABILITY OVER THE COMMON WIRE
--
-- Gear can be inspected and buffs can sometimes be read; durability can
-- not - no API answers it about another player. Every raid tool settled on
-- the same fix years ago: LibDurability, a tiny shared channel that MRT,
-- BigWigs and friends embed. Anybody running ANY of them answers a ready
-- check with their own number, unasked - which is why an MRT window shows
-- durability for people who have never heard of MRT.
--
-- This file SPEAKS that protocol instead of embedding the library. The copy
-- on this machine carries no licence line to copy it under, and the protocol
-- itself is three facts, read from MRT/libs/LibDurability/LibDurability.lua:
--
--     prefix "LibDRBLT", a request is the letter R,
--     an answer is "percent,broken" as two integers,
--     and a channel holds four seconds between sends.
--
-- TWO DIALECTS OF "PERCENT", kept apart on purpose. The lib's number is the
-- sum of all current durability over the sum of all maximums; this addon's
-- own window shows the WORST slot, because the weapon about to break is the
-- question. On the lib's wire we speak the lib's dialect - a reader over
-- there expects it - and our own wire keeps ours.
--
-- IF A REAL COPY IS LOADED (the user also runs MRT or BigWigs), this file
-- goes quiet as a sender - two answers from one machine is noise - and keeps
-- reading. The check is made at send time, not load time, because addon
-- load order is nobody's promise.
---------------------------------------------------------------------------
local _, ns = ...

local Durability = {}
ns.Durability = Durability

Durability.PREFIX = "LibDRBLT"

-- The lib's own pace. Slower than our Comm throttle because the channel is
-- shared with every other addon speaking it.
Durability.QUIET = 4.0

---------------------------------------------------------------------------
-- OUR OWN NUMBER, in the lib's dialect.
---------------------------------------------------------------------------
function Durability.Read()
    if type(GetInventoryItemDurability) ~= "function" then return nil end
    local current, maximum, broken = 0, 0, 0
    for slot = 1, 18 do
        local ok, here, top = pcall(GetInventoryItemDurability, slot)
        if ok and here and top then
            current = current + here
            maximum = maximum + top
            if top > 0 and here == 0 then broken = broken + 1 end
        end
    end
    if maximum == 0 then return nil end
    return math.floor(current / maximum * 100 + 0.5), broken
end

---------------------------------------------------------------------------
-- WHAT THE GROUP SAID. Keyed by the full name the raid check keys by, and
-- wiped when a check is asked - the same staleness rule as every other
-- answer on that window.
---------------------------------------------------------------------------
local heard = {}

function Durability.Of(key)
    return key and heard[key] or nil
end

function Durability.Forget()
    for key in pairs(heard) do heard[key] = nil end
end

local function Now()
    return (GetTime and GetTime()) or 0
end

---------------------------------------------------------------------------
-- SENDING. One quiet clock per purpose, the lib's four seconds.
---------------------------------------------------------------------------
local lastSent = {}

-- True when another addon brought the real library. Then IT answers for
-- this machine and a second voice would only double every message.
function Durability.RealLibLoaded()
    if type(LibStub) ~= "table" or type(LibStub.GetLibrary) ~= "function" then
        return false
    end
    local ok, lib = pcall(LibStub.GetLibrary, LibStub, "LibDurability", true)
    return (ok and lib ~= nil) and true or false
end

local function Channel()
    if not ns.Comm then return nil end
    return ns.Comm.Channel(IsInGroup(), IsInRaid(), ns.Chat.InInstanceGroup())
end

local function Send(message, bucket)
    local send = C_ChatInfo and C_ChatInfo.SendAddonMessage
    if not send then return false end
    local channel = Channel()
    if not channel then return false end

    local now = Now()
    local previous = lastSent[bucket]
    if previous and now - previous < Durability.QUIET then return false end
    lastSent[bucket] = now

    return pcall(send, Durability.PREFIX, message, channel) and true or false
end

-- Our own number onto the shared wire - the ready-check broadcast and the
-- answer to somebody's R are the same sentence.
function Durability.Say()
    if Durability.RealLibLoaded() then return false end
    -- A switched-off feature that still talks is a feature that is not
    -- switched off - the same gate the raid check's own answers stand behind.
    if not (ns.Modules and ns.Modules:IsOn("raidbar")) then return false end
    local percent, broken = Durability.Read()
    if not percent then return false end
    return Send(string.format("%d,%d", percent, broken or 0), "SAY")
end

-- Ask the room. Everybody with the lib answers, whatever addon carried it.
function Durability.Request()
    return Send("R", "ASK")
end

---------------------------------------------------------------------------
-- RECEIVING. Exported whole, because a delivery path that has never run is
-- a delivery path that runs for the first time in a raid.
---------------------------------------------------------------------------
-- Which rooms the shared wire listens to. The real library gates on the
-- same three; anything else - a WHISPER from a stranger above all - is
-- somebody else's conversation and gets no answer and no row.
local CHANNELS = { RAID = true, PARTY = true, INSTANCE_CHAT = true }

function Durability.OnMessage(prefix, message, channel, sender)
    if prefix ~= Durability.PREFIX then return nil end
    if type(message) ~= "string" then return nil end
    if not sender or sender == "" then return nil end
    if not CHANNELS[channel] then return nil end

    -- The FULL name decides what is an echo: a group-mate on another
    -- realm may legitimately carry this character's name, and dropping
    -- their answers as our own would leave their row waiting all evening.
    local me = ns.Comm.FullName(UnitName and UnitName("player") or nil)
    local full = ns.Comm.FullName(sender)
    local mine = me ~= nil and full == me

    if message == "R" then
        -- Somebody asked the room. Answering includes answering an MRT
        -- player's window - which is the other half of "works without the
        -- addon on the other side".
        if not mine then Durability.Say() end
        return "request"
    end

    local percent, broken = message:match("^(%d+),(%d+)$")
    if not percent then return nil end
    -- The dialect never exceeds a whole kit or eighteen slots. A wider
    -- number is a lie or a mistake; either way it is not shown.
    percent, broken = tonumber(percent), tonumber(broken)
    if percent > 100 or broken > 18 then return nil end
    if mine then return "mine" end
    if not full then return nil end

    heard[full] = {
        at = Now(),
        percent = percent,
        broken = broken,
    }
    if ns.RaidCheck then ns.RaidCheck:Refresh() end
    return "heard"
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("CHAT_MSG_ADDON")
watcher:RegisterEvent("READY_CHECK")
watcher:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4)
    if event == "READY_CHECK" then
        -- The lib broadcasts on every ready check without being asked, and
        -- so do we: it is the moment every window over there is looking.
        Durability.Say()
        return
    end
    Durability.OnMessage(arg1, arg2, arg3, arg4)
end)

-- Registered at load, like every prefix: unregistered means dropped before
-- any addon code sees it. Registering a prefix the real lib also registers
-- is harmless - the second call is a no-op.
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, Durability.PREFIX)
end
