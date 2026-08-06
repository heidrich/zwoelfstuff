# ZwoelfStuff

A cooldown manager for a Death Knight, built on the one thing that actually
works on this patch: **Blizzard's own Cooldown Manager does the hard part, and
this addon arranges it.**

1. **Bars** — your own bars, as many as you like. A bar is a grid of cells; you
   set the rows and columns and put a spell in each cell.
2. **Isolated aura display** — a single buff in its own movable frame, for auras
   the Cooldown Manager does not carry. Ships tracking **spell 1265968**
   (Boiling Point).

> **Status:** the bar editor works; bars do not render on screen yet. See
> `HANDOFF.md`.

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
| left | what the addon does — Cooldowns, Aura Display, Settings, Diagnostics, About, Changelog |
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

The spell list is grouped into **Cooldowns, Utility, Buffs and Buff bars**,
with filter buttons above to jump to one of them. Spells already on the bar
you have selected are **green**, with the cell they sit in; spells your
current talent build does not have are **greyed out** and sorted to the end of
their group — still pickable, because a bar is often built for the build you
are about to switch into.

Changing rows or columns **re-flows** what is already there rather than
scrambling it: 6×1 becomes 3×2 with the same spells in the same order.

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

## Co-tank panel (parked until 12.1)

`/zs tanks` toggles it, `/zs tanks unlock` moves it, and the **Co-Tanks**
options tab has the rest.

One row per tank, the player first so rows never reorder mid-pull. The auras are
the interesting part: a co-tank's boss debuff stacks are secret exactly like your
own buffs, so no addon can read them. Each row therefore owns two
`AuraContainer`s — one `HARMFUL`, one `HELPFUL` — and the engine binds, shows and
times them. The addon only supplies the widgets and the unit token.

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
| `/zs bars` | list your bars (`add <name>` / `remove <n>`) |
| `/zs cdm` | what Blizzard's Cooldown Manager currently holds |
| `/zs auras` | the procs seen on this spec, and what drives each one |
| `/zs auras export` | print this spec's set, ready to paste into the database |
| `/zs auras icon <glowID> <spellID>` | which icon a proc shows |
| `/zs auras bind <glowID> <auraID>` | name the buff itself (12.1 route) |
| `/zs auras forget <glowID>` | drop one, shipped entries included |
| `/zs auras remember` | put every forgotten one back |
| `/zs minimap` | show or hide the minimap button |
| `/zs reset` | restore defaults, keeping recorded procs |

### Unlock mode

Every bar gets a panel with its live coordinates. Drag it, or select it and
nudge with the arrow keys — Shift for 10. It snaps to the screen centre and to
the other bars' centres and edges, with a guide line showing what it caught;
hold **Alt** while dragging to switch snapping off. The cog opens that bar's
menu. **Shift + Right Click** hides the overlay so you can see what is
underneath, and Escape leaves.

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

| File | Responsibility |
| --- | --- |
| `Core/Init.lua` | namespace, defaults, saved variables, helpers, slash commands |
| `Core/Secrets.lua` | secret-value guards |
| `Core/CDM.lua` | Blizzard's Cooldown Manager: find the viewers, adopt their item frames, hold them |
| `Core/KnownProcs.lua` | the shipped proc database, by class and spec |
| `Core/Auras.lua` | records procs while you play, measures their duration, exports them |
| `Core/Bars.lua` | the data model: a bar is a grid of cells |
| `Core/Glow.lua` | proc glow — expanding ring plus flash, no external library |
| `Core/Widgets.lua` | the design system: every control is built here |
| `Core/Screen.lua` | the bars on screen — adopted frames and drawn aura cells |
| `Core/EditMode.lua` | unlock mode: movers, snapping, guides, the cog menu |
| `Core/Minimap.lua` | minimap button |
| `Core/OptionsBars.lua` | the middle and right columns of the window |
| `Core/Options.lua` | the window shell and the secondary pages |

Deleted in 4.4.0: `Core/Display.lua` and `Core/Watcher.lua`, the old
single-aura window, superseded by `Core/Screen.lua`. Parked until patch 12.1:
`Engine`, `Catalog`, `Probe`, `Groups`, `CoTanks`, `OptionsGroups` — they need
`Blizzard_AuraContainer`, which does not exist on a 12.0 client.

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

Static analysis via the Lua language server:

```powershell
& "$env:USERPROFILE\.vscode\extensions\sumneko.lua-3.18.2-win32-x64\server\bin\lua-language-server.exe" `
    --check "C:\Users\Christian\Documents\GitHub\ZwoelfStuff" --checklevel=Warning --logpath="$env:TEMP\llscheck"
```

## Credits

Addon Author: **Zwölf** — EU Destromath

License: MIT
