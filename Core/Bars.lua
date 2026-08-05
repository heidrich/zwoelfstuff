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

    rows    = 1,
    columns = 6,
    cells   = {},              -- [index] = spellID; holes are empty cells

    -- Size
    iconSize    = 40,
    barWidth    = 200,
    barHeight   = 24,
    spacing     = 4,
    lineSpacing = 4,

    -- Looks
    scale       = 1.0,
    alpha       = 1.0,
    borderSize  = 1,
    borderColor = { 0.00, 0.00, 0.00 },

    -- Position
    point    = "CENTER",
    relPoint = "CENTER",
    x        = 0,
    y        = -200,
    locked   = true,
}

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

-- How many cells a bar has. The grid is always rows x columns, so an empty
-- trailing cell is a real, clickable place to put something - that is what
-- makes "add a row" mean anything before you have filled it.
function Bars:CellCount(cfg)
    return math.max(1, (cfg.rows or 1) * (cfg.columns or 1))
end

---------------------------------------------------------------------------
-- Editing
---------------------------------------------------------------------------
function Bars:Add(name, kind)
    local cfg = {}
    ns.ApplyDefaults(cfg, ns.BAR_DEFAULTS)
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
    self:Changed(#ns.db.bars)
    return #ns.db.bars
end

function Bars:Remove(index)
    if not ns.db.bars[index] then return false end
    table.remove(ns.db.bars, index)
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
function Bars:MoveCell(index, from, to)
    local cfg = self:Get(index)
    if not cfg or from == to then return false end

    cfg.cells[from], cfg.cells[to] = cfg.cells[to], cfg.cells[from]
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

    cfg.rows = (cfg.rows or 1) + 1
    return self:SetCell(index, self:CellCount(cfg) - (cfg.columns or 1) + 1, spellID)
end

-- Re-flowing keeps the sequence: changing the column count must not scramble
-- what the user arranged, only re-wrap it.
function Bars:SetGrid(index, rows, columns)
    local cfg = self:Get(index)
    if not cfg then return false end

    rows = math.max(1, math.min(20, rows or cfg.rows))
    columns = math.max(1, math.min(20, columns or cfg.columns))
    if rows == cfg.rows and columns == cfg.columns then return false end

    -- Compact to a plain sequence first, then re-lay it into the new grid.
    -- Without this, shrinking a grid would silently drop whatever sat in the
    -- cells that no longer exist.
    local sequence = {}
    for cell = 1, self:CellCount(cfg) do
        if cfg.cells[cell] then sequence[#sequence + 1] = cfg.cells[cell] end
    end

    cfg.rows, cfg.columns = rows, columns
    wipe(cfg.cells)
    for position, spellID in ipairs(sequence) do
        if position > self:CellCount(cfg) then break end
        cfg.cells[position] = spellID
    end

    self:Changed(index)
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

function Bars:Prepare()
    for _, cfg in ipairs(ns.db.bars) do
        ns.ApplyDefaults(cfg, ns.BAR_DEFAULTS)
    end
end
