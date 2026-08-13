---------------------------------------------------------------------------
-- Effects - the things a cell does that are not just sitting there.
--
-- A flash when a cooldown comes back. A glow while it is ready. A pulse when
-- you have been standing on a ready defensive for six seconds in combat. This
-- is the half of a cooldown display that people actually read out of the
-- corner of their eye, and it is why "just show the icons" is never enough.
--
-- WHAT DRIVES IT, AND WHY NOT A TIMER OFF THE SPELL.
--
-- Blizzard's Cooldown Manager already knows whether a spell is on a real
-- cooldown, and it says so on the info table every item frame carries:
-- isActive with isOnGCD to tell a real cooldown from the global one. Those
-- two field names are read off working code on this machine
-- (EllesmereUICooldownManager, EllesmereUICdmHooks.lua and CdmFakeActive.lua),
-- never guessed - and they are the ONLY honest source, because the alternative
-- is polling a spell cooldown that reports the GCD for everything and flashes
-- every 1.5 seconds.
--
-- SECRET VALUES.
--
-- Since 12.0 those fields can arrive as secret values, and a boolean test on
-- one raises. Everything below goes through ns.CanCompute first, and an
-- unreadable state means "do nothing" rather than "guess" - a display that
-- flashes at random is worse than one that does not flash at all.
--
-- REMAINING TIME.
--
-- Deliberately NOT read for adopted frames. There is no field on the info
-- table for it, and the Cooldown widget's own timing is a duration object on
-- this patch. The low-time warning therefore applies to the auras this addon
-- clocks itself, where the number is ours, and the option says so.
---------------------------------------------------------------------------
local _, ns = ...

local Effects = {}
ns.Effects = Effects

local GetTime, sin, pi = GetTime, math.sin, math.pi

ns.EFFECT_DEFAULTS = {
    -- The flash when a cooldown finishes. The single most asked-for thing in
    -- any cooldown addon, and the reason people keep a second one installed.
    readyFlash   = false,
    readyPulses  = 2,
    readyColor   = { 1.00, 0.85, 0.40 },

    -- A steady edge while the spell is up. Combat-only by default: a screen
    -- of glowing icons while you stand in the city is noise.
    readyGlow    = false,
    readyGlowCombatOnly = true,

    -- WHAT THE GLOW LOOKS LIKE.
    --
    --   "edge"   two rings at different alphas - a soft rectangle
    --   "pixel"  a handful of squares running round the outline
    --
    -- The edge is the quiet one and stays the default. The running squares
    -- are the shape people know from every other addon that has ever marked
    -- "press this", and motion is caught by the corner of your eye in a way a
    -- steady colour is not - which is the entire job of a proc marker.
    glowStyle    = "edge",
    glowDots     = 8,

    -- READY AND AFFORDABLE ARE TWO DIFFERENT THINGS, and only one of them is
    -- what "can I press this" means. A cooldown that has finished while you
    -- are short of the rage, the runic power or the runes is an icon telling
    -- you to press something that will not go off. Off by default, because
    -- the plain reading - "the cooldown is back" - is the one people expect
    -- from a cooldown display and the surprising one should be asked for.
    readyGlowUsableOnly = false,
    glowColor    = { 1.00, 0.72, 0.25 },
    glowSize     = 2,

    -- The nag. A spell that has been ready for this long IN COMBAT starts
    -- pulsing. 0 switches it off.
    reminderAfter = 0,
    reminderColor = { 1.00, 0.35, 0.30 },

    -- While our own tracked aura is up.
    activeGlow   = false,
    activeColor  = { 0.45, 0.90, 1.00 },

    -- The refresh window: the tail of an aura where recasting wastes nothing.
    -- NOT calculated here - Blizzard works it out and this addon hooks the
    -- answer, see CDM:InPandemic. It therefore only lights for auras the user
    -- has pandemic alerts switched on for in Blizzard's own settings.
    pandemicGlow  = false,
    pandemicColor = { 1.00, 0.45, 0.15 },

    -- Below this many seconds left, the cell pulses. Ours-only, see header.
    lowWarn      = 0,
    lowColor     = { 1.00, 0.35, 0.30 },

    -- Classic and quiet: the art greys out while the cooldown runs.
    dimOnCooldown = false,
    dimAmount     = 0.55,

    -- TAKE IT OFF THE SCREEN ENTIRELY, by state.
    --
    --   "never"    always there                       (the default)
    --   "cooling"  gone while it is on cooldown  - a display of what you
    --              can press RIGHT NOW and nothing else
    --   "ready"    gone while it is ready        - a display of what you are
    --              waiting for
    --
    -- Both readings are useful and they are opposites, which is why this is
    -- one setting with three values rather than two switches that can
    -- contradict each other.
    --
    -- IT LEAVES THE GAP. The cell keeps its place and goes to nothing;
    -- everything else stays where it was. A display whose icons move around
    -- as cooldowns come and go is one you have to re-read every time, and the
    -- muscle memory of "the third one is my stun" is worth more than the
    -- empty square costs. Closing the gap is a separate decision and a
    -- separate setting, not a side effect of this one.
    hideWhen = "never",

    -- How fast anything that pulses, pulses. One control for all of them, so
    -- a display does not end up with three different heartbeats.
    pulseSpeed   = 1.0,
}

