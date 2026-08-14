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
local FRAME_W, FRAME_H = 780, 476
local PLOT_W = FRAME_W - PLOT_L - PLOT_R
local AXIS_Y = 268          -- from the top of the frame
local COLUMN_MAX = 70       -- tallest an incoming column may draw
local MARKS_IN, MARKS_OUT, MARKS_CAST = 28, 20, 24

-- The columns stand clear of the axis rather than on it: the seconds are
-- written ON the line now, and a column starting at the line drew straight
-- through them. The owner asked for exactly this - "setz die income balken
-- ein paar pixel nach oben, das die nicht die zahlen verdecken".
local COLUMN_LIFT = 10

-- A face over every hit. In a dungeon twenty things are hitting you at once
-- and a number with no face on it cannot be assigned to any of them.
--
-- Twenty pixels was the first size and the owner asked for bigger: a
-- creature model is not an icon, it is a whole silhouette squeezed into a
-- square, and below about this it stops being recognisable as anything.
local AVATAR = 30

-- Three lanes and where each starts, measured from the top of the frame.
local HEALTH_Y = 84         -- your own health bar
local LANE_IN_Y = 112       -- "what came in", growing UP to the axis
local LANE_CAST_Y = 272     -- everything else you cast, as icons only
local LANE_OUT_Y = 312      -- your DEFENSIVES, as bars, under those

-- THERE WAS A FOURTH LANE, "Healing on you", and it went in 4.81.0. Owner:
-- "bitte noch im death log replay der healing on you bereich rausnehmen." It
-- held a fifth of the window's height and, on the death he photographed,
-- nothing at all - which is the ordinary case for the deaths worth opening
-- this window over. The heals are still RECORDED and the death window still
-- counts them; what went is the empty band under the plot.

-- The press bars: how tall each row is and how many rows may stack before
-- the rest are dropped onto the last one. Four is more overlapping
-- defensives than anybody presses in ten seconds.
local BAR_H, BAR_GAP, BAR_ROWS = 18, 2, 4

-- WHERE THE PLOT ENDS, so the window is exactly as tall as what it draws.
-- The press bars are the lowest thing in it and BAR_ROWS of them can stack.
-- Derived rather than typed: the healing lane used to hold this edge down,
-- and a number left behind after it went would have left the gap behind too.
local PLOT_BOTTOM = LANE_OUT_Y + BAR_ROWS * (BAR_H + BAR_GAP)

-- Half a second before the first thing happens, so the eye is on the plot
-- when it starts moving rather than arriving after it.
local LEAD = 0.5
local SPEED_MIN, SPEED_MAX, SPEED_STEP = 0.25, 3, 0.25
-- Eight times in means a ten-second death shown one and a quarter seconds
-- at a time, which is finer than any press sequence a person makes.
local ZOOM_MAX = 8

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

-- WHICH SLICE OF TIME THE PLOT SHOWS.
--
-- The owner's problem, in his words: six spells inside two tenths of a
-- second all draw on top of each other. The answer is not smaller icons -
-- it is a plot that can be zoomed into and scrolled along, the way every
-- log viewer works.
--
-- zoom 1 shows the whole span. zoom 4 shows a quarter of it, centred on
-- `centre` - which while it is playing is the playhead, so the window
-- follows the story, and while it is paused is wherever the wheel left it.
-- Returns from (the older edge, on the left) and to (the newer, on the
-- right), both clamped inside the span so scrolling cannot run off it.
function Replay.View(span, zoom, centre)
    span = math.max(0.001, span or 1)
    local visible = span / math.max(1, zoom or 1)
    if visible >= span then return span, 0 end

    centre = centre or (visible / 2)
    local from = centre + visible / 2
    if from > span then from = span end
    local to = from - visible
    if to < 0 then
        to = 0
        from = visible
    end
    return from, to
end

-- Where a moment sits, as a fraction from the left edge of what is shown.
-- t counts DOWN to the death, so `from` is the left edge and `to` the
-- right. A moment outside the view answers past 0 or past 1 rather than
-- being clamped onto the edge - a mark two seconds off screen must not
-- pile up against the border pretending it is at it.
function Replay.Fraction(t, from, to)
    from = from or 1
    to = to or 0
    local width = from - to
    if width <= 0 then return 1 end
    return (from - (t or 0)) / width
end

-- Is this moment on screen at all?
function Replay.Visible(t, from, to)
    return (t or 0) <= (from or 0) + 0.001 and (t or 0) >= (to or 0) - 0.001
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
--
-- Asked for ANY source now, not only the killer: every face on the plot
-- carries its own summary, which is the point of putting a face on every
-- hit in the first place.
-- Death owns the recap and three windows ask this now, so the body moved
-- there. The name stays: this file has called it that since 4.60.0, and
-- so do its checks.
function Replay.SourceSummary(events, who)
    return ns.Death.SourceSummary(events, who)
end

-- How tall an incoming column stands: its share of the health bar, floored
-- so a small hit is still a visible mark rather than a line.
function Replay.ColumnHeight(amount, maxHP)
    if not (maxHP and maxHP > 0 and amount and amount > 0) then return 6 end
    local share = math.min(1, amount / maxHP)
    return math.max(6, share * COLUMN_MAX)
