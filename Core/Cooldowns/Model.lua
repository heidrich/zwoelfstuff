---------------------------------------------------------------------------
-- The lattice. Where cell N of a bar sits, and how big it is.
--
-- PURE. Nothing here creates a frame, reads the game or knows what a spell
-- is - numbers and words in, numbers and words out. That is not tidiness: an
-- off-by-one in this file does not raise an error, it puts the right icon in
-- the wrong square and looks exactly like a working display. The only way to
-- catch that is to be able to ask without a client.
--
-- WHY IT IS BEING WRITTEN AGAIN. Layout.lua's header says what happened to
-- the last one: two thirds of that file was one closed cluster - Build, the
-- cell sizes, the grid and stagger slots, the per-cell nudges - and when the
-- bars went, nothing outside it could reach any of it from any door. So it
-- went too. What stayed there is what the rest of the addon measures with,
-- and this file deliberately does not duplicate a line of it: the gap-closing
-- rule is still Layout.Compact and is called, not copied.
--
-- THE MODEL, in one sentence: A BAR IS A FLAT LIST OF CELLS IN READING
-- ORDER, and the column count is a property of the VIEW.
--
-- That sentence is the whole advantage this has over saying "row 2, column 3"
-- per cell. Change the column count and a flat list RE-FLOWS - the fourth
-- thing you put on the bar is still the fourth thing - while a stored grid
-- position scrambles, because there is no row 3 any more and nothing says
-- where its occupants went. It is also why the editor can show the true
-- arrangement: what it draws is the list, in order, at the current width.
--
-- THE COORDINATE SYSTEM is Layout.lua's, unchanged, so no caller has to hold
-- two: local to the bar's own frame, origin anywhere, +x right and +y UP -
-- the way a SetPoint offset reads. A slot comes back as its CENTRE plus a
-- size, because a thing that grows should grow around itself rather than
-- shove its neighbours.
---------------------------------------------------------------------------
local _, ns = ...

local Cooldowns = ns.Cooldowns
local Model = {}
Cooldowns.Model = Model

---------------------------------------------------------------------------
-- The vocabularies
--
-- These three left with the bars - Layout.lua says so at the place they used
-- to be - and they come back here rather than there, because they describe
-- an arrangement of cells and Layout no longer arranges anything.
--
-- The words are the SAME words the fill and gradient directions already use.
-- Two vocabularies for one idea is how a settings page starts needing to be
-- learned, and this addon already has "Left to right" meaning a direction in
-- four other places.
---------------------------------------------------------------------------

ns.CD_LAYOUTS = {
    { value = "grid",      text = "Grid",      icon = "dir-left-right" },
    -- Every other line pushed along by half a cell. It is not decoration:
    -- on a wide bar of small icons a straight grid reads as one block and a
    -- staggered one reads as rows, which is what you want when the second
    -- row means something different from the first.
    { value = "staggered", text = "Staggered", icon = "dir-top-bottom" },
}

-- WHICH WAY A GRID FILLS BEFORE IT WRAPS. Reading order is not the same
-- question as growth direction, and conflating them is why a bar set to grow
-- upwards used to fill its bottom row last.
ns.CD_FLOWS = {
    { value = "rows",    text = "Along rows",    icon = "dir-left-right" },
    { value = "columns", text = "Down columns",  icon = "dir-top-bottom" },
}

ns.CD_GROW_X = {
    { value = "right", text = "Left to right", icon = "dir-left-right" },
    { value = "left",  text = "Right to left", icon = "dir-right-left" },
}

-- ns.GROW_Y survived in Layout.lua and is not restated here. One list, one
-- place: the day somebody adds a third answer to it, a copy in this file
-- would be the one that did not get it.

---------------------------------------------------------------------------
-- Reading order
---------------------------------------------------------------------------

-- Which ROW and COLUMN the Nth cell of the list occupies, both zero-based.
--
-- This is the only place the flow is interpreted. Everything below asks this
-- and then does arithmetic, so "down columns" is implemented once instead of
-- inside three different position functions where the third one is always the
-- one that forgets.
--
-- `count` matters for columns-first and is ignored for rows-first: filling
-- downwards needs to know how tall the lattice is before it can say when to
-- wrap, and how tall it is depends on how many cells there are.
function Model.Cell(index, columns, flow, count)
    columns = math.max(1, math.floor(columns or 1))
    index = math.max(1, math.floor(index or 1))

    if flow ~= "columns" then
        local zero = index - 1
        return math.floor(zero / columns), zero % columns
    end

    -- Down the first column, then the second. The height is what the whole
    -- list needs at this width, which is why it is not a parameter with a
    -- default: a wrong height here silently interleaves the columns.
    local rows = math.max(1, math.ceil(math.max(1, count or index) / columns))
    local zero = index - 1
    return zero % rows, math.floor(zero / rows)
end

-- How many rows and columns a list of `count` needs at this width.
function Model.Shape(count, columns)
    columns = math.max(1, math.floor(columns or 1))
    count = math.max(0, math.floor(count or 0))
    if count == 0 then return 0, columns end
    return math.ceil(count / columns), math.min(count, columns)
end

---------------------------------------------------------------------------
-- Where a cell sits
---------------------------------------------------------------------------