---------------------------------------------------------------------------
-- The overlay
--
-- One frame per cell, above whatever the cell draws.
--
-- HALF OF WHAT IT HAS TO COVER IS NOT OURS. An adopted Cooldown Manager frame
-- is Blizzard's child, so its draw order has nothing to do with our frame
-- level. Both are read off the frame we have to beat and applied to ours:
-- reading a Blizzard frame's strata is harmless, writing to one is not.
---------------------------------------------------------------------------
function Effects.Attach(cell)
    if cell.fx then return cell.fx end

    local fx = CreateFrame("Frame", nil, cell)
    fx:SetAllPoints(cell)
    fx:Hide()

    -- The edge. Drawn on a frame of its own rather than as a texture on the
    -- cell, for the same reason the border is: a texture is painted under the
    -- cell's own child frames whatever layer it claims.
    fx.glow = ns.CreateBorder(fx, 2, "OVERLAY")
    fx.glow:Hide()

    -- A second, wider edge just outside the first. Two rings at different
    -- alphas read as a soft glow; one hard rectangle reads as a selection box.
    fx.halo = CreateFrame("Frame", nil, fx)
    fx.halo:SetPoint("TOPLEFT", fx, "TOPLEFT", -2, 2)
    fx.halo:SetPoint("BOTTOMRIGHT", fx, "BOTTOMRIGHT", 2, -2)
    fx.haloEdge = ns.CreateBorder(fx.halo, 2, "OVERLAY")
    fx.haloEdge:Hide()

    -- The running squares live on a frame of their own, OUTSIDE the cell's
    -- rect: a dot is centred on the outline, so half of it hangs over the
    -- edge and would be clipped by a parent that stops there.
    fx.dotHost = CreateFrame("Frame", nil, fx)
    fx.dotHost:SetPoint("TOPLEFT", fx, "TOPLEFT", -4, 4)
    fx.dotHost:SetPoint("BOTTOMRIGHT", fx, "BOTTOMRIGHT", 4, -4)
    fx.dotHost:Hide()
    fx.dots = {}

    fx.flash = fx:CreateTexture(nil, "OVERLAY", nil, 3)
    fx.flash:SetAllPoints(fx)
    fx.flash:SetTexture(ns.WHITE)
    fx.flash:SetBlendMode("ADD")
    fx.flash:SetAlpha(0)

    cell.fx = fx
    return fx
end

