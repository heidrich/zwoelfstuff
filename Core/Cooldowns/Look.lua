---------------------------------------------------------------------------
-- The look. What one adopted frame is dressed in.
--
-- THE SECOND FILE THAT GOES NEAR A FRAME BLIZZARD OWNS, and the first that is
-- not allowed to write to one. Claim.lua is still the only writer: every
-- touch below is Claim.Set, one of the three doors this wave adds to Claim,
-- or an object we made ourselves. Every entry point spells its first
-- parameter `item` on purpose - that is the name the frame-contract desk
-- guard watches, so this file sits INSIDE the contract rather than merely
-- next to it.
--
-- WHAT IT OWNS: the eighteen keys of Store.READERS.look that describe a
-- SURFACE. The fill's own colour and texture, the spark, the charge marks,
-- the counters and the countdown are wave 5's; they are named in Store and
-- deliberately absent from Look.KEYS below.
--
---------------------------------------------------------------------------
-- ONE BRANCH, TWO OPPOSITE CORRECTIONS. A single rule is wrong on one of
-- them, and both halves were measured on screen rather than reasoned about.
-- 4.82.0's own words, kept because a fresh attempt gets them wrong in exactly
-- this order:
--
--   A BAR-SHAPED FRAME IS ALREADY A WHOLE BAR. Blizzard's TrackedBar template
--   carries a square icon at one end, a StatusBar that fills with the
--   remaining time, and its own name and timer. "Forcing its icon to fill the
--   frame - which is exactly right for the icon template, and the fix that
--   made six adopted icons one size in 4.5.0 - smears that icon across the
--   full width of the bar. Which is the one thing a tracking bar must never
--   look like, and it is what the owner saw the first time one was on
--   screen." So its parts stay where its own template put them: only the crop
--   and the direction of its fill are ours.
--
--   AN ICON-SHAPED FRAME HAS TO BE TOLD TO FILL ITS FRAME. "Each viewer's
--   template anchors its own icon texture its own way - a fixed size here, an
--   inset there - so six adopted icons in one row came out at six sizes,
--   sitting at six different offsets, while the cells behind them were a
--   perfectly even grid." Sizing the FRAME is not enough, and it is the same
--   call that ruins the bar above.
--
---------------------------------------------------------------------------
-- THE PLATE, THE BORDER AND THE VEIL ARE OURS, and where each one lives was
-- decided by what was wrong with the other place:
--
--   the plate   on the ITEM at BACKGROUND, under its own icon texture. On our
--               cell it would have to guess whether Blizzard's frame draws
--               above or below ours, and that depends on frame levels we do
--               not own.
--   the border  on a frame of ITS OWN at parent level +5 - ns.CreateChrome.
--               "A texture on the item would be painted under the item's own
--               child frames whatever layer it claims, and the swipe is one
--               of them - the border would darken along with the icon as the
--               cooldown ran."
--   the veil    on the border's frame, for exactly that reason a third time:
--               a veil at OVERLAY on the item would sit UNDER the swipe. It
--               is anchored to the ITEM rather than to the chrome, because
--               PaintBorder pushes the chrome outward by borderSize on a bar
--               and a darkening sheet that overhangs the frame is visible.
--
---------------------------------------------------------------------------
-- RULE 4, THE PER-CELL ALPHA, AND WHAT THE ANSWER COSTS.
--
-- Contract rule 4 permits Claim exactly two alphas on a Blizzard frame: 0 and
-- 1. `alpha` and `inactiveAlpha` are both this wave's, and both are numbers
-- in between - so they cannot go on the frame at all. Look.Opacity folds the
-- two into ONE number and this file spends it three ways: 1 is Claim.Reveal,
-- 0 is Claim.Veil - so "0 hides them after all" is still reachable inside the
-- rule - and anything between is Reveal plus our own veil texture.
--
-- WHAT THE VEIL COSTS, stated here rather than discovered later. It DARKENS,
-- it does not fade. An icon under a 45%-opaque plate-coloured sheet is the
-- same picture as one at alpha 0.55 over his black backdropAlpha 0.9, and a
-- different picture over anything bright. It cannot make a frame translucent,
-- so "see the world through the icon" is not deliverable this way; the only
-- thing that would is relaxing rule 4, which Claim.lua already invites
-- somebody to decide in the open. Measured against his own file this costs
-- him nothing today: `alpha` is 1 on all four of his bars and `inactiveAlpha`
-- is 0.55 on all four, so the veil does exactly the work the setting was
-- bought for. It also costs one texture per adopted frame, created once and
-- never destroyed - nothing in this API destroys a region.
--
-- AND THE HALF THAT IS ALREADY DELIVERED ELSEWHERE. inactiveAlpha's own
-- defaults entry says what it was for: "Blizzard removes its own buff icons,
-- which makes a bar reflow under your eye." Render's grid keeps the hole
-- whether or not a frame turns up, so that reflow cannot happen any more. The
-- other half - a quiet placeholder naming the missing spell - is not
-- deliverable from a frame Blizzard has pooled away, and a buff ICON that is
-- down has no frame at all. Only a buff BAR stays shown while inactive, per
-- CDM:ItemIsActive's own note. So on his screen these two keys reach exactly
-- the cells they can reach and say nothing about the ones they cannot.
---------------------------------------------------------------------------
local _, ns = ...

