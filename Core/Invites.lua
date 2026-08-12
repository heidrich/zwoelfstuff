---------------------------------------------------------------------------
-- Invites - the group fills itself while you are doing something else.
--
-- Owner, 2026-08-12: "Das naechste feature unter m+ und raids ist das invite
-- tool. ein paar einstellungen, welche es erlauben key woerter festzulegen,
-- wenn mich jemand mit inv oder invite etc anwispert, wird die person direkt
-- in die gruppe oder raid eingeladen."
--
-- EVERYTHING IN HERE IS OFF UNTIL IT IS SWITCHED ON, and that is not caution
-- for its own sake. Every other feature in this addon draws something; this
-- one ACTS ON ITS OWN, in your name, at people who are not in the room. A
-- switch that arrives already on would mean an update started inviting
-- strangers into somebody's raid, and there is no way to take that back.
--
-- So the module may be on and still do nothing at all: the keyword listener,
-- the auto-accept and the auto-promote each carry their own switch and each
-- starts at off. The page says so on the page rather than in a tooltip.
--
-- WHAT IS ACTUALLY ALLOWED. Inviting, promoting, uninviting and accepting are
-- all plain calls - the game lets an addon do them, and refuses when you have
-- no lead, which is a refusal that cannot go stale. What it does NOT allow is
-- reading a whisper you were not sent, so everything here starts from a
-- message that arrived at your own client.
--
-- READ, NOT REMEMBERED: the call names below are MRT's InviteTool.lua on this
-- machine - C_PartyInfo.InviteUnit with the old InviteUnit behind it,
-- C_PartyInfo.ConvertToRaid, GetGuildRosterInfo, AcceptGroup - because it is
-- maintained against the live game and this addon has lost two evenings to
-- API names quoted from memory.
---------------------------------------------------------------------------
local _, ns = ...

local Invites = {}
ns.Invites = Invites

-- HOW MANY ARE SENT IN ONE GO. Forty is a full raid; anything above it is a
-- loop that cannot succeed and a server that starts refusing.
Invites.MAX_INVITES = 40

Invites.DEFAULT_KEYWORDS = "inv\ninvite\n1"

---------------------------------------------------------------------------
-- Configuration
---------------------------------------------------------------------------
function Invites.Config()
    ns.db.invites = ns.db.invites or {}
    local cfg = ns.db.invites

    -- The keyword TEXT is what the box holds and what is stored - one word a
    -- line, exactly as typed. The SET is derived; storing the set instead
    -- would lose the order and the spelling somebody typed.
    if cfg.keywords == nil then cfg.keywords = Invites.DEFAULT_KEYWORDS end

    cfg.promote = cfg.promote or ""
    cfg.lastGroup = cfg.lastGroup or {}

    return cfg
end

