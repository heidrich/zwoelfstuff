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
            send(text, where.channel, nil,
                where.channel == "WHISPER" and whisperTo or nil)
        end
        note = note or where.note
    end

    return true, note
end
