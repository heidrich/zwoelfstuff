---------------------------------------------------------------------------
-- The StatusBar half of an adopted tracking bar.
--
-- BLIZZARD'S TrackedBar TEMPLATE ALREADY IS A BAR: a square icon at one end, a
-- StatusBar, its own name and its own timer. Wave 2 adopts that frame whole, so
-- this wave has no fill of its own to draw and no clock of its own to run - it
-- DRESSES THEIR StatusBar and leaves the value alone.
--
-- That is what deletes RefreshFill's entire mirror. The OnUpdate, Arm and Tick,
-- CanDriveTimer, DurationHandle and the copied timer text were 130 lines that
-- existed only because the old renderer drew a SECOND bar beside Blizzard's and
-- then had to keep the two in step. There is one bar now.
--
-- WHAT WAS ACTUALLY BROKEN HERE, all of it measured rather than reasoned:
--
--   1. THE ADOPTED BAR WAS NEVER GIVEN BACK. old CDM.lua:1405-1414 wrote our
--      texture and our colour onto Blizzard's fill with a bare pcall and
--      recorded neither, and CDM:Release put back the decorations, the
--      counters, the masks, the plate and the chrome - and not one word about
--      the fill. Every TrackedBar the addon ever touched kept our look for the
--      rest of the session after the module said it let go. Claim.lua's failure
--      4, on the one surface Claim's own Parts() list cannot see when
--      `item.Bar` is absent. That is why Fill.Release exists as its own call.
--
--   2. "FILL UP" WAS WIRED TO THE WRONG CALL. old Bars.lua:171-173 in as many
--      words: it was wired to SetReverseFill, "which moves the fill to the
--      OTHER END rather than making it grow". Owner: "die funktion fill up
--      macht irgendwie nix". They are two settings and two mechanisms; this
--      file implements the SPACE half (fillDirection, fillSide) and does not
--      read fillGrow at all - see the note above Fill.Direction for why the
--      clock is named and deferred rather than half-wired a second time.
--
--   3. THE VERTICAL FILL WAS UNREACHABLE. old Screen.lua:284-286: "SetReverseFill
--      on its own only ever flips a HORIZONTAL bar, so a vertical fill was
--      unreachable no matter which way the old switch was thrown." Four answers,
--      two of which need SetOrientation as well.
--
--   4. THE SPARK WAS NEVER ONCE ON SCREEN. old Screen.lua:724-730: it hung by
--      its own top AND its own bottom, twice from the texture's "RIGHT" - the
--      MIDDLE of that edge - "so it was drawn ten pixels wide and nothing tall".
--      One point, its own CENTRE on Layout.SparkEdge, sized outright.
--
--   5. THE MARKS DIVIDED NOTHING ON HALF THE BARS. old Screen.lua:676-678: "On
--      a vertical fill the old code drew vertical lines down a vertical bar -
--      three lines parallel to the fill instead of across it, which divides
--      nothing." A division runs ACROSS, so the axis follows the orientation -
--      and the orientation is ours to KNOW now rather than to read back.
--
--   6. HIS THRESHOLDS ARE NOT ON THE BAR. They sit in bar.cellOpts[1].look,
--      together with chargeMarks, fillGradient, showSpark and fillColor; the
--      bar underneath them carries none. Nothing in the rebuild reads cellOpts
--      at all - Layout.CellOpts went with the old Bars.lua and Store only counts
--      the table for Capacity. Fill.Option is that reader, and it is the whole
--      difference between carrying his configuration and reporting success
--      while throwing it away.
--
-- EVERY WRITE TO SOMETHING BLIZZARD OWNS GOES THROUGH Claim.Set, which records
-- what was there first. The overlays below - the marks, the spark, the
-- threshold bars - are OURS and are written directly; they are created ON their
-- fill for the reason old CDM.lua:1440 gives about the plate: "Ours would have
-- to guess whether Blizzard's frame draws above or below our cell, and the
-- answer depends on frame levels we do not own."
--
-- ONE TICKER AT MOST, at 0.1s, feeding only the fills that have live thresholds
-- and the ones whose span still measures zero. It is cancelled the moment both
-- sets are empty; Fill.Watching is the number that has to fall to nought.
---------------------------------------------------------------------------
local _, ns = ...

local Cooldowns = ns.Cooldowns
local Fill = {}
Cooldowns.Fill = Fill

-- Captured at file scope, so the TOC order is part of the program: Contract,
-- then Claim, then this, then Render. A reorder is `attempt to index a nil
-- value` on the next login and nothing out here would say a word.
local Claim = Cooldowns.Claim
-- Store is above Claim in the TOC and holds the ONE resolver for "does this
-- place answer for itself, or does the bar answer for it".
local Store = Cooldowns.Store

-- OUR OWN SPARK FILE, not Blizzard's. UI-CastingBar-Spark carries its glow in
-- the middle of a lot of transparent padding, so a frame stretched to a bar's
-- height shows a bright core covering about a third of it - owner: "sehr klein
-- und auch nicht so hoch wie die bar". Ours does not vary down its height, so
-- it fills whatever frame it is given.
local SPARK = [[Interface\AddOns\ZwoelfStuff\Media\spark]]
local SPARK_THICKNESS = 12

-- A charge division is a hairline, and it is drawn just short of opaque so the
-- fill's own colour still reads through it on a dark bar.
local MARK_ALPHA = 0.85

-- The ticker's period. Fast enough that a stack falling off is seen within a
-- fifth of a second, slow enough that a screen of bars is nothing at all - and
-- it only ever runs while something wants it.
local TICK = 0.1

---------------------------------------------------------------------------
-- Finding the bar
--
-- THE ONE FINDER. Every other export in this file goes through it, or the
-- styling pass and the release pass would eventually look in different places -
-- which is precisely how a fill gets dressed and never given back.
---------------------------------------------------------------------------

