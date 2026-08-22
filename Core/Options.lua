---------------------------------------------------------------------------
-- Options - the app window.
--
-- Three columns, fixed:
--
--   left    the functions. Cooldowns, Edit mode, settings, and the three
--           read-only pages. It does NOT list your bars - that was the
--           mistake in the last shape, because it made you pick a bar before
--           you could see any of them.
--   middle  what you are working on. For Cooldowns that is every bar you own,
--           under each other, scrollable, with "Add new bar" at the bottom of
--           the stack where the next one appears.
--   right   the spells, in full, all the time. It becomes the settings for
--           one bar while you have its Options open, and goes back after.
--
-- The secondary pages take the middle AND the right, because they have no
-- spell list to show and a narrow column of text next to an empty panel is
-- the wasted space this rebuild set out to remove.
---------------------------------------------------------------------------
local _, ns = ...

local Options = {}
ns.Options = Options

local UI = ns.UI
local C = UI.C

-- The left column holds six words and a button; it does not need to be as
-- wide as the thing you are working on. The right one holds a settings label
-- AND its control on the same line, and it was clipping labels to "T..." to
-- fit. So: take the width from the one that has nothing to say and give it to
-- the one that ran out.
-- TAKEN FROM THE DESIGN SYSTEM, NOT TYPED AGAIN.
--
-- These were four literals here and four more in Widgets, for the same four
-- measurements - and the inspector reads its own copy in order to decide what
-- fits on a row. Two numbers for one distance is a number that will disagree
-- with itself, and it did the moment the rail was widened.
--
-- The rail carries a state light per feature now, so it needed the room for
-- one; the window grew by the same amount rather than taking it out of the
-- work area, which is the column that was short in the first place.
local WINDOW_W, WINDOW_H = UI.WINDOW_W, UI.WINDOW_H
local SIDEBAR_W = UI.RAIL_W
local SIDE_W    = UI.INSPECTOR_W
local PAD       = 20

-- Shared with Widgets, so the rule under the brand, the rule under the page
-- title and the rule under the right column's heading are the same line.
local HEADER_H  = UI.HEADER_H

-- The strip at the bottom of the rail that carries the version and the client
-- build. Named because the sum that decides whether the list of entries fits
-- has to subtract it, and a number typed in two places is a number that
-- drifts - which is exactly how an entry ends up behind it.
local RAIL_FOOT_H = 38

-- The block of outward links between the nav and that foot: one row per store
-- plus Discord. SHORTER THAN A NAV ROW, and the number is measured, not
-- preferred - see where they are built. It is also the right look: these are
-- references, not pages, and a reference as tall as a destination claims to be
-- one.
local RAIL_LINK_H = 22

-- What that block costs the nav, published so the check and the layout read
-- ONE number. They were two for a version - the check still subtracted a
-- single row while three were being drawn - which is a check quietly agreeing
-- with a window that had already changed.
function Options.RailTail()
    return #ns.LINKS * RAIL_LINK_H + 12
end

-- THE CLOSE CROSS, AND WHY ITS SIZE IS A SHARED NUMBER.
--
-- The cross sits in the window's top-right corner. The page's header actions
-- sit at the right edge of the MIDDLE column. On a page with a third column
-- those are 400 pixels apart and nothing touches; on a page without one they
-- are the same corner, and the cross was drawn straight through the last
-- button's label. Owner, with a picture of the answer page: "das X oben
-- rechts fixen".
--
-- So the actions have to know how much room to leave, which means the cross's
-- width cannot be typed at the one place that draws it.
local CLOSE_W = 24
local CLOSE_ROOM = CLOSE_W + 10

---------------------------------------------------------------------------
-- Diagnostics
---------------------------------------------------------------------------
-- THE FOUR READINGS AT THE TOP OF DIAGNOSTICS.
--
-- Every one of them is measured on this machine. Nothing here is a number
-- somebody typed in once, and nothing that has no live source is drawn: the
-- design sketch also showed a "secret values" count and a timing chart, and
-- neither exists to be read - the secret-value figure in About is a
-- measurement taken by hand, not a counter, and there is no timing series at
-- all. A dashboard that invents its own numbers is worse than one with four.
-- MEMORY IS A READING LIKE THE OTHERS, and it is here because the owner had
-- to ask: "warum ist unser addon im spiel 13 mb gross". Nothing in the window
-- could answer him, so the answer took a desktop measurement. It is one call
-- and it belongs on the page whose whole job is what this addon is doing to
-- your client.
--
-- No good/warn colour on it. A threshold would be invented - what is "too
-- much" depends on what you have open - and a tile that turns orange at a
-- number somebody guessed teaches people to distrust the other four.
local DIAG_STATS = { "Cooldowns tracked", "Pixels per unit", "Memory" }

-- HOW MUCH OF THE CLIENT'S LUA HEAP IS OURS, in a form a tile can show.
--
-- Two facts, both checked against addons installed on this machine rather
-- than assumed:
--
--   * The memory pair is still GLOBAL - only the addon INFO calls moved into
--     C_AddOns - and GetAddOnMemoryUsage takes a NAME as well as an index.
--   * UpdateAddOnMemoryUsage walks every loaded addon and is a spike you can
--     see. EllesmereUI, which puts the same number on a data bar, rescans
--     once every thirty seconds and says why in its own comment.
--
-- This page repaints on every keystroke in a settings box, so the reading is
-- taken at most once every five seconds and the tile shows the last one in
-- between. A number five seconds old is the truth about an addon's memory;
-- a scan per keystroke is a stutter while you type.
local MEM_EVERY = 5
local memTaken, memText = 0, "-"

-- The client counts in KB. Pure, and exported, so the one thing here that can
-- be wrong without anybody noticing - a tile reading "13312 KB" - has a test.
function Options.MemoryText(kb)
    kb = tonumber(kb) or 0
    if kb >= 1024 then return string.format("%.1f MB", kb / 1024) end
    return string.format("%d KB", kb)
end

local function MemoryReading()
    if not (UpdateAddOnMemoryUsage and GetAddOnMemoryUsage) then return "-" end

    local now = GetTime and GetTime() or 0
    if memText ~= "-" and now - memTaken < MEM_EVERY then return memText end
    memTaken = now

    UpdateAddOnMemoryUsage()
    memText = Options.MemoryText(GetAddOnMemoryUsage("ZwoelfStuff"))
    return memText
end

