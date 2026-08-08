---------------------------------------------------------------------------
-- Layout - where every cell of a bar ends up.
--
-- Pure geometry. Nothing in this file creates a frame, reads the game or
-- knows what a spell is: it takes a bar's settings and answers "cell 7 sits
-- HERE and is THIS big". That is what makes an arrangement testable, and it
-- is why each arrangement below is one short function rather than a copy of
-- the render pass.
--
-- THE COORDINATE SYSTEM.
--
-- Local to the bar, origin anywhere, +x right and +y UP - the same way WoW
-- reads a SetPoint offset, so no renderer has to flip a sign. Every slot is
-- returned as its CENTRE plus a size. Centres, not corners, because a puzzle
-- and a mixed grid have no shared corner to measure from, and because a cell
-- that grows should grow around itself rather than shove its neighbours.
--
-- Screen.lua takes the bounding box over all slots, makes the bar frame that
-- size, and anchors each cell by its centre. So a bar is always exactly as
-- big as what it holds - which is what makes the unlock overlay, snapping and
-- attachment work for a hand-built layout exactly as well as for a row.
--
-- THE PUZZLE, AND WHY IT KEEPS ITS OWN TWO NUMBERS.
--
-- "free" ignores the lattice and puts each cell exactly where it was dragged.
-- Every other arrangement works a position out and then adds the cell's nudge
-- on top, so pulling one icon out of a neat row is a normal edit.
--
-- Those are two DIFFERENT quantities. A puzzle's numbers are a POSITION; a
-- lattice's are an OFFSET from a slot the lattice chose. They were once the
-- same pair of fields, and that was a real bug: entering the puzzle wrote
-- spread-out positions into x/y, and switching back to a grid read them as
-- nudges and scattered the grid - permanently, because nothing ever removed
-- them. So the puzzle has px/py of its own.
--
-- The gain is not only correctness. Because neither field is touched by the
-- other arrangement, you can move a bar into the puzzle, drag it about, go
-- back to a grid and return - and find the puzzle exactly as you left it.
---------------------------------------------------------------------------
local _, ns = ...

local Layout = {}
ns.Layout = Layout

local floor, max = math.floor, math.max

-- THREE, not five.
--
-- Arc and Diagonal were removed on 2026-08-07: the owner reported that they
-- threw errors and did not look good, and both were true enough that keeping
-- them was not worth the settings they cost. The geometry itself was correct
-- and tested - so if either ever comes back, the fault to look for is in the
-- panel around it, not in the arithmetic. A saved bar that still names one is
-- migrated onto Grid; see Bars:Migrate.
-- `icon` is the design's own name for the mark that goes with the choice; the
-- menu draws it in front of the label. Every entry in these four lists picks a
-- SHAPE, and a shape shown is worth more than a shape described - "Staggered"
-- and "Puzzle" are both just words until you have seen each one once.
ns.LAYOUTS = {
    { value = "grid",     text = "Grid",      icon = "layout-grid",
      note = "Rows and columns. The straight answer." },
    { value = "stagger",  text = "Staggered", icon = "layout-stagger",
      note = "Every other line pushed along by half a cell." },
    { value = "free",     text = "Puzzle",    icon = "layout-puzzle",
      note = "No rows, no columns. Every cell sits exactly where you dragged "
          .. "it, and you drag them in build mode." },
}

-- Which way a grid fills before it wraps.
ns.FLOWS = {
    { value = "rows",    text = "Fill rows first",    icon = "flow-rows" },
    { value = "columns", text = "Fill columns first", icon = "flow-columns" },
}

ns.GROW_X = {
    { value = "right", text = "Left to right", icon = "dir-left-right" },
    { value = "left",  text = "Right to left", icon = "dir-right-left" },
}

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

