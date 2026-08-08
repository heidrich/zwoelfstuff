---------------------------------------------------------------------------
-- Bars - the data model.
--
-- A bar is a grid of cells. Every cell is either empty or holds one spell.
-- Rows and columns are set by the user and the grid re-flows; the options
-- editor shows exactly this grid, so what you arrange there is what appears
-- on screen.
--
-- Cells are stored in reading order (left to right, then down), which is why
-- changing the column count re-flows rather than scrambles: the sequence of
-- spells is preserved and only the wrap point moves.
--
-- The spells themselves come from Blizzard's Cooldown Manager (Core/CDM.lua)
-- - it already knows them, already binds their auras and already has correct
-- timing, none of which an addon can do for itself on this patch.
---------------------------------------------------------------------------
local _, ns = ...

local Bars = {}
ns.Bars = Bars

ns.BAR_DEFAULTS = {
    name    = "Bar",
    enabled = true,
    kind    = "icon",          -- "icon" | "bar"

    -- Pinned in place. Edit mode still shows it and still opens its settings;
    -- it cannot be dragged or nudged. Per bar rather than one switch for all
    -- of them, because the bar you have finished placing and the bar you are
    -- still placing are usually on screen together, and the finished one is
    -- exactly what a stray drag lands on.
    --
    -- `pinned`, not `locked`. There WAS a `locked = true` in this table, and
    -- nothing anywhere read it - a dead field from an older shape. Reusing the
    -- name would have locked every bar you already own the moment you updated,
    -- because the defaults are re-applied on load and every saved bar already
    -- carries it as true.
    pinned  = false,

    -- Identity, and it is NOT the position in the list. A bar that is anchored
    -- to another one has to keep pointing at the same bar after a delete
    -- reshuffles every index below it.
    id      = 0,               -- assigned by Prepare(), never reused

    rows    = 1,
    columns = 6,
    -- [index] = spellID; holes are empty cells.
    --
    -- NOT saved here. This field is pointed at cellsBySpec[class:spec] by
    -- Bars:BindSpec, because the layout is shared by every character and the
    -- spells are not - see the block above Bars:All. Reading and writing it
    -- is unchanged everywhere else.
    cells   = {},

    -- How the cells are arranged. See Core/Layout.lua - "grid" is rows and
    -- columns, "stagger" is the same lattice with every other line pushed
    -- along, and "free" is the puzzle, which has no lattice at all.
    layout  = "grid",
    flow    = "rows",          -- which axis fills before it wraps
    growX   = "right",         -- reading direction across
    growY   = "down",          -- reading direction down

    -- How many cells the puzzle holds. It has no rows and columns, so a grid
    -- of 2x3 means nothing to it; this is its length.
    freeCount = 6,

    -- Belongs to Staggered and is ignored by the others. Flat rather than
    -- nested, so switching pattern and switching back cannot lose it.
    staggerOffset = 50,        -- percent of a cell, on every other line

    -- The puzzle raster. Dragging a cell in build mode lands on it, so a
    -- hand-built layout still lines up. 0 is free-hand.
    raster = 4,

    -- Per-cell overrides: cellOpts[index] = { scale, x, y, kind, hidden }.
    -- This is what lets one icon in a row be twice the size, one cell be a
    -- tracking bar among icons, and any of them sit where the lattice would
    -- not have put it. Absent for every cell nobody has touched.
    --
    -- SHARED by every character, because it describes the SLOT rather than
    -- what is in it. That is why moving a spell no longer drags its cell's
    -- look along - see Bars:MoveCell.
    cellOpts = {},

    -- Size
    iconSize    = 40,
    barWidth    = 200,
    barHeight   = 24,
    spacing     = 4,
    lineSpacing = 4,

    -- Bar-shaped cells only: where the spell icon sits, and it stays SQUARE
    -- wherever that is. A spell icon stretched to the width of a bar is the
    -- one thing a tracking bar must never look like.
    --   "left" | "right" | "hidden"
    iconPlacement = "left",

    -- Looks
    scale       = 1.0,
    alpha       = 1.0,
    borderSize  = 1,
    borderColor = { 0.00, 0.00, 0.00 },

    -- A surface behind the icon. Visible through the icon's own transparency
    -- and, more usefully, everywhere the icon is not - a zoomed-out icon on a
    -- dark plate reads very differently from one floating on the world.
    backdrop        = true,
    backdropColor   = { 0.00, 0.00, 0.00 },
    backdropAlpha   = 0.90,
    backdropTexture = "Blizzard",

    -- "None" keeps the crisp one-pixel line drawn from colour textures.
    -- Anything else is a real edge file out of LibSharedMedia, which is where
    -- the beveled and glowing borders people already own come from.
    borderTexture = "None",

    -- How much of the icon art is cut away. Blizzard's own icons carry a
    -- baked-in border that this crops off; 0 shows the whole file.
    iconZoom = 0.08,

    -- What an aura we draw ourselves looks like while it is NOT up. Blizzard
    -- simply removes its own buff icons, which makes a bar re-flow under your
    -- eye - the point of a fixed grid is that a spell is always in the same
    -- place. So ours stay, quieter.
    --
    -- 0 hides them after all, for anyone who wants Blizzard's behaviour.
    inactiveAlpha      = 0.55,
    inactiveDesaturate = true,

    -- The cooldown sweep.
    swipeColor = { 0.00, 0.00, 0.00 },
    swipeAlpha = 0.70,
    showEdge   = false,        -- the bright line that follows the sweep

    -- THE FILL OF A TRACKING BAR, whichever of the two renderers draws it.
    --
    -- A cell we draw had no fill at all, so a bar-shaped aura was a square
    -- icon and a hole beside it. An adopted buff-bar frame had Blizzard's,
    -- which no setting here could reach - so one row could hold two bars
    -- wearing two different textures with one picker between them. Both go
    -- through these four values now.
    --
    -- Empty texture means "wear the backdrop's", so the default bar is one
    -- object rather than two textures that happen to be adjacent.
    fillColor   = { 1.00, 0.478, 0.239 },
    fillAlpha   = 0.85,
    fillTexture = "",

    -- TWO SETTINGS, because they are two different things and shipping them
    -- as one was a real bug: "Fill up" was wired to SetReverseFill, which
    -- moves the fill to the OTHER END rather than making it grow.
    --
    --   fillSide  which end the fill starts from. SetReverseFill.
    --   fillGrow  grows as time passes instead of draining away. That is the
    --             CLOCK, and on this client it is Blizzard's own
    --             StatusBar:SetTimerDuration with
    --             Enum.StatusBarTimerDirection.ElapsedTime - read off
    --             EllesmereUICdmBuffBars.lua:4088, not invented here.
    fillSide    = false,       -- true starts the fill at the right-hand end
    fillGrow    = false,       -- true fills up as time passes

    -- WHICH WAY THE FILL RUNS, as one setting with four answers instead of a
    -- pair of switches you have to combine in your head. It replaced
    -- `fillSide` as the thing the panel offers - fillSide is still read, and
    -- still migrated, because a profile written before this carries it.
    --
    -- Two of the four are NEW: a StatusBar's SetReverseFill only ever flips a
    -- horizontal bar, so up and down needed SetOrientation as well and were
    -- simply not reachable before.
    --
    --   "right"  left to right   HORIZONTAL, not reversed
    --   "left"   right to left   HORIZONTAL, reversed
    --   "up"     bottom to top   VERTICAL,   not reversed
    --   "down"   top to bottom   VERTICAL,   reversed
    fillDirection = "right",

    -- A bright line riding the leading edge of the fill. Anchored TO the
    -- fill's texture, so it follows the clock without costing a frame.
    showSpark   = false,

    -- One line across the fill per charge boundary: three charges get two
    -- lines, at a third and two thirds. Only ever shown for a spell that has
    -- more than one charge, so the setting can stay on for a whole bar.
    chargeMarks     = false,
    chargeMarkColor = { 0, 0, 0 },

    -- STACK THRESHOLDS. The bar's fill changes colour once the stack count
    -- reaches a number you choose. Bone Shield is the reason it exists.
    --
    -- A list of { value, color }, and the colour BELOW the lowest threshold
    -- is the bar's own fillColor. So the natural way to say "warn me under
    -- five" is a red fill with one threshold at 5 wearing the normal colour -
    -- there is no separate "below" mode to get the wrong way round.
    --
    -- Sorted ascending, because the order IS the draw order: see the overlay
    -- pool in Core/Screen.lua, where the highest crossed threshold has to
    -- paint last and cannot be chosen with an `if`.
    stackThresholds = {},      -- { { value = 5, color = {r,g,b}, alpha = 1 }, ... }

    -- Text. Three elements, one shape each, because "the countdown can be
    -- moved but the stack count cannot" is the kind of arbitrary limit that
    -- makes people go looking for another addon.
    --
    -- A size of 0 means "work it out from the cell", which is what keeps a
    -- 24px cell and a 64px cell looking like one design.
    countdown = {
        show    = true,
        font    = "",   -- empty means "whatever Settings says"
        size    = 0,
        color   = { 1.00, 1.00, 1.00 },
        outline = "OUTLINE",
        anchor  = "CENTER",
        x       = 0,
        y       = 0,
    },

    stacks = {
        show    = true,
        font    = "",   -- empty means "whatever Settings says"
        size    = 0,
        color   = { 1.00, 1.00, 1.00 },
        outline = "OUTLINE",
        anchor  = "BOTTOMRIGHT",
        x       = 0,
        y       = 0,
    },

    -- The spell name on a bar-shaped cell. NOT cfg.name - that is the bar's
    -- own name, and one of these overwriting the other is exactly the kind of
    -- collision a flat settings table invites.
    spellName = {
        show    = true,
        font    = "",   -- empty means "whatever Settings says"
        size    = 0,
        color   = { 1.00, 1.00, 1.00 },
        outline = "",
        anchor  = "LEFT",
        x       = 0,
        y       = 0,
    },

    -- What the cell does beyond sitting there: the flash when a cooldown
    -- lands, the edge while it is ready, the nag when you have been sitting
    -- on it. Filled from ns.EFFECT_DEFAULTS so there is one definition.
    effects = ns.EFFECT_DEFAULTS,

    -- When this bar is on screen at all. Filled from ns.SHOW_DEFAULTS.
    show = ns.SHOW_DEFAULTS,

    -- Position, relative to the screen centre. Always the bar's own centre,
    -- so the readout in unlock mode means something and snapping is
    -- arithmetic rather than a case analysis.
    point    = "CENTER",
    relPoint = "CENTER",
    x        = 0,
    y        = -200,

    -- Attached to another bar, and then the fields above are not used:
    --   { to = <bar id>, point, relPoint, x, y }
    -- Nil means it stands on its own. See Bars:Anchor.
    anchor   = nil,
}

