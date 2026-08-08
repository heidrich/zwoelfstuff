---------------------------------------------------------------------------
-- Screen - the bars, on screen.
--
-- A cell holds a spell, and there are exactly two kinds of spell. They are
-- rendered by two completely different mechanisms, and knowing which is which
-- is most of this file:
--
--   A COOLDOWN MANAGER SPELL is not drawn. Blizzard already owns a frame for
--   it - correct icon, swipe, charges, stacks and timing, all computed inside
--   the game where secret values are not a problem. We adopt that frame: move
--   it onto our cell and hold it there. Drawing our own would mean reading
--   aura data, which patch 12.0 forbids outright.
--
--   AN AURA PROC has no such frame - that is the whole reason Core/Auras.lua
--   exists. There we draw the icon ourselves and run our own clock, started
--   by the glow on the ability the aura empowers.
--
-- THE RULES FOR TOUCHING BLIZZARD'S FRAMES, and they are not style advice.
-- Taken verbatim from the reference implementation on this machine
-- (EllesmereUICooldownManager/EllesmereUICdmHooks.lua, top of file):
--
--     Never SetParent/SetScale/Hide/Show on Blizzard frames
--     Never move Blizzard frames offscreen
--     Never write custom keys to Blizzard frame tables
--     All per-frame data in external weak-keyed tables
--     Unclaimed frames: SetAlpha(0). Claimed: SetAlpha(1).
--
-- Two consequences run through everything below:
--
--   * An adopted frame stays Blizzard's child, so it does NOT inherit our
--     scale or our alpha. "Scale" is therefore a size multiplier here, not a
--     SetScale, and per-bar opacity is pushed into the frame itself. Both
--     would otherwise apply to our own cells and silently skip half the bar.
--   * A cooldown you did not place vanishes with alpha, never with Hide().
--
-- WHY IT TAKES OVER RATHER THAN SITTING NEXT TO IT.
--
-- Blizzard lays its viewer out by walking its active frames and placing them
-- in a row. It has no idea one of them now lives on our bar, so it leaves a
-- hole where that one used to be. There is no version of this where the
-- original bar still looks right - so the default is to take the display
-- over completely, and the setting to switch that off says what it costs.
---------------------------------------------------------------------------
local _, ns = ...

local Screen = {}
ns.Screen = Screen

---------------------------------------------------------------------------
-- Where a cell sits, and how big it is
--
-- The arrangement itself lives in Core/Layout.lua: it is pure geometry and it
-- has no business being tangled up with frames. This file asks it once per
-- bar and then places what it is told.
--
-- Everything is multiplied by the bar's scale in THAT file rather than through
-- SetScale, because adopted frames are not our children - see the header.
---------------------------------------------------------------------------
local function Metrics(cfg)
    local scale = cfg.scale or 1
    local width, height = ns.Layout.CellSize(cfg, nil)
    return width, height, (cfg.spacing or 4) * scale, (cfg.lineSpacing or 4) * scale
end

-- Which point of a frame sits where, in screen coordinates. Needed because a
-- bar can be pinned by any of its nine points now - grow-to-the-right is
-- "pinned by the left edge", and the stored x/y are that point's offset.
local function PointOffset(frame, point)
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    if not (left and bottom) then return nil end

    local width, height = frame:GetWidth(), frame:GetHeight()
    local x, y = left + width / 2, bottom + height / 2

    if point:find("LEFT") then x = left
    elseif point:find("RIGHT") then x = left + width end

    if point:find("BOTTOM") then y = bottom
    elseif point:find("TOP") then y = bottom + height end

    return x, y
end
ns.PointOffset = PointOffset

---------------------------------------------------------------------------
-- Aura cells - our own icon, our own clock
--
-- The remaining time is a number we own (measured, see Core/Auras.lua), so
-- SetCooldown takes plain numbers here. Nothing on this path reads aura data,
-- which is exactly why it works on 12.0.
---------------------------------------------------------------------------
local function BuildAuraVisual(cell)
    if cell.aura then return cell.aura end

    local aura = CreateFrame("Frame", nil, cell)
    aura:SetAllPoints(cell)

    aura.bg = aura:CreateTexture(nil, "BACKGROUND")
    aura.bg:SetAllPoints(aura)
    aura.bg:SetColorTexture(0, 0, 0, 0.9)

    aura.icon = aura:CreateTexture(nil, "ARTWORK")
    aura.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- THE FILL. Only ever seen on a bar-shaped cell.
    --
    -- An adopted buff-bar frame arrives with Blizzard's own status bar in it.
    -- A cell we draw ourselves had nothing, so a bar-shaped aura was a square
    -- icon with a hole beside it - it did not read as a bar at all, which is
    -- the whole reason somebody picks that shape.
    --
    -- A real StatusBar rather than a texture we resize by hand: it takes the
    -- textures out of LibSharedMedia unchanged, it clips its own art instead
    -- of squashing it, and the value is one number.
    aura.fill = CreateFrame("StatusBar", nil, aura)
    aura.fill:SetFrameLevel(aura:GetFrameLevel() + 1)
    aura.fill:SetMinMaxValues(0, 1)
    aura.fill:SetValue(0)
    aura.fill:Hide()

    -- One overlay per stack threshold is created on demand; see
    -- ApplyThresholds below for why they are not made here.
    aura.thresholds = {}

    -- One line per charge boundary, also on demand: most spells have one
    -- charge and would carry an empty pool for the whole session.
    aura.marks = {}

    -- THE SPARK RIDES THE FILL'S TEXTURE, not the fill frame.
    --
    -- Anchored to the texture's leading edge, it follows the clock with no
    -- per-frame work at all: the engine moves the texture, and anything
    -- anchored to it moves with it. Anchoring to the frame instead would mean
    -- computing a position every tick, for the same picture.
    aura.spark = aura.fill:CreateTexture(nil, "OVERLAY")
    aura.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    aura.spark:SetBlendMode("ADD")
    aura.spark:Hide()

    aura.cd = CreateFrame("Cooldown", nil, aura, "CooldownFrameTemplate")
    aura.cd:SetDrawEdge(false)
    aura.cd:SetDrawSwipe(true)
    aura.cd:SetSwipeColor(0, 0, 0, 0.7)
    aura.cd:SetHideCountdownNumbers(false)
    -- The engine draws the number; OmniCC drawing a second one on top of it
    -- is the usual cause of a doubled countdown.
    aura.cd.noCooldownCount = true

    aura.textLayer = CreateFrame("Frame", nil, aura)
    aura.textLayer:SetAllPoints(aura)
    aura.textLayer:SetFrameLevel(aura.cd:GetFrameLevel() + 2)

    -- Its own frame above the swipe, exactly like an adopted icon's. A
    -- texture on the cell would be painted under the cell's own child frames
    -- whatever layer it claims, and the cooldown swipe is one of them - the
    -- border would darken as the cooldown ran while the adopted icons next
    -- to it did not.
    aura.chrome = ns.CreateChrome(aura)

    aura.label = aura.textLayer:CreateFontString(nil, "OVERLAY")
    aura.label:SetJustifyH("LEFT")
    aura.label:SetWordWrap(false)

    -- The countdown at the far end of a MIRRORED bar. A bar we clock ourselves
    -- puts its number in the Cooldown widget over the icon; a mirrored one has
    -- no duration of its own to give that widget, so the text is copied from
    -- Blizzard's own timer instead. Only ever shown in that case.
    aura.timer = aura.textLayer:CreateFontString(nil, "OVERLAY")
    aura.timer:SetJustifyH("RIGHT")
    aura.timer:SetWordWrap(false)
    ns.Media.ApplyFont(aura.timer, nil, 11)
    aura.timer:Hide()
    -- A font HERE, not only where the size is chosen. Icon cells hide the
    -- label and never reach that branch, and SetText on a font string with no
    -- font raises rather than doing nothing.
    ns.Media.ApplyFont(aura.label, nil, 11)

    -- HOW MANY CHARGES ARE LEFT. Adopted icons get this from Blizzard's own
    -- ChargeCount frame; a cell we draw ourselves had nothing at all, which
    -- is why a charge spell on one of our bars showed no number while the
    -- same spell on an adopted icon beside it did.
    aura.charges = aura.textLayer:CreateFontString(nil, "OVERLAY")
    aura.charges:SetWordWrap(false)
    ns.Media.ApplyFont(aura.charges, nil, 11)
    aura.charges:Hide()

    cell.aura = aura
    return aura
end

