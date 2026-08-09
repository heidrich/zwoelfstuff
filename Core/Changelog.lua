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
        version = "4.58.0",
        date = "2026-08-09",
        lines = {
            "|cffffd100EXTERNAL COOLDOWNS - a new module, under Tank stuff.|r The cooldowns somebody ELSE presses on you: Blessing of Sacrifice, Pain Suppression, Ironbark, Life Cocoon and ten more. Pick the ones you care about, arrange them into a panel, place it where you want it.",
            "|cffffd100One click asks for one.|r In a five-man it whispers the healer of that class - the only person who has it. In a raid you can name somebody per spell.",
            "A slot nobody in the group can fill is not drawn at all, so the panel is only ever as wide as the help that actually exists.",
            "|cffffd100It does not count anybody's cooldown down, and it never will on this patch.|r Another player's instant cast is not announced to addons since 12.0.5, so \"ready in 1:12\" would be a guess - in the one moment you would believe it.",
            "|cffffd100/zs externals|r says who each slot would whisper.",
        },
    },
    {
        version = "4.57.2",
        date = "2026-08-09",
        lines = {
            "|cffffd100Zoom into the replay and drag the plot with the mouse|r to move along it. Not zoomed in, grabbing it still moves the window, the way it always did.",
        },
    },
    {
        version = "4.57.1",
        date = "2026-08-09",
        lines = {
            "|cffffd100DRAG A POTION OUT OF YOUR BAGS ONTO A CONSUMABLE SLOT.|r The same gesture as an action bar - drop it, or pick it up and click the slot.",
            "|cffffd100The list of what you are carrying was empty for everybody|r, always: it was reading the wrong field and comparing an icon to a category. Your potions and healthstones are in there now.",
            "|cffffd100You can type in the search fields.|r They had no mouse at all - the box drew, showed its hint, and could never be clicked into. A menu with a filter now opens ready to type.",
        },
    },
    {
        version = "4.57.0",
        date = "2026-08-09",
        lines = {
            "|cffffd100THE LIST OF HITS SCROLLS,|r and it no longer throws any away. It was capped at twelve rows so they would not run off the bottom of the window - which meant the deaths with the most to say were the ones losing hits.",
            "The list opens at the |cffffd100bottom|r, on the hit that killed you.",
            "The footer no longer prints across the last row. Its block grows upwards and the list now ends where the footer begins, so neither can land on the other however long either one gets.",
        },
    },
    {
        version = "4.56.2",
        date = "2026-08-09",
        lines = {
            "|cffffd100EVERY ICON IN THIS WINDOW WAS BLURRY,|r on every screen, and it was one wrong comparison: the addon asked whether your interface was dense and got an answer that is never yes. So it loaded the smallest drawing it ships and stretched it - a 22-pixel mark across 43 real pixels in a card header.",
            "It now measures how many real pixels one interface unit covers and loads the drawing that fits. Nothing about the art changed; it was always there.",
            "|cffffd100Diagnostics|r shows the measurement and which files it picked, so this never has to be argued from a screenshot again.",
        },
    },
    {
        version = "4.56.1",
        date = "2026-08-09",
        lines = {
            "|cffffd100The numbers on a co-tank's aura icons get a font of their own|r - the countdown and the stack count, under Co-Tanks, Auras. They were the last text in this addon you could not choose the face of, and they were drawn in two different faces depending on your patch.",
            "Under the hood: two things the reminders and the death log rely on used to be started by the Cooldown bars. Switch the bars off and a reminder would have run on a world nobody had looked at, and the death log would have kept reading the measurements of the spec you left.",
        },
    },
    {
        version = "4.56.0",
        date = "2026-08-09",
        lines = {
            "|cffffd100THIS ADDON IS FOUR THINGS, AND YOU PICK WHICH.|r Cooldowns, Co-Tanks, Reminders and the Death-log are modules now, and each one can be switched off under |cffffd100Settings|r. Off is not hidden: the module builds no frame and listens to nothing at all.",
            "Switch the |cffffd100Cooldowns|r module off and Blizzard gets its own icons back - every icon on your bars is one of its frames, so this hands them over rather than covering them up.",
            "A module you switched off keeps its page, greyed, with the switch on it - so nothing you set up can go missing behind a switch.",
            "New characters get a |cffffd100welcome window|r that asks which of the four they want. You can open it again any time from Settings or with |cffffd100/zs welcome|r.",
            "|cffffd100/zs modules|r says what is running.",
        },
    },
    {
        version = "4.55.1",
        date = "2026-08-09",
        lines = {
            "|cffffd100Post it to|r sits on a line of its own with air under it, so the two buttons read as the page's actions rather than as part of that setting.",
            "Worth knowing: a death recorded before 4.54.0 carries no consumables - it was captured when they were not part of the list. They appear in the footer of the |cffffd100next|r death after you pick them.",
        },
    },
    {
        version = "4.55.0",
        date = "2026-08-09",
        lines = {
            "THE PAGE IS CALLED |cffffd100Death-log|r NOW, with a skull in the rail - the same skull that sits on your screen counting deaths, rather than a second mark for one feature.",
            "|cffffd100Your defensives are SLOTS|r, at the top of the page where the work is. Drag a spell out of the list on the right and drop it in, or click it there; right-click a slot to clear it. The same picture the cooldown bars use, instead of a list of rows with a Remove button each.",
            "Consumables get the same slots. An empty one opens a menu of what you are actually carrying.",
            "The settings under them sit |cffffd100two to a line|r and their paragraphs are on the rows - point at one and it explains itself. Three switches used to fill a screen and a half with the right half of every line empty.",
        },
    },
    {
        version = "4.54.0",
        date = "2026-08-09",
        lines = {
            "THE TIMELINE PAGE IS GONE, and everything it held is on |cffffd100Deaths|r. The panel it drew showed the fight's next scheduled hit; the replay answers the same question afterwards with everything that panel could never show, and the defensives list it carried was always read by the death window anyway.",
            "Pick your defensives from the |cffffd100list on the right|r of the Deaths page - the same spell list the bars use. Click one to make it a defensive, click it again to stop. That list decides three things: what the verdict calls still ready, which presses get a bar in the replay, and how long that bar runs.",
            "|cffffd100CONSUMABLES ARE DEFENSIVES.|r A healthstone that stayed in the bag is the same verdict as a defensive that stayed off cooldown, so they are judged in one list. Add any usable consumable you are carrying; the window says whether it was ready and whether you had one at all. Drinking one is a cast like any other on this patch, so the replay draws it on the timeline with everything else.",
            "Unlike a spell, an item's cooldown is a fact the client still answers - so that half of the list is not an estimate.",
        },
    },
    {
        version = "4.53.0",
        date = "2026-08-09",
        lines = {
            "BARS ARE FOR DEFENSIVES, and only for the ones you picked on the Timeline page. A bar says \"this was up for this long\", and a Death Strike has nothing that is up - drawing it as one invented a state that does not exist. The rest of your rotation now has |cffffd100a row of its own|r right under the axis, as icons: moments, which is what they are.",
            "Every bar carries |cffffd100a line up to the time axis|r from the moment it was cast, so you can see where it starts without sighting across an empty gap.",
            "|cffffd100What you pressed|r as a caption is gone. A row of your own spell icons under a time axis needs no label.",
            "The list of defensives under a death is laid out as icons with tooltips instead of being written into a sentence that wrapped wherever it liked and left names stranded without their icon.",
        },
    },
    {
        version = "4.52.0",
        date = "2026-08-09",
        lines = {
            "EVERY DEFENSIVE GETS A BAR NOW. Most of them have a fixed length and the game writes it in the tooltip - so the addon reads it there. That is asking the client, not guessing, and it was the missing fourth source: what this press actually did, then the length you set yourself, then what has been measured on this spec, and finally the number in the tooltip.",
            "The word for \"seconds\" comes out of the client too, in whatever language it is installed in - a tooltip that says |cffffd1005 Sek.|r is read exactly like one that says 5 sec.",
            "Hovering a bar says which of the four it came from, so a length that looks wrong can be traced instead of doubted.",
        },
    },
    {
        version = "4.51.2",
        date = "2026-08-09",
        lines = {
            "|cffffd100/zs death cds|r says why a press has no bar under it. Four different things wear that one symptom - the Cooldown Manager is off, its buff section holds nothing, the ids are withheld, or the death you are looking at is older than the recorder - and only the game can say which. It prints all four.",
            "Worth knowing either way: a death captured before this build carries no measured windows and cannot be given any afterwards. The bars appear on the |cffffd100next|r death after a defensive has been up and fallen off once.",
            "|cffffd100Your casts|r is a line of its own now, instead of the tail of the verdict. Seven abilities wrapped that sentence over three lines and the judgement disappeared into the middle of a list.",
        },
    },
    {
        version = "4.51.1",
        date = "2026-08-09",
        lines = {
            "The footer under a death only writes what it actually knows now. |cffffd100ready|r and |cffffd10025s to go|r are answers; \"no known cooldown\" and \"not cast since login\" are the addon saying it cannot tell, five times in a row, in the space where the answer should be.",
            "The inline spell icons sit ON their line instead of standing above it - they had a fixed height, and an icon taller than the line hangs out of the top of it.",
            "The faces on the replay are bigger, and |cffffd100What you pressed|r sits above its own bars where the other two lanes carry their names.",
        },
    },
    {
        version = "4.51.0",
        date = "2026-08-09",
        lines = {
            "THE DEFENSIVE BARS RUN THEIR REAL LENGTH NOW. Every press drew as a stub before, because the only thing that knew how long a defensive lasts was a number you had to type in yourself. It is |cffffd100measured|r instead: while you play, the addon watches Blizzard's own buff display and writes down the window between a buff going up and going down - so a bar in the replay is the length that buff was actually up, on that press, in that fight. A buff that was still up when you died runs to the end and says so on hover.",
            "|cffffd100A face over every hit|r, and over every heal. The killer's portrait used to sit alone in the corner of the lane, which in a dungeon with twenty mobs on you answers for all of them and therefore for none. Now each hit carries the face of whatever dealt it and each heal the face of whoever cast it, and the hover says what that one source did to you across the whole window.",
            "The damage columns stand clear of the axis, so the seconds written on the line stay readable under twenty of them.",
            "|cffffd100Defensives used|r, not \"pressed\" - and the spells in it are drawn the way this game draws spells: an icon in front of the name and the client's own tooltip on hover. Same in the verdict and in the footer that lists what was ready.",
        },
    },
    {
        version = "4.50.0",
        date = "2026-08-09",
        lines = {
            "WHAT YOU PRESSED IS DRAWN AS BARS, not as icons in a row: each one starts where you cast it and runs for as long as it is up, so you can see whether it was still there when the hit landed. Two running at once stack instead of covering each other, and each keeps its own colour.",
            "|cffffd100Zoom|r, and the wheel scrolls the plot. Six presses inside two tenths of a second cannot be drawn apart at any icon size - so the plot shows less time instead. Playing, the view walks with the playhead; scroll it yourself and it stays where you put it until Restart or Stop.",
            "The axis is thicker and carries its seconds |cffffd100on|r the line, with half-second marks between them. The scale follows the zoom: a second and a half on screen gets a mark every half second.",
            "The killer's portrait is small and sits on the damage lane rather than filling the corner - in a dungeon there are twenty things hitting you and one large face claimed the whole picture for one of them.",
            "The health bar is red, the boxes around the icons are gone, and the Speed label sits next to its slider instead of eighty pixels away from it.",
            "A heal was recognised by comparing against two spell-event names written from memory. It is anything the client calls HEAL now - if the recap ever says SPELL_HEAL_ABSORBED, a heal would have been drawn as damage and counted into the wrong total.",
        },
    },
    {
        version = "4.49.0",
        date = "2026-08-09",
        lines = {
            "THE REPLAY HAS THREE LANES NOW. |cffffd100Damage on you|r above the axis, |cffffd100what you pressed|r below it, and |cffffd100healing on you|r under that - with the amount, the spell's icon and |cffffd100the name of whoever cast it|r, in their class colour. Healing used to be a green column in among the red ones; \"was anybody healing me\" is its own question and now it has its own row.",
            "The killer's portrait sits in the corner of the replay, and the hover says what HE did to you: how many hits, the total, the biggest, and which of his abilities landed. What else a mob can do is not something the client will tell an addon on this patch, and the tooltip says so rather than leaving a gap.",
            "The health bar says |cffffd100Your health|r over it. It is the only bar in the window and it was being read as the mob's.",
            "Speed is a slider from a quarter to triple, and the death window's size is a slider too - both were buttons walking a fixed list, and dragging to the one you want beats clicking past three you do not.",
            "The death window's buttons drew straight through the replay standing in front of it. Two windows in one layer: whichever you click comes forward now.",
        },
    },
    {
        version = "4.48.0",
        date = "2026-08-09",
        lines = {
            "HOW MANY DEATHS TO KEEP is yours to set now - |cffffd100three to fifty|r, ten as it was. They are kept for this character and survive logging out, so the number is how far back you want to be able to look. Lowering it drops the oldest at once rather than waiting for them to fall out one death at a time.",
            "The list beside the analysis shows twelve at a time and |cffffd100scrolls|r for the rest. Walking through deaths with the wheel over the analysis keeps the one you are reading in view; the wheel over the list itself scrolls the list.",
        },
    },
    {
        version = "4.47.1",
        date = "2026-08-09",
        lines = {
            "|cffffd100Restart|r on the replay: from the top, running. |cffffd100Stop|r rewinds and waits - the one you want when you are about to point at something - and Restart is the one you want when you just missed it.",
            "|cffffd100Play|r at the end of a replay starts it over rather than doing nothing. The clock had already run out, so un-pausing it changed nothing on screen: a button that looks live and moves nothing reads as broken.",
        },
    },
    {
        version = "4.47.0",
        date = "2026-08-09",
        lines = {
            "REPLAY. A window of its own with a time axis down the middle: what came in above it, |cffffd100what you pressed below it|r. Play, pause, stop and a speed from a quarter to double. Icons, numbers and the client's own tooltips on every mark, a health bar that drains as the playhead crosses them, and a defensive of yours drawn in the accent colour so it can be found at a glance. Anybody looking at an empty lower half can see that no defensive was pressed - which is the whole point of it.",
            "The presses are your own casts, recorded as you make them. The combat log is closed to addons on this patch; this is a live event about your own character that survived, so the addon knows what YOU did even where it cannot see what anybody else did.",
            "The verdict says it too, in one line: \"You pressed nothing in those seconds\", \"No defensive was pressed - you cast Death Strike, Heart Strike\", or which defensives you did use.",
            "YOUR DEATHS SURVIVE A RELOAD NOW. They were kept for the session only, so reloading - which happens after every settings change and every addon update - took the list and the skull with it. The last ten are kept for this character and read back when you log in. |cffffd100Clear list|r is still how they go.",
            "The event table has a head that says what its columns are, and every hit now shows |cffffd100what share of your health it took|r and |cffffd100the health you had left|r - as a number and as a percentage, in the row itself rather than only in the hover. On the killing blow that last column says how far past zero it went.",
            "A |cffffd100Size|r button beside Share, 70 to 130 percent. The moment you want this window smaller is the moment it is in front of you, not the moment you are in a settings page.",
            "The list down the side had all the air and the analysis had none: the verdict, the Close button and the defensives line all ran into the divider. Even margins on both sides of it now.",
            "The defensives you picked show their icons and answer a hover with the client's own tooltip - the picker had both since 4.44.1 and the list of what you picked did not.",
        },
    },
    {
        version = "4.46.0",
        date = "2026-08-09",
        lines = {
            "THE DEATHS OF THE SESSION NOW STAND IN A LIST down the right side of the window - time, where it happened, who did it. Click one and it opens; the wheel steps through them. The arrows beside the close cross are gone, because a list you can see beats a counter you have to walk. |cffffd100Clear list|r under it throws them away, and asks once first.",
            "WHERE IT HAPPENED is recorded with every death and says which kind of evening this was: |cffffd100M+12 - Ara-Kara - Avanoxx|r, |cffffd100Raid - Nerub-ar Palace (Heroic)|r, |cffffd100Open world - Duskwood|r. The boss's name comes from the pull itself, so a wipe on a boss says the boss and a death on the trash before it does not. It travels with the share.",
            "THE KILLER'S PORTRAIT sits beside the title when the client hands one over - the same 3D model Blizzard's own recap draws. Where it does not, the header simply starts at the margin: no empty box.",
            "Every hit in the list answers a hover with the client's own spell tooltip, plus what it did to you - the damage, the overkill, the health you had left after it. A melee swing has no spell to ask about and says what it knows itself.",
            "Where the share goes is yours to choose on the Deaths page: the group you are in, or party, raid, instance, guild, say, yell outright. A channel you picked that is not there - Raid while you stand in a party of three - prints in your own chat frame and says why, rather than posting nowhere in silence.",
            "|cffffd100/zs death clear|r empties the list from the command line.",
        },
    },
    {
        version = "4.45.0",
        date = "2026-08-09",
        lines = {
            "THE SKULL. A small icon appears with your first death of the session and counts them in its corner. Click opens the death window; drag it anywhere, any time, or lock it on the Deaths page. It never shows before anything has happened.",
            "The death window keeps the |cffffd100last ten deaths|r of the session - the arrows beside the close cross page through them, and Share posts the one you are looking at.",
            "Every hit in the list carries its icon now - a melee swing gets the sword rather than a hole - and the attacker's name stands in quiet grey beside it. The verdict names the killer: \"Melee from Heavyweight Golem for 109.5k\".",
            "The row list honours its own heading: hits older than the promised ten seconds stay off it, and when nothing recent was readable the heading says so instead of lying.",
        },
    },
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