-- WHERE A PART-FULL PREVIEW FILL SITS.
--
-- Back, and worth saying why. A version ago this described a bar drawn at a
-- STATIC 70%, which was wrong three separate times: the bar read as shorter
-- than it is, and no amount of marking the rest of the run fixed that. So the
-- card drew a full bar, and could then show neither which way the fill runs
-- nor the backdrop behind it.
--
-- Now the preview MOVES. A bar that drains is at every fraction in turn, so
-- there is no single length to be wrong about - and the settings that a full
-- bar could not show are all visible again while it runs. The rule was never
-- the fault; the still picture was.
--
-- ONE anchor and both sizes, never two opposing anchors plus a size: those
-- two rules fight, and which of them wins is not worth having to remember.
--
-- leftPad and rightPad are the room the icon takes at either end (rightPad
-- negative, as an inset from the right edge); area and height are what is
-- left over for the bar itself. portion is how full it is right now.
function Layout.PreviewFill(direction, leftPad, rightPad, area, height, portion)
    portion = portion or 1

    if direction.orientation == "VERTICAL" then
        -- Downwards hangs from the TOP: the fill starts at the end it grows
        -- away from, which is the reverse flag read the same way the
        -- StatusBar reads it.
        local corner = direction.reverse and "TOPLEFT" or "BOTTOMLEFT"
        return corner, leftPad, area, math.max(1, height * portion)
    end

    if direction.reverse then
        return "TOPRIGHT", rightPad, math.max(1, area * portion), height
    end
    return "TOPLEFT", leftPad, math.max(1, area * portion), height
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

-- Which point of the bar stays put when the bar changes size. The lattice
-- grows around the centre by default, so a bar that gains a row spreads both
-- ways; pin it by an edge and it grows away from that edge instead. This is
-- the setting people mean by "grow direction", and it belongs on the frame
-- rather than in the arrangement - the arrangement decides reading order.
ns.PIVOTS = {
    { value = "CENTER",      text = "Centre" },
    { value = "TOPLEFT",     text = "Top left" },
    { value = "TOP",         text = "Top" },
    { value = "TOPRIGHT",    text = "Top right" },
    { value = "LEFT",        text = "Left" },
    { value = "RIGHT",       text = "Right" },
    { value = "BOTTOMLEFT",  text = "Bottom left" },
    { value = "BOTTOM",      text = "Bottom" },
    { value = "BOTTOMRIGHT", text = "Bottom right" },
}

---------------------------------------------------------------------------
-- Per-cell settings
--
-- Stored on the bar as cellOpts[index] and every field is optional, so a bar
-- nobody has touched carries no per-cell table at all. Read through here so
-- no caller has to test for the table AND the field.
---------------------------------------------------------------------------
function Layout.CellOpts(cfg, index)
    local all = cfg.cellOpts
    return all and all[index] or nil
end

-- The writable version: makes the table on demand. Only the editor calls it.
function Layout.EnsureCellOpts(cfg, index)
    cfg.cellOpts = cfg.cellOpts or {}
    cfg.cellOpts[index] = cfg.cellOpts[index] or {}
    return cfg.cellOpts[index]
end

-- Drops a per-cell table once it says nothing. A table of defaults is a table
-- that survives every reset and makes "why is this one different" unanswerable.
function Layout.TidyCellOpts(cfg, index)
    local opts = cfg.cellOpts and cfg.cellOpts[index]
    if not opts then return end

    -- A look table that has been emptied counts as nothing, so clearing the
    -- last override on a cell tidies the cell away with it.
    if opts.look and not next(opts.look) then opts.look = nil end

    local interesting = (opts.scale and opts.scale ~= 1)
        or (opts.x and opts.x ~= 0) or (opts.y and opts.y ~= 0)
        or (opts.px and opts.px ~= 0) or (opts.py and opts.py ~= 0)
        or opts.kind or opts.hidden or opts.look
    if not interesting then cfg.cellOpts[index] = nil end
end

---------------------------------------------------------------------------
-- The two numbers the editor writes
--
-- Which pair of fields a drag lands in depends on the arrangement, and that
-- is the whole point - see the header. Every caller goes through here, so no
-- editor has to know the rule and none of them can disagree about it.
---------------------------------------------------------------------------
function Layout.OffsetKeys(cfg)
    if (cfg.layout or "grid") == "free" then return "px", "py" end
    return "x", "y"
end

function Layout.GetOffset(cfg, index)
    local opts = Layout.CellOpts(cfg, index)
    if not opts then return 0, 0 end
    local keyX, keyY = Layout.OffsetKeys(cfg)
    return opts[keyX] or 0, opts[keyY] or 0
end

function Layout.SetOffset(cfg, index, x, y)
    local opts = Layout.EnsureCellOpts(cfg, index)
    local keyX, keyY = Layout.OffsetKeys(cfg)
    opts[keyX], opts[keyY] = x, y
    return opts
end

-- Is anything nudged off the lattice at all? Drives whether the way out of a
-- scattered bar is offered, so it is not a button that does nothing on the
-- ninety per cent of bars nobody has dragged.
function Layout.HasOffsets(cfg)
    if not cfg.cellOpts then return false end
    local keyX, keyY = Layout.OffsetKeys(cfg)

    for _, opts in pairs(cfg.cellOpts) do
        if (opts[keyX] and opts[keyX] ~= 0) or (opts[keyY] and opts[keyY] ~= 0) then
            return true
        end
    end
    return false
