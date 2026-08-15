---------------------------------------------------------------------------
-- Putting the icons where the model says.
--
-- The join between three things that already exist and one that did not:
-- Store reads the bar, Model says where each cell is, Claim does the writing,
-- and this file is the pass that walks a bar and calls them in order. It
-- writes to nothing Blizzard owns - the desk guard watches it, because
-- `local item = ns.CDM:ItemForSpell(...)` is one of the eight doors and a
-- SetPoint on that name here fails the build.
--
---------------------------------------------------------------------------
-- THE CELL FRAMES ARE OURS, AND THAT IS THE WHOLE DESIGN.
--
-- A bar is our container; inside it sits one small frame per slot, also ours;
-- and Blizzard's item frame is anchored to its slot at an offset of ZERO.
-- Three reasons, and the first one is not obvious enough to rediscover:
--
-- 1. AN ANCHOR OFFSET IS MEASURED IN THE ANCHORED FRAME'S OWN SCALE. Blizzard
--    scales its item frames - Edit Mode has a slider for it - so an item told
--    to sit 84 units right of our container's centre lands at 84 times ITS
--    scale, not ours. Every icon after the first would be wrong, by more the
--    further along the row it sits, which reads as "the spacing setting is
--    broken" rather than as a unit. An offset of zero is the same number in
--    every coordinate system there is. Only the SIZE still needs correcting,
--    and that is Claim's ScaleRatio.
--
-- 2. THE EDITOR NEEDS THE RECTANGLES. Wave 3 draws the empty slots, drags one
--    cell onto another and shows the arrangement while nothing is on cooldown.
--    All of that is about the SLOT rather than about whatever frame is
--    currently in it, and a slot with no frame of its own is a rectangle that
--    exists only as four numbers inside a render pass.
--
-- 3. A SLOT OUTLIVES ITS OCCUPANT. Blizzard hands its frames out of a pool:
--    the frame showing Divine Shield this second is not the one that showed
--    it before the spec change. Anchoring cell to container and item to cell
--    means a re-issued frame is one Claim.Place call, not a relayout.
---------------------------------------------------------------------------
local _, ns = ...

local Cooldowns = ns.Cooldowns
local Render = {}
Cooldowns.Render = Render

-- Captured at file scope, which makes the TOC ORDER load-bearing: Contract,
-- Model, Store, Rivals, Claim, then this. A desk guard reads the TOC and
-- fails the build if that order is ever disturbed, because the failure it
-- would otherwise produce is `attempt to index a nil value` on login and
-- nothing at all out here.
local Model = Cooldowns.Model
local Store = Cooldowns.Store
local Claim = Cooldowns.Claim
local Effects = Cooldowns.Effects
local Look = Cooldowns.Look
local Text = Cooldowns.Text
local Fill = Cooldowns.Fill

---------------------------------------------------------------------------
-- Our frames
---------------------------------------------------------------------------

-- barID -> our container. Kept across a refresh: a frame cannot be destroyed
-- in this API, so building one per pass would leak one per pass.
local containers = {}

local function Container(bar)
    local frame = containers[bar.id]
    if not frame then
        frame = CreateFrame("Frame", nil, UIParent)
        frame:SetFrameStrata("MEDIUM")
        frame:SetClampedToScreen(true)
        frame.cells = {}
        frame.barID = bar.id
        containers[bar.id] = frame
    end
    return frame
end

-- One slot frame, made on demand and reused. `index` is the SLOT, not the
-- cell: two cells never share a slot, but a cell's slot changes when the
-- arrangement closes a gap.
local function Cell(container, index)
    local cell = container.cells[index]
    if not cell then
        cell = CreateFrame("Frame", nil, container)
        cell.index = index
        container.cells[index] = cell
    end
    return cell
end

---------------------------------------------------------------------------
-- One bar
---------------------------------------------------------------------------

