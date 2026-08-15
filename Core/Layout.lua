---------------------------------------------------------------------------
-- Layout - the arithmetic behind what you see, kept away from the frames.
--
-- Pure geometry. Nothing in this file creates a frame, reads the game or
-- knows what a spell is: it takes numbers and words and hands back numbers
-- and words. That is what makes it testable at a desk, and it is why the
-- rules that were WRONG ON SCREEN and correct-looking in the source - the
-- spark with no height, the label anchored from the wrong edge - are worked
-- out here rather than inside whichever renderer needed them that week.
--
-- WHAT LEFT, in 4.83.0.
--
-- Two thirds of this file was one closed cluster: Build, the cell sizes, the
-- grid and stagger slots, the per-cell nudges and the puzzle's own raster -
-- "cell 7 of this bar sits HERE and is THIS big". It answered for the
-- cooldown bars and for nothing else, and when they went nothing outside
-- this file could reach any of it. Not one function of it, from any door.
--
-- What stayed is what the rest of the addon actually measures with, and all
-- of it is entered from outside: the co-tank strips (StripCorner, StripSlot,
-- StripSize), the fill and gradient directions, HealthTint, the spark edge,
-- and the label band that CoTanks hangs its names in.
--
-- THE COORDINATE SYSTEM, for what remains.
--
-- Local to the frame, origin anywhere, +x right and +y UP - the same way WoW
-- reads a SetPoint offset, so no caller has to flip a sign. A slot comes back
-- as its CENTRE plus a size, because a thing that grows should grow around
-- itself rather than shove its neighbours.
---------------------------------------------------------------------------
local _, ns = ...

local Layout = {}
ns.Layout = Layout

-- `icon` is the design's own name for the mark that goes with the choice; the
-- menu draws it in front of the label. Every entry in the lists below picks a
-- SHAPE, and a shape shown is worth more than a shape described.
--
-- LAYOUTS, FLOWS and GROW_X were here too - Grid, Staggered, Puzzle, which
-- way a grid fills before it wraps, and which way it reads across. They chose
-- how a cooldown bar arranged its cells, and there is no such bar any more.

-- Which way a tracking bar's FILL runs. Same four marks as the reading
-- directions above, and deliberately the same words: a direction is a
-- direction, and two vocabularies for one idea is how a settings page starts
-- needing to be learned.
--
-- The pairs are what the renderer needs - a StatusBar has an orientation and
-- a reverse flag, and SetReverseFill alone only ever flips a horizontal bar.
-- Kept HERE, next to the names, so the mapping cannot drift from the list.
ns.FILL_DIRECTIONS = {
    { value = "right", text = "Left to right", icon = "dir-left-right",
      orientation = "HORIZONTAL", reverse = false },
    { value = "left",  text = "Right to left", icon = "dir-right-left",
      orientation = "HORIZONTAL", reverse = true },
    { value = "up",    text = "Bottom to top", icon = "dir-bottom-top",
      orientation = "VERTICAL",   reverse = false },
    { value = "down",  text = "Top to bottom", icon = "dir-top-bottom",
      orientation = "VERTICAL",   reverse = true },
}

-- THE OTHER AXIS, and it lives here so the two cannot be read apart.
--
-- The owner asked whether this and the four directions above are the same
-- setting twice, which is a fair question about a switch that was called
-- "Fill up" - that reads as a DIRECTION, sitting one row under a control
-- called Direction whose answers include "Bottom to top".
--
-- They are two axes of one motion and neither implies the other:
--
--   Direction is SPACE. Which end of the bar is nailed down, and therefore
--   which way the fill runs - left to right, right to left, bottom to top,
--   top to bottom.
--
--   This is TIME. Whether the bar is filling or emptying while the cooldown
--   runs. A bar can drain to the left or drain downwards; it can equally
--   fill to the left or fill downwards.
--
-- Named after the clock, with BOTH answers written out. The off state of a
-- switch has no name, and an unnamed state is one you have to work out - so
-- a switch was the wrong control for a question with two real answers.
ns.FILL_CLOCKS = {
    { value = false, text = "Drains away" },
    { value = true,  text = "Fills up" },
}