-- Blizzard's StatusBar on an adopted item frame, or nil.
--
-- The field name first, and the CHILDREN walked when it is absent, so a member
-- Blizzard renames costs the fill and never an error. Ported from old
-- CDM.lua:1186, where it was the only thing that made the texture picker reach
-- the most bar-like thing this addon puts on screen.
--
-- STILL REACHABLE UNDER ITS OWN NAME even though the finder below usually
-- answers with ours: Own.lua MIRRORS this bar - its min, its max, its value
-- and its timer string - and "the one Blizzard is running" is a different
-- question from "the one we are dressing". Two questions, two names.
function Fill.Blizzard(item)
    if type(item) ~= "table" then return nil end

    local named = item.Bar
    if type(named) == "table" and type(named.SetStatusBarTexture) == "function" then
        return named
    end

    if type(item.GetChildren) ~= "function" then return nil end
    for _, child in ipairs({ item:GetChildren() }) do
        if type(child) == "table" and type(child.GetObjectType) == "function"
            and child:GetObjectType() == "StatusBar"
            and type(child.SetStatusBarTexture) == "function" then
            return child
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- THE FILLS WE DREW OURSELVES
--
-- Wave 6 stopped adopting bar-shaped places and draws them instead - see
-- Own.lua's header for why, and for the five reports it answers. That leaves
-- this file with a choice, and only one of the two is honest.
--
-- The tempting one is for Own.lua to draw its own texture, its own colour, its
-- own spark, its own charge marks and its own threshold bands. It is also the
-- one this project has already paid for twice: "the second copy of a list is
-- already stale". Everything in this file is written, proved and load-bearing
-- in an order the header spells out, and a second version of it would drift on
-- the first afternoon somebody fixed a colour in one of them.
--
-- So the fill CHANGES OWNER and the file does not change job. Own.lua hands
-- its StatusBar over here, the one finder answers with it, and the marks, the
-- spark, the bands, the ticker and the release all follow it without knowing
-- anything happened.
--
-- Weak keys, like every other table in this folder: a cell's widget outlives a
-- render pass but not a reload, and a strong table would hold every frame the
-- session ever saw.
---------------------------------------------------------------------------
local ours = setmetatable({}, { __mode = "k" })

-- WHOSE FILLS ARE OURS, by the fill rather than by the item. Two tables rather
-- than a search, because the question "may I write on this without recording
-- an undo" is asked once per setter per pass and a linear walk there would be
-- the one hot loop in the file.
local mine = setmetatable({}, { __mode = "k" })

-- HANDS ONE OVER, or takes it back when `fill` is nil.
--
-- `host` is the frame this fill is MEASURED against when it cannot measure
-- itself - our cell, whose size is known a pass earlier than the fill's. On an
-- adopted bar that job fell to the item frame; on ours the item frame is
-- somewhere else entirely and its width would put every charge mark in the
-- wrong place.
function Fill.Own(item, fill, host)
    if type(item) ~= "table" then return nil end

    if fill == nil then
        ours[item] = nil
        return nil
    end

    ours[item] = { fill = fill, host = host or fill }
    mine[fill] = true
    return fill
end

-- THE ONE FINDER. Every other export in this file goes through it, or the
-- styling pass and the release pass would eventually look in different places
-- - which is precisely how a fill gets dressed and never given back.
function Fill.Bar(item)
    local held = type(item) == "table" and ours[item] or nil
    if held then return held.fill end
    return Fill.Blizzard(item)
end

---------------------------------------------------------------------------
-- What the user actually asked for
--
-- All pure, all askable without a client, and all reading the stored bar as it
-- stands - Store's promise. Nothing here writes a profile key.
---------------------------------------------------------------------------

-- ONE LOOK KEY, with the PLACE's own answer winning over the bar's.
--
-- IT MOVED, AS ITS OWN HEADER SAID IT MUST. This was `Fill.Option`, and it
-- carried the note "when the look wave lands its own resolver, this must MOVE
-- rather than be joined". That resolver is Store.Option, it knows one level
-- more than this did - a place's styling keyed by SPELL, so it travels when the
-- spell is moved - and there is now exactly one of it. Look's own `Chosen` came
-- across in the same commit.
--
-- The name stays local to this file because sixteen call sites read better as
-- `Option(bar, index, key)` than as the full path, and because the file's own
-- header names it as the reader of the per-place look. It is one line and it
-- decides nothing.
local function Option(bar, index, key)
    return Store.Option(bar, index, key)
end

-- WHICH WAY THE FILL RUNS, as ns.Layout.FillDirection's entry: the four names,
-- the orientation and the reverse flag, in the one place they are decided.
--
-- THE TRANSLATION OF THE OLD KEY IS STORE'S, NOT THIS FILE'S. It used to be
-- the four lines below, and Look.Style resolved the same setting WITHOUT the
-- fallback - so a bar carrying only 4.82.0's `fillSide` ran one way on screen
-- and the other way in the style table. Two askers, one answer, and it lives
-- in the file whose job is translating what is on disk.
--
-- WHAT IS DELIBERATELY NOT HERE: `fillGrow`. On an adopted bar the clock is
-- Blizzard's, and driving it means SetTimerDuration(durObj, interp,
-- Enum.StatusBarTimerDirection.ElapsedTime) - which has no getter, no known way
-- to clear and needs re-arming on a second (old Screen.lua:909-920). A claim we
-- cannot take back is the one thing Claim.Set refuses, so it is named and
-- deferred. Half-wiring it is exactly how "Fill up" came to do nothing at all.
function Fill.Direction(bar, index)
    return Store.FillDirection(bar, index)
end

-- WHICH TWO COLOURS GO INTO THE RAMP, AND IN WHICH ORDER. PURE.
--
-- Split out of the painting because it is a DECISION, and the decision was
-- wrong for months in a way no check could see: a flat look put white at both
-- ends, on the reasoning that white multiplies to one. It does not multiply -
-- it replaces - so every bar with a flat colour drew white, and the first
-- evidence was a screenshot. There is no GetGradient in this API, so the only
-- way this is ever askable again is to ask it before it reaches a texture.
--
-- Returns orientation, the near colour, the far colour and the alpha. A flat
-- look is the SAME colour at both ends, which is what "no ramp" has to look
-- like on a texture that cannot have its ramp removed.
function Fill.Ramp(colour, alpha, gradient)
    colour = type(colour) == "table" and colour or {}
    local r = colour[1] or 1
    local g = colour[2] or 1
    local b = colour[3] or 1

    local orientation, swap = "HORIZONTAL", false
    local one, two = { r, g, b }, { r, g, b }

    if gradient and gradient.on then
        orientation, swap = ns.Layout.GradientOrder(gradient.direction)
        local far = gradient.color
        two = type(far) == "table" and { far[1] or 1, far[2] or 1, far[3] or 1 }
            or { r, g, b }
    end
    if swap then one, two = two, one end

    return orientation, one, two, tonumber(alpha) or 1
end

