---------------------------------------------------------------------------
-- CoTanks - every tank in the group, stacked, with health and auras.
--
-- One row per tank: health bar, name, health percent, then all debuffs on
-- that tank and all of their own buffs.
--
-- The auras are the reason this needs the engine. Auras on OTHER players are
-- secret exactly like your own, so an addon cannot read a co-tank's boss
-- debuff stacks at all. Each row therefore owns two AuraContainers - one
-- HARMFUL, one HELPFUL - and the engine binds, shows and times them.
-- We only supply the widgets and the unit token.
--
-- Buttons are created by us and registered with AddAuraFrame, so they stay
-- ours to move and resize; only engine-created frames get locked.
---------------------------------------------------------------------------
local _, ns = ...

local CoTanks = {}
ns.CoTanks = CoTanks

local MAX_ROWS = 5              -- more tanks than any raid actually runs
local HEALTH_INTERVAL = 0.1

---------------------------------------------------------------------------
-- Roster
---------------------------------------------------------------------------
local function GroupUnits(out)
    wipe(out)
    if IsInRaid() then
        for index = 1, GetNumGroupMembers() do
            out[#out + 1] = "raid" .. index
        end
    elseif IsInGroup() then
        out[#out + 1] = "player"
        for index = 1, GetNumGroupMembers() - 1 do
            out[#out + 1] = "party" .. index
        end
    else
        out[#out + 1] = "player"
    end
    return out
end

local unitScratch = {}

-- Tanks in a stable order, the player first so the row never jumps around.
function CoTanks:CollectTanks(out)
    wipe(out)
    local db = ns.db.coTanks

    for _, unit in ipairs(GroupUnits(unitScratch)) do
        if UnitExists(unit) and UnitGroupRolesAssigned(unit) == "TANK" then
            local isSelf = UnitIsUnit(unit, "player")
            if not isSelf or db.includeSelf then
                if isSelf then
                    table.insert(out, 1, unit)
                else
                    out[#out + 1] = unit
                end
            end
        end
        if #out >= MAX_ROWS then break end
    end

    return out
end

---------------------------------------------------------------------------
-- Row construction
---------------------------------------------------------------------------

-- One engine group per aura strip. The engine creates the icons, lays them
-- out along the strip and shows only the ones that currently hold an aura -
-- which is the whole point, because a co-tank's debuffs are as unreadable to
-- an addon as your own.
--
-- Everything the buttons carry is baked in the initializer: it is the only
-- window in which an engine button may be touched. An uncaught error in there
-- aborts the engine's frame batch and kills the strip, so the optional text
-- registrations are pcall-armoured.
local function BuildStrip(proxy, filter, maxCount, anchorPoint, growthH, border)
    if maxCount < 1 then return nil end

    local size = ns.db.coTanks.iconSize

    local container = ns.Engine:CreateContainer(proxy, {
        anchorPoint = anchorPoint,
        growthH     = growthH,
        growthV     = "DOWN",
    })
    if not container then return nil end

    ns.Engine:AddGroup(container, {
        key    = "dkstank",
        filter = ns.Engine:Filter(filter),
        max    = maxCount,
        layout = {
            elementWidth   = size,
            elementHeight  = size,
            elementSpacing = 1,
            lineSpacing    = 1,
        },
        initialize = function(button)
            ns.Engine:MakeDisplayOnly(button)

            local icon = button:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
            icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            button:SetIcon(icon)

            local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
            cooldown:SetAllPoints(icon)
            cooldown:SetDrawEdge(false)
            cooldown:SetSwipeColor(0, 0, 0, 0.7)
            cooldown:SetHideCountdownNumbers(true)
            cooldown.noCooldownCount = true
            button:SetDurationCooldown(cooldown)

            local edge = ns.CreateBorder(button, 1, "OVERLAY")
            edge:SetColor(border[1], border[2], border[3], 1)

            local textLayer = CreateFrame("Frame", nil, button)
            textLayer:SetAllPoints(button)
            textLayer:SetFrameLevel(button:GetFrameLevel() + 4)

            pcall(function()
                local stacks = textLayer:CreateFontString(nil, "OVERLAY")
                ns.StyleFont(stacks, math.max(8, size * 0.34))
                stacks:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
                -- minCount 2 blanks a single application engine-side, so a
                -- stack count never has to be compared by us.
                button:SetApplicationCount(stacks, { minCount = 2 })
            end)

            pcall(function()
                local duration = textLayer:CreateFontString(nil, "OVERLAY")
                -- Fonted before registration; the engine writes into it at
                -- bind time and an unfonted string hard-errors.
                ns.StyleFont(duration, math.max(9, size * 0.40))
                duration:SetPoint("CENTER", button, "CENTER", 0, 0)
                ns.Engine.BindDurationText(button, duration)
            end)
        end,
    })

    return container
end

local function BuildRow(panel)
    local db = ns.db.coTanks

    local row = CreateFrame("Frame", nil, panel)
    row:Hide()

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetColorTexture(0, 0, 0, 0.85)

    row.health = CreateFrame("StatusBar", nil, row)
    row.health:SetStatusBarTexture(ns.WHITE)
    row.health:SetMinMaxValues(0, 1)
    row.health:SetValue(1)

    row.track = row.health:CreateTexture(nil, "BACKGROUND")
    row.track:SetAllPoints(row.health)
    row.track:SetColorTexture(1, 1, 1, 0.10)

    row.border = ns.CreateBorder(row, 1, "OVERLAY")

    row.textLayer = CreateFrame("Frame", nil, row)
    row.textLayer:SetFrameLevel(row.health:GetFrameLevel() + 2)

    row.name = row.textLayer:CreateFontString(nil, "OVERLAY")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.percent = row.textLayer:CreateFontString(nil, "OVERLAY")
    row.percent:SetJustifyH("RIGHT")

    -- Aura strips. Each gets a plain proxy we own; the container is its child
    -- so all positioning happens on frames the engine does not police.
    row.debuffProxy = CreateFrame("Frame", nil, row)
    row.buffProxy = CreateFrame("Frame", nil, row)


    row.debuffContainer = BuildStrip(row.debuffProxy, "HARMFUL", db.maxDebuffs,
        "TOPLEFT", "RIGHT", { 0.75, 0.15, 0.15 })
    row.buffContainer = BuildStrip(row.buffProxy, "HELPFUL", db.maxBuffs,
        "TOPRIGHT", "LEFT", { 0.25, 0.55, 0.30 })

    return row
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
local function LayoutRow(row, index)
    local db = ns.db.coTanks
    local barHeight = db.rowHeight
    local stripHeight = (row.debuffContainer or row.buffContainer) and db.iconSize or 0
    local rowHeight = barHeight + stripHeight + (stripHeight > 0 and 2 or 0)

    row:SetSize(db.width, rowHeight)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", row:GetParent(), "TOPLEFT", 0,
        -(index - 1) * (rowHeight + db.spacing))

    row.bg:SetAllPoints(row)

    row.health:ClearAllPoints()
    row.health:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    row.health:SetPoint("TOPRIGHT", row, "TOPRIGHT", -1, -1)
    row.health:SetHeight(barHeight - 2)

    row.textLayer:SetAllPoints(row.health)
    ns.StyleFont(row.name, math.max(9, barHeight * 0.52))
    ns.StyleFont(row.percent, math.max(9, barHeight * 0.52))
    row.percent:SetPoint("RIGHT", row.textLayer, "RIGHT", -4, 0)
    row.name:SetPoint("LEFT", row.textLayer, "LEFT", 4, 0)
    row.name:SetPoint("RIGHT", row.percent, "LEFT", -6, 0)

    -- Debuffs grow rightwards from the left edge, buffs leftwards from the
    -- right edge, so the two never collide in the middle.
    row.debuffProxy:ClearAllPoints()
    row.debuffProxy:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -barHeight)
    row.debuffProxy:SetSize(db.width, db.iconSize)

    row.buffProxy:ClearAllPoints()
    row.buffProxy:SetPoint("TOPRIGHT", row, "TOPRIGHT", -1, -barHeight)
    row.buffProxy:SetSize(db.width, db.iconSize)

    -- The icons themselves are the engine's; it lays them out along the strip
    -- from the anchor corner given at construction. All we place is the
    -- container, and only within our own proxy.
    if row.debuffContainer then
        row.debuffContainer:ClearAllPoints()
        row.debuffContainer:SetPoint("TOPLEFT", row.debuffProxy, "TOPLEFT", 0, 0)
    end
    if row.buffContainer then
        row.buffContainer:ClearAllPoints()
        row.buffContainer:SetPoint("TOPRIGHT", row.buffProxy, "TOPRIGHT", 0, 0)
    end

    return rowHeight
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
function CoTanks:Create()
    if self.panel then return end

    local panel = CreateFrame("Frame", "ZwoelfStuffCoTanks", UIParent)
    panel:SetFrameStrata("MEDIUM")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(false)
    panel:RegisterForDrag("LeftButton")
    panel:Hide()

    panel:SetScript("OnDragStart", function(frame)
        if not ns.db.coTanks.locked then frame:StartMoving() end
    end)
    panel:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        CoTanks:SavePosition()
    end)

    local hint = panel:CreateFontString(nil, "OVERLAY")
    hint:SetPoint("BOTTOM", panel, "TOP", 0, 4)
    ns.StyleFont(hint, 11)
    hint:SetText("ZwoelfStuff co-tanks - drag me")
    hint:Hide()
    self.moveHint = hint

    self.panel = panel
    self.rows = {}
    self.tanks = {}
    self.wiredUnits = {}

    for index = 1, MAX_ROWS do
        self.rows[index] = BuildRow(panel)
    end

    self:ApplyLayout()
    self:StartEvents()
end

function CoTanks:ApplyLayout()
    if not self.panel then return end
    local db = ns.db.coTanks

    self.panel:SetScale(db.scale)
    self.panel:ClearAllPoints()
    self.panel:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)

    local total = 0
    for index, row in ipairs(self.rows) do
        local height = LayoutRow(row, index)
        total = total + height + db.spacing
        row.border:SetColor(db.accent[1], db.accent[2], db.accent[3], 0.6)
        row.health:SetStatusBarColor(db.accent[1], db.accent[2], db.accent[3], 1)
    end

    self.panel:SetSize(db.width, math.max(1, total))
    self:Refresh()
end

function CoTanks:SavePosition()
    local point, _, relPoint, x, y = self.panel:GetPoint(1)
    if not point then return end
    local db = ns.db.coTanks
    db.point, db.relPoint = point, relPoint
    db.x, db.y = math.floor(x + 0.5), math.floor(y + 0.5)
end

function CoTanks:SetUnlocked(unlocked)
    if not self.panel then return end
    local db = ns.db.coTanks
    db.locked = not unlocked
    self.panel:EnableMouse(unlocked and true or false)

    if unlocked then
        self.moveHint:Show()
        self.previewing = true
        self:Refresh()
        ns.Print("Co-tank panel unlocked - drag it, then lock it again.")
    else
        self.moveHint:Hide()
        self.previewing = false
        self:SavePosition()
        self:Refresh()
        ns.Print("Co-tank panel locked.")
    end
end

---------------------------------------------------------------------------
-- Binding
---------------------------------------------------------------------------

-- Re-points each row's containers at its tank. Refused in combat, so the
-- request is queued and replayed when combat ends.
function CoTanks:WireRows()
    if ns.Engine:IsLocked() then
        self.wirePending = true
        return
    end
    self.wirePending = false

    for index, row in ipairs(self.rows) do
        local unit = self.tanks[index]
        if unit then
            -- Only the unit is re-pointed; the strip's content was declared
            -- once at construction and is add-only afterwards.
            if self.wiredUnits[index] ~= unit then
                ns.Engine:Bind(row.debuffContainer, unit)
                ns.Engine:Bind(row.buffContainer, unit)
                self.wiredUnits[index] = unit
            end
        elseif self.wiredUnits[index] then
            ns.Engine:Retire(row.debuffContainer)
            ns.Engine:Retire(row.buffContainer)
            self.wiredUnits[index] = nil
        end
    end
end

---------------------------------------------------------------------------
-- Health
---------------------------------------------------------------------------
local function UpdateHealth(row, unit)
    local current, maximum = UnitHealth(unit), UnitHealthMax(unit)

    -- StatusBar accepts secret numbers, so the bar renders either way; only
    -- the percentage text needs values we may compute on.
    if ns.CanCompute(maximum) and maximum > 0 then
        row.health:SetMinMaxValues(0, maximum)
    end
    row.health:SetValue(current)

    if ns.CanCompute(current) and ns.CanCompute(maximum) and maximum > 0 then
        row.percent:SetText(string.format("%d%%", math.floor(current / maximum * 100 + 0.5)))
    else
        row.percent:SetText("")
    end

    if UnitIsDeadOrGhost(unit) then
        row.health:SetStatusBarColor(0.45, 0.45, 0.45, 1)
    elseif not UnitIsConnected(unit) then
        row.health:SetStatusBarColor(0.35, 0.35, 0.45, 1)
    else
        local accent = ns.db.coTanks.accent
        row.health:SetStatusBarColor(accent[1], accent[2], accent[3], 1)
    end
end

local function UpdateName(row, unit)
    local name = UnitName(unit) or "?"
    local _, classFile = UnitClass(unit)
    local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if color then
        row.name:SetTextColor(color.r, color.g, color.b)
    else
        row.name:SetTextColor(1, 1, 1)
    end
    row.name:SetText(name)
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
function CoTanks:ShouldShow()
    local db = ns.db.coTanks
    if not db.enabled then return false end
    if self.previewing then return true end
    if db.onlyInGroup and not IsInGroup() then return false end
    return #self.tanks > 0
end

function CoTanks:Refresh()
    if not self.panel then return end

    self:CollectTanks(self.tanks)

    if not self:ShouldShow() then
        self.panel:Hide()
        for _, row in ipairs(self.rows) do row:Hide() end
        return
    end

    local shown = 0
    for index, row in ipairs(self.rows) do
        local unit = self.tanks[index]
        if unit then
            UpdateName(row, unit)
            UpdateHealth(row, unit)
            row:Show()
            shown = shown + 1
        elseif self.previewing and index == 1 and #self.tanks == 0 then
            -- Something to drag when solo.
            row.name:SetText("(no tanks)")
            row.name:SetTextColor(0.7, 0.7, 0.7)
            row.percent:SetText("--%")
            row.health:SetMinMaxValues(0, 1)
            row.health:SetValue(1)
            row:Show()
            shown = 1
        else
            row:Hide()
        end
    end

    local db = ns.db.coTanks
    local rowHeight = db.rowHeight + db.iconSize + 2
    self.panel:SetHeight(math.max(1, shown * (rowHeight + db.spacing)))
    self.panel:Show()

    self:WireRows()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
function CoTanks:StartEvents()
    if self.events then return end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")

    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" and CoTanks.wirePending then
            CoTanks:WireRows()
        end
        CoTanks:Refresh()
    end)

    -- Health is polled rather than event-driven: at most a handful of rows,
    -- and it sidesteps re-registering unit events on every roster change.
    frame:SetScript("OnUpdate", function(_, elapsed)
        CoTanks.accum = (CoTanks.accum or 0) + elapsed
        if CoTanks.accum < HEALTH_INTERVAL then return end
        CoTanks.accum = 0
        if not (CoTanks.panel and CoTanks.panel:IsShown()) then return end
        for index, row in ipairs(CoTanks.rows) do
            local unit = CoTanks.tanks[index]
            if unit and row:IsShown() then
                UpdateHealth(row, unit)
            end
        end
    end)

    self.events = frame
end
