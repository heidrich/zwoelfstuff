---------------------------------------------------------------------------
-- Replay.lua - the death, played back on a timeline
--
-- The owner's ask, in their words: "dann würde ich das als extra fenster
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
-- THE PANEL DOWN THE LEFT, same as the death window's: what you pressed,
-- what you still had, what else you cast, as rows with icons (owner,
-- 2026-08-16: "fuege auch hier links ein neues panel ein, mit auflistung
-- welche def cds man hatte und was geused wurde (scrollbar)"). It took the
-- place of the "Defensives used:" chip strip under the plot. The plot
-- keeps its width and moves right by the panel and its gutters; every x
-- in this file is measured from PLOT_L, so nothing else had to move.
local PANEL_W = 186
local PANEL_X = 16
local PLOT_R = 30
local PLOT_L = PANEL_X + PANEL_W + 16 + PLOT_R
local FRAME_W = PLOT_L + 720 + PLOT_R
local PLOT_W = FRAME_W - PLOT_L - PLOT_R
-- What the window keeps under the plot for the transport and the legend.
-- The HEIGHT itself is worked out below, once the lanes have said how much
-- room they need: it was a typed 476 and the third press lane would have
-- grown straight through the bottom of the window without moving it.
local FOOT_H = 84
local AXIS_Y = 268          -- from the top of the frame
local COLUMN_MAX = 70       -- tallest an incoming column may draw
local MARKS_IN, MARKS_OUT, MARKS_CAST = 28, 20, 24
local MARKS_CD = 12

-- AND, ON A FIGHT, WHERE YOU WENT DOWN. A death replay ends ON the killing
-- blow and never needed one of these; a pull can hold several, and "when did
-- it go wrong" is the first question anybody opens this window with. Eight is
-- more deaths than a pull worth replaying has in it.
local MARKS_FALL = 8

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

-- How tall a press bar is, and the MOST rows a lane may ever hold.
--
-- Owner, 2026-08-31, in front of a plot with bars drawn through each other:
-- "hier ueberlagern noch zu viele cooldowns. das muesste dynamisch besser
-- sein."
--
-- He is right and the cause was the word "most". These were HEIGHTS: four
-- rows for the defensives whether the fight needed one or nine, and
-- everything past the fourth clamped onto the fourth - drawn on top of what
-- was already there, which is the one thing the stacking exists to prevent.
-- A cap that silently overdraws is worse than no cap: the plot looks busy
-- and two answers occupy one line.
--
-- So they are CEILINGS now and the lane is as tall as the fight needs. An
-- empty row costs nothing when the height follows the content, which is why
-- these can be generous - and a fight that really does chain nine
-- defensives gets nine lines instead of a smear.
local BAR_H, BAR_GAP = 18, 2
local BAR_ROWS = 8          -- defensives: the ceiling, not the height
local CD_ROWS = 6           -- cooldowns

-- The lanes and where each starts, measured from the top of the frame.
local HEALTH_Y = 84         -- your own health bar
local LANE_IN_Y = 112       -- "what came in", growing UP to the axis
local LANE_CAST_Y = 272     -- everything else you cast, as icons only
local LANE_CD_Y = 312       -- your COOLDOWNS, as bars, under those

-- AND THE DEFENSIVES UNDER THOSE, at a distance rather than at a number.
--
-- Owner, 2026-08-31: "auf dem Zeitstrahl zeigen wir die cooldowns unterhalb
-- den spells an, darunter die def cds." Three lanes in that order, and the
-- order is the whole point: what you press to keep going, then what you
-- press to win, then what you press to survive. Reading down the plot is
-- reading from routine to desperate.
--
-- WHERE IT STARTS IS A QUESTION, NOT A NUMBER - see Replay.LaneOut. It
-- depends on how many rows the cooldowns above it turned out to need, and
-- that is a fact about the fight in the window rather than about the file.

-- THERE WAS A FOURTH LANE, "Healing on you", and it went in 4.81.0. Owner:
-- "bitte noch im death log replay der healing on you bereich rausnehmen." It
-- held a fifth of the window's height and, on the death they photographed,
-- nothing at all - which is the ordinary case for the deaths worth opening
-- this window over. The heals are still RECORDED and the death window still
-- counts them; what went is the empty band under the plot.

-- WHERE THE PLOT ENDS is a question too - Replay.PlotFloor. The window is
-- exactly as tall as what is drawn on it, so both bar lanes moving under
-- their own content move this, and the frame's height with it.

-- THE DAMAGE GRAPH, under the defensives lane. Owner, 2026-08-16: "koennte
-- man hier unterhalb der spell leiste einen graphen einbauen der den dmg
-- income zeigt? ggf als haken zum aktivieren?" - and then "bau das mal".
-- Incoming damage over the same seconds as the axis, in as many columns
-- as fit at a readable width, red for what landed and a lighter cap for
-- the overkill; it scrolls and zooms with the plot because it is placed by
-- the same view. A switch above Play shows or hides it, remembered in
-- the profile, and the window is only as tall as what is on it.
local GRAPH_H = 56
local GRAPH_COLS = 72                    -- 10px each across the 720 plot
local GRAPH_BLOCK = 10 + GRAPH_H + 8      -- what the graph adds to the window

-- AND FOR A FIGHT IT SITS ABOVE THE AXIS, not under the presses.
--
-- Owner, 2026-08-31: "health lost sollte ueber meinen spell sein, nicht
-- darunter." He is right, and it is not a preference: everything ABOVE the
-- axis is what happened TO you and everything below it is what you did about
-- it. That is the whole grammar of this window, and a band of incoming
-- damage parked under the presses reads as something you cast.
--
-- On a FALL the band stays where it was - there the lane above the axis is
-- already full of the recap's own columns, and the graph was added under the
-- plot precisely so it would not fight them for the space.
-- WHAT WAS ON YOU, as bars, between the caption and the health band.
--
-- Owner, 2026-08-31: "oder wann ich debuffs oder so bekommen habe?" - and
-- they are BARS rather than icons for the same reason the defensives below
-- the axis are: a debuff is a stretch, not a moment, and how long you wore
-- it is the whole question. Above the axis, because it was done to you.
local DEBUFF_Y = 146
local DEBUFF_H, DEBUFF_GAP = 18, 2
-- TWO CEILINGS, because this lane's room depends on what is under it. With
-- the recap's columns in play they grow up towards it and it keeps to
-- three; with nothing under it - which is every pull nobody died in - it
-- may use the room the columns would have wanted. See Replay.DebuffCap.
local DEBUFF_ROWS = 3
local DEBUFF_ROOM = 5
local MARKS_WORN = 12

-- One row in every lane: the smallest this window can be, and what it is
-- built at before any fight has said how much room it wants.
local EMPTY_LANES = { cd = 1, def = 1, worn = 1 }

-- Shorter than it was, to make room for them: the band is a shape, and the
-- shape survives being half as tall. Derived from the lane above it rather
-- than typed, so moving one moves the other and they cannot overlap.
local GRAPH_UP_H = 48

-- WHAT IS LEFT ABOVE THE AXIS WHEN THE HEALTH BLOCK IS PUT AWAY, and where
-- it goes.
--
-- Owner, 2026-08-31: "damage on you gehoert zu health." He is right, and it
-- takes the incoming lane with it: the caption, its note and the columns
-- under it are all one answer to "what was being done to you", and half of
-- that answer folded away is not tidier, it is confusing.
--
-- Which leaves the debuffs alone up there - so they come DOWN into the room
-- that opened up, rather than staying where they were with fifty pixels of
-- nothing between them and the line. Both numbers are worked out from the
-- axis and the lane's own height - see Replay.DebuffTop and the lift in
-- Replay.Metrics, which is the distance between the two. The bars land on
-- the health bar's own mark and the axis just under them, whether the lane
-- turned out to need one row or five.
-- Both are worked out in Replay.DebuffTop and Replay.Metrics, from however
-- many rows this fight's debuffs actually needed.

-- WHAT THE TWO HEADER SWITCHES TAKE, and what the title gives up for them.
--
-- A row is its label plus the control - see UI.FitRow - and both labels are
-- one short word, so one width covers both. Written once because the title's
-- right edge and the switches' own anchor are the SAME edge: two numbers
-- would be two places for it to be got wrong, and the symptom would be a
-- mob's name running under a switch on exactly the fights whose names are
-- long.
local SWITCH_W, SWITCH_GAP = 92, 12
local SWITCH_BAND = SWITCH_W * 2 + SWITCH_GAP

-- Half a second before the first thing happens, so the eye is on the plot
-- when it starts moving rather than arriving after it.
local LEAD = 0.5
local SPEED_MIN, SPEED_MAX, SPEED_STEP = 0.25, 3, 0.25
-- HOW FAR IN A PLOT MAY BE ZOOMED, and it depends on how long the plot is.
--
-- Owner, 2026-08-30: "im combat log brauchen wir einen zoom der bis locker
-- 30 gehen muss."
--
-- Eight was written for a DEATH and is right for one: ten seconds shown a
-- second and a quarter at a time is finer than any press sequence a person
-- makes. A pull is minutes, and eight times into four of them still leaves
-- half a minute on screen - which is the width at which two presses in the
-- same second are the same pixel, and telling those apart is the whole
-- reason anybody drags this slider.
--
-- So the ceiling follows the SPAN rather than the file: far enough in to
-- bring the view down to ONE second, which is where a single press fills
-- the plot and there is nothing left to separate. Any fight of half a
-- minute or more therefore reaches thirty, which is what he asked for, and
-- a four-minute one is capped so the slider keeps a usable travel.
--
-- Never below the eight a death always had: a fight can be shorter than
-- eight seconds and the slider must not shrink to nothing on it.
local ZOOM_MIN_MAX, ZOOM_CEILING, ZOOM_CLOSEST = 8, 60, 1

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
-- The owner's problem, in their words: six spells inside two tenths of a
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

function Replay.ZoomMax(span)
    if type(span) ~= "number" or span <= 0 then return ZOOM_MIN_MAX end
    return math.max(ZOOM_MIN_MAX,
        math.min(ZOOM_CEILING, math.floor(span / ZOOM_CLOSEST + 0.5)))
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
-- INCOMING DAMAGE, BUCKETED ACROSS THE VISIBLE BAND. Column 1 is the
-- oldest moment shown (`from`, the left edge), column `count` the newest
-- (`to`). Each column carries what landed in its slice, its overkill on
-- top of that, and the newest edge of its slice - so Paint can dim the
-- columns the playhead has not reached. Heals are not damage and are
-- skipped. Returns the columns and the tallest one, for the scale.
function Replay.Buckets(events, from, to, count)
    from = from or 1
    to = to or 0
    count = math.max(1, count or 1)
    local width = (from - to) / count
    local out, peak = {}, 0
    for index = 1, count do
        out[index] = { damage = 0, overkill = 0,
            t = from - (index - 1) * width }
    end
    if width <= 0 then return out, 0 end
    for _, ev in ipairs(events or {}) do
        if not ev.heal and (ev.amount or 0) > 0 then
            local t = ev.t or 0
            -- Which column: 0 at the left edge, count-1 at the right. The
            -- death itself (t = 0 = `to`) lands in the last column.
            local index = math.floor((from - t) / width) + 1
            -- The newest edge itself belongs to the last column, not to a
            -- column past it: t = `to` is exactly the death.
            if t <= to + 0.0001 then index = count end
            if index >= 1 and index <= count then
                local bucket = out[index]
                bucket.damage = bucket.damage + ev.amount
                bucket.overkill = bucket.overkill + (ev.overkill or 0)
                if bucket.damage > peak then peak = bucket.damage end
            end
        end
    end
    return out, peak
end

-- The moment under a fraction of the plot's width - the inverse of
-- Fraction, clamped to the band on screen. 0 is the left edge (`from`,
-- the oldest moment shown), 1 the right edge (`to`).
function Replay.Scrub(fraction, from, to)
    from = from or 1
    to = to or 0
    fraction = math.max(0, math.min(1, fraction or 0))
    return from - fraction * (from - to)
end

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
-- The owner asked for it and they are right: an icon says "you pressed it" and
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
    if item.fell then
        GameTooltip:AddLine("You went down here", 0.86, 0.42, 0.42)
    end
    if item.worn then
        GameTooltip:AddLine(item.stillOn
            and "Put on you - and still on you when it ended"
            or string.format("Put on you - you wore it for %.1fs",
                item.duration or 0), 0.80, 0.46, 0.72)
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
    -- Two above the window, so a mark is over the scrub surface (one
    -- above) and keeps its own tooltip and click. Left to the default the
    -- two sat at the same level and which one got the mouse was whichever
    -- had been created later.
    mark:SetFrameLevel(parent:GetFrameLevel() + 2)

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

-- Written further down; the scrub surface built above needs to call them.
local Paint, Place

local function BuildWindow()
    UI = ns.UI
    local C = UI.C

    frame = CreateFrame("Frame", "ZwoelfStuffDeathReplay", UIParent)
    -- The smallest this window can be. Relayout gives it the height the
    -- fight in it actually needs, on every open and on every switch.
    frame:SetSize(FRAME_W, Replay.Metrics(true, false, EMPTY_LANES).height)
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

    -- WHAT THE WHOLE PLOT HANGS FROM, and the only thing that moves when
    -- the health block is put away.
    --
    -- Not a container - a REFERENCE. Everything in the plot stays a child
    -- of the window and keeps the draw order it had; only the point each
    -- one measures from is this frame rather than the window, so one
    -- SetPoint here takes the axis, the lanes, the ticks, the band and the
    -- playhead with it. Reparenting them would have moved them too, and
    -- would also have lifted every one of them above the window's own
    -- layers on the way.
    frame.plot = CreateFrame("Frame", nil, frame)
    frame.plot:SetSize(1, 1)
    frame.plot:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)

    -- A rich line, not a label: the killer's face in front of its name and
    -- the enemy tip on both, as every other place the addon names a mob
    -- (owner, 2026-08-16: "vor dem gegner namen fehlt noch avatar und
    -- hover ... bei replay").
    frame.title = ns.Death.BuildRichLine(frame, 15)
    -- THE TITLE STOPS SHORT OF THE TWO SWITCHES. Owner, 2026-08-30: "pack
    -- die 2 buttons nach oben in den header." They stood over Play, in the
    -- bottom-left corner - which is inside the plot, so a bar that ran to
    -- the left edge was drawn across them. Up here they are beside the
    -- title, out of the picture entirely, and the plot has its corner back.
    --
    -- SWITCH_BAND is what they take, so this edge and their own anchor are
    -- one number rather than two that drift apart.
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", PLOT_L, -14)
    frame.title:SetPoint("RIGHT", frame, "RIGHT", -(44 + SWITCH_BAND), 0)

    frame.sub = UI.Label(frame, "", 11, C.textFaint)
    frame.sub:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -3)
    -- The sub-line stops at the same edge. It carries a place and a length
    -- and would otherwise run under them.
    frame.sub:SetPoint("RIGHT", frame, "RIGHT", -(44 + SWITCH_BAND), 0)
    frame.sub:SetJustifyH("LEFT")

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

    -- THE SCRUB SURFACE. Left button held over the plot moves the
    -- PLAYHEAD - the yellow line - to wherever the mouse is, and keeps
    -- moving it while the button is down. Owner, 2026-08-16: "es waere
    -- intuitiver wenn ich es mit linker maustaste gedrueckt halte ziehen
    -- kann. es waere auch gut, wenn man dann den gelben strich zieht.
    -- nicht einfach nur die bar." So the drag is a scrub, not a pan: the
    -- line goes where the hand goes, the replay pauses under it, and when
    -- zoomed in the view follows the line - which IS the band moving. The
    -- wheel still pans the view on its own.
    --
    -- ONE ABOVE THE WINDOW. It used to sit at the window's own level, and
    -- the window is registered for drag: which of the two got a left
    -- button was whichever had been created later, and it was the window
    -- - the drag moved the whole replay across the screen instead of
    -- doing anything to the plot. The marks sit one higher still, so
    -- their tooltips and clicks are untouched.
    local scrub = CreateFrame("Frame", nil, frame)
    scrub:SetPoint("TOPLEFT", frame.plot, "TOPLEFT", PLOT_L, -(HEALTH_Y - 20))
    scrub:SetPoint("BOTTOMRIGHT", frame.plot, "TOPLEFT", PLOT_L + PLOT_W,
        -Replay.PlotFloor(EMPTY_LANES))
    scrub:SetFrameLevel(frame:GetFrameLevel() + 1)
    scrub:EnableMouse(true)

    local function CursorX()
        local x = GetCursorPosition()
        return x / (frame:GetEffectiveScale() or 1)
    end

    -- Where the mouse is, as a moment on the plot: the inverse of the
    -- Fraction the marks are placed by, clamped to the visible band.
    local function MomentUnderCursor()
        local state = Replay.state
        if not state then return nil end
        local from, to = state.viewFrom or state.span, state.viewTo or 0
        local left = frame:GetLeft() or 0
        local frac = (CursorX() - left - PLOT_L) / PLOT_W
        return Replay.Scrub(frac, from, to)
    end

    scrub:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local state = Replay.state
        if not state then return end
        state.paused = true
        state.following = true
        frame.playButton.label:SetText("Play")
        self.dragging = true
        local at = MomentUnderCursor()
        if at then
            state.now = at
            Replay.Redraw()
            Paint(state.now)
        end
    end)

    local function StopScrub(self)
        self.dragging = nil
    end
    scrub:SetScript("OnMouseUp", StopScrub)
    scrub:SetScript("OnHide", StopScrub)

    scrub:SetScript("OnUpdate", function(self)
        if not self.dragging then return end
        if not (Replay.state and IsMouseButtonDown("LeftButton")) then
            StopScrub(self)
            return
        end
        local at = MomentUnderCursor()
        if at and at ~= Replay.state.now then
            Replay.state.now = at
            Replay.Redraw()
            Paint(Replay.state.now)
        end
    end)

    frame.scrub = scrub

    frame.healthText = UI.Label(frame.health, "", 11, C.text)
    frame.healthText:SetPoint("LEFT", frame.health, "LEFT", 6, 0)

    frame.clock = UI.Label(frame.health, "", 11, C.text)
    frame.clock:SetPoint("RIGHT", frame.health, "RIGHT", -6, 0)
    frame.clock:SetJustifyH("RIGHT")

    -- The axis. Three pixels rather than one: it is the spine of the whole
    -- picture and a hairline read as a scratch between two empty halves.
    local axis = frame:CreateTexture(nil, "ARTWORK")
    axis:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    axis:SetPoint("TOPLEFT", frame.plot, "TOPLEFT", PLOT_L, -AXIS_Y)
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
    frame.playhead:SetPoint("TOP", frame.plot, "TOPLEFT", PLOT_L, -(HEALTH_Y - 4))
    frame.playhead:SetHeight(Replay.PlotFloor(EMPTY_LANES) - HEALTH_Y)

    -- What hit you above the axis, and the three things you pressed below
    -- it: the rotation as icons, then the cooldowns and the defensives as
    -- bars, each in a lane of its own.
    frame.incoming, frame.outgoing, frame.casts = {}, {}, {}
    frame.cooldowns = {}
    for i = 1, MARKS_IN do frame.incoming[i] = BuildMark(frame, "in") end
    for i = 1, MARKS_OUT do frame.outgoing[i] = BuildMark(frame, "press") end
    for i = 1, MARKS_CAST do frame.casts[i] = BuildMark(frame, "press") end
    for i = 1, MARKS_CD do frame.cooldowns[i] = BuildMark(frame, "press") end

    -- And the falls, which only a fight has.
    frame.falls = {}
    for i = 1, MARKS_FALL do frame.falls[i] = BuildMark(frame, "fall") end

    -- And what was put on you, which only a fight has either: a fall's ten
    -- seconds are drawn hit by hit and need no bar to say "this was on you".
    frame.worn = {}
    for i = 1, MARKS_WORN do frame.worn[i] = BuildMark(frame, "worn") end

    frame.wornLabel = UI.Eyebrow(frame, "Debuffs on you")
    frame.wornLabel:SetPoint("BOTTOMLEFT", frame.plot, "TOPLEFT", PLOT_L,
        -(DEBUFF_Y - 4))
    frame.wornLabel:Hide()

    frame.laneIn = UI.Eyebrow(frame, "Damage on you")
    frame.laneIn:SetPoint("TOPLEFT", frame.plot, "TOPLEFT", PLOT_L, -LANE_IN_Y)

    -- AND WHY IT IS EMPTY, WHEN IT IS. An empty lane and a lane the client
    -- will not fill look exactly alike, and the owner read the second as the
    -- first twice in one evening. Same lesson as the dim button: the state
    -- is not the reason.
    frame.laneNote = UI.Label(frame, "", 11, C.textFaint)
    frame.laneNote:SetPoint("TOPLEFT", frame.laneIn, "BOTTOMLEFT", 0, -4)
    frame.laneNote:SetWidth(PLOT_W)
    frame.laneNote:SetJustifyH("LEFT")
    frame.laneNote:Hide()
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
    -- THE CEILING IS THE FIGHT'S, so the config table is kept and its max
    -- moved when a window opens. The slider reads cfg.max every time it is
    -- asked rather than at build, which is what makes that legal - and a
    -- slider whose travel ends where the fight does is the difference
    -- between "as far as it goes" and a number silently clamped behind it.
    frame.zoomCfg = {
        get = function() return (Replay.state and Replay.state.zoom) or 1 end,
        set = function(value)
            if not Replay.state then return end
            local most = Replay.ZoomMax(Replay.state.span)
            Replay.state.zoom = math.max(1, math.min(most, value))
            Replay.Redraw()
        end,
        min = 1, max = ZOOM_MIN_MAX, step = 0.5,
        silent = true,
        format = function(v) return Replay.SpeedLabel(v) end,
    }
    UI.Slider(zoomRow, frame.zoomCfg)
    UI.FitRow(zoomRow)
    frame.zoomRow = zoomRow

    -- The switch for the graph, remembered in the profile. ABOVE PLAY, on
    -- the graph's own left edge, not at the far end of the control row
    -- (owner, 2026-08-16: "der graph button ist zu weit rechts aussen, den
    -- kannste auch ueber den play button schieben"): it sits between the
    -- thing it switches and the buttons, where the eye already is.
    -- THE TWO THINGS THIS WINDOW CAN PUT AWAY, in the header beside the
    -- title. Owner, 2026-08-30: "pack die 2 buttons nach oben in den
    -- header." They were stacked over Play in the bottom-left, which is
    -- the plot's own corner - a defensive still running at the left edge
    -- was drawn straight across them, and a switch you cannot read is a
    -- switch nobody presses.
    --
    -- Health first, then Graph, in the order the window folds them away.
    local healthRow = UI.Row(frame, "Health", { controlWidth = 40 })
    healthRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT",
        -(44 + SWITCH_W + SWITCH_GAP), -10)
    healthRow.rule:Hide()
    UI.Toggle(healthRow,
        function()
            local state = Replay.state
            return state and state.healthOpen or false
        end,
        function(value)
            local state = Replay.state
            if not state then return end
            state.healthSaid = value and true or false
            state.healthOpen = state.healthSaid
            Replay.Relayout()
        end)
    UI.FitRow(healthRow)
    frame.healthRow = healthRow

    local graphRow = UI.Row(frame, "Graph", { controlWidth = 40 })
    graphRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -44, -10)
    graphRow.rule:Hide()
    UI.Toggle(graphRow,
        function() return Replay.GraphWanted() end,
        function(value)
            ns.db.death = ns.db.death or {}
            ns.db.death.replayGraph = value and true or false
            Replay.Relayout()
        end)
    UI.FitRow(graphRow)
    frame.graphRow = graphRow

    -- THE GRAPH ITSELF: a caption, a baseline, one column per bucket.
    frame.graphLabel = UI.Eyebrow(frame, "Damage taken")
    frame.graphLabel:SetPoint("BOTTOMLEFT", frame.plot, "TOPLEFT", PLOT_L,
        -(Replay.GraphBand(false, EMPTY_LANES) - 4))

    frame.graphPeak = UI.Label(frame, "", 10, C.textDim)
    frame.graphPeak:SetPoint("BOTTOMRIGHT", frame.plot, "TOPLEFT",
        PLOT_L + PLOT_W, -(Replay.GraphBand(false, EMPTY_LANES) - 4))
    frame.graphPeak:SetJustifyH("RIGHT")

    frame.graphBase = frame:CreateTexture(nil, "ARTWORK")
    frame.graphBase:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    frame.graphBase:SetPoint("TOPLEFT", frame.plot, "TOPLEFT", PLOT_L,
        -(Replay.GraphBand(false, EMPTY_LANES) + GRAPH_H))
    frame.graphBase:SetSize(PLOT_W, 1)

    frame.graphCols = {}
    for i = 1, GRAPH_COLS do
        local col = frame:CreateTexture(nil, "ARTWORK")
        col:SetColorTexture(0.55, 0.11, 0.11, 0.95)
        col:Hide()
        local cap = frame:CreateTexture(nil, "ARTWORK")
        cap:SetColorTexture(0.85, 0.30, 0.26, 0.95)
        cap:Hide()
        frame.graphCols[i] = { bar = col, cap = cap }
    end

    -- THE ONE SENTENCE THIS WINDOW EXISTS TO MAKE UNNECESSARY, said anyway.
    -- The spells in it are spells, so they are drawn the way this game draws
    -- spells: an icon in front of the name and a tooltip on hover. The
    -- owner's rule - "immer wenn eine faehigkeit einen tooltip und icon hat,
    -- muss das angezeigt werden. egal bei was".
    -- The panel down the left, and the hairline between it and the plot.
    -- What used to be a caption and a strip of chips under the plot -
    -- "Defensives used:" - is the first of its three lists.
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(C.edge[1], C.edge[2], C.edge[3], 1)
    divider:SetPoint("TOPLEFT", frame, "TOPLEFT", PANEL_X + PANEL_W + 16, -14)
    divider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PANEL_X + PANEL_W + 16, 14)
    divider:SetWidth(1)

    frame.panel = ns.Death.BuildDefensivePanel(frame, PANEL_W)
    frame.panel:SetPoint("TOPLEFT", frame, "TOPLEFT", PANEL_X, -16)
    frame.panel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PANEL_X, 14)

    -- NO "CLOSE" BUTTON here either: the X closes it, and the two sliders
    -- beside it needed the room. Both of them were unreadable - "1x" twice
    -- with no way to tell speed from zoom, because each slider was drawing
    -- over its own label. See UI.FitRow.
