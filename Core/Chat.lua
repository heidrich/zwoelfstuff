---------------------------------------------------------------------------
-- Chat - the one answer to "which channel am I actually in".
--
-- This was written inside the externals panel, where it worked and was
-- tested. It is here because it is about to have a SECOND caller: the taunt
-- announce, and the kick rotation after it. A second copy of these rules
-- would be a second thing to get wrong, and the one that matters is not
-- obvious enough to get right twice:
--
--   /p IS NOT PARTY CHAT IN A DUNGEON FROM THE GROUP FINDER. That group
--   talks on INSTANCE_CHAT, and a message sent to PARTY there arrives
--   NOWHERE - silently, which is the worst way for a "tell the healer"
--   button to fail. IsInGroup(2) is the test, taken from BigWigs, which
--   picks its channel exactly this way in shipping code.
--
-- Everything here that decides something is PURE and takes the world as
-- arguments, because a five-man where you have assist and a raid where you
-- do not are not states a self test can arrange in game.
---------------------------------------------------------------------------
local _, ns = ...

local Chat = {}
ns.Chat = Chat

-- The five a player picks from. "GROUP" is one entry rather than three, and
-- that is the whole reason it exists - see the header.
Chat.CHANNELS = {
    { value = "WHISPER",      text = "Whisper" },
    { value = "GROUP",        text = "Party or raid",
      long = "Whichever group you are actually in" },
    { value = "RAID_WARNING", text = "Raid warning", long = "Needs lead or assist" },
    { value = "SAY",          text = "Say" },
    { value = "YELL",         text = "Yell" },
}

-- The channel a message would actually be sent on, and why not, when not.
-- Its own function so a page can say "you are not in a group" before you
-- press anything rather than after.
function Chat.ResolveChannel(choice, inGroup, inRaid, inInstanceGroup, canWarn)
    choice = choice or "WHISPER"
    if choice == "WHISPER" then return "WHISPER" end

    if choice == "SAY" or choice == "YELL" then return choice end

    if not inGroup then
        return nil, "you are not in a group"
    end

    if choice == "RAID_WARNING" then
        if not inRaid then
            -- Not an error worth refusing over: outside a raid the warning
            -- channel does not exist, and the message still wants to arrive.
            return inInstanceGroup and "INSTANCE_CHAT" or "PARTY",
                "no raid, sent to the group instead"
        end
        if not canWarn then
            return "RAID", "not lead or assist, sent to raid chat instead"
        end
        return "RAID_WARNING"
    end

    -- "GROUP"
    if inInstanceGroup then return "INSTANCE_CHAT" end
    if inRaid then return "RAID" end
    return "PARTY"
end

-- Every channel one press would actually go out on, in the order they are
-- listed, with duplicates removed.
--
-- The de-duplication is not tidiness: "Raid warning" and "Party or raid" both
-- resolve to RAID for somebody without assist, and sending the same sentence
-- to the same channel twice is a person spamming their own group because of
-- a setting they thought was two different things.
function Chat.SendingTo(chosen, inGroup, inRaid, inInstanceGroup, canWarn)
    local out, seen = {}, {}
    for _, entry in ipairs(Chat.CHANNELS) do
        if chosen[entry.value] then
            local channel, note = Chat.ResolveChannel(entry.value,
                inGroup, inRaid, inInstanceGroup, canWarn)
            if channel and not seen[channel] then
                seen[channel] = true
                out[#out + 1] = { channel = channel, note = note }
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- The world, read once
---------------------------------------------------------------------------
-- LE_PARTY_CATEGORY_INSTANCE. The constant is not guaranteed to exist under
-- that name on every client, and BigWigs writes the literal 2 for the same
-- reason - so the name is used when it is there and the number when it is not.
function Chat.InInstanceGroup()
    local category = LE_PARTY_CATEGORY_INSTANCE or 2
    return IsInGroup(category) and true or false
end

function Chat.CanWarn()
    return (UnitIsGroupLeader and UnitIsGroupLeader("player"))
        or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))
        or false
end

-- SendingTo against the group you are standing in right now.
function Chat.Where(chosen)
    return Chat.SendingTo(chosen or {}, IsInGroup(), IsInRaid(),
        Chat.InInstanceGroup(), Chat.CanWarn())
end

