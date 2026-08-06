---------------------------------------------------------------------------
-- Widgets - the design system.
--
-- One set of controls, one set of colours, one row geometry, used by every
-- page. Pages declare WHAT they contain; this file decides how it looks.
--
-- Self-built throughout. Blizzard's slider, dropdown and checkbox templates
-- have been renamed repeatedly across expansions, and their look cannot be
-- brought in line with a custom panel anyway. Everything here is drawn from
-- colour textures and font strings, so nothing can break on a template
-- rename and every control matches every other one.
---------------------------------------------------------------------------
local _, ns = ...

local UI = {}
ns.UI = UI

---------------------------------------------------------------------------
-- Tokens
---------------------------------------------------------------------------
local C = {
    windowBg   = { 0.055, 0.060, 0.075 },
    sidebarBg  = { 0.040, 0.044, 0.056 },
    headerBg   = { 0.075, 0.082, 0.100 },
    rowBg      = { 0.098, 0.106, 0.130 },
    rowHover   = { 0.130, 0.140, 0.170 },
    control    = { 0.145, 0.158, 0.190 },
    controlHi  = { 0.190, 0.205, 0.245 },
    line       = { 1, 1, 1, 0.06 },

    accent     = { 1.00, 0.478, 0.239 },  -- DKstuff orange
    accentCool = { 0.494, 0.776, 0.831 },  -- the "DK" cyan

    text       = { 0.90, 0.91, 0.93 },
    textDim    = { 0.55, 0.57, 0.62 },
    textFaint  = { 0.38, 0.40, 0.45 },
    danger     = { 0.85, 0.28, 0.28 },
}
UI.C = C

UI.ROW_H      = 40
UI.ROW_GAP    = 4
UI.SECTION_H  = 34
UI.COL_GAP    = 16

local function Tex(parent, layer, r, g, b, a)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

local function Fill(parent, layer, colour, alpha)
    local t = Tex(parent, layer, colour[1], colour[2], colour[3], alpha or colour[4] or 1)
    t:SetAllPoints(parent)
    return t
end
UI.Fill = Fill

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------
function UI.Label(parent, text, size, colour, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    -- Panel text uses the client's UI font. The number font this used to
    -- take is built for digits over a busy 3D scene and reads cramped and
    -- slightly wrong at every size in a settings window. Numbers drawn ON
    -- icons still use it, which is what it is for.
    ns.StyleUIFont(fs, size or 12, flags or "")
    local c = colour or C.text
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetText(text or "")
    fs:SetJustifyH("LEFT")
    return fs
end

function UI.Hint(parent, text)
    return UI.Label(parent, text, 11, C.textDim)
end

---------------------------------------------------------------------------
-- Button - flat, accent on hover
---------------------------------------------------------------------------
function UI.Button(parent, text, width, onClick, style)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or 100, 26)

    local bg = Fill(btn, "BACKGROUND", style == "primary" and C.accent or C.control,
        style == "primary" and 0.22 or 1)
    local edge = ns.CreateBorder(btn, 1, "BORDER")
    edge:SetColor(1, 1, 1, 0.08)

    local label = UI.Label(btn, text, 12, style == "primary" and C.accent or C.text)
    label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.label = label

    btn:SetScript("OnEnter", function()
        if btn:IsEnabled() then
            bg:SetColorTexture(C.controlHi[1], C.controlHi[2], C.controlHi[3], 1)
            edge:SetColor(C.accent[1], C.accent[2], C.accent[3], 0.5)
        end
    end)
    btn:SetScript("OnLeave", function()
        local base = style == "primary" and C.accent or C.control
        bg:SetColorTexture(base[1], base[2], base[3], style == "primary" and 0.22 or 1)
        edge:SetColor(1, 1, 1, 0.08)
    end)
    if onClick then btn:SetScript("OnClick", onClick) end

    -- SetEnabled exists on Button and still does the input half; only the
    -- greying is ours. Wrapped rather than hooked, because a hook cannot
    -- change what the widget already did and this is not a secure frame.
    local baseSetEnabled = btn.SetEnabled
    btn.SetEnabled = function(self, enabled)
        baseSetEnabled(self, enabled)
        local c = enabled and (style == "primary" and C.accent or C.text) or C.textFaint
        label:SetTextColor(c[1], c[2], c[3])
    end

    btn.SetText = function(_, value) label:SetText(value) end
    return btn
end

---------------------------------------------------------------------------
-- Row - the card every setting sits in
--
-- opts = { sublabel, tall }
-- The control is anchored to row.slot, a right-aligned area of fixed width,
-- so every control in a column lines up no matter what type it is.
---------------------------------------------------------------------------
local CONTROL_W = 150

function UI.Row(parent, text, opts)
    opts = opts or {}
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(opts.tall and 54 or UI.ROW_H)

    row.bg = Fill(row, "BACKGROUND", C.rowBg)

    row.label = UI.Label(row, text, 12, C.text)
    row.label:SetPoint("LEFT", row, "LEFT", 12, opts.sublabel and 7 or 0)
    row.label:SetWordWrap(false)

    if opts.sublabel then
        row.sub = UI.Label(row, opts.sublabel, 10, C.textFaint)
        row.sub:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -2)
        row.sub:SetWordWrap(false)
    end

    row.slot = CreateFrame("Frame", nil, row)
    row.slot:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    row.slot:SetSize(opts.controlWidth or CONTROL_W, row:GetHeight() - 10)

    -- The label must never run under the control.
    row.label:SetPoint("RIGHT", row.slot, "LEFT", -8, 0)

    row.SetRelevant = function(self, relevant)
        self.dkSkip = not relevant
        self:SetShown(relevant)
    end

    return row
end

