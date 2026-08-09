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
        .. "bags. Nothing is saved between sessions: this is for the minute "
        .. "after dying, not for an archive.")

    UI.Toggle(grid:Row("Open the window right away"),
        function() return Config().openOnDeath ~= false end,
        function(value) Config().openOnDeath = value and true or false end)

    grid:Note("The window with the quick analysis, up before you release. "
        .. "Switched off, the death is still recorded and "
        .. "|cffffd100/zs death|r opens it when you want it.")

    ---------------------------------------------------------------------
    -- The last one
    ---------------------------------------------------------------------
    grid:Section("The last one")

    grid:Buttons({
        { text = "Open it", width = 120, style = "primary", onClick = function()
            ns.Death:Show()
        end },
        { text = "Share in chat", width = 130, onClick = function()
            ns.Death:Share()
        end },
    })

    grid:Note("Share posts the short version - total taken, the biggest "
        .. "hit, what was still ready - to the group you are in, and only "
        .. "there. Words the client marks secret never go into chat; where "
        .. "a spell's name is withheld, the line says \"a spell\" rather "
        .. "than guessing.")

    ---------------------------------------------------------------------
    -- What counts as available
    ---------------------------------------------------------------------
    grid:Section("What counts as available")

    grid:Note("The defensives judged are the ones picked on the "
        .. "|cffffd100Timeline|r page - one list for the panel and for this "
        .. "window. Readiness is estimated from your own casts plus base "
        .. "cooldowns, because the client withholds live cooldowns from "
        .. "every addon on this patch. \"Ready\" here means ready as far as "
        .. "that clock can tell.")

    grid:Layout()
    page.Refresh = function() grid:Refresh() end
end
