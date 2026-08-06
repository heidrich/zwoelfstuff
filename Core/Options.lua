---------------------------------------------------------------------------
-- Options - the app window.
--
-- Not a settings dialog. You have a set of cooldown bars, you pick one from
-- the rail, and you work on it in the middle while the inspector on the
-- right edits whatever is selected. The secondary pages borrow the middle
-- and hide the inspector.
--
-- Every control comes from the design system in Widgets.lua, so nothing is
-- styled twice and nothing drifts. Pages are built on first view: building
-- all of them at login would cost frames nobody asked to see.
---------------------------------------------------------------------------
local _, ns = ...

local Options = {}
ns.Options = Options

local UI = ns.UI
local C = UI.C
local Bars = ns.Bars

local WINDOW_W, WINDOW_H = 1060, 640
local RAIL_W = 196
local INSPECTOR_W = 236
local PAD = 20

---------------------------------------------------------------------------
-- Shared page helpers
---------------------------------------------------------------------------

-- A strip of buttons that flows like any other block in the grid.
local function ButtonStrip(grid, buttons)
    local strip = CreateFrame("Frame", nil, grid.content)
    strip:SetSize(grid.width, 28)

    local x = 0
    for _, spec in ipairs(buttons) do
        local btn = UI.Button(strip, spec.text, spec.width or 120, spec.onClick, spec.style)
        btn:SetPoint("LEFT", strip, "LEFT", x, 0)
        x = x + (spec.width or 120) + 8
        spec.frame = btn
    end

    grid:Wide(strip, 36)
    return strip
end

---------------------------------------------------------------------------
-- General
---------------------------------------------------------------------------
local function BuildGeneralPage(page, width)
    local grid = UI.Page(page, width)

    grid:Section("Minimap button")
    UI.Toggle(grid:Row("Show the button"),
        function() return ns.db.minimap.show end,
        function(value) ns.MinimapButton:SetShown(value) end)
    UI.Toggle(grid:Row("Lock its position"),
        function() return ns.db.minimap.locked end,
        function(value) ns.db.minimap.locked = value end)

    grid:Note("Left click opens this window, right click toggles the co-tank panel, "
        .. "drag moves it around the minimap edge.")

    grid:Section("Everything")

    local resetArmed = false
    local resetStrip
    resetStrip = ButtonStrip(grid, {
        {
            text = "Reset all settings", width = 160, style = "primary",
            onClick = function()
                -- Two-step, because this throws away every group, position
                -- and colour the user has set.
                if not resetArmed then
                    resetArmed = true
                    resetStrip.reset:SetText("Really reset? Click again")
                    C_Timer.NewTimer(4, function()
                        resetArmed = false
                        if resetStrip.reset then resetStrip.reset:SetText("Reset all settings") end
                    end)
                    return
                end
                resetArmed = false
                resetStrip.reset:SetText("Reset all settings")
                SlashCmdList.DKSTUFF("reset")
            end,
        },
    })
    resetStrip.reset = select(1, resetStrip:GetChildren())

    grid:Note("Restores every default: display, tracking groups, co-tank panel and "
        .. "minimap button. There is no undo.")

    grid:Layout()
    page.Refresh = function() grid:Refresh() end
end

---------------------------------------------------------------------------
-- Aura display (the classic single-buff frame)
---------------------------------------------------------------------------
local MAX_SPELL_ROWS = 6

