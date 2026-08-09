---------------------------------------------------------------------------
-- Death.lua - what killed you, and what could have prevented it
--
-- The owner's ask, in his words: when you die, a window with a quick
-- analysis - what came in, with numbers; which defensives were AVAILABLE;
-- whether a healthstone or a potion was sitting in the bags; and a way to
-- share the short version in chat.
--
-- WHERE THE DATA COMES FROM, because on this patch that is the whole design:
-- the combat log is gone and auras are secret, but Blizzard now runs its own
-- damage meter and death recap and lets an addon READ them -
-- C_DamageMeter.GetCombatSessionFromType lists the deaths of the current
-- fight, each carrying a deathRecapID, and C_DeathRecap.GetRecapEvents turns
-- that into the last events before the death: timestamp, amount, the health
-- you had left after each, overkill on the killing blow. The AMOUNTS ARE
-- REAL NUMBERS - EllesmereUIDamageMeters divides and compares them in
-- shipping code, which is how this was established. The spell NAME may be a
-- secret: displayable, but not comparable and never allowed into a chat
-- string. Every name in here goes through SafeName first.
--
-- "Was it available" is ns.History's estimate - own casts plus base
-- cooldown - because the client will not answer the question directly. The
-- window says "by our own clock" and means it.
---------------------------------------------------------------------------
local _, ns = ...

local Death = {}
ns.Death = Death

local UI -- ns.UI, taken late: Widgets loads after this file

-- The deaths of this session, oldest first, capped - the owner asked to
-- page through "the last 10 or so". Session only, not saved variables: an
-- analysis is read in the minutes after dying, not archived across days.
-- Death.snapshot stays the NEWEST entry, because half the wiring asks
-- "did the last capture find anything" and that question has one answer.
Death.log = {}
Death.snapshot = nil
local DEATHS_KEPT = 10

-- How far back the quick analysis looks, in seconds. The recap itself
-- decides how many events it hands over; this only bounds OUR arithmetic.
local WINDOW = 10

