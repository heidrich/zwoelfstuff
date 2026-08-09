# Changelog

All notable changes to ZwoelfStuff are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.44.1] - 2026-08-09

### Fixed

- **The death window said "no deaths this fight" while Blizzard's own recap
  stood open showing the killer.** The deaths list sits in the damage
  meter's answer under `combatSources`; this code read a field that does
  not exist and took the empty fallback for an empty fight. It reads the
  right one now - the field EllesmereUI's shipping code iterates - and
  checks the Current session first, Overall second.

### Added

- **Blizzard's own Death Recap is now the tie-breaker.** When it opens, the
  id it opens with is by definition your death - so it is taken over, and a
  window still saying "not enough was readable" repaints itself with the
  real events.

- **The defensive picker got spell icons, tooltips and a filter box.** A
  list of forty same-grey names tells you nothing; the icon is the
  recognition, the tooltip is the client's own, and typing narrows the list.

- The death probe prints the damage meter's answer WHOLE - both session
  types, every field of the session itself and of the first death in it -
  so a wrongly guessed field name can never blind it again.

## [4.44.0] - 2026-08-09

### Added

- **Deaths.** When you die, a window opens with what actually happened: the
  last ten seconds as a list you can read - each hit with its icon, its
  damage and the health you had left after it, the killing blow with its
  overkill - and a verdict on top: whether one hit did most of it or it was
  death by a thousand cuts, when the last heal landed, which of your
  defensives were STILL READY, and whether a healthstone or a potion sat
  unused in the bags. A button shares the short version with your group;
  words the client marks secret never go into chat. Everything comes from
  Blizzard's own death recap and damage meter - the readable sources on this
  patch - and readiness is our own estimate from your casts plus base
  cooldowns, honestly labelled as such. The window opening by itself can be
  switched off on the new Deaths page; `/zs death` opens it any time.

- **Timeline.** A panel with whatever the fight has scheduled next - the
  same feed the boss mods run on now - and your defensives under it,
  coloured by whether they are back. Pick the defensives on the new Timeline
  page; the same list tells the death window what counted as available. The
  panel shows in combat and is placed in Edit Mode. What it cannot do,
  honestly: the client marks event severity secret, so "tank busters only"
  is a filter no addon can build.

- **The options window can be scaled.** Settings, under This window: 60% to
  125%, live while you drag it. Not everybody has the pixels for 1360x760 -
  the owner's words.

- `/zs death probe` and `/zs timeline probe` print, field by field, what
  this client will actually reveal - run them once dead and once in a boss
  fight, and the window fills in what the measurements allow.

## [4.43.0] - 2026-08-09

### Changed

- **The Settings page finally says what applies to what.** It used to say
  "Applies to every bar" over rows about the minimap, and filed one font for
  the window and one for the bars under a single heading called "Text". It is
  three sections now, one axis: *Every bar* (taking over the Cooldown Manager
  display, the bar text font), *This window* (the panel font), and *Ways in*
  (the minimap button and the game menu entry).

- **"Take a layout from" and "Reset all settings" moved to Profiles.**
  Everything on Settings changes how something looks; those two change which
  settings you have at all - and that is the page whose subject that is, next
  to the delete button that already lives there.

### Fixed

- **"Take a layout from" had been broken since 4.42.0.** The dropdown listed
  your other characters, and picking one always answered "that character has
  no bars": the copy still read the saved-variable shape that the profiles
  migration deletes on first login. It reads the migrated one now, and the
  self test pins the two to the same answer.

- **A character sharing your profile is no longer offered as a copy source.**
  Copying a profile onto itself is not a copy: the cells are emptied on the
  way over, so "take my own layout" would have stripped every spell off the
  bars it claimed to duplicate. Possible at all since two characters can
  point at one profile.

## [4.42.1] - 2026-08-09

### Fixed

- **`/zs` listed a command that does not exist.** `/zs route` stayed in the
  help after the MDT pull badges were parked, so typing it did nothing at all.
  A menu naming something that does nothing is worse than a shorter menu.

- The help's one-line description of **`/zs reset`** still said it restored
  every default. It resets the profile you are using, and nothing else.

### Documentation

- **The README was rewritten.** It had been describing a different addon: it
  claimed 166 checks where there are 694, documented the *Arc* and *Diagonal*
  arrangements that were removed in 4.8.0, called the co-tank panel parked when
  it has been shipping since 4.41.0, listed a source file deleted in 4.9.0, and
  had nothing at all about reminders, profiles or sharing. It is the first page
  anyone sees on GitHub.

## [4.42.0] - 2026-08-09

### Added

- **Profiles.** A set of settings now has a name of its own, and your
  character points at one. It starts out pointing at a profile named after
  itself, which is exactly how this worked before - so nothing moved when you
  updated, and if you never open the page you will not notice it exists.

  Point a second character at the same profile and they really are the same
  settings rather than two copies drifting apart: change a colour on either
  and both have it. You can make a new empty one, copy the one you are using,
  rename it - every character using it follows - or delete it. The last
  remaining profile cannot be deleted, because something has to be in use.

- **Sharing, by string.** Copy what you have built into a piece of text and
  paste it anywhere - a chat window, a Discord, a forum. Whoever gets it
  pastes it back in.

  You choose what travels: bars, reminders, the co-tank panel, your saved
  looks, your settings - each with its own tick - and **one row per bar**
  underneath, so "here is my Bone Shield bar" is a single string rather than
  a whole profile somebody has to unpick.

  The string remembers which class and specialisation it was made on and says
  so before anything is written. Made on your class, the spells come with it;
  made on another, the layout arrives and the cells are empty, because a Death
  Knight's cooldowns are not castable on a Paladin. **Your character's name is
  not in it** - a string is made to be pasted somewhere public, and a layout
  is no reason to publish who built it.

  **Nothing you already have is thrown away.** Bars and reminders from a
  string are added to yours, not swapped for them - there is no undo here, and
  a string somebody handed you must not be able to delete an evening's work. A
  saved look whose name you already use keeps both. The co-tank panel and the
  settings are single things, so those do get replaced.

### Fixed

- **The two aura strips on a co-tank row were drawing on top of each other.**
  They sat at opposite ends of the same edge and grew towards each other,
  which sounds like it keeps them apart and does not: eight icons fill more
  than half the row, so from the fifth one on they were in the same place.
  Debuffs now sit along the top of the row and buffs along the bottom, both
  reading left to right, which cannot collide at any icon count or size. If
  you had never moved either strip yourself, yours is moved for you; if you
  had, your arrangement is left exactly as you set it.

- **`/zs reset` threw away your recorded procs**, despite saying it kept
  them. It also reset every character on the account, not the one you typed
  it on. It now resets the settings you are using and nothing else, and the
  procs really do survive.

### Changed

- **"Not shown by Blizzard" is gone as a heading.** The spells under it were
  not a different kind of thing - they are your spec's cooldowns, and on a
  default setup they are most of the list. They are listed under **Cooldowns**
  with everything else, in Blizzard's own order, with the ones you arranged
  first. The one thing that was worth knowing is still said, on the entry
  itself: a spell Blizzard is not currently displaying has no frame for this
  addon to adopt, and it takes one drag in Blizzard's Cooldown Manager
  settings to change that.

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
