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

-- A LINE MAY CARRY A LINK, and most do not. A plain string is still a line -
-- six hundred of them are - and one that wants a button under it is written
-- as { text = "...", link = { label = "...", page = "deaths" } }. `page` is a
-- key of the options window; `open` names a window that has no settings page
-- of its own, out of News.OPENERS. See Core/News.lua.
-- WHAT A LINE SAYS, whichever shape it is in. Two windows draw this list -
-- the changelog page and the what's-new window - and each of them used to
-- decide for itself what a line was. The one that was written first did not
-- know about the table shape, so a single entry with an icon in it left the
-- page blank.
function ns.ChangelogText(line)
    if type(line) == "string" then return line end
    if type(line) == "table" and type(line.text) == "string" then
        return line.text
    end
    return ""
end

ns.CHANGELOG = {
    {
        version = "4.84.0",
        date = "2026-08-16",
        lines = {
            {
                icon = "Interface\\Icons\\Spell_Holy_PainSupression",
                text = "|cffffd100The answer bar gets an alert.|r When somebody "
                    .. "asks you for one of yours, a line goes up near the "
                    .. "middle of the screen - |cffffd100Akui asks for Pain "
                    .. "Suppression|r - flashing, in your font and colour. "
                    .. "You pick when it comes down: when answered, after "
                    .. "so many seconds, or so many flashes. One switch per "
                    .. "spell you offer, a sound per spell, placed in Edit "
                    .. "mode. Off until you switch it on.",
                link = { label = "Open the Alerts tab", page = "answers" },
            },
            {
                icon = "Interface\\Icons\\Spell_Holy_PowerWordShield",
                text = "|cffffd100The answer bar gets its display conditions|r "
                    .. "- always, only when..., never; combat, group, target, "
                    .. "rested, the kind of place, and |cffffd100the role you "
                    .. "are playing|r: as a tank, as a healer, as damage. "
                    .. "And the look it was missing: opacity when asked, name "
                    .. "size, the key, the shout's ring.",
                link = { label = "Open the answer bar", page = "answers" },
            },
        },
    },
    {
        version = "4.83.0",
        date = "2026-08-16",
        lines = {
            {
                icon = "Interface\\Icons\\INV_Misc_Wrench_01",
                text = "|cffffd100The Cooldown Manager is temporarily "
                    .. "disabled|r - we are not satisfied with the result. "
                    .. "The focus is on tank and group play features, and "
                    .. "there are a lot of other very good CDM addons that "
                    .. "do the job well.",
            },
            {
                icon = "Interface\\Icons\\INV_Misc_Gem_Pearl_01",
                text = "|cffffd100One look, out of the box.|r Every "
                    .. "background and border in the addon is #1a1a1a and "
                    .. "opaque, and everything drawn on your screen is set "
                    .. "in Expressway, outlined, never under 10 pixels. Your "
                    .. "own choices are kept - only settings still wearing an "
                    .. "older default move. |cffffd100Settings|r has a "
                    .. "|cffffd100Standard look|r button for when you want it "
                    .. "all back on purpose.",
            },
            {
                icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
                text = "|cffffd100Co-Tanks are Tank Unitframes now|r, and they "
                    .. "ship set up the way the author runs them - your own "
                    .. "row, only in an instance, growing up from below the "
                    .. "middle, flat texture, white name. A profile you have "
                    .. "tuned is not touched. The taunt button can be limited "
                    .. "to raids, and its macro button sits with its icon.",
                link = { label = "Open the tank unitframes", page = "cotanks" },
            },
            {
                icon = "Interface\\Icons\\Ability_Rogue_Feint",
                text = "|cffffd100The death window has a third column.|r "
                    .. "What you pressed, what you still had, and everything "
                    .. "else you cast are rows down the left now, with their "
                    .. "icons - the same in the replay. Left button held on "
                    .. "the replay's plot drags the yellow line. A potion is "
                    .. "pictured as the potion you drank, and a Healthstone "
                    .. "counts as a defensive.",
                link = { label = "Open the death log", open = "death" },
            },
            -- The one thing from that page a player can go looking for. Its
            -- number is untouched in your account file; only the row moved.
            {
                icon = "Interface\\Icons\\Spell_Holy_BorrowedTime",
                text = "|cffffd100\"Active for\" moved to the death log.|r It "
                    .. "was on the cooldowns page, and it still does the same "
                    .. "thing: say how long a trinket or a potion lasts and "
                    .. "the death replay draws that window.",
            },
        },
    },
    {
        version = "4.82.0",
        date = "2026-08-14",
        lines = {
            {
                icon = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
                text = "|cffffd100New: the group's deaths, as a log.|r Who "
                    .. "fell, when, and what ended them - for everybody, not "
                    .. "just you. A second icon with three skulls sits beside "
                    .. "the death one and opens it. Down the right are the "
                    .. "last pulls; click one to read it.",
                link = { label = "Open the group death log", open = "raiddeaths" },
            },
            {
                icon = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
                text = "|cffffd100Click a death and read their last ten "
                    .. "seconds|r - the same table your own death window "
                    .. "shows, for whoever the row names. A red mark down the "
                    .. "left edge of a hit means the game itself calls that "
                    .. "damage avoidable.",
                link = { label = "Open the group death log", open = "raiddeaths" },
            },
            {
                icon = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
                text = "|cffffd100Tonight, across pulls.|r At the top of the "
                    .. "pull list: what keeps killing the group - with how "
                    .. "many PULLS, which is what makes it a pattern rather "
                    .. "than a moment - and who keeps falling. Share in chat "
                    .. "sends whichever page you are reading.",
                link = { label = "Open the group death log", open = "raiddeaths" },
            },
            {
                icon = 10060,
                text = "|cffffd100Power Infusion can be requested.|r It joins "
                    .. "the external cooldown panel, and it asks ANY priest - "
                    .. "all three specialisations have it, so the shadow "
                    .. "priest is as good an answer as the healer.",
                link = { label = "External CD request", page = "externals" },
            },
            "|cffffd100Fixed: a request whispered to a name that does not "
                .. "exist.|r Across a realm border a group mate is "
                .. "\"Name-Realm\", and the whisper was addressed to the "
                .. "short name - so it reached nobody, and the game refused "
                .. "the send. The message still reads the short name; the "
                .. "envelope carries the full one. |cffffd100/zs chat|r says "
                .. "what your client allows if one ever goes missing again.",
            "|cffffd100Fixed: \"the game does not call this avoidable\" was "
                .. "never said.|r A recorded answer of no was being filed as "
                .. "\"the game did not say\", so no death could ever be given "
                .. "a clean bill. Nothing on screen looked wrong.",
            "|cffffd100Mob faces are portraits now,|r not tiny figures "
                .. "standing in a box, and they sit in front of the mob's "
                .. "name instead of in the clock column. Spec icons in front "
                .. "of the dead. Orange marks anything you can point at or "
                .. "click; red is what the row cost.",
            "|cffffd100A magnifier in front of a death|r marks the ones "
                .. "you can open, and the page you land on carries their "
                .. "portrait and their specialisation.",
            "|cffffd100Fixed: an opened death stood indented from its own "
                .. "window.|r Its sentences and its table began a button's "
                .. "width right of everything above them. |cffffd100Back to "
                .. "the pull|r has moved up into the window's header beside "
                .. "the close button - it changes which page you are on, so "
                .. "it belongs with the other window controls.",
            {
                icon = "Interface\\AddOns\\ZwoelfStuff\\Media\\logo",
                text = "|cffffd100New: this window.|r What changed since you "
                    .. "last played, once per update, with a way straight to "
                    .. "each thing. The whole history is under Changelog.",
                link = { label = "Changelog", page = "changelog" },
            },
        },
    },
    {
        version = "4.81.0",
        date = "2026-08-13",
        lines = {
            "|cffffd100Fixed: the external cooldown panel offered spells the person cannot cast.|r A priest in your group meant both Pain Suppression and Guardian Spirit on screen, though no priest has both. It now reads what everybody is actually playing and offers only what they can cast. Somebody too far away to read still gets their icon - an empty panel while you run into the room would be worse than one icon too many.",
            "|cffffd100A saved bar now holds the whole bar,|r not just its look: the sizes and colours, the grid it is laid out in, and the spells you put in it. Under |cffffd100Bars - Reuse|r, and the same goes for copying one bar onto another. |cffffd100Take the spells too|r switches it back off if you only ever wanted the styling. Where a bar sits on screen never travels.",
            "|cffffd100The Healing on you lane is gone from the death replay.|r It took a fifth of the window and was usually empty. The heals are still recorded and still counted in the death window.",
            "|cffffd100The description texts on the Raid Bar, Invites and Settings pages are translated|r - German for now. Their labels had been for months; the sentences under them had not, which read like an addon that gave up half way.",
            "|cffffd100New: |r|cffffd100/zs specs|r prints what the game says each specialisation is, and which one every request slot is waiting for.",
        },
    },
    {
        version = "4.80.0",
        date = "2026-08-13",
        lines = {
            "|cffffd100Take a cooldown off the bar while it is recharging.|r Under |cffffd100Bars - Behaviour - Fading and hiding|r. Ready is always on screen, and pressing something does not make it vanish: it stays as long as its buff is still running - Anti-Magic Shell, Blood Shield - and only goes once there is nothing left but the wait. Buffs and procs are treated the same way, so one setting works on a bar holding all of them.",
            "|cffffd100The others can close up behind it,|r or the place can stay empty - which is what it does unless you say otherwise. A display whose icons move around as cooldowns come and go has to be read again every time, and \"the third one is my stun\" is worth more than an empty square costs. |cffffd100Close up in the row|r keeps a grid's shape, so your second row stays your second row.",
            "|cffffd100A glow that runs round the icon|r instead of sitting on it, under |cffffd100Edge style|r. Movement catches your eye where a steady colour does not, which is the whole point of a proc marker.",
            "|cffffd100The ready glow can wait until you can actually cast it.|r |cffffd100Only when castable|r keeps the edge dark while you are short of the resource. It ignores range and target on purpose - a defensive with nothing targeted is not the same as one you cannot pay for.",
            "|cffffd100Fixed: the flash, the ready edge, the reminder and the greying did nothing on Cooldown Manager icons.|r They all asked the game one question that this version of WoW no longer answers, and an addon that gets no answer stays quiet - so it looked like four switches that did not work. They work again.",
            "|cffffd100Fixed:|r a setting added in an update showed an empty box instead of its value, because a setting only reaches your profile when the profile is made. It now shows what your bar is really doing.",
            "|cffffd100Fixed:|r switching tabs in the options kept the scroll position of the tab you left, so the new one opened with its first heading cut in half.",
            "|cffffd100Fixed:|r two settings looked like the same thing twice. |cffffd100Grey out while the aura is down|r and |cffffd100Grey out while the cooldown runs|r never touch the same icon - an aura has no cooldown - and now say so.",
        },
    },
    {
        version = "4.79.0",
        date = "2026-08-13",
        lines = {
            "|cffffd100A proc's buff now identifies itself.|r Patch 12.1 lets the game show the real buff - its own icon, its own timer, extensions and all - instead of our stopwatch, but only if the addon knows which buff belongs to which proc, and nothing in the game will tell it. So it watches: the glow comes up when the buff lands and goes down when it is spent, and whatever came and went with it three times running is the buff. Nothing to press and nothing to set. It needs to happen |cffffd100out in the world|r - in a dungeon the game hides your buffs from addons - so one proc on a target dummy is enough, for you and for everybody else who plays that spec.",
            "|cffffd100The aura icons on the co-tank panel have a sweep now,|r the round one you know from every cooldown. The game draws it from the buff's own timer, so a buff that gets extended sweeps to the new end instead of finishing early. |cffffd100Co-tanks - Auras - Sweep|r if you would rather not have it.",
            "|cffffd100Fixed:|r the Auras page still talked as though patch 12.1 were coming, on a client that already has it. It also said your buffs are hidden from addons everywhere - where you are standing decides that, and out in the world they usually are not.",
        },
    },
    {
        version = "4.78.1",
        date = "2026-08-13",
        lines = {
            "|cffffd100Fixed: the raid check window would not stay open.|r It appeared while you held the button down and disappeared again when you let go. A place on the raid bar hears the press and the release - it has to, or the markers stop working for anybody casting on key down - and the three buttons that are not spells were doing their job on both. Opened, then shut, faster than you could see. The pull timer and the ready check went out twice for the same reason.",
        },
    },
    {
        version = "4.78.0",
        date = "2026-08-13",
        lines = {
            "|cffffd100The addon speaks your language.|r Eleven of them, picked automatically from your client and changeable under |cffffd100Settings|r. German is finished; French, Spanish, Italian, Portuguese and Russian carry the whole interface; Korean and Chinese carry the words on the buttons. Anything not translated yet is shown in English rather than left blank, and the list says how far each language has got.",
            "|cffffd100New: a Raid Bar.|r Every raid marker, the eight world markers, the game's four pings, a ready check and a pull timer - on a bar you put together yourself and place where you like. The first twelve places can carry a key, set in the game's own key list. Under |cffffd100M+ and raid stuff|r, and switched off until you ask for it.",
            "|cffffd100The raid check window|r says who is fed, flasked, runed, buffed, how worn their gear is and what item level they are carrying. Nobody's client will tell yours what they are carrying, so everybody's addon answers for itself - which means it works for the people in your group who run this addon, and says nothing at all about the ones who do not, rather than guessing.",
            "|cffffd100New: an invite tool.|r Somebody whispers \"inv\" and they are in the group. Keywords are yours to choose, and it can listen in say and yell too, invite the guild by rank, accept invitations from friends, promote the people you name, and turn the party into a raid at five. Every one of those is off until you switch it on.",
            "|cffffd100The window is taller|r, because the list on the left ran out of room at thirteen pages. If it no longer fits your screen, |cffffd100Settings - Scale|r brings it back down.",
            "|cffffd100Fixed:|r on a setting with a second line under it, that line could run underneath the control on its right. It was most visible on the welcome window, where a feature's description was drawn through the NEW badge beside it.",
            "|cffffd100The welcome window is wider|r, so the eight features have room to say what they are.",
            "|cffffd100Fixed:|r a healer's name in the death replay was drawn with a colour the game could not read, on any client whose Lua is stricter than the one this was written on.",
            "|cffffd100The window builds a column when you open the page it belongs to,|r not all five the moment the window appears. Four of them belong to pages you may never visit that session, and one of them was being built even with its feature switched off. Measured: 1391 frames and about four megabytes, on every open.",
            "|cffffd100Diagnostics shows how much memory this addon is using.|r It is the reading the page was missing - everything else there says what the addon is doing to your client, and this says what it costs. Taken at most once every five seconds, because asking the client walks every addon you have loaded.",
            "|cffffd100Drag things where you want them.|r Pick a marker, a spell or a cooldown up out of any list and drop it on a place; drop it on a place that is taken and the two swap; pull one off into empty space and it comes off. Clicking still works exactly as before - this is the second way, not a replacement. The raid bar and the external-cooldown panel could not be dropped into at all until now.",
            "|cffffd100The mouse wheel scrolls the page and nothing else.|r It used to change whatever number the pointer happened to be over, which on a page you scroll is a setting changed by accident rather than a shortcut. Drag the rail or type into the box - both are aimed.",
            "|cffffd100The raid bar preview draws the bar at the size it really is.|r It was drawn at 40 pixels a button while the bar itself is 26, because those numbers came from the panel the page was modelled on. A preview now shows what you set, and only ever shrinks - to fit the page, never to look better.",
            "|cffffd100The spell list builds what you can see.|r It used to build a row for every spell you own the moment the column opened, and keep all of them for the session - a hundred and more, for a column that shows a dozen. It now builds the dozen and re-uses them as you scroll. Nothing about using it changes; it is the same list, in the same order, and it costs a fraction of what it did.",
        },
    },
    {
        version = "4.77.0",
        date = "2026-08-12",
        lines = {
            "|cffffd100The addon is on Wago as well as CurseForge.|r The same build, from the same release - take whichever you already use.",
            "|cffffd100About says where to get it, and how to reach us.|r Both stores under |cffffd100Where to get it|r, and |cffffd100Discord|r in the page header. None of them can open your browser, because no addon is allowed to hand a URL to one; each puts the address in a box you can copy from instead.",
            "|cffffd100A bar you switched off says so in the list.|r It looked exactly like a running one, and the only way to find out was to open its options again. The badge names the settled reasons only - switched off, or set to never show - because \"waiting for combat\" would be wrong a minute later and the list does not redraw when you pull.",
            "|cffffd100Edit mode's Move bars and Build say which one you are in.|r The current one is lit the way everything else in this window marks what is current. It was a dimmed label before, which is also how a button says it cannot be pressed.",
            "|cffffd100The welcome window has a second way out, and you can see it.|r Escape always closed it; a key nobody is told about is not an exit. |cffffd100Not now|r sits beside |cffffd100Let's go|r.",
            "|cffffd100Fixed:|r the welcome window and the Settings page both said \"Four features in one addon\" over six switches. The count comes from the list now.",
        },
    },
    {
        version = "4.76.0",
        date = "2026-08-11",
        lines = {
            "|cffffd100Every number is a slider again|r - a track with the value beside it. Drag it, click anywhere on it, roll the wheel over it, or type into the box. There is one numeric control in the whole addon, so every page, every panel and Edit mode changed at once.",
            "|cffffd100Each page's buttons are up in its header|r, beside the page name, instead of stacked in a column inside the page. On the pages that had that column it was taking a third of the width away from the preview it stood next to.",
            "|cffffd100About is a page instead of a wall of text|r, and the command list on it is the same one |cffffd100/zs|r prints in chat - so it cannot go out of date again. It had: it still advertised a command that no longer exists and was missing seven that do.",
            "|cffffd100Diagnostics opens with four readings|r - what the Cooldown Manager holds, how many cells on your bars are filled, how sharp the marks in this window are, and whether another cooldown addon is fighting for the same frames.",
            "|cffffd100Settings lost its right-hand column|r, which stood empty until you pointed at something. The explanations are on the page now.",
            "|cffffd100The window can be seen through|r - 94% by default, with a slider under |cffffd100Settings|r. It never goes below 70%: a window you cannot see is a window you cannot close.",
            "|cffffd100Cards and menus have some depth|r, and a menu casts a shadow rather than announcing itself with the same bright outline that marks the row you picked inside it.",
            "|cffffd100Fixed:|r a typed number could land outside its own slider - 1 became 1.2 on a range that only went to 1.",
            "|cffffd100Fixed:|r dragging a slider redrew the bar sixty times a second even while the number was not moving.",
        },
    },
    {
        version = "4.75.0",
        date = "2026-08-11",
        lines = {
            "|cffffd100The light and dark stripes are gone.|r They were meant to group a setting with its explanation without drawing a line, and in this window they did the opposite: half the page stands in two columns, and one stripe ran under a pair of them. Air does the grouping now - a sentence sits close to the setting it belongs to and further from the next one.",
            "|cffffd100Labels start where the headings do.|r The indent existed to keep text off the edge of a stripe. With the stripes gone it was just a gap at the front of every line.",
            "|cffffd100Arial Narrow is the default font again|r, for the window and for bar text. The file the last version picked up from other addons is a bold cut whatever its name says, which made the whole window heavier than it is drawn. It is still in the picker under |cffffd100Settings|r, along with everything else your addons register.",
            "|cffffd100About names the addons this one was written by reading|r - EllesmereUI, ElvUI, BigWigs, MRT, MDT, Details!, WeakAuras, Plater, LibOpenRaid - and says what was taken from them: no code, facts about the game's API that are written down nowhere else.",
        },
    },
    {
        version = "4.74.0",
        date = "2026-08-11",
        lines = {
            "|cffffd100Room around the words.|r Now that every setting sits on a ground of its own, it gets padding inside it instead of starting on the edge - taller rows, and a real gap under a heading rather than three pixels.",
            "|cffffd100Headings are not painted in the brightest white any more.|r The panel font is a bold face; full white on top of it was three emphases for one thing.",
        },
    },
    {
        version = "4.73.0",
        date = "2026-08-11",
        lines = {
            "|cffffd100The lines between settings are gone.|r Each setting and its explanation sit on a ground of their own instead, two shades taking turns. Nothing to look at, and the grouping reads without being pointed out.",
            "|cffffd100The window takes the font you already have.|r If any of your other addons ships |cffffd100Expressway|r it is used by default now - the settings page has been offering it for months while the window was quietly drawn in Arial Narrow. Pick any other under |cffffd100Settings|r.",
            "|cffffd100About says what this addon is|r, in the author's own words, and spells his name properly.",
        },
    },
    {
        version = "4.72.0",
        date = "2026-08-10",
        lines = {
            "|cffffd100You can see which features are running at a glance.|r A green light beside one in the list on the left means it is on, |cffff4040OFF|r in red means it is not.",
            "|cffffd100Headings are bigger than the settings under them|r - they used to be smaller, so the one word saying what a block IS was the faintest thing in it.",
            "|cffffd100The explanations line up with everything else|r, and a line no longer runs between a setting and its own explanation. The hairline sits under the pair now, with room to breathe on both sides.",
            "|cffffd100Set keys is a button in Edit Mode|r, in the box with the rest.",
            "|cffffd100The empty Keys section is fixed.|r Its two sentences were being handed to the row above it and hidden in that row's tooltip - which happened to every section that opens with a paragraph.",
        },
    },
    {
        version = "4.71.0",
        date = "2026-08-10",
        lines = {
            "|cffffd100You can ask for lust, and for a battle res|r - |cffffd100one slot each|r, not one per class. |cffffd100Lust|r asks whoever in the group has one: Bloodlust, Heroism, Time Warp, Primal Rage or Fury of the Aspects. |cffffd100Bres|r covers Rebirth, Raise Ally, Intercession and Soulstone.",
            "|cffffd100On the answering side you get your own.|r A mage's cell is Time Warp, a warlock's is Soulstone, and a shaman gets whichever lust his faction gave him - one press on the other side lights the right cell on everybody's bar.",
            "|cffffd100The co-tanks page matches the other two.|r The preview and the two buttons that act on it stay at the top while the settings scroll - they used to be at the very bottom - and the settings stand in two columns instead of one per line.",
        },
    },
    {
        version = "4.70.0",
        date = "2026-08-10",
        lines = {
            "|cffffd100The two pages are called External CD request and External CD answer.|r One asks for a cooldown, the other answers somebody asking. They were |cffffd100External cooldowns|r and |cffffd100Answering|r, which named neither end.",
            "|cffffd100The answer page is built like the request page.|r The spells you offer sit at the top and stay there while you scroll, with |cffffd100Move the bar|r, |cffffd100Set keys|r and |cffffd100What every cell would cast|r beside them - they used to be at the very bottom, past every setting.",
            "|cffffd100What you offer is a row of icons|r instead of a stack of switches. Click one to stop offering it; it goes grey and stays where it was.",
            "|cffffd100The settings stand in two columns|r, the way the rest of the window does.",
        },
    },
    {
        version = "4.69.0",
        date = "2026-08-10",
        lines = {
            "|cffffd100A button looks like a button everywhere.|r Actions were drawn three different ways - solid, outlined, or bare text with no surface at all.",
            "|cffffd100The orange is rare again.|r Fourteen buttons wore it, including |cffffd100Delete this profile|r and |cffffd100Reset all settings|r - the loudest things in the window were the two destructive ones.",
            "|cffffd100Buttons are as wide as their words|r instead of fifteen hand-typed widths.",
            "|cffffd100Half the explanation text is gone.|r What a setting does, in a sentence or two - not what the game will not allow.",
        },
    },
    {
        version = "4.68.1",
        date = "2026-08-10",
        lines = {
            "|cffffd100A Done button|r in the key mode, and Escape works from anywhere in it - not only while a square is waiting for a key. Every key is set the moment you press it, so leaving loses nothing.",
        },
    },
    {
        version = "4.68.0",
        date = "2026-08-10",
        lines = {
            "|cffffd100Setting a key is its own mode now.|r Press |cffffd100Set keys|r and the panel comes out with a square over every place - click one, press the key, Escape when you are done. No list of rows to count through.",
            "|cffffd100The buttons on a page stand one under the other|r, all the same width.",
        },
    },
    {
        version = "4.67.0",
        date = "2026-08-10",
        lines = {
            "|cffffd100Set your keys here|r, next to the slots they press - a |cffffd100Keys|r section on the External cooldowns page and on the Answering page. Click a row, press the key. Right-click clears it, and it tells you if the key was on something else. No trip to the game's key list needed; these ARE the game's keys, so they show up there as well.",
            "|cffffd100\"Let's go\" opens the addon.|r It asks you which features you want and then left you looking at nothing.",
            "|cffffd100Edit Mode hands the window back.|r Going in from the addon and coming out again reopens it - going in from the minimap opens nothing, because there was nothing to hide.",
        },
    },
    {
        version = "4.66.2",
        date = "2026-08-10",
        lines = {
            "|cffffd100This page reads as releases now|r - a line between them, room to breathe, and the version you are actually running marked |cffffd100INSTALLED|r.",
        },
    },
    {
        version = "4.66.1",
        date = "2026-08-10",
        lines = {
            "|cffffd100A taunt cell taunts what that tank is fighting|r, not what you happen to be looking at - which in a pull with adds is a different creature and a wasted taunt. If his target cannot be taunted, yours is used, so there is no press that does nothing.",
            "|cffffd100Keys for the external cooldown slots|r - the first eight places, under |cffffd100ZwoelfStuff|r in the game's own Key Bindings. The key shows in the corner of the slot. Answer cells now go up to eight as well.",
            "|cffffd100A quick menu on the answer bar.|r Move the mouse over the bar and a small button appears: who you answer, set right there instead of in the settings window.",
            "|cffffd100Tank stuff|r is now called |cffffd100M+ and raid stuff|r.",
        },
    },
    {
        version = "4.66.0",
        date = "2026-08-10",
        lines = {
            "|cffffd100Clicking an answer cell casts.|r It lit up, it took the press, and then nothing happened - no cast and no error either. The button was listening for the wrong half of the click, and with the game set to cast on key down, which is how it comes, the press was thrown away in silence.",
            "|cffffd100A taunt cell taunts your target|r instead of trying to taunt the tank who asked, which could never have worked.",
            "|cffffd100You choose who gets a row:|r the tanks, everybody in the group, or people you name yourself - with a row count. Groups that never assigned roles used to get an empty bar and no explanation.",
            "|cffffd100Six cells can have a key|r, in the game's own Key Bindings under |cffffd100ZwoelfStuff|r. The key shows in the corner of the cell.",
            "|cffffd100Only what you can actually cast is offered.|r A holy priest was given a Pain Suppression cell that could not work - and was telling the group it was ready.",
            "Optionally take the person as your target as well. Off: the cast does not need it, and you keep whoever you were healing.",
            "|cffffd100/zs answers|r now prints exactly what each cell would cast, straight off the button. If one of them ever goes quiet again, that line says why.",
        },
    },
    {
        version = "4.65.3",
        date = "2026-08-10",
        lines = {
            "|cffffd100Answer cells work across realms now.|r The click cast nothing at all if the tank was from another realm - the macro was addressing a name that, as far as the game was concerned, was not there.",
            "|cffffd100The co-tank panel no longer crashes on some machines and not others|r, and no longer takes Edit Mode down with it. One of the game's own answers about a group member is withheld on 12.0, and reading it threw.",
            "|cffffd100The keybinding shows up in the game's key list.|r It was being read by the wrong parser and never registered at all.",
        },
    },
    {
        version = "4.65.2",
        date = "2026-08-10",
        lines = {
            "|cffffd100A spell you switched off under \"What you can be asked for\" can be switched back on.|r It could be turned off exactly once and never back - one line of Lua that always stored the same answer whichever way you clicked.",
        },
    },
    {
        version = "4.65.1",
        date = "2026-08-10",
        lines = {
            "|cffffd100The taunt button can be moved now|r - it had a mover and a padlock and nothing that actually dragged it.",
            "|cffffd100The externals panel stops jumping back|r when you leave Edit Mode. Its position was being re-measured in the wrong units every time.",
            "|cffffd100The answer bar shows up in Edit Mode|r even when you are standing alone, so it can be placed before the group exists.",
            "|cffffd100The taunt button has its own look settings|r - border, colour, backdrop, opacity. The page said they existed; now they do.",
            "A panel set up before version 4.59 no longer throws on login.",
        },
    },
    {
        version = "4.65.0",
        date = "2026-08-10",
        lines = {
            "|cffffd100Answering - somebody asks, and a button lights up.|r When a tank asks for one of your cooldowns, the cell for that spell ON THAT TANK brightens; you click it and it goes off. Your own taunt answers a tank-swap request the same way. New page under Tank stuff, off until you switch it on.",
            "|cffffd100You can finally see whether the healer still HAS it.|r Their own client says so over an invisible addon channel, with the real length - so the slot shows a proper cooldown, not a guess. Somebody without the addon shows nothing at all rather than a hopeful clock.",
            "A green ring on your slot means somebody is casting it right now - sent when the spell actually goes out, not when they click.",
            "|cffff8040The addon never casts for you|r, and only people who also run it can light up. Everybody else still gets the chat line.",
        },
    },
    {
        version = "4.64.0",
        date = "2026-08-10",
        lines = {
            "|cffffd100Three ways to ask the other tank to taunt.|r A button on your screen, a real keybinding in the game's own Key Bindings under |cffffd100ZwoelfStuff|r, and a macro the addon writes for you - all three do the same thing, pick whichever fits your hands.",
            "|cffffd100The button is yours to style:|r pick its icon (your own taunt by default), its size, its border and its backdrop, and place it in Edit Mode like everything else. Off until you switch it on.",
            "|cffffd100Make the macro|r writes |cffffd100ZS Taunt|r with your icon and keeps it up to date - drag it onto a bar once and it stays right.",
        },
    },
    {
        version = "4.63.0",
        date = "2026-08-10",
        lines = {
            "|cffffd100Say it when you taunt.|r One line in chat the moment you press your taunt, so the other tank knows you took it - with what you taunted in it. On the Co-Tanks page under |cffffd100Taunts|r, and switched off until you ask for it.",
            "|cffffd100/zs taunt ask|r tells the other tank to take it. Put it in a macro and give it a key: that is the half of a tank swap an addon can actually help with.",
            "Write the sentence yourself: |cffffd100%t|r is what you taunted, |cffffd100%s|r the taunt you pressed, |cffffd100%n|r the other tank.",
            "|cffff8040What it cannot do, and says so on the page:|r tell you when the OTHER tank taunts. This patch does not announce another player's instant casts to addons at all, and every taunt is instant. Yours is readable, so it says yours.",
        },
    },
    {
        version = "4.62.0",
        date = "2026-08-10",
        lines = {
            "|cffffd100The co-tank and externals panels have a cog and a padlock in Edit Mode|r, the same two a cooldown bar has. Centre it, pin it, open its settings, or switch the whole thing off - from the panel itself.",
            "|cffffd100Pinned means it does not move.|r The panel you have finished placing stops being the thing a stray drag lands on. It still selects and still opens its settings.",
            "Both sit on a small strip above the panel, so they fit even when the panel is a single icon.",
        },
    },
    {
        version = "4.61.0",
        date = "2026-08-10",
        lines = {
            "|cffffd100Your externals were still there - the page just was not drawing them.|r An empty row of slots after a reload was a drawing fault, not lost settings. Nothing you picked was ever thrown away.",
            "|cffffd100Rows and columns, the same as a cooldown bar.|r Rows times columns is how many places there are to put a spell, and the preview above the settings IS that grid - what you arrange is what appears on your screen.",
            "|cffffd100Move the panel, Test mode and Who would be asked moved up|r to sit with the slots they act on, instead of forty rows further down.",
            "|cffffd100What you say|r now sits directly under |cffffd100Who to ask|r - the two belong together - and everything about the look follows below.",
            "A chat channel you switched off stayed off. It was coming back at every login.",
        },
    },
    {
        version = "4.60.2",
        date = "2026-08-09",
        lines = {
            "|cffffd100Your slots stay on screen while the settings scroll under them.|r Change the border or the size and watch it happen on the same picture, instead of scrolling back up to see what you did.",
        },
    },
    {
        version = "4.60.1",
        date = "2026-08-09",
        lines = {
            "|cffffd100Who to ask|r sits directly under your slots now, where it belongs - the two are the same decision seen twice.",
        },
    },
    {
        version = "4.60.0",
        date = "2026-08-09",
        lines = {
            "|cffffd100The externals panel has the same look settings a cooldown bar has|r - scale, opacity, icon zoom, border thickness, colour and texture, backdrop and its texture. Same rows, same words, same drawing code: what you learn on one you already know on the other.",
        },
    },
    {
        version = "4.59.1",
        date = "2026-08-09",
        lines = {
            "|cffffd100Pick as many channels as you like.|r A whisper to the one person who can cast it AND a line in party chat: the first is aimed, the second is insurance.",
            "Two that come out the same channel are sent once - a raid warning without assist IS raid chat, and you would have said it twice.",
            "The last one cannot be switched off, and a whisper with nobody to whisper no longer stops the others going out.",
        },
    },
    {
        version = "4.59.0",
        date = "2026-08-09",
        lines = {
            "|cffffd100The externals panel works like the cooldown bars now.|r Set how many slots you want, click one to mark it, then click a spell in the list to put it there. Right-click empties a slot. It was an ordered list before, which is why the slot count did nothing at all.",
            "|cffffd100Send it somewhere other than a whisper|r - party, raid, raid warning, say, yell. |cffffd100Party or raid|r picks the right channel for the group you are actually in: in a dungeon from the group finder that is NOT party chat, and a message sent there would have arrived nowhere.",
            "|cffffd100%n|r in your message is the person being asked, next to |cffffd100%s|r for the spell. In party chat \"Ironbark bitte!\" asks nobody in particular; \"Baum, Ironbark bitte!\" asks somebody.",
            "A raid warning outside a raid, or without assist, goes to the group instead of failing quietly.",
            "The |cffffd100Who to ask|r boxes were blank and now say what they do.",
        },
    },
    {
        version = "4.58.1",
        date = "2026-08-09",
        lines = {
            "|cffffd100The externals panel now appears in Edit Mode|r, with every slot you picked - so there is something to actually place. It was invisible there, which meant it could not be moved at all.",
            "|cffffd100Build your set whenever you like.|r The list no longer dims what your current group cannot cast: you pick your spells on a quiet evening, and who casts them is a separate question under |cffffd100Who to ask|r.",
        },
    },
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