local function BuildDiagnosticsPage(page, width)
    local grid = UI.Page(page, width)

    ---------------------------------------------------------------------
    -- The readings
    ---------------------------------------------------------------------
    local statHost = CreateFrame("Frame", nil, grid.content)
    statHost:SetHeight(UI.STAT_H)

    local STAT_GAP = 10
    local tileWidth = math.floor(
        (grid.width - STAT_GAP * (#DIAG_STATS - 1)) / #DIAG_STATS)

    local stats = {}
    for index, caption in ipairs(DIAG_STATS) do
        local stat = UI.Stat(statHost, caption)
        stat:SetTileWidth(tileWidth)
        stat:SetPoint("TOPLEFT", statHost, "TOPLEFT",
            (index - 1) * (tileWidth + STAT_GAP), 0)
        stats[index] = stat
    end
    grid:Wide(statHost, UI.STAT_H, 0, 12)

    grid:Section("Cooldown Manager")
    grid:Note("Everything on your bars comes from Blizzard's Cooldown Manager - it "
        .. "already knows the spells, binds the auras and has the timing, none of "
        .. "which an addon can do for itself on this patch.")

    grid:Buttons({
        { text = "What it holds", onClick = function()
            ns.CDM:Dump()
        end },
    })

    grid:Section("Auras")
    grid:Note("Procs are recorded while you play, per class and spec, and their "
        .. "duration is measured rather than assumed. Output goes to your chat frame.")

    grid:Buttons({
        { text = "What was seen", onClick = function()
            ns.Auras:Dump()
        end },
        { text = "Export this spec", onClick = function()
            ns.Auras:Export()
        end },
    })


    grid:Section("This client")

    -- HOW SHARP THE MARKS IN THIS WINDOW ARE, and it is a measurement rather
    -- than an opinion. Every icon here was soft for months because the rule
    -- that picks a file guessed at this number instead of reading it, and
    -- "sieht matschig aus" is not something a screenshot can settle. Now it
    -- says which file it loaded and why.
    -- The caveat belongs ON the row: a cut is chosen when a mark is BUILT, so
    -- this line can be right while the window in front of you was drawn under
    -- the old setting.
    local sharpRow = grid:FullRow("Icon sharpness", { controlWidth = 300,
        sublabel = "Chosen when the window is built - a UI scale change needs a /reload" })
    local sharpState = UI.Label(sharpRow.slot, "", 12, C.text)
    sharpState:SetPoint("RIGHT", sharpRow.slot, "RIGHT", 0, 0)
    sharpState:SetJustifyH("RIGHT")

    local engineRow = grid:FullRow("Aura engine (12.1)", { controlWidth = 260 })
    local engineState = UI.Label(engineRow.slot, "", 12, C.text)
    engineState:SetPoint("RIGHT", engineRow.slot, "RIGHT", 0, 0)
    engineState:SetJustifyH("RIGHT")

    grid:Note("Procs are recognised by their spell overlay, and their length "
        .. "is measured while you play.")

    grid:Layout()

    page.Refresh = function()
        local perUnit = UI.PixelsPerUnit()

        ---------------------------------------------------------------
        -- The four readings
        ---------------------------------------------------------------
        -- COUNTED, not asked for: there is no items-held call on CDM, and
        -- walking what it hands out is the only honest answer. Guarded,
        -- because on a client where the Cooldown Manager is not up
        -- ForEachItemEverywhere walks nothing and the answer is nought
        -- rather than an error.
        local held = 0
        if ns.CDM:IsAvailable() then
            ns.CDM:ForEachItemEverywhere(function() held = held + 1 end)
        end
        -- What the Cooldown Manager is holding. Nothing of ours displays
        -- it any more; the catalogue behind the death log's defensives and
        -- the reminders is built out of exactly these items, so nought here
        -- is why those two come up empty.
        stats[1]:Set(tostring(held), held > 0 and "good" or "warn")
        stats[2]:Set(string.format("%.2f", perUnit))
        stats[3]:Set(MemoryReading())

        sharpState:SetText(string.format(
            "%.2f px per unit - %dpx and %dpx files",
            perUnit, UI.IconCutFor(16, perUnit), UI.IconCutFor(32, perUnit)))

        -- THIS COMMENT SAID "Engine.lua is parked on a 12.0 client, so
        -- ns.Engine is nil here" AND IT HAD BEEN FALSE FOR FIVE DAYS. It was
        -- written 2026-08-06, when the file really was out of the TOC; the
        -- co-tank wave put Core\Engine.lua back in on 2026-08-08 and this line
        -- was never revisited. ns.Engine has existed on every client since -
        -- the file assigns it at file scope - and the only thing 12.1 changed
        -- is that Engine:IsAvailable() now answers true.
        --
        -- The guard stays, because a file CAN be parked again and reading
        -- through a nil is a crash rather than a missing feature. What went is
        -- the sentence that promised a patch which has since arrived.
        if not ns.Engine then
            engineState:SetText("|cff888888not loaded on this client|r")
        elseif ns.Engine:IsAvailable() then
            engineState:SetText("|cff40ff40available|r")
        else
            engineState:SetText("|cffff4040"
                .. (ns.Engine:UnavailableReason() or "unavailable") .. "|r")
        end

        grid:Refresh()
    end
end

---------------------------------------------------------------------------
-- About
---------------------------------------------------------------------------
-- THE BLOCK AT THE TOP OF ABOUT: the mark, the name, why it exists, and the
-- three facts anybody is asked for the moment something goes wrong.
--
-- Its own function because it is the one piece of this page that is a LAYOUT
-- rather than a paragraph, and the page below it is built by the grid.
local ABOUT_LOGO = 56
local ABOUT_META = { "Author", "Version", "Client" }

local function BuildAboutHead(parent, width, intro)
    local head = CreateFrame("Frame", nil, parent)

    local logo = head:CreateTexture(nil, "ARTWORK")
    logo:SetSize(ABOUT_LOGO, ABOUT_LOGO)
    logo:SetPoint("TOPLEFT", head, "TOPLEFT", 0, 0)
    logo:SetTexture(ns.ICON_TEXTURE)

    local column = ABOUT_LOGO + 18

    local name = UI.Label(head, "ZwoelfStuff", UI.FS.title, C.text)
    name:SetPoint("TOPLEFT", head, "TOPLEFT", column, -2)

    local blurb = UI.Label(head, intro, UI.FS.row, C.textBody)
    blurb:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -10)
    blurb:SetJustifyH("LEFT")
    blurb:SetJustifyV("TOP")
    blurb:SetWidth(width - column)

    -- Author, version, client - caption over value, side by side. The same
    -- three the rail's foot carries, which is not a duplication: the foot is
    -- glanceable and this is the page you are sent to when somebody asks.
    --
    -- Zwoelf with the umlaut: this VALUE names the person. The addon keeps
    -- the transliteration everywhere it is an identifier. Owner: "der
    -- charakter heisst Zwölf! das addon zwoelf, wichtig!"
    local values = {
        "Zwölf  -  EU Destromath",
        ns.version,
        (GetBuildInfo()) or "",
    }

    local FIELD_GAP = 34
    local x, fieldTop = 0, nil
    for index, caption in ipairs(ABOUT_META) do
        local label = UI.Eyebrow(head, caption)
        local value = UI.Label(head, values[index], UI.FS.row, C.text)

        if fieldTop then
            label:SetPoint("TOPLEFT", fieldTop, "TOPLEFT", x, 0)
        else
            label:SetPoint("TOPLEFT", blurb, "BOTTOMLEFT", 0, -18)
            fieldTop = label
        end
        value:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)

        x = x + math.max(label:GetStringWidth(), value:GetStringWidth())
            + FIELD_GAP
    end

    -- IT SETS ITS OWN SIZE, and that is not a detail.
    --
    -- Grid:Layout gives a wide block a POINT and nothing else - it never sets
    -- a height. A frame left at its default 0 reserves the room the grid was
    -- told about and draws none of it, which is exactly what this block did on
    -- its first outing: owner, with a picture, "about hat ein riesen gap
    -- oben." Every other frame block in this window sets its own rectangle -
    -- Grid:Buttons does, the chip host does, the stat strip does - and this
    -- one had been written as if the grid would do it.
    --
    -- Measured, not typed: the blurb wraps, and how many lines that takes
    -- depends on the panel font the user chose.
    local NAME_H, EYEBROW_H, VALUE_H = 22, 11, 15
    local height = math.max(ABOUT_LOGO,
        NAME_H + 10 + blurb:GetStringHeight() + 18 + EYEBROW_H + 4 + VALUE_H)

    head:SetSize(width, height)
    head.Measure = function() return height end
    return head
end

-- WHY THIS ADDON EXISTS, IN HIS OWN WORDS, and the same words the README
-- opens with. Owner: "der text sollte auch ins about!" - and he is right that
-- it belongs here rather than only on a page nobody reads from inside the
-- game.
--
-- One paragraph up top rather than nine lines: the block beside the mark is
-- what somebody reads, and everything colder than that has its own heading
-- under it.
local ABOUT_INTRO =
    "After many years I have built a new addon again, one that serves my own "
    .. "needs as a tank first, and those of my M+ groups and friends. You will "
    .. "find a lot of these features in other addons too - but like everybody, "
    .. "I have my own ideas about what I want in the game. Hence this addon. I "
    .. "hope it is as useful to you as it is to me."

-- THE CREDIT, WORD FOR WORD FROM THE README. Owner: "in about muss unter
-- meinen text noch der info text aus der readme rein." It belongs in both
-- places for the same reason it exists at all: the people who would recognise
-- these names are players, and a player never opens a repository.
local ABOUT_CREDIT = {
    "This addon is no replacement for EllesmereUI or ElvUI. I love both of "
    .. "them and use them for my own UI. This is a collection of the features "
    .. "I like, done my way. And of course - feature requests and feedback are "
    .. "welcome!",

    "It was written by reading other addons - EllesmereUI, ElvUI, BigWigs, "
    .. "Method Raid Tools, Mythic Dungeon Tools, Details!, WeakAuras, Plater, "
    .. "LibOpenRaid and a few more. Their authors have our thanks.",

    "No code was copied from any of them. What we took is a different thing: "
    .. "facts about the game's API. Which field a table actually carries, "
    .. "which event fires first, which call answers on a fresh login and which "
    .. "one returns nothing until a frame later, which values the client "
    .. "withholds in a dungeon. None of that is documented anywhere, and on a "
    .. "patch that keeps closing doors it is often not discoverable at all "
    .. "except by reading code that already works.",

    "So the comments in Core/ cite those addons by name and by line, and they "
    .. "say 'read off working code on this machine' rather than pretending we "
    .. "knew. A number nobody can re-check is a number that quietly goes wrong "
    .. "two patches later - see Core/CDM.lua, which is mostly a record of "
    .. "where each fact came from.",

    "If you are one of those authors and you would rather not be named here, "
    .. "say so and we will take the citation out.",
}

-- One command row: the command on the left in the accent, what it does beside
-- it. NOT a Grid row - a row right-aligns its control against a slot, and
-- these two are a pair read left to right.
--
-- There is no monospace face to set the command in. The client ships none and
-- the panel font is whatever LibSharedMedia handed over, so the column is held
-- by a MEASURED indent instead and the colour does the separating.
local COMMAND_H = 20
local COMMAND_GAP = 14

local function BuildCommandColumn(parent, entries, columnWidth, cmdWidth)
    local block = CreateFrame("Frame", nil, parent)
    block:SetWidth(columnWidth)

    local y = 0
    for _, entry in ipairs(entries) do
        if entry.group then
            local caption = UI.Eyebrow(block, entry.group)
            caption:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -(y + 10))
            y = y + 10 + 18
        else
            local cmd = UI.Label(block, entry.cmd, UI.FS.meta, C.accent)
            cmd:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -y)
            cmd:SetWidth(cmdWidth)
            cmd:SetJustifyH("LEFT")

            local what = UI.Label(block, entry.text, UI.FS.meta, C.textDim)
            what:SetPoint("TOPLEFT", block, "TOPLEFT",
                cmdWidth + COMMAND_GAP, -y)
            what:SetWidth(columnWidth - cmdWidth - COMMAND_GAP)
            what:SetJustifyH("LEFT")
            what:SetJustifyV("TOP")

            -- A description can wrap, and the next row has to start under the
            -- taller of the two rather than under a number typed here.
            y = y + math.max(COMMAND_H, what:GetStringHeight() + 6)
        end
    end

    block:SetHeight(math.max(1, y))
    return block
end

-- Where to cut the command list into two columns, counting the HEIGHT each
-- entry costs rather than the entries - a heading is not a command and a
-- wrapped description is worth two rows.
--
-- Pure, and exported, because the harness cannot measure a string: it is the
-- balance rule that is worth checking, not the pixels.
function Options.SplitCommands(entries)
    local weight = 0
    for _, entry in ipairs(entries) do
        weight = weight + (entry.group and 1.4 or 1)
    end

    local half, running = weight / 2, 0
    for index, entry in ipairs(entries) do
        running = running + (entry.group and 1.4 or 1)
        -- Never cut so that a heading is the last thing in the left column.
        if running >= half and not entry.group then return index end
    end
    return #entries
end

