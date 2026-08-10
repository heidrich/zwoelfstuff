# ZwoelfStuff

**A tank and group-play focused addon, from Zwoelf — EU-Destromath.**

After many years I have built a new addon again, one that serves my own needs
as a tank first, and those of my M+ groups and friends. You will find a lot of
these features in other addons too — but like everybody, I have my own ideas
about what I want in the game. Hence this addon. I hope it is as useful to you
as it is to me.

1. **Bars** — your own bars, as many as you like. A bar is a grid of cells; you
   set the rows and columns and put a spell in each cell. Grid, staggered, or a
   puzzle where every cell sits exactly where you dragged it.
2. **Arranged on screen, not in a preview.** Bars are placed in edit mode and
   taken apart cell by cell in build mode, with snapping to the other bars, the
   screen edges and a grid.
3. **Per bar and per cell**: size, textures, colours, the cooldown sweep, the
   effects that fire when something comes back up, and rules for when the bar
   is on screen at all.
4. **Reminders** — a line of text on screen when a buff has fallen off, or
   while it is up. You write the sentence.
5. **A co-tank panel** — one row per tank, health, absorbs and aura strips.
6. **Profiles, and sharing by string** — name a set of settings, point several
   characters at it, or paste it to somebody else.

Auras the Cooldown Manager does not carry are handled on the bars like anything
else. The separate single-aura window that used to be point 2 here was removed
in 4.4.0 — a second window showing one buff was two answers to one question.

> **Status:** published on CurseForge and in use. `/zs test` runs 1264 checks on
> the model and the rules; what it cannot check is how it *looks*.
> `/zs report` hands back the procs it has recorded on your class and spec —
> that is the thing worth sending back.

## Standing on other people's shoulders

This addon was written by reading other addons — **EllesmereUI**, **ElvUI**,
**BigWigs**, **Method Raid Tools**, **Mythic Dungeon Tools**, **Details!**,
**WeakAuras**, **Plater**, **LibOpenRaid** and a few more. Their authors have
our thanks.

**No code was copied from any of them.** What we took is a different thing:
*facts about the game's API.* Which field a table actually carries, which event
fires first, which call answers on a fresh login and which one returns nothing
until a frame later, which values the client withholds in a dungeon. None of
that is documented anywhere, and on a patch that keeps closing doors it is
often not discoverable at all except by reading code that already works.

So the comments in `Core/` cite those addons by name and by line, and they say
"read off working code on this machine" rather than pretending we knew. That is
deliberate. A number nobody can re-check is a number that quietly goes wrong
two patches later — see [`Core/CDM.lua`](Core/CDM.lua), which is mostly a
record of where each fact came from.

If you are one of those authors and you would rather not be named here, say so
and we will take the citation out.

## Why it works this way

Patch 12.0 made aura data *secret*: an addon cannot identify a buff by ID, by
name or by icon. The sanctioned replacement, `Blizzard_AuraContainer`, does not
arrive until **12.1** — on a 12.0 client, creating one fails outright.

So an addon on 12.0 can neither read an aura nor hand one to the engine.

Blizzard's Cooldown Manager already solved this. It knows every tracked
cooldown and buff, owns frames that display them with correct icons, swipes,
charges, stacks and timing, and does that inside the game where secret values
are not a problem. Every addon that "does cooldowns" on this patch works the
same way — it parses nothing and restyles Blizzard's item frames.

ZwoelfStuff reads the Cooldown Manager's live item frames
(`viewer.itemFramePool:EnumerateActive()`), resolves what each one is, and pins
them into bars of your own shape. The aura-tracking code written before this is
kept but parked until 12.1.

## Bars

`/zs` → **Cooldowns**. The window has three columns and each has one job:

| Column | What is in it |
| --- | --- |
| left | what the addon does — Cooldowns, Settings, Co-Tanks, Reminders, Profiles, Diagnostics, About, Changelog |
| middle | **every bar you own**, under each other, scrollable, with *Add new bar* at the bottom |
| right | **every cooldown** your Cooldown Manager knows — or the settings for one bar |