end

---------------------------------------------------------------------------
-- What you pressed, as BARS
--
-- The owner asked for it and he is right: an icon says "you pressed it" and
-- a bar says "and it was up for these four seconds, which is the half of it
-- that was still true when the hit landed". Two of them running at once
-- stack, so an overlap is visible instead of two icons on top of each other.
--
-- HOW LONG IS IT UP? This addon has one rule about durations and it is
-- MEASURED, NEVER ASSUMED - see KnownProcs.lua, which says so in capitals.
-- On this patch aura data is secret, so no call answers "how long does
-- Icebound Fortitude last".
--
-- The first version of this had one source: the number a person can type in
-- on the Auras page. Nobody types it in, so every press drew as a stub and
-- the owner said so - "die cd bars muessen so weit gehen wie sie aktiv
-- sind". The answer was not to invent a length. It was to MEASURE one:
-- History.lua now watches Blizzard's buff viewers and records the window
-- between a tracked buff going up and going down, so a press carries the
-- length of its own window - what happened, in that fight, to that press.
--
-- Three sources, in order of how much they know:
--
--   1. cast.lasted   the window this very press opened. A fact about THIS
--                    death, including "it was still up when you died".
--   2. the setting    "active for N seconds", stated by the player. Believed
--                    the moment it exists - that is the design in Auras.lua.
--   3. the measured   the longest window ever seen for this spell on this
--      store          spec. For deaths restored from disk, which have no
--                    live window behind them.
--
-- None of the three answering means a marker with no length. Never a guess.
---------------------------------------------------------------------------

function Replay.DurationOf(spellID)
    if not spellID then return nil end

    if ns.Auras and ns.Auras.ActiveStateFor then
        local ok, seconds = pcall(ns.Auras.ActiveStateFor, ns.Auras, spellID)
        if ok and type(seconds) == "number" and seconds > 0 then
            return seconds, "set"
        end
    end

    if ns.History and ns.History.MeasuredFor then
        local ok, seconds = pcall(ns.History.MeasuredFor, ns.History, spellID)
        if ok and type(seconds) == "number" and seconds > 0 then
            return seconds, "measured"
        end
    end

    -- LAST, and only last: the number written in the spell's own tooltip.
    -- The owner is right that most defensives have a fixed length and that
    -- the game states it - reading it is asking, not guessing. It comes
    -- after the three above because a tooltip says what is SUPPOSED to
    -- happen: before talents, before haste, before the hit that cut it
    -- short. See ns.SpellDuration.
    if ns.SpellDuration then
        local seconds = ns.SpellDuration(spellID)
        if seconds then return seconds, "tooltip" end
    end

    return nil
end

-- The length of one bar and where that length came from, so the tooltip can
-- say it out loud instead of leaving a person to wonder whether a bar is a
-- reading or a decoration.
function Replay.BarLength(cast)
    if not cast then return nil end
    if type(cast.lasted) == "number" and cast.lasted > 0 then
        return cast.lasted, cast.stillUp and "open" or "window"
    end
    return Replay.DurationOf(cast.spellID)
end

function Replay.LengthNote(source, seconds)
    if source == "open" then
        return "Still up when you died."
    elseif source == "window" then
        return string.format("Up for %.1fs - measured on this press.", seconds)
    elseif source == "measured" then
        return string.format("About %.1fs - the longest window measured for "
            .. "it on this spec.", seconds)
    elseif source == "set" then
        return string.format("%.0fs - the length you set for it on the Auras "
            .. "page.", seconds)
    elseif source == "tooltip" then
        return string.format("%.0fs - the length written in its own tooltip. "
            .. "Nothing has measured this one yet, so talents and haste are "
            .. "not in it.", seconds)
    end
    return "No length has been measured for this one yet, so it is a mark "
        .. "rather than a bar."
end