end

-- The panel on the left says what was used and what was not; it replaced
-- the one-line legend under the plot, which could only ever say the first.
local function PaintLegend(snapshot)
    frame.panel.Paint(snapshot)
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
-- The title as pieces for the rich line: the words in the window's text
-- colour, then the killer with its face and the tip - what the mob did to
-- you in these seconds. Pure.
-- WHAT YOUR HEALTH WAS AT A GIVEN MOMENT, from whichever of the two sources
-- the story carries. `now` counts DOWN in seconds before the end, so the
-- reading that stands is the newest one that is not still in the future.
--
-- A DEATH knows it hit by hit, out of Blizzard's recap. A FIGHT knows it once
-- a second, out of the sampler in CombatLog's watcher - and between two falls
-- a fight has no recap at all, which is exactly why the recap's answer must
-- not be stretched across a pull: the health left after a hit three minutes
-- ago is not your health now.
--
-- NOTHING RATHER THAN A FULL BAR when neither source has reached a moment.
-- The old reader answered maxHP before the first event, which is true of a
-- death - the recap starts at full - and an invention on a pull.
function Replay.HealthAt(track, events, now, maxHP)
    if type(track) == "table" and #track > 0 then
        local hp, most
        for _, one in ipairs(track) do
            if (one.t or 0) >= now then hp, most = one.hp, one.max end
        end
        return hp, most or maxHP
    end
    local _, hp = ns.Death.ReplayAt(events, now, maxHP)
    return hp, maxHP
