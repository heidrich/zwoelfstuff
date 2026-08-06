---------------------------------------------------------------------------
-- Options - the app window.
--
-- Three columns, fixed:
--
--   left    the functions. Cooldowns, the aura display, settings, and the
--           three read-only pages. It does NOT list your bars - that was the
--           mistake in the last shape, because it made you pick a bar before
--           you could see any of them.
--   middle  what you are working on. For Cooldowns that is every bar you own,
--           under each other, scrollable, with "Add new bar" at the bottom of
--           the stack where the next one appears.
--   right   the spells, in full, all the time. It becomes the settings for
--           one bar while you have its Options open, and goes back after.
--
-- The secondary pages take the middle AND the right, because they have no
-- spell list to show and a narrow column of text next to an empty panel is
-- the wasted space this rebuild set out to remove.
---------------------------------------------------------------------------
local _, ns = ...

local Options = {}
ns.Options = Options

local UI = ns.UI
local C = UI.C

-- The left column holds six words and a button; it does not need to be as
-- wide as the thing you are working on. The right one holds a settings label
-- AND its control on the same line, and it was clipping labels to "T..." to
-- fit. So: take the width from the one that has nothing to say and give it to
-- the one that ran out.
local WINDOW_W, WINDOW_H = 1360, 760
local SIDEBAR_W = 168
local SIDE_W    = 400
local PAD       = 20

