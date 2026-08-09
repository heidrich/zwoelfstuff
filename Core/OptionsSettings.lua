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
    local grid = UI.Page(page, width, { explain = true })

    ---------------------------------------------------------------------
    -- Every bar
    ---------------------------------------------------------------------
    grid:Section("Every bar")

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

    UI.MediaPicker(grid:FullRow("Bar text", { controlWidth = 220 }), "font",
        function() return ns.db.font end,
        function(value) ns.db.font = value end,
        function() ns.Screen:Render() end)

    grid:Note("Every piece of text on every bar, unless that one piece has "
        .. "been given its own font in the bar's own settings. The list is "
        .. "whatever your other addons have registered - so a font you "
        .. "installed for ElvUI or WeakAuras is already in it.")

    ---------------------------------------------------------------------
    -- This window
    ---------------------------------------------------------------------
    grid:Section("This window")

    -- The window is drawn at 1360x760 and not everybody has the pixels for
    -- that - the owner's words: "nicht alle haben grosse screens". SetScale
    -- is live, so the row shows its own effect while being dragged through.
    UI.Slider(grid:Row("Scale"), {
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

    grid:Note("The size of this window on your screen, not of anything on "
        .. "the bars. 100% is the size it was designed at; on a laptop 80% "
        .. "keeps all three columns in view. Takes effect as you change it.")

    -- Two fonts, two jobs, two sections. Panel text is read in rows in a
    -- window; bar text is read at a glance over a moving scene. The design
    -- draws the window in a narrow grotesk, and the client's own face is not
    -- one - which is why this is not the same setting as "Bar text" above.
    UI.MediaPicker(grid:FullRow("Panel font", { controlWidth = 220 }), "font",
        function() return ns.db.panelFont or ns.Media.PanelFont() end,
        function(value) ns.db.panelFont = value end,
        function() ns.Print("Panel font set. |cffffd100/reload|r to redraw the window in it.") end)

    grid:Note("The window you are looking at - its labels, values and headings. "
        .. "It is a separate setting from the bars on purpose: a face that is "
        .. "right over a moving 3D scene is rarely the one that is right for "
        .. "forty rows of settings. The list is whatever your other addons have "
        .. "registered.")

    ---------------------------------------------------------------------
    -- Ways in
    ---------------------------------------------------------------------
    grid:Section("Ways in")

    UI.Toggle(grid:Row("Minimap button"),
        function() return ns.db.minimap.show end,
        function(value) ns.MinimapButton:SetShown(value) end)

    grid:Note("Left click opens this window, right click moves the bars, and "
        .. "drag moves the button around the minimap edge.")

    UI.Toggle(grid:Row("Lock its position"),
        function() return ns.db.minimap.locked end,
        function(value) ns.db.minimap.locked = value end)

    grid:Note("The button stays where you put it on the minimap edge, and "
        .. "dragging it does nothing until you unlock it again.")

    UI.Toggle(grid:Row("Game menu entry"),
        function() return ns.db.gameMenu ~= false end,
        function(value) ns.GameMenu:SetShown(value) end)

    grid:Note("An entry under the last of Blizzard's own, where you look for "
        .. "an addon when you have forgotten what its slash command was. It "
        .. "stands down while you are in combat: pressing it closes the pause "
        .. "menu, and the game does not let an addon do that mid-fight.")

    grid:Layout()
    page.Refresh = function() grid:Refresh() end
end
