# Changelog

All notable changes to DKstuff are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.0.0] - 2026-08-06

A different approach, because the previous one could not work on this client.

### Why

Everything up to 3.x tried to track auras itself. On patch **12.0** that is a
dead end from both directions:

| | 12.0.7 |
| --- | --- |
| Read an aura | blocked — aura fields are secret values |
| Hand one to the engine | impossible — `AuraContainer` arrives in **12.1** |

Measured on the live client: `CreateFrame("AuraContainer", …)` fails, and
EllesmereUI gates every one of its own AuraContainer files behind
`select(4, GetBuildInfo()) >= 120100`. So the proc-glow route was never a
workaround for a broken lookup — it was the only thing possible.

Blizzard's **Cooldown Manager** already solved this. It knows every tracked
cooldown and buff, owns frames that display them with correct icons, swipes,
charges, stacks and timing, and does it inside the game where secret values
are not a problem. Every addon that "does cooldowns" on this patch works the
same way — it parses nothing and restyles Blizzard's item frames. EllesmereUI
says so in one line at the top of its own CDM file: *"Does NOT parse secret
values, works around restricted APIs."*

### Added

- **`Core/CDM.lua`** — the Cooldown Manager layer: finds the four viewers,
  enumerates their live item frames, resolves what each one is, and pins them
  where we want against Blizzard's own re-anchoring.

  Two details taken from the reference rather than invented: the **frame pool
  is the ground truth** for what is displayed (the static category API says
  where a cooldown *belongs*, but Edit Mode and per-spec layouts move it), and
  Blizzard re-anchors constantly, so position and size are held by hooking
  `SetPoint` and `SetSize` and re-asserting.
- **`Core/Bars.lua`** — a bar is a grid of cells, each holding one spell.
  Cells are stored in reading order, so changing the column count re-wraps
  what is there instead of scrambling it, and shrinking a grid compacts rather
  than silently dropping the cells that no longer exist.
- **The bar editor** — pick the bar, set rows and columns, see the grid, fill
  it. The grid on the options page *is* the bar: same rows, same columns, same
  order, nothing to translate. Click an empty cell to choose a spell, drag one
  cell onto another to swap, right click to clear.
- **Spell picker** sourced from the Cooldown Manager, so anything in the list
  is guaranteed to have working timing. Manual IDs still accepted.
- `/dks cdm` — what the Cooldown Manager currently holds, per viewer.
- `/dks bars` — list, add, remove.

### Parked until 12.1

`Engine`, `Catalog`, `Probe`, `Groups`, `CoTanks` and `OptionsGroups` are out
of the TOC. They are inert on a 12.0 client, not wrong — the reason is written
next to them in the TOC. The proc-glow display for Boiling Point stays, since
that buff is not in the Cooldown Manager data set and this is the only way to
see it.

### Not yet

Bars render nothing on screen. The editor comes first, and is signed off
first — building on unverified foundations cost this project two full rounds
already.

## [3.4.0] - 2026-08-05

### Fixed

- **The aura engine reported itself unavailable on every client.** Every
  engine-backed feature was therefore dead: the display's aura slot, the
  co-tank aura strips, and every tracking group. The only thing that ever
  worked was the proc-glow route — which is why a group with several spells
  showed exactly one icon, and that icon was the classic display, not the
  group.

  The availability check began with
  `C_AddOns.LoadAddOn("Blizzard_AuraContainer")` and returned false when it
  failed. **There is no such addon.** `AuraContainer` and
  `CustomAuraContainerTemplate` are built into the client; every reference
  implementation on this machine simply calls `CreateFrame` — EllesmereUI
  gates on the build number, NorthernSkyRaidTools pcalls the creation. The
  gate could never open, on any client, ever.

  The check now builds a container, verifies `AddAuraGroup`, `AddAuraSlot`
  and `SetUnit` exist on it, and caches that. When it says no it now says
  *why*, instead of a bare "not available" that reads like a client problem.

### Added