local function BuildDisplayPage(page, width)
    local grid = UI.Page(page, width)
    local db = function() return ns.db end

    local function Apply() ns.Display:ApplyLayout() end

    grid:Section("Display")

    UI.Dropdown(grid:Row("Look"), {
        { value = "icon", text = "Icon" },
        { value = "bar",  text = "Bar" },
    }, function() return db().mode end,
       function(value) db().mode = value end, { apply = Apply })

    UI.Dropdown(grid:Row("Aura source", { sublabel = "Engine slot, or the proc glow proxy" }), {
        { value = "auto", text = "Engine slot" },
        { value = "glow", text = "Proc glow" },
    }, function() return db().source end,
       function(value) db().source = value end, { apply = Apply })

    UI.Toggle(grid:Row("Always show", { sublabel = "Greyed out while the aura is down" }),
        function() return db().alwaysShow end,
        function(value) db().alwaysShow = value; Apply() end)

    UI.Slider(grid:Row("Greyed-out opacity"), {
        get = function() return db().inactiveAlpha end,
        set = function(value) db().inactiveAlpha = value end,
        min = 0.1, max = 1, step = 0.05, apply = Apply,
        format = function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end,
    })

    grid:Section("Size")

    local iconRow = UI.Slider(grid:Row("Icon size"), {
        get = function() return db().iconSize end,
        set = function(value) db().iconSize = value end,
        min = 20, max = 200, step = 2, apply = Apply,
    })
    local barWRow = UI.Slider(grid:Row("Bar width"), {
        get = function() return db().barWidth end,
        set = function(value) db().barWidth = value end,
        min = 60, max = 600, step = 5, apply = Apply,
    })
    local barHRow = UI.Slider(grid:Row("Bar height"), {
        get = function() return db().barHeight end,
        set = function(value) db().barHeight = value end,
        min = 10, max = 80, step = 2, apply = Apply,
    })
    UI.Slider(grid:Row("Scale"), {
        get = function() return db().scale end,
        set = function(value) db().scale = value end,
        min = 0.4, max = 3, step = 0.05, apply = Apply,
        format = function(v) return string.format("%.2f", v) end,
    })

    grid:Section("Text and effects")

    UI.Toggle(grid:Row("Remaining time", { sublabel = "Drawn by the game engine" }),
        function() return db().showTimer end,
        function(value) db().showTimer = value; Apply() end)
    UI.Toggle(grid:Row("Stacks"),
        function() return db().showStacks end,
        function(value) db().showStacks = value; Apply() end)
    UI.Toggle(grid:Row("Spell name", { sublabel = "Bar look only" }),
        function() return db().showName end,
        function(value) db().showName = value; Apply() end)
    UI.Toggle(grid:Row("Proc glow"),
        function() return db().glow end,
        function(value) db().glow = value end)
    UI.Toggle(grid:Row("Proc sound"),
        function() return db().sound end,
        function(value) db().sound = value end)

    grid:Section("Position")

    local strip = ButtonStrip(grid, {
        { text = "Unlock", width = 110, onClick = function()
            ns.Display:SetUnlocked(ns.db.locked)
        end },
        { text = "Reset position", width = 130, onClick = function()
            ns.Display:ResetPosition()
        end },
        { text = "Test 15s", width = 110, onClick = function()
            ns.Display:StartTest()
        end },
    })
    local lockBtn = select(1, strip:GetChildren())

    grid:Section("Tracked auras")
    grid:Note("The first one present on you wins - the order is a priority list.")

    local rows = {}
    for index = 1, MAX_SPELL_ROWS do
        local row = grid:Row("", { controlWidth = 30 })
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", row, "LEFT", 10, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)

        row.remove = UI.Button(row.slot, "X", 24, nil)
        row.remove:SetHeight(20)
        row.remove:SetPoint("RIGHT", row.slot, "RIGHT", 0, 0)
        rows[index] = row
    end

    local addRow = CreateFrame("Frame", nil, grid.content)
    addRow:SetSize(grid.width, 26)
    local input = UI.Input(addRow, 110, function(text)
        local spellID = tonumber(text)
        if spellID and spellID > 0 then
            ns.Watcher:AddSpell(spellID)
        else
            ns.Print("Enter a numeric spell ID.")
        end
        Options:Refresh()
    end, true)
    input:SetPoint("LEFT", addRow, "LEFT", 0, 0)
    local addHint = UI.Hint(addRow, "spell ID, then Enter")
    addHint:SetPoint("LEFT", input, "RIGHT", 10, 0)
    grid:Wide(addRow, 34)

    grid:Section("Proc glow")
    grid:Note("For auras no addon may read. Log the glows, then set the spell whose "
        .. "action button lights up - not the buff itself.")

    local glowRow = grid:FullRow("Glow source", { controlWidth = 320 })
    local glowInput = UI.Input(glowRow.slot, 110, function(text)
        local spellID = tonumber(text)
        ns.Watcher:SetGlowSpell(spellID and spellID > 0 and spellID or nil)
        Options:Refresh()
    end, true)
    glowInput:SetPoint("RIGHT", glowRow.slot, "RIGHT", 0, 0)

    local glowLog = UI.Button(glowRow.slot, "Log glows", 96, function()
        ns.Watcher:ToggleGlowLog()
    end)
    glowLog:SetHeight(22)
    glowLog:SetPoint("RIGHT", glowInput, "LEFT", -8, 0)

    local glowStatus = UI.Label(glowRow, "", 11, C.accent)
    glowStatus:SetPoint("RIGHT", glowLog, "LEFT", -12, 0)
    glowStatus:SetWordWrap(false)

    UI.Slider(grid:Row("Proc duration"), {
        get = function() return db().glowDuration end,
        set = function(value) db().glowDuration = value end,
        min = 1, max = 120, step = 1,
        format = function(v) return v .. "s" end,
    })

    grid:Layout()

    page.Refresh = function()
        local isBar = ns.db.mode == "bar"
        iconRow:SetRelevant(not isBar)
        barWRow:SetRelevant(isBar)
        barHRow:SetRelevant(isBar)

        lockBtn:SetText(ns.db.locked and "Unlock" or "Lock")

        local glowID = ns.db.glowSpellID
        glowStatus:SetText(glowID
            and string.format("%d  %s", glowID, ns.SpellName(glowID) or "?")
            or "|cff888888not set|r")

        local list = ns.db.spellIDs
        for index = 1, MAX_SPELL_ROWS do
            local row = rows[index]
            local spellID = list[index]
            if spellID then
                local texture = ns.SpellTexture(spellID)
                row.icon:SetTexture(texture or ns.WHITE)
                row.icon:SetDesaturated(not texture)
                row.label:SetText(string.format("%s  |cff888888%d|r",
                    ns.SpellName(spellID) or "unknown to this client", spellID))
                row.remove:SetScript("OnClick", function()
                    ns.Watcher:RemoveSpell(spellID)
                    Options:Refresh()
                end)
                row:SetRelevant(true)
            else
                row:SetRelevant(false)
            end
        end

        grid:Refresh()
    end
