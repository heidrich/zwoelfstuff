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
    -- Read today, by Model and by this file.
    now = {
        "id", "name", "enabled", "kind", "columns", "rows", "layout", "flow",
        "growX", "growY", "iconSize", "spacing", "staggerOffset",
        "cells", "cellsBySpec", "cellOpts",
        -- MOVED UP FROM `placement` after an audit against his own bars.
        -- Filing these under a later wave was the mistake: they are not
        -- where a bar SITS, they are how big one of its cells is and how far
        -- the next row is. The model cannot answer at all for his "Bars 2"
        -- without barWidth and barHeight, and it answers WRONGLY - which is
        -- worse - for two of his bars without lineSpacing.
        "lineSpacing", "barWidth", "barHeight",
        -- MOVED UP FROM `look` in wave 2, and it is the same correction a
        -- third time. `iconPlacement` reads like styling and is geometry: it
        -- decides where an ICON-shaped frame sits inside a BAR-shaped slot,
        -- and the alternative to answering it is stretching a square across
        -- 250 pixels. Filed under the look wave, that would have shipped.
        "iconPlacement",
        -- Wave 2 reads these because they are where the bar IS. The rest of
        -- `placement` is about being MOVED, which is the editor's wave.
        "point", "relPoint", "x", "y", "scale",
    },
    -- Wave 2, Claim and Render: where the bar sits.
    --
    -- `anchor` is here because a guard found it, not because anybody
    -- remembered it. None of his four bars carries the key - he has never
    -- hung one bar off another - so the check that reads his profile could
    -- never have surfaced it. The one that reads 4.82.0's shipped defaults
    -- did, on its first run. It is `{ to = <barID>, ... }`, it is released
    -- when its target bar is deleted, and it is validated on load against
    -- circular references; all of that is real work that wave 2 owes
    -- somebody who is not him.
    placement = {
        "pinned", "locked", "freeCount", "parked", "parkedBySpec", "raster",
        "anchor",
    },
    -- Wave 4, the look.
    look = {
        "alpha", "backdrop", "backdropAlpha", "backdropColor",
        "backdropGradient", "backdropTexture", "borderColor",
        "borderGradient", "borderSize", "borderTexture", "fillAlpha",
        "fillColor", "fillDirection", "fillGradient", "fillGrow", "fillSide",
        "fillTexture", "iconPlacement", "iconZoom", "inactiveAlpha",
        "inactiveDesaturate", "showEdge", "showSpark", "spellName",
        "swipeAlpha", "swipeColor",
        -- `iconPlacement` used to be here. It is geometry - see `now`.
    },
    -- Wave 4 as well, but they are states rather than colours.
    effects = {
        "effects", "charges", "chargeMarks", "chargeMarkColor", "countdown",
        "stacks", "stackThresholds", "show",
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
