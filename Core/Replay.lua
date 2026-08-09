---------------------------------------------------------------------------
-- Replay.lua - the death, played back on a timeline
--
-- The owner's ask, in his words: "dann würde ich das als extra fenster
-- aufmachen - dann ein zeitstrahl in der mitte, oben der income also was an
-- dmg und heal reinkommt. und spieler aktionen. mit speed regler, pause.
-- play stop. und spell icons, zahlen, tooltips".
--
-- WHY THIS IS WORTH A WINDOW OF ITS OWN. The death table answers "what
-- killed me". It cannot answer "what was I doing while it happened", and
-- that is the question a tank actually has. Two rows of the same clock -
-- what came in above the line, what you pressed below it - answer it
-- without a sentence: anybody looking at a bare lower half can see that no
-- defensive was pressed.
--
-- WHERE THE DATA COMES FROM, and one correction worth keeping written down:
-- the presses are NOT combat log. The combat log is closed to addons on
-- this patch. They come from UNIT_SPELLCAST_SUCCEEDED for "player", which
-- survived - ns.History records every one with the time it landed. The
-- incoming side is Blizzard's own death recap, the same source the death
-- window reads. Nothing here asks the client anything it has not already
-- answered once.
---------------------------------------------------------------------------
local _, ns = ...

local Replay = {}
ns.Replay = Replay

local UI -- taken late: Widgets loads after this file

local frame

-- The plot. The axis runs the full width between these margins, time
-- flowing left to right and ending at the killing blow on the right edge.
local PLOT_L, PLOT_R = 30, 30
local FRAME_W, FRAME_H = 780, 330
local PLOT_W = FRAME_W - PLOT_L - PLOT_R
local AXIS_Y = 196          -- from the top of the frame
local COLUMN_MAX = 96       -- tallest an incoming column may draw
local MARKS_IN, MARKS_OUT = 28, 20

-- Half a second before the first thing happens, so the eye is on the plot
-- when it starts moving rather than arriving after it.
local LEAD = 0.5
local SPEEDS = { 0.25, 0.5, 1, 2 }

---------------------------------------------------------------------------
-- Pure rules, exported for the self test
---------------------------------------------------------------------------

-- How far back the plot reaches, in seconds. The oldest thing in the story
-- plus the lead-in, and never zero - a plot with no width would put every
-- mark on top of every other one and divide by nothing.
function Replay.Span(story)
    local oldest = 0
    for _, item in ipairs(story or {}) do
        if item.t > oldest then oldest = item.t end
    end
    return math.max(1, oldest + LEAD)
end

-- Where a moment sits on the axis, as a fraction from the left. t counts
-- DOWN to the death, so the oldest moment is at 0 and the death is at 1.
function Replay.Fraction(t, span)
    if not (span and span > 0) then return 1 end
    local at = (span - (t or 0)) / span
    return math.max(0, math.min(1, at))
end

