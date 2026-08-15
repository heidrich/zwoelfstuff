---------------------------------------------------------------------------
-- OptionsCooldowns.lua - the Cooldowns page
--
-- THE SHAPE IS THE ONE THIS ADDON ALREADY HAS, and that is the whole point.
-- The owner asked for it out loud on the raid bar - "das bewaehrte layout wo
-- ich mir die bar zusammen stellen kann" - and the externals panel, the raid
-- bar and the answer bar all wear it: the lattice in a sticky band at the
-- top, the list you pick from in the third column, the settings under it.
--
-- The page this replaces was 2 710 lines on ONE page. Owner, 2026-08-15:
-- that was the defect, not the number of knobs. So the knobs come back in
-- folding sections, one subject each, and the two that answer "what is on
-- this bar" are not settings at all - they are the preview and the picker.
--
-- WHAT IS DELIBERATELY NOT HERE YET: the per-cell overrides (one icon in a
-- row twice the size, one cell a bar among icons) and the free-form puzzle
-- layout. Both are `cellOpts`, both need a drag surface of their own, and
-- both are named in Store.READERS under the wave that owns them. A page that
-- offered them and did nothing would be worse than a page that does not.
---------------------------------------------------------------------------
local _, ns = ...

local UI = ns.UI
local C = UI.C

local Page = {}
ns.OptionsCooldowns = Page

-- HOW SMALL A SLOT MAY GET BEFORE YOU CANNOT AIM AT IT, and how much of the
-- window the band may take. Both are about the PAGE rather than about the
-- bar - the size itself is asked of the bar every time it is drawn.
--
-- The lesson behind that sentence cost a release on the raid bar: a copied
-- `SLOT = 40` drew every button half again too big over a bar that is 26.
-- A preview that does not agree with the screen is worse than none.
local MIN_SLOT = 20
local BAND_MAX_H = 190

-- Which bar is being edited, and which of its cells is waiting for a spell.
-- On the module rather than local, so the self test can drive the page the
-- way a user does.
Page.barID = nil
Page.cell = nil

local function Store() return ns.Cooldowns and ns.Cooldowns.Store end
local function Bars() return ns.Cooldowns and ns.Cooldowns.Bars end

-- THE BAR BEING EDITED, and it answers for a profile that has changed under
-- it. A stored id outlives a deleted bar, and every reader here would
-- otherwise be a nil index on the first click after a delete.
function Page.Current()
    local store = Store()
    if not store then return nil end

    local bar = Page.barID and store.ByID(Page.barID) or nil
    if bar then return bar end

    -- Fall to the first one there is, so the page always has something to
    -- draw rather than an empty band with no way back.
    for _, first in pairs(store.Bars()) do
        if type(first) == "table" and first.id then
            Page.barID = first.id
            return first
        end
    end

    Page.barID = nil
    return nil
end

local function Refresh()
    if ns.Cooldowns and ns.Cooldowns.Render then
        ns.Cooldowns.Render.Refresh()
    end
    ns.Options:Refresh()
end

-- WHAT ONE PREVIEW SLOT IS DRAWN AT. Read off the bar, never a constant of
-- this file's own - see the note at MIN_SLOT.
--
-- A bar-shaped bar previews as its own rectangle, so its "slot" is as wide as
-- barWidth and as tall as barHeight, scaled down together if the band cannot
-- hold it. Squares for a bar a quarter of the screen wide is exactly the
-- picture the old renderer's header warns about, and a preview that lies that
-- way is how somebody spends an evening on a setting that was never wrong.
function Page.PreviewGeometry(width)
    local store, bar = Store(), Page.Current()
    if not (store and bar) then return 40, 4, 40 end

    local opts = store.Lattice(bar)
    local rows = math.max(1, math.ceil(
        math.max(1, store.Capacity(bar)) / math.max(1, opts.columns or 1)))
    local gap = math.max(0, opts.spacing or 4)

    local wanted = opts.width or opts.size or 40
    local size = UI.PreviewSize(wanted, rows, opts.columns or 1,
        width - 28, BAND_MAX_H, gap, MIN_SLOT)

    -- The height follows the width by the SAME ratio, so a 250x24 bar
    -- previews as a 250x24 bar and not as a 250 square.
    local ratio = (wanted > 0) and (size / wanted) or 1
    local height = math.max(MIN_SLOT, math.floor((opts.size or 40) * ratio))
    return size, gap, height
