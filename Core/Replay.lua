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
local FRAME_W, FRAME_H = 780, 496
local PLOT_W = FRAME_W - PLOT_L - PLOT_R
local AXIS_Y = 274          -- from the top of the frame
local COLUMN_MAX = 96       -- tallest an incoming column may draw
local MARKS_IN, MARKS_OUT, MARKS_HEAL = 28, 20, 20

-- Three lanes and where each starts, measured from the top of the frame.
local HEALTH_Y = 92         -- your own health bar
local LANE_IN_Y = 120       -- "what came in", growing UP to the axis
local LANE_OUT_Y = 282      -- "what you pressed", under the axis
local LANE_HEAL_Y = 356     -- "who healed you", under that

-- Half a second before the first thing happens, so the eye is on the plot
-- when it starts moving rather than arriving after it.
local LEAD = 0.5
local SPEED_MIN, SPEED_MAX, SPEED_STEP = 0.25, 3, 0.25

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

-- The speed, kept inside what is watchable. It was a button walking a list
-- of four; the owner asked for a slider, which is right - a quarter and a
-- half are different things to want and clicking past one to reach the
-- other is a worse control than dragging to it.
function Replay.ClampSpeed(value)
    if type(value) ~= "number" then return 1 end
    return math.max(SPEED_MIN, math.min(SPEED_MAX, value))
end

-- What the play button MEANS at a given moment. At the end of a replay the
-- clock has run out, so un-pausing it would do nothing anybody can see -
-- a button that looks live and changes nothing reads as broken. There, and
-- only there, play means play it again.
function Replay.PlayAction(now)
    if (now or 0) <= 0 then return "restart" end
    return "toggle"
end