-- onToggle turns the header into a disclosure: the caption gains a marker
-- and the whole strip becomes clickable. Used to fold away everything that
-- is set once and then never touched again, so the page shows the work
-- rather than the options.
function UI.SectionHeader(parent, text, onToggle, isOpen)
    local header = onToggle and CreateFrame("Button", nil, parent)
        or CreateFrame("Frame", nil, parent)
    header:SetHeight(UI.SECTION_H)

    local caption = text:upper()
    local label = UI.Label(header, caption, 11, C.textDim, "")
    label:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", onToggle and 14 or 2, 8)

    local line = Tex(header, "ARTWORK", C.line[1], C.line[2], C.line[3], C.line[4])
    line:SetPoint("BOTTOMLEFT", label, "BOTTOMRIGHT", 10, 4)
    line:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -2, 8)
    line:SetHeight(1)

    if onToggle then
        local marker = UI.Label(header, "", 10, C.textDim)
        marker:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 2, 8)

        header:SetScript("OnClick", onToggle)
        header:SetScript("OnEnter", function()
            label:SetTextColor(C.text[1], C.text[2], C.text[3])
        end)
        header:SetScript("OnLeave", function()
            label:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
        end)

        header.Refresh = function()
            local open = isOpen()
            marker:SetText(open and "v" or ">")
            label:SetText(caption)
        end
        header.Refresh()
    end

    return header
end

---------------------------------------------------------------------------
-- Toggle - an on/off switch
---------------------------------------------------------------------------
function UI.Toggle(row, get, set)
    local toggle = CreateFrame("Button", nil, row.slot)
    toggle:SetSize(42, 20)
    toggle:SetPoint("RIGHT", row.slot, "RIGHT", 0, 0)

    local track = Fill(toggle, "BACKGROUND", C.control)
    local edge = ns.CreateBorder(toggle, 1, "BORDER")
    edge:SetColor(1, 1, 1, 0.10)

    local knob = Tex(toggle, "ARTWORK", 1, 1, 1, 1)
    knob:SetSize(16, 16)

    toggle.Refresh = function()
        local on = get() and true or false
        knob:ClearAllPoints()
        if on then
            knob:SetPoint("RIGHT", toggle, "RIGHT", -2, 0)
            knob:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
            track:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.22)
        else
            knob:SetPoint("LEFT", toggle, "LEFT", 2, 0)
            knob:SetColorTexture(0.45, 0.47, 0.52, 1)
            track:SetColorTexture(C.control[1], C.control[2], C.control[3], 1)
        end
    end

    toggle:SetScript("OnClick", function()
        set(not get())
        toggle.Refresh()
        ns.Options:Refresh()
    end)

    row.control = toggle
    row.Refresh = toggle.Refresh
    return row
end

---------------------------------------------------------------------------
-- Counter - minus, number, plus
--
-- For whole numbers you count rather than tune: rows, columns, how many of
-- something. A slider is the wrong control for those - it is imprecise for
-- small ranges and it does not read as "add one".
---------------------------------------------------------------------------
function UI.Counter(row, cfg)
    local holder = CreateFrame("Frame", nil, row.slot)
    holder:SetPoint("RIGHT", row.slot, "RIGHT", 0, 0)
    holder:SetSize(96, 24)

    local value = UI.Label(holder, "", 13, C.text)
    value:SetPoint("CENTER", holder, "CENTER", 0, 0)
    value:SetJustifyH("CENTER")
    value:SetWidth(40)

    local function Step(delta)
        local next_ = (cfg.get() or cfg.min) + delta
        if next_ < cfg.min then next_ = cfg.min end
        if next_ > cfg.max then next_ = cfg.max end
        cfg.set(next_)
        if cfg.apply then cfg.apply() end
        ns.Options:Refresh()
    end

    local minus = UI.Button(holder, "-", 26, function() Step(-1) end)
    minus:SetHeight(22)
    minus:SetPoint("LEFT", holder, "LEFT", 0, 0)

    local plus = UI.Button(holder, "+", 26, function() Step(1) end)
    plus:SetHeight(22)
    plus:SetPoint("RIGHT", holder, "RIGHT", 0, 0)

    holder.Refresh = function()
        local current = cfg.get()
        value:SetText(tostring(current or cfg.min))
        minus:SetEnabled((current or cfg.min) > cfg.min)
        plus:SetEnabled((current or cfg.min) < cfg.max)
    end

    row.control = holder
    row.Refresh = holder.Refresh
    return row
end

---------------------------------------------------------------------------
-- Slider - track, thumb and a numeric readout
--
-- Self-built rather than templated: it has to sit inside a fixed control
-- slot and match the rest, and the Blizzard templates do neither.
---------------------------------------------------------------------------
function UI.Slider(row, cfg)
    local BOX = 44
    local slider = CreateFrame("Frame", nil, row.slot)
    slider:SetPoint("RIGHT", row.slot, "RIGHT", 0, 0)
    slider:SetSize(row.slot:GetWidth(), 20)

    local box = CreateFrame("Frame", nil, slider)
    box:SetSize(BOX, 18)
    box:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    Fill(box, "BACKGROUND", C.windowBg)
    local boxEdge = ns.CreateBorder(box, 1, "BORDER")
    boxEdge:SetColor(1, 1, 1, 0.08)

    local value = UI.Label(box, "", 11, C.text)
    value:SetPoint("CENTER", box, "CENTER", 0, 0)
    value:SetJustifyH("CENTER")

    local bar = CreateFrame("Frame", nil, slider)
    bar:SetPoint("LEFT", slider, "LEFT", 0, 0)
    bar:SetPoint("RIGHT", box, "LEFT", -8, 0)
    bar:SetHeight(18)
    bar:EnableMouse(true)

    local track = Tex(bar, "BACKGROUND", 1, 1, 1, 0.10)
    track:SetPoint("LEFT", bar, "LEFT", 0, 0)
    track:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    track:SetHeight(2)

    local fill = Tex(bar, "ARTWORK", C.accent[1], C.accent[2], C.accent[3], 0.9)
    fill:SetPoint("LEFT", bar, "LEFT", 0, 0)
    fill:SetHeight(2)

    local thumb = Tex(bar, "OVERLAY", 1, 1, 1, 1)
    thumb:SetSize(10, 10)

    local function Clamp(v)
        if v < cfg.min then v = cfg.min end
        if v > cfg.max then v = cfg.max end
        -- Snap to the step, then round away the float noise it accumulates.
        v = cfg.min + math.floor((v - cfg.min) / cfg.step + 0.5) * cfg.step
        return math.floor(v * 1000 + 0.5) / 1000
    end

    local function Commit(v)
        cfg.set(Clamp(v))
        if cfg.apply then cfg.apply() end
        slider.Refresh()
    end

    local function FromCursor()
        local scale = bar:GetEffectiveScale()
        local x = select(1, GetCursorPosition()) / scale
        local left, width = bar:GetLeft(), bar:GetWidth()
        if not left or width <= 0 then return end
        local pct = math.max(0, math.min(1, (x - left) / width))
        Commit(cfg.min + pct * (cfg.max - cfg.min))
    end

    bar:SetScript("OnMouseDown", function(self)
        self.dragging = true
        FromCursor()
    end)
    bar:SetScript("OnMouseUp", function(self)
        self.dragging = false
        ns.Options:Refresh()
    end)
    bar:SetScript("OnUpdate", function(self)
        if self.dragging then FromCursor() end
    end)
    bar:SetScript("OnMouseWheel", function(_, delta) Commit(cfg.get() + delta * cfg.step) end)
    bar:EnableMouseWheel(true)

    slider.Refresh = function()
        local current = cfg.get()
        if type(current) ~= "number" then current = cfg.min end
        value:SetText(cfg.format and cfg.format(current) or tostring(current))

        local span = cfg.max - cfg.min
        local pct = span > 0 and ((current - cfg.min) / span) or 0
        local width = math.max(1, bar:GetWidth())
        fill:SetWidth(math.max(1, width * pct))
        thumb:ClearAllPoints()
        thumb:SetPoint("CENTER", bar, "LEFT", width * pct, 0)
    end

    row.control = slider
    row.Refresh = slider.Refresh
    return row
