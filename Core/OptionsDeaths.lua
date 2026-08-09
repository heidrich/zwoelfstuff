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
