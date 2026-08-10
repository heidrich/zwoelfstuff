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
    canvasBg   = { 0.039, 0.043, 0.051 },  -- #0A0B0D  behind the window
    windowBg   = { 0.071, 0.078, 0.094 },  -- #121418  the window, middle column
    sidebarBg  = { 0.055, 0.063, 0.075 },  -- #0E1013  rail AND inspector
    well       = { 0.043, 0.051, 0.063 },  -- #0B0D10  preview, input, overlay
    surface    = { 0.098, 0.110, 0.129 },  -- #191C21  a card, the active nav row
    control    = { 0.129, 0.145, 0.169 },  -- #21252B  stepper, select, chip
    controlHi  = { 0.200, 0.224, 0.255 },  -- #333941  control under the cursor
    separator  = { 0.122, 0.137, 0.165 },  -- #1F232A  hairline
    edge       = { 0.165, 0.184, 0.216 },  -- #2A2F37  card outline, window edge

    accent     = { 1.000, 0.478, 0.239 },  -- #FF7A3D  ZwoelfStuff orange
    accentSoft = { 0.180, 0.118, 0.082 },  -- #2E1E15  toggle track on, badge bed
    accentCool = { 0.494, 0.776, 0.831 },  -- #7EC6D4  references, category badges

    -- Green means "this one is already on the bar you have selected". Only
    -- ever used for that, so it stays readable as a state rather than decoration.
    inUse      = { 0.404, 0.788, 0.443 },  -- #67C971
    inUseSoft  = { 0.086, 0.149, 0.106 },  -- #16261B

    danger     = { 0.898, 0.353, 0.318 },  -- #E5645A  destructive actions ONLY
    warning    = { 0.890, 0.702, 0.255 },  -- #E3B341  log level WARN

    text       = { 0.937, 0.945, 0.957 },  -- #EFF1F4  titles, values, active row
    textBody   = { 0.788, 0.812, 0.847 },  -- #C9CFD8  row labels in the inspector
    textDim    = { 0.608, 0.639, 0.686 },  -- #9BA3AF  secondary, inactive nav
    textFaint  = { 0.384, 0.416, 0.463 },  -- #626A76  meta, sublines
    textGhost  = { 0.306, 0.337, 0.380 },  -- #4E5661  eyebrows, disabled
}

-- Two more the design names in prose rather than in the token list, and both
-- earn a name because they appear in more than one place.
--
-- overlayEdge is what tells an overlay it is ON TOP of the page. There are no
-- shadows here, so the only way to lift a popup off its background is an
-- outline one step brighter than any edge on the page itself.
C.overlayEdge     = { 0.235, 0.259, 0.294 }  -- #3C424B  popup outline, scroll grip
C.accentCoolSoft  = { 0.082, 0.133, 0.153 }  -- #152227  bed for a category badge

-- Derived, not designed. The palette above has no entry for either, but both
-- are asked for by name in a couple of dozen places, so they are computed from
-- the ladder rather than left to drift back to their old values.
--
--   surfaceHi   a card under the cursor - which in this ladder is simply the
--               next step up, the same one a control sits on
--   accentDim   orange that is NOT the current thing: Edit Mode draws every
--               bar's outline, and only the selected one may be full accent.
--               45% of the way back to the window ground.
C.surfaceHi = C.control
C.accentDim = {
    C.accent[1] * 0.55 + C.windowBg[1] * 0.45,
    C.accent[2] * 0.55 + C.windowBg[2] * 0.45,
    C.accent[3] * 0.55 + C.windowBg[3] * 0.45,
}

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
UI.SECTION_H  = 32
UI.COL_GAP    = 18

-- The window, and the three columns it is made of. Stated here rather than in
-- Options.lua because the inspector needs to know how wide it is in order to
-- decide what fits on a row, and it is not the thing that creates itself.
UI.WINDOW_W    = 1360
UI.WINDOW_H    = 760
UI.RAIL_W      = 168
UI.INSPECTOR_W = 400
UI.CONTENT_W   = UI.WINDOW_W - UI.RAIL_W - UI.INSPECTOR_W  -- 792

-- One height for the whole window's header band, so the rule under every
-- heading lands on the same line no matter which column it is in.
UI.HEADER_H = 62

-- Fixed heights, so that two controls of different kinds on the same row have
-- the same silhouette.
UI.CARD_HEAD_H = 40
UI.NAV_ITEM_H  = 30
UI.CONTROL_H   = 24   -- select
UI.BUTTON_H    = 26   -- every screen in the design says 26, so 26 it is
UI.STEPPER_H   = 22

-- The one spacing rhythm: 4 · 8 · 12 · 16 · 20 · 24. Only these six for layout
-- gaps and container padding. Padding INSIDE a control belongs to the control
-- and is not on the scale: button 12, chip 6-8, stepper 0.
UI.PAD    = 16
UI.GAP    = 8
UI.RADIUS = 0

-- Five sizes, and there is no sixth. Seven had crept in, which is how a panel
-- stops having a hierarchy: if everything is nearly the same size, size stops
-- carrying meaning and colour has to do all the work on its own.
--
-- The design asks for weight 600 on title, card and eyebrow. There is no
-- weight axis here - a FontString gets a font FILE, and the panel font is
-- whatever the user picked in LibSharedMedia, which may ship one cut. So the
-- emphasis those three would have taken from weight is taken from size and
-- colour instead: a title is 20px `text` against 13px `textDim`, which is a
-- wider gap than 600-against-400 would have been anyway.
UI.FS = {
    title   = 20,   -- page title in the header band
    card    = 15,   -- bar name, inspector title
    row     = 13,   -- row labels, nav, lists
    meta    = 12,   -- sublines, hints
    eyebrow = 10,   -- section heads, badges - ALWAYS upper case
}

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
    return UI.Label(parent, text, UI.FS.meta, C.textDim)
end

-- Eyebrow - the small upper-case caption over a section, a group of nav rows,
-- or inside a badge.
--
-- The design asks for .14em tracking. There is no letter spacing here:
-- FontString:SetSpacing sets LINE spacing, and nothing in the client exposes
-- the other one. The usual workaround is to push a space between every
-- character, and it is rejected on purpose - a space in a proportional font is
-- roughly .3em, so it would be double the tracking asked for, it would make
-- "SHIPPED WITH ZWOELFSTUFF" wider than the column it lives in, and it turns
-- a caption into a string that can no longer be measured or compared.
--
-- Upper case at 10px against a body of 13px carries the same signal on its own.
function UI.Eyebrow(parent, text, colour)
    return UI.Label(parent, (text or ""):upper(), UI.FS.eyebrow,
        colour or C.textGhost)
end

-- Badge - upper-case caption on its own bed. Three meanings, and they are the
-- only three: what KIND of thing this is (cool), what STATE it is in (green),
-- and which one is CURRENT (accent).
function UI.Badge(parent, text, kind)
    local fg, bed = C.accentCool, C.accentCoolSoft
    if kind == "state" then fg, bed = C.inUse, C.inUseSoft
    elseif kind == "current" then fg, bed = C.accent, C.accentSoft end

    local badge = CreateFrame("Frame", nil, parent)
    badge.bg = Fill(badge, "BACKGROUND", bed)
    badge.label = UI.Eyebrow(badge, text, fg)
    badge.label:SetPoint("CENTER", badge, "CENTER", 0, 0)

    -- Padding 4 vertical / 6 horizontal is the control's own, not the layout's,
    -- so it does not sit on the spacing scale.
    badge.SetLabel = function(self, value)
        self.label:SetText((value or ""):upper())
        self:SetSize(self.label:GetStringWidth() + 12,
            self.label:GetStringHeight() + 8)
    end
    badge:SetLabel(text)
    return badge
end

---------------------------------------------------------------------------
-- Button - flat, accent on hover
---------------------------------------------------------------------------
-- Lighten a colour towards white. Used for the hovered state of the two
-- styles that have no background to change - a fill cannot report the cursor
-- if there is no fill.
local function Lift(colour, amount)
    return {
        colour[1] + (1 - colour[1]) * amount,
        colour[2] + (1 - colour[2]) * amount,
        colour[3] + (1 - colour[3]) * amount,
    }
end

-- HOW WIDE A BUTTON IS, IS NOT A DECISION ANYBODY SHOULD BE MAKING.
--
-- Owner, 2026-08-10: "auch die button größen sind wahnsinn." He is right and
-- the count says so: 54, 84, 96, 106, 110, 120, 130, 132, 140, 150, 156, 170,
-- 190, 200, 220 - fifteen widths, every one of them typed by hand at a call
-- site and none of them measured. A label that grew by a word got clipped; a
-- short one sat in a slab.
--
-- The design gives the answer and it is not a number: "Innenabstand 12-14".
-- So the button is as wide as its words plus its padding, with a floor so
-- that "Done" is still a target and a ceiling so a long label wraps the
-- thinking rather than the layout.
UI.BUTTON_PAD = 14
UI.BUTTON_MIN = 84
UI.BUTTON_MAX = 260

function UI.ButtonWidth(text)
    local ruler = UI.ruler
    if not ruler then
        ruler = UIParent:CreateFontString(nil, "ARTWORK")
        UI.ruler = ruler
    end
    ns.StyleUIFont(ruler, UI.FS.meta)
    ruler:SetText(text or "")

    local wide = (ruler:GetStringWidth() or 0) + UI.BUTTON_PAD * 2
    return math.max(UI.BUTTON_MIN, math.min(UI.BUTTON_MAX, math.ceil(wide)))
end

function UI.Button(parent, text, width, onClick, style)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or UI.ButtonWidth(text), UI.BUTTON_H)

    -- Four weights, and they are not interchangeable:
    --   nil        an ordinary action - a surface with an outline
    --   "primary"  the one action a page is for - SOLID accent, dark text.
    --              There is at most one of these visible per column.
    --   "ghost"    an action that belongs to the band it sits in and must not
    --              compete with the content under it - no fill at all
    --   "link"     a reference, not an action on this page
    local fg, base, hover, outline = C.text, C.surface, C.control, C.edge
    if style == "primary" then
        -- Dark text on orange, not orange text on dark. This is the one place
        -- the accent is a FILL, which is what makes it the loudest thing in
        -- the column and therefore the thing that has to be rarest.
        fg, base, hover, outline = C.windowBg, C.accent, Lift(C.accent, 0.15), nil
    elseif style == "ghost" then
        fg, base, hover, outline = C.textDim, nil, C.surface, nil
    elseif style == "link" then
        fg, base, hover, outline = C.accentCool, nil, nil, nil
    end

    local bg = Fill(btn, "BACKGROUND", base or C.surface)
    if not base then bg:Hide() end

    local edge
    if outline then
        edge = ns.CreateBorder(btn, 1, "BORDER")
        edge:SetColor(outline[1], outline[2], outline[3], 1)
    end

    local label = UI.Label(btn, text, UI.FS.meta, fg)
    label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.label = label

    -- An optional mark in front of the label, added after the fact so the four
    -- weights above stay one signature. The PAIR is what gets centred: the
    -- label moves right by half the mark's block and the mark hangs off its
    -- left edge, so a button with one and a button without both read as
    -- centred rather than one of them sitting off to the side.
    btn.SetIcon = function(self, kind)
        if self.mark then
            self.mark:SetKind(kind)
            return
        end
        self.mark = UI.Glyph(self, kind, 12, fg)
        self.mark:SetPoint("RIGHT", label, "LEFT", -4, 0)
        label:SetPoint("CENTER", self, "CENTER", 10, 0)
    end

    local hoverFg = style == "link" and Lift(C.accentCool, 0.25)
        or (style == "ghost" and C.text or nil)

    btn:SetScript("OnEnter", function()
        if not btn:IsEnabled() then return end
        if hover then
            bg:SetColorTexture(hover[1], hover[2], hover[3], 1)
            bg:Show()
        end
        if hoverFg then
            label:SetTextColor(hoverFg[1], hoverFg[2], hoverFg[3])
            if btn.mark then btn.mark:SetColor(hoverFg[1], hoverFg[2], hoverFg[3]) end
        end
    end)
    btn:SetScript("OnLeave", function()
        if base then
            bg:SetColorTexture(base[1], base[2], base[3], 1)
        else
            bg:Hide()
        end
        label:SetTextColor(fg[1], fg[2], fg[3])
        if btn.mark then btn.mark:SetColor(fg[1], fg[2], fg[3]) end
    end)
    if onClick then btn:SetScript("OnClick", onClick) end

    -- SetEnabled exists on Button and still does the input half; only the
    -- greying is ours. Wrapped rather than hooked, because a hook cannot
    -- change what the widget already did and this is not a secure frame.
    local baseSetEnabled = btn.SetEnabled
    btn.SetEnabled = function(self, enabled)
        baseSetEnabled(self, enabled)
        local c = enabled and fg or C.textGhost
        label:SetTextColor(c[1], c[2], c[3])
        if self.mark then self.mark:SetColor(c[1], c[2], c[3]) end
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
-- The widest control there is - a select. Everything else is right-aligned
-- inside the same slot so that a column of mixed controls has one right edge.
local CONTROL_W = 168

-- A control narrower than the slot gives the label the difference back. The
-- slot exists to align right edges, not to reserve space nobody uses: the
-- stepper is 96 of the 168, and without this a label would be cut off at 192
-- while 72 pixels sat empty next to it.
local function ClaimRow(row, control)
    row.label:SetPoint("RIGHT", control, "LEFT", -UI.GAP, 0)
end

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
    -- the background, and it runs the full width of the row so that it lines
    -- up with the rule under a section heading and with the column edge.
    row.rule = Tex(row, "BACKGROUND", C.separator[1], C.separator[2],
        C.separator[3], 1)
    row.rule:SetHeight(1)
    row.rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)

    -- textBody, not text. A column of forty labels at full white is forty
    -- things shouting; the value on the right is what the eye is looking for,
    -- and it is the only thing on the row in `text`.
    row.label = UI.Label(row, text, UI.FS.row, C.textBody)
    row.label:SetPoint("LEFT", row, "LEFT", 0, opts.sublabel and 8 or 0)
    row.label:SetWordWrap(false)

    -- A mark in front of the label, for the runs of rows that are one KIND of
    -- thing repeated: six places, four conditions. There the labels differ by
    -- a single word and the eye has to read all six to find the one it wants;
    -- with a mark it finds it without reading. Not on ordinary rows - a mark
    -- next to every setting is decoration, and decoration next to a real
    -- signal makes the signal worth less.
    if opts.icon then
        row.mark = UI.Glyph(row, opts.icon, 12, C.textFaint)
        row.mark:SetPoint("LEFT", row, "LEFT", -2, opts.sublabel and 8 or 0)
        row.label:SetPoint("LEFT", row, "LEFT", 22, opts.sublabel and 8 or 0)
    end

    if opts.sublabel then
        row.sub = UI.Label(row, opts.sublabel, UI.FS.meta, C.textFaint)
        row.sub:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -3)
        row.sub:SetWordWrap(false)
    end

    -- Flush with the column edge, not inset. The padding a row needs is the
    -- SECTION's - inset again here and every control sits 8px short of the
    -- rule above it, which is the one misalignment that is visible from
    -- across the room.
    row.slot = CreateFrame("Frame", nil, row)
    row.slot:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.slot:SetSize(opts.controlWidth or CONTROL_W, row:GetHeight() - 6)

    -- The label must never run under the control.
    row.label:SetPoint("RIGHT", row.slot, "LEFT", -UI.GAP, 0)

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self) self.bg:Show() end)
    row:SetScript("OnLeave", function(self) self.bg:Hide() end)

    row.SetRelevant = function(self, relevant)
        self.dkSkip = not relevant
        self:SetShown(relevant)
    end

    return row
end