-- THE STACK THRESHOLDS, CLEANED UP AND SORTED ASCENDING.
--
-- Ascending is not a tidiness preference: the order IS the draw order, because
-- the highest crossed threshold has to paint LAST and cannot be chosen with an
-- `if` - see the overlay pool below. Port of old Bars:StackThresholds.
--
-- Whole numbers of at least 1 only, "because a threshold of 0 is crossed by an
-- aura that is merely present" (old Bars.lua:1022-1024) - and the number
-- DROPPED comes back as a second answer, which is new. Measured in his own
-- file, not in the defaults: all three of his thresholds carry value = 0, so
-- the one bar he ever configured thresholds on has never painted one. The panel
-- wrote rows the renderer discards. Reporting the count is what lets the wave
-- that owns the panel fix the WRITER instead of somebody loosening this filter.
function Fill.Thresholds(bar, index)
    local stored = Option(bar, index, "stackThresholds")
    local out, dropped = {}, 0

    for _, entry in ipairs(type(stored) == "table" and stored or {}) do
        local value = type(entry) == "table" and tonumber(entry.value) or nil
        if value and value >= 1 then
            local colour = type(entry.color) == "table" and entry.color
                or { 0.85, 0.15, 0.15 }
            local ramp = type(entry.gradient) == "table" and entry.gradient or nil

            out[#out + 1] = {
                value = math.floor(value),
                color = { colour[1] or 0, colour[2] or 0, colour[3] or 0 },
                alpha = tonumber(entry.alpha) or 1,
                -- Its own ramp, never the fill's. The whole point of the band is
                -- that it is a different colour, and inheriting the fill's would
                -- make it a different colour that ramps the wrong way.
                gradient = {
                    on        = (ramp and ramp.on) and true or false,
                    color     = (ramp and ramp.color) or { 1, 1, 1 },
                    direction = (ramp and ramp.direction) or "right",
                },
            }
        else
            dropped = dropped + 1
        end
    end

    table.sort(out, function(a, b) return a.value < b.value end)
    return out, dropped
end

-- How many lines divide N charges. Two charges have ONE boundary between them,
-- so it is N-1: drawing N puts a line on the end of the bar, where it reads as
-- a border rather than as a division.
--
-- Port of old Bars:ChargeDivisions, which went with old Bars.lua and has no
-- home in the rebuild. Pure, so the off-by-one is askable without a client.
function Fill.Divisions(most)
    local count = tonumber(most)
    if not count or count < 2 then return 0 end
    return math.floor(count) - 1
end

-- HOW MANY CHARGES A SPELL HAS AT MOST, or nil for the ordinary one.
--
-- nil is the answer that keeps the promise charge marks are sold on - they only
-- ever show for a spell with more than one charge, so the setting can be left on
-- for a whole bar. The maximum is a property of the SPELL and stays plain while
-- the live count does not; ns.CanCompute is what says so before any arithmetic.
--
-- pcall because the accessor is absent on some builds and raises on others
-- rather than returning nothing.
function Fill.MaxCharges(spellID)
    local get = C_Spell and C_Spell.GetSpellCharges
    if not (get and ns.CanCompute(spellID)) then return nil end

    local ok, charges = pcall(get, spellID)
    if not (ok and type(charges) == "table") then return nil end

    local most = charges.maxCharges
    if not (ns.CanCompute(most) and type(most) == "number") then return nil end
    if most <= 1 then return nil end
    return math.floor(most + 0.5)
end

-- IS THERE ANYTHING TO FEED A THRESHOLD WITH?
--
-- CDM:ItemStacks answers it, and this asks for it BY NAME rather than assuming
-- it. It was gone for one wave - it went out with the old CDM.lua and came back
-- verbatim from cdm-full-4.82.0:Core/CDM.lua:416-455 - and while it was gone NO
-- threshold was drawn at all, on a bar the owner had already set three of them
-- on. A band that never appears is a setting that looks unfinished; a band that
-- appears and never changes colour looks like the addon lying about what it can
-- see. So the switch stays, and /zs cdm prints its answer.
--
-- It stays ONE reader, in CDM.lua, because the stack TEXT half of the same wave
-- needs the identical answer and two readers would be two answers to one
-- question.
function Fill.CanFeed()
    return type(ns.CDM and ns.CDM.ItemStacks) == "function"
end

---------------------------------------------------------------------------
-- What we remember, and where
--
-- Two weak-keyed tables and nothing on Blizzard's frame - rule 3. Neither value
-- holds a reference back to its own key: a weak-keyed table in Lua 5.1 has no
-- ephemerons, so a note that pointed at its own frame would pin the entry for
-- the session and the weakness would be decoration.
---------------------------------------------------------------------------

-- OUR FRAMES ON THEIR BAR, kept for the life of the StatusBar rather than
-- dropped when we let go. A frame cannot be destroyed in this API - Render says
-- the same about its containers - so building a set per adoption would leak one
-- set per pool churn, and Blizzard churns these on every talent change.
local parts = setmetatable({}, { __mode = "k" })

-- THE FILLS WE HAVE DRESSED AND NOT YET GIVEN BACK. Separate from `parts` on
-- purpose: this one is the CLAIM, and it is the number that has to fall to
-- nought after a release rather than merely stop climbing.
local held = setmetatable({}, { __mode = "k" })

local function Note(fill)
    local note = parts[fill]
    if not note then
        note = { marks = {}, thresholds = {} }
        parts[fill] = note
    end
    return note
end

---------------------------------------------------------------------------
-- Measuring, colouring, and the pieces that hang off the fill
---------------------------------------------------------------------------

-- HOW LONG THE BAR IS ON ONE AXIS, with the item as the fallback.
--
-- The fill is ANCHORED inside the item rather than sized, so on a pass where the
-- item has only just been given its size this reads zero. old Screen.lua:744-747
-- says it for the spark - "a spark sized zero is invisible, which is the bug
-- this whole function has already had once" - and ApplyChargeMarks measured the
-- SAME span at line 680 with no fallback at all, so every mark landed on pixel 0
-- on such a pass. On an adopted frame the exposure is worse, because the fill
-- sits inside a frame Claim has only just resized.
--
-- Zero after both is not papered over. It is what puts this fill on the ticker
-- until it can be measured, which is why the ticker has two client sets.
--
-- WRITTEN AS TWO IFS, NOT `vertical and X or Y`. That idiom cannot carry a
-- false and it cannot carry a NIL either: a frame that answers nil for its
-- height would fall through the `or` and hand back its WIDTH, which is a real
-- number of the wrong axis - so a vertical bar would divide itself by the
-- wrong length and look laid out rather than broken. Same shape as the
-- `avoidable = false` that fell through an `or` twice in one evening.
-- `host` is the frame that answers when the fill cannot: the adopted item on
-- a borrowed bar, our own cell on a drawn one. See Fill.Own.
local function Span(host, fill, vertical)
    local here, there
    if vertical then
        here, there = fill:GetHeight(), host and host:GetHeight()
    else
        here, there = fill:GetWidth(), host and host:GetWidth()
    end

    -- ns.PlainSize, NOT type(). This fill has threshold overlays hanging off
    -- it that are fed a secret count through SetValue (see Feed below), and a
    -- secret number answers "number" to type() and then RAISES on the `>`.
    -- Same ticker, same frames: Fill.Tick hands the widget a secret and then
    -- measures it, in that order, ten times a second.
    here = ns.PlainSize(here, 0)
    there = ns.PlainSize(there, 0)

    if here > 0 then return here end
    if there > 0 then return there end
    return 0
end

-- HANDED OUT so a check can drive it. It is measured ten times a second on a
-- frame this file deliberately feeds secret values into, and "does it survive
-- that" is not a question the shape of the code can answer.
Fill.Span = Span