-- Puts the overlay above the thing it decorates. Called per pass, because the
-- adopted frame can change from one pass to the next - and because Blizzard
-- hands its item frames out of a pool with whatever level they had last.
local function Raise(cell, item)
    local fx = cell.fx
    if not fx then return end

    if item and item.GetFrameStrata then
        fx:SetFrameStrata(item:GetFrameStrata())
        fx:SetFrameLevel((item:GetFrameLevel() or 0) + 6)
    else
        fx:SetFrameStrata(cell:GetFrameStrata())
        fx:SetFrameLevel((cell:GetFrameLevel() or 0) + 12)
    end
end

---------------------------------------------------------------------------
-- The registry
--
-- Rebuilt every render pass rather than kept in step by hand. A cell that
-- stops being tracked has to stop being ticked, and "remember to unregister"
-- is the kind of rule that survives exactly until the next feature.
---------------------------------------------------------------------------
local watched = {}
local count = 0

function Effects.BeginPass()
    for index = 1, count do watched[index] = nil end
    count = 0
end

-- entry = { cell, spellID, cooldownID, drawn, effects }
function Effects.Watch(cell, entry)
    count = count + 1
    watched[count] = entry
    entry.cell = cell
end

-- Anything on a cell that is no longer showing an effect has to be put back,
-- or the last frame of a glow stays on screen for ever.
function Effects.Silence(cell)
    local fx = cell.fx
    if not fx then return end
    fx:Hide()
    fx.glow:Hide()
    if fx.dotHost then fx.dotHost:Hide() end
    fx.haloEdge:Hide()
    fx.flash:SetAlpha(0)
    cell.fxState = nil
end

---------------------------------------------------------------------------
-- Reading the state
---------------------------------------------------------------------------

-- Is this spell on a REAL cooldown right now?
--   true   yes
--   false  no, it is ready
--   nil    cannot tell - the value is secret, or there is no info
--
-- The GCD is explicitly not a cooldown here. Without that test every spell in
-- the game "comes off cooldown" every 1.5 seconds and the flash is a strobe.
local function OnCooldown(cooldownID)
    local info = ns.CDM:GetInfo(cooldownID)
    if not info then return nil end

    local active, gcd = info.isActive, info.isOnGCD
    if not ns.CanCompute(active) then return nil end
    if active ~= true then return false end

    -- Active AND on the GCD is the global cooldown spinning, not the spell's
    -- own. Unreadable GCD flag: treat the cooldown as real, which at worst
    -- delays a flash by a GCD and never invents one.
    if ns.CanCompute(gcd) and gcd == true then return false end
    return true
end

-- READY, as the rest of the addon asks it: true, false, or nil for "cannot
-- tell". The render pass needs the same answer the ticker works from, and two
-- readings of one state is how they end up disagreeing for a frame.
function Effects.Ready(cooldownID)
    local onCd = OnCooldown(cooldownID)
    if onCd == nil then return nil end
    return not onCd
end

---------------------------------------------------------------------------
-- WALKING THE OUTLINE OF A RECTANGLE
--
-- PURE, and the reason the running glow can be checked at all out here: the
-- harness has no screen, but "where is dot 3 of 8 at this instant" is
-- arithmetic.
--
-- progress 0..1 walks CLOCKWISE from the top-left corner and wraps, so a
-- caller can hand in 0.9 + 0.3 without thinking about it. Returns x, y
-- measured from the BOTTOM-LEFT, which is the corner WoW's SetPoint arithmetic
-- is happiest with.
---------------------------------------------------------------------------
function Effects.PerimeterPoint(progress, width, height)
    width, height = math.max(0, width or 0), math.max(0, height or 0)
    local perimeter = 2 * (width + height)
    if perimeter <= 0 then return 0, 0 end

    -- Wrap first: a dot at 1.25 is a dot at 0.25, and a negative one runs
    -- backwards rather than off the end.
    progress = progress % 1
    if progress < 0 then progress = progress + 1 end

    local along = progress * perimeter

    if along <= width then                       -- the top, left to right
        return along, height
    end
    along = along - width
    if along <= height then                      -- the right, downwards
        return width, height - along
    end
    along = along - height
    if along <= width then                       -- the bottom, right to left
        return width - along, 0
    end
    along = along - width
    return 0, along                              -- the left, upwards