-- One rule for how a capture enters the log, pure and tested. `replace` is
-- the retry and the Blizzard-recap hook speaking: the SAME death got a
-- better answer, and pushing it again would show one fall twice in the
-- pager. A plain push is a new death; the cap drops the oldest.
function Death.Remember(log, snapshot, cap, replace)
    if replace and #log > 0 then
        log[#log] = snapshot
    else
        log[#log + 1] = snapshot
        while #log > (cap or DEATHS_KEPT) do
            table.remove(log, 1)
        end
    end
    return snapshot
end

---------------------------------------------------------------------------
-- Names, made safe
---------------------------------------------------------------------------

-- A name that is safe to compute with, concatenate, and send to chat - or a
-- fallback word derived from the event type, which is always ours. This is
-- the only door a recap string passes through.
function Death.SafeName(name, eventType)
    if type(name) == "string" and name ~= "" and ns.CanCompute(name) then
        return name
    end
    if eventType == "SWING_DAMAGE" then return "Melee" end
    if eventType == "SPELL_HEAL" or eventType == "SPELL_PERIODIC_HEAL" then
        return "a heal"
    end
    return "a spell"
end

---------------------------------------------------------------------------
-- Where it happened, and where a share goes - pure, exported, tested
---------------------------------------------------------------------------

-- The place a death happened, said the way a player says it: "M+7 -
-- Ara-Kara", "Raid - Nerub-ar Palace (Heroic) - Queen Ansurek", "Open
-- world - Duskwood". Every input may be nil - each one comes off an API
-- the client is allowed to withhold - and the label degrades a word at a
-- time instead of failing.
-- Two answers: the full line for the window header and the share, and one
-- SHORT word for the list down the side, where 180 pixels have to say what
-- kind of evening this was.
function Death.WhereLabel(instanceType, instanceName, difficultyName,
        keyLevel, encounterName, zoneText)
    local place, short
    if instanceType == "party" then
        if keyLevel and keyLevel > 0 then
            short = "M+" .. keyLevel
            place = string.format("M+%d - %s", keyLevel,
                instanceName or "a dungeon")
        else
            short = "Dungeon"
            place = "Dungeon - " .. (instanceName or "?")
            if difficultyName and difficultyName ~= "" then
                place = place .. " (" .. difficultyName .. ")"
            end
        end
    elseif instanceType == "raid" then
        short = "Raid"
        place = "Raid - " .. (instanceName or "?")
        if difficultyName and difficultyName ~= "" then
            place = place .. " (" .. difficultyName .. ")"
        end
    elseif instanceType == "pvp" then
        short = "Battleground"
        place = "Battleground - " .. (instanceName or "?")
    elseif instanceType == "arena" then
        short = "Arena"
        place = "Arena - " .. (instanceName or "?")
    elseif instanceType == "scenario" then
        short = "Scenario"
        place = "Scenario - " .. (instanceName or "?")
    else
        short = "Open world"
        place = (zoneText and zoneText ~= "")
            and ("Open world - " .. zoneText) or "Open world"
    end
    -- A boss is the most specific thing that can be true about a place, so
    -- it wins the short word outright: "Avanoxx" says more than "M+12".
    if encounterName and encounterName ~= "" then
        place = place .. " - " .. encounterName
        short = encounterName
    end
    return place, short
end

-- Which channel a share goes to. choice is the Deaths-page setting; state
-- says which groups are actually around. "AUTO" is the group around you,
-- instance first - the behaviour before there was a setting. An explicit
-- choice that is not available answers nil and why, and the caller prints
-- to the own chat frame instead: a share must never silently go nowhere.
function Death.ShareTarget(choice, state)
    state = state or {}
    if not choice or choice == "AUTO" then
        if state.inInstance then return "INSTANCE_CHAT" end
        if state.inRaid then return "RAID" end
        if state.inParty then return "PARTY" end
        return nil, "not in a group"
    end
    if choice == "PARTY" and not state.inParty then
        return nil, "not in a party"
    end
    if choice == "RAID" and not state.inRaid then
        return nil, "not in a raid"
    end
    if choice == "INSTANCE_CHAT" and not state.inInstance then
        return nil, "not in an instance group"
    end
    if choice == "GUILD" and not state.inGuild then
        return nil, "not in a guild"
    end
    return choice
end

-- Wiping a GIVEN list, so the test can clear its own and never touches the
-- session's real one - /zs test in game must not eat the player's deaths.
function Death.ClearLog(log)
    for i = #log, 1, -1 do log[i] = nil end
    return log
end

---------------------------------------------------------------------------
-- The analysis - pure, exported, tested
--
-- events: oldest first, each { t, amount, hp, heal, name, overkill }
--         with t in seconds before death (0 = the killing blow), every
--         field already readable - Capture below guarantees that.
-- avail:  { { spellID, name, remaining, why } } - remaining 0 = ready by
--         our clock, nil = cannot tell (why says why).
-- items:  { { name, count } } - only what was actually in the bags.
---------------------------------------------------------------------------
function Death.Analyse(events, maxHP, avail, items)
    local out = {
        totalIn = 0, totalHealed = 0, hits = 0,
        biggest = nil,          -- { amount, name, pct }
        lastHealAgo = nil,      -- seconds before death the last heal landed
        readyDefensives = {},   -- names, ready and unpressed
        unknownDefensives = {}, -- names we cannot judge
        itemsInBags = {},       -- names with count > 0
        lines = {},             -- the verdict, one sentence per line
    }

    for _, ev in ipairs(events or {}) do
        if ev.t <= WINDOW then
            if ev.heal then
                out.totalHealed = out.totalHealed + (ev.amount or 0)
                if not out.lastHealAgo or ev.t < out.lastHealAgo then
                    out.lastHealAgo = ev.t
                end
            else
                out.totalIn = out.totalIn + (ev.amount or 0)
                out.hits = out.hits + 1
                if not out.biggest or (ev.amount or 0) > out.biggest.amount then
                    out.biggest = {
                        amount = ev.amount or 0, name = ev.name, who = ev.who,
                    }
                end
            end
        end
    end

    if out.biggest and maxHP and maxHP > 0 then
        out.biggest.pct = out.biggest.amount / maxHP
    end

    for _, entry in ipairs(avail or {}) do
        if entry.remaining == 0 then
            out.readyDefensives[#out.readyDefensives + 1] = entry.name
        elseif entry.remaining == nil then
            out.unknownDefensives[#out.unknownDefensives + 1] = entry.name
        end
    end

    for _, item in ipairs(items or {}) do
        if (item.count or 0) > 0 then
            out.itemsInBags[#out.itemsInBags + 1] = item.name
        end
    end

    -- The verdict. Written as observations, not accusations - the person
    -- reading this just died and the addon was not there.
    local lines = out.lines

    if out.hits > 0 then
        if out.biggest and out.biggest.pct and out.biggest.pct >= 0.4 then
            -- The mob's name belongs in the sentence when the recap gave
            -- one: "Melee for 109k" answers what, "Melee from Heavyweight
            -- Golem" answers what AND who.
            local hit = out.biggest.name or "a spell"
            if out.biggest.who then
                hit = hit .. " from " .. out.biggest.who
            end
            lines[#lines + 1] = string.format(
                "One hit did most of it: %s for %s - %d%% of your health.",
                hit, ns.ShortNumber(out.biggest.amount),
                math.floor(out.biggest.pct * 100 + 0.5))
        else
            lines[#lines + 1] = string.format(
                "No single killer: %d hits for %s over %ds.",
                out.hits, ns.ShortNumber(out.totalIn), WINDOW)
        end
    end

    if out.lastHealAgo and out.lastHealAgo > 3 then
        lines[#lines + 1] = string.format(
            "The last heal landed %.1fs before the end.", out.lastHealAgo)
    end

    if #out.readyDefensives > 0 then
        lines[#lines + 1] = "Ready and unpressed (by our own clock): "
            .. table.concat(out.readyDefensives, ", ") .. "."
    end

    if #out.itemsInBags > 0 then
        lines[#lines + 1] = "In the bags: "
            .. table.concat(out.itemsInBags, ", ") .. "."
    end

    if #lines == 0 then
        lines[#lines + 1] = "Not enough was readable to say anything useful."
    end

    return out
end

-- The events inside the promised window, oldest first - what the row list
-- shows. Its own function because the first live death displayed rows from
-- FIVE MINUTES earlier: the recap hands over more history than its name
-- says, and a window subtitled "the last 10 seconds" showing -309.8s is
-- lying about one of the two. When nothing falls inside the window the full
-- list comes back rather than an empty frame - with a flag, so the caller
-- can re-title instead of quietly breaking the same promise again.
function Death.RecentEvents(events, window)
    local out = {}
    for _, ev in ipairs(events or {}) do
        if ev.t <= window then out[#out + 1] = ev end
    end
    if #out > 0 then return out, false end
    return events or {}, true
end

---------------------------------------------------------------------------
-- Finding our own recap
---------------------------------------------------------------------------

-- The realm half of a name, gone. The damage meter names people with realm,
-- UnitName("player") answers without one.
local function StripRealm(name)
    if type(name) ~= "string" then return name end
    local short = name:match("^(.-)%-")
    return short or name
end

-- The deathRecapID of OUR latest death in the current fight, or nil and why.
-- Read the way EllesmereUIDamageMeters reads it: the Deaths list of the
-- damage meter's current session, matched by name. Every step may be absent
-- or secret on this patch, so every step is guarded and names its failure.
function Death.OwnRecapID()
    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType
        and Enum and Enum.DamageMeterType and Enum.DamageMeterSessionType) then
        return nil, "this client has no damage meter API"
    end

    -- combatSources, because that is the field EllesmereUI's shipping code
    -- iterates. The first in-game death was reported "no deaths this fight"
    -- while Blizzard's own recap stood open showing the killer: the field
    -- here was guessed as .sources, the guess answered nil, and the empty
    -- fallback made a wrong name read as an empty fight. Current first,
    -- Overall as the fallback - a training dummy kill landed in one and not
    -- the other on the owner's screen.
    local function SourcesOf(sessionType)
        local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType,
            sessionType, Enum.DamageMeterType.Deaths)
        if not ok or type(session) ~= "table" then return nil end
        local list = session.combatSources or session.sources
        if type(list) ~= "table" or #list == 0 then return nil end
        return list
    end

    local sources = SourcesOf(Enum.DamageMeterSessionType.Current)
        or SourcesOf(Enum.DamageMeterSessionType.Overall)
    if not sources then
        return nil, "the damage meter lists no deaths yet"
    end

    local me = UnitName("player")
    if not ns.CanCompute(me) then
        return nil, "the client withheld your own name"
    end

    -- Newest wins: iterate to the end, keep the last match. Dying twice in
    -- one fight lists two rows, and the one being asked about is always the
    -- one that just happened.
    local found
    for _, src in ipairs(sources) do
        local name = src.name
        if ns.CanCompute(name) and StripRealm(name) == me then
            local rid = src.deathRecapID
            if ns.CanCompute(rid) and type(rid) == "number" and rid > 0 then
                found = rid
            end
        end
    end
    if not found then
        return nil, "your death carries no readable recap id"
    end
    return found
end

---------------------------------------------------------------------------
-- Capture
---------------------------------------------------------------------------

-- Health potions and healthstone. Item ids are stable facts; counts are
-- bag questions, not combat questions, and stay readable. The list is
-- deliberately short - the two things a healer will ask about first.
local RESCUE_ITEMS = {
    { itemID = 5512,   name = "Healthstone" },
    { itemID = 244839, name = "Invigorating Healing Potion" },
    { itemID = 211880, name = "Algari Healing Potion" },
}

local function ItemsInBags()
    local out = {}
    if not (C_Item and C_Item.GetItemCount) then return out end
    for _, item in ipairs(RESCUE_ITEMS) do
        local ok, count = pcall(C_Item.GetItemCount, item.itemID)
        if ok and type(count) == "number" and count > 0 then
            out[#out + 1] = { name = item.name, count = count }
        end
    end
    return out
end

-- WHERE it happened. The owner asked for it in as many words: open world,
-- dungeon, raid, boss, M+. Every call here is one the client may refuse, so
-- each is guarded on its own and the label is built from whatever survived.
--
-- The encounter name comes from ENCOUNTER_START rather than from any lookup:
-- it is the only thing that knows a BOSS is what you are standing in front
-- of, and it arrives readable (BigWigs drives its whole engage logic off it).
Death.encounter = nil

local function KeyLevel()
    if not (C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.GetActiveKeystoneInfo) then
        return nil
    end
    local okActive, active = pcall(C_ChallengeMode.IsChallengeModeActive)
    if not okActive or not active then return nil end
    local okLevel, level = pcall(C_ChallengeMode.GetActiveKeystoneInfo)
    if okLevel and ns.CanCompute(level) and type(level) == "number"
        and level > 0 then
        return level
    end
    return nil
end

local function Readable(value)
    if ns.CanCompute(value) and type(value) == "string" and value ~= "" then
        return value
    end
    return nil
end

function Death.Where()
    local instanceName, instanceType, difficultyName
    if GetInstanceInfo then
        local ok, name, kind, _, diffName = pcall(GetInstanceInfo)
        if ok then
            instanceName = Readable(name)
            instanceType = Readable(kind)
            difficultyName = Readable(diffName)
        end
    end

    local zone
    if GetRealZoneText then
        local ok, text = pcall(GetRealZoneText)
        if ok then zone = Readable(text) end
    end
    if not zone and GetZoneText then
        local ok, text = pcall(GetZoneText)
        if ok then zone = Readable(text) end
    end

    return Death.WhereLabel(instanceType, instanceName, difficultyName,
        KeyLevel(), Death.encounter, zone)
end

-- What was still ready, off the defensives picked on the Timeline page.
local function Availability(now)
    local out = {}
    for spellID in pairs((ns.db and ns.db.defensives) or {}) do
        local name = ns.SpellName(spellID) or ("Spell " .. spellID)
        local remaining, why = ns.History:Estimate(spellID, now)
        out[#out + 1] = {
            spellID = spellID, name = name,
            remaining = remaining, why = why,
        }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Reads the recap into OUR shape, with every field made safe at the door.
-- After this function nothing downstream needs a guard, which is the only
-- way the pure analysis can stay pure.
function Death.ReadRecap(recapID)
    if not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then
        return nil, nil, "this client has no death recap API"
    end
    local ok, raw = pcall(C_DeathRecap.GetRecapEvents, recapID)
    if not ok or type(raw) ~= "table" or #raw == 0 then
        return nil, nil, "the recap is empty"
    end

    local maxHP
    if C_DeathRecap.GetRecapMaxHealth then
        local ok2, hp = pcall(C_DeathRecap.GetRecapMaxHealth, recapID)
        if ok2 and type(hp) == "number" and hp > 0 then maxHP = hp end
    end

    -- Newest first in the API; ours is oldest first with t = seconds before
    -- death, because that is the order a person reads a story in.
    local deathAt
    for i = 1, #raw do
        local ts = raw[i].timestamp
        if ns.CanCompute(ts) and type(ts) == "number" then
            deathAt = ts
            break
        end
    end

    -- WHO. The recap names sources readably - "killed by Heavyweight Golem"
    -- stood on the owner's screen off this very loop - so every event gets
    -- its who, not just the window title. Three candidate field names until
    -- a probe dump settles which one is real; the first readable wins.
    local function WhoOf(ev)
        for _, key in ipairs({ "sourceName", "casterName", "caster" }) do
            local who = ev[key]
            if ns.CanCompute(who) and type(who) == "string" and who ~= "" then
                return who
            end
        end
        return nil
    end

    -- The killer is the newest event's readable source - raw arrives newest
    -- first, so the first hit of this loop is the one that landed last.
    local killer
    for i = 1, #raw do
        killer = WhoOf(raw[i])
        if killer then break end
    end

    -- The killer's PICTURE. Blizzard's own recap draws the model, so the
    -- client holds one; what it hands an addon is what the probe is for.
    -- Two doors, both proven in shipping code: a creature id goes into
    -- PlayerModel:SetCreature - MDT points its enemy tooltips at raw npc
    -- ids that way - and a display id into SetDisplayInfo. A readable GUID
    -- is the third door: an npc id is the sixth field of one, and outside a
    -- dungeon the recap's GUIDs are not withheld. Whichever answers first
    -- wins; none answering means no portrait, not an empty box.
    local function NumberFrom(ev, keys)
        for _, key in ipairs(keys) do
            local value = ev[key]
            if ns.CanCompute(value) and type(value) == "number" and value > 0 then
                return value
            end
        end
        return nil
    end

    local function CreatureFromGUID(ev)
        for _, key in ipairs({ "sourceGUID", "casterGUID", "guid" }) do
            local guid = ev[key]
            if ns.CanCompute(guid) and type(guid) == "string" then
                local kind, npcID = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
                if npcID and (kind == "Creature" or kind == "Vehicle"
                    or kind == "Pet" or kind == "GameObject") then
                    return tonumber(npcID)
                end
            end
        end
        return nil
    end

    local art
    for i = 1, #raw do
        local creature = NumberFrom(raw[i], {
            "sourceCreatureID", "creatureID", "npcID", "sourceNpcID",
        }) or CreatureFromGUID(raw[i])
        local display = NumberFrom(raw[i], {
            "displayID", "sourceDisplayID", "creatureDisplayID",
        })
        if creature or display then
            art = { creatureID = creature, displayID = display }
            break
        end
    end

    local events = {}
    for i = #raw, 1, -1 do
        local ev = raw[i]
        local amount = ev.amount
        local hp = ev.currentHP
        local ts = ev.timestamp
        local overkill = ev.overkill
        local kind = ns.CanCompute(ev.event) and ev.event or ""
        events[#events + 1] = {
            t = (deathAt and ns.CanCompute(ts) and type(ts) == "number")
                and math.max(0, deathAt - ts) or 0,
            amount = (ns.CanCompute(amount) and type(amount) == "number")
                and math.abs(amount) or 0,
            hp = (ns.CanCompute(hp) and type(hp) == "number") and hp or nil,
            heal = kind == "SPELL_HEAL" or kind == "SPELL_PERIODIC_HEAL",
            name = Death.SafeName(ev.spellName, kind),
            who = WhoOf(ev),
            spellID = (ns.CanCompute(ev.spellId) and type(ev.spellId) == "number"
                and ev.spellId > 0) and ev.spellId or nil,
            overkill = (ns.CanCompute(overkill) and type(overkill) == "number"
                and overkill > 0) and overkill or nil,
        }
    end
    return events, maxHP, nil, killer, art
end

function Death:Capture(overrideID, replace)
    local now = GetTime()
    local recapID, why
    if overrideID then
        -- Handed straight from Blizzard's own recap window opening - no
        -- searching, no name matching, the id is by definition ours.
        recapID = overrideID
    else
        recapID, why = Death.OwnRecapID()
    end

    local events, maxHP, readWhy, killer, art
    if recapID then
        events, maxHP, readWhy, killer, art = Death.ReadRecap(recapID)
    end

    local avail = Availability(now)
    local items = ItemsInBags()
    local where, whereShort = Death.Where()

    self.snapshot = Death.Remember(self.log, {
        at = now,
        when = date("%H:%M:%S"),
        where = where,
        whereShort = whereShort,
        events = events,
        maxHP = maxHP,
        killer = killer,
        killerArt = art,
        avail = avail,
        items = items,
        reason = events == nil and (readWhy or why) or nil,
        analysis = Death.Analyse(events, maxHP, avail, items),
    }, DEATHS_KEPT, replace)

    -- The pager may be standing on an older death; a new one must not yank
    -- it. Only a view of the newest follows the newest.
    if self.showing and not replace then self.showing = nil end
    Death.RefreshIcon()
    return self.snapshot
end

---------------------------------------------------------------------------
-- Chat
---------------------------------------------------------------------------

-- Which groups are around, as plain booleans - the state half of the rule
-- above, kept apart from it so the rule itself stays testable on a desktop.
local function GroupState()
    return {
        inInstance = IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) or false,
        inRaid = IsInRaid and IsInRaid() or false,
        inParty = IsInGroup and IsInGroup() or false,
        inGuild = IsInGuild and IsInGuild() or false,
    }
end

-- The short version, built ONLY from lines the analysis already made safe.
function Death.ShareLines(snapshot)
    if not snapshot then return nil end
    local a = snapshot.analysis
    local lines = {}
    -- The killer is in the lead line when the recap named one readably -
    -- it is the first thing the group asks, so it goes first. The place
    -- follows it: "in an M+7" is the difference between a pull that was
    -- always going to hurt and one that should not have.
    local by = snapshot.killer and (" by " .. snapshot.killer) or ""
    local at = snapshot.where and (" [" .. snapshot.where .. "]") or ""
    if a.hits > 0 then
        lines[#lines + 1] = string.format("Death %s%s%s: %s in %ds (%d hits).",
            snapshot.when or "", by, at,
            ns.ShortNumber(a.totalIn), WINDOW, a.hits)
    else
        lines[#lines + 1] = string.format("Death %s%s%s.",
            snapshot.when or "", by, at)
    end
    for _, line in ipairs(a.lines) do
        lines[#lines + 1] = line
    end
    return lines
end

function Death:Share()
    -- The death being LOOKED AT, not blindly the newest: sharing while
    -- paged back to an earlier one must post the one on screen.
    local snapshot = self.log[self.showing or #self.log]
    if not snapshot then
        ns.Print("No death recorded yet this session.")
        return
    end
    local lines = Death.ShareLines(snapshot) or {}
    local channel, why = Death.ShareTarget(
        ns.db and ns.db.death and ns.db.death.channel, GroupState())
    -- C_ChatInfo is the living call on this client (BigWigs' Loader uses
    -- it); the bare global is deprecated and only kept as the fallback.
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    for _, line in ipairs(lines) do
        if channel then
            send("ZwoelfStuff: " .. line, channel)
        else
            ns.Print(line)
        end
    end
    if not channel then
        -- A chosen channel that is not there must SAY so. Printing the
        -- analysis to your own frame while you believe it went to the raid
        -- is the one failure a share feature is not allowed to have.
        ns.Print("|cff888888" .. (why or "not in a group")
            .. " - printed here instead.|r")
    end
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local frame

-- One row of the event list: time, name, a health bar behind the amount.
-- The bar IS the graph - each row's fill is the health you still had after
-- that event, so reading down the list is watching the health drain.
local ROW_H = 22
local ROWS_MAX = 12

-- The window is two columns: the analysis of ONE death on the left, and the
-- session's deaths down the right so you can walk them without paging. The
-- numbers are the left column's content width and the side list's width;
-- everything else is measured off them.
local MAIN_W = 430
local SIDE_W = 186
local SIDE_X = 16 + MAIN_W + 14
local SIDE_ROW_H = 34
local HEADER_BOTTOM = 82

local function BuildWindow()
    UI = ns.UI
    local C = UI.C

    frame = CreateFrame("Frame", "ZwoelfStuffDeathFrame", UIParent)
    frame:SetSize(SIDE_X + SIDE_W + 16, 520)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    UI.Fill(frame, "BACKGROUND", C.windowBg)
    local edge = ns.CreateBorder(frame, 1, "BORDER")
    edge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)

    -- The killer's portrait. A PlayerModel pointed at a creature id, which
    -- is how MDT draws the mob in its enemy tooltips - the same call, on
    -- the same kind of id. It is Hidden until one actually renders: an
    -- empty black square where a face should be is worse than no square.
    frame.portrait = CreateFrame("PlayerModel", nil, frame)
    frame.portrait:SetSize(54, 54)
    frame.portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -12)
    frame.portrait:Hide()
    local portraitEdge = ns.CreateBorder(frame.portrait, 1, "OVERLAY")
    portraitEdge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)

    frame.title = UI.Label(frame, "You died", 16, C.text)
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)

    frame.sub = UI.Label(frame, "", 11, C.textFaint)
    frame.sub:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -3)

    -- Where it happened, on its own line: the owner asked for it by name,
    -- and "M+12 - Ara-Kara - Avanoxx" is a different story from the same
    -- numbers taken in the open world.
    frame.place = UI.Label(frame, "", 11, C.accentCool)
    frame.place:SetPoint("TOPLEFT", frame.sub, "BOTTOMLEFT", 0, -2)
    frame.place:SetWidth(MAIN_W - 70)
    frame.place:SetWordWrap(false)

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
    local closeMark = UI.Glyph(close, "ui-close", 12, C.textDim)
    closeMark:SetPoint("CENTER", close, "CENTER", 0, 0)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- The pager arrows that stood here in 4.45.0 are gone: the list down
    -- the right side IS the pager now, and it shows where you are instead
    -- of counting for you. The wheel still steps, because a wheel over a
    -- list of things costs no pixels.
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        Death:Show((Death.showing or #Death.log) + delta)
    end)

    -- The verdict block, above the event rows: the analysis is the point of
    -- the window, so it does not sit under a scroll.
    frame.verdict = UI.Label(frame, "", 12, C.text)
    frame.verdict:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -HEADER_BOTTOM)
    frame.verdict:SetWidth(MAIN_W)
    frame.verdict:SetJustifyH("LEFT")
    frame.verdict:SetJustifyV("TOP")
    frame.verdict:SetSpacing(3)

    -- Event rows, built once, filled per death.
    frame.rows = {}
    for i = 1, ROWS_MAX do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(MAIN_W, ROW_H)

        row.fill = row:CreateTexture(nil, "BACKGROUND")
        row.fill:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        row.fill:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)

        row.when = UI.Label(row, "", 11, C.textDim)
        row.when:SetPoint("LEFT", row, "LEFT", 6, 0)

        -- The spell's icon, when the recap names a readable id. EllesmereUI
        -- resolves recap icons exactly this way in shipping code.
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", row, "LEFT", 52, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row.what = UI.Label(row, "", 12, C.text)
        row.what:SetPoint("LEFT", row, "LEFT", 74, 0)
        row.what:SetWidth(222)
        row.what:SetJustifyH("LEFT")
        row.what:SetWordWrap(false)

        row.amount = UI.Label(row, "", 12, C.text)
        row.amount:SetPoint("RIGHT", row, "RIGHT", -6, 0)

        -- The client's own spell tooltip on hover, which is the whole
        -- point: a name tells you what hit, the tooltip tells you what it
        -- does. A melee swing has no spell to ask about, so the row says
        -- what it knows itself rather than showing an empty frame.
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            local ev = self.ev
            if not (ev and GameTooltip) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local shown = false
            if ev.spellID then
                shown = pcall(GameTooltip.SetSpellByID, GameTooltip, ev.spellID)
            end
            if not shown then
                GameTooltip:ClearLines()
                GameTooltip:AddLine(ev.name or "", 1, 1, 1)
            end
            if ev.who then
                GameTooltip:AddLine("from " .. ev.who, 0.61, 0.64, 0.69)
            end
            GameTooltip:AddLine(string.format("%s%s  -  %.1fs before the end",
                ev.heal and "+" or "-", ns.ShortNumber(ev.amount), ev.t),
                0.61, 0.64, 0.69)
            if ev.overkill then
                GameTooltip:AddLine(ns.ShortNumber(ev.overkill)
                    .. " of it was overkill", 0.61, 0.64, 0.69)
            end
            if ev.hp then
                GameTooltip:AddLine("Health left afterwards: "
                    .. ns.ShortNumber(ev.hp), 0.61, 0.64, 0.69)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)

        row:Hide()
        frame.rows[i] = row
    end

    -----------------------------------------------------------------------
    -- The list down the side: every death this session, newest first.
    -- The owner asked for it in as many words, and it replaces the arrows -
    -- a list you can see beats a counter you have to walk.
    -----------------------------------------------------------------------
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(C.edge[1], C.edge[2], C.edge[3], 1)
    divider:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE_X - 14, -14)
    divider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", SIDE_X - 14, 14)
    divider:SetWidth(1)

    frame.sideTitle = UI.Label(frame, "This session", 11, C.textDim)
    frame.sideTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE_X, -16)

    frame.sideRows = {}
    for i = 1, DEATHS_KEPT do
        local row = CreateFrame("Button", nil, frame)
        row:SetSize(SIDE_W, SIDE_ROW_H)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE_X,
            -(40 + (i - 1) * SIDE_ROW_H))

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints(row)
        row.bg:Hide()

        -- The accent bar on the left edge marks the one being read. A
        -- fill alone reads as hover on a list you can also hover.
        row.mark = row:CreateTexture(nil, "ARTWORK")
        row.mark:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        row.mark:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        row.mark:SetWidth(2)
        row.mark:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        row.mark:Hide()

        row.when = UI.Label(row, "", 11, C.text)
        row.when:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -4)

        row.where = UI.Label(row, "", 10, C.accentCool)
        row.where:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -4)
        row.where:SetJustifyH("RIGHT")
        row.where:SetWidth(96)
        row.where:SetWordWrap(false)

        row.who = UI.Label(row, "", 10, C.textFaint)
        row.who:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -19)
        row.who:SetWidth(SIDE_W - 16)
        row.who:SetWordWrap(false)

        row:SetScript("OnEnter", function(self)
            if self.index ~= Death.showing then
                row.bg:SetColorTexture(C.surface[1], C.surface[2], C.surface[3], 1)
                row.bg:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            if self.index ~= Death.showing then row.bg:Hide() end
        end)
        row:SetScript("OnClick", function(self)
            if self.index then Death:Show(self.index) end
        end)

        row:Hide()
        frame.sideRows[i] = row
    end

    -- Clearing the list. Two steps, like every other irreversible button in
    -- this addon: there is no undo, and a mis-click during a wipe would
    -- take the analysis you were about to read.
    local clearArmed, clear = false, nil
    clear = UI.Button(frame, "Clear list", 100, function()
        if not clearArmed then
            clearArmed = true
            clear.label:SetText("Sure?")
            return
        end
        clearArmed = false
        clear.label:SetText("Clear list")
        Death:Clear()
    end)
    clear:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", SIDE_X, 12)
    frame.disarmClear = function()
        clearArmed = false
        clear.label:SetText("Clear list")
    end
    frame:SetScript("OnHide", function() frame.disarmClear() end)

    -- Availability column footer: what was ready, what was in the bags.
    frame.avail = UI.Label(frame, "", 11, C.textDim)
    frame.avail:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 46)
    frame.avail:SetWidth(MAIN_W)
    frame.avail:SetJustifyH("LEFT")
    frame.avail:SetJustifyV("BOTTOM")
    frame.avail:SetSpacing(2)

    local share = UI.Button(frame, "Share in chat", 130, function()
        Death:Share()
    end, "primary")
    share:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 12)

    local dismiss = UI.Button(frame, "Close", 90, function()
        frame:Hide()
    end)
    dismiss:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16 + MAIN_W - 90, 12)