-- Turns a settings ROW into one that stands for a spell: the client's own
-- icon in front of the label, and the client's own tooltip on hover.
--
-- Not UI.SpellRow, which builds a row of the spell PALETTE from scratch and
-- is a different thing with a confusingly similar name - this one dresses a
-- row that already exists. The two collided under one name for a few
-- minutes and the static check caught it: the later definition simply won,
-- and the caller here would have got the palette's builder instead.
--
-- The picker got icon and tooltip in 4.44.1 and the list of what you picked
-- did not, so choosing a defensive showed you an icon and living with the
-- choice showed you a column of same-grey names. One rule, one place, and
-- every future list of spells - the externals panel is next - calls this
-- instead of growing its own copy.
--
-- Pooled rows are re-labelled rather than rebuilt, so the wiring happens
-- once and the SPELL is a field the hover reads at hover time. A closure
-- would answer for whichever spell the row was built with.
function UI.MakeRowASpell(row, spellID, texture)
    if not row.dkSpellIcon then
        row.dkSpellIcon = row:CreateTexture(nil, "ARTWORK")
        row.dkSpellIcon:SetSize(18, 18)
        row.dkSpellIcon:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.dkSpellIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row:HookScript("OnEnter", function(entered)
            if not (entered.dkSpellID and GameTooltip) then return end
            GameTooltip:SetOwner(entered, "ANCHOR_RIGHT")
            -- pcall: a spell the client would rather not describe must cost
            -- a missing tooltip, never an error thrown under the cursor.
            if pcall(GameTooltip.SetSpellByID, GameTooltip, entered.dkSpellID) then
                GameTooltip:Show()
            else
                GameTooltip:Hide()
            end
        end)
        row:HookScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
    end

    row.dkSpellID = spellID
    local icon = texture or (spellID and ns.SpellTexture(spellID)) or nil
    row.dkSpellIcon:SetTexture(icon)
    row.dkSpellIcon:SetShown(icon ~= nil)

    -- The label carries BOTH its points - left of the row and right of the
    -- control - so it is re-anchored as a pair or it runs under the button.
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", icon and 24 or 0, 0)
    row.label:SetPoint("RIGHT", row.slot, "LEFT", -UI.GAP, 0)
    return row
end

-- The same for a CONSUMABLE. A potion has an icon and a tooltip, so it
-- shows both - the rule does not care that it is an item.
function UI.MakeRowAnItem(row, itemID)
    if not row.dkItemIcon then
        row.dkItemIcon = row:CreateTexture(nil, "ARTWORK")
        row.dkItemIcon:SetSize(18, 18)
        row.dkItemIcon:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.dkItemIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row:HookScript("OnEnter", function(entered)
            if not (entered.dkItemID and GameTooltip) then return end
            GameTooltip:SetOwner(entered, "ANCHOR_RIGHT")
            if pcall(GameTooltip.SetItemByID, GameTooltip, entered.dkItemID) then
                GameTooltip:Show()
            else
                GameTooltip:Hide()
            end
        end)
        row:HookScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
    end

    row.dkItemID = itemID
    local icon = itemID and ns.Death and ns.Death.ItemIcon(itemID) or nil
    row.dkItemIcon:SetTexture(icon)
    row.dkItemIcon:SetShown(icon ~= nil)

    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", icon and 24 or 0, 0)
    row.label:SetPoint("RIGHT", row.slot, "LEFT", -UI.GAP, 0)
    return row
end

---------------------------------------------------------------------------
-- A ROW OF SPELLS, drawn the way this game draws spells
--
-- The owner's rule: anything with an icon and a tooltip shows both. Written
-- into a sentence that wraps, that is an inline texture escape - and a list
-- of six of them packed with spaces wraps wherever it likes, leaves a name
-- stranded on the next line without its icon, and reads as a mess. He said
-- so: "icons sind alle verschoben, das kann man auch in einer eigenen zeile
-- anzeigen. einfach bissel schoenes ui machen".
--
-- So a list of spells is LAID OUT, not written: icon and name as one chip,
-- chips flowing left to right, wrapping onto as many rows as they need, the
-- client's own tooltip on each. One implementation, used by the death
-- window's footer and the replay's legend, because two would drift.
--
-- Paint(entries) takes { spellID, name, suffix } and returns the height it
-- used, so whatever sits above it can be anchored to the real number rather
-- than to a guess about how many rows there would be.
---------------------------------------------------------------------------
function UI.SpellChips(parent, opts)
    opts = opts or {}
    local size = opts.size or 11
    local iconSize = opts.iconSize or 16
    local rowHeight = opts.rowHeight or (iconSize + 5)
    local gap = opts.gap or 14
    local width = opts.width or 400

    local strip = CreateFrame("Frame", nil, parent)
    strip:SetSize(width, rowHeight)
    strip.chips = {}

    for index = 1, (opts.max or 12) do
        local chip = CreateFrame("Button", nil, strip)
        chip:SetHeight(rowHeight)

        chip.icon = chip:CreateTexture(nil, "ARTWORK")
        chip.icon:SetSize(iconSize, iconSize)
        chip.icon:SetPoint("LEFT", chip, "LEFT", 0, 0)
        chip.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        chip.label = UI.Label(chip, "", size, opts.colour or UI.C.text)
        chip.label:SetPoint("LEFT", chip.icon, "RIGHT", 5, 0)
        chip.label:SetWordWrap(false)

        chip:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
            -- A consumable gets the client's item tooltip, a spell its spell
            -- tooltip. Same rule either way: whatever has one, shows it.
            local shown = false
            if self.itemID then
                shown = pcall(GameTooltip.SetItemByID, GameTooltip, self.itemID)
            elseif self.spellID then
                shown = pcall(GameTooltip.SetSpellByID, GameTooltip, self.spellID)
            end
            if shown then GameTooltip:Show() else GameTooltip:Hide() end
        end)
        chip:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        chip:Hide()
        strip.chips[index] = chip
    end

    -- Returns the height used and how many entries did not fit, so a caller
    -- can say "+3 more" rather than silently dropping them.
    function strip.Paint(entries)
        local x, y, rows, shown = 0, 0, 1, 0

        for _, entry in ipairs(entries or {}) do
            local chip = strip.chips[shown + 1]
            if not chip then break end

            local texture
            if entry.itemID and C_Item and C_Item.GetItemIconByID then
                local ok, icon = pcall(C_Item.GetItemIconByID, entry.itemID)
                if ok then texture = icon end
            end
            texture = texture
                or (entry.spellID and ns.SpellTexture(entry.spellID))
            chip.spellID = entry.spellID
            chip.itemID = entry.itemID
            chip.icon:SetTexture(texture)
            chip.icon:SetShown(texture and true or false)
            chip.label:SetText((entry.name or "?") .. (entry.suffix or ""))
            chip.label:SetPoint("LEFT", chip.icon, "RIGHT",
                texture and 5 or -iconSize, 0)

            local chipWidth = (texture and (iconSize + 5) or 0)
                + (chip.label:GetStringWidth() or 40)
            -- Wrap before drawing, not after: a chip that has already been
            -- placed cannot be moved without another pass.
            if x > 0 and x + chipWidth > width then
                x, y, rows = 0, y - rowHeight, rows + 1
            end

            chip:SetWidth(chipWidth)
            chip:ClearAllPoints()
            chip:SetPoint("TOPLEFT", strip, "TOPLEFT", x, y)
            chip:Show()

            x = x + chipWidth + gap
            shown = shown + 1
        end

        for index = shown + 1, #strip.chips do
            strip.chips[index].spellID = nil
            strip.chips[index].itemID = nil
            strip.chips[index]:Hide()
        end

        -- Nothing shown is no height at all, not one empty row: whatever is
        -- anchored to this strip must close up rather than leave a gap
        -- where a list would have been.
        local height = (shown > 0) and (rows * rowHeight) or 0
        strip:SetHeight(math.max(1, height))
        return height, math.max(0, #(entries or {}) - shown)
    end

    return strip
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
    local label = UI.Eyebrow(header, caption)
    label:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", onToggle and 13 or 0, 7)

    -- The rule runs from the caption to the right EDGE of the column, on the
    -- caption's own baseline. That is what ties a heading to the rows under it
    -- rather than leaving it floating over them.
    local line = Tex(header, "ARTWORK", C.line[1], C.line[2], C.line[3], C.line[4])
    line:SetPoint("BOTTOMLEFT", label, "BOTTOMRIGHT", 10, 4)
    line:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 7)
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
    -- 32 by 18 with a 14 knob: square, no outline, no animation. The track
    -- carries the state as much as the knob position does, which is what lets
    -- it stay readable at this size - a 4px travel on its own is not a signal.
    local toggle = CreateFrame("Button", nil, row.slot)
    toggle:SetSize(32, 18)
    toggle:SetPoint("RIGHT", row.slot, "RIGHT", 0, 0)
    ClaimRow(row, toggle)

    local track = Fill(toggle, "BACKGROUND", C.control)

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
            knob:SetColorTexture(C.textGhost[1], C.textGhost[2], C.textGhost[3], 1)
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
-- THE KEY THE PLAYER PRESSED, as the game names it
--
-- Setting a key is a MODE on the screen now, not a control in a row - see
-- Core/Keys.lua and the owner's own description of it. What stayed here is
-- the one piece of it that is pure and belongs to the design system: turning
-- a key press into the string the binding system uses.
---------------------------------------------------------------------------
-- The key the player actually pressed, as the game names it. Modifiers are a
-- prefix, and a modifier PRESSED ALONE is not a binding - it is the first
-- half of one, and taking it would make every combination impossible to
-- enter.
local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, UNKNOWN = true,
}

function UI.Chord(key)
    if type(key) ~= "string" or key == "" then return nil end
    if MODIFIER_KEYS[key] then return nil end

    local prefix = ""
    if IsAltKeyDown and IsAltKeyDown() then prefix = "ALT-" end
    if IsControlKeyDown and IsControlKeyDown() then prefix = prefix .. "CTRL-" end
    if IsShiftKeyDown and IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
    return prefix .. key
end

---------------------------------------------------------------------------
-- Counter - minus, number, plus
--
-- For whole numbers you count rather than tune: rows, columns, how many of
-- something. A slider is the wrong control for those - it is imprecise for
-- small ranges and it does not read as "add one".
---------------------------------------------------------------------------
function UI.Counter(row, cfg)
    -- Kept as its own name because "count me one more" and "tune this" read
    -- differently at the call site, but there is only one control now. It is
    -- the narrow one: a count is at most three digits.
    return UI.Slider(row, {
        min = cfg.min, max = cfg.max, step = 1, compact = true,
        get = cfg.get, set = cfg.set, apply = cfg.apply,
        format = function(v) return tostring(math.floor(v + 0.5)) end,
    })
end

---------------------------------------------------------------------------
-- Stepper - minus, value, plus. There is no slider in this window any more.
--
-- A slider is the wrong control for everything on these pages. It is a
-- fixed-width track standing in for a range, so its precision is whatever
-- pixels-per-step happens to fall out of the column width: on a 0-to-1 opacity
-- in a 150px slot, one pixel is .007 and no exact value is reachable by hand.
-- Every number here is either small and counted (rows, columns) or tuned in
-- known steps (scale .05, opacity 5%), and both of those are "give me one
-- more", which is a button.
--
--   [ - ] [  value  ] [ + ]
--     22      36|52     22        all 22 tall, gap 1
--
-- 52 wide in the inspector (96 total, leaving the label 264 of the 368), 36 in
-- the narrower card column (80 total).
--
-- The value stays an EDIT BOX. That is not in the design, and it is not
-- negotiable either: it was asked for directly, and a stepper without it is a
-- worse slider - reaching 250 from 24 is 226 clicks. Click it and type.
---------------------------------------------------------------------------
local function StepperButton(parent, kind, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(UI.STEPPER_H, UI.STEPPER_H)

    local bg = Fill(btn, "BACKGROUND", C.control)
    -- The design's own marks, not the characters. A hyphen and a plus sign are
    -- different weights on different baselines in every font, so the pair sat
    -- crooked and never read as one control.
    local mark = UI.Glyph(btn, kind, 12, C.text)
    mark:SetPoint("CENTER", btn, "CENTER", 0, 0)

    btn:SetScript("OnClick", onClick)
    btn:SetScript("OnEnter", function(self)
        if self:IsEnabled() then
            bg:SetColorTexture(C.controlHi[1], C.controlHi[2], C.controlHi[3], 1)
        end
    end)
    btn:SetScript("OnLeave", function()
        bg:SetColorTexture(C.control[1], C.control[2], C.control[3], 1)
    end)

    -- At the end of the range the button says so by going quiet, rather than
    -- staying lit and doing nothing when clicked.
    local baseSetEnabled = btn.SetEnabled
    btn.SetEnabled = function(self, enabled)
        baseSetEnabled(self, enabled)
        local c = enabled and C.text or C.textGhost
        mark:SetColor(c[1], c[2], c[3])
        if not enabled then
            bg:SetColorTexture(C.control[1], C.control[2], C.control[3], 1)
        end
    end

    return btn
end

-- The control itself. Both public names below are three lines of anchoring
-- around this one builder, so the big one and the small one cannot drift.
local function BuildStepper(parent, cfg)
    local BOX = cfg.compact and 36 or 52
    local slider = CreateFrame("Frame", nil, parent)
    slider:SetSize(UI.STEPPER_H * 2 + BOX + 2, UI.STEPPER_H)

    local box = CreateFrame("Frame", nil, slider)
    box:SetSize(BOX, UI.STEPPER_H)
    box:SetPoint("CENTER", slider, "CENTER", 0, 0)
    Fill(box, "BACKGROUND", C.well)

    -- AN EDIT BOX, NOT A LABEL. The number was read-only, which meant an exact
    -- value could only be reached by dragging until the display agreed - and
    -- for a 0.05 step that is a game of patience. Click it and type.
    --
    -- What is TYPED is a plain number. What is SHOWN may carry a unit, and the
    -- two are kept apart by cfg.scale: a percentage displays 85 and stores
    -- 0.85, so typing 85 has to divide. Without that the box would either show
    -- 0.85 (unreadable) or take 85 and store it (a bar at 8500% opacity).
    local value = CreateFrame("EditBox", nil, box)
    value:SetAllPoints(box)
    value:SetAutoFocus(false)
    value:SetJustifyH("CENTER")
    value:SetNumeric(false)   -- decimals and a minus sign are both legal
    value:SetMaxLetters(8)
    ns.StyleFont(value, UI.FS.meta)
    value:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

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

    local function Step(delta)
        local current = cfg.get()
        if type(current) ~= "number" then current = cfg.min end
        Commit(current + delta * cfg.step)
        -- The card column redraws itself from the model, so a shape change has
        -- to go round the page. On-screen panels pass silent and repaint
        -- themselves through cfg.apply instead.
        if not cfg.silent then ns.Options:Refresh() end
    end

    local minus = StepperButton(slider, "ui-minus", function() Step(-1) end)
    minus:SetPoint("LEFT", slider, "LEFT", 0, 0)

    local plus = StepperButton(slider, "ui-plus", function() Step(1) end)
    plus:SetPoint("RIGHT", slider, "RIGHT", 0, 0)

    -- The wheel over the value is the third way in, and it is the fast one:
    -- it steps without moving the pointer off the row.
    box:EnableMouseWheel(true)
    box:SetScript("OnMouseWheel", function(_, delta) Step(delta) end)

    -- Typing. The unit and any decoration the format added are stripped, so
    -- "85%", "85" and " 85 s" all mean the same thing - people re-type over a
    -- value they can see, and what they can see has a unit on it.
    value:SetScript("OnEnterPressed", function(self)
        local typed = tonumber((self:GetText() or ""):match("%-?%d+%.?%d*"))
        if typed then Commit(typed / (cfg.scale or 1)) end
        self:ClearFocus()
    end)
    -- Escape means "I did not mean that", so the box goes back to the value.
    value:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        slider.Refresh()
    end)
    -- Clicking away is not a decision either way; treat it as Enter, because
    -- typing a number and then clicking the next control is what people do.
    value:SetScript("OnEditFocusLost", function(self)
        local typed = tonumber((self:GetText() or ""):match("%-?%d+%.?%d*"))
        if typed then Commit(typed / (cfg.scale or 1)) else slider.Refresh() end
    end)
    value:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)

    slider.Refresh = function()
        local current = cfg.get()
        if type(current) ~= "number" then current = cfg.min end
        -- Never overwrite what is being typed: a refresh from somewhere else
        -- would delete the half-finished number under the cursor.
        if not value:HasFocus() then
            value:SetText(cfg.format and cfg.format(current) or tostring(current))
        end

        -- Compared against the CLAMPED ends rather than the raw bounds: with a
        -- step that does not divide the range evenly the last reachable value
        -- is short of cfg.max, and a plus button that stays lit on a number it
        -- can no longer change is the same broken promise as a dead slider.
        minus:SetEnabled(current > Clamp(cfg.min))
        plus:SetEnabled(current < Clamp(cfg.max))
    end

    return slider
end

-- On a settings row: right-aligned in the control slot. 96 wide in the
-- inspector, which leaves the label 264 of the 368 and it never runs out.
function UI.Slider(row, cfg)
    local stepper = BuildStepper(row.slot, cfg)
    stepper:SetPoint("RIGHT", row.slot, "RIGHT", 0, 0)
    ClaimRow(row, stepper)
    row.control = stepper
    row.Refresh = stepper.Refresh
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

-- How tall a popup is allowed to get before it scrolls instead. Chosen so it
-- fits inside the window it opens over rather than over the whole screen.
local MENU_MAX_H = 404

local popup

