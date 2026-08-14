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
-- A nudge every cell shares
--
-- HIS BUG, WITH HIS OWN NUMBERS. Reported as "error when I want to set more
-- rows", photographed as one bar drawn in two blocks: the icons where he had
-- dragged them and the empty cells a long way below, on a lattice nobody
-- could see. Read off his saved variables afterwards - five cells in a 1x5
-- bar, every one of them carrying y = 156.
--
-- The first check is the fault itself and the second is the licence to fix
-- it: taking a shared displacement off every cell must move NOTHING.
---------------------------------------------------------------------------
local function Drawn(cfg)
    local slots, box = ns.Layout.Build(cfg, ns.Bars:CellCount(cfg),
        cfg.spacing or 4, cfg.lineSpacing or 4)
    local out = {}
    for index, slot in ipairs(slots) do
        out[index] = { x = slot.x - box.centreX, y = slot.y - box.centreY,
            w = slot.w, h = slot.h }
    end
    return out, box
end

local function TestSharedNudge()
    -- His bar: 36px icons, 2 across, five of them, all dragged 156 up.
    local function His(rows, columns, nudge)
        local cfg = Fresh({ layout = "grid", rows = rows, columns = columns,
            iconSize = 36, spacing = 2, lineSpacing = 4 })
        if nudge then
            for cell = 1, 5 do ns.Layout.SetOffset(cfg, cell, 0, 156) end
        end
        return cfg
    end

    -- THE FAULT. A bar whose cells all carry the same nudge must measure the
    -- same as one whose cells carry none - it is the same picture, drawn in
    -- the same place, and only the lattice underneath it has moved. Before
    -- the fix this came out 272 tall against 124.
    local scattered = His(1, 5, true)
    ns.Bars:ReshapeGrid(scattered, 3, 5)
    local _, scatteredBox = Drawn(scattered)
    local _, neatBox = Drawn(His(3, 5, false))
    Check("Adding a row to a dragged bar does not split it in two",
        Near(scatteredBox.height, neatBox.height)
        and Near(scatteredBox.width, neatBox.width),
        string.format("%.0fx%.0f, expected %.0fx%.0f", scatteredBox.width,
            scatteredBox.height, neatBox.width, neatBox.height))

    -- THE LICENCE. Nothing on screen may move, or this is not a tidy-up, it
    -- is the editor rearranging a bar behind his back.
    local still = His(1, 5, true)
    local before = Drawn(still)
    local dx, dy = ns.Layout.Normalise(still, 5)
    local ok, why = SameGeometry(before, Drawn(still))
    Check("Taking the shared nudge off moves nothing on screen", ok, why)
    Check("...and it is the nudge they shared that came off",
        Near(dx, 0) and Near(dy, 156), string.format("%.0f,%.0f", dx, dy))

    -- A bar nobody has dragged is not written to at all. Otherwise every
    -- reshape would stamp a cellOpts table onto a bar that had none.
    local neat = His(2, 3, false)
    local zeroX, zeroY = ns.Layout.Normalise(neat, 6)
    Check("A bar nobody dragged is left alone",
        Near(zeroX, 0) and Near(zeroY, 0) and not next(neat.cellOpts))

    -- THE MEDIAN, NOT THE MEAN. Four cells sitting still and one dragged
    -- out: the mean would invent a displacement none of them has and nudge
    -- all four. The four must stay exactly where they are.
    local one = Fresh({ layout = "grid", rows = 1, columns = 5 })
    ns.Layout.SetOffset(one, 3, 90, -70)
    local wasOne = Drawn(one)
    ns.Layout.Normalise(one, 5)
    local sameOne, whyOne = SameGeometry(wasOne, Drawn(one))
    Check("One cell dragged out: the other four are not touched",
        sameOne and not ns.Layout.CellOpts(one, 1), whyOne)
    local keptX, keptY = ns.Layout.GetOffset(one, 3)
    Check("...and the one that was dragged keeps its nudge",
        Near(keptX, 90) and Near(keptY, -70),
        string.format("%.0f,%.0f", keptX, keptY))

    -- A puzzle has no lattice to be measured against, so it is not touched.
    local puzzle = Fresh({ layout = "free", freeCount = 3 })
    ns.Layout.SetOffset(puzzle, 1, 300, 300)
    ns.Layout.SetOffset(puzzle, 2, 300, 300)
    ns.Layout.SetOffset(puzzle, 3, 300, 300)
    local puzzleX, puzzleY = ns.Layout.Normalise(puzzle, 3)
    local stillThere = ns.Layout.GetOffset(puzzle, 1)
    Check("A puzzle is left where it was built",
        Near(puzzleX, 0) and Near(puzzleY, 0) and Near(stillThere, 300))
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
-- The slider's arithmetic
--
-- Extracted from the control on purpose. The harness CANNOT see a geometry
-- bug - its frame stub answers GetWidth with a fixed number whatever was set,
-- so a track built at the wrong width tests exactly like a right one. What it
-- CAN see is the arithmetic, so the arithmetic stands on its own and is
-- checked here.
---------------------------------------------------------------------------
local function TestSliderMaths()
    local Snap, Frac, At = ns.UI.SliderSnap, ns.UI.SliderFraction, ns.UI.SliderValueAt

    -- The ends hold, from both directions and from nonsense.
    Check("Below the range comes back as the minimum", Snap(0, 100, 1, -40) == 0)
    Check("Above the range comes back as the maximum", Snap(0, 100, 1, 900) == 100)
    Check("A non-number is the minimum, not an error", Snap(16, 100, 2, nil) == 16)

    -- ROUNDING TO THE NEAREST STEP CAN LAND PAST THE END. 0..1 by .4 rounds a
    -- typed 1 up to 1.2, and the old code clamped only BEFORE snapping - so it
    -- handed back a value its own track had no room to draw. This is the check
    -- that goes red if the second clamp is ever taken out again.
    Check("A step that does not divide the range still ends at the maximum",
        Snap(0, 1, 0.4, 1) <= 1, tostring(Snap(0, 1, 0.4, 1)))

    -- Snapping accumulates float noise, and the box shows this number.
    Check("Twenty steps of .05 from 0 is exactly 1", Snap(0, 1, 0.05, 1) == 1)
    Check("A value between steps takes the nearer one", Snap(0, 100, 10, 24) == 20)
    Check("Exactly halfway rounds up", Snap(0, 100, 10, 25) == 30)

    -- Value and fraction have to be each other's inverse, or the knob sits
    -- somewhere the number does not.
    Check("The minimum is the left end", Near(Frac(0.4, 2.5, 0.4), 0))
    Check("The maximum is the right end", Near(Frac(0.4, 2.5, 2.5), 1))
    Check("Halfway is halfway", Near(Frac(0, 100, 50), 0.5))
    Check("A fraction outside 0..1 is pulled in", Frac(0, 100, -20) == 0
        and Frac(0, 100, 300) == 1)

    -- A range with no span must not divide by zero - it happens whenever a
    -- setting is temporarily pinned to one value.
    Check("A range of nothing answers 0 rather than throwing", Frac(5, 5, 5) == 0)

    local roundTrip = true
    for _, value in ipairs({ 16, 30, 44, 68, 100 }) do
        if At(16, 100, 2, Frac(16, 100, value)) ~= value then roundTrip = false end
    end
    Check("A value survives the trip through its own fraction", roundTrip)

    Check("Dragging past either end stays inside", At(0, 1, 0.05, -3) == 0
        and At(0, 1, 0.05, 4) == 1)

    ---------------------------------------------------------------------
    -- The rail still holds every entry
    --
    -- This is the sum that stops a page being added and the LAST rail entry
    -- quietly disappearing behind the foot. It is not hypothetical: it
    -- happened while that column was being drawn, and a rail that clips looks
    -- exactly like a rail that is simply full.
    --
    -- It replaces the old RailArtHeight check. That one asked how much room
    -- was LEFT OVER for the lit cap; the cap is gone (owner: "lass den
    -- verlauf weg") and the question that was actually worth asking is this
    -- one.
    ---------------------------------------------------------------------
    local Fits = ns.UI.RailFits

    -- The real window: rail 758, head 62, foot 38, and the block of outward
    -- links between the nav and that foot.
    --
    -- TAIL IS ASKED FOR, NOT TYPED. It was a copy - one nav row plus air -
    -- and it stayed that number while the window grew to three shorter rows,
    -- so this check was quietly agreeing with a layout that no longer
    -- existed. ns.Options.RailTail is what the window itself lays out to.
    local TAIL = ns.Options.RailTail()
    local navNow = ns.UI.NAV_ITEM_H * (#ns.Options.PAGES + 1) + 4 * 38

    -- THE RAIL IS THE WINDOW LESS ITS OWN EDGE, and it is asked for rather
    -- than typed. It was 758 in four places here while UI.WINDOW_H said 760,
    -- and the raid bar wave then made the window taller - at which point four
    -- correct numbers would all have been wrong at once, and this check would
    -- have gone on agreeing with a window that no longer existed. That is the
    -- exact fault the TAIL line above was written to fix.
    local RAIL = ns.UI.WINDOW_H - 2

    Check("Today's rail holds every entry", Fits(RAIL, 62, 38, TAIL, navNow),
        string.format("nav %d of %d", navNow, RAIL - 62 - 38 - TAIL))

    -- The sum rather than a number: the first draft of the check this replaces
    -- guessed 700 and went red against correct code.
    local room = RAIL - 62 - 38 - TAIL
    Check("A nav that fills the column exactly still fits",
        Fits(RAIL, 62, 38, TAIL, room))
    Check("One row more than fits is reported as not fitting",
        not Fits(RAIL, 62, 38, TAIL, room + 1))

    -- The margin is worth naming, because it is what a new page spends. Two
    -- more pages must still fit, or the next feature lands on a broken rail
    -- and nobody finds out until a screenshot arrives.
    --
    -- IT HAS ALREADY EARNED ITS KEEP ONCE: the raid bar and the invite tool
    -- took the spare down to 8 pixels, which is what made the window taller.
    Check("There is room for two more pages",
        Fits(RAIL, 62, 38, TAIL, navNow + 2 * ns.UI.NAV_ITEM_H),
        string.format("%d spare", room - navNow))
end

---------------------------------------------------------------------------
-- Which noise, for which spell
--
-- HIS RULE: "bei den requests auch je nach spell nicht slot und beim cmd
-- auch." A key belongs to the place, a sound belongs to the spell.
--
-- Four links in the chain and one check per link, in order, each naming the
-- LINK rather than the value - the shape Locale.Resolve's suite uses. The
-- default arm is checked twice on purpose: an unknown value and no value at
-- all are different code paths, and a resolver that copied the default at
-- write time passes the first and fails the second.
---------------------------------------------------------------------------
local function TestSounds()
    local S = ns.Sounds
    if not Check("There is a sound model", S ~= nil) then return end

    ---------------------------------------------------------------------
    -- The chain, driven on a book this test made itself
    ---------------------------------------------------------------------
    local book = {
        request  = { any = "Whistle", spells = { [33206] = "Bell" } },
        ready    = { any = nil,       spells = {} },
        asked    = { any = "None",    spells = { [6940] = "" } },
        reminder = { spells = {} },
    }

    Check("A spell's own sound wins",
        S.Choice(book, "request", 33206) == "Bell",
        tostring(S.Choice(book, "request", 33206)))
    Check("A spell with none of its own follows the event",
        S.Choice(book, "request", 47788) == "Whistle",
        tostring(S.Choice(book, "request", 47788)))
    Check("No spell at all follows the event",
        S.Choice(book, "request", nil) == "Whistle")
    Check("An event with nothing set answers nothing",
        S.Choice(book, "ready", 12345) == nil,
        tostring(S.Choice(book, "ready", 12345)))
    Check("An event nobody has ever touched answers nothing",
        S.Choice(book, "reminder", 12345) == nil)
    Check("An event this addon does not have answers nothing",
        S.Choice(book, "nonsense", 12345) == nil)

    -- THE EMPTY STRING IS WHAT A PICKER WRITES FOR "no answer of my own", so
    -- it has to fall THROUGH. "None" must not: it is the answer "silence",
    -- and the two being confused is how a chime becomes unsilenceable.
    Check("An empty choice falls through to the event",
        S.Choice(book, "asked", 6940) == "None",
        tostring(S.Choice(book, "asked", 6940)))
    Check("'None' is an answer, not the absence of one",
        S.Choice(book, "asked", nil) == "None")

    ---------------------------------------------------------------------
    -- What ships. Three of four silent, and the fourth is the chime that
    -- was already playing - an update that starts making a noise nobody
    -- asked for is an update people switch off.
    ---------------------------------------------------------------------
    Check("Four moments can make a noise", #S.EVENTS == 4,
        tostring(#S.EVENTS))
    for _, event in ipairs(S.EVENTS) do
        Check("'" .. tostring(event.key) .. "' is a known event",
            S.IsEvent(event.key))
        Check("'" .. tostring(event.key) .. "' has something to call it",
            type(event.text) == "string" and event.text ~= "")
    end
    Check("The answer chime is still the answer chime",
        S.BuiltIn("asked") == 8959, tostring(S.BuiltIn("asked")))
    for _, key in ipairs({ "request", "ready", "reminder" }) do
        Check("Nothing new makes a noise on its own: " .. key,
            S.BuiltIn(key) == nil, tostring(S.BuiltIn(key)))
    end

    ---------------------------------------------------------------------
    -- THE PICKER HAS SOMETHING TO OFFER.
    --
    -- A MediaPicker builds its menu when it is CLICKED, so the check that
    -- every menu on every page can be drawn cannot see this one - it would
    -- open blank on the page and nowhere else. That is the failure the
    -- widget's own header calls the worst kind: a control that is silently
    -- unusable. Media.List falls back to { Media.DEFAULT[kind] }, so this
    -- is really asking whether that entry exists at all.
    ---------------------------------------------------------------------
    local list = ns.Media.List("sound")
    Check("The sound picker has something in it", #list > 0,
        string.format("%d entries", #list))
    Check("...and silence is one of the answers",
        ns.Media.DEFAULT.sound == "None", tostring(ns.Media.DEFAULT.sound))

    -- The same hole existed for backgrounds and nobody had opened that
    -- picker yet. Every kind a picker can be pointed at, in one loop.
    for _, kind in ipairs({ "font", "statusbar", "border", "background",
        "sound" }) do
        Check("The " .. kind .. " picker has a floor to fall back to",
            ns.Media.DEFAULT[kind] ~= nil)
    end

    ---------------------------------------------------------------------
    -- SWITCHING A WHOLE PACK OUT OF THE LIST
    --
    -- Owner: "die exwind sounds muessen alle raus oder geblockt werden, das
    -- sind 1000." Two packs on his machine register 188 entries each. Driven
    -- against whatever is really registered here rather than against a made
    -- up one, because registering a fake pack would leave it in the shared
    -- registry for every other addon for the rest of the session.
    ---------------------------------------------------------------------
    local counts, order = ns.Media.Providers("sound")
    local before = #ns.Media.List("sound")

    if #order > 0 then
        local biggest = order[1]
        ns.Sounds.SetMuted(biggest, true)
        local after = #ns.Media.List("sound")
        Check("Switching a pack off takes it out of the picker",
            after == before - counts[biggest],
            string.format("%d - %d gave %d", before, counts[biggest], after))
        Check("...and the pack knows it is off", ns.Sounds.IsMuted(biggest))

        -- EVERY PACK OFF STILL LEAVES SOMETHING TO CLICK. A dropdown with no
        -- rows is the one state a control must never be in, and it would
        -- take away the "None" that means silence.
        for _, who in ipairs(order) do ns.Sounds.SetMuted(who, true) end
        local bare = ns.Media.List("sound")
        Check("With every pack off the picker is still not empty",
            #bare > 0, tostring(#bare))

        for _, who in ipairs(order) do ns.Sounds.SetMuted(who, false) end
        Check("Switching them back on restores the list",
            #ns.Media.List("sound") == before,
            string.format("%d, expected %d", #ns.Media.List("sound"), before))
    else
        Skip("Switching a sound pack out of the picker",
            "no addon here has registered any sounds")
    end

    -- A CHOICE OUTLIVES ITS PACK BEING HIDDEN. The filter decides what is
    -- OFFERED; it must not reach into what was already chosen, or switching
    -- a pack off would silently change what four moments sound like.
    Check("A sound already chosen is not un-chosen by hiding its pack",
        ns.Sounds.Choice({ ready = { any = "[Pack]One", spells = {} } },
            "ready") == "[Pack]One")

    -- "None" is a name, and the sink has to refuse it rather than hand a
    -- number to the client and call it a path.
    Check("Silence is never played", ns.Media.PlaySound("None") == false)
    Check("Nothing at all is never played", ns.Media.PlaySound(nil) == false)
    Check("An empty choice is never played", ns.Media.PlaySound("") == false)

    ---------------------------------------------------------------------
    -- The throttle. Pure, with its own clock, because the alternative is
    -- a test that waits - and because a whole bar can come back at once.
    ---------------------------------------------------------------------
    Check("The first one always plays", S.MayPlay(100, nil))
    Check("A second one in the same tick does not",
        S.MayPlay(100.1, 100) == false)
    Check("A moment later it plays again", S.MayPlay(101, 100))
    Check("The gap can be asked for", S.MayPlay(100.2, 100, 0.1))

    ---------------------------------------------------------------------
    -- Reading and writing, against the real store
    ---------------------------------------------------------------------
    if ns.db then
        local before = ns.db.sounds
        ns.db.sounds = nil

        Check("A profile with no sounds still answers",
            S.Get("request", 33206) == "" and not S.HasAny("request"))

        S.Set("request", nil, "Whistle")
        Check("An event sound is written", S.Get("request") == "Whistle")
        Check("...and the spell that has none reads it as its own nothing",
            S.Get("request", 33206) == "",
            "Get reports what is SET, the chain is Choice's job")
        Check("Something is set now", S.HasAny("request"))

        S.Set("request", 33206, "Bell")
        Check("A spell sound is written", S.Get("request", 33206) == "Bell")
        Check("...and its neighbour is untouched",
            S.Get("request", 47788) == "")
        Check("...and the event's own is untouched",
            S.Get("request") == "Whistle")

        -- Clearing means "follow again", which is how a picker hands a
        -- setting back. The empty string must not survive as a value.
        S.Set("request", 33206, "")
        Check("Clearing a spell goes back to following",
            S.Get("request", 33206) == ""
            and S.Choice(S.Config(), "request", 33206) == "Whistle")

        S.Set("request", nil, "")
        Check("Clearing the event leaves nothing set",
            not S.HasAny("request"))

        ns.db.sounds = before
    else
        Skip("The sound store reads and writes", "no profile is open")
    end
end

---------------------------------------------------------------------------
-- The command list, which two readers share
--
-- The About page draws ns.COMMANDS and the chat help prints it. Before this
-- they were two hand-typed lists, and the second had gone stale: it still
-- advertised /zs text and had never heard of build, modules, report, skin,
-- test, taunt or death. Checked here so it cannot drift apart again.
---------------------------------------------------------------------------
local function TestCommandList()
    local commands = ns.COMMANDS or {}

    Check("There is a command list at all", #commands > 0,
        string.format("%d entries", #commands))

    -- An entry is a HEADING or a COMMAND. One that is both would be drawn
    -- twice, and one that is neither is an empty row nobody can see.
    local shaped, described = true, true
    for _, entry in ipairs(commands) do
        local isGroup = entry.group ~= nil
        local isCommand = entry.cmd ~= nil
        if isGroup == isCommand then shaped = false end
        if isCommand and (entry.text == nil or entry.text == "") then
            described = false
        end
    end
    Check("Every entry is either a heading or a command", shaped)
    Check("Every command says what it does", described)

    -- WHAT THE SLASH HANDLER ACTUALLY ANSWERS TO. A list that names a command
    -- with no handler behind it is worse than a short list - that is why
    -- /zs route came out when Routes was parked.
    local handled = {
        [""] = true, unlock = true, lock = true, build = true, minimap = true,
        cdm = true, skin = true, text = true, numbers = true, tanks = true,
        cotanks = true, modules = true, module = true, welcome = true,
        externals = true, external = true, taunt = true, taunts = true,
        reminders = true, reminder = true, death = true, test = true,
        report = true, auras = true, bars = true, reset = true,
        raidbar = true, raid = true, check = true, invite = true,
        invites = true, loca = true, language = true,
        specs = true, spec = true,
        sounds = true, sound = true,
    }

    local unknown
    for _, entry in ipairs(commands) do
        if entry.cmd then
            -- "/zs auras forget <glowID>" -> "auras"; "/zs" -> "".
            local word = entry.cmd:match("^/zs%s*(%S*)") or ""
            if not handled[word:lower()] then unknown = entry.cmd end
        end
    end
    Check("Every command listed has a handler behind it", unknown == nil,
        unknown and ("no handler for " .. unknown) or nil)

    ---------------------------------------------------------------------
    -- Cutting it into two columns
    ---------------------------------------------------------------------
    local cut = ns.Options.SplitCommands(commands)

    Check("The cut leaves something in both columns",
        cut >= 1 and cut < #commands, string.format("cut after %d of %d",
            cut, #commands))

    -- A heading is a promise that entries follow it. Ending the left column
    -- on one puts the heading at the bottom of one column and everything it
    -- names at the top of the other.
    Check("The left column does not end on a heading",
        commands[cut] ~= nil and commands[cut].group == nil)

    -- Degenerate input must answer rather than throw: an empty list has no
    -- cut, and a single entry cannot be split at all.
    Check("An empty list answers without throwing",
        ns.Options.SplitCommands({}) == 0)
    Check("One entry stays in one column",
        ns.Options.SplitCommands({ { cmd = "/zs", text = "open" } }) == 1)

    ---------------------------------------------------------------------
    -- The in-game changelog, which is the OTHER hand-typed list
    --
    -- CHANGELOG.md is the source of truth and changelog.py renders the page
    -- and the Discord post from it. ns.CHANGELOG is written by hand on top of
    -- that, so it can drift the same way the command list did - and the way
    -- it drifts is the worst one available: shipping a version whose own
    -- Changelog page has never heard of it. The page marks entry 1 as the one
    -- you are running, so if that is not true it says so out loud to every
    -- player who opens it.
    ---------------------------------------------------------------------
    local newest = ns.CHANGELOG and ns.CHANGELOG[1]

    Check("The changelog names the version being shipped",
        newest ~= nil and newest.version == ns.version,
        newest and ("newest entry " .. tostring(newest.version)
            .. ", running " .. tostring(ns.version)) or "no changelog at all")

    -- Newest first is what the page assumes; an entry inserted in the wrong
    -- place puts "installed" on somebody else's release.
    local ordered, empty = true, nil
    local function Rank(version)
        local major, minor, patch = tostring(version):match("(%d+)%.(%d+)%.(%d+)")
        if not major then return -1 end
        return tonumber(major) * 1000000 + tonumber(minor) * 1000 + tonumber(patch)
    end
    for index, entry in ipairs(ns.CHANGELOG or {}) do
        if index > 1 and Rank(entry.version)
            >= Rank(ns.CHANGELOG[index - 1].version) then
            ordered = false
        end
        if not entry.lines or #entry.lines == 0 then empty = entry.version end
    end
    Check("The changelog runs newest first", ordered)
    Check("No release in it is silent", empty == nil,
        empty and (tostring(empty) .. " has no lines") or nil)
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

    -- WHAT THE LIST IS ALLOWED TO SAY.
    --
    -- The card in the bar list carries a badge for a bar that is not on
    -- screen, and that list is redrawn when you change something in it - not
    -- when you pull, take a target or zone in. So Fixed may only hand back
    -- reasons that outlive the moment, and it may not word them itself.
    Check("A switched-off bar says so in the list",
        ns.Visibility:Fixed(off) ~= nil)
    Check("The list and the panel word it the same way",
        ns.Visibility:Fixed(off) == ns.Visibility:Explain(off))
    Check("'Never' is settled enough for the list",
        ns.Visibility:Fixed(never) ~= nil)

    local pull = Fresh()
    pull.show.mode, pull.show.combat = "rules", "in"
    Check("A bar waiting for combat is explained but not badged",
        ns.Visibility:Explain(pull) ~= nil and ns.Visibility:Fixed(pull) == nil)

    -- And the badge cannot lie: everything it appears on really is off screen.
    local honest = true
    for _, probe in ipairs({ cfg, off, never, pull }) do
        if ns.Visibility:Fixed(probe) and ns.Visibility:Evaluate(probe) then
            honest = false
        end
    end
    Check("Nothing badged as hidden is on screen", honest)

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
        -- Each ability is {spellID, name} rather than a bare name, so the
        -- enemy tip can draw it with its icon - the rule everywhere else in
        -- this addon. Still once each.
        Check("It lists what it used, once each",
            #facts.spells == 2 and facts.spells[1].name == "Scratch"
            and facts.spells[2].name == "Melee")
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

---------------------------------------------------------------------------
-- Everybody ELSE's deaths
--
-- The rows below are the four his client actually handed over on 2026-08-14,
-- typed in as they came rather than rounded into tidy examples. That matters
-- for exactly one reason: two of the four died in the SAME SECOND, which is
-- the case a made-up list would never have contained and the one where the
-- ordering has to fall back on something other than the clock.
---------------------------------------------------------------------------
local function TestRaidDeaths()
    local R = ns.RaidDeaths
    if not R then
        Skip("Raid deaths", "the module is not loaded")
        return
    end

    -- Newest first, which is the order the client hands them over.
    local function Recorded()
        return {
            { name = "Meredy Huntswell", classFilename = "MAGE",
              deathRecapID = 40, deathTimeSeconds = 87, isLocalPlayer = false },
            { name = "Austin Huxworth", classFilename = "HUNTER",
              deathRecapID = 39, deathTimeSeconds = 65, isLocalPlayer = false },
            { name = "Crenna Earth-Daughter", classFilename = "DRUID",
              deathRecapID = 38, deathTimeSeconds = 62, isLocalPlayer = false },
            { name = "Shuja Grimaxe", classFilename = "SHAMAN",
              deathRecapID = 37, deathTimeSeconds = 62, isLocalPlayer = false },
        }
    end

    local rows = R.Rows(Recorded(), "Zwoelf")
    Check("Every death in the list is read", #rows == 4,
        string.format("%d of 4", #rows))

    local order, timed = R.Timeline(rows)
    Check("The Current session's clock is usable", timed)
    Check("They come out in the order they fell",
        order[1].short == "Shuja Grimaxe"
        and order[2].short == "Crenna Earth-Daughter"
        and order[3].short == "Austin Huxworth"
        and order[4].short == "Meredy Huntswell",
        order[1] and order[1].short)

    -- The two at 62 are the whole reason there is a second sort key: the
    -- clock cannot separate them and the recap id can, because it counts up.
    Check("Two deaths in one second are split by the recap id",
        order[1].recapID == 37 and order[2].recapID == 38)

    Check("The gap to the one before is what tells a wipe from bad luck",
        order[1].gap == nil and order[2].gap == 0
        and order[3].gap == 3 and order[4].gap == 22,
        tostring(order[4] and order[4].gap))

    -- Overall answers -1 for every death. That is "there is no clock in
    -- here", not "he died at second zero", and a timeline drawn off it would
    -- put four people on the same tick.
    local blind = Recorded()
    for _, row in ipairs(blind) do row.deathTimeSeconds = -1 end
    local noClock, stillTimed = R.Timeline(R.Rows(blind, "Zwoelf"))
    Check("Overall's -1 is refused as a time", not stillTimed)
    Check("...and they still come out oldest first, by recap id",
        noClock[1].short == "Shuja Grimaxe"
        and noClock[4].short == "Meredy Huntswell")

    -- And with neither, the order the client listed them in is the last
    -- thing left - reversed, because that list arrives newest first.
    local bare = Recorded()
    for _, row in ipairs(bare) do
        row.deathTimeSeconds, row.deathRecapID = -1, nil
    end
    local reversed = R.Timeline(R.Rows(bare, "Zwoelf"))
    Check("With no clock and no id the list order becomes the order",
        reversed[1].short == "Shuja Grimaxe"
        and reversed[4].short == "Meredy Huntswell")

    local broken = Recorded()
    broken[2].name = nil
    Check("A row that cannot even be named is dropped, not drawn empty",
        #R.Rows(broken, "Zwoelf") == 3)

    -- The damage meter lists creatures as readily as people, and a creature's
    -- own name may have a hyphen in it. Cutting at the first one listed her
    -- as "Crenna Earth", which looks like a truncation bug and is not.
    Check("A creature whose own name has a hyphen keeps all of it",
        R.Rows({ { name = "Crenna Earth-Daughter", deathRecapID = 38 } },
            "Zwoelf")[1].short == "Crenna Earth-Daughter")
    Check("...and a player's realm half still comes off",
        ns.Death.StripRealm("Zwoelf-Destromath") == "Zwoelf")

    ---------------------------------------------------------------------
    -- Whose row it is
    ---------------------------------------------------------------------
    Check("The client's own isLocalPlayer decides, name or no name",
        R.IsYou({ isLocalPlayer = true, name = "Meredy Huntswell" }, "Zwoelf")
        and not R.IsYou({ isLocalPlayer = false, name = "Zwoelf" }, "Zwoelf"))
    Check("...and without the flag the name answers, realm half dropped",
        R.IsYou({ name = "Zwoelf-Destromath" }, "Zwoelf")
        and not R.IsYou({ name = "Meredy Huntswell" }, "Zwoelf"))

    ---------------------------------------------------------------------
    -- What ended each one
    ---------------------------------------------------------------------
    -- Death.ReadRecap hands events over OLDEST first, so the last one is the
    -- one that landed last. The amounts are his: 31829 with 28483 of it
    -- wasted on a corpse.
    local events = {
        { name = "Spirit Rend", who = "Tormented Shade", amount = 4000 },
        { name = "Spirit Rend", who = "Tormented Shade", amount = 31829,
          overkill = 28483, spellID = 1259255 },
    }
    local blow = R.Blow(events)
    Check("The killing blow is the last event, not the first",
        blow ~= nil and blow.amount == 31829 and blow.overkill == 28483)
    Check("...and it names the source of the hit",
        blow ~= nil and blow.who == "Tormented Shade"
        and blow.spellID == 1259255)

    -- A heal can be the newest thing in a recap - somebody was still trying.
    -- Taking the newest event blindly would print the healer as the killer.
    events[#events + 1] = { name = "a heal", who = "A Friend",
        heal = true, amount = 9000 }
    local past = R.Blow(events)
    Check("A heal after the killing blow does not become the killer",
        past ~= nil and past.who == "Tormented Shade" and past.amount == 31829)

    Check("A recap with nothing in it has no killing blow",
        R.Blow({}) == nil and R.Blow(nil) == nil)

    local counted = R.Culprits({
        { blow = { who = "Tormented Shade", spell = "Spirit Rend" } },
        { blow = { who = "Tormented Shade", spell = "Spirit Rend" } },
        { blow = { who = "Tormented Shade", spell = "Void Bolt" } },
        { blowWhy = "the recap is empty" },
    })
    Check("What did the killing is counted per ABILITY, not per mob",
        #counted == 2 and counted[1].count == 2
        and counted[1].spell == "Spirit Rend",
        string.format("%d kinds", #counted))
    Check("A death whose recap said nothing counts towards nothing",
        counted[1].count + counted[2].count == 3)

    ---------------------------------------------------------------------
    -- How the line reads
    ---------------------------------------------------------------------
    Check("A class the colour table knows is coloured",
        R.Coloured("Zwoelf", "DEATHKNIGHT"):find("|cff", 1, true) == 1)
    Check("...and one it has never heard of is still a readable name",
        R.Coloured("Meredy", "SOMETHINGNEW") == "Meredy")
    Check("The clock reads the way a fight is talked about",
        R.Clock(121) == "2:01" and R.Clock(62) == "1:02"
        and R.Clock(0) == "0:00" and R.Clock(nil) == "--:--")

    local line = R.Line({ short = "Shuja Grimaxe", class = "SHAMAN", at = 62,
        gap = 3, blow = { who = "Tormented Shade", spell = "Spirit Rend",
            amount = 31829, overkill = 28483 } }, true)
    Check("A line says when, who and to what",
        line:find("1:02", 1, true) and line:find("Shuja", 1, true)
        and line:find("Tormented Shade", 1, true)
        and line:find("Spirit Rend", 1, true), line)
    local silent = R.Line({ short = "Shuja Grimaxe",
        blowWhy = "the recap is empty" }, false)
    Check("...and a death whose recap refused says so instead of nothing",
        silent:find("the recap is empty", 1, true) ~= nil, silent)

    ---------------------------------------------------------------------
    -- Keeping the fight, because the Current session does not wait
    ---------------------------------------------------------------------
    Check("A pull is named by its FIRST death, which is its lowest id",
        R.FightKey({ { recapID = 40 }, { recapID = 37 }, { recapID = 38 } })
        == 37)
    Check("...and a list with no ids in it has no name",
        R.FightKey({}) == nil and R.FightKey({ {} }) == nil)

    local log = {}
    R.Remember(log, { key = 37, mark = "first read" }, 3)
    R.Remember(log, { key = 37, mark = "second read" }, 3)
    Check("The same pull read twice is one entry, not two",
        #log == 1 and log[1].mark == "second read")
    R.Remember(log, { key = 44 }, 3)
    Check("A pull with a different first death is a new entry", #log == 2)
    R.Remember(log, { key = 51 }, 3)
    R.Remember(log, { key = 58 }, 3)
    Check("The oldest drops out when the cap is reached",
        #log == 3 and log[1].key == 44,
        string.format("%d kept, oldest %s", #log, tostring(log[1].key)))

    ---------------------------------------------------------------------
    -- THE GAME'S OWN VERDICT
    --
    -- The recap marks damage the client itself considers avoidable. It is
    -- the most valuable field in the whole thing and the easiest to report
    -- dishonestly: a client that withholds it must not make a raid look
    -- blameless. Three answers, never two.
    ---------------------------------------------------------------------
    local function Died(flag)
        return { blow = { who = "A", spell = "B", avoidable = flag } }
    end
    local yes, no, unknown = R.Avoidable({ Died(true), Died(true),
        Died(false), Died(nil), { blowWhy = "empty" } })
    Check("Avoidable, not avoidable and NOT SAID are three answers",
        yes == 2 and no == 1 and unknown == 2,
        string.format("%d yes, %d no, %d not said", yes, no, unknown))

    Check("A pull with an avoidable death says so and counts it",
        R.Verdict({ { at = 0, blow = { avoidable = true } },
                    { at = 4, blow = { avoidable = false } } }, {})
            :find("1 of 2 to damage the game calls avoidable", 1, true) ~= nil)
    Check("...and one where the client said nothing claims NOTHING",
        R.Verdict({ { at = 0, blow = {} }, { at = 4, blow = {} } }, {})
            :find("avoidable", 1, true) == nil)
    Check("...while all-clear is only said when the client said it every time",
        R.Verdict({ { at = 0, blow = { avoidable = false } },
                    { at = 4, blow = { avoidable = false } } }, {})
            :find("none of it was avoidable", 1, true) ~= nil)

    Check("The verdict leads with the thing that killed more than one",
        R.Verdict({ { at = 0 }, { at = 2 } },
            { { who = "Shade", spell = "Grim Ward", count = 2 } })
            :find("Grim Ward killed 2 of them", 1, true) == 1)
    Check("...and says how long the dying took",
        R.Verdict({ { at = 10 }, { at = 16 } }, {})
            :find("2 deaths in 6s", 1, true) ~= nil)
    Check("A pull nobody died in has no verdict at all",
        R.Verdict({}, {}) == "")

    ---------------------------------------------------------------------
    -- The hit that mattered, which is rarely the one that finished them
    ---------------------------------------------------------------------
    -- Oldest first, the way ReadRecap hands them over. The last event is
    -- 31829 with 28483 of it wasted on a corpse, so it only LANDED 3346 -
    -- the 20000 two events earlier is the one worth talking about.
    local story = {
        { name = "Melee", who = "Shade", amount = 5000 },
        { name = "Grim Ward", who = "Shade", amount = 20000, spellID = 7 },
        { name = "a heal", who = "A Friend", amount = 90000, heal = true },
        { name = "Spirit Rend", who = "Shade", amount = 31829,
          overkill = 28483 },
    }
    local real = R.RealBlow(story)
    Check("The hit that mattered is the one that TOOK the most",
        real ~= nil and real.spell == "Grim Ward" and real.landed == 20000,
        real and real.spell)
    Check("...and a heal is never it", real ~= nil and real.who ~= "A Friend")
    Check("...and when the killing blow IS the biggest, nothing is claimed",
        R.RealBlow({ { name = "Small", who = "X", amount = 10 },
                     { name = "Big", who = "X", amount = 900 } }) == nil)
    Check("A recap of one event has no earlier hit to name",
        R.RealBlow({ { name = "Only", who = "X", amount = 10 } }) == nil)

    ---------------------------------------------------------------------
    -- The enemy tip, which three windows share
    ---------------------------------------------------------------------
    local summary = ns.Death.SourceSummary({
        { who = "Shade", name = "Melee", amount = 5000 },
        { who = "Shade", name = "Spirit Rend", amount = 31829, spellID = 7 },
        { who = "Shade", name = "Melee", amount = 4000 },
        { who = "Somebody Else", name = "Cleave", amount = 999 },
        { who = "Shade", name = "a heal", amount = 90000, heal = true },
    }, "Shade")
    Check("The tip counts only what THIS thing did",
        summary.hits == 3 and summary.total == 40829
        and summary.biggest == 31829,
        string.format("%d hits, %d total", summary.hits, summary.total))
    Check("...and names each ability once, with its id for the icon",
        #summary.spells == 2 and summary.spells[1].name == "Melee"
        and summary.spells[2].spellID == 7)

    Check("What it did reads as a sentence",
        ns.Death.EnemyFacts(summary):find("3 hits", 1, true) ~= nil)
    Check("...and one hit is not \"1 hits\"",
        ns.Death.EnemyFacts({ hits = 1, total = 500, spells = {} })
            :find("One hit", 1, true) ~= nil)
    Check("A source nothing is known about says nothing at all",
        ns.Death.EnemyFacts(nil) == "" and ns.Death.EnemySpells(nil) == "")
    Check("The ability line carries every ability",
        ns.Death.EnemySpells(summary):find("Spirit Rend", 1, true) ~= nil)

    -- It goes to disk with the pull, because the recap is gone by the time
    -- anybody points at the row.
    local stored = R.PlainSummary(summary)
    Check("The tip's facts survive a reload",
        stored ~= nil and stored.hits == 3 and #stored.spells == 2
        and stored.spells[2].spellID == 7)
    Check("...and a summary of nothing is not written",
        R.PlainSummary(nil) == nil and R.PlainSummary({}) == nil)

    ---------------------------------------------------------------------
    -- What goes to chat
    ---------------------------------------------------------------------
    local lines = R.ShareLines({
        { short = "Shuja", at = 62,
          blow = { who = "Grim Skirmisher", spell = "Melee" } },
        { short = "Meredy", at = 87, blowWhy = "the recap is empty" },
    }, { timed = true, where = "M+7 - Ara-Kara", duration = 121,
         culprits = {} })
    Check("A share names the place and the count first",
        lines ~= nil and lines[1]:find("Ara-Kara", 1, true) ~= nil
        and lines[1]:find("2 died", 1, true) ~= nil, lines and lines[1])
    Check("...and one line per death, with the time on it",
        #lines >= 3 and lines[#lines]:find("Meredy", 1, true) ~= nil
        and lines[#lines - 1]:find("1:02", 1, true) ~= nil)
    -- An inline icon is an escape sequence. It either arrives at the other
    -- end as raw punctuation or not at all, so it is stripped - Death's rule
    -- and Death's own function.
    Check("...with no inline icons in it",
        table.concat(lines, " "):find("|T", 1, true) == nil)
    Check("A pull with nobody dead has nothing to share",
        R.ShareLines({}, {}) == nil and R.ShareLines(nil, nil) == nil)

    ---------------------------------------------------------------------
    -- Surviving a reload
    --
    -- A new saved-variable schema, so the two rules are checked rather than
    -- commented: only what is READABLE goes in, copied field by field, and a
    -- fight nothing could be read out of is not kept.
    ---------------------------------------------------------------------
    local fight = {
        key = 37, when = "21:14", where = "M+7 - Ara-Kara",
        whereShort = "M+7", duration = 121, at = 99999,
        entries = {
            { name = "Shuja Grimaxe", short = "Shuja Grimaxe",
              class = "SHAMAN", at = 62, seq = 1, recapID = 37, you = false,
              blow = { who = "Grim Skirmisher", spell = "Melee",
                       amount = 39900, overkill = 8300,
                       art = { creatureID = 214390 },
                       summary = { hits = 2, total = 44000, biggest = 39900,
                           spells = { { name = "Melee" } } } } },
            { name = "Meredy Huntswell", short = "Meredy Huntswell",
              class = "MAGE", at = 87, seq = 4, recapID = 40, you = false,
              blowWhy = "the recap is empty" },
        },
    }

    local saved = R.Persist(fight)
    Check("A pull is written field by field",
        saved ~= nil and saved.key == 37 and #saved.entries == 2
            and saved.whereShort == "M+7")
    -- `at` is a GetTime stamp and GetTime restarts with the client, so a
    -- stored one would be a time in a clock that no longer exists.
    Check("...and the GetTime stamp is deliberately NOT written",
        saved.at == nil)
    Check("...and the killer's face travels with it",
        saved.entries[1].blow ~= nil
        and saved.entries[1].blow.art.creatureID == 214390)
    -- The RULE for reducing a summary is checked on its own further up. This
    -- checks that Persist actually CALLS it - the recap is gone after a
    -- reload, so a tip with no facts on disk is a tip with no facts at all.
    Check("...and so does what that mob did, for the enemy tip",
        saved.entries[1].blow.summary ~= nil
        and saved.entries[1].blow.summary.hits == 2
        and #saved.entries[1].blow.summary.spells == 1)
    Check("...and a death whose recap said nothing keeps the reason",
        saved.entries[2].blowWhy == "the recap is empty"
        and saved.entries[2].blow == nil)

    fight.entries[1].junk = { "a field nobody whitelisted" }
    Check("A field nobody named never reaches the disk",
        R.Persist(fight).entries[1].junk == nil)
    fight.entries[1].junk = nil

    local back = R.Restore({ saved })
    Check("It reads back as one pull with both deaths",
        #back == 1 and #back[1].entries == 2
        and back[1].entries[1].short == "Shuja Grimaxe")
    -- Derived on the way in, not stored: a better count written next month
    -- applies to the pulls already on disk.
    Check("...with the killing counted afresh rather than stored",
        back[1].culprits ~= nil and #back[1].culprits == 1
        and back[1].culprits[1].who == "Grim Skirmisher")

    Check("A pull with nothing readable in it is not kept",
        R.Persist({ entries = {} }) == nil and R.Persist(nil) == nil
        and #R.Restore({ { entries = {} } }) == 0)
    Check("...and neither is a death that cannot even be named",
        #R.Persist({ entries = { { name = 5 },
            { name = "Real Person" } } }).entries == 1)

    ---------------------------------------------------------------------
    -- What the footer says
    ---------------------------------------------------------------------
    Check("A count where nothing repeats is not worth printing",
        not R.WorthCounting({ { count = 1 }, { count = 1 } })
        and R.WorthCounting({ { count = 1 }, { count = 2 } }))
    Check("...so four deaths to four things say it in one sentence",
        R.FootLine({ { who = "A", spell = "B", count = 1 } }, 4)
            :find("each to something different", 1, true) ~= nil)
    Check("...and something that killed three is named and counted",
        R.FootLine({ { who = "Shade", spell = "Rend", count = 3 } }, 3)
            :find("3x Shade", 1, true) ~= nil)
    Check("A fight nobody died in has no footer at all",
        R.FootLine({}, 0) == "")
    Check("The footer offers the click only when something can be opened",
        R.FootLine({}, 4, true):find("last ten seconds", 1, true) ~= nil
        and R.FootLine({}, 4, false):find("last ten seconds", 1, true) == nil)

    ---------------------------------------------------------------------
    -- ONE DEATH, KEPT WHOLE AND OPENED
    ---------------------------------------------------------------------
    local story = {
        { t = 8.2, amount = 4000, hp = 30000, name = "Melee",
            who = "Grim Skirmisher", avoidable = false },
        { t = 5.0, amount = 12000, hp = 18000, name = "Grim Ward",
            who = "Grim Skirmisher", spellID = 1234, avoidable = true },
        { t = 2.0, amount = 9000, hp = 27000, name = "Renew", heal = true },
        { t = 0.0, amount = 31829, overkill = 28483, name = "Spirit Rend",
            who = "Tormented Shade", spellID = 1259255 },
    }

    local kept, dropped = R.PlainEvents(story)
    Check("A recap's hits are kept, field by field",
        kept ~= nil and #kept == 4 and dropped == 0
        and kept[4].overkill == 28483 and kept[2].spellID == 1234)
    Check("...a heal stays marked as one",
        kept[3].heal == true and kept[1].heal == false)
    Check("...and avoidable survives as a boolean, nil included",
        kept[2].avoidable == true and kept[1].avoidable == false
        and kept[4].avoidable == nil)

    -- The cap, and it must keep the END of the story: the hits nearest the
    -- death are the ones the window is opened for.
    local long = {}
    for i = 1, R.EVENTS_KEPT + 6 do
        long[i] = { t = 30 - i * 0.1, amount = i, name = "Hit " .. i }
    end
    local trimmed, cut = R.PlainEvents(long)
    Check("A very long death is trimmed from the OLD end",
        trimmed ~= nil and #trimmed == R.EVENTS_KEPT and cut == 6
        and trimmed[#trimmed].name == "Hit " .. #long)
    Check("...and nothing readable at all keeps nothing",
        R.PlainEvents({ { t = "secret", amount = 1 } }) == nil
        and R.PlainEvents("not a list") == nil)

    -- THE GAME'S OWN VERDICT over the hits, three answers and never two.
    local yes, no, unknown = R.AvoidableHits(kept)
    Check("Avoidable hits are counted, and heals are not damage",
        yes == 1 and no == 1 and unknown == 1)
    local _, cleanNo, cleanUnknown = R.AvoidableHits({
        { amount = 1, avoidable = false }, { amount = 2, avoidable = false } })
    Check("...a clean bill needs the game to have answered every time",
        R.DetailVerdict({ { amount = 1, avoidable = false } })
            :find("None of this", 1, true) ~= nil
        and cleanNo == 2 and cleanUnknown == 0)
    Check("...and one unanswered hit takes the clean bill away",
        R.DetailVerdict({ { amount = 1, avoidable = false },
            { amount = 2 } }) == "")
    Check("...while one it DID call avoidable is counted out loud",
        R.DetailVerdict(kept):find("1 of these hits is", 1, true) ~= nil)

    Check("A death with nothing kept cannot be opened",
        not R.Openable(nil) and not R.Openable({ name = "X" })
        and not R.Openable({ events = {} }) and R.Openable({ events = kept }))

    local entry = {
        name = "Meredy Huntswell", short = "Meredy",
        class = "PRIEST", at = 87, you = false,
        events = kept, maxHP = 41000, dropped = 6,
        blow = { who = "Tormented Shade", spell = "Spirit Rend",
            amount = 31829, overkill = 28483 },
        real = { who = "Grim Skirmisher", spell = "Grim Ward", landed = 12000 },
    }
    Check("The opened death names who fell and when",
        R.DetailTitle(entry, true):find("Meredy", 1, true) ~= nil
        and R.DetailTitle(entry, true):find("1:27", 1, true) ~= nil)
    Check("...and says nothing about a clock it does not have",
        R.DetailTitle(entry, false):find(":", 1, true) == nil)
    local line = R.DetailLine(entry)
    Check("...what ended them, and what actually dropped them",
        line:find("Tormented Shade", 1, true) ~= nil
        and line:find("overkill", 1, true) ~= nil
        and line:find("The hit that mattered", 1, true) ~= nil)
    Check("...and a death whose recap said nothing says that instead",
        R.DetailLine({ blowWhy = "the recap gave nothing" })
            == "the recap gave nothing")
    Check("What was cut off is said out loud, never silently",
        R.DetailNote(entry, false, 10):find("6 older hits", 1, true) ~= nil
        and R.DetailNote({}, false, 10):find("older", 1, true) == nil)
    Check("...and so is a recap that reaches back past the window",
        R.DetailNote({}, true, 10):find("all the recap gave", 1, true) ~= nil)

    -- ACROSS THE DISK. The story is the whole point of the feature and it is
    -- read after a reload more often than before one.
    local rebuilt = R.Persist({ entries = { entry } })
    local back = rebuilt and rebuilt.entries[1]
    Check("The last seconds survive being written and read back",
        back ~= nil and back.events ~= nil and #back.events == #kept
        and back.maxHP == 41000
        and back.events[4].overkill == 28483)
    Check("...including the three-way avoidable answer",
        back.events[2].avoidable == true
        and back.events[1].avoidable == false
        and back.events[4].avoidable == nil)
    Check("...and the count of what was never kept is not lost on the way",
        back.dropped == 6)

    ---------------------------------------------------------------------
    -- THE WIRING, not the rule. Everything above is arithmetic on tables
    -- this file typed out. This asks the client the addon will actually ask,
    -- and reports what came back rather than asserting a fight is running.
    ---------------------------------------------------------------------
    local entries, why, info = R.Collect()
    if not (entries and info) then
        Skip("Reading the deaths the client is holding", why or "?")
        return
    end

    Check("The client's own list comes back ordered",
        #entries > 0 and (not info.timed
            or entries[1].at <= entries[#entries].at),
        string.format("%d deaths, %s", #entries,
            info.timed and "timed" or "no clock"))

    local read, refused = 0, 0
    for _, entry in ipairs(entries) do
        if entry.blow then read = read + 1
        elseif entry.blowWhy then refused = refused + 1 end
    end
    Check("Every death either read its recap or said why it could not",
        read + refused == #entries,
        string.format("%d read, %d refused", read, refused))

    Skip("What the client is holding right now", string.format(
        "%d deaths in %s%s, %d recaps read", #entries, info.label,
        info.duration and (" of " .. R.Clock(info.duration)) or "", read))

    -- And the capture, driven against whatever the client has. A fight with
    -- no clock on it must NOT be kept: that is Overall, and keeping it would
    -- overwrite a good capture with a worse one.
    local before = R.log
    R.log = {}
    local fight = R.Capture()
    if not fight then
        Skip("Keeping the fight", info.timed
            and "the client had a timed session but nothing was kept"
            or "no timed session right now, so there is nothing to keep")
    else
        Check("A timed fight is kept whole",
            #R.log == 1 and #fight.entries > 0 and fight.key ~= nil,
            string.format("%d deaths, pull %s", #fight.entries,
                tostring(fight.key)))
        R.Capture()
        Check("...and reading the same pull again replaces it",
            #R.log == 1, string.format("%d fights kept", #R.log))
    end
    R.log = before
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

    ---------------------------------------------------------------------
    -- A ROW'S TEXT STOPS BEFORE ITS CONTROL - BOTH LINES OF IT
    --
    -- The owner photographed the welcome window with a module's blurb drawn
    -- straight through the NEW badge beside it. The label had been stopped at
    -- the control since this widget was written and the SUBLABEL never was:
    -- it got one anchor, top-left, and ran the full width of the row.
    --
    -- Invisible for as long as every blurb was short enough, and every page
    -- in the addon uses this row.
    --
    -- The rule is checkable without a screen because it is not about pixels:
    -- a piece of text with ONE anchor has no right-hand edge at all. Two
    -- anchors is what "stops somewhere" means, in game and out here alike.
    ---------------------------------------------------------------------
    local sampleParent = CreateFrame("Frame", nil, UIParent)
    local sample = UI.Row(sampleParent, "Label", {
        sublabel = "A second line long enough to run under a control",
        controlWidth = 96,
    })

    Check("A row's label stops before its control",
        sample.label and sample.label:GetNumPoints() >= 2,
        sample.label and tostring(sample.label:GetNumPoints()) or "no label")

    Check("A row's second line stops before its control too",
        sample.sub and sample.sub:GetNumPoints() >= 2,
        sample.sub and tostring(sample.sub:GetNumPoints()) or "no sublabel")

    -- And a row WITHOUT one still has exactly the label. Written because the
    -- fix above is one `if row.sub`, and an `if` that is wrong in the other
    -- direction throws on every ordinary row in the addon.
    local plain = UI.Row(sampleParent, "Label", { controlWidth = 96 })
    Check("A row with no second line is still built",
        plain.label ~= nil and plain.sub == nil)

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
        "CARD_HEAD_H", "NAV_ITEM_H", "CONTROL_H", "BUTTON_H", "SLIDER_H",
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

    -- TWO CHANNELS ON ONE BUTTON, AND THEY ARE NOT THE SAME QUESTION.
    --
    -- "This is the current mode" is a bed; "you cannot press this" is a dimmed
    -- label. They were the same channel once, on edit mode's Move/Build pair,
    -- where the mode that was simply not current read as a dead button.
    --
    -- The colour cannot be read back out here - the harness has no pixels - so
    -- what this checks is that both channels still exist and still take a
    -- call. A button that lost SetActive throws in the one place that has no
    -- test of its own: the overlay, in combat, with no window open.
    local probe = UI.Button(UIParent, "Probe", 80, nil)
    local channels = type(probe.SetActive) == "function"
        and type(probe.SetEnabled) == "function"
    if channels then
        channels = pcall(function()
            probe:SetActive(true)
            probe:SetEnabled(false)
            probe:SetEnabled(true)
            probe:SetActive(false)
        end)
    end
    Check("A button can say it is the one that is on", channels)

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
    -- WHAT A DRAG BETWEEN TWO PLACES MEANS
    --
    -- Owner, 2026-08-13: "ich haette gern das alle spells, icons what ever im
    -- addon drag and drop bar sind ... also auch plaetze tauschen, reinziehen,
    -- rausziehen etc. ueberall wo man sachen adden kann."
    --
    -- The rule is checked here and the hands are not, and that split is
    -- forced: the harness answers GetCursorPosition with a constant 0,0 and
    -- IsVisible with false, so every hit test comes back nil out here. A check
    -- driven through the real widgets would prove the stub refuses drops.
    -----------------------------------------------------------------------
    do
        local What = ns.UI.DragOutcome

        Check("Dragging nothing is not a gesture",
            What({ kind = "spell" }, { kind = "spell" }) == "none")

        Check("Let go over open air and it comes off",
            What({ kind = "spell", payload = 42 }, nil) == "clear")

        Check("Let go over an empty place and it goes there",
            What({ kind = "spell", payload = 42 },
                 { kind = "spell" }) == "drop")

        Check("Let go over a full place and the two change places",
            What({ kind = "spell", payload = 42 },
                 { kind = "spell", payload = 99 }) == "swap")

        Check("Let go over where it started and nothing happens",
            What({ kind = "spell", payload = 42 },
                 { kind = "spell", payload = 42, same = true }) == "none")

        -- THE ONE THAT STOPS A SILENT CORRUPTION. One list holds every grid in
        -- the window, so a raid bar place - which holds the word "mark3" - is
        -- a neighbour of a cooldown cell, which holds a number. Written into
        -- each other they draw an empty square and say nothing about why.
        Check("A marker may not be dropped into a cooldown bar",
            What({ kind = "raidbar", payload = "mark3" },
                 { kind = "spell", payload = 42 }) == "refused")

        Check("A cooldown may not be dropped onto the raid bar",
            What({ kind = "spell", payload = 42 },
                 { kind = "raidbar" }) == "refused")

        -- Squares that are a VIEW of a set rather than an arrangement: the
        -- death log sorts its defensives by name and rebuilds them every
        -- refresh, so a swap would take both out, put both back and change
        -- nothing - which reads as broken rather than as refused.
        Check("A place that is not a position cannot be swapped with",
            What({ kind = "defensive", payload = 42 },
                 { kind = "defensive", payload = 99, ordered = false })
                == "refused")

        -- ...but taking one OUT of that set is exactly what those squares can
        -- say, so it must still work.
        Check("An unordered place can still be dragged out of",
            What({ kind = "defensive", payload = 42 }, nil) == "clear")

        -- And a spell may still land in an EMPTY unordered square: that is
        -- adding it to the set, which is the whole point of the page.
        Check("An empty unordered place still takes a drop",
            What({ kind = "defensive", payload = 42 },
                 { kind = "defensive", ordered = false }) == "drop")
    end

    -----------------------------------------------------------------------
    -- ONE PRESS, ONE RUN
    --
    -- Owner, 2026-08-13: "der raid check, der geht nur auf wenn man den
    -- button gedrueckt haellt ... bitte so einstellen, das bei klick fenster
    -- aufgeht und auch stehen bleibt."
    --
    -- A place is registered for both directions - a secure one has to be - so
    -- every press arrives at the script twice. Toggle on the way down opened
    -- the window, Toggle on the way up shut it, and the only way to see it
    -- was to keep holding the mouse down. The pull timer and the ready check
    -- fired twice as well and simply did not look wrong.
    --
    -- The gate cannot be pressed out here: the stub has no mouse. It is a
    -- pure function for that reason, and the DELIVERY ORDER is the thing
    -- being checked - including the two lopsided ones, because a keyboard
    -- binding and a scripted Click() do not deliver the same pair a mouse
    -- does.
    -----------------------------------------------------------------------
    do
        local Gate = ns.RaidBar.PressGate

        -- A mouse: down, then up. One run, on the first edge.
        local run, pressed = Gate(nil, "LeftButton", true)
        Check("A press acts on the way down", run and pressed == "LeftButton")
        run, pressed = Gate(pressed, "LeftButton", false)
        Check("The release of that same press does nothing",
            not run and pressed == nil)

        -- A scripted Click() and any client that only ever hands over the up
        -- edge: that up IS the press, and it must not be swallowed.
        run, pressed = Gate(nil, "LeftButton", false)
        Check("A lone release is a press of its own", run)

        -- Slide off the button and let go somewhere else: the up never comes.
        -- The stale memory may not eat the NEXT press.
        run, pressed = Gate(nil, "LeftButton", true)
        run, pressed = Gate(pressed, "LeftButton", true)
        Check("A press whose release went missing does not eat the next one",
            run and pressed == "LeftButton")

        -- Right-click cancels the pull timer while the left is still held.
        -- A different button is a different press.
        run, pressed = Gate("LeftButton", "RightButton", false)
        Check("The other button is its own press, and the first is remembered",
            run and pressed == "LeftButton")

        -- Two presses, four edges, two runs - the whole point, counted.
        --
        -- (The aura-binding block below is the other half of today's lesson:
        -- a rule with a test, and a wiring with one.)
        local runs = 0
        local memory = nil
        for _, edge in ipairs({ true, false, true, false }) do
            local acts
            acts, memory = Gate(memory, "LeftButton", edge)
            if acts then runs = runs + 1 end
        end
        Check("Two presses run the thing twice, not four times", runs == 2)
    end

    -----------------------------------------------------------------------
    -- TAKING AN ICON OFF THE SCREEN BY ITS STATE
    --
    -- A display of what you can press right now, or of what you are waiting
    -- for. Two useful readings and they are opposites, so it is one setting
    -- with three values rather than two switches that can contradict.
    --
    -- The case that matters most is the third answer: a cooldown the client
    -- will not talk about. An icon that vanishes because something could not
    -- be READ is indistinguishable from a bug, and it takes the spell with
    -- it - so unknown always shows.
    -----------------------------------------------------------------------
    do
        local Hidden = ns.Effects.HiddenByState

        Check("Off by default, whatever the state",
            not Hidden({}, true) and not Hidden({}, false))
        Check("\"never\" means never",
            not Hidden({ hideWhen = "never" }, true)
            and not Hidden({ hideWhen = "never" }, false))

        -- The second argument is "is this worth looking at", NOT "is it
        -- ready" - for an ability those are the same sentence and for a buff
        -- they are opposites. See Effects.Relevant.
        Check("Hiding what is not up to anything leaves what is",
            Hidden({ hideWhen = "cooling" }, false)
            and not Hidden({ hideWhen = "cooling" }, true))

        -- The inverse was removed after it emptied a bar twice. A profile
        -- that still carries the value must land on "hide nothing" - the
        -- outcome that gives the bar back rather than leaving it empty.
        Check("The value that was removed now hides nothing",
            not Hidden({ hideWhen = "ready" }, true)
            and not Hidden({ hideWhen = "ready" }, false))

        -- THE ONE THAT KEEPS A READING FAILURE FROM LOOKING LIKE A BUG.
        Check("A state the client will not name never hides anything",
            not Hidden({ hideWhen = "cooling" }, nil))

        Check("No settings at all hides nothing", not Hidden(nil, true))

        -- A PROFILE FROM BEFORE THE SETTING EXISTED. ns.DEFAULTS only reaches
        -- a profile being created, so the key is simply absent from every
        -- older one - and absent must read as "never", never as "hide it".
        Check("A profile that predates the setting hides nothing",
            not Hidden({ dimOnCooldown = true }, true)
            and not Hidden({ dimOnCooldown = true }, false))
        Check("And the default the page falls back to is 'never'",
            ns.EFFECT_DEFAULTS.hideWhen == "never"
            and ns.EFFECT_DEFAULTS.reflow == "off")

        -- A bar that ONLY hides still has to be ticked - the ticker is the
        -- only thing watching for the flip that puts the icon back.
        Check("A bar that only hides is still watched",
            ns.Effects.Wanted({ hideWhen = "cooling" }) and true or false)
        Check("A bar with nothing on is still not watched",
            not ns.Effects.Wanted({ hideWhen = "never" }))
    end

    -----------------------------------------------------------------------
    -- READY AND AFFORDABLE ARE TWO DIFFERENT THINGS
    --
    -- A cooldown that has come back while you are short of the resource is
    -- an icon telling you to press something that will not go off. Off by
    -- default: "the cooldown is back" is what people expect a cooldown
    -- display to mean, so the other reading has to be asked for.
    -----------------------------------------------------------------------
    do
        local Allowed = ns.Effects.GlowAllowed

        Check("No glow while it is still on cooldown",
            not Allowed({ readyGlow = true }, false, true))
        Check("No glow when the glow is switched off",
            not Allowed({ readyGlow = false }, true, true))
        Check("Ready and switched on lights it",
            Allowed({ readyGlow = true }, true, nil))

        local strict = { readyGlow = true, readyGlowUsableOnly = true }
        Check("Ready but unaffordable stays dark", not Allowed(strict, true, false))
        Check("Ready and affordable lights it", Allowed(strict, true, true))

        -- THE FALLBACK THIS WHOLE ADDON USES. A value the client withheld
        -- must behave like the feature switched off - an effect that
        -- disappears because something could not be READ is
        -- indistinguishable from a broken one.
        Check("A resource the client will not name still lights it",
            Allowed(strict, true, nil))
    end

    -----------------------------------------------------------------------
    -- CLOSING THE GAPS A HIDDEN CELL LEAVES
    --
    -- An off-by-one here does not raise. It puts the wrong icon in the wrong
    -- square and looks exactly like a working display - which is why the
    -- arithmetic is separate from the drawing and checked on its own.
    --
    -- Two ways to close, and they are different answers rather than a better
    -- and a worse: "all" repacks the lot, "line" closes each row within
    -- itself so a grid keeps its shape and "the second row is my defensives"
    -- stays true.
    -----------------------------------------------------------------------
    do
        local Compact = ns.Layout.Compact

        -- Off is the identity, so no caller needs a branch around it.
        local place, used = Compact({ [2] = true }, 4, nil, 4)
        Check("Switched off, every cell keeps its own slot",
            place[1] == 1 and place[2] == 2 and place[3] == 3 and used == 4)

        -- "all": everything shuffles down and the bar gets shorter.
        place, used = Compact({ [2] = true }, 4, "all")
        Check("Repacking moves everything after the gap down",
            place[1] == 1 and place[2] == nil and place[3] == 2
            and place[4] == 3)
        Check("Repacking shortens the bar", used == 3)

        place, used = Compact({ [1] = true, [2] = true }, 4, "all")
        Check("Two gaps at the front pull the rest to the front",
            place[3] == 1 and place[4] == 2 and used == 2)

        Check("Everything hidden leaves nothing to draw",
            select(2, Compact({ true, true, true }, 3, "all")) == 0)

        -- "line": a 3x2 grid, one gone from the FIRST row. The second row
        -- must not move up - that is the whole difference.
        local grid = { [2] = true }
        place, used = Compact(grid, 6, "line", 3)
        Check("A row closes up within itself",
            place[1] == 1 and place[2] == nil and place[3] == 2)
        Check("The row below keeps its place",
            place[4] == 4 and place[5] == 5 and place[6] == 6)
        Check("The box still covers the furthest row", used == 6)

        -- A gap in the LAST row shortens the box; a gap above it does not.
        place, used = Compact({ [5] = true }, 6, "line", 3)
        Check("A gap in the last row does shorten it",
            place[6] == 5 and used == 5)

        -- A whole row gone in the middle leaves its space empty rather than
        -- pulling the row below up into it - the price of keeping the grid,
        -- and it is the point of the mode rather than a defect.
        place, used = Compact({ [4] = true, [5] = true, [6] = true }, 9, "line", 3)
        Check("An empty middle row stays empty",
            place[7] == 7 and place[8] == 8 and used == 9)

        -- A line of one is every cell on its own line, which must not become
        -- a division by zero or a silent repack.
        place, used = Compact({ [1] = true }, 3, "line", 1)
        Check("A line of one still answers", place[2] == 2 and used == 3)

        Check("No cells at all is not an error",
            select(2, Compact({}, 0, "all")) == 0)
    end

    -----------------------------------------------------------------------
    -- THE SQUARES THAT RUN ROUND THE OUTLINE
    --
    -- Motion is caught by the corner of your eye in a way a steady colour is
    -- not, which is the whole job of a proc marker. The harness has no screen
    -- and does not need one: "where is dot 3 of 8 at this instant" is
    -- arithmetic, and arithmetic is exactly what goes wrong here - an
    -- off-by-one at a corner puts a dot inside the icon for a quarter of
    -- every lap.
    -----------------------------------------------------------------------
    do
        local At = ns.Effects.PerimeterPoint
        local W, H = 40, 20                      -- perimeter 120

        local function Same(progress, wantX, wantY)
            local x, y = At(progress, W, H)
            return math.abs(x - wantX) < 0.001 and math.abs(y - wantY) < 0.001
        end

        -- The four corners, walking clockwise from the top-left.
        Check("It starts in the top-left corner", Same(0, 0, H))
        Check("A third of the way round is the top-right", Same(40 / 120, W, H))
        Check("Half way round is the bottom-right", Same(60 / 120, W, 0))
        Check("Five sixths round is the bottom-left", Same(100 / 120, 0, 0))

        -- Midpoints of each side, because a corner can be right while the
        -- side between two corners runs the wrong way.
        Check("The top runs left to right", Same(20 / 120, 20, H))
        Check("The right side runs downwards", Same(50 / 120, W, 10))
        Check("The bottom runs right to left", Same(80 / 120, 20, 0))
        Check("The left side runs upwards", Same(110 / 120, 0, 10))

        -- A caller adds an offset per dot and must not have to think about
        -- the end of the lap.
        Check("Past the end is back at the start", Same(1, 0, H))
        -- A quarter of 120 is 30 along the top, and a whole lap further on is
        -- the same place.
        Check("A lap and a quarter is a quarter", Same(1.25, 30, H))
        Check("Backwards wraps too", Same(-0.5, W, 0))

        -- A cell that has not been laid out yet has no size, and dividing by
        -- its perimeter would be a divide by zero on the very first pass.
        Check("A rectangle with no size answers without dividing by zero",
            select(1, At(0.5, 0, 0)) == 0 and select(2, At(0.5, 0, 0)) == 0)
    end

    -----------------------------------------------------------------------
    -- THE AURA BINDS ITSELF
    --
    -- Owner: "das muss auch ohne mich gehen, die sachen sind doch alle im
    -- spiel." He is right about the second half and it does not follow from
    -- it: there is no call that says which buff an ability lights up for -
    -- EllesmereUI is fully on 12.1 and keeps exactly ONE such pairing, by
    -- hand. So it is watched instead, and the watching is what must not need
    -- a person.
    --
    -- A proc's glow rises with the buff and falls when it is spent, so the
    -- buff is in the aura list at SHOW and gone at HIDE. The flask, the food
    -- and the raid buffs are in both and cancel. What survives across
    -- several procs is the aura.
    -----------------------------------------------------------------------
    do
        local Narrow = ns.Auras.NarrowAura

        -- One proc never decides. Three things ended together and any of
        -- them could be the one.
        local cand, bound = Narrow(nil, { [10] = true, [20] = true }, 3)
        Check("One proc is a shortlist, not an answer", bound == nil)
        Check("Both of them are still standing", cand[10] == 1 and cand[20] == 1)

        -- The second proc drops the coincidence. Still not enough: alone is
        -- not the same as confirmed.
        cand, bound = Narrow(cand, { [10] = true }, 3)
        Check("What did not happen again falls out", cand[20] == nil)
        Check("Alone after two is still not confirmed", bound == nil)

        cand, bound = Narrow(cand, { [10] = true }, 3)
        Check("Alone and agreed three times is the aura", bound == 10)
        Check("The shortlist is dropped once it is decided", cand == nil)

        -- THE ONE THAT STOPS A WRONG BINDING. Three agreements while two ids
        -- are still standing does not say which - and a wrong auraID drives
        -- the caption and the timing of a real bar.
        local two = { [10] = true, [20] = true }
        local both = Narrow(Narrow(Narrow(nil, two, 3), two, 3), two, 3)
        Check("Three agreements on two ids still binds nothing",
            select(2, Narrow(both, two, 3)) == nil)

        -- A moment the client would not answer for - inside a dungeon - must
        -- not throw away what was learned outside it.
        local kept = Narrow({ [10] = 2 }, {}, 3)
        Check("A reading with nothing in it changes nothing",
            kept and kept[10] == 2)
        Check("So does no reading at all", Narrow({ [10] = 2 }, nil, 3)[10] == 2)

        -- Everything disagreed: the recorder starts again from what it just
        -- saw rather than sitting on an empty set for ever.
        local restarted = Narrow({ [10] = 2 }, { [30] = true }, 3)
        Check("A total disagreement starts over instead of dying",
            restarted[30] == 1 and restarted[10] == nil)
    end

    -----------------------------------------------------------------------
    -- A PREVIEW DRAWS WHAT THE THING IS
    --
    -- Owner, with a screenshot of the raid bar page: "die icons sind einfach
    -- zu gross in der vorschau." The page had copied the externals page's
    -- SLOT = 40 - a number that is exactly right THERE, because 40 is the
    -- externals panel's own default cell size, and 54% too big here, because
    -- the raid bar's button is 26.
    --
    -- So the rule is checked rather than the number: what the player set is
    -- what gets drawn, the lattice may only ever shrink to fit the page, and
    -- the floor that keeps a slot clickable may not push it back up past what
    -- was asked for.
    -----------------------------------------------------------------------
    do
        local Size = ns.UI.PreviewSize

        -- The raid bar at its defaults: 26, one row of twelve, on the 722 the
        -- page actually has. Nothing binds, so it draws what the bar draws.
        Check("A preview draws the size the bar is set to",
            Size(26, 1, 12, 722, 200, 2, 22) == 26,
            tostring(Size(26, 1, 12, 722, 200, 2, 22)))

        -- The externals page passes its own constant and must not move: this
        -- is the case its four existing checks pin.
        Check("A page that asks for 40 still gets 40",
            Size(40, 1, 6, 722, 200, 8, 22) == 40,
            tostring(Size(40, 1, 6, 722, 200, 8, 22)))

        -- Sixteen columns of 48 need 16*48 + 15*2 = 798 and there are 722, so
        -- it comes down to floor((722 - 30)/16) = 43.
        Check("A lattice too wide for the page shrinks",
            Size(48, 1, 16, 722, 200, 2, 22) == 43,
            tostring(Size(48, 1, 16, 722, 200, 2, 22)))

        -- The other axis, and it is the one the band cares about: four rows of
        -- 48 in a band 120 tall is (120 - 3*2)/4 = 28.5, so 28.
        Check("A lattice too tall for the band shrinks",
            Size(48, 4, 4, 722, 120, 2, 22) == 28,
            tostring(Size(48, 4, 4, 722, 120, 2, 22)))

        -- ...and at the band's real 200 it does NOT shrink, which is worth
        -- pinning too: (200 - 6)/4 = 48.5, so the four-row raid bar at maximum
        -- icon size still draws true.
        Check("Four rows at the band's real height still draw true",
            Size(48, 4, 4, 722, 200, 2, 22) == 48,
            tostring(Size(48, 4, 4, 722, 200, 2, 22)))

        Check("It never shrinks past being clickable",
            Size(48, 4, 12, 200, 60, 2, 22) >= 22,
            tostring(Size(48, 4, 12, 200, 60, 2, 22)))

        -- THE ONE THE OLD VERSION GOT WRONG IN THE OTHER DIRECTION. Somebody
        -- who sets 16 gets 16 drawn - small and true. A floor of 22 applied to
        -- a deliberate choice is the same lie as the 40, in miniature.
        Check("A player who asks for smaller than the floor gets what they asked for",
            Size(16, 1, 12, 722, 200, 2, 22) == 16,
            tostring(Size(16, 1, 12, 722, 200, 2, 22)))

        -- And it never grows: a page with room to spare does not get to make
        -- the preview a nicer size than the thing it is previewing.
        Check("A preview never grows past what was asked for",
            Size(26, 1, 2, 722, 200, 2, 22) == 26,
            tostring(Size(26, 1, 2, 722, 200, 2, 22)))

        -- AND THE PAGE ITSELF IS ASKED, not just the arithmetic under it. The
        -- fault was never in the sum: it was a page handing it a constant 40
        -- over a bar drawn at 26, and a check that only exercises UI.PreviewSize
        -- would have gone green through the whole mistake.
        local Geometry = ns.OptionsRaidBar and ns.OptionsRaidBar.PreviewGeometry
        if Geometry then
            local cfg = ns.RaidBar.Config()
            local keepSize, keepGap = cfg.size, cfg.gap

            cfg.size, cfg.gap = 26, 2
            local drawn, air = Geometry(750)
            Check("The raid bar preview draws the bar's own size", drawn == 26,
                tostring(drawn))
            Check("...with the bar's own air between two buttons", air == 2,
                tostring(air))

            cfg.size = 48
            Check("...and follows the icon size when it is changed",
                (Geometry(750)) == 48, tostring((Geometry(750))))

            cfg.size, cfg.gap = keepSize, keepGap
        end
    end

    -----------------------------------------------------------------------
    -- WHICH LINES OF A LIST ARE IN THE COLUMN
    --
    -- The spell picker held one frame per spell for the session. It builds
    -- what fits now and re-uses it as you scroll, and THIS is the arithmetic
    -- that decides which lines those are - so it is checked here rather than
    -- through the window: the harness answers GetHeight with a constant, so a
    -- check that went through the real column would be asking the stub.
    --
    -- The list is deliberately MIXED - headings are 26 and rows are 32 - which
    -- is the case a "divide by the row height" version gets wrong the moment
    -- a group boundary is on screen.
    -----------------------------------------------------------------------
    do
        local Range = ns.UI.VisibleRange

        local function Lines(heights)
            local items, y = {}, 0
            for _, height in ipairs(heights) do
                items[#items + 1] = { y = y, h = height }
                y = y + height
            end
            return items
        end

        -- 26, then eight rows of 32: 26, 58, 90, 122, 154, 186, 218, 250, 282
        local mixed = Lines({ 26, 32, 32, 32, 32, 32, 32, 32, 32 })

        local first, last = Range(mixed, 0, 100)
        Check("The top of a list starts at its first line", first == 1)
        Check("A 100 tall column holds a heading and three rows", last == 4,
            string.format("%d..%d", first, last))

        -- Offset 90 is exactly the bottom edge of the third line, so the
        -- third is GONE and the fourth is the first one drawn. The off-by-one
        -- here is a real one: `<=` rather than `<` is the difference between
        -- a line that has just left the column and one that is still in it.
        first, last = Range(mixed, 90, 100)
        Check("A line whose bottom edge is the top of the column is out",
            first == 4, tostring(first))
        -- The window ends at 190 and the seventh line starts at 186: four
        -- pixels of it are showing, and it is drawn.
        Check("A line four pixels into the column is in", last == 7,
            tostring(last))

        -- The one that decides whether a saving is real: the answer has to be
        -- a HANDFUL out of a long list, not a share of it.
        local long = {}
        do
            local y = 0
            for index = 1, 400 do
                long[index] = { y = y, h = 32 }
                y = y + 32
            end
        end
        first, last = Range(long, 0, 384)
        Check("Four hundred lines in a 384 column are twelve", last - first + 1 == 12,
            string.format("%d", last - first + 1))

        first, last = Range(long, 32 * 399, 384)
        Check("The end of a list is reachable", last == 400, tostring(last))

        -- THE THREE EMPTY ANSWERS, and all three have to be first > last
        -- rather than 1..1: a column with no height yet is the state every
        -- one of these frames is in before it is laid out, and drawing "the
        -- first line" then would put a spell nobody asked for on screen.
        first, last = Range({}, 0, 100)
        Check("An empty list draws nothing", first > last)

        first, last = Range(long, 0, 0)
        Check("A column with no height draws nothing", first > last)

        first, last = Range(long, 32 * 500, 384)
        Check("Scrolled past the end, nothing is drawn", first > last)

        -- Negative scroll is not a state the client produces, but the sum
        -- that produces it here is `y - height` and that one has been
        -- negative before.
        first, last = Range(mixed, -50, 100)
        Check("A scroll above the top starts at the top", first == 1)
    end

    -----------------------------------------------------------------------
    -- A HUNDRED SPELLS, A DOZEN FRAMES
    --
    -- The picker was the most expensive thing this addon builds. The check
    -- is not "is it smaller" - nothing here can weigh a frame - it is the
    -- CONTRACT that makes it smaller: the list knows every line, and only
    -- the ones in the column exist as frames.
    --
    -- It has to hold a catalogue up to the pane, because the desktop client
    -- has no Cooldown Manager and the real one comes back empty out here -
    -- which is exactly how "the picker costs 2.4 MB" went unmeasured for a
    -- version: the harness was building a list of nothing and reporting a
    -- number that was all the OTHER panes.
    -----------------------------------------------------------------------
    do
        local realCDM, realAuras = ns.CDM.Catalogue, ns.Auras.Catalogue

        local many = {}
        for index = 1, 200 do
            many[index] = {
                spellID = 900000 + index,
                name = string.format("Test spell %d", index),
                viewer = "essential",
                order = index,
                known = true,
            }
        end

        ns.CDM.Catalogue = function() return many end
        ns.Auras.Catalogue = function() return {} end

        local host = CreateFrame("Frame", nil, UIParent)
        host:Hide()

        local pane = ns.OptionsBars:BuildSpellPane(host, 380, {
            Used = function() return {} end,
            Assign = function() end,
        })
        pane.Fill()

        ns.CDM.Catalogue, ns.Auras.Catalogue = realCDM, realAuras

        -- 200 spells and the heading over them.
        Check("Every spell is in the list", pane.LineCount() == 201,
            tostring(pane.LineCount()))

        -- The harness's column answers 200 tall, so seven rows fit and one
        -- more is the slack below the fold. The number is not the point; the
        -- ORDER OF MAGNITUDE is, and 200 rows would sail past this.
        Check("Two hundred spells do not build two hundred rows",
            pane.RowCount() > 0 and pane.RowCount() <= 24,
            tostring(pane.RowCount()))
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
    --
    -- EVERY MODULE HAS AN ANSWER HERE, and that is the rule - not "everything
    -- is on". A module missing from this table is filled in as nil, which
    -- Modules:IsOn reads as ON, so a feature that was meant to arrive quietly
    -- would switch itself on for everybody with no line anywhere saying so.
    --
    -- WHICH answer is a per-module decision and it is written at the entry.
    -- The six that draw or record something default on, because for those an
    -- update that switched them off would be an update that broke somebody's
    -- screen. The raid bar and the invite tool default OFF: one puts a row of
    -- buttons on the screen and the other acts in your name at people who are
    -- not in the room, and neither should start because somebody updated an
    -- addon. The welcome window is what offers them - which is what
    -- Modules.GENERATION exists for, and it is checked below.
    for _, entry in ipairs(list) do
        Check("Module '" .. entry.key .. "' has a default",
            ns.DEFAULTS.modules
                and type(ns.DEFAULTS.modules[entry.key]) == "boolean",
            "missing means nil, and nil reads as ON")
    end

    Check("A module that acts on its own is off until it is asked for",
        ns.DEFAULTS.modules.raidbar == false
            and ns.DEFAULTS.modules.invites == false)

    -- AND THE OTHER SIX ARE STILL ON. Written out rather than "every other
    -- entry", because the list of features that may arrive switched on is a
    -- decision and not a default: the next module added has to be argued for
    -- in one of the two directions rather than inheriting whichever way this
    -- loop happened to be written.
    for _, key in ipairs({ "cooldowns", "cotanks", "reminders", "externals",
        "answers", "deaths" }) do
        Check("Module '" .. key .. "' still defaults to ON",
            ns.DEFAULTS.modules[key] == true)
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

    -- AND THEN THE PAIR WE ACTUALLY SHIP.
    --
    -- Everything above runs on a made-up list. The one that goes wrong in a
    -- release is the real one: a module is added with `since = 4` and the
    -- generation stays at 3, so every character is asked "have you seen
    -- generation 3" - yes - and the new module is never offered to anybody.
    -- Silent, and it looks exactly like a module nobody wanted.
    local highest = 0
    for _, entry in ipairs(Modules:All()) do
        highest = math.max(highest, entry.since or 1)
    end
    Check("The generation we ship covers every module in it",
        Modules.GENERATION >= highest,
        string.format("generation %d, newest module since %d",
            Modules.GENERATION, highest))

    -- The two sentences that say how many features there are do not type the
    -- number any more; this is the list they count.
    Check("The module count is the list's own length",
        Modules:Count() == #Modules:All())

    -- The memory tile on Diagnostics. The client answers in KB, and the whole
    -- point of the tile is that somebody can read it at a glance - "13312 KB"
    -- is the failure it exists to avoid.
    local Text = ns.Options.MemoryText
    Check("Memory under a megabyte reads in KB", Text(512) == "512 KB")
    Check("13312 KB reads as 13.0 MB", Text(13312) == "13.0 MB")
    Check("A megabyte exactly is already MB", Text(1024) == "1.0 MB")
    Check("Nothing to report is not an error", Text(nil) == "0 KB")
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

    ---------------------------------------------------------------------
    -- KEYS ON THE SLOTS
    --
    -- Owner, 2026-08-10: "das sollte standard sein, das haben fast alle
    -- addons". The binding presses into the SHOWN list, which is the same
    -- list the panel draws from - a key that hits the third slot while your
    -- eyes are on a different third slot is worse than no key.
    ---------------------------------------------------------------------
    Check("Every slot key has a name the game can show",
        X.BindingName(3) == "ZWOELFSTUFF_EXTERNAL_3", X.BindingName(3))
    Check("And a label under it",
        _G["BINDING_NAME_" .. X.BindingName(3)] ~= nil)
    Check("Eight of them", X.KEYS == 8, tostring(X.KEYS))

    -- The drawn list is never longer than what was picked, and it drops
    -- exactly what nobody present can cast.
    Check("What is shown is a subset of what is picked",
        #X.Shown() <= #X.Picked(), #X.Shown() .. " of " .. #X.Picked())

    -- A KEY PRESSED AT AN EMPTY PLACE MUST SAY SO, not throw and not go
    -- quiet. Alone, with nobody to ask, every slot is empty - so this is the
    -- press that happens most often while nothing is going on.
    Check("A key at a place with nothing in it is harmless",
        select(1, pcall(X.AskSlot, 99)) == true)

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

    -- THE NUMBERS THAT WERE LOOKED UP, GUARDED.
    --
    -- Owner asked for lust and a battle res; every id was read out of an
    -- installed, maintained addon rather than remembered, because a spell
    -- number recalled from memory has been wrong here twice. A test is the
    -- only thing that keeps a later edit from quietly putting a wrong one
    -- back - nothing else in this addon would notice: a bad id draws a
    -- question-mark icon and whispers somebody about a spell they do not have.
    --
    -- The CLASS is checked with the id, because that is what decides who gets
    -- whispered. A right id under the wrong class asks the wrong person.
    local researched = {
        { 2825,   "SHAMAN"      },   -- Bloodlust
        { 32182,  "SHAMAN"      },   -- Heroism
        { 80353,  "MAGE"        },   -- Time Warp
        { 264667, "HUNTER"      },   -- Primal Rage
        { 390386, "EVOKER"      },   -- Fury of the Aspects
        { 20484,  "DRUID"       },   -- Rebirth
        { 61999,  "DEATHKNIGHT" },   -- Raise Ally
        { 391054, "PALADIN"     },   -- Intercession
        { 20707,  "WARLOCK"     },   -- Soulstone
    }
    -- Asked of the TRANSLATION and of the offer list rather than of the
    -- table: what matters is that a player of that class ends up with that
    -- spell on their bar, and that it answers the slot the asker pressed. A
    -- test that walked `covers` itself would be the table written twice and
    -- would go on passing while the feature was broken.
    for _, want in ipairs(researched) do
        local offered = false
        for _, offer in ipairs(ns.Answers.Offers(want[2])) do
            if offer.spellID == want[1] then offered = true end
        end
        Check("A " .. want[2] .. " is offered " .. want[1], offered)
    end

    -- The five lusts are ONE question and the four battle resses are another,
    -- and the two are not the same question. Stated as the relationship
    -- rather than as "spell X sits in slot Y", which would only be the table
    -- copied out a second time.
    Check("Every lust answers the same slot", (function()
        for _, id in ipairs({ 32182, 80353, 264667, 390386 }) do
            if not X.SameSlot(id, 2825) then return false end
        end
        return true
    end)())
    Check("Every battle res answers the same slot", (function()
        for _, id in ipairs({ 61999, 391054, 20707 }) do
            if not X.SameSlot(id, 20484) then return false end
        end
        return true
    end)())
    Check("And lust is not a battle res", not X.SameSlot(2825, 20484))
    Check("Nor is an ordinary external either of them",
        not X.SameSlot(6940, 2825) and not X.SameSlot(6940, 20484))

    ---------------------------------------------------------------------
    -- ONE SLOT, SEVERAL SPELLS
    --
    -- Owner: "sprich das waere ein Lust command und Bres". The whole feature
    -- is a round trip between two clients that never agree about which spell
    -- "lust" is, so the round trip is what is checked.
    ---------------------------------------------------------------------
    local lust = X.Get(2825)
    Check("Lust is one slot, not five", lust ~= nil and lust.covers ~= nil)
    Check("It is called Lust rather than Bloodlust",
        X.Label(2825) == "Lust", tostring(X.Label(2825)))
    Check("Bres is one slot too", (X.Get(20484) or {}).covers ~= nil)
    Check("It is called Bres", X.Label(20484) == "Bres")

    -- An ordinary spell is untouched by either translation - that is what
    -- lets every other caller in the file stay as it was.
    Check("An ordinary spell is its own slot", X.SlotFor(6940) == 6940)

    -- THE ROUND TRIP. The asker's panel holds the slot; the mage answers with
    -- his own spell; the ACK coming back has to land on the slot again, or
    -- the asker's cell never goes quiet.
    Check("A mage's Time Warp lands back on the Lust slot",
        X.SlotFor(80353) == 2825)
    Check("A warlock's Soulstone lands back on the Bres slot",
        X.SlotFor(20707) == 20484)

    -- Two groups claiming one spell would make SlotFor answer at random,
    -- depending on which entry was written last.
    Check("No spell is covered by two slots", (function()
        local seen = {}
        for _, entry in ipairs(X.SPELLS) do
            for _, sub in ipairs(entry.covers or {}) do
                if seen[sub.spellID] then return false end
                seen[sub.spellID] = true
            end
        end
        return true
    end)())

    -- WHO A GROUPED SLOT WOULD ASK: anybody holding a version of it, not the
    -- class the slot happens to be stored under.
    Check("The Lust slot would ask the mage in the group", (function()
        local roster = {
            { name = "Me",   class = "WARRIOR", isPlayer = true },
            { name = "Mage", class = "MAGE" },
        }
        local target = X.Whom(lust, roster, nil)
        return target ~= nil and target.name == "Mage"
    end)())
    Check("A group with nobody who can lust has nobody to ask", (function()
        local roster = {
            { name = "Me",     class = "WARRIOR", isPlayer = true },
            { name = "Sneaky", class = "ROGUE" },
        }
        return X.Whom(lust, roster, nil) == nil
    end)())

    -- A CLASS TOKEN, not a class name. "Death Knight" and "DEATHKNIGHT" look
    -- equally right in a table and only one of them ever matches a roster
    -- entry, which compares against UnitClass's second return.
    Check("Every external names a real class token", (function()
        local tokens = {}
        for _, token in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE",
            "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK",
            "DRUID", "DEMONHUNTER", "EVOKER" }) do
            tokens[token] = true
        end
        for _, entry in ipairs(X.SPELLS) do
            if not tokens[entry.class] then return false end
        end
        return true
    end)())

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
    -- WHICH SPEC, which is the owner's priest bug
    --
    -- "wenn ich einen priester in der gruppe habe, werden fuer beide heiler
    -- specs die icons angezeigt." Pain Suppression is Discipline's and
    -- Guardian Spirit is Holy's, and a class check cannot tell them apart.
    --
    -- THE NUMBERS BELOW ARE THE GAME'S, not ours. The test asks
    -- Specs.Table() what a priest's specs actually are and builds its roster
    -- out of that, so it is checking the rule rather than agreeing with the
    -- assumption the rule is built on.
    ---------------------------------------------------------------------
    local S = ns.Specs

    Check("Unknown spec keeps the icon", S and X.SpecFits({ spec = nil }, 42))
    Check("A matching spec keeps it", S and X.SpecFits({ spec = 42 }, 42))
    Check("A different spec loses it", S and not X.SpecFits({ spec = 43 }, 42))
    Check("No restriction keeps everybody",
        S and X.SpecFits({ spec = 43 }, nil))

    -- The role guard, on a table we control: an index that points at the
    -- wrong KIND of spec must produce nothing rather than a wrong filter.
    local FAKE = { PRIEST = {
        [1] = { id = 111, name = "One",   role = "HEALER" },
        [2] = { id = 222, name = "Two",   role = "HEALER" },
        [3] = { id = 333, name = "Three", role = "DAMAGER" },
    } }
    Check("A spec index resolves to the game's id",
        S and S.Resolve(FAKE, "PRIEST", 2, "HEALER") == 222)
    Check("An index whose role is wrong resolves to nothing",
        S and S.Resolve(FAKE, "PRIEST", 3, "HEALER") == nil)
    Check("An index past the end resolves to nothing",
        S and S.Resolve(FAKE, "PRIEST", 9, "HEALER") == nil)
    Check("A class the game does not know resolves to nothing",
        S and S.Resolve(FAKE, "TINKER", 1, "HEALER") == nil)

    -- The throttle. Pure, with its own clock, because the alternative is a
    -- test that waits thirty seconds.
    Check("A fresh guid may be asked about", S and S.MayAsk(100, nil, nil))
    Check("Not twice within the gap", S and not S.MayAsk(100, 99.5, nil))
    Check("And not again straight after a failure",
        S and not S.MayAsk(100, nil, 90))
    Check("But it is worth another try later",
        S and S.MayAsk(200, nil, 100))

    ---------------------------------------------------------------------
    -- AGAINST THE REAL TABLE. In game this is the check that matters: every
    -- index the catalogue claims has to point at a spec of the role it says,
    -- on THIS client. It cannot catch two specs of one class with the same
    -- role swapped - /zs specs prints the names for that - but it does catch
    -- the whole family of "the order moved".
    ---------------------------------------------------------------------
    local list = S and S.Table() or {}
    Check("The game answered about specialisations", next(list) ~= nil)

    if next(list) then
        local bad
        for _, entry in ipairs(X.SpecRestrictions()) do
            if not S.Resolve(list, entry.class, entry.index, entry.role) then
                bad = string.format("%s %s %d", tostring(entry.name),
                    entry.class, entry.index)
            end
        end
        Check("Every spec the catalogue names is the role it says",
            bad == nil, bad)

        -- TWO LISTS, ONE WORD, TWO MEANINGS is how a drag rule rejected
        -- every drop in silence three days ago. Taunts.SPELLS carries a spec
        -- ID under `spec`; the externals carry an INDEX under `specIndex`.
        -- Neither list may grow the other's field.
        local crossed
        for _, entry in ipairs(X.SPELLS) do
            if entry.spec then crossed = "an external carries `spec`" end
        end
        for _, entry in ipairs(ns.Taunts.SPELLS) do
            if entry.specIndex then crossed = "a taunt carries `specIndex`" end
        end
        Check("The two spell lists do not swap each other's spec field",
            crossed == nil, crossed)

        -- AND THE ID THAT WAS ALREADY THERE, checked at last. Taunts has
        -- carried spec = 250 for Death Grip since the day it was written, on
        -- the word of another addon's table. The game can settle it now: it
        -- has to be a real specialisation OF THAT CLASS.
        --
        -- ONLY AGAINST A CLIENT. The desk harness invents its spec ids on
        -- purpose - baking the real ones into a stub would turn this into the
        -- assumption agreeing with itself, which is not a check.
        if __FAKE_SPECS then
            Skip("The taunt list's spec ids are real",
                "the harness invents them - a client has to answer this")
        else
            local wrong
            for _, entry in ipairs(ns.Taunts.SPELLS) do
                if entry.spec then
                    local found
                    for _, spec in pairs(list[entry.class] or {}) do
                        if spec.id == entry.spec then found = true end
                    end
                    if not found then
                        wrong = string.format("%s has no spec %d",
                            entry.class, entry.spec)
                    end
                end
            end
            Check("Every spec id the taunt list names belongs to its class",
                wrong == nil, wrong)
        end

        -- THE BUG ITSELF, end to end. Two priest slots, one priest, and the
        -- panel must offer exactly the one he can actually cast.
        local priest = list.PRIEST
        local disc = priest and priest[1] and priest[1].id
        local holy = priest and priest[2] and priest[2].id
        if disc and holy and disc ~= holy then
            local WITH_DISC = {
                { name = "Zwoelf", class = "DEATHKNIGHT", isPlayer = true },
                { name = "Prister", class = "PRIEST", role = "HEALER",
                  spec = disc },
            }
            Check("A discipline priest is offered Pain Suppression",
                #X.Candidates(X.Get(33206), WITH_DISC) == 1)
            Check("And is NOT offered Guardian Spirit",
                #X.Candidates(X.Get(47788), WITH_DISC) == 0)

            local UNREAD = {
                { name = "Zwoelf", class = "DEATHKNIGHT", isPlayer = true },
                { name = "Prister", class = "PRIEST", role = "HEALER" },
            }
            Check("A priest nobody has read yet is offered both",
                #X.Candidates(X.Get(33206), UNREAD) == 1
                and #X.Candidates(X.Get(47788), UNREAD) == 1)
        end
    end

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

    ---------------------------------------------------------------------
    -- A YES OR NO THAT CANNOT THROW
    --
    -- 12.0 hands back SECRET booleans from some unit queries, and testing one
    -- RAISES. It took the co-tank panel and Edit Mode down on somebody else's
    -- machine while working perfectly here, because WHICH values are withheld
    -- depends on where you are standing.
    ---------------------------------------------------------------------
    Check("A plain true is true", ns.Truth(true, false) == true)
    Check("A plain false is false", ns.Truth(false, true) == false)
    Check("Nothing at all takes the fallback", ns.Truth(nil, true) == true)
    Check("And the fallback is used as given",
        ns.Truth(nil, false) == false)

    ---------------------------------------------------------------------
    -- THE NAME A MACRO CAN ADDRESS
    --
    -- `/cast [@Akui]` reaches nobody when Akui is on another realm, and the
    -- click does nothing at all - no target, no cast, no error. Which is
    -- exactly what the first live test of this looked like.
    ---------------------------------------------------------------------
    local mate
    for _, member in ipairs(ns.Roster()) do
        if not member.isPlayer then mate = member end
    end
    if mate then
        Check("Everybody in the roster has a name a macro can address",
            type(mate.fullName) == "string" and #mate.fullName > 0,
            tostring(mate.fullName))
    else
        Skip("Whether a group-mate keeps its realm", "you are on your own")
    end

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
    -- A GROUPED SLOT REACHES EVERY CLASS THAT HAS A VERSION OF IT
    --
    -- Owner: "und answering muesste das dann fuer jede klasse entsprechend
    -- anders wiedergeben". The request side collapses five spells into one
    -- slot; this side has to expand it again, per class. A mage had NOTHING
    -- on his answer bar before lust existed, so this is also the check that
    -- the expansion happens at all.
    ---------------------------------------------------------------------
    local function Offered(class, spellID, chosen, known)
        for _, offer in ipairs(A.Offers(class, chosen, known)) do
            if offer.spellID == spellID then return true end
        end
        return false
    end

    Check("A mage is offered Time Warp", Offered("MAGE", 80353))
    Check("A hunter is offered Primal Rage", Offered("HUNTER", 264667))
    Check("An evoker is offered Fury of the Aspects", Offered("EVOKER", 390386))
    Check("A warlock is offered Soulstone", Offered("WARLOCK", 20707))
    Check("A death knight is offered Raise Ally", Offered("DEATHKNIGHT", 61999))

    -- Both spellings reach the shaman, and the spellbook decides which one
    -- survives - the same filter that keeps a holy priest from being offered
    -- Pain Suppression. Faction is not something this addon should guess at.
    Check("A shaman is offered both lusts",
        Offered("SHAMAN", 2825) and Offered("SHAMAN", 32182))
    Check("And the spellbook drops the one he has not got",
        Offered("SHAMAN", 2825, nil, function(id) return id ~= 32182 end)
        and not Offered("SHAMAN", 32182, nil,
            function(id) return id ~= 32182 end))

    -- A mage is not handed the shaman's spelling, which is what a careless
    -- expansion - offering every covered spell to everybody - would do.
    Check("A mage is not offered Bloodlust", not Offered("MAGE", 2825))
    Check("A rogue is still offered nothing", #A.Offers("ROGUE") == 0)

    -- OFF AND BACK ON, through the real setter.
    --
    -- Owner, 2026-08-10: "wenn ich den button auf aus schalte [...] kann ich
    -- ihn nicht mehr anschalten." It was written `on and nil or false`, and
    -- that NEVER yields nil - `true and nil` is nil, nil is false, so `or
    -- false` takes over whichever way the switch went. Stored false either
    -- way; off exactly once and never back.
    --
    -- Through SetOffering rather than by writing the table, because the table
    -- was never the part that was broken.
    local keptOffers = A.Config().offers
    A.Config().offers = {}
    Check("A spell nobody has touched is offered", A.Offering(6940))
    A.SetOffering(6940, false)
    Check("Switching it off sticks", A.Offering(6940) == false)
    A.SetOffering(6940, true)
    Check("AND IT CAN BE SWITCHED BACK ON", A.Offering(6940) == true)
    A.Config().offers = keptOffers

    ---------------------------------------------------------------------
    -- Who might ask
    ---------------------------------------------------------------------
    local ROSTER = {
        { name = "Heiler",  class = "PALADIN", role = "HEALER", isPlayer = true },
        { name = "Zwoelf",  class = "DEATHKNIGHT", role = "TANK" },
        { name = "Zweit",   class = "WARRIOR", role = "TANK" },
        { name = "Schaden", class = "MAGE",    role = "DAMAGER" },
    }
    local TANKS = { who = A.WHO_TANKS, rows = 3, rowNames = {} }
    local askers = A.Askers(ROSTER, TANKS)
    Check("Both tanks could ask", #askers == 2, tostring(#askers))
    Check("You are never one of them", (function()
        for _, member in ipairs(askers) do
            if member.isPlayer then return false end
        end
        return true
    end)())
    Check("Nobody tanking means no cells at all", #A.Askers({}, TANKS) == 0)

    -- THE OTHER TWO ANSWERS TO "WHO".
    --
    -- Owner, 2026-08-10: "man kann keine spieler auswaehlen". The automatic
    -- one is right until the group never set its roles, and then it is an
    -- empty bar that explains nothing.
    Check("Everybody means everybody but you",
        #A.Askers(ROSTER, { who = A.WHO_GROUP, rows = 6 }) == 3,
        tostring(#A.Askers(ROSTER, { who = A.WHO_GROUP, rows = 6 })))

    Check("The row count is a ceiling",
        #A.Askers(ROSTER, { who = A.WHO_GROUP, rows = 2 }) == 2)

    local picked = A.Askers(ROSTER, { who = A.WHO_CHOSEN, rows = 3,
        rowNames = { "Schaden", "Zwoelf" } })
    Check("Picked people come in the order they were picked",
        #picked == 2 and picked[1].name == "Schaden"
            and picked[2].name == "Zwoelf",
        #picked > 0 and picked[1].name or "none")

    Check("Naming somebody who left leaves no row",
        #A.Askers(ROSTER, { who = A.WHO_CHOSEN, rows = 3,
            rowNames = { "Weg" } }) == 0)

    -- Two rows aimed at one person light up together and answer nothing
    -- extra, so it is one row.
    Check("Naming the same person twice is ONE row",
        #A.Askers(ROSTER, { who = A.WHO_CHOSEN, rows = 3,
            rowNames = { "Zwoelf", "Zwoelf" } }) == 1)

    Check("You cannot pick yourself",
        #A.Askers(ROSTER, { who = A.WHO_CHOSEN, rows = 3,
            rowNames = { "Heiler" } }) == 0)

    ---------------------------------------------------------------------
    -- ONLY WHAT YOU ACTUALLY HAVE
    --
    -- A class list is not a spellbook: Pain Suppression is on the priest list
    -- and a holy priest cannot cast it.
    ---------------------------------------------------------------------
    local full = A.Offers("PRIEST")
    local half = A.Offers("PRIEST", nil, function(id) return id ~= 33206 end)
    Check("A spell you do not have is not offered", #half == #full - 1,
        #half .. " of " .. #full)
    Check("And it says how many it took out", A.hidden == 1,
        tostring(A.hidden))

    -- THE FILTER MUST NOT BE ABLE TO EMPTY THE BAR. The spellbook is not
    -- readable for a moment at every login and every talent swap, and an
    -- empty bar for a paladin is a worse wrong answer than one extra cell.
    local none = A.Offers("PALADIN", nil, function() return false end)
    Check("A filter that removes EVERYTHING is refused", #none == #paladin,
        tostring(#none))

    ---------------------------------------------------------------------
    -- THE MACRO - the one string the whole feature is
    --
    -- Three separate reasons for a click that cast nothing have now been
    -- found by reading code, and every one of them is a wrong string here.
    -- None of them said anything on screen.
    ---------------------------------------------------------------------
    local tank = { name = "Akui", fullName = "Akui-Gilneas", unit = "party2" }

    Check("An external is cast on whoever asked",
        A.Macro(C.EXTERNAL, "Lay on Hands", tank)
            == "/cast [@Akui-Gilneas] Lay on Hands",
        tostring(A.Macro(C.EXTERNAL, "Lay on Hands", tank)))

    -- A TAUNT GOES ON WHAT HE IS FIGHTING. Not on him - that is a taunt on a
    -- friendly player, which does nothing and says nothing - and not on your
    -- own target either, which in a pull with adds is a different creature.
    -- Owner: "bei spott müsste das target von akui anvisiert werden".
    Check("A taunt is cast on the ASKER'S target",
        A.Macro(C.TAUNT, "Dark Command", tank)
            == "/cast [@party2target,harm][] Dark Command",
        tostring(A.Macro(C.TAUNT, "Dark Command", tank)))

    Check("And it never names the tank himself",
        A.Macro(C.TAUNT, "Dark Command", tank):find("Akui") == nil)

    -- The empty clause: if what he is on cannot be taunted, your own target
    -- is used rather than the press doing nothing at all.
    Check("A taunt falls back to your own target",
        A.Macro(C.TAUNT, "Dark Command", tank):find("[]", 1, true) ~= nil)

    -- Without a token there is no way to say "his target" at all.
    Check("With no unit to reach him by, it is your own target",
        A.Macro(C.TAUNT, "Dark Command", { name = "Akui" })
            == "/cast Dark Command")

    Check("The realm travels with the name",
        A.Macro(C.EXTERNAL, "Ironbark", tank):find("Akui-Gilneas", 1, true)
            ~= nil)

    Check("Taking the target as well is a second line",
        A.Macro(C.EXTERNAL, "Ironbark", tank, true)
            == "/target Akui-Gilneas\n/cast [@Akui-Gilneas] Ironbark")

    -- And with the switch on it takes HIS target, not him: after a swap you
    -- are the one holding that creature, so being on it is the point.
    Check("With the switch on, a taunt takes what he is fighting",
        A.Macro(C.TAUNT, "Taunt", tank, true)
            == "/target party2target\n/cast [@party2target,harm][] Taunt",
        tostring(A.Macro(C.TAUNT, "Taunt", tank, true)))

    -- A stand-in cell must cast NOTHING: there is nobody called "Tank".
    Check("The stand-in cell gets no macro at all",
        A.Macro(C.EXTERNAL, "Taunt", { name = "Tank", preview = true })
            == nil)

    -- "Spell 633" is a fine thing to draw and a catastrophic thing to cast.
    Check("A spell the client cannot name gets no macro",
        A.Macro(C.EXTERNAL, nil, tank) == nil)
    Check("Nor an empty one", A.Macro(C.EXTERNAL, "", tank) == nil)

    ---------------------------------------------------------------------
    -- THE KEY IN THE CORNER
    ---------------------------------------------------------------------
    Check("Each cell has its own binding",
        A.BindingName(2) == "CLICK ZwoelfStuffAnswer2:LeftButton",
        A.BindingName(2))
    Check("And the game knows what to call it",
        _G["BINDING_NAME_" .. A.BindingName(2)] ~= nil)
    Check("SHIFT-F1 fits in a corner", A.ShortKey("SHIFT-F1") == "sF1",
        tostring(A.ShortKey("SHIFT-F1")))
    Check("So does a mouse button", A.ShortKey("BUTTON4") == "M4",
        tostring(A.ShortKey("BUTTON4")))
    Check("No key is no text", A.ShortKey(nil) == nil)
    Check("One shortener, read by both panels",
        A.ShortKey == ns.ShortKey and ns.Externals.Key ~= nil)
    Check("Eight cells can carry one", A.KEYS == 8, tostring(A.KEYS))

    -- THE KEY YOU PRESS, AS THE GAME NAMES IT. A modifier held down is a
    -- prefix; a modifier pressed ALONE is half a binding, and taking it as a
    -- whole one would make every combination impossible to enter - the shift
    -- always lands first.
    Check("A plain key is itself", ns.UI.Chord("F9") == "F9")
    Check("A modifier on its own is not a key", ns.UI.Chord("LSHIFT") == nil)
    Check("Nor is nothing at all", ns.UI.Chord(nil) == nil)

    ---------------------------------------------------------------------
    -- SETTING A KEY IS A MODE, NOT A LIST
    --
    -- Owner, 2026-08-10, having been handed eight rows: "du machst da einen
    -- keybind button, dann grauen die buttons aus und du kannst auf den
    -- button klicken und einen key belegen." A key belongs to a place on the
    -- screen, and the screen is right there.
    ---------------------------------------------------------------------
    Check("There is a key mode", ns.Keys ~= nil)
    if ns.Keys then
        local binding = ns.Externals.BindingName(1)
        local kept = ns.Keys.Current(binding)
        ns.Keys.Clear(binding)

        Check("A key can be bound to a place", ns.Keys.Bind(binding, "F9")
            and ns.Keys.Current(binding) == "F9",
            tostring(ns.Keys.Current(binding)))

        -- One key, one command. Announced when it is taken from something
        -- else, never left on both.
        SetBinding("F9", A.BindingName(1))
        ns.Keys.Bind(binding, "F9")
        Check("One key answers to one thing", ns.Keys.Current(A.BindingName(1))
            == nil and ns.Keys.Current(binding) == "F9")

        ns.Keys.Clear(binding)
        Check("And it can be taken off again",
            ns.Keys.Current(binding) == nil)

        -- THERE IS A WAY OUT THAT YOU CAN SEE. Owner, 2026-08-10: "man kommt
        -- nicht mehr aus dem modus." Escape was handled on the SQUARE, and a
        -- square only listens while it is waiting for a key - so standing in
        -- the mode without having clicked one, nothing was listening at all.
        ns.Keys:SetActive(true)
        Check("The key mode opens", ns.Keys.active)
        Check("And its window is one the game closes on Escape", (function()
            for _, name in ipairs(UISpecialFrames or {}) do
                if name == "ZwoelfStuffKeysBanner" then return true end
            end
            return false
        end)())
        ns.Keys:SetActive(false)
        Check("And it closes again", ns.Keys.active == false)

        if kept then ns.Keys.Bind(binding, kept) end
    end

    ---------------------------------------------------------------------
    -- THE QUICK MENU ON THE BAR
    --
    -- Owner, 2026-08-10: "kann man das als button an die answer bar hauen,
    -- damit man das dort schnell einstellen kann?" - and the reason is WHEN
    -- this decision happens: the group forms, and the options window is on a
    -- different part of the screen from the bar you are looking at.
    ---------------------------------------------------------------------
    local keptWho, keptRows = A.Config().who, A.Config().rowNames
    local keptCount = A.Config().rows
    A.Config().rowNames = {}

    A.SetWho(A.WHO_GROUP)
    Check("The menu switches the mode", A.Config().who == A.WHO_GROUP)

    Check("Nobody is picked to begin with", A.Picked("Zwoelf") == false)
    A.TogglePicked("Zwoelf")
    Check("Picking somebody picks them", A.Picked("Zwoelf"))
    -- Picking a person and then not being in the mode that reads the list
    -- would be a click that did nothing.
    Check("And puts you in the mode that reads it",
        A.Config().who == A.WHO_CHOSEN)
    A.TogglePicked("Zwoelf")
    Check("Clicking again takes them off", A.Picked("Zwoelf") == false)

    -- More names than rows: the extra one is REFUSED out loud rather than
    -- dropped, which would read as a click that never registered.
    A.Config().rows = 1
    A.TogglePicked("Einer")
    A.TogglePicked("Zweiter")
    Check("A name with no row left is not silently swallowed",
        A.Picked("Einer") and A.Picked("Zweiter") == false)

    local items = A.MenuItems()
    Check("The menu offers the modes and the people", #items >= 3,
        tostring(#items))

    A.Config().rowNames, A.Config().who = keptRows, keptWho
    A.Config().rows = keptCount

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
    ---------------------------------------------------------------------
    -- EDIT MODE GIVES BACK WHAT IT TOOK
    --
    -- Owner, 2026-08-10, in one breath: "wenn ich aus dem addon in den edit
    -- mode gehe und den edit mode verlasse, sollte das addon wieder aufgehen"
    -- and "wenn ich nur rechtsklick auf dem minimap icon mache [...] kein
    -- addon öffnen". Two sentences, one rule - a window it hid, it puts back;
    -- a window that was never open stays shut. Which makes the minimap and
    -- /zs unlock need no case of their own, and that is the point.
    ---------------------------------------------------------------------
    local wasOpen = ns.Options.frame and ns.Options.frame:IsShown()
    if ns.Options.frame then ns.Options.frame:Hide() end

    ns.EditMode:SetUnlocked(true)
    Check("Coming in from the minimap, there is nothing to hand back",
        ns.EditMode.cameFromWindow == false)
    ns.EditMode:SetUnlocked(false)
    Check("And leaving opens nothing",
        not (ns.Options.frame and ns.Options.frame:IsShown()))

    if wasOpen and ns.Options.frame then ns.Options.frame:Show() end

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

        -- EVERY FIELD A ROW OWES, and the reason this is a loop rather than
        -- four lines about one panel: a surface is a ROW in PANEL_MOVERS now,
        -- so adding a sixth is adding a row - and a row missing one field
        -- fails in its own quiet way. No label draws a nameless box; no
        -- origin means the coordinates read 0,0 for ever; no config means the
        -- padlock cannot find `pinned` and every drag goes through.
        Check("The " .. name .. " row says what to call it",
            type(mover.spec.label) == "string" and mover.spec.label ~= "",
            tostring(mover.spec and mover.spec.label))
        Check("The " .. name .. " row can say where it is",
            type(mover.spec.origin) == "function"
            and select(1, mover.spec.origin()) ~= nil)
        Check("The " .. name .. " row can find its own settings",
            type(mover.spec.config) == "function"
            and mover.spec.config() ~= nil)

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
        --
        -- The same block runs over the REMINDER movers below, because "it has
        -- a padlock" and "the padlock does something" are two questions and
        -- the reminders had neither answer for five days.
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

    ---------------------------------------------------------------------
    -- AND THE REMINDERS, WHICH ARE MOVERS TOO
    --
    -- Owner, with a screenshot of one: "mein reminder hat kein zahnrad oder
    -- lock". He had said the same sentence about the externals mover five
    -- days earlier - and the answer then went into the PANEL builder, which
    -- the reminders do not use. Nothing could see the difference, because
    -- the reminder movers were a local nothing could reach.
    ---------------------------------------------------------------------
    local reminders = ns.EditMode.ReminderMovers
        and ns.EditMode:ReminderMovers() or {}

    -- SAY SO WHEN THERE IS NOTHING TO LOOK AT. A loop over an empty list is
    -- a suite that reports green about nothing, and that is exactly how this
    -- gap survived: nothing could reach the reminder movers, so nothing said
    -- they were missing anything.
    if #reminders == 0 then
        Skip("Whether the reminder movers carry a cog and a padlock",
            "no reminder is placed, so no mover was built")
    else
        for index, mover in ipairs(reminders) do
            local who = "reminder " .. index
            Check("The " .. who .. " mover has a cog", mover.cog ~= nil)
            Check("The " .. who .. " mover has a padlock", mover.lock ~= nil)
            Check("And it knows how to draw the padlock",
                type(mover.RefreshLock) == "function")
            Check("And it carries what its cog needs",
                mover.spec ~= nil and mover.spec.page ~= nil
                and type(mover.spec.apply) == "function"
                and type(mover.spec.config) == "function")

            -- THE PADLOCK HAS TO DO SOMETHING. It is not enough that it is
            -- drawn: the reminder drag never read `pinned` at all until it
            -- was given one, so a padlock there would have been a picture.
            local cfg = mover.spec and mover.spec.config()
            if cfg then
                local was = cfg.pinned
                local start = mover:GetScript("OnDragStart")

                cfg.pinned = true
                mover.grab = nil
                if start then start(mover) end
                Check("A pinned " .. who .. " refuses to be dragged",
                    mover.grab == nil)

                cfg.pinned = false
                mover.grab = nil
                if start then start(mover) end
                Check("An unpinned " .. who .. " takes the drag",
                    mover.grab ~= nil)

                mover.grab = nil
                cfg.pinned = was
                mover:RefreshLock()
            end
        end
    end

    if not any then
        Skip("Whether the panel movers carry a cog and a padlock",
            "edit mode has not been opened this session")
    end
end

---------------------------------------------------------------------------
-- The language
--
-- WHAT CAN ACTUALLY GO WRONG HERE, because it is not what it looks like. A
-- missing translation is harmless by design - the key IS the English string,
-- so it comes back as itself. The three things that are NOT harmless:
--
--   a key that is in a translation and not in enUS   a word nothing asks for.
--                                                    It is a typo, and it
--                                                    shows as English forever
--                                                    while looking translated
--                                                    in the file.
--   a translation that loses a placeholder            "%d features" becoming
--                                                    "Funktionen" drops the
--                                                    number silently, or
--                                                    throws inside format.
--   a lookup at FILE SCOPE                            answered in English
--                                                    before the profile is
--                                                    open, then frozen for
--                                                    the session.
---------------------------------------------------------------------------
local function TestLocale()
    local Locale = ns.Locale
    local L = ns.L

    Check("There is a language engine", Locale ~= nil and L ~= nil)
    if not Locale then return end

    ---------------------------------------------------------------------
    -- Which language, given what
    ---------------------------------------------------------------------
    Check("A chosen language wins over the client",
        Locale.Resolve("frFR", "deDE") == "frFR")
    Check("auto follows the client",
        Locale.Resolve("auto", "deDE") == "deDE")
    Check("Nothing chosen follows the client",
        Locale.Resolve(nil, "ruRU") == "ruRU")
    -- The British client is the American strings, and nobody ships a separate
    -- enGB. Without this line every British player gets the raw keys back -
    -- which happens to be English, so it works by luck rather than by rule.
    Check("enGB is enUS", Locale.Resolve("auto", "enGB") == "enUS")
    Check("A language we do not ship falls back to English",
        Locale.Resolve("xxXX", "xxXX") == "enUS")
    Check("No client at all falls back to English",
        Locale.Resolve(nil, nil) == "enUS")

    ---------------------------------------------------------------------
    -- The tables
    ---------------------------------------------------------------------
    local master = Locale.TABLES.enUS
    Check("There is a master list", type(master) == "table")

    local masterCount = 0
    for _ in pairs(master or {}) do masterCount = masterCount + 1 end
    Check("The master list has something in it", masterCount > 50,
        tostring(masterCount) .. " strings")

    for _, entry in ipairs(Locale.LANGUAGES) do
        Check("Language " .. entry.code .. " has a table",
            type(Locale.TABLES[entry.code]) == "table")
        -- IN ITS OWN LANGUAGE. Somebody looking for their language in a list
        -- is looking for the word they use for it, which may not be a word
        -- they would recognise in English.
        Check("Language " .. entry.code .. " names itself",
            type(entry.native) == "string" and entry.native ~= "")
    end

    -- A KEY THAT IS NOT IN THE MASTER. See the header: it is a typo that
    -- cannot be seen, because the screen shows English and the file shows a
    -- translation.
    local stray, strayIn
    for _, entry in ipairs(Locale.LANGUAGES) do
        if entry.code ~= "enUS" then
            for key in pairs(Locale.TABLES[entry.code] or {}) do
                if master[key] == nil then
                    stray, strayIn = key, entry.code
                end
            end
        end
    end
    Check("Every translated key is one the addon asks for", stray == nil,
        stray and (strayIn .. ": " .. stray) or nil)

    -- PLACEHOLDERS SURVIVE TRANSLATION. %d and %s carry the numbers, and a
    -- translation that drops one prints a sentence with the fact missing -
    -- or throws inside string.format, which takes the page down.
    local function Marks(text)
        local count = 0
        for _ in tostring(text):gmatch("%%[%a]") do count = count + 1 end
        return count
    end

    local lost, lostIn
    for _, entry in ipairs(Locale.LANGUAGES) do
        for key, value in pairs(Locale.TABLES[entry.code] or {}) do
            if type(value) == "string" and Marks(key) ~= Marks(value) then
                lost, lostIn = key, entry.code
            end
        end
    end
    Check("No translation loses a placeholder", lost == nil,
        lost and (lostIn .. ": " .. lost) or nil)

    ---------------------------------------------------------------------
    -- The lookup
    ---------------------------------------------------------------------
    local was = ns.db and ns.db.language
    local restore = Locale.active

    Locale:Use("enUS")
    Check("English answers with the key itself", L["Ready check"] == "Ready check")
    Check("A string nobody has translated answers with itself",
        L["a sentence that is in no table anywhere"]
            == "a sentence that is in no table anywhere")

    Locale:Use("deDE")
    Check("A translated string comes back translated",
        L["Settings"] == "Einstellungen")
    Check("An untranslated one still answers in English",
        L["a sentence that is in no table anywhere"]
            == "a sentence that is in no table anywhere")

    -- The formatting door. A translation with a broken placeholder must not
    -- take the caller down with it - see the pcall in Locale.lua.
    Check("A formatted string fills in", L("%d of %d answered", 3, 5)
        == "3 von 5 haben geantwortet")
    Check("A formatted string with no arguments is the string",
        L("Settings") == "Einstellungen")

    Locale:Use(restore)
    if ns.db then ns.db.language = was end

    -- READ-ONLY. A translation assigned at runtime would put one language's
    -- word into every later session of another one, and it would be found
    -- weeks later.
    Check("The table refuses to be written to",
        not pcall(function() ns.L["Ready check"] = "nope" end))

    ---------------------------------------------------------------------
    -- Coverage, which the Settings list and /zs loca both print
    ---------------------------------------------------------------------
    local done, total = Locale.Coverage("enUS")
    Check("English is complete by definition", done == total and total > 0)

    local germanDone, germanTotal = Locale.Coverage("deDE")
    -- The file says German is finished. Held to it here, because "complete"
    -- in a comment is a claim and this is the same claim as a number.
    Check("German is complete", germanDone == germanTotal,
        string.format("%d of %d", germanDone, germanTotal))

    for _, entry in ipairs(Locale.LANGUAGES) do
        local hit, all = Locale.Coverage(entry.code)
        Check("Coverage for " .. entry.code .. " is a real fraction",
            hit >= 0 and hit <= all and all == masterCount)
    end

    Check("What is missing is listed",
        #Locale.Missing("koKR") == masterCount - select(1, Locale.Coverage("koKR")))

    ---------------------------------------------------------------------
    -- The window's own strings resolve
    --
    -- Every page title and every module name goes through L when it is drawn.
    -- A title that is not a string would come back as a table address on a
    -- button, which is the sort of thing that only shows up in a screenshot.
    ---------------------------------------------------------------------
    local titles = true
    for _, page in ipairs(ns.Options.PAGES) do
        if type(L[page.title]) ~= "string" or L[page.title] == "" then
            titles = false
        end
    end
    Check("Every page title resolves to a string", titles)

    local moduleNames = true
    for _, entry in ipairs(ns.Modules:All()) do
        if type(L[entry.title]) ~= "string" or type(L[entry.blurb]) ~= "string" then
            moduleNames = false
        end
    end
    Check("Every module name and blurb resolves to a string", moduleNames)
end

---------------------------------------------------------------------------
-- The raid bar
--
-- WHAT THE DESKTOP CAN AND CANNOT SEE HERE, and the split decides the whole
-- suite. It cannot press a secure button, and it cannot know whether the game
-- accepted the macro. What it CAN check is the two things that actually break
-- a marks bar: the text of the macro each place is given, and the arithmetic
-- that decides which place is which.
--
-- A macro with the wrong word in it is a button that does nothing in a raid,
-- silently, for one language's players only. That is the failure this suite
-- exists for.
---------------------------------------------------------------------------
local function TestRaidBar()
    local RaidBar = ns.RaidBar
    Check("There is a raid bar", RaidBar ~= nil)
    if not RaidBar then return end

    ---------------------------------------------------------------------
    -- What can go on it
    ---------------------------------------------------------------------
    local keys, kinds = {}, {}
    local duplicate, artless, nameless
    for _, entry in ipairs(RaidBar.ACTIONS) do
        if keys[entry.key] then duplicate = entry.key end
        keys[entry.key] = true
        kinds[entry.kind] = (kinds[entry.kind] or 0) + 1
        -- EVERY BUTTON IS A PICTURE. A place with no art is a black square on
        -- the bar, and the picker beside it is a list of blank rows.
        -- A PATH OR A FILE ID, and both are real. The pull timer is drawn
        -- with 134376, the number BigWigs uses for its own timer bars; a
        -- check that insisted on a string would go red against correct code.
        -- Anything else - a table, a boolean, a nil - is a place that draws
        -- nothing.
        local art = entry.texture or entry.atlas
        if not (type(art) == "string" or type(art) == "number") then
            artless = entry.key
        end
        if type(entry.label) ~= "string" or entry.label == "" then
            nameless = entry.key
        end
    end

    Check("Every button has its own key", duplicate == nil, duplicate)
    Check("Every button has a picture", artless == nil, artless)
    Check("Every button has a name", nameless == nil, nameless)

    Check("There are eight markers and a clear", kinds.marker == 9,
        tostring(kinds.marker))
    Check("There are eight world markers and a clear", kinds.worldmarker == 9,
        tostring(kinds.worldmarker))
    Check("There are four pings", kinds.ping == 4, tostring(kinds.ping))
    Check("Three buttons run in the addon", kinds.call == 3,
        tostring(kinds.call))

    ---------------------------------------------------------------------
    -- WHAT A PRESS SENDS
    --
    -- The slash commands are the CLIENT'S, because they are translated on
    -- some clients - MRT carries a special case for exactly the four
    -- languages where "/wm" is not "/wm". Passed in here rather than read,
    -- so both halves are executed.
    ---------------------------------------------------------------------
    Check("A marker toggles rather than sets",
        RaidBar.MarkerMacro(3, false, "/tm") == "/tm !3")
    Check("The clear button clears every marker",
        RaidBar.MarkerMacro(0, true, "/tm") == "/tm 0")
    Check("A marker macro follows a translated command",
        RaidBar.MarkerMacro(5, false, "/marcador") == "/marcador !5")

    Check("A world marker is placed",
        RaidBar.WorldMarkerMacro(2, false, "/wm", "/cwm") == "/wm 2")
    Check("A world marker is taken away",
        RaidBar.WorldMarkerMacro(2, true, "/wm", "/cwm"):find("/cwm") == 1)
    Check("The world clear takes them all",
        RaidBar.WorldMarkerMacro(0, false, "/wm", "/cwm"):find("/cwm") == 1)

    Check("A ping is aimed at the target",
        RaidBar.PingMacro("attack", "/ping", "Attack")
            == "/ping [@target] Attack")

    ---------------------------------------------------------------------
    -- The lattice, which is now shared with the externals panel
    ---------------------------------------------------------------------
    local sameAsExternals = true
    for index = 1, 12 do
        local ax, ay = ns.LatticeCell(index, 2, 6, false)
        local bx, by = ns.Externals.Cell(index, 2, 6, false)
        if ax ~= bx or ay ~= by then sameAsExternals = false end
    end
    Check("Both panels place a place the same way", sameAsExternals)

    local x, y = ns.LatticeCell(7, 2, 6, false)
    Check("The seventh of six across starts the second row", x == 0 and y == 1)
    x, y = ns.LatticeCell(3, 2, 6, true)
    Check("Running down fills a column first", x == 1 and y == 0)

    local wide, tall = ns.LatticeExtent(3, 2, 6, false)
    Check("Three of twelve is three wide and one tall", wide == 3 and tall == 1)
    Check("Nothing shown takes no room",
        select(1, ns.LatticeExtent(0, 2, 6, false)) == 0)

    ---------------------------------------------------------------------
    -- The bar's own settings, on a copy of the profile's
    --
    -- Put back at the end. This is the one part of the suite that writes, and
    -- it writes to the live raid bar - so it is wrapped the way the module
    -- switch test is.
    ---------------------------------------------------------------------
    if not ns.db then
        Skip("The raid bar's settings", "no profile open")
        return
    end

    local kept = ns.db.raidBar
    local ok, err = pcall(function()
        ns.db.raidBar = nil

        local cfg = RaidBar.Config()
        Check("A fresh bar is seeded", cfg.cells[1] ~= nil and cfg.seeded)
        Check("The seed is a marks bar", cfg.cells[1] == "mark1"
            and cfg.cells[9] == "markclear")

        -- SEEDED ONCE. A migration that runs twice puts back the place
        -- somebody has just emptied, and it does it at every login.
        RaidBar.ClearSlot(1)
        RaidBar.Config()
        Check("Emptying a place survives the next read",
            RaidBar.Config().cells[1] == nil)

        RaidBar.SetSlot(1, "mark1")
        Check("A button goes where it is put",
            RaidBar.ActionAt(1) == "mark1")

        -- ONE BUTTON, ONE PLACE. Two Skulls on a bar is two places doing one
        -- job and a key bound to whichever of them you did not mean.
        RaidBar.SetSlot(4, "mark1")
        Check("Putting a button somewhere else moves it",
            RaidBar.ActionAt(1) == nil and RaidBar.ActionAt(4) == "mark1")

        Check("An unknown button is refused",
            (RaidBar.Pick("nonesuch") == nil) and not RaidBar.IsPicked("nonesuch"))

        -- Into the marked place, not the first free one.
        RaidBar.ClearSlot(2)
        Check("A button lands in the place you marked",
            RaidBar.Pick("pingattack", 2) == 2)

        RaidBar.SetRows(1)
        RaidBar.SetColumns(2)
        Check("Rows times columns is the count", RaidBar.Count() == 2)

        RaidBar.SetColumns(RaidBar.MAX_COLUMNS + 5)
        Check("Columns are clamped",
            RaidBar.Columns() == RaidBar.MAX_COLUMNS)
        RaidBar.SetRows(0)
        Check("Rows are clamped", RaidBar.Rows() == 1)

        -- WHAT FALLS OFF THE END STAYS PUT. Taking the bar down and back up
        -- has to give you what you had - the same rule a cooldown bar's cells
        -- follow.
        RaidBar.SetRows(1)
        RaidBar.SetColumns(12)
        RaidBar.SetSlot(12, "readycheck")
        RaidBar.SetColumns(4)
        RaidBar.SetColumns(12)
        Check("A button off the end comes back",
            RaidBar.ActionAt(12) == "readycheck")
    end)
    ns.db.raidBar = kept
    if not ok then error(err) end

    ---------------------------------------------------------------------
    -- The two calls the game may refuse
    ---------------------------------------------------------------------
    local may, why = RaidBar.MayLead()
    if IsInGroup and IsInGroup() then
        Skip("Leading refused when alone", "you are in a group")
    else
        Check("Alone, there is nobody to ready-check",
            may == false and why == "not in a group")
    end

    ---------------------------------------------------------------------
    -- The keys
    --
    -- The NAME shape, which is the half that can be checked in game: a
    -- binding this addon names has to be the CLICK form, because a line of
    -- Lua may not press a protected button. Whether Bindings.xml carries
    -- twelve of them is checked by the desktop harness, which can read files.
    ---------------------------------------------------------------------
    Check("A raid bar key presses the button itself",
        RaidBar.BindingName(3) == "CLICK ZwoelfStuffRaidBar3:LeftButton")
    Check("There are keys for the first twelve places",
        RaidBar.KEYS == 12)

    local reads = true
    for index = 1, RaidBar.KEYS do
        if not pcall(RaidBar.Key, index) then reads = false end
    end
    Check("Reading a bound key never throws", reads)
end

---------------------------------------------------------------------------
-- The raid check
--
-- The window cannot be judged out here, but everything that DECIDES what it
-- draws can: what this client says about itself, what travels, and what
-- arrives. The wire is the part worth guarding - it is read from another
-- machine, and a decoder that trusts what it is handed is a decoder that can
-- be handed a table key.
---------------------------------------------------------------------------
local function TestRaidCheck()
    local RaidCheck = ns.RaidCheck
    local Comm = ns.Comm
    Check("There is a raid check", RaidCheck ~= nil)
    if not RaidCheck then return end

    ---------------------------------------------------------------------
    -- The buffs, and the bits they travel as
    ---------------------------------------------------------------------
    local bits, spells = {}, 0
    for _, buff in ipairs(RaidCheck.BUFFS) do
        Check("Buff " .. buff.key .. " has a bit of its own", not bits[buff.bit])
        bits[buff.bit] = true
        for _ in pairs(buff.spells) do spells = spells + 1 end
    end
    Check("There are six group buffs", #RaidCheck.BUFFS == 6)
    Check("Every buff names at least one spell", spells >= #RaidCheck.BUFFS)

    local all = 0
    for _, buff in ipairs(RaidCheck.BUFFS) do all = all + buff.bit end
    local everyBit, noBit = true, false
    for _, buff in ipairs(RaidCheck.BUFFS) do
        if not RaidCheck.HasBuff(all, buff) then everyBit = false end
        if RaidCheck.HasBuff(0, buff) then noBit = true end
    end
    Check("Every bit reads back out of a full mask", everyBit)
    Check("An empty mask has nothing in it", not noBit)
    Check("A mask that is not a number is not a buff",
        not RaidCheck.HasBuff(nil, RaidCheck.BUFFS[1]))

    -- One bit set and the others clear, which is the case a bad shift gets
    -- wrong while a full mask still looks right.
    local second = RaidCheck.BUFFS[2]
    Check("One buff alone reads as that buff",
        RaidCheck.HasBuff(second.bit, second)
            and not RaidCheck.HasBuff(second.bit, RaidCheck.BUFFS[1]))

    ---------------------------------------------------------------------
    -- What this client says about itself
    ---------------------------------------------------------------------
    local mine = RaidCheck.Read()
    Check("The reading is a table", type(mine) == "table")

    if GetInventoryItemDurability then
        local worst = RaidCheck.Durability()
        -- THE LOWEST, NOT THE AVERAGE. A raid leader asking about durability
        -- is asking whether somebody's weapon is about to fall apart, and an
        -- average hides exactly that.
        Check("Durability is the worst piece worn",
            worst == nil or (worst >= 0 and worst <= 100),
            tostring(worst))
    end

    if RaidCheck.AurasReadable() then
        -- WHETHER YOU ARE FED IS NOT A PROPERTY OF THIS CODE.
        --
        -- These three lines used to read `mine.fo == 1`, `mine.fl == 1` and
        -- "buff six is not up" - which is not a test of the reader, it is a
        -- test of what the player happens to be carrying at the moment they
        -- type /zs test. Written during a raid, they passed; run in the guild
        -- city the next afternoon they reported TWO FAILURES against code
        -- that was working perfectly. A check that fails on a true negative
        -- teaches you to ignore the report, which costs more than the check
        -- was ever worth.
        --
        -- The desk could not catch it either: out there AurasReadable() is
        -- false and the whole block is skipped, so this only ever ran on a
        -- client - and only ever agreed with whoever was holding a flask.
        --
        -- WHAT IS ACTUALLY OURS TO GET WRONG is the SHAPE of the reading,
        -- and there are two real faults in here that the old lines could not
        -- tell apart from an empty stomach:
        --   the client says auras are readable and the read gives NOTHING
        --   the read gives something that is not a flag
        local flags = { fo = "food", fl = "flask", ru = "rune" }
        local missing, malformed
        for key, what in pairs(flags) do
            if mine[key] == nil then
                missing = missing or what
            elseif mine[key] ~= 0 and mine[key] ~= 1 then
                malformed = string.format("%s = %s", what, tostring(mine[key]))
            end
        end

        Check("Your own auras can be read at all", missing == nil,
            missing and ("no " .. missing .. " reading came back, though this "
                .. "client says auras are readable"))
        Check("Each consumable reads as a yes or a no", malformed == nil,
            malformed)
        Check("The buff mask is a number", type(mine.bf) == "number",
            type(mine.bf))

        -- Every bit in the mask has to belong to a buff we know. A stray one
        -- means the mask and the BUFFS table have drifted apart, which IS
        -- ours - and unlike "are you flasked", it is true whatever you are
        -- standing in.
        if type(mine.bf) == "number" then
            local known = 0
            for _, buff in ipairs(RaidCheck.BUFFS) do known = known + buff.bit end
            Check("The mask claims no buff this addon does not know",
                mine.bf >= 0 and mine.bf <= known
                and math.floor(mine.bf) == mine.bf, tostring(mine.bf))
        end

        -- AND THEN SAY WHAT IT FOUND, rather than have an opinion about it.
        -- This is the half that was worth having: if he is sitting there with
        -- a flask up and this line says no, THAT is the bug - and now it is
        -- one line to read instead of a red check that cries wolf every time
        -- somebody tests outside a raid.
        local carried = {}
        for _, buff in ipairs(RaidCheck.BUFFS) do
            if RaidCheck.HasBuff(mine.bf, buff) then
                carried[#carried + 1] = buff.label
            end
        end
        Skip("What you are carrying right now", string.format(
            "food %s, flask %s, rune %s, buffs: %s",
            mine.fo == 1 and "yes" or "no",
            mine.fl == 1 and "yes" or "no",
            mine.ru == 1 and "yes" or "no",
            #carried > 0 and table.concat(carried, ", ") or "none"))
    else
        Skip("Reading your own consumables", "this client keeps auras secret")
    end

    ---------------------------------------------------------------------
    -- The wire
    ---------------------------------------------------------------------
    local wire = Comm.EncodeCheck({ il = 639, du = 94, fo = 1, fl = 1, ru = 0,
        bf = 63 })
    local back = Comm.DecodeCheck(wire)
    Check("A reading survives the trip", back ~= nil and back.fields
        and back.fields.il == 639 and back.fields.du == 94
        and back.fields.bf == 63)

    -- WRITTEN IN A FIXED ORDER, so the same facts are the same string.
    Check("The same facts encode the same way",
        Comm.EncodeCheck({ bf = 1, il = 2 })
            == Comm.EncodeCheck({ il = 2, bf = 1 }))

    local ask = Comm.DecodeCheck(Comm.EncodeCheckAsk())
    Check("An ask decodes as an ask", ask ~= nil and ask.ask == true)

    -- THE TWO WIRE FORMS MUST NOT READ EACH OTHER. This is the whole reason
    -- the check form was shaped the way it was: an older client runs
    -- Comm.Decode alone, and it has to come back with nothing rather than
    -- with a spell it half understood.
    Check("The old decoder rejects a raid check", Comm.Decode(wire) == nil)
    Check("The old decoder rejects an ask",
        Comm.Decode(Comm.EncodeCheckAsk()) == nil)
    Check("The check decoder rejects a cooldown message",
        Comm.DecodeCheck(Comm.Encode(Comm.USED, Comm.EXTERNAL, 1022, 300))
            == nil)

    -- DATA FROM ANOTHER MACHINE IS NOT TRUSTED. A key nobody knows and a
    -- number wider than its field are both dropped rather than kept.
    local dirty = Comm.DecodeCheck("1|CHECK|il=639,zz=1,du=99999")
    Check("An unknown field is dropped",
        dirty ~= nil and dirty.fields.zz == nil)
    Check("A number too wide for its field is dropped",
        dirty ~= nil and dirty.fields.du == nil and dirty.fields.il == 639)
    Check("A message with nothing usable in it is nil",
        Comm.DecodeCheck("1|CHECK|zz=1") == nil)
    Check("Another version's check is not read",
        Comm.DecodeCheck("9|CHECK|il=1") == nil)
    Check("Rubbish is not a check", Comm.DecodeCheck("hello") == nil
        and Comm.DecodeCheck(nil) == nil)

    ---------------------------------------------------------------------
    -- The columns
    ---------------------------------------------------------------------
    local buffColumns = 0
    for _, column in ipairs(RaidCheck.COLUMNS) do
        if column.kind == "bit" then buffColumns = buffColumns + 1 end
    end
    Check("Every group buff has a column of its own",
        buffColumns == #RaidCheck.BUFFS)
    Check("The window is as wide as its columns", RaidCheck.Width() > 400)
    Check("The first column is the name", RaidCheck.COLUMNS[1].key == "name")
end

---------------------------------------------------------------------------
-- The invite tool
--
-- EVERY RULE IN HERE IS ONE STRING COMPARISON, and getting it wrong is either
-- a raid nobody can join or a raid that invites everybody who says hello.
-- None of it needs a group, which is the point of writing it as pure
-- functions in the first place.
---------------------------------------------------------------------------
local function TestInvites()
    local Invites = ns.Invites
    Check("There is an invite tool", Invites ~= nil)
    if not Invites then return end

    ---------------------------------------------------------------------
    -- The keywords
    ---------------------------------------------------------------------
    local set, order = Invites.Keywords("inv\nINVITE\n  1  \ninv\n\n")
    Check("Keywords are lower-cased and trimmed",
        set.inv and set.invite and set["1"])
    Check("A repeated keyword is kept once", #order == 3,
        table.concat(order, ","))
    Check("Empty lines are not keywords", set[""] == nil)
    Check("Commas separate too", select(2, Invites.Keywords("inv, invite"))[2]
        == "invite")
    -- The brackets are load-bearing: Keywords answers TWO values, and
    -- `next(a, b)` reads the second as a key to start from - which threw
    -- "invalid key to 'next'" rather than answering.
    Check("No keywords at all is an empty set",
        next((Invites.Keywords(""))) == nil)

    ---------------------------------------------------------------------
    -- The match
    ---------------------------------------------------------------------
    Check("The exact word invites", Invites.Matches("inv", set, false))
    Check("Case does not matter", Invites.Matches("INV", set, false))
    Check("Trailing punctuation does not matter",
        Invites.Matches("inv!", set, false) and Invites.Matches("inv.", set, false))
    Check("Space around it does not matter",
        Invites.Matches("  inv  ", set, false))

    -- STRICT IS STRICT. This is the half that keeps a raid leader from
    -- inviting somebody who was talking about something else.
    Check("A sentence containing the word does not invite",
        not Invites.Matches("inv please", set, false))
    Check("A sentence containing the word invites when asked to",
        Invites.Matches("inv please", set, true))
    -- AND THE COST OF LOOSE, which is on the page in as many words.
    Check("Loose matching finds it in a refusal too",
        Invites.Matches("I cannot inv you sorry", set, true))
    Check("An empty message never matches",
        not Invites.Matches("", set, true) and not Invites.Matches("  ", set, true))
    Check("Something that is not a message never matches",
        not Invites.Matches(nil, set, true))

    ---------------------------------------------------------------------
    -- Who gets in
    ---------------------------------------------------------------------
    Check("With no filters anybody gets in",
        Invites.MayInvite({}, false, false))
    Check("Guild only keeps a stranger out",
        not Invites.MayInvite({ guildOnly = true }, false, false))
    Check("Guild only lets a guild member in",
        Invites.MayInvite({ guildOnly = true }, true, false))
    Check("Friends only lets a friend in",
        Invites.MayInvite({ friendsOnly = true }, false, true))
    -- GUILD COUNTS AS FRIEND, and it is deliberate rather than sloppy: a
    -- guild member is somebody you have already said yes to once.
    Check("Friends only lets a guild member in",
        Invites.MayInvite({ friendsOnly = true }, true, false))
    Check("A refusal says why",
        select(2, Invites.MayInvite({ guildOnly = true }, false, false))
            == "not in your guild")

    ---------------------------------------------------------------------
    -- Being invited
    ---------------------------------------------------------------------
    Check("Nothing is accepted while the switch is off",
        not Invites.ShouldAccept({}, true, true))
    Check("A friend's invitation is accepted",
        Invites.ShouldAccept({ autoAccept = true }, true, false))
    Check("A guild member's invitation is accepted",
        Invites.ShouldAccept({ autoAccept = true }, false, true))
    Check("A stranger's invitation is not",
        not Invites.ShouldAccept({ autoAccept = true }, false, false))

    ---------------------------------------------------------------------
    -- Ranks, which count the wrong way round
    ---------------------------------------------------------------------
    Check("Any rank passes when none is set",
        Invites.RankAllowed(4, nil))
    Check("The guild master passes every filter",
        Invites.RankAllowed(0, 3))
    Check("A rank below the line is kept out",
        not Invites.RankAllowed(5, 3))
    Check("The line itself is in", Invites.RankAllowed(3, 3))
    Check("A rank that is not a number is out",
        not Invites.RankAllowed(nil, 3))

    ---------------------------------------------------------------------
    -- Promotion
    ---------------------------------------------------------------------
    Check("A named player is promoted",
        Invites.ShouldPromote("Zwoelf", "zwoelf\nakui"))
    Check("A name with a realm on it still matches",
        Invites.ShouldPromote("Akui-Gilneas", "akui"))
    Check("Nobody else is promoted",
        not Invites.ShouldPromote("Somebody", "zwoelf\nakui"))
    Check("An empty list promotes nobody",
        not Invites.ShouldPromote("Zwoelf", ""))

    ---------------------------------------------------------------------
    -- The listener, which must do nothing until it is switched on
    ---------------------------------------------------------------------
    if not ns.db then
        Skip("The invite listener", "no profile open")
        return
    end

    local keptModules = ns.db.modules and ns.db.modules.invites
    local keptInvites = ns.db.invites
    local ok, err = pcall(function()
        ns.db.modules = ns.db.modules or {}
        ns.db.invites = { keywords = "inv" }

        ns.db.modules.invites = false
        Check("A switched-off module does not invite",
            not Invites.OnMessage("inv", "Somebody", "WHISPER"))

        ns.db.modules.invites = true
        Check("Nothing happens until the switch is on",
            not Invites.OnMessage("inv", "Somebody", "WHISPER"))

        ns.db.invites.onWhisper = true
        Check("Say and yell are ignored until asked for",
            not Invites.OnMessage("inv", "Somebody", "SAYYELL"))

        -- YOUR OWN MESSAGE COMES BACK TO YOU on some channels, and inviting
        -- yourself is a refusal in the client and a puzzled line in chat.
        Check("Your own message is not an invitation",
            not Invites.OnMessage("inv", UnitName("player"), "WHISPER"))

        Check("Something that is not a word is not a request",
            not Invites.OnMessage("hello", "Somebody", "WHISPER"))

        -- A NAME THE CLIENT WITHHELD. Comparing it raises; the guard is the
        -- only reason this does not take the chat handler down with it.
        Check("A withheld name is not invited",
            not Invites.OnMessage("inv", __SECRET, "WHISPER"))

        ns.db.invites.guildOnly = true
        Check("Guild only keeps a stranger out of the group",
            not Invites.OnMessage("inv", "Somebody", "WHISPER"))
    end)
    ns.db.invites = keptInvites
    if ns.db.modules then ns.db.modules.invites = keptModules end
    if not ok then error(err) end
end

function Test:Run()
    passed, failed, notes = 0, {}, {}

    local suites = {
        { "Modules",       TestModules },
        { "Language",      TestLocale },
        { "Raid bar",      TestRaidBar },
        { "Raid check",    TestRaidCheck },
        { "Invites",       TestInvites },
        { "CD request",    TestExternals },
        { "Arrangements",  TestLayout },
        { "Coordinates",   TestOffsets },
        { "Shared nudge",  TestSharedNudge },
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
        { "Raid deaths",   TestRaidDeaths },
        { "Your bars",     TestLiveBars },
        { "Panel movers",  TestPanelMovers },
        { "Taunts",        TestTaunts },
        { "Addon channel", TestComm },
        { "CD answer",     TestAnswers },
        { "Slider maths",  TestSliderMaths },
        { "Lists with two readers", TestCommandList },
        { "Sounds",        TestSounds },
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
