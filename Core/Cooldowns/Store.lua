---------------------------------------------------------------------------
-- Reading the bars that are still in his profile.
--
-- THE PROMISE MADE WHEN THE BARS WERE CUT: nothing was deleted from anybody's
-- settings. `bars`, `barPresets`, `cellsBySpec`, `parkedBySpec`, `barsSeeded`,
-- `takeOverCDM` and `lastBarID` are all exactly where 4.82.0 left them. A
-- rebuild that cannot read them back is a rebuild that loses his layouts.
--
-- SO THIS TRANSLATES. IT DOES NOT MIGRATE.
--
-- The first plan for this file was a migration: read the old shape once,
-- write a new one, leave the old keys alone. That is one more copy of the
-- truth than the job needs, and the copy is the thing that goes stale. This
-- reads the stored bar as it stands and hands out what each reader wants -
-- so nothing is rewritten, nothing can be lost in the rewriting, and an older
-- version of the addon still finds a profile it understands. The `cellsWere`
-- key on the request panel already works this way and for the same reason.
--
-- MEASURED AGAINST HIS ACTUAL FILE, not against the defaults table. The plan
-- said "about a hundred keys per bar"; the profile on disk carries 64 across
-- four bars, and `locked` is on two of them and not the other two. A reader
-- written against the defaults would have been written against a bar nobody
-- has.
---------------------------------------------------------------------------
local _, ns = ...

local Cooldowns = ns.Cooldowns
local Store = {}
Cooldowns.Store = Store

---------------------------------------------------------------------------
-- THE CELL LIST, AND WHY # IS NEVER USED ON IT
--
-- The case that DOES bite, measured: his file has a bar declaring five
-- columns in one row - room for five - and a cell list twelve long. Trust the
-- declared number and seven of his picks are gone, with nothing said. So the
-- capacity is whichever is largest of what the bar declares and what anything
-- actually references.
--
-- The case that MIGHT bite, stated honestly because the desk says it does not
-- today: a stored cell list has holes in it -
--
--     ["cells"] = { 1044, nil, 102342, 633, 47788, ... }
--
-- and a hole is the normal case, a bar somebody arranged with a gap. Lua's
-- `#` on a table with a hole may answer at the hole or past it; both are
-- correct by the language's own definition. Run against his real file the
-- guard reports zero lists where `#` disagrees with the highest index, so
-- this has never actually cost him a pick. It is avoided anyway: the answer
-- is undefined rather than merely unlikely, and the failure it would produce
-- is silent.
---------------------------------------------------------------------------

-- The highest index anything is stored at, holes ignored.
local function Highest(list)
    local top = 0
    if type(list) ~= "table" then return top end
    for index in pairs(list) do
        if type(index) == "number" and index > top then top = index end
    end
    return top
end

function Store.Capacity(bar)
    if type(bar) ~= "table" then return 0 end

    local rows = tonumber(bar.rows) or 1
    local columns = tonumber(bar.columns) or 1
    local declared = math.max(0, math.floor(rows * columns))

    local most = math.max(declared, Highest(bar.cells), Highest(bar.cellOpts))
    for _, list in pairs(type(bar.cellsBySpec) == "table" and bar.cellsBySpec or {}) do
        most = math.max(most, Highest(list))
    end
    return most
end

-- THE PICKS FOR THE SPEC BEING PLAYED.
--
-- ns.SpecStore, given the bar as its owner - the third argument it gained for
-- this. One bar's picks are not the next bar's, so the store cannot sit at
-- the top of the profile the way the reminders' does.
--
-- It answers nil while the client has not said which spec this is, and that
-- is not a case to paper over: filing a pick under "WARRIOR:0" puts it in a
-- bin nothing ever reads. The shared list is handed back for that moment,
-- read-only in practice, exactly as the other callers do.
function Store.Cells(bar)
    if type(bar) ~= "table" then return {} end
    local mine = ns.SpecStore("cellsBySpec", bar.cells, bar)
    return mine or bar.cells or {}
end