-- The same style table the adopted frames get, applied to the parts we drew
-- ourselves. Kept next to each other on purpose: these two are the ones that
-- must never disagree, because they sit on the same bar.
local function StyleAuraVisual(aura, style, isBar)
    ns.PaintSurface(aura.bg, style)
    -- Same rule as an adopted frame, from the same place: a bar frames itself
    -- from outside, an icon from just inside. Decided once, or the two
    -- renderers sitting on one bar would eventually disagree about it.
    ns.PaintBorder(aura.chrome, style, isBar)

    local zoom = style.iconZoom
    aura.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)

    local swipe = style.swipeColor
    aura.cd:SetSwipeColor(swipe[1], swipe[2], swipe[3], style.swipeAlpha)
    aura.cd:SetDrawEdge(style.showEdge)
    aura.cd:SetHideCountdownNumbers(not style.countdown.show)
    if style.countdown.show then
        -- The same trap as an adopted icon's, and for the same reason: the
        -- engine has not made the font string yet on a cell that is not
        -- counting down. See ns.StyleCountdown.
        ns.StyleCountdown(aura.cd, style.countdown)
    end

    -- The fill wears a real LibSharedMedia texture, so the twenty this addon
    -- ships and everything the user's other addons registered are all equally
    -- available to it. An unknown name falls back to a flat white that the
    -- colour below tints - never to nothing, which is how a bar ends up
    -- invisible because of a typo in a saved variable.
    local fill = style.fillTexture
    if fill and ns.Media.IsKnown("statusbar", fill) then
        aura.fillTexturePath = ns.Media.Statusbar(fill)
    else
        aura.fillTexturePath = ns.WHITE
    end
    -- Kept on the frame because the threshold overlays wear the same texture,
    -- and resolving it twice is how the two ended up looking different.
    aura.fill:SetStatusBarTexture(aura.fillTexturePath)

    local colour = style.fillColor
    aura.fill:SetStatusBarColor(colour[1], colour[2], colour[3], style.fillAlpha)
    -- WHICH END, not which direction in time. Those are two settings now, and
    -- confusing them was the reported "fillup richtung stimmt nicht": this call
    -- moves the fill to the other end of the bar and has nothing to do with
    -- whether it grows or drains. The clock is in RefreshFill.
    -- WHICH WAY IT RUNS, not which direction in time. Those are two settings
    -- and confusing them was the reported "fillup richtung stimmt nicht": this
    -- pair decides where the fill starts and along which axis, and has nothing
    -- to do with whether it grows or drains. The clock is in RefreshFill.
    --
    -- The orientation is why up and down are new: SetReverseFill on its own
    -- only ever flips a HORIZONTAL bar, so a vertical fill was unreachable no
    -- matter which way the old switch was thrown.
    local direction = style.fillDirection or ns.Layout.FillDirection("right")
    aura.fill:SetOrientation(direction.orientation)
    aura.fill:SetReverseFill(direction.reverse)
    aura.grow = style.fillGrow and true or false
    -- Handed to the overlays through the frame rather than as an argument:
    -- they are applied from RefreshFill, which owns everything about the
    -- fill's behaviour and deliberately takes no style.
    aura.stackThresholds = style.stackThresholds
    aura.showSpark = style.showSpark
    aura.chargeMarks = style.chargeMarks
    aura.chargeMarkColor = style.chargeMarkColor

    local name = style.spellName
    ns.Media.ApplyFont(aura.label, name.font, name.size, name.outline, name.color)

    local timer = style.countdown
    ns.Media.ApplyFont(aura.timer, timer.font, timer.size, timer.outline, timer.color)

    -- The charge count is placed HERE rather than in the layout pass: where it
    -- sits is a position the user picked, not a consequence of the cell's
    -- shape. Same anchor and same inset as an adopted icon's, from the same
    -- function, so the two renderers cannot drift apart on it.
    ns.PlaceText(aura.charges, aura, style.charges)
    -- Read by ApplyChargeCount, which runs on its own event and has no style
    -- table in hand - the same arrangement as the spark and the marks above.
    aura.showCharges = style.charges.show
end

-- WHERE THE SPELL NAME SITS ON A BAR CELL.
--
-- Its nine positions and its nudge were being ignored outright: both
-- renderers anchored it hard to LEFT and threw the setting away. The panel
-- offered a control that could not do anything, which is not a limitation -
-- it is a broken control, and the owner found it by trying it.
--
-- The name is the one text element with a WIDTH. It is a word rather than a
-- number, so it has to be told where to stop or it runs across the timer at
-- the other end. That is why the band beside the icon is worked out first and
-- the position is applied INSIDE it, instead of the plain point-and-nudge the
-- numbers get.
--
-- Deliberately not ns.TextOffset: that adds the 2px an outlined number needs
-- to clear a border, and this label is already inset by the icon gap. Two
-- insets stacked is a name that does not line up with anything.
-- `width` is the cell's width from the ARRANGEMENT, not parent:GetWidth().
-- This runs during the layout pass, where the frame may not have been sized
-- yet - and a label handed a width of zero collapses to the 10px floor and
-- ellipsises every name on the bar.
local function PlaceLabel(label, parent, text, width, leftInset, rightInset)
    local x, y = (text and text.x) or 0, (text and text.y) or 0
    local point, side, justify = ns.Layout.LabelAnchor(text and text.anchor)

    local inset = 0
    if side == "LEFT" then
        inset = leftInset
    elseif side == "RIGHT" then
        inset = -rightInset
    end

    label:ClearAllPoints()
    label:SetWidth(math.max(10, (width or 0) - leftInset - rightInset))
    label:SetPoint(point, parent, point, inset + x, y)
    label:SetJustifyH(justify)
end

-- Bar-shaped aura cells put the icon on the left and the name beside it;
-- icon-shaped ones are just the icon.
local function LayoutAuraVisual(aura, cfg, slot)
    local width, height = slot.w, slot.h
    if slot.kind == "bar" then
        -- Square, wherever it sits. Same rule as an adopted icon: a spell
        -- icon stretched to the width of a bar is what a tracking bar must
        -- never look like.
        local placement = cfg.iconPlacement or "left"
        local shown = placement ~= "hidden"

        aura.icon:ClearAllPoints()
        aura.icon:SetShown(shown)
        if shown then
            local side = placement == "right" and "RIGHT" or "LEFT"
            aura.icon:SetPoint("TOP" .. side, aura, "TOP" .. side, 0, 0)
            aura.icon:SetPoint("BOTTOM" .. side, aura, "BOTTOM" .. side, 0, 0)
            aura.icon:SetWidth(height)
        end

        -- The fill takes the whole cell except the square the icon occupies.
        -- The name then reads OVER it, the way it does on every other bar in
        -- the game - a bar with the text pushed off to one side of the fill
        -- wastes the width that made it a bar.
        local gap = shown and height or 0
        aura.fill:ClearAllPoints()
        aura.fill:SetPoint("TOPLEFT", aura, "TOPLEFT",
            (placement == "right") and 0 or gap, 0)
        aura.fill:SetPoint("BOTTOMRIGHT", aura, "BOTTOMRIGHT",
            (placement == "right") and -gap or 0, 0)
        aura.fill:Show()

        local leftInset, rightInset = ns.Layout.LabelBand(placement, shown and height or 0)
        PlaceLabel(aura.label, aura, cfg.spellName, width, leftInset, rightInset)
        aura.label:SetShown((cfg.spellName or {}).show ~= false)

        aura.timer:ClearAllPoints()
        aura.timer:SetPoint("RIGHT", aura, "RIGHT",
            (shown and placement == "right") and -(height + 5) or -5, 0)

        aura.cd:ClearAllPoints()
        if shown then
            aura.cd:SetAllPoints(aura.icon)
        else
            aura.cd:SetAllPoints(aura)
        end
    else
        -- Edge to edge, exactly like an adopted icon: Blizzard's fill the
        -- whole frame and the border sits over them. A one-pixel inset here
        -- and none there is the kind of difference nobody can name and
        -- everybody sees.
        aura.icon:ClearAllPoints()
        aura.icon:SetAllPoints(aura)

        aura.label:Hide()
        aura.fill:Hide()
        aura.timer:Hide()

        aura.cd:ClearAllPoints()
        aura.cd:SetAllPoints(aura.icon)
    end
end

-- Cooldown:Clear does not exist on every build this addon supports, so the
-- fallback is the two-zero SetCooldown that has always meant the same thing.
local function ClearCooldown(cd)
    if cd.Clear then
        cd:Clear()
    else
        cd:SetCooldown(0, 0)
    end
end

-- Active auras are lit; inactive ones stay in place, quieter. A cell that
-- disappeared entirely would make the bar re-flow under the eye, and the
-- point of a fixed grid is that a spell is always in the same place.
--
-- "Quieter" is one setting, not three stacked. Alpha AND desaturation AND a
-- vertex darkening on top turned an icon into a dark box that read as broken
-- next to its sharp neighbours - which is exactly what it looked like on a
-- bar where two of six cells are ours.
local function PaintAura(cell, active)
    local aura = cell.aura
    if not aura then return end

    aura.icon:SetVertexColor(1, 1, 1)

    if active then
        aura.icon:SetDesaturated(false)
        aura:SetAlpha(1)
        aura:Show()
        return
    end

    local alpha = cell.inactiveAlpha or 0.55
    -- A cell whose spell an earlier bar already took is quieter still: it is
    -- not waiting to light up, it is never going to.
    if cell.conflict then alpha = alpha * 0.4 end

    aura.icon:SetDesaturated(cell.inactiveDesaturate ~= false)
    aura:SetAlpha(alpha)
    -- Zero means "do what Blizzard does and take it away", for anyone who
    -- prefers that to a placeholder.
    aura:SetShown(alpha > 0)
    ClearCooldown(aura.cd)
