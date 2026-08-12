---------------------------------------------------------------------------
-- OptionsRaidBar.lua - the Raid Bar page
--
-- The externals page's shape, and deliberately so: the owner asked for "das
-- bewaehrte layout wo ich mir die bar zusammen stellen kann", and this addon
-- already has one - a lattice in a sticky band at the top, the list you pick
-- from in the third column, the settings under it.
--
-- Two pages that do the same thing must not be two different pictures. What
-- is different here is what the list holds: a marker is not a spell, so the
-- rows draw a texture and a word rather than a spell name and a cooldown.
---------------------------------------------------------------------------
local _, ns = ...

local UI = ns.UI
local C = UI.C

local Page = {}
ns.OptionsRaidBar = Page

local SLOT, GAP = 40, 8
local MIN_SLOT = 22
local BAND_MAX_H = 200

local function Cfg() return ns.RaidBar.Config() end
local function Apply() ns.RaidBar.Refresh() end

-- The same rule the externals preview uses, and it is the same function's
-- worth of arithmetic - a preview that cannot fit its lattice shrinks it
-- rather than clipping, because the SHAPE is what is being decided.
function Page.PreviewSize(rows, columns, availableWidth, availableHeight)
    local byWidth = (availableWidth - (columns - 1) * GAP) / columns
    local byHeight = (availableHeight - (rows - 1) * GAP) / rows
    local size = math.floor(math.min(SLOT, byWidth, byHeight))
    return math.max(MIN_SLOT, size)
end

Page.selected = nil

