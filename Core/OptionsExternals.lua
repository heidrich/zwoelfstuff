---------------------------------------------------------------------------
-- OptionsExternals.lua - the External CD request page
--
-- The same shape as the Death-log page, deliberately: the SLOTS at the top
-- where the work is, the settings under them with their paragraphs on the
-- rows, and the list you pick from in the third column. Two pages that do the
-- same thing - "choose some spells and arrange them" - must not be two
-- different pictures.
--
-- WHAT THE THIRD COLUMN IS NOT: the Cooldown Manager's catalogue. That list
-- is YOUR spells, and every spell on this page belongs to somebody else. So
-- it is our own list, grouped by class, and it is short enough to read
-- rather than search.
---------------------------------------------------------------------------
local _, ns = ...

local UI = ns.UI
local C = UI.C

local Page = {}
ns.OptionsExternals = Page

local SLOT, GAP = 40, 8
local MIN_SLOT = 22

-- How tall the preview is allowed to get. The band does not scroll - that is
-- the point of it - so a six-row lattice at full size would push the settings
-- it is a preview OF off the bottom of the window.
local BAND_MAX_H = 200

local function Cfg() return ns.Externals.Config() end
local function Apply() ns.Externals.Refresh() end

-- HOW BIG ONE SLOT IS DRAWN IN THE PREVIEW. Pure, because the alternative is
-- finding out in game that twelve columns run off the edge of the page.
--
-- The preview shrinks rather than clipping or scrolling: a lattice you cannot
-- see all of is not a preview of anything, and the shape - which is what you
-- are actually deciding - survives being smaller. It never grows past the
-- design's own 40.
--
-- THE ARITHMETIC ITSELF IS UI.PreviewSize NOW, and it is shared rather than
-- copied. This function had been duplicated verbatim into two other pages, and
-- one of them - the raid bar - carried the 40 across without carrying the
-- reason for it: on THIS page 40 is the panel's own default cell size, so the
-- preview and the screen agree. On that one the real button is 26, and the
-- copy drew every one of them half again too big.
--
-- Why this page still passes a constant rather than Cfg().size: it is written
-- on the Icon size row, in the player's own words - "The preview above keeps
-- its own size - it has a page to fit into." Twelve columns at the panel's
-- maximum 64 would not fit, and this band is what you arrange the SHAPE in.
function Page.PreviewSize(rows, columns, availableWidth, availableHeight)
    return UI.PreviewSize(SLOT, rows, columns, availableWidth, availableHeight,
        GAP, MIN_SLOT)
end

