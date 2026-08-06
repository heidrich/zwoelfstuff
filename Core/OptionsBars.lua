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

local CARD_PAD  = 14
local HEADER_H  = 34
local SLIDER_H  = 20
local CARD_GAP  = 12
local ADD_H     = 34

---------------------------------------------------------------------------
-- Selection
--
-- One bar is current and, inside it, at most one cell. The right column
-- always acts on that pair, which is what makes "click a cell, click a
-- spell" work without any drag, dialog or confirmation.
---------------------------------------------------------------------------
Workspace.mode = "spells"          -- "spells" | "options"

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
    -- clicking did nothing.
    if cell then self.mode = "spells" end
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
    local number = UI.Label(card, "", 11, C.textFaint)
    number:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -12)

    local title = UI.Label(card, "", 13.5, C.text)
    title:SetPoint("LEFT", number, "RIGHT", 8, 0)
    title:SetWidth(width - 180)      -- never under the header's two actions
    title:SetWordWrap(false)

    -- Two-step, because one stray click would otherwise throw away a bar the
    -- user spent time filling, and there is no undo.
    local remove
    remove = UI.GhostButton(card, "Delete", function()
        if not card.dkIndex then return end

        if not card.armed then
            card.armed = true
            remove:SetText("Sure?")
            remove:SetBaseColor(C.danger)
            C_Timer.After(4, function()
                if not card.armed then return end
                card.armed = false
                remove:SetText("Delete")
                remove:SetBaseColor(C.textFaint)
            end)
            return
        end

        card.armed = false
        remove:SetText("Delete")
        remove:SetBaseColor(C.textFaint)
        Bars:Remove(card.dkIndex)
        Workspace.cell = nil
        ns.Options:Refresh()
    end, C.textFaint)
    remove:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD + 6, -10)

    local options = UI.GhostButton(card, "Options", function()
        if card.dkIndex then Workspace:ShowOptions(card.dkIndex) end
    end)
    options:SetPoint("RIGHT", remove, "LEFT", -2, 0)

    local headerLine = UI.Separator(card)
    headerLine:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -HEADER_H)
    headerLine:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, -HEADER_H)

    -- The bar itself -------------------------------------------------------
    local stage = CreateFrame("Frame", nil, card)
    stage:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -(HEADER_H + 12))
    stage:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD, -(HEADER_H + 12))
    stage:SetHeight(1)

    local function Cfg()
        return card.dkIndex and Bars:Get(card.dkIndex)
    end

    local grid = UI.CellGrid(stage, {
        cellSize = function()
            local cfg = Cfg()
            if not cfg then return 40, 40 end
            if cfg.kind == "bar" then return cfg.barWidth, cfg.barHeight end
            return cfg.iconSize, cfg.iconSize
        end,
        gaps = function()
            local cfg = Cfg()
            if not cfg then return 4, 4 end
            return cfg.spacing, cfg.lineSpacing
        end,
        rows    = function() local cfg = Cfg() return cfg and cfg.rows or 1 end,
        columns = function() local cfg = Cfg() return cfg and cfg.columns or 1 end,
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
        onMove = function(from, to)
            Bars:MoveCell(card.dkIndex, from, to)
            Workspace:SelectCell(card.dkIndex, to)
        end,
    })
    grid:SetPoint("TOPLEFT", stage, "TOPLEFT", 0, 0)

    -- Shape ----------------------------------------------------------------
    local shape = CreateFrame("Frame", nil, card)
    shape:SetHeight(SLIDER_H)
    shape:SetPoint("LEFT", card, "LEFT", CARD_PAD, 0)
    shape:SetPoint("RIGHT", card, "RIGHT", -CARD_PAD, 0)

    local sliderW = math.floor((width - CARD_PAD * 2 - 24) / 2)

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
    rows:SetPoint("LEFT", shape, "LEFT", 0, 0)
    rows:SetWidth(sliderW)

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
    columns:SetPoint("RIGHT", shape, "RIGHT", 0, 0)
    columns:SetWidth(sliderW)

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

        -- Any other action disarms a half-pressed Delete. Cards are reused for
        -- whatever bar sits at their position, so an armed one must never be
        -- handed on to a different bar.
        if card.armed then
            card.armed = false
            remove:SetText("Delete")
            remove:SetBaseColor(C.textFaint)
        end

        number:SetText(tostring(card.dkIndex) .. ".")
        title:SetText(cfg.name)

        local gridHeight = grid.Refresh()

        -- A wide grid must not run out of the card. Scaling the preview keeps
        -- the arrangement honest - it is still the real shape, just not at
        -- real size - and the drag maths follows the scale on its own.
        local available = width - CARD_PAD * 2
        local natural = math.max(1, grid:GetWidth())
        local fit = math.min(1, available / natural)
        grid:SetScale(fit)
        gridHeight = gridHeight * fit

        stage:SetHeight(math.max(1, gridHeight))
        shape:ClearAllPoints()
        shape:SetPoint("TOPLEFT", stage, "BOTTOMLEFT", 0, -14)
        shape:SetPoint("TOPRIGHT", stage, "BOTTOMRIGHT", 0, -14)

        rows.Refresh()
        columns.Refresh()

        local active = Workspace.index == card.dkIndex
        card:SetActive(active)
        title:SetTextColor(
            active and C.text[1] or C.textDim[1],
            active and C.text[2] or C.textDim[2],
            active and C.text[3] or C.textDim[3])
        options:SetBaseColor((active and Workspace.mode == "options")
            and C.accent or C.textDim)

        local height = HEADER_H + 12 + gridHeight + 14 + SLIDER_H + CARD_PAD
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

    local addWidth = math.floor((cardWidth - 10) / 2)

    local addIcons = UI.Button(content, "+   Icon bar", addWidth,
        function() Add("icon") end, "soft")
    addIcons:SetHeight(ADD_H)

    local addBars = UI.Button(content, "+   Tracking bar", addWidth,
        function() Add("bar") end, "soft")
    addBars:SetHeight(ADD_H)

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

        addIcons:ClearAllPoints()
        addIcons:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        addBars:ClearAllPoints()
        addBars:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
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

    local target = UI.Label(pane, "", 11, C.accent)
    target:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
    target:SetWidth(width)
    target:SetWordWrap(false)

    local search = UI.Input(pane, width, function() end, false, "Search")
    search:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -18)
    search:SetHeight(24)

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
    listHost:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 52)

    local scroll, content = UI.ScrollArea(listHost, width - 8)

    local manual = UI.Input(pane, 92, function(text)
        local spellID = tonumber(text)
        if spellID and spellID > 0 then
            Workspace:Assign(spellID)
        else
            ns.Print("Enter a numeric spell ID.")
        end
    end, true, "ID")
    manual:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 0, 22)

    local manualHint = UI.Hint(pane, "add by spell ID")
    manualHint:SetPoint("LEFT", manual, "RIGHT", 8, 0)

    local footer = UI.Label(pane, "", 10.5, C.textFaint)
    footer:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 0, 4)
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

        -- Within a group: what you can cast first, what you cannot after.
        -- Greyed entries are worth listing but not worth scrolling past.
        for _, group in ipairs(GROUPS) do
            table.sort(buckets[group.key], function(a, b)
                local aKnown, bKnown = a.known ~= false, b.known ~= false
                if aKnown ~= bKnown then return aKnown end
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
                    heading:SetText(group.label .. "   " .. #bucket)
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

                    if not known then
                        row.meta:SetText(string.format("not talented   %d",
                            entry.spellID))
                    elseif cell then
                        row.meta:SetText(string.format("on this bar, cell %d   %d",
                            cell, entry.spellID))
                    elseif entry.parent then
                        -- An aura: say what actually drives it, because that
                        -- is the surprising part and the thing to correct if
                        -- the name above it is wrong. Unless the name IS the
                        -- glowing ability, in which case there is nothing to
                        -- name and "Defile on Defile" only reads as a fault.
                        local driver = entry.route == "engine" and "aura" or "proc"
                        row.meta:SetText(entry.spellID ~= entry.parent
                            and string.format("%s on %s   %s", driver,
                                ns.SpellName(entry.parent) or entry.parent,
                                entry.duration and (entry.duration .. "s") or "?s")
                            or string.format("%s   %s", driver,
                                entry.duration and (entry.duration .. "s") or "?s"))
                    else
                        row.meta:SetText(tostring(entry.spellID))
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

        footer:SetText(string.format("%d of %d cooldowns", matched, #catalogue))
    end

    -- Typing filters as you type; there is nothing to submit.
    search.input:SetScript("OnTextChanged", function()
        search.UpdateGhost()
        Fill()
    end)

    pane.Fill = Fill
    pane.Refresh = function()
        local _, cfg = Workspace:Current()
        if not cfg then
            target:SetText("Add a bar first")
        elseif Workspace.cell then
            target:SetText(string.format("Click a spell to fill cell %d of %s",
                Workspace.cell, cfg.name))
        else
            target:SetText(string.format("Click a spell to add it to %s", cfg.name))
        end
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

    local body = CreateFrame("Frame", nil, pane)
    body:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0)

    local grid = UI.Page(body, width)

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
    local function Slide(label, key, min, max, step, format)
        return UI.Slider(grid:FullRow(label, { controlWidth = 124 }), {
            get = Get(key), set = Set(key),
            min = min, max = max, step = step, format = format, apply = Apply,
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

    -- A size of 0 means "work it out from the cell", so the slider says that
    -- rather than showing a zero nobody would read as automatic.
    local function AutoSize(v)
        if v <= 0 then return "auto" end
        return string.format("%d", v)
    end
    local function Percent(v)
        return string.format("%d%%", math.floor(v * 100 + 0.5))
    end

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
        { value = "icon", text = "Icon bar" },
        { value = "bar",  text = "Tracking bar" },
    }, Get("kind"), Set("kind"), { apply = Apply })

    UI.Toggle(grid:FullRow("Shown", { controlWidth = 124 }), Get("enabled"),
        function(value)
            Set("enabled")(value)
            Apply()
        end)

    -- Size ----------------------------------------------------------------
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

    local nameShowRow = Switch("Spell name", "showName")
    local nameSizeRow = Slide("Name size", "nameSize", 0, 24, 1, AutoSize)
    local nameColRow  = Colour("Name colour", "nameColor")
    Slide("Spacing", "spacing", 0, 24, 1)
    Slide("Row gap", "lineSpacing", 0, 24, 1)
    Slide("Scale", "scale", 0.4, 2.5, 0.05,
        function(v) return string.format("%.2f", v) end)

    -- Looks ---------------------------------------------------------------
    grid:Section("Icon")

    Slide("Opacity", "alpha", 0.1, 1, 0.05, Percent)
    Slide("Crop", "iconZoom", 0, 0.2, 0.01, Percent)
    grid:Note("Blizzard's icon art has a border baked into the file. Cropping "
        .. "cuts it off; at 0 you see the whole thing, frame and all.")

    grid:Section("Edge")

    Slide("Border", "borderSize", 0, 4, 1)
    Colour("Border colour", "borderColor")
    Switch("Backdrop", "backdrop", "A plate behind the icon")
    Colour("Backdrop colour", "backdropColor")
    Slide("Backdrop opacity", "backdropAlpha", 0, 1, 0.05, Percent)

    grid:Section("Cooldown sweep")

    Colour("Sweep colour", "swipeColor")
    Slide("Sweep opacity", "swipeAlpha", 0, 1, 0.05, Percent)
    Switch("Leading edge", "showEdge", "The bright line the sweep drags")

    grid:Section("Numbers")

    Switch("Countdown", "showCountdown")
    Slide("Countdown size", "countdownSize", 0, 30, 1, AutoSize)
    Colour("Countdown colour", "countdownColor")
    UI.Dropdown(grid:FullRow("Countdown at", { controlWidth = 124 }),
        ns.TEXT_ANCHORS, Get("countdownAnchor"), Set("countdownAnchor"),
        { apply = Apply })

    Switch("Stacks and charges", "showStacks")
    Slide("Stack size", "stackSize", 0, 24, 1, AutoSize)
    Colour("Stack colour", "stackColor")

    -- Reuse ---------------------------------------------------------------
    grid:Section("Reuse")
    grid:Note("Sizes, spacing and colours only. Which spells a bar holds and "
        .. "how many rows it has always stay with that bar.")

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

    local presetRow = grid:FullRow("Preset", { controlWidth = 130 })
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

    local saveRow = grid:FullRow("Save as", { controlWidth = 130 })
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

        local isBar = cfg.kind == "bar"
        iconRow:SetRelevant(not isBar)
        barWRow:SetRelevant(isBar)
        barHRow:SetRelevant(isBar)
        iconPlaceRow:SetRelevant(isBar)
        nameShowRow:SetRelevant(isBar)
        nameSizeRow:SetRelevant(isBar)
        nameColRow:SetRelevant(isBar)

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
function Workspace:BuildSide(parent, pad)
    local side = CreateFrame("Frame", nil, parent)
    side:SetAllPoints(parent)

    local width = parent:GetWidth() - pad * 2

    local title = UI.Label(side, "", 15, C.text)
    title:SetPoint("TOPLEFT", side, "TOPLEFT", pad, -18)
    title:SetWidth(width - 56)       -- never under the Done button
    title:SetWordWrap(false)

    local subtitle = UI.Label(side, "", 11, C.textDim)
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    subtitle:SetWidth(width - 56)
    subtitle:SetWordWrap(false)

    -- Below the close button, not beside it: both want the top right corner
    -- and the close button owns it.
    local back = UI.GhostButton(side, "Done", function()
        Workspace:ShowSpells()
    end)
    back:SetPoint("TOPRIGHT", side, "TOPRIGHT", -pad + 6, -40)

    local host = CreateFrame("Frame", nil, side)
    host:SetPoint("TOPLEFT", side, "TOPLEFT", pad, -(UI.HEADER_H + 16))
    host:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -pad, pad)

    local spells = self:BuildSpellPane(host, width)
    local options = self:BuildOptionsPane(host, width)

    side.Refresh = function()
        local onOptions = Workspace.mode == "options" and Bars:Count() > 0
        local _, cfg = Workspace:Current()

        spells:SetShown(not onOptions)
        options:SetShown(onOptions)
        back:SetShown(onOptions)

        if onOptions then
            title:SetText(cfg and cfg.name or "Bar")
            subtitle:SetText("How this bar looks")
            options.Refresh()
        else
            title:SetText("Spells")
            subtitle:SetText("From your Cooldown Manager")
            spells.Refresh()
        end
    end

    return side
end
