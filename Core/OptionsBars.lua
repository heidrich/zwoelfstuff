---------------------------------------------------------------------------
-- OptionsBars - the bar workspace.
--
-- Shaped like an app, not a settings page: the bar is the thing you are
-- working on, so it sits in the middle at its real size. What you select is
-- what the inspector on the right edits - a cell if you clicked one,
-- otherwise the bar itself.
--
-- The canvas IS the bar: same rows, same columns, same order, same sizes.
-- Nothing has to be translated from a list of numbers into a shape.
---------------------------------------------------------------------------
local _, ns = ...

local UI = ns.UI
local C = UI.C
local Bars = ns.Bars

ns.OptionsBars = {}
local Workspace = ns.OptionsBars

---------------------------------------------------------------------------
-- Selection
---------------------------------------------------------------------------
function Workspace:Current()
    local index = self.index or 1
    if index > Bars:Count() then index = Bars:Count() end
    if index < 1 then index = 1 end
    self.index = index
    return index, Bars:Get(index)
end

function Workspace:Select(index)
    self.index = index
    self.cell = nil          -- a different bar means the old cell is gone
    ns.Options:Refresh()
end

function Workspace:SelectCell(cell)
    self.cell = cell
    ns.Options:Refresh()
end

local function Apply()
    Bars:Changed((Workspace:Current()))
    ns.Options:Refresh()
end

---------------------------------------------------------------------------
-- Spell picker
--
-- Sourced from Blizzard's Cooldown Manager: anything in this list is already
-- tracked by the game, so its timing is guaranteed to work.
---------------------------------------------------------------------------
local Picker = {}
ns.BarSpellPicker = Picker

local PICK_ROW_H = 26

local function PickerRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(PICK_ROW_H)

    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints(row)
    row.hl:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.15)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.name = UI.Label(row, "", 12, C.text)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
    row.name:SetWordWrap(false)

    row.meta = UI.Label(row, "", 11, C.textFaint)
    row.meta:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    row.meta:SetJustifyH("RIGHT")
    row.meta:SetWidth(140)
    row.name:SetPoint("RIGHT", row.meta, "LEFT", -8, 0)

    return row
end