---------------------------------------------------------------------------
-- The lattice, in the words Model.lua speaks
--
-- Two vocabularies meet here and this is the only place they touch. The bar
-- says `iconSize` and `staggerOffset`; the model says `size` and `stagger`.
-- Renaming the stored keys would have been the tidier-looking answer and
-- would have rewritten his profile to gain nothing.
--
-- THE ONE CONVERSION THAT MATTERS: staggerOffset is stored as a PERCENTAGE.
-- Every bar in his file says 50. The model takes a fraction of one step, so
-- 50 means 0.5 - and a model handed 50 would shift the second row fifty cells
-- to the right, which draws nothing on screen at all and reads as "the
-- staggered layout is broken" rather than as a unit.
---------------------------------------------------------------------------
-- The value 4.82.0 stored for the staggered layout, and the one this model
-- says. A rename with no translation is the quietest bug there is: the source
-- reads correctly, the stored bar reads correctly, and the comparison between
-- them is false - so a staggered bar draws as a plain grid and nothing
-- anywhere says why. None of his four bars is staggered today, which is
-- precisely why this would have gone unnoticed until somebody imported one
-- from a shared string.
local LAYOUTS = { stagger = "staggered" }

function Store.Lattice(bar)
    bar = type(bar) == "table" and bar or {}

    local percent = tonumber(bar.staggerOffset)

    -- A CELL IS NOT ALWAYS A SQUARE, and one of his bars is the proof.
    --
    -- `kind` is "icon" or "bar". An icon cell is iconSize square; a bar cell
    -- is a StatusBar, barWidth by barHeight. His "Bars 2" is kind="bar",
    -- 250 by 24, and carries iconSize 40 as an untouched default - so a
    -- reader that looks at iconSize and never at kind hands the model four
    -- forty-pixel squares for a bar a quarter of the screen wide. It would
    -- have drawn something, which is the problem.
    local size, width
    if bar.kind == "bar" then
        size = tonumber(bar.barHeight) or 24
        width = tonumber(bar.barWidth) or 200
    else
        size = tonumber(bar.iconSize) or 32
    end

    local spacing = tonumber(bar.spacing) or 4
    return {
        columns = tonumber(bar.columns) or 1,
        size    = size,
        width   = width,
        spacing = spacing,
        -- Two gaps, not one. See Model's FIELDS: two of his bars carry a row
        -- gap different from their column gap, and on the single-column one
        -- it is the only gap it has.
        lineSpacing = tonumber(bar.lineSpacing) or spacing,
        layout  = LAYOUTS[bar.layout] or bar.layout,
        flow    = bar.flow,
        growX   = bar.growX,
        growY   = bar.growY,
        stagger = percent and (percent / 100) or nil,
    }
end

