---------------------------------------------------------------------------
-- ZwoelfStuff - your own cooldown bars, built on Blizzard's Cooldown Manager.
--
-- Spells go in a grid you arrange, and every bar is styled on its own. What
-- the Cooldown Manager carries is adopted rather than redrawn; what it does
-- NOT carry - auras like Boiling Point, which is not in the C_CooldownViewer
-- data set and can never be added to it - is recorded and drawn by us.
--
-- This file: namespace, defaults, saved variables, shared helpers, commands.
---------------------------------------------------------------------------
local ADDON, ns = ...

ns.ADDON = ADDON
ns.version = "4.41.0"

-- The addon's own mark, used by the minimap button. Kept next to the TOC's
-- IconTexture line so the two cannot drift apart.
ns.ICON_TEXTURE = "Interface\\AddOns\\ZwoelfStuff\\Media\\logo"

-- The aura this addon was built for: the Boiling Point buff, 15s, Blood
-- Death Knight. Everything user-facing resolves the name from the client at
-- runtime (ns.SpellName / aura.name) - the ID is the only fixed fact here.
ns.PRIMARY_SPELL_ID = 1265968

ns.WHITE = "Interface\\Buttons\\WHITE8X8"

---------------------------------------------------------------------------
-- One tracking group. Groups are the general form of "show me these auras":
-- any number of them, icons or bars, laid out in rows, columns or a grid.
--
-- Font sizes of 0 mean "derive it from the element size" - see Auto() in
-- Groups.lua. They are numbers rather than nil so the option steppers have
-- something to edit.
---------------------------------------------------------------------------
ns.GROUP_DEFAULTS = {
    name       = "Tracker",
    enabled    = true,

    style      = "icon",       -- "icon" | "bar"
    -- "fixed"   - one slot per spell, YOUR order, gaps stay open
    -- "dynamic" - engine picks and sorts, stays compact, positions move
    layoutMode = "fixed",

    unit       = "player",     -- player | target | focus | pet
    filter     = "HELPFUL",    -- HELPFUL | HARMFUL
    onlyMine   = false,        -- adds the PLAYER token to the filter
    spells     = {},           -- in fixed mode this list IS the sort order
    max        = 8,            -- dynamic mode only: how many buttons exist

    -- Layout. All of these apply live, in combat included.
    growthH     = "RIGHT",     -- RIGHT | LEFT
    growthV     = "DOWN",      -- DOWN | UP
    axis        = "horizontal",-- horizontal: lines are rows | vertical: columns
    wrapAfter   = 0,           -- 0 = never wrap
    spacing     = 4,
    lineSpacing = 4,
    sort        = "default",   -- default | important  (dynamic mode)

    -- Element size
    iconSize   = 40,
    barWidth   = 200,
    barHeight  = 22,

    -- Looks
    borderSize    = 1,
    borderColor   = { 0.00, 0.00, 0.00 },
    barColor      = { 1.00, 0.44, 0.16 },
    backdropAlpha = 0.90,
    trackAlpha    = 0.08,

    showSwipe  = true,
    showTimer  = true,
    showStacks = true,
    showName   = true,         -- bar style, fixed mode only
    showIcon   = true,         -- bar style
    showLabel  = false,        -- icon style, fixed mode only

    timerAnchor = "CENTER",    -- CENTER | BOTTOM | TOP
    timerSize   = 0,           -- 0 = auto
    stackSize   = 0,
    nameSize    = 0,

    scale    = 1.0,
    alpha    = 1.0,
    point    = "CENTER",
    relPoint = "CENTER",
    x        = 0,
    y        = -220,
}