end

-- Puts every cell back on the lattice, for the CURRENT arrangement only. The
-- one-click answer to "I nudged things about and want the neat row back", and
-- it deliberately leaves the puzzle's own positions alone: straightening a
-- grid must not throw away a layout you built on the other side.
function Layout.ClearOffsets(cfg)
    if not cfg.cellOpts then return end
    local keyX, keyY = Layout.OffsetKeys(cfg)

    for index, opts in pairs(cfg.cellOpts) do
        opts[keyX], opts[keyY] = nil, nil
        Layout.TidyCellOpts(cfg, index)
    end
end

-- What one cell measures. kind can be overridden per cell, which is the whole
-- point of the puzzle: a tracking bar and three icons in one arrangement.
function Layout.CellSize(cfg, opts)
    local kind = (opts and opts.kind) or cfg.kind or "icon"

    local width, height
    if kind == "bar" then
        width  = cfg.barWidth or 200
        height = cfg.barHeight or 24
    else
        width  = cfg.iconSize or 40
        height = width
    end

    local scale = (cfg.scale or 1) * ((opts and opts.scale) or 1)
    return width * scale, height * scale, kind
end

---------------------------------------------------------------------------
-- The arrangements
--
-- Each one answers for a single index and returns the centre of its slot,
-- measured from the lattice origin. Per-cell nudges are added afterwards, in
-- one place, so every arrangement gets them for free.
---------------------------------------------------------------------------

-- Row and column of a cell, honouring which axis fills first and which way
-- each one reads. Four settings, one function, no case analysis anywhere else.
local function RowColumn(cfg, index, columns, rows)
    local row, column

    if (cfg.flow or "rows") == "columns" then
        row    = (index - 1) % rows
        column = floor((index - 1) / rows)
    else
        column = (index - 1) % columns
        row    = floor((index - 1) / columns)
    end

    if (cfg.growX or "right") == "left" then column = (columns - 1) - column end
    if (cfg.growY or "down") == "up"    then row    = (rows - 1) - row end

    return row, column
end

local function GridSlot(cfg, index, cellW, cellH, spacing, lineSpacing, columns, rows)
    local row, column = RowColumn(cfg, index, columns, rows)

    local x = column * (cellW + spacing) + cellW / 2
    local y = -(row * (cellH + lineSpacing)) - cellH / 2
    return x, y
end

local function StaggerSlot(cfg, index, cellW, cellH, spacing, lineSpacing, columns, rows)
    local row, column = RowColumn(cfg, index, columns, rows)
    local shift = (cfg.staggerOffset or 50) / 100

    local x = column * (cellW + spacing) + cellW / 2
    local y = -(row * (cellH + lineSpacing)) - cellH / 2

    -- The offset goes on the axis that WRAPS. Pushing rows sideways in a
    -- column-first grid would shear the thing nobody asked to shear.
    if (cfg.flow or "rows") == "columns" then
        if column % 2 == 1 then y = y - (cellH + lineSpacing) * shift end
    else
        if row % 2 == 1 then x = x + (cellW + spacing) * shift end
    end

    return x, y
end

---------------------------------------------------------------------------
-- The whole bar
--
-- Returns:
--   slots   [index] = { x, y, w, h, kind, hidden }  centres, local coords
--   box     { width, height, centreX, centreY }     what the frame must be
--
-- The box is measured over the cells as DRAWN, per-cell sizes included, so a
-- bar with one oversized icon in it is big enough to hold it. That matters
-- for more than looks: the unlock overlay, snapping and attaching one bar to
-- another all measure the frame.
---------------------------------------------------------------------------
-- THE GAPS BETWEEN CELLS, SCALED, in one place.
--
-- Layout.CellSize already applies the bar's scale to the CELLS. The gaps are
-- passed in, so whoever draws has to scale them too - and the screen did
-- while the preview card did not. A bar at 150% therefore drew correctly
-- sized cells separated by unscaled gaps in the editor, and its measured
-- height came out short by (rows-1) x lineSpacing x (scale-1) - which the
-- card's own fit-scale then divided, so the well was sized off the wrong
-- number as well.
--
-- NOT applied inside Build itself, which was the obvious-looking fix and is
-- wrong twice over: the screen already multiplies before it calls, so it
-- would double, and the model callers below want unscaled numbers.
--   Bars:Resized  works out where a cell WAS, in model terms, and draws
--                 nothing
--   the self test passes its own numbers to check the arithmetic
function Layout.Gaps(cfg)
    local scale = (cfg and cfg.scale) or 1
    return ((cfg and cfg.spacing) or 4) * scale,
           ((cfg and cfg.lineSpacing) or 4) * scale
