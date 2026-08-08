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
--
-- Every colour here is OPAQUE. Nothing in this window is see-through: a
-- translucent panel over a moving 3D world is unreadable, and the layering
-- that a glass effect is meant to suggest is done properly instead, with
-- distinct surface levels.
--
-- The levels, darkest to lightest:
--   canvasBg   the work area - the darkest thing on screen, so what sits on
--              it reads as raised
--   windowBg   the window itself
--   sidebarBg  the two side columns, one step lighter than the work area
--   surface    a card, the thing you actually work on
--   surfaceHi  that card under the cursor
--   control    an interactive part inside a card
--
-- Anything that needs to look like a hairline is an opaque colour one step
-- off its background, never white at 6%.
---------------------------------------------------------------------------
local C = {
    canvasBg   = { 0.063, 0.067, 0.075 },
    windowBg   = { 0.082, 0.086, 0.098 },
    sidebarBg  = { 0.106, 0.110, 0.125 },
    well       = { 0.090, 0.094, 0.106 },  -- a recessed slot: empty cells, inputs
    surface    = { 0.137, 0.145, 0.165 },
    surfaceHi  = { 0.173, 0.182, 0.204 },
    control    = { 0.204, 0.216, 0.243 },
    controlHi  = { 0.251, 0.263, 0.294 },
    separator  = { 0.169, 0.176, 0.196 },
    edge       = { 0.196, 0.204, 0.227 },  -- a card's own outline

    accent     = { 1.000, 0.478, 0.239 },  -- ZwoelfStuff orange
    accentDim  = { 0.694, 0.337, 0.169 },
    accentSoft = { 0.286, 0.192, 0.161 },  -- accent laid over a surface, opaque
    accentCool = { 0.494, 0.776, 0.831 },  -- the "DK" cyan

    -- Green means "this one is already on the bar you have selected". Only
    -- ever used for that, so it stays readable as a state rather than decoration.
    inUse      = { 0.404, 0.788, 0.443 },
    inUseSoft  = { 0.145, 0.235, 0.180 },

    text       = { 0.949, 0.953, 0.965 },
    textDim    = { 0.616, 0.635, 0.678 },
    textFaint  = { 0.408, 0.424, 0.467 },
    danger     = { 0.898, 0.353, 0.318 },
}

-- One height for the whole window's header band, so the rule under every
-- heading lands on the same line no matter which column it is in.
UI.HEADER_H = 62

-- Kept so the panels that are parked until 12.1 still resolve their colours.
C.headerBg = C.surface
C.rowBg    = C.surface
C.rowHover = C.surfaceHi
C.line     = { C.separator[1], C.separator[2], C.separator[3], 1 }

UI.C = C

-- Row geometry, and it is deliberately TIGHT.
--
-- Every row used to be a filled card 38 pixels tall with a 4 pixel gap, which
-- put a visible box around every single setting. Forty of those is a brick
-- wall, and it reads as heavy however good the colours are - the complaint
-- was "altbacken, viel space wasted" and it was right.
--
-- What replaced it: rows are FLAT, separated by a hairline instead of a gap,
-- and only the row under the cursor gets a surface. The eye follows a list
-- rather than counting boxes, and the same page shows a third more of itself.
UI.ROW_H      = 28
UI.ROW_GAP    = 1
UI.SECTION_H  = 34
UI.COL_GAP    = 18

