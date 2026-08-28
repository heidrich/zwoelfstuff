---------------------------------------------------------------------------
-- OptionsAnswers.lua - the External CD answer page.
--
-- The mirror of the request page, and now built out of the same parts.
--
-- Owner, 2026-08-10, with a picture of the three buttons stranded at the
-- bottom: "bitte die 3 buttons wie bei den external cd request nach oben
-- packen" - and then the general form of it: "viele ansichten sind ja mehr
-- oder weniger gleich, dann koennen wir die auch gleich designen", "man kann
-- eigentlich das layout von request uebernehmen, sehe keinen grund der
-- dagegen spricht". There was none.
--
-- So: the BAND at the top holds the cells you offer and, beside them, the
-- three things you do to the bar; the settings scroll underneath in two
-- columns. Two pages that are one idea seen from both ends must not be two
-- different pictures.
--
-- What moved OUT of the scrolling half is the list of "what you can be asked
-- for" - it was a stack of full-width toggle rows, which is the same list the
-- request page draws as a row of icons. Same decision, same shape.
---------------------------------------------------------------------------
local _, ns = ...

local UI = ns.UI
local C = UI.C

local Page = {}
ns.OptionsAnswers = Page

---------------------------------------------------------------------------
-- THE ALERTS EDITOR - the reminders page, on the answer alerts' book
--
-- Owner, 2026-08-17: "bau doch einfach die reminder-seite da ein und in die
-- rechte seite, wo bei reminder die spells sind, haust du die answer
-- spells." So it is that page: Core/OptionsReminders.lua's editor class on
-- ns.AnswerAlerts (Core/AnswerAlerts.lua), built into the Alerts tab below,
-- with a spec that says the few things that differ - the words, and "Ends"
-- where a reminder has "Appears". The right-hand column is BuildSide at
-- the foot of this file: your answer spells, click or drag onto the slot.
---------------------------------------------------------------------------
local ALERT_SPEC = {
    prefix    = "aa",
    intro     = "A line of text on your screen the moment somebody asks you "
        .. "for one of yours - \"Akui asks for Pain Suppression\" - whether "
        .. "the bar is up or not. Drag the spell in from the list on the "
        .. "right; |cffffd100%who|r and |cffffd100%spell|r in the words are "
        .. "filled in when it fires.",
    newLabel  = "New alert",
    full      = "That is as many alerts as this addon will hold",
    emptyHint = "No alerts yet. New alert, then drag one of your spells in "
        .. "from the right.",
    -- No sound row: the "asked" chime is the bar's, one per spell, and it
    -- plays whether or not an alert watches the spell. It is picked on the
    -- Bar tab beside "A sound when somebody asks".
    sound     = nil,

    -- WHEN IT GOES AWAY, where a reminder has "Appears". A request is a
    -- moment, not a state, so the alert has to decide for itself when to
    -- stop - "nach x sekunden, oder 3 mal aufleuchten, gib den leuten
    -- optionen". Only the count that applies is live.
    Trigger = function(editor, grid, Body, Get, Set, Apply)
        Body(UI.Dropdown(grid:FullRow("Ends", { controlWidth = 260 }),
            ns.ALERT_ENDINGS, Get("ending", "asked"), Set("ending"),
            { apply = Apply }))
        local seconds = Body(UI.Slider(grid:FullRow("Seconds", { controlWidth = 124 }), {
            get = Get("seconds", 4), set = Set("seconds"),
            min = 1, max = 20, step = 1, apply = Apply,
            format = function(v) return string.format("%ds", v or 0) end,
        }))
        local flashes = Body(UI.Slider(grid:FullRow("Flashes", { controlWidth = 124 }), {
            get = Get("flashes", 3), set = Set("flashes"),
            min = 1, max = 10, step = 1, apply = Apply,
            format = function(v) return string.format("%dx", v or 0) end,
        }))
        grid:Note("Casting the answer takes it down early under every one of "
            .. "these. \"When answered or run out\" follows the bar's own "
            .. "|cffffd100How long it shouts|r.")
        return function(cfg)
            seconds:SetRelevant(cfg.ending == "seconds")
            flashes:SetRelevant(cfg.ending == "flashes")
        end
    end,

    StateLine = function(book, cfg)
        local state, why = book:State(cfg)
        if not state then return "Cannot tell - " .. (why or "no reason given") end
        local ask = ns.AnswerAlerts.AskFor(cfg.spellID)
        if state == "asked" and ask then
            return (ask.who or "Somebody") .. " is asking for it right now."
        end
        return "Nobody is asking for it right now."
    end,
}

