---------------------------------------------------------------------------
-- OptionsDeaths.lua - the Death-log page
--
-- Everything about dying: which spells and consumables count as defensives,
-- what is recorded, the skull on the screen, and where a death is shared.
-- The feature itself lives in Core/Death.lua and Core/Replay.lua and fires
-- on its own.
--
-- THE LIST COMES FIRST because it is the only thing here that is work. The
-- switches under it are set once and never touched again, and they were
-- standing in front of it. Its notes are on the rows rather than under
-- them, so the settings pair two to a line instead of running down a
-- screen and a half - the owner asked for both in one sentence: "das ui
-- muessen wir aufraeumen ... orientiere dich an den anderen fenstern".
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
    -- NOTES AS TOOLTIPS, like the bars page. This page had a paragraph under
    -- every switch, which pushed three toggles down a screen and a half and
    -- left the right half of every line empty. The owner looked at it and
    -- said so: "das ui muessen wir aufraeumen ... optionen kann man auch
    -- nebeneinander machen, orientiere dich an den anderen fenstern".
    --
    -- The words are not lost - they are on the row, where somebody who wants
    -- them points at it. Half-width rows then pair two to a line by
    -- themselves, which is what they were built to do.
    local grid = UI.Page(page, width, { tooltipNotes = true })

    ---------------------------------------------------------------------
    -- YOUR DEFENSIVES, first and as slots
    --
    -- At the top because it is the only thing on this page that is WORK:
    -- the switches below are set once and never touched again, and they
    -- were standing in front of the list you actually come here to edit.
    --
    -- Slots rather than rows, at the owner's word: the same picture the
    -- cooldown bars use, so a spell is dragged out of the list on the right
    -- and dropped, and right-click clears it. A list of named rows with a
    -- Remove button each is a form; this is the thing itself.
    ---------------------------------------------------------------------
    grid:Section("Your defensives")

    local SLOT, GAP, PER_ROW, SLOTS = 40, 8, 8, 16

    local slotHost = CreateFrame("Frame", nil, grid.content)
    local slotRows = math.ceil(SLOTS / PER_ROW)
    slotHost:SetHeight(slotRows * SLOT + (slotRows - 1) * GAP)

    -- Which spell each slot shows. Sorted by name and rebuilt on every
    -- refresh: the slots are a VIEW of the picked set, not an order of
    -- their own - a defensive is picked or it is not, and inventing a
    -- position for it would be a second thing to keep in step.
    local picked = {}

    local slots = {}
    for index = 1, SLOTS do
        local slot = UI.SpellSlot(slotHost, {
            size = SLOT,
            get = function() return picked[index] end,
            onPick = function(spellID)
                if not spellID then return end
                ns.db.defensives = ns.db.defensives or {}
                ns.db.defensives[spellID] = true
                ns.Options:Refresh()
            end,
            onClear = function()
                local spellID = picked[index]
                if spellID and ns.db.defensives then
                    ns.db.defensives[spellID] = nil
                    ns.Options:Refresh()
                end
            end,
        })
        local row = math.floor((index - 1) / PER_ROW)
        local col = (index - 1) % PER_ROW
        slot:SetPoint("TOPLEFT", slotHost, "TOPLEFT",
            col * (SLOT + GAP), -(row * (SLOT + GAP)))
        slots[index] = slot
    end

    grid:Wide(slotHost, slotHost:GetHeight(), 2, 10)

    grid:Note("Drag one out of the list on the right, or click it there. "
        .. "Right-click a slot to clear it. These are the spells judged as "
        .. "defensives: the verdict says which were still ready when you "
        .. "fell, and the replay draws a bar for each one you pressed. "
        .. "Readiness is our own estimate - your last cast plus the base "
        .. "cooldown - because the client will not let an addon read a live "
        .. "cooldown on this patch.")

    ---------------------------------------------------------------------
    -- Consumables
    --
    -- The owner: "wir brauchen zudem noch neben spells consumables wie
    -- traenke oder healthstones, das sind auch def cds". They are, and
    -- unlike a spell the client still answers what their cooldown is - so
    -- this half of the list is a fact rather than an estimate.
    --
    -- Same slots, because to the person reading the window it is the same
    -- kind of thing: something you could have pressed and did not. They
    -- cannot be dragged in from the spell list - it holds no items - so an
    -- empty one opens a menu of what is actually in your bags.
    ---------------------------------------------------------------------
    grid:Section("Consumables")

    local ITEM_SLOTS = 8
    local itemHost = CreateFrame("Frame", nil, grid.content)
    itemHost:SetHeight(SLOT)

    local carried = {}

    local function OfferItems(owner)
        local items = {}
        local have = ns.Death.PickedItems()
        for _, itemID in ipairs(ns.Death.BagConsumables()) do
            if not have[itemID] then
                items[#items + 1] = {
                    text = ns.Death.ItemName(itemID) or ("Item " .. itemID),
                    iconTexture = ns.Death.ItemIcon(itemID),
                    onClick = function()
                        ns.Death.PickedItems()[itemID] = true
                        ns.Options:Refresh()
                    end,
                }
            end
        end
        if #items == 0 then
            items[1] = { text = "Nothing usable in your bags", disabled = true }
        end
        UI.ShowMenu(owner, {
            items = items, width = 300, search = true, rowHeight = 26,
            foot = "What you are carrying right now",
        })
    end

    local itemSlots = {}
    for index = 1, ITEM_SLOTS do
        local slot = UI.SpellSlot(itemHost, {
            size = SLOT,
            get = function() return carried[index] end,
            texture = function(itemID) return ns.Death.ItemIcon(itemID) end,
            tooltip = function(tip, itemID)
                return pcall(tip.SetItemByID, tip, itemID)
            end,
            onEmptyClick = function() OfferItems(itemHost) end,
            onClear = function()
                local itemID = carried[index]
                if itemID then
                    ns.Death.PickedItems()[itemID] = nil
                    ns.Options:Refresh()
                end
            end,
        })
        slot:SetPoint("TOPLEFT", itemHost, "TOPLEFT",
            (index - 1) * (SLOT + GAP), 0)
        itemSlots[index] = slot
    end

    grid:Wide(itemHost, SLOT, 2, 10)

    grid:Note("Click an empty slot to pick from what you are carrying; "
        .. "right-click a filled one to drop it from the list. A healthstone "
        .. "that stayed in the bag is the same verdict as a defensive that "
        .. "stayed off cooldown, so they are judged together - and drinking "
        .. "one is a cast like any other on this patch, so the replay draws "
        .. "it on the timeline with everything else.")

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
        .. "our own clock, and whether a potion was in the bags. They are "
        .. "kept for this character and survive logging out; anything past "
        .. "the number beside this falls off the end, and |cffffd100Clear "
        .. "list|r in the window empties them.")

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

    grid:Note("Ten by default, three to fifty. Lowering it drops the oldest "
        .. "immediately, and there is no undo. The window shows twelve at a "
        .. "time and the list scrolls.")

    UI.Toggle(grid:Row("Open the window right away"),
        function() return Config().openOnDeath ~= false end,
        function(value) Config().openOnDeath = value and true or false end)

    grid:Note("The window with the quick analysis, up before you release. "
        .. "Switched off, the death is still recorded and "
        .. "|cffffd100/zs death|r opens it when you want it. Its size is the "
        .. "|cffffd100Size|r button in the window itself - the moment you "
        .. "want it smaller is the moment it is in front of you.")

    ---------------------------------------------------------------------
    -- The skull on the screen
    ---------------------------------------------------------------------
    grid:Section("The skull on the screen")

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

    UI.Dropdown(grid:Row("Post it to", { controlWidth = 150 }), {
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
        .. "group first, then the raid, then the party. Any other choice is "
        .. "taken literally, and when it is not available - Raid while you "
        .. "are in a party of three - the analysis is printed in your own "
        .. "chat frame and the reason is said out loud. A share that quietly "
        .. "goes nowhere is the one thing this must never do. Words the "
        .. "client marks secret never go into chat.")

    grid:Buttons({
        { text = "Open it", width = 120, style = "primary", onClick = function()
            ns.Death:Show()
        end },
        { text = "Share in chat", width = 130, onClick = function()
            ns.Death:Share()
        end },
    })

    grid:Layout()

    page.Refresh = function()
        wipe(picked)
        for spellID in pairs((ns.db and ns.db.defensives) or {}) do
            picked[#picked + 1] = spellID
        end
        table.sort(picked, function(a, b)
            return (ns.SpellName(a) or "") < (ns.SpellName(b) or "")
        end)
        for _, slot in ipairs(slots) do slot.Refresh() end

        wipe(carried)
        for itemID in pairs(ns.Death.PickedItems()) do
            carried[#carried + 1] = itemID
        end
        table.sort(carried, function(a, b)
            return (ns.Death.ItemName(a) or "") < (ns.Death.ItemName(b) or "")
        end)
        for _, slot in ipairs(itemSlots) do slot.Refresh() end

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
