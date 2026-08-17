---------------------------------------------------------------------------
-- OptionsReminders - the reminders page, and the editor every book of reminders shares.
--
-- THE SHAPE, AND WHY IT IS THIS SHAPE.
--
-- The right-hand column is the SAME spell list the bars page uses - not a
-- copy of it, the same function with a different set of three callbacks. That
-- is what makes "drag Bone Shield onto the slot" work without this file
-- knowing anything about dragging: UI.SpellRow already implements the drag,
-- UI.SpellSlot already answers it, and neither has heard of the other.
--
-- The middle column is one reminder at a time. A list of them across the top,
-- then everything about the selected one underneath: what it says, what it
-- watches, when it is allowed to appear, and what it looks like.
--
-- THE PREVIEW IS THE REAL MESSAGE, BORROWED.
--
-- Same rule as the co-tank panel and the bar cards, and the reason is written
-- across three memory files by now: a preview that draws itself drifts from
-- the thing it previews. So the card holds the actual reminder frame,
-- reparented in and put back on hide, and the flash runs in it because the
-- flash is the setting hardest to judge from a number.
---------------------------------------------------------------------------
local _, ns = ...

-- ONE PAGE FOR TWO BOOKS (4.84.0). Everything below is a CLASS - an editor
-- for a book of reminders (Core/Reminders.lua) - and ns.OptionsReminders is
-- its first instance. The answer page's Alerts tab is the second, on the
-- answer alerts' book: owner, 2026-08-17, "bau doch einfach die reminder-seite
-- da ein". What differs between the two is a small SPEC (words, the trigger
-- rows, the sound event, the section keys); what is the same - the list, the
-- card, the text, the spell slot, the look, the flash, the rules - is written
-- once here.
--
--   prefix     section/anchor keys ("rm")
--   intro      the note at the top of the page
--   newLabel   the button that adds one          ("New reminder")
--   full       the line when the list is full
--   emptyHint  what the card says with nothing to edit
--   sound      the Sounds event the sound row edits ("reminder"), or nil
--   soundNote  the note under the sound row
--   Trigger(self, grid, Body, Get, Set, Apply)  builds the rows between the
--              spell and the switch - "Appears" for a reminder, "Ends" for
--              an alert - and returns a Paint hook (cfg) or nil
--   StateLine(book, cfg) -> the sentence under the spell name
local Editor = {}
Editor.__index = Editor
ns.RemindersEditor = Editor

function Editor.New(book, spec)
    return setmetatable({ book = book, spec = spec }, Editor)
end

local UI = ns.UI
local C = UI.C

-- Which reminder the page is showing. Clamped on every read rather than
-- fixed up on delete: a stale index after a removal is the everyday case, and
-- a clamp in one place beats a correction in six.
function Editor:Current()
    local count = self.book:Count()
    if count == 0 then
        self.index = nil
        return nil, nil
    end
    local index = self.index or 1
    if index > count then index = count end
    if index < 1 then index = 1 end
    self.index = index
    return index, self.book:Get(index)
end

function Editor:Select(index)
    self.index = index
    self:Refresh()
end

-- Every control ends here. Style redraws the frame from the settings; Rebuild
-- is only needed when the NUMBER of reminders changed.
function Editor:Apply()
    local index = self.index
    if index then self.book:Style(index) end
    self.book:Refresh()
    self:Refresh()
end

---------------------------------------------------------------------------
-- The preview card
---------------------------------------------------------------------------
local STAGE_H = 120

local function BuildStage(self, parent, width)
    local card = UI.Card(parent, width)
    card:SetHeight(STAGE_H)

    local caption = UI.Eyebrow(card, "Preview")
    caption:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -12)

    local slot = CreateFrame("Frame", nil, card)
    slot:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 0, -8)
    slot:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -14, 32)
    card.slot = slot

    -- WHAT THE MESSAGE IS DOING RIGHT NOW, under the preview.
    --
    -- This is the one line that makes the feature usable. A reminder is a
    -- conditional, and a conditional you cannot see the state of is a
    -- conditional you debug by standing in a raid. It prints the same
    -- sentence /zs reminders does, off the same function, so the window and
    -- the chat line can never disagree.
    card.state = UI.Label(card, "", UI.FS.meta, C.textFaint)
    card.state:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 14, 12)
    card.state:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -14, 12)
    card.state:SetJustifyH("LEFT")
    card.state:SetWordWrap(false)

    card:SetScript("OnHide", function() self:ReleaseFrame() end)
    return card