end

---------------------------------------------------------------------------
-- Menu - one shared popup for every dropdown and picker
--
-- A per-dropdown popup would mean one extra frame per option row, and only
-- one can ever be open. Entries optionally carry a delete affordance, and a
-- menu can end in a set of actions ("Add new bar group") below a separator -
-- which is how a picker doubles as its own create/delete surface.
---------------------------------------------------------------------------
local ENTRY_H = 23
local popup

local function GetPopup()
    if popup then return popup end

    popup = CreateFrame("Frame", nil, UIParent)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetClampedToScreen(true)
    popup:Hide()
    Fill(popup, "BACKGROUND", C.headerBg)
    local edge = ns.CreateBorder(popup, 1, "BORDER")
    edge:SetColor(C.accent[1], C.accent[2], C.accent[3], 0.35)
    popup.rows = {}
    popup.divider = Tex(popup, "ARTWORK", 1, 1, 1, 0.10)
    popup.divider:SetHeight(1)
    popup.divider:Hide()

    -- Click-away catcher: a full-screen button one level below the popup.
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(1)
    catcher:Hide()
    catcher:SetScript("OnClick", function() popup:Hide() end)
    popup.catcher = catcher

    popup:SetScript("OnHide", function() catcher:Hide() end)
    return popup
end

-- Closes any open menu. Called when a window that owns one is hidden, so the
-- menu cannot outlive the panel it belongs to.
function UI.ClosePopup()
    if popup then popup:Hide() end
end

local function MenuEntry(menu, index)
    local entry = menu.rows[index]
    if entry then return entry end

    entry = CreateFrame("Button", nil, menu)
    entry:SetHeight(ENTRY_H)

    entry.hl = entry:CreateTexture(nil, "HIGHLIGHT")
    entry.hl:SetAllPoints(entry)
    entry.hl:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.16)

    entry.label = UI.Label(entry, "", 12, C.text)
    entry.label:SetPoint("LEFT", entry, "LEFT", 10, 0)
    entry.label:SetWordWrap(false)

    entry.del = CreateFrame("Button", nil, entry)
    entry.del:SetSize(18, 18)
    entry.del:SetPoint("RIGHT", entry, "RIGHT", -6, 0)
    entry.del.label = UI.Label(entry.del, "x", 12, C.textFaint)
    entry.del.label:SetPoint("CENTER", entry.del, "CENTER", 0, 0)
    entry.del:SetScript("OnEnter", function(self)
        self.label:SetTextColor(C.danger[1], C.danger[2], C.danger[3])
    end)
    entry.del:SetScript("OnLeave", function(self)
        self.label:SetTextColor(C.textFaint[1], C.textFaint[2], C.textFaint[3])
    end)

    menu.rows[index] = entry
    return entry
end

-- spec = { width, items = {{text, value, onClick, onDelete}}, actions = {...},
--          current, anchor = {point, relPoint, x, y} }
local function ShowMenu(owner, spec)
    local menu = GetPopup()
    if menu:IsShown() and menu.owner == owner then
        menu:Hide()
        return
    end

    menu.owner = owner
    menu:ClearAllPoints()
    local anchor = spec.anchor or { "TOPRIGHT", "BOTTOMRIGHT", 0, -2 }
    menu:SetPoint(anchor[1], owner, anchor[2], anchor[3], anchor[4])
    menu:SetWidth(math.max(owner:GetWidth(), spec.width or 0))

    local y, index = -4, 0

    local function AddEntry(item, isAction)
        index = index + 1
        local entry = MenuEntry(menu, index)
        entry:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, y)
        entry:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, y)

        entry.label:SetText(item.text)
        local active = (not isAction) and item.value ~= nil and item.value == spec.current
        local colour = isAction and C.accent or (active and C.accent or C.text)
        entry.label:SetTextColor(colour[1], colour[2], colour[3])

        if item.onDelete then
            entry.label:SetPoint("RIGHT", entry.del, "LEFT", -4, 0)
            entry.del:Show()
            entry.del:SetScript("OnClick", function()
                menu:Hide()
                item.onDelete()
            end)
        else
            entry.label:SetPoint("RIGHT", entry, "RIGHT", -10, 0)
            entry.del:Hide()
        end

        entry:SetScript("OnClick", function()
            menu:Hide()
            item.onClick()
        end)
        entry:Show()
        y = y - ENTRY_H
    end

    for _, item in ipairs(spec.items or {}) do AddEntry(item, false) end

    if spec.actions and #spec.actions > 0 then
        y = y - 5
        menu.divider:ClearAllPoints()
        menu.divider:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, y + 2)
        menu.divider:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -8, y + 2)
        menu.divider:Show()
        for _, item in ipairs(spec.actions) do AddEntry(item, true) end
    else
        menu.divider:Hide()
    end

    for i = index + 1, #menu.rows do menu.rows[i]:Hide() end

    menu:SetHeight(-y + 4)
    menu.catcher:Show()
    menu:SetFrameLevel(menu.catcher:GetFrameLevel() + 10)
    menu:Show()