local function GetPopup()
    if popup then return popup end

    popup = CreateFrame("Frame", nil, UIParent)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetClampedToScreen(true)
    popup:Hide()
    -- A well with a brighter-than-anything outline. There are no shadows here,
    -- so "this is on top of the page" has to be said with an edge: one step
    -- above the brightest edge the page itself can draw.
    Fill(popup, "BACKGROUND", C.well)
    local edge = ns.CreateBorder(popup, 1, "BORDER")
    edge:SetColor(C.overlayEdge[1], C.overlayEdge[2], C.overlayEdge[3], 1)
    popup.rows = {}
    popup.divider = Tex(popup, "ARTWORK", C.separator[1], C.separator[2], C.separator[3], 1)
    popup.divider:SetHeight(1)
    popup.divider:Hide()

    popup.grip = Tex(popup, "OVERLAY", C.overlayEdge[1], C.overlayEdge[2],
        C.overlayEdge[3], 1)
    popup.grip:SetWidth(4)
    popup.grip:Hide()

    -- THE HEAD, 38 high: a filter box, and ESC on the right.
    --
    -- Only shown for the lists long enough to need it. A search field over a
    -- two-item overflow menu is furniture, and furniture on a menu you open
    -- forty times a day is worse than nothing.
    popup.head = CreateFrame("Frame", nil, popup)
    popup.head:SetHeight(38)
    popup.head:SetPoint("TOPLEFT", popup, "TOPLEFT", 0, 0)
    popup.head:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, 0)
    popup.head:Hide()

    popup.search = UI.Input(popup.head, 200, function() end, false, "Search")
    popup.search:SetPoint("LEFT", popup.head, "LEFT", 10, 0)
    popup.search:SetPoint("RIGHT", popup.head, "RIGHT", -46, 0)
    popup.search:SetHeight(24)
    popup.search:SetIcon("ui-search")

    popup.escape = UI.Label(popup.head, "ESC", UI.FS.eyebrow, C.textGhost)
    popup.escape:SetPoint("RIGHT", popup.head, "RIGHT", -10, 0)

    popup.headRule = Tex(popup.head, "ARTWORK", C.separator[1], C.separator[2],
        C.separator[3], 1)
    popup.headRule:SetHeight(1)
    popup.headRule:SetPoint("BOTTOMLEFT", popup.head, "BOTTOMLEFT", 0, 0)
    popup.headRule:SetPoint("BOTTOMRIGHT", popup.head, "BOTTOMRIGHT", 0, 0)

    -- THE RUN-OUT, 16 high. A gradient on ALPHA over the popup's own ground,
    -- not a blur - there is no blur here - so the last row fades instead of
    -- being cut in half by the edge.
    popup.fade = popup:CreateTexture(nil, "OVERLAY")
    popup.fade:SetHeight(16)
    popup.fade:SetColorTexture(C.well[1], C.well[2], C.well[3], 1)
    -- VERTICAL runs bottom to top, so the OPAQUE end is the first colour: the
    -- fade is solid where it meets the popup's edge and gone where the list
    -- still has to be readable.
    if CreateColor then
        popup.fade:SetGradient("VERTICAL",
            CreateColor(C.well[1], C.well[2], C.well[3], 1),
            CreateColor(C.well[1], C.well[2], C.well[3], 0))
    end
    popup.fade:Hide()

    -- THE FOOT, 32: what the keys do. It is the only place the wheel and the
    -- filter are mentioned at all.
    popup.foot = CreateFrame("Frame", nil, popup)
    popup.foot:SetHeight(32)
    popup.foot:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 0, 0)
    popup.foot:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", 0, 0)
    popup.foot:Hide()

    popup.footRule = Tex(popup.foot, "ARTWORK", C.separator[1], C.separator[2],
        C.separator[3], 1)
    popup.footRule:SetHeight(1)
    popup.footRule:SetPoint("TOPLEFT", popup.foot, "TOPLEFT", 0, 0)
    popup.footRule:SetPoint("TOPRIGHT", popup.foot, "TOPRIGHT", 0, 0)

    popup.footHint = UI.Label(popup.foot, "Scroll or type to filter",
        UI.FS.eyebrow, C.textGhost)
    popup.footHint:SetPoint("LEFT", popup.foot, "LEFT", 10, 0)

    popup.footKeys = UI.Label(popup.foot, "ENTER", UI.FS.eyebrow, C.textGhost)
    popup.footKeys:SetPoint("RIGHT", popup.foot, "RIGHT", -10, 0)

    -- Click-away catcher: a full-screen button one level below the popup.
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(1)
    catcher:Hide()
    catcher:SetScript("OnClick", function() popup:Hide() end)
    popup.catcher = catcher

    -- The keyboard goes back when the menu does. A filter box that keeps
    -- focus after its menu has gone swallows every key you press next -
    -- including the one that would open something else.
    popup:HookScript("OnHide", function(self)
        if self.search and self.search.input then
            self.search.input:ClearFocus()
        end
    end)

    popup:SetScript("OnHide", function(self)
        catcher:Hide()
        if self.owner and self.owner.SetOpen then self.owner:SetOpen(false) end
    end)
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
    -- The one thing that says "you are on this one": a raised ground, an
    -- accent bar down the left edge and a tick on the right. Orange TEXT alone
    -- was the whole signal before, and orange text in a list of grey text is a
    -- difference you have to look for rather than one you see.
    entry.pick = Tex(entry, "ARTWORK", C.accent[1], C.accent[2], C.accent[3], 1)
    entry.pick:SetWidth(2)
    entry.pick:SetPoint("TOPLEFT", entry, "TOPLEFT", 0, 0)
    entry.pick:SetPoint("BOTTOMLEFT", entry, "BOTTOMLEFT", 0, 0)
    entry.pick:Hide()

    entry.tick = UI.Glyph(entry, "ui-check", 12, C.accent)
    entry.tick:SetPoint("RIGHT", entry, "RIGHT", -8, 0)
    entry.tick:Hide()

    entry.swatchHost = CreateFrame("Frame", nil, entry)
    entry.swatchHost:SetPoint("RIGHT", entry, "RIGHT", -8, 0)
    entry.swatchHost:SetSize(76, ENTRY_H - 8)
    entry.swatchHost:Hide()

    entry.swatch = entry.swatchHost:CreateTexture(nil, "ARTWORK")
    entry.swatch:SetAllPoints(entry.swatchHost)

    entry.swatchEdge = ns.CreateBorder(entry.swatchHost, 1, "OVERLAY")
    entry.swatchEdge:Hide()

    -- An optional mark, for the menus that pick a THING rather than a value.
    -- The arrangement list is five words that all mean "a shape", and the
    -- shape is the whole of what is being chosen; a word alone makes you
    -- remember which one "Stagger" was. Pooled with the row, so the kind is
    -- set per item.
    entry.mark = UI.Glyph(entry, "layout-grid", 12, C.textDim)
    entry.mark:SetPoint("LEFT", entry, "LEFT", 8, 0)
    entry.mark:Hide()

    -- A real texture beside the vector mark: a spell list is the one menu
    -- where the icon IS the recognition - people find Vampiric Blood by its
    -- red drop long before they read its name. The owner asked in as many
    -- words. Cropped like every spell icon this addon draws.
    entry.spellIcon = entry:CreateTexture(nil, "ARTWORK")
    entry.spellIcon:SetSize(ENTRY_H - 6, ENTRY_H - 6)
    entry.spellIcon:SetPoint("LEFT", entry, "LEFT", 6, 0)
    entry.spellIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    entry.spellIcon:Hide()

    entry.label = UI.Label(entry, "", 12, C.text)
    entry.label:SetPoint("LEFT", entry, "LEFT", 10, 0)
    entry.label:SetWordWrap(false)

    entry.del = CreateFrame("Button", nil, entry)
    entry.del:SetSize(18, 18)
    entry.del:SetPoint("RIGHT", entry, "RIGHT", -6, 0)
    entry.del.label = UI.Glyph(entry.del, "ui-close", 12, C.textFaint)
    entry.del.label:SetPoint("CENTER", entry.del, "CENTER", 0, 0)
    entry.del:SetScript("OnEnter", function(self)
        self.label:SetColor(C.danger[1], C.danger[2], C.danger[3])
    end)
    entry.del:SetScript("OnLeave", function(self)
        self.label:SetColor(C.textFaint[1], C.textFaint[2], C.textFaint[3])
    end)

    menu.rows[index] = entry
    return entry
end

-- WHICH ITEMS SURVIVE THE FILTER. Pure, and exported so it can be tested.
--
-- The rule that is easy to get wrong is the heading: a group title is kept
-- only if something under it survived. A title over nothing is worse than no
-- title, and it is the state a list spends most of its time in while somebody
-- is typing.
--
-- Case-insensitive substring, not fuzzy. For forty names the plain answer is
-- the predictable one, and predictable beats clever on a list you filter
-- twenty times a day.
function UI.FilterMenuItems(items, filter)
    items = items or {}
    if not filter or filter == "" then return items end

    local needle = filter:lower()
    local out, pending = {}, nil
    for _, item in ipairs(items) do
        if item.heading then
            pending = item
        elseif (item.text or ""):lower():find(needle, 1, true) then
            if pending then
                out[#out + 1] = pending
                pending = nil
            end
            out[#out + 1] = item
        end
    end
    return out
end

-- spec = { width, items = {{text, value, onClick, onDelete}}, actions = {...},
--          current, anchor = {point, relPoint, x, y},
--          search, foot, rowHeight, previewWidth/Height/Colour }
local function ShowMenu(owner, spec)
    local menu = GetPopup()
    if menu:IsShown() and menu.owner == owner then
        menu:Hide()
        return
    end

    -- The button that was open before this one is not necessarily the one
    -- being clicked, and nothing else will ever tell it to close: the popup is
    -- shared, so there is exactly one place that knows a select stopped being
    -- the open one.
    if menu.owner and menu.owner.SetOpen then menu.owner:SetOpen(false) end
    menu.owner = owner
    if owner.SetOpen then owner:SetOpen(true) end
    menu:ClearAllPoints()

    -- THE POPUP WEARS THE OWNER'S SCALE. It is parented to UIParent so it can
    -- escape the window bounds, which means the window's scale setting does
    -- not reach it - and a 100% menu hanging off an 80% select is both the
    -- wrong size and, because SetWidth below is in the popup's own units, the
    -- wrong width. Matching effective scales makes every number below mean
    -- what it says again.
    menu:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())

    local anchor = spec.anchor or { "TOPRIGHT", "BOTTOMRIGHT", 0, -2 }
    menu:SetPoint(anchor[1], owner, anchor[2], anchor[3], anchor[4])
    menu:SetWidth(math.max(owner:GetWidth(), spec.width or 0))

    -- THE LIST DOES NOT OWN THE WHOLE POPUP ANY MORE.
    --
    -- A head with the filter box and a foot with the key hints each take a
    -- band, and the scrolling arithmetic below runs on what is left. Both are
    -- opt-in: an overflow menu with two entries in it gets neither, because a
    -- search field over two rows is furniture.
    local ROW = spec.rowHeight or ENTRY_H
    local HEAD = spec.search and 38 or 4
    local FOOT = spec.foot and 32 or 4

    -- Laid out as a FUNCTION, because the filter box re-runs it on every
    -- keystroke. The rows are positioned by hand from a running y, so
    -- filtering is the same walk over a shorter list rather than a second
    -- code path that has to agree with this one.
    local y, index

    local function AddEntry(item, isAction)
        index = index + 1
        local entry = MenuEntry(menu, index)
        entry.dkY = y
        entry:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, y)
        entry:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, y)

        -- A GROUP HEADING is a row that is not an entry: no hover, no click,
        -- upper case at the smallest size. It exists because the media lists
        -- are forty-odd names long and the twenty this addon ships are the
        -- ones you can rely on being there.
        if item.heading then
            entry:SetHeight(24)
            entry:EnableMouse(false)
            entry.hl:Hide()
            entry.pick:Hide()
            entry.tick:Hide()
            entry.del:Hide()
            entry.mark:Hide()
            entry.swatchHost:Hide()
            entry.swatchEdge:Hide()
            entry.label:SetText(item.text:upper())
            entry.label:ClearAllPoints()
            entry.label:SetPoint("LEFT", entry, "LEFT", 10, -3)
            entry.label:SetPoint("RIGHT", entry, "RIGHT", -10, -3)
            ns.StyleUIFont(entry.label, UI.FS.eyebrow)
            entry.label:SetTextColor(C.textFaint[1], C.textFaint[2], C.textFaint[3])
            entry:SetScript("OnClick", nil)
            entry:Show()
            y = y - 24
            return
        end

        entry:SetHeight(ROW)
        entry:EnableMouse(true)

        entry.label:SetText(item.text)
        local active = (not isAction) and item.value ~= nil and item.value == spec.current
        local colour = isAction and C.accent or (active and C.accent or C.text)
        entry.label:SetTextColor(colour[1], colour[2], colour[3])

        -- The chosen one, said three ways because one was not enough: a raised
        -- ground, an accent bar on the left edge and a tick on the right.
        entry.pick:SetShown(active)
        entry.tick:SetShown(active and spec.search and true or false)
        if active then
            entry.hl:SetColorTexture(C.surface[1], C.surface[2], C.surface[3], 1)
            entry.hl:Show()
        else
            entry.hl:SetColorTexture(C.accentSoft[1], C.accentSoft[2],
                C.accentSoft[3], 1)
            entry.hl:Hide()
        end
        -- A row that is already the answer must not lose its ground when the
        -- cursor leaves it, and a row that is not must not keep one.
        --
        -- A row that names a SPELL also answers for it: the client's own
        -- tooltip, the same call the spell pane makes. pcall, because on
        -- this patch a tooltip API is allowed to refuse a spell.
        entry:SetScript("OnEnter", function(self)
            if not active then self.hl:Show() end
            if item.spellID and GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if not pcall(GameTooltip.SetSpellByID, GameTooltip, item.spellID) then
                    GameTooltip:Hide()
                else
                    GameTooltip:Show()
                end
            end
        end)
        entry:SetScript("OnLeave", function(self)
            if item.spellID and GameTooltip then GameTooltip:Hide() end
            if active then return end
            self.hl:Hide()
        end)

        -- Back to the panel font unless this row asks for its own. Rows are
        -- reused, so a font left on one from a previous menu would turn up on
        -- an unrelated entry three menus later.
        ns.StyleUIFont(entry.label, 12)
        entry.swatchHost:Hide()
        entry.swatchEdge:Hide()

        -- A row with a mark indents its label past it; a row without one takes
        -- the indent back, or the next menu through this pooled row would sit
        -- 20 pixels in with nothing in front of it. `iconTexture` is a real
        -- texture (a spell's icon); `icon` stays the vector-glyph key it has
        -- always been - two names because they are two different things.
        if item.iconTexture then
            entry.spellIcon:SetTexture(item.iconTexture)
            entry.spellIcon:Show()
            entry.mark:Hide()
            entry.label:SetPoint("LEFT", entry, "LEFT", 6 + (ENTRY_H - 6) + 6, 0)
        elseif item.icon and entry.mark:SetKind(item.icon) then
            entry.mark:SetColor(colour[1], colour[2], colour[3])
            entry.mark:Show()
            entry.spellIcon:Hide()
            entry.label:SetPoint("LEFT", entry, "LEFT", 30, 0)
        else
            entry.mark:Hide()
            entry.spellIcon:Hide()
            entry.label:SetPoint("LEFT", entry, "LEFT", 10, 0)
        end

        local preview = item.preview
        if preview == "font" then
            -- A font shown in itself. Nothing else answers "what does this
            -- actually look like", and the fallback is honest: a file that
            -- will not load leaves the row in the panel font.
            ns.Media.ApplyFont(entry.label, item.value, 12, "")
        elseif preview == "statusbar" and ns.Media.IsKnown("statusbar", item.value) then
            entry.swatchHost:SetSize(spec.previewWidth or 76,
                spec.previewHeight or (ROW - 8))
            entry.swatch:SetTexture(ns.Media.Statusbar(item.value))
            -- IN THE BAR'S OWN FILL COLOUR, not in the accent. You open this
            -- list to find out what THIS bar will look like, and every strip
            -- painted orange answers a question nobody asked.
            local tint = spec.previewColour or C.accent
            entry.swatch:SetVertexColor(tint[1], tint[2], tint[3], 1)
            entry.swatchHost:Show()
        elseif preview == "border" and ns.Media.IsKnown("border", item.value) then
            -- An edge file has to be drawn as an EDGE to mean anything, so
            -- the swatch is a small framed box rather than the strip itself -
            -- which on its own is eight tiles in a row and reads as noise.
            entry.swatchHost:SetSize(spec.previewWidth or 76,
                spec.previewHeight or (ROW - 8))
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
        elseif entry.tick:IsShown() then
            entry.label:SetPoint("RIGHT", entry.tick, "LEFT", -6, 0)
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
        y = y - ROW
    end

local function Build(filter)
    y, index = -HEAD, 0

    for _, item in ipairs(UI.FilterMenuItems(spec.items, filter)) do
        AddEntry(item, false)
    end

    -- The actions are what the menu can DO rather than what it can pick, so
    -- they are not filtered away by a search for a texture name.
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

    -- SCROLLING, once the list is longer than the screen can usefully show.
    --
    -- The media lists are the reason: a full UI setup registers forty to sixty
    -- textures, and a popup sized to all of them is taller than the window it
    -- belongs to - the entries at the bottom are simply unreachable. So the
    -- popup stops at a height, and the wheel moves the entries inside it.
    --
    -- Done by moving the ENTRIES rather than by putting a ScrollFrame in: the
    -- entries are already positioned by hand from a running y, so scrolling is
    -- the same arithmetic with an offset added, and a scroll frame would mean
    -- reparenting every row.
    -- The list runs from -HEAD down to wherever y ended up. Everything below
    -- is in those terms rather than in the popup's, because the head and the
    -- foot are outside the scrolling area and must not move with it.
    local full = -y - HEAD + 4
    local limit = math.min(MENU_MAX_H, full)
    menu:SetHeight(HEAD + limit + FOOT)

    menu.dkFull, menu.dkLimit, menu.dkScroll = full, limit, 0
    menu.dkCount = index
    menu.dkHead = HEAD

    menu.head:SetShown(spec.search and true or false)
    if spec.search then
        menu.search:SetText("")
        menu.search.UpdateGhost()
        -- THE MENU OPENS READY TO TYPE. Its own foot says "type to filter",
        -- which was a promise nothing kept: the box does not take focus by
        -- itself, so every one of these menus needed a click into a field
        -- most people never noticed was a field.
        menu.search.input:SetFocus()
    end

    menu.foot:SetShown(spec.foot and true or false)
    if spec.foot then menu.footHint:SetText(spec.foot) end

    local scrollable = full > limit
    menu.grip:SetShown(scrollable)
    menu:EnableMouseWheel(scrollable)
    -- The run-out only means anything over a list that continues past it.
    menu.fade:SetShown(scrollable)
    if scrollable then
        menu.fade:ClearAllPoints()
        menu.fade:SetPoint("BOTTOMLEFT", menu, "BOTTOMLEFT", 1, FOOT)
        menu.fade:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -1, FOOT)

        menu:SetScript("OnMouseWheel", function(self, delta)
            local span = self.dkFull - self.dkLimit
            local head = self.dkHead or 0
            local next_ = math.max(0, math.min(span,
                (self.dkScroll or 0) - delta * ROW * 3))
            if next_ == self.dkScroll then return end
            self.dkScroll = next_
            for position = 1, self.dkCount do
                local entry = self.rows[position]
                if entry then
                    entry:ClearAllPoints()
                    entry:SetPoint("TOPLEFT", self, "TOPLEFT", 0,
                        (entry.dkY or 0) + next_)
                    entry:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0,
                        (entry.dkY or 0) + next_)
                    -- An entry scrolled past either edge of the LIST would
                    -- otherwise still be drawn - over the head, or over the
                    -- foot, both of which sit outside it.
                    local at = (entry.dkY or 0) + next_
                    entry:SetShown(at <= -head and at > -(head + self.dkLimit))
                end
            end
            self.grip:SetPoint("TOP", self, "TOP", 0,
                -head - 4 - (next_ / span) * (self.dkLimit - 8 - self.grip:GetHeight()))
        end)

        -- The grip says how far down the list this is. Four pixels wide, one
        -- step brighter than the popup's own outline.
        menu.grip:SetHeight(math.max(20,
            (limit / full) * (limit - 8)))
        menu.grip:ClearAllPoints()
        menu.grip:SetPoint("TOP", menu, "TOP", 0, -HEAD - 4)
        menu.grip:SetPoint("RIGHT", menu, "RIGHT", -2, 0)

        for position = 1, index do
            local entry = menu.rows[position]
            if entry then
                entry:SetShown((entry.dkY or 0) > -(HEAD + limit))
            end
        end
    else
        menu:SetScript("OnMouseWheel", nil)
    end
