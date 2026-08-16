---------------------------------------------------------------------------
-- The four text elements on a cell: the countdown, the stacks, the charges
-- and the spell name.
--
-- THREE OF THE FOUR ARE NOT OURS, and that is the whole shape of this wave.
-- Blizzard counts the stacks, counts the charges and runs the clock, into
-- font strings on frames it owns. We set a face, a colour, an alpha and a
-- point on the widget that holds them, and never the text. So nothing in this
-- file computes a number - which is the strongest form of the secret rule
-- there is: there is nothing to guard because there is nothing read.
--
---------------------------------------------------------------------------
-- FOUR THINGS MEASURED, three of them off the implementation that ran in his
-- client for months and one off the reference on this machine. Each one cost
-- a released setting that silently did nothing, and a fresh attempt would get
-- them wrong in the same order.
--
-- 1. A STACK COUNT IS A SECRET ON THIS PATCH. It may not be compared, added
--    to or tested for truth. The old renderer drew cells of its own and so
--    had to carry one, and paid for it: ns.CanDisplay is true for ANY secret,
--    so a protected count of nought printed exactly like a real one - the
--    owner's "wenn ich eine aufladung verbrauche noch zusaetzlich eine 0" -
--    and it cannot be compared to 1 to find out. The answer is to ask
--    Blizzard, which CAN compare and does: it HIDES the counter frame rather
--    than clearing the string when there is nothing worth showing, so the
--    frame's own visibility IS the comparison an addon may not make. That is
--    CDM:CounterShown, it answers a plain boolean, and nil there means "there
--    is no counter to ask" - which is not false and must never be read as one.
--
--    On an adopted frame the count never enters our Lua at all. This file
--    reads no counter and formats no number; the diagnostic at the bottom is
--    the only thing here that goes near one, and it describes rather than
--    prints.
--
-- 2. A COUNTER LIVES IN ONE OF TWO PLACES. `item.ChargeCount` and
--    `item.Applications` are siblings of the icon, and on frames whose Icon is
--    a container the stack text is at `Icon.Applications`
--    (EllesmereUICdmHooks.lua). Looking in the first place only made the
--    setting silently do nothing on the other kind of frame, which from the
--    outside is indistinguishable from the setting being broken and was
--    reported as exactly that. The finder is ns.CDM:Counter and there is
--    deliberately no second copy of it here - a second finder is a finder that
--    looks in one place and quietly answers "none".
--
--    The two shapes go all the way down: one is a FRAME with the string
--    inside it, the other IS the string. That is why nothing below asks a
--    counter for its regions without asking what it is first.
--
-- 3. THE COUNTDOWN NUMBER IS NOT THERE WHEN YOU GO LOOKING FOR IT. A Cooldown
--    widget's number is drawn by the engine, and the font string it draws into
--    does not exist until a cooldown is actually running on that widget.
--    Styling happens on a render pass, and on a render pass almost nothing is
--    on cooldown - so the walk found nothing, styled nothing, and the moment a
--    cooldown started the engine made one in its own face in its own place.
--    That is the whole of "the countdown position and the nudges do nothing":
--    not the arithmetic, not the setting, not the panel - the thing being
--    styled had not been created yet. So the style is REMEMBERED against the
--    widget and re-applied from a hook on the two cooldown setters. An event,
--    not a ticker: nothing here polls.
--
-- 4. ONE SETTING FOR TWO NUMBERS WAS INVISIBLE ON ANY ONE ICON AND WRONG
--    ACROSS A SCREEN. Charges and stacks shared a setting because Blizzard
--    never puts both on one frame - a cooldown item carries ChargeCount, a
--    buff item carries Applications. But "charges top left, stacks bottom
--    right" is an ordinary thing to want, and one setting cannot answer it.
--    His own file proves the split is in use: on "Bars 2" the countdown is
--    RIGHT at size 9 in Expressway, the stacks are LEFT, and the charges are
--    LEFT at x=3 size 13.
--
-- EVERY WRITE GOES THROUGH Claim, so Claim.Give puts all of it back without
-- knowing this file exists. The one thing here that is OURS is the spell name:
-- it is a font string on a layer over our own cell, it takes no Blizzard frame
-- at all, and it is the only place ns.Media.ApplyFont - which calls SetFont
-- and SetTextColor directly - may be used.
---------------------------------------------------------------------------
local _, ns = ...

local Cooldowns = ns.Cooldowns
local Text = {}
Cooldowns.Text = Text

-- Captured at file scope, so this file loads after Claim and Store and before
-- Render - see Render.lua's own note on why the TOC order is part of the
-- program. Render is NOT captured: it loads after us, and the one thing here
-- that wants it is the diagnostic, which asks at call time.
local Claim = Cooldowns.Claim
local Store = Cooldowns.Store

---------------------------------------------------------------------------
-- What the stored bar asked for
--
-- PURE. No frame, no game, no globals - given a table and a number it answers
-- the same thing every time, which is the half of the old styling pass that
-- was never provable without a client.
---------------------------------------------------------------------------

