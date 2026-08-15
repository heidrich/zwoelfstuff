---------------------------------------------------------------------------
-- Changing the bars. The write side of Store.lua.
--
-- SEPARATE FROM Store ON PURPOSE. Store's promise is in its own header: it
-- translates what is on disk and rewrites nothing. Putting a setter in there
-- would make that sentence false on its first line, and the sentence is what
-- stops somebody "tidying" his profile into a shape an older version cannot
-- read.
--
-- PURE PROFILE WORK. Nothing here creates a frame or asks the game anything,
-- so every rule below can be proved without a client - which matters, because
-- the rules are about not losing a layout somebody built by hand.
--
-- THE ONE RULE WORTH READING FIRST: an id is not a position. A bar anchored
-- to another one stores the other one's id, so deleting the bar above it must
-- not renumber anything. `lastBarID` only ever goes up.
---------------------------------------------------------------------------
local _, ns = ...

local Cooldowns = ns.Cooldowns
local Bars = {}
Cooldowns.Bars = Bars

local Store = Cooldowns.Store

-- The default a NEW bar starts as. Deliberately small: it is a shape you can
-- see the whole of on the first screen, not a demonstration of every setting.
-- Everything absent falls back inside Model and Store, which is where the
-- defaults for a bar somebody made in 4.82.0 come from too - one set of
-- fallbacks, not a second table that drifts from it.
local NEW = {
    enabled = true,
    kind    = "icon",
    rows    = 1,
    columns = 5,
    layout  = "grid",
    flow    = "rows",
    growX   = "right",
    growY   = "down",
    iconSize = 40,
    spacing = 4,
    lineSpacing = 4,
    barWidth = 200,
    barHeight = 24,
    staggerOffset = 50,
    iconPlacement = "left",
    point = "CENTER",
    relPoint = "CENTER",
    x = 0,
    y = -200,
    scale = 1,
}

local function Profile()
    local db = ns.db
    if not db then return nil end
    db.bars = type(db.bars) == "table" and db.bars or {}
    return db
end

-- THE NEXT ID, AND IT NEVER GOES BACKWARDS.
--
-- `lastBarID` is what 4.82.0 stored and it is read rather than recomputed:
-- deriving the next id from "the highest one in use" hands a deleted bar's id
-- to the next new one, and anything still anchored to the old one silently
-- follows the new one instead. His file says 1 today; a profile that once had
-- six says 6, and that is the number to trust.
function Bars.NextID()
    local db = Profile()
    if not db then return 1 end

    local last = tonumber(db.lastBarID) or 0
    for _, bar in pairs(db.bars) do
        local id = type(bar) == "table" and tonumber(bar.id)
        if id and id > last then last = id end
    end

    db.lastBarID = last + 1
    return db.lastBarID
end

-- A NAME THAT IS NOT ALREADY TAKEN. "Bar", then "Bar 2", and so on - the
-- shape people expect from every other list in this addon.
function Bars.FreeName(wanted)
    local db = Profile()
    wanted = (type(wanted) == "string" and wanted ~= "") and wanted or "Bar"
    if not db then return wanted end

    local taken = {}
    for _, bar in pairs(db.bars) do
        if type(bar) == "table" and type(bar.name) == "string" then
            taken[bar.name] = true
        end
    end

    if not taken[wanted] then return wanted end
    local suffix = 2
    while taken[wanted .. " " .. suffix] do suffix = suffix + 1 end
    return wanted .. " " .. suffix
end