end

---------------------------------------------------------------------------
-- The band: what is actually on this bar
---------------------------------------------------------------------------
local function BuildBand(grid, width)
    local L = ns.L
    local band = grid.sticky
    UI.Fill(band, "BACKGROUND", C.windowBg)

    local BAND_HEAD = 32

    local title = UI.Eyebrow(band, L["This bar"])
    title:SetPoint("TOPLEFT", band, "TOPLEFT", 0, -10)

    local rule = band:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(C.separator[1], C.separator[2], C.separator[3], 1)
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT", band, "BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", band, "BOTTOMRIGHT", -14, 0)

    local host = CreateFrame("Frame", nil, band)
    host:SetPoint("TOPLEFT", band, "TOPLEFT", 0, -BAND_HEAD)
    host:SetPoint("TOPRIGHT", band, "TOPRIGHT", -14, -BAND_HEAD)

    local slotW, gap, slotH = Page.PreviewGeometry(width)
    host:SetHeight(slotH)

    local slots = {}

    -- CREATED AT THE SIZE IT IS ABOUT TO BE DRAWN AT. UI.SpellSlot takes the
    -- font size of its empty "+" from the size it is handed, once - so a
    -- lattice rebuilt from 40 down to 26 keeps a plus sign drawn for a 40
    -- pixel box, and it is the only thing on the page that does not shrink.
    local function SlotAt(index)
        if slots[index] then return slots[index] end

        local slot = UI.SpellSlot(host, {
            size = slotW,
            -- NAMED BY WHAT IT CARRIES, not by the page it is on. A drag kind
            -- of "cooldowns" would take a raid-bar marker without complaint
            -- and draw an empty square for the rest of the session; "spell"
            -- is what a cooldown cell actually holds. See UI.DragOutcome.
            dragKind = "spell",
            get = function()
                local store, bar = Store(), Page.Current()
                if not (store and bar) then return nil end
                return store.Cells(bar)[index]
            end,
            onPick = function(spellID)
                local bars, bar = Bars(), Page.Current()
                if not (bars and bar) then return end
                local ok, why = bars.SetCell(bar, index, spellID)
                if not ok then
                    ns.Print("|cffff8040Not put on the bar|r - "
                        .. (why or "?") .. ".")
                    return
                end
                Page.cell = nil
                Refresh()
            end,
            onEmptyClick = function()
                Page.cell = (Page.cell ~= index) and index or nil
                ns.Options:Refresh()
            end,
            onClear = function()
                local bars, bar = Bars(), Page.Current()
                if bars and bar then bars.SetCell(bar, index, nil) end
                Refresh()
            end,
        })
        slots[index] = slot
        return slot
    end

    -- THE LATTICE, DRAWN BY THE SAME MODEL THAT DRAWS THE SCREEN.
    --
    -- Not "a grid that looks like the bar" - Model.Slot, the function the
    -- renderer calls, scaled to fit the band. That is what makes "the preview
    -- agrees with the screen" a fact rather than a hope: a stagger, a flow
    -- down columns or a bar that grows leftwards is right here because it is
    -- right there, and an off-by-one in the model is visible on this page.
    band.Refresh = function()
        local store, bar = Store(), Page.Current()
        title:SetText(bar and (bar.name or L["This bar"]) or L["No bars yet"])

        for _, slot in pairs(slots) do slot:Hide() end
        if not (store and bar) then
            host:SetHeight(1)
            return
        end

        local model = ns.Cooldowns.Model
        local opts = store.Lattice(bar)
        local count = math.max(1, store.Capacity(bar))

        slotW, gap, slotH = Page.PreviewGeometry(width)

        -- The preview lattice is the real one at a scale. Every step comes
        -- from the model, so only the two sizes and the two gaps are scaled.
        local scaled = {
            columns = opts.columns, layout = opts.layout, flow = opts.flow,
            growX = opts.growX, growY = opts.growY, stagger = opts.stagger,
            size = slotH, width = slotW,
            spacing = gap,
            lineSpacing = math.max(0, math.floor(
                (opts.lineSpacing or gap) * (slotH / math.max(1, opts.size or 40)))),
        }

        local boxW, boxH, offX, offY = model.Extent(count, scaled)
        host:SetHeight(math.max(1, boxH))

        for index = 1, count do
            local slot = SlotAt(index)
            local x, y = model.Slot(index, scaled, count)
            slot:Resize(slotW)
            if slot.SetSize then slot:SetSize(slotW, slotH) end
            slot:ClearAllPoints()
            -- Anchored from the left edge rather than the middle: the band is
            -- as wide as the page and the bar is not, and a bar that grows
            -- leftwards would otherwise walk off the edge it grew towards.
            slot:SetPoint("CENTER", host, "LEFT",
                (x - offX) + boxW / 2 + 4, (y - offY) + boxH / 2 - boxH / 2)
            slot:SetSelected(Page.cell == index)
            slot:Show()
            if slot.Refresh then slot:Refresh() end
        end
    end

    return band