end

-- The killer's face, or nothing at all. Two doors, both guarded: a creature
-- id through SetCreature - MDT's enemy tooltip does exactly this with a raw
-- npc id - and a display id through SetDisplayInfo. Neither answering means
-- the block stays hidden and the header slides back to the left margin.
local function PaintPortrait(art)
    local model = frame.portrait
    if not (art and (art.creatureID or art.displayID)) then
        model:Hide()
        return false
    end
    local ok = false
    if art.creatureID and model.SetCreature then
        ok = pcall(model.SetCreature, model, art.creatureID)
    end
    if not ok and art.displayID and model.SetDisplayInfo then
        ok = pcall(model.SetDisplayInfo, model, art.displayID)
    end
    if not ok then
        model:Hide()
        return false
    end
    pcall(model.SetPosition, model, 0, 0, 0)
    pcall(model.SetFacing, model, 0.4)
    pcall(model.SetCamDistanceScale, model, 1.35)
    model:Show()
    return true
end

-- The side list, repainted whole. Newest at the top, because that is the
-- one being asked about nine times in ten.
local function PaintSideList()
    local total = #Death.log
    for slot = 1, DEATHS_KEPT do
        local row = frame.sideRows[slot]
        local index = total - slot + 1
        local snapshot = index >= 1 and Death.log[index] or nil
        if not snapshot then
            row.index = nil
            row:Hide()
        else
            row.index = index
            row.when:SetText(snapshot.when or "")
            row.where:SetText(snapshot.whereShort or "")
            row.who:SetText(snapshot.killer or "|cff626a76no killer named|r")
            local selected = index == Death.showing
            row.mark:SetShown(selected)
            if selected then
                local C = ns.UI.C
                row.bg:SetColorTexture(C.control[1], C.control[2], C.control[3], 1)
                row.bg:Show()
            else
                row.bg:Hide()
            end
            row:Show()
        end
    end
    frame.sideTitle:SetText(total == 1 and "This session - 1 death"
        or string.format("This session - %d deaths", total))
