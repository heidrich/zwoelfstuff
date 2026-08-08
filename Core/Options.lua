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
local WINDOW_W, WINDOW_H = 1360, 760
local SIDEBAR_W = 168
local SIDE_W    = 400
local PAD       = 20

-- Shared with Widgets, so the rule under the brand, the rule under the page
-- title and the rule under the right column's heading are the same line.
local HEADER_H  = UI.HEADER_H

---------------------------------------------------------------------------
-- Shared page helpers
---------------------------------------------------------------------------

-- A strip of buttons that flows like any other block in the grid.
local function ButtonStrip(grid, buttons)
    local strip = CreateFrame("Frame", nil, grid.content)
    strip:SetSize(grid.width, 28)

    local x = 0
    for _, spec in ipairs(buttons) do
        local btn = UI.Button(strip, spec.text, spec.width or 120, spec.onClick, spec.style)
        btn:SetPoint("LEFT", strip, "LEFT", x, 0)
        x = x + (spec.width or 120) + 8
        spec.frame = btn
    end

    grid:Wide(strip, 36)
    return strip
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local function BuildGeneralPage(page, width)
    local grid = UI.Page(page, width, { explain = true })

    grid:Section("Text")

    -- Two fonts, two jobs. Panel text is read in rows in a window; bar text is
    -- read at a glance over a moving scene. The design draws the window in a
    -- narrow grotesk, and the client's own face is not one.
    UI.MediaPicker(grid:FullRow("Panel font", { controlWidth = 220 }), "font",
        function() return ns.db.panelFont or ns.Media.PanelFont() end,
        function(value) ns.db.panelFont = value end,
        function() ns.Print("Panel font set. |cffffd100/reload|r to redraw the window in it.") end)

    grid:Note("The window you are looking at - its labels, values and headings. "
        .. "It is a separate setting from the bars on purpose: a face that is "
        .. "right over a moving 3D scene is rarely the one that is right for "
        .. "forty rows of settings. The list is whatever your other addons have "
        .. "registered.")

    UI.MediaPicker(grid:FullRow("Bar text", { controlWidth = 220 }), "font",
        function() return ns.db.font end,
        function(value) ns.db.font = value end,
        function() ns.Screen:Render() end)

    grid:Note("Every piece of text on every bar, unless that one piece has "
        .. "been given its own font in the bar's own settings. The list is "
        .. "whatever your other addons have registered - so a font you "
        .. "installed for ElvUI or WeakAuras is already in it.")

    grid:Section("Blizzard's Cooldown Manager")

    UI.Toggle(grid:Row("Take the display over",
        { sublabel = "Hide the cooldowns you have not placed on a bar" }),
        function() return ns.db.takeOverCDM ~= false end,
        function(value)
            ns.db.takeOverCDM = value and true or false
            if not value then ns.Screen:ReleaseAll() end
            ns.Screen:Render()
        end)

    grid:Note("Every icon on your bars IS one of Blizzard's - it owns the timing, "
        .. "the charges and the stacks, and on this patch no addon may read those "
        .. "for itself. Moving one onto your bar leaves a hole in Blizzard's own "
        .. "row, because its layout does not know the icon left. With this off you "
        .. "get that row back, holes included.")

    grid:Section("Minimap button")
    UI.Toggle(grid:Row("Show the button"),
        function() return ns.db.minimap.show end,
        function(value) ns.MinimapButton:SetShown(value) end)
    UI.Toggle(grid:Row("Lock its position"),
        function() return ns.db.minimap.locked end,
        function(value) ns.db.minimap.locked = value end)

    grid:Note("Left click opens this window, right click moves the bars, and "
        .. "drag moves the button around the minimap edge.")

    grid:Section("Game menu")
    UI.Toggle(grid:Row("Show in the game menu"),
        function() return ns.db.gameMenu ~= false end,
        function(value) ns.GameMenu:SetShown(value) end)

    grid:Note("An entry under the last of Blizzard's own, where you look for "
        .. "an addon when you have forgotten what its slash command was. It "
        .. "stands down while you are in combat: pressing it closes the pause "
        .. "menu, and the game does not let an addon do that mid-fight.")

    ---------------------------------------------------------------------
    -- Another character's layout
    --
    -- The other half of settings being per character. Without this, every
    -- alt starts from an empty screen and nobody builds the same interface
    -- twice - which is why the owner asked for it in the same breath as the
    -- per-character rule itself.
    ---------------------------------------------------------------------
    -- A FUNCTION, not a table: another character's profile appears the moment
    -- they log out, and a list built once at login would never show them.
    -- UI.Dropdown takes either.
    local function OtherCharacters()
        local out = {}
        for _, entry in ipairs(ns.OtherProfiles()) do
            out[#out + 1] = {
                value = entry.key,
                text = string.format("%s  |cff888888%d %s|r", entry.key,
                    entry.bars, entry.bars == 1 and "bar" or "bars"),
            }
        end
        if #out == 0 then
            out[1] = { value = false, text = "|cff888888No other character yet|r" }
        end
        return out
    end

    local copyRow = grid:FullRow("Take a layout from", { controlWidth = 190 })
    UI.Dropdown(copyRow, OtherCharacters, function() return nil end,
        function(value)
            if not value then return end
            local ok, result = ns.Bars:CopyLayoutFrom(value)
            if ok then
                ns.Print(string.format("Copied %d bar%s from |cffffd100%s|r. "
                    .. "The cells are empty - a spell belongs to the character "
                    .. "that can cast it.",
                    result, result == 1 and "" or "s", value))
            else
                ns.Print("|cffff4040Nothing copied|r - " .. tostring(result) .. ".")
            end
        end, { emptyText = "Pick a character" })

    grid:Note("Everything you built comes across - the bars, their "
        .. "arrangements, sizes, looks, rules and positions - and every cell "
        .. "arrives EMPTY. The spells stay behind on purpose: a Death Knight's "
        .. "cooldowns are not castable on a Paladin, and copying them is the "
        .. "bug this whole split exists to prevent. This replaces the bars you "
        .. "have here.")

    grid:Section("Everything")

    local resetArmed = false
    local resetStrip
    resetStrip = ButtonStrip(grid, {
        {
            text = "Reset all settings", width = 160, style = "primary",
            onClick = function()
                -- Two-step, because this throws away every bar, position and
                -- colour the user has set.
                if not resetArmed then
                    resetArmed = true
                    resetStrip.reset:SetText("Really reset? Click again")
                    C_Timer.NewTimer(4, function()
                        resetArmed = false
                        if resetStrip.reset then resetStrip.reset:SetText("Reset all settings") end
                    end)
                    return
                end
                resetArmed = false
                resetStrip.reset:SetText("Reset all settings")
                SlashCmdList.ZWOELFSTUFF("reset")
            end,
        },
    })
    resetStrip.reset = select(1, resetStrip:GetChildren())

    grid:Note("Restores every default: your bars, your presets and the minimap "
        .. "button. Recorded procs are kept - those are measurements, and they "
        .. "cannot be typed back in. There is no undo for the rest.")

    grid:Layout()
    page.Refresh = function() grid:Refresh() end