Each bar in the middle is a card that **is** the bar: same rows, same columns,
same order, nothing to translate. **Rows** and **Columns** sit right underneath
it as two sliders, so the shape changes under your hand. At the bottom of the
stack, **Icon bar** and **Tracking bar** add the next one.

- Click a cell, then click a spell on the right. The selection moves on to the
  next empty cell by itself, so filling a bar is click, click, click.
- Drag one cell onto another to swap them.
- Right click a cell to clear it.
- Manual spell IDs are accepted, bottom right.

The spell list is grouped into **Cooldowns, Utility, Buffs, Buff bars** and
**Auras**, with filter buttons above to jump to one of them. Spells already on
the bar you have selected are **green**, with the cell they sit in; spells your
current talent build does not have are **greyed out** and sorted to the end of
their group — still pickable, because a bar is often built for the build you
are about to switch into.

Blizzard's Cooldown Manager hides most of a spec by default, and until 4.42.0
those spells had a heading of their own called *Not shown by Blizzard*. That
described Blizzard's settings panel rather than the spell, and read as though
they were a different kind of thing. They are listed under **Cooldowns** with
everything else now, the ones you arranged first and the rest underneath, in
Blizzard's own order. The distinction that *is* true stays on the entry: a
spell the Cooldown Manager is not displaying has no frame for this addon to
adopt, and moving it into one of Blizzard's viewers is one drag.

Changing rows or columns **re-flows** what is already there rather than
scrambling it: 6×1 becomes 3×2 with the same spells in the same order.

### Arrangements

A bar does not have to be a plain row. Under **Options → Arrangement** there are
three shapes, and the card in the middle column previews whichever one you pick
— the editor asks the same engine the screen does, so what you see in the
window is what lands on screen.

| Arrangement | What it is |
| --- | --- |
| **Grid** | rows and columns |
| **Staggered** | every other line pushed along by half a cell |
| **Puzzle** | every cell exactly where you dragged it. No lattice at all |

*Arc* and *Diagonal* were removed in **4.8.0**. Both were lattices nobody
arranged a real bar with, and Puzzle does everything either of them did with
one less thing to explain — bars on either were moved onto Grid by a migration.

With them: **fill order** (rows first or columns first), **reading direction**
on both axes, and **which point the bar is pinned by**. That last one is what
people usually mean by grow direction — pinned by the centre a bar spreads both
ways when it gains a row, pinned by an edge it grows away from that edge.

**Puzzle is not a separate mode.** Every arrangement adds each cell's own
offset on top of whatever the lattice worked out, so nudging one icon out of a
neat row and building a free-form layout are the same edit.

### Per-cell overrides

Any single cell can carry its own **scale**, its own **offset**, its own
**kind** and its own **visibility**. One icon in a row at 150 %. A tracking bar
in among the icons. A slot hidden while you decide.

The overrides travel with the **spell**, not the position: drag a cell to
another slot and its settings come along, and re-flowing a grid carries them in
the same sequence the spells move in.

### Build mode

`/zs build`, the **Build** button on any bar card, or the switch in the unlock
toolbar. The bar's panel shrinks to a chip above it and every cell gets a
handle of its own:

- **drag** it — snapped to the bar's raster, hold **Alt** for free hand
- **scroll** over it to scale it
- **Tab** through the slots, **arrow keys** to nudge, **Delete** to empty
- **right click** for kind, hide and reset

The **spell palette** opens beside it. Click a slot, click a spell, and the
selection walks on to the next slot — filling a bar is one click each. Every
Cooldown Manager spell is in it, greyed when your build does not have it.

### Effects

All off until you ask for them. Under **Options → When it comes back** and
**Nag and warn**:

- a **flash** when a cooldown lands, with a pulse count and a colour
- an **edge** while the spell is up, optionally only in combat
- a **nag** — a spell ready for *n* seconds *in combat* starts pulsing, for the
  defensive you keep forgetting
- a **last-seconds warning** on the auras this addon clocks itself
- a **glow** while a tracked aura is up, and **greying out** while a cooldown
  runs

