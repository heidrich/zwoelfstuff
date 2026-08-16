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

    -- HOW MANY PLACES THE BAR HAS, AND IT IS ONE NUMBER.
    --
    -- `cellCount` is that number when it is set, and rows x columns when it
    -- is not - which is every bar written before this, so nothing moves.
    --
    -- The pair was the only way to say it and could only ever describe a
    -- RECTANGLE: six across meant six, twelve or eighteen, never seven. Owner,
    -- 2026-08-15: "feste cells und rows sollte man einstellen koennen". His
    -- own 4.82.0 bars already carry the number under `freeCount`, and the
    -- desk has been reporting "1 carry more cells than their width declares"
    -- since the audit - the shape was too narrow for his own profile.
    --
    -- `rows` stays READ, never written: Store translates, it does not
    -- migrate. A bar that has never met this page answers exactly as before.
    -- AN EXPLICIT COUNT IS THE HARD TRUTH, AND THAT IS THE ROW LIMIT.
    --
    -- Owner, 2026-08-15, with a picture of a bar he could not get down to one
    -- line: "ich muss auf eine reihe begrenzen koennen." He could not, and
    -- the reason was here: this used to answer with whichever was LARGEST of
    -- the declared number and the highest index anything was stored at. Set
    -- Rows to 1 on a bar carrying twelve picks and the bar went on drawing
    -- twelve, because the picks outvoted the setting. A limit that a stored
    -- value can overrule is not a limit.
    --
    -- NOTHING IS DELETED BY THIS. The picks stay exactly where they are and
    -- come back the moment there is room; Store.Parked below counts them and
    -- the page says the number out loud. That was the whole worry behind the
    -- generous answer - "seven of his picks are gone, with nothing said" -
    -- and saying it is the honest half of the fix rather than inflating the
    -- bar to hide it.
    local declared = tonumber(bar.cellCount)
    if declared then return math.max(0, math.floor(declared)) end

    -- NO EXPLICIT COUNT, WHICH IS EVERY BAR THAT HAS NEVER MET THIS PAGE.
    -- Those keep the generous answer to the letter, so nothing on his screen
    -- moves until he touches a control - and the first touch of Columns, Rows
    -- or Places writes the number and settles it for good.
    local rows = tonumber(bar.rows) or 1
    local columns = tonumber(bar.columns) or 1

    local most = math.max(rows * columns, Highest(bar.cells),
        Highest(bar.cellOpts))
    for _, list in pairs(type(bar.cellsBySpec) == "table" and bar.cellsBySpec or {}) do
        most = math.max(most, Highest(list))
    end
    return most
end

-- HOW MANY PICKS SIT PAST THE LAST PLACE.
--
-- The other half of the limit above: a bar narrowed below what it holds keeps
-- every spell, and a page that did not say so would look exactly like a page
-- that had thrown them away. Counted off the spec's own list, which is the
-- one the renderer draws from.
function Store.Parked(bar)
    if type(bar) ~= "table" then return 0 end

    local capacity = Store.Capacity(bar)
    local count = 0
    for index, spellID in pairs(Store.Cells(bar) or {}) do
        if type(index) == "number" and index > capacity and spellID ~= nil then
            count = count + 1
        end
    end
    return count
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
-- ONE PLACE'S OWN STYLING, AND THERE IS EXACTLY ONE RESOLVER FOR IT
--
-- WHAT THIS IS FOR, in his own report: he set a fill colour on "Buff Bar" and
-- two of its places ignored him without saying anything. Read out of his real
-- saved variables rather than reasoned about:
--
--     Buff Bar              fillColor = RED      {1.00, 0.05, 0.12}
--       cellOpts[1].look    fillColor = GREEN    {0.00, 1.00, 0.32}
--       cellOpts[2].look    fillColor = MAGENTA  {0.99, 0.05, 1.00}
--
-- Both readers were RIGHT: the renderer takes the place's own colour first and
-- the page's swatch shows the bar's. They disagree because they are different
-- things, and there was no way to see the place's value, no way to change it
-- and no mark saying a place carries one. "Die Farbvorschauen sind alle kacke"
-- is that, and not a broken swatch.
--
-- KEYED BY SPELL, NOT BY SLOT, and that is the decision this function exists to
-- carry. `cellOpts` is keyed by slot INDEX, so moving a spell one place along
-- leaves its styling behind on whatever lands there next - which is the thing
-- that actually breaks in play. `cellLook[spellID]` travels with the spell.
--
-- THREE LEVELS, IN THIS ORDER, and the middle one is READ AND NEVER WRITTEN:
--
--   1. bar.cellLook[spellID]      ours, what the per-place editor writes
--   2. bar.cellOpts[index].look   4.82.0's, his real settings, read-only
--   3. bar[key]                   the bar
--
-- ONE RESOLVER AND NOT TWO. There were two - Look's own `Chosen` and
-- Fill.Option - and both of their headers say in as many words that they must
-- MOVE here rather than be joined by a third. A second copy of a precedence
-- rule is a copy that goes stale, and this one decides what colour something
-- is: the day they disagree, half a bar wears one answer and half the other.
---------------------------------------------------------------------------