-- Which row each bar draws in, so that two that overlap never sit on top of
-- each other. Greedy by start time, which is optimal for intervals: put the
-- bar in the first row whose last bar had already finished.
--
-- Time here counts DOWN to the death, so a bar runs from t (its cast) to
-- t - duration (when it fell off), and "later" means a SMALLER t.
function Replay.StackRows(bars)
    local sorted = {}
    for index, bar in ipairs(bars or {}) do sorted[index] = bar end
    table.sort(sorted, function(a, b)
        if a.t ~= b.t then return a.t > b.t end
        return (a.duration or 0) > (b.duration or 0)
    end)

    local rowEnd = {}
    for _, bar in ipairs(sorted) do
        local finish = bar.t - (bar.duration or 0)
        local placed
        for row = 1, #rowEnd do
            if bar.t <= rowEnd[row] then
                rowEnd[row] = finish
                placed = row
                break
            end
        end
        if not placed then
            rowEnd[#rowEnd + 1] = finish
            placed = #rowEnd
        end
        bar.row = placed
    end
    return sorted, #rowEnd
end

-- A colour per bar, so two defensives running together are two things
-- rather than one long block. Stable within a replay: the same spell keeps
-- its colour whichever row it lands in.
local BAR_COLOURS = {
    { 0.90, 0.55, 0.20 },   -- amber
    { 0.35, 0.62, 0.85 },   -- steel blue
    { 0.55, 0.75, 0.35 },   -- moss
    { 0.72, 0.45, 0.80 },   -- violet
    { 0.85, 0.40, 0.45 },   -- rose
    { 0.40, 0.75, 0.72 },   -- teal
}

function Replay.ColourFor(index)
    return BAR_COLOURS[((index - 1) % #BAR_COLOURS) + 1]
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

-- TWO TOOLTIPS, AND THEY MUST NOT SIT ON EACH OTHER.
--
-- Owner, with a photograph of it: "im replay die tooltips vom mobs und
-- spells ueberlagern sich." Both were anchored to the same mark and both go
-- to its right, so the big enemy tip and the client's spell tooltip were
-- drawn in the same place - two readable things making one unreadable one.
--
-- When the big one is up, the small one hangs UNDER it instead. Not beside:
-- the plot is wide and the mark can be anywhere along it, so a tip that
-- grows sideways runs off the screen from half of them.
local function Tooltip(owner, item, under)
    if not GameTooltip then return end
    if under then
        GameTooltip:SetOwner(under, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("TOPLEFT", under, "BOTTOMLEFT", 0, -6)
    else
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    end
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
        -- Where the bar's length came from, said out loud. A bar whose
        -- length nobody can account for is decoration.
        GameTooltip:AddLine(Replay.LengthNote(item.source, item.duration),
            0.61, 0.64, 0.69, true)
    elseif item.who then
        GameTooltip:AddLine("from " .. item.who, 0.61, 0.64, 0.69)
        -- And what that source did to you across the whole window, since
        -- the face over the mark is now the source's and not the killer's.
        local facts = item.summary
        if facts and facts.hits > 1 then
            GameTooltip:AddLine(string.format("%d hits from it, %s in total, "
                .. "biggest %s", facts.hits, ns.ShortNumber(facts.total),
                ns.ShortNumber(facts.biggest)), 0.61, 0.64, 0.69, true)
        end
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

-- WHOSE FACE GOES OVER A MARK.
--
-- A mob is a model: a creature id into PlayerModel:SetCreature, which is
-- what MDT's enemy tooltips do with raw npc ids and what the killer
-- portrait has been doing since 4.49.0. Built only when a mark actually
-- has art behind it - a model frame is not free and most plots need a
-- handful, not twenty-eight.
local function EnsureFace(mark)
    if mark.model then return mark.model end
    -- One frame carrying a flat portrait and a model, and Death decides which
    -- of the two is on screen. Still called `model` on the mark because every
    -- position and every hover in this file already points at that name.
    mark.model = ns.Death.CreateFace(mark, AVATAR)
    return mark.model
end

local function PaintCreature(mark, art)
    if not (art and (art.creatureID or art.displayID)) then
        if mark.model then mark.model:Hide() end
        return false
    end
    -- The doors live in Death.PaintFace now. The early return above stays
    -- here, because it is this file's own rule: no art means no frame gets
    -- BUILT, and a shared painter cannot know that.
    return ns.Death.PaintFace(EnsureFace(mark), art)
end

-- A person is a portrait texture, which needs a unit token - so the name
-- is looked for among the units this client will still answer for. Outside
-- the group there is no answer and the mark keeps its name and no face,
-- which is honest: we do not know what that person looks like.
-- A PERSON'S PORTRAIT USED TO BE PAINTED HERE and nothing has called it for
-- some time - the plot draws creatures, and the one face on it belongs to
-- whatever hit you. Pulling the creature painter out into Death made the
-- dead one visible beside it, so it goes rather than being left as a
-- function somebody will one day fix a bug in.
--
-- The question itself did not disappear: the group log's detail head asks it
-- about the person who died, and Death.PaintUnitFace answers it there. This
-- copy also compared only the full name, so anybody on our own realm never
-- matched it - which is the other reason not to keep it around.

-- One mark on the plot: a column, an icon and a number for the incoming
-- side; an icon alone for a press of yours. Built once, re-pointed per
-- death, because the marks are a pool like every other list in this addon.
local function BuildMark(parent, kind)
    local C = UI.C
    local mark = CreateFrame("Frame", nil, parent)
    mark:SetSize(24, 24)

    mark.column = mark:CreateTexture(nil, "ARTWORK")
    mark.column:SetWidth(kind == "in" and 8 or 3)

    -- THE DROP LINE, for a bar under the axis. A bar three rows down starts
    -- somewhere along a plot ten seconds wide, and reading its start off
    -- the scale means sighting up an empty gap. The owner asked for the
    -- line: "auch fehlt so ein mittelstrich zur timeline, das man sieht
    -- wann die losgehen". One pixel, from the axis to the top of the bar,
    -- standing exactly on the moment it was cast.
    if kind == "press" then
        mark.drop = mark:CreateTexture(nil, "BACKGROUND")
        mark.drop:SetWidth(1)
        mark.drop:Hide()
    end

    -- No border. The icons carried one and it drew a box round every mark,
    -- which on a plot of twenty of them is twenty boxes and no picture.
    mark.icon = mark:CreateTexture(nil, "ARTWORK")
    mark.icon:SetSize(22, 22)
    mark.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    mark.value = UI.Label(mark, "", 10, C.text)
    mark.value:SetJustifyH("CENTER")
    mark.value:SetWidth(70)

    mark:EnableMouse(true)
    mark:SetScript("OnEnter", function(self)
        if not self.item then return end
        -- THE BIG ONE FIRST, whenever this mark carries a mob's face. The
        -- small tooltip answers "what was this hit"; the enemy tip answers
        -- "what is this thing" - the picture at a size you can recognise and
        -- everything it did in these seconds.
        --
        -- First because the other one is hung UNDER it, and a frame cannot
        -- be pointed at until it has been placed.
        local item = self.item
        local under
        if not item.cast and item.who then
            ns.Death.ShowEnemyTip(self, {
                who = item.who, art = item.art, summary = item.summary,
            })
            local tip = ns.Death.EnemyTipFrame()
            if tip and tip:IsShown() then under = tip end
        end
        Tooltip(self, item, under)
    end)
    mark:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
        ns.Death.HideEnemyTip()
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
    -- Red, at the owner's word. In the death window's rows the slate means
    -- "what was left of a bar you can also see the red of"; here there is
    -- no second colour beside it, so it is a health bar and health bars in
    -- this game are red.
    frame.healthFill:SetColorTexture(0.62, 0.15, 0.15, 1)

    -- The plot scrolls under the wheel. Doing so takes the view off the
    -- playhead until Restart or Stop gives it back - otherwise the next
    -- frame would drag it out from under the pointer.
    frame.health:EnableMouseWheel(true)
    local function Scroll(_, delta)
        local state = Replay.state
        if not (state and state.zoom > 1) then return end
        local visible = state.span / state.zoom
        state.following = false
        state.pan = math.max(visible / 2, math.min(state.span - visible / 2,
            (state.pan or state.now) + delta * visible * 0.25))
        Replay.Redraw()
    end
    frame.health:SetScript("OnMouseWheel", Scroll)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", Scroll)

    -----------------------------------------------------------------------
    -- DRAGGING THE PLOT ALONG. Owner, 2026-08-09: "ich haette nur gern, dass
    -- wenn ich beim replay reinzoome, die timeline mit der maus verschieben
    -- kann".
    --
    -- A pane over the plot, and it does BOTH gestures rather than stealing
    -- one: zoomed in it pans, and at zoom 1 - where there is nothing to pan
    -- to - it moves the window, which is what grabbing this area did before
    -- it existed. Taking that away to add panning would be a trade, not a
    -- feature.
    --
    -- AT THE PARENT'S OWN LEVEL, which puts it UNDER every mark: a child
    -- frame sits one level above its parent by default, so the icons keep
    -- their tooltips and this pane only ever gets the empty space between
    -- them - which is most of the plot.
    --
    -- The cursor is divided by THIS frame's effective scale, not UIParent's.
    -- The two only agree while the window is at 100%, and the size slider on
    -- this very window makes that the exception rather than the rule.
    -----------------------------------------------------------------------
    local pan = CreateFrame("Frame", nil, frame)
    pan:SetPoint("TOPLEFT", frame, "TOPLEFT", PLOT_L, -(HEALTH_Y - 20))
    pan:SetPoint("BOTTOMRIGHT", frame, "TOPLEFT", PLOT_L + PLOT_W,
        -PLOT_BOTTOM)
    pan:SetFrameLevel(frame:GetFrameLevel())
    pan:EnableMouse(true)

    local function CursorX()
        local x = GetCursorPosition()
        return x / (frame:GetEffectiveScale() or 1)
    end

    pan:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local state = Replay.state
        if not (state and state.zoom > 1) then
            -- Nothing to pan to. The gesture goes back to what it was.
            self.moving = true
            frame:StartMoving()
            return
        end
        state.following = false
        self.grabAt = CursorX()
        self.grabPan = state.pan or state.now
        self.dragging = true
    end)

    local function StopPan(self)
        if self.moving then
            frame:StopMovingOrSizing()
            self.moving = nil
        end
        self.dragging = nil
    end
    pan:SetScript("OnMouseUp", StopPan)
    -- The button can be released outside the pane - over the buttons, off
    -- the window, anywhere. Without this the plot keeps following a cursor
    -- nobody is pressing any more.
    pan:SetScript("OnHide", StopPan)

    pan:SetScript("OnUpdate", function(self)
        if not self.dragging then return end
        local state = Replay.state
        if not (state and state.zoom > 1) then
            StopPan(self)
            return
        end
        if not IsMouseButtonDown("LeftButton") then
            StopPan(self)
            return
        end

        local visible = state.span / state.zoom
        -- Dragging RIGHT pulls the plot right, which brings EARLIER seconds
        -- into view - the axis runs oldest on the left. The content follows
        -- the hand; a plot that moves the other way feels like a scrollbar
        -- nailed to the wrong end.
        local moved = (CursorX() - (self.grabAt or 0)) / PLOT_W * visible
        state.pan = math.max(visible / 2, math.min(state.span - visible / 2,
            (self.grabPan or state.now) + moved))
        Replay.Redraw()
    end)

    frame.pan = pan

    frame.healthText = UI.Label(frame.health, "", 11, C.text)
    frame.healthText:SetPoint("LEFT", frame.health, "LEFT", 6, 0)

    frame.clock = UI.Label(frame.health, "", 11, C.text)
    frame.clock:SetPoint("RIGHT", frame.health, "RIGHT", -6, 0)
    frame.clock:SetJustifyH("RIGHT")

    -- The axis. Three pixels rather than one: it is the spine of the whole
    -- picture and a hairline read as a scratch between two empty halves.
    local axis = frame:CreateTexture(nil, "ARTWORK")
    axis:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    axis:SetPoint("TOPLEFT", frame, "TOPLEFT", PLOT_L, -AXIS_Y)
    axis:SetSize(PLOT_W, 3)

    -- The whole seconds, written ON the line - the owner asked for it and
    -- it is right: under the line they belong to nothing, on it they are
    -- the line's own scale. Each carries a patch of the window's own
    -- background so the axis does not run through the letters.
    frame.ticks = {}
    for i = 1, 13 do
        local plate = frame:CreateTexture(nil, "OVERLAY")
        plate:SetColorTexture(C.windowBg[1], C.windowBg[2], C.windowBg[3], 1)
        plate:SetSize(34, 13)
        local label = UI.Label(frame, "", 10, C.textDim)
        label:SetJustifyH("CENTER")
        label:SetWidth(34)
        frame.ticks[i] = { plate = plate, label = label }
    end

    -- And the half seconds, as marks with no writing: they say how fast
    -- the story is running without adding a second column of numbers.
    frame.halfTicks = {}
    for i = 1, 26 do
        local tick = frame:CreateTexture(nil, "ARTWORK")
        tick:SetColorTexture(C.separator[1], C.separator[2], C.separator[3], 1)
        tick:SetSize(1, 7)
        tick:Hide()
        frame.halfTicks[i] = tick
    end

    frame.playhead = frame:CreateTexture(nil, "OVERLAY")
    frame.playhead:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9)
    frame.playhead:SetWidth(1)
    frame.playhead:SetPoint("TOP", frame, "TOPLEFT", PLOT_L, -(HEALTH_Y - 4))
    frame.playhead:SetHeight(PLOT_BOTTOM - HEALTH_Y)

    -- Two lanes: what hit you above the axis, and what you pressed below it.
    frame.incoming, frame.outgoing, frame.casts = {}, {}, {}
    for i = 1, MARKS_IN do frame.incoming[i] = BuildMark(frame, "in") end
    for i = 1, MARKS_OUT do frame.outgoing[i] = BuildMark(frame, "press") end
    for i = 1, MARKS_CAST do frame.casts[i] = BuildMark(frame, "press") end

    frame.laneIn = UI.Eyebrow(frame, "Damage on you")
    frame.laneIn:SetPoint("TOPLEFT", frame, "TOPLEFT", PLOT_L, -LANE_IN_Y)
    -- No caption over the press lanes. The owner: "what you pressed als
    -- text kann eigentlich raus, das sieht jeder" - a row of your own spell
    -- icons under a time axis needs no label, and the legend at the foot of
    -- the window already names the defensives among them.

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
    -- Sized to its own contents: the label was floating eighty pixels away
    -- from the control it names, because the row was wider than either.
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
    UI.FitRow(speedRow)
    frame.speedRow = speedRow

    -- ZOOM. Six presses inside two tenths of a second cannot be drawn apart
    -- at any icon size; the plot has to be able to show less time instead.
    local zoomRow = UI.Row(frame, "Zoom", { controlWidth = 116 })
    zoomRow:SetPoint("LEFT", speedRow, "RIGHT", 10, 0)
    zoomRow.rule:Hide()
    UI.Slider(zoomRow, {
        get = function() return (Replay.state and Replay.state.zoom) or 1 end,
        set = function(value)
            if not Replay.state then return end
            Replay.state.zoom = math.max(1, math.min(ZOOM_MAX, value))
            Replay.Redraw()
        end,
        min = 1, max = ZOOM_MAX, step = 0.5,
        silent = true,
        format = function(v) return Replay.SpeedLabel(v) end,
    })
    UI.FitRow(zoomRow)
    frame.zoomRow = zoomRow

    -- THE ONE SENTENCE THIS WINDOW EXISTS TO MAKE UNNECESSARY, said anyway.
    -- The spells in it are spells, so they are drawn the way this game draws
    -- spells: an icon in front of the name and a tooltip on hover. The
    -- owner's rule - "immer wenn eine faehigkeit einen tooltip und icon hat,
    -- muss das angezeigt werden. egal bei was".
    frame.legend = UI.Label(frame, "", 11, C.textFaint)
    frame.legend:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PLOT_L, 46)
    frame.legend:SetJustifyH("LEFT")
    frame.legend:SetWordWrap(false)

    -- The same strip the death window's footer uses. One implementation of
    -- "a list of spells", or the two would drift into two answers to the
    -- same question.
    frame.chips = UI.SpellChips(frame, {
        width = PLOT_W - 140, max = 10, size = 11,
    })
    frame.chips:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PLOT_L, 46)

    -- NO "CLOSE" BUTTON here either: the X closes it, and the two sliders
    -- beside it needed the room. Both of them were unreadable - "1x" twice
    -- with no way to tell speed from zoom, because each slider was drawing
    -- over its own label. See UI.FitRow.
