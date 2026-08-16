---------------------------------------------------------------------------
-- OptionsCooldownsBar.lua - the four blocks that say what one bar LOOKS like.
--
-- Waves 4 and 5 landed Look, Text, Effects and Fill, and Render drives all
-- four on every pass. Not one of their settings had a row: every one of them
-- was a key only a profile editor could reach, on a page whose whole job is to
-- be the profile editor. These are the rows.
--
-- FOUR BUILDERS RATHER THAN ONE SECTION, and that is not tidiness.
-- OptionsCooldowns.lua's own header says why: the page this replaces was
-- 2 710 lines on ONE page, and the owner said in as many words that THAT was
-- the defect and not the number of knobs. So the knobs come back in folding
-- sections, one subject each, and the four blocks are called from the page
-- rather than living inside it.
--
---------------------------------------------------------------------------
-- WHAT IS DELIBERATELY NOT OFFERED. Three things, and each was checked
-- against the file that would have to draw it rather than assumed.
--
--   THE SPELL NAME. Text.Caption is written, commented and diagnosed, and it
--   has NO CALLER: Render.DrawBar dresses a cell with Fill, Text, Look and
--   Effects and never asks for a caption. Its eight settings would be eight
--   controls that do nothing. Unlike the two below, nothing at run time can
--   tell whether it has been wired since - so there is no row AND no sentence
--   about it either. A warning that cannot notice it has come true is worse
--   than none, because the day it is wrong is the day somebody believes it.
--
--   "OVER TIME" on a fill. fillGrow needs Claim.Grow, and Claim.lua has Fill
--   and OnGive and not that one - Look.Door prints one line about it and
--   skips the work. That IS askable at run time, so the row below is built
--   the day the door lands and not one release before it.
--
--   THE LAST SECONDS. lowWarn and lowColor are absent from Effects.ANSWERED
--   and its own comment says the absence is the statement: with every cell
--   adopted there is no remaining time to read. Every effects row here is
--   built FROM that table, so this is not a list somebody has to remember to
--   keep in step - it is the same fact, read once.
--
---------------------------------------------------------------------------
-- ROWS THAT COME AND GO, and the rule is written down once because it is a
-- decision rather than a detail:
--
--   a row that is the DETAIL of a switch above it - how many pulses, how
--   grey, how many squares - is not there while its switch is off. It has
--   nothing to say and the section reads shorter without it.
--
--   a row that is a setting in its OWN right but needs something else to have
--   an effect - closing a gap needs something being taken off screen - STAYS,
--   and says so on itself. Hiding that one means somebody looking for it
--   finds nothing at all and concludes the addon cannot do it.
--
-- Which of the two a row is decides whether its sentence is on the page or in
-- the hover, and that is the owner's rule: a limit, a warning or a "this
-- needs the other thing switched on" is a fact you act on and has to be
-- readable without pointing at anything. The reasoning behind a default is
-- not, and it goes in the tooltip.
---------------------------------------------------------------------------
local _, ns = ...

local UI = ns.UI

local Panel = {}
ns.OptionsCooldownsBar = Panel

-- Asked for by name at call time, exactly as OptionsCooldowns.lua does it.
-- This file loads well below all four of them, so a file-scope capture would
-- work today - and a TOC reorder would make it nil on the next login with
-- nothing out here saying a word. Render.lua's header says the same thing
-- about the three IT captures, and it captures them on purpose.
local function Store() return ns.Cooldowns and ns.Cooldowns.Store end
local function Texts() return ns.Cooldowns and ns.Cooldowns.Text end
local function Fx() return ns.Cooldowns and ns.Cooldowns.Effects end
local function Fills() return ns.Cooldowns and ns.Cooldowns.Fill end

-- The same three lines OptionsCooldowns.lua keeps as a local. Written out
-- rather than reached for across the file boundary, because it is not
-- exported there - and a page that repainted the WINDOW without repainting
-- the BARS would leave every control on it looking like it had done nothing.
local function Refresh()
    if ns.Cooldowns and ns.Cooldowns.Render then
        ns.Cooldowns.Render.Refresh()
    end
    ns.Options:Refresh()
end

-- THE BAR THESE ROWS ARE ABOUT, ASKED EVERY TIME.
--
-- `bar` is handed in when the block is built, and a page in this window is
-- built exactly ONCE: Options.ShowPage sets entry.built and nothing ever
-- clears it. A getter that closed over the table it was handed would go on
-- reading whichever bar happened to be selected the first time the window was
-- opened, so every slider here would edit a bar the preview above it is not
-- showing - and the page would look like it had stopped saving.
--
-- The handed-in table is the FALLBACK rather than the source, so a caller
-- that means one particular bar still gets it when the page has no selection.
local function Bar(fallback)
    local page = ns.OptionsCooldowns
    local current = page and page.Current and page.Current()
    if current then return current end
    return fallback
end

-- WHAT IS STORED, OR WHAT THE ADDON DOES WITHOUT IT.
--
-- `value ~= nil`, never `stored and value or fallback`. Several of the
-- settings below default to TRUE - the plate, the combat-only glow, the
-- greying while inactive - and `x and y or z` cannot carry false: a stored
-- `false` would collapse back into the default and come back ON, and no
-- amount of clicking the switch would change it. Effects.Option is this exact
-- function one folder down and its comment says the same thing.
local function Stored(source, key, fallback)
    if type(source) == "table" then
        local value = source[key]
        if value ~= nil then return value end
    end
    return fallback
end

---------------------------------------------------------------------------
-- The control shapes
--
-- Four of them, pointed at a bar that is resolved on every read. A slider
-- passes `apply` rather than refreshing inside its setter: BuildSlider's
-- Commit calls set and THEN apply, so a refreshing setter would repaint
-- twice per drag step.
---------------------------------------------------------------------------
local function Get(bar, key, fallback)
    return function() return Stored(Bar(bar), key, fallback) end
end

local function Put(bar, key)
    return function(value)
        local current = Bar(bar)
        if type(current) == "table" then current[key] = value end
    end
end

local function Switch(grid, bar, label, key, fallback, opts)
    local write = Put(bar, key)
    return UI.Toggle(grid:Row(label, opts), Get(bar, key, fallback),
        function(value) write(value) Refresh() end)
end

local function Slide(grid, bar, label, key, spec, opts)
    return UI.Slider(grid:Row(label, opts), {
        min = spec.min, max = spec.max, step = spec.step,
        format = spec.format, scale = spec.scale,
        get = Get(bar, key, spec.fallback),
        set = Put(bar, key),
        apply = Refresh,
    })
end

local function Choice(grid, bar, label, key, options, fallback, opts)
    return UI.Dropdown(grid:Row(label, opts), options,
        Get(bar, key, fallback), Put(bar, key), { apply = Refresh })
end