end

---------------------------------------------------------------------------
-- The button half of a dropdown, without the row wrapper
---------------------------------------------------------------------------
function UI.MenuButton(parent, width, height)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height or 22)

    local bg = Fill(button, "BACKGROUND", C.control)
    local edge = ns.CreateBorder(button, 1, "BORDER")
    edge:SetColor(1, 1, 1, 0.10)

    button.label = UI.Label(button, "", 12, C.text)
    button.label:SetPoint("LEFT", button, "LEFT", 10, 0)
    button.label:SetPoint("RIGHT", button, "RIGHT", -20, 0)
    button.label:SetWordWrap(false)

    local arrow = UI.Label(button, "v", 9, C.textDim)
    arrow:SetPoint("RIGHT", button, "RIGHT", -8, 0)

    button:SetScript("OnEnter", function()
        bg:SetColorTexture(C.controlHi[1], C.controlHi[2], C.controlHi[3], 1)
        edge:SetColor(C.accent[1], C.accent[2], C.accent[3], 0.45)
    end)
    button:SetScript("OnLeave", function()
        bg:SetColorTexture(C.control[1], C.control[2], C.control[3], 1)
        edge:SetColor(1, 1, 1, 0.10)
    end)

    return button
end

---------------------------------------------------------------------------
-- Dropdown - a plain value picker inside a settings row
---------------------------------------------------------------------------
function UI.Dropdown(row, options, get, set, cfg)
    cfg = cfg or {}
    local button = UI.MenuButton(row.slot, cfg.width or row.slot:GetWidth())
    button:SetPoint("RIGHT", row.slot, "RIGHT", 0, 0)

    -- Options may be a table or a function returning one, so a list that
    -- depends on live data (spec lines, group names) stays current.
    local function Options()
        return type(options) == "function" and options() or options
    end

    button:SetScript("OnClick", function()
        local items = {}
        for _, option in ipairs(Options()) do
            items[#items + 1] = {
                text = option.text, value = option.value,
                onClick = function()
                    set(option.value)
                    if cfg.apply then cfg.apply() end
                    ns.Options:Refresh()
                end,
            }
        end
        ShowMenu(button, { items = items, current = get(), width = cfg.menuWidth })
    end)

    button.Refresh = function()
        local current = get()
        local text = cfg.emptyText or "-"
        for _, option in ipairs(Options()) do
            if option.value == current then text = option.text break end
        end
        button.label:SetText(text)
    end

    row.control = button
    row.Refresh = button.Refresh
    return row
end

---------------------------------------------------------------------------
-- Picker - a dropdown that also creates and deletes its own entries
--
-- cfg = { items() -> {{text, value, onDelete}}, current(), onSelect(value),
--         actions = {{text, onClick}}, emptyText, width, menuWidth }
---------------------------------------------------------------------------
function UI.Picker(parent, cfg)
    local button = UI.MenuButton(parent, cfg.width or 240, cfg.height or 24)

    button:SetScript("OnClick", function()
        local items = {}
        for _, item in ipairs(cfg.items()) do
            items[#items + 1] = {
                text = item.text, value = item.value, onDelete = item.onDelete,
                onClick = function() cfg.onSelect(item.value) end,
            }
        end
        ShowMenu(button, {
            items = items, actions = cfg.actions,
            current = cfg.current(), width = cfg.menuWidth,
        })
    end)

    button.Refresh = function()
        local current = cfg.current()
        local text = cfg.emptyText or "-"
        for _, item in ipairs(cfg.items()) do
            if item.value == current then text = item.text break end
        end
        button.label:SetText(text)
    end

    return button
end

---------------------------------------------------------------------------
-- Icon strip - the spell list as a row of icons
--
-- Click the plus to add one, drag an icon to move it, right click to remove
-- it. The strip IS the preview: what you see here is the order the group
-- renders in.
--
-- cfg = { size, spacing, items() -> {{icon, name, id}}, onAdd,
--         onReorder(from, to), onRemove(index), perRow }
---------------------------------------------------------------------------
local dragProxy

local function GetDragProxy()
    if dragProxy then return dragProxy end
    dragProxy = CreateFrame("Frame", nil, UIParent)
    dragProxy:SetFrameStrata("TOOLTIP")
    dragProxy:SetSize(40, 40)
    dragProxy:Hide()
    dragProxy.icon = dragProxy:CreateTexture(nil, "ARTWORK")
    dragProxy.icon:SetAllPoints(dragProxy)
    dragProxy.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    dragProxy.icon:SetAlpha(0.85)
    return dragProxy
end

