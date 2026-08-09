---------------------------------------------------------------------------
-- OptionsProfiles.lua - the Profiles page
--
-- Four things happen here and they are kept apart on purpose, because three
-- of them are harmless and one of them is not:
--
--   which profile this character uses        switching, instant, reversible
--   making another one                       new, copy, rename
--   deleting one                             two-step, no undo
--   giving one away and taking one in        strings
--
-- The page deliberately has no "replace everything with this string" button.
-- Bars and reminders that arrive are ADDED to what you have - see
-- Share.Apply, which says why at length. Somebody pasting a string they were
-- handed in a Discord must not be able to delete an evening's work with one
-- click, and there is no undo in this addon to walk it back with.
---------------------------------------------------------------------------
local _, ns = ...

local UI = ns.UI
local Page = {}
ns.OptionsProfiles = Page

---------------------------------------------------------------------------
-- WHAT IS TICKED FOR EXPORT, kept out here rather than in the saved
-- variables. It is a question about the NEXT string, not a setting - saving
-- it would mean a tick somebody made once quietly deciding what they share
-- three weeks later.
--
-- barIDs holds only the bars switched OFF. Absent means yes, so a bar built
-- after this page was last drawn travels rather than silently staying home.
---------------------------------------------------------------------------
local pick = {
    bars = true, reminders = true, coTanks = true,
    presets = true, settings = true,
    barIDs = {},
}