-- The automatic size of each element as a fraction of the cell height, with
-- the floor and ceiling it is clamped to. Measured off 4.82.0's TextStyle
-- rather than re-chosen: these are what his four bars have been drawn at, and
-- a "tidier" number would silently reflow every bar he owns.
--
-- Charges and stacks share a scale on purpose - they are the same kind of
-- small number in the same corner, and a charge count that came out larger
-- than a stack count would read as a different display.
--
-- THE FLOORS ARE ns.FONT_FLOOR NOW, not 8 and 9. Owner, 2026-08-16: "minimum
-- 10 pixel". Those numbers came off 4.82.0 and they are the one part of this
-- table that was never a measurement of his bars - they are the size at which
-- the worked-out number stops shrinking, and eight pixels of outlined digit
-- over a moving scene is not a number anybody reads. The SCALES and the
-- CEILINGS stay exactly as measured: they are what his four bars are drawn
-- at, and moving one would reflow a bar he has already arranged.
local ELEMENTS = {
    { key = "countdown", scale = 0.42, floor = ns.FONT_FLOOR, ceiling = 20,
      anchor = "CENTER",      outline = ns.SCREEN_OUTLINE },
    { key = "stacks",    scale = 0.30, floor = ns.FONT_FLOOR, ceiling = 16,
      anchor = "BOTTOMRIGHT", outline = ns.SCREEN_OUTLINE },
    -- INHERITS FROM stacks, FIELD BY FIELD, and that is a read-time
    -- translation rather than a migration - Store's promise. A bar written
    -- before the two were split carries no `charges` at all, and the one
    -- setting it does carry is the one it was drawn with; falling back to the
    -- defaults instead would move a number somebody had placed.
    { key = "charges",   scale = 0.30, floor = ns.FONT_FLOOR, ceiling = 16,
      anchor = "BOTTOMRIGHT", outline = ns.SCREEN_OUTLINE, inherit = "stacks" },
    -- AND THE NAME IS OUTLINED TOO NOW. It was the one element shipped with
    -- no outline at all, which made it the one element that disappeared over
    -- a bright floor - "mit outline" was not a preference, it was the reason
    -- the other three were already readable and this one was not.
    { key = "spellName", scale = 0.45, floor = ns.FONT_FLOOR, ceiling = 14,
      anchor = "LEFT",        outline = ns.SCREEN_OUTLINE },
}

local function Field(stored, inherit, key)
    local value = stored and stored[key]
    if value == nil and inherit then value = inherit[key] end
    return value
end

-- ALWAYS FOUR NUMBERS, AND ALWAYS A FRESH TABLE. Handing back the stored
-- colour would let a renderer's tint reach into his profile through an alias,
-- which is the one thing Store promised cannot happen here.
local function Colour(value)
    if type(value) ~= "table" then return { 1, 1, 1, 1 } end
    return {
        tonumber(value[1]) or 1, tonumber(value[2]) or 1,
        tonumber(value[3]) or 1, tonumber(value[4]) or 1,
    }
end

local function Element(bar, spec, height)
    local stored = type(bar[spec.key]) == "table" and bar[spec.key] or nil
    local inherit = spec.inherit and type(bar[spec.inherit]) == "table"
        and bar[spec.inherit] or nil

    -- A SIZE OF 0 MEANS "WORK IT OUT FROM THE CELL", which is what keeps a
    -- 24px bar and a 64px icon looking like one design.
    local size = tonumber(Field(stored, inherit, "size")) or 0
    if size <= 0 then
        size = math.max(spec.floor, math.min(spec.ceiling, height * spec.scale))
    else
        -- AND THE FLOOR IS UNDER THE TYPED NUMBER TOO. "minimum 10 pixel" is
        -- a fact about what can be read on a screen, so it cannot depend on
        -- whether the size was worked out or entered - and profiles written
        -- before the rail's own minimum moved still carry sixes and nines.
        --
        -- CLAMPED AT READ TIME RATHER THAN REWRITTEN IN THE PROFILE. Nothing
        -- here reaches into a saved setting: the stored nine is still a nine,
        -- and the day the floor changes it means whatever the floor says
        -- then.
        size = math.max(ns.FONT_FLOOR, size)
    end

    -- AN EMPTY FONT MEANS THE ONE SCREEN FACE, and that is where the automatic
    -- went out.
    --
    -- It used to answer `(ns.db and ns.db.font) or nil`, and nil is what
    -- ns.Media.Font turned into Blizzard's Friz Quadrata - so a bar in a
    -- profile that had never been given a face was drawn in a serif while
    -- every tracking group beside it was drawn in Blizzard's number face, and
    -- no control anywhere named either rule.
    --
    -- ns.ScreenFontName is the one answer now: the user's `ns.db.font` if
    -- there is one, ns.SCREEN_FONT otherwise. The setting survives - it is
    -- still "one place to change the typeface on every bar" - it just cannot
    -- resolve to nothing any more.
    local font = Field(stored, inherit, "font")
    if type(font) ~= "string" or font == "" then
        font = ns.ScreenFontName()
    end

    local anchor = Field(stored, inherit, "anchor")
    local outline = Field(stored, inherit, "outline")

    return {
        show    = Field(stored, inherit, "show") ~= false,
        font    = font,
        size    = size,
        color   = Colour(Field(stored, inherit, "color")),
        outline = type(outline) == "string" and outline or spec.outline,
        anchor  = type(anchor) == "string" and anchor or spec.anchor,
        x       = tonumber(Field(stored, inherit, "x")) or 0,
        y       = tonumber(Field(stored, inherit, "y")) or 0,
    }
end

