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
local CARD_W = 330
local CARD_GAP = 22
local CARD_HEAD = 26
local CARD_PAD = 10
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

    local wanted = opts.width or opts.size or 40
    local size = UI.PreviewSize(wanted, rows, columns,
        CARD_W - CARD_PAD * 2, PREVIEW_MAX_H, gap, MIN_SLOT)

    -- The height follows the width by the SAME ratio, so a 250x24 bar previews
    -- as a 250x24 bar and not as a 250 square.
    local ratio = (wanted > 0) and (size / wanted) or 1
    local height = math.max(MIN_SLOT, math.floor((opts.size or 40) * ratio))
    return size, gap, height
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
        card.remove:SetPoint("TOPRIGHT", card.toggle, "TOPLEFT", -6, -1)

        card.copy = UI.GhostButton(card, ns.L["Duplicate"], function()
            local bars = Bars()
            local made = card.dkBar and bars and bars.Duplicate(card.dkBar.id)
            if made then Page.barID = made.id end
            Refresh()
        end)
        card.copy:SetPoint("TOPRIGHT", card.remove, "TOPLEFT", -4, 0)

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

        local y = 26
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
            card:SetHeight(CARD_HEAD + 4 + card.well:GetHeight() + CARD_PAD)

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
-- multiplied out here. Capacity also counts a pick sitting past the last
-- place, which is what keeps "narrowing a bar never throws a pick away" true
-- on this page as well as in the renderer.
local function Places()
    local store, bar = Store(), Bar()
    if not (store and bar) then return 1 end
    return math.max(1, store.Capacity(bar))
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
    -- A real write to Across rather than a rule that overrides it, so the
    -- control still says what the bar is doing and dragging it back to four
    -- across is allowed. A bar 200 wide beside another one is not a layout
    -- anybody meant to ask for; it is the default nobody changed.
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

    -- HOW MANY PLACES, AND HOW MANY OF THEM PER LINE. Two numbers, not a
    -- rectangle. See Store.Capacity: `cellCount` is the truth and Across is
    -- the view of it, exactly as Model.lua's own header puts it - "the list
    -- is the truth and the columns are the view".
    UI.Slider(grid:Row(L["Places"]), {
        min = 1, max = 40, step = 1,
        get = function() return Places() end,
        set = function(value) Set("cellCount", value) end,
    })
    UI.Slider(grid:Row(L["Across"]), {
        min = 1, max = 20, step = 1,
        get = function() return Number("columns", 1) end,
        set = function(value) Set("columns", value) end,
    })

    -- DOWN IS A VIEW OF PLACES, and writing it writes places.
    --
    -- It is not a third number: lines are what you get when you wrap Places
    -- every Across, so reading it is that division and setting it to three
    -- is another way of saying "three lines' worth of places". Two controls
    -- over one stored number and no way for them to disagree - which is the
    -- whole reason the pair could not describe seven places before.
    UI.Slider(grid:Row(L["Down"]), {
        min = 1, max = 20, step = 1,
        get = function()
            local across = math.max(1, Number("columns", 1))
            return math.max(1, math.ceil(Places() / across))
        end,
        set = function(value)
            Set("cellCount", math.max(1, Number("columns", 1)) * value)
        end,
    })
    grid:Note(L["Places is how many the bar has and across is how many of "
        .. "them sit on a line; down is what that comes to. A spell already "
        .. "sitting past the last place keeps its cell - narrowing a bar "
        .. "never throws a pick away."])

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
-- Who else is doing this
---------------------------------------------------------------------------
local function BuildRivals(grid)
    local L = ns.L

    local rivals = ns.Cooldowns and ns.Cooldowns.Rivals
    local others = rivals and rivals.Others() or {}

    -- THE SECTION ONLY EXISTS WHEN THERE IS A CONFLICT.
    --
    -- It used to open with a heading and the sentence "Nothing else on this
    -- account is managing them", which is a paragraph that costs a reader
    -- exactly as much as a real one and tells them about a problem they do
    -- not have. Owner, with a picture of it: "das kann raus."
    --
    -- Built at page-build time, and that is a real limit rather than an
    -- oversight: this page is built once, so an addon enabled later in the
    -- session is noticed on the next reload. Enabling one already requires a
    -- reload, so there is no moment where the two disagree.
    if #others > 0 then
        grid:Section(L["Who is managing your cooldowns"], "rivals", true)
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
    end

    -- HOW IT DECIDED USED TO BE WRITTEN OUT HERE, and it is gone. Owner,
    -- 2026-08-15, with a picture of this section: "der text kann raus."
    --
    -- He is right, and the reason is worth keeping: it explained the METHOD
    -- ("read from what each addon says about itself in its own description")
    -- to somebody who has just been told there is nothing to worry about.
    -- A paragraph about how a check works belongs next to a check that found
    -- something; over a clean answer it is just noise on the way past.

    ---------------------------------------------------------------------
    -- What Blizzard's own Cooldown Manager knows
    ---------------------------------------------------------------------
    grid:Section(L["Blizzard's Cooldown Manager"], "blizzard", true)

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

    grid:Tab(L["Blizzard"])
    BuildRivals(grid)

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

        local has = Page.Current() ~= nil
        strip:SetShown(has)
        settings:SetShown(has)
        none:SetShown(not has)
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