-- ALWAYS THREE NUMBERS OUT. A stored colour that is not a table at all - an
-- older shape, a hand-edited profile - falls back to the renderer's own
-- default, and white for a key that names no colour at all: the alternative
-- is three nils reaching SetColorTexture, which paints nothing and reads on
-- screen as "the swatch is broken" rather than as "that key is not a colour".
-- Effects.Colour makes the same two steps for the same reason.
local function Colour(grid, bar, label, key, fallback, opts)
    return UI.Swatch(grid:Row(label, opts),
        function()
            local colour = Stored(Bar(bar), key, fallback)
            if type(colour) ~= "table" then colour = fallback end
            if type(colour) ~= "table" then return 1, 1, 1 end
            return colour[1] or 1, colour[2] or 1, colour[3] or 1
        end,
        function(r, g, b)
            local current = Bar(bar)
            if type(current) == "table" then current[key] = { r, g, b } end
        end,
        Refresh)
end

local function Picture(grid, bar, label, kind, key, fallback, icon, inherit)
    return UI.MediaPicker(
        grid:FullRow(label, { controlWidth = 190, icon = icon }), kind,
        Get(bar, key, fallback), Put(bar, key), Refresh, inherit)
end

-- THE SMALLEST A NUMBER WITH AN OUTLINE CAN BE READ AT. Measured on his own
-- screenshot rather than chosen: the outline eats a pixel on each side, so
-- below this the glyph is two pixels of colour between two of black.
local TEXT_FLOOR = 6

local function Percent(value)
    return string.format("%d%%", math.floor((value or 0) * 100 + 0.5))
end

-- FLOORED BEFORE %d, and not for tidiness: the value box is typed into as
-- well as dragged, so a whole number is what the step promises rather than
-- what the control guarantees.
local function Seconds(value)
    if (value or 0) <= 0 then return ns.L["off"] end
    return string.format("%ds", math.floor(value))
end

-- 0 IS A REAL ANSWER AND IT HAS A NAME. Text.Element turns a size of nought
-- into a share of the cell height, which is what keeps a 24px bar and a 64px
-- icon looking like one design - so the number nought has to read as the
-- setting it is rather than as an empty box.
local function AutoSize(value)
    if (value or 0) <= 0 then return ns.L["auto"] end
    return string.format("%d", math.floor(value))
end

---------------------------------------------------------------------------
-- Rows that appear and disappear
--
-- Recomputed from the settings on every pass and never read back off dkSkip:
-- a flag left over from the last refresh is how a row hidden once stays
-- hidden for the rest of the session. Both calls are needed - Grid:Layout
-- skips a dkSkip block without hiding it, so a region that is not also told
-- to hide stays painted where it last stood.
---------------------------------------------------------------------------
local function Reveal(groups)
    for _, group in ipairs(groups) do
        local shown = group.when() and true or false
        for _, region in ipairs(group.rows) do
            region.dkSkip = not shown
            region:SetShown(shown)
        end
    end
end