-- Everything a slot needs, with the defaults it is measured against. Written
-- out rather than taken from a bar's stored table on purpose: this file must
-- stay askable with six numbers and no profile.
local FIELDS = {
    columns = 1,
    size    = 32,     -- one cell, square unless width says otherwise
    width   = nil,    -- nil means square
    spacing = 4,
    -- THE GAP BETWEEN ROWS IS ITS OWN NUMBER, and it was very nearly not.
    --
    -- The first draft used `spacing` on both axes, which is right on exactly
    -- one of his four bars by coincidence: two of them carry spacing 2 and 3
    -- against lineSpacing 4, and one of those has a single column, so the row
    -- gap is the ONLY gap it has. A bar drawn with the wrong row gap is not a
    -- bar that fails - it is a bar that looks very slightly not like the one
    -- you arranged, which is the hardest kind of wrong to report.
    --
    -- nil rather than a number of its own: falling back to `spacing` keeps a
    -- caller that only knows about one gap honest, and a stored bar always
    -- carries both.
    lineSpacing = nil,
    layout  = "grid",
    flow    = "rows",
    growX   = "right",
    growY   = "down",
    -- How far the odd rows shift, as a FRACTION of one step. 0.5 is the half
    -- cell that makes a staggered bar read as rows; stored as a fraction so
    -- it survives a change of icon size, which a stored pixel count would not.
    stagger = 0.5,
}

local function Read(opts, key)
    local value = opts and opts[key]
    if value == nil then return FIELDS[key] end
    return value
end

-- The step from one cell's centre to the next, on each axis.
local function Steps(opts)
    local size = Read(opts, "size")
    local width = Read(opts, "width") or size
    local spacing = Read(opts, "spacing")
    local lineSpacing = Read(opts, "lineSpacing") or spacing
    return width + spacing, size + lineSpacing, width, size
end

-- WHERE CELL `index` SITS, as its centre and its size.
--
-- The centre, not a corner, and that is the same decision Layout.StripSlot
-- made for the same reason: a cell that grows should grow around itself. Hand
-- a renderer a corner and every size change moves every neighbour.
--
-- The origin is cell 1's centre. A bar that grows left puts cell 2 at a
-- NEGATIVE x from there, which is what "grows left" means and what stops the
-- caller having to flip a sign it cannot see.
function Model.Slot(index, opts, count)
    local stepX, stepY, cellW, cellH = Steps(opts)
    local row, column = Model.Cell(index, Read(opts, "columns"),
        Read(opts, "flow"), count)

    local x = column * stepX
    if Read(opts, "growX") == "left" then x = -x end

    -- +y is UP, and "down" is the ordinary reading direction, so the ordinary
    -- case is the one carrying the minus. Getting this backwards draws the
    -- second row above the first and looks like a deliberate design.
    local y = row * stepY
    if Read(opts, "growY") ~= "up" then y = -y end

    -- The stagger rides on the ROW, not on the cell, so a whole row moves
    -- together. Odd rows only - shifting every row is a bar that has simply
    -- moved sideways.
    if Read(opts, "layout") == "staggered" and row % 2 == 1 then
        local shift = stepX * (Read(opts, "stagger") or 0)
        if Read(opts, "growX") == "left" then shift = -shift end
        x = x + shift
    end

    return x, y, cellW, cellH
end

-- HOW BIG THE WHOLE THING IS, measured the same way it is drawn.
--
-- Computed from the slots rather than from a formula of its own. The formula
-- would be right until the day the stagger changed, and then a bar would be
-- drawn correctly inside a box half a cell too small - which crops one row's
-- last icon and nothing else, on one layout, and reads as a texture problem.
--
-- Returns the width, the height, and the offset from cell 1's centre to the
-- box's own centre, so a caller can anchor the box without knowing any of
-- the arithmetic above.
function Model.Extent(count, opts)
    count = math.max(0, math.floor(count or 0))
    if count == 0 then return 0, 0, 0, 0 end

    local minX, maxX, minY, maxY
    for index = 1, count do
        local x, y, w, h = Model.Slot(index, opts, count)
        local left, right = x - w / 2, x + w / 2
        local bottom, top = y - h / 2, y + h / 2
        minX = math.min(minX or left, left)
        maxX = math.max(maxX or right, right)
        minY = math.min(minY or bottom, bottom)
        maxY = math.max(maxY or top, top)
    end

    return maxX - minX, maxY - minY,
        (minX + maxX) / 2, (minY + maxY) / 2
end

---------------------------------------------------------------------------
-- Re-flow
--
-- There is deliberately no function here that moves cells about when the
-- column count changes, and its absence is the design rather than a gap.
--
-- The list is the truth and the columns are the view. Nothing has to be
-- rewritten when the width changes - ask Model.Slot again and every cell is
-- where the new width puts it. A Reflow() would be a function that took the
-- model, did nothing, and gave callers somewhere to put a bug.
--
-- What DOES need saying is what happens to a cell that is not drawn, and that
-- is Layout.Compact's job and stays there. This is the one line that joins
-- them: ask Compact which SLOT each cell takes, then ask Slot where that slot
-- is. Two rules, each in one place, composed at the call site.
---------------------------------------------------------------------------

-- The positions of a whole bar in one pass: for each cell that is drawn, its
-- slot's centre and size. `hidden` is indexed by cell, exactly as
-- Layout.Compact takes it.
--
-- Returns a table indexed by CELL - not by slot - because every caller has a
-- cell in its hand and wants to know where to put it. Cells that are not
-- drawn are absent rather than false, so `for cell, at in pairs(...)` walks
-- what is on screen and nothing else.
function Model.Places(count, opts, hidden, compact)
    local place, used = ns.Layout.Compact(hidden, count,
        compact, Read(opts, "columns"))

    local out = {}
    for cell = 1, count do
        local slot = place[cell]
        if slot then
            local x, y, w, h = Model.Slot(slot, opts, used)
            out[cell] = { x = x, y = y, w = w, h = h, slot = slot }
        end
    end
    return out, used
end