-- Takes the stored NAME and hands back the entry. It also takes an entry and
-- hands it straight back, and that second half is not politeness.
--
-- Bars:Style resolves this field once and stores the ENTRY, so half the code
-- base holds a table where the other half holds a string. Ask this function
-- for a table and the loop below compares a string against a table - false
-- every time, no error in Lua - and it returns "left to right" while looking
-- like it worked. That silent default is how the preview card spent 4.33.0
-- animating every bar horizontally no matter which arrow was picked.
--
-- A caller that already has the answer asking for the answer is not a
-- mistake worth punishing, so it is simply answered. What IS a mistake is a
-- wrong shape becoming a plausible default, and that cannot happen here now.
function Layout.FillDirection(value)
    if type(value) == "table" and value.orientation then return value end
    for _, entry in ipairs(ns.FILL_DIRECTIONS) do
        if entry.value == value then return entry end
    end
    return ns.FILL_DIRECTIONS[1]
end

---------------------------------------------------------------------------
-- Gradients
--
-- SetGradient(orientation, colourA, colourB) takes EXACTLY TWO COLOURS and
-- one of "HORIZONTAL" / "VERTICAL". There are no stops and there is no
-- diagonal, so the four directions people expect are two orientations and a
-- swap - which is what this table says and what GradientOrder returns.
--
-- Which end each colour lands on was READ OFF SHIPPING CODE, not assumed:
--   HORIZONTAL  A is LEFT, B is RIGHT
--               EllesmereUIQoL colour picker: SetGradient("HORIZONTAL",
--               white opaque, white transparent) draws the saturation ramp,
--               and white sits on the left of an HSV square.
--   VERTICAL    A is BOTTOM, B is TOP
--               the same picker's value ramp is SetGradient("VERTICAL",
--               black, transparent), and a second call there names its two
--               arguments `bot` and `top` in as many words.
--
-- Getting that backwards is invisible on a symmetric pair of colours and
-- upside down on every other one, which is why it is written here once.
ns.GRADIENT_DIRECTIONS = {
    { value = "right", text = "Left to right", icon = "dir-left-right",
      orientation = "HORIZONTAL", swap = false },
    { value = "left",  text = "Right to left", icon = "dir-right-left",
      orientation = "HORIZONTAL", swap = true },
    { value = "up",    text = "Bottom to top", icon = "dir-bottom-top",
      orientation = "VERTICAL",   swap = false },
    { value = "down",  text = "Top to bottom", icon = "dir-top-bottom",
      orientation = "VERTICAL",   swap = true },
}

-- The orientation, and whether the two colours change places.
--
-- Pure on purpose, like SnapAxis and SparkEdge: the whole of the "which way
-- round" question is four strings in and two values out, and that is testable
-- without a texture, a frame or a client.
function Layout.GradientOrder(value)
    for _, entry in ipairs(ns.GRADIENT_DIRECTIONS) do
        if entry.value == value then return entry.orientation, entry.swap end
    end
    local first = ns.GRADIENT_DIRECTIONS[1]
    return first.orientation, first.swap
end

---------------------------------------------------------------------------
-- Aura strips
--
-- Where the Nth icon of a strip sits, as two numbers. Pure for the usual
-- reason and for one extra: on this client the LIVE strip is laid out by
-- Blizzard's aura engine and only the TEST strip is laid out by us, so these
-- are the numbers that have to agree with the engine's own flow. A preview
-- that arranges its icons differently from the thing it previews is worse
-- than no preview, and the only way to keep the two honest is to be able to
-- check one of them without a client.
--
-- The offsets are measured FROM THE STRIP'S ANCHOR CORNER, and both axes run
-- away from it: a strip anchored bottom-left growing right puts icon 1 at
-- 0,0 and stacks any second line downwards.
---------------------------------------------------------------------------
-- A STRIP HANGS OFF THE ROW, IT DOES NOT SIT IN IT.
--
-- The setting names the corner of the ROW the strip attaches to. The strip's
-- own anchor is that corner flipped vertically, so a strip attached to the
-- row's bottom-left hangs its TOP-left there and grows downwards, away from
-- the health bar. Anchored corner-to-same-corner instead, twenty-two pixel
-- icons sit on top of a twenty-six pixel row and the bar is gone.
--
-- Pure, and tested, because "which corner is the other one" is a sentence
-- that is easy to write down wrong and impossible to spot in a screenshot
-- taken with one strip switched off.
function Layout.StripCorner(rowAnchor)
    rowAnchor = rowAnchor or "BOTTOMLEFT"
    local side = rowAnchor:find("RIGHT") and "RIGHT"
        or rowAnchor:find("LEFT") and "LEFT" or ""
    if rowAnchor:find("BOTTOM") then return "TOP" .. side end
    return "BOTTOM" .. side
