---------------------------------------------------------------------------
-- OptionsExternals.lua - the External cooldowns page
--
-- The same shape as the Death-log page, deliberately: the SLOTS at the top
-- where the work is, the settings under them with their paragraphs on the
-- rows, and the list you pick from in the third column. Two pages that do the
-- same thing - "choose some spells and arrange them" - must not be two
-- different pictures.
--
-- WHAT THE THIRD COLUMN IS NOT: the Cooldown Manager's catalogue. That list
-- is YOUR spells, and every spell on this page belongs to somebody else. So
-- it is our own fourteen, grouped by class, and it is short enough to read
-- rather than search.
---------------------------------------------------------------------------
local _, ns = ...

local UI = ns.UI
local C = UI.C

local Page = {}
ns.OptionsExternals = Page

local SLOT, GAP = 40, 8
local PER_ROW = 8

local function Cfg() return ns.Externals.Config() end
local function Apply() ns.Externals.Refresh() end

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
    -- IN THE STICKY BAND, at his word: "vorschau sticky machen! sprich
    -- content darunter scrollt." It is the thing you are editing, and the
    -- forty rows under it are the settings for it - watching your own slots
    -- while you change what they look like is the whole point of a preview.
    ---------------------------------------------------------------------
    local band = grid.sticky
    UI.Fill(band, "BACKGROUND", C.windowBg)

    local bandTitle = UI.Eyebrow(band, "Your externals")
    bandTitle:SetPoint("TOPLEFT", band, "TOPLEFT", 0, -6)

    local bandRule = band:CreateTexture(nil, "ARTWORK")
    bandRule:SetColorTexture(C.separator[1], C.separator[2], C.separator[3], 1)
    bandRule:SetHeight(1)
    bandRule:SetPoint("BOTTOMLEFT", band, "BOTTOMLEFT", 0, 0)
    bandRule:SetPoint("BOTTOMRIGHT", band, "BOTTOMRIGHT", -14, 0)

    local host = CreateFrame("Frame", nil, band)
    local MAX = ns.Externals.MAX_SLOTS
    local HOST_H = math.ceil(MAX / PER_ROW) * (SLOT + GAP)
    host:SetHeight(HOST_H)

    -- Every slot the count could ever reach is BUILT once and shown or hidden
    -- from the count. Building them from the count instead would mean
    -- creating frames while somebody drags a slider, which is how a settings
    -- page ends up with two hundred frames after one afternoon.
    local slots = {}
    for index = 1, MAX do
        local slot = UI.SpellSlot(host, {
            size = SLOT,
            get = function() return ns.Externals.SpellAt(index) end,
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
        slot:SetPoint("TOPLEFT", host, "TOPLEFT",
            ((index - 1) % PER_ROW) * (SLOT + GAP),
            -math.floor((index - 1) / PER_ROW) * (SLOT + GAP))
        slots[index] = slot
    end

    host:SetPoint("TOPLEFT", band, "TOPLEFT", 0, -24)

    -- The band is as tall as the rows that are actually shown, measured when
    -- the count changes. A band sized for twenty-four slots would be a third
    -- of the page held empty for slots nobody asked for.
    band.Fit = function()
        local rows = math.max(1, math.ceil(ns.Externals.Count() / PER_ROW))
        host:SetHeight(rows * SLOT + (rows - 1) * GAP)
        band:SetHeight(24 + host:GetHeight() + 10)
    end
    band.Fit()

    grid:Note("Pick from the list on the right - any of them, at any time, "
        .. "whoever happens to be in your group. On your screen, clicking one "
        .. "of these whispers whoever can cast it; right-click a slot above "
        .. "to drop it. A slot nobody present can fill is not drawn while you "
        .. "play, and every one of them is drawn while you place the panel.")

    ---------------------------------------------------------------------
    -- Assignment
    --
    -- DIRECTLY UNDER THE SLOTS, at his word - and it belongs there: these
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
    -- of forty names against fourteen spells is a wall, and thirty-nine of
    -- those names cannot cast the thing anyway.
    ---------------------------------------------------------------------
    grid:Section("Who to ask")

    for index = 1, ns.Externals.MAX_SLOTS do
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
                row.label:SetText(ns.SpellName(spellID) or ("Spell " .. spellID))
            end
        end
    end

    grid:Note("Left alone, a click asks the healer of that class - which in a "
        .. "five-man is the only person who has it. In a raid, name somebody. "
        .. "The names offered are whoever is in the group right now, so this "
        .. "is a thing to set once the raid has formed - picking the spells "
        .. "themselves works anywhere, alone included.")

    ---------------------------------------------------------------------
    -- The panel
    ---------------------------------------------------------------------
    grid:Section("The panel")

    UI.Slider(grid:Row("How many slots"), {
        get = function() return ns.Externals.Count() end,
        set = function(value) ns.Externals.SetCount(value) end,
        min = 1, max = ns.Externals.MAX_SLOTS, step = 1,
        apply = function() ns.Options:Refresh() end,
    })
    grid:Note("How many places there are to put a spell. Taking it down and "
        .. "back up gives you what you had - a slot beyond the count keeps "
        .. "what is in it, the same way a shrunk bar keeps its cells.")

    UI.Slider(grid:Row("Icon size"), {
        get = function() return Cfg().size or 40 end,
        set = function(value) Cfg().size = value end,
        min = 20, max = 64, step = 2, apply = Apply,
    })
    grid:Note("How big each icon is on your screen.")

    UI.Slider(grid:Row("Spacing"), {
        get = function() return Cfg().gap or 4 end,
        set = function(value) Cfg().gap = value end,
        min = 0, max = 16, step = 1, apply = Apply,
    })
    grid:Note("The gap between two icons.")

    UI.Slider(grid:Row("How many in a line"), {
        get = function() return Cfg().perLine or 6 end,
        set = function(value) Cfg().perLine = value end,
        min = 1, max = 12, step = 1, apply = Apply,
    })
    grid:Note("After this many the panel starts a second line.")

    UI.Dropdown(grid:Row("Runs"), {
        { value = "right", text = "Across", icon = "dir-left-right" },
        { value = "down",  text = "Down",   icon = "dir-top-bottom" },
    }, function() return Cfg().growth or "right" end,
        function(value) Cfg().growth = value end, { apply = Apply })
    grid:Note("Whether the icons run across the screen or down it.")

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
            local colour = Cfg().borderColor or { 0, 0, 0 }
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
            local colour = Cfg().backdropColor or { 0, 0, 0 }
            return colour[1], colour[2], colour[3]
        end,
        function(r, g, b) Cfg().backdropColor = { r, g, b } end, Apply)

    Slide("Opacity", "backdropAlpha", 0, 1, 0.05, Percent, 100)

    UI.MediaPicker(grid:FullRow("Texture",
        { controlWidth = 190, icon = "media-texture" }), "statusbar",
        function() return Cfg().backdropTexture end,
        function(value) Cfg().backdropTexture = value end, Apply)

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

    grid:Note("Pick as many as you like. A whisper reaches the one person who "
        .. "can cast it; party or raid reaches everybody, which is what you "
        .. "want when you do not care who answers as long as somebody does. "
        .. "|cffffd100Party or raid|r picks the right channel for the group "
        .. "you are actually in - in a dungeon from the finder that is NOT "
        .. "party chat. Two that come out the same are sent once. The last "
        .. "one cannot be switched off: a button that sends nowhere is not a "
        .. "setting.")

    local messageRow = grid:FullRow("Message", { controlWidth = 300 })
    local input = UI.Input(messageRow.slot, 300, function(text)
        Cfg().message = (text ~= "" and text) or nil
    end, false, ns.Externals.DEFAULT_MESSAGE)
    input:SetPoint("RIGHT", messageRow.slot, "RIGHT", 0, 0)
    -- The row is already in grid.widgets - Grid:FullRow put it there - so
    -- giving it a Refresh is all that is needed. Adding it again would run
    -- this twice on every repaint.
    messageRow.Refresh = function() input:SetText(Cfg().message or "") end

    grid:Note("One sentence for every slot. |cffffd100%s|r is the spell's "
        .. "name and |cffffd100%n|r is the person being asked - worth having "
        .. "in party or raid chat, where \"Ironbark bitte!\" asks nobody in "
        .. "particular. Leave |cffffd100%s|r out and the name is put in "
        .. "brackets anyway: a message that does not say WHAT you want is one "
        .. "nobody can act on.")

    grid:Buttons({
        { text = "Move the panel", width = 150, style = "primary",
          onClick = function() ns.EditMode:SetUnlocked(true, "bars") end },
        { text = "Test mode", width = 120, onClick = function()
            ns.Externals:SetTestMode(not ns.Externals.testing)
            ns.Print("External cooldowns test mode",
                ns.Externals.testing and "|cff40ff40on|r" or "|cff888888off|r")
        end },
        { text = "Who would be asked", width = 170, onClick = function()
            ns.Externals:Dump()
        end },
    }, 14)

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
    -- alphabetical list of fourteen makes it five separate decisions.
    local rows = {}
    local y, lastClass = 0, nil

    for _, entry in ipairs(ns.Externals.SPELLS) do
        if entry.class ~= lastClass then
            lastClass = entry.class
            local heading = UI.Eyebrow(content, entry.class)
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
    -- koennen" - and he is right. You build a set once, on a quiet evening,
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
            row.name:SetText(ns.SpellName(spellID) or ("Spell " .. spellID))
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