end

-- The legend, as a label and a row of spell chips beside it. Names alone
-- were there before and they read as a list of words; this reads as the
-- abilities they are.
local function PaintLegend(analysis)
    local used = (analysis and analysis.defensivesUsed) or {}

    frame.legend:SetText(#used > 0 and "Defensives used:"
        or "|cffe0a05eNo defensive was used in these seconds.|r")

    -- Measured, not guessed: the caption's own width decides where the
    -- chips start, so a long caption in another language cannot run under
    -- the first icon.
    local _, dropped = frame.chips.Paint(used)
    frame.chips:ClearAllPoints()
    frame.chips:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT",
        PLOT_L + (#used > 0 and ((frame.legend:GetStringWidth() or 90) + 12)
            or 0), 40)

    if dropped > 0 then
        frame.legend:SetText(string.format("Defensives used: (+%d more)",
            dropped))
    end
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

-- Places every mark for one death. Positions do not change while it plays;
-- only what is lit does, which is what makes the playhead read as time
-- passing rather than as things appearing out of nowhere.
local function Place(snapshot, from, to)
    local events = ns.Death.RecentEvents(snapshot.events, ns.Death.WINDOW)
    local maxHP = snapshot.maxHP

    -- WHAT CAME IN, above the axis. Heals are skipped rather than filtered
    -- out of the list: the list is Death's, several things read it, and
    -- rebuilding it here to leave one kind out would be a second version of
    -- the story that has to be kept in step with the first.
    local slot = 0
    for _, ev in ipairs(events) do
        if not ev.heal then
            slot = slot + 1
            if slot <= MARKS_IN then
                local mark = frame.incoming[slot]
                mark.item = ev
                if not Replay.Visible(ev.t, from, to) then
                    mark:Hide()
                else
                    local height = Replay.ColumnHeight(ev.amount, maxHP)
                    local x = PLOT_L + Replay.Fraction(ev.t, from, to) * PLOT_W

                    mark:ClearAllPoints()
                    -- Clear of the axis, so the seconds written on the line
                    -- stay readable under twenty columns.
                    mark:SetPoint("BOTTOM", frame, "TOPLEFT", x,
                        -(AXIS_Y - COLUMN_LIFT))
                    mark:SetSize(24, height + 40 + AVATAR)

                    mark.column:ClearAllPoints()
                    mark.column:SetPoint("BOTTOM", mark, "BOTTOM", 0, 0)
                    mark.column:SetHeight(height)
                    mark.column:SetColorTexture(0.55, 0.11, 0.11, 0.95)

                    mark.icon:ClearAllPoints()
                    mark.icon:SetPoint("BOTTOM", mark.column, "TOP", 0, 2)
                    mark.icon:SetTexture(
                        (ev.spellID and ns.SpellTexture(ev.spellID)) or 135274)

                    mark.value:ClearAllPoints()
                    mark.value:SetPoint("BOTTOM", mark.icon, "TOP", 0, 2)
                    mark.value:SetText("|cffe06c5e-"
                        .. ns.ShortNumber(ev.amount) .. "|r")

                    -- WHO HIT YOU, over the hit itself. The killer's face
                    -- used to sit alone in the corner of the lane; with ten
                    -- mobs on you that face answers for all of them and
                    -- therefore for none of them.
                    if PaintCreature(mark, ev.art) then
                        mark.model:ClearAllPoints()
                        mark.model:SetPoint("BOTTOM", mark.value, "TOP", 0, 2)
                    end
                    -- Summed once per source and kept on the event: the
                    -- plot is laid out again on every scroll, and this
                    -- walks the whole list.
                    if ev.who and not ev.summary then
                        ev.summary = Replay.SourceSummary(events, ev.who)
                    end
                    mark:Show()
                end
            end
        end
    end
    for i = slot + 1, MARKS_IN do
        frame.incoming[i].item = nil
        frame.incoming[i]:Hide()
    end

    -- YOUR PRESSES, AS BARS. Each starts where you cast it and runs for as
    -- long as it is up, so an overlap is two bars on two rows rather than
    -- two icons on top of each other. The icon rides the bar's left end.
    -- TWO ROWS, NOT ONE. The owner: "normale spells brauchen eigentlich
    -- keinen balken, nur def cds die man einstellt. das verwirrt nur. ich
    -- wuerde auch normale spells in eine eigene reihe legen."
    --
    -- He is right on both counts. A bar means "this was up for this long",
    -- and a Death Strike has nothing that is up - drawing it as a bar off
    -- its tooltip's number invents a state that does not exist. So the
    -- rotation goes in a row of its own, as icons: moments, which is what
    -- they are. Only the defensives picked on the Deaths page get bars.
    local colourOf, nextColour = {}, 0
    local bars, others = {}, {}
    for _, cast in ipairs(snapshot.casts or {}) do
        if cast.defensive then
            -- The window this press opened, first. See Replay.BarLength.
            local duration, source = Replay.BarLength(cast)
            bars[#bars + 1] = {
                t = cast.t, name = cast.name, spellID = cast.spellID,
                cast = true, defensive = true,
                duration = duration, source = source,
            }
        else
            others[#others + 1] = {
                t = cast.t, name = cast.name, spellID = cast.spellID,
                cast = true,
            }
        end
    end

    -- The rotation, as icons on their own line right under the axis, each
    -- on a hairline that reaches up to it - "man sieht wann die losgehen".
    slot = 0
    for _, item in ipairs(others) do
        slot = slot + 1
        if slot <= MARKS_CAST then
            local mark = frame.casts[slot]
            mark.item = item
            if not Replay.Visible(item.t, from, to) then
                mark:Hide()
            else
                local x = PLOT_L + Replay.Fraction(item.t, from, to) * PLOT_W
                mark:ClearAllPoints()
                mark:SetPoint("TOP", frame, "TOPLEFT", x, -LANE_CAST_Y)
                mark:SetSize(20, 27)

                mark.column:ClearAllPoints()
                mark.column:SetPoint("TOP", mark, "TOP", 0, 0)
                mark.column:SetWidth(1)
                mark.column:SetHeight(7)
                mark.column:SetColorTexture(0.45, 0.49, 0.55, 0.9)

                mark.icon:ClearAllPoints()
                mark.icon:SetSize(18, 18)
                mark.icon:SetPoint("TOP", mark.column, "BOTTOM", 0, -1)
                mark.icon:SetTexture(item.spellID
                    and ns.SpellTexture(item.spellID))
                mark.value:SetText("")
                mark:Show()
            end
        end
    end
    for i = slot + 1, MARKS_CAST do
        frame.casts[i].item = nil
        frame.casts[i]:Hide()
    end

    local stacked = Replay.StackRows(bars)

    slot = 0
    for _, bar in ipairs(stacked) do
        slot = slot + 1
        if slot <= MARKS_OUT then
            local mark = frame.outgoing[slot]
            mark.item = bar

            -- A bar is on screen when ANY part of it is: it may start
            -- before the left edge and still be running under the hit you
            -- are looking at, which is exactly the case worth seeing.
            local ended = bar.t - (bar.duration or 0)
            if bar.t < to or ended > from then
                mark:Hide()
            else
                local x = PLOT_L
                    + math.max(0, Replay.Fraction(bar.t, from, to)) * PLOT_W
                -- A press whose length nobody has measured gets a marker,
                -- not an invented bar: this addon does not guess durations.
                local ends = bar.duration
                    and (PLOT_L + math.min(1,
                        Replay.Fraction(math.max(0, ended), from, to)) * PLOT_W)
                    or (x + 4)
                local row = math.min(bar.row or 1, BAR_ROWS)
                local top = LANE_OUT_Y + (row - 1) * (BAR_H + BAR_GAP)

                mark:ClearAllPoints()
                mark:SetPoint("TOPLEFT", frame, "TOPLEFT", x - 9, -top)
                mark:SetSize(math.max(BAR_H, (ends - x) + 9), BAR_H)

                -- Its own colour, kept by spell so the same defensive is
                -- the same colour wherever it lands.
                local key = bar.spellID or bar.name or slot
                if not colourOf[key] then
                    nextColour = nextColour + 1
                    colourOf[key] = Replay.ColourFor(nextColour)
                end
                local colour = colourOf[key]

                mark.column:ClearAllPoints()
                mark.column:SetPoint("TOPLEFT", mark, "TOPLEFT", 9, 0)
                mark.column:SetPoint("BOTTOMRIGHT", mark, "BOTTOMRIGHT", 0, 0)
                mark.column:SetColorTexture(colour[1], colour[2], colour[3], 0.85)

                mark.icon:ClearAllPoints()
                mark.icon:SetPoint("LEFT", mark, "LEFT", 0, 0)
                mark.icon:SetSize(BAR_H, BAR_H)
                mark.icon:SetTexture(bar.spellID
                    and ns.SpellTexture(bar.spellID))
                mark.value:SetText("")

                -- The drop line: from the axis down to this bar's own row,
                -- standing on the moment it was cast. Only for a bar that
                -- starts inside the view - one clamped to the left edge
                -- started off screen, and a line there would point at a
                -- moment that is not under it.
                if mark.drop then
                    local started = Replay.Visible(bar.t, from, to)
                    if started then
                        mark.drop:ClearAllPoints()
                        mark.drop:SetPoint("BOTTOMLEFT", mark, "TOPLEFT", 9, 0)
                        mark.drop:SetHeight(math.max(1, top - AXIS_Y - 3))
                        mark.drop:SetColorTexture(colour[1], colour[2],
                            colour[3], 0.55)
                    end
                    mark.drop:SetShown(started)
                end
                mark:Show()
            end
        end
    end
    for i = slot + 1, MARKS_OUT do
        frame.outgoing[i].item = nil
        frame.outgoing[i]:Hide()
    end

    -- The scale, written ON the line. The step follows the ZOOM: showing
    -- twelve seconds at once wants a label every two, showing one and a
    -- half wants one every half, or the axis is either crowded or bare.
    local shown = from - to
    local step = 1
    if shown > 12 then step = 2
    elseif shown <= 3 then step = 0.5
    end

    local slotIndex = 0
    for at = math.floor(to / step) * step, from + step, step do
        if at >= to - 0.001 and at <= from + 0.001 then
            slotIndex = slotIndex + 1
            local entry = frame.ticks[slotIndex]
            if entry then
                local x = PLOT_L + Replay.Fraction(at, from, to) * PLOT_W
                entry.plate:ClearAllPoints()
                entry.plate:SetPoint("CENTER", frame, "TOPLEFT", x,
                    -(AXIS_Y + 1))
                entry.label:ClearAllPoints()
                entry.label:SetPoint("CENTER", frame, "TOPLEFT", x,
                    -(AXIS_Y + 1))
                entry.label:SetText(at < 0.001 and "death"
                    or (step < 1 and string.format("%.1fs", at)
                        or string.format("%ds", at)))
                entry.plate:SetWidth(at < 0.001 and 40 or 30)
                entry.plate:Show()
                entry.label:Show()
            end
        end
    end
    for i = slotIndex + 1, #frame.ticks do
        frame.ticks[i].plate:Hide()
        frame.ticks[i].label:Hide()
    end

    -- Half a step between them, unwritten: they say how fast the story is
    -- running without adding a second column of numbers.
    local half = 0
    for at = math.floor(to / step) * step + step / 2, from, step do
        if at >= to and at <= from then
            half = half + 1
            local tick = frame.halfTicks[half]
            if tick then
                local x = PLOT_L + Replay.Fraction(at, from, to) * PLOT_W
                tick:ClearAllPoints()
                tick:SetPoint("TOP", frame, "TOPLEFT", x, -(AXIS_Y - 2))
                tick:Show()
            end
        end
    end
    for i = half + 1, #frame.halfTicks do frame.halfTicks[i]:Hide() end