-- WHAT SIZE THIS FRAME SHOULD DRAW AT IN THIS SLOT.
--
-- The slot knows how big it is. The frame knows what SHAPE it is. Those are
-- two different facts and conflating them is the fault the old renderer's own
-- header describes: a square icon told to fill a 250-wide bar slot smears its
-- art across a quarter of the screen.
--
-- So an icon-shaped frame in a bar-shaped slot stays SQUARE at the slot's
-- height, and `iconPlacement` says which end of the slot it sits at. That key
-- was filed under wave 4 with the rest of the look, and it is geometry - the
-- same mistake, and the same correction, as barWidth and lineSpacing in wave
-- 1. "hidden" means the slot is a bar for a spell we have no bar frame for,
-- and showing a lone square there is worse than showing nothing.
local function Fit(item, slot, placement)
    local wide = slot.w > slot.h + 0.5
    if not wide or ns.CDM:ItemShape(item) == "bar" then
        return "CENTER", 0, slot.w, slot.h
    end

    placement = placement or "left"
    if placement == "hidden" then return nil end
    if placement == "right" then
        return "RIGHT", 0, slot.h, slot.h
    end
    return "LEFT", 0, slot.h, slot.h
end

-- Walks one bar and returns how many of its cells found a live frame.
--
-- `claimed` is filled in rather than returned, because the takeover pass
-- afterwards needs every bar's answer at once - a frame on bar two must not
-- be veiled because bar one did not want it.
-- `factor` is what ns.Visibility says this bar's rule comes to: 1 when every
-- rule agrees, and whatever "otherwise" is set to when one does not. Handed
-- in rather than asked for here, because Render.Refresh has already asked
-- once to decide whether to draw the bar at all - and two answers to one
-- question is how a bar ends up half drawn at the wrong brightness.
local function DrawBar(bar, claimed, factor)
    local container = Container(bar)
    local cells = Store.Cells(bar)
    local count = Store.Capacity(bar)
    local opts = Store.Lattice(bar)

    -- WHICH CELLS HAVE A LIVE FRAME AT ALL. A cell whose spell has none is a
    -- hole, and a hole STAYS a hole: the point of a fixed grid is that a
    -- spell is always in the same place.
    local items = {}
    for index = 1, count do
        local spellID = cells[index]
        items[index] = spellID and ns.CDM:ItemForSpell(spellID) or nil
    end

    -- AND WHICH ARE HIDDEN BY A RULE, WHICH IS NOT THE SAME QUESTION.
    --
    -- Wave 2 fed the compactor "this cell has no live frame" and it was dead
    -- code, because nothing set a reflow mode. The day one did, his five-icon
    -- row would have re-packed itself every time Blizzard stopped pooling a
    -- situational spell - a bar that rearranges itself when nothing about it
    -- changed. 4.82.0 fed Compact the STATE map only (Screen.lua:1240-1248)
    -- and so does this: closing a gap is something a rule you switched on
    -- does, never something a missing frame does behind your back.
    local hidden, compact = Effects.Pass(bar, items, count)
    local places = Model.Places(count, opts, hidden, compact)

    -- The box, measured off the slots rather than from a formula - see
    -- Model.Extent. The offsets below turn cell-1-centre coordinates into
    -- container-centre ones, which is what the third and fourth answers are.
    local boxW, boxH, offX, offY = Model.Extent(count, opts)
    container:SetSize(math.max(1, boxW), math.max(1, boxH))
    container:ClearAllPoints()
    container:SetPoint(bar.point or "CENTER", UIParent,
        bar.relPoint or "CENTER", tonumber(bar.x) or 0, tonumber(bar.y) or 0)
    container:SetScale(tonumber(bar.scale) or 1)
    container:Show()

    local drawn = 0
    for index = 1, count do
        local cell = Cell(container, index)
        local at = places[index]

        if at then
            cell:SetSize(at.w, at.h)
            cell:ClearAllPoints()
            cell:SetPoint("CENTER", container, "CENTER",
                at.x - offX, at.y - offY)
            cell:Show()

            local item = items[index]
            if item then
                local point, inset, width, height =
                    Fit(item, at, bar.iconPlacement)
                if point then
                    Claim.Strip(item)
                    Claim.Place(item,
                        { point, cell, point, inset, 0 }, width, height)

                    -- THE ORDER IS THE PICTURE, and it is not arbitrary.
                    --
                    -- Look last of the three that dress it: it is the file
                    -- that decides whether this cell is on screen at all -
                    -- Claim.Reveal or Claim.Veil, folded out of `alpha` and
                    -- `inactiveAlpha` - and a cell told to be visible before
                    -- its fill and its numbers are right flickers the old
                    -- ones for a frame.
                    --
                    -- Text before Look for the same reason and Fill before
                    -- Text because Fill owns the widget Text writes over.
                    local style = Text.Style(bar, at.h)
                    Fill.Apply(item, bar, index, cells[index])
                    Text.Apply(item, style)

                    -- THE SHOW RULE ARRIVES AS OPACITY, and that is the only
                    -- place it can arrive. Rule 4 allows a claimed frame
                    -- alpha 1 and nothing else, so "half hidden" cannot be
                    -- spent on the frame - Look.Apply already solved exactly
                    -- this for the bar's own Opacity setting with a veil
                    -- texture on our OWN chrome, and this multiplies into the
                    -- same number rather than adding a second dimmer that
                    -- would multiply with it by accident.
                    --
                    -- Multiplied onto a FRESH table: Look.Style builds one per
                    -- call, so nothing stored is being written here.
                    local look = Look.Style(bar, index)
                    if factor and factor < 1 then
                        look.alpha = (tonumber(look.alpha) or 1) * factor
                    end
                    Look.Apply(item, look)
                    Effects.Track(item, cell, bar, cells[index])

                    -- THE SPELL NAME, AND ONLY RENDER KNOWS WHETHER THERE IS
                    -- ROOM FOR ONE.
                    --
                    -- It is written on OUR cell rather than on their frame,
                    -- and it stands down unless the slot is wider than it is
                    -- tall: a square has no band beside the icon to put a
                    -- word in, and a buff-bar frame already writes its own
                    -- name along itself - ours on top of that is the same
                    -- word twice, the second one pushed into an ellipsis.
                    --
                    -- `width` is what the icon actually took, so the name
                    -- starts where the picture ends however the icon was
                    -- placed. Its own nine positions are honoured inside
                    -- Text.Caption; both old renderers anchored it hard to
                    -- the left and ignored the setting, which is a control
                    -- that cannot do anything - and the owner found it by
                    -- trying it.
                    local band = (at.w > at.h + 0.5)
                        and ns.CDM:ItemShape(item) ~= "bar" and width or nil
                    Text.Caption(cell, style, cells[index], band,
                        bar.iconPlacement)

                    claimed[item] = true
                    drawn = drawn + 1
                end
            end
        else
            cell:Hide()
        end
    end

    -- Slots left over from a wider arrangement. They are ours, so hiding them
    -- is allowed and is the only way a bar narrowed from twelve to five stops
    -- carrying seven empty rectangles.
    for index = count + 1, #container.cells do
        container.cells[index]:Hide()
    end

    return drawn