What drives them is Blizzard's own answer to "is this on a *real* cooldown",
global cooldown excluded — without that exclusion every spell in the game comes
off cooldown every 1.5 s and the flash is a strobe.

### When a bar is on screen

**Options → When to show it** turns a bar into a conditional one: combat, group
size, target, rested area, and six kinds of place — world, dungeon, raid,
scenario or delve, battleground, arena.

Every rule has to agree, and every one of them starts on *any*, so a rule you
have not set can never be the reason something is missing. Out of condition a
bar is gone — or dimmed to whatever you choose, which is what you want while
you are still arranging it. The section tells you which rule is currently
keeping it off screen.

### Per-bar settings

**Options** on a bar's header turns the right column into that bar's settings —
name, icons or bars, sizes, spacing, scale, opacity, border and border colour.
**Done** brings the spells back.

A look does not have to be set twice. **Copy from** takes it from another bar
in one click, and **Save as** stores it as a named preset you can apply to any
bar later. Only sizes, spacing and colours travel; the spells and the grid stay
with their own bar, because those are what make it that bar.

`/zs cdm` prints what the Cooldown Manager currently holds, per viewer — the
same data the spell list draws from.

## Reminders

`/zs` → **Reminders**, or `/zs reminders` to print every one and why it is or
is not on screen right now.

A reminder is a line of text that appears when something is wrong. You write
the sentence, drag a spell onto it, and say whether it fires while the buff is
**missing** or while it is **up**. Size, colour, flashing and an icon beside it,
plus the same visibility rules the bars have — combat, group size, target,
rested, and the kind of place you are in.

Nothing is seeded. A reminder that arrives pre-written with an update is a
message shouting on your screen that you did not ask for, about a spell your
build may not even have.

## Profiles and sharing

`/zs` → **Profiles**.

A set of settings has a name of its own, and your character points at one. It
starts out pointing at a profile named after itself — which is exactly how this
worked before profiles had names, so nothing moves when you update. Point a
second character at the same one and they really *are* the same settings rather
than two copies drifting apart.

You can make a new empty profile, copy the one you are using, rename it (every
character using it follows), or delete it. The last remaining profile cannot be
deleted, because something has to be in use.

**Sharing is by string.** What you built becomes a piece of text you can paste
anywhere, and whoever gets it pastes it back in:

```text
!ZS1_<compressed, printable>
```

`LibSerialize` packs the table, `LibDeflate` compresses it and makes it
printable. The format version sits in the **prefix**, so a string from a newer
build is refused *before* a byte of it is decoded — the alternative is
decompressing something built by rules this copy does not have and calling it
corrupt.

You choose what travels — bars, reminders, the co-tank panel, saved looks,
settings — each with its own tick, and **one row per bar** underneath, so "here
is my Bone Shield bar" is a single string rather than a whole profile somebody
has to unpick.

The string records the class and specialisation it was made on and says so
before anything is written. Your class, and the spells come with it; another,
and the layout arrives with the cells empty, because a Death Knight's cooldowns
are not castable on a Paladin. **The character's name is not in it** — a string
is made to be pasted somewhere public.

**Nothing you already have is thrown away.** Bars and reminders from a string
are *added* to yours, never swapped for them: there is no undo in this addon,
and a string somebody handed you must not be able to delete an evening's work.
A saved look whose name is already taken keeps both. The co-tank panel and the
settings are single things, so those do get replaced.

## Co-tank panel

`/zs tanks` toggles it, `/zs tanks unlock` moves it, `/zs tanks test` fakes a
raid so it can be arranged solo, and the **Co-Tanks** page has the rest.

One row per tank, the player first so rows never reorder mid-pull — health,
absorbs, heal absorbs, target ring, raid marker and indicators.

**The aura strips need patch 12.1 for live data.** A co-tank's boss debuff
stacks are secret exactly like your own buffs, so no addon may read them. Each
row owns two `AuraContainer`s — one `HARMFUL`, one `HELPFUL` — and the engine
binds, shows and times them; the addon supplies only the widgets and the unit
token. Until 12.1 the strips draw in **test mode**, so every setting is
adjustable today and correct the moment the patch lands. The panel says so
rather than showing an empty strip.