end

---------------------------------------------------------------------------
-- The settings
---------------------------------------------------------------------------
local function BuildBars(grid)
    local L = ns.L
    local store, bars = Store(), Bars()

    grid:Section(L["Your bars"], "bars")

    local list = {}
    for _, bar in pairs(store and store.Bars() or {}) do
        if type(bar) == "table" and bar.id then list[#list + 1] = bar end
    end
    table.sort(list, function(a, b) return (a.id or 0) < (b.id or 0) end)

    if #list == 0 then
        grid:Note(L["No bars yet. Make one and the spells you pick land on "
            .. "it - everything Blizzard's Cooldown Manager already knows "
            .. "about is in the list on the right."])
    end

    for _, bar in ipairs(list) do
        local id = bar.id
        -- WHICH ONE YOU ARE EDITING, SAID IN WORDS ON THE ROW ITSELF. A page
        -- whose preview belongs to one of five identical-looking rows and
        -- says so nowhere is a page you edit the wrong bar on.
        --
        -- A sublabel rather than a colour, and not for taste: `UI.Row` takes
        -- `icon`, `sublabel` and `tall`, and nothing else. The first draft
        -- passed `accent = true`, which the row does not read - so it would
        -- have marked nothing at all, silently, which is exactly the kind of
        -- control that does nothing this addon spent a session removing.
        local row = grid:Row(bar.name or L["Bar"], {
            sublabel = (Page.barID == id)
                and L["Shown in the preview above"] or nil,
        })
        UI.Toggle(row,
            function() return bar.enabled ~= false end,
            function(on)
                bar.enabled = on and true or false
                Refresh()
            end)
        row:SetScript("OnClick", function()
            Page.barID = id
            Page.cell = nil
            Refresh()
        end)
    end

    grid:Buttons({
        { text = L["New bar"], onClick = function()
            local made = bars and bars.New()
            if made then Page.barID = made.id end
            Refresh()
        end },
        { text = L["Duplicate this one"], onClick = function()
            local bar = Page.Current()
            local made = bar and bars and bars.Duplicate(bar.id)
            if made then Page.barID = made.id end
            Refresh()
        end },
    }, UI.PAD)

    -- DELETING ONE ASKS TWICE, like every other thing in this addon you
    -- cannot take back in the same second.
    local bar = Page.Current()
    if bar then
        local armed, button = false, nil
        local idle = L("Delete %s", bar.name or L["this bar"])
        local _, made = grid:Buttons({
            {
                text = idle,
                onClick = function()
                    local handle = button
                    if not handle then return end
                    if not armed then
                        armed = true
                        handle:SetText(L["Really delete it?"])
                        C_Timer.After(4, function()
                            armed = false
                            if handle and handle.SetText then
                                handle:SetText(idle)
                            end
                        end)
                        return
                    end
                    -- `and` cannot carry two answers, so the call is its own
                    -- statement. Written as `local _, freed = bars and
                    -- bars.Delete(...)` the second return is dropped on the
                    -- floor and `freed` is always nil - so the line that says
                    -- how many bars were let loose would never once print.
                    local freed = 0
                    if bars then
                        local _, released = bars.Delete(bar.id)
                        freed = released or 0
                    end
                    Page.barID = nil
                    if freed > 0 then
                        ns.Print(ns.L("%d bars were following it and now sit "
                            .. "where they are.", freed))
                    end
                    Refresh()
                end,
            },
        })
        button = made
        grid.deleteButton = made
    end
end

local function BuildArrangement(grid)
    local L = ns.L
    local bar = Page.Current()
    if not bar then return end

    grid:Section(L["Arrangement"], "arrangement")

    -- INTO THE ROW'S CONTROL SLOT, anchored to its right edge, which is where
    -- every other control on every other page sits. The first draft made the
    -- ROW the parent, so the box landed at the row's origin - on top of its
    -- own label - and nothing would have said so out here.
    local nameRow = grid:FullRow(L["Name"], { controlWidth = 260 })
    local nameInput = UI.Input(nameRow.slot, 260, function(text)
        if text and text ~= "" then
            bar.name = text
            Refresh()
        end
    end, false, L["Bar"])
    nameInput:SetPoint("RIGHT", nameRow.slot, "RIGHT", 0, 0)
    nameInput:SetText(bar.name or "")
    nameRow.Refresh = function() nameInput:SetText(bar.name or "") end

    UI.Dropdown(grid:Row(L["Cells are"]), {
        { value = "icon", text = L["Icons"] },
        { value = "bar",  text = L["Bars"] },
    }, function() return bar.kind or "icon" end,
       function(value) bar.kind = value; Refresh() end)

    UI.Slider(grid:Row(L["Across"]), {
        min = 1, max = 20, step = 1,
        get = function() return tonumber(bar.columns) or 1 end,
        set = function(value) bar.columns = value; Refresh() end,
    })
    UI.Slider(grid:Row(L["Down"]), {
        min = 1, max = 10, step = 1,
        get = function() return tonumber(bar.rows) or 1 end,
        set = function(value) bar.rows = value; Refresh() end,
    })
    grid:Note(L["Across times down is how many places the bar has. A spell "
        .. "already sitting past the last place keeps its cell - narrowing a "
        .. "bar never throws a pick away."])

    UI.Dropdown(grid:Row(L["Pattern"]), ns.CD_LAYOUTS,
        function() return (ns.Cooldowns.Store.Lattice(bar)).layout or "grid" end,
        function(value) bar.layout = value; Refresh() end)

    if (ns.Cooldowns.Store.Lattice(bar)).layout == "staggered" then
        UI.Slider(grid:Row(L["Shift every other line"]), {
            min = 0, max = 100, step = 5, suffix = "%",
            get = function() return tonumber(bar.staggerOffset) or 50 end,
            set = function(value) bar.staggerOffset = value; Refresh() end,
        })
        grid:Note(L["As a share of one cell, so it stays right when you "
            .. "change the icon size."])
    end

    UI.Dropdown(grid:Row(L["Fills"]), ns.CD_FLOWS,
        function() return bar.flow or "rows" end,
        function(value) bar.flow = value; Refresh() end)
    UI.Dropdown(grid:Row(L["Grows across"]), ns.CD_GROW_X,
        function() return bar.growX or "right" end,
        function(value) bar.growX = value; Refresh() end)
    UI.Dropdown(grid:Row(L["Grows down"]), ns.GROW_Y,
        function() return bar.growY or "down" end,
        function(value) bar.growY = value; Refresh() end)
end

local function BuildSize(grid)
    local L = ns.L
    local bar = Page.Current()
    if not bar then return end

    grid:Section(L["Size and spacing"], "size")

    if bar.kind == "bar" then
        UI.Slider(grid:Row(L["Bar width"]), {
            min = 60, max = 500, step = 5,
            get = function() return tonumber(bar.barWidth) or 200 end,
            set = function(value) bar.barWidth = value; Refresh() end,
        })
        UI.Slider(grid:Row(L["Bar height"]), {
            min = 8, max = 80, step = 1,
            get = function() return tonumber(bar.barHeight) or 24 end,
            set = function(value) bar.barHeight = value; Refresh() end,
        })
        -- WHERE THE SQUARE ICON SITS ON A BAR-SHAPED CELL, and it is here
        -- rather than under the look because it decides GEOMETRY: without an
        -- answer, an icon-shaped frame in a bar-shaped slot is a square
        -- stretched across a quarter of the screen.
        UI.Dropdown(grid:Row(L["Spell icon"]), {
            { value = "left",   text = L["At the left"] },
            { value = "right",  text = L["At the right"] },
            { value = "hidden", text = L["Not shown"] },
        }, function() return bar.iconPlacement or "left" end,
           function(value) bar.iconPlacement = value; Refresh() end)
    else
        UI.Slider(grid:Row(L["Icon size"]), {
            min = 16, max = 80, step = 1,
            get = function() return tonumber(bar.iconSize) or 40 end,
            set = function(value) bar.iconSize = value; Refresh() end,
        })
    end

    UI.Slider(grid:Row(L["Gap across"]), {
        min = 0, max = 40, step = 1,
        get = function() return tonumber(bar.spacing) or 4 end,
        set = function(value) bar.spacing = value; Refresh() end,
    })
    -- TWO GAPS, NOT ONE, and the second one is not decoration: two of his own
    -- four bars carry a row gap different from their column gap, and on the
    -- single-column one it is the only gap the bar has.
    UI.Slider(grid:Row(L["Gap down"]), {
        min = 0, max = 40, step = 1,
        get = function() return tonumber(bar.lineSpacing) or tonumber(bar.spacing) or 4 end,
        set = function(value) bar.lineSpacing = value; Refresh() end,
    })
    UI.Slider(grid:Row(L["Scale"]), {
        min = 0.5, max = 2, step = 0.05,
        get = function() return tonumber(bar.scale) or 1 end,
        set = function(value) bar.scale = value; Refresh() end,
    })
end

---------------------------------------------------------------------------
-- Who else is doing this
---------------------------------------------------------------------------
local function BuildRivals(grid)
    local L = ns.L

    grid:Section(L["Who is managing your cooldowns"], "rivals")

    local rivals = ns.Cooldowns and ns.Cooldowns.Rivals
    local others = rivals and rivals.Others() or {}

    if #others > 0 then
        local names = {}
        for index, entry in ipairs(others) do names[index] = entry.label end
        grid:Note(L("Also managing cooldowns on this account: %s.",
            table.concat(names, ", ")))
        grid:Note(L["Blizzard owns these frames and only one addon can hold "
            .. "them. Whichever loads second finds them already taken, and "
            .. "what you get on screen depends on the order they happened to "
            .. "load in - which is why this is a choice rather than something "
            .. "either addon can work around. Leave Cooldowns switched off to "
            .. "keep theirs, or switch theirs off and switch this on."])

        -----------------------------------------------------------------
        -- ONE BUTTON PER ADDON, AND IT ASKS TWICE
        --
        -- Owner, 2026-08-15: "einen button einbauen, das man andere cdm
        -- abstellt, das kann elle ui auch."
        --
        -- Two steps, disarming itself after four seconds - the same pattern
        -- as deleting a profile, which is the other place in this addon
        -- where one click does something you cannot take back in the same
        -- second. It reloads the interface, and a reload nobody expected is
        -- indistinguishable from a crash.
        --
        -- One button per addon rather than one for all of them. Two names on
        -- one button is a press whose consequences the label cannot state.
        -----------------------------------------------------------------
        -- KEPT ON THE PAGE, so the desk can prove the button was actually
        -- made. Without a handle the only evidence that this branch works is
        -- that building it did not throw - and a `grid:Buttons` that quietly
        -- returned nothing would pass that, then do nothing on click for
        -- everybody who has a conflict, which is the only person who ever
        -- sees this branch at all.
        grid.page.rivalButtons = {}

        for _, entry in ipairs(others) do
            local dependents = ns.Cooldowns.Rivals.Dependents(entry.folder)
            local armed, button = false, nil
            local idle = L("Switch off %s", entry.label)

            local _, made = grid:Buttons({
                {
                    text = idle,
                    onClick = function()
                        local handle = button
                        if not handle then return end
                        if not armed then
                            armed = true
                            handle:SetText(L["Do it and reload?"])
                            -- Disarms itself. A button left sitting on
                            -- "really?" is one somebody clicks on their way
                            -- past a week later.
                            C_Timer.After(4, function()
                                armed = false
                                if handle and handle.SetText then
                                    handle:SetText(idle)
                                end
                            end)
                            return
                        end

                        armed = false
                        handle:SetText(idle)

                        local ok, why = ns.Cooldowns.Rivals.Disable(entry.folder)
                        if not ok then
                            ns.Print("|cffff4040Not switched off|r - "
                                .. (why or "?") .. ".")
                            return
                        end
                        ReloadUI()
                    end,
                },
            })
            button = made
            grid.page.rivalButtons[#grid.page.rivalButtons + 1] = made

            if #dependents > 0 then
                -- THE ONE THING THEIR POWER BUTTON DOES NOT SAY. Disabling
                -- does not cascade: an addon that lists this one as a
                -- dependency just stops loading, silently.
                grid:Note(L("Careful: %s would stop loading as well, because "
                    .. "it needs that addon.", table.concat(dependents, ", ")))
            end
            grid:Note(L["Switches that addon off, switches Cooldowns on here, "
                .. "and reloads. Nothing is deleted - it is the same tick as "
                .. "in the game's own addon list, and putting it back there "
                .. "puts everything back with it."])
        end
    else
        grid:Note(L["Nothing else on this account is managing them."])
    end

    -- HOW IT DECIDED, because a check that reports something surprising and
    -- will not say why is a check people stop believing. It is also the line
    -- that explains why an addon they think of as a cooldown addon is not
    -- listed: it never said so about itself.
    grid:Note(L["Read from what each addon says about itself in its own "
        .. "description, so an addon that manages cooldowns without ever "
        .. "saying so is not found. Addons switched off for this character "
        .. "are not counted."])

    ---------------------------------------------------------------------
    -- What Blizzard's own Cooldown Manager knows
    ---------------------------------------------------------------------
    grid:Section(L["Blizzard's Cooldown Manager"], "blizzard")

    -- WHAT WE DO WITH THE ONES YOU DID NOT PLACE. Blizzard goes on drawing
    -- every cooldown it knows in its own viewers, so without this the bar you
    -- arranged sits next to a second, unarranged copy of the same icons.
    UI.Toggle(grid:Row(ns.L["Hide the ones you did not place"]),
        function() return ns.db.takeOverCDM ~= false end,
        function(on) ns.db.takeOverCDM = on and true or false; Refresh() end)
    grid:Note(L["Blizzard's own viewers keep showing everything they know. "
        .. "This makes the ones you have not put on a bar invisible rather "
        .. "than hiding them - they are Blizzard's frames and hiding one is "
        .. "the thing that breaks them for the rest of the session."])

    grid:Note(L["Everything here comes from Blizzard's Cooldown Manager - it "
        .. "already knows the spells, binds the auras and has the timing, "
        .. "none of which an addon can do for itself on this patch. The "
        .. "reminders, the death log and the spell pickers all read it, and "
        .. "they go on doing so whether this module is on or off."])

    grid:Buttons({
        { text = L["What it holds"], onClick = function()
            ns.CDM:Dump()
        end },
    })
end

function Page:BuildPage(page, width)
    local grid = UI.Page(page, width, { tooltipNotes = true, sticky = true })
    grid.page = page

    BuildBand(grid, width)
    BuildBars(grid)
    BuildArrangement(grid)
    BuildSize(grid)
    BuildRivals(grid)

    return grid
end

---------------------------------------------------------------------------
-- The third column: every spell this character can be shown
--
-- SpellPane, the same list the reminders and the death log pick from. It was
-- lifted out of the old cooldown workspace when the bars went, which is the
-- only reason there is one to reuse - and reusing it is what keeps the four
-- pickers in this addon one picture rather than four.
---------------------------------------------------------------------------
function Page:BuildSide(sideHost, pad)
    local L = ns.L
    local side = CreateFrame("Frame", nil, sideHost)
    side:SetAllPoints(sideHost)
    side:Hide()

    local title = UI.Label(side, L["Every spell"], UI.FS.card, C.text)
    title:SetPoint("TOPLEFT", side, "TOPLEFT", pad, -18)

    local hint = UI.Label(side, L["Click one to put it on the bar."],
        UI.FS.meta, C.textFaint)
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

    local paneHost = CreateFrame("Frame", nil, side)
    paneHost:SetPoint("TOPLEFT", side, "TOPLEFT", pad, -(UI.HEADER_H + 16))
    paneHost:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -pad, pad)

    local pane = ns.SpellPane:Build(paneHost, UI.INSPECTOR_W - pad * 2 - 8, {
        Used = function()
            local bars, bar = Bars(), Page.Current()
            return (bars and bar) and bars.Used(bar) or {}
        end,

        -- WHERE A CLICK PUTS IT: the cell you selected, or the first empty
        -- one. Saying "the bar is full" out loud rather than overwriting cell
        -- one, because a picker that silently replaces something is a picker
        -- you stop trusting after it eats one spell.
        Assign = function(spellID)
            local bars, bar = Bars(), Page.Current()
            if not (bars and bar) then
                ns.Print("|cffff8040No bar to put it on.|r Make one first.")
                return
            end

            local index = Page.cell or bars.FirstFree(bar)
            if not index then
                ns.Print("|cffff8040Every place on this bar is full.|r Raise "
                    .. "|cffffd100Across|r or |cffffd100Down|r, or "
                    .. "right-click a place to empty it.")
                return
            end

            local ok, why = bars.SetCell(bar, index, spellID)
            if not ok then
                ns.Print("|cffff8040Not put on the bar|r - " .. (why or "?")
                    .. ".")
                return
            end
            Page.cell = nil
            Refresh()
        end,

        Hint = function()
            local bar = Page.Current()
            if not bar then return nil end
            if Page.cell then
                return L("Click to fill place %d of %s", Page.cell,
                    bar.name or L["this bar"])
            end
            return L("Click to add it to %s", bar.name or L["this bar"])
        end,

        -- The selection has to come back into range before the list is
        -- filled: a cell chosen on a bar that has since been narrowed is a
        -- place that no longer exists, and filling it writes a pick nothing
        -- draws.
        Sync = function()
            local store, bar = Store(), Page.Current()
            if not (store and bar) then Page.cell = nil return end
            if Page.cell and Page.cell > store.Capacity(bar) then
                Page.cell = nil
            end
        end,
    })

    side.Refresh = function()
        if pane and pane.Refresh then pane:Refresh() end
    end

    return side
end