end

    Build(nil)

    -- The filter box is wired to THIS menu's Build, and unwired when the menu
    -- closes: the popup is shared, so a handler left behind would filter the
    -- next menu through a closure over the last one's items.
    if spec.search then
        menu.search.input:SetScript("OnTextChanged", function(self)
            menu.search.UpdateGhost()
            Build(self:GetText())
        end)
        menu.search.input:SetScript("OnEscapePressed", function()
            menu:Hide()
        end)
    else
        menu.search.input:SetScript("OnTextChanged", menu.search.UpdateGhost)
    end

    menu.catcher:Show()
    menu:SetFrameLevel(menu.catcher:GetFrameLevel() + 10)
    menu:Show()
end

-- Exported so the unlock overlay uses the SAME menu as the options window.
-- A second menu implementation is a second set of paddings, colours and
-- click-away rules to keep in step, and they never stay in step.
UI.ShowMenu = ShowMenu

---------------------------------------------------------------------------
-- PICKING AN ICON
--
-- Owner, about the taunt button: "als button zum stylen mit icon auswahl".
--
-- A GRID, PAGED, and no search box - which is a decision rather than a
-- shortcut. On this client GetMacroIcons answers a list of file IDs and
-- NOTHING ELSE: there are no names to type against, which is exactly why
-- Blizzard's own macro picker is a nameless grid you page through. A search
-- field over numbers would be a control that cannot work.
--
-- What replaces it is the row of QUICK PICKS at the top - the icons that are
-- actually likely, handed in by the caller - so the common answer is one
-- click and the grid is there for the rest.
---------------------------------------------------------------------------
UI.ICON_COLUMNS = 10
UI.ICON_ROWS = 8

-- Pure: which slice of the list a page shows, and how many pages there are.
-- Its own function because "page 4 of 3" and an off-by-one at the end of the
-- last page are the two things that go wrong here, and neither is visible
-- until somebody scrolls to the end.
function UI.IconPage(total, page, perPage)
    local pages = math.max(1, math.ceil(total / perPage))
    page = math.max(1, math.min(pages, page or 1))
    local first = (page - 1) * perPage + 1
    local last = math.min(total, first + perPage - 1)
    return first, last, page, pages
end

-- Every icon the game offers a macro, gathered once. The four calls are the
-- set Blizzard's own picker uses, in the order NorthernSkyRaidTools reads
-- them - spells first, then the loose ones, then the general lists.
local iconList
local function IconList()
    if iconList then return iconList end
    iconList = {}

    -- The question mark first, always: it is what a macro with no icon shows,
    -- so it is the "none of these" answer and belongs where it can be found.
    iconList[1] = 134400

    for _, getter in ipairs({ "GetLooseMacroItemIcons", "GetLooseMacroIcons",
        "GetMacroIcons", "GetMacroItemIcons" }) do
        local fn = _G[getter]
        if type(fn) == "function" then pcall(fn, iconList) end
    end
    return iconList
end

local iconPicker

local function BuildIconPicker()
    if iconPicker then return iconPicker end

    local CELL, GAP, PAD = 34, 4, 14
    local width = PAD * 2 + UI.ICON_COLUMNS * CELL + (UI.ICON_COLUMNS - 1) * GAP

    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:Hide()
    Fill(frame, "BACKGROUND", C.sidebarBg)
    ns.CreateBorder(frame, 1, "BORDER"):SetColor(C.edge[1], C.edge[2], C.edge[3], 1)

    local title = UI.Label(frame, "Pick an icon", UI.FS.card, C.text)
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -12)

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    local closeGlyph = UI.Glyph(close, "ui-close", 12, C.textFaint)
    closeGlyph:SetPoint("CENTER", close, "CENTER", 0, 0)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- The quick picks, on their own line with a word in front of them: they
    -- are answers, not a first page of the grid, and running them together
    -- would read as one list where the first six happen to be different.
    local quickLabel = UI.Eyebrow(frame, "Likely")
    quickLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -40)

    local function Cell(parent)
        local cell = CreateFrame("Button", nil, parent)
        cell:SetSize(CELL, CELL)
        cell.icon = cell:CreateTexture(nil, "ARTWORK")
        cell.icon:SetAllPoints(cell)
        cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        cell.edge = ns.CreateBorder(cell, 1, "OVERLAY")
        cell.edge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)
        cell.pick = ns.CreateBorder(cell, 2, "OVERLAY")
        cell.pick:SetColor(C.accent[1], C.accent[2], C.accent[3], 1)
        cell.pick:Hide()
        cell:SetScript("OnEnter", function(self) self.pick:Show() end)
        cell:SetScript("OnLeave", function(self)
            self.pick:SetShown(self.chosen and true or false)
        end)
        cell:SetScript("OnClick", function(self)
            if frame.onPick and self.texture then frame.onPick(self.texture) end
            frame:Hide()
        end)
        return cell
    end

    frame.quick = {}
    for index = 1, UI.ICON_COLUMNS do
        local cell = Cell(frame)
        cell:SetPoint("TOPLEFT", frame, "TOPLEFT",
            PAD + (index - 1) * (CELL + GAP), -60)
        frame.quick[index] = cell
    end

    local gridTop = 60 + CELL + 16
    local gridLabel = UI.Eyebrow(frame, "Everything the game offers")
    gridLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(gridTop - 16))

    frame.cells = {}
    for index = 1, UI.ICON_COLUMNS * UI.ICON_ROWS do
        local cell = Cell(frame)
        local column = (index - 1) % UI.ICON_COLUMNS
        local row = math.floor((index - 1) / UI.ICON_COLUMNS)
        cell:SetPoint("TOPLEFT", frame, "TOPLEFT",
            PAD + column * (CELL + GAP), -(gridTop + row * (CELL + GAP)))
        frame.cells[index] = cell
    end

    local footTop = gridTop + UI.ICON_ROWS * (CELL + GAP) + 8

    frame.pageLabel = UI.Label(frame, "", UI.FS.meta, C.textFaint)
    frame.pageLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(footTop + 6))

    local prev = UI.Button(frame, "Back", 70, function()
        frame.page = frame.page - 1
        frame.Paint()
    end)
    prev:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(PAD + 78), -footTop)

    local next_ = UI.Button(frame, "More", 70, function()
        frame.page = frame.page + 1
        frame.Paint()
    end)
    next_:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -footTop)

    frame:SetSize(width, footTop + UI.BUTTON_H + PAD)

    frame.Paint = function()
        local list = IconList()
        local perPage = UI.ICON_COLUMNS * UI.ICON_ROWS
        local first, last, page, pages = UI.IconPage(#list, frame.page, perPage)
        frame.page = page

        for index, cell in ipairs(frame.cells) do
            local texture = list[first + index - 1]
            cell.texture = texture
            cell.chosen = texture ~= nil and texture == frame.current
            cell.icon:SetTexture(texture)
            cell.pick:SetShown(cell.chosen)
            cell:SetShown(texture ~= nil and index <= (last - first + 1))
        end

        frame.pageLabel:SetText(string.format("%d - %d of %d", first, last, #list))
        prev:SetEnabled(page > 1)
        next_:SetEnabled(page < pages)
    end

    iconPicker = frame
    return frame
end

-- spec = { current, quick = { textureID, ... }, onPick = function(texture) }
function UI.ShowIconPicker(owner, spec)
    local frame = BuildIconPicker()

    if frame:IsShown() and frame.owner == owner then
        frame:Hide()
        return
    end

    frame.owner = owner
    frame.onPick = spec.onPick
    frame.current = spec.current
    frame.page = 1

    for index, cell in ipairs(frame.quick) do
        local texture = spec.quick and spec.quick[index]
        cell.texture = texture
        cell.chosen = texture ~= nil and texture == spec.current
        cell.icon:SetTexture(texture)
        cell.pick:SetShown(cell.chosen)
        cell:SetShown(texture ~= nil)
    end

    frame.Paint()

    -- The owner's own scale, or a picker opened from a scaled window hangs off
    -- it at the wrong size - the same rule the shared menu follows.
    frame:SetScale((owner and owner.GetEffectiveScale and owner:GetEffectiveScale())
        or 1)
    frame:ClearAllPoints()
    frame:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -4)
    frame:Show()
end

---------------------------------------------------------------------------
-- The button half of a dropdown, without the row wrapper
---------------------------------------------------------------------------
function UI.MenuButton(parent, width, height)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height or UI.CONTROL_H)

    local bg = Fill(button, "BACKGROUND", C.control)
    local edge = ns.CreateBorder(button, 1, "BORDER")
    edge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)

    button.label = UI.Label(button, "", UI.FS.meta, C.text)
    button.label:SetPoint("LEFT", button, "LEFT", 8, 0)
    button.label:SetPoint("RIGHT", button, "RIGHT", -18, 0)
    button.label:SetWordWrap(false)

    -- The closed button shows the mark of what is currently chosen, when the
    -- list has marks at all. Otherwise you pick a shape from a row of pictures
    -- and the field you picked it in shows a word.
    button.mark = UI.Glyph(button, "layout-grid", 12, C.textDim)
    button.mark:SetPoint("LEFT", button, "LEFT", 6, 0)
    button.mark:Hide()

    button.SetMark = function(self, kind)
        if kind and self.mark:SetKind(kind) then
            self.mark:Show()
            self.label:SetPoint("LEFT", self, "LEFT", 26, 0)
        else
            self.mark:Hide()
            self.label:SetPoint("LEFT", self, "LEFT", 8, 0)
        end
    end

    -- The design's chevron rather than a "v". The letter has a stem and a
    -- baseline, so it sat low and to one side of the eight pixels it was
    -- supposed to fill.
    local arrow = UI.Glyph(button, "caretDOWN", 10, C.textFaint)
    arrow:SetPoint("RIGHT", button, "RIGHT", -4, 0)

    -- Hover moves the FILL, not the outline. The outline going orange is the
    -- OPEN state, and if hovering did the same thing the two would be the same
    -- picture - one of them meaning "a list is on screen somewhere" and the
    -- other meaning nothing at all.
    button:SetScript("OnEnter", function()
        bg:SetColorTexture(C.controlHi[1], C.controlHi[2], C.controlHi[3], 1)
    end)
    button:SetScript("OnLeave", function()
        bg:SetColorTexture(C.control[1], C.control[2], C.control[3], 1)
    end)

    button.SetOpen = function(_, open)
        local c = open and C.accent or C.edge
        edge:SetColor(c[1], c[2], c[3], 1)
        arrow:SetKind(open and "caretUP" or "caretDOWN")
    end

    return button
end

---------------------------------------------------------------------------
-- CopyBox - text somebody can actually get out of the game
--
-- The chat frame is not a way to hand anything over: you cannot select text in
-- it, the colour codes come along if you could, and thirty lines scroll past
-- the top. Every "export" that prints to chat is an export only the person who
-- wrote it can use, because they are the one reading the file instead.
--
-- So: a real EditBox, multi-line, focused and fully selected the moment it
-- opens, so the whole thing is one Ctrl+C. Plain text, no colour codes - what
-- is on screen is exactly what lands in the paste.
---------------------------------------------------------------------------
local copyBox

