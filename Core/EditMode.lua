---------------------------------------------------------------------------
-- EditMode - unlock the screen and put the bars where you want them.
--
-- Built to work the way EllesmereUI's unlock mode does, because that is what
-- this addon is used next to and a second set of rules for "how do I move a
-- thing" is a tax on the user, not a feature:
--
--   * every bar gets a labelled panel over it, with its live coordinates
--   * drag it, or select it and nudge with the arrow keys (Shift = 10)
--   * it snaps to the screen centre and to the other bars, with a guide line
--     saying what it snapped to
--   * a cog on each panel opens that bar's own menu
--   * Shift + Right Click hides the overlay so you can see what is underneath
--
-- WHY THE PANEL AND NOT THE BAR ITSELF.
--
-- Half of what a bar shows is a Blizzard frame we adopted, and those bring
-- their own mouse handling. Dragging the bar directly would fight tooltips
-- and clicks that are not ours to intercept. A panel above it at a higher
-- strata answers the mouse instead, and the bar never learns it is being
-- moved.
--
-- POSITIONS ARE ALWAYS CENTRE-RELATIVE.
--
-- One anchor for every bar: its centre, offset from the screen centre. That
-- is what makes the readout mean something, what makes snapping arithmetic
-- instead of a case analysis, and what keeps a bar in the same visual place
-- when the window resolution changes.
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
local overlay, toolbar, keyCatcher
local movers = {}
local selected = nil
local dragging = nil
local guideX, guideY, gridLines

