---------------------------------------------------------------------------
-- OptionsReminders - the Reminders page and its spell list.
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

local OptionsReminders = {}
ns.OptionsReminders = OptionsReminders

local UI = ns.UI
local C = UI.C
local Reminders = ns.Reminders

-- Which reminder the page is showing. Clamped on every read rather than
-- fixed up on delete: a stale index after a removal is the everyday case, and
-- a clamp in one place beats a correction in six.
function OptionsReminders:Current()
    local count = Reminders:Count()
    if count == 0 then
        self.index = nil
        return nil, nil
    end
    local index = self.index or 1
    if index > count then index = count end
    if index < 1 then index = 1 end
    self.index = index
    return index, Reminders:Get(index)
end

function OptionsReminders:Select(index)
    self.index = index
    self:Refresh()
end

-- Every control ends here. Style redraws the frame from the settings; Rebuild
-- is only needed when the NUMBER of reminders changed.
local function Apply()
    local index = OptionsReminders.index
    if index then Reminders:Style(index) end
    Reminders:Refresh()
    OptionsReminders:Refresh()
end

---------------------------------------------------------------------------
-- The preview card
---------------------------------------------------------------------------
local STAGE_H = 120

local function BuildStage(parent, width)
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

    card:SetScript("OnHide", function() OptionsReminders:ReleaseFrame() end)
    return card
end

function OptionsReminders:BorrowFrame()
    local index = self:Current()
    if not (index and self.stage) then return end

    -- A DIFFERENT REMINDER THAN THE ONE ALREADY BORROWED means putting the
    -- first one back before taking the second. Without this, clicking through
    -- the list leaves every reminder you looked at parented to the card and
    -- gone from the screen - the exact fault the co-tank panel's release is
    -- written to avoid, one selection deeper.
    if self.borrowed and self.borrowed ~= index then self:ReleaseFrame() end
    if self.borrowed == index then return end

    local frame = Reminders:Borrow(index, self.stage.slot)
    if not frame then return end
    self.borrowed = index
end

function OptionsReminders:ReleaseFrame()
    if not self.borrowed then return end
    self.borrowed = nil
    Reminders:Release()
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

