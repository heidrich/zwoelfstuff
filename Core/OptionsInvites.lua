---------------------------------------------------------------------------
-- OptionsInvites.lua - the Invites page
--
-- NO THIRD COLUMN. There is no list to pick from here: everything on this
-- page is a yes-or-no about something that happens without you, and the two
-- boxes are typed into rather than chosen from.
--
-- THE ORDER IS THE ORDER OF CONSEQUENCE. What listens comes first, then who
-- it will let in, then what it does to the group afterwards, then the rank
-- filter for the three buttons that act right now - which sit in the page's
-- header. Somebody reading down the page reads the chain an invite actually
-- travels.
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

    -- TWO COLUMNS, WITH THE SENTENCE UNDER THE SWITCH. Every switch on this
    -- page used to be followed by a paragraph, and a paragraph is a wide
    -- block - so no two switches could ever share a line, and a page of ten
    -- yes-or-nos ran down one column with air on the right of every one.
    -- Owner, 2026-08-16: "alles in einer spalte sieht sehr offen aus." The
    -- one line each switch needs is its sublabel now; what would not fit on
    -- a line and is worth keeping stands as one note under the section.
    UI.Toggle(grid:Row(L["Invite on a whisper"], {
        sublabel = L["Somebody whispers one of the words above"],
    }), function() return Cfg().onWhisper and true or false end,
        function(value) Cfg().onWhisper = value and true or false end)

    UI.Toggle(grid:Row(L["Also on say and yell"], {
        sublabel = L["For shouting at a summoning stone"],
    }), function() return Cfg().onSayYell and true or false end,
        function(value) Cfg().onSayYell = value and true or false end)

    UI.Toggle(grid:Row("Anywhere in the message", {
        sublabel = L["Off, the whole message has to be the word"],
    }), function() return Cfg().looseMatch and true or false end,
        function(value) Cfg().looseMatch = value and true or false end)

    -- THE ONE THING SOMEBODY WILL REPORT AS A BUG stays as a sentence: a
    -- Battle.net whisper cannot be invited, and without this line the addon
    -- looks as if it ignored a friend.
    grid:Note(L["A Battle.net whisper names an account rather than a "
        .. "character, which cannot be invited - that one is answered with "
        .. "a line telling them to whisper the character instead."])

    ---------------------------------------------------------------------
    -- Who gets in
    ---------------------------------------------------------------------
    grid:Section("Who gets in")

    UI.Toggle(grid:Row(L["Guild members only"], {
        sublabel = L["Anybody else is ignored, and you are told"],
    }), function() return Cfg().guildOnly and true or false end,
        function(value) Cfg().guildOnly = value and true or false end)

    UI.Toggle(grid:Row(L["Friends only"], {
        sublabel = L["Guild members count as friends here"],
    }), function() return Cfg().friendsOnly and true or false end,
        function(value) Cfg().friendsOnly = value and true or false end)

    UI.Toggle(grid:Row(L["Accept invites from friends"], {
        sublabel = L["Their invitation is accepted for you"],
    }), function() return Cfg().autoAccept and true or false end,
        function(value) Cfg().autoAccept = value and true or false end)

    ---------------------------------------------------------------------
    -- The group
    ---------------------------------------------------------------------
    grid:Section("The group")

    UI.Toggle(grid:Row(L["Make it a raid at five"], {
        sublabel = L["The sixth invitation needs a raid"],
    }), function() return Cfg().convertAtFive and true or false end,
        function(value) Cfg().convertAtFive = value and true or false end)

    UI.Toggle(grid:Row("Say what it did", {
        sublabel = L["A line in your chat for every invitation"],
    }), function() return Cfg().announce ~= false end,
        function(value) Cfg().announce = value and true or false end)

    UI.Toggle(grid:Row(L["Promote"], {
        sublabel = L["The names below become assistants"],
    }), function() return Cfg().autoPromote and true or false end,
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
        .. "and only while you are the leader of a raid."])

    ---------------------------------------------------------------------
    -- Right now
    --
    -- THE THREE BUTTONS ARE IN THE PAGE HEADER now (owner, 2026-08-16); the
    -- rank filter stays down here with the sentence that says what it
    -- filters, because it is the one control on this page that changes
    -- what a press does rather than what happens on its own.
    ---------------------------------------------------------------------
    grid:Section("Right now")

    UI.Dropdown(grid:Row(L["Guild rank"], {
        sublabel = L["Everybody at that rank and above it"],
    }), function()
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

    grid:Note("|cffffd100" .. L["Invite the guild"] .. "|r, above, invites "
        .. "everybody at that rank and above it who is online and not in a "
        .. "group. |cffffd100" .. L["Disband"] .. "|r remembers who was in the "
        .. "group, so |cffffd100" .. L["Invite everyone back"] .. "|r is the "
        .. "second half of it - the usual way to reset a raid that has gone "
        .. "wrong.")

    grid:Layout()
    page.Refresh = function() grid:Refresh() end
end