end

-- The fill of a bar-shaped aura cell, driven by the clock this addon owns.
--
-- Its own OnUpdate rather than a seat in the effects ticker: that ticker only
-- walks cells which asked for an effect, and a bar has to drain whether or
-- not anything else is switched on. It runs ONLY while an aura is actually
-- up and takes its script off again the moment it is not, so a screen full of
-- idle cells costs nothing at all.
--
-- Everything it needs is on the cell, so a render pass in the middle of a
-- buff picks the fill back up where it was instead of blanking it.
---------------------------------------------------------------------------
-- Stack thresholds: colour past N stacks, WITHOUT ever comparing N
--
-- The stack count can be a secret value, and secret values may not be
-- compared, added to or tested for truth in Lua. So the comparison is not
-- done in Lua. Each threshold gets a StatusBar whose range is exactly
-- (value - 1, value), and the count is pushed into it with SetValue - a
-- sanctioned sink for a secret. The C layer does the arithmetic and the
-- overlay snaps from empty to full as the count crosses the threshold.
--
-- WITH SEVERAL THRESHOLDS, EVERY CROSSED OVERLAY IS FULL AT ONCE. "The
-- highest crossed one wins" therefore cannot be an `if` - there is nothing
-- to branch on. It has to be draw order: overlay i is parented to overlay
-- i-1, a child always renders above its parent, and the list is sorted
-- ascending, so the highest crossed threshold paints last and covers the
-- rest. Read off EllesmereUICdmBuffBars.lua:1995-2103; the whole trick is
-- theirs and it is the only legal way to do this on 12.x.
--
-- Created on demand rather than up front: most bars have no thresholds at
-- all, and a StatusBar per cell per threshold is real memory on a 24-cell
-- bar that will never use one.
---------------------------------------------------------------------------
local function EnsureThreshold(aura, index)
    local pool = aura.thresholds
    if pool[index] then return pool[index] end

    -- Parent is the PREVIOUS overlay, which is what puts a higher threshold
    -- above a lower one. The first sits on the fill itself.
    local overlay = CreateFrame("StatusBar", nil, pool[index - 1] or aura.fill)
    overlay:SetFrameLevel(aura.fill:GetFrameLevel() + 2)
    overlay:SetMinMaxValues(0, 1)
    overlay:SetValue(0)
    overlay:Hide()
    pool[index] = overlay
    return overlay
end

-- Blizzard's charge record for a spell, or nil when there is none to be had.
-- pcall because the accessor is absent on some builds and raises on others
-- rather than returning nothing.
local function ChargeInfo(spellID)
    local get = C_Spell and C_Spell.GetSpellCharges
    if not (get and ns.CanCompute(spellID)) then return nil end

    local ok, charges = pcall(get, spellID)
    if not (ok and type(charges) == "table") then return nil end
    return charges
end

-- How many charges a spell has AT MOST, or nil for the ordinary one-charge
-- case. The readable half of the record: the maximum is a property of the
-- spell and stays plain while the live count does not.
local function MaxOf(charges)
    local most = charges and charges.maxCharges
    if not ns.CanCompute(most) or type(most) ~= "number" then return nil end
    if most <= 1 then return nil end
    return math.floor(most + 0.5)
end

local function MaxCharges(spellID)
    return MaxOf(ChargeInfo(spellID))
end

-- HOW MANY CHARGES ARE LEFT, on a cell we draw ourselves.
--
-- Adopted icons get this from Blizzard's own ChargeCount frame. A drawn cell
-- had nothing, so the same charge spell showed a number on one bar and not on
-- the next - which is the "Charge Count fehlt" this exists to answer.
--
-- THE LIVE COUNT IS A SECRET VALUE IN COMBAT. It may not be compared, added
-- to or tested for truth. It may be PRINTED: SetFormattedText declares a
-- secret argument, the engine formats it, and no addon Lua ever sees the
-- number. Nothing here reads it - `show` is decided entirely from values that
-- are known to be plain, and the count itself only ever travels from the
-- accessor to the setter.
--
-- `isActive` is the clean signal that makes that possible: it stays readable
-- and is false only at full charges. At full, the answer IS the maximum and
-- no secret is touched at all. Read off EllesmereUICdmBuffBars.lua:4310-4340,
-- which does the same two-arm split for the same reason.
local function ApplyChargeCount(cell)
    local aura = cell.aura
    if not (aura and aura.charges) then return end

    local value, show = nil, false

    if aura.showCharges then
        local charges = ChargeInfo(cell.spellID)
        local most = charges and MaxOf(charges)
        if charges and most then
            local recharging = charges.isActive
            if not ns.CanCompute(recharging) then
                -- Unreadable: show nothing rather than freeze yesterday's
                -- number on screen. A stale count is worse than none, because
                -- it looks exactly like a working one.
                show = false
            elseif not recharging then
                value, show = most, true
            elseif ns.CanDisplay(charges.currentCharges) then
                value, show = charges.currentCharges, true
            end
        end
    end

    -- pcall around the one call that takes the secret: a build where the
    -- setter has not declared that argument raises, and it would raise inside
    -- a render pass that has a whole screen still to draw.
    if show and pcall(aura.charges.SetFormattedText, aura.charges, "%d", value) then
        aura.charges:Show()
    else
        aura.charges:SetText("")
        aura.charges:Hide()
    end
end

-- The lines between charges. Three charges give two lines, at a third and
-- two thirds - the boundaries, not the charges, which is why it is N-1.
--
-- Drawn across the fill FRAME rather than its texture: these divisions belong
-- to the bar's whole length and must not move with the clock. That is exactly
-- the opposite of the spark, which is anchored to the texture for the same
-- reason in reverse.
local function ApplyChargeMarks(cell)
    local aura = cell.aura
    if not (aura and aura.fill) then return end

    local wanted = 0
    if aura.chargeMarks then
        wanted = ns.Bars:ChargeDivisions(MaxCharges(cell.spellID))
    end
    if wanted == 0 and #aura.marks == 0 then return end

    local colour = aura.chargeMarkColor or { 0, 0, 0 }
    -- A division runs ACROSS the bar, so which axis it spans depends on which
    -- way the bar runs. On a vertical fill the old code drew vertical lines
    -- down a vertical bar - three lines parallel to the fill instead of across
    -- it, which divides nothing.
    local vertical = aura.fill:GetOrientation() == "VERTICAL"
    local span = vertical and aura.fill:GetHeight() or aura.fill:GetWidth()

    for index = 1, wanted do
        local mark = aura.marks[index]
        if not mark then
            mark = aura.fill:CreateTexture(nil, "OVERLAY")
            aura.marks[index] = mark
        end
        mark:SetColorTexture(colour[1], colour[2], colour[3], 0.85)
        mark:ClearAllPoints()

        -- Measured from one fixed corner, so the divisions stay where they are
        -- whichever end the fill starts from.
        local at = math.floor(span * index / (wanted + 1) + 0.5)
        if vertical then
            mark:SetPoint("BOTTOMLEFT", aura.fill, "BOTTOMLEFT", 0, at)
            mark:SetPoint("BOTTOMRIGHT", aura.fill, "BOTTOMRIGHT", 0, at)
            mark:SetHeight(1)
        else
            mark:SetPoint("TOPLEFT", aura.fill, "TOPLEFT", at, 0)
            mark:SetPoint("BOTTOMLEFT", aura.fill, "BOTTOMLEFT", at, 0)
            mark:SetWidth(1)
        end
        mark:Show()
    end

    for index = wanted + 1, #aura.marks do aura.marks[index]:Hide() end
end

