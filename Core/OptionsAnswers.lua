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
    cell:SetScript("OnLeave", function()
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

    -- ONE UNDER THE OTHER, ALL ONE WIDTH, in a column of their own on the
    -- right - the request page's arrangement, for the reason it has it: three
    -- boxes shoulder to shoulder at three different widths read as a toolbar
    -- somebody stopped styling.
    local BAND_ACTIONS = {
        { text = "Move the bar",
          onClick = function() ns.EditMode:SetUnlocked(true, "bars") end },
        { text = "Set keys",
          onClick = function() ns.Keys:SetActive(true) end },
        -- The report, and it is worth finding: it prints the macro each cell
        -- would run, which is the one thing that says whether this works.
        { text = "What every cell would cast",
          onClick = function() ns.Answers:Dump() end },
    }

    -- Measured, and the widest one sets the column. No number typed here.
    local ACTION_W = 0
    for _, spec in ipairs(BAND_ACTIONS) do
        ACTION_W = math.max(ACTION_W, UI.ButtonWidth(spec.text))
    end

    local ACTION_GAP = 6
    local ACTIONS_H = #BAND_ACTIONS * (UI.BUTTON_H + ACTION_GAP) - ACTION_GAP

    local y = -6
    for _, spec in ipairs(BAND_ACTIONS) do
        local button = UI.Button(band, spec.text, ACTION_W, spec.onClick)
        button:SetPoint("TOPRIGHT", band, "TOPRIGHT", -14, y)
        y = y - UI.BUTTON_H - ACTION_GAP
    end

    -- THE HOST NEEDS A RECTANGLE, NOT A HEIGHT: two points across for the
    -- width, and a height. A frame whose rect cannot be worked out is not
    -- drawn and neither are its children - the request page learned that the
    -- hard way, and this is the same band.
    --
    -- The cells keep the left, the actions have the right.
    local host = CreateFrame("Frame", nil, band)
    host:SetPoint("TOPLEFT", band, "TOPLEFT", 0, -BAND_HEAD)
    host:SetPoint("TOPRIGHT", band, "TOPRIGHT", -(14 + ACTION_W + 14),
        -BAND_HEAD)
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

    -- The band is as tall as it actually needs to be. Sized for the largest
    -- class it would hold a third of the page empty for everybody else.
    band.Fit = function()
        local count = #cells
        local size = SLOT
        if count > 0 then
            -- The cells get what the action column leaves them, and shrink
            -- rather than running off the edge.
            local room = width - 28 - ACTION_W - 14
            local byWidth = (room - (count - 1) * GAP) / count
            size = math.max(MIN_SLOT, math.floor(math.min(SLOT, byWidth)))
        end

        for index, cell in ipairs(cells) do
            cell:SetSize(size, size)
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", host, "TOPLEFT",
                (index - 1) * (size + GAP), 0)
        end

        host:SetHeight(count > 0 and size or 20)
        band:SetHeight(math.max(BAND_HEAD + host:GetHeight(),
            ACTIONS_H + 12) + 10)
    end
    band.Fit()

    grid:Note("Click one to stop offering it. Only spells your spec can cast "
        .. "are here.")

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
    -- Keys - on the bar itself, not in a list of eight rows.
    ---------------------------------------------------------------------
    grid:Section("Keys")

    grid:Note("|cffffd100Set keys|r puts the bar on screen with a square over "
        .. "every cell: click one, press the key. The key then shows in the "
        .. "corner of the cell.")

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

    UI.Toggle(grid:Row("Only in dungeons and raids"),
        function() return Cfg().onlyInInstance and true or false end,
        function(value)
            Cfg().onlyInInstance = value and true or false
            Apply()
        end)

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
            local colour = Cfg().borderColor or { 0, 0, 0 }
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
            local colour = Cfg().backdropColor or { 0, 0, 0 }
            return colour[1], colour[2], colour[3]
        end,
        function(r, g, b) Cfg().backdropColor = { r, g, b } end, Apply)

    Slide("Opacity", "backdropAlpha", 0, 1, 0.05, Percent, 100)

    UI.MediaPicker(grid:FullRow("Texture",
        { controlWidth = 190, icon = "media-texture" }), "statusbar",
        function() return Cfg().backdropTexture end,
        function(value) Cfg().backdropTexture = value end, Apply)

    grid:Layout()

    page.Refresh = function()
        band.Fit()
        for _, cell in ipairs(cells) do cell:Paint() end
        grid:Refresh()
    end
end