end

-- WHAT THE HEALTH LINE SAYS ABOUT DAMAGE, which is the only timed answer a
-- FIGHT has at all.
--
-- Measured, 2026-08-31, from the owner's probe taken mid-combat: while a
-- fight is running the meter withholds `totalAmount` AND `spellID` AND
-- `unitName` AND `sourceCreatureID`. So "who hit you for how much at second
-- forty" is not a thing this addon is refusing to do - it is a thing the
-- client does not answer. Blizzard's death recap is the one exception and it
-- opens on a death.
--
-- `UnitHealth` is plain at all times, though. So what CAN be measured second
-- by second is how much health you LOST, and that is what this returns - a
-- different fact, labelled as a different fact. A second in which a heal
-- landed on top of a big hit shows the net, which is why the lane over it
-- says "health lost" and not "damage taken".
function Replay.LossEvents(track)
    local out = {}
    for index = 2, #(track or {}) do
        local before, after = track[index - 1], track[index]
        local was = type(before) == "table" and before.hp or nil
        local now = type(after) == "table" and after.hp or nil
        if type(was) == "number" and type(now) == "number" and was > now then
            out[#out + 1] = {
                t = after.t, amount = was - now, overkill = 0,
            }
        end
    end
    return out
end

function Replay.TitlePieces(snapshot)
    local C = ns.UI.C
    -- A FIGHT WEARS THE NAME THE PAGE IT CAME FROM WEARS. Two windows about
    -- one pull that name it differently are two pulls as far as anybody
    -- reading them is concerned.
    if type(snapshot) == "table" and snapshot.pull then
        return {
            { text = "Replay - ", colour = C.text },
            { text = snapshot.title or "this fight", colour = C.accent },
        }
    end
    if not (type(snapshot) == "table" and snapshot.killer) then
        return { { text = "Replay", colour = C.text } }
    end
    return {
        { text = "Replay - killed by ", colour = C.text },
        { who = snapshot.killer, art = snapshot.killerArt,
          summary = ns.Death.SourceSummary(snapshot.events, snapshot.killer) },
    }