local function ApplySpark(cell)
    local aura = cell.aura
    if not (aura and aura.spark) then return end

    if not aura.showSpark then
        aura.spark:Hide()
        return
    end

    local texture = aura.fill:GetStatusBarTexture()
    if not texture then
        aura.spark:Hide()
        return
    end

    aura.spark:ClearAllPoints()
    -- Anchored to the END the fill grows towards, so it sits on the moving
    -- edge rather than on the fixed one - and on a vertical bar that end is a
    -- top or a bottom, not a left or a right. The spark also has to lie ACROSS
    -- the bar, so its 10 pixels are its width one way round and its height the
    -- other.
    --
    -- TO THE TWO CORNERS OF THAT EDGE, NOT TWICE TO ITS MIDDLE.
    --
    -- This used to anchor the spark's top AND its bottom to the texture's
    -- "RIGHT" - one point, which is the middle of the right edge. Both of the
    -- spark's own edges therefore landed on the same y and it was drawn ten
    -- pixels wide and NOTHING tall. It was never on screen, on any bar, in
    -- any direction: "die funktion spark geht auch nicht", and it was not the
    -- setting or the texture, it was a rectangle with no height.
    local orientation = aura.fill:GetOrientation()
    local reverse = aura.fill:GetReverseFill()
    if orientation == "VERTICAL" then
        aura.spark:SetHeight(10)
    else
        aura.spark:SetWidth(10)
    end

    local mineA, theirsA, mineB, theirsB =
        ns.Layout.SparkPoints(orientation, reverse)
    aura.spark:SetPoint(mineA, texture, theirsA, 0, 0)
    aura.spark:SetPoint(mineB, texture, theirsB, 0, 0)
    aura.spark:Show()
end

local function ApplyThresholds(cell)
    local aura = cell.aura
    if not (aura and aura.fill) then return end

    local list = aura.stackThresholds or {}
    if #list == 0 and #aura.thresholds == 0 then return end
    local texture = aura.fill:GetStatusBarTexture()

    for index, entry in ipairs(list) do
        local overlay = EnsureThreshold(aura, index)

        overlay:SetStatusBarTexture(aura.fillTexturePath or ns.WHITE)
        overlay:SetOrientation(aura.fill:GetOrientation())
        overlay:SetReverseFill(aura.fill:GetReverseFill())

        -- Anchored to the fill's TEXTURE, not to the fill: the threshold
        -- recolours the part of the bar that is actually filled, so the bar
        -- keeps its length from the clock and only changes colour. Re-anchored
        -- every pass because SetStatusBarTexture replaces the texture object.
        overlay:ClearAllPoints()
        if texture then
            overlay:SetAllPoints(texture)
        else
            overlay:SetAllPoints(aura.fill)
        end

        local colour = entry.color
        local tex = overlay:GetStatusBarTexture()
        if tex then
            tex:SetVertexColor(colour[1], colour[2], colour[3], entry.alpha or 1)
            tex:SetDrawLayer("ARTWORK", math.min(7, index))
        end

        -- THE COMPARISON, expressed as a range. Nothing in Lua reads it.
        overlay:SetMinMaxValues(entry.value - 1, entry.value)
        overlay:SetValue(0)
        overlay:Show()
    end

    for index = #list + 1, #aura.thresholds do
        aura.thresholds[index]:Hide()
    end
end

-- Push the current count into every live overlay. The value may be secret;
-- SetValue takes it untouched.
local function FeedThresholds(cell)
    local aura = cell.aura
    if not (aura and aura.thresholds[1]) then return end

    local item = cell.mirrorItem or cell.item
    if not item then return end

    local count = ns.CDM:ItemStacks(item)
    -- nil means the count is unknowable right now - leave the overlays where
    -- they are rather than reporting zero, which would flash the bar back to
    -- its base colour every time the cache is empty for a frame.
    if count == nil then return end

    for _, overlay in ipairs(aura.thresholds) do
        if overlay:IsShown() then pcall(overlay.SetValue, overlay, count) end
    end
end

local function RefreshFill(cell)
    local aura = cell.aura
    if not (aura and aura.fill) then return end

    local fill = aura.fill
    fill:SetScript("OnUpdate", nil)
    fill:SetMinMaxValues(0, 1)

    -- After the fill has its texture and orientation, because the overlays
    -- copy both and anchor to its texture object.
    ApplyThresholds(cell)
    ApplyChargeMarks(cell)
    ApplySpark(cell)

    -- MIRRORED FROM BLIZZARD'S OWN BAR.
    --
    -- The cell holds a spell the Cooldown Manager tracks, so Blizzard has a
    -- StatusBar for it with correct timing worked out inside the game. Its
    -- numbers are passed straight through - SetValue is a supported sink for
    -- a secret value, and nothing here inspects or computes with one. The
    -- approach is EllesmereUI's (EllesmereUICdmBuffBars.lua:4649, "reads
    -- min/max/value from Blizzard's Bar - zero duration computation"), and it
    -- is why our bar can look like OUR bar while keeping Blizzard's clock.
    local mirror = cell.mirrorItem and ns.CDM:BarFill(cell.mirrorItem)
    if mirror then
        -- Blizzard's own timer text, copied across. The first FontString on
        -- one of these StatusBars is the spell name and the SECOND is the
        -- timer - counted rather than named, because they have no names
        -- (EllesmereUICdmBuffBars.lua:3407).
        local timerText
        local seen = 0
        for _, region in ipairs({ mirror:GetRegions() }) do
            if region.GetObjectType and region:GetObjectType() == "FontString" then
                seen = seen + 1
                if seen == 2 then timerText = region break end
            end
        end
        aura.timer:SetShown(timerText ~= nil)

        local function Tick(self)
            local ok = pcall(function()
                self:SetMinMaxValues(mirror:GetMinMaxValues())
                self:SetValue(mirror:GetValue())
            end)
            if not ok then
                self:SetScript("OnUpdate", nil)
                return
            end

            if timerText then
                local got, text = pcall(timerText.GetText, timerText)
                if got then aura.timer:SetText(text or "") end
            end

            -- The stack count changes without the value changing at all - a
            -- Bone Shield charge falls off while the timer runs on - so it is
            -- read here rather than on a render pass.
            FeedThresholds(cell)

            -- Whether the buff is up is Blizzard's answer as well, and it
            -- changes without any render pass - so it is asked here rather
            -- than once, when the cell happened to be painted.
            local active = ns.CDM:ItemIsActive(cell.mirrorItem)
            if active ~= nil and active ~= cell.active then
                cell.active = active
                PaintAura(cell, active)
            end
        end

        Tick(fill)
        fill:SetScript("OnUpdate", Tick)
        return
    end

    aura.timer:Hide()

    -- Our own clock, for an aura Blizzard does not track.
    local grow = aura.grow
    local function Level(fraction)
        return grow and (1 - fraction) or fraction
    end

    if not (cell.active and fill:IsShown()) then
        fill:SetValue(Level(0))
        return
    end

    local ends, duration = cell.auraEnds, cell.auraDuration
    if not (ends and duration and duration > 0) then
        -- Up, but of unknown length - a proc nobody has timed yet, or one
        -- picked up by the resync after a reload. Full is the honest answer:
        -- an empty bar would say "about to run out", which is a lie.
        fill:SetValue(1)
        return
    end

    fill:SetValue(Level(1))
    FeedThresholds(cell)
    fill:SetScript("OnUpdate", function(self)
        local left = ends - GetTime()
        if left <= 0 then
            self:SetValue(Level(0))
            self:SetScript("OnUpdate", nil)
            -- A window the player declared has no event to end it. This is
            -- the only clock that knows, so it is the one that closes it.
            if cell.customEnds then Screen:StopCustomActive(cell) end
            return
        end
        self:SetValue(Level(left / duration))
        FeedThresholds(cell)
    end)
end

---------------------------------------------------------------------------
-- Which live Cooldown Manager frame stands for which spell
--
-- Rebuilt whenever the pools churn rather than searched per cell: a spec
-- change, a talent change and entering combat all reshuffle them.
---------------------------------------------------------------------------
local itemBySpell = {}
local itemViewer  = {}   -- which viewer an item came from: it decides its shape
local held = {}          -- every item we have touched, so it can be handed back

local function RebuildItemIndex()
    wipe(itemBySpell)
    wipe(itemViewer)

    -- INDEXED UNDER EVERY FORM OF THE SPELL, not just the one the frame is
    -- reporting this second. A talent that replaces a spell changes the ID
    -- the frame resolves to, and a cell that stored the old ID would simply
    -- stop finding it - the spell is right there on screen and the bar goes
    -- blank. Frostbolt becoming Glacial Spike is the everyday case.
    --
    -- The exact ID always wins; the other forms only fill gaps. Two spells of
    -- one family can be on screen at once (a base and its override both
    -- tracked), and without that rule whichever came out of the pool first
    -- would answer for both.
    local exact = {}

    for _, viewer in ipairs(ns.CDM.VIEWERS) do
        ns.CDM:ForEachItem(viewer.key, function(item)
            local spellID = ns.CDM:ItemSpellID(item)
            if not spellID then return end

            if not exact[spellID] then
                exact[spellID] = true
                itemBySpell[spellID] = item
            end
            for _, variant in ipairs(ns.CDM:VariantFamily(spellID)) do
                if not itemBySpell[variant] then itemBySpell[variant] = item end
            end
            itemViewer[item] = viewer
        end)
    end
end

