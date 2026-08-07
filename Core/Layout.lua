---------------------------------------------------------------------------
-- Layout - where every cell of a bar ends up.
--
-- Pure geometry. Nothing in this file creates a frame, reads the game or
-- knows what a spell is: it takes a bar's settings and answers "cell 7 sits
-- HERE and is THIS big". That is what makes an arrangement testable, and it
-- is why the five arrangements below are five short functions rather than
-- five copies of the render pass.
--
-- THE COORDINATE SYSTEM.
--
-- Local to the bar, origin anywhere, +x right and +y UP - the same way WoW
-- reads a SetPoint offset, so no renderer has to flip a sign. Every slot is
-- returned as its CENTRE plus a size. Centres, not corners, because an arc
-- and a mixed grid have no shared corner to measure from, and because a cell
-- that grows should grow around itself rather than shove its neighbours.
--
-- Screen.lua takes the bounding box over all slots, makes the bar frame that
-- size, and anchors each cell by its centre. So a bar is always exactly as
-- big as what it holds - which is what makes the unlock overlay, snapping and
-- attachment work for a circle exactly as well as for a row.
--
-- THE PUZZLE.
--
-- "free" is not a special case bolted on: it is the arrangement that ignores
-- the lattice and uses only each cell's own offset. Every other arrangement
-- ADDS that offset on top of what it worked out, so nudging one icon out of a
-- neat row is the same edit as building a whole free-form layout. One rule,
-- and there is no line to cross between "a bar" and "a puzzle".
---------------------------------------------------------------------------
local _, ns = ...

local Layout = {}
ns.Layout = Layout

local cos, sin, rad, floor, max, abs = math.cos, math.sin, math.rad, math.floor, math.max, math.abs

ns.LAYOUTS = {
    { value = "grid",     text = "Grid",
      note = "Rows and columns. The straight answer." },
    { value = "stagger",  text = "Staggered",
      note = "Every other line pushed along by half a cell." },
    { value = "arc",      text = "Arc",
      note = "Cells around a circle. A full 360 closes the ring." },
    { value = "diagonal", text = "Diagonal",
      note = "Each cell steps by a fixed offset. Steps, ladders, slants." },
    { value = "free",     text = "Puzzle",
      note = "Every cell exactly where you dragged it. No lattice at all." },
}

-- Which way a grid fills before it wraps.
ns.FLOWS = {
    { value = "rows",    text = "Fill rows first" },
    { value = "columns", text = "Fill columns first" },
}

ns.GROW_X = {
    { value = "right", text = "Left to right" },
    { value = "left",  text = "Right to left" },
}

ns.GROW_Y = {
    { value = "down", text = "Top to bottom" },
    { value = "up",   text = "Bottom to top" },
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

    local interesting = (opts.scale and opts.scale ~= 1)
        or (opts.x and opts.x ~= 0) or (opts.y and opts.y ~= 0)
        or opts.kind or opts.hidden
    if not interesting then cfg.cellOpts[index] = nil end
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

-- The radius that puts exactly `spacing` between neighbours, from the chord
-- of the step angle. Worked out rather than guessed, so an arc of four big
-- icons and one of twelve small ones both come out evenly spaced.
local function AutoRadius(step, cellW, spacing)
    local half = rad(abs(step)) / 2
    local chord = sin(half)
    if chord < 0.0001 then return (cellW + spacing) * 2 end
    return (cellW + spacing) / (2 * chord)
end

local function ArcSlot(cfg, index, cellW, cellH, spacing, count)
    local span = cfg.arcSpan or 180
    local closed = abs(span) >= 359.5

    -- A closed ring divides by the count; an open arc puts a cell on each end
    -- and divides by the gaps between them.
    local divisor = closed and count or max(1, count - 1)
    local step = span / divisor
    if (cfg.growX or "right") == "left" then step = -step end

    local radius = cfg.arcRadius or 0
    if radius <= 0 then radius = AutoRadius(step, cellW, spacing) end

    local angle = rad((cfg.arcStart or 90) + step * (index - 1))
    return cos(angle) * radius, sin(angle) * radius
end

local function DiagonalSlot(cfg, index, cellW, cellH, spacing, lineSpacing)
    local stepX = (cellW + spacing) * ((cfg.diagonalX or 100) / 100)
    local stepY = (cellH + lineSpacing) * ((cfg.diagonalY or -100) / 100)

    if (cfg.growX or "right") == "left" then stepX = -stepX end
    if (cfg.growY or "down") == "up" then stepY = -stepY end

    return (index - 1) * stepX + cellW / 2, (index - 1) * stepY - cellH / 2
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
            x, y = 0, 0
        elseif kind == "arc" then
            x, y = ArcSlot(cfg, index, baseW, baseH, spacing, count)
        elseif kind == "diagonal" then
            x, y = DiagonalSlot(cfg, index, baseW, baseH, spacing, lineSpacing)
        elseif kind == "stagger" then
            x, y = StaggerSlot(cfg, index, baseW, baseH, spacing, lineSpacing,
                columns, rows)
        else
            x, y = GridSlot(cfg, index, baseW, baseH, spacing, lineSpacing,
                columns, rows)
        end

        -- The nudge, on every arrangement. See the header: this is what makes
        -- "drag one icon out of the row" and "build a puzzle" the same edit.
        if opts then
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
    if Layout.IsFree(cfg) or (cfg.layout or "grid") == "arc"
        or (cfg.layout or "grid") == "diagonal" then
        return max(1, cfg.freeCount or 6)
    end
    return max(1, (cfg.rows or 1) * (cfg.columns or 1))
end

-- Rounds a coordinate onto the puzzle raster. Zero means no raster, which is
-- what "off" has to mean here - the alternative is a snap of one pixel that
-- reads as broken.
function Layout.SnapToRaster(value, step)
    if not step or step <= 0 then return value end
    return floor(value / step + 0.5) * step
end