end

-- THE THREE KINDS OF PRESS, SORTED INTO THEIR LANES.
--
-- Pure, and asked twice: once when the window opens, to work out how tall
-- each lane has to be, and again on every layout to draw them. Two copies
-- of this test would be two answers to "which lane is this press in" - the
-- window would make room for one shape and then draw another.
--
-- THE KIND IS READ, NOT DECIDED. Both flags were settled where the press
-- was recorded and only one of them can be set; testing defensive first
-- here as well costs nothing and means saved data that predates the
-- pickers still draws once.
function Replay.Presses(casts)
    local bars, majors, others = {}, {}, {}
    for _, cast in ipairs(casts or {}) do
        if cast.defensive then
            -- The window this press opened, first. See Replay.BarLength.
            local duration, source = Replay.BarLength(cast)
            bars[#bars + 1] = {
                t = cast.t, name = cast.name, spellID = cast.spellID,
                itemID = cast.itemID,
                cast = true, defensive = true,
                duration = duration, source = source,
            }
        elseif cast.cooldown then
            -- A BAR FOR THE SAME REASON THE DEFENSIVES GET ONE: a cooldown
            -- is a window you are inside, and "was Avatar still up when it
            -- went wrong" is the question this lane exists to answer. An
            -- icon on its own could not.
            local duration, source = Replay.BarLength(cast)
            majors[#majors + 1] = {
                t = cast.t, name = cast.name, spellID = cast.spellID,
                itemID = cast.itemID,
                cast = true, cooldown = true,
                duration = duration, source = source,
            }
        else
            others[#others + 1] = {
                t = cast.t, name = cast.name, spellID = cast.spellID,
                itemID = cast.itemID,
                cast = true,
            }
        end
    end
    return bars, majors, others
end

-- AND WHAT WAS PUT ON YOU, in the same shape, for the same two readers.
function Replay.WornBars(worn)
    local out = {}
    for _, one in ipairs(worn or {}) do
        out[#out + 1] = {
            t = one.t, name = one.name, spellID = one.spellID,
            worn = true,
            -- STILL ON YOU RUNS TO THE END. It is the case worth seeing
            -- and the one a recorder that only files closed windows loses.
            duration = one.stillOn and one.t or one.held,
            stillOn = one.stillOn,
        }
    end
    return out