function UI.CopyBox(title, text, hint)
    if not copyBox then
        copyBox = CreateFrame("Frame", "ZwoelfStuffCopyBox", UIParent)
        copyBox:SetSize(620, 460)
        copyBox:SetPoint("CENTER")
        copyBox:SetFrameStrata("FULLSCREEN_DIALOG")
        copyBox:EnableMouse(true)
        copyBox:SetMovable(true)
        copyBox:RegisterForDrag("LeftButton")
        copyBox:SetScript("OnDragStart", copyBox.StartMoving)
        copyBox:SetScript("OnDragStop", copyBox.StopMovingOrSizing)
        copyBox:SetClampedToScreen(true)

        Fill(copyBox, "BACKGROUND", C.windowBg)
        local edge = ns.CreateBorder(copyBox, 1, "BORDER")
        edge:SetColor(C.overlayEdge[1], C.overlayEdge[2], C.overlayEdge[3], 1)

        copyBox.title = UI.Label(copyBox, "", UI.FS.card, C.text)
        copyBox.title:SetPoint("TOPLEFT", copyBox, "TOPLEFT", UI.PAD, -18)

        local close = CreateFrame("Button", nil, copyBox)
        close:SetSize(24, 24)
        close:SetPoint("TOPRIGHT", copyBox, "TOPRIGHT", -UI.PAD, -14)
        local cross = UI.Glyph(close, "ui-close", 12, C.textDim)
        cross:SetPoint("CENTER", close, "CENTER", 0, 0)
        close:SetScript("OnEnter", function()
            cross:SetColor(C.danger[1], C.danger[2], C.danger[3])
        end)
        close:SetScript("OnLeave", function()
            cross:SetColor(C.textDim[1], C.textDim[2], C.textDim[3])
        end)
        close:SetScript("OnClick", function() copyBox:Hide() end)

        local rule = Tex(copyBox, "ARTWORK", C.separator[1], C.separator[2],
            C.separator[3], 1)
        rule:SetHeight(1)
        rule:SetPoint("TOPLEFT", copyBox, "TOPLEFT", 0, -UI.HEADER_H)
        rule:SetPoint("TOPRIGHT", copyBox, "TOPRIGHT", 0, -UI.HEADER_H)

        copyBox.hint = UI.Label(copyBox, "", UI.FS.meta, C.textFaint)
        copyBox.hint:SetPoint("BOTTOMLEFT", copyBox, "BOTTOMLEFT", UI.PAD, 14)

        local scroll = CreateFrame("ScrollFrame", nil, copyBox,
            "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", copyBox, "TOPLEFT", UI.PAD,
            -(UI.HEADER_H + 12))
        scroll:SetPoint("BOTTOMRIGHT", copyBox, "BOTTOMRIGHT", -30, 40)

        -- SetAutoFocus(false), and focused by hand when the box opens. On
        -- true it steals the keyboard the moment the frame is created, which
        -- is at login.
        local input = CreateFrame("EditBox", nil, scroll)
        input:SetMultiLine(true)
        input:SetAutoFocus(false)
        input:SetFontObject("GameFontHighlightSmall")
        input:SetWidth(560)
        input:SetScript("OnEscapePressed", function() copyBox:Hide() end)
        -- Read-only in the way that matters: typing changes nothing that is
        -- kept, and any edit is undone so the paste is always the real thing.
        input:SetScript("OnTextChanged", function(self, byUser)
            if byUser then
                self:SetText(copyBox.dkText or "")
                self:HighlightText()
            end
        end)
        scroll:SetScrollChild(input)
        copyBox.input = input

        table.insert(UISpecialFrames, "ZwoelfStuffCopyBox")
    end

    copyBox.title:SetText(title or "Copy")
    copyBox.hint:SetText(hint or "Ctrl+C copies it. Esc closes.")
    copyBox.dkText = text or ""
    copyBox.input:SetText(copyBox.dkText)
    copyBox:Show()
    copyBox.input:SetFocus()
    copyBox.input:HighlightText()
    return copyBox
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
-- tint, when given, is a function returning r, g, b: the colour the preview
-- strips are drawn in. You open this list to find out what THIS bar will look
-- like, so the strips are in the bar's own fill colour and not in the accent.
function UI.MediaPicker(row, kind, get, set, apply, inheritLabel, tint)
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

        -- OURS FIRST, THEN EVERYTHING ELSE - deliberately not alphabetical
        -- across the two. A full UI setup registers forty to sixty textures,
        -- and at that length grouping is the difference between finding and
        -- searching: the twenty that are always there sit together at the top.
        local ours, theirs = ns.Media.Grouped(kind)
        local function AddGroup(heading, names)
            if #names == 0 then return end
            items[#items + 1] = { heading = true, text = heading }
            for _, name in ipairs(names) do
                items[#items + 1] = {
                    text = name, value = name, preview = kind,
                    onClick = function()
                        set(name)
                        if apply then apply() end
                        ns.Options:Refresh()
                    end,
                }
            end
        end
        AddGroup("Shipped with ZwoelfStuff", ours)
        AddGroup("From your other addons", theirs)

        local previewR, previewG, previewB
        if tint then previewR, previewG, previewB = tint() end

        UI.ShowMenu(button, {
            items = items, current = get(), width = 368,
            search = true, foot = "Scroll or type to filter",
            rowHeight = 28, previewWidth = 132, previewHeight = 14,
            previewColour = previewR and { previewR, previewG, previewB } or nil,
        })
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
                text = option.text, value = option.value, icon = option.icon,
                -- The two spell fields ride along untouched: iconTexture
                -- draws the real icon, spellID hangs the client's own
                -- tooltip on the row. Options that carry neither cost
                -- nothing here.
                iconTexture = option.iconTexture, spellID = option.spellID,
                onClick = function()
                    set(option.value)
                    if cfg.apply then cfg.apply() end
                    ns.Options:Refresh()
                end,
            }
        end
        ShowMenu(button, {
            items = items, current = get(), width = cfg.menuWidth,
            -- A list of forty spells without a filter is a scroll hunt; the
            -- box only appears when the caller asks, so two-entry menus stay
            -- two entries tall.
            search = cfg.search, rowHeight = cfg.rowHeight,
            foot = cfg.search and "Scroll or type to filter" or nil,
        })
    end)

    button.Refresh = function()
        local current = get()
        local text, icon = cfg.emptyText or "-", nil
        for _, option in ipairs(Options()) do
            if option.value == current then
                text, icon = option.text, option.icon
                break
            end
        end
        button.label:SetText(text)
        button:SetMark(icon)
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
                icon = item.icon,
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

    -- A BOX YOU COULD NOT CLICK INTO. Owner, 2026-08-09: "ich kann auch
    -- nichts eingeben in das suchfeld".
    --
    -- An EditBox built from Lua has NO mouse. Blizzard's InputBoxTemplate
    -- enables it in XML, which is why almost nobody hits this - and why every
    -- addon that builds one without the template turns it on by hand:
    -- AceGUI's MultiLineEditBox and its slider box both do, so does BugSack's.
    -- Verified in the installed copies rather than remembered.
    --
    -- Without it the field draws, shows its placeholder, styles its edge on
    -- focus - and can never be given focus by the only gesture anybody tries.
    input:EnableMouse(true)
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

    -- An optional mark inside the field, at the left, with the text moved past
    -- it. For the search boxes: a field you type into and a field you read is
    -- the same rectangle otherwise, and the magnifier says which without
    -- spending a word on it.
    holder.SetIcon = function(self, kind)
        if self.mark then
            self.mark:SetKind(kind)
            return
        end
        self.mark = UI.Glyph(self, kind, 12, C.textFaint)
        self.mark:SetPoint("LEFT", self, "LEFT", 4, 0)
        input:SetPoint("TOPLEFT", self, "TOPLEFT", 26, 0)
        ghost:SetPoint("LEFT", self, "LEFT", 27, 0)
    end

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
-- TextArea - several lines of typing
--
-- NOT UI.Input WITH A TALLER BOX. A multi-line EditBox differs in three ways
-- that each break something if they are missed:
--
--   Enter inserts a newline instead of submitting, so there is no "commit"
--   keystroke at all - the value is saved as it is typed and on focus loss.
--   Escape is the only way out, and it has to give the keyboard back or the
--   window cannot be closed while the cursor is in here.
--
--   It does not scroll itself. Blizzard's own answer is a ScrollFrame with
--   the EditBox as its scroll child, and the box's height driven by its own
--   content - anything else clips the line you are typing the moment you
--   reach the bottom.
--
--   It has no width until it is given one. SetPoint on both sides is not
--   enough inside a ScrollFrame, whose child is free-floating: the text wraps
--   at zero and every character lands on its own line.
---------------------------------------------------------------------------
-- maxLetters: 0 for no limit at all, nil for the reminder-sized default.
--
-- The default exists because a reminder is a line of text somebody reads at a
-- glance during a pull, and 240 is already more than that. It is a HARD cap in
-- the client, though, not a nudge: text past it is discarded on the way in.
-- A profile string is thousands of characters, so pasting one into a box with
-- the default would have silently kept the first 240 and reported the result
-- as damaged - a paste failing with a message about corruption, for a string
-- that was perfectly fine.
function UI.TextArea(parent, width, height, onChange, placeholder, maxLetters)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, height or 74)
    Fill(holder, "BACKGROUND", C.canvasBg)
    local edge = ns.CreateBorder(holder, 1, "BORDER")
    edge:SetColor(C.separator[1], C.separator[2], C.separator[3], 1)

    local scroll = CreateFrame("ScrollFrame", nil, holder)
    scroll:SetPoint("TOPLEFT", holder, "TOPLEFT", 6, -5)
    scroll:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -6, 5)

    local input = CreateFrame("EditBox", nil, scroll)
    input:SetMultiLine(true)
    input:SetAutoFocus(false)
    input:SetMaxLetters(maxLetters or 240)
    input:SetWidth(width - 12)
    input:SetHeight(height or 74)
    ns.StyleUIFont(input, 12, "")
    input:SetTextColor(C.text[1], C.text[2], C.text[3])
    scroll:SetScrollChild(input)

    local ghost = UI.Label(holder, placeholder or "", 12, C.textFaint)
    ghost:SetPoint("TOPLEFT", holder, "TOPLEFT", 7, -6)
    ghost:SetWidth(width - 14)
    ghost:SetJustifyH("LEFT")

    local function UpdateGhost()
        ghost:SetShown((placeholder or "") ~= ""
            and (input:GetText() or "") == "" and not input:HasFocus())
    end

    -- Typed, not submitted. There is no Enter to press - Enter is a newline
    -- here - so the setting follows the keystrokes and the preview moves with
    -- them. That is also what makes the card worth looking at while typing.
    input:SetScript("OnTextChanged", function(self, byUser)
        UpdateGhost()
        if byUser and onChange then onChange(self:GetText() or "") end
        -- Keep the caret in view: without this, typing past the bottom of the
        -- box carries on invisibly.
        local caret = self.GetCursorPosition and self:GetCursorPosition() or nil
        if caret then scroll:UpdateScrollChildRect() end
    end)

    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    input:SetScript("OnEditFocusGained", function()
        edge:SetColor(C.accent[1], C.accent[2], C.accent[3], 1)
        UpdateGhost()
    end)
    input:SetScript("OnEditFocusLost", function(self)
        edge:SetColor(C.separator[1], C.separator[2], C.separator[3], 1)
        UpdateGhost()
        if onChange then onChange(self:GetText() or "") end
    end)

    -- Clicking anywhere in the box puts the cursor in it. The EditBox is only
    -- as tall as its text, so the lower half of an empty box is dead space
    -- that looks exactly like the live part.
    holder:EnableMouse(true)
    holder:SetScript("OnMouseDown", function() input:SetFocus() end)

    holder.input = input
    holder.SetText = function(_, text)
        input:SetText(text or "")
        UpdateGhost()
    end
    UpdateGhost()
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

---------------------------------------------------------------------------
-- THE PREVIEW BARS RUN.
--
-- A still bar in an editor is a lie by omission: it says nothing about which
-- way the fill goes, what is behind it, where the leading edge sits or how
-- the ramp reads while it moves - and every one of those is a control on the
-- page beside it. Drawn full it showed none of them; drawn part-full it read
-- as a bar that was the wrong length, which was reported three times.
-- Running, it is at every length in turn and there is nothing to be wrong
-- about. My own standing rule, written down after the co-tank test mode:
-- invented data has to move.
--
-- One clock for the whole card, and each cell offset along it so the bars do
-- not march in lockstep - real cooldowns are not in step either.
---------------------------------------------------------------------------
local PREVIEW_CYCLE = 4.0
local PREVIEW_STAGGER = 0.43

local function ApplyPreviewFill(cell, portion)
    local run = cell.run
    if not run then return end

    local corner, pad, w, h = ns.Layout.PreviewFill(run.direction,
        run.leftPad, run.rightPad, run.area, run.height, portion)
    cell.fill:ClearAllPoints()
    cell.fill:SetPoint(corner, cell, corner, pad, 0)
    cell.fill:SetSize(w, h)
end

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