end

function Death:Show(index)
    if #self.log == 0 then
        ns.Print("No death recorded yet this session.")
        return
    end

    -- Clamped, not wrapped: paging past the oldest death and landing on the
    -- newest reads as the list jumping, not as an edge.
    index = index or self.showing or #self.log
    if index < 1 then index = 1 end
    if index > #self.log then index = #self.log end
    self.showing = index
    local snapshot = self.log[index]

    if not frame then BuildWindow() end
    frame.disarmClear()

    -- The killer, when the recap named one readably. The name is already
    -- through SafeName's door or it would not be in the snapshot.
    if snapshot.killer then
        frame.sub:SetText(string.format("%s  -  killed by %s  -  the last %d seconds",
            snapshot.when or "", snapshot.killer, WINDOW))
    else
        frame.sub:SetText(string.format("%s  -  the last %d seconds",
            snapshot.when or "", WINDOW))
    end

    frame.place:SetText(snapshot.where or "")

    -- The portrait decides where the header starts: with a face, the text
    -- moves out of its way; without one, it keeps the left margin every
    -- other window in this addon uses.
    local hasPortrait = PaintPortrait(snapshot.killerArt)
    frame.title:ClearAllPoints()
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", hasPortrait and 82 or 16, -14)

    PaintSideList()

    frame.verdict:SetText(table.concat(snapshot.analysis.lines, "\n"))

    -- Rows: only what falls inside the promised window - the first live
    -- death showed hits from five minutes earlier under a subtitle saying
    -- ten seconds. The LAST of those win the visible slots, oldest on top.
    local events, stale = Death.RecentEvents(snapshot.events, WINDOW)
    if stale and #events > 0 then
        -- Nothing recent, so the promise is re-worded rather than broken.
        frame.sub:SetText((snapshot.when or "")
            .. "  -  nothing in the last seconds; the events below are older")
    end
    local first = math.max(1, #events - ROWS_MAX + 1)
    local shown = 0
    local maxHP = snapshot.maxHP

    -- Anchored under the verdict, which wraps: measured, not guessed.
    local top = HEADER_BOTTOM + (frame.verdict:GetStringHeight() or 0) + 14

    for i = first, #events do
        shown = shown + 1
        local row = frame.rows[shown]
        local ev = events[i]

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 16,
            -(top + (shown - 1) * (ROW_H + 2)))

        -- What the hover reads. Kept on the row rather than closed over,
        -- because these twelve frames are pooled across every death in the
        -- list and a closure would answer for the one they were built with.
        row.ev = ev

        row.when:SetText(string.format("-%.1fs", ev.t))

        -- A melee hit carries no spell id, and Blizzard's own recap draws a
        -- sword for it rather than a hole. 135274 is the fallback icon
        -- EllesmereUI's recap tooltip ships with, for the same case.
        local icon = ev.spellID and ns.SpellTexture(ev.spellID)
        row.icon:SetTexture(icon or 135274)
        row.icon:Show()

        -- What, then who, in the quiet grey: "Melee - Heavyweight Golem".
        -- The mob's name is part of the story and the owner asked for it by
        -- name; inline and dimmed so the amounts stay the loudest column.
        if ev.who then
            row.what:SetText((ev.name or "")
                .. "  |cff9ba3af" .. ev.who .. "|r")
        else
            row.what:SetText(ev.name or "")
        end
        local sign = ev.heal and "+" or "-"
        local extra = ev.overkill
            and string.format("  (%s overkill)", ns.ShortNumber(ev.overkill))
            or ""
        row.amount:SetText(sign .. ns.ShortNumber(ev.amount) .. extra)

        -- The fill is the health AFTER this event, so the story reads as a
        -- draining bar. A heal row paints the same bar in the green.
        local pct = (maxHP and ev.hp) and math.min(1, ev.hp / maxHP) or 0
        row.fill:SetWidth(math.max(1, MAIN_W * pct))
        if ev.heal then
            row.fill:SetColorTexture(0.10, 0.35, 0.12, 0.55)
        else
            row.fill:SetColorTexture(0.42, 0.08, 0.08, 0.55)
        end
        row:Show()
    end
    for i = shown + 1, ROWS_MAX do
        frame.rows[i].ev = nil
        frame.rows[i]:Hide()
    end

    if snapshot.reason then
        frame.avail:SetText("|cffff8040" .. snapshot.reason .. "|r")
    else
        local bits = {}
        for _, entry in ipairs(snapshot.avail or {}) do
            local state
            if entry.remaining == 0 then
                state = "|cff67c971ready|r"
            elseif entry.remaining then
                state = string.format("|cff9ba3af%ds to go|r",
                    math.floor(entry.remaining + 0.5))
            else
                state = "|cff626a76" .. (entry.why or "unknown") .. "|r"
            end
            bits[#bits + 1] = entry.name .. ": " .. state
        end
        frame.avail:SetText(#bits > 0
            and ("Defensives by our own clock -  " .. table.concat(bits, "   "))
            or "No defensives picked on the Timeline page yet.")
    end

    frame:Show()
end

-- Throwing the session's deaths away. The skull goes with them - it counts
-- what is in the list, and a skull over an empty list is a promise the
-- click cannot keep.
function Death:Clear()
    local had = #self.log
    Death.ClearLog(self.log)
    self.snapshot = nil
    self.showing = nil
    if frame then frame:Hide() end
    Death.RefreshIcon()
    ns.Print(had == 1 and "The one death this session is cleared."
        or string.format("%d deaths cleared.", had))
end

---------------------------------------------------------------------------
-- The icon on the screen - the owner's ask in his words: "ein kleines
-- death icon auf dem screen, das wir jederzeit frei bewegen oder locken
-- können. beim klick öffnet sich das dann."
--
-- Deliberately NOT an Edit Mode mover: "jederzeit frei bewegen" is the
-- minimap button's contract, not the bars' - drag it whenever it is not
-- locked, and the lock lives on the Deaths page. It appears with the first
-- death and not before: an always-on skull promising nothing is furniture.
---------------------------------------------------------------------------
local iconButton

local function IconConfig()
    ns.db.death = ns.db.death or {}
    ns.db.death.icon = ns.db.death.icon or {}
    return ns.db.death.icon
end

local function BuildIcon()
    local C = ns.UI.C

    iconButton = CreateFrame("Button", "ZwoelfStuffDeathIcon", UIParent)
    iconButton:SetSize(30, 30)
    iconButton:SetFrameStrata("MEDIUM")
    iconButton:SetClampedToScreen(true)
    iconButton:SetMovable(true)
    iconButton:RegisterForDrag("LeftButton")
    iconButton:Hide()

    local bg = iconButton:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(iconButton)
    bg:SetColorTexture(C.windowBg[1], C.windowBg[2], C.windowBg[3], 0.85)

    local edge = ns.CreateBorder(iconButton, 1, "BORDER")
    edge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)

    -- The client's own skull, shipped since the beginning of time - not a
    -- traced one, for the same reason the Discord row carries no mark.
    local skull = iconButton:CreateTexture(nil, "ARTWORK")
    skull:SetPoint("TOPLEFT", iconButton, "TOPLEFT", 3, -3)
    skull:SetPoint("BOTTOMRIGHT", iconButton, "BOTTOMRIGHT", -3, 3)
    skull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")

    -- How many this session, in the corner. The number is the reason to
    -- click at all after a rough pull.
    iconButton.count = iconButton:CreateFontString(nil, "OVERLAY")
    ns.Media.ApplyFont(iconButton.count, nil, 10, "OUTLINE")
    iconButton.count:SetPoint("BOTTOMRIGHT", iconButton, "BOTTOMRIGHT", -1, 1)

    iconButton:SetScript("OnClick", function() Death:Show() end)

    iconButton:SetScript("OnDragStart", function(self)
        if IconConfig().locked then return end
        self:StartMoving()
    end)
    iconButton:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Written back in CENTRE terms and reapplied, so the saved numbers
        -- and the frame never disagree about what was just dragged.
        local cfg = IconConfig()
        local x, y = self:GetCenter()
        local px, py = UIParent:GetCenter()
        cfg.x = math.floor(x - px + 0.5)
        cfg.y = math.floor(y - py + 0.5)
        Death.RefreshIcon()
    end)

    iconButton:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Deaths this session: " .. #Death.log, 1, 1, 1)
        GameTooltip:AddLine(IconConfig().locked
            and "Click to open. The position is locked on the Deaths page."
            or "Click to open. Drag to move it.", 0.6, 0.63, 0.69, true)
        GameTooltip:Show()
    end)
    iconButton:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
