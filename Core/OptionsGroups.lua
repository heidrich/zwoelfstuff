---------------------------------------------------------------------------
-- OptionsGroups - the Groups page and the spell browser.
--
-- Kept out of Options.lua because it is the largest page by a wide margin: a
-- tracking group has around forty settings, and the browser it opens is a
-- window in its own right.
---------------------------------------------------------------------------
local _, ns = ...

local UI = ns.UI
local C = UI.C
local Groups = ns.Groups

ns.OptionsGroups = {}
local Page = ns.OptionsGroups

---------------------------------------------------------------------------
-- Which group is being edited
---------------------------------------------------------------------------
function Page:Current()
    local index = self.index or 1
    if index > #ns.db.groups then index = #ns.db.groups end
    if index < 1 then index = 1 end
    self.index = index
    return index, ns.db.groups[index]
end

function Page:Select(index)
    self.index = index
    ns.Options:Refresh()
end

local function Apply()
    local index = Page:Current()
    Groups:Refresh(index)
    ns.Options:Refresh()
end

-- Debounced twin, for the sliders that get dragged.
local function ApplySoon()
    local index = Page:Current()
    Groups:RefreshSoon(index)
end

---------------------------------------------------------------------------
-- The spell browser
--
-- Everything in it comes from Catalog, which reads the live client: the
-- talents you actually picked, every spellbook line including the specs you
-- are not playing, and Blizzard's own Cooldown Manager set.
---------------------------------------------------------------------------
local Browser = {}
ns.SpellBrowser = Browser

local ROW_H = 22

local function BrowserRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints(row)
    row.highlight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.15)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.tag = UI.Label(row, "", 11, C.accent)
    row.tag:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.tag:SetWidth(14)

    row.name = UI.Label(row, "", 12, C.text)
    row.name:SetPoint("LEFT", row.tag, "RIGHT", 2, 0)
    row.name:SetWordWrap(false)

    row.id = UI.Label(row, "", 11, C.textFaint)
    row.id:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.id:SetJustifyH("RIGHT")
    row.id:SetWidth(70)
    row.name:SetPoint("RIGHT", row.id, "LEFT", -8, 0)

    return row
end

function Browser:Create()
    if self.frame then return end

    local frame = CreateFrame("Frame", "ZwoelfStuffSpellBrowser", UIParent)
    frame:SetSize(460, 560)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    UI.Fill(frame, "BACKGROUND", C.windowBg, 0.98)
    local edge = ns.CreateBorder(frame, 1, "BORDER")
    edge:SetColor(0.22, 0.24, 0.29, 1)

    local title = UI.Label(frame, "Pick a spell", 17, C.text)
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)

    local target = UI.Label(frame, "", 11, C.accent)
    target:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    target:SetWordWrap(false)
    frame.target = target

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(26, 26)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    local closeLabel = UI.Label(close, "X", 13, C.textDim)
    closeLabel:SetPoint("CENTER", close, "CENTER", 0, 0)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- Source picker + search ---------------------------------------------
    -- Built through the shared Row so the dropdown lines up exactly as it
    -- does on every options page.
    local pickerRow = UI.Row(frame, "Source", { controlWidth = 300 })
    pickerRow:SetWidth(428)
    pickerRow:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -66)

    UI.Dropdown(pickerRow,
        function()
            local out = {}
            for index, section in ipairs(ns.Catalog:Get()) do
                out[#out + 1] = {
                    value = index,
                    text  = section.title .. (section.isActive and "  *" or ""),
                }
            end
            return out
        end,
        function() return Browser.section end,
        function(value) Browser.section = value end,
        { apply = function() Browser:Fill() end, emptyText = "Loading..." })
    frame.pickerRow = pickerRow

    local search = UI.Input(frame, 428, function() Browser:Fill() end, false)
    search:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -114)
    search.input:SetScript("OnTextChanged", function() Browser:Fill() end)
    frame.search = search

    local searchHint = UI.Label(search, "", 11, C.textFaint)
    searchHint:SetPoint("RIGHT", search, "RIGHT", -8, 0)
    searchHint:SetText("search name or ID")
    frame.searchHint = searchHint

    -- List ----------------------------------------------------------------
    local list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -148)
    list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 44)
    UI.Fill(list, "BACKGROUND", C.sidebarBg)

    local scroll = CreateFrame("ScrollFrame", nil, list, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", list, "TOPLEFT", 2, -2)
    scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -24, 2)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(400, 1)
    scroll:SetScrollChild(content)
    frame.scroll, frame.content = scroll, content

    local footer = UI.Label(frame, "", 11, C.textFaint)
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 16)
    footer:SetWidth(428)
    footer:SetWordWrap(false)
    frame.footer = footer

    frame.rows = {}
    self.frame = frame

    table.insert(UISpecialFrames, "ZwoelfStuffSpellBrowser")