-- TWO COLOUR CARRIERS, REUSED. SetGradient copies its arguments at call time, so
-- one pair serves every bar on screen, and tinting runs on every pass - a pair
-- of fresh tables here would be garbage per bar per pass.
--
-- A second pair rather than Media.lua's, and that is not duplication for its own
-- sake: Media's is file-local and reachable only through ns.Tint, which writes
-- to a texture WITHOUT recording what was there. On a texture Blizzard owns that
-- is failure 4, so the ramp has to travel through Claim.Set instead.
--
-- The plain-table shape is Media.lua's own fallback rather than a second
-- decision about what a colour is: a colour object IS four fields, the four
-- fields are all SetGradient reads, and CreateColor does not exist on the desk.
local function ColourObject()
    if CreateColor then return CreateColor(1, 1, 1, 1) end
    return { r = 1, g = 1, b = 1, a = 1 }
end

local rampA, rampB = ColourObject(), ColourObject()

-- THE BAR COLOUR AND ITS RAMP, in the order that is load-bearing.
--
-- old Screen.lua:263-270: "SetStatusBarColor is a vertex colour on the bar's own
-- texture, and a gradient set afterwards would be multiplied by it. Worse,
-- calling it again later FLATTENS the ramp back to one colour - so the order
-- here is load-bearing: texture, then white, then the ramp, and nothing may set
-- the bar colour after this point."
--
-- A FLAT LOOK IS A RAMP OF ONE COLOUR, AND THAT IS NOW MEASURED.
--
-- Two comments used to stand here and they contradicted each other. One said a
-- gradient MULTIPLIES the vertex colour, so a bar carrying a flat tint would
-- come out tint-times-ramp. The other said white at both ends multiplies to
-- one, so a white ramp is what "no ramp" looks like. This file said so out
-- loud - "those two comments cannot both be right and both are written as
-- measurements" - and left it, because the shape was correct under either
-- reading.
--
-- IT WAS NOT. Owner, first screenshot of a bar we draw ourselves: a tracking
-- bar filled edge to edge in PURE WHITE, with a fill colour set on it.
--
-- So SetGradient REPLACES the vertex colour rather than multiplying it, and
-- the flat path was setting the colour and then wiping it one line later. The
-- bar had been white ever since a ramp was written unconditionally; on
-- Blizzard's adopted bar the same two calls ran and the same thing happened,
-- which is a good part of "die Farb vorschauen sind alle kacke".
--
-- MEDIA.LUA HAD IT RIGHT ALL ALONG. ns.Tint sets the vertex colour to white
-- and puts the COLOUR at both ends of the ramp - a ramp of one colour - and it
-- has been drawing every backdrop in the addon that way for months. This was
-- the second copy of that idea and it had drifted, which is the lesson this
-- project has now paid for three times.
--
-- WRITTEN TO BE RIGHT UNDER BOTH READINGS ANYWAY. White times a colour is that
-- colour, and white replaced by a colour is that colour - so setting the bar
-- to white and letting the ramp carry everything cannot be wrong whichever way
-- the engine composes them.
--
-- Returns the fill's texture object, which the spark and the overlays anchor to.
-- `Put` is the writer: Claim.Set on a frame Blizzard owns, a plain call on one
-- of ours. Handed in rather than decided here, because Dress already knows the
-- answer and asking twice is two answers to one question.
local function Paint(Put, fill, colour, alpha, gradient)
    -- WHITE, ALWAYS. The colour lives in the ramp from here on, and a bar
    -- colour left underneath it is either ignored or multiplied in twice.
    Put(fill, "SetStatusBarColor", 1, 1, 1, 1)

    local texture = type(fill.GetStatusBarTexture) == "function"
        and fill:GetStatusBarTexture() or nil
    if type(texture) ~= "table" then return nil end

    local orientation, one, two, opacity = Fill.Ramp(colour, alpha, gradient)

    rampA.r, rampA.g, rampA.b, rampA.a = one[1], one[2], one[3], opacity
    rampB.r, rampB.g, rampB.b, rampB.a = two[1], two[2], two[3], opacity

    Put(texture, "SetGradient", orientation, rampA, rampB)
    return texture
end

-- WHAT THE THRESHOLD OVERLAYS SHOULD WEAR.
--
-- The same material as the fill, so the bar does not change MATERIAL when a
-- threshold is crossed - only its colour. When an unknown texture key left
-- Blizzard's own on, that is the one to copy, and asking a texture what it wears
-- is a read rather than a write.
local function Material(fill, path)
    if path then return path end

    local texture = type(fill.GetStatusBarTexture) == "function"
        and fill:GetStatusBarTexture() or nil
    local worn = type(texture) == "table" and type(texture.GetTexture) == "function"
        and texture:GetTexture() or nil

    -- An atlas-backed region answers nil here, and handing nil to
    -- SetStatusBarTexture leaves the overlay with nothing to tint.
    if type(worn) == "string" or type(worn) == "number" then return worn end
    return ns.WHITE
end

-- THE LINES BETWEEN CHARGES. Three charges give two lines, at a third and two
-- thirds - the boundaries, not the charges.
--
-- Drawn across the fill FRAME rather than its texture: these divisions belong to
-- the bar's whole length and must not move with the clock. That is exactly the
-- opposite of the spark, which rides the texture for the same reason in reverse.
--
-- Returns whether the span was real. A mark placed against a span of zero lands
-- on pixel 0, which is a stack of hairlines on one edge - so it is HIDDEN until
-- the bar can be measured rather than drawn in the wrong place.
-- THE TRACK: THE PART OF THE BAR THAT IS NOT FILLED YET.
--
-- A texture of OURS on the fill, at BACKGROUND, covering the whole bar. The
-- StatusBar's own texture draws at ARTWORK and shrinks with the value, so a
-- texture underneath it is exactly "everything the fill is not covering" with
-- no arithmetic at all - which matters, because the value may be a secret and
-- working out how much of the bar is empty is precisely the sum nobody may do.
--
-- ON THE FILL RATHER THAN ON THE CELL, and that is the whole reason this is
-- not just the backdrop turned up. The cell's plate sits behind the icon too;
-- this sits behind the bar only, so a dark trough under the fill no longer
-- costs you a dark plate under the picture.
--
-- The SAME MATERIAL as the fill, from the same resolver the thresholds use: a
-- bar whose empty half is a different texture from its full half reads as two
-- objects that happen to be adjacent.
local function Track(fill, note, back, material)
    local track = note.track

    if not (type(back) == "table" and back.on) then
        if track then track:Hide() end
        return
    end

    if not track then
        track = fill:CreateTexture(nil, "BACKGROUND")
        track:SetAllPoints(fill)
        note.track = track
    end

    track:SetTexture(material or ns.WHITE)
    -- Through ns.Tint like every other surface in the addon. Ours, created by
    -- us, so it is written directly - there is nothing to give back.
    ns.Tint(track, back.color, back.alpha, nil)
    track:Show()
end