end

---------------------------------------------------------------------------
-- Diagnostics
---------------------------------------------------------------------------
local function BuildDiagnosticsPage(page, width)
    local grid = UI.Page(page, width)

    grid:Section("Cooldown Manager")
    grid:Note("Everything on your bars comes from Blizzard's Cooldown Manager - it "
        .. "already knows the spells, binds the auras and has the timing, none of "
        .. "which an addon can do for itself on this patch.")

    ButtonStrip(grid, {
        { text = "What it holds", width = 150, style = "primary", onClick = function()
            ns.CDM:Dump()
        end },
    })

    grid:Section("Auras")
    grid:Note("Procs are recorded while you play, per class and spec, and their "
        .. "duration is measured rather than assumed. Output goes to your chat frame.")

    ButtonStrip(grid, {
        { text = "What was seen", width = 150, style = "primary", onClick = function()
            ns.Auras:Dump()
        end },
        { text = "Export this spec", width = 150, onClick = function()
            ns.Auras:Export()
        end },
    })

    -- Custom active states ---------------------------------------------------
    --
    -- The spells offered are the ones ON YOUR BARS, because that is the only
    -- set where declaring a window changes anything you can see. A list of
    -- every spell in the game would be a longer list and a worse one.
    grid:Section("Active for")
    grid:Note("Some things the Cooldown Manager only shows as a cooldown - a "
        .. "trinket's use effect, a potion, a racial. It knows when they come "
        .. "back, and nothing about how long they LAST, so the one number that "
        .. "matters is on screen nowhere. Say how long it lasts and the cell "
        .. "runs that window every time you press it.")

    local activeSpell

    local function BarSpells()
        local out, seen = {}, {}
        for _, cfg in ipairs((ns.db and ns.db.bars) or {}) do
            for _, spellID in pairs(cfg.cells or {}) do
                if spellID and not seen[spellID] then
                    seen[spellID] = true
                    local seconds = ns.Auras:ActiveStates()[spellID]
                    out[#out + 1] = {
                        value = spellID,
                        text = (ns.SpellName(spellID) or ("Spell " .. spellID))
                            .. (seconds and ("  |cff7ec6d4" .. seconds .. "s|r") or ""),
                        name = ns.SpellName(spellID) or "",
                    }
                end
            end
        end
        table.sort(out, function(a, b) return a.name < b.name end)
        return out
    end

    UI.Dropdown(grid:FullRow("Spell", { controlWidth = 260 }), BarSpells,
        function() return activeSpell end,
        function(value) activeSpell = value end,
        { emptyText = "Pick a spell from your bars" })

    UI.Slider(grid:FullRow("Lasts", { controlWidth = 200 }), {
        get = function()
            if not activeSpell then return 0 end
            return ns.Auras:ActiveStates()[activeSpell] or 0
        end,
        set = function(value)
            if activeSpell then ns.Auras:SetActiveState(activeSpell, value) end
        end,
        min = 0, max = 120, step = 1,
        format = function(v)
            if (v or 0) < 1 then return "off" end
            return string.format("%ds", v)
        end,
        apply = function() ns.Options:Refresh() end,
    })

    grid:Note("Zero switches it off. This is remembered for the whole account, "
        .. "not this character: how long a trinket lasts is a fact about the "
        .. "trinket. A spell the Cooldown Manager already tracks as a buff is "
        .. "left alone - its own clock is better than a number you typed.")

    grid:Section("This client")

    local rivalRow = grid:FullRow("Another addon holding the same frames",
        { controlWidth = 300 })
    local rivalState = UI.Label(rivalRow.slot, "", 12, C.text)
    rivalState:SetPoint("RIGHT", rivalRow.slot, "RIGHT", 0, 0)
    rivalState:SetJustifyH("RIGHT")

    local cdmRow = grid:FullRow("Cooldown Manager", { controlWidth = 260 })
    local cdmState = UI.Label(cdmRow.slot, "", 12, C.text)
    cdmState:SetPoint("RIGHT", cdmRow.slot, "RIGHT", 0, 0)
    cdmState:SetJustifyH("RIGHT")

    local engineRow = grid:FullRow("Aura engine (12.1)", { controlWidth = 260 })
    local engineState = UI.Label(engineRow.slot, "", 12, C.text)
    engineState:SetPoint("RIGHT", engineRow.slot, "RIGHT", 0, 0)
    engineState:SetJustifyH("RIGHT")

    grid:Note("There is ONE set of Cooldown Manager item frames, and every addon that "
        .. "does cooldowns on this patch works by adopting them. Two addons adopting "
        .. "the same frame both re-assert their own anchor, so the icons end up split "
        .. "between two layouts - which looks like a bug in whichever one you are "
        .. "looking at. Run one or the other.")

    grid:Note("Patch 12.0 made aura data secret, so an addon cannot identify a buff by "
        .. "ID, name or icon. The sanctioned replacement, Blizzard_AuraContainer, only "
        .. "arrives in 12.1 - until then the Cooldown Manager is the one usable source, "
        .. "which is what this addon is built on.")

    grid:Layout()

    page.Refresh = function()
        local rival = ns.CDM:RivalName()
        rivalState:SetText(rival and ("|cffff4040" .. rival .. "|r")
            or "|cff40ff40none found|r")

        cdmState:SetText(ns.CDM:IsAvailable()
            and "|cff40ff40available|r"
            or ("|cffff4040" .. (ns.CDM:UnavailableReason() or "unavailable") .. "|r"))

        -- Engine.lua is parked on a 12.0 client, so ns.Engine is nil here.
        -- Reading it without the guard is a crash, not a missing feature.
        if not ns.Engine then
            engineState:SetText("|cff888888not on this client - parked until 12.1|r")
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
local function BuildAboutPage(page, width)
    local scroll, content = UI.ScrollArea(page, width - 14)

    local author = UI.Label(content, "Zwolf  -  EU Destromath", 15, C.accent)
    author:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)

    local version = UI.Label(content, "Version " .. ns.version, 12, C.textDim)
    version:SetPoint("TOPLEFT", author, "BOTTOMLEFT", 0, -6)

    local body = UI.Label(content, table.concat({
        "Blizzard's Cooldown Manager can only show spells that exist in its own",
        "C_CooldownViewer data set. Boiling Point (1265968) is not in that set, so it",
        "cannot be added there by hand - and no Cooldown Manager addon can add it",
        "either, because their spell pickers read the exact same list.",
        "",
        "Since patch 12.0 aura data is 'secret'. Measured on this character, in combat,",
        "with the buff up: 0 readable, 18 secret. Not just Boiling Point - every buff.",
        "So an addon cannot identify an aura at all, by ID, by name or by icon.",
        "",
        "Blizzard's answer is Blizzard_AuraContainer: an addon declares what it wants to",
        "see and hands over the widgets, and the engine binds the aura, shows the button",
        "only while it is up, and drives icon, duration, bar and stacks itself. That",
        "frame type arrives in patch 12.1 - this client is 12.0.7, so it is not here yet.",
        "",
        "What is also readable is a proc: Boiling Point empowers Blood Boil, and",
        "IsSpellOverlayed(50842) is a plain boolean that never touches aura data. That",
        "is the fallback route, timed off our own clock.",
        "",
        "If no countdown number appears anywhere, enable it globally:",
        "  /console countdownForCooldowns 1",
        "",
        "Commands",
        "  /zs                    open this window",
        "  /zs unlock | lock      move the bars around the screen",
        "  /zs bars               list your bars   |   add <name>   |   remove <n>",
        "  /zs cdm                what Blizzard's Cooldown Manager currently holds",
        "  /zs auras              the procs seen on this spec, and what drives them",
        "  /zs auras export       hand this spec's set back so it ships with the addon",
        "  /zs auras icon <glowID> <spellID>    which icon a proc shows",
        "  /zs auras bind <glowID> <auraID>     name the buff itself (12.1 route)",
        "  /zs auras forget <glowID>            drop a recording",
        "  /zs text               where each number and name actually ended up",
        "  /zs minimap            show or hide the minimap button",
        "  /zs reset              restore defaults, keeping recorded procs",
    }, "\n"), 12, C.text)
    body:SetPoint("TOPLEFT", version, "BOTTOMLEFT", 0, -18)
    body:SetJustifyV("TOP")
    body:SetWidth(width - 30)

    content:SetHeight(body:GetStringHeight() + 90)
    if scroll.Update then scroll.Update() end
