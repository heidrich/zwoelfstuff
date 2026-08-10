---------------------------------------------------------------------------
-- OptionsAnswers.lua - the Answering page.
--
-- The mirror of the externals page, and it says so: that one is "what the
-- group can cast on me", this one is "what I can be asked for". Same shape,
-- same words, because they are one idea seen from both ends.
---------------------------------------------------------------------------
local _, ns = ...

local UI = ns.UI
local C = UI.C

local Page = {}
ns.OptionsAnswers = Page

local function Cfg() return ns.Answers.Config() end
local function Apply() ns.Answers.Rebuild() end

function Page:BuildPage(page, width)
    local grid = UI.Page(page, width, { tooltipNotes = true })

    ---------------------------------------------------------------------
    -- What this is, before any switch
    --
    -- Two sentences that are LIMITS rather than features, and they belong at
    -- the top: somebody who reads them and stops has lost nothing, and
    -- somebody who does not read them would otherwise find out mid-pull.
    ---------------------------------------------------------------------
    grid:Section("What this is")

    grid:Note("A tank in your group presses \"ask\" on one of your cooldowns. "
        .. "Here, the cell for that spell |cffffd100on that tank|r lights up, "
        .. "and clicking it casts. Your own taunt works the same way when the "
        .. "other tank asks for a swap.")

    grid:Note("|cffff8040Two things this cannot do, and both are the game "
        .. "rather than the addon:|r\n\n"
        .. "|cffffd100Only people who also run ZwoelfStuff|r can light up "
        .. "your bar. The chat line still reaches everybody else, so nothing "
        .. "is lost - they just have to read it.\n\n"
        .. "|cffffd100The addon never casts.|r You press the cell and the "
        .. "GAME casts. That is also why the bar stands there permanently and "
        .. "only brightens: which spell a cell casts, and on whom, is written "
        .. "while you are out of combat, and the game does not allow it to be "
        .. "rewritten during a fight.")

    ---------------------------------------------------------------------
    -- The switch
    ---------------------------------------------------------------------
    grid:Section("Switch it on")

    UI.Toggle(grid:FullRow("Show the bar", {
        controlWidth = 124,
        sublabel = "A cell for each of your cooldowns, on each tank",
    }), function() return Cfg().enabled and true or false end,
        function(value) Cfg().enabled = value and true or false; Apply() end)

    grid:Note("Off, a request still reaches you - it is printed once, with "
        .. "this switch named - but there is no button to press. The bar is "
        .. "off to begin with because something appearing on your screen "
        .. "after an update is worse than something you have not found yet.")

    ---------------------------------------------------------------------
    -- What you offer
    ---------------------------------------------------------------------
    grid:Section("What you can be asked for")

    local _, class = UnitClass("player")
    local mine = ns.Answers.Offers(class)

    if #mine == 0 then
        grid:Note("|cff888888Your class has nothing on the externals list and "
            .. "no taunt, so there is nothing here to offer. The bar stays "
            .. "away.|r")
    end

    for _, offer in ipairs(mine) do
        local spellID = offer.spellID
        local row = grid:FullRow("", { controlWidth = 124 })
        UI.Toggle(row,
            function() return ns.Answers.Offering(spellID) end,
            function(value) ns.Answers.SetOffering(spellID, value) end)

        local paint = row.Refresh
        row.Refresh = function()
            if paint then paint() end
            UI.MakeRowASpell(row, spellID)
            row.label:SetText(ns.SpellName(spellID) or ("Spell " .. spellID))
        end
    end

    grid:Note("Switch one off and no cell is built for it - you will not be "
        .. "asked, and nothing lights up. A spell you have never touched is "
        .. "ON, because a bar that is empty until you find a settings page is "
        .. "a bar that does not work.")

    ---------------------------------------------------------------------
    -- The bar
    ---------------------------------------------------------------------
    grid:Section("The bar")

    UI.Slider(grid:Row("Cell size"), {
        get = function() return Cfg().size end,
        set = function(value) Cfg().size = value end,
        min = 24, max = 64, step = 2, apply = Apply,
    })

    UI.Slider(grid:Row("Spacing"), {
        get = function() return Cfg().gap end,
        set = function(value) Cfg().gap = value end,
        min = 0, max = 16, step = 1, apply = Apply,
    })

    local function Percent(v)
        return string.format("%d%%", math.floor((v or 0) * 100 + 0.5))
    end

    UI.Slider(grid:Row("Resting opacity"), {
        get = function() return Cfg().idleAlpha end,
        set = function(value) Cfg().idleAlpha = value end,
        min = 0.1, max = 1, step = 0.05, format = Percent, scale = 100,
        apply = function() ns.Answers.Repaint() end,
    })
    grid:Note("How the bar looks with nobody asking. It cannot be hidden "
        .. "outright - a cell that appears mid-fight is exactly what the game "
        .. "forbids - but it can sit quietly until it is wanted. It still "
        .. "casts when you click it, which makes it a quick-cast bar for your "
        .. "tank's cooldowns whether anybody asked or not.")

    UI.Slider(grid:Row("How long it shouts"), {
        get = function() return Cfg().linger end,
        set = function(value) Cfg().linger = value end,
        min = 3, max = 20, step = 1,
        format = function(v) return string.format("%ds", v or 0) end,
        apply = function() ns.Answers.Repaint() end,
    })
    grid:Note("A request nobody answered stops shouting after this. It is not "
        .. "cancelled - the person who asked has moved on either way.")

    UI.Toggle(grid:Row("A sound when somebody asks"),
        function() return Cfg().sound ~= false end,
        function(value) Cfg().sound = value and true or false end)

    UI.Toggle(grid:Row("Only in dungeons and raids"),
        function() return Cfg().onlyInInstance and true or false end,
        function(value)
            Cfg().onlyInInstance = value and true or false
            Apply()
        end)

    ---------------------------------------------------------------------
    -- The look, in the bar's own words
    ---------------------------------------------------------------------
    local function Slide(label, key, min, max, step, format, scale)
        UI.Slider(grid:Row(label), {
            get = function() return Cfg()[key] end,
            set = function(value) Cfg()[key] = value end,
            min = min, max = max, step = step,
            format = format, scale = scale, apply = Apply,
        })
    end

    grid:Section("Look")

    Slide("Scale", "scale", 0.5, 2, 0.05, Percent, 100)
    Slide("Icon zoom", "iconZoom", 0, 0.2, 0.01, Percent, 100)

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

    grid:Section("Backdrop")

    UI.Toggle(grid:Row("Show"),
        function() return Cfg().backdrop ~= false end,
        function(value) Cfg().backdrop = value and true or false; Apply() end)

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

    grid:Buttons({
        { text = "Move the bar", width = 150, style = "primary",
          onClick = function() ns.EditMode:SetUnlocked(true, "bars") end },
        { text = "What could be asked of me", width = 210,
          onClick = function() ns.Answers:Dump() end },
    }, 14)

    grid:Layout()
    page.Refresh = function() grid:Refresh() end
end
