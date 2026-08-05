---------------------------------------------------------------------------
-- OptionsBars - the bar editor.
--
-- The order on this page is the order you work in: pick the bar, set how big
-- the grid is, see the grid, fill it. Everything that only changes how it
-- looks comes after that, because you do it once and then never again.
--
-- The grid on this page is the bar. Same rows, same columns, same order - so
-- arranging it here is arranging it on screen, with no mental translation
-- from a list of settings to a shape.
---------------------------------------------------------------------------
local _, ns = ...

local UI = ns.UI
local C = UI.C
local Bars = ns.Bars

ns.OptionsBars = {}
local Page = ns.OptionsBars

---------------------------------------------------------------------------
-- Which bar is being edited
---------------------------------------------------------------------------
function Page:Current()
    local index = self.index or 1
    if index > Bars:Count() then index = Bars:Count() end
    if index < 1 then index = 1 end
    self.index = index
    return index, Bars:Get(index)
end

function Page:Select(index)
    self.index = index
    ns.Options:Refresh()
end

---------------------------------------------------------------------------
-- Spell picker
--
-- Sourced from Blizzard's Cooldown Manager, because that is where the spells
-- actually come from - anything in this list is guaranteed to have working
-- timing. A manual ID field covers the rest.
---------------------------------------------------------------------------
local Picker = {}
ns.BarSpellPicker = Picker

local ROW_H = 24

local function PickerRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)

    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints(row)
    row.hl:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.15)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.name = UI.Label(row, "", 12, C.text)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetWordWrap(false)

    row.meta = UI.Label(row, "", 11, C.textFaint)
    row.meta:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.meta:SetJustifyH("RIGHT")
    row.meta:SetWidth(150)
    row.name:SetPoint("RIGHT", row.meta, "LEFT", -8, 0)

    return row
end

function Picker:Create()
    if self.frame then return end

    local frame = CreateFrame("Frame", "DKstuffSpellPicker", UIParent)
    frame:SetSize(440, 520)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    UI.Fill(frame, "BACKGROUND", C.windowBg, 0.98)
    local edge = ns.CreateBorder(frame, 1, "BORDER")
    edge:SetColor(0.22, 0.24, 0.29, 1)

    local title = UI.Label(frame, "Choose a spell", 16, C.text)
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)

    frame.target = UI.Label(frame, "", 11, C.accent)
    frame.target:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    frame.target:SetWordWrap(false)

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(26, 26)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    local closeLabel = UI.Label(close, "X", 13, C.textDim)
    closeLabel:SetPoint("CENTER", close, "CENTER", 0, 0)
    close:SetScript("OnClick", function() frame:Hide() end)

    local search = UI.Input(frame, 408, function() Picker:Fill() end, false)
    search:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -62)
    search.input:SetScript("OnTextChanged", function() Picker:Fill() end)
    frame.search = search

    local list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -94)
    list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 78)
    UI.Fill(list, "BACKGROUND", C.sidebarBg)

    local scroll = CreateFrame("ScrollFrame", nil, list, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", list, "TOPLEFT", 2, -2)
    scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -24, 2)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(380, 1)
    scroll:SetScrollChild(content)
    frame.content = content

    -- Manual entry, for anything the Cooldown Manager does not carry.
    local manual = UI.Input(frame, 110, function(text)
        local spellID = tonumber(text)
        if spellID and spellID > 0 then
            Picker:Assign(spellID)
        else
            ns.Print("Enter a numeric spell ID.")
        end
    end, true)
    manual:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 42)

    local manualHint = UI.Hint(frame, "or a spell ID, then Enter")
    manualHint:SetPoint("LEFT", manual, "RIGHT", 10, 0)

    frame.footer = UI.Label(frame, "", 11, C.textFaint)
    frame.footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 16)
    frame.footer:SetWordWrap(false)

    frame.rows = {}
    self.frame = frame

    table.insert(UISpecialFrames, "DKstuffSpellPicker")
end

function Picker:Assign(spellID)
    if not self.barIndex or not self.cell then return end
    Bars:SetCell(self.barIndex, self.cell, spellID)
    self.frame:Hide()
    ns.Options:Refresh()
end