-- Where an adopted frame goes inside a cell, and how big it is.
--
-- A frame from the buff-BAR viewer is already bar shaped, so it fills a bar
-- cell. Everything else is an icon and must stay SQUARE: stretching a spell
-- icon across the width of a bar is the one thing a tracking bar must never
-- look like, and it is what happens if a cell simply hands over its size.
--
-- The cell's OWN kind decides, not the bar's: one cell in a row of icons can
-- be a tracking bar, which is the whole point of the per-cell override.
-- Which of Blizzard's two templates a frame came out of. It decides how the
-- frame may be restyled AND whether we add anything of our own beside it, so
-- it is asked once and passed along rather than re-derived in three places.
local function ItemShape(item)
    local viewer = itemViewer[item]
    return (viewer and viewer.kind) or "icon"
end

local function ItemGeometry(cfg, cell, item, slot)
    local isBarShaped = ItemShape(item) == "bar"
    local width, height = slot.w, slot.h

    if slot.kind ~= "bar" or isBarShaped then
        return { "TOPLEFT", cell, "TOPLEFT", 0, 0 }, width, height, true
    end

    local placement = cfg.iconPlacement or "left"
    if placement == "hidden" then
        return nil, height, height, false
    end
    if placement == "right" then
        return { "TOPRIGHT", cell, "TOPRIGHT", 0, 0 }, height, height, true
    end
    return { "TOPLEFT", cell, "TOPLEFT", 0, 0 }, height, height, true
end

---------------------------------------------------------------------------
-- Bars
---------------------------------------------------------------------------
local barFrames = {}

local function CreateCell(bar, index)
    local cell = CreateFrame("Frame", nil, bar)
    cell.index = index

    -- Only ever seen while unlocked: in play an empty cell is nothing at all.
    cell.slot = cell:CreateTexture(nil, "BACKGROUND")
    cell.slot:SetAllPoints(cell)
    cell.slot:SetColorTexture(1, 1, 1, 0.05)
    cell.slot:Hide()

    cell.slotEdge = ns.CreateBorder(cell, 1, "BORDER")
    cell.slotEdge:SetColor(1, 1, 1, 0.18)
    cell.slotEdge:Hide()

    return cell
end

local function CreateBarFrame(index)
    local bar = CreateFrame("Frame", "ZwoelfStuffBar" .. index, UIParent)
    bar:SetFrameStrata("MEDIUM")
    bar:SetClampedToScreen(true)
    bar.cells = {}
    bar.index = index
    return bar
end

function Screen:BarFrame(index)
    return barFrames[index]
end

-- One cell's frame. Build mode puts a handle on exactly this, so what you
-- grab on screen is the thing that is actually drawn there.
function Screen:CellFrame(barIndex, cellIndex)
    local bar = barFrames[barIndex]
    return bar and bar.cells[cellIndex] or nil
end

function Screen:ApplyPosition(index)
    local cfg = ns.db.bars[index]
    local bar = barFrames[index]
    if not (cfg and bar) then return end

    bar:ClearAllPoints()

    -- Attached to another bar: the parent's FRAME is the anchor, so moving or
    -- resizing the parent carries this one along without a single line of
    -- follow-up code. Falls through to the screen if the parent has no frame
    -- yet, which happens while the list is still being built.
    if cfg.anchor then
        local _, parentIndex = ns.Bars:ByID(cfg.anchor.to)
        local parent = parentIndex and barFrames[parentIndex]
        if parent then
            bar:SetPoint(cfg.anchor.point, parent, cfg.anchor.relPoint,
                cfg.anchor.x or 0, cfg.anchor.y or 0)
            return
        end
    end

    bar:SetPoint(cfg.point or "CENTER", UIParent, cfg.relPoint or "CENTER",
        cfg.x or 0, cfg.y or 0)
end

-- Writes where the bar ACTUALLY is back into the config, as a centre offset
-- from the screen centre. Used when a bar is detached: its stored x/y are
-- from before it was attached, and dropping it somewhere it has not been for
-- an hour is the kind of surprise that makes people stop using a feature.
-- Written for whichever point the bar is PINNED by, which is no longer always
-- its centre: a bar pinned by its left edge grows to the right, and that is
-- the setting people mean by "grow direction".
function Screen:CapturePosition(index)
    local cfg = ns.db.bars[index]
    local bar = barFrames[index]
    if not (cfg and bar) then return end

    local pointX, pointY = PointOffset(bar, cfg.point or "CENTER")
    local screenX, screenY = UIParent:GetCenter()
    if not (pointX and screenX) then return end

    cfg.relPoint = "CENTER"
    cfg.x = math.floor(pointX - screenX + 0.5)
    cfg.y = math.floor(pointY - screenY + 0.5)
end

-- Where the bar's CENTRE is, as an offset from the screen centre. Snapping
-- works in centre terms whatever the bar is pinned by, so unlock mode needs
-- the translation in one place.
function Screen:CentreOffset(index)
    local bar = barFrames[index]
    if not bar then return nil end

    local centreX, centreY = bar:GetCenter()
    local screenX, screenY = UIParent:GetCenter()
    if not (centreX and screenX) then return nil end

    return centreX - screenX, centreY - screenY
end

---------------------------------------------------------------------------
-- The render pass
--
-- One function, run whenever anything could have changed. It claims what it
-- needs, and hands back everything it did not claim - which is what keeps a
-- deleted bar from leaving Blizzard's icons stranded in mid-air.
---------------------------------------------------------------------------
local claimedBy = {}     -- spellID -> "bar name" of whoever got it first

function Screen:Render()
    if not ns.db then return end

    RebuildItemIndex()
    wipe(claimedBy)

    -- The effect ticker walks a list that this pass rebuilds. A cell that
    -- stops being drawn has to stop being ticked, and "remember to
    -- unregister" is the kind of rule that survives one feature.
    ns.Effects.BeginPass()

    local claimedNow = {}

    -- Built ONCE per pass. Asking Auras for its catalogue per cell meant
    -- rebuilding the whole proc list - talent scan included - forty times for
    -- one spec change.
    local auraBySpell = {}
    if ns.Auras then
        for _, entry in ipairs(ns.Auras:Catalogue()) do
            auraBySpell[entry.spellID] = entry
        end
    end

    for index, cfg in ipairs(ns.db.bars) do
        local bar = barFrames[index]
        if not bar then
            bar = CreateBarFrame(index)
            barFrames[index] = bar
        end

        local _, _, spacing, lineSpacing = Metrics(cfg)
        local count = ns.Bars:CellCount(cfg)

        -- One call, and everything about the arrangement is decided: grid,
        -- staggered, arc, diagonal or puzzle, per-cell sizes included.
        local slots, box = ns.Layout.Build(cfg, count, spacing, lineSpacing)

        -- Auto text sizes follow the CELL, so a bar with one enlarged icon in
        -- it gets a bigger number on that one. Cached by height, because most
        -- bars have exactly one size and building the table per cell would be
        -- a table per cell per pass.
        -- Cached by height, because most cells share one. A cell wearing a
        -- look of its own is asked for separately and NOT cached: it is the
        -- rare case, and keying the cache by cell as well would cost every
        -- ordinary bar a table per cell to serve the one that is different.
        local styles = {}
        local function StyleFor(height, cellIndex)
            if ns.Bars:CellHasLook(cfg, cellIndex) then
                return ns.Bars:CellStyle(cfg, cellIndex, height)
            end
            local key = math.floor(height + 0.5)
            local style = styles[key]
            if not style then
                style = ns.Bars:Style(cfg, height)
                styles[key] = style
            end
            return style
        end

        -- Whether the rules let this bar be seen at all, and what it looks
        -- like when they do not. See Core/Visibility.lua.
        local factor = ns.Visibility:Factor(cfg)
        local visible = factor > 0 or self.unlocked

        bar:SetSize(box.width, box.height)
        self:ApplyPosition(index)
        bar:SetShown(visible)

        -- The bar's own opacity belongs HERE as well, not only on the adopted
        -- frames. Our own cells are this frame's children and an adopted one
        -- is not, so the two need it applied in two places - and while it was
        -- applied in only one, the Opacity slider moved half of a mixed bar
        -- and left the other half at full strength.
        bar:SetAlpha((cfg.alpha or 1) * (self.unlocked and 1 or factor))

        for cellIndex = 1, count do
            local cell = bar.cells[cellIndex]
            if not cell then
                cell = CreateCell(bar, cellIndex)
                bar.cells[cellIndex] = cell
            end

            local slot = slots[cellIndex]
            cell:SetSize(slot.w, slot.h)
            cell:ClearAllPoints()
            -- By its CENTRE, against the bar's centre. A corner is no use
            -- here: an arc has no corner to measure from, and a cell that is
            -- scaled up should grow around itself rather than shove the row.
            cell:SetPoint("CENTER", bar, "CENTER",
                slot.x - box.centreX, slot.y - box.centreY)
            cell:SetShown(not slot.hidden)

            if slot.hidden then
                self:BlankCell(cell)
            else
                self:PaintCell(bar, cell, cfg, slot, claimedNow, auraBySpell,
                    StyleFor(slot.h, cellIndex), factor)
            end
        end

        -- Cells left over from a smaller grid. The aura record has to go with
        -- them, or a hidden cell would still answer the glow that drives it.
        for cellIndex = count + 1, #bar.cells do
            local cell = bar.cells[cellIndex]
            cell:Hide()
            self:BlankCell(cell)
        end
    end

    -- Bars that no longer exist.
    for index = #ns.db.bars + 1, #barFrames do
        local bar = barFrames[index]
        if bar then
            for _, cell in ipairs(bar.cells) do
                if cell.item then
                    ns.CDM:Release(cell.item)
                    cell.item = nil
                end
            end
            bar:Hide()
        end
    end

    -- A second pass for attached bars. The first one runs in list order, so a
    -- bar anchored to one BELOW it in the list found no frame to hang on yet
    -- and fell back to the screen. Cheap, and it removes an ordering rule
    -- nobody would remember.
    for index, cfg in ipairs(ns.db.bars) do
        if cfg.anchor then self:ApplyPosition(index) end
    end

    self:ApplyTakeover(claimedNow)

    -- A moment later, because a rival addon reacts to the same events we do
    -- and asking straight away would only ever see our own anchor.
    if not self.rivalCheckQueued then
        self.rivalCheckQueued = true
        C_Timer.After(1, function()
            Screen.rivalCheckQueued = false
            ns.CDM:CheckForRivals()
            Screen:WarnIfInvisible()
        end)
    end

    if ns.EditMode and ns.EditMode.Refresh then ns.EditMode:Refresh() end
