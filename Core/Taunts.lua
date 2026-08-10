---------------------------------------------------------------------------
-- Taunts - saying that you took it, and asking the other tank to.
--
-- Roadmap item 6, the owner's own order: "10, dann 6, dann 1."
--
-- WHAT IS KNOWABLE, and the whole design follows from it:
--
--   YOUR taunt          UNIT_SPELLCAST_SUCCEEDED on "player" is the one
--                       combat fact this client still hands an addon. It is
--                       what History.lua already runs on.
--   the target's NAME   readable, even in a dungeon. UnitGUID is withheld
--                       for every mob on 12.0 and UnitName is not - measured
--                       in game, see the handoff.
--   the OTHER tank's    NOT knowable. Since 12.0.5 another player's INSTANT
--   taunt               cast is not announced at all, and every taunt in the
--                       game is instant. The combat log is closed. So this
--                       addon cannot tell you the co-tank taunted, and the
--                       settings page says so rather than pretending.
--   "swap at X stacks"  NOT knowable, and not in 12.1 either: a foreign
--                       aura's value cannot be read, only displayed.
--
-- What is left is exactly what a tank actually needs from a swap: TELL THE
-- OTHER TANK. A message in chat reaches them whatever addons they run, which
-- is better than anything an addon-to-addon channel could do here.
--
-- IT IS OFF UNTIL ASKED FOR. A feature that starts writing in party chat
-- after an update is the worst surprise this addon could hand somebody.
---------------------------------------------------------------------------
local _, ns = ...

local Taunts = {}
ns.Taunts = Taunts