local function Marks(host, fill, note, wanted, colour, vertical)
    local pool = note.marks

    if wanted == 0 then
        for _, mark in ipairs(pool) do mark:Hide() end
        return true
    end

    local span = Span(host, fill, vertical)
    if span <= 0 then
        for _, mark in ipairs(pool) do mark:Hide() end
        return false
    end

    for index = 1, wanted do
        local mark = pool[index]
        if not mark then
            mark = fill:CreateTexture(nil, "OVERLAY")
            pool[index] = mark
        end

        mark:SetColorTexture(colour[1] or 0, colour[2] or 0, colour[3] or 0,
            MARK_ALPHA)
        mark:ClearAllPoints()

        -- Measured from one fixed corner, so the divisions stay where they are
        -- whichever end the fill starts from. The axis follows the ORIENTATION,
        -- because a division runs across the bar and not along it.
        local at = math.floor(span * index / (wanted + 1) + 0.5)
        if vertical then
            mark:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT", 0, at)
            mark:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, at)
            mark:SetHeight(1)
        else
            mark:SetPoint("TOPLEFT", fill, "TOPLEFT", at, 0)
            mark:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT", at, 0)
            mark:SetWidth(1)
        end
        mark:Show()
    end

    for index = wanted + 1, #pool do pool[index]:Hide() end
    return true
end

-- THE BRIGHT LINE ON THE MOVING EDGE.
--
-- One point, its own CENTRE on Layout.SparkEdge of the fill's TEXTURE, sized
-- outright. Anchored to the texture rather than to the frame, it follows the
-- clock with no per-frame work at all: the engine moves the texture and anything
-- hung off it moves too.
--
-- The shape is old Screen.lua:724-730's correction, kept exactly. It lies ACROSS
-- the bar, so the thickness is its width one way round and its height the other,
-- and the bar's own measurement is the axis that is left.
-- IS THERE ANYTHING FOR IT TO LEAD? Owner: "wenn die bar leer ist, ist der
-- spark immer noch zu sehen" - the texture collapses onto the end the bar
-- grows FROM when it empties, and the spark sat on it as a bright line for
-- as long as the buff was down.
--
-- THE SPARK IS TOLD, NEVER ASKS - and that sentence closed two doors his
-- client shut in one day.
--
-- The first version asked the fill for its VALUE, with "cannot say" counting
-- as lit. On a mirrored buff bar the value is a secret on every frame, so
-- that default was the only branch that ever ran and the spark never went
-- out.
--
-- The second version asked the TEXTURE for its drawn width, on the theory
-- that the engine computes it inside the game where the value is readable.
-- His client, 22 raises in one session: `attempt to compare local 'size' (a
-- secret number value)`. THE ENGINE'S OUTPUT INHERITS THE PROTECTION - a
-- width derived from a secret is a secret, `type()` on it still says
-- "number", and the comparison itself is the raise. There is no geometry
-- door either, and nothing hung off the mirror may be read at all.
--
-- So the answer comes from the caller, out of the one source that speaks
-- plain booleans: CDM:ItemLooksActive, the same tri-state the icon's dimming
-- runs on. A buff that is up has a leading edge; one that is down has
-- nothing to lead. That is also simply TRUER than the geometry was - a full
-- bar's edge sits against the border, and a spark there marks nothing.
--
--   lit   plain true/false from the caller. Only false puts it out -
--         unknown is never rounded into the answer that hides a working
--         bar's spark.
--
-- Setter only on change: this runs from Own's mirror tick, sixty times a
-- second, and a spark that is already lit is not re-lit per frame.
function Fill.Lead(item, lit)
    local fill = type(item) == "table" and Fill.Bar(item) or nil
    local note = fill and parts[fill] or nil
    if not (note and note.spark) then return false end

    lit = (note.sparkWanted and lit ~= false) and true or false
    if lit ~= note.sparkLit then
        note.sparkLit = lit
        note.spark:SetShown(lit)
    end
    return true
end

local function Spark(host, fill, note, show, direction, texture, vertical)
    local spark = note.spark

    -- REMEMBERED, because Fill.Lead has to be able to tell "the user switched
    -- the spark off" from "there is nothing to lead just now" - and turning
    -- one back on must never turn the other on with it.
    note.sparkWanted = show and true or false

    if not show then
        if spark then spark:Hide() end
        return true
    end

    if not spark then
        spark = fill:CreateTexture(nil, "OVERLAY")
        spark:SetTexture(SPARK)
        spark:SetBlendMode("ADD")
        note.spark = spark
    end

    local across = Span(host, fill, not vertical)
    if across <= 0 then
        spark:Hide()
        return false
    end

    -- NO TEXTURE, NO SPARK - and the `or fill` that used to stand at the
    -- anchor below is the bug he photographed twice.
    --
    -- The spark's whole job is to ride the fill's TEXTURE: the engine moves
    -- that as the clock runs and anything hung off it moves too, at no cost
    -- per frame. Hanging it on the fill FRAME instead does not degrade the
    -- effect, it produces a different object - a bright line pinned to the
    -- cell's own edge that never moves at all, whatever the bar is doing.
    -- Which is exactly "der spark bei der bar darunter ist nicht am ende der
    -- roten bar" and "der rechte border ist immer noch white", one screenshot
    -- each.
    --
    -- Paint answers nil whenever GetStatusBarTexture is not a real region,
    -- and that nil arrived here as a silent fallback. A spark with nothing to
    -- ride is not a spark; it goes out and says so through the return value.
    if type(texture) ~= "table" then
        spark:Hide()
        return false
    end

    if vertical then
        spark:SetSize(across, SPARK_THICKNESS)
        -- The picture is a bright line down a wide texture. Turned a quarter so
        -- it lies across a vertical bar instead of along it.
        spark:SetRotation(math.pi / 2)
    else
        spark:SetSize(SPARK_THICKNESS, across)
        spark:SetRotation(0)
    end

    -- ITS OWN EDGE ON THE FILL'S EDGE, NOT ITS CENTRE.
    --
    -- Owner, 2026-08-16: "rechts von den bars ist immer noch ein weisser
    -- border." It was the spark. Twelve pixels wide, blended ADD, hung by its
    -- CENTRE on the leading edge - so six pixels of white stood OUTSIDE the
    -- bar, and on a full bar the bar's leading edge is the cell's own edge.
    -- It reads as a border because it is the same shape as one and it is
    -- always on the same side.
    --
    -- Anchored edge to edge it sits entirely inside the fill at every value,
    -- which is also what it looked like it was doing on every screenshot: at
    -- half full nobody can see which six pixels are which.
    local edge = ns.Layout.SparkEdge(direction.orientation, direction.reverse)
    spark:ClearAllPoints()
    spark:SetPoint(edge, texture, edge, 0, 0)

    -- DARK UNTIL SOMEBODY WHO KNOWS SAYS OTHERWISE. This function styles; it
    -- has no legal way to find out whether the buff is up - see Fill.Lead -
    -- and Own.Draw runs its first mirror tick in the same pass, so the
    -- answer arrives before the frame is ever seen.
    note.sparkLit = false
    spark:Hide()
    return true