function UI.IconStrip(parent, cfg)
    local size = cfg.size or 40
    local spacing = cfg.spacing or 4
    local perRow = cfg.perRow or 10

    local strip = CreateFrame("Frame", nil, parent)
    strip.slots = {}

    local function SlotPosition(index)
        local zero = index - 1
        local col, line = zero % perRow, math.floor(zero / perRow)
        return col * (size + spacing), -line * (size + spacing)
    end

    -- Which slot the cursor is over, in the strip's own coordinates.
    local function IndexUnderCursor(count)
        local scale = strip:GetEffectiveScale()
        local cursorX, cursorY = GetCursorPosition()
        cursorX, cursorY = cursorX / scale, cursorY / scale

        local left, top = strip:GetLeft(), strip:GetTop()
        if not left or not top then return nil end

        local col = math.floor((cursorX - left) / (size + spacing))
        local line = math.floor((top - cursorY) / (size + spacing))
        local index = line * perRow + col + 1
        if index < 1 then index = 1 end
        if index > count then index = count end
        return index
    end

    local marker = Tex(strip, "OVERLAY", C.accent[1], C.accent[2], C.accent[3], 1)
    marker:SetWidth(2)
    marker:SetHeight(size)
    marker:Hide()

    local function NewSlot(index)
        local slot = CreateFrame("Button", nil, strip)
        slot:SetSize(size, size)
        slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        slot:RegisterForDrag("LeftButton")

        slot.bg = Fill(slot, "BACKGROUND", C.control)

        slot.icon = slot:CreateTexture(nil, "ARTWORK")
        slot.icon:SetPoint("TOPLEFT", slot, "TOPLEFT", 1, -1)
        slot.icon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 1)
        slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        slot.edge = ns.CreateBorder(slot, 1, "OVERLAY")
        slot.edge:SetColor(0, 0, 0, 1)

        slot.hl = slot:CreateTexture(nil, "HIGHLIGHT")
        slot.hl:SetAllPoints(slot)
        slot.hl:SetColorTexture(1, 1, 1, 0.16)

        slot.order = slot:CreateFontString(nil, "OVERLAY")
        ns.StyleFont(slot.order, math.max(9, size * 0.26), "OUTLINE")
        slot.order:SetPoint("TOPLEFT", slot, "TOPLEFT", 2, -2)
        slot.order:SetTextColor(1, 1, 1, 0.7)

        slot:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self.dkName or "")
            GameTooltip:AddLine("Drag to reorder", 0.6, 0.6, 0.6)
            GameTooltip:AddLine("Right click to remove", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        slot:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)

        slot:SetScript("OnClick", function(self, button)
            if button == "RightButton" and cfg.onRemove then
                cfg.onRemove(self.dkIndex)
            end
        end)

        slot:SetScript("OnDragStart", function(self)
            strip.dragFrom = self.dkIndex
            local proxy = GetDragProxy()
            proxy:SetSize(size, size)
            proxy.icon:SetTexture(self.icon:GetTexture())
            proxy:Show()
            self.icon:SetAlpha(0.25)
            strip:SetScript("OnUpdate", function()
                local scale = UIParent:GetEffectiveScale()
                local x, y = GetCursorPosition()
                proxy:ClearAllPoints()
                proxy:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)

                local target = IndexUnderCursor(strip.count or 1)
                if target then
                    local mx, my = SlotPosition(target)
                    marker:ClearAllPoints()
                    marker:SetPoint("TOPLEFT", strip, "TOPLEFT", mx - spacing / 2 - 1, my)
                    marker:Show()
                end
            end)
        end)

        slot:SetScript("OnDragStop", function(self)
            strip:SetScript("OnUpdate", nil)
            marker:Hide()
            if dragProxy then dragProxy:Hide() end
            self.icon:SetAlpha(1)

            local from = strip.dragFrom
            strip.dragFrom = nil
            local target = IndexUnderCursor(strip.count or 1)
            if from and target and target ~= from and cfg.onReorder then
                cfg.onReorder(from, target)
            end
        end)

        strip.slots[index] = slot
        return slot
    end

    -- The plus tile: same size and place in the flow as a spell, because it
    -- is the next thing in the row.
    local add = CreateFrame("Button", nil, strip)
    add:SetSize(size, size)
    Fill(add, "BACKGROUND", C.control)
    local addEdge = ns.CreateBorder(add, 1, "OVERLAY")
    addEdge:SetColor(C.accent[1], C.accent[2], C.accent[3], 0.55)
    local plus = UI.Label(add, "+", 20, C.accent)
    plus:SetPoint("CENTER", add, "CENTER", 0, -1)
    add:SetScript("OnEnter", function()
        addEdge:SetColor(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    add:SetScript("OnLeave", function()
        addEdge:SetColor(C.accent[1], C.accent[2], C.accent[3], 0.55)
    end)
    add:SetScript("OnClick", cfg.onAdd)
    strip.add = add

    strip.Refresh = function()
        local items = cfg.items()
        strip.count = #items

        for index, item in ipairs(items) do
            local slot = strip.slots[index] or NewSlot(index)
            local x, y = SlotPosition(index)
            slot:ClearAllPoints()
            slot:SetPoint("TOPLEFT", strip, "TOPLEFT", x, y)
            slot:SetSize(size, size)

            if item.icon then
                slot.icon:SetTexture(item.icon)
                slot.icon:SetDesaturated(false)
            else
                slot.icon:SetTexture(ns.WHITE)
                slot.icon:SetDesaturated(true)
            end
            slot.icon:SetAlpha(1)
            slot.order:SetText(tostring(index))
            slot.dkIndex = index
            slot.dkName = item.name
            slot:Show()
        end

        for index = #items + 1, #strip.slots do strip.slots[index]:Hide() end

        local x, y = SlotPosition(#items + 1)
        add:ClearAllPoints()
        add:SetPoint("TOPLEFT", strip, "TOPLEFT", x, y)
        add:SetSize(size, size)

        local lines = math.floor(#items / perRow) + 1
        strip:SetSize(perRow * (size + spacing), lines * (size + spacing))
        return lines * (size + spacing)
    end

    return strip
end

---------------------------------------------------------------------------
-- Colour swatch
---------------------------------------------------------------------------
function UI.Swatch(row, get, set, apply)
    local swatch = CreateFrame("Button", nil, row.slot)
    swatch:SetSize(44, 18)
    swatch:SetPoint("RIGHT", row.slot, "RIGHT", 0, 0)

    local fill = Tex(swatch, "ARTWORK", 1, 1, 1, 1)
    fill:SetAllPoints(swatch)

    local edge = ns.CreateBorder(swatch, 1, "OVERLAY")
    edge:SetColor(1, 1, 1, 0.25)

    local function Commit(r, g, b)
        set(r, g, b)
        fill:SetColorTexture(r, g, b, 1)
        if apply then apply() end
    end

    swatch:SetScript("OnClick", function()
        local r, g, b = get()
        local picker = ColorPickerFrame
        if not picker then return end

        picker:SetFrameStrata("FULLSCREEN_DIALOG")
        picker:SetClampedToScreen(true)

        local function OnPick() Commit(picker:GetColorRGB()) end
        local function OnCancel() Commit(r, g, b) end

        -- SetupColorPickerAndShow is the 10.2.5 overhaul; the field
        -- assignment below is the pre-overhaul path.
        if picker.SetupColorPickerAndShow then
            picker:SetupColorPickerAndShow({
                r = r, g = g, b = b, hasOpacity = false,
                swatchFunc = OnPick, cancelFunc = OnCancel,
            })
        else
            picker.func, picker.cancelFunc = OnPick, OnCancel
            picker.hasOpacity = false
            picker:SetColorRGB(r, g, b)
            picker:Show()
        end
    end)

    swatch.Refresh = function()
        local r, g, b = get()
        fill:SetColorTexture(r or 1, g or 1, b or 1, 1)
    end

    row.control = swatch
    row.Refresh = swatch.Refresh
    return row
end

---------------------------------------------------------------------------
-- Text input
---------------------------------------------------------------------------
function UI.Input(parent, width, onSubmit, numeric)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, 22)
    Fill(holder, "BACKGROUND", C.windowBg)
    local edge = ns.CreateBorder(holder, 1, "BORDER")
    edge:SetColor(1, 1, 1, 0.10)

    local input = CreateFrame("EditBox", nil, holder)
    input:SetPoint("TOPLEFT", holder, "TOPLEFT", 6, 0)
    input:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -6, 0)
    input:SetAutoFocus(false)
    input:SetMaxLetters(numeric and 10 or 40)
    if numeric then input:SetNumeric(true) end
    ns.StyleFont(input, 12, "")
    input:SetTextColor(C.text[1], C.text[2], C.text[3])

    input:SetScript("OnEnterPressed", function(self)
        onSubmit(self:GetText())
        self:ClearFocus()
    end)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    input:SetScript("OnEditFocusGained", function()
        edge:SetColor(C.accent[1], C.accent[2], C.accent[3], 0.6)
    end)
    input:SetScript("OnEditFocusLost", function()
        edge:SetColor(1, 1, 1, 0.10)
    end)

    holder.input = input
    holder.SetEnabled = function(_, enabled)
        input:SetEnabled(enabled)
        input:SetTextColor(enabled and C.text[1] or C.textFaint[1],
                           enabled and C.text[2] or C.textFaint[2],
                           enabled and C.text[3] or C.textFaint[3])
    end
    return holder
end

---------------------------------------------------------------------------
-- CellGrid - the bar, laid out as you will see it on screen
--
-- Rows x columns of cells. An empty cell is a real place you can click, not
-- a gap, which is what makes "add a row" mean something before it is filled.
-- Left click picks the spell for that cell, right click clears it, dragging
-- one cell onto another swaps them.
--
-- cfg = {
--   cellSize()  -> width, height
--   gaps()      -> spacing, lineSpacing
--   rows(), columns()
--   content(cell) -> spellID or nil
--   onPick(cell), onClear(cell), onMove(from, to)
-- }
---------------------------------------------------------------------------
function UI.CellGrid(parent, cfg)
    local grid = CreateFrame("Frame", nil, parent)
    grid.cells = {}

    local marker = Tex(grid, "OVERLAY", C.accent[1], C.accent[2], C.accent[3], 1)
    marker:Hide()

    local function Geometry()
        local w, h = cfg.cellSize()
        local sx, sy = cfg.gaps()
        return w, h, sx, sy
    end

    local function CellPosition(index)
        local w, h, sx, sy = Geometry()
        local columns = math.max(1, cfg.columns())
        local zero = index - 1
        local col, row = zero % columns, math.floor(zero / columns)
        return col * (w + sx), -row * (h + sy)
    end

    local function CellUnderCursor()
        local w, h, sx, sy = Geometry()
        local scale = grid:GetEffectiveScale()
        local cursorX, cursorY = GetCursorPosition()
        cursorX, cursorY = cursorX / scale, cursorY / scale

        local left, top = grid:GetLeft(), grid:GetTop()
        if not left or not top then return nil end

        local columns = math.max(1, cfg.columns())
        local col = math.floor((cursorX - left) / (w + sx))
        local row = math.floor((top - cursorY) / (h + sy))
        if col < 0 or col >= columns or row < 0 then return nil end

        local index = row * columns + col + 1
        if index < 1 or index > cfg.rows() * columns then return nil end
        return index
    end

    local function NewCell(index)
        local cell = CreateFrame("Button", nil, grid)
        cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        cell:RegisterForDrag("LeftButton")

        cell.bg = Fill(cell, "BACKGROUND", C.control)

        cell.icon = cell:CreateTexture(nil, "ARTWORK")
        cell.icon:SetPoint("TOPLEFT", cell, "TOPLEFT", 1, -1)
        cell.icon:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -1, 1)
        cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        cell.plus = UI.Label(cell, "+", 18, C.textFaint)
        cell.plus:SetPoint("CENTER", cell, "CENTER", 0, -1)

        cell.edge = ns.CreateBorder(cell, 1, "OVERLAY")

        -- A second, outset border for the selection, so it reads clearly even
        -- on a cell whose own border is already dark.
        cell.ringHost = CreateFrame("Frame", nil, cell)
        cell.ringHost:SetPoint("TOPLEFT", cell, "TOPLEFT", -2, 2)
        cell.ringHost:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 2, -2)
        cell.ring = ns.CreateBorder(cell.ringHost, 2, "OVERLAY")
        cell.ring:SetColor(C.accent[1], C.accent[2], C.accent[3], 1)
        cell.ring:Hide()

        cell.hl = cell:CreateTexture(nil, "HIGHLIGHT")
        cell.hl:SetAllPoints(cell)
        cell.hl:SetColorTexture(1, 1, 1, 0.14)

        cell.number = cell:CreateFontString(nil, "OVERLAY")
        ns.StyleFont(cell.number, 10, "OUTLINE")
        cell.number:SetPoint("TOPLEFT", cell, "TOPLEFT", 2, -2)
        cell.number:SetTextColor(1, 1, 1, 0.6)

        cell:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.dkSpellID then
                GameTooltip:AddLine(ns.SpellName(self.dkSpellID) or "?")
                GameTooltip:AddLine(tostring(self.dkSpellID), 0.5, 0.5, 0.5)
                GameTooltip:AddLine("Click to change", 0.6, 0.6, 0.6)
                GameTooltip:AddLine("Drag to move, right click to clear", 0.6, 0.6, 0.6)
            else
                GameTooltip:AddLine("Empty")
                GameTooltip:AddLine("Click to put a spell here", 0.6, 0.6, 0.6)
            end
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)

        cell:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                if self.dkSpellID and cfg.onClear then cfg.onClear(self.dkIndex) end
            elseif cfg.onPick then
                cfg.onPick(self.dkIndex)
            end
        end)

        cell:SetScript("OnDragStart", function(self)
            if not self.dkSpellID then return end
            grid.dragFrom = self.dkIndex
            self.icon:SetAlpha(0.3)
            grid:SetScript("OnUpdate", function()
                local target = CellUnderCursor()
                if target then
                    local x, y = CellPosition(target)
                    local w, h = Geometry()
                    marker:ClearAllPoints()
                    marker:SetPoint("TOPLEFT", grid, "TOPLEFT", x - 1, y + 1)
                    marker:SetSize(w + 2, h + 2)
                    marker:SetAlpha(0.28)
                    marker:Show()
                else
                    marker:Hide()
                end
            end)
        end)

        cell:SetScript("OnDragStop", function(self)
            grid:SetScript("OnUpdate", nil)
            marker:Hide()
            self.icon:SetAlpha(1)

            local from = grid.dragFrom
            grid.dragFrom = nil
            local target = CellUnderCursor()
            if from and target and target ~= from and cfg.onMove then
                cfg.onMove(from, target)
            end
        end)

        grid.cells[index] = cell
        return cell
    end

    -- Returns the height it ended up needing, so the page can lay out below.
    grid.Refresh = function()
        local w, h, sx, sy = Geometry()
        local rows = math.max(1, cfg.rows())
        local columns = math.max(1, cfg.columns())
        local total = rows * columns

        for index = 1, total do
            local cell = grid.cells[index] or NewCell(index)
            local x, y = CellPosition(index)

            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", grid, "TOPLEFT", x, y)
            cell:SetSize(w, h)
            cell.dkIndex = index

            local spellID = cfg.content(index)
            cell.dkSpellID = spellID

            if spellID then
                local texture = ns.SpellTexture(spellID)
                cell.icon:SetTexture(texture or ns.WHITE)
                cell.icon:SetDesaturated(not texture)
                cell.icon:SetAlpha(1)
                cell.icon:Show()
                cell.plus:Hide()
                cell.number:SetText(tostring(index))
                cell.edge:SetColor(0, 0, 0, 1)
            else
                cell.icon:Hide()
                cell.plus:Show()
                cell.number:SetText("")
                cell.edge:SetColor(C.accent[1], C.accent[2], C.accent[3], 0.35)
            end

            -- The selected cell is what the inspector is editing, so it has
            -- to be obvious which one that is.
            local isSelected = cfg.selected and cfg.selected() == index
            cell.ring:SetShown(isSelected)
            if isSelected then
                cell.edge:SetColor(C.accent[1], C.accent[2], C.accent[3], 1)
            end

            cell:Show()
        end

        for index = total + 1, #grid.cells do grid.cells[index]:Hide() end

        local width = columns * w + (columns - 1) * sx
        local height = rows * h + (rows - 1) * sy
        grid:SetSize(math.max(width, 1), math.max(height, 1))
        return height
    end

    return grid
