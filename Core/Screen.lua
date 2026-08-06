---------------------------------------------------------------------------
-- Screen - the bars, on screen.
--
-- A cell holds a spell, and there are exactly two kinds of spell. They are
-- rendered by two completely different mechanisms, and knowing which is which
-- is most of this file:
--
--   A COOLDOWN MANAGER SPELL is not drawn. Blizzard already owns a frame for
--   it - correct icon, swipe, charges, stacks and timing, all computed inside
--   the game where secret values are not a problem. We adopt that frame: move
--   it onto our cell and hold it there. Drawing our own would mean reading
--   aura data, which patch 12.0 forbids outright.
--
--   AN AURA PROC has no such frame - that is the whole reason Core/Auras.lua
--   exists. There we draw the icon ourselves and run our own clock, started
--   by the glow on the ability the aura empowers.
--
-- THE RULES FOR TOUCHING BLIZZARD'S FRAMES, and they are not style advice.
-- Taken verbatim from the reference implementation on this machine
-- (EllesmereUICooldownManager/EllesmereUICdmHooks.lua, top of file):
--
--     Never SetParent/SetScale/Hide/Show on Blizzard frames
--     Never move Blizzard frames offscreen
--     Never write custom keys to Blizzard frame tables
--     All per-frame data in external weak-keyed tables
--     Unclaimed frames: SetAlpha(0). Claimed: SetAlpha(1).
--
-- Two consequences run through everything below:
--
--   * An adopted frame stays Blizzard's child, so it does NOT inherit our
--     scale or our alpha. "Scale" is therefore a size multiplier here, not a
--     SetScale, and per-bar opacity is pushed into the frame itself. Both
--     would otherwise apply to our own cells and silently skip half the bar.
--   * A cooldown you did not place vanishes with alpha, never with Hide().
--
-- WHY IT TAKES OVER RATHER THAN SITTING NEXT TO IT.
--
-- Blizzard lays its viewer out by walking its active frames and placing them
-- in a row. It has no idea one of them now lives on our bar, so it leaves a
-- hole where that one used to be. There is no version of this where the
-- original bar still looks right - so the default is to take the display
-- over completely, and the setting to switch that off says what it costs.
---------------------------------------------------------------------------
local _, ns = ...

local Screen = {}
ns.Screen = Screen

---------------------------------------------------------------------------
-- Where a cell sits, and how big it is
--
-- Everything is multiplied by the bar's scale HERE rather than through
-- SetScale, because adopted frames are not our children - see the header.
---------------------------------------------------------------------------
local function Metrics(cfg)
    local scale = cfg.scale or 1
    local width, height

    if cfg.kind == "bar" then
        width  = (cfg.barWidth or 200) * scale
        height = (cfg.barHeight or 24) * scale
    else
        width  = (cfg.iconSize or 40) * scale
        height = width
    end

    return width, height, (cfg.spacing or 4) * scale, (cfg.lineSpacing or 4) * scale
end

local function CellOffset(cfg, index, width, height, spacing, lineSpacing)
    local columns = math.max(1, cfg.columns or 1)
    local column  = (index - 1) % columns
    local row     = math.floor((index - 1) / columns)
    return column * (width + spacing), -(row * (height + lineSpacing))
end