-- Shared with Widgets, so the rule under the brand, the rule under the page
-- title and the rule under the right column's heading are the same line.
local HEADER_H  = UI.HEADER_H

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
-- Settings
---------------------------------------------------------------------------
local function BuildGeneralPage(page, width)
    local grid = UI.Page(page, width)

    grid:Section("Text")

    UI.MediaPicker(grid:FullRow("Font", { controlWidth = 220 }), "font",
        function() return ns.db.font end,
        function(value) ns.db.font = value end,
        function() ns.Screen:Render() end)

    grid:Note("Every piece of text on every bar, unless that one piece has "
        .. "been given its own font in the bar's own settings. The list is "
        .. "whatever your other addons have registered - so a font you "
        .. "installed for ElvUI or WeakAuras is already in it.")

    grid:Section("Blizzard's Cooldown Manager")

    UI.Toggle(grid:Row("Take the display over",
        { sublabel = "Hide the cooldowns you have not placed on a bar" }),
        function() return ns.db.takeOverCDM ~= false end,
        function(value)
            ns.db.takeOverCDM = value and true or false
            if not value then ns.Screen:ReleaseAll() end
            ns.Screen:Render()
        end)

    grid:Note("Every icon on your bars IS one of Blizzard's - it owns the timing, "
        .. "the charges and the stacks, and on this patch no addon may read those "
        .. "for itself. Moving one onto your bar leaves a hole in Blizzard's own "
        .. "row, because its layout does not know the icon left. With this off you "
        .. "get that row back, holes included.")

    grid:Section("Minimap button")
    UI.Toggle(grid:Row("Show the button"),
        function() return ns.db.minimap.show end,
        function(value) ns.MinimapButton:SetShown(value) end)
    UI.Toggle(grid:Row("Lock its position"),
        function() return ns.db.minimap.locked end,
        function(value) ns.db.minimap.locked = value end)

    grid:Note("Left click opens this window, drag moves it around the minimap edge.")

    grid:Section("Everything")

    local resetArmed = false
    local resetStrip
    resetStrip = ButtonStrip(grid, {
        {
            text = "Reset all settings", width = 160, style = "primary",
            onClick = function()
                -- Two-step, because this throws away every bar, position and
                -- colour the user has set.
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
                SlashCmdList.ZWOELFSTUFF("reset")
            end,
        },
    })
    resetStrip.reset = select(1, resetStrip:GetChildren())

    grid:Note("Restores every default: your bars, your presets and the minimap "
        .. "button. Recorded procs are kept - those are measurements, and they "
        .. "cannot be typed back in. There is no undo for the rest.")

    grid:Layout()
    page.Refresh = function() grid:Refresh() end
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

    grid:Section("Auras")
    grid:Note("Procs are recorded while you play, per class and spec, and their "
        .. "duration is measured rather than assumed. Output goes to your chat frame.")

    ButtonStrip(grid, {
        { text = "What was seen", width = 150, style = "primary", onClick = function()
            ns.Auras:Dump()
        end },
        { text = "Export this spec", width = 150, onClick = function()
            ns.Auras:Export()
        end },
    })

    grid:Section("This client")

    local rivalRow = grid:FullRow("Another addon holding the same frames",
        { controlWidth = 300 })
    local rivalState = UI.Label(rivalRow.slot, "", 12, C.text)
    rivalState:SetPoint("RIGHT", rivalRow.slot, "RIGHT", 0, 0)
    rivalState:SetJustifyH("RIGHT")

    local cdmRow = grid:FullRow("Cooldown Manager", { controlWidth = 260 })
    local cdmState = UI.Label(cdmRow.slot, "", 12, C.text)
    cdmState:SetPoint("RIGHT", cdmRow.slot, "RIGHT", 0, 0)
    cdmState:SetJustifyH("RIGHT")

    local engineRow = grid:FullRow("Aura engine (12.1)", { controlWidth = 260 })
    local engineState = UI.Label(engineRow.slot, "", 12, C.text)
    engineState:SetPoint("RIGHT", engineRow.slot, "RIGHT", 0, 0)
    engineState:SetJustifyH("RIGHT")

    grid:Note("There is ONE set of Cooldown Manager item frames, and every addon that "
        .. "does cooldowns on this patch works by adopting them. Two addons adopting "
        .. "the same frame both re-assert their own anchor, so the icons end up split "
        .. "between two layouts - which looks like a bug in whichever one you are "
        .. "looking at. Run one or the other.")

    grid:Note("Patch 12.0 made aura data secret, so an addon cannot identify a buff by "
        .. "ID, name or icon. The sanctioned replacement, Blizzard_AuraContainer, only "
        .. "arrives in 12.1 - until then the Cooldown Manager is the one usable source, "
        .. "which is what this addon is built on.")

    grid:Layout()

    page.Refresh = function()
        local rival = ns.CDM:RivalName()
        rivalState:SetText(rival and ("|cffff4040" .. rival .. "|r")
            or "|cff40ff40none found|r")

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
    local scroll, content = UI.ScrollArea(page, width - 14)

    local author = UI.Label(content, "Zwolf  -  EU Destromath", 15, C.accent)
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
        "only while it is up, and drives icon, duration, bar and stacks itself. That",
        "frame type arrives in patch 12.1 - this client is 12.0.7, so it is not here yet.",
        "",
        "What is also readable is a proc: Boiling Point empowers Blood Boil, and",
        "IsSpellOverlayed(50842) is a plain boolean that never touches aura data. That",
        "is the fallback route, timed off our own clock.",
        "",
        "If no countdown number appears anywhere, enable it globally:",
        "  /console countdownForCooldowns 1",
        "",
        "Commands",
        "  /zs                    open this window",
        "  /zs unlock | lock      move the bars around the screen",
        "  /zs bars               list your bars   |   add <name>   |   remove <n>",
        "  /zs cdm                what Blizzard's Cooldown Manager currently holds",
        "  /zs auras              the procs seen on this spec, and what drives them",
        "  /zs auras export       hand this spec's set back so it ships with the addon",
        "  /zs auras icon <glowID> <spellID>    which icon a proc shows",
        "  /zs auras bind <glowID> <auraID>     name the buff itself (12.1 route)",
        "  /zs auras forget <glowID>            drop a recording",
        "  /zs minimap            show or hide the minimap button",
        "  /zs reset              restore defaults, keeping recorded procs",
    }, "\n"), 12, C.text)
    body:SetPoint("TOPLEFT", version, "BOTTOMLEFT", 0, -18)
    body:SetJustifyV("TOP")
    body:SetWidth(width - 30)

    content:SetHeight(body:GetStringHeight() + 90)
    if scroll.Update then scroll.Update() end
end

---------------------------------------------------------------------------
-- Changelog
---------------------------------------------------------------------------
local function BuildChangelogPage(page, width)
    local textWidth = width - 20
    local scroll, content = UI.ScrollArea(page, textWidth)

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
    if scroll.Update then scroll.Update() end
end

---------------------------------------------------------------------------
-- The functions in the left column
--
-- "cooldowns" is the addon; the rest are secondary and look it. Only the
-- first one uses the right column, which is why it carries the flag rather
-- than the shell hardcoding an index.
---------------------------------------------------------------------------
local PAGES = {
    { key = "cooldowns", title = "Cooldowns", glyph = "grid", side = true,
      subtitle = "Your bars, in the order you built them. Click a cell, then pick "
              .. "a cooldown on the right." },

    { key = "settings", title = "Settings", glyph = "sliders",
      subtitle = "How the bars sit next to Blizzard's own, the minimap button, and resetting.",
      build = BuildGeneralPage },

    { key = "diagnostics", title = "Diagnostics", glyph = "pulse",
      subtitle = "What the Cooldown Manager holds, and what the client refuses to show.",
      build = BuildDiagnosticsPage },

    { key = "about", title = "About", glyph = "info",
      subtitle = "Why this addon exists, and every command.",
      build = BuildAboutPage },

    { key = "changelog", title = "Changelog", glyph = "log",
      subtitle = "What changed, and why.",
      build = BuildChangelogPage },
}