ns.DEFAULTS = {
    -- 3: the puzzle got its own two coordinate fields. Before that a cell's
    --    x/y meant a position in the puzzle and a nudge everywhere else, and
    --    switching arrangement silently reinterpreted one as the other.
    -- 4: Arc and Diagonal removed; bars on either move onto Grid.
    -- 5: the one fill setting becomes two - which END the fill sits at, and
    --    whether it grows or drains. They were shipped as one and the label
    --    described the half that was not implemented.
    -- 6: the spells on a bar move to a per-class-and-spec table.
    -- 7: EVERY setting moves under the character it was made on. See
    --    ns.OpenProfile - the owner's rule is that a change to the UI belongs
    --    to the character and realm that made it, and no keying by class or
    --    spec can stop two characters of one class overwriting each other.
    --    Version 6 is therefore now a split INSIDE one character's profile:
    --    the spec you are in decides which spells its bars hold.
    -- See Bars:Migrate.
    dbVersion  = 7,

    -- Bars: a grid of cells, each holding one spell from Blizzard's Cooldown
    -- Manager. Seeded once on first run and never re-seeded, so a deleted
    -- bar stays deleted.
    bars       = {},

    -- REMINDERS: a line of text on the screen when something is wrong.
    --
    -- Empty on purpose and never seeded. A reminder is a sentence somebody
    -- meant to write; one that arrives pre-written with an update is a
    -- message shouting on your screen that you did not ask for, about a spell
    -- that may not be in your build.
    reminders  = {},

    -- M+ ROUTES: the pull you are on, badged onto the mobs themselves.
    --
    -- OFF until asked for, like the co-tank panel. It draws on top of every
    -- nameplate in a dungeon, and a display that appears unbidden after an
    -- update is worse than one nobody has found yet.
    routes = {
        enabled   = false,
        showNext  = true,       -- badge the pull AFTER this one, dimmed
        showNumber = true,      -- the pull number inside the badge
        autoAdvance = true,     -- step on when the pull is down

        -- How much of a pull's forces has to be down before it counts as
        -- finished. Not all of it: a stray that ran off or a patrol that was
        -- already dead would mean never advancing. MDTHelper lands on the
        -- same four fifths.
        forcesThreshold = 0.8,

        size      = 30,
        alpha     = 0.90,
        nextAlpha = 0.45,
        offsetX   = 0,
        offsetY   = 4,
    },

    -- Saved looks, by name. A preset carries ns.BAR_STYLE_KEYS only - sizes,
    -- spacing and colours - never the spells or the grid shape.
    barPresets = {},

    -- Highest bar id handed out so far. Ids are never reused, because an
    -- anchor points at one and a recycled id would silently re-attach a bar
    -- to whatever took the old one's place.
    lastBarID  = 0,

    -- The recorded procs, the hand-made aura links and the list of shipped
    -- procs somebody threw away are NOT here. They are measurements, shared
    -- by every character on the account - see ns.OpenProfile and
    -- ACCOUNT_DEFAULTS below, and ns.account.* is how they are read.

    -- The font every piece of text on every bar uses unless that one piece
    -- has been given its own. One place to change it, and no need to visit
    -- three sections on four bars to change a typeface.
    font       = "Friz Quadrata TT",

    -- The PANEL font - the options window, not the bars. Two different jobs:
    -- bar text is read at a glance over a moving scene, panel text is read in
    -- rows. The design asks for a narrow grotesk here and the client's own
    -- face is not one, which is why this is a separate setting rather than a
    -- reuse of the one above.
    --
    -- nil on purpose: resolved at read time to the best narrow face actually
    -- registered, so a profile made before this existed picks it up too.
    panelFont  = nil,

    -- Whether the bars REPLACE Blizzard's Cooldown Manager display or sit
    -- next to it. On by default, and the setting says what off costs: taking
    -- a cooldown onto our bar leaves a hole in Blizzard's row, because its
    -- layout does not know the frame moved. See Core/Screen.lua.
    takeOverCDM = true,

    -- How unlock and build mode behave. Saved rather than reset each time,
    -- because these are working habits: somebody who arranges on a 20-pixel
    -- grid with snapping off wants that again tomorrow, and re-setting it at
    -- the top of every session is the kind of small tax that makes a tool
    -- feel like it is not on your side.
    -- `snap` was here and is gone in 4.25.0: snapping is what dragging does,
    -- and Alt suspends it for one drag. A switch whose off position makes a
    -- feature silently do nothing is the switch that gets left off and then
    -- reported as a broken feature. A profile that still carries the key is
    -- harmless - nothing reads it.
    editMode = {
        grid         = false,
        gridStep     = 40,
        snapDistance = 10,
        snapToGrid   = true,
        dim          = 0.35,
        showCoords   = false,
    },

    -- Parked with the 12.1 stack; kept so nothing is lost when it returns.
    groups     = {},

    -- Minimap button. angle is degrees around the minimap centre.
    minimap = {
        show   = true,
        locked = false,
        angle  = 200,
    },

    -- An entry in the game menu (Escape), under the last of Blizzard's own.
    -- On by default: it is the place people look for an interface addon, and
    -- one line in a menu you open by choice is not clutter.
    gameMenu = true,

    -- CO-TANKS: a unit frame per tank in the group.
    --
    -- The one display in this addon that is about somebody ELSE. As a Blood
    -- DK you need to know whether the other tank is alive, low, out of range
    -- and holding their cooldowns - and the raid frames answer none of that
    -- at a glance because the other tank is one of twenty boxes.
    --
    -- The vocabulary follows EllesmereUI's unit frames, which is ~200 keys per
    -- frame, cut to what a CO-TANK row needs. Deliberately not carried over:
    -- power bars (a tank's mana is not your problem), cast bars (theirs is not
    -- yours to interrupt), portraits (a name reads faster in a stack of five),
    -- class-power bars and the whole bottom-text-bar apparatus. Every one of
    -- those is a real feature on a PLAYER frame and noise on this one.
    coTanks = {
        -- OFF until asked for. A panel that appears on screen unbidden after
        -- an update is worse than one nobody has found yet - and this one
        -- draws over the middle of the screen by default.
        enabled     = false,
        testMode    = false,
        includeSelf = false,      -- your own frame is already on your screen
        onlyInGroup = true,
        onlyInInstance = false,
        locked      = true,

        -- The frame
        width       = 240,
        rowHeight   = 26,
        spacing     = 6,
        scale       = 1.0,
        maxRows     = 5,          -- more tanks than any raid actually fields
        growth      = "down",     -- which way the stack grows: down | up
        sortBy      = "group",    -- group | name | health

        point       = "CENTER",
        relPoint    = "CENTER",
        x           = -340,
        y           = 140,

        -- Health
        healthTexture = "",
        healthColor   = "class",  -- class | custom | health
        healthCustom  = { 0.36, 0.62, 0.86 },
        healthAlpha   = 1.00,
        healthGradient = { on = false, color = { 0.10, 0.20, 0.30 }, direction = "right" },
        healthReverse = false,
        healthVertical = false,
        -- Colour by REMAINING HEALTH rather than by class: green at full,
        -- through amber, to red. Only reachable when the numbers are readable
        -- - see ns.CanCompute - so it falls back to the class colour rather
        -- than to a bar that stops changing colour mid-fight.
        healthHigh    = { 0.16, 0.75, 0.28 },
        healthMid     = { 0.90, 0.72, 0.16 },
        healthLow     = { 0.80, 0.14, 0.14 },

        -- The plate behind the bar, and the empty part of the bar itself
        bgColor       = { 0.05, 0.05, 0.06 },
        bgAlpha       = 0.85,
        bgGradient    = { on = false, color = { 0.10, 0.10, 0.12 }, direction = "down" },
        trackAlpha    = 0.12,     -- the unfilled part, in the bar's own colour

        borderSize    = 1,
        borderColor   = { 0.00, 0.00, 0.00 },
        borderTexture = "None",
        borderGradient = { on = false, color = { 0.35, 0.35, 0.35 }, direction = "right" },

        -- Absorbs, drawn over the health rather than beside it: a shield is
        -- health you have, and a separate strip somewhere else is a second
        -- thing to look at during the two seconds you have to look.
        -- THEIR OWN TEXTURE, not the health bar's. A shield drawn in the same
        -- material as the health under it reads as more health rather than as
        -- a shield, which is the one thing it must not do. Empty means "wear
        -- the health bar's", which is what it did before and still the
        -- default, so nothing on screen changes until it is picked.
        absorbShow    = true,
        absorbColor   = { 0.85, 0.90, 1.00 },
        absorbAlpha   = 0.45,
        absorbTexture = "",
        healAbsorbShow  = true,
        healAbsorbColor = { 0.78, 0.11, 0.11 },
        healAbsorbAlpha = 0.55,
        healAbsorbTexture = "",

        -- Text. The same seven controls per element as a bar's, from the same
        -- shape, so the panel generator and the anchor rules are shared.
        name = {
            show = true, font = "", size = 0, color = { 1, 1, 1 },
            outline = "OUTLINE", anchor = "LEFT", x = 0, y = 0,
            classColor = true,
            maxLength = 0,       -- 0 keeps the whole name
        },
        health = {
            show = true, font = "", size = 0, color = { 1, 1, 1 },
            outline = "OUTLINE", anchor = "RIGHT", x = 0, y = 0,
            classColor = false,
            -- percent | current | both | deficit
            -- On this patch a health value may arrive protected, and then
            -- NONE of these can be computed. The renderer blanks the text
            -- rather than printing a zero, and the bar keeps working because
            -- a StatusBar takes the number without reading it.
            format = "percent",
        },

        -- INDICATORS - one table each, and all of them the same shape.
        --
        -- They were six loose keys with two settings between them (show, and
        -- a size for three of them), so a marker could not be moved off the
        -- name it was sitting on. Every one now carries the same controls,
        -- generated from ns.COTANK_INDICATORS rather than written out five
        -- times - which is what stops "the crown can be moved but the role
        -- mark cannot" from ever becoming true.
        --
        -- The list lives in Core/CoTanks.lua next to the code that draws
        -- them, because the artwork and the anchor belong together.
        marker = { show = true,  size = 16, anchor = "LEFT",     x = 2,  y = 0 },
        leader = { show = true,  size = 12, anchor = "TOPLEFT",  x = -2, y = 4 },
        role   = { show = false, size = 14, anchor = "RIGHT",    x = -2, y = 0 },
        combat = { show = false, size = 14, anchor = "TOPRIGHT", x = 2,  y = 4 },

        -- A SECOND BORDER when that tank is your target, not a "ring": it is
        -- drawn exactly like the border above, and the owner said so - "das
        -- ist einfach nur ein border". It answers "am I taunting the right
        -- one" without moving your eyes off the health.
        targetBorder = {
            show = true,
            size = 2,
            color = { 1.00, 0.82, 0.20 },
        },

        deadFade      = 0.45,
        offlineFade   = 0.45,
        rangeFade     = true,
        rangeAlpha    = 0.45,

        -- Aura strips. One per polarity, growing away from opposite ends of
        -- the row so they cannot collide in the middle.
        --
        -- LIVE DATA NEEDS PATCH 12.1. Auras on another player are secret on
        -- this client and no addon may read them at all; the sanctioned route
        -- is Blizzard's AuraContainer, which arrives with 12.1. Until then the
        -- strips draw in TEST MODE only - so every setting here is adjustable
        -- today and correct the moment the patch lands. The panel says this in
        -- as many words rather than showing an empty strip.
        debuffs = {
            show = true, max = 8, size = 22, spacing = 1, perRow = 8,
            anchor = "BOTTOMLEFT", growth = "right",
            x = 0, y = 0,
            borderSize = 1, borderColor = { 0.75, 0.15, 0.15 },
            countdown = true, countdownSize = 0,
            stacks = true, stacksSize = 0,
        },
        buffs = {
            show = true, max = 8, size = 22, spacing = 1, perRow = 8,
            anchor = "BOTTOMRIGHT", growth = "left",
            x = 0, y = 0,
            borderSize = 1, borderColor = { 0.25, 0.55, 0.30 },
            countdown = true, countdownSize = 0,
            stacks = true, stacksSize = 0,
        },
    },
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Recursive default fill: adds missing keys, never overwrites user values.
function ns.ApplyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            ns.ApplyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

function ns.Print(...)
    print("|cff7ec6d4Zwoelf|r|cffff7a3dStuff|r:", ...)
end

---------------------------------------------------------------------------
-- Which class and spec is playing
--
-- "DEATHKNIGHT:250". The key everything per-character is filed under: the
-- recorded procs, and since 4.10.0 the spells on each bar as well.
--
-- Returns the key AND whether the spec is really known. Right after login the
-- API can answer 0 for a while, and filing anything under "DEATHKNIGHT:0" is
-- how a character's picks end up somewhere nothing will ever look for them.
-- Callers that WRITE have to check the second value; callers that read do not.
---------------------------------------------------------------------------
local specKey, specKnown

function ns.SpecKey()
    if specKnown then return specKey, true end

    local _, class = UnitClass("player")
    if not class then return nil, false end

    local specID = 0
    local info = C_SpecializationInfo
    if info and info.GetSpecialization and info.GetSpecializationInfo then
        local ok, index = pcall(info.GetSpecialization)
        if ok and index then
            local okID, id = pcall(info.GetSpecializationInfo, index)
            if okID and id then specID = id end
        end
    end

    specKey = class .. ":" .. specID
    specKnown = specID ~= 0
    return specKey, specKnown
end

-- A spec change makes the cached answer wrong, and nothing else does.
function ns.ForgetSpecKey()
    specKey, specKnown = nil, nil
end

function ns.SpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellID)
    end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    return info and info.name