end

-- HOW MANY ROWS EACH LANE NEEDS FOR THIS FIGHT, before any ceiling. The
-- stacking already works this out; this asks it of all three lanes at once
-- so the window can be measured before a single bar is drawn.
function Replay.Needed(snapshot)
    if type(snapshot) ~= "table" then return 1, 1, 1 end
    local bars, majors = Replay.Presses(snapshot.casts)
    local _, def = Replay.StackRows(bars)
    local _, cd = Replay.StackRows(majors)
    local _, worn = Replay.StackRows(Replay.WornBars(snapshot.worn))
    return cd, def, worn
end

-- HOW MANY ROWS A LANE ACTUALLY USES. StackRows already worked out how many
-- the fight needs; this only holds that to the ceiling and never returns
-- less than one, so an empty lane is still a lane and not a negative gap.
function Replay.RowsUsed(needed, cap)
    return math.max(1, math.min(needed or 1, cap or 1))
end

-- HOW MANY ROWS THE DEBUFF LANE MAY HAVE, which depends on what is under it.
--
-- It is the one lane with a hard edge below: the recap's columns grow UP
-- towards it from the axis. Where there are none - every pull nobody died
-- in, and every fight with the health block put away - that room is free
-- and this lane may use it.
function Replay.DebuffCap(open, hits)
    if not open then return DEBUFF_ROOM end
    return ((hits or 0) > 0) and DEBUFF_ROWS or DEBUFF_ROOM
end

-- THE ROW COUNTS FOR THE FIGHT IN THE WINDOW, as one shape.
--
-- Everything that measures this window asks for them together, because they
-- are one answer: how much room does what is actually on the plot need. The
-- state carries what each lane NEEDED, worked out once when the window
-- opened; the ceilings are applied here, so there is a single place where
-- "and no more than this" is said.
function Replay.Lanes(state)
    state = state or Replay.state or {}
    return {
        cd = Replay.RowsUsed(state.cdNeeded, CD_ROWS),
        def = Replay.RowsUsed(state.defNeeded, BAR_ROWS),
        worn = Replay.RowsUsed(state.wornNeeded,
            Replay.DebuffCap(state.healthOpen, state.hits)),
    }
end

-- WHERE THE DEFENSIVES LANE STARTS: under however many rows the cooldowns
-- above it turned out to need.
function Replay.LaneOut(lanes)
    lanes = lanes or Replay.Lanes()
    return LANE_CD_Y + lanes.cd * (BAR_H + BAR_GAP)
end

-- AND WHERE THE PLOT ENDS: under however many the defensives needed.
function Replay.PlotFloor(lanes)
    lanes = lanes or Replay.Lanes()
    return Replay.LaneOut(lanes) + lanes.def * (BAR_H + BAR_GAP)
end

-- The band's top edge and its height, measured from the top of the frame.
-- Pure, and one answer: the columns, the caption, the peak and the baseline
-- all read it, and four of them working it out separately is four places for
-- the band to end up half a pixel apart.
function Replay.GraphBand(pull, lanes)
    if pull then
        return (AXIS_Y - COLUMN_LIFT) - GRAPH_UP_H, GRAPH_UP_H
    end
    return Replay.PlotFloor(lanes) + 10, GRAPH_H
end

-- WHERE THE DEBUFF LANE SITS. Under the health block while there is one,
-- and down on the axis when there is not - it is the only thing left up
-- there, and a lane floating a window's width above the line it is read
-- against says nothing about when anything happened. Shut, its BOTTOM is
-- what is fixed, so a lane that needs four rows grows upwards into the room
-- the health block gave up rather than down through the line.
function Replay.DebuffTop(open, lanes)
    if open then return DEBUFF_Y end
    lanes = lanes or Replay.Lanes()
    return AXIS_Y - 14 - lanes.worn * (DEBUFF_H + DEBUFF_GAP)
end

-- WHERE THE PLOT'S VERTICAL SPAN BEGINS - what the playhead, the scrub
-- surface and the fall markers run from. Under the health bar while it is
-- shown, at the debuff lane when it is not.
function Replay.PlotTop(open, lanes)
    if open then return HEALTH_Y end
    return Replay.DebuffTop(false, lanes) - 18
end

-- WHETHER THE HEALTH BLOCK IS OPEN.
--
-- Owner, 2026-08-31, twice, and the second one governs: "STANDARD EIN" ...
-- "also standard ausgeblendet, nur bei tod wirds direkt eingeblendet."
--
-- So: shut, unless somebody died. A death replay IS a death and always
-- opens it; a pull opens it when somebody fell in that pull, because that
-- is the fight where "how much was left" is the question. Everything else
-- gets the room back.
--
-- `said` is the answer given by hand in this window, and it wins over the
-- rule while the window is open. It is deliberately NOT remembered: the
-- rule already gets it right for the fight in front of you, and a stored
-- "shut" taken once on a quiet pull would then hide the health on the
-- death you actually opened this window for.
function Replay.HealthOpen(snapshot, said)
    if said ~= nil then return said and true or false end
    if type(snapshot) ~= "table" then return false end
    if not snapshot.pull then return true end
    return #(snapshot.fell or {}) > 0
end

-- WHAT THE WINDOW MEASURES, in one answer instead of three sums scattered
-- through Relayout. Pure, so the desk can ask what a shut block does to the
-- height without opening a window - and so that "the plot ends far enough
-- above the transport" is a question something can be asked at all. That one
-- was a typed 476 for a year and would have swallowed the third press lane
-- in silence: the buttons are anchored to the BOTTOM of the frame, so a
-- plot that grows past them draws the bars through Play rather than off the
-- window where somebody would see it.
function Replay.Metrics(open, under, lanes)
    lanes = lanes or Replay.Lanes()
    -- HOW FAR THE PLOT RISES WHEN THE HEALTH BLOCK IS PUT AWAY: exactly the
    -- room between the health bar and where the debuff lane lands, so the
    -- bars end up on the health bar's own mark. ONE NUMBER, and it is the
    -- only one that knows about the collapse - every height below it is an
    -- offset inside frame.plot, and frame.plot is what moves.
    local lift = open and 0
        or (Replay.DebuffTop(false, lanes) - HEALTH_Y)
    local floorY = Replay.PlotFloor(lanes)
    local deep = under and (floorY + 10 + GRAPH_H) or floorY
    return {
        top = Replay.PlotTop(open, lanes),
        -- IN PLOT COORDINATES, like every other height in this file: an
        -- offset inside frame.plot, which is the thing that moves.
        floor = deep,
        -- AND THE SAME EDGE IN THE WINDOW'S OWN. The two differ by the lift
        -- and are the same number only while the health block is open - so
        -- "does the plot clear the transport" has to be asked of THIS one.
        -- Asked of the other it passes on an open window and lies on a shut
        -- one, which is a check that agrees with itself and not with the
        -- screen.
        bottom = deep - lift,
        height = floorY + FOOT_H - lift + (under and GRAPH_BLOCK or 0),
        lift = lift,
        foot = FOOT_H,
    }
end

function Replay.GraphWanted()
    return not (ns.db and ns.db.death and ns.db.death.replayGraph == false)
end

-- WHY THE INCOMING LANE IS EMPTY, WHEN IT IS.
--
-- An empty lane and a lane the game refuses to fill look identical, and the
-- owner read the second as the first twice in one evening. Same lesson as
-- the dim button: the state is not the reason.
--
-- ASKED AGAIN ON EVERY RELAYOUT, not written once when the window opens.
-- The health switch decides whether this lane is on screen at all, so a
-- sentence set at Open and never revisited is left standing from whatever
-- was opened before - and a stale explanation of a different fight is worse
-- than none. It was exactly that until 2026-08-31.
local function SayLane()
    if not (frame and frame.laneNote) then return end
    local state = Replay.state
    if not state then return end
    if not state.healthOpen then
        frame.laneNote:Hide()
        return
    end
    local events = state.events or {}
    if state.pull and #events == 0 then
        frame.laneNote:SetText("Only around a death - while a fight runs "
            .. "the game withholds what hit you and for how much. The "
            .. "band lower down is your health, which it does answer.")
        frame.laneNote:Show()
    elseif state.pull then
        frame.laneNote:SetText("The seconds around each fall - that is "
            .. "as far as the game's own recap reaches.")
        frame.laneNote:Show()
    else
        frame.laneNote:Hide()
    end
