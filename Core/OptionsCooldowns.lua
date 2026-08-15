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
-- How tall one card's preview may grow before it is scaled down. A bar with
-- twenty places would otherwise be a card you scroll past rather than a
-- picture you can compare with the one under it.
local PREVIEW_MAX_H = 190

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

---------------------------------------------------------------------------
-- THE CARD COLUMN: EVERY BAR, LIVE, ONE UNDER THE OTHER
--
-- Owner, 2026-08-15, having seen both: "ich fand es vorher besser, wo ich alle
-- bars als live view untereinander hatte. koennen wir hier einen mittelweg
-- finden?" - and the requirement that decides how this is built: "die bars
-- muessen immer 100% den ist status spiegeln, also so wie sie wirklich
-- aussehen."
--
-- THE MIDDLE GROUND IS: his column of live cards on the left, the tabbed
-- settings on the right. One bar per card, each drawing ITSELF rather than the
-- one that happens to be selected - so the page answers "what do my bars look
-- like" without clicking anything, which is what the old page was better at.
--
-- 100% IS A CLAIM THAT HAS TO BE EARNED, so it is worth writing down exactly
-- what it means here. Every card is painted by UI.CellGrid, which asks Model
-- for the positions and ns.PaintSurface / ns.PaintBorder for the look - the
-- same functions the renderer uses, from the same resolved style. What it
-- cannot show is named on the page rather than faked: the sweep and the
-- numbers need Blizzard's own frame, and the counts are secret values.
---------------------------------------------------------------------------
-- HOW WIDE THE CARD COLUMN IS, AND WHY IT IS NOT WIDER.
--
-- Owner, 2026-08-15: "du kannst auch den mittleren bereich breiter machen,
-- wir haben ja platz." The page is handed 750 and every pixel of it is spoken
-- for, so the middle only widens if this narrows - there is no slack between
-- them to take.
--
-- 400, AND THE WINDOW GREW TO PAY FOR IT. Narrowing this column to 270 was
-- the first answer and it was the wrong one: the settings got their room and
-- the previews became postage stamps. Owner, with a picture of both: "den
-- bereich schmaler und die vorschau links breiter ... wenns vom platz her
-- nicht reicht, koennen wir rechts die icon spalte schmaler machen oder addon
-- breiter." So UI.WINDOW_W went 1382 -> 1460 and both halves got what they
-- need - 400 here, 392 for the settings.
--
-- 400 is not a taste: the preview is SCALED to the card, and 380 of usable
-- width is what draws his widest tracking bar at its real size instead of a
-- shrunk picture of it. A preview that does not agree with the screen is
-- worse than none - that lesson cost a release on the raid bar.
--
-- The two word buttons stay in the FOOTER they moved to at 270. They fit in
-- the header again at this width, and they read better under the bar they act
-- on than crowded against the switch.
local CARD_W = 400
local CARD_GAP = 22
local CARD_HEAD = 26
local CARD_PAD = 10
local CARD_FOOT = 20
local STAGE_MIN = 46

-- HOW BIG ONE PREVIEW CELL IS DRAWN, read off the bar and scaled to the card.
-- Never a constant of this file's own: a copied `SLOT = 40` drew every button
-- half again too big over a bar that is 26, and cost a release on the raid bar.
local function CardGeometry(bar)
    local store = Store()
    if not (store and bar) then return 40, 4, 40 end

    local opts = store.Lattice(bar)
    local count = math.max(1, store.Capacity(bar))
    local columns = math.max(1, opts.columns or 1)
    local rows = math.max(1, math.ceil(count / columns))
    local gap = math.max(0, opts.spacing or 4)

    -- ONE SCALE FOR BOTH SIDES, AND EACH SIDE MEASURED AGAINST ITS OWN ROOM.
    --
    -- UI.PreviewSize takes ONE wanted size and divides both the width and the
    -- height budget by it - which is right for a square and wrong for a bar.
    -- A 250 by 24 bar in three lines was measured as 250 against the 190
    -- pixels of height, came out at 60, and then STAYED at 60 however far the
    -- width slider was dragged. Owner: "die bar breite veraendert sich nicht
    -- live, kann die bar nicht im addon stylen wenn ich nicht sehe was da
    -- passiert." He is right, and it was not the slider.
    --
    -- One scale, never two: the picture has to keep the bar's shape, so a
    -- preview that fitted the width and the height separately would show a
    -- rectangle nobody configured.
    local wantedW = opts.width or opts.size or 40
    local wantedH = opts.size or 40

    local roomW = (CARD_W - CARD_PAD * 2) - (columns - 1) * gap
    local roomH = PREVIEW_MAX_H - (rows - 1) * gap

    -- NEVER ENLARGED. A bar drawn bigger than it is would be the same lie as
    -- one drawn smaller, and the size he types is the size on screen.
    local scale = 1
    if wantedW > 0 then scale = math.min(scale, (roomW / columns) / wantedW) end
    if wantedH > 0 then scale = math.min(scale, (roomH / rows) / wantedH) end
    scale = math.max(0, scale)

    return math.max(1, math.floor(wantedW * scale)),
           math.floor(gap * scale + 0.5),
           math.max(1, math.floor(wantedH * scale))
end