end

-- Resolves a spell name to its ID using the player's own client, so no spell
-- ID ever has to be hardcoded or guessed.
function ns.SpellIDByName(name)
    if not name or name == "" then return nil end
    if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
    local ok, info = pcall(C_Spell.GetSpellInfo, name)
    if ok and info and info.spellID then return info.spellID end
    return nil
end

-- Has the character got this spell in the build it is in right now?
--
-- C_SpellBook.IsSpellKnownOrInSpellBook, not the older IsPlayerSpell that the
-- reference CDM picker still calls: that one is flagged deprecated, and
-- BigWigs on this client already uses the current form. It touches no aura
-- data, so it is legal on 12.0.
--
-- A missing API means "assume known": greying out everything would be far
-- worse than greying out nothing.
function ns.IsSpellKnown(spellID)
    local isKnown = C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook
    if not (isKnown and spellID) then return true end
    local ok, known = pcall(isKnown, spellID)
    if not ok then return true end
    return known and true or false
end

function ns.SpellTexture(spellID)
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellID)
    end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    return info and info.iconID
end

-- Font paths are read from live font objects, so no hardcoded path can break.
--
-- Two fonts, because they have different jobs. The number font is built for
-- digits over a busy 3D scene - tight, heavy, outlined - and it is the right
-- choice for a cooldown countdown on an icon. It is the wrong choice for
-- panel text, where it reads cramped and slightly wrong at every size. Panel
-- text uses the client's own UI font instead.
function ns.StyleFont(fontString, size, flags)
    local path = NumberFontNormalLarge:GetFont()
    fontString:SetFont(path, size, flags or "OUTLINE")