end

-- The strip's own corner, not the row's: see StripCorner. Passing the row's
-- would send every overflow line back across the health bar.
function Layout.StripSlot(index, size, spacing, perRow, growth, anchor)
    perRow = math.max(1, math.floor(perRow or 1))
    size = size or 0
    spacing = spacing or 0

    local column = (index - 1) % perRow
    local line = math.floor((index - 1) / perRow)
    local step = size + spacing

    local dx = column * step
    if growth == "left" then dx = -dx end

    -- Extra lines stack AWAY from the row, which is whichever way the anchor
    -- is not. A strip hung under the bar that grew upwards on its second line
    -- would draw its overflow across the health bar.
    local dy = line * step
    if not (anchor and anchor:find("BOTTOM")) then dy = -dy end

    return dx, dy
end

-- How much room a strip of N icons takes. Used to keep the two strips on a
-- row from meeting in the middle, and to size the test strip's own frame.
function Layout.StripSize(count, size, spacing, perRow)
    if not count or count < 1 then return 0, 0 end
    perRow = math.max(1, math.floor(perRow or 1))
    size = size or 0
    spacing = spacing or 0

    local across = math.min(count, perRow)
    local lines = math.ceil(count / perRow)
    return across * size + (across - 1) * spacing,
           lines * size + (lines - 1) * spacing
end

-- Which edge of a fill its overlays hang off.
--
-- THE SAME QUESTION AS THE SPARK'S, and the same answer for the same reason:
-- the leading edge is the one that moves with the clock, so anything that
-- belongs to "the end of the health you have" has to hang off the TEXTURE
-- there rather than off a fixed side of the frame. Hard-coded to RIGHT, a
-- shield overlay on a right-to-left bar sits at the wrong end of the bar and
-- an absorb on a vertical one is a line across the middle.
--
-- Returns the edge and whether the strip runs vertically, which is what
-- decides whether the span is a width or a height.
function Layout.FillEdge(orientation, reverse)
    if orientation == "VERTICAL" then
        return reverse and "BOTTOM" or "TOP", true
    end
    return reverse and "LEFT" or "RIGHT", false
end

-- Green at full, through amber, to red. Two straight ramps rather than one
-- across all three, because a single interpolation from green to red passes
-- through grey-brown at the halfway point and reads as "something is wrong
-- with the addon" rather than "this tank is at half".
--
-- The fraction is only ever called with a number the caller has already
-- established it may compute on - see ns.CanCompute. Clamped here anyway,
-- because a health value above maximum is a real thing during an absorb.
function Layout.HealthTint(fraction, high, mid, low)
    fraction = math.max(0, math.min(1, fraction or 1))

    local from, to, t
    if fraction >= 0.5 then
        from, to, t = mid, high, (fraction - 0.5) * 2
    else
        from, to, t = low, mid, fraction * 2
    end

    return from[1] + (to[1] - from[1]) * t,
           from[2] + (to[2] - from[2]) * t,
           from[3] + (to[3] - from[3]) * t
end

ns.GROW_Y = {
    { value = "down", text = "Top to bottom", icon = "dir-top-bottom" },
    { value = "up",   text = "Bottom to top", icon = "dir-bottom-top" },
}

---------------------------------------------------------------------------
-- Anchor arithmetic, kept away from the frames
--
-- Both of the rules below were WRONG on screen and correct-looking in the
-- source, and neither could be seen without the game running. That is the
-- same shape as the snapping bug, and it gets the same answer: the naming is
-- worked out here, in functions that take strings and return strings, so
-- /zs test can say whether a spark has any height before anybody logs in.
---------------------------------------------------------------------------

-- Which end of the fill the spark rides: the one the fill GROWS TOWARDS, so
-- it sits on the moving edge and not on the fixed one. On a vertical bar that
-- end is a top or a bottom rather than a left or a right - four answers, and
-- any of them backwards parks the spark on the end that never moves, where it
-- reads as a stray line rather than as a setting gone wrong.
--
-- The spark hangs its own CENTRE on that point and is sized outright. It used
-- to hang by its top AND its bottom, twice from the texture's "RIGHT" - which
-- is the MIDDLE of that edge, so both of its own edges landed on one line and
-- it was drawn with no height at all. Never once visible, on any bar.
function Layout.SparkEdge(orientation, reverse)
    if orientation == "VERTICAL" then
        return reverse and "BOTTOM" or "TOP"
    end
    return reverse and "LEFT" or "RIGHT"