end

function Death.RefreshIcon()
    if not ns.UI then return end
    local cfg = (ns.db and ns.db.death and ns.db.death.icon) or {}
    if #Death.log == 0 or cfg.show == false then
        if iconButton then iconButton:Hide() end
        return
    end
    if not iconButton then BuildIcon() end

    iconButton:ClearAllPoints()
    iconButton:SetPoint("CENTER", UIParent, "CENTER",
        cfg.x or 320, cfg.y or -180)
    iconButton.count:SetText(tostring(#Death.log))
    iconButton:Show()
end

---------------------------------------------------------------------------
-- The probe - every question at once, the way the Routes questions were
-- settled in one trip instead of five. Run it dead, on a corpse, after a
-- wipe: /zs death probe. What it prints decides which window fields stop
-- saying "unknown".
---------------------------------------------------------------------------
local function Verdict(value)
    if value == nil then return "|cff888888absent|r" end
    if not ns.CanCompute(value) then return "|cffff8040SECRET|r" end
    -- A nested table's address answers nothing; its length at least says
    -- "the list you are looking for may live here".
    if type(value) == "table" then
        return string.format("|cff7ec6d4table, %d list entries|r", #value)
    end
    return "|cff40ff40" .. tostring(value) .. "|r"
end

local function DumpTable(label, tbl)
    ns.Print("  " .. label .. ":")
    local keys = {}
    for key in pairs(tbl) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    for _, key in ipairs(keys) do
        ns.Print("    " .. key .. " = " .. Verdict(tbl[key]))
    end
end

function Death:Probe()
    ns.Print("|cffffd100death probe|r - the damage meter first:")
    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType
        and Enum and Enum.DamageMeterType) then
        ns.Print("  C_DamageMeter is |cffff4040not on this client|r.")
        return
    end

    -- BOTH session types, and the session's OWN fields before anything in
    -- it. The first in-game run printed "no deaths this fight" because the
    -- list sat under a field this code had guessed wrong - a probe that
    -- dumps the parent cannot be blinded that way.
    for _, sessionType in ipairs({
        { key = Enum.DamageMeterSessionType.Current, label = "Current" },
        { key = Enum.DamageMeterSessionType.Overall, label = "Overall" },
    }) do
        local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType,
            sessionType.key, Enum.DamageMeterType.Deaths)
        if not ok or type(session) ~= "table" then
            ns.Print("  " .. sessionType.label .. ": no Deaths session.")
        else
            DumpTable(sessionType.label .. " session, every field", session)
            local list = session.combatSources or session.sources
            if type(list) == "table" and list[1] then
                DumpTable(sessionType.label .. " first death, every field", list[1])
            end
        end
    end

    local recapID, why = Death.OwnRecapID()
    if not recapID then
        ns.Print("  own recap: |cffff8040" .. (why or "?") .. "|r")
        return
    end
    ns.Print("  own recap id: " .. Verdict(recapID))

    local okEv, raw = pcall(C_DeathRecap.GetRecapEvents, recapID)
    if not okEv or type(raw) ~= "table" then
        ns.Print("  GetRecapEvents |cffff4040threw or answered nothing|r.")
        return
    end
    ns.Print(string.format("  %d recap events. The newest, every field:", #raw))
    if raw[1] then DumpTable("event 1", raw[1]) end

    -- What the header can draw and say, measured rather than assumed.
    local _, _, _, _, art = Death.ReadRecap(recapID)
    if art then
        ns.Print("  portrait: creature "
            .. Verdict(art.creatureID) .. ", display " .. Verdict(art.displayID))
    else
        ns.Print("  portrait: |cffff8040no creature or display id in the recap|r")
    end
    local where, short = Death.Where()
    ns.Print("  where: |cff40ff40" .. where .. "|r  (short: " .. short .. ")")
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------

-- Blizzard's own recap window opened for the owner's death while our first
-- damage-meter search came up empty. The id it opens with is by definition
-- OUR recap, so the opener is hooked and the id kept. Everything here is
-- guarded twice: the frame lives in a load-on-demand Blizzard addon, so the
-- global may not exist yet at our load - hence the second attempt on
-- ADDON_LOADED - and on some client this hook may simply never fire, which
-- costs nothing.
local recapHooked = false
local function TryHookBlizzardRecap()
    if recapHooked then return end
    if not (type(hooksecurefunc) == "function"
        and type(OpenDeathRecapUI) == "function") then
        return
    end
    recapHooked = true
    hooksecurefunc("OpenDeathRecapUI", function(recapID)
        if not (ns.CanCompute(recapID) and type(recapID) == "number"
            and recapID > 0) then
            return
        end
        -- A fresh death whose capture found nothing gets a second chance
        -- with the definitive id - and the window, if it is up showing
        -- "not enough was readable", is repainted rather than left lying.
        local snapshot = Death.snapshot
        if snapshot and snapshot.events == nil
            and (GetTime() - snapshot.at) < 120 then
            -- replace: this is the SAME death getting a better answer, not
            -- a new one for the pager.
            Death:Capture(recapID, true)
            if frame and frame:IsShown() then Death:Show(#Death.log) end
        end
    end)
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_DEAD")
watcher:RegisterEvent("ADDON_LOADED")
-- The only thing that knows a BOSS is what you are standing in front of.
-- BigWigs runs its entire engage logic off this pair, so the name arrives
-- readable; it is still put through the same door as every other string.
watcher:RegisterEvent("ENCOUNTER_START")
watcher:RegisterEvent("ENCOUNTER_END")
watcher:SetScript("OnEvent", function(_, event, _, encounterName)
    if event == "ADDON_LOADED" then
        TryHookBlizzardRecap()
        return
    end

    if event == "ENCOUNTER_START" then
        -- The first payload is the encounter id, the second its name.
        Death.encounter = (ns.CanCompute(encounterName)
            and type(encounterName) == "string" and encounterName ~= "")
            and encounterName or nil
        return
    end

    if event == "ENCOUNTER_END" then
        Death.encounter = nil
        return
    end

    if ns.db and ns.db.death and ns.db.death.record == false then return end

    -- The recap needs a moment to exist: capture shortly after the fall,
    -- and once more a little later in case the meter was still writing.
    C_Timer.After(0.8, function()
        local snapshot = Death:Capture()
        local open = not (ns.db and ns.db.death) or ns.db.death.openOnDeath ~= false
        if snapshot.events == nil then
            C_Timer.After(2.0, function()
                -- replace: the same death, asked again once the meter had
                -- time to write - not a second entry in the pager.
                snapshot = Death:Capture(nil, true)
                if open then Death:Show(#Death.log) end
            end)
        elseif open then
            Death:Show(#Death.log)
        end
    end)
end)

TryHookBlizzardRecap()