end

-- THE PANEL FONT IS THE ONE THE USER PICKED, not the client's.
--
-- This read GameFontHighlight, which is the client's default UI face - wide,
-- round, and the reason the window looked nothing like the design it was
-- built from. The design names a narrow grotesk, Settings already offers a
-- "Panel font" picker, and every string in the window ignored it.
--
-- Falls back down the chain rather than assuming: the library may not have
-- loaded yet when the very first string is styled at login.
-- THE PANEL FONT, BY PATH, NOT BY NAME.
--
-- LibSharedMedia is a registry of NAMES. Any addon that loads after this one
-- can register "Expressway" over a different file, and then the window is
-- drawn in whatever that addon felt like - which is the one thing a design
-- system must not leave to chance.
--
-- This is a path into the client's own Fonts directory. It ships with every
-- installation, it is the narrow grotesk the design asks for, and nothing any
-- other addon does can move it.
-- A long string, so the backslash is a backslash. "Fonts\A..." in quotes is
-- an invalid escape and takes the whole file down at load - which has now
-- happened twice, both times via a script writing this line.
ns.PANEL_FONT = [[Fonts\ARIALN.TTF]]

function ns.StyleUIFont(fontString, size, flags)
    -- A font the USER picked still wins - that is a choice, not an accident.
    local path
    if ns.db and ns.db.panelFont and ns.Media then
        path = ns.Media.Font(ns.db.panelFont)
    end
    path = path or ns.PANEL_FONT

    -- SetFont reports whether the file loaded. It will not on a client whose
    -- locale needs glyphs this file does not carry, and a font string that
    -- silently failed to take a font renders nothing at all.
    if not fontString:SetFont(path, size, flags or "") then
        local fallback = GameFontHighlight and GameFontHighlight:GetFont()
            or NumberFontNormalLarge:GetFont()
        fontString:SetFont(fallback, size, flags or "")
    end
end

-- Every font string inside a widget, styled with the number font. Used on
-- Blizzard's cooldown countdown, which has no stable name - it is simply a
-- region of the Cooldown widget, so it is found rather than looked up.
--
-- anchor moves the text off centre. Blizzard's engine sets its own baseline
-- for the countdown, so ours is applied on top rather than instead - which
-- also means an anchor of CENTER is left alone, because that is already
-- where the engine puts it and re-anchoring it can only go wrong.
-- Where one of the nine positions actually puts a number, nudge included.
--
-- The inset keeps an outlined glyph off the border: a corner position with no
-- inset has its outline clipped by the edge it sits in, which reads as a
-- blurry number rather than as a placement problem.
--
-- ONE function, because there are two renderers - Blizzard's adopted frames
-- and the cells this addon draws - and they sit next to each other on the
-- same bar. A position that means something slightly different on each is
-- exactly the disagreement the whole styling pass exists to end.
function ns.TextOffset(text)
    local inset = 2
    local x = (text.anchor:find("LEFT") and inset
        or text.anchor:find("RIGHT") and -inset or 0) + text.x
    local y = (text.anchor:find("TOP") and -inset
        or text.anchor:find("BOTTOM") and inset or 0) + text.y
    return x, y
end

-- A font string OF OUR OWN, given a text element's font and its place. The
-- counterpart to StyleNumbers below, which has to go looking for somebody
-- else's font strings inside a frame we do not own.
function ns.PlaceText(fontString, parent, text)
    if not (fontString and parent and text) then return end

    ns.Media.ApplyFont(fontString, text.font, text.size, text.outline, text.color)

    local x, y = ns.TextOffset(text)
    fontString:ClearAllPoints()
    fontString:SetPoint(text.anchor, parent, text.anchor, x, y)
end

-- A LABEL HUNG FROM BOTH EDGES OF A BAND, never given a width.
--
-- The counterpart to PlaceText above: that one is for a NUMBER, which sits in
-- a corner and is nudged from it; this is for a WORD, which needs a box to be
-- left, centred or right in.
--
-- A width is a number taken once. Measured from the arrangement and handed to
-- SetWidth, the box stayed the size it was when the bar was that size - widen
-- the bar and a right-aligned name sat at the old right edge, which is the
-- owner's "der container waechst nicht mit der bar breite mit, sondern ist
-- fest". Two horizontal points instead: the box IS the band, it follows
-- whatever it is anchored to, and there is no moment during layout when a
-- frame that has not been sized yet reports zero. The position no longer
-- decides the box at all - the box is always the whole band, and where the
-- words sit inside it is the justification.
--
-- Shared rather than copied, because the co-tank rows need exactly this and a
-- second implementation would have started out right and drifted.
function ns.PlaceLabel(label, parent, text, leftInset, rightInset)
    if not (label and parent) then return end
    local x, y = (text and text.x) or 0, (text and text.y) or 0
    local _, _, justify, vertical = ns.Layout.LabelAnchor(text and text.anchor)

    label:ClearAllPoints()
    label:SetPoint(vertical .. "LEFT", parent, vertical .. "LEFT",
        (leftInset or 0) + x, y)
    label:SetPoint(vertical .. "RIGHT", parent, vertical .. "RIGHT",
        -(rightInset or 0) + x, y)
    label:SetJustifyH(justify)
end