end

-- The window is as tall as what is on it: the graph adds its block, and
-- the playhead runs down through it. Called when the switch moves and
-- when the window opens.
function Replay.Relayout()
    if not frame then return end
    -- A FIGHT'S BAND IS INSIDE THE PLOT, so it costs the window no height -
    -- and the playhead stops at the plot's own floor rather than reaching
    -- down through a block that is not there.
    local pull = Replay.state and Replay.state.pull
    local open = (Replay.state and Replay.state.healthOpen) and true or false

    -- THE BAND IS THE HEALTH TOO. On a fight it is called "Health lost" and
    -- it is drawn off the same readings as the bar - putting the block away
    -- and leaving its band standing would be half a tidy-up. On a death the
    -- band is the recap's damage, which is a different answer and stays.
    local on = Replay.GraphWanted() and (open or not pull)
    local under = on and not pull

    -- ONE MOVE FOR THE WHOLE PLOT. Positive y is up: shut, everything
    -- measured inside frame.plot rises by exactly the room the health
    -- block took.
    local size = Replay.Metrics(open, under)
    local lift = size.lift
    frame.plot:ClearAllPoints()
    frame.plot:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, lift)
    frame.healthLabel:SetShown(open)
    frame.health:SetShown(open)

    -- AND "DAMAGE ON YOU" IS PART OF IT. Owner, 2026-08-31: "damage on you
    -- gehoert zu health." The caption, the sentence under it saying how far
    -- the game lets it reach, and the columns themselves - one answer, put
    -- away in one piece.
    frame.laneIn:SetShown(open)
    SayLane()
    if not open then
        for _, mark in ipairs(frame.incoming) do
            mark.item = nil
            mark:Hide()
        end
    end

    -- AND THE DEBUFFS COME DOWN ONTO THE LINE, being all that is left up
    -- there. Re-anchored rather than lifted with the rest: the lane does
    -- not move by the same amount as the plot, it moves INTO what the plot
    -- gave up.
    frame.wornLabel:ClearAllPoints()
    frame.wornLabel:SetPoint("BOTTOMLEFT", frame.plot, "TOPLEFT", PLOT_L,
        -(Replay.DebuffTop(open) - 4))

    -- AND THE THREE THINGS THAT SPAN THE PLOT rather than sitting in it:
    -- they start at its top edge, which is what moved.
    local top = size.top
    frame.scrub:ClearAllPoints()
    frame.scrub:SetPoint("TOPLEFT", frame.plot, "TOPLEFT", PLOT_L, -(top - 20))
    frame.scrub:SetPoint("BOTTOMRIGHT", frame.plot, "TOPLEFT",
        PLOT_L + PLOT_W, -Replay.PlotFloor(lanes))

    frame:SetHeight(size.height)
    frame.playhead:SetHeight(size.floor - top)

    local top, tall = Replay.GraphBand(pull)
    frame.graphLabel:ClearAllPoints()
    frame.graphLabel:SetPoint("BOTTOMLEFT", frame.plot, "TOPLEFT", PLOT_L,
        -(top - 4))
    frame.graphPeak:ClearAllPoints()
    frame.graphPeak:SetPoint("BOTTOMRIGHT", frame.plot, "TOPLEFT",
        PLOT_L + PLOT_W, -(top - 4))
    frame.graphBase:ClearAllPoints()
    frame.graphBase:SetPoint("TOPLEFT", frame.plot, "TOPLEFT", PLOT_L,
        -(top + tall))
    frame.graphLabel:SetShown(on)
    frame.graphPeak:SetShown(on)
    frame.graphBase:SetShown(on)
    if frame.healthRow and frame.healthRow.Refresh then
        frame.healthRow.Refresh()
    end
    if not on then
        for _, col in ipairs(frame.graphCols) do
            col.bar:Hide()
            col.cap:Hide()
        end
    end
    -- Placed again against the current view, so switching it on mid-replay
    -- draws it at once rather than on the next scroll.
    local state = Replay.state
    if state then
        Place(state.snapshot, state.viewFrom or state.span, state.viewTo or 0)
        Paint(math.max(0, state.now))
    end
end

-- The graph's columns against the visible band. Pure buckets, drawn.
local function PlaceGraph(events, from, to)
    if not Replay.GraphWanted() then return end
    -- AND ON A FIGHT, ONLY WHILE THE HEALTH BLOCK IS OPEN: the band is that
    -- block's second half. Relayout hides the caption and the baseline in
    -- the same breath, and a column drawn under a caption that is not there
    -- is a red shape nothing in the window explains.
    if Replay.state and Replay.state.pull
        and not Replay.state.healthOpen then
        for _, col in ipairs(frame.graphCols) do
            col.bar:Hide()
            col.cap:Hide()
        end
        return
    end
    -- A FIGHT'S GRAPH IS ITS HEALTH, not its recap: the recap covers ten
    -- seconds around a fall and the graph runs the length of the pull, so
    -- drawing the recap here would put one small red island on an empty
    -- band and call it the fight.
    local state = Replay.state
    local pull = state and state.pull
    if pull then events = state.loss or {} end
    local top, tall = Replay.GraphBand(pull)
    local buckets, peak = Replay.Buckets(events, from, to, GRAPH_COLS)
    local colW = PLOT_W / GRAPH_COLS
    for index, bucket in ipairs(buckets) do
        local col = frame.graphCols[index]
        col.t = bucket.t
        if bucket.damage <= 0 or peak <= 0 then
            col.bar:Hide()
            col.cap:Hide()
        else
            local x = PLOT_L + (index - 1) * colW
            local height = math.max(1, tall * (bucket.damage / peak))
            local capH = math.min(height - 1,
                tall * (bucket.overkill / peak))
            col.bar:ClearAllPoints()
            col.bar:SetPoint("BOTTOMLEFT", frame.plot, "TOPLEFT", x + 1,
                -(top + tall))
            col.bar:SetSize(math.max(1, colW - 2), height - math.max(0, capH))
            col.bar:Show()
            if capH > 0 then
                col.cap:ClearAllPoints()
                col.cap:SetPoint("BOTTOMLEFT", col.bar, "TOPLEFT", 0, 0)
                col.cap:SetSize(math.max(1, colW - 2), capH)
                col.cap:Show()
            else
                col.cap:Hide()
            end
        end
    end
    frame.graphPeak:SetText(peak > 0
        and string.format("peak %s per %.1fs", ns.ShortNumber(peak),
            (from - to) / GRAPH_COLS)
        or "")
end