Debuffs run along the top of a row and buffs along the bottom, both left to
right. They used to sit at opposite ends of the same edge growing towards each
other, which sounds like it keeps them apart and does not: eight icons at 22
with a point between them is 183 of a 240-wide row, so from the fifth icon on
they drew in the same place.

Health is polled at 10 Hz rather than event-driven: there are at most a handful
of rows, and it avoids re-registering unit events on every roster change. The
health bar is fed raw values (a `StatusBar` accepts secret numbers), while the
percent text only appears when the numbers are actually computable.

Container rewiring is refused in combat, so roster changes are queued and
replayed on `PLAYER_REGEN_ENABLED`.

## Why this exists

The Cooldown Manager only offers spells contained in its own
`C_CooldownViewer` data set. Spell 1265968 is not in that set, so it cannot be
added by hand — and no Cooldown Manager addon can add it either, because their
spell pickers enumerate the exact same list. (Checked against
`EllesmereUICooldownManager`, whose `AddSpellToBar` sources its candidates from
`EnumerateCDMViewerSpells`.)

ZwoelfStuff sidesteps this: it queries the aura straight off the player by spell ID
and draws it on its own frame. Anything in your buff bar can be isolated this
way, regardless of who cast it.

## Secret values (patch 12.0+) — the constraint that shapes this addon

Since patch 12.0 aura data arrives as **secret values**. Tainted code — which
every addon is — may not use them as table keys, compare them, do arithmetic on
them, or take their length. It may only store them, pass them on, and hand them
to the few widget setters that accept secret arguments.

That rules out the obvious implementation. Scanning the aura list and comparing
`aura.spellId` against a set of tracked IDs raises
`attempted to index a table that cannot be indexed with secret keys`. Version
1.0.0 did exactly that and threw on every aura change.

The rules this addon follows instead:

| Need | Forbidden approach | What is used |
| --- | --- | --- |
| Is the aura up? | scan auras, compare `spellId` | three routes, see below |
| Cooldown swipe | `SetCooldown(expiration - duration, duration)` | `C_UnitAuras.GetAuraDuration` → `Cooldown:SetCooldownFromDurationObject` |
| Remaining time | `expirationTime - GetTime()` | the cooldown frame's engine-drawn countdown |
| Stack count | `if applications > 1` | `C_UnitAuras.GetAuraApplicationDisplayCount(unit, id, 2, 999)` |
| Icon and name | `aura.icon`, `aura.name` | `C_Spell.GetSpellTexture/GetSpellName` on *our* ID |

### Can the buff be displayed at all? — the measurement

`/zs dump`, run in combat with the buff up, reported **0 readable, 18 secret**.
Every buff on the player was secret, not just this one. The cooldown viewers did
hand out plain spell IDs and readable `auraInstanceID`s — but only for the buffs
the Cooldown Manager tracks, and Boiling Point is not among them.

So: **the buff itself cannot be read by an addon.** That is by design, not a bug
to route around. What *can* be read is the **proc**: Boiling Point empowers Blood
Boil, and `C_SpellActivationOverlay.IsSpellOverlayed(50842)` is a plain boolean
that never touches aura data. ZwoelfStuff displays that, and times the 15 seconds
itself.

The same technique is used by `EllesmereUIAuraBuffReminders` for beacons it
cannot read either — its own comment calls it "IsSpellOverlayed-based,
combat-safe, independent from the main aura/buff system".

**Limitation, stated plainly:** several procs can light up the same button. The
glow is the signal, not the aura, so a different proc glowing Blood Boil looks
identical. `/zs glowlog` prints every glow event with its spell ID, so a more
specific source can be chosen if one exists.

### The five lookup routes

Each exists because it fails for a different class of aura:

1. `C_UnitAuras.GetPlayerAuraBySpellID(id)` — the spell ID goes *into* the
   query, so nothing secret is compared.
