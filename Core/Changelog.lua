---------------------------------------------------------------------------
-- Changelog data.
--
-- Kept in its own file: it only ever grows, and it is data, not layout.
-- Rendered by the Changelog page in Options.lua.
--
-- WRITTEN FOR THE PERSON PLAYING, not for whoever picks the code up next.
-- What changed and what it does, in their words. The reasoning, the dead
-- ends and the measurements live in the commit messages and in the
-- development changelog, which is not in this repository.
---------------------------------------------------------------------------
local _, ns = ...

ns.CHANGELOG = {
    {
        version = "4.41.0",
        date = "2026-08-09",
        lines = {
            "FIRST PUBLIC RELEASE.",
            "BARS. Your own cooldown bars, as many as you like. A bar is a grid of cells - set the rows and columns, put a spell in each. Changing the shape re-flows what is already there instead of scrambling it. Grid, staggered, or puzzle, where every cell sits exactly where you dragged it.",
            "Any single cell can carry its own scale, offset, kind and visibility, and those settings travel with the SPELL rather than the slot - drag a cell somewhere else and they come along.",
            "EFFECTS, all off until you ask: a flash when a cooldown lands, an edge while the spell is up, a nag for the defensive you keep forgetting, a last-seconds warning, and greying out while a cooldown runs.",
            "RULES FOR WHEN A BAR IS ON SCREEN - combat, group size, target, rested, and the kind of place you are in. Every rule starts on |cffffd100any|r, so a rule you never set can never be the reason something is missing, and the panel tells you which rule is hiding it.",
            "PLACED ON SCREEN, NOT IN A PREVIEW. |cffffd100/zs unlock|r moves whole bars with snapping to the screen and to other bars; |cffffd100/zs build|r takes one apart cell by cell, with the spell palette beside it. Bars can be attached to each other so one follows the other.",
            "REMINDERS. Text on your screen when something is missing. Write the message, drag a spell onto it, and choose whether it fires when the buff is gone or while it is up. Size, colour, flashing, an icon beside it, and the same visibility rules the bars have.",
            "CO-TANK PANEL. One row per tank, you first, so rows never reorder mid-pull - health, absorbs, target ring, raid marker and indicators. The aura strips draw in test mode; live aura data for another player needs patch 12.1.",
            "A LOOK DOES NOT HAVE TO BE SET TWICE. |cffffd100Copy from|r takes another bar's style in one click, |cffffd100Save as|r stores it as a preset. Only sizes, spacing and colours travel - the spells and the grid stay with their own bar.",
            "Fonts and bar textures come from the shared media registry, so everything your other addons ship is in the pickers under the names you already know.",
            "HOW IT WORKS: every icon on your bars IS one of Blizzard's Cooldown Manager frames, moved onto your cell. It keeps the right icon, sweep, charges and timing, because on this patch an addon may not read aura data at all. Blizzard would leave a hole where an icon went, so cooldowns you have not placed are hidden too - |cffffd100Settings|r, |cffffd100Take the display over|r gives that row back.",
            "IF A SPELL IS MISSING FROM THE LIST: Blizzard's Cooldown Manager hides most spells by default, and one it is not displaying has no frame for this addon to adopt. Those appear under |cffffd100Not shown by Blizzard|r - move them into a viewer in Blizzard's own Cooldown Manager settings and they become usable here.",
        },
    },
}