-- The one spacing rhythm. Everything in the window is a multiple of it, which
-- is most of what makes a layout look considered rather than assembled.
UI.PAD    = 14
UI.GAP    = 8
UI.RADIUS = 0

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
    btn:SetSize(width or 100, 24)

    -- Three weights, and they are not interchangeable:
    --   nil        an ordinary action
    --   "primary"  the one action a page is for
    --   "soft"     an action that belongs to the surface it sits on and must
    --              not shout - the accent is in the text, not the fill
    local accented = style == "primary" or style == "soft"
    local base = style == "primary" and C.accentSoft or C.control
    local hover = style == "primary" and C.accentDim or C.controlHi
    if style == "soft" then base, hover = C.surface, C.accentSoft end

    local bg = Fill(btn, "BACKGROUND", base)
    local edge = ns.CreateBorder(btn, 1, "BORDER")
    local rest = style == "soft" and C.edge or C.separator
    edge:SetColor(rest[1], rest[2], rest[3], 1)

    local label = UI.Label(btn, text, 12, accented and C.accent or C.text)
    label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.label = label

    btn:SetScript("OnEnter", function()
        if btn:IsEnabled() then
            bg:SetColorTexture(hover[1], hover[2], hover[3], 1)
            edge:SetColor(C.accent[1], C.accent[2], C.accent[3], 1)
            if style == "primary" then label:SetTextColor(1, 1, 1) end
        end
    end)
    btn:SetScript("OnLeave", function()
        bg:SetColorTexture(base[1], base[2], base[3], 1)
        edge:SetColor(rest[1], rest[2], rest[3], 1)
        if accented then label:SetTextColor(C.accent[1], C.accent[2], C.accent[3]) end
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
    -- A row with a second line needs room for it. 28 fits one 12pt label; two
    -- lines in the same 28 put the smaller one on the hairline underneath.
    row:SetHeight(opts.tall and 46 or (opts.sublabel and 38 or UI.ROW_H))

    -- Flat until you point at it. The surface is the CURSOR's, not the row's,
    -- which is what turns forty boxes into one list. Hidden rather than
    -- coloured-to-match: a fill drawn every frame at the background colour is
    -- still a fill.
    row.bg = Fill(row, "BACKGROUND", C.surface)
    row.bg:Hide()

    -- The hairline that does the separating instead. One pixel, one step off
    -- the background, and it stops short of both edges so a column of rows
    -- reads as a list rather than as a table.
    row.rule = Tex(row, "BACKGROUND", C.separator[1], C.separator[2],
        C.separator[3], 1)
    row.rule:SetHeight(1)
    row.rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 0)
    row.rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 0)

    row.label = UI.Label(row, text, 12, C.text)
    row.label:SetPoint("LEFT", row, "LEFT", 8, opts.sublabel and 8 or 0)
    row.label:SetWordWrap(false)

    if opts.sublabel then
        row.sub = UI.Label(row, opts.sublabel, 10, C.textFaint)
        row.sub:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -3)
        row.sub:SetWordWrap(false)
    end

    row.slot = CreateFrame("Frame", nil, row)
    row.slot:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.slot:SetSize(opts.controlWidth or CONTROL_W, row:GetHeight() - 6)

    -- The label must never run under the control.
    row.label:SetPoint("RIGHT", row.slot, "LEFT", -8, 0)

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self) self.bg:Show() end)
    row:SetScript("OnLeave", function(self) self.bg:Hide() end)

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

    -- The air goes ABOVE the heading, not below it. A heading belongs to what
    -- follows it, and spacing it evenly is what makes a long page read as one
    -- undifferentiated column.
    local caption = text:upper()
    local label = UI.Label(header, caption, 10, C.textDim, "")
    label:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", onToggle and 13 or 2, 7)

    local line = Tex(header, "ARTWORK", C.line[1], C.line[2], C.line[3], C.line[4])
    line:SetPoint("BOTTOMLEFT", label, "BOTTOMRIGHT", 8, 4)
    line:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -2, 7)
    line:SetHeight(1)

    if onToggle then
        -- A triangle drawn from two rectangles rather than a letter. "v" and
        -- ">" are two different glyph widths and two different baselines, so
        -- the caption next to them shifted every time a section was folded.
        local marker = header:CreateTexture(nil, "ARTWORK")
        marker:SetColorTexture(C.textDim[1], C.textDim[2], C.textDim[3], 1)
        marker:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 2, 12)
        marker:SetSize(7, 2)

        local marker2 = header:CreateTexture(nil, "ARTWORK")
        marker2:SetColorTexture(C.textDim[1], C.textDim[2], C.textDim[3], 1)

        header:SetScript("OnClick", onToggle)
        header:SetScript("OnEnter", function()
            label:SetTextColor(C.text[1], C.text[2], C.text[3])
            marker:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
            marker2:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        header:SetScript("OnLeave", function()
            label:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
            marker:SetColorTexture(C.textDim[1], C.textDim[2], C.textDim[3], 1)
            marker2:SetColorTexture(C.textDim[1], C.textDim[2], C.textDim[3], 1)
        end)

        header.Refresh = function()
            local open = isOpen()
            marker2:ClearAllPoints()
            if open then
                -- Open: a minus. Closed: a plus. Two rectangles, one of which
                -- is simply hidden - and both states are exactly as wide.
                marker2:Hide()
            else
                marker2:SetSize(2, 7)
                marker2:SetPoint("CENTER", marker, "CENTER", 0, 0)
                marker2:Show()
            end
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
    toggle:SetSize(38, 18)
    toggle:SetPoint("RIGHT", row.slot, "RIGHT", 0, 0)

    local track = Fill(toggle, "BACKGROUND", C.control)
    local edge = ns.CreateBorder(toggle, 1, "BORDER")
    edge:SetColor(C.separator[1], C.separator[2], C.separator[3], 1)

    local knob = Tex(toggle, "ARTWORK", 1, 1, 1, 1)
    knob:SetSize(14, 14)

    toggle.Refresh = function()
        local on = get() and true or false
        knob:ClearAllPoints()
        if on then
            knob:SetPoint("RIGHT", toggle, "RIGHT", -2, 0)
            knob:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
            track:SetColorTexture(C.accentSoft[1], C.accentSoft[2], C.accentSoft[3], 1)
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
    holder:SetSize(92, 22)

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
    minus:SetHeight(20)
    minus:SetPoint("LEFT", holder, "LEFT", 0, 0)

    local plus = UI.Button(holder, "+", 26, function() Step(1) end)
    plus:SetHeight(20)
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
    Fill(box, "BACKGROUND", C.canvasBg)
    local boxEdge = ns.CreateBorder(box, 1, "BORDER")
    boxEdge:SetColor(C.separator[1], C.separator[2], C.separator[3], 1)

    local value = UI.Label(box, "", 11, C.text)
    value:SetPoint("CENTER", box, "CENTER", 0, 0)
    value:SetJustifyH("CENTER")

    local bar = CreateFrame("Frame", nil, slider)
    bar:SetPoint("LEFT", slider, "LEFT", 0, 0)
    bar:SetPoint("RIGHT", box, "LEFT", -8, 0)
    bar:SetHeight(18)
    bar:EnableMouse(true)

    local track = Tex(bar, "BACKGROUND", C.control[1], C.control[2], C.control[3], 1)
    track:SetPoint("LEFT", bar, "LEFT", 0, 0)
    track:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    track:SetHeight(3)

    local fill = Tex(bar, "ARTWORK", C.accent[1], C.accent[2], C.accent[3], 1)
    fill:SetPoint("LEFT", bar, "LEFT", 0, 0)
    fill:SetHeight(3)

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
    Fill(popup, "BACKGROUND", C.surface)
    local edge = ns.CreateBorder(popup, 1, "BORDER")
    edge:SetColor(C.accentDim[1], C.accentDim[2], C.accentDim[3], 1)
    popup.rows = {}
    popup.divider = Tex(popup, "ARTWORK", C.separator[1], C.separator[2], C.separator[3], 1)
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

    -- ARTWORK and switched by hand, NOT the HIGHLIGHT layer. HIGHLIGHT draws
    -- above every other layer including OVERLAY, so an opaque highlight there
    -- painted straight over the label and the hovered entry was the one you
    -- could not read.
    entry.hl = entry:CreateTexture(nil, "ARTWORK")
    entry.hl:SetAllPoints(entry)
    entry.hl:SetColorTexture(C.accentSoft[1], C.accentSoft[2], C.accentSoft[3], 1)
    entry.hl:Hide()

    entry:SetScript("OnEnter", function(self) self.hl:Show() end)
    entry:SetScript("OnLeave", function(self) self.hl:Hide() end)

    -- The preview strip. A texture list where every row is the same grey text
    -- tells you nothing about the one thing you are choosing, and picking a
    -- bar texture by NAME is guessing twenty times in a row.
    --
    -- On the right, not behind the label: a texture painted across the whole
    -- row competes with the word on top of it, and the darker ones make it
    -- unreadable. This way both are legible and neither is a compromise.
    -- Its own frame, because the outline has to go around the SWATCH and a
    -- border built on the row would frame the whole row instead.
    entry.swatchHost = CreateFrame("Frame", nil, entry)
    entry.swatchHost:SetPoint("RIGHT", entry, "RIGHT", -8, 0)
    entry.swatchHost:SetSize(76, ENTRY_H - 8)
    entry.swatchHost:Hide()

    entry.swatch = entry.swatchHost:CreateTexture(nil, "ARTWORK")
    entry.swatch:SetAllPoints(entry.swatchHost)

    entry.swatchEdge = ns.CreateBorder(entry.swatchHost, 1, "OVERLAY")
    entry.swatchEdge:Hide()

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

        -- Back to the panel font unless this row asks for its own. Rows are
        -- reused, so a font left on one from a previous menu would turn up on
        -- an unrelated entry three menus later.
        ns.StyleUIFont(entry.label, 12)
        entry.swatchHost:Hide()
        entry.swatchEdge:Hide()

        local preview = item.preview
        if preview == "font" then
            -- A font shown in itself. Nothing else answers "what does this
            -- actually look like", and the fallback is honest: a file that
            -- will not load leaves the row in the panel font.
            ns.Media.ApplyFont(entry.label, item.value, 12, "")
        elseif preview == "statusbar" and ns.Media.IsKnown("statusbar", item.value) then
            entry.swatch:SetTexture(ns.Media.Statusbar(item.value))
            entry.swatch:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
            entry.swatchHost:Show()
        elseif preview == "border" and ns.Media.IsKnown("border", item.value) then
            -- An edge file has to be drawn as an EDGE to mean anything, so
            -- the swatch is a small framed box rather than the strip itself -
            -- which on its own is eight tiles in a row and reads as noise.
            entry.swatch:SetTexture(ns.WHITE)
            entry.swatch:SetVertexColor(C.canvasBg[1], C.canvasBg[2], C.canvasBg[3], 1)
            entry.swatchHost:Show()
            entry.swatchEdge:SetThickness(2)
            entry.swatchEdge:SetColor(C.accent[1], C.accent[2], C.accent[3], 1)
            entry.swatchEdge:Show()
        end

        if item.onDelete then
            entry.label:SetPoint("RIGHT", entry.del, "LEFT", -4, 0)
            entry.del:Show()
            entry.del:SetScript("OnClick", function()
                menu:Hide()
                item.onDelete()
            end)
        elseif entry.swatchHost:IsShown() then
            entry.label:SetPoint("RIGHT", entry.swatchHost, "LEFT", -8, 0)
            entry.del:Hide()
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

-- Exported so the unlock overlay uses the SAME menu as the options window.
-- A second menu implementation is a second set of paddings, colours and
-- click-away rules to keep in step, and they never stay in step.
UI.ShowMenu = ShowMenu

---------------------------------------------------------------------------
-- The button half of a dropdown, without the row wrapper
---------------------------------------------------------------------------
function UI.MenuButton(parent, width, height)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height or 22)

    local bg = Fill(button, "BACKGROUND", C.control)
    local edge = ns.CreateBorder(button, 1, "BORDER")
    edge:SetColor(C.separator[1], C.separator[2], C.separator[3], 1)

    button.label = UI.Label(button, "", 12, C.text)
    button.label:SetPoint("LEFT", button, "LEFT", 10, 0)
    button.label:SetPoint("RIGHT", button, "RIGHT", -20, 0)
    button.label:SetWordWrap(false)

    local arrow = UI.Label(button, "v", 9, C.textDim)
    arrow:SetPoint("RIGHT", button, "RIGHT", -8, 0)

    button:SetScript("OnEnter", function()
        bg:SetColorTexture(C.controlHi[1], C.controlHi[2], C.controlHi[3], 1)
        edge:SetColor(C.accentDim[1], C.accentDim[2], C.accentDim[3], 1)
    end)
    button:SetScript("OnLeave", function()
        bg:SetColorTexture(C.control[1], C.control[2], C.control[3], 1)
        edge:SetColor(C.separator[1], C.separator[2], C.separator[3], 1)
    end)

    return button
