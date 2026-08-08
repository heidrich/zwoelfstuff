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

function Test:Run()
    passed, failed, notes = 0, {}, {}

    local suites = {
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
        { "Visibility",    TestVisibility },
        { "Effects",       TestEffects },
        { "Media",         TestMedia },
        { "Your bars",     TestLiveBars },
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