---------------------------------------------------------------------------
-- Aura cells - our own icon, our own clock
--
-- The remaining time is a number we own (measured, see Core/Auras.lua), so
-- SetCooldown takes plain numbers here. Nothing on this path reads aura data,
-- which is exactly why it works on 12.0.
---------------------------------------------------------------------------
local function BuildAuraVisual(cell)
    if cell.aura then return cell.aura end

    local aura = CreateFrame("Frame", nil, cell)
    aura:SetAllPoints(cell)

    aura.bg = aura:CreateTexture(nil, "BACKGROUND")
    aura.bg:SetAllPoints(aura)
    aura.bg:SetColorTexture(0, 0, 0, 0.9)

    aura.icon = aura:CreateTexture(nil, "ARTWORK")
    aura.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    aura.cd = CreateFrame("Cooldown", nil, aura, "CooldownFrameTemplate")
    aura.cd:SetDrawEdge(false)
    aura.cd:SetDrawSwipe(true)
    aura.cd:SetSwipeColor(0, 0, 0, 0.7)
    aura.cd:SetHideCountdownNumbers(false)
    -- The engine draws the number; OmniCC drawing a second one on top of it
    -- is the usual cause of a doubled countdown.
    aura.cd.noCooldownCount = true

    aura.textLayer = CreateFrame("Frame", nil, aura)
    aura.textLayer:SetAllPoints(aura)
    aura.textLayer:SetFrameLevel(aura.cd:GetFrameLevel() + 2)

    -- On the text layer, not on the cell. A texture on a frame is painted
    -- under that frame's own child frames whatever layer it claims, and the
    -- cooldown swipe is one of them - the border would darken along with the
    -- icon as the cooldown ran, while the adopted icons next to it did not.
    aura.border = ns.CreateBorder(aura.textLayer, 1, "OVERLAY")

    aura.label = aura.textLayer:CreateFontString(nil, "OVERLAY")
    aura.label:SetJustifyH("LEFT")
    aura.label:SetWordWrap(false)
    -- A font HERE, not only where the size is chosen. Icon cells hide the
    -- label and never reach that branch, and SetText on a font string with no
    -- font raises rather than doing nothing.
    ns.StyleUIFont(aura.label, 11)

    cell.aura = aura
    return aura
end

-- The same style table the adopted frames get, applied to the parts we drew
-- ourselves. Kept next to each other on purpose: these two are the ones that
-- must never disagree, because they sit on the same bar.
local function StyleAuraVisual(aura, style)
    local plate = style.backdropColor
    aura.bg:SetColorTexture(plate[1], plate[2], plate[3], style.backdropAlpha)
    aura.bg:SetShown(style.backdrop)

    local zoom = style.iconZoom
    aura.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)

    local edge = style.borderColor
    aura.border:SetThickness(style.borderSize)
    aura.border:SetColor(edge[1], edge[2], edge[3], 1)
    aura.border:SetShown(style.borderSize > 0)

    local swipe = style.swipeColor
    aura.cd:SetSwipeColor(swipe[1], swipe[2], swipe[3], style.swipeAlpha)
    aura.cd:SetDrawEdge(style.showEdge)
    aura.cd:SetHideCountdownNumbers(not style.showCountdown)
    if style.showCountdown then
        ns.StyleNumbers(aura.cd, style.countdownSize, style.countdownColor,
            style.countdownAnchor)
    end

    ns.StyleUIFont(aura.label, style.nameSize)
    aura.label:SetTextColor(style.nameColor[1], style.nameColor[2],
        style.nameColor[3])
end

-- Bar-shaped aura cells put the icon on the left and the name beside it;
-- icon-shaped ones are just the icon.
local function LayoutAuraVisual(aura, cfg, width, height)
    if cfg.kind == "bar" then
        -- Square, wherever it sits. Same rule as an adopted icon: a spell
        -- icon stretched to the width of a bar is what a tracking bar must
        -- never look like.
        local placement = cfg.iconPlacement or "left"
        local shown = placement ~= "hidden"

        aura.icon:ClearAllPoints()
        aura.icon:SetShown(shown)
        if shown then
            local side = placement == "right" and "RIGHT" or "LEFT"
            aura.icon:SetPoint("TOP" .. side, aura, "TOP" .. side, 0, 0)
            aura.icon:SetPoint("BOTTOM" .. side, aura, "BOTTOM" .. side, 0, 0)
            aura.icon:SetWidth(height)
        end

        local inset = shown and (height + 5) or 5
        aura.label:ClearAllPoints()
        if shown and placement == "right" then
            aura.label:SetPoint("LEFT", aura, "LEFT", 5, 0)
        else
            aura.label:SetPoint("LEFT", aura, "LEFT", inset, 0)
        end
        aura.label:SetWidth(math.max(10, width - inset - 5))
        aura.label:SetShown(cfg.showName ~= false)

        aura.cd:ClearAllPoints()
        if shown then
            aura.cd:SetAllPoints(aura.icon)
        else
            aura.cd:SetAllPoints(aura)
        end
    else
        -- Edge to edge, exactly like an adopted icon: Blizzard's fill the
        -- whole frame and the border sits over them. A one-pixel inset here
        -- and none there is the kind of difference nobody can name and
        -- everybody sees.
        aura.icon:ClearAllPoints()
        aura.icon:SetAllPoints(aura)

        aura.label:Hide()

        aura.cd:ClearAllPoints()
        aura.cd:SetAllPoints(aura.icon)
    end