-- The next speed the button walks to, wrapping at the end.
function Replay.NextSpeed(current)
    local at = 0
    for index, value in ipairs(SPEEDS) do
        if math.abs(value - (current or 1)) < 0.001 then at = index end
    end
    return SPEEDS[(at % #SPEEDS) + 1]
end

-- How tall an incoming column stands: its share of the health bar, floored
-- so a small hit is still a visible mark rather than a line.
function Replay.ColumnHeight(amount, maxHP)
    if not (maxHP and maxHP > 0 and amount and amount > 0) then return 6 end
    local share = math.min(1, amount / maxHP)
    return math.max(6, share * COLUMN_MAX)
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function Tooltip(owner, item)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local shown = false
    if item.spellID then
        shown = pcall(GameTooltip.SetSpellByID, GameTooltip, item.spellID)
    end
    if not shown then
        GameTooltip:ClearLines()
        GameTooltip:AddLine(item.name or "", 1, 1, 1)
    end
    if item.cast then
        GameTooltip:AddLine(item.defensive and "You pressed it - a defensive"
            or "You pressed it", 0.49, 0.78, 0.83)
    elseif item.who then
        GameTooltip:AddLine("from " .. item.who, 0.61, 0.64, 0.69)
    end
    if item.amount and item.amount > 0 then
        GameTooltip:AddLine(string.format("%s%s",
            item.heal and "+" or "-", ns.ShortNumber(item.amount)),
            0.61, 0.64, 0.69)
    end
    if item.overkill then
        GameTooltip:AddLine(ns.ShortNumber(item.overkill)
            .. " of it was overkill", 0.61, 0.64, 0.69)
    end
    if item.hp then
        GameTooltip:AddLine("Health left afterwards: "
            .. ns.ShortNumber(item.hp), 0.61, 0.64, 0.69)
    end
    GameTooltip:AddLine(string.format("%.1fs before the end", item.t or 0),
        0.38, 0.42, 0.46)
    GameTooltip:Show()
end

-- One mark on the plot: a column, an icon and a number for the incoming
-- side; an icon alone for a press of yours. Built once, re-pointed per
-- death, because the marks are a pool like every other list in this addon.
local function BuildMark(parent, upwards)
    local C = UI.C
    local mark = CreateFrame("Frame", nil, parent)
    mark:SetSize(24, 24)

    mark.column = mark:CreateTexture(nil, "ARTWORK")
    mark.column:SetWidth(upwards and 8 or 3)

    mark.icon = mark:CreateTexture(nil, "ARTWORK")
    mark.icon:SetSize(22, 22)
    mark.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    mark.edge = ns.CreateBorder(mark, 1, "OVERLAY")

    mark.value = UI.Label(mark, "", 10, C.text)
    mark.value:SetJustifyH("CENTER")
    mark.value:SetWidth(70)

    mark:EnableMouse(true)
    mark:SetScript("OnEnter", function(self)
        if self.item then Tooltip(self, self.item) end
    end)
    mark:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    mark:Hide()
    return mark
end

local function BuildWindow()
    UI = ns.UI
    local C = UI.C

    frame = CreateFrame("Frame", "ZwoelfStuffDeathReplay", UIParent)
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    UI.Fill(frame, "BACKGROUND", C.windowBg)
    local edge = ns.CreateBorder(frame, 1, "BORDER")
    edge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)

    frame.title = UI.Label(frame, "Replay", 15, C.text)
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", PLOT_L, -14)

    frame.sub = UI.Label(frame, "", 11, C.textFaint)
    frame.sub:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -3)

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
    local closeMark = UI.Glyph(close, "ui-close", 12, C.textDim)
    closeMark:SetPoint("CENTER", close, "CENTER", 0, 0)
    close:SetScript("OnClick", function() Replay:Close() end)

    -- The health bar, across the top of the plot. It is the one number
    -- that makes the columns mean something as they land.
    frame.health = CreateFrame("Frame", nil, frame)
    frame.health:SetSize(PLOT_W, 16)
    frame.health:SetPoint("TOPLEFT", frame, "TOPLEFT", PLOT_L, -62)

    local track = frame.health:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(frame.health)
    track:SetColorTexture(C.surface[1], C.surface[2], C.surface[3], 1)

    frame.healthFill = frame.health:CreateTexture(nil, "ARTWORK")
    frame.healthFill:SetPoint("TOPLEFT", frame.health, "TOPLEFT", 0, 0)
    frame.healthFill:SetPoint("BOTTOMLEFT", frame.health, "BOTTOMLEFT", 0, 0)
    frame.healthFill:SetColorTexture(0.20, 0.26, 0.34, 1)

    frame.healthText = UI.Label(frame.health, "", 11, C.text)
    frame.healthText:SetPoint("LEFT", frame.health, "LEFT", 6, 0)

    frame.clock = UI.Label(frame.health, "", 11, C.text)
    frame.clock:SetPoint("RIGHT", frame.health, "RIGHT", -6, 0)
    frame.clock:SetJustifyH("RIGHT")

    -- The axis itself, with the playhead riding it.
    local axis = frame:CreateTexture(nil, "ARTWORK")
    axis:SetColorTexture(C.edge[1], C.edge[2], C.edge[3], 1)
    axis:SetPoint("TOPLEFT", frame, "TOPLEFT", PLOT_L, -AXIS_Y)
    axis:SetSize(PLOT_W, 1)

    frame.ticks = {}
    for i = 1, 11 do
        local tick = frame:CreateTexture(nil, "ARTWORK")
        tick:SetColorTexture(C.separator[1], C.separator[2], C.separator[3], 1)
        tick:SetSize(1, 5)
        local label = UI.Label(frame, "", 10, C.textGhost)
        label:SetJustifyH("CENTER")
        label:SetWidth(40)
        frame.ticks[i] = { tick = tick, label = label }
    end

    frame.playhead = frame:CreateTexture(nil, "OVERLAY")
    frame.playhead:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9)
    frame.playhead:SetWidth(1)
    frame.playhead:SetPoint("TOP", frame, "TOPLEFT", PLOT_L, -56)
    frame.playhead:SetHeight(AXIS_Y + 48 - 56)

    -- Two lanes of marks: incoming above the axis, your own below it.
    frame.incoming, frame.outgoing = {}, {}
    for i = 1, MARKS_IN do frame.incoming[i] = BuildMark(frame, true) end
    for i = 1, MARKS_OUT do frame.outgoing[i] = BuildMark(frame, false) end

    frame.laneIn = UI.Eyebrow(frame, "What came in")
    frame.laneIn:SetPoint("TOPLEFT", frame, "TOPLEFT", PLOT_L, -84)
    frame.laneOut = UI.Eyebrow(frame, "What you pressed")
    frame.laneOut:SetPoint("TOPLEFT", frame, "TOPLEFT", PLOT_L, -(AXIS_Y + 52))

    ---------------------------------------------------------------------
    -- The transport
    ---------------------------------------------------------------------
    local play
    play = UI.Button(frame, "Pause", 90, function()
        if not Replay.state then return end
        Replay.state.paused = not Replay.state.paused
        play.label:SetText(Replay.state.paused and "Play" or "Pause")
    end, "primary")
    play:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PLOT_L, 12)
    frame.playButton = play

    local stop = UI.Button(frame, "Stop", 80, function()
        Replay:Rewind()
    end)
    stop:SetPoint("LEFT", play, "RIGHT", 8, 0)

    local speed
    speed = UI.Button(frame, "Speed 1x", 96, function()
        local state = Replay.state
        if not state then return end
        state.speed = Replay.NextSpeed(state.speed)
        ns.db.death = ns.db.death or {}
        ns.db.death.replaySpeed = state.speed
        speed.label:SetText(Replay.SpeedLabel(state.speed))
    end)
    speed:SetPoint("LEFT", stop, "RIGHT", 8, 0)
    frame.speedButton = speed

    frame.legend = UI.Label(frame, "", 11, C.textFaint)
    frame.legend:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PLOT_L, 46)
    frame.legend:SetWidth(PLOT_W)
    frame.legend:SetJustifyH("LEFT")

    local dismiss = UI.Button(frame, "Close", 90, function()
        Replay:Close()
    end)
    dismiss:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PLOT_R, 12)
