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

    -- Two fonts, two jobs, two sections. Panel text is read in rows in a
    -- window; bar text is read at a glance over a moving scene. The design
    -- draws the window in a narrow grotesk, and the client's own face is not
    -- one - which is why this is not the same setting as "Bar text" above.
    UI.MediaPicker(grid:FullRow(L["Panel font"], { controlWidth = 220 }), "font",
        function() return ns.db.panelFont or ns.Media.PanelFont() end,
        function(value) ns.db.panelFont = value end,
        function() ns.Print("Panel font set. |cffffd100/reload|r to redraw the window in it.") end)

    grid:Note(L["The window you are looking at - its labels, values and "
        .. "headings."])

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