end

-- Cooldown:Clear does not exist on every build this addon supports, so the
-- fallback is the two-zero SetCooldown that has always meant the same thing.
local function ClearCooldown(cd)
    if cd.Clear then
        cd:Clear()
    else
        cd:SetCooldown(0, 0)
    end
end

-- Active auras are lit; inactive ones stay in place, dimmed. A cell that
-- disappeared entirely would make the bar re-flow under the eye, and the
-- point of a fixed grid is that a spell is always in the same place.
local function PaintAura(cell, active)
    local aura = cell.aura
    if not aura then return end

    aura.icon:SetDesaturated(not active)
    if active then
        aura.icon:SetVertexColor(1, 1, 1)
        aura:SetAlpha(1)
    else
        aura.icon:SetVertexColor(0.6, 0.6, 0.6)
        -- A cell whose spell is taken by an earlier bar is dimmer still: it
        -- is not waiting to light up, it is never going to.
        aura:SetAlpha(cell.conflict and 0.18 or 0.35)
        ClearCooldown(aura.cd)
    end
end

---------------------------------------------------------------------------
-- Which live Cooldown Manager frame stands for which spell
--
-- Rebuilt whenever the pools churn rather than searched per cell: a spec
-- change, a talent change and entering combat all reshuffle them.
---------------------------------------------------------------------------
local itemBySpell = {}
local itemViewer  = {}   -- which viewer an item came from: it decides its shape
local held = {}          -- every item we have touched, so it can be handed back

local function RebuildItemIndex()
    wipe(itemBySpell)
    wipe(itemViewer)
    for _, viewer in ipairs(ns.CDM.VIEWERS) do
        ns.CDM:ForEachItem(viewer.key, function(item)
            local spellID = ns.CDM:ItemSpellID(item)
            if spellID and not itemBySpell[spellID] then
                itemBySpell[spellID] = item
                itemViewer[item] = viewer
            end
        end)
    end
end

-- Where an adopted frame goes inside a cell, and how big it is.
--
-- A frame from the buff-BAR viewer is already bar shaped, so it fills a bar
-- cell. Everything else is an icon and must stay SQUARE: stretching a spell
-- icon across the width of a bar is the one thing a tracking bar must never
-- look like, and it is what happens if a cell simply hands over its size.
local function ItemGeometry(cfg, cell, item, width, height)
    local viewer = itemViewer[item]
    local isBarShaped = viewer ~= nil and viewer.kind == "bar"

    if cfg.kind ~= "bar" or isBarShaped then
        return { "TOPLEFT", cell, "TOPLEFT", 0, 0 }, width, height, true
    end

    local placement = cfg.iconPlacement or "left"
    if placement == "hidden" then
        return nil, height, height, false
    end
    if placement == "right" then
        return { "TOPRIGHT", cell, "TOPRIGHT", 0, 0 }, height, height, true
    end
    return { "TOPLEFT", cell, "TOPLEFT", 0, 0 }, height, height, true
end

---------------------------------------------------------------------------
-- Bars
---------------------------------------------------------------------------
local barFrames = {}