end

---------------------------------------------------------------------------
-- Stack thresholds: colour past N stacks, WITHOUT ever comparing N
--
-- The stack count can be a secret value, and secret values may not be compared,
-- added to or tested for truth in Lua. So the comparison is not done in Lua.
-- Each threshold gets a StatusBar whose range is exactly (value - 1, value), and
-- the count is pushed in with SetValue - a sanctioned sink for a secret. The C
-- layer does the arithmetic and the overlay snaps from empty to full as the
-- count crosses.
--
-- WITH SEVERAL THRESHOLDS, EVERY CROSSED OVERLAY IS FULL AT ONCE. "The highest
-- crossed one wins" therefore cannot be an `if` - there is nothing to branch on.
-- It has to be DRAW ORDER: overlay i is parented to overlay i-1, a child always
-- renders above its parent, and the list is sorted ascending, so the highest
-- crossed threshold paints last and covers the rest. Read off
-- EllesmereUICdmBuffBars.lua:1995-2103; the mechanism is theirs and it is the
-- only legal way to do this on 12.x. It is not optional and it is kept verbatim.
--
-- Created on demand: most bars have no thresholds at all, and a StatusBar per
-- cell per threshold is real memory on a bar that will never use one.
---------------------------------------------------------------------------
-- Named for the frames rather than for the setting, because Fill.Thresholds -
-- the pure reader that produces the list this takes - is called from the same
-- function two lines above, and one name for both would read as a recursion.
local function Overlays(fill, note, material, texture, direction, list)
    local pool = note.thresholds

    -- Nothing can push a count in, so nothing is drawn. See Fill.CanFeed.
    if not Fill.CanFeed() then list = {} end

    for index, entry in ipairs(list) do
        local overlay = pool[index]
        if not overlay then
            overlay = CreateFrame("StatusBar", nil, pool[index - 1] or fill)
            pool[index] = overlay
        end

        overlay:SetFrameLevel((fill:GetFrameLevel() or 0) + 2)
        overlay:SetStatusBarTexture(material)
        -- Copied from what we SET on the fill, never read back off it.
        overlay:SetOrientation(direction.orientation)
        overlay:SetReverseFill(direction.reverse)

        -- Anchored to the fill's TEXTURE, not to the fill: the threshold
        -- recolours the part of the bar that is actually filled, so the bar
        -- keeps its length from Blizzard's clock and only changes colour.
        -- Re-anchored every pass, "because SetStatusBarTexture replaces the
        -- texture object" (old Screen.lua:787).
        overlay:ClearAllPoints()
        overlay:SetAllPoints(texture or fill)

        local tex = overlay:GetStatusBarTexture()
        if tex then
            -- ns.Tint direct, and legally: this texture is ours.
            ns.Tint(tex, entry.color, entry.alpha, entry.gradient)
            tex:SetDrawLayer("ARTWORK", math.min(7, index))
        end

        -- THE COMPARISON, EXPRESSED AS A RANGE. Nothing in Lua reads it.
        overlay:SetMinMaxValues(entry.value - 1, entry.value)
        overlay:SetValue(0)
        overlay:Show()
    end

    for index = #list + 1, #pool do pool[index]:Hide() end
end

---------------------------------------------------------------------------
-- WHAT A FILL LOOKS LIKE, WITHOUT A FRAME TO PUT IT ON
--
-- Dress below writes these five values through Claim onto a StatusBar
-- Blizzard owns. The options page needs the SAME five to paint a preview on a
-- bar of OURS - and the preview must not resolve them a second time, because
-- a second copy of "empty means wear the backdrop's texture" and of the two
-- default colours is a second copy that goes stale. Fill.lua's own header
-- says it in the note above Option: when the look wave lands its own
-- resolver, this must MOVE rather than be joined.
--
-- Pure: it reads the stored bar and nothing else, so it answers at the desk.
-- The texture is a KEY, not a path - `nil` means "leave whatever is there",
-- which is Blizzard's own on screen and the backdrop's on a preview.
---------------------------------------------------------------------------
function Fill.Paint(bar, index)
    local key = Option(bar, index, "fillTexture")
    if key == nil or key == "" then
        key = Option(bar, index, "backdropTexture")
    end
    if not (key ~= nil and key ~= "" and ns.Media.IsKnown("statusbar", key)) then
        key = nil
    end

    local colour = Option(bar, index, "fillColor")
    local markColour = Option(bar, index, "chargeMarkColor")

    -- THE TRACK - what shows through where the bar is not filled yet.
    --
    -- Owner, with the Fill tab open: "wir brauchen hier eine bg farbe fuer den
    -- bar fill." Until now the empty part of a bar showed the CELL's backdrop,
    -- which is the plate behind the icon as well - so there was no way to have
    -- a dark trough under a bar without darkening the icon's plate with it.
    --
    -- OFF BY DEFAULT, and that is not timidity. Every bar he has arranged
    -- looks the way it looks today because the empty part shows the backdrop;
    -- shipping a track switched on would repaint all nine of them for a
    -- setting nobody had chosen. Store's promise is about the saved file and
    -- this is the same promise about the picture.
    local backColour = Option(bar, index, "fillBackColor")

    return {
        texture   = key,
        color     = type(colour) == "table" and colour or { 1.00, 0.478, 0.239 },
        alpha     = tonumber(Option(bar, index, "fillAlpha")) or 0.85,
        gradient  = Option(bar, index, "fillGradient"),
        direction = Fill.Direction(bar, index),
        spark     = Option(bar, index, "showSpark") and true or false,
        marks     = Option(bar, index, "chargeMarks") and true or false,
        markColor = type(markColour) == "table" and markColour or { 0, 0, 0 },

        back = {
            on    = Option(bar, index, "fillBack") and true or false,
            -- THE TROUGH IS A SURFACE, so it is the house colour. `markColor`
            -- above is not: a charge mark is a LINE drawn across the fill to
            -- say where one charge ends, and it has to sit against whatever
            -- colour the fill is - it takes its own default and keeps it.
            color = type(backColour) == "table" and backColour
                or ns.SurfaceColor(),
            alpha = tonumber(Option(bar, index, "fillBackAlpha")) or 0.5,
        },
    }
end

---------------------------------------------------------------------------
-- Dressing one fill
--
-- The order below is the order old Screen.lua:263-270 proved is load-bearing,
-- and every step of it is idempotent - Claim.Set records only the first time,
-- so a fill dressed on every render pass is recorded once.
---------------------------------------------------------------------------

