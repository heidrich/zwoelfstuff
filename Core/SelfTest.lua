---------------------------------------------------------------------------
-- SelfTest - /zs test
--
-- WHY AN ADDON SHIPS ITS OWN TEST SUITE.
--
-- Nothing in here can be run outside the game. There is no WoW without a
-- client, so a rule about arrangement geometry either gets checked where the
-- code actually runs or it gets checked by a person squinting at a screenshot
-- and reporting "sieht strange aus". This file is the first option.
--
-- It answers the questions a screenshot cannot: does switching pattern and
-- switching back give you what you had, does the Columns slider lose a spell,
-- does the editor's explanation agree with the rule the renderer applies.
-- Every one of those has been a real bug in this addon.
--
-- IT NEVER TOUCHES YOUR BARS.
--
-- Every model test runs on a throwaway config built from BAR_DEFAULTS, which
-- is why Bars carries Reshape/Relayout next to SetGrid/SetLayout: the model
-- operation takes a config, and only the wrapper needs an index. A test that
-- has to create a real bar is a test that eventually leaves one behind.
--
-- The checks against YOUR data are read-only and say so.
---------------------------------------------------------------------------
local _, ns = ...

local Test = {}
ns.SelfTest = Test

local passed, failed, notes

local function Check(name, ok, detail)
    if ok then
        passed = passed + 1
        return true
    end
    failed[#failed + 1] = detail and (name .. "  |cff888888" .. detail .. "|r")
        or name
    return false
end

-- Something the test could not judge either way. Reported separately, because
-- a suite that silently skips is a suite that reports green while covering
-- nothing.
local function Skip(name, why)
    notes[#notes + 1] = name .. "  |cff888888" .. why .. "|r"
end

local function Near(a, b, tolerance)
    return math.abs((a or 0) - (b or 0)) <= (tolerance or 0.01)
end

local function Finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

-- A bar nobody owns. Filled from the same defaults a real one gets, so a
-- setting added tomorrow is in the test the same day.
local function Fresh(overrides)
    local cfg = ns.ApplyDefaults({}, ns.BAR_DEFAULTS)
    cfg.cellOpts = {}
    -- Bound the way BindSpec binds a real one, so the throwaway bar has the
    -- same shape as the thing under test rather than a simpler one.
    cfg.cellsBySpec = { test = {} }
    cfg.parkedBySpec = { test = {} }
    cfg.cells = cfg.cellsBySpec.test
    cfg.parked = cfg.parkedBySpec.test
    for key, value in pairs(overrides or {}) do cfg[key] = value end
    return cfg
end

local function Slots(cfg)
    return ns.Layout.Build(cfg, ns.Bars:CellCount(cfg),
        cfg.spacing or 4, cfg.lineSpacing or 4)
end

-- Two arrangements, compared cell by cell. The whole point of the round-trip
-- tests below, so it lives in one place.
local function SameGeometry(a, b)
    if #a ~= #b then return false, string.format("%d cells vs %d", #a, #b) end
    for index = 1, #a do
        if not (Near(a[index].x, b[index].x) and Near(a[index].y, b[index].y)
            and Near(a[index].w, b[index].w) and Near(a[index].h, b[index].h)) then
            return false, string.format("cell %d moved from %.1f,%.1f to %.1f,%.1f",
                index, a[index].x, a[index].y, b[index].x, b[index].y)
        end
    end
    return true
end

---------------------------------------------------------------------------
-- The arrangements
---------------------------------------------------------------------------
local function TestLayout()
    for _, entry in ipairs(ns.LAYOUTS) do
        local cfg = Fresh({ layout = entry.value, rows = 2, columns = 3,
            freeCount = 6 })

        local slots, box = Slots(cfg)
        local count = ns.Bars:CellCount(cfg)

        Check(entry.text .. ": returns one slot per cell", #slots == count,
            string.format("%d slots for %d cells", #slots, count))

        local sane, contained = true, true
        for _, slot in ipairs(slots) do
            if not (Finite(slot.x) and Finite(slot.y)
                and Finite(slot.w) and Finite(slot.h)) then
                sane = false
            end
            if not slot.hidden then
                -- Every visible cell has to be inside the frame the renderer
                -- is told to make. A cell outside it is drawn beyond the edge
                -- of the thing you can grab in unlock mode.
                if slot.x - slot.w / 2 < box.centreX - box.width / 2 - 0.01
                    or slot.x + slot.w / 2 > box.centreX + box.width / 2 + 0.01
                    or slot.y - slot.h / 2 < box.centreY - box.height / 2 - 0.01
                    or slot.y + slot.h / 2 > box.centreY + box.height / 2 + 0.01 then
                    contained = false
                end
            end
        end

        Check(entry.text .. ": every number is real", sane)
        Check(entry.text .. ": the box holds every cell", contained)
    end

    -- Spacing, on the one arrangement where it is arithmetic anybody can
    -- check by hand. Neighbours in a row sit exactly one cell plus one gap
    -- apart - not "about", which is how an off-by-a-border creeps in.
    local grid = Fresh({ layout = "grid", rows = 1, columns = 4,
        iconSize = 40, spacing = 6, scale = 1 })
    local slots = Slots(grid)
    Check("Grid: neighbours are cell + spacing apart",
        Near(slots[2].x - slots[1].x, 46),
        string.format("%.1f, expected 46", slots[2].x - slots[1].x))

    -- Scale multiplies the cell AND the gap, or a scaled bar is a bar with
    -- the wrong spacing.
    local scaled = Fresh({ layout = "grid", rows = 1, columns = 4,
        iconSize = 40, spacing = 6, scale = 2 })
    local scaledSlots = ns.Layout.Build(scaled, 4, (scaled.spacing or 4) * 2,
        (scaled.lineSpacing or 4) * 2)
    Check("Grid: scale multiplies cell and gap alike",
        Near(scaledSlots[2].x - scaledSlots[1].x, 92),
        string.format("%.1f, expected 92", scaledSlots[2].x - scaledSlots[1].x))

    -- Staggered pushes every other LINE and leaves the first one alone.
    local stagger = Fresh({ layout = "stagger", rows = 2, columns = 3,
        iconSize = 40, spacing = 6, staggerOffset = 50 })
    local staggerSlots = Slots(stagger)
    Check("Staggered: the first line is not moved",
        Near(staggerSlots[1].x, 20), string.format("%.1f", staggerSlots[1].x))
    Check("Staggered: the second line is pushed by half a cell",
        Near(staggerSlots[4].x - staggerSlots[1].x, 23),
        string.format("%.1f, expected 23", staggerSlots[4].x - staggerSlots[1].x))

    -- Arc and Diagonal are GONE, and a saved bar naming one must not quietly
    -- come out as something with the right cell count and the wrong shape.
    for _, dead in ipairs({ "arc", "diagonal" }) do
        local gone = true
        for _, entry in ipairs(ns.LAYOUTS) do
            if entry.value == dead then gone = false end
        end
        Check("'" .. dead .. "' is no longer offered", gone)
    end
end

---------------------------------------------------------------------------
-- The two coordinate systems
--
-- This is the bug that was reported: entering the puzzle wrote positions into
-- the same fields a nudge uses, and every other arrangement then added them
-- for ever. These four checks are the guard on that never coming back.
---------------------------------------------------------------------------
local function TestOffsets()
    local grid = Fresh({ layout = "grid", rows = 1, columns = 3 })
    local plain = Slots(grid)

    -- A puzzle position must be invisible to a grid.
    ns.Layout.EnsureCellOpts(grid, 2).px = 500
    ns.Layout.EnsureCellOpts(grid, 2).py = -500
    local withPuzzlePos = Slots(grid)
    local clean, why = SameGeometry(plain, withPuzzlePos)
    Check("A grid ignores the puzzle's positions", clean, why)

    -- ...and a nudge must be invisible to a puzzle.
    local puzzle = Fresh({ layout = "free", freeCount = 3 })
    ns.Layout.EnsureCellOpts(puzzle, 2).x = 500
    ns.Layout.EnsureCellOpts(puzzle, 2).y = -500
    local puzzleSlots = Slots(puzzle)
    Check("A puzzle ignores the lattice nudges",
        Near(puzzleSlots[2].x, 0) and Near(puzzleSlots[2].y, 0),
        string.format("%.1f,%.1f", puzzleSlots[2].x, puzzleSlots[2].y))

    -- The nudge itself still works where it is supposed to.
    local nudged = Fresh({ layout = "grid", rows = 1, columns = 3 })
    ns.Layout.SetOffset(nudged, 2, 17, -9)
    local nudgedSlots = Slots(nudged)
    Check("A nudge moves its cell and only its cell",
        Near(nudgedSlots[2].x, plain[2].x + 17)
        and Near(nudgedSlots[2].y, plain[2].y - 9)
        and Near(nudgedSlots[1].x, plain[1].x))

    -- Straightening clears the pair in use and leaves the other one alone.
    local both = Fresh({ layout = "grid", rows = 1, columns = 3 })
    ns.Layout.SetOffset(both, 2, 17, -9)
    both.layout = "free"
    ns.Layout.SetOffset(both, 2, 40, 40)
    both.layout = "grid"

    Check("Straighten sees a scattered grid", ns.Layout.HasOffsets(both))
    ns.Layout.ClearOffsets(both)
    Check("Straighten clears the grid's nudges",
        not ns.Layout.HasOffsets(both))
    both.layout = "free"
    Check("Straightening a grid leaves the puzzle alone",
        ns.Layout.HasOffsets(both))
end

---------------------------------------------------------------------------
-- Switching pattern, and switching back
---------------------------------------------------------------------------
local function TestPatternRoundTrip()
    for _, entry in ipairs(ns.LAYOUTS) do
        if entry.value ~= "free" then
            local cfg = Fresh({ layout = entry.value, rows = 2, columns = 3,
                freeCount = 6 })
            local before = Slots(cfg)

            ns.Bars:Relayout(cfg, "free")
            ns.Bars:Relayout(cfg, entry.value)
            local after = Slots(cfg)

            local ok, why = SameGeometry(before, after)
            Check(entry.text .. ": survives a trip through the puzzle", ok, why)
        end
    end

    -- The puzzle starts as what you were just looking at, whatever that was.
    -- Staggered, because it is the one left whose slots a rows-and-columns
    -- loop would NOT reproduce - which is exactly the mistake this catches.
    local shaped = Fresh({ layout = "stagger", rows = 2, columns = 3 })
    local before = Slots(shaped)
    ns.Bars:Relayout(shaped, "free")
    local puzzleSlots = Slots(shaped)

    local ok, why = SameGeometry(before, puzzleSlots)
    Check("The puzzle opens on the arrangement you left", ok, why)

    -- And coming back to a puzzle finds it as it was left, not re-seeded.
    ns.Layout.SetOffset(shaped, 1, 123, 45)
    ns.Bars:Relayout(shaped, "grid")
    ns.Bars:Relayout(shaped, "free")
    local x, y = ns.Layout.GetOffset(shaped, 1)
    Check("A puzzle you already built is not re-seeded",
        Near(x, 123) and Near(y, 45), string.format("%.0f,%.0f", x, y))
end

---------------------------------------------------------------------------
-- The rows and columns sliders
---------------------------------------------------------------------------
local function TestGridSliders()
    -- A hole in the middle is a deliberate arrangement, not a gap to close.
    local cfg = Fresh({ layout = "grid", rows = 1, columns = 6 })
    cfg.cells = { [1] = 101, [2] = 102, [4] = 104, [5] = 105, [6] = 106 }

    ns.Bars:ReshapeGrid(cfg, 1, 12)
    ns.Bars:ReshapeGrid(cfg, 1, 6)

    local same = cfg.cells[1] == 101 and cfg.cells[2] == 102
        and cfg.cells[3] == nil and cfg.cells[4] == 104
        and cfg.cells[5] == 105 and cfg.cells[6] == 106
    Check("Columns 6 -> 12 -> 6 gives back exactly what was there", same)

    -- Shrinking below what is in the bar parks the rest instead of deleting
    -- it, and growing again brings it home to its own index.
    local full = Fresh({ layout = "grid", rows = 1, columns = 6 })
    full.cells = { 201, 202, 203, 204, 205, 206 }

    ns.Bars:ReshapeGrid(full, 1, 2)
    Check("Shrinking keeps only what fits",
        full.cells[1] == 201 and full.cells[2] == 202 and full.cells[3] == nil)

    ns.Bars:ReshapeGrid(full, 1, 6)
    local restored = true
    for cell = 1, 6 do
        if full.cells[cell] ~= 200 + cell then restored = false end
    end
    Check("Growing back restores every spell to its own slot", restored,
        "nothing is deleted by a slider")
end

---------------------------------------------------------------------------
-- What is shared between characters, and what is not
--
-- The layout is one user interface you built once; the spells are not
-- portable. Getting this backwards showed a Paladin a row of Death Knight
-- cooldowns, which is what prompted the split.
---------------------------------------------------------------------------
local function TestPerSpec()
    local cfg = Fresh()
    cfg.cellsBySpec = { ["DEATHKNIGHT:250"] = { 101, 102 }, ["PALADIN:66"] = {} }
    cfg.parkedBySpec = { ["DEATHKNIGHT:250"] = {}, ["PALADIN:66"] = {} }

    cfg.cells = cfg.cellsBySpec["DEATHKNIGHT:250"]
    Check("A spec sees its own spells", cfg.cells[1] == 101)

    cfg.cells = cfg.cellsBySpec["PALADIN:66"]
    Check("Another class sees none of them", cfg.cells[1] == nil)

    -- The other half of the rule: the LOOK is shared, so it must not be
    -- filed per spec and must not travel when a spell is dragged.
    local layout = Fresh({ layout = "grid", rows = 1, columns = 3 })
    ns.Layout.SetOffset(layout, 2, 17, -9)
    layout.cells[1], layout.cells[2] = 201, 202

    -- Asked of the real reorder rather than by swapping two fields here: a
    -- test that performs the operation itself proves only that it can.
    ns.Bars:Reorder(layout, 1, 2)
    local x, y = ns.Layout.GetOffset(layout, 2)
    Check("The per-cell look stays with the slot, not the spell",
        Near(x, 17) and Near(y, -9))
    Check("Nothing about the look is filed per spec",
        layout.cellOptsBySpec == nil)
end

---------------------------------------------------------------------------
-- One cell wearing its own look
--
-- Every setting follows the bar until the cell is given its own, and going
-- back has to be possible. The failure mode is silent in both directions: a
-- cell that stops following looks like the bar setting is broken, and a cell
-- that never starts looks like the cell setting is.
---------------------------------------------------------------------------
local function TestCellLook()
    local cfg = Fresh({ kind = "bar", fillColor = { 1, 0, 0 }, fillAlpha = 0.5 })

    Check("A fresh cell wears nothing of its own",
        not ns.Bars:CellHasLook(cfg, 2))
    Check("It follows the bar's colour",
        ns.Bars:CellStyle(cfg, 2, 24).fillColor[1] == 1)

    ns.Bars:SetCellLook(cfg, 2, "fillColor", { 0, 0, 1 })
    Check("A cell can wear its own colour", ns.Bars:CellHasLook(cfg, 2))
    Check("Its own colour is what the renderer gets",
        ns.Bars:CellStyle(cfg, 2, 24).fillColor[3] == 1)

    -- The half that is easy to lose: everything NOT overridden still has to
    -- follow, including settings changed after the override was made.
    Check("Everything else still follows the bar",
        Near(ns.Bars:CellStyle(cfg, 2, 24).fillAlpha, 0.5))
    cfg.fillAlpha = 0.9
    Check("A change to the bar reaches the cell that did not override it",
        Near(ns.Bars:CellStyle(cfg, 2, 24).fillAlpha, 0.9))

    Check("Its neighbours are untouched",
        ns.Bars:CellStyle(cfg, 1, 24).fillColor[1] == 1
        and not ns.Bars:CellHasLook(cfg, 1))
    Check("And the bar itself is untouched", cfg.fillColor[1] == 1)

    -- Nil means "follow again", which is how a control hands a setting back.
    ns.Bars:SetCellLook(cfg, 2, "fillColor", nil)
    Check("Clearing one override goes back to following",
        ns.Bars:CellStyle(cfg, 2, 24).fillColor[1] == 1)
    Check("A cell with nothing left is tidied away",
        not ns.Bars:CellHasLook(cfg, 2) and cfg.cellOpts[2] == nil,
        "an empty override table must not survive")

    -- Reset, and the rule that a cell's look belongs to the SLOT: the scale
    -- and the nudge live in the same table and must survive it.
    ns.Bars:SetCellLook(cfg, 3, "fillColor", { 0, 1, 0 })
    ns.Layout.EnsureCellOpts(cfg, 3).scale = 1.5
    Check("Reset gives the look back", ns.Bars:ClearCellLook(cfg, 3))
    Check("Reset keeps the size, which is not part of the look",
        ns.Layout.CellOpts(cfg, 3) and ns.Layout.CellOpts(cfg, 3).scale == 1.5)
    Check("Resetting a cell that wears nothing reports so",
        ns.Bars:ClearCellLook(cfg, 1) == false)

    -- Only the look travels. Rows and spacing describe the whole bar and
    -- would mean something different per cell.
    local allowed = {}
    for _, key in ipairs(ns.CELL_LOOK_KEYS) do allowed[key] = true end
    Check("A cell may not override the bar's shape",
        not allowed.rows and not allowed.columns and not allowed.spacing
        and not allowed.layout)
    Check("A cell may override the things you can see",
        allowed.fillColor and allowed.borderColor and allowed.fillGrow
        and allowed.stackThresholds)
end

---------------------------------------------------------------------------
-- Sorting a bar by dragging
--
-- Dragging a spell up a list has to leave the others in THEIR order. Swapping
-- cannot do that - every swap disturbs a second cell nobody pointed at - so
-- sorting four spells would take six drags and a plan.
---------------------------------------------------------------------------
local function TestReorder()
    local function Bar(...)
        local cfg = Fresh({ layout = "grid", rows = 1, columns = 6 })
        local ids = { ... }
        for slot = 1, #ids do
            if ids[slot] ~= 0 then cfg.cells[slot] = ids[slot] end
        end
        return cfg
    end
    local function Reads(cfg, count)
        local out = {}
        for slot = 1, count do out[slot] = cfg.cells[slot] or 0 end
        return table.concat(out, ",")
    end

    -- The owner's case: three spells, drag the third to the front.
    local cfg = Bar(101, 102, 103)
    ns.Bars:Reorder(cfg, 3, 1)
    Check("Dragging the last spell to the front keeps the others in order",
        Reads(cfg, 3) == "103,101,102", Reads(cfg, 3))

    cfg = Bar(101, 102, 103)
    ns.Bars:Reorder(cfg, 1, 3)
    Check("Dragging the first spell to the end keeps the others in order",
        Reads(cfg, 3) == "102,103,101", Reads(cfg, 3))

    cfg = Bar(101, 102, 103, 104)
    ns.Bars:Reorder(cfg, 2, 3)
    Check("A one-place move touches only those two",
        Reads(cfg, 4) == "101,103,102,104", Reads(cfg, 4))

    -- Nothing is ever lost, which is the property that matters most: a drag
    -- that drops a spell is worse than a drag that does nothing.
    cfg = Bar(101, 102, 103, 104, 105)
    for _, move in ipairs({ { 5, 1 }, { 2, 4 }, { 1, 5 }, { 3, 2 } }) do
        ns.Bars:Reorder(cfg, move[1], move[2])
    end
    local seen = {}
    for slot = 1, 5 do if cfg.cells[slot] then seen[cfg.cells[slot]] = true end end
    local all = true
    for id = 101, 105 do if not seen[id] then all = false end end
    Check("Four drags in a row lose nothing", all, Reads(cfg, 5))

    -- A hole is a position like any other. It travels rather than being
    -- silently filled, or a bar with a deliberate gap closes up by itself.
    cfg = Bar(101, 0, 102)
    ns.Bars:Reorder(cfg, 3, 1)
    Check("A hole moves with the sequence instead of being filled",
        Reads(cfg, 3) == "102,101,0", Reads(cfg, 3))

    -- Out of bounds and no-ops report failure rather than corrupting the row.
    cfg = Bar(101, 102, 103)
    Check("A drag onto itself does nothing", ns.Bars:Reorder(cfg, 2, 2) == false)
    Check("A drop outside the bar is refused",
        ns.Bars:Reorder(cfg, 2, 99) == false and ns.Bars:Reorder(cfg, 0, 2) == false)
    Check("Neither left the row disturbed", Reads(cfg, 3) == "101,102,103")

    -- Swapping still exists, because "these two are in each other's places"
    -- is a real thing to want. It is Shift on the drop, and it has to be a
    -- DIFFERENT answer to the same drag or the modifier is decoration.
    local sorted = Bar(101, 102, 103)
    local swapped = Bar(101, 102, 103)
    ns.Bars:Reorder(sorted, 3, 1)
    ns.Bars:Swap(swapped, 3, 1)
    Check("Sorting and swapping answer the same drag differently",
        Reads(sorted, 3) == "103,101,102" and Reads(swapped, 3) == "103,102,101",
        Reads(sorted, 3) .. "  vs  " .. Reads(swapped, 3))
end

---------------------------------------------------------------------------
-- The bar fill
--
-- Which END the fill sits at and whether it GROWS are two different things.
-- They were one setting whose label described the half that was not
-- implemented, so turning on "fill up" moved the bar to the other side.
---------------------------------------------------------------------------
local function TestFill()
    local cfg = Fresh({ kind = "bar" })

    cfg.fillSide, cfg.fillGrow = true, false
    local side = ns.Bars:Style(cfg, 24)
    Check("The side and the direction are separate settings",
        side.fillSide == true and side.fillGrow == false)

    cfg.fillSide, cfg.fillGrow = false, true
    local grow = ns.Bars:Style(cfg, 24)
    Check("Filling up does not move the bar to the other end",
        grow.fillSide == false and grow.fillGrow == true)

    -- An empty texture means "wear the backdrop's", so a default bar reads as
    -- one object rather than two textures that happen to be adjacent.
    cfg.fillTexture, cfg.backdropTexture = "", "ZS Smooth"
    Check("An empty fill texture follows the backdrop",
        ns.Bars:Style(cfg, 24).fillTexture == "ZS Smooth")

    cfg.fillTexture = "ZS Neon"
    Check("A chosen fill texture wins",
        ns.Bars:Style(cfg, 24).fillTexture == "ZS Neon")

    -- The spark and the charge marks are opposites on purpose: one is
    -- anchored to the fill's TEXTURE so it rides the clock, the other to the
    -- fill FRAME so it stays put. Nothing here can see a frame, so what is
    -- checked is that both reach the renderer at all.
    cfg.showSpark, cfg.chargeMarks = true, true
    local look = ns.Bars:Style(cfg, 24)
    Check("The spark and the charge marks reach the renderer",
        look.showSpark == true and look.chargeMarks == true)

    local travels = {}
    for _, key in ipairs(ns.BAR_STYLE_KEYS) do travels[key] = true end
    Check("Both travel with the look",
        travels.showSpark and travels.chargeMarks and travels.chargeMarkColor)

    -- N charges are divided by N-1 lines, not N. Off by one here draws a line
    -- on the very end of the bar, where it reads as a border rather than as a
    -- division. Asked of the renderer's own helper, not of a copy of the rule.
    Check("Three charges are split by two lines", ns.Bars:ChargeDivisions(3) == 2)
    Check("One charge is split by nothing", ns.Bars:ChargeDivisions(1) == 0)
    Check("A nonsense charge count draws nothing",
        ns.Bars:ChargeDivisions(nil) == 0 and ns.Bars:ChargeDivisions(0) == 0)
end

---------------------------------------------------------------------------
-- Stack thresholds
--
-- The renderer stacks one overlay per threshold and lets DRAW ORDER decide
-- which colour wins, because the count may be a secret value and cannot be
-- compared in Lua. That makes ascending order a correctness requirement
-- rather than a tidiness one, and it is the kind of rule that fails by
-- looking slightly wrong rather than by throwing.
---------------------------------------------------------------------------
local function TestStackThresholds()
    local cfg = Fresh({ kind = "bar" })

    Check("A bar with no thresholds has an empty list",
        #ns.Bars:StackThresholds(cfg) == 0)

    -- Deliberately out of order: the panel writes three fixed rows and the
    -- user can put the big number in the first one.
    cfg.stackThresholds = {
        { value = 10, color = { 0, 1, 0 } },
        { value = 3,  color = { 1, 0, 0 } },
        { value = 7,  color = { 1, 1, 0 } },
    }
    local sorted = ns.Bars:StackThresholds(cfg)
    Check("Thresholds come back in ascending order",
        #sorted == 3 and sorted[1].value == 3
        and sorted[2].value == 7 and sorted[3].value == 10,
        #sorted == 3 and string.format("%d, %d, %d",
            sorted[1].value, sorted[2].value, sorted[3].value) or nil)
    Check("A threshold keeps its own colour through the sort",
        sorted[1].color[1] == 1 and sorted[1].color[2] == 0
        and sorted[3].color[2] == 1 and sorted[3].color[1] == 0)

    -- 0 is how the panel switches a band off, and it has to mean off rather
    -- than "a threshold every aura crosses just by existing".
    cfg.stackThresholds = {
        { value = 0, color = { 1, 0, 0 } },
        { value = 5, color = { 0, 1, 0 } },
    }
    local live = ns.Bars:StackThresholds(cfg)
    Check("A count of zero switches its band off",
        #live == 1 and live[1].value == 5)

    cfg.stackThresholds = { { value = 4.7, color = { 1, 0, 0 } } }
    Check("A threshold is a whole number of stacks",
        ns.Bars:StackThresholds(cfg)[1].value == 4)

    cfg.stackThresholds = { { value = "nonsense" }, { value = 6 } }
    Check("Nonsense in the saved list is dropped, not rendered",
        #ns.Bars:StackThresholds(cfg) == 1)

    -- The renderer styles frames from this list; a shared table would let one
    -- bar's edit reach another's.
    cfg.stackThresholds = { { value = 5, color = { 1, 0, 0 } } }
    local first = ns.Bars:StackThresholds(cfg)
    local second = ns.Bars:StackThresholds(cfg)
    Check("Each read gets its own list", first ~= second
        and first[1] ~= second[1] and first[1].color ~= second[1].color)

    Check("The thresholds reach the style", #ns.Bars:Style(cfg, 24).stackThresholds == 1)

    -- The look travels to another character; what the cells hold does not.
    local travels = false
    for _, key in ipairs(ns.BAR_STYLE_KEYS) do
        if key == "stackThresholds" then travels = true end
    end
    Check("Stack colours count as part of the look", travels)
end

---------------------------------------------------------------------------
-- Custom active states
--
-- A window the player declared, for the things Blizzard only shows as a
-- cooldown. Runs on the real account store and puts back what it found, so
-- it is safe against saved data.
---------------------------------------------------------------------------
local function TestActiveStates()
    if not (ns.Auras and ns.Auras.SetActiveState) then
        Skip("Active states", "the aura layer is not loaded")
        return
    end

    local store = ns.Auras:ActiveStates()
    local restore = store[12345]

    ns.Auras:SetActiveState(12345, 20)
    Check("A declared window is remembered", ns.Auras:ActiveStateFor(12345) == 20)

    Check("A spell with no window has none", ns.Auras:ActiveStateFor(12346) == nil
        or ns.CDM:SameSpell(12345, 12346))

    -- The whole reason the lookup is variant-aware: the game reports the form
    -- you actually cast, which is not always the form you set the window on.
    local other = ns.CDM:OverrideSpell(12345) or ns.CDM:BaseSpell(12345)
    if other then
        Check("The window follows the spell into its other form",
            ns.Auras:ActiveStateFor(other) == 20)
    else
        Skip("The window follows the spell into its other form",
            "this client reports no other form for the test ID")
    end

    ns.Auras:SetActiveState(12345, 0)
    Check("Zero switches the window off",
        ns.Auras:ActiveStateFor(12345) == nil and store[12345] == nil,
        "an absent key, not a stored zero")

    ns.Auras:SetActiveState(12345, 15)
    ns.Auras:SetActiveState(12345, 30)
    Check("Changing the number takes effect at once",
        ns.Auras:ActiveStateFor(12345) == 30,
        "the variant cache has to be dropped on every write")

    Check("Nothing usable is never given a window",
        ns.Auras:ActiveStateFor(nil) == nil)

    store[12345] = restore
    ns.ForgetActiveStates()
end

---------------------------------------------------------------------------
-- Which spell a frame stands for
--
-- Every one of these is a bug that was reported as "it tracks the wrong
-- thing" or "the list makes no sense". They are written so that they do not
-- depend on which class is logged in: the fabricated info tables are plain
-- arguments, and the family checks assert the shape rather than the contents.
---------------------------------------------------------------------------
local function TestSpellIdentity()
    local CDM = ns.CDM
    if not CDM then
        Skip("Spell identity", "the Cooldown Manager layer is not loaded")
        return
    end

    local Usable = CDM.UsableSpellID
    Check("A spell ID has to be a positive whole number",
        Usable(12345) and not Usable(0) and not Usable(-3)
        and not Usable(1.5) and not Usable("12345") and not Usable(nil))

    -- The stale-override guard. 99999999 is not a spell anybody has, so a
    -- resolver that trusts overrideSpellID blindly returns it and the cell
    -- shows an empty icon with no name.
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        Check("An override the player does not have is ignored",
            CDM:InfoSpellID({ overrideSpellID = 99999999, spellID = 12345 }) == 12345)
    else
        Skip("An override the player does not have is ignored",
            "this client cannot answer whether a spell is known")
    end

    Check("A missing override falls through to the spell",
        CDM:InfoSpellID({ spellID = 12345 }) == 12345)
    Check("An override of zero is not an override",
        CDM:InfoSpellID({ overrideSpellID = 0, spellID = 12345 }) == 12345)
    Check("A linked ID is better than nothing",
        CDM:InfoSpellID({ linkedSpellIDs = { 12345 } }) == 12345)
    Check("Nothing usable resolves to nothing",
        CDM:InfoSpellID({}) == nil and CDM:InfoSpellID(nil) == nil)

    -- The family is what lets a stored spell survive its own transform.
    local family = CDM:VariantFamily(12345)
    local hasSelf, clean, duplicate = false, true, false
    local seen = {}
    for _, id in ipairs(family) do
        if id == 12345 then hasSelf = true end
        if not Usable(id) then clean = false end
        if seen[id] then duplicate = true end
        seen[id] = true
    end
    Check("A spell is a member of its own family", hasSelf)
    Check("Every member of a family is a real ID", clean)
    Check("A family lists nothing twice", not duplicate)
    Check("Nothing usable has no family", #CDM:VariantFamily(nil) == 0)

    Check("A spell is the same spell as itself", CDM:SameSpell(12345, 12345))
    -- Two IDs no client has, so "unrelated" is true on every client rather
    -- than true until somebody logs in as the wrong class.
    Check("Two unrelated spells are not the same",
        not CDM:SameSpell(99999998, 99999999))
    Check("Nothing is never the same as something",
        not CDM:SameSpell(nil, 12345) and not CDM:SameSpell(12345, nil))

    -- The rule the whole family exists for, asserted against whatever this
    -- client actually reports rather than an ID picked in advance.
    local transformed = CDM:OverrideSpell(12345) or CDM:BaseSpell(12345)
    if transformed then
        Check("A spell and its other form are the same spell",
            CDM:SameSpell(12345, transformed)
            and CDM:SameSpell(transformed, 12345))
    else
        Skip("A spell and its other form are the same spell",
            "this client reports no other form for the test ID")
    end

    -- The bands. This is what stopped Cooldowns and Utility interleaving.
    local ranks = {}
    for index, viewer in ipairs(CDM.VIEWERS) do
        ranks[index] = CDM:ViewerRank(viewer.key)
    end
    local ascending = true
    for index = 2, #ranks do
        if ranks[index] <= ranks[index - 1] then ascending = false end
    end
    Check("The viewers rank in the order they are listed", ascending)
    Check("The first viewer ranks first", ranks[1] == 0)
    Check("An unknown viewer ranks last",
        CDM:ViewerRank("no such viewer") >= #CDM.VIEWERS)

    -- A band is ten thousand wide, so a viewer would have to show ten
    -- thousand cooldowns before it could reach into the next one.
    local first  = ranks[1] * 10000 + 9999
    local second = ranks[2] and (ranks[2] * 10000) or math.huge
    Check("A viewer's band cannot reach into the next one", first < second)

    -- WHICH HEADING AN ENTRY IS LISTED UNDER.
    --
    -- Above the live check on purpose. Everything below this block needs a
    -- running Cooldown Manager and is skipped on a desktop, which is where
    -- "the picker groups the viewers" has been going unchecked - so the one
    -- part of the answer that is a pure decision is asserted here, where it
    -- runs every time.
    local GroupKeyFor = ns.OptionsBars and ns.OptionsBars.GroupKeyFor
    if GroupKeyFor then
        -- The spells Blizzard's Cooldown Manager knows but is not currently
        -- displaying. They used to carry a heading of their own that called
        -- them "Not shown by Blizzard", which described Blizzard's settings
        -- panel rather than the spell. They are this spec's cooldowns and
        -- they are listed with the rest.
        Check("Spells Blizzard is not displaying list under Cooldowns",
            GroupKeyFor(CDM.HIDDEN_KEY) == "essential",
            GroupKeyFor(CDM.HIDDEN_KEY))

        -- And every real viewer still keeps its own, or the line above would
        -- have swallowed the whole list into one heading.
        for _, viewer in ipairs(CDM.VIEWERS) do
            Check("Viewer " .. viewer.key .. " keeps its own heading",
                GroupKeyFor(viewer.key) == viewer.key,
                GroupKeyFor(viewer.key))
        end

        -- The catch-all, both ways in. A viewer key a later patch renames must
        -- cost one "Other" row, never a spell that quietly disappears.
        Check("An unknown viewer falls through to Other",
            GroupKeyFor("no such viewer") == "other")
        Check("An entry with no viewer at all falls through to Other",
            GroupKeyFor(nil) == "other")
    end

    -- READ-ONLY, against whatever the Cooldown Manager is holding right now.
    -- The reported symptom was groups interleaving, so the catalogue is asked
    -- whether it ever returns to a viewer it has already left behind.
    if not CDM:IsAvailable() then
        Skip("The picker groups the viewers", "the Cooldown Manager is not up")
        return
    end

    local catalogue = CDM:Catalogue()
    if #catalogue == 0 then
        Skip("The picker groups the viewers", "the catalogue is empty")
        return
    end

    local visited, current, revisited = {}, nil, nil
    local ordered = true
    local previous
    for _, entry in ipairs(catalogue) do
        if entry.viewer ~= current then
            if visited[entry.viewer] then revisited = entry.viewer end
            visited[entry.viewer] = true
            current = entry.viewer
        end
        local order = entry.order
        if order and previous and order < previous then ordered = false end
        if order then previous = order end
    end

    Check("The picker groups the viewers", not revisited,
        revisited and ("comes back to " .. tostring(revisited)) or nil)
    Check("The picker never goes backwards through Blizzard's order", ordered)

    -- BOTH SOURCES RUN, AND NEITHER REPEATS THE OTHER.
    --
    -- The walk used to stop after the arranged source, so every spell the
    -- Cooldown Manager only pools situationally was absent from the picker on
    -- every class. Now the static sets fill in behind it - which is only safe
    -- if a cooldown the arranged pass already spoke for cannot come back
    -- through the second one. Handed the same cooldownID twice, the picker
    -- would list the spell once anyway (it keys by spell) and quietly award it
    -- two positions, so this is the only place the fault is visible.
    local emitted, twice, count = {}, nil, 0
    local arranged, extra, hidden = CDM:ForEachCatalogued(function(cooldownID)
        if emitted[cooldownID] then twice = cooldownID end
        emitted[cooldownID] = true
        count = count + 1
    end)
    Check("No cooldown is catalogued twice", not twice,
        twice and ("cooldown " .. tostring(twice)) or nil)

    -- NOTHING THE WALK SEES IS DROPPED ON THE FLOOR.
    --
    -- The counters and the callback have to agree, and this is the check that
    -- would have caught the real fault: cooldowns Blizzard is not displaying
    -- were COUNTED and never handed over, so a picker with nine entries sat
    -- next to a Cooldown Manager settings panel listing seventy-four. Every
    -- one of the three numbers is now something the caller was told about.
    Check("Every catalogued cooldown reaches the caller",
        count == arranged + extra + hidden,
        string.format("%d handed over, %d+%d+%d counted",
            count, arranged, extra, hidden))
    Check("The catalogue walk reports what each source gave",
        type(arranged) == "number" and type(extra) == "number"
        and type(hidden) == "number")

    -- Not an assertion: with no arrangement read, everything legitimately
    -- comes from the static set, and a fresh login before Blizzard's settings
    -- have been opened is exactly that. It is worth SAYING, because "0 extra"
    -- next to a short list is the signature of the bug this replaced.
    Skip("Catalogue sources", string.format(
        "%d arranged, %d situational, %d not displayed",
        arranged, extra, hidden))
end

---------------------------------------------------------------------------
-- The visibility rules
---------------------------------------------------------------------------
local function TestVisibility()
    local cfg = Fresh()
    Check("A fresh bar is visible", ns.Visibility:Evaluate(cfg))
    Check("A visible bar has nothing to explain",
        ns.Visibility:Explain(cfg) == nil)

    local never = Fresh()
    never.show.mode = "never"
    Check("'Never' hides", not ns.Visibility:Evaluate(never))
    Check("'Never' says why", ns.Visibility:Explain(never) ~= nil)

    local off = Fresh({ enabled = false })
    Check("A switched-off bar is hidden", not ns.Visibility:Evaluate(off))

    -- THE INVARIANT: the editor's explanation and the renderer's decision are
    -- the same answer. They were not, for instance types this addon has never
    -- heard of - the editor named a reason the renderer did not apply.
    local agree = true
    for _, mode in ipairs({ "always", "rules", "never" }) do
        for _, combat in ipairs({ "any", "in", "out" }) do
            for _, group in ipairs({ "any", "solo", "party", "raid" }) do
                local probe = Fresh()
                probe.show.mode, probe.show.combat, probe.show.group =
                    mode, combat, group
                local visible = ns.Visibility:Evaluate(probe)
                local why = ns.Visibility:Explain(probe)
                if visible == (why ~= nil) then agree = false end
            end
        end
    end
    Check("Every rule explains itself the way it is applied", agree)

    -- Alpha follows the answer, and the ghost setting is honoured.
    local ghost = Fresh()
    ghost.show.mode = "never"
    ghost.show.hiddenAlpha = 0.3
    Check("A hidden bar uses its own faded alpha",
        Near(ns.Visibility:Factor(ghost), 0.3))
end

---------------------------------------------------------------------------
-- Effects
---------------------------------------------------------------------------
local function TestEffects()
    Check("A bar with no effects registers nothing",
        not ns.Effects.Wanted(ns.EFFECT_DEFAULTS))

    local fx = ns.ApplyDefaults({}, ns.EFFECT_DEFAULTS)
    fx.readyFlash = true
    Check("Switching one effect on registers the bar", ns.Effects.Wanted(fx))

    local nag = ns.ApplyDefaults({}, ns.EFFECT_DEFAULTS)
    nag.reminderAfter = 5
    Check("A reminder counts as an effect", ns.Effects.Wanted(nag))

    -- The refresh window has no clock of its own to keep it alive, so a bar
    -- that uses only this effect still has to be registered with the ticker.
    local pandemic = ns.ApplyDefaults({}, ns.EFFECT_DEFAULTS)
    pandemic.pandemicGlow = true
    Check("The refresh glow alone registers the bar", ns.Effects.Wanted(pandemic))

    -- Asked of nothing: a cell with no Blizzard frame behind it must answer
    -- "no" rather than throw, because that is the everyday case for a proc
    -- this addon draws itself.
    local ok, answer = pcall(ns.CDM.InPandemic, ns.CDM, nil)
    Check("Nothing is never in its refresh window", ok and answer == false)
end

---------------------------------------------------------------------------
-- Media
--
-- Every name this addon puts in the shared registry has to come back out of
-- it. That is exactly the failure that shipped once: twenty textures were
-- registered and the files were written outside the addon folder, so the list
-- was full of names pointing at nothing.
--
-- What this CANNOT check is whether the file itself loads - there is no way
-- to ask the client that from Lua. Said out loud rather than implied.
---------------------------------------------------------------------------
local function TestMedia()
    local missing = 0
    local count = 0

    for _, name in ipairs(ns.Media.List("statusbar")) do
        if name:sub(1, 3) == "ZS " then
            count = count + 1
            local path = ns.Media.Statusbar(name)
            if type(path) ~= "string" or not path:find("ZwoelfStuff") then
                missing = missing + 1
            end
        end
    end

    Check("Every shipped bar texture is in the registry", missing == 0,
        string.format("%d of %d resolve to nothing", missing, count))
    Check("The shipped textures are actually registered", count >= 20,
        string.format("found %d", count))

    Skip("Whether each texture FILE loads",
        "the client does not answer that question - look at the picker")
end

---------------------------------------------------------------------------
-- Your own bars. Read-only.
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Cast history - the estimate the death window
-- colour their answers with. The rule has one trap worth pinning: nil and 0
-- are different answers ("cannot tell" against "ready"), and a caller that
-- collapses them calls every unknown spell ready.
---------------------------------------------------------------------------
local function TestHistory()
    local History = ns.History
    if not History then
        Skip("Cast history", "History.lua did not load")
        return
    end

    Check("Still cooling is the seconds left",
        History.Remaining(100, 60, 130) == 30)
    Check("Elapsed answers exactly 0", History.Remaining(100, 60, 160) == 0)
    Check("Long past stays 0, never negative",
        History.Remaining(100, 60, 1000) == 0)
    Check("Never cast answers nil, not 0",
        History.Remaining(nil, 60, 130) == nil)
    Check("No known cooldown answers nil, not 0",
        History.Remaining(100, nil, 130) == nil)
    Check("A zero-length cooldown answers nil - there is nothing to estimate",
        History.Remaining(100, 0, 130) == nil)

    local last, casts = {}, {}
    for i = 1, 7 do History.Push(last, casts, 100 + i, i, 5) end
    Check("The ring keeps the cap and no more", #casts == 5)
    Check("The oldest fall out, the newest stay",
        casts[1].spellID == 103 and casts[5].spellID == 107)
    History.Push(last, casts, 103, 99, 5)
    Check("The map remembers only the newest cast of a spell",
        last[103] == 99)

    -----------------------------------------------------------------------
    -- HOW LONG A DEFENSIVE WAS UP, measured. The replay drew every press
    -- as a stub because its only source was a number nobody types in. So
    -- the window between a tracked buff going up and going down is
    -- recorded while it happens - our own clock over a value this patch
    -- withholds, exactly as the proc recorder works.
    -----------------------------------------------------------------------
    local windows = {}
    Check("A window shorter than a flicker is not a reading",
        History.PushActive(windows, 871, 100, 100.2, 10) == false
            and #windows == 0)
    Check("A window that never closed is not a reading either",
        History.PushActive(windows, 871, 100, 400, 10) == false)
    Check("A real window is kept",
        History.PushActive(windows, 871, 100, 108, 10) == true
            and windows[1].from == 100 and windows[1].to == 108)

    Check("The press finds the window it opened",
        (function()
            local from, to = History.WindowFor(windows, {}, 871, 99.8)
            return from == 100 and to == 108
        end)())
    Check("A window from another fight is not that press's window",
        History.WindowFor(windows, {}, 871, 60) == nil)
    Check("Another spell's window is never borrowed",
        History.WindowFor(windows, {}, 12345, 99.8) == nil)
    Check("A talented form of the same spell still finds it",
        (function()
            local from = History.WindowFor(windows, {}, 12345, 99.8, { 871 })
            return from == 100
        end)())

    -- Pressed twice in one fight: each press gets ITS window, not both the
    -- first one - the reason the search runs newest first.
    History.PushActive(windows, 871, 200, 209, 10)
    Check("Two presses of one spell keep their own windows",
        (function()
            local from = History.WindowFor(windows, {}, 871, 199.9)
            return from == 200
        end)())

    Check("A buff still up answers with no end, which means 'to the death'",
        (function()
            local from, to = History.WindowFor({}, { [871] = 300 }, 871, 299.8)
            return from == 300 and to == nil
        end)())

    local measured = {}
    History.NoteMeasured(measured, 871, 8.04)
    Check("A measured length is kept to a tenth", measured[871] == 8)
    History.NoteMeasured(measured, 871, 5)
    Check("A shorter reading never shortens what was already seen",
        measured[871] == 8)
    History.NoteMeasured(measured, 871, 12)
    Check("A longer reading wins - a window can be cut short, never grown",
        measured[871] == 12)
    History.NoteMeasured(measured, 871, 999)
    Check("A reading that never closed is not stored", measured[871] == 12)

    -----------------------------------------------------------------------
    -- THE NUMBER IN THE TOOLTIP. The owner: "viele def cds haben FESTE
    -- zeiten, die auch so in den tooltips stehen". Reading it is asking the
    -- client, not guessing - but the WORD for "seconds" has to come from
    -- the client as well, or this works in English and nowhere else. He
    -- plays German.
    -----------------------------------------------------------------------
    local words = ns.DurationWords({ "%d |4Sekunde:Sekunden;", "%d |4Sek.:Sek.;" })
    Check("Both forms of the word come out of the client's own format",
        (function()
            local found = {}
            for _, word in ipairs(words) do found[word] = true end
            return found["sekunde"] and found["sekunden"] and found["sek."]
        end)())
    Check("The longest word is tried first, so a short one cannot cut it off",
        #words[1] >= #words[#words])

    Check("A German description answers in seconds",
        ns.DurationInText("Umgibt Euch 5 Sek. lang mit einer Hülle.",
            words) == 5)
    Check("An English one does too",
        ns.DurationInText("Reduces damage taken for 8 sec.",
            ns.DurationWords({ "%d sec" })) == 8)
    Check("Minutes are converted, not read as seconds",
        ns.DurationInText("Lasts 2 min.", ns.DurationWords({ "%d min" }), 60)
            == 120)
    Check("A dot in the word is a dot, not 'any character'",
        ns.DurationInText("12 Sekx", ns.DurationWords({ "%d |4Sek.:Sek.;" }))
            == nil)
    Check("A description with no duration in it says so",
        ns.DurationInText("Erhöht Euren Schaden um 30%.", words) == nil)
    Check("Text that is not text is not parsed",
        ns.DurationInText(nil, words) == nil)
end

---------------------------------------------------------------------------
-- Death analysis - pure rules over a made-up recap. The capture path makes
-- every field readable before this runs, so the analysis owes no guards -
-- what it owes is the right sentence for each shape of death.
---------------------------------------------------------------------------
local function TestDeath()
    local Death = ns.Death
    if not Death then
        Skip("Death analysis", "Death.lua did not load")
        return
    end

    -- One big hit out of small ones: the verdict names it, with the share
    -- of health it took.
    local oneShot = Death.Analyse({
        { t = 4.0, amount = 50000,  heal = false, name = "Scratch" },
        { t = 1.2, amount = 900000, heal = false, name = "Crushing Blow" },
        { t = 0.0, amount = 60000,  heal = false, name = "Scratch" },
    }, 2000000, {}, {})
    Check("The biggest hit is found",
        oneShot.biggest and oneShot.biggest.amount == 900000)
    Check("Its share of max health is computed",
        oneShot.biggest.pct and math.abs(oneShot.biggest.pct - 0.45) < 0.001)
    Check("A hit worth 40% or more is called out by name",
        oneShot.lines[1] ~= nil
            and oneShot.lines[1]:find("Crushing Blow", 1, true) ~= nil)

    -- Death by a thousand cuts: no single hit is named.
    local chip = Death.Analyse({
        { t = 6, amount = 100000, heal = false, name = "Chip" },
        { t = 4, amount = 100000, heal = false, name = "Chip" },
        { t = 2, amount = 100000, heal = false, name = "Chip" },
    }, 2000000, {}, {})
    Check("Small hits are summed, not blamed one by one",
        chip.lines[1] ~= nil and chip.lines[1]:find("No single killer", 1, true) ~= nil)

    -- Heals count to their own total and the drought is measured.
    local healed = Death.Analyse({
        { t = 8.0, amount = 300000, heal = true,  name = "Heal" },
        { t = 1.0, amount = 500000, heal = false, name = "Hit" },
    }, 2000000, {}, {})
    Check("A heal lands in the healed total, not the taken total",
        healed.totalHealed == 300000 and healed.totalIn == 500000)
    Check("A heal drought over 3s gets its own sentence",
        (function()
            for _, line in ipairs(healed.lines) do
                if line:find("last heal", 1, true) then return true end
            end
            return false
        end)())

    -- Availability: ready by our clock is listed, unknown is not called
    -- ready, and a CONSUMABLE is judged in the same list as the spells -
    -- "what could have saved you" is one question and used to have two
    -- answers on one window.
    local avail = Death.Analyse({},  nil, {
        { spellID = 1, name = "Icebound Fortitude", remaining = 0 },
        { spellID = 2, name = "Vampiric Blood",     remaining = 25 },
        { spellID = 3, name = "Lichborne",          remaining = nil, why = "not cast since login" },
        { itemID = 5512, name = "Healthstone", count = 1, remaining = 0 },
    }, {})
    Check("Ready and unused is listed by name",
        #avail.readyDefensives == 2
            and avail.readyDefensives[1].name == "Icebound Fortitude")
    -- The id travels with the name everywhere, because only the id can
    -- produce an icon and a tooltip - and this game shows both, always.
    Check("A named spell carries its id for the icon and the tooltip",
        avail.readyDefensives[1].spellID == 1)
    -- A consumable carries an ITEM id and is judged with the spells: a
    -- healthstone in the bag is the same verdict as a defensive off cooldown.
    Check("A consumable is judged as a defensive, by its item id",
        avail.readyDefensives[2].itemID == 5512)
    Check("Cannot-tell is never promoted to ready",
        #avail.unknownDefensives == 1
            and avail.unknownDefensives[1].name == "Lichborne")


    -- CONSUMABLES ARE PICKED, NOT SHIPPED. The three seeded ids are a
    -- starting point; nil means the setting has never been seen, which is a
    -- different thing from a list somebody emptied on purpose - and getting
    -- that wrong would re-seed a potion he threw out, every login.
    if ns.db then
        ns.db.rescueItems = nil
        local seeded = Death.PickedItems()
        local count = 0
        for _ in pairs(seeded) do count = count + 1 end
        Check("An unseen list is seeded once", count > 0)

        for id in pairs(seeded) do seeded[id] = nil end
        local again = Death.PickedItems()
        local emptied = 0
        for _ in pairs(again) do emptied = emptied + 1 end
        Check("A list emptied on purpose stays empty", emptied == 0)
        ns.db.rescueItems = nil
    end

    -- Nothing readable at all still answers with a sentence.
    local empty = Death.Analyse(nil, nil, {}, {})
    Check("An empty recap still gets an honest sentence", #empty.lines == 1)

    -- The row filter. The first live death drew hits from five minutes
    -- earlier under a subtitle promising ten seconds - the recap hands over
    -- more history than its name says.
    local recent, stale = Death.RecentEvents({
        { t = 309.8 }, { t = 2.1 }, { t = 0 },
    }, 10)
    Check("Events older than the window are kept off the rows",
        #recent == 2 and stale == false)
    local old, oldStale = Death.RecentEvents({ { t = 300 } }, 10)
    Check("A recap with only old events comes back whole, and flagged",
        #old == 1 and oldStale == true)
    local none, noneStale = Death.RecentEvents(nil, 10)
    Check("No events at all is an empty list, flagged",
        #none == 0 and noneStale == true)

    -- The mob's name in the verdict, when the recap gave one.
    local named = Death.Analyse({
        { t = 1, amount = 900000, heal = false, name = "Melee",
          who = "Heavyweight Golem" },
    }, 1000000, {}, {})
    Check("The killer's name lands in the sentence",
        named.lines[1]:find("from Heavyweight Golem", 1, true) ~= nil)

    -- The session log. One rule, three promises: a new death is appended,
    -- the cap drops the oldest, and a RETRY replaces instead of appending -
    -- or one fall would sit in the pager twice.
    local log = {}
    for i = 1, 12 do Death.Remember(log, { n = i }, 10) end
    Check("The log keeps the cap and no more", #log == 10)
    Check("The oldest deaths fall out, the newest stay",
        log[1].n == 3 and log[10].n == 12)
    Death.Remember(log, { n = 99 }, 10, true)
    Check("A replace overwrites the newest rather than appending",
        #log == 10 and log[10].n == 99)
    local fresh = {}
    Death.Remember(fresh, { n = 1 }, 10, true)
    Check("A replace on an empty log still records the death",
        #fresh == 1 and fresh[1].n == 1)

    -- SafeName: the fallback words come from the event type.
    Check("A withheld melee name says Melee",
        Death.SafeName(nil, "SWING_DAMAGE") == "Melee")
    Check("A withheld heal name says a heal",
        Death.SafeName(nil, "SPELL_HEAL") == "a heal")
    Check("A readable name passes through",
        Death.SafeName("Crushing Blow", "SPELL_DAMAGE") == "Crushing Blow")

    -- The share is built from analysed lines only, and leads with totals.
    local lines = Death.ShareLines({
        when = "20:15:01",
        where = "M+12 - Ara-Kara - Avanoxx",
        analysis = Death.Analyse({
            { t = 1, amount = 500000, heal = false, name = "Hit" },
        }, 1000000, {}, {}),
    })
    Check("The share leads with the totals line",
        lines and lines[1] ~= nil and lines[1]:find("Death 20:15:01", 1, true) ~= nil)
    Check("Where it happened travels with the share",
        lines and lines[1]:find("M+12 - Ara-Kara", 1, true) ~= nil)
    Check("The verdict lines travel with it", lines and #lines >= 2)

    ---------------------------------------------------------------------
    -- Where it happened. Every argument is one the client may withhold,
    -- so the label has to degrade a word at a time rather than fail.
    ---------------------------------------------------------------------
    local key, keyShort = Death.WhereLabel("party", "Ara-Kara, City of Echoes",
        "Mythic Keystone", 12, nil, nil)
    Check("A keystone level makes the dungeon an M+",
        key == "M+12 - Ara-Kara, City of Echoes" and keyShort == "M+12")

    local dungeon = Death.WhereLabel("party", "Ara-Kara", "Heroic", nil, nil, nil)
    Check("A dungeon without a key keeps its difficulty",
        dungeon == "Dungeon - Ara-Kara (Heroic)")

    local raid, raidShort = Death.WhereLabel("raid", "Nerub-ar Palace", "Heroic",
        nil, "Queen Ansurek", nil)
    Check("A raid boss is named after the raid and its difficulty",
        raid == "Raid - Nerub-ar Palace (Heroic) - Queen Ansurek")
    Check("The boss wins the short word outright", raidShort == "Queen Ansurek")

    local open, openShort = Death.WhereLabel("none", nil, nil, nil, nil, "Duskwood")
    Check("Outside an instance the zone is the place",
        open == "Open world - Duskwood" and openShort == "Open world")
    Check("A withheld zone still answers something",
        Death.WhereLabel(nil, nil, nil, nil, nil, nil) == "Open world")

    ---------------------------------------------------------------------
    -- Where a share goes. The rule is separate from the group state so
    -- this can be asked on a desktop with nobody around.
    ---------------------------------------------------------------------
    Check("Auto prefers the instance group over the raid",
        Death.ShareTarget("AUTO", { inInstance = true, inRaid = true,
            inParty = true }) == "INSTANCE_CHAT")
    Check("Auto falls back to the raid, then the party",
        Death.ShareTarget("AUTO", { inRaid = true, inParty = true }) == "RAID"
            and Death.ShareTarget(nil, { inParty = true }) == "PARTY")
    Check("Auto alone answers nobody, with a reason",
        select(1, Death.ShareTarget("AUTO", {})) == nil
            and select(2, Death.ShareTarget("AUTO", {})) ~= nil)
    Check("A chosen channel that is not there never silently posts",
        select(1, Death.ShareTarget("RAID", { inParty = true })) == nil)
    Check("A chosen channel that IS there is taken literally",
        Death.ShareTarget("RAID", { inRaid = true }) == "RAID"
            and Death.ShareTarget("GUILD", { inGuild = true }) == "GUILD")
    Check("Say and yell need no group at all",
        Death.ShareTarget("SAY", {}) == "SAY"
            and Death.ShareTarget("YELL", {}) == "YELL")

    ---------------------------------------------------------------------
    -- How many are kept, and which slice of them the side column shows.
    ---------------------------------------------------------------------
    Check("Ten is the number when nobody has said otherwise",
        Death.KEEP_DEFAULT == 10)
    Check("The bounds are real bounds", Death.KEEP_MIN >= 1
        and Death.KEEP_MAX > Death.KEEP_MIN)

    -- The side column shows twelve of up to fifty, so the slice has to
    -- follow the selection or the list stops answering "where am I".
    Check("The newest death sits at the top with nothing scrolled",
        Death.ScrollTo(30, 30, 0, 12) == 0)
    Check("Walking past the bottom edge scrolls by exactly one",
        Death.ScrollTo(18, 30, 0, 12) == 1)
    Check("Walking back up above the top edge scrolls back",
        Death.ScrollTo(30, 30, 5, 12) == 0)
    Check("A selection already in view does not move the list",
        Death.ScrollTo(25, 30, 3, 12) == 3)
    Check("The list never scrolls past its own end",
        Death.ScrollTo(1, 30, 99, 12) == 18)
    Check("A list shorter than the column never scrolls",
        Death.ScrollTo(1, 4, 0, 12) == 0)

    -- Clearing empties the list it is handed, and only that one.
    local mine = { { n = 1 }, { n = 2 } }
    Death.ClearLog(mine)
    Check("Clearing the list leaves nothing behind", #mine == 0)

    ---------------------------------------------------------------------
    -- Surviving a reload. The owner reloaded to test a build and the
    -- skull went with the list, so the last ten are written to the saved
    -- variables - which is only safe if nothing secret can get in.
    ---------------------------------------------------------------------
    local kept = Death.Persist({
        when = "16:10:54", day = "2026-08-09",
        where = "M+12 - Ara-Kara", whereShort = "M+12",
        killer = "Heavyweight Golem",
        killerArt = { creatureID = 213333 },
        maxHP = 2000000,
        events = {
            { t = 2.0, amount = 81600, hp = 40000, name = "Melee",
              who = "Heavyweight Golem", spellID = 195181,
              art = { creatureID = 213333 } },
        },
        avail = { { spellID = 48792, name = "Icebound Fortitude", remaining = 0 } },
        items = { { name = "Healthstone", count = 1 } },
        casts = { { t = 6, spellID = 48792, name = "Icebound Fortitude",
                    defensive = true, lasted = 8, stillUp = true } },
        analysis = { lines = { "derived, and not stored" } },
    })
    Check("A death worth keeping is kept whole",
        kept ~= nil and kept.killer == "Heavyweight Golem"
            and kept.where == "M+12 - Ara-Kara"
            and kept.killerArt.creatureID == 213333
            and #kept.events == 1 and kept.events[1].amount == 81600)
    Check("The verdict is NOT stored - it is derived on the way back",
        kept.analysis == nil)
    -- Each hit keeps its own face, or a reload turns twenty mobs back into
    -- one, which is the whole reason the faces are per hit.
    Check("Every hit keeps the face that belongs to it",
        kept.events[1].art ~= nil and kept.events[1].art.creatureID == 213333)
    -- And each press keeps the length that was measured for it, or the bar
    -- silently changes size after a reload.
    Check("A measured press keeps its length across a reload",
        kept.casts[1].lasted == 8 and kept.casts[1].stillUp == true)
    Check("A face with no numbers behind it is not stored as an empty box",
        Death.Persist({ events = { { t = 0, amount = 1, art = {} } } })
            .events[1].art == nil)
    Check("A death nothing was readable out of is not stored at all",
        Death.Persist({ when = "16:11:00", events = nil }) == nil)

    local back = Death.Restore({ kept })
    Check("Restoring rebuilds the verdict from the stored events",
        #back == 1 and back[1].analysis ~= nil and #back[1].analysis.lines > 0)
    Check("A stored entry with no events is dropped on the way back",
        #Death.Restore({ { when = "x" }, kept }) == 1)
    Check("Restoring an empty store is an empty list",
        #Death.Restore(nil) == 0)

    -- Nothing but a plain readable value of the right type gets in. A
    -- secret cannot be forged from Lua to test with directly, but it dies
    -- at the same gate as a wrong type does - one function, one rule, and
    -- this is the half of it that can be asked on a desktop.
    local dirty = Death.Persist({
        when = { "not a string" },
        killer = 12345,
        events = { { t = 0, amount = 100, name = {}, who = 7, spellID = "no" } },
        avail = {}, items = {},
    })
    Check("Only plain values of the right type reach the saved variables",
        dirty ~= nil and dirty.when == nil and dirty.killer == nil
            and dirty.events[1].name == nil and dirty.events[1].who == nil
            and dirty.events[1].spellID == nil
            and dirty.events[1].amount == 100)

    ---------------------------------------------------------------------
    -- The bar behind a row: two pieces of ONE health bar, which together
    -- are the health you had before the event landed.
    ---------------------------------------------------------------------
    local wasLeft, took = Death.RowSpans(
        { amount = 400000, hp = 600000 }, 1000000)
    Check("A hit draws what was left and what it took, side by side",
        math.abs(wasLeft - 0.6) < 0.001 and math.abs(took - 0.4) < 0.001)

    local healBefore, given = Death.RowSpans(
        { amount = 300000, hp = 800000, heal = true }, 1000000)
    Check("A heal draws the health BEFORE it and the piece it gave",
        math.abs(healBefore - 0.5) < 0.001 and math.abs(given - 0.3) < 0.001)

    local none, killing = Death.RowSpans(
        { amount = 3000000, hp = 0 }, 1000000)
    Check("An overkill cannot draw past the end of the row",
        none == 0 and math.abs(killing - 1) < 0.001)
    Check("With no maximum health there is no bar to draw",
        select(2, Death.RowSpans({ amount = 100, hp = 50 }, nil)) == 0)

    ---------------------------------------------------------------------
    -- One story out of two lists, and where a replay stands in it.
    ---------------------------------------------------------------------
    local story = Death.Storyline(
        { { t = 4.0, amount = 100, name = "First hit" },
          { t = 0.0, amount = 900, name = "Killing blow" } },
        { { t = 2.0, spellID = 48792, name = "Icebound Fortitude",
            defensive = true } })
    Check("What hit you and what you pressed become one order",
        #story == 3 and story[1].name == "First hit"
            and story[2].name == "Icebound Fortitude"
            and story[3].name == "Killing blow")
    Check("A press is marked as yours and keeps its defensive flag",
        story[2].cast == true and story[2].defensive == true)
    Check("A story with nothing in it is empty rather than nil",
        #Death.Storyline(nil, nil) == 0)

    -- A press landing in the same instant as the hit it answers reads
    -- before it: you pressed, then it landed.
    local tie = Death.Storyline({ { t = 2.0, name = "Hit" } },
        { { t = 2.0, name = "Press" } })
    Check("A press and a hit in the same instant read press first",
        tie[1].name == "Press")

    local rows = { { t = 4, hp = 900 }, { t = 2, hp = 500 }, { t = 0, hp = 0 } }
    Check("Before anything lands the bar is still full",
        select(2, Death.ReplayAt(rows, 9, 1000)) == 1000)
    Check("Mid-replay the health is the last landed event's",
        select(2, Death.ReplayAt(rows, 3, 1000)) == 900)
    local landed = Death.ReplayAt(rows, 1.5, 1000)
    Check("The count of what has landed follows the clock", landed == 2)
    Check("At the end everything has landed",
        Death.ReplayAt(rows, 0, 1000) == 3)

    ---------------------------------------------------------------------
    -- The replay window's own rules.
    ---------------------------------------------------------------------
    local Replay = ns.Replay
    if Replay then
        Check("The plot reaches past the oldest thing in the story",
            Replay.Span({ { t = 8 }, { t = 2 } }) > 8)
        Check("An empty story still has a plot to draw on",
            Replay.Span({}) >= 1)
        Check("The death sits at the right-hand end of the axis",
            math.abs(Replay.Fraction(0, 10, 0) - 1) < 0.001)
        Check("The oldest moment shown sits at the left-hand end",
            math.abs(Replay.Fraction(10, 10, 0)) < 0.001)
        -- NOT clamped, on purpose: a mark two seconds off the left edge
        -- must not pile up against the border pretending it is at it.
        -- Replay.Visible is what decides whether it is drawn at all.
        Check("A moment off the plot answers off the plot",
            Replay.Fraction(20, 10, 0) < 0 and Replay.Fraction(-5, 10, 0) > 1)
        Check("What is on screen and what is not is its own question",
            Replay.Visible(5, 10, 0) and not Replay.Visible(12, 10, 0)
                and not Replay.Visible(-1, 10, 0))

        -- The view: zoom 1 is everything, and zooming in follows a centre
        -- without ever running off either end of the story.
        local from, to = Replay.View(10, 1, nil)
        Check("At rest the plot shows the whole death",
            from == 10 and to == 0)
        from, to = Replay.View(10, 2, 5)
        Check("Zoomed in, it shows a window round where you are looking",
            math.abs(from - 7.5) < 0.001 and math.abs(to - 2.5) < 0.001)
        from, to = Replay.View(10, 2, 9.9)
        Check("It cannot scroll past the beginning",
            math.abs(from - 10) < 0.001 and math.abs(to - 5) < 0.001)
        from, to = Replay.View(10, 2, 0)
        Check("It cannot scroll past the death",
            math.abs(to) < 0.001 and math.abs(from - 5) < 0.001)

        -- What a source's face says on hover, summed from the events we
        -- already read. There is no client call for "what can this NPC do"
        -- and a dungeon mob withholds even its name, so this is what IT
        -- did to YOU rather than a page from a database.
        local facts = Replay.SourceSummary({
            { t = 4, amount = 50000, name = "Scratch", who = "Golem" },
            { t = 2, amount = 900000, name = "Melee", who = "Golem" },
            { t = 1, amount = 300000, heal = true, name = "Heal",
              who = "Healyboi" },
            { t = 0, amount = 10000, name = "Melee", who = "Someone else" },
        }, "Golem")
        Check("A face counts only what that source did",
            facts.hits == 2 and facts.total == 950000)
        Check("It names its biggest hit", facts.biggest == 900000)
        Check("It lists what it used, once each",
            #facts.spells == 2 and facts.spells[1] == "Scratch")
        Check("A heal is never counted as something it did to you",
            facts.total == 950000)
        Check("No named source is an empty summary, not an error",
            Replay.SourceSummary({ { t = 1, amount = 5 } }, nil).hits == 0)

        -----------------------------------------------------------------
        -- HOW LONG A BAR IS, and where that length came from. The owner
        -- watched presses draw as stubs and said so: "die cd bars muessen
        -- so weit gehen wie sie aktiv sind". The fix was not to invent a
        -- length - it was to measure one and to keep saying which is which.
        -----------------------------------------------------------------
        local lasted, source = Replay.BarLength({ spellID = 1, t = 6,
            lasted = 8 })
        Check("A press draws the window it actually opened",
            lasted == 8 and source == "window")
        lasted, source = Replay.BarLength({ spellID = 1, t = 6, lasted = 6,
            stillUp = true })
        Check("A buff still up when you died says so",
            lasted == 6 and source == "open")
        Check("A press with no window measured gets no invented length",
            Replay.BarLength({ spellID = 99999901 }) == nil)
        Check("A bar with no length is called a mark, not a bar",
            Replay.LengthNote(nil, nil):find("mark", 1, true) ~= nil)
        Check("A tooltip length says it came off the tooltip",
            Replay.LengthNote("tooltip", 8):find("tooltip", 1, true) ~= nil)
        Check("A measured window says it was measured",
            Replay.LengthNote("window", 8):find("measured", 1, true) ~= nil)
        Check("A still-running buff is worded as still running",
            Replay.LengthNote("open", 6):find("Still up", 1, true) ~= nil)

        Check("A speed outside what is watchable is pulled back in",
            Replay.ClampSpeed(0.01) > 0 and Replay.ClampSpeed(0.01) <= 1
                and Replay.ClampSpeed(50) <= 10)
        Check("A speed inside the range is left alone",
            Replay.ClampSpeed(1.5) == 1.5)
        Check("A speed that is not a number answers real time",
            Replay.ClampSpeed(nil) == 1 and Replay.ClampSpeed("fast") == 1)

        Check("A hit worth half your health draws half a column",
            math.abs(Replay.ColumnHeight(500, 1000)
                - Replay.ColumnHeight(1000, 1000) / 2) < 0.01)
        Check("A tiny hit still draws a visible mark",
            Replay.ColumnHeight(1, 1000000) >= 6)
        Check("Without a maximum health there is nothing to scale by",
            Replay.ColumnHeight(500, nil) == 6)
        Check("The speed label does not invent precision",
            Replay.SpeedLabel(1) == "1x"
                and Replay.SpeedLabel(0.25) == "0.25x")

        -- Play at the end must mean "again". Un-pausing a clock that has
        -- already run out changes nothing on screen, and a live-looking
        -- button that changes nothing is read as broken.
        Check("Play in the middle of a replay pauses and resumes",
            Replay.PlayAction(4) == "toggle")
        Check("Play at the end starts it over instead of doing nothing",
            Replay.PlayAction(0) == "restart"
                and Replay.PlayAction(-1) == "restart")
    else
        Skip("The replay window", "Replay.lua did not load")
    end

    ---------------------------------------------------------------------
    -- What you pressed, in the verdict. This is the line the whole
    -- feature is for: anybody reading it can see nothing was pressed.
    ---------------------------------------------------------------------
    local nothing = Death.Analyse(
        { { t = 1, amount = 900000, name = "Melee" } }, 1000000, {}, {})
    Check("Pressing nothing at all is said out loud",
        (function()
            for _, line in ipairs(nothing.lines) do
                if line:find("pressed nothing", 1, true) then return true end
            end
            return false
        end)())

    local wrongOnes = Death.Analyse(
        { { t = 1, amount = 900000, name = "Melee" } }, 1000000, {},
        { { name = "Death Strike" }, { name = "Heart Strike" } })
    -- The judgement and the evidence are two lines, not one sentence: a
    -- rotation of seven abilities wrapped the old one over three lines and
    -- the verdict disappeared into the middle of a list.
    Check("Pressing no defensive is its own sentence",
        (function()
            for _, line in ipairs(wrongOnes.lines) do
                if line == "No defensive was used." then return true end
            end
            return false
        end)())
    Check("What you did cast is listed on a line of its own",
        (function()
            for _, line in ipairs(wrongOnes.lines) do
                local plain = Death.PlainText(line)
                if plain:find("Your casts:", 1, true)
                    and plain:find("Death Strike", 1, true) then return true end
            end
            return false
        end)())

    local rightOne = Death.Analyse(
        { { t = 1, amount = 900000, name = "Melee" } }, 1000000, {},
        { { spellID = 48792, name = "Icebound Fortitude", defensive = true },
          { name = "Death Strike" } })
    Check("A defensive that WAS used is credited on its own",
        #rightOne.defensivesUsed == 1
            and rightOne.defensivesUsed[1].name == "Icebound Fortitude")
    Check("And it carries its id, so the chip can draw an icon",
        rightOne.defensivesUsed[1].spellID == 48792)

    ---------------------------------------------------------------------
    -- ICON AND TOOLTIP, ALWAYS. The owner's rule, in his words: "immer
    -- wenn eine faehigkeit oder was auch immer einen tooltip und icon hat,
    -- muss das angezeigt werden. egal bei was". A wrapped sentence cannot
    -- hold a hover target, so the verdict carries the icon inline - and
    -- chat, which would show the escape sequence as punctuation or drop it
    -- outright, gets it taken back out on the way through.
    ---------------------------------------------------------------------
    Check("A spell with no icon behind it still reads as its name",
        Death.SpellText(nil, "Shield Wall") == "Shield Wall")
    Check("A list of spells reads as an enumeration",
        Death.PlainText(Death.SpellList({
            { spellID = 1, name = "A" }, { spellID = 2, name = "B" },
        })) == "A, B")
    Check("An inline icon never reaches the chat",
        Death.PlainText("Defensives used: |T123:14:14|t Shield Wall.")
            == "Defensives used: Shield Wall.")
    Check("Text with no icons in it is handed back untouched",
        Death.PlainText("nothing to strip") == "nothing to strip")

    -- The clock in the list. Today it is a time; older, the day goes first.
    Check("A death from today reads as a clock",
        Death.WhenLabel({ when = "16:10:54", day = "2026-08-09" },
            "2026-08-09") == "16:10:54")
    Check("A death from another day carries its date",
        Death.WhenLabel({ when = "16:10:54", day = "2026-08-07" },
            "2026-08-09") == "07.08.  16:10:54")
    Check("A death with no day recorded still reads",
        Death.WhenLabel({ when = "16:10:54" }, "2026-08-09") == "16:10:54")

    -----------------------------------------------------------------------
    -- WHAT THE BAG SCAN OFFERS
    --
    -- Owner, 2026-08-09: "der erkennt die silvermoon health potion nicht".
    -- It recognised nothing at all, ever: the class id is the SIXTH return of
    -- GetItemInfoInstant, four values were discarded and the fifth taken -
    -- the ICON - and a texture file id was then compared against 0.
    --
    -- This runs against YOUR bags, so it cannot expect particular items. What
    -- it can do is re-derive the answer independently and require the filter
    -- to have agreed: every item offered as a consumable must really be one,
    -- and must really have something to press. The exact-contents test lives
    -- in the desktop harness, which owns a bag it made up.
    -----------------------------------------------------------------------
    if C_Item and C_Item.GetItemInfoInstant and C_Container then
        local offered = Death.BagConsumables()
        Check("The bag scan answers with a list", type(offered) == "table")

        local wrongClass, noUse = 0, 0
        for _, itemID in ipairs(offered or {}) do
            local ok, class = pcall(function()
                return select(6, C_Item.GetItemInfoInstant(itemID))
            end)
            if not ok or class ~= 0 then wrongClass = wrongClass + 1 end

            local okSpell, _, spellID = pcall(C_Item.GetItemSpell, itemID)
            if not (okSpell and spellID) then noUse = noUse + 1 end
        end
        Check("Everything offered as a consumable really is one",
            wrongClass == 0, wrongClass .. " were not")
        Check("Everything offered has something to press",
            noUse == 0, noUse .. " had no use effect")

        -- The count is reported rather than judged: an empty bag is a fact
        -- about your character, not a failure. Reported, though, because
        -- "nothing usable in your bags" and "the scan is broken again" look
        -- identical from the outside, and this is the line that tells them
        -- apart.
        if #offered == 0 then
            Skip("What the bag scan found",
                "nothing usable in your bags right now")
        end
    else
        Skip("The bag scan", "this client has no container API")
    end
end

local function TestLiveBars()
    if not (ns.db and ns.db.bars) then
        Skip("Your bars", "no saved data yet")
        return
    end

    local strays, doubles, broken = 0, 0, 0

    for index, cfg in ipairs(ns.db.bars) do
        local count = ns.Bars:CellCount(cfg)

        for cell in pairs(cfg.cells) do
            if cell > count then strays = strays + 1 end
        end

        local seen = {}
        for _, spellID in pairs(cfg.cells) do
            if seen[spellID] then doubles = doubles + 1 end
            seen[spellID] = true
        end

        local ok, slots, box = pcall(ns.Layout.Build, cfg, count,
            cfg.spacing or 4, cfg.lineSpacing or 4)
        if not ok or #slots ~= count
            or not (Finite(box.width) and Finite(box.height)) then
            broken = broken + 1
        end

        local frame = ns.Screen:BarFrame(index)
        if frame then
            Check(string.format("Bar %d (%s) has a real size", index,
                cfg.name or "?"),
                (frame:GetWidth() or 0) > 0 and (frame:GetHeight() or 0) > 0)
        end
    end

    Check("No spell sits outside its bar", strays == 0,
        strays .. " beyond the last cell - they will be parked on the next resize")
    Check("No spell is on the same bar twice", doubles == 0,
        doubles .. " duplicated")
    Check("Every one of your bars can be laid out", broken == 0)
end

---------------------------------------------------------------------------
-- Running it
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- The design system
--
-- Colour and type are not usually worth a test, and these are not tests of
-- taste. They are the three rules the palette is BUILT on - if one of them
-- gets tuned away the window still renders, still passes every other check,
-- and quietly stops working the way it was drawn.
---------------------------------------------------------------------------
local function TestDesignSystem()
    local UI = ns.UI
    local C = UI.C

    local names = {
        "canvasBg", "windowBg", "sidebarBg", "well", "surface", "control",
        "controlHi", "separator", "edge", "overlayEdge", "accent", "accentSoft",
        "accentCool", "accentCoolSoft", "inUse", "inUseSoft", "danger",
        "warning", "text", "textBody", "textDim", "textFaint", "textGhost",
        -- Derived rather than designed, and referenced in two dozen places.
        "surfaceHi", "accentDim",
    }
    local complete, broken = true, nil
    for _, name in ipairs(names) do
        local colour = C[name]
        if type(colour) ~= "table" or #colour < 3 then
            complete, broken = false, name
            break
        end
        for channel = 1, 3 do
            local v = colour[channel]
            if type(v) ~= "number" or v < 0 or v > 1 then
                complete, broken = false, name
                break
            end
        end
        if not complete then break end
    end
    Check("Every colour the window asks for exists", complete,
        broken and ("missing or out of range: " .. broken))

    -- EVERY MEASUREMENT THE WINDOW IS BUILT FROM.
    --
    -- This check exists because it was earned. Re-tuning the palette dropped
    -- UI.HEADER_H with the block it happened to sit in; nothing caught it -
    -- the static check sees a field, not a missing one, and no model test
    -- opens a window - and the first thing that noticed was the client, with
    -- "attempt to perform arithmetic on a nil value" and no window at all.
    -- One constant read at file scope by three files is worth one loop.
    local metrics = {
        "HEADER_H", "ROW_H", "ROW_GAP", "SECTION_H", "COL_GAP",
        "WINDOW_W", "WINDOW_H", "RAIL_W", "INSPECTOR_W", "CONTENT_W",
        "CARD_HEAD_H", "NAV_ITEM_H", "CONTROL_H", "BUTTON_H", "STEPPER_H",
        "PAD", "GAP", "RADIUS",
    }
    local measured, missing = true, nil
    for _, name in ipairs(metrics) do
        if type(UI[name]) ~= "number" then
            measured, missing = false, name
            break
        end
    end
    Check("Every measurement the window is built from exists", measured,
        missing and ("UI." .. missing .. " is " .. type(UI[missing])))

    -- The three columns add up to the window. A change to one of them that
    -- forgets the others leaves a stripe of nothing down the middle.
    Check("The three columns add up to the window",
        UI.RAIL_W + UI.CONTENT_W + UI.INSPECTOR_W == UI.WINDOW_W,
        string.format("%d + %d + %d vs %d", UI.RAIL_W, UI.CONTENT_W,
            UI.INSPECTOR_W, UI.WINDOW_W))

    -- The inversion the whole redesign turns on. The side columns used to be
    -- LIGHTER than the window, which put the content in a trench.
    local function Lum(c) return c[1] + c[2] + c[3] end
    Check("The side columns are darker than the window",
        Lum(C.sidebarBg) < Lum(C.windowBg),
        string.format("sidebar %.3f vs window %.3f", Lum(C.sidebarBg),
            Lum(C.windowBg)))

    -- There are no shadows here, so an overlay can only say it is on top by
    -- being outlined brighter than anything the page can draw.
    Check("An overlay outlines brighter than the page does",
        Lum(C.overlayEdge) > Lum(C.edge),
        string.format("overlay %.3f vs edge %.3f", Lum(C.overlayEdge),
            Lum(C.edge)))

    -- Five sizes, each clearly apart from the next. Two sizes one point apart
    -- are not a hierarchy, they are a mistake nobody can see.
    local ladder = { UI.FS.title, UI.FS.card, UI.FS.row, UI.FS.meta,
        UI.FS.eyebrow }
    local descends = true
    for i = 2, #ladder do
        if not (ladder[i] and ladder[i - 1] and ladder[i] < ladder[i - 1]) then
            descends = false
            break
        end
    end
    Check("The five text sizes descend", descends,
        table.concat({ tostring(ladder[1]), tostring(ladder[2]),
            tostring(ladder[3]), tostring(ladder[4]), tostring(ladder[5]) }, " "))

    -- An item with no tab is on every tab; a page with no tabs shows all of
    -- them. Both nil cases are decisions, and both were wrong once.
    Check("A row with no tab shows on every tab",
        UI.OnTab(nil, "Look") and UI.OnTab(nil, nil))
    Check("A page with no tabs shows every row",
        UI.OnTab("Look", nil) and UI.OnTab("Reuse", nil))
    Check("A row shows only on its own tab",
        UI.OnTab("Look", "Look") and not UI.OnTab("Look", "Reuse"))

    -- Every icon named in a DATA table has to resolve to a file.
    --
    -- An unknown name does not throw and does not draw nothing: UI.Glyph falls
    -- back to four rectangles in the shape of a grid. So a typo, or a file
    -- dropped from Media/icons, ships as the wrong mark and looks deliberate -
    -- which is exactly the failure that started this whole redesign.
    --
    -- The lists are walked rather than copied. A second list of names here
    -- would be a list that goes stale the first time one is added.
    -- Edit mode reads its working habits through one function that fills in
    -- anything a profile is missing. That function used to carry its OWN list
    -- of four keys next to the seven the profile declares, and `snapToGrid`
    -- was in one list and not the other - so grid snapping was permanently off
    -- on any profile older than the key, with nothing on screen saying why.
    --
    -- It fills from ns.DEFAULTS.editMode now. This is the check that the keys
    -- the panel reads are all actually in there.
    for _, key in ipairs({ "grid", "gridStep", "snapDistance",
        "snapToGrid", "dim", "showCoords" }) do
        Check("Edit mode default: " .. key,
            ns.DEFAULTS.editMode[key] ~= nil)
    end

    local marked = {
        { "Arrangement", ns.LAYOUTS }, { "Fill order", ns.FLOWS },
        { "Across", ns.GROW_X }, { "Down", ns.GROW_Y },
        { "Places", ns.SHOW_WHERE },
    }
    for _, pair in ipairs(marked) do
        local label, list = pair[1], pair[2]
        local bad
        for _, entry in ipairs(list or {}) do
            if not (entry.icon and UI.HasIcon(entry.icon)) then
                bad = entry.icon or (entry.text or entry.key or "?")
                break
            end
        end
        Check(label .. " marks all resolve to a file", not bad, bad)
    end

    -----------------------------------------------------------------------
    -- WHICH CUT OF A MARK GETS LOADED
    --
    -- Every mark in the window was soft for months because this decision was
    -- one comparison against `UIParent:GetEffectiveScale() > 1.25` - a number
    -- that is never above 1.25 on a real machine, so the smallest file was
    -- loaded every time and then stretched. A rule that is a screen
    -- measurement cannot be checked by reading it, which is why it is pure
    -- now and checked here.
    --
    -- THE ONE THING THAT MUST HOLD: never upscale by more than the slack.
    -----------------------------------------------------------------------
    local CUTS = ns.UI.ICON_CUTS
    Check("There are four cuts of every mark", #CUTS == 4, tostring(#CUTS))

    for _, canvas in ipairs({ 16, 32 }) do
        for _, perUnit in ipairs({ 0.75, 1, 1.33, 1.5, 1.79, 2, 2.5, 4 }) do
            local cut = ns.UI.IconCutFor(canvas, perUnit)
            local wanted = canvas * perUnit
            local biggest = CUTS[#CUTS]
            -- Never stretched further than the design's own 14-into-16, and
            -- the only permitted exception is a screen denser than the
            -- largest file we ship, where there is nothing better to load.
            local ok = cut >= wanted * ns.UI.ICON_SLACK or cut == biggest
            Check(string.format("A %d box at %.2f px/unit is not stretched",
                canvas, perUnit), ok,
                string.format("picked %d for %.1f px", cut, wanted))
        end
    end

    -- And it must not reach for a bigger file than it needs: that is a
    -- download and a texture load for nothing.
    Check("A 16 box at 1:1 takes the 14 cut",
        ns.UI.IconCutFor(16, 1) == 14, tostring(ns.UI.IconCutFor(16, 1)))
    Check("A 16 box on a dense screen takes the 22 cut",
        ns.UI.IconCutFor(16, 1.33) == 22, tostring(ns.UI.IconCutFor(16, 1.33)))
    Check("A 32 box at 1:1 takes the 28 cut",
        ns.UI.IconCutFor(32, 1) == 28, tostring(ns.UI.IconCutFor(32, 1)))
    Check("Nothing bigger than the biggest cut exists",
        ns.UI.IconCutFor(32, 99) == CUTS[#CUTS])

    -----------------------------------------------------------------------
    -- A WHEEL OVER A LIST THAT CANNOT SCROLL
    --
    -- EnableMouseWheel swallows the gesture whether or not there is anything
    -- to move. In the death window that wheel is how you page between
    -- deaths, and the event list covers most of the window - so a death with
    -- three hits would have eaten the gesture over the area you are most
    -- likely to be pointing at. The escape hatch is a contract of the
    -- widget, so it is checked on the widget.
    -----------------------------------------------------------------------
    do
        local host = CreateFrame("Frame", nil, UIParent)
        host:SetSize(200, 100)
        host:Hide()
        local scroll, content = ns.UI.ScrollArea(host, 200, 8)
        -- One unit tall: there is nothing to scroll, by construction.
        content:SetHeight(1)

        local passed_ = false
        scroll.OnIdleWheel = function(delta) passed_ = (delta == -1) end

        local handler = scroll:GetScript("OnMouseWheel")
        Check("A scrolling area answers the wheel", handler ~= nil)
        if handler then
            handler(scroll, -1)
            Check("A wheel a list cannot use is handed back, not swallowed",
                passed_)
        end
    end

    -----------------------------------------------------------------------
    -- A SLOT TAKES WHAT IS ON THE CURSOR
    --
    -- The owner asked for it - "kann man das so machen, das man die sachen da
    -- reinziehen kann" - and it is the gesture the game's own action bars
    -- use. Two doors, because the client offers two: releasing a drag fires
    -- OnReceiveDrag, and clicking a target while carrying something fires
    -- OnClick with the item still on the cursor. A slot that wires only the
    -- first works for drag and silently ignores click-to-place.
    -----------------------------------------------------------------------
    do
        local host = CreateFrame("Frame", nil, UIParent)
        host:Hide()

        local plain = ns.UI.SpellSlot(host, { size = 40, get = function() end })
        Check("A slot with nothing to drop into it takes no drag",
            plain:GetScript("OnReceiveDrag") == nil)

        local dropped
        local taker = ns.UI.SpellSlot(host, {
            size = 40,
            get = function() end,
            onDropItem = function(itemID) dropped = itemID end,
        })
        Check("A slot that accepts items answers a drag",
            taker:GetScript("OnReceiveDrag") ~= nil)
        Check("It also answers a click, for click-to-place",
            taker:GetScript("OnClick") ~= nil)
        -- Nothing is on the cursor in a test, so the handler must decline
        -- quietly rather than raise - and must NOT swallow the click, or an
        -- empty slot would stop opening its menu.
        local ok = pcall(taker:GetScript("OnReceiveDrag"), taker)
        Check("A drag with nothing on the cursor is declined, not raised", ok)
        Check("Nothing was picked up out of an empty cursor", dropped == nil)
    end

    -- The screen measurement itself. It cannot be predicted out here, but it
    -- can be required to be a usable number - EllesmereUI's own comment says
    -- GetPhysicalScreenSize answers 0 or nil during a display-mode change,
    -- and a 0 would make every mark ask for the 14 cut.
    local perUnit = ns.UI.PixelsPerUnit()
    Check("Pixels per unit is a sane number",
        Finite(perUnit) and perUnit > 0 and perUnit < 8, tostring(perUnit))
end

---------------------------------------------------------------------------
-- Snapping
--
-- It went wrong three times and every diagnosis was reading the code, because
-- the arithmetic was welded to live frames and saved variables and could not
-- be run. EditMode.SnapAxis is the pure half now: plain numbers in, plain
-- numbers out. These are the cases the owner actually reported.
--
-- Everything is an offset from the SCREEN CENTRE, which is how a bar's
-- position is stored. Our own bar is `half` wide either side of `value`.
---------------------------------------------------------------------------
local function TestSnapping()
    local SnapAxis = ns.EditMode.SnapAxis
    local SCREEN = 960          -- half of a 1920 screen
    local loose = { snapDistance = 10, snapToGrid = false }

    -- Nothing near, nothing asked for: the value comes back untouched. A snap
    -- function that always moves something is worse than none.
    local free = SnapAxis(137, 50, SCREEN, {}, loose)
    Check("Nothing near leaves it where it is", free == 137, tostring(free))

    -- The screen centre, which is the one candidate that was always there.
    local centred = SnapAxis(4, 50, SCREEN, {}, loose)
    Check("Near the middle it centres", centred == 0, tostring(centred))

    -- A second bar 200 wide sitting at +300. Its edges are 200 and 400.
    local other = { { centre = 300, half = 100 } }

    local aligned = SnapAxis(296, 50, SCREEN, other, loose)
    Check("It lines up with another bar's middle", aligned == 300,
        tostring(aligned))

    -- Our left edge onto their left edge: our centre at 200 + our half.
    local leftEdges = SnapAxis(248, 50, SCREEN, other, loose)
    Check("Left edge lines up with their left edge", leftEdges == 250,
        tostring(leftEdges))

    -- FLUSH, the case that did not exist: our right edge against their left,
    -- so our centre sits at 200 - 50. Two bars side by side, which is how a
    -- row is built and what "snap to other elements" was asked for.
    local flush = SnapAxis(146, 50, SCREEN, other, loose)
    Check("It sits flush against another bar", flush == 150, tostring(flush))

    -- The screen edge, with our edge on it rather than our centre.
    local edge = SnapAxis(-905, 50, SCREEN, {}, loose)
    Check("It sits flush against the screen edge", edge == -910,
        tostring(edge))

    -- Out of catch range on every one of them.
    local far = SnapAxis(500, 50, SCREEN, other, loose)
    Check("Beyond the catch distance nothing pulls", far == 500, tostring(far))

    -- The grid is the FALLBACK: it fires from any distance, but never over a
    -- bar that caught. Both halves of that are load-bearing.
    local grid = { snapDistance = 10, snapToGrid = true, gridStep = 40 }

    -- 490 rather than 500: 500 sits exactly between two lines and the answer
    -- would be a statement about which way .5 rounds, not about snapping.
    local onGrid, gridGuide = SnapAxis(490, 50, SCREEN, other, grid)
    Check("The grid pulls from any distance", onGrid == 480, tostring(onGrid))
    Check("The grid says which line caught", gridGuide == 480,
        tostring(gridGuide))

    local barWins = SnapAxis(296, 50, SCREEN, other, grid)
    Check("A bar beats the grid", barWins == 300, tostring(barWins))

    -- A grid step of zero is a division waiting to happen.
    local noStep = SnapAxis(137, 50, SCREEN, {},
        { snapDistance = 10, snapToGrid = true, gridStep = 0 })
    Check("A zero grid step is ignored", noStep == 137, tostring(noStep))
end

---------------------------------------------------------------------------
-- Which way the fill runs
--
-- Four names, and each one has to land on a DIFFERENT pair of (orientation,
-- reverse). Two of them are new: SetReverseFill only ever flips a horizontal
-- bar, so up and down were unreachable before and the obvious mistake is to
-- give one of them the same pair as an existing one - which looks like the
-- setting doing nothing.
---------------------------------------------------------------------------
local function TestFillDirection()
    local seen = {}
    for _, entry in ipairs(ns.FILL_DIRECTIONS) do
        local key = entry.orientation .. ":" .. tostring(entry.reverse)
        Check("Fill direction '" .. entry.value .. "' is its own pair",
            not seen[key], key .. " already taken by " .. tostring(seen[key]))
        seen[key] = entry.value

        Check("Fill direction '" .. entry.value .. "' has a mark",
            entry.icon and ns.UI.HasIcon(entry.icon), tostring(entry.icon))
    end

    Check("All four directions are offered", #ns.FILL_DIRECTIONS == 4,
        tostring(#ns.FILL_DIRECTIONS))

    -- Both axes are used. Four horizontal variants would pass the test above
    -- and still mean the vertical fill was never built.
    local vertical = false
    for _, entry in ipairs(ns.FILL_DIRECTIONS) do
        if entry.orientation == "VERTICAL" then vertical = true end
    end
    Check("Two of them are vertical", vertical)

    -- An unknown name must not return nil - the renderer reads .orientation
    -- straight off whatever comes back.
    local fallback = ns.Layout.FillDirection("sideways")
    Check("An unknown direction falls back rather than returning nil",
        fallback and fallback.orientation ~= nil)
    Check("The fallback is left to right", fallback.value == "right",
        tostring(fallback.value))

    -- THE TWO AXES MUST NOT SOUND LIKE ONE.
    --
    -- Direction is space and "Over time" is the clock, and the owner asked
    -- whether they were the same setting twice - because the second one was
    -- called "Fill up", which is a direction word, sitting one row under a
    -- control offering "Bottom to top". Both answers are written out now, and
    -- no word may appear in both lists.
    Check("There are two answers about the clock", #ns.FILL_CLOCKS == 2,
        tostring(#ns.FILL_CLOCKS))

    local sawFalse, sawTrue = false, false
    for _, entry in ipairs(ns.FILL_CLOCKS) do
        if entry.value == false then sawFalse = true end
        if entry.value == true then sawTrue = true end
        Check("The clock answer '" .. tostring(entry.value) .. "' is named",
            type(entry.text) == "string" and entry.text ~= "")
    end
    Check("Draining is one of them", sawFalse)
    Check("Filling is the other", sawTrue)

    for _, clock in ipairs(ns.FILL_CLOCKS) do
        for _, direction in ipairs(ns.FILL_DIRECTIONS) do
            Check("'" .. clock.text .. "' is not also a direction",
                clock.text ~= direction.text)
        end
    end

    -- Driving a bar off a duration handle is asked about, never assumed. A
    -- client without the method must fall back to the value mirror rather
    -- than raise on the first cooldown that starts.
    Check("Nothing cannot be driven by a timer",
        ns.CDM:CanDriveTimer(nil) == false)
    Check("A bar with no SetTimerDuration cannot be driven",
        ns.CDM:CanDriveTimer({}) == false)

    -- ASKING TWICE MUST NOT CHANGE THE ANSWER.
    --
    -- Bars:Style resolves this once and stores the entry, so a caller reading
    -- from a style holds a TABLE while a caller reading raw config holds a
    -- STRING. Handing the table back in used to compare it against a string,
    -- miss every time, and return "left to right" - the preview card animated
    -- every bar horizontally for a whole version because of it, and nothing
    -- errored. Four directions, both shapes, same answer.
    for _, entry in ipairs(ns.FILL_DIRECTIONS) do
        local once = ns.Layout.FillDirection(entry.value)
        local twice = ns.Layout.FillDirection(once)
        Check("Resolving '" .. entry.value .. "' twice keeps it",
            twice == once, tostring(twice and twice.value))
    end
end

---------------------------------------------------------------------------
-- THE PREVIEW CARD MUST DRAW THE BAR THE SCREEN WOULD DRAW.
--
-- The card's bars RUN, so the fill is at every fraction in turn and where it
-- hangs from has to be right for all four directions. The harness cannot see
-- any of it - its frame stub answers GetWidth and GetHeight with fixed
-- numbers whatever was set - so the placement is a pure function and it is
-- checked here.
---------------------------------------------------------------------------
local function TestPreviewBar()
    local Layout = ns.Layout

    -- Every direction the settings page offers must place the fill somewhere.
    -- Left and right were once the whole of it, so up and down previewed lying
    -- down while the bar on screen stood up.
    local corners, axes = {}, {}
    for _, entry in ipairs(ns.FILL_DIRECTIONS) do
        local corner, pad, w, h = Layout.PreviewFill(entry, 20, 0, 100, 24, 0.5)
        Check("Preview places the '" .. entry.value .. "' fill",
            corner and w and h, tostring(corner))

        -- The corner alone does not separate them and must not be asked to:
        -- left-to-right and top-to-bottom BOTH hang off the top left, and
        -- rightly so. What has to be its own is the corner together with the
        -- axis the fraction goes on.
        local key = corner .. ":" .. entry.orientation
        Check("Preview '" .. entry.value .. "' draws unlike the others",
            not corners[key], key .. " already used by "
            .. tostring(corners[key]))
        corners[key] = entry.value
        axes[entry.orientation] = (axes[entry.orientation] or 0) + 1

        -- The fraction goes on the axis the bar runs along and the other
        -- dimension stays full. The wrong way round is a bar that drains
        -- downwards while it is meant to be draining sideways.
        if entry.orientation == "VERTICAL" then
            Check("Preview '" .. entry.value .. "' shortens, not narrows",
                w == 100 and h < 24, tostring(w) .. "x" .. tostring(h))
        else
            Check("Preview '" .. entry.value .. "' narrows, not shortens",
                h == 24 and w < 100, tostring(w) .. "x" .. tostring(h))
        end
        Check("Preview '" .. entry.value .. "' clears the icon",
            pad ~= nil, tostring(pad))
    end
    Check("Both axes are previewed", (axes.VERTICAL or 0) == 2
        and (axes.HORIZONTAL or 0) == 2)

    -- A right-hand icon is cleared from the right, and the reversed fill is
    -- the one that has to know it.
    local corner, pad = Layout.PreviewFill(Layout.FillDirection("left"),
        0, -24, 100, 24, 0.5)
    Check("A reversed fill starts at the right edge", corner == "TOPRIGHT",
        tostring(corner))
    Check("...inside the icon on that side", pad == -24, tostring(pad))

    -- A bar at the very end of its run must still be a bar. A texture sized to
    -- nothing is not drawn at all, and the last frame of every cooldown would
    -- flicker out rather than finish.
    local _, _, w = Layout.PreviewFill(Layout.FillDirection("right"),
        0, 0, 100, 24, 0)
    Check("An empty bar is still one pixel wide", w >= 1, tostring(w))

    -- Full is the default, because the first paint happens before the clock
    -- has ticked once.
    local _, _, full = Layout.PreviewFill(Layout.FillDirection("right"),
        0, 0, 100, 24)
    Check("With no fraction the bar is full", full == 100, tostring(full))
end

---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Gradients
--
-- The whole of "which way round do the two colours go" is four strings in and
-- two values out, so it is checked here rather than looked at on a bar - a
-- swapped pair is invisible on two similar colours and upside down on every
-- other one, which is the worst kind of bug to have to see.
---------------------------------------------------------------------------
-- THE PREVIEW CARD AND THE SCREEN MUST SPACE A BAR THE SAME WAY.
--
-- They did not, at any scale but 1: the screen multiplied its gaps by the
-- bar's scale and the card passed them raw, so a bar at 150% drew correctly
-- sized cells with unscaled spacing in the editor and measured short. One
-- exported rule now, and this is the check that keeps it one.
local function TestGaps()
    local cfg = {}
    ns.ApplyDefaults(cfg, ns.BAR_DEFAULTS)

    cfg.spacing, cfg.lineSpacing, cfg.scale = 6, 8, 1
    local across, down = ns.Layout.Gaps(cfg)
    Check("At 100% the gaps are what was typed", across == 6 and down == 8,
        across .. "," .. down)

    cfg.scale = 1.5
    across, down = ns.Layout.Gaps(cfg)
    Check("At 150% both gaps scale with the cells",
        across == 9 and down == 12, across .. "," .. down)

    -- A bar with nothing set must still answer, because the card asks before
    -- the user has touched anything.
    across, down = ns.Layout.Gaps({})
    Check("An empty bar still has gaps", across == 4 and down == 4,
        across .. "," .. down)
    across, down = ns.Layout.Gaps(nil)
    Check("So does no bar at all", across == 4 and down == 4,
        across .. "," .. down)
end

local function TestGradients()
    local seen = {}
    for _, entry in ipairs(ns.GRADIENT_DIRECTIONS) do
        local key = entry.orientation .. ":" .. tostring(entry.swap)
        Check("Gradient direction '" .. entry.value .. "' is its own pair",
            not seen[key], key .. " already taken by " .. tostring(seen[key]))
        seen[key] = entry.value

        Check("Gradient direction '" .. entry.value .. "' has a mark",
            entry.icon and ns.UI.HasIcon(entry.icon), tostring(entry.icon))
    end
    Check("All four gradient directions are offered",
        #ns.GRADIENT_DIRECTIONS == 4, tostring(#ns.GRADIENT_DIRECTIONS))

    -- The four the engine can actually draw: two orientations times a swap.
    -- Anything else on this list would be a control that cannot be built.
    local orientation, swap = ns.Layout.GradientOrder("right")
    Check("Left to right is HORIZONTAL, unswapped",
        orientation == "HORIZONTAL" and swap == false,
        tostring(orientation) .. " swap=" .. tostring(swap))

    orientation, swap = ns.Layout.GradientOrder("left")
    Check("Right to left is HORIZONTAL, swapped",
        orientation == "HORIZONTAL" and swap == true,
        tostring(orientation) .. " swap=" .. tostring(swap))

    -- VERTICAL takes (bottom, top) - so bottom-to-top is the UNSWAPPED one.
    -- This is the assertion that catches the whole thing being upside down,
    -- and the convention behind it is written out in ns.GRADIENT_DIRECTIONS.
    orientation, swap = ns.Layout.GradientOrder("up")
    Check("Bottom to top is VERTICAL, unswapped",
        orientation == "VERTICAL" and swap == false,
        tostring(orientation) .. " swap=" .. tostring(swap))

    orientation, swap = ns.Layout.GradientOrder("down")
    Check("Top to bottom is VERTICAL, swapped",
        orientation == "VERTICAL" and swap == true,
        tostring(orientation) .. " swap=" .. tostring(swap))

    orientation, swap = ns.Layout.GradientOrder("diagonal")
    Check("An unknown direction falls back rather than returning nil",
        orientation ~= nil and swap ~= nil)
    Check("The gradient fallback is left to right",
        orientation == "HORIZONTAL" and swap == false)

    -- The resolved style always hands the renderer a table. ns.Tint reads
    -- .on and would take a nil as "off" today; the first line of code that
    -- reads .direction off it would throw instead.
    local cfg = {}
    ns.ApplyDefaults(cfg, ns.BAR_DEFAULTS)
    local style = ns.Bars:Style(cfg, 40)
    for _, key in ipairs({ "fillGradient", "backdropGradient", "borderGradient" }) do
        Check(key .. " is always a table", type(style[key]) == "table",
            type(style[key]))
        Check(key .. " starts switched off", style[key].on == false)
        Check(key .. " always carries a direction",
            type(style[key].direction) == "string")
        Check(key .. " always carries a second colour",
            type(style[key].color) == "table")
    end

    -- A profile written before gradients existed carries none of this, and
    -- the renderer must still be handed the full shape.
    local old = { fillGradient = nil, stackThresholds = { { value = 3 } } }
    local oldStyle = ns.Bars:Style(old, 40)
    Check("A profile with no gradient still resolves to one",
        type(oldStyle.fillGradient) == "table" and oldStyle.fillGradient.on == false)
    Check("A band with no gradient still resolves to one",
        type(oldStyle.stackThresholds[1].gradient) == "table",
        type(oldStyle.stackThresholds[1].gradient))

    -- Every colour that CAN ramp travels when a look is copied. The three
    -- that cannot must not be in the list, or a preset would carry a setting
    -- with nothing to apply it to.
    local styleKeys = {}
    for _, key in ipairs(ns.BAR_STYLE_KEYS) do styleKeys[key] = true end
    for _, key in ipairs({ "fillGradient", "backdropGradient", "borderGradient" }) do
        Check(key .. " travels with a copied look", styleKeys[key] == true)
    end
    for _, key in ipairs({ "swipeGradient", "chargeMarkGradient" }) do
        Check(key .. " does not exist - the engine cannot draw it",
            styleKeys[key] == nil and ns.BAR_DEFAULTS[key] == nil)
    end

    -- A look that says nothing about a gradient leaves the last look's
    -- ramping on a bar that is meant to be flat. Every built-in must declare
    -- all three, which is the same rule as the empty `effects` table.
    for _, look in ipairs(ns.BUILT_IN_LOOKS) do
        for _, key in ipairs({ "fillGradient", "backdropGradient", "borderGradient" }) do
            Check("Look '" .. look.name .. "' declares " .. key,
                look.style[key] ~= nil)
        end
    end

    -- And at least one of them turns a gradient on, or the capability ships
    -- switched off everywhere and nobody finds it.
    local anyOn = false
    for _, look in ipairs(ns.BUILT_IN_LOOKS) do
        if look.style.fillGradient and look.style.fillGradient.on then anyOn = true end
    end
    Check("One built-in look shows what a gradient does", anyOn)
end

---------------------------------------------------------------------------
-- Co-tanks
--
-- The arithmetic first, because it is the part that can be wrong without
-- looking wrong: a strip whose second line stacks the wrong way draws over
-- the health bar, and a colour ramp that passes through grey-brown at half
-- reads as a broken addon rather than as a tank at half.
---------------------------------------------------------------------------
local function TestCoTanks()
    local Layout = ns.Layout

    -- THE PREVIEW CARD SHOWS EXACTLY ONE ROW, whatever else is switched on.
    -- Five of them at their real size made the card shrink the whole panel to
    -- fit, and then nothing on it could be read - so this is checked with test
    -- mode ON, which is the setting that used to win.
    local ctdb = ns.db.coTanks
    local hosted, testing, rows = ns.CoTanks.hosted, ctdb.testMode, ctdb.maxRows
    -- Cleared, not just saved. Run /zs test with the options window open on
    -- the Co-tanks page and the panel is genuinely hosted, so the first check
    -- below would read 1 and report a failure about a panel behaving exactly
    -- as designed. A check has to state the conditions it needs, not inherit
    -- whichever window happens to be open.
    ns.CoTanks.hosted = nil
    ctdb.testMode, ctdb.maxRows = true, 5
    Check("Test mode fills the panel", ns.CoTanks:RowCount() == 5,
        tostring(ns.CoTanks:RowCount()))
    ns.CoTanks.hosted = true
    Check("The preview card shows one tank", ns.CoTanks:RowCount() == 1,
        tostring(ns.CoTanks:RowCount()))
    -- The card invents its tank whether or not test mode is on, or the two
    -- sections that set up the aura strips preview as empty space - PaintStrip
    -- refuses to draw an invented aura on anything claiming to be a real
    -- player, and on a normal evening there is no real tank to be.
    ctdb.testMode = false
    Check("The preview card invents its tank either way",
        ns.CoTanks:Invented() == true)
    ns.CoTanks.hosted = nil
    Check("Off the card it does not", ns.CoTanks:Invented() == false)

    ns.CoTanks.hosted, ctdb.testMode, ctdb.maxRows = hosted, testing, rows

    -- Slot 1 is always the anchor corner itself. Everything else is measured
    -- from there, so an offset on the first icon means the whole strip has
    -- moved and nothing on screen says which end it moved from.
    local dx, dy = Layout.StripSlot(1, 20, 2, 4, "right", "BOTTOMLEFT")
    Check("The first icon of a strip sits on the anchor",
        dx == 0 and dy == 0, dx .. "," .. dy)

    dx = Layout.StripSlot(3, 20, 2, 4, "right", "BOTTOMLEFT")
    Check("Icons step by size plus spacing", dx == 44, tostring(dx))

    dx = Layout.StripSlot(3, 20, 2, 4, "left", "BOTTOMRIGHT")
    Check("Growing left steps the other way", dx == -44, tostring(dx))

    -- The wrap, and the direction the second line takes. A strip hung under
    -- the bar must overflow DOWNWARDS; upwards it draws across the health.
    dx, dy = Layout.StripSlot(5, 20, 2, 4, "right", "BOTTOMLEFT")
    Check("The fifth of four per row starts a new line", dx == 0, tostring(dx))
    Check("A bottom-anchored strip overflows downwards", dy == 22, tostring(dy))

    dx, dy = Layout.StripSlot(5, 20, 2, 4, "right", "TOPLEFT")
    Check("A top-anchored strip overflows upwards", dy == -22, tostring(dy))

    -- THE CORNER FLIP. A strip attached to the row's bottom-left hangs its
    -- TOP-left there, so it falls away from the health bar instead of sitting
    -- on it. Same corner both ends and a 22px icon covers a 26px row.
    Check("A bottom strip hangs by its top",
        Layout.StripCorner("BOTTOMLEFT") == "TOPLEFT",
        Layout.StripCorner("BOTTOMLEFT"))
    Check("A top strip hangs by its bottom",
        Layout.StripCorner("TOPRIGHT") == "BOTTOMRIGHT",
        Layout.StripCorner("TOPRIGHT"))
    Check("The side never changes, only the top and bottom",
        Layout.StripCorner("BOTTOMRIGHT") == "TOPRIGHT",
        Layout.StripCorner("BOTTOMRIGHT"))

    -- Which edge the shield hangs off - the one the clock moves. Hard-coded
    -- to RIGHT it sits at the wrong end of a right-to-left bar and across the
    -- middle of a vertical one, which is the fault the spark had for months.
    local edge, vertical = Layout.FillEdge("HORIZONTAL", false)
    Check("A left-to-right bar leads on the right",
        edge == "RIGHT" and vertical == false, tostring(edge))
    edge = Layout.FillEdge("HORIZONTAL", true)
    Check("A right-to-left bar leads on the left", edge == "LEFT", tostring(edge))
    edge, vertical = Layout.FillEdge("VERTICAL", false)
    Check("A bottom-to-top bar leads at the top",
        edge == "TOP" and vertical == true, tostring(edge))
    edge = Layout.FillEdge("VERTICAL", true)
    Check("A top-to-bottom bar leads at the bottom", edge == "BOTTOM", tostring(edge))

    local w, h = Layout.StripSize(4, 20, 2, 4)
    Check("Four in a row measure four icons and three gaps", w == 86, tostring(w))
    Check("One line is one icon tall", h == 20, tostring(h))

    w, h = Layout.StripSize(5, 20, 2, 4)
    Check("Five over two lines are still four wide", w == 86, tostring(w))
    Check("Two lines are two icons and one gap tall", h == 42, tostring(h))

    w = Layout.StripSize(0, 20, 2, 4)
    Check("An empty strip takes no room", w == 0, tostring(w))

    -- The ramp. Two straight halves, and the ends are exactly the colours
    -- that were picked rather than something near them.
    local high, mid, low = { 0, 1, 0 }, { 1, 1, 0 }, { 1, 0, 0 }
    local r, g, b = Layout.HealthTint(1, high, mid, low)
    Check("Full health is exactly the full colour",
        r == 0 and g == 1 and b == 0, r .. "," .. g .. "," .. b)

    r, g, b = Layout.HealthTint(0, high, mid, low)
    Check("Empty is exactly the empty colour",
        r == 1 and g == 0 and b == 0, r .. "," .. g .. "," .. b)

    r, g, b = Layout.HealthTint(0.5, high, mid, low)
    Check("Half is exactly the middle colour",
        r == 1 and g == 1 and b == 0, r .. "," .. g .. "," .. b)

    -- Above maximum is a real state during an absorb, and below zero should
    -- not be reachable but must not produce a colour outside the ramp.
    r = Layout.HealthTint(1.4, high, mid, low)
    Check("Over-full clamps to the full colour", r == 0, tostring(r))
    r = Layout.HealthTint(-1, high, mid, low)
    Check("Under-empty clamps to the empty colour", r == 1, tostring(r))

    -- The text, and the one case that matters most: a number this client
    -- will not let an addon compute on must produce NOTHING, not a zero.
    local CoTanks = ns.CoTanks
    Check("Percent reads as a percent",
        CoTanks:HealthText("percent", 500, 1000) == "50%",
        tostring(CoTanks:HealthText("percent", 500, 1000)))
    Check("A full bar shows no deficit",
        CoTanks:HealthText("deficit", 1000, 1000) == "",
        tostring(CoTanks:HealthText("deficit", 1000, 1000)))
    Check("An unreadable health gives no text at all",
        CoTanks:HealthText("percent", nil, 1000) == nil)
    Check("A zero maximum gives no text rather than dividing by it",
        CoTanks:HealthText("percent", 0, 0) == nil)

    -- Cutting a name. The limit is in CHARACTERS, and a name shorter than the
    -- limit comes back whole rather than padded or truncated to it.
    Check("Zero keeps the whole name",
        CoTanks:CutName("Sunwarden", 0) == "Sunwarden")
    Check("A short name is left alone",
        CoTanks:CutName("Zwoelf", 10) == "Zwoelf")
    local cut = CoTanks:CutName("Sunwarden", 4)
    Check("A long name is cut to the limit", cut == "Sunw", tostring(cut))

    -- THE LIMIT IS IN CHARACTERS, NOT BYTES, and on a European realm that is
    -- the difference between a name and a name with a box on the end. The
    -- first version stepped one byte per pass while counting to a limit in
    -- characters: four letters of "Grimtusk" came back as four bytes of a name
    -- whose first letter is two bytes long.
    local wide = "\195\150lrunn"           -- "Oelrunn" with an O-umlaut: 7 chars, 8 bytes
    cut = CoTanks:CutName(wide, 3)
    Check("A two-byte letter counts as one", cut == "\195\150lr", cut)
    Check("A cut never ends mid-letter",
        not strlenutf8 or strlenutf8(cut) == 3,
        tostring(strlenutf8 and strlenutf8(cut)))
    Check("A name shorter than the limit comes back whole",
        CoTanks:CutName(wide, 20) == wide)

    -- Every setting the panel reads has a default. Two lists of the same
    -- thing drift - that is written down in this file already, from the time
    -- it cost a whole feature - so this walks the defaults rather than a
    -- second hand-typed list.
    local defaults = ns.DEFAULTS.coTanks
    for _, key in ipairs({
        "enabled", "testMode", "includeSelf", "onlyInGroup", "onlyInInstance",
        "width", "rowHeight", "spacing", "scale", "maxRows", "growth", "sortBy",
        "healthTexture", "healthColor", "healthCustom", "healthAlpha",
        "healthGradient", "healthHigh", "healthMid", "healthLow",
        "bgColor", "bgAlpha", "bgGradient", "trackAlpha",
        "borderSize", "borderColor", "borderTexture", "borderGradient",
        "absorbShow", "absorbColor", "healAbsorbShow",
        "name", "health", "debuffs", "buffs",
        "targetBorder", "absorbTexture", "healAbsorbTexture",
        "deadFade", "offlineFade", "rangeFade", "rangeAlpha",
    }) do
        Check("Co-tanks default for '" .. key .. "'", defaults[key] ~= nil)
    end

    -- THE INDICATORS ARE WALKED, not listed a second time. Every one has to
    -- carry the same five fields, because the panel generates the same five
    -- controls for all of them off this very table - a mark missing one is a
    -- control that reads nil and writes into a table nothing looks at.
    Check("There are indicators to check", #ns.COTANK_INDICATORS >= 4,
        tostring(#ns.COTANK_INDICATORS))
    for _, entry in ipairs(ns.COTANK_INDICATORS) do
        local mark = defaults[entry.key]
        Check("Indicator '" .. entry.key .. "' has a default table",
            type(mark) == "table", type(mark))
        if type(mark) == "table" then
            for _, field in ipairs({ "show", "size", "anchor", "x", "y" }) do
                Check("Indicator '" .. entry.key .. "' has " .. field,
                    mark[field] ~= nil)
            end
            -- Every anchor the panel offers must be one SetPoint accepts, or
            -- the mark lands on a point that does not exist and throws in a
            -- repaint.
            local vertical = ns.Layout.LabelVertical(mark.anchor)
            Check("Indicator '" .. entry.key .. "' anchors to a real point",
                vertical == "" or vertical == "TOP" or vertical == "BOTTOM",
                tostring(mark.anchor))
        end
        Check("Indicator '" .. entry.key .. "' has a label",
            type(entry.label) == "string" and #entry.label > 0)
    end

    -- The target border is the fifth mark and does NOT have the same shape -
    -- it is a border, so it carries a thickness and a colour instead of a
    -- position. Checked separately rather than bent into the list above.
    Check("The target border has a thickness",
        type(defaults.targetBorder.size) == "number")
    Check("The target border has a colour",
        type(defaults.targetBorder.color) == "table")

    -- The old flat keys are GONE, not merely unused. A leftover default is a
    -- setting somebody will wire a control to by accident in six months.
    for _, dead in ipairs({ "raidMarker", "raidMarkerSize", "leaderIcon",
        "leaderIconSize", "roleIcon", "roleIconSize", "targetHighlight",
        "targetColor" }) do
        Check("The old indicator key '" .. dead .. "' is gone",
            defaults[dead] == nil)
    end

    -- AND A PROFILE THAT STILL CARRIES THEM IS CARRIED OVER, not thrown away.
    -- Run on a throwaway table, so nothing the player owns is touched.
    local old = {
        raidMarker = false, raidMarkerSize = 22,
        leaderIcon = false, leaderIconSize = 9,
        roleIcon = true, roleIconSize = 20,
        targetHighlight = false, targetColor = { 0.1, 0.2, 0.3 },
    }
    ns.CoTanks:Migrate(old)
    Check("A switched-off marker stays switched off",
        old.marker and old.marker.show == false, tostring(old.marker))
    Check("Its size comes with it", old.marker.size == 22,
        tostring(old.marker.size))
    Check("A switched-on role mark stays on",
        old.role and old.role.show == true)
    Check("The target border keeps its colour",
        old.targetBorder and old.targetBorder.color[3] == 0.3)
    Check("The target border keeps its switch",
        old.targetBorder.show == false)
    for _, dead in ipairs({ "raidMarker", "raidMarkerSize", "leaderIcon",
        "leaderIconSize", "roleIcon", "roleIconSize", "targetHighlight",
        "targetColor" }) do
        Check("Migration removes '" .. dead .. "' from the profile",
            old[dead] == nil)
    end

    -- Twice is the same as once: it runs on every login and must not undo
    -- what the user changed after the first one.
    old.marker.show = true
    ns.CoTanks:Migrate(old)
    Check("Migrating again changes nothing", old.marker.show == true)

    -- The two text elements carry the same seven fields, because the panel
    -- generates the same seven controls for both. One missing field is a
    -- control that reads nil and writes into a table nothing else looks at.
    for _, key in ipairs({ "name", "health" }) do
        for _, field in ipairs({ "show", "font", "size", "color", "outline",
            "anchor", "x", "y" }) do
            Check("Co-tank text '" .. key .. "' has " .. field,
                defaults[key][field] ~= nil)
        end
        -- Every anchor the panel offers has to be one LabelAnchor understands,
        -- or SetPoint is called with a point that does not exist.
        local point = ns.Layout.LabelVertical(defaults[key].anchor)
        Check("Co-tank text '" .. key .. "' anchors to a real point",
            point == "" or point == "TOP" or point == "BOTTOM", point)
    end

    for _, key in ipairs({ "debuffs", "buffs" }) do
        for _, field in ipairs({ "show", "max", "size", "spacing", "perRow",
            "anchor", "growth", "x", "y", "borderSize", "borderColor",
            "countdown", "stacks" }) do
            Check("Co-tank strip '" .. key .. "' has " .. field,
                defaults[key][field] ~= nil)
        end
    end

    -- WHERE THE STRIPS SIT is checked in its own suite now - see "Co-tank
    -- strips" below.
    --
    -- What stood here asserted the opposite of what is true: "the two strips
    -- grow apart, not into each other", which is what opposite growth
    -- directions on the SAME edge look like in a comment and never was on a
    -- screen. Eight icons at 22 is 183 of a 240 row, so they met in the
    -- middle and drew on top of each other from the fifth icon on.
    --
    -- It is worth the extra lines to say why: this check went RED the moment
    -- the arrangement was fixed. A test that restates the design instead of
    -- the requirement reports a correct change as a regression, and the
    -- cheapest way past a red test is to undo the fix.

    -- The gradients the co-tank frame offers are the same three the bars
    -- offer, for the same reason: those are the three the engine can draw.
    for _, key in ipairs({ "healthGradient", "bgGradient", "borderGradient" }) do
        Check("Co-tank " .. key .. " starts off", defaults[key].on == false)
        Check("Co-tank " .. key .. " carries a direction",
            type(defaults[key].direction) == "string")
    end

    -- A row's block is the bar PLUS whatever hangs off it, or every row's
    -- aura strips draw across the next row down. Checked against the setting
    -- rather than a fixed number, because it is the relationship that matters.
    local db = ns.db.coTanks
    local extent, above, below = ns.CoTanks:RowExtent(db)
    Check("A row's block is at least its bar", extent >= db.rowHeight,
        tostring(extent))
    Check("The block is the bar plus what hangs off it",
        extent == db.rowHeight + above + below,
        string.format("%d vs %d+%d+%d", extent, db.rowHeight, above, below))

    -- With both strips switched off the block IS the bar, and with one on it
    -- is taller. A block that ignored its strips would pass the first of
    -- those and fail this one.
    local saved = { db.debuffs.show, db.buffs.show }
    db.debuffs.show, db.buffs.show = false, false
    local bare = ns.CoTanks:RowExtent(db)
    Check("With no strips the block is exactly the bar", bare == db.rowHeight,
        tostring(bare))
    db.debuffs.show = true
    local withStrip = ns.CoTanks:RowExtent(db)
    Check("A strip makes the block taller", withStrip > bare,
        withStrip .. " vs " .. bare)
    db.debuffs.show, db.buffs.show = saved[1], saved[2]

    -- And it can actually be built and painted. Test mode invents its own
    -- roster, so this runs the whole renderer without a group, a raid or a
    -- second player - which is the entire point of test mode existing.
    if ns.CoTanks.Create then
        local ok, err = pcall(function()
            ns.CoTanks:Create()
            local was = ns.db.coTanks.testMode
            ns.db.coTanks.testMode = true
            ns.CoTanks:ApplyLayout()
            ns.CoTanks:Refresh()
            ns.db.coTanks.testMode = was
            ns.CoTanks:Refresh()
        end)
        Check("The co-tank panel builds and paints", ok, tostring(err))
    end

    -- A PAGE MUST BE BUILT AT THE WIDTH IT IS SHOWN AT.
    --
    -- This is the only check in this file that exists because the HARNESS
    -- cannot help: its frame stub answers GetWidth with a fixed number
    -- whatever was set, so a page built four hundred units too wide for the
    -- column it lives in builds, paints, and passes every check - while every
    -- control on it sits off the side of the window. It shipped exactly that
    -- way, on two pages, and only a screenshot found it.
    local NARROW, WIDE = 750, 1150
    local carried = 0
    for _, entry in ipairs(ns.Options.PAGES) do
        -- THE ADDON'S OWN PREDICATE, not a copy of it. This line used to list
        -- the flags again, so adding a page that carried a third column made
        -- the check assert the opposite of the rule and fail a correct page.
        local third = ns.Options.HasThirdColumn(entry)
        local width = ns.Options.PageWidth(entry, NARROW, WIDE)
        if third then
            carried = carried + 1
            Check("Page '" .. entry.key .. "' carries a third column, so it is "
                .. "built narrow", width == NARROW, tostring(width))
        else
            Check("Page '" .. entry.key .. "' has the middle to itself",
                width == WIDE, tostring(width))
        end
    end
    -- If nothing declares a third column the loop above asserts nothing, and
    -- would go green on a PAGES table that had lost the flags entirely.
    Check("Some page does carry a third column", carried >= 2, tostring(carried))

    -- The rail's own mark. PAGES names icons and was NOT among the data
    -- tables this file walks - which is the same gap that let four wrong
    -- icons ship, because an unknown name never throws: it falls back to four
    -- rectangles in the shape of a grid and looks like a deliberate choice.
    for _, glyph in ipairs({ "grid", "move", "sliders", "pulse", "info", "log",
        "tanks" }) do
        Check("The rail mark '" .. glyph .. "' resolves to a file",
            ns.UI.HasIcon(glyph))
    end

    -- Why the aura strips are empty, when they are. It must always be a
    -- sentence or nothing - never a nil that the panel would concatenate.
    local reason = ns.CoTanks:AuraReason()
    Check("The aura reason is a sentence or nothing",
        reason == nil or (type(reason) == "string" and #reason > 0),
        tostring(reason))
end

---------------------------------------------------------------------------
-- The menu filter
--
-- Pure, for the same reason the snapping arithmetic is: the rule that is easy
-- to get wrong - a group heading kept only when something under it survived -
-- is invisible in a screenshot and obvious in a test.
---------------------------------------------------------------------------
local function TestMenuFilter()
    local Filter = ns.UI.FilterMenuItems

    local items = {
        { heading = true, text = "Shipped with ZwoelfStuff" },
        { text = "ZS Flat" }, { text = "ZS Smooth" },
        { heading = true, text = "From your other addons" },
        { text = "Blizzard" }, { text = "Details Flat" },
    }

    Check("No filter returns everything", #Filter(items, nil) == 6)
    Check("An empty filter returns everything", #Filter(items, "") == 6)

    -- Two hits, in two different groups, so both headings stay.
    local flat = Filter(items, "flat")
    Check("It matches anywhere in the name, not just the start",
        #flat == 4, tostring(#flat))
    Check("Both groups keep their heading",
        flat[1].heading and flat[3].heading)

    -- One hit, in the SECOND group: the first heading must not survive on its
    -- own. This is the case that looks fine until you try it.
    local one = Filter(items, "blizz")
    Check("A group with no survivors loses its heading",
        #one == 2 and one[1].text == "From your other addons",
        tostring(#one) .. " " .. tostring(one[1] and one[1].text))

    Check("Filtering is case-insensitive", #Filter(items, "ZS ") == 3)
    Check("No hits at all is an empty list", #Filter(items, "zzz") == 0)
    Check("A nil list is not a crash", #Filter(nil, "flat") == 0)
end

---------------------------------------------------------------------------
-- The text elements
--
-- The charge count split off from the stack count, and a split like that has
-- three ways to go wrong that nothing on screen would show you: the new
-- element never reaching the renderer, the migration not carrying the old
-- look over, and the two ending up sharing one colour table so that editing
-- either edits both.
--
-- ns.TextOffset is checked here rather than in the design suite because it is
-- the ONE piece of arithmetic both renderers run. A drawn cell and an adopted
-- icon sitting on the same bar disagreeing about where "bottom right" is, is
-- exactly the class of bug this addon keeps finding by eye.
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- THE REMINDERS.
--
-- Three things are worth checking without a screen, and they are the three
-- that would be silent faults:
--
--   The trigger, which is one word turning into a decision. Getting it
--   backwards means a message that shows exactly when nothing is wrong, and
--   nothing about that looks like a bug from the code.
--
--   "Cannot answer" is not "not active". A spell the Cooldown Manager does
--   not track has to make the reminder SILENT, or every mistyped spell sits
--   on screen forever insisting a buff is gone.
--
--   The flash, whose whole job is to never reach nothing. A message that
--   vanishes and comes back is one you have to catch.
--
-- The geometry is a pure function for the usual reason: the harness answers
-- GetStringWidth with a stub, so the arithmetic is checked here and the
-- drawing is checked by a pair of eyes.
---------------------------------------------------------------------------
local function TestReminders()
    local Reminders = ns.Reminders

    -- The trigger, all four combinations.
    Check("'Not active' fires when it is idle",
        Reminders.Fires("missing", "idle") == true)
    Check("'Not active' stays quiet while it is up",
        Reminders.Fires("missing", "active") == false)
    Check("'While active' fires while it is up",
        Reminders.Fires("active", "active") == true)
    Check("'While active' stays quiet when it is idle",
        Reminders.Fires("active", "idle") == false)

    -- AN UNANSWERABLE STATE IS SILENT, both ways round. This is the one that
    -- matters: nil is not false.
    Check("An unknown state fires nothing (missing)",
        Reminders.Fires("missing", nil) == false)
    Check("An unknown state fires nothing (active)",
        Reminders.Fires("active", nil) == false)

    -- Every trigger in the vocabulary is one the evaluator answers. A word in
    -- the dropdown that Fires has never heard of would silently behave like
    -- "missing".
    for _, entry in ipairs(ns.REMINDER_TRIGGERS) do
        local onActive = Reminders.Fires(entry.value, "active")
        local onIdle = Reminders.Fires(entry.value, "idle")
        Check("Trigger '" .. entry.value .. "' tells the two states apart",
            onActive ~= onIdle, tostring(onActive) .. "/" .. tostring(onIdle))
    end

    -- The flash never reaches nothing, and it does come back to full.
    local floor = 0.25
    local lowest, highest = 1, 0
    for step = 0, 40 do
        local alpha = Reminders.FlashAlpha(step / 40, 1, floor)
        if alpha < lowest then lowest = alpha end
        if alpha > highest then highest = alpha end
        if alpha < floor - 0.001 or alpha > 1.001 then
            Check("The flash stays inside its range", false,
                string.format("%.3f at %d", alpha, step))
        end
    end
    Check("The flash reaches full brightness", highest > 0.99,
        string.format("%.3f", highest))
    Check("The flash dims to the floor", Near(lowest, floor, 0.02),
        string.format("%.3f", lowest))
    Check("A flash rate of nothing is a steady message",
        Reminders.FlashAlpha(1.7, 0, 0.25) == 1)

    -- The box is measured, and the icon has to be inside it.
    local wide, tall = Reminders.Extent(120, 30, "left", 40, 8)
    Check("The icon widens the box", wide == 168, tostring(wide))
    Check("A tall icon raises the box", tall == 40, tostring(tall))
    local plainW, plainH = Reminders.Extent(120, 30, "none", 40, 8)
    Check("No icon, no extra width", plainW == 120, tostring(plainW))
    Check("No icon, the text's own height", plainH == 30, tostring(plainH))
    local zeroW, zeroH = Reminders.Extent(0, 0, "none", 0, 8)
    Check("An empty reminder still has a size", zeroW >= 1 and zeroH >= 1)

    -- The store, and the label that must never be empty.
    local before = Reminders:Count()
    local index = Reminders:Add()
    Check("A new reminder is added", index ~= nil and Reminders:Count() == before + 1)
    if index then
        local cfg = Reminders:Get(index)
        Check("A brand new reminder still has a name",
            (Reminders:Label(cfg, index) or "") ~= "")
        Check("It waits for combat by default", cfg.show.combat == "in",
            tostring(cfg.show.combat))
        -- WITH NO SPELL it cannot answer, and therefore must not show.
        Check("With nothing to watch it stays off the screen",
            Reminders:ShouldShow(cfg) == false)
        Check("And it says why", (Reminders:Explain(cfg) or "") ~= "")

        cfg.text = "  BONE SHIELD  \nsecond line"
        Check("The name comes off the first line of the text",
            Reminders:Label(cfg, index) == "BONE SHIELD",
            Reminders:Label(cfg, index))

        Reminders:Remove(index)
    end
    Check("A removed reminder is gone", Reminders:Count() == before,
        tostring(Reminders:Count()))
end

---------------------------------------------------------------------------
-- THE ROUTES.
--
-- Two pure rules decide everything this feature does, and both fail silently
-- if they are wrong - a badge on the wrong mob looks exactly like a badge on
-- the right one.
local function TestTextElements()
    local byKey = {}
    for _, element in ipairs(ns.TEXT_ELEMENTS) do byKey[element.key] = element end

    Check("Charges are their own text element", byKey.charges ~= nil)
    Check("Stacks and charges are two entries, not one",
        byKey.stacks ~= nil and byKey.charges ~= nil
            and byKey.stacks ~= byKey.charges)

    -- Every element in the list must be a real default, or the options panel
    -- generates seven controls that read and write a table nothing renders.
    for _, element in ipairs(ns.TEXT_ELEMENTS) do
        Check("'" .. element.label .. "' has defaults to edit",
            type(ns.BAR_DEFAULTS[element.key]) == "table")

        local travels = false
        for _, key in ipairs(ns.BAR_STYLE_KEYS) do
            if key == element.key then travels = true end
        end
        Check("'" .. element.label .. "' travels with a saved look", travels)
    end

    -- And it has to reach the renderer with its size resolved. A size of 0
    -- means "work it out from the cell", and an element that skipped that step
    -- would be drawn at zero.
    local style = ns.Bars:Style(Fresh({ kind = "bar" }), 24)
    Check("The charge count reaches the renderer",
        type(style.charges) == "table" and Finite(style.charges.size)
            and style.charges.size > 0,
        tostring(style.charges and style.charges.size))

    -- THE MIGRATION. Both numbers used to be driven by `stacks`, so a bar that
    -- had moved its stack count keeps that placement for its charges rather
    -- than snapping back to the default on update.
    local old = Fresh()
    old.charges = nil
    old.stacks = { show = true, font = "", size = 14, color = { 1, 0.5, 0 },
        outline = "THICKOUTLINE", anchor = "TOPLEFT", x = 3, y = -2 }

    local saved = ns.db.bars
    ns.db.bars = { old }
    ns.Bars:Prepare()
    ns.db.bars = saved

    Check("An older bar inherits its stack placement for charges",
        old.charges ~= nil and old.charges.anchor == "TOPLEFT"
            and old.charges.x == 3 and old.charges.size == 14,
        old.charges and tostring(old.charges.anchor) or "nil")

    -- A SHARED COLOUR TABLE would make the two settings one setting again, one
    -- indirection further down where it is much harder to see: the panel would
    -- write a colour into charges and the stack count would change with it.
    Check("The two do not share one colour table",
        old.charges.color ~= old.stacks.color
            and old.charges.color[1] == old.stacks.color[1])

    -- Replay-safe: a second Prepare must not undo a charge placement the user
    -- has since moved. This is the failure the fillDirection migration was
    -- moved out of Migrate to avoid, and it only shows on the NEXT login.
    old.charges.anchor = "BOTTOM"
    ns.db.bars = { old }
    ns.Bars:Prepare()
    ns.db.bars = saved
    Check("Preparing twice does not undo the user's own placement",
        old.charges.anchor == "BOTTOM", tostring(old.charges.anchor))

    -- The nine positions. A corner insets itself so an outlined glyph is not
    -- clipped by the border; the centre does not, because there is no edge to
    -- be clipped by and an inset there would just be off centre.
    local function At(anchor, x, y)
        return ns.TextOffset({ anchor = anchor, x = x or 0, y = y or 0 })
    end

    local cx, cy = At("CENTER")
    Check("The centre is not inset", cx == 0 and cy == 0)

    local bx, by = At("BOTTOMRIGHT")
    Check("Bottom right insets inwards on both axes", bx == -2 and by == 2,
        bx .. "," .. by)

    local tx, ty = At("TOPLEFT")
    Check("Top left insets the other way", tx == 2 and ty == -2,
        tx .. "," .. ty)

    local nx, ny = At("CENTER", 5, -7)
    Check("The nudge is added to the position", nx == 5 and ny == -7)

    local mx, my = At("TOPLEFT", -2, 2)
    Check("A nudge can cancel the inset", mx == 0 and my == 0)

    -- What a font string's setter may be handed. CanDisplay is the opposite of
    -- CanCompute on purpose: it says "this may be PRINTED and nothing else".
    -- A secret cannot be made here, so what is checked is the plain half.
    Check("A plain number may be displayed", ns.CanDisplay(3))
    Check("Nothing at all may not", not ns.CanDisplay(nil))
    Check("A string is not a count", not ns.CanDisplay("3"))
end

---------------------------------------------------------------------------
-- The game menu entry
--
-- Our button hangs under the LAST of Blizzard's, and both halves of working
-- that out fail silently: pick the wrong two and it sits in the middle of the
-- menu, get the gap backwards and it lands on the entry above it. Neither
-- throws, and both need the pause menu open to look at - which is exactly the
-- shape of the snapping bug that was misdiagnosed three times by reading.
---------------------------------------------------------------------------
local function TestGameMenu()
    local Menu = ns.GameMenu
    local function Bottom(item) return item.y end

    -- Deliberately out of order: the menu's pool does not enumerate in
    -- layout order, and code that assumed it did would pass a sorted fixture.
    local buttons = {
        { name = "options", y = 400 },
        { name = "editmode", y = 100 },
        { name = "addons",  y = 200 },
        { name = "shop",    y = 300 },
    }

    local lowest, second = Menu.TwoLowest(buttons, Bottom)
    Check("The bottom-most button is found whatever the order",
        lowest and lowest.name == "editmode", lowest and lowest.name or "nil")
    Check("And the one directly above it",
        second and second.name == "addons", second and second.name or "nil")

    -- A button the menu is not showing is not in the running. Hanging ours
    -- under a hidden one puts it in empty space below the frame.
    local hidden = Menu.TwoLowest({
        { name = "shown", y = 300 },
        { name = "hidden", y = 100, gone = true },
    }, function(item) return not item.gone and item.y or nil end)
    Check("A hidden button is not the anchor",
        hidden and hidden.name == "shown", hidden and hidden.name or "nil")

    Check("An empty menu has no anchor at all", Menu.TwoLowest({}, Bottom) == nil)
    Check("One button alone has no partner to measure against",
        select(2, Menu.TwoLowest({ { y = 1 } }, Bottom)) == nil)

    -- The gap: the bottom of the button ABOVE, minus the top of the one below
    -- it. Backwards, this is negative and the entry lands on its neighbour.
    Check("The gap is measured between the two edges that face each other",
        Menu.GapBetween(100, 112) == 12, tostring(Menu.GapBetween(100, 112)))
    Check("A different spacing is followed rather than assumed",
        Menu.GapBetween(100, 104) == 4, tostring(Menu.GapBetween(100, 104)))

    -- Everything the arithmetic cannot make sense of falls back rather than
    -- producing a number: a menu laid out some other way is not something to
    -- guess at.
    Check("Overlapping buttons fall back", Menu.GapBetween(100, 90) == 12)
    Check("An absurd gap falls back", Menu.GapBetween(0, 5000) == 12)
    Check("A missing partner falls back", Menu.GapBetween(100, nil) == 12)
    Check("A missing measurement falls back", Menu.GapBetween(nil, nil) == 12)
end

---------------------------------------------------------------------------
-- Anchors that were wrong on screen and right-looking in the source
--
-- The spark was drawn with no height for its whole life, and the spell name
-- ignored its position outright. Neither throws, neither shows up in a static
-- check, and both need a bar on screen with a running cooldown on it to see.
-- So the naming is done by functions that take strings and return strings,
-- and those are what is checked here.
---------------------------------------------------------------------------
local function TestAnchors()
    -- THE SPARK rides the end the fill GROWS TOWARDS. On the other end it
    -- never moves, and a spark that does not move is not a spark.
    local Edge = ns.Layout.SparkEdge
    Check("A left-to-right fill carries it on the right",
        Edge("HORIZONTAL", false) == "RIGHT", Edge("HORIZONTAL", false))
    Check("A right-to-left fill carries it on the left",
        Edge("HORIZONTAL", true) == "LEFT", Edge("HORIZONTAL", true))
    Check("A bottom-to-top fill carries it on the top",
        Edge("VERTICAL", false) == "TOP", Edge("VERTICAL", false))
    Check("A top-to-bottom fill carries it on the bottom",
        Edge("VERTICAL", true) == "BOTTOM", Edge("VERTICAL", true))

    -- The four answers must be four DIFFERENT edges. Two directions sharing
    -- one is how a spark ends up parked on the fixed end of half the bars.
    local edges = {}
    for _, orientation in ipairs({ "HORIZONTAL", "VERTICAL" }) do
        for _, reverse in ipairs({ true, false }) do
            local edge = Edge(orientation, reverse)
            Check("'" .. edge .. "' is claimed only once", not edges[edge],
                orientation .. " " .. tostring(reverse))
            edges[edge] = true
        end
    end

    -- And a horizontal spark must never ride a horizontal edge - that is the
    -- axis the fill runs along, so it would lie ALONG the bar rather than
    -- across it. The mistake the charge marks made in 4.27.0, one file over.
    Check("A horizontal fill's edge is a side, not a top or a bottom",
        Edge("HORIZONTAL", false):find("LEFT")
            or Edge("HORIZONTAL", false):find("RIGHT"))
    Check("A vertical fill's edge is a top or a bottom, not a side",
        Edge("VERTICAL", false):find("TOP")
            or Edge("VERTICAL", false):find("BOTTOM"))

    -- THE SPELL NAME. Nine positions, and the middle of the middle is the one
    -- that breaks: the vertical part is empty there, and an empty string is
    -- not a point - SetPoint("") is an error at layout time on every bar.
    for _, entry in ipairs(ns.TEXT_ANCHORS) do
        local point, side, justify, vertical = ns.Layout.LabelAnchor(entry.value)

        -- The vertical half is a PREFIX, and the label hangs from both edges
        -- of the band by concatenating it: vertical .. "LEFT" and
        -- vertical .. "RIGHT". An unexpected value there is SetPoint on a
        -- point that does not exist, which is an error at layout time on
        -- every bar rather than something you notice later.
        Check("'" .. entry.text .. "' has a usable vertical half",
            vertical == "" or vertical == "TOP" or vertical == "BOTTOM",
            tostring(vertical))
        Check("'" .. entry.text .. "' spans the band from both edges",
            (vertical .. "LEFT"):find("LEFT") ~= nil
                and (vertical .. "RIGHT"):find("RIGHT") ~= nil)
        Check("'" .. entry.text .. "' names a real point",
            type(point) == "string" and point ~= "", tostring(point))
        Check("'" .. entry.text .. "' reads in a real direction",
            justify == "LEFT" or justify == "RIGHT" or justify == "CENTER",
            tostring(justify))
        -- The inset only belongs to the two columns that have an edge to be
        -- inset from. A centred name pushed in by the icon gap is off centre.
        Check("'" .. entry.text .. "' insets only where there is an edge",
            (side == nil) == (not entry.value:find("LEFT")
                and not entry.value:find("RIGHT")))
    end

    Check("The centre of the centre is CENTER",
        ns.Layout.LabelAnchor("CENTER") == "CENTER")
    Check("Top centre is a point of its own",
        ns.Layout.LabelAnchor("TOP") == "TOP")
    Check("A corner keeps both halves",
        ns.Layout.LabelAnchor("BOTTOMRIGHT") == "BOTTOMRIGHT")
    Check("Nothing at all falls back to the left",
        ns.Layout.LabelAnchor(nil) == "LEFT")

    -- The three rows, spelled out. These are the strings the label's two
    -- points are built from, so a wrong one is an invalid SetPoint.
    Check("The middle row has no vertical part",
        ns.Layout.LabelVertical("RIGHT") == ""
            and ns.Layout.LabelVertical("CENTER") == "")
    Check("The top row prefixes TOP",
        ns.Layout.LabelVertical("TOPRIGHT") == "TOP")
    Check("The bottom row prefixes BOTTOM",
        ns.Layout.LabelVertical("BOTTOM") == "BOTTOM")

    -- The band the name lives in, beside the icon.
    local left, right = ns.Layout.LabelBand("left", 22)
    Check("An icon on the left pushes the name past it",
        left == 27 and right == 5, left .. "/" .. right)

    left, right = ns.Layout.LabelBand("right", 22)
    Check("An icon on the right keeps the name off it",
        left == 5 and right == 27, left .. "/" .. right)

    left, right = ns.Layout.LabelBand("hidden", 0)
    Check("No icon leaves the whole width", left == 5 and right == 5)
end

---------------------------------------------------------------------------
-- The two aura strips on a co-tank row
--
-- They shipped drawing on top of each other and nothing here noticed, because
-- nothing here asked. The old arrangement was two strips on the SAME edge
-- growing towards each other, which reads as "away from each other" and is
-- not: eight icons at 22 is 183 of a 240 row, so they met in the middle.
--
-- The rule that replaces it is one a test can hold: the two strips live on
-- DIFFERENT vertical edges. That is true at any icon count, any size and any
-- row width, which the old arrangement never was at any of them.
---------------------------------------------------------------------------
local function TestCoTankStrips()
    local defaults = ns.DEFAULTS and ns.DEFAULTS.coTanks
    if not defaults then
        Skip("Co-tank strips", "no co-tank defaults")
        return
    end

    local function Edge(anchor)
        return tostring(anchor):find("TOP") and "top" or "bottom"
    end

    Check("The two strips do not share an edge",
        Edge(defaults.debuffs.anchor) ~= Edge(defaults.buffs.anchor),
        defaults.debuffs.anchor .. " / " .. defaults.buffs.anchor)
    Check("Debuffs sit on the top edge", defaults.debuffs.anchor == "TOPLEFT")
    Check("Buffs sit on the bottom edge", defaults.buffs.anchor == "BOTTOMLEFT")
    Check("Both strips read left to right",
        defaults.debuffs.growth == "right" and defaults.buffs.growth == "right")

    -- THE ARITHMETIC THAT WAS NEVER DONE. Kept as a check rather than a
    -- comment: if somebody widens the strips or narrows the row later, the
    -- old arrangement stops being merely wrong and starts being wrong again.
    local width = defaults.debuffs.perRow * defaults.debuffs.size
        + (defaults.debuffs.perRow - 1) * defaults.debuffs.spacing
    Check("A full strip is wider than half the row - which is why one edge each",
        width > defaults.width / 2, width .. " of " .. defaults.width)

    ---------------------------------------------------------------------
    -- The migration off the overlapping pair
    ---------------------------------------------------------------------
    local old = {
        debuffs = { anchor = "BOTTOMLEFT", growth = "right" },
        buffs   = { anchor = "BOTTOMRIGHT", growth = "left" },
    }
    ns.CoTanks:Migrate(old)
    Check("An untouched panel is moved off the overlap",
        old.debuffs.anchor == "TOPLEFT" and old.buffs.anchor == "BOTTOMLEFT"
            and old.buffs.growth == "right")

    -- AND THE ONE THAT MUST NOT MOVE. A setting that changes itself back
    -- after somebody has fixed it is worse than the fault it is fixing.
    local chosen = {
        debuffs = { anchor = "BOTTOMLEFT", growth = "right" },
        buffs   = { anchor = "TOPRIGHT",  growth = "left" },
    }
    ns.CoTanks:Migrate(chosen)
    Check("A panel somebody has already moved is left alone",
        chosen.debuffs.anchor == "BOTTOMLEFT" and chosen.buffs.anchor == "TOPRIGHT"
            and chosen.buffs.growth == "left")

    local bare = {}
    ns.CoTanks:Migrate(bare)
    Check("A profile with no strips yet is not invented", bare.debuffs == nil)
end

---------------------------------------------------------------------------
-- Moving somebody's settings from one shape to another
--
-- THE ONE FUNCTION IN THIS ADDON THAT CAN LOSE WORK. Everything else that
-- goes wrong costs a reload; this one deletes the old copy after writing the
-- new one, so a mistake here is bars that were there yesterday and are not
-- there now. It runs once, on a login, against data nobody can hand back.
--
-- Asserted against a made-up store rather than trusted, and the case that
-- matters most is the second run: a migration that is not idempotent has
-- already worked once by the time anybody could notice.
---------------------------------------------------------------------------
local function TestProfileMigration()
    local Profiles = ns.Profiles
    if not (Profiles and Profiles.Migrate) then
        Skip("Profile migration", "Profiles.lua did not load")
        return
    end

    local key = ns.CharacterKey()
    if not key then
        Skip("Profile migration", "the client will not name this character")
        return
    end

    ---------------------------------------------------------------------
    -- A file written before profiles existed at all: everything sat at the
    -- root and belonged to whoever was playing.
    ---------------------------------------------------------------------
    local ancient = {
        bars = { { id = 1 } },
        font = "Friz Quadrata TT",
        procs = { [195181] = 10 },
    }
    Profiles.Migrate(ancient)

    Check("An ancient file keeps its bars",
        ancient.profiles and ancient.profiles[key]
            and #ancient.profiles[key].bars == 1)
    Check("An ancient file keeps its settings",
        ancient.profiles[key].font == "Friz Quadrata TT")
    Check("The character is pointed at its own profile",
        ancient.charProfile and ancient.charProfile[key] == key)
    Check("The measurements are lifted out to the account",
        ancient.account and ancient.account.procs
            and ancient.account.procs[195181] == 10)
    Check("A measurement does not ALSO stay in the profile",
        ancient.profiles[key].procs == nil)
    Check("Nothing is left loose at the root", ancient.bars == nil)

    ---------------------------------------------------------------------
    -- The shape before this update: settings under a character key.
    ---------------------------------------------------------------------
    local chars = {
        chars = {
            ["Zwoelf - Destromath"] = { bars = { { id = 1 }, { id = 2 } } },
            ["Alt - Destromath"]    = { bars = { { id = 9 } } },
        },
        account = { procs = {} },
    }
    Profiles.Migrate(chars)

    Check("Every character becomes a profile named after it",
        chars.profiles["Zwoelf - Destromath"] and chars.profiles["Alt - Destromath"])
    Check("Each one keeps its own bars",
        #chars.profiles["Zwoelf - Destromath"].bars == 2
            and #chars.profiles["Alt - Destromath"].bars == 1)
    Check("Each character points at its own",
        chars.charProfile["Zwoelf - Destromath"] == "Zwoelf - Destromath"
            and chars.charProfile["Alt - Destromath"] == "Alt - Destromath")
    Check("The old shape is gone once it is safely moved", chars.chars == nil)

    -- THE COPY PATH AND THE MIGRATION MUST AGREE ABOUT WHERE BARS LIVE.
    -- CopyLayoutFrom read the pre-migration shape for a whole version -
    -- store.chars, which the migration deletes - so every "Take a layout
    -- from" answered "that character has no bars" while the dropdown listed
    -- them. This asks the migrated store through the same lookup the copy
    -- uses now.
    local lifted = ns.Profiles:BarsOfCharacter("Alt - Destromath", chars)
    Check("The copy path finds a migrated character's bars",
        lifted ~= nil and #lifted == 1 and lifted[1].id == 9)
    Check("The copy path does not resurrect the deleted shape",
        ns.Profiles:BarsOfCharacter("Alt - Destromath",
            { chars = { ["Alt - Destromath"] = { bars = { { id = 9 } } } } }) == nil)

    ---------------------------------------------------------------------
    -- RUN IT AGAIN. This is the one that would go unnoticed: a migration
    -- that is not idempotent has already succeeded once by the time anybody
    -- could see it fail.
    ---------------------------------------------------------------------
    Profiles.Migrate(chars)
    Check("Migrating twice changes nothing",
        #chars.profiles["Zwoelf - Destromath"].bars == 2
            and chars.charProfile["Alt - Destromath"] == "Alt - Destromath")

    ---------------------------------------------------------------------
    -- A name that is already taken must never be written over. The old
    -- table is deleted right after, so an overwrite here is not a clash -
    -- it is the other profile being gone.
    ---------------------------------------------------------------------
    local clash = {
        chars = { ["Zwoelf - Destromath"] = { bars = { { id = 1 } } } },
        profiles = { ["Zwoelf - Destromath"] = { bars = { { id = 7 }, { id = 8 } } } },
        charProfile = {},
    }
    Profiles.Migrate(clash)
    Check("A profile that already has the name is not written over",
        #clash.profiles["Zwoelf - Destromath"].bars == 2
            and clash.profiles["Zwoelf - Destromath"].bars[1].id == 7)

    ---------------------------------------------------------------------
    -- A fresh install has nothing to move and must not invent anything.
    ---------------------------------------------------------------------
    local fresh = { profiles = {}, charProfile = {}, account = {} }
    Profiles.Migrate(fresh)
    Check("A fresh file is left empty rather than seeded",
        next(fresh.profiles) == nil and next(fresh.charProfile) == nil)

    ---------------------------------------------------------------------
    -- Names people type
    ---------------------------------------------------------------------
    Check("A name is trimmed", Profiles.CleanName("  Raid  ") == "Raid")
    Check("A name of only spaces is refused", Profiles.CleanName("   ") == nil)
    Check("An empty name is refused", Profiles.CleanName("") == nil)
    Check("A non-string is refused", Profiles.CleanName(nil) == nil)
    Check("A very long name is cut rather than refused",
        #Profiles.CleanName(string.rep("x", 200)) == 64)
end

---------------------------------------------------------------------------
-- Sharing
--
-- The one part of this addon whose output goes to a STRANGER. Everything else
-- that breaks costs the person who broke it a reload; a string that packs
-- wrong is pasted into a Discord and fails on somebody else's machine, where
-- nobody can see what happened. So the round trip is asserted here rather
-- than trusted, and so is every refusal - a wrong error message sends the
-- reader to a bug report when the real problem was a truncated paste.
---------------------------------------------------------------------------
local function TestShare()
    local Share = ns.Share
    if not Share then
        Skip("Sharing", "Share.lua did not load")
        return
    end

    -- THE LIBRARIES, first and by name. Everything below is meaningless if
    -- these are absent, and "nothing failed" while nothing ran is the exact
    -- shape of a check more generous than the thing it checks.
    local haveSerialize = LibStub and LibStub("LibSerialize", true) and true or false
    local haveDeflate   = LibStub and LibStub("LibDeflate", true) and true or false
    Check("LibSerialize is loaded", haveSerialize)
    Check("LibDeflate is loaded", haveDeflate)
    if not (haveSerialize and haveDeflate) then return end

    ---------------------------------------------------------------------
    -- Out and back
    ---------------------------------------------------------------------
    local payload = {
        stamp = { class = "DEATHKNIGHT", spec = 250, specName = "Blood" },
        label = "Zwoelf M+",
        parts = {
            bars = {
                { id = 3, rows = 2, cols = 4, cells = { [1] = 49028, [2] = 55233 },
                  colour = { 0.1, 0.2, 0.3, 1 }, anchor = { to = 7, point = "TOP" } },
                { id = 7, rows = 1, cols = 6, cells = {} },
            },
            reminders = { { text = "Bone Shield", spellID = 195181, trigger = "missing" } },
            presets = { ["My look"] = { barWidth = 210, gap = 3 } },
        },
    }

    local text, err = Share.Encode(payload)
    Check("A profile packs into a string", type(text) == "string", err)

    if type(text) == "string" then
        Check("The string carries the format in its prefix",
            text:sub(1, #Share.PREFIX) == Share.PREFIX, text:sub(1, 8))

        -- Printable in the sense the name promises: this gets pasted into a
        -- chat window, and one byte the client eats takes the whole string.
        Check("The string is printable text",
            not text:find("[%z\1-\31\127]"), "control character in the string")

        local back, backErr = Share.Decode(text)
        Check("The string unpacks again", type(back) == "table", backErr)

        if type(back) == "table" then
            Check("The format version survives", back.v == Share.FORMAT)
            Check("The label survives", back.label == "Zwoelf M+")
            Check("The class stamp survives", back.stamp and back.stamp.class == "DEATHKNIGHT")
            Check("Both bars survive", back.parts.bars and #back.parts.bars == 2)

            local first = back.parts.bars and back.parts.bars[1]
            Check("A bar's grid survives", first and first.rows == 2 and first.cols == 4)
            Check("A spell in a cell survives", first and first.cells and first.cells[1] == 49028)
            Check("A colour survives to the decimal",
                first and first.colour and first.colour[1] == 0.1 and first.colour[4] == 1)
            Check("An attachment survives", first and first.anchor and first.anchor.to == 7)
            Check("A reminder survives",
                back.parts.reminders and back.parts.reminders[1]
                and back.parts.reminders[1].spellID == 195181)
            Check("A saved look survives by its name",
                back.parts.presets and back.parts.presets["My look"]
                and back.parts.presets["My look"].barWidth == 210)
        end

        -- Whitespace at either end is what a forum and a chat window add, and
        -- it is far more common than real corruption.
        local padded = Share.Decode("  \n" .. text .. "\n  ")
        Check("A string pasted with spaces around it still opens", type(padded) == "table")
    end

    ---------------------------------------------------------------------
    -- Every refusal, in its own words
    ---------------------------------------------------------------------
    local function Refuses(name, input, wanted)
        local got, why = Share.Decode(input)
        local ok = got == nil and type(why) == "string" and why:find(wanted, 1, true) ~= nil
        Check(name, ok, why or "it was ACCEPTED")
    end

    Refuses("Nothing pasted in says so", "", "nothing pasted in")
    Refuses("Only spaces says the same", "   \n ", "nothing pasted in")
    Refuses("Somebody else's string names ours", "!EUI_abcdef", "not a ZwoelfStuff string")
    Refuses("Plain typing is not a string", "hello", "not a ZwoelfStuff string")

    -- The one that matters most: a FUTURE format has to read as "update the
    -- addon", not as "damaged". They are different problems and only one of
    -- them is the reader's to fix.
    Refuses("A newer format asks for an update", "!ZS9_abcdef", "newer ZwoelfStuff")

    Refuses("A cut-short string says it was cut short",
        Share.PREFIX .. "!!!!not printable at all!!!!", "cut short")

    if type(text) == "string" then
        -- Half a string. The prefix is intact and the payload is not, which is
        -- exactly what a chat window's length limit produces.
        Refuses("Half a string is reported as damaged",
            text:sub(1, math.floor(#text / 2)), "damaged")
    end

    -- A valid string holding nothing is not an error in the format; it is an
    -- empty export, and saying "damaged" would send somebody looking for a
    -- corruption that is not there.
    local empty = Share.Encode({ parts = {} })
    Refuses("An empty export says it is empty", empty, "nothing in it")

    ---------------------------------------------------------------------
    -- A PART THIS BUILD DOES NOT KNOW must cost that part and nothing else.
    -- The alternative is that adding a sixth part in a later version makes
    -- every string from it unopenable in this one.
    ---------------------------------------------------------------------
    local mixed = Share.Encode({
        parts = { bars = { { id = 1 } }, somethingNewer = { 1, 2, 3 } },
    })
    local got = mixed and Share.Decode(mixed)
    Check("An unknown part is dropped, not refused",
        type(got) == "table" and got.parts.bars ~= nil and got.parts.somethingNewer == nil)
    Check("The dropped part is reported",
        type(got) == "table" and got.dropped and got.dropped[1] == "somethingNewer")

    local allNew = Share.Encode({ parts = { somethingNewer = { 1 } } })
    Refuses("A string of nothing BUT unknown parts says so", allNew, "newer version")

    ---------------------------------------------------------------------
    -- Whose spells these are
    ---------------------------------------------------------------------
    local mine = { class = "DEATHKNIGHT" }
    Check("The same class fits",
        Share.SpellsFit({ class = "DEATHKNIGHT" }, mine) == true)
    Check("A different class does not fit",
        Share.SpellsFit({ class = "PALADIN" }, mine) == false)

    -- THREE ANSWERS, NOT TWO. An unstamped string used to read as a match,
    -- which is the same silent yes as a real one and the more dangerous of
    -- the two - it puts uncastable spells on a bar and says nothing.
    Check("An unstamped string answers 'cannot tell'",
        Share.SpellsFit(nil, mine) == nil)
    Check("A stamp with no class answers 'cannot tell'",
        Share.SpellsFit({ spec = 250 }, mine) == nil)

    ---------------------------------------------------------------------
    -- Taking somebody else's bars
    ---------------------------------------------------------------------
    local counter = 100
    local function NextID() counter = counter + 1 return counter end

    local source = {
        { id = 1, cells = { 49028 }, cellsBySpec = { [250] = { 49028 } },
          parked = { 55233 }, rows = 1, cols = 3 },
        { id = 2, anchor = { to = 1, point = "TOP" } },
        { id = 3, anchor = { to = 99, point = "TOP" } },  -- target never travels
    }

    local taken = Share.AdoptBars(source, NextID, false)
    Check("Every bar comes across", #taken == 3)
    Check("Every bar gets a new id",
        taken[1].id == 101 and taken[2].id == 102 and taken[3].id == 103)
    Check("An attachment follows its bar to the new id", taken[2].anchor.to == 101)
    Check("An attachment to a bar that did not travel is dropped",
        taken[3].anchor == nil)

    Check("Without the spells, the cells arrive empty",
        taken[1].cells and next(taken[1].cells) == nil)
    Check("Without the spells, the per-spec cells are gone too",
        taken[1].cellsBySpec == nil)
    Check("Without the spells, the parked ones are gone as well",
        taken[1].parked and next(taken[1].parked) == nil)
    Check("The grid still comes across",
        taken[1].rows == 1 and taken[1].cols == 3)

    -- THE SOURCE MUST NOT MOVE. It is somebody's live profile on the copy
    -- path, and a shallow copy here would have edited their bars while
    -- claiming to read them.
    Check("Adopting does not touch what it read from",
        source[1].cells[1] == 49028 and source[3].anchor ~= nil
            and source[1].id == 1)

    counter = 200
    local kept = Share.AdoptBars(source, NextID, true)
    Check("With the spells, the cells arrive filled", kept[1].cells[1] == 49028)
    Check("With the spells, the per-spec cells arrive too",
        kept[1].cellsBySpec and kept[1].cellsBySpec[250]
            and kept[1].cellsBySpec[250][1] == 49028)
    Check("With the spells, the ids are still re-issued", kept[1].id == 201)

    Check("Nothing to adopt is not an error", select(2, Share.AdoptBars({}, NextID, false)) == 0)
    Check("Adopting a non-table is not an error", select(2, Share.AdoptBars(nil, NextID, false)) == 0)

    ---------------------------------------------------------------------
    -- Packing up what is ticked, and writing one in
    ---------------------------------------------------------------------
    local db = {
        bars = { { id = 1, rows = 1, cols = 2, cells = { 49028 } },
                 { id = 2, rows = 1, cols = 2, cells = { 55233 } } },
        lastBarID = 2,
        reminders = { { text = "Bone Shield", spellID = 195181 } },
        coTanks = { enabled = true, width = 240 },
        barPresets = { Main = { barWidth = 200 } },
        font = "Friz Quadrata TT",
    }

    local all = Share.Gather(db, {
        bars = true, reminders = true, coTanks = true,
        presets = true, settings = true,
    })
    Check("Everything ticked packs every part",
        all.bars and all.reminders and all.coTanks and all.presets and all.settings)

    -- lastBarID must NOT be a part. It is dropped as unknown on arrival, and
    -- the receiver re-issues ids from its own counter anyway.
    Check("The id counter is not packed as a part", all.lastBarID == nil)
    Check("The id counter is not packed as a setting",
        all.settings and all.settings.lastBarID == nil)
    Check("The file's shape version does not travel",
        all.settings and all.settings.dbVersion == nil)
    Check("A loose setting travels without being listed anywhere",
        all.settings and all.settings.font == "Friz Quadrata TT")

    local one = Share.Gather(db, { bars = true, barIDs = { [2] = false } })
    Check("A bar left unticked stays behind", one.bars and #one.bars == 1)
    Check("The bar that travelled is the ticked one", one.bars[1].id == 1)
    Check("Nothing else comes along uninvited",
        one.reminders == nil and one.coTanks == nil and one.settings == nil)

    -- A ticked part with nothing in it is left out. Otherwise the import
    -- window promises reminders and none arrive.
    local bare = Share.Gather({ bars = {} }, { bars = true, reminders = true })
    Check("A ticked part with nothing in it is left out",
        bare.bars == nil and bare.reminders == nil)

    -- WRITING IN: added, never substituted. There is no undo here, and
    -- pasting a stranger's string must not be able to delete an evening.
    local target = {
        bars = { { id = 40, cells = { 999 } } },
        reminders = { { text = "already here" } },
        barPresets = { Main = { barWidth = 111 } },
    }
    local nextFreeID = 500
    local applied = Share.Apply(target, { parts = all }, {
        nextID = function() nextFreeID = nextFreeID + 1 return nextFreeID end,
        keepSpells = true,
    })

    Check("Imported bars are ADDED to the ones you have", #target.bars == 3)
    Check("The bar you already had is untouched", target.bars[1].id == 40)
    Check("Imported bars get ids from YOUR counter",
        target.bars[2].id == 501 and target.bars[3].id == 502)
    Check("Imported reminders are added too", #target.reminders == 2)
    Check("The panel is a single thing, so it does replace",
        target.coTanks and target.coTanks.width == 240)
    Check("A look with a name you already use keeps BOTH",
        target.barPresets.Main.barWidth == 111
            and target.barPresets["Main (imported)"] ~= nil)
    Check("Applying reports what it did",
        applied.bars == 2 and applied.reminders == 1 and applied.presets == 1)

    -- Without the spells: the writing survives, the spell does not.
    local other = { reminders = {} }
    Share.Apply(other, { parts = { reminders = all.reminders } }, {
        nextID = function() return 1 end, keepSpells = false,
    })
    Check("A reminder crossing classes keeps its words",
        other.reminders[1].text == "Bone Shield")
    Check("A reminder crossing classes loses its spell",
        other.reminders[1].spellID == nil)

    ---------------------------------------------------------------------
    -- What the import window says before it writes anything
    ---------------------------------------------------------------------
    local lines = Share.Describe(payload)
    Check("The preview lists one line per part", #lines == 3)
    Check("The preview counts the bars",
        lines[1].label == "Bars" and lines[1].detail == "2 bars")
    Check("The preview counts one reminder in the singular",
        lines[2].detail == "1 reminder")
    Check("The preview counts saved looks, which have no order",
        lines[3].detail == "1 look")
    Check("The preview of nothing is empty", #Share.Describe(nil) == 0)
end

---------------------------------------------------------------------------
-- Modules
--
-- The switches that decide which features run at all. Three kinds of check,
-- and the first two are the ones that would ship a silent hole:
--
--   the REGISTRY agrees with the pages - a module with no page is a feature
--   you can switch off and never find again, and a page naming a module that
--   does not exist greys itself out forever
--
--   the DEFAULTS say on - ApplyDefaults fills these into every existing
--   profile on the first login after an update, and any other value here
--   means the update switched somebody's bars off for them
--
--   WelcomeDue, which is pure and therefore testable without a profile: the
--   rule for when the first-run window opens, including the case that only
--   showed up while writing it - a generation bumped with no new module must
--   not open a window in anybody's face.
---------------------------------------------------------------------------
local function TestModules()
    local Modules = ns.Modules
    Check("There is a module registry", Modules ~= nil)
    if not Modules then return end

    local list = Modules:All()

    -- Not a fixed number. This said "four" and went red the day a fifth was
    -- added, which is a test failing at the exact moment the code was right -
    -- the count is not the rule. The rule is that the registry and the
    -- window's page list agree, and that is checked below in both directions.
    Check("There are modules registered", #list >= 4, tostring(#list))

    local seen = {}
    for _, entry in ipairs(list) do
        Check("Module '" .. tostring(entry.key) .. "' has a key that is a word",
            type(entry.key) == "string" and entry.key ~= "")
        Check("Module '" .. tostring(entry.key) .. "' is named",
            type(entry.title) == "string" and entry.title ~= "")
        -- The welcome window and the greyed page both print this. Empty, they
        -- offer a switch with nothing said about what it does.
        Check("Module '" .. tostring(entry.key) .. "' says what it is for",
            type(entry.blurb) == "string" and #entry.blurb > 20)
        Check("Module '" .. tostring(entry.key) .. "' has a mark that resolves",
            entry.glyph and ns.UI.HasGlyph(entry.glyph), tostring(entry.glyph))
        Check("Module key '" .. tostring(entry.key) .. "' is used once",
            not seen[entry.key])
        seen[entry.key] = true
    end

    -- The registry and the window's page list, in both directions.
    local pageByModule = {}
    for _, page in ipairs(ns.Options.PAGES) do
        if page.module then
            Check("Page '" .. page.key .. "' names a module that exists",
                Modules:Get(page.module) ~= nil, tostring(page.module))
            pageByModule[page.module] = page.key
        end
    end
    for _, entry in ipairs(list) do
        Check("Module '" .. entry.key .. "' has a page to be switched on from",
            pageByModule[entry.key] ~= nil)
    end

    -- Boot order is dependency order, and it is the LIST's order. A reminder
    -- asks the Cooldown Manager whether a buff is up and the bars claim its
    -- frames first, so this pair must not be swapped by a tidy-up.
    local order = {}
    for index, entry in ipairs(list) do order[entry.key] = index end
    Check("The bars boot before the reminders",
        (order.cooldowns or 99) < (order.reminders or 0))

    -- The defaults. Read from ns.DEFAULTS rather than from a live profile:
    -- this is the table an existing character gets filled in from.
    for _, entry in ipairs(list) do
        Check("Module '" .. entry.key .. "' defaults to ON",
            ns.DEFAULTS.modules and ns.DEFAULTS.modules[entry.key] == true)
    end
    Check("The welcome flag is NOT in the defaults",
        ns.DEFAULTS.welcomeSeen == nil,
        "a default would answer the question before it was asked")

    -- An unknown key answers YES. A typo in a gate has to leave the feature
    -- running, not switch it off for everybody.
    Check("An unknown module counts as running", Modules:IsOn("nonesuch"))

    -- The switch itself, on the live profile, put back immediately. The one
    -- test in this file that writes to your settings, and it writes one
    -- boolean it already knows the value of.
    if ns.db then
        ns.db.modules = ns.db.modules or {}
        local was = ns.db.modules.deaths
        local ok, err = pcall(function()
            ns.db.modules.deaths = false
            Check("A module switched off reads as off", not Modules:IsOn("deaths"))
            ns.db.modules.deaths = true
            Check("A module switched on reads as on", Modules:IsOn("deaths"))
            ns.db.modules.deaths = nil
            Check("A module nobody has answered for counts as on",
                Modules:IsOn("deaths"))
        end)
        ns.db.modules.deaths = was
        if not ok then error(err) end
    else
        Skip("The module switch on a live profile", "no profile open")
    end

    ---------------------------------------------------------------------
    -- WelcomeDue
    ---------------------------------------------------------------------
    local FAKE = {
        { key = "old", since = 1 },
        { key = "new", since = 2 },
    }

    local due, fresh, first = Modules.WelcomeDue(nil, 2, FAKE)
    Check("Never asked: the window is due", due)
    Check("Never asked: it is a first run", first)
    Check("Never asked: nothing is singled out as new", #fresh == 0)

    due = Modules.WelcomeDue(2, 2, FAKE)
    Check("Already asked about everything: not due", not due)

    due = Modules.WelcomeDue(3, 2, FAKE)
    Check("Asked about MORE than we ship: not due", not due,
        "a downgrade must not re-ask")

    due, fresh, first = Modules.WelcomeDue(1, 2, FAKE)
    Check("A new module makes it due again", due)
    Check("Only the new module is singled out",
        #fresh == 1 and fresh[1] == "new",
        table.concat(fresh, ","))
    Check("A second visit is not a first run", not first)

    -- The case that is easy to get wrong: the number moved, the list did not.
    due = Modules.WelcomeDue(1, 2, { { key = "old", since = 1 } })
    Check("A generation bump with no new module opens nothing", not due)

    due = Modules.WelcomeDue("yes", 2, FAKE)
    Check("A nonsense flag does not open the window every login", not due)
end

---------------------------------------------------------------------------
-- External cooldowns
--
-- The rule that decides WHO a click whispers, and it is the whole feature: a
-- panel that asks the wrong person is worse than no panel, because you spend
-- the two seconds you had believing help is coming.
--
-- Pure, and it takes the roster as a plain list - which is the only way this
-- can ever be tested. A five-man with two paladins in it, one of them a
-- healer, is not something a self test can arrange in the game.
---------------------------------------------------------------------------
local function TestExternals()
    local X = ns.Externals
    Check("The externals list exists", X ~= nil)
    if not X then return end

    Check("Every external names a spell and a class", (function()
        for _, entry in ipairs(X.SPELLS) do
            if type(entry.spellID) ~= "number" or type(entry.class) ~= "string" then
                return false
            end
        end
        return #X.SPELLS > 0
    end)())

    -- No duplicates: the panel keys its assignment table by spell id, and two
    -- entries with one id would share an assignment silently.
    local seen, twice = {}, nil
    for _, entry in ipairs(X.SPELLS) do
        if seen[entry.spellID] then twice = entry.spellID end
        seen[entry.spellID] = true
    end
    Check("No external is listed twice", twice == nil, tostring(twice))

    local sacrifice = X.Get(6940)
    Check("Blessing of Sacrifice is in the list", sacrifice ~= nil)
    Check("It belongs to the paladin",
        sacrifice and sacrifice.class == "PALADIN")

    ---------------------------------------------------------------------
    -- Who gets asked
    ---------------------------------------------------------------------
    local ROSTER = {
        { name = "Zwoelf",  class = "DEATHKNIGHT", role = "TANK",   isPlayer = true },
        { name = "Heiler",  class = "PALADIN",     role = "HEALER" },
        { name = "Schaden", class = "PALADIN",     role = "DAMAGER" },
        { name = "Baum",    class = "DRUID",       role = "HEALER" },
    }

    local who = X.Whom(sacrifice, ROSTER)
    Check("The healing paladin is asked, not the other one",
        who and who.name == "Heiler", who and who.name or "nobody")

    local named, why = X.Whom(sacrifice, ROSTER, "Schaden")
    Check("A name you assigned wins over the rule",
        named and named.name == "Schaden", named and named.name or "nobody")
    Check("And it says it was an assignment", why == "assigned", tostring(why))

    -- The assigned player left the group. Falling back is right; silently
    -- whispering somebody else without saying so would not be.
    local gone, goneWhy = X.Whom(sacrifice, ROSTER, "Somebody Else")
    Check("An assignment to somebody who left falls back",
        gone and gone.name == "Heiler", gone and gone.name or "nobody")
    Check("And the fallback does not claim to be the assignment",
        goneWhy ~= "assigned", tostring(goneWhy))

    Check("Nobody of that class means nobody is asked",
        X.Whom(X.Get(116849), ROSTER) == nil)   -- Life Cocoon, no monk here

    -- THE PLAYER IS NEVER ASKED. A paladin tank whispering himself for a
    -- Blessing of Sacrifice is the panel answering its own question.
    local SELF_ONLY = {
        { name = "Zwoelf", class = "PALADIN", role = "TANK", isPlayer = true },
    }
    Check("You are never a candidate for your own external",
        X.Whom(sacrifice, SELF_ONLY) == nil)
    Check("And that leaves no candidates at all",
        #X.Candidates(sacrifice, SELF_ONLY) == 0)

    Check("An unknown spell has no candidates",
        #X.Candidates(nil, ROSTER) == 0)

    ---------------------------------------------------------------------
    -- What the whisper says
    ---------------------------------------------------------------------
    local cfg = X.Config()
    local was = cfg.message

    cfg.message = nil
    Check("The default message names the spell",
        X.Message("Ironbark"):find("Ironbark", 1, true) ~= nil,
        X.Message("Ironbark"))

    cfg.message = "%s jetzt bitte"
    Check("A message you wrote is used",
        X.Message("Ironbark") == "Ironbark jetzt bitte", X.Message("Ironbark"))

    -- The case somebody will create by deleting the placeholder: the spell
    -- has to be named anyway, or every slot sends one sentence and nobody
    -- knows which of four buttons is being asked for.
    cfg.message = "HILFE"
    Check("A message with no placeholder still names the spell",
        X.Message("Ironbark"):find("Ironbark", 1, true) ~= nil,
        X.Message("Ironbark"))

    -- %n, the person. Worth having in party chat, where "Ironbark bitte!"
    -- asks nobody in particular.
    cfg.message = "%n, %s bitte"
    Check("The name is written into the message",
        X.Message("Ironbark", "Baum") == "Baum, Ironbark bitte",
        X.Message("Ironbark", "Baum"))

    -- Nobody resolved: the placeholder comes OUT rather than being read as
    -- "%n" by somebody mid-pull, and the space it sat in goes with it.
    Check("With nobody to name, the placeholder is removed",
        X.Message("Ironbark", nil):find("%%n") == nil,
        X.Message("Ironbark", nil))
    Check("And no hole is left where the name was",
        X.Message("Ironbark", nil) == ", Ironbark bitte"
            or X.Message("Ironbark", nil) == "Ironbark bitte"
            or X.Message("Ironbark", nil):find("  ") == nil,
        X.Message("Ironbark", nil))

    -- A percent sign in a spell name would otherwise be read as a capture by
    -- the NEXT gsub. Nothing in this list has one today, which is exactly why
    -- it is worth a test rather than a memory.
    cfg.message = "%s bitte"
    Check("A percent in a name survives",
        X.Message("100%% Mana", nil):find("Mana", 1, true) ~= nil,
        X.Message("100%% Mana", nil))

    cfg.message = was

    ---------------------------------------------------------------------
    -- WHICH CHANNEL IT ACTUALLY GOES ON
    --
    -- The one that would have shipped broken: /p is NOT the party channel in
    -- a dungeon from the group finder. That group talks on INSTANCE_CHAT, and
    -- a message sent to PARTY there arrives NOWHERE - silently, which is the
    -- worst way for a "tell the healer" button to fail.
    ---------------------------------------------------------------------
    local R = X.ResolveChannel
    Check("A whisper is a whisper anywhere", R("WHISPER") == "WHISPER")
    Check("Say needs no group", R("SAY", false) == "SAY")

    Check("A group message alone goes nowhere, and says so",
        R("GROUP", false) == nil)
    Check("In a party it is PARTY",
        R("GROUP", true, false, false) == "PARTY")
    Check("In a raid it is RAID",
        R("GROUP", true, true, false) == "RAID")
    Check("IN A DUNGEON FROM THE FINDER IT IS INSTANCE_CHAT",
        R("GROUP", true, false, true) == "INSTANCE_CHAT",
        tostring(R("GROUP", true, false, true)))
    Check("An instance raid is instance chat too",
        R("GROUP", true, true, true) == "INSTANCE_CHAT")

    -- The raid warning, and its two ways of not being available. Neither
    -- refuses to send: the message still wants to arrive.
    Check("A raid warning as lead is a raid warning",
        R("RAID_WARNING", true, true, false, true) == "RAID_WARNING")
    local fallback, why2 = R("RAID_WARNING", true, true, false, false)
    Check("Without assist it falls back to raid chat", fallback == "RAID")
    Check("And it says why", type(why2) == "string" and #why2 > 0)
    Check("Outside a raid it goes to the group instead",
        R("RAID_WARNING", true, false, false, false) == "PARTY")
    Check("In an instance group, to instance chat",
        R("RAID_WARNING", true, false, true, false) == "INSTANCE_CHAT")

    ---------------------------------------------------------------------
    -- SEVERAL CHANNELS AT ONCE
    --
    -- The de-duplication is the part worth a test: "Raid warning" and "Party
    -- or raid" both come out as RAID for somebody without assist, and sending
    -- one sentence to one channel twice is a person spamming their own group
    -- because of a setting they thought was two different things.
    ---------------------------------------------------------------------
    local function Names(list)
        local out = {}
        for _, entry in ipairs(list) do out[#out + 1] = entry.channel end
        return table.concat(out, ",")
    end

    Check("One channel goes to one place",
        Names(X.SendingTo({ WHISPER = true }, true, false, false, false))
            == "WHISPER")

    Check("A whisper and the group are two messages",
        Names(X.SendingTo({ WHISPER = true, GROUP = true },
            true, false, false, false)) == "WHISPER,PARTY",
        Names(X.SendingTo({ WHISPER = true, GROUP = true },
            true, false, false, false)))

    -- Both resolve to RAID without assist. One message, not two.
    Check("Two choices that come out the same are sent once",
        Names(X.SendingTo({ GROUP = true, RAID_WARNING = true },
            true, true, false, false)) == "RAID",
        Names(X.SendingTo({ GROUP = true, RAID_WARNING = true },
            true, true, false, false)))

    -- With assist they are genuinely two channels, and both are wanted.
    Check("With assist they are two different channels",
        Names(X.SendingTo({ GROUP = true, RAID_WARNING = true },
            true, true, false, true)) == "RAID,RAID_WARNING",
        Names(X.SendingTo({ GROUP = true, RAID_WARNING = true },
            true, true, false, true)))

    Check("Solo, a group-only choice sends nowhere",
        #X.SendingTo({ GROUP = true }, false, false, false, false) == 0)
    Check("But Say still goes out solo",
        Names(X.SendingTo({ GROUP = true, SAY = true },
            false, false, false, false)) == "SAY")

    -- The last one cannot be switched off. A button that sends nowhere is not
    -- a setting, and the click that emptied it is the one nobody notices.
    local keptChannels = X.Config().channels
    X.Config().channels = { WHISPER = true }
    X.ToggleChannel("WHISPER")
    Check("Switching off the last channel leaves one on",
        next(X.Config().channels) ~= nil)
    X.Config().channels = keptChannels

    ---------------------------------------------------------------------
    -- THE LOOK, UNDER THE BAR'S OWN KEY NAMES
    --
    -- The point of the naming is that ns.PaintSurface and ns.PaintBorder can
    -- read this table without knowing what a panel is. If a key is ever
    -- renamed here, the painters keep working on the DEFAULTS and the setting
    -- silently stops doing anything - which is the failure this catches.
    ---------------------------------------------------------------------
    local style = X.Style()
    for _, key in ipairs({ "borderSize", "borderColor", "borderTexture",
        "backdrop", "backdropColor", "backdropAlpha", "backdropTexture",
        "iconZoom" }) do
        Check("The panel's style carries '" .. key .. "'", style[key] ~= nil)
    end
    Check("Its border thickness is a number", type(style.borderSize) == "number")
    Check("Its border colour is three numbers",
        type(style.borderColor) == "table" and #style.borderColor >= 3)
    Check("A negative thickness cannot get through",
        (function()
            local keptSize = X.Config().borderSize
            X.Config().borderSize = -5
            local clamped = X.Style().borderSize
            X.Config().borderSize = keptSize
            return clamped >= 0
        end)())

    -- Every one of these names is one a BAR uses. Spelled the same or the
    -- two renderers are two vocabularies for one idea.
    for _, key in ipairs({ "borderSize", "borderColor", "borderTexture",
        "backdrop", "backdropColor", "backdropAlpha", "backdropTexture",
        "iconZoom", "scale", "alpha" }) do
        local found = false
        for _, barKey in ipairs(ns.BAR_STYLE_KEYS) do
            if barKey == key then found = true break end
        end
        Check("'" .. key .. "' is spelled the way a bar spells it", found)
    end

    ---------------------------------------------------------------------
    -- Slots
    ---------------------------------------------------------------------
    local keptCells = X.Config().cells
    local keptRows, keptColumns = X.Config().rows, X.Config().columns
    X.Config().cells = {}
    X.SetRows(1)
    X.SetColumns(4)

    Check("An empty panel has nothing on it", #X.Picked() == 0)

    local landed = X.Pick(6940)
    Check("A spell lands in the first free slot", landed == 1, tostring(landed))
    Check("And it is on the panel", X.IsPicked(6940))

    landed = X.Pick(102342, 3)
    Check("A marked slot is used when there is one", landed == 3,
        tostring(landed))
    Check("The slot between them is still empty", X.SpellAt(2) == nil)

    -- One spell, one slot. A second copy would whisper twice for one click.
    X.SetSlot(2, 6940)
    Check("Putting a spell somewhere else MOVES it", X.SpellAt(1) == nil)
    Check("And it is in its new place", X.SpellAt(2) == 6940)

    -- What falls off the end stays put. The same rule a shrunk bar follows.
    X.SetColumns(2)
    Check("A slot outside the lattice keeps what is in it",
        X.SpellAt(3) == 102342)
    Check("But it is not on the panel", #X.Picked() == 1)
    X.SetColumns(4)
    Check("Making the lattice bigger gives it back", #X.Picked() == 2)

    X.ClearSlot(2)
    Check("Clearing a slot empties it", X.SpellAt(2) == nil)

    ---------------------------------------------------------------------
    -- ROWS AND COLUMNS, the shape itself
    --
    -- Owner: "anzahl rows fehlt! wie die cdm einstellungen, reihe und spalten
    -- anzahl." So the count is not a setting any more - it is what the two
    -- of them multiply to, and there is no third number that can disagree.
    ---------------------------------------------------------------------
    X.SetRows(3)
    X.SetColumns(4)
    Check("Rows times columns is how many places there are", X.Count() == 12,
        tostring(X.Count()))

    X.SetRows(0)
    Check("Neither ever goes below one", X.Rows() == 1)
    X.SetColumns(999)
    Check("And neither past its ceiling", X.Columns() == X.MAX_COLUMNS)

    -- WHERE EACH SLOT SITS. Pure, and the same answer the panel and the
    -- preview both draw from - a preview that disagrees with the screen is
    -- worse than no preview.
    local function At(index, rows, columns, down)
        local column, row = X.Cell(index, rows, columns, down)
        return column .. "," .. row
    end
    Check("The first slot is the top left corner", At(1, 2, 4) == "0,0")
    Check("Across, the fourth is at the end of the first row",
        At(4, 2, 4) == "3,0", At(4, 2, 4))
    Check("Across, the fifth wraps to the next row", At(5, 2, 4) == "0,1",
        At(5, 2, 4))
    Check("Down, the second is UNDER the first",
        At(2, 2, 4, true) == "0,1", At(2, 2, 4, true))
    Check("Down, the third starts a new column",
        At(3, 2, 4, true) == "1,0", At(3, 2, 4, true))

    -- HOW BIG THE DRAWN PANEL IS. What nobody can cast is not drawn at all,
    -- so three usable spells in a lattice of twelve is three icons wide -
    -- the owner's "verschwindet ganz", measured.
    local function Extent(shown, rows, columns, down)
        local wide, tall = X.Extent(shown, rows, columns, down)
        return wide .. "x" .. tall
    end
    Check("Nothing to show is no size at all", Extent(0, 2, 4) == "0x0")
    Check("Three of twelve are three across and one down",
        Extent(3, 3, 4) == "3x1", Extent(3, 3, 4))
    Check("Five of twelve wrap onto a second row",
        Extent(5, 3, 4) == "4x2", Extent(5, 3, 4))
    Check("Growing downwards, three are one column of three",
        Extent(3, 3, 4, true) == "1x3", Extent(3, 3, 4, true))
    Check("A full lattice is exactly its own shape",
        Extent(12, 3, 4) == "4x3", Extent(12, 3, 4))

    ---------------------------------------------------------------------
    -- THE OLD SHAPE IS READ ONCE AND DROPPED
    --
    -- A profile written before the lattice carries a count and a line width.
    -- This is the migration everybody who updates runs exactly once, and
    -- getting it wrong means somebody's arranged panel comes back as a
    -- default - which is the same thing as losing it.
    ---------------------------------------------------------------------
    local cfg = X.Config()
    local savedRows, savedColumns = cfg.rows, cfg.columns
    cfg.rows, cfg.columns = nil, nil
    cfg.count, cfg.perLine = 12, 4
    X.Config()
    Check("An old count of twelve in lines of four is 3 x 4",
        cfg.rows == 3 and cfg.columns == 4,
        tostring(cfg.rows) .. "x" .. tostring(cfg.columns))
    Check("And the two old keys are gone rather than kept in step",
        cfg.count == nil and cfg.perLine == nil)
    -- THE OLDEST PROFILE OF ALL: an ordered `picked` list AND a count. Both
    -- migrations run in one call, and reading them in the wrong order threw
    -- on login - the lattice one deletes cfg.count, and the list one was
    -- doing arithmetic on it afterwards.
    cfg.rows, cfg.columns = nil, nil
    cfg.count, cfg.perLine = 6, 6
    cfg.cells = {}
    cfg.picked = { 6940, 102342 }
    local ok = pcall(X.Config)
    Check("A profile from before the slots still opens", ok)
    Check("And its spells are in the first two slots",
        cfg.cells[1] == 6940 and cfg.cells[2] == 102342)
    Check("And it has a lattice big enough to hold them",
        (cfg.rows or 0) * (cfg.columns or 0) >= 2)
    cfg.picked = nil

    cfg.rows, cfg.columns = savedRows, savedColumns

    ---------------------------------------------------------------------
    -- WHAT A LOGIN DOES TO A PANEL SOMEBODY HAS ARRANGED
    --
    -- Owner, 2026-08-09: "nach rl ist mein preset von meinen external cds
    -- immer weg." What he was actually looking at was a preview that did not
    -- draw - but "the login path keeps what I arranged" is worth pinning down
    -- rather than believing, because ApplyDefaults runs over every profile
    -- before anything reads it and it is the one thing that could.
    --
    -- Run on a stand-in profile, so this can never touch his own.
    ---------------------------------------------------------------------
    local realDB = ns.db
    local saved = {
        externals = {
            cells = { [1] = 6940, [3] = 102342 },
            assigned = { [6940] = "Heiler" },
            rows = 2, columns = 5,
            -- Whisper switched OFF and Say switched on. Stored by being
            -- MISSING, which is the shape ApplyDefaults would undo.
            channels = { SAY = true },
            message = "%s bitte!",
        },
    }
    ns.ApplyDefaults(saved, ns.DEFAULTS)
    ns.db = saved
    local after = X.Config()
    ns.db = realDB

    Check("A login keeps the spells you put in your slots",
        after.cells[1] == 6940 and after.cells[3] == 102342)
    Check("And the lattice you arranged them in",
        after.rows == 2 and after.columns == 5,
        tostring(after.rows) .. "x" .. tostring(after.columns))
    Check("And who you assigned them to", after.assigned[6940] == "Heiler")
    Check("A CHANNEL YOU SWITCHED OFF STAYS OFF over a login",
        after.channels.WHISPER == nil and after.channels.SAY == true)

    ---------------------------------------------------------------------
    -- THE PREVIEW FITS THE PAGE
    --
    -- The band does not scroll, so the lattice has to be drawn at whatever
    -- size fits both ways. This is the rule that stops twelve columns running
    -- off the edge of the settings page - which is not something the desktop
    -- harness can see, because every frame out here answers 400 wide.
    ---------------------------------------------------------------------
    local P = ns.OptionsExternals and ns.OptionsExternals.PreviewSize
    if P then
        Check("A small lattice is drawn at the design's own size",
            P(1, 6, 730, 200) == 40, tostring(P(1, 6, 730, 200)))
        Check("Twelve columns still fit across the page",
            P(1, 12, 730, 200) * 12 + 11 * 8 <= 730,
            tostring(P(1, 12, 730, 200)))
        Check("Six rows still fit inside the band",
            P(6, 6, 730, 200) * 6 + 5 * 8 <= 200, tostring(P(6, 6, 730, 200)))
        Check("It never shrinks past being clickable", P(6, 12, 200, 60) >= 22,
            tostring(P(6, 12, 200, 60)))
    end

    X.Config().cells = keptCells
    X.SetRows(keptRows)
    X.SetColumns(keptColumns)
end

---------------------------------------------------------------------------
-- THE TAUNT ANNOUNCE (roadmap 6)
--
-- Every rule that decides anything here is pure and takes the world as an
-- argument, because none of these states can be arranged in game: a raid with
-- two other tanks, a party where you have no assist, a second press half a
-- second after the first.
---------------------------------------------------------------------------
local function TestTaunts()
    local T = ns.Taunts
    Check("The taunt list exists", T ~= nil)
    if not T then return end

    Check("Every taunt names a spell and a class", (function()
        for _, entry in ipairs(T.SPELLS) do
            if type(entry.spellID) ~= "number" or type(entry.class) ~= "string" then
                return false
            end
        end
        return #T.SPELLS > 0
    end)())

    -- The six classes that have one. Read out of NorthernSkyRaidTools rather
    -- than remembered - if this ever goes red, check THAT list first.
    Check("A warrior's Taunt is one", T.IsTaunt(355))
    Check("Dark Command is one", T.IsTaunt(56222))
    Check("Hand of Reckoning is one", T.IsTaunt(62124))
    Check("Provoke is one", T.IsTaunt(115546))
    Check("Growl is one", T.IsTaunt(6795))
    Check("Torment is one", T.IsTaunt(185245))
    Check("A Death Strike is not", T.IsTaunt(49998) == false)

    -- DEATH GRIP TAUNTS IN BLOOD AND ONLY IN BLOOD. A frost death knight
    -- pressing it is pulling something, not taking it, and announcing a swap
    -- there tells the other tank something untrue.
    Check("Death Grip counts for Blood", T.IsTaunt(49576, 250))
    Check("But not for Frost", T.IsTaunt(49576, 251) == false)
    Check("With no spec known it still counts", T.IsTaunt(49576, nil))

    ---------------------------------------------------------------------
    -- Who the other tank is
    ---------------------------------------------------------------------
    local ROSTER = {
        { name = "Zwoelf", class = "DEATHKNIGHT", role = "TANK", isPlayer = true },
        { name = "Krieger", class = "WARRIOR",    role = "TANK" },
        { name = "Heiler",  class = "PRIEST",     role = "HEALER" },
        { name = "Zweit",   class = "DRUID",      role = "TANK" },
    }

    local other = T.CoTank(ROSTER)
    Check("The other tank is the one who is not you",
        other and other.name == "Krieger", other and other.name or "nobody")

    local named, why = T.CoTank(ROSTER, "Zweit")
    Check("A tank you named wins over the rule",
        named and named.name == "Zweit", named and named.name or "nobody")
    Check("And it says it was an assignment", why == "assigned", tostring(why))

    local gone = T.CoTank(ROSTER, "Somebody Else")
    Check("Naming somebody who left falls back to the rule",
        gone and gone.name == "Krieger", gone and gone.name or "nobody")

    Check("Tanking alone, there is nobody to tell",
        T.CoTank({ { name = "Zwoelf", role = "TANK", isPlayer = true } }) == nil)
    Check("YOU are never the other tank",
        T.CoTank({ { name = "Zwoelf", role = "TANK", isPlayer = true } },
            "Zwoelf") == nil)

    ---------------------------------------------------------------------
    -- What it says
    ---------------------------------------------------------------------
    Check("The default names what you taunted",
        T.Message(nil, "Dark Command", "Golem"):find("Golem", 1, true) ~= nil,
        T.Message(nil, "Dark Command", "Golem"))
    Check("The taunt itself can be in it too",
        T.Message("%s -> %t", "Dark Command", "Golem")
            == "Dark Command -> Golem",
        T.Message("%s -> %t", "Dark Command", "Golem"))
    Check("And the other tank",
        T.Message("%n, ich hab ihn", nil, nil, "Krieger") == "Krieger, ich hab ihn",
        T.Message("%n, ich hab ihn", nil, nil, "Krieger"))

    -- Nothing to fill it with: the placeholder comes OUT rather than being
    -- read out as "%t" by somebody mid-pull.
    Check("An unfilled placeholder is removed",
        T.Message("Taunt: %t", "Dark Command", nil):find("%%t") == nil,
        T.Message("Taunt: %t", "Dark Command", nil))
    Check("And no hole is left where it was",
        T.Message("Taunt: %t", "Dark Command", nil) == "Taunt:",
        T.Message("Taunt: %t", "Dark Command", nil))

    -- ONE PASS. A mob called "%n the Devourer" must not be read as a
    -- placeholder by a second substitution, because there is no second one.
    Check("A placeholder inside a NAME is left alone",
        T.Message("Taunt: %t", nil, "%n the Devourer", "Krieger")
            == "Taunt: %n the Devourer",
        T.Message("Taunt: %t", nil, "%n the Devourer", "Krieger"))

    ---------------------------------------------------------------------
    -- Whether it speaks at all
    --
    -- OFF UNTIL ASKED FOR is the load-bearing one: an addon that starts
    -- writing in party chat after an update is the worst surprise it could
    -- hand somebody, and this is the check that keeps that promise.
    ---------------------------------------------------------------------
    local S = T.ShouldAnnounce
    Check("Switched off, it says nothing", S({}, true, true) == false)
    Check("Switched on in a group, it speaks",
        S({ announce = true }, true, true) == true)
    Check("Alone, it stays quiet",
        S({ announce = true }, false, false) == false)
    Check("Alone is allowed when you asked for it",
        S({ announce = true, onlyInGroup = false }, false, false) == true)
    Check("Set to instances only, the open world is quiet",
        S({ announce = true, onlyInInstance = true }, true, false) == false)
    Check("And a dungeon is not",
        S({ announce = true, onlyInInstance = true }, true, true) == true)

    -- TWO PRESSES IN A SECOND ARE ONE ANNOUNCE. A taunt that misses is
    -- pressed again straight away, and a tank who spams his own group over it
    -- switches the feature off and never comes back.
    Check("The first press always speaks", T.MaySpeak(100, nil))
    Check("A second one straight after does not",
        T.MaySpeak(100.5, 100) == false)
    Check("Two seconds later it does again", T.MaySpeak(102.5, 100))

    ---------------------------------------------------------------------
    -- The channels are the SAME rules the externals panel uses
    --
    -- Not a copy of them. This is the check that catches somebody growing a
    -- second answer to "which channel am I in" - the one thing the handoff
    -- said not to do before this feature was written.
    ---------------------------------------------------------------------
    ---------------------------------------------------------------------
    -- THE THREE WAYS TO ASK
    --
    -- A button, a keybinding and a macro, and all three have to run the same
    -- line - three ways in is a feature, three implementations is a bug
    -- waiting for one of them to drift.
    ---------------------------------------------------------------------
    Check("The keybinding has something to call",
        type(_G.ZwoelfStuff_TauntAsk) == "function")
    Check("And the game has a name to show for it",
        type(_G.BINDING_NAME_ZWOELFSTUFF_TAUNT_ASK) == "string"
        and type(_G.BINDING_HEADER_ZWOELFSTUFF) == "string")

    -- SIXTEEN CHARACTERS is the limit on a macro name. Over it, the macro is
    -- created under a truncated name, GetMacroIndexByName never finds it
    -- again, and every press of "Make the macro" makes another one.
    Check("The macro name fits in a macro name", #T.MACRO_NAME <= 16,
        T.MACRO_NAME)
    Check("And its body is the command that exists",
        T.MACRO_BODY == "/zs taunt ask", T.MACRO_BODY)

    -- The button is painted by the BAR's painters, under the bar's key names,
    -- exactly as the externals panel is. Renaming one here would leave the
    -- painters quietly using their defaults while the setting looks live.
    local style = T.Style()
    for _, key in ipairs({ "borderSize", "borderColor", "borderTexture",
        "backdrop", "backdropColor", "backdropAlpha", "backdropTexture",
        "iconZoom" }) do
        local found = false
        for _, barKey in ipairs(ns.BAR_STYLE_KEYS) do
            if barKey == key then found = true break end
        end
        Check("The taunt button's '" .. key .. "' is a bar's word", found)
        Check("And it has a value", style[key] ~= nil)
    end

    -- THE ICON PICKER'S PAGING. Pure, and it is the pair of off-by-ones that
    -- only shows up on the last page of four thousand icons.
    Check("The first page starts at one",
        select(1, ns.UI.IconPage(400, 1, 80)) == 1)
    Check("The last page stops at the end",
        select(2, ns.UI.IconPage(400, 5, 80)) == 400)
    Check("A page past the end is clamped to the last one",
        select(3, ns.UI.IconPage(400, 99, 80)) == 5)
    Check("A page before the first is clamped too",
        select(3, ns.UI.IconPage(400, 0, 80)) == 1)
    Check("A short last page does not run past the list",
        select(2, ns.UI.IconPage(85, 2, 80)) == 85,
        tostring(select(2, ns.UI.IconPage(85, 2, 80))))
    Check("An empty list is still one page",
        select(4, ns.UI.IconPage(0, 1, 80)) == 1)

    Check("There is one set of channel rules", ns.Chat ~= nil)
    if ns.Chat then
        Check("And the externals panel uses it",
            ns.Externals.ResolveChannel == ns.Chat.ResolveChannel)
        Check("And so does everything that sends",
            ns.Externals.SendingTo == ns.Chat.SendingTo)
    end
end

---------------------------------------------------------------------------
-- THE ADDON CHANNEL, and the bar at the other end of it
--
-- Every rule here is about data from ANOTHER MACHINE, which is the one kind
-- this addon can never inspect while it is happening. So the wire is pure
-- both ways and the answering rules take the world as arguments: a group with
-- two tanks, a message from a version that does not exist yet, a request for
-- a spell your class does not have.
---------------------------------------------------------------------------
local function TestComm()
    local C = ns.Comm
    Check("The addon channel exists", C ~= nil)
    if not C then return end

    -- SIXTEEN CHARACTERS is the limit on a prefix. Over it,
    -- RegisterAddonMessagePrefix refuses and NOTHING is ever received, while
    -- everything on the sending side looks perfectly healthy.
    Check("The prefix fits in a prefix", #C.PREFIX <= 16, C.PREFIX)

    ---------------------------------------------------------------------
    -- The wire
    ---------------------------------------------------------------------
    local wire = C.Encode(C.REQUEST, C.EXTERNAL, 6940)
    local back = C.Decode(wire)
    Check("A request survives the wire",
        back and back.what == C.REQUEST and back.kind == C.EXTERNAL
        and back.spellID == 6940, wire)

    local used = C.Decode(C.Encode(C.USED, C.EXTERNAL, 633, 480))
    Check("A cooldown carries its own length", used and used.value == 480,
        used and tostring(used.value))

    local taunt = C.Decode(C.Encode(C.REQUEST, C.TAUNT))
    Check("A taunt request names no spell",
        taunt and taunt.kind == C.TAUNT and taunt.spellID == nil)

    -- EVERYTHING THAT IS NOT UNDERSTOOD IS DROPPED. This is data somebody
    -- else's machine sent; the only safe thing to do with a shape this
    -- version does not know is nothing.
    Check("A message from a newer version is dropped",
        C.Decode("9|REQ|EXT|6940|0") == nil)
    Check("A message from another addon is dropped",
        C.Decode("hello everybody") == nil)
    Check("An unknown verb is dropped", C.Decode("1|WAT|EXT|6940|0") == nil)
    Check("An unknown kind is dropped", C.Decode("1|REQ|XXX|6940|0") == nil)
    Check("An external with no spell is dropped",
        C.Decode("1|REQ|EXT|0|0") == nil)
    Check("Nothing at all is dropped", C.Decode(nil) == nil)

    -- A version behind sends four fields. Dropping those would make an addon
    -- that only works when both sides updated on the same evening.
    Check("A message without the number still arrives",
        (C.Decode("1|REQ|EXT|6940") or {}).spellID == 6940)

    ---------------------------------------------------------------------
    -- Which channel it goes on
    ---------------------------------------------------------------------
    Check("Alone, an addon message goes nowhere", C.Channel(false) == nil)
    Check("In a party it is PARTY", C.Channel(true, false, false) == "PARTY")
    Check("In a raid it is RAID", C.Channel(true, true, false) == "RAID")
    Check("IN A DUNGEON FROM THE FINDER IT IS INSTANCE_CHAT",
        C.Channel(true, false, true) == "INSTANCE_CHAT")

    Check("The first message goes out", C.MaySend("x", 100, nil))
    Check("The same one again straight after does not",
        C.MaySend("x", 100.2, 100) == false)
end

local function TestAnswers()
    local A, C = ns.Answers, ns.Comm
    Check("The answering side exists", A ~= nil)
    if not A then return end

    ---------------------------------------------------------------------
    -- What a class can be asked for
    ---------------------------------------------------------------------
    local paladin = A.Offers("PALADIN")
    Check("A paladin can be asked for several things", #paladin >= 5,
        tostring(#paladin))

    local hasTaunt = false
    for _, offer in ipairs(paladin) do
        if offer.kind == C.TAUNT then hasTaunt = true end
    end
    Check("And one of them is his taunt", hasTaunt)

    Check("A rogue can be asked for nothing", #A.Offers("ROGUE") == 0)
    Check("With no class there is nothing to offer", #A.Offers(nil) == 0)

    -- DEATH GRIP IS NOT OFFERED. It taunts in Blood only, and a cell that
    -- taunts nothing is worse than no cell: it is a promise to a tank.
    for _, offer in ipairs(A.Offers("DEATHKNIGHT")) do
        Check("Death Grip is not on the answer bar", offer.spellID ~= 49576)
    end

    -- A spell switched off is not built, so nobody can ask for it.
    local fewer = A.Offers("PALADIN", { [6940] = false })
    Check("Switching one off takes it off the bar", #fewer == #paladin - 1)

    ---------------------------------------------------------------------
    -- Who might ask
    ---------------------------------------------------------------------
    local ROSTER = {
        { name = "Heiler",  class = "PALADIN", role = "HEALER", isPlayer = true },
        { name = "Zwoelf",  class = "DEATHKNIGHT", role = "TANK" },
        { name = "Zweit",   class = "WARRIOR", role = "TANK" },
        { name = "Schaden", class = "MAGE",    role = "DAMAGER" },
    }
    local askers = A.Askers(ROSTER)
    Check("Both tanks could ask", #askers == 2, tostring(#askers))
    Check("You are never one of them", (function()
        for _, member in ipairs(askers) do
            if member.isPlayer then return false end
        end
        return true
    end)())
    Check("Nobody tanking means no cells at all", #A.Askers({}) == 0)

    ---------------------------------------------------------------------
    -- Which cell answers which request
    --
    -- The rule the whole feature turns on: the right one lights up and the
    -- others do not.
    ---------------------------------------------------------------------
    local cell = { who = "Zwoelf", kind = C.EXTERNAL, spellID = 6940 }
    Check("The cell for that spell on that tank matches",
        A.Matches(cell, { from = "Zwoelf", kind = C.EXTERNAL, spellID = 6940 }))
    Check("The same spell for the OTHER tank does not",
        A.Matches(cell, { from = "Zweit", kind = C.EXTERNAL, spellID = 6940 })
            == false)
    Check("A different spell for the same tank does not",
        A.Matches(cell, { from = "Zwoelf", kind = C.EXTERNAL, spellID = 1022 })
            == false)

    -- A taunt request names no spell: any taunt of yours answers it.
    local tauntCell = { who = "Zwoelf", kind = C.TAUNT, spellID = 355 }
    Check("Any taunt answers a taunt request",
        A.Matches(tauntCell, { from = "Zwoelf", kind = C.TAUNT }))

    ---------------------------------------------------------------------
    -- What is waiting, and for how long
    ---------------------------------------------------------------------
    local list = {}
    A.Remember(list, { fromShort = "Zwoelf", kind = C.EXTERNAL, spellID = 6940 }, 100)
    Check("A request is remembered", #list == 1)

    A.Remember(list, { fromShort = "Zwoelf", kind = C.EXTERNAL, spellID = 6940 }, 101)
    Check("Asking twice is ONE row, not two", #list == 1)
    Check("And the clock restarts", list[1].at == 101, tostring(list[1].at))

    A.Remember(list, { fromShort = "Zweit", kind = C.EXTERNAL, spellID = 6940 }, 101)
    Check("Two people asking is two rows", #list == 2)

    Check("A cell knows the one that is its own",
        A.Waiting(list, cell, 102, 8) ~= nil)
    Check("And ignores one that is not",
        A.Waiting(list, { who = "Nobody", kind = C.EXTERNAL, spellID = 6940 },
            102, 8) == nil)

    A.Prune(list, 130, 8)
    Check("An old request stops shouting", #list == 0)
end

---------------------------------------------------------------------------
-- THE PANEL MOVERS
--
-- Owner, 2026-08-09, with a screenshot of the externals mover: "hier fehlt
-- noch das zahnrad fuer einstellungen und das lock item!" A bar's mover had
-- both and a panel's had neither, which is the sort of gap nobody notices
-- while writing the second one.
--
-- Skipped rather than failed when edit mode has never been opened: the movers
-- are made on the first refresh, and "not built yet" is not "built wrong".
---------------------------------------------------------------------------
local function TestPanelMovers()
    if not ns.EditMode.PanelMovers then
        Check("Edit mode can name its panel movers", false)
        return
    end

    local movers = ns.EditMode:PanelMovers()
    local any = false

    -- FOUR PANELS ARE PLACED IN EDIT MODE, and every one of them has to be in
    -- the list that OnUpdate drags. The taunt button shipped in 4.64.0 with a
    -- mover, a cog and a padlock and no way to move it, because the drag was
    -- a hand-written pair of lines beside a hand-written list. They are one
    -- list now, and this is the check that says so out loud.
    local named = 0
    for _ in pairs(movers) do named = named + 1 end
    Check("Every placed panel is in the mover list", named >= 4,
        tostring(named))

    for name, mover in pairs(movers) do
        any = true
        Check("The " .. name .. " mover has a cog", mover.cog ~= nil)
        Check("The " .. name .. " mover has a padlock", mover.lock ~= nil)
        Check("And it knows how to draw the padlock",
            type(mover.RefreshLock) == "function")
        Check("And it carries what its cog needs",
            mover.spec ~= nil and mover.spec.page ~= nil
            and mover.spec.module ~= nil and type(mover.spec.apply) == "function")

        -- THE TWO KEYS HAVE TO NAME REAL THINGS. Both are strings handed to
        -- something that looks them up and quietly does nothing when it does
        -- not find them: Options:Open walks its page list and falls off the
        -- end, Modules:Set returns. A cog entry that silently does nothing is
        -- indistinguishable from a cog entry that is broken.
        if mover.spec then
            local page = false
            for _, entry in ipairs(ns.Options.PAGES or {}) do
                if entry.key == mover.spec.page then page = true break end
            end
            Check("Its cog opens a page that exists", page,
                tostring(mover.spec.page))
            Check("And names a module that exists",
                ns.Modules:Get(mover.spec.module) ~= nil,
                tostring(mover.spec.module))
        end

        -- PINNED MEANS IT DOES NOT MOVE, and that is the whole feature. Run
        -- through the real handler rather than restating the rule: a test that
        -- re-implements what it is checking passes the day the rule changes.
        local cfg = mover.spec.config()
        if cfg then
            local was = cfg.pinned
            local start = mover:GetScript("OnDragStart")

            cfg.pinned = true
            mover.grab = nil
            if start then start(mover) end
            Check("A pinned " .. name .. " panel refuses to be dragged",
                mover.grab == nil)

            cfg.pinned = false
            mover.grab = nil
            if start then start(mover) end
            Check("An unpinned one takes the drag", mover.grab ~= nil)

            -- Never left holding one. Edit mode's OnUpdate reads this every
            -- frame, and a grab nobody asked for would move his panel.
            mover.grab = nil
            cfg.pinned = was
            mover:RefreshLock()
        end
    end

    if not any then
        Skip("Whether the panel movers carry a cog and a padlock",
            "edit mode has not been opened this session")
    end
end

function Test:Run()
    passed, failed, notes = 0, {}, {}

    local suites = {
        { "Modules",       TestModules },
        { "Externals",     TestExternals },
        { "Arrangements",  TestLayout },
        { "Coordinates",   TestOffsets },
        { "Pattern switch", TestPatternRoundTrip },
        { "Rows and columns", TestGridSliders },
        { "Sorting by drag", TestReorder },
        { "One cell's look", TestCellLook },
        { "Per character", TestPerSpec },
        { "Bar fill",      TestFill },
        { "Stack colours", TestStackThresholds },
        { "Active states", TestActiveStates },
        { "Spell identity", TestSpellIdentity },
        { "Design system",  TestDesignSystem },
        { "Snapping",      TestSnapping },
        { "Menu filter",   TestMenuFilter },
        { "Fill direction", TestFillDirection },
        { "Preview bar",   TestPreviewBar },
        { "Gradients",     TestGradients },
        { "Cell gaps",     TestGaps },
        { "Co-tanks",      TestCoTanks },
        { "Co-tank strips", TestCoTankStrips },
        { "Reminders",     TestReminders },
        { "Text elements", TestTextElements },
        { "Game menu",     TestGameMenu },
        { "Anchors",       TestAnchors },
        { "Visibility",    TestVisibility },
        { "Effects",       TestEffects },
        { "Media",         TestMedia },
        { "Profile migration", TestProfileMigration },
        { "Sharing",       TestShare },
        { "Cast history",  TestHistory },
        { "Death analysis", TestDeath },
        { "Your bars",     TestLiveBars },
        { "Panel movers",  TestPanelMovers },
        { "Taunts",        TestTaunts },
        { "Addon channel", TestComm },
        { "Answering",     TestAnswers },
    }

    for _, suite in ipairs(suites) do
        -- One suite that throws must not take the other seven with it. The
        -- throw is itself a failure and is reported as one.
        local ok, err = pcall(suite[2])
        if not ok then
            failed[#failed + 1] = suite[1] .. " threw  |cff888888"
                .. tostring(err) .. "|r"
        end
    end

    ns.Print(string.format("|cffffd100self test|r  %d passed, %s",
        passed, #failed == 0 and "|cff40ff40nothing failed|r"
            or ("|cffff4040" .. #failed .. " FAILED|r")))

    for _, line in ipairs(failed) do
        ns.Print("  |cffff4040x|r " .. line)
    end

    for _, line in ipairs(notes) do
        ns.Print("  |cff888888- not checked:|r " .. line)
    end

    if #failed == 0 then
        ns.Print("|cff888888Green here means the model and the rules behave. "
            .. "It says nothing about how it LOOKS - that is still a pair of "
            .. "eyes on a screen.|r")
    end

    return #failed
end
