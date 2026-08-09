---------------------------------------------------------------------------
-- EditMode - unlock the screen and build the thing.
--
-- Two modes, and the difference is the level you are working at:
--
--   MOVE   the whole bar is one object. Drag it, snap it to the screen or to
--          another bar, attach it so it follows. This is what unlock mode has
--          always been.
--
--   BUILD  every CELL is its own object. Drag one icon out of the row, scale
--          it, swap it for a tracking bar, drop a spell into an empty slot
--          from the palette, take one out. This is the puzzle: a grid you
--          pull apart by hand until the display is the shape you wanted
--          rather than the shape a row of icons happens to be.
--
-- One mode is not a lesser version of the other, and neither is a separate
-- feature: the arrangement engine adds a per-cell offset on top of whatever
-- the lattice worked out (Core/Layout.lua), so nudging one icon out of a neat
-- row and building a free-form layout are the SAME edit. There is no line to
-- cross between "a bar" and "a puzzle".
--
-- WHY A PANEL AND NOT THE BAR ITSELF.
--
-- Half of what a bar shows is a Blizzard frame we adopted, and those bring
-- their own mouse handling. Dragging the bar directly would fight tooltips
-- and clicks that are not ours to intercept. A panel above it at a higher
-- strata answers the mouse instead, and the bar never learns it is being
-- moved. The same argument makes every cell handle a panel of its own.
--
-- POSITIONS ARE PINNED-POINT RELATIVE.
--
-- A bar is placed by ONE of its nine points, offset from the screen centre.
-- The centre is the default and the readout means what it says; pin an edge
-- instead and the bar grows away from that edge when it gains a row. Snapping
-- still works in centre terms, because "line these two up" is about the shapes
-- and not about what each one happens to be pinned by - the translation
-- happens once, here.
---------------------------------------------------------------------------
local _, ns = ...

local EditMode = {}
ns.EditMode = EditMode

local UI = ns.UI
local C = UI.C

local NUDGE = 1
local NUDGE_FAST = 10

-- Everything about how unlock mode BEHAVES lives in saved variables, so it is
-- there again tomorrow. Read through one function rather than reached into,
-- because it has to survive a profile that predates any of these keys.
-- FILLED FROM THE PROFILE DEFAULTS, not from a second list of the same keys.
--
-- There used to be a list here: gridStep, snap, snapDistance, dim. Four of the
-- seven keys ns.DEFAULTS.editMode declares - and `snapToGrid` was one of the
-- three it did not. So on any profile made before that key existed it read
-- nil, grid snapping was off, and nothing on screen said it had never been on.
-- Two lists of the same thing drift; this one cannot.
local function Prefs()
    ns.db.editMode = ns.db.editMode or {}
    local prefs = ns.db.editMode
    for key, value in pairs(ns.DEFAULTS.editMode) do
        if prefs[key] == nil then prefs[key] = value end
    end
    return prefs
end

local unlocked = false
local mode = "bars"            -- "bars" | "build"
local overlay, toolbar, keyCatcher, palette, inspector, tools
local movers = {}
local handles = {}             -- [barIndex] = { [cellIndex] = handle }
local selected = nil           -- the selected MOVER
---@type table|nil
local picked = nil             -- { bar = index, cell = index } in build mode
local dragging = nil
local cellDrag = nil
local guideX, guideY, gridLines

-- Forward declarations. A handle's script is written above the drag section
-- that defines these, and without them the reference would silently be a
-- global that is nil at call time.
local StopDrag, StopCellDrag, RefreshInspector, SelectCell

---------------------------------------------------------------------------
-- Geometry
---------------------------------------------------------------------------
local function CursorPosition()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    if scale == 0 then return 0, 0 end
    return x / scale, y / scale
end

