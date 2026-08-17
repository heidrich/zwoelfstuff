---------------------------------------------------------------------------
-- Answers - the other end of a request. Somebody asks; this is the button.
--
-- Owner, 2026-08-10: "wenn man selbst heiler ist" - so this is the mirror of
-- the externals panel. That one asks; this one is asked.
--
-- WHY THE BAR IS ALWAYS THERE AND ONLY LIGHTS UP, which is the whole shape of
-- this file and is dictated by the game rather than chosen:
--
--   A cell casts a real spell on a real person, so it is a
--   SecureActionButton. Its spell and its target live in ATTRIBUTES, and
--   attributes cannot be changed in combat. Neither can Show, Hide, SetPoint,
--   SetParent or a resize on a protected frame. Verified in EllesmereUIQoL's
--   raid tools, which writes the same rule at the top of its own file and
--   defers every options-driven change to PLAYER_REGEN_ENABLED.
--
--   So a cell CANNOT be pointed at whoever happens to have asked. It is
--   pointed at somebody while you are out of combat - which is the owner's
--   own question, "kann das addon beim gruppen bauen die erkannten spieler
--   schon reinschreiben?", and the answer is yes, that is exactly when.
--
--   What CAN change in combat is how it looks. So every cell that could ever
--   be needed stands there dimmed, and a request makes the right one shout.
--
-- WHAT THIS NEVER DOES: cast. The player presses the button and the GAME
-- casts. There is no path in this addon that reaches a protected function,
-- and there is not going to be one.
---------------------------------------------------------------------------
local _, ns = ...

local Answers = {}
ns.Answers = Answers