2. `C_UnitAuras.GetAuraDataBySpellName(unit, name, filter)` — covers auras
   whose applied ID differs from the tooltip or talent ID.
3. **Blizzard's cooldown viewer buff frames** (`BuffIconCooldownViewer`,
   `BuffBarCooldownViewer`). Secret *rotational procs* — Boiling Point among
   them — are invisible to routes 1 and 2 no matter how correct the ID is. The
   viewer still binds them, and its item frames carry a plain `auraInstanceID`
   and `auraDataUnit`, which is enough for presence, duration and stacks.
   Matching runs through `C_CooldownViewer.GetCooldownViewerCooldownInfo`
   against `spellID`, `overrideSpellID`, `linkedSpellIDs` and the spell name.
4. **Icon match** over the aura list — only works while icons stay readable.
5. **Proc glow** — `C_SpellActivationOverlay.IsSpellOverlayed(glowSpellID)`.
   The only route that survives when every aura is secret. Timing comes from our
   own clock plus `glowDuration`, both plain numbers we own.

Route 3 is the ironic one: the Cooldown Manager will not let you *add* this
buff, yet it knows perfectly well when it is up.

Because a secret proc gives no readable event, and because the viewer binds its
frame a moment after the aura lands, the watcher polls at 10 Hz. The display
re-renders only when the shown aura actually changes, so polling never restarts
the swipe.

Since 12.0.1, `SetCooldownFromDurationObject` is the **only** way to configure a
cooldown frame with secret timing — `SetCooldown`, `SetCooldownDuration`,
`SetCooldownFromExpirationTime` and `SetCooldownUNIX` all reject secrets from
tainted code.

`Core/Secrets.lua` holds the guards (`ns.CanCompute`, `ns.SameValue`); every
engine query is `pcall`-wrapped, because a secret-flagged spell can make the
query itself raise.

### Consequences you can see

- The remaining-time number is drawn by the game, so it obeys the global
  setting. If no number appears: `/console countdownForCooldowns 1`.
- Bar mode animates its fill only for auras whose timing is readable. For a
  secret aura the bar stays full and the countdown carries the timing.
- The proc glow fires when the aura appears or when the aura instance
  demonstrably changes. A refresh that keeps the same instance cannot be
  detected without reading secret timing, so it does not re-trigger the glow.

## Install

The repo is linked into the WoW AddOns folder:

```text
C:\Games\World of Warcraft\_retail_\Interface\AddOns\ZwoelfStuff
    -> C:\Users\Christian\Documents\GitHub\ZwoelfStuff
```

Edit here, `/reload` in game. After adding a **new file** to the TOC, restart the
client fully rather than relying on `/reload`.

## Usage

`/zs` opens the window. `/zs unlock` puts the bars where you want them.

| Command | Effect |
| --- | --- |
| `/zs` | open the window |
| `/zs unlock` / `lock` | move the bars around the screen |
| `/zs build` | take a bar apart slot by slot, on screen |
| `/zs bars` | list your bars (`add <name>` / `remove <n>`) |
| `/zs cdm` | what Blizzard's Cooldown Manager currently holds |
| `/zs skin` | what is actually drawn on one adopted icon |
| `/zs auras` | the procs seen on this spec, and what drives each one |
| `/zs report` | the proc report, in a box you can copy from |
| `/zs auras export` | the same thing, under its older name |
| `/zs auras icon <glowID> <spellID>` | which icon a proc shows |
| `/zs auras bind <glowID> <auraID>` | name the buff itself (12.1 route) |
| `/zs auras forget <glowID>` | drop one, shipped entries included |
| `/zs auras remember` | put every forgotten one back |
| `/zs tanks` | the co-tank panel (`unlock` moves it, `test` fakes a raid) |
| `/zs reminders` | every reminder, and why each one is or is not up |
| `/zs test` | run the addon's own checks and report failures |
| `/zs minimap` | show or hide the minimap button |
| `/zs reset` | reset the profile you are using, keeping recorded procs |