local Cooldowns = ns.Cooldowns
local Look = {}
Cooldowns.Look = Look

local Claim = Cooldowns.Claim
-- Captured at file scope, so the TOC order is part of the program: Store is
-- twenty lines above this file in the list and holds the one resolver that
-- decides whether a key comes from the place or from the bar.
local Store = Cooldowns.Store

---------------------------------------------------------------------------
-- The doors this wave adds to Claim
--
-- Fill, Grow and OnGive are not in Claim.lua as this file is written. Claim
-- is the one file allowed to write to a frame Blizzard owns and it is not
-- this wave's to edit, so they arrive with the integrator - and between those
-- two commits Look loads against a Claim that has none of them.
--
-- A nil call on the first render pass is the wrong way to find that out, and
-- silently skipping the work is worse: a door that quietly is not there is a
-- control that does nothing, which is the defect this addon has already
-- shipped twice under the name "Fill up". So each is asked for by name and an
-- absent one is SAID once, in the pass where it would have been used.
---------------------------------------------------------------------------
local announced = {}

local function Door(name)
    local fn = Claim[name]
    if type(fn) == "function" then return fn end

    if not announced[name] then
        announced[name] = true
        ns.Print("|cffff4040Claim." .. name .. " is missing.|r The part of the "
            .. "cooldown look that goes through it is not being applied.")
    end
    return nil
end

-- Look.Release has to run when a frame goes back, and three different callers
-- hand one back: the takeover pass through Claim.Give, the module switch
-- through Claim.GiveAll, and Render.Stop. A decoration of ours left on a
-- frame we have just said we let go is failure mode 4 arrived at from our own
-- side. Claim loads ABOVE this file and cannot name Look at file scope, so
-- the file that loads later registers itself - on the first pass rather than
-- at load, which is where a missing door can actually be read.
local registered = false

local function Register()
    if registered then return end
    local onGive = Door("OnGive")
    if not onGive then return end
    registered = true
    onGive(Look.Release)
end

---------------------------------------------------------------------------
-- Reading the eighteen keys
--
-- PURE. This half reads the profile and nothing else - no frame, no game -
-- which is what lets the desk ask it. A wrong number here does not raise; it
-- draws a cell that is very slightly not the one he arranged, and the only
-- way to catch that is to be able to ask without a client.
---------------------------------------------------------------------------

-- WHAT THIS WAVE ANSWERS FOR, in one list, so the self test can hold it up
-- against Store.READERS.look and say which of them nothing reads yet. Two
-- copies of that list would drift, and the copy that drifts is the one that
-- quietly stops reading a key somebody's layout depends on.
Look.KEYS = {
    "alpha", "backdrop", "backdropAlpha", "backdropColor", "backdropGradient",
    "backdropTexture", "borderColor", "borderGradient", "borderSize",
    "borderTexture", "fillDirection", "fillGrow", "iconZoom", "inactiveAlpha",
    "inactiveDesaturate", "showEdge", "swipeAlpha", "swipeColor",
}