local function CreateCell(bar, index)
    local cell = CreateFrame("Frame", nil, bar)
    cell.index = index

    -- Only ever seen while unlocked: in play an empty cell is nothing at all.
    cell.slot = cell:CreateTexture(nil, "BACKGROUND")
    cell.slot:SetAllPoints(cell)
    cell.slot:SetColorTexture(1, 1, 1, 0.05)
    cell.slot:Hide()

    cell.slotEdge = ns.CreateBorder(cell, 1, "BORDER")
    cell.slotEdge:SetColor(1, 1, 1, 0.18)
    cell.slotEdge:Hide()

    return cell
end

local function CreateBarFrame(index)
    local bar = CreateFrame("Frame", "ZwoelfStuffBar" .. index, UIParent)
    bar:SetFrameStrata("MEDIUM")
    bar:SetClampedToScreen(true)
    bar.cells = {}
    bar.index = index
    return bar
end

function Screen:BarFrame(index)
    return barFrames[index]
end

function Screen:ApplyPosition(index)
    local cfg = ns.db.bars[index]
    local bar = barFrames[index]
    if not (cfg and bar) then return end

    bar:ClearAllPoints()

    -- Attached to another bar: the parent's FRAME is the anchor, so moving or
    -- resizing the parent carries this one along without a single line of
    -- follow-up code. Falls through to the screen if the parent has no frame
    -- yet, which happens while the list is still being built.
    if cfg.anchor then
        local _, parentIndex = ns.Bars:ByID(cfg.anchor.to)
        local parent = parentIndex and barFrames[parentIndex]
        if parent then
            bar:SetPoint(cfg.anchor.point, parent, cfg.anchor.relPoint,
                cfg.anchor.x or 0, cfg.anchor.y or 0)
            return
        end
    end

    bar:SetPoint(cfg.point or "CENTER", UIParent, cfg.relPoint or "CENTER",
        cfg.x or 0, cfg.y or 0)
end

-- Writes where the bar ACTUALLY is back into the config, as a centre offset
-- from the screen centre. Used when a bar is detached: its stored x/y are
-- from before it was attached, and dropping it somewhere it has not been for
-- an hour is the kind of surprise that makes people stop using a feature.
function Screen:CapturePosition(index)
    local cfg = ns.db.bars[index]
    local bar = barFrames[index]
    if not (cfg and bar) then return end

    local centreX, centreY = bar:GetCenter()
    local screenX, screenY = UIParent:GetCenter()
    if not (centreX and screenX) then return end

    cfg.point, cfg.relPoint = "CENTER", "CENTER"
    cfg.x = math.floor(centreX - screenX + 0.5)
    cfg.y = math.floor(centreY - screenY + 0.5)
end

---------------------------------------------------------------------------
-- The render pass
--
-- One function, run whenever anything could have changed. It claims what it
-- needs, and hands back everything it did not claim - which is what keeps a
-- deleted bar from leaving Blizzard's icons stranded in mid-air.
---------------------------------------------------------------------------
local claimedBy = {}     -- spellID -> "bar name" of whoever got it first

