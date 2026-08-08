---------------------------------------------------------------------------
-- CoTanks - a unit frame per tank in the group.
--
-- The only display in this addon that is about somebody else. As a Blood DK
-- what you need from the other tank is four things, fast: are they alive, are
-- they low, are they in range, and are their cooldowns up. Blizzard's raid
-- frames answer none of that at a glance, because the other tank is one box
-- among twenty and looks like the rest of them.
--
-- ONE RENDERER, TWO SOURCES.
--
-- Nothing below ever asks a unit token a question. Every row is painted from
-- a SNAPSHOT - a plain table of numbers and strings - and the only difference
-- between the live display and test mode is which function filled that table
-- in. That is the whole reason test mode is trustworthy: it is not a second
-- drawing of the same idea, it is the same drawing with invented input.
--
-- Two earlier features in this addon were built the other way round, with a
-- preview that drew itself, and both of them drifted from the thing they were
-- previewing within a session.
--
-- AURAS NEED PATCH 12.1, AND THIS FILE SAYS SO RATHER THAN PRETENDING.
--
-- On this client an aura on ANOTHER player is a secret value: an addon may
-- not read its icon, its stacks, its duration, or even tell two of them
-- apart. There is no clever way round it - the sanctioned route is Blizzard's
-- AuraContainer, which arrives with 12.1 and which ns.Engine already wraps.
-- So the strips bind to the engine when the engine exists, and until then
-- they draw in TEST MODE only. Every aura setting is therefore adjustable
-- today and correct the moment the patch lands, and the panel prints the
-- reason instead of showing an empty strip and letting the user wonder.
---------------------------------------------------------------------------
local _, ns = ...

local CoTanks = {}
ns.CoTanks = CoTanks

local HEALTH_INTERVAL = 0.1     -- polled, see StartEvents
local MAX_ROWS = 8              -- the ceiling the slider stops at

---------------------------------------------------------------------------
-- Who counts as a tank
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

-- UnitGroupRolesAssigned is the role the GROUP has agreed on, which is what
-- "the other tank" means - not the spec, because a Blood DK in a dungeon
-- queued as dps is not co-tanking with you.
function CoTanks:CollectTanks(out)
    wipe(out)
    local db = ns.db.coTanks
    local limit = math.max(1, math.min(MAX_ROWS, db.maxRows or 5))

    for _, unit in ipairs(GroupUnits(unitScratch)) do
        if UnitExists(unit) and UnitGroupRolesAssigned(unit) == "TANK" then
            local isSelf = UnitIsUnit(unit, "player")
            if not isSelf or db.includeSelf then
                out[#out + 1] = unit
            end
        end
        if #out >= limit then break end
    end

    if db.sortBy == "name" then
        table.sort(out, function(a, b)
            return (UnitName(a) or "") < (UnitName(b) or "")
        end)
    elseif db.sortBy == "health" then
        -- READ EVERY VALUE FIRST, AND ONLY THEN DECIDE WHETHER TO SORT.
        --
        -- The obvious shape - compare inside the comparator and return false
        -- when a value is unreadable - is INTRANSITIVE, and table.sort detects
        -- that and raises "invalid order function for sorting". So the answer
        -- is not a careful comparator, it is not calling sort at all: if any
        -- health in the group is protected the roster order stands, which is
        -- the order it was in a moment ago and therefore the order that does
        -- not shuffle under the eye.
        local key, sortable = {}, true
        for _, unit in ipairs(out) do
            local health = UnitHealth(unit)
            if ns.CanCompute(health) then
                key[unit] = health
            else
                sortable = false
                break
            end
        end
        if sortable then
            table.sort(out, function(a, b) return key[a] < key[b] end)
        end
    end

    return out
end

---------------------------------------------------------------------------
-- Snapshots
--
-- What one row needs to draw itself, and nothing else. Filled in place so a
-- refresh at 10 Hz allocates nothing.
---------------------------------------------------------------------------
local function BlankSnapshot(snap)
    snap.name, snap.classFile = nil, nil
    snap.health, snap.healthMax = nil, nil
    snap.absorb, snap.healAbsorb = nil, nil
    snap.dead, snap.offline, snap.inRange = false, false, true
    snap.leader, snap.marker, snap.role = false, nil, nil
    snap.targeted = false
    return snap
end

local function LiveSnapshot(unit, snap)
    BlankSnapshot(snap)

    snap.name = UnitName(unit) or "?"
    snap.classFile = select(2, UnitClass(unit))
    snap.health = UnitHealth(unit)
    snap.healthMax = UnitHealthMax(unit)
    snap.absorb = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or nil
    snap.healAbsorb = UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unit) or nil
    snap.dead = UnitIsDeadOrGhost(unit) and true or false
    snap.offline = not UnitIsConnected(unit)
    -- UnitInRange answers false for the player's own unit on some paths, so
    -- "is it me" wins: you are never out of range of yourself.
    if UnitIsUnit(unit, "player") then
        snap.inRange = true
    else
        snap.inRange = UnitInRange(unit) and true or false
    end
    snap.leader = UnitIsGroupLeader(unit) and true or false
    snap.marker = GetRaidTargetIndex and GetRaidTargetIndex(unit) or nil
    snap.role = UnitGroupRolesAssigned(unit)
    snap.targeted = UnitIsUnit(unit, "target") and true or false

    return snap
end

-- Five invented tanks, so the panel can be laid out and judged without a
-- raid. The names are obviously not real players and the classes cover five
-- different class colours, because the one thing a fake roster has to prove
-- is that the colouring works.
local TEST_TANKS = {
    { name = "Zwoelf",     class = "DEATHKNIGHT", leader = true,  marker = 1 },
    { name = "Brakh",      class = "WARRIOR" },
    { name = "Sunwarden",  class = "PALADIN",     marker = 8 },
    { name = "Ironhide",   class = "DRUID",       offline = true },
    { name = "Stonefist",  class = "MONK",        dead = true },
    { name = "Ashvale",    class = "DEMONHUNTER" },
    { name = "Thornwake",  class = "WARRIOR" },
    { name = "Duskbarrow", class = "PALADIN" },
}