---------------------------------------------------------------------------
-- Writing the sentence
---------------------------------------------------------------------------
-- %s, %n, %t - whatever the caller offers. One PASS, with a function as the
-- replacement, and both halves of that are deliberate:
--
--   one pass    a spell called "Blessing of %n" cannot be read as a
--               placeholder by the next substitution, because there is no
--               next substitution.
--   a function  Lua only reads % in a replacement STRING. A function's return
--               value goes in exactly as it is, so nothing has to be escaped
--               and the "%%" dance disappears.
--
-- The trap this replaces cost a whole session's messages: gsub answers the
-- string AND a count, and handing that pair straight to another gsub makes
-- the count its LIMIT - "replace at most 0 times". Every message went out
-- with a literal %s in it and the code looked perfect.
--
-- A placeholder nobody filled comes OUT, and the space it sat in goes with
-- it - or the sentence keeps a hole where the name should have been.
function Chat.Fill(text, values)
    values = values or {}

    local filled = text:gsub("%%(%a)", function(key)
        local value = values[key]
        if value == nil then return "\1" .. key end
        return tostring(value)
    end)

    filled = filled:gsub("%s*\1%a%s*", " ")
    filled = filled:gsub("^%s+", "")
    return (filled:gsub("%s+$", ""))
end

---------------------------------------------------------------------------
-- Saying it
---------------------------------------------------------------------------
-- C_ChatInfo first, the global as the fallback. The bare one is deprecated on
-- this patch - BigWigs' loader takes the namespaced version outright,
-- ChatThrottleLib takes it with exactly this fallback.
function Chat.Sender()
    ---@diagnostic disable-next-line: deprecated
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if type(send) ~= "function" then return nil end
    return send
end

---------------------------------------------------------------------------
-- WHEN THE CLIENT REFUSES
--
-- 2026-08-14, out of his BugSack, twice:
--
--   [ADDON_ACTION_BLOCKED] AddOn 'ZwoelfStuff' tried to call the protected
--   function 'UNKNOWN()'      ... Chat.lua:174 in function 'Post'
--                             ... Externals.lua in function 'Ask'
--
-- A BLOCK IS NOT A LUA ERROR AND pcall CANNOT SEE IT. The client refuses the
-- call and fires an event; the send returns as if nothing happened. So the
-- addon listens for that event and says what it was doing when it arrived -
-- otherwise the only account of it is a stack trace in somebody's error
-- window, which is how a refused whisper reads as "the button does nothing".
--
-- WHAT IS KNOWN AND WHAT IS NOT, kept apart on purpose:
--   * Known: his externals config has WHISPER on and nothing else, so it is
--     not the SAY/YELL restriction. Read out of his saved variables, not
--     guessed.
--   * Known: the destination was the SHORT name. The roster computes a
--     NAME-REALM `fullName` precisely because a short name addresses nobody
--     across a realm border, and Externals.Ask was handing the short one to
--     the whisper. That is a real defect and it is fixed - independently of
--     whether it is THIS one.
--   * A clue, not a fact: the client names a blocked GLOBAL, so a nameless
--     `UNKNOWN()` points at a function inside a C_ namespace - which would be
--     C_ChatInfo.SendChatMessage rather than the plain global. But BigWigs's
--     loader and ChatThrottleLib both take that same namespaced door in
--     shipping code, so it is not proof, and nothing here is flipped on it.
--
-- `/zs chat probe` is what settles it, and it asks HIS client rather than me.
---------------------------------------------------------------------------
local lastSend
local lastBlocked

function Chat.LastSend() return lastSend end
function Chat.LastBlocked() return lastBlocked end

