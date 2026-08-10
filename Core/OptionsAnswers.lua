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
    -- WHO GETS A ROW
    --
    -- Owner, 2026-08-10: "man kann keine spieler auswaehlen, oder einstellen
    -- also targets". There was no answer to that at all - the tanks were
    -- picked for you and that was the whole of it, which is right until the
    -- group has not set its roles, and then it is an empty bar with no
    -- explanation. Directly under the switch, because "is it on" and "who is
    -- it for" are the same minute's decision.
    ---------------------------------------------------------------------
    grid:Section("Who you answer")

    local whoHost = CreateFrame("Frame", nil, grid.content)
    local whoChips = UI.ChipRow(whoHost, width - 40, {
        chips = {
            { key = ns.Answers.WHO_TANKS,  text = "The tanks" },
            { key = ns.Answers.WHO_GROUP,  text = "Everybody" },
            { key = ns.Answers.WHO_CHOSEN, text = "People I pick" },
        },
        isOn = function(key)
            return (Cfg().who or ns.Answers.WHO_TANKS) == key
        end,
        onSelect = function(key)
            Cfg().who = key
            Apply()
            ns.Options:Refresh()
        end,
    })
    whoChips:SetPoint("TOPLEFT", whoHost, "TOPLEFT", 0, 0)
    whoHost:SetHeight(whoChips:GetHeight())
    grid:Wide(whoHost, whoChips:GetHeight(), 4, 8)
    whoHost.Refresh = function() whoChips.Refresh() end
    grid.widgets[#grid.widgets + 1] = whoHost

    grid:Note("One row of cells per person. |cffffd100The tanks|r is whoever "
        .. "the group has marked as tanking - nothing to set up, and empty in "
        .. "a group that never assigned roles. |cffffd100Everybody|r is the "
        .. "answer to that. |cffffd100People I pick|r names them yourself, in "
        .. "the order the rows should be.")

    UI.Slider(grid:Row("Rows"), {
        get = function() return ns.Answers.Rows(Cfg()) end,
        set = function(value) Cfg().rows = value end,
        min = 1, max = ns.Answers.MAX_ROWS, step = 1, apply = function()
            Apply()
            ns.Options:Refresh()
        end,
    })

    -- ONE DROPDOWN PER ROW, the same shape the externals page uses for "who
    -- to ask" - and out of the layout entirely while the mode does not use
    -- them, rather than sitting there greyed out.
    for index = 1, ns.Answers.MAX_ROWS do
        local row = grid:FullRow("Row " .. index, { controlWidth = 220 })

        UI.Dropdown(row, function()
            local items = { { value = "", text = "Nobody" } }
            for _, member in ipairs(ns.Roster()) do
                if not member.isPlayer then
                    items[#items + 1] = { value = member.name,
                        text = member.name }
                end
            end
            return items
        end, function()
            return Cfg().rowNames[index] or ""
        end, function(value)
            Cfg().rowNames[index] = (value ~= "" and value) or nil
            Apply()
        end, { emptyText = "Nobody" })

        local paintControl = row.Refresh
        row.Refresh = function()
            if paintControl then paintControl() end
            row:SetRelevant(Cfg().who == ns.Answers.WHO_CHOSEN
                and index <= ns.Answers.Rows(Cfg()))
        end
    end

    ---------------------------------------------------------------------
    -- What you offer
    ---------------------------------------------------------------------
    grid:Section("What you can be asked for")

    local _, class = UnitClass("player")
    local mine = ns.Answers.Offers(class, nil, ns.KnowsSpell)

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
        .. "a bar that does not work. Only what you can actually cast is "
        .. "listed: your class's spells for another spec are not offered, "
        .. "because a cell that casts nothing is worse than no cell.")

    ---------------------------------------------------------------------
    -- WHAT PRESSING ONE DOES
    ---------------------------------------------------------------------
    grid:Section("When you press one")

    UI.Toggle(grid:FullRow("Take them as your target too", {
        controlWidth = 124,
        sublabel = "The cast does not need it",
    }), function() return Cfg().target and true or false end,
        function(value) Cfg().target = value and true or false; Apply() end)

    grid:Note("The cell casts |cffffd100on|r whoever asked without touching "
        .. "your target - which is the point, a healer keeps healing whoever "
        .. "they were healing. Switch this on and it takes the target as "
        .. "well.\n\nA |cffffd100taunt|r cell is different, because a taunt "
        .. "request means take the boss: it casts on |cffffd100what that tank "
        .. "is fighting|r, and if that cannot be taunted, on your own target. "
        .. "With the switch on you end up on the creature, which after a swap "
        .. "is where you want to be.")

    ---------------------------------------------------------------------
    -- Keys, beside the thing they press rather than in the game's menu.
    ---------------------------------------------------------------------
    grid:Section("Keys")

    grid:Note("Counted the way the bar is drawn: along the first row, then "
        .. "the next. The key shows in the corner of the cell.\n\nA key here "
        .. "does not cast by itself - it presses the cell, and the cell casts. "
        .. "That is the only way a key can reach a spell at all, and it is why "
        .. "these are the game's own bindings rather than something this addon "
        .. "invented.")

    for index = 1, ns.Answers.KEYS do
        local row = grid:FullRow("Cell " .. index, { controlWidth = 130 })
        UI.KeyBind(row, {
            binding = ns.Answers.BindingName(index),
            label = "Answer cell " .. index,
        })
    end

    grid:Note("Click one, press the key. Right-click clears it. They are also "
        .. "under Escape, Key Bindings, |cffffd100ZwoelfStuff|r.")

    UI.Toggle(grid:FullRow("A quick menu on the bar", {
        controlWidth = 124,
        sublabel = "Appears when the mouse is over it",
    }), function() return Cfg().quickMenu ~= false end,
        function(value) Cfg().quickMenu = value and true or false; Apply() end)

    grid:Note("A small button above the bar that opens |cffffd100who you "
        .. "answer|r where you are already looking - the group forms, somebody "
        .. "picks up a second tank, and this settings window is on the other "
        .. "side of the screen.")

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
        -- The report, and it is worth finding: it prints the macro each cell
        -- would run, which is the one thing that says whether this works.
        { text = "What every cell would cast", width = 220,
          onClick = function() ns.Answers:Dump() end },
    }, 14)

    grid:Layout()
    page.Refresh = function() grid:Refresh() end
end