-- Just the FONT on every font string inside a widget. Used where the position
-- is set on the widget itself rather than on the text inside it - the stack
-- and charge counters, which are frames of their own.
function ns.StyleNumberFont(widget, text)
    if not (widget and text) then return end

    for _, region in ipairs({ widget:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "FontString" then
            ns.Media.ApplyFont(region, text.font, text.size, text.outline,
                text.color)
        end
    end
end

function ns.StyleNumbers(widget, text)
    if not (widget and text) then return end

    ns.StyleNumberFont(widget, text)

    -- Left alone at CENTER with no offset: that is already where Blizzard's
    -- engine puts its countdown, and re-anchoring it can only go wrong.
    -- Anywhere else we have to say so ourselves.
    if text.anchor == "CENTER" and text.x == 0 and text.y == 0 then return end

    local x, y = ns.TextOffset(text)
    for _, region in ipairs({ widget:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "FontString" then
            -- NOT reparented, only re-anchored. Moving one of these font
            -- strings to another parent makes the engine re-centre it and
            -- ignore both the position and the offset
            -- (EllesmereUICooldownManager.lua:5934-5941).
            region:ClearAllPoints()
            region:SetPoint(text.anchor, widget, text.anchor, x, y)
        end
    end
end

---------------------------------------------------------------------------
-- The countdown number, which is not there when you go looking for it
--
-- A Cooldown widget's number is drawn by the engine, and the font string it
-- draws into DOES NOT EXIST until a cooldown is actually running on that
-- widget. Styling happens on a render pass, and on a render pass almost
-- nothing is on cooldown - so the walk above found no font string, styled
-- nothing, and the moment a cooldown started the engine made one with its own
-- font in its own place.
--
-- That is the whole of "the countdown position and the nudges do nothing".
-- Not the arithmetic, not the setting, not the panel: the thing being styled
-- had not been created yet.
--
-- So the style is REMEMBERED against the widget and re-applied every time a
-- cooldown is set on it. A frame later, deliberately: the engine builds the
-- number during the draw that follows the call, so doing it inline would
-- still find nothing on the first cooldown of the session.
---------------------------------------------------------------------------

-- Weak keys throughout: these hold Blizzard's frames, and a strong reference
-- from an addon is how a pooled frame never gets collected.
local countdownStyle = setmetatable({}, { __mode = "k" })
local countdownQueued = setmetatable({}, { __mode = "k" })

-- Both ways a cooldown can be armed on this patch. The second takes a secret
-- duration object and is what the Cooldown Manager uses for anything whose
-- timing is protected - hooking only the first would miss exactly the frames
-- this addon adopts.
local COOLDOWN_SETTERS = { "SetCooldown", "SetCooldownFromDurationObject" }

function ns.StyleCountdown(cooldown, text)
    if not (cooldown and text) then return end

    local first = countdownStyle[cooldown] == nil
    countdownStyle[cooldown] = text

    -- Now, for the case where a cooldown is already running on it.
    ns.StyleNumbers(cooldown, text)

    if not first then return end

    for _, setter in ipairs(COOLDOWN_SETTERS) do
        if type(cooldown[setter]) == "function" then
            hooksecurefunc(cooldown, setter, function(self)
                -- One queued pass per widget. A refresh can arm the same
                -- cooldown several times in a row, and one timer each would
                -- be a queue that grows with the fight.
                if countdownQueued[self] then return end
                countdownQueued[self] = true

                C_Timer.After(0, function()
                    countdownQueued[self] = nil
                    local wanted = countdownStyle[self]
                    if wanted then ns.StyleNumbers(self, wanted) end
                end)
            end)
        end
    end
end

function ns.FormatTime(remaining)
    if remaining >= 60 then
        return string.format("%d:%02d", math.floor(remaining / 60), math.floor(remaining % 60))
    elseif remaining >= 10 then
        return string.format("%d", math.floor(remaining))
    end
    return string.format("%.1f", remaining)
end

-- One-pixel border built from color textures - no texture files, no library.
function ns.CreateBorder(frame, thickness, layer)
    local border = { thickness = thickness or 1 }
    local edges = { "TOP", "BOTTOM", "LEFT", "RIGHT" }

    for _, edge in ipairs(edges) do
        border[edge] = frame:CreateTexture(nil, layer or "OVERLAY")
    end

    function border:SetColor(r, g, b, a)
        for _, edge in ipairs(edges) do
            self[edge]:SetColorTexture(r, g, b, a or 1)
        end
    end

    -- Solid or gradient, in the shape the rest of the addon uses.
    --
    -- A BORDER IS NOT A SURFACE, and the difference is the whole of this
    -- function. A gradient across a rectangle is one ramp over one quad; a
    -- gradient across a FRAME is four separate strips, and only two of them
    -- run along the ramp at all. The other two sit at its ends, so each takes
    -- the single colour of the end it is on - ramping them as well draws two
    -- little rainbows at right angles to the one you asked for.
    --
    --   HORIZONTAL  TOP and BOTTOM carry the ramp; LEFT is its start colour
    --               and RIGHT its end colour.
    --   VERTICAL    LEFT and RIGHT carry it; BOTTOM starts and TOP ends.
    function border:SetTint(colour, alpha, gradient)
        alpha = alpha or 1

        local on = gradient and gradient.on
        local orientation, swap = ns.Layout.GradientOrder(
            gradient and gradient.direction)
        local from, to = colour, (gradient and gradient.color) or colour
        if swap then from, to = to, from end

        local along, startEdge, endEdge
        if on and orientation == "VERTICAL" then
            along, startEdge, endEdge = { "LEFT", "RIGHT" }, "BOTTOM", "TOP"
        else
            along, startEdge, endEdge = { "TOP", "BOTTOM" }, "LEFT", "RIGHT"
        end

        -- ALL FOUR go through ns.Tint, including the flat ones, and including
        -- the whole flat case. SetColorTexture cannot undo a gradient an edge
        -- was given a moment ago, so switching the ramp off - or turning it
        -- from vertical to horizontal - left the old one crossing the new.
        -- ns.Tint always sets a ramp; a solid colour is simply that colour
        -- twice.
        for _, edge in ipairs(along) do
            self[edge]:SetColorTexture(1, 1, 1, 1)
            ns.Tint(self[edge], colour, alpha, on and gradient or nil)
        end
        for _, pair in ipairs({ { startEdge, from }, { endEdge, to } }) do
            self[pair[1]]:SetColorTexture(1, 1, 1, 1)
            ns.Tint(self[pair[1]], pair[2], alpha, nil)
        end
    end

    -- This is a plain table of four textures, not a frame, so it has none of
    -- the frame visibility methods by default - callers reasonably expect
    -- them, and their absence only shows up at runtime.
    function border:SetShown(shown)
        for _, edge in ipairs(edges) do
            self[edge]:SetShown(shown and true or false)
        end
    end

    function border:Show() self:SetShown(true) end
    function border:Hide() self:SetShown(false) end

    function border:SetThickness(t)
        self.thickness = t

        self.TOP:ClearAllPoints()
        self.TOP:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        self.TOP:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        self.TOP:SetHeight(t)

        self.BOTTOM:ClearAllPoints()
        self.BOTTOM:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        self.BOTTOM:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        self.BOTTOM:SetHeight(t)

        self.LEFT:ClearAllPoints()
        self.LEFT:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -t)
        self.LEFT:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, t)
        self.LEFT:SetWidth(t)

        self.RIGHT:ClearAllPoints()
        self.RIGHT:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -t)
        self.RIGHT:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, t)
        self.RIGHT:SetWidth(t)
    end

    border:SetThickness(border.thickness)
    border:SetColor(0, 0, 0, 1)
    return border