-- Returns whether every measurement it needed was real. False means the bar
-- could not be measured yet, which is a reason to come back rather than a fault.
-- WRITING ON A FRAME WE OWN, AND ON ONE WE DO NOT.
--
-- Claim.Set exists to record what was there first, so an adopted frame can be
-- handed back exactly as it arrived. On a StatusBar we created there is nobody
-- to hand it back TO: the record would be an undo nothing will ever call, and
-- it would make Claim.Touched count our own frames - so /zs cdm's "how much
-- are we holding" would climb with the number of bars on screen and mean
-- something different from what it says.
local function Direct(object, setter, ...)
    local fn = type(object) == "table" and object[setter] or nil
    if type(fn) == "function" then pcall(fn, object, ...) end
end

local function Dress(item, fill, bar, index, spellID)
    local note = Note(fill)
    -- Kept so the ticker can run this again without the render pass. Ours, in
    -- our table, keyed by their frame - never a key written onto theirs.
    note.bar, note.index, note.spellID = bar, index, spellID

    local held = type(item) == "table" and ours[item] or nil
    local Put = mine[fill] and Direct or Claim.Set
    local host = (held and held.host) or item

    -- 1. THE TEXTURE. An unknown key leaves Blizzard's own on, which is a better
    --    default than white and one less thing to give back. Empty means "wear
    --    whatever the backdrop wears", so a bar reads as one object rather than
    --    two textures that happen to be adjacent (old Bars.lua:1165-1169).
    -- Asked ONCE, of the resolver the preview also asks. See Fill.Paint.
    local wear = Fill.Paint(bar, index)

    local path
    if wear.texture then
        path = ns.Media.Statusbar(wear.texture)
        Put(fill, "SetStatusBarTexture", path)
    end

    -- 1b. THE TRACK, under everything else on this bar. Before the colour so
    --    that a bar whose fill is see-through has something to be seen
    --    through onto - and after the texture, because it wears the same one.
    Track(fill, note, wear.back, Material(fill, path))

    -- 2 and 3. THE BAR COLOUR, THEN THE RAMP. Nothing may set the bar colour
    --    after this point.
    local texture = Paint(Put, fill, wear.color, wear.alpha, wear.gradient)

    -- 4. WHICH END AND WHICH AXIS. Two calls, because SetReverseFill alone only
    --    ever flips a horizontal bar - up and down were unreachable in 4.82.0 no
    --    matter which way the switch was thrown.
    local direction = wear.direction
    Put(fill, "SetOrientation", direction.orientation)
    Put(fill, "SetReverseFill", direction.reverse)

    local vertical = direction.orientation == "VERTICAL"

    -- 5. THE CHARGE MARKS. Only ever for a spell with more than one charge -
    --    Fill.MaxCharges answers nil for the ordinary one and Fill.Divisions
    --    turns that into no lines at all, so the setting can stay on for a bar
    --    of spells that mostly have a single charge.
    local wanted = 0
    if wear.marks then
        wanted = Fill.Divisions(Fill.MaxCharges(spellID))
    end
    local marked = Marks(host, fill, note, wanted, wear.markColor, vertical)

    -- 6. THE SPARK, on the edge the fill grows towards.
    local sparked = Spark(host, fill, note, wear.spark, direction, texture,
        vertical)

    -- 7. THE THRESHOLDS, last, because they copy the direction and anchor to the
    --    texture object the two steps above settled. The second answer - how
    --    many rows were DROPPED for being below 1 - is deliberately not carried
    --    on the note: it is a fact about his stored file rather than about this
    --    frame, and /zs cdm asks Fill.Thresholds for it directly.
    local list = Fill.Thresholds(bar, index)
    Overlays(fill, note, Material(fill, path), texture, direction, list)

    return marked and sparked
end

---------------------------------------------------------------------------
-- The one ticker
--
-- Two client sets, because they are two different reasons to come back and they
-- end at different moments: a fill FEEDS while it has live thresholds, and it is
-- MEASURED until its span stops reading zero. One set would keep the second kind
-- running for as long as the first kind wanted it, and stop the first kind the
-- moment the second settled.
--
-- Keyed by the ITEM rather than by the fill, so the note's own table never holds
-- a reference back to its own weak key - and so the fill is re-found through the
-- one finder each time rather than remembered, which is what makes a frame the
-- pool has re-issued drop out by itself.
---------------------------------------------------------------------------
local feeding = setmetatable({}, { __mode = "k" })
local measuring = setmetatable({}, { __mode = "k" })
local ticker

local function Stop()
    if not ticker then return end
    if type(ticker.Cancel) == "function" then ticker:Cancel() end
    ticker = nil
end

-- PUSH THE CURRENT COUNT INTO EVERY LIVE OVERLAY. The value may be secret;
-- SetValue takes it untouched and nothing here looks at it.
--
-- Returns whether this item still wants feeding.
local function Feed(item)
    local fill = Fill.Bar(item)
    local note = fill and parts[fill] or nil
    if not (note and note.thresholds[1] and held[fill]) then return false end

    local reader = ns.CDM and ns.CDM.ItemStacks
    if type(reader) ~= "function" then return false end

    local count = reader(ns.CDM, item)
    -- nil means the count is unknowable RIGHT NOW - leave the overlays where
    -- they are rather than reporting zero, "which would flash the bar back to
    -- its base colour every time the cache is empty for a frame" (old
    -- Screen.lua:823-825). An unreadable count is not a count of nought.
    if count == nil then return true end

    for _, overlay in ipairs(note.thresholds) do
        if overlay:IsShown() then pcall(overlay.SetValue, overlay, count) end
    end
    return true
end

-- Returns whether this item still needs measuring.
local function Remeasure(item)
    local fill = Fill.Bar(item)
    local note = fill and parts[fill] or nil
    if not (note and note.bar and held[fill]) then return false end
    return not Dress(item, fill, note.bar, note.index, note.spellID)
end

-- THE TWO LISTS THE TICK WALKS, MADE ONCE AND REUSED FOR EVER.
--
-- They have to exist: both loops clear entries out of the set they came from,
-- and mutating a table you are walking with `next` is undefined in Lua - the
-- same trap Cooldowns.Each documents. What they do NOT have to be is new.
--
-- A fresh pair per tick is two tables ten times a second for as long as
-- anything is fed, which on an evening of raiding is the same shape the mirror
-- had: small enough to be invisible in one tick and endless. MEASURED at the
-- desk on one fed bar: 21.5 KB over 200 ticks, against 0.2 for this version.
-- Owner: "schlimm waere es nur, wenn im zu zustand so viele ressourcen
-- verbraucht werden" - and this ticker runs with the window shut, because its
-- whole job is the bars on screen.
--
-- EMPTIED AT THE END AS WELL AS AT THE START, and that is not belt and braces.
-- These hold Blizzard's pooled item frames, and `feeding` and `measuring` are
-- weak-keyed exactly so a frame the pool has re-issued drops out by itself. A
-- strong list left full between ticks would pin every one of them until the
-- next tick happened to overwrite the slot - the weakness would still be there
-- and would no longer mean anything.
local measureList, feedList = {}, {}