---------------------------------------------------------------------------
-- WHAT IS SHARED, AND WHAT IS NOT
--
-- Owner, 2026-08-07: "das layout muss gespeichert werden, aber nicht die
-- spells" - and the bug that prompted it: the saved variables are account
-- wide, so a Paladin was shown a row of Death Knight cooldowns.
--
-- So a bar is two things. Everything about how it LOOKS and where it sits -
-- the arrangement, the sizes, the colours, the rules, the per-cell overrides
-- - is shared by every character, because that is a user interface you built
-- once and want everywhere. What each cell HOLDS is per class and spec,
-- because a spell is not portable.
--
-- HOW, without rewriting forty-five call sites. cfg.cells stays exactly what
-- it was - the table of spells, read and written the same way everywhere -
-- and BindSpec points it at the right per-spec table. One place decides who
-- is playing; nothing else has to know the rule exists.
--
-- Two characters of the same class and spec share their picks. That is help
-- rather than harm: they can cast the same things, and it is the same key the
-- proc registry has always used.
---------------------------------------------------------------------------
local function SpecTable(cfg, field, key)
    local store = field .. "BySpec"
    cfg[store] = cfg[store] or {}
    cfg[store][key] = cfg[store][key] or {}
    return cfg[store][key]
end

-- Points every bar's cells and parked list at the current spec's own tables.
-- Returns true when the answer changed, so callers know to redraw.
function Bars:BindSpec()
    local key, known = ns.SpecKey()
    key = key or "unknown"
    if self.boundSpec == key then return false end

    for _, cfg in ipairs(ns.db.bars) do
        -- Saved by a version that kept ONE set of spells for every character.
        -- They belong to whoever was playing when it was written, and the
        -- first spec that can identify itself is that character - so they are
        -- adopted then, and never while the spec still reads as 0.
        if known and cfg.cells and not cfg.cellsBySpec then
            if next(cfg.cells) then
                cfg.cellsBySpec = { [key] = cfg.cells }
            end
        end

        cfg.cells  = SpecTable(cfg, "cells", key)
        cfg.parked = SpecTable(cfg, "parked", key)

        -- A set filed under an unknown spec - "DEATHKNIGHT:0", written in the
        -- moment between login and the client being able to answer - is
        -- dropped once it is empty, so the saved file does not collect one of
        -- those per character for ever.
        for other, set in pairs(cfg.cellsBySpec) do
            if other ~= key and other:find(":0$") and not next(set) then
                cfg.cellsBySpec[other] = nil
            end
        end
    end

    self.boundSpec = key
    return true
end

---------------------------------------------------------------------------
-- Taking another character's layout
--
-- The other half of per-character settings, and the owner named it in the
-- same breath: "das sind dann auswahloptionen ob ich das layout von anderen
-- chars übernehmen will". Without it, every alt starts from an empty screen
-- and nobody builds the same interface twice.
--
-- THE SPELLS DO NOT COME. That is the whole reason the settings are split per
-- character: a Death Knight's cooldowns are not castable on a Paladin, and
-- copying them across would recreate the bug this all started with. What
-- arrives is the shape - the bars, their names, arrangements, sizes, looks,
-- rules and positions - with every cell empty and waiting.
---------------------------------------------------------------------------
-- Copied all the way down, not referenced: a shared table would mean editing
-- one bar's border silently repainted every bar made from it. Recursive
-- rather than an ipairs pass, because the text settings are hash tables and
-- ipairs over one of those copies NOTHING - a preset that looked saved and
-- restored an empty table.
--
-- Declared here rather than beside the preset code that used to own it: the
-- layout copy above needs it too, and a second copy of the same function is
-- the kind of duplicate that drifts.
local function DeepCopy(value)
    if type(value) ~= "table" then return value end

    local copy = {}
    for key, inner in pairs(value) do copy[key] = DeepCopy(inner) end
    return copy
end

