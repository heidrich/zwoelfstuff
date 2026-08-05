---------------------------------------------------------------------------
-- Changelog data.
--
-- Kept in its own file: it only ever grows, and it is data, not layout.
-- Rendered by the Changelog page in Options.lua.
---------------------------------------------------------------------------
local _, ns = ...

ns.CHANGELOG = {
    {
        version = "4.0.0",
        date = "2026-08-06",
        lines = {
            "Different approach. Everything before this tried to track auras itself, which cannot work on patch 12.0: aura data is secret, and the sanctioned replacement (Blizzard_AuraContainer) does not exist until 12.1 - measured on this client, creating one fails outright.",
            "Blizzard's Cooldown Manager already does all of it. It knows the spells, binds the auras and has the timing. Every addon that does cooldowns on this patch works the same way: it takes Blizzard's item frames and restyles them. DKstuff does that now too.",
            "NEW: bars. A bar is a grid of cells; each cell holds one spell. Set rows and columns and the grid in the options changes with them - that grid IS the bar, same rows, same columns, same order.",
            "Click an empty cell to choose a spell (the list comes from your own Cooldown Manager), drag one cell onto another to swap, right click to clear. Changing rows or columns re-flows what is there instead of scrambling or dropping it.",
            "The whole aura-tracking stack is parked until 12.1 - Engine, Groups, Catalog, CoTanks, Probe. The code is correct, it simply cannot run on a 12.0 client. The reason is written into the TOC next to them.",
            "The proc-glow display for Boiling Point stays: that buff is not in the Cooldown Manager data set, so it remains the only way to see it.",
            "On screen nothing is rendered from bars yet - the editor comes first, on purpose.",
        },
    },
    {
        version = "3.4.0",
        date = "2026-08-05",
        lines = {
            "THE BIG ONE: the aura engine reported itself unavailable on every client, so every engine-backed feature was dead - the display's aura slot, the co-tank aura strips, and every tracking group. Only the proc-glow route ever worked.",
            "Cause: the availability check tried to LoadAddOn('Blizzard_AuraContainer') first and gave up when that failed. There is no such addon. The AuraContainer frame type is built into the client - every reference implementation just calls CreateFrame. The gate could never open.",
            "The check now builds a container and looks at it, which is the only honest test, and reports WHY when it says no instead of a bare 'not available'.",
            "NEW: /dks group status - per spell, one of: slot refused (a bug here, with the error), registered but never seen (the ID is wrong or the aura was never up), or bound. Turns 'only one icon shows' into an answer.",
            "Slots that the engine refuses now say so in chat instead of vanishing into a pcall, and they keep their place in the order rather than silently closing the gap.",
        },
    },
    {
        version = "3.3.0",
        date = "2026-08-05",
        lines = {
            "NEW: /dks probe <spellID> - does that ID actually bind? A hidden slot is bound to the ID and the engine shows it exactly while that aura is on you, so the answer comes from your own client instead of from a database or from memory.",
            "It reports every bind and unbind with a timestamp, which is what tells a CAST spell apart from the aura it applies - the trap that cost this project two rounds on Boiling Point and another on Death and Decay.",
            "Nothing is read from the aura or even from the button: the show and hide handlers are registered inside the initializer, the one window where touching an engine button is legal, and the engine does the telling.",
            "Also on the Diagnostics page: type an ID, press Enter, watch for 20 seconds.",
        },
    },
    {
        version = "3.2.0",
        date = "2026-08-05",
        lines = {
            "Fixed: nothing could be dragged into place. The aura containers lay over their own anchor frames and swallowed every click - engine containers come mouse-enabled, and only the buttons had been told otherwise. Unlocking looked like it did nothing at all.",
            "Fixed: an unlocked group with no active auras was an invisible rectangle. Unlocked groups now show a tinted drag surface and stay visible even when switched off, so they can be placed before they ever light up.",
            "The spell list is now a row of icons. Click + to add, drag an icon to move it, right click to remove it. What you see is the order the group renders in - no more arrow buttons on a list of text rows.",
            "The group picker now creates and deletes groups itself: pick a group, or use '+ New icon group' / '+ New bar group' at the bottom of the same menu, with a delete on every entry.",
            "The spell browser opens with the cursor already in the search box - type the name, click the hit.",
        },
    },
    {
        version = "3.1.0",
        date = "2026-08-05",
        lines = {
            "The settings window was rebuilt. It was a flat list of steppers and checkboxes; it is now a proper panel - a sidebar of modules, a titled content area, settings as two-column cards, and a footer that stays put.",
            "New controls, all self-built and all matching: on/off switches instead of checkboxes, real sliders with a numeric readout, dropdown menus instead of button rows, and colour swatches that open the game's colour picker.",
            "Blizzard's slider, dropdown and checkbox templates have been renamed repeatedly across expansions and cannot be styled to match a custom panel, so none of them are used. Nothing here can break on a template rename.",
            "Pages are built on first view instead of at login, so the panel costs only what you actually open.",
            "New Diagnostics page: the check, dump, scan and catalogue commands as buttons, plus whether the aura engine is available on this client.",
            "New General page: the minimap button toggles and a two-step reset-everything.",
            "Rows that do not apply to your current settings are dropped from the layout rather than left visible, so the page closes up instead of showing gaps.",
        },
    },
    {
        version = "3.0.1",
        date = "2026-08-05",
        lines = {
            "Fixed: tracking groups threw at login. ns.CreateBorder returns a table of four textures, not a frame, so it never had Hide/Show/SetShown - and the group anchor called Hide() on its outline.",
            "Fixed: that one error disabled every feature after it. The login handler ran the features in one straight line, so a broken group meant no co-tank panel and no minimap button either. Each feature now starts on its own and a failure is reported by name.",
            "In fixed mode the slot container is sized to its group anchor instead of staying 1x1, so nothing can clip the buttons.",
            "The spell browser now repopulates itself after a respec or spec switch.",
        },
    },
    {
        version = "3.0.0",
        date = "2026-08-05",
        lines = {
            "NEW: tracking groups. As many as you like, icons or bars, each with its own spells, position, size and colours.",
            "Arrange them any way: grows left or right, rows up or down, fill by rows or by columns, wrap after any number for a grid. All of it applies live, in combat included.",
            "Two ordering modes. 'My order' gives every spell one fixed place that never moves, so muscle memory holds and bars can show spell names. 'Auto' lets the game pick and sort, which stays compact but moves things around.",
            "NEW: spell browser. Your talents, your whole spellbook including the specs you are NOT playing, and Blizzard's Cooldown Manager set - all read out of the live client, so it follows every respec and every patch by itself. Nothing is hardcoded. Manual spell IDs still work.",
            "NEW: bars can now actually drain. button:SetDurationBar hands a StatusBar to the game engine, which drains it from the aura's own duration - so a bar works even for auras no addon may read.",
            "Fixed, and this is the big one: the engine slot never bound anything. It used AddAuraFilter/AddAuraFrame, which do not exist. The real API is AddAuraGroup/AddAuraSlot with an initializeFrame callback - verified against four working 12.1 addons on this machine rather than guessed.",
            "Fixed: the container was given its unit BEFORE its content. Unit assignment re-evaluates event registrations, and those are gated on the container already having groups, so UNIT_AURA stayed unregistered and the container silently never updated.",
        },
    },
    {
        version = "2.1.0",
        date = "2026-08-05",
        lines = {
            "Minimap button: left click opens the settings, right click toggles the co-tank panel, drag moves it around the minimap edge. Self-built, no LibDBIcon.",
            "The addon now has an icon in the AddOn list and the addon compartment.",
            "Toggle both from the options, or with /dks minimap.",
        },
    },
    {
        version = "2.0.0",
        date = "2026-08-05",
        lines = {
            "NEW: co-tank panel. One row per tank in the group - health bar, name, health percent, every debuff on them and every buff they carry.",
            "Auras on other players are secret exactly like your own, so an addon cannot read a co-tank's boss debuff stacks at all. The panel hands the widgets to the game engine, which binds and times them itself.",
            "NEW: engine aura slot for the tracked buff. Blizzard_AuraContainer can bind a secret aura by spell ID and render it - real icon, real duration, real stacks. This replaces the proc-glow proxy where it works.",
            "The proc glow stays as the fallback and still drives the proc flash. Switch with /dks source engine or /dks source glow.",
            "Fixed: the options window clipped its last section - the proc glow row was added without raising the window height.",
            "Fixed: reserved aura rows left a large empty gap; three rows instead of five.",
            "Fixed: the inactive greyed-out state dimmed the whole frame, which would have dimmed the engine's aura button too. Only the placeholder dims now.",
        },
    },
    {
        version = "1.4.0",
        date = "2026-08-05",
        lines = {
            "Measured in game: every single buff on the player came back secret (0 readable, 18 secret). No addon can identify an aura this way - not Boiling Point, not any other.",
            "The cooldown viewers do hand out plain data, but only for buffs the Cooldown Manager tracks, and Boiling Point is not one of them.",
            "So the buff itself cannot be read. The proc can: Boiling Point empowers Blood Boil, and C_SpellActivationOverlay.IsSpellOverlayed(50842) is a plain boolean that never touches aura data.",
            "Route 5 added, driven off that proc glow. Timing comes from our own clock and our own 15s constant, so the swipe and countdown work normally.",
            "This is the same combat-safe technique EllesmereUIAuraBuffReminders uses for beacons it cannot read either.",
            "Added /dks glowlog to find the glowing spell ID, /dks glow <id or name> to set it, /dks glowduration to tune it.",
            "The dump now reports which APIs actually exist, combat state, whether the spell is in the Cooldown Manager data set at all, and the override-spell state - so 'API missing' can never again look like 'aura not found'.",
        },
    },
    {
        version = "1.3.0",
        date = "2026-08-05",
        lines = {
            "The cooldown viewer route only searched the two buff viewers; it now searches all four, including Essential and Utility.",
            "Added a fourth route: icon match. If a secret aura keeps a readable icon, it can be identified by comparing it against our own spell's icon.",
            "Added /dks dump - dumps every cooldown viewer entry and every player buff, marking icon matches. Run it WHILE the buff is up; it is the command that shows what actually exists.",
            "/dks check now reports all four routes.",
        },
    },
    {
        version = "1.2.0",
        date = "2026-08-05",
        lines = {
            "Fixed: Boiling Point was never found. It is a secret rotational proc, and those are invisible to BOTH aura queries - by ID and by name alike.",
            "Added a third lookup route: Blizzard's own cooldown viewer buff frames. They still bind such procs, and expose a plain auraInstanceID that yields duration and stacks.",
            "The irony: the Cooldown Manager will not let you add this buff, but it knows exactly when it is up.",
            "Display now only re-renders when the shown aura actually changes, so the polling never restarts the cooldown swipe.",
            "/dks check now reports all three routes separately, and says whether timing is available or only presence.",
            "Added /dks scan - lists the buffs an addon is allowed to read and counts the secret ones.",
        },
    },
    {
        version = "1.1.0",
        date = "2026-08-05",
        lines = {
            "Fixed: the addon threw on every aura change. Patch 12.0 made aura fields 'secret values', and a secret may not be used as a table key - which is exactly how 1.0.0 matched spell IDs.",
            "Aura lookup reversed: the spell ID now goes INTO the query via GetPlayerAuraBySpellID, so nothing secret is ever read.",
            "Added a fallback lookup by spell name, for auras whose applied ID differs from the tooltip or talent ID.",
            "Cooldown swipe now armed from a DurationObject, the only carrier a cooldown frame accepts since 12.0.1.",
            "Remaining time and stack count are now rendered by the game engine, since an addon can no longer compute them.",
            "Removed the 'red timer in the last 3s' option - it required comparing a secret value.",
            "Added /dks check and /dks status, plus a Diagnose button, to tell a wrong spell ID apart from a broken display.",
        },
    },
    {
        version = "1.0.0",
        date = "2026-08-05",
        lines = {
            "Isolated aura display - shows a single buff the Cooldown Manager cannot track.",
            "Ships tracking Boiling Point (spell 1265968), the Blood Death Knight Blood Boil empowerment.",
            "Two display modes: icon with cooldown swipe, or icon plus shrinking bar.",
            "Optional 'always show' mode that greys the display out while the aura is down.",
            "Self-built proc glow, optional proc sound, optional warning colour in the last seconds.",
            "Movable and lockable display with a 15 second test preview for positioning.",
            "Additional spell IDs can be tracked; the list doubles as a priority order.",
            "Full slash command set under /dks.",
        },
    },
}