local function BuildAboutPage(page, width)
    local grid = UI.Page(page, width)

    local head = BuildAboutHead(grid.content, grid.width, ABOUT_INTRO)
    grid:Wide(head, head.Measure(), 0, 10)

    ---------------------------------------------------------------------
    -- Where to get it
    --
    -- FROM ns.STORES, not typed here: the same list the release announcement
    -- prints from, so a third store appears on this page by existing rather
    -- than by somebody remembering.
    --
    -- A click cannot open a browser - no addon may hand a URL to one, by
    -- design - so it opens a box with the address selected. That is the
    -- honest version of a link inside a game: one Ctrl+C and it is in the
    -- address bar. A row that looked like a link and did nothing would be
    -- worse than no row.
    ---------------------------------------------------------------------
    grid:Section("Where to get it")

    for _, store in ipairs(ns.STORES) do
        local row = grid:Row(store.name, { icon = store.icon })
        local button = UI.Button(row.slot, "Copy the address",
            UI.ButtonWidth("Copy the address"), function()
                UI.CopyBox(store.name, store.url,
                    "Ctrl+C copies it, then paste it into your browser. "
                    .. "Esc closes.")
            end)
        button:SetPoint("RIGHT", row.slot, "RIGHT", 0, 0)
    end

    grid:Note("Both stores get the same build from the same release, so it "
        .. "makes no difference which one you use.")

    grid:Section("Standing on other people's shoulders")
    for _, paragraph in ipairs(ABOUT_CREDIT) do grid:Note(paragraph) end

    ---------------------------------------------------------------------
    -- WHO OWNS THIS, said in the addon rather than only in a file nobody
    -- opens. The store page has always said All Rights Reserved; the folder
    -- that ships shipped an MIT LICENSE beside it until 4.83.0, which is the
    -- kind of contradiction that only ever gets found by somebody acting on
    -- the wrong half of it.
    --
    -- The libraries are named separately on purpose: their terms are theirs,
    -- they travel with the files, and claiming them under ours would be
    -- exactly the mistake the LibDeflate note in the README is about.
    ---------------------------------------------------------------------
    grid:Section("Licence")

    grid:Note("ZwoelfStuff is |cffffd100All Rights Reserved|r, "
        .. "\194\169 2026 Christian McCain. Download it, install it, play "
        .. "with it, keep your own backup. Republishing it, selling it or "
        .. "handing out a changed copy needs written permission first.")

    grid:Note("The libraries under Libs/ keep their own terms and are not "
        .. "covered by that: LibStub is public domain, CallbackHandler is "
        .. "BSD, LibSharedMedia is LGPL 2.1, LibSerialize is MIT and "
        .. "LibDeflate is zlib.")

    grid:Note("Releases up to 4.82.0 went out under the MIT License. That "
        .. "was given and is not being taken back - it still applies to "
        .. "those versions. These terms start at 4.83.0.")

    ---------------------------------------------------------------------
    -- Commands
    --
    -- FROM ns.COMMANDS, which the chat help prints from as well. This page
    -- used to carry a second list, typed by hand, and it had gone stale: it
    -- advertised `/zs text` and knew nothing of build, modules, report, skin,
    -- test, taunt or death.
    ---------------------------------------------------------------------
    grid:Section("Commands")

    local cut = Options.SplitCommands(ns.COMMANDS)
    local left, right = {}, {}
    for index, entry in ipairs(ns.COMMANDS) do
        local into = (index <= cut) and left or right
        into[#into + 1] = entry
    end

    -- The widest command there is, measured once and used by both columns, so
    -- the two lists have one indent between them rather than two.
    local cmdWidth = 0
    local ruler = UI.Label(grid.content, "", UI.FS.meta, C.accent)
    for _, entry in ipairs(ns.COMMANDS) do
        if entry.cmd then
            ruler:SetText(entry.cmd)
            cmdWidth = math.max(cmdWidth, ruler:GetStringWidth() or 0)
        end
    end
    ruler:Hide()
    cmdWidth = math.ceil(cmdWidth) + 6

    local columnWidth = grid.colWidth
    local host = CreateFrame("Frame", nil, grid.content)

    local leftBlock = BuildCommandColumn(host, left, columnWidth, cmdWidth)
    leftBlock:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)

    local rightBlock = BuildCommandColumn(host, right, columnWidth, cmdWidth)
    rightBlock:SetPoint("TOPLEFT", host, "TOPLEFT",
        columnWidth + UI.COL_GAP, 0)

    local tallest = math.max(leftBlock:GetHeight(), rightBlock:GetHeight())
    host:SetHeight(tallest)
    grid:Wide(host, tallest, 0, 10)

    grid:Layout()
end

---------------------------------------------------------------------------
-- Changelog
---------------------------------------------------------------------------
-- ONE RELEASE IS ONE THING TO READ, so it is drawn as one.
--
-- It was a version, a date and a column of hyphens, and forty-six of those
-- run together into a wall you scroll past rather than read. What separates
-- them now is the same thing that separates two sections anywhere else in
-- this window: a rule across, air above it, and the eye's own idea of a
-- block. No boxes - a card border around every release would be forty-six
-- rectangles and louder than the words in them.
--
-- THE ONE YOU ARE RUNNING SAYS SO. Opening this page after an update, the
-- first question is "is this the one I just got", and a date does not answer
-- it - "installed" beside the number does.
local function BuildChangelogPage(page, width)
    local textWidth = width - 20
    local scroll, content = UI.ScrollArea(page, textWidth)

    local y = 0
    for index, entry in ipairs(ns.CHANGELOG) do
        -- A hairline over every release but the first: it belongs to the gap
        -- BETWEEN two of them, so the top of the page does not get one.
        if index > 1 then
            y = y - 20
            local rule = content:CreateTexture(nil, "ARTWORK")
            rule:SetColorTexture(C.edge[1], C.edge[2], C.edge[3], 1)
            rule:SetHeight(1)
            rule:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
            rule:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
            y = y - 20
        end

        local heading = UI.Label(content, entry.version, 15, C.accent)
        heading:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)

        local date = UI.Label(content, entry.date, 11, C.textFaint)
        date:SetPoint("LEFT", heading, "RIGHT", 10, -1)

        if entry.version == ns.version then
            local mark = UI.Label(content, "INSTALLED", 10, C.textDim)
            mark:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y - 2)
        end

        y = y - 26

        for _, line in ipairs(entry.lines) do
            -- A DOT, not a hyphen: a hyphen sits on the baseline of a line
            -- whose first row is what it belongs to, and at three lines of
            -- wrapped text it reads as punctuation. Four pixels, faint, on
            -- the cap height of the first row.
            local dot = content:CreateTexture(nil, "ARTWORK")
            dot:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.55)
            dot:SetSize(3, 3)
            dot:SetPoint("TOPLEFT", content, "TOPLEFT", 3, y - 7)

            -- THROUGH THE SAME READER AS THE NEWS WINDOW. A line may be a
            -- string or a table carrying an icon and a link, and this page
            -- passed it straight to SetText - so the first entry with an
            -- icon in it emptied the whole page. One list with two readers
            -- is one reader too many; there is a shared one for this.
            local bullet = UI.Label(content, ns.ChangelogText(line), 12,
                C.text)
            bullet:SetPoint("TOPLEFT", content, "TOPLEFT", 14, y)
            bullet:SetWidth(textWidth - 14)
            bullet:SetJustifyV("TOP")
            -- Width is set, so GetStringHeight reports the wrapped height.
            -- Ten between two entries rather than six: these are sentences,
            -- not a list of names, and they need to come apart.
            y = y - (bullet:GetStringHeight() + 10)
        end
    end

    content:SetHeight(math.max(1, -y + 10))
    if scroll.Update then scroll.Update() end
end

---------------------------------------------------------------------------
-- The functions in the left column
--
-- "cooldowns" is the addon; the rest are secondary and look it. Only the
-- first one uses the right column, which is why it carries the flag rather
-- than the shell hardcoding an index.
---------------------------------------------------------------------------
-- THE FIRST ENTRY IS THE PAGE THE WINDOW OPENS ON, and that is not merely an
-- order: Create() runs its builder before anything is shown. Whatever stands
-- here has to survive being built before the window has ever been on screen.
--
-- (The ten lines that used to sit here belonged to the Cooldowns page, which
-- was the first entry until the bars went. The comment stayed behind and read
-- as if it were about Settings - "its two actions carry their marks" over a
-- page that has no actions.)
-- IS THIS PAGE FINISHED? Pure, and kept out of the paint for the reason
-- every guard in this addon is kept out of one: a flag that is only ever
-- read inside a repaint is a flag no test can ask a question about. It also
-- pins WHERE the answer comes from - the entry, not the page index - so
-- retiring the mark is deleting one word from the table below.
function Options.ComingSoon(entry)
    return type(entry) == "table" and entry.soon == true
end

