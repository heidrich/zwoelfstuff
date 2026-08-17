---------------------------------------------------------------------------
-- Answer alerts - the line on the screen when somebody asks you for one
--
-- Owner, 2026-08-17: "bei cd answer muessten wir auch ein alert system
-- einbauen. eigentlich ist das der reminder, aber den nennen wir alert ...
-- speziell fuer das system. das kannste auch nur mit genau den spells die du
-- zur verfuegung hast konfigurieren." And: "nach x sekunden, oder 3 mal
-- aufleuchten oder oder, gib den leuten optionen." And: "der alert sollte
-- auch beim edit verschiebbar sein."
--
-- WHAT IT IS. The answer bar lights a cell when somebody asks - a ring and a
-- name on a forty-pixel button that lives wherever you parked it. This is
-- the same moment written large, near the middle of the screen, in the
-- reminders' own type: "Akui asks for Pain Suppression". A healer watching
-- the raid frames does not see a ring on a bar in the corner; the reminders
-- exist for exactly that reason and this is their shape, borrowed for the
-- one event the bar knows about.
--
-- WHAT IT IS NOT. Not a reminder. A reminder watches a STATE and stays as
-- long as the state is wrong; this announces an EVENT and has to decide for
-- itself when to stop, which is the one setting the reminders never needed
-- and the one the owner asked for options on. And it is not a second module:
-- it lives inside the answers, obeys the answers' switch, and only ever names
-- a spell the answer bar could offer. A separate "Alerts" module would have
-- been a second thing to switch on before the first one did anything.
--
-- WHAT IT BORROWS, ON PURPOSE. Reminders.Extent sizes the frame from the
-- text and Reminders.FlashAlpha shapes the pulse - both pure, both already
-- tested, and a second copy of either is a second place to be wrong. Its
-- settings copy the reminders' vocabulary (font, size, edge, colour, icon,
-- flash) so the two pages read as one addon.
--
-- ONE LINE, NOT A LIST. The newest request replaces the one before it. Two
-- people asking a healer for two different externals inside one second is
-- rare, and when it happens the bar still lights both cells; a stack that
-- grows downwards would need its own layout, its own edit-mode box and its
-- own idea of which line ends first, for a case nobody has reported.
--
-- OFF UNTIL ASKED FOR, like the bar itself: an update that starts putting
-- large red words in the middle of the screen is an update people write
-- about. The switch is on the Alerts tab of the answer page.
---------------------------------------------------------------------------
local _, ns = ...

local Alerts = {}
ns.AnswerAlerts = Alerts

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
-- WHEN IT GOES AWAY. "asked" is the reminders' idea carried over: the line
-- stands while the request stands (the bar's own "how long it shouts") and
-- goes when you cast the answer. The other two are the owner's options - a
-- fixed number of seconds, or a fixed number of pulses of the flash. Casting
-- the answer ends it EARLY under every one of them: a message about a thing
-- you have already done is noise, whatever the timer says.
Alerts.ENDINGS = {
    { value = "asked",   text = "When answered or run out",
      hint = "As long as the request itself lasts." },
    { value = "seconds", text = "After a number of seconds" },
    { value = "flashes", text = "After a number of flashes" },
}

Alerts.DEFAULTS = {
    enabled   = false,
    -- Which of your offers get a line. ABSENT MEANS YES, the same reading
    -- Answers.Offers gives cfg.offers: a spell you have never seen a switch
    -- for should alert, not silently not. Only ever holds `false`.
    spells    = {},

    font      = "",
    size      = 34,
    outline   = "THICKOUTLINE",
    color     = { 1.00, 0.36, 0.30 },
    iconSide  = "left",
    iconSize  = 34,

    flash     = true,
    flashRate = 1.1,
    flashMin  = 0.25,

    ending    = "asked",
    seconds   = 4,
    flashes   = 3,

    -- Where. CENTER of the screen plus an offset, exactly as the answer bar
    -- and every other placed panel: the edit-mode mover writes x and y and
    -- nothing else moves this. Above the bar's own default (-260) and the
    -- reminders' (180), so the three do not open on top of one another.
    x         = 0,
    y         = 240,
    scale     = 1.0,
}

-- The alert's table lives INSIDE the answers' settings (cfg.alert), because
-- it is part of that feature: one module switch, one page, one profile key.
-- Tables in DEFAULTS are copied, never shared - a colour picker moving two
-- profiles at once is the shape the house-look test guards against.
function Alerts.Config()
    local host = ns.Answers.Config()
    host.alert = host.alert or {}
    local cfg = host.alert
    for key, value in pairs(Alerts.DEFAULTS) do
        if cfg[key] == nil then
            if type(value) == "table" then
                local copy = {}
                for k, v in pairs(value) do copy[k] = v end
                cfg[key] = copy
            else
                cfg[key] = value
            end
        end
    end
    return cfg
end

---------------------------------------------------------------------------
-- The pure rules - checked on the desk, no screen needed
---------------------------------------------------------------------------

-- Does this spell get a line? The master switch and the per-spell one, and
-- the per-spell one only ever says no.
function Alerts.Wants(cfg, spellID)
    if not (cfg and cfg.enabled) then return false end
    if spellID and cfg.spells and cfg.spells[spellID] == false then
        return false
    end
    return true
end

-- The words. A taunt request names no spell (see Answers.Matches), so it
-- says so in words rather than printing "asks for nil".
function Alerts.Text(who, spellID, isTaunt)
    who = (who and who ~= "") and who or "Somebody"
    if isTaunt then return who .. " asks for a taunt" end
    local name = spellID and ns.SpellName(spellID) or nil
    return who .. " asks for " .. (name or "a cooldown")
end

-- When a line that went up at `at` has to come down, by the settings. The
-- request's own lifetime is `linger` (the bar's "how long it shouts").
--
-- "flashes" is counted in the flash's own time: N full cycles at flashRate
-- per second. With the flash switched off the count still means something -
-- N cycles' worth of seconds - rather than a line that never ends.
function Alerts.Until(cfg, at, linger)
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

