---------------------------------------------------------------------------
-- OptionsExternals.lua - the External cooldowns page
--
-- The same shape as the Death-log page, deliberately: the SLOTS at the top
-- where the work is, the settings under them with their paragraphs on the
-- rows, and the list you pick from in the third column. Two pages that do the
-- same thing - "choose some spells and arrange them" - must not be two
-- different pictures.
--
-- WHAT THE THIRD COLUMN IS NOT: the Cooldown Manager's catalogue. That list
-- is YOUR spells, and every spell on this page belongs to somebody else. So
-- it is our own fourteen, grouped by class, and it is short enough to read
-- rather than search.
---------------------------------------------------------------------------
local _, ns = ...

local UI = ns.UI
local C = UI.C

local Page = {}
ns.OptionsExternals = Page

local SLOT, GAP = 40, 8
local PER_ROW = 8
local SLOTS = 12

local function Cfg() return ns.Externals.Config() end
local function Apply() ns.Externals.Refresh() end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
function Page:BuildPage(page, width)
    local grid = UI.Page(page, width, { tooltipNotes = true })

    ---------------------------------------------------------------------
    -- What you have picked
    ---------------------------------------------------------------------
    grid:Section("Your externals")

    local host = CreateFrame("Frame", nil, grid.content)
    host:SetHeight(SLOT * 2 + GAP)

    local slots = {}
    for index = 1, SLOTS do
        local slot = UI.SpellSlot(host, {
            size = SLOT,
            get = function() return ns.Externals.Picked()[index] end,
            onClear = function()
                local spellID = ns.Externals.Picked()[index]
                if spellID then
                    ns.Externals.Drop(spellID)
                    ns.Options:Refresh()
                end
            end,
        })
        slot:SetPoint("TOPLEFT", host, "TOPLEFT",
            ((index - 1) % PER_ROW) * (SLOT + GAP),
            -math.floor((index - 1) / PER_ROW) * (SLOT + GAP))
        slots[index] = slot
    end

    grid:Wide(host, SLOT * 2 + GAP, 2, 10)

    grid:Note("Pick from the list on the right. On your screen, clicking one "
        .. "of these whispers whoever in the group can cast it; right-click a "
        .. "slot here to drop it.")

    ---------------------------------------------------------------------
    -- The panel
    ---------------------------------------------------------------------
    grid:Section("The panel")

    UI.Slider(grid:Row("Icon size"), {
        get = function() return Cfg().size or 40 end,
        set = function(value) Cfg().size = value end,
        min = 20, max = 64, step = 2, apply = Apply,
    })
    grid:Note("How big each icon is on your screen.")

    UI.Slider(grid:Row("Spacing"), {
        get = function() return Cfg().gap or 4 end,
        set = function(value) Cfg().gap = value end,
        min = 0, max = 16, step = 1, apply = Apply,
    })
    grid:Note("The gap between two icons.")

    UI.Slider(grid:Row("How many in a line"), {
        get = function() return Cfg().perLine or 6 end,
        set = function(value) Cfg().perLine = value end,
        min = 1, max = 12, step = 1, apply = Apply,
    })
    grid:Note("After this many the panel starts a second line.")

    UI.Dropdown(grid:Row("Runs"), {
        { value = "right", text = "Across", icon = "dir-left-right" },
        { value = "down",  text = "Down",   icon = "dir-top-bottom" },
    }, function() return Cfg().growth or "right" end,
        function(value) Cfg().growth = value end, { apply = Apply })
    grid:Note("Whether the icons run across the screen or down it.")

    UI.Toggle(grid:Row("Only in a group"),
        function() return Cfg().onlyInGroup ~= false end,
        function(value) Cfg().onlyInGroup = value and true or false; Apply() end)
    grid:Note("On your own there is nobody to ask, so the panel stays away.")

    UI.Toggle(grid:Row("Only in combat"),
        function() return Cfg().onlyInCombat and true or false end,
        function(value) Cfg().onlyInCombat = value and true or false; Apply() end)
    grid:Note("Out of combat you are asking for nothing.")

    ---------------------------------------------------------------------
    -- The message
    ---------------------------------------------------------------------
    grid:Section("What you say")

    local messageRow = grid:FullRow("Whisper", { controlWidth = 300 })
    local input = UI.Input(messageRow.slot, 300, function(text)
        Cfg().message = (text ~= "" and text) or nil
    end, false, ns.Externals.DEFAULT_MESSAGE)
    input:SetPoint("RIGHT", messageRow.slot, "RIGHT", 0, 0)
    -- The row is already in grid.widgets - Grid:FullRow put it there - so
    -- giving it a Refresh is all that is needed. Adding it again would run
    -- this twice on every repaint.
    messageRow.Refresh = function() input:SetText(Cfg().message or "") end

    grid:Note("One sentence for every slot. |cffffd100%s|r is where the "
        .. "spell's name goes. Leave it out and the name is put in brackets "
        .. "after it anyway - a whisper that does not say WHAT you want is a "
        .. "whisper nobody can act on.")

    grid:Buttons({
        { text = "Move the panel", width = 150, style = "primary",
          onClick = function() ns.EditMode:SetUnlocked(true, "bars") end },
        { text = "Test mode", width = 120, onClick = function()
            ns.Externals:SetTestMode(not ns.Externals.testing)
            ns.Print("External cooldowns test mode",
                ns.Externals.testing and "|cff40ff40on|r" or "|cff888888off|r")
        end },
        { text = "Who would be asked", width = 170, onClick = function()
            ns.Externals:Dump()
        end },
    }, 14)

    ---------------------------------------------------------------------
    -- Assignment
    --
    -- Owner: "im raid sollte man das zuweisen koennen. ggf. einstellungen
    -- wenn man im raid ist, werden die spieler im tool aufgelistet, dann
    -- einfach hinter dem spell anklicken".
    --
    -- One row per PICKED spell, and the control lists whoever in the group
    -- can actually cast it. Not every player and not every spell: a dropdown
    -- of forty names against fourteen spells is a wall, and thirty-nine of
    -- those names cannot cast the thing anyway.
    ---------------------------------------------------------------------
    grid:Section("Who to ask")

    for index = 1, SLOTS do
        local row = grid:FullRow("", { controlWidth = 220 })
        local function SpellID() return ns.Externals.Picked()[index] end

        UI.Dropdown(row, function()
            local spellID = SpellID()
            local spell = spellID and ns.Externals.Get(spellID)
            local items = { { value = "", text = "The healer of that class" } }
            for _, member in ipairs(ns.Externals.Candidates(spell,
                ns.Externals.Roster())) do
                items[#items + 1] = { value = member.name, text = member.name }
            end
            return items
        end, function()
            local spellID = SpellID()
            return (spellID and Cfg().assigned[spellID]) or ""
        end, function(value)
            local spellID = SpellID()
            if spellID then
                Cfg().assigned[spellID] = (value ~= "" and value) or nil
            end
        end, { emptyText = "The healer of that class" })

        row.Refresh = function()
            local spellID = SpellID()
            -- A row for a slot you have not filled is not an empty row, it is
            -- no row: SetRelevant takes it out of the layout entirely.
            row:SetRelevant(spellID ~= nil)
            if spellID then
                UI.MakeRowASpell(row, spellID)
                row.label:SetText(ns.SpellName(spellID) or ("Spell " .. spellID))
            end
        end
    end

    grid:Note("Left alone, a click asks the healer of that class - which in a "
        .. "five-man is the only person who has it. In a raid, name somebody.")

    grid:Layout()

    page.Refresh = function()
        for _, slot in ipairs(slots) do slot.Refresh() end
        grid:Refresh()
    end
end

---------------------------------------------------------------------------
-- The third column: everything there is, grouped by class
---------------------------------------------------------------------------
function Page:BuildSide(sideHost, pad)
    local side = CreateFrame("Frame", nil, sideHost)
    side:SetAllPoints(sideHost)
    side:Hide()

    local title = UI.Label(side, "Every external", UI.FS.card, C.text)
    title:SetPoint("TOPLEFT", side, "TOPLEFT", pad, -18)

    local hint = UI.Label(side, "Click one to put it on your panel.",
        UI.FS.meta, C.textFaint)
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

    -- A host for the scrolling area, because UI.ScrollArea anchors ITSELF to
    -- whatever it is given - so the thing it is given has to be the viewport.
    local listHost = CreateFrame("Frame", nil, side)
    listHost:SetPoint("TOPLEFT", side, "TOPLEFT", pad, -(UI.HEADER_H + 16))
    listHost:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -pad, pad)

    local rowWidth = UI.INSPECTOR_W - pad * 2 - 8
    local _, content = UI.ScrollArea(listHost, rowWidth, 8)

    -- Grouped by class, in the order the list is written: a run of five
    -- paladin blessings reads as one thing to decide about, and a flat
    -- alphabetical list of fourteen makes it five separate decisions.
    local rows = {}
    local y, lastClass = 0, nil

    for _, entry in ipairs(ns.Externals.SPELLS) do
        if entry.class ~= lastClass then
            lastClass = entry.class
            local heading = UI.Eyebrow(content, entry.class)
            heading:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(y + 8))
            y = y + 26
        end

        local row = UI.SpellRow(content, rowWidth, 30)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        row.dkSpellID = entry.spellID
        row.spellID = entry.spellID
        row:SetScript("OnClick", function()
            if ns.Externals.IsPicked(entry.spellID) then
                ns.Externals.Drop(entry.spellID)
            else
                ns.Externals.Pick(entry.spellID)
            end
            ns.Options:Refresh()
        end)
        rows[#rows + 1] = row
        y = y + 31
    end

    content:SetHeight(math.max(1, y))

    side.Refresh = function()
        local roster = ns.Externals.Roster()
        for _, row in ipairs(rows) do
            local spellID = row.spellID
            local picked = ns.Externals.IsPicked(spellID)
            local candidates = ns.Externals.Candidates(
                ns.Externals.Get(spellID), roster)

            row.icon:SetTexture(ns.SpellTexture(spellID) or ns.WHITE)
            row.name:SetText(ns.SpellName(spellID) or ("Spell " .. spellID))

            -- known = "somebody here can actually cast this". A picked spell
            -- whose class is not in the group draws NOTHING on screen - the
            -- panel hides that slot - so without this the page would have
            -- offered no explanation for an icon that never appears.
            row:SetUsed(picked and "on panel" or nil, #candidates > 0)

            if picked then
                row:SetTrailing("On panel", "cell")
            elseif #candidates == 0 then
                row:SetTrailing("nobody here")
            elseif #candidates == 1 then
                row:SetTrailing(candidates[1].name)
            else
                row:SetTrailing(#candidates .. " in the group")
            end
        end
    end

    return side
end
