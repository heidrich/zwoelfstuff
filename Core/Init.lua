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

-- OFF THE TOC, not typed a second time. This was a literal and it had drifted
-- three versions behind the one the packager ships - and it is the number the
-- window shows, the About page prints and a shared profile is stamped with,
-- so it was wrong in all three places at once. The literal below is only what
-- answers when the client has no metadata call at all.
ns.version = (function()
    local get = C_AddOns and C_AddOns.GetAddOnMetadata
    if get then
        local ok, value = pcall(get, ADDON, "Version")
        if ok and type(value) == "string" and value ~= "" then return value end
    end
    return "0.0.0"
end)()

-- The addon's own mark, used by the minimap button. Kept next to the TOC's
-- IconTexture line so the two cannot drift apart.
ns.ICON_TEXTURE = "Interface\\AddOns\\ZwoelfStuff\\Media\\logo"

-- WHERE THIS LIVES, written down once.
--
-- The About page shows both, the rail's foot shows the Discord one, and the
-- release announcement prints the CurseForge one - and the one thing worse
-- than no address is three that disagree. (.github/scripts/discord_release.py
-- has its own copy of the CurseForge line because it runs on a machine where
-- this file does not exist; that is the one place it is repeated, and it is
-- repeated on purpose.)
--
-- Neither of these can be OPENED from here. No addon can: the client has no
-- call that hands a URL to a browser, by design. So a click puts the address
-- in a box you can copy from, which is the honest version of a link in a game.
ns.CURSEFORGE_URL = "https://www.curseforge.com/wow/addons/zwoelfstuff"
ns.WAGO_URL = "https://addons.wago.io/addons/zwoelfstuff"
ns.DISCORD_URL = "https://discord.gg/d2EnXGNbGu"

-- Both stores get the same build from the same tag - the packager uploads to
-- whichever it has a token and a project id for. They are listed in the order
-- they were published in, and neither is "the real one".
ns.STORES = {
    { name = "CurseForge", url = ns.CURSEFORGE_URL },
    { name = "Wago", url = ns.WAGO_URL },
}

-- The aura this addon was built for: the Boiling Point buff, 15s, Blood
-- Death Knight. Everything user-facing resolves the name from the client at
-- runtime (ns.SpellName / aura.name) - the ID is the only fixed fact here.
ns.PRIMARY_SPELL_ID = 1265968

ns.WHITE = "Interface\\Buttons\\WHITE8X8"

---------------------------------------------------------------------------
-- THE HOUSE LOOK: one surface colour, one face, one floor.
--
-- Owner, 2026-08-16, three sentences and one design:
--
--   "standard BG farben bei allem -> 100% 1a1a1a bitte bei allen bg farben
--    und Border Farben einfuegen ... also icons, bars, border. ueberall im
--    addon"
--   "standard Fonts ausserhalb von der addon font ist expressway mit outline
--    und minimum 10 pixel"
--   "nimm das automatisch bitte raus. wir muessen den usern direkt vom start
--    weg eine schoene ui anbieten"
--
-- THE LAST SENTENCE IS THE REASON THIS BLOCK EXISTS AT ALL. Every one of
-- these numbers was already written down - fourteen times for the colour, in
-- fourteen files, each of them the literal `{ 0, 0, 0 }`. Fourteen copies of
-- one decision is not fourteen settings, it is one setting that cannot be
-- changed: the next person to want a different surface has to find all of
-- them and will find thirteen. "A second copy of a list is already stale."
--
-- So they are named once here, above everything that draws, and every default
-- table below and in every other file asks for them by name.
---------------------------------------------------------------------------

-- #1a1a1a. ONE NUMBER, because the colour is a grey and r = g = b is a fact
-- about it rather than a coincidence three literals have to keep agreeing on.
ns.SURFACE = 0x1a / 255

-- A FRESH TABLE EVERY CALL, and that is not caution for its own sake: half
-- the modules in this addon write their fallback straight into the profile
-- (`cfg.borderColor = cfg.borderColor or ...`), so one shared table handed to
-- two profiles is one colour picker moving two panels - and the bug would
-- only show up on the second character somebody made.
function ns.SurfaceColor()
    local v = ns.SURFACE
    return { v, v, v }
end

-- The same colour for the setters that take four numbers rather than a table.
-- Opaque unless something asks otherwise: "100% 1a1a1a" is one instruction,
-- and a surface at 90% over a moving scene is never the colour it names.
function ns.SurfaceRGB(alpha)
    local v = ns.SURFACE
    return v, v, v, alpha == nil and 1 or alpha
end

-- WHAT THE ADDON WRITES ON THE SCREEN IS SET IN EXPRESSWAY. Not the options
-- window - that is "die addon font" and stays the narrow grotesk Media.lua
-- argues for. This is the other side of his sentence: the names, the numbers
-- and the counters out on the bars.
--
-- A NAME RATHER THAN A PATH, because it goes through LibSharedMedia and has
-- to survive being read back by a picker. Media.Font falls through
-- Media.SCREEN_FONTS when the client has no Expressway, so the worst case is
-- a different narrow grotesk rather than Blizzard's serif.
ns.SCREEN_FONT = "Expressway"

-- OUTLINED, ALWAYS. Everything this addon draws sits over a moving scene, and
-- an unoutlined glyph on a bright floor is the one thing that cannot be fixed
-- by picking a colour.
ns.SCREEN_OUTLINE = "OUTLINE"

-- THE FLOOR UNDER EVERY WORKED-OUT SIZE. His "minimum 10 pixel".
--
-- The automatic size STAYS - it is what keeps a 22px bar and a 64px icon
-- looking like one design, and it is not the "automatic" he asked me to take
-- out. What went out is the automatic FACE: a default that read "whatever
-- font your other addons happen to have installed" is not a default, and two
-- players comparing screenshots of one version saw different type.
ns.FONT_FLOOR = 10

-- WHICH FACE THE SCREEN IS SET IN, AND THERE IS ONLY ONE ANSWER TO IT.
--
-- `ns.db.font` is a real setting - "the font every piece of text on every bar
-- uses unless that one piece has been given its own" - and ns.SCREEN_FONT is
-- what it defaults to. Both are resolved HERE so that ns.StyleFont (tracking
-- groups) and Cooldowns.Text (bars and icons) cannot answer differently,
-- which is exactly what they used to do: one asked ns.db.font and the other
-- asked Blizzard for its number face.
--
-- Askable with no client and no saved variables, which is what lets the desk
-- prove it.
function ns.ScreenFontName()
    local chosen = ns.db and ns.db.font
    if type(chosen) == "string" and chosen ~= "" then return chosen end
    return ns.SCREEN_FONT
end