end

---------------------------------------------------------------------------
-- Page - a two-column grid of sections and rows
--
-- Rows are recorded, not positioned on creation, so a row that does not
-- apply can be skipped at layout time and the rows below close up instead of
-- leaving a hole.
---------------------------------------------------------------------------
local Grid = {}
Grid.__index = Grid

-- A scroll area with our own scrollbar. Blizzard's UIPanelScrollFrameTemplate
-- brings its pale, chunky bar with it, which reads as a foreign object inside
-- a dark custom panel - and it cannot be restyled into one.
--
-- Returns scroll, content. Call scroll.Update() after changing the content
-- height so the bar re-measures.
function UI.ScrollArea(parent, contentWidth, gutter)
    gutter = gutter or 10

    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -gutter, 0)
    scroll:EnableMouseWheel(true)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(contentWidth, 1)
    scroll:SetScrollChild(content)

    local rail = CreateFrame("Frame", nil, parent)
    rail:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    rail:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    rail:SetWidth(5)
    local track = Tex(rail, "BACKGROUND", 1, 1, 1, 0.05)
    track:SetAllPoints(rail)

    local thumb = CreateFrame("Frame", nil, rail)
    thumb:SetWidth(5)
    thumb:EnableMouse(true)
    local thumbFill = Fill(thumb, "ARTWORK", C.controlHi)

    local function Range()
        local range = scroll:GetVerticalScrollRange() or 0
        return range > 1 and range or 0
    end

    local function UpdateThumb()
        local range = Range()
        local visible = scroll:GetHeight()
        local total = visible + range

        if range <= 0 or total <= 0 then
            rail:Hide()
            return
        end
        rail:Show()

        local height = math.max(24, visible * (visible / total))
        local travel = visible - height
        local progress = range > 0 and (scroll:GetVerticalScroll() / range) or 0

        thumb:SetHeight(height)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", rail, "TOP", 0, -travel * progress)
    end

    local function ScrollBy(delta)
        local range = Range()
        if range <= 0 then return end
        local next_ = scroll:GetVerticalScroll() - delta * 40
        if next_ < 0 then next_ = 0 end
        if next_ > range then next_ = range end
        scroll:SetVerticalScroll(next_)
    end

    scroll:SetScript("OnMouseWheel", function(_, delta) ScrollBy(delta) end)
    scroll:SetScript("OnVerticalScroll", UpdateThumb)
    scroll:SetScript("OnScrollRangeChanged", UpdateThumb)
    scroll:SetScript("OnSizeChanged", UpdateThumb)

    thumb:SetScript("OnEnter", function()
        thumbFill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.8)
    end)
    thumb:SetScript("OnLeave", function()
        if not thumb.dragging then
            thumbFill:SetColorTexture(C.controlHi[1], C.controlHi[2], C.controlHi[3], 1)
        end
    end)
    thumb:SetScript("OnMouseDown", function(self)
        self.dragging = true
        local _, cursorY = GetCursorPosition()
        self.grabAt = cursorY / self:GetEffectiveScale()
        self.grabScroll = scroll:GetVerticalScroll()
    end)
    thumb:SetScript("OnMouseUp", function(self)
        self.dragging = false
        thumbFill:SetColorTexture(C.controlHi[1], C.controlHi[2], C.controlHi[3], 1)
    end)
    thumb:SetScript("OnUpdate", function(self)
        if not self.dragging then return end
        local range = Range()
        local travel = scroll:GetHeight() - self:GetHeight()
        if range <= 0 or travel <= 0 then return end

        local _, cursorY = GetCursorPosition()
        cursorY = cursorY / self:GetEffectiveScale()
        local moved = (self.grabAt - cursorY) / travel * range

        local next_ = self.grabScroll + moved
        if next_ < 0 then next_ = 0 end
        if next_ > range then next_ = range end
        scroll:SetVerticalScroll(next_)
    end)

    scroll.Update = UpdateThumb
    UpdateThumb()

    return scroll, content