-- Does the line answer this cast? A taunt request is answered by any taunt;
-- everything else by its own spell.
function Alerts.Answers(entry, spellID, isTaunt)
    if not entry then return false end
    if entry.taunt then return isTaunt and true or false end
    return entry.spellID == spellID
end

---------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------
local frame
local ICON_GAP = 8

-- One OnUpdate, ON THE FRAME ITSELF, so it runs only while the frame is
-- shown - a hidden frame's OnUpdate does not fire. Nothing ticks while
-- nobody is asking, which is the resting state and the one that matters.
local function OnUpdate(self, elapsed)
    self.phase = (self.phase or 0) + elapsed
    if Alerts.placing then
        self:SetAlpha(1)
        return
    end
    local now = GetTime and GetTime() or self.phase
    local entry = Alerts.current
    if not entry or now >= (entry.deadline or 0) then
        Alerts.Clear()
        return
    end
    local cfg = Alerts.Config()
    if cfg.flash then
        self:SetAlpha(ns.Reminders.FlashAlpha(self.phase - (self.flashFrom or 0),
            cfg.flashRate, cfg.flashMin))
    else
        self:SetAlpha(1)
    end
end

local function BuildFrame()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(false)
    f:Hide()

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.text = f:CreateFontString(nil, "OVERLAY")
    -- Fonted here, because SetText on a FontString with no font raises.
    ns.Media.ApplyFont(f.text, nil, 32, "THICKOUTLINE")
    f.text:SetJustifyH("CENTER")

    f:SetScript("OnUpdate", OnUpdate)
    return f
end

function Alerts.Frame() return frame end

-- The look, in the settings' words. Sized FROM the text, as the reminders
-- are, so the edit-mode box matches the words under it.
function Alerts.Style()
    if not frame then return end
    local cfg = Alerts.Config()
    local entry = Alerts.current

    ns.Media.ApplyFont(frame.text, cfg.font ~= "" and cfg.font or nil,
        cfg.size, cfg.outline, cfg.color)
    frame.text:SetText(entry and entry.text or "")

    local side = cfg.iconSide or "left"
    local hasIcon = (side == "left" or side == "right")
        and entry and entry.spellID
    frame.icon:ClearAllPoints()
    frame.text:ClearAllPoints()

    if hasIcon then
        frame.icon:SetTexture(ns.SpellTexture(entry.spellID))
        frame.icon:SetSize(cfg.iconSize, cfg.iconSize)
        frame.icon:Show()
        if side == "left" then
            frame.icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
            frame.text:SetPoint("LEFT", frame.icon, "RIGHT", ICON_GAP, 0)
        else
            frame.icon:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
            frame.text:SetPoint("RIGHT", frame.icon, "LEFT", -ICON_GAP, 0)
        end
    else
        frame.icon:Hide()
        frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    end

    local wide, tall = ns.Reminders.Extent(
        frame.text:GetStringWidth() or 0,
        frame.text:GetStringHeight() or 0,
        hasIcon and side or "none", cfg.iconSize or 0, ICON_GAP)
    frame:SetSize(wide, tall)

    frame:SetScale(math.max(0.3, math.min(3, cfg.scale or 1)))
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", cfg.x or 0, cfg.y or 0)
end