-- 4.82.0's own defaults, from Bars:Style, and they are the shape a bar
-- somebody built in 4.82.0 falls back to. `backdropTexture` is absent on
-- purpose rather than missing: nil means "no statusbar texture named", which
-- ns.PaintSurface turns into a flat colour fill - sharper on a square than a
-- bar texture stretched over one. All four of his bars name "Blizzard", so on
-- his screen the plate is a real texture and this branch is the untravelled
-- one.
--
-- THE PLATE AND THE BORDER ARE #1a1a1a AND OPAQUE. Owner, 2026-08-16:
-- "standard BG farben bei allem -> 100% 1a1a1a ... also icons, bars, border."
-- The colour is named once in Init.lua and asked for here by name.
--
-- THE SWIPE IS NOT ONE OF THEM AND KEEPS ITS BLACK. It is not a surface: it
-- is the shadow the engine wipes across an icon to say how much cooldown is
-- left, and it is drawn OVER the picture rather than behind it. A swipe in
-- #1a1a1a at 70% is a grey veil that makes a ready icon and a spent one look
-- more alike, which is the one thing that mark exists to tell apart.
local DEFAULTS = {
    alpha              = 1,
    backdropAlpha      = 1,
    backdropColor      = ns.SurfaceColor(),
    borderColor        = ns.SurfaceColor(),
    borderSize         = 1,
    borderTexture      = "None",
    iconZoom           = 0.08,
    inactiveAlpha      = 0.55,
    swipeAlpha         = 0.7,
    swipeColor         = { 0, 0, 0 },
}

local WHITE = { 1, 1, 1 }
local EMPTY = {}

local function Clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

-- A NUMBER BETWEEN NONE AND ALL, defaulted BY THE NAME IT IS STORED UNDER.
--
-- Four of the eighteen keys are exactly this shape, and writing the fallback
-- out four times is four chances for one of them to drift from what 4.82.0
-- put on disk - which is a bar that looks very slightly not like the one he
-- arranged, and the hardest kind of wrong to report.
local function Fraction(cfg, key)
    return Clamp(tonumber(cfg[key]) or DEFAULTS[key], 0, 1)
end

-- ALWAYS A FRESH THREE-NUMBER TABLE. Handing back the stored table would let
-- a renderer write into his profile by accident, and handing back DEFAULTS
-- would let it write into every bar at once.
local function Colour(value, fallback)
    local source = type(value) == "table" and value or fallback
    return {
        tonumber(source[1]) or 0,
        tonumber(source[2]) or 0,
        tonumber(source[3]) or 0,
    }
end

-- The shape ns.Tint and ns.CreateBorder's SetTint both read: on, a second
-- colour, and which way the ramp runs. Absent is off, which is what every
-- gradient in his file says.
local function Gradient(value)
    value = type(value) == "table" and value or EMPTY
    return {
        on        = value.on and true or false,
        color     = Colour(value.color, WHITE),
        direction = value.direction or "right",
    }
end

-- THE CELL'S OWN LOOK, OVER THE BAR'S, and it is not tidiness.
--
-- His "Bars 2" - the only bar-shaped one he has - carries a `look` table on
-- two of its cells, and one of them overrides `fillGrow`. A reader that took
-- the bar level only would drop styling he set by hand and say nothing about
-- it, which is the quietest kind of loss there is.
--
-- THE PRECEDENCE ITSELF IS NOT DECIDED HERE ANY MORE. It moved to
-- Store.Option, which is the one place that knows all three levels - the
-- spell's own styling, the slot's from 4.82.0, and the bar - and this file's
-- own header carried the warning that made it move: a second copy of that rule
-- is a copy that goes stale, and it decides what colour things are.
--
-- A COPY OF AT MOST EIGHTEEN FIELDS, and only for a place that actually
-- carries overrides. 4.82.0 used a metatable proxy here; a copy of a fixed
-- list is the same answer without a table whose __index reaches into the
-- profile from wherever it ends up being read.
local function Chosen(bar, index)
    bar = type(bar) == "table" and bar or EMPTY

    if not Store.Overridden(bar, index) then return bar end

    local mixed = {}
    for _, key in ipairs(Look.KEYS) do
        mixed[key] = Store.Option(bar, index, key)
    end
    return mixed
