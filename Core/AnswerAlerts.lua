---------------------------------------------------------------------------
-- Answer alerts - reminders that fire when somebody asks you for one
--
-- Owner, 2026-08-17: "eigentlich ist das der reminder, aber den nennen wir
-- alert ... speziell fuer das system. das kannste auch nur mit genau den
-- spells die du zur verfuegung hast konfigurieren." Then, seeing the
-- reminders page: "bau doch einfach die reminder-seite da ein und in die
-- rechte seite, wo bei reminder die spells sind, haust du die answer spells."
--
-- So this is not a second renderer. It is Core/Reminders.lua's class with a
-- SECOND SPEC: a book of messages that keeps its own list under the answers'
-- settings, draws with the reminders' frames, flashes with the reminders'
-- pulse, is placed by the reminders' movers - and differs in exactly the
-- things a spec is for. What it WATCHES is not the Cooldown Manager but the
-- request packets the answer bar hears; what it SAYS carries the asker's
-- name; and WHEN IT GOES is a setting, because a request is a moment, not a
-- state - "nach x sekunden, oder 3 mal aufleuchten, gib den leuten optionen".
--
-- The list lives in ns.db.answers.alerts: one module switch (answers), one
-- page (the Alerts tab of the answer page), one profile key. Off out of the
-- box in the only sense that matters - a fresh profile has no alerts, and an
-- alert only exists once somebody pressed New alert.
--
-- THE ASKS. Answers.lua tells this file about two moments: somebody asked
-- (Asked) and you cast something (Settle). Between them the request is
-- "live" for the spell it named, and every alert watching that spell is up
-- - each under its own ending, because two alerts on one spell may want to
-- stay for different lengths. A taunt request names no spell, so it is
-- filed under a key of its own and matched by "is your spell a taunt".
---------------------------------------------------------------------------
local _, ns = ...

local Alerts -- the book, made at the foot of the file

-- [spellID] = { who = "Akui", at = <GetTime> } ; the taunt request under TAUNT
local asks = {}
local TAUNT = "taunt"

---------------------------------------------------------------------------
-- The vocabulary
---------------------------------------------------------------------------
-- WHEN IT GOES AWAY. "asked" follows the request itself (the bar's own
-- "how long it shouts") and the answer; the other two are the owner's
-- options. Casting the answer ends it EARLY under every one of them: a
-- message about a thing you have already done is noise, whatever the timer
-- says.
ns.ALERT_ENDINGS = {
    { value = "asked",   text = "When answered or run out",
      hint = "As long as the request itself lasts." },
    { value = "seconds", text = "After a number of seconds" },
    { value = "flashes", text = "After a number of flashes" },
}

---------------------------------------------------------------------------
-- The pure rules - checked on the desk, no screen needed
---------------------------------------------------------------------------
local Rules = {}
ns.AnswerAlertRules = Rules

-- Which key a spell's requests are filed under: its own id, or the one
-- taunt drawer for any taunt.
function Rules.Key(spellID)
    if spellID and ns.Taunts and ns.Taunts.IsTaunt
        and ns.Taunts.IsTaunt(spellID) then
        return TAUNT
    end
    return spellID
end

-- The words, with the asker and the spell filled in. %who and %spell are
-- the two tokens; a taunt has no spell name worth printing, it is "a taunt".
function Rules.Words(text, who, spellID, isTaunt)
    who = (who and who ~= "") and who or "Somebody"
    local spell
    if isTaunt then
        spell = "a taunt"
    else
        spell = spellID and ns.SpellName(spellID) or "a cooldown"
    end
    text = text or ""
    text = text:gsub("%%who", who):gsub("%%spell", spell)
    return text
end

