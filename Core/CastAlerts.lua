---------------------------------------------------------------------------
-- CAST ALERTS - the third book of reminders.
--
-- "alert system eine combination aus reminder + balken + x" (owner,
-- 2026-08-18). The balken is Core/CastBar.lua; this is the reminder half,
-- and it is a reminder in code rather than a copy of one: Core/Reminders.lua
-- became a class in 4.84.0 and Core/AnswerAlerts.lua was its second
-- instance. This is the third, so the three cannot drift - the list, the
-- words, the look, the flash, the rules and the edit-mode box are all the
-- reminders' own.
--
-- WHAT ONE WATCHES is a rank and an aim, never a spell: on this patch the
-- spell being cast is a secret value and cannot be named (Core/Casts.lua's
-- header says why, with the code that proves it). So an alert is "a
-- lieutenant is casting at you" and its icon is the CAST's icon, handed
-- straight through by the engine.
--
-- THE VOICE lives here too, on the same rising edge as the sound: the
-- reminders class calls spec.OnShow(cfg) once when a message comes up, never
-- while it is being placed or previewed.
---------------------------------------------------------------------------
local _, ns = ...

local Alerts

---------------------------------------------------------------------------
-- Pure rules
---------------------------------------------------------------------------
local Rules = {}
ns.CastAlertRules = Rules

-- WHICH CAST, IF ANY, THIS ALERT IS ABOUT. The first live cast that matches
-- both of the alert's sets - and the sets are the same shape as everywhere
-- else in this addon: absent means "any", present means "these".
--
-- Pure on purpose: the live list is passed in, so the desk can ask this
-- question without a dungeon.
function Rules.Match(cfg, live)
    if type(cfg) ~= "table" then return nil end
    for _, entry in ipairs(live or {}) do
        local ranks = cfg.ranks
        local aims = cfg.aims
        local rankOK = type(ranks) ~= "table" or ranks[entry.rank or ""] == true
        local aimOK = type(aims) ~= "table" or aims[entry.aim or "nobody"] == true
        -- AND THE ONE FILTER THAT NAMES SOMETHING. Left out of the first
        -- draft, which is the shape of the bug the "test the wiring, not
        -- just the rule" lesson is about: MobWanted was written, tested and
        -- green, the page wrote cfg.mobs, and nothing ever asked.
        local mobOK = ns.CastRules.MobWanted(cfg.mobs, entry.mob, entry.npc)
        if rankOK and aimOK and mobOK then return entry end
    end
    return nil
end

-- The words, through the cast module's one token door.
function Rules.Words(text, entry)
    local spell
    if type(entry) == "table" and entry.likelySpell and ns.SpellName then
        spell = ns.SpellName(entry.likelySpell)
    end
    if type(entry) ~= "table" then
        return ns.CastRules.Words(text, nil, nil, nil)
    end
    return ns.CastRules.Words(text, entry.rank, entry.aim, entry.mob, spell)
end

---------------------------------------------------------------------------
-- WHAT EACH ALERT IS CURRENTLY ABOUT - kept HERE, never on the alert.
--
-- Two reasons, and the second one is the serious one.
--
-- 1. The live rows are POOLED (Core/Casts.lua): the same table is filled in
--    again on the next walk, so a reference held across ticks quietly starts
--    describing a different cast. What is kept here is a COPY of the four
--    fields that are drawn.
--
-- 2. An alert's cfg IS the saved file. `cfg.dkEntry = <live row>` would put
--    the cast's name, icon and id - all SECRET VALUES on this patch - into
--    SavedVariables, and a secret value cannot be written out. That is not a
--    style point: it is a saved file that fails to save.
--
-- Weak keys, so an alert somebody deletes takes its row with it.
---------------------------------------------------------------------------
local about = setmetatable({}, { __mode = "k" })

local function About(cfg)
    local row = about[cfg]
    if not row then
        row = {}
        about[cfg] = row
    end
    return row
end