-- THE LIST, and it is not from memory. Read out of NorthernSkyRaidTools'
-- shipping Reminders.lua, which keys exactly this set as `Taunts` - the same
-- door the externals list came through (MRT's DEFTAR). Cross-checked against
-- its LibDFramework spell table, which files the same ids per spec.
--
-- Death Grip is in the list because it taunts in Blood and only in Blood; a
-- Frost death knight pressing it is not taking anything, so the spec is
-- checked before it announces.
Taunts.SPELLS = {
    { spellID = 355,    class = "WARRIOR" },      -- Taunt
    { spellID = 56222,  class = "DEATHKNIGHT" },  -- Dark Command
    { spellID = 49576,  class = "DEATHKNIGHT", spec = 250 },  -- Death Grip, Blood
    { spellID = 62124,  class = "PALADIN" },      -- Hand of Reckoning
    { spellID = 115546, class = "MONK" },         -- Provoke
    { spellID = 6795,   class = "DRUID" },        -- Growl
    { spellID = 185245, class = "DEMONHUNTER" },  -- Torment
}

local byID = {}
for _, entry in ipairs(Taunts.SPELLS) do byID[entry.spellID] = entry end

function Taunts.Get(spellID) return byID[spellID] end

-- Pure: is this cast a taunt, for somebody of this spec. `specID` may be nil
-- (the client answers 0 for a while after login) and a nil spec must not
-- swallow a real taunt - only Death Grip is ever refused by it.
function Taunts.IsTaunt(spellID, specID)
    local entry = byID[spellID]
    if not entry then return false end
    if entry.spec and specID and entry.spec ~= specID then return false end
    return true
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
Taunts.DEFAULT_MESSAGE = "Taunt: %t"
Taunts.DEFAULT_ASK = "%n, bitte taunten!"

function Taunts.Config()
    ns.db.taunts = ns.db.taunts or {}
    local cfg = ns.db.taunts

    -- The channels are seeded HERE and not in ns.DEFAULTS, for the reason the
    -- externals ones are: a channel you switch OFF is stored by being
    -- missing, and ApplyDefaults fills in what is missing - so a default
    -- would switch it back on at every login and no amount of clicking would
    -- keep it off.
    cfg.channels = cfg.channels or {}
    if next(cfg.channels) == nil then cfg.channels.GROUP = true end

    return cfg
end

function Taunts.ChannelOn(value)
    return Taunts.Config().channels[value] and true or false
end

function Taunts.ToggleChannel(value)
    local cfg = Taunts.Config()
    cfg.channels[value] = (not cfg.channels[value]) or nil
    for _ in pairs(cfg.channels) do return end
    cfg.channels.GROUP = true
end

---------------------------------------------------------------------------
-- WHO THE OTHER TANK IS
--
-- Pure, and it takes the roster as a list for the same reason the externals
-- one does: a raid with three tanks in it is not something a self test can
-- arrange in game.
--
-- Answers the FIRST other tank. In a five-man there is at most one, and in a
-- raid the person you are swapping with is the one you have named - which is
-- what the assignment is for.
---------------------------------------------------------------------------
function Taunts.CoTank(roster, assignedName)
    if type(roster) ~= "table" then return nil end

    if assignedName then
        for _, member in ipairs(roster) do
            if member.name == assignedName and not member.isPlayer then
                return member, "assigned"
            end
        end
        -- Named somebody who has left. Falling back to the rule is right and
        -- saying so matters - the same rule the externals slots follow.
    end

    for _, member in ipairs(roster) do
        if not member.isPlayer and member.role == "TANK" then
            return member, "the other tank"
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- What it says
---------------------------------------------------------------------------
-- %s the taunt, %t what you taunted, %n the other tank.
function Taunts.Message(template, spellName, targetName, personName)
    if type(template) ~= "string" or template == "" then
        template = Taunts.DEFAULT_MESSAGE
    end
    return ns.Chat.Fill(template, {
        s = spellName, t = targetName, n = personName,
    })
end

---------------------------------------------------------------------------
-- Announcing
---------------------------------------------------------------------------
-- TWO PRESSES IN A SECOND ARE ONE ANNOUNCE. A taunt that does not land is
-- pressed again immediately, and a tank who spams his own group because his
-- first taunt missed will switch the feature off and never come back.
Taunts.QUIET = 2.0
local lastAt = 0

-- Pure, so the rule can be checked without a clock: has enough time passed.
function Taunts.MaySpeak(now, previous, quiet)
    if not previous then return true end
    return (now - previous) >= (quiet or Taunts.QUIET)
end

-- Whether an announce should happen AT ALL, before anything is written. Pure,
-- because every one of these is a state that has to be arranged rather than
-- waited for.
function Taunts.ShouldAnnounce(cfg, inGroup, inInstance)
    if not cfg.announce then return false, "switched off" end
    if cfg.onlyInGroup ~= false and not inGroup then
        return false, "not in a group"
    end
    if cfg.onlyInInstance and not inInstance then
        return false, "not in an instance"
    end
    return true
end

local function InInstance()
    if not IsInInstance then return false end
    local inside = IsInInstance()
    return inside and true or false
end

-- The one this whole file exists for. Answers whether it said anything, and
-- why not when it did not - the diagnostic prints that line rather than
-- leaving "it does nothing" as the only description.
function Taunts.Announce(spellID, targetName)
    local cfg = Taunts.Config()

    local ok, why = Taunts.ShouldAnnounce(cfg, IsInGroup(), InInstance())
    if not ok then return false, why end

    local now = GetTime and GetTime() or 0
    if not Taunts.MaySpeak(now, lastAt > 0 and lastAt or nil, cfg.quiet) then
        return false, "just said it"
    end

    local roster = ns.Roster()
    local person = Taunts.CoTank(roster, cfg.assigned)

    local going = ns.Chat.Where(cfg.channels)
    for index = #going, 1, -1 do
        if going[index].channel == "WHISPER" and not person then
            table.remove(going, index)
        end
    end
    if #going == 0 then
        return false, "there is nowhere to send it"
    end

    local text = Taunts.Message(cfg.message,
        ns.SpellName(spellID) or "Taunt", targetName, person and person.name)

    local sent, note = ns.Chat.Post(text, going, person and person.name)
    if sent then lastAt = now end
    return sent, note
end

-- "Your turn" - the other half of a swap, and the half an addon CAN do
-- something about. Bind it to a key with a macro: /zs taunt ask
function Taunts.Ask()
    local cfg = Taunts.Config()
    local person, why = Taunts.CoTank(ns.Roster(), cfg.assigned)

    local going = ns.Chat.Where(cfg.channels)
    for index = #going, 1, -1 do
        if going[index].channel == "WHISPER" and not person then
            table.remove(going, index)
        end
    end
    if #going == 0 then
        return false, "there is nowhere to send it - you are not in a group"
    end

    local text = Taunts.Message(cfg.ask or Taunts.DEFAULT_ASK,
        nil, nil, person and person.name)
    local sent, note = ns.Chat.Post(text, going, person and person.name)
    return sent, note or why
end

---------------------------------------------------------------------------
-- Watching
--
-- One event, on the player's own unit. Not the combat log - that is closed on
-- 12.0 - and not a hook on the action bars, which would miss a macro.
---------------------------------------------------------------------------
local watcher = CreateFrame("Frame")

-- The handler, with a name on it: the desktop harness cannot fire an event,
-- so without this the whole path from "a spell was cast" to "something was
-- said" would only ever run for the first time on his screen.
function Taunts.OnCast(spellID)
    if not ns.db then return end
    if not ns.Modules:IsOn("cotanks") then return end

    -- The spec, out of the key everything per-character is filed under. Nil
    -- while the client is still answering 0, and nil is allowed to pass: only
    -- Death Grip is ever refused for being the wrong spec, and a missed
    -- announce is better than a swallowed one.
    local key, known = ns.SpecKey()
    local specID = known and tonumber(key:match(":(%d+)$")) or nil
    if not Taunts.IsTaunt(spellID, specID) then return end

    -- THE TARGET IS READ NOW OR NEVER. The event carries no target, and a
    -- moment later the mob may be dead, out of range or replaced by whatever
    -- you tabbed to. A name that is not readable is left out of the sentence
    -- rather than guessed at.
    local seen = UnitName("target")
    local targetName = (ns.CanCompute(seen) and type(seen) == "string")
        and seen or nil

    return Taunts.Announce(spellID, targetName)
end

function Taunts:Start()
    if self.started then return end
    self.started = true

    watcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    watcher:SetScript("OnEvent", function(_, _, _, _, spellID)
        Taunts.OnCast(spellID)
    end)
end

---------------------------------------------------------------------------
-- What it would do, printed
---------------------------------------------------------------------------
function Taunts:Dump()
    ns.Print("|cffffd100taunts|r - what a taunt of yours would do.")

    local cfg = Taunts.Config()
    local ok, why = Taunts.ShouldAnnounce(cfg, IsInGroup(), InInstance())
    ns.Print("  announce: " .. (ok and "|cff40ff40yes|r"
        or ("|cff888888no - " .. tostring(why) .. "|r")))

    local person = Taunts.CoTank(ns.Roster(), cfg.assigned)
    ns.Print("  the other tank: " .. (person and ("|cff40ff40" .. person.name .. "|r")
        or "|cff888888nobody here|r"))

    local going = ns.Chat.Where(cfg.channels)
    local names = {}
    for _, where in ipairs(going) do names[#names + 1] = where.channel end
    ns.Print("  channels: " .. (#names > 0 and table.concat(names, ", ")
        or "|cff888888nowhere|r"))

    ns.Print("  it would say: |cffffd100"
        .. Taunts.Message(cfg.message, "Dark Command", "Heavyweight Golem",
            person and person.name) .. "|r")

    local _, class = UnitClass("player")
    local mine = {}
    for _, entry in ipairs(Taunts.SPELLS) do
        if entry.class == class then
            mine[#mine + 1] = ns.SpellName(entry.spellID)
                or tostring(entry.spellID)
        end
    end
    ns.Print("  watching: " .. (#mine > 0 and table.concat(mine, ", ")
        or "|cff888888your class has no taunt in the list|r"))
end