end

-- ONE STORED BAR, RESOLVED. `index` is optional: without it this is the bar's
-- own look, which is what every cell that carries no override of its own
-- wears.
function Look.Style(bar, index)
    local cfg = Chosen(bar, index)

    return {
        alpha = Fraction(cfg, "alpha"),

        backdrop         = cfg.backdrop ~= false,
        backdropAlpha    = Fraction(cfg, "backdropAlpha"),
        backdropColor    = Colour(cfg.backdropColor, DEFAULTS.backdropColor),
        backdropGradient = Gradient(cfg.backdropGradient),
        backdropTexture  = cfg.backdropTexture,

        borderColor    = Colour(cfg.borderColor, DEFAULTS.borderColor),
        borderGradient = Gradient(cfg.borderGradient),
        -- No upper bound: an edge file is scaled into the 6-24 it needs by
        -- ns.PaintBorder, and the slider that writes this runs 0-4. Zero is a
        -- real answer and his only bar-shaped bar gives it.
        borderSize     = math.max(0, tonumber(cfg.borderSize)
            or DEFAULTS.borderSize),
        borderTexture  = cfg.borderTexture or DEFAULTS.borderTexture,

        -- Resolved to the ENTRY - orientation plus reverse - so no renderer
        -- has to know the four names and the four names live in one place.
        --
        -- ASKED OF STORE, NOT OF `cfg`, AND THAT IS A FIX. This read
        -- `ns.Layout.FillDirection(cfg.fillDirection)` and knew nothing about
        -- 4.82.0's `fillSide`, while Fill.Direction did - so every bar he
        -- built before the four-answer control ran the way HE set it on
        -- screen and left-to-right in this table. Two readers of one setting,
        -- disagreeing on exactly the bars that carry the old key.
        fillDirection = Store.FillDirection(bar, index),
        fillGrow      = cfg.fillGrow and true or false,

        -- The one fraction that is NOT a fraction of one: 0.2 is where the
        -- crop starts eating the art rather than its border, and above it
        -- every icon looks like a detail of itself.
        iconZoom = Clamp(tonumber(cfg.iconZoom) or DEFAULTS.iconZoom, 0, 0.2),

        inactiveAlpha      = Fraction(cfg, "inactiveAlpha"),
        inactiveDesaturate = cfg.inactiveDesaturate ~= false,

        showEdge   = cfg.showEdge and true or false,
        swipeAlpha = Fraction(cfg, "swipeAlpha"),
        swipeColor = Colour(cfg.swipeColor, DEFAULTS.swipeColor),
    }
end

-- HOW BRIGHT THIS CELL IS, as one number, whatever state it is in.
--
-- Pure on purpose, and separate from everything that touches a frame: this is
-- the whole of the rule-4 answer, and it is the one part of it that can be
-- proved at a desk. `active` nil means the client would not say, and unknown
-- is never rounded into the dimmer answer - a cell that reads as switched off
-- because a secret could not be tested is a display lying with confidence.
function Look.Opacity(style, active)
    style = type(style) == "table" and style or EMPTY

    -- No clamp on the way out. Both halves are already in 0-1 and a product
    -- of two of those cannot leave it - a second clamp here would be a line
    -- that can never do anything, which is a line that stops being read.
    local alpha = Fraction(style, "alpha")
    if active == false then alpha = alpha * Fraction(style, "inactiveAlpha") end
    return alpha
end