end

-- What is lit and what is waiting, for the clock's current position.
local function Paint(now)
    local state = Replay.state
    local from, to = state.viewFrom or state.span, state.viewTo or 0

    for _, lane in ipairs({ frame.incoming, frame.outgoing,
        frame.casts }) do
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

    -- The playhead only exists where the view reaches; zoomed in and
    -- scrolled away from it, it is off the plot and must not be drawn
    -- pinned to an edge it is not at.
    if Replay.Visible(now, from, to) then
        frame.playhead:ClearAllPoints()
        frame.playhead:SetPoint("TOP", frame, "TOPLEFT",
            PLOT_L + Replay.Fraction(now, from, to) * PLOT_W, -(HEALTH_Y - 4))
        frame.playhead:Show()
    else
        frame.playhead:Hide()
    end
end

-- Recomputes the view and lays every mark out again. Called when the zoom
-- or the scroll changes, and every frame while a zoomed-in replay is
-- following the playhead. At zoom 1 the view never moves, so the normal
-- case costs one comparison rather than sixty-eight SetPoints.
function Replay.Redraw()
    local state = Replay.state
    if not (state and frame) then return end

    local centre = state.following and state.now or state.pan
    local from, to = Replay.View(state.span, state.zoom, centre)
    if state.viewFrom == from and state.viewTo == to then return end

    state.viewFrom, state.viewTo = from, to
    Place(state.snapshot, from, to)
    Paint(math.max(0, state.now))
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
        snapshot = snapshot,
        events = events,
        maxHP = snapshot.maxHP,
        span = span,
        now = span,
        paused = false,
        speed = (ns.db and ns.db.death and ns.db.death.replaySpeed) or 1,
        -- The zoom starts out showing everything, and the view FOLLOWS the
        -- playhead until the wheel is used - after which it stays where it
        -- was put, until Restart or Stop hands it back.
        zoom = 1,
        following = true,
        pan = nil,
    }

    -- The mob and the place in orange, the addon's mark for a word that
    -- answers: every face on the plot below opens a tip for that same mob.
    frame.title:SetText(snapshot.killer
        and ("Replay - killed by " .. ns.UI.HotText(snapshot.killer))
        or "Replay")
    frame.sub:SetText((snapshot.when or "")
        .. (snapshot.where and ("  -  " .. ns.UI.HotText(snapshot.where)) or ""))

    -- The single portrait that used to sit in the corner of the damage lane
    -- is gone: every hit carries its own face now. One face for a death
    -- with twenty mobs in it answered for all of them, which is the owner's
    -- objection and it is right.
    PaintLegend(snapshot.analysis)

    frame.playButton.label:SetText("Pause")
    frame.speedRow.Refresh()
    frame.zoomRow.Refresh()

    Replay.state.viewFrom, Replay.state.viewTo = span, 0
    Place(snapshot, span, 0)
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
        -- Zoomed in, the view walks with the playhead; at zoom 1 Redraw
        -- finds nothing changed and returns without touching a frame.
        if state.zoom > 1 and state.following then Replay.Redraw() end
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