---------------------------------------------------------------------------
-- The spec
---------------------------------------------------------------------------
local SPEC = {
    key = "castAlerts",
    module = "casts",
    noun = "Alert",
    empty = "No cast alerts. |cffffd100/zs|r, then Casts on you, "
        .. "the Alerts tab.",

    -- The list travels with the profile inside the cast module's own config,
    -- the way the answer alerts live in ns.db.answers.alerts.
    store = function()
        local cfg = ns.Casts.Config()
        cfg.alerts = cfg.alerts or {}
        return cfg.alerts
    end,

    Defaults = function(base)
        base.text = "%rank casting at %who"
        -- No spell: there is none to pick on this patch. The trigger is the
        -- pair of sets below.
        base.trigger = nil
        base.spellID = nil
        base.ranks = { standard = false, lieutenant = true, boss = true }
        -- UNKNOWN IS ON, and leaving it off was a real bug the desk caught:
        -- inside a dungeon the cast target's role and class can be withheld,
        -- so the honest answer is `unknown` - and an alert that watched only
        -- `me` would have been silent in exactly the place it is for.
        base.aims = { me = true, unknown = true,
                      tank = false, group = false, nobody = false }
        -- Up while the cast is up, and no longer: a cast alert that lingers
        -- is a warning about something that already landed.
        base.show = base.show or {}
        base.show.mode = "always"
        base.y = 300
        base.color = { 1.00, 0.55, 0.20 }
        -- Its own voice line, so two alerts can say different things. Empty
        -- means "say nothing", which is the default - a voice on every alert
        -- at once is how a feature gets switched off.
        base.voice = ""
        return base
    end,

    -- THE FACT THE TRIGGER READS: is a cast this alert cares about on screen
    -- right now. What it found is copied into the side table above, so Text
    -- and Icon draw the same cast the state was decided by.
    State = function(cfg)
        if not ns.Casts then return nil, "the cast module is not loaded" end
        local entry = Rules.Match(cfg, ns.Casts.live)
        local row = About(cfg)
        if entry then
            row.rank, row.aim, row.mob = entry.rank, entry.aim, entry.mob
            row.likelySpell = entry.likelySpell
            -- The texture may be secret. It is carried and handed to
            -- SetTexture, and it never goes near the saved file.
            row.texture = entry.texture
            return "casting"
        end
        row.rank, row.aim, row.mob, row.texture = nil, nil, nil, nil
        row.likelySpell = nil
        return "idle"
    end,

    Fires = function(_, state)
        return state == "casting"
    end,

    WhyNot = function()
        return "Nothing is casting that this one watches."
    end,

    Text = function(cfg)
        return Rules.Words(cfg.text, About(cfg))
    end,

    -- THE CAST'S OWN ICON. Secret or not, it only ever reaches SetTexture.
    Icon = function(cfg)
        return About(cfg).texture
    end,

    -- THE VOICE, on the rising edge. The alert's own line first, then the
    -- module's line for that rank - so somebody who wants one sentence sets
    -- it once on the page and somebody who wants a different one per alert
    -- can have that too.
    OnShow = function(cfg)
        if not ns.Casts then return end
        local voice = ns.Casts.Config().voice
        if not (voice and voice.enabled) then return end
        local entry = About(cfg)
        local line = cfg.voice
        if type(line) == "string" and line ~= "" then
            ns.Casts.Speak(Rules.Words(line, entry), voice)
            return
        end
        line = ns.Casts.Line(voice, entry)
        if line then ns.Casts.Speak(line, voice) end
    end,

    When = function(cfg)
        local ranks, aims = {}, {}
        for _, rank in ipairs(ns.Casts.RANKS) do
            if type(cfg.ranks) ~= "table" or cfg.ranks[rank.key] then
                ranks[#ranks + 1] = rank.text:lower()
            end
        end
        for _, aim in ipairs(ns.Casts.AIMS) do
            if type(cfg.aims) ~= "table" or cfg.aims[aim.key] then
                aims[#aims + 1] = aim.text:lower()
            end
        end
        return string.format("when %s cast %s",
            #ranks > 0 and table.concat(ranks, " or ") or "nothing",
            #aims > 0 and table.concat(aims, " or ") or "nowhere")
    end,
}

---------------------------------------------------------------------------
-- The book
--
-- ns.Reminders.New reaches the class through __index on the instance, the
-- same door Core/AnswerAlerts.lua uses.
---------------------------------------------------------------------------
Alerts = ns.Reminders.New(SPEC)
ns.CastAlerts = Alerts
Alerts.Rules = Rules
Alerts.SPEC = SPEC

---------------------------------------------------------------------------
-- REPAINT - the words and the icon follow the cast, not only the state.
--
-- Reminders:Refresh decides whether a message is UP; the words and the icon
-- are written by Style, which Refresh does not call. For a reminder that is
-- right - its text is a sentence somebody typed. For a cast alert it is not:
-- two lieutenants in a row are two different casts under one message, and
-- without this the second one would wear the first one's icon.
--
-- So: ask State (which fills the side table), and restyle only the ones
-- whose answer actually changed. Nothing is drawn while nothing changes,
-- which is what makes this safe to call ten times a second.
---------------------------------------------------------------------------
function Alerts:Repaint()
    for index = 1, self:Count() do
        local cfg = self:Get(index)
        if cfg then
            self:State(cfg)
            local row = About(cfg)
            if row.rank ~= row.drawnRank or row.aim ~= row.drawnAim
                or row.mob ~= row.drawnMob then
                row.drawnRank, row.drawnAim, row.drawnMob =
                    row.rank, row.aim, row.mob
                self:Style(index)
            end
        end
    end
    self:Refresh()
end