---------------------------------------------------------------------------
-- What we made ourselves
--
-- OUR PLATE, OUR BORDER AND OUR VEIL, KEYED BY THE FRAME THEY SIT ON - and
-- deliberately NOT in the Contract record.
--
-- Claim.Give calls Cooldowns.Forget, which drops that record entirely. A
-- plate kept there would be LOST the moment a frame went back, and the next
-- adoption of the same pooled frame would grow a second one - one per
-- adopt/release cycle, for ever, every one of them still parented to the
-- frame and still being painted. 4.82.0 got away with keeping it there
-- because its Release left the record in place; the rebuild does not, so the
-- store has to be ours.
--
-- Weak keys for the reason every other table in this folder has them:
-- Blizzard pools these frames, and a strong table would hold every one the
-- session ever saw.
---------------------------------------------------------------------------
local worn = setmetatable({}, { __mode = "k" })

local function Worn(item)
    local dressing = worn[item]
    if not dressing then
        dressing = {}
        worn[item] = dressing
    end
    return dressing
end

-- THE STATUSBAR INSIDE A TRACKED-BAR FRAME.
--
-- `item.Bar` on every build this addon has seen. The walk is 4.82.0's own
-- fallback rather than a fresh guess: the field name is Blizzard's, and one
-- rename would leave the direction setting moving nothing at all - which is
-- the exact shape of defect this wave is trying not to ship again.
local function BarFill(item)
    local fill = item and item.Bar
    if type(fill) == "table" and fill.SetOrientation then return fill end

    if not (item and item.GetChildren) then return nil end
    for _, child in ipairs({ item:GetChildren() }) do
        if child.GetObjectType and child:GetObjectType() == "StatusBar" then
            return child
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Dressing one frame
---------------------------------------------------------------------------

