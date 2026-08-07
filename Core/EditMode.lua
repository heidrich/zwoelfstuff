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

local SNAP_DISTANCE = 10       -- screen units, matched against bar centres and edges
local NUDGE = 1
local NUDGE_FAST = 10
local GRID_STEP = 40

local unlocked = false
local mode = "bars"            -- "bars" | "build"
local overlay, toolbar, keyCatcher, palette, inspector
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
local function Candidates(index, half, axis)
    local list = { { value = 0, guide = 0 } }   -- the screen centre

    for otherIndex in ipairs(ns.db.bars) do
        local bar = ns.Screen:BarFrame(otherIndex)
        if otherIndex ~= index and bar and bar:IsShown() then
            local offsetX, offsetY = ns.Screen:CentreOffset(otherIndex)
            if offsetX then
                local centre = (axis == "x") and offsetX or offsetY
                local otherHalf = ((axis == "x") and bar:GetWidth() or bar:GetHeight()) / 2

                list[#list + 1] = { value = centre, guide = centre }
                list[#list + 1] = { value = centre - otherHalf + half, guide = centre - otherHalf }
                list[#list + 1] = { value = centre + otherHalf - half, guide = centre + otherHalf }
            end
        end
    end

    return list
end

local function Snap(value, index, half, axis)
    local best, bestDistance, guide = value, SNAP_DISTANCE, nil

    for _, candidate in ipairs(Candidates(index, half, axis)) do
        local distance = math.abs(candidate.value - value)
        if distance < bestDistance then
            bestDistance, best, guide = distance, candidate.value, candidate.guide
        end
    end

    return best, guide
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

-- Drawn once and reused: a grid rebuilt on every toggle is a few hundred
-- textures churned for nothing.
local function BuildGrid()
    gridLines = CreateFrame("Frame", nil, overlay)
    gridLines:SetAllPoints(overlay)
    gridLines:Hide()

    local width  = UIParent:GetWidth()
    local height = UIParent:GetHeight()

    local function Line(vertical, offset, strong)
        local line = gridLines:CreateTexture(nil, "BACKGROUND")
        local alpha = strong and 0.35 or 0.12
        line:SetColorTexture(1, 1, 1, alpha)
        if vertical then
            line:SetWidth(1)
            line:SetPoint("TOP", gridLines, "TOP", offset, 0)
            line:SetPoint("BOTTOM", gridLines, "BOTTOM", offset, 0)
        else
            line:SetHeight(1)
            line:SetPoint("LEFT", gridLines, "LEFT", 0, offset)
            line:SetPoint("RIGHT", gridLines, "RIGHT", 0, offset)
        end
    end

    for offset = 0, width / 2, GRID_STEP do
        Line(true, offset, offset == 0)
        if offset > 0 then Line(true, -offset, false) end
    end
    for offset = 0, height / 2, GRID_STEP do
        Line(false, offset, offset == 0)
        if offset > 0 then Line(false, -offset, false) end
    end
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
        other.coords:SetShown(isIt)
        -- Raised while selected, so two overlapping bars do not leave you
        -- dragging the one underneath the one you clicked.
        other:SetFrameLevel(overlay:GetFrameLevel() + (isIt and 20 or 10))
    end
    selected = mover
    if mode == "build" then
        picked = { bar = mover.index, cell = picked and picked.cell or 1 }
    end
    RefreshInspector()
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
            ApplyMove(mover, 0, 0)
        end }
        items[#items + 1] = { text = "Centre horizontally", onClick = function()
            ApplyMove(mover, 0, cfg.y or 0)
        end }
        items[#items + 1] = { text = "Centre vertically", onClick = function()
            ApplyMove(mover, cfg.x or 0, 0)
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
    local cogGlyph = UI.Glyph(mover.cog, "sliders", 12, C.textDim)
    cogGlyph:SetPoint("CENTER", mover.cog, "CENTER", 0, 0)
    mover.cog:SetScript("OnEnter", function()
        cogGlyph:SetColor(C.accent[1], C.accent[2], C.accent[3])
    end)
    mover.cog:SetScript("OnLeave", function()
        cogGlyph:SetColor(C.textDim[1], C.textDim[2], C.textDim[3])
    end)
    mover.cog:SetScript("OnClick", function() OpenMenu(mover) end)

    mover:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            -- The one gesture that is not about moving: get the overlay out
            -- of the way to check what is actually underneath it.
            if IsShiftKeyDown() then EditMode:SetOverlayShown(false) end
            return
        end

        SetSelected(self)
        local cfg = BarConfig(self.index)
        if not cfg then return end

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
        if selected ~= self then self.coords:Hide() end
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
              write.x, write.y, write.scale = nil, nil, nil
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

        local opts = ns.Layout.CellOpts(cfg, self.cellIndex)
        local cursorX, cursorY = CursorPosition()
        local point, _, relPoint, offsetX, offsetY = cell:GetPoint(1)

        cellDrag = {
            barIndex = self.barIndex, cellIndex = self.cellIndex,
            cursorX = cursorX, cursorY = cursorY,
            startX = (opts and opts.x) or 0,
            startY = (opts and opts.y) or 0,
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

    local opts = ns.Layout.EnsureCellOpts(cfg, cellDrag.cellIndex)
    opts.x, opts.y = x, y

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

local function OnUpdate()
    if cellDrag then DragCell() end
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

    -- Free movement with Alt held: snapping is right almost always, and
    -- "almost" is why there has to be a way to switch it off in the moment.
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

    local opts = ns.Layout.EnsureCellOpts(cfg, where.cell)
    opts.x = (opts.x or 0) + direction[1] * step
    opts.y = (opts.y or 0) + direction[2] * step

    ns.Layout.TidyCellOpts(cfg, where.cell)
    ns.Bars:Changed(where.bar)
    RefreshInspector()
end

local function BuildKeyCatcher()
    keyCatcher = CreateFrame("Frame", nil, UIParent)
    keyCatcher:EnableKeyboard(true)
    keyCatcher:SetPropagateKeyboardInput(true)
    keyCatcher:Hide()

    keyCatcher:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            EditMode:SetUnlocked(false)
            return
        end

        if key == "TAB" and mode == "build" and picked then
            self:SetPropagateKeyboardInput(false)
            local cfg = ns.db.bars[picked.bar]
            if cfg then
                local count = ns.Bars:CellCount(cfg)
                SelectCell(picked.bar, (picked.cell % count) + 1)
            end
            return
        end

        if (key == "DELETE" or key == "BACKSPACE") and mode == "build" and picked then
            self:SetPropagateKeyboardInput(false)
            ns.Bars:ClearCell(picked.bar, picked.cell)
            return
        end

        local direction = ARROWS[key]
        if not direction then
            self:SetPropagateKeyboardInput(true)
            return
        end

        local step = IsShiftKeyDown() and NUDGE_FAST or NUDGE

        if mode == "build" and picked then
            self:SetPropagateKeyboardInput(false)
            NudgeCell(picked, direction, step)
            return
        end

        if not selected then
            self:SetPropagateKeyboardInput(true)
            return
        end

        self:SetPropagateKeyboardInput(false)
        local cfg = BarConfig(selected.index)
        if not cfg then return end

        local x, y = Origin(cfg)
        ApplyMove(selected, x + direction[1] * step, y + direction[2] * step)
    end)

    keyCatcher:SetScript("OnKeyUp", function(self)
        self:SetPropagateKeyboardInput(true)
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
        inspector:SetText("Drag a bar. Arrow keys nudge it, Shift for 10.\n"
            .. "Alt while dragging switches snapping off.\n"
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
    if opts.x or opts.y then
        details[#details + 1] = string.format("%+d, %+d", opts.x or 0, opts.y or 0)
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
    toolbar:SetSize(360, 168)
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
    moveBtn = UI.Button(toolbar, "Move bars", 108, function() SetMode("bars") end)
    moveBtn:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 12, -12)

    buildBtn = UI.Button(toolbar, "Build", 84, function() SetMode("build") end)
    buildBtn:SetPoint("LEFT", moveBtn, "RIGHT", 6, 0)

    local addBtn = UI.Button(toolbar, "Add slot", 88, function()
        if picked then
            ns.Bars:AddCell(picked.bar)
        elseif selected then
            ns.Bars:AddCell(selected.index)
        else
            ns.Print("Pick a bar first.")
        end
    end, "soft")
    addBtn:SetPoint("LEFT", buildBtn, "RIGHT", 6, 0)

    local rule = UI.Separator(toolbar, true)
    rule:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 0, -48)
    rule:SetPoint("TOPRIGHT", toolbar, "TOPRIGHT", 0, -48)

    inspector = UI.Label(toolbar, "", 11, C.textDim)
    inspector:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 12, -58)
    inspector:SetWidth(336)
    inspector:SetJustifyH("LEFT")
    inspector:SetJustifyV("TOP")

    local gridBtn = UI.Button(toolbar, "Grid", 68, function()
        EditMode:SetGridShown(not (gridLines and gridLines:IsShown()))
    end, "soft")
    gridBtn:SetPoint("BOTTOMLEFT", toolbar, "BOTTOMLEFT", 12, 12)

    local overlayBtn = UI.Button(toolbar, "Hide overlay", 100, function()
        EditMode:SetOverlayShown(not EditMode.overlayShown)
    end, "soft")
    overlayBtn:SetPoint("LEFT", gridBtn, "RIGHT", 6, 0)

    local spellsBtn = UI.Button(toolbar, "Spells", 72, function()
        if not palette then return end
        if palette:IsShown() then
            palette:Hide()
        else
            SetMode("build")
            palette.Refresh()
            palette:Show()
        end
    end, "soft")
    spellsBtn:SetPoint("LEFT", overlayBtn, "RIGHT", 6, 0)

    local doneBtn = UI.Button(toolbar, "Done", 72, function()
        EditMode:SetUnlocked(false)
    end, "primary")
    doneBtn:SetPoint("BOTTOMRIGHT", toolbar, "BOTTOMRIGHT", -12, 12)

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
    overlay.dim:SetColorTexture(0, 0, 0, 0.35)

    BuildGrid()
    BuildGuides()
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

function EditMode:SetUnlocked(state)
    state = state and true or false
    if state == unlocked then return end

    Build()
    unlocked = state
    self.overlayShown = true
    dragging, cellDrag, selected = nil, nil, nil

    ns.Screen:SetUnlocked(state)

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
        keyCatcher:SetPropagateKeyboardInput(true)
        if gridLines then gridLines:Hide() end
        if palette then palette:Hide() end
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