-- WHAT WE ACTUALLY KNOW ABOUT THE MOB THAT KILLED YOU.
--
-- The owner asked whether the tooltip could say what the mob "can do -
-- spells, hp, whatever". Honestly: no. There is no client call that lists
-- an arbitrary NPC's abilities, and on this patch a mob inside a dungeon
-- withholds its name, its health and its creature type outright - that is
-- measured, it is why the pull badges were parked. The Encounter Journal
-- knows raid and dungeon BOSSES and nothing about trash.
--
-- What we do have is better than a wiki page anyway: what this mob did to
-- YOU, in these seconds. Summed from the events we already read.
function Replay.KillerSummary(events, killer)
    local out = { hits = 0, total = 0, biggest = 0, spells = {} }
    if not killer then return out end
    local seen = {}
    for _, ev in ipairs(events or {}) do
        if ev.who == killer and not ev.heal then
            out.hits = out.hits + 1
            out.total = out.total + (ev.amount or 0)
            if (ev.amount or 0) > out.biggest then out.biggest = ev.amount end
            local name = ev.name
            if name and not seen[name] then
                seen[name] = true
                out.spells[#out.spells + 1] = name
            end
        end
    end
    return out
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
local function BuildMark(parent, kind)
    local C = UI.C
    local mark = CreateFrame("Frame", nil, parent)
    mark:SetSize(24, 24)

    mark.column = mark:CreateTexture(nil, "ARTWORK")
    mark.column:SetWidth(kind == "in" and 8 or 3)

    mark.icon = mark:CreateTexture(nil, "ARTWORK")
    mark.icon:SetSize(22, 22)
    mark.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    mark.edge = ns.CreateBorder(mark, 1, "OVERLAY")

    mark.value = UI.Label(mark, "", 10, C.text)
    mark.value:SetJustifyH("CENTER")
    mark.value:SetWidth(70)

    -- The heal lane names WHO. A number with no name on it answers "was I
    -- healed" and not "was anybody healing me", and the second is the
    -- question a tank has after a death.
    if kind == "heal" then
        mark.who = UI.Label(mark, "", 10, C.textFaint)
        mark.who:SetJustifyH("CENTER")
        mark.who:SetWidth(84)
        mark.who:SetWordWrap(false)
    end

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
    -- Two movable windows in one strata: without this the death window's
    -- buttons drew straight through this one, because its children sit at
    -- a higher frame level than this frame's background. SetToplevel makes
    -- whichever is clicked come forward, which is what a person expects
    -- from two windows lying on each other.
    frame:SetToplevel(true)
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

    -- The killer, in the corner, with what he did to you on the hover.
    frame.portrait = CreateFrame("PlayerModel", nil, frame)
    frame.portrait:SetSize(56, 56)
    frame.portrait:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -44, -12)
    frame.portrait:EnableMouse(true)
    frame.portrait:Hide()
    local portraitEdge = ns.CreateBorder(frame.portrait, 1, "OVERLAY")
    portraitEdge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)

    frame.portrait:SetScript("OnEnter", function(self)
        local facts = self.facts
        if not (facts and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(facts.name or "Unknown", 1, 1, 1)
        if facts.hits > 0 then
            GameTooltip:AddLine(string.format(
                "%d hit%s on you, %s in total", facts.hits,
                facts.hits == 1 and "" or "s", ns.ShortNumber(facts.total)),
                0.61, 0.64, 0.69)
            GameTooltip:AddLine("Biggest: " .. ns.ShortNumber(facts.biggest),
                0.61, 0.64, 0.69)
        end
        if #facts.spells > 0 then
            GameTooltip:AddLine("Used: " .. table.concat(facts.spells, ", "),
                0.61, 0.64, 0.69, true)
        end
        -- Said out loud rather than left as a gap somebody wonders about.
        GameTooltip:AddLine("What else it can do is not something the client "
            .. "will tell an addon on this patch.", 0.38, 0.42, 0.46, true)
        GameTooltip:Show()
    end)
    frame.portrait:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    -- YOUR health, said in as many words. It is the only bar in the window
    -- and it was being read as the mob's.
    frame.healthLabel = UI.Eyebrow(frame, "Your health")
    frame.healthLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", PLOT_L,
        -(HEALTH_Y - 18))

    frame.health = CreateFrame("Frame", nil, frame)
    frame.health:SetSize(PLOT_W, 16)
    frame.health:SetPoint("TOPLEFT", frame, "TOPLEFT", PLOT_L, -HEALTH_Y)

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
    frame.playhead:SetPoint("TOP", frame, "TOPLEFT", PLOT_L, -(HEALTH_Y - 4))
    frame.playhead:SetHeight(LANE_HEAL_Y + 60 - HEALTH_Y)

    -- Three lanes: what hit you above the axis, what you pressed below it,
    -- and who was healing you under that.
    frame.incoming, frame.outgoing, frame.heals = {}, {}, {}
    for i = 1, MARKS_IN do frame.incoming[i] = BuildMark(frame, "in") end
    for i = 1, MARKS_OUT do frame.outgoing[i] = BuildMark(frame, "press") end
    for i = 1, MARKS_HEAL do frame.heals[i] = BuildMark(frame, "heal") end

    frame.laneIn = UI.Eyebrow(frame, "Damage on you")
    frame.laneIn:SetPoint("TOPLEFT", frame, "TOPLEFT", PLOT_L, -LANE_IN_Y)
    frame.laneOut = UI.Eyebrow(frame, "What you pressed")
    frame.laneOut:SetPoint("TOPLEFT", frame, "TOPLEFT", PLOT_L, -(LANE_OUT_Y + 46))
    frame.laneHeal = UI.Eyebrow(frame, "Healing on you")
    frame.laneHeal:SetPoint("TOPLEFT", frame, "TOPLEFT", PLOT_L, -LANE_HEAL_Y)

    ---------------------------------------------------------------------
    -- The transport
    ---------------------------------------------------------------------
    local play
    play = UI.Button(frame, "Pause", 90, function()
        local state = Replay.state
        if not state then return end
        if Replay.PlayAction(state.now) == "restart" then
            Replay:Restart()
            return
        end
        state.paused = not state.paused
        play.label:SetText(state.paused and "Play" or "Pause")
    end, "primary")
    play:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PLOT_L, 12)
    frame.playButton = play

    -- Again, from the top, running. Stop rewinds and WAITS - which is the
    -- one you want when you are about to point at something - and this one
    -- is the one you want when you just missed it.
    local again = UI.Button(frame, "Restart", 90, function()
        Replay:Restart()
    end)
    again:SetPoint("LEFT", play, "RIGHT", 8, 0)

    local stop = UI.Button(frame, "Stop", 80, function()
        Replay:Rewind()
    end)
    stop:SetPoint("LEFT", again, "RIGHT", 8, 0)

    -- A slider, not four steps of a button: a quarter and a half are
    -- different things to want, and clicking past one to reach the other is
    -- a worse control than dragging to it. `silent` because this is an
    -- on-screen panel - the options window has nothing to repaint.
    local speedRow = UI.Row(frame, "Speed", { controlWidth = 116 })
    speedRow:SetWidth(196)
    speedRow:SetPoint("LEFT", stop, "RIGHT", 16, 0)
    speedRow.rule:Hide()   -- a settings hairline has no business in a panel
    UI.Slider(speedRow, {
        get = function()
            return (Replay.state and Replay.state.speed)
                or (ns.db and ns.db.death and ns.db.death.replaySpeed) or 1
        end,
        set = function(value)
            value = Replay.ClampSpeed(value)
            if Replay.state then Replay.state.speed = value end
            ns.db.death = ns.db.death or {}
            ns.db.death.replaySpeed = value
        end,
        min = SPEED_MIN, max = SPEED_MAX, step = SPEED_STEP,
        silent = true,
        format = function(v) return Replay.SpeedLabel(v) end,
    })
    frame.speedRow = speedRow

    frame.legend = UI.Label(frame, "", 11, C.textFaint)
    frame.legend:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PLOT_L, 46)
    frame.legend:SetWidth(PLOT_W)
    frame.legend:SetJustifyH("LEFT")

    local dismiss = UI.Button(frame, "Close", 90, function()
        Replay:Close()
    end)
    dismiss:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PLOT_R, 12)