-- THE LATTICE THIS CARD DRAWS, in the renderer's own geometry at the card's
-- scale. Only the two sizes and the two gaps are scaled - every step comes
-- from the model, so a stagger, a flow down columns or a bar that grows
-- leftwards is right here because it is right there.
local function CardSlots(bar)
    local store = Store()
    if not (store and bar) then return nil, nil end

    local model = ns.Cooldowns.Model
    local opts = store.Lattice(bar)
    local count = math.max(1, store.Capacity(bar))
    local slotW, gap, slotH = CardGeometry(bar)

    local scaled = {
        columns = opts.columns, layout = opts.layout, flow = opts.flow,
        growX = opts.growX, growY = opts.growY, stagger = opts.stagger,
        size = slotH, width = slotW,
        spacing = gap,
        lineSpacing = math.max(0, math.floor(
            (opts.lineSpacing or gap) * (slotH / math.max(1, opts.size or 40)))),
    }

    local boxW, boxH, centreX, centreY = model.Extent(count, scaled)

    local slots = {}
    for index = 1, count do
        local x, y, w, h = model.Slot(index, scaled, count)
        slots[index] = { x = x, y = y, w = w, h = h,
            kind = (bar.kind == "bar") and "bar" or "icon" }
    end

    return slots, { width = boxW, height = boxH,
        centreX = centreX, centreY = centreY }
end

-- THE LOOK OF ONE CELL, merged from the three modules that own the pieces.
--
-- Not resolved here - ASKED. Look.Style answers the backdrop, the border and
-- the crop; Fill.Paint answers the fill, and it is the same reader Fill.Dress
-- uses on the real frame; Text.Style answers the four text elements. A fourth
-- copy of any of those defaults is a fourth copy that goes stale, which is the
-- fault this card has already had three times.
local function CardStyle(bar, height, index)
    local cd = ns.Cooldowns
    if not (cd and cd.Look and cd.Fill and cd.Text and bar) then return nil end

    local style = cd.Look.Style(bar, index)
    if type(style) ~= "table" then return nil end

    local wear = cd.Fill.Paint(bar, index)
    local text = cd.Text.Style(bar, height)

    -- COPIED ONTO THE LOOK RATHER THAN MUTATING IT. Look.Style hands back a
    -- table whose fillDirection is the SHARED entry out of ns.FILL_DIRECTIONS
    -- - writing into it would corrupt every bar and every renderer.
    local merged = {}
    for key, value in pairs(style) do merged[key] = value end
    merged.fillTexture = wear.texture
    merged.fillColor = wear.color
    merged.fillAlpha = wear.alpha
    merged.fillGradient = wear.gradient
    merged.fillDirection = wear.direction
    merged.spellName = text and text.spellName or nil
    return merged
end