end

-- Can it actually be cast right now - not "is the cooldown back", but "will
-- pressing it do something". nil when the client will not say.
--
-- IsSpellUsable answers two things at once and the second is the one that
-- matters here: usable, and whether the reason it is not is resources. A
-- spell out of range or without a target reports unusable too, and that is
-- NOT what this is for - a defensive is unusable by that reading whenever
-- nothing is targeted, and greying it out would be wrong every pull.
function Effects.Affordable(spellID)
    if not (spellID and C_Spell and C_Spell.IsSpellUsable) then return nil end
    local ok, usable, noResource = pcall(C_Spell.IsSpellUsable, spellID)
    if not ok then return nil end
    if not ns.CanCompute(usable) or not ns.CanCompute(noResource) then
        return nil
    end
    -- Unusable for any OTHER reason is left alone: only the resource answer
    -- belongs to this feature.
    if noResource == true then return false end
    return true
end

-- PURE. Whether the ready glow may light this instant.
--
--   ready       the cooldown is back
--   affordable  true / false / nil for "the client will not say"
--
-- Unknown lights it. Every unreadable value in this addon falls back to the
-- behaviour of the feature switched off, because an effect that disappears
-- when something could not be read is indistinguishable from a broken one.
function Effects.GlowAllowed(fxOpts, ready, affordable)
    if not (fxOpts and ready) then return false end
    if not fxOpts.readyGlow then return false end
    if fxOpts.readyGlowUsableOnly and affordable == false then return false end
    return true
end

-- PURE. Whether this cell is currently hidden by its state rule.
--
-- `ready` is the three-valued answer above, and nil is the important one: a
-- cooldown the client will not talk about must never disappear. An icon that
-- vanishes because the addon could not read something is indistinguishable
-- from a bug, and it takes the spell with it.
function Effects.HiddenByState(fxOpts, ready)
    if not fxOpts or ready == nil then return false end
    local rule = fxOpts.hideWhen
    if rule == "cooling" then return ready == false end
    if rule == "ready" then return ready == true end
    return false
end

---------------------------------------------------------------------------
-- The tick
--
-- One frame, one OnUpdate, every watched cell. Throttled: nothing here has to
-- be right to the frame, and a pulse computed twelve times a second looks
-- exactly like one computed sixty times a second.
---------------------------------------------------------------------------
local TICK = 0.06
local elapsed = 0

-- Set by any cell whose state rule changed what it should look like, cleared
-- by the ticker after ONE repaint. A flag rather than a call per cell: twelve
-- cooldowns coming back together is one render, not twelve.
local repaintWanted = false

local function Pulse(speed, phase)
    -- 0..1, smooth. phase keeps two different pulses on one cell from lining
    -- up into a single brighter one.
    return 0.5 + 0.5 * sin(GetTime() * 3.2 * (speed or 1) + (phase or 0))
end

