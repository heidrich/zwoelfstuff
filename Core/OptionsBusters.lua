---------------------------------------------------------------------------
-- OptionsBusters.lua - the Timeline page
--
-- Two things live here and they are one feature: the panel that shows the
-- fight's next scheduled hit, and the list of defensives whose readiness is
-- painted under it. The defensives list is ALSO what the death window reads
-- when it says what was still available - one list, two consumers, because
-- "my defensives" is one fact about a character, not two.
---------------------------------------------------------------------------
local _, ns = ...

local UI = ns.UI
local Page = {}
ns.OptionsBusters = Page

function Page:BuildPage(page, width)
    local grid = UI.Page(page, width)

    ---------------------------------------------------------------------
    -- The panel
    ---------------------------------------------------------------------
    grid:Section("The panel")

    UI.Toggle(grid:Row("Show it"),
        function() return ns.Busters:Config().enabled ~= false end,
        function(value)
            ns.Busters:Config().enabled = value and true or false
            ns.Busters:Refresh()
        end)

    grid:Note("A bar with whatever the fight has scheduled next - the same "
        .. "feed the boss mod addons run on since the combat log went away - "
        .. "and your defensives under it, coloured by whether they are back. "
        .. "It shows in combat and is placed in Edit Mode, like everything "
        .. "else this addon draws.")

    grid:Note("What it cannot do, honestly: the client marks the event's "
        .. "severity as a secret, so \"tank busters only\" is a filter no "
        .. "addon can build. The panel shows the next thing, whatever it is. "
        .. "Outside raid and dungeon bosses the timeline is usually empty - "
        .. "the strip below still works everywhere.")

    ---------------------------------------------------------------------
    -- The defensives
    ---------------------------------------------------------------------
    grid:Section("Your defensives")

    -- Offered: what the Cooldown Manager knows for this character, minus
    -- what is already picked. CDM:Catalogue is the same source every other
    -- spell list in this addon reads - it answers in SPELL ids, where the
    -- low-level walk answers in cooldown ids, and mixing those two up is a
    -- picker full of numbers that match nothing.
    local function Choices()
        local out = {}
        local picked = (ns.db and ns.db.defensives) or {}
        for _, entry in ipairs(ns.CDM:Catalogue()) do
            if entry.spellID and not picked[entry.spellID] then
                out[#out + 1] = {
                    value = entry.spellID,
                    text = entry.name or ("Spell " .. entry.spellID),
                    -- The icon and the client's own tooltip, both off the
                    -- catalogue entry - the owner asked while picking on a
                    -- list of forty same-grey names.
                    iconTexture = entry.icon,
                    spellID = entry.spellID,
                }
            end
        end
        return out
    end

    UI.Dropdown(grid:FullRow("Add one", { controlWidth = 260 }), Choices,
        function() return nil end,
        function(value)
            if not value then return end
            ns.db.defensives = ns.db.defensives or {}
            ns.db.defensives[value] = true
            ns.Options:Refresh()
            ns.Busters:Refresh()
        end, { emptyText = "Pick a spell the Cooldown Manager knows",
               search = true, rowHeight = 26 })

    grid:Note("Readiness is OUR OWN estimate - your last cast plus the "
        .. "spell's base cooldown - because the client will not let an addon "
        .. "read a live cooldown on this patch. Charges, resets and haste "
        .. "are not in it, so the panel says about, and means it. The death "
        .. "window reads this same list when it says what was still ready.")

    -- One row per picked defensive, built once and re-labelled, the same
    -- pattern as the profile page's bar rows and for the same reason.
    local ROWS = 16
    local rows = {}
    for i = 1, ROWS do
        local row = grid:FullRow("", { controlWidth = 90 })
        local remove = UI.Button(row.slot, "Remove", 90, function()
            if row.dkSpell and ns.db.defensives then
                ns.db.defensives[row.dkSpell] = nil
                ns.Options:Refresh()
                ns.Busters:Refresh()
            end
        end)
        remove:SetPoint("RIGHT", row.slot, "RIGHT", 0, 0)
        rows[i] = row
    end

    grid:Layout()

    page.Refresh = function()
        local picked = {}
        for spellID in pairs((ns.db and ns.db.defensives) or {}) do
            picked[#picked + 1] = spellID
        end
        table.sort(picked, function(a, b)
            return (ns.SpellName(a) or "") < (ns.SpellName(b) or "")
        end)

        for i, row in ipairs(rows) do
            local spellID = picked[i]
            row.dkSpell = spellID
            row:SetShown(spellID ~= nil)
            if spellID then
                row.label:SetText(ns.SpellName(spellID) or ("Spell " .. spellID))
                -- Icon and the client's own tooltip, the same two the picker
                -- shows: choosing from a list with icons and then living
                -- with a list without them was the owner's report.
                UI.MakeRowASpell(row, spellID)
            end
        end

        grid:Refresh()
        grid:Layout()
    end
end