function Options:Create()
    if self.frame then return end

    local frame = CreateFrame("Frame", "ZwoelfStuffOptionsFrame", UIParent)
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
        -- The menu lives on UIParent so it can escape the window bounds; it
        -- may not outlive the window.
        UI.ClosePopup()
    end)
    frame:Hide()

    UI.Fill(frame, "BACKGROUND", C.windowBg)
    local outer = ns.CreateBorder(frame, 1, "BORDER")
    outer:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)

    ---------------------------------------------------------------------
    -- Left column
    ---------------------------------------------------------------------
    local rail = CreateFrame("Frame", nil, frame)
    rail:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    rail:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
    rail:SetWidth(SIDEBAR_W)
    UI.Fill(rail, "BACKGROUND", C.sidebarBg)

    local railEdge = UI.Separator(rail, false)
    railEdge:SetPoint("TOPRIGHT", rail, "TOPRIGHT", 0, 0)
    railEdge:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", 0, 0)

    local brand = UI.Label(rail, "|cff7ec6d4Zwoelf|r|cffff7a3dStuff|r", 19, C.text)
    brand:SetPoint("TOPLEFT", rail, "TOPLEFT", 18, -18)

    local brandSub = UI.Label(rail, "by Zwoelf - EU Destromath", 11, C.textDim)
    brandSub:SetPoint("TOPLEFT", brand, "BOTTOMLEFT", 0, -5)

    local versionLabel = UI.Label(rail, "v" .. ns.version, 11, C.textFaint)
    versionLabel:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", 18, 16)

    -- ONE rule, across the whole window. Three separate lines with three sets
    -- of padding never quite agree, and the eye reads the disagreement as
    -- sloppiness even when the heights match.
    --
    -- Window chrome: the one header rule and the close button. Both have to
    -- sit ABOVE the three column backgrounds, and a texture on the window
    -- itself would be painted under its own child frames no matter which
    -- layer it claims. So they get a frame of their own, with a level that
    -- settles the question rather than relying on creation order.
    local chrome = CreateFrame("Frame", nil, frame)
    chrome:SetAllPoints(frame)
    chrome:SetFrameLevel(frame:GetFrameLevel() + 20)

    local headerLine = chrome:CreateTexture(nil, "OVERLAY")
    headerLine:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -HEADER_H)
    headerLine:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -HEADER_H)
    headerLine:SetHeight(1)
    headerLine:SetColorTexture(C.separator[1], C.separator[2], C.separator[3], 1)

    local close = CreateFrame("Button", nil, chrome)
    close:SetSize(30, 30)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
    local closeLabel = UI.Label(close, "X", 13, C.textDim)
    closeLabel:SetPoint("CENTER", close, "CENTER", 0, 0)
    close:SetScript("OnEnter", function()
        closeLabel:SetTextColor(C.danger[1], C.danger[2], C.danger[3])
    end)
    close:SetScript("OnLeave", function()
        closeLabel:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    end)
    close:SetScript("OnClick", function() frame:Hide() end)

    ---------------------------------------------------------------------
    -- Right column
    ---------------------------------------------------------------------
    local sideHost = CreateFrame("Frame", nil, frame)
    sideHost:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    sideHost:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    sideHost:SetWidth(SIDE_W)
    UI.Fill(sideHost, "BACKGROUND", C.sidebarBg)

    local sideEdge = UI.Separator(sideHost, false)
    sideEdge:SetPoint("TOPLEFT", sideHost, "TOPLEFT", 0, 0)
    sideEdge:SetPoint("BOTTOMLEFT", sideHost, "BOTTOMLEFT", 0, 0)

    ---------------------------------------------------------------------
    -- Middle
    ---------------------------------------------------------------------
    local stageHost = CreateFrame("Frame", nil, frame)
    stageHost:SetPoint("TOPLEFT", rail, "TOPRIGHT", 0, 0)
    stageHost:SetPoint("BOTTOMLEFT", rail, "BOTTOMRIGHT", 0, 0)
    UI.Fill(stageHost, "BACKGROUND", C.canvasBg)

    local pageTitle = UI.Label(stageHost, "", 19, C.text)
    pageTitle:SetPoint("TOPLEFT", stageHost, "TOPLEFT", PAD, -18)

    -- Width, not a second anchor: a font string given both TOPLEFT and RIGHT
    -- is told two different vertical positions and lands somewhere else.
    local pageSubtitle = UI.Label(stageHost, "", 11, C.textDim)
    pageSubtitle:SetPoint("TOPLEFT", pageTitle, "BOTTOMLEFT", 0, -5)
    pageSubtitle:SetJustifyH("LEFT")
    pageSubtitle:SetWordWrap(false)

    local body = CreateFrame("Frame", nil, stageHost)
    body:SetPoint("TOPLEFT", stageHost, "TOPLEFT", PAD, -(HEADER_H + 16))
    body:SetPoint("BOTTOMRIGHT", stageHost, "BOTTOMRIGHT", -PAD, PAD)

    -- The middle is as wide as whatever is not the two side columns. It is
    -- re-anchored per view rather than fixed, because the pages that have no
    -- spell list get the right column's space instead of leaving it blank.
    local NARROW_W = WINDOW_W - SIDEBAR_W - SIDE_W - 2
    local WIDE_W   = WINDOW_W - SIDEBAR_W - 2

    local function SetStageWidth(withSide)
        stageHost:SetWidth(withSide and NARROW_W or WIDE_W)
    end

    local listWidth = NARROW_W - PAD * 2
    local pageWidth = WIDE_W - PAD * 2

    local barList = ns.OptionsBars:BuildList(body, listWidth)
    local side = ns.OptionsBars:BuildSide(sideHost, PAD)

    local pageFrames = {}
    for index, entry in ipairs(PAGES) do
        if entry.build then
            local page = CreateFrame("Frame", nil, body)
            page:SetAllPoints(body)
            page:Hide()
            pageFrames[index] = page
        end
    end

    self.frame = frame
    self.pageIndex = 1

    ---------------------------------------------------------------------
    -- Left column entries
    ---------------------------------------------------------------------
    local navItems = {}

    local function ShowPage(index)
        self.pageIndex = index

        local entry = PAGES[index]
        if entry.build and not entry.built then
            entry.built = true
            entry.build(pageFrames[index], pageWidth)
        end
        self:Refresh()
    end

    for index, entry in ipairs(PAGES) do
        local item = UI.NavItem(rail, entry.title, entry.glyph,
            function() ShowPage(index) end)
        item:SetPoint("TOPLEFT", rail, "TOPLEFT", 8, -76 - (index - 1) * 34)
        item:SetPoint("TOPRIGHT", rail, "TOPRIGHT", -8, -76 - (index - 1) * 34)
        navItems[index] = item
    end

    -- Unlock sits at the bottom of the rail rather than among the pages: it
    -- is not a place you go, it is a thing you do, and it closes the window
    -- to do it. Same shape as EllesmereUI's, because that is the gesture
    -- people already have in their hands.
    local unlockBtn = UI.Button(rail, "Unlock Mode", SIDEBAR_W - 36, function()
        frame:Hide()
        ns.EditMode:SetUnlocked(true)
    end, "soft")
    unlockBtn:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", 18, 42)

    ---------------------------------------------------------------------
    -- Painting
    ---------------------------------------------------------------------
    local function PaintView()
        local entry = PAGES[self.pageIndex] or PAGES[1]
        local withSide = entry.side and true or false

        SetStageWidth(withSide)
        sideHost:SetShown(withSide)

        pageTitle:SetText(entry.title)
        pageSubtitle:SetText(entry.subtitle)
        pageSubtitle:SetWidth((withSide and NARROW_W or WIDE_W) - PAD * 2)

        barList:SetShown(withSide)
        for index, page in pairs(pageFrames) do
            page:SetShown(index == self.pageIndex)
        end

        for index, item in ipairs(navItems) do
            item:SetActive(index == self.pageIndex)
        end

        if withSide then
            barList.Refresh()
            side.Refresh()
        else
            local page = pageFrames[self.pageIndex]
            if page and page.Refresh then page.Refresh() end
        end
    end

    self.PaintView = PaintView
    self.ShowPage = ShowPage

    SetStageWidth(true)
    self:Refresh()

    table.insert(UISpecialFrames, "ZwoelfStuffOptionsFrame")   -- close with ESC
end

function Options:Refresh()
    if not self.frame then return end
    if self.PaintView then self.PaintView() end
end

-- Called by CDM when the Cooldown Manager's contents change: the spell list
-- is a view of it, so it must not go stale while it is open.
function Options:OnCatalogChanged()
    if self.frame and self.frame:IsShown() then
        self:Refresh()
    end
end

-- Opens on a named page. Separate from Toggle on purpose: something that
-- WANTS the window open must not close it because it happened to be open
-- already, which is exactly what "Bar options" in the unlock overlay did.
function Options:Open(pageKey)
    self:Create()

    if pageKey and self.ShowPage then
        for index, entry in ipairs(PAGES) do
            if entry.key == pageKey then
                self.ShowPage(index)
                break
            end
        end
    end

    self:Refresh()
    self.frame:Show()
end

function Options:Toggle()
    self:Create()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Open()
    end
end