function Picker:Create()
    if self.frame then return end

    local frame = CreateFrame("Frame", "DKstuffSpellPicker", UIParent)
    frame:SetSize(430, 500)
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

    local title = UI.Label(frame, "Add a cooldown", 16, C.text)
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

    local search = UI.Input(frame, 398, function() Picker:Fill() end, false)
    search:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -62)
    search.input:SetScript("OnTextChanged", function() Picker:Fill() end)
    frame.search = search

    local list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -94)
    list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 74)
    UI.Fill(list, "BACKGROUND", C.sidebarBg)

    local scroll, content = UI.ScrollArea(list, 370)
    frame.content = content
    frame.scroll = scroll

    local manual = UI.Input(frame, 100, function(text)
        local spellID = tonumber(text)
        if spellID and spellID > 0 then
            Picker:Assign(spellID)
        else
            ns.Print("Enter a numeric spell ID.")
        end
    end, true)
    manual:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 40)

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

    local labels = {}
    for _, viewer in ipairs(ns.CDM.VIEWERS) do labels[viewer.key] = viewer.label end

    local y, shown = 0, 0
    for _, entry in ipairs(catalogue) do
        local hit = query == ""
            or entry.name:lower():find(query, 1, true)
            or tostring(entry.spellID):find(query, 1, true)

        if hit then
            shown = shown + 1
            local row = frame.rows[shown]
            if not row then
                row = PickerRow(frame.content)
                frame.rows[shown] = row
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

            y = y - PICK_ROW_H
        end
    end

    for index = shown + 1, #frame.rows do frame.rows[index]:Hide() end
    frame.content:SetHeight(math.max(1, -y))
    if frame.scroll.Update then frame.scroll.Update() end

    frame.footer:SetText(string.format("%d of %d from your Cooldown Manager",
        shown, #catalogue))
end

function Picker:Open(barIndex, cell)
    self:Create()
    self.barIndex, self.cell = barIndex, cell

    local cfg = Bars:Get(barIndex)
    self.frame.target:SetText(string.format("into cell %d of \"%s\"",
        cell, cfg and cfg.name or "?"))

    self.frame.search.input:SetText("")
    self:Fill()
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    self.frame:Show()
    self.frame.search.input:SetFocus()
end

---------------------------------------------------------------------------
-- Canvas - the bar, at its real size
---------------------------------------------------------------------------
function Workspace:BuildCanvas(parent)
    local canvas = CreateFrame("Frame", nil, parent)
    canvas:SetAllPoints(parent)

    -- Title row
    local title = UI.Label(canvas, "", 17, C.text)
    title:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, 0)

    local rename = UI.Input(canvas, 150, function(text)
        local _, cfg = Workspace:Current()
        if cfg and text ~= "" then
            cfg.name = text
            ns.Options:Refresh()
        end
    end, false)
    rename:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -100, 2)

    local unlock = UI.Button(canvas, "Unlock", 90, function()
        ns.Print("Moving the bar comes with the on-screen display.")
    end)
    unlock:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", 0, 2)

    -- The bar itself, centred in the space below the title.
    local stage = CreateFrame("Frame", nil, canvas)
    stage:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -44)
    stage:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", 0, -44)
    stage:SetHeight(230)
    UI.Fill(stage, "BACKGROUND", C.sidebarBg, 0.5)

    local grid = UI.CellGrid(stage, {
        cellSize = function()
            local _, cfg = Workspace:Current()
            if not cfg then return 40, 40 end
            if cfg.kind == "bar" then return cfg.barWidth, cfg.barHeight end
            return cfg.iconSize, cfg.iconSize
        end,
        gaps = function()
            local _, cfg = Workspace:Current()
            if not cfg then return 4, 4 end
            return cfg.spacing, cfg.lineSpacing
        end,
        rows    = function() local _, cfg = Workspace:Current() return cfg and cfg.rows or 1 end,
        columns = function() local _, cfg = Workspace:Current() return cfg and cfg.columns or 1 end,
        content = function(cell)
            local _, cfg = Workspace:Current()
            return cfg and cfg.cells[cell]
        end,
        selected = function() return Workspace.cell end,
        -- Clicking a cell selects it; the inspector on the right is where it
        -- is then filled or cleared. One click, one meaning.
        onPick  = function(cell) Workspace:SelectCell(cell) end,
        onClear = function(cell)
            Bars:ClearCell((Workspace:Current()), cell)
            ns.Options:Refresh()
        end,
        onMove  = function(from, to)
            Bars:MoveCell((Workspace:Current()), from, to)
            Workspace.cell = to
            ns.Options:Refresh()
        end,
    })
    grid:SetPoint("CENTER", stage, "CENTER", 0, 0)

    local hint = UI.Hint(canvas, "")
    hint:SetPoint("TOPLEFT", stage, "BOTTOMLEFT", 0, -10)
    hint:SetWidth(420)

    -- Shape, right under the bar it shapes.
    local shape = CreateFrame("Frame", nil, canvas)
    shape:SetPoint("TOPLEFT", stage, "BOTTOMLEFT", 0, -34)
    shape:SetSize(420, 30)

    local rowsLabel = UI.Label(shape, "Rows", 12, C.textDim)
    rowsLabel:SetPoint("LEFT", shape, "LEFT", 0, 0)

    local function Counter(anchorTo, offset, get, set)
        local holder = CreateFrame("Frame", nil, shape)
        holder:SetSize(90, 24)
        holder:SetPoint("LEFT", anchorTo, "RIGHT", offset, 0)

        local value = UI.Label(holder, "", 13, C.text)
        value:SetPoint("CENTER", holder, "CENTER", 0, 0)
        value:SetWidth(34)
        value:SetJustifyH("CENTER")

        local function Step(delta)
            set(math.max(1, math.min(12, get() + delta)))
            ns.Options:Refresh()
        end

        local minus = UI.Button(holder, "-", 24, function() Step(-1) end)
        minus:SetHeight(22)
        minus:SetPoint("LEFT", holder, "LEFT", 0, 0)

        local plus = UI.Button(holder, "+", 24, function() Step(1) end)
        plus:SetHeight(22)
        plus:SetPoint("RIGHT", holder, "RIGHT", 0, 0)

        holder.Refresh = function()
            value:SetText(tostring(get()))
            minus:SetEnabled(get() > 1)
            plus:SetEnabled(get() < 12)
        end
        return holder
    end

    local rowsCounter = Counter(rowsLabel, 8,
        function() local _, cfg = Workspace:Current() return cfg and cfg.rows or 1 end,
        function(value)
            local index, cfg = Workspace:Current()
            if cfg then Bars:SetGrid(index, value, cfg.columns) end
        end)

    local colsLabel = UI.Label(shape, "Columns", 12, C.textDim)
    colsLabel:SetPoint("LEFT", rowsCounter, "RIGHT", 24, 0)

    local colsCounter = Counter(colsLabel, 8,
        function() local _, cfg = Workspace:Current() return cfg and cfg.columns or 1 end,
        function(value)
            local index, cfg = Workspace:Current()
            if cfg then Bars:SetGrid(index, cfg.rows, value) end
        end)

    canvas.Refresh = function()
        local _, cfg = Workspace:Current()
        if not cfg then return end

        title:SetText(cfg.name)
        rename:SetEnabled(true)
        rowsCounter.Refresh()
        colsCounter.Refresh()
        grid.Refresh()

        local filled = 0
        for cell = 1, Bars:CellCount(cfg) do
            if cfg.cells[cell] then filled = filled + 1 end
        end
        if filled == 0 then
            hint:SetText("Click a cell, then choose a cooldown on the right.")
        else
            hint:SetText(string.format(
                "%d of %d cells filled. Drag a cell onto another to swap them.",
                filled, Bars:CellCount(cfg)))
        end
    end

    return canvas