---------------------------------------------------------------------------
-- SpellSlot - one square you drop a spell onto
--
-- A reminder watches ONE spell, so the bar's whole grid is the wrong shape
-- for it - but the gesture has to be the same one, because "drag it out of
-- the list" is the thing people already know how to do here.
--
-- SO IT IS A GRID OF ONE. It registers in the same list UI.CellGrid does and
-- answers the same four questions, which means UI.SpellRow needs no idea this
-- widget exists: the drag it already implements finds this the way it finds a
-- bar card. The alternative was a second drag path in SpellRow with its own
-- proxy, its own marker and its own drop test - three more places for the two
-- to drift apart.
--
-- cfg = { size, get() -> spellID or nil, onPick(spellID), onClear() }
---------------------------------------------------------------------------
function UI.SpellSlot(parent, cfg)
    local size = cfg.size or 46
    local slot = CreateFrame("Button", nil, parent)
    slot:SetSize(size, size)
    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    grids[#grids + 1] = slot

    Fill(slot, "BACKGROUND", C.well)
    local edge = ns.CreateBorder(slot, 1, "BORDER")
    edge:SetColor(C.separator[1], C.separator[2], C.separator[3], 1)

    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", slot, "TOPLEFT", 2, -2)
    slot.icon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -2, 2)
    slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    slot.icon:Hide()

    -- What an empty slot says. A plus sign and nothing else reads as "add",
    -- which is right, and it disappears the moment there is an icon.
    -- The same "+" an empty bar cell shows, not a glyph of its own: two marks
    -- for "there is nothing here yet" is two things to learn.
    slot.mark = UI.Label(slot, "+", math.floor(size * 0.38), C.textFaint)
    slot.mark:SetPoint("CENTER", slot, "CENTER", 0, 0)

    -- The drop marker, the same green ring the bar cards show.
    local marker = ns.CreateBorder(slot, 2, "OVERLAY")
    marker:SetColor(C.accent[1], C.accent[2], C.accent[3], 1)
    marker:Hide()

    -- THE SELECTED SLOT, marked the way a selected bar cell is: an accent
    -- outline that STAYS. Owner: "wenn ich eine zelle anklicke, sollte die
    -- zelle markiert sein" - and it is not decoration, it is the answer to
    -- "where does the next spell I click go".
    --
    -- Its own border rather than recolouring the resting one: the resting
    -- edge has to come back when the selection moves, and a colour that is
    -- both the resting state and the selected state cannot.
    local chosen = ns.CreateBorder(slot, 2, "OVERLAY")
    chosen:SetColor(C.accent[1], C.accent[2], C.accent[3], 1)
    chosen:Hide()

    slot.SetSelected = function(_, on)
        slot.selected = on and true or false
        chosen:SetShown(slot.selected)
    end

    slot.CellAt = function()
        if not slot:IsVisible() then return nil end
        local x, y = GetCursorPosition()
        local scale = slot:GetEffectiveScale()
        x, y = x / scale, y / scale
        local left, bottom = slot:GetLeft(), slot:GetBottom()
        if not (left and bottom) then return nil end
        if x < left or x > left + slot:GetWidth() then return nil end
        if y < bottom or y > bottom + slot:GetHeight() then return nil end
        -- 1, because there is exactly one place to land. The drag machinery
        -- treats this as the cell index and hands it straight back to dkDrop.
        return 1
    end

    slot.ShowMarker = function(index) marker:SetShown(index and true or false) end
    slot.HideMarker = function() marker:Hide() end
    slot.dkDrop = function(_, spellID)
        if cfg.onPick then cfg.onPick(spellID) end
    end

    -- AN ITEM CARRIED ON THE CURSOR, dropped straight in.
    --
    -- Owner, 2026-08-09: "kann man das so machen, das man die sachen da
    -- reinziehen kann und das addon die id ausliest?" - yes, and it is the
    -- gesture the game itself uses for an action bar. A spell comes out of
    -- our own list through the drag machinery above; an item comes off the
    -- CLIENT'S cursor, which is a different road to the same slot.
    --
    -- Both doors, because the game offers both: drag-and-release fires
    -- OnReceiveDrag, and picking an item up and clicking a target fires
    -- OnClick with the item still on the cursor. Verified in EllesmereUIBags,
    -- which wires exactly this pair - and ClearCursor is what puts the item
    -- down; without it the cursor keeps carrying it.
    local function TakeCursorItem()
        if not (cfg.onDropItem and GetCursorInfo) then return false end
        local kind, itemID = GetCursorInfo()
        if kind ~= "item" or not itemID then return false end
        if ClearCursor then ClearCursor() end
        cfg.onDropItem(itemID)
        return true
    end

    -- Only a slot that can actually take one registers for drag. A spell slot
    -- is not a place to drop a sword, and RegisterForDrag changes what a
    -- press-and-move means on a frame - not something to switch on for every
    -- slot in the addon to serve the two that need it.
    if cfg.onDropItem then
        slot:RegisterForDrag("LeftButton")
        slot:SetScript("OnReceiveDrag", TakeCursorItem)
    end

    slot:SetScript("OnClick", function(_, button)
        -- Before anything else: a click while carrying something is an
        -- attempt to put it down, not a request to open a menu over it.
        if TakeCursorItem() then return end
        if button == "RightButton" then
            if cfg.onClear then cfg.onClear() end
        elseif cfg.onEmptyClick then
            cfg.onEmptyClick()
        end
    end)

    slot:SetScript("OnEnter", function(self)
        edge:SetColor(C.accent[1], C.accent[2], C.accent[3], 1)
        local spellID = cfg.get and cfg.get()
        if not (GameTooltip and spellID) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        -- cfg.tooltip lets a slot hold something that is not a spell - a
        -- consumable, say - without a second slot widget existing. Same
        -- reason cfg.texture exists: one slot, two kinds of contents.
        local shown = cfg.tooltip and cfg.tooltip(GameTooltip, spellID)
        if not shown
            and not pcall(GameTooltip.SetSpellByID, GameTooltip, spellID) then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(ns.SpellName(spellID) or tostring(spellID))
        end
        GameTooltip:AddLine("Right click to clear.", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)

    slot:SetScript("OnLeave", function()
        edge:SetColor(C.separator[1], C.separator[2], C.separator[3], 1)
        if GameTooltip then GameTooltip:Hide() end
    end)

    -- NO SELF, and it closes over `slot`. Every Refresh in this file is called
    -- as a plain function - Grid:Refresh does `widget.Refresh()` - so one
    -- written as `function(self)` gets nil and raises on its first field.
    slot.Refresh = function()
        local spellID = cfg.get and cfg.get()
        if spellID then
            slot.icon:SetTexture((cfg.texture and cfg.texture(spellID))
                or ns.SpellTexture(spellID))
            slot.icon:Show()
            slot.mark:Hide()
        else
            slot.icon:Hide()
            slot.mark:Show()
        end
    end

    slot.Refresh()
    return slot
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
        -- nothing about the texture you just picked. It runs the WHOLE length
        -- of the bar - see the note where it is anchored, which is the third
        -- and last word on why there is no part-full fill here any more.
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

        -- THE DRAG DOES NOT OWN OnUpdate. It used to install its own handler
        -- here and clear it on drop, which would have torn the running
        -- preview off the card the first time anybody sorted a bar. There is
        -- one handler on the grid and it reads `dragFrom` - see the end of
        -- UI.CellGrid.
        cell:SetScript("OnDragStart", function(self)
            if not self.dkSpellID then return end
            grid.dragFrom = self.dkIndex
            self.icon:SetAlpha(0.3)
        end)

        cell:SetScript("OnDragStop", function(self)
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
            -- Per CELL, so a cell wearing its own colour previews in that
            -- colour rather than in the bar's.
            local style = cfg.style and cfg.style(h, index)
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

                    -- The fill, in the bar's OWN colour and texture, from the
                    -- same settings the screen uses - a preview painted in the
                    -- editor's accent colour tells you nothing about the bar
                    -- you are actually building. The pads are the room the
                    -- icon takes at whichever end it sits.
                    local inset = (place == "hidden") and 0 or h
                    local leftPad = (place == "right") and 0 or inset
                    local rightPad = (place == "right") and -inset or 0

                    -- WHAT THE BAR NEEDS IN ORDER TO RUN, remembered on the
                    -- cell rather than worked out again sixty times a second.
                    -- The direction is the same one-of-four the screen fills
                    -- along, both ends and both axes: at 100% those look
                    -- identical, which is exactly why a still preview could
                    -- not show the setting at all.
                    --
                    -- `grow` is the Fill-up switch, honoured here even though
                    -- a bar the Cooldown Manager times ignores it on screen.
                    -- The card previews the SETTINGS; that this one does not
                    -- reach a mirrored bar is a fault to fix, not a reason for
                    -- the editor to quietly agree with it.
                    cell.run = {
                        -- The entry Bars:Style already resolved, exactly as
                        -- Screen.lua reads it. Handing it back through
                        -- FillDirection was the eighth time this card and the
                        -- screen disagreed - it silently answered "left to
                        -- right" for every bar.
                        direction = (style and style.fillDirection)
                            or ns.Layout.FillDirection("right"),
                        grow = style and style.fillGrow and true or false,
                        leftPad = leftPad,
                        rightPad = rightPad,
                        area = math.max(1, w - inset),
                        height = h,
                    }
                    ApplyPreviewFill(cell, 1)

                    if style then
                        local fill = style.fillTexture
                        if fill and ns.Media.IsKnown("statusbar", fill) then
                            cell.fill:SetTexture(ns.Media.Statusbar(fill))
                        else
                            cell.fill:SetTexture(ns.WHITE)
                        end
                        -- THROUGH ns.Tint, like everything else that can
                        -- ramp. 4.31.0 made it the one sink and rewired the
                        -- fill, the backdrop, the border and every stack band
                        -- through it - and missed the card, so the editor drew
                        -- a gradient backdrop under a flat fill while the
                        -- screen drew both. A preview that disagrees with the
                        -- thing it previews is the fault this card has now had
                        -- three times.
                        local colour = style.fillColor
                        ns.Tint(cell.fill, colour, style.fillAlpha,
                            style.fillGradient)
                    end
                    cell.fill:Show()

                    if style and style.spellName.show then
                        local name = style.spellName
                        ns.Media.ApplyFont(cell.caption, name.font, name.size,
                            name.outline, name.color)
                        -- The SAME band and the same anchor the screen uses,
                        -- from the same two functions. A preview that puts the
                        -- name somewhere else is not a preview - and it drew
                        -- it hard on the left while the bar itself had learned
                        -- to follow the setting.
                        local leftInset, rightInset =
                            ns.Layout.LabelBand(place, (place == "hidden") and 0 or h)
                        local _, _, justify, vertical =
                            ns.Layout.LabelAnchor(name.anchor)

                        cell.caption:ClearAllPoints()
                        cell.caption:SetPoint(vertical .. "LEFT", cell,
                            vertical .. "LEFT", leftInset + (name.x or 0), name.y or 0)
                        cell.caption:SetPoint(vertical .. "RIGHT", cell,
                            vertical .. "RIGHT", -rightInset + (name.x or 0), name.y or 0)
                        cell.caption:SetJustifyH(justify)
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
                    -- An icon cell has no fill to run. Cleared rather than
                    -- left behind: cells are reused, and a cell that turns
                    -- from a bar into an icon would otherwise go on being
                    -- resized every frame.
                    cell.run = nil
                end

                cell.plus:Hide()
                cell.number:SetText(tostring(index))
                cell.edge:Hide()
            else
                cell.icon:Hide()
                cell.fill:Hide()
                cell.caption:Hide()
                cell.run = nil
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

    -- THE ONE HANDLER ON THIS FRAME, doing both jobs. A hidden frame gets no
    -- OnUpdate, so the card costs nothing while the window is shut and there
    -- is nothing to start or stop.
    grid:SetScript("OnUpdate", function(self, elapsed)
        if self.dragFrom then self.ShowMarker(CellUnderCursor()) end

        local phase = (self.phase or 0) + elapsed
        if phase >= PREVIEW_CYCLE then phase = phase % PREVIEW_CYCLE end
        self.phase = phase

        for index, cell in ipairs(self.cells) do
            local run = cell.run
            if run and cell:IsShown() then
                -- Draining is what a cooldown does, so that is the default and
                -- Fill up is the one that runs the other way.
                local own = (phase + index * PREVIEW_STAGGER) % PREVIEW_CYCLE
                local portion = 1 - own / PREVIEW_CYCLE
                if run.grow then portion = 1 - portion end
                ApplyPreviewFill(cell, portion)
            end
        end
    end)

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

    -- A WHEEL OVER A LIST THAT DOES NOT SCROLL IS NOT A WHEEL NOBODY MEANT.
    --
    -- EnableMouseWheel swallows the gesture whether or not there is anything
    -- to move, so a short list would eat the wheel over the largest part of
    -- the window - and in the death log that wheel is how you page between
    -- deaths. The owner would have lost it on every death with few hits.
    scroll:SetScript("OnMouseWheel", function(self, delta)
        if Range() <= 0 then
            if self.OnIdleWheel then self.OnIdleWheel(delta) end
            return
        end
        ScrollBy(delta)
    end)
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

-- opts.sticky asks for a band at the TOP of the page that does not scroll.
-- The caller fills `grid.sticky` and then sets its height; everything laid
-- out through the grid scrolls underneath it.
--
-- Owner, 2026-08-09, about the externals page: "vorschau sticky machen!
-- sprich content darunter scrollt." Which is right for any page whose top is
-- the thing you are editing and whose bottom is the settings for it - you
-- want to see what you are changing while you change it.
--
-- The scroll area CLIPS its own children, so nothing can be drawn into the
-- band from below: the band is simply above where the scrolling starts. The
-- hairline under it is the caller's, because only the caller knows whether
-- its block ends in something that already reads as an edge.
function UI.Page(parent, width, opts)
    local contentWidth = width - 14

    local host, sticky = parent, nil
    if opts and opts.sticky then
        sticky = CreateFrame("Frame", nil, parent)
        sticky:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        sticky:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
        sticky:SetHeight(1)

        -- THREE POINTS, NOT FOUR. Top left and top right give the width and
        -- where it starts; bottom left gives where it ends. A centre point
        -- among them would be a second opinion about the left edge.
        host = CreateFrame("Frame", nil, parent)
        host:SetPoint("TOPLEFT", sticky, "BOTTOMLEFT", 0, 0)
        host:SetPoint("TOPRIGHT", sticky, "BOTTOMRIGHT", 0, 0)
        host:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    end

    local scroll, content = UI.ScrollArea(host, contentWidth)

    local grid = setmetatable({
        content  = content,
        scroll   = scroll,
        sticky   = sticky,
        explain  = opts and opts.explain or nil,
        tooltipNotes = opts and opts.tooltipNotes or nil,
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
        tab = self.recordTab,
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

-- Whether an item belongs on the tab currently showing.
--
-- Its own function because both nil cases are decisions rather than accidents,
-- and both have been got wrong once already:
--   item has no tab   it was recorded before any Tab() call, so it belongs to
--                     the page rather than to one tab - shown on all of them
--   page has no tab   the page is not split at all - everything shows
function UI.OnTab(itemTab, activeTab)
    if itemTab == nil or activeTab == nil then return true end
    return itemTab == activeTab
end

-- Everything added after this belongs to the named tab, until the next call.
--
-- A tab is not a section: a section folds and its heading stays put, a tab
-- REPLACES the page under a strip that is always in the same place. Nine
-- sections in one scroll is a page you have to remember your way around; the
-- same nine split three ways is three short pages.
-- A TAB BOUNDARY ALSO ENDS THE SECTION. A tab REPLACES the page under a
-- strip; a section is a disclosure inside one. So a section cannot span two
-- tabs, and leaving `group` set meant the first thing written on the new tab
-- was quietly filed into the last tab's folded-shut section - present, laid
-- out, and never once on screen. That is exactly how the co-tank page's "live
-- auras need 12.1" note, the single most important sentence on it, opened
-- hidden.
--
-- Reset here rather than at the call site, because the call site that gets it
-- wrong is always the next one.
function Grid:Tab(name)
    -- AND IT ENDS THE OPEN SECTION. See the note above this function.
    self.group = nil
    self.sectionName = nil

    -- recordTab is where new items are FILED. tab is which one is on SCREEN.
    -- One field for both reads fine until the page finishes building, at which
    -- point "the tab we are recording into" is the last one declared and the
    -- page silently opens on Reuse.
    self.recordTab = name
    self.tab = self.tab or name
    self.tabs = self.tabs or {}
    if name then
        for _, existing in ipairs(self.tabs) do
            if existing == name then return end
        end
        self.tabs[#self.tabs + 1] = name
    end
end

-- Which one is on screen. Layout is the only thing that reads it, so a switch
-- costs one re-layout of frames that already exist.
function Grid:ShowTab(name)
    if self.tab == name then return end
    self.tab = name
    self:Layout()
end

function Grid:Section(title, key)
    self.group = key
    self.sectionName = title
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

    -- ON A PAGE WITH A THIRD COLUMN, a note is not laid out at all: it becomes
    -- the explanation of the row above it, shown on the right when that row is
    -- pointed at.
    --
    -- The note is kept as a real region rather than reduced to a string,
    -- because several of them are written later (`layoutNote:SetText(...)`) -
    -- so the text is read at the moment it is shown and a note that changes
    -- with the setting above it still says the right thing.
    if (self.explain or self.tooltipNotes) and self.lastRow then
        note.dkSkip = true
        note:Hide()
        self.lastRow.dkNote = note
        if self.tooltipNotes then self:WireTooltip(self.lastRow) end
        return self:Wide(note, 0, 0, 0, NOTE_INDENT)
    end
    -- MEASURED AT LAYOUT TIME, NOT HERE - unless a height was given outright.
    --
    -- A note's height is a WRAPPED height, so it depends on the font. Fonts
    -- arrive late: another addon registering one with LibSharedMedia, or the
    -- panel font being changed, re-wraps every note on the page. Measured once
    -- when the note was written, the page then lays the next section out on
    -- top of it - three notes and a heading drawn over each other, which is
    -- exactly what came back in a screenshot.
    --
    -- Width is set first either way: the unwrapped height is one line, and
    -- measuring before the width has always been the same bug in miniature.
    note.dkMeasure = height == nil
    return self:Wide(note, height or note:GetStringHeight(), 3, 11, NOTE_INDENT)
end

-- On a page with a third column, every row publishes itself when pointed at,
-- and the last one pointed at stays marked. Marked rather than merely hovered
-- because the text it puts on the right has to survive the mouse travelling
-- over there to read it.
function Grid:WireExplain(row)
    if not self.explain then return end

    row:HookScript("OnEnter", function(entered)
        if self.marked and self.marked ~= entered then self.marked.bg:Hide() end
        self.marked = entered
        -- Read at show time, not at build time: several notes are written
        -- later than the row they belong to, and one or two are rewritten
        -- whenever the setting above them changes.
        ns.Options:SetExplain(entered.label:GetText(), entered.section,
            entered.dkNote and entered.dkNote:GetText())
    end)
    row:HookScript("OnLeave", function(left)
        if self.marked == left then left.bg:Show() end
    end)
end

-- WHERE A PAGE HAS NO THIRD COLUMN, the explanation goes in the tooltip.
--
-- The inspector IS the third column, so it has nowhere to put one. It carried
-- them inline instead: a wrapped grey paragraph under every other row, which
-- is most of the height of the panel and, in the owner's words, "das juckt
-- keinen". The row says what the setting is; the sentence is one hover away
-- for the two or three where that is not enough.
function Grid:WireTooltip(row)
    if row.dkTipWired then return end
    row.dkTipWired = true

    row:HookScript("OnEnter", function(entered)
        local note = entered.dkNote
        local text = note and note:GetText()
        if not text or text == "" then return end
        GameTooltip:SetOwner(entered, "ANCHOR_LEFT")
        GameTooltip:AddLine(entered.label:GetText() or "", 1, 1, 1)
        GameTooltip:AddLine(text, 0.65, 0.67, 0.71, true)
        GameTooltip:Show()
    end)
    row:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A half-width row. Two consecutive calls share a line.
function Grid:Row(label, opts)
    opts = opts or {}
    opts.controlWidth = opts.controlWidth or 150
    local row = UI.Row(self.content, label, opts)
    row:SetWidth(self.colWidth)
    row.section = self.sectionName
    self:WireExplain(row)
    self.items[#self.items + 1] = {
        region = row, height = row:GetHeight(), group = self.group,
        tab = self.recordTab, padTop = 0, padBottom = UI.ROW_GAP, indent = 0,
    }
    self.widgets[#self.widgets + 1] = row
    self.lastRow = row
    return row
end

-- A row spanning both columns, for controls that need the space.
function Grid:FullRow(label, opts)
    opts = opts or {}
    opts.controlWidth = opts.controlWidth or 300
    local row = UI.Row(self.content, label, opts)
    row:SetWidth(self.width)
    row.section = self.sectionName
    self:WireExplain(row)
    self.items[#self.items + 1] = {
        region = row, height = row:GetHeight(), wide = true, group = self.group,
        tab = self.recordTab, padTop = 0, padBottom = UI.ROW_GAP, indent = 0,
    }
    self.widgets[#self.widgets + 1] = row
    self.lastRow = row
    return row
end

-- A strip of buttons that flows like any other block in the grid.
--
-- Two Options files each carried their own local copy of this. They had not
-- drifted yet, and the way to keep it that way is for there to be one.
--
-- The FIRST button comes back as a second return: a two-step button
-- ("Really delete it?") needs a handle on itself to rewrite its own label,
-- and fishing it out of GetChildren was the old workaround in both copies.
-- padTop is the air ABOVE the strip, and it is a parameter because a strip
-- of buttons under a row of settings had none: they sat against the control
-- above them and read as part of that setting rather than as the page's own
-- actions. Pads collapse with the neighbour's, so a value smaller than the
-- row gap changes nothing - which is why the callers that want the air ask
-- for a real amount of it.
-- ONE PER LINE. Owner, 2026-08-10, looking at three of them side by side:
-- "kannste die 3 buttons alle untereinander machen, das sieht nicht gut aus."
--
-- He is right, and the reason is that a row of them is a row of NOTHING ELSE:
-- every other block on these pages is a line with a name on the left and a
-- control on the right, so three boxes shoulder to shoulder read as a dialog
-- that wandered in. Stacked, they are a short list of things the page can do,
-- which is what they are. All to the widest one's width so they line up on
-- both edges rather than making a staircase.
function Grid:Buttons(buttons, padTop)
    local strip = CreateFrame("Frame", nil, self.content)

    local GAP = 6
    local width = 0
    for _, spec in ipairs(buttons) do
        -- MEASURED, not typed. A width at the call site is a number somebody
        -- guessed once and nobody re-guessed when the words changed.
        width = math.max(width, UI.ButtonWidth(spec.text))
    end

    local y, first = 0, nil
    for _, spec in ipairs(buttons) do
        local btn = UI.Button(strip, spec.text, width, spec.onClick,
            spec.style)
        btn:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, y)
        y = y - (UI.BUTTON_H + GAP)
        if not first then first = btn end
    end

    local height = math.max(1, #buttons * (UI.BUTTON_H + GAP) - GAP)
    strip:SetSize(self.width, height)
    self:Wide(strip, height + 8, padTop or 0)
    return strip, first
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
        if folded or not UI.OnTab(item.tab, self.tab) then
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
            -- happened to have when it was recorded. dkMeasure does the same
            -- for a note, whose height depends on a font that can change
            -- under it: it is asked again here, every pass.
            local height = item.height
            if region and region.dkMeasure then
                region:SetWidth(self.width - (item.indent or 0))
                height = math.max(region:GetStringHeight() or 0, height)
            elseif region and region.dkHeight then
                height = region.dkHeight
            end
            y = y - height
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
    card.edge:SetColor(C.separator[1], C.separator[2], C.separator[3], 1)

    -- The selected card is marked on its LEFT EDGE, not by turning its whole
    -- outline orange. A full orange rectangle round a card that already
    -- contains an orange chip and an orange badge is the third accent in one
    -- column, and by the third the colour has stopped meaning anything. A bar
    -- down one side says the same thing once.
    card.mark = Tex(card, "ARTWORK", C.accent[1], C.accent[2], C.accent[3], 1)
    card.mark:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
    card.mark:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0)
    card.mark:SetWidth(3)
    card.mark:Hide()

    card.SetActive = function(self, active)
        self.mark:SetShown(active)
        local c = active and C.edge or C.separator
        self.edge:SetColor(c[1], c[2], c[3], 1)
    end

    return card
end

---------------------------------------------------------------------------
-- TabStrip - equal-width tabs over a rule
--
-- 34 tall, the rule on its bottom edge, and the active tab marks itself with
-- a 2px accent bar sitting ON that rule rather than under it. That is the
-- whole reason it reads as a tab: the marker and the line are the same line,
-- so the active one looks connected to what is below and the others do not.
---------------------------------------------------------------------------
function UI.TabStrip(parent, names, onPick)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetHeight(34)

    local rule = Tex(strip, "ARTWORK", C.separator[1], C.separator[2],
        C.separator[3], 1)
    rule:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", 0, 0)
    rule:SetHeight(1)

    local tabs = {}
    for index, name in ipairs(names) do
        local tab = CreateFrame("Button", nil, strip)
        tab:SetPoint("TOP", strip, "TOP", 0, 0)
        tab:SetPoint("BOTTOM", strip, "BOTTOM", 0, 0)

        tab.label = UI.Label(tab, name, UI.FS.row, C.textDim)
        tab.label:SetPoint("CENTER", tab, "CENTER", 0, 0)

        tab.mark = Tex(tab, "OVERLAY", C.accent[1], C.accent[2], C.accent[3], 1)
        tab.mark:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
        tab.mark:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
        tab.mark:SetHeight(2)
        tab.mark:Hide()

        tab:SetScript("OnClick", function() onPick(name) end)
        tab:SetScript("OnEnter", function(self)
            if self.mark:IsShown() then return end
            self.label:SetTextColor(C.text[1], C.text[2], C.text[3])
        end)
        tab:SetScript("OnLeave", function(self)
            if self.mark:IsShown() then return end
            self.label:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
        end)

        tabs[index] = { button = tab, name = name }
    end

    -- Widths are handed out at layout time, not now: the strip does not know
    -- how wide it is until its parent has been sized.
    strip.Layout = function(self)
        local each = math.floor(self:GetWidth() / #tabs)
        for index, entry in ipairs(tabs) do
            entry.button:ClearAllPoints()
            entry.button:SetPoint("TOP", self, "TOP", 0, 0)
            entry.button:SetPoint("BOTTOM", self, "BOTTOM", 0, 0)
            entry.button:SetPoint("LEFT", self, "LEFT", (index - 1) * each, 0)
            entry.button:SetWidth(each)
        end
    end

    strip.Select = function(_, name)
        for _, entry in ipairs(tabs) do
            local on = entry.name == name
            entry.button.mark:SetShown(on)
            local c = on and C.text or C.textDim
            entry.button.label:SetTextColor(c[1], c[2], c[3])
        end
    end

    strip:Select(names[1])

    -- IT LAYS ITSELF OUT, and re-does it whenever it is resized.
    --
    -- A tab is created with no width and no x — Layout is what divides the
    -- strip between them — so a strip whose Layout was never called has four
    -- tabs that exist, answer to clicks nobody can aim at, and are INVISIBLE.
    -- That shipped once, on the co-tank inspector: the open tab looked like
    -- the whole page and three tabs of settings simply could not be reached.
    --
    -- The caller was at fault and the caller should not have been ABLE to be.
    -- A widget that needs a follow-up call to be visible at all is a widget
    -- that will eventually be built without it — the same reasoning that took
    -- the snapping switch out of the tools panel. OnSizeChanged is the honest
    -- moment for it too: the strip does not know its width until its parent
    -- has been sized, which is exactly why this was a separate step.
    strip:SetScript("OnSizeChanged", function(self) self:Layout() end)
    strip:Layout()

    return strip
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

    -- Two tracks, each with its own handle at a different place. The old one
    -- was two bars and two ticks that did not line up with either, and read as
    -- a list rather than as controls.
    sliders = { {0,2,12,2}, {8,0,2,6}, {0,8,12,2}, {2,6,2,6} },

    pulse   = { {0,8,2,4}, {3,4,2,8}, {6,0,2,12}, {9,6,2,6} },

    -- An "i" INSIDE a ring, which is the sign everybody already knows. The
    -- bare dot-and-stem it replaced read as a lower-case L.
    --
    -- Four sides and four turned corners. Four sides ALONE read as square
    -- brackets round the middle, which is what they looked like; the corners
    -- are what make it a ring. Counter-clockwise is positive, so the two
    -- corners that rise left-to-right are positive and the two that fall are
    -- negative.
    info    = { {4,0,4,2}, {4,10,4,2}, {0,4,2,4}, {10,4,2,4},
                {0,1.5,5,2, 0.7854}, {7,1.5,5,2, -0.7854},
                {0,8.5,5,2, -0.7854}, {7,8.5,5,2, 0.7854},
                {5,3,2,2}, {5,6,2,3} },

    log     = { {0,0,12,2}, {0,5,9,2}, {0,10,6,2} },

    -- Four carets, for the nudge pad on a bar in Edit Mode. Two turned bars
    -- meeting at a point, rather than an arrow CHARACTER - "^" and "v" are
    -- different widths on different baselines in every font, so a row of four
    -- of them never lines up.
    caretUP    = { {2,6,7,2,  0.7854}, {5,6,7,2, -0.7854} },
    caretDOWN  = { {2,4,7,2, -0.7854}, {5,4,7,2,  0.7854} },
    caretLEFT  = { {3,2,2,7,  0.7854}, {3,5,2,7, -0.7854} },
    caretRIGHT = { {5,2,2,7, -0.7854}, {5,5,2,7,  0.7854} },

    -- A six-pointed asterisk - three bars through one centre, two of them
    -- turned. Distinct from the four-way arrow the movers on screen use, so
    -- the rail entry and the thing it opens are not the same mark.
    move    = { {5,0,2,12}, {5,0,2,12, 1.0472}, {5,0,2,12, -1.0472} },
}

-- THE DESIGN'S OWN ICONS, rendered to TGA at the two sizes it specifies.
--
-- The marks below this table are built from filled rectangles, and that is
-- exactly why they never matched: the design draws OUTLINES at 1.4px with
-- round caps - four empty squares, a true circle, real diagonals. A filled
-- 4.6 square next to a 1.4 stroke is a different weight of drawing
-- altogether, which is what "die icons sind komplett anders" was.
--
-- Rectangles cannot draw a circle. So the source SVGs are rasterised at the
-- sizes they are shown at - 14 and 22, never scaled between - and shipped as
-- TGA, which is what the client loads. They are white, and tinted per use, so
-- one file serves textDim, text and accent.
-- A long string. Quoted, this path opens with \A, which Lua rejects as an
-- escape and which takes the whole file down at load. Third time.
local ICON_PATH = [[Interface\AddOns\ZwoelfStuff\Media\icons\]]

local ICON_FILES = {
    grid    = "nav-cooldowns",
    move    = "nav-edit-mode",
    sliders = "nav-settings",
    pulse   = "nav-diagnostics",
    info    = "nav-about",
    log     = "nav-changelog",
    bars    = "kind-bar",

    -- Co-tanks has no nav-* mark of its own: the design's rail predates the
    -- page. cond-group is two people and it is the drawing this entry wants,
    -- so it is aliased under a semantic name here for the same reason the six
    -- above are - the rail names a FUNCTION, and what stays put when the
    -- drawing is eventually replaced is the function.
    tanks   = "cond-group",

    -- Same reasoning again, and a happier accident: the design's mark for the
    -- "nag" effect on a bar is a reminder drawn small, which is exactly what
    -- this page is. One drawing, one idea, two places.
    bell    = "effect-nag",

    caretUP    = "ui-chevron-up",
    caretDOWN  = "ui-chevron-down",
    caretRIGHT = "ui-chevron-right",
    caretLEFT  = "ui-chevron-right",   -- turned below; there is no left file
}

-- Everything else is asked for by the name the design gave it.
--
-- No second naming scheme and no translation table to drift: if the file is in
-- Media/icons, the name works. The seven above keep semantic names only
-- because the nav table names a FUNCTION ("settings"), not a drawing, and the
-- function is what stays put when the drawing changes.
for _, name in ipairs({
    "action-build", "action-build-on-screen", "action-delete",
    "action-duplicate", "action-eye", "action-grip", "action-move-bars",
    "action-overflow",
    "cell-clear", "cell-hide", "cell-scale",
    "cond-combat", "cond-group", "cond-rested", "cond-target",
    "dir-bottom-top", "dir-left-right", "dir-right-left", "dir-top-bottom",
    "effect-edge", "effect-flash", "effect-glow", "effect-nag",
    "flow-columns", "flow-rows",
    "kind-bar", "kind-icon",
    "layout-grid", "layout-puzzle", "layout-stagger",
    "media-border", "media-font", "media-outline", "media-texture",
    "menu-attach", "menu-export", "menu-import", "menu-snap", "menu-unlock",
    "pivot-picker",
    "place-arena", "place-battleground", "place-dungeon", "place-raid",
    "place-scenario", "place-world",
    "preset-apply", "preset-save",
    "ui-arrow-right", "ui-check", "ui-close", "ui-drag-handle", "ui-gear",
    "ui-lock", "ui-minus", "ui-plus", "ui-reset", "ui-search",
}) do
    ICON_FILES[name] = name
end

-- Which cut of a mark to load, and how big its frame is IN UI UNITS.
--
-- Two things are being decided at once and they are not the same thing:
--
--   the FRAME is in interface units, and must not change - a 14 icon occupies
--   14 units whatever else is true, or the row it sits in moves
--
--   the FILE is in real pixels, and must match what the screen will actually
--   draw. The interface is rarely at 1:1: on a 1440p screen at the usual
--   setting one unit is about 1.8 pixels, so a 14px file shown at 14 units is
--   stretched to 25 and every 1.4px stroke goes soft. That is the blur, and
--   no amount of care in the file fixes it - the file was simply too small.
--
-- So each mark exists at four cuts and the one that is BIG ENOUGH wins.
-- Downsampling loses far less than upsampling: a 28px stroke squeezed into 25
-- still has an edge, a 14px stroke pulled up to 25 cannot invent one.
--
-- HOW THIS WAS WRONG, and it made every mark in the window soft:
--
-- The test used to be `UIParent:GetEffectiveScale() > 1.25`, and that number
-- is never above 1.25 on any normal setup - on 1440p it sits around 0.53 to
-- 0.75. So "dense" was false on every machine, the SMALL cut was loaded every
-- time, and a 14px file was then stretched across 21 real pixels. The blur
-- the owner reported was not the art and not the colours; it was one
-- comparison against a quantity that does not mean what it looks like it
-- means.
--
-- WHAT ACTUALLY DECIDES IT: how many physical pixels one interface unit
-- covers, which is the screen's real width divided by the width the interface
-- thinks it has. Verified against EllesmereUI, which computes the same ratio
-- the same way (`GetScreenWidth() / physW`, its baseScale) - including the
-- guard, which is its own comment: GetPhysicalScreenSize can answer 0 or nil
-- while the display mode is changing.
-- The number in a file's name is the MARK inside it, not the file: measured,
-- not assumed - nav-cooldowns-14.tga is a 16x16 image with a 14-pixel drawing
-- in it, -22 and -28 are both 32x32, -44 is 64x64. So a cut is chosen by
-- comparing the drawing to the box it will fill, in real pixels.
UI.ICON_CUTS = { 14, 22, 28, 44 }

-- HOW MUCH SMALLER THAN ITS BOX A MARK MAY BE, and it is the design's own
-- ratio rather than a tolerance somebody picked: 14 into 16 and 28 into 32 are
-- both exactly this, which is the pairing every one of these files was drawn
-- for. Anything under it is the file the design intended; anything over it is
-- a stretch, and a stretch is what the owner saw.
UI.ICON_SLACK = 14 / 16

function UI.PixelsPerUnit()
    local physical = GetPhysicalScreenSize and (GetPhysicalScreenSize()) or nil
    local units = GetScreenWidth and GetScreenWidth() or nil
    if not (physical and units) or physical <= 0 or units <= 0 then return 1 end
    return physical / units
end

-- Pure, so the rule can be checked without a screen: the smallest cut the
-- design would pair with a box this size, and the largest one when the screen
-- is denser than anything we ship for.
--
-- It does NOT simply take the biggest available. A 44-pixel drawing squeezed
-- into 16 real pixels is a 64x64 texture loaded to look no better than the
-- 16x16 one, and there are sixty-eight of these marks.
function UI.IconCutFor(canvas, perUnit, cuts)
    cuts = cuts or UI.ICON_CUTS
    local wanted = (canvas or 16) * (perUnit or 1)
    for _, cut in ipairs(cuts) do
        if cut >= wanted * UI.ICON_SLACK then return cut end
    end
    return cuts[#cuts]
end

local function IconCut(size)
    -- The FRAME is quantised to two sizes and always has been: a mark either
    -- sits in a row or it heads a card, and giving each caller its own canvas
    -- would move the rows it sits in.
    local canvas = (size >= 19) and 32 or 16
    return UI.IconCutFor(canvas, UI.PixelsPerUnit()), canvas
end

-- Whether a name resolves to a FILE. A name that does not still draws - four
-- rectangles, silently, in the shape of a grid - so nothing throws and the
-- wrong mark ships. This is what lets the self test catch that.
function UI.HasIcon(kind)
    return ICON_FILES[kind] ~= nil
end

-- A mark that is the CLIENT'S art rather than ours. One entry so far and it
-- earns its place: the death log's skull in the nav rail is the same picture
-- as the skull that sits on the screen counting your deaths, and drawing a
-- second one out of rectangles would be two marks for one feature.
local RAW_TEXTURES = {
    skull = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
}

-- Whether a name draws SOMETHING - ours or the client's. UI.HasIcon above
-- answers only for our own files, which is what the icon-set checks want; a
-- caller that just needs to know the mark will not come out as four
-- rectangles has to include the client's art, or "skull" reads as missing.
function UI.HasGlyph(kind)
    return ICON_FILES[kind] ~= nil or RAW_TEXTURES[kind] ~= nil
end

function UI.Glyph(parent, kind, size, colour)
    size = size or 12

    local raw = RAW_TEXTURES[kind]
    if raw then
        local glyph = CreateFrame("Frame", nil, parent)
        -- Blizzard's skull is drawn small inside its own file, so it is given
        -- more room than a glyph of ours would get at the same nominal size.
        glyph:SetSize(size + 4, size + 4)

        local tex = glyph:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(glyph)
        tex:SetTexture(raw)

        glyph.SetColor = function(_, r, g, b) tex:SetVertexColor(r, g, b, 1) end
        glyph.SetKind = function() return false end

        local c = colour or C.textDim
        glyph:SetColor(c[1], c[2], c[3])
        return glyph
    end

    local file = ICON_FILES[kind]
    if file then
        local drawn, canvas = IconCut(size)
        local glyph = CreateFrame("Frame", nil, parent)
        glyph:SetSize(canvas, canvas)

        local tex = glyph:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(glyph)
        tex:SetTexture(ICON_PATH .. file .. "-" .. drawn)
        if kind == "caretLEFT" then tex:SetRotation(math.pi) end

        glyph.SetColor = function(_, r, g, b) tex:SetVertexColor(r, g, b, 1) end

        -- Pooled rows reuse one glyph for a different mark each time they are
        -- filled, so the KIND has to be settable after the fact. The cut is
        -- already decided by the frame's size and does not change with it.
        glyph.SetKind = function(_, newKind)
            local swap = ICON_FILES[newKind]
            if not swap then return false end
            tex:SetTexture(ICON_PATH .. swap .. "-" .. drawn)
            tex:SetRotation(newKind == "caretLEFT" and math.pi or 0)
            return true
        end

        local c = colour or C.textDim
        glyph:SetColor(c[1], c[2], c[3])
        return glyph
    end

    local glyph = CreateFrame("Frame", nil, parent)
    glyph:SetSize(size, size)

    local scale = size / 12
    local parts = {}
    for _, rect in ipairs(GLYPHS[kind] or GLYPHS.grid) do
        local part = Tex(glyph, "ARTWORK", 1, 1, 1, 1)
        part:SetSize(rect[3] * scale, rect[4] * scale)
        -- A FIFTH number is a rotation, in radians, about the bar's centre.
        -- Rectangles alone cannot draw a diagonal, and two of these marks are
        -- diagonals - so the one that spins is anchored by its CENTRE, since
        -- a rotated texture keeps its centre and moves its corners.
        if rect[5] then
            part:SetPoint("CENTER", glyph, "TOPLEFT",
                (rect[1] + rect[3] / 2) * scale,
                -(rect[2] + rect[4] / 2) * scale)
            part:SetRotation(rect[5])
        else
            part:SetPoint("TOPLEFT", glyph, "TOPLEFT",
                rect[1] * scale, -rect[2] * scale)
        end
        parts[#parts + 1] = part
    end

    glyph.SetColor = function(_, r, g, b)
        for _, part in ipairs(parts) do part:SetColorTexture(r, g, b, 1) end
    end

    -- The rectangle fallback cannot swap what it draws - the parts ARE the
    -- mark. It reports the failure instead of pretending, and a caller that
    -- pools rows only ever asks for names that have files.
    glyph.SetKind = function() return false end

    local c = colour or C.textDim
    glyph:SetColor(c[1], c[2], c[3])
    return glyph
end

---------------------------------------------------------------------------
-- NavItem - one entry in the left column
---------------------------------------------------------------------------
function UI.NavItem(parent, text, glyphKind, onClick)
    local item = CreateFrame("Button", nil, parent)
    item:SetHeight(UI.NAV_ITEM_H)

    -- A neutral raised fill plus an accent marker, rather than a block of
    -- tinted orange: the tint muddies the label sitting on it, and the marker
    -- says "you are here" more plainly than a colour ever does.
    --
    -- The fill is `surface` - the same level a card is. The rail is DARKER
    -- than the window in this palette, so the active row is the one thing in
    -- the column that comes forward, and it comes forward to exactly the
    -- level of the thing it opens.
    item.bg = Fill(item, "BACKGROUND", C.surface)
    item.bg:Hide()

    item.marker = Tex(item, "ARTWORK", C.accent[1], C.accent[2], C.accent[3], 1)
    item.marker:SetPoint("TOPLEFT", item, "TOPLEFT", 0, 0)
    item.marker:SetPoint("BOTTOMLEFT", item, "BOTTOMLEFT", 0, 0)
    item.marker:SetWidth(2)
    item.marker:Hide()

    item.glyph = UI.Glyph(item, glyphKind, 14)
    -- The row now runs edge to edge, so the row's own left padding is here:
    -- past the 2px accent bar, on the same 16 the rail's heading uses.
    item.glyph:SetPoint("LEFT", item, "LEFT", UI.PAD, 0)

    item.label = UI.Label(item, text, UI.FS.row, C.textDim)
    item.label:SetPoint("LEFT", item.glyph, "RIGHT", 10, 0)
    item.label:SetWordWrap(false)

    -- A RIGHT EDGE, so the label has a width to obey.
    --
    -- With only a left anchor a FontString draws at whatever width its text
    -- happens to be and simply keeps going: a title one word longer than the
    -- rail runs under the OFF badge and off the column. Bounded, the client
    -- truncates it instead, which is the failure you can read.
    --
    -- Which right edge depends on whether the badge is there, so it moves in
    -- SetDimmed. A single anchor that always left room for OFF would spend
    -- twenty pixels on a badge that is hidden on every switched-on row - and
    -- these titles need those pixels.
    item.LABEL_INSET = 12
    item.AnchorLabel = function(self)
        self.label:ClearAllPoints()
        self.label:SetPoint("LEFT", self.glyph, "RIGHT", 10, 0)
        if self.dimmed then
            self.label:SetPoint("RIGHT", self.offMark, "LEFT", -6, 0)
        else
            self.label:SetPoint("RIGHT", self, "RIGHT", -self.LABEL_INSET, 0)
        end
    end

    -- A ROW WHOSE FEATURE IS NOT RUNNING. It stays in the column and it stays
    -- clickable - the page behind it is where you switch the thing back on,
    -- so a row you cannot reach would be a dead end. What changes is that it
    -- reads as off: the whole row drops a level, and the word says so.
    --
    -- The word rather than a dot: a faint dot beside a faint label is two
    -- things to decode, and this column already spends its one accent on
    -- "you are here".
    item.offMark = UI.Label(item, "OFF", UI.FS.eyebrow, C.textGhost)
    item.offMark:SetPoint("RIGHT", item, "RIGHT", -12, 0)
    item.offMark:Hide()

    item.SetActive = function(self, active)
        self.active = active and true or false
        self.bg:SetShown(active)
        self.marker:SetShown(active)
        local c = self.dimmed and C.textGhost or (active and C.text or C.textDim)
        self.label:SetTextColor(c[1], c[2], c[3])
        -- THE ICON DOES NOT GO ORANGE. The 2px edge on the left is this
        -- column's one accent, and an orange icon next to it makes two - which
        -- is the rule this palette is built on, broken in the first place it
        -- could be. The icon brightens with the label instead.
        local g = self.dimmed and C.textGhost or (active and C.text or C.textFaint)
        self.glyph:SetColor(g[1], g[2], g[3])
    end

    item.SetDimmed = function(self, dimmed)
        self.dimmed = dimmed and true or false
        self.offMark:SetShown(self.dimmed)
        -- The badge appears and disappears, so the room left for the label
        -- changes with it.
        self:AnchorLabel()
        -- Through SetActive rather than setting the colours here: two places
        -- deciding one row's colour is how the active row ends up bright and
        -- switched-off at the same time.
        self:SetActive(self.active)
    end

    item:SetScript("OnEnter", function(self)
        if self.bg:IsShown() then return end
        local c = self.dimmed and C.textFaint or C.text
        self.label:SetTextColor(c[1], c[2], c[3])
    end)
    item:SetScript("OnLeave", function(self)
        if self.bg:IsShown() then return end
        local c = self.dimmed and C.textGhost or C.textDim
        self.label:SetTextColor(c[1], c[2], c[3])
    end)
    if onClick then item:SetScript("OnClick", onClick) end

    item:AnchorLabel()
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
        if btn.mark then btn.mark:SetColor(C.accent[1], C.accent[2], C.accent[3]) end
    end)
    btn:SetScript("OnLeave", function()
        btn.label:SetTextColor(base[1], base[2], base[3])
        if btn.mark then btn.mark:SetColor(base[1], base[2], base[3]) end
    end)
    if onClick then btn:SetScript("OnClick", onClick) end

    -- A mark in front, with the button widened to hold it. The width is
    -- measured from the label, so it has to be recomputed rather than nudged -
    -- a SetText afterwards would otherwise shrink it back over the mark.
    btn.SetIcon = function(self, kind)
        if not self.mark then
            self.mark = UI.Glyph(self, kind, 12, base)
            self.mark:SetPoint("LEFT", self, "LEFT", -1, 0)
            self.label:SetPoint("CENTER", self, "CENTER", 9, 0)
            self.dkIconPad = 18
        else
            self.mark:SetKind(kind)
        end
        self:SetWidth(math.max(24, self.label:GetStringWidth() + 14 + 18))
    end

    btn.SetText = function(self, value)
        self.label:SetText(value)
        self:SetWidth(math.max(24,
            self.label:GetStringWidth() + 14 + (self.dkIconPad or 0)))
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
-- MiniSlider - a labelled stepper on one compact line
--
--   Rows            [ - ] [ 3 ] [ + ]
--
-- The control the bar cards use, and the one on the Edit Mode panels. Same
-- builder as the inspector's, with the narrow value box: a row count and a
-- column count are at most two digits.
--
-- cfg = { label, get, set, min, max, step, format, scale, apply }
---------------------------------------------------------------------------
function UI.MiniSlider(parent, cfg)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(UI.ROW_H)

    local stepper = BuildStepper(row, {
        min = cfg.min, max = cfg.max, step = cfg.step, compact = true,
        get = cfg.get, set = cfg.set, apply = cfg.apply,
        format = cfg.format, scale = cfg.scale,
        -- Always silent. Every caller of this one already hands in an apply
        -- that redraws what it owns - the card re-measures itself, the
        -- on-screen panel repaints its bar - so a page-wide refresh on top of
        -- that is a second rebuild per click and nothing more.
        silent = true,
    })
    stepper:SetPoint("RIGHT", row, "RIGHT", 0, 0)

    local label = UI.Label(row, cfg.label or "", UI.FS.row, C.textBody)
    label:SetPoint("LEFT", row, "LEFT", 0, 0)
    label:SetWordWrap(false)
    -- Anchored to the control rather than given a width. A fixed width was
    -- what let a long label run under the value; this way the label owns
    -- exactly what the stepper does not, whatever the column turns out to be.
    label:SetPoint("RIGHT", stepper, "LEFT", -UI.GAP, 0)

    row.Refresh = stepper.Refresh
    return row
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

    -- The hairline between entries. A list of forty needs a rhythm; without
    -- one the icons are the only thing the eye can hold on to.
    row.rule = Tex(row, "BACKGROUND", C.separator[1], C.separator[2],
        C.separator[3], 1)
    row.rule:SetHeight(1)
    row.rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", row, "LEFT", 9, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- ONE LINE, not two.
    --
    -- The name sat on top of a grey subline carrying "on this bar, cell 2" and
    -- the spell ID. Two lines per entry is a list half as long as the column,
    -- and the ID is a number nobody reads while choosing a spell. What the
    -- entry has to say on the right is one short thing - which cell it is in,
    -- how long its cooldown is, or that the build does not have it - so it is
    -- one short thing.
    row.name = UI.Label(row, "", UI.FS.row, C.text)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
    row.name:SetWordWrap(false)

    row.trail = UI.Label(row, "", 11, C.textFaint)
    row.trail:SetPoint("RIGHT", row, "RIGHT", -9, 0)
    row.trail:SetJustifyH("RIGHT")
    row.trail:SetWordWrap(false)

    -- The cell badge, which is the one trailing thing that is not just text:
    -- "already on this bar" is a STATE, and a state gets a bed.
    row.cellBadge = UI.Badge(row, "CELL 1", "state")
    row.cellBadge:SetPoint("RIGHT", row, "RIGHT", -9, 0)
    row.cellBadge:Hide()

    row.name:SetPoint("RIGHT", row.trail, "LEFT", -8, 0)

    -- kind: "cell" puts it on a green bed, anything else is plain small type.
    row.SetTrailing = function(self, text, kind)
        if kind == "cell" and text then
            self.cellBadge:SetLabel(text)
            self.cellBadge:Show()
            self.trail:SetText("")
            self.name:SetPoint("RIGHT", self.cellBadge, "LEFT", -8, 0)
        else
            self.cellBadge:Hide()
            self.trail:SetText(text or "")
            self.name:SetPoint("RIGHT", self.trail, "LEFT", -8, 0)
        end
    end

    -- cell is the cell number it sits in, or nil when it is not on the bar.
    -- known is false for a spell the current talent build does not have: it
    -- stays pickable, because a bar is often built for the build you are
    -- about to switch into, but it must not look available.
    row.SetUsed = function(self, cell, known)
        self.dkUsedIn = cell
        -- Not in the build: dimmed as a whole rather than recoloured piece by
        -- piece. It stays pickable - a bar is often built for the build you
        -- are about to switch into - it just must not look available.
        self:SetAlpha(known and 1 or 0.42)

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

    heading.label = UI.Eyebrow(heading, "")
    heading.label:SetPoint("BOTTOMLEFT", heading, "BOTTOMLEFT", 0, 5)
    heading.label:SetWordWrap(false)

    -- How many are in this group, at the FAR right with the rule running
    -- between. Sat immediately after the name before, which made it read as
    -- part of the name - "COOLDOWNS 14" is not a heading, it is a puzzle.
    heading.count = UI.Eyebrow(heading, "")
    heading.count:SetPoint("BOTTOMRIGHT", heading, "BOTTOMRIGHT", 0, 5)
    heading.count:SetJustifyH("RIGHT")

    -- Both ends resolve to the same height: the label's bottom sits 5 above
    -- the heading's, so +5 there and +10 here are the same line. Two anchors
    -- that disagree vertically do not make a slanted rule, they make a wrong one.
    heading.line = UI.Separator(heading)
    heading.line:SetPoint("BOTTOMLEFT", heading.label, "BOTTOMRIGHT", 8, 5)
    heading.line:SetPoint("BOTTOMRIGHT", heading.count, "BOTTOMLEFT", -8, 5)

    heading.SetText = function(self, text, count)
        self.label:SetText((text or ""):upper())
        self.count:SetText(count and tostring(count) or "")
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
    local ROW = 22

    local row = CreateFrame("Frame", nil, parent)
    row:SetWidth(width)

    -- ONE CHIP LIT, OR SEVERAL. `current` is the filter case this was built
    -- for - one of six, and picking another puts the last one out. `isOn` is
    -- the other shape, where every chip is its own yes or no: the externals
    -- panel sends a message to a whisper AND to party chat, and a control
    -- that can only hold one answer cannot say that.
    --
    -- One predicate for both, so nothing below has to know which it is.
    local function IsOn(key)
        if cfg.isOn then return cfg.isOn(key) and true or false end
        return cfg.current and cfg.current() == key
    end

    local chips = {}
    for index, spec in ipairs(cfg.chips) do
        local chip = CreateFrame("Button", nil, row)
        chip:SetHeight(ROW)

        chip.bg = Fill(chip, "BACKGROUND", C.control)

        -- Upper case at 10, no outline. A filter chip is a LABEL you can
        -- press, not a button: six outlined buttons across the top of a list
        -- weigh more than the list does, which is the wrong way round.
        chip.label = UI.Eyebrow(chip, spec.text, C.textDim)
        chip.label:SetPoint("CENTER", chip, "CENTER", 0, 0)
        chip:SetWidth(chip.label:GetStringWidth() + 16)

        chip:SetScript("OnClick", function() cfg.onSelect(spec.key) end)
        chip:SetScript("OnEnter", function(self)
            if IsOn(spec.key) then return end
            self.bg:SetColorTexture(C.control[1], C.control[2], C.control[3], 1)
            self.bg:Show()
        end)
        chip:SetScript("OnLeave", function(self)
            if IsOn(spec.key) then return end
            self.bg:Hide()
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
        for index, chip in ipairs(chips) do
            local active = IsOn(cfg.chips[index].key)
            -- Only the chosen one has a bed. Six filled boxes across the top
            -- of a list weigh more than the list, and five of them are saying
            -- "not me".
            chip.bg:SetShown(active)
            if active then
                chip.bg:SetColorTexture(C.accentSoft[1], C.accentSoft[2],
                    C.accentSoft[3], 1)
            end
            local text = active and C.accent or C.textDim
            chip.label:SetTextColor(text[1], text[2], text[3])
        end
    end

    row.Layout()
    row.Refresh()
    return row
end
