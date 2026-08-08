---------------------------------------------------------------------------
-- OptionsBars - the cooldown workspace.
--
-- Three columns, and each one has exactly one job:
--
--   left     what you are working on at all (handled in Options.lua)
--   middle   ALL your bars, under each other, each one a card that IS the
--            bar: the same grid, the same order, plus the two sliders that
--            shape it. Nothing is hidden behind a selection - you see every
--            bar you own at once, and "Add new bar" sits at the bottom of
--            the stack where the next one will appear.
--   right    the spells, listed in full. Click a cell, click a spell, done.
--            The same column doubles as the settings for one bar when you
--            press Options on its header, and comes back afterwards.
--
-- What the middle deliberately does NOT contain: sizes, colours, opacity.
-- Those are per-bar settings, they are set rarely, and putting them here
-- would bury the two numbers that are actually the shape of the bar.
---------------------------------------------------------------------------
local _, ns = ...

local UI = ns.UI
local C = UI.C
local Bars = ns.Bars

ns.OptionsBars = {}
local Workspace = ns.OptionsBars

local CARD_PAD  = 16
local HEADER_H  = ns.UI.CARD_HEAD_H
local SLIDER_H  = ns.UI.ROW_H
local CARD_GAP  = 14
local ADD_H     = 40

-- The shape column, to the RIGHT of the preview rather than under it.
--
-- Rows and columns used to sit in a full-width strip below the bar, which
-- meant every card was as tall as its preview PLUS a row of controls, and two
-- cards no longer fitted on the page. Beside it they cost nothing: a preview
-- is never shorter than three rows anyway.
local SHAPE_W   = 212
local STAGE_MIN = 112

---------------------------------------------------------------------------
-- Selection
--
-- One bar is current and, inside it, at most one cell. The right column
-- always acts on that pair, which is what makes "click a cell, click a
-- spell" work without any drag, dialog or confirmation.
---------------------------------------------------------------------------
Workspace.mode = "spells"          -- "spells" | "options" | "cell"

function Workspace:Current()
    local index = self.index or 1
    if index > Bars:Count() then index = Bars:Count() end
    if index < 1 then index = 1 end
    self.index = index
    return index, Bars:Get(index)
end

function Workspace:Select(index)
    if self.index ~= index then
        self.index = index
        self.cell = nil            -- a different bar means the old cell is gone
    end
    ns.Options:Refresh()
end

function Workspace:SelectCell(index, cell)
    self.index = index
    self.cell = cell
    -- Picking a cell means you are about to fill it, so the spells come back
    -- by themselves rather than leaving you on a settings pane wondering why
    -- clicking did nothing. Editing one cell and clicking the NEXT is the
    -- exception: that is "now this one", not "I want the spell list".
    if cell and self.mode ~= "cell" then self.mode = "spells" end
    ns.Options:Refresh()
end

function Workspace:ShowOptions(index)
    self.index = index
    self.cell = nil
    self.mode = "options"
    ns.Options:Refresh()
end

function Workspace:ShowSpells()
    self.mode = "spells"
    ns.Options:Refresh()
end

-- One cell's own look. Reached from the spells pane while a cell is picked,
-- because that is the moment you are already looking at the cell you mean.
function Workspace:ShowCell(index, cell)
    self.index = index
    self.cell = cell
    self.mode = "cell"
    ns.Options:Refresh()
end

-- The next cell worth filling, so filling a bar is click, click, click
-- instead of click, click, re-aim, click.
function Workspace:AdvanceCell()
    local _, cfg = self:Current()
    if not cfg then return end

    for cell = (self.cell or 0) + 1, Bars:CellCount(cfg) do
        if not cfg.cells[cell] then
            self.cell = cell
            return
        end
    end

    self.cell = nil
    ns.Print(string.format("\"%s\" is full - pull Rows or Columns up to fit more.",
        cfg.name))
end

local function Apply()
    Bars:Changed((Workspace:Current()))
    ns.Options:Refresh()
end

---------------------------------------------------------------------------
-- Assigning a spell
---------------------------------------------------------------------------
function Workspace:Assign(spellID)
    local index, cfg = self:Current()
    if not cfg then
        ns.Print("Add a bar first.")
        return
    end

    if self.cell then
        Bars:SetCell(index, self.cell, spellID)
        self:AdvanceCell()
    else
        -- No cell aimed at: the first free one is what the user means.
        Bars:AddSpell(index, spellID)
    end

    ns.Options:Refresh()
end