local Comm = ns.Comm

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
Answers.DEFAULTS = {
    -- OFF UNTIL ASKED FOR, and this is not the module switch - it is the same
    -- pair the co-tank panel has. The module being on is what makes the
    -- feature exist; this is what puts something on your screen. A bar that
    -- appears unbidden after an update is worse than one nobody has found,
    -- and the module defaults ON so that a request can still TELL you the
    -- feature is there. See Announce below.
    enabled   = false,
    size      = 40,
    gap       = 4,
    linger    = 8,       -- how long a request keeps shouting

    -- WHO GETS A ROW. Owner, 2026-08-10: "man kann keine spieler auswaehlen,
    -- oder einstellen also targets" - and he was right that there was no
    -- answer to that at all: the tanks were picked for you and that was the
    -- whole of it. Three modes and a row count, which is the same shape the
    -- externals panel has for the other direction.
    who       = "tanks",
    rows      = 3,

    -- TAKING THE TARGET IS A SEPARATE QUESTION FROM CASTING, and it is off.
    -- `/cast [@somebody]` needs no target and takes none, which is the whole
    -- reason it is written that way: a healer who clicks a cell mid-pull
    -- keeps whoever they were healing. Owner asked for the target too, so it
    -- is a switch - but a switch, not the default, because losing your target
    -- to a button you pressed for something else is the kind of help nobody
    -- asked for.
    target    = false,
    scale     = 1.0,
    alpha     = 1.0,
    idleAlpha = 0.35,    -- what a cell looks like with nothing to answer
    borderSize      = 1,
    borderTexture   = "None",
    backdrop        = true,
    backdropAlpha   = 1.00,
    backdropTexture = "Blizzard",
    iconZoom        = 0.08,
    -- THE WORDS ON A CELL: the asker's name at the foot, the key in the
    -- corner. Both were a fixed ten and unnamed; a setting that has no
    -- control is a setting nobody can change (Discord, 2026-08-16: "styling
    -- optionen fuer die answer buttons").
    nameSize        = 10,
    showKey         = true,
    -- THE SHOUT: the ring a cell wears while somebody is asking. Its colour
    -- was the addon's accent and its thickness three, both unnamed too.
    callSize        = 3,
    -- WHEN IT IS ON THE SCREEN AT ALL is ns.Visibility's rule under `show`
    -- - the same block the reminders and the bars carry - and NOT a switch
    -- of its own here. `onlyInInstance` was that switch until 4.84.0 and is
    -- folded into the rule by Config (see there); a second control for the
    -- same question is two controls that can disagree.
}

function Answers.Config()
    ns.db.answers = ns.db.answers or {}
    local cfg = ns.db.answers
    for key, value in pairs(Answers.DEFAULTS) do
        if cfg[key] == nil then cfg[key] = value end
    end
    cfg.borderColor = cfg.borderColor or ns.SurfaceColor()
    cfg.backdropColor = cfg.backdropColor or ns.SurfaceColor()
    -- The old "only in dungeons and raids" switch becomes the rule it always
    -- was: every kind of place but the open world. Once, and the key goes,
    -- so a rule somebody edits afterwards is never overwritten by it.
    if cfg.onlyInInstance ~= nil then
        if cfg.onlyInInstance and type(cfg.show) ~= "table" then
            cfg.show = Answers.RuleFromOnlyInInstance()
        end
        cfg.onlyInInstance = nil
    end
    -- Which of your spells you are willing to be asked for. Absent means
    -- "not answered yet", and Offers reads that as yes - a spell you have
    -- never seen a switch for should be on the bar, not silently missing.
    cfg.offers = cfg.offers or {}
    -- Row one is this person, row two is that one. Only read while "who" is
    -- set to the picked mode; kept either way, so switching to tanks and back
    -- does not throw the list away.
    cfg.rowNames = cfg.rowNames or {}
    return cfg
end

-- The rule "only in dungeons and raids" meant, in ns.Visibility's words:
-- shown, only when the place is any instance kind - not the open world.
-- Pure, for the self test.
function Answers.RuleFromOnlyInInstance()
    local where = {}
    for _, place in ipairs(ns.SHOW_WHERE) do where[place.key] = true end
    where.none = false
    return { mode = "rules", where = where }
end

-- The alpha the whole bar is drawn at right now: 1 while it is being placed
-- (you have to see the thing to move it), otherwise what the rule says -
-- and the rule is applied as ALPHA, never as Hide, because the cells are
-- protected buttons and combat is exactly when a rule about combat flips.
-- ns.Visibility's own header says the same about the bars.
function Answers.Factor(cfg)
    if Answers.placing then return 1 end
    if not (ns.Visibility and cfg) then return 1 end
    return ns.Visibility:Factor(cfg)
end

function Answers.Offering(spellID)
    return Answers.Config().offers[spellID] ~= false
end

-- `x and nil or y` NEVER YIELDS nil, and that is not a subtlety - it is the
-- shape of the bug. `true and nil` is nil, nil is false, so `or y` takes over
-- and the answer is y whichever way x went. Written that way, switching a
-- spell ON stored `false`, so it could be turned off exactly once and never
-- back on. Owner, 2026-08-10: "wenn ich den button auf aus schalte [...] kann
-- ich ihn nicht mehr anschalten."
--
-- An if. Every time. There is no clever form of this that works.
function Answers.SetOffering(spellID, on)
    local offers = Answers.Config().offers
    if on then
        offers[spellID] = nil     -- absent means yes, see Offering
    else
        offers[spellID] = false
    end
    Answers.Rebuild()
end

---------------------------------------------------------------------------
-- WHAT YOU CAN BE ASKED FOR
--
-- Pure, and it takes the class rather than reading it, because "what does a
-- paladin see" is a question this has to answer without being on a paladin.
--
-- Your class's externals, plus your taunt if you have one - a taunt request
-- is answered by pressing your OWN taunt, which is why it carries no target
-- spell of its own.
--
-- AND ONLY THE ONES YOU ACTUALLY HAVE. A holy priest is not a discipline
-- priest: a Pain Suppression cell on his bar is a button that does nothing
-- when it is pressed and says nothing about why, which is the exact failure
-- this whole wave is about. `known` is a predicate rather than a call so this
-- stays pure and a test can ask what a priest of either spec would see.
---------------------------------------------------------------------------
Answers.hidden = 0

function Answers.Offers(class, chosen, known)
    local out = {}
    if not class then return out end

    for _, entry in ipairs(ns.Externals.SPELLS) do
        if entry.covers then
            -- A GROUPED SLOT IS ONE QUESTION WITH SEVERAL ANSWERS, and which
            -- one is yours depends on your class. The asker's slot says
            -- "lust"; what goes on YOUR bar is the lust you have. A shaman
            -- gets both spellings offered here and `known` drops the one his
            -- faction does not have, which is the same filter that already
            -- keeps a holy priest from being offered Pain Suppression.
            for _, sub in ipairs(entry.covers) do
                if sub.class == class
                    and (not chosen or chosen[sub.spellID] ~= false) then
                    out[#out + 1] = { spellID = sub.spellID,
                        kind = Comm.EXTERNAL }
                end
            end
        elseif entry.class == class
            and (not chosen or chosen[entry.spellID] ~= false) then
            out[#out + 1] = { spellID = entry.spellID, kind = Comm.EXTERNAL }
        end
    end

    for _, entry in ipairs(ns.Taunts.SPELLS) do
        if entry.class == class and not entry.spec
            and (not chosen or chosen[entry.spellID] ~= false) then
            out[#out + 1] = { spellID = entry.spellID, kind = Comm.TAUNT }
        end
    end

    if not known then return out end

    local kept, dropped = {}, 0
    for _, offer in ipairs(out) do
        if known(offer.spellID) then
            kept[#kept + 1] = offer
        else
            dropped = dropped + 1
        end
    end

    -- A FILTER THAT THROWS EVERYTHING AWAY IS NOT AN ANSWER, IT IS A REFUSAL.
    -- The spellbook is not always readable the moment this runs - a login, a
    -- spec change, a talent load - and an empty bar for a paladin is a worse
    -- wrong answer than one extra cell. Count what it removed either way, so
    -- /zs answers can say so out loud instead of leaving a short list to be
    -- discovered.
    if #kept == 0 and #out > 0 then
        Answers.hidden = 0
        return out
    end

    Answers.hidden = dropped
    return kept
end

-- Blood's Death Grip is the one taunt with a spec on it, and Offers leaves
-- every spec-bound entry out rather than showing a frost death knight a
-- button that taunts nothing. His own taunt is Dark Command either way.

---------------------------------------------------------------------------
-- WHO MIGHT ASK
--
-- The tanks by default, because the request side of this addon is the
-- externals panel and the taunt button and both belong to a tank - a cell per
-- group member would be thirty-eight buttons for a question nobody is going
-- to ask from them.
--
-- BUT NOT ONLY THE TANKS, AND NOT ONLY BY THEMSELVES. Owner, 2026-08-10:
-- "man kann keine spieler auswaehlen". Three answers to "who", because the
-- automatic one is right until it is not:
--
--   tanks    whoever the group has marked as tanking. Nothing to set up, and
--            wrong the moment roles are not assigned - a world boss, a
--            premade that never set them, two people messing about.
--   group    everybody but you. Small groups, and the answer to "roles are
--            not set and I want this to work anyway".
--   chosen   you name them, in the order you want the rows.
--
-- Pure: it takes the settings rather than reading them, so a test can ask
-- what each mode does without a database.
---------------------------------------------------------------------------
Answers.WHO_TANKS  = "tanks"
Answers.WHO_GROUP  = "group"
Answers.WHO_CHOSEN = "chosen"

Answers.MAX_ASKERS = 3     -- the default row count
Answers.MAX_ROWS   = 6     -- the ceiling on the slider

function Answers.Rows(cfg)
    local rows = (cfg and cfg.rows) or Answers.MAX_ASKERS
    if type(rows) ~= "number" then rows = Answers.MAX_ASKERS end
    return math.max(1, math.min(Answers.MAX_ROWS, math.floor(rows)))
end

function Answers.Askers(roster, cfg)
    cfg = cfg or Answers.Config()
    local who = cfg.who or Answers.WHO_TANKS
    local rows = Answers.Rows(cfg)
    local out, taken = {}, {}

    if who == Answers.WHO_CHOSEN then
        local byName = {}
        for _, member in ipairs(roster or {}) do
            if not member.isPlayer then byName[member.name] = member end
        end
        for index = 1, rows do
            local name = cfg.rowNames and cfg.rowNames[index]
            local member = name and byName[name]
            -- Naming the same person twice is one row, not two identical
            -- ones: two rows aimed at one player answer nothing extra and
            -- both light up together.
            if member and not taken[member.name] then
                taken[member.name] = true
                out[#out + 1] = member
            end
        end
        return out
    end

    for _, member in ipairs(roster or {}) do
        if not member.isPlayer
            and (who == Answers.WHO_GROUP or member.role == "TANK") then
            out[#out + 1] = member
            if #out >= rows then break end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- WHAT IS PENDING
--
-- A list rather than one slot: two tanks asking at once is the moment this
-- feature is for, not an edge case.
---------------------------------------------------------------------------
Answers.pending = {}

-- Pure. Returns the list so a test can hold one of its own, and REPLACES the
-- entry from the same person for the same thing - pressing a request button
-- twice is one request, not two rows.
function Answers.Remember(list, packet, now)
    for _, entry in ipairs(list) do
        if entry.from == packet.fromShort and entry.kind == packet.kind
            and entry.spellID == packet.spellID then
            entry.at = now
            return list
        end
    end
    list[#list + 1] = {
        from = packet.fromShort, kind = packet.kind,
        spellID = packet.spellID, at = now,
    }
    return list
end

function Answers.Prune(list, now, linger)
    for index = #list, 1, -1 do
        if (now - list[index].at) > (linger or 8) then
            table.remove(list, index)
        end
    end
    return list
end

-- Does this cell answer that request? Pure, and it is the one rule the whole
-- feature turns on: the right cell lights up and the others do not.
function Answers.Matches(cell, entry)
    if not (cell and entry) then return false end
    if cell.who ~= entry.from then return false end
    if cell.kind ~= entry.kind then return false end
    -- A taunt request names no spell: any taunt of yours answers it.
    if entry.kind == Comm.TAUNT then return true end
    return cell.spellID == entry.spellID
end

function Answers.Waiting(list, cell, now, linger)
    for _, entry in ipairs(list) do
        if Answers.Matches(cell, entry)
            and (now - entry.at) <= (linger or 8) then
            return entry
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- THE LINE THE GAME RUNS WHEN YOU PRESS A CELL
--
-- Pure, and it is pure on purpose: this one string is the entire feature.
-- Everything else - the message, the ring, the name under the icon - is
-- decoration around a click that either casts or does not, and a click that
-- does not cast says NOTHING. No error, no red text, no combat log line. It
-- is the quietest failure this addon has, and the only defence against it is
-- being able to read the string in a test and print it in a report.
--
-- A TAUNT IS NOT CAST ON THE TANK, and this is what the first version got
-- wrong. A taunt request means "take the boss" - so the spell goes on YOUR
-- target, the enemy, and a `[@Akui-Gilneas]` in front of it aims a taunt at a
-- friendly player, which does exactly nothing and does it silently. The two
-- kinds are answered with two different lines because they are two different
-- actions that happen to share a bar.
---------------------------------------------------------------------------
function Answers.Macro(kind, spellName, asker, alsoTarget)
    if not asker or asker.preview then return nil end
    if type(spellName) ~= "string" or spellName == "" then return nil end

    -- A TAUNT GOES ON WHAT HE IS FIGHTING. Owner, 2026-08-10: "bei spott
    -- müsste das target von akui anvisiert werden, nicht akui selbst" - and
    -- that is the whole point of a swap: the boss he is holding, not the one
    -- you happen to be looking at, which in a pull with adds is a different
    -- creature and a taunt wasted.
    --
    -- THIS IS THE ONE PLACE A UNIT TOKEN IS UNAVOIDABLE. Everywhere else this
    -- file addresses people by name, because names survive the shuffle that
    -- turns party2 into party1 when somebody leaves. But "his target" has no
    -- name form: `[@Akui-Gilneastarget]` is a player nobody is called. Only a
    -- token takes the suffix, so a token it is - and the bar is rebuilt on
    -- every roster change, which is when a token could go stale.
    if kind == Comm.TAUNT then
        local unit = asker.unit
        if type(unit) ~= "string" or unit == "" then
            -- No token to reach him by. Your own target, which is what this
            -- did before and is still better than nothing.
            return "/cast " .. spellName
        end

        -- His target when it is something you can taunt, YOURS otherwise -
        -- the empty clause. Between them there is no press that does nothing.
        local line = "/cast [@" .. unit .. "target,harm][] " .. spellName
        if alsoTarget then
            return "/target " .. unit .. "target\n" .. line
        end
        return line
    end

    -- THE FULL NAME, WITH THE REALM ON IT WHEN THERE IS ONE. `/cast [@Akui]`
    -- addresses nobody when Akui is on another realm - no target, no cast, no
    -- error - which is what the first live test of this looked like across
    -- Destromath and Gilneas.
    local who = asker.fullName or asker.name
    if type(who) ~= "string" or who == "" then return nil end

    if alsoTarget then
        return "/target " .. who .. "\n/cast [@" .. who .. "] " .. spellName
    end
    return "/cast [@" .. who .. "] " .. spellName
end

-- WRITING THE CLICK ONTO THE BUTTON, in both places the game looks.
--
-- `RegisterForClicks("AnyUp")` alone is why a cell lit up, took a press, and
-- cast nothing. Blizzard's own handler compares the press it got against the
-- "cast on key down" setting and RETURNS if they disagree - so with that
-- setting on, an up-only button is skipped in silence. EllesmereUI writes the
-- same finding into its kick proxy; MRT and EllesmereUIActionBars register
-- both directions on every casting button they own. Both arrive, the gate
-- lets exactly one through, and it works whichever way the setting is set.
--
-- The numbered attributes go with the bare ones because the resolver looks up
-- `type` by button suffix first, and EllesmereUI's proxies found the bare
-- fallback unreliable on this patch. Two extra writes, no downside.
function Answers.Arm(cell, macro)
    if not cell then return false end
    if macro then
        cell:SetAttribute("type", "macro")
        cell:SetAttribute("type1", "macro")
        cell:SetAttribute("macrotext", macro)
        cell:SetAttribute("macrotext1", macro)
        return true
    end
    cell:SetAttribute("type", nil)
    cell:SetAttribute("type1", nil)
    cell:SetAttribute("macrotext", nil)
    cell:SetAttribute("macrotext1", nil)
    return false
end

---------------------------------------------------------------------------
-- KEYS
--
-- Owner, 2026-08-10, in the same breath as the cast: "keine keybinds".
--
-- A binding CANNOT run a function of ours and then cast - that is the same
-- wall the whole file is built around. What it can do is press the button for
-- you: a binding named "CLICK <frame>:LeftButton" is the game's own, handled
-- entirely inside it, and the cast is then as legitimate as a mouse click.
-- Declared in Bindings.xml, named here, and set by the player in Blizzard's
-- key bindings under ZwoelfStuff. MRT and Fitter both do exactly this.
---------------------------------------------------------------------------
Answers.KEYS = 8     -- how many cells can carry a key

function Answers.BindingName(index)
    return "CLICK ZwoelfStuffAnswer" .. index .. ":LeftButton"
end

for index = 1, Answers.KEYS do
    _G["BINDING_NAME_" .. Answers.BindingName(index)] =
        "Answer cell " .. index
end

-- Shortened in ns.ShortKey, which the externals slots use as well - two
-- shorteners for the same corner of the same kind of icon would drift.
Answers.ShortKey = ns.ShortKey

function Answers.Key(index)
    if not GetBindingKey then return nil end
    local ok, key = pcall(GetBindingKey, Answers.BindingName(index))
    if not ok then return nil end
    return ns.ShortKey(key)
end

---------------------------------------------------------------------------
-- THE QUICK MENU ON THE BAR ITSELF
--
-- Owner, 2026-08-10: "kann man das als button an die answer bar hauen, damit
-- man das dort schnell einstellen kann?" - and the reason he is right is
-- WHEN this decision happens: the group forms, somebody is on a second tank,
-- and the options window is four clicks and a different part of the screen
-- away from the bar you are looking at.
--
-- It appears when the mouse is over the bar and while the bar is being
-- placed, and is otherwise not there - a permanent cog beside a bar that is
-- deliberately dim when idle would be the brightest thing on it.
---------------------------------------------------------------------------
local panel, cells = nil, {}
local pendingRebuild = false

function Answers.Frame() return panel end

-- The built cells, for the report and for a test that has to press one. Not
-- a copy: /zs answers reads the attributes off the real buttons, because the
-- day this file and the button disagree is the day worth catching.
function Answers.Cells() return cells end

function Answers.Style()
    local cfg = Answers.Config()
    return {
        borderSize       = math.max(0, cfg.borderSize or 1),
        borderColor      = cfg.borderColor or ns.SurfaceColor(),
        borderTexture    = cfg.borderTexture or "None",
        borderGradient   = cfg.borderGradient,
        backdrop         = cfg.backdrop ~= false,
        backdropColor    = cfg.backdropColor or ns.SurfaceColor(),
        backdropAlpha    = cfg.backdropAlpha or 1,
        backdropTexture  = cfg.backdropTexture or "Blizzard",
        backdropGradient = cfg.backdropGradient,
        iconZoom         = cfg.iconZoom or 0.08,
    }
end

function Answers:ShouldShow()
    if not ns.Modules:IsOn("answers") then return false end
    if Answers.placing then return true end
    local cfg = Answers.Config()
    if not cfg.enabled then return false end
    -- WHERE and WHEN are the rule's business, applied as alpha in Repaint,
    -- not as Hide here: a bar hidden out of combat by a rule about combat
    -- could never be shown again once combat began.
    return true
end

-- SOMEBODY ASKED AND YOU HAVE NO BAR TO ANSWER WITH.
--
-- The bar is off until it is switched on, which is right - but a request that
-- then does nothing at all is a feature that silently does nothing, which is
-- the same as one that does not work. So the first time in a session that
-- somebody asks you for something you could actually give, you are told once
-- what happened and where the switch is.
local told = false

function Answers.Announce(who, spellID)
    if told then return false end
    told = true
    ns.Print(string.format("|cffffd100%s asked you for %s.|r", who or "Somebody",
        spellID and (ns.SpellName(spellID) or "a cooldown") or "a taunt"))
    ns.Print("  Switch on |cffffd100External CD answer|r (|cffffd100/zs|r, in the list on "
        .. "the left) and a button lights up for it instead of this line.")
    return true
end

local function BuildCell(index)
    if cells[index] then return cells[index] end

    -- SecureActionButtonTemplate, and the type is "macro" rather than
    -- "spell": a macro line takes [@Name], which survives the roster
    -- shuffling that moves party2 to party1 mid-key. The `unit` attribute
    -- takes a TOKEN, and a token is exactly the thing that changes under you.
    local cell = CreateFrame("Button", "ZwoelfStuffAnswer" .. index, panel,
        "SecureActionButtonTemplate")
    -- BOTH DIRECTIONS. See Answers.Arm: up-only is skipped in silence when
    -- the game is set to cast on key down, which is the default and which is
    -- why this lit up, took the click and cast nothing.
    cell:RegisterForClicks("AnyUp", "AnyDown")

    cell.bg = cell:CreateTexture(nil, "BACKGROUND")
    cell.bg:SetAllPoints(cell)

    cell.chrome = ns.CreateChrome(cell)

    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetPoint("TOPLEFT", cell, "TOPLEFT", 2, -2)
    cell.icon:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -2, 2)

    -- The shout: an accent ring and the asker's name. Both are pure looks,
    -- which is the only kind of change allowed on a protected frame while
    -- somebody is in combat - and combat is when this happens.
    cell.call = ns.CreateBorder(cell, 3, "OVERLAY")
    cell.call:SetColor(ns.UI.C.accent[1], ns.UI.C.accent[2], ns.UI.C.accent[3], 1)
    cell.call:Hide()

    cell.name = ns.UI.Label(cell, "", 10, ns.UI.C.text)
    cell.name:SetPoint("BOTTOM", cell, "BOTTOM", 0, 2)
    cell.name:SetWordWrap(false)

    -- The key, where every action bar in the game puts it. A cell with no key
    -- shows nothing rather than an empty box.
    cell.key = ns.UI.Label(cell, "", 10, ns.UI.C.textDim)
    cell.key:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -2, -2)
    cell.key:SetWordWrap(false)

    cell:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.spellName or "")
        -- A taunt goes on the boss, not on the tank who asked - so the line
        -- that says what pressing this does has to say which.
        if self.kind == Comm.TAUNT then
            GameTooltip:AddLine("On what |cffffd100"
                .. (self.who or "the other tank") .. "|r is fighting", 1, 1, 1)
        else
            GameTooltip:AddLine(self.who
                and ("On |cffffd100" .. self.who .. "|r")
                or "|cff888888Nobody to cast it on|r", 1, 1, 1)
        end
        local key = Answers.Key(self.index or 0)
        if key then
            GameTooltip:AddLine("Key: |cffffd100" .. key .. "|r", 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    cell:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    cell.index = index
    cells[index] = cell
    return cell
end

-- WHICH CELL IS WHICH, written while nobody is in combat.
--
-- Everything in here is a protected change - SetAttribute, SetPoint, a size.
-- In combat it is remembered and done again the moment the fight ends, which
-- is the pattern EllesmereUIQoL uses and names: applyPending.
function Answers.Rebuild()
    if not panel then return end

    if InCombatLockdown and InCombatLockdown() then
        pendingRebuild = true
        return
    end
    pendingRebuild = false

    local cfg = Answers.Config()
    local _, class = UnitClass("player")
    local offers = Answers.Offers(class, cfg.offers, ns.KnowsSpell)
    local askers = Answers.Askers(ns.Roster(), cfg)
    local size, gap = cfg.size or 40, cfg.gap or 4
    local style = Answers.Style()

    -- WHILE PLACING, THERE IS SOMETHING TO PLACE. Owner, 2026-08-10: "awnser
    -- button sehe ich im edit mode nicht" - and he was right: standing alone,
    -- there are no tanks to build cells FOR, so the bar had nothing in it and
    -- correctly drew nothing. Which is useless when the whole point of edit
    -- mode is to decide where it goes.
    --
    -- A stand-in row, and it carries NO macro: a cell aimed at nobody must do
    -- nothing when it is clicked rather than cast at whoever you happen to
    -- have targeted. The same rule the externals panel follows when it draws
    -- every picked slot while being placed.
    local preview = false
    if #askers == 0 and (Answers.placing or cfg.preview) then
        askers = { { name = "Tank", preview = true } }
        preview = true
    end
    if #offers == 0 and preview then
        offers = { { spellID = 355, kind = Comm.TAUNT, preview = true } }
    end

    local index = 0
    for row, asker in ipairs(askers) do
        for column, offer in ipairs(offers) do
            index = index + 1
            local cell = BuildCell(index)

            cell.who = asker.name
            cell.kind = offer.kind
            cell.spellID = offer.spellID
            cell.preview = asker.preview and true or false

            -- TWO NAMES, AND ONLY ONE OF THEM MAY REACH A MACRO. The client
            -- knows what to call a spell; when it does not, "Spell 633" is a
            -- fine thing to draw and a catastrophic thing to cast - it is not
            -- a spell, so the line runs and nothing happens, quietly. So the
            -- macro is built from the real name or not at all.
            local real = ns.SpellName(offer.spellID)
            cell.spellName = real or ("Spell " .. offer.spellID)

            -- The macro the GAME runs when you click, written here, out of
            -- combat, exactly once per roster change. A stand-in cell gets
            -- none: there is nobody called "Tank" to cast on, and a cell that
            -- fired at your current target instead would be the addon doing
            -- something you did not ask for.
            cell.macro = Answers.Macro(offer.kind, real, asker, cfg.target)
            Answers.Arm(cell, cell.macro)

            cell:SetSize(size, size)
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", panel, "TOPLEFT",
                (column - 1) * (size + gap), -(row - 1) * (size + gap))

            cell.icon:SetTexture(ns.SpellTexture(offer.spellID))
            ns.PaintSurface(cell.bg, style)
            ns.PaintBorder(cell.chrome, style, false)
            local zoom = style.iconZoom
            cell.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
            Answers.DressCell(cell, cfg)
            cell.name:SetText(asker.name)
            cell.key:SetText(Answers.Key(index) or "")

            cell:Show()
        end
    end

    for spare = index + 1, #cells do
        cells[spare].who = nil
        cells[spare]:Hide()
    end

    local wide = math.max(1, #offers)
    local tall = math.max(1, #askers)
    panel:SetSize(wide * size + (wide - 1) * gap,
        tall * size + (tall - 1) * gap)
    panel:ClearAllPoints()
    panel:SetPoint("CENTER", UIParent, "CENTER", cfg.x or 0, cfg.y or -260)
    panel:SetScale(math.max(0.3, math.min(3, cfg.scale or 1)))

    panel:SetShown(index > 0 and Answers:ShouldShow())
    Answers.Repaint()
end

-- THE WORDS AND THE RING, in the settings' sizes and colours. Pure looks,
-- so it may run in combat as well - and it does, from Repaint, so a slider
-- moved mid-fight lands on the cell at once.
function Answers.DressCell(cell, cfg)
    cfg = cfg or Answers.Config()
    local size = math.max(6, math.min(20, tonumber(cfg.nameSize) or 10))
    if cell.nameSize ~= size then
        cell.nameSize = size
        ns.StyleUIFont(cell.name, size)
        ns.StyleUIFont(cell.key, size)
    end
    local ring = cfg.callColor or ns.UI.C.accent
    cell.call:SetColor(ring[1], ring[2], ring[3], 1)
    local thick = math.max(1, math.min(8, tonumber(cfg.callSize) or 3))
    if cell.callSize ~= thick then
        cell.callSize = thick
        cell.call:SetThickness(thick)
    end
end

-- WHAT CHANGES WHILE SOMEBODY IS FIGHTING. Alpha, a ring, a word - and
-- nothing else, because nothing else is allowed and nothing else is needed.
function Answers.Repaint()
    if not panel then return end

    local cfg = Answers.Config()
    local now = GetTime and GetTime() or 0
    Answers.Prune(Answers.pending, now, cfg.linger)

    -- THE RULE, as alpha on the whole bar. See Answers.Factor.
    panel:SetAlpha(Answers.Factor(cfg))

    local idle = math.max(0, math.min(1, cfg.idleAlpha or 0.35))
    local lit = math.max(0, math.min(1, cfg.alpha or 1))

    -- THE QUICK MENU IS THERE WHEN YOUR HAND IS. The hit area is stretched 26
    -- units upward so that the button, which stands above the bar, keeps it
    -- open while you reach for it - otherwise it disappears out from under
    -- the cursor on the way.
    if Answers.menu then
        local wanted = cfg.quickMenu ~= false
            and (Answers.placing
                or (panel.IsMouseOver and panel:IsMouseOver(26, 0, 0, 0)))
        Answers.menu:SetShown(wanted and true or false)
    end

    for _, cell in ipairs(cells) do
        if cell.who then
            -- A key can be bound mid-fight, and a piece of text is one of the
            -- few things a protected button will still accept then.
            cell.key:SetText(Answers.Key(cell.index or 0) or "")
            -- A stand-in cell is drawn at full strength with its name on it:
            -- while you are placing the bar, "which of these is it" is the
            -- only question, and a dimmed square answers it badly.
            Answers.DressCell(cell, cfg)
            cell.key:SetShown(cfg.showKey ~= false)
            if cell.preview then
                cell:SetAlpha(lit)
                cell.call:Hide()
                cell.name:Show()
            else
                local waiting = Answers.Waiting(Answers.pending, cell, now,
                    cfg.linger)
                cell:SetAlpha(waiting and lit or idle)
                cell.call:SetShown(waiting ~= nil)
                cell.name:SetShown(waiting ~= nil)
            end
        end
    end
end

function Answers:SavePosition()
    -- NOTHING, on purpose. Working the position out again from GetCenter
    -- minus UIParent:GetCenter() mixes two coordinate spaces the moment this
    -- carries a scale of its own, and the frame jumps every time edit mode
    -- closes. The mover writes cfg.x and cfg.y exactly; nothing else moves
    -- this. See the long note in Externals.lua.
end

function Answers:SetPlacing(on)
    Answers.placing = on and true or false
    if not Answers.placing then self:SavePosition() end
    Answers.Rebuild()
end

function Answers.Refresh() Answers.Rebuild() end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
-- WHAT THE LITTLE BUTTON OFFERS. Built fresh every time it opens, because
-- the group is the whole subject and it changes while you are standing there.
function Answers.MenuItems()
    local cfg = Answers.Config()
    local items = {
        { heading = true, text = "Who you answer" },
        { text = "The tanks", value = Answers.WHO_TANKS,
          onClick = function() Answers.SetWho(Answers.WHO_TANKS) end },
        { text = "Everybody in the group", value = Answers.WHO_GROUP,
          onClick = function() Answers.SetWho(Answers.WHO_GROUP) end },
    }

    -- THE PEOPLE, WITH THEIR OWN STATE ON THEM. The menu marks one chosen
    -- row, and "chosen" here is a list - so each name carries its own tick in
    -- its text. Clicking one means "this person", which also means the picked
    -- mode: choosing somebody and then not being in the mode that reads it is
    -- a click that does nothing.
    local names = {}
    for _, member in ipairs(ns.Roster()) do
        if not member.isPlayer then names[#names + 1] = member.name end
    end

    if #names > 0 then
        items[#items + 1] = { heading = true, text = "Or pick them" }
        for _, name in ipairs(names) do
            local picked = Answers.Picked(name)
            items[#items + 1] = {
                text = (picked and "|cff40ff40+|r " or "|cff5a5f6a-|r ") .. name,
                onClick = function() Answers.TogglePicked(name) end,
            }
        end
    end

    return items, cfg.who or Answers.WHO_TANKS
end

-- A CHANGE HERE MAY HAVE TO WAIT, and saying so is the difference between a
-- setting and a mystery: which cell casts what is written out of combat, and
-- the game will not have it rewritten during a fight.
local function Applied()
    Answers.Rebuild()
    if InCombatLockdown and InCombatLockdown() then
        ns.Print("|cffffd100The bar is rebuilt when you leave combat.|r The "
            .. "game does not allow a cell to be re-aimed during a fight.")
    end
end

function Answers.SetWho(who)
    Answers.Config().who = who
    Applied()
end

function Answers.Picked(name)
    for _, chosen in pairs(Answers.Config().rowNames) do
        if chosen == name then return true end
    end
    return false
end

-- Off the list if it is on it; otherwise into the first free row, and only
-- while there is one - silently dropping the fourth name would read as a
-- click that did not register.
function Answers.TogglePicked(name)
    local cfg = Answers.Config()
    local rows = Answers.Rows(cfg)

    for index, chosen in pairs(cfg.rowNames) do
        if chosen == name then
            cfg.rowNames[index] = nil
            cfg.who = Answers.WHO_CHOSEN
            Applied()
            return false
        end
    end

    for index = 1, rows do
        if not cfg.rowNames[index] then
            cfg.rowNames[index] = name
            cfg.who = Answers.WHO_CHOSEN
            Applied()
            return true
        end
    end

    ns.Print(string.format("|cffffd100%d rows, all taken.|r Raise the row "
        .. "count under External CD answer, or take somebody off first.", rows))
    return false
end

function Answers:Create()
    if panel then return panel end

    panel = CreateFrame("Frame", "ZwoelfStuffAnswers", UIParent)
    panel:SetSize(40, 40)
    panel:SetClampedToScreen(true)
    panel:Hide()

    -- The button, above the top left corner - outside the lattice, so it
    -- never sits on a cell however many rows there are. Two people rather
    -- than a cog: the question it answers is "who", and the cog on every
    -- mover in this addon already means "this panel's settings".
    local C = ns.UI.C
    local menu = CreateFrame("Button", nil, panel)
    menu:SetSize(20, 20)
    menu:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 0, 3)

    menu.bg = menu:CreateTexture(nil, "BACKGROUND")
    menu.bg:SetAllPoints(menu)
    menu.bg:SetColorTexture(0, 0, 0, 0.7)

    local glyph = ns.UI.Glyph(menu, "cond-group", 12, C.textDim)
    glyph:SetPoint("CENTER", menu, "CENTER", 0, 0)

    menu:SetScript("OnClick", function(button)
        local items, current = Answers.MenuItems()
        ns.UI.ShowMenu(button, {
            width = 200,
            anchor = { "TOPLEFT", "BOTTOMLEFT", 0, -2 },
            items = items,
            current = current,
            actions = {
                { text = "Answer options", onClick = function()
                    ns.Options:Open("answers")
                end },
            },
        })
    end)
    menu:SetScript("OnEnter", function(button)
        glyph:SetColor(C.accent[1], C.accent[2], C.accent[3])
        if not GameTooltip then return end
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Who you answer")
        GameTooltip:AddLine("One row of cells per person.", 1, 1, 1)
        GameTooltip:Show()
    end)
    menu:SetScript("OnLeave", function()
        glyph:SetColor(C.textDim[1], C.textDim[2], C.textDim[3])
        if GameTooltip then GameTooltip:Hide() end
    end)
    menu:Hide()

    Answers.menu = menu
    Answers.panel = panel
    self:Rebuild()
    return panel
end

function Answers:Start()
    if self.started then return end
    self.started = true

    Comm.Listen(function(packet)
        if packet.what ~= Comm.REQUEST then return end
        if not ns.Modules:IsOn("answers") then return end

        -- Only what you could actually answer. A druid being told that
        -- somebody wants Pain Suppression is noise: there is no button of
        -- his that answers it. Neither has a holy priest - which is the same
        -- sentence one step further in, and why the spellbook is asked here
        -- as well as on the bar.
        local _, class = UnitClass("player")

        -- MATCHED ON THE SLOT, ANSWERED WITH MY OWN SPELL.
        --
        -- The asker's slot can stand for several spells - "lust" is one
        -- question with five spellings - so the test is not "is that my
        -- spell" but "does one of MY spells answer that question". Asking it
        -- this way round is what makes it right for the shaman: which lust he
        -- owns is his faction's business, and this list has already been
        -- through the spellbook, so whichever one is really his is the one
        -- that matches. Deciding it the other way - working out the spell
        -- from the class - would light up nothing for half of them.
        --
        -- `wanted` is that spell, and every line below uses it: the cell that
        -- brightens, the macro it runs, the ACK that goes back.
        local wanted, mine = packet.spellID, false
        for _, offer in ipairs(Answers.Offers(class, Answers.Config().offers,
            ns.KnowsSpell)) do
            if offer.kind == packet.kind
                and (packet.kind == Comm.TAUNT
                    or ns.Externals.SameSlot(offer.spellID, packet.spellID)) then
                mine = true
                if packet.kind ~= Comm.TAUNT then wanted = offer.spellID end
            end
        end
        if not mine then return end

        -- A COPY, NOT A WRITE. The externals panel listens to these same
        -- packets and keys its own state by what it was actually sent;
        -- rewriting the object under it would move somebody else's furniture.
        -- Copied field by field rather than rebuilt from a list of names, so
        -- a field added to a packet later cannot be dropped here silently.
        local ask = packet
        if wanted ~= packet.spellID then
            ask = {}
            for key, value in pairs(packet) do ask[key] = value end
            ask.spellID = wanted
        end

        -- THE ALERT, whether or not the bar is up. It is the same moment
        -- said larger (Core/AnswerAlerts.lua), and somebody who keeps the
        -- bar off and the alert on has said "tell me, I will cast it
        -- myself" - so the line and the chime go up for them too, and only
        -- the chat hint stays as the pointer to the bar.
        local cfg = Answers.Config()
        local alerted = ns.AnswerAlerts and ns.AnswerAlerts.Fire(ask) or false

        if not cfg.enabled then
            Answers.Announce(ask.fromShort, ask.spellID)
            if not alerted then return end
        else
            Answers.Remember(Answers.pending, ask,
                GetTime and GetTime() or 0)
            Answers.Repaint()
        end

        -- THE CHIME MOVED, IT DID NOT CHANGE. 8959 is now named in
        -- Core/Sounds.lua as this event's built-in, so a profile that has
        -- never opened the sound page sounds exactly as it did before - and
        -- one that picks a sound of its own gets that instead, per SPELL.
        -- Picking "None" silences it without switching the answers off, which
        -- the toggle below could never do on its own.
        if cfg.sound ~= false and ns.Sounds then
            ns.Sounds.Play("asked", ask.spellID)
        end
    end)

    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    watcher:RegisterEvent("UPDATE_BINDINGS")
    -- A spec change changes what you have, and what you have is what the bar
    -- offers - a holy priest who goes discipline gains a cell.
    watcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    watcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    watcher:SetScript("OnEvent", function(_, event, _, _, spellID)
        if not ns.db then return end

        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            Answers.OnCast(spellID)
            return
        end

        -- Only the letters in the corner change, and they are allowed to
        -- change in combat - which is exactly when somebody binds a key they
        -- suddenly need.
        if event == "UPDATE_BINDINGS" then
            Answers.Repaint()
            return
        end

        -- PLAYER_REGEN_ENABLED is the moment a rebuild that was refused in
        -- combat is allowed. The roster events are why it would have been
        -- asked for at all.
        if event ~= "PLAYER_REGEN_ENABLED" or pendingRebuild then
            Answers.Rebuild()
        end

        -- AND SAY WHAT YOU HAVE. A tank who joins mid-key missed every
        -- message sent before he arrived, so the group re-introduces itself
        -- whenever it changes. Two seconds late on purpose: a roster event
        -- comes in a burst of three or four while people load in.
        if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
            if C_Timer and C_Timer.After then
                C_Timer.After(2, Answers.ReportAll)
            end
        end
    end)

    -- Ten a second is what everything else in this addon repaints at, and
    -- this one only changes an alpha and a ring.
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(0.2, function()
            if panel and panel:IsShown() then Answers.Repaint() end
        end)
    end
end

---------------------------------------------------------------------------
-- TELLING THE GROUP WHAT YOU HAVE
--
-- The owner's idea, and it is the one that gets past the wall this addon has
-- been standing at since 4.58.0: a foreign cooldown cannot be READ, but the
-- person who owns it can SAY it. Every client knows its own perfectly.
--
-- Sent as an addon message, not a chat line - same information, invisible,
-- and it does not fill the party window with "lay on hands rdy" every ten
-- minutes.
---------------------------------------------------------------------------
-- What the client says about one of your own spells. Answers the seconds
-- left, 0 when it is ready, and nil when the client will not say - which is
-- a different answer and must not be reported as "ready".
function Answers.Remaining(spellID)
    local info = C_Spell and C_Spell.GetSpellCooldown
        and C_Spell.GetSpellCooldown(spellID)
    if type(info) ~= "table" then return nil end

    local start, duration = info.startTime, info.duration
    if not (ns.CanCompute(start) and ns.CanCompute(duration)) then return nil end
    if type(start) ~= "number" or type(duration) ~= "number" then return nil end

    -- A duration under two seconds is the global cooldown, not this spell's.
    -- Reporting THAT as "used" would blink every icon in the group every
    -- time the healer pressed anything at all.
    if start == 0 or duration <= 1.5 then return 0 end

    local left = (start + duration) - (GetTime and GetTime() or 0)
    return left > 0 and left or 0
end

-- Announce one spell's state. Sent on a cast, when it comes back, and once
-- when the group changes - the last one is what a tank joining mid-key needs,
-- because he missed every message that came before he was there.
function Answers.Report(spellID, kind)
    local left = Answers.Remaining(spellID)
    if left == nil then return false end

    if left <= 0 then
        return Comm.Send(Comm.READY, kind or Comm.EXTERNAL, spellID, 0)
    end
    return Comm.Send(Comm.USED, kind or Comm.EXTERNAL, spellID, left)
end

-- ONLY WHAT YOU HAVE, and here it is not tidiness. A spell that is not in
-- your book has no cooldown running, so the client answers "ready" for it -
-- and this would tell the whole group that a holy priest's Pain Suppression
-- is up. A number that is confidently wrong is worse than no number, which is
-- the rule the whole reporting side was built on.
function Answers.ReportAll()
    if not ns.Modules:IsOn("answers") then return end
    local _, class = UnitClass("player")
    for _, offer in ipairs(Answers.Offers(class, Answers.Config().offers,
        ns.KnowsSpell)) do
        Answers.Report(offer.spellID, offer.kind)
    end
end

-- YOU PRESSED IT. The honest signal that a request was answered is the spell
-- actually going out - not the click, which happens whether the cast lands or
-- not. Whoever asked gets told, and the request stops shouting here.
function Answers.OnCast(spellID)
    local now = GetTime and GetTime() or 0
    local answered = nil

    -- The line comes down first, and on its own: it may be up with the bar
    -- switched off, in which case `pending` below has nothing to say.
    if ns.AnswerAlerts then ns.AnswerAlerts.Settle(spellID) end

    for index = #Answers.pending, 1, -1 do
        local entry = Answers.pending[index]
        local isTaunt = entry.kind == Comm.TAUNT
            and ns.Taunts.IsTaunt(spellID)
        if isTaunt or entry.spellID == spellID then
            answered = entry
            table.remove(Answers.pending, index)
        end
    end

    -- THE COOLDOWN GOES OUT WHETHER ANYBODY ASKED OR NOT. A tank wants to
    -- know his healer just spent Lay on Hands even if the press was the
    -- healer's own idea - which it usually is.
    --
    -- One frame later: the cooldown does not exist yet in the moment the cast
    -- succeeds, so asking now would answer "ready" and undo itself.
    local _, class = UnitClass("player")
    for _, offer in ipairs(Answers.Offers(class, Answers.Config().offers,
        ns.KnowsSpell)) do
        if offer.spellID == spellID then
            if C_Timer and C_Timer.After then
                C_Timer.After(0.1, function()
                    Answers.Report(spellID, offer.kind)
                    -- And once more when it should be back, so "ready" is a
                    -- fact rather than the tank's arithmetic. Verified before
                    -- it is sent: a reset or a second charge would make the
                    -- guess wrong in the direction that matters.
                    local left = Answers.Remaining(spellID)
                    if left and left > 0 then
                        C_Timer.After(left + 0.2, function()
                            Answers.Report(spellID, offer.kind)
                        end)
                    end
                end)
            end
        end
    end

    if not answered then return end
    Comm.Send(Comm.ACK, answered.kind, answered.spellID)
    Answers.Repaint()
    return answered, now
end

---------------------------------------------------------------------------
-- WHAT IS ACTUALLY ON THE BAR, PRINTED
--
-- This is a diagnostic, not a summary, and it exists because a cell that
-- casts nothing looks exactly like a cell that casts: it lights up, it takes
-- the press, and then there is silence. Three separate reasons for that
-- silence have now been found by reading code - a name without a realm, a
-- taunt aimed at a friend, a click the game skipped - and each one would have
-- been a single line here.
--
-- SO IT REPORTS THE SWITCHES FIRST, then the macro text itself, verbatim,
-- because the macro IS the feature and every other line is about it.
---------------------------------------------------------------------------
function Answers:Dump()
    local cfg = Answers.Config()
    ns.Print("|cffffd100answers|r - what you could be asked for, and by whom.")

    -- The switches, before anything that depends on them.
    if not ns.Modules:IsOn("answers") then
        ns.Print("  |cffff4040The External CD answer module is switched off.|r")
    end
    if not cfg.enabled then
        ns.Print("  |cffff4040The bar is switched off|r - a request is printed "
            .. "instead of lighting anything up.")
    end

    -- The game's own setting, because it is the one that silently ate every
    -- click before 4.66.0 and the one nobody would think to look at.
    local keyDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
    ns.Print(string.format("  cast on key down: |cffffd100%s|r  (both "
        .. "directions are registered either way)", keyDown and "on" or "off"))

    local _, class = UnitClass("player")
    local offers = Answers.Offers(class, cfg.offers, ns.KnowsSpell)
    local names = {}
    for _, offer in ipairs(offers) do
        names[#names + 1] = ns.SpellName(offer.spellID)
            or tostring(offer.spellID)
    end
    ns.Print("  you offer: " .. (#names > 0 and table.concat(names, ", ")
        or "|cff888888nothing your class has|r"))
    if (Answers.hidden or 0) > 0 then
        ns.Print(string.format("    |cff888888%d more your class has but you "
            .. "do not - wrong spec, or not talented.|r", Answers.hidden))
    end

    local askers = Answers.Askers(ns.Roster(), cfg)
    local who = {}
    for _, member in ipairs(askers) do
        who[#who + 1] = member.name
            .. (member.fullName ~= member.name and " |cff888888("
                .. member.fullName .. ")|r" or "")
    end
    ns.Print(string.format("  rows go to |cffffd100%s|r, up to %d: %s",
        cfg.who or Answers.WHO_TANKS, Answers.Rows(cfg),
        #who > 0 and table.concat(who, ", ")
            or "|cffff4040nobody - so there is no bar|r"))

    ns.Print(string.format("  %d cell%s built, %d waiting.",
        #cells, #cells == 1 and "" or "s", #Answers.pending))

    -- EVERY CELL, AND WHAT IT WOULD DO. Read off the button itself rather
    -- than from what this file believes it wrote: the point is to catch the
    -- day those two disagree.
    for index, cell in ipairs(cells) do
        if cell.who then
            local macro = cell:GetAttribute("macrotext")
            local kind = cell:GetAttribute("type")
            local key = Answers.Key(index)
            ns.Print(string.format("    |cffffd100#%d|r %s / %s%s%s",
                index, cell.who, cell.spellName or "?",
                cell:IsShown() and "" or " |cff888888(hidden)|r",
                key and ("  |cff40ff40[" .. key .. "]|r") or ""))
            if kind == "macro" and macro then
                ns.Print("        " .. macro:gsub("\n", " | "))
            elseif cell.preview then
                ns.Print("        |cff888888stand-in while you place the bar "
                    .. "- casts nothing, on purpose|r")
            else
                ns.Print("        |cffff4040no macro: this cell casts "
                    .. "nothing|r")
            end
        end
    end

    for _, entry in ipairs(Answers.pending) do
        ns.Print(string.format("    |cff40ff40%s|r asked for %s",
            entry.from, entry.spellID
                and (ns.SpellName(entry.spellID) or entry.spellID)
                or "a taunt"))
    end

    if #cells == 0 then
        ns.Print("  |cff888888Nothing is built yet. The bar builds itself out "
            .. "of combat, from who is in the group.|r")
    end
end