end

---------------------------------------------------------------------------
-- Diagnostics
---------------------------------------------------------------------------
local function BuildDiagnosticsPage(page, width)
    local grid = UI.Page(page, width)

    grid:Section("Cooldown Manager")
    grid:Note("Everything on your bars comes from Blizzard's Cooldown Manager - it "
        .. "already knows the spells, binds the auras and has the timing, none of "
        .. "which an addon can do for itself on this patch.")

    ButtonStrip(grid, {
        { text = "What it holds", width = 150, style = "primary", onClick = function()
            ns.CDM:Dump()
        end },
    })

    grid:Section("Is the aura findable right now?")
    grid:Note("Run these WHILE the buff is up. Output goes to your chat frame.")

    ButtonStrip(grid, {
        { text = "Check routes", width = 130, style = "primary", onClick = function()
            ns.Watcher:Check(ns.db.spellIDs[1] or ns.PRIMARY_SPELL_ID)
        end },
        { text = "Full dump", width = 120, onClick = function() ns.Watcher:Dump() end },
        { text = "Readable buffs", width = 130, onClick = function() ns.Watcher:Scan() end },
        { text = "Status", width = 100, onClick = function() ns.Watcher:Status() end },
    })

    grid:Section("This client")

    local cdmRow = grid:FullRow("Cooldown Manager", { controlWidth = 260 })
    local cdmState = UI.Label(cdmRow.slot, "", 12, C.text)
    cdmState:SetPoint("RIGHT", cdmRow.slot, "RIGHT", 0, 0)
    cdmState:SetJustifyH("RIGHT")

    local engineRow = grid:FullRow("Aura engine (12.1)", { controlWidth = 260 })
    local engineState = UI.Label(engineRow.slot, "", 12, C.text)
    engineState:SetPoint("RIGHT", engineRow.slot, "RIGHT", 0, 0)
    engineState:SetJustifyH("RIGHT")

    grid:Note("Patch 12.0 made aura data secret, so an addon cannot identify a buff by "
        .. "ID, name or icon. The sanctioned replacement, Blizzard_AuraContainer, only "
        .. "arrives in 12.1 - until then the Cooldown Manager is the one usable source, "
        .. "which is what this addon is built on.")

    grid:Layout()

    page.Refresh = function()
        cdmState:SetText(ns.CDM:IsAvailable()
            and "|cff40ff40available|r"
            or ("|cffff4040" .. (ns.CDM:UnavailableReason() or "unavailable") .. "|r"))

        -- Engine.lua is parked on a 12.0 client, so ns.Engine is nil here.
        -- Reading it without the guard is a crash, not a missing feature.
        if not ns.Engine then
            engineState:SetText("|cff888888not on this client - parked until 12.1|r")
        elseif ns.Engine:IsAvailable() then
            engineState:SetText("|cff40ff40available|r")
        else
            engineState:SetText("|cffff4040"
                .. (ns.Engine:UnavailableReason() or "unavailable") .. "|r")
        end

        grid:Refresh()
    end