end

-- "Speed 0.25x" without a trailing zero pretending to be precision.
function Replay.SpeedLabel(speed)
    if speed == math.floor(speed) then
        return string.format("Speed %dx", speed)
    end
    return string.format("Speed %.2gx", speed)
end

---------------------------------------------------------------------------
-- Painting
---------------------------------------------------------------------------

-- Places every mark for one death. Positions do not change while it plays;
-- only what is lit does, which is what makes the playhead read as time
-- passing rather than as things appearing out of nowhere.
local function Place(snapshot, span)
    local C = ns.UI.C
    local events = ns.Death.RecentEvents(snapshot.events, ns.Death.WINDOW)
    local maxHP = snapshot.maxHP

    local slot = 0
    for _, ev in ipairs(events) do
        slot = slot + 1
        if slot <= MARKS_IN then
            local mark = frame.incoming[slot]
            mark.item = ev
            local height = Replay.ColumnHeight(ev.amount, maxHP)
            local x = PLOT_L + Replay.Fraction(ev.t, span) * PLOT_W

            mark:ClearAllPoints()
            mark:SetPoint("BOTTOM", frame, "TOPLEFT", x, -(AXIS_Y - 1))
            mark:SetSize(24, height + 46)

            mark.column:ClearAllPoints()
            mark.column:SetPoint("BOTTOM", mark, "BOTTOM", 0, 0)
            mark.column:SetHeight(height)
            if ev.heal then
                mark.column:SetColorTexture(0.12, 0.42, 0.16, 0.95)
            else
                mark.column:SetColorTexture(0.55, 0.11, 0.11, 0.95)
            end

            mark.icon:ClearAllPoints()
            mark.icon:SetPoint("BOTTOM", mark.column, "TOP", 0, 2)
            mark.icon:SetTexture((ev.spellID and ns.SpellTexture(ev.spellID))
                or 135274)
            mark.edge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)

            mark.value:ClearAllPoints()
            mark.value:SetPoint("BOTTOM", mark.icon, "TOP", 0, 2)
            mark.value:SetText((ev.heal and "|cff67c971+" or "|cffe06c5e-")
                .. ns.ShortNumber(ev.amount) .. "|r")
            mark:Show()
        end
    end
    for i = slot + 1, MARKS_IN do
        frame.incoming[i].item = nil
        frame.incoming[i]:Hide()
    end

    slot = 0
    for _, cast in ipairs(snapshot.casts or {}) do
        slot = slot + 1
        if slot <= MARKS_OUT then
            local mark = frame.outgoing[slot]
            mark.item = {
                t = cast.t, name = cast.name, spellID = cast.spellID,
                cast = true, defensive = cast.defensive,
            }
            local x = PLOT_L + Replay.Fraction(cast.t, span) * PLOT_W

            mark:ClearAllPoints()
            mark:SetPoint("TOP", frame, "TOPLEFT", x, -(AXIS_Y + 1))
            mark:SetSize(24, 44)

            mark.column:ClearAllPoints()
            mark.column:SetPoint("TOP", mark, "TOP", 0, 0)
            mark.column:SetHeight(10)
            if cast.defensive then
                mark.column:SetColorTexture(C.accent[1], C.accent[2],
                    C.accent[3], 1)
            else
                mark.column:SetColorTexture(C.textGhost[1], C.textGhost[2],
                    C.textGhost[3], 1)
            end

            mark.icon:ClearAllPoints()
            mark.icon:SetPoint("TOP", mark.column, "BOTTOM", 0, -2)
            mark.icon:SetTexture(cast.spellID and ns.SpellTexture(cast.spellID))
            -- A defensive gets the accent edge: on a plot of twenty grey
            -- presses, the two that mattered have to be findable.
            if cast.defensive then
                mark.edge:SetColor(C.accent[1], C.accent[2], C.accent[3], 1)
            else
                mark.edge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)
            end

            mark.value:SetText("")
            mark:Show()
        end
    end
    for i = slot + 1, MARKS_OUT do
        frame.outgoing[i].item = nil
        frame.outgoing[i]:Hide()
    end

    -- The axis labels: one every two seconds, oldest on the left.
    local step = span > 12 and 4 or 2
    for i, entry in ipairs(frame.ticks) do
        local at = (i - 1) * step
        if at <= span then
            local x = PLOT_L + Replay.Fraction(at, span) * PLOT_W
            entry.tick:ClearAllPoints()
            entry.tick:SetPoint("TOP", frame, "TOPLEFT", x, -AXIS_Y)
            entry.label:ClearAllPoints()
            entry.label:SetPoint("TOP", frame, "TOPLEFT", x - 20, -(AXIS_Y + 7))
            entry.label:SetText(at == 0 and "death" or string.format("-%ds", at))
            entry.tick:Show()
            entry.label:Show()
        else
            entry.tick:Hide()
            entry.label:Hide()
        end
    end