-- Pure: the sentence said when the client refuses a send it has already been
-- handed. Its own function so the wording can be read back in a check.
function Chat.BlockedLine(attempt)
    if type(attempt) ~= "table" then
        return "The game refused a chat message from this addon. Run "
            .. "|cffffd100/zs chat probe|r and paste what it prints."
    end
    local where = attempt.channel or "?"
    if attempt.to then where = where .. " to " .. attempt.to end
    return string.format("The game refused to send that message (%s). "
        .. "Nothing was sent. Run |cffffd100/zs chat probe|r and paste what "
        .. "it prints.", where)
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_ACTION_BLOCKED")
watcher:SetScript("OnEvent", function(_, _, addon)
    if addon ~= "ZwoelfStuff" then return end
    -- Only when WE were mid-send. The same event fires for anything else the
    -- client refuses us, and claiming every one of those was a chat message
    -- would send the next person looking in the wrong file.
    local attempt = lastSend
    if not (attempt and GetTime and (GetTime() - attempt.at) < 1) then return end
    -- KEPT, not just reported: the probe used to eat its own evidence -
    -- wiping the attempt here meant the very probe the refusal asks for
    -- could no longer print what was refused (owner's 2026-08-24 paste
    -- showed a healthy client and no attempt line, which reads as "nothing
    -- happened" about a send that was refused seconds earlier).
    lastBlocked = attempt
    lastSend = nil
    ns.Print("|cffff8040" .. Chat.BlockedLine(attempt) .. "|r")
end)

-- One sentence, onto every channel in `going`. Answers whether anything went
-- out, and the note the resolver left - "not lead or assist, sent to raid
-- chat instead" is worth repeating to the person who pressed the button.
function Chat.Post(text, going, whisperTo)
    local send = Chat.Sender()
    if not send then return false, "this client has no way to send a chat message" end
    if not going or #going == 0 then return false, "there is nowhere to send it" end

    local note
    for _, where in ipairs(going) do
        if where.channel == "WHISPER" and not whisperTo then
            -- Nobody to whisper. Dropped rather than sent to nobody, and the
            -- other channels still carry it.
        else
            -- Written down BEFORE the call, because a block arrives while the
            -- call is still running and there is nothing to read afterwards.
            lastSend = {
                at = (GetTime and GetTime()) or 0,
                channel = where.channel,
                to = where.channel == "WHISPER" and whisperTo or nil,
            }
            send(text, where.channel, nil,
                where.channel == "WHISPER" and whisperTo or nil)
        end
        note = note or where.note
    end

    return true, note
end

---------------------------------------------------------------------------
-- THE PROBE
--
-- The same move that unblocked the group death log: stop reasoning about
-- what a client does and ask it. Everything here is READ - no message is
-- sent, because a probe that spams his group to learn something is a worse
-- probe than one that does not.
---------------------------------------------------------------------------
function Chat.Probe()
    ns.Print("|cffffd100chat probe|r")

    ---@diagnostic disable-next-line: deprecated
    local plain = SendChatMessage
    local spaced = C_ChatInfo and C_ChatInfo.SendChatMessage
    ns.Print(string.format("  send paths: global %s, C_ChatInfo %s",
        type(plain) == "function" and "|cff40ff40there|r" or "|cffff4040gone|r",
        type(spaced) == "function" and "|cff40ff40there|r" or "|cffff4040gone|r"))
    ns.Print("  we take: " .. (spaced and "C_ChatInfo.SendChatMessage"
        or "the global"))

    -- WHETHER THE CLIENT CONSIDERS EITHER OF THEM TAINTED. This is the line
    -- that decides it: a secure variable an addon may not call is exactly
    -- what an ADDON_ACTION_BLOCKED is about.
    if issecurevariable then
        local okPlain = select(1, issecurevariable("SendChatMessage"))
        ns.Print("  global secure: " .. tostring(okPlain))
        if C_ChatInfo then
            local okSpaced = select(1,
                issecurevariable(C_ChatInfo, "SendChatMessage"))
            ns.Print("  C_ChatInfo secure: " .. tostring(okSpaced))
        end
    end

    -- WHO WE WOULD ADDRESS, in both spellings, because the short one is what
    -- was being used and the full one is what a cross-realm whisper needs.
    local roster = ns.Roster and ns.Roster() or {}
    ns.Print(string.format("  group: %d readable", #roster))
    for _, member in ipairs(roster) do
        ns.Print(string.format("    %s  |cff888888full:|r %s  |cff888888%s|r",
            tostring(member.name), tostring(member.fullName),
            tostring(member.class)))
    end

    -- AND WHERE A REQUEST WOULD GO right now, resolved against the group he
    -- is actually standing in.
    local cfg = ns.Externals and ns.Externals.Config()
    local chosen = (cfg and cfg.channels) or {}
    local picked = {}
    for value in pairs(chosen) do picked[#picked + 1] = value end
    table.sort(picked)
    ns.Print("  channels switched on: "
        .. (#picked > 0 and table.concat(picked, ", ") or "none"))
    for _, where in ipairs(Chat.Where(chosen)) do
        ns.Print(string.format("    -> %s%s", where.channel,
            where.note and ("  |cff888888" .. where.note .. "|r") or ""))
    end

    local last = Chat.LastSend()
    if last then
        ns.Print(string.format("  last attempt: %s%s", last.channel or "?",
            last.to and (" to " .. last.to) or ""))
    end
    local blocked = Chat.LastBlocked()
    if blocked then
        ns.Print(string.format("  |cffff8040last refused:|r %s%s",
            blocked.channel or "?",
            blocked.to and (" to " .. blocked.to) or ""))
    end
end