-- WHICH SLOT THE NEXT SPELL GOES INTO. The same idea the cooldown page runs
-- on: you click a cell, it stays marked, and the list on the right fills THAT
-- one. Owner: "wenn ich eine zelle anklicke, sollte die zelle markiert sein".
--
-- On the module rather than a local, because the third column is built by a
-- different function and has to read it.
Page.selected = nil

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
function Page:BuildPage(page, width)
    local grid = UI.Page(page, width, { tooltipNotes = true, sticky = true })

    ---------------------------------------------------------------------
    -- What you have picked
    --
    -- IN THE STICKY BAND, at their word: "vorschau sticky machen! sprich
    -- content darunter scrollt." It is the thing you are editing, and the
    -- forty rows under it are the settings for it - watching your own slots
    -- while you change what they look like is the whole point of a preview.
    ---------------------------------------------------------------------
    local band = grid.sticky
    UI.Fill(band, "BACKGROUND", C.windowBg)

    -- The band's own header line: what it is on the left, what you can do to
    -- it on the right, the slots under both.
    local BAND_HEAD = 32

    local bandTitle = UI.Eyebrow(band, "Your externals")
    bandTitle:SetPoint("TOPLEFT", band, "TOPLEFT", 0, -10)

    local bandRule = band:CreateTexture(nil, "ARTWORK")
    bandRule:SetColorTexture(C.separator[1], C.separator[2], C.separator[3], 1)
    bandRule:SetHeight(1)
    bandRule:SetPoint("BOTTOMLEFT", band, "BOTTOMLEFT", 0, 0)
    bandRule:SetPoint("BOTTOMRIGHT", band, "BOTTOMRIGHT", -14, 0)

    -- THE THINGS YOU DO TO THE PANEL ARE NOT IN THIS BAND ANY MORE.
    --
    -- They were a column of four buttons down its right-hand side, and that
    -- column cost the preview a third of the page's width - on the page whose
    -- whole job is arranging a lattice. "Set keys" and "Test mode" are in the
    -- WINDOW's header band now, beside the page title, which is where every
    -- other page's actions are; see the PAGES table in Options.lua.
    --
    -- The two that did not go with them:
    --   Move the panel      Edit mode, at the top of the rail, is the same
    --                       act and it is one click away. The paragraph at
    --                       the end of the slots says so.
    --   Who would be asked  it prints the resolved roster to chat, which is
    --                       the "Who to ask" list read out loud - so it sits
    --                       under that section, with the thing it explains.

    -- THE SLOT HOST NEEDS A RECTANGLE, NOT A HEIGHT.
    --
    -- It had one point and a height, no width - and a frame whose rect cannot
    -- be worked out is not drawn AND NEITHER ARE ITS CHILDREN. The band's own
    -- eyebrow and hairline are REGIONS of the band, so they kept drawing,
    -- which is exactly what made this look like lost saved data: an empty
    -- band over a "Who to ask" list that still named two spells. Two points
    -- across, or SetWidth - never a lone corner.
    -- THE SLOTS HAVE THE WHOLE BAND. They used to share it with the column
    -- of buttons above, which took a third of it away from the one thing this
    -- band exists to show.
    local host = CreateFrame("Frame", nil, band)
    host:SetPoint("TOPLEFT", band, "TOPLEFT", 0, -BAND_HEAD)
    host:SetPoint("TOPRIGHT", band, "TOPRIGHT", -14, -BAND_HEAD)
    host:SetHeight(SLOT)

    -- THE PREVIEW IS THE PANEL'S OWN LATTICE. Rows and columns, filled the
    -- way the panel fills them, from ns.Externals.Cell - so what you arrange
    -- here is the shape you get on screen rather than a second opinion about
    -- it.
    --
    -- Built on demand and kept: a lattice can be seventy-two places, and
    -- creating those frames up front to show six of them is a page that costs
    -- what its largest setting costs on every login.
    local slots = {}
    local function SlotAt(index)
        if slots[index] then return slots[index] end

        local slot = UI.SpellSlot(host, {
            size = SLOT,     -- re-sized by Fit; this is only the first guess
            -- KIND IS THE TYPE OF THE THING, NOT THE NAME OF THE PAGE. These
            -- hold a spell ID, so they are "spell" - the default - and the
            -- list in the third column can fill them.
            --
            -- It said "external" for one commit, and that broke exactly what
            -- it was meant to protect: the rows in the third column are
            -- UI.SpellRow with no kind of their own, so every drop from the
            -- list was refused and nothing lit up on the way. Kinds exist to
            -- keep a marker KEY out of a place that holds a NUMBER; two pages
            -- that both hold numbers are not a conflict, and they are never on
            -- screen together anyway.
            get = function() return ns.Externals.SpellAt(index) end,
            -- Same gap the raid bar had: the slot answered a drag and had
            -- nothing to write with, so a drop here did nothing at all.
            onPick = function(spellID)
                ns.Externals.SetSlot(index, spellID)
                ns.Options:Refresh()
            end,
            onEmptyClick = function()
                Page.selected = (Page.selected ~= index) and index or nil
                ns.Options:Refresh()
            end,
            onClear = function()
                ns.Externals.ClearSlot(index)
                ns.Options:Refresh()
            end,
        })
        -- A FILLED slot answers a left click too - selecting it is how you
        -- say "replace this one". UI.SpellSlot only calls onEmptyClick, so
        -- the click is taken here and the widget's own path is left alone.
        slot:HookScript("OnClick", function(_, button)
            if button ~= "LeftButton" then return end
            if ns.Externals.SpellAt(index) then
                Page.selected = (Page.selected ~= index) and index or nil
                ns.Options:Refresh()
            end
        end)
        slots[index] = slot
        return slot
    end

    -- The band is as tall as the lattice actually is, measured whenever it
    -- changes. Sized for the largest one it could ever be, it would hold a
    -- third of the page empty for slots nobody asked for.
    band.Fit = function()
        local cfg = Cfg()
        local count = ns.Externals.Count()
        local down = cfg.growth == "down"
        -- The preview gets the band, less the scrollbar gutter on its right.
        local size = Page.PreviewSize(cfg.rows, cfg.columns,
            width - 28, BAND_MAX_H)

        for index = 1, count do
            local slot = SlotAt(index)
            local column, line = ns.Externals.Cell(index, cfg.rows, cfg.columns, down)
            -- Resize, not SetSize: the empty "+" takes its font from the size
            -- the slot was made at, so a lattice that shrinks to six rows kept
            -- a plus drawn for a 40 pixel box.
            slot:Resize(size)
            slot:ClearAllPoints()
            slot:SetPoint("TOPLEFT", host, "TOPLEFT",
                column * (size + GAP), -line * (size + GAP))
        end
        for index = count + 1, #slots do slots[index]:Hide() end

        -- Always exactly the lattice: rows times columns IS the count, so
        -- both fill orders end up filling the same rectangle.
        --
        -- The lattice alone decides the height now. It used to be the taller
        -- of the lattice and the button column, so a one-row panel held a
        -- band four buttons deep with nothing in three quarters of it.
        host:SetHeight(cfg.rows * size + (cfg.rows - 1) * GAP)
        band:SetHeight(BAND_HEAD + host:GetHeight() + 10)
    end
    band.Fit()

    -- NO SENTENCE UNDER THE LATTICE. It said "pick from the list on the
    -- right ... open Edit mode at the top of the list on the left", and the
    -- owner struck it (2026-08-16) with the rest of its kind: the list IS on
    -- the right, and Edit mode IS at the top of the rail - a page that
    -- describes its own furniture is telling the reader what they are
    -- looking at.

    ---------------------------------------------------------------------
    -- Assignment
    --
    -- DIRECTLY UNDER THE SLOTS, at their word - and it belongs there: these
    -- rows and the slots above them are the same decision seen twice, "which
    -- spells do I want and who gives me each one". Everything below is what
    -- the panel LOOKS like, which is a different afternoon.
    --
    -- Owner: "im raid sollte man das zuweisen koennen. ggf. einstellungen
    -- wenn man im raid ist, werden die spieler im tool aufgelistet, dann
    -- einfach hinter dem spell anklicken".
    --
    -- One row per PICKED spell, and the control lists whoever in the group
    -- can actually cast it. Not every player and not every spell: a dropdown
    -- of forty names against this list is a wall, and thirty-nine of
    -- those names cannot cast the thing anyway.
    ---------------------------------------------------------------------
    grid:Section("Who to ask")

    -- THE HALF THAT NEEDS NOTHING FROM ANYBODY. Externals.Ask sends the
    -- sentence on chat AND the same request on the addon channel: the chat
    -- line reaches every group-mate, the addon message only reaches the ones
    -- running this. So asking is never the thing that fails - what changes
    -- is whether they answer with a button or by reading a line.
    grid:Note("|cffffd100Asking always works.|r The request goes out as a "
        .. "chat line anybody can read. A group-mate who also runs "
        .. "ZwoelfStuff gets a button that answers it with one click.")

    -- ONE ROW PER SPELL THERE IS, not per slot there could be. A spell lives
    -- in exactly one slot, so #SPELLS is the real ceiling however large the
    -- lattice gets - and building a row per possible slot would be seventy-two
    -- dropdowns for a list that can never be longer than the list on the right.
    for index = 1, #ns.Externals.SPELLS do
        local row = grid:FullRow("", { controlWidth = 220 })
        local function SpellID() return ns.Externals.Picked()[index] end

        UI.Dropdown(row, function()
            local spellID = SpellID()
            local spell = spellID and ns.Externals.Get(spellID)
            local items = { { value = "", text = "The healer of that class" } }
            for _, member in ipairs(ns.Externals.Candidates(spell,
                ns.Externals.Roster())) do
                items[#items + 1] = { value = member.name, text = member.name }
            end
            return items
        end, function()
            local spellID = SpellID()
            return (spellID and Cfg().assigned[spellID]) or ""
        end, function(value)
            local spellID = SpellID()
            if spellID then
                Cfg().assigned[spellID] = (value ~= "" and value) or nil
            end
        end, { emptyText = "The healer of that class" })

        -- UI.Dropdown HANGS ITS OWN Refresh ON THE ROW, and the line below
        -- used to replace it - so the control never repainted and every one
        -- of these boxes was blank, including the "The healer of that class"
        -- that says what happens when you leave it alone. Two things want one
        -- hook; the second has to call the first, not take it.
        local paintControl = row.Refresh

        row.Refresh = function()
            if paintControl then paintControl() end
            local spellID = SpellID()
            -- A row for a slot you have not filled is not an empty row, it is
            -- no row: SetRelevant takes it out of the layout entirely.
            row:SetRelevant(spellID ~= nil)
            if spellID then
                UI.MakeRowASpell(row, spellID)
                row.label:SetText(ns.Externals.Label(spellID))
            end
        end
    end

    -- WITH THE LIST IT READS OUT LOUD. It prints, for every slot, who the
    -- click would actually reach - the rows above answered for the group you
    -- are standing in, and this is the same answer in a form you can paste.
    -- It was in the band's button column, four sections away from the thing
    -- it is about.
    -- A NOTE EXPLAINS THE ROW ABOVE IT, and this one had drifted three
    -- sections down to sit under Keys, where it read as a claim about
    -- keybinds. It is about the dropdowns directly above it.
    grid:Note("Left alone, a click asks the healer of that class. In a raid, "
        .. "name somebody.")

    grid:Buttons({
        { text = "Who would be asked",
          onClick = function() ns.Externals:Dump() end },
    }, 10)

    ---------------------------------------------------------------------
    -- NO KEYS SECTION. Keys are set ON THE PANEL - owner, 2026-08-10, after
    -- being handed eight rows: "du machst da einen keybind button, dann
    -- grauen die buttons aus und du kannst auf den button klicken und einen
    -- key belegen" - and the button that starts it is |cffffd100Set keys|r
    -- in this page's header. The paragraph that used to sit here only said
    -- so, and the owner struck it (2026-08-16): "den komplett raus".
    ---------------------------------------------------------------------

    ---------------------------------------------------------------------
    -- Sounds
    --
    -- A key is bound to the PLACE - what sits in it changes as people come
    -- and go. A sound is bound to the SPELL, and for the same reason read
    -- the other way: asking for Pain Suppression and asking for a battle
    -- res have to sound different, and where they happen to sit says
    -- nothing about that.
    --
    -- The owner's words: "bei den requests auch je nach spell nicht slot."
    --
    -- ONE ROW PER SPELL THERE IS, the same shape as "Who to ask" above and
    -- for the same reason - a spell lives in exactly one slot, so a row per
    -- possible slot would be seventy-two pickers for a list that can never
    -- be longer than the one on the right.
    ---------------------------------------------------------------------
    grid:Section("Sounds")

    for index = 1, #ns.Externals.SPELLS do
        local row = grid:FullRow("", { controlWidth = 220 })
        local function SpellID() return ns.Externals.Picked()[index] end

        UI.MediaPicker(row, "sound",
            function()
                local spellID = SpellID()
                return spellID and ns.Sounds.Get("request", spellID) or ""
            end,
            function(value)
                local spellID = SpellID()
                if spellID then
                    ns.Sounds.Set("request", spellID, value)
                end
            end,
            -- Choosing one plays it, exactly as on the Settings page.
            function()
                local spellID = SpellID()
                if spellID then
                    ns.Sounds.Preview(ns.Sounds.Get("request", spellID))
                end
            end,
            -- The top entry, and it is the honest name for what an empty
            -- value does here: fall back to whatever Settings chose for
            -- every request. "Same as everywhere" is the wording the font
            -- pickers already use for exactly this.
            "Same as everywhere")

        -- SECOND HOOK, NOT A REPLACEMENT. MediaPicker hangs its own Refresh
        -- on the row and the line below would take it - which is the fault
        -- the dropdowns above this section shipped with once already, and
        -- every one of those boxes was blank because of it.
        local paintControl = row.Refresh

        row.Refresh = function()
            if paintControl then paintControl() end
            local spellID = SpellID()
            row:SetRelevant(spellID ~= nil)
            if spellID then
                UI.MakeRowASpell(row, spellID)
                row.label:SetText(ns.Externals.Label(spellID))
            end
        end
    end

    grid:Note("A sound of its own for one request. Left alone, each one uses "
        .. "whatever |cffffd100Settings - Sounds|r chose for all of them. "
        .. "The sound follows the spell, so moving it to another place on "
        .. "the panel keeps the noise and changes the key.")

    ---------------------------------------------------------------------
    -- The message
    ---------------------------------------------------------------------
    grid:Section("What you say")

    -- CHIPS, NOT A SELECT. Owner: "wir brauchen hier eine mehrfachauswahl."
    -- Five yes-or-no answers, all of them visible at once, which a dropdown
    -- showing one line cannot do however it is worded.
    local channelHost = CreateFrame("Frame", nil, grid.content)
    local chips = UI.ChipRow(channelHost, width - 40, {
        chips = {
            { key = "WHISPER",      text = "Whisper" },
            { key = "GROUP",        text = "Party or raid" },
            { key = "RAID_WARNING", text = "Raid warning" },
            { key = "SAY",          text = "Say" },
            { key = "YELL",         text = "Yell" },
        },
        isOn = function(key) return ns.Externals.ChannelOn(key) end,
        onSelect = function(key)
            ns.Externals.ToggleChannel(key)
            ns.Options:Refresh()
        end,
    })
    chips:SetPoint("TOPLEFT", channelHost, "TOPLEFT", 0, 0)
    channelHost:SetHeight(chips:GetHeight())
    grid:Wide(channelHost, chips:GetHeight(), 4, 8)
    channelHost.Refresh = function() chips.Refresh() end
    grid.widgets[#grid.widgets + 1] = channelHost

    grid:Note("Pick as many as you like. |cffffd100Party or raid|r picks the "
        .. "right channel for the group you are in.")

    local messageRow = grid:FullRow("Message", { controlWidth = 300 })
    local input = UI.Input(messageRow.slot, 300, function(text)
        Cfg().message = (text ~= "" and text) or nil
    end, false, ns.Externals.DEFAULT_MESSAGE)
    input:SetPoint("RIGHT", messageRow.slot, "RIGHT", 0, 0)
    -- The row is already in grid.widgets - Grid:FullRow put it there - so
    -- giving it a Refresh is all that is needed. Adding it again would run
    -- this twice on every repaint.
    messageRow.Refresh = function() input:SetText(Cfg().message or "") end

    grid:Note("One sentence for every slot. |cffffd100%s|r is the spell, "
        .. "|cffffd100%n|r the person being asked.")

    ---------------------------------------------------------------------
    -- The panel
    --
    -- ROWS AND COLUMNS, the two words a cooldown bar uses. Owner: "anzahl
    -- rows fehlt! wie die cdm einstellungen, reihe und spalten anzahl."
    --
    -- Both sliders repaint the page rather than only the panel, because the
    -- preview in the band IS the lattice - it has to grow with them.
    ---------------------------------------------------------------------
    grid:Section("The panel")

    local function Relayout() ns.Options:Refresh() end

    UI.Slider(grid:Row("Rows"), {
        get = ns.Externals.Rows, set = ns.Externals.SetRows,
        min = 1, max = ns.Externals.MAX_ROWS, step = 1, apply = Relayout,
    })

    UI.Slider(grid:Row("Columns"), {
        get = ns.Externals.Columns, set = ns.Externals.SetColumns,
        min = 1, max = ns.Externals.MAX_COLUMNS, step = 1, apply = Relayout,
    })
    grid:Note("Rows times columns is how many places there are to put a "
        .. "spell.")

    UI.Dropdown(grid:Row("Runs"), {
        { value = "right", text = "Across", icon = "dir-left-right" },
        { value = "down",  text = "Down",   icon = "dir-top-bottom" },
    }, function() return Cfg().growth or "right" end,
        function(value) Cfg().growth = value end, { apply = Relayout })
    grid:Note("Which way the slots fill: across a row first, or down a column "
        .. "first.")

    UI.Slider(grid:Row("Icon size"), {
        get = function() return Cfg().size or 40 end,
        set = function(value) Cfg().size = value end,
        min = 20, max = 64, step = 2, apply = Apply,
    })
    grid:Note("How big each icon is on your screen. The preview above keeps "
        .. "its own size - it has a page to fit into.")

    UI.Slider(grid:Row("Spacing"), {
        get = function() return Cfg().gap or 4 end,
        set = function(value) Cfg().gap = value end,
        min = 0, max = 16, step = 1, apply = Apply,
    })
    grid:Note("The gap between two icons.")

    UI.Toggle(grid:Row("Only in a group"),
        function() return Cfg().onlyInGroup ~= false end,
        function(value) Cfg().onlyInGroup = value and true or false; Apply() end)
    grid:Note("On your own there is nobody to ask, so the panel stays away.")

    UI.Toggle(grid:Row("Only in combat"),
        function() return Cfg().onlyInCombat and true or false end,
        function(value) Cfg().onlyInCombat = value and true or false; Apply() end)
    grid:Note("Out of combat you are asking for nothing.")

    ---------------------------------------------------------------------
    -- The look
    --
    -- Owner: "genau wie die anderen optionen beim cdm" - so these are the
    -- BAR's settings, under the bar's key names, drawn by the bar's painters.
    -- Same words on the rows too: a border is a border, and calling it
    -- something else here would make one addon read like two.
    ---------------------------------------------------------------------
    local function Slide(label, key, min, max, step, format, scale)
        UI.Slider(grid:Row(label), {
            get = function() return Cfg()[key] end,
            set = function(value) Cfg()[key] = value end,
            min = min, max = max, step = step,
            format = format, scale = scale, apply = Apply,
        })
    end

    local function Percent(v)
        return string.format("%d%%", math.floor((v or 0) * 100 + 0.5))
    end

    grid:Section("Look")

    Slide("Scale", "scale", 0.5, 2, 0.05, Percent, 100)
    grid:Note("The whole panel, larger or smaller. The icon size above "
        .. "changes one icon; this changes everything on it at once.")

    Slide("Opacity", "alpha", 0, 1, 0.05, Percent, 100)

    Slide("Icon zoom", "iconZoom", 0, 0.2, 0.01, Percent, 100)
    grid:Note("How far into the spell art each icon is cropped. Blizzard's "
        .. "own art carries a border in the file; cropping cuts it off, and "
        .. "at 0 you see the whole thing, frame and all.")

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
    grid:Note("None is a crisp one-pixel line drawn from colour textures, and "
        .. "it stays sharper than any edge file at small sizes. The rest come "
        .. "from whatever your other addons registered.")

    grid:Section("Backdrop")

    UI.Toggle(grid:Row("Show"),
        function() return Cfg().backdrop ~= false end,
        function(value) Cfg().backdrop = value and true or false; Apply() end)
    grid:Note("A plate behind the icon. Spell art is opaque and fills its "
        .. "square, so this shows at the edges and wherever the art does not "
        .. "reach - it is what a cropped icon sits on.")

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

    grid:Layout()

    page.Refresh = function()
        local count = ns.Externals.Count()
        band.Fit()
        -- The selection cannot outlive the slot it points at: drag the count
        -- down past the marked one and it would sit on a slot nobody can see.
        if Page.selected and Page.selected > count then Page.selected = nil end

        for index, slot in ipairs(slots) do
            slot:SetShown(index <= count)
            slot:SetSelected(Page.selected == index)
            slot.Refresh()
        end
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
-- The third column: everything there is, grouped by class
---------------------------------------------------------------------------
function Page:BuildSide(sideHost, pad)
    local side = CreateFrame("Frame", nil, sideHost)
    side:SetAllPoints(sideHost)
    side:Hide()

    local title = UI.Label(side, "Every external", UI.FS.card, C.text)
    title:SetPoint("TOPLEFT", side, "TOPLEFT", pad, -18)

    local hint = UI.Label(side, "Click one to put it on your panel.",
        UI.FS.meta, C.textFaint)
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

    -- A host for the scrolling area, because UI.ScrollArea anchors ITSELF to
    -- whatever it is given - so the thing it is given has to be the viewport.
    local listHost = CreateFrame("Frame", nil, side)
    listHost:SetPoint("TOPLEFT", side, "TOPLEFT", pad, -(UI.HEADER_H + 16))
    listHost:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -pad, pad)

    local rowWidth = UI.INSPECTOR_W - pad * 2 - 8
    local _, content = UI.ScrollArea(listHost, rowWidth, 8)

    -- Grouped by class, in the order the list is written: a run of five
    -- paladin blessings reads as one thing to decide about, and a flat
    -- one alphabetical list makes it five separate decisions.
    local rows = {}
    local y, lastClass = 0, nil

    for _, entry in ipairs(ns.Externals.SPELLS) do
        -- A GROUPED SLOT IS NOT FILED UNDER A CLASS. Lust under SHAMAN would
        -- say the shaman is the one it asks, which is the whole thing the
        -- grouping exists to stop being true.
        local group = entry.heading or entry.class
        if group ~= lastClass then
            lastClass = group
            local heading = UI.Eyebrow(content, group)
            heading:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(y + 8))
            y = y + 26
        end

        local row = UI.SpellRow(content, rowWidth, 30)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        row.dkSpellID = entry.spellID
        row.spellID = entry.spellID
        row:SetScript("OnClick", function()
            if ns.Externals.IsPicked(entry.spellID) then
                ns.Externals.Drop(entry.spellID)
            else
                -- Into the slot you marked, or the first empty one. Nothing
                -- free is not a silent no: the page says so, because a click
                -- that appears to do nothing reads as a broken list.
                local landed = ns.Externals.Pick(entry.spellID, Page.selected)
                if not landed then
                    ns.Print("|cffff8040Every slot is full.|r Raise "
                        .. "|cffffd100How many slots|r, or right-click one to "
                        .. "empty it.")
                else
                    -- The marked slot has been used. Keeping the mark would
                    -- make the next click overwrite what this one just placed.
                    Page.selected = nil
                end
            end
            ns.Options:Refresh()
        end)
        rows[#rows + 1] = row
        y = y + 31
    end

    content:SetHeight(math.max(1, y))

    -- THIS LIST DOES NOT CARE WHO IS IN THE GROUP. Owner: "man sollte auch
    -- ohne das die klassen in der gruppe sind sich sein set zusammenstellen
    -- koennen" - and they are right. You build a set once, on a quiet evening,
    -- for the dungeons you run all week; a list that greys out everything
    -- because you are standing alone in Dornogal is a list that can only be
    -- used at the exact moment you have no time for it.
    --
    -- WHO can cast it is a different question and it has its own place: the
    -- "Who to ask" rows on the page, where the names are. Two answers to one
    -- question in two columns is how they drift.
    side.Refresh = function()
        for _, row in ipairs(rows) do
            local spellID = row.spellID
            local picked = ns.Externals.IsPicked(spellID)
            local spell = ns.Externals.Get(spellID)

            row.icon:SetTexture(ns.SpellTexture(spellID) or ns.WHITE)
            row.name:SetText(ns.Externals.Label(spellID))
            row:SetUsed(picked and "on panel" or nil, true)

            if picked then
                row:SetTrailing("On panel", "cell")
            elseif spell and spell.cooldown then
                -- Its cooldown, as a fact about the spell rather than a
                -- clock. See Externals.lua: nothing here counts anybody down.
                local minutes = math.floor(spell.cooldown / 60)
                row:SetTrailing(minutes > 0
                    and string.format("%d min", minutes)
                    or string.format("%d sec", spell.cooldown))
            else
                row:SetTrailing("")
            end
        end
    end

    return side
end