end

-- What is lit and what is waiting, for the clock's current position.
local function Paint(now)
    local state = Replay.state
    local span = state.span

    for _, lane in ipairs({ frame.incoming, frame.outgoing }) do
        for _, mark in ipairs(lane) do
            if mark.item then
                -- Landed marks stand at full strength; the rest wait at a
                -- quarter, visible enough to read the shape of what is
                -- coming without pretending it has happened.
                mark:SetAlpha(mark.item.t >= now and 1 or 0.22)
            end
        end
    end

    local _, hp = ns.Death.ReplayAt(state.events, now, state.maxHP)
    local pct = (state.maxHP and state.maxHP > 0)
        and math.max(0, math.min(1, (hp or 0) / state.maxHP)) or 0
    frame.healthFill:SetWidth(math.max(1, PLOT_W * pct))
    frame.healthText:SetText(hp
        and string.format("%s  |cff9ba3af%d%%|r", ns.ShortNumber(hp),
            math.floor(pct * 100 + 0.5))
        or "")
    frame.clock:SetText(string.format("-%.1fs", math.max(0, now)))

    frame.playhead:ClearAllPoints()
    frame.playhead:SetPoint("TOP", frame, "TOPLEFT",
        PLOT_L + Replay.Fraction(now, span) * PLOT_W, -56)