---------------------------------------------------------------------------
-- PUTTING THE HOUSE LOOK ON A PROFILE THAT ALREADY EXISTS
--
-- A changed default reaches a NEW profile and nothing else. Every setting
-- below has been written into the owner's saved variables for versions, so
-- "the standard background is #1a1a1a now" would have been a sentence that
-- changed nothing on the one screen it was written for. That is the oldest
-- failure in this project - a setting that kept its reader and lost its
-- writer - and it is why this function exists rather than a comment saying
-- "new profiles only".
--
-- ONE RULE, TWO CALLERS, and that is the whole design:
--
--   force = false   the version 7 -> 8 step in Profiles.Migrate. It moves
--                   only what still carries an OLD DEFAULT. A colour somebody
--                   PICKED is theirs; a default is not licence to reach into
--                   a saved setting.
--   force = true    the "Standard look" button in Settings. That button means
--                   "put it all back", so it does, and the person pressing it
--                   said so.
--
-- WALKED BY KEY NAME RATHER THAN BY A LIST OF PLACES. There are eleven
-- containers holding one of these settings today - answers, taunts,
-- externals, the raid bar, the co-tank panel, every bar, every tracking group
-- - and a list of them is a second copy that is stale the first time somebody
-- adds a twelfth. The walk asks what a key is CALLED, which is the one thing
-- that does not drift.
---------------------------------------------------------------------------

-- Keys whose value is a SURFACE: a plate behind something, the trough of a
-- bar, the line around it.
local SURFACE_COLOR = {
    backdropColor = true, borderColor = true,
    bgColor = true, fillBackColor = true,
}
local SURFACE_ALPHA = { backdropAlpha = true, bgAlpha = true }

-- AND THE ONE PLACE A COLOUR OF THAT NAME IS NOT A SURFACE. The aura strips
-- on the co-tank panel are bordered red for a debuff and green for a buff,
-- and that line is the only thing that says which strip you are looking at.
-- Reached by the key that leads INTO the table, because that is all a walk
-- knows about where it is standing.
local NOT_A_SURFACE = { debuffs = true, buffs = true }

-- What the addon used to ship. Recognised rather than assumed: everything
-- else is somebody's choice.
local WAS_SURFACE = { { 0, 0, 0 }, { 0.05, 0.05, 0.06 } }
local WAS_ALPHA = { 0.9, 0.85 }

-- A TOLERANCE RATHER THAN `==`, because these numbers have been through
-- SavedVariables. The file is written as decimal text and read back as a
-- double, and 0.05 is not exactly representable either way - so an equality
-- test would answer "somebody picked this" for a value nobody ever touched.
local function SameColor(colour, r, g, b)
    if type(colour) ~= "table" then return false end
    return math.abs((tonumber(colour[1]) or -1) - r) < 0.005
        and math.abs((tonumber(colour[2]) or -1) - g) < 0.005
        and math.abs((tonumber(colour[3]) or -1) - b) < 0.005
end

local function WoreOldColor(colour)
    for _, was in ipairs(WAS_SURFACE) do
        if SameColor(colour, was[1], was[2], was[3]) then return true end
    end
    return false
end

local function WoreOldAlpha(value)
    for _, was in ipairs(WAS_ALPHA) do
        if type(value) == "number" and math.abs(value - was) < 0.005 then
            return true
        end
    end
    return false
end

-- Returns how many settings it moved, which is what the button reports and
-- what the desk asserts. A run that changes nothing answers 0 rather than
-- claiming success, so "it did nothing" and "there was nothing to do" are
-- told apart by the one number.
function ns.ApplyHouseLook(profile, force)
    if type(profile) ~= "table" then return 0 end
    local v, moved = ns.SURFACE, 0

    local function Walk(tbl, depth, guarded)
        for key, value in pairs(tbl) do
            if SURFACE_COLOR[key] then
                if not guarded and (force or WoreOldColor(value))
                    and not SameColor(value, v, v, v) then
                    tbl[key] = ns.SurfaceColor()
                    moved = moved + 1
                end

            elseif SURFACE_ALPHA[key] then
                if (force or WoreOldAlpha(value)) and value ~= 1 then
                    tbl[key] = 1
                    moved = moved + 1
                end

            elseif key == "outline" then
                -- ONLY AN EMPTY ONE, AND IN BOTH MODES. "" is no outline at
                -- all, which is the state his spell name shipped in and the
                -- reason it was the one element that disappeared over a
                -- bright floor. A THICKOUTLINE somewhere else is a choice
                -- with a reason - the reminder text is read across the whole
                -- screen - and flattening it would be this function deciding
                -- something nobody asked it to.
                if value == "" then
                    tbl[key] = ns.SCREEN_OUTLINE
                    moved = moved + 1
                end

            elseif key == "font" then
                -- THE ROOT `font` IS THE ONE SETTING FOR EVERY BAR; a `font`
                -- further down belongs to a single element and empty means
                -- "follow the root". So the root gets a name and the rest get
                -- put back to following it - and outside force mode only the
                -- old default is touched.
                if depth == 0 then
                    if force or value == "Arial Narrow" then
                        if value ~= ns.SCREEN_FONT then
                            tbl[key] = ns.SCREEN_FONT
                            moved = moved + 1
                        end
                    end
                elseif force and value ~= "" then
                    tbl[key] = ""
                    moved = moved + 1
                end

            elseif type(value) == "table" then
                Walk(value, depth + 1, guarded or NOT_A_SURFACE[key] or false)
            end
        end
    end

    Walk(profile, 0, false)
    return moved