function Picker:Fill()
    local frame = self.frame
    if not frame then return end

    local query = (frame.search.input:GetText() or ""):lower()
    local catalogue = ns.CDM:Catalogue()

    local matches = {}
    for _, entry in ipairs(catalogue) do
        if query == ""
            or entry.name:lower():find(query, 1, true)
            or tostring(entry.spellID):find(query, 1, true) then
            matches[#matches + 1] = entry
        end
    end

    local labels = {}
    for _, viewer in ipairs(ns.CDM.VIEWERS) do labels[viewer.key] = viewer.label end

    local y = 0
    for index, entry in ipairs(matches) do
        local row = frame.rows[index]
        if not row then
            row = PickerRow(frame.content)
            frame.rows[index] = row
        end

        row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", frame.content, "TOPRIGHT", 0, y)

        row.icon:SetTexture(entry.icon or ns.WHITE)
        row.icon:SetDesaturated(entry.icon == nil)
        row.name:SetText(entry.name)
        row.meta:SetText(string.format("%s  |cff666666%d|r",
            labels[entry.viewer] or "", entry.spellID))

        row:SetScript("OnClick", function() Picker:Assign(entry.spellID) end)
        row:Show()
        y = y - ROW_H
    end

    for index = #matches + 1, #frame.rows do frame.rows[index]:Hide() end
    frame.content:SetHeight(math.max(1, -y))

    frame.footer:SetText(string.format(
        "%d of %d from Blizzard's Cooldown Manager", #matches, #catalogue))
end

function Picker:Open(barIndex, cell)
    self:Create()
    self.barIndex, self.cell = barIndex, cell

    local cfg = Bars:Get(barIndex)
    self.frame.target:SetText(string.format("Cell %d of \"%s\"", cell, cfg and cfg.name or "?"))

    self.frame.search.input:SetText("")
    self:Fill()
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", UIParent, "CENTER", 290, 0)
    self.frame:Show()
    self.frame.search.input:SetFocus()
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
function Page:Build(page, width)
    -- Bar picker, pinned so it never scrolls away.
    local bar = CreateFrame("Frame", nil, page)
    bar:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    bar:SetSize(width, 30)
    UI.Fill(bar, "BACKGROUND", C.rowBg)

    local picker = UI.Picker(bar, {
        width = 230, height = 24, emptyText = "no bars yet",
        items = function()
            local out = {}
            for index, cfg in ipairs(Bars:All()) do
                out[#out + 1] = {
                    value = index,
                    text  = cfg.name .. (cfg.enabled and "" or "  (off)"),
                    onDelete = function()
                        if Bars:Remove(index) then
                            Page:Select(math.min(index, Bars:Count()))
                        end
                    end,
                }
            end
            return out
        end,
        current  = function() return (Page:Current()) end,
        onSelect = function(value) Page:Select(value) end,
        actions = {
            { text = "+  New icon bar", onClick = function()
                Page:Select(Bars:Add(nil, "icon"))
            end },
            { text = "+  New bar-style bar", onClick = function()
                Page:Select(Bars:Add(nil, "bar"))
            end },
        },
    })
    picker:SetPoint("LEFT", bar, "LEFT", 6, 0)

    local nameInput = UI.Input(bar, 170, function(text)
        local _, cfg = Page:Current()
        if cfg and text ~= "" then
            cfg.name = text
            ns.Options:Refresh()
        end
    end, false)
    nameInput:SetPoint("LEFT", picker, "RIGHT", 10, 0)

    local nameHint = UI.Hint(bar, "rename, then Enter")
    nameHint:SetPoint("LEFT", nameInput, "RIGHT", 10, 0)

    local unlockBtn = UI.Button(bar, "Unlock all", 96, function()
        ns.Print("Positioning comes with the on-screen bars.")
    end)
    unlockBtn:SetHeight(22)
    unlockBtn:SetPoint("RIGHT", bar, "RIGHT", -6, 0)

    -- Body ---------------------------------------------------------------
    local body = CreateFrame("Frame", nil, page)
    body:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -8)
    body:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)

    local grid = UI.Page(body, width)

    local function Get(key)
        return function()
            local _, cfg = Page:Current()
            return cfg and cfg[key]
        end
    end
    local function Set(key)
        return function(value)
            local _, cfg = Page:Current()
            if cfg then cfg[key] = value end
        end
    end
    local function Apply()
        local index = Page:Current()
        Bars:Changed(index)
        ns.Options:Refresh()
    end
    local function Slide(label, key, min, max, step, format)
        return UI.Slider(grid:Row(label), {
            get = Get(key), set = Set(key),
            min = min, max = max, step = step, format = format, apply = Apply,
        })
    end

    -- THE GRID, first, because it is the thing you came here for ----------
    grid:Section("Layout")

    UI.Slider(grid:Row("Rows"), {
        get = function() local _, cfg = Page:Current() return cfg and cfg.rows or 1 end,
        set = function(value)
            local index, cfg = Page:Current()
            if cfg then Bars:SetGrid(index, value, cfg.columns) end
        end,
        min = 1, max = 12, step = 1, apply = function() ns.Options:Refresh() end,
    })
    UI.Slider(grid:Row("Columns"), {
        get = function() local _, cfg = Page:Current() return cfg and cfg.columns or 1 end,
        set = function(value)
            local index, cfg = Page:Current()
            if cfg then Bars:SetGrid(index, cfg.rows, value) end
        end,
        min = 1, max = 12, step = 1, apply = function() ns.Options:Refresh() end,
    })

    local cellGrid = UI.CellGrid(grid.content, {
        cellSize = function()
            local _, cfg = Page:Current()
            if not cfg then return 40, 40 end
            if cfg.kind == "bar" then return cfg.barWidth, cfg.barHeight end
            return cfg.iconSize, cfg.iconSize
        end,
        gaps = function()
            local _, cfg = Page:Current()
            if not cfg then return 4, 4 end
            return cfg.spacing, cfg.lineSpacing
        end,
        rows    = function() local _, cfg = Page:Current() return cfg and cfg.rows or 1 end,
        columns = function() local _, cfg = Page:Current() return cfg and cfg.columns or 1 end,
        content = function(cell)
            local _, cfg = Page:Current()
            return cfg and cfg.cells[cell]
        end,
        onPick  = function(cell) Picker:Open((Page:Current()), cell) end,
        onClear = function(cell)
            Bars:ClearCell((Page:Current()), cell)
            ns.Options:Refresh()
        end,
        onMove  = function(from, to)
            Bars:MoveCell((Page:Current()), from, to)
            ns.Options:Refresh()
        end,
    })
    grid:Wide(cellGrid, 60)

    grid:Note("This is the bar. Click an empty cell to put a spell in it, drag one cell "
        .. "onto another to swap them, right click to clear. Rows and columns re-flow "
        .. "what is already there instead of scrambling it.")

    -- Size and looks, after the part that matters ------------------------
    grid:Section("Size")

    local iconRow = Slide("Icon size", "iconSize", 16, 120, 2)
    local barWRow = Slide("Bar width", "barWidth", 60, 500, 5)
    local barHRow = Slide("Bar height", "barHeight", 10, 60, 2)
    Slide("Spacing", "spacing", 0, 30, 1)
    Slide("Row spacing", "lineSpacing", 0, 30, 1)
    Slide("Scale", "scale", 0.4, 2.5, 0.05,
        function(v) return string.format("%.2f", v) end)
    Slide("Opacity", "alpha", 0.1, 1, 0.05,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end)

    grid:Section("Appearance")
    UI.Toggle(grid:Row("Bar enabled"), Get("enabled"), function(value)
        Set("enabled")(value)
        Apply()
    end)
    Slide("Border thickness", "borderSize", 0, 4, 1)
    UI.Swatch(grid:Row("Border colour"),
        function()
            local _, cfg = Page:Current()
            local c = cfg and cfg.borderColor or { 0, 0, 0 }
            return c[1], c[2], c[3]
        end,
        function(r, g, b)
            local _, cfg = Page:Current()
            if cfg then cfg.borderColor = { r, g, b } end
        end,
        Apply)

    grid:Layout()

    -- Refresh -------------------------------------------------------------
    page.Refresh = function()
        local _, cfg = Page:Current()
        local hasBars = cfg ~= nil

        picker.Refresh()
        nameInput:SetEnabled(hasBars)
        body:SetShown(hasBars)
        if not hasBars then return end

        local isBar = cfg.kind == "bar"
        iconRow:SetRelevant(not isBar)
        barWRow:SetRelevant(isBar)
        barHRow:SetRelevant(isBar)

        -- The grid reports how tall it turned out, so the settings below it
        -- move down as rows are added instead of being written over.
        cellGrid.dkHeight = cellGrid.Refresh() + 10

        grid:Refresh()
    end
end
