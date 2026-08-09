# Changelog

All notable changes to ZwoelfStuff are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.41.1] - 2026-08-09

### Fixed

- **Six files the addon never loads were being packaged with it.** They did
  nothing on your machine - they are not in the load list - but they were
  dead weight in the download, and one of them was a feature that had been
  taken out. The build now leaves them behind.

## [4.41.0] - 2026-08-09

First public release. Everything below is new to anyone installing it now.

### Bars

- **Your own cooldown bars, as many as you like.** A bar is a grid of cells;
  set the rows and columns with two sliders and put a spell in each cell.
  Changing the shape re-flows what is already there rather than scrambling it —
  6×1 becomes 3×2 with the same spells in the same order.
- **Three arrangements:** grid, staggered, and puzzle, where every cell sits
  exactly where you dragged it. Every arrangement adds each cell's own offset
  on top, so nudging one icon out of a neat row and building a free-form
  layout are the same edit.
- **Per-cell overrides.** Any single cell can carry its own scale, offset,
  kind and visibility — one icon at 150 %, a tracking bar among the icons, a
  slot hidden while you decide. The overrides travel with the spell, not the
  position.
- **Icons or bars,** per bar or per cell. Bars can fill or drain over time,
  and the direction the fill runs is a separate setting from which end it is
  anchored to.
- **Effects, all off until you ask.** A flash when a cooldown lands, an edge
  while the spell is up, a nag for a defensive that has been ready too long in
  combat, a last-seconds warning, a glow while a tracked aura is up, and
  greying out while a cooldown runs.
- **Rules for when a bar is on screen:** combat, group size, target, rested
  area, and the kind of place you are in. Every rule starts on *any*, so a
  rule you have not set can never be the reason something is missing, and the
  panel tells you which rule is currently keeping a bar hidden.
- **Styling per bar,** with *Copy from* to take another bar's look in one
  click and *Save as* to store it as a named preset. Only sizes, spacing and
  colours travel; the spells and the grid stay with their own bar.
- Fonts and textures come from LibSharedMedia, so everything your other addons
  ship is in the pickers under the names you already know.

### Placing things on screen

- **Unlock mode** moves whole bars, with snapping to the screen centre and to
  other bars' edges and centres, a guide line showing what was caught, and
  Alt to switch snapping off. Arrow keys nudge, Shift for ten.
- **Bars can be attached to each other.** Snapping puts a bar next to another
  once; attaching keeps it there.
- **Build mode** takes a bar apart cell by cell on screen — drag, scroll to
  scale, Tab between slots, arrow keys to nudge, right click for kind, hide
  and reset. The spell palette opens beside it and the selection walks on to
  the next slot by itself.

### Reminders

- **Text on your screen when something is missing.** Write the message, drag a
  spell onto it from the same list the bars use, and choose when it fires —
  when the buff is missing, or when it is active.
- Text size, colour, flashing, an icon beside it, and the same visibility
  rules the bars have.
- Placed in edit mode like everything else, where all reminders are forced
  visible so you can see what you are arranging.
- If the client cannot say whether a spell is active, the reminder stays
  silent rather than shouting — an unanswerable question is not a missing buff.

### Co-tank panel

- One row per tank in your group, you first, so rows never reorder mid-pull.
  Health, name, absorbs, target ring, raid marker, and configurable
  indicators for marker, leader, role and combat.
- Aura strips are built and wired, and draw in test mode (`/zs tanks test`).
  Live aura data for another player needs patch 12.1; the panel says so itself
  and names the client build it read.

### The window

- Three fixed columns: what the addon does, everything you own, and the
  settings for whatever is selected.
- A changelog page, an about page, and a diagnostics page.
- Minimap button, addon compartment entry, and an entry in the game menu under
  Escape.

### Commands

| Command | Effect |
| --- | --- |
| `/zs` | open the window |
| `/zs unlock` / `lock` | move the bars around the screen |
| `/zs build` | take a bar apart slot by slot |
| `/zs bars` | list your bars |
| `/zs cdm` | what Blizzard's Cooldown Manager currently holds |
| `/zs reminders` | why each reminder is or is not showing |
| `/zs tanks` | the co-tank panel |
| `/zs auras` | the procs recorded on this spec |
| `/zs test` | the checks that run inside the game on the model and the rules |
| `/zs reset` | restore defaults, keeping recorded procs |

### How it works, and what that costs

- Every icon on your bars **is** one of Blizzard's Cooldown Manager frames,
  moved onto your cell. It keeps the correct icon, sweep, charges, stacks and
  timing, because on this patch aura data is secret and no addon may read it.
- Because Blizzard lays its own row out without knowing an icon left, it would
  show a hole where one used to be. Cooldowns you have not placed are
  therefore hidden as well. Settings → *Take the display over* switches that
  off and gives the row back, holes included.
- Auras the Cooldown Manager does not carry are drawn by the addon and timed
  on its own clock.

### Known limitations

- **Spells Blizzard's Cooldown Manager is not displaying have no frame to
  adopt.** They appear in the spell list under *Not shown by Blizzard*, and
  moving them into a viewer in Blizzard's own Cooldown Manager settings makes
  them usable here. Blizzard's default hides most of them.
- Live aura data for other players needs patch 12.1.

---

Versions before 4.41.0 were development builds and were never published.