---------------------------------------------------------------------------
-- WHAT NOTHING READS YET
--
-- The rebuild lands in waves, so at any moment most of a stored bar is
-- settings no code has been written for again. That is fine and it is also
-- exactly how a key gets quietly lost: it stops being read, nobody notices,
-- and three versions later somebody "tidies up" a profile key that a user's
-- layout depends on.
--
-- So the readers are declared, and everything else is REPORTED rather than
-- assumed dead. /zs cdm says what is carried and what is still waiting, and
-- the number falling is what progress looks like.
--
-- Grouped by the wave that will claim them, from CDM-PLAN.md §9. A key in no
-- group at all is the interesting one: it is either new or it is orphaned,
-- and the report names it separately for that reason.
---------------------------------------------------------------------------
Store.READERS = {
    -- READ TODAY, by Model, by Store, by Render and by the four files of
    -- waves 4 and 5. It started as thirteen keys and it is the whole bar bar
    -- six, which is what progress looks like here: the number that falls is
    -- the point of this table existing.
    now = {
        -- The bar itself, and where it sits.
        "id", "name", "enabled", "kind", "columns", "rows", "layout", "flow",
        "growX", "growY", "point", "relPoint", "x", "y", "scale", "pinned",
        "staggerOffset",

        -- What is on it.
        "cells", "cellsBySpec", "cellOpts",

        -- HOW BIG ONE CELL IS AND HOW FAR THE NEXT ONE. Every one of these
        -- reads like styling and is GEOMETRY, and every one of them was
        -- filed under a later wave until an audit against his own four bars
        -- moved it: without barWidth and barHeight the model cannot answer at
        -- all for his "Bars 2", and without lineSpacing it answers WRONGLY -
        -- which is worse - for two of them.
        "iconSize", "spacing", "lineSpacing", "barWidth", "barHeight",
        "iconPlacement",

        -- The look, wave 4.
        "alpha", "backdrop", "backdropAlpha", "backdropColor",
        "backdropGradient", "backdropTexture", "borderColor",
        "borderGradient", "borderSize", "borderTexture", "iconZoom",
        "inactiveAlpha", "inactiveDesaturate", "showEdge", "swipeAlpha",
        "swipeColor",

        -- The text, wave 4.
        "countdown", "stacks", "charges", "spellName",

        -- The states and the effects, wave 4.
        "effects", "show",

        -- The fill of a tracking bar, wave 5.
        "fillAlpha", "fillColor", "fillDirection", "fillGradient", "fillGrow",
        "fillSide", "fillTexture", "showSpark", "chargeMarks",
        "chargeMarkColor", "stackThresholds",
    },

    -- WHAT NOTHING READS YET, and there are six left.
    --
    -- Five of them are one feature: the free-form puzzle layout, where a bar
    -- has no lattice at all and every cell carries its own x and y.
    -- `freeCount` is its length, `raster` is what a dragged cell snaps to,
    -- and `parked`/`parkedBySpec` are the cells taken off it. His first bar
    -- carries ten `cellOpts` for five cells, left over from when it was
    -- wider, so this is not hypothetical for him.
    --
    -- `anchor` is the sixth and it is on its own: `{ to = <barID> }`, one bar
    -- hung off another. He has never used it - which is exactly why it needed
    -- a guard that reads 4.82.0's SHIPPED DEFAULTS rather than his profile to
    -- surface it at all. Deleting a bar already releases its followers (see
    -- Cooldowns/Bars.lua); what is missing is anything that READS it to place
    -- one, plus the circular-reference check that owes somebody who is not him.
    --
    -- `locked` is deliberately NOT here: 4.82.0's own defaults call it a dead
    -- field from an older shape, replaced by `pinned`, and it survives on two
    -- of his four bars as a fossil. Naming it as "waiting" would be a promise
    -- to read something that never meant anything.
    later = {
        "freeCount", "raster", "parked", "parkedBySpec", "anchor",
        "locked",
    },
}

local claimedBy
local function Claims()
    if claimedBy then return claimedBy end
    claimedBy = {}
    for wave, keys in pairs(Store.READERS) do
        for _, key in ipairs(keys) do claimedBy[key] = wave end
    end
    return claimedBy
end

-- Every key on this bar, and which wave answers for it. `unknown` is the list
-- worth reading: a key nothing has ever claimed.
function Store.Survey(bar)
    local by = Claims()
    local out, unknown = {}, {}
    for key in pairs(type(bar) == "table" and bar or {}) do
        local wave = by[key]
        if wave then
            out[wave] = out[wave] or {}
            out[wave][#out[wave] + 1] = key
        else
            unknown[#unknown + 1] = key
        end
    end
    for _, list in pairs(out) do table.sort(list) end
    table.sort(unknown)
    return out, unknown
end

---------------------------------------------------------------------------
-- The bars themselves
---------------------------------------------------------------------------

-- Every stored bar, or an empty list. Never creates the table: a profile
-- that has never had a bar should not grow one by being asked about.
function Store.Bars()
    local db = ns.db
    return (db and type(db.bars) == "table") and db.bars or {}
end

function Store.Count()
    local count = 0
    for _ in pairs(Store.Bars()) do count = count + 1 end
    return count
end

-- One bar by its stored id, which is not its position in the list.
function Store.ByID(id)
    for _, bar in pairs(Store.Bars()) do
        if type(bar) == "table" and bar.id == id then return bar end
    end
    return nil
end