end

---------------------------------------------------------------------------
-- Changelog
---------------------------------------------------------------------------
local function BuildChangelogPage(page, width)
    local textWidth = width - 20
    local scroll, content = UI.ScrollArea(page, textWidth)

    local y = 0
    for _, entry in ipairs(ns.CHANGELOG) do
        local heading = UI.Label(content, "v" .. entry.version, 14, C.accent)
        heading:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)

        local date = UI.Label(content, entry.date, 11, C.textFaint)
        date:SetPoint("LEFT", heading, "RIGHT", 10, -1)
        y = y - 24

        for _, line in ipairs(entry.lines) do
            local dot = UI.Label(content, "-", 12, C.textFaint)
            dot:SetPoint("TOPLEFT", content, "TOPLEFT", 2, y)

            local bullet = UI.Label(content, line, 12, C.text)
            bullet:SetPoint("TOPLEFT", content, "TOPLEFT", 14, y)
            bullet:SetWidth(textWidth - 14)
            bullet:SetJustifyV("TOP")
            -- Width is set, so GetStringHeight reports the wrapped height.
            y = y - (bullet:GetStringHeight() + 6)
        end
        y = y - 14
    end

    content:SetHeight(math.max(1, -y))
    if scroll.Update then scroll.Update() end
end

---------------------------------------------------------------------------
-- The functions in the left column
--
-- "cooldowns" is the addon; the rest are secondary and look it. Only the
-- first one uses the right column, which is why it carries the flag rather
-- than the shell hardcoding an index.
---------------------------------------------------------------------------
local PAGES = {
    -- No subtitle text of its own: this page's second line is a STATUS, not
    -- an instruction. "Your bars, in the order you built them" is true on the
    -- first visit and noise on every one after it, whereas how many cells are
    -- still empty is the one thing worth knowing at a glance.
    { key = "cooldowns", title = "Cooldowns", glyph = "grid", side = true,
      status = true },

    { key = "settings", title = "Settings", glyph = "sliders",
      subtitle = "Applies to every bar.",
      explain = true, build = BuildGeneralPage },

    -- The one page that is about somebody ELSE. It carries its own right-hand
    -- column - not the bar inspector and not the explain panel - because what
    -- belongs beside a co-tank preview is the co-tank settings and nothing in
    -- the other two is about this page at all.
    { key = "cotanks", title = "Co-Tanks", glyph = "tanks", tanks = true,
      subtitle = "Every tank in the group, with their health and their auras.",
      -- Through the namespace, not a local: the builder lives in
      -- Core/OptionsCoTanks.lua, which loads BEFORE this file but after this
      -- table would have captured a local upvalue that was still nil.
      build = function(page, width) return ns.OptionsCoTanks:BuildPage(page, width) end },

    -- The other page about the fight rather than about the bars. It carries
    -- the SPELL LIST as its third column - the same list the bars page uses -
    -- because the whole gesture is dragging a spell onto the reminder.
    { key = "reminders", title = "Reminders", glyph = "bell", reminders = true,
      subtitle = "Text on your screen when a buff has fallen off.",
      build = function(page, width) return ns.OptionsReminders:BuildPage(page, width) end },

    -- The third page about the fight. No third column: what it shows is the
    -- state of a route, and there is no list to pick from.
    -- NOT "M+". Nothing in this feature is gated on a keystone - the mobs in
    -- a normal dungeon are the same mobs with the same npcIDs, so a route
    -- marks them just as well on any difficulty, and in a raid MDT has data
    -- for. The owner's point, and the code already agreed with it.
    { key = "routes", title = "Routes", glyph = "place-dungeon",
      subtitle = "Your MDT pull, badged onto the mobs themselves.",
      build = function(page, width) return ns.OptionsRoutes:BuildPage(page, width) end },

    { key = "diagnostics", title = "Diagnostics", glyph = "pulse",
      subtitle = "What the Cooldown Manager holds, and what the client refuses to show.",
      build = BuildDiagnosticsPage },

    { key = "about", title = "About", glyph = "info",
      subtitle = "Why this addon exists, and every command.",
      build = BuildAboutPage },

    { key = "changelog", title = "Changelog", glyph = "log",
      subtitle = "What changed, and why.",
      build = BuildChangelogPage },
}