-- THE SQUARES, PLACED. Everything decided here is arithmetic from
-- Effects.PerimeterPoint; this function only turns it into anchors.
--
-- The dots are made on demand and kept: a frame cannot be freed in this game,
-- so a pool that only ever grows to the largest count a bar has used is the
-- honest shape rather than a leak.
local function RunDots(fx, fxOpts, colour, alpha, thickness)
    local host = fx.dotHost
    if not host then return end

    local wanted = math.max(2, math.min(24, math.floor(fxOpts.glowDots or 8)))
    local size = math.max(2, thickness + 1)

    -- The inset the host was given, so a dot centred on the OUTLINE of the
    -- cell sits at the middle of its own square rather than at its corner.
    local width = math.max(0, (host:GetWidth() or 0) - 8)
    local height = math.max(0, (host:GetHeight() or 0) - 8)

    -- One lap every four seconds at speed 1. Slow enough to read as a
    -- travelling light rather than as a flicker.
    local lap = (GetTime() * 0.25 * (fxOpts.pulseSpeed or 1)) % 1

    for index = 1, wanted do
        local dot = fx.dots[index]
        if not dot then
            dot = host:CreateTexture(nil, "OVERLAY")
            dot:SetTexture(ns.WHITE)
            dot:SetBlendMode("ADD")
            fx.dots[index] = dot
        end

        local x, y = Effects.PerimeterPoint(lap + (index - 1) / wanted,
            width, height)
        dot:SetSize(size, size)
        dot:ClearAllPoints()
        -- +4 puts it back into the host's own coordinates, and the half-size
        -- centres the square on the line instead of hanging it off one side.
        dot:SetPoint("CENTER", host, "BOTTOMLEFT", x + 4, y + 4)
        dot:SetColorTexture(colour[1], colour[2], colour[3], alpha)
        dot:Show()
    end

    -- Anything left over from a larger count is parked, never destroyed.
    for index = wanted + 1, #fx.dots do fx.dots[index]:Hide() end

    host:Show()
end