end

-- Creates the starter group for the parked 12.1 tracking-group module,
-- exactly once per saved-variables file. Guarded by a flag rather than by "is
-- the list empty", so a user who deletes every group does not get one handed
-- back at the next login.
function ns.SeedGroups()
    if ns.db.groupsSeeded then return end
    ns.db.groupsSeeded = true

    local seed = {}
    ns.ApplyDefaults(seed, ns.GROUP_DEFAULTS)
    seed.name = ns.SpellName(ns.PRIMARY_SPELL_ID) or "Tracker"
    seed.spells = { ns.PRIMARY_SPELL_ID }

    ns.db.groups[#ns.db.groups + 1] = seed
end

---------------------------------------------------------------------------
-- WHOSE SETTINGS THESE ARE
--
-- Owner, 2026-08-07: "mach ich eine Ã¤nderung am ui oder egal was, muss das
-- unter dem charakter namen und server gespeichert werden".
--
-- So the file holds one profile per character, keyed "Name - Realm" - the
-- same key EllesmereUI uses on this client, verified rather than invented.
-- Everything you can change is in there: the bars, their looks, where they
-- sit, the font, unlock-mode habits, the minimap button.
--
-- WHAT STAYS SHARED, and it is not a UI setting: the recorded procs, the
-- aura links and the list of shipped procs somebody threw away. Those are
-- MEASUREMENTS - hours of playing to collect, identical for anyone of that
-- class and spec, and impossible to type back in. Filing them per character
-- would make every alt start the recording again from nothing.
--
-- The owner's own reason for the split, verbatim: "sonst wird das pro klasse
-- oder spec ja jedes mal Ã¼berschrieben". Two characters of one class were
-- writing over each other, and no keying by class or spec can fix that -
-- only keying by the character.
---------------------------------------------------------------------------
function ns.CharacterKey()
    local name = UnitName("player")
    if not name then return nil end
    local realm = GetRealmName and GetRealmName() or ""
    return name .. " - " .. realm
end

-- The measurements, shared by every character on the account.
local ACCOUNT_DEFAULTS = {
    procs       = {},
    auraLinks   = {},
    procsHidden = {},

    -- CUSTOM ACTIVE STATES: [spellID] = seconds.
    --
    -- "This is active for twenty seconds after I press it." For the things
    -- Blizzard's Cooldown Manager shows as a cooldown and nothing more - a
    -- trinket's use effect, a potion, a racial - where the buff it grants is
    -- not a tracked buff and so has no clock anywhere on screen.
    --
    -- ACCOUNT-WIDE, and for the same reason the recorded procs are: how long
    -- a trinket lasts is a fact about the trinket, identical on every
    -- character. It is not a piece of user interface, so it does not belong
    -- to a profile.
    activeStates = {},
}

function ns.OpenProfile()
    local store = ZwoelfStuffDB

    -- A file written before profiles existed: everything in it belonged to
    -- whoever was playing, so it becomes that character's profile and the
    -- measurements are lifted out to the account.
    if store.chars == nil then
        local old = {}
        for key, value in pairs(store) do
            old[key] = value
            store[key] = nil
        end

        store.account = {}
        for key in pairs(ACCOUNT_DEFAULTS) do
            store.account[key] = old[key]
            old[key] = nil
        end

        store.chars = {}
        local key = ns.CharacterKey()
        if key and next(old) then store.chars[key] = old end
    end

    store.account = ns.ApplyDefaults(store.account or {}, ACCOUNT_DEFAULTS)
    ns.account = store.account

    local key = ns.CharacterKey() or "unknown"
    store.chars[key] = store.chars[key] or {}

    -- BEFORE ApplyDefaults, never after. A migration that runs afterwards is
    -- overwritten by the default it was meant to replace on the very next
    -- login, which is the class of bug that eats a saved setting in silence.
    -- Same placement, and the same reasoning, as the fill-direction migration
    -- in Bars:Prepare.
    if ns.CoTanks and ns.CoTanks.Migrate then
        pcall(ns.CoTanks.Migrate, ns.CoTanks, store.chars[key].coTanks)
    end

    ns.db = ns.ApplyDefaults(store.chars[key], ns.DEFAULTS)
    ns.profileKey = key
end

-- Every other character with a profile, newest list built on demand because
-- it changes whenever somebody else logs out.
function ns.OtherProfiles()
    local out = {}
    if not (ZwoelfStuffDB and ZwoelfStuffDB.chars) then return out end

    for key, profile in pairs(ZwoelfStuffDB.chars) do
        if key ~= ns.profileKey and type(profile) == "table" then
            out[#out + 1] = { key = key, bars = #(profile.bars or {}) }
        end
    end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")

boot:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        ZwoelfStuffDB = ZwoelfStuffDB or {}
        ns.OpenProfile()

        -- Before Seed and before Prepare: everything below this line reads a
        -- bar, and a migration that runs after the first read is a migration
        -- that fixed nothing.
        ns.Bars:Migrate()
        ns.Bars:Seed()
        ns.Bars:Prepare()

        -- Same reason, one line down: a reminder saved before a setting
        -- existed has to gain it before anything reads it.
        ns.Reminders:Migrate()

        -- Auras deliberately has no seeding step, and calling one here used to
        -- throw on every login. Its recorder registers itself when the file
        -- loads, and the shipped procs are merged when the list is READ -
        -- copying them into saved variables would freeze today's data into
        -- every profile and make the next update invisible.

    elseif event == "PLAYER_LOGIN" then
        -- Each feature boots on its own. They used to run in one straight
        -- line, so the first error took every later feature down with it -
        -- one broken tracking group meant no co-tank panel and no minimap
        -- button, which looks like "the whole addon is dead" and hides which
        -- part actually failed. Errors are reported, never swallowed.
        local function Boot(name, fn)
            local ok, err = pcall(fn)
            if not ok then
                ns.Print("|cffff4040" .. name .. " failed to start.|r Everything else still runs.")
                geterrorhandler()(err)
            end
            return ok
        end

        Boot("Cooldown Manager", function()
            ns.CDM:HookPools()
            -- The spell list is a live view of the Cooldown Manager, so a
            -- talent or spec change has to reach an open window.
            ns.CDM:OnChanged(function() ns.Options:OnCatalogChanged() end)
        end)
        -- After the Cooldown Manager, and not before: the first render claims
        -- Blizzard's item frames, and there is nothing to claim until its
        -- pools have been walked once.
        Boot("Bars", function() ns.Screen:Start() end)
        -- Built even when switched off, because the panel's preview and
        -- test mode both need the frames to exist before anybody turns
        -- it on. Create() draws nothing until Refresh decides to.
        Boot("Co-tanks", function() ns.CoTanks:Create() end)
        -- After the Cooldown Manager for the same reason the bars are: a
        -- reminder asks CDM whether its spell is active, and before the pools
        -- have been walked once the honest answer is "not tracked" for
        -- everything.
        Boot("Reminders", function()
            ns.Reminders:Rebuild()
            ns.Reminders:Start()
        end)
        -- MDT may load after us, so the route is read on demand rather than
        -- here: Start only puts the listeners up.
        Boot("Routes", function()
            ns.Routes:Sync()
            ns.Routes:Start()
        end)
        Boot("Minimap button", function() ns.MinimapButton:Create() end)
        Boot("Game menu entry", function() ns.GameMenu:Create() end)
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function ToNumber(value, min, max)
    local n = tonumber(value)
    if not n then return nil end
    if min and n < min then n = min end
    if max and n > max then n = max end
    return n
end

-- Only commands that exist. A usage list that offers a command the addon no
-- longer has is worse than no list: it sends people looking for a feature.
local usage = {
    "|cff7ec6d4Zwoelf|r|cffff7a3dStuff|r - commands:",
    "  |cffffd100/zs|r - open the window",
    "  |cffffd100/zs unlock|r / |cffffd100lock|r - move the bars around the screen",
    "  |cffffd100/zs build|r - take a bar apart slot by slot, on screen",
    "",
    "  Bars",
    "  |cffffd100/zs bars|r - list them (|cffffd100add <name>|r / |cffffd100remove <n>|r)",
    "  |cffffd100/zs cdm|r - what Blizzard's Cooldown Manager currently holds",
    "  |cffffd100/zs skin|r - what is actually drawn on one adopted icon",
    "",
    "  Auras",
    "  |cffffd100/zs auras|r - the procs seen on this spec, and what drives them",
    "  |cffffd100/zs report|r - open the proc report in a box you can copy from",
    "  |cffffd100/zs auras export|r - the same thing, under its older name",
    "  |cffffd100/zs auras icon <glowID> <spellID>|r - which icon a proc shows",
    "  |cffffd100/zs auras bind <glowID> <auraID>|r - name the buff (12.1 route)",
    "  |cffffd100/zs auras forget <glowID>|r - drop one, shipped ones included",
    "  |cffffd100/zs auras remember|r - put every forgotten one back",
    "",
    "",
    "  Tank stuff",
    "  |cffffd100/zs tanks|r - the co-tank panel (|cffffd100test|r fakes a raid)",
    "  |cffffd100/zs reminders|r - every reminder, and why each one is or is not up",
    "  |cffffd100/zs route|r - your MDT pull on the mobs (|cffffd100next|r / |cffffd100prev|r / |cffffd100reset|r)",
    "",
    "  |cffffd100/zs test|r - run the addon's own checks and report failures",
    "  |cffffd100/zs minimap|r - show or hide the minimap button",
    "  |cffffd100/zs reset|r - restore defaults, keeping recorded procs",
}

SLASH_ZWOELFSTUFF1 = "/zs"
SLASH_ZWOELFSTUFF2 = "/zwoelfstuff"

SlashCmdList.ZWOELFSTUFF = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    local db = ns.db

    if cmd == "" then
        ns.Options:Toggle()

    elseif cmd == "unlock" or cmd == "lock" then
        ns.EditMode:SetUnlocked(cmd == "unlock")

    elseif cmd == "build" then
        -- Unlocks first if it has to. "Build" names an intent, not a mode you
        -- have to be in something else to reach.
        ns.EditMode:OpenBuild()

    elseif cmd == "minimap" then
        local sub = rest:lower()
        if sub == "on" or sub == "show" then
            ns.MinimapButton:SetShown(true)
        elseif sub == "off" or sub == "hide" then
            ns.MinimapButton:SetShown(false)
        elseif sub == "lock" or sub == "unlock" then
            db.minimap.locked = (sub == "lock")
            ns.Print("Minimap button", db.minimap.locked and "locked" or "unlocked")
        else
            ns.MinimapButton:SetShown(not db.minimap.show)
        end

    elseif cmd == "cdm" then
        ns.CDM:Dump()

    elseif cmd == "skin" then
        ns.Screen:DumpCells()
        ns.CDM:DumpSkin()

    -- "Position does nothing" has now been answered three times by reading the
    -- code, and been wrong three times. This asks the frames instead: what the
    -- setting says against where the font string actually ended up.
    elseif cmd == "text" then
        ns.Screen:DumpText()

    -- The third diagnostic of its kind, and written for the same reason as
    -- the other two: a number appeared on a cell that nothing in the code
    -- says should be there, and reading the code says which font string
    -- SHOULD print what - not which one IS printing a nought.
    elseif cmd == "numbers" then
        ns.Screen:DumpNumbers()

    -- Co-tanks. The panel owns the settings; these three are the ones worth
    -- reaching without opening a window - move it, fake a raid, put it away.
    elseif cmd == "tanks" or cmd == "cotanks" then
        local sub = (rest or ""):match("^(%S*)"):lower()
        if sub == "test" then
            ns.CoTanks:SetTestMode(not db.coTanks.testMode)
            ns.Print("Co-tank test mode",
                db.coTanks.testMode and "|cff40ff40on|r" or "|cff888888off|r")
        -- Both of these now go through EDIT MODE, because that is where
        -- everything this addon draws is placed. Two ways to move one thing,
        -- with two different sets of rules, is one way too many.
        elseif sub == "unlock" or sub == "move" then
            ns.EditMode:SetUnlocked(true, "bars")
        elseif sub == "lock" then
            ns.EditMode:SetUnlocked(false)
        else
            db.coTanks.enabled = not db.coTanks.enabled
            ns.CoTanks:Refresh()
            ns.Print("Co-tanks",
                db.coTanks.enabled and "|cff40ff40on|r" or "|cff888888off|r")
        end

    -- Reminders. One command, and it is the diagnostic rather than a toggle:
    -- "why is my reminder not showing" is the only question anybody has about
    -- this feature, and it has a printable answer.
    elseif cmd == "reminders" or cmd == "reminder" then
        ns.Reminders:Dump()

    -- Routes. The diagnostic first, again: "it is not marking anything" has
    -- three causes - no MDT, no route open, or the mobs in front of you are
    -- not in it - and they look identical on screen.
    elseif cmd == "route" or cmd == "routes" then
        local sub = (rest or ""):match("^(%S*)"):lower()
        if sub == "next" then
            ns.Routes:Step(1)
            ns.Print("Pull", ns.Routes.index)
        elseif sub == "prev" or sub == "back" then
            ns.Routes:Step(-1)
            ns.Print("Pull", ns.Routes.index)
        elseif sub == "reset" then
            ns.Routes:Sync()
            ns.Routes:ResetRun()
            ns.Print("Route re-read, back to pull 1.")
        elseif sub == "probe" then
            -- Every question about a mob at once, and what came back. Its own
            -- word because it is the thing to run when a badge is missing and
            -- the rest of the report already looks correct.
            ns.Routes:Probe()
        else
            ns.Routes:Sync()
            ns.Routes:Dump()
        end

    elseif cmd == "test" then
        ns.SelfTest:Run()

    -- Its own top-level name, because this is the one command a TESTER runs
    -- and "auras export" is filed under a word they have no reason to look in.
    elseif cmd == "report" then
        ns.Auras:Export()

    elseif cmd == "auras" then
        local sub, arg = rest:match("^(%S*)%s*(.-)$")
        sub = (sub or ""):lower()

        -- The numbers, wherever they sit in the argument. Anchoring the match
        -- to the whole string meant a pasted line with a note after the ID
        -- ("49020  Obliterate") was rejected as "no number given", which reads
        -- as the command being broken rather than the paste being untidy.
        local first, second = arg:match("(%d+)%D+(%d+)")
        if not first then first = arg:match("(%d+)") end

        if sub == "export" then
            ns.Auras:Export()

        elseif sub == "bind" then
            -- Two IDs: the ability that lights up, then the aura itself.
            if first and second then
                ns.Auras:SetAura(tonumber(first), tonumber(second))
            else
                ns.Print("Usage: |cffffd100/zs auras bind <glowID> <auraID>|r")
                ns.Print("The first is the ability whose button lights up, the second")
                ns.Print("is the buff itself - only patch 12.1 needs the second one.")
            end

        elseif sub == "icon" then
            if first and second then
                ns.Auras:SetDisplay(tonumber(first), tonumber(second))
            else
                ns.Print("Usage: |cffffd100/zs auras icon <glowID> <spellID>|r")
            end

        elseif sub == "remember" then
            ns.Auras:Remember()

        elseif sub == "forget" then
            local id = tonumber(first)
            if not id then
                ns.Print("Usage: |cffffd100/zs auras forget <glowID>|r")
                ns.Print("|cffffd100/zs auras remember|r puts every forgotten one back.")
            elseif not ns.Auras:Forget(id) then
                ns.Print("No proc recorded on", id, "for this spec.")
                ns.Print("The ID is the one on the RIGHT in |cffffd100/zs auras|r - "
                    .. "the ability that lights up, not the icon shown.")
            end

        else
            ns.Auras:Dump()
        end

    elseif cmd == "bars" then
        local sub, arg = rest:match("^(%S*)%s*(.-)$")
        sub = (sub or ""):lower()

        if sub == "add" then
            local index = ns.Bars:Add(arg ~= "" and arg or nil, "icon")
            ns.Print("Added bar", index, "-", ns.Bars:Get(index).name)
        elseif sub == "remove" or sub == "rem" then
            local index = ToNumber(arg)
            if index and ns.Bars:Remove(index) then
                ns.Print("Removed bar", index)
            else
                ns.Print("Usage: |cffffd100/zs bars remove <number>|r")
            end
        else
            if ns.Bars:Count() == 0 then
                ns.Print("No bars yet - open |cffffd100/zs|r and press New icon bar.")
            end
            for i, cfg in ipairs(ns.Bars:All()) do
                local filled = 0
                for cell = 1, ns.Bars:CellCount(cfg) do
                    if cfg.cells[cell] then filled = filled + 1 end
                end
                ns.Print(string.format("%d. %s |cff888888(%s, %dx%d, %d filled)|r%s",
                    i, cfg.name, cfg.kind, cfg.rows, cfg.columns, filled,
                    cfg.enabled and "" or " |cffff4040disabled|r"))
            end
        end

    elseif cmd == "reset" then
        -- Recorded procs survive. They are measurements that took hours of
        -- playing to collect and cannot be typed back in, so they are not
        -- "settings" - /zs auras forget is how those go away.
        local procs = ns.account.procs
        ZwoelfStuffDB = {}
        ns.db = ns.ApplyDefaults(ZwoelfStuffDB, ns.DEFAULTS)
        ns.account.procs = procs or ns.account.procs
        ns.Bars:Seed()
        ns.Bars:Prepare()
        ns.Auras:Invalidate()
        ns.Bars:Changed()
        if ns.Options.Refresh then ns.Options:Refresh() end
        ns.Print("Settings reset to defaults. Recorded procs kept.")

    else
        for _, line in ipairs(usage) do print(line) end
    end
end

function ZwoelfStuff_OnAddonCompartmentClick()
    ns.Options:Toggle()
end