end

---------------------------------------------------------------------------
-- MediaPicker - fonts, bar textures and border textures
--
-- A list of names is useless here. "Empyrean" says nothing about a texture,
-- and the whole reason to offer a font is that it looks different - so each
-- entry shows itself: a font renders its own name in itself, a texture draws
-- a swatch behind it.
--
-- The list is asked for at OPEN time, never cached. Media arrives late: an
-- addon that loads after this one registers its textures when it is ready,
-- and a list built once at login is a list missing half of them.
---------------------------------------------------------------------------
-- inheritLabel, when given, puts an entry at the top of the list whose value
-- is the empty string: "use whatever the global setting says". The global
-- itself is the one picker that does NOT offer it, or it would point at
-- itself.
function UI.MediaPicker(row, kind, get, set, apply, inheritLabel)
    local button = UI.MenuButton(row.slot, row.slot:GetWidth())
    button:SetPoint("RIGHT", row.slot, "RIGHT", 0, 0)

    -- A swatch behind the label, so the button itself previews the choice.
    local preview = button:CreateTexture(nil, "BORDER")
    preview:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    preview:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    preview:Hide()

    local function Paint()
        local key = get()
        preview:Hide()

        if inheritLabel and (not key or key == "") then
            button.label:SetText(inheritLabel)
            ns.StyleUIFont(button.label, 12)
            button.label:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
            return
        end

        button.label:SetText(key or "-")
        button.label:SetTextColor(C.text[1], C.text[2], C.text[3])

        if kind == "font" then
            -- Its own typeface, at the panel's size. If the file will not
            -- load the label simply stays in the panel font, which is the
            -- honest answer to "this font does not work here".
            ns.Media.ApplyFont(button.label, key, 12, "")
        elseif kind == "statusbar" and ns.Media.IsKnown(kind, key) then
            preview:SetTexture(ns.Media.Statusbar(key))
            preview:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.55)
            preview:Show()
        end
    end

    button:SetScript("OnClick", function()
        local items = {}

        if inheritLabel then
            items[1] = {
                text = inheritLabel, value = "",
                onClick = function()
                    set("")
                    if apply then apply() end
                    ns.Options:Refresh()
                end,
            }
        end

        for _, name in ipairs(ns.Media.List(kind)) do
            items[#items + 1] = {
                text = name, value = name, preview = kind,
                onClick = function()
                    set(name)
                    if apply then apply() end
                    ns.Options:Refresh()
                end,
            }
        end
        UI.ShowMenu(button, { items = items, current = get(), width = 190 })
    end)

    button.Refresh = Paint
    row.control = button
    row.Refresh = Paint
    return row
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
function UI.Input(parent, width, onSubmit, numeric, placeholder)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, 22)
    Fill(holder, "BACKGROUND", C.canvasBg)
    local edge = ns.CreateBorder(holder, 1, "BORDER")
    edge:SetColor(C.separator[1], C.separator[2], C.separator[3], 1)

    local input = CreateFrame("EditBox", nil, holder)
    input:SetPoint("TOPLEFT", holder, "TOPLEFT", 6, 0)
    input:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -6, 0)
    input:SetAutoFocus(false)
    input:SetMaxLetters(numeric and 10 or 40)
    if numeric then input:SetNumeric(true) end
    ns.StyleUIFont(input, 12, "")
    input:SetTextColor(C.text[1], C.text[2], C.text[3])

    -- An empty box with no caption reads as broken rather than optional, so
    -- every input can say what it is for.
    local ghost = UI.Label(holder, placeholder or "", 12, C.textFaint)
    ghost:SetPoint("LEFT", holder, "LEFT", 7, 0)
    ghost:SetWordWrap(false)
    local function UpdateGhost()
        ghost:SetShown((placeholder or "") ~= ""
            and (input:GetText() or "") == "" and not input:HasFocus())
    end
    holder.UpdateGhost = UpdateGhost

    input:SetScript("OnEnterPressed", function(self)
        onSubmit(self:GetText())
        self:ClearFocus()
    end)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    input:SetScript("OnEditFocusGained", function()
        edge:SetColor(C.accent[1], C.accent[2], C.accent[3], 1)
        UpdateGhost()
    end)
    input:SetScript("OnEditFocusLost", function()
        edge:SetColor(C.separator[1], C.separator[2], C.separator[3], 1)
        UpdateGhost()
    end)
    input:SetScript("OnTextChanged", UpdateGhost)
    UpdateGhost()

    holder.input = input
    holder.SetText = function(_, text)
        input:SetText(text or "")
        UpdateGhost()
    end
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
-- An empty cell is a real place you can click, not a gap, which is what makes
-- "add a row" mean something before it is filled. Left click picks the spell
-- for that cell, right click clears it, dragging one cell onto another swaps
-- them.
--
-- IT ASKS THE SAME ENGINE THE SCREEN DOES.
--
-- The positions come from Core/Layout.lua, not from a rows-times-columns loop
-- of its own. That is the difference between a preview and a promise: an arc
-- is an arc here, a diagonal slants, a puzzle shows every cell exactly where
-- it was dragged, and one cell scaled up is bigger in the editor too. A second
-- implementation would drift from the first one the day either changed.
--
-- cfg = {
--   layout()      -> slots, box   straight out of ns.Layout.Build
--   content(cell) -> spellID or nil
--   selected(), onPick(cell), onClear(cell), onMove(from, to)
-- }
---------------------------------------------------------------------------
-- Every live grid, so a spell dragged out of the list can find the cell it
-- was dropped on. The list has no idea which cards exist, and a card has no
-- idea a drag is happening - this is the one thing that has to know both.
local grids = {}

-- The cell under the cursor across ALL of them, or nothing. Walked backwards
-- so the most recently built card wins where two overlap.
function UI.CellUnderCursor()
    for index = #grids, 1, -1 do
        local grid = grids[index]
        if grid:IsVisible() then
            local cell = grid.CellAt()
            if cell then return grid, cell end
        end
    end
    return nil, nil