end

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
    borderColor   = ns.SurfaceColor(),
    barColor      = { 1.00, 0.44, 0.16 },
    -- OPAQUE. `trackAlpha` below is the bar's OWN colour showing through where
    -- it is not filled, which is a different question and keeps its own
    -- number - the surface behind everything is what "100%" was about.
    backdropAlpha = 1.00,
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
    -- 8: the house look. One surface colour (#1a1a1a, opaque) behind and
    --    around everything, one screen face (Expressway, outlined), one
    --    floor under every worked-out size. See ns.ApplyHouseLook - the
    --    version step moves only what still carries an older DEFAULT, and
    --    the "Standard look" button in Settings is the same rule with force.
    -- See Bars:Migrate and Profiles.Migrate.
    dbVersion  = 8,

    -- WHICH FEATURES ARE RUNNING. See Core/Modules.lua for what counts as one
    -- and what does not.
    --
    -- All four on, and that default is load-bearing rather than tidy: an
    -- existing profile gets these keys filled in by ApplyDefaults on the first
    -- login after the update, and any other value would mean an update
    -- silently switched somebody's bars off.
    --
    -- THE TWO FALSE ONES ARE NOT AN OVERSIGHT. The argument above is about
    -- features somebody is ALREADY using; a module nobody has ever had cannot
    -- be switched off by defaulting it off. And these two do something the
    -- other six do not - one puts a row of buttons on the screen, the other
    -- acts in your name at people who are not in the room - so they arrive
    -- switched off and the welcome window offers them, which is what the
    -- generation counter above exists for.
    -- COOLDOWNS IS THE THIRD FALSE ONE, and it has the strongest case of the
    -- three. The other two put something of ours on the screen; this one
    -- reaches for frames that belong to BLIZZARD and that another addon may
    -- already be holding. Two addons claiming those frames produce a broken
    -- screen neither of them can diagnose - see Cooldowns/Rivals.lua, which
    -- says who else is doing it, and the strip on the welcome window that
    -- reports it.
    --
    -- Defaulting it off means the answer is always one somebody GAVE. There
    -- is no clever version of this: a default that switches itself on when
    -- the addon list looks quiet is a setting that changes behind the user
    -- when they install something else.
    modules    = {
        cotanks   = true,
        reminders = true,
        externals = true,
        answers   = true,
        deaths    = true,
        raidbar   = false,
        invites   = false,
        cooldowns = false,
    },

    -- WHICH LANGUAGE. "auto" is the client's own, which is what nearly
    -- everybody wants and what a fresh profile gets; a code here is somebody
    -- who wants a different one, and that choice outranks the client. See
    -- Core/Locale.lua - it is a setting on the Settings page and never a
    -- module.
    language   = "auto",

    -- THE RAID BAR. Its cells are NOT listed here, for the same reason the
    -- externals ones are not: RaidBar.Config seeds them once under its own
    -- flag, and a default table would be poured back in at every login over
    -- a bar somebody has emptied on purpose.
    raidBar    = {
        onlyInGroup = true,
        size        = 26,
        gap         = 2,
    },

    -- THE INVITE TOOL, and every switch in it is missing on purpose. Each one
    -- makes something happen without you, so the code reads `cfg.onWhisper
    -- and true` - absent is off, and there is no default that could turn one
    -- of them on for somebody who has never opened the page.
    invites    = {},

    -- EXTERNAL COOLDOWNS: the ones somebody else presses on you. Empty, and
    -- never seeded - the panel draws nothing until you have picked something,
    -- which is the right silence for a feature that puts icons on the screen.
    externals  = {
        cells    = {},
        assigned = {},

        -- CHANNELS, ROWS AND COLUMNS ARE DELIBERATELY NOT LISTED HERE.
        -- Externals.Config owns all three, and putting them in the defaults
        -- would break each one in its own way:
        --
        --   channels        a channel you switched OFF is stored by being
        --                   MISSING, and ApplyDefaults fills in what is
        --                   missing - so the whisper would come back at every
        --                   login and no amount of clicking would keep it off.
        --                   The same rule welcomeSeen follows below.
        --   rows, columns   ApplyDefaults runs BEFORE the first Config call,
        --                   so a default would already be sitting in the two
        --                   keys the count/perLine migration is about to read
        --                   as "nothing here yet" - and a panel of twelve in
        --                   lines of four would come back as one line of six.
        size     = 40,
        gap      = 4,
        growth   = "right",
        onlyInGroup = true,

        -- THE LOOK, UNDER THE SAME KEY NAMES A BAR USES. Owner asked for
        -- "genau wie die anderen optionen beim cdm", and the cheapest way to
        -- mean it is literally: ns.PaintSurface and ns.PaintBorder read these
        -- names, so the panel is painted by the SAME code as a cooldown cell
        -- rather than by a second renderer that would drift from it.
        --
        -- The values are the bar defaults, so a panel and a bar look like
        -- they belong to one addon before anybody has touched either.
        --
        -- EXCEPT THE BORDER, which is 0 here on purpose. Owner, 2026-08-13:
        -- "cd request border bitte auf 0 dicke per default stellen." A bar
        -- is a row of cells that need telling apart; this panel is a list of
        -- names, and a line around each row only boxes in what the spacing
        -- already separates. The setting is untouched - anybody who wants
        -- the line back sets it under the panel's own Appearance.
        scale            = 1.0,
        alpha            = 1.0,
        borderSize       = 0,
        borderColor      = ns.SurfaceColor(),
        borderTexture    = "None",
        backdrop         = true,
        backdropColor    = ns.SurfaceColor(),
        backdropAlpha    = 1.00,
        backdropTexture  = "Blizzard",
        iconZoom         = 0.08,
    },

    -- Which round of modules this character has already been shown. Absent
    -- means never asked, which is why it is not listed with a value here -
    -- ApplyDefaults would then write the answer before the question.
    -- Read through ns.Modules.WelcomeDue.

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


    -- Saved bars, by name: { style = ..., content = ... }. The style is
    -- ns.BAR_STYLE_KEYS, the content is the grid shape, the per-cell overrides
    -- and the spells of the spec it was saved on. Presets written before
    -- 4.81.0 are a bare style table and stay readable as one - see
    -- Bars:SavePreset.
    barPresets = {},

    -- Whether applying one of the above - or copying one bar onto another -
    -- brings the spells and the grid shape with it, or only the styling.
    --
    -- ON, because it is the reason the owner asked for saved bars at all:
    -- "Alles, auch die Spells." Off is the behaviour every version before
    -- 4.81.0 had, and it is one switch away for anybody who wants a look
    -- without the work that went into the bar underneath it.
    presetSpells = true,

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
    --
    -- EXPRESSWAY rather than Arial Narrow, and that is the owner's own split:
    -- "standard Fonts ausserhalb von der addon font ist expressway". Both are
    -- narrow grotesks - bar text is read at a glance over a moving scene, and
    -- a narrow face fits more name into the same bar without dropping in size
    -- - but the WINDOW and the SCREEN are two jobs and now say so.
    --
    -- Read through ns.ScreenFontName, which is the only thing that resolves
    -- this key. It is a real setting rather than a constant: one place to
    -- change the typeface on every bar, without visiting three sections on
    -- four bars.
    --
    -- ONLY REACHES A NEW PROFILE. Anyone who already has one keeps the face
    -- stored in it, deliberate or not; a default is not licence to reach into
    -- a saved setting - which is what the version 8 step in Profiles.Migrate
    -- and the "Standard look" button in Settings are for.
    font       = ns.SCREEN_FONT,

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

        -- The plate behind the bar, and the empty part of the bar itself.
        --
        -- This one was NOT black - it was 0.05,0.05,0.06, a near-black with a
        -- blue cast that nothing else in the addon shared. That is exactly
        -- what one named surface is for: the co-tank panel had drifted a
        -- shade off every other plate and no one setting was wrong.
        bgColor       = ns.SurfaceColor(),
        bgAlpha       = 1.00,
        bgGradient    = { on = false, color = { 0.10, 0.10, 0.12 }, direction = "down" },
        trackAlpha    = 0.12,     -- the unfilled part, in the bar's own colour

        borderSize    = 1,
        borderColor   = ns.SurfaceColor(),
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
        --
        -- `font` NAMES A FACE rather than standing empty. An empty string
        -- meant "whatever Settings says", and Settings said "whatever font
        -- one of your other addons happened to register" - which is the
        -- automatic the owner asked to have taken out. `size = 0` is a
        -- different thing and stays: it means "work it out from the row
        -- height", which is what keeps one panel looking like one design at
        -- any size, and its floor is ns.FONT_FLOOR.
        name = {
            show = true, font = ns.SCREEN_FONT, size = 0, color = { 1, 1, 1 },
            outline = ns.SCREEN_OUTLINE, anchor = "LEFT", x = 0, y = 0,
            classColor = true,
            maxLength = 0,       -- 0 keeps the whole name
        },
        health = {
            show = true, font = ns.SCREEN_FONT, size = 0, color = { 1, 1, 1 },
            outline = ns.SCREEN_OUTLINE, anchor = "RIGHT", x = 0, y = 0,
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

        -- Aura strips. One per polarity, ONE ABOVE THE OTHER and both
        -- growing to the right.
        --
        -- They used to sit at opposite ends of the same edge - debuffs from
        -- the bottom left, buffs from the bottom right - on the reasoning
        -- that growing away from each other kept them apart. It does not, and
        -- the arithmetic was there to be done all along: eight icons at 22
        -- with a point between them is 183 wide, and the row is 240. From the
        -- fifth icon on, the two strips are drawing in the same place. On a
        -- real pull, when both are full, they were simply on top of one
        -- another.
        --
        -- Separating them by EDGE instead of by direction cannot collide at
        -- any count, at any icon size, on any row width. Both read left to
        -- right, which is also the direction everything else on the row does.
        --
        -- LIVE DATA NEEDS PATCH 12.1. Auras on another player are secret on
        -- this client and no addon may read them at all; the sanctioned route
        -- is Blizzard's AuraContainer, which arrives with 12.1. Until then the
        -- strips draw in TEST MODE only - so every setting here is adjustable
        -- today and correct the moment the patch lands. The panel says this in
        -- as many words rather than showing an empty strip.
        -- The font is the SHARED screen face, the same default the name and
        -- the health text carry. The two numbers on an aura icon are read over
        -- a moving scene like everything else on this panel, so they belong to
        -- that family and not to the window's.
        --
        -- THE TWO BORDER COLOURS HERE ARE THE ONE PAIR THAT DID NOT GO GREY.
        -- Red and green are not decoration on these two strips, they are the
        -- only thing that says which strip you are looking at - a debuff and a
        -- buff at the same size in the same corner, both in #1a1a1a, is one
        -- setting saying nothing twice.
        debuffs = {
            show = true, max = 8, size = 22, spacing = 1, perRow = 8,
            anchor = "TOPLEFT", growth = "right",
            x = 0, y = 0,
            borderSize = 1, borderColor = { 0.75, 0.15, 0.15 },
            font = ns.SCREEN_FONT, outline = ns.SCREEN_OUTLINE,
            countdown = true, countdownSize = 0,
            stacks = true, stacksSize = 0,
            swipe = true,
        },
        buffs = {
            show = true, max = 8, size = 22, spacing = 1, perRow = 8,
            anchor = "BOTTOMLEFT", growth = "right",
            x = 0, y = 0,
            borderSize = 1, borderColor = { 0.25, 0.55, 0.30 },
            font = ns.SCREEN_FONT, outline = ns.SCREEN_OUTLINE,
            countdown = true, countdownSize = 0,
            stacks = true, stacksSize = 0,
            -- THE SWEEP ON THE ICON, engine-driven. On by default, and that
            -- is a free choice rather than a change: these strips have never
            -- drawn live for anybody - they were test mode only until 12.1 -
            -- so this default IS the first impression, not a disturbance of
            -- a settled one. The engine reads the aura's own duration OBJECT,
            -- so an aura that gets extended sweeps to the new end instead of
            -- finishing early and lying about it.
            swipe = true,
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

-- A YES OR NO THAT CANNOT THROW.
--
-- On 12.0 some unit queries answer a SECRET boolean, and a secret cannot be
-- TESTED: `UnitInRange(unit) and true or false` raises "attempt to perform
-- boolean test on a secret boolean value" and takes everything above it with
-- it. That is how the co-tank panel took Edit Mode down on somebody else's
-- machine while working perfectly on ours - WHICH values are withheld depends
-- on where you are standing and who is beside you, which is why this belongs
-- in one place rather than at each call.
--
-- The fallback is the NEUTRAL answer, never a guess: unknown range is IN
-- range, because greying somebody out on a value the client refused to give
-- is the display lying with confidence.
function ns.Truth(value, fallback)
    if not ns.CanCompute(value) then return fallback end
    if value then return true end
    return false
end

function ns.Print(...)
    print("|cff7ec6d4Zwoelf|r|cffff7a3dStuff|r:", ...)
end

---------------------------------------------------------------------------
-- A LATTICE: rows, columns, and which square the nth thing sits in.
--
-- Written inside the externals panel, and here because the raid bar is the
-- SECOND panel built out of squares somebody arranges. Two copies of this
-- would be two chances to disagree about which way a lattice fills - and the
-- disagreement would be silent, because both look plausible until you count.
--
-- ns.Externals.Cell and .Extent still exist and still answer: a hundred lines
-- of self test call them by those names, and a rename that gains nothing is
-- churn. They delegate here now, so there is one rule and two doors.
--
-- `down` is the growth setting: fill a column before wrapping, rather than a
-- row. Zero-based column and row out, because that is what a SetPoint offset
-- multiplies.
---------------------------------------------------------------------------
function ns.LatticeCell(index, rows, columns, down)
    local slot = index - 1
    if down then
        return math.floor(slot / rows), slot % rows
    end
    return slot % columns, math.floor(slot / columns)
end

-- How big the DRAWN thing is, in columns and rows. A bar showing three of its
-- twelve places is three wide and one tall, not twelve by one: what is not
-- drawn takes up no room.
function ns.LatticeExtent(shown, rows, columns, down)
    if shown <= 0 then return 0, 0 end
    if down then
        return math.ceil(shown / rows), math.min(shown, rows)
    end
    return math.min(shown, columns), math.ceil(shown / columns)
end

---------------------------------------------------------------------------
-- WHO IS IN THE GROUP
--
-- Written for the externals panel - "who here can cast Ironbark" - and here
-- because the taunt announce asks the same list a different question: "who
-- is the other tank". Two walks over one party would be two chances to
-- disagree about who is in it.
--
-- One scratch table, refilled. This is called on a click and on a roster
-- change, never in a render pass, but the entries are small tables and
-- handing out fresh ones per call would be garbage for nothing.
---------------------------------------------------------------------------
local function GroupUnits(out)
    wipe(out)
    if IsInRaid() then
        for index = 1, GetNumGroupMembers() do out[#out + 1] = "raid" .. index end
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

local unitScratch, rosterScratch = {}, {}

function ns.Roster()
    wipe(rosterScratch)
    for _, unit in ipairs(GroupUnits(unitScratch)) do
        if UnitExists(unit) then
            local name = UnitName(unit)
            local _, class = UnitClass(unit)
            -- Readable on this patch, both of them, and checked anyway: a
            -- name that came back secret must not become a table key.
            if ns.CanCompute(name) and ns.CanCompute(class)
                and type(name) == "string" and type(class) == "string" then
                -- NAME-REALM, not the short name, and this is what stopped a
                -- click from casting anything at all: the owner is on
                -- Destromath and the group-mate testing it was on Gilneas, so
                -- `/cast [@Akui]` addressed somebody who, as far as that macro
                -- is concerned, is not there.
                --
                -- GetUnitName(unit, true) is the pair everybody uses: it adds
                -- the realm ONLY when it is a different one, so a same-realm
                -- group keeps its plain names and nothing else has to change.
                local full = GetUnitName and GetUnitName(unit, true) or nil
                if not (ns.CanCompute(full) and type(full) == "string") then
                    full = name
                end

                -- THE SPEC IS ASKED FOR HERE AND ANSWERED LATER. Want puts
                -- anybody we have not read into the inspect queue, Of hands
                -- back what has already come in - so every walk over the
                -- group is also the thing that keeps the answers coming, and
                -- no caller has to know an inspect exists. nil means "not
                -- known yet"; see Core/Specs.lua for why that must never
                -- hide anything.
                local specs = ns.Specs
                if specs then specs.Want(unit) end

                rosterScratch[#rosterScratch + 1] = {
                    unit = unit,
                    name = name,
                    fullName = full,
                    class = class,
                    spec = specs and specs.Of(unit) or nil,
                    role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or nil,
                    isPlayer = ns.Truth(UnitIsUnit(unit, "player"), false),
                }
            end
        end
    end
    return rosterScratch
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

---------------------------------------------------------------------------
-- SETTINGS THAT BELONG TO THE SPECIALISATION
--
-- Owner: "nach specs settings sind wichtig in wow", and he is right about
-- which ones. A protection warrior and a fury warrior share a character and
-- share almost nothing else: not the defensives they watch, not the
-- cooldowns they ask other people for, not what they want reminding about.
-- One list for both means half of it is about somebody who is not playing.
--
-- WHAT IS *NOT* IN HERE, deliberately: where a panel sits, how big it is,
-- which channels it talks on. A window that jumps across the screen when you
-- change spec is a bug in everybody's book, and the shape of a thing is not
-- an opinion about the fight.
--
-- ONE IMPLEMENTATION, THREE CALLERS. This started as a private helper in the
-- death log and was pulled up here the moment the second feature wanted it:
-- three copies of "which table is mine" is three chances to get the
-- unanswered-spec case wrong, and that case is the one that loses data.
--
--   field   the per-spec table on the profile, e.g. "remindersBySpec"
--   legacy  what was there before, read ONCE to carry it into whichever spec
--           is being played, and then left exactly where it is so an older
--           version still finds it. A STRING names a key on the profile; a
--           TABLE is that table - the request panel keeps its slots inside
--           its own config, not at the top level.
--   owner   whose table it is, defaulting to the profile. A cooldown bar
--           keeps its own cellsBySpec INSIDE the bar - one bar's picks are
--           not the next bar's - so the store has to be able to sit
--           somewhere other than the top level.
--
--           This argument is the whole of what the rebuilt cooldown manager
--           needed from this function. It was worth a fourth caller and one
--           parameter rather than a second implementation: the case that
--           loses data is the unanswered spec below, and there is exactly
--           one place that gets it right.
--
-- Returns nil while the client has not said which spec this is. Writing
-- under "WARRIOR:0" files a pick in a bin nothing will ever read again;
-- callers hand back a throwaway table for that moment instead.
---------------------------------------------------------------------------
local function CarryOver(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, inner in pairs(value) do out[key] = CarryOver(inner) end
    return out
end

function ns.SpecStore(field, legacy, owner)
    owner = owner or ns.db
    if not owner then return nil end

    local key, known = ns.SpecKey()
    if not (key and known) then return nil end

    owner[field] = owner[field] or {}
    local store = owner[field]

    if store[key] == nil then
        local was = legacy
        if type(legacy) == "string" then was = ns.db[legacy] end

        -- COPIED, not pointed at. Sharing the table would mean editing this
        -- spec's list also edits what the old version reads back - and the
        -- whole promise of leaving the legacy key alone is that it still
        -- says what it said.
        store[key] = CarryOver(type(was) == "table" and was or {})
    end

    return store[key]
end

---------------------------------------------------------------------------
-- A KEY, SHORT ENOUGH FOR THE CORNER OF AN ICON
--
-- "SHIFT-CTRL-F1" in a forty-pixel square is a smear. Pure, and here rather
-- than in either panel because both of them draw one now - the externals
-- slots and the answer cells - and two shorteners would drift apart.
---------------------------------------------------------------------------
function ns.ShortKey(key)
    if type(key) ~= "string" or key == "" then return nil end
    local short = key:upper()
    short = short:gsub("SHIFT%-", "s"):gsub("CTRL%-", "c"):gsub("ALT%-", "a")
    short = short:gsub("BUTTON(%d+)", "M%1")
    short = short:gsub("MOUSEWHEELUP", "MwU"):gsub("MOUSEWHEELDOWN", "MwD")
    short = short:gsub("NUMPAD", "N")
    short = short:gsub("SPACE", "Sp")
    return short
end

function ns.SpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellID)
    end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    return info and info.name
end

---------------------------------------------------------------------------
-- DO YOU ACTUALLY HAVE IT
--
-- A class list is not a spellbook. Pain Suppression is on the priest list and
-- a holy priest cannot cast it; putting a cell for it on his answer bar is a
-- button that does nothing when pressed and gives no reason - which is the
-- worst thing a button can do and the thing this whole wave is about.
--
-- Two questions rather than one, because they disagree on talents: one asks
-- whether the spell is in your book, the other whether something you took
-- REPLACED it and the replacement is. Either yes is a yes.
--
-- NEITHER ANSWERING IS ALSO A YES - a login, a talent load, a spec swap, and
-- the book is briefly not there. The caller would rather draw one cell too
-- many than an empty bar; see Answers.Offers, which counts what this removes
-- and refuses to remove everything.
--
-- C_SpellBook only. The old global IsPlayerSpell still works and is marked
-- deprecated, which would put a warning in a build that has none.
---------------------------------------------------------------------------
function ns.KnowsSpell(spellID)
    if type(spellID) ~= "number" then return false end
    local book = C_SpellBook
    if not book then return true end

    local asked = false
    for _, name in ipairs({ "IsSpellKnownOrOverridesKnown", "IsSpellKnown" }) do
        local query = book[name]
        if query then
            asked = true
            local ok, known = pcall(query, spellID)
            if ok and ns.Truth(known, false) then return true end
        end
    end

    return not asked
end

---------------------------------------------------------------------------
-- HOW LONG A SPELL LASTS, off its own tooltip
--
-- The owner, looking at a replay where two defensives drew as marks: "viele
-- def cds haben FESTE zeiten, die auch so in den tooltips stehen". He is
-- right, and this is not the rule against guessing - it is the opposite of
-- it. The client writes the number in the description itself; reading it is
-- asking, exactly like asking for the name or the icon.
--
-- It is still the LAST source the replay tries. A window this addon watched
-- is what happened; a tooltip is what is supposed to happen, before
-- talents, before haste, before the hit that cut it short.
--
-- THE UNIT WORDS COME FROM THE CLIENT TOO. "sec" would work on one client
-- and nowhere else; the owner plays German. SECONDS_ABBR and D_SECONDS are
-- Blizzard's own formats in whatever language is installed - "%d
-- |4Sekunde:Sekunden;" - so both forms of the word are in there and neither
-- was typed here.
---------------------------------------------------------------------------

-- "%d |4Sekunde:Sekunden;" -> { "sekunde", "sekunden" }. Pure, exported for
-- the self test: a locale this addon has never seen must still be checkable.
function ns.DurationWords(templates)
    local seen, out = {}, {}
    local function Add(word)
        word = (word or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
        if word == "" or seen[word] then return end
        seen[word] = true
        out[#out + 1] = word
    end

    for _, template in ipairs(templates or {}) do
        if type(template) == "string" then
            -- Strip the format spec, in every shape a locale writes it:
            -- %d, %s, %1$d, %.1f.
            local body = template:gsub("%%[%d%$%.%-]*%a", "")
            local singular, plural = body:match("|4(.-):(.-);")
            if singular then
                Add(singular)
                Add(plural)
            else
                Add(body)
            end
        end
    end

    -- Longest first, so "sekunden" is tried before "sek" and a match cannot
    -- stop halfway through the word it is looking at.
    table.sort(out, function(a, b) return #a > #b end)
    return out
end

-- The first "N <word>" in a description, in seconds. nil when the text says
-- no such thing - which is an answer, not a failure.
function ns.DurationInText(text, words, factor)
    if type(text) ~= "string" then return nil end
    local hay = text:lower()
    for _, word in ipairs(words or {}) do
        -- The word is data, not a pattern: "sek." carries a dot, and an
        -- unescaped one matches any character at all.
        local escaped = word:gsub("(%W)", "%%%1")
        local found = hay:match("(%d+[%.,]?%d*)%s*" .. escaped)
        if found then
            local seconds = tonumber((found:gsub(",", ".")))
            if seconds and seconds > 0 then return seconds * (factor or 1) end
        end
    end
    return nil
end

local secondWords, minuteWords

function ns.ForgetDurationWords()
    secondWords, minuteWords = nil, nil
end

-- Seconds off the spell's own description, or nil. Capped: anything past
-- two minutes in a defensive's text is another sentence's number.
function ns.SpellDuration(spellID)
    if not (spellID and ns.CanCompute(spellID)) then return nil end
    local get = C_Spell and C_Spell.GetSpellDescription
    if not get then return nil end

    if not secondWords then
        secondWords = ns.DurationWords({ SECONDS_ABBR, D_SECONDS, "%d sec" })
        minuteWords = ns.DurationWords({ MINUTES_ABBR, D_MINUTES, "%d min" })
    end

    local ok, text = pcall(get, spellID)
    if not (ok and ns.CanCompute(text) and type(text) == "string") then
        return nil
    end

    local seconds = ns.DurationInText(text, secondWords)
        or ns.DurationInText(text, minuteWords, 60)
    if seconds and seconds >= 1 and seconds <= 120 then return seconds end
    return nil
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

-- 2314156 -> "2.31M". Damage numbers on this patch run to seven digits, and
-- seven digits in a row of text is a wall, not a number. Pure, tested.
-- Below a thousand the number is itself - "941" abbreviated is longer.
function ns.ShortNumber(value)
    if type(value) ~= "number" then return "0" end
    local sign = value < 0 and "-" or ""
    value = math.abs(value)
    if value >= 1e6 then
        return string.format("%s%.2fM", sign, value / 1e6)
    elseif value >= 1e3 then
        return string.format("%s%.1fk", sign, value / 1e3)
    end
    return sign .. string.format("%d", value)
end

-- THE FACE FOR EVERYTHING THIS ADDON DRAWS OUT ON THE SCREEN.
--
-- Two fonts, because they have different jobs. This one is for digits and
-- short words over a busy 3D scene - narrow, outlined, read at a glance. It
-- is the wrong choice for panel text, which reads cramped in it at every
-- size; that is ns.StyleUIFont below.
--
-- IT USED TO BE `NumberFontNormalLarge:GetFont()`, AND THAT WAS THE OTHER
-- HALF OF THE AUTOMATIC. Blizzard's number face is whatever the client makes
-- it - it changes with the locale, and it is a different design from
-- everything else this addon draws, because every OTHER string on screen goes
-- through Media.ApplyFont with a name out of the profile. So a tracking
-- group's timer and a cooldown bar's timer were set in two different faces
-- and no setting anywhere said so.
--
-- Owner: "nimm das automatisch bitte raus. wir muessen den usern direkt vom
-- start weg eine schoene ui anbieten."
--
-- BY NAME RATHER THAN BY PATH, and that is the opposite of what ns.PANEL_FONT
-- does one screen down - deliberately. The panel is pinned to a file the
-- client ships so no other addon can move it. Expressway is a file we do NOT
-- ship, so the only way to reach it at all is to ask the registry for the
-- name; Media.Font falls through the house chain when nobody has it.
--
-- The floor is applied HERE rather than at eleven call sites. Every one of
-- them worked its size out from a cell height, and the smallest of them asked
-- for eight - his "minimum 10 pixel" is a property of the face on screen, not
-- of each thing that happens to use it.
function ns.StyleFont(fontString, size, flags)
    size = math.max(ns.FONT_FLOOR, tonumber(size) or ns.FONT_FLOOR)
    flags = flags or ns.SCREEN_OUTLINE

    local path = ns.Media and ns.Media.Font
        and ns.Media.Font(ns.ScreenFontName()) or nil

    -- SetFont answers whether the file loaded, and a string that silently
    -- took no font draws NOTHING - which is how a missing face turns into
    -- "the stack count stopped working" rather than into "it looks wrong".
    if not (path and fontString:SetFont(path, size, flags)) then
        fontString:SetFont(NumberFontNormalLarge:GetFont(), size, flags)
    end
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

    -- WITH NO CHOICE MADE, ASK MEDIA RATHER THAN JUMPING TO THE FLOOR.
    --
    -- Media.PanelFont is what the settings page has been SHOWING as the
    -- default for as long as it has existed, and for most of that time it was
    -- not the font that got used: with nothing picked, this went straight past
    -- it to the fallback below. The picker named one face while the window was
    -- drawn in another, and nobody could have found that by reading either.
    --
    -- The two now agree, and they answer "Arial Narrow" - see PANEL_FONTS in
    -- Core/Media.lua for why nothing installed by another addon gets to be the
    -- default any more.
    if not path and ns.Media and ns.Media.PanelFont then
        path = ns.Media.Font(ns.Media.PanelFont())
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
    border:SetColor(ns.SurfaceRGB())
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
--
-- On the namespace rather than a local: Profiles.lua owns opening the store
-- now, and it needs this list to tell a measurement apart from a setting when
-- it migrates an old database.
ns.ACCOUNT_DEFAULTS = {
    procs       = {},
    auraLinks   = {},
    procsHidden = {},

    -- THE LAST TEN DEATHS, per character key. Not a setting and not really
    -- a measurement either - it is a record, kept here because a /reload
    -- used to take it and a reload happens after every settings change and
    -- every addon update. Written by Core/Death.lua, which copies each
    -- field by name rather than storing the live table: a secret value in
    -- a saved variable throws at logout, when nobody is watching.
    deaths      = {},

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

-- ns.OpenProfile used to live here. It is in Core/Profiles.lua now, together
-- with the migration that gives a profile a name of its own and lets a second
-- character point at it.

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

        -- THE MACHINERY, and it is not a module. Every feature below stands on
        -- the Cooldown Manager: the bars claim its icon frames, a reminder
        -- asks it whether a buff is up, the death log builds its defensives
        -- out of its catalogue. Switching the bars off must not take the
        -- catalogue with it, so this runs whatever the module switches say -
        -- and it runs FIRST, because the first render claims item frames and
        -- there is nothing to claim until the pools have been walked once.
        Boot("Cooldown Manager", function()
            ns.CDM:HookPools()
            -- The spell list is a live view of the Cooldown Manager, so a
            -- talent or spec change has to reach an open window.
            ns.CDM:OnChanged(function() ns.Options:OnCatalogChanged() end)
        end)

        -- WHERE YOU ARE AND WHO YOU ARE PLAYING, and it is machinery for the
        -- same reason the Cooldown Manager is: a reminder's "only in combat"
        -- reads this evaluator, not the bars'.
        --
        -- It used to be started inside Screen:Start, which was correct while
        -- the bars were the addon and became a hole the moment they became a
        -- module - Reminders without Cooldowns would have run on a state
        -- nobody had ever sampled. It survived only because
        -- PLAYER_ENTERING_WORLD samples it anyway, which is luck, not design.
        Boot("Visibility", function()
            ns.Visibility:Start()

            -- THE CACHED SPEC KEY, dropped when the spec changes. Worse than
            -- the above if it goes missing: that key is the name the measured
            -- cooldown lengths and the recorded procs are FILED under, and
            -- both belong to the account rather than to the bars. Left inside
            -- Screen:Start, switching the bars off would have had the death
            -- log reading Blood's measurements while you played Frost.
            ns.Visibility:OnChanged(function() ns.ForgetSpecKey() end)
        end)

        -- THE FEATURES, in the order Core/Modules.lua lists them, which is
        -- the order this used to be a straight line of calls in. A module
        -- that is switched off boots nothing at all - no frame, no event.
        ns.Modules:BootAll()

        -- The two ways in. Not modules: they are how you REACH the window,
        -- and a switch you can only find through a door you switched off is
        -- a switch nobody can find.
        Boot("Minimap button", function() ns.MinimapButton:Create() end)
        Boot("Game menu entry", function() ns.GameMenu:Create() end)

        -- Last, and only if this character has never been asked which modules
        -- it wants - or an update brought one it has not been offered.
        Boot("Welcome", function() ns.Welcome:ShowIfDue() end)
        -- AFTER the welcome, and News.Due is what keeps the two apart: a
        -- fresh install stamps the version and says nothing, so nobody ever
        -- gets both windows on one login.
        Boot("News", function() ns.News:ShowIfDue() end)
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
-- Only commands that exist. A usage list that offers a command the addon no
-- longer has is worse than no list: it sends people looking for a feature.
-- EVERY COMMAND, WRITTEN ONCE.
--
-- Chat prints this list and the About page draws it, so a command cannot be
-- in one of them and missing from the other - which is exactly what had
-- happened. The About page carried a SECOND list, typed by hand, that still
-- advertised `/zs text` and had never heard of `/zs build`, `/zs modules`,
-- `/zs report`, `/zs skin`, `/zs test`, `/zs taunt` or `/zs death`. Two lists
-- of the same thing is one list and one lie.
--
-- An entry with `group` opens a heading; an entry with `cmd` is a command
-- under whichever heading came last. Colour codes are allowed in `text`
-- because both readers are FontStrings and both render them.
--
-- /zs route is deliberately absent: Routes is parked, and it was listed here
-- with no handler behind it. A menu naming something that does nothing is
-- worse than a short menu.
ns.COMMANDS = {
    { group = "Getting around" },
    { cmd = "/zs", text = "open the window" },
    { cmd = "/zs unlock / lock",
      text = "move what this addon draws around the screen" },
    { cmd = "/zs modules", text = "which features are running "
        .. "(|cffffd100/zs modules <name>|r switches one)" },
    { cmd = "/zs welcome", text = "the window that asks which ones you want" },

    { group = "The Cooldown Manager" },
    { cmd = "/zs cdm",
      text = "what Blizzard's Cooldown Manager currently holds - the "
        .. "catalogue the death log and the reminders read" },

    { group = "Auras" },
    { cmd = "/zs auras",
      text = "the procs seen on this spec, and what drives them" },
    { cmd = "/zs report",
      text = "open the proc report in a box you can copy from" },
    { cmd = "/zs auras export", text = "the same thing, under its older name" },
    { cmd = "/zs auras icon <glowID> <spellID>",
      text = "which icon a proc shows" },
    { cmd = "/zs auras bind <glowID> <auraID>",
      text = "name the buff (12.1 route)" },
    { cmd = "/zs auras forget <glowID>",
      text = "drop one, shipped ones included" },
    { cmd = "/zs auras remember", text = "put every forgotten one back" },

    { group = "M+ and raid stuff" },
    { cmd = "/zs raidbar", text = "what is on the raid bar, and what each "
        .. "press would send" },
    { cmd = "/zs check", text = "the raid check window (|cffffd100ask|r "
        .. "asks the group without opening it)" },
    { cmd = "/zs invite", text = "what the invite tool is listening for "
        .. "(|cffffd100guild|r invites, |cffffd100back|r re-invites, "
        .. "|cffffd100disband|r empties the group)" },
    { cmd = "/zs tanks",
      text = "the co-tank panel (|cffffd100test|r fakes a raid)" },
    { cmd = "/zs reminders",
      text = "every reminder, and why each one is or is not up" },
    { cmd = "/zs externals", text = "who each external slot would whisper "
        .. "(|cffffd100test|r shows the panel)" },
    { cmd = "/zs specs", text = "what the game says each specialisation is, "
        .. "and which spec each slot is waiting for" },
    { cmd = "/zs chat", text = "why a request did not go out: which send the "
        .. "client allows, who it would address, and where it would land" },
    { cmd = "/zs news", text = "what changed in the last few versions, with a "
        .. "way straight to each thing" },
    { cmd = "/zs sounds", text = "every sound your addons have registered, "
        .. "and what each moment would play" },
    { cmd = "/zs taunt", text = "what your next taunt would say "
        .. "(|cffffd100ask|r tells the other tank to take it)" },
    { cmd = "/zs death", text = "the last death's analysis (|cffffd100share|r "
        .. "posts it, |cffffd100clear|r empties the list, |cffffd100cds|r says "
        .. "why a press has no bar)" },
    { cmd = "/zs death raid", text = "everybody who died this fight, in the "
        .. "order they fell, and what ended each one (|cffffd100chat|r prints "
        .. "it instead of opening the window)" },

    { group = "Housekeeping" },
    { cmd = "/zs test", text = "run the addon's own checks and report failures" },
    { cmd = "/zs minimap", text = "show or hide the minimap button" },
    { cmd = "/zs reset", text = "reset the profile you are using, keeping procs" },
}

-- The same list, laid out for a chat frame. Built rather than typed, for the
-- reason above it.
local function UsageLines()
    local lines = { "|cff7ec6d4Zwoelf|r|cffff7a3dStuff|r - commands:" }
    for _, entry in ipairs(ns.COMMANDS) do
        if entry.group then
            lines[#lines + 1] = ""
            lines[#lines + 1] = "  " .. entry.group
        else
            lines[#lines + 1] = string.format("  |cffffd100%s|r - %s",
                entry.cmd, entry.text)
        end
    end
    return lines
end

local usage = UsageLines()

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

    -- THREE DIAGNOSTICS THAT WERE WRITTEN AND COULD NOT BE RUN.
    --
    -- Text.Dump, Look.Dump and Effects.Dump were complete, commented and had
    -- no caller. Text.Dump answers, per placed cell and per element: what the
    -- setting asked for, where the widget's own first anchor actually is,
    -- whether we have styled it, whether Blizzard is showing it, and what it
    -- reads. That is precisely the question two rounds of "the number is not
    -- there" were spent on, and it could not be asked.
    --
    -- Its own header says why it exists: "Three separate fixes for 'the
    -- position does nothing' were made by reading the code and reasoning
    -- about it, and each came back reported still broken." A diagnostic with
    -- no way in is the same failure one level up.
    elseif cmd == "numbers" or cmd == "text" then
        local text = ns.Cooldowns and ns.Cooldowns.Text
        if text and text.Dump then text.Dump() else
            ns.Print("The cooldown text module is not loaded.")
        end

    elseif cmd == "look" then
        local look = ns.Cooldowns and ns.Cooldowns.Look
        if look and look.Dump then look.Dump() else
            ns.Print("The cooldown look module is not loaded.")
        end

    elseif cmd == "fx" or cmd == "effects" then
        local fx = ns.Cooldowns and ns.Cooldowns.Effects
        if fx and fx.Dump then fx.Dump() else
            ns.Print("The cooldown effects module is not loaded.")
        end


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
            ns.EditMode:SetUnlocked(true)
        elseif sub == "lock" then
            ns.EditMode:SetUnlocked(false)
        else
            db.coTanks.enabled = not db.coTanks.enabled
            ns.CoTanks:Refresh()
            ns.Print("Co-tanks",
                db.coTanks.enabled and "|cff40ff40on|r" or "|cff888888off|r")
        end

    -- Which features are running, and switching one without opening a window.
    -- The list prints first and the switch second, so "/zs modules" alone is
    -- a report and never an accident.
    elseif cmd == "modules" or cmd == "module" then
        local wanted = (rest or ""):match("^(%S*)"):lower()
        if wanted ~= "" then
            if ns.Modules:Get(wanted) then
                ns.Modules:Toggle(wanted)
                ns.Options:Refresh()
            else
                ns.Print("|cffff4040No module called|r " .. wanted .. ".")
            end
        end
        local on, total = ns.Modules:CountOn()
        ns.Print(string.format("Modules - %d of %d running:", on, total))
        for _, entry in ipairs(ns.Modules:All()) do
            ns.Print(string.format("  |cffffd100%s|r  %s  %s",
                entry.key, entry.title,
                ns.Modules:IsOn(entry.key) and "|cff40ff40on|r" or "|cff888888off|r"))
        end

    elseif cmd == "welcome" then
        ns.Welcome:Show()

    -- External cooldowns. The diagnostic rather than a toggle, for the same
    -- reason the reminders one is: "who would this button whisper" is the
    -- only question anybody has about it, and it has a printable answer.
    elseif cmd == "externals" or cmd == "external" then
        local sub = (rest or ""):match("^(%S*)"):lower()
        if sub == "test" then
            ns.Externals:SetTestMode(not ns.Externals.testing)
            ns.Print("External CD request test mode",
                ns.Externals.testing and "|cff40ff40on|r" or "|cff888888off|r")
        else
            ns.Externals:Dump()
        end

    -- The raid bar, the window one of its buttons opens, and the invite tool.
    -- All three answer with what they WOULD do rather than doing it, because
    -- that is the question anybody types a slash command to find out.
    elseif cmd == "raidbar" or cmd == "raid" then
        ns.RaidBar:Dump()

    -- WHAT THE GAME SAYS EACH SPEC IS, next to what the catalogue assumed.
    -- The one check that cannot be run from a desk: an index that points at
    -- the wrong spec of the right role hides the right healer and looks like
    -- a panel that is working.
    elseif cmd == "specs" or cmd == "spec" then
        ns.Specs:Dump()

    -- WHICH SOUNDS EXIST AT ALL. Not knowable from here: the registry is
    -- filled by whatever OTHER addons are installed, and a picker showing
    -- one entry is a correct picker on a bare machine. See Sounds:Dump.
    elseif cmd == "sounds" or cmd == "sound" then
        ns.Sounds:Dump()

    elseif cmd == "check" then
        local sub = (rest or ""):match("^(%S*)"):lower()
        if sub == "ask" then
            -- Asks without opening anything. For a macro key: the answers are
            -- worth collecting before you open the window, not after.
            ns.RaidCheck:Ask()
        elseif sub == "dump" then
            ns.RaidCheck:Dump()
        else
            ns.RaidCheck:Toggle()
        end

    elseif cmd == "invite" or cmd == "invites" then
        local sub = (rest or ""):match("^(%S*)"):lower()
        if sub == "guild" then
            ns.Invites.InviteGuild()
        elseif sub == "back" then
            ns.Invites.InviteBack()
        elseif sub == "disband" then
            ns.Invites.Disband()
        else
            ns.Invites:Dump()
        end

    -- Which language, how finished each one is, and what is left in it.
    elseif cmd == "loca" or cmd == "language" then
        local sub = (rest or ""):match("^(%S*)")
        ns.Locale:Dump(sub ~= "" and sub or nil)

    -- The taunt announce. `ask` is the one meant for a macro key - it is the
    -- half of a tank swap an addon can actually do something about.
    elseif cmd == "taunt" or cmd == "taunts" then
        local sub = (rest or ""):match("^(%S*)"):lower()
        if sub == "ask" then
            local sent, why = ns.Taunts.Ask()
            if not sent then
                ns.Print("|cffff8040Nothing sent.|r " .. tostring(why))
            end
        else
            ns.Taunts:Dump()
        end

    -- Reminders. One command, and it is the diagnostic rather than a toggle:
    -- "why is my reminder not showing" is the only question anybody has about
    -- this feature, and it has a printable answer.
    elseif cmd == "reminders" or cmd == "reminder" then
        ns.Reminders:Dump()

    elseif cmd == "death" then
        local sub = rest:lower()
        if sub == "share" then
            ns.Death:Share()
        elseif sub == "probe" then
            ns.Death:Probe()
        -- Everybody else's, which is a different question from "what killed
        -- me" and reads a different half of the same list. The window is the
        -- answer; the chat version stays because a paste is how a number gets
        -- checked, and a screenshot of a window is not.
        elseif sub == "raid" or sub == "group" then
            ns.RaidDeaths:Toggle()
        elseif sub == "raid chat" or sub == "raid text" then
            ns.RaidDeaths:Dump()
        -- Why a press has no bar under it. Four different causes wear the
        -- same symptom, and only the client can say which one it is.
        elseif sub == "cds" or sub == "cd" then
            ns.History:Dump()
        elseif sub == "clear" then
            ns.Death:Clear()
        else
            ns.Death:Show()
        end

    -- WHY A MESSAGE DID NOT GO OUT. The client is the only one who can say
    -- which door it keeps shut, so it is asked rather than reasoned about.
    elseif cmd == "chat" then
        ns.Chat.Probe()

    -- The update window, on purpose rather than on a login. It opens by
    -- itself once per version; this is for looking at it again afterwards,
    -- and it does NOT re-stamp anything you had not read.
    elseif cmd == "news" or cmd == "whatsnew" then
        ns.News:Toggle()

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

    elseif cmd == "reset" then
        -- Recorded procs survive. They are measurements that took hours of
        -- playing to collect and cannot be typed back in, so they are not
        -- "settings" - /zs auras forget is how those go away.
        -- THIS PROFILE, and nothing else in the file.
        --
        -- It used to be ZwoelfStuffDB = {}, which threw away every other
        -- character's settings as well - and worse, it DETACHED the account
        -- table, so ns.account pointed at a table no longer in the saved
        -- variable. The very next line wrote the rescued procs into that
        -- orphan, and they were gone on the next login. The promise in the
        -- message above lived in the comment and never in the code.
        local store = ZwoelfStuffDB
        store.profiles[ns.profileName] = {}
        ns.db = ns.ApplyDefaults(store.profiles[ns.profileName], ns.DEFAULTS)

        ns.Profiles:Reload()
        ns.Print(string.format("|cffffd100%s|r reset to defaults. Recorded "
            .. "procs kept, and no other profile was touched.", ns.profileName))

    else
        for _, line in ipairs(usage) do print(line) end
    end
end

function ZwoelfStuff_OnAddonCompartmentClick()
    ns.Options:Toggle()
end