local function TickCell(entry, inCombat, span)
    local cell = entry.cell
    local fx = cell.fx
    if not fx then return end

    local fxOpts = entry.effects
    local state = cell.fxState
    if not state then
        state = {}
        cell.fxState = state
    end

    ---------------------------------------------------------------------
    -- What is true right now
    ---------------------------------------------------------------------
    -- TWO DIFFERENT QUESTIONS, and they are not each other's opposite.
    --
    --   ready  a COOLDOWN is available again. nil when it cannot be read.
    --   lit    one of OUR OWN auras is up. nil when this is not that kind of
    --          cell at all.
    --
    -- The first version answered both with one field - `ready = not active` on
    -- an aura cell - and it was backwards in the way that shows: the ready
    -- glow lit every proc that was DOWN, and the ready flash fired when one
    -- ran out rather than when it landed. An aura cell has no cooldown to be
    -- ready, so `ready` simply stays unknown there and every cooldown effect
    -- below stands down on its own.
    local ready, lit, remaining

    if entry.drawn then
        lit = cell.active and true or false
        if lit and state.auraEnds then
            remaining = state.auraEnds - GetTime()
        end
    else
        local onCd = OnCooldown(entry.cooldownID)
        if onCd ~= nil then ready = not onCd end
    end

    ---------------------------------------------------------------------
    -- The flash, on the edge into the state worth noticing: a cooldown
    -- coming back, or one of our own auras landing.
    --
    -- Compared against `false` rather than "not nil": the very first tick
    -- after a cell appears knows nothing about the tick before it, and a
    -- flash there would fire on every reload and every re-flow.
    ---------------------------------------------------------------------
    local arrived
    if lit ~= nil then
        arrived = lit and state.wasLit == false
        state.wasLit = lit
    elseif ready ~= nil then
        arrived = ready and state.wasReady == false
        state.wasReady = ready
    end

    if arrived and fxOpts.readyFlash then
        state.flashLeft = (fxOpts.readyPulses or 2) * 0.35
    end

    -- How long it has been sitting there ready, for the nag. Cooldowns only:
    -- an aura that is up is not something you are forgetting to press.
    if ready == false then
        state.readySince = nil
    elseif ready and not state.readySince then
        state.readySince = GetTime()
    end

    ---------------------------------------------------------------------
    -- Draw it
    ---------------------------------------------------------------------
    local glowColour, glowAlpha

    -- The nag wins over the plain ready glow: it is the one that means
    -- something is going wrong, and two edges at once is just mud.
    local nagAfter = fxOpts.reminderAfter or 0
    if nagAfter > 0 and inCombat and ready and state.readySince
        and (GetTime() - state.readySince) >= nagAfter then
        glowColour = fxOpts.reminderColor
        glowAlpha = 0.35 + 0.65 * Pulse(fxOpts.pulseSpeed)
    elseif Effects.GlowAllowed(fxOpts, ready,
            fxOpts.readyGlowUsableOnly and Effects.Affordable(entry.spellID) or nil)
        and (inCombat or not fxOpts.readyGlowCombatOnly) then
        glowColour = fxOpts.glowColor
        glowAlpha = 0.85
    elseif fxOpts.activeGlow and lit then
        glowColour = fxOpts.activeColor
        glowAlpha = 0.85
    end

    -- THE REFRESH WINDOW WINS OVER THE PLAIN GLOWS, for the same reason the
    -- nag does: it is the one that means "press this now". It sits below the
    -- last-seconds warning, which is more urgent still.
    if fxOpts.pandemicGlow
        and ns.CDM:InPandemic(cell.mirrorItem or cell.item) then
        glowColour = fxOpts.pandemicColor
        glowAlpha = 0.45 + 0.55 * Pulse(fxOpts.pulseSpeed)
    end

    -- The last-seconds warning, on top of whatever else is showing.
    local low = fxOpts.lowWarn or 0
    if low > 0 and remaining and remaining > 0 and remaining <= low then
        glowColour = fxOpts.lowColor
        glowAlpha = 0.35 + 0.65 * Pulse((fxOpts.pulseSpeed or 1) * 1.6, pi / 2)
    end

    if glowColour then
        local thickness = fxOpts.glowSize or 2

        if fxOpts.glowStyle == "pixel" then
            -- The two rings step aside entirely. A running outline INSIDE a
            -- solid one is a box with something crawling in it; the motion is
            -- the whole signal and it needs the edge to itself.
            fx.glow:Hide()
            fx.haloEdge:Hide()
            RunDots(fx, fxOpts, glowColour, glowAlpha, thickness)
        else
            if fx.dotHost then fx.dotHost:Hide() end
            fx.glow:SetThickness(thickness)
            fx.glow:SetColor(glowColour[1], glowColour[2], glowColour[3], glowAlpha)
            fx.glow:Show()
            fx.haloEdge:SetThickness(math.max(1, thickness - 1))
            fx.haloEdge:SetColor(glowColour[1], glowColour[2], glowColour[3],
                glowAlpha * 0.35)
            fx.haloEdge:Show()
        end
        fx:Show()
    else
        fx.glow:Hide()
        fx.haloEdge:Hide()
        if fx.dotHost then fx.dotHost:Hide() end
    end

    if state.flashLeft and state.flashLeft > 0 then
        -- The REAL span since the last tick, not the throttle interval. They
        -- are not the same number - a tick fires on the first frame at or
        -- after TICK, so counting in TICKs makes "two pulses" run long on a
        -- loaded machine and drift further the worse the frame rate is.
        state.flashLeft = state.flashLeft - span
        local colour = fxOpts.readyColor or { 1, 1, 1 }
        -- Repeating sawtooth, so "two pulses" is two visible flashes rather
        -- than one long fade that happens to last twice as long.
        local phase = (state.flashLeft % 0.35) / 0.35
        fx.flash:SetVertexColor(colour[1], colour[2], colour[3])
        fx.flash:SetAlpha(phase * 0.55)
        fx:Show()
        if state.flashLeft <= 0 then
            state.flashLeft = nil
            fx.flash:SetAlpha(0)
        end
    elseif fx.flash:GetAlpha() > 0 then
        fx.flash:SetAlpha(0)
    end

    if not glowColour and not state.flashLeft then fx:Hide() end

    ---------------------------------------------------------------------
    -- Taking it off the screen, by state
    --
    -- NOT WRITTEN HERE, and that is the whole design. The render pass owns a
    -- cell's alpha - it multiplies the bar's own alpha, the visibility fade
    -- and the unlocked state into one number - and a ticker writing a second
    -- alpha sixteen times a second would win until the next render and lose
    -- on it, which is a flicker rather than a feature.
    --
    -- So this notices the FLIP and asks for one repaint. A cooldown starting
    -- or ending is a handful of events a fight, not a per-frame job.
    ---------------------------------------------------------------------
    local wantsHidden = Effects.HiddenByState(fxOpts, ready)
    if state.hidden == nil then
        state.hidden = wantsHidden
    elseif state.hidden ~= wantsHidden then
        state.hidden = wantsHidden
        repaintWanted = true
    end

    ---------------------------------------------------------------------
    -- Greying out while the cooldown runs
    ---------------------------------------------------------------------
    if not entry.SetDim then return end

    if fxOpts.dimOnCooldown and ready ~= nil then
        local target = ready and 1 or (fxOpts.dimAmount or 0.55)
        -- Only on a CHANGE. Writing a vertex colour sixteen times a second
        -- for the whole length of a two-minute cooldown is work for nothing.
        if state.dim ~= target then
            state.dim = target
            entry.SetDim(target)
        end
    elseif state.dim and state.dim ~= 1 then
        state.dim = 1
        entry.SetDim(1)
    end
