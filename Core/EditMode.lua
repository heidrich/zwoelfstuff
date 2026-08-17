---------------------------------------------------------------------------
-- EditMode - unlock the screen and put everything where you want it.
--
-- ONE MODE. There were two: one moved whole bars, the other took a bar apart
-- cell by cell. Both went with the cooldown bars in 4.83.0, and what is left
-- is the thing this file was always also doing - placing the surfaces this
-- addon draws: the co-tank panel, the taunt button, the request and answer
-- panels, the raid bar and every reminder.
--
-- WHY A PANEL AND NOT THE SURFACE ITSELF.
--
-- Several of them answer the mouse already - a co-tank row is clickable, the
-- request panel takes a press. Dragging them directly would fight clicks that
-- are not ours to intercept. A panel above at a higher strata answers the
-- mouse instead, and the surface never learns it is being moved.
--
-- POSITIONS ARE PINNED-POINT RELATIVE.
--
-- A surface is placed by ONE of its nine points, offset from the screen
-- centre. The centre is the default and the readout means what it says; pin
-- an edge instead and it grows away from that edge. Snapping still works in
-- centre terms, because "line these two up" is about the shapes and not about
-- what each one happens to be pinned by - the translation happens once, here.
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
local overlay, toolbar, keyCatcher, inspector, tools
local movers = {}
local selected = nil           -- the selected MOVER
---@type table|nil
local dragging = nil
local guideX, guideY, gridLines

-- Forward declarations. A handle's script is written above the drag section
-- that defines these, and without them the reference would silently be a
-- global that is nil at call time.
local StopDrag, RefreshInspector

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

-- Filled where the panels are described, far below; declared here so the
-- snapper and the movers are looking at ONE list.
local PANEL_MOVERS