local PAGES = {
    -- Through the namespace like the pages below it: the builder lives in
    -- Core/OptionsSettings.lua. What this page holds is the split its own
    -- header comment explains - every bar, this window, the ways in - and
    -- nothing that changes WHICH settings you have. That is Profiles.
    -- NO THIRD COLUMN. It had the explain panel - a column that shows the
    -- paragraph belonging to whichever row you point at - and the owner threw
    -- it out on sight: "die settings seite braucht keine rechte leiste."
    --
    -- He is right, and the reason is that this page is the one where the
    -- paragraphs are SHORT. A panel 400 wide standing empty until you hover
    -- something, to hold two lines that fit under the row perfectly well, is
    -- 400 pixels spent on a hover state. The notes are drawn on the page now,
    -- which is what every other page without a third column does.
    { key = "settings", title = "Settings", glyph = "sliders",
      subtitle = "Every bar, this window, and the ways in.",
      build = function(page, width) return ns.OptionsSettings:BuildPage(page, width) end },

    -- The one page that is about somebody ELSE. It carries its own right-hand
    -- column - not the bar inspector and not the explain panel - because what
    -- belongs beside a co-tank preview is the co-tank settings and nothing in
    -- the other two is about this page at all.
    -- NO HEADER ACTIONS. Owner, 2026-08-16: the macro button belongs with
    -- the taunt settings it writes for - it sits under "Asking for a taunt"
    -- on the page now - and "What a taunt would say" was a report for the
    -- desk, not a thing a player goes looking for. `/zs tanks` still prints
    -- it.
    { key = "cotanks", title = "Tank Unitframes", glyph = "tanks", tanks = true,
      module = "cotanks",
      subtitle = "Every tank in the group, with their health and their auras.",
      -- Through the namespace, not a local: the builder lives in
      -- Core/OptionsCoTanks.lua, which loads BEFORE this file but after this
      -- table would have captured a local upvalue that was still nil.
      build = function(page, width) return ns.OptionsCoTanks:BuildPage(page, width) end },

    -- The other page about the fight rather than about the bars. It carries
    -- the SPELL LIST as its third column - the same list the bars page uses -
    -- because the whole gesture is dragging a spell onto the reminder.
    { key = "reminders", title = "Reminders", glyph = "bell", reminders = true,
      module = "reminders",
      subtitle = "Text on your screen when a buff has fallen off.",
      build = function(page, width) return ns.OptionsReminders:BuildPage(page, width) end },

    -- The cooldowns SOMEBODY ELSE presses on you. Its third column is our own
    -- own short list rather than the Cooldown Manager's catalogue - that
    -- list is YOUR spells, and every spell on this page belongs to another
    -- player.
    { key = "externals", title = "External CD request", glyph = "tanks",
      externals = true, module = "externals",
      subtitle = "Somebody else's cooldown, and one click to ask for it.",
      actions = {
          { text = "Set keys",
            onClick = function() ns.Keys:SetActive(true) end },
          { text = "Test mode", widest = "Test mode: on",
            label = function()
                return ns.Externals.testing and "Test mode: on" or "Test mode"
            end,
            onClick = function()
                ns.Externals:SetTestMode(not ns.Externals.testing)
                ns.Options:Refresh()
            end },
      },
      build = function(page, width) return ns.OptionsExternals:BuildPage(page, width) end },

    -- THE MIRROR OF THE PAGE ABOVE. That one asks; this one is asked. Two
    -- pages rather than two halves of one, because they belong to different
    -- people on different evenings - a tank sets the first up, a healer the
    -- second - and they are separate modules for the same reason.
    -- Its third column is YOUR answer spells - the drag source for the
    -- Alerts tab, which is the reminders page on the answer alerts' book
    -- (owner, 2026-08-17: "in die rechte seite ... haust du die answer
    -- spells").
    { key = "answers", title = "External CD answer", glyph = "tanks",
      module = "answers", answers = true,
      subtitle = "When somebody asks for one of yours, a button lights up.",
      -- ONE ACTION. "What every cell would cast" was the report that says
      -- whether this works at all - and it is a report for the desk, so it
      -- left the header on the owner's word (2026-08-16). ns.Answers:Dump()
      -- is still there behind `/zs answers`.
      actions = {
          { text = "Set keys",
            onClick = function() ns.Keys:SetActive(true) end },
      },
      build = function(page, width) return ns.OptionsAnswers:BuildPage(page, width) end },

    -- WHAT IS BEING CAST AT YOU. Its third column is the season's mob list
    -- out of Core/MobData.lua - the shape of EXBoss's Trash CD page (owner,
    -- 2026-08-18, with two screenshots of it). Alerts filter on the NPC id,
    -- because the spell id of a live cast is secret on this patch.
    { key = "casts", title = "Casts on you", glyph = "pulse",
      module = "casts", casts = true, soon = true,
      subtitle = "The bar says what is being cast, and marks the one on you.",
      build = function(page, width) return ns.OptionsCasts:BuildPage(page, width) end },

    -- THE RAID LEADER'S PAGE. Its third column is the list of buttons there
    -- are, which is the externals page's shape and deliberately so - the
    -- owner asked for "das bewaehrte layout wo ich mir die bar zusammen
    -- stellen kann", and two pages that assemble a lattice must not be two
    -- different pictures.
    { key = "raidbar", title = "Raid Bar", glyph = "grid", raidbar = true,
      module = "raidbar",
      subtitle = "Markers, pings, a ready check and a pull timer.",
      actions = {
          { text = "Raid check",
            onClick = function() ns.RaidCheck:Toggle() end },
          { text = "Move it",
            onClick = function() ns.EditMode:SetUnlocked(true) end },
      },
      build = function(page, width) return ns.OptionsRaidBar:BuildPage(page, width) end },

    -- THE COOLDOWN MANAGER PAGE IS GONE FROM THIS LIST, on the owner's word
    -- (2026-08-16): "das modul komplett aus der uebersicht links rausnehmen
    -- ... als wenn es nicht drin waere." The page builder
    -- (OptionsCooldowns) still loads and the module entry still exists,
    -- hidden - see Core/Modules.lua - so `/zs modules cooldowns` can
    -- resurrect the feature without an install. Putting the page back is
    -- one entry here and one NAV row below.

    -- NO THIRD COLUMN. Everything on it is a yes-or-no about something that
    -- happens without you, and there is no list to pick from - the two boxes
    -- are typed into.
    { key = "invites", title = "Invites", glyph = "tanks", module = "invites",
      subtitle = "Somebody whispers a word and they are in the group.",
      -- THE THREE THINGS THIS PAGE DOES RIGHT NOW are its header, on the
      -- owner's word (2026-08-16): they used to sit at the bottom of the
      -- page under the rank filter, and "What is listening" - a report for
      -- the desk - sat up here instead. The rank filter stays on the page,
      -- beside the note that says what it filters.
      actions = {
          { text = "Invite the guild",
            onClick = function() ns.Invites.InviteGuild() end },
          { text = "Invite everyone back",
            onClick = function() ns.Invites.InviteBack() end },
          { text = "Disband",
            onClick = function() ns.Invites.Disband() end },
      },
      build = function(page, width) return ns.OptionsInvites:BuildPage(page, width) end },

    -- The death log, and with it the DEFENSIVES LIST that used to live on a
    -- Timeline page of its own. That page is gone: what it drew live was the
    -- fight's next scheduled hit, and the replay answers the same question
    -- afterwards with everything the panel could never show. The list it
    -- carried was always read by this window anyway.
    --
    -- It carries the spell palette as its third column, because picking your
    -- defensives out of a dropdown of forty names was the worst part of it.
    { key = "deaths", title = "Death-log", glyph = "skull", deaths = true,
      module = "deaths",
      subtitle = "What killed you, and what could have prevented it.",
      actions = {
          { text = "Open it", onClick = function() ns.Death:Show() end },
          { text = "Share in chat", onClick = function() ns.Death:Share() end },
      },
      build = function(page, width) return ns.OptionsDeaths:BuildPage(page, width) end },

    -- The third page about the fight. No third column: what it shows is the
    -- state of a route, and there is no list to pick from.
    -- Its own page rather than a section of Settings. Everything on Settings
    -- changes how something LOOKS; everything here changes which settings are
    -- in use at all, and one of the buttons deletes them. Those two do not
    -- belong on one page under two headings.
    { key = "profiles", title = "Profiles", glyph = "sliders",
      subtitle = "Name a set of settings, share it, or use somebody else's.",
      build = function(page, width) return ns.OptionsProfiles:BuildPage(page, width) end },

    { key = "diagnostics", title = "Diagnostics", glyph = "pulse",
      subtitle = "What the Cooldown Manager holds.",
      build = BuildDiagnosticsPage },

    -- ONE ACTION, AND THE STORES ARE NOT IT.
    --
    -- CurseForge was up here for a version. Then Wago arrived, and three
    -- addresses do not fit a band with a measured ceiling of two - which is
    -- the right answer, because it exposed the real mistake: a download
    -- address is not something you DO on this page, it is something the page
    -- SAYS. The stores are a section in the body now, built from ns.STORES,
    -- so a third one appears by existing.
    --
    -- Discord stays, because "ask somebody" is an action.
    { key = "about", title = "About", glyph = "info",
      subtitle = "Why this addon exists, and every command.",
      actions = {
          { text = "Discord", icon = "brand-discord", onClick = function()
              UI.CopyBox("Discord", ns.DISCORD_URL,
                  "Ctrl+C copies it, then paste it into your browser. "
                  .. "Esc closes.")
          end },
      },
      build = BuildAboutPage },

    { key = "changelog", title = "Changelog", glyph = "log",
      subtitle = "What changed, and why.",
      build = BuildChangelogPage },
}

-- The three pages that carry a THIRD COLUMN, published so the rule below can
-- be checked without building a window.
Options.PAGES = PAGES

---------------------------------------------------------------------------
-- The rail, in the order it reads
--
-- AT FILE SCOPE SO IT CAN BE CHECKED. It was built inside the window, where
-- nothing could look at it, and a `page` naming a key PAGES no longer has
-- costs a blank row: the lookup answers nil, the label falls back to the
-- empty string and the click calls ShowPage(nil). A dead row in the rail
-- that says nothing about itself - which is what "the Bars entry can go" was
-- one bad edit away from leaving behind.
--
-- Every entry is an `eyebrow` heading, a `page`, or a bare `gap`. The one row
-- that is none of those - Edit mode, which CLOSES this window rather than
-- opening a page - is added by the builder, because its action needs the
-- frame it closes. It goes at the head: it is the entry used most often, and
-- a door belongs at the top.
--
-- THE FIRST GROUP HAS NO HEADING, at the owner's word 2026-08-15: "entferne
-- M+ and raid stuff". It never earned one - "System" and "Info" name a
-- handful of rows each and are worth a caption, while the first group was
-- everything the addon does and got a label that only said so at length.
--
-- The `gap` in its place is not decoration and is the reason this is not a
-- plain deletion. That heading carried the ONLY air between the door and the
-- list (see `position > 1` in the painter), and glueing Edit mode to
-- Cooldowns turns a door into the first item of a menu.
---------------------------------------------------------------------------
local NAV = {
    { gap = true },
    -- Cooldowns stood here, above co-tanks, until the owner benched the
    -- feature (2026-08-16): "komplett aus der uebersicht links rausnehmen".
    { page = "cotanks" },
    { page = "reminders" },
    { page = "externals" },
    { page = "answers" },
    { page = "casts" },
    { page = "deaths" },
    -- THE TWO NEWEST GO AT THE END, at the owner's word: "raid bar bitte
    -- unter death log stellen".
    --
    -- The first draft put the raid bar at the head of this group on the
    -- argument that it is the entry about the whole group rather than about
    -- you. That argument is fine and it loses to a better one: the five above
    -- it have not moved since they were added, and a rail somebody has been
    -- reading for weeks is a list they no longer read - they go to the place.
    -- Inserting a row at the top moves every one of those places by one, to
    -- save one row of travel on a page that is new to everybody anyway.
    { page = "raidbar" },
    { page = "invites" },
    { eyebrow = "System" },
    { page = "settings" },
    { page = "profiles" },
    { page = "diagnostics" },
    { eyebrow = "Info" },
    { page = "about" },
    { page = "changelog" },
}
Options.NAV = NAV