end

function Layout.Build(cfg, count, spacing, lineSpacing)
    count = max(1, count or 1)
    spacing = spacing or 0
    lineSpacing = lineSpacing or 0

    local columns = max(1, cfg.columns or 1)
    local rows    = max(1, cfg.rows or 1)

    -- The lattice is spaced by the bar's OWN cell size, never by an individual
    -- cell's. A grid whose spacing followed whichever cell happened to be
    -- enlarged would re-flow every time you scaled one thing.
    local baseW, baseH = Layout.CellSize(cfg, nil)
    local kind = cfg.layout or "grid"

    local slots = {}
    local minX, maxX, minY, maxY

    for index = 1, count do
        local opts = Layout.CellOpts(cfg, index)
        local cellW, cellH, cellKind = Layout.CellSize(cfg, opts)

        local x, y
        if kind == "free" then
            -- The puzzle's own numbers ARE the position, and it reads nothing
            -- else. A cell nudged while it was in a grid must not arrive here
            -- carrying that nudge - see the header.
            x, y = (opts and opts.px) or 0, (opts and opts.py) or 0
        elseif kind == "stagger" then
            x, y = StaggerSlot(cfg, index, baseW, baseH, spacing, lineSpacing,
                columns, rows)
        else
            x, y = GridSlot(cfg, index, baseW, baseH, spacing, lineSpacing,
                columns, rows)
        end

        -- The nudge, on every arrangement that HAS a slot to nudge away from.
        -- The puzzle is not one of them: there the position above is already
        -- the answer, and adding the nudge would count it twice.
        if opts and kind ~= "free" then
            x = x + (opts.x or 0)
            y = y + (opts.y or 0)
        end

        local hidden = opts and opts.hidden or false
        slots[index] = {
            x = x, y = y, w = cellW, h = cellH, kind = cellKind, hidden = hidden,
        }

        -- A hidden cell is not part of the bar's extent. It would otherwise
        -- pad the frame out with nothing, and the overlay would show a bar
        -- reaching well past anything you can see.
        if not hidden then
            local left, right = x - cellW / 2, x + cellW / 2
            local bottom, top = y - cellH / 2, y + cellH / 2
            minX = minX and (left < minX and left or minX) or left
            maxX = maxX and (right > maxX and right or maxX) or right
            minY = minY and (bottom < minY and bottom or minY) or bottom
            maxY = maxY and (top > maxY and top or maxY) or top
        end
    end

    -- Everything hidden: the bar still needs a size, or it collapses to a
    -- point nobody can grab in unlock mode.
    if not minX then
        minX, maxX, minY, maxY = -baseW / 2, baseW / 2, -baseH / 2, baseH / 2
    end

    local box = {
        width   = max(1, maxX - minX),
        height  = max(1, maxY - minY),
        centreX = (minX + maxX) / 2,
        centreY = (minY + maxY) / 2,
    }

    return slots, box
end

---------------------------------------------------------------------------
-- Reading the settings back
---------------------------------------------------------------------------

-- Whether a given arrangement uses rows and columns at all. Used to hide the
-- controls that would do nothing rather than leave them there to be tried.
function Layout.UsesGrid(cfg)
    local kind = cfg.layout or "grid"
    return kind == "grid" or kind == "stagger"
end

function Layout.IsFree(cfg)
    return (cfg.layout or "grid") == "free"
end

-- How many cells an arrangement has. A lattice has rows x columns; a puzzle
-- has however many the user dragged in, and growing it is what the "add"
-- button does rather than a second pair of sliders.
function Layout.CellCount(cfg)
    if Layout.IsFree(cfg) then return max(1, cfg.freeCount or 6) end
    return max(1, (cfg.rows or 1) * (cfg.columns or 1))
end

-- Rounds a coordinate onto the puzzle raster. Zero means no raster, which is
-- what "off" has to mean here - the alternative is a snap of one pixel that
-- reads as broken.
function Layout.SnapToRaster(value, step)
    if not step or step <= 0 then return value end
    return floor(value / step + 0.5) * step
end

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
