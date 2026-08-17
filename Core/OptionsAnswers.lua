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

    local bandRule = band:CreateTexture(nil, "ARTWORK")
    bandRule:SetColorTexture(C.separator[1], C.separator[2], C.separator[3], 1)
    bandRule:SetHeight(1)
    bandRule:SetPoint("BOTTOMLEFT", band, "BOTTOMLEFT", 0, 0)
    bandRule:SetPoint("BOTTOMRIGHT", band, "BOTTOMRIGHT", -14, 0)

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
    strip:SetPoint("BOTTOMLEFT", band, "BOTTOMLEFT", 0, 0)
    strip:SetPoint("BOTTOMRIGHT", band, "BOTTOMRIGHT", -14, 0)
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
        band:SetHeight(BAND_HEAD + host:GetHeight() + 10 + 34)
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

    UI.Toggle(grid:Row("Show the bar"),
        function() return Cfg().enabled and true or false end,
        function(value) Cfg().enabled = value and true or false; Apply() end)

    UI.Toggle(grid:Row("A quick menu on the bar"),
        function() return Cfg().quickMenu ~= false end,
        function(value) Cfg().quickMenu = value and true or false; Apply() end)

    grid:Note("Off, a request is printed in chat instead. The quick menu is a "
        .. "small button above the bar for |cffffd100who you answer|r.")

    grid:Note("Only players who also run ZwoelfStuff can light up your bar - "
        .. "everybody else still gets the chat line.")

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
-- THE ALERTS TAB - the line that goes up when somebody asks
--
-- The reminders' vocabulary on purpose (font, size, edge, colour, icon,
-- flash), because it IS a reminder in shape and the two pages should read as
-- one addon; plus the one thing a reminder never needed - when to stop - and
-- the per-spell switches, which can only name the spells your spec offers.
-- Owner, 2026-08-17: "das kannste auch nur mit genau den spells die du zur
-- verfuegung hast da so konfigurieren."
---------------------------------------------------------------------------
function Page:BuildAlerts(grid, width)
    grid:Tab("Alerts")
    local A = ns.AnswerAlerts
    local function ACfg() return A.Config() end
    local function Restyle() A.Refresh() end

    grid:Section("Switch it on", "aa-on", true)

    UI.Toggle(grid:Row("Show a line when asked"),
        function() return ACfg().enabled end,
        function(value) ACfg().enabled = value and true or false end)

    grid:Note("Large type near the middle of the screen - \"Akui asks for "
        .. "Pain Suppression\" - the moment a request comes in, whether the "
        .. "bar is up or not. To put it somewhere, open |cffffd100Edit mode|r "
        .. "at the top of the list on the left; |cffffd100Show me|r below "
        .. "puts a sample up under the real rules.")

    grid:Buttons({
        { text = "Show me", onClick = function() A.Preview() end },
    }, 4)

    ---------------------------------------------------------------------
    -- WHEN IT GOES AWAY. The one setting the reminders never needed.
    ---------------------------------------------------------------------
    grid:Section("How long it stays", "aa-end", true)

    local endRow = grid:FullRow("Ends", { controlWidth = 260 })
    UI.Dropdown(endRow, function() return A.ENDINGS end,
        function() return ACfg().ending end,
        function(value)
            ACfg().ending = value
            grid:Refresh()
        end)

    local secondsRow = grid:Row("Seconds")
    UI.Slider(secondsRow, {
        get = function() return ACfg().seconds end,
        set = function(value) ACfg().seconds = value end,
        min = 1, max = 20, step = 1,
        format = function(v) return string.format("%ds", v or 0) end,
    })
    local flashesRow = grid:Row("Flashes")
    UI.Slider(flashesRow, {
        get = function() return ACfg().flashes end,
        set = function(value) ACfg().flashes = value end,
        min = 1, max = 10, step = 1,
        format = function(v) return string.format("%dx", v or 0) end,
    })

    -- ONLY THE COUNT THAT APPLIES IS LIVE. Two sliders for one setting,
    -- with the other one greyed, is how the page says which one the
    -- dropdown is reading right now.
    local paintSeconds, paintFlashes = secondsRow.Refresh, flashesRow.Refresh
    secondsRow.Refresh = function()
        if paintSeconds then paintSeconds() end
        secondsRow:SetRelevant(ACfg().ending == "seconds")
    end
    flashesRow.Refresh = function()
        if paintFlashes then paintFlashes() end
        flashesRow:SetRelevant(ACfg().ending == "flashes")
    end

    grid:Note("Casting the answer takes the line down early under every "
        .. "one of these. \"When answered or run out\" follows the bar's own "
        .. "|cffffd100How long it shouts|r.")

    ---------------------------------------------------------------------
    -- WHICH OF YOURS. One switch per spell the spec offers, the same list
    -- the band above shows - and only that list.
    ---------------------------------------------------------------------
    grid:Section("Which of your spells", "aa-spells", true)

    local _, class = UnitClass("player")
    local mine = ns.Answers.Offers(class, nil, ns.KnowsSpell)
    local Comm = ns.Comm
    local any = false
    for _, offer in ipairs(mine) do
        if offer.spellID then
            any = true
            local spellID = offer.spellID
            local row = grid:Row("")
            UI.MakeRowASpell(row, spellID)
            row.label:SetText(offer.kind == (Comm and Comm.TAUNT)
                and "A taunt" or (ns.SpellName(spellID) or tostring(spellID)))
            UI.Toggle(row,
                function() return ACfg().spells[spellID] ~= false end,
                function(value)
                    ACfg().spells[spellID] = (not value) and false or nil
                end)
        end
    end
    if not any then
        grid:Note("Your class has nothing to offer here, so there is nothing "
            .. "to be asked for.")
    end

    grid:Note("Left alone, every spell you offer gets a line. Switch one off "
        .. "to keep the bar's ring and skip the words for it.")

    ---------------------------------------------------------------------
    -- SOUNDS. The "asked" event has ONE sound per spell, and the bar plays
    -- it - this is where it is picked, because this tab is where the spells
    -- are listed. Same shape as the request page's sound rows.
    ---------------------------------------------------------------------
    grid:Section("Sounds", "aa-sounds", true)

    for _, offer in ipairs(mine) do
        if offer.spellID then
            local spellID = offer.spellID
            local row = grid:FullRow("", { controlWidth = 220 })
            UI.MediaPicker(row, "sound",
                function() return ns.Sounds.Get("asked", spellID) end,
                function(value) ns.Sounds.Set("asked", spellID, value) end,
                function() ns.Sounds.Preview(ns.Sounds.Get("asked", spellID)) end,
                "Same as everywhere")
            local paintControl = row.Refresh
            row.Refresh = function()
                if paintControl then paintControl() end
                UI.MakeRowASpell(row, spellID)
                row.label:SetText(offer.kind == (Comm and Comm.TAUNT)
                    and "A taunt" or (ns.SpellName(spellID) or tostring(spellID)))
            end
        end
    end

    grid:Note("Played once when the request comes in, line or no line. Left "
        .. "alone, each one uses whatever |cffffd100Settings - Sounds|r chose "
        .. "for \"When somebody asks you\".")

    ---------------------------------------------------------------------
    -- HOW IT LOOKS - the reminders' rows, one for one.
    ---------------------------------------------------------------------
    grid:Section("How it looks", "aa-look", true)

    UI.MediaPicker(grid:FullRow("Font", { controlWidth = 190 }), "font",
        function() return ACfg().font end,
        function(value) ACfg().font = value end, Restyle, "Same as everywhere")
    UI.Slider(grid:FullRow("Size", { controlWidth = 124 }), {
        get = function() return ACfg().size end,
        set = function(value) ACfg().size = value end,
        min = 12, max = 72, step = 1, apply = Restyle,
    })
    UI.Dropdown(grid:FullRow("Edge", { controlWidth = 150 }),
        ns.Media.OUTLINES,
        function() return ACfg().outline end,
        function(value) ACfg().outline = value end, { apply = Restyle })
    UI.Swatch(grid:FullRow("Colour", { controlWidth = 124 }),
        function()
            local c = ACfg().color
            return c[1], c[2], c[3]
        end,
        function(r, g, b) ACfg().color = { r, g, b } end, Restyle)
    UI.Dropdown(grid:FullRow("Icon", { controlWidth = 150 }),
        ns.REMINDER_ICON_SIDES,
        function() return ACfg().iconSide end,
        function(value) ACfg().iconSide = value end, { apply = Restyle })
    UI.Slider(grid:FullRow("Icon size", { controlWidth = 124 }), {
        get = function() return ACfg().iconSize end,
        set = function(value) ACfg().iconSize = value end,
        min = 12, max = 96, step = 1, apply = Restyle,
    })
    UI.Slider(grid:FullRow("Scale", { controlWidth = 124 }), {
        get = function() return ACfg().scale end,
        set = function(value) ACfg().scale = value end,
        min = 0.5, max = 2, step = 0.05,
        format = function(v) return string.format("%d%%", (v or 1) * 100) end,
        apply = Restyle,
    })

    grid:Section("Flashing", "aa-flash", true)

    UI.Toggle(grid:FullRow("Flash", { controlWidth = 124 }),
        function() return ACfg().flash end,
        function(value) ACfg().flash = value and true or false end)
    UI.Slider(grid:FullRow("Speed", { controlWidth = 124 }), {
        get = function() return ACfg().flashRate end,
        set = function(value) ACfg().flashRate = value end,
        min = 0.3, max = 3, step = 0.1,
        format = function(v) return string.format("%.1f/s", v or 0) end,
    })
    UI.Slider(grid:FullRow("Fades to", { controlWidth = 124 }), {
        get = function() return ACfg().flashMin end,
        set = function(value) ACfg().flashMin = value end,
        min = 0, max = 0.9, step = 0.05,
        format = function(v) return string.format("%d%%", (v or 0) * 100) end,
    })

    grid:Note("It never fades all the way out. \"After a number of flashes\" "
        .. "counts these.")
end