end

local function HideBar(bar)
    local container = containers[bar.id]
    if container then container:Hide() end
end

---------------------------------------------------------------------------
-- Everything the user did NOT place
--
-- `takeOverCDM` has defaulted to true since the bars existed and is one of
-- the keys the removal promised not to touch, so it is read here in the shape
-- it was written in: anything but an explicit false means yes.
--
-- Alpha only, never Hide - rule 4 and rule 1. And switching the takeover off
-- has to give those frames back rather than merely stop veiling them, or
-- Blizzard's display stays blank with nothing left holding it that way.
---------------------------------------------------------------------------
local function Takeover(claimed)
    local takeover = ns.db.takeOverCDM ~= false

    ns.CDM:ForEachItemEverywhere(function(item)
        if claimed[item] then return end

        if takeover then
            Claim.Veil(item)
        elseif Cooldowns.Known(item) then
            Claim.Give(item)
        end
    end)
end

---------------------------------------------------------------------------
-- The pass
---------------------------------------------------------------------------

-- "MY BAR IS EMPTY" AND "THE COOLDOWN MANAGER IS OFF" LOOK IDENTICAL.
--
-- An adopted icon is still Blizzard's child, so a viewer switched off in
-- Blizzard's own Edit Mode takes our icons down with it: every frame is
-- pooled, pinned to exactly the right cell, and nothing is on screen.
--
-- Said once per session, and only when a cell actually wanted one of those
-- frames - a warning that fires for somebody who has placed nothing is noise.
local warned = false

local function WarnIfInvisible(drawn)
    if warned or drawn == 0 then return end

    local hidden = ns.CDM:HiddenViewers()
    if not hidden then return end

    warned = true
    ns.Print("|cffff4040These Cooldown Manager viewers are switched off:|r "
        .. hidden)
    ns.Print("Your icons ARE on the bar - they are Blizzard's frames, and a "
        .. "switched-off viewer hides its own children. Turn it back on in "
        .. "Blizzard's Edit Mode (Escape, Edit Mode, Cooldown Manager).")