end

function Editor:BorrowFrame()
    local index = self:Current()
    if not (index and self.stage) then return end

    -- A DIFFERENT REMINDER THAN THE ONE ALREADY BORROWED means putting the
    -- first one back before taking the second. Without this, clicking through
    -- the list leaves every reminder you looked at parented to the card and
    -- gone from the screen - the exact fault the co-tank panel's release is
    -- written to avoid, one selection deeper.
    if self.borrowed and self.borrowed ~= index then self:ReleaseFrame() end
    if self.borrowed == index then return end

    local frame = self.book:Borrow(index, self.stage.slot)
    if not frame then return end
    self.borrowed = index
end

function Editor:ReleaseFrame()
    if not self.borrowed then return end
    self.borrowed = nil
    self.book:Release()
end

---------------------------------------------------------------------------
-- The list of reminders
--
-- Chips rather than rows: there are at most a dozen, each identified by one
-- short name, and a scrolling list for twelve short names is a list you have
-- to scroll to count.
---------------------------------------------------------------------------
local LIST_H = 30
local CHIP_GAP = 6

local function BuildList(self, parent, width)
    local host = CreateFrame("Frame", nil, parent)
    host:SetSize(width, LIST_H)
    host.chips = {}

    -- NO SELF. Grid:Refresh calls `widget.Refresh()` with no arguments, so a
    -- method written as `function(self)` gets nil and raises on the first
    -- field it touches. Every Refresh in this file closes over what it needs.
    host.Refresh = function()
        local count = self.book:Count()
        local current = self:Current()
        local x = 0

        for index = 1, count do
            local chip = host.chips[index]
            if not chip then
                chip = UI.GhostButton(host, "", function()
                    self:Select(index)
                end)
                -- A BED UNDER EVERY CHIP, and the chosen one's is lit. They
                -- were bare words - the chosen one orange, the rest grey -
                -- and one orange word in a row of grey ones does not read as
                -- "one of these is picked" (owner, 2026-08-16: "das sollte
                -- besser zu sehen sein, dass es eine auswahl ist"). The
                -- same two colours the filter chips over the spell list use,
                -- so a picked thing looks picked the same way everywhere.
                chip.bed = chip:CreateTexture(nil, "BACKGROUND")
                chip.bed:SetAllPoints(chip)
                host.chips[index] = chip
            end
            local cfg = self.book:Get(index)
            local label = self.book:Label(cfg, index)
            -- A switched-off reminder still gets a chip - it is still one of
            -- your reminders - but it says so, or "why is it not showing" has
            -- an answer you have to click to find.
            if cfg and not cfg.enabled then label = label .. " (off)" end
            chip:SetText(label)
            local picked = index == current
            chip:SetBaseColor(picked and C.accent or C.textDim)
            local bed = picked and C.accentSoft or C.control
            chip.bed:SetColorTexture(bed[1], bed[2], bed[3], 1)
            chip:ClearAllPoints()
            chip:SetPoint("LEFT", host, "LEFT", x, 0)
            chip:Show()
            x = x + chip:GetWidth() + CHIP_GAP
        end

        for index = count + 1, #host.chips do host.chips[index]:Hide() end
    end

    return host
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
function Editor:BuildPage(page, width)
    local grid = UI.Page(page, width)
    self:BuildInto(grid, width)
    page.Refresh = function() self:Refresh() end
    page:SetScript("OnHide", function() self:ReleaseFrame() end)
    return grid
end

-- Into a grid somebody else made - the answer page's Alerts tab. The stage
-- card releases the borrowed frame on its own OnHide, so a page that hides
-- with the tab needs nothing more.
function Editor:BuildInto(grid, width)
    local function Apply() self:Apply() end

    -- Everything that is about the SELECTED reminder, so it can all go away
    -- together when there is not one. Rows know how to hide themselves
    -- (SetRelevant); the blocks that are not rows - the text area, the spell
    -- slot - carry the same flag the layout reads, set by hand.
    local bodyRows, bodyBlocks = {}, {}
    local function Body(row) bodyRows[#bodyRows + 1] = row; return row end

    grid:Note(self.spec.intro)

    -- The list, and the two buttons that change what is in it.
    local list = BuildList(self, grid.content, width - 190)
    grid:Wide(list, LIST_H, 4, 8)

    local addRow = CreateFrame("Frame", nil, grid.content)
    addRow:SetHeight(28)

    local addBtn = UI.Button(addRow, self.spec.newLabel, 132, function()
        local index = self.book:Add()
        if not index then
            ns.Print(self.spec.full .. " (" .. self.book.MAX .. ").")
            return
        end
        self:Select(index)
    end)
    addBtn:SetPoint("LEFT", addRow, "LEFT", 0, 0)

    local removeBtn = UI.Button(addRow, "Delete", 84, function()
        local index = self:Current()
        if not index then return end
        -- The borrowed frame goes home FIRST. Removing the config out from
        -- under a frame that is still parented to the card leaves it there
        -- with nothing to style it and no way to reach it again.
        self:ReleaseFrame()
        self.book:Remove(index)
        self:Refresh()
    end, "quiet")
    removeBtn:SetPoint("LEFT", addBtn, "RIGHT", 8, 0)
    grid:Wide(addRow, 28, 0, 12)

    self.stage = BuildStage(self, grid.content, width)
    grid:Wide(self.stage, STAGE_H, 0, 14)

    ---------------------------------------------------------------------
    -- Reading and writing the selected reminder
    ---------------------------------------------------------------------
    local function Get(key, fallback)
        return function()
            local _, cfg = self:Current()
            if not cfg then return fallback end
            local value = cfg[key]
            if value == nil then return fallback end
            return value
        end
    end
    local function Set(key)
        return function(value)
            local _, cfg = self:Current()
            if cfg then cfg[key] = value end
        end
    end

    ---------------------------------------------------------------------
    grid:Section("What it says")

    local textRow = CreateFrame("Frame", nil, grid.content)
    textRow:SetHeight(80)
    local area = UI.TextArea(textRow, width, 80, function(text)
        local _, cfg = self:Current()
        if not cfg then return end
        cfg.text = text
        -- Styled, not fully refreshed: this runs on every keystroke, and
        -- Refresh would rewrite the box you are typing into.
        local index = self.index
        if index then self.book:Style(index) end
    end, "The words that appear on your screen")
    area:SetPoint("TOPLEFT", textRow, "TOPLEFT", 0, 0)
    self.area = area
    grid:Wide(textRow, 80, 0, 12)
    bodyBlocks[#bodyBlocks + 1] = textRow

    ---------------------------------------------------------------------
    grid:Section("What it watches")

    local spellRow = CreateFrame("Frame", nil, grid.content)
    spellRow:SetHeight(52)

    local slot = UI.SpellSlot(spellRow, {
        size = 46,
        get = function()
            local _, cfg = self:Current()
            return cfg and cfg.spellID
        end,
        onPick = function(spellID)
            local _, cfg = self:Current()
            if not cfg then return end
            cfg.spellID = spellID
            Apply()
        end,
        onClear = function()
            local _, cfg = self:Current()
            if not cfg then return end
            cfg.spellID = nil
            Apply()
        end,
    })
    slot:SetPoint("LEFT", spellRow, "LEFT", 0, 0)
    self.slot = slot

    local spellName = UI.Label(spellRow, "", UI.FS.row, C.text)
    spellName:SetPoint("TOPLEFT", slot, "TOPRIGHT", 12, -6)
    spellName:SetWordWrap(false)

    local spellHint = UI.Label(spellRow, "", UI.FS.meta, C.textFaint)
    spellHint:SetPoint("TOPLEFT", spellName, "BOTTOMLEFT", 0, -4)
    spellHint:SetWidth(width - 70)
    spellHint:SetJustifyH("LEFT")
    spellHint:SetWordWrap(false)

    self.spellName, self.spellHint = spellName, spellHint
    grid:Wide(spellRow, 52, 0, 10)
    bodyBlocks[#bodyBlocks + 1] = spellRow

    local paintTrigger = self.spec.Trigger(self, grid, Body, Get, Set, Apply)

    Body(UI.Toggle(grid:FullRow("Switched on", { controlWidth = 124 }),
        Get("enabled", true), function(value)
            local _, cfg = self:Current()
            if cfg then cfg.enabled = value end
            Apply()
        end))

    -- ITS OWN SOUND, KEYED BY THE SPELL IT WATCHES. Beside the trigger
    -- rather than down in "How it looks", because a noise is not a look -
    -- it is the other half of "this reminder went up", and it belongs next
    -- to the setting that decides when that happens.
    --
    -- A reminder with no spell in it has nothing to key a sound to and can
    -- only use the one Settings chose for all of them; the row says so
    -- rather than writing into a nil.
    local soundEvent = self.spec.sound
    if soundEvent then
        Body(UI.MediaPicker(grid:FullRow("Sound", { controlWidth = 190 }),
            "sound",
            function()
                local _, cfg = self:Current()
                return cfg and cfg.spellID
                    and ns.Sounds.Get(soundEvent, cfg.spellID) or ""
            end,
            function(value)
                local _, cfg = self:Current()
                if cfg and cfg.spellID then
                    ns.Sounds.Set(soundEvent, cfg.spellID, value)
                end
            end,
            function()
                local _, cfg = self:Current()
                if cfg and cfg.spellID then
                    ns.Sounds.Preview(ns.Sounds.Get(soundEvent, cfg.spellID))
                end
            end,
            "Settings"))

        grid:Note(self.spec.soundNote)
    end

    ---------------------------------------------------------------------
    grid:Section("How it looks", self.spec.prefix .. "-look")

    Body(UI.MediaPicker(grid:FullRow("Font", { controlWidth = 190 }), "font",
        Get("font", ""), Set("font"), Apply, "Settings"))

    Body(UI.Slider(grid:FullRow("Size", { controlWidth = 124 }), {
        get = Get("size", 34), set = Set("size"),
        min = 10, max = 96, step = 1, apply = Apply,
    }))

    Body(UI.Dropdown(grid:FullRow("Edge", { controlWidth = 150 }),
        ns.Media.OUTLINES, Get("outline", "THICKOUTLINE"), Set("outline"),
        { apply = Apply }))

    Body(UI.Swatch(grid:FullRow("Colour", { controlWidth = 124 }),
        function()
            local _, cfg = self:Current()
            local colour = (cfg and cfg.color) or { 1, 1, 1 }
            return colour[1], colour[2], colour[3]
        end,
        function(r, g, b)
            local _, cfg = self:Current()
            if cfg then cfg.color = { r, g, b } end
        end, Apply))

    Body(UI.Dropdown(grid:FullRow("Icon", { controlWidth = 150 }),
        ns.REMINDER_ICON_SIDES, Get("iconSide", "left"), Set("iconSide"),
        { apply = Apply }))

    local iconSizeRow = Body(UI.Slider(grid:FullRow("Icon size", { controlWidth = 124 }), {
        get = Get("iconSize", 34), set = Set("iconSize"),
        min = 12, max = 96, step = 1, apply = Apply,
    }))

    Body(UI.Slider(grid:FullRow("Scale", { controlWidth = 124 }), {
        get = Get("scale", 1), set = Set("scale"),
        min = 0.5, max = 2.5, step = 0.05, apply = Apply,
        format = function(v) return string.format("%.2f", v) end,
    }))

    ---------------------------------------------------------------------
    grid:Section("Flashing", self.spec.prefix .. "-flash")

    Body(UI.Toggle(grid:FullRow("Flash", { controlWidth = 124 }),
        Get("flash", true), Set("flash")))

    local flashRate = Body(UI.Slider(grid:FullRow("Speed", { controlWidth = 124 }), {
        get = Get("flashRate", 1.1), set = Set("flashRate"),
        min = 0.2, max = 3.0, step = 0.1, apply = Apply,
        format = function(v) return string.format("%.1f/s", v) end,
    }))

    local flashMin = Body(UI.Slider(grid:FullRow("Fades to", { controlWidth = 124 }), {
        get = Get("flashMin", 0.25), set = Set("flashMin"),
        min = 0, max = 0.9, step = 0.05, apply = Apply, scale = 100,
        format = function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end,
    }))

    grid:Note("It never fades all the way out. A message that vanishes and "
        .. "comes back is one you have to catch; one that dims and brightens "
        .. "is one you cannot miss.")

    ---------------------------------------------------------------------
    -- When it is allowed to appear at all - the bars' own rules, evaluated by
    -- the bars' own evaluator, EDITED BY THE ONE BUILDER every page with a
    -- rule uses (ns.OptionsWhen, 4.84.0). This block was typed out here once;
    -- the builder owns its rows' relevance - with nothing selected the
    -- whole block goes, under any other mode than "Only when..." the rule
    -- rows go - so Paint below does not touch them.
    ---------------------------------------------------------------------
    ns.OptionsWhen.Build(grid, {
        title = "When it may appear",
        anchor = self.spec.prefix .. "-rules",
        open = false,
        holder = function()
            local _, cfg = self:Current()
            return cfg
        end,
        apply = Apply,
        relevant = function()
            local _, cfg = self:Current()
            return cfg and true or false
        end,
    })

    ---------------------------------------------------------------------
    -- What is shown and what is hidden, re-decided every refresh.
    --
    -- SetRelevant rather than a greyed-out control: a row that does not apply
    -- is not a row you might want, it is a row about something you have
    -- switched off. This is the same pattern the bars page uses for its own
    -- rule rows, and the order below is that page's order too - decide first,
    -- then lay out, then refresh - because Layout reads the flag SetRelevant
    -- sets and a Layout that runs first places rows it is about to hide.
    ---------------------------------------------------------------------
    local function Paint()
        local _, cfg = self:Current()
        local has = cfg and true or false

        list.Refresh()
        removeBtn:SetEnabled(has)

        -- WITH NOTHING SELECTED there is nothing for any of these to be about,
        -- so the page is the list and the New button. A page full of dead
        -- controls reads as broken rather than empty.
        for _, row in ipairs(bodyRows) do row:SetRelevant(has) end
        for _, region in ipairs(bodyBlocks) do
            region.dkSkip = not has
            region:SetShown(has)
        end

        -- The test is on `cfg` rather than on `has`, so everything below this
        -- line is reading something that provably exists - to the analyser as
        -- well as to a reader. Gating on the boolean cost eight "check for
        -- nil" warnings that were all about the same missing connection.
        if not cfg then
            self.stage.state:SetText(self.spec.emptyHint)
            self.area:SetText("")
            self.slot.Refresh()
            return
        end

        -- NOT WHILE IT IS BEING TYPED IN. Every keystroke calls Apply, which
        -- ends here; rewriting the box from the config would put the caret
        -- back at the start on every character.
        if not self.area.input:HasFocus() then
            self.area:SetText(cfg.text or "")
        end
        self.slot.Refresh()

        if cfg.spellID then
            self.spellName:SetText(ns.SpellName(cfg.spellID)
                or ("Spell " .. cfg.spellID))
            self.spellHint:SetText(self.spec.StateLine(self.book, cfg))
        else
            self.spellName:SetText("Nothing yet")
            self.spellHint:SetText(
                "Drag a spell out of the list on the right.")
        end

        if paintTrigger then paintTrigger(cfg) end
        iconSizeRow:SetRelevant(cfg.iconSide ~= "none")
        local flashing = cfg.flash and true or false
        flashRate:SetRelevant(flashing)
        flashMin:SetRelevant(flashing)

        -- The live sentence. Green when it is on screen, because that is the
        -- only question anybody asks on this page.
        local reason = self.book:Explain(cfg)
        self.stage.state:SetText(reason
            and ("|cff888888" .. reason .. "|r")
            or "|cff40ff40On your screen right now.|r")

        self:BorrowFrame()
    end

    grid:Layout()
    self.Paint = Paint
    self.grid = grid
    Paint()
    grid:Layout()
    return grid
end

function Editor:Refresh()
    if self.Paint then self.Paint() end
    if self.grid then
        self.grid:Layout()
        self.grid:Refresh()
    end
    if self.spellPane and self.spellPane.Refresh then self.spellPane.Refresh() end
end

---------------------------------------------------------------------------
-- The right-hand column: the spell list, drag and all
--
-- ns.SpellPane:Build with three callbacks of ours. Not a copy -
-- the list, the search, the chips, the grouping, the sorting and the drag are
-- one implementation, and this page only says what a click means here.
---------------------------------------------------------------------------
function Editor:BuildSide(parent, pad)
    local side = CreateFrame("Frame", nil, parent)
    side:SetAllPoints(parent)
    side:Hide()

    local width = parent:GetWidth() - pad * 2

    local title = UI.Label(side, "Spells", UI.FS.card, C.text)
    title:SetPoint("TOPLEFT", side, "TOPLEFT", pad, -16)
    title:SetWidth(width - 96)
    title:SetWordWrap(false)

    local subtitle = UI.Eyebrow(side, "DRAG ONE ONTO THE SLOT")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    subtitle:SetWidth(width - 96)
    subtitle:SetWordWrap(false)

    local host = CreateFrame("Frame", nil, side)
    host:SetPoint("TOPLEFT", side, "TOPLEFT", pad, -(UI.HEADER_H + 16))
    host:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -pad, pad)

    self.spellPane = ns.SpellPane:Build(host, width, {
        -- The spell this reminder already watches, marked the way a spell
        -- already on a bar is. One entry at most, because a reminder watches
        -- one thing.
        Used = function()
            local _, cfg = self:Current()
            if not (cfg and cfg.spellID) then return {} end
            return { [cfg.spellID] = "Watched" }
        end,
        Assign = function(spellID)
            local _, cfg = self:Current()
            if not cfg then
                ns.Print("Make a reminder first - the New reminder button.")
                return
            end
            cfg.spellID = spellID
            self:Apply()
        end,
        Hint = function(spellID)
            local index, cfg = self:Current()
            if not cfg then return "Make a reminder first." end
            if cfg.spellID == spellID then
                return "This reminder already watches it."
            end
            return string.format("Click to have \"%s\" watch it.",
                self.book:Label(cfg, index))
        end,
    })

    self.side = side
    return side
end

---------------------------------------------------------------------------
-- THE REMINDERS PAGE - the first instance, on the reminders' own book. The
-- answer alerts' page is made in Core/OptionsAnswers.lua on theirs.
---------------------------------------------------------------------------
Editor.REMINDER_SPEC = {
    prefix    = "rm",
    intro     = "A line of text on your screen when something is wrong - a "
        .. "buff that has fallen off, a cooldown that is ready and sitting "
        .. "there. Drag the spell in from the list on the right.",
    newLabel  = "New reminder",
    full      = "That is as many reminders as this addon will hold",
    emptyHint = "No reminders yet. New reminder, then drag a spell in from "
        .. "the right.",
    sound     = "reminder",
    soundNote = "Played once when the message appears, not while it is up. "
        .. "The sound follows the SPELL, so two reminders watching the same "
        .. "one share it - a reminder with no spell picked uses whatever "
        .. "|cffffd100Settings - Sounds|r chose.",

    Trigger = function(_, grid, Body, Get, Set, Apply)
        Body(UI.Dropdown(grid:FullRow("Appears", { controlWidth = 190 }),
            ns.REMINDER_TRIGGERS, Get("trigger", "missing"), Set("trigger"),
            { apply = Apply }))
        grid:Note("Active is the game's own answer for that spell.")
        return nil
    end,

    StateLine = function(book, cfg)
        local state, why = book:State(cfg)
        return state and ("The Cooldown Manager says: " .. state)
            or ("Cannot tell - " .. (why or "no reason given"))
    end,
}

ns.OptionsReminders = Editor.New(ns.Reminders, Editor.REMINDER_SPEC)
