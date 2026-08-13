---------------------------------------------------------------------------
-- OptionsInvites.lua - the Invites page
--
-- NO THIRD COLUMN. There is no list to pick from here: everything on this
-- page is a yes-or-no about something that happens without you, and the two
-- boxes are typed into rather than chosen from.
--
-- THE ORDER IS THE ORDER OF CONSEQUENCE. What listens comes first, then who
-- it will let in, then what it does to the group afterwards, then the three
-- buttons that act right now. Somebody reading down the page reads the chain
-- an invite actually travels.
---------------------------------------------------------------------------
local _, ns = ...

local UI = ns.UI

local Page = {}
ns.OptionsInvites = Page

local function Cfg() return ns.Invites.Config() end

function Page:BuildPage(page, width)
    local L = ns.L
    local grid = UI.Page(page, width)

    ---------------------------------------------------------------------
    -- What it listens for
    ---------------------------------------------------------------------
    grid:Section(L["Keywords"])

    -- THE WARNING IS THE FIRST THING ON THE PAGE, because everything under it
    -- acts in your name at people who are not in the room.
    grid:Note(L["Everything on this page is |cffffd100off until you switch "
        .. "it on|r. Nothing here invites, promotes or accepts anything "
        .. "until the switch above it says so."])

    local keywordHost = CreateFrame("Frame", nil, grid.content)
    local keywords = UI.TextArea(keywordHost, width - 40, 70,
        function(text) Cfg().keywords = text end,
        ns.Invites.DEFAULT_KEYWORDS, 400)
    keywords:SetPoint("TOPLEFT", keywordHost, "TOPLEFT", 0, 0)
    keywordHost:SetHeight(keywords:GetHeight())
    grid:Wide(keywordHost, keywords:GetHeight(), 4, 8)
    keywordHost.Refresh = function() keywords:SetText(Cfg().keywords or "") end
    grid.widgets[#grid.widgets + 1] = keywordHost

    grid:Note(L["One word per line."] .. " Case does not matter, and a full "
        .. "stop or an exclamation mark on the end is ignored.")

    UI.Toggle(grid:Row(L["Invite on a whisper"]),
        function() return Cfg().onWhisper and true or false end,
        function(value) Cfg().onWhisper = value and true or false end)
    grid:Note(L["Somebody whispers one of the words above and the invitation "
        .. "goes out. A Battle.net whisper names an account rather than a "
        .. "character, which cannot be invited - so that one is answered "
        .. "with a line telling them to whisper the character instead."])

    UI.Toggle(grid:Row(L["Also on say and yell"]),
        function() return Cfg().onSayYell and true or false end,
        function(value) Cfg().onSayYell = value and true or false end)
    grid:Note(L["For standing at a summoning stone and shouting. It listens "
        .. "to everybody in earshot, so it belongs to the ten minutes you "
        .. "are filling a group and not to the evening."])

    UI.Toggle(grid:Row("Anywhere in the message"),
        function() return Cfg().looseMatch and true or false end,
        function(value) Cfg().looseMatch = value and true or false end)
    grid:Note(L["Off, the whole message has to BE the word - \"inv\" "
        .. "invites, \"inv please\" does not. On, the word is found anywhere "
        .. "in the sentence, which also finds it in \"I cannot inv you "
        .. "sorry\"."])

    ---------------------------------------------------------------------
    -- Who gets in
    ---------------------------------------------------------------------
    grid:Section("Who gets in")

    UI.Toggle(grid:Row(L["Guild members only"]),
        function() return Cfg().guildOnly and true or false end,
        function(value) Cfg().guildOnly = value and true or false end)
    grid:Note(L["Anybody else who whispers the word is told nothing happened "
        .. "- in your chat frame, not theirs."])

    UI.Toggle(grid:Row(L["Friends only"]),
        function() return Cfg().friendsOnly and true or false end,
        function(value) Cfg().friendsOnly = value and true or false end)
    grid:Note(L["Your friends list, and guild members count as friends here."])

    UI.Toggle(grid:Row(L["Accept invites from friends"]),
        function() return Cfg().autoAccept and true or false end,
        function(value) Cfg().autoAccept = value and true or false end)
    grid:Note(L["The other direction: an invitation FROM a friend or a guild "
        .. "member is accepted for you and the box goes away. From anybody "
        .. "else the box stays, which is the point."])

    ---------------------------------------------------------------------
    -- The group
    ---------------------------------------------------------------------
    grid:Section("The group")

    UI.Toggle(grid:Row(L["Make it a raid at five"]),
        function() return Cfg().convertAtFive and true or false end,
        function(value) Cfg().convertAtFive = value and true or false end)
    grid:Note(L["A party holds five. Without this the sixth invitation goes "
        .. "nowhere at all - which is the step everybody forgets. Not done "
        .. "in combat: the game refuses."])

    UI.Toggle(grid:Row(L["Promote"]),
        function() return Cfg().autoPromote and true or false end,
        function(value) Cfg().autoPromote = value and true or false end)

    local promoteHost = CreateFrame("Frame", nil, grid.content)
    local promote = UI.TextArea(promoteHost, width - 40, 56,
        function(text) Cfg().promote = text end,
        "Name\nName-Realm", 400)
    promote:SetPoint("TOPLEFT", promoteHost, "TOPLEFT", 0, 0)
    promoteHost:SetHeight(promote:GetHeight())
    grid:Wide(promoteHost, promote:GetHeight(), 4, 8)
    promoteHost.Refresh = function() promote:SetText(Cfg().promote or "") end
    grid.widgets[#grid.widgets + 1] = promoteHost

    grid:Note(L["One name a line. They are made assistants when they join, "
        .. "and only while you are the leader of a raid. A raid where "
        .. "everybody is an assistant is a raid where anybody can pull."])

    UI.Toggle(grid:Row("Say what it did"),
        function() return Cfg().announce ~= false end,
        function(value) Cfg().announce = value and true or false end)
    grid:Note(L["A line in your own chat frame for every invitation sent. "
        .. "Worth keeping on: an invite tool that works silently is one you "
        .. "cannot tell from one that has stopped."])

    ---------------------------------------------------------------------
    -- Right now
    ---------------------------------------------------------------------
    grid:Section("Right now")

    -- THE RANK FILTER SITS WITH THE BUTTON IT AFFECTS. It is the one control
    -- on this page that changes what a press does rather than what happens on
    -- its own, and it would read as another listener anywhere higher up.
    UI.Dropdown(grid:Row(L["Guild rank"]), function()
        local items = { { value = "", text = L["Any rank"] } }
        for _, rank in ipairs(ns.Invites.GuildRanks()) do
            items[#items + 1] = {
                value = tostring(rank.index),
                text = rank.name or ("Rank " .. rank.index),
            }
        end
        return items
    end, function()
        local max = Cfg().maxRank
        return max and tostring(max) or ""
    end, function(value)
        Cfg().maxRank = (value ~= "" and tonumber(value)) or nil
    end, { emptyText = L["Any rank"] })

    grid:Note(L["Everybody at that rank and above it. Rank numbers count "
        .. "downwards from the guild master, which is why this reads as "
        .. "\"and above\" rather than \"and below\"."])

    grid:Buttons({
        { text = L["Invite the guild"],
          onClick = function() ns.Invites.InviteGuild() end },
        { text = L["Invite everyone back"],
          onClick = function() ns.Invites.InviteBack() end },
        { text = L["Disband"],
          onClick = function() ns.Invites.Disband() end },
    }, 10)

    grid:Note("|cffffd100Disband|r remembers who was in the group, so "
        .. "|cffffd100" .. L["Invite everyone back"] .. "|r is the second half "
        .. "of it - the usual way to reset a raid that has gone wrong. Only "
        .. "online guild members not already in a group are invited.")

    grid:Layout()
    page.Refresh = function() grid:Refresh() end
end