end

-- The spell's name next to an adopted icon in a bar-shaped cell.
--
-- Ours, on our own cell, because the name is not something Blizzard's icon
-- frame carries - and a bar cell holding nothing but a square icon in one
-- corner reads as broken rather than as deliberate.
function Screen:PaintCaption(cell, cfg, spellID, slot, iconWidth, style)
    local width = slot.w
    if slot.kind ~= "bar" or not style.spellName.show then
        if cell.caption then cell.caption:Hide() end
        return
    end

    if not cell.caption then
        local layer = CreateFrame("Frame", nil, cell)
        layer:SetAllPoints(cell)
        layer:SetFrameLevel(cell:GetFrameLevel() + 10)
        cell.caption = layer:CreateFontString(nil, "OVERLAY")
        cell.caption:SetJustifyH("LEFT")
        cell.caption:SetWordWrap(false)
    end

    local name = style.spellName
    local leftInset, rightInset = ns.Layout.LabelBand(cfg.iconPlacement or "left", iconWidth)
    PlaceLabel(cell.caption, cell, name, width, leftInset, rightInset)

    ns.Media.ApplyFont(cell.caption, name.font, name.size, name.outline, name.color)
    cell.caption:SetText(ns.SpellName(spellID) or "")
    cell.caption:Show()
end

-- A cell that is showing nothing at all: hidden by its own override, or empty.
function Screen:BlankCell(cell)
    if cell.item then
        ns.CDM:Release(cell.item)
        cell.item = nil
    end
    -- A mirrored frame is held at alpha 0 rather than pinned, so letting go of
    -- it is the same call - otherwise Blizzard's own bar stays invisible after
    -- the cell that borrowed its numbers is gone.
    if cell.mirrorItem then
        ns.CDM:Release(cell.mirrorItem)
        cell.mirrorItem = nil
    end
    if cell.aura then
        cell.aura:Hide()
        ClearCooldown(cell.aura.cd)
        -- Its OnUpdate as well, or a cell taken off the bar goes on running a
        -- countdown nobody can see, for ever.
        cell.aura.fill:SetScript("OnUpdate", nil)
        cell.aura.fill:SetValue(0)
        -- Same reason as the SetValue above: a blanked cell keeps its frames,
        -- and the overlays are only re-applied from RefreshFill - which a cell
        -- that stays blank never reaches. Left shown, they would go on being
        -- fed a stack count for a spell that is no longer here.
        for _, overlay in ipairs(cell.aura.thresholds) do overlay:Hide() end
        for _, mark in ipairs(cell.aura.marks) do mark:Hide() end
        cell.aura.spark:Hide()
        -- And the charge count, for the same reason: it is refreshed from its
        -- own event, which would go on writing a number for the spell that
        -- used to be here.
        cell.aura.charges:SetText("")
        cell.aura.charges:Hide()
    end
    if cell.caption then cell.caption:Hide() end
    ns.Effects.Silence(cell)
    -- The clock's own state too. A cell that comes back into use later would
    -- otherwise start out claiming a buff is up, with a stale end time.
    cell.spellID, cell.auraEntry, cell.conflict = nil, nil, nil
    cell.active, cell.auraEnds, cell.auraDuration = nil, nil, nil
    -- A declared window belongs to the spell that was here, not to the cell.
    cell.customEnds = nil
end