function Bars:CopyLayoutFrom(profileKey)
    local store = ZwoelfStuffDB and ZwoelfStuffDB.chars
    local source = store and store[profileKey]
    if not (source and source.bars) then return false, "that character has no bars" end

    local copied = {}
    for _, cfg in ipairs(source.bars) do
        local bar = DeepCopy(cfg)

        -- Everything that names a spell is dropped, and the ids are re-issued
        -- so an attachment cannot end up pointing at one of OUR bars by
        -- coincidence of numbering.
        bar.cellsBySpec, bar.parkedBySpec = nil, nil
        bar.cells, bar.parked = {}, {}
        bar.id = 0

        copied[#copied + 1] = bar
    end

    if #copied == 0 then return false, "that character has no bars" end

    -- Attachments are by id, so the old ids have to be mapped onto the new
    -- ones. Done in a second pass, because a bar can be attached to one that
    -- comes after it in the list.
    local newID = {}
    for index, bar in ipairs(copied) do
        newID[source.bars[index].id] = self:NextID()
        bar.id = newID[source.bars[index].id]
    end
    for _, bar in ipairs(copied) do
        if bar.anchor then
            bar.anchor.to = newID[bar.anchor.to]
            if not bar.anchor.to then bar.anchor = nil end
        end
    end

    ns.db.bars = copied
    self:Prepare()
    self:BindSpec()
    self.boundSpec = nil
    self:BindSpec()

    self:Changed()
    return true, #copied
end

---------------------------------------------------------------------------
-- Access
---------------------------------------------------------------------------
function Bars:All()
    return ns.db.bars
end

function Bars:Get(index)
    return ns.db.bars[index]
end

function Bars:Count()
    return #ns.db.bars
end

-- How many cells a bar has. A lattice is rows x columns, so an empty trailing
-- cell is a real, clickable place to put something - that is what makes "add
-- a row" mean anything before you have filled it. An arc, a diagonal and a
-- puzzle are a sequence instead and carry their own length.
function Bars:CellCount(cfg)
    return ns.Layout.CellCount(cfg)
end

-- One more cell on an arrangement that has no rows and columns. The button
-- that calls this is the whole "add something to the puzzle" gesture.
function Bars:AddCell(index)
    local cfg = self:Get(index)
    if not cfg then return false end

    if ns.Layout.UsesGrid(cfg) then
        cfg.rows = math.min(20, (cfg.rows or 1) + 1)
    else
        cfg.freeCount = math.min(40, (cfg.freeCount or 6) + 1)
    end

    -- A bigger bar has room for anything a smaller one had to park.
    self:Resized(cfg)
    self:Changed(index)
    return true
end

-- Takes a cell out of a sequence and closes the gap behind it, spell and
-- per-cell settings together. Leaving the hole would be the easy version and
-- it is wrong: the cells below would all shift by one on the next re-flow.
function Bars:RemoveCell(index, cell)
    local cfg = self:Get(index)
    if not cfg then return false end

    -- The spells close up; the slots do not move. See MoveCell.
    local last = self:CellCount(cfg)
    for position = cell, last - 1 do
        cfg.cells[position] = cfg.cells[position + 1]
    end
    cfg.cells[last] = nil

    -- A lattice keeps its shape - taking a cell out of a 2x3 grid would leave
    -- a grid that is no longer rectangular - so there the last slot simply
    -- becomes empty. A sequence gets one shorter, which is what "remove" means
    -- when there are no rows and columns to preserve.
    if not ns.Layout.UsesGrid(cfg) then
        cfg.freeCount = math.max(1, (cfg.freeCount or 6) - 1)
    end

    self:Resized(cfg)
    self:Changed(index)
    return true
end

---------------------------------------------------------------------------
-- Editing
---------------------------------------------------------------------------
function Bars:Add(name, kind)
    local cfg = {}
    ns.ApplyDefaults(cfg, ns.BAR_DEFAULTS)
    -- Its own id immediately. The default is 0, and two bars sharing 0 would
    -- make ByID answer with whichever came first.
    cfg.id = self:NextID()
    cfg.kind = kind or "icon"
    cfg.name = name or ((kind == "bar" and "Bars " or "Icons ") .. (#ns.db.bars + 1))
    cfg.cells = {}

    if kind == "bar" then
        -- A bar-shaped element is wide, so a column of them is the sensible
        -- default; icons default to a row.
        cfg.rows, cfg.columns = 4, 1
    end

    -- Stagger, so a second bar does not land exactly on the first.
    cfg.y = ns.BAR_DEFAULTS.y - (#ns.db.bars * 70)

    ns.db.bars[#ns.db.bars + 1] = cfg

    -- Straight into the per-spec scheme, or its cells table is detached and
    -- nothing you put in it is ever saved. BindSpec skips a bar it has
    -- already bound, so it is asked to do this one directly.
    local key = ns.SpecKey() or "unknown"
    cfg.cells  = SpecTable(cfg, "cells", key)
    cfg.parked = SpecTable(cfg, "parked", key)

    self:Changed(#ns.db.bars)
    return #ns.db.bars
end

function Bars:Remove(index)
    local going = ns.db.bars[index]
    if not going then return false end

    table.remove(ns.db.bars, index)

    -- Anything hanging on it is set free where it stands. Left pointing at a
    -- bar that no longer exists, it would have no position at all.
    for _, cfg in ipairs(ns.db.bars) do
        if cfg.anchor and cfg.anchor.to == going.id then self:Release(cfg) end
    end

    self:Changed()
    return true
end

function Bars:SetCell(index, cell, spellID)
    local cfg = self:Get(index)
    if not cfg then return false end
    cfg.cells[cell] = spellID
    self:Changed(index)
    return true
end

function Bars:ClearCell(index, cell)
    return self:SetCell(index, cell, nil)
end

-- Drag and drop. Moving onto an occupied cell swaps, which is what dragging
-- one icon onto another visibly looks like it should do.
--
-- THE PER-CELL LOOK STAYS WITH THE SLOT, and that is a reversal. It used to
-- travel with the spell, on the reasoning that a cell scaled up is that
-- spell's presentation. That stopped being true when the layout became shared
-- and the spells did not: a slot scaled to 150% is part of a bar every
-- character sees, so dragging a spell on one of them must not rearrange it
-- for the rest.
function Bars:Swap(cfg, from, to)
    if not cfg or from == to then return false end

    local count = self:CellCount(cfg)
    if from < 1 or to < 1 or from > count or to > count then return false end

    cfg.cells[from], cfg.cells[to] = cfg.cells[to], cfg.cells[from]
    return true
end

function Bars:MoveCell(index, from, to)
    if not self:Swap(self:Get(index), from, to) then return false end
    self:Changed(index)
    return true
end

-- SORTING, which is not the same as swapping.
--
-- Dragging the third spell onto the first should leave the other two in the
-- order they were in, one place further down - that is what "sort this list"
-- means and it is what a single drag has to do, or putting four spells in
-- order takes six swaps and a diagram.
--
-- Swapping was what the drag did before, and it is still right for "these two
-- are in each other's places". It just cannot sort: every swap disturbs a
-- second cell nobody pointed at.
--
-- ONLY THE SPELLS MOVE. A cell's own look - its scale, its nudge, its kind -
-- belongs to the SLOT and stays where it is, the same rule MoveCell follows.
-- Drag a spell to the front of a bar and it wears the front slot's look,
-- which is the whole point of a slot having one.
-- The model operation takes a CONFIG, and only the wrapper below needs an
-- index - so the rule can be checked on a throwaway bar rather than by
-- creating a real one and leaving it behind. Same split as Reshape/Relayout.
function Bars:Reorder(cfg, from, to)
    if not cfg or from == to then return false end

    local count = self:CellCount(cfg)
    if from < 1 or to < 1 or from > count or to > count then return false end

    local moving = cfg.cells[from]

    -- Everything between the two closes up by one. Holes travel with it,
    -- because a hole is a position in the sequence like any other - dropping
    -- a spell in front of one must not quietly fill it.
    if to > from then
        for cell = from, to - 1 do cfg.cells[cell] = cfg.cells[cell + 1] end
    else
        for cell = from, to + 1, -1 do cfg.cells[cell] = cfg.cells[cell - 1] end
    end
    cfg.cells[to] = moving
    return true
end

function Bars:ReorderCell(index, from, to)
    if not self:Reorder(self:Get(index), from, to) then return false end
    self:Changed(index)
    return true
end

-- Puts a spell in the first free cell, growing by a row if the grid is full.
-- Used by "add" flows that do not name a target cell.
function Bars:AddSpell(index, spellID)
    local cfg = self:Get(index)
    if not cfg then return false end

    for cell = 1, self:CellCount(cfg) do
        if not cfg.cells[cell] then
            return self:SetCell(index, cell, spellID)
        end
    end

    -- Full: grow, then put it in the first slot that appeared. A lattice grows
    -- by a row, a sequence by one slot - which is why the growing is asked for
    -- rather than written out here.
    local before = self:CellCount(cfg)
    self:AddCell(index)
    local after = self:CellCount(cfg)
    if after <= before then return false end

    return self:SetCell(index, before + 1, spellID)
end

---------------------------------------------------------------------------
-- Resizing a bar, without ever losing what is in it
--
-- EVERY CELL KEEPS ITS INDEX. That is what makes the sliders reversible:
-- widening a grid to twelve columns and pulling it back to six gives you back
-- exactly what you started with, and a deliberate hole in the middle of a row
-- is still a hole afterwards.
--
-- The version before this one compacted everything to the front on every
-- change. It called itself a re-flow and it was really a destroy: one drag of
-- the Columns slider and the arrangement was gone with no way back - which is
-- precisely what "they do not switch back" meant.
--
-- WHAT SHRINKING DOES.
--
-- A spell whose index no longer exists is PARKED, not deleted, and it comes
-- back into its own index the moment the bar is big enough again. Losing a
-- spell to a slider you were only dragging to see what it looked like is not
-- something an addon gets to do.
---------------------------------------------------------------------------
-- ONLY THE SPELL IS PARKED. The per-cell look - scale, offset, kind, hidden -
-- belongs to the SLOT now, not to whatever is sitting in it: the layout is
-- shared by every character and the spells are not, so a look that travelled
-- with a spell would let one character rearrange another one's bar.
local function Park(cfg, cell)
    local spellID = cfg.cells[cell]
    if not spellID then return end

    cfg.parked = cfg.parked or {}
    cfg.parked[cell] = spellID
    cfg.cells[cell] = nil
end

local function Place(cfg, cell, spellID)
    cfg.cells[cell] = spellID
end

-- Anything parked that now has room again. Its own index first, so a bar that
-- grows back is the bar you had rather than a re-sorted version of it.
local function Unpark(cfg, count)
    local parked = cfg.parked
    if not parked then return end

    for cell, spellID in pairs(parked) do
        if cell <= count and not cfg.cells[cell] then
            Place(cfg, cell, spellID)
            parked[cell] = nil
        end
    end

    -- Its own index is taken or gone: the first free slot, in index order so
    -- the result does not depend on the order a hash table happens to walk in.
    local waiting = {}
    for cell in pairs(parked) do waiting[#waiting + 1] = cell end
    table.sort(waiting)

    for _, cell in ipairs(waiting) do
        for target = 1, count do
            if not cfg.cells[target] then
                Place(cfg, target, parked[cell])
                parked[cell] = nil
                break
            end
        end
    end

    -- The empty table is KEPT. It is the one BindSpec pointed cfg.parked at,
    -- and dropping it here would leave the next park writing into a table
    -- nothing saves.
end

-- Called after anything that changes how many cells a bar has. Walks what is
-- actually there rather than counting up to some ceiling, so a table that has
-- been hand-edited in the saved variables is handled too.
function Bars:Resized(cfg, count)
    count = count or self:CellCount(cfg)

    local over = {}
    for cell in pairs(cfg.cells) do
        if cell > count then over[#over + 1] = cell end
    end
    for _, cell in ipairs(over) do Park(cfg, cell) end

    Unpark(cfg, count)
end

-- The model operation, on a config rather than an index. Split out so the
-- self test can exercise it on a throwaway bar without ever touching the
-- user's own - a test that has to create a real bar to check a rule is a test
-- that eventually leaves one behind.
function Bars:ReshapeGrid(cfg, rows, columns)
    rows = math.max(1, math.min(20, rows or cfg.rows))
    columns = math.max(1, math.min(20, columns or cfg.columns))
    if rows == cfg.rows and columns == cfg.columns then return false end

    cfg.rows, cfg.columns = rows, columns
    self:Resized(cfg)
    return true
end

function Bars:SetGrid(index, rows, columns)
    local cfg = self:Get(index)
    if not cfg then return false end
    if not self:ReshapeGrid(cfg, rows, columns) then return false end

    self:Changed(index)
    return true
end

-- Switching arrangement, without losing what is already in the bar.
--
-- A lattice counts its cells as rows x columns; an arc, a diagonal and a
-- puzzle count them as a length. Switching between the two without carrying
-- the number across is what makes a six-icon row become a six-icon default
-- that happens to be the same size by luck, and a 3x4 grid collapse to six.
function Bars:Relayout(cfg, layout)
    if cfg.layout == layout then return false end

    local before = self:CellCount(cfg)

    -- Where the cells are RIGHT NOW, worked out by the arrangement the bar is
    -- still in. Taken before anything changes, because this is what seeds the
    -- puzzle: an arc dragged into the puzzle has to arrive as that arc. The
    -- old version re-derived a plain row out of rows and columns, so every
    -- arrangement that was not a grid was flattened on the way in.
    local seed
    if layout == "free" then
        seed = ns.Layout.Build(cfg, before, cfg.spacing or 4, cfg.lineSpacing or 4)
    end

    cfg.layout = layout

    if ns.Layout.UsesGrid(cfg) then
        -- Back onto a lattice, and the lattice's own rows and columns were
        -- never touched while the bar was away - they are separate fields
        -- from the sequence's length. So the shape you left is the shape you
        -- come back to, and a 3x2 grid does not return as a row of six.
        --
        -- Only a bar that GREW while it was a sequence needs more room than
        -- it had.
        local room = (cfg.rows or 1) * (cfg.columns or 1)
        if before > room then
            local columns = math.max(1, math.min(before, 12))
            cfg.columns = columns
            cfg.rows = math.max(1, math.ceil(before / columns))
        end
    else
        cfg.freeCount = math.max(1, math.min(40, before))
    end

    -- A puzzle with every cell at 0,0 is a stack nobody can pull apart, so the
    -- first visit takes its positions from what was on screen a moment ago.
    --
    -- Only cells the puzzle has never held a position for. Coming back to a
    -- puzzle you already arranged must find it exactly as you left it - which
    -- it now can, because those positions live in fields no other arrangement
    -- reads or writes. See the header of Core/Layout.lua.
    if layout == "free" and seed then
        for cell = 1, self:CellCount(cfg) do
            local opts = ns.Layout.CellOpts(cfg, cell)
            local slot = seed[cell]
            if slot and not (opts and (opts.px or opts.py)) then
                ns.Layout.SetOffset(cfg, cell, slot.x, slot.y)
            end
        end
    end

    self:Resized(cfg)
    return true
end

function Bars:SetLayout(index, layout)
    local cfg = self:Get(index)
    if not cfg then return false end
    if not self:Relayout(cfg, layout) then return false end

    self:Changed(index)
    return true
end

-- Changing which point of the bar is pinned, without the bar jumping.
--
-- The stored x/y are that point's offset from the screen centre, so simply
-- writing a new point would move the bar by half its own size. Screen knows
-- where it actually is; ask, then write the new numbers for the new point.
function Bars:SetPivot(index, pivot)
    local cfg = self:Get(index)
    if not cfg or cfg.point == pivot then return false end

    -- Written BEFORE the capture on purpose: the frame has not moved yet, so
    -- reading it now gives the true geometry, and CapturePosition then works
    -- out where the NEW point currently sits. Put the numbers back and the
    -- bar has not budged.
    cfg.point = pivot
    if ns.Screen then ns.Screen:CapturePosition(index) end

    self:Changed(index)
    return true
end

---------------------------------------------------------------------------
-- Look and feel, as a transferable thing
--
-- Every bar has its own settings - that is the point of having several. But
-- setting eight sliders twice is work nobody should have to do, so a look can
-- be taken from another bar in one click, or saved once and applied to any
-- bar later.
--
-- Only the LOOK travels. Which spells are in the bar, how many rows it has
-- and where it sits on screen are what makes it that bar, and copying those
-- would overwrite the work rather than the styling.
---------------------------------------------------------------------------
ns.BAR_STYLE_KEYS = {
    "kind",
    "iconSize", "barWidth", "barHeight",
    "spacing", "lineSpacing",
    "iconPlacement",
    "scale", "alpha",
    "borderSize", "borderColor", "borderTexture",
    "backdrop", "backdropColor", "backdropAlpha", "backdropTexture",
    "iconZoom", "inactiveAlpha", "inactiveDesaturate",
    "swipeColor", "swipeAlpha", "showEdge",
    "fillColor", "fillAlpha", "fillTexture", "fillSide", "fillGrow",
    "fillDirection",
    "showSpark", "chargeMarks", "chargeMarkColor",
    "stackThresholds",
    "countdown", "stacks", "spellName",

    -- The arrangement travels too - it is how a bar LOOKS, not what it holds.
    -- Rows and columns deliberately do not: those are the shape the user laid
    -- their spells into, and overwriting them would rearrange the work rather
    -- than the styling.
    "layout", "flow", "growX", "growY",
    "staggerOffset", "raster",

    -- Effects are a look. Visibility rules are not: "only in raids" belongs to
    -- that one bar's job, and copying it onto another is never what was meant.
    "effects",
}

-- The three text elements, in the order they appear in the options.
ns.TEXT_ELEMENTS = {
    { key = "countdown", label = "Countdown", barOnly = false },
    { key = "stacks",    label = "Stacks and charges", barOnly = false },
    { key = "spellName", label = "Spell name", barOnly = true },
}

-- The nine places a number can sit on an icon.
ns.TEXT_ANCHORS = {
    { value = "TOPLEFT",     text = "Top left" },
    { value = "TOP",         text = "Top" },
    { value = "TOPRIGHT",    text = "Top right" },
    { value = "LEFT",        text = "Left" },
    { value = "CENTER",      text = "Centre" },
    { value = "RIGHT",       text = "Right" },
    { value = "BOTTOMLEFT",  text = "Bottom left" },
    { value = "BOTTOM",      text = "Bottom" },
    { value = "BOTTOMRIGHT", text = "Bottom right" },
}

-- Everything the two renderers need, resolved once and in one place.
--
-- There are two of them - Blizzard's adopted frames and our own drawn aura
-- cells - and they sit next to each other on the same bar. Any setting read
-- separately by each is a setting they will eventually disagree about, and
-- "these two icons look different and I cannot say why" is the exact bug
-- this whole styling pass exists to end.
--
-- Sizes of 0 are resolved HERE, so "auto" means the same thing on both.

-- One text element, with its automatic size worked out. autoScale is the
-- fraction of the cell height the element takes when its size is 0.
local function TextStyle(element, height, autoScale, floor, ceiling)
    element = element or {}
    local size = element.size or 0
    if size <= 0 then
        size = math.max(floor, math.min(ceiling, height * autoScale))
    end

    -- An empty font means "whatever Settings says", resolved HERE so no
    -- renderer has to know the rule and the two cannot disagree about it.
    local font = element.font
    if not font or font == "" then font = ns.db.font end

    return {
        show    = element.show ~= false,
        font    = font,
        size    = size,
        color   = element.color or { 1, 1, 1 },
        outline = element.outline or "",
        anchor  = element.anchor or "CENTER",
        x       = element.x or 0,
        y       = element.y or 0,
    }
end

-- The thresholds, cleaned up and SORTED ASCENDING.
--
-- Sorted here rather than trusted from the panel, because ascending order is
-- not a tidiness preference: the renderer stacks one overlay per threshold and
-- relies on the order being the draw order. An out-of-order list would leave a
-- lower threshold painting over a higher one, which reads as the colour simply
-- being wrong.
--
-- Returns a fresh list every time. The caller styles frames from it, and a
-- shared table would let one bar's edit reach another's.
function Bars:StackThresholds(cfg)
    local out = {}
    for _, entry in ipairs(cfg.stackThresholds or {}) do
        local value = tonumber(entry and entry.value)
        -- Whole numbers only, and at least 1: a stack count is never 0.5, and
        -- a threshold of 0 is crossed by an aura that is merely present.
        if value and value >= 1 then
            local colour = entry.color or { 0.85, 0.15, 0.15 }
            out[#out + 1] = {
                value = math.floor(value),
                color = { colour[1] or 0, colour[2] or 0, colour[3] or 0 },
                alpha = entry.alpha or 1,
            }
        end
    end

    table.sort(out, function(a, b) return a.value < b.value end)
    return out
end

-- How many lines divide N charges. Two charges have ONE boundary between
-- them, so it is N-1: drawing N puts a line on the end of the bar, where it
-- reads as a border rather than as a division.
--
-- In the model rather than beside the renderer so it can be checked, and so
-- the off-by-one has one home.
function Bars:ChargeDivisions(charges)
    local count = tonumber(charges)
    if not count or count < 2 then return 0 end
    return math.floor(count) - 1
end

-- What ONE CELL may wear differently from the bar it sits on.
--
-- Deliberately the look and nothing else. Rows, columns, spacing and the
-- arrangement describe the bar as a whole and cannot be per cell without
-- meaning something different; these are all "what does this rectangle look
-- like", which every cell can answer for itself.
--
-- Text is absent on purpose: three elements times seven controls is a panel
-- nobody can read, and a bar whose cells use four different fonts is not a
-- design. If one cell needs its own countdown, that is a real request and can
-- be added here - but it should be asked for rather than assumed.
ns.CELL_LOOK_KEYS = {
    "fillColor", "fillAlpha", "fillTexture", "fillSide", "fillGrow",
    "fillDirection",
    "borderSize", "borderColor", "borderTexture",
    "backdrop", "backdropColor", "backdropAlpha", "backdropTexture",
    "iconZoom", "swipeColor", "swipeAlpha",
    "showSpark", "chargeMarks", "chargeMarkColor",
    "stackThresholds",
}

-- The cell's own look, over the bar's.
--
-- A PROXY rather than a copy. Style only ever READS its config, so a table
-- that falls through to the bar costs one metatable instead of copying every
-- field of the bar on each call - and a field added to a bar tomorrow is
-- carried without this function being told about it. Both are true of a
-- rebuilt copy as well; the proxy is simply the cheaper way to be right.
function Bars:CellStyle(cfg, index, height)
    local opts = ns.Layout.CellOpts(cfg, index)
    local look = opts and opts.look

    -- The common case by far: no overrides, so the bar's own style is the
    -- answer and the caller's cache does its job.
    if not (look and next(look)) then return self:Style(cfg, height) end

    local proxy = setmetatable({}, { __index = cfg })
    for _, key in ipairs(ns.CELL_LOOK_KEYS) do
        if look[key] ~= nil then proxy[key] = look[key] end
    end
    return self:Style(proxy, height)
end

-- Whether this cell wears anything of its own. Used by the panel to show that
-- a cell has been changed without having to compare every value.
function Bars:CellHasLook(cfg, index)
    local opts = ns.Layout.CellOpts(cfg, index)
    return (opts and opts.look and next(opts.look)) ~= nil
end

-- Write one override. A nil value REMOVES it, which is how a control says
-- "follow the bar again" - and it is why nothing here stores a copy of the
-- bar's value as a default: a stored copy stops following.
function Bars:SetCellLook(cfg, index, key, value)
    if not cfg then return end

    if value == nil then
        local opts = ns.Layout.CellOpts(cfg, index)
        if not (opts and opts.look) then return end
        opts.look[key] = nil
        ns.Layout.TidyCellOpts(cfg, index)
        return
    end

    local opts = ns.Layout.EnsureCellOpts(cfg, index)
    opts.look = opts.look or {}
    opts.look[key] = value
end

-- Back to the bar's look entirely.
function Bars:ClearCellLook(cfg, index)
    local opts = ns.Layout.CellOpts(cfg, index)
    if not (opts and opts.look) then return false end
    opts.look = nil
    ns.Layout.TidyCellOpts(cfg, index)
    return true
end

function Bars:Style(cfg, height)
    height = height or 40

    return {
        height = height,

        borderSize    = math.max(0, cfg.borderSize or 1),
        borderColor   = cfg.borderColor or { 0, 0, 0 },
        borderTexture = cfg.borderTexture or "None",

        backdrop        = cfg.backdrop ~= false,
        backdropColor   = cfg.backdropColor or { 0, 0, 0 },
        backdropAlpha   = cfg.backdropAlpha or 0.9,
        backdropTexture = cfg.backdropTexture,

        iconZoom = math.min(0.2, math.max(0, cfg.iconZoom or 0.08)),

        inactiveAlpha      = cfg.inactiveAlpha or 0.55,
        inactiveDesaturate = cfg.inactiveDesaturate ~= false,

        swipeColor = cfg.swipeColor or { 0, 0, 0 },
        swipeAlpha = cfg.swipeAlpha or 0.7,
        showEdge   = cfg.showEdge and true or false,

        fillColor   = cfg.fillColor or { 1.00, 0.478, 0.239 },
        fillAlpha   = cfg.fillAlpha or 0.85,
        -- Empty means "whatever the backdrop is wearing", which is what keeps
        -- a bar looking like one object rather than two textures that happen
        -- to be next to each other.
        fillTexture = (cfg.fillTexture ~= "" and cfg.fillTexture)
            or cfg.backdropTexture,
        fillSide    = cfg.fillSide and true or false,
        fillGrow    = cfg.fillGrow and true or false,
        -- Resolved to the orientation and the reverse flag HERE, so the
        -- renderer never has to know the four names and the four names live
        -- in exactly one place.
        fillDirection = ns.Layout.FillDirection(cfg.fillDirection),

        showSpark       = cfg.showSpark and true or false,
        chargeMarks     = cfg.chargeMarks and true or false,
        chargeMarkColor = cfg.chargeMarkColor or { 0, 0, 0 },
        stackThresholds = self:StackThresholds(cfg),

        countdown = TextStyle(cfg.countdown, height, 0.42, 9, 20),
        stacks    = TextStyle(cfg.stacks,    height, 0.30, 8, 16),
        spellName = TextStyle(cfg.spellName, height, 0.45, 9, 14),
    }
end

function Bars:CaptureStyle(index)
    local cfg = self:Get(index)
    if not cfg then return nil end

    local style = {}
    for _, key in ipairs(ns.BAR_STYLE_KEYS) do
        style[key] = DeepCopy(cfg[key])
    end
    return style
end

function Bars:ApplyStyle(index, style)
    local cfg = self:Get(index)
    if not (cfg and style) then return false end

    for _, key in ipairs(ns.BAR_STYLE_KEYS) do
        if style[key] ~= nil then cfg[key] = DeepCopy(style[key]) end
    end

    -- A preset saved before a setting existed simply does not carry it, and
    -- the bar would be left with a hole where the renderer expects a value.
    ns.ApplyDefaults(cfg, ns.BAR_DEFAULTS)

    self:Changed(index)
    return true
end

function Bars:CopyStyleFrom(source, target)
    if source == target then return false end
    return self:ApplyStyle(target, self:CaptureStyle(source))
end

---------------------------------------------------------------------------
-- Looks that ship with the addon
--
-- Thirty-odd settings is what people ask for and none of them wants to build
-- a look out of thirty-odd settings from scratch. These are starting points:
-- pick one, then change the three things you disagree with.
--
-- They only carry what they are ABOUT. A look that also set sizes and spacing
-- would silently rearrange a bar you had already laid out, so grid, sizes and
-- spacing are left alone by every one of them.
---------------------------------------------------------------------------
local function Text(size, colour, outline, anchor)
    return { size = size, color = colour, outline = outline, anchor = anchor }
end

ns.BUILT_IN_LOOKS = {
    {
        name = "Clean",
        note = "One-pixel black edge, dark plate, white numbers. The default.",
        style = {
            borderSize = 1, borderColor = { 0, 0, 0 }, borderTexture = "None",
            backdrop = true, backdropColor = { 0, 0, 0 }, backdropAlpha = 0.9,
            iconZoom = 0.08,
            swipeColor = { 0, 0, 0 }, swipeAlpha = 0.7, showEdge = false,
            fillColor = { 1.00, 0.478, 0.239 }, fillAlpha = 0.85,
            fillTexture = "", fillSide = false, fillGrow = false,
            countdown = Text(0, { 1, 1, 1 }, "OUTLINE", "CENTER"),
            stacks    = Text(0, { 1, 1, 1 }, "OUTLINE", "BOTTOMRIGHT"),
            spellName = Text(0, { 1, 1, 1 }, "", "LEFT"),
            -- Explicitly empty, not absent: a look that says nothing about
            -- effects would leave the last one's flashing switched on, and
            -- "I picked Clean and it still pulses" is not a look at all.
            effects = {},
        },
    },
    {
        name = "Blizzard",
        note = "The whole icon including its own frame, no plate, no edge.",
        style = {
            borderSize = 0, borderColor = { 0, 0, 0 }, borderTexture = "None",
            backdrop = false, backdropColor = { 0, 0, 0 }, backdropAlpha = 0.9,
            iconZoom = 0,
            swipeColor = { 0, 0, 0 }, swipeAlpha = 0.8, showEdge = true,
            fillColor = { 1.00, 0.478, 0.239 }, fillAlpha = 0.80,
            fillTexture = "", fillSide = false, fillGrow = false,
            countdown = Text(0, { 1, 1, 1 }, "OUTLINE", "CENTER"),
            stacks    = Text(0, { 1, 1, 1 }, "OUTLINE", "BOTTOMRIGHT"),
            spellName = Text(0, { 1, 1, 1 }, "", "LEFT"),
            -- Explicitly empty, not absent: a look that says nothing about
            -- effects would leave the last one's flashing switched on, and
            -- "I picked Clean and it still pulses" is not a look at all.
            effects = {},
        },
    },
    {
        name = "Heavy",
        note = "Thick dark edge, tight crop, big outlined numbers. Reads at "
            .. "a glance in a fight.",
        style = {
            borderSize = 3, borderColor = { 0.02, 0.02, 0.03 }, borderTexture = "None",
            backdrop = true, backdropColor = { 0, 0, 0 }, backdropAlpha = 1,
            iconZoom = 0.12,
            swipeColor = { 0, 0, 0 }, swipeAlpha = 0.85, showEdge = false,
            fillColor = { 1.00, 0.478, 0.239 }, fillAlpha = 1.00,
            fillTexture = "", fillSide = false, fillGrow = false,
            countdown = Text(0, { 1, 1, 1 }, "THICKOUTLINE", "CENTER"),
            stacks    = Text(0, { 1, 0.9, 0.4 }, "THICKOUTLINE", "BOTTOMRIGHT"),
            spellName = Text(0, { 1, 1, 1 }, "OUTLINE", "LEFT"),
            effects = {},
        },
    },
    {
        name = "Reactive",
        note = "Clean, plus the things that move: a flash when a cooldown "
            .. "lands, an edge while it is up, and a nag if you sit on it.",
        style = {
            borderSize = 1, borderColor = { 0, 0, 0 }, borderTexture = "None",
            backdrop = true, backdropColor = { 0, 0, 0 }, backdropAlpha = 0.9,
            iconZoom = 0.08,
            swipeColor = { 0, 0, 0 }, swipeAlpha = 0.7, showEdge = false,
            fillColor = { 1.00, 0.478, 0.239 }, fillAlpha = 0.85,
            fillTexture = "", fillSide = false, fillGrow = false,
            countdown = Text(0, { 1, 1, 1 }, "OUTLINE", "CENTER"),
            stacks    = Text(0, { 1, 1, 1 }, "OUTLINE", "BOTTOMRIGHT"),
            spellName = Text(0, { 1, 1, 1 }, "", "LEFT"),
            effects = {
                readyFlash = true, readyPulses = 2,
                readyGlow = true, readyGlowCombatOnly = true,
                reminderAfter = 6,
                dimOnCooldown = true, dimAmount = 0.6,
            },
        },
    },
    {
        name = "Bare",
        note = "No edge, no plate, no numbers. Just the icons.",
        style = {
            borderSize = 0, borderColor = { 0, 0, 0 }, borderTexture = "None",
            backdrop = false, backdropColor = { 0, 0, 0 }, backdropAlpha = 0,
            iconZoom = 0.08,
            swipeColor = { 0, 0, 0 }, swipeAlpha = 0.6, showEdge = false,
            fillColor = { 1.00, 0.478, 0.239 }, fillAlpha = 0.50,
            fillTexture = "", fillSide = false, fillGrow = false,
            countdown = { show = false },
            stacks    = { show = false },
            spellName = { show = false },
            effects = {},
        },
    },
}

function Bars:ApplyLook(name, index)
    for _, look in ipairs(ns.BUILT_IN_LOOKS) do
        if look.name == name then
            return self:ApplyStyle(index, look.style)
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Presets
---------------------------------------------------------------------------
function Bars:SavePreset(name, index)
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return false end

    local style = self:CaptureStyle(index)
    if not style then return false end

    ns.db.barPresets[name] = style
    return true
end

function Bars:DeletePreset(name)
    if not ns.db.barPresets[name] then return false end
    ns.db.barPresets[name] = nil
    return true
end

-- Sorted, so the list does not reshuffle itself between openings - pairs()
-- over a string-keyed table has no order to speak of.
function Bars:PresetNames()
    local names = {}
    for name in pairs(ns.db.barPresets) do names[#names + 1] = name end
    table.sort(names)
    return names
end

function Bars:ApplyPreset(name, index)
    return self:ApplyStyle(index, ns.db.barPresets[name])
end

---------------------------------------------------------------------------
-- Anchoring one bar to another
--
-- Snapping puts a bar next to another one ONCE. Anchoring keeps it there:
-- move the one it hangs on and it comes along, resize the one it hangs on and
-- it stays flush. That is the difference between arranging a layout and
-- rearranging it every time you change your mind.
--
-- The relationship is stored on the CHILD, pointing at the parent's id, which
-- is why ids exist at all.
---------------------------------------------------------------------------
function Bars:NextID()
    local highest = ns.db.lastBarID or 0
    for _, cfg in ipairs(ns.db.bars) do
        if (cfg.id or 0) > highest then highest = cfg.id end
    end
    ns.db.lastBarID = highest + 1
    return ns.db.lastBarID
end

function Bars:ByID(id)
    if not id then return nil end
    for index, cfg in ipairs(ns.db.bars) do
        if cfg.id == id then return cfg, index end
    end
    return nil
end

-- Where a child sits relative to its parent. The two points are what an
-- anchor IS, so the sides are a table rather than four branches.
ns.ANCHOR_SIDES = {
    { key = "below", text = "Below",       point = "TOP",    relPoint = "BOTTOM", x = 0, y = -4 },
    { key = "above", text = "Above",       point = "BOTTOM", relPoint = "TOP",    x = 0, y =  4 },
    { key = "left",  text = "Left of",     point = "RIGHT",  relPoint = "LEFT",   x = -4, y = 0 },
    { key = "right", text = "Right of",    point = "LEFT",   relPoint = "RIGHT",  x =  4, y = 0 },
}

-- Would attaching child to parent make a loop? WoW raises a hard error on
-- circular anchors, so this is a guard rather than a nicety.
function Bars:WouldLoop(childID, parentID)
    local seen = {}
    local id = parentID

    while id do
        if id == childID then return true end
        if seen[id] then return true end
        seen[id] = true

        local cfg = self:ByID(id)
        id = cfg and cfg.anchor and cfg.anchor.to or nil
    end

    return false
end

function Bars:Anchor(index, parentID, sideKey)
    local cfg = self:Get(index)
    local parent = self:ByID(parentID)
    if not (cfg and parent) then return false end
    if cfg.id == parentID then return false end
    if self:WouldLoop(cfg.id, parentID) then return false end

    local side = ns.ANCHOR_SIDES[1]
    for _, candidate in ipairs(ns.ANCHOR_SIDES) do
        if candidate.key == sideKey then side = candidate break end
    end

    cfg.anchor = {
        to = parentID, side = side.key,
        point = side.point, relPoint = side.relPoint,
        x = side.x, y = side.y,
    }
    self:Changed(index)
    return true
end

-- Detaches, keeping the bar exactly where it is on screen. Reading the frame
-- back rather than restoring the old x/y: the old numbers are from before it
-- was attached, and dropping a bar somewhere it has not been for an hour is
-- the kind of surprise that makes people stop using a feature.
function Bars:Release(cfg)
    if not cfg or not cfg.anchor then return false end
    cfg.anchor = nil

    for index, candidate in ipairs(ns.db.bars) do
        if candidate == cfg then
            if ns.Screen then ns.Screen:CapturePosition(index) end
            self:Changed(index)
            break
        end
    end
    return true
end

---------------------------------------------------------------------------
-- Change notification
--
-- One place for "something about a bar changed", so the editor and the
-- on-screen rendering cannot drift apart.
---------------------------------------------------------------------------
local listeners = {}

function Bars:OnChanged(fn)
    listeners[#listeners + 1] = fn
end

function Bars:Changed(index)
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, index)
        if not ok then geterrorhandler()(err) end
    end
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

-- Seeds one bar on a fresh install so the editor has something to show
-- instead of an empty screen with a "New bar" button.
function Bars:Seed()
    if ns.db.barsSeeded then return end
    ns.db.barsSeeded = true
    if #ns.db.bars == 0 then
        self:Add("Cooldowns", "icon")
    end
end

---------------------------------------------------------------------------
-- Saved variables written by an older version
--
-- Runs once, before anything reads a bar. Kept next to Prepare because the
-- two are the same job - making a table on disk safe to use - and splitting
-- them across files is how a migration ends up running after the thing it was
-- supposed to fix.
---------------------------------------------------------------------------
function Bars:Migrate()
    local from = ns.db.dbVersion or 0

    -- 2 -> 3: the puzzle's positions move into fields of their own.
    --
    -- In a puzzle those numbers ARE positions, so they can be moved across
    -- with certainty. On any other arrangement the same fields are a nudge,
    -- and there is no way to tell a nudge somebody meant from one the old
    -- switch-to-puzzle left behind - so those are reported rather than
    -- guessed at, with the one action that clears them.
    if from < 3 then
        local strays = 0

        for _, cfg in ipairs(ns.db.bars) do
            if cfg.cellOpts then
                local free = (cfg.layout or "grid") == "free"
                for cell, opts in pairs(cfg.cellOpts) do
                    if free then
                        if opts.px == nil and opts.py == nil then
                            opts.px, opts.py = opts.x, opts.y
                        end
                        opts.x, opts.y = nil, nil
                    elseif (opts.x and opts.x ~= 0) or (opts.y and opts.y ~= 0) then
                        strays = strays + 1
                    end
                    ns.Layout.TidyCellOpts(cfg, cell)
                end
            end
        end

        if strays > 0 then
            ns.Print(string.format("%d cell%s carry an offset from an older "
                .. "version. If a bar looks scattered, open it and use "
                .. "|cffffd100Straighten|r under Arrangement.",
                strays, strays == 1 and "" or "s"))
        end
    end

    -- 3 -> 4: Arc and Diagonal are gone (owner, 2026-08-07: they threw errors
    -- and did not look good). A bar still naming one would otherwise fall
    -- through to the grid branch of the engine while its pattern picker showed
    -- nothing selected - so it is moved onto Grid properly, keeping the number
    -- of cells it had rather than the rows and columns it was ignoring.
    if from < 4 then
        local moved = 0

        for _, cfg in ipairs(ns.db.bars) do
            if cfg.layout == "arc" or cfg.layout == "diagonal" then
                local count = math.max(1, cfg.freeCount or 6)
                cfg.layout = "grid"
                cfg.columns = math.max(1, math.min(count, 12))
                cfg.rows = math.max(1, math.ceil(count / cfg.columns))
                moved = moved + 1
            end
            cfg.arcRadius, cfg.arcStart, cfg.arcSpan = nil, nil, nil
            cfg.diagonalX, cfg.diagonalY = nil, nil
        end

        if moved > 0 then
            ns.Print(string.format("Arc and Diagonal have been removed. %d bar%s "
                .. "moved onto Grid, with everything still on %s.",
                moved, moved == 1 and "" or "s", moved == 1 and "it" or "them"))
        end
    end

    -- 4 -> 5: the one fill setting becomes two.
    --
    -- Anybody who switched the old one on read its label - "grow from empty
    -- instead of draining away" - so that is what they meant, and that is
    -- where the value goes. What it actually DID was move the fill to the
    -- other end of the bar, which is the setting they did not ask for.
    if from < 5 then
        for _, cfg in ipairs(ns.db.bars) do
            if cfg.fillReverse ~= nil then
                if cfg.fillGrow == nil then cfg.fillGrow = cfg.fillReverse end
                cfg.fillReverse = nil
            end
        end
    end

    -- 5 -> 6: the spells move to a per-class-and-spec table. Nothing is done
    -- HERE, because the spec is not reliably known this early - the client
    -- can still answer 0 at ADDON_LOADED, and filing a character's picks
    -- under "DEATHKNIGHT:0" would hide them from the character that made
    -- them. Bars:BindSpec adopts them the first time a real spec identifies
    -- itself, which is that same character.

    ns.db.dbVersion = 6
end

function Bars:Prepare()
    for _, cfg in ipairs(ns.db.bars) do
        -- `fillSide` becomes one of four directions. BEFORE the defaults, not
        -- in Migrate: a bar that has already been through Migrate would come
        -- back here on the next login with no fillDirection, and ApplyDefaults
        -- would hand it "right" - quietly undoing a bar that filled from the
        -- other end. Replay-safe by construction: it only writes where the
        -- new key is still absent.
        if cfg.fillDirection == nil and cfg.fillSide ~= nil then
            cfg.fillDirection = cfg.fillSide and "left" or "right"
        end

        ns.ApplyDefaults(cfg, ns.BAR_DEFAULTS)
        if not cfg.id or cfg.id == 0 then cfg.id = self:NextID() end

        -- Bars written before there was a global font carry the old default
        -- spelled out on every text element, which would quietly ignore the
        -- new Settings choice. Same typeface either way, so nothing changes
        -- on screen - it just starts following.
        for _, element in ipairs(ns.TEXT_ELEMENTS) do
            local text = cfg[element.key]
            if text and text.font == "Friz Quadrata TT" then text.font = "" end
        end

        -- Anything sitting past the last cell is parked rather than left to
        -- be invisible for ever. A saved bar can hold one after a shrink in
        -- an older version, and an unreachable spell reads as a lost spell.
        self:Resized(cfg)
    end

    -- Two ways a saved anchor can be unusable, and both have to be caught
    -- before anything is drawn: a target that no longer exists leaves the bar
    -- with no position at all, and a loop is a hard error from the engine
    -- rather than a layout problem. Neither should be possible - a delete
    -- releases its children and the menu filters loops out - but saved
    -- variables are a file on disk, and files get edited.
    for _, cfg in ipairs(ns.db.bars) do
        if cfg.anchor then
            local target = self:ByID(cfg.anchor.to)
            if not target then
                cfg.anchor = nil
            elseif self:WouldLoop(cfg.id, cfg.anchor.to) then
                cfg.anchor = nil
                ns.Print("|cffff4040Dropped a circular attachment|r on bar "
                    .. (cfg.name or "?") .. ".")
            end
        end
    end
end