end

-- The gap the icon leaves on each side of a bar cell, for the spell name to
-- live in. One function, because the drawn cells and the adopted ones both
-- ask - and a name sitting five pixels differently depending on which
-- renderer drew it is the kind of difference nobody can name and everybody
-- sees.
function Layout.LabelBand(placement, iconWidth)
    iconWidth = iconWidth or 0
    if iconWidth <= 0 then return 5, 5 end
    if placement == "right" then return 5, iconWidth + 5 end
    return iconWidth + 5, 5
end

-- Which point a spell name hangs from, and which way it reads, for one of the
-- nine positions. Returns the point, the side the inset applies to (or nil
-- for the middle column), and the justification.
--
-- The middle column is why this is a function: "TOP" and "BOTTOM" are whole
-- points on their own, but the centre of the centre has no vertical part at
-- all, and the empty string is not a point. Building the name by
-- concatenation without that case gives SetPoint("") - an error, at layout
-- time, on every bar.
function Layout.LabelAnchor(anchor)
    anchor = anchor or "LEFT"

    local side = anchor:find("LEFT") and "LEFT"
        or anchor:find("RIGHT") and "RIGHT" or nil
    local vertical = Layout.LabelVertical(anchor)

    if side then
        return vertical .. side, side, side, vertical
    end
    return (vertical ~= "" and vertical or "CENTER"), nil, "CENTER", vertical
end

-- The vertical half of one of the nine positions, as a PREFIX. Empty for the
-- middle row, which is what makes "LEFT" and "RIGHT" come out of the same
-- concatenation as "TOPLEFT" and "BOTTOMRIGHT".
function Layout.LabelVertical(anchor)
    anchor = anchor or "LEFT"
    return anchor:find("TOP") and "TOP"
        or anchor:find("BOTTOM") and "BOTTOM" or ""
end

---------------------------------------------------------------------------
-- CLOSING THE GAPS a hidden cell leaves
--
-- Owner: "aber das nachrücken wäre noch gut, das die plätze automatisch
-- rücken, dann noch einstellungen wie die nachrücken können."
--
-- The hiding itself is Core/Effects.lua's state rule. This decides only WHICH
-- SLOT each surviving cell lands in, and it is pure arithmetic on purpose:
-- an off-by-one here does not raise an error, it puts the wrong icon in the
-- wrong square and looks like a working display.
--
-- TWO WAYS TO CLOSE, and they are different answers to the same question
-- rather than a better and a worse:
--
--   "all"   everything repacks from the first slot. The bar becomes as short
--           as it needs to be. Right for a row of cooldowns you read left to
--           right - what is left IS the list.
--   "line"  each row closes up within itself and the rows keep their places.
--           Right for a GRID, where "the second row is my defensives" is a
--           thing you know without reading, and repacking would move a
--           defensive up into the first row.
--
-- `hidden` is indexed by cell. Returns a table where place[cell] is the slot
-- that cell takes, or nil when it is not drawn, plus how many slots ended up
-- in use - so a caller that sizes itself can ask for a box that fits what is
-- actually drawn rather than what was declared.
---------------------------------------------------------------------------
function Layout.Compact(hidden, count, mode, perLine)
    local place, used = {}, 0
    count = math.max(0, count or 0)
    hidden = hidden or {}

    -- The whole feature switched off is the identity, and saying so here
    -- means no caller needs a branch around it.
    if mode ~= "all" and mode ~= "line" then
        for cell = 1, count do
            place[cell] = cell
        end
        return place, count
    end

    if mode == "all" then
        for cell = 1, count do
            if not hidden[cell] then
                used = used + 1
                place[cell] = used
            end
        end
        return place, used
    end

    -- "line". A line of one or less is every cell on its own line, which is
    -- the same as "all" and is answered rather than divided by.
    perLine = math.max(1, math.floor(perLine or 1))
    local lines = math.ceil(count / perLine)

    for line = 0, lines - 1 do
        local first = line * perLine
        local taken = 0
        for offset = 1, perLine do
            local cell = first + offset
            if cell <= count and not hidden[cell] then
                taken = taken + 1
                place[cell] = first + taken
            end
        end
        -- The LAST slot any line reached, not the sum: a half-empty first row
        -- still leaves the second row where it was, so the box has to cover
        -- up to the furthest slot used rather than to the count of survivors.
        if taken > 0 then used = math.max(used, first + taken) end
    end

    return place, used
end