end

function UI.CellGrid(parent, cfg)
    local grid = CreateFrame("Frame", nil, parent)
    grid.cells = {}
    grid.slots = {}
    grids[#grids + 1] = grid

    -- Where a dragged cell would land: an accent outline rather than a wash
    -- over the icon, so it can be fully opaque and still show what is under it.
    local marker = CreateFrame("Frame", nil, grid)
    marker:SetFrameLevel(grid:GetFrameLevel() + 10)
    local markerEdge = ns.CreateBorder(marker, 2, "OVERLAY")
    markerEdge:SetColor(C.accent[1], C.accent[2], C.accent[3], 1)
    marker:Hide()

    -- One slot, as a rectangle measured from the grid's top left. The engine
    -- answers in centres against the arrangement's own origin; this is the one
    -- place that converts, so nothing below has to think about it twice.
    local function SlotRect(index)
        local slot = grid.slots[index]
        local box = grid.box
        if not (slot and box) then return nil end

        local left = box.centreX - box.width / 2
        local top  = box.centreY + box.height / 2
        return slot.x - slot.w / 2 - left,
               -(top - (slot.y + slot.h / 2)),
               slot.w, slot.h
    end

    local function CellPosition(index)
        local x, y = SlotRect(index)
        return x or 0, y or 0
    end

    -- Hit-tested against the real rectangles rather than divided out of a
    -- lattice. An arc has no columns to divide by, and a puzzle has no lattice
    -- at all - the arithmetic version would answer confidently and wrongly.
    local function CellUnderCursor()
        local scale = grid:GetEffectiveScale()
        local cursorX, cursorY = GetCursorPosition()
        cursorX, cursorY = cursorX / scale, cursorY / scale

        local left, top = grid:GetLeft(), grid:GetTop()
        if not left or not top then return nil end

        local localX, localY = cursorX - left, cursorY - top

        -- Backwards, so the cell drawn LAST - the one on top where two
        -- overlap - is the one the cursor is understood to be over.
        for index = #grid.slots, 1, -1 do
            local x, y, w, h = SlotRect(index)
            if x and localX >= x and localX <= x + w
                and localY <= y and localY >= y - h then
                return index
            end
        end
        return nil
    end

    local function NewCell(index)
        local cell = CreateFrame("Button", nil, grid)
        cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        cell:RegisterForDrag("LeftButton")

        -- Recessed, not raised: an empty cell is a slot waiting to be filled,
        -- and a well reads that way where a raised tile reads as a button.
        -- Only ever seen on an EMPTY cell now - a filled one wears the bar's
        -- own backdrop instead, see below.
        cell.bg = Fill(cell, "BACKGROUND", C.well)

        -- The bar's real backdrop, with its real texture and colour. This is
        -- what makes the card a PREVIEW rather than a diagram: what you are
        -- looking at is painted by the same two functions that paint the
        -- thing on screen, from the same style table.
        cell.plate = cell:CreateTexture(nil, "BACKGROUND", nil, 1)
        cell.plate:SetAllPoints(cell)
        cell.plate:Hide()

        cell.icon = cell:CreateTexture(nil, "ARTWORK")
        cell.icon:SetPoint("TOPLEFT", cell, "TOPLEFT", 1, -1)
        cell.icon:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -1, 1)
        cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        -- The fill of a bar-shaped cell, beside its square icon. Without it a
        -- tracking bar in the editor is an icon and a hole, which tells you
        -- nothing about the texture you just picked.
        cell.fill = cell:CreateTexture(nil, "ARTWORK", nil, 1)
        cell.fill:Hide()

        cell.caption = cell:CreateFontString(nil, "OVERLAY")
        cell.caption:SetJustifyH("LEFT")
        cell.caption:SetWordWrap(false)
        cell.caption:Hide()

        -- Its own frame above the cell's textures, exactly like the border on
        -- screen: a texture on the cell would be painted under the cell's own
        -- child frames whatever layer it claims.
        cell.chrome = ns.CreateChrome(cell)

        cell.plus = UI.Label(cell, "+", 16, C.textFaint)
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

        -- Hover is a ring, not a white wash: a wash over a spell icon dulls
        -- the very thing it is meant to point at, and it would have to be
        -- see-through to work at all.
        cell.hoverHost = CreateFrame("Frame", nil, cell)
        cell.hoverHost:SetPoint("TOPLEFT", cell, "TOPLEFT", -2, 2)
        cell.hoverHost:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 2, -2)
        cell.hover = ns.CreateBorder(cell.hoverHost, 2, "OVERLAY")
        cell.hover:SetColor(C.controlHi[1], C.controlHi[2], C.controlHi[3], 1)
        cell.hover:Hide()

        cell.number = cell:CreateFontString(nil, "OVERLAY")
        ns.StyleFont(cell.number, 10, "OUTLINE")
        cell.number:SetPoint("TOPLEFT", cell, "TOPLEFT", 2, -2)
        cell.number:SetTextColor(1, 1, 1, 0.6)

        cell:SetScript("OnEnter", function(self)
            if not (cfg.selected and cfg.selected() == self.dkIndex) then
                self.hover:Show()
            end
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")

            if self.dkSpellID then
                -- The game's own tooltip. An ID the client does not know
                -- throws rather than returning empty, hence the fallback.
                if not pcall(GameTooltip.SetSpellByID, GameTooltip, self.dkSpellID) then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(ns.SpellName(self.dkSpellID) or "?")
                    GameTooltip:AddLine(tostring(self.dkSpellID), 0.5, 0.5, 0.5)
                end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Click to change it", 0.62, 0.64, 0.68)
                GameTooltip:AddLine("Drag it to sort the bar", 0.62, 0.64, 0.68)
                GameTooltip:AddLine("Hold Shift while dropping to swap the two",
                    0.62, 0.64, 0.68)
                GameTooltip:AddLine("Right click to clear", 0.62, 0.64, 0.68)
            else
                GameTooltip:AddLine(string.format("Cell %d", self.dkIndex or 0))
                GameTooltip:AddLine("Empty", 0.62, 0.64, 0.68)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Click it, then pick a spell on the right",
                    1.00, 0.478, 0.239)
            end
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function(self)
            self.hover:Hide()
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
                grid.ShowMarker(CellUnderCursor())
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
                -- Read at the DROP, not at the pick-up: the modifier is a
                -- statement about where it is landing, and people press it
                -- while they are already dragging.
                cfg.onMove(from, target, IsShiftKeyDown())
            end
        end)

        grid.cells[index] = cell
        return cell
    end

    -- Reachable from outside, so a drag that started somewhere else entirely
    -- can ask this grid whether the cursor is over one of its cells.
    grid.CellAt = CellUnderCursor
    grid.dkDrop = cfg.onDrop

    grid.ShowMarker = function(index)
        local x, y, w, h
        if index then x, y, w, h = SlotRect(index) end
        if not x then
            marker:Hide()
            return
        end
        marker:ClearAllPoints()
        marker:SetPoint("TOPLEFT", grid, "TOPLEFT", x - 2, y + 2)
        marker:SetSize(w + 4, h + 4)
        marker:Show()
    end

    grid.HideMarker = function() marker:Hide() end

    -- Returns the height it ended up needing, so the page can lay out below.
    grid.Refresh = function()
        local slots, box = cfg.layout()
        grid.slots, grid.box = slots, box
        local total = #slots

        for index = 1, total do
            local cell = grid.cells[index] or NewCell(index)
            local x, y, w, h = SlotRect(index)

            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", grid, "TOPLEFT", x, y)
            cell:SetSize(w, h)
            cell.dkIndex = index

            -- A cell hidden by its own override still has to be clickable in
            -- the editor, or there would be no way to bring it back. It is
            -- shown at a fraction instead, which also says WHY it is faint.
            cell:SetAlpha(slots[index].hidden and 0.3 or 1)

            local spellID = cfg.content(index)
            cell.dkSpellID = spellID

            -- The bar's OWN look, resolved by the same function the screen
            -- calls. Asked for per cell, because a cell can be scaled and the
            -- automatic text size follows the cell rather than the bar.
            local style = cfg.style and cfg.style(h)
            local isBar = slots[index].kind == "bar"

            if spellID and style then
                ns.PaintSurface(cell.plate, style)
                ns.PaintBorder(cell.chrome, style, isBar)
                cell.bg:Hide()
            else
                cell.plate:Hide()
                cell.chrome.pixel:Hide()
                if cell.chrome.SetBackdrop then cell.chrome:SetBackdrop(nil) end
                cell.bg:Show()
            end

            if spellID then
                local texture = ns.SpellTexture(spellID)
                cell.icon:SetTexture(texture or ns.WHITE)
                cell.icon:SetDesaturated(not texture)
                cell.icon:SetAlpha(1)

                local zoom = style and style.iconZoom or 0.08
                cell.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)

                -- Square, even in a bar-shaped cell. Stretched across the
                -- width of a bar a spell icon is an unreadable smear, and the
                -- editor is supposed to show what the bar will look like -
                -- where the icon is a square at one end.
                cell.icon:ClearAllPoints()
                if isBar then
                    local place = cfg.iconPlacement and cfg.iconPlacement() or "left"
                    cell.icon:SetShown(place ~= "hidden")
                    local side = (place == "right") and "RIGHT" or "LEFT"
                    cell.icon:SetPoint("TOP" .. side, cell, "TOP" .. side, 0, 0)
                    cell.icon:SetPoint("BOTTOM" .. side, cell, "BOTTOM" .. side, 0, 0)
                    cell.icon:SetWidth(h)

                    -- The fill, in the bar's OWN colour and texture, drawn at
                    -- a part-full value so it reads as a bar rather than as a
                    -- coloured block. It is the same settings the screen uses
                    -- - a preview painted in the editor's accent colour tells
                    -- you nothing about the bar you are actually building.
                    local inset = (place == "hidden") and 0 or h
                    local area = math.max(1, w - inset)
                    local start = (place == "right") and 0 or inset

                    cell.fill:ClearAllPoints()
                    if style and style.fillSide then
                        cell.fill:SetPoint("TOPRIGHT", cell, "TOPLEFT",
                            start + area, 0)
                        cell.fill:SetPoint("BOTTOMRIGHT", cell, "BOTTOMLEFT",
                            start + area, 0)
                    else
                        cell.fill:SetPoint("TOPLEFT", cell, "TOPLEFT", start, 0)
                        cell.fill:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT", start, 0)
                    end
                    cell.fill:SetWidth(math.max(1, area * 0.7))

                    if style then
                        local fill = style.fillTexture
                        if fill and ns.Media.IsKnown("statusbar", fill) then
                            cell.fill:SetTexture(ns.Media.Statusbar(fill))
                        else
                            cell.fill:SetTexture(ns.WHITE)
                        end
                        local colour = style.fillColor
                        cell.fill:SetVertexColor(colour[1], colour[2], colour[3],
                            style.fillAlpha or 0.85)
                    end
                    cell.fill:Show()

                    if style and style.spellName.show then
                        local name = style.spellName
                        ns.Media.ApplyFont(cell.caption, name.font, name.size,
                            name.outline, name.color)
                        cell.caption:ClearAllPoints()
                        cell.caption:SetPoint("LEFT", cell, "LEFT",
                            ((place == "right") and 4 or (inset + 4)), 0)
                        cell.caption:SetWidth(math.max(8, w - inset - 8))
                        cell.caption:SetText(ns.SpellName(spellID) or "")
                        cell.caption:Show()
                    else
                        cell.caption:Hide()
                    end
                else
                    cell.icon:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0)
                    cell.icon:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 0, 0)
                    cell.icon:Show()
                    cell.fill:Hide()
                    cell.caption:Hide()
                end

                cell.plus:Hide()
                cell.number:SetText(tostring(index))
                cell.edge:Hide()
            else
                cell.icon:Hide()
                cell.fill:Hide()
                cell.caption:Hide()
                cell.plus:Show()
                cell.number:SetText("")
                cell.edge:SetColor(C.control[1], C.control[2], C.control[3], 1)
                cell.edge:Show()
            end

            -- The selected cell is what the right column is editing, so it has
            -- to be obvious which one that is.
            local isSelected = cfg.selected and cfg.selected() == index
            cell.ring:SetShown(isSelected)
            if isSelected then cell.hover:Hide() end

            cell:Show()
        end

        for index = total + 1, #grid.cells do grid.cells[index]:Hide() end

        grid:SetSize(math.max(box.width, 1), math.max(box.height, 1))
        return box.height
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

    -- No track, only a thumb, and only while there is something to scroll.
    -- A permanent groove down the side of every panel is noise.
    local rail = CreateFrame("Frame", nil, parent)
    rail:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    rail:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    rail:SetWidth(5)

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
        thumbFill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
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
--
-- padTop and padBottom are the air around it, and they are NOT decoration.
-- Only the half-width rows used to get a gap; every wide block was stacked
-- against the one above it with nothing in between, which is invisible while
-- each row is a filled card and turns into text touching text the moment they
-- are flat. Every block says how much room it wants around itself, in one
-- place, so a page cannot be spaced one way here and another way there.
function Grid:Wide(region, height, padTop, padBottom, indent)
    indent = indent or 0

    -- The width, here, once. A block placed by Layout is only ever given a
    -- POINT, so anything that does not set its own width is zero pixels wide:
    -- section headings were laid out correctly and invisible, and their rule
    -- line could not draw at all. Notes set their own, which is exactly why
    -- they showed and the headings did not.
    if region.SetWidth then region:SetWidth(self.width - indent) end

    self.items[#self.items + 1] = {
        region = region, height = height, wide = true, group = self.group,
        padTop = padTop or 0, padBottom = padBottom or UI.ROW_GAP,
        indent = indent,
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
-- The air above a heading is what separates two groups of settings. It is
-- deliberately much larger than the gap below it: a heading belongs to what
-- FOLLOWS it, and spacing it evenly makes a long page read as one column.
--
-- The very first heading on a page gets none of it - there is nothing above
-- it to be separated from, and a page that starts with a hole looks unloaded.
local SECTION_PAD_TOP = 16
local SECTION_PAD_BOTTOM = 3

function Grid:Section(title, key)
    self.group = key
    local padTop = (#self.items == 0) and 0 or SECTION_PAD_TOP

    if not key then
        return self:Wide(UI.SectionHeader(self.content, title), UI.SECTION_H,
            padTop, SECTION_PAD_BOTTOM)
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
    self:Wide(header, UI.SECTION_H, padTop, SECTION_PAD_BOTTOM)
    self.group = key
    return header
end

-- height is only needed for a note whose text is set LATER: the measured
-- height would be the empty string's, and the rows below would overlap it.
--
-- A note explains the row ABOVE it, so it sits close to that one and keeps
-- its distance from whatever comes next - and it is indented to the same
-- place a row's label starts, or the page has two left edges.
local NOTE_INDENT = 8

function Grid:Note(text, height)
    local note = UI.Hint(self.content, text)
    note:SetWidth(self.width - NOTE_INDENT)
    note:SetJustifyV("TOP")
    -- Width is set, so GetStringHeight reports the WRAPPED height. Measured
    -- after the width, never before: the unwrapped height is one line, and
    -- everything below would be laid out on top of the other two.
    return self:Wide(note, height or note:GetStringHeight(), 3, 11, NOTE_INDENT)
end

-- A half-width row. Two consecutive calls share a line.
function Grid:Row(label, opts)
    opts = opts or {}
    opts.controlWidth = opts.controlWidth or 150
    local row = UI.Row(self.content, label, opts)
    row:SetWidth(self.colWidth)
    self.items[#self.items + 1] = {
        region = row, height = row:GetHeight(), group = self.group,
        padTop = 0, padBottom = UI.ROW_GAP, indent = 0,
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
        padTop = 0, padBottom = UI.ROW_GAP, indent = 0,
    }
    self.widgets[#self.widgets + 1] = row
    return row
end

-- Places everything and returns the y the next free line would start at.
--
-- Every block carries its own padTop and padBottom, and the pads of two
-- neighbours COLLAPSE into one - the larger of them - the way margins do in
-- any layout engine worth the name. Adding them would make the gap under a
-- heading depend on what happened to come next, which is how a page ends up
-- with six different spacings nobody can account for.
function Grid:Layout()
    local y, column, lineHeight = 0, 0, 0
    local pending = 0        -- the bottom pad the previous block asked for

    local function EndLine()
        if column > 0 then
            y = y - lineHeight
            pending = math.max(pending, UI.ROW_GAP)
            column, lineHeight = 0, 0
        end
    end

    -- Opens the gap before a block: the larger of what the last one wanted
    -- below it and what this one wants above it, never the sum.
    local function OpenGap(padTop)
        y = y - math.max(pending, padTop or 0)
        pending = 0
    end

    local collapsed = self.collapsed or {}

    for _, item in ipairs(self.items) do
        local region = item.region
        local folded = item.group ~= nil and collapsed[item.group]

        if folded then
            if region then region:Hide() end
        elseif region and region.dkSkip then
            -- Skipped entirely, and its padding goes with it: a hidden row
            -- that still contributed a gap is a hole nobody can explain.
        elseif item.wide then
            EndLine()
            OpenGap(item.padTop)
            if region then
                region:ClearAllPoints()
                region:SetPoint("TOPLEFT", self.content, "TOPLEFT",
                    item.indent or 0, y)
                region:Show()
            end
            -- dkHeight lets a block that grows with its content - a grid
            -- gaining a row - report its real height instead of the one it
            -- happened to have when it was recorded.
            y = y - ((region and region.dkHeight) or item.height)
            pending = item.padBottom or UI.ROW_GAP
        else
            if column == 0 then OpenGap(item.padTop) end
            region:ClearAllPoints()
            region:SetPoint("TOPLEFT", self.content, "TOPLEFT",
                (item.indent or 0) + column * (self.colWidth + UI.COL_GAP), y)
            region:Show()
            lineHeight = math.max(lineHeight, item.height)
            column = column + 1
            if column >= 2 then EndLine() end
        end
    end
    EndLine()

    self.content:SetHeight(math.max(1, -y + 12))
    if self.scroll.Update then self.scroll.Update() end
    return y
end

function Grid:Refresh()
    for _, widget in ipairs(self.widgets) do
        if widget.Refresh then widget.Refresh() end
    end
    self:Layout()
end

---------------------------------------------------------------------------
-- Separator - one opaque hairline
---------------------------------------------------------------------------
function UI.Separator(parent, horizontal)
    local line = Tex(parent, "ARTWORK", C.separator[1], C.separator[2], C.separator[3], 1)
    if horizontal == false then line:SetWidth(1) else line:SetHeight(1) end
    return line
end

---------------------------------------------------------------------------
-- Card - the panel one thing lives in
--
-- A raised opaque surface with a hairline edge and a header strip. Everything
-- the user works on sits in one, so the window reads as a set of objects
-- rather than a wall of controls.
---------------------------------------------------------------------------
function UI.Card(parent, width)
    local card = CreateFrame("Frame", nil, parent)
    card:SetWidth(width)

    Fill(card, "BACKGROUND", C.surface)
    card.edge = ns.CreateBorder(card, 1, "BORDER")
    card.edge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)

    card.SetActive = function(self, active)
        self.edge:SetColor(
            active and C.accent[1] or C.edge[1],
            active and C.accent[2] or C.edge[2],
            active and C.accent[3] or C.edge[3], 1)
    end

    return card
end

---------------------------------------------------------------------------
-- Glyph - a small mark drawn from colour textures
--
-- No icon files. Every one of these is a handful of rectangles, so nothing
-- can 404 on a client that renamed an art path, and they all share one
-- weight and one colour instead of six different Blizzard icon styles.
---------------------------------------------------------------------------
local GLYPHS = {
    -- x, y, w, h in a 12x12 box, measured from the top left
    grid    = { {0,0,5,5}, {7,0,5,5}, {0,7,5,5}, {7,7,5,5} },
    bars    = { {0,0,12,3}, {0,5,8,3}, {0,10,12,3} },
    aura    = { {4,0,4,4}, {0,5,12,3}, {4,10,4,3} },
    sliders = { {0,2,12,2}, {8,0,2,6}, {0,8,12,2}, {2,6,2,6} },
    pulse   = { {0,8,2,4}, {3,4,2,8}, {6,0,2,12}, {9,6,2,6} },
    info    = { {5,0,3,3}, {5,5,3,7} },
    log     = { {0,0,12,2}, {0,5,9,2}, {0,10,6,2} },
}

function UI.Glyph(parent, kind, size, colour)
    size = size or 12
    local glyph = CreateFrame("Frame", nil, parent)
    glyph:SetSize(size, size)

    local scale = size / 12
    local parts = {}
    for _, rect in ipairs(GLYPHS[kind] or GLYPHS.grid) do
        local part = Tex(glyph, "ARTWORK", 1, 1, 1, 1)
        part:SetSize(rect[3] * scale, rect[4] * scale)
        part:SetPoint("TOPLEFT", glyph, "TOPLEFT", rect[1] * scale, -rect[2] * scale)
        parts[#parts + 1] = part
    end

    glyph.SetColor = function(_, r, g, b)
        for _, part in ipairs(parts) do part:SetColorTexture(r, g, b, 1) end
    end

    local c = colour or C.textDim
    glyph:SetColor(c[1], c[2], c[3])
    return glyph
end

---------------------------------------------------------------------------
-- NavItem - one entry in the left column
---------------------------------------------------------------------------
function UI.NavItem(parent, text, glyphKind, onClick)
    local item = CreateFrame("Button", nil, parent)
    item:SetHeight(32)

    -- A neutral raised fill plus an accent marker, rather than a block of
    -- tinted orange: the tint muddies the label sitting on it, and the marker
    -- says "you are here" more plainly than a colour ever does.
    item.bg = Fill(item, "BACKGROUND", C.surfaceHi)
    item.bg:Hide()

    item.marker = Tex(item, "ARTWORK", C.accent[1], C.accent[2], C.accent[3], 1)
    item.marker:SetPoint("TOPLEFT", item, "TOPLEFT", 0, 0)
    item.marker:SetPoint("BOTTOMLEFT", item, "BOTTOMLEFT", 0, 0)
    item.marker:SetWidth(3)
    item.marker:Hide()

    item.glyph = UI.Glyph(item, glyphKind, 12)
    item.glyph:SetPoint("LEFT", item, "LEFT", 16, 0)

    item.label = UI.Label(item, text, 12.5, C.textDim)
    item.label:SetPoint("LEFT", item.glyph, "RIGHT", 11, 0)
    item.label:SetWordWrap(false)

    item.SetActive = function(self, active)
        self.bg:SetShown(active)
        self.marker:SetShown(active)
        local c = active and C.text or C.textDim
        self.label:SetTextColor(c[1], c[2], c[3])
        local g = active and C.accent or C.textFaint
        self.glyph:SetColor(g[1], g[2], g[3])
    end

    item:SetScript("OnEnter", function(self)
        if self.bg:IsShown() then return end
        self.label:SetTextColor(C.text[1], C.text[2], C.text[3])
    end)
    item:SetScript("OnLeave", function(self)
        if self.bg:IsShown() then return end
        self.label:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    end)
    if onClick then item:SetScript("OnClick", onClick) end

    item:SetActive(false)
    return item
end

---------------------------------------------------------------------------
-- GhostButton - a label that acts, with no box around it
--
-- For the second-rank actions on a card header, where a filled button would
-- shout louder than the thing it belongs to.
---------------------------------------------------------------------------
function UI.GhostButton(parent, text, onClick, colour)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(20)

    local base = colour or C.textDim
    btn.label = UI.Label(btn, text, 11.5, base)
    btn.label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn:SetWidth(math.max(24, btn.label:GetStringWidth() + 14))

    btn:SetScript("OnEnter", function()
        btn.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    end)
    btn:SetScript("OnLeave", function()
        btn.label:SetTextColor(base[1], base[2], base[3])
    end)
    if onClick then btn:SetScript("OnClick", onClick) end

    btn.SetText = function(self, value)
        self.label:SetText(value)
        self:SetWidth(math.max(24, self.label:GetStringWidth() + 14))
    end

    -- The resting colour, not just the current one: colouring the label
    -- directly would be undone by the next OnLeave.
    btn.SetBaseColor = function(self, next_)
        base = next_ or C.textDim
        if not self:IsMouseOver() then
            self.label:SetTextColor(base[1], base[2], base[3])
        end
    end
    return btn
end

---------------------------------------------------------------------------
-- MiniSlider - a labelled slider on one compact line
--
--   Rows   -----o--------   3
--
-- The control the bar cards use. It is the whole point of the middle column:
-- the shape of a bar is two numbers, so they sit right under the bar and are
-- dragged, not typed.
--
-- cfg = { label, get, set, min, max, step, format, apply, labelWidth }
---------------------------------------------------------------------------
function UI.MiniSlider(parent, cfg)
    local VALUE_W = 30
    local labelWidth = cfg.labelWidth or 56

    local slider = CreateFrame("Frame", nil, parent)
    slider:SetHeight(20)

    local label = UI.Label(slider, cfg.label or "", 11.5, C.textDim)
    label:SetPoint("LEFT", slider, "LEFT", 0, 0)
    label:SetWidth(labelWidth)
    label:SetWordWrap(false)

    local value = UI.Label(slider, "", 12, C.text)
    value:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    value:SetWidth(VALUE_W)
    value:SetJustifyH("RIGHT")

    local bar = CreateFrame("Frame", nil, slider)
    bar:SetPoint("LEFT", label, "RIGHT", 8, 0)
    bar:SetPoint("RIGHT", value, "LEFT", -8, 0)
    bar:SetHeight(18)
    bar:EnableMouse(true)
    bar:EnableMouseWheel(true)

    local track = Tex(bar, "BACKGROUND", C.control[1], C.control[2], C.control[3], 1)
    track:SetPoint("LEFT", bar, "LEFT", 0, 0)
    track:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    track:SetHeight(3)

    local fill = Tex(bar, "ARTWORK", C.accent[1], C.accent[2], C.accent[3], 1)
    fill:SetPoint("LEFT", bar, "LEFT", 0, 0)
    fill:SetHeight(3)

    local knob = CreateFrame("Frame", nil, bar)
    knob:SetSize(11, 11)
    knob:SetFrameLevel(bar:GetFrameLevel() + 2)
    -- Round, via the same circular alpha mask the minimap button uses - that
    -- path is verified in use on this client. A square handle on a track
    -- reads as a rendering fault rather than a control.
    local knobFill = Fill(knob, "BACKGROUND", C.text)
    knobFill:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")

    local function Clamp(v)
        if v < cfg.min then v = cfg.min end
        if v > cfg.max then v = cfg.max end
        v = cfg.min + math.floor((v - cfg.min) / cfg.step + 0.5) * cfg.step
        return math.floor(v * 1000 + 0.5) / 1000
    end

    local function Commit(v)
        local wanted = Clamp(v)
        if wanted ~= cfg.get() then
            cfg.set(wanted)
            if cfg.apply then cfg.apply() end
        end
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
    bar:SetScript("OnMouseUp", function(self) self.dragging = false end)
    bar:SetScript("OnUpdate", function(self)
        if self.dragging then FromCursor() end
    end)
    bar:SetScript("OnMouseWheel", function(_, delta)
        Commit((cfg.get() or cfg.min) + delta * cfg.step)
    end)
    bar:SetScript("OnEnter", function()
        knob:SetScale(1.15)
        fill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    bar:SetScript("OnLeave", function() knob:SetScale(1) end)

    slider.Refresh = function()
        local current = cfg.get()
        if type(current) ~= "number" then current = cfg.min end
        value:SetText(cfg.format and cfg.format(current) or tostring(current))

        local span = cfg.max - cfg.min
        local pct = span > 0 and ((current - cfg.min) / span) or 0
        local width = math.max(1, bar:GetWidth())
        fill:SetWidth(math.max(1, width * pct))
        knob:ClearAllPoints()
        knob:SetPoint("CENTER", bar, "LEFT", width * pct, 0)
    end

    return slider
end

---------------------------------------------------------------------------
-- SpellRow - one entry in the right column's spell list
---------------------------------------------------------------------------
function UI.SpellRow(parent, width, height)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(width, height or 32)

    -- Drag it onto a cell. Clicking works and always has, but picking a spell
    -- up and putting it where you want it is the gesture people reach for
    -- first - and until now the list simply did not answer it.
    row:RegisterForDrag("LeftButton")

    row:SetScript("OnDragStart", function(self)
        if not self.dkSpellID then return end

        local proxy = GetDragProxy()
        proxy:SetSize(30, 30)
        proxy.icon:SetTexture(self.icon:GetTexture())
        proxy:Show()

        -- The proxy follows the cursor and the target cell lights up, so the
        -- drop is aimed rather than hoped for. Driven from the ROW, because
        -- the grid it will land on is not known yet.
        self:SetScript("OnUpdate", function()
            local scale = UIParent:GetEffectiveScale()
            local x, y = GetCursorPosition()
            proxy:ClearAllPoints()
            proxy:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)

            local grid, cell = UI.CellUnderCursor()
            if row.dkMarked and row.dkMarked ~= grid then
                row.dkMarked.HideMarker()
            end
            row.dkMarked = grid
            if grid then grid.ShowMarker(cell) end
        end)
    end)

    row:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        if dragProxy then dragProxy:Hide() end

        local grid, cell = UI.CellUnderCursor()
        if row.dkMarked then row.dkMarked.HideMarker() end
        row.dkMarked = nil

        if grid and cell and grid.dkDrop and self.dkSpellID then
            grid.dkDrop(cell, self.dkSpellID)
        end
    end)

    row.bg = Fill(row, "BACKGROUND", C.surface)
    row.bg:Hide()

    -- Green stripe: this spell is already on the bar you have selected. On the
    -- left edge, where the eye scans down a list, so "have I got that one" is
    -- answered without reading a word.
    row.mark = Tex(row, "ARTWORK", C.inUse[1], C.inUse[2], C.inUse[3], 1)
    row.mark:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -3)
    row.mark:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 3)
    row.mark:SetWidth(3)
    row.mark:Hide()

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", row, "LEFT", 9, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Widths rather than a second anchor: a font string given both TOPLEFT
    -- and RIGHT is told two different vertical positions, and what comes out
    -- is not what was meant.
    local textWidth = width - 44

    row.name = UI.Label(row, "", 12, C.text)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 9, 1)
    row.name:SetWidth(textWidth)
    row.name:SetWordWrap(false)

    row.meta = UI.Label(row, "", 10, C.textFaint)
    row.meta:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.meta:SetWidth(textWidth)
    row.meta:SetWordWrap(false)

    -- cell is the cell number it sits in, or nil when it is not on the bar.
    -- known is false for a spell the current talent build does not have: it
    -- stays pickable, because a bar is often built for the build you are
    -- about to switch into, but it must not look available.
    row.SetUsed = function(self, cell, known)
        self.mark:SetShown(cell ~= nil)
        self.dkUsedIn = cell

        local colour = C.text
        if not known then
            colour = C.textFaint
        elseif cell then
            colour = C.inUse
        end
        self.name:SetTextColor(colour[1], colour[2], colour[3])

        self.icon:SetDesaturated(not known)
        self.icon:SetVertexColor(known and 1 or 0.55, known and 1 or 0.55,
            known and 1 or 0.55)
    end

    -- The game's own tooltip, not a copy of it. What a spell does is Blizzard's
    -- text to keep current, and it changes every patch; anything written here
    -- would be a second version of it going quietly out of date.
    --
    -- Anchored LEFT because this list lives against the right edge of the
    -- screen, where a tooltip growing rightwards would run off it.
    row.dkLines = {}

    row:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(
            self.dkUsedIn and C.inUseSoft[1] or C.surface[1],
            self.dkUsedIn and C.inUseSoft[2] or C.surface[2],
            self.dkUsedIn and C.inUseSoft[3] or C.surface[3], 1)
        self.bg:Show()

        if not (GameTooltip and self.dkSpellID) then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")

        -- An ID the client does not know throws rather than returning empty.
        if not pcall(GameTooltip.SetSpellByID, GameTooltip, self.dkSpellID) then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine(self.name:GetText() or "")
            GameTooltip:AddLine(tostring(self.dkSpellID), 0.5, 0.5, 0.5)
        end

        for _, line in ipairs(self.dkLines) do
            GameTooltip:AddLine(line.text, line.r or 0.65, line.g or 0.67,
                line.b or 0.71, true)
        end
        GameTooltip:Show()
    end)

    row:SetScript("OnLeave", function(self)
        self.bg:Hide()
        if GameTooltip then GameTooltip:Hide() end
    end)

    return row