-- One cell: adopt, draw, or leave empty.
function Screen:PaintCell(bar, cell, cfg, slot, claimedNow, auraBySpell, style, factor)
    local spellID = cfg.cells[cell.index]

    -- Whatever this cell held last time is handed back before anything else,
    -- or moving a spell would leave its old frame pinned to a dead cell.
    -- SameSpell, not equality: the frame we are holding may have transformed
    -- into another form of the same spell since the last pass, and dropping it
    -- for that reason is how a cell goes empty mid-fight.
    if cell.item and (not spellID
        or not ns.CDM:SameSpell(ns.CDM:ItemSpellID(cell.item), spellID)) then
        ns.CDM:Release(cell.item)
        cell.item = nil
    end

    -- A CELL IS REUSED FOR WHATEVER SPELL ENDS UP AT ITS INDEX, so everything
    -- remembered about the last one has to go with it. Two of those are state
    -- machines: the aura clock, and the effects' "was it ready a moment ago".
    -- Left behind, they made a swapped icon arrive lit up with the previous
    -- spell's sweep still running, and fire a ready-flash for a transition
    -- that belonged to a spell no longer on the bar.
    if cell.spellID ~= spellID then
        cell.active, cell.auraEnds, cell.auraDuration = nil, nil, nil
        cell.fxState = nil
        cell.mirrorItem = nil
        if cell.aura then
            ClearCooldown(cell.aura.cd)
            cell.aura.fill:SetScript("OnUpdate", nil)
            cell.aura.timer:SetText("")
        end
    end

    if not spellID then
        self:BlankCell(cell)
        return
    end

    cell.spellID = spellID

    local item = itemBySpell[spellID]

    -- A BAR-SHAPED CELL IS DRAWN, NEVER ADOPTED.
    --
    -- Blizzard's TrackedBar template is a whole bar: its own border, its own
    -- fill, its own two font strings. None of that is ours to restyle, and
    -- that is why the thing on screen never matched the preview and why a
    -- border stayed on a bar whose thickness was set to zero. There is no
    -- amount of stripping that turns somebody else's template into your
    -- design.
    --
    -- So the frame is kept alive as a DATA SOURCE at alpha 0, and the bar is
    -- drawn here with its numbers taken straight from Blizzard's StatusBar.
    -- This is EllesmereUI's approach - "reads min/max/value from Blizzard's
    -- Bar, zero duration computation" - and the reason its tracking bars look
    -- like its own work rather than like a reskin.
    --
    -- ICONS ARE STILL ADOPTED. There the frame IS the art: Blizzard's icon is
    -- the correct one for the talent you have, its swipe and charges are
    -- already right, and drawing our own would mean reading aura data, which
    -- this patch forbids. The two halves are different problems.
    local barCell = slot.kind == "bar"

    if item and not claimedNow[item] and not barCell then
        -- A Cooldown Manager spell: adopt Blizzard's frame.
        claimedNow[item] = true
        claimedBy[spellID] = cfg.name or ("Bar " .. bar.index)
        held[item] = true
        cell.item = item
        cell.auraEntry, cell.conflict = nil, nil
        -- Idempotent, so calling it on every pass costs one table read. Only
        -- frames a cell actually holds are hooked, which bounds it by the
        -- number of cells rather than by everything the game is tracking.
        ns.CDM:HookPandemic(item)

        -- A CUSTOM ACTIVE WINDOW DRAWS OVER THE ADOPTED ICON.
        --
        -- Blizzard's frame stays exactly as it is - not its alpha, not its
        -- cooldown, not its parent - and our overlay is raised above it for
        -- as long as the window the player declared is open. That is the
        -- reference's arrangement (EllesmereUICdmFakeActive.lua:6-9), and it
        -- is the only one that cannot leave Blizzard's display damaged if we
        -- are unloaded mid-window.
        --
        -- Drawn HERE rather than where the window starts, so there is one
        -- renderer for the overlay and it cannot drift from the drawn cells.
        if cell.customEnds and cell.customEnds > GetTime() then
            local overlay = BuildAuraVisual(cell)
            overlay:Show()
            LayoutAuraVisual(overlay, cfg, slot)
            StyleAuraVisual(overlay, style, slot.kind == "bar")
            overlay:SetFrameLevel(item:GetFrameLevel() + 2)
            overlay.icon:SetTexture(ns.SpellTexture(spellID))
            overlay.label:SetText(ns.SpellName(spellID) or "")
            cell.inactiveAlpha = style.inactiveAlpha
            cell.inactiveDesaturate = style.inactiveDesaturate
            PaintAura(cell, true)
            RefreshFill(cell)
            ApplyChargeCount(cell)
        elseif cell.aura then
            cell.aura:Hide()
        end

        local shape = ItemShape(item)
        local anchor, itemWidth, itemHeight, visible =
            ItemGeometry(cfg, cell, item, slot)

        if anchor then
            ns.CDM:Pin(item, anchor, itemWidth, itemHeight)
        end
        -- The visibility rule multiplies in HERE, not on the bar frame: an
        -- adopted icon is Blizzard's child and does not inherit our alpha.
        ns.CDM:SetAlpha(item,
            visible and (cfg.alpha or 1) * (self.unlocked and 1 or factor) or 0)
        ns.CDM:Skin(item, style, shape)

        -- A buff-bar frame writes its own name and timer along the bar. Ours
        -- on top of that is the same word twice, and it was being pushed off
        -- the right-hand edge into an ellipsis because the "icon" it makes
        -- room for is the whole frame.
        if shape == "bar" then
            if cell.caption then cell.caption:Hide() end
        else
            self:PaintCaption(cell, cfg, spellID, slot,
                visible and itemWidth or 0, style)
        end

        -- The flash, the edge and the nag. Greying is a vertex colour on
        -- Blizzard's own icon texture - the same kind of decoration change
        -- the skin pass already makes, and never a Hide.
        ns.Effects.Track(cell, cfg, spellID, ns.CDM:ItemCooldownID(item), false,
            function(value)
                if item.Icon then
                    pcall(item.Icon.SetVertexColor, item.Icon, value, value, value)
                end
            end)
        return
    end

    cell.item = nil
    cell.mirrorItem = nil

    if item and not claimedNow[item] then
        -- A bar-shaped cell whose spell Blizzard tracks: claim the frame so
        -- nothing else takes it, keep it alive and INVISIBLE, and drive our
        -- own bar off it. Not pinned: an invisible frame does not need to be
        -- anywhere, and leaving Blizzard's layout alone is one less fight.
        claimedNow[item] = true
        claimedBy[spellID] = cfg.name or ("Bar " .. bar.index)
        held[item] = true
        cell.mirrorItem = item
        cell.conflict = nil
        ns.CDM:HookPandemic(item)
        ns.CDM:SetAlpha(item, 0)

        local active = ns.CDM:ItemIsActive(item)
        if active ~= nil then cell.active = active end
    else
        -- The same spell on two bars. One frame cannot be in two places, so
        -- the first bar keeps it and this cell is drawn dimmer rather than
        -- empty - an empty cell where you know you put something reads as a
        -- fault.
        cell.conflict = item and claimedBy[spellID] or nil
    end

    -- An aura proc, or a cooldown whose frame is not pooled right now. It
    -- carries its own name, so the caption for adopted icons stands down.
    if cell.caption then cell.caption:Hide() end

    local aura = BuildAuraVisual(cell)
    aura:Show()
    LayoutAuraVisual(aura, cfg, slot)
    StyleAuraVisual(aura, style, slot.kind == "bar")

    -- Carried on the cell, because the glow events repaint it later and have
    -- no style table in hand.
    cell.inactiveAlpha = style.inactiveAlpha
    cell.inactiveDesaturate = style.inactiveDesaturate

    aura.icon:SetTexture(ns.SpellTexture(spellID))
    aura.label:SetText(ns.SpellName(spellID) or "")

    -- Looked up per render rather than cached on the cell: a respec changes
    -- which procs exist, and a stale record would drive a clock off a glow
    -- this build can no longer raise.
    cell.auraEntry = auraBySpell[spellID]
    PaintAura(cell, cell.active and true or false)
    RefreshFill(cell)
    ApplyChargeCount(cell)

    -- Ours, so the effects get a real remaining time out of the clock we run
    -- ourselves. Adopted frames deliberately do not - see Core/Effects.lua.
    ns.Effects.Track(cell, cfg, spellID, nil, true, function(value)
        aura.icon:SetVertexColor(value, value, value)
    end)
end

-- Everything the user did not place. Alpha only - see the header.
function Screen:ApplyTakeover(claimedNow)
    local takeover = ns.db.takeOverCDM ~= false

    ns.CDM:ForEachItemEverywhere(function(item)
        if claimedNow[item] then return end

        if takeover then
            held[item] = true
            ns.CDM:SetAlpha(item, 0)
        elseif held[item] then
            ns.CDM:Release(item)
            held[item] = nil
        end
    end)
end

-- "My bar is empty" and "the Cooldown Manager is off" look identical from the
-- outside. An adopted icon is still Blizzard's child, so a viewer switched
-- off in Blizzard's own Edit Mode takes our icons with it - everything on our
-- side is correct and nothing is on screen. Said once, and only when a cell
-- actually wanted one of those frames.
function Screen:WarnIfInvisible()
    if self.invisibleReported then return end

    local hidden = ns.CDM:HiddenViewers()
    if not hidden then return end

    local wanted = false
    for _, cfg in ipairs(ns.db.bars) do
        for _, spellID in pairs(cfg.cells) do
            if itemBySpell[spellID] then wanted = true break end
        end
        if wanted then break end
    end
    if not wanted then return end

    self.invisibleReported = true
    ns.Print("|cffff4040These Cooldown Manager viewers are switched off:|r " .. hidden)
    ns.Print("Your icons ARE on the bar - they are Blizzard's frames, and a "
        .. "switched-off viewer hides its own children. Turn it back on in "
        .. "Blizzard's Edit Mode (Escape, Edit Mode, Cooldown Manager).")
end

-- Hands every frame back and lets Blizzard have its display again. Used when
-- the takeover is switched off, and on the way out.
function Screen:ReleaseAll()
    for item in pairs(held) do
        ns.CDM:Release(item)
    end
    wipe(held)
end

-- The charge counts on the cells we draw, without a render pass.
--
-- Its own entry point because charges change several times a fight, and a
-- full Render walks every bar, every cell and every adopted frame to answer a
-- question about one font string.
--
-- Adopted icons are deliberately not touched: their number is Blizzard's own
-- ChargeCount frame and the game keeps it correct without us.
function Screen:RefreshCharges()
    for _, bar in ipairs(barFrames) do
        for _, cell in ipairs(bar.cells) do
            if cell.aura and cell.aura:IsShown() then
                ApplyChargeCount(cell)
            end
        end
    end
end

---------------------------------------------------------------------------
-- The clock for aura cells
--
-- Driven by the glow on the ability the aura empowers - the only signal that
-- is readable on 12.0. On 12.1 the same cell gets its timing from the aura
-- itself; that route is prepared in Core/Auras.lua and lands here as a
-- different entry.route.
---------------------------------------------------------------------------
local function ForEachAuraCell(fn)
    for index, bar in ipairs(barFrames) do
        local cfg = ns.db.bars[index]
        if cfg then
            for _, cell in ipairs(bar.cells) do
                if cell.auraEntry then fn(cell, cell.auraEntry, cfg) end
            end
        end
    end
end

function Screen:StartAura(parentSpellID)
    ForEachAuraCell(function(cell, entry)
        if entry.parent ~= parentSpellID then return end
        cell.active = true
        local duration = entry.duration or 0
        if duration > 0 then
            cell.auraEnds, cell.auraDuration = GetTime() + duration, duration
            cell.aura.cd:SetCooldown(GetTime(), duration)
            -- The effect ticker has no clock of its own; this is the only
            -- place that knows when the thing it is watching runs out.
            ns.Effects.NoteAuraEnd(cell, cell.auraEnds)
        else
            cell.auraEnds, cell.auraDuration = nil, nil
            ClearCooldown(cell.aura.cd)
            ns.Effects.NoteAuraEnd(cell, nil)
        end
        PaintAura(cell, true)
        RefreshFill(cell)
    end)
end