local function BuildCards(host)
    local L = ns.L
    local cards = {}

    local title = UI.Eyebrow(host, L["Your bars"])
    title:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -2)

    local empty = UI.Hint(host, L["No bars yet. Make one and the spells you "
        .. "pick land on it."])
    empty:SetWidth(CARD_W)
    empty:SetJustifyV("TOP")
    empty:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -26)

    -- ADDING A BAR IS A + AT THE TOP, on the heading's own line.
    --
    -- Owner, 2026-08-15: "wir brauchen oben ein + button zum hinzufuegen von
    -- bars." It belongs at the top because that is where you look when there
    -- is nothing yet, and it stays in one place whether the column holds no
    -- bars or nine - which a button parked under the last card does not.
    --
    -- The other two actions moved ONTO THE CARDS. Duplicating and deleting are
    -- things you do to a particular bar, and a footer button that acts on
    -- "whichever one is selected" is a button whose consequence you have to
    -- look somewhere else to know.
    local add = UI.Button(host, "+", 30, function()
        local bars = Bars()
        local made = bars and bars.New()
        if made then Page.barID = made.id end
        Refresh()
    end)
    add:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
    add.dkTip = L["New bar"]
    add:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(self.dkTip)
        GameTooltip:Show()
    end)
    add:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    -- ONE CARD PER BAR, POOLED. Cards are frames and a page that makes a fresh
    -- one per refresh leaks a frame per press for the whole session.
    local function CardAt(index)
        if cards[index] then return cards[index] end

        local card = CreateFrame("Button", nil, host)
        card:SetWidth(CARD_W)
        card:RegisterForClicks("LeftButtonUp")
        UI.Fill(card, "BACKGROUND", C.surface)
        UI.Plate(card, 1, 1)

        -- The accent stripe down the left edge is the selection, which is the
        -- mark UI.Card already uses everywhere else in this window.
        card.mark = card:CreateTexture(nil, "OVERLAY")
        card.mark:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        card.mark:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
        card.mark:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0)
        card.mark:SetWidth(3)
        card.mark:Hide()

        card.title = UI.Label(card, "", UI.FS.row, C.text)
        card.title:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -8)
        card.title:SetWordWrap(false)

        card.badge = UI.Badge(card, "", "kind")
        card.badge:SetPoint("LEFT", card.title, "RIGHT", 8, 0)

        card.toggle = CreateFrame("Frame", nil, card)
        card.toggle:SetSize(40, 20)
        card.toggle:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD, -7)

        -- THE TWO ACTIONS THAT BELONG TO THIS BAR, on this bar. Deleting asks
        -- twice, like every other thing in this addon you cannot take back in
        -- the same second, and it disarms itself after four seconds: a button
        -- left sitting on "really?" is one somebody clicks on their way past a
        -- week later.
        card.remove = UI.GhostButton(card, ns.L["Delete"], function()
            if not card.dkBar then return end
            if not card.armed then
                card.armed = true
                card.remove:SetText(ns.L["Really?"])
                local id = card.dkBar.id
                C_Timer.After(4, function()
                    if not (card.armed and card.dkBar
                        and card.dkBar.id == id) then return end
                    card.armed = false
                    card.remove:SetText(ns.L["Delete"])
                end)
                return
            end
            card.armed = false

            local bars = Bars()
            -- `and` cannot carry two answers, so the call is its own
            -- statement: written as `local _, freed = bars and bars.Delete()`
            -- the second return is dropped and the line that says how many
            -- bars were let loose would never once print.
            local freed = 0
            if bars then
                local _, released = bars.Delete(card.dkBar.id)
                freed = released or 0
            end
            if Page.barID == card.dkBar.id then Page.barID = nil end
            if freed > 0 then
                ns.Print(ns.L("%d bars were following it and now sit where "
                    .. "they are.", freed))
            end
            Refresh()
        end, C.danger)

        card.copy = UI.GhostButton(card, ns.L["Duplicate"], function()
            local bars = Bars()
            local made = card.dkBar and bars and bars.Duplicate(card.dkBar.id)
            if made then Page.barID = made.id end
            Refresh()
        end)

        -- The well the preview sits in: a piece of SCREEN set into the card,
        -- which is what makes the picture read as the bar rather than as more
        -- of the page.
        card.well = CreateFrame("Frame", nil, card)
        card.well:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD,
            -(CARD_HEAD + 4))
        card.well:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD,
            -(CARD_HEAD + 4))
        UI.Fill(card.well, "BACKGROUND", C.well)

        card.grid = UI.CellGrid(card.well, {
            dragKind = "spell",
            layout = function() return CardSlots(card.dkBar) end,
            style = function(height, index)
                return CardStyle(card.dkBar, height, index)
            end,
            iconPlacement = function()
                return card.dkBar and card.dkBar.iconPlacement or "left"
            end,
            content = function(index)
                local store = Store()
                if not (store and card.dkBar) then return nil end
                return store.Cells(card.dkBar)[index]
            end,
            selected = function()
                if not (card.dkBar and Page.barID == card.dkBar.id) then
                    return nil
                end
                return Page.cell
            end,
            onPick = function(index)
                if not card.dkBar then return end
                Page.barID = card.dkBar.id
                Page.cell = (Page.cell ~= index) and index or nil
                Refresh()
            end,
            onClear = function(index)
                local bars = Bars()
                if bars and card.dkBar then
                    bars.SetCell(card.dkBar, index, nil)
                end
                Refresh()
            end,
            onDrop = function(index, spellID)
                local bars = Bars()
                if not (bars and card.dkBar) then return end
                local ok, why = bars.SetCell(card.dkBar, index, spellID)
                if not ok then
                    ns.Print("|cffff8040Not put on the bar|r - "
                        .. (why or "?") .. ".")
                    return
                end
                Page.barID = card.dkBar.id
                Page.cell = nil
                Refresh()
            end,
            onMove = function(from, to, swap)
                local bars, store = Bars(), Store()
                if not (bars and store and card.dkBar) then return end
                local cells = store.Cells(card.dkBar)
                local moving, landing = cells[from], cells[to]
                bars.SetCell(card.dkBar, to, moving)
                bars.SetCell(card.dkBar, from, swap and landing or nil)
                Refresh()
            end,
        })
        card.grid:SetPoint("TOPLEFT", card.well, "TOPLEFT", 6, -6)

        -- THE FOOTER, under the preview rather than beside the switch. Both
        -- buttons are made above with the rest of the header so their
        -- handlers read in one place; only where they SIT is decided here,
        -- because until the well exists there is nothing to hang them under.
        card.remove:SetPoint("TOPRIGHT", card.well, "BOTTOMRIGHT", 0, -4)
        card.copy:SetPoint("RIGHT", card.remove, "LEFT", -10, 0)

        card:SetScript("OnClick", function()
            if not card.dkBar then return end
            Page.barID = card.dkBar.id
            Refresh()
        end)

        cards[index] = card
        return card
    end

    host.Refresh = function()
        local store = Store()
        local list = {}
        for _, bar in pairs(store and store.Bars() or {}) do
            if type(bar) == "table" and bar.id then list[#list + 1] = bar end
        end
        table.sort(list, function(a, b) return (a.id or 0) < (b.id or 0) end)

        -- WHERE THE FIRST CARD STARTS, and it is a clearance rather than a
        -- margin: the + and the eyebrow share the top line, and at 26 the
        -- button's bottom edge and the first card's top edge were two pixels
        -- apart. Owner, with a picture: "der plus button braucht nach unten
        -- hin mehr platz." Nothing above the button to give it, so the room
        -- comes from below - which is the same gap either way.
        local y = 44
        for index, bar in ipairs(list) do
            local card = CardAt(index)
            card.dkBar = bar
            card.title:SetText(bar.name or L["Bar"])
            -- SetLabel, not SetText. A badge is a FRAME with a string
            -- inside it, and a frame has no SetText - the call was a nil
            -- value, it threw on the FIRST card, and everything after it in
            -- this refresh never ran. That is why every control on the right
            -- was blank: page.Refresh calls this before grid:Refresh, so one
            -- nil call here left the whole settings half unpainted.
            card.badge:SetLabel((bar.kind == "bar") and L["Tracking bar"]
                or L["Icon bar"])

            if not card.switch then
                card.switch = UI.Toggle({ slot = card.toggle },
                    function()
                        return card.dkBar and card.dkBar.enabled ~= false
                    end,
                    function(on)
                        if not card.dkBar then return end
                        card.dkBar.enabled = on and true or false
                        Refresh()
                    end).control
            end
            if card.switch and card.switch.Refresh then card.switch.Refresh() end

            card.mark:SetShown(Page.barID == bar.id)

            -- A CARD IS POOLED, so the one that was armed to delete bar three
            -- can come back holding bar four. Disarmed on every pass unless it
            -- is still the same bar - otherwise the second click deletes
            -- something nobody asked about.
            if card.dkArmedFor ~= bar.id then
                card.armed = false
                card.dkArmedFor = bar.id
            end
            if not card.armed then card.remove:SetText(L["Delete"]) end

            local height = card.grid.Refresh() or 0
            card.well:SetHeight(math.max(STAGE_MIN, height + 12))
            card:SetHeight(CARD_HEAD + 4 + card.well:GetHeight()
                + 4 + CARD_FOOT + CARD_PAD)

            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
            card:Show()
            y = y + card:GetHeight() + CARD_GAP
        end
        for index = #list + 1, #cards do cards[index]:Hide() end

        -- WHICHEVER CARD IS FIRST, for the desk guard that asks whether this
        -- page still offers a way to delete a bar. Read after the loop,
        -- because before it there is no card to name.
        host.deleteButton = cards[1] and cards[1].remove or nil

        empty:SetShown(#list == 0)
        if #list == 0 then y = y + 40 end

        -- The column says how tall it is, or the scroll under it has no range
        -- and the last card is unreachable.
        host:SetHeight(math.max(1, y + 10))
        return y
    end

    -- Named for the desk, which asks whether this page offers a way to make a
    -- bar and a way to delete one - and asks it of a page with NO bars, which
    -- is the state in which those two are easiest to lose.
    host.addButton = add
    host.CardAt = CardAt

    return host
end

-- THE BAR IS RESOLVED WHEN A CONTROL IS READ, NEVER WHEN IT IS BUILT.
--
-- This page is built ONCE - Options.ShowPage sets entry.built and nothing
-- clears it - so a `local bar = Page.Current()` at the top of a builder is
-- the bar that happened to be selected the first time the page was opened.
-- Click a second bar in "Your bars" and every slider on the page would go on
-- reading and WRITING the first one, silently, for the rest of the session.
--
-- Found by the agent that wrote the look and effects sections, which resolves
-- through Page.Current() on every read for exactly this reason. Four rows had
-- it wrong here and none of them would have raised.
local function Bar()
    return Page.Current()
end

-- Reading and writing one field of whichever bar is selected. A setter that
-- fires with no bar is a no-op rather than an error: the page still exists
-- for a moment after the last bar is deleted.
local function Get(key, fallback)
    local bar = Bar()
    local value = bar and bar[key]
    if value == nil then return fallback end
    return value
end

local function Set(key, value)
    local bar = Bar()
    if not bar then return end
    bar[key] = value
    Refresh()
end

local function Number(key, fallback)
    return tonumber(Get(key, fallback)) or fallback
end

-- HOW MANY PLACES THE SELECTED BAR HAS, asked of the store rather than
-- multiplied out here. A bar that has said how many it has is believed to the
-- letter - that is what makes Rows a limit - and a pick sitting past the last
-- one is kept rather than counted: Store.Parked is what says how many, and
-- the note under the sliders is where it is said.
local function Places()
    local store, bar = Store(), Bar()
    if not (store and bar) then return 1 end
    return math.max(1, store.Capacity(bar))
end

-- A refresher that is not a ROW. Grid:Refresh walks grid.widgets and calls
-- Refresh on anything that has one, so a plain table with the one field is
-- how a block hangs recomputation off the page without a control to hang it
-- on. The same three lines OptionsCooldownsBar.lua keeps, written out rather
-- than reached for across the file boundary because it is a local there.
local function OnRefresh(grid, fn)
    grid.widgets[#grid.widgets + 1] = { Refresh = fn }
end

-- WHETHER ANY PLACE ON THIS BAR HAS A FILL AT ALL.
--
-- Two answers, and the second is why this is not `bar.kind == "bar"`. A
-- PLACE'S SHAPE IS BLIZZARD'S: ns.CDM:ItemShape reads the viewer the spell
-- lives in, so a spell out of the Buff bars viewer arrives as a StatusBar
-- however this bar's places are set, and Render.Fit puts it in the place
-- whole. A bar of icons with one tracked buff on it HAS a fill to configure,
-- and gating on the bar's own kind would hide the settings for the only place
-- on it they could reach.
local function HasFill(bar)
    if type(bar) ~= "table" then return false end
    if bar.kind == "bar" then return true end

    local store, cdm = Store(), ns.CDM
    if not (store and cdm and cdm.ItemForSpell and cdm.ItemShape) then
        return false
    end

    local cells = store.Cells(bar)
    for index = 1, store.Capacity(bar) do
        local spellID = cells[index]
        local item = spellID and cdm:ItemForSpell(spellID) or nil
        if item and cdm:ItemShape(item) == "bar" then return true end
    end
    return false
end

local function BuildArrangement(grid)
    local L = ns.L

    grid:Section(L["Arrangement"], "arrangement", true)

    -- INTO THE ROW'S CONTROL SLOT, anchored to its right edge, which is where
    -- every other control on every other page sits. The first draft made the
    -- ROW the parent, so the box landed at the row's origin - on top of its
    -- own label - and nothing would have said so out here.
    local nameRow = grid:FullRow(L["Name"], { controlWidth = 260 })
    local nameInput = UI.Input(nameRow.slot, 260, function(text)
        if text and text ~= "" then Set("name", text) end
    end, false, L["Bar"])
    nameInput:SetPoint("RIGHT", nameRow.slot, "RIGHT", 0, 0)
    -- Refreshed rather than set once, so it follows the selection. Grid:Refresh
    -- walks every row that carries one of these.
    nameRow.Refresh = function() nameInput:SetText(Get("name", "") or "") end

    -- SWITCHING TO BAR-SHAPED PLACES STACKS THEM. Owner, with a picture of
    -- four of them shoulder to shoulder: "bars muss gestabelt werden, und das
    -- sieht nicht gut aus."
    --
    -- A real write to Columns rather than a rule that overrides it, so the
    -- control still says what the bar is doing and dragging it back to four
    -- columns is allowed. A bar 200 wide beside another one is not a layout
    -- anybody meant to ask for; it is the default nobody changed.
    --
    -- The PLACES are left alone, so a bar of five icons becomes five stacked
    -- bars rather than one - the count is what he set and only the width of a
    -- line is being decided here.
    UI.Dropdown(grid:Row(L["Cells are"]), {
        { value = "icon", text = L["Icons"] },
        { value = "bar",  text = L["Bars"] },
    }, function() return Get("kind", "icon") end,
       function(value)
            local bar = Bar()
            if bar and value == "bar" and Number("columns", 1) > 1 then
                bar.columns = 1
            end
            Set("kind", value)
       end)

    -----------------------------------------------------------------------
    -- COLUMNS AND ROWS, IN THOSE WORDS
    --
    -- Owner, 2026-08-15, with a photograph of the three sliders: "wir
    -- brauchen anzahl an spalten und reihen, nicht across. ich muss auf eine
    -- reihe begrenzen koennen. das across versteht keiner" - and then, in
    -- case the first was read as a layout note: "wir brauchen 2 klare
    -- einstellungen, spalten und reihen."
    --
    -- He is right twice over. "Across" and "Down" are directions, and a
    -- direction is not a count - somebody reading them cannot tell whether
    -- Down is a number of lines or which way the bar grows, which is a
    -- question the two rows further down actually answer. Columns and Rows
    -- have meant one thing each since the first spreadsheet.
    --
    -- EITHER OF THEM WRITES THE TOTAL: cellCount = columns x rows. That is
    -- what makes "one row" a thing you can ask for rather than a thing you
    -- arrive at by dividing. Places is still there underneath as the truth,
    -- because the pair can only ever describe a RECTANGLE and one of his own
    -- bars is not one - see Model.lua's header, "the list is the truth and
    -- the columns are the view".
    -----------------------------------------------------------------------
    grid:Section(L["Rows and columns"], "cd-grid", true)

    -- BOTH NOTES ON THE PAGE, not in the hover. Grid:Section clears the row a
    -- note would otherwise attach itself to, so a note written here is laid
    -- out rather than hung on the control above - which is the only way a
    -- limit is readable before you go looking for the control it limits.
    grid:Note(L["Columns and Rows lay the places out, and either one sets how "
        .. "many places that comes to. Places is the total underneath and may "
        .. "be fewer than the rectangle holds - seven places in two rows of "
        .. "four leaves the last one empty."])

    local parked = grid:Note("")

    -- HOW MANY LINES THE BAR COMES TO RIGHT NOW. Read rather than stored: two
    -- controls over one number cannot disagree, and a stored `rows` beside a
    -- stored `cellCount` is the pair that drifts.
    local function Lines()
        local across = math.max(1, Number("columns", 1))
        return math.max(1, math.ceil(Places() / across))
    end

    UI.Slider(grid:Row(L["Columns"]), {
        min = 1, max = 20, step = 1,
        get = function() return Number("columns", 1) end,
        set = function(value)
            local bar = Bar()
            if not bar then return end
            -- COUNTED BEFORE THE WRITE. Lines() divides by the column count,
            -- so reading it after the new one is in place answers for the
            -- layout being replaced rather than the one being changed - and
            -- widening a bar would quietly drop a row every time.
            local lines = Lines()
            bar.columns = value
            Set("cellCount", value * lines)
        end,
    })

    UI.Slider(grid:Row(L["Rows"]), {
        min = 1, max = 20, step = 1,
        get = Lines,
        set = function(value)
            Set("cellCount", math.max(1, Number("columns", 1)) * value)
        end,
    })

    UI.Slider(grid:Row(L["Places"]), {
        min = 1, max = 40, step = 1,
        get = function() return Places() end,
        set = function(value) Set("cellCount", value) end,
    })

    -- SAID ONLY WHILE IT IS TRUE, and it is the honest half of the hard limit
    -- in Store.Capacity: narrowing a bar below what it holds keeps every
    -- spell, and a page that stayed quiet about it would look exactly like
    -- one that had thrown them away.
    grid.widgets[#grid.widgets + 1] = { Refresh = function()
        local store, bar = Store(), Bar()
        local left = (store and bar and store.Parked) and store.Parked(bar) or 0
        parked.dkSkip = left < 1
        parked:SetShown(left > 0)
        if left > 0 then
            parked:SetText(L("%d spells sit past the last place and are not "
                .. "drawn. Nothing was thrown away - make room and they come "
                .. "back where they were.", left))
        end
    end }

    UI.Dropdown(grid:Row(L["Pattern"]), ns.CD_LAYOUTS,
        function() return ns.Cooldowns.Store.Lattice(Bar()).layout or "grid" end,
        function(value) Set("layout", value) end)

    -- ALWAYS BUILT, NEVER CONDITIONALLY. It used to appear only when the bar
    -- was already staggered - on a page that is built ONCE, which means that
    -- for anybody who arrived with a grid bar the control could never appear
    -- at all, however many times they switched the pattern afterwards.
    --
    -- So it is always here and the row says what it belongs to. That is the
    -- owner's own triage rule: a "this needs the other thing switched on" is
    -- a fact you act on and has to be readable without pointing at anything.
    --
    -- `format` and `scale`, not `suffix`. UI.Slider has no suffix - the first
    -- version passed one and it did nothing, which is the exact defect this
    -- addon spent a session removing.
    UI.Slider(grid:Row(L["Shift every other line"]), {
        min = 0, max = 100, step = 5,
        format = function(value) return string.format("%d%%", value or 0) end,
        get = function() return Number("staggerOffset", 50) end,
        set = function(value) Set("staggerOffset", value) end,
    })
    grid:Note(L["Belongs to the staggered pattern and is ignored by the "
        .. "others. As a share of one cell, so it stays right when you change "
        .. "the icon size."])

    UI.Dropdown(grid:Row(L["Fills"]), ns.CD_FLOWS,
        function() return Get("flow", "rows") end,
        function(value) Set("flow", value) end)
    UI.Dropdown(grid:Row(L["Grows across"]), ns.CD_GROW_X,
        function() return Get("growX", "right") end,
        function(value) Set("growX", value) end)
    UI.Dropdown(grid:Row(L["Grows down"]), ns.GROW_Y,
        function() return Get("growY", "down") end,
        function(value) Set("growY", value) end)
end

local function BuildSize(grid)
    local L = ns.L

    grid:Section(L["Size and spacing"], "size", true)

    -- ALL FOUR, ALWAYS, for the reason the stagger row carries: this page is
    -- built once, so a block behind `if bar.kind == "bar"` is a block that can
    -- never appear for anybody who arrived with an icon bar. The rows that do
    -- not apply say so rather than hiding.
    UI.Slider(grid:Row(L["Icon size"]), {
        min = 16, max = 80, step = 1,
        get = function() return Number("iconSize", 40) end,
        set = function(value) Set("iconSize", value) end,
    })
    UI.Slider(grid:Row(L["Bar width"]), {
        min = 60, max = 500, step = 5,
        get = function() return Number("barWidth", 200) end,
        set = function(value) Set("barWidth", value) end,
    })
    UI.Slider(grid:Row(L["Bar height"]), {
        min = 8, max = 80, step = 1,
        get = function() return Number("barHeight", 24) end,
        set = function(value) Set("barHeight", value) end,
    })
    grid:Note(L["An icon place is square and uses the first of these; a bar "
        .. "place is the other two. Which one a bar's places are is up under "
        .. "Arrangement."])

    -- WHERE THE SQUARE ICON SITS ON A BAR-SHAPED CELL, and it is here rather
    -- than under the look because it decides GEOMETRY: without an answer, an
    -- icon-shaped frame in a bar-shaped slot is a square stretched across a
    -- quarter of the screen.
    UI.Dropdown(grid:Row(L["Spell icon"]), {
        { value = "left",   text = L["At the left"] },
        { value = "right",  text = L["At the right"] },
        { value = "hidden", text = L["Not shown"] },
    }, function() return Get("iconPlacement", "left") end,
       function(value) Set("iconPlacement", value) end)

    UI.Slider(grid:Row(L["Gap across"]), {
        min = 0, max = 40, step = 1,
        get = function() return Number("spacing", 4) end,
        set = function(value) Set("spacing", value) end,
    })
    -- TWO GAPS, NOT ONE, and the second one is not decoration: two of his own
    -- four bars carry a row gap different from their column gap, and on the
    -- single-column one it is the only gap the bar has.
    UI.Slider(grid:Row(L["Gap down"]), {
        min = 0, max = 40, step = 1,
        get = function() return Number("lineSpacing", Number("spacing", 4)) end,
        set = function(value) Set("lineSpacing", value) end,
    })
    UI.Slider(grid:Row(L["Scale"]), {
        min = 0.5, max = 2, step = 0.05,
        format = function(value) return string.format("%.2f", value or 1) end,
        get = function() return Number("scale", 1) end,
        set = function(value) Set("scale", value) end,
    })
end

---------------------------------------------------------------------------
-- When a bar is on screen at all
--
-- Its own tab, because it is the one block on this page that is not about
-- what a bar LOOKS like. Owner, 2026-08-15: "display conditions sind immer
-- noch nicht drin ... das ging alles mal bevor wir den cdm rausgehauen
-- haben." It did, and ns.Visibility survived the removal intact - the rules,
-- the eight events, the explanation. What it lost was every caller.
--
-- EVERY RULE IS AN "AND", and every one defaults to "any" - a rule you have
-- not set cannot be the reason something is missing. That sentence is
-- ns.Visibility's own header and it is what makes the block readable without
-- a diagram.
---------------------------------------------------------------------------
local function BuildWhen(grid)
    local L = ns.L
    local V = ns.Visibility

    grid:Tab(L["When"])
    grid:Section(L["When to show it"], "cd-when", true)

    -- READ WITHOUT CREATING, written on the first WRITE. Store's promise is
    -- that nothing is rewritten, and a bar that grew an empty `show` table by
    -- being looked at is a rewrite - the same rule GradientRows follows one
    -- file over.
    local function Rule(key, fallback)
        return function()
            local bar = Bar()
            local rule = type(bar) == "table" and bar.show or nil
            local value = type(rule) == "table" and rule[key] or nil
            if value == nil then return fallback end
            return value
        end
    end

    local function Write(key)
        return function(value)
            local bar = Bar()
            if type(bar) ~= "table" then return end
            if type(bar.show) ~= "table" then bar.show = {} end
            bar.show[key] = value
            Refresh()
        end
    end

    local mode = Rule("mode", "always")
    UI.Dropdown(grid:FullRow(L["Show"], { controlWidth = 190 }),
        ns.SHOW_MODES, mode, Write("mode"), { apply = Refresh })

    -- THE ROWS THAT ONLY MEAN ANYTHING UNDER "Only when...".
    --
    -- SetRelevant rather than hidden: a rule row is not a row you might want,
    -- it is a row about a mode you have not chosen - and somebody who finds
    -- no row at all concludes the addon cannot do it. Same decision, same
    -- word, as the reminders page.
    local ruleRows = {}
    local function Keep(row)
        if row then ruleRows[#ruleRows + 1] = row end
        return row
    end

    -- The four conditions carry a mark each for the reason the six places
    -- below do: they are one kind of thing, four times over, and the word is
    -- otherwise the only thing telling them apart.
    Keep(UI.Dropdown(grid:FullRow(L["Combat"],
        { controlWidth = 190, icon = "cond-combat" }),
        ns.SHOW_COMBAT, Rule("combat", "any"), Write("combat"),
        { apply = Refresh }))
    Keep(UI.Dropdown(grid:FullRow(L["Group"],
        { controlWidth = 190, icon = "cond-group" }),
        ns.SHOW_GROUP, Rule("group", "any"), Write("group"),
        { apply = Refresh }))
    Keep(UI.Dropdown(grid:FullRow(L["Target"],
        { controlWidth = 190, icon = "cond-target" }),
        ns.SHOW_TARGET, Rule("target", "any"), Write("target"),
        { apply = Refresh }))
    Keep(UI.Dropdown(grid:FullRow(L["Rested"],
        { controlWidth = 190, icon = "cond-rested" }),
        ns.SHOW_RESTING, Rule("resting", "any"), Write("resting"),
        { apply = Refresh }))

    -- ONE SWITCH PER PLACE, not a multi-select: six switches whose state you
    -- can see beat one control you have to open to find out what is in it.
    --
    -- Written as FALSE and never as nil - a missing key reads as "allowed"
    -- (see ns.Visibility's Allows), so unticking a place by clearing the key
    -- would silently undo itself.
    for _, place in ipairs(ns.SHOW_WHERE) do
        Keep(UI.Toggle(grid:FullRow(place.text,
            { controlWidth = 124, icon = place.icon }),
            function()
                local bar = Bar()
                local where = type(bar) == "table" and type(bar.show) == "table"
                    and bar.show.where or nil
                -- NO STORED LIST MEANS EVERYWHERE, which is what the
                -- evaluator does with it. A switch that read "off" for a bar
                -- that shows everywhere would be six lies on one screen.
                if type(where) ~= "table" then return true end
                if where[place.key] == nil then return true end
                return where[place.key] and true or false
            end,
            function(value)
                local bar = Bar()
                if type(bar) ~= "table" then return end
                if type(bar.show) ~= "table" then bar.show = {} end
                if type(bar.show.where) ~= "table" then
                    -- SEEDED FULL on the first tick, because the stored table
                    -- is read as a filter: writing only the one key somebody
                    -- just switched OFF would leave a table that allows
                    -- nothing else, and the bar would vanish from five places
                    -- nobody touched.
                    local seeded = {}
                    for _, entry in ipairs(ns.SHOW_WHERE) do
                        seeded[entry.key] = true
                    end
                    bar.show.where = seeded
                end
                bar.show.where[place.key] = value and true or false
                Refresh()
            end))
    end

    -- WHAT "DOES NOT APPLY" LOOKS LIKE, and it really is a fraction.
    --
    -- Rule 4 allows a claimed frame alpha 1 and nothing else, so this cannot
    -- be spent on the frames - but Look.Apply already solved that for the
    -- bar's own Opacity with a veil texture on our own chrome, and Render
    -- multiplies this into the same number. Nought is the frame let go of
    -- entirely; anything above it is a ghost you can still arrange against.
    Keep(UI.Slider(grid:FullRow(L["Otherwise"], { controlWidth = 124 }), {
        min = 0, max = 1, step = 0.05,
        -- `scale`, and it is not decoration: the value box is typed into as
        -- well as dragged, and without it a typed 55 is stored as 55, clamps
        -- to 1, and the fade silently stops working. 4.82.0 shipped this row
        -- without it for a release.
        scale = 100,
        format = function(value)
            if (value or 0) <= 0 then return L["gone"] end
            return string.format("%d%%", math.floor((value or 0) * 100 + 0.5))
        end,
        get = Rule("hiddenAlpha", 0),
        set = Write("hiddenAlpha"),
        apply = Refresh,
    }))

    -- WHY IT IS NOT ON SCREEN RIGHT NOW, in the evaluator's own words.
    --
    -- Asked of ns.Visibility:Explain rather than worked out here, so the
    -- panel and the bar can never disagree about which rule won - the exact
    -- failure 4.82.0 had, where the editor named "not in this kind of place"
    -- in the one case the evaluator lets the bar through.
    local why = grid:Note("")

    OnRefresh(grid, function()
        local on = mode() == "rules"
        for _, row in ipairs(ruleRows) do row:SetRelevant(on) end

        local bar = Bar()
        local reason = bar and V and V:Explain(bar) or nil
        if reason then
            why:SetText("|cffff7a3dRight now:|r " .. reason)
        else
            why:SetText("|cff888888Every rule has to agree. One you have not "
                .. "set cannot be the reason something is missing.|r")
        end
    end)
end

function Page:BuildPage(page, width)
    local L = ns.L

    ---------------------------------------------------------------------
    -- THE PAGE, IN TWO HALVES. His own layout, twice asked for: "teile das
    -- fenster in der mitte, links untereinander alle bars, rechts alle
    -- einstellungen", and then "ich fand es vorher besser, wo ich alle bars
    -- als live view untereinander hatte."
    --
    --   left   every bar as a live card, scrolling, one under the other
    --   right  the tab strip and the settings for the one you picked
    --
    -- THERE IS NO PREVIEW BAND ANY MORE. The cards ARE the preview, so a copy
    -- of the selected one across the top of the page was the same picture
    -- twice - and the one at the top was the one that could not be compared
    -- with anything.
    ---------------------------------------------------------------------
    local left = CreateFrame("Frame", nil, page)
    left:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
    left:SetWidth(CARD_W + 14)

    local scroll, column = UI.ScrollArea(left, CARD_W)
    BuildCards(column)

    -- The hairline between the halves. It is the only thing saying the left
    -- column is a different kind of thing from the right one.
    local split = page:CreateTexture(nil, "ARTWORK")
    split:SetColorTexture(C.separator[1], C.separator[2], C.separator[3], 1)
    split:SetWidth(1)
    split:SetPoint("TOPLEFT", left, "TOPRIGHT", CARD_GAP / 2, 0)
    split:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", CARD_GAP / 2, 0)

    local right = CreateFrame("Frame", nil, page)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", CARD_GAP, 0)
    right:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)

    local strip
    local settings = CreateFrame("Frame", nil, right)
    settings:SetPoint("TOPLEFT", right, "TOPLEFT", 0, -(34 + UI.PAD))
    settings:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", 0, 0)

    local pageWidth = width - CARD_W - 14 - CARD_GAP
    local grid = UI.Page(settings, pageWidth,
        { tooltipNotes = true, single = true })
    grid.page = page
    grid.cards = column

    ---------------------------------------------------------------------
    -- FIVE SHORT PAGES INSTEAD OF ONE OF TWENTY-THREE HEADINGS.
    --
    -- Folding sections were the answer to the 2 710-line page and on their own
    -- were not enough: twenty-three of them, all shut, is a screen with
    -- nothing on it but a list of things it will not show you. Owner, with the
    -- picture: "well, damit kann man nicht arbeiten."
    ---------------------------------------------------------------------
    grid:Tab(L["Bars"])
    BuildArrangement(grid)
    BuildSize(grid)

    -- WAVES 4 AND 5. Their own file, because eighteen look keys, four text
    -- elements, twenty effects and eleven fill settings on this one would be
    -- the 2 710-line page again - which the owner named as the defect. Each
    -- one opens its own tab.
    local bar = Page.Current()
    ns.OptionsCooldownsBar.BuildLook(grid, bar)
    ns.OptionsCooldownsBar.BuildText(grid, bar)
    ns.OptionsCooldownsBar.BuildEffects(grid, bar)
    ns.OptionsCooldownsBar.BuildFill(grid, bar)

    BuildWhen(grid)

    -- WITH NO BARS THERE IS NOTHING TO SET.
    --
    -- Every control on the right reads the SELECTED bar, and with none there
    -- is nothing to read - so the sliders showed empty boxes and the menus
    -- showed empty buttons, and a menu only filled in once you had picked
    -- something in it. That reads as a broken page rather than as an empty
    -- one. So the settings stand down and say what to do instead, which is
    -- the + at the top of the column.
    local none = UI.Hint(right, L["Nothing to set up yet. Press + at the top "
        .. "of the list to make your first bar."])
    none:SetPoint("TOPLEFT", right, "TOPLEFT", 0, -(34 + UI.PAD))
    none:SetPoint("TOPRIGHT", right, "TOPRIGHT", 0, -(34 + UI.PAD))
    none:SetJustifyV("TOP")
    none:Hide()

    strip = UI.TabStrip(right, grid.tabs, function(name)
        grid:ShowTab(name)
        strip:Select(name)
    end)
    strip:SetPoint("TOPLEFT", right, "TOPLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", right, "TOPRIGHT", 0, 0)
    grid.strip = strip

    -- LAID OUT HERE, not left to OnSizeChanged. A tab is created with no width
    -- and no x, so a strip that was never laid out has tabs that exist, answer
    -- to clicks nobody can aim at, and are invisible - which shipped once on
    -- the co-tank inspector.
    grid.tab = grid.tabs[1]
    strip:Layout()
    strip:Select(grid.tabs[1])

    -- Grid:Layout is what PLACES every row, and Options.PaintView ends in
    -- `if page.Refresh then page.Refresh() end` - so with that field nil,
    -- Grid:Refresh never runs, no row refreshes, and no card is ever redrawn.
    grid:Layout()
    column.Refresh()
    if scroll.Update then scroll.Update() end

    -- AFTER the first refresh, never before: the delete button belongs to a
    -- card and there is no card until the column has drawn one. Named so the
    -- desk guard that asks "does this page offer a way to delete a bar" finds
    -- one - a guard that cannot find the control reports it absent, and
    -- absent prints the same green as passing.
    grid.deleteButton = column.deleteButton
    grid.addButton = column.addButton
    page.Refresh = function()
        column.Refresh()
        if scroll.Update then scroll.Update() end

        local current = Page.Current()
        local has = current ~= nil
        strip:SetShown(has)
        settings:SetShown(has)
        none:SetShown(not has)

        -- THE FILL TAB ONLY WHERE THERE IS A FILL. Re-decided on every pass
        -- rather than at build time: this page is built ONCE, and the answer
        -- changes with the selected bar and with what is dropped onto it.
        local fill = L["Fill"]
        strip:SetTabShown(fill, HasFill(current))
        if not HasFill(current) and grid.tab == fill then
            -- STOOD ON A TAB THAT JUST LEFT. Without this the settings half
            -- shows the fill rows with nothing on the strip marked, which
            -- reads as a page that has lost its place.
            grid:ShowTab(grid.tabs[1])
            strip:Select(grid.tabs[1])
        end
        strip:Layout()
        -- REFRESHED EVEN WHILE HIDDEN. A hidden grid still has to be right
        -- the moment it is shown again, and skipping it here is how a page
        -- comes back wearing the last bar's values.
        grid:Refresh()
    end

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