end

local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < TICK then return end

    local span = elapsed
    elapsed = 0
    if count == 0 then return end

    local inCombat = UnitAffectingCombat("player") and true or false

    for index = 1, count do
        local entry = watched[index]
        if entry and entry.cell then
            local ok, err = pcall(TickCell, entry, inCombat, span)
            if not ok then
                -- One bad cell must not stop the other eleven, and it must not
                -- spam the error frame sixteen times a second either.
                watched[index] = nil
                geterrorhandler()(err)
            end
        end
    end

    -- AFTER the walk, so a render triggered by the first cell does not run
    -- while the other eleven are still being ticked - Render rebuilds the
    -- very list being walked.
    if repaintWanted then
        repaintWanted = false
        if ns.Screen and ns.Screen.Render then pcall(ns.Screen.Render, ns.Screen) end
    end
end)

---------------------------------------------------------------------------
-- Wiring from the render pass
---------------------------------------------------------------------------

-- Whether a bar wants any of this at all. A bar with everything off is not
-- registered, so the ticker walks nothing and costs nothing.
function Effects.Wanted(fxOpts)
    if not fxOpts then return false end
    return fxOpts.readyFlash or fxOpts.readyGlow or fxOpts.activeGlow
        or fxOpts.pandemicGlow
        or fxOpts.dimOnCooldown
        or (fxOpts.reminderAfter or 0) > 0
        or (fxOpts.lowWarn or 0) > 0
        -- A bar that only hides things still needs the ticker: it is the
        -- only thing watching for the state to flip.
        or (fxOpts.hideWhen and fxOpts.hideWhen ~= "never")
end

-- Called by Screen for a cell that is showing something. `setDim` is how the
-- cell greys its own art - the two renderers do it differently, so the cell
-- hands in the function rather than this file learning both.
function Effects.Track(cell, cfg, spellID, cooldownID, drawn, setDim)
    local fxOpts = cfg.effects
    if not Effects.Wanted(fxOpts) then
        Effects.Silence(cell)
        return
    end

    Effects.Attach(cell)
    Raise(cell, cell.item)

    Effects.Watch(cell, {
        spellID = spellID,
        cooldownID = cooldownID,
        drawn = drawn and true or false,
        effects = fxOpts,
        SetDim = setDim,
    })
end

-- The aura clock tells the low-time warning when the thing it is watching
-- ends. Stored on the cell, because the tick has no other way to know.
function Effects.NoteAuraEnd(cell, endTime)
    cell.fxState = cell.fxState or {}
    cell.fxState.auraEnds = endTime
end