---------------------------------------------------------------------------
-- The middle: every bar, under each other
---------------------------------------------------------------------------
local function BuildCard(parent, width)
    local card = UI.Card(parent, width)

    -- Header ---------------------------------------------------------------
    --
    -- Left: which bar this is, what it is called, what KIND it is. Right: the
    -- actions. The two halves never meet, because a click that changes the bar
    -- and a click that changes the view must not be neighbours.
    local chip = CreateFrame("Frame", nil, card)
    chip:SetSize(20, 20)
    chip:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -10)
    local chipBg = UI.Fill(chip, "BACKGROUND", C.control)

    local number = UI.Label(chip, "", 11, C.textDim)
    number:SetPoint("CENTER", chip, "CENTER", 0, 0)

    local title = UI.Label(card, "", UI.FS.card, C.text)
    title:SetPoint("LEFT", chip, "RIGHT", 11, 0)
    title:SetWordWrap(false)

    local kindBadge = UI.Badge(card, "", "kind")
    kindBadge:SetPoint("LEFT", title, "RIGHT", 11, 0)

    -- The overflow. Delete lives in here and nowhere else: it is the one
    -- action on this card with no undo, and an action with no undo does not
    -- belong one pixel away from the button you press all day.
    local menu = CreateFrame("Button", nil, card)
    menu:SetSize(24, 24)
    menu:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -8)
    -- Three dots as a MARK, not as three full stops. Typed, they sit on the
    -- baseline and had to be nudged up by three pixels to look centred, which
    -- is the tell that a character was standing in for a drawing.
    local menuMark = UI.Glyph(menu, "action-overflow", 12, C.textFaint)
    menuMark:SetPoint("CENTER", menu, "CENTER", 0, 0)
    menu:SetScript("OnEnter", function()
        menuMark:SetColor(C.text[1], C.text[2], C.text[3])
    end)
    menu:SetScript("OnLeave", function()
        menuMark:SetColor(C.textFaint[1], C.textFaint[2], C.textFaint[3])
    end)
    menu:SetScript("OnClick", function()
        if not card.dkIndex then return end
        UI.ShowMenu(menu, {
            width = 170,
            items = {
                {
                    text = "Delete this bar",
                    icon = "action-delete",
                    colour = C.danger,
                    onClick = function()
                        Bars:Remove(card.dkIndex)
                        Workspace.cell = nil
                        ns.Options:Refresh()
                    end,
                },
            },
        })
    end)

    -- The bar's own settings, in the right column.
    local options = UI.GhostButton(card, "Options", function()
        if not card.dkIndex then return end
        Workspace:ShowOptions(card.dkIndex)
    end, C.textDim)
    options:SetPoint("RIGHT", menu, "LEFT", -4, 0)

    -- Straight from the card onto the screen. An arrangement is something you
    -- judge by looking at it where it will live, not in a preview.
    --
    -- THE ONLY WAY IN, on purpose. The settings panel used to carry a second
    -- "Build on screen" row doing exactly this - two buttons for one action,
    -- one of them on a page you have to open first, and its control sat on top
    -- of its own sublabel. The card is where the bar is, so the button is here.
    local build = UI.GhostButton(card, "Build on screen", function()
        if not card.dkIndex then return end
        Workspace:Select(card.dkIndex)
        ns.EditMode:OpenBuild()
    end, C.accentCool)
    build:SetPoint("RIGHT", options, "LEFT", -11, 0)
    build:SetIcon("action-build-on-screen")

    -- ONE BUTTON FOR THE PICKED CELL, named after what the bar is made of.
    --
    -- This was three tabs - Spells, Bar, Cell - and three tabs on a card is
    -- three questions asked before anything is answered. The card now says the
    -- two things it is FOR: this cell, and this bar. Which cell is not left to
    -- be remembered either; the badge says it.
    local cellBadge = UI.Badge(card, "CELL 1", "current")
    cellBadge:SetPoint("RIGHT", build, "LEFT", -11, 0)

    local cellBtn = UI.GhostButton(card, "Icon options", function()
        if not card.dkIndex then return end
        if not Workspace.cell then
            ns.Print("Pick a cell in the bar first - then this is its own settings.")
            return
        end
        Workspace:ShowCell(card.dkIndex, Workspace.cell)
    end, C.textDim)
    cellBtn:SetPoint("RIGHT", cellBadge, "LEFT", -6, 0)

    card.cellBtn, card.cellBadge, card.options = cellBtn, cellBadge, options

    local headerLine = UI.Separator(card)
    headerLine:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -HEADER_H)
    headerLine:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, -HEADER_H)

    -- The bar itself -------------------------------------------------------
    --
    -- A well with a hairline round it, so the preview reads as a piece of
    -- SCREEN set into the card rather than as more card.
    local well = CreateFrame("Frame", nil, card)
    well:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -(HEADER_H + CARD_PAD))
    well:SetWidth(width - CARD_PAD * 2 - SHAPE_W - UI.PAD)
    well:SetHeight(STAGE_MIN)
    UI.Fill(well, "BACKGROUND", C.well)
    local wellEdge = ns.CreateBorder(well, 1, "BORDER")
    wellEdge:SetColor(C.separator[1], C.separator[2], C.separator[3], 1)

    local stage = CreateFrame("Frame", nil, well)
    stage:SetPoint("TOPLEFT", well, "TOPLEFT", 14, -14)
    stage:SetPoint("TOPRIGHT", well, "TOPRIGHT", -14, -14)
    stage:SetHeight(1)

    local function Cfg()
        return card.dkIndex and Bars:Get(card.dkIndex)
    end

    local grid = UI.CellGrid(stage, {
        -- The same engine the screen uses, so the preview is the arrangement
        -- and not a drawing of one. An arc curves here too.
        layout = function()
            local cfg = Cfg()
            if not cfg then
                return { { x = 0, y = 0, w = 40, h = 40, kind = "icon" } },
                    { width = 40, height = 40, centreX = 0, centreY = 0 }
            end
            return ns.Layout.Build(cfg, Bars:CellCount(cfg),
                cfg.spacing or 4, cfg.lineSpacing or 4)
        end,
        -- The bar's real look, from the same function the screen calls. This
        -- is what makes the card a preview of what you built rather than a
        -- diagram of it: pick a texture and you see that texture, here.
        style = function(height, cell)
            local cfg = Cfg()
            if not cfg then return nil end
            return ns.Bars:CellStyle(cfg, cell, height)
        end,
        iconPlacement = function()
            local cfg = Cfg()
            return cfg and cfg.iconPlacement or "left"
        end,
        content = function(cell) local cfg = Cfg() return cfg and cfg.cells[cell] end,
        selected = function()
            if Workspace.index ~= card.dkIndex then return nil end
            return Workspace.cell
        end,
        onPick = function(cell) Workspace:SelectCell(card.dkIndex, cell) end,
        onClear = function(cell)
            Bars:ClearCell(card.dkIndex, cell)
            ns.Options:Refresh()
        end,
        -- A spell dragged out of the right-hand list and dropped on this
        -- cell. The card it lands on becomes the selected one, because that
        -- is plainly what you meant by dropping something in it.
        onDrop = function(cell, spellID)
            if not card.dkIndex then return end
            Bars:SetCell(card.dkIndex, cell, spellID)
            Workspace:SelectCell(card.dkIndex, cell)
            ns.Options:Refresh()
        end,
        -- Reorder, not swap: dragging a spell up the list has to leave the
        -- others in their own order, or sorting a bar is a puzzle rather than
        -- a drag. Shift held means "these two change places" instead, which is
        -- the other thing people mean by dragging one icon onto another.
        onMove = function(from, to, swap)
            if swap then
                Bars:MoveCell(card.dkIndex, from, to)
            else
                Bars:ReorderCell(card.dkIndex, from, to)
            end
            Workspace:SelectCell(card.dkIndex, to)
        end,
    })
    grid:SetPoint("TOPLEFT", stage, "TOPLEFT", 0, 0)

    -- Shape ----------------------------------------------------------------
    --
    -- Three rows in a 212 column beside the preview: how many across, how many
    -- down, and which pattern they are laid out in. Everything else about a
    -- bar is in the inspector; these three are here because they change the
    -- picture immediately to their left.
    local shape = CreateFrame("Frame", nil, card)
    shape:SetWidth(SHAPE_W)
    shape:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD, -(HEADER_H + CARD_PAD))
    shape:SetHeight(SLIDER_H * 3)

    local rows = UI.MiniSlider(shape, {
        label = "Rows", min = 1, max = 12, step = 1,
        get = function() local cfg = Cfg() return cfg and cfg.rows or 1 end,
        set = function(value)
            local cfg = Cfg()
            if cfg then Bars:SetGrid(card.dkIndex, value, cfg.columns) end
        end,
        -- Shaping a bar is also a way of pointing at it, so the right column
        -- follows rather than staying on whatever was picked before.
        apply = function() Workspace:Select(card.dkIndex) end,
    })
    rows:SetPoint("TOPLEFT", shape, "TOPLEFT", 0, 0)
    rows:SetPoint("TOPRIGHT", shape, "TOPRIGHT", 0, 0)

    local columns = UI.MiniSlider(shape, {
        label = "Columns", labelWidth = 62, min = 1, max = 12, step = 1,
        get = function() local cfg = Cfg() return cfg and cfg.columns or 1 end,
        set = function(value)
            local cfg = Cfg()
            if cfg then Bars:SetGrid(card.dkIndex, cfg.rows, value) end
        end,
        -- Shaping a bar is also a way of pointing at it, so the right column
        -- follows rather than staying on whatever was picked before.
        apply = function() Workspace:Select(card.dkIndex) end,
    })
    columns:SetPoint("TOPLEFT", shape, "TOPLEFT", 0, -SLIDER_H)
    columns:SetPoint("TOPRIGHT", shape, "TOPRIGHT", 0, -SLIDER_H)

    -- An arc, a diagonal and a puzzle have no rows and columns to set. They
    -- have a LENGTH, and offering two sliders that do nothing is worse than
    -- offering the one that does.
    local slots = UI.MiniSlider(shape, {
        label = "Slots", min = 1, max = 40, step = 1,
        get = function() local cfg = Cfg() return cfg and cfg.freeCount or 6 end,
        set = function(value)
            local cfg = Cfg()
            if cfg then
                cfg.freeCount = value
                Bars:Changed(card.dkIndex)
            end
        end,
        apply = function() Workspace:Select(card.dkIndex) end,
    })
    slots:SetPoint("TOPLEFT", shape, "TOPLEFT", 0, 0)
    slots:SetPoint("TOPRIGHT", shape, "TOPRIGHT", 0, 0)

    -- Which pattern. A grid, a row, an arc - the one setting that changes what
    -- the other two even mean, so it sits under them rather than over them:
    -- you count first and shape second.
    local arrangeRow = CreateFrame("Frame", nil, shape)
    arrangeRow:SetHeight(SLIDER_H)
    arrangeRow:SetPoint("TOPLEFT", shape, "TOPLEFT", 0, -SLIDER_H * 2)
    arrangeRow:SetPoint("TOPRIGHT", shape, "TOPRIGHT", 0, -SLIDER_H * 2)

    local arrangeLabel = UI.Label(arrangeRow, "Arrangement", UI.FS.row, C.textBody)
    arrangeLabel:SetPoint("LEFT", arrangeRow, "LEFT", 0, 0)
    arrangeLabel:SetWordWrap(false)

    local arrange = UI.MenuButton(arrangeRow, 124)
    arrange:SetPoint("RIGHT", arrangeRow, "RIGHT", 0, 0)
    arrangeLabel:SetPoint("RIGHT", arrange, "LEFT", -UI.GAP, 0)
    arrange:SetScript("OnClick", function()
        if not card.dkIndex then return end
        local items = {}
        for _, option in ipairs(ns.LAYOUTS) do
            items[#items + 1] = {
                text = option.text, value = option.value,
                onClick = function()
                    Bars:SetLayout(card.dkIndex, option.value)
                    Workspace:Select(card.dkIndex)
                    ns.Options:Refresh()
                end,
            }
        end
        local cfg = Cfg()
        UI.ShowMenu(arrange, { items = items, current = cfg and cfg.layout })
    end)
    arrange.Refresh = function()
        local cfg = Cfg()
        local text = "-"
        for _, option in ipairs(ns.LAYOUTS) do
            if cfg and option.value == cfg.layout then text = option.text break end
        end
        arrange.label:SetText(text)
    end


    -- Clicking anywhere on the card makes it the one the spells go into.
    card:EnableMouse(true)
    card:SetScript("OnMouseDown", function()
        if card.dkIndex then Workspace:Select(card.dkIndex) end
    end)

    -- Height depends on the grid, which depends on the user's numbers, so the
    -- card measures itself and reports back.
    card.Refresh = function()
        local cfg = Cfg()
        if not cfg then return 0 end

        number:SetText(tostring(card.dkIndex))
        title:SetText(cfg.name)
        -- Measured, then capped. A FontString cannot be given a left anchor
        -- and a right one at the same time, so the badge that follows the name
        -- has to be told where the name ended.
        title:SetWidth(math.min(title:GetStringWidth() + 1, 150))

        local isIcons = cfg.kind ~= "bar"
        kindBadge:SetLabel(isIcons and "Icon bar" or "Tracking bar")
        cellBtn:SetText(isIcons and "Icon options" or "Bar options")

        local gridHeight = grid.Refresh()

        -- A wide grid must not run out of the card. Scaling the preview keeps
        -- the arrangement honest - it is still the real shape, just not at
        -- real size - and the drag maths follows the scale on its own.
        local available = well:GetWidth() - 28
        local natural = math.max(1, grid:GetWidth())
        local fit = math.min(1, available / natural)
        grid:SetScale(fit)
        gridHeight = gridHeight * fit

        stage:SetHeight(math.max(1, gridHeight))

        -- The preview never collapses below the shape column beside it, or a
        -- one-cell bar would leave the card with three controls hanging off
        -- the side of a 40px picture.
        local bodyHeight = math.max(STAGE_MIN, gridHeight + 28, SLIDER_H * 3)
        well:SetHeight(bodyHeight)

        local lattice = ns.Layout.UsesGrid(cfg)
        rows:SetShown(lattice)
        columns:SetShown(lattice)
        slots:SetShown(not lattice)
        if lattice then
            rows.Refresh()
            columns.Refresh()
        else
            slots.Refresh()
        end
        arrange.Refresh()

        local active = Workspace.index == card.dkIndex
        card:SetActive(active)
        title:SetTextColor(
            active and C.text[1] or C.textDim[1],
            active and C.text[2] or C.textDim[2],
            active and C.text[3] or C.textDim[3])

        -- The index chip carries the selection as well as the card outline
        -- does. It is the one thing on the card that is always in the same
        -- place, so it is the one worth colouring.
        chipBg:SetColorTexture(
            active and C.accent[1] or C.control[1],
            active and C.accent[2] or C.control[2],
            active and C.accent[3] or C.control[3], 1)
        local digit = active and C.windowBg or C.textDim
        number:SetTextColor(digit[1], digit[2], digit[3])

        -- Which cell the cell button would open. Shown only on the card that
        -- owns the selection, because a badge saying CELL 2 on three cards is
        -- three claims that only one of them can mean.
        local hasCell = active and Workspace.cell ~= nil
        cellBadge:SetShown(hasCell)
        if hasCell then cellBadge:SetLabel("Cell " .. Workspace.cell) end
        cellBtn:SetBaseColor(hasCell and C.textDim or C.textFaint)
        options:SetBaseColor(active and Workspace.mode == "options"
            and C.accent or C.textDim)

        local height = HEADER_H + CARD_PAD + bodyHeight + CARD_PAD
        card:SetHeight(height)
        return height
    end

    return card
end

