---------------------------------------------------------------------------
-- OptionsCoTanks - the Co-Tanks page and its inspector.
--
-- The middle column is the PREVIEW and the handful of settings you change
-- while looking at it. The right-hand column is everything else, in tabs.
-- That split is the owner's, and it is the right one: a preview is only worth
-- the space if the controls that change what it shows are next to it, and the
-- forty that you set once are not those controls.
--
-- THE PREVIEW IS THE REAL DISPLAY, MOVED.
--
-- There is no second renderer in this file. The card in the middle holds the
-- actual co-tank panel, reparented into it and put back when you leave.
-- Every preview in this addon that drew itself has drifted from the thing it
-- was previewing - the bar card did it twice in one session - and the only
-- fix that holds is to have nothing to drift.
---------------------------------------------------------------------------
local _, ns = ...

local OptionsCoTanks = {}
ns.OptionsCoTanks = OptionsCoTanks

local UI = ns.UI
local C = UI.C

local function DB() return ns.db.coTanks end

-- Everything on this page changes what is on screen, so every control ends
-- here. ApplyLayout restyles the rows and rebuilds the aura containers;
-- Refresh only repaints. Which one a control needs is the difference between
-- a slider that stutters and one that does not.
local function Apply()
    ns.CoTanks:ApplyLayout()
    -- AND THE PAGE IS RE-READ, not just the display repainted.
    --
    -- Rows on this page appear and disappear with the settings above them -
    -- the gradient's second colour and direction, the custom colour, the
    -- three-colour ramp. That decision lives in a Refresh hook, and
    -- Grid:Refresh is what runs it (and lays out afterwards). Calling only
    -- Layout, as this did, moved the rows that were already showing and never
    -- asked whether a different set should be: switch a gradient on and its
    -- two rows stayed hidden until something else happened to refresh.
    --
    -- Same shape as OptionsBars, whose Apply ends in ns.Options:Refresh for
    -- exactly this reason. It also re-fits the borrowed preview, which may
    -- have changed size.
    OptionsCoTanks:Refresh()
end

local function Repaint()
    ns.CoTanks:Refresh()
end

---------------------------------------------------------------------------
-- The preview
--
-- The panel itself, borrowed. It goes home on hide, and it goes home whatever
-- happens: a display left parented to a closed window is a display that has
-- vanished, and the user's only clue would be that their co-tanks stopped
-- appearing after they looked at the settings once.
---------------------------------------------------------------------------
-- ONE ROW, so the card no longer has to be tall enough for a stack of five -
-- and with only one in it FitPanel stops scaling the panel down, which is
-- what actually made everything unreadable. There is still room for a row
-- turned right up with aura strips above and below it; past that FitPanel
-- shrinks it to fit, as it always did.
local STAGE_H = 180

local function BuildStage(parent, width)
    local card = UI.Card(parent, width)
    -- A card sets its own width and nothing else; the grid only positions it.
    -- Left without a height it is zero pixels tall and everything in it draws
    -- somewhere nobody can see - which is how a section header once shipped
    -- laid out perfectly and invisible.
    card:SetHeight(STAGE_H)

    local caption = UI.Eyebrow(card, "Preview")
    caption:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -12)

    -- NO EXPLANATION UNDER THE HEADING. There was one, describing how the
    -- preview is implemented - that the panel is borrowed rather than drawn.
    -- That is a fact about the code, not about the user's display, and the
    -- owner's verdict was exactly right: nobody cares, and nobody would
    -- understand it if this were NOT a preview. Three lines of text at the top
    -- of the card also pushed the thing you came to look at down the page.

    -- Where the borrowed panel sits. Its own frame so the panel is anchored to
    -- something whose size this file controls rather than to the card.
    local slot = CreateFrame("Frame", nil, card)
    slot:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 0, -10)
    slot:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -14, 14)

    card.slot = slot

    -- The panel is only borrowed while the page is on screen AND the window
    -- is. Both conditions, because hiding the window does not hide a page.
    card:SetScript("OnHide", function() OptionsCoTanks:ReleasePanel() end)

    return card
end

function OptionsCoTanks:BorrowPanel()
    local panel = ns.CoTanks.panel
    if not (panel and self.stage) then return end
    if self.borrowed then return end

    -- Remembered so it can be put back exactly, rather than dropped at a
    -- default that would quietly move the user's panel every time they looked
    -- at this page.
    local db = DB()
    self.homePoint = { db.point, db.relPoint, db.x, db.y }
    self.homeScale = panel:GetScale()

    self.borrowed = true
    -- Read by CoTanks:ApplyLayout, ShouldShow and SavePosition: while this is
    -- set the panel takes its position from the card, shows whether or not
    -- the feature is switched on, and never writes its position back.
    ns.CoTanks.hosted = true
    -- CENTRED, not hung from the top. With five rows the panel filled the slot
    -- and it made no difference; with one it would sit at the top of an empty
    -- card and read as something that failed to draw.
    panel:SetParent(self.stage.slot)
    panel:ClearAllPoints()
    panel:SetPoint("CENTER", self.stage.slot, "CENTER", 0, 0)

    -- AND NOW ASK IT TO DRAW ITSELF. Setting `hosted` only changes what
    -- ShouldShow and RowCount ANSWER - it does not make anything ask, and
    -- nothing on this path did. With the feature off (the shipped default)
    -- the last Refresh had taken the early exit that hides every row and
    -- returns before the panel is ever given a size, so the card showed the
    -- word "Preview" over a nought-by-nought frame full of hidden rows.
    --
    -- ApplyLayout rather than Refresh, so Borrow and Release are symmetric:
    -- both end by re-applying the layout under the new value of `hosted`.
    -- Before FitPanel, because FitPanel measures the panel's height.
    ns.CoTanks:ApplyLayout()
    panel:Show()
    self:FitPanel()
end