-- Forward declaration: a mover's OnMouseUp is written before the dragging
-- section that defines this, and without it the reference would silently be
-- a global that is nil at call time.
local StopDrag

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
local function Candidates(index, half, axis)
    local list = { { value = 0, guide = 0 } }   -- the screen centre

    for otherIndex, cfg in ipairs(ns.db.bars) do
        local bar = ns.Screen:BarFrame(otherIndex)
        if otherIndex ~= index and bar and bar:IsShown() then
            local centre  = (axis == "x") and (cfg.x or 0) or (cfg.y or 0)
            local otherHalf = ((axis == "x") and bar:GetWidth() or bar:GetHeight()) / 2

            list[#list + 1] = { value = centre, guide = centre }
            list[#list + 1] = { value = centre - otherHalf + half, guide = centre - otherHalf }
            list[#list + 1] = { value = centre + otherHalf - half, guide = centre + otherHalf }
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
-- One mover
---------------------------------------------------------------------------
local function BarConfig(index)
    return ns.db.bars[index]
end

local function UpdateReadout(mover)
    local cfg = BarConfig(mover.index)
    if not cfg then return end
    mover.coords:SetText(string.format("%d, %d", cfg.x or 0, cfg.y or 0))
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
end

local function ApplyMove(mover, x, y)
    local cfg = BarConfig(mover.index)
    if not cfg then return end

    cfg.point, cfg.relPoint = "CENTER", "CENTER"
    cfg.x, cfg.y = math.floor(x + 0.5), math.floor(y + 0.5)
    ns.Screen:ApplyPosition(mover.index)
    UpdateReadout(mover)
end

local function OpenMenu(mover)
    local index = mover.index
    local cfg = BarConfig(index)
    if not cfg then return end

    UI.ShowMenu(mover.cog, {
        width = 190,
        anchor = { "TOPRIGHT", "BOTTOMRIGHT", 0, -2 },
        items = {
            { text = "Bar options", onClick = function()
                EditMode:SetUnlocked(false)
                ns.OptionsBars:ShowOptions(index)
                -- Open, not Toggle: this wants the window shown, and Toggle
                -- would close it if it happened to be open already.
                ns.Options:Open("cooldowns")
            end },
            { text = "Centre on screen", onClick = function()
                ApplyMove(mover, 0, 0)
            end },
            { text = "Centre horizontally", onClick = function()
                ApplyMove(mover, 0, cfg.y or 0)
            end },
            { text = "Centre vertically", onClick = function()
                ApplyMove(mover, cfg.x or 0, 0)
            end },
        },
        actions = {
            { text = cfg.enabled == false and "Switch on" or "Switch off",
              onClick = function()
                  cfg.enabled = (cfg.enabled == false)
                  ns.Bars:Changed(index)
              end },
        },
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
        dragging = {
            mover = self,
            cursorX = cursorX, cursorY = cursorY,
            originX = cfg.x or 0, originY = cfg.y or 0,
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
-- Dragging
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
    if not IsAltKeyDown() then
        x, lineX = Snap(x, mover.index, bar:GetWidth() / 2, "x")
        y, lineY = Snap(y, mover.index, bar:GetHeight() / 2, "y")
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

        local direction = ARROWS[key]
        if not (direction and selected) then
            self:SetPropagateKeyboardInput(true)
            return
        end

        self:SetPropagateKeyboardInput(false)
        local cfg = BarConfig(selected.index)
        if not cfg then return end

        local step = IsShiftKeyDown() and NUDGE_FAST or NUDGE
        ApplyMove(selected, (cfg.x or 0) + direction[1] * step,
                            (cfg.y or 0) + direction[2] * step)
    end)

    keyCatcher:SetScript("OnKeyUp", function(self)
        self:SetPropagateKeyboardInput(true)
    end)
end

---------------------------------------------------------------------------
-- The panel
--
-- Always visible while unlocked, including while the overlay is hidden -
-- otherwise Shift + Right Click would be a one-way door.
---------------------------------------------------------------------------
local function BuildToolbar()
    toolbar = CreateFrame("Frame", nil, overlay)
    toolbar:SetSize(330, 132)
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

    local title = UI.Label(toolbar, "Unlock Mode", 14, C.text)
    title:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 14, -12)

    local rule = UI.Separator(toolbar, true)
    rule:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 0, -36)
    rule:SetPoint("TOPRIGHT", toolbar, "TOPRIGHT", 0, -36)

    local hint = UI.Label(toolbar, table.concat({
        "Drag a bar, or select it and use the arrow keys - Shift for 10.",
        "Alt while dragging switches snapping off.",
        "Shift + Right Click hides the overlay.",
    }, "\n"), 11, C.textDim)
    hint:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 14, -46)
    hint:SetWidth(300)
    hint:SetJustifyH("LEFT")

    local gridBtn = UI.Button(toolbar, "Grid", 76, function()
        EditMode:SetGridShown(not (gridLines and gridLines:IsShown()))
    end, "soft")
    gridBtn:SetPoint("BOTTOMLEFT", toolbar, "BOTTOMLEFT", 14, 12)

    local overlayBtn = UI.Button(toolbar, "Overlay", 90, function()
        EditMode:SetOverlayShown(not EditMode.overlayShown)
    end, "soft")
    overlayBtn:SetPoint("LEFT", gridBtn, "RIGHT", 8, 0)

    local doneBtn = UI.Button(toolbar, "Done", 100, function()
        EditMode:SetUnlocked(false)
    end, "primary")
    doneBtn:SetPoint("BOTTOMRIGHT", toolbar, "BOTTOMRIGHT", -14, 12)
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
    BuildKeyCatcher()
end

-- Movers are rebuilt from the bar list rather than kept in step by hand, so
-- adding or deleting a bar while unlocked cannot leave a panel behind.
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
            mover:SetAllPoints(bar)
            mover.name:SetText(cfg.name or ("Bar " .. index))
            mover.name:SetTextColor(
                cfg.enabled == false and C.textFaint[1] or C.text[1],
                cfg.enabled == false and C.textFaint[2] or C.text[2],
                cfg.enabled == false and C.textFaint[3] or C.text[3])
            UpdateReadout(mover)
            mover:SetShown(self.overlayShown)
        elseif mover then
            mover:Hide()
        end
    end

    for index = #ns.db.bars + 1, #movers do
        movers[index]:Hide()
    end
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
    end
end

function EditMode:IsUnlocked()
    return unlocked
end

function EditMode:SetUnlocked(state)
    state = state and true or false
    if state == unlocked then return end

    Build()
    unlocked = state
    self.overlayShown = true
    dragging, selected = nil, nil

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
        ns.Print("Unlocked. Drag the bars, or select one and nudge it with the "
            .. "arrow keys. |cffffd100/zs lock|r when you are done.")
    else
        UI.ClosePopup()
        overlay:Hide()
        keyCatcher:Hide()
        keyCatcher:SetPropagateKeyboardInput(true)
        if gridLines then gridLines:Hide() end
    end
end

function EditMode:Toggle()
    self:SetUnlocked(not unlocked)
end