-- A PAGE IS BUILT AT THE WIDTH IT WILL BE SHOWN AT, not at the widest one
-- there is.
--
-- Every page used to be built at the WIDE middle column - the one you get when
-- there is no third column. A page that DECLARES a third column is shown in
-- the NARROW middle instead, so its rows were 1136 units wide inside 750: the
-- labels showed, the rule lines ran to the edge and were clipped, and every
-- control - which sits at the RIGHT end of its row - was four hundred units
-- off the side of the window.
--
-- The whole Co-Tanks page looked like a list of headings with nothing to set,
-- and Settings has had the same hole in it since the explain column was added:
-- its font pickers are full-width rows and have never been on screen.
-- Half-width rows fit either way, which is why it survived so long and why it
-- was invisible - the page was half working, which reads as a design.
--
-- Pure and exported for the same reason SnapAxis and SparkEdge are: the whole
-- rule is one table entry in and one number out, and the desktop harness
-- CANNOT see the bug it prevents - its frame stub answers GetWidth with a
-- fixed number whatever was set, so a page built at the wrong width looks
-- exactly like one built at the right one.
-- DOES THIS PAGE CARRY A THIRD COLUMN AT ALL?
--
-- One function, because the answer is needed in three places - the width
-- above, the painter below, and the check in SelfTest - and the check used to
-- carry its own copy of the list. A page flag added to PAGES and to PageWidth
-- but not to the check would then be asserted against the OLD rule and fail
-- while being correct, which is precisely what a new page did.
--
-- WHICH column it is stays a separate question, asked only by the painter.
---------------------------------------------------------------------------
-- THE OFF STATE, drawn once and reused by every page that has a module.
--
-- Owner's choice, 2026-08-09: a switched-off module keeps its row in the rail
-- and keeps its page. So the page is still built and still shown, and this
-- sits over it, greying it and swallowing the clicks.
--
-- ONE of these, not one per page. Four copies of "this is switched off" is
-- four things to keep in step, and it is always the fourth that drifts - the
-- same reason the death window has one renderer and not a preview beside it.
--
-- It is deliberately not a full curtain: what shows through underneath is the
-- page you would get, which is the best argument the switch has.
---------------------------------------------------------------------------
local function BuildModuleGate(parent)
    local gate = CreateFrame("Frame", nil, parent)
    gate:SetAllPoints(parent)
    -- Well above the page it covers. A page builds cards, scroll areas and
    -- popups at levels of their own, and a curtain a card can poke through is
    -- worse than none.
    gate:SetFrameLevel(parent:GetFrameLevel() + 30)
    -- Swallows what is meant for the page beneath. Without this the greyed
    -- page is still fully clickable, which is the one thing greying promises
    -- it is not.
    gate:EnableMouse(true)
    gate:Hide()
    UI.Fill(gate, "BACKGROUND", C.windowBg, 0.86)

    local card = UI.Card(gate, 460)
    card:SetPoint("TOP", gate, "TOP", 0, -120)

    local title = UI.Label(card, "", UI.FS.card, C.text)
    title:SetPoint("TOPLEFT", card, "TOPLEFT", UI.PAD, -UI.PAD)

    local blurb = UI.Label(card, "", UI.FS.meta, C.textBody)
    blurb:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    blurb:SetWidth(460 - UI.PAD * 2)
    blurb:SetJustifyH("LEFT")

    local detail = UI.Label(card, "", UI.FS.meta, C.textFaint)
    detail:SetPoint("TOPLEFT", blurb, "BOTTOMLEFT", 0, -6)
    detail:SetWidth(460 - UI.PAD * 2)
    detail:SetJustifyH("LEFT")

    local button = UI.Button(card, ns.L["Switch it on"], 140, function()
        if gate.key then
            ns.Modules:Set(gate.key, true)
            ns.Options:Refresh()
        end
    end, "primary")
    button:SetPoint("TOPLEFT", detail, "BOTTOMLEFT", 0, -UI.PAD)

    -- The card is as tall as what is in it, measured after the text has been
    -- set rather than guessed at - two wrapped lines and one are 14 pixels
    -- apart, and a fixed height is wrong for one of them.
    function gate:Update(key)
        self.key = key
        local entry = key and ns.Modules:Get(key)
        if not entry then
            self:Hide()
            return
        end
        title:SetText(ns.L("%s is switched off", ns.L[entry.title]))
        blurb:SetText(ns.L[entry.blurb])
        detail:SetText(entry.detail and ns.L[entry.detail] or "")
        detail:SetShown((entry.detail or "") ~= "")
        card:SetHeight(UI.PAD + title:GetStringHeight() + 8
            + blurb:GetStringHeight() + (detail:IsShown() and (6 + detail:GetStringHeight()) or 0)
            + UI.PAD + UI.BUTTON_H + UI.PAD)
        self:Show()
    end

    return gate
end

function Options.HasThirdColumn(entry)
    return (entry.side or entry.explain or entry.tanks or entry.reminders
        or entry.deaths or entry.externals or entry.raidbar
        or entry.cooldowns or entry.answers or entry.casts) and true or false
end

-- WHICH PAGE THE WINDOW OPENS ON, as a pure function of the page list and
-- what was last remembered.
--
--   the remembered key, if that page still exists and its module is on
--   else the first page there is, which is Settings and always exists
--
-- (The middle preference - "else Cooldowns, where a fresh install lands" -
-- went with the Cooldowns page when the owner benched the feature.)
--
-- Pure so the desk can ask it every one of those ways without a window.
function Options.Landing(pages, remembered)
    local firstLive
    for index, entry in ipairs(pages or {}) do
        local live = not entry.module or ns.Modules:IsOn(entry.module)
        if live then
            if entry.key == remembered then return index end
            firstLive = firstLive or index
        end
    end

    return firstLive or 1
end

function Options.PageWidth(entry, narrow, wide)
    if Options.HasThirdColumn(entry) then return narrow end
    return wide
end

-- The one place the window's scale is applied, so the row on Settings and
-- the boot path cannot drift apart about what the setting means.
function Options:ApplyScale()
    if self.frame then self.frame:SetScale(ns.db.windowScale or 1) end
end

-- HOW SOLID THE WINDOW IS, and there is exactly ONE alpha - on the outermost
-- frame, where it fades the whole thing at once.
--
-- Not per layer. Card 90, row 80, field 70 sounds like depth and is not: the
-- values MULTIPLY wherever two of them overlap, so no surface has a colour you
-- can predict from its own setting, and the darkest tone in the design stops
-- being the darkest one.
--
-- 94% by default. That is enough to see that something is behind the window
-- and little enough that no 13px label goes soft; below about 85 it stops
-- being reliable over a bright scene. The file header in Widgets.lua used to
-- say every colour here is opaque - the owner asked for this, so that block
-- says what it says now.
--
-- Like windowScale, it is read with a fallback rather than seeded into
-- DEFAULTS: a profile that predates the setting resolves to the same number
-- as a new one, and nothing has to migrate.
function Options:ApplyAlpha()
    if self.frame then self.frame:SetAlpha(ns.db.windowAlpha or 0.94) end
end