-- WORKED OUT EVERY REFRESH, not once when the panel was borrowed. Width is one
-- of the four sliders on this very page, so a scale taken at borrow time is
-- wrong the moment somebody uses the control the preview is there to show -
-- the panel simply grew out of the card.
function OptionsCoTanks:FitPanel()
    local panel = ns.CoTanks.panel
    if not (panel and self.borrowed and self.stage) then return end

    local room = self.stage.slot:GetWidth() - 8
    local wide = math.max(1, DB().width)
    local tall = math.max(1, panel:GetHeight())
    local high = math.max(1, self.stage.slot:GetHeight() - 4)

    -- The tighter of the two, so a tall stack of rows shrinks as well. A
    -- preview you have to scroll is not a preview.
    panel:SetScale(math.min(1, room / wide, high / tall))
end

function OptionsCoTanks:ReleasePanel()
    local panel = ns.CoTanks.panel
    if not (panel and self.borrowed) then return end
    self.borrowed = false
    ns.CoTanks.hosted = nil

    panel:SetParent(UIParent)
    panel:SetScale(self.homeScale or 1)
    panel:ClearAllPoints()
    local home = self.homePoint
    if home then
        panel:SetPoint(home[1], UIParent, home[2], home[3], home[4])
    end
    ns.CoTanks:ApplyLayout()
end