-- The four elements of one bar, resolved once. `height` is the cell height -
-- Store.Lattice's `size`, which is iconSize on an icon bar and barHeight on a
-- bar-shaped one, and not the same number as the slot's width.
function Text.Style(bar, height)
    bar = type(bar) == "table" and bar or {}
    height = tonumber(height) or 40

    local out = {}
    for _, spec in ipairs(ELEMENTS) do
        out[spec.key] = Element(bar, spec, height)
    end
    return out
end

-- WHERE ONE OF THE NINE POSITIONS ACTUALLY PUTS A NUMBER, nudge included.
--
-- The inset keeps an outlined glyph off the border it sits in: a corner
-- position with no inset has its outline clipped by that edge, which reads as
-- a blurry number rather than as a placement problem.
--
-- The three NUMBERS get this. The spell name deliberately does not - it is
-- already inset by the icon gap, and two insets stacked is a name that lines
-- up with nothing.
function Text.Offset(text)
    local anchor = (text and text.anchor) or "CENTER"
    local inset = 2

    local x = (anchor:find("LEFT") and inset
        or anchor:find("RIGHT") and -inset or 0) + ((text and text.x) or 0)
    local y = (anchor:find("TOP") and -inset
        or anchor:find("BOTTOM") and inset or 0) + ((text and text.y) or 0)
    return x, y
end

---------------------------------------------------------------------------
-- Somebody else's font strings
---------------------------------------------------------------------------