-- The two tables that can override a bar key for one place, newest first, or
-- nil for each that is not there. ALLOCATES NOTHING - it hands back what is
-- stored rather than a merge of it, which is what lets the resolver below be
-- asked once per key without building a table per cell per pass.
local function Overrides(bar, index)
    if not index then return nil, nil end

    -- WHICH SPELL SITS HERE NOW, asked of the bar rather than passed in. It is
    -- the same answer - the caller would have read it out of this same list -
    -- and asking here is what keeps every call site speaking (bar, index) as
    -- it always has.
    --
    -- ASKED ONLY OF A BAR THAT CARRIES PER-SPELL STYLING, which is none of his
    -- today. Store.Cells goes through ns.SpecStore, and SpecStore FILES a
    -- per-spec copy on first read - a write, on a path that is nothing but a
    -- read, and one that would now run for every key of every place on every
    -- pass. The `cellLook` test in front of it costs one table lookup and
    -- leaves a bar that has none exactly as it was.
    local mine
    if type(bar.cellLook) == "table" then
        local spellID = Store.Cells(bar)[index]
        if spellID ~= nil then mine = bar.cellLook[spellID] end
    end

    local opts = type(bar.cellOpts) == "table" and bar.cellOpts[index] or nil
    local was = type(opts) == "table" and opts.look or nil

    return type(mine) == "table" and mine or nil,
        type(was) == "table" and was or nil
end

-- ONE VALUE FOR ONE PLACE. `index` is optional: without it this is the bar's
-- own answer, which is what a place carrying no styling of its own wears.
--
-- NOT `mine[key] or was[key] or bar[key]`. Every level here can legally hold
-- `false` - "no spark on this one", "no charge marks on that one" - and `x and
-- y or z` cannot carry a false. That idiom has cost this project two settings
-- that could not be switched off; the comparison is against nil, three times.
function Store.Option(bar, index, key)
    if type(bar) ~= "table" then return nil end

    local own, carried = Store.Own(bar, index, key)
    if carried then return own end
    return bar[key]
end

-- WHAT THIS PLACE ANSWERS FOR ITSELF, and WHETHER it answers at all.
--
-- Two returns rather than one, for the same reason the comparisons above are
-- against nil: `false` is a real answer at every level - "no spark on this
-- one" - and a single return cannot tell it apart from "this place says
-- nothing". A caller that folded them together would show a mark on a place
-- carrying nothing, or none on a place that had switched something off.
--
-- It is the reader behind the mark the owner asked for ("wo sehe ich denn,
-- wenn ich einzelne bars oder icons style? ich sehe da keinen indikator"), and
-- behind a per-place "follow the bar again": what that button clears is
-- exactly what this returns.
function Store.Own(bar, index, key)
    if type(bar) ~= "table" then return nil, false end

    local mine, was = Overrides(bar, index)
    if mine and mine[key] ~= nil then return mine[key], true end
    if was and was[key] ~= nil then return was[key], true end
    return nil, false
end

-- WHICH WAY A FILL RUNS, IN ONE PLACE, INCLUDING THE OLD KEY
--
-- 4.82.0 stored `fillSide`, a true/false "does it run left", and the control
-- that replaced it has four answers. Store TRANSLATES rather than migrates -
-- the bar on disk keeps the key it was written with - so the translation has
-- to happen on every read, and this is the read.
--
-- IT IS HERE BECAUSE THERE ARE TWO ASKERS AND THEY HAD DIFFERENT ANSWERS.
-- Fill.Direction carried the fallback and Look.Style did not, so the same bar
-- ran one way on the screen and the other way in the style table - on exactly
-- the bars written before the new control, which is every bar he made in
-- 4.82.0. Neither file can capture the other (Look loads above Fill), and the
-- one thing above both of them is this.
function Store.FillDirection(bar, index)
    local named = Store.Option(bar, index, "fillDirection")
    if named == nil then
        -- NOT `x and "left" or "right"` as a shortcut for the missing case:
        -- the old key is a real boolean and false means right, which is the
        -- answer this idiom throws away everywhere else in this addon. Here it
        -- is safe only because both halves are strings and neither is false -
        -- said out loud so the next reader does not copy it somewhere it is
        -- not.
        named = Store.Option(bar, index, "fillSide") and "left" or "right"
    end
    return ns.Layout.FillDirection(named)
end

-- DOES THIS PLACE CARRY ANY STYLING OF ITS OWN?
--
-- Owner, with the page open: "wo sehe ich denn, wenn ich einzelne bars oder
-- icons style? ich sehe da keinen indikator." There is no mark yet and this is
-- what one is drawn from - the preview cell and the block being edited both
-- need the same answer, and two ways of asking it is how they come to disagree.
--
-- It is also the fast path for a whole-look read: a place with nothing of its
-- own is the bar, and copying eighteen keys to say so is work for nothing.
function Store.Overridden(bar, index)
    if type(bar) ~= "table" then return false end

    local mine, was = Overrides(bar, index)
    if mine and next(mine) ~= nil then return true end
    if was and next(was) ~= nil then return true end
    return false
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
        "id", "name", "enabled", "kind", "columns", "rows", "cellCount",
        "layout", "flow",
        "growX", "growY", "point", "relPoint", "x", "y", "scale", "pinned",
        "staggerOffset",

        -- What is on it. `cellOpts` is 4.82.0's per-SLOT styling, read and
        -- never rewritten; `cellLook` is the same idea keyed by SPELL, so a
        -- place's styling travels when the spell is moved. Store.Option is the
        -- one reader of both.
        "cells", "cellsBySpec", "cellOpts", "cellLook",

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

        -- The trough under the fill, wave 6. Absent from every bar written
        -- before it, which is why it defaults to OFF rather than to a colour.
        "fillBack", "fillBackAlpha", "fillBackColor",
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