-- The string that has been read but not yet added, and what Decode said about
-- it. Both cleared the moment the text changes, so "Add it" can never act on
-- a payload from a string that is no longer in the box.
local pending, pendingWhy

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
-- The page
---------------------------------------------------------------------------
function Page:BuildPage(page, width)
    local grid = UI.Page(page, width)
    local Profiles = ns.Profiles
    local Share = ns.Share

    ---------------------------------------------------------------------
    -- Which one is in use
    ---------------------------------------------------------------------
    grid:Section("The one you are using")

    -- A FUNCTION, not a table. Another character's profile appears the moment
    -- they log out, and a list built once when the window was first opened
    -- would never show it.
    local function Choices()
        local out = {}
        for _, entry in ipairs(Profiles:List()) do
            local shared = #entry.users > 1
                and string.format("  |cff888888%d characters|r", #entry.users)
                or ""
            out[#out + 1] = {
                value = entry.name,
                text = string.format("%s  |cff888888%d %s|r%s", entry.name,
                    entry.bars, entry.bars == 1 and "bar" or "bars", shared),
            }
        end
        return out
    end

    local useRow = grid:FullRow("Profile", { controlWidth = 260 })
    UI.Dropdown(useRow, Choices,
        function() return ns.profileName end,
        function(value)
            local ok, why = Profiles:Use(value)
            if ok then
                ns.Print(string.format("Now using |cffffd100%s|r.", value))
            elseif why then
                ns.Print("|cffff4040Nothing changed|r - " .. why .. ".")
            end
        end)

    grid:Note("A profile is a set of settings with a name. Your character "
        .. "points at one, and it starts out pointing at a profile named "
        .. "after itself - which is exactly how this worked before profiles "
        .. "had names, so nothing moved when you updated.\n\n"
        .. "Point a second character at the same one and they really are the "
        .. "same settings, not two copies drifting apart. Change a colour on "
        .. "either and both have it.")

    ---------------------------------------------------------------------
    -- Making another
    ---------------------------------------------------------------------
    grid:Section("Make another")

    local newInput
    local newRow = grid:FullRow("New, empty", { controlWidth = 160 })
    newInput = UI.Input(newRow.slot, 160, function(text)
        local ok, why = Profiles:Create(text)
        if ok then
            newInput:SetText("")
            ns.Print(string.format("Made |cffffd100%s|r and switched to it.", text))
        else
            ns.Print("|cffff4040Not made|r - " .. (why or "no name") .. ".")
        end
    end, false, "a name")
    newInput:SetPoint("RIGHT", newRow.slot, "RIGHT", 0, 0)

    local copyInput
    local copyRow = grid:FullRow("Copy this one as", { controlWidth = 160 })
    copyInput = UI.Input(copyRow.slot, 160, function(text)
        local ok, why = Profiles:Create(text, ns.profileName)
        if ok then
            copyInput:SetText("")
            ns.Print(string.format("Copied into |cffffd100%s|r and switched to it.", text))
        else
            ns.Print("|cffff4040Not copied|r - " .. (why or "no name") .. ".")
        end
    end, false, "a name")
    copyInput:SetPoint("RIGHT", copyRow.slot, "RIGHT", 0, 0)

    local renameInput
    local renameRow = grid:FullRow("Rename this one to", { controlWidth = 160 })
    renameInput = UI.Input(renameRow.slot, 160, function(text)
        local from = ns.profileName
        local ok, why = Profiles:Rename(from, text)
        if ok then
            renameInput:SetText("")
            ns.Print(string.format("|cffffd100%s|r is now |cffffd100%s|r. Every "
                .. "character that used it follows.", from, text))
        else
            ns.Print("|cffff4040Not renamed|r - " .. (why or "no name") .. ".")
        end
    end, false, "a new name")
    renameInput:SetPoint("RIGHT", renameRow.slot, "RIGHT", 0, 0)

    grid:Note("A copy is a real copy: editing it later leaves the original "
        .. "alone. Renaming brings every character that was using it along, "
        .. "so nobody is left pointing at a name that no longer exists.")

    ---------------------------------------------------------------------
    -- Deleting one. Two steps, because there is no undo.
    ---------------------------------------------------------------------
    local armed, deleteStrip = false, nil
    deleteStrip = ButtonStrip(grid, {
        {
            text = "Delete this profile", width = 170, style = "primary",
            onClick = function()
                local button = deleteStrip.button
                if not armed then
                    armed = true
                    button:SetText("Really delete it?")
                    -- Disarmed by itself. A button left sitting on "really?"
                    -- is one somebody clicks on their way past a week later.
                    C_Timer.After(4, function()
                        armed = false
                        if button and button.SetText then
                            button:SetText("Delete this profile")
                        end
                    end)
                    return
                end

                armed = false
                button:SetText("Delete this profile")

                local gone = ns.profileName
                local ok, why = ns.Profiles:Delete(gone)
                if ok then
                    ns.Print(string.format("Deleted |cffffd100%s|r. This "
                        .. "character now has one of its own again.", gone))
                else
                    ns.Print("|cffff4040Not deleted|r - " .. (why or "?") .. ".")
                end
            end,
        },
    })
    deleteStrip.button = select(1, deleteStrip:GetChildren())

    grid:Note("Deletes the profile you are using, for every character using "
        .. "it - they each get a fresh one named after themselves on their "
        .. "next login. The last remaining profile cannot be deleted: "
        .. "something has to be in use. There is no undo.")

    ---------------------------------------------------------------------
    -- Out
    ---------------------------------------------------------------------
    grid:Section("Give one away")

    for _, part in ipairs(Share.PARTS) do
        UI.Toggle(grid:Row(part.label),
            function() return pick[part.key] end,
            function(value) pick[part.key] = value end)
        grid:Note(part.note)
    end

    -- ONE ROW PER BAR, so "here is my Bone Shield bar" is one string rather
    -- than a whole profile somebody has to unpick.
    local barRows = {}
    for index = 1, 12 do
        local row = grid:Row("")
        UI.Toggle(row,
            function()
                local cfg = ns.db.bars and ns.db.bars[index]
                return cfg and pick.barIDs[cfg.id] ~= false or false
            end,
            function(value)
                local cfg = ns.db.bars and ns.db.bars[index]
                if cfg then pick.barIDs[cfg.id] = value or nil end
            end)
        barRows[index] = row
    end

    ButtonStrip(grid, {
        {
            text = "Copy a string", width = 150, style = "primary",
            onClick = function()
                local parts = Share.Gather(ns.db, pick)
                if not next(parts) then
                    ns.Print("|cffff4040Nothing ticked|r - there is nothing to "
                        .. "put in a string.")
                    return
                end

                local text, why = Share.Encode({
                    stamp = Share.Stamp(),
                    label = ns.profileName,
                    parts = parts,
                })
                if not text then
                    ns.Print("|cffff4040Could not make a string|r - " .. why .. ".")
                    return
                end

                UI.CopyBox("Your ZwoelfStuff string", text,
                    "Ctrl+A then Ctrl+C. Paste it anywhere - it is text.")
            end,
        },
    })

    grid:Note("The string remembers which class and specialisation it was "
        .. "made on, and says so when somebody opens it. Your character's "
        .. "name is NOT in it: a string is made to be pasted somewhere "
        .. "public, and a layout is no reason to publish who built it.")

    ---------------------------------------------------------------------
    -- In
    ---------------------------------------------------------------------
    grid:Section("Bring one in")

    local preview
    local paste = UI.TextArea(grid.content, grid.width, 76, function()
        -- ANY change clears what was read. Otherwise "Add it" acts on the
        -- payload from the PREVIOUS string while the box shows a new one.
        pending, pendingWhy = nil, nil
        if preview then preview:SetText(" ") end
    end, "paste a ZwoelfStuff string here", 0)
    grid:Wide(paste, 84)

    ButtonStrip(grid, {
        {
            text = "Read it", width = 110,
            onClick = function()
                pending, pendingWhy = Share.Decode(paste.input:GetText())
                if not pending then
                    preview:SetText("|cffff4040" .. (pendingWhy or "?") .. "|r")
                    return
                end

                local bits = {}
                for _, line in ipairs(Share.Describe(pending)) do
                    bits[#bits + 1] = line.detail
                        and string.format("%s |cff888888(%s)|r", line.label, line.detail)
                        or line.label
                end

                local fits = Share.SpellsFit(pending.stamp)
                local spells
                if fits == true then
                    spells = "|cff40ff40Made on your class|r - the spells come with it."
                elseif fits == false then
                    spells = string.format("|cffff8040Made on a %s|r - the layout "
                        .. "comes across and the cells arrive empty.",
                        pending.stamp.class:lower())
                else
                    spells = "|cffff8040This one does not say which class made "
                        .. "it|r - the cells will arrive empty."
                end

                preview:SetText(table.concat(bits, "   ") .. "\n" .. spells)
            end,
        },
        {
            text = "Add it", width = 110, style = "primary",
            onClick = function()
                if not pending then
                    ns.Print("Press |cffffd100Read it|r first.")
                    return
                end

                local applied = Share.Apply(ns.db, pending, {
                    nextID = function() return ns.Bars:NextID() end,
                    keepSpells = Share.SpellsFit(pending.stamp) == true,
                })
                ns.Profiles:Reload()

                local said = {}
                if applied.bars then said[#said + 1] = applied.bars .. " bars" end
                if applied.reminders then said[#said + 1] = applied.reminders .. " reminders" end
                if applied.presets then said[#said + 1] = applied.presets .. " looks" end
                if applied.coTanks then said[#said + 1] = "the co-tank panel" end
                if applied.settings then said[#said + 1] = "the settings" end

                ns.Print("Added " .. (next(said) and table.concat(said, ", ")
                    or "nothing") .. ".")

                pending, pendingWhy = nil, nil
                paste:SetText("")
                preview:SetText(" ")
            end,
        },
    })

    preview = grid:Note(" ")

    grid:Note("Nothing is written until you press Add it, and nothing you "
        .. "already have is thrown away: bars and reminders from a string are "
        .. "ADDED to yours. The co-tank panel and the settings are single "
        .. "things, so those do get replaced.")

    grid:Layout()

    ---------------------------------------------------------------------
    -- Kept current
    ---------------------------------------------------------------------
    page.Refresh = function()
        -- The bar rows are built once and re-labelled, because the number of
        -- bars changes while this page is open - a string that arrives brings
        -- three more - and rebuilding the page from inside its own button
        -- would be pulling the floor up while standing on it.
        for index, row in ipairs(barRows) do
            local cfg = ns.db.bars and ns.db.bars[index]
            row:SetShown(cfg ~= nil and pick.bars)

            -- row.label, not a SetLabel method - UI.Row does not have one.
            -- Written as `if row.SetLabel then` first, which is a guard that
            -- would have been false forever: the rows would have stayed blank
            -- and nothing would have said why.
            if cfg then row.label:SetText(cfg.name or ("Bar " .. index)) end
        end

        grid:Refresh()
        grid:Layout()
    end
end