function Workspace:BuildList(parent, width)
    local list = CreateFrame("Frame", nil, parent)
    list:SetAllPoints(parent)

    local scroll, content = UI.ScrollArea(list, width - 12)
    local cardWidth = width - 12

    local cards = {}

    -- Two buttons, because the two kinds are a different thing to build, not a
    -- setting you change afterwards: a row of icons and a stack of timer bars
    -- want different sizes, a different default grid and a different place on
    -- screen. Choosing up front means the first one is already right.
    local function Add(kind)
        local index = Bars:Add(nil, kind)
        Workspace:SelectCell(index, 1)

        -- The new bar lands at the bottom of the stack. On a list that already
        -- fills the column, not going there looks like nothing happened. Next
        -- frame, because the scroll range only knows about the new card once
        -- the layout above has run.
        C_Timer.After(0, function()
            scroll:SetVerticalScroll(scroll:GetVerticalScrollRange() or 0)
            if scroll.Update then scroll.Update() end
        end)
    end

    -- One 40 row under the stack, ruled off from it, with the two actions
    -- centred and a hairline between them. Two half-width filled buttons read
    -- as a THIRD card - the heaviest thing on a page whose subject is the
    -- cards above it.
    local addRow = CreateFrame("Frame", nil, content)
    addRow:SetHeight(ADD_H)
    local addLine = UI.Separator(addRow, true)
    addLine:SetPoint("TOPLEFT", addRow, "TOPLEFT", 0, 0)
    addLine:SetPoint("TOPRIGHT", addRow, "TOPRIGHT", 0, 0)

    local addStud = UI.Separator(addRow, false)
    addStud:SetPoint("CENTER", addRow, "CENTER", 0, 0)
    addStud:SetHeight(14)

    local addIcons = UI.Button(addRow, "+   Icon bar", 120,
        function() Add("icon") end, "ghost")
    addIcons:SetPoint("RIGHT", addStud, "LEFT", -UI.PAD, 0)

    local addBars = UI.Button(addRow, "+   Tracking bar", 140,
        function() Add("bar") end, "ghost")
    addBars:SetPoint("LEFT", addStud, "RIGHT", UI.PAD, 0)

    local empty = UI.Label(content, "", 12, C.textDim)
    empty:SetWidth(cardWidth)
    empty:SetJustifyH("LEFT")

    list.Refresh = function()
        local y = 0

        for index = 1, math.max(#cards, Bars:Count()) do
            local cfg = Bars:Get(index)
            local card = cards[index]

            if cfg and not card then
                card = BuildCard(content, cardWidth)
                cards[index] = card
            end

            if cfg then
                card.dkIndex = index
                card:ClearAllPoints()
                card:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
                card:Show()
                y = y - card.Refresh() - CARD_GAP
            elseif card then
                card:Hide()
            end
        end

        if Bars:Count() == 0 then
            empty:SetText("No bars yet. Add one, then click a cell and pick a "
                .. "cooldown from the list on the right.")
            empty:ClearAllPoints()
            empty:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
            empty:Show()
            y = y - empty:GetStringHeight() - 12
        else
            empty:Hide()
        end

        addRow:ClearAllPoints()
        addRow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        addRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
        y = y - ADD_H

        content:SetHeight(math.max(1, -y + 10))
        if scroll.Update then scroll.Update() end
    end

    return list
end

---------------------------------------------------------------------------
-- The right column, pane one: every spell the Cooldown Manager knows
--
-- Sourced from Blizzard's Cooldown Manager on purpose: anything in this list
-- is already tracked by the game, so its icon, its charges and its timing are
-- guaranteed to work. A spell that is not in here cannot be made to work by
-- any addon on this patch - see the About page for why.
---------------------------------------------------------------------------
-- "2m", "1m 30", "25s". A cooldown is compared with other cooldowns while
-- scanning a list, and 90 against 120 is arithmetic; a minute and a half
-- against two minutes is not.
local function Duration(seconds)
    if type(seconds) ~= "number" or seconds <= 0 then return "" end
    if seconds < 60 then return string.format("%ds", seconds) end
    local minutes = math.floor(seconds / 60)
    local rest = seconds - minutes * 60
    if rest == 0 then return string.format("%dm", minutes) end
    return string.format("%dm %d", minutes, rest)
end

local SPELL_ROW_H = 32
local HEADING_H   = 26

-- The order the groups appear in, and what they are called. "other" is the
-- catch-all for anything the client hands back under a category this build
-- does not know - it exists so a renamed enum member costs one heading rather
-- than a spell vanishing from the list.
local GROUPS = {
    { key = "essential", label = "Cooldowns" },
    { key = "utility",   label = "Utility" },
    { key = "buffIcon",  label = "Buffs" },
    { key = "buffBar",   label = "Buff bars" },
    -- Not from the Cooldown Manager: procs this character has been seen to
    -- raise. What is shown is the aura; what drives it is the glow underneath.
    { key = "aura",      label = "Auras" },
    { key = "other",     label = "Other" },
}

function Workspace:BuildSpellPane(parent, width)
    local pane = CreateFrame("Frame", nil, parent)
    pane:SetAllPoints(parent)

    local filter = "all"

    -- The search sits at the TOP. The line that used to be above it said
    -- "Click a spell to fill cell 5 of Cooldowns" in orange - which is what
    -- the column's own subtitle says, one line higher, and orange is meant to
    -- be rare enough to mean something.
    local search = UI.Input(pane, width, function() end, false, "Search")
    search:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
    search:SetHeight(28)
    search:SetIcon("ui-search")

    local chips
    chips = UI.ChipRow(pane, width, {
        chips = {
            { key = "all",       text = "All" },
            { key = "essential", text = "Cooldowns" },
            { key = "utility",   text = "Utility" },
            { key = "buffIcon",  text = "Buffs" },
            { key = "buffBar",   text = "Buff bars" },
            { key = "aura",      text = "Auras" },
        },
        current = function() return filter end,
        onSelect = function(key)
            filter = key
            chips.Refresh()
            pane.Fill()
        end,
    })
    chips:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -10)

    local listHost = CreateFrame("Frame", nil, pane)
    listHost:SetPoint("TOPLEFT", chips, "BOTTOMLEFT", 0, -10)
    listHost:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 56)

    local scroll, content = UI.ScrollArea(listHost, width - 8)

    -- The footer: a labelled field and the button that acts on it. The label
    -- is beside the field rather than inside it as a placeholder, because a
    -- placeholder disappears the moment you start typing - which is exactly
    -- when "what am I typing here" is still a live question.
    local function AddManual(text)
        local spellID = tonumber(text)
        if spellID and spellID > 0 then
            Workspace:Assign(spellID)
        else
            ns.Print("Enter a numeric spell ID.")
        end
    end

    local manualLabel = UI.Label(pane, "Spell ID", UI.FS.meta, C.textFaint)
    manualLabel:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 0, 14)

    local manualAdd = UI.Button(pane, "Add", 54, function() end)
    manualAdd:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 12)

    local manual = UI.Input(pane, 92, AddManual, true, "")
    manual:SetPoint("LEFT", manualLabel, "RIGHT", 10, 0)
    manual:SetPoint("RIGHT", manualAdd, "LEFT", -8, 0)
    manual:SetHeight(26)

    manualAdd:SetScript("OnClick", function()
        AddManual(manual.input and manual.input:GetText())
    end)

    local footer = UI.Label(pane, "", UI.FS.eyebrow, C.textGhost)
    footer:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 0, 0)
    footer:SetWordWrap(false)

    local rows, headings = {}, {}
    local rowWidth = width - 8

    local function Fill()
        local query = (search.input:GetText() or ""):lower()

        -- Two sources, one list. The Cooldown Manager's entries and the procs
        -- this character has raised carry the same fields, so the row below
        -- does not care which it got.
        local catalogue = {}
        for _, entry in ipairs(ns.CDM:Catalogue()) do catalogue[#catalogue + 1] = entry end
        for _, entry in ipairs(ns.Auras:Catalogue()) do catalogue[#catalogue + 1] = entry end

        -- Which spells are already on the bar being worked on. Only that bar:
        -- the same spell may sit on three others, and marking it here would
        -- say something the user did not ask about.
        local _, cfg = Workspace:Current()
        local used = {}
        if cfg then
            for cell = 1, Bars:CellCount(cfg) do
                local spellID = cfg.cells[cell]
                if spellID and not used[spellID] then used[spellID] = cell end
            end
        end

        local buckets = {}
        for _, group in ipairs(GROUPS) do buckets[group.key] = {} end

        local matched = 0
        for _, entry in ipairs(catalogue) do
            local hit = query == ""
                or entry.name:lower():find(query, 1, true)
                or tostring(entry.spellID):find(query, 1, true)

            local key = entry.viewer or "other"
            if not buckets[key] then key = "other" end

            if hit and (filter == "all" or filter == key) then
                matched = matched + 1
                local bucket = buckets[key]
                bucket[#bucket + 1] = entry
            end
        end

        -- WITHIN A GROUP: what you can cast, in BLIZZARD'S OWN ORDER.
        --
        -- Alphabetical was tidy and matched nothing. This panel says "From
        -- your Cooldown Manager" at the top, and the Cooldown Manager has an
        -- order of its own - the one you arranged in Blizzard's Edit Mode and
        -- the one the icons appear in on screen. Sorting by anything else
        -- makes the picker and the thing it picks from two different lists.
        --
        -- What you cannot cast still goes last. It is worth listing - a bar
        -- can be built for the build you are about to switch into - but not
        -- worth scrolling past to reach what you can use.
        --
        -- Names only ever break a tie now, which also quietly stops a German
        -- client sorting its umlauts after Z.
        for _, group in ipairs(GROUPS) do
            table.sort(buckets[group.key], function(a, b)
                local aKnown, bKnown = a.known ~= false, b.known ~= false
                if aKnown ~= bKnown then return aKnown end

                -- math.huge: the catalogue's order is banded per viewer, so
                -- any fixed sentinel would land inside one of the bands.
                local aOrder, bOrder = a.order or math.huge, b.order or math.huge
                if aOrder ~= bOrder then return aOrder < bOrder end

                if a.name == b.name then return a.spellID < b.spellID end
                return a.name < b.name
            end)
        end

        local y, rowCount, headCount = 0, 0, 0

        for _, group in ipairs(GROUPS) do
            local bucket = buckets[group.key]
            if #bucket > 0 then
                -- Headings only when everything is shown. Filtered to one
                -- group, a heading repeats what the chip above already says.
                if filter == "all" then
                    headCount = headCount + 1
                    local heading = headings[headCount]
                    if not heading then
                        heading = UI.ListHeading(content, rowWidth, HEADING_H)
                        headings[headCount] = heading
                    end
                    heading:SetText(group.label, #bucket)
                    heading:ClearAllPoints()
                    heading:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
                    heading:Show()
                    y = y - HEADING_H
                end

                for _, entry in ipairs(bucket) do
                    rowCount = rowCount + 1
                    local row = rows[rowCount]
                    if not row then
                        row = UI.SpellRow(content, rowWidth, SPELL_ROW_H)
                        rows[rowCount] = row
                    end

                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)

                    row.icon:SetTexture(entry.icon or ns.WHITE)
                    row.name:SetText(entry.name)

                    local cell = used[entry.spellID]
                    local known = entry.known ~= false
                    row:SetUsed(cell, known)

                    -- ONE SHORT THING ON THE RIGHT, in this order of
                    -- importance: is it already placed, does the build have
                    -- it, how long does it last. Everything else - the ID,
                    -- what drives an aura - is in the tooltip, which is where
                    -- you look when you are asking about ONE of them rather
                    -- than scanning all of them.
                    if cell then
                        row:SetTrailing("Cell " .. cell, "cell")
                    elseif not known then
                        row:SetTrailing("Not in build")
                    elseif entry.duration then
                        row:SetTrailing(Duration(entry.duration))
                    else
                        row:SetTrailing("")
                    end

                    -- What the game's own tooltip cannot know: where this
                    -- spell already sits, what actually drives it, and what a
                    -- click here would do.
                    row.dkSpellID = entry.spellID
                    wipe(row.dkLines)

                    if not known then
                        row.dkLines[#row.dkLines + 1] = {
                            text = "Not talented right now. It can still go on a "
                                .. "bar - useful when you are about to switch "
                                .. "into the build that has it.",
                            r = 0.62, g = 0.64, b = 0.68,
                        }
                    end

                    if entry.parent and entry.spellID ~= entry.parent then
                        row.dkLines[#row.dkLines + 1] = {
                            text = string.format(
                                "Shown while %s lights up%s. The Cooldown Manager "
                                .. "does not carry this one, so the proc is what "
                                .. "drives it.",
                                ns.SpellName(entry.parent) or entry.parent,
                                entry.duration and (", about " .. entry.duration .. "s") or ""),
                            r = 1.00, g = 0.478, b = 0.239,
                        }
                    end

                    if cell then
                        row.dkLines[#row.dkLines + 1] = {
                            text = string.format("Already on %s, in cell %d.",
                                cfg and cfg.name or "this bar", cell),
                            r = 0.404, g = 0.788, b = 0.443,
                        }
                    elseif cfg then
                        row.dkLines[#row.dkLines + 1] = {
                            text = Workspace.cell
                                and string.format("Click to put it in cell %d of %s.",
                                    Workspace.cell, cfg.name)
                                or string.format("Click to add it to %s.", cfg.name),
                            r = 0.62, g = 0.64, b = 0.68,
                        }
                    end

                    row:SetScript("OnClick", function() Workspace:Assign(entry.spellID) end)
                    row:Show()

                    y = y - SPELL_ROW_H
                end
            end
        end

        for index = rowCount + 1, #rows do rows[index]:Hide() end
        for index = headCount + 1, #headings do headings[index]:Hide() end

        content:SetHeight(math.max(1, -y))
        if scroll.Update then scroll.Update() end

        -- "cooldowns" was wrong for four of the six groups this list holds -
        -- utility, buffs, buff bars and recorded auras are not cooldowns, and
        -- a count that miscounts what it is counting reads as a bug.
        footer:SetText(string.format("%d of %d", matched, #catalogue))
    end

    -- Typing filters as you type; there is nothing to submit.
    search.input:SetScript("OnTextChanged", function()
        search.UpdateGhost()
        Fill()
    end)

    pane.Fill = Fill
    pane.Refresh = function()
        -- Called for its clamping side effect, not its return: it pulls the
        -- selection back into range after a bar has been deleted, and the
        -- list below is filled from that selection.
        Workspace:Current()
        chips.Refresh()
        Fill()
    end

    return pane
end

---------------------------------------------------------------------------
-- The right column, pane two: everything about one bar
--
-- Reached from the Options button on that bar's card, and it comes back to
-- the spells when you are done. Nothing here changes what a bar contains -
-- only how it looks.
---------------------------------------------------------------------------
function Workspace:BuildOptionsPane(parent, width)
    local pane = CreateFrame("Frame", nil, parent)
    pane:SetAllPoints(parent)

    -- The strip is part of the PANE, not of the scroll area under it: it has
    -- to stay put while the settings scroll, or it is a heading rather than a
    -- control.
    local strip
    strip = UI.TabStrip(pane, { "Look", "Behaviour", "Reuse" }, function(name)
        pane.grid:ShowTab(name)
        strip:Select(name)
    end)
    strip:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, 0)

    local body = CreateFrame("Frame", nil, pane)
    body:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, -UI.PAD)
    body:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0)

    -- The paragraphs under the rows go into TOOLTIPS here.
    --
    -- This column IS the third column, so there is nowhere to move them
    -- to. Inline they were a wrapped grey block under every other setting
    -- and most of the height of the panel, for text that answers a
    -- question almost nobody is asking twice. The row says what the
    -- setting is; the sentence is one hover away.
    local grid = UI.Page(body, width, { tooltipNotes = true })
    pane.grid, pane.strip = grid, strip

    local function Get(key)
        return function()
            local _, cfg = Workspace:Current()
            return cfg and cfg[key]
        end
    end
    local function Set(key)
        return function(value)
            local _, cfg = Workspace:Current()
            if cfg then cfg[key] = value end
        end
    end
    -- The text settings live in sub-tables (cfg.countdown.size), so they need
    -- their own accessors. Kept beside the flat ones rather than made clever:
    -- one extra pair of four-line functions beats a key parser.
    local function GetIn(group, key)
        return function()
            local _, cfg = Workspace:Current()
            local inner = cfg and cfg[group]
            return inner and inner[key]
        end
    end
    local function SetIn(group, key)
        return function(value)
            local _, cfg = Workspace:Current()
            if cfg and cfg[group] then cfg[group][key] = value end
        end
    end

    -- scale: what the DISPLAY multiplies by, so a typed number can be
    -- divided back. A percentage shows 85 and stores 0.85.
    local function Slide(label, key, min, max, step, format, scale)
        return UI.Slider(grid:FullRow(label, { controlWidth = 124 }), {
            get = Get(key), set = Set(key),
            min = min, max = max, step = step, format = format,
            scale = scale, apply = Apply,
        })
    end
    local function Switch(label, key, sublabel)
        return UI.Toggle(grid:FullRow(label, { controlWidth = 124, sublabel = sublabel }),
            Get(key), function(value) Set(key)(value); Apply() end)
    end
    local function Colour(label, key)
        return UI.Swatch(grid:FullRow(label, { controlWidth = 124 }),
            function()
                local _, cfg = Workspace:Current()
                local colour = cfg and cfg[key] or { 0, 0, 0 }
                return colour[1], colour[2], colour[3]
            end,
            function(r, g, b)
                local _, cfg = Workspace:Current()
                if cfg then cfg[key] = { r, g, b } end
            end,
            Apply)
    end

    -- THE SECOND COLOUR AND THE DIRECTION, for the colours that can ramp.
    --
    -- Three rows, and the last two are HIDDEN while the switch is off rather
    -- than greyed: a colour picker and a direction list that belong to a
    -- gradient nobody has turned on are two more things to read on a page
    -- that is already long, and they say nothing about the bar as it is.
    --
    -- Only four colours get called with this, and the three that cannot ramp
    -- get nothing at all - see the note beside the defaults for which and
    -- why. There is no gradientable-ness flag to look up: the call site IS
    -- the list, so a colour cannot quietly acquire a control that does not
    -- work by being added to a table somewhere.
    local gradientGroups = {}

    -- Where a gradient LIVES, handed in rather than looked up.
    --
    -- Three of the four sit on the bar's own config and one sits inside a
    -- numbered stack band, so there is no single path expression that reaches
    -- all four. A resolver is two closures and no string parsing, and the
    -- band's own accessors already know how to make an entry that does not
    -- exist yet - which a path walker here would have had to reinvent.
    local function CfgGradient(key)
        return {
            read = function()
                local _, cfg = Workspace:Current()
                local grad = cfg and cfg[key]
                if type(grad) == "table" then return grad end
                return nil
            end,
            write = function(field, value)
                local _, cfg = Workspace:Current()
                if not cfg then return end
                if type(cfg[key]) ~= "table" then cfg[key] = {} end
                cfg[key][field] = value
            end,
        }
    end

    local function GradientRows(access, note, collect)
        local function Field(field, fallback)
            return function()
                local grad = access.read()
                if not grad then return fallback end
                local value = grad[field]
                if value == nil then return fallback end
                return value
            end
        end
        local function SetField(field)
            return function(value) access.write(field, value) end
        end

        -- gated: this gradient sits inside a section that stands down on a
        -- bar of icons. The visibility pass has to know, because "the switch
        -- is on" and "the section is on screen" are two different questions
        -- and the answer is the AND of them.
        local group = { rows = {}, on = Field("on", false), gated = collect ~= nil }

        local switch = UI.Toggle(
            grid:FullRow("Gradient", { controlWidth = 124, sublabel = note }),
            Field("on", false),
            function(value)
                SetField("on")(value)
                Apply()
                -- The two rows below appear and disappear with it, so the
                -- page has to be measured again - a Refresh alone repaints
                -- rows that are still in their old places.
                grid:Layout()
            end)

        group.rows[#group.rows + 1] = UI.Swatch(
            grid:FullRow("Second colour", { controlWidth = 124 }),
            function()
                local colour = Field("color", { 1, 1, 1 })()
                return colour[1], colour[2], colour[3]
            end,
            function(r, g, b) SetField("color")({ r, g, b }) end,
            Apply)

        group.rows[#group.rows + 1] = UI.Dropdown(
            grid:FullRow("Runs", { controlWidth = 150 }),
            ns.GRADIENT_DIRECTIONS, Field("direction", "right"),
            SetField("direction"), { apply = Apply })

        gradientGroups[#gradientGroups + 1] = group

        -- Everything this built goes into the caller's list, switch included.
        -- The fill's section disappears entirely on a bar of icons, and three
        -- gradient rows left standing there would be three settings pointing
        -- at a fill that is not on the screen.
        if collect then
            collect[#collect + 1] = switch
            for _, row in ipairs(group.rows) do collect[#collect + 1] = row end
        end
        return switch
    end

    -- A size of 0 means "work it out from the cell", so the slider says that
    -- rather than showing a zero nobody would read as automatic.
    local function AutoSize(v)
        if v <= 0 then return "auto" end
        return string.format("%d", v)
    end
    local function Percent(v)
        return string.format("%d%%", math.floor(v * 100 + 0.5))
    end

    -- THREE TABS, not one nine-section scroll.
    --
    -- Look is what it looks like, Behaviour is what it does, Reuse is how it
    -- gets copied. Anything filed under no tab at all shows on every one of
    -- them, which is what the tab strip itself is.
    --
    -- Arrangement is NOT here any more - rows, columns and pattern moved onto
    -- the card, next to the picture they change.
    grid:Tab("Behaviour")
    -- Which one is open when the panel is first built. Declared here rather
    -- than left to fall out of the build order: the first section written is
    -- Behaviour, and "the page opens on whatever I happened to type first" is
    -- not a decision.
    grid.tab = "Look"

    -- Identity ------------------------------------------------------------
    grid:Section("This bar")

    local nameRow = grid:FullRow("Name", { controlWidth = 130 })
    local nameInput = UI.Input(nameRow.slot, 130, function(text)
        local _, cfg = Workspace:Current()
        text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if cfg and text ~= "" then
            cfg.name = text
            ns.Options:Refresh()
        end
    end, false, "name it")
    nameInput:SetPoint("RIGHT", nameRow.slot, "RIGHT", 0, 0)
    nameRow.Refresh = function()
        -- Never while it is being typed in: a refresh from anywhere else
        -- would wipe half-entered text out from under the cursor.
        if nameInput.input:HasFocus() then return end
        local _, cfg = Workspace:Current()
        nameInput:SetText(cfg and cfg.name or "")
    end

    UI.Dropdown(grid:FullRow("Kind", { controlWidth = 124 }), {
        { value = "icon", text = "Icon bar",     icon = "kind-icon" },
        { value = "bar",  text = "Tracking bar", icon = "kind-bar" },
    }, Get("kind"), Set("kind"), { apply = Apply })

    UI.Toggle(grid:FullRow("Shown", { controlWidth = 124 }), Get("enabled"),
        function(value)
            Set("enabled")(value)
            Apply()
        end)

    -- The same switch the padlock on the mover throws. It is here as well so
    -- that "which of my bars are pinned" is answerable without entering edit
    -- mode and looking at each one.
    UI.Toggle(grid:FullRow("Pinned", {
        controlWidth = 124,
        sublabel = "Cannot be dragged or nudged in edit mode",
    }), Get("pinned"), Set("pinned"))

    -- Size ----------------------------------------------------------------
    grid:Tab("Look")
    grid:Section("Size")

    local iconRow = Slide("Icon size", "iconSize", 16, 100, 2)
    local barWRow = Slide("Width", "barWidth", 60, 400, 5)
    local barHRow = Slide("Height", "barHeight", 10, 60, 2)

    -- Bar-shaped cells only. The icon stays square wherever it goes; this
    -- decides which end of the bar it sits at, or whether it appears at all.
    local iconPlaceRow = UI.Dropdown(grid:FullRow("Spell icon", { controlWidth = 124 }), {
        { value = "left",   text = "Left of the bar" },
        { value = "right",  text = "Right of the bar" },
        { value = "hidden", text = "Hidden" },
    }, Get("iconPlacement"), Set("iconPlacement"), { apply = Apply })

    Slide("Spacing", "spacing", 0, 24, 1)
    Slide("Row gap", "lineSpacing", 0, 24, 1)
    Slide("Scale", "scale", 0.4, 2.5, 0.05,
        function(v) return string.format("%.2f", v) end)

    -- Arrangement -----------------------------------------------------------
    --
    -- The shape of the thing, as opposed to what it is made of. Kept high on
    -- the page and unfolded, because it is the setting that changes the most
    -- and the one people come here for.
    grid:Tab("Behaviour")
    grid:Section("Arrangement")

    local layoutRow = grid:FullRow("Pattern", { controlWidth = 150 })
    UI.Dropdown(layoutRow, ns.LAYOUTS, Get("layout"), function(value)
        local index = Workspace:Current()
        if index then ns.Bars:SetLayout(index, value) end
    end, { apply = Apply })

    local layoutNote = grid:Note("", 26)

    local flowRow = UI.Dropdown(grid:FullRow("Fill order", { controlWidth = 150 }),
        ns.FLOWS, Get("flow"), Set("flow"), { apply = Apply })

    UI.Dropdown(grid:FullRow("Across", { controlWidth = 150 }),
        ns.GROW_X, Get("growX"), Set("growX"), { apply = Apply })

    local growYRow = UI.Dropdown(grid:FullRow("Down", { controlWidth = 150 }),
        ns.GROW_Y, Get("growY"), Set("growY"), { apply = Apply })

    UI.Dropdown(grid:FullRow("Pinned by",
        { controlWidth = 150, icon = "pivot-picker" }),
        ns.PIVOTS, Get("point"), function(value)
            local index = Workspace:Current()
            if index then ns.Bars:SetPivot(index, value) end
        end, { apply = Apply })
    grid:Note("Which point of the bar stays put when it changes size. Pinned "
        .. "by the centre it spreads both ways; pin an edge and it grows away "
        .. "from that edge instead.")

    -- One dial per pattern, and each one is only shown for the pattern it
    -- belongs to. A page of sliders that do nothing is how a settings screen
    -- stops being trusted.
    local staggerRow = Slide("Offset", "staggerOffset", 0, 100, 5,
        function(v) return string.format("%d%%", v) end)

    local rasterRow = Slide("Snap to", "raster", 0, 40, 1,
        function(v) return v <= 0 and "free hand" or string.format("%d px", v) end)

    -- The way back out of a bar somebody has been experimenting with.
    --
    -- Every arrangement adds each cell's own nudge on top of the slot it
    -- worked out, which is what makes "pull one icon out of the row" possible
    -- - and it is also how a bar ends up looking broken with no obvious way
    -- back. Only offered when there is something to undo, and it leaves the
    -- puzzle's own positions alone: those belong to the other pattern.
    local straightenRow = grid:FullRow("Straighten", {
        controlWidth = 150,
        sublabel = "Put every cell back where this pattern wants it",
    })
    local straightenBtn = UI.Button(straightenRow.slot, "Straighten", 150,
        function()
            local index, cfg = Workspace:Current()
            if not (index and cfg) then return end
            ns.Layout.ClearOffsets(cfg)
            ns.Bars:Changed(index)
            ns.Options:Refresh()
        end)
    straightenBtn:SetPoint("RIGHT", straightenRow.slot, "RIGHT", 0, 0)
    straightenBtn:SetIcon("ui-reset")

    -- Which of the above apply right now. Recorded as one function so the
    -- rule lives in a single place rather than in nine SetRelevant calls
    -- scattered through the section.
    local function RefreshArrangement()
        local _, cfg = Workspace:Current()
        if not cfg then return end

        local kind = cfg.layout or "grid"
        local lattice = ns.Layout.UsesGrid(cfg)

        for _, entry in ipairs(ns.LAYOUTS) do
            if entry.value == kind then layoutNote:SetText(entry.note) end
        end

        flowRow:SetRelevant(lattice)
        growYRow:SetRelevant(lattice)
        staggerRow:SetRelevant(kind == "stagger")
        rasterRow:SetRelevant(kind == "free")
        straightenRow:SetRelevant(ns.Layout.HasOffsets(cfg))
    end

    -- Looks ---------------------------------------------------------------
    --
    -- Every section from here down is FOLDED by default. There are thirty-odd
    -- settings and they are set once; the grid, the spells and the sizes are
    -- what you come back to. A page that shows all of it at once buries the
    -- work under the knobs.
    grid:Tab("Look")
    grid:Section("Icon", "look-icon")

    Slide("Opacity", "alpha", 0.1, 1, 0.05, Percent, 100)
    Slide("Crop", "iconZoom", 0, 0.2, 0.01, Percent, 100)
    grid:Note("Blizzard's icon art has a border baked into the file. Cropping "
        .. "cuts it off; at 0 you see the whole thing, frame and all.")

    Slide("While inactive", "inactiveAlpha", 0, 1, 0.05, Percent, 100)
    Switch("Grey out while inactive", "inactiveDesaturate")
    grid:Note("Auras this addon draws itself stay in place while they are "
        .. "down, so the bar does not re-flow under your eye. At 0 they "
        .. "disappear instead, the way Blizzard's own buff icons do.")

    grid:Section("Border", "look-border")

    Slide("Thickness", "borderSize", 0, 4, 1)
    Colour("Colour", "borderColor")
    GradientRows(CfgGradient("borderGradient"),
        "Only the one-pixel line - an edge texture takes a single colour")
    UI.MediaPicker(grid:FullRow("Texture",
        { controlWidth = 190, icon = "media-border" }), "border",
        Get("borderTexture"), Set("borderTexture"), Apply)
    grid:Note("None is a crisp one-pixel line drawn from colour textures, and "
        .. "it stays sharper than any edge file at small sizes. The rest come "
        .. "from whatever your other addons registered.")

    grid:Section("Backdrop", "look-backdrop")

    Switch("Show", "backdrop", "A plate behind the icon")
    Colour("Colour", "backdropColor")
    GradientRows(CfgGradient("backdropGradient"))
    Slide("Opacity", "backdropAlpha", 0, 1, 0.05, Percent, 100)
    UI.MediaPicker(grid:FullRow("Texture",
        { controlWidth = 190, icon = "media-texture" }), "statusbar",
        Get("backdropTexture"), Set("backdropTexture"), Apply)
    -- Said out loud, because "I picked a texture and nothing happened" is
    -- otherwise an unanswerable question. The plate is BEHIND the art, and
    -- spell art is opaque and fills its cell.
    grid:Note("This sits behind the icon, so on a square icon you will not see "
        .. "it - spell art is opaque. It shows on a tracking bar, beside and "
        .. "under the fill, and through an aura this addon dims while it is "
        .. "down. For the coloured part of a bar, use Bar fill.")

    -- The fill of a tracking bar this addon draws itself ---------------------
    --
    -- Only ever visible on a bar-shaped cell, so the whole section stands down
    -- on a bar of icons rather than offering four settings that do nothing.
    -- An ADOPTED buff bar brings Blizzard's own fill and is not affected by
    -- any of this; the note says so, because "why did my colour not take" is
    -- otherwise a genuinely unanswerable question.
    local fillRows = {
        grid:Section("Bar fill", "look-fill"),
        Colour("Colour", "fillColor"),
        Slide("Opacity", "fillAlpha", 0, 1, 0.05, Percent, 100),
    }
    -- The preview strips in the list are painted in THIS bar's fill colour.
    -- You open the list to see what this bar will look like, and a column of
    -- orange strips answers a question nobody asked.
    GradientRows(CfgGradient("fillGradient"), nil, fillRows)

    fillRows[#fillRows + 1] = UI.MediaPicker(
        grid:FullRow("Texture",
            { controlWidth = 190, icon = "media-texture" }), "statusbar",
        Get("fillTexture"), Set("fillTexture"), Apply, nil,
        function()
            local colour = Get("fillColor")()
            if type(colour) ~= "table" then return end
            return colour[1], colour[2], colour[3]
        end)
    -- ONE SETTING WITH FOUR ANSWERS, not two switches you have to combine in
    -- your head. "Start on the right" plus "Fill up" was four states spelled
    -- as two questions, and neither question named the thing you actually want
    -- to say, which is which way the bar runs. Two of the four - up and down -
    -- were not reachable at all before: SetReverseFill only flips a horizontal
    -- bar, so the renderer needed an orientation as well.
    fillRows[#fillRows + 1] = UI.Dropdown(
        grid:FullRow("Direction", { controlWidth = 190 }),
        ns.FILL_DIRECTIONS, Get("fillDirection"), Set("fillDirection"),
        { apply = Apply })
    fillRows[#fillRows + 1] = Switch("Fill up", "fillGrow",
        "Grow as time passes instead of draining away")
    -- Stack colours ----------------------------------------------------------
    --
    -- Three bands rather than a list editor with add and remove buttons. A
    -- stack bar has two or three meaningful readings - low, normal, capped -
    -- and three fixed rows say that better than an empty list does. A count of
    -- 0 switches its band off, so the rows are their own on/off.
    --
    -- The list in the config stays variable-length; only this panel is fixed,
    -- so nothing has to change here if the renderer is ever given more.
    local function ThresholdEntry(index)
        local _, cfg = Workspace:Current()
        if not cfg then return nil end
        cfg.stackThresholds = cfg.stackThresholds or {}
        return cfg.stackThresholds[index]
    end
    local function GetThreshold(index, field, fallback)
        return function()
            local entry = ThresholdEntry(index)
            if not entry then return fallback end
            local value = entry[field]
            if value == nil then return fallback end
            return value
        end
    end
    local function SetThreshold(index, field)
        return function(value)
            local _, cfg = Workspace:Current()
            if not cfg then return end
            cfg.stackThresholds = cfg.stackThresholds or {}
            local entry = cfg.stackThresholds[index]
            if not entry then
                entry = { value = 0, color = { 0.85, 0.15, 0.15 } }
                cfg.stackThresholds[index] = entry
            end
            entry[field] = value
        end
    end

    local BAND_COLOURS = {
        { 0.85, 0.15, 0.15 },   -- low
        { 1.00, 0.78, 0.20 },   -- middling
        { 0.30, 0.85, 0.35 },   -- capped
    }

    fillRows[#fillRows + 1] = Switch("Spark", "showSpark",
        "A bright line on the moving edge")
    fillRows[#fillRows + 1] = Switch("Charge marks", "chargeMarks",
        "One line per charge boundary")
    fillRows[#fillRows + 1] = Colour("Mark colour", "chargeMarkColor")
    fillRows[#fillRows + 1] = grid:Note("Charge marks only appear on a spell "
        .. "that HAS more than one charge, so the setting can stay on for a "
        .. "whole bar without marking everything on it.")

    fillRows[#fillRows + 1] = grid:Section("Stack colours", "look-stacks")
    fillRows[#fillRows + 1] = grid:Note("The bar changes colour once the stack "
        .. "count reaches a number you pick. Below the lowest one it wears the "
        .. "Bar fill colour above - so the way to say \"warn me under five\" is "
        .. "a red fill with a band at 5 in your normal colour. Set a count to 0 "
        .. "to switch that band off.")

    for index = 1, 3 do
        fillRows[#fillRows + 1] = UI.Slider(
            -- "At ... stacks" READ as a label that had been cut off, because
            -- that is what an ellipsis in the middle of a phrase looks like.
            -- The number it was standing in for is in the control two inches
            -- to the right, where it says "5+".
            grid:FullRow("From", { controlWidth = 124 }), {
                get = GetThreshold(index, "value", 0),
                set = SetThreshold(index, "value"),
                min = 0, max = 20, step = 1, apply = Apply,
                format = function(v)
                    if (v or 0) < 1 then return "off" end
                    return string.format("%d+", v)
                end,
            })
        local fallback = BAND_COLOURS[index]
        fillRows[#fillRows + 1] = UI.Swatch(
            grid:FullRow("Colour", { controlWidth = 124 }),
            function()
                local colour = GetThreshold(index, "color", fallback)()
                return colour[1], colour[2], colour[3]
            end,
            function(r, g, b) SetThreshold(index, "color")({ r, g, b }) end,
            Apply)
        -- Its own ramp per band, not the fill's. A band exists precisely
        -- because it is a different colour from the fill, so inheriting the
        -- fill's second stop would give it a ramp that ends somewhere the
        -- band was never meant to go.
        GradientRows({
            read  = function() return GetThreshold(index, "gradient", nil)() end,
            write = function(field, value)
                local grad = GetThreshold(index, "gradient", nil)()
                if type(grad) ~= "table" then
                    grad = {}
                    SetThreshold(index, "gradient")(grad)
                end
                grad[field] = value
            end,
        }, nil, fillRows)
    end

    fillRows[#fillRows + 1] = grid:Note("Blizzard reports the count, and on this "
        .. "patch it may arrive as a protected value that no addon may read. "
        .. "This addon never reads it: each band is a bar whose range is set to "
        .. "the number you chose, and the game itself decides whether the count "
        .. "has crossed it. That is why it works at all.")

    fillRows[#fillRows + 1] = grid:Note("Leave the texture empty and the fill "
        .. "wears the backdrop's, so the bar reads as one object. This reaches "
        .. "buff bars adopted from Blizzard's Cooldown Manager as well, so the "
        .. "two kinds of bar on one row look like one design.")

    grid:Section("Cooldown sweep", "look-sweep")

    Colour("Colour", "swipeColor")
    Slide("Opacity", "swipeAlpha", 0, 1, 0.05, Percent, 100)
    Switch("Leading edge", "showEdge", "The bright line the sweep drags")

    -- Text ------------------------------------------------------------------
    --
    -- Generated, not written out three times. Every element gets the SAME
    -- seven controls, because "the countdown can be moved but the stack count
    -- cannot" is the kind of arbitrary limit that sends people looking for
    -- another addon.
    local textRows = {}

    for _, element in ipairs(ns.TEXT_ELEMENTS) do
        local group = element.key
        local rows = {}

        rows[#rows + 1] = grid:Section(element.label, "text-" .. group)

        rows[#rows + 1] = UI.Toggle(grid:FullRow("Show", { controlWidth = 124 }),
            GetIn(group, "show"),
            function(value) SetIn(group, "show")(value); Apply() end)

        rows[#rows + 1] = UI.MediaPicker(
            grid:FullRow("Font", { controlWidth = 190, icon = "media-font" }),
            "font",
            GetIn(group, "font"), SetIn(group, "font"), Apply,
            "Same as everywhere")

        rows[#rows + 1] = UI.Slider(grid:FullRow("Size", { controlWidth = 124 }), {
            get = GetIn(group, "size"), set = SetIn(group, "size"),
            min = 0, max = 32, step = 1, format = AutoSize, apply = Apply,
        })

        rows[#rows + 1] = UI.Swatch(grid:FullRow("Colour", { controlWidth = 124 }),
            function()
                local colour = GetIn(group, "color")() or { 1, 1, 1 }
                return colour[1], colour[2], colour[3]
            end,
            function(r, g, b) SetIn(group, "color")({ r, g, b }) end,
            Apply)

        rows[#rows + 1] = UI.Dropdown(grid:FullRow("Outline",
            { controlWidth = 124, icon = "media-outline" }),
            ns.Media.OUTLINES, GetIn(group, "outline"), SetIn(group, "outline"),
            { apply = Apply })

        rows[#rows + 1] = UI.Dropdown(grid:FullRow("Position", { controlWidth = 124 }),
            ns.TEXT_ANCHORS, GetIn(group, "anchor"), SetIn(group, "anchor"),
            { apply = Apply })

        rows[#rows + 1] = UI.Slider(grid:FullRow("Nudge across", { controlWidth = 124 }), {
            get = GetIn(group, "x"), set = SetIn(group, "x"),
            min = -30, max = 30, step = 1, apply = Apply,
        })
        rows[#rows + 1] = UI.Slider(grid:FullRow("Nudge up", { controlWidth = 124 }), {
            get = GetIn(group, "y"), set = SetIn(group, "y"),
            min = -30, max = 30, step = 1, apply = Apply,
        })

        if element.barOnly then textRows[#textRows + 1] = rows end
    end

    -- Effects -----------------------------------------------------------------
    --
    -- The half of a cooldown display people actually read out of the corner of
    -- their eye. Every one of these is off by default: a screen that flashes
    -- at you before you asked it to is the reason some addons get uninstalled
    -- in the first fight.
    local function FxGet(key)
        return function()
            local _, cfg = Workspace:Current()
            return cfg and cfg.effects and cfg.effects[key]
        end
    end
    local function FxSet(key)
        return function(value)
            local _, cfg = Workspace:Current()
            if cfg and cfg.effects then cfg.effects[key] = value end
        end
    end
    -- `icon` goes on the switch that turns an EFFECT on, not on the colour and
    -- size rows under it. That is what makes it readable: the mark says "this
    -- is the effect", and the unmarked rows beneath it are plainly its
    -- settings rather than four more effects.
    local function FxSwitch(label, key, sublabel, icon)
        return UI.Toggle(grid:FullRow(label,
            { controlWidth = 124, sublabel = sublabel, icon = icon }),
            FxGet(key), function(value) FxSet(key)(value); Apply() end)
    end
    -- scale: what the DISPLAY multiplies by, so a typed number can be
    -- divided back. A percentage shows 85 and stores 0.85.
    local function FxSlide(label, key, min, max, step, format, scale)
        return UI.Slider(grid:FullRow(label, { controlWidth = 124 }), {
            get = FxGet(key), set = FxSet(key),
            min = min, max = max, step = step, format = format,
            scale = scale, apply = Apply,
        })
    end
    local function FxColour(label, key)
        return UI.Swatch(grid:FullRow(label, { controlWidth = 124 }),
            function()
                local _, cfg = Workspace:Current()
                local colour = cfg and cfg.effects and cfg.effects[key] or { 1, 1, 1 }
                return colour[1], colour[2], colour[3]
            end,
            function(r, g, b)
                local _, cfg = Workspace:Current()
                if cfg and cfg.effects then cfg.effects[key] = { r, g, b } end
            end,
            Apply)
    end
    local function Seconds(v)
        if v <= 0 then return "off" end
        return string.format("%ds", v)
    end

    grid:Tab("Behaviour")
    grid:Section("When it comes back", "fx-ready")

    FxSwitch("Flash", "readyFlash", "A pulse the moment the cooldown ends",
        "effect-flash")
    FxSlide("How many", "readyPulses", 1, 5, 1)
    FxColour("Flash colour", "readyColor")
    FxSwitch("Keep an edge while it is up", "readyGlow", nil, "effect-edge")
    FxSwitch("Only in combat", "readyGlowCombatOnly")
    FxColour("Edge colour", "glowColor")
    FxSlide("Edge thickness", "glowSize", 1, 5, 1)
    grid:Note("Blizzard's Cooldown Manager is asked whether the spell is on a "
        .. "real cooldown, so the global cooldown never sets any of this off.")

    grid:Section("Nag and warn", "fx-nag")

    -- The nag is a slider rather than a switch - zero means off - so its mark
    -- goes on the row that IS the nag.
    UI.Slider(grid:FullRow("Remind me after",
        { controlWidth = 124, icon = "effect-nag" }), {
        get = FxGet("reminderAfter"), set = FxSet("reminderAfter"),
        min = 0, max = 20, step = 1, format = Seconds, apply = Apply,
    })
    FxColour("Reminder colour", "reminderColor")
    grid:Note("A spell that has been ready this long IN COMBAT starts pulsing. "
        .. "For the defensive you keep forgetting.")

    FxSlide("Last seconds", "lowWarn", 0, 20, 1, Seconds)
    FxColour("Warning colour", "lowColor")
    grid:Note("Applies to the auras this addon clocks itself, where the "
        .. "remaining time is a number we own. Blizzard's frames do not hand "
        .. "one out on this patch, so their icons do not carry it.")

    FxSwitch("Glow while the aura is up", "activeGlow", nil, "effect-glow")
    FxColour("Aura colour", "activeColor")

    FxSwitch("Glow in the refresh window", "pandemicGlow", nil, "effect-glow")
    FxColour("Refresh colour", "pandemicColor")
    -- The dependency is stated rather than discovered. "I switched it on and
    -- nothing happens" is otherwise a question with no answer on this screen.
    grid:Note("The tail of an aura where recasting it wastes nothing. This "
        .. "addon does not work the window out - it cannot, the numbers are "
        .. "protected on this patch - it asks Blizzard, which already knows. "
        .. "So it only lights for the spells you have switched pandemic alerts "
        .. "on for in Blizzard's own Cooldown Manager settings.")
    FxSwitch("Grey out on cooldown", "dimOnCooldown")
    FxSlide("How grey", "dimAmount", 0.2, 1, 0.05, Percent, 100)
    FxSlide("Pulse speed", "pulseSpeed", 0.4, 2.5, 0.1,
        function(v) return string.format("%.1f", v) end)

    -- Visibility ------------------------------------------------------------
    local function RuleGet(key)
        return function()
            local _, cfg = Workspace:Current()
            return cfg and cfg.show and cfg.show[key]
        end
    end
    local function RuleSet(key)
        return function(value)
            local _, cfg = Workspace:Current()
            if cfg and cfg.show then cfg.show[key] = value end
        end
    end

    grid:Section("When to show it", "show-rules")

    UI.Dropdown(grid:FullRow("Show", { controlWidth = 150 }),
        ns.SHOW_MODES, RuleGet("mode"), RuleSet("mode"), { apply = Apply })

    local ruleRows = {}
    local function Rule(row)
        ruleRows[#ruleRows + 1] = row
        return row
    end

    -- The four conditions carry their mark for the same reason the six places
    -- below do: they are one kind of thing, four times, and the word is the
    -- only thing telling them apart.
    Rule(UI.Dropdown(grid:FullRow("Combat",
        { controlWidth = 150, icon = "cond-combat" }),
        ns.SHOW_COMBAT, RuleGet("combat"), RuleSet("combat"), { apply = Apply }))
    Rule(UI.Dropdown(grid:FullRow("Group",
        { controlWidth = 150, icon = "cond-group" }),
        ns.SHOW_GROUP, RuleGet("group"), RuleSet("group"), { apply = Apply }))
    Rule(UI.Dropdown(grid:FullRow("Target",
        { controlWidth = 150, icon = "cond-target" }),
        ns.SHOW_TARGET, RuleGet("target"), RuleSet("target"), { apply = Apply }))
    Rule(UI.Dropdown(grid:FullRow("Rested",
        { controlWidth = 150, icon = "cond-rested" }),
        ns.SHOW_RESTING, RuleGet("resting"), RuleSet("resting"), { apply = Apply }))

    -- One switch per place, not a multi-select: six switches you can see the
    -- state of beat one control you have to open to find out what is in it.
    for _, place in ipairs(ns.SHOW_WHERE) do
        Rule(UI.Toggle(grid:FullRow(place.text,
            { controlWidth = 124, icon = place.icon }),
            function()
                local _, cfg = Workspace:Current()
                local where = cfg and cfg.show and cfg.show.where
                return where and where[place.key] and true or false
            end,
            function(value)
                local _, cfg = Workspace:Current()
                if not (cfg and cfg.show) then return end
                cfg.show.where = cfg.show.where or {}
                -- FALSE, never nil: the defaults are re-applied on every load
                -- and a missing key would come back as "allowed" - unticking
                -- a place would silently undo itself on the next reload.
                cfg.show.where[place.key] = value and true or false
                Apply()
            end))
    end

    Rule(UI.Slider(grid:FullRow("Otherwise", { controlWidth = 124 }), {
        get = RuleGet("hiddenAlpha"), set = RuleSet("hiddenAlpha"),
        min = 0, max = 1, step = 0.05, apply = Apply,
        format = function(v)
            if v <= 0 then return "gone" end
            return string.format("%d%%", math.floor(v * 100 + 0.5))
        end,
    }))

    local ruleNote = grid:Note("", 26)

    local function RefreshRules()
        local _, cfg = Workspace:Current()
        if not cfg then return end

        local on = (cfg.show and cfg.show.mode) == "rules"
        for _, row in ipairs(ruleRows) do row:SetRelevant(on) end

        local why = ns.Visibility:Explain(cfg)
        ruleNote:SetText(why and ("|cffff7a3dRight now:|r " .. why)
            or "|cff888888Every rule has to agree. One you have not set cannot "
            .. "be the reason something is missing.|r")
    end

    -- Reuse ---------------------------------------------------------------
    grid:Tab("Reuse")
    grid:Section("Reuse")
    grid:Note("Sizes, spacing and colours only. Which spells a bar holds and "
        .. "how many rows it has always stay with that bar.")

    -- Somewhere to start. Thirty settings is what people ask for, and nobody
    -- wants to build a look out of thirty settings from nothing.
    local lookRow = grid:FullRow("Start from", { controlWidth = 130 })
    local lookPicker = UI.Picker(lookRow.slot, {
        width = 130, height = 22, emptyText = "a ready-made look",
        current = function() return nil end,
        items = function()
            local items = {}
            for _, look in ipairs(ns.BUILT_IN_LOOKS) do
                items[#items + 1] = { text = look.name, value = look.name }
            end
            return items
        end,
        onSelect = function(name)
            local index = Workspace:Current()
            if Bars:ApplyLook(name, index) then
                ns.Print("Applied the", name, "look.")
            end
            Apply()
            ns.Options:Refresh()
        end,
    })
    lookPicker:SetPoint("RIGHT", lookRow.slot, "RIGHT", 0, 0)
    lookRow.Refresh = function()
        lookPicker.label:SetText("a ready-made look")
    end

    local copyRow = grid:FullRow("Copy from", { controlWidth = 130 })
    local copyPicker = UI.Picker(copyRow.slot, {
        width = 130, height = 22, emptyText = "another bar",
        current = function() return nil end,
        items = function()
            local items = {}
            local current = Workspace:Current()
            for index, cfg in ipairs(Bars:All()) do
                if index ~= current then
                    items[#items + 1] = {
                        text = cfg.name, value = index,
                        onClick = nil,
                    }
                end
            end
            return items
        end,
        onSelect = function(index)
            local target = Workspace:Current()
            if Bars:CopyStyleFrom(index, target) then
                ns.Print("Took the look of", Bars:Get(index).name)
            end
            ns.Options:Refresh()
        end,
    })
    copyPicker:SetPoint("RIGHT", copyRow.slot, "RIGHT", 0, 0)
    copyRow.Refresh = function()
        copyPicker.label:SetText("another bar")
    end

    local presetRow = grid:FullRow("Preset",
        { controlWidth = 130, icon = "preset-apply" })
    local presetPicker = UI.Picker(presetRow.slot, {
        width = 130, height = 22, emptyText = "apply a preset",
        current = function() return nil end,
        items = function()
            local items = {}
            for _, name in ipairs(Bars:PresetNames()) do
                items[#items + 1] = {
                    text = name, value = name,
                    onDelete = function()
                        Bars:DeletePreset(name)
                        ns.Print("Deleted the preset", name)
                        ns.Options:Refresh()
                    end,
                }
            end
            if #items == 0 then
                items[1] = { text = "no presets saved yet", value = nil,
                    onClick = function() end }
            end
            return items
        end,
        onSelect = function(name)
            if name and Bars:ApplyPreset(name, (Workspace:Current())) then
                ns.Print("Applied the preset", name)
            end
            ns.Options:Refresh()
        end,
    })
    presetPicker:SetPoint("RIGHT", presetRow.slot, "RIGHT", 0, 0)
    presetRow.Refresh = function()
        presetPicker.label:SetText("apply a preset")
    end

    local saveRow = grid:FullRow("Save as",
        { controlWidth = 130, icon = "preset-save" })
    local saveInput
    saveInput = UI.Input(saveRow.slot, 130, function(text)
        if Bars:SavePreset(text, (Workspace:Current())) then
            -- Cleared here rather than in Refresh: a Refresh-time clear would
            -- also fire for every unrelated redraw and eat what is being typed.
            saveInput:SetText("")
            ns.Print("Saved the preset", text)
            ns.Options:Refresh()
        else
            ns.Print("Give the preset a name first.")
        end
    end, false, "preset name")
    saveInput:SetPoint("RIGHT", saveRow.slot, "RIGHT", 0, 0)

    grid:Layout()

    pane.Refresh = function()
        local _, cfg = Workspace:Current()
        if not cfg then return end

        -- Whether anything on this bar is bar SHAPED, which is not the same
        -- question as whether the bar is. Build mode can turn one cell in a
        -- row of icons into a tracking bar - and while this asked only about
        -- cfg.kind, doing that gave you a cell whose width, name and fill
        -- settings were all hidden on the page that owns it.
        local isBar = cfg.kind == "bar"
        if not isBar and cfg.cellOpts then
            for _, opts in pairs(cfg.cellOpts) do
                if opts.kind == "bar" then isBar = true break end
            end
        end

        iconRow:SetRelevant(cfg.kind ~= "bar")
        barWRow:SetRelevant(isBar)
        barHRow:SetRelevant(isBar)
        iconPlaceRow:SetRelevant(isBar)

        for _, region in ipairs(fillRows) do
            region.dkSkip = not isBar
            region:SetShown(isBar)
        end

        -- AFTER the section pass, and computed from scratch rather than read
        -- back off dkSkip. A flag left over from the last refresh is how a row
        -- that was hidden once stays hidden for the rest of the session.
        for _, group in ipairs(gradientGroups) do
            local shown = group.on() and (isBar or not group.gated) and true or false
            for _, row in ipairs(group.rows) do
                row.dkSkip = not shown
                row:SetShown(shown)
            end
        end

        RefreshArrangement()
        RefreshRules()

        -- The spell name only exists on a bar-shaped cell, so its whole
        -- section - heading included - goes away on an icon bar rather than
        -- sitting there greyed out. Section headers are not rows and have no
        -- SetRelevant, so the flag the layout actually reads is set directly.
        for _, rows in ipairs(textRows) do
            for _, region in ipairs(rows) do
                region.dkSkip = not isBar
                region:SetShown(isBar)
            end
        end

        strip:Layout()
        strip:Select(grid.tab)
        grid:Layout()
        grid:Refresh()
    end

    return pane
end

---------------------------------------------------------------------------
-- The right column itself: a header, and whichever pane belongs there
---------------------------------------------------------------------------
-- parent is the whole column, not an inset frame: the heading has to sit in
-- the window's header band so its rule lands on the same line as the ones in
-- the other two columns.
---------------------------------------------------------------------------
-- One cell, on its own
--
-- Everything here FOLLOWS THE BAR until you touch it. The moment you do, this
-- cell owns that setting and stops following - which is why there is a Reset
-- rather than twenty little "inherit" switches: one clear way back beats a
-- panel where every row has two states to read.
--
-- The overrides belong to the SLOT, not to the spell in it, exactly like the
-- scale and the nudge. Drag Bone Shield somewhere else and the red stays
-- where it was. That is the rule from 4.10.0 and it is why a layout can be
-- handed to another character at all.
---------------------------------------------------------------------------
function Workspace:BuildCellPane(parent, width)
    local pane = CreateFrame("Frame", nil, parent)
    pane:SetAllPoints(parent)

    local grid = UI.Page(pane, width, { tooltipNotes = true })

    local function Cell()
        local _, cfg = Workspace:Current()
        return cfg, Workspace.cell
    end

    -- Reads the cell's own value, or the bar's while it is still following.
    local function Get(key, fallback)
        return function()
            local cfg, index = Cell()
            if not (cfg and index) then return fallback end
            local opts = ns.Layout.CellOpts(cfg, index)
            local look = opts and opts.look
            if look and look[key] ~= nil then return look[key] end
            if cfg[key] ~= nil then return cfg[key] end
            return fallback
        end
    end
    local function Set(key)
        return function(value)
            local cfg, index = Cell()
            if cfg and index then ns.Bars:SetCellLook(cfg, index, key, value) end
        end
    end

    -- scale: what the DISPLAY multiplies by, so a typed number can be
    -- divided back. A percentage shows 85 and stores 0.85.
    local function Slide(label, key, min, max, step, format, scale)
        return UI.Slider(grid:FullRow(label, { controlWidth = 124 }), {
            get = Get(key, min), set = Set(key),
            min = min, max = max, step = step, format = format,
            scale = scale, apply = Apply,
        })
    end
    local function Switch(label, key, sublabel)
        return UI.Toggle(grid:FullRow(label, { controlWidth = 124, sublabel = sublabel }),
            Get(key, false), function(value) Set(key)(value); Apply() end)
    end
    local function Colour(label, key)
        return UI.Swatch(grid:FullRow(label, { controlWidth = 124 }),
            function()
                local colour = Get(key, { 0, 0, 0 })()
                return colour[1], colour[2], colour[3]
            end,
            function(r, g, b) Set(key)({ r, g, b }) end,
            Apply)
    end

    local function Percent(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end

    -- THE GRADIENT TRIO, per cell. It was missing here entirely: the whole-bar
    -- pane grew it and this one did not, so a cell that had been given its own
    -- fill colour could not be given the ramp that goes with it. Owner: "wenn
    -- ich bei den individuellen optionen von einer bar bin, fehlt die verlauf
    -- option". The MODEL already carried it - all three keys are in
    -- ns.CELL_LOOK_KEYS - so this was a control that had simply never been
    -- built, which is the quietest kind of missing feature.
    --
    -- COPY BEFORE WRITE, and this is the trap. Get() falls through to the
    -- BAR's table while this cell is still following it, so writing a field
    -- into what it returns would edit the bar - and therefore every other cell
    -- on it - from a panel headed "This one only". The stack bands two
    -- sections down already copy for exactly this reason.
    local gradientGroups = {}

    local function GradientRows(key)
        local function Read()
            local grad = Get(key, nil)()
            return type(grad) == "table" and grad or nil
        end
        local function Field(field, fallback)
            return function()
                local grad = Read()
                if not grad then return fallback end
                local value = grad[field]
                if value == nil then return fallback end
                return value
            end
        end
        local function Write(field, value)
            local cfg, index = Cell()
            if not (cfg and index) then return end

            local from = Read() or {}
            local colour = from.color or { 1, 1, 1 }
            local copy = {
                on = from.on and true or false,
                direction = from.direction or "right",
                color = { colour[1] or 1, colour[2] or 1, colour[3] or 1 },
            }
            copy[field] = value
            ns.Bars:SetCellLook(cfg, index, key, copy)
        end

        local group = { rows = {}, on = Field("on", false) }

        UI.Toggle(grid:FullRow("Gradient", { controlWidth = 124 }),
            Field("on", false),
            function(value) Write("on", value); Apply() end)

        group.rows[#group.rows + 1] = UI.Swatch(
            grid:FullRow("Second colour", { controlWidth = 124 }),
            function()
                local colour = Field("color", { 1, 1, 1 })()
                return colour[1], colour[2], colour[3]
            end,
            function(r, g, b) Write("color", { r, g, b }) end,
            Apply)

        group.rows[#group.rows + 1] = UI.Dropdown(
            grid:FullRow("Runs", { controlWidth = 150 }),
            ns.GRADIENT_DIRECTIONS, Field("direction", "right"),
            function(value) Write("direction", value) end, { apply = Apply })

        gradientGroups[#gradientGroups + 1] = group
    end

    grid:Section("This one only")
    grid:Note("Every setting here follows the bar until you change it. After "
        .. "that this cell keeps its own, and Reset below hands it all back.")

    -- Size and shape, which already had per-cell overrides of their own and
    -- are read from the same place rather than duplicated.
    UI.Slider(grid:FullRow("Size", { controlWidth = 124, icon = "cell-scale" }), {
        get = function()
            local cfg, index = Cell()
            local opts = cfg and index and ns.Layout.CellOpts(cfg, index)
            return (opts and opts.scale) or 1
        end,
        set = function(value)
            local cfg, index = Cell()
            if not (cfg and index) then return end
            ns.Layout.EnsureCellOpts(cfg, index).scale = value
            ns.Layout.TidyCellOpts(cfg, index)
        end,
        min = 0.5, max = 3, step = 0.05, apply = Apply,
        format = function(v) return string.format("%.2f", v) end,
    })

    UI.Dropdown(grid:FullRow("Shape", { controlWidth = 160 }), {
        { value = "",     text = "Follow the bar" },
        { value = "icon", text = "Icon" },
        { value = "bar",  text = "Tracking bar" },
    }, function()
        local cfg, index = Cell()
        local opts = cfg and index and ns.Layout.CellOpts(cfg, index)
        return (opts and opts.kind) or ""
    end, function(value)
        local cfg, index = Cell()
        if not (cfg and index) then return end
        ns.Layout.EnsureCellOpts(cfg, index).kind = (value ~= "" and value) or nil
        ns.Layout.TidyCellOpts(cfg, index)
    end, { apply = Apply })

    grid:Section("Bar fill", "cell-fill")
    Colour("Colour", "fillColor")
    GradientRows("fillGradient")
    Slide("Opacity", "fillAlpha", 0, 1, 0.05, Percent, 100)
    UI.MediaPicker(grid:FullRow("Texture",
        { controlWidth = 190, icon = "media-texture" }), "statusbar",
        Get("fillTexture", ""), Set("fillTexture"), Apply)
    -- The same one-of-four the bar has, so a cell override reads as the same
    -- question with the same answers rather than as a different setting.
    UI.Dropdown(grid:FullRow("Direction", { controlWidth = 190 }),
        ns.FILL_DIRECTIONS, Get("fillDirection", "right"),
        Set("fillDirection"), { apply = Apply })
    Switch("Fill up", "fillGrow", "Grow as time passes instead of draining")
    Switch("Spark", "showSpark", "A bright line on the moving edge")
    Switch("Charge marks", "chargeMarks", "One line per charge boundary")

    grid:Section("Border and backdrop", "cell-edge")
    Slide("Thickness", "borderSize", 0, 4, 1)
    Colour("Border colour", "borderColor")
    GradientRows("borderGradient")
    Colour("Backdrop colour", "backdropColor")
    GradientRows("backdropGradient")
    Slide("Backdrop opacity", "backdropAlpha", 0, 1, 0.05, Percent, 100)

    -- Stack colours per cell, because this is the setting that most obviously
    -- belongs to ONE spell: Bone Shield wants bands and the two bars under it
    -- do not.
    grid:Section("Stack colours", "cell-stacks")
    grid:Note("Same as the bar's, but for this cell alone. Below the lowest "
        .. "band it wears the fill colour above. 0 switches a band off.")

    local BAND_COLOURS = {
        { 0.85, 0.15, 0.15 },
        { 1.00, 0.78, 0.20 },
        { 0.30, 0.85, 0.35 },
    }

    local function Bands()
        local cfg, index = Cell()
        if not (cfg and index) then return {} end
        local opts = ns.Layout.CellOpts(cfg, index)
        local look = opts and opts.look
        -- The bar's list is the starting point, copied on first edit so the
        -- two can never share a table.
        return (look and look.stackThresholds) or cfg.stackThresholds or {}
    end
    local function WriteBand(slot, field, value)
        local cfg, index = Cell()
        if not (cfg and index) then return end

        local list = {}
        for position, entry in ipairs(Bands()) do
            list[position] = {
                value = entry.value, alpha = entry.alpha,
                color = { (entry.color or {})[1] or 0,
                          (entry.color or {})[2] or 0,
                          (entry.color or {})[3] or 0 },
            }
        end
        list[slot] = list[slot] or { value = 0, color = BAND_COLOURS[slot] }
        list[slot][field] = value
        ns.Bars:SetCellLook(cfg, index, "stackThresholds", list)
    end

    for slot = 1, 3 do
        UI.Slider(grid:FullRow("From", { controlWidth = 124 }), {
            get = function() return (Bands()[slot] or {}).value or 0 end,
            set = function(value) WriteBand(slot, "value", value) end,
            min = 0, max = 20, step = 1, apply = Apply,
            format = function(v)
                if (v or 0) < 1 then return "off" end
                return string.format("%d+", v)
            end,
        })
        local fallback = BAND_COLOURS[slot]
        UI.Swatch(grid:FullRow("Colour", { controlWidth = 124 }),
            function()
                local colour = (Bands()[slot] or {}).color or fallback
                return colour[1], colour[2], colour[3]
            end,
            function(r, g, b) WriteBand(slot, "color", { r, g, b }) end,
            Apply)
    end

    grid:Section("Back to normal")
    local reset = UI.Button(grid:FullRow("", { controlWidth = 200 }).slot,
        "Follow the bar again", 200, function()
            local cfg, index = Cell()
            if not (cfg and index) then return end
            ns.Bars:ClearCellLook(cfg, index)
            Apply()
        end)
    reset:SetPoint("RIGHT", reset:GetParent(), "RIGHT", 0, 0)
    reset:SetIcon("ui-reset")

    pane.Refresh = function()
        for _, group in ipairs(gradientGroups) do
            local shown = group.on() and true or false
            for _, row in ipairs(group.rows) do
                row.dkSkip = not shown
                row:SetShown(shown)
            end
        end
        grid:Refresh()
        grid:Layout()
    end

    return pane
end

function Workspace:BuildSide(parent, pad)
    local side = CreateFrame("Frame", nil, parent)
    side:SetAllPoints(parent)

    local width = parent:GetWidth() - pad * 2

    -- The column header, on the same 62 as the other two.
    --
    -- It replaced a breadcrumb. The path was three words above the title that
    -- between them named the same place the title already named, and its
    -- deepest step was unreachable half the time. What is actually needed here
    -- is two things: WHAT am I editing, and HOW DO I GET OUT - so that is
    -- what is here.
    local title = UI.Label(side, "", UI.FS.card, C.text)
    title:SetPoint("TOPLEFT", side, "TOPLEFT", pad, -16)
    title:SetWidth(width - 96)       -- never under Done and the close cross
    title:SetWordWrap(false)

    local subtitle = UI.Eyebrow(side, "")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    subtitle:SetWidth(width - 96)
    subtitle:SetWordWrap(false)

    -- Done steps back out to the spell list, which is where the work is.
    --
    -- There is NO close cross here. The window already draws one in its own
    -- top-right corner - which, this column being the rightmost, is exactly
    -- where the design puts it. Adding a second one landed two crosses on top
    -- of each other, which is what it looked like.
    local done = UI.Button(side, "Done", 56, function()
        Workspace:ShowSpells()
    end, "primary")
    done:SetPoint("TOPRIGHT", side, "TOPRIGHT", -(pad + 24 + 8), -18)

    local host = CreateFrame("Frame", nil, side)
    host:SetPoint("TOPLEFT", side, "TOPLEFT", pad, -(UI.HEADER_H + 16))
    host:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -pad, pad)

    local spells = self:BuildSpellPane(host, width)
    local options = self:BuildOptionsPane(host, width)
    local cellPane = self:BuildCellPane(host, width)

    side.Refresh = function()
        local bars = Bars:Count() > 0
        local onOptions = Workspace.mode == "options" and bars
        local onCell = Workspace.mode == "cell" and bars and Workspace.cell ~= nil
        -- Called for its clamping side effect as well as for the config: it
        -- pulls the selection back into range after a bar is deleted.
        local _, cfg = Workspace:Current()

        spells:SetShown(not onOptions and not onCell)
        options:SetShown(onOptions)
        cellPane:SetShown(onCell)

        -- Done is the way back to the spell list, so it has nothing to do on
        -- the spell list itself.
        done:SetShown(onOptions or onCell)

        if onCell then
            local spellID = cfg and cfg.cells and cfg.cells[Workspace.cell]
            title:SetText(spellID and (ns.SpellName(spellID) or "This cell")
                or string.format("Cell %d", Workspace.cell))
            subtitle:SetText(ns.Bars:CellHasLook(cfg, Workspace.cell)
                and "Its own look"
                or "Following the bar")
            cellPane.Refresh()
        elseif onOptions then
            title:SetText(cfg and cfg.name or "Bar")
            -- What KIND of bar and how full it is, which is the pair of facts
            -- that tells you whether you are on the right one.
            subtitle:SetText(string.format("%s - %d cells",
                (cfg and cfg.kind == "bar") and "Tracking bar" or "Icon bar",
                cfg and Bars:CellCount(cfg) or 0))
            options.Refresh()
        else
            title:SetText("Cooldown manager")
            subtitle:SetText(cfg and Workspace.cell
                and string.format("Cell %d of \"%s\" - pick a spell",
                    Workspace.cell, cfg.name)
                or "Pick a cell on a bar first")
            spells.Refresh()
        end
    end

    return side
end
