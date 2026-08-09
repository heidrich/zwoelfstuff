---------------------------------------------------------------------------
-- OptionsDeaths.lua - the Deaths page
--
-- The feature itself lives in Core/Death.lua and fires on its own; this
-- page is the two switches the owner asked for in as many words - "an
-- option that a window opens right on death" and the chat share - plus the
-- honest paragraph about where the numbers come from.
---------------------------------------------------------------------------
local _, ns = ...

local UI = ns.UI
local Page = {}
ns.OptionsDeaths = Page

local function Config()
    ns.db.death = ns.db.death or {}
    return ns.db.death
end

function Page:BuildPage(page, width)
    local grid = UI.Page(page, width)

    ---------------------------------------------------------------------
    -- When you die
    ---------------------------------------------------------------------
    grid:Section("When you die")

    UI.Toggle(grid:Row("Record it"),
        function() return Config().record ~= false end,
        function(value) Config().record = value and true or false end)

    grid:Note("Reads Blizzard's own death recap and damage meter the moment "
        .. "you fall - what hit you, how hard, the health you had left after "
        .. "each blow - plus which of your defensives were still ready by "
        .. "our own clock, and whether a healthstone or a potion was in the "
        .. "bags. They are kept for this character and survive logging out; "
        .. "anything past the number below falls off the end, and "
        .. "|cffffd100Clear list|r in the window empties them.")

    UI.Slider(grid:Row("How many to keep"), {
        get = function() return ns.Death.KeepCount() end,
        set = function(value) Config().keep = math.floor(value + 0.5) end,
        min = ns.Death.KEEP_MIN, max = ns.Death.KEEP_MAX, step = 1,
        format = function(v)
            return string.format("%d", math.floor((v or 10) + 0.5))
        end,
        -- Applied at once, not at the next death: a list that keeps forty
        -- for the rest of the evening after being told ten is a setting
        -- that appears to do nothing.
        apply = function() ns.Death.Trim() end,
    })

    grid:Note("Ten by default. They are kept for this character and survive "
        .. "logging out, so the number is how far back you want to be able "
        .. "to look - the window shows twelve at a time and the list "
        .. "scrolls. Lowering it drops the oldest immediately, and there is "
        .. "no undo.")

    UI.Toggle(grid:Row("Open the window right away"),
        function() return Config().openOnDeath ~= false end,
        function(value) Config().openOnDeath = value and true or false end)

    grid:Note("The window with the quick analysis, up before you release. "
        .. "Switched off, the death is still recorded and "
        .. "|cffffd100/zs death|r opens it when you want it. Its size is the "
        .. "|cffffd100Size|r button in the window itself - the moment you "
        .. "want it smaller is the moment it is in front of you.")

    ---------------------------------------------------------------------
    -- The icon on the screen
    ---------------------------------------------------------------------
    grid:Section("The icon on the screen")

    UI.Toggle(grid:Row("Show it"),
        function()
            local icon = ns.db.death and ns.db.death.icon
            return not icon or icon.show ~= false
        end,
        function(value)
            Config().icon = Config().icon or {}
            Config().icon.show = value and true or false
            ns.Death.RefreshIcon()
        end)

    grid:Note("A small skull that appears with your first death of the "
        .. "session and counts them in its corner. Click opens the window. "
        .. "It never shows before anything has happened.")

    UI.Toggle(grid:Row("Lock its position"),
        function()
            local icon = ns.db.death and ns.db.death.icon
            return icon and icon.locked or false
        end,
        function(value)
            Config().icon = Config().icon or {}
            Config().icon.locked = value and true or false
        end)

    grid:Note("Unlocked, the skull is dragged wherever you want it - any "
        .. "time, no Edit Mode needed. Locked, it stays put and only clicks.")

    ---------------------------------------------------------------------
    -- Sharing
    ---------------------------------------------------------------------
    grid:Section("Sharing")

    UI.Dropdown(grid:FullRow("Post it to", { controlWidth = 200 }), {
        { value = "AUTO",          text = "The group I am in" },
        { value = "PARTY",         text = "Party" },
        { value = "RAID",          text = "Raid" },
        { value = "INSTANCE_CHAT", text = "Instance" },
        { value = "GUILD",         text = "Guild" },
        { value = "SAY",           text = "Say" },
        { value = "YELL",          text = "Yell" },
    }, function() return Config().channel or "AUTO" end,
        function(value) Config().channel = value end)

    grid:Note("|cffffd100The group I am in|r picks for itself: the instance "
        .. "group first, then the raid, then the party - which is what this "
        .. "did before there was a setting. Any other choice is taken "
        .. "literally, and when it is not available - Raid while you are in "
        .. "a party of three - the analysis is printed in your own chat "
        .. "frame and the reason is said out loud. A share that quietly "
        .. "goes nowhere is the one thing this must never do.")

    grid:Buttons({
        { text = "Open it", width = 120, style = "primary", onClick = function()
            ns.Death:Show()
        end },
        { text = "Share in chat", width = 130, onClick = function()
            ns.Death:Share()
        end },
    })

    grid:Note("Share posts the short version - where you were, who killed "
        .. "you, the total taken, the biggest hit and what was still ready. "
        .. "Words the client marks secret never go into chat; where a "
        .. "spell's name is withheld, the line says \"a spell\" rather than "
        .. "guessing. The window keeps the last ten deaths of the session in "
        .. "a list down its right side, and Share posts the one you are "
        .. "looking at - |cffffd100Clear list|r there throws them away.")

    ---------------------------------------------------------------------
    -- Your defensives
    --
    -- This list used to live on a Timeline page of its own, and that page
    -- is gone: what it drew live was the fight's next scheduled hit, which
    -- the replay answers afterwards with everything the panel could never
    -- show. The list was always read by this window anyway.
    --
    -- It decides three things: what the verdict calls "still ready", which
    -- presses get a bar in the replay, and how long that bar runs.
    ---------------------------------------------------------------------
    grid:Section("Your defensives")

    grid:Note("Pick them from the list on the right - what the Cooldown "
        .. "Manager knows for this character. These are the spells judged as "
        .. "defensives: the verdict says which were |cffffd100still ready|r "
        .. "when you fell, and the replay draws a bar for each one you did "
        .. "press. Readiness is our own estimate - your last cast plus the "
        .. "base cooldown - because the client will not let an addon read a "
        .. "live cooldown on this patch. Charges, resets and haste are not "
        .. "in it, so it says about and means it.")

    local SPELL_ROWS = 14
    local spellRows = {}
    for i = 1, SPELL_ROWS do
        local row = grid:FullRow("", { controlWidth = 90 })
        local remove = UI.Button(row.slot, "Remove", 90, function()
            if row.dkSpell and ns.db.defensives then
                ns.db.defensives[row.dkSpell] = nil
                ns.Options:Refresh()
            end
        end)
        remove:SetPoint("RIGHT", row.slot, "RIGHT", 0, 0)
        spellRows[i] = row
    end

    ---------------------------------------------------------------------
    -- Consumables
    --
    -- The owner: "wir brauchen zudem noch neben spells consumables wie
    -- traenke oder healthstones, das sind auch def cds". They ARE - and
    -- unlike a spell, the client still answers what their cooldown is, so
    -- this half of the list is a fact rather than an estimate.
    ---------------------------------------------------------------------
    grid:Section("Consumables")

    grid:Note("A healthstone that stayed in the bag is the same verdict as a "
        .. "defensive that stayed off cooldown, so they are judged in one "
        .. "list. Drinking one is a cast like any other on this patch, which "
        .. "means the replay draws it on the timeline with everything else. "
        .. "What is offered is whatever is in your bags right now.")

    UI.Dropdown(grid:FullRow("Add one", { controlWidth = 260 }),
        function()
            local out = {}
            local picked = ns.Death.PickedItems()
            for _, itemID in ipairs(ns.Death.BagConsumables()) do
                if not picked[itemID] then
                    out[#out + 1] = {
                        value = itemID,
                        text = ns.Death.ItemName(itemID) or ("Item " .. itemID),
                        iconTexture = ns.Death.ItemIcon(itemID),
                        itemID = itemID,
                    }
                end
            end
            return out
        end,
        function() return nil end,
        function(value)
            if not value then return end
            ns.Death.PickedItems()[value] = true
            ns.Options:Refresh()
        end, { emptyText = "Nothing usable found in your bags",
               search = true, rowHeight = 26 })

    local ITEM_ROWS = 8
    local itemRows = {}
    for i = 1, ITEM_ROWS do
        local row = grid:FullRow("", { controlWidth = 90 })
        local remove = UI.Button(row.slot, "Remove", 90, function()
            if row.dkItem then
                ns.Death.PickedItems()[row.dkItem] = nil
                ns.Options:Refresh()
            end
        end)
        remove:SetPoint("RIGHT", row.slot, "RIGHT", 0, 0)
        itemRows[i] = row
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

        for i, row in ipairs(spellRows) do
            local spellID = picked[i]
            row.dkSpell = spellID
            row:SetShown(spellID ~= nil)
            if spellID then
                row.label:SetText(ns.SpellName(spellID) or ("Spell " .. spellID))
                UI.MakeRowASpell(row, spellID)
            end
        end

        local items = {}
        for itemID in pairs(ns.Death.PickedItems()) do
            items[#items + 1] = itemID
        end
        table.sort(items, function(a, b)
            return (ns.Death.ItemName(a) or "") < (ns.Death.ItemName(b) or "")
        end)

        for i, row in ipairs(itemRows) do
            local itemID = items[i]
            row.dkItem = itemID
            row:SetShown(itemID ~= nil)
            if itemID then
                local count = ns.Death.ItemCount(itemID)
                row.label:SetText((ns.Death.ItemName(itemID)
                    or ("Item " .. itemID))
                    .. (count > 0 and ("  |cff9ba3af x" .. count .. "|r")
                        or "  |cff626a76none carried|r"))
                -- The icon and the item's own tooltip, the same treatment
                -- every spell in this addon gets.
                UI.MakeRowAnItem(row, itemID)
            end
        end

        grid:Refresh()
    end
end

---------------------------------------------------------------------------
-- The third column: the spell list, click to pick
--
-- The same pane the bars and the reminders use, with three callbacks of
-- ours. Not a copy - every second copy of a display in this addon has
-- drifted from the first, without exception.
---------------------------------------------------------------------------
function Page:BuildSide(parent, pad)
    local side = CreateFrame("Frame", nil, parent)
    side:SetAllPoints(parent)
    side:Hide()

    local width = parent:GetWidth() - pad * 2
    local C = UI.C

    local title = UI.Label(side, "Spells", UI.FS.card, C.text)
    title:SetPoint("TOPLEFT", side, "TOPLEFT", pad, -16)
    title:SetWidth(width - 96)
    title:SetWordWrap(false)

    local subtitle = UI.Eyebrow(side, "CLICK ONE TO MAKE IT A DEFENSIVE")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    subtitle:SetWidth(width - 96)
    subtitle:SetWordWrap(false)

    local host = CreateFrame("Frame", nil, side)
    host:SetPoint("TOPLEFT", side, "TOPLEFT", pad, -(UI.HEADER_H + 16))
    host:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -pad, pad)

    self.spellPane = ns.OptionsBars:BuildSpellPane(host, width, {
        Used = function()
            local used = {}
            for spellID in pairs((ns.db and ns.db.defensives) or {}) do
                used[spellID] = "Defensive"
            end
            return used
        end,
        -- A click TOGGLES. Picking is done from this list, so unpicking
        -- from it too is the one place a person looks second.
        Assign = function(spellID)
            ns.db.defensives = ns.db.defensives or {}
            if ns.db.defensives[spellID] then
                ns.db.defensives[spellID] = nil
            else
                ns.db.defensives[spellID] = true
            end
            ns.Options:Refresh()
        end,
        Hint = function(spellID)
            if ns.db and ns.db.defensives and ns.db.defensives[spellID] then
                return "Click to stop judging it as a defensive."
            end
            return "Click to judge it as a defensive."
        end,
    })

    self.side = side
    return side
end

function Page:Refresh()
    if self.spellPane and self.spellPane.Refresh then
        self.spellPane.Refresh()
    end
end
