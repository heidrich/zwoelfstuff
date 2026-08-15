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
            -- NO KIND OF ITS OWN: these hold a spell ID, so they are "spell"
            -- like the list that fills them. Naming them "defensive" for one
            -- commit refused every drop out of that list and lit nothing up on
            -- the way - the kind is the type of the THING, not the name of the
            -- page it is on.
            --
            -- THESE SQUARES ARE NOT POSITIONS. `picked` is rebuilt sorted by
            -- name on every refresh, so which square a spell lands in is
            -- arithmetic rather than a choice - and swapping two of them would
            -- take both out, put both back and change nothing. Dragging one
            -- OUT still works: that is taking it off the list, which is the
            -- one thing these squares can actually say.
            ordered = false,
            get = function() return picked[index] end,
            onPick = function(spellID)
                if not spellID then return end
                ns.Death.Defensives()[spellID] = true
                ns.Options:Refresh()
            end,
            onClear = function()
                local spellID = picked[index]
                if spellID then
                    ns.Death.Defensives()[spellID] = nil
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
        .. "Right-click a slot to clear it.")

    ---------------------------------------------------------------------
    -- How long one of them lasts, when the game will not say
    --
    -- THIS SETTING LOST ITS PAGE AND NOT ITS PURPOSE. It sat on the cooldown
    -- bars page and its list read the bars' own cells - "pick a spell from
    -- your bars" - so when the bars went, the only way to state a number
    -- went with them. Nothing threw: Auras:SetActiveState is the ONLY writer
    -- of that store, so the store simply stayed empty and every replay bar
    -- fell through to the next source. A designed feature, silently
    -- unreachable, exactly like the item index the audit found.
    --
    -- It belongs here now, because the number has one reader left and it is
    -- on this page: Replay.BarLength asks for it FIRST for every press it
    -- draws in the death replay, before the measured store and before the
    -- tooltip. So the spells to offer are the defensives picked above -
    -- those are the presses the replay draws bars for.
    --
    -- Anything already carrying a number is listed too, even if it is no
    -- longer picked. A stored value with no row to edit it is a setting the
    -- player cannot take back, and dropping a spell from the list above is
    -- not the same as saying its duration was wrong.
    ---------------------------------------------------------------------
    grid:Section("Active for")

    grid:Note("Some defensives have no duration the game reports - a trinket, "
        .. "a potion, a racial. Say how long it lasts and the death replay "
        .. "draws that window instead of a bare mark.")

    local activeSpell

    local function TimedSpells()
        local out, seen = {}, {}
        local function Offer(spellID)
            if not spellID or seen[spellID] then return end
            seen[spellID] = true
            local seconds = ns.Auras:ActiveStates()[spellID]
            local name = ns.SpellName(spellID) or ("Spell " .. spellID)
            out[#out + 1] = {
                value = spellID,
                text = name .. (seconds and ("  |cff7ec6d4" .. seconds .. "s|r")
                    or ""),
                iconTexture = ns.SpellTexture(spellID),
                spellID = spellID,
                name = name,
            }
        end

        for spellID in pairs(ns.Death.Defensives()) do Offer(spellID) end
        for spellID in pairs(ns.Auras:ActiveStates()) do Offer(spellID) end

        table.sort(out, function(a, b) return a.name < b.name end)
        return out
    end

    UI.Dropdown(grid:FullRow("Spell", { controlWidth = 260 }), TimedSpells,
        function() return activeSpell end,
        function(value) activeSpell = value end,
        { emptyText = "Pick one of your defensives" })

    UI.Slider(grid:FullRow("Lasts", { controlWidth = 200 }), {
        get = function()
            if not activeSpell then return 0 end
            return ns.Auras:ActiveStates()[activeSpell] or 0
        end,
        set = function(value)
            if activeSpell then ns.Auras:SetActiveState(activeSpell, value) end
        end,
        min = 0, max = 120, step = 1,
        format = function(v)
            if (v or 0) < 1 then return "off" end
            return string.format("%ds", v)
        end,
        -- So the seconds beside the name in the list above are the ones just
        -- set, rather than the ones this page was opened with.
        apply = function() ns.Options:Refresh() end,
    })

    grid:Note("Zero switches it off. Remembered for the whole account, not "
        .. "per spec: a trinket lasts as long on every one of them.")

    ---------------------------------------------------------------------
    -- Consumables
    --
    -- The owner: "wir brauchen zudem noch neben spells consumables wie
    -- traenke oder healthstones, das sind auch def cds". They are, and
    -- unlike a spell the client still answers what their cooldown is - so
    -- this half of the list is a fact rather than an estimate.
    --
    -- Same slots, because to the person reading the window it is the same
    -- kind of thing: something you could have pressed and did not.
    --
    -- TWO WAYS IN, because an item is not a spell. It cannot come out of the
    -- spell list beside this page - that list holds no items - so either
    -- DRAG IT OUT OF YOUR BAGS onto a slot, which is what the game's own
    -- action bars accept and what the owner asked for, or click an empty one
    -- and pick from what you are carrying.
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
            -- Dropped off the cursor. The id is the client's own answer, so
            -- this path does not care whether the bag scan can see the item -
            -- which is the whole reason it is the better door.
            onDropItem = function(itemID)
                ns.Death.PickedItems()[itemID] = true
                ns.Death.ItemName(itemID)   -- asked to load, for the name
                ns.Options:Refresh()
            end,
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

    grid:Note("Drag anything out of your bags onto a slot.")

    ---------------------------------------------------------------------
    -- When you die
    ---------------------------------------------------------------------
    grid:Section("When you die")

    UI.Toggle(grid:Row("Record it"),
        function() return Config().record ~= false end,
        function(value) Config().record = value and true or false end)

    grid:Note("Reads the game's own death recap the moment you fall: what hit "
        .. "you, and what you still had.")

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

    grid:Note("The window with the quick analysis, up before you release.")

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

    -- A FULL-width row for the one control on this page that is not a
    -- switch. Half-width put a 150-pixel menu in the middle of the line
    -- with its label stranded at the far left and nothing beside it, and
    -- the buttons underneath then read as part of the setting rather than
    -- as the page's own actions.
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

    grid:Note("|cffffd100The group I am in|r picks the instance group, then "
        .. "the raid, then the party.")

    -- THE PAGE'S TWO ACTIONS ARE IN THE WINDOW'S HEADER BAND, beside the page
    -- title, with every other page's - see the PAGES table in Options.lua.
    -- They were the last thing on the page, under every setting: "open the
    -- log" is what you come to this page to do, and it was below the fold.

    grid:Layout()

    page.Refresh = function()
        wipe(picked)
        for spellID in pairs(ns.Death.Defensives()) do
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

    self.spellPane = ns.SpellPane:Build(host, width, {
        Used = function()
            local used = {}
            for spellID in pairs(ns.Death.Defensives()) do
                used[spellID] = "Defensive"
            end
            return used
        end,
        -- A click TOGGLES. Picking is done from this list, so unpicking
        -- from it too is the one place a person looks second.
        Assign = function(spellID)
            local picked = ns.Death.Defensives()
            picked[spellID] = not picked[spellID] or nil
            ns.Options:Refresh()
        end,
        Hint = function(spellID)
            if ns.Death.Defensives()[spellID] then
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