---------------------------------------------------------------------------
-- The middle column
---------------------------------------------------------------------------
function OptionsCoTanks:BuildPage(page, width)
    local grid = UI.Page(page, width)

    self.stage = BuildStage(grid.content, grid.width)
    grid:Wide(self.stage, STAGE_H, 0, 14)

    grid:Section("Switch it on")

    UI.Toggle(grid:FullRow("Show co-tanks", {
        controlWidth = 124,
        sublabel = "A row for every tank in your group",
    }), function() return DB().enabled end,
        function(value) DB().enabled = value; Apply() end)

    -- TEST MODE IS THE POINT OF THIS PAGE ON A NORMAL EVENING. Nobody sits in
    -- a raid to adjust a panel, and every other setting here is unjudgeable
    -- without one - so this is not a debugging aid tucked away at the bottom,
    -- it is the second control on the page.
    UI.Toggle(grid:FullRow("Test mode", {
        controlWidth = 124,
        sublabel = "Invented tanks, so it can be set up without a raid",
    }), function() return DB().testMode end,
        function(value) ns.CoTanks:SetTestMode(value) end)

    -- NO PARAGRAPH EXPLAINING WHAT A TEST MODE IS. Everyone who plays this
    -- game has used one - "wow spieler kennen das" - and the sublabel on the
    -- switch already says what these tanks are. `/zs tanks test` still works
    -- and is listed with the other commands.

    -- NO "MOVE IT" BUTTON. It moved into Edit Mode, where every other thing
    -- this addon draws is placed - the owner's call, and the right one: a
    -- display moved from a button on a settings page is moved blind, because
    -- the window is sitting over the place you are trying to put it.
    grid:Note("To move it, open |cffffd100Edit mode|r at the top of the list "
        .. "on the left. The panel comes out while you are in there even if "
        .. "it is switched off, it drags like a bar, and it snaps to your "
        .. "bars and to the middle of the screen - hold |cffffd100Alt|r to "
        .. "put it exactly where you want it instead.")

    grid:Section("The basics")

    UI.Slider(grid:FullRow("Width", { controlWidth = 124 }), {
        get = function() return DB().width end,
        set = function(value) DB().width = value end,
        min = 100, max = 480, step = 5, apply = Apply,
    })
    UI.Slider(grid:FullRow("Row height", { controlWidth = 124 }), {
        get = function() return DB().rowHeight end,
        set = function(value) DB().rowHeight = value end,
        min = 12, max = 60, step = 1, apply = Apply,
    })
    UI.Slider(grid:FullRow("Gap", { controlWidth = 124 }), {
        get = function() return DB().spacing end,
        set = function(value) DB().spacing = value end,
        min = 0, max = 30, step = 1, apply = Apply,
    })
    UI.Slider(grid:FullRow("Scale", { controlWidth = 124 }), {
        get = function() return DB().scale end,
        set = function(value) DB().scale = value end,
        min = 0.5, max = 2.0, step = 0.05, apply = Apply,
        format = function(v) return string.format("%.2f", v) end,
    })

    grid:Note("Everything else - colours, texts, indicators and the aura "
        .. "strips - is in the column on the right.")

    ---------------------------------------------------------------------
    -- Taunts
    --
    -- On the co-tank page because a taunt announce is about the OTHER tank,
    -- and this is the page about the other tank. Roadmap item 6.
    --
    -- WHAT IT CANNOT DO IS ON THE PAGE, not buried in a comment. An addon
    -- cannot see the co-tank's taunt on this patch - another player's instant
    -- cast has not been announced since 12.0.5 - and a settings page that
    -- quietly leaves that out is how somebody ends up trusting a panel that
    -- is not watching anything.
    ---------------------------------------------------------------------
    local T = ns.Taunts
    local function TCfg() return T.Config() end

    grid:Section("Taunts")

    UI.Toggle(grid:FullRow("Say when you taunt", {
        controlWidth = 124,
        sublabel = "One line in chat, so the other tank knows you took it",
    }), function() return TCfg().announce and true or false end,
        function(value) TCfg().announce = value and true or false end)

    local channelHost = CreateFrame("Frame", nil, grid.content)
    local chips = UI.ChipRow(channelHost, grid.width - 8, {
        chips = {
            { key = "WHISPER",      text = "Whisper the tank" },
            { key = "GROUP",        text = "Party or raid" },
            { key = "RAID_WARNING", text = "Raid warning" },
            { key = "SAY",          text = "Say" },
            { key = "YELL",         text = "Yell" },
        },
        isOn = function(key) return T.ChannelOn(key) end,
        onSelect = function(key)
            T.ToggleChannel(key)
            ns.Options:Refresh()
        end,
    })
    chips:SetPoint("TOPLEFT", channelHost, "TOPLEFT", 0, 0)
    channelHost:SetHeight(chips:GetHeight())
    grid:Wide(channelHost, chips:GetHeight(), 4, 8)
    channelHost.Refresh = function() chips.Refresh() end

    grid:Note("|cffffd100Party or raid|r picks the channel for the group you "
        .. "are actually in - in a dungeon from the finder that is NOT party "
        .. "chat, which is why it is one button and not three. "
        .. "|cffffd100Whisper the tank|r goes to the other tank alone, and is "
        .. "dropped when there is nobody else tanking.")

    local messageRow = grid:FullRow("Message", { controlWidth = 260 })
    local messageInput = UI.Input(messageRow.slot, 260, function(text)
        TCfg().message = (text ~= "" and text) or nil
    end, false, T.DEFAULT_MESSAGE)
    messageInput:SetPoint("RIGHT", messageRow.slot, "RIGHT", 0, 0)
    messageRow.Refresh = function()
        messageInput:SetText(TCfg().message or "")
    end

    local askRow = grid:FullRow("Asking for a swap", { controlWidth = 260 })
    local askInput = UI.Input(askRow.slot, 260, function(text)
        TCfg().ask = (text ~= "" and text) or nil
    end, false, T.DEFAULT_ASK)
    askInput:SetPoint("RIGHT", askRow.slot, "RIGHT", 0, 0)
    askRow.Refresh = function() askInput:SetText(TCfg().ask or "") end

    grid:Note("|cffffd100%t|r is what you taunted, |cffffd100%s|r is the "
        .. "taunt you pressed and |cffffd100%n|r is the other tank. A "
        .. "placeholder nothing filled comes out of the sentence rather than "
        .. "being read out as \"%t\" by somebody mid-pull.\n\n"
        .. "The second line is what |cffffd100/zs taunt ask|r says - put that "
        .. "in a macro and give it a key, and it is one press to tell the "
        .. "other tank to take it.")

    UI.Toggle(grid:FullRow("Only in a group", { controlWidth = 124 }),
        function() return TCfg().onlyInGroup ~= false end,
        function(value) TCfg().onlyInGroup = value and true or false end)

    UI.Toggle(grid:FullRow("Only in dungeons and raids", { controlWidth = 124 }),
        function() return TCfg().onlyInInstance and true or false end,
        function(value) TCfg().onlyInInstance = value and true or false end)

    ---------------------------------------------------------------------
    -- THREE WAYS TO ASK, and they all run the same line
    --
    -- Owner: "kann man das nicht einbauen, also fertiges dynamisches macro,
    -- und als button zum stylen mit icon auswahl?"
    ---------------------------------------------------------------------
    grid:Section("Asking for a taunt")

    UI.Toggle(grid:FullRow("A button on your screen", {
        controlWidth = 124,
        sublabel = "Click it to tell the other tank to take it",
    }), function() return TCfg().button and true or false end,
        function(value)
            TCfg().button = value and true or false
            ns.Taunts.Refresh()
        end)

    UI.Toggle(grid:FullRow("Only in a group", { controlWidth = 124 }),
        function() return TCfg().buttonOnlyInGroup ~= false end,
        function(value)
            TCfg().buttonOnlyInGroup = value and true or false
            ns.Taunts.Refresh()
        end)

    -- THE ICON, with the class taunts as the likely answers. Yours is the
    -- default and it is the right one: it is the picture you already press.
    local iconRow = grid:FullRow("Icon", { controlWidth = 124 })
    local iconButton = UI.MenuButton(iconRow.slot, 124, UI.BUTTON_H)
    iconButton:SetPoint("RIGHT", iconRow.slot, "RIGHT", 0, 0)

    local iconPreview = iconButton:CreateTexture(nil, "ARTWORK")
    iconPreview:SetSize(UI.BUTTON_H - 8, UI.BUTTON_H - 8)
    iconPreview:SetPoint("LEFT", iconButton, "LEFT", 6, 0)
    iconPreview:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    iconButton:SetScript("OnClick", function(self)
        local quick = {}
        for _, entry in ipairs(ns.Taunts.SPELLS) do
            local texture = ns.SpellTexture(entry.spellID)
            if texture then quick[#quick + 1] = texture end
        end
        UI.ShowIconPicker(self, {
            current = ns.Taunts.Icon(),
            quick = quick,
            onPick = function(texture)
                -- The class default is stored as "no choice", not as the
                -- number it happens to be today: change spec or character and
                -- a stored number would be somebody else's taunt.
                local _, class = UnitClass("player")
                local mine
                for _, entry in ipairs(ns.Taunts.SPELLS) do
                    if entry.class == class then
                        mine = mine or ns.SpellTexture(entry.spellID)
                    end
                end
                TCfg().icon = (texture ~= mine) and texture or nil
                ns.Taunts.Refresh()
                ns.Options:Refresh()
            end,
        })
    end)

    iconRow.Refresh = function()
        iconPreview:SetTexture(ns.Taunts.Icon())
        iconButton:SetText(TCfg().icon and "Chosen" or "Your taunt")
    end

    UI.Slider(grid:FullRow("Button size", { controlWidth = 124 }), {
        get = function() return TCfg().size or 44 end,
        set = function(value) TCfg().size = value end,
        min = 20, max = 80, step = 2,
        apply = function() ns.Taunts.Refresh() end,
    })

    grid:Note("The button is placed in |cffffd100Edit mode|r like everything "
        .. "else this addon draws, and it has the same cog and padlock the "
        .. "panels do. Its border and backdrop are the bar settings, under "
        .. "|cffffd100Look|r on the right.")

    grid:Buttons({
        { text = "Make the macro", width = 150, style = "primary",
          onClick = function()
              local ok, why = ns.Taunts.MakeMacro()
              ns.Print(ok and ("|cff40ff40Macro " .. tostring(why) .. ".|r")
                  or ("|cffff8040Not made:|r " .. tostring(why)))
          end },
        { text = "What a taunt would say", width = 190,
          onClick = function() ns.Taunts:Dump() end },
    }, 10)

    grid:Note("|cffffd100Make the macro|r writes a macro called "
        .. "|cffffd100ZS Taunt|r with the icon above and keeps it in step - "
        .. "drag it onto a bar from the macro window. Or skip the macro "
        .. "entirely: the game's own |cffffd100Key Bindings|r has a "
        .. "|cffffd100ZwoelfStuff|r section with |cffffd100Ask the other tank "
        .. "to taunt|r in it. All three do the same thing.")

    grid:Note("|cffff8040What this cannot do:|r tell you when the OTHER tank "
        .. "taunts. Since 12.0.5 another player's instant cast is not "
        .. "announced to addons at all, the combat log is closed, and every "
        .. "taunt in the game is instant - so anything claiming to show you "
        .. "the co-tank's taunt is guessing. Yours is readable, which is why "
        .. "this says yours out loud instead.")

    grid:Layout()
    page.Refresh = function() grid:Refresh() end
    self.pageGrid = grid
    return grid
end

---------------------------------------------------------------------------
-- The right-hand column
---------------------------------------------------------------------------
function OptionsCoTanks:BuildSide(parent, pad)
    local side = CreateFrame("Frame", nil, parent)
    side:SetAllPoints(parent)
    side:Hide()

    local width = parent:GetWidth() - pad * 2

    local title = UI.Label(side, "Co-tank rows", UI.FS.card, C.text)
    title:SetPoint("TOPLEFT", side, "TOPLEFT", pad, -16)
    title:SetWidth(width - 96)
    title:SetWordWrap(false)

    local subtitle = UI.Eyebrow(side, "EVERY SETTING")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    subtitle:SetWidth(width - 96)
    subtitle:SetWordWrap(false)

    local host = CreateFrame("Frame", nil, side)
    host:SetPoint("TOPLEFT", side, "TOPLEFT", pad, -(UI.HEADER_H + 16))
    host:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -pad, pad)

    -- The tab strip on top, the page under it. Both edges anchored, never a
    -- measured width - the column is a fixed 400 today and that is exactly
    -- the kind of number that moves once and breaks something nobody looks at.
    local body = CreateFrame("Frame", nil, host)
    local strip
    local grid

    strip = UI.TabStrip(host, { "Look", "Text", "Auras", "Rules" },
        function(name)
            grid:ShowTab(name)
            strip:Select(name)
        end)
    strip:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)

    body:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, -UI.PAD)
    body:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)

    grid = UI.Page(body, width)

    self:BuildLook(grid)
    self:BuildText(grid)
    self:BuildAuras(grid)
    self:BuildRules(grid)

    grid.tab = "Look"
    grid:Layout()
    -- LAY THE STRIP OUT. Its tabs are created with no width and no x - Layout
    -- is what divides the strip between them - so without this the four tabs
    -- exist, answer to clicks nobody can aim at, and are invisible. Look was
    -- the open tab, so the page LOOKED complete and Text, Auras and Rules
    -- simply could not be reached: "rechts fehlt auch einiges".
    strip:Layout()
    strip:Select("Look")
    grid:ShowTab("Look")

    side.Refresh = function()
        grid:Refresh()
        OptionsCoTanks:BorrowPanel()
        OptionsCoTanks:FitPanel()
    end

    side:SetScript("OnShow", function() OptionsCoTanks:BorrowPanel() end)
    side:SetScript("OnHide", function() OptionsCoTanks:ReleasePanel() end)

    self.side = side
    self.grid = grid
    return side