-- EXPORTED for the same reason Effects.Step is: the harness deliberately does
-- not fire tickers - its C_Timer.NewTicker hands back something cancellable
-- that never runs - so a local one is a loop the desk cannot walk even once.
-- That is how the two tables above went unseen: nothing out there had a way to
-- call this, and a check that cannot run is worth exactly what an absent one
-- is.
function Fill.Tick()
    wipe(measureList)
    wipe(feedList)
    for item in pairs(measuring) do measureList[#measureList + 1] = item end
    for item in pairs(feeding) do feedList[#feedList + 1] = item end

    -- Measuring first. A re-dress writes SetValue(0) into every overlay, so the
    -- feed below puts the real count back inside the same frame.
    for _, item in ipairs(measureList) do
        if not Remeasure(item) then measuring[item] = nil end
    end
    for _, item in ipairs(feedList) do
        if not Feed(item) then feeding[item] = nil end
    end

    wipe(measureList)
    wipe(feedList)

    if next(measuring) == nil and next(feeding) == nil then Stop() end
end

local function Watch()
    if ticker then return end
    if next(measuring) == nil and next(feeding) == nil then return end
    if not (C_Timer and C_Timer.NewTicker) then return end
    ticker = C_Timer.NewTicker(TICK, Fill.Tick)
end

---------------------------------------------------------------------------
-- The two calls Render makes
---------------------------------------------------------------------------

-- THE WHOLE StatusBar HALF FOR ONE ADOPTED FRAME.
--
-- Called from Render.DrawBar directly after Claim.Reveal(item). Returns true
-- when a StatusBar was found and dressed - false is an icon-template frame,
-- which is most of them, and is not a fault.
--
-- Writes nothing except through Claim.Set, and never writes the bar's VALUE:
-- the clock stays Blizzard's, worked out inside the game where a secret is
-- readable and ours to borrow rather than to reproduce.
function Fill.Apply(item, bar, index, spellID)
    local fill = Fill.Bar(item)
    if not fill then return false end

    held[fill] = true
    local settled = Dress(item, fill, bar, index, spellID)

    if settled then measuring[item] = nil else measuring[item] = true end
    if parts[fill].thresholds[1] then feeding[item] = true else feeding[item] = nil end
    Watch()

    return true
end

-- Everything we changed on one StatusBar, put back.
local function Undress(fill)
    if not held[fill] then return false end
    held[fill] = nil

    -- The texture object FIRST: the ramp was recorded on it, and it is reached
    -- through the fill, whose own undo may mount a different one.
    --
    -- NOT ON A FILL OF OURS. Nothing was recorded for it - see Direct - so
    -- Claim.Unset would be a call that cannot do anything, which is a call the
    -- next reader has to work out is harmless. Its overlays still come down
    -- below, which is the whole of "released" for a frame we own.
    if not mine[fill] then
        local texture = type(fill.GetStatusBarTexture) == "function"
            and fill:GetStatusBarTexture() or nil
        if type(texture) == "table" then Claim.Unset(texture) end
        Claim.Unset(fill)
    end

    local note = parts[fill]
    if note then
        if note.track then note.track:Hide() end
        if note.spark then note.spark:Hide() end
        for _, mark in ipairs(note.marks) do mark:Hide() end
        for _, overlay in ipairs(note.thresholds) do overlay:Hide() end
    end
    return true
end

-- HANDS ONE BAR BACK.
--
-- Its own call rather than a line inside Claim.Give, because Claim's Parts()
-- list names `item.Bar` - so the child-walk case, the one Fill.Bar exists for,
-- is invisible to it. Render calls this beside Claim.Give in Takeover.
function Fill.Release(item)
    -- Nil-safe for the same reason Cooldowns.Record is: every caller reaches
    -- this by way of a viewer that may not exist on this client. And it is not
    -- only politeness here - `feeding[nil] = nil` RAISES in Lua 5.1, because
    -- luaH_set refuses a nil key whatever the value is.
    if type(item) ~= "table" then return false end

    feeding[item] = nil
    measuring[item] = nil

    local fill = Fill.Bar(item)
    if not fill then return false end
    return Undress(fill)
end

-- EVERY FILL WE HAVE DRESSED, HANDED BACK, and the ticker cancelled. What the
-- module switch and Render.Stop call.
--
-- The list is collected BEFORE anything is released, for the reason
-- Cooldowns.Each gives: Undress clears the table this is walking.
function Fill.ReleaseAll()
    local list = {}
    for fill in pairs(held) do list[#list + 1] = fill end

    local given = 0
    for _, fill in ipairs(list) do
        if Undress(fill) then given = given + 1 end
    end

    wipe(feeding)
    wipe(measuring)
    Stop()
    return given
end

---------------------------------------------------------------------------
-- The numbers
--
-- The same pair of questions Cooldowns.Held and Claim.Placed already answer for
-- the item frames, and for the same reason: a number that climbs across reloads
-- is a leak, and a number that merely stops climbing after a release is not a
-- release. /zs cdm prints both, and the self test asserts both fall to nought.
---------------------------------------------------------------------------

-- How many fills the ticker is currently feeding or measuring. A ticker still
-- running with nothing to feed is the rule-4 breach, and this is the count that
-- says so on its own verdict rather than on the render pass's.
function Fill.Watching()
    local seen, count = {}, 0
    for item in pairs(feeding) do seen[item] = true end
    for item in pairs(measuring) do seen[item] = true end
    for _ in pairs(seen) do count = count + 1 end
    return count
end

-- THE TROUGH UNDER ONE BAR'S FILL, or nil.
--
-- Its own reader because it lives in this file's private note and two things
-- outside need it: the self test, which has to prove the switch reaches a
-- texture rather than merely being stored, and /zs cdm, which says on the line
-- for each bar whether one is on. Both would otherwise have to go looking
-- through the fill's regions for "the one at BACKGROUND", which is a second
-- finder and would answer differently the day anything else is drawn there.
function Fill.Trough(item)
    local fill = Fill.Bar(item)
    local note = fill and parts[fill] or nil
    return note and note.track or nil
end

-- THE SPARK ON ONE BAR, or nil. Fill.Trough's twin and for the same two
-- readers: the self test has to prove where it is anchored and whether it
-- goes out on an empty bar, and /zs cdm says whether one is lit. Both of
-- those were reported as bugs on the same day - "rechts von den bars ist
-- immer noch ein weisser border" and "wenn die bar leer ist, ist der spark
-- immer noch zu sehen" - and neither could be seen from outside this file.
function Fill.Spark(item)
    local fill = Fill.Bar(item)
    local note = fill and parts[fill] or nil
    return note and note.spark or nil
end

-- How many StatusBars we are holding a note about.
function Fill.Held()
    local count = 0
    for _ in pairs(held) do count = count + 1 end
    return count
end