-- THE FAKE HEALTH MOVES, and that is the point rather than decoration: a
-- still bar tells you nothing about the texture, the fill direction, the
-- absorb overlay or the colour ramp, all of which are settings on this page.
-- Each row drifts on its own period so the five never move together.
local function TestSnapshot(index, snap)
    BlankSnapshot(snap)

    local fake = TEST_TANKS[((index - 1) % #TEST_TANKS) + 1]
    snap.name = fake.name
    snap.classFile = fake.class
    snap.leader = fake.leader or false
    snap.marker = fake.marker
    snap.role = "TANK"
    snap.dead = fake.dead or false
    snap.offline = fake.offline or false
    snap.targeted = index == 1
    snap.inRange = index ~= 4

    snap.healthMax = 1000000
    if snap.dead then
        snap.health = 0
    else
        local phase = GetTime() * (0.35 + index * 0.07) + index
        -- 0.12 to 0.98, so the ramp is seen at both ends over one cycle.
        local fraction = 0.55 + math.sin(phase) * 0.43
        snap.health = math.floor(snap.healthMax * fraction)
        snap.absorb = math.floor(snap.healthMax * 0.12 * (0.5 + 0.5 * math.sin(phase * 1.7)))
        snap.healAbsorb = index == 2
            and math.floor(snap.healthMax * 0.10) or 0
    end

    return snap
end

---------------------------------------------------------------------------
-- Sample icons for the test strips
--
-- NEVER A HARDCODED SPELL ID. Two wrong ones have already cost this project a
-- day, and the rule written in KnownProcs.lua applies just as much to a
-- decoration as to a tracked aura. So the sample icons come from spells this
-- installation already resolved: whatever the user put on their own bars,
-- then whatever the Cooldown Manager is offering. If neither answers, the
-- strip draws flat squares - which still shows the size, the spacing, the
-- growth and the border, because those are what this strip is for.
---------------------------------------------------------------------------
local sampleIcons, sampleStamp = {}, 0

local function SampleIcons()
    -- Rebuilt at most every ten seconds: the spell list changes when the user
    -- edits a bar, and rebuilding it per frame would ask the client for a
    -- texture forty times a second for a decoration.
    local now = GetTime()
    if sampleStamp > 0 and now - sampleStamp < 10 then return sampleIcons end
    sampleStamp = now
    wipe(sampleIcons)

    local seen = {}
    local function Take(spellID)
        if not spellID or seen[spellID] or #sampleIcons >= 16 then return end
        local texture = ns.SpellTexture(spellID)
        if not texture then return end
        seen[spellID] = true
        sampleIcons[#sampleIcons + 1] = texture
    end

    for index = 1, ns.Bars:Count() do
        local cfg = ns.Bars:Get(index)
        for _, spellID in pairs(cfg and cfg.cells or {}) do Take(spellID) end
    end

    -- CDM:Catalogue(), not ForEachCatalogued. The low-level walk hands over
    -- (cooldownID, viewerKey, order) - three numbers - and this asked it for
    -- `entry.spellID`, which raises on the first one. The pcall around it
    -- swallowed that, so the documented fallback silently contributed nothing:
    -- the exact shape of bug this addon keeps finding, one that succeeds at
    -- doing nothing. Catalogue is the assembled list and already carries the
    -- resolved icon.
    if #sampleIcons < 6 and ns.CDM and ns.CDM.Catalogue then
        local ok, list = pcall(ns.CDM.Catalogue, ns.CDM)
        if ok and type(list) == "table" then
            for _, entry in ipairs(list) do Take(entry and entry.spellID) end
        end
    end

    return sampleIcons
end

---------------------------------------------------------------------------
-- Building one row
---------------------------------------------------------------------------
local function BuildStrip(row, key)
    local strip = CreateFrame("Frame", nil, row)
    strip.buttons = {}
    strip.key = key
    return strip
end

local function BuildRow(panel)
    local row = CreateFrame("Frame", nil, panel)
    row:Hide()

    row.bg = row:CreateTexture(nil, "BACKGROUND")

    row.health = CreateFrame("StatusBar", nil, row)
    row.health:SetMinMaxValues(0, 1)
    row.health:SetValue(1)

    -- The empty part of the bar, in the bar's own colour at a low alpha. A
    -- bar on a black plate reads as "how much is left"; a bar on a ghost of
    -- itself reads as "how much of what there was", which is the question.
    row.track = row.health:CreateTexture(nil, "BACKGROUND")
    row.track:SetAllPoints(row.health)

    -- Absorbs sit OVER the health rather than beside it. A shield is health
    -- you have; a separate strip somewhere else is a second thing to find
    -- during the two seconds you have to look at all.
    row.absorb = row.health:CreateTexture(nil, "ARTWORK")
    row.absorb:SetDrawLayer("ARTWORK", 1)
    row.healAbsorb = row.health:CreateTexture(nil, "ARTWORK")
    row.healAbsorb:SetDrawLayer("ARTWORK", 2)

    row.chrome = ns.CreateChrome(row)

    -- Your target, as a ring rather than a colour change: the health colour
    -- is already carrying class or health, and a third meaning on the same
    -- pixel is a meaning nobody reads.
    row.targetRing = ns.CreateBorder(row, 2, "OVERLAY")
    row.targetRing:Hide()

    row.textLayer = CreateFrame("Frame", nil, row)
    row.textLayer:SetFrameLevel(row.health:GetFrameLevel() + 3)

    row.name = row.textLayer:CreateFontString(nil, "OVERLAY")
    row.name:SetWordWrap(false)
    row.healthText = row.textLayer:CreateFontString(nil, "OVERLAY")
    row.healthText:SetWordWrap(false)

    row.marker = row.textLayer:CreateTexture(nil, "OVERLAY")
    row.marker:SetTexture([[Interface\TargetingFrame\UI-RaidTargetingIcons]])
    row.marker:Hide()

    row.leader = row.textLayer:CreateTexture(nil, "OVERLAY")
    row.leader:SetTexture([[Interface\GroupFrame\UI-Group-LeaderIcon]])
    row.leader:Hide()

    row.roleIcon = row.textLayer:CreateTexture(nil, "OVERLAY")
    row.roleIcon:SetTexture([[Interface\LFGFrame\UI-LFG-ICON-PORTRAITROLES]])
    -- The tank quarter of Blizzard's four-role sheet.
    row.roleIcon:SetTexCoord(0, 0.25, 0.25, 0.5)
    row.roleIcon:Hide()

    row.debuffs = BuildStrip(row, "debuffs")
    row.buffs = BuildStrip(row, "buffs")

    return row
end

---------------------------------------------------------------------------
-- Styling one row
---------------------------------------------------------------------------

-- HOW MUCH ROOM ONE ROW TAKES, strips included, and how much of that hangs
-- above the health bar and below it.
--
-- Its own function because three separate things need exactly this answer -
-- where the next row starts, how tall the panel is, and how far the preview
-- has to be scaled down - and three places working it out for themselves is
-- three chances to disagree. The rows overlapping their neighbours' aura
-- strips is precisely what that disagreement looks like.
function CoTanks:RowExtent(db)
    db = db or ns.db.coTanks
    local above, below = 0, 0

    for _, key in ipairs({ "debuffs", "buffs" }) do
        local cfg = db[key]
        local count = cfg.show and math.max(0, math.min(40, cfg.max or 0)) or 0
        if count > 0 then
            local _, height = ns.Layout.StripSize(count, math.max(6, cfg.size or 20),
                cfg.spacing or 0, cfg.perRow or 1)
            -- The nudge counts: a strip pushed six pixels further out needs
            -- those six pixels, or the next row sits on them.
            height = height + math.abs(cfg.y or 0)
            if (cfg.anchor or ""):find("TOP") then
                above = math.max(above, height)
            else
                below = math.max(below, height)
            end
        end
    end

    return db.rowHeight + above + below, above, below
end


-- The style table the shared painters expect. Built from the co-tank
-- settings so ns.PaintSurface, ns.PaintBorder and ns.Tint can be reused
-- exactly as the bars use them - including the gradients, which is why a
-- co-tank frame gets them without a line of new drawing code.
local function ChromeStyle(db)
    return {
        backdrop = true,
        backdropColor = db.bgColor,
        backdropAlpha = db.bgAlpha,
        backdropTexture = nil,
        backdropGradient = db.bgGradient,
        borderSize = db.borderSize,
        borderColor = db.borderColor,
        borderTexture = db.borderTexture,
        borderGradient = db.borderGradient,
    }
end

local function TextSize(element, rowHeight, fallbackScale)
    local size = element and element.size or 0
    if size and size > 0 then return size end
    return math.max(8, math.min(20, rowHeight * fallbackScale))
end

local function StyleStrip(row, strip, cfg)
    local size = math.max(6, cfg.size or 20)
    local wanted = cfg.show and math.max(0, math.min(40, cfg.max or 0)) or 0

    -- The strip's own corner is the row's, flipped: it hangs OFF the row
    -- rather than sitting in it. See ns.Layout.StripCorner.
    local corner = ns.Layout.StripCorner(cfg.anchor)

    strip:ClearAllPoints()
    strip:SetPoint(corner, row, cfg.anchor, cfg.x or 0, cfg.y or 0)
    local width, height = ns.Layout.StripSize(math.max(1, wanted), size,
        cfg.spacing or 0, cfg.perRow or 1)
    strip:SetSize(math.max(1, width), math.max(1, height))
    strip:SetShown(wanted > 0)

    strip.iconSize = size
    strip.wanted = wanted

    for index = 1, wanted do
        local button = strip.buttons[index]
        if not button then
            button = CreateFrame("Frame", nil, strip)
            button.icon = button:CreateTexture(nil, "ARTWORK")
            button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            button.edge = ns.CreateBorder(button, 1, "OVERLAY")
            button.text = button:CreateFontString(nil, "OVERLAY")
            button.count = button:CreateFontString(nil, "OVERLAY")
            strip.buttons[index] = button
        end

        button:SetSize(size, size)
        button:ClearAllPoints()
        local dx, dy = ns.Layout.StripSlot(index, size, cfg.spacing or 0,
            cfg.perRow or 1, cfg.growth, corner)
        button:SetPoint(corner, strip, corner, dx, dy)

        button.icon:SetAllPoints(button)
        button.edge:SetThickness(math.max(0, cfg.borderSize or 0))
        button.edge:SetColor(cfg.borderColor[1], cfg.borderColor[2],
            cfg.borderColor[3], 1)
        button.edge:SetShown((cfg.borderSize or 0) > 0)

        -- FONT BEFORE TEXT, every time. A font string with no font raises on
        -- the next SetText rather than doing nothing, and that has already
        -- taken a whole feature down in this addon once.
        local textSize = cfg.countdownSize
        if not textSize or textSize <= 0 then textSize = math.max(8, size * 0.42) end
        ns.Media.ApplyFont(button.text, "", textSize, "OUTLINE", { 1, 1, 1 })
        button.text:ClearAllPoints()
        button.text:SetPoint("CENTER", button, "CENTER", 0, 0)
        button.text:SetShown(cfg.countdown and true or false)

        local countSize = cfg.stacksSize
        if not countSize or countSize <= 0 then countSize = math.max(8, size * 0.36) end
        ns.Media.ApplyFont(button.count, "", countSize, "OUTLINE", { 1, 1, 1 })
        button.count:ClearAllPoints()
        button.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        button.count:SetShown(cfg.stacks and true or false)

        button:Show()
    end

    for index = wanted + 1, #strip.buttons do
        strip.buttons[index]:Hide()
    end
end

local function StyleRow(row, index, db)
    local height = math.max(10, db.rowHeight)
    local width = math.max(60, db.width)

    row:SetSize(width, height)
    row:ClearAllPoints()

    -- The row frame is the HEALTH BAR. What the stack steps by is the whole
    -- BLOCK - the bar plus whatever its aura strips hang above and below it -
    -- and the bar sits inside that block past the part that hangs above.
    -- Stepping by the bar alone put every row's strips across the next row.
    local extent, above, below = CoTanks:RowExtent(db)
    local step = (index - 1) * (extent + db.spacing)

    -- Which way the stack grows is which corner every row hangs from. Anchored
    -- from the top and told to grow up, a row would move when the one above it
    -- resized; from the bottom it does not.
    if db.growth == "up" then
        row:SetPoint("BOTTOMLEFT", row:GetParent(), "BOTTOMLEFT", 0, step + below)
    else
        row:SetPoint("TOPLEFT", row:GetParent(), "TOPLEFT", 0, -(step + above))
    end

    row.bg:SetAllPoints(row)
    local style = ChromeStyle(db)
    ns.PaintSurface(row.bg, style)
    ns.PaintBorder(row.chrome, style, false)

    local inset = math.max(0, db.borderSize)
    row.health:ClearAllPoints()
    row.health:SetPoint("TOPLEFT", row, "TOPLEFT", inset, -inset)
    row.health:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -inset, inset)

    local texture = ns.WHITE
    if db.healthTexture ~= "" and ns.Media.IsKnown("statusbar", db.healthTexture) then
        texture = ns.Media.Statusbar(db.healthTexture)
    end
    row.health:SetStatusBarTexture(texture)
    row.health:SetOrientation(db.healthVertical and "VERTICAL" or "HORIZONTAL")
    row.health:SetReverseFill(db.healthReverse and true or false)
    row.track:SetTexture(texture)

    row.absorb:SetTexture(texture)
    row.healAbsorb:SetTexture(texture)
    ns.Tint(row.absorb, db.absorbColor, db.absorbAlpha)
    ns.Tint(row.healAbsorb, db.healAbsorbColor, db.healAbsorbAlpha)
    row.absorb:SetShown(false)
    row.healAbsorb:SetShown(false)

    row.targetRing:SetThickness(2)
    row.targetRing:SetColor(db.targetColor[1], db.targetColor[2],
        db.targetColor[3], 1)

    row.textLayer:SetAllPoints(row.health)

    -- The two texts hang off BOTH edges of the row, never off a measured
    -- width. A width is a number taken once, so a right-aligned name sat at
    -- the old right edge the moment the panel got wider - the same fault that
    -- was found and fixed on the bars, and it would have arrived here for
    -- free by copying the wrong half.
    local nameSize = TextSize(db.name, height, 0.52)
    ns.Media.ApplyFont(row.name, db.name.font, nameSize, db.name.outline,
        db.name.color)
    ns.PlaceLabel(row.name, row.textLayer, db.name, 4, 4)
    row.name:SetShown(db.name.show ~= false)

    local healthSize = TextSize(db.health, height, 0.52)
    ns.Media.ApplyFont(row.healthText, db.health.font, healthSize,
        db.health.outline, db.health.color)
    ns.PlaceLabel(row.healthText, row.textLayer, db.health, 4, 4)
    row.healthText:SetShown(db.health.show ~= false)

    row.marker:SetSize(db.raidMarkerSize, db.raidMarkerSize)
    row.marker:ClearAllPoints()
    row.marker:SetPoint("LEFT", row.textLayer, "LEFT", 2, 0)

    row.leader:SetSize(db.leaderIconSize, db.leaderIconSize)
    row.leader:ClearAllPoints()
    row.leader:SetPoint("TOPLEFT", row, "TOPLEFT", -2, 4)

    row.roleIcon:SetSize(db.roleIconSize, db.roleIconSize)
    row.roleIcon:ClearAllPoints()
    row.roleIcon:SetPoint("RIGHT", row.textLayer, "RIGHT", -2, 0)
    row.roleIcon:SetShown(db.roleIcon and true or false)

    StyleStrip(row, row.debuffs, db.debuffs)
    StyleStrip(row, row.buffs, db.buffs)
end

---------------------------------------------------------------------------
-- Painting one row from a snapshot
---------------------------------------------------------------------------
-- An overlay against one edge of the fill's texture.
--
-- inward puts it INSIDE the fill (healing taken away, which is health you
-- have and cannot get back); outward puts it past the end (a shield, which is
-- health you do not have yet). Both hang off the texture rather than off the
-- bar frame, so they travel with the clock instead of being repositioned
-- every tick - the same decision the spark makes, for the same reason.
local function PlaceOverlay(texture, fill, edge, vertical, span, inward)
    -- The far side of the strip: where it ends, given where it starts.
    local far
    if vertical then
        far = edge == "TOP" and "BOTTOM" or "TOP"
    else
        far = edge == "RIGHT" and "LEFT" or "RIGHT"
    end
    local head = inward and edge or far

    texture:ClearAllPoints()
    if vertical then
        texture:SetPoint(head .. "LEFT", fill, edge .. "LEFT", 0, 0)
        texture:SetPoint(head .. "RIGHT", fill, edge .. "RIGHT", 0, 0)
        texture:SetHeight(math.max(1, span))
    else
        texture:SetPoint("TOP" .. head, fill, "TOP" .. edge, 0, 0)
        texture:SetPoint("BOTTOM" .. head, fill, "BOTTOM" .. edge, 0, 0)
        texture:SetWidth(math.max(1, span))
    end
end

local CLASS_FALLBACK = { r = 0.7, g = 0.7, b = 0.7 }

local function ClassColour(classFile)
    local colours = RAID_CLASS_COLORS or CUSTOM_CLASS_COLORS
    return (classFile and colours and colours[classFile]) or CLASS_FALLBACK
end

-- The bar colour, which is three settings arguing with each other and worth
-- keeping in one place: the mode picks it, death and disconnection override
-- it, and "by health" quietly falls back to the class colour when the numbers
-- are unreadable - which they are, in combat, on this patch, for anyone but
-- yourself.
local function BarColour(db, snap)
    if snap.dead then return 0.35, 0.35, 0.35 end
    if snap.offline then return 0.30, 0.30, 0.38 end

    if db.healthColor == "custom" then
        return db.healthCustom[1], db.healthCustom[2], db.healthCustom[3]
    end

    if db.healthColor == "health"
        and ns.CanCompute(snap.health) and ns.CanCompute(snap.healthMax)
        and snap.healthMax > 0 then
        return ns.Layout.HealthTint(snap.health / snap.healthMax,
            db.healthHigh, db.healthMid, db.healthLow)
    end

    local colour = ClassColour(snap.classFile)
    return colour.r, colour.g, colour.b
end

-- What the health text says. nil means "cannot be known right now", and the
-- caller blanks the string rather than printing a zero - a bar that reads 0%
-- because the number is protected is worse than a bar that reads nothing.
function CoTanks:HealthText(format, health, maximum)
    if not (ns.CanCompute(health) and ns.CanCompute(maximum)) then return nil end
    if maximum <= 0 then return nil end

    local percent = math.floor(health / maximum * 100 + 0.5)
    if format == "current" then
        return AbbreviateNumbers and AbbreviateNumbers(health) or tostring(health)
    elseif format == "deficit" then
        local missing = maximum - health
        if missing <= 0 then return "" end
        return "-" .. (AbbreviateNumbers and AbbreviateNumbers(missing)
            or tostring(missing))
    elseif format == "both" then
        local shown = AbbreviateNumbers and AbbreviateNumbers(health)
            or tostring(health)
        return string.format("%s  %d%%", shown, percent)
    end
    return string.format("%d%%", percent)
end

-- Cut a name to N characters. Zero keeps the whole of it.
--
-- Its own function because the obvious string.sub is wrong on a realm where
-- names are not ASCII: it would cut a multi-byte character in half and the
-- client draws the remains as a box. strsub with a UTF-8 offset is what
-- Blizzard's own frames use for exactly this.
function CoTanks:CutName(name, limit)
    if not name or not limit or limit <= 0 then return name end
    if strlenutf8 and strlenutf8(name) <= limit then return name end

    -- WALKED BY CHARACTER, NOT BY BYTE. The first version stepped one byte per
    -- pass while counting to a limit in characters, so a name with any
    -- non-ASCII letter came back too short and could end halfway through a
    -- sequence - which the client draws as a box. That is precisely what this
    -- function exists to prevent, so it was worth writing out.
    --
    -- A leading byte is < 0x80 (one byte), or >= 0xC0 and says how many
    -- follow. Bytes in 0x80-0xBF are continuations and are never counted.
    local index, length, count = 1, #name, 0
    while index <= length and count < limit do
        local byte = name:byte(index)
        local size = 1
        if byte >= 240 then size = 4
        elseif byte >= 224 then size = 3
        elseif byte >= 192 then size = 2 end
        index = index + size
        count = count + 1
    end
    return name:sub(1, index - 1)
end

local function PaintStrip(strip, cfg, testing)
    if not (strip and strip.wanted and strip.wanted > 0) then return end

    -- LIVE AURAS ARE THE ENGINE'S, and the engine does not exist yet on this
    -- client. Nothing is drawn rather than something wrong: an icon we
    -- invented on a live frame would be a lie about another player's buffs.
    if not testing then
        for _, button in ipairs(strip.buttons) do button:Hide() end
        return
    end

    local icons = SampleIcons()
    local now = GetTime()

    for index = 1, strip.wanted do
        local button = strip.buttons[index]
        if not button then break end

        local texture = icons[((index - 1) % math.max(1, #icons)) + 1]
        if texture then
            button.icon:SetTexture(texture)
            button.icon:SetVertexColor(1, 1, 1, 1)
        else
            -- No spell on this installation resolved to a texture. A flat
            -- square still shows the size, the spacing, the growth and the
            -- border, which is what this strip is being adjusted for.
            button.icon:SetColorTexture(0.30, 0.32, 0.38, 1)
        end

        if cfg.countdown then
            -- A countdown that never changes tells you nothing about whether
            -- the number fits in the icon, which is the whole question.
            local remaining = (now * (1 + index * 0.1)) % 30
            button.text:SetText(ns.FormatTime(remaining))
        end
        if cfg.stacks then
            button.count:SetText(tostring((index % 4) + 2))
        end
        button:Show()
    end
end

local function PaintRow(row, snap, db, testing)
    local r, g, b = BarColour(db, snap)
    row.health:SetStatusBarColor(1, 1, 1, 1)
    ns.Tint(row.health:GetStatusBarTexture(), { r, g, b }, db.healthAlpha,
        db.healthGradient)
    row.track:SetVertexColor(r, g, b, db.trackAlpha)

    -- THE BAR TAKES THE NUMBER WITHOUT READING IT. SetMinMaxValues and
    -- SetValue both accept secret values, so the bar is correct on a client
    -- and in a fight where no addon may compute the percentage. That is why
    -- the bar always works and the TEXT is the part that sometimes cannot.
    if ns.CanCompute(snap.healthMax) and snap.healthMax > 0 then
        row.health:SetMinMaxValues(0, snap.healthMax)
    end
    row.health:SetValue(snap.health)

    -- Both overlays hang off the fill's LEADING EDGE, the one that moves with
    -- the clock - the shield outward from it, the un-healable part inward.
    -- Which edge that is depends on the direction the bar runs, and a
    -- hard-coded RIGHT put the shield at the wrong end of a right-to-left bar
    -- and across the middle of a vertical one.
    local texture = row.health:GetStatusBarTexture()
    local readable = ns.CanCompute(snap.health) and ns.CanCompute(snap.healthMax)
        and snap.healthMax > 0
    local edge, vertical = ns.Layout.FillEdge(row.health:GetOrientation(),
        row.health:GetReverseFill())
    local full = vertical and row.health:GetHeight() or row.health:GetWidth()

    local showAbsorb = db.absorbShow and readable and ns.CanCompute(snap.absorb)
        and (snap.absorb or 0) > 0
    row.absorb:SetShown(showAbsorb and true or false)
    if showAbsorb and texture then
        PlaceOverlay(row.absorb, texture, edge, vertical,
            math.min(full, full * (snap.absorb / snap.healthMax)), false)
    end

    -- Healing taken away is health you HAVE and cannot get back, so it is
    -- drawn inside the fill rather than past its end.
    local showHealAbsorb = db.healAbsorbShow and readable
        and ns.CanCompute(snap.healAbsorb) and (snap.healAbsorb or 0) > 0
    row.healAbsorb:SetShown(showHealAbsorb and true or false)
    if showHealAbsorb and texture then
        PlaceOverlay(row.healAbsorb, texture, edge, vertical,
            math.min(full, full * (snap.healAbsorb / snap.healthMax)), true)
    end

    if db.name.show ~= false then
        local shown = CoTanks:CutName(snap.name, db.name.maxLength)
        row.name:SetText(shown or "")
        if db.name.classColor then
            local colour = ClassColour(snap.classFile)
            row.name:SetTextColor(colour.r, colour.g, colour.b)
        else
            row.name:SetTextColor(db.name.color[1], db.name.color[2],
                db.name.color[3])
        end
    end

    if db.health.show ~= false then
        local text
        if snap.dead then
            text = DEAD or "Dead"
        elseif snap.offline then
            -- A literal, not a global. DEAD is real (23 installed addons use
            -- it); the offline one was written from memory and NOTHING on
            -- this machine references it - which is exactly how a nil ends up
            -- concatenated into a font string at the worst moment.
            text = "Offline"
        else
            text = CoTanks:HealthText(db.health.format, snap.health, snap.healthMax)
        end
        row.healthText:SetText(text or "")
    end

    row.marker:SetShown(db.raidMarker and snap.marker ~= nil)
    if db.raidMarker and snap.marker then
        SetRaidTargetIconTexture(row.marker, snap.marker)
    end
    row.leader:SetShown(db.leaderIcon and snap.leader and true or false)

    row.targetRing:SetShown(db.targetHighlight and snap.targeted and true or false)

    -- One alpha for the whole row, decided by the worst thing true about it.
    -- Three separate fades multiplied together made a dead, disconnected tank
    -- out of range invisible, which is precisely when you want to see that
    -- there is one.
    local alpha = 1
    if snap.dead then
        alpha = db.deadFade
    elseif snap.offline then
        alpha = db.offlineFade
    elseif db.rangeFade and not snap.inRange then
        alpha = db.rangeAlpha
    end
    row:SetAlpha(alpha)

    PaintStrip(row.debuffs, db.debuffs, testing)
    PaintStrip(row.buffs, db.buffs, testing)
end

---------------------------------------------------------------------------
-- The panel
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
    -- Fonted BEFORE the text, or SetText raises on a string with no font.
    ns.StyleUIFont(hint, 11)
    hint:SetText("ZwoelfStuff co-tanks - drag me")
    hint:Hide()
    self.moveHint = hint

    self.panel = panel
    self.rows = {}
    self.tanks = {}
    self.snapshots = {}

    for index = 1, MAX_ROWS do
        self.rows[index] = BuildRow(panel)
        self.snapshots[index] = BlankSnapshot({})
    end

    self:ApplyLayout()
    self:StartEvents()
end

function CoTanks:ApplyLayout()
    if not self.panel then return end
    local db = ns.db.coTanks

    -- NOT WHILE IT IS BORROWED. The options page reparents this panel into
    -- its preview card, and ApplyLayout runs on every single control there -
    -- so without this the preview jumps back to its place on the screen the
    -- moment you touch a slider, and does it again on the next one.
    if not self.hosted then
        self.panel:SetScale(db.scale)
        self.panel:ClearAllPoints()
        self.panel:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
    end

    for index, row in ipairs(self.rows) do
        StyleRow(row, index, db)
    end

    -- Groups are add-only, so a settings change means NEW containers rather
    -- than mutated ones. Here and not in Refresh: Refresh runs ten times a
    -- second and rebuilding an engine container at that rate would be a frame
    -- spike per tick.
    self:BuildAuraContainers()
    self:Refresh()
end

function CoTanks:SavePosition()
    if not self.panel then return end
    -- NOT WHILE IT IS SITTING IN THE OPTIONS CARD. Its point is then relative
    -- to that card, and writing those numbers into the profile would move the
    -- real panel somewhere arbitrary the next time it goes home.
    if self.hosted then return end
    local point, _, relPoint, x, y = self.panel:GetPoint(1)
    if not point then return end
    local db = ns.db.coTanks
    db.point, db.relPoint = point, relPoint
    db.x, db.y = math.floor(x + 0.5), math.floor(y + 0.5)
end

function CoTanks:SetUnlocked(unlocked)
    self:Create()
    local db = ns.db.coTanks
    db.locked = not unlocked
    self.panel:EnableMouse(unlocked and true or false)
    self.moveHint:SetShown(unlocked and true or false)
    if not unlocked then self:SavePosition() end
    self:Refresh()
end

-- Test mode is a SETTING, not a hidden state: it survives a reload, it shows
-- in the panel, and the display says so on screen. A display that quietly
-- keeps showing invented tanks after you tab back into the game is a way to
-- be lied to at exactly the wrong moment.
function CoTanks:SetTestMode(on)
    ns.db.coTanks.testMode = on and true or false
    self:Create()
    self:Refresh()
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
function CoTanks:Testing()
    return ns.db.coTanks.testMode and true or false
end

function CoTanks:RowCount()
    local db = ns.db.coTanks
    local limit = math.max(1, math.min(MAX_ROWS, db.maxRows or 5))
    if self:Testing() then return limit end

    -- ONE ROW MINIMUM WHILE IT IS BEING MOVED OR PREVIEWED. Playing solo there
    -- are no tanks, so the panel came out one pixel tall - "Move it on screen"
    -- unlocked something invisible and the user had nothing to drag. The row
    -- says what it is instead of pretending to be somebody.
    if not db.locked or self.hosted then return math.max(1, #self.tanks) end

    return math.min(limit, #self.tanks)
end

function CoTanks:ShouldShow()
    local db = ns.db.coTanks
    -- In the preview card it always shows. A card that is empty until you
    -- switch the feature on is a card that cannot tell you what switching it
    -- on would look like.
    if self.hosted then return true end
    if not db.enabled then return false end
    if self:Testing() then return true end
    if not db.locked then return true end
    if db.onlyInGroup and not IsInGroup() then return false end
    if db.onlyInInstance and not IsInInstance() then return false end
    return #self.tanks > 0
end

function CoTanks:Refresh()
    if not self.panel then return end
    local db = ns.db.coTanks
    local testing = self:Testing()

    if not testing then self:CollectTanks(self.tanks) else wipe(self.tanks) end

    if not self:ShouldShow() then
        self.panel:Hide()
        for _, row in ipairs(self.rows) do row:Hide() end
        return
    end

    local shown = self:RowCount()
    for index, row in ipairs(self.rows) do
        if index <= shown then
            local snap = self.snapshots[index]
            if testing then
                TestSnapshot(index, snap)
            elseif self.tanks[index] then
                LiveSnapshot(self.tanks[index], snap)
            else
                -- Unlocked or previewed with nobody to show. Something to
                -- take hold of, and it says why it is empty.
                BlankSnapshot(snap)
                snap.name = "No tanks in the group"
                snap.healthMax, snap.health = 1, 1
            end
            PaintRow(row, snap, db, testing)
            row:Show()
        else
            row:Hide()
        end
    end

    local extent = self:RowExtent(db)
    self.panel:SetSize(math.max(1, db.width),
        math.max(1, shown * (extent + db.spacing) - db.spacing))
    self.panel:Show()

    self:WireAuras()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
function CoTanks:StartEvents()
    if self.events then return end

    local frame = CreateFrame("Frame")
    for _, event in ipairs({
        "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_ENTERING_WORLD",
        "PLAYER_TARGET_CHANGED", "RAID_TARGET_UPDATE", "PLAYER_REGEN_ENABLED",
    }) do
        frame:RegisterEvent(event)
    end

    frame:SetScript("OnEvent", function(_, event)
        -- Container creation and unit binding are refused in combat, so both
        -- requests queue and are replayed the moment it ends. Without this a
        -- tank who joined mid-pull has a row and no aura strip until the next
        -- settings change.
        if event == "PLAYER_REGEN_ENABLED" then
            if CoTanks.containersPending then CoTanks:BuildAuraContainers() end
            if CoTanks.wirePending then CoTanks:WireAuras() end
        end
        CoTanks:Refresh()
    end)

    -- HEALTH IS POLLED, and that is a decision rather than laziness. The
    -- event route is UNIT_HEALTH with a unit filter, which has to be
    -- re-registered on every roster change for a set of units that changes
    -- whenever anybody in the raid swaps role. At most eight rows at 10 Hz
    -- costs less than getting that wrong once.
    frame:SetScript("OnUpdate", function(_, elapsed)
        CoTanks.accum = (CoTanks.accum or 0) + elapsed
        if CoTanks.accum < HEALTH_INTERVAL then return end
        CoTanks.accum = 0
        if not (CoTanks.panel and CoTanks.panel:IsShown()) then return end

        local db = ns.db.coTanks
        local testing = CoTanks:Testing()
        for index, row in ipairs(CoTanks.rows) do
            if row:IsShown() then
                local snap = CoTanks.snapshots[index]
                if testing then
                    TestSnapshot(index, snap)
                elseif CoTanks.tanks[index] then
                    LiveSnapshot(CoTanks.tanks[index], snap)
                end
                PaintRow(row, snap, db, testing)
            end
        end
    end)

    self.events = frame
end

-- Why the aura strips are empty on a live frame, in one sentence, for the
-- panel to print. Empty when there is nothing to explain.
function CoTanks:AuraReason()
    if ns.Engine and ns.Engine:IsAvailable() then return nil end
    local why = ns.Engine and ns.Engine:UnavailableReason()
    return why or "this client cannot show another player's auras"
end

---------------------------------------------------------------------------
-- Live auras - the 12.1 route
--
-- WRITTEN, NEVER RUN. There is no client on this machine that has
-- AuraContainer, so none of this has executed once. It is built against the
-- contract written at the top of Core/Engine.lua, which was itself read off
-- four working 12.1 implementations - but "follows a contract" and "works"
-- are different claims and only one of them is being made here.
--
-- The four rules that shape it, from that contract:
--   * content first, unit LAST, or the container never registers UNIT_AURA
--   * the button subtree may only be built inside initializeFrame
--   * an uncaught error in there kills the whole group, so decoration is
--     pcall-armoured
--   * a duration FontString must be fonted BEFORE it is registered
---------------------------------------------------------------------------
local function BuildEngineStrip(strip, cfg, filter)
    if not (ns.Engine and ns.Engine:IsAvailable()) then return nil end
    local wanted = cfg.show and math.max(0, math.min(40, cfg.max or 0)) or 0
    if wanted < 1 then return nil end

    local size = math.max(6, cfg.size or 20)
    local border = cfg.borderColor

    -- THE STRIP'S OWN CORNER, the same one the test strip lays out from.
    -- Handed the ROW's corner the engine starts its flow at the opposite end
    -- of the strip frame and overflows the other way - so the live display
    -- could not land where the preview drew it, which is the one thing the
    -- preview exists to promise.
    local corner = ns.Layout.StripCorner(cfg.anchor)

    local container = ns.Engine:CreateContainer(strip, {
        anchorPoint = corner,
        growthH     = cfg.growth == "left" and "LEFT" or "RIGHT",
        growthV     = corner:find("BOTTOM") and "UP" or "DOWN",
    })
    if not container then return nil end

    ns.Engine:AddGroup(container, {
        key    = "zscotank",
        filter = ns.Engine:Filter(filter),
        max    = wanted,
        layout = {
            -- THE SAME FOUR NUMBERS THE TEST STRIP LAYS ITSELF OUT WITH.
            -- The engine does its own arithmetic, so this is the only thing
            -- keeping the preview and the real display the same shape.
            elementWidth   = size,
            elementHeight  = size,
            elementSpacing = cfg.spacing or 0,
            lineSpacing    = cfg.spacing or 0,
        },
        initialize = function(button)
            ns.Engine:MakeDisplayOnly(button)

            local icon = button:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints(button)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            button:SetIcon(icon)

            local edge = ns.CreateBorder(button, math.max(0, cfg.borderSize or 0),
                "OVERLAY")
            edge:SetColor(border[1], border[2], border[3], 1)

            local textLayer = CreateFrame("Frame", nil, button)
            textLayer:SetAllPoints(button)
            textLayer:SetFrameLevel(button:GetFrameLevel() + 4)

            if cfg.stacks then
                pcall(function()
                    local count = textLayer:CreateFontString(nil, "OVERLAY")
                    local countSize = cfg.stacksSize
                    if not countSize or countSize <= 0 then countSize = size * 0.36 end
                    ns.StyleUIFont(count, math.max(8, countSize), "OUTLINE")
                    count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
                    -- minCount 2 blanks a single application engine-side, so
                    -- a stack count never has to be compared by us.
                    button:SetApplicationCount(count, { minCount = 2 })
                end)
            end

            if cfg.countdown then
                pcall(function()
                    local text = textLayer:CreateFontString(nil, "OVERLAY")
                    local textSize = cfg.countdownSize
                    if not textSize or textSize <= 0 then textSize = size * 0.42 end
                    -- Fonted BEFORE registration: the engine writes into it at
                    -- bind time and an unfonted string hard-errors.
                    ns.StyleUIFont(text, math.max(8, textSize), "OUTLINE")
                    text:SetPoint("CENTER", button, "CENTER", 0, 0)
                    ns.Engine.BindDurationText(button, text)
                end)
            end
        end,
    })

    return container
end

-- Groups are ADD-ONLY: a settings change that alters the baked skin needs a
-- NEW container, and the old one is retired rather than mutated. So this runs
-- from ApplyLayout, not from Refresh.
-- What the containers were BAKED with. A group is add-only, so any change to
-- the skin needs new containers - but only a change to the skin, and a frame
-- can never be freed. Rebuilding on every ApplyLayout meant one drag of one
-- slider leaked hundreds of AuraContainer frames.
local function StripSignature(db)
    local parts = {}
    for _, key in ipairs({ "debuffs", "buffs" }) do
        local cfg = db[key]
        local colour = cfg.borderColor or { 0, 0, 0 }
        parts[#parts + 1] = table.concat({
            tostring(cfg.show), tostring(cfg.max), tostring(cfg.size),
            tostring(cfg.spacing), tostring(cfg.perRow), tostring(cfg.anchor),
            tostring(cfg.growth), tostring(cfg.borderSize),
            tostring(colour[1]), tostring(colour[2]), tostring(colour[3]),
            tostring(cfg.countdown), tostring(cfg.countdownSize),
            tostring(cfg.stacks), tostring(cfg.stacksSize),
        }, ",")
    end
    return table.concat(parts, "|")
end

function CoTanks:BuildAuraContainers()
    if not (ns.Engine and ns.Engine:IsAvailable()) then return end
    if ns.Engine:IsLocked() then
        self.containersPending = true
        return
    end
    self.containersPending = false

    local db = ns.db.coTanks
    local signature = StripSignature(db)
    if signature == self.containerSignature then return end
    self.containerSignature = signature
    for _, row in ipairs(self.rows or {}) do
        for key, filter in pairs({ debuffs = "HARMFUL", buffs = "HELPFUL" }) do
            local strip = row[key]
            if strip.container then
                ns.Engine:Retire(strip.container)
                strip.container = nil
            end
            strip.container = BuildEngineStrip(strip, db[key], filter)
            strip.boundUnit = nil
        end
    end
    self:WireAuras()
end

-- Re-points each row's containers at its tank. Refused in combat, so the
-- request is queued and replayed when combat ends.
function CoTanks:WireAuras()
    if not (ns.Engine and ns.Engine:IsAvailable()) then return end
    if ns.Engine:IsLocked() then
        self.wirePending = true
        return
    end
    self.wirePending = false

    local testing = self:Testing()
    for index, row in ipairs(self.rows or {}) do
        local unit = not testing and self.tanks[index] or nil
        for _, key in ipairs({ "debuffs", "buffs" }) do
            local strip = row[key]
            if strip.container and strip.boundUnit ~= unit then
                if unit then
                    ns.Engine:Bind(strip.container, unit)
                else
                    ns.Engine:Retire(strip.container)
                end
                strip.boundUnit = unit
            end
        end
    end
end