end

---------------------------------------------------------------------------
-- About
---------------------------------------------------------------------------
local function BuildAboutPage(page, width)
    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -22, 0)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width - 22, 1)
    scroll:SetScrollChild(content)

    local author = UI.Label(content, "ZwÃ¶lf  -  EU Destromath", 15, C.accent)
    author:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)

    local version = UI.Label(content, "Version " .. ns.version, 12, C.textDim)
    version:SetPoint("TOPLEFT", author, "BOTTOMLEFT", 0, -6)

    local body = UI.Label(content, table.concat({
        "Blizzard's Cooldown Manager can only show spells that exist in its own",
        "C_CooldownViewer data set. Boiling Point (1265968) is not in that set, so it",
        "cannot be added there by hand - and no Cooldown Manager addon can add it",
        "either, because their spell pickers read the exact same list.",
        "",
        "Since patch 12.0 aura data is 'secret'. Measured on this character, in combat,",
        "with the buff up: 0 readable, 18 secret. Not just Boiling Point - every buff.",
        "So an addon cannot identify an aura at all, by ID, by name or by icon.",
        "",
        "Blizzard's answer is Blizzard_AuraContainer: an addon declares what it wants to",
        "see and hands over the widgets, and the engine binds the aura, shows the button",
        "only while it is up, and drives icon, duration, bar and stacks itself. Every",
        "display in this addon is built on that.",
        "",
        "What is also readable is a proc: Boiling Point empowers Blood Boil, and",
        "IsSpellOverlayed(50842) is a plain boolean that never touches aura data. That",
        "is the fallback route, timed off our own clock.",
        "",
        "If no countdown number appears anywhere, enable it globally:",
        "  /console countdownForCooldowns 1",
        "",
        "Commands",
        "  /dks                    open this window",
        "  /dks groups             unlock every tracking group for dragging",
        "  /dks group add <name>   new group   |   remove <n>   |   list",
        "  /dks catalog            what the client knows about your spells",
        "  /dks tanks              toggle the co-tank panel (unlock to move it)",
        "  /dks unlock | lock      move the classic display",
        "  /dks test               15 second preview",
        "  /dks check <spellID>    is that aura findable right now?",
        "  /dks dump               full diagnosis - run it while the buff is up",
        "  /dks minimap            show or hide the minimap button",
        "  /dks reset              restore defaults",
    }, "\n"), 12, C.text)
    body:SetPoint("TOPLEFT", version, "BOTTOMLEFT", 0, -18)
    body:SetJustifyV("TOP")
    body:SetWidth(width - 30)

    content:SetHeight(body:GetStringHeight() + 90)
end

