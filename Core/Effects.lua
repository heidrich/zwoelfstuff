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
    glowColor    = { 1.00, 0.72, 0.25 },
    glowSize     = 2,

    -- The nag. A spell that has been ready for this long IN COMBAT starts
    -- pulsing. 0 switches it off.
    reminderAfter = 0,
    reminderColor = { 1.00, 0.35, 0.30 },

    -- While our own tracked aura is up.
    activeGlow   = false,
    activeColor  = { 0.45, 0.90, 1.00 },

    -- Below this many seconds left, the cell pulses. Ours-only, see header.
    lowWarn      = 0,
    lowColor     = { 1.00, 0.35, 0.30 },

    -- Classic and quiet: the art greys out while the cooldown runs.
    dimOnCooldown = false,
    dimAmount     = 0.55,

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

---------------------------------------------------------------------------
-- The tick
--
-- One frame, one OnUpdate, every watched cell. Throttled: nothing here has to
-- be right to the frame, and a pulse computed twelve times a second looks
-- exactly like one computed sixty times a second.
---------------------------------------------------------------------------
local TICK = 0.06
local elapsed = 0

local function Pulse(speed, phase)
    -- 0..1, smooth. phase keeps two different pulses on one cell from lining
    -- up into a single brighter one.
    return 0.5 + 0.5 * sin(GetTime() * 3.2 * (speed or 1) + (phase or 0))
end

local function TickCell(entry, inCombat)
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
    local ready, remaining

    if entry.drawn then
        -- Our own aura cell: we own the clock, so both answers are exact.
        ready = not cell.active
        if cell.active and state.auraEnds then
            remaining = state.auraEnds - GetTime()
        end
    else
        local onCd = OnCooldown(entry.cooldownID)
        if onCd == nil then
            ready = nil
        else
            ready = not onCd
        end
    end

    ---------------------------------------------------------------------
    -- The flash, on the edge from "was on cooldown" to "is ready"
    ---------------------------------------------------------------------
    if ready ~= nil and state.wasReady ~= nil and ready and not state.wasReady then
        if fxOpts.readyFlash then
            state.flashLeft = (fxOpts.readyPulses or 2) * 0.35
            state.flashTotal = state.flashLeft
        end
        state.readySince = GetTime()
    end

    if ready ~= nil and not ready then
        state.readySince = nil
    elseif ready and not state.readySince then
        state.readySince = GetTime()
    end

    if ready ~= nil then state.wasReady = ready end

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
    elseif fxOpts.readyGlow and ready
        and (inCombat or not fxOpts.readyGlowCombatOnly) then
        glowColour = fxOpts.glowColor
        glowAlpha = 0.85
    elseif fxOpts.activeGlow and entry.drawn and cell.active then
        glowColour = fxOpts.activeColor
        glowAlpha = 0.85
    end

    -- The last-seconds warning, on top of whatever else is showing.
    local low = fxOpts.lowWarn or 0
    if low > 0 and remaining and remaining > 0 and remaining <= low then
        glowColour = fxOpts.lowColor
        glowAlpha = 0.35 + 0.65 * Pulse((fxOpts.pulseSpeed or 1) * 1.6, pi / 2)
    end

    if glowColour then
        local thickness = fxOpts.glowSize or 2
        fx.glow:SetThickness(thickness)
        fx.glow:SetColor(glowColour[1], glowColour[2], glowColour[3], glowAlpha)
        fx.glow:Show()
        fx.haloEdge:SetThickness(math.max(1, thickness - 1))
        fx.haloEdge:SetColor(glowColour[1], glowColour[2], glowColour[3],
            glowAlpha * 0.35)
        fx.haloEdge:Show()
        fx:Show()
    else
        fx.glow:Hide()
        fx.haloEdge:Hide()
    end

    if state.flashLeft and state.flashLeft > 0 then
        state.flashLeft = state.flashLeft - TICK
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
    elapsed = 0
    if count == 0 then return end

    local inCombat = UnitAffectingCombat("player") and true or false

    for index = 1, count do
        local entry = watched[index]
        if entry and entry.cell then
            local ok, err = pcall(TickCell, entry, inCombat)
            if not ok then
                -- One bad cell must not stop the other eleven, and it must not
                -- spam the error frame sixteen times a second either.
                watched[index] = nil
                geterrorhandler()(err)
            end
        end
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
        or fxOpts.dimOnCooldown
        or (fxOpts.reminderAfter or 0) > 0
        or (fxOpts.lowWarn or 0) > 0
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