local function BuildList(parent, width)
    local host = CreateFrame("Frame", nil, parent)
    host:SetSize(width, LIST_H)
    host.chips = {}

    -- NO SELF. Grid:Refresh calls `widget.Refresh()` with no arguments, so a
    -- method written as `function(self)` gets nil and raises on the first
    -- field it touches. Every Refresh in this file closes over what it needs.
    host.Refresh = function()
        local count = Reminders:Count()
        local current = OptionsReminders:Current()
        local x = 0

        for index = 1, count do
            local chip = host.chips[index]
            if not chip then
                chip = UI.GhostButton(host, "", function()
                    OptionsReminders:Select(index)
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
            local cfg = Reminders:Get(index)
            local label = Reminders:Label(cfg, index)
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
function OptionsReminders:BuildPage(page, width)
    local grid = UI.Page(page, width)

    -- Everything that is about the SELECTED reminder, so it can all go away
    -- together when there is not one. Rows know how to hide themselves
    -- (SetRelevant); the blocks that are not rows - the text area, the spell
    -- slot - carry the same flag the layout reads, set by hand.
    local bodyRows, bodyBlocks = {}, {}
    local function Body(row) bodyRows[#bodyRows + 1] = row; return row end

    grid:Note("A line of text on your screen when something is wrong - a buff "
        .. "that has fallen off, a cooldown that is ready and sitting there. "
        .. "Drag the spell in from the list on the right.")

    -- The list, and the two buttons that change what is in it.
    local list = BuildList(grid.content, width - 190)
    grid:Wide(list, LIST_H, 4, 8)

    local addRow = CreateFrame("Frame", nil, grid.content)
    addRow:SetHeight(28)

    local addBtn = UI.Button(addRow, "New reminder", 132, function()
        local index = Reminders:Add()
        if not index then
            ns.Print("That is as many reminders as this addon will hold ("
                .. Reminders.MAX .. ").")
            return
        end
        OptionsReminders:Select(index)
    end)
    addBtn:SetPoint("LEFT", addRow, "LEFT", 0, 0)

    local removeBtn = UI.Button(addRow, "Delete", 84, function()
        local index = OptionsReminders:Current()
        if not index then return end
        -- The borrowed frame goes home FIRST. Removing the config out from
        -- under a frame that is still parented to the card leaves it there
        -- with nothing to style it and no way to reach it again.
        OptionsReminders:ReleaseFrame()
        Reminders:Remove(index)
        OptionsReminders:Refresh()
    end, "quiet")
    removeBtn:SetPoint("LEFT", addBtn, "RIGHT", 8, 0)
    grid:Wide(addRow, 28, 0, 12)

    self.stage = BuildStage(grid.content, width)
    grid:Wide(self.stage, STAGE_H, 0, 14)

    ---------------------------------------------------------------------
    -- Reading and writing the selected reminder
    ---------------------------------------------------------------------
    local function Get(key, fallback)
        return function()
            local _, cfg = OptionsReminders:Current()
            if not cfg then return fallback end
            local value = cfg[key]
            if value == nil then return fallback end
            return value
        end
    end
    local function Set(key)
        return function(value)
            local _, cfg = OptionsReminders:Current()
            if cfg then cfg[key] = value end
        end
    end

    ---------------------------------------------------------------------
    grid:Section("What it says")

    local textRow = CreateFrame("Frame", nil, grid.content)
    textRow:SetHeight(80)
    local area = UI.TextArea(textRow, width, 80, function(text)
        local _, cfg = OptionsReminders:Current()
        if not cfg then return end
        cfg.text = text
        -- Styled, not fully refreshed: this runs on every keystroke, and
        -- Refresh would rewrite the box you are typing into.
        local index = OptionsReminders.index
        if index then Reminders:Style(index) end
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
            local _, cfg = OptionsReminders:Current()
            return cfg and cfg.spellID
        end,
        onPick = function(spellID)
            local _, cfg = OptionsReminders:Current()
            if not cfg then return end
            cfg.spellID = spellID
            Apply()
        end,
        onClear = function()
            local _, cfg = OptionsReminders:Current()
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

    Body(UI.Dropdown(grid:FullRow("Appears", { controlWidth = 190 }),
        ns.REMINDER_TRIGGERS, Get("trigger", "missing"), Set("trigger"),
        { apply = Apply }))

    grid:Note("Active is the game's own answer for that spell.")

    Body(UI.Toggle(grid:FullRow("Switched on", { controlWidth = 124 }),
        Get("enabled", true), function(value)
            local _, cfg = OptionsReminders:Current()
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
    Body(UI.MediaPicker(grid:FullRow("Sound", { controlWidth = 190 }),
        "sound",
        function()
            local _, cfg = OptionsReminders:Current()
            return cfg and cfg.spellID
                and ns.Sounds.Get("reminder", cfg.spellID) or ""
        end,
        function(value)
            local _, cfg = OptionsReminders:Current()
            if cfg and cfg.spellID then
                ns.Sounds.Set("reminder", cfg.spellID, value)
            end
        end,
        function()
            local _, cfg = OptionsReminders:Current()
            if cfg and cfg.spellID then
                ns.Sounds.Preview(ns.Sounds.Get("reminder", cfg.spellID))
            end
        end,
        "Settings"))

    grid:Note("Played once when the message appears, not while it is up. "
        .. "The sound follows the SPELL, so two reminders watching the same "
        .. "one share it - a reminder with no spell picked uses whatever "
        .. "|cffffd100Settings - Sounds|r chose.")

    ---------------------------------------------------------------------
    grid:Section("How it looks", "rm-look")

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
            local _, cfg = OptionsReminders:Current()
            local colour = (cfg and cfg.color) or { 1, 1, 1 }
            return colour[1], colour[2], colour[3]
        end,
        function(r, g, b)
            local _, cfg = OptionsReminders:Current()
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
    grid:Section("Flashing", "rm-flash")

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
    -- the bars' own evaluator. A second vocabulary for "only in combat" is a
    -- second thing to learn and a second thing to get wrong.
    ---------------------------------------------------------------------
    grid:Section("When it may appear", "rm-rules")

    local function RuleGet(key, fallback)
        return function()
            local _, cfg = OptionsReminders:Current()
            local value = cfg and cfg.show and cfg.show[key]
            if value == nil then return fallback end
            return value
        end
    end
    local function RuleSet(key)
        return function(value)
            local _, cfg = OptionsReminders:Current()
            if cfg and cfg.show then cfg.show[key] = value end
        end
    end

    Body(UI.Dropdown(grid:FullRow("Show", { controlWidth = 150 }),
        ns.SHOW_MODES, RuleGet("mode", "rules"), RuleSet("mode"),
        { apply = Apply }))

    local ruleRows = {}
    local function Rule(row)
        ruleRows[#ruleRows + 1] = row
        -- A rule row is BOTH: it goes away with the reminder, and it goes
        -- away when the mode is not "Only when...". Paint decides in that
        -- order, so the second test only runs when there is one at all.
        bodyRows[#bodyRows + 1] = row
        return row
    end

    Rule(UI.Dropdown(grid:FullRow("Combat",
        { controlWidth = 150, icon = "cond-combat" }),
        ns.SHOW_COMBAT, RuleGet("combat", "in"), RuleSet("combat"),
        { apply = Apply }))
    Rule(UI.Dropdown(grid:FullRow("Group",
        { controlWidth = 150, icon = "cond-group" }),
        ns.SHOW_GROUP, RuleGet("group", "any"), RuleSet("group"),
        { apply = Apply }))
    Rule(UI.Dropdown(grid:FullRow("Target",
        { controlWidth = 150, icon = "cond-target" }),
        ns.SHOW_TARGET, RuleGet("target", "any"), RuleSet("target"),
        { apply = Apply }))

    for _, place in ipairs(ns.SHOW_WHERE) do
        Rule(UI.Toggle(grid:FullRow(place.text,
            { controlWidth = 124, icon = place.icon }),
            function()
                local _, cfg = OptionsReminders:Current()
                local where = cfg and cfg.show and cfg.show.where
                return where and where[place.key] and true or false
            end,
            function(value)
                local _, cfg = OptionsReminders:Current()
                if not (cfg and cfg.show) then return end
                cfg.show.where = cfg.show.where or {}
                -- FALSE, never nil: the defaults are re-applied on every load
                -- and a missing key comes back as "allowed".
                cfg.show.where[place.key] = value and true or false
                Apply()
            end))
    end

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
        local _, cfg = OptionsReminders:Current()
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
            OptionsReminders.stage.state:SetText(
                "No reminders yet. New reminder, then drag a spell in from "
                .. "the right.")
            OptionsReminders.area:SetText("")
            OptionsReminders.slot.Refresh()
            return
        end

        -- NOT WHILE IT IS BEING TYPED IN. Every keystroke calls Apply, which
        -- ends here; rewriting the box from the config would put the caret
        -- back at the start on every character.
        if not OptionsReminders.area.input:HasFocus() then
            OptionsReminders.area:SetText(cfg.text or "")
        end
        OptionsReminders.slot.Refresh()

        if cfg.spellID then
            OptionsReminders.spellName:SetText(ns.SpellName(cfg.spellID)
                or ("Spell " .. cfg.spellID))
            local state, why = Reminders:State(cfg)
            OptionsReminders.spellHint:SetText(state
                and ("The Cooldown Manager says: " .. state)
                or ("Cannot tell - " .. (why or "no reason given")))
        else
            OptionsReminders.spellName:SetText("Nothing yet")
            OptionsReminders.spellHint:SetText(
                "Drag a spell out of the list on the right.")
        end

        local ruled = (cfg.show and cfg.show.mode) == "rules"
        for _, row in ipairs(ruleRows) do row:SetRelevant(ruled) end

        iconSizeRow:SetRelevant(cfg.iconSide ~= "none")
        local flashing = cfg.flash and true or false
        flashRate:SetRelevant(flashing)
        flashMin:SetRelevant(flashing)

        -- The live sentence. Green when it is on screen, because that is the
        -- only question anybody asks on this page.
        local reason = Reminders:Explain(cfg)
        OptionsReminders.stage.state:SetText(reason
            and ("|cff888888" .. reason .. "|r")
            or "|cff40ff40On your screen right now.|r")

        OptionsReminders:BorrowFrame()
    end

    grid:Layout()
    self.Paint = Paint
    page.Refresh = function() OptionsReminders:Refresh() end
    page:SetScript("OnHide", function() OptionsReminders:ReleaseFrame() end)
    self.grid = grid
    Paint()
    grid:Layout()
    return grid
end

function OptionsReminders:Refresh()
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
function OptionsReminders:BuildSide(parent, pad)
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
            local _, cfg = OptionsReminders:Current()
            if not (cfg and cfg.spellID) then return {} end
            return { [cfg.spellID] = "Watched" }
        end,
        Assign = function(spellID)
            local _, cfg = OptionsReminders:Current()
            if not cfg then
                ns.Print("Make a reminder first - the New reminder button.")
                return
            end
            cfg.spellID = spellID
            Apply()
        end,
        Hint = function(spellID)
            local index, cfg = OptionsReminders:Current()
            if not cfg then return "Make a reminder first." end
            if cfg.spellID == spellID then
                return "This reminder already watches it."
            end
            return string.format("Click to have \"%s\" watch it.",
                Reminders:Label(cfg, index))
        end,
    })

    self.side = side
    return side
end