-- RESTYLES ONE ADOPTED FRAME. Runs on EVERY render pass, because decorations
-- come back from the pool - Claim's point 6 - and so does the anchoring of
-- an icon template's own icon texture.
--
-- Returns true when the frame was actually dressed.
function Look.Apply(item, style)
    if type(item) ~= "table" or type(style) ~= "table" then return false end
    Register()

    local dressing = Worn(item)
    local shape = ns.CDM:ItemShape(item)

    -- nil is "the client will not say", and it counts as ACTIVE. See
    -- Look.Opacity: unknown is never rounded into the dimmer answer.
    local active = ns.CDM:ItemIsActive(item) ~= false

    local zoom = style.iconZoom

    -- A BAR-SHAPED FRAME NEVER GETS HERE ANY MORE, and the branch that used
    -- to dress one is gone rather than left standing.
    --
    -- Sixty lines lived here: the fill's texture anchoring, its orientation,
    -- its reverse flag and a warning about "Fill up". All of it wrote onto
    -- Blizzard's TrackedBar template, and wave 6 stopped adopting that
    -- template - Render sends a bar-shaped place to Own.lua, which draws its
    -- own StatusBar on a cell we size. So every one of those lines was
    -- unreachable the moment that branch landed.
    --
    -- KEPT AS A CONDITION ANYWAY, because it still decides something: a bar
    -- frames itself from just OUTSIDE and an icon from just inside, and
    -- PaintBorder below reads exactly that. What is gone is the styling, not
    -- the distinction.
    --
    -- The "Fill up" warning went with it and is not missed. Owner, in his own
    -- chat, twice: "ZwoelfStuff: Claim.Grow is missing." It was a complaint
    -- about a setting he cannot reach - the row is gated on the same door - so
    -- it could only ever be noise, and noise is how a real warning stops being
    -- read. `fillGrow` stays a named, deferred setting; see Own.lua's header
    -- for why a mirrored value cannot be made to grow without arithmetic on a
    -- secret.
    if shape ~= "bar" then
        -- The art has to be told to fill the frame, and so does the sweep -
        -- or the cooldown would darken a rectangle that is not the icon it
        -- belongs to. Claim.Fill records the region's whole point list first,
        -- which is the half an anchor cannot express through Claim.Set.
        local stretch = Door("Fill")
        if stretch then
            stretch(item.Icon, item)
            stretch(item.Cooldown, item)
        end
        Claim.Set(item.Icon, "SetTexCoord", zoom, 1 - zoom, zoom, 1 - zoom)
    end

    -- The plate, on THEIR frame at BACKGROUND. Created once and kept in our
    -- own table above; ns.PaintSurface shows or hides it from `backdrop`.
    local plate = dressing.plate
    if not plate then
        plate = item:CreateTexture(nil, "BACKGROUND")
        plate:SetAllPoints(item)
        dressing.plate = plate
    end
    ns.PaintSurface(plate, style)

    -- The border, on a frame of its own above the swipe. PaintBorder Shows
    -- the chrome every time, and that line is load-bearing: Release hides it,
    -- and in 4.82.0 nothing ever turned it back on - so a spell that left a
    -- bar and came back had no border for the rest of the session while the
    -- textures below it were being set on a frame nobody could see.
    local chrome = dressing.chrome
    if not chrome then
        chrome = ns.CreateChrome(item)
        dressing.chrome = chrome
    end
    -- On a bar the edge goes OUTSIDE: the last pixel of the fill and the
    -- leading spark are the parts you read, and a border sitting on them is
    -- what the owner meant by "the border is in front of the background".
    ns.PaintBorder(chrome, style, shape == "bar")

    local swipe = style.swipeColor
    Claim.Set(item.Cooldown, "SetSwipeColor",
        swipe[1], swipe[2], swipe[3], style.swipeAlpha)
    Claim.Set(item.Cooldown, "SetDrawEdge", style.showEdge)

    -- "QUIETER" IS ONE SETTING, NOT THREE STACKED. 4.82.0's PaintAura: "Alpha
    -- AND desaturation AND a vertex darkening on top turned an icon into a
    -- dark box that read as broken next to its sharp neighbours - which is
    -- exactly what it looked like on a bar where two of six cells are ours."
    -- So there are two levers here and no third: the veil below, and this.
    -- A vertex darkening belongs to the effects wave, and stacking one here
    -- is the measured defect rather than a stronger version of the feature.
    local dull = false
    if not active then dull = style.inactiveDesaturate end
    Claim.Set(item.Icon, "SetDesaturated", dull)

    -- And rule 4, spent. Reveal even at full brightness, because the alpha
    -- hook is what holds it against Blizzard's own range veil.
    local opacity = Look.Opacity(style, active)
    local veil = dressing.veil
    if not veil then
        -- ARTWORK on the chrome, not OVERLAY: the chrome's own pixel border
        -- is at OVERLAY and a sheet drawn over it would darken the border
        -- along with the icon. Anchored to the ITEM, because PaintBorder
        -- pushes the chrome outward by borderSize on a bar.
        veil = chrome:CreateTexture(nil, "ARTWORK")
        veil:SetColorTexture(1, 1, 1, 1)
        veil:SetAllPoints(item)
        dressing.veil = veil
    end

    if opacity <= 0 then
        veil:Hide()
        Claim.Veil(item)
    else
        if opacity >= 1 then
            veil:Hide()
        else
            -- White first, then the tint - ns.PaintSurface's rule, and for
            -- its reason: SetColorTexture bakes the colour into the texture
            -- itself, and anything set on top of a texture that is already
            -- coloured is that colour times the new one.
            ns.Tint(veil, style.backdropColor, 1 - opacity, nil)
            veil:Show()
        end
        Claim.Reveal(item)
    end

    return true
end

-- TAKES OUR PLATE, BORDER AND VEIL OFF A FRAME THAT IS GOING BACK.
--
-- Registered once with Claim.OnGive, so no call site has to remember it -
-- Claim.Give, Claim.GiveAll and Render.Stop all reach it by themselves.
--
-- Hidden rather than destroyed, because nothing in this API destroys a
-- region, and kept in our own table so the next adoption of this pooled frame
-- finds them again instead of growing a second set.
function Look.Release(item)
    local dressing = item and worn[item]
    if not dressing then return false end

    if dressing.plate then dressing.plate:Hide() end
    if dressing.chrome then dressing.chrome:Hide() end
    if dressing.veil then dressing.veil:Hide() end
    dressing.grew = nil

    return true