end

---------------------------------------------------------------------------
-- ListHeading - a small caption inside a scrolling list
---------------------------------------------------------------------------
function UI.ListHeading(parent, width, height)
    local heading = CreateFrame("Frame", nil, parent)
    heading:SetSize(width, height or 24)

    heading.label = UI.Label(heading, "", 10, C.textFaint)
    heading.label:SetPoint("BOTTOMLEFT", heading, "BOTTOMLEFT", 0, 5)
    heading.label:SetWordWrap(false)

    -- Both ends resolve to the same height: the label's bottom sits 5 above
    -- the heading's, so +5 there and +10 here are the same line. Two anchors
    -- that disagree vertically do not make a slanted rule, they make a wrong one.
    heading.line = UI.Separator(heading)
    heading.line:SetPoint("BOTTOMLEFT", heading.label, "BOTTOMRIGHT", 8, 5)
    heading.line:SetPoint("BOTTOMRIGHT", heading, "BOTTOMRIGHT", 0, 10)

    heading.SetText = function(self, text)
        self.label:SetText((text or ""):upper())
    end
    return heading
end

---------------------------------------------------------------------------
-- ChipRow - small filter buttons that flow onto as many lines as they need
--
-- cfg = { chips = {{key, text}}, current() -> key, onSelect(key), gap }
-- Returns the frame; call Refresh() to re-colour, Layout() for its height.
---------------------------------------------------------------------------
function UI.ChipRow(parent, width, cfg)
    local GAP = cfg.gap or 5
    local ROW = 21

    local row = CreateFrame("Frame", nil, parent)
    row:SetWidth(width)

    local chips = {}
    for index, spec in ipairs(cfg.chips) do
        local chip = CreateFrame("Button", nil, row)
        chip:SetHeight(ROW)

        chip.bg = Fill(chip, "BACKGROUND", C.control)
        chip.edge = ns.CreateBorder(chip, 1, "BORDER")
        chip.edge:SetColor(C.separator[1], C.separator[2], C.separator[3], 1)

        chip.label = UI.Label(chip, spec.text, 11, C.textDim)
        chip.label:SetPoint("CENTER", chip, "CENTER", 0, 0)
        chip:SetWidth(chip.label:GetStringWidth() + 18)

        chip:SetScript("OnClick", function() cfg.onSelect(spec.key) end)
        chip:SetScript("OnEnter", function(self)
            if cfg.current() == spec.key then return end
            self.bg:SetColorTexture(C.controlHi[1], C.controlHi[2], C.controlHi[3], 1)
        end)
        chip:SetScript("OnLeave", function(self)
            if cfg.current() == spec.key then return end
            self.bg:SetColorTexture(C.control[1], C.control[2], C.control[3], 1)
        end)

        chips[index] = chip
    end

    -- Flowed, not fixed: the labels are words, and a fixed grid would either
    -- clip "Cooldowns" or leave "All" swimming in its own cell.
    row.Layout = function()
        local x, y, height = 0, 0, ROW
        for _, chip in ipairs(chips) do
            local chipWidth = chip:GetWidth()
            if x > 0 and x + chipWidth > width then
                x, y = 0, y - (ROW + GAP)
                height = height + ROW + GAP
            end
            chip:ClearAllPoints()
            chip:SetPoint("TOPLEFT", row, "TOPLEFT", x, y)
            x = x + chipWidth + GAP
        end
        row:SetHeight(height)
        return height
    end

    row.Refresh = function()
        local current = cfg.current()
        for index, chip in ipairs(chips) do
            local active = cfg.chips[index].key == current
            local bg = active and C.accentSoft or C.control
            chip.bg:SetColorTexture(bg[1], bg[2], bg[3], 1)
            chip.edge:SetColor(
                active and C.accentDim[1] or C.separator[1],
                active and C.accentDim[2] or C.separator[2],
                active and C.accentDim[3] or C.separator[3], 1)
            local text = active and C.accent or C.textDim
            chip.label:SetTextColor(text[1], text[2], text[3])
        end
    end

    row.Layout()
    row.Refresh()
    return row
end