local function OnRefresh(grid, fn)
    grid.widgets[#grid.widgets + 1] = { Refresh = fn }
end

-- A row that may not exist - an effect nothing answers for - must not join a
-- reveal group as a nil, or the group's own loop would stop at it.
local function Keep(list, region)
    if region then list[#list + 1] = region end
    return region
end

---------------------------------------------------------------------------
-- The places that carry their own answer
--
-- The renderer takes a place's own answer FIRST and the bar only afterwards,
-- so a place with an override of its own does not move when these rows do.
-- That is not hypothetical and it is not rare: his "Bars 2" carries fillColor,
-- chargeMarks, showSpark, fillGradient and stackThresholds on place 1 and
-- fillColor, fillGrow and showSpark on place 2, and the bar underneath them
-- carries none of it - so on that one bar most of the fill block would look
-- like it had stopped working.
--
-- ASKED OF Store.Own RATHER THAN OF cellOpts. This used to walk `cellOpts`
-- itself, which was the whole story while there was one place styling could
-- live in. There are two now - the per-SPELL table the per-place editor writes
-- and 4.82.0's per-slot one - and a counter that knew about only the old one
-- would go quiet exactly when somebody used the new one. Store.Own knows both
-- because it is the same reader the renderer uses.
--
-- Editing a single place is a later wave (OptionsCooldowns.lua's header names
-- it). Until it exists, the honest thing is to say the places are there, and
-- to say it only when they are.
---------------------------------------------------------------------------
local function Overrides(bar, keys)
    local store = Store()
    if not (type(bar) == "table" and store) then return 0 end

    local count = 0
    for index = 1, store.Capacity(bar) do
        for _, key in ipairs(keys) do
            local _, carried = store.Own(bar, index, key)
            if carried then
                count = count + 1
                break
            end
        end
    end
    return count
end

local function OverrideNote(grid, bar, keys)
    local L = ns.L
    local note = grid:Note(L["Some places on this bar carry a look of their "
        .. "own and keep it. What you change here reaches every other place."])

    OnRefresh(grid, function()
        local shown = Overrides(Bar(bar), keys) > 0
        note.dkSkip = not shown
        note:SetShown(shown)
    end)
    return note
end

---------------------------------------------------------------------------
-- The gradient trio
--
-- A switch, a second colour and which way the ramp runs, with the last two
-- gone while the switch is off. ns.Tint and ns.CreateBorder's SetTint both
-- read { on, color, direction }, so this is the same three rows the co-tank
-- panel has, pointed at a bar instead of at the panel.
---------------------------------------------------------------------------
local function GradientRows(grid, bar, key, groups, note)
    local L = ns.L

    local function Ramp()
        local current = Bar(bar)
        local ramp = current and current[key]
        return type(ramp) == "table" and ramp or nil
    end

    local function Field(field, fallback)
        return function()
            local ramp = Ramp()
            if not ramp then return fallback end
            local value = ramp[field]
            if value == nil then return fallback end
            return value
        end
    end

    -- The table is made on the first WRITE and never on a read: Store's whole
    -- promise is that nothing is rewritten, and a bar that grew an empty
    -- gradient by being looked at is a rewrite.
    local function Write(field, value)
        local current = Bar(bar)
        if type(current) ~= "table" then return end
        if type(current[key]) ~= "table" then current[key] = {} end
        current[key][field] = value
    end

    local on = Field("on", false)

    UI.Toggle(grid:Row(L["Gradient"], { sublabel = note }), on,
        function(value) Write("on", value) Refresh() end)

    local rows = {
        UI.Swatch(grid:Row(L["Second colour"]),
            function()
                local colour = Field("color", nil)()
                if type(colour) ~= "table" then colour = { 1, 1, 1 } end
                return colour[1] or 1, colour[2] or 1, colour[3] or 1
            end,
            function(r, g, b) Write("color", { r, g, b }) end,
            Refresh),

        UI.Dropdown(grid:Row(L["Runs"]), ns.GRADIENT_DIRECTIONS,
            Field("direction", "right"),
            function(value) Write("direction", value) end,
            { apply = Refresh }),
    }

    groups[#groups + 1] = { when = on, rows = rows }
end

---------------------------------------------------------------------------
-- Look - what one adopted frame is dressed in
--
-- Sixteen of Look.KEYS' eighteen. The other two - fillDirection and fillGrow
-- - are about a bar's FILL, and somebody looking for which way a bar runs
-- opens the block called the fill. One control per key, in the place the
-- question is asked, which is also why this list is not Look.KEYS itself: it
-- is what the OVERRIDE check below has to look for, and the two that moved
-- are checked over there.
---------------------------------------------------------------------------
local LOOK_KEYS = {
    "alpha", "backdrop", "backdropAlpha", "backdropColor", "backdropGradient",
    "backdropTexture", "borderColor", "borderGradient", "borderSize",
    "borderTexture", "iconZoom", "inactiveAlpha", "inactiveDesaturate",
    "showEdge", "swipeAlpha", "swipeColor",
}

-- EACH OF THE FOUR OPENS ITS OWN TAB, and a tab boundary also ends whatever
-- section was open - see the note on Grid:Tab. Without one, all fifteen of
-- these headings sat in a single column under the three the page proper
-- brings, which is the screen the owner could not work on.
function Panel.BuildLook(grid, bar)
    local L = ns.L
    local groups = {}

    grid:Tab(L["Look"])
    grid:Section(L["The icon"], "cd-look-icon", true)
    OverrideNote(grid, bar, LOOK_KEYS)

    -- IT STOPS AT A TENTH, and nought is deliberately not on the rail even
    -- though Look.Opacity reaches Claim.Veil with it. A bar has two ways to
    -- be gone already - its own switch under "Your bars", and a show rule -
    -- and both of them say so somewhere. A slider dragged to the end says
    -- nothing at all: the bar is simply not there, and the one place that
    -- could explain it is the page you have just left.
    Slide(grid, bar, L["Opacity"], "alpha",
        { min = 0.1, max = 1, step = 0.05, format = Percent, scale = 100,
          fallback = 1 })

    Slide(grid, bar, L["Crop"], "iconZoom",
        { min = 0, max = 0.2, step = 0.01, format = Percent, scale = 100,
          fallback = 0.08 })
    grid:Note(L["Blizzard's icon art has a border baked into the file. "
        .. "Cropping cuts it off; at 0 you see the whole thing, frame and "
        .. "all. Above a fifth it starts eating the picture instead."])

    Slide(grid, bar, L["While inactive"], "inactiveAlpha",
        { min = 0, max = 1, step = 0.05, format = Percent, scale = 100,
          fallback = 0.55 })
    Switch(grid, bar, L["Grey out while it is down"], "inactiveDesaturate",
        true)
    grid:Note(L["A tracked buff BAR stays on screen while its aura is down, "
        .. "so these two reach it. A buff ICON does not - Blizzard takes the "
        .. "frame away entirely and there is nothing left to dim."])

    grid:Section(L["Border"], "cd-look-border", true)

    Slide(grid, bar, L["Thickness"], "borderSize",
        { min = 0, max = 4, step = 1, fallback = 1 })
    Colour(grid, bar, L["Colour"], "borderColor", { 0, 0, 0 })
    GradientRows(grid, bar, "borderGradient", groups,
        L["Only the one-pixel line - an edge file takes one colour"])
    Picture(grid, bar, L["Texture"], "border", "borderTexture", "None",
        "media-border")
    grid:Note(L["None is a crisp one-pixel line drawn from colour textures, "
        .. "and it stays sharper than any edge file at small sizes. The rest "
        .. "come from whatever your other addons registered."])

    grid:Section(L["Behind the icon"], "cd-look-plate", true)
    grid:Note(L["A plate under the art. Spell art is opaque and fills its "
        .. "place, so you only see this where the art does not cover it - "
        .. "along a border, and behind a bar-shaped place."])

    Switch(grid, bar, L["Show"], "backdrop", true)
    Colour(grid, bar, L["Colour"], "backdropColor", { 0, 0, 0 })
    GradientRows(grid, bar, "backdropGradient", groups)
    Slide(grid, bar, L["Opacity"], "backdropAlpha",
        { min = 0, max = 1, step = 0.05, format = Percent, scale = 100,
          fallback = 0.9 })
    -- WITH A WAY BACK. ns.PaintSurface treats an unknown or empty key as a
    -- flat colour fill, which is sharper on a square than a bar texture
    -- stretched over one - and without a row for it a picker is one-way:
    -- every entry in the library is a texture, so a plate that had one could
    -- never be given none again.
    Picture(grid, bar, L["Texture"], "statusbar", "backdropTexture", nil,
        "media-texture", L["Flat colour"])

    grid:Section(L["The cooldown sweep"], "cd-look-sweep", true)

    Colour(grid, bar, L["Colour"], "swipeColor", { 0, 0, 0 })
    Slide(grid, bar, L["Opacity"], "swipeAlpha",
        { min = 0, max = 1, step = 0.05, format = Percent, scale = 100,
          fallback = 0.7 })
    Switch(grid, bar, L["Leading edge"], "showEdge", false,
        { sublabel = L["The bright line the sweep drags behind it"] })

    -- Once here as well as on every refresh: a page whose builder has just
    -- run has never been through Grid:Refresh, so without this the rows that
    -- belong to a switched-off gradient are on screen until something else
    -- happens to repaint.
    Reveal(groups)
    OnRefresh(grid, function() Reveal(groups) end)
end

---------------------------------------------------------------------------
-- Text - three numbers that are Blizzard's own
--
-- ONE LIST, THREE TIMES OVER. Written out three times, the fourth copy is
-- where a field goes missing - and a countdown you can move beside a stack
-- count you cannot is the kind of arbitrary limit that sends somebody looking
-- for another addon.
--
-- The spell name is the fourth element and it is not in this list. See the
-- header: Text.Caption has no caller.
--
-- `inherit` IS A COPY OF A FACT THAT LIVES IN Text.lua's OWN ELEMENTS, and it
-- is the only one in this file. It cannot be read from there - the resolver is
-- a local - and it cannot be skipped either: a bar written before charges and
-- stacks were split carries no `charges` at all, so a page that read only
-- `bar.charges` would show the defaults while the screen drew the stack
-- count's settings. If Text.lua ever inherits differently, this line is the
-- one that has to move with it.
---------------------------------------------------------------------------
-- EACH NAME IS LOOKED UP AS A LITERAL, and that is why the label is a
-- function rather than a string. `L[spec.label]` is invisible to the locale
-- guard - it reads the SOURCE and only ever sees a literal L["..."], which is
-- correct of it: a key that arrives through a variable can only be caught by
-- a table check written for that table, and there is none for this one. So
-- the three names would never have reached the master list and would never
-- have been translated, in silence, which is the exact hole that guard is
-- for. A closure keeps one list and puts the literal back in the file.
local TEXT_ELEMENTS = {
    { key = "countdown", label = function() return ns.L["Countdown"] end },

    -- ONE BLOCK FOR ONE NUMBER, AND THE SPLIT WAS OUR PLUMBING SHOWING.
    --
    -- Owner, after a session of this: "WIR BRAUCHEN DEN STACK COUNT: ich muss
    -- doch sehen wie viel aufladungen der spell hat", and before that
    -- "kann es sein dass du hier paar sachen durcheinander bringst und wild
    -- benennst?"
    --
    -- He is right, and it is worth being exact about whose fault it is.
    -- BLIZZARD has two frames: `Applications` counts the stacks of an aura,
    -- `ChargeCount` counts the charges of a spell, and no frame ever carries
    -- both. That is a real distinction inside the engine. It is not a
    -- distinction anybody has while looking at a bar: there, it is the small
    -- number in the corner that says how many. Two blocks of eight identical
    -- controls, named after which of Blizzard's frames happens to feed them,
    -- made the user's job "work out which of our two pages your spell is on
    -- before you can change its font".
    --
    -- So the page offers one block and writes BOTH keys. `also` is what makes
    -- that true rather than nearly true: Text.Element already lets `charges`
    -- inherit from `stacks` field by field, so writing only `stacks` would
    -- work on a fresh profile and quietly stop working on any bar that
    -- already carries a `charges` value from the split-era page - which is
    -- exactly the shape of bug that takes a week to find.
    --
    -- Nothing changes in the renderer. Text.Style still resolves two
    -- elements, Render still styles two of Blizzard's frames, and Text.Count
    -- still draws either number when Blizzard draws none. Only the page
    -- stopped asking somebody to care.
    { key = "stacks", also = "charges",
      label = function() return ns.L["Stacks and charges"] end },
    -- THE FOURTH ONE, ADDED THE DAY IT BECAME REACHABLE. It was left out
    -- because Text.Caption had no caller - eight controls that could not
    -- reach anything is worse than a missing block - and Render calls it now.
    --
    -- It is the only one of the four this addon draws ITSELF, on our own
    -- cell rather than on a counter of Blizzard's, and the only one that can
    -- stand down for want of room: a square place has no band beside the icon
    -- to put a word in. Render decides that; this offers the settings.
    { key = "spellName", label = function() return ns.L["Spell name"] end },
}

-- Built when it is asked for rather than at file scope, for the reason the
-- TOC gives above Locale.lua: at file scope the profile is not open, so every
-- one of these would be looked up in English and then frozen there for the
-- session however the language row is set.
local function TextAnchors()
    local L = ns.L
    return {
        { value = "TOPLEFT",     text = L["Top left"] },
        { value = "TOP",         text = L["Top"] },
        { value = "TOPRIGHT",    text = L["Top right"] },
        { value = "LEFT",        text = L["Left"] },
        { value = "CENTER",      text = L["Centre"] },
        { value = "RIGHT",       text = L["Right"] },
        { value = "BOTTOMLEFT",  text = L["Bottom left"] },
        { value = "BOTTOM",      text = L["Bottom"] },
        { value = "BOTTOMRIGHT", text = L["Bottom right"] },
    }
end

-- WHAT THE SCREEN IS ACTUALLY DRAWING, asked of the file that draws it.
--
-- Text.Style resolves the inheritance, the per-element defaults and the nine
-- positions in one place, so a getter that reads it cannot disagree with the
-- cell. The two it resolves too far are handled below.
local function TextStyle(bar)
    local text, store = Texts(), Store()
    local current = Bar(bar)
    if not (text and store and current) then return nil end
    return text.Style(current, store.Lattice(current).size)
end

local function TextGet(bar, element, key, fallback)
    return function()
        local style = TextStyle(bar)
        local one = style and style[element]
        if type(one) ~= "table" then return fallback end
        local value = one[key]
        if value == nil then return fallback end
        return value
    end
end

-- THE TWO Text.Style RESOLVES TOO FAR FOR A CONTROL.
--
-- A size of nought becomes a share of the cell and an empty font becomes
-- whatever Settings says - both correct for the renderer and both wrong for a
-- row, because they spend exactly the answer the control has to be able to
-- show. So these two are read raw, with the same inheritance and nothing else.
local function TextRaw(bar, spec, key)
    return function()
        local current = Bar(bar)
        if type(current) ~= "table" then return nil end

        local stored = type(current[spec.key]) == "table"
            and current[spec.key] or nil
        local value = stored and stored[key]
        if value ~= nil then return value end

        if spec.inherit then
            local parent = type(current[spec.inherit]) == "table"
                and current[spec.inherit] or nil
            value = parent and parent[key]
            if value ~= nil then return value end
        end
        return nil
    end
end

-- WRITES EVERY ELEMENT THE ROW SPEAKS FOR, which is one of them except for
-- the merged stacks-and-charges block. See TEXT_ELEMENTS: writing only the
-- first would work until a bar carried a value under the second, and then the
-- control would edit a number nobody could see changing.
local function TextPut(bar, spec, key)
    return function(value)
        local current = Bar(bar)
        if type(current) ~= "table" then return end
        for _, name in ipairs({ spec.key, spec.also }) do
            if type(current[name]) ~= "table" then current[name] = {} end
            current[name][key] = value
        end
    end
end

function Panel.BuildText(grid, bar)
    local L = ns.L
    local groups = {}

    grid:Tab(L["Text"])

    for _, spec in ipairs(TEXT_ELEMENTS) do
        -- COLLECTED so a whole block can leave the page together. A section
        -- heading is a region like any other, and one left standing over
        -- hidden rows is a heading for nothing.
        local block = {}
        local function Keep(region)
            if region then block[#block + 1] = region end
            return region
        end

        Keep(grid:Section(spec.label(), "cd-text-" .. spec.key, true))

        -- ON THE PAGE, because it decides whether you touch this block at
        -- all: Blizzard puts a charge count on a cooldown and a stack count
        -- on a buff and never both on one frame, so a bar of ordinary
        -- cooldowns has nothing for the stack rows to reach.
        --
        -- AND SAID ABOUT THIS BAR RATHER THAN IN GENERAL. The sentence below
        -- was correct and did not help: he spent a session in the Stack count
        -- block setting up a spell that has CHARGES, because nothing on the
        -- page said which of the two his own places carry. Counted live now,
        -- off the frames themselves.
        -- THE TWO PARAGRAPHS THAT USED TO STAND HERE ARE GONE. One explained
        -- that Blizzard puts a stack count on a buff and a charge count on a
        -- cooldown; the other explained the inheritance between them. Owner,
        -- with a picture of both: "die beschreibung kannst du rausnehmen, das
        -- juckt niemanden, entweder es geht oder nicht."
        --
        -- He is right, and the live line above them is why: it says the same
        -- thing about HIS bar, in numbers, and it is the sentence that
        -- actually sends him to the right block. A rule stated in general
        -- next to the same rule stated about the thing in front of you is the
        -- general one being read twice and acted on neither time.

        Keep(UI.Toggle(grid:Row(L["Show"]),
            TextGet(bar, spec.key, "show", true),
            function(value)
                TextPut(bar, spec, "show")(value)
                Refresh()
            end))
        -- ONE MORE PARAGRAPH GONE. "Blizzard counts these and runs the clock"
        -- explained an implementation detail to somebody deciding whether to
        -- tick a box. Owner: "text raus, juckt keinen."

        Keep(UI.MediaPicker(
            grid:FullRow(L["Font"], { controlWidth = 190, icon = "media-font" }),
            "font", TextRaw(bar, spec, "font"), TextPut(bar, spec, "font"),
            Refresh, L["Same as everywhere"]))

        -- NO LEGAL VALUE MAY BE INVISIBLE.
        --
        -- Owner, with a photograph of this row reading 4 and a bar showing no
        -- numbers: "stack count wird immer noch nicht angezeigt ... empowered
        -- rune weapon hat 2 aufladungen, stack count ist aktiviert aber nicht
        -- sichtbar." The number was there. It was four pixels tall.
        --
        -- Worse than it looks, and this is why it is fixed rather than
        -- explained: the charge count INHERITS from the stack count field by
        -- field, so one drag to 4 while hunting for a missing number made the
        -- other number invisible too - and the second one is the one his
        -- spell actually has. A setting that hides the thing you are looking
        -- for, while you are looking for it, is a trap.
        --
        -- The bottom of the rail is therefore two positions and not six:
        -- nought, which is the automatic size, and then six, which is the
        -- smallest a number with an outline can be read at. Snapped in the
        -- SETTER so the jump is visible in the box as it happens - silently
        -- accepting 4 and drawing 6 would be a control that lies.
        Keep(UI.Slider(grid:Row(L["Size"]), {
            min = 0, max = 32, step = 1, format = AutoSize,
            get = TextRaw(bar, spec, "size"),
            set = function(value)
                value = tonumber(value) or 0
                if value > 0 and value < TEXT_FLOOR then value = TEXT_FLOOR end
                TextPut(bar, spec, "size")(value)
            end,
            apply = Refresh,
        }))
        Keep(grid:Note(L("Nought works the size out from the place it sits in, "
            .. "which is what keeps a 24 pixel bar and a 64 pixel icon "
            .. "looking like one design. Below %d pixels a number is there "
            .. "and cannot be read, so the rail goes straight from nought to "
            .. "%d.", TEXT_FLOOR, TEXT_FLOOR)))

        -- THE STORED ALPHA IS KEPT. A text colour is four numbers and a
        -- swatch only ever hands back three, so writing { r, g, b } would
        -- quietly set a number somebody had faded back to fully opaque - and
        -- there is no control on this page that could put it back.
        Keep(UI.Swatch(grid:Row(L["Colour"]),
            function()
                local colour = TextGet(bar, spec.key, "color", nil)()
                if type(colour) ~= "table" then colour = { 1, 1, 1, 1 } end
                return colour[1] or 1, colour[2] or 1, colour[3] or 1
            end,
            function(r, g, b)
                local was = TextGet(bar, spec.key, "color", nil)()
                local alpha = type(was) == "table" and was[4] or 1
                TextPut(bar, spec, "color")({ r, g, b, alpha })
            end,
            Refresh))

        Keep(UI.Dropdown(grid:FullRow(L["Outline"],
            { controlWidth = 150, icon = "media-outline" }),
            ns.Media.OUTLINES,
            TextGet(bar, spec.key, "outline", "OUTLINE"),
            TextPut(bar, spec, "outline"), { apply = Refresh }))

        Keep(UI.Dropdown(grid:Row(L["Position"]), TextAnchors(),
            TextGet(bar, spec.key, "anchor", "BOTTOMRIGHT"),
            TextPut(bar, spec, "anchor"), { apply = Refresh }))

        Keep(UI.Slider(grid:Row(L["Nudge across"]), {
            min = -30, max = 30, step = 1,
            get = TextGet(bar, spec.key, "x", 0),
            set = TextPut(bar, spec, "x"), apply = Refresh,
        }))
        Keep(UI.Slider(grid:Row(L["Nudge up"]), {
            min = -30, max = 30, step = 1,
            get = TextGet(bar, spec.key, "y", 0),
            set = TextPut(bar, spec, "y"), apply = Refresh,
        }))

        -- THE SPELL NAME BLOCK ONLY EXISTS WHERE A NAME CAN APPEAR.
        --
        -- Owner: "spell name kannste bei icons rausnehmen, nur bei bars
        -- sichtbar. macht null sinn das bei icons anzuzeigen wenn man es
        -- nicht einblenden kann." Eight controls that cannot reach anything
        -- is the same defect as a setter with no undo, arrived at from the
        -- page's side rather than from Claim's - and it is the one kind this
        -- addon has shipped most often.
        --
        -- Re-decided on every pass rather than at build time: this page is
        -- built ONCE and the kind of a bar's places is a dropdown two tabs
        -- over. Render's own test is `at.w > at.h`, which on our own lattice
        -- is exactly `kind == "bar"`.
        if spec.key == "spellName" then
            groups[#groups + 1] = {
                when = function()
                    local current = Bar(bar)
                    return type(current) == "table" and current.kind == "bar"
                end,
                rows = block,
            }
        end

        -- NOTHING HERE HIDES A FIELD OF A SWITCHED-OFF ELEMENT, and that is
        -- the second half of the rule in the header: a face, a colour and a
        -- corner are still what the number will wear when it is switched back
        -- on, so they are settings in their own right and not the detail of
        -- the switch above them.
    end

    Reveal(groups)
    OnRefresh(grid, function() Reveal(groups) end)
end

---------------------------------------------------------------------------
-- Effects - what a cell DOES rather than what it is
--
-- Grouped by what each one is FOR. Alphabetical is how the old page ended up
-- with the edge style three sections below the edge it changes: the owner had
-- that control built for him and still had to ask where it was.
--
-- EVERY ROW ASKS THE FILE THAT DRIVES IT. Effects.ANSWERED names the keys
-- something actually reads and its own comment says the options page builds
-- from it, so a key nothing answers for gets no row rather than a row that
-- can never fire - and the day wave 5 flips an entry, the row appears without
-- anybody having to remember this file exists.
---------------------------------------------------------------------------
local function Answered(key)
    local effects = Fx()
    local list = effects and effects.ANSWERED
    return type(list) == "table" and list[key] == true
end

local function FxGet(bar, key)
    return function()
        local effects = Fx()
        if not effects then return ns.EFFECT_DEFAULTS[key] end
        local current = Bar(bar)
        return effects.Option(current and current.effects, key)
    end
end

local function FxPut(bar, key)
    return function(value)
        local current = Bar(bar)
        if type(current) ~= "table" then return end
        if type(current.effects) ~= "table" then current.effects = {} end
        current.effects[key] = value
    end
end

local function FxSwitch(grid, bar, label, key, opts)
    if not Answered(key) then return nil end
    local write = FxPut(bar, key)
    return UI.Toggle(grid:Row(label, opts), FxGet(bar, key),
        function(value) write(value) Refresh() end)
end

local function FxSlide(grid, bar, label, key, spec, opts)
    if not Answered(key) then return nil end
    return UI.Slider(grid:Row(label, opts), {
        min = spec.min, max = spec.max, step = spec.step,
        format = spec.format, scale = spec.scale,
        get = FxGet(bar, key), set = FxPut(bar, key), apply = Refresh,
    })
end

local function FxColour(grid, bar, label, key, opts)
    if not Answered(key) then return nil end
    return UI.Swatch(grid:Row(label, opts),
        function()
            local colour = FxGet(bar, key)()
            if type(colour) ~= "table" then colour = { 1, 1, 1 } end
            return colour[1] or 1, colour[2] or 1, colour[3] or 1
        end,
        function(r, g, b) FxPut(bar, key)({ r, g, b }) end,
        Refresh)
end

local function FxChoice(grid, bar, label, key, options, opts)
    if not Answered(key) then return nil end
    return UI.Dropdown(grid:Row(label, opts), options,
        FxGet(bar, key), FxPut(bar, key), { apply = Refresh })
end

function Panel.BuildEffects(grid, bar)
    local L = ns.L
    local groups = {}

    grid:Tab(L["Effects"])

    -----------------------------------------------------------------------
    -- The flash
    -----------------------------------------------------------------------
    grid:Section(L["When a cooldown comes back"], "cd-fx-ready", true)

    local flashOn = FxGet(bar, "readyFlash")
    FxSwitch(grid, bar, L["Flash"], "readyFlash",
        { sublabel = L["A pulse the moment the cooldown ends"],
          icon = "effect-flash" })

    local flash = {}
    Keep(flash, FxSlide(grid, bar, L["How many"], "readyPulses",
        { min = 1, max = 5, step = 1 }))
    Keep(flash, FxColour(grid, bar, L["Flash colour"], "readyColor"))
    groups[#groups + 1] = { when = flashOn, rows = flash }

    -----------------------------------------------------------------------
    -- The edge while it is ready
    -----------------------------------------------------------------------
    grid:Section(L["The edge while it is ready"], "cd-fx-glow", true)

    local glowOn = FxGet(bar, "readyGlow")
    FxSwitch(grid, bar, L["Keep an edge"], "readyGlow", { icon = "effect-edge" })
    grid:Note(L["Blizzard's Cooldown Manager is asked whether the spell is on "
        .. "a real cooldown, so the global cooldown never sets any of this "
        .. "off. A cooldown the client will not talk about is left alone."])

    local glow = {}
    Keep(glow, FxSwitch(grid, bar, L["Only in combat"], "readyGlowCombatOnly"))
    Keep(glow, FxSwitch(grid, bar, L["Only when you can pay for it"],
        "readyGlowUsableOnly"))
    grid:Note(L["Keeps the edge dark while you are short of the resource. "
        .. "Range and target are ignored - a defensive with nothing targeted "
        .. "is not the same as one you cannot pay for."])

    Keep(glow, FxColour(grid, bar, L["Edge colour"], "glowColor"))
    Keep(glow, FxSlide(grid, bar, L["Edge thickness"], "glowSize",
        { min = 1, max = 5, step = 1 }))

    -- BESIDE THE EDGE IT CHANGES rather than three sections further down. The
    -- old page put it under a different heading and the owner, who had it
    -- built for him, still had to ask where it was: a control nobody can find
    -- is a control that does not work.
    local styleOf = FxGet(bar, "glowStyle")
    Keep(glow, FxChoice(grid, bar, L["Edge style"], "glowStyle", {
        { value = "edge",  text = L["Soft edge"] },
        { value = "pixel", text = L["Running squares"] },
    }))

    local dots = FxSlide(grid, bar, L["How many squares"], "glowDots",
        { min = 2, max = 24, step = 1 })
    if dots then
        -- TWO CONDITIONS, NOT ONE. The count belongs to the running squares,
        -- so it goes when the edge is off AND when the edge is the soft one -
        -- a slider under "Soft edge" moves nothing at all.
        groups[#groups + 1] = {
            when = function()
                return glowOn() and styleOf() == "pixel"
            end,
            rows = { dots },
        }
    end
    groups[#groups + 1] = { when = glowOn, rows = glow }

    -----------------------------------------------------------------------
    -- The nag
    -----------------------------------------------------------------------
    grid:Section(L["The nag"], "cd-fx-nag", true)

    -- A SLIDER RATHER THAN A SWITCH, so the mark goes on the row that IS the
    -- nag. Nought is off and the value box says so in the word rather than in
    -- the number.
    local after = FxGet(bar, "reminderAfter")
    FxSlide(grid, bar, L["Remind me after"], "reminderAfter",
        { min = 0, max = 20, step = 1, format = Seconds }, { icon = "effect-nag" })
    grid:Note(L["A spell that has been ready this long IN COMBAT starts "
        .. "pulsing. For the defensive you keep forgetting."])

    local nag = {}
    Keep(nag, FxColour(grid, bar, L["Reminder colour"], "reminderColor"))
    groups[#groups + 1] = {
        when = function() return (tonumber(after()) or 0) > 0 end,
        rows = nag,
    }

    -----------------------------------------------------------------------
    -- While the buff it puts on you is up
    -----------------------------------------------------------------------
    grid:Section(L["While the buff is up"], "cd-fx-active", true)

    local activeOn = FxGet(bar, "activeGlow")
    FxSwitch(grid, bar, L["Glow while it is up"], "activeGlow",
        { icon = "effect-glow" })

    local active = {}
    Keep(active, FxColour(grid, bar, L["Its colour"], "activeColor"))
    groups[#groups + 1] = { when = activeOn, rows = active }

    -----------------------------------------------------------------------
    -- The refresh window
    -----------------------------------------------------------------------
    grid:Section(L["The refresh window"], "cd-fx-pandemic", true)
    -- ON THE PAGE, because it is a "this needs the other thing switched on":
    -- the window is Blizzard's arithmetic and we only ask for the answer, so
    -- an aura whose pandemic alert is off in the game's own settings never
    -- lights however this row is set.
    grid:Note(L["The tail of an aura where recasting it wastes nothing. "
        .. "Blizzard works the window out and we ask for the answer, so this "
        .. "only lights for auras you have switched pandemic alerts on for in "
        .. "the game's own settings."])

    local pandemicOn = FxGet(bar, "pandemicGlow")
    FxSwitch(grid, bar, L["Glow in the window"], "pandemicGlow",
        { icon = "effect-glow" })

    local pandemic = {}
    Keep(pandemic, FxColour(grid, bar, L["Window colour"], "pandemicColor"))
    groups[#groups + 1] = { when = pandemicOn, rows = pandemic }

    -----------------------------------------------------------------------
    -- Greying and hiding
    -----------------------------------------------------------------------
    grid:Section(L["Greying and hiding"], "cd-fx-hide", true)

    local dimOn = FxGet(bar, "dimOnCooldown")
    FxSwitch(grid, bar, L["Grey out while it runs"], "dimOnCooldown")

    local dim = {}
    Keep(dim, FxSlide(grid, bar, L["How grey"], "dimAmount",
        { min = 0.2, max = 1, step = 0.05, format = Percent, scale = 100 }))
    groups[#groups + 1] = { when = dimOn, rows = dim }

    -----------------------------------------------------------------------
    -- WHEN A PLACE IS ON SCREEN AT ALL, and it is five answers now.
    --
    -- Owner, 2026-08-15: "ich brauch noch conditions wann und wie die icons
    -- und bars angezeigt werden, also wenn auf cd, oder immer, oder wenn rdy
    -- etc. das fehlt komplett" - and then "ich kann es aber nicht einstellen
    -- im addon! das sind noch alte regeln."
    --
    -- He is right about both halves. The rule was welded shut: one behaviour,
    -- and a two-value switch that could only turn it on or off. Every other
    -- state was already ANSWERABLE - Effects.CellState has had the arithmetic
    -- all along - and none of them could be ASKED for.
    --
    -- READ THROUGH Effects.ShowWhen, NOT OFF THE KEY. A bar written in 4.82.0
    -- carries `hideWhen` and no `showWhen`, and the translation lives in
    -- exactly one place - Store's promise is that nothing on disk is
    -- rewritten. A second copy here would be the copy that goes stale, and
    -- its way of failing is that the menu says "Always" while the bar hides
    -- half its places.
    -----------------------------------------------------------------------
    if Answered("showWhen") then
        UI.Dropdown(grid:FullRow(L["Show this place"], { controlWidth = 210 }),
            ns.CD_SHOW_WHEN,
            function()
                local effects, current = Fx(), Bar(bar)
                if not effects then return "always" end
                return effects.ShowWhen(current and current.effects)
            end,
            FxPut(bar, "showWhen"), { apply = Refresh })
        grid:Note(L["Ready means you can press it. Working means the buff it "
            .. "put on you is still running - Anti-Magic Shell, Blood Shield. "
            .. "Recharging is neither. A place the client will not answer for "
            .. "stays on screen: one that vanished because something could "
            .. "not be read is indistinguishable from a bug."])
    end

    -- STAYS EVEN WHEN NOTHING IS BEING HIDDEN, and says so on itself. It is a
    -- setting in its own right rather than the detail of the row above, and
    -- somebody looking for "close the gaps" who finds no row at all concludes
    -- the addon cannot do it.
    FxChoice(grid, bar, L["The empty place"], "reflow", {
        { value = "off",  text = L["Leave it empty"] },
        { value = "all",  text = L["Close up"] },
        { value = "line", text = L["Close up in the row"] },
    }, { sublabel = L["Only closes up what the row above takes off screen"] })
    grid:Note(L["Leaving it empty keeps everything where you learned it. "
        .. "Closing up in the ROW keeps a grid's shape, so the second row "
        .. "stays the second row."])

    -----------------------------------------------------------------------
    -- One heartbeat for all of them
    -----------------------------------------------------------------------
    grid:Section(L["Everything that pulses"], "cd-fx-pulse", true)

    FxSlide(grid, bar, L["Speed"], "pulseSpeed",
        { min = 0.4, max = 2.5, step = 0.1,
          format = function(value) return string.format("%.1f", value or 1) end },
        { sublabel = L["One speed for the flash, the nag and the squares"] })

    Reveal(groups)
    OnRefresh(grid, function() Reveal(groups) end)
end

---------------------------------------------------------------------------
-- Fill - the StatusBar half of an adopted tracking bar
--
-- NOT GATED ON bar.kind, AND THAT WAS MEASURED RATHER THAN ASSUMED. A place's
-- SHAPE is Blizzard's, not this bar's: CDM:ItemShape reads the viewer the
-- spell lives in, so a spell in the Buff bars viewer arrives as a StatusBar
-- however this bar's places are set, and Render.Fit puts it in the place
-- whole. Hiding this block on a bar of icons would therefore hide the
-- settings for the one place on it that has a fill.
--
-- So the block is always there and says on the page what it reaches. That is
-- the second half of the owner's rule: offer them only where they apply, or
-- say plainly on the row that they do not.
---------------------------------------------------------------------------
local FILL_KEYS = {
    "fillAlpha", "fillColor", "fillDirection", "fillGradient", "fillGrow",
    "fillSide", "fillTexture", "showSpark", "chargeMarks", "chargeMarkColor",
    "stackThresholds", "fillBack", "fillBackAlpha", "fillBackColor",
}

-- HOW MANY BANDS ONE BAR CARRIES.
--
-- A fixed pool rather than rows made on demand, because a page in this window
-- is built ONCE and a row created by a click would never be laid out. Six is
-- twice what the old page's three fixed bands offered and twice what he has
-- ever stored; a stack bar has two or three readings worth marking.
local BANDS = 6

local function BandRows(grid, bar)
    local L = ns.L

    -- Read without creating. Store's promise is that nothing is rewritten,
    -- and a bar that grew an empty list by being looked at is a rewrite.
    local function List()
        local current = Bar(bar)
        local list = current and current.stackThresholds
        return type(list) == "table" and list or nil
    end

    -- COUNTED THE WAY THE RENDERER COUNTS. Fill.Thresholds walks with ipairs,
    -- so its idea of the list ends at the first hole; `#` on a table with a
    -- hole may answer at it or past it and both are correct by the language's
    -- own definition. A page showing a band the renderer never reads is the
    -- same defect as a band the page cannot see.
    local function Count()
        local list = List()
        if not list then return 0 end
        local total = 0
        for _ in ipairs(list) do total = total + 1 end
        return total
    end

    local function Held()
        local current = Bar(bar)
        if type(current) ~= "table" then return nil end
        if type(current.stackThresholds) ~= "table" then
            current.stackThresholds = {}
        end
        return current.stackThresholds
    end

    local function Field(index, key, fallback)
        return function()
            local list = List()
            local entry = list and list[index]
            if type(entry) ~= "table" then return fallback end
            local value = entry[key]
            if value == nil then return fallback end
            return value
        end
    end

    local function Write(index, key)
        return function(value)
            local list = Held()
            local entry = list and list[index]
            if type(entry) == "table" then entry[key] = value end
        end
    end

    local groups = {}

    -- BEFORE THE FIRST ROW OF THE SECTION, and that is not layout taste. On a
    -- page with tooltip notes a sentence attaches itself to the last row above
    -- it and is only ever seen by somebody already pointing at that row -
    -- Grid:Note, and Grid:Section clears the row for exactly this reason. A
    -- limit belongs where you read it before you go looking for the control.
    local full = grid:Note(L("That is as many bands as one bar carries (%d). "
        .. "Take one away to add another.", BANDS))

    for index = 1, BANDS do
        local rows = {}

        -- A MINIMUM OF ONE, which is the writer's half of the fix described
        -- at the section note above: the renderer drops anything lower and
        -- the old panel wrote nought on every band it made.
        rows[#rows + 1] = UI.Slider(grid:Row(L["From"]), {
            min = 1, max = 20, step = 1,
            format = function(value)
                return string.format("%d+", math.floor(value or 1))
            end,
            get = Field(index, "value", 1),
            set = Write(index, "value"), apply = Refresh,
        })

        rows[#rows + 1] = UI.Swatch(grid:Row(L["Colour"]),
            function()
                local colour = Field(index, "color", nil)()
                if type(colour) ~= "table" then colour = { 0.85, 0.15, 0.15 } end
                return colour[1] or 1, colour[2] or 1, colour[3] or 1
            end,
            function(r, g, b) Write(index, "color")({ r, g, b }) end,
            Refresh)

        rows[#rows + 1] = UI.Slider(grid:Row(L["Opacity"]), {
            min = 0, max = 1, step = 0.05, format = Percent, scale = 100,
            get = Field(index, "alpha", 1),
            set = Write(index, "alpha"), apply = Refresh,
        })

        local strip = grid:Buttons({
            { text = L["Take this band away"], onClick = function()
                local list = Held()
                if list and list[index] then table.remove(list, index) end
                Refresh()
            end },
        })
        rows[#rows + 1] = strip

        groups[#groups + 1] = {
            when = function() return Count() >= index end,
            rows = rows,
        }
    end

    local addStrip = grid:Buttons({
        { text = L["Add a band"], onClick = function()
            local list = Held()
            if not list then return end
            local used = Count()
            if used >= BANDS then return end
            list[used + 1] = {
                value = 1, color = { 0.85, 0.15, 0.15 }, alpha = 1,
            }
            Refresh()
        end },
    }, UI.PAD)

    -- The limit is said only while it applies, and the button goes when it
    -- does: a control that refuses every press is worse than one that is not
    -- offered.
    groups[#groups + 1] = {
        when = function() return Count() < BANDS end, rows = { addStrip },
    }
    groups[#groups + 1] = {
        when = function() return Count() >= BANDS end, rows = { full },
    }

    return groups
end

function Panel.BuildFill(grid, bar)
    local L = ns.L
    local groups = {}

    grid:Tab(L["Fill"])
    grid:Section(L["The bar's fill"], "cd-fill-bar", true)
    -- THE PARAGRAPH THAT USED TO STAND HERE IS GONE, and so is the reason it
    -- was needed. It explained that these settings reach a place Blizzard
    -- draws as a tracked buff BAR and that an icon has no fill - which is a
    -- sentence you only have to write when the block is offered to somebody
    -- it cannot help. Owner, 2026-08-15, with a picture of it: "der erklaer
    -- text raus, und die bars fill option nicht bei den icon cds einblenden,
    -- nur bei track bars. dann haben wir wieder was entwirrt."
    --
    -- The tab now appears only where there IS a fill, decided in
    -- OptionsCooldowns.lua's HasFill. That is not the same test as
    -- `bar.kind == "bar"`: a place's shape is Blizzard's, not this bar's, so
    -- a spell out of the Buff bars viewer arrives as a StatusBar however this
    -- bar's places are set. Gating on the bar's own kind would have hidden
    -- the settings for the one place on an icon bar that has a fill, which is
    -- the case the header above measured rather than assumed.
    OverrideNote(grid, bar, FILL_KEYS)

    Colour(grid, bar, L["Colour"], "fillColor", { 1.00, 0.478, 0.239 })
    Slide(grid, bar, L["Opacity"], "fillAlpha",
        { min = 0, max = 1, step = 0.05, format = Percent, scale = 100,
          fallback = 0.85 })
    GradientRows(grid, bar, "fillGradient", groups)
    Picture(grid, bar, L["Texture"], "statusbar", "fillTexture", nil,
        "media-texture", L["Same as behind the icon"])

    -- THE TROUGH. Its colour and its opacity only appear once it is on, the
    -- same shape the gradient trio above uses - two rows that can change
    -- nothing are two rows to read past on every visit.
    local backOn = Get(bar, "fillBack", false)
    Switch(grid, bar, L["Background"], "fillBack", false,
        { sublabel = L["Behind the fill, where the bar is not full yet"] })
    groups[#groups + 1] = {
        when = backOn,
        rows = {
            Colour(grid, bar, L["Background colour"], "fillBackColor",
                { 0, 0, 0 }),
            Slide(grid, bar, L["Background opacity"], "fillBackAlpha",
                { min = 0, max = 1, step = 0.05, format = Percent,
                  scale = 100, fallback = 0.5 }),
        },
    }

    -- ONE CONTROL WITH FOUR ANSWERS rather than two switches to combine in
    -- your head. Two of the four were unreachable before it: SetReverseFill
    -- on its own only ever flips a horizontal bar, so up and down needed an
    -- orientation as well.
    --
    -- READ THROUGH Fill.Direction, not off the key. A bar written before the
    -- four-answer control carries only `fillSide`, and that translation lives
    -- in exactly one place - a second copy here would be the copy that goes
    -- stale, and its way of failing is that the dropdown says "left to right"
    -- while the bar runs the other way.
    UI.Dropdown(grid:Row(L["Runs"]), ns.FILL_DIRECTIONS,
        function()
            local fill, current = Fills(), Bar(bar)
            if not (fill and current) then return "right" end
            return fill.Direction(current, nil).value
        end,
        Put(bar, "fillDirection"), { apply = Refresh })

    -- THE OTHER AXIS, AND ONLY WHEN IT CAN DO ANYTHING. Direction is SPACE -
    -- which end is nailed down; this is TIME - whether the bar fills or
    -- drains while the cooldown runs. It goes through Claim.Grow, which does
    -- not exist yet: Look.Door prints one line and skips the work. Shipped as
    -- a row anyway it would be "Fill up" a third time, which is the control
    -- this addon has already shipped twice doing nothing at all.
    local claim = ns.Cooldowns and ns.Cooldowns.Claim
    if claim and type(claim.Grow) == "function" then
        Choice(grid, bar, L["Over time"], "fillGrow", ns.FILL_CLOCKS, false)
        grid:Note(L["Whether the bar fills or empties while the cooldown "
            .. "runs. The clock belongs to Blizzard's own template and it "
            .. "re-drives the bar on every update, so this is the one setting "
            .. "here whose undo is its owner putting it back."])
    end

    grid:Section(L["Charge marks and the spark"], "cd-fill-marks", true)
    -- ON THE PAGE: it is why the switch can be left on for a whole bar, which
    -- is a thing you decide rather than a thing you wonder about afterwards.
    grid:Note(L["Charge marks only appear on a spell that HAS more than one "
        .. "charge, so the switch can stay on for a whole bar without marking "
        .. "everything on it."])

    -- The marks first, so the sentence above lands on the row it is about.
    local marksOn = Get(bar, "chargeMarks", false)
    Switch(grid, bar, L["Charge marks"], "chargeMarks", false,
        { sublabel = L["One line per charge boundary"] })

    groups[#groups + 1] = {
        when = marksOn,
        rows = { Colour(grid, bar, L["Mark colour"], "chargeMarkColor",
            { 0, 0, 0 }) },
    }

    Switch(grid, bar, L["Spark"], "showSpark", false,
        { sublabel = L["A bright line on the moving edge"] })

    grid:Section(L["Stack colours"], "cd-fill-stacks", true)
    grid:Note(L["A band takes the fill's colour over once the stack count "
        .. "reaches its number. The highest one reached is the one you see."])
    -- THE FLOOR IS ON THE PAGE, and it is the writer's half of a fault the
    -- renderer already reports. Fill.Thresholds drops every band below one -
    -- "a threshold of 0 is crossed by an aura that is merely present" - and
    -- counts what it dropped; measured against his own file, all three of his
    -- bands carry value = 0, so the one bar he ever set bands on has never
    -- painted a single one. The old panel called nought "off" and wrote rows
    -- the renderer threw away. Off is having no band.
    grid:Note(L["A band starts at one stack. To switch one off, take it "
        .. "away - a band of nought would be crossed by an aura that is "
        .. "merely there."])

    -- SAID ONLY WHILE IT IS TRUE, and it is asked rather than written down:
    -- Fill.CanFeed answers whether anything can push a stack count in at all,
    -- and nothing in this version can - CDM:ItemStacks went with the old
    -- reader and has not come back, so Fill.Overlays is handed an empty list
    -- whatever is stored. The day the reader lands this sentence goes by
    -- itself, which is why it is a question and not a paragraph.
    local dry = grid:Note(L["No band is drawn yet: nothing in this version "
        .. "can read a stack count off a frame Blizzard owns. What you set "
        .. "here is kept and starts painting when it can."])
    OnRefresh(grid, function()
        local fill = Fills()
        local shown = not (fill and fill.CanFeed and fill.CanFeed())
        dry.dkSkip = not shown
        dry:SetShown(shown)
    end)

    for _, group in ipairs(BandRows(grid, bar)) do
        groups[#groups + 1] = group
    end

    Reveal(groups)
    OnRefresh(grid, function() Reveal(groups) end)
end