function Screen:Render()
    if not ns.db then return end

    RebuildItemIndex()
    wipe(claimedBy)

    local claimedNow = {}

    -- Built ONCE per pass. Asking Auras for its catalogue per cell meant
    -- rebuilding the whole proc list - talent scan included - forty times for
    -- one spec change.
    local auraBySpell = {}
    if ns.Auras then
        for _, entry in ipairs(ns.Auras:Catalogue()) do
            auraBySpell[entry.spellID] = entry
        end
    end

    for index, cfg in ipairs(ns.db.bars) do
        local bar = barFrames[index]
        if not bar then
            bar = CreateBarFrame(index)
            barFrames[index] = bar
        end

        local width, height, spacing, lineSpacing = Metrics(cfg)
        -- Resolved once per bar and handed to BOTH renderers. Read separately
        -- by each, "auto" would eventually mean two different sizes.
        local style = ns.Bars:Style(cfg, height)
        local columns = math.max(1, cfg.columns or 1)
        local rows    = math.max(1, cfg.rows or 1)
        local count   = columns * rows

        bar:SetSize(columns * width + (columns - 1) * spacing,
                    rows * height + (rows - 1) * lineSpacing)
        self:ApplyPosition(index)
        bar:SetShown(cfg.enabled ~= false)

        for cellIndex = 1, count do
            local cell = bar.cells[cellIndex]
            if not cell then
                cell = CreateCell(bar, cellIndex)
                bar.cells[cellIndex] = cell
            end

            cell:SetSize(width, height)
            cell:ClearAllPoints()
            local offsetX, offsetY = CellOffset(cfg, cellIndex, width, height,
                spacing, lineSpacing)
            cell:SetPoint("TOPLEFT", bar, "TOPLEFT", offsetX, offsetY)
            cell:Show()

            self:PaintCell(bar, cell, cfg, width, height, claimedNow,
                auraBySpell, style)
        end

        -- Cells left over from a smaller grid. The aura record has to go with
        -- them, or a hidden cell would still answer the glow that drives it.
        for cellIndex = count + 1, #bar.cells do
            local cell = bar.cells[cellIndex]
            cell:Hide()
            cell.auraEntry, cell.conflict = nil, nil
            if cell.item then
                ns.CDM:Release(cell.item)
                cell.item = nil
            end
        end
    end

    -- Bars that no longer exist.
    for index = #ns.db.bars + 1, #barFrames do
        local bar = barFrames[index]
        if bar then
            for _, cell in ipairs(bar.cells) do
                if cell.item then
                    ns.CDM:Release(cell.item)
                    cell.item = nil
                end
            end
            bar:Hide()
        end
    end

    -- A second pass for attached bars. The first one runs in list order, so a
    -- bar anchored to one BELOW it in the list found no frame to hang on yet
    -- and fell back to the screen. Cheap, and it removes an ordering rule
    -- nobody would remember.
    for index, cfg in ipairs(ns.db.bars) do
        if cfg.anchor then self:ApplyPosition(index) end
    end

    self:ApplyTakeover(claimedNow)

    -- A moment later, because a rival addon reacts to the same events we do
    -- and asking straight away would only ever see our own anchor.
    if not self.rivalCheckQueued then
        self.rivalCheckQueued = true
        C_Timer.After(1, function()
            Screen.rivalCheckQueued = false
            ns.CDM:CheckForRivals()
            Screen:WarnIfInvisible()
        end)
    end

    if ns.EditMode and ns.EditMode.Refresh then ns.EditMode:Refresh() end
end

-- The spell's name next to an adopted icon in a bar-shaped cell.
--
-- Ours, on our own cell, because the name is not something Blizzard's icon
-- frame carries - and a bar cell holding nothing but a square icon in one
-- corner reads as broken rather than as deliberate.
function Screen:PaintCaption(cell, cfg, spellID, width, height, iconWidth, style)
    if cfg.kind ~= "bar" or not style.showName then
        if cell.caption then cell.caption:Hide() end
        return
    end

    if not cell.caption then
        local layer = CreateFrame("Frame", nil, cell)
        layer:SetAllPoints(cell)
        layer:SetFrameLevel(cell:GetFrameLevel() + 10)
        cell.caption = layer:CreateFontString(nil, "OVERLAY")
        cell.caption:SetJustifyH("LEFT")
        cell.caption:SetWordWrap(false)
    end

    local placement = cfg.iconPlacement or "left"
    local inset = iconWidth > 0 and (iconWidth + 5) or 5

    cell.caption:ClearAllPoints()
    if placement == "right" and iconWidth > 0 then
        cell.caption:SetPoint("LEFT", cell, "LEFT", 5, 0)
        cell.caption:SetWidth(math.max(10, width - inset - 5))
    else
        cell.caption:SetPoint("LEFT", cell, "LEFT", inset, 0)
        cell.caption:SetWidth(math.max(10, width - inset - 5))
    end

    ns.StyleUIFont(cell.caption, style.nameSize)
    cell.caption:SetTextColor(style.nameColor[1], style.nameColor[2],
        style.nameColor[3])
    cell.caption:SetText(ns.SpellName(spellID) or "")
    cell.caption:Show()
