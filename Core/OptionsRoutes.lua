---------------------------------------------------------------------------
-- OptionsRoutes - the M+ routes page.
--
-- No preview card, and that is deliberate. What this feature draws is a badge
-- over a nameplate in a dungeon; a card showing a badge over nothing would be
-- a picture of a coloured square. What it CAN show honestly is the state:
-- which route MDT is holding, which pull you are on, and what the mobs in
-- front of you resolved to. That is the same thing /zs route prints, off the
-- same functions.
---------------------------------------------------------------------------
local _, ns = ...

local OptionsRoutes = {}
ns.OptionsRoutes = OptionsRoutes

local UI = ns.UI
local C = UI.C
local Routes = ns.Routes

local function DB() return ns.db.routes end

local function Apply()
    ns.Routes:Sweep()
    OptionsRoutes:Refresh()
end

function OptionsRoutes:BuildPage(page, width)
    local grid = UI.Page(page, width)

    grid:Note("The pull you are on, badged onto the mobs themselves, in the "
        .. "colour that pull already has in Mythic Dungeon Tools. Plan the "
        .. "route in MDT as you always do; this reads it.")

    ---------------------------------------------------------------------
    -- What MDT is holding right now. The first thing anybody needs, because
    -- every "it does nothing" on this page is one of three states and they
    -- look identical on screen.
    ---------------------------------------------------------------------
    local status = UI.Card(grid.content, width)
    status:SetHeight(92)

    local caption = UI.Eyebrow(status, "Right now")
    caption:SetPoint("TOPLEFT", status, "TOPLEFT", 14, -12)

    local headline = UI.Label(status, "", UI.FS.card, C.text)
    headline:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 0, -8)
    headline:SetWidth(width - 28)
    headline:SetJustifyH("LEFT")
    headline:SetWordWrap(false)

    local detail = UI.Label(status, "", UI.FS.meta, C.textFaint)
    detail:SetPoint("TOPLEFT", headline, "BOTTOMLEFT", 0, -6)
    detail:SetWidth(width - 28)
    detail:SetJustifyH("LEFT")

    grid:Wide(status, 92, 4, 12)

    ---------------------------------------------------------------------
    local stepRow = CreateFrame("Frame", nil, grid.content)
    stepRow:SetHeight(28)

    local back = UI.Button(stepRow, "Previous pull", 132, function()
        Routes:Step(-1)
        OptionsRoutes:Refresh()
    end, "quiet")
    back:SetPoint("LEFT", stepRow, "LEFT", 0, 0)

    local forward = UI.Button(stepRow, "Next pull", 110, function()
        Routes:Step(1)
        OptionsRoutes:Refresh()
    end)
    forward:SetPoint("LEFT", back, "RIGHT", 8, 0)

    local reread = UI.Button(stepRow, "Re-read route", 130, function()
        Routes:Sync()
        Routes:ResetRun()
        OptionsRoutes:Refresh()
    end, "quiet")
    reread:SetPoint("LEFT", forward, "RIGHT", 8, 0)

    grid:Wide(stepRow, 28, 0, 14)

    ---------------------------------------------------------------------
    -- TEST. "Nothing is marked" is two questions wearing one face: is the
    -- badge being drawn at all, and did the route match anything standing in
    -- front of you. This answers the first on its own - every nameplate gets
    -- a badge, route or no route - so the second is the only one left.
    ---------------------------------------------------------------------
    local testRow = CreateFrame("Frame", nil, grid.content)
    testRow:SetHeight(28)

    local test
    test = UI.Button(testRow, "Test the badges", 150, function()
        Routes:SetTesting(not Routes.testing)
        OptionsRoutes:Refresh()
    end)
    test:SetPoint("LEFT", testRow, "LEFT", 0, 0)

    local testNote = UI.Label(testRow,
        "Badges every nameplate on screen, ignoring the route.",
        UI.FS.meta, C.textFaint)
    testNote:SetPoint("LEFT", test, "RIGHT", 10, 0)

    grid:Wide(testRow, 28, 0, 14)

    ---------------------------------------------------------------------
    grid:Section("The badges")

    local function Switch(label, key, sublabel)
        return UI.Toggle(grid:FullRow(label,
            { controlWidth = 124, sublabel = sublabel }),
            function() return DB()[key] end,
            function(value) DB()[key] = value; Apply() end)
    end

    Switch("Show them", "enabled",
        "Off until you ask - this draws over every nameplate in a dungeon")
    Switch("Mark the next pull too", "showNext",
        "Dimmed, so it reads as a hint rather than a second job")
    Switch("Number inside the badge", "showNumber")
    Switch("Step on by itself", "autoAdvance",
        "In a key, off the game's own forces counter - it needs no mob ids "
        .. "and it counts what your team kills out of sight. Elsewhere, off "
        .. "the mobs of the pull dying")

    UI.Slider(grid:FullRow("Enough of a pull", { controlWidth = 124,
        sublabel = "How much of its forces has to be down before it steps on. "
            .. "Never all of it - a stray that ran off would mean never "
            .. "advancing" }), {
        get = function() return DB().forcesThreshold end,
        set = function(value) DB().forcesThreshold = value end,
        min = 0.5, max = 1, step = 0.05, scale = 100,
        format = function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end,
    })

    UI.Slider(grid:FullRow("Size", { controlWidth = 124 }), {
        get = function() return DB().size end,
        set = function(value) DB().size = value end,
        min = 12, max = 64, step = 1, apply = Apply,
    })
    UI.Slider(grid:FullRow("Strength", { controlWidth = 124 }), {
        get = function() return DB().alpha end,
        set = function(value) DB().alpha = value end,
        min = 0.2, max = 1, step = 0.05, apply = Apply, scale = 100,
        format = function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end,
    })
    UI.Slider(grid:FullRow("Next pull at", { controlWidth = 124 }), {
        get = function() return DB().nextAlpha end,
        set = function(value) DB().nextAlpha = value end,
        min = 0.1, max = 1, step = 0.05, apply = Apply, scale = 100,
        format = function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end,
    })
    UI.Slider(grid:FullRow("Nudge across", { controlWidth = 124 }), {
        get = function() return DB().offsetX end,
        set = function(value) DB().offsetX = value end,
        min = -60, max = 60, step = 1, apply = Apply,
    })
    UI.Slider(grid:FullRow("Nudge up", { controlWidth = 124 }), {
        get = function() return DB().offsetY end,
        set = function(value) DB().offsetY = value end,
        min = -60, max = 80, step = 1, apply = Apply,
    })

    ---------------------------------------------------------------------
    -- THE LIMIT, ON THE PAGE. Said here rather than discovered in a key:
    -- MDT plans per clone and the game only tells us what KIND a mob is.
    ---------------------------------------------------------------------
    grid:Section("What it can and cannot know")
    grid:Note("A badge marks a mob TYPE, not one particular mob. MDT plans "
        .. "per pack - \"these two of the four over there\" - and the game "
        .. "only tells an addon what kind a mob is, never where it stands. So "
        .. "if a pull takes two of four identical mobs, all four wear the "
        .. "badge and the count tells you how many to take.")
    grid:Note("Nothing here writes to a nameplate. The badge is our own frame "
        .. "hung above it, so other nameplate addons have nothing to fight "
        .. "with.")
    grid:Note("A mob is identified by the id inside its GUID. In a dungeon "
        .. "this client often will not let an addon look at that, so the "
        .. "mob's NAME is used instead - MDT stores one for every enemy. It "
        .. "is the weaker of the two: where two different mobs share a name, "
        .. "only one of them can win. Run /zs route to see which way each "
        .. "nameplate was found.")

    local function Paint()
        test:SetText(Routes.testing and "Stop testing" or "Test the badges")

        local why = Routes:UnavailableReason()
        if why then
            headline:SetText("|cffff8040No route.|r")
            detail:SetText(why:sub(1, 1):upper() .. why:sub(2) .. ".")
        else
            local pull = Routes:Current()
            headline:SetText(string.format("Pull |cffffd100%d|r of %d  "
                .. "|cff888888%s|r", Routes.index, Routes:Count(),
                Routes.presetName or ""))

            local parts = {}
            if pull then
                for npcID, want in pairs(pull.npcs) do
                    parts[#parts + 1] = string.format("%s x%d",
                        pull.names[npcID] or ("npc " .. npcID), want)
                end
            end
            table.sort(parts)

            -- WHICH DUNGEON, AND WHO DECIDED IT. Said on the panel because a
            -- route read for the wrong dungeon looks exactly like a working
            -- one right up until nothing gets marked.
            local place = Routes:DungeonName() or "?"
            if Routes.dungeonFrom ~= "zone" then
                place = place .. " |cffff8040(MDT's window, not where you "
                    .. "are standing)|r"
            end
            detail:SetText(place .. "  |cff888888-|r  "
                .. (#parts > 0 and table.concat(parts, ", ")
                    or "this pull is empty in MDT"))
        end
        back:SetEnabled(Routes:Count() > 0)
        forward:SetEnabled(Routes:Count() > 0)
    end

    grid:Layout()
    self.Paint = Paint
    page.Refresh = function() OptionsRoutes:Refresh() end
    -- Test mode draws over every nameplate in the world. It does not outlive
    -- the page it was switched on from - closing the window is the same as
    -- switching it off, which is the behaviour anybody would assume.
    page:SetScript("OnHide", function() Routes:SetTesting(false) end)
    self.grid = grid
    Paint()
    grid:Layout()
    return grid
end

function OptionsRoutes:Refresh()
    -- Re-read before painting: MDT is a live thing on the other monitor and
    -- the route can change while this page is open.
    Routes:Sync()
    if self.Paint then self.Paint() end
    if self.grid then self.grid:Refresh() end
end