---------------------------------------------------------------------------
-- Custom active states: a window the player declared
--
-- The cell already holds this spell and is usually showing Blizzard's own
-- icon for it, with a cooldown sweep and nothing else. For the length of the
-- window we put OUR OWN overlay on top of that icon - our swipe, our fill,
-- our timer - and then take it away again.
--
-- THE ADOPTED FRAME IS NEVER TOUCHED. Not its alpha, not its cooldown, not
-- its parent. It sits underneath, covered while we are active, exactly as it
-- was; the reference is explicit that this is the only safe arrangement
-- (EllesmereUICdmFakeActive.lua:6-9) and it is also the only one that cannot
-- leave Blizzard's display damaged if we are unloaded mid-window.
--
-- The overlay is raised by frame level rather than by hiding anything, so
-- nothing about the cell's own layout has to change to make room for it.
---------------------------------------------------------------------------
local function ForEachCellHolding(spellID, fn)
    for index, bar in ipairs(barFrames) do
        local cfg = ns.db.bars[index]
        if cfg then
            for _, cell in ipairs(bar.cells) do
                -- NOT `held`: that name belongs to the module-level set of
                -- frames we have borrowed, and shadowing it here would read
                -- like the wrong thing to the next person in this file.
                local inCell = cfg.cells and cfg.cells[cell.index]
                if inCell and ns.CDM:SameSpell(inCell, spellID) then fn(cell, cfg) end
            end
        end
    end
end

function Screen:StartCustomActive(spellID, seconds)
    if not (ns.db and ns.db.bars) then return end

    local touched = false

    ForEachCellHolding(spellID, function(cell)
        -- A cell already driven by a real aura is left alone: Blizzard's own
        -- clock beats a number somebody typed, every time.
        if cell.auraEntry or cell.mirrorItem then return end

        local now = GetTime()
        cell.customEnds = now + seconds
        cell.active = true
        cell.auraEnds, cell.auraDuration = cell.customEnds, seconds
        if cell.aura then cell.aura.cd:SetCooldown(now, seconds) end
        ns.Effects.NoteAuraEnd(cell, cell.customEnds)
        touched = true
    end)

    -- The overlay itself is drawn by the render pass, so pressing the button
    -- only has to say that the window is open. One repaint per press.
    if touched then self:Render() end
end

-- Called when the window runs out. Separate from StopAura because there is no
-- event behind it: the fill's own clock notices and calls this.
function Screen:StopCustomActive(cell)
    if not cell.customEnds then return end
    cell.customEnds = nil
    cell.active = false
    cell.auraEnds, cell.auraDuration = nil, nil
    ns.Effects.NoteAuraEnd(cell, nil)
    ClearCooldown(cell.aura and cell.aura.cd)
    PaintAura(cell, false)

    -- The overlay goes away and leaves Blizzard's icon exactly as it was,
    -- because it was never altered.
    if cell.item and cell.aura then cell.aura:Hide() end
    RefreshFill(cell)
end

function Screen:StopAura(parentSpellID)
    ForEachAuraCell(function(cell, entry)
        if entry.parent ~= parentSpellID then return end
        cell.active = false
        cell.auraEnds, cell.auraDuration = nil, nil
        PaintAura(cell, false)
        RefreshFill(cell)
    end)
end

-- After a reload the glow may already be up, and no event will announce it
-- again. IsSpellOverlayed is a plain boolean and never touches aura data.
function Screen:ResyncAuras()
    local isOverlayed = C_SpellActivationOverlay
        and C_SpellActivationOverlay.IsSpellOverlayed
    if not isOverlayed then return end

    ForEachAuraCell(function(cell, entry)
        local ok, active = pcall(isOverlayed, entry.parent)
        cell.active = (ok and active) and true or false
        -- No end time: the glow was already up when we looked, so nobody
        -- knows when it started. RefreshFill shows a full bar rather than
        -- inventing a countdown.
        cell.auraEnds, cell.auraDuration = nil, nil
        PaintAura(cell, cell.active)
        RefreshFill(cell)
    end)
end

---------------------------------------------------------------------------
-- Every cell, and which of the two mechanisms is drawing it
--
-- The skin report covers adopted frames. It cannot cover the cells we draw
-- ourselves, and a bar is usually a mix - so "the icons are different sizes"
-- was being answered with only half the icons on the table.
---------------------------------------------------------------------------
function Screen:DumpCells()
    ns.Print("|cffffd100--- every cell, both kinds ---|r")

    for index, cfg in ipairs(ns.db.bars) do
        local bar = barFrames[index]
        if bar then
            local width, height = Metrics(cfg)
            ns.Print(string.format("|cffffd100%d. %s|r  %dx%d, cells asked for "
                .. "%.0fx%.0f", index, cfg.name or "?", cfg.rows or 1,
                cfg.columns or 1, width, height))

            for cellIndex, cell in ipairs(bar.cells) do
                if cell:IsShown() and cell.spellID then
                    local drawn = cell.item == nil
                    local w, h = cell:GetWidth(), cell:GetHeight()

                    -- Screen pixels. A frame at scale 1.2 reports 36 and
                    -- draws 43, and reporting the 36 is how a row of icons
                    -- was declared even while three of them were not.
                    local cellScale = cell:GetEffectiveScale() or 1
                    local shown = cell.item or (drawn and cell.aura) or cell
                    local shownScale = shown:GetEffectiveScale() or cellScale

                    ns.Print(string.format("   %d %s |cff888888%d|r  cell "
                        .. "%.0fx%.0f px  drawn %.0fx%.0f px  %s",
                        cellIndex, ns.SpellName(cell.spellID) or "?",
                        cell.spellID, w * cellScale, h * cellScale,
                        (shown:GetWidth() or 0) * shownScale,
                        (shown:GetHeight() or 0) * shownScale,
                        drawn and "|cffffd100ours|r" or "|cff40ff40adopted|r"))
                end
            end
        end
    end

    ns.Print("|cff888888ours = we draw it (an aura proc, or a cooldown whose "
        .. "frame is not pooled right now). Those are dimmed while inactive - "
        .. "that is on purpose, not a size.|r")
end

---------------------------------------------------------------------------
-- Unlocked look
--
-- The grid itself becomes visible, so an empty bar is still something you can
-- see and grab. Nothing here changes what is saved.
---------------------------------------------------------------------------
function Screen:SetUnlocked(unlocked)
    self.unlocked = unlocked and true or false

    -- A bar hidden by its own rule - "only in a raid" - has to come back while
    -- you are arranging it, or the rule you just wrote makes the thing you are
    -- editing disappear. Everything is drawn at full strength while unlocked
    -- and goes back to its rule on the next pass.
    self:Render()

    for index, bar in ipairs(barFrames) do
        local cfg = ns.db.bars[index]
        if cfg then
            -- A disabled bar is shown while unlocked, or it could never be
            -- found again to switch back on.
            bar:SetShown(unlocked or cfg.enabled ~= false)
            for _, cell in ipairs(bar.cells) do
                cell.slot:SetShown(unlocked and cell:IsShown())
                cell.slotEdge:SetShown(unlocked and cell:IsShown())
            end
        end
    end
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
events:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
-- A charge spent or regained. Event-driven rather than polled, like
-- everything else here: the number is wrong for exactly as long as it takes
-- this to arrive, which is no time at all.
events:RegisterEvent("SPELL_UPDATE_CHARGES")

events:SetScript("OnEvent", function(_, event, spellID)
    if event == "PLAYER_ENTERING_WORLD" then
        Screen:Render()
        Screen:ResyncAuras()
        return
    end

    -- Before the spell ID check below: this one carries no payload at all,
    -- and CanCompute(nil) is false, so it would be dropped there.
    if event == "SPELL_UPDATE_CHARGES" then
        Screen:RefreshCharges()
        return
    end

    -- Computing on a secret value throws; these carry plain IDs, but the
    -- check costs nothing and the alternative is a broken event handler.
    if not ns.CanCompute(spellID) then return end

    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        Screen:StartAura(spellID)
    else
        Screen:StopAura(spellID)
    end
end)

function Screen:Start()
    ns.Bars:OnChanged(function() Screen:Render() end)
    ns.CDM:OnChanged(function() Screen:Render() end)

    -- Combat, a zone change, a group forming: everything that can change the
    -- answer to "should this bar be on screen". Event-driven, never polled.
    ns.Visibility:Start()

    -- Which spells these bars hold, before anything is drawn with them.
    ns.Bars:BindSpec()

    ns.Visibility:OnChanged(function()
        -- A spec change is one of the events that arrives here, and it changes
        -- WHICH SPELLS every bar holds. The cached answer to "who is playing"
        -- goes first: BindSpec compares against it, so leaving it in place
        -- would have it compare the new spec against itself and do nothing.
        ns.ForgetSpecKey()
        if ns.Bars:BindSpec() and ns.Options and ns.Options.Refresh then
            ns.Options:Refresh()
        end
        Screen:Render()
    end)

    -- Media arrives late: an addon loading after this one registers its fonts
    -- and textures when IT is ready. Without this, a bar set to a texture
    -- from a slower addon would sit on the fallback until the next reload.
    ns.Media.OnChanged(function() Screen:Render() end)

    self:Render()
    self:ResyncAuras()
end