end

function OptionsCoTanks:Refresh()
    if self.side and self.side.Refresh then self.side:Refresh() end
    if self.pageGrid then self.pageGrid:Refresh() end
end

-- Declared up here rather than beside the text section, because the
-- indicators use the same nine and a second copy would drift.
local TEXT_ANCHORS = {
    { value = "TOPLEFT",     text = "Top left" },
    { value = "TOP",         text = "Top" },
    { value = "TOPRIGHT",    text = "Top right" },
    { value = "LEFT",        text = "Left" },
    { value = "CENTER",      text = "Centre" },
    { value = "RIGHT",       text = "Right" },
    { value = "BOTTOMLEFT",  text = "Bottom left" },
    { value = "BOTTOM",      text = "Bottom" },
    { value = "BOTTOMRIGHT", text = "Bottom right" },
}

---------------------------------------------------------------------------
-- Control helpers
--
-- The same four shapes the bar inspector uses, pointed at ns.db.coTanks
-- instead of at a bar. Written out rather than shared with OptionsBars
-- because that one resolves through a SELECTION - which bar, which cell - and
-- there is exactly one co-tank panel. Threading a selection that is always
-- the same thing through forty call sites buys nothing.
---------------------------------------------------------------------------
local function Get(key) return function() return DB()[key] end end
local function Set(key, after)
    return function(value) DB()[key] = value; (after or Apply)() end
end

local function Slide(grid, label, key, min, max, step, format, scale, sublabel)
    return UI.Slider(grid:FullRow(label, { controlWidth = 124, sublabel = sublabel }), {
        get = Get(key), set = function(value) DB()[key] = value end,
        min = min, max = max, step = step, format = format, scale = scale,
        apply = Apply,
    })
end

local function Switch(grid, label, key, sublabel)
    return UI.Toggle(grid:FullRow(label, { controlWidth = 124, sublabel = sublabel }),
        Get(key), Set(key))
end