function Options:Create()
    if self.frame then return end

    local frame = CreateFrame("Frame", "ZwoelfStuffOptionsFrame", UIParent)
    frame:SetSize(WINDOW_W, WINDOW_H)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnHide", function()
        -- The menu lives on UIParent so it can escape the window bounds; it
        -- may not outlive the window.
        UI.ClosePopup()
    end)
    frame:Hide()

    UI.Fill(frame, "BACKGROUND", C.windowBg)

    -- THE GROUND GETS AN UP AND A DOWN.
    --
    -- It was one flat colour, and three columns of three flat colours have no
    -- direction at all - the window read as a wall rather than as a surface.
    -- A single vertical gradient over the whole frame fixes that for the price
    -- of one texture: lighter at the top, gone by the middle, so nothing sits
    -- on a ground that is brighter than the row above it.
    --
    -- NO TILED WEAVE. It was drawn in the mockup and measured out again: a
    -- pattern under 12px text needs to sit on the interface grid to stay
    -- still, WoW does not put it there, and 4% of a texture that shimmers is
    -- worse than no texture. The gradient carries the whole effect anyway.
    if type(CreateColor) == "function" then
        local lift = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
        lift:SetColorTexture(1, 1, 1, 1)
        lift:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
        lift:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
        lift:SetHeight(math.floor(WINDOW_H * 0.55))
        lift:SetGradient("VERTICAL",
            CreateColor(C.windowBg[1], C.windowBg[2], C.windowBg[3], 0),
            CreateColor(0.106, 0.118, 0.145, 1))
    end
    local outer = ns.CreateBorder(frame, 1, "BORDER")
    outer:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)

    ---------------------------------------------------------------------
    -- Left column
    ---------------------------------------------------------------------
    local rail = CreateFrame("Frame", nil, frame)
    rail:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    rail:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
    rail:SetWidth(SIDEBAR_W)
    UI.Fill(rail, "BACKGROUND", C.sidebarBg)

    local railEdge = UI.Separator(rail, false)
    railEdge:SetPoint("TOPRIGHT", rail, "TOPRIGHT", 0, 0)
    railEdge:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", 0, 0)

    -- NO LIT CAP OVER THE RAIL, AND IT IS NOT TO COME BACK.
    --
    -- 4.76.0 put a four-layer gradient here and 160 pixels of dark red stood
    -- over the wordmark. Owner, with a picture of it: "lass den verlauf weg,
    -- das sieht unmoeglich aus und raum das menue wieder auf."
    --
    -- The gesture it was copying - a wordmark standing on artwork, the way a
    -- launcher does it - needs artwork worth standing on. A gradient is not
    -- that. What it actually bought was a third of the column spent on
    -- nothing, above a list that then had to fight for the rest.
    --
    -- The head starts at the top of the rail now, where it started before.

    -- The rail head, on the same 62 as every other column's header band.
    --
    -- A FRAME of its own now, rather than offsets from the rail's top corner.
    -- Everything below it is anchored to it, so setting the art's height at
    -- the end re-flows the head and the nav with it - and a hardcoded offset
    -- here would have to be corrected in three more places every time the cap
    -- changes.
    local head = CreateFrame("Frame", nil, rail)
    head:SetHeight(HEADER_H)
    head:SetPoint("TOPLEFT", rail, "TOPLEFT", 0, 0)
    head:SetPoint("TOPRIGHT", rail, "TOPRIGHT", 0, 0)

    -- The mark is the addon's own icon, at 26. The wordmark is lower case and
    -- carries the split in COLOUR rather than in weight: `zwoelf` in text and
    -- `stuff` a step back. There is no weight axis on a FontString - the panel
    -- font is whatever LibSharedMedia handed over and it may ship one cut - so
    -- a design that asks for 600 against 400 gets contrast it can actually
    -- have.
    local mark = head:CreateTexture(nil, "ARTWORK")
    mark:SetSize(26, 26)
    mark:SetPoint("TOPLEFT", head, "TOPLEFT", UI.PAD, -18)
    mark:SetTexture(ns.ICON_TEXTURE)

    local brand = UI.Label(head, "zwoelf", UI.FS.card, C.text)
    brand:SetPoint("TOPLEFT", mark, "TOPRIGHT", 10, -1)

    local brandTail = UI.Label(head, "stuff", UI.FS.card, C.textFaint)
    brandTail:SetPoint("LEFT", brand, "RIGHT", 0, 0)

    local brandSub = UI.Eyebrow(head, "EU Destromath")
    brandSub:SetPoint("TOPLEFT", brand, "BOTTOMLEFT", 0, -3)

    -- The foot: what version this is, and what it is running on. Both are the
    -- first thing anybody is asked for when something is wrong, and neither
    -- belongs anywhere the eye goes while working.
    local foot = CreateFrame("Frame", nil, rail)
    foot:SetHeight(RAIL_FOOT_H)
    foot:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", 0, 0)
    foot:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", 0, 0)

    local footLine = UI.Separator(foot, true)
    footLine:SetPoint("TOPLEFT", foot, "TOPLEFT", 0, 0)
    footLine:SetPoint("TOPRIGHT", foot, "TOPRIGHT", 0, 0)

    local versionLabel = UI.Label(rail, "v" .. ns.version, UI.FS.eyebrow, C.textGhost)
    versionLabel:SetPoint("LEFT", foot, "LEFT", UI.PAD, 0)

    -- GetBuildInfo returns version, build, date, tocversion. The first is the
    -- one people quote.
    local clientVersion = UI.Label(rail, (GetBuildInfo()) or "", UI.FS.eyebrow,
        C.textGhost)
    clientVersion:SetPoint("RIGHT", foot, "RIGHT", -UI.PAD, 0)

    -- THE THREE ADDRESSES, above the foot rule.
    --
    -- Where to get it, and where to ask. None of these can open a browser - no
    -- addon can, the client has no call for it - so a click opens the copy box
    -- with the address already selected. That is the honest version of a link
    -- inside a game: one Ctrl+C and it is in the address bar. A row that looked
    -- like a link and did nothing would be worse than no row.
    --
    -- SHORTER THAN A NAV ROW, and the number is not a preference. The rail is
    -- 758 tall; head 62 and foot 38 come off it, and the nav needs 512 today.
    -- Three rows at the nav's own 30 plus their air would leave 44 - less than
    -- the two spare pages the checks insist on. At 22 they leave 68. That is
    -- also the right LOOK: these are references, not pages, and a reference
    -- that stands as tall as a destination claims to be one.
    --
    -- Built from ns.STORES plus Discord rather than typed out, so a third
    -- store appears here by existing. The addresses live in Init.lua, so this
    -- column and the About page cannot end up pointing at different places.
    local LINK_H = RAIL_LINK_H
    local LINKS = {}
    for _, entry in ipairs(ns.LINKS) do
        LINKS[#LINKS + 1] = { text = entry.name, url = entry.url,
            icon = entry.icon }
    end

    -- Laid out from the foot upwards, so the LAST one written sits nearest the
    -- version line and adding a fourth pushes the block up rather than into
    -- the foot.
    local previousLink
    for position = #LINKS, 1, -1 do
        local entry = LINKS[position]

        local link = CreateFrame("Button", nil, rail)
        link:SetHeight(LINK_H)
        if previousLink then
            link:SetPoint("BOTTOMLEFT", previousLink, "TOPLEFT", 0, 0)
            link:SetPoint("BOTTOMRIGHT", previousLink, "TOPRIGHT", 0, 0)
        else
            -- Air above the block. At 6 the first of these sat against
            -- Changelog and read as the last entry of the Info group, which
            -- it is not - all three leave the addon.
            link:SetPoint("BOTTOMLEFT", foot, "TOPLEFT", 0, 12)
            link:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT", 0, 12)
        end
        previousLink = link

        -- The same hover ground a nav row has. Without it these are the only
        -- rows in the column that answer the mouse with nothing but a colour,
        -- and a row that behaves differently reads as a row of another kind.
        local background = UI.Fill(link, "BACKGROUND", C.surface)
        background:Hide()

        -- NO MARKS. There was one here for Discord for a version and it was
        -- not Discord's - traced from memory, and a brand mark you have drawn
        -- yourself is worse than none, because it claims to be the real thing.
        -- The words say it exactly, and two of the three have no mark that
        -- could be drawn at all.
        --
        -- ON THE NAV'S OWN INDENT, not the headings'. See UI.NAV_LABEL_X: at
        -- 16 this lined up with "INFO" rather than with "Changelog" right
        -- above it, and the whole foot of the column looked broken for it.
        -- A MARK ON EACH, on the nav's own 16 so the three line up with the
        -- entries above them rather than starting a second left edge.
        --
        -- It is the SAME mark on all three, and it is not a brand. It says
        -- "this leaves the game", which is the one thing all three have in
        -- common and the only thing about them this addon can honestly draw.
        -- Real logos are image files, and the two ways to get them are to
        -- ship the official ones or to trace them from memory; the second is
        -- worse than none, because a traced mark claims to be the real thing.
        -- Drop the official files into Media/icons and this line takes them.
        -- THEY ARE ON THE DISK NOW (2026-08-16) - the real marks, see
        -- ns.LINKS - so each row wears its own, and the arrow that stood in
        -- for all of them stays the fallback for a link without one.
        local outward = UI.Glyph(link, entry.icon or "menu-export", 12,
            C.textGhost)
        outward:SetPoint("LEFT", link, "LEFT", UI.PAD, 0)

        local label = UI.Label(link, entry.text, UI.FS.meta, C.textDim)
        label:SetPoint("LEFT", link, "LEFT", UI.NAV_LABEL_X, 0)

        link:SetScript("OnEnter", function()
            background:Show()
            label:SetTextColor(C.text[1], C.text[2], C.text[3])
        end)
        link:SetScript("OnLeave", function()
            background:Hide()
            label:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
        end)
        link:SetScript("OnClick", function()
            UI.CopyBox(entry.text, entry.url,
                "Ctrl+C copies it, then paste it into your browser. Esc "
                .. "closes.")
        end)
    end


    -- ONE rule, across the whole window. Three separate lines with three sets
    -- of padding never quite agree, and the eye reads the disagreement as
    -- sloppiness even when the heights match.
    --
    -- Window chrome: the one header rule and the close button. Both have to
    -- sit ABOVE the three column backgrounds, and a texture on the window
    -- itself would be painted under its own child frames no matter which
    -- layer it claims. So they get a frame of their own, with a level that
    -- settles the question rather than relying on creation order.
    local chrome = CreateFrame("Frame", nil, frame)
    chrome:SetAllPoints(frame)
    chrome:SetFrameLevel(frame:GetFrameLevel() + 20)

    local headerLine = chrome:CreateTexture(nil, "OVERLAY")
    headerLine:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -HEADER_H)
    headerLine:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -HEADER_H)
    headerLine:SetHeight(1)
    headerLine:SetColorTexture(C.separator[1], C.separator[2], C.separator[3], 1)

    -- The one close cross, in the window's top-right corner - which is also
    -- the top right of the inspector, which is where the design draws it.
    local close = CreateFrame("Button", nil, chrome)
    close:SetSize(CLOSE_W, CLOSE_W)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -19)
    -- The design's cross, not the letter X. At 12 the two are hard to tell
    -- apart until you look, and then the letter is unmistakable: it has serif
    -- weight on one stroke and none on the other.
    local closeMark = UI.Glyph(close, "ui-close", 12, C.textDim)
    closeMark:SetPoint("CENTER", close, "CENTER", 0, 0)
    close:SetScript("OnEnter", function()
        closeMark:SetColor(C.danger[1], C.danger[2], C.danger[3])
    end)
    close:SetScript("OnLeave", function()
        closeMark:SetColor(C.textDim[1], C.textDim[2], C.textDim[3])
    end)
    close:SetScript("OnClick", function() frame:Hide() end)

    ---------------------------------------------------------------------
    -- Right column
    ---------------------------------------------------------------------
    local sideHost = CreateFrame("Frame", nil, frame)
    sideHost:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    sideHost:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    sideHost:SetWidth(SIDE_W)
    UI.Fill(sideHost, "BACKGROUND", C.sidebarBg)

    local sideEdge = UI.Separator(sideHost, false)
    sideEdge:SetPoint("TOPLEFT", sideHost, "TOPLEFT", 0, 0)
    sideEdge:SetPoint("BOTTOMLEFT", sideHost, "BOTTOMLEFT", 0, 0)

    ---------------------------------------------------------------------
    -- The third column on a page that has no bar list: what the row you
    -- are pointing at actually does.
    --
    -- THE COLUMN IS NEVER EMPTY, and that is the point of it. Every setting
    -- used to carry its explanation on a wrapped grey line underneath, which
    -- was the single largest consumer of vertical space on the page - forty
    -- rows, forty paragraphs, and a page you scroll past the thing you came
    -- for. The text is the same text; it has moved to the one place that had
    -- nothing in it.
    ---------------------------------------------------------------------
    local explain = CreateFrame("Frame", nil, sideHost)
    explain:SetAllPoints(sideHost)
    explain:Hide()

    local explainTitle = UI.Label(explain, "", UI.FS.card, C.text)
    explainTitle:SetPoint("TOPLEFT", explain, "TOPLEFT", PAD, -16)
    explainTitle:SetWidth(SIDE_W - PAD * 2)
    explainTitle:SetWordWrap(false)

    local explainWhere = UI.Eyebrow(explain, "")
    explainWhere:SetPoint("TOPLEFT", explainTitle, "BOTTOMLEFT", 0, -5)
    explainWhere:SetWidth(SIDE_W - PAD * 2)
    explainWhere:SetWordWrap(false)

    local explainBody = UI.Label(explain, "", UI.FS.meta, C.textBody)
    explainBody:SetPoint("TOPLEFT", explain, "TOPLEFT", PAD, -(HEADER_H + 20))
    explainBody:SetWidth(SIDE_W - PAD * 2)
    explainBody:SetJustifyH("LEFT")
    explainBody:SetJustifyV("TOP")

    -- Nothing pointed at yet. A column that starts blank looks unloaded, so
    -- it says what it is for instead.
    local explainIdle = UI.Label(explain, "Point at a setting and this is where "
        .. "it says what it does.", UI.FS.meta, C.textGhost)
    explainIdle:SetPoint("TOPLEFT", explain, "TOPLEFT", PAD, -(HEADER_H + 20))
    explainIdle:SetWidth(SIDE_W - PAD * 2)
    explainIdle:SetJustifyH("LEFT")

    function self:SetExplain(title, section, body)
        explainTitle:SetText(title or "")
        explainWhere:SetText((section or ""):upper())
        explainBody:SetText(body or "")
        -- A setting with no note of its own is not a failure - most of them
        -- are named well enough not to need one. The heading still changes,
        -- so the column tracks the pointer either way.
        explainBody:SetShown(body ~= nil and body ~= "")
        explainIdle:Hide()
    end

    ---------------------------------------------------------------------
    -- Middle
    ---------------------------------------------------------------------
    local stageHost = CreateFrame("Frame", nil, frame)
    stageHost:SetPoint("TOPLEFT", rail, "TOPRIGHT", 0, 0)
    stageHost:SetPoint("BOTTOMLEFT", rail, "BOTTOMRIGHT", 0, 0)
    -- windowBg, not canvasBg. The rail and the inspector are DARKER than this
    -- in the new palette, which is the whole trick: the content is the top
    -- level of the window rather than a trench between two raised sides.
    UI.Fill(stageHost, "BACKGROUND", C.windowBg)

    -- NO LIT SURFACE ON THIS BAND, and it was tried. The run-out closed in
    -- from the RIGHT, so the open, brightest part sat at x=20 - which is
    -- exactly where the page title and its subline start. In game the title
    -- was dark red on red and could not be read at all.
    --
    -- It is the same rule this design already writes down for settings rows,
    -- and the band breaks it harder: a 20px title, a 12px subline AND two
    -- buttons all stand on these 62 pixels. There is nowhere on it that is
    -- free. The rail cap and the welcome window are where the surface earns
    -- its place - both have room above the words.

    local pageTitle = UI.Label(stageHost, "", UI.FS.title, C.text)
    pageTitle:SetPoint("TOPLEFT", stageHost, "TOPLEFT", PAD, -16)

    -- NOT FINISHED YET, SAID WHERE IT CANNOT BE MISSED. A page carrying
    -- `soon` is one whose module is built, switched off by default and not
    -- yet through a real week of play. The badge rides the title rather than
    -- the page body so it is there on every tab of that page, including the
    -- ones somebody lands on from a changelog link.
    local pageSoon = UI.Badge(stageHost, ns.L["COMING SOON"], "current")
    pageSoon:SetPoint("LEFT", pageTitle, "RIGHT", 10, 0)
    pageSoon:Hide()

    -- Width, not a second anchor: a font string given both TOPLEFT and RIGHT
    -- is told two different vertical positions and lands somewhere else.
    local pageSubtitle = UI.Label(stageHost, "", UI.FS.meta, C.textFaint)
    pageSubtitle:SetPoint("TOPLEFT", pageTitle, "BOTTOMLEFT", 0, -6)
    pageSubtitle:SetJustifyH("LEFT")
    pageSubtitle:SetWordWrap(false)

    -- THE PAGE'S OWN ACTIONS, IN THE BAND BESIDE ITS TITLE.
    --
    -- Every page names its own in the PAGES table above and this draws
    -- whichever pair the page in front of you asked for. They used to be a
    -- COLUMN OF BUTTONS INSIDE the page, beside that page's preview - so the
    -- same kind of thing lived in two different places depending on which
    -- entry in the rail you had clicked, and on the pages that had them they
    -- ate the width the preview needed.
    --
    -- TWO IS A MEASURED CEILING, not a preference. A page with a third column
    -- gets a 790 middle, 750 of it inside the padding. A 20px title takes
    -- some 190 of that, so the actions may have about 540 - and the SUBLINE
    -- has to live in what is left of the line under them, without wrapping.
    -- Four buttons at the width their own words ask for come to about 470 and
    -- leave the sentence 260, cut off mid-word. Two leave it 400.
    --
    -- A page WITHOUT a third column has the inspector's 400 as well, and
    -- that is where a third button fits: the Invites page carries its three
    -- "right now" actions up here (owner, 2026-08-16), some 400 of buttons
    -- against a middle 400 wider than the one the ceiling was measured on.
    -- The ceiling is asked per page, from the same predicate that decides
    -- the width, so the two cannot disagree.
    local ACTION_GAP = 6
    local MAX_ACTIONS = 2
    local MAX_ACTIONS_WIDE = 3

    -- A button with a mark in front of it needs room for the mark as well as
    -- for its words, and UI.ButtonWidth measures the WORDS: twelve for the
    -- glyph, four for the gap after it, four so the pair keeps its padding.
    local ICON_ROOM = 20

    local actionsByPage = {}
    for index, entry in ipairs(PAGES) do
        if entry.actions then
            local built, span = {}, 0
            local ceiling = Options.HasThirdColumn(entry) and MAX_ACTIONS
                or MAX_ACTIONS_WIDE
            for slot, spec in ipairs(entry.actions) do
                if slot > ceiling then break end

                -- CUT FOR THE WIDEST IT WILL EVER SAY, not for what it says
                -- while the window is being built. "Test mode" grows to
                -- "Test mode: on" the moment it is running, and a button
                -- measured for the short one clips the long one.
                local room = UI.ButtonWidth(spec.widest or spec.text)
                    + (spec.icon and ICON_ROOM or 0)

                local button = UI.Button(stageHost, spec.text, room,
                    spec.onClick)
                if spec.icon then button:SetIcon(spec.icon) end
                button:Hide()

                built[#built + 1] = { button = button, spec = spec }
                span = span + room + (slot > 1 and ACTION_GAP or 0)
            end

            -- Laid out from the right edge inwards, so the page reads
            -- title -> air -> first action -> second action the way it is
            -- written in the table. Only the LAST one touches the column
            -- edge; the rest hang off it, which is why re-anchoring for the
            -- close cross below is one call and not a loop.
            local previous
            for position = #built, 1, -1 do
                local button = built[position].button
                if previous then
                    button:SetPoint("TOPRIGHT", previous, "TOPLEFT",
                        -ACTION_GAP, 0)
                end
                previous = button
            end

            built.last = previous and built[#built].button or nil
            built.span = span
            actionsByPage[index] = built
        end
    end

    local body = CreateFrame("Frame", nil, stageHost)
    body:SetPoint("TOPLEFT", stageHost, "TOPLEFT", PAD, -(HEADER_H + 16))
    body:SetPoint("BOTTOMRIGHT", stageHost, "BOTTOMRIGHT", -PAD, PAD)

    -- The middle is as wide as whatever is not the two side columns. It is
    -- re-anchored per view rather than fixed, because the pages that have no
    -- spell list get the right column's space instead of leaving it blank.
    local NARROW_W = WINDOW_W - SIDEBAR_W - SIDE_W - 2
    local WIDE_W   = WINDOW_W - SIDEBAR_W - 2

    local function SetStageWidth(withSide)
        stageHost:SetWidth(withSide and NARROW_W or WIDE_W)
    end

    local listWidth = NARROW_W - PAD * 2
    local pageWidth = WIDE_W - PAD * 2




    -- THE THIRD COLUMN IS BUILT WHEN A PAGE FIRST ASKS FOR IT.
    --
    -- All five used to be built right here, the moment the window opened,
    -- whichever page you were on - and the co-tank one even with its module
    -- switched off. MEASURED, because the owner asked why this addon holds
    -- 13 MB while a whole UI replacement holds 15:
    --
    --   Options:Create                    4.6 MB
    --     OptionsBars:BuildSide           2.4 MB   796 frames
    --     OptionsCoTanks:BuildSide        1.7 MB   595 frames
    --     the other three                 0.25 MB   80 frames
    --
    -- Two panes, 1391 frames, and on a normal evening you open one of them.
    -- The PAGES have been lazy for versions - `entry.build and not
    -- entry.built` a few lines down is this same idea - the panes were just
    -- never brought over.
    --
    -- Built on first SHOW rather than on first page-visit, because that is
    -- the same question: a pane is shown by exactly one page.
    local SIDES = {
        tanks     = function() return ns.OptionsCoTanks:BuildSide(sideHost, PAD) end,
        reminders = function() return ns.OptionsReminders:BuildSide(sideHost, PAD) end,
        deaths    = function() return ns.OptionsDeaths:BuildSide(sideHost, PAD) end,
        externals = function() return ns.OptionsExternals:BuildSide(sideHost, PAD) end,
        answers   = function() return ns.OptionsAnswers:BuildSide(sideHost, PAD) end,
        casts     = function() return ns.OptionsCasts:BuildSide(sideHost, PAD) end,
        raidbar   = function() return ns.OptionsRaidBar:BuildSide(sideHost, PAD) end,
        cooldowns = function() return ns.OptionsCooldowns:BuildSide(sideHost, PAD) end,
    }
    local panes = {}

    local function Pane(key)
        local pane = panes[key]
        if not pane then
            pane = SIDES[key]()
            panes[key] = pane
        end
        return pane
    end

    -- Hiding one that was never built is not a thing that has to happen: a
    -- pane nobody has asked for is not on screen.
    local function ShowPane(key, wanted)
        if wanted then
            Pane(key):Show()
        elseif panes[key] then
            panes[key]:Hide()
        end
    end

    -- Over the middle column, and built here so it is above every page frame
    -- created below it.
    local moduleGate = BuildModuleGate(body)

    local pageFrames = {}
    for index, entry in ipairs(PAGES) do
        if entry.build then
            local page = CreateFrame("Frame", nil, body)
            page:SetAllPoints(body)
            page:Hide()
            pageFrames[index] = page
        end
    end

    self.frame = frame
    self.pageIndex = 1
    self:ApplyScale()
    self:ApplyAlpha()

    ---------------------------------------------------------------------
    -- Left column entries
    ---------------------------------------------------------------------
    local navItems = {}

    local function ShowPage(index)
        self.pageIndex = index

        local entry = PAGES[index]

        -- REMEMBERED BY KEY, NEVER BY INDEX. Owner, 2026-08-15: "das
        -- speichern des letzten offenen modules fehlt immer noch, ich lande
        -- beim oeffnen immer in den settings."
        --
        -- The key and not the number: PAGES is reordered whenever a page is
        -- added or a group is rearranged, so a stored 4 is "whichever page is
        -- fourth in the version you are running" - it would silently point
        -- somewhere else after every release, which is worse than not
        -- remembering at all because it looks like it worked.
        if ns.db and entry and entry.key then ns.db.lastPage = entry.key end
        if entry.build and not entry.built then
            entry.built = true
            entry.build(pageFrames[index], Options.PageWidth(entry, listWidth, pageWidth))
        end
        self:Refresh()
    end

    -- THE RAIL IS GROUPED, and its order is not the page list's order.
    --
    -- Seven flat entries is a list you read from the top every time, because
    -- nothing in it says where the thing you want is likely to be. Three
    -- headed groups is three places to look, and the heading answers "is what
    -- I want even in here" before any of the labels are read.
    --
    -- EDIT MODE STANDS ABOVE THE GROUPS, on its own, with no heading over it.
    --
    -- It was filed under Bars, which reads as "one of the bar pages" - and it
    -- is not a page at all. Every other entry opens something inside this
    -- window; this one CLOSES the window and puts you on the screen with your
    -- panels in your hands. That is a different kind of thing, and a heading
    -- over it would be a promise that the entries under it behave alike.
    --
    -- It is also the entry that gets used most often and it was five rows
    -- down. A door belongs at the top.
    --
    -- The rest of the rail is the NAV table at the top of this file, where the
    -- self test can read it. Only this one row is built here, because closing
    -- the window needs the window.
    local rail_entries = {
        { title = "Edit mode", glyph = "move", onClick = function()
            frame:Hide()
            ns.EditMode:SetUnlocked(true)
        end },
    }
    for _, entry in ipairs(NAV) do
        rail_entries[#rail_entries + 1] = entry
    end

    local pageByKey = {}
    for index, entry in ipairs(PAGES) do pageByKey[entry.key] = index end

    -- Measured from the HEAD's bottom edge, not the rail's top corner. The lit
    -- cap above the head has no height yet - it gets one at the end of this
    -- function, from what the loop below turns out to need - and an offset
    -- from the rail's top would have to be recomputed then.
    local y = UI.PAD
    for position, entry in ipairs(rail_entries) do
        if entry.gap then
            -- The same air a heading brings, without the words. Only between
            -- rows: leading air at the very top would push the list off its
            -- own head.
            if position > 1 then y = y + 18 end
        elseif entry.eyebrow then
            -- Air ABOVE the heading, and none under it. A heading belongs to
            -- what follows; spaced evenly it belongs to neither side.
            if position > 1 then y = y + 18 end
            local caption = UI.Eyebrow(rail, ns.L[entry.eyebrow])
            caption:SetPoint("TOPLEFT", head, "BOTTOMLEFT", UI.PAD, -y - 6)
            y = y + 20
        else
            local index = entry.page and pageByKey[entry.page]
            local pageEntry = index and PAGES[index]
            local item = UI.NavItem(rail,
                ns.L[entry.title or (pageEntry and pageEntry.title) or ""],
                entry.glyph or (pageEntry and pageEntry.glyph),
                entry.onClick or function() ShowPage(index) end)
            -- FLUSH WITH BOTH EDGES of the rail, not inset.
            --
            -- Inset by 8, the active row's fill is a floating box with a gap
            -- down its right-hand side, and the accent bar sits 8 pixels in
            -- from the column edge instead of ON it. The design runs the row
            -- from edge to edge; the padding belongs INSIDE the row, which is
            -- where the icon's own 8 already is.
            item:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -y)
            item:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, -y)
            if index then navItems[index] = item end
            y = y + UI.NAV_ITEM_H
        end
    end

    -- WHAT THE LIST ACTUALLY NEEDS, checked rather than hoped for. `y` is the
    -- nav's real height, counted as it was built. There is no artwork to take
    -- the room from any more, but the sum still has to hold: rail less head
    -- less foot less the Discord row is what the entries may use, and going
    -- over it does not clip - it pushes the last entry behind the foot. That
    -- is not hypothetical. It happened while this column was being designed,
    -- and the one that vanished was Changelog.
    -- The sum itself is UI.RailFits, and it is checked by the self test
    -- against the real page count rather than here - a rail that does not fit
    -- is a mistake made while editing this file, not a state a player can get
    -- into, so it belongs in the checks and not in everybody's login.

    ---------------------------------------------------------------------
    -- Painting
    ---------------------------------------------------------------------
    local function PaintView()
        local entry = PAGES[self.pageIndex] or PAGES[1]

        -- IS THE FEATURE THIS PAGE BELONGS TO RUNNING AT ALL. Asked before
        -- anything else, because the answer decides how much of the window
        -- this page gets to use.
        local moduleOn = not entry.module or ns.Modules:IsOn(entry.module)
        moduleGate:Update(not moduleOn and entry.module or nil)

        local withExplain = entry.explain and true or false
        local withTanks = entry.tanks and moduleOn or false
        local withReminders = entry.reminders and moduleOn or false
        local withDeaths = entry.deaths and moduleOn or false
        local withExternals = entry.externals and moduleOn or false
        local withRaidBar = entry.raidbar and moduleOn or false
        local withAnswers = entry.answers and moduleOn or false
        local withCasts = entry.casts and moduleOn or false

        -- The middle column narrows for any of them: the third column is
        -- there or it is not, and what is IN it is a separate question.
        --
        -- A switched-off module has no third column. Greying the page but
        -- leaving its spell palette live beside it would be half a state, and
        -- the half that is still live is the half that edits settings for
        -- something that is not running.
        local third = withExplain or withTanks or withReminders
            or withDeaths or withExternals or withRaidBar or withAnswers
            or withCasts
        SetStageWidth(third)
        sideHost:SetShown(third)
        explain:SetShown(withExplain)
        ShowPane("tanks", withTanks)
        ShowPane("reminders", withReminders)
        ShowPane("deaths", withDeaths)
        ShowPane("externals", withExternals)
        ShowPane("raidbar", withRaidBar)
        ShowPane("answers", withAnswers)
        ShowPane("casts", withCasts)
        if withTanks then ns.OptionsCoTanks:Refresh() end
        if withReminders then ns.OptionsReminders:Refresh() end
        if withDeaths then ns.OptionsDeaths:Refresh() end
        if withExternals then panes.externals.Refresh() end
        if withRaidBar then panes.raidbar.Refresh() end
        if withAnswers then panes.answers.Refresh() end
        if withCasts then panes.casts.Refresh() end

        -- THROUGH L, and the fallback is what makes this free: a page whose
        -- title has no translation gets its own English word back, which is
        -- the string that was there before this line existed.
        pageTitle:SetText(ns.L[entry.title])
        pageSubtitle:SetText(entry.subtitle and ns.L[entry.subtitle] or nil)
        -- READ OFF THE ENTRY, never off the page index: the badge belongs to
        -- whichever page declared it, so retiring the mark is deleting one
        -- word in the table above and nothing else.
        pageSoon:SetShown(ns.Options.ComingSoon(entry))

        -- WHATEVER THE LAST PAGE PUT IN THE BAND COMES OUT OF IT. Every
        -- page's pair is walked, not only this one's: the band is one strip
        -- of window shared by eleven pages, and a button left showing is a
        -- button that acts on the page you just left.
        --
        -- A switched-off module takes its actions with it. "Move bars" over a
        -- page that is greyed out is an offer to go and arrange nothing.
        for pageIndex, built in pairs(actionsByPage) do
            local mine = pageIndex == self.pageIndex and moduleOn
            for _, item in ipairs(built) do
                item.button:SetShown(mine)

                -- A LABEL THAT REPORTS A STATE IS RE-READ HERE. "Test mode"
                -- says "Test mode: on" while it is running, and what changed
                -- is the state, not which page you are standing on - so it
                -- cannot be set once when the button is made.
                if mine and item.spec.label then
                    item.button:SetText(item.spec.label())
                end
            end
        end

        -- WHERE THE LAST ACTION STOPS, and it is not the same edge on every
        -- page. With a third column the close cross is 400 pixels away over
        -- that column and the buttons may have the whole middle; without one
        -- the middle runs to the window's edge and the cross is standing in
        -- the last button's label.
        --
        -- Set on every repaint rather than at build time: whether a page has
        -- its third column is not fixed - switching its module off takes the
        -- column away and hands the middle those 400 pixels.
        local crossRoom = third and 0 or CLOSE_ROOM
        local mineActions = moduleOn and actionsByPage[self.pageIndex]
        if mineActions and mineActions.last then
            mineActions.last:ClearAllPoints()
            mineActions.last:SetPoint("TOPRIGHT", stageHost, "TOPRIGHT",
                -(PAD + crossRoom), -18)
        end

        -- The subtitle stops at the buttons rather than at the column edge,
        -- or a long one runs underneath them.
        local room = (third and NARROW_W or WIDE_W) - PAD * 2
        if mineActions then
            room = room - (mineActions.span + crossRoom + UI.PAD)
        end
        pageSubtitle:SetWidth(room)

        for index, page in pairs(pageFrames) do
            page:SetShown(index == self.pageIndex)
        end

        -- Every row, not just this one: switching a module changes a row that
        -- is not the row you are standing on.
        for index, item in ipairs(navItems) do
            local rowEntry = PAGES[index]
            local rowModule = rowEntry and rowEntry.module
            item:SetModuleState(rowModule ~= nil,
                rowModule ~= nil and ns.Modules:IsOn(rowModule))
            item:SetActive(index == self.pageIndex)
        end

        do
            local page = pageFrames[self.pageIndex]
            if page and page.Refresh then page.Refresh() end
        end
    end

    self.PaintView = PaintView
    self.ShowPage = ShowPage

    SetStageWidth(true)

    -- THROUGH THE SAME DOOR AS EVERY OTHER PAGE, and this line is a bug fix.
    --
    -- It used to be a bare self:Refresh(), which PAINTS the window and shows
    -- page one - and never runs its builder, because building happens in
    -- ShowPage and nothing had called it yet. That was harmless for exactly
    -- as long as page one was the Cooldowns page: that page had NO builder at
    -- all, it was drawn entirely by the frame, its status line and its two
    -- action buttons.
    --
    -- The bars went and Settings moved up into the first slot. Settings has a
    -- builder. So the window opened on a page that had never been built - an
    -- empty stage with its rail row lit - and clicking any other row and back
    -- filled it in, because THAT goes through ShowPage. Owner, 2026-08-15:
    -- "immer wenn ich das addon oeffne, lande ich auf einer leeren settings
    -- seite, erst beim hin und her klicken wird der inhalt geladen."
    --
    -- The desk could not see it: the harness walks ShowPage over every page
    -- deliberately, so out here page one was always built a moment later.
    -- WHERE THE WINDOW OPENS.
    --
    -- Cooldowns on the very first open - owner, 2026-08-15: "bitte cooldowns
    -- als standard open fenster einstellen wenn das erste mal geoeffnet wird
    -- ansonsten bitte last modul merken" - and after that wherever he was.
    --
    -- FALLS BACK TWICE, and both fallbacks matter: a remembered page whose
    -- MODULE has since been switched off is a page the rail no longer shows,
    -- and opening onto it would be a blank window with nothing selected.
    self.pageIndex = Options.Landing(PAGES, ns.db and ns.db.lastPage)
    ShowPage(self.pageIndex)

    table.insert(UISpecialFrames, "ZwoelfStuffOptionsFrame")   -- close with ESC
end

function Options:Refresh()
    if not self.frame then return end
    if self.PaintView then self.PaintView() end
end

-- Called by CDM when the Cooldown Manager's contents change: the spell list
-- is a view of it, so it must not go stale while it is open.
function Options:OnCatalogChanged()
    if self.frame and self.frame:IsShown() then
        self:Refresh()
    end
end

-- Opens on a named page. Separate from Toggle on purpose: something that
-- WANTS the window open must not close it because it happened to be open
-- already, which is exactly what "Bar options" in the unlock overlay did.
function Options:Open(pageKey)
    self:Create()

    if pageKey and self.ShowPage then
        for index, entry in ipairs(PAGES) do
            if entry.key == pageKey then
                self.ShowPage(index)
                break
            end
        end
    end

    self:Refresh()
    self.frame:Show()
end

function Options:Toggle()
    self:Create()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Open()
    end
end