---------------------------------------------------------------------------
-- Changelog
---------------------------------------------------------------------------
local function BuildChangelogPage(page, width)
    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -22, 0)

    local textWidth = width - 30
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(textWidth, 1)
    scroll:SetScrollChild(content)

    local y = 0
    for _, entry in ipairs(ns.CHANGELOG) do
        local heading = UI.Label(content, "v" .. entry.version, 14, C.accent)
        heading:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)

        local date = UI.Label(content, entry.date, 11, C.textFaint)
        date:SetPoint("LEFT", heading, "RIGHT", 10, -1)
        y = y - 24

        for _, line in ipairs(entry.lines) do
            local dot = UI.Label(content, "-", 12, C.textFaint)
            dot:SetPoint("TOPLEFT", content, "TOPLEFT", 2, y)

            local bullet = UI.Label(content, line, 12, C.text)
            bullet:SetPoint("TOPLEFT", content, "TOPLEFT", 14, y)
            bullet:SetWidth(textWidth - 14)
            bullet:SetJustifyV("TOP")
            -- Width is set, so GetStringHeight reports the wrapped height.
            y = y - (bullet:GetStringHeight() + 6)
        end
        y = y - 14
    end

    content:SetHeight(math.max(1, -y))
end

---------------------------------------------------------------------------
-- The workspace shell
--
-- Shaped like an app rather than a settings dialog, because that is what it
-- is: you have a set of bars, you pick one, and you work on it.
--
--   left rail    your bars, then everything else
--   middle       the bar itself, at its real size
--   inspector    whatever is selected - a cell, or the bar
--
-- The secondary pages reuse the middle area and hide the inspector. They are
-- not the point of the addon and should not look like they are.
---------------------------------------------------------------------------
local PAGES = {
    { key = "display", title = "Aura Display",
      subtitle = "One buff in its own frame, for auras the Cooldown Manager does not carry.",
      build = BuildDisplayPage },

    { key = "settings", title = "Settings",
      subtitle = "Minimap button and resetting.",
      build = BuildGeneralPage },

    { key = "diagnostics", title = "Diagnostics",
      subtitle = "What the Cooldown Manager holds, and what the client refuses to show.",
      build = BuildDiagnosticsPage },

    { key = "about", title = "About",
      subtitle = "Why this addon exists, and every command.",
      build = BuildAboutPage },

    { key = "changelog", title = "Changelog",
      subtitle = "What changed, and why.",
      build = BuildChangelogPage },
}