function Bars.New(name)
    local db = Profile()
    if not db then return nil end

    -- The defaults FIRST, then the three things that are this bar's own.
    -- Written this way round rather than as a copy onto a half-built table:
    -- a literal of three keys tells the static check the table holds numbers
    -- and strings, and the loop then writes booleans into it.
    local bar = {}
    for key, value in pairs(NEW) do bar[key] = value end
    bar.id = Bars.NextID()
    bar.name = Bars.FreeName(name)
    bar.cells = {}

    db.bars[#db.bars + 1] = bar
    return bar
end

-- A COPY, WITH ITS OWN IDENTITY AND ITS OWN CELLS.
--
-- Deep enough to matter and no deeper: every table on a bar is copied, so
-- changing the copy's colours or its cells cannot reach back into the
-- original. A shallow copy here is the classic "I duplicated it and editing
-- one edits both" - and on a bar the shared table would be the CELL LIST,
-- which is the one thing somebody duplicates a bar in order to change.
local function Clone(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, inner in pairs(value) do out[key] = Clone(inner) end
    return out
end

function Bars.Duplicate(id)
    local db = Profile()
    if not db then return nil end
    local source = Store.ByID(id)
    if not source then return nil end

    local bar = Clone(source)
    bar.id = Bars.NextID()
    bar.name = Bars.FreeName(source.name)
    -- AN ANCHOR IS NOT COPIED. "Follow that bar" on a duplicate means the
    -- copy sits exactly on top of the original with no way to tell which one
    -- you are dragging. It gets its own position instead, nudged so it is
    -- visibly a second thing.
    bar.anchor = nil
    bar.y = (tonumber(bar.y) or 0) - 60

    db.bars[#db.bars + 1] = bar
    return bar
end

-- DELETING ONE RELEASES ANYTHING THAT FOLLOWED IT.
--
-- `anchor = { to = <barID> }` is how one bar hangs off another. A bar whose
-- target has been deleted has nowhere to be, and the failure is not an error
-- - it is a bar that quietly stops appearing, or appears at the origin, with
-- nothing on screen to say why. So the followers are cut loose and keep the
-- position they are at.
function Bars.Delete(id)
    local db = Profile()
    if not db then return false end

    local removed = false
    for index = #db.bars, 1, -1 do
        local bar = db.bars[index]
        if type(bar) == "table" and bar.id == id then
            table.remove(db.bars, index)
            removed = true
        end
    end
    if not removed then return false end

    local freed = 0
    for _, bar in pairs(db.bars) do
        if type(bar) == "table" and type(bar.anchor) == "table"
            and bar.anchor.to == id then
            bar.anchor = nil
            freed = freed + 1
        end
    end

    return true, freed
end

---------------------------------------------------------------------------
-- The cells
--
-- A CELL IS FILED UNDER THE SPEC BEING PLAYED, and that is the whole reason
-- this is not one line. The LAYOUT is shared by every character - it is how
-- the bar looks - and the SPELLS are not, because a protection paladin and a
-- holy one do not have the same cooldowns. Store.Cells reads through
-- ns.SpecStore for exactly that reason.
--
-- SO A WRITE WITH NO SPEC IS REFUSED, and it is refused rather than filed
-- somewhere safe. Just after login the client answers "WARRIOR:0" for a
-- moment - not a spec, a placeholder - and a pick filed under it goes into a
-- bin nothing ever reads again. The alternative, writing to the shared list
-- instead, is worse: it would put one character's spells on every character's
-- bar, and the user would have no way to tell that had happened.
---------------------------------------------------------------------------

-- The table a pick should actually be written into, or nil and a reason.
function Bars.CellStore(bar)
    if type(bar) ~= "table" then return nil, "there is no such bar" end

    local mine = ns.SpecStore("cellsBySpec", bar.cells, bar)
    if not mine then
        return nil, "the client has not said which specialisation this is yet"
    end
    return mine
end

function Bars.SetCell(bar, index, spellID)
    index = tonumber(index)
    if not index or index < 1 then return false, "there is no such cell" end

    local cells, why = Bars.CellStore(bar)
    if not cells then return false, why end

    cells[index] = tonumber(spellID) or nil
    return true
end

-- THERE IS NO MoveCell HERE, AND THAT IS THE DESIGN.
--
-- One was written, and it was a second writer for something that already had
-- one: UI.SpellSlot's drag machinery empties the source and fills the target
-- through the page's own onClear and onPick, which are SetCell both times.
-- Its swap is three ordered writes and it is correct - see UI.DragOutcome -
-- so a MoveCell beside it would be a second answer to "where did that spell
-- go", and the two would drift on the first change to either.
--
-- The orphan check found it: written, exported, and called by nothing.

-- Which spells are on this bar, as a set, for the picker's "already used"
-- mark. Keyed by spell so a lookup is one index rather than a walk per row.
function Bars.Used(bar)
    local out = {}
    local cells = Store.Cells(bar)
    for index, spellID in pairs(type(cells) == "table" and cells or {}) do
        if type(spellID) == "number" then
            out[spellID] = tostring(index)
        end
    end
    return out
end

-- THE FIRST EMPTY CELL, so a click on a spell with nothing selected still
-- has somewhere to go. Nil when the bar is full, which the caller says out
-- loud rather than silently overwriting cell 1.
function Bars.FirstFree(bar)
    local cells = Store.Cells(bar)
    for index = 1, Store.Capacity(bar) do
        if cells[index] == nil then return index end
    end
    return nil
end