local function Colour(grid, label, key)
    return UI.Swatch(grid:FullRow(label, { controlWidth = 124 }),
        function()
            local colour = DB()[key] or { 0, 0, 0 }
            return colour[1], colour[2], colour[3]
        end,
        function(r, g, b) DB()[key] = { r, g, b } end,
        Apply)
end

-- The gradient trio, exactly as the bars have it: a switch, a second colour
-- and a direction, with the last two hidden until the switch is on. Same
-- three colours can ramp here as there, and for the same reasons.
local function GradientRows(grid, key, collect, note)
    local function Read()
        local grad = DB()[key]
        return type(grad) == "table" and grad or nil
    end
    local function Write(field, value)
        if type(DB()[key]) ~= "table" then DB()[key] = {} end
        DB()[key][field] = value
    end
    local function Field(field, fallback)
        return function()
            local grad = Read()
            if not grad then return fallback end
            local value = grad[field]
            if value == nil then return fallback end
            return value
        end
    end

    local rows = {}

    UI.Toggle(grid:FullRow("Gradient", { controlWidth = 124, sublabel = note }),
        Field("on", false),
        function(value)
            Write("on", value)
            Apply()
        end)

    rows[#rows + 1] = UI.Swatch(
        grid:FullRow("Second colour", { controlWidth = 124 }),
        function()
            local colour = Field("color", { 1, 1, 1 })()
            return colour[1], colour[2], colour[3]
        end,
        function(r, g, b) Write("color", { r, g, b }) end,
        Apply)

    rows[#rows + 1] = UI.Dropdown(
        grid:FullRow("Runs", { controlWidth = 150 }),
        ns.GRADIENT_DIRECTIONS, Field("direction", "right"),
        function(value) Write("direction", value) end, { apply = Apply })

    collect[#collect + 1] = { on = Field("on", false), rows = rows }
end

-- Recomputed from scratch every refresh, never read back off dkSkip: a flag
-- left over from the last pass is how a row hidden once stays hidden for the
-- rest of the session.
local function ApplyGradientVisibility(groups)
    for _, group in ipairs(groups) do
        local shown = group.on() and true or false
        for _, row in ipairs(group.rows) do
            row.dkSkip = not shown
            row:SetShown(shown)
        end
    end
end

---------------------------------------------------------------------------
-- Look
---------------------------------------------------------------------------
function OptionsCoTanks:BuildLook(grid)
    local gradients = {}

    grid:Tab("Look")
    grid:Section("Health bar")

    UI.MediaPicker(grid:FullRow("Texture",
        { controlWidth = 190, icon = "media-texture" }), "statusbar",
        Get("healthTexture"), function(value) DB().healthTexture = value end,
        Apply)

    UI.Dropdown(grid:FullRow("Colour", { controlWidth = 150 }), {
        { value = "class",  text = "By class" },
        { value = "custom", text = "One colour" },
        { value = "health", text = "By remaining health" },
    }, Get("healthColor"), function(value) DB().healthColor = value end,
        { apply = Apply })

    -- SHOWN ONLY WHEN THE MODE USES IT. A colour picker sitting under
    -- "By class" is a control that does nothing, which is the one thing this
    -- panel is not allowed to have.
    local customRow = Colour(grid, "Custom colour", "healthCustom")
    GradientRows(grid, "healthGradient", gradients)
    Slide(grid, "Opacity", "healthAlpha", 0, 1, 0.05,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end, 100)
    Slide(grid, "Empty part", "trackAlpha", 0, 0.6, 0.02,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end, 100,
        "The bar's own colour, faint, behind the fill")

    UI.Dropdown(grid:FullRow("Runs", { controlWidth = 150 }),
        ns.FILL_DIRECTIONS,
        function()
            if DB().healthVertical then
                return DB().healthReverse and "down" or "up"
            end
            return DB().healthReverse and "left" or "right"
        end,
        function(value)
            local entry = ns.Layout.FillDirection(value)
            DB().healthVertical = entry.orientation == "VERTICAL"
            DB().healthReverse = entry.reverse
        end, { apply = Apply })

    grid:Note("\"By remaining health\" needs numbers this client will let an "
        .. "addon read. On this patch another player's health can arrive "
        .. "protected mid-fight, and then it falls back to the class colour "
        .. "rather than freezing on the last one it could work out. The BAR is "
        .. "always right either way - it is handed the number without reading "
        .. "it, which is the whole trick.")

    -- Same for the three-colour ramp: it is the whole of one mode and nothing
    -- at all in the other two, so it goes away rather than sitting folded
    -- shut and inert.
    local rampRows = {
        grid:Section("Colour by health", "ct-ramp"),
        Colour(grid, "Full", "healthHigh"),
        Colour(grid, "Half", "healthMid"),
        Colour(grid, "Nearly dead", "healthLow"),
    }

    -- "Plate" was a word from the bar code that means nothing on a unit
    -- frame - the owner asked what it was, which is the answer. It is the
    -- surface the bar is drawn on, seen wherever the bar is not.
    grid:Section("Behind the bar", "ct-plate")
    grid:Note("The surface the health bar sits on. You see it wherever the "
        .. "bar is not - the empty end of it, and the gap the border leaves.")
    Colour(grid, "Colour", "bgColor")
    GradientRows(grid, "bgGradient", gradients)
    Slide(grid, "Opacity", "bgAlpha", 0, 1, 0.05,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end, 100)

    grid:Section("Border", "ct-border")
    Slide(grid, "Thickness", "borderSize", 0, 4, 1)
    Colour(grid, "Colour", "borderColor")
    GradientRows(grid, "borderGradient", gradients,
        "Only the one-pixel line - an edge texture takes a single colour")
    UI.MediaPicker(grid:FullRow("Texture",
        { controlWidth = 190, icon = "media-border" }), "border",
        Get("borderTexture"), function(value) DB().borderTexture = value end,
        Apply)

    grid:Section("Shields", "ct-absorb")
    grid:Note("Two different things, both drawn over the health bar rather "
        .. "than beside it. A SHIELD is damage they can take before they lose "
        .. "any health, so it sits past the end of the fill. HEALING BLOCKED "
        .. "is the opposite - a debuff that eats incoming heals until it is "
        .. "used up, so it sits inside the fill, at the end that would be "
        .. "healed first. Necrotic Wound and Mortal Wounds are the ones you "
        .. "will see it from.")

    Switch(grid, "Shield", "absorbShow", "Damage they can take for free")
    Colour(grid, "Shield colour", "absorbColor")
    Slide(grid, "Shield opacity", "absorbAlpha", 0, 1, 0.05,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end, 100)
    UI.MediaPicker(grid:FullRow("Shield texture",
        { controlWidth = 190, icon = "media-texture" }), "statusbar",
        Get("absorbTexture"), function(v) DB().absorbTexture = v end, Apply)

    Switch(grid, "Healing blocked", "healAbsorbShow",
        "A debuff that eats their incoming heals")
    Colour(grid, "Its colour", "healAbsorbColor")
    Slide(grid, "Its opacity", "healAbsorbAlpha", 0, 1, 0.05,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end, 100)
    UI.MediaPicker(grid:FullRow("Its texture",
        { controlWidth = 190, icon = "media-texture" }), "statusbar",
        Get("healAbsorbTexture"),
        function(v) DB().healAbsorbTexture = v end, Apply)

    grid:Note("Leave a texture empty and it wears the health bar's. Picking a "
        .. "different one is the point though: a shield drawn in the same "
        .. "material as the health under it reads as more health, which is "
        .. "the one thing it must not do.")

    self.lookGradients = gradients
    grid.widgets[#grid.widgets + 1] = {
        Refresh = function()
            ApplyGradientVisibility(gradients)

            -- Recomputed from the mode every pass, never read back off
            -- dkSkip: a flag left over from the last refresh is how a row
            -- hidden once stays hidden for the rest of the session.
            local mode = DB().healthColor
            customRow.dkSkip = mode ~= "custom"
            customRow:SetShown(mode == "custom")
            for _, row in ipairs(rampRows) do
                row.dkSkip = mode ~= "health"
                row:SetShown(mode == "health")
            end
        end,
    }
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------

-- Both texts get THE SAME SEVEN CONTROLS, generated rather than written out
-- twice. "The name can be moved but the health cannot" is exactly the kind of
-- arbitrary limit that sends people looking for another addon, and it is
-- always the result of a second copy that nobody finished.
local function TextSection(grid, key, label)
    local function El() return DB()[key] end
    local function ElSet(field)
        return function(value) El()[field] = value; Apply() end
    end
    local function ElGet(field, fallback)
        return function()
            local value = El()[field]
            if value == nil then return fallback end
            return value
        end
    end

    grid:Section(label, "ct-text-" .. key)

    UI.Toggle(grid:FullRow("Show", { controlWidth = 124 }),
        ElGet("show", true), ElSet("show"))

    UI.MediaPicker(grid:FullRow("Font",
        { controlWidth = 190, icon = "media-font" }), "font",
        ElGet("font", ""), ElSet("font"), Apply)

    UI.Slider(grid:FullRow("Size", { controlWidth = 124 }), {
        get = ElGet("size", 0), set = function(v) El().size = v end,
        min = 0, max = 32, step = 1, apply = Apply,
        format = function(v)
            if v <= 0 then return "auto" end
            return string.format("%d", v)
        end,
    })

    UI.Swatch(grid:FullRow("Colour", { controlWidth = 124 }),
        function()
            local colour = El().color or { 1, 1, 1 }
            return colour[1], colour[2], colour[3]
        end,
        function(r, g, b) El().color = { r, g, b } end, Apply)

    UI.Toggle(grid:FullRow("Class colour", {
        controlWidth = 124,
        sublabel = "Wins over the colour above",
    }), ElGet("classColor", false), ElSet("classColor"))

    UI.Dropdown(grid:FullRow("Outline", { controlWidth = 150 }),
        ns.Media.OUTLINES, ElGet("outline", "OUTLINE"), ElSet("outline"),
        { apply = Apply })

    UI.Dropdown(grid:FullRow("Position", { controlWidth = 150 }),
        TEXT_ANCHORS, ElGet("anchor", "LEFT"), ElSet("anchor"), { apply = Apply })

    UI.Slider(grid:FullRow("Nudge across", { controlWidth = 124 }), {
        get = ElGet("x", 0), set = function(v) El().x = v end,
        min = -40, max = 40, step = 1, apply = Apply,
    })
    UI.Slider(grid:FullRow("Nudge up", { controlWidth = 124 }), {
        get = ElGet("y", 0), set = function(v) El().y = v end,
        min = -40, max = 40, step = 1, apply = Apply,
    })
end

function OptionsCoTanks:BuildText(grid)
    grid:Tab("Text")

    TextSection(grid, "name", "Name")
    UI.Slider(grid:FullRow("Cut the name to", { controlWidth = 124 }), {
        get = function() return DB().name.maxLength or 0 end,
        set = function(value) DB().name.maxLength = value end,
        min = 0, max = 12, step = 1, apply = Apply,
        format = function(v)
            if v <= 0 then return "whole name" end
            return string.format("%d letters", v)
        end,
    })

    TextSection(grid, "health", "Health")
    UI.Dropdown(grid:FullRow("Shows", { controlWidth = 150 }), {
        { value = "percent", text = "Percent" },
        { value = "current", text = "How much is left" },
        { value = "both",    text = "Both" },
        { value = "deficit", text = "How much is missing" },
    }, function() return DB().health.format end,
        function(value) DB().health.format = value end, { apply = Apply })

    grid:Note("On this patch another player's health can arrive as a protected "
        .. "number that no addon may do arithmetic on. When that happens the "
        .. "text goes BLANK rather than printing a zero - a row that reads 0% "
        .. "because the number could not be read is worse than one that says "
        .. "nothing. The bar itself keeps working throughout.")
end

---------------------------------------------------------------------------
-- Auras
---------------------------------------------------------------------------
local function StripSection(grid, key, label, note)
    local function El() return DB()[key] end
    local function ElGet(field, fallback)
        return function()
            local value = El()[field]
            if value == nil then return fallback end
            return value
        end
    end
    local function ElSet(field)
        return function(value) El()[field] = value; Apply() end
    end

    grid:Section(label, "ct-strip-" .. key)
    if note then grid:Note(note) end

    UI.Toggle(grid:FullRow("Show", { controlWidth = 124 }),
        ElGet("show", true), ElSet("show"))

    UI.Slider(grid:FullRow("How many", { controlWidth = 124 }), {
        get = ElGet("max", 8), set = function(v) El().max = v end,
        min = 0, max = 20, step = 1, apply = Apply,
    })
    UI.Slider(grid:FullRow("Icon size", { controlWidth = 124 }), {
        get = ElGet("size", 22), set = function(v) El().size = v end,
        min = 8, max = 48, step = 1, apply = Apply,
    })
    UI.Slider(grid:FullRow("Spacing", { controlWidth = 124 }), {
        get = ElGet("spacing", 1), set = function(v) El().spacing = v end,
        min = 0, max = 12, step = 1, apply = Apply,
    })
    UI.Slider(grid:FullRow("Per row", { controlWidth = 124 }), {
        get = ElGet("perRow", 8), set = function(v) El().perRow = v end,
        min = 1, max = 20, step = 1, apply = Apply,
    })

    UI.Dropdown(grid:FullRow("Corner", { controlWidth = 150 }), {
        { value = "TOPLEFT",     text = "Top left" },
        { value = "TOPRIGHT",    text = "Top right" },
        { value = "BOTTOMLEFT",  text = "Bottom left" },
        { value = "BOTTOMRIGHT", text = "Bottom right" },
    }, ElGet("anchor", "BOTTOMLEFT"), ElSet("anchor"), { apply = Apply })

    UI.Dropdown(grid:FullRow("Grows", { controlWidth = 150 }), {
        { value = "right", text = "To the right", icon = "dir-left-right" },
        { value = "left",  text = "To the left",  icon = "dir-right-left" },
    }, ElGet("growth", "right"), ElSet("growth"), { apply = Apply })

    UI.Slider(grid:FullRow("Nudge across", { controlWidth = 124 }), {
        get = ElGet("x", 0), set = function(v) El().x = v end,
        min = -60, max = 60, step = 1, apply = Apply,
    })
    UI.Slider(grid:FullRow("Nudge up", { controlWidth = 124 }), {
        get = ElGet("y", 0), set = function(v) El().y = v end,
        min = -60, max = 60, step = 1, apply = Apply,
    })

    UI.Slider(grid:FullRow("Border", { controlWidth = 124 }), {
        get = ElGet("borderSize", 1), set = function(v) El().borderSize = v end,
        min = 0, max = 4, step = 1, apply = Apply,
    })
    UI.Swatch(grid:FullRow("Border colour", { controlWidth = 124 }),
        function()
            local colour = El().borderColor or { 0, 0, 0 }
            return colour[1], colour[2], colour[3]
        end,
        function(r, g, b) El().borderColor = { r, g, b } end, Apply)

    -- THE TWO NUMBERS ON AN ICON get the same pair the name and the health
    -- text get. They were the only text this addon draws with no way to
    -- choose its face - hard-coded to the shared bar font in one renderer and
    -- to the WINDOW'S font in the other, which is how the same two numbers
    -- ended up in two typefaces depending on the patch.
    UI.MediaPicker(grid:FullRow("Number font",
        { controlWidth = 190, icon = "media-font" }), "font",
        ElGet("font", ""), ElSet("font"), Apply)

    UI.Dropdown(grid:FullRow("Number outline", { controlWidth = 150 }),
        ns.Media.OUTLINES, ElGet("outline", "OUTLINE"), ElSet("outline"),
        { apply = Apply })

    UI.Toggle(grid:FullRow("Countdown", { controlWidth = 124 }),
        ElGet("countdown", true), ElSet("countdown"))
    UI.Slider(grid:FullRow("Countdown size", { controlWidth = 124 }), {
        get = ElGet("countdownSize", 0),
        set = function(v) El().countdownSize = v end,
        min = 0, max = 24, step = 1, apply = Apply,
        format = function(v)
            if v <= 0 then return "auto" end
            return string.format("%d", v)
        end,
    })
    UI.Toggle(grid:FullRow("Stacks", { controlWidth = 124 }),
        ElGet("stacks", true), ElSet("stacks"))
    UI.Slider(grid:FullRow("Stack size", { controlWidth = 124 }), {
        get = ElGet("stacksSize", 0),
        set = function(v) El().stacksSize = v end,
        min = 0, max = 24, step = 1, apply = Apply,
        format = function(v)
            if v <= 0 then return "auto" end
            return string.format("%d", v)
        end,
    })
end

function OptionsCoTanks:BuildAuras(grid)
    grid:Tab("Auras")

    -- THE NOTE THAT MUST NOT BE SOFTENED. Live aura strips need patch 12.1,
    -- and a page that let the user set fourteen things and then showed them
    -- nothing, with no explanation, is the exact defect this addon spent a
    -- whole session removing. The reason is asked of the engine rather than
    -- written here, so it names the actual client build.
    local reason = grid:Note("")
    reason.Refresh = function()
        local why = ns.CoTanks:AuraReason()
        if why then
            reason:SetText("|cffffd100Live auras need patch 12.1.|r An aura on "
                .. "another player is a protected value on this client - no "
                .. "addon may read its icon, its stacks or its time left, and "
                .. "there is no way round that. Blizzard's own aura engine can, "
                .. "and it arrives with 12.1; this addon already speaks to it "
                .. "and will simply start working. Until then the strips draw "
                .. "in |cffffd100test mode|r, so everything below can be set up "
                .. "now and will be right the moment the patch lands.\n\n"
                .. "|cff888888" .. why .. "|r")
        else
            reason:SetText("Your client has Blizzard's aura engine, so these "
                .. "strips show real auras on the real tanks.")
        end
    end
    grid.widgets[#grid.widgets + 1] = reason

    StripSection(grid, "debuffs", "Debuffs",
        "What is on them - the boss's stacking debuff, the thing you swap on.")
    -- "Player buffs" is what the game calls these and what the owner asked for.
    -- "Their own buffs" was mine, and it made a reader work out which of the
    -- two strips they were looking at from a possessive pronoun.
    StripSection(grid, "buffs", "Player buffs",
        "Their cooldowns, so you can see whether the other tank still has one.")
end

---------------------------------------------------------------------------
-- Rules
---------------------------------------------------------------------------
function OptionsCoTanks:BuildRules(grid)
    grid:Tab("Rules")
    grid:Section("Who appears")

    Switch(grid, "Include yourself", "includeSelf",
        "Your own frame is already on your screen")
    Slide(grid, "At most", "maxRows", 1, 8, 1,
        function(v) return string.format("%d rows", v) end)

    UI.Dropdown(grid:FullRow("Order", { controlWidth = 150 }), {
        { value = "group",  text = "Raid order" },
        { value = "name",   text = "By name" },
        { value = "health", text = "Lowest first" },
    }, Get("sortBy"), function(value) DB().sortBy = value end, { apply = Repaint })

    UI.Dropdown(grid:FullRow("Stack grows", { controlWidth = 150 }),
        ns.GROW_Y, Get("growth"), function(value) DB().growth = value end,
        { apply = Apply })

    grid:Note("\"Lowest first\" needs health numbers this client will let an "
        .. "addon compare. When it will not, the raid order stands - which is "
        .. "the order it was in a moment ago, so the rows do not shuffle under "
        .. "your eye mid-pull.")

    grid:Section("When it appears")
    Switch(grid, "Only in a group", "onlyInGroup")
    Switch(grid, "Only in a dungeon or raid", "onlyInInstance")

    -- THE MARKS, GENERATED. Every one gets the same five controls, walked off
    -- ns.COTANK_INDICATORS rather than typed out four times - which is what
    -- stops the fourth one shipping with three of them. The owner asked for
    -- exactly this: "ich muss die raid marker, leader, in fight etc. icons
    -- einstellen koennen. also alles was dazu gehoert."
    for _, entry in ipairs(ns.COTANK_INDICATORS) do
        local function El() return DB()[entry.key] end
        local function ElGet(field, fallback)
            return function()
                local value = El()[field]
                if value == nil then return fallback end
                return value
            end
        end
        local function ElSet(field)
            return function(value) El()[field] = value; Apply() end
        end

        grid:Section(entry.label, "ct-mark-" .. entry.key)
        if entry.note then grid:Note(entry.note) end

        UI.Toggle(grid:FullRow("Show", { controlWidth = 124 }),
            ElGet("show", true), ElSet("show"))
        UI.Slider(grid:FullRow("Size", { controlWidth = 124 }), {
            get = ElGet("size", 14), set = function(v) El().size = v end,
            min = 6, max = 40, step = 1, apply = Apply,
        })
        UI.Dropdown(grid:FullRow("Position", { controlWidth = 150 }),
            TEXT_ANCHORS, ElGet("anchor", "LEFT"), ElSet("anchor"),
            { apply = Apply })
        UI.Slider(grid:FullRow("Nudge across", { controlWidth = 124 }), {
            get = ElGet("x", 0), set = function(v) El().x = v end,
            min = -60, max = 60, step = 1, apply = Apply,
        })
        UI.Slider(grid:FullRow("Nudge up", { controlWidth = 124 }), {
            get = ElGet("y", 0), set = function(v) El().y = v end,
            min = -60, max = 60, step = 1, apply = Apply,
        })
    end

    -- NOT A RING. It is drawn exactly like the border above, which is what
    -- the owner said, and calling it a ring sent people looking for a circle.
    grid:Section("Target border", "ct-target")
    grid:Note("A second border on the tank you currently have targeted, so "
        .. "you can see at a glance whether you are about to taunt the right "
        .. "one.")
    UI.Toggle(grid:FullRow("Show", { controlWidth = 124 }),
        function() return DB().targetBorder.show end,
        function(value) DB().targetBorder.show = value; Apply() end)
    UI.Slider(grid:FullRow("Thickness", { controlWidth = 124 }), {
        get = function() return DB().targetBorder.size end,
        set = function(value) DB().targetBorder.size = value end,
        min = 1, max = 6, step = 1, apply = Apply,
    })
    UI.Swatch(grid:FullRow("Colour", { controlWidth = 124 }),
        function()
            local colour = DB().targetBorder.color
            return colour[1], colour[2], colour[3]
        end,
        function(r, g, b) DB().targetBorder.color = { r, g, b } end, Apply)

    grid:Section("Fading", "ct-fade")
    Switch(grid, "Fade out of range", "rangeFade")
    Slide(grid, "Out of range", "rangeAlpha", 0.1, 1, 0.05,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end, 100)
    Slide(grid, "Dead", "deadFade", 0.1, 1, 0.05,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end, 100)
    Slide(grid, "Disconnected", "offlineFade", 0.1, 1, 0.05,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end, 100)

    grid:Note("One alpha for the whole row, decided by the worst thing true "
        .. "about it. Multiplying the three together made a dead, disconnected "
        .. "tank who is out of range invisible - which is precisely the moment "
        .. "you want to see that there is one.")
end
