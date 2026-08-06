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

    aura.border = ns.CreateBorder(aura, 1, "OVERLAY")

    aura.textLayer = CreateFrame("Frame", nil, aura)
    aura.textLayer:SetAllPoints(aura)
    aura.textLayer:SetFrameLevel(aura.cd:GetFrameLevel() + 2)

    aura.label = aura.textLayer:CreateFontString(nil, "OVERLAY")
    aura.label:SetJustifyH("LEFT")
    aura.label:SetWordWrap(false)

    cell.aura = aura
    return aura
end

-- Bar-shaped aura cells put the icon on the left and the name beside it;
-- icon-shaped ones are just the icon.
local function LayoutAuraVisual(aura, cfg, width, height)
    if cfg.kind == "bar" then
        aura.icon:ClearAllPoints()
        aura.icon:SetPoint("TOPLEFT", aura, "TOPLEFT", 1, -1)
        aura.icon:SetPoint("BOTTOMLEFT", aura, "BOTTOMLEFT", 1, 1)
        aura.icon:SetWidth(height - 2)

        aura.label:ClearAllPoints()
        aura.label:SetPoint("LEFT", aura.icon, "RIGHT", 5, 0)
        aura.label:SetWidth(math.max(10, width - height - 10))
        aura.label:Show()
        ns.StyleUIFont(aura.label, math.max(9, math.min(14, height * 0.45)))

        aura.cd:ClearAllPoints()
        aura.cd:SetAllPoints(aura.icon)
    else
        aura.icon:ClearAllPoints()
        aura.icon:SetPoint("TOPLEFT", aura, "TOPLEFT", 1, -1)
        aura.icon:SetPoint("BOTTOMRIGHT", aura, "BOTTOMRIGHT", -1, 1)

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
local held = {}          -- every item we have touched, so it can be handed back

local function RebuildItemIndex()
    wipe(itemBySpell)
    ns.CDM:ForEachItemEverywhere(function(item)
        local spellID = ns.CDM:ItemSpellID(item)
        if spellID and not itemBySpell[spellID] then
            itemBySpell[spellID] = item
        end
    end)
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
    bar:SetPoint(cfg.point or "CENTER", UIParent, cfg.relPoint or "CENTER",
        cfg.x or 0, cfg.y or 0)
end

-- Reads the frame's own anchor back into the config. Called after a drag, so
-- what is saved is where it actually ended up rather than where we asked it
-- to go - SetClampedToScreen can differ from both.
function Screen:SavePosition(index)
    local cfg = ns.db.bars[index]
    local bar = barFrames[index]
    if not (cfg and bar) then return end

    local point, _, relPoint, x, y = bar:GetPoint(1)
    if not point then return end

    cfg.point, cfg.relPoint = point, relPoint
    cfg.x, cfg.y = math.floor(x + 0.5), math.floor(y + 0.5)
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

            self:PaintCell(bar, cell, cfg, width, height, claimedNow, auraBySpell)
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

    self:ApplyTakeover(claimedNow)

    if ns.EditMode and ns.EditMode.Refresh then ns.EditMode:Refresh() end
end

-- One cell: adopt, draw, or leave empty.
function Screen:PaintCell(bar, cell, cfg, width, height, claimedNow, auraBySpell)
    local spellID = cfg.cells[cell.index]

    -- Whatever this cell held last time is handed back before anything else,
    -- or moving a spell would leave its old frame pinned to a dead cell.
    if cell.item and (not spellID or ns.CDM:ItemSpellID(cell.item) ~= spellID) then
        ns.CDM:Release(cell.item)
        cell.item = nil
    end

    if not spellID then
        if cell.aura then cell.aura:Hide() end
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

        ns.CDM:Pin(item, { "TOPLEFT", cell, "TOPLEFT", 0, 0 }, width, height)
        ns.CDM:SetAlpha(item, cfg.alpha or 1)
        return
    end

    -- The same spell on two bars. One frame cannot be in two places, so the
    -- first bar keeps it and this cell is drawn dimmer rather than empty -
    -- an empty cell where you know you put something reads as a fault.
    cell.item = nil
    cell.conflict = item and claimedBy[spellID] or nil

    -- An aura proc, or a cooldown whose frame is not pooled right now.
    local aura = BuildAuraVisual(cell)
    aura:Show()
    LayoutAuraVisual(aura, cfg, width, height)

    aura.icon:SetTexture(ns.SpellTexture(spellID))
    aura.label:SetText(ns.SpellName(spellID) or "")

    local border = cfg.borderColor or { 0, 0, 0 }
    aura.border:SetThickness(math.max(0, cfg.borderSize or 1))
    aura.border:SetColor(border[1], border[2], border[3], 1)

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