function Place(snapshot, from, to)
    -- THE EVENTS THE STORY WAS OPENED WITH, not a second trim of the same
    -- list. A FIGHT is not ten seconds long and re-trimming here would throw
    -- away every hit outside the last ten of the pull - and it ran on every
    -- scroll, so the plot would empty out as you moved along it.
    local state = Replay.state
    local events = (state and state.events)
        or ns.Death.RecentEvents(snapshot.events, ns.Death.WINDOW)
    local maxHP = snapshot.maxHP
    PlaceGraph(events, from, to)

    -- WHAT CAME IN, above the axis. Heals are skipped rather than filtered
    -- out of the list: the list is Death's, several things read it, and
    -- rebuilding it here to leave one kind out would be a second version of
    -- the story that has to be kept in step with the first.
    local slot = 0
    for _, ev in ipairs(events) do
        -- NOT WHILE THE HEALTH BLOCK IS SHUT. The columns are the other
        -- half of "Damage on you", and Relayout has already put the caption
        -- away - a column standing under a caption that is not there is a
        -- red shape nothing in the window explains.
        if not ev.heal and (not state or state.healthOpen) then
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
                    mark:SetPoint("BOTTOM", frame.plot, "TOPLEFT", x,
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
    -- The owner is right on both counts. A bar means "this was up for this
    -- long", and a Death Strike has nothing that is up - drawing it as a bar
    -- off its tooltip's number invents a state that does not exist. So the
    -- rotation goes in a row of its own, as icons: moments, which is what they
    -- are. Only the defensives picked on the Deaths page get bars.
    local colourOf, nextColour = {}, 0
    local bars, majors, others = Replay.Presses(snapshot.casts)

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
                mark:SetPoint("TOP", frame.plot, "TOPLEFT", x, -LANE_CAST_Y)
                mark:SetSize(20, 27)

                mark.column:ClearAllPoints()
                mark.column:SetPoint("TOP", mark, "TOP", 0, 0)
                mark.column:SetWidth(1)
                mark.column:SetHeight(7)
                mark.column:SetColorTexture(0.45, 0.49, 0.55, 0.9)

                mark.icon:ClearAllPoints()
                mark.icon:SetSize(18, 18)
                mark.icon:SetPoint("TOP", mark.column, "BOTTOM", 0, -1)
                mark.icon:SetTexture(ns.Death.PanelIcon(item))
                mark.value:SetText("")
                mark:Show()
            end
        end
    end
    for i = slot + 1, MARKS_CAST do
        frame.casts[i].item = nil
        frame.casts[i]:Hide()
    end

    -- ONE PAINTER FOR BOTH BAR LANES, and it has to be one: the cooldowns
    -- want every rule the defensives already have - the stacking, the
    -- colour kept per spell, the drop line to the axis, the marker for a
    -- press whose length nobody measured. A second copy of sixty lines is
    -- a second place for one of them to be fixed and the other forgotten,
    -- which is how the two lanes would end up disagreeing about the same
    -- press. The lane it paints, its pool and how many rows it may stack
    -- are the only things that differ.
    local function PaintBars(pool, cap, list, laneY, rows)
        local slot = 0
        for _, bar in ipairs(Replay.StackRows(list)) do
            slot = slot + 1
            if slot <= cap then
                local mark = pool[slot]
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
                    local row = math.min(bar.row or 1, rows)
                    local top = laneY + (row - 1) * (BAR_H + BAR_GAP)

                    mark:ClearAllPoints()
                    mark:SetPoint("TOPLEFT", frame.plot, "TOPLEFT", x - 9, -top)
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
                    -- The ITEM's icon for a potion or a stone - the picture
                    -- you pressed - and the spell's for a spell. Same door the
                    -- panel's rows read, so plot and panel show one potion.
                    mark.icon:SetTexture(ns.Death.PanelIcon(bar))
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
        for i = slot + 1, cap do
            pool[i].item = nil
            pool[i]:Hide()
        end
    end

    -- Top lane first, so a cooldown and a defensive pressed in the same
    -- second are drawn in the order they are read. Each gets the rows the
    -- fight needs rather than a fixed four - and the second lane starts
    -- under however many the first took.
    local lanes = Replay.Lanes()
    PaintBars(frame.cooldowns, MARKS_CD, majors, LANE_CD_Y, lanes.cd)
    PaintBars(frame.outgoing, MARKS_OUT, bars, Replay.LaneOut(lanes),
        lanes.def)

    -- WHAT WAS ON YOU, above the axis. Stacked the same way the defensives
    -- below it are - two that overlap are two rows, not two bars on top of
    -- each other - and through the SAME pure function, because "which row
    -- does this go in" is one question with one answer.
    local wornBars = Replay.WornBars(snapshot.worn)
    slot = 0
    local wornLanes = Replay.Lanes()
    for _, bar in ipairs(Replay.StackRows(wornBars)) do
        slot = slot + 1
        if slot <= MARKS_WORN then
            local mark = frame.worn[slot]
            mark.item = bar
            local ended = bar.t - (bar.duration or 0)
            if bar.t < to or ended > from then
                mark:Hide()
            else
                local x = PLOT_L
                    + math.max(0, Replay.Fraction(bar.t, from, to)) * PLOT_W
                local ends = bar.duration
                    and (PLOT_L + math.min(1,
                        Replay.Fraction(math.max(0, ended), from, to)) * PLOT_W)
                    or (x + 4)
                local place = math.min(bar.row or 1, wornLanes.worn)
                local top = Replay.DebuffTop(
                    Replay.state and Replay.state.healthOpen, wornLanes)
                    + (place - 1) * (DEBUFF_H + DEBUFF_GAP)

                mark:ClearAllPoints()
                mark:SetPoint("TOPLEFT", frame.plot, "TOPLEFT", x - 9, -top)
                mark:SetSize(math.max(DEBUFF_H, (ends - x) + 9), DEBUFF_H)

                mark.column:ClearAllPoints()
                mark.column:SetPoint("TOPLEFT", mark, "TOPLEFT", 9, 0)
                mark.column:SetPoint("BOTTOMRIGHT", mark, "BOTTOMRIGHT", 0, 0)
                mark.column:SetColorTexture(0.72, 0.30, 0.62, 0.55)

                mark.icon:ClearAllPoints()
                mark.icon:SetPoint("LEFT", mark, "LEFT", 0, 0)
                mark.icon:SetSize(DEBUFF_H, DEBUFF_H)
                mark.icon:SetTexture(
                    (bar.spellID and ns.SpellTexture(bar.spellID)) or 135274)
                mark.value:SetText("")
                mark:Show()
            end
        end
    end
    for i = slot + 1, MARKS_WORN do
        frame.worn[i].item = nil
        frame.worn[i]:Hide()
    end

    -- WHERE YOU WENT DOWN, straight down the plot, so the presses and the
    -- hits on either side of it can be read against it. Only a fight has
    -- these: a death replay ends on the killing blow.
    slot = 0
    for _, one in ipairs(snapshot.fell or {}) do
        slot = slot + 1
        if slot <= MARKS_FALL then
            local mark = frame.falls[slot]
            mark.item = one
            if not Replay.Visible(one.t, from, to) then
                mark:Hide()
            else
                local x = PLOT_L + Replay.Fraction(one.t, from, to) * PLOT_W
                -- FROM THE TOP OF THE PLOT, whatever that is right now: with
                -- the health block put away the line would otherwise start
                -- above the window and end short of the presses.
                local head = Replay.PlotTop(
                    Replay.state and Replay.state.healthOpen)
                local tall = Replay.PlotFloor() - head

                mark:ClearAllPoints()
                mark:SetPoint("TOP", frame.plot, "TOPLEFT", x, -head)
                mark:SetSize(20, tall)

                mark.column:ClearAllPoints()
                mark.column:SetPoint("TOP", mark, "TOP", 0, 0)
                mark.column:SetWidth(2)
                mark.column:SetHeight(tall)
                mark.column:SetColorTexture(0.86, 0.28, 0.28, 0.55)

                mark.icon:ClearAllPoints()
                mark.icon:SetSize(18, 18)
                mark.icon:SetPoint("TOP", mark, "TOP", 0, -1)
                mark.icon:SetTexture(
                    (one.spellID and ns.SpellTexture(one.spellID)) or 135274)
                mark.value:SetText("")
                mark:Show()
            end
        end
    end
    for i = slot + 1, MARKS_FALL do
        frame.falls[i].item = nil
        frame.falls[i]:Hide()
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
                entry.plate:SetPoint("CENTER", frame.plot, "TOPLEFT", x,
                    -(AXIS_Y + 1))
                entry.label:ClearAllPoints()
                entry.label:SetPoint("CENTER", frame.plot, "TOPLEFT", x,
                    -(AXIS_Y + 1))
                -- WHAT THE PLOT ENDS ON. A death ends on the death; a
                -- fight ends when combat drops, and calling that "death" on
                -- a pull everybody walked away from is the window lying in
                -- one word.
                entry.label:SetText(at < 0.001
                    and ((state and state.pull) and "end" or "death")
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
                tick:SetPoint("TOP", frame.plot, "TOPLEFT", x, -(AXIS_Y - 2))
                tick:Show()
            end
        end
    end
    for i = half + 1, #frame.halfTicks do frame.halfTicks[i]:Hide() end
end

-- What is lit and what is waiting, for the clock's current position.
function Paint(now)
    local state = Replay.state
    local from, to = state.viewFrom or state.span, state.viewTo or 0

    for _, lane in ipairs({ frame.incoming, frame.outgoing,
        frame.casts, frame.falls, frame.worn, frame.cooldowns }) do
        for _, mark in ipairs(lane) do
            if mark.item then
                -- Landed marks stand at full strength; the rest wait at a
                -- quarter, visible enough to read the shape of what is
                -- coming without pretending it has happened.
                mark:SetAlpha(mark.item.t >= now and 1 or 0.22)
            end
        end
    end

    -- The graph fills in as the line passes: a column whose newest edge is
    -- still ahead of now is dimmed like a mark that has not happened yet.
    if Replay.GraphWanted() then
        for _, col in ipairs(frame.graphCols) do
            local alpha = (col.t and col.t >= now) and 1 or 0.22
            col.bar:SetAlpha(alpha)
            col.cap:SetAlpha(alpha)
        end
    end

    local hp, most = Replay.HealthAt(state.track, state.events, now,
        state.maxHP)
    local pct = (most and most > 0 and hp)
        and math.max(0, math.min(1, hp / most)) or 0
    frame.healthFill:SetWidth(math.max(1, PLOT_W * pct))
    -- AND WHEN IT HAS NO READING IT SAYS SO. Owner, 2026-08-31: "die your
    -- health bar ist immer leer im replay." It was empty because there was
    -- nothing behind it - a fight recorded before the sampler existed, or
    -- one that began before the addon loaded - and an empty bar is the same
    -- picture as a bar at zero. The bar cannot say which; the line can.
    if hp then
        frame.healthText:SetText(string.format("%s  |cff9ba3af%d%%|r",
            ns.ShortNumber(hp), math.floor(pct * 100 + 0.5)))
    elseif state.pull and not state.track then
        frame.healthText:SetText("|cff9ba3afNo health kept for this fight - "
            .. "it is recorded from the moment combat opens|r")
    elseif state.pull then
        frame.healthText:SetText("|cff9ba3afbefore the first reading|r")
    else
        frame.healthText:SetText("")
    end
    frame.clock:SetText(string.format("-%.1fs", math.max(0, now)))

    -- The playhead only exists where the view reaches; zoomed in and
    -- scrolled away from it, it is off the plot and must not be drawn
    -- pinned to an edge it is not at.
    if Replay.Visible(now, from, to) then
        frame.playhead:ClearAllPoints()
        frame.playhead:SetPoint("TOP", frame.plot, "TOPLEFT",
            PLOT_L + Replay.Fraction(now, from, to) * PLOT_W,
            -(Replay.PlotTop(Replay.state and Replay.state.healthOpen) - 4))
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

    -- A death recorded before presses carried an item id gets it now, so
    -- the stone is a bar in the defensives lane and the potion is pictured
    -- as the bottle - see Death.Upgrade.
    ns.Death.Upgrade(snapshot)

    -- TWO SUBJECTS, ONE WINDOW. Owner, 2026-08-31: "es soll nur die
    -- mechaniken und ui etc von deathlog uebernehmen." A fall arrives as
    -- Blizzard's recap and is ten seconds long by definition; a fight
    -- arrives from the combat log already built, over its own span, with
    -- every hit in it inside that span. Trimming the second one to the
    -- first one's window would empty most of the plot.
    local pull = snapshot.pull and true or nil
    local events, span
    if pull then
        events = snapshot.events or {}
        span = snapshot.span
    else
        events = ns.Death.RecentEvents(snapshot.events, ns.Death.WINDOW)
        local story = ns.Death.Storyline(events, snapshot.casts)
        if #story == 0 then
            ns.Print("Nothing readable to replay for that death.")
            return
        end
        span = Replay.Span(story)
    end
    -- A PLOT WITH NO WIDTH puts every mark on top of every other one and
    -- divides by nothing. It is not a window worth opening.
    if not (type(span) == "number" and span > 0) then
        ns.Print(pull and "Nothing readable to replay for that fight."
            or "Nothing readable to replay for that death.")
        return
    end

    Replay.state = {
        snapshot = snapshot,
        events = events,
        pull = pull,
        -- YOUR HEALTH ACROSS THE WHOLE FIGHT, where a fight carries it. See
        -- Replay.HealthAt for why the recap cannot stand in for this.
        track = pull and snapshot.track or nil,
        -- Health lost per reading, which is what the band under a FIGHT
        -- draws. Worked out once here rather than inside Place: Place runs
        -- again on every scroll and this walks the whole track.
        loss = pull and Replay.LossEvents(snapshot.track) or nil,
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
        -- SHUT UNLESS SOMEBODY DIED - see Replay.HealthOpen. Worked out on
        -- every open rather than carried between windows: the answer is
        -- about THIS fight, and the switch under Play is how you disagree
        -- with it for as long as you are looking at it.
        healthSaid = nil,
        healthOpen = Replay.HealthOpen(snapshot, nil),
    }

    -- HOW MANY ROWS THIS FIGHT NEEDS IN EACH LANE.
    --
    -- Owner, 2026-08-31: "hier ueberlagern noch zu viele cooldowns. das
    -- muesste dynamisch besser sein." Worked out once, here, because the
    -- window's height depends on it and the height is set before anything
    -- is drawn. The CEILINGS are applied in Replay.Lanes, which is also
    -- where the debuff lane's room is decided - that one depends on whether
    -- the recap has columns growing up underneath it, and on whether the
    -- health block is open, both of which can change while the window is.
    local cdNeeded, defNeeded, wornNeeded = Replay.Needed(snapshot)
    Replay.state.cdNeeded = cdNeeded
    Replay.state.defNeeded = defNeeded
    Replay.state.wornNeeded = wornNeeded
    local hits = 0
    for _, ev in ipairs(events or {}) do
        if not ev.heal then hits = hits + 1 end
    end
    Replay.state.hits = hits

    -- The mob in orange, the addon's mark for a word that answers: every
    -- face on the plot below opens a tip for that same mob. The place in
    -- the blue every place name in the addon wears (owner, 2026-08-16:
    -- "bei replay ... da muss der dungeon name noch blau sein").
    frame.title.Paint(Replay.TitlePieces(snapshot))
    -- A FIGHT ALREADY HAS ITS SUB-LINE WRITTEN - the same one the page it
    -- was opened from carries, through CombatLog.ReportSub. One wording for
    -- the place, the clock and the length, in both windows.
    frame.sub:SetText(pull and (snapshot.sub or "")
        or ((snapshot.when or "")
        .. (snapshot.where and ("  -  " .. ns.UI.CoolText(snapshot.where))
            or "")))

    -- The single portrait that used to sit in the corner of the damage lane
    -- is gone: every hit carries its own face now. One face for a death
    -- with twenty mobs in it answered for all of them, which is the owner's
    -- objection and it is right.
    PaintLegend(snapshot)

    -- WHAT THE TWO INCOMING LANES ARE, for the subject actually on screen.
    --
    -- A FALL has Blizzard's recap: every hit, timed, with an amount and a
    -- face. A FIGHT has that only around its falls, because the recap is the
    -- one door to per-hit numbers and it opens on a death - measured, not
    -- assumed: mid-combat the meter withholds the amount AND the spell id
    -- AND who it was. So the fight's own band is the health line, and it is
    -- named for what it is rather than for what one would rather have.
    SayLane()
    if frame.graphLabel then
        frame.graphLabel:SetText(pull and "Health lost" or "Damage taken")
    end
    -- The debuff lane is a FIGHT's lane: a fall is drawn hit by hit and
    -- needs no bar to say something was on you.
    if frame.wornLabel then
        frame.wornLabel:SetShown(pull and #(snapshot.worn or {}) > 0)
    end

    -- A LONG FIGHT GETS A LONG SLIDER. Set before the row is refreshed, or
    -- the control draws its handle against last window's range.
    frame.zoomCfg.max = Replay.ZoomMax(span)

    frame.playButton.label:SetText("Pause")
    frame.speedRow.Refresh()
    frame.zoomRow.Refresh()
    frame.graphRow.Refresh()
    Replay.Relayout()

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

-- The window, for the desk: it drives the scrub surface by hand.
function Replay.Frame()
    return frame
end

function Replay:Close()
    Replay.state = nil
    if frame then
        frame:SetScript("OnUpdate", nil)
        frame:Hide()
    end
end