end

---------------------------------------------------------------------------
-- Driving it
---------------------------------------------------------------------------

function Replay:Open(snapshot)
    if not snapshot then
        ns.Print("No death recorded yet this session.")
        return
    end
    if not frame then BuildWindow() end

    local events = ns.Death.RecentEvents(snapshot.events, ns.Death.WINDOW)
    local story = ns.Death.Storyline(events, snapshot.casts)
    if #story == 0 then
        ns.Print("Nothing readable to replay for that death.")
        return
    end

    local span = Replay.Span(story)
    Replay.state = {
        events = events,
        maxHP = snapshot.maxHP,
        span = span,
        now = span,
        paused = false,
        speed = (ns.db and ns.db.death and ns.db.death.replaySpeed) or 1,
    }

    frame.title:SetText(snapshot.killer
        and ("Replay - killed by " .. snapshot.killer) or "Replay")
    frame.sub:SetText((snapshot.when or "")
        .. (snapshot.where and ("  -  " .. snapshot.where) or ""))

    -- The one sentence this window exists to make unnecessary - said
    -- anyway, because a plot is read in a second and a sentence in less.
    local pressed = snapshot.analysis and snapshot.analysis.defensivesPressed
    frame.legend:SetText(#(pressed or {}) > 0
        and ("Defensives pressed: " .. table.concat(pressed, ", ") .. ".")
        or "|cffe0a05eNo defensive was pressed in these seconds.|r")

    frame.playButton.label:SetText("Pause")
    frame.speedButton.label:SetText(Replay.SpeedLabel(Replay.state.speed))

    Place(snapshot, span)
    Paint(span)

    frame:SetScript("OnUpdate", function(_, elapsed)
        local state = Replay.state
        if not state or state.paused then return end
        state.now = state.now - elapsed * state.speed
        if state.now <= -1 then
            -- It stops ON the death rather than running off the end, and
            -- stays there: the last frame is the one worth looking at.
            state.now = 0
            state.paused = true
            frame.playButton.label:SetText("Play")
        end
        Paint(math.max(0, state.now))
    end)

    frame:Show()
end

-- Back to the start, paused - the second look is the one that finds it.
function Replay:Rewind()
    local state = Replay.state
    if not state then return end
    state.now = state.span
    state.paused = true
    if frame then
        frame.playButton.label:SetText("Play")
        Paint(state.now)
    end
end

function Replay:Close()
    Replay.state = nil
    if frame then
        frame:SetScript("OnUpdate", nil)
        frame:Hide()
    end
end