-- The three pages that carry a THIRD COLUMN, published so the rule below can
-- be checked without building a window.
Options.PAGES = PAGES

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
function Options.HasThirdColumn(entry)
    return (entry.side or entry.explain or entry.tanks or entry.reminders)
        and true or false
end

function Options.PageWidth(entry, narrow, wide)
    if Options.HasThirdColumn(entry) then return narrow end
    return wide
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

    -- The rail head, on the same 62 as every other column's header band.
    --
    -- The mark is the addon's own icon, at 26. The wordmark is lower case and
    -- carries the split in COLOUR rather than in weight: `zwoelf` in text and
    -- `stuff` a step back. There is no weight axis on a FontString - the panel
    -- font is whatever LibSharedMedia handed over and it may ship one cut - so
    -- a design that asks for 600 against 400 gets contrast it can actually
    -- have.
    local mark = rail:CreateTexture(nil, "ARTWORK")
    mark:SetSize(26, 26)
    mark:SetPoint("TOPLEFT", rail, "TOPLEFT", UI.PAD, -18)
    mark:SetTexture(ns.ICON_TEXTURE)

    local brand = UI.Label(rail, "zwoelf", UI.FS.card, C.text)
    brand:SetPoint("TOPLEFT", mark, "TOPRIGHT", 10, -1)

    local brandTail = UI.Label(rail, "stuff", UI.FS.card, C.textFaint)
    brandTail:SetPoint("LEFT", brand, "RIGHT", 0, 0)

    local brandSub = UI.Eyebrow(rail, "EU Destromath")
    brandSub:SetPoint("TOPLEFT", brand, "BOTTOMLEFT", 0, -3)

    -- The foot: what version this is, and what it is running on. Both are the
    -- first thing anybody is asked for when something is wrong, and neither
    -- belongs anywhere the eye goes while working.
    local foot = CreateFrame("Frame", nil, rail)
    foot:SetHeight(38)
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

    -- DISCORD, above the foot rule.
    --
    -- The click cannot open a browser - no addon can, the client has no call
    -- for it - so it opens the copy box with the invite already selected. That
    -- is the honest version of a link here: one Ctrl+C and it is in the
    -- address bar. A row that looked like a link and did nothing would be
    -- worse than no row.
    local DISCORD_URL = "https://discord.gg/d2EnXGNbGu"

    local discord = CreateFrame("Button", nil, rail)
    discord:SetHeight(UI.NAV_ITEM_H)
    discord:SetPoint("BOTTOMLEFT", foot, "TOPLEFT", 0, 6)
    discord:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT", 0, 6)

    -- THE WORD, AND NO MARK. There was a mark here for one version and it was
    -- not Discord's - drawn from memory, and a brand mark you have traced
    -- yourself is worse than none, because it claims to be the real thing. The
    -- word says it exactly.
    --
    -- Aligned on the same 16 as the rail's own headings, past where an active
    -- row's accent bar sits, so it lines up with the nav above it.
    local discordLabel = UI.Label(discord, "Discord", UI.FS.row, C.textDim)
    discordLabel:SetPoint("LEFT", discord, "LEFT", 16, 0)

    discord:SetScript("OnEnter", function()
        discordLabel:SetTextColor(C.text[1], C.text[2], C.text[3])
    end)
    discord:SetScript("OnLeave", function()
        discordLabel:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    end)
    discord:SetScript("OnClick", function()
        UI.CopyBox("Discord", DISCORD_URL,
            "Ctrl+C copies it, then paste it into your browser. Esc closes. "
            .. "An addon cannot open a browser itself - the client has no "
            .. "call for it, by design.")
    end)

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
    close:SetSize(24, 24)
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

    local pageTitle = UI.Label(stageHost, "", UI.FS.title, C.text)
    pageTitle:SetPoint("TOPLEFT", stageHost, "TOPLEFT", PAD, -16)

    -- Width, not a second anchor: a font string given both TOPLEFT and RIGHT
    -- is told two different vertical positions and lands somewhere else.
    local pageSubtitle = UI.Label(stageHost, "", UI.FS.meta, C.textFaint)
    pageSubtitle:SetPoint("TOPLEFT", pageTitle, "BOTTOMLEFT", 0, -6)
    pageSubtitle:SetJustifyH("LEFT")
    pageSubtitle:SetWordWrap(false)

    -- The two ways into Edit Mode, in the header band where the page's own
    -- actions live. They are shortcuts, not a second home: the rail entry
    -- still opens edit mode, these two say which half of it you want.
    --
    -- Both carry their mark, because these two are the only pair in the window
    -- whose names describe the same activity from two sides - "move them" and
    -- "take them apart" - and the marks separate them faster than the words do.
    -- The widths are named, because the subtitle below has to stop short of
    -- them and a number typed twice is a number that drifts.
    local BUILD_W, MOVE_W = 104, 124

    local buildBtn = UI.Button(stageHost, "Build", BUILD_W, function()
        ns.EditMode:SetUnlocked(true, "build")
    end)
    buildBtn:SetPoint("TOPRIGHT", stageHost, "TOPRIGHT", -PAD, -18)
    buildBtn:SetIcon("action-build")

    local moveBtn = UI.Button(stageHost, "Move bars", MOVE_W, function()
        ns.EditMode:SetUnlocked(true, "bars")
    end)
    moveBtn:SetPoint("TOPRIGHT", buildBtn, "TOPLEFT", -6, 0)
    moveBtn:SetIcon("action-move-bars")

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



    local barList = ns.OptionsBars:BuildList(body, listWidth)
    local side = ns.OptionsBars:BuildSide(sideHost, PAD)
    local tankSide = ns.OptionsCoTanks:BuildSide(sideHost, PAD)
    local reminderSide = ns.OptionsReminders:BuildSide(sideHost, PAD)

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

    ---------------------------------------------------------------------
    -- Left column entries
    ---------------------------------------------------------------------
    local navItems = {}

    local function ShowPage(index)
        self.pageIndex = index

        local entry = PAGES[index]
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
    -- bars in your hands. That is a different kind of thing, and a heading
    -- over it would be a promise that the entries under it behave alike.
    --
    -- It is also the entry that gets used most often and it was five rows
    -- down. A door belongs at the top.
    local NAV = {
        { title = "Edit mode", glyph = "move", onClick = function()
            frame:Hide()
            ns.EditMode:SetUnlocked(true)
        end },
        { eyebrow = "Bars" },
        { page = "cooldowns" },
        { eyebrow = "Tank stuff" },
        { page = "cotanks" },
        { page = "reminders" },
        { page = "routes" },
        { eyebrow = "System" },
        { page = "settings" },
        { page = "diagnostics" },
        { eyebrow = "Info" },
        { page = "about" },
        { page = "changelog" },
    }

    local pageByKey = {}
    for index, entry in ipairs(PAGES) do pageByKey[entry.key] = index end

    local y = HEADER_H + UI.PAD
    for position, entry in ipairs(NAV) do
        if entry.eyebrow then
            -- Air ABOVE the heading, and none under it. A heading belongs to
            -- what follows; spaced evenly it belongs to neither side.
            if position > 1 then y = y + 18 end
            local caption = UI.Eyebrow(rail, entry.eyebrow)
            caption:SetPoint("TOPLEFT", rail, "TOPLEFT", UI.PAD, -y - 6)
            y = y + 20
        else
            local index = entry.page and pageByKey[entry.page]
            local pageEntry = index and PAGES[index]
            local item = UI.NavItem(rail,
                entry.title or (pageEntry and pageEntry.title) or "",
                entry.glyph or (pageEntry and pageEntry.glyph),
                entry.onClick or function() ShowPage(index) end)
            -- FLUSH WITH BOTH EDGES of the rail, not inset.
            --
            -- Inset by 8, the active row's fill is a floating box with a gap
            -- down its right-hand side, and the accent bar sits 8 pixels in
            -- from the column edge instead of ON it. The design runs the row
            -- from edge to edge; the padding belongs INSIDE the row, which is
            -- where the icon's own 8 already is.
            item:SetPoint("TOPLEFT", rail, "TOPLEFT", 0, -y)
            item:SetPoint("TOPRIGHT", rail, "TOPRIGHT", 0, -y)
            if index then navItems[index] = item end
            y = y + UI.NAV_ITEM_H
        end
    end

    ---------------------------------------------------------------------
    -- Painting
    ---------------------------------------------------------------------
    local function PaintView()
        local entry = PAGES[self.pageIndex] or PAGES[1]
        local withSide = entry.side and true or false
        local withExplain = entry.explain and true or false
        local withTanks = entry.tanks and true or false
        local withReminders = entry.reminders and true or false

        -- The middle column narrows for any of them: the third column is
        -- there or it is not, and what is IN it is a separate question.
        local third = withSide or withExplain or withTanks or withReminders
        SetStageWidth(third)
        sideHost:SetShown(third)
        side:SetShown(withSide)
        explain:SetShown(withExplain)
        tankSide:SetShown(withTanks)
        reminderSide:SetShown(withReminders)
        if withTanks then ns.OptionsCoTanks:Refresh() end
        if withReminders then ns.OptionsReminders:Refresh() end

        pageTitle:SetText(entry.title)
        if entry.status then
            local count = ns.Bars:Count()
            local slots, filled = 0, 0
            for index = 1, count do
                local cfg = ns.Bars:Get(index)
                if cfg then
                    local total = ns.Bars:CellCount(cfg)
                    slots = slots + total
                    for cell = 1, total do
                        if cfg.cells and cfg.cells[cell] then filled = filled + 1 end
                    end
                end
            end
            pageSubtitle:SetText(string.format("%d bar%s - %d of %d cells filled",
                count, count == 1 and "" or "s", filled, slots))
        else
            pageSubtitle:SetText(entry.subtitle)
        end

        -- The header actions belong to the bars page. On a page with no bars
        -- on it, "Move bars" is an instruction to leave.
        moveBtn:SetShown(withSide)
        buildBtn:SetShown(withSide)

        -- The subtitle stops at the buttons rather than at the column edge,
        -- or a long one runs underneath them.
        local room = (third and NARROW_W or WIDE_W) - PAD * 2
        if withSide then room = room - (MOVE_W + BUILD_W + 6 + UI.PAD) end
        pageSubtitle:SetWidth(room)

        barList:SetShown(withSide)
        for index, page in pairs(pageFrames) do
            page:SetShown(index == self.pageIndex)
        end

        for index, item in ipairs(navItems) do
            item:SetActive(index == self.pageIndex)
        end

        if withSide then
            barList.Refresh()
            side.Refresh()
        else
            local page = pageFrames[self.pageIndex]
            if page and page.Refresh then page.Refresh() end
        end
    end

    self.PaintView = PaintView
    self.ShowPage = ShowPage

    SetStageWidth(true)
    self:Refresh()

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