-- Every candidate carries two numbers, and they are not the same one:
--   value  where OUR centre has to end up
--   guide  where the line is drawn, which is the edge that actually lined up
--
-- Measured off the live frames rather than off the saved x/y: a bar pinned by
-- its left edge stores a number that is not its centre, and lining two bars up
-- is about where they ARE.
-- PURE, AND THAT IS THE POINT.
--
-- Snapping went wrong three times and every diagnosis was reading the code and
-- reasoning about it, because none of it could be run: the arithmetic was
-- welded to live frames and saved variables. This half takes plain numbers and
-- returns plain numbers, so /zs test can put two bars 4 units apart and assert
-- where the second one lands.
--
--   value       where our centre wants to go, offset from the screen centre
--   half        half our width (or height)
--   screenHalf  half the screen's
--   others      { { centre = n, half = n }, ... }  the OTHER bars
--   prefs       { snapDistance, snapToGrid, gridStep }
--
-- Returns the value to use, and where to draw the line - or nil for no line.
function EditMode.SnapAxis(value, half, screenHalf, others, prefs)
    local list = { { value = 0, guide = 0 } }   -- the screen centre

    -- The screen's own edges, with our edge flush against them. Pushing a bar
    -- into a corner is one of the two things everybody does with a bar, and
    -- there was nothing there to catch it.
    list[#list + 1] = { value = -screenHalf + half, guide = -screenHalf }
    list[#list + 1] = { value = screenHalf - half,  guide = screenHalf }

    for _, other in ipairs(others) do
        local near, far = other.centre - other.half, other.centre + other.half

        -- ALIGNED: our centre or one of our edges on one of theirs.
        list[#list + 1] = { value = other.centre, guide = other.centre }
        list[#list + 1] = { value = near + half, guide = near }
        list[#list + 1] = { value = far - half,  guide = far }

        -- FLUSH: our edge against theirs, the two side by side with nothing
        -- between. This was the missing half of "snap to another bar" - every
        -- candidate was an ALIGNMENT, so two bars could line up their left
        -- edges but never sit next to each other, which is how a row of bars
        -- is actually built.
        list[#list + 1] = { value = near - half, guide = near }
        list[#list + 1] = { value = far + half,  guide = far }
    end

    local best, bestDistance, guide = value, prefs.snapDistance, nil
    for _, candidate in ipairs(list) do
        local distance = math.abs(candidate.value - value)
        if distance < bestDistance then
            bestDistance, best, guide = distance, candidate.value, candidate.guide
        end
    end

    -- The screen grid, when it is asked for, and only where nothing better
    -- caught. A bar edge lining up with another bar's edge beats landing on
    -- an arbitrary multiple of 40, so this is the fallback and not the rule.
    --
    -- The grid pulls from any distance, unlike everything above: a grid you
    -- have switched on means every position is on it, not "on it if you were
    -- already close". What it did NOT do was say so - it returned no guide, so
    -- the one kind of snapping that always fires was also the only kind with
    -- no line to show for it, and it read as nothing happening.
    if prefs.snapToGrid and not guide then
        local step = prefs.gridStep
        if step and step > 0 then
            best = math.floor(value / step + 0.5) * step
            guide = best
        end
    end

    return best, guide
end

-- The frame-reading half: measure the other bars, then hand the numbers over.
--
-- Measured off the live frames rather than off the saved x/y, because a bar
-- pinned by its left edge stores a number that is not its centre, and lining
-- two bars up is about where they ARE.
local function Snap(value, index, half, axis)
    local others = {}

    for otherIndex in ipairs(ns.db.bars) do
        local bar = ns.Screen:BarFrame(otherIndex)
        if otherIndex ~= index and bar and bar:IsShown() then
            local offsetX, offsetY = ns.Screen:CentreOffset(otherIndex)
            if offsetX then
                others[#others + 1] = {
                    centre = (axis == "x") and offsetX or offsetY,
                    half = ((axis == "x") and bar:GetWidth()
                        or bar:GetHeight()) / 2,
                }
            end
        end
    end

    local screenHalf = ((axis == "x") and UIParent:GetWidth()
        or UIParent:GetHeight()) / 2

    return EditMode.SnapAxis(value, half, screenHalf, others, Prefs())
end

---------------------------------------------------------------------------
-- Overlay furniture
---------------------------------------------------------------------------
local function BuildGuides()
    guideX = overlay:CreateTexture(nil, "OVERLAY")
    guideX:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9)
    guideX:SetWidth(1)
    guideX:Hide()

    guideY = overlay:CreateTexture(nil, "OVERLAY")
    guideY:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9)
    guideY:SetHeight(1)
    guideY:Hide()
end

local function ShowGuide(texture, offset, vertical)
    if not offset then
        texture:Hide()
        return
    end
    texture:ClearAllPoints()
    if vertical then
        texture:SetPoint("TOP", UIParent, "TOP", offset, 0)
        texture:SetPoint("BOTTOM", UIParent, "BOTTOM", offset, 0)
    else
        texture:SetPoint("LEFT", UIParent, "LEFT", 0, offset)
        texture:SetPoint("RIGHT", UIParent, "RIGHT", 0, offset)
    end
    texture:Show()
end

-- The grid is REDRAWN when the step changes, so the lines are pooled rather
-- than created: a texture cannot be destroyed, and a fresh set every time
-- somebody drags the step slider would leak a few hundred of them per drag.
local gridPool, gridUsed = {}, 0

local function GridLine(vertical, offset, strong)
    gridUsed = gridUsed + 1
    local line = gridPool[gridUsed]
    if not line then
        line = gridLines:CreateTexture(nil, "BACKGROUND")
        gridPool[gridUsed] = line
    end

    line:SetColorTexture(1, 1, 1, strong and 0.35 or 0.12)
    line:ClearAllPoints()
    if vertical then
        line:SetWidth(1)
        line:SetHeight(0)
        line:SetPoint("TOP", gridLines, "TOP", offset, 0)
        line:SetPoint("BOTTOM", gridLines, "BOTTOM", offset, 0)
    else
        line:SetHeight(1)
        line:SetWidth(0)
        line:SetPoint("LEFT", gridLines, "LEFT", 0, offset)
        line:SetPoint("RIGHT", gridLines, "RIGHT", 0, offset)
    end
    line:Show()
end

local function DrawGrid()
    if not gridLines then return end

    local step = math.max(4, Prefs().gridStep or 40)
    local width  = UIParent:GetWidth()
    local height = UIParent:GetHeight()
    gridUsed = 0

    -- Measured OUT FROM THE CENTRE in both directions, because the centre is
    -- what every bar's position is measured from. A grid starting at the
    -- screen edge would put its lines where no coordinate is round.
    for offset = 0, width / 2, step do
        GridLine(true, offset, offset == 0)
        if offset > 0 then GridLine(true, -offset, false) end
    end
    for offset = 0, height / 2, step do
        GridLine(false, offset, offset == 0)
        if offset > 0 then GridLine(false, -offset, false) end
    end

    for index = gridUsed + 1, #gridPool do gridPool[index]:Hide() end
end

local function BuildGrid()
    gridLines = CreateFrame("Frame", nil, overlay)
    gridLines:SetAllPoints(overlay)
    gridLines:Hide()
    DrawGrid()
end

---------------------------------------------------------------------------
-- One mover - a whole bar
---------------------------------------------------------------------------
local function BarConfig(index)
    return ns.db.bars[index]
end

-- The pair of numbers a drag or a nudge edits. For a bar that hangs on
-- another one that is its OFFSET from the parent, not its place on screen -
-- editing the screen position of an attached bar would do nothing at all.
local function Origin(cfg)
    if cfg.anchor then return cfg.anchor.x or 0, cfg.anchor.y or 0 end
    return cfg.x or 0, cfg.y or 0
end

-- The pinned-point numbers that put the bar's CENTRE on the screen centre.
--
-- Not 0,0 - that only centres a bar pinned by its middle. Pinned by its left
-- edge, 0 puts the EDGE on the centre line and the bar sits half a bar to the
-- right, so "Centre on screen" quietly did something other than what it says.
-- The drag already carries this translation; the buttons did not.
local function CentringOffsets(index, cfg)
    local originX, originY = Origin(cfg)
    local centreX, centreY = ns.Screen:CentreOffset(index)
    if not centreX then return originX, originY end
    return originX - centreX, originY - centreY
end

local function UpdateReadout(mover)
    local cfg = BarConfig(mover.index)
    if not cfg then return end

    local x, y = Origin(cfg)
    if cfg.anchor then
        local parent = ns.Bars:ByID(cfg.anchor.to)
        mover.coords:SetText(string.format("|cffff7a3d>|r %s  %d, %d",
            parent and parent.name or "?", x, y))
    else
        mover.coords:SetText(string.format("%d, %d", x, y))
    end
end

local function SetSelected(mover)
    for _, other in ipairs(movers) do
        local isIt = (other == mover)
        other.edge:SetColor(
            isIt and C.accent[1] or C.accentDim[1],
            isIt and C.accent[2] or C.accentDim[2],
            isIt and C.accent[3] or C.accentDim[3], 1)
        other.coords:SetShown(isIt or Prefs().showCoords)
        -- Raised while selected, so two overlapping bars do not leave you
        -- dragging the one underneath the one you clicked.
        other:SetFrameLevel(overlay:GetFrameLevel() + (isIt and 20 or 10))
    end
    selected = mover
    if mode == "build" then
        -- The cell index carries across so clicking about between bars does
        -- not keep resetting you to slot 1 - but CLAMPED, or picking a bar
        -- with fewer cells than the last one leaves the inspector reading
        -- "slot 9 of 6" and the arrows nudging a slot that is not there.
        local cfg = BarConfig(mover.index)
        local cell = (picked and picked.cell) or 1
        if cfg then cell = math.min(cell, ns.Bars:CellCount(cfg)) end
        picked = { bar = mover.index, cell = math.max(1, cell) }
    end
    RefreshInspector()
    if tools and tools:IsShown() then tools.Refresh() end
end

local function ApplyMove(mover, x, y)
    local cfg = BarConfig(mover.index)
    if not cfg then return end

    x, y = math.floor(x + 0.5), math.floor(y + 0.5)

    if cfg.anchor then
        cfg.anchor.x, cfg.anchor.y = x, y
    else
        -- The pinned point is kept. Forcing it back to CENTER here is what
        -- would silently undo a grow direction the moment the bar is nudged.
        cfg.relPoint = "CENTER"
        cfg.x, cfg.y = x, y
    end

    ns.Screen:ApplyPosition(mover.index)
    UpdateReadout(mover)
end

-- Which bar to attach to. Its own menu rather than a submenu, because the
-- shared menu has one level and a flat list of every bar times every side
-- would be a wall of entries.
local function OpenAttachMenu(mover)
    local index = mover.index
    local cfg = BarConfig(index)
    if not cfg then return end

    local items = {}
    for otherIndex, other in ipairs(ns.db.bars) do
        if otherIndex ~= index and not ns.Bars:WouldLoop(cfg.id, other.id) then
            items[#items + 1] = {
                text = other.name or ("Bar " .. otherIndex),
                onClick = function()
                    -- Below is the default because a stack of bars is what
                    -- people build; the side is one click away afterwards.
                    ns.Bars:Anchor(index, other.id, "below")
                end,
            }
        end
    end

    if #items == 0 then
        items[1] = { text = "|cff888888Nothing to attach to|r", onClick = function() end }
    end

    UI.ShowMenu(mover.cog, {
        width = 190,
        anchor = { "TOPRIGHT", "BOTTOMRIGHT", 0, -2 },
        items = items,
    })
end

local function OpenMenu(mover)
    local index = mover.index
    local cfg = BarConfig(index)
    if not cfg then return end

    local items = {}

    -- An attached bar gets the four sides instead of the screen-centring
    -- entries: those would move a bar whose position is not its own to
    -- decide, and doing nothing visible is worse than not offering it.
    if cfg.anchor then
        local parent = ns.Bars:ByID(cfg.anchor.to)
        for _, side in ipairs(ns.ANCHOR_SIDES) do
            items[#items + 1] = {
                text = side.text .. " " .. (parent and parent.name or "?"),
                value = side.key,
                onClick = function()
                    ns.Bars:Anchor(index, cfg.anchor.to, side.key)
                end,
            }
        end
    else
        items[#items + 1] = { text = "Attach to another bar", onClick = function()
            OpenAttachMenu(mover)
        end }
        items[#items + 1] = { text = "Centre on screen", onClick = function()
            local x, y = CentringOffsets(index, cfg)
            ApplyMove(mover, x, y)
        end }
        items[#items + 1] = { text = "Centre horizontally", onClick = function()
            local x = CentringOffsets(index, cfg)
            ApplyMove(mover, x, select(2, Origin(cfg)))
        end }
        items[#items + 1] = { text = "Centre vertically", onClick = function()
            local _, y = CentringOffsets(index, cfg)
            ApplyMove(mover, (Origin(cfg)), y)
        end }
    end

    local actions = {
        { text = "Bar options", onClick = function()
            EditMode:SetUnlocked(false)
            ns.OptionsBars:ShowOptions(index)
            -- Open, not Toggle: this wants the window shown, and Toggle
            -- would close it if it happened to be open already.
            ns.Options:Open("cooldowns")
        end },
        { text = cfg.enabled == false and "Switch on" or "Switch off",
          onClick = function()
              cfg.enabled = (cfg.enabled == false)
              ns.Bars:Changed(index)
          end },
    }

    if cfg.anchor then
        table.insert(actions, 1, { text = "Detach", onClick = function()
            ns.Bars:Release(cfg)
        end })
    end

    UI.ShowMenu(mover.cog, {
        width = 190,
        anchor = { "TOPRIGHT", "BOTTOMRIGHT", 0, -2 },
        current = cfg.anchor and cfg.anchor.side or nil,
        items = items,
        actions = actions,
    })
end

local function CreateMover(index)
    local mover = CreateFrame("Button", nil, overlay)
    mover.index = index
    mover:SetFrameLevel(overlay:GetFrameLevel() + 10)

    mover.bg = mover:CreateTexture(nil, "BACKGROUND")
    mover.bg:SetAllPoints(mover)
    mover.bg:SetColorTexture(C.sidebarBg[1], C.sidebarBg[2], C.sidebarBg[3], 0.92)

    mover.edge = ns.CreateBorder(mover, 1, "BORDER")
    mover.edge:SetColor(C.accentDim[1], C.accentDim[2], C.accentDim[3], 1)

    -- Own frame, raised: a texture on the mover would be painted under the
    -- mover's own child frames whatever layer it claims, and the cog is one.
    local text = CreateFrame("Frame", nil, mover)
    text:SetAllPoints(mover)
    text:SetFrameLevel(mover:GetFrameLevel() + 2)
    text:SetClipsChildren(true)

    mover.name = UI.Label(text, "", 12, C.text)
    mover.name:SetPoint("CENTER", text, "CENTER", 0, 0)
    mover.name:SetWordWrap(false)

    mover.coords = UI.Label(text, "", 10, C.textDim)
    mover.coords:SetPoint("TOPLEFT", text, "TOPLEFT", 4, -3)
    mover.coords:SetWordWrap(false)
    mover.coords:Hide()

    mover.cog = CreateFrame("Button", nil, mover)
    mover.cog:SetSize(20, 20)
    mover.cog:SetPoint("TOPRIGHT", mover, "TOPRIGHT", -2, -2)
    mover.cog:SetFrameLevel(mover:GetFrameLevel() + 4)
    local cogGlyph = UI.Glyph(mover.cog, "ui-gear", 12, C.textDim)
    cogGlyph:SetPoint("CENTER", mover.cog, "CENTER", 0, 0)
    mover.cog:SetScript("OnEnter", function()
        cogGlyph:SetColor(C.accent[1], C.accent[2], C.accent[3])
    end)
    mover.cog:SetScript("OnLeave", function()
        cogGlyph:SetColor(C.textDim[1], C.textDim[2], C.textDim[3])
    end)
    mover.cog:SetScript("OnClick", function() OpenMenu(mover) end)

    -- THE PADLOCK, DIRECTLY UNDER THE COG. One bar at a time.
    --
    -- The bar you have finished placing and the bar you are still placing are
    -- on screen together, and the finished one is exactly what a stray drag
    -- lands on. Pinned still selects, still opens its settings, still takes a
    -- cell - it just does not move.
    mover.lock = CreateFrame("Button", nil, mover)
    mover.lock:SetSize(20, 20)
    mover.lock:SetPoint("TOPRIGHT", mover.cog, "BOTTOMRIGHT", 0, -2)
    mover.lock:SetFrameLevel(mover:GetFrameLevel() + 4)
    local lockGlyph = UI.Glyph(mover.lock, "ui-lock", 12, C.textDim)
    lockGlyph:SetPoint("CENTER", mover.lock, "CENTER", 0, 0)
    mover.lockGlyph = lockGlyph

    -- Its own function, because three things set it: the click, the refresh
    -- that runs when edit mode opens, and hovering off it.
    mover.RefreshLock = function(self)
        local cfg = BarConfig(self.index)
        local pinned = cfg and cfg.pinned

        -- Under the cog when there is room for it, beside it when there is
        -- not. A mover is exactly as tall as its bar, and a tracking bar is 24
        -- high by default - two 20px buttons stacked need 44, so on those the
        -- padlock would hang out of the bottom of the box.
        self.lock:ClearAllPoints()
        if (self:GetHeight() or 0) >= 44 then
            self.lock:SetPoint("TOPRIGHT", self.cog, "BOTTOMRIGHT", 0, -2)
        else
            self.lock:SetPoint("TOPRIGHT", self.cog, "TOPLEFT", -2, 0)
        end

        self.lockGlyph:SetKind(pinned and "ui-lock" or "menu-unlock")
        local c = pinned and C.accent or C.textDim
        self.lockGlyph:SetColor(c[1], c[2], c[3])
        -- The pad has nothing to do on a pinned bar, and a row of arrows that
        -- silently ignore you is worse than no row at all.
        if self.pad then self.pad:SetShown(not pinned) end
    end

    mover.lock:SetScript("OnEnter", function()
        lockGlyph:SetColor(C.accent[1], C.accent[2], C.accent[3])
    end)
    mover.lock:SetScript("OnLeave", function() mover:RefreshLock() end)
    mover.lock:SetScript("OnClick", function()
        local cfg = BarConfig(mover.index)
        if not cfg then return end
        cfg.pinned = not cfg.pinned
        mover:RefreshLock()
        ns.Options:Refresh()
    end)

    -- FOUR ARROWS ON THE ELEMENT ITSELF, one pixel a click.
    --
    -- The keyboard already nudged, and the keyboard is the wrong hand: you are
    -- holding the mouse, you have just dragged the bar to nearly the right
    -- place, and the last three pixels are the whole point of nudging. Reaching
    -- for the arrow keys means letting go of what you are aiming.
    --
    -- Shift is the same multiplier the keys use, so the two are one behaviour
    -- with two ways in rather than two features.
    --
    -- ONE ROW, ON A TAB ABOVE THE BOX - not a four-way pad inside it.
    --
    -- Inside, the pad sat on top of the bar's own name and whatever the bar is
    -- drawing behind the overlay, and a 10px chevron over a spell icon is not
    -- readable at any colour. On its own strip above the frame it always has
    -- the same ground under it. It is a TAB: flush on the top edge, same fill
    -- and same outline, so it reads as part of the box rather than as a second
    -- floating thing near it.
    local ARROW = 16
    local PAD_INSET = 4
    local pad = CreateFrame("Frame", nil, mover)
    pad:SetSize(PAD_INSET * 2 + ARROW * 4 + 6, ARROW + 6)
    pad:SetPoint("BOTTOMLEFT", mover, "TOPLEFT", 0, 0)
    pad:SetFrameLevel(mover:GetFrameLevel() + 4)
    mover.pad = pad

    pad.bg = pad:CreateTexture(nil, "BACKGROUND")
    pad.bg:SetAllPoints(pad)
    pad.bg:SetColorTexture(C.sidebarBg[1], C.sidebarBg[2], C.sidebarBg[3], 0.92)

    pad.edge = ns.CreateBorder(pad, 1, "BORDER")
    pad.edge:SetColor(C.accentDim[1], C.accentDim[2], C.accentDim[3], 1)

    -- Reading order, left to right: across first, then up and down. That is
    -- the order it was asked for, and it is also the order the two pairs come
    -- in everywhere else in this addon - x before y.
    local NUDGERS = {
        { key = "LEFT",  dx = -1, dy = 0  },
        { key = "RIGHT", dx = 1,  dy = 0  },
        { key = "UP",    dx = 0,  dy = 1  },
        { key = "DOWN",  dx = 0,  dy = -1 },
    }

    for position, spec in ipairs(NUDGERS) do
        local button = CreateFrame("Button", nil, pad)
        button:SetSize(ARROW, ARROW)
        button:SetPoint("LEFT", pad, "LEFT",
            PAD_INSET + (position - 1) * (ARROW + 2), 0)

        local glyph = UI.Glyph(button, "caret" .. spec.key, 10, C.textDim)
        glyph:SetPoint("CENTER", button, "CENTER", 0, 0)

        button:SetScript("OnEnter", function()
            glyph:SetColor(C.accent[1], C.accent[2], C.accent[3])
        end)
        button:SetScript("OnLeave", function()
            glyph:SetColor(C.textDim[1], C.textDim[2], C.textDim[3])
        end)
        button:SetScript("OnClick", function()
            local step = IsShiftKeyDown() and NUDGE_FAST or NUDGE
            local cfg = BarConfig(mover.index)
            if not cfg or cfg.pinned then return end
            local x, y = Origin(cfg)
            ApplyMove(mover, x + spec.dx * step, y + spec.dy * step)
        end)
    end

    mover:RefreshLock()

    mover:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            -- The one gesture that is not about moving: get the overlay out
            -- of the way to check what is actually underneath it.
            if IsShiftKeyDown() then EditMode:SetOverlayShown(false) end
            return
        end

        SetSelected(self)

        -- CLICKING A BAR OPENS ITS SETTINGS. The tools panel already followed
        -- the selection, but you had to know that and press Tools first, so
        -- clicking a bar looked like it did nothing at all. Opened here rather
        -- than in SetSelected, because entering edit mode also selects and
        -- should not throw a panel across the screen on its own.
        if tools then
            tools.Refresh()
            tools:Show()
        end

        local cfg = BarConfig(self.index)
        if not cfg then return end

        -- A pinned bar selects and opens like any other. It just does not move.
        if cfg.pinned then return end

        local cursorX, cursorY = CursorPosition()
        local originX, originY = Origin(cfg)

        -- The gap between what we EDIT (the pinned point) and what we SNAP
        -- (the centre). Constant for the length of a drag, so it is worked
        -- out once rather than per frame.
        local centreX, centreY = ns.Screen:CentreOffset(self.index)
        dragging = {
            mover = self,
            cursorX = cursorX, cursorY = cursorY,
            originX = originX, originY = originY,
            toCentreX = (centreX or originX) - originX,
            toCentreY = (centreY or originY) - originY,
            -- An attached bar is dragged in its parent's terms, so screen
            -- snapping does not apply: the anchor already put it flush.
            anchored = cfg.anchor ~= nil,
        }
    end)

    mover:SetScript("OnMouseUp", function()
        if dragging then StopDrag() end
    end)

    mover:SetScript("OnEnter", function(self)
        self.coords:Show()
        UpdateReadout(self)
    end)
    mover:SetScript("OnLeave", function(self)
        if selected ~= self and not Prefs().showCoords then self.coords:Hide() end
    end)

    return mover
end

---------------------------------------------------------------------------
-- One handle - a single cell
--
-- Only in build mode. Every one of these sits exactly on a cell frame, so
-- what you grab is what you see, and the bar underneath never learns about
-- the mouse.
---------------------------------------------------------------------------
local function OpenCellMenu(handle)
    local cfg = ns.db.bars[handle.barIndex]
    if not cfg then return end

    local cell = handle.cellIndex
    local opts = ns.Layout.CellOpts(cfg, cell)
    local spellID = cfg.cells[cell]

    local items = {
        { text = (opts and opts.kind == "bar") and "Draw as an icon"
            or "Draw as a tracking bar",
          onClick = function()
              local write = ns.Layout.EnsureCellOpts(cfg, cell)
              -- The override is dropped rather than set to the bar's own
              -- kind: a cell that agrees with its bar should keep agreeing
              -- when the bar changes, not freeze today's answer.
              if write.kind then
                  write.kind = nil
              else
                  write.kind = (cfg.kind == "bar") and "icon" or "bar"
              end
              ns.Layout.TidyCellOpts(cfg, cell)
              ns.Bars:Changed(handle.barIndex)
          end },
        { text = (opts and opts.hidden) and "Show this cell" or "Hide this cell",
          onClick = function()
              local write = ns.Layout.EnsureCellOpts(cfg, cell)
              write.hidden = not write.hidden or nil
              ns.Layout.TidyCellOpts(cfg, cell)
              ns.Bars:Changed(handle.barIndex)
          end },
        { text = "Back into line",
          onClick = function()
              local write = ns.Layout.EnsureCellOpts(cfg, cell)
              -- Only the pair this arrangement uses. Straightening a cell in
              -- a grid must not quietly demolish where it sits in the puzzle
              -- on the other side of the pattern switch.
              local keyX, keyY = ns.Layout.OffsetKeys(cfg)
              write[keyX], write[keyY], write.scale = nil, nil, nil
              ns.Layout.TidyCellOpts(cfg, cell)
              ns.Bars:Changed(handle.barIndex)
          end },
    }

    local actions = {}
    if spellID then
        actions[#actions + 1] = { text = "Empty this cell", onClick = function()
            ns.Bars:ClearCell(handle.barIndex, cell)
        end }
    end
    if not ns.Layout.UsesGrid(cfg) then
        actions[#actions + 1] = { text = "Remove this cell", onClick = function()
            ns.Bars:RemoveCell(handle.barIndex, cell)
            picked = nil
            RefreshInspector()
        end }
    end

    UI.ShowMenu(handle, {
        width = 200,
        anchor = { "TOPLEFT", "BOTTOMLEFT", 0, -2 },
        items = items,
        actions = #actions > 0 and actions or nil,
    })
end

local function ScaleCell(barIndex, cellIndex, delta)
    local cfg = ns.db.bars[barIndex]
    if not cfg then return end

    local opts = ns.Layout.EnsureCellOpts(cfg, cellIndex)
    local scale = (opts.scale or 1) + delta * 0.1
    -- Clamped hard at both ends: a cell at 0.05 cannot be clicked again to
    -- undo, and one at 12 is a wall you cannot see past to fix it.
    opts.scale = math.max(0.3, math.min(4, math.floor(scale * 100 + 0.5) / 100))
    if math.abs(opts.scale - 1) < 0.001 then opts.scale = nil end

    ns.Layout.TidyCellOpts(cfg, cellIndex)
    ns.Bars:Changed(barIndex)
    RefreshInspector()
end

local function CreateHandle(barIndex, cellIndex)
    local handle = CreateFrame("Button", nil, overlay)
    handle.barIndex, handle.cellIndex = barIndex, cellIndex
    handle:SetFrameLevel(overlay:GetFrameLevel() + 30)
    handle:RegisterForClicks("LeftButtonDown", "RightButtonDown")
    handle:EnableMouseWheel(true)

    handle.tint = handle:CreateTexture(nil, "BACKGROUND")
    handle.tint:SetAllPoints(handle)
    handle.tint:SetColorTexture(1, 1, 1, 0.06)

    handle.edge = ns.CreateBorder(handle, 1, "BORDER")
    handle.edge:SetColor(C.accentDim[1], C.accentDim[2], C.accentDim[3], 0.8)

    handle.tag = UI.Label(handle, "", 10, C.textDim)
    handle.tag:SetPoint("TOPLEFT", handle, "TOPLEFT", 2, -2)
    handle.tag:SetWordWrap(false)

    handle:SetScript("OnEnter", function(self)
        if picked and picked.bar == self.barIndex and picked.cell == self.cellIndex then
            return
        end
        self.tint:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.16)
    end)
    handle:SetScript("OnLeave", function(self)
        if picked and picked.bar == self.barIndex and picked.cell == self.cellIndex then
            return
        end
        self.tint:SetColorTexture(1, 1, 1, 0.06)
    end)

    handle:SetScript("OnMouseWheel", function(self, delta)
        ScaleCell(self.barIndex, self.cellIndex, delta)
    end)

    handle:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            SelectCell(self.barIndex, self.cellIndex)
            OpenCellMenu(self)
            return
        end

        SelectCell(self.barIndex, self.cellIndex)

        local cfg = ns.db.bars[self.barIndex]
        local cell = ns.Screen:CellFrame(self.barIndex, self.cellIndex)
        if not (cfg and cell) then return end

        local cursorX, cursorY = CursorPosition()
        local point, _, relPoint, offsetX, offsetY = cell:GetPoint(1)

        -- Which two fields a drag lands in is the arrangement's business, not
        -- this file's - a puzzle's numbers are a position, a lattice's are an
        -- offset from a slot. See the header of Core/Layout.lua.
        local startX, startY = ns.Layout.GetOffset(cfg, self.cellIndex)

        cellDrag = {
            barIndex = self.barIndex, cellIndex = self.cellIndex,
            cursorX = cursorX, cursorY = cursorY,
            startX = startX, startY = startY,
            cell = cell,
            point = point, relPoint = relPoint,
            frameX = offsetX or 0, frameY = offsetY or 0,
        }
    end)

    handle:SetScript("OnMouseUp", function()
        if cellDrag then StopCellDrag() end
    end)

    return handle
end

-- Live feedback WITHOUT a render pass. A full pass walks Blizzard's frame
-- pools, and running that sixty times a second because a mouse is moving is
-- how a smooth drag becomes a stutter. The cell frame is moved directly and
-- the arrangement catches up once, on mouse up.
local function DragCell()
    if not cellDrag then return end

    if not IsMouseButtonDown("LeftButton") then
        StopCellDrag()
        return
    end

    local cfg = ns.db.bars[cellDrag.barIndex]
    if not cfg then return end

    local cursorX, cursorY = CursorPosition()
    local deltaX = cursorX - cellDrag.cursorX
    local deltaY = cursorY - cellDrag.cursorY

    local raster = IsAltKeyDown() and 0 or (cfg.raster or 0)
    local x = ns.Layout.SnapToRaster(cellDrag.startX + deltaX, raster)
    local y = ns.Layout.SnapToRaster(cellDrag.startY + deltaY, raster)

    ns.Layout.SetOffset(cfg, cellDrag.cellIndex, x, y)

    local cell = cellDrag.cell
    cell:ClearAllPoints()
    cell:SetPoint(cellDrag.point, cell:GetParent(), cellDrag.relPoint,
        cellDrag.frameX + (x - cellDrag.startX),
        cellDrag.frameY + (y - cellDrag.startY))

    RefreshInspector()
end

function StopCellDrag()
    if not cellDrag then return end
    local barIndex, cellIndex = cellDrag.barIndex, cellDrag.cellIndex
    cellDrag = nil

    local cfg = ns.db.bars[barIndex]
    if cfg then ns.Layout.TidyCellOpts(cfg, cellIndex) end
    ns.Bars:Changed(barIndex)
end

function SelectCell(barIndex, cellIndex)
    picked = { bar = barIndex, cell = cellIndex }

    for _, row in pairs(handles) do
        for _, handle in pairs(row) do
            local isIt = handle.barIndex == barIndex and handle.cellIndex == cellIndex
            handle.edge:SetColor(
                isIt and C.accent[1] or C.accentDim[1],
                isIt and C.accent[2] or C.accentDim[2],
                isIt and C.accent[3] or C.accentDim[3],
                isIt and 1 or 0.8)
            handle.tint:SetColorTexture(
                isIt and C.accent[1] or 1,
                isIt and C.accent[2] or 1,
                isIt and C.accent[3] or 1,
                isIt and 0.20 or 0.06)
        end
    end

    RefreshInspector()
    if tools and tools:IsShown() then tools.Refresh() end
end

---------------------------------------------------------------------------
-- Dragging a bar
--
-- Manual rather than StartMoving, because snapping means deciding where the
-- frame goes on every frame and StartMoving owns that decision itself.
---------------------------------------------------------------------------
function StopDrag()
    dragging = nil
    guideX:Hide()
    guideY:Hide()
end

---------------------------------------------------------------------------
-- The co-tank panel, moved the same way the bars are
--
-- The owner's call, and the right one: "das tank panel musst du wie die
-- cooldowns im edit mode bearbeiten koennen. der button kann da also raus".
-- A display that is moved from a button on a settings page is a display you
-- move blind - the window is over the place you are trying to put it. Every
-- other thing this addon draws is placed on the screen it lives on, and this
-- is now no different.
--
-- It reuses Snap, which needs nothing from the panel but a half-width: the
-- `index` argument is only ever used to leave a bar out of its own candidate
-- list, and nil is not a bar. So the panel lines up on the bars and the bars
-- line up on it, which is the whole point of snapping to something.
---------------------------------------------------------------------------
local tankMover, busterMover

local function TankPanel()
    local panel = ns.CoTanks and ns.CoTanks.panel
    if panel and panel:IsShown() then return panel end
    return nil
end

local function ApplyTankMove(x, y)
    local db = ns.db.coTanks
    -- Written in CENTRE terms, like a bar with no anchor. The pinned point is
    -- forced to CENTER because that is what the numbers below now mean.
    db.point, db.relPoint = "CENTER", "CENTER"
    db.x, db.y = math.floor(x + 0.5), math.floor(y + 0.5)
    ns.CoTanks:ApplyLayout()
end

-- The Timeline panel, moved by the same machinery. Its numbers were born in
-- CENTRE terms, so Apply is one write and one refresh.
local function BusterPanel()
    local panel = ns.Busters and ns.Busters.panel
    if panel and panel:IsShown() then return panel end
    return nil
end

local function ApplyBusterMove(x, y)
    local cfg = ns.Busters:Config()
    cfg.x, cfg.y = math.floor(x + 0.5), math.floor(y + 0.5)
    ns.Busters:ApplyPosition()
end

-- label and origin are the only things the two panel movers disagree about,
-- so they are the only parameters. A third copy of this builder would be
-- the drift the reminders section warns about one screen down.
local function CreatePanelMover(label, getOrigin)
    local mover = CreateFrame("Button", nil, overlay)
    mover:SetFrameLevel(overlay:GetFrameLevel() + 10)
    mover:RegisterForDrag("LeftButton")
    mover:Hide()

    mover.bg = mover:CreateTexture(nil, "BACKGROUND")
    mover.bg:SetAllPoints(mover)
    mover.bg:SetColorTexture(C.sidebarBg[1], C.sidebarBg[2], C.sidebarBg[3], 0.92)

    mover.edge = ns.CreateBorder(mover, 1, "BORDER")
    mover.edge:SetColor(C.accentDim[1], C.accentDim[2], C.accentDim[3], 1)

    local text = CreateFrame("Frame", nil, mover)
    text:SetAllPoints(mover)
    text:SetFrameLevel(mover:GetFrameLevel() + 2)
    text:SetClipsChildren(true)

    mover.name = UI.Label(text, label, 12, C.text)
    mover.name:SetPoint("CENTER", text, "CENTER", 0, 0)
    mover.name:SetWordWrap(false)

    mover.coords = UI.Label(text, "", 10, C.textDim)
    mover.coords:SetPoint("TOPLEFT", text, "TOPLEFT", 4, -3)
    mover.coords:SetWordWrap(false)

    mover:SetScript("OnDragStart", function(self)
        local cursorX, cursorY = CursorPosition()
        local originX, originY = getOrigin()
        self.grab = {
            cursorX = cursorX, cursorY = cursorY,
            originX = originX, originY = originY,
        }
    end)

    local function Stop(self)
        self.grab = nil
        ShowGuide(guideX, nil, true)
        ShowGuide(guideY, nil, false)
    end
    mover:SetScript("OnDragStop", Stop)
    mover:SetScript("OnMouseUp", Stop)

    return mover
end

-- Dragged from the overlay's own OnUpdate, for the same reason the bars are:
-- the button can be let go anywhere, including off the edge of the screen,
-- and OnMouseUp only fires on the frame it went down on. Without this the
-- panel stays glued to the cursor.
local function DragPanel(mover, getPanel, apply)
    if not (mover and mover.grab) then return end

    if not IsMouseButtonDown("LeftButton") then
        mover.grab = nil
        ShowGuide(guideX, nil, true)
        ShowGuide(guideY, nil, false)
        return
    end

    local panel = getPanel()
    if not panel then return end

    local cursorX, cursorY = CursorPosition()
    local x = mover.grab.originX + (cursorX - mover.grab.cursorX)
    local y = mover.grab.originY + (cursorY - mover.grab.cursorY)

    -- Snapping is what dragging DOES here too, and Alt suspends it for the
    -- length of one drag. Same rule, same escape hatch, so there is one thing
    -- to learn rather than two.
    local lineX, lineY
    if not IsAltKeyDown() then
        local scale = panel:GetScale()
        if not scale or scale <= 0 then scale = 1 end
        local snappedX, guideLineX = Snap(x, nil, panel:GetWidth() * scale / 2, "x")
        local snappedY, guideLineY = Snap(y, nil, panel:GetHeight() * scale / 2, "y")
        x, y = snappedX, snappedY
        lineX, lineY = guideLineX, guideLineY
    end

    apply(x, y)
    ShowGuide(guideX, lineX, true)
    ShowGuide(guideY, lineY, false)
end

-- Placed over its panel, sized to it, and only there at all when there is a
-- panel to place it over.
local function RefreshPanelMover(mover, getPanel, x, y)
    local panel = getPanel()
    if not (panel and EditMode.overlayShown) then
        mover:Hide()
        return
    end

    mover:ClearAllPoints()
    mover:SetAllPoints(panel)
    mover.coords:SetText(string.format("%d, %d", x or 0, y or 0))
    mover.coords:SetShown(Prefs().showCoords or mover.grab ~= nil)
    mover:Show()
end

local function RefreshTankMover()
    if not tankMover then
        tankMover = CreatePanelMover("Co-tanks", function()
            return ns.db.coTanks.x or 0, ns.db.coTanks.y or 0
        end)
    end
    RefreshPanelMover(tankMover, TankPanel, ns.db.coTanks.x, ns.db.coTanks.y)
end

local function RefreshBusterMover()
    if not busterMover then
        busterMover = CreatePanelMover("Timeline", function()
            local cfg = ns.Busters:Config()
            return cfg.x or 0, cfg.y or -220
        end)
    end
    local cfg = ns.Busters and ns.Busters:Config() or {}
    RefreshPanelMover(busterMover, BusterPanel, cfg.x, cfg.y)
end

---------------------------------------------------------------------------
-- The reminders, moved the same way
--
-- Same three functions as the panel above, over a LIST rather than one frame.
-- Everything this addon draws is placed on the screen it lives on, and a
-- message that appears in the middle of a fight is the last thing anybody
-- wants to position from a settings window.
--
-- THE OVERLAY FORCES THEM VISIBLE. A reminder is only on screen when its
-- condition fires, so without Reminders:SetPlacing there would be nothing to
-- drag except during the exact moment you are too busy to drag it.
---------------------------------------------------------------------------
local reminderMovers = {}

local function ApplyReminderMove(index, x, y)
    local cfg = ns.Reminders:Get(index)
    if not cfg then return end
    -- Centre terms, like the panel and like a bar with no anchor.
    cfg.point, cfg.relPoint = "CENTER", "CENTER"
    cfg.x, cfg.y = math.floor(x + 0.5), math.floor(y + 0.5)
    ns.Reminders:Style(index)
end

local function CreateReminderMover(index)
    local mover = CreateFrame("Button", nil, overlay)
    mover:SetFrameLevel(overlay:GetFrameLevel() + 10)
    mover:RegisterForDrag("LeftButton")
    mover:Hide()

    mover.bg = mover:CreateTexture(nil, "BACKGROUND")
    mover.bg:SetAllPoints(mover)
    mover.bg:SetColorTexture(C.sidebarBg[1], C.sidebarBg[2], C.sidebarBg[3], 0.55)

    mover.edge = ns.CreateBorder(mover, 1, "BORDER")
    mover.edge:SetColor(C.accentDim[1], C.accentDim[2], C.accentDim[3], 1)

    -- The label sits ABOVE the box rather than in it. The box is exactly the
    -- size of the words the reminder itself is showing, and a second caption
    -- inside it would be printed over the thing being placed.
    mover.name = UI.Label(mover, "", 11, C.textDim)
    mover.name:SetPoint("BOTTOM", mover, "TOP", 0, 3)
    mover.name:SetWordWrap(false)

    mover.coords = UI.Label(mover, "", 10, C.textDim)
    mover.coords:SetPoint("TOP", mover, "BOTTOM", 0, -3)
    mover.coords:SetWordWrap(false)

    mover:SetScript("OnDragStart", function(self)
        local cfg = ns.Reminders:Get(self.dkIndex)
        if not cfg then return end
        local cursorX, cursorY = CursorPosition()
        self.grab = {
            cursorX = cursorX, cursorY = cursorY,
            originX = cfg.x or 0, originY = cfg.y or 0,
        }
    end)

    local function Stop(self)
        self.grab = nil
        ShowGuide(guideX, nil, true)
        ShowGuide(guideY, nil, false)
    end
    mover:SetScript("OnDragStop", Stop)
    mover:SetScript("OnMouseUp", Stop)

    mover.dkIndex = index
    return mover
end

local function DragReminders()
    for index, mover in ipairs(reminderMovers) do
        if mover.grab then
            if not IsMouseButtonDown("LeftButton") then
                mover.grab = nil
                ShowGuide(guideX, nil, true)
                ShowGuide(guideY, nil, false)
                return
            end

            local frame = ns.Reminders:Frame(index)
            if not frame then return end

            local cursorX, cursorY = CursorPosition()
            local x = mover.grab.originX + (cursorX - mover.grab.cursorX)
            local y = mover.grab.originY + (cursorY - mover.grab.cursorY)

            local lineX, lineY
            if not IsAltKeyDown() then
                local scale = frame:GetScale()
                if not scale or scale <= 0 then scale = 1 end
                local snappedX, gx = Snap(x, nil, frame:GetWidth() * scale / 2, "x")
                local snappedY, gy = Snap(y, nil, frame:GetHeight() * scale / 2, "y")
                x, y = snappedX, snappedY
                lineX, lineY = gx, gy
            end

            ApplyReminderMove(index, x, y)
            ShowGuide(guideX, lineX, true)
            ShowGuide(guideY, lineY, false)
            return
        end
    end
end

local function RefreshReminderMovers()
    local count = ns.Reminders:Count()

    for index = 1, count do
        local mover = reminderMovers[index]
        if not mover then
            mover = CreateReminderMover(index)
            reminderMovers[index] = mover
        end

        local frame = ns.Reminders:Frame(index)
        local cfg = ns.Reminders:Get(index)
        -- Not while the options page has it: the frame is then parented into
        -- a card inside a window, and a mover pinned to it would be a box
        -- floating over the settings.
        if not (frame and cfg and EditMode.overlayShown and not ns.Reminders.hosted) then
            mover:Hide()
        else
            mover:ClearAllPoints()
            mover:SetAllPoints(frame)
            mover.name:SetText(ns.Reminders:Label(cfg, index))
            mover.coords:SetText(string.format("%d, %d", cfg.x or 0, cfg.y or 0))
            mover.coords:SetShown(Prefs().showCoords or mover.grab ~= nil)
            mover:Show()
        end
    end

    for index = count + 1, #reminderMovers do reminderMovers[index]:Hide() end
end

local function OnUpdate()
    if cellDrag then DragCell() end
    DragPanel(tankMover, TankPanel, ApplyTankMove)
    DragPanel(busterMover, BusterPanel, ApplyBusterMove)
    DragReminders()
    if not dragging then return end

    -- The button can be let go anywhere, including over another window or off
    -- the edge of the screen, and OnMouseUp only fires on the frame it went
    -- down on. Without this the bar stays glued to the cursor.
    if not IsMouseButtonDown("LeftButton") then
        StopDrag()
        return
    end

    local mover = dragging.mover
    local bar = ns.Screen:BarFrame(mover.index)
    if not bar then return end

    local cursorX, cursorY = CursorPosition()
    local x = dragging.originX + (cursorX - dragging.cursorX)
    local y = dragging.originY + (cursorY - dragging.cursorY)

    -- SNAPPING IS NOT A SETTING ANY MORE. It is what dragging DOES.
    --
    -- It used to hang off a switch in a panel you have to open first, and a
    -- feature that silently does nothing until you find its switch is a
    -- feature that does not work - which is exactly how it was reported. Alt
    -- is the escape hatch, held in the moment, on the drag that needs it.
    local lineX, lineY
    if not (dragging.anchored or IsAltKeyDown()) then
        -- Snapped in CENTRE terms and written back in pinned-point terms, so
        -- a bar pinned by its left edge still lines up by its middle.
        local centreX, guideLineX = Snap(x + dragging.toCentreX, mover.index,
            bar:GetWidth() / 2, "x")
        local centreY, guideLineY = Snap(y + dragging.toCentreY, mover.index,
            bar:GetHeight() / 2, "y")

        x, y = centreX - dragging.toCentreX, centreY - dragging.toCentreY
        lineX, lineY = guideLineX, guideLineY
    end

    ApplyMove(mover, x, y)
    ShowGuide(guideX, lineX, true)
    ShowGuide(guideY, lineY, false)
end

---------------------------------------------------------------------------
-- Keyboard
--
-- Propagation is on by default and only switched off for a key that was
-- actually used, so edit mode never swallows a keybind it has no business
-- touching.
---------------------------------------------------------------------------
local ARROWS = {
    UP    = {  0,  1 },
    DOWN  = {  0, -1 },
    LEFT  = { -1,  0 },
    RIGHT = {  1,  0 },
}

-- In build mode the arrows nudge the SELECTED CELL; in move mode they nudge
-- the selected bar. Same keys, same feel, one level down.
local function NudgeCell(where, direction, step)
    local cfg = ns.db.bars[where.bar]
    if not cfg then return end

    local x, y = ns.Layout.GetOffset(cfg, where.cell)
    ns.Layout.SetOffset(cfg, where.cell,
        x + direction[1] * step, y + direction[2] * step)

    ns.Layout.TidyCellOpts(cfg, where.cell)
    ns.Bars:Changed(where.bar)
    RefreshInspector()
end

-- SetPropagateKeyboardInput IS PROTECTED IN COMBAT.
--
-- Calling it from addon code while the player is in combat raises
-- ADDON_ACTION_BLOCKED - reported from a training dummy, closing unlock mode
-- mid-fight. It is not a taint problem and there is no way around it: the
-- call simply may not happen in combat.
--
-- So it does not. The cost is that the arrow keys do not nudge while you are
-- fighting, which is the right thing to give up: propagation defaults to ON,
-- so every key reaches the game as usual and nothing is swallowed.
local function Propagate(frame, state)
    if InCombatLockdown() then return false end
    frame:SetPropagateKeyboardInput(state)
    return true
end

local function BuildKeyCatcher()
    keyCatcher = CreateFrame("Frame", nil, UIParent)
    keyCatcher:EnableKeyboard(true)
    Propagate(keyCatcher, true)
    keyCatcher:Hide()

    -- Combat can start between a key going down and coming back up, which
    -- would leave propagation switched off for the whole fight with no way to
    -- switch it back. This puts it right the moment the fight ends.
    keyCatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    keyCatcher:SetScript("OnEvent", function(self)
        Propagate(self, true)
    end)

    keyCatcher:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            Propagate(self, false)
            EditMode:SetUnlocked(false)
            return
        end

        if key == "TAB" and mode == "build" and picked then
            Propagate(self, false)
            local cfg = ns.db.bars[picked.bar]
            if cfg then
                local count = ns.Bars:CellCount(cfg)
                SelectCell(picked.bar, (picked.cell % count) + 1)
            end
            return
        end

        if (key == "DELETE" or key == "BACKSPACE") and mode == "build" and picked then
            Propagate(self, false)
            ns.Bars:ClearCell(picked.bar, picked.cell)
            return
        end

        local direction = ARROWS[key]
        if not direction then
            Propagate(self, true)
            return
        end

        local step = IsShiftKeyDown() and NUDGE_FAST or NUDGE

        if mode == "build" and picked then
            Propagate(self, false)
            NudgeCell(picked, direction, step)
            return
        end

        if not selected then
            Propagate(self, true)
            return
        end

        Propagate(self, false)
        local cfg = BarConfig(selected.index)
        if not cfg then return end

        -- Pinned means pinned, whichever hand is asking. The arrow keys and
        -- the arrow buttons are one behaviour with two ways in, so a rule that
        -- held for only one of them would be the bug, not the feature.
        if cfg.pinned then
            ns.Print(cfg.name or "That bar", "is pinned - the padlock on it "
                .. "lets it move again.")
            return
        end

        local x, y = Origin(cfg)
        ApplyMove(selected, x + direction[1] * step, y + direction[2] * step)
    end)

    keyCatcher:SetScript("OnKeyUp", function(self)
        Propagate(self, true)
    end)
end

---------------------------------------------------------------------------
-- The palette - every spell, one click from a cell
--
-- The whole reason build mode exists as something you do ON SCREEN rather
-- than in a window: pick the cell, pick the spell, see it land. Opening a
-- settings window to fill a slot you are looking at is the long way round.
---------------------------------------------------------------------------
local PALETTE_COLUMNS = 6
local PALETTE_ICON = 34

local function AssignPicked(spellID)
    if not picked then
        ns.Print("Pick a cell first - click one of the outlined slots.")
        return
    end

    ns.Bars:SetCell(picked.bar, picked.cell, spellID)

    -- Straight on to the next one, so filling a bar is six clicks rather than
    -- twelve. Wraps, and stops being helpful at the end rather than looping
    -- silently back over what was just done.
    local cfg = ns.db.bars[picked.bar]
    if cfg then
        local count = ns.Bars:CellCount(cfg)
        if picked.cell < count then SelectCell(picked.bar, picked.cell + 1) end
    end
    RefreshInspector()
end

local function BuildPalette()
    palette = CreateFrame("Frame", nil, overlay)
    palette:SetSize(PALETTE_COLUMNS * (PALETTE_ICON + 4) + 24, 340)
    palette:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
    palette:SetFrameLevel(overlay:GetFrameLevel() + 40)
    palette:EnableMouse(true)
    palette:SetMovable(true)
    palette:RegisterForDrag("LeftButton")
    palette:SetScript("OnDragStart", palette.StartMoving)
    palette:SetScript("OnDragStop", palette.StopMovingOrSizing)
    palette:SetClampedToScreen(true)
    palette:Hide()

    UI.Fill(palette, "BACKGROUND", C.windowBg)
    local edge = ns.CreateBorder(palette, 1, "BORDER")
    edge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)

    local title = UI.Label(palette, "Spells", 13, C.text)
    title:SetPoint("TOPLEFT", palette, "TOPLEFT", 12, -10)

    local hint = UI.Label(palette, "Click a slot, then a spell.", 10, C.textFaint)
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)

    local rule = UI.Separator(palette, true)
    rule:SetPoint("TOPLEFT", palette, "TOPLEFT", 0, -46)
    rule:SetPoint("TOPRIGHT", palette, "TOPRIGHT", 0, -46)

    local body = CreateFrame("Frame", nil, palette)
    body:SetPoint("TOPLEFT", palette, "TOPLEFT", 10, -54)
    body:SetPoint("BOTTOMRIGHT", palette, "BOTTOMRIGHT", -8, 10)

    local scroll, content = UI.ScrollArea(body,
        PALETTE_COLUMNS * (PALETTE_ICON + 4))
    palette.scroll, palette.content = scroll, content
    palette.buttons = {}

    palette.Refresh = function()
        local catalogue = ns.CDM:Catalogue()

        for position, entry in ipairs(catalogue) do
            local button = palette.buttons[position]
            if not button then
                button = CreateFrame("Button", nil, content)
                button:SetSize(PALETTE_ICON, PALETTE_ICON)

                button.icon = button:CreateTexture(nil, "ARTWORK")
                button.icon:SetAllPoints(button)
                button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                button.edge = ns.CreateBorder(button, 1, "OVERLAY")
                button.edge:SetColor(0, 0, 0, 1)

                button:SetScript("OnEnter", function(self)
                    self.edge:SetColor(C.accent[1], C.accent[2], C.accent[3], 1)
                end)
                button:SetScript("OnLeave", function(self)
                    self.edge:SetColor(0, 0, 0, 1)
                end)

                palette.buttons[position] = button
            end

            local column = (position - 1) % PALETTE_COLUMNS
            local row = math.floor((position - 1) / PALETTE_COLUMNS)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", content, "TOPLEFT",
                column * (PALETTE_ICON + 4), -row * (PALETTE_ICON + 4))

            button.icon:SetTexture(entry.icon)
            -- A spell you have not talented is shown greyed rather than left
            -- out: a bar can be built for the spec you are about to switch
            -- into, and a list that silently drops half the class reads as
            -- broken.
            button.icon:SetDesaturated(not entry.known)
            button:SetScript("OnClick", function() AssignPicked(entry.spellID) end)
            button:Show()
        end

        for position = #catalogue + 1, #palette.buttons do
            palette.buttons[position]:Hide()
        end

        local rows = math.ceil(#catalogue / PALETTE_COLUMNS)
        content:SetHeight(math.max(1, rows * (PALETTE_ICON + 4)))
        if scroll.Update then scroll.Update() end
    end
end

---------------------------------------------------------------------------
-- The tool panel
--
-- Everything you would otherwise have to close the overlay, open the window,
-- change one number and come back for. Two groups, and the split is what each
-- one belongs to: the SCREEN settings are how you work, and they are saved
-- because they are a habit; the BAR settings are the one you have selected,
-- and they are the same numbers the options page edits.
--
-- Deliberately not every setting. Colours, fonts and effects are things you
-- judge by looking at one bar closely, and the window is the place for that.
-- What is here is what you judge by looking at the WHOLE SCREEN, which is
-- exactly what you cannot do from inside a window covering it.
---------------------------------------------------------------------------

-- Which bar the panel is editing: the one whose cell is picked in build mode,
-- otherwise the selected mover. Nil is a real answer and the panel says so
-- rather than quietly editing bar 1.
local function CurrentBar()
    if mode == "build" and picked then
        return picked.bar, ns.db.bars[picked.bar]
    end
    if selected then return selected.index, ns.db.bars[selected.index] end
    return nil, nil
end

local function BuildTools()
    tools = CreateFrame("Frame", nil, overlay)
    tools:SetSize(292, 392)
    tools:SetPoint("LEFT", UIParent, "LEFT", 40, 0)
    tools:SetFrameLevel(overlay:GetFrameLevel() + 40)
    tools:EnableMouse(true)
    tools:SetMovable(true)
    tools:RegisterForDrag("LeftButton")
    tools:SetScript("OnDragStart", tools.StartMoving)
    tools:SetScript("OnDragStop", tools.StopMovingOrSizing)
    tools:SetClampedToScreen(true)
    tools:Hide()

    UI.Fill(tools, "BACKGROUND", C.windowBg)
    local edge = ns.CreateBorder(tools, 1, "BORDER")
    edge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)

    local title = UI.Label(tools, "Tools", 13, C.text)
    title:SetPoint("TOPLEFT", tools, "TOPLEFT", 12, -10)

    local rule = UI.Separator(tools, true)
    rule:SetPoint("TOPLEFT", tools, "TOPLEFT", 0, -32)
    rule:SetPoint("TOPRIGHT", tools, "TOPRIGHT", 0, -32)

    local y = -42
    local INNER = 12
    local WIDTH = 292 - INNER * 2
    local refreshers = {}

    local function Heading(text)
        local label = UI.Label(tools, text:upper(), 10, C.textFaint)
        label:SetPoint("TOPLEFT", tools, "TOPLEFT", INNER, y)
        y = y - 18
        return label
    end

    local function Slider(cfg)
        local slider = UI.MiniSlider(tools, cfg)
        slider:SetPoint("TOPLEFT", tools, "TOPLEFT", INNER, y)
        slider:SetWidth(WIDTH)
        -- ASK THE WIDGET how tall it is. This stepped down by a hardcoded 23
        -- while the control was 20 tall, and the moment the control became a
        -- 28-tall stepper every row in this panel overlapped the next one.
        -- A layout that repeats a number the widget already knows is a layout
        -- that breaks the next time the widget changes.
        y = y - (slider:GetHeight() + 3)
        refreshers[#refreshers + 1] = slider
        return slider
    end

    -- A switch that says what it IS, not what pressing it would do. "Snap:
    -- on" reads at a glance across a screen; "Turn snapping off" has to be
    -- parsed every single time.
    local function Switch(text, get, set, width, sameLine)
        local button
        button = UI.Button(tools, text, width or WIDTH, function()
            set(not get())
            if button.Refresh then button.Refresh() end
        end)
        button:SetHeight(21)

        if sameLine then
            button:SetPoint("TOPRIGHT", tools, "TOPRIGHT", -INNER, y + 24)
        else
            button:SetPoint("TOPLEFT", tools, "TOPLEFT", INNER, y)
            y = y - 24
        end

        button.Refresh = function()
            local on = get() and true or false
            button:SetText(text .. ":  " .. (on and "on" or "off"))
            button.label:SetTextColor(
                on and C.accent[1] or C.textFaint[1],
                on and C.accent[2] or C.textFaint[2],
                on and C.accent[3] or C.textFaint[3])
        end
        refreshers[#refreshers + 1] = button
        return button
    end

    -----------------------------------------------------------------------
    -- The screen
    -----------------------------------------------------------------------
    Heading("Screen")

    local half = math.floor((WIDTH - 6) / 2)

    Switch("Grid", function() return gridLines and gridLines:IsShown() end,
        function(value) EditMode:SetGridShown(value) end, half)
    Switch("Snap to it", function() return Prefs().snapToGrid end,
        function(value)
            Prefs().snapToGrid = value
            RefreshInspector()
        end, half, true)

    Slider({
        label = "Grid", labelWidth = 60, min = 8, max = 160, step = 4,
        get = function() return Prefs().gridStep end,
        set = function(value)
            Prefs().gridStep = value
            DrawGrid()
        end,
    })

    -- There was a "Snapping" switch here, and it is gone on purpose: snapping
    -- is what dragging does now, and Alt suspends it for one drag. A switch
    -- whose off position makes a feature silently do nothing is the switch
    -- that gets left off by accident and then reported as a broken feature.
    Switch("Coordinates", function() return Prefs().showCoords end,
        function(value)
            Prefs().showCoords = value
            EditMode:Refresh()
        end, WIDTH)

    Slider({
        label = "Catch", labelWidth = 60, min = 2, max = 40, step = 1,
        get = function() return Prefs().snapDistance end,
        set = function(value) Prefs().snapDistance = value end,
    })

    Slider({
        label = "Dim", labelWidth = 60, min = 0, max = 0.8, step = 0.05,
        get = function() return Prefs().dim end,
        set = function(value)
            Prefs().dim = value
            if overlay then overlay.dim:SetColorTexture(0, 0, 0, value) end
        end,
    })

    -----------------------------------------------------------------------
    -- The selected bar
    -----------------------------------------------------------------------
    y = y - 8
    local barHeading = Heading("Nothing selected")

    -- Every one of these edits the bar the panel is pointing at, and every
    -- one is the SAME field the options page edits. One writer, so there is
    -- no version of a number that only one of the two knows about.
    local function BarGet(key, fallback)
        return function()
            local _, cfg = CurrentBar()
            return cfg and cfg[key] or fallback
        end
    end
    local function BarSet(key)
        return function(value)
            local index, cfg = CurrentBar()
            if not cfg then return end
            cfg[key] = value
            ns.Bars:Changed(index)
        end
    end

    local patternBtn = UI.Button(tools, "Pattern", WIDTH, function()
        local index, cfg = CurrentBar()
        if not cfg then return end

        -- Cycles rather than opening a menu. There are five, you are looking
        -- at the screen while you press it, and the answer to "what does this
        -- one look like" is one click away either direction.
        local at = 1
        for position, entry in ipairs(ns.LAYOUTS) do
            if entry.value == (cfg.layout or "grid") then at = position end
        end
        local next_ = ns.LAYOUTS[(at % #ns.LAYOUTS) + 1]
        ns.Bars:SetLayout(index, next_.value)
    end)
    patternBtn:SetHeight(21)
    patternBtn:SetPoint("TOPLEFT", tools, "TOPLEFT", INNER, y)
    y = y - 25

    local rowsSlider = Slider({
        label = "Rows", labelWidth = 60, min = 1, max = 12, step = 1,
        get = BarGet("rows", 1),
        set = function(value)
            local index, cfg = CurrentBar()
            if cfg then ns.Bars:SetGrid(index, value, cfg.columns) end
        end,
    })
    local colsSlider = Slider({
        label = "Columns", labelWidth = 60, min = 1, max = 12, step = 1,
        get = BarGet("columns", 1),
        set = function(value)
            local index, cfg = CurrentBar()
            if cfg then ns.Bars:SetGrid(index, cfg.rows, value) end
        end,
    })
    local slotsSlider = Slider({
        label = "Slots", labelWidth = 60, min = 1, max = 40, step = 1,
        get = BarGet("freeCount", 6), set = BarSet("freeCount"),
    })

    local iconSlider = Slider({
        label = "Icon", labelWidth = 60, min = 16, max = 100, step = 2,
        get = BarGet("iconSize", 40), set = BarSet("iconSize"),
    })
    local widthSlider = Slider({
        label = "Width", labelWidth = 60, min = 60, max = 400, step = 5,
        get = BarGet("barWidth", 200), set = BarSet("barWidth"),
    })
    local heightSlider = Slider({
        label = "Height", labelWidth = 60, min = 10, max = 60, step = 2,
        get = BarGet("barHeight", 24), set = BarSet("barHeight"),
    })

    Slider({
        label = "Spacing", labelWidth = 60, min = 0, max = 24, step = 1,
        get = BarGet("spacing", 4), set = BarSet("spacing"),
    })
    Slider({
        label = "Row gap", labelWidth = 60, min = 0, max = 24, step = 1,
        get = BarGet("lineSpacing", 4), set = BarSet("lineSpacing"),
    })
    Slider({
        label = "Scale", labelWidth = 60, min = 0.4, max = 2.5, step = 0.05,
        get = BarGet("scale", 1), set = BarSet("scale"),
    })

    -- Centring, from here, because it is the one placement you cannot do by
    -- eye and the one people want most often.
    y = y - 4
    local third = math.floor((WIDTH - 12) / 3)

    local function Centre(text, fn, offset)
        local button = UI.Button(tools, text, third, function()
            local index, cfg = CurrentBar()
            if not (cfg and movers[index]) then return end
            fn(movers[index], cfg)
        end)
        button:SetHeight(21)
        button:SetPoint("TOPLEFT", tools, "TOPLEFT", INNER + offset * (third + 6), y)
        return button
    end

    -- Through CentringOffsets, not 0: a bar pinned by an edge stores a number
    -- that is not its centre, and writing 0 there moves the EDGE onto the
    -- centre line. See the comment on that function.
    Centre("Centre", function(mover, cfg)
        local x, y2 = CentringOffsets(mover.index, cfg)
        ApplyMove(mover, x, y2)
    end, 0)
    Centre("Across", function(mover, cfg)
        local x = CentringOffsets(mover.index, cfg)
        ApplyMove(mover, x, select(2, Origin(cfg)))
    end, 1)
    Centre("Down", function(mover, cfg)
        local _, y2 = CentringOffsets(mover.index, cfg)
        ApplyMove(mover, (Origin(cfg)), y2)
    end, 2)
    y = y - 25

    -----------------------------------------------------------------------
    -- The cell you picked
    --
    -- The same overrides the options window offers, HERE - because this is
    -- where you are looking at the real bar rather than at a preview of it,
    -- and a colour is a thing you judge against the screen it will live on.
    -- Both write the same fields through the same model calls, so neither can
    -- know a value the other does not.
    -----------------------------------------------------------------------
    local cellHeading = Heading("Nothing picked")

    -- Returns the bar INDEX as well, so nothing below has to reach back into
    -- `picked` - which the checker cannot prove is still there, and which a
    -- deselect between the two reads really would empty.
    local function PickedCell()
        if not picked then return nil end
        local cfg = BarConfig(picked.bar)
        if not cfg then return nil end
        return cfg, picked.cell, picked.bar
    end

    -- Reads the cell's own value, or the bar's while it is still following.
    local function CellGet(key, fallback)
        return function()
            local cfg, cell = PickedCell()
            if not cfg then return fallback end
            local opts = ns.Layout.CellOpts(cfg, cell)
            local look = opts and opts.look
            if look and look[key] ~= nil then return look[key] end
            if cfg[key] ~= nil then return cfg[key] end
            return fallback
        end
    end
    local function CellSet(key)
        return function(value)
            local cfg, cell, barIndex = PickedCell()
            if not cfg then return end
            ns.Bars:SetCellLook(cfg, cell, key, value)
            ns.Bars:Changed(barIndex)
        end
    end

    local cellScale = Slider({
        label = "Size", labelWidth = 60, min = 0.5, max = 3, step = 0.05,
        get = function()
            local cfg, cell = PickedCell()
            local opts = cfg and ns.Layout.CellOpts(cfg, cell)
            return (opts and opts.scale) or 1
        end,
        set = function(value)
            local cfg, cell, barIndex = PickedCell()
            if not cfg then return end
            ns.Layout.EnsureCellOpts(cfg, cell).scale = value
            ns.Layout.TidyCellOpts(cfg, cell)
            ns.Bars:Changed(barIndex)
        end,
    })

    -- UI.Swatch returns the ROW it was given, and the row here is a bare
    -- table standing in for one. The control is what needs anchoring, and it
    -- comes back on row.control.
    --
    -- Calling ClearAllPoints on the table instead threw, and a throw here
    -- takes the whole tool panel with it - grid, grid size, everything below
    -- this line simply never got built.
    local cellRow = { slot = tools }
    UI.Swatch(cellRow,
        function()
            local colour = CellGet("fillColor", { 1, 1, 1 })()
            return colour[1], colour[2], colour[3]
        end,
        function(r, g, b) CellSet("fillColor")({ r, g, b }) end)

    local cellColour = cellRow.control
    cellColour:ClearAllPoints()
    cellColour:SetPoint("TOPLEFT", tools, "TOPLEFT", INNER, y)
    local colourLabel = UI.Label(tools, "Colour", 11, C.textFaint)
    colourLabel:SetPoint("LEFT", cellColour, "RIGHT", 8, 0)
    y = y - 24

    local cellGrow = Switch("Fill up",
        function() return CellGet("fillGrow", false)() end,
        function(value) CellSet("fillGrow")(value) end)

    -- Four answers, so it cycles rather than switching. Same shape as the
    -- Pattern button above it: you are looking at the bar while you press it,
    -- and one more press is always the way back.
    local cellSide = UI.Button(tools, "Direction", WIDTH, function()
        local at = 1
        local current = CellGet("fillDirection", "right")()
        for position, entry in ipairs(ns.FILL_DIRECTIONS) do
            if entry.value == current then at = position end
        end
        CellSet("fillDirection")(
            ns.FILL_DIRECTIONS[(at % #ns.FILL_DIRECTIONS) + 1].value)
    end)
    cellSide:SetHeight(21)
    cellSide:SetPoint("TOPLEFT", tools, "TOPLEFT", INNER, y)
    y = y - 25
    cellSide.Refresh = function()
        local entry = ns.Layout.FillDirection(CellGet("fillDirection", "right")())
        cellSide:SetText("Fill:  " .. entry.text)
    end
    refreshers[#refreshers + 1] = cellSide

    local cellReset = UI.Button(tools, "Follow the bar again", WIDTH, function()
        local cfg, cell, barIndex = PickedCell()
        if not cfg then return end
        ns.Bars:ClearCellLook(cfg, cell)
        ns.Bars:Changed(barIndex)
        tools.Refresh()
    end)
    cellReset:SetHeight(21)
    cellReset:SetPoint("TOPLEFT", tools, "TOPLEFT", INNER, y)
    y = y - 25

    tools:SetHeight(-y + 10)

    tools.Refresh = function()
        local index, cfg = CurrentBar()

        -- The picked cell's own row of controls. They stand down entirely
        -- when nothing is picked rather than editing whatever was last
        -- touched, which is the one way this panel could do real damage.
        local cellCfg, cellIndex = PickedCell()
        local spellID = cellCfg and cellCfg.cells and cellCfg.cells[cellIndex]
        cellHeading:SetText(cellCfg
            and ((spellID and (ns.SpellName(spellID) or "CELL") or "EMPTY CELL")
                .. (ns.Bars:CellHasLook(cellCfg, cellIndex) and "  |cffff7a3d*|r" or ""))
            or "|cff888888NOTHING PICKED|r")

        for _, widget in ipairs({ cellScale, cellColour, colourLabel,
            cellGrow, cellSide, cellReset }) do
            widget:SetShown(cellCfg ~= nil)
        end

        barHeading:SetText(cfg and (cfg.name or ("BAR " .. index)):upper()
            or "|cff888888NOTHING SELECTED|r")

        if cfg then
            local lattice = ns.Layout.UsesGrid(cfg)
            local isBar = cfg.kind == "bar"

            for _, entry in ipairs(ns.LAYOUTS) do
                if entry.value == (cfg.layout or "grid") then
                    patternBtn:SetText("Pattern:  " .. entry.text)
                end
            end

            rowsSlider:SetShown(lattice)
            colsSlider:SetShown(lattice)
            slotsSlider:SetShown(not lattice)
            iconSlider:SetShown(not isBar)
            widthSlider:SetShown(isBar)
            heightSlider:SetShown(isBar)
        end

        for _, widget in ipairs(refreshers) do
            if widget:IsShown() and widget.Refresh then widget.Refresh() end
        end
    end
end

---------------------------------------------------------------------------
-- The panel
--
-- Always visible while unlocked, including while the overlay is hidden -
-- otherwise Shift + Right Click would be a one-way door.
---------------------------------------------------------------------------
local function SetMode(next_)
    mode = next_
    if toolbar and toolbar.Refresh then toolbar.Refresh() end
    if palette and mode ~= "build" then palette:Hide() end
    EditMode:Refresh()
    RefreshInspector()
end

-- What the inspector says about the selected cell. Written out rather than
-- built from a loop: four facts, each phrased for what it means, beats a
-- table of key-value pairs nobody reads.
function RefreshInspector()
    if not inspector then return end

    if mode ~= "build" then
        -- The snapping state is STATED, not implied. It lives on two switches
        -- in a panel you have to open, so "why does nothing snap" was a
        -- question this screen could answer and did not - it explained how to
        -- suspend snapping while snapping was switched off.
        local prefs = Prefs()
        local snapLine
        if prefs.snapToGrid then
            snapLine = string.format(
                "Snaps to the other bars, the screen edges and a %d grid. "
                .. "Hold Alt to place it free.", prefs.gridStep or 40)
        else
            snapLine = "Snaps to the other bars and the screen edges. "
                .. "Hold Alt to place it free."
        end

        inspector:SetText("Drag a bar. Arrow keys nudge it, Shift for 10.\n"
            .. snapLine .. "\n"
            .. "The cog attaches a bar to another one, so it moves along.")
        return
    end

    if not picked then
        inspector:SetText("Click a slot on any bar.\n"
            .. "|cff888888Drag it, wheel to scale, right click for more.|r")
        return
    end

    local cfg = ns.db.bars[picked.bar]
    if not cfg then
        inspector:SetText("")
        return
    end

    local spellID = cfg.cells[picked.cell]
    local opts = ns.Layout.CellOpts(cfg, picked.cell) or {}

    local lines = {
        string.format("|cffff7a3d%s|r  slot %d of %d", cfg.name or "?",
            picked.cell, ns.Bars:CellCount(cfg)),
        spellID and (ns.SpellName(spellID) or ("Spell " .. spellID))
            or "|cff888888empty|r",
    }

    local details = {}
    if opts.scale then details[#details + 1] = string.format("%.0f%%", opts.scale * 100) end

    -- Whichever pair this arrangement is actually using, so the readout can
    -- never show a number that is not the one your drag is moving.
    local offsetX, offsetY = ns.Layout.GetOffset(cfg, picked.cell)
    if offsetX ~= 0 or offsetY ~= 0 then
        details[#details + 1] = string.format("%+d, %+d", offsetX, offsetY)
    end
    if opts.kind then details[#details + 1] = opts.kind end
    if opts.hidden then details[#details + 1] = "hidden" end
    if #details > 0 then
        lines[#lines + 1] = "|cff888888" .. table.concat(details, "  ") .. "|r"
    end

    inspector:SetText(table.concat(lines, "\n"))
end

local function BuildToolbar()
    toolbar = CreateFrame("Frame", nil, overlay)
    -- 460, not 360. At 360 the bottom row ran to x=332 and Done, anchored to
    -- the right edge, started at 276 - so in BUILD mode the primary button sat
    -- on top of Spells and the two shared 56 pixels. It only showed up in build
    -- mode, because Spells is the button that is hidden the rest of the time.
    toolbar:SetSize(460, 168)
    toolbar:SetPoint("TOP", UIParent, "TOP", 0, -120)
    toolbar:SetFrameLevel(overlay:GetFrameLevel() + 40)
    toolbar:EnableMouse(true)
    toolbar:SetMovable(true)
    toolbar:RegisterForDrag("LeftButton")
    toolbar:SetScript("OnDragStart", toolbar.StartMoving)
    toolbar:SetScript("OnDragStop", toolbar.StopMovingOrSizing)
    toolbar:SetClampedToScreen(true)

    UI.Fill(toolbar, "BACKGROUND", C.windowBg)
    local edge = ns.CreateBorder(toolbar, 1, "BORDER")
    edge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)

    -- The mode switch, and it is the first thing in the panel because it
    -- changes what every other control in it means.
    local moveBtn, buildBtn
    -- The same two marks the options window puts on the same two words, so
    -- the pair is recognisable in both places.
    moveBtn = UI.Button(toolbar, "Move bars", 128, function() SetMode("bars") end)
    moveBtn:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 12, -12)
    moveBtn:SetIcon("action-move-bars")

    buildBtn = UI.Button(toolbar, "Build", 104, function() SetMode("build") end)
    buildBtn:SetPoint("LEFT", moveBtn, "RIGHT", 6, 0)
    buildBtn:SetIcon("action-build")

    local addBtn = UI.Button(toolbar, "Add slot", 88, function()
        if picked then
            ns.Bars:AddCell(picked.bar)
        elseif selected then
            ns.Bars:AddCell(selected.index)
        else
            ns.Print("Pick a bar first.")
        end
    end)
    addBtn:SetPoint("LEFT", buildBtn, "RIGHT", 6, 0)

    local rule = UI.Separator(toolbar, true)
    rule:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 0, -48)
    rule:SetPoint("TOPRIGHT", toolbar, "TOPRIGHT", 0, -48)

    inspector = UI.Label(toolbar, "", 11, C.textDim)
    inspector:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 12, -58)
    inspector:SetWidth(toolbar:GetWidth() - 24)
    inspector:SetJustifyH("LEFT")
    inspector:SetJustifyV("TOP")

    local gridBtn = UI.Button(toolbar, "Grid", 68, function()
        EditMode:SetGridShown(not (gridLines and gridLines:IsShown()))
    end)
    gridBtn:SetPoint("BOTTOMLEFT", toolbar, "BOTTOMLEFT", 12, 12)

    -- The label follows the state, because this button is the ONLY way back:
    -- hiding the overlay hides every mover with it, so the Shift-right-click
    -- that got you here is not available to get you out. A button that still
    -- reads "Hide overlay" while the overlay is hidden reads as a dead end.
    local overlayBtn
    overlayBtn = UI.Button(toolbar, "Hide overlay", 100, function()
        EditMode:SetOverlayShown(not EditMode.overlayShown)
        overlayBtn:SetText(EditMode.overlayShown and "Hide overlay"
            or "Show overlay")
    end)
    EditMode.overlayButton = overlayBtn
    overlayBtn:SetPoint("LEFT", gridBtn, "RIGHT", 6, 0)

    local toolsBtn = UI.Button(toolbar, "Tools", 62, function()
        if not tools then return end
        if tools:IsShown() then
            tools:Hide()
        else
            tools.Refresh()
            tools:Show()
        end
    end)
    toolsBtn:SetPoint("LEFT", overlayBtn, "RIGHT", 6, 0)

    local spellsBtn = UI.Button(toolbar, "Spells", 72, function()
        if not palette then return end
        if palette:IsShown() then
            palette:Hide()
        else
            SetMode("build")
            palette.Refresh()
            palette:Show()
        end
    end)
    spellsBtn:SetPoint("LEFT", toolsBtn, "RIGHT", 6, 0)

    -- The padlock, because that is what Done DOES: it locks the bars again.
    local doneBtn = UI.Button(toolbar, "Done", 92, function()
        EditMode:SetUnlocked(false)
    end, "primary")
    doneBtn:SetPoint("BOTTOMRIGHT", toolbar, "BOTTOMRIGHT", -12, 12)
    doneBtn:SetIcon("ui-lock")

    toolbar.Refresh = function()
        -- The active mode is the one that reads as pressed. Two buttons and a
        -- colour beats a segmented control nobody can tell is interactive.
        moveBtn.label:SetTextColor(
            mode == "bars" and C.accent[1] or C.textDim[1],
            mode == "bars" and C.accent[2] or C.textDim[2],
            mode == "bars" and C.accent[3] or C.textDim[3])
        buildBtn.label:SetTextColor(
            mode == "build" and C.accent[1] or C.textDim[1],
            mode == "build" and C.accent[2] or C.textDim[2],
            mode == "build" and C.accent[3] or C.textDim[3])
        addBtn:SetShown(mode == "build")
        spellsBtn:SetShown(mode == "build")
    end
    toolbar.Refresh()
end

---------------------------------------------------------------------------
-- Assembly
---------------------------------------------------------------------------
local function Build()
    if overlay then return end

    overlay = CreateFrame("Frame", "ZwoelfStuffEditMode", UIParent)
    overlay:SetAllPoints(UIParent)
    -- Above the bars (MEDIUM) and above the options window (HIGH), but below
    -- FULLSCREEN_DIALOG so the shared menu still opens on top of it.
    overlay:SetFrameStrata("FULLSCREEN")
    overlay:Hide()
    overlay:SetScript("OnUpdate", OnUpdate)

    overlay.dim = overlay:CreateTexture(nil, "BACKGROUND")
    overlay.dim:SetAllPoints(overlay)
    overlay.dim:SetColorTexture(0, 0, 0, Prefs().dim)

    BuildGrid()
    BuildGuides()
    BuildTools()
    BuildToolbar()
    BuildPalette()
    BuildKeyCatcher()
end

---------------------------------------------------------------------------
-- Keeping the overlay in step with the bars
--
-- Movers and handles are rebuilt from the bar list rather than kept in step by
-- hand, so adding or deleting a bar while unlocked cannot leave a panel behind.
---------------------------------------------------------------------------
local function RefreshHandles(index, cfg)
    handles[index] = handles[index] or {}
    local row = handles[index]
    local count = ns.Bars:CellCount(cfg)
    local building = (mode == "build") and EditMode.overlayShown

    for cellIndex = 1, count do
        local cell = ns.Screen:CellFrame(index, cellIndex)
        local handle = row[cellIndex]

        if cell and building then
            if not handle then
                handle = CreateHandle(index, cellIndex)
                row[cellIndex] = handle
            end
            handle.barIndex, handle.cellIndex = index, cellIndex
            handle:ClearAllPoints()
            handle:SetAllPoints(cell)

            local spellID = cfg.cells[cellIndex]
            handle.tag:SetText(spellID and "" or tostring(cellIndex))
            handle:Show()
        elseif handle then
            handle:Hide()
        end
    end

    for cellIndex = count + 1, #row do
        if row[cellIndex] then row[cellIndex]:Hide() end
    end
end

function EditMode:Refresh()
    if not (unlocked and overlay) then return end

    for index, cfg in ipairs(ns.db.bars) do
        local bar = ns.Screen:BarFrame(index)
        local mover = movers[index]

        if bar then
            if not mover then
                mover = CreateMover(index)
                movers[index] = mover
            end
            mover.index = index
            mover:ClearAllPoints()

            if mode == "build" then
                -- Out of the way: in build mode the bar's own cells are what
                -- you are aiming at, and a panel covering them would swallow
                -- every click meant for a slot.
                mover:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 2)
                mover:SetSize(math.max(90, math.min(bar:GetWidth(), 220)), 18)
            else
                mover:SetAllPoints(bar)
            end

            mover.name:SetText(cfg.name or ("Bar " .. index))
            mover.name:SetTextColor(
                cfg.enabled == false and C.textFaint[1] or C.text[1],
                cfg.enabled == false and C.textFaint[2] or C.text[2],
                cfg.enabled == false and C.textFaint[3] or C.text[3])
            UpdateReadout(mover)
            mover.coords:SetShown(Prefs().showCoords or selected == mover)
            mover:RefreshLock()
            mover:SetShown(self.overlayShown)

            RefreshHandles(index, cfg)
        elseif mover then
            mover:Hide()
        end
    end

    for index = #ns.db.bars + 1, #movers do
        movers[index]:Hide()
        if handles[index] then
            for _, handle in pairs(handles[index]) do handle:Hide() end
        end
    end

    RefreshTankMover()
    RefreshBusterMover()
    RefreshReminderMovers()

    -- The selection can outlive what it pointed at: delete a bar, or shrink a
    -- grid, and the cell it named is gone.
    if picked then
        local cfg = ns.db.bars[picked.bar]
        if not cfg or picked.cell > ns.Bars:CellCount(cfg) then
            picked = nil
        end
    end
    RefreshInspector()
end

function EditMode:SetGridShown(shown)
    if gridLines then gridLines:SetShown(shown and unlocked) end
end

function EditMode:SetOverlayShown(shown)
    self.overlayShown = shown and true or false
    if not overlay then return end

    -- Also when something OTHER than the button changed it: Shift-right-click
    -- on a mover, and unlocking, both come through here.
    if self.overlayButton then
        self.overlayButton:SetText(self.overlayShown and "Hide overlay"
            or "Show overlay")
    end

    overlay.dim:SetShown(self.overlayShown)
    for _, mover in ipairs(movers) do
        mover:SetShown(self.overlayShown and BarConfig(mover.index) ~= nil)
    end
    if not self.overlayShown then
        guideX:Hide()
        guideY:Hide()
        for _, row in pairs(handles) do
            for _, handle in pairs(row) do handle:Hide() end
        end
    else
        self:Refresh()
    end
end

function EditMode:IsUnlocked()
    return unlocked
end

function EditMode:Mode()
    return mode
end

-- wanted, when given, says which mode to land in ("bars" or "build"). The
-- window's header offers both as separate buttons, and arriving in the wrong
-- one means the first thing anybody does after opening edit mode is change
-- the mode - which is a step the button already knew the answer to.
function EditMode:SetUnlocked(state, wanted)
    state = state and true or false
    if state == unlocked then
        -- Already open. The mode is still worth honouring: this is also the
        -- path a second click on the other header button takes.
        if state and wanted then SetMode(wanted) end
        return
    end

    Build()
    if state and wanted then mode = wanted end
    unlocked = state
    self.overlayShown = true
    dragging, cellDrag, selected = nil, nil, nil

    ns.Screen:SetUnlocked(state)

    -- THE CO-TANK PANEL COMES OUT WHILE YOU ARE PLACING IT. It hides itself
    -- when the feature is off, when you are solo, or when nobody else is
    -- tanking - which is very nearly always, for somebody who has just opened
    -- edit mode to put it somewhere. `locked` is what ShouldShow reads, and
    -- it outranks the master switch on purpose.
    if ns.CoTanks and ns.CoTanks.panel then
        ns.db.coTanks.locked = not state
        ns.CoTanks:Refresh()
    end

    -- AND SO DO THE REMINDERS, for the same reason one layer sharper: a
    -- reminder is on screen only while the thing it names is wrong. Waiting
    -- for Bone Shield to fall off in order to place the message about Bone
    -- Shield falling off is not a workflow.
    if ns.Reminders then ns.Reminders:SetPlacing(state) end

    -- The Timeline panel too: it shows in combat, and edit mode is the one
    -- moment it must be there with nothing scheduled and nobody swinging.
    if ns.Busters then ns.Busters:SetPlacing(state) end

    if state then
        -- The window would sit behind the overlay, catching clicks that were
        -- meant for a bar. Unlocking is a full-screen mode, so it gets the
        -- full screen.
        if ns.Options.frame then ns.Options.frame:Hide() end

        overlay:Show()
        keyCatcher:Show()
        self:SetOverlayShown(true)
        self:Refresh()
        ns.Print("Unlocked. |cffffd100Move bars|r drags whole bars; "
            .. "|cffffd100Build|r takes them apart slot by slot. "
            .. "|cffffd100/zs lock|r when you are done.")
    else
        UI.ClosePopup()
        overlay:Hide()
        keyCatcher:Hide()
        Propagate(keyCatcher, true)
        if gridLines then gridLines:Hide() end
        if palette then palette:Hide() end
        if tools then tools:Hide() end
    end
end

function EditMode:Toggle()
    self:SetUnlocked(not unlocked)
end

-- Straight into build mode from anywhere - the slash command and the button
-- in the options window both want this rather than "unlock, then switch".
function EditMode:OpenBuild()
    if not unlocked then self:SetUnlocked(true) end
    SetMode("build")
end
