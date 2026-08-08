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

function Layout.FillDirection(value)
    for _, entry in ipairs(ns.FILL_DIRECTIONS) do
        if entry.value == value then return entry end
    end
    return ns.FILL_DIRECTIONS[1]
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