end

function Browser:BuildSections()
    local sections = ns.Catalog:Get()
    if not self.section or not sections[self.section] then
        -- Default to the talent list: "what did I actually pick" is the
        -- question this window gets opened with.
        self.section = 1
        for index, section in ipairs(sections) do
            if section.key == "talents" then self.section = index break end
        end
    end
    if self.frame and self.frame.pickerRow.Refresh then
        self.frame.pickerRow.Refresh()
    end
end

function Browser:Fill()
    local frame = self.frame
    if not frame then return end

    local sections = ns.Catalog:Get()
    local section = sections[self.section]
    if not section then
        frame.footer:SetText("The client returned no spells yet.")
        return
    end

    local entries = ns.Catalog:Search(section, frame.search.input:GetText())
    local groupIndex, cfg = ns.OptionsGroups:Current()

    -- Already-picked spells stay listed, greyed and inert, so the list never
    -- changes length under the cursor while you scan it.
    local picked = {}
    if cfg then
        for _, spellID in ipairs(cfg.spells) do picked[spellID] = true end
    end

    local y = 0
    for index, entry in ipairs(entries) do
        local row = frame.rows[index]
        if not row then
            row = BrowserRow(frame.content)
            frame.rows[index] = row
        end

        row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", frame.content, "TOPRIGHT", 0, y)

        if entry.icon then
            row.icon:SetTexture(entry.icon)
            row.icon:SetDesaturated(false)
        else
            row.icon:SetTexture(ns.WHITE)
            row.icon:SetDesaturated(true)
        end

        if picked[entry.id] then
            row.tag:SetText("+")
            row.tag:SetTextColor(0.35, 0.80, 0.40)
            row.name:SetTextColor(C.textFaint[1], C.textFaint[2], C.textFaint[3])
        elseif entry.talented then
            row.tag:SetText("*")
            row.tag:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
            row.name:SetTextColor(C.text[1], C.text[2], C.text[3])
        else
            row.tag:SetText("")
            local dim = entry.passive
            row.name:SetTextColor(
                dim and C.textDim[1] or C.text[1],
                dim and C.textDim[2] or C.text[2],
                dim and C.textDim[3] or C.text[3])
        end

        row.name:SetText(entry.name)
        row.id:SetText(tostring(entry.id))

        row:SetScript("OnClick", function()
            if not ns.db.groups[groupIndex] then return end
            if Groups:AddSpell(groupIndex, entry.id) then
                Browser:Fill()
                ns.Options:Refresh()
            end
        end)
        row:Show()

        y = y - ROW_H
    end

    for index = #entries + 1, #frame.rows do
        frame.rows[index]:Hide()
    end

    frame.content:SetHeight(math.max(1, -y))

    frame.footer:SetText(string.format(
        "%d spells   |cffff7a3d*|r talented   |cff59cc66+|r already in this group%s",
        #entries, section.note and ("   -   " .. section.note) or ""))

    frame.target:SetText(cfg and ("Adding to:  " .. cfg.name) or "|cffff4040No group selected|r")
end

function Browser:Open()
    self:Create()
    ns.Catalog:Get()
    self:BuildSections()
    self:Fill()
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
    self.frame:Show()
    -- Opened to add a spell, so the cursor belongs in the search box: type
    -- the name, click the hit. No second click to get there.
    self.frame.search.input:SetFocus()
end

---------------------------------------------------------------------------
-- The Groups page
---------------------------------------------------------------------------
function Page:Build(page, width)
    -- Group picker bar, pinned above the scrolling body so it never scrolls
    -- away - you always know which group you are editing.
    local bar = CreateFrame("Frame", nil, page)
    bar:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    bar:SetSize(width, 30)
    UI.Fill(bar, "BACKGROUND", C.rowBg)

    -- The picker is also where groups are created and deleted, so there is
    -- one place to go for "which bar am I editing" instead of three controls.
    local picker = UI.Picker(bar, {
        width = 240, height = 24, emptyText = "no groups yet",
        items = function()
            local out = {}
            for index, cfg in ipairs(ns.db.groups) do
                out[#out + 1] = {
                    value = index,
                    text  = cfg.name .. (cfg.enabled and "" or "  (off)"),
                    onDelete = function()
                        if Groups:Remove(index) then
                            Page:Select(math.min(index, #ns.db.groups))
                        end
                    end,
                }
            end
            return out
        end,
        current  = function() return (Page:Current()) end,
        onSelect = function(value) Page:Select(value) end,
        actions = {
            { text = "+  New icon group", onClick = function()
                Page:Select(Groups:Add(nil, "icon"))
            end },
            { text = "+  New bar group", onClick = function()
                Page:Select(Groups:Add(nil, "bar"))
            end },
        },
    })
    picker:SetPoint("LEFT", bar, "LEFT", 6, 0)

    local nameInput = UI.Input(bar, 180, function(text)
        local _, cfg = Page:Current()
        if cfg and text ~= "" then
            cfg.name = text
            ns.Options:Refresh()
        end
    end, false)
    nameInput:SetPoint("LEFT", picker, "RIGHT", 10, 0)

    local nameHint = UI.Hint(bar, "rename, then Enter")
    nameHint:SetPoint("LEFT", nameInput, "RIGHT", 10, 0)

    local unlockBtn = UI.Button(bar, "Unlock all", 96, function()
        local anyUnlocked = false
        for index in ipairs(ns.db.groups) do
            local rt = Groups.runtime[index]
            if rt and rt.anchor.dkUnlocked then anyUnlocked = true end
        end
        Groups:SetAllUnlocked(not anyUnlocked)
        ns.Options:Refresh()
    end)
    unlockBtn:SetHeight(22)
    unlockBtn:SetPoint("RIGHT", bar, "RIGHT", -6, 0)

    -- Body ----------------------------------------------------------------
    local body = CreateFrame("Frame", nil, page)
    body:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -8)
    body:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)

    local grid = UI.Page(body, width, { tooltipNotes = true })

    -- Field accessors bound to whichever group is selected right now.
    local function Get(key)
        return function()
            local _, cfg = Page:Current()
            return cfg and cfg[key]
        end
    end
    local function Set(key)
        return function(value)
            local _, cfg = Page:Current()
            if cfg then cfg[key] = value end
        end
    end

    local function Toggle(label, key, opts, apply)
        return UI.Toggle(grid:Row(label, opts), Get(key), function(value)
            Set(key)(value)
            ;(apply or Apply)()
        end)
    end
    local function Choose(label, key, options, opts, apply)
        return UI.Dropdown(grid:Row(label, opts), options, Get(key), Set(key),
            { apply = apply or Apply })
    end
    local function Slide(label, key, min, max, step, format, apply, opts)
        return UI.Slider(grid:Row(label, opts), {
            get = Get(key), set = Set(key),
            min = min, max = max, step = step, format = format,
            apply = apply or ApplySoon,
        })
    end
    local function Colour(label, key)
        return UI.Swatch(grid:Row(label),
            function()
                local _, cfg = Page:Current()
                local c = cfg and cfg[key] or { 1, 1, 1 }
                return c[1], c[2], c[3]
            end,
            function(r, g, b)
                local _, cfg = Page:Current()
                if cfg then cfg[key] = { r, g, b } end
            end,
            Apply)
    end

    local percent = function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end
    local twoDigits = function(v) return string.format("%.2f", v) end

    -- WHAT ----------------------------------------------------------------
    grid:Section("What to show")

    Toggle("Group enabled", "enabled")
    Toggle("Only auras I applied", "onlyMine")

    Choose("Aura type", "filter", {
        { value = "HELPFUL", text = "Buffs" },
        { value = "HARMFUL", text = "Debuffs" },
    })
    Choose("On unit", "unit", {
        { value = "player", text = "Me" },
        { value = "target", text = "Target" },
        { value = "focus",  text = "Focus" },
        { value = "pet",    text = "Pet" },
    })

    Choose("Order", "layoutMode", {
        { value = "fixed",   text = "My order" },
        { value = "dynamic", text = "Auto, compact" },
    })
    local sortRow = Choose("Auto sorting", "sort", {
        { value = "default",   text = "Default" },
        { value = "important", text = "Important first" },
    })

    grid:Note("My order: one fixed place per spell, gaps stay open, bars can show names. "
        .. "Auto: the game picks and sorts, stays compact, but positions move as auras "
        .. "come and go and no name can be shown.")

    local maxRow = Slide("Auto: how many slots", "max", 1, 20, 1)

    -- STYLE ---------------------------------------------------------------
    grid:Section("Style")

    Choose("Look", "style", {
        { value = "icon", text = "Icons" },
        { value = "bar",  text = "Bars" },
    })
    local iconSizeRow  = Slide("Icon size", "iconSize", 16, 200, 2)
    local barWidthRow  = Slide("Bar width", "barWidth", 60, 600, 5)
    local barHeightRow = Slide("Bar height", "barHeight", 10, 80, 2)

    Slide("Scale", "scale", 0.4, 3, 0.05, twoDigits, Apply)
    Slide("Opacity", "alpha", 0.1, 1, 0.05, percent, Apply)

    -- ARRANGEMENT ---------------------------------------------------------
    grid:Section("Arrangement")

    Choose("Grows", "growthH", {
        { value = "RIGHT", text = "Rightwards" },
        { value = "LEFT",  text = "Leftwards" },
    }, nil, ApplySoon)
    Choose("Rows go", "growthV", {
        { value = "DOWN", text = "Downwards" },
        { value = "UP",   text = "Upwards" },
    }, nil, ApplySoon)
    Choose("Fill along", "axis", {
        { value = "horizontal", text = "Rows first" },
        { value = "vertical",   text = "Columns first" },
    }, nil, ApplySoon)

    Slide("Wrap after", "wrapAfter", 0, 20, 1,
        function(v) return v == 0 and "off" or tostring(v) end)
    Slide("Spacing", "spacing", 0, 40, 1)
    Slide("Row spacing", "lineSpacing", 0, 40, 1)

    grid:Note("Wrap after 0 is one single line. Set it to 1 for a vertical stack, "
        .. "or to 4 for a four-wide grid.")

    -- TEXT ----------------------------------------------------------------
    grid:Section("Text and detail")

    Toggle("Remaining time", "showTimer")
    Toggle("Stacks", "showStacks")
    Toggle("Cooldown swipe", "showSwipe")
    Toggle("Icon on bars", "showIcon")
    local nameRow = Toggle("Spell name on bars", "showName")
    local labelRow = Toggle("Label under icons", "showLabel")

    Choose("Timer position", "timerAnchor", {
        { value = "CENTER", text = "Centre" },
        { value = "BOTTOM", text = "Bottom" },
        { value = "TOP",    text = "Top" },
    })

    local autoSize = function(v) return v == 0 and "auto" or tostring(v) end
    Slide("Timer size", "timerSize", 0, 40, 1, autoSize, Apply)
    Slide("Stack size", "stackSize", 0, 40, 1, autoSize, Apply)
    Slide("Name size", "nameSize", 0, 40, 1, autoSize, Apply)

    -- COLOURS -------------------------------------------------------------
    grid:Section("Colours")

    Colour("Border colour", "borderColor")
    Colour("Bar colour", "barColor")
    Slide("Border thickness", "borderSize", 0, 4, 1, nil, Apply)
    Slide("Backdrop opacity", "backdropAlpha", 0, 1, 0.05, percent, Apply)
    Slide("Bar track opacity", "trackAlpha", 0, 1, 0.02, percent, Apply)

    -- SPELLS --------------------------------------------------------------
    grid:Section("Spells")

    -- The strip IS the preview: what you see here is the order the group
    -- renders in, and you rearrange it by dragging the icons.
    local strip = UI.IconStrip(grid.content, {
        size = 40, spacing = 4, perRow = 12,
        items = function()
            local _, cfg = Page:Current()
            local out = {}
            if not cfg then return out end
            for _, spellID in ipairs(cfg.spells) do
                out[#out + 1] = {
                    id   = spellID,
                    icon = ns.SpellTexture(spellID),
                    name = string.format("%s  |cff888888%d|r",
                        ns.SpellName(spellID) or "unknown to this client", spellID),
                }
            end
            return out
        end,
        onAdd = function() Browser:Open() end,
        onReorder = function(from, to)
            Groups:MoveSpell((Page:Current()), from, to)
            ns.Options:Refresh()
        end,
        onRemove = function(position)
            local index, cfg = Page:Current()
            local spellID = cfg and cfg.spells[position]
            if spellID then
                Groups:RemoveSpell(index, spellID)
                ns.Options:Refresh()
                if Browser.frame and Browser.frame:IsShown() then Browser:Fill() end
            end
        end,
    })
    grid:Wide(strip, 44)

    grid:Note("Click + to add a spell. Drag an icon to move it, right click to remove it. "
        .. "In \"My order\" this is exactly the order the group displays in.")

    local addRow = CreateFrame("Frame", nil, grid.content)
    addRow:SetSize(grid.width, 26)

    local idInput = UI.Input(addRow, 100, function(text)
        local spellID = tonumber(text)
        local index = Page:Current()
        if spellID and spellID > 0 then
            Groups:AddSpell(index, spellID)
            ns.Options:Refresh()
        else
            ns.Print("Enter a numeric spell ID.")
        end
    end, true)
    idInput:SetPoint("LEFT", addRow, "LEFT", 0, 0)

    local idHint = UI.Hint(addRow, "know the ID already? type it here and press Enter")
    idHint:SetPoint("LEFT", idInput, "RIGHT", 10, 0)
    grid:Wide(addRow, 34)

    grid:Layout()

    -- Refresh -------------------------------------------------------------
    page.Refresh = function()
        local _, cfg = Page:Current()
        local hasGroups = cfg ~= nil

        picker.Refresh()
        nameInput:SetEnabled(hasGroups)

        -- With no group selected every accessor returns nil, and a slider
        -- dragged in that state would do arithmetic on it. Park the body
        -- rather than leaving live controls with nothing behind them.
        body:SetShown(hasGroups)
        if not hasGroups then return end

        local anyUnlocked = false
        for i in ipairs(ns.db.groups) do
            local rt = Groups.runtime[i]
            if rt and rt.anchor.dkUnlocked then anyUnlocked = true end
        end
        unlockBtn:SetText(anyUnlocked and "Lock all" or "Unlock all")

        -- Drop what does not apply instead of showing dead controls; the
        -- rows below close up, so the page has no gaps in either mode.
        local isBar = cfg.style == "bar"
        local isFixed = cfg.layoutMode ~= "dynamic"
        iconSizeRow:SetRelevant(not isBar)
        barWidthRow:SetRelevant(isBar)
        barHeightRow:SetRelevant(isBar)
        sortRow:SetRelevant(not isFixed)
        maxRow:SetRelevant(not isFixed)
        -- Names and labels need a fixed slot: in auto mode the engine alone
        -- knows which aura sits in which button.
        nameRow:SetRelevant(isBar and isFixed)
        labelRow:SetRelevant(not isBar and isFixed)

        -- The strip grows a line at a time, so it reports its own height back
        -- to the layout instead of keeping the one it was recorded with.
        strip.dkHeight = strip.Refresh() + 6

        grid:Refresh()
    end
end