function Page:BuildPage(page, width)
    local L = ns.L
    local grid = UI.Page(page, width, { tooltipNotes = true, sticky = true })

    ---------------------------------------------------------------------
    -- What you have put on it
    ---------------------------------------------------------------------
    local band = grid.sticky
    UI.Fill(band, "BACKGROUND", C.windowBg)

    local BAND_HEAD = 32

    local bandTitle = UI.Eyebrow(band, L["Your raid bar"])
    bandTitle:SetPoint("TOPLEFT", band, "TOPLEFT", 0, -10)

    local bandRule = band:CreateTexture(nil, "ARTWORK")
    bandRule:SetColorTexture(C.separator[1], C.separator[2], C.separator[3], 1)
    bandRule:SetHeight(1)
    bandRule:SetPoint("BOTTOMLEFT", band, "BOTTOMLEFT", 0, 0)
    bandRule:SetPoint("BOTTOMRIGHT", band, "BOTTOMRIGHT", -14, 0)

    local host = CreateFrame("Frame", nil, band)
    host:SetPoint("TOPLEFT", band, "TOPLEFT", 0, -BAND_HEAD)
    host:SetPoint("TOPRIGHT", band, "TOPRIGHT", -14, -BAND_HEAD)
    host:SetHeight(SLOT)

    local slots = {}
    local function SlotAt(index)
        if slots[index] then return slots[index] end

        local slot = UI.SpellSlot(host, {
            size = SLOT,
            get = function() return ns.RaidBar.ActionAt(index) end,
            texture = function(key)
                local entry = ns.RaidBar.Get(key)
                return entry and entry.texture or nil
            end,
            atlas = function(key)
                local entry = ns.RaidBar.Get(key)
                return entry and entry.atlas or nil
            end,
            -- A marker has no spell tooltip to borrow, so the slot writes its
            -- own: the name the client calls it, which is the word the raid
            -- leader just said out loud.
            tooltip = function(tooltip, key)
                local entry = ns.RaidBar.Get(key)
                if not entry then return false end
                tooltip:ClearLines()
                tooltip:AddLine(ns.RaidBar.Label(entry))
                return true
            end,
            onEmptyClick = function()
                Page.selected = (Page.selected ~= index) and index or nil
                ns.Options:Refresh()
            end,
            onClear = function()
                ns.RaidBar.ClearSlot(index)
                ns.Options:Refresh()
            end,
        })
        slot:HookScript("OnClick", function(_, button)
            if button ~= "LeftButton" then return end
            if ns.RaidBar.ActionAt(index) then
                Page.selected = (Page.selected ~= index) and index or nil
                ns.Options:Refresh()
            end
        end)
        slots[index] = slot
        return slot
    end

    band.Fit = function()
        local cfg = Cfg()
        local count = ns.RaidBar.Count()
        local down = cfg.growth == "down"
        local size = Page.PreviewSize(cfg.rows, cfg.columns, width - 28,
            BAND_MAX_H)

        for index = 1, count do
            local slot = SlotAt(index)
            local column, line = ns.LatticeCell(index, cfg.rows, cfg.columns,
                down)
            slot:SetSize(size, size)
            slot:ClearAllPoints()
            slot:SetPoint("TOPLEFT", host, "TOPLEFT",
                column * (size + GAP), -line * (size + GAP))
        end
        for index = count + 1, #slots do slots[index]:Hide() end

        host:SetHeight(cfg.rows * size + (cfg.rows - 1) * GAP)
        band:SetHeight(BAND_HEAD + host:GetHeight() + 10)
    end
    band.Fit()

    grid:Note("Pick from the list on the right. Right-click a place to empty "
        .. "it. To put the bar somewhere on your screen, open "
        .. "|cffffd100Edit mode|r at the top of the list on the left.")

    -- THE ONE SENTENCE NOBODY WOULD GUESS, and it is on the page rather than
    -- in a tooltip because it explains a delay somebody will otherwise report
    -- as a bug: the marker buttons are the game's own protected kind, and the
    -- game freezes those for the length of a fight.
    grid:Note("|cffffd100Marker, world marker and ping buttons are the game's "
        .. "own protected kind|r - the addon cannot press them for you, and "
        .. "the bar cannot be rearranged while you are in combat. Changes made "
        .. "in a fight appear the moment it ends.")

    ---------------------------------------------------------------------
    -- The bar
    ---------------------------------------------------------------------
    grid:Section(L["The bar"])

    local function Relayout() ns.Options:Refresh() end

    UI.Slider(grid:Row(L["Rows"]), {
        get = ns.RaidBar.Rows, set = ns.RaidBar.SetRows,
        min = 1, max = ns.RaidBar.MAX_ROWS, step = 1, apply = Relayout,
    })

    UI.Slider(grid:Row(L["Columns"]), {
        get = ns.RaidBar.Columns, set = ns.RaidBar.SetColumns,
        min = 1, max = ns.RaidBar.MAX_COLUMNS, step = 1, apply = Relayout,
    })
    grid:Note(L["Rows times columns is how many places there are."])

    UI.Dropdown(grid:Row(L["Runs"]), {
        { value = "right", text = L["Across"], icon = "dir-left-right" },
        { value = "down",  text = L["Down"],   icon = "dir-top-bottom" },
    }, function() return Cfg().growth or "right" end,
        function(value) Cfg().growth = value end, { apply = Relayout })

    UI.Slider(grid:Row(L["Icon size"]), {
        get = function() return Cfg().size or 26 end,
        set = function(value) Cfg().size = value end,
        min = 16, max = 48, step = 1, apply = Apply,
    })
    grid:Note(L["How big each button is on your screen."])

    UI.Slider(grid:Row(L["Spacing"]), {
        get = function() return Cfg().gap or 2 end,
        set = function(value) Cfg().gap = value end,
        min = 0, max = 12, step = 1, apply = Apply,
    })
    grid:Note(L["The gap between two icons."])

    UI.Toggle(grid:Row(L["Only in a group"]),
        function() return Cfg().onlyInGroup ~= false end,
        function(value) Cfg().onlyInGroup = value and true or false; Apply() end)
    grid:Note(L["On your own there is nobody to ask, so it stays away."])

    UI.Toggle(grid:Row(L["Only in an instance"]),
        function() return Cfg().onlyInInstance and true or false end,
        function(value) Cfg().onlyInInstance = value and true or false; Apply() end)
    grid:Note("Out in the world there is nothing to mark. Off, the bar is "
        .. "there whenever you are in a group.")

    ---------------------------------------------------------------------
    -- The pull timer
    ---------------------------------------------------------------------
    grid:Section(L["Pull timer"])

    UI.Slider(grid:Row(L["Seconds"]), {
        get = function() return Cfg().pullSeconds or 10 end,
        set = function(value) Cfg().pullSeconds = value end,
        min = 3, max = 30, step = 1,
    })

    -- WHY THERE IS NO "ALSO TELL BIGWIGS" SWITCH, said on the page because
    -- the absence is the surprising part.
    grid:Note("The countdown is the game's own - the one Blizzard added for "
        .. "exactly this - so a boss mod picks it up by itself and everybody "
        .. "without one still sees the numbers. Right-click the Pull button on "
        .. "the bar to cancel it. The game refuses to start one in combat.")

    ---------------------------------------------------------------------
    -- Keys
    ---------------------------------------------------------------------
    grid:Section(L["Keys"])

    grid:Note("The first |cffffd100" .. ns.RaidBar.KEYS .. "|r places on the "
        .. "bar can carry a key, set in the game's own key list under "
        .. "|cffffd100ZwoelfStuff|r. The key belongs to the PLACE, not to what "
        .. "is in it - so rearranging the bar moves what each key does.")

    ---------------------------------------------------------------------
    -- Look
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

    grid:Section(L["Look"])

    Slide(L["Scale"], "scale", 0.5, 2, 0.05, Percent, 100)
    Slide(L["Opacity"], "alpha", 0, 1, 0.05, Percent, 100)

    grid:Section(L["Border"])

    Slide(L["Thickness"], "borderSize", 0, 4, 1)

    UI.Swatch(grid:Row(L["Colour"]),
        function()
            local colour = Cfg().borderColor or { 0, 0, 0 }
            return colour[1], colour[2], colour[3]
        end,
        function(r, g, b) Cfg().borderColor = { r, g, b } end, Apply)

    UI.MediaPicker(grid:FullRow(L["Texture"],
        { controlWidth = 190, icon = "media-border" }), "border",
        function() return Cfg().borderTexture end,
        function(value) Cfg().borderTexture = value end, Apply)

    grid:Section(L["Backdrop"])

    UI.Toggle(grid:Row(L["Show"]),
        function() return Cfg().backdrop ~= false end,
        function(value) Cfg().backdrop = value and true or false; Apply() end)

    UI.Swatch(grid:Row(L["Colour"]),
        function()
            local colour = Cfg().backdropColor or { 0, 0, 0 }
            return colour[1], colour[2], colour[3]
        end,
        function(r, g, b) Cfg().backdropColor = { r, g, b } end, Apply)

    Slide(L["Opacity"], "backdropAlpha", 0, 1, 0.05, Percent, 100)

    grid:Buttons({
        { text = "What a press would send",
          onClick = function() ns.RaidBar:Dump() end },
    }, 14)

    grid:Layout()

    page.Refresh = function()
        local count = ns.RaidBar.Count()
        band.Fit()
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
-- The third column: every button there is, grouped
---------------------------------------------------------------------------
function Page:BuildSide(sideHost, pad)
    local L = ns.L
    local side = CreateFrame("Frame", nil, sideHost)
    side:SetAllPoints(sideHost)
    side:Hide()

    local title = UI.Label(side, L["Every button"], UI.FS.card, C.text)
    title:SetPoint("TOPLEFT", side, "TOPLEFT", pad, -18)

    local hint = UI.Label(side, L["Click one to put it on your bar."],
        UI.FS.meta, C.textFaint)
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

    local listHost = CreateFrame("Frame", nil, side)
    listHost:SetPoint("TOPLEFT", side, "TOPLEFT", pad, -(UI.HEADER_H + 16))
    listHost:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -pad, pad)

    local rowWidth = UI.INSPECTOR_W - pad * 2 - 8
    local _, content = UI.ScrollArea(listHost, rowWidth, 8)

    local rows = {}
    local y, lastGroup = 0, nil

    for _, entry in ipairs(ns.RaidBar.ACTIONS) do
        if entry.group ~= lastGroup then
            lastGroup = entry.group
            local heading = UI.Eyebrow(content, L[entry.group])
            heading:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(y + 8))
            y = y + 26
        end

        local row = UI.SpellRow(content, rowWidth, 30)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        row.actionKey = entry.key
        row:SetScript("OnClick", function()
            if ns.RaidBar.IsPicked(entry.key) then
                ns.RaidBar.Drop(entry.key)
            else
                local landed = ns.RaidBar.Pick(entry.key, Page.selected)
                if not landed then
                    ns.Print("|cffff8040Every place is full.|r Raise "
                        .. "|cffffd100Rows|r or |cffffd100Columns|r, or "
                        .. "right-click a place to empty it.")
                else
                    Page.selected = nil
                end
            end
            ns.Options:Refresh()
        end)
        rows[#rows + 1] = row
        y = y + 31
    end

    content:SetHeight(math.max(1, y))

    side.Refresh = function()
        for _, row in ipairs(rows) do
            local entry = ns.RaidBar.Get(row.actionKey)
            local picked = ns.RaidBar.IsPicked(row.actionKey)

            if entry and entry.atlas and row.icon.SetAtlas then
                row.icon:SetAtlas(entry.atlas)
            else
                row.icon:SetTexture(entry and entry.texture or ns.WHITE)
            end
            row.name:SetText(ns.RaidBar.Label(entry))
            row:SetUsed(picked and "on bar" or nil, true)
            row:SetTrailing(picked and "On bar" or "", picked and "cell" or nil)
        end
    end

    return side
end
