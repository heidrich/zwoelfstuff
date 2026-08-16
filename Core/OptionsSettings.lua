---------------------------------------------------------------------------
-- OptionsSettings.lua - the Settings page
--
-- The last page to get its own file, and the delay is what made it a mess:
-- built inline in Options.lua it grew by accretion - a font here, a toggle
-- there - until "Text" held one font for the window and one for the bars,
-- and the page said "Applies to every bar" over rows about the minimap.
--
-- The grouping IS the fix. Three sections, one axis:
--
--   Every bar     what changes the bars on screen - all of them at once
--   This window   what changes the window you are reading this in
--   Ways in       how you reach the addon when this window is closed
--
-- What LEFT this page: "Take a layout from" and "Reset all settings" live on
-- Profiles now. Everything here changes how something looks or where a
-- button sits; those two change which settings you have at all - the same
-- rule that made Profiles its own page instead of a section here.
---------------------------------------------------------------------------
local _, ns = ...

local UI = ns.UI

local Page = {}
ns.OptionsSettings = Page

function Page:BuildPage(page, width)
    local L = ns.L
    -- NOT `explain = true` ANY MORE, and the pair matters: the PAGES entry
    -- dropped its third column, and `explain` here does not merely style the
    -- notes - it takes each one OUT of the layout and hangs it on the row
    -- above, to be shown in that column. With the column gone they would have
    -- been hidden with nowhere to appear, and every sentence on this page
    -- would have vanished silently.
    local grid = UI.Page(page, width)

    ---------------------------------------------------------------------
    -- Modules
    --
    -- First on the page, because these four decide what the REST of the
    -- window even has to show. Built from ns.Modules rather than typed out:
    -- a fifth module must appear here by existing, or this page becomes the
    -- place a feature goes missing.
    ---------------------------------------------------------------------
    grid:Section(L["Modules"])

    -- COUNTED, NOT TYPED. This said "Four" while six switches sat under it.
    grid:Note(L("%d features in one addon. Switch off what you do not want.",
        ns.Modules:Count()))

    for _, entry in ipairs(ns.Modules:All()) do
        UI.Toggle(grid:Row(L[entry.title], { sublabel = L[entry.blurb] }),
            function() return ns.Modules:IsOn(entry.key) end,
            function(value)
                ns.Modules:Set(entry.key, value)
                -- The rail and the page behind this one both change.
                ns.Options:Refresh()
            end)
    end

    grid:Buttons({
        { text = L["Show the welcome screen"], onClick = function()
            ns.Welcome:Show()
        end },
    }, 14)

    ---------------------------------------------------------------------
    -- Language
    --
    -- HERE AND NOWHERE ELSE. Owner, 2026-08-12: "Kein Modul, das ist fest in
    -- den settings" - and he is right for a reason worth writing down: a
    -- module is a feature you can want or not want, and nobody wants "no
    -- language". It is a property of the whole addon, like the window's scale
    -- two sections down.
    --
    -- Directly under Modules, because it is the other setting on this page
    -- that changes what every OTHER page looks like.
    ---------------------------------------------------------------------
    grid:Section(L["Language"])

    UI.Dropdown(grid:Row(L["Language"]), function()
        local items = { { value = "auto", text = L["Same as the game"] } }
        for _, entry in ipairs(ns.Locale.LANGUAGES) do
            local done, total = ns.Locale.Coverage(entry.code)
            local percent = total > 0 and math.floor(done / total * 100) or 0
            items[#items + 1] = {
                value = entry.code,
                -- HOW FINISHED IT IS, IN THE LIST. Nine of these are
                -- unfinished, and somebody picking one deserves to know that
                -- before the window redraws rather than after.
                text = entry.native
                    .. (percent < 100
                        and string.format("  |cff888888%d%%|r", percent) or ""),
            }
        end
        return items
    end, function() return ns.Locale.Chosen() end,
        function(value)
            ns.db.language = value
            ns.Locale:Apply()
            ns.Print(L["Pick a language, then reload."]
                .. " |cffffd100/reload|r")
        end)

    grid:Note(L["The window is drawn when it opens, so a new language reaches it after a |cffffd100/reload|r."]
        .. " " .. L["Missing lines are shown in English."])

    ---------------------------------------------------------------------
    -- Blizzard's Cooldown Manager
    --
    -- ACCOUNT-WIDE, WHICH IS WHY IT IS HERE. Both of these used to sit in a
    -- tab on the Cooldowns page - beside twenty rows that every one of them
    -- edits the ONE bar you have selected. A setting that belongs to the whole
    -- account, on a page where its neighbours belong to one bar, reads as a
    -- setting for that bar. Owner, 2026-08-15: "auch move die blizzard cdm
    -- einstellung in die normalen settings."
    --
    -- BUILT WHETHER THE MODULE IS ON OR OFF, and that is deliberate. This page
    -- is built ONCE, so a block behind `if Cooldowns is on` is a block that
    -- can never appear for anybody who switched it on afterwards - the same
    -- trap the stagger row on the Cooldowns page carries a comment about.
    ---------------------------------------------------------------------
    grid:Section(L["Blizzard's Cooldown Manager"])

    -- WHAT WE DO WITH THE ONES YOU DID NOT PLACE. Blizzard goes on drawing
    -- every cooldown it knows in its own viewers, so without this the bar you
    -- arranged sits next to a second, unarranged copy of the same icons.
    UI.Toggle(grid:Row(L["Hide the ones you did not place"]),
        function() return ns.db.takeOverCDM ~= false end,
        function(on)
            ns.db.takeOverCDM = on and true or false
            -- THE BARS AS WELL AS THE WINDOW. ns.Options:Refresh repaints
            -- this page and nothing on screen, so on its own the switch would
            -- look like it had done nothing until the next login.
            if ns.Cooldowns and ns.Cooldowns.Render then
                ns.Cooldowns.Render.Refresh()
            end
            ns.Options:Refresh()
        end)
    grid:Note(L["Blizzard's own viewers keep showing everything they know. "
        .. "This makes the ones you have not put on a bar invisible rather "
        .. "than hiding them - they are Blizzard's frames and hiding one is "
        .. "the thing that breaks them for the rest of the session."])

    grid:Note(L["Everything here comes from Blizzard's Cooldown Manager - it "
        .. "already knows the spells, binds the auras and has the timing, "
        .. "none of which an addon can do for itself on this patch. The "
        .. "reminders, the death log and the spell pickers all read it, and "
        .. "they go on doing so whether this module is on or off."])

    ---------------------------------------------------------------------
    -- Who else is doing this
    --
    -- THE SECTION ONLY EXISTS WHEN THERE IS A CONFLICT. A heading and the
    -- sentence "nothing else is managing them" costs a reader exactly as much
    -- as a real one and tells them about a problem they do not have.
    --
    -- Read at page-build time, and that is a real limit rather than an
    -- oversight: enabling an addon already requires a reload, so there is no
    -- moment where this and the game's own addon list disagree.
    ---------------------------------------------------------------------
    local rivals = ns.Cooldowns and ns.Cooldowns.Rivals
    local others = rivals and rivals.Others() or {}

    if #others > 0 then
        grid:Section(L["Who is managing your cooldowns"])

        local names = {}
        for index, entry in ipairs(others) do names[index] = entry.label end
        grid:Note(L("Also managing cooldowns on this account: %s.",
            table.concat(names, ", ")))
        grid:Note(L["Blizzard owns these frames and only one addon can hold "
            .. "them. Whichever loads second finds them already taken, and "
            .. "what you get on screen depends on the order they happened to "
            .. "load in - which is why this is a choice rather than something "
            .. "either addon can work around. Leave Cooldowns switched off to "
            .. "keep theirs, or switch theirs off and switch this on."])

        -----------------------------------------------------------------
        -- ONE BUTTON PER ADDON, AND IT ASKS TWICE
        --
        -- Owner, 2026-08-15: "einen button einbauen, das man andere cdm
        -- abstellt, das kann elle ui auch."
        --
        -- Two steps, disarming itself after four seconds - the same pattern
        -- as deleting a profile, which is the other place in this addon
        -- where one click does something you cannot take back in the same
        -- second. It reloads the interface, and a reload nobody expected is
        -- indistinguishable from a crash.
        --
        -- One button per addon rather than one for all of them. Two names on
        -- one button is a press whose consequences the label cannot state.
        --
        -- KEPT ON THE PAGE, so the desk can prove the button was actually
        -- made. Without a handle the only evidence that this branch works is
        -- that building it did not throw - and a grid:Buttons that quietly
        -- returned nothing would pass that, then do nothing on click for
        -- everybody who has a conflict, which is the only person who ever
        -- sees this branch at all.
        -----------------------------------------------------------------
        page.rivalButtons = {}

        for _, entry in ipairs(others) do
            local dependents = rivals.Dependents(entry.folder)
            local armed, button = false, nil
            local idle = L("Switch off %s", entry.label)

            local _, made = grid:Buttons({
                {
                    text = idle,
                    onClick = function()
                        local handle = button
                        if not handle then return end
                        if not armed then
                            armed = true
                            handle:SetText(L["Do it and reload?"])
                            -- Disarms itself. A button left sitting on
                            -- "really?" is one somebody clicks on their way
                            -- past a week later.
                            C_Timer.After(4, function()
                                armed = false
                                if handle and handle.SetText then
                                    handle:SetText(idle)
                                end
                            end)
                            return
                        end

                        armed = false
                        handle:SetText(idle)

                        local ok, why = rivals.Disable(entry.folder)
                        if not ok then
                            ns.Print("|cffff4040Not switched off|r - "
                                .. (why or "?") .. ".")
                            return
                        end
                        ReloadUI()
                    end,
                },
            })
            button = made
            page.rivalButtons[#page.rivalButtons + 1] = made

            if #dependents > 0 then
                -- THE ONE THING THEIR POWER BUTTON DOES NOT SAY. Disabling
                -- does not cascade: an addon that lists this one as a
                -- dependency just stops loading, silently.
                grid:Note(L("Careful: %s would stop loading as well, because "
                    .. "it needs that addon.", table.concat(dependents, ", ")))
            end
            grid:Note(L["Switches that addon off, switches Cooldowns on here, "
                .. "and reloads. Nothing is deleted - it is the same tick as "
                .. "in the game's own addon list, and putting it back there "
                .. "puts everything back with it."])
        end
    end

    ---------------------------------------------------------------------
    -- Sounds
    --
    -- THE FOUR MOMENTS, AND THIS IS THE ANSWER FOR ALL OF THEM. A sound
    -- picked for one SPELL is set where that spell already lives - on the
    -- panel it is requested from, on the reminder that watches it, on the
    -- cell it sits in - because that is where you are when you have an
    -- opinion about it. What belongs here is the answer for everything
    -- else, which is what nearly everybody will actually set.
    --
    -- CHOOSING ONE PLAYS IT. The picker's apply callback is the whole
    -- preview: nobody can pick a sound from a list of names, and a
    -- separate "test" button beside every row is three more controls for
    -- something the act of choosing can do on its own.
    ---------------------------------------------------------------------
    grid:Section(L["Sounds"])

    -- WHAT THE LIST WILL ACTUALLY HOLD, said out loud rather than left to be
    -- discovered. LibSharedMedia registers exactly one sound by itself -
    -- "None" - so on a machine with nothing else installed these four
    -- pickers offer one entry, and there is no way to tell that apart from a
    -- broken control by looking at it. Measured at a desk.
    --
    -- This addon ships no sounds on purpose; the argument is at the top of
    -- Core/Media.lua, and it is the same one that made us use the registry
    -- rather than our own list. What it owes anybody in that case is to say
    -- where sounds come from.
    if #ns.Media.List("sound") <= 1 then
        grid:Note(L["|cffffd100Your addons have not registered any sounds "
            .. "yet.|r They come from whatever else you have installed - "
            .. "BigWigs, Northern Sky and WeakAuras all bring their own. "
            .. "|cffffd100/zs sounds|r lists what is there."])
    else
        grid:Note(L["The list is every sound your other addons have "
            .. "registered - pick one and you will hear it. "
            .. "|cffffd100None|r is a real answer and silences that moment "
            .. "completely."])
    end

    for _, event in ipairs(ns.Sounds.EVENTS) do
        local key = event.key
        UI.MediaPicker(grid:FullRow(L[event.text], { controlWidth = 220 }),
            "sound",
            function() return ns.Sounds.Get(key) end,
            function(value) ns.Sounds.Set(key, nil, value) end,
            function() ns.Sounds.Preview(ns.Sounds.Get(key)) end)
    end

    grid:Note(L["A sound belongs to the SPELL, not to the place it sits in - so a "
        .. "cooldown you gave a sound of its own keeps it on the reminder "
        .. "and on the request panel alike."])

    ---------------------------------------------------------------------
    -- WHICH PACKS ARE IN THE LIST AT ALL
    --
    -- Owner, the first time he opened the picker: "die exwind sounds
    -- muessen alle raus oder geblockt werden, das sind 1000." Counted on
    -- his machine: 188 from one pack, 188 from the pack beside it, 19 from
    -- a third. Opening the shared registry was right - those are the sounds
    -- he already has - but four hundred undifferentiated rows is a haystack.
    --
    -- BY THE ADDON, NOT BY THE NAME. The names in a pack happen to share a
    -- bracketed prefix, and matching on that would work today and break the
    -- moment somebody renames one. The folder cannot be spelt two ways.
    --
    -- Built at DRAW time from what is actually registered, so it lists the
    -- packs this machine has rather than a hardcoded set - and a pack that
    -- is uninstalled simply stops appearing instead of leaving a dead row.
    local counts, order = ns.Media.Providers("sound")
    if #order > 0 then
        grid:Section(L["Where sounds come from"], "sound-packs")

        grid:Note(L["Switch a pack off and its sounds leave the four lists "
            .. "above. Nothing here changes what you have already chosen - "
            .. "a sound you picked goes on playing even if its pack is "
            .. "switched off."])

        for _, provider in ipairs(order) do
            local who = provider
            UI.Toggle(grid:Row(who, {
                sublabel = L("%d sounds", counts[who]),
            }), function() return not ns.Sounds.IsMuted(who) end,
                function(value)
                    ns.Sounds.SetMuted(who, not value)
                    ns.Options:Refresh()
                end)
        end
    end

    ---------------------------------------------------------------------
    -- This window
    ---------------------------------------------------------------------
    grid:Section(L["This window"])

    -- The window is drawn at 1360x760 and not everybody has the pixels for
    -- that - the owner's words: "nicht alle haben grosse screens". SetScale
    -- is live, so the row shows its own effect while being dragged through.
    UI.Slider(grid:Row(L["Scale"]), {
        get = function() return ns.db.windowScale or 1 end,
        set = function(value) ns.db.windowScale = value end,
        min = 0.6, max = 1.25, step = 0.05,
        -- scale: the box shows and takes PERCENT. Without it a typed "80"
        -- would store 80 and paint the window over four screens - the exact
        -- fault the visibility slider shipped once already.
        scale = 100,
        -- floor()ed, not left to %d: handing a float to %d is a truncation
        -- on the client's Lua 5.1 and an ERROR on the harness's 5.3, and the
        -- harness is right - the rounding should be spelled out.
        format = function(v)
            return string.format("%d%%", math.floor((v or 1) * 100 + 0.5))
        end,
        apply = function() ns.Options:ApplyScale() end,
    })

    grid:Note(L["The size of this window on your screen, not of anything on "
        .. "the bars. 100% is the size it was designed at; on a laptop 80% "
        .. "keeps all three columns in view. Takes effect as you change it."])

    -- HOW SOLID THE WINDOW IS. See Options:ApplyAlpha for why there is one
    -- alpha and not one per layer.
    --
    -- The floor is 70 rather than 0. A window you cannot see is a window you
    -- cannot close, and there is no second way back to this row once it is
    -- gone - the minimap button opens the same invisible frame.
    UI.Slider(grid:Row(L["Opacity"]), {
        get = function() return ns.db.windowAlpha or 0.94 end,
        set = function(value) ns.db.windowAlpha = value end,
        min = 0.7, max = 1, step = 0.02,
        scale = 100,
        format = function(v)
            return string.format("%d%%", math.floor((v or 1) * 100 + 0.5))
        end,
        apply = function() ns.Options:ApplyAlpha() end,
    })

    grid:Note(L["Lets the scene behind the window through. It fades the "
        .. "whole window at once, on purpose: fading each layer separately "
        .. "makes the values multiply where they overlap and no surface "
        .. "keeps its colour. Judge it in a bright zone, not a dark one."])

    -- TWO FONTS, TWO JOBS, TWO ROWS - and for a while there was only one row.
    --
    -- The comment that used to stand here said "this is not the same setting
    -- as Bar text above", and there was no Bar text row above: `ns.db.font`
    -- had a default, a translation and a reader, and the control that set it
    -- was gone. So the one setting that decides what every bar in the addon
    -- is written in could only be changed by editing a saved-variables file.
    -- The row is back, and it is directly above the window's own so the two
    -- can be told apart by standing next to each other.
    UI.MediaPicker(grid:FullRow(L["Bar text"], { controlWidth = 220 }), "font",
        function() return ns.ScreenFontName() end,
        function(value) ns.db.font = value end,
        function() ns.Profiles:Reload() end)

    grid:Note(L["Everything this addon draws OUT ON THE SCREEN - the names, "
        .. "the counts and the timers on your bars, icons and panels. The "
        .. "standard is Expressway: narrow, so more name fits in the same "
        .. "bar, and outlined, because all of it is read over a moving "
        .. "scene. If your client has no Expressway the closest face it does "
        .. "have is used."])

    -- Panel text is read in rows in a window; bar text is read at a glance
    -- over a moving scene. The design draws the window in a narrow grotesk,
    -- and the client's own face is not one - which is why this is a separate
    -- setting from the one directly above.
    UI.MediaPicker(grid:FullRow(L["Panel font"], { controlWidth = 220 }), "font",
        function() return ns.db.panelFont or ns.Media.PanelFont() end,
        function(value) ns.db.panelFont = value end,
        function() ns.Print("Panel font set. |cffffd100/reload|r to redraw the window in it.") end)

    grid:Note(L["The window you are looking at - its labels, values and "
        .. "headings."])

    -- THE WAY BACK TO THE STANDARD, and the reason it is a button rather than
    -- a promise in a changelog.
    --
    -- The version 7 -> 8 step moves only what still carries an OLD DEFAULT,
    -- because a colour somebody picked is theirs. That is the right rule and
    -- it leaves one honest gap: somebody who tried a colour, kept it for a
    -- month and now wants the house look back has nothing to press. This is
    -- that thing, it is the SAME rule with force, and it says how many
    -- settings it moved rather than "done".
    grid:Buttons({
        { text = L["Standard look"], onClick = function()
            local moved = ns.ApplyHouseLook(ns.db, true)
            if moved == 0 then
                ns.Print(L["Everything was already on the standard look."])
            else
                ns.Print(L("%d settings put back to the standard look.",
                    moved))
            end
            -- Profiles:Reload rather than Options:Refresh - the same
            -- sequence a profile switch runs. Refreshing the WINDOW would
            -- redraw the rows and leave every bar on screen wearing the old
            -- colours until the next login, which is the half of "it did
            -- nothing" that is hardest to argue with.
            ns.Profiles:Reload()
        end },
    }, 14)

    grid:Note(L["Puts every background, every border and every typeface back "
        .. "to the standard: #1a1a1a behind and around everything, opaque, "
        .. "and Expressway outlined on top. It touches only those - your "
        .. "bars, your spells, your positions and your sizes stay exactly "
        .. "where they are."])

    ---------------------------------------------------------------------
    -- Ways in
    ---------------------------------------------------------------------
    grid:Section(L["Ways in"])

    UI.Toggle(grid:Row(L["Minimap button"]),
        function() return ns.db.minimap.show end,
        function(value) ns.MinimapButton:SetShown(value) end)

    grid:Note(L["Left click opens this window, right click unlocks the "
        .. "panels for moving, and drag moves the button around the minimap "
        .. "edge."])

    UI.Toggle(grid:Row(L["Lock its position"]),
        function() return ns.db.minimap.locked end,
        function(value) ns.db.minimap.locked = value end)

    grid:Note(L["The button stays where you put it on the minimap edge, and "
        .. "dragging it does nothing until you unlock it again."])

    UI.Toggle(grid:Row(L["Game menu entry"]),
        function() return ns.db.gameMenu ~= false end,
        function(value) ns.GameMenu:SetShown(value) end)

    grid:Note(L["An entry in the game's own addon list."])

    grid:Layout()
    page.Refresh = function() grid:Refresh() end
end