-- Put a line up. `entry` carries who, spellID, taunt, text, at, deadline.
local function Raise(entry)
    if not frame then frame = BuildFrame() end
    Alerts.current = entry
    Alerts.Style()
    -- Every line starts its flash at full brightness rather than wherever
    -- the last one left off - the reminders do the same, for the same
    -- reason: the first thing you see of it should be all of it.
    frame.flashFrom = frame.phase or 0
    frame:SetAlpha(1)
    frame:Show()
end

function Alerts.Clear()
    Alerts.current = nil
    if frame then frame:Hide() end
end

---------------------------------------------------------------------------
-- The two moments the answers tell it about
---------------------------------------------------------------------------

-- Somebody asked. Returns whether a line went up, so the caller knows the
-- request was SEEN by something even with the bar switched off.
function Alerts.Fire(ask)
    if not ask then return false end
    local cfg = Alerts.Config()
    local isTaunt = ns.Comm and ask.kind == ns.Comm.TAUNT
    if not Alerts.Wants(cfg, ask.spellID) then return false end
    -- Not over the placing sample: edit mode is for putting it somewhere,
    -- and a real request landing mid-drag would move the box under the hand.
    if Alerts.placing then return true end

    local now = GetTime and GetTime() or 0
    Raise({
        who = ask.fromShort, spellID = ask.spellID, taunt = isTaunt,
        text = Alerts.Text(ask.fromShort, ask.spellID, isTaunt),
        at = now,
        deadline = Alerts.Until(cfg, now, ns.Answers.Config().linger),
    })
    return true
end

-- You cast something. If it answers the line, the line goes - under every
-- ending, see ENDINGS.
function Alerts.Settle(spellID)
    local entry = Alerts.current
    if not entry or Alerts.placing then return false end
    local isTaunt = ns.Taunts and ns.Taunts.IsTaunt
        and ns.Taunts.IsTaunt(spellID) or false
    if Alerts.Answers(entry, spellID, isTaunt) then
        Alerts.Clear()
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- Placing and previewing
---------------------------------------------------------------------------

-- The first spell you actually offer, for a sample line that reads like a
-- real one; a fixed name when the class offers nothing.
local function SampleSpell()
    local _, class = UnitClass("player")
    for _, offer in ipairs(ns.Answers.Offers(class, ns.Answers.Config().offers,
        ns.KnowsSpell)) do
        if offer.kind ~= (ns.Comm and ns.Comm.TAUNT) and offer.spellID then
            return offer.spellID
        end
    end
    return nil
end

-- Edit mode. A line is on screen only while somebody is asking, and
-- waiting to be asked in order to place the message about being asked is
-- not a workflow - the reminders say the same. So placing shows a sample.
function Alerts:SetPlacing(on)
    Alerts.placing = on and true or false
    if Alerts.placing then
        local spellID = SampleSpell()
        Raise({
            who = "Somebody", spellID = spellID, taunt = spellID == nil,
            text = Alerts.Text("Somebody", spellID, spellID == nil),
            at = 0, deadline = math.huge,
        })
    else
        Alerts.Clear()
    end
end

-- The button on the options page: a real line, under the real rules, ended
-- by the real timer. What you see is what a request will look like.
function Alerts.Preview()
    local cfg = Alerts.Config()
    local spellID = SampleSpell()
    local now = GetTime and GetTime() or 0
    Raise({
        who = "Somebody", spellID = spellID, taunt = spellID == nil,
        text = Alerts.Text("Somebody", spellID, spellID == nil),
        at = now,
        deadline = Alerts.Until(cfg, now, ns.Answers.Config().linger),
    })
end

-- Sliders call this: restyle what is up, leave what is not.
function Alerts.Refresh()
    if frame and frame:IsShown() then Alerts.Style() end
end

function Alerts:Dump()
    local cfg = Alerts.Config()
    ns.Print(string.format("Answer alerts: %s, ending %s (%ds / %d flashes)",
        cfg.enabled and "|cff40ff40on|r" or "|cffff4040off|r",
        tostring(cfg.ending), cfg.seconds or 0, cfg.flashes or 0))
    if Alerts.current then
        ns.Print("  up now: " .. tostring(Alerts.current.text))
    end
end