end

-- One cell: adopt, draw, or leave empty.
function Screen:PaintCell(bar, cell, cfg, width, height, claimedNow, auraBySpell, style)
    local spellID = cfg.cells[cell.index]

    -- Whatever this cell held last time is handed back before anything else,
    -- or moving a spell would leave its old frame pinned to a dead cell.
    if cell.item and (not spellID or ns.CDM:ItemSpellID(cell.item) ~= spellID) then
        ns.CDM:Release(cell.item)
        cell.item = nil
    end

    if not spellID then
        if cell.aura then cell.aura:Hide() end
        if cell.caption then cell.caption:Hide() end
        cell.spellID, cell.auraEntry, cell.conflict = nil, nil, nil
        return
    end

    cell.spellID = spellID

    local item = itemBySpell[spellID]
    if item and not claimedNow[item] then
        -- A Cooldown Manager spell: adopt Blizzard's frame.
        claimedNow[item] = true
        claimedBy[spellID] = cfg.name or ("Bar " .. bar.index)
        held[item] = true
        cell.item = item
        cell.auraEntry, cell.conflict = nil, nil
        if cell.aura then cell.aura:Hide() end

        local anchor, itemWidth, itemHeight, visible =
            ItemGeometry(cfg, cell, item, width, height)

        if anchor then
            ns.CDM:Pin(item, anchor, itemWidth, itemHeight)
        end
        ns.CDM:SetAlpha(item, visible and (cfg.alpha or 1) or 0)
        ns.CDM:Skin(item, style)

        self:PaintCaption(cell, cfg, spellID, width, height,
            visible and itemWidth or 0, style)
        return
    end

    -- The same spell on two bars. One frame cannot be in two places, so the
    -- first bar keeps it and this cell is drawn dimmer rather than empty -
    -- an empty cell where you know you put something reads as a fault.
    cell.item = nil
    cell.conflict = item and claimedBy[spellID] or nil

    -- An aura proc, or a cooldown whose frame is not pooled right now. It
    -- carries its own name, so the caption for adopted icons stands down.
    if cell.caption then cell.caption:Hide() end

    local aura = BuildAuraVisual(cell)
    aura:Show()
    LayoutAuraVisual(aura, cfg, width, height)
    StyleAuraVisual(aura, style)

    aura.icon:SetTexture(ns.SpellTexture(spellID))
    aura.label:SetText(ns.SpellName(spellID) or "")

    -- Looked up per render rather than cached on the cell: a respec changes
    -- which procs exist, and a stale record would drive a clock off a glow
    -- this build can no longer raise.
    cell.auraEntry = auraBySpell[spellID]
    PaintAura(cell, cell.active and true or false)
end

-- Everything the user did not place. Alpha only - see the header.
function Screen:ApplyTakeover(claimedNow)
    local takeover = ns.db.takeOverCDM ~= false

    ns.CDM:ForEachItemEverywhere(function(item)
        if claimedNow[item] then return end

        if takeover then
            held[item] = true
            ns.CDM:SetAlpha(item, 0)
        elseif held[item] then
            ns.CDM:Release(item)
            held[item] = nil
        end
    end)
end

-- "My bar is empty" and "the Cooldown Manager is off" look identical from the
-- outside. An adopted icon is still Blizzard's child, so a viewer switched
-- off in Blizzard's own Edit Mode takes our icons with it - everything on our
-- side is correct and nothing is on screen. Said once, and only when a cell
-- actually wanted one of those frames.
function Screen:WarnIfInvisible()
    if self.invisibleReported then return end

    local hidden = ns.CDM:HiddenViewers()
    if not hidden then return end

    local wanted = false
    for _, cfg in ipairs(ns.db.bars) do
        for _, spellID in pairs(cfg.cells) do
            if itemBySpell[spellID] then wanted = true break end
        end
        if wanted then break end
    end
    if not wanted then return end

    self.invisibleReported = true
    ns.Print("|cffff4040These Cooldown Manager viewers are switched off:|r " .. hidden)
    ns.Print("Your icons ARE on the bar - they are Blizzard's frames, and a "
        .. "switched-off viewer hides its own children. Turn it back on in "
        .. "Blizzard's Edit Mode (Escape, Edit Mode, Cooldown Manager).")