-- EVERY FONT STRING A COUNTER HOLDS, whichever of the two shapes it is.
--
-- `item.ChargeCount` is a frame with the number inside it; `Icon.Applications`
-- IS the number. GetRegions is a FRAME method, so asking the second one for
-- its regions raises rather than answering nothing - which is how a finder
-- that knows about both places still ends up working on only one of them.
--
-- IsObjectType rather than "does it have GetText": the answer has to be the
-- same at the desk as in his client, and the harness's stub answers to every
-- method name there is.
local function Strings(widget)
    if type(widget) ~= "table" then return {} end
    if widget.IsObjectType and widget:IsObjectType("FontString") then
        return { widget }
    end

    local out = {}
    if type(widget.GetRegions) == "function" then
        for _, region in ipairs({ widget:GetRegions() }) do
            if region.IsObjectType and region:IsObjectType("FontString") then
                out[#out + 1] = region
            end
        end
    end
    return out
end

-- OUR FACE ON A STRING BLIZZARD OWNS, recorded so it can be given back.
--
-- Not ns.Media.ApplyFont, and that is the line that makes this wave legal at
-- all: ApplyFont calls SetFont and SetTextColor on the string directly, which
-- is the rule Claim.lua exists for. It stays the right call for our own
-- caption below and is wrong for every string in this function.
local function Face(fontString, text)
    Claim.Set(fontString, "SetFont", ns.Media.Font(text.font), text.size,
        text.outline)

    -- A font file that will not load leaves the string with NO face, and the
    -- next SetText raises rather than doing nothing. ApplyFont reads SetFont's
    -- own answer to catch that; through Claim.Set the answer is swallowed by
    -- the pcall, so the same question is put to the string afterwards.
    if fontString.GetFont and not fontString:GetFont() then
        local fallback = GameFontHighlight and GameFontHighlight:GetFont()
        if fallback then
            Claim.Set(fontString, "SetFont", fallback, text.size, text.outline)
        end
    end

    local colour = text.color
    Claim.Set(fontString, "SetTextColor", colour[1], colour[2], colour[3],
        colour[4] or 1)
end

---------------------------------------------------------------------------
-- The countdown, which is not there when you go looking for it
--
-- Weak keys throughout: these hold Blizzard's frames, and a strong table here
-- is how a pooled frame never gets collected.
--
-- The record carries the item, and that is a reference from a weak table's
-- VALUE back to something that reaches its own key - the entry cannot be
-- collected on a 5.1 weak table by itself. It is kept anyway and stated
-- rather than worked around: a frame in this client cannot be destroyed, so
-- what the weak key really buys is that a record never OUTLIVES its frame,
-- and the item is what answers the only question the callback has - has this
-- frame been given back since.
---------------------------------------------------------------------------
local remembered = setmetatable({}, { __mode = "k" })
local queued = setmetatable({}, { __mode = "k" })

-- WHICH WIDGETS ARE HOOKED, kept apart from the style they were hooked for.
--
-- Deriving it from "is there a record yet" reads like the same question and is
-- not: the record is DROPPED when the frame is given back, so a frame adopted,
-- released and adopted again would look like a first sight and take a second
-- hook. Hooks cannot be removed, so that is one more closure on the same
-- widget per spec change for the rest of the session.
local hooked = setmetatable({}, { __mode = "k" })

-- Both ways a cooldown can be armed on this patch. The second takes a secret
-- duration object and is what the Cooldown Manager uses for anything whose
-- timing is protected - hooking only the first would miss exactly the frames
-- this addon adopts.
local COOLDOWN_SETTERS = { "SetCooldown", "SetCooldownFromDurationObject" }

-- The remembered look, applied to whatever font strings the widget has NOW.
local function Paint(cooldown, text)
    -- CENTER at 0,0 is left alone: that is already where the engine puts its
    -- countdown, and re-anchoring it there can only go wrong.
    local move = not (text.anchor == "CENTER" and text.x == 0 and text.y == 0)
    local x, y = Text.Offset(text)

    for _, fontString in ipairs(Strings(cooldown)) do
        Face(fontString, text)
        if move then
            -- NOT reparented, only re-anchored. Moving one of these strings to
            -- another parent makes the engine re-centre it and ignore both the
            -- position and the offset.
            Claim.Anchor(fontString, text.anchor, cooldown, text.anchor,
                x, y)
        end
    end
end

-- `item` first so the desk guard watches this function: it is handed one of
-- Blizzard's frames, and a function that takes one under any other name is
-- outside the contract while looking inside it.
local function Countdown(item, cooldown, text)
    remembered[cooldown] = { item = item, text = text }

    -- Now, for a cooldown that is already running on it.
    Paint(cooldown, text)

    if hooked[cooldown] then return end
    hooked[cooldown] = true

    for _, setter in ipairs(COOLDOWN_SETTERS) do
        if type(cooldown[setter]) == "function" then
            hooksecurefunc(cooldown, setter, function(self)
                -- ONE QUEUED PASS PER WIDGET. A refresh can arm the same
                -- cooldown several times in a row, and one timer each would be
                -- a queue that grows with the fight. A frame later,
                -- deliberately: the engine builds the number during the draw
                -- that FOLLOWS the call, so doing it inline would still find
                -- nothing on the first cooldown of the session.
                if queued[self] then return end
                queued[self] = true

                C_Timer.After(0, function()
                    queued[self] = nil
                    local wanted = remembered[self]
                    if not wanted then return end

                    -- A FRAME WE HAVE GIVEN BACK IS SOMEBODY ELSE'S AGAIN. A
                    -- hook cannot be removed, so without this line releasing
                    -- the Cooldown Manager would leave a hook that re-applies
                    -- our face the next time Blizzard arms that frame - a mark
                    -- left by an addon that has just said it let go.
                    if not Cooldowns.Known(wanted.item) then
                        remembered[self] = nil
                        return
                    end
                    Paint(self, wanted.text)
                end)
            end)
        end
    end
end

---------------------------------------------------------------------------
-- The three numbers that are Blizzard's own
---------------------------------------------------------------------------

-- WHICH ELEMENT DRIVES WHICH COUNTER. Blizzard never puts both on one frame,
-- which is why the pairing is a list rather than an if: whichever one this
-- template carries is the one that gets styled, and the other is absent.
local COUNTERS = {
    { key = "ChargeCount",  element = "charges" },
    { key = "Applications", element = "stacks"  },
}

local function Counters(item, style)
    for _, pair in ipairs(COUNTERS) do
        local widget = ns.CDM:Counter(item, pair.key)
        local text = style[pair.element]

        if widget then
            -- Alpha, never Hide - the same rule as the item itself, and on the
            -- WIDGET rather than on the item or its icon: dimming either of
            -- those would take the numbers down with the picture.
            Claim.Set(widget, "SetAlpha", text.show and 1 or 0)

            for _, fontString in ipairs(Strings(widget)) do
                Face(fontString, text)
            end

            -- THE FRAME MOVES, NOT THE TEXT INSIDE IT. These counters are
            -- frames Blizzard anchors once, and the string inside is written
            -- by its own layout - re-anchoring that is a fight the engine wins
            -- every time the count changes. Moving the frame is one call that
            -- stays put and takes the number with it whatever Blizzard does.
            --
            -- Anchored to the ITEM, not to its icon, which is what 4.82.0 did
            -- and what his bars are arranged against: on a bar-shaped frame
            -- that puts a bottom-right counter at the end of the bar rather
            -- than on the square, and moving it now would move a number he
            -- has already placed.
            --
            -- NEVER TO OUR OWN CELL, AND THE VEIL IS NOT PIERCED. One
            -- version tried SetIgnoreParentAlpha plus an anchor onto the
            -- cell, so Blizzard's counter would show through the veiled
            -- item and the engine would feed it. It does not: the charges
            -- vanished from his bars and the stacks never arrived ("die
            -- aufladungen bei den bars jetzt auch weg") - the engine keys
            -- its counter updates on the ITEM it belongs to, not on whether
            -- the string itself could be seen. A place we draw writes its
            -- own numbers instead - Text.Count, the mechanism that was
            -- working before that detour.
            local x, y = Text.Offset(text)
            Claim.Anchor(widget, text.anchor, item, text.anchor, x, y)
        end
    end
end

-- THE THREE NUMBERS ON ONE ADOPTED FRAME. Font, colour, alpha and position -
-- never the text.
function Text.Apply(item, style)
    if not (item and style) then return end

    -- type-checked, not truth-checked: this is a member on somebody else's
    -- frame, and "whatever is there" is the only honest assumption.
    local cooldown = type(item.Cooldown) == "table" and item.Cooldown or nil
    if cooldown then
        -- Switched off at the source rather than hidden afterwards: the engine
        -- reads this before it builds the font string at all, so there is
        -- nothing left to chase around the screen.
        Claim.Set(cooldown, "SetHideCountdownNumbers",
            not style.countdown.show)

        if style.countdown.show then
            Countdown(item, cooldown, style.countdown)
        else
            -- The hook stays, because a hook cannot be removed - but with the
            -- record gone it reads nil on its first line and does nothing.
            -- Left in place it would go on re-applying a face for a number the
            -- user has just switched off.
            remembered[cooldown] = nil
        end
    end

    Counters(item, style)
end

---------------------------------------------------------------------------
-- The spell name, which is the only one of the four that is ours
--
-- Blizzard's icon frame does not carry a name, and a bar-shaped cell holding
-- nothing but a square icon in one corner reads as broken rather than as
-- deliberate. So this one is a font string of our own, on a layer over our own
-- cell, and it takes no Blizzard frame at all.
--
-- ITS NINE POSITIONS WERE THROWN AWAY. Both old renderers anchored it hard to
-- LEFT and ignored the setting, so the panel offered a control that could not
-- do anything - which is not a limitation, it is a broken control, and the
-- owner found it by trying it.
--
-- `iconWidth` nil means STAND DOWN, and Render is the only thing that knows
-- whether there is a band: a square slot has no room beside the icon, and a
-- buff-bar frame writes its own name along the bar already - ours on top of
-- that is the same word twice, pushed off the right-hand edge into an ellipsis
-- because the "icon" it makes room for is the whole frame.
---------------------------------------------------------------------------
function Text.Caption(cell, style, spellID, iconWidth, placement)
    local text = style and style.spellName
    if not (cell and text) then return end

    -- NIL STANDS DOWN, AND NOUGHT DOES NOT. A bar-shaped place with its icon
    -- switched off is still a bar with a name on it - Layout.LabelBand answers
    -- 5 and 5 for an icon width of nought - and reading the two as the same
    -- answer took the name off every bar whose owner had hidden the icon.
    if not (iconWidth and text.show) then
        if cell.caption then cell.caption:Hide() end
        return
    end

    if not cell.caption then
        -- A LAYER OF ITS OWN, ten levels up. The adopted frame is Blizzard's
        -- child rather than ours, so this cannot decide the whole stacking
        -- order - what it does decide is that the name draws over our own
        -- cell's background instead of under it.
        local layer = CreateFrame("Frame", nil, cell)
        layer:SetAllPoints(cell)
        layer:SetFrameLevel(cell:GetFrameLevel() + 10)

        cell.caption = layer:CreateFontString(nil, "OVERLAY")
        -- A name is a word, not a number: it has to be told where to stop or
        -- it runs across whatever is at the other end of the bar.
        cell.caption:SetWordWrap(false)
    end

    -- HUNG FROM BOTH EDGES OF THE BAND, NEVER GIVEN A WIDTH. A width is a
    -- number taken once: measured and handed to SetWidth, the box stayed the
    -- size it was when the bar was that size - the owner's "der container
    -- waechst nicht mit der bar breite mit, sondern ist fest".
    local left, right = ns.Layout.LabelBand(placement or "left", iconWidth)
    ns.PlaceLabel(cell.caption, cell, text, left, right)

    -- Our own font string, so the direct setter is the right one here and only
    -- here.
    ns.Media.ApplyFont(cell.caption, text.font, text.size, text.outline,
        text.color)
    cell.caption:SetText(ns.SpellName(spellID) or "")
    cell.caption:Show()
end

---------------------------------------------------------------------------
-- THE STACK COUNT, WHEN BLIZZARD HAS NO COUNTER TO SHOW ONE WITH
--
-- Owner, twice: "stack count wird immer noch nicht bei den buffs angezeigt."
--
-- WHY EVERY CONTROL ON THE STACK BLOCK WAS CORRECT AND NOTHING APPEARED.
-- On an adopted frame the number is Blizzard's own `Applications` frame and
-- NOTHING ELSE - this addon authors no number anywhere. The Show switch, the
-- face, the size, the colour and the position all write onto that frame
-- correctly, and every one of them is a way of styling something that is not
-- there. Alpha 1 on a frame Blizzard never made is still nothing, so the
-- switch could only ever hide.
--
-- 4.82.0 DID NOT HAVE THIS FAULT, and the reason is the shape this project
-- has paid for before: it drew its OWN font string on cells it drew itself
-- (Screen.lua:617-655, ApplyStackCount), and only leaned on Blizzard's frame
-- for the ones it had adopted. Every cell is adopted now. Deleting the second
-- renderer deleted the only thing that ever wrote a stack number - the
-- setting kept its reader and lost its writer.
--
-- THE "NOT WORTH A NUMBER" RULE IS BLIZZARD'S TO MAKE, and that is not
-- deference: the count is a SECRET VALUE on this patch, so "is it more than
-- one" may not be asked here at all. Blizzard asks it inside the engine and
-- answers by HIDING its counter frame, and a frame's visibility is a plain
-- boolean that touching is legal.
--
--   shown == true    Blizzard is drawing it. We draw nothing - two numbers in
--                    one corner is worse than none.
--   shown == false   Blizzard looked and decided it is not worth showing.
--                    That IS the comparison; we do not second-guess it.
--   shown == nil     there is no counter frame to ask. Ours, under the same
--                    rule 4.82.0 used: compare when the count is readable,
--                    and when it is secret SHOW it, because guessing that a
--                    protected count is 1 hides a real one for a whole fight.
---------------------------------------------------------------------------
-- PURE, AND THE WHOLE DECISION. Split out from the drawing below because
-- this is the half that can be PROVED at a desk with no screen - the same
-- division Effects.lua draws through its own file, and for the same reason:
-- three of the four branches here are about a value that may not be looked
-- at, and "it seemed right when I read it" is how the extra 0 shipped in
-- 4.82.0.
--
--   shown   what Blizzard says about ITS counter frame: true, false or nil
--   count   ns.CDM:ItemStacks, which may be a secret or nil
--
-- Returns the value to draw, or nil for "draw nothing". The value is passed
-- straight to SetFormattedText and is never compared here unless CanCompute
-- has already said it may be.
-- HOW MANY CHARGES ARE UP, or nil.
--
-- Its own reader because the two numbers come from opposite places: a stack
-- count lives on the aura and is read off the frame, a charge count is the
-- SPELL's and is read off the API. Fill.MaxCharges already asks this question
-- for the charge marks; this asks the same call for the other half of its
-- answer, and the same guards apply - the count can be secret in restricted
-- content and `most <= 1` is not a number worth a corner.
function Text.ChargesUp(spellID)
    local get = C_Spell and C_Spell.GetSpellCharges
    if not (get and ns.CanCompute(spellID)) then return nil end

    local ok, charges = pcall(get, spellID)
    if not (ok and type(charges) == "table") then return nil end

    -- A SPELL WITH ONE CHARGE HAS NO CHARGE COUNT. Blizzard draws none and
    -- neither do we: "1" under every icon on the bar is noise on every icon
    -- to say something about none of them.
    local most = charges.maxCharges
    if not (ns.CanCompute(most) and type(most) == "number" and most > 1) then
        return nil
    end

    local now = charges.currentCharges
    if now == nil then return nil end
    return now
end

-- `ours` says WE are drawing this place - Own.lua - which changes exactly one
-- of the four branches and did silently empty the corner it fills when it was
-- taken out.
--
-- On a place we draw, Blizzard's frame for the same spell is veiled at alpha
-- 0. Its counter frame is still SHOWN in the sense the API means, so without
-- `ours` the first branch reads "Blizzard is already drawing one" and stands
-- down - and the number goes missing. The frame being shown is not the
-- question. Whether the USER can see it is, and on our own place he cannot:
-- piercing the veil (SetIgnoreParentAlpha onto our cell) was tried and the
-- engine still fed it nothing, because its updates key on the ITEM, not on
-- the string's own visibility.
--
-- The other half of that branch survives untouched and has to: `shown ==
-- false` is Blizzard saying it looked at a count we may not look at ourselves
-- and decided it was not worth a number. That IS the comparison, it is the
-- only legal one on this patch, and it stays final on both kinds of place.
function Text.StackToShow(shown, count, ours)
    if shown == true and ours then
        -- Blizzard would draw it and cannot be seen doing so. Its comparison
        -- has already said yes, so the count goes straight out - possibly a
        -- secret, which is why it reaches SetFormattedText and nothing else.
        return count
    end

    -- BLIZZARD'S ANSWER IS FINAL EITHER WAY. `true` means it is already
    -- drawing one and a second number in the same corner is worse than none;
    -- `false` means it looked at a count we may not look at ourselves and
    -- decided there is nothing worth showing, which IS the comparison this
    -- code may not make. Only nil - no counter frame at all - leaves the
    -- question to us.
    if shown ~= nil then return nil end
    if count == nil then return nil end

    if ns.CanCompute(count) and type(count) == "number" then
        -- Readable, so the comparison is ours and it is the same one
        -- Blizzard makes: a single application is not worth a corner.
        if count > 1 then return count end
        return nil
    end

    if ns.CanDisplay(count) then
        -- SECRET. It may not be compared and there is no counter frame to
        -- ask instead, so it is shown. 4.82.0's own note: guessing that a
        -- protected count is 1 hides a real stack count for a whole fight.
        return count
    end

    return nil
end

-- BOTH NUMBERS, and one function because they differ in exactly two places:
-- which Blizzard counter would have drawn it, and where the value comes from.
--
-- Owner: "empowered rune weapon hat 2 aufladungen ... da muesste eine 2
-- irgendwo sein." Charges were the half this addon still could not draw: the
-- stack half landed first and the same hole was left under it.
local NUMBERS = {
    { key = "stacks",  member = "Applications", field = "stackCount",
      Value = function(item, spellID, ours)
          -- NOT `ItemStacks(item) or nil`. The count this answers can be a
          -- SECRET, and `X or nil` is a boolean test on X - the same raise
          -- as CDM.lua:1103, four times in his chat, one wave ago. The
          -- `and .. or` shape cannot carry a secret for the same reason it
          -- cannot carry false.
          local count
          if ns.CDM.ItemStacks then count = ns.CDM:ItemStacks(item) end
          return Text.StackToShow(
              ns.CDM:CounterShown(item, "Applications"), count, ours)
      end },
    { key = "charges", member = "ChargeCount", field = "chargeCount",
      Value = function(item, spellID, ours)
          -- A DIFFERENT GATE FROM THE STACKS, AND THE ASYMMETRY IS THE POINT.
          --
          -- For a stack count we defer to Blizzard COMPLETELY, because the
          -- count is a secret value: "is it worth a number" cannot be asked
          -- here at all, and Blizzard hiding its own counter IS that
          -- comparison. Deferring is the only honest thing to do.
          --
          -- A charge count is not secret. C_Spell.GetSpellCharges answers
          -- maxCharges and currentCharges in plain numbers, so the comparison
          -- is ours to make and we do not need Blizzard to make it for us.
          -- The only thing we still owe it is not to draw a SECOND number
          -- beside one it is already drawing.
          --
          -- Which is why this asks `== true` and the stacks ask `~= nil`. The
          -- frame EXISTING is not the question - his own bar has one on all
          -- three places and shows no number on any of them.
          --
          -- AND NOT ON A PLACE WE DRAW. The only thing we owe Blizzard here
          -- is not putting a second number beside one of its own; on our own
          -- bar there is no visible first one to sit beside - the item is
          -- veiled, and the engine does not feed a veiled item's counter
          -- even when the counter itself is told to ignore the alpha. This
          -- `not ours` went out once, and the charges went out with it:
          -- "die aufladungen bei den bars jetzt auch weg".
          if not ours and ns.CDM:CounterShown(item, "ChargeCount") == true then
              return nil
          end
          return Text.ChargesUp(spellID)
      end },
}

-- TWO DETOURS DIED HERE AND NEITHER MAY COME BACK. The RELAY read Blizzard's
-- counter string off the veiled frame, and the string was empty with the
-- stacks plainly up ("es wird nix angezeigt") - the engine does not write
-- text into a counter nobody can see, and you cannot copy what is never
-- written. The VEIL-PIERCING then made the counter itself visible
-- (SetIgnoreParentAlpha, anchored onto our cell) so the engine would feed it
-- - and it still did not ("die aufladungen bei den bars jetzt auch weg"):
-- its updates key on the ITEM, not on the string's own visibility. So a
-- place we draw writes its own numbers from sources this addon can hold -
-- the charge API in plain numbers, a stack count wherever a reader answers -
-- which is the mechanism that was already working before either detour.
--
-- `ours` is true when Own.lua drew this place rather than Claim adopting it.
-- It changes nothing about how a number is drawn and one thing about whether
-- one is - see Text.StackToShow.
function Text.Count(cell, item, style, spellID, ours)
    if not (cell and item and style) then return end

    for _, number in ipairs(NUMBERS) do
        local text = style[number.key]
        local field = number.field

        local function Away()
            if cell[field] then
                cell[field]:SetText("")
                cell[field]:Hide()
            end
        end

        -- A PLAIN if, NOT `.. and Value() or nil`. Value can answer a SECRET
        -- - that is the whole CanDisplay branch of StackToShow - and the
        -- `or` would boolean-test it, which raises. This function's entire
        -- promise is that a secret passes through it into SetFormattedText
        -- and is never looked at on the way.
        local value
        if text and text.show then
            value = number.Value(item, spellID, ours)
        end

        if value == nil then
            Away()
        else
            if not cell[field] then
                -- A LAYER OF ITS OWN, ten levels up, exactly as the caption.
                -- The adopted frame is Blizzard's child rather than ours, so
                -- this cannot decide the whole stacking order - what it
                -- decides is that the number draws over our own cell rather
                -- than under it.
                local layer = CreateFrame("Frame", nil, cell)
                layer:SetAllPoints(cell)
                layer:SetFrameLevel(cell:GetFrameLevel() + 10)

                cell[field] = layer:CreateFontString(nil, "OVERLAY")
                cell[field]:SetWordWrap(false)
            end

            -- Our own font string, so the direct setter is right here.
            ns.Media.ApplyFont(cell[field], text.font, text.size, text.outline,
                text.color)

            local x, y = Text.Offset(text)
            cell[field]:ClearAllPoints()
            cell[field]:SetPoint(text.anchor, cell, text.anchor, x, y)

            -- SetFormattedText, NEVER SetText(tostring(value)). The engine
            -- formats a secret without ever handing it to us; tostring on one
            -- is the raise. pcall because a font string with no face raises
            -- on being written to, and a missing media file is a user's
            -- problem rather than an error.
            if pcall(cell[field].SetFormattedText, cell[field],
                    "%d", value) then
                cell[field]:Show()
            else
                Away()
            end
        end
    end
end

---------------------------------------------------------------------------
-- /zs text and /zs numbers, answered together
--
-- Three separate fixes for "the position does nothing" were made by reading
-- the code and reasoning about it, and each came back reported still broken.
-- That is the lesson arriving a third time: a rule that cannot be run gets
-- diagnosed by reading, and reading keeps being wrong. So this asks the
-- frames.
--
-- Per placed cell and per element: what the setting asked for, where the
-- widget's own first anchor actually is, whether we have styled it, whether
-- Blizzard is showing it, and what it reads.
---------------------------------------------------------------------------

-- WHAT A STRING READS, WITHOUT READING IT.
--
-- A counter's text can be a secret: it was formatted from one by the engine,
-- and comparing it or calling tostring on it is itself the raise. `== nil` is
-- the one comparison Secrets.lua makes on a possibly-secret value, so it is
-- the one allowed to tell "absent" and "protected" apart - and it has to
-- happen BEFORE the empty-string test, not after. The old DumpNumbers had
-- these the wrong way round and broke its own rule eight lines under the
-- comment that states it.
local function Says(fontString)
    if not fontString then return "|cff888888none|r" end

    local ok, text = pcall(fontString.GetText, fontString)
    if not ok then return "|cff888888unreadable|r" end

    if not ns.CanCompute(text) then
        if text == nil then return "|cff888888blank|r" end
        return "|cffff7a3dSECRET|r (the engine formatted it, we never saw it)"
    end
    if text == "" then return "|cff888888blank|r" end
    return "\"" .. tostring(text) .. "\""
end

local function Landed(region, text)
    local point, _, _, x, y = region:GetPoint(1)
    return string.format("asked |cff7ec6d4%s|r %.0fpx  got |cff7ec6d4%s|r "
        .. "at %.0f,%.0f", text.anchor, text.size, tostring(point),
        x or 0, y or 0)
end

local function ReportCountdown(item, text)
    local cooldown = item.Cooldown
    if not cooldown then
        ns.Print("   countdown |cff888888this frame has no Cooldown widget|r")
        return
    end

    local numbers = Strings(cooldown)
    if #numbers == 0 then
        ns.Print(string.format("   %-9s asked |cff7ec6d4%s|r %.0fpx  "
            .. "|cff888888the engine has not built the number yet - it does "
            .. "not exist until a cooldown runs|r",
            "countdown", text.anchor, text.size))
        return
    end

    for _, fontString in ipairs(numbers) do
        ns.Print(string.format("   %-9s %s  ours %s  reads %s", "countdown",
            Landed(fontString, text),
            Claim.Touched(fontString) and "|cff40ff40yes|r" or "|cffff4040no|r",
            Says(fontString)))
    end
end

local function ReportCounter(item, key, what, text, mine)
    local widget = ns.CDM:Counter(item, key)
    if not widget then
        ns.Print(string.format("   %-9s |cff888888this frame carries no %s - "
            .. "Blizzard puts one on a cooldown and the other on a buff|r",
            what, key))
        return
    end

    -- nil is a THIRD answer and is printed as one. Read as false it would say
    -- "Blizzard is hiding it", which is the opposite of "there is nothing to
    -- ask" and is how a real count gets talked out of being shown.
    local shown = ns.CDM:CounterShown(item, key)

    ns.Print(string.format("   %-9s %s  ours %s  blizzard shows it %s  reads %s",
        what, Landed(widget, text),
        Claim.Touched(widget) and "|cff40ff40yes|r" or "|cffff4040no|r",
        shown == nil and "|cff888888nothing to ask|r" or tostring(shown),
        Says(ns.CDM:CounterText(item, key))))

    -- AND THE STRING WE DRAW, when there is one. The line above measures
    -- BLIZZARD'S widget, and on a place we draw ourselves that widget is
    -- under the veil and was never moved - so "asked LEFT, got BOTTOMRIGHT"
    -- there is not a fault, it is the wrong object being measured. His dump
    -- read exactly like a mis-anchoring until the second line existed.
    if mine then
        if mine:IsShown() then
            ns.Print(string.format("   %-9s %s  |cff888888(the one we "
                .. "draw)|r  reads %s", "", Landed(mine, text), Says(mine)))
        else
            ns.Print(string.format("   %-9s |cff888888our own string is "
                .. "hidden - nothing to draw or relay right now|r", ""))
        end
    end
end

local function ReportCaption(cell, text)
    local label = cell and cell.caption
    if not label then
        ns.Print("   name      |cff888888no caption on this cell - the name is "
            .. "only drawn beside an icon in a bar-shaped slot|r")
        return
    end

    ns.Print(string.format("   %-9s %s  ours |cff40ff40yes|r  reads %s",
        "name", Landed(label, text), Says(label)))
end

function Text.Dump()
    ns.Print("|cffffd100--- text: asked for / where it landed / what it reads ---|r")

    if not (ns.CDM.IsAvailable and ns.CDM:IsAvailable()) then
        ns.Print("|cffff4040Cooldown Manager unavailable|r - "
            .. (ns.CDM:UnavailableReason() or "reason unknown"))
        return
    end

    -- At call time rather than at file scope: Render loads after this file.
    local containers = Cooldowns.Render.Containers()
    local said = 0

    for _, bar in pairs(Store.Bars()) do
        if type(bar) == "table" and bar.id then
            local style = Text.Style(bar, Store.Lattice(bar).size)
            local cells = Store.Cells(bar)
            local container = containers[bar.id]

            for index = 1, Store.Capacity(bar) do
                local spellID = cells[index]
                local item = ns.CDM:ItemForSpell(spellID)

                if item then
                    said = said + 1
                    ns.Print(string.format("|cffffd100%s %d|r  %s",
                        bar.name or ("bar " .. tostring(bar.id)), index,
                        ns.SpellName(spellID) or "?"))

                    local cell = container and container.cells[index]
                    ReportCountdown(item, style.countdown)
                    ReportCounter(item, "ChargeCount", "charges",
                        style.charges, cell and cell.chargeCount)
                    ReportCounter(item, "Applications", "stacks",
                        style.stacks, cell and cell.stackCount)
                    ReportCaption(cell, style.spellName)
                end
            end
        end
    end

    if said == 0 then
        ns.Print("|cff888888No cell on any bar has a live frame right now, so "
            .. "there is nothing to measure. /zs cdm says whether Blizzard is "
            .. "showing anything at all.|r")
        return
    end

    ns.Print("|cff888888Three of the four are Blizzard's own font strings and "
        .. "we only set a face, a colour and a point on them - so a line that "
        .. "reads SECRET is the count doing exactly what it should. A count "
        .. "marked SECRET may not be compared to anything, which is why "
        .. "'blizzard shows it' is the only honest answer to 'should this "
        .. "number be here'.|r")
end