end

-- "0.25x" without a trailing zero pretending to be precision. The word
-- "Speed" is the row's label and does not belong in the value as well.
function Replay.SpeedLabel(speed)
    speed = speed or 1
    if speed == math.floor(speed) then
        return string.format("%dx", speed)
    end
    return string.format("%.2gx", speed)
end

---------------------------------------------------------------------------
-- Painting
---------------------------------------------------------------------------

-- One heal, in the bottom lane: the amount, the spell's icon, and the name
-- of whoever cast it under both. The class colour comes from the client
-- when that person is in your group, which is when it can.
local function PlaceHeal(mark, ev, span)
    local C = ns.UI.C
    mark.item = ev
    local x = PLOT_L + Replay.Fraction(ev.t, span) * PLOT_W

    mark:ClearAllPoints()
    mark:SetPoint("TOP", frame, "TOPLEFT", x, -(LANE_HEAL_Y + 16))
    mark:SetSize(24, 62)

    mark.column:ClearAllPoints()
    mark.column:SetPoint("TOP", mark, "TOP", 0, 0)
    mark.column:SetHeight(8)
    mark.column:SetColorTexture(0.12, 0.42, 0.16, 1)

    mark.icon:ClearAllPoints()
    mark.icon:SetPoint("TOP", mark.column, "BOTTOM", 0, -14)
    mark.icon:SetTexture((ev.spellID and ns.SpellTexture(ev.spellID)) or 135966)
    mark.edge:SetColor(0.12, 0.42, 0.16, 1)

    mark.value:ClearAllPoints()
    mark.value:SetPoint("TOP", mark.column, "BOTTOM", 0, -1)
    mark.value:SetText("|cff67c971+" .. ns.ShortNumber(ev.amount) .. "|r")

    -- The healer's name, in their class colour where the client will give
    -- it. UnitClass answers for a name that is in your group and nothing
    -- else, so it is asked under pcall and the plain name is the fallback.
    local who = ev.who
    if who then
        local coloured = who
        local ok, _, classFile = pcall(UnitClass, who)
        if ok and classFile and RAID_CLASS_COLORS
            and RAID_CLASS_COLORS[classFile] then
            local colour = RAID_CLASS_COLORS[classFile]
            coloured = string.format("|cff%02x%02x%02x%s|r",
                colour.r * 255, colour.g * 255, colour.b * 255, who)
        end
        mark.who:SetText(coloured)
    else
        mark.who:SetText("|cff626a76unnamed|r")
    end
    mark.who:ClearAllPoints()
    mark.who:SetPoint("TOP", mark.icon, "BOTTOM", 0, -2)
    mark.who:SetTextColor(C.textFaint[1], C.textFaint[2], C.textFaint[3])
    mark:Show()