end

function Render.Refresh()
    if not ns.Modules:IsOn("cooldowns") then return Render.Stop() end
    if not (ns.CDM.IsAvailable and ns.CDM:IsAvailable()) then return 0 end

    -- ONE PASS BOUNDARY. Everything the effects layer remembers per pass -
    -- which cells a rule turned off, whether any sound is wanted at all -
    -- is cleared here rather than per bar, so a spell sitting on two bars is
    -- one answer rather than two that can disagree.
    Effects.BeginPass()

    local claimed, drawn = {}, 0

    for _, bar in pairs(Store.Bars()) do
        if type(bar) == "table" and bar.id then
            -- WHETHER THIS BAR IS ON SCREEN AT ALL, asked of ns.Visibility
            -- rather than of bar.enabled.
            --
            -- ns.Visibility has been complete since 4.82.0 - the rules, the
            -- events, the explanation - and until this line it had NOT ONE
            -- CALLER. `show` sat in Store.READERS.now under "the states and
            -- the effects", which is a table whose whole job is to say which
            -- keys are read; for this key it was simply untrue. Every rule
            -- anybody had set was stored, listed as read, and ignored.
            --
            -- Factor rather than Evaluate: it folds `enabled == false` and
            -- mode "never" into the same number as a rule that does not
            -- match, so there is one answer and one place that decides it.
            local factor = ns.Visibility:Factor(bar)
            if factor <= 0 then
                HideBar(bar)
            else
                drawn = drawn + DrawBar(bar, claimed, factor)
            end
        end
    end

    Takeover(claimed)
    WarnIfInvisible(drawn)
    return drawn
end

-- HANDS EVERYTHING BACK AND TAKES OUR SCAFFOLDING OFF SCREEN.
--
-- What the module switch calls, and it has to be the complete inverse of a
-- render pass: every frame released at the decoration it had before, every
-- container hidden. A release that only stops REFRESHING would leave the
-- icons pinned exactly where they are with nothing left able to name them.
function Render.Stop()
    -- THE TICKERS FIRST. Each of these arms its own OnUpdate and disarms it
    -- when its list empties; handing the frames back without emptying the
    -- lists would leave two tickers walking frames that are Blizzard's again
    -- - which is not a leak that shows on screen, and therefore one nobody
    -- would ever find.
    Effects.StopAll()
    Fill.ReleaseAll()

    local given = Claim.GiveAll()
    for _, container in pairs(containers) do container:Hide() end
    return given
end

-- The containers, for the self test and for the editor that comes next.
function Render.Containers()
    return containers
end

---------------------------------------------------------------------------
-- When it runs
--
-- The pools churn on talents, spec changes and Blizzard's own situational
-- show and hide, and CDM already centralises that into one notification -
-- rebuilt BEFORE the listeners, so the first question every listener asks
-- ("which frame is this spell") is answered from this second's index rather
-- than from last minute's.
---------------------------------------------------------------------------
function Render.Start()
    if Render.started then return end
    Render.started = true

    -- WHEN A STATE FLIPS, THE ARRANGEMENT MAY HAVE TO CHANGE. Effects.lua
    -- loads above this file and cannot name it, so it asks to be called back
    -- instead. Guarded against re-entry by the pass boundary above: a repaint
    -- asked for from inside a repaint would recurse.
    Effects.OnRepaint(function()
        if ns.Modules:IsOn("cooldowns") then Render.Refresh() end
    end)

    ns.CDM:OnChanged(function()
        if ns.Modules:IsOn("cooldowns") then Render.Refresh() end
    end)

    -- AND WHEN THE WORLD CHANGES UNDER THE RULES. Combat, group, target,
    -- resting, zone and spec - ns.Visibility watches all eight events and
    -- samples ONCE per change, so twelve bars asking twelve questions is one
    -- pass over the game rather than twelve. Never a timer: polling the group
    -- size sixty times a second to learn something that changes twice an
    -- evening is how an addon earns a reputation.
    ns.Visibility:OnChanged(function()
        if ns.Modules:IsOn("cooldowns") then Render.Refresh() end
    end)
    -- Sampled before the first pass, or every rule is evaluated against the
    -- state table's own initial values - "not in combat, alone, out in the
    -- world" - until the first event happens to fire.
    ns.Visibility:Start()

    Render.Refresh()
end