end

---------------------------------------------------------------------------
-- Inspector - what is selected
---------------------------------------------------------------------------
function Workspace:BuildInspector(parent, width)
    local inspector = CreateFrame("Frame", nil, parent)
    inspector:SetAllPoints(parent)

    -- Cell half -----------------------------------------------------------
    local cellPane = CreateFrame("Frame", nil, inspector)
    cellPane:SetAllPoints(inspector)

    local cellTitle = UI.Label(cellPane, "", 13, C.accent)
    cellTitle:SetPoint("TOPLEFT", cellPane, "TOPLEFT", 0, 0)

    local preview = CreateFrame("Frame", nil, cellPane)
    preview:SetSize(48, 48)
    preview:SetPoint("TOPLEFT", cellPane, "TOPLEFT", 0, -26)
    UI.Fill(preview, "BACKGROUND", C.control)
    local previewEdge = ns.CreateBorder(preview, 1, "OVERLAY")
    previewEdge:SetColor(0, 0, 0, 1)
    local previewIcon = preview:CreateTexture(nil, "ARTWORK")
    previewIcon:SetPoint("TOPLEFT", preview, "TOPLEFT", 1, -1)
    previewIcon:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -1, 1)
    previewIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local spellName = UI.Label(cellPane, "", 13, C.text)
    spellName:SetPoint("TOPLEFT", preview, "TOPRIGHT", 10, -4)
    spellName:SetWidth(width - 70)

    local spellMeta = UI.Label(cellPane, "", 11, C.textFaint)
    spellMeta:SetPoint("TOPLEFT", spellName, "BOTTOMLEFT", 0, -4)

    local chooseBtn = UI.Button(cellPane, "Choose cooldown", width, function()
        if Workspace.cell then Picker:Open((Workspace:Current()), Workspace.cell) end
    end, "primary")
    chooseBtn:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 0, -14)

    local clearBtn = UI.Button(cellPane, "Clear this cell", width, function()
        if Workspace.cell then
            Bars:ClearCell((Workspace:Current()), Workspace.cell)
            ns.Options:Refresh()
        end
    end)
    clearBtn:SetPoint("TOPLEFT", chooseBtn, "BOTTOMLEFT", 0, -6)

    local deselect = UI.Button(cellPane, "Done", width, function()
        Workspace:SelectCell(nil)
    end)
    deselect:SetPoint("TOPLEFT", clearBtn, "BOTTOMLEFT", 0, -6)

    -- Bar half -------------------------------------------------------------
    local barPane = CreateFrame("Frame", nil, inspector)
    barPane:SetAllPoints(inspector)

    -- Full-width rows throughout: the inspector is a single narrow column, so
    -- the two-column grid the wide pages use would put a 118px control into a
    -- 103px slot and push the label off its own row.
    local grid = UI.Page(barPane, width)

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
        return UI.Slider(grid:FullRow(label, { controlWidth = 118 }), {
            get = Get(key), set = Set(key),
            min = min, max = max, step = step, format = format, apply = Apply,
        })
    end

    grid:Section("Bar")
    UI.Toggle(grid:FullRow("Shown", { controlWidth = 118 }), Get("enabled"), function(value)
        Set("enabled")(value)
        Apply()
    end)

    local iconRow = Slide("Icon size", "iconSize", 16, 100, 2)
    local barWRow = Slide("Width", "barWidth", 60, 400, 5)
    local barHRow = Slide("Height", "barHeight", 10, 60, 2)
    Slide("Spacing", "spacing", 0, 24, 1)
    Slide("Row gap", "lineSpacing", 0, 24, 1)

    grid:Section("Look", "look")
    Slide("Scale", "scale", 0.4, 2.5, 0.05,
        function(v) return string.format("%.2f", v) end)
    Slide("Opacity", "alpha", 0.1, 1, 0.05,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end)
    Slide("Border", "borderSize", 0, 4, 1)
    UI.Swatch(grid:FullRow("Border colour", { controlWidth = 118 }),
        function()
            local _, cfg = Workspace:Current()
            local c = cfg and cfg.borderColor or { 0, 0, 0 }
            return c[1], c[2], c[3]
        end,
        function(r, g, b)
            local _, cfg = Workspace:Current()
            if cfg then cfg.borderColor = { r, g, b } end
        end,
        Apply)

    grid:Layout()

    inspector.Refresh = function()
        local _, cfg = Workspace:Current()
        if not cfg then
            cellPane:Hide()
            barPane:Hide()
            return
        end

        local cell = Workspace.cell
        cellPane:SetShown(cell ~= nil)
        barPane:SetShown(cell == nil)

        if cell then
            local spellID = cfg.cells[cell]
            cellTitle:SetText(string.format("CELL %d", cell))

            if spellID then
                local texture = ns.SpellTexture(spellID)
                previewIcon:SetTexture(texture or ns.WHITE)
                previewIcon:SetDesaturated(not texture)
                previewIcon:Show()
                spellName:SetText(ns.SpellName(spellID) or "unknown to this client")
                spellMeta:SetText(tostring(spellID))
                chooseBtn:SetText("Replace")
                clearBtn:SetEnabled(true)
            else
                previewIcon:Hide()
                spellName:SetText("|cff888888empty|r")
                spellMeta:SetText("")
                chooseBtn:SetText("Choose cooldown")
                clearBtn:SetEnabled(false)
            end
            return
        end

        local isBar = cfg.kind == "bar"
        iconRow:SetRelevant(not isBar)
        barWRow:SetRelevant(isBar)
        barHRow:SetRelevant(isBar)
        grid:Refresh()
    end

    return inspector
end