end

-- Places every mark for one death. Positions do not change while it plays;
-- only what is lit does, which is what makes the playhead read as time
-- passing rather than as things appearing out of nowhere.
local function Place(snapshot, span)
    local C = ns.UI.C
    local events = ns.Death.RecentEvents(snapshot.events, ns.Death.WINDOW)
    local maxHP = snapshot.maxHP

    -- Damage above the axis, healing in a lane of its own below it. They
    -- were one lane and two colours; two questions - "what hit me" and
    -- "was anybody healing me" - read better as two rows of one clock.
    local slot, healSlot = 0, 0
    for _, ev in ipairs(events) do
        if ev.heal then
            healSlot = healSlot + 1
            if healSlot <= MARKS_HEAL then
                PlaceHeal(frame.heals[healSlot], ev, span)
            end
        else
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
                mark.column:SetColorTexture(0.55, 0.11, 0.11, 0.95)

                mark.icon:ClearAllPoints()
                mark.icon:SetPoint("BOTTOM", mark.column, "TOP", 0, 2)
                mark.icon:SetTexture((ev.spellID and ns.SpellTexture(ev.spellID))
                    or 135274)
                mark.edge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)

                mark.value:ClearAllPoints()
                mark.value:SetPoint("BOTTOM", mark.icon, "TOP", 0, 2)
                mark.value:SetText("|cffe06c5e-"
                    .. ns.ShortNumber(ev.amount) .. "|r")
                mark:Show()
            end
        end
    end
    for i = slot + 1, MARKS_IN do
        frame.incoming[i].item = nil
        frame.incoming[i]:Hide()
    end
    for i = healSlot + 1, MARKS_HEAL do
        frame.heals[i].item = nil
        frame.heals[i]:Hide()
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
            mark:SetPoint("TOP", frame, "TOPLEFT", x, -(LANE_OUT_Y - 8))
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

    for _, lane in ipairs({ frame.incoming, frame.outgoing, frame.heals }) do
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

    -- The killer's face and what he did to you, off the same events the
    -- plot is drawn from. Hidden outright when the recap gave us no model
    -- to draw - an empty box in the corner answers nothing.
    local art = snapshot.killerArt
    local drawn = false
    if art and (art.creatureID or art.displayID) then
        if art.creatureID and frame.portrait.SetCreature then
            drawn = pcall(frame.portrait.SetCreature, frame.portrait,
                art.creatureID)
        end
        if not drawn and art.displayID and frame.portrait.SetDisplayInfo then
            drawn = pcall(frame.portrait.SetDisplayInfo, frame.portrait,
                art.displayID)
        end
    end
    if drawn then
        pcall(frame.portrait.SetPosition, frame.portrait, 0, 0, 0)
        pcall(frame.portrait.SetFacing, frame.portrait, 0.4)
        pcall(frame.portrait.SetCamDistanceScale, frame.portrait, 1.35)
        local facts = Replay.KillerSummary(events, snapshot.killer)
        facts.name = snapshot.killer
        frame.portrait.facts = facts
        frame.portrait:Show()
    else
        frame.portrait.facts = nil
        frame.portrait:Hide()
    end

    -- The one sentence this window exists to make unnecessary - said
    -- anyway, because a plot is read in a second and a sentence in less.
    local pressed = snapshot.analysis and snapshot.analysis.defensivesPressed
    frame.legend:SetText(#(pressed or {}) > 0
        and ("Defensives pressed: " .. table.concat(pressed, ", ") .. ".")
        or "|cffe0a05eNo defensive was pressed in these seconds.|r")

    frame.playButton.label:SetText("Pause")
    frame.speedRow.Refresh()

    Place(snapshot, span)
    Paint(span)

    -- Opened from the death window's button, so it opens IN FRONT of it
    -- without needing a click to get there.
    frame:Raise()

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

-- From the top, playing.
function Replay:Restart()
    local state = Replay.state
    if not state then return end
    state.now = state.span
    state.paused = false
    if frame then
        frame.playButton.label:SetText("Pause")
        Paint(state.now)
    end
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