-- The frame-reading half: measure the other panels, then hand the numbers
-- over.
--
-- Measured off the live frames rather than off the saved x/y, because a panel
-- pinned by an edge stores a number that is not its centre, and lining two of
-- them up is about where they ARE.
--
-- The targets come out of PANEL_MOVERS - the same list that drags them, and
-- the same list that stopped the taunt button being forgotten. It is FILLED
-- further down the file, so it is declared above this function: a local
-- declared after a function that names it is not the same variable, and this
-- would have read a nil global and snapped to nothing at all. The static
-- check caught it; nothing on screen would have.
local function Snap(value, index, half, axis)
    local others = {}

    for _, entry in ipairs(PANEL_MOVERS or {}) do
        local panel = entry.panel and entry.panel()
        if entry.mover ~= index and panel and panel:IsShown() then
            local centre = (axis == "x")
                and (panel:GetCenter())
                or select(2, panel:GetCenter())
            if centre then
                others[#others + 1] = {
                    centre = centre,
                    half = ((axis == "x") and panel:GetWidth()
                        or panel:GetHeight()) / 2,
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

local function TankPanel()
    local panel = ns.CoTanks and ns.CoTanks.panel

    -- HOSTED IS NOT ON SCREEN. The co-tank panel can be borrowed by the
    -- options page as a live preview card, and while it is, CoTanks:
    -- ApplyLayout does nothing (see the `hosted` guard there). A mover over
    -- it would take a drag, write the new numbers into the profile and move
    -- NOTHING - the one failure that looks like a bug in the drag rather
    -- than in what it was pointed at. The reminder movers already asked
    -- their equivalent of this question; this one did not.
    if ns.CoTanks and ns.CoTanks.hosted then return nil end

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

-- WHAT THE COG ON A PANEL OFFERS. The bar's menu is anchoring plus its own
-- settings plus a switch; a panel has nothing to anchor to another panel, so
-- what is left is where it sits, the settings behind it, and the switch.
--
-- Centring writes ZERO, because both panels are stored as an offset from the
-- middle of the screen - the same terms an unanchored bar uses.
local function OpenPanelMenu(mover)
    local spec = mover.spec
    local cfg = spec.config()
    if not cfg then return end

    local x, y = spec.origin()
    local items = {
        { text = "Centre on screen", onClick = function() spec.apply(0, 0) end },
        { text = "Centre horizontally", onClick = function() spec.apply(0, y) end },
        { text = "Centre vertically", onClick = function() spec.apply(x, 0) end },
    }

    local actions = {
        { text = cfg.pinned and "Unpin" or "Pin in place", onClick = function()
            cfg.pinned = not cfg.pinned
            mover:RefreshLock()
            ns.Options:Refresh()
        end },
        { text = spec.settingsText or "Settings", onClick = function()
            -- Out of edit mode first: the window this opens would otherwise
            -- land on top of the thing being placed, which is the whole
            -- reason placing happens on the screen rather than in a panel.
            EditMode:SetUnlocked(false)
            ns.Options:Open(spec.page)
        end },
        -- SWITCHING OFF MEANS THE THING IN FRONT OF YOU. For a panel that is
        -- its module; for one reminder out of twelve it is that reminder, and
        -- taking the whole feature away because you did not want THIS line on
        -- screen would be an answer nobody asked for. The surface says which
        -- it is; the menu does not guess.
        spec.switchOff or { text = "Switch off", onClick = function()
            ns.Modules:Set(spec.module, false)
            EditMode:Refresh()
            ns.Options:Refresh()
        end },
    }

    UI.ShowMenu(mover.cog, {
        width = 190,
        anchor = { "TOPRIGHT", "BOTTOMRIGHT", 0, -2 },
        items = items,
        actions = actions,
    })
end

---------------------------------------------------------------------------
-- THE TWO CONTROLS EVERY MOVER OWES, wherever it is.
--
-- Owner, 2026-08-09, with a screenshot of the externals mover: "hier fehlt
-- noch das zahnrad fuer einstellungen und das lock item!" Five days later,
-- with a screenshot of a REMINDER mover: "mein reminder hat kein zahnrad
-- oder lock". The same sentence, one surface later - because the fix went
-- into the panel builder and the reminders have a builder of their own.
--
-- So the controls come out of the panel builder and live here. It is not the
-- whole mover that is shared - a reminder's box is exactly the size of the
-- words it is showing, so its NAME has to sit outside the box where a
-- panel's sits inside it - but the cog and the padlock are the same two
-- things doing the same two jobs, and that is what was being copied.
--
-- Returns the strip, so a caller whose label lives outside the box can put
-- it beside these rather than under them.
---------------------------------------------------------------------------
local function AttachTools(mover, spec)
    local BUTTON = 20
    local tab = CreateFrame("Frame", nil, mover)
    tab:SetSize(BUTTON * 2 + 10, BUTTON + 6)
    tab:SetPoint("BOTTOMLEFT", mover, "TOPLEFT", 0, 0)
    tab:SetFrameLevel(mover:GetFrameLevel() + 4)
    mover.tab = tab

    tab.bg = tab:CreateTexture(nil, "BACKGROUND")
    tab.bg:SetAllPoints(tab)
    tab.bg:SetColorTexture(C.sidebarBg[1], C.sidebarBg[2], C.sidebarBg[3], 0.92)

    tab.edge = ns.CreateBorder(tab, 1, "BORDER")
    tab.edge:SetColor(C.accentDim[1], C.accentDim[2], C.accentDim[3], 1)

    local function IconButton(kind, offset, onClick)
        local button = CreateFrame("Button", nil, tab)
        button:SetSize(BUTTON, BUTTON)
        button:SetPoint("LEFT", tab, "LEFT", offset, 0)
        button:SetFrameLevel(tab:GetFrameLevel() + 2)
        local glyph = UI.Glyph(button, kind, 12, C.textDim)
        glyph:SetPoint("CENTER", button, "CENTER", 0, 0)
        button:SetScript("OnClick", onClick)
        return button, glyph
    end

    local cog, cogGlyph = IconButton("ui-gear", 4, function()
        OpenPanelMenu(mover)
    end)
    mover.cog, mover.cogGlyph = cog, cogGlyph

    local lock, lockGlyph = IconButton("ui-lock", 4 + BUTTON + 2, function()
        local cfg = spec.config()
        if not cfg then return end
        cfg.pinned = not cfg.pinned
        mover:RefreshLock()
        ns.Options:Refresh()
    end)
    mover.lock, mover.lockGlyph = lock, lockGlyph

    -- Its own function for the same three callers the bars have: the click,
    -- the refresh when edit mode opens, and hovering off it.
    mover.RefreshLock = function(self)
        local cfg = spec.config()
        local pinned = cfg and cfg.pinned
        self.lockGlyph:SetKind(pinned and "ui-lock" or "menu-unlock")
        local colour = pinned and C.accent or C.textDim
        self.lockGlyph:SetColor(colour[1], colour[2], colour[3])
    end

    mover.cog:SetScript("OnEnter", function()
        mover.cogGlyph:SetColor(C.accent[1], C.accent[2], C.accent[3])
    end)
    mover.cog:SetScript("OnLeave", function()
        mover.cogGlyph:SetColor(C.textDim[1], C.textDim[2], C.textDim[3])
    end)
    lock:SetScript("OnEnter", function()
        lockGlyph:SetColor(C.accent[1], C.accent[2], C.accent[3])
    end)
    lock:SetScript("OnLeave", function() mover:RefreshLock() end)

    return tab
end

-- A PANEL'S MOVER HAS A COG AND A PADLOCK, the same two a bar's mover has.
--
-- Owner, 2026-08-09, with a screenshot of the externals mover: "hier fehlt
-- noch das zahnrad fuer einstellungen und das lock item!" - and he is right,
-- because the two kinds of mover are one idea and having half the controls on
-- one of them is a thing to discover rather than to learn.
--
-- Built ONCE for both panels. `spec` is what they disagree about and nothing
-- else:
--   label    what the box says
--   origin   where it is now, as x, y from the screen centre
--   apply    put it at x, y
--   config   the table its `pinned` lives in
--   page     which options page opens from the cog
--   module   which module the cog can switch off
--
-- ON ITS OWN STRIP ABOVE THE BOX rather than in a corner of it. A panel can
-- be as small as one icon - a single-slot externals panel is forty pixels
-- square - and two twenty-pixel buttons do not fit inside that at all, never
-- mind over the thing you are looking at. Above it, the controls are the same
-- size and in the same place whatever is being moved.
local function CreatePanelMover(spec)
    local mover = CreateFrame("Button", nil, overlay)
    mover:SetFrameLevel(overlay:GetFrameLevel() + 10)
    mover:RegisterForDrag("LeftButton")
    mover:Hide()
    mover.spec = spec

    local label, getOrigin = spec.label, spec.origin

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

    AttachTools(mover, spec)

    mover:SetScript("OnDragStart", function(self)
        -- A PINNED PANEL SELECTS AND OPENS LIKE ANY OTHER. It just does not
        -- move - the same sentence a pinned bar follows.
        local cfg = spec.config()
        if cfg and cfg.pinned then return end

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

    mover:RefreshLock()
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
    mover:RefreshLock()
    mover:Show()
end

-- THE EXTERNALS PANEL. Two functions now, not three: which frame it is and
-- what moving it means. Everything else - the module gate, building the
-- mover on first sight, hiding it when the feature is off, drawing the
-- coordinates - is the same for all five and lives once, at the end of this
-- run of surfaces. See PANEL_MOVERS.
local function ExternalPanel()
    local panel = ns.Externals and ns.Externals.Frame()
    if panel and panel:IsShown() then return panel end
    return nil
end

local function ApplyExternalMove(x, y)
    local cfg = ns.Externals.Config()
    cfg.x, cfg.y = x, y
    ns.Externals.Refresh()
end

-- THE RAID BAR, placed the same way as the two above it.
--
-- ONE DIFFERENCE, AND IT IS THE WHOLE OF ITS BEHAVIOUR: the bar is made of
-- protected buttons, so it cannot be moved, resized or hidden during a fight.
-- Nothing special is needed here for that - RaidBar.Refresh parks the work and
-- does it on the way out of combat - but a mover that appears to do nothing
-- mid-pull is a mover somebody will report, so the bar says so itself.
local function RaidBarPanel()
    local panel = ns.RaidBar and ns.RaidBar.Frame()
    if panel and panel:IsShown() then return panel end
    return nil
end

local function ApplyRaidBarMove(x, y)
    local cfg = ns.RaidBar.Config()
    cfg.x, cfg.y = x, y
    ns.RaidBar.Refresh()
end

-- THE TAUNT BUTTON, placed the same way. It belongs to the co-tank module, so
-- that is the switch its mover reads and the page its cog opens - a third
-- mover type for a forty-pixel square would be the drift this builder exists
-- to prevent.
local function TauntButton()
    local frame = ns.Taunts and ns.Taunts.Frame()
    if frame and frame:IsShown() then return frame end
    return nil
end

local function ApplyTauntMove(x, y)
    local cfg = ns.Taunts.Config()
    cfg.x, cfg.y = x, y
    ns.Taunts.Refresh()
end

-- THE ANSWER BAR, placed like the rest. Its cells are SECURE buttons, so the
-- mover never touches them - it sits over the frame they live in, and every
-- protected change (a size, an anchor, an attribute) happens in
-- Answers.Rebuild, out of combat.
local function AnswerBar()
    local frame = ns.Answers and ns.Answers.Frame()
    if frame and frame:IsShown() then return frame end
    return nil
end

local function ApplyAnswerMove(x, y)
    local cfg = ns.Answers.Config()
    cfg.x, cfg.y = x, y
    ns.Answers.Rebuild()
end


---------------------------------------------------------------------------
-- EVERY PLACED PANEL, IN ONE LIST, DESCRIBED ONCE.
--
-- THREE THINGS HAVE TO HAPPEN TO EACH OF THESE - a refresh, a drag and a
-- placing call - and until now they were written down in two places: a
-- Refresh<Name>Mover function per surface, and this list. Five functions of
-- eleven lines that differed in a module key, a label and an accessor, and
-- a list that had to REPEAT the frame getter and the apply function those
-- functions had already named.
--
-- Two lists is the bug, and not a theoretical one: the taunt button shipped
-- in 4.64.0 built, shown, wearing a cog and a padlock, and could not be
-- moved - the drag was a hand-written pair of lines beside a hand-written
-- list and nobody added the third thing. The comment that used to sit here
-- said exactly that. It was still true of the REFRESH, which had five
-- hand-written calls of its own further down this file.
--
-- So a surface is a ROW now, and adding a sixth is adding a row:
--
--   key      what the self test and the harness call it
--   module   the switch that decides whether it is on screen at all
--   panel    -> the live frame, or nil when there is nothing to place
--   apply    (x, y) -> write it down and redraw
--   label    what the box over it says
--   page     which options page its cog opens
--   config   -> the table `pinned` lives in
--   origin   -> where it is now
--
-- `mover` is filled in on the first refresh and belongs to the row. It was
-- five upvalues and five getters that returned them.
--
-- WHAT IS DELIBERATELY NOT IN HERE: the bars. A bar has anchors, a grow
-- point, a selection, a nudge pad, keyboard nudging and a shape that changes
-- with the mode. Flattening that into this row would mean a descriptor with
-- eight fields nobody else fills in. Two kinds of movable thing is honest;
-- eight nearly-identical ones was not, and one pretending to be general
-- would be worse than either.
---------------------------------------------------------------------------
PANEL_MOVERS = {
    { key = "tanks", module = "cotanks",
      panel = TankPanel, apply = ApplyTankMove,
      label = "Tank Unitframes", page = "cotanks",
      -- RAW, not through an accessor, and it is the one thing this surface
      -- does differently: ns.db.coTanks is filled in by ns.DEFAULTS rather
      -- than seeded by a Config() call of its own.
      config = function() return ns.db.coTanks end,
      origin = function()
          return ns.db.coTanks.x or 0, ns.db.coTanks.y or 0
      end },

    -- ITS MODULE AND ITS PAGE BELONG TO ANOTHER FEATURE, and that is not an
    -- inconsistency to tidy away: the taunt button is part of the co-tank
    -- module, so that is the switch it obeys and the page its cog opens. A
    -- row can say so plainly; a function named after the surface could only
    -- imply it.
    { key = "taunt", module = "cotanks",
      panel = TauntButton, apply = ApplyTauntMove,
      label = "Taunt button", page = "cotanks",
      config = function() return ns.Taunts.Config() end,
      origin = function()
          local cfg = ns.Taunts.Config()
          return cfg.x or 0, cfg.y or 0
      end },

    { key = "externals", module = "externals",
      panel = ExternalPanel, apply = ApplyExternalMove,
      label = "External CD request", page = "externals",
      config = function() return ns.Externals.Config() end,
      origin = function()
          local cfg = ns.Externals.Config()
          return cfg.x or 0, cfg.y or 0
      end },

    { key = "answers", module = "answers",
      panel = AnswerBar, apply = ApplyAnswerMove,
      label = "External CD answer", page = "answers",
      config = function() return ns.Answers.Config() end,
      origin = function()
          local cfg = ns.Answers.Config()
          return cfg.x or 0, cfg.y or 0
      end },


    { key = "raidbar", module = "raidbar",
      panel = RaidBarPanel, apply = ApplyRaidBarMove,
      label = "Raid Bar", page = "raidbar",
      config = function() return ns.RaidBar.Config() end,
      origin = function()
          local cfg = ns.RaidBar.Config()
          return cfg.x or 0, cfg.y or 0
      end },
}

-- The spec CreatePanelMover is handed, built FROM the row so the two cannot
-- drift apart. apply is wrapped rather than passed straight through because
-- the row's version is a plain function and the cog calls spec.apply with no
-- self - which is the shape the five hand-written specs already used.
local function PanelSpec(entry)
    return {
        label = entry.label,
        page = entry.page,
        module = entry.module,
        config = entry.config,
        origin = entry.origin,
        apply = function(x, y) entry.apply(x, y) end,
    }
end

local function RefreshPanelMovers()
    for _, entry in ipairs(PANEL_MOVERS) do
        -- A module that is not running has nothing on screen to place. Its
        -- frames still EXIST once it has run at all, so "is there a panel"
        -- is not the same question as "is this feature on", and both have to
        -- be asked - the second one here, the first inside RefreshPanelMover.
        if not ns.Modules:IsOn(entry.module) then
            if entry.mover then entry.mover:Hide() end
        else
            if not entry.mover then
                entry.mover = CreatePanelMover(PanelSpec(entry))
            end
            local x, y = entry.origin()
            RefreshPanelMover(entry.mover, entry.panel, x, y)
        end
    end
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
-- TWO BOOKS OF REMINDERS, ONE SET OF MOVERS (4.84.0). ns.Reminders and
-- ns.AnswerAlerts are the same class (Core/Reminders.lua) with different
-- specs, and their messages are placed the same way. So a mover belongs to
-- a BOOK and an index, and everything below that used to say ns.Reminders
-- says `book`. The list is walked in order; each row carries its own module
-- switch and options page, as the panel rows above do.
local BOOKS = {
    { book = function() return ns.Reminders end,
      module = "reminders", page = "reminders", movers = {} },
    { book = function() return ns.AnswerAlerts end,
      module = "answers", page = "answers", movers = {} },
}

local function ApplyReminderMove(entry, index, x, y)
    local book = entry.book()
    local cfg = book and book:Get(index)
    if not cfg then return end
    -- Centre terms, like the panel and like a bar with no anchor.
    cfg.point, cfg.relPoint = "CENTER", "CENTER"
    cfg.x, cfg.y = math.floor(x + 0.5), math.floor(y + 0.5)
    book:Style(index)
end

local function CreateReminderMover(entry, index)
    local mover = CreateFrame("Button", nil, overlay)
    mover:SetFrameLevel(overlay:GetFrameLevel() + 10)
    mover:RegisterForDrag("LeftButton")
    mover:Hide()

    mover.bg = mover:CreateTexture(nil, "BACKGROUND")
    mover.bg:SetAllPoints(mover)
    mover.bg:SetColorTexture(C.sidebarBg[1], C.sidebarBg[2], C.sidebarBg[3], 0.55)

    mover.edge = ns.CreateBorder(mover, 1, "BORDER")
    mover.edge:SetColor(C.accentDim[1], C.accentDim[2], C.accentDim[3], 1)

    -- THE SAME COG AND PADLOCK EVERY OTHER MOVER HAS.
    --
    -- Owner, with a screenshot of exactly this box: "mein reminder hat kein
    -- zahnrad oder lock". He said the same sentence on 2026-08-09 about the
    -- externals mover, and the answer then went into the PANEL builder -
    -- which this is not. See AttachTools.
    --
    -- A reminder is one of TWELVE, so `pinned` and "switch off" mean this
    -- one rather than the whole feature. Everything else the cog offers -
    -- centring, the settings page - is the same act on either surface.
    local spec = {
        label = "",
        page = entry.page,
        module = entry.module,
        config = function() return entry.book():Get(index) end,
        origin = function()
            local cfg = entry.book():Get(index)
            if not cfg then return 0, 0 end
            return cfg.x or 0, cfg.y or 0
        end,
        apply = function(x, y) ApplyReminderMove(entry, index, x, y) end,
        switchOff = { text = "Switch this one off", onClick = function()
            local book = entry.book()
            local cfg = book:Get(index)
            if not cfg then return end
            cfg.enabled = false
            book:Rebuild()
            EditMode:Refresh()
            ns.Options:Refresh()
        end },
    }
    mover.spec = spec
    local tab = AttachTools(mover, spec)

    -- The label sits ABOVE the box rather than in it. The box is exactly the
    -- size of the words the reminder itself is showing, and a second caption
    -- inside it would be printed over the thing being placed. Beside the
    -- strip rather than under it, now that there is one.
    mover.name = UI.Label(mover, "", 11, C.textDim)
    mover.name:SetPoint("LEFT", tab, "RIGHT", 6, 0)
    mover.name:SetWordWrap(false)

    mover.coords = UI.Label(mover, "", 10, C.textDim)
    mover.coords:SetPoint("TOP", mover, "BOTTOM", 0, -3)
    mover.coords:SetWordWrap(false)

    mover:SetScript("OnDragStart", function(self)
        local cfg = entry.book():Get(self.dkIndex)
        if not cfg then return end

        -- A PINNED REMINDER DOES NOT MOVE, which is the whole point of the
        -- padlock it has just been given. The panels have said this since
        -- they got theirs; this one had no padlock, so nothing read it.
        if cfg.pinned then return end

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
    mover.dkBook = entry
    return mover
end

local function DragReminders()
  for _, entry in ipairs(BOOKS) do
    local book = entry.book()
    for index, mover in ipairs(entry.movers) do
        if mover.grab then
            if not IsMouseButtonDown("LeftButton") then
                mover.grab = nil
                ShowGuide(guideX, nil, true)
                ShowGuide(guideY, nil, false)
                return
            end

            local frame = book and book:Frame(index)
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

            ApplyReminderMove(entry, index, x, y)
            ShowGuide(guideX, lineX, true)
            ShowGuide(guideY, lineY, false)
            return
        end
    end
  end
end

---------------------------------------------------------------------------
-- THE COOLDOWN BARS
--
-- A LIST, LIKE THE REMINDERS, AND NOT A SINGLETON LIKE THE PANELS. That is
-- the whole reason this is a third block rather than five more rows in
-- PANEL_MOVERS: there is one co-tank panel and one taunt button, and there
-- are as many bars as you make.
--
-- FOLLOWED BY ID, NOT BY POSITION. `Store.Bars()` is a list and deleting one
-- reshuffles every index below it, so a mover that remembered "I am number 3"
-- would start dragging somebody else's bar the moment a bar above it went.
-- The id is the thing 4.82.0 already stored for exactly this reason - see
-- Cooldowns/Bars.lua - and it is never reused.
---------------------------------------------------------------------------
local barMovers = {}

-- The bars in a stable order, with their containers. One walk, because every
-- reader below wants the same pairing, and building it twice is how a mover
-- and the thing it drags end up disagreeing about which bar is which.
local function BarList()
    local out = {}
    local Cooldowns = ns.Cooldowns
    if not (Cooldowns and Cooldowns.Store and Cooldowns.Render) then return out end
    if not ns.Modules:IsOn("cooldowns") then return out end

    local containers = Cooldowns.Render.Containers()
    for _, bar in pairs(Cooldowns.Store.Bars()) do
        if type(bar) == "table" and bar.id and bar.enabled ~= false then
            out[#out + 1] = { bar = bar, frame = containers[bar.id] }
        end
    end
    table.sort(out, function(a, b) return (a.bar.id or 0) < (b.bar.id or 0) end)
    return out
end

local function BarByID(id)
    local Cooldowns = ns.Cooldowns
    local store = Cooldowns and Cooldowns.Store
    return store and store.ByID(id) or nil
end

local function ApplyBarMove(id, x, y)
    local bar = BarByID(id)
    if not bar then return end
    -- Centre terms, like the panels and the reminders. A bar pinned by one of
    -- its own corners is a later wave; until then the readout means what it
    -- says on every surface this addon places.
    bar.point, bar.relPoint = "CENTER", "CENTER"
    bar.x, bar.y = math.floor(x + 0.5), math.floor(y + 0.5)
    if ns.Cooldowns.Render then ns.Cooldowns.Render.Refresh() end
end

local function CreateBarMover(index)
    local mover = CreateFrame("Button", nil, overlay)
    mover:SetFrameLevel(overlay:GetFrameLevel() + 10)
    mover:RegisterForDrag("LeftButton")
    mover:Hide()

    mover.bg = mover:CreateTexture(nil, "BACKGROUND")
    mover.bg:SetAllPoints(mover)
    mover.bg:SetColorTexture(C.sidebarBg[1], C.sidebarBg[2], C.sidebarBg[3], 0.55)

    mover.edge = ns.CreateBorder(mover, 1, "BORDER")
    mover.edge:SetColor(C.accentDim[1], C.accentDim[2], C.accentDim[3], 1)

    -- THE COG AND THE PADLOCK EVERY OTHER MOVER HAS. The owner has now asked
    -- for these twice on two different surfaces - the externals mover and the
    -- reminders - and both times the answer went into the builder that was
    -- not this one. Third surface, same tools, from the start.
    --
    -- A bar is one of SEVERAL, so `pinned` and "switch off" mean this bar
    -- rather than the whole module - the reminders' reading, not the panels'.
    local spec = {
        label = "",
        page = "cooldowns",
        module = "cooldowns",
        config = function() return BarByID(mover.dkBarID) end,
        origin = function()
            local bar = BarByID(mover.dkBarID)
            if not bar then return 0, 0 end
            return bar.x or 0, bar.y or 0
        end,
        apply = function(x, y) ApplyBarMove(mover.dkBarID, x, y) end,
        switchOff = { text = "Switch this one off", onClick = function()
            local bar = BarByID(mover.dkBarID)
            if not bar then return end
            bar.enabled = false
            if ns.Cooldowns.Render then ns.Cooldowns.Render.Refresh() end
            EditMode:Refresh()
            ns.Options:Refresh()
        end },
    }
    mover.spec = spec
    local tab = AttachTools(mover, spec)

    -- Beside the tool strip rather than inside the box: the box is exactly
    -- the size of the bar, and on a row of five 40-pixel icons a caption
    -- printed inside it would sit on top of the icons being placed.
    mover.name = UI.Label(mover, "", 11, C.textDim)
    mover.name:SetPoint("LEFT", tab, "RIGHT", 6, 0)
    mover.name:SetWordWrap(false)

    mover.coords = UI.Label(mover, "", 10, C.textDim)
    mover.coords:SetPoint("TOP", mover, "BOTTOM", 0, -3)
    mover.coords:SetWordWrap(false)

    mover:SetScript("OnDragStart", function(self)
        local bar = BarByID(self.dkBarID)
        if not bar then return end
        -- A PINNED BAR DOES NOT MOVE. That is what its padlock is for, and
        -- the bar you have finished placing is exactly the one a stray drag
        -- lands on while you are still placing the other.
        if bar.pinned then return end

        local cursorX, cursorY = CursorPosition()
        self.grab = {
            cursorX = cursorX, cursorY = cursorY,
            originX = bar.x or 0, originY = bar.y or 0,
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

local function DragBars()
    for _, mover in ipairs(barMovers) do
        if mover.grab then
            if not IsMouseButtonDown("LeftButton") then
                mover.grab = nil
                ShowGuide(guideX, nil, true)
                ShowGuide(guideY, nil, false)
                return
            end

            local frame = mover.dkFrame
            if not frame then return end

            local cursorX, cursorY = CursorPosition()
            local x = mover.grab.originX + (cursorX - mover.grab.cursorX)
            local y = mover.grab.originY + (cursorY - mover.grab.cursorY)

            local lineX, lineY
            if not IsAltKeyDown() then
                -- The bar's own scale, exactly as the reminders do it: the
                -- saved x and y are in screen terms and the width is not.
                local scale = frame:GetScale()
                if not scale or scale <= 0 then scale = 1 end
                local snappedX, gx = Snap(x, nil, frame:GetWidth() * scale / 2, "x")
                local snappedY, gy = Snap(y, nil, frame:GetHeight() * scale / 2, "y")
                x, y = snappedX, snappedY
                lineX, lineY = gx, gy
            end

            ApplyBarMove(mover.dkBarID, x, y)
            ShowGuide(guideX, lineX, true)
            ShowGuide(guideY, lineY, false)
            return
        end
    end
end

local function RefreshBarMovers()
    local list = BarList()

    for index, entry in ipairs(list) do
        local mover = barMovers[index]
        if not mover then
            mover = CreateBarMover(index)
            barMovers[index] = mover
        end

        -- WHICH BAR THIS MOVER IS FOR, written before anything reads it. The
        -- movers are pooled by position and the bars are sorted by id, so the
        -- pairing changes whenever a bar is added or deleted - and every
        -- closure above reads dkBarID rather than closing over the id it
        -- happened to have when it was built.
        mover.dkBarID = entry.bar.id
        mover.dkFrame = entry.frame

        if not (entry.frame and EditMode.overlayShown and entry.frame:IsShown()) then
            mover:Hide()
        else
            mover:ClearAllPoints()
            mover:SetAllPoints(entry.frame)
            mover.name:SetText(entry.bar.name or "Bar")
            mover.coords:SetText(string.format("%d, %d",
                entry.bar.x or 0, entry.bar.y or 0))
            mover.coords:SetShown(Prefs().showCoords or mover.grab ~= nil)
            mover:RefreshLock()
            mover:Show()
        end
    end

    for index = #list + 1, #barMovers do barMovers[index]:Hide() end
end

local function RefreshReminderMovers()
  for _, entry in ipairs(BOOKS) do
    local book = entry.book()
    local movers = entry.movers
    -- Same as the panel above: switched off, there is nothing to place, and
    -- the frames of a module that ran earlier this session are still there.
    local count = (book and ns.Modules:IsOn(entry.module)) and book:Count() or 0

    for index = 1, count do
        local mover = movers[index]
        if not mover then
            mover = CreateReminderMover(entry, index)
            movers[index] = mover
        end

        local frame = book:Frame(index)
        local cfg = book:Get(index)
        -- Not while the options page has it: the frame is then parented into
        -- a card inside a window, and a mover pinned to it would be a box
        -- floating over the settings.
        if not (frame and cfg and EditMode.overlayShown and not book.hosted) then
            mover:Hide()
        else
            mover:ClearAllPoints()
            mover:SetAllPoints(frame)
            mover.name:SetText(book:Label(cfg, index))
            mover.coords:SetText(string.format("%d, %d", cfg.x or 0, cfg.y or 0))
            mover.coords:SetShown(Prefs().showCoords or mover.grab ~= nil)
            -- The padlock has to say which way it is, and a reminder can be
            -- pinned from the options page as well as from its own cog.
            mover:RefreshLock()
            mover:Show()
        end
    end

    for index = count + 1, #movers do movers[index]:Hide() end
  end
end

local function OnUpdate()
    -- EVERY PANEL MOVER, and the list is why the taunt button could not be
    -- moved at all in 4.64.0: it was created, shown, and given a cog and a
    -- padlock, and then nothing dragged it. A mover is TWO halves - the frame
    -- and this line - and the second one is easy to forget because the first
    -- one looks finished. That is what PanelMovers() is for below.
    for _, entry in ipairs(PANEL_MOVERS) do
        DragPanel(entry.mover, entry.panel, entry.apply)
    end
    DragReminders()
    DragBars()
    if not dragging then return end

    -- The button can be let go anywhere, including over another window or off
    -- the edge of the screen, and OnMouseUp only fires on the frame it went
    -- down on. Without this the bar stays glued to the cursor.
    if not IsMouseButtonDown("LeftButton") then
        StopDrag()
        return
    end

    local mover = dragging.mover
    local cursorX, cursorY = CursorPosition()
    local width, height = mover:GetWidth() or 0, mover:GetHeight() or 0
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
        local centreX, guideLineX = Snap(x + dragging.toCentreX, mover,
            width / 2, "x")
        local centreY, guideLineY = Snap(y + dragging.toCentreY, mover,
            height / 2, "y")

        x, y = centreX - dragging.toCentreX, centreY - dragging.toCentreY
        lineX, lineY = guideLineX, guideLineY
    end

    if mover.Place then mover:Place(x, y) end
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

        local direction = ARROWS[key]
        if not direction then
            Propagate(self, true)
            return
        end

        local step = IsShiftKeyDown() and NUDGE_FAST or NUDGE

        if not selected then
            Propagate(self, true)
            return
        end

        Propagate(self, false)
        selected:Nudge(direction[1] * step, direction[2] * step)
    end)

    keyCatcher:SetScript("OnKeyUp", function(self)
        Propagate(self, true)
    end)
end

---------------------------------------------------------------------------
-- The panel
--
-- Always visible while unlocked, including while the overlay is hidden -
-- otherwise Shift + Right Click would be a one-way door.
---------------------------------------------------------------------------
-- One line under the toolbar saying what the mouse and the keys do here.
-- It used to have a second half about the picked cell; there are no cells.
function RefreshInspector()
    if not inspector then return end

    -- The snapping state is STATED, not implied. It lives on two switches in
    -- a panel you have to open, so "why does nothing snap" was a question
    -- this screen could answer and did not - it explained how to suspend
    -- snapping while snapping was switched off.
    local prefs = Prefs()
    local snapLine
    if prefs.snapToGrid then
        snapLine = string.format(
            "Snaps to the other panels, the screen edges and a %d grid. "
            .. "Hold Alt to place it free.", prefs.gridStep or 40)
    else
        snapLine = "Snaps to the other panels and the screen edges. "
            .. "Hold Alt to place it free."
    end

    inspector:SetText("Drag a panel. Arrow keys nudge it, Shift for 10.\n"
        .. snapLine)
end

---------------------------------------------------------------------------
-- The tool panel, back - the SCREEN half of it
--
-- The old panel had two halves: the screen settings and the selected bar's.
-- It went out whole with the cooldown bars ("Edit Mode keeps its panels" -
-- the panels stayed, the panel of TOOLS did not), and the owner noticed the
-- day the rest was finished: "im edit mode fehlen die tools, wie grid
-- groessen anpassen, snapping und und. das ist irgendwie mit rausgeflogen."
--
-- He is right on both counts. The bar half belonged to the bars and stays
-- gone; the SCREEN half - the grid and its step, snap-to-grid, how far a
-- snap catches, the dim, the coordinates - is about placing PANELS, which is
-- what Edit Mode still does all day. Its five settings kept their defaults,
-- their reader and their store the whole time; what fell out was the one
-- link in the chain a user can see, the control.
--
-- EVERY WRITE IS A NAMED SETTER ON EditMode, not a closure in a row: the
-- desk cannot press a toggle, but it can call SetGridStep(24) and read the
-- profile - so the rules are testable and the rows stay thin.
---------------------------------------------------------------------------
function EditMode:SetGridStep(value)
    value = tonumber(value)
    if not value then return end
    Prefs().gridStep = math.max(4, math.floor(value))
    DrawGrid()
    RefreshInspector()
end

function EditMode:SetSnapToGrid(on)
    Prefs().snapToGrid = on and true or false
    RefreshInspector()
end

function EditMode:SetSnapCatch(value)
    value = tonumber(value)
    if not value then return end
    Prefs().snapDistance = math.max(1, math.floor(value))
end

function EditMode:SetDim(value)
    value = tonumber(value)
    if not value then return end
    if value < 0 then value = 0 elseif value > 0.8 then value = 0.8 end
    Prefs().dim = value
    if overlay and overlay.dim then
        overlay.dim:SetColorTexture(0, 0, 0, value)
    end
end

function EditMode:SetCoordsShown(on)
    Prefs().showCoords = on and true or false
    if unlocked then self:Refresh() end
end

local function BuildTools()
    tools = CreateFrame("Frame", nil, overlay)
    tools:SetSize(320, 236)
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

    -- Untranslated like every other label on this surface - the toolbar's
    -- buttons say "Grid" and "Done" in plain English too.
    tools.rows = {}
    local previous
    local function Row(label, wire)
        local row = UI.Row(tools, label)
        row:SetHeight(30)
        row:SetPoint("LEFT", tools, "LEFT", 10, 0)
        row:SetPoint("RIGHT", tools, "RIGHT", -10, 0)
        if previous then
            row:SetPoint("TOP", previous, "BOTTOM", 0, -2)
        else
            row:SetPoint("TOP", tools, "TOP", 0, -40)
        end
        previous = row
        wire(row)
        tools.rows[#tools.rows + 1] = row
        return row
    end

    Row("Grid", function(row)
        UI.Toggle(row,
            function() return gridLines and gridLines:IsShown() or false end,
            function(value) EditMode:SetGridShown(value) end)
    end)
    Row("Snap to grid", function(row)
        UI.Toggle(row, function() return Prefs().snapToGrid end,
            function(value) EditMode:SetSnapToGrid(value) end)
    end)
    Row("Grid step", function(row)
        UI.Slider(row, { min = 8, max = 160, step = 4,
            get = function() return Prefs().gridStep end,
            set = function(value) EditMode:SetGridStep(value) end })
    end)
    Row("Snap catch", function(row)
        UI.Slider(row, { min = 2, max = 40, step = 1,
            get = function() return Prefs().snapDistance end,
            set = function(value) EditMode:SetSnapCatch(value) end })
    end)
    Row("Dim", function(row)
        UI.Slider(row, { min = 0, max = 0.8, step = 0.05,
            get = function() return Prefs().dim end,
            set = function(value) EditMode:SetDim(value) end })
    end)
    Row("Coordinates", function(row)
        UI.Toggle(row, function() return Prefs().showCoords end,
            function(value) EditMode:SetCoordsShown(value) end)
    end)

    tools.Refresh = function()
        for _, row in ipairs(tools.rows) do
            if row.Refresh then row.Refresh() end
        end
    end
    tools:SetScript("OnShow", tools.Refresh)

    -- Published for the desk, which walks the rows rather than trusting
    -- that a panel with a working title also has working controls.
    EditMode.toolsPanel = tools
end

function EditMode:ToggleTools()
    if not tools then return end
    tools:SetShown(not tools:IsShown())
end

local function BuildToolbar()
    toolbar = CreateFrame("Frame", nil, overlay)
    -- WIDE ENOUGH FOR THE BOTTOM ROW, measured rather than chosen: Grid,
    -- Hide overlay, Set keys and Done sit in it left to right, and Done is
    -- anchored to the RIGHT edge - so a toolbar that is too narrow does not
    -- clip, it puts two buttons on top of each other.
    --
    -- The number was raised twice for exactly that, the second time for a
    -- build mode that has since gone out with the cooldown bars. What is
    -- left is the four above, and the width stays until something measures
    -- them again.
    toolbar:SetSize(544, 108)
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

    inspector = UI.Label(toolbar, "", 11, C.textDim)
    -- Handed over the way the overlay button is, so the desk can read what
    -- the band actually says rather than trusting that something wrote it.
    EditMode.inspectorLabel = inspector
    inspector:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 12, -14)
    inspector:SetWidth(toolbar:GetWidth() - 24)
    inspector:SetJustifyH("LEFT")
    inspector:SetJustifyV("TOP")

    local gridBtn = UI.Button(toolbar, "Grid", 68, function()
        EditMode:SetGridShown(not (gridLines and gridLines:IsShown()))
    end)
    gridBtn:SetPoint("BOTTOMLEFT", toolbar, "BOTTOMLEFT", 12, 12)

    -- The way into the restored panel. Next to Grid because the panel is
    -- mostly ABOUT the grid; a screen setting you cannot reach from the
    -- screen is the fault this button undoes.
    local toolsBtn = UI.Button(toolbar, "Tools", 68, function()
        EditMode:ToggleTools()
    end)
    toolsBtn:SetPoint("LEFT", gridBtn, "RIGHT", 6, 0)

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
    overlayBtn:SetPoint("LEFT", toolsBtn, "RIGHT", 6, 0)

    -- SET KEYS, IN THE BOX WITH THE REST. Owner: "set keys, die funktion,
    -- gehoert noch als button in den edit modus! in die grosse box." It is
    -- the same kind of thing as everything else here - something you do to
    -- the panels while they are out - and it was reachable only from two
    -- settings pages.
    --
    -- IT HANDS OVER RATHER THAN LAYERING. Both modes put squares over the
    -- same panels; up at once, Edit Mode's movers sit on top and swallow the
    -- click that was meant to bind a key. So Edit Mode closes first - and the
    -- "who do I hand the window back to" token goes with it, so that leaving
    -- the key mode reopens the window if that is where you came from.
    --
    -- Asked BEFORE closing anything, because a mode that refuses after Edit
    -- Mode has already packed up leaves you nowhere you asked to be.
    local keysBtn = UI.Button(toolbar, "Set keys",
        UI.ButtonWidth("Set keys"), function()
            local why = ns.Keys:Blocked()
            if why then ns.Print(why) return end

            local fromWindow = EditMode.cameFromWindow
            EditMode.cameFromWindow = false
            EditMode:SetUnlocked(false)
            ns.Keys:SetActive(true)
            ns.Keys.cameFromWindow = fromWindow
        end)
    keysBtn:SetPoint("LEFT", overlayBtn, "RIGHT", 6, 0)

    -- The padlock, because that is what Done DOES: it locks the bars again.
    local doneBtn = UI.Button(toolbar, "Done", 92, function()
        EditMode:SetUnlocked(false)
    end, "primary")
    doneBtn:SetPoint("BOTTOMRIGHT", toolbar, "BOTTOMRIGHT", -12, 12)
    doneBtn:SetIcon("ui-lock")

    toolbar.Refresh = function()
        -- The active mode is the one that reads as pressed. Two buttons and a
        -- colour beats a segmented control nobody can tell is interactive -
        -- but the colour has to be the BED, not the label. A dimmed label is
        -- what SetEnabled does, so "not the current mode" and "you cannot
        -- press this" looked the same on the one control that has to be
        -- unmistakable. UI.Button:SetActive lights it the way the chip row
        -- and the CURRENT badge light theirs.
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
    BuildKeyCatcher()
end

---------------------------------------------------------------------------
-- Keeping the overlay in step with the bars
--
-- Movers and handles are rebuilt from the bar list rather than kept in step by
-- hand, so adding or deleting a bar while unlocked cannot leave a panel behind.
---------------------------------------------------------------------------
function EditMode:Refresh()
    if not (unlocked and overlay) then return end

    -- ONE CALL, NOT FIVE. These were five hand-written lines beside a
    -- hand-written list, which is the exact shape that left the taunt button
    -- unmovable for a whole release.
    RefreshPanelMovers()
    RefreshReminderMovers()
    RefreshBarMovers()

    -- AND THE LINE THAT SAYS WHAT TO DO. It used to be refreshed from the
    -- mode switch, and the mode switch went with the bars - so the panel
    -- opened with an empty band where the instructions belong. Nothing threw
    -- and no check noticed: an empty FontString looks exactly like a
    -- FontString nobody has written to yet.
    RefreshInspector()
end

-- The panel movers, by name, for the self test and for the harness.
--
-- Both of them have to carry the same two controls as a bar's mover, and "it
-- has a cog" is the sort of thing that stays true right up until somebody
-- adds a third panel and builds it by hand. Nil until edit mode has been
-- opened once - they are made on first refresh.
function EditMode:PanelMovers()
    -- BUILT FROM THE SAME LIST THAT DRAGS THEM. It used to be written out by
    -- hand, which is how the taunt button ended up with a mover, a cog and a
    -- padlock and no way to move it: OnUpdate had its own hand-written pair
    -- of lines and nobody added the third. Two lists is the bug; one list is
    -- the fix, and the self test walks this one.
    local out = {}
    for _, entry in ipairs(PANEL_MOVERS) do
        out[entry.key] = entry.mover
    end
    return out
end

-- THE REMINDER MOVERS, for the same reason and by the same route.
--
-- They are a LIST rather than a set of named singletons, so they get their
-- own accessor instead of joining the one above - but they owe the check the
-- same answer: a cog, a padlock, and a spec that knows what those two do.
-- Without this the self test could not see them at all, which is how they
-- went five days wearing neither.
function EditMode:ReminderMovers()
    local out = {}
    for _, entry in ipairs(BOOKS) do
        for _, mover in ipairs(entry.movers) do out[#out + 1] = mover end
    end
    return out
end

-- THE BAR MOVERS, and they owe the check the same answer the other two do: a
-- cog, a padlock, and a spec that knows what those two are for. Two surfaces
-- have now shipped without them because the builder that grew the tools was
-- not the builder that made the box, so this is what the self test walks.
function EditMode:BarMovers()
    local out = {}
    for index, mover in ipairs(barMovers) do out[index] = mover end
    return out
end

function EditMode:SetGridShown(shown)
    if gridLines then gridLines:SetShown(shown and unlocked) end
    -- The toolbar button and the panel's toggle both move this; whichever
    -- one was pressed, the other must not keep saying yesterday's state.
    if tools and tools:IsShown() and tools.Refresh then tools.Refresh() end
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
        mover:SetShown(self.overlayShown)
    end
    if not self.overlayShown then
        guideX:Hide()
        guideY:Hide()
    else
        self:Refresh()
    end
end

function EditMode:IsUnlocked()
    return unlocked
end

-- There is one mode: things come out, you place them, Done puts them back.
-- the mode - which is a step the button already knew the answer to.
function EditMode:SetUnlocked(state)
    state = state and true or false
    if state == unlocked then return end

    Build()
    unlocked = state
    self.overlayShown = true
    dragging, selected = nil, nil

    -- THE CO-TANK PANEL COMES OUT WHILE YOU ARE PLACING IT. It hides itself
    -- when the feature is off, when you are solo, or when nobody else is
    -- tanking - which is very nearly always, for somebody who has just opened
    -- edit mode to put it somewhere. `locked` is what ShouldShow reads, and
    -- it outranks the master switch on purpose.
    if ns.CoTanks and ns.CoTanks.panel then
        ns.db.coTanks.locked = not state
        ns.CoTanks:Refresh()
    end

    -- AND THE EXTERNALS PANEL, for the sharpest version of the same reason:
    -- it hides a slot nobody in the group can fill, and the group you are
    -- standing in while placing it is usually nobody at all. Placing shows
    -- every slot you picked, or there is nothing on screen to put anywhere.
    if ns.Externals then ns.Externals:SetPlacing(state) end
    if ns.Taunts then ns.Taunts:SetPlacing(state) end
    if ns.Answers then ns.Answers:SetPlacing(state) end

    -- THE RAID BAR, which hides itself when you are alone - and somebody
    -- opening edit mode to place it is alone almost by definition. It refuses
    -- in combat like everything else it does; the mover simply has nothing to
    -- sit on until the fight ends, which is the honest behaviour rather than a
    -- bar that moves and snaps back.
    if ns.RaidBar then ns.RaidBar:SetPlacing(state) end

    -- AND SO DO THE REMINDERS, for the same reason one layer sharper: a
    -- reminder is on screen only while the thing it names is wrong. Waiting
    -- for Bone Shield to fall off in order to place the message about Bone
    -- Shield falling off is not a workflow.
    if ns.Reminders then ns.Reminders:SetPlacing(state) end
    -- And the answer alerts, which are up only while somebody is asking.
    if ns.AnswerAlerts then ns.AnswerAlerts:SetPlacing(state) end

    if state then
        -- The window would sit behind the overlay, catching clicks that were
        -- meant for a bar. Unlocking is a full-screen mode, so it gets the
        -- full screen.
        --
        -- AND IT COMES BACK IF IT WAS THE WAY IN. Owner, 2026-08-10: "wenn
        -- ich aus dem addon in den edit mode gehe und den edit mode verlasse,
        -- sollte das addon wieder aufgehen" - and in the same breath the
        -- other half, which is what makes this a rule rather than a
        -- convenience: "wenn ich nur rechtsklick auf dem minimap icon mache
        -- [...] kein addon öffnen".
        --
        -- So it is not "always reopen". Edit mode gives back what it took: a
        -- window it hid, it puts back, and a window that was never open stays
        -- shut. The minimap and /zs unlock are the second case and need no
        -- special handling at all - there was nothing to hide.
        self.cameFromWindow = ns.Options.frame
            and ns.Options.frame:IsShown() and true or false
        if ns.Options.frame then ns.Options.frame:Hide() end

        overlay:Show()
        keyCatcher:Show()
        self:SetOverlayShown(true)
        self:Refresh()
        -- WHAT IT SAYS HAS TO BE WHAT THE BAND SAYS. This line named the two
        -- modes - "Move bars" and "Build" - for a week after both of them
        -- went out with the cooldown bars, so the first thing the mode said
        -- about itself was two buttons that are not there. It now says what
        -- the instruction band above the toolbar says, and if one of them
        -- changes the other is wrong.
        ns.Print("Unlocked. Drag any panel to move it; arrow keys nudge it, "
            .. "|cffffd100Shift|r for ten. |cffffd100Done|r or "
            .. "|cffffd100/zs lock|r when you are finished.")
    else
        UI.ClosePopup()
        overlay:Hide()
        keyCatcher:Hide()
        Propagate(keyCatcher, true)
        if gridLines then gridLines:Hide() end

        -- Handed back, and only once: a second lock does not conjure a
        -- window nobody opened.
        if self.cameFromWindow then
            self.cameFromWindow = false
            if ns.Options then ns.Options:Open() end
        end
    end
end

function EditMode:Toggle()
    self:SetUnlocked(not unlocked)
end

