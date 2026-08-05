# DKstuff

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

DKstuff reads the Cooldown Manager's live item frames
(`viewer.itemFramePool:EnumerateActive()`), resolves what each one is, and pins
them into bars of your own shape. The aura-tracking code written before this is
kept but parked until 12.1.

## Bars

`/dks` → **Bars**.

Pick a bar from the dropdown — which is also where you create and delete them —
set rows and columns, and the grid below changes with them. **That grid is the
bar**: same rows, same columns, same order, nothing to translate.

- Click an empty cell to choose a spell. The list is your own Cooldown Manager,
  so anything in it is guaranteed to have working timing. Manual spell IDs are
  accepted too.
- Drag one cell onto another to swap them.
- Right click a cell to clear it.

Changing rows or columns **re-flows** what is already there rather than
scrambling it: 6×1 becomes 3×2 with the same spells in the same order.

`/dks cdm` prints what the Cooldown Manager currently holds, per viewer — the
same data the picker draws from.

## Co-tank panel (parked until 12.1)

`/dks tanks` toggles it, `/dks tanks unlock` moves it, and the **Co-Tanks**
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

DKstuff sidesteps this: it queries the aura straight off the player by spell ID
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

`/dks dump`, run in combat with the buff up, reported **0 readable, 18 secret**.
Every buff on the player was secret, not just this one. The cooldown viewers did
hand out plain spell IDs and readable `auraInstanceID`s — but only for the buffs
the Cooldown Manager tracks, and Boiling Point is not among them.

So: **the buff itself cannot be read by an addon.** That is by design, not a bug
to route around. What *can* be read is the **proc**: Boiling Point empowers Blood
Boil, and `C_SpellActivationOverlay.IsSpellOverlayed(50842)` is a plain boolean
that never touches aura data. DKstuff displays that, and times the 15 seconds
itself.

The same technique is used by `EllesmereUIAuraBuffReminders` for beacons it
cannot read either — its own comment calls it "IsSpellOverlayed-based,
combat-safe, independent from the main aura/buff system".

**Limitation, stated plainly:** several procs can light up the same button. The
glow is the signal, not the aura, so a different proc glowing Blood Boil looks
identical. `/dks glowlog` prints every glow event with its spell ID, so a more
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
C:\Games\World of Warcraft\_retail_\Interface\AddOns\DKstuff
    -> C:\Users\Christian\Documents\GitHub\DKstuff
```

Edit here, `/reload` in game. After adding a **new file** to the TOC, restart the
client fully rather than relying on `/reload`.

## Usage

`/dks` opens the settings window (Options / About / Changelog).

| Command | Effect |
| --- | --- |
| `/dks` | open the settings window |
| `/dks unlock` / `lock` | drag the display into place |
| `/dks test` | 15 second preview, for positioning |
| `/dks icon` / `bar` | switch display mode |
| `/dks size <n>` | icon size |
| `/dks width <n>` / `height <n>` | bar size |
| `/dks scale <n>` | overall scale |
| `/dks add <spellID>` | track another aura |
| `/dks remove <spellID>` | stop tracking one |
| `/dks list` | list tracked auras |
| `/dks check <spellID>` | is that aura findable right now, and by which route |
| `/dks status` | what is tracked, what is active, current settings |
| `/dks dump` | full diagnosis — run it **while the buff is up** |
| `/dks glowlog` | log every proc glow, to find the right spell ID |
| `/dks glow <id or name>` | drive the display off that proc glow (`off` to disable) |
| `/dks glowduration <s>` | how long the proc lasts, default 15 |
| `/dks reset` | restore defaults |

### Wrong spell ID?

With the buff up, run `/dks check`. It reports `FOUND` or `not found` separately
for the ID route and the name route. If both miss, the ID is wrong — hover the
buff in your buff bar, **idTip** shows the real one, then:

```text
/dks add <realID>
/dks remove 1265968
```

### Display modes

- **Icon** — square icon, cooldown swipe, engine countdown, stack count.
- **Bar** — icon plus a status bar with spell name and countdown.

### Options

Always show (greyed out while the aura is down), remaining time, stacks, spell
name, proc glow, proc sound. The tracked spell list doubles as a priority list —
the first entry present on the player wins.

## Architecture

| File | Responsibility |
| --- | --- |
| `Core/Init.lua` | namespace, defaults, saved variables, helpers, slash commands |
| `Core/Secrets.lua` | secret-value guards |
| `Core/Glow.lua` | proc glow — expanding ring plus flash, no external library |
| `Core/Display.lua` | both display modes, layout, preview, inactive and test rendering |
| `Core/Watcher.lua` | aura lookup by ID with name fallback, diagnostics |
| `Core/Options.lua` | tabbed settings window |

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
    --check "C:\Users\Christian\Documents\GitHub\DKstuff" --checklevel=Warning --logpath="$env:TEMP\llscheck"
```

## Credits

Addon Author: **Zwölf** — EU Destromath

License: MIT