function Options:Create()
    if self.frame then return end

    local frame = CreateFrame("Frame", "DKstuffOptionsFrame", UIParent)
    frame:SetSize(WINDOW_W, WINDOW_H)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnHide", function()
        -- The menu and the picker live on UIParent so they can escape the
        -- window bounds; neither may outlive it.
        UI.ClosePopup()
        if ns.BarSpellPicker and ns.BarSpellPicker.frame then
            ns.BarSpellPicker.frame:Hide()
        end
    end)
    frame:Hide()

    UI.Fill(frame, "BACKGROUND", C.windowBg, 0.98)
    local outer = ns.CreateBorder(frame, 1, "BORDER")
    outer:SetColor(0.22, 0.24, 0.29, 1)

    -- Rail -----------------------------------------------------------------
    local rail = CreateFrame("Frame", nil, frame)
    rail:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    rail:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
    rail:SetWidth(RAIL_W)
    UI.Fill(rail, "BACKGROUND", C.sidebarBg)

    local railEdge = rail:CreateTexture(nil, "ARTWORK")
    railEdge:SetPoint("TOPRIGHT", rail, "TOPRIGHT", 0, 0)
    railEdge:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", 0, 0)
    railEdge:SetWidth(1)
    railEdge:SetColorTexture(1, 1, 1, 0.06)

    local brand = UI.Label(rail, "|cff7ec6d4DK|r|cffff7a3dstuff|r", 19, C.text)
    brand:SetPoint("TOPLEFT", rail, "TOPLEFT", 16, -18)

    local versionLabel = UI.Label(rail, "v" .. ns.version, 11, C.textFaint)
    versionLabel:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", 16, 14)

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(28, 28)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    local closeLabel = UI.Label(close, "X", 13, C.textDim)
    closeLabel:SetPoint("CENTER", close, "CENTER", 0, 0)
    close:SetScript("OnEnter", function()
        closeLabel:SetTextColor(C.danger[1], C.danger[2], C.danger[3])
    end)
    close:SetScript("OnLeave", function()
        closeLabel:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    end)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- Middle and inspector -------------------------------------------------
    local main = CreateFrame("Frame", nil, frame)
    main:SetPoint("TOPLEFT", rail, "TOPRIGHT", PAD, -PAD - 6)
    main:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(INSPECTOR_W + PAD * 2), PAD)

    local inspectorHost = CreateFrame("Frame", nil, frame)
    inspectorHost:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -PAD - 6)
    inspectorHost:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)
    inspectorHost:SetWidth(INSPECTOR_W)

    local inspectorEdge = inspectorHost:CreateTexture(nil, "ARTWORK")
    inspectorEdge:SetPoint("TOPLEFT", inspectorHost, "TOPLEFT", -PAD, 0)
    inspectorEdge:SetPoint("BOTTOMLEFT", inspectorHost, "BOTTOMLEFT", -PAD, 0)
    inspectorEdge:SetWidth(1)
    inspectorEdge:SetColorTexture(1, 1, 1, 0.06)

    local canvas = ns.OptionsBars:BuildCanvas(main)
    local inspector = ns.OptionsBars:BuildInspector(inspectorHost, INSPECTOR_W)

    local pageFrames = {}
    for index in ipairs(PAGES) do
        local page = CreateFrame("Frame", nil, main)
        page:SetPoint("TOPLEFT", main, "TOPLEFT", 0, -52)
        page:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", 0, 0)
        page:Hide()
        pageFrames[index] = page
    end

    local pageTitle = UI.Label(main, "", 19, C.text)
    pageTitle:SetPoint("TOPLEFT", main, "TOPLEFT", 0, 0)
    local pageSubtitle = UI.Label(main, "", 12, C.textDim)
    pageSubtitle:SetPoint("TOPLEFT", pageTitle, "BOTTOMLEFT", 0, -5)

    self.frame = frame
    self.pageFrames = pageFrames

    local barButtons, pageButtons = {}, {}

    local function ShowBar(index)
        self.view = "bar"
        ns.OptionsBars:Select(index)
    end

    local function ShowPage(index)
        self.view = "page"
        self.pageIndex = index

        local entry = PAGES[index]
        if not entry.built then
            entry.built = true
            -- Pages get the middle at full width; they have no inspector.
            entry.build(pageFrames[index], WINDOW_W - RAIL_W - PAD * 2)
        end
        self:Refresh()
    end

    ---------------------------------------------------------------------
    -- Rail
    ---------------------------------------------------------------------
    local barsCaption = UI.Label(rail, "COOLDOWN BARS", 10, C.textFaint)
    barsCaption:SetPoint("TOPLEFT", rail, "TOPLEFT", 16, -58)

    local function RailButton(parent, height)
        local button = CreateFrame("Button", nil, parent)
        button:SetHeight(height)

        button.bg = button:CreateTexture(nil, "BACKGROUND")
        button.bg:SetAllPoints(button)
        button.bg:SetColorTexture(1, 1, 1, 0.05)
        button.bg:Hide()

        button.marker = button:CreateTexture(nil, "ARTWORK")
        button.marker:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
        button.marker:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
        button.marker:SetWidth(3)
        button.marker:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        button.marker:Hide()

        button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
        button.highlight:SetAllPoints(button)
        button.highlight:SetColorTexture(1, 1, 1, 0.04)

        button.label = UI.Label(button, "", 13, C.textDim)
        button.label:SetPoint("LEFT", button, "LEFT", 16, 0)
        button.label:SetWordWrap(false)

        return button
    end

    local addIconBtn = UI.Button(rail, "+ Icons", 76, function()
        ShowBar(Bars:Add(nil, "icon"))
    end)
    addIconBtn:SetHeight(22)

    local addBarBtn = UI.Button(rail, "+ Bars", 76, function()
        ShowBar(Bars:Add(nil, "bar"))
    end)
    addBarBtn:SetHeight(22)

    local railDivider = rail:CreateTexture(nil, "ARTWORK")
    railDivider:SetHeight(1)
    railDivider:SetColorTexture(1, 1, 1, 0.07)

    for index, entry in ipairs(PAGES) do
        local button = RailButton(rail, 28)
        button.label:SetText(entry.title)
        button:SetScript("OnClick", function() ShowPage(index) end)
        pageButtons[index] = button
    end

    -- The rail mirrors the model rather than a stale copy of it, so adding
    -- or deleting a bar re-lays it out.
    local function LayoutRail()
        local y = -78

        for index = 1, math.max(#barButtons, Bars:Count()) do
            local button = barButtons[index]
            local cfg = Bars:Get(index)

            if cfg and not button then
                button = RailButton(rail, 30)
                button:SetScript("OnClick", function() ShowBar(index) end)
                barButtons[index] = button
            end

            if cfg then
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", rail, "TOPLEFT", 0, y)
                button:SetPoint("TOPRIGHT", rail, "TOPRIGHT", 0, y)
                button.label:SetText(cfg.name)
                button:Show()
                y = y - 30
            elseif button then
                button:Hide()
            end
        end

        y = y - 10
        addIconBtn:ClearAllPoints()
        addIconBtn:SetPoint("TOPLEFT", rail, "TOPLEFT", 16, y)
        addBarBtn:ClearAllPoints()
        addBarBtn:SetPoint("LEFT", addIconBtn, "RIGHT", 6, 0)
        y = y - 36

        railDivider:ClearAllPoints()
        railDivider:SetPoint("TOPLEFT", rail, "TOPLEFT", 16, y)
        railDivider:SetPoint("TOPRIGHT", rail, "TOPRIGHT", -16, y)
        y = y - 14

        for index, button in ipairs(pageButtons) do
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", rail, "TOPLEFT", 0, y - (index - 1) * 28)
            button:SetPoint("TOPRIGHT", rail, "TOPRIGHT", 0, y - (index - 1) * 28)
        end
    end

    ---------------------------------------------------------------------
    -- Painting
    ---------------------------------------------------------------------
    local function PaintView()
        local onBar = (self.view ~= "page") and Bars:Count() > 0

        canvas:SetShown(onBar)
        inspectorHost:SetShown(onBar)
        pageTitle:SetShown(not onBar)
        pageSubtitle:SetShown(not onBar)

        for index, page in ipairs(pageFrames) do
            page:SetShown((not onBar) and self.pageIndex == index)
        end

        if not onBar then
            local entry = PAGES[self.pageIndex or 1]
            if entry then
                pageTitle:SetText(entry.title)
                pageSubtitle:SetText(entry.subtitle)
            end
        end

        -- Exactly one rail entry is current.
        local currentBar = onBar and (ns.OptionsBars:Current()) or nil
        for index, button in ipairs(barButtons) do
            local active = (index == currentBar)
            button.bg:SetShown(active)
            button.marker:SetShown(active)
            local colour = active and C.text or C.textDim
            button.label:SetTextColor(colour[1], colour[2], colour[3])
        end
        for index, button in ipairs(pageButtons) do
            local active = (not onBar) and self.pageIndex == index
            button.bg:SetShown(active)
            button.marker:SetShown(active)
            local colour = active and C.text or C.textDim
            button.label:SetTextColor(colour[1], colour[2], colour[3])
        end

        if onBar then
            canvas.Refresh()
            inspector.Refresh()
        else
            local page = pageFrames[self.pageIndex or 1]
            if page and page.Refresh then page.Refresh() end
        end
    end

    self.LayoutRail, self.PaintView = LayoutRail, PaintView
    self.ShowBar, self.ShowPage = ShowBar, ShowPage

    LayoutRail()
    self.view = "bar"
    self:Refresh()

    table.insert(UISpecialFrames, "DKstuffOptionsFrame")   -- close with ESC
end

function Options:Refresh()
    if not self.frame then return end
    if self.LayoutRail then self.LayoutRail() end
    if self.PaintView then self.PaintView() end
end

-- Called by CDM when the Cooldown Manager's contents change.
function Options:OnCatalogChanged()
    local picker = ns.BarSpellPicker
    if picker and picker.frame and picker.frame:IsShown() then
        picker:Fill()
    end
end

function Options:Toggle()
    self:Create()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Refresh()
        self.frame:Show()
    end
end