- **`/dks group status`** — per spell, one of three answers: *slot refused*
  (a bug here, printed with the engine's error), *registered but never seen*
  (the slot is fine, the ID is wrong or the aura has not been up), or
  *bound*. This is what turns "only one icon shows" into something
  actionable in one command.
- Slots the engine refuses now report it in chat instead of disappearing into
  a `pcall`, and they keep their position in the order rather than silently
  closing the gap — a shorter row otherwise looks like a layout setting.

## [3.3.0] - 2026-08-05

### Added

- **`/dks probe <spellID> [seconds]`** — the decisive test for "can this be
  tracked at all". A hidden one-slot container is bound to the candidate ID,
  and the engine shows its button exactly while that aura sits on the unit.
  Every bind and unbind is printed with a timestamp.

  That timing is the point: it is what tells a **cast spell** apart from the
  **aura it applies**. If the slot lights up the instant you press the button,
  the ID is the cast. If it lights up when you walk into the area and goes out
  when you leave, it is the aura. Guessing between the two has cost this
  project two rounds on Boiling Point and another on Death and Decay.

  Nothing is read from the aura, and nothing is read from the button either:
  `OnShow` and `OnHide` are registered *inside* `initializeFrame`, the one
  window in which touching an engine button is legal, and the engine does the
  telling. Both polarities are bound, so a debuff answers the same way a buff
  does.

  Also on the Diagnostics page: type an ID, press Enter.

## [3.2.0] - 2026-08-05

### Fixed

- **Nothing could be dragged into place.** Every `AuraContainer` sits over the
  proxy frame the addon moves, and engine containers come mouse-enabled — only
  the *buttons* had been told otherwise. The containers swallowed every click
  meant for the anchor, so unlocking a group, the display or the co-tank panel
  appeared to do nothing at all. Containers are display surfaces and are now
  mouse-dead on creation.
- **An unlocked group with no active auras was an invisible rectangle.** There
  was a one-pixel outline and nothing else to aim at. Unlocked groups now show
  a tinted drag surface, and stay visible even while switched off, so they can
  be positioned before they ever light up.

### Changed

- **The spell list is a strip of icons.** Click `+` to add, drag an icon to
  move it, right click to remove it. The strip is the preview: what you see is
  the order the group renders in. This replaces a list of text rows with
  up/down/remove buttons, which showed the order without ever showing the
  *shape*.
- **The group picker creates and deletes groups itself.** One menu: pick a
  group, or use "+ New icon group" / "+ New bar group" at the bottom, with a
  delete on each entry. Replaces a prev/next/rename/new/delete button bar.
- The spell browser opens with the cursor already in its search box.

## [3.1.0] - 2026-08-05

The settings window was a flat list of steppers and checkboxes. It is now a
panel.

### Added

- **A design system** (`Core/Widgets.lua`): one set of colours, one row
  geometry, one set of controls, used by every page. Pages declare what they
  contain; the design system decides how it looks.
- **New controls**, all self-built and all matching each other: on/off
  switches, sliders with a numeric readout and mouse-wheel support, dropdown
  menus, colour swatches wired to the game's colour picker.
- **Sidebar navigation** — Tracking Groups, Aura Display, Co-Tank Panel,
  General, Diagnostics, About, Changelog — with a titled content area and a
  persistent footer.
- **Diagnostics page**: check, dump, scan and catalogue as buttons, plus
  whether `Blizzard_AuraContainer` exists on this client.
- **General page**: minimap button toggles, and a two-step reset-everything.

### Changed

- Pages are built on first view rather than at login, so the window costs only
  what you actually open. The Groups page alone is several dozen rows plus a
  spell browser.
- Rows that do not apply to the current settings are dropped from the layout
  rather than merely hidden, so the rows below close up instead of leaving a
  gap. Bar sizes vanish in icon mode; auto-sorting vanishes in fixed mode;
  spell names vanish where the engine cannot tell us which aura is where.
- Changelog data moved to `Core/Changelog.lua` — it only grows, and it is data,
  not layout.

### Notes

No Blizzard slider, dropdown or checkbox template is used anywhere. Those have
been renamed repeatedly across expansions, and none of them can be styled to
match a custom panel. Everything is drawn from colour textures and font
strings, so nothing can break on a template rename.

## [3.0.1] - 2026-08-05

### Fixed

- **Tracking groups threw at login, and took the rest of the addon with them.**
  `ns.CreateBorder` returns a plain table of four textures, not a frame, so it
  never had `Hide` / `Show` / `SetShown` — the group anchor called `Hide()` on
  its outline and hit a nil. The three visibility methods now exist on the
  border helper, where they belonged all along.
- **One broken feature disabled every feature after it.** The login handler ran
  Display → Watcher → Groups → Co-Tanks → Minimap in one straight line, so the
  error above meant no co-tank panel and no minimap button either. That looks
  like "the whole addon is dead" and hides which part actually failed. Each
  feature now boots independently; a failure is reported by name and passed to
  the error handler, never swallowed, and the rest still starts.

### Changed

- In fixed mode the slot container is sized to its group anchor rather than
  left at 1x1. The engine never resizes a slots-only container, and a 1x1
  parent is one `SetClipsChildren` away from hiding every button in the group.
- The spell browser repopulates itself on a respec or spec switch, if it is
  open at the time.

## [3.0.0] - 2026-08-05

Tracking groups, a spell browser that reads the live client, and the fix for
why the engine slot never bound anything.

### The finding

The engine slot added in 2.0.0 was built on `AddAuraFilter` + `AddAuraFrame`.
Those functions **do not exist**. Grepping four working 12.1 implementations on
this machine turned up zero uses of either name; the real API is
`AddAuraGroup` / `AddAuraSlot` with an `initializeFrame` callback. Every engine
call was wrapped in `pcall`, so the failure was silent and the addon quietly
fell back to the proc-glow route — which is why route 5 looked like the only
thing that worked.

A second, independent bug in the same code: the container was given its unit
*before* its content. Unit assignment re-evaluates event registrations, and
those are gated on the container already having groups or slots, so
`UNIT_AURA` stayed unregistered and the container never updated. Content
first, unit last, then `UpdateAllAuras()`.

Both are documented as rules 1–5 at the top of `Core/Engine.lua`.

### Added

- **Tracking groups.** Any number of them, icons or bars, each with its own
  spells, unit, filter, position, size, colours and text settings.
- **Arrangement.** Grows rightwards or leftwards, rows downwards or upwards,
  fills by rows or by columns, wraps after any number for a grid. All of it
  applies live, in combat included — layout only touches frames the addon
  owns.
- **Two ordering modes.** *My order* gives every spell one fixed engine slot
  that never moves, so a missing aura leaves its place empty instead of
  letting the next one slide in; bars can show spell names, because the slot's
  spell ID is ours and therefore plain. *Auto* uses one engine group with
  engine sorting: compact, but positions move and no name can be shown — which
  aura sits in which button is exactly the secret the engine keeps.
- **Spell browser.** Reads the running client: the talents you have actually
  purchased (walked through `C_Traits` from the active loadout), every
  spellbook skill line — including the specs you are **not** playing, which
  come back with a non-zero `offSpecID` — and Blizzard's own Cooldown Manager
  data set. Nothing is hardcoded, so it follows every respec and every patch by
  itself. Search by name or ID; talented spells are marked and sorted first.
  Manual spell IDs still work.
- **Bars that actually drain.** `button:SetDurationBar(bar, opts)` hands a
  StatusBar to the engine, which drains it from the aura's own duration, GPU
  side. It works for auras no addon may read.
- `/dks groups`, `/dks group add|remove|list`, `/dks catalog`.
- `Core/Widgets.lua` — the option controls, shared between pages: steppers,
  segmented choices, colour swatches, scroll areas. Still no external library.

### Fixed

- **Co-tank size steppers changed nothing.** They fell through to the shared
  stepper's default apply action, which re-lays-out the classic display — the
  wrong frame entirely. The values were written to the saved variables and
  never reached the panel.
- Options rows that do not apply to the current group (bar sizes in icon mode,
  auto-sorting in fixed mode) are now skipped by the layout instead of merely
  hidden, so the rows below close up rather than leaving a gap.

### Also ported to the corrected API

Both older engine users were built on the same non-existent functions, so
neither had ever bound an aura in game:

- **Co-tank aura strips** are now one `AddAuraGroup` per strip with engine
  flow layout, instead of hand-created buttons the addon placed itself.
- **The display's engine slot** is now an `AddAuraSlot` anchored to its proxy,
  rebuilt only when the tracked spell list changes and deferred out of combat.

### Notes

- The classic single-aura display still runs off the proc glow, which remains
  the one route verified in game. Group 1 is seeded with the same spell, so
  both are visible at first — compare them and switch off whichever you do not
  want.
- Rebuilding a group only happens when something *baked into the widgets*
  changes (style, colours, fonts, spell list). Position, size, spacing, growth
  and wrapping are live, because the engine buttons are anchored to proxy
  frames the addon owns and moves.

## [2.1.0] - 2026-08-05

### Added

- **Minimap button.** Left click opens the settings, right click toggles the
  co-tank panel, drag moves it around the minimap edge (the angle is saved).
  Self-built, no LibDBIcon — the round shape comes from
  `Interface\CharacterFrame\TempPortraitAlphaMask`, verified in use by other
  addons on this client rather than guessed.
- Addon icon in the AddOn list and the addon compartment
  (`## IconTexture: 1380870`, the Boiling Point FileDataID read off the live
  client in `/dks dump`).
- `/dks minimap` plus two options checkboxes to show/hide and lock it.

## [2.0.0] - 2026-08-05

Two features, one foundation: `Blizzard_AuraContainer`. The engine may read the
secret auras an addon may not, so the addon stops trying and hands over widgets
instead.

### Added

- **Co-tank panel.** One row per tank in the group: health bar, name, health
  percent, every debuff on that tank and every buff they carry. Rows are
  ordered with the player first so nothing jumps around mid-pull.
  Auras on other players are secret exactly like your own — a co-tank's boss
  debuff stacks cannot be read by an addon at all — so each row owns two
  `AuraContainer`s (HARMFUL and HELPFUL) and the engine binds, shows and times
  them. `/dks tanks`, `/dks tanks unlock`, plus a **Co-Tanks** options tab.
- **Engine aura slot for the tracked buff.** `AddAuraFilter` with
  `candidateFilters.includeSpellIDs` binds the real Boiling Point aura — real
  icon, real duration, real stacks — instead of proxying it through the proc
  glow. `/dks source engine` / `/dks source glow` switches; the glow route
  remains and still drives the proc flash.
- `Core/Engine.lua` — the shared engine layer, with a cached availability probe
  and a combat-lock guard, so both features degrade instead of erroring.

### Fixed

- **The options window clipped its last section.** The proc glow row was added
  without raising the window height. The height is now derived from a written
  content budget, with a comment saying to recount it when adding a section.
- Five reserved aura rows left a large empty gap above the input; now three.
- The inactive greyed-out state dimmed the whole root frame, which would have
  dimmed the engine's aura button along with it — engine-bound children inherit
  effective alpha. Only the placeholder composite dims now.

### Notes

- Aura buttons are created by the addon and registered with `AddAuraFrame`, not
  created by the engine via `AddAuraGroup`/`initializeFrame`. Engine-created
  subtrees are locked afterwards (reads *and* writes); self-created ones stay
  movable, which keeps the live size and layout options working.
- Container rewiring is refused in combat, so roster changes are queued and
  replayed on `PLAYER_REGEN_ENABLED`.

## [1.4.0] - 2026-08-05

The measurement that settled it, and the workaround that follows from it.

### The finding

`/dks dump` run in combat with the buff up reported **0 readable, 18 secret**.
Not just Boiling Point — *every* buff on the player was secret. The four
cooldown viewers meanwhile handed out plain spell IDs and readable
`auraInstanceID`s (Death and Decay, Bone Shield, Blood Shield, Hemostasis,
Dancing Rune Weapon), but none of them was Boiling Point.

So the conclusion is not "our lookup is broken". It is: **the buff itself
cannot be read by any addon.** Aura identification is closed, and the one
sanctioned channel that stays open — the Cooldown Manager — does not carry
this spell. That is exactly the gap this addon exists to fill.

### Added

- **Route 5: proc glow.** Boiling Point empowers Blood Boil, and
  `C_SpellActivationOverlay.IsSpellOverlayed(50842)` is a plain boolean that
  never touches aura data. The display is driven off that, with timing from our
  own clock and our own duration constant — plain numbers we own, so the swipe
  and the countdown work normally.
  This is the same combat-safe technique `EllesmereUIAuraBuffReminders` uses for
  beacons it cannot read either ("Standalone Beacon Reminders —
  IsSpellOverlayed-based, combat-safe").
- `/dks glowlog` — logs every `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE` with
  spell ID and name, so the right ID is read off the client rather than guessed.
- `/dks glow <spellID or name>` — sets the proc source; a name is resolved via
  `C_Spell.GetSpellInfo`, so no ID is ever hardcoded. `/dks glow off` disables.
- `/dks glowduration <seconds>` — proc length, default 15.
- Proc glow section in the options window, with a live status readout.

### Changed

- Default `glowSpellID` is 50842 (Blood Boil), confirmed from the live client.
- `/dks dump` now also reports: combat state, which APIs actually exist, whether
  the target spell is in the Cooldown Manager data set at all
  (`GetCooldownViewerCategorySet` over all four categories), the current overlay
  state, and the override-spell state.

### Fixed

- **Diagnostics could not tell "API does not exist" from "aura not found".**
  Both printed `not found`. Every API is now reported explicitly.

### Known limitation

Several procs can light up the same button. If Blood Boil glows for another
reason, route 5 cannot tell them apart — the glow is the signal, not the aura.
`/dks glowlog` shows exactly which spell IDs fire, so a more specific source can
be chosen when one exists.

## [1.3.0] - 2026-08-05

Still not found in game — all three routes reported `not found`. This release
widens the search and, more importantly, adds the diagnosis that shows what
actually exists instead of testing one hypothesis at a time.

### Fixed

- The cooldown viewer route only searched `BuffIconCooldownViewer` and
  `BuffBarCooldownViewer`. It now searches all four viewers, adding
  `EssentialCooldownViewer` and `UtilityCooldownViewer` — a proc can be
  registered in those categories too.

### Added

- **Fourth route: icon match.** The icon of *our* spell ID is always plain, so
  comparing it against a readable aura icon is legal. Catches secret auras that
  keep a readable icon. Last in priority, because two buffs can share an icon.
- `/dks dump` — dumps every entry of all four cooldown viewers (spell ID, name,
  shown state, whether timing is available) and every player buff (readable ones
  with ID and name, secret ones counted with their aura instance), marking any
  icon match. Must be run **while the buff is up**.
- `/dks check` reports all four routes.

## [1.2.0] - 2026-08-05

Boiling Point was still never found. 1.1.0 stopped the errors but not the
silence — because a secret rotational proc is invisible to *both* aura reads.

### Fixed

- **The tracked aura was never detected.** `GetPlayerAuraBySpellID` and
  `GetAuraDataBySpellName` both return nothing for secret-flagged rotational
  procs, no matter how correct the spell ID is. Confirmed in game: `/dks check`
  reported `not found` on both routes while the buff was up.

### Added

- **Third lookup route: Blizzard's cooldown viewer buff frames**
  (`BuffIconCooldownViewer`, `BuffBarCooldownViewer`). Their item frames still
  bind such procs and expose a plain `auraInstanceID` plus `auraDataUnit` —
  which is enough for presence, duration and stacks. Matching goes through
  `C_CooldownViewer.GetCooldownViewerCooldownInfo`, comparing `spellID`,
  `overrideSpellID`, `linkedSpellIDs` and finally the spell name.
  The irony: the Cooldown Manager refuses to let you *add* this buff, yet it
  knows exactly when it is up.
- `/dks scan` — lists the buffs an addon is allowed to read and counts the
  secret ones, so "wrong ID" and "secret aura" can be told apart.

### Changed

- `/dks check` now reports all three routes separately, and states whether a
  hit carries timing or presence only.
- The watcher polls at 10 Hz, because secret procs give no readable event and
  the cooldown viewer binds its frames a moment after the aura lands.
- The display re-renders only when the shown aura actually changes, so polling
  never restarts the cooldown swipe.

## [1.1.0] - 2026-08-05

Rewritten for patch 12.x secret values. 1.0.0 threw on every aura change.

### Fixed

- **The addon errored on every `UNIT_AURA` event.** Patch 12.0 turned aura
  fields into *secret values*, and tainted code — which every addon is — may
  not use a secret as a table key. Matching `tracked[aura.spellId]` did exactly
  that. The whole scan-and-compare design was invalid on 12.x.

### Changed

- **Aura lookup reversed.** Instead of scanning auras and comparing their spell
  IDs, the spell ID now goes *into* the query via
  `C_UnitAuras.GetPlayerAuraBySpellID`. No secret is ever read.
- **Fallback lookup by spell name** via `C_UnitAuras.GetAuraDataBySpellName`,
  for auras whose applied ID differs from the tooltip or talent ID.
- **Cooldown swipe armed from a DurationObject**
  (`C_UnitAuras.GetAuraDuration` → `Cooldown:SetCooldownFromDurationObject`).
  Since 12.0.1 this is the only way to feed a cooldown frame secret timing.
- **Remaining time and stacks are rendered by the engine.**
  `expirationTime - GetTime()` is arithmetic on a secret and would raise, so
  the countdown comes from the cooldown frame and the stack count from
  `C_UnitAuras.GetAuraApplicationDisplayCount` (with `minCount = 2`, which
  applies the "hide a single application" rule engine-side).
- Icon and spell name are resolved from *our* spell ID, never from aura data.
- Bar mode animates its fill only when the aura's timing is readable; for
  secret auras the bar stays full and the engine countdown carries the timing.
- Changelog tab is now scrollable.

### Added

- `/dks check <spellID>` — reports whether that aura is findable right now, and
  by which route (ID or name). Distinguishes a wrong spell ID from a broken
  display.
- `/dks status` — what is tracked, what is currently active, and the current
  display settings.
- **Diagnose** button in the options window, running both of the above.

### Removed

- The "red timer in the last 3 seconds" option. It required comparing a secret
  value against a threshold, which is not permitted.

## [1.0.0] - 2026-08-05

### Added

- Isolated aura display — shows a single buff the Cooldown Manager cannot
  track, because it only offers spells from its own `C_CooldownViewer` data set.
- Ships tracking spell **1265968** (Boiling Point, Blood Death Knight, 15s).
- Two display modes: **icon** with cooldown swipe, stack count and remaining
  time, or **bar** with an icon plus a status bar and spell name.
- **Always show** option that keeps the display on screen while the aura is
  down, greyed out and desaturated.
- Self-built proc glow (expanding ring plus flash) and an optional proc sound.
- Movable and lockable display with a 15 second test preview for positioning,
  plus a reset-position action.
- Additional spell IDs can be tracked; the list doubles as a priority order —
  the first entry present on the player wins.
- Tabbed settings window (Options / About / Changelog), reachable via `/dks`
  or the addon compartment.
- Full slash command set under `/dks`, `/dkstuff`.

[1.1.0]: https://github.com/zwoelf/DKstuff/releases/tag/v1.1.0
[1.0.0]: https://github.com/zwoelf/DKstuff/releases/tag/v1.0.0