end

---------------------------------------------------------------------------
-- The measurement door
--
-- In the shape `/zs skin` had, and for the same reason it existed: when
-- something does not look right after a pass, the answer is not to guess
-- another field name - it is to look at what this client actually put there.
--
-- FILLGROW IS THE ONE THING IN THIS WAVE THAT IS REASONED ABOUT RATHER THAN
-- MEASURED. It needs SetTimerDuration, a duration object, and a template that
-- re-drives its own Bar. Every other setting here was read off a working
-- implementation that ran in his client for months; this one was not, and the
-- honest thing to do about that is to be able to ask before the switch is
-- offered. Three greens below mean it can be; anything red means the control
-- must be greyed WITH THE REASON rather than shipped doing nothing, which is
-- what "Fill up" did twice.
---------------------------------------------------------------------------

-- THE THREE THE fillGrow QUESTION TURNS ON, asked of the frame in front of us
-- rather than assumed off a build number.
local TIMER_API = { "GetOrientation", "GetReverseFill", "SetTimerDuration" }

-- The o and the x every other dump in this addon prints, so a reader does not
-- have to learn a second alphabet halfway down the page.
local function Mark(yes)
    return yes and "|cff40ff40o|r" or "|cffff4040x|r"
end

-- The first bar-shaped frame we are currently holding.
local function FirstBar()
    local found
    Cooldowns.Each(function(frame)
        if not found and ns.CDM:ItemShape(frame) == "bar" then found = frame end
    end)
    return found
end

function Look.Dump(item)
    ns.Print("|cffffd100--- the look, on this client ---|r")

    if not item then item = FirstBar() end
    if not item then
        ns.Print("|cffff8040No adopted bar-shaped frame.|r Put a tracked buff "
            .. "bar on a bar of kind 'bar' and ask again - every answer below "
            .. "is about Blizzard's TrackedBar template and nothing else.")
        return
    end

    local dressing = worn[item]
    ns.Print(string.format("shape |cffffd100%s|r, dressed by us: %s",
        ns.CDM:ItemShape(item),
        dressing and "|cff40ff40yes|r" or "|cffff4040no|r"))

    local fill = BarFill(item)
    if not fill then
        ns.Print("|cffff4040item.Bar answers nothing|r and no child of this "
            .. "frame is a StatusBar. fillDirection and fillGrow have nowhere "
            .. "to go on this build.")
        return
    end

    ns.Print(string.format("item.Bar: |cffffd100%s|r%s",
        (fill.GetObjectType and fill:GetObjectType()) or "?",
        fill == item.Bar and "" or " |cff888888(found among the children)|r"))

    for _, ask in ipairs(TIMER_API) do
        ns.Print(string.format("   %s %s",
            Mark(type(fill[ask]) == "function"), ask))
    end

    -- The enum half of the same question. A missing member is one greyed row
    -- rather than an error, which is why it is asked rather than assumed.
    local timer = Enum and Enum.StatusBarTimerDirection
    ns.Print(string.format("   %s Enum.StatusBarTimerDirection.ElapsedTime",
        Mark(timer and timer.ElapsedTime ~= nil)))

    -- What is on it RIGHT NOW, so "the setting did nothing" and "the setting
    -- was overwritten" can be told apart - they have completely different
    -- fixes, and that is the whole reason /zs skin existed.
    local okOrientation, orientation = pcall(fill.GetOrientation, fill)
    local okReverse, reverse = pcall(fill.GetReverseFill, fill)
    ns.Print(string.format(
        "   now: orientation |cffffd100%s|r, reverse |cffffd100%s|r",
        okOrientation and tostring(orientation) or "unanswerable",
        okReverse and tostring(reverse) or "unanswerable"))

    if dressing and dressing.grew ~= nil then
        ns.Print(string.format("   Claim.Grow last answered |cffffd100%s|r",
            tostring(dressing.grew)))
    else
        ns.Print("   |cff888888Claim.Grow has not answered yet - fillGrow is "
            .. "only driven on a bar-shaped frame.|r")
    end
end