ns.OptionsAnswerAlerts = ns.RemindersEditor.New(ns.AnswerAlerts, ALERT_SPEC)

-- The request page's numbers, because it is the same band.
local SLOT, GAP = 40, 8
local MIN_SLOT = 22

local function Cfg() return ns.Answers.Config() end
local function Apply() ns.Answers.Rebuild() end

---------------------------------------------------------------------------
-- ONE CELL IN THE BAND
--
-- NOT UI.SpellSlot, and the difference is what a click means. That widget's
-- subject is which spell is IN a slot: it takes a drop, shows a "+" when
-- there is nothing there, and clears on a right click. Here the spells are
-- fixed by your class and the only question is whether you offer each one,
-- so an empty state would be a lie about what the click does.
--
-- It borrows the slot's LOOK exactly - same well, same one-pixel edge, same
-- crop on the art - so that the two bands read as one band.
---------------------------------------------------------------------------
local function OfferCell(parent, spellID)
    local cell = CreateFrame("Button", nil, parent)
    cell:RegisterForClicks("LeftButtonUp")
    cell.spellID = spellID

    UI.Fill(cell, "BACKGROUND", C.well)
    local edge = ns.CreateBorder(cell, 1, "BORDER")

    -- THE HOVER RING, the same one the bar cells and the spell slots wear.
    -- This cell answered a hover with a tooltip and nothing else: the one
    -- square in the addon you press that never said it was under the cursor.
    -- Owner: "wir brauchen da ueberall einen hoverindikator."
    local hoverHost = CreateFrame("Frame", nil, cell)
    hoverHost:SetPoint("TOPLEFT", cell, "TOPLEFT", -2, 2)
    hoverHost:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 2, -2)
    local hover = ns.CreateBorder(hoverHost, 2, "OVERLAY")
    hover:SetColor(C.controlHi[1], C.controlHi[2], C.controlHi[3], 1)
    hover:Hide()
    cell.hover = hover

    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetPoint("TOPLEFT", cell, "TOPLEFT", 2, -2)
    cell.icon:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -2, 2)
    cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    cell.icon:SetTexture(ns.SpellTexture(spellID))

    -- OFF IS GREY AND DIM, NOT GONE. The spell is still yours and switching
    -- it back on is the same click in the same place; a cell that vanished
    -- would send you looking for a list that is not there any more.
    cell.Paint = function(self)
        local on = ns.Answers.Offering(self.spellID)
        self.icon:SetDesaturated(not on)
        self.icon:SetAlpha(on and 1 or 0.3)
        local colour = on and C.accentDim or C.separator
        edge:SetColor(colour[1], colour[2], colour[3], 1)
    end

    cell:SetScript("OnClick", function(self)
        ns.Answers.SetOffering(self.spellID,
            not ns.Answers.Offering(self.spellID))
        Apply()
        ns.Options:Refresh()
    end)

    cell:SetScript("OnEnter", function(self)
        self.hover:Show()
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        -- pcall for the reason every other tooltip here has one: a spell the
        -- client would rather not describe costs a missing tooltip, never an
        -- error thrown under the cursor.
        if pcall(GameTooltip.SetSpellByID, GameTooltip, self.spellID) then
            GameTooltip:AddLine(ns.Answers.Offering(self.spellID)
                and "Click to stop offering it."
                or "Click to offer it.", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        else
            GameTooltip:Hide()
        end
    end)
    cell:SetScript("OnLeave", function(self)
        self.hover:Hide()
        if GameTooltip then GameTooltip:Hide() end
    end)

    cell:Paint()
    return cell
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
function Page:BuildPage(page, width)
    local grid = UI.Page(page, width, { tooltipNotes = true, sticky = true })

    ---------------------------------------------------------------------
    -- THE BAND: what you offer, and what you can do to the bar
    ---------------------------------------------------------------------
    local band = grid.sticky
    UI.Fill(band, "BACKGROUND", C.windowBg)

    local BAND_HEAD = 32

    local bandTitle = UI.Eyebrow(band, "What you can be asked for")
    bandTitle:SetPoint("TOPLEFT", band, "TOPLEFT", 0, -10)

    -- NO RULE OF ITS OWN at the foot: the tab strip below carries one, and
    -- two lines sixteen pixels apart read as the text sitting on the lower
    -- one (owner, 2026-08-17: "der text muss weiter runter ... nicht den
    -- rest noch weiter hoch").

    -- THE THINGS YOU DO TO THE BAR ARE IN THE WINDOW'S HEADER BAND, beside
    -- the page title, with every other page's - see the PAGES table in
    -- Options.lua. They were a column of three down the right of THIS band,
    -- which is the arrangement the request page had and lost for the same
    -- reason: it took a third of the width away from the cells.
    --
    -- "Move the bar" did not go with them. Edit mode is at the top of the
    -- rail and is the same act; the paragraph under the cells says so.

    -- THE HOST NEEDS A RECTANGLE, NOT A HEIGHT: two points across for the
    -- width, and a height. A frame whose rect cannot be worked out is not
    -- drawn and neither are its children - the request page learned that the
    -- hard way, and this is the same band.
    local host = CreateFrame("Frame", nil, band)
    host:SetPoint("TOPLEFT", band, "TOPLEFT", 0, -BAND_HEAD)
    host:SetPoint("TOPRIGHT", band, "TOPRIGHT", -14, -BAND_HEAD)
    host:SetHeight(SLOT)

    -- WHAT YOUR SPEC CAN ACTUALLY CAST, and nothing else. ns.KnowsSpell is
    -- the filter: a cell for a spell you do not have is a button that reports
    -- READY and then casts nothing.
    local _, class = UnitClass("player")
    local mine = ns.Answers.Offers(class, nil, ns.KnowsSpell)

    local cells = {}
    for index, offer in ipairs(mine) do
        cells[index] = OfferCell(host, offer.spellID)
    end

    if #mine == 0 then
        local none = UI.Label(host, "Your class has nothing to offer here.",
            UI.FS.meta, C.textFaint)
        none:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -6)
    end

    -- THE TWO TABS, at the foot of the band so the offers stay in view on
    -- both: "Bar" is everything the page was, "Alerts" is the line that goes
    -- up when somebody asks (Core/AnswerAlerts.lua). Owner, 2026-08-17: "wir
    -- fuegen einen tab alerts ein". Built here, laid out once the band knows
    -- its width, and mounted on `grid.strip` as the cooldowns page does.
    local strip
    strip = UI.TabStrip(band, { "Bar", "Alerts" }, function(name)
        grid:ShowTab(name)
        strip:Select(name)
    end)
    -- A FEW PIXELS above the band's foot, so the first line of whichever
    -- tab is open does not sit on the strip's rule ("hier klebt wieder der
    -- text an der linie"). The note under it adds its own six.
    local STRIP_GAP = 8
    strip:SetPoint("BOTTOMLEFT", band, "BOTTOMLEFT", 0, STRIP_GAP)
    strip:SetPoint("BOTTOMRIGHT", band, "BOTTOMRIGHT", -14, STRIP_GAP)
    grid.strip = strip

    -- The band is as tall as it actually needs to be. Sized for the largest
    -- class it would hold a third of the page empty for everybody else.
    band.Fit = function()
        local count = #cells
        local size = SLOT
        if count > 0 then
            -- The cells get the whole band, less the scrollbar gutter, and
            -- shrink rather than running off the edge.
            local room = width - 28
            local byWidth = (room - (count - 1) * GAP) / count
            size = math.max(MIN_SLOT, math.floor(math.min(SLOT, byWidth)))
        end

        for index, cell in ipairs(cells) do
            cell:SetSize(size, size)
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", host, "TOPLEFT",
                (index - 1) * (size + GAP), 0)
        end

        -- The cells alone decide the height now. It used to be the taller of
        -- the cells and the button column, so a class with two offers held a
        -- band three buttons deep.
        host:SetHeight(count > 0 and size or 20)
        band:SetHeight(BAND_HEAD + host:GetHeight() + 10 + 34 + STRIP_GAP)
        strip:Layout()
    end
    band.Fit()

    -- EVERYTHING FROM HERE TO THE ALERTS TAB IS THE BAR'S. Grid:Tab files
    -- every row made after it under this name; the alerts tab below is
    -- deferred until somebody presses it (see Grid:LazyTab).
    grid:Tab("Bar")

    grid:Note("Click one to stop offering it. Only spells your spec can cast "
        .. "are here. To put the bar somewhere, open |cffffd100Edit mode|r at "
        .. "the top of the list on the left.")

    ---------------------------------------------------------------------
    -- The switches
    --
    -- Two half-width rows rather than two full-width ones. A toggle needs a
    -- label and a switch; giving it the whole page puts eighteen inches of
    -- nothing between them.
    ---------------------------------------------------------------------
    grid:Section("Switch it on")

    -- STRAIGHT AFTER THE HEADING, WHICH IS THE ONLY PLACE A NOTE ON THIS
    -- PAGE IS ACTUALLY DRAWN: Section clears lastRow, so this one is laid
    -- out instead of becoming some toggle's tooltip. Owner, 2026-08-25:
    -- "requesten geht immer, answer nur MIT addon" - the asymmetry belongs
    -- at the top of the page it is about, not four sections down.
    grid:Note("|cffffd100This bar needs the addon on both sides.|r Anybody "
        .. "can ask you in chat. The bar only lights up when the person "
        .. "asking runs ZwoelfStuff too.")

    UI.Toggle(grid:Row("Show the bar"),
        function() return Cfg().enabled and true or false end,
        function(value) Cfg().enabled = value and true or false; Apply() end)

    UI.Toggle(grid:Row("A quick menu on the bar"),
        function() return Cfg().quickMenu ~= false end,
        function(value) Cfg().quickMenu = value and true or false; Apply() end)

    grid:Note("Off, a request is printed in chat instead. The quick menu is a "
        .. "small button above the bar for |cffffd100who you answer|r.")

    ---------------------------------------------------------------------
    -- WHO GETS A ROW
    --
    -- Owner, 2026-08-10: "man kann keine spieler auswaehlen, oder einstellen
    -- also targets". There was no answer to that at all - the tanks were
    -- picked for you and that was the whole of it, which is right until the
    -- group has not set its roles, and then it is an empty bar with no
    -- explanation.
    ---------------------------------------------------------------------
    grid:Section("Who you answer")

    local whoHost = CreateFrame("Frame", nil, grid.content)
    local whoChips = UI.ChipRow(whoHost, width - 40, {
        chips = {
            { key = ns.Answers.WHO_TANKS,  text = "The tanks" },
            { key = ns.Answers.WHO_GROUP,  text = "Everybody" },
            { key = ns.Answers.WHO_CHOSEN, text = "People I pick" },
        },
        isOn = function(key)
            return (Cfg().who or ns.Answers.WHO_TANKS) == key
        end,
        onSelect = function(key)
            Cfg().who = key
            Apply()
            ns.Options:Refresh()
        end,
    })
    whoChips:SetPoint("TOPLEFT", whoHost, "TOPLEFT", 0, 0)
    whoHost:SetHeight(whoChips:GetHeight())
    grid:Wide(whoHost, whoChips:GetHeight(), 4, 8)
    whoHost.Refresh = function() whoChips.Refresh() end
    grid.widgets[#grid.widgets + 1] = whoHost

    grid:Note("One row of cells per person. |cffffd100The tanks|r needs "
        .. "assigned roles; |cffffd100People I pick|r names them yourself.")

    UI.Slider(grid:Row("Rows"), {
        get = function() return ns.Answers.Rows(Cfg()) end,
        set = function(value) Cfg().rows = value end,
        min = 1, max = ns.Answers.MAX_ROWS, step = 1, apply = function()
            Apply()
            ns.Options:Refresh()
        end,
    })

    -- ONE DROPDOWN PER ROW, full width because a character name plus a realm
    -- is what goes in it - the same reason the request page's "who to ask"
    -- rows span both columns. Out of the layout entirely while the mode does
    -- not use them, rather than sitting there greyed out.
    for index = 1, ns.Answers.MAX_ROWS do
        local row = grid:FullRow("Row " .. index, { controlWidth = 220 })

        UI.Dropdown(row, function()
            local items = { { value = "", text = "Nobody" } }
            for _, member in ipairs(ns.Roster()) do
                if not member.isPlayer then
                    items[#items + 1] = { value = member.name,
                        text = member.name }
                end
            end
            return items
        end, function()
            return Cfg().rowNames[index] or ""
        end, function(value)
            Cfg().rowNames[index] = (value ~= "" and value) or nil
            Apply()
        end, { emptyText = "Nobody" })

        local paintControl = row.Refresh
        row.Refresh = function()
            if paintControl then paintControl() end
            row:SetRelevant(Cfg().who == ns.Answers.WHO_CHOSEN
                and index <= ns.Answers.Rows(Cfg()))
        end
    end

    ---------------------------------------------------------------------
    -- WHAT PRESSING ONE DOES
    ---------------------------------------------------------------------
    grid:Section("When you press one")

    UI.Toggle(grid:Row("Take them as your target too"),
        function() return Cfg().target and true or false end,
        function(value) Cfg().target = value and true or false; Apply() end)

    grid:Note("A cell casts on whoever asked and leaves your target alone. A "
        .. "|cffffd100taunt|r cell casts on what that tank is fighting.")

    ---------------------------------------------------------------------
    -- NO KEYS SECTION. Keys are set on the bar itself - |cffffd100Set keys|r
    -- in this page's header - and the paragraph that stood here only said
    -- so. Owner, 2026-08-16: "den komplett raus".
    ---------------------------------------------------------------------

    ---------------------------------------------------------------------
    -- The bar
    ---------------------------------------------------------------------
    grid:Section("The bar")

    UI.Slider(grid:Row("Cell size"), {
        get = function() return Cfg().size end,
        set = function(value) Cfg().size = value end,
        min = 24, max = 64, step = 2, apply = Apply,
    })

    UI.Slider(grid:Row("Spacing"), {
        get = function() return Cfg().gap end,
        set = function(value) Cfg().gap = value end,
        min = 0, max = 16, step = 1, apply = Apply,
    })

    local function Percent(v)
        return string.format("%d%%", math.floor((v or 0) * 100 + 0.5))
    end

    UI.Slider(grid:Row("Resting opacity"), {
        get = function() return Cfg().idleAlpha end,
        set = function(value) Cfg().idleAlpha = value end,
        min = 0.1, max = 1, step = 0.05, format = Percent, scale = 100,
        apply = function() ns.Answers.Repaint() end,
    })

    -- The other half of the pair. `alpha` was read by the bar and had no
    -- control - the part without its own setting.
    UI.Slider(grid:Row("Opacity when asked"), {
        get = function() return Cfg().alpha end,
        set = function(value) Cfg().alpha = value end,
        min = 0.1, max = 1, step = 0.05, format = Percent, scale = 100,
        apply = function() ns.Answers.Repaint() end,
    })

    UI.Slider(grid:Row("How long it shouts"), {
        get = function() return Cfg().linger end,
        set = function(value) Cfg().linger = value end,
        min = 3, max = 20, step = 1,
        format = function(v) return string.format("%ds", v or 0) end,
        apply = function() ns.Answers.Repaint() end,
    })

    grid:Note("How the bar looks with nobody asking, and how long an "
        .. "unanswered request keeps shouting. A resting cell still casts.")

    UI.Toggle(grid:Row("A sound when somebody asks"),
        function() return Cfg().sound ~= false end,
        function(value) Cfg().sound = value and true or false end)

    ---------------------------------------------------------------------
    -- WHEN IT IS ON THE SCREEN AT ALL - ns.Visibility's rule, the same
    -- block the reminders and the bars carry, built by ns.OptionsWhen. The
    -- "Only in dungeons and raids" switch that stood here until 4.84.0 is
    -- one line of that rule now (Answers.Config folds it in). Discord,
    -- 2026-08-16: "display conditions wie beim taunt button ... show as
    -- tank, dps, heal".
    ---------------------------------------------------------------------
    ns.OptionsWhen.Build(grid, {
        title = "When to show it",
        anchor = "an-when",
        holder = Cfg,
        apply = function() ns.Answers.Repaint() end,
    })

    ---------------------------------------------------------------------
    -- THE WORDS ON A CELL, AND THE SHOUT.
    ---------------------------------------------------------------------
    grid:Section("Text")

    UI.Slider(grid:Row("Name size"), {
        get = function() return Cfg().nameSize end,
        set = function(value) Cfg().nameSize = value end,
        min = 6, max = 20, step = 1,
        apply = function() ns.Answers.Repaint() end,
    })

    UI.Toggle(grid:Row("Show the key"),
        function() return Cfg().showKey ~= false end,
        function(value)
            Cfg().showKey = value and true or false
            ns.Answers.Repaint()
        end)

    grid:Section("The shout")

    UI.Swatch(grid:Row("Ring colour"),
        function()
            local colour = Cfg().callColor or ns.UI.C.accent
            return colour[1], colour[2], colour[3]
        end,
        function(r, g, b) Cfg().callColor = { r, g, b } end,
        function() ns.Answers.Repaint() end)

    UI.Slider(grid:Row("Ring thickness"), {
        get = function() return Cfg().callSize end,
        set = function(value) Cfg().callSize = value end,
        min = 1, max = 8, step = 1,
        apply = function() ns.Answers.Repaint() end,
    })

    grid:Note("The ring and the name appear while somebody is asking, and go "
        .. "again when you have answered or the request has run out.")

    ---------------------------------------------------------------------
    -- The look, in the bar's own words
    ---------------------------------------------------------------------
    local function Slide(label, key, min, max, step, format, scale)
        UI.Slider(grid:Row(label), {
            get = function() return Cfg()[key] end,
            set = function(value) Cfg()[key] = value end,
            min = min, max = max, step = step,
            format = format, scale = scale, apply = Apply,
        })
    end

    grid:Section("Look")

    Slide("Scale", "scale", 0.5, 2, 0.05, Percent, 100)
    Slide("Icon zoom", "iconZoom", 0, 0.2, 0.01, Percent, 100)

    grid:Section("Border")

    Slide("Thickness", "borderSize", 0, 4, 1)

    UI.Swatch(grid:Row("Colour"),
        function()
            local colour = Cfg().borderColor or ns.SurfaceColor()
            return colour[1], colour[2], colour[3]
        end,
        function(r, g, b) Cfg().borderColor = { r, g, b } end, Apply)

    UI.MediaPicker(grid:FullRow("Texture",
        { controlWidth = 190, icon = "media-border" }), "border",
        function() return Cfg().borderTexture end,
        function(value) Cfg().borderTexture = value end, Apply)

    grid:Section("Backdrop")

    UI.Toggle(grid:Row("Show"),
        function() return Cfg().backdrop ~= false end,
        function(value) Cfg().backdrop = value and true or false; Apply() end)

    UI.Swatch(grid:Row("Colour"),
        function()
            local colour = Cfg().backdropColor or ns.SurfaceColor()
            return colour[1], colour[2], colour[3]
        end,
        function(r, g, b) Cfg().backdropColor = { r, g, b } end, Apply)

    Slide("Opacity", "backdropAlpha", 0, 1, 0.05, Percent, 100)

    UI.MediaPicker(grid:FullRow("Texture",
        { controlWidth = 190, icon = "media-texture" }), "statusbar",
        function() return Cfg().backdropTexture end,
        function(value) Cfg().backdropTexture = value end, Apply)

    grid:LazyTab("Alerts", function() Page:BuildAlerts(grid, width) end)

    grid.tab = "Bar"
    grid:Layout()
    strip:Layout()
    strip:Select("Bar")

    page.Refresh = function()
        band.Fit()
        for _, cell in ipairs(cells) do cell:Paint() end
        -- The alerts editor's own picture (list, card, spell), when its tab
        -- has been built; the rows themselves are refreshed with the grid.
        local editor = ns.OptionsAnswerAlerts
        if editor and editor.Paint then editor.Paint() end
        grid:Refresh()
    end

    -- RETURNED, so the desk can look at what was built rather than only at
    -- the fact that building it did not throw. See the "a page has to open on
    -- something you can work with" guard: it asks the band for its height and
    -- the grid for one visible control, and it can ask neither of a page that
    -- hands back nothing.
    return grid
end

---------------------------------------------------------------------------
-- THE ALERTS TAB - the reminders page, built into this grid
---------------------------------------------------------------------------
function Page:BuildAlerts(grid, width)
    grid:Tab("Alerts")
    ns.OptionsAnswerAlerts:BuildInto(grid, width)
end

---------------------------------------------------------------------------
-- THE RIGHT-HAND COLUMN - your answer spells, for the alerts
--
-- The externals page's shape (a short list of our own, not the Cooldown
-- Manager's catalogue): one row per spell your spec offers, the same list
-- the band shows. Click one to have the selected alert watch it, or drag
-- it onto the slot. The trailing word says whether the bar OFFERS it -
-- read-only here; the band's cells are the switch for that, and a second
-- switch for the same question is two that can disagree.
---------------------------------------------------------------------------
function Page:BuildSide(sideHost, pad)
    local side = CreateFrame("Frame", nil, sideHost)
    side:SetAllPoints(sideHost)
    side:Hide()

    local title = UI.Label(side, "Your spells", UI.FS.card, C.text)
    title:SetPoint("TOPLEFT", side, "TOPLEFT", pad, -18)

    local hint = UI.Label(side, "Click one to have the alert watch it, or drag it onto the slot.",
        UI.FS.meta, C.textFaint)
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    hint:SetPoint("RIGHT", side, "RIGHT", -pad, 0)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(false)

    local listHost = CreateFrame("Frame", nil, side)
    listHost:SetPoint("TOPLEFT", side, "TOPLEFT", pad, -(UI.HEADER_H + 16))
    listHost:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -pad, pad)

    local rowWidth = UI.INSPECTOR_W - pad * 2 - 8
    local _, content = UI.ScrollArea(listHost, rowWidth, 8)

    local rows = {}
    local none = UI.Hint(content, "Your class has nothing to offer here.")
    none:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -8)
    none:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -8)
    none:Hide()

    -- Built on refresh rather than once: what the spec offers changes with
    -- the spec, and this column has to say so without a /reload.
    side.Refresh = function()
        local editor = ns.OptionsAnswerAlerts
        local _, class = UnitClass("player")
        local mine = ns.Answers.Offers(class, nil, ns.KnowsSpell)
        local Comm = ns.Comm
        local y = 0
        for index, offer in ipairs(mine) do
            local row = rows[index]
            if not row then
                row = UI.SpellRow(content, rowWidth, 30)
                row:SetScript("OnClick", function(self)
                    local _, cfg = editor:Current()
                    if not cfg then
                        ns.Print("Make an alert first - the New alert button on the Alerts tab.")
                        return
                    end
                    cfg.spellID = self.spellID
                    editor:Apply()
                end)
                rows[index] = row
            end
            local spellID = offer.spellID
            row.dkSpellID = spellID
            row.spellID = spellID
            row.icon:SetTexture(ns.SpellTexture(spellID) or ns.WHITE)
            row.name:SetText(offer.kind == (Comm and Comm.TAUNT)
                and ((ns.SpellName(spellID) or "Taunt") .. " (taunt)")
                or (ns.SpellName(spellID) or ("Spell " .. spellID)))
            local _, cfg = editor:Current()
            local watched = cfg and cfg.spellID == spellID
            row:SetUsed(watched and "watched" or nil, true)
            local offered = ns.Answers.Offering(spellID)
            row:SetTrailing(watched and "Watched" or (offered and "Offered" or "Not offered"),
                watched and "cell" or nil)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            row:Show()
            y = y + 31
        end
        for index = #mine + 1, #rows do rows[index]:Hide() end
        none:SetShown(#mine == 0)
        content:SetHeight(math.max(1, y))
    end

    return side
end
