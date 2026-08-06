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

    -- Identity, and it is NOT the position in the list. A bar that is anchored
    -- to another one has to keep pointing at the same bar after a delete
    -- reshuffles every index below it.
    id      = 0,               -- assigned by Prepare(), never reused

    rows    = 1,
    columns = 6,
    cells   = {},              -- [index] = spellID; holes are empty cells

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

    -- The cooldown sweep.
    swipeColor = { 0.00, 0.00, 0.00 },
    swipeAlpha = 0.70,
    showEdge   = false,        -- the bright line that follows the sweep

    -- Text. Three elements, one shape each, because "the countdown can be
    -- moved but the stack count cannot" is the kind of arbitrary limit that
    -- makes people go looking for another addon.
    --
    -- A size of 0 means "work it out from the cell", which is what keeps a
    -- 24px cell and a 64px cell looking like one design.
    countdown = {
        show    = true,
        font    = "Friz Quadrata TT",
        size    = 0,
        color   = { 1.00, 1.00, 1.00 },
        outline = "OUTLINE",
        anchor  = "CENTER",
        x       = 0,
        y       = 0,
    },

    stacks = {
        show    = true,
        font    = "Friz Quadrata TT",
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
        font    = "Friz Quadrata TT",
        size    = 0,
        color   = { 1.00, 1.00, 1.00 },
        outline = "",
        anchor  = "LEFT",
        x       = 0,
        y       = 0,
    },

    -- Position, relative to the screen centre. Always the bar's own centre,
    -- so the readout in unlock mode means something and snapping is
    -- arithmetic rather than a case analysis.
    point    = "CENTER",
    relPoint = "CENTER",
    x        = 0,
    y        = -200,
    locked   = true,

    -- Attached to another bar, and then the fields above are not used:
    --   { to = <bar id>, point, relPoint, x, y }
    -- Nil means it stands on its own. See Bars:Anchor.
    anchor   = nil,
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
    "iconZoom",
    "swipeColor", "swipeAlpha", "showEdge",
    "countdown", "stacks", "spellName",
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

    return {
        show    = element.show ~= false,
        font    = element.font,
        size    = size,
        color   = element.color or { 1, 1, 1 },
        outline = element.outline or "",
        anchor  = element.anchor or "CENTER",
        x       = element.x or 0,
        y       = element.y or 0,
    }
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

        swipeColor = cfg.swipeColor or { 0, 0, 0 },
        swipeAlpha = cfg.swipeAlpha or 0.7,
        showEdge   = cfg.showEdge and true or false,

        countdown = TextStyle(cfg.countdown, height, 0.42, 9, 20),
        stacks    = TextStyle(cfg.stacks,    height, 0.30, 8, 16),
        spellName = TextStyle(cfg.spellName, height, 0.45, 9, 14),
    }
end

-- Copied all the way down, not referenced: a shared table would mean editing
-- one bar's border silently repainted every bar made from it. Recursive
-- rather than an ipairs pass, because the text settings are hash tables and
-- ipairs over one of those copies NOTHING - a preset that looked saved and
-- restored an empty table.
local function DeepCopy(value)
    if type(value) ~= "table" then return value end

    local copy = {}
    for key, inner in pairs(value) do copy[key] = DeepCopy(inner) end
    return copy
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
            countdown = Text(0, { 1, 1, 1 }, "OUTLINE", "CENTER"),
            stacks    = Text(0, { 1, 1, 1 }, "OUTLINE", "BOTTOMRIGHT"),
            spellName = Text(0, { 1, 1, 1 }, "", "LEFT"),
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
            countdown = Text(0, { 1, 1, 1 }, "OUTLINE", "CENTER"),
            stacks    = Text(0, { 1, 1, 1 }, "OUTLINE", "BOTTOMRIGHT"),
            spellName = Text(0, { 1, 1, 1 }, "", "LEFT"),
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
            countdown = Text(0, { 1, 1, 1 }, "THICKOUTLINE", "CENTER"),
            stacks    = Text(0, { 1, 0.9, 0.4 }, "THICKOUTLINE", "BOTTOMRIGHT"),
            spellName = Text(0, { 1, 1, 1 }, "OUTLINE", "LEFT"),
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
            countdown = { show = false },
            stacks    = { show = false },
            spellName = { show = false },
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

function Bars:Prepare()
    for _, cfg in ipairs(ns.db.bars) do
        ns.ApplyDefaults(cfg, ns.BAR_DEFAULTS)
        if not cfg.id or cfg.id == 0 then cfg.id = self:NextID() end
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