`/zs reset` touches **only the profile in use**. Until 4.42.0 it wiped the
whole saved-variables file — every character — and it detached the account
table on the way, so the recorded procs it promised to keep were written into
an orphan and were gone at the next login.

### Unlock mode

Two modes, and the difference is the level you work at: **Move bars** treats a
whole bar as one object, **Build** treats every cell as one. The toolbar
switches between them.

Every bar gets a panel with its live coordinates. Drag it, or select it and
nudge with the arrow keys — Shift for 10. It snaps to the screen centre and to
the other bars' centres and edges, with a guide line showing what it caught;
hold **Alt** while dragging to switch snapping off. The cog opens that bar's
menu. **Shift + Right Click** hides the overlay so you can see what is
underneath, and Escape leaves.

**Bars can be attached to each other.** Snapping puts a bar next to another
one once; attaching keeps it there — move the one it hangs on and it comes
along, resize it and the other stays flush. The cog offers it, and afterwards
the same menu switches which side. Dragging an attached bar adjusts its
offset rather than a screen position it no longer owns.

### It takes Blizzard's display over

Every icon on your bars *is* one of Blizzard's Cooldown Manager frames, moved
onto your cell — it owns the timing, the charges and the stacks, and on this
patch no addon may read those for itself. Blizzard lays its own row out
without knowing an icon left, so it would show a hole where that one used to
be. Because of that, cooldowns you have not placed are hidden as well.

Settings → *Take the display over* switches that off and gives Blizzard's row
back, holes included.

### The proc database

`Core/KnownProcs.lua` ships with the addon, keyed by class and spec:

```lua
["DEATHKNIGHT:250"] = {
    [50842] = { display = 1265968, auraID = 1265968, duration = 15 },
},
```

A glow set belongs to a class and a spec, not to a player, so one person
playing one spec once is enough for everybody who plays it. Nothing in that
file is written from memory: play the spec, let each proc run out on its own
at least once so the duration is measured rather than guessed, then
`/zs auras export` and paste the block in.

## Architecture

28 files load, in this order. The list below is the whole of it.

| File | Responsibility |
| --- | --- |
| `Core/Init.lua` | namespace, defaults, helpers, slash commands |
| `Core/Share.lua` | a layout to a pasteable string and back — pure, no database, no frames |
| `Core/Profiles.lua` | which settings a character uses; the migration that moves them |
| `Core/Media.lua` / `MediaLibrary.lua` | the shipped textures, registered into LibSharedMedia |
| `Core/Secrets.lua` | secret-value guards |
| `Core/CDM.lua` | Blizzard's Cooldown Manager: find the viewers, adopt their item frames, hold them |
| `Core/KnownProcs.lua` | the shipped proc database, by class and spec |
| `Core/Auras.lua` | records procs while you play, measures their duration, exports them |
| `Core/Layout.lua` | pure geometry — where every cell of a bar ends up |
| `Core/Visibility.lua` | the rules that decide when a bar is on screen |
| `Core/Effects.lua` | flash, edge, nag, warning — what a cell does beyond sitting there |
| `Core/Bars.lua` | the data model: cells, arrangement, per-cell overrides |
| `Core/Engine.lua` | the `AuraContainer` layer, probed for by building one and seeing |
| `Core/CoTanks.lua` | the co-tank panel |
| `Core/Reminders.lua` | text on screen when a buff is missing or up |
| `Core/Minimap.lua` | minimap button |
| `Core/GameMenu.lua` | the entry under Blizzard's own pause menu |
| `Core/Widgets.lua` | the design system: every control is built here |
| `Core/Screen.lua` | the bars on screen — adopted frames and drawn aura cells |
| `Core/EditMode.lua` | unlock **and** build mode: movers, cell handles, the spell palette, snapping |
| `Core/Changelog.lua` | what changed, written for the person playing |
| `Core/OptionsBars.lua` | the middle and right columns of the window |
| `Core/OptionsCoTanks.lua` / `OptionsReminders.lua` / `OptionsProfiles.lua` | the pages that carry a third column |
| `Core/Options.lua` | the window shell and the secondary pages |
| `Core/SelfTest.lua` | `/zs test` — 694 checks on the model and the rules |

