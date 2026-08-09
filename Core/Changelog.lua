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
        version = "4.44.1",
        date = "2026-08-09",
        lines = {
            "The death window said \"no deaths this fight\" while Blizzard's own recap stood open. The deaths list lives in a differently named field of the damage meter's answer than this code read; fixed, and the Overall session is checked when the Current one is empty.",
            "Blizzard's own Death Recap is the tie-breaker now: when it opens, the id it opens with IS your death, and a window still showing \"not enough was readable\" repaints itself with the real events.",
            "The defensive picker shows each spell's icon, the client's own tooltip on hover, and a filter box - forty same-grey names tell you nothing.",
        },
    },
    {
        version = "4.44.0",
        date = "2026-08-09",
        lines = {
            "DEATHS. When you die, a window opens with what actually happened: the last ten seconds hit by hit - icon, damage, the health you had left after each - and a verdict on top. Whether one hit did most of it or it was a thousand cuts, when the last heal landed, which of your defensives were |cffffd100still ready|r, and whether a healthstone or a potion sat unused in the bags. |cffffd100Share in chat|r posts the short version to your group. The auto-open can be switched off on the Deaths page; |cffffd100/zs death|r opens it any time.",
            "TIMELINE. A panel with whatever the fight has scheduled next - the feed the boss mods run on - and your defensives under it, coloured by whether they are back. Pick them on the Timeline page; the death window judges the same list. Shows in combat, placed in Edit Mode. The client keeps an event's severity secret, so \"tank busters only\" is a filter no addon can build - it shows the next thing, whatever it is.",
            "Readiness is our own estimate - your last cast plus the spell's base cooldown - because live cooldowns are closed to addons on this patch. Charges and resets are not in it, so it says about, and means it.",
            "This window can be scaled: Settings, under This window, 60 to 125 percent, live while you drag it.",
        },
    },
    {
        version = "4.43.0",
        date = "2026-08-09",
        lines = {
            "The Settings page finally says what applies to what. Three sections, one axis: |cffffd100Every bar|r (taking the Cooldown Manager display over, the bar text font), |cffffd100This window|r (the panel font), and |cffffd100Ways in|r (the minimap button and the game menu entry). It used to say \"applies to every bar\" over rows about the minimap.",
            "\"Take a layout from\" and \"Reset all settings\" moved to the Profiles page. Everything on Settings changes how something looks; those two change which settings you have at all - and that is the page whose subject that is.",
            "\"Take a layout from\" had been broken since 4.42.0: picking a character always answered \"that character has no bars\", because the copy still read the old saved-variable shape that the profiles update moves everything out of. It reads the new one now.",
            "A character sharing your profile is no longer offered as a copy source. The copy empties every cell on the way over, so taking your own layout would have stripped the spells off your own bars.",
        },
    },
    {
        version = "4.42.1",
        date = "2026-08-09",
        lines = {
            "|cffffd100/zs|r listed a command that does not exist: |cffffd100/zs route|r stayed in the help after the MDT pull badges were parked, so typing it did nothing at all. A menu naming something that does nothing is worse than a shorter menu.",
            "The one-line description of |cffffd100/zs reset|r still said it restored every default. It resets the profile you are using, and nothing else.",
            "The README on the project page was rewritten - it had been describing a different addon, down to arrangements removed in 4.8.0 and a co-tank panel it called parked while shipping it.",
        },
    },
    {
        version = "4.42.0",
        date = "2026-08-09",
        lines = {
            "PROFILES. A set of settings now has a name of its own, and your character points at one. It starts out pointing at a profile named after itself - which is exactly how this worked before - so nothing moved when you updated. Point a second character at the same one and they really are the same settings rather than two copies drifting apart: change a colour on either and both have it.",
            "Make a new empty one, copy the one you are using, rename it - every character using it follows - or delete it. The last profile cannot be deleted, because something has to be in use, and there is no undo.",
            "SHARING, BY STRING. Copy what you built into a piece of text and paste it anywhere. You choose what travels - bars, reminders, the co-tank panel, saved looks, settings - each with its own tick, and |cffffd100one row per bar|r underneath, so \"here is my Bone Shield bar\" is a single string instead of a whole profile somebody has to unpick.",
            "The string remembers which class and specialisation made it and says so before anything is written. Your class, and the spells come with it; another, and the layout arrives with the cells empty - a Death Knight's cooldowns are not castable on a Paladin. Your character's NAME is not in it: a string is made to be pasted somewhere public.",
            "Nothing you already have is thrown away. Bars and reminders from a string are ADDED to yours, never swapped for them - there is no undo here, and a string somebody handed you must not be able to delete an evening's work. A saved look whose name you already use keeps both.",
            "The two aura strips on a co-tank row were drawing on top of each other. They sat at opposite ends of the same edge and grew towards each other - which sounds like it keeps them apart and does not, because eight icons fill more than half the row. Debuffs now run along the top of the row and buffs along the bottom, both left to right. If you never moved either strip, yours is moved for you; if you did, your arrangement stays exactly as you set it.",
            "|cffffd100/zs reset|r threw away your recorded procs while telling you it kept them, and it reset every character on the account instead of the one you typed it on. It now resets the settings you are using, and nothing else.",
            "|cffffd100Not shown by Blizzard|r is gone as a heading. Those were never a different kind of thing - they are your spec's cooldowns, and on a default setup they are most of the list. They sit under |cffffd100Cooldowns|r with the rest, the ones you arranged first. What was worth knowing is still said on the entry itself: Blizzard is not displaying that spell, so there is no frame to adopt yet, and one drag in Blizzard's own Cooldown Manager settings fixes it.",
        },
    },
    {
        version = "4.41.1",
        date = "2026-08-09",
        lines = {
            "Six files the addon never loads were being packaged with it. They did nothing on your machine, but they were dead weight in the download. The build leaves them behind now.",
        },
    },
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
