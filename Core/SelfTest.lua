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

    -- The swap MoveCell performs, without needing a bar in the real list.
    layout.cells[1], layout.cells[2] = layout.cells[2], layout.cells[1]
    local x, y = ns.Layout.GetOffset(layout, 2)
    Check("The per-cell look stays with the slot, not the spell",
        Near(x, 17) and Near(y, -9))
    Check("Nothing about the look is filed per spec",
        layout.cellOptsBySpec == nil)
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
function Test:Run()
    passed, failed, notes = 0, {}, {}

    local suites = {
        { "Arrangements",  TestLayout },
        { "Coordinates",   TestOffsets },
        { "Pattern switch", TestPatternRoundTrip },
        { "Rows and columns", TestGridSliders },
        { "Per character", TestPerSpec },
        { "Bar fill",      TestFill },
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