-- When a request that landed at `at` stops keeping this alert up, by the
-- alert's own ending. The request's own life is `linger` (the bar's "how
-- long it shouts"). "flashes" is counted in the flash's own time: N full
-- cycles at flashRate a second - and with the flash off the count still
-- means N cycles' worth of seconds, not a line that never ends.
function Rules.Until(cfg, at, linger)
    at = at or 0
    local mode = cfg and cfg.ending or "asked"
    if mode == "seconds" then
        return at + math.max(0.5, tonumber(cfg.seconds) or 4)
    elseif mode == "flashes" then
        local rate = tonumber(cfg.flashRate) or 0
        if rate <= 0 then rate = 1 end
        return at + math.max(1, tonumber(cfg.flashes) or 3) / rate
    end
    return at + (tonumber(linger) or 8)
end

-- Is a request for this alert's spell live right now?
function Rules.Live(cfg, ask, now, linger)
    if not (cfg and ask) then return false end
    return (now or 0) < Rules.Until(cfg, ask.at, linger)
end

---------------------------------------------------------------------------
-- The spec - what makes this book the answers' and not the reminders'
---------------------------------------------------------------------------
local function Linger()
    local cfg = ns.Answers and ns.Answers.Config()
    return cfg and cfg.linger or 8
end

local function Now()
    return GetTime and GetTime() or 0
end

local SPEC = {
    key    = "answerAlerts",
    module = "answers",
    noun   = "Alert",
    empty  = "No answer alerts. |cffffd100/zs|r, External CD answer, the "
        .. "Alerts tab.",
    -- No sound of its own: the "asked" chime is the answer bar's and plays
    -- from Answers.lua whether or not an alert watches the spell.

    store = function()
        local cfg = ns.Answers.Config()
        cfg.alerts = cfg.alerts or {}
        return cfg.alerts
    end,

    -- The reminders' defaults, plus the ending and its two counts, and the
    -- words with the tokens in them. Higher than a reminder's 180 and the
    -- bar's -260, so the three do not open on top of one another.
    Defaults = function(base)
        base.text    = "%who asks for %spell"
        base.trigger = nil
        -- ALWAYS, not "in combat" as a reminder starts: a request before
        -- the pull is a request, and the moment it lands is the moment
        -- you want the words. The rule block is still there to narrow it.
        base.show.mode = "always"
        base.ending  = "asked"
        base.seconds = 4
        base.flashes = 3
        base.y       = 240
        return base
    end,

    -- The fact: is somebody asking for this spell right now?
    State = function(cfg)
        if not cfg.spellID then return nil, "no spell picked yet" end
        local ask = asks[Rules.Key(cfg.spellID)]
        if Rules.Live(cfg, ask, Now(), Linger()) then return "asked" end
        return "idle"
    end,

    Fires = function(_, state)
        return state == "asked"
    end,

    WhyNot = function()
        return "Nobody is asking for it right now."
    end,

    -- The words on the screen: the asker's name while a request is live,
    -- "Somebody" on the options card and in edit mode.
    Text = function(cfg)
        local key = Rules.Key(cfg.spellID)
        local ask = asks[key]
        return Rules.Words(cfg.text, ask and ask.who or nil, cfg.spellID,
            key == TAUNT)
    end,

    When = function(cfg)
        local mode = cfg.ending or "asked"
        if mode == "seconds" then
            return string.format("when asked, for %ds", cfg.seconds or 4)
        elseif mode == "flashes" then
            return string.format("when asked, for %d flashes", cfg.flashes or 3)
        end
        return "when asked, until answered"
    end,
}

---------------------------------------------------------------------------
-- The book
---------------------------------------------------------------------------
Alerts = ns.Reminders.New(SPEC)
ns.AnswerAlerts = Alerts
Alerts.Rules = Rules

-- Does any alert watch this spell (or, for a taunt request, any taunt)?
-- Answers.lua asks so it can play the chime for somebody who keeps the bar
-- off and an alert on.
function Alerts.Watches(spellID, isTaunt)
    for _, cfg in ipairs(Alerts:All()) do
        if cfg.enabled and cfg.spellID then
            if isTaunt then
                if Rules.Key(cfg.spellID) == TAUNT then return true end
            elseif cfg.spellID == spellID then
                return true
            end
        end
    end
    return false
end

-- Somebody asked. Filed under the spell (or the taunt drawer), and the
-- book refreshed at once rather than on its next tenth of a second - the
-- request and the line should land in the same frame. Returns whether an
-- alert watches it.
function Alerts.Asked(ask)
    if not ask then return false end
    local isTaunt = ns.Comm and ask.kind == ns.Comm.TAUNT
    local key = isTaunt and TAUNT or ask.spellID
    if not key then return false end
    asks[key] = { who = ask.fromShort, at = Now() }
    -- The words carry the asker, so every alert on this key is restyled
    -- before it is shown - Refresh alone only decides shown or hidden.
    for index, cfg in ipairs(Alerts:All()) do
        if cfg.spellID and Rules.Key(cfg.spellID) == key then
            Alerts:Style(index)
        end
    end
    Alerts:Refresh()
    return Alerts.Watches(ask.spellID, isTaunt)
end

-- You cast something. If it answers a live request, the request goes - and
-- with it every alert that was up for it, under every ending.
function Alerts.Settle(spellID)
    local key = Rules.Key(spellID)
    if not key or not asks[key] then return false end
    asks[key] = nil
    Alerts:Refresh()
    return true
end

-- What is live, for the test and the printout.
function Alerts.AskFor(spellID)
    return asks[Rules.Key(spellID)]
end

function Alerts.ClearAsks()
    for key in pairs(asks) do asks[key] = nil end
end