---------------------------------------------------------------------------
-- THE KEYWORDS
--
-- Pure, both ways, and tested - because the whole feature is one string
-- comparison and getting it wrong is either a raid nobody can join or a raid
-- that invites everybody who says hello.
--
-- A word is trimmed and lower-cased on both sides. Punctuation is stripped
-- from the MESSAGE only: "inv!" and "inv?" are the same request, and somebody
-- who deliberately types a keyword with a comma in it should get it back.
---------------------------------------------------------------------------
function Invites.Keywords(text)
    local set, order = {}, {}
    for raw in tostring(text or ""):gmatch("[^\r\n,]+") do
        -- Its own local rather than assigning to the loop variable: a for
        -- control variable is const on the Lua the desktop harness runs, and
        -- the client's 5.1 would have taken it silently.
        local word = raw:lower():gsub("^%s+", ""):gsub("%s+$", "")
        if word ~= "" and not set[word] then
            set[word] = true
            order[#order + 1] = word
        end
    end
    return set, order
end

-- Does this message ask for an invite?
--
-- STRICT BY DEFAULT: the whole message has to BE the keyword. Loose matching
-- finds it anywhere, which is what somebody typing "inv pls" wants and also
-- what makes "I will not invite you" an invitation. The switch is on the page
-- with both halves of that written out.
function Invites.Matches(message, set, loose)
    if type(message) ~= "string" then return false end

    local text = message:lower():gsub("^%s+", ""):gsub("%s+$", "")
    -- Trailing punctuation only. A word with a full stop after it is the same
    -- word; one with a hyphen inside it is not.
    text = text:gsub("[%.%!%?,;:]+$", "")
    if text == "" then return false end

    if set[text] then return true end
    if not loose then return false end

    for word in text:gmatch("[%a%d]+") do
        if set[word] then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Who may be invited
---------------------------------------------------------------------------
function Invites.InGuild(name)
    if not (IsInGuild and IsInGuild()) then return false end
    if not (GetNumGuildMembers and GetGuildRosterInfo) then return false end

    local short = tostring(name or ""):match("^([^%-]+)") or name
    for index = 1, (GetNumGuildMembers() or 0) do
        local member = GetGuildRosterInfo(index)
        if member then
            local memberShort = member:match("^([^%-]+)") or member
            if member == name or memberShort == short then return true end
        end
    end
    return false
end

function Invites.IsFriend(name)
    local short = tostring(name or ""):match("^([^%-]+)") or name

    if C_FriendList and C_FriendList.GetNumFriends then
        for index = 1, (C_FriendList.GetNumFriends() or 0) do
            local info = C_FriendList.GetFriendInfoByIndex(index)
            local friend = info and info.name
            if friend then
                local friendShort = friend:match("^([^%-]+)") or friend
                if friend == name or friendShort == short then return true end
            end
        end
    end
    return false
end

-- Pure: given what is known about a person and the settings, may they in?
-- Its own function so the rule can be read in one place and checked without
-- a guild.
function Invites.MayInvite(cfg, isGuild, isFriend)
    if cfg.guildOnly and not isGuild then
        return false, "not in your guild"
    end
    if cfg.friendsOnly and not (isFriend or isGuild) then
        return false, "not a friend"
    end
    return true
end

---------------------------------------------------------------------------
-- Inviting
---------------------------------------------------------------------------
local function InviteCall(name)
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        return pcall(C_PartyInfo.InviteUnit, name)
    end
    if InviteUnit then return pcall(InviteUnit, name) end
    return false
end

-- FIVE IS THE WALL. A party holds five, so the sixth invite goes nowhere at
-- all unless the party has been made into a raid first - which is the one
-- step everybody forgets and then blames the addon for.
local function ConvertIfNeeded()
    if not Invites.Config().convertAtFive then return end
    if IsInRaid and IsInRaid() then return end
    if not (GetNumGroupMembers and GetNumGroupMembers() >= 5) then return end
    -- The conversion is protected during a fight on 12.x, the same rule the
    -- raid bar's buttons live under.
    if InCombatLockdown and InCombatLockdown() then return end
    if C_PartyInfo and C_PartyInfo.ConvertToRaid then
        pcall(C_PartyInfo.ConvertToRaid)
    end
end

function Invites.Invite(name, why)
    if not name or name == "" then return false end
    ConvertIfNeeded()
    local ok = InviteCall(name)
    if ok and Invites.Config().announce ~= false then
        ns.Print(ns.L("Invited %s.", name)
            .. (why and (" |cff888888" .. why .. "|r") or ""))
    end
    return ok
end

---------------------------------------------------------------------------
-- The listener
--
-- One handler for all four chat events. They differ only in which switch
-- allows them, and writing four would be four chances for one of them to fall
-- behind the rule - which is exactly what a copy of a rule does.
---------------------------------------------------------------------------
function Invites.OnMessage(message, sender, source)
    if not ns.Modules:IsOn("invites") then return false end

    local cfg = Invites.Config()
    if not cfg.onWhisper then return false end
    if source ~= "WHISPER" and not cfg.onSayYell then return false end

    -- A NAME THAT CAME BACK SECRET IS NOT A NAME. 12.x withholds them in
    -- places, and a secret cannot be compared, concatenated or used as a
    -- table key - which is three of the four things done with it below.
    if not (ns.CanCompute(sender) and type(sender) == "string") then
        return false
    end

    -- Your own message, echoed. Inviting yourself is a refusal in the client
    -- and a puzzled line in the chat frame.
    local me = UnitName and UnitName("player")
    local short = sender:match("^([^%-]+)") or sender
    if me and (sender == me or short == me) then return false end

    local set = Invites.Keywords(cfg.keywords)
    if not Invites.Matches(message, set, cfg.looseMatch) then return false end

    local isGuild = Invites.InGuild(sender)
    local may, refusal = Invites.MayInvite(cfg, isGuild,
        Invites.IsFriend(sender))
    if not may then
        -- SAID OUT LOUD, once. Somebody whispered and nothing happened is the
        -- worst outcome here: they are standing at the summoning stone
        -- wondering whether to whisper again.
        ns.Print(string.format("|cff888888%s asked for an invite - %s.|r",
            sender, refusal))
        return false
    end

    Invites.Invite(sender, source == "WHISPER" and "whisper" or "say")
    return true
end

-- WHO TO PROMOTE, and it is not a free-for-all: only the names typed in the
-- box, matched short or full. A raid where everybody is an assistant is a raid
-- where anybody can pull.
function Invites.ShouldPromote(name, listText)
    if not name then return false end
    local set = Invites.Keywords(listText)
    local short = tostring(name):match("^([^%-]+)") or name
    return (set[tostring(name):lower()] or set[short:lower()]) and true or false
end

local function PromotePass()
    local cfg = Invites.Config()
    if not cfg.autoPromote then return end
    if not (IsInRaid and IsInRaid()) then return end
    if not (UnitIsGroupLeader and ns.Truth(UnitIsGroupLeader("player"), false)) then
        return
    end
    if not PromoteToAssistant then return end

    for _, member in ipairs(ns.Roster()) do
        if not member.isPlayer and Invites.ShouldPromote(member.name, cfg.promote)
            and not ns.Truth(UnitIsGroupAssistant
                and UnitIsGroupAssistant(member.unit), false) then
            pcall(PromoteToAssistant, member.fullName or member.name)
        end
    end
end

---------------------------------------------------------------------------
-- The things with buttons
---------------------------------------------------------------------------
-- REMEMBERED BEFORE IT IS EMPTIED. "Disband and invite everyone back" is one
-- gesture in two presses, and the list has to survive the first one.
function Invites.Remember()
    local cfg = Invites.Config()
    local kept = {}
    for _, member in ipairs(ns.Roster()) do
        if not member.isPlayer then
            kept[#kept + 1] = member.fullName or member.name
        end
    end
    cfg.lastGroup = kept
    return #kept
end

function Invites.Disband()
    if not UninviteUnit then return 0 end
    local count = Invites.Remember()
    if count == 0 then
        ns.Print("|cff888888" .. ns.L["The group is empty."] .. "|r")
        return 0
    end
    for _, name in ipairs(Invites.Config().lastGroup) do
        pcall(UninviteUnit, name)
    end
    ns.Print(string.format("|cffffd100%s|r %d.", ns.L["Disband"], count))
    return count
end

function Invites.InviteBack()
    local kept = Invites.Config().lastGroup or {}
    if #kept == 0 then
        ns.Print("|cff888888" .. ns.L["Nobody to invite back."] .. "|r")
        return 0
    end
    local sent = 0
    for _, name in ipairs(kept) do
        if sent >= Invites.MAX_INVITES then break end
        InviteCall(name)
        sent = sent + 1
    end
    ns.Print(string.format("|cffffd100%s|r %d.", ns.L["Invite"], sent))
    return sent
end

-- Whether a guild rank passes the filter. Rank 0 is the guild master and the
-- numbers grow downwards, which is the opposite of what everybody expects -
-- so this is its own named function rather than a comparison written four
-- times with the sign guessed at.
function Invites.RankAllowed(rankIndex, maxRank)
    if maxRank == nil then return true end
    if type(rankIndex) ~= "number" then return false end
    return rankIndex <= maxRank
end

function Invites.GuildRanks()
    local out = {}
    if not (GuildControlGetNumRanks and GuildControlGetRankName) then
        return out
    end
    for index = 1, (GuildControlGetNumRanks() or 0) do
        out[#out + 1] = { index = index - 1, name = GuildControlGetRankName(index) }
    end
    return out
end

function Invites.InviteGuild()
    if not (IsInGuild and IsInGuild()) then
        ns.Print("|cffff8040You are not in a guild.|r")
        return 0
    end
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        pcall(C_GuildInfo.GuildRoster)
    end

    local cfg = Invites.Config()
    local me = UnitName and UnitName("player")
    local sent = 0

    for index = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
        if sent >= Invites.MAX_INVITES then break end
        local name, _, rankIndex, _, _, _, _, _, online, _, _, _, _, isMobile =
            GetGuildRosterInfo(index)
        local short = name and (name:match("^([^%-]+)") or name)
        if name and online and not isMobile and short ~= me
            and Invites.RankAllowed(rankIndex, cfg.maxRank) then
            ConvertIfNeeded()
            InviteCall(name)
            sent = sent + 1
        end
    end

    ns.Print(string.format("|cffffd100%s|r %d.", ns.L["Invite the guild"], sent))
    return sent
end

---------------------------------------------------------------------------
-- Being invited
---------------------------------------------------------------------------
-- Pure: should this invitation be accepted on its own? Its own function
-- because the answer is a policy and policies belong somewhere they can be
-- read - and because "accept from friends" quietly meaning "accept from
-- anybody in your guild too" is the sort of thing that has to be deliberate.
function Invites.ShouldAccept(cfg, isFriend, isGuild)
    if not cfg.autoAccept then return false end
    return (isFriend or isGuild) and true or false
end

local function OnInvited(name)
    if not ns.Modules:IsOn("invites") then return end
    if not (ns.CanCompute(name) and type(name) == "string") then return end

    local cfg = Invites.Config()
    if not Invites.ShouldAccept(cfg, Invites.IsFriend(name),
        Invites.InGuild(name)) then
        return
    end

    if AcceptGroup then pcall(AcceptGroup) end

    -- THE POPUP STAYS ON SCREEN OTHERWISE, asking a question that has been
    -- answered. Four of them can be up at once; the one that matters is
    -- whichever is showing a party invite.
    for index = 1, 4 do
        local popup = _G["StaticPopup" .. index]
        if popup and popup:IsVisible()
            and (popup.which == "PARTY_INVITE"
                or popup.which == "PARTY_INVITE_XREALM") then
            popup.inviteAccepted = true
            if StaticPopup_Hide then StaticPopup_Hide(popup.which) end
            break
        end
    end
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("CHAT_MSG_WHISPER")
watcher:RegisterEvent("CHAT_MSG_BN_WHISPER")
watcher:RegisterEvent("CHAT_MSG_SAY")
watcher:RegisterEvent("CHAT_MSG_YELL")
watcher:RegisterEvent("PARTY_INVITE_REQUEST")
watcher:RegisterEvent("GROUP_ROSTER_UPDATE")

watcher:SetScript("OnEvent", function(_, event, ...)
    if not ns.db then return end

    if event == "PARTY_INVITE_REQUEST" then
        OnInvited((...))

    elseif event == "GROUP_ROSTER_UPDATE" then
        PromotePass()

    elseif event == "CHAT_MSG_BN_WHISPER" then
        -- A REAL-ID WHISPER NAMES AN ACCOUNT, NOT A CHARACTER, and an account
        -- cannot be invited - which is why this is not simply the whisper
        -- branch with a different event name. What CAN be done is telling
        -- them so, once, rather than swallowing the request.
        local message, sender = ...
        if ns.Modules:IsOn("invites") and Invites.Config().onWhisper
            and ns.CanCompute(message) then
            local set = Invites.Keywords(Invites.Config().keywords)
            if Invites.Matches(message, set, Invites.Config().looseMatch) then
                ns.Print(string.format(
                    "|cff888888%s asked over Battle.net - invite them by "
                    .. "character name.|r", tostring(sender or "?")))
            end
        end

    else
        local message, sender = ...
        Invites.OnMessage(message, sender,
            event == "CHAT_MSG_WHISPER" and "WHISPER" or "SAYYELL")
    end
end)

---------------------------------------------------------------------------
-- /zs invite
---------------------------------------------------------------------------
function Invites:Dump()
    local cfg = Invites.Config()
    ns.Print("|cffffd100invites|r - what is listening, and to what.")

    if not ns.Modules:IsOn("invites") then
        ns.Print("  |cffff4040The Invites module is switched off.|r")
    end

    local _, order = Invites.Keywords(cfg.keywords)
    ns.Print(string.format("  keywords: %s (%s)",
        #order > 0 and table.concat(order, ", ") or "none",
        cfg.looseMatch and "anywhere in the message" or "the whole message"))
    ns.Print(string.format("  on a whisper: %s   on say and yell: %s",
        cfg.onWhisper and "|cff40ff40yes|r" or "|cff888888no|r",
        cfg.onSayYell and "|cff40ff40yes|r" or "|cff888888no|r"))
    ns.Print(string.format("  guild only: %s   friends only: %s   accept from friends: %s",
        cfg.guildOnly and "yes" or "no",
        cfg.friendsOnly and "yes" or "no",
        cfg.autoAccept and "yes" or "no"))
    ns.Print(string.format("  make it a raid at five: %s   promote: %s",
        cfg.convertAtFive and "yes" or "no",
        cfg.autoPromote and (cfg.promote ~= "" and cfg.promote:gsub("[\r\n]+", ", ")
            or "nobody named") or "no"))
    ns.Print(string.format("  remembered from the last disband: %d",
        #(cfg.lastGroup or {})))
end