end

-- Hands every frame back and lets Blizzard have its display again. Used when
-- the takeover is switched off, and on the way out.
function Screen:ReleaseAll()
    for item in pairs(held) do
        ns.CDM:Release(item)
    end
    wipe(held)
end

---------------------------------------------------------------------------
-- The clock for aura cells
--
-- Driven by the glow on the ability the aura empowers - the only signal that
-- is readable on 12.0. On 12.1 the same cell gets its timing from the aura
-- itself; that route is prepared in Core/Auras.lua and lands here as a
-- different entry.route.
---------------------------------------------------------------------------
local function ForEachAuraCell(fn)
    for index, bar in ipairs(barFrames) do
        local cfg = ns.db.bars[index]
        if cfg then
            for _, cell in ipairs(bar.cells) do
                if cell.auraEntry then fn(cell, cell.auraEntry, cfg) end
            end
        end
    end
end

function Screen:StartAura(parentSpellID)
    ForEachAuraCell(function(cell, entry)
        if entry.parent ~= parentSpellID then return end
        cell.active = true
        local duration = entry.duration or 0
        if duration > 0 then
            cell.aura.cd:SetCooldown(GetTime(), duration)
        else
            ClearCooldown(cell.aura.cd)
        end
        PaintAura(cell, true)
    end)
end

function Screen:StopAura(parentSpellID)
    ForEachAuraCell(function(cell, entry)
        if entry.parent ~= parentSpellID then return end
        cell.active = false
        PaintAura(cell, false)
    end)
end

-- After a reload the glow may already be up, and no event will announce it
-- again. IsSpellOverlayed is a plain boolean and never touches aura data.
function Screen:ResyncAuras()
    local isOverlayed = C_SpellActivationOverlay
        and C_SpellActivationOverlay.IsSpellOverlayed
    if not isOverlayed then return end

    ForEachAuraCell(function(cell, entry)
        local ok, active = pcall(isOverlayed, entry.parent)
        cell.active = (ok and active) and true or false
        PaintAura(cell, cell.active)
    end)
end

---------------------------------------------------------------------------
-- Unlocked look
--
-- The grid itself becomes visible, so an empty bar is still something you can
-- see and grab. Nothing here changes what is saved.
---------------------------------------------------------------------------
function Screen:SetUnlocked(unlocked)
    for index, bar in ipairs(barFrames) do
        local cfg = ns.db.bars[index]
        if cfg then
            -- A disabled bar is shown while unlocked, or it could never be
            -- found again to switch back on.
            bar:SetShown(unlocked or cfg.enabled ~= false)
            for _, cell in ipairs(bar.cells) do
                cell.slot:SetShown(unlocked and cell:IsShown())
                cell.slotEdge:SetShown(unlocked and cell:IsShown())
            end
        end
    end
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
events:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
events:RegisterEvent("PLAYER_ENTERING_WORLD")

events:SetScript("OnEvent", function(_, event, spellID)
    if event == "PLAYER_ENTERING_WORLD" then
        Screen:Render()
        Screen:ResyncAuras()
        return
    end

    -- Computing on a secret value throws; these carry plain IDs, but the
    -- check costs nothing and the alternative is a broken event handler.
    if not ns.CanCompute(spellID) then return end

    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        Screen:StartAura(spellID)
    else
        Screen:StopAura(spellID)
    end
end)

function Screen:Start()
    ns.Bars:OnChanged(function() Screen:Render() end)
    ns.CDM:OnChanged(function() Screen:Render() end)
    self:Render()
    self:ResyncAuras()
end
