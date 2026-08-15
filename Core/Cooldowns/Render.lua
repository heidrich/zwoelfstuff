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
local function DrawBar(bar, claimed)
    local container = Container(bar)
    local cells = Store.Cells(bar)
    local count = Store.Capacity(bar)
    local opts = Store.Lattice(bar)

    -- WHICH CELLS HAVE NOTHING TO DRAW. A cell whose spell has no live frame
    -- is a hole, and in wave 2 a hole STAYS a hole: the point of a fixed grid
    -- is that a spell is always in the same place. Closing the gaps up is
    -- Layout.Compact, it is driven by a setting under `effects`, and it
    -- belongs to the wave that owns that setting.
    local items, hidden = {}, {}
    for index = 1, count do
        local spellID = cells[index]
        local item = spellID and ns.CDM:ItemForSpell(spellID) or nil
        if item then items[index] = item else hidden[index] = true end
    end

    local places = Model.Places(count, opts, hidden, nil)

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
                    Claim.Reveal(item)
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

    local claimed, drawn = {}, 0

    for _, bar in pairs(Store.Bars()) do
        if type(bar) == "table" and bar.id then
            if bar.enabled == false then
                HideBar(bar)
            else
                drawn = drawn + DrawBar(bar, claimed)
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

    ns.CDM:OnChanged(function()
        if ns.Modules:IsOn("cooldowns") then Render.Refresh() end
    end)

    Render.Refresh()
end