**Deleted:** `Core/Display.lua` and `Core/Watcher.lua` in 4.4.0 (the old
single-aura window, superseded by `Core/Screen.lua`), and `Core/Glow.lua` in
4.9.0 (the expanding proc ring — it went with the arrangements nobody used).

**Parked** — on disk, out of the TOC *and* out of `.pkgmeta`, so they neither
load nor ship: `Catalog`, `Probe`, `Groups`, `OptionsGroups` (they need
`Blizzard_AuraContainer`, which does not exist on a 12.0 client), and `Routes`
/ `OptionsRoutes` — the MDT pull badges, which are not coming back on 12.0 for
reasons measured rather than assumed: in a dungeon the client withholds a mob's
name, GUID, health and criteria progress; `UnitPosition` returns nothing for
the player; and asking a nameplate for its centre raises.

> Parking a file means **both** lists. The packager copies the repository and
> reads `.pkgmeta`; it does **not** read the TOC. Version 4.41.0 shipped six
> files it never loads because only the TOC had been edited.

### Further implementation notes

- **No hardcoded spell names.** Names are resolved from the client at runtime.
  The spell ID is the only fixed fact.
- **No texture-path guessing.** Borders, bar fill and glow are built from colour
  textures and `Interface\Buttons\WHITE8X8`; fonts are read off a live font
  object. Nothing breaks when Blizzard reshuffles art paths.
- **Steppers instead of sliders.** Slider templates have been renamed several
  times across expansions; `-`/`+` steppers hit exact values and cannot break.
- **No protected frames**, so combat lockdown is never an issue.
- The `UNIT_AURA` payload is deliberately ignored. Reading it would mean
  touching secret fields; re-querying a handful of IDs is legal and cheap.

## Verification

In the game, `/zs test` runs the addon's own checks — 694 of them, on the model
and the rules. It says nothing about how anything *looks*; that is still a pair
of eyes on a screen.

Static analysis via the Lua language server. **Do not write the version into
the path** — the extension updates itself, and a pinned path stops working
without saying why:

```powershell
$ls = (Get-ChildItem "$env:USERPROFILE\.vscode\extensions\sumneko.lua-*\server\bin\lua-language-server.exe" |
       Sort-Object FullName | Select-Object -Last 1).FullName
& $ls --check "$PSScriptRoot" --checklevel=Warning --logpath="$env:TEMP\llscheck"
```

## Embedded libraries

| Library | Licence | Why |
| --- | --- | --- |
| LibStub | Public domain | Loader the others need |
| CallbackHandler-1.0 | BSD | LibSharedMedia dependency |
| LibSharedMedia-3.0 | LGPL v2.1 | Fonts, bar textures, border textures |
| LibSerialize | MIT | Turns a profile into bytes for a share string |
| LibDeflate | zlib | Compresses those bytes and makes them printable |

The rest of this addon is built from scratch on purpose — the window, the
widgets, the look. These five are the exceptions, and none of them is there to
save effort.

**LibSharedMedia is a registry, not a design.** Every UI addon on a machine
registers what it ships into it, so asking it for the list shows you the media
you already have, under the names you already know. Shipping our own instead
would give you a second, smaller, unfamiliar set with the one you wanted
missing.

**LibSerialize and LibDeflate are the pair every addon that shares a string
uses** — WeakAuras, Plater, MDT and EllesmereUI all reach for exactly these
two. A hand-written serializer is a worse copy of a solved problem, and the one
place it would show is somebody else's string failing to open with no way to
tell whose fault it was.

> A note on LibDeflate's licence, because getting it wrong is easy: the
> `LICENSE.txt` sitting beside it in one of the addons on this machine is the
> **LGPL**, which is *not* its licence — `LibDeflate.lua` says **zlib** in its
> own header. Copying the file that happens to sit next to a library is how a
> project ends up claiming the wrong terms.

Their licences stay with them; our own code is MIT.

## Credits

Addon Author: **Zwölf** — EU Destromath

License: MIT