end

function UI.Page(parent, width)
    local contentWidth = width - 14
    local scroll, content = UI.ScrollArea(parent, contentWidth)

    local grid = setmetatable({
        content  = content,
        scroll   = scroll,
        width    = contentWidth,
        colWidth = math.floor((contentWidth - UI.COL_GAP) / 2),
        items    = {},
        widgets  = {},
    }, Grid)

    return grid
end

-- A full-width block: section headers, notes, button strips.
function Grid:Wide(region, height)
    self.items[#self.items + 1] = {
        region = region, height = height, wide = true, group = self.group,
    }
    if region.Refresh then self.widgets[#self.widgets + 1] = region end
    return region
end

-- Passing a key makes the section a disclosure, folded shut by default.
-- Everything added after it belongs to it until the next section.
--
-- This is what keeps the page honest: the things you do while working stay
-- visible, and the dozen knobs you set once are one click away instead of
-- filling the screen and hiding the work.
function Grid:Section(title, key)
    self.group = key

    if not key then
        return self:Wide(UI.SectionHeader(self.content, title), UI.SECTION_H)
    end

    self.collapsed = self.collapsed or {}
    if self.collapsed[key] == nil then self.collapsed[key] = true end

    local header
    header = UI.SectionHeader(self.content, title,
        function()
            self.collapsed[key] = not self.collapsed[key]
            header.Refresh()
            self:Layout()
        end,
        function() return not self.collapsed[key] end)

    -- Recorded with no group of its own: a section header must stay visible
    -- when its own contents are folded away.
    self.group = nil
    self:Wide(header, UI.SECTION_H)
    self.group = key
    return header
end

-- height is only needed for a note whose text is set LATER: the measured
-- height would be the empty string's, and the rows below would overlap it.
function Grid:Note(text, height)
    local note = UI.Hint(self.content, text)
    note:SetWidth(self.width)
    note:SetJustifyV("TOP")
    -- Width is set, so GetStringHeight reports the wrapped height.
    return self:Wide(note, height or (note:GetStringHeight() + 10))
end

-- A half-width row. Two consecutive calls share a line.
function Grid:Row(label, opts)
    opts = opts or {}
    opts.controlWidth = opts.controlWidth or 150
    local row = UI.Row(self.content, label, opts)
    row:SetWidth(self.colWidth)
    self.items[#self.items + 1] = {
        region = row, height = row:GetHeight(), group = self.group,
    }
    self.widgets[#self.widgets + 1] = row
    return row
end

-- A row spanning both columns, for controls that need the space.
function Grid:FullRow(label, opts)
    opts = opts or {}
    opts.controlWidth = opts.controlWidth or 300
    local row = UI.Row(self.content, label, opts)
    row:SetWidth(self.width)
    self.items[#self.items + 1] = {
        region = row, height = row:GetHeight(), wide = true, group = self.group,
    }
    self.widgets[#self.widgets + 1] = row
    return row
end

-- Places everything and returns the y the next free line would start at.
function Grid:Layout()
    local y, column, lineHeight = 0, 0, 0

    local function EndLine()
        if column > 0 then
            y = y - lineHeight - UI.ROW_GAP
            column, lineHeight = 0, 0
        end
    end

    local collapsed = self.collapsed or {}

    for _, item in ipairs(self.items) do
        local region = item.region
        local folded = item.group ~= nil and collapsed[item.group]

        if folded then
            if region then region:Hide() end
        elseif region and region.dkSkip then
            -- skipped entirely: no gap left behind
        elseif item.wide then
            EndLine()
            if region then
                region:ClearAllPoints()
                region:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, y)
                region:Show()
            end
            -- dkHeight lets a block that grows with its content - a grid
            -- gaining a row - report its real height instead of the one it
            -- happened to have when it was recorded.
            y = y - ((region and region.dkHeight) or item.height)
        else
            region:ClearAllPoints()
            region:SetPoint("TOPLEFT", self.content, "TOPLEFT",
                column * (self.colWidth + UI.COL_GAP), y)
            region:Show()
            lineHeight = math.max(lineHeight, item.height)
            column = column + 1
            if column >= 2 then EndLine() end
        end
    end
    EndLine()

    self.content:SetHeight(math.max(1, -y + 10))
    if self.scroll.Update then self.scroll.Update() end
    return y
end

function Grid:Refresh()
    for _, widget in ipairs(self.widgets) do
        if widget.Refresh then widget.Refresh() end
    end
    self:Layout()
end
