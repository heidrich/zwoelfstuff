# Changelog

All notable changes to ZwoelfStuff are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.6.1] - 2026-08-07

### Added

- **Twenty bar textures, shipped.** Flat, Smooth, Velvet, Charcoal, Gloss,
  Glass, Steel, Bevel, Inset, Neon, Outline, Ridged, Aluminium, Stripes,
  Blocks, Pixel, Cylinder, Hairline, Split and Frost. They go into
  LibSharedMedia under a `ZS` prefix, so they sit next to everything ElvUI,
  WeakAuras and the rest registered — and they are available to those addons
  in return. Generated rather than drawn: each one is a formula for "how
  bright is this bar at this height", and they are white-based because a bar
  texture is tinted by whoever draws it.
- **Drag a spell from the list onto a cell.** It genuinely was not
  implemented — clicking worked and always has, but picking a spell up and
  putting it where you want it is the gesture people reach for first. The
  cell under the cursor lights up while you drag, across every card.
- **A tool panel in unlock mode.** Grid and its step, snap to it, snapping and
  how far it catches, dim, permanent coordinates — saved, because they are
  working habits. Plus the selected bar's pattern, shape, sizes, spacing,
  scale and centring.
- **A logo.** A cooldown sweep closing around a two-tone 12.

### Changed

- **The bar card is a real preview.** It paints with the bar's own backdrop,
  texture, border and crop, through the same two functions that paint the
  thing on screen — so picking a texture shows you that texture, in the
  editor. A bar-shaped cell draws its square icon at the end you chose, its
  fill beside it and its spell name on top.

### Fixed

- The spacing model. Only half-width rows ever got a gap; every wide block was
  stacked flat against the one above. Invisible while rows were filled cards,
  text on text once they were not.
- `SetPropagateKeyboardInput` is protected in combat, and closing unlock mode
  at a training dummy raised `ADDON_ACTION_BLOCKED`.
- The border on an adopted buff bar sat on the fill. It frames from outside now.
- The icon on an adopted buff bar was smeared across the full width.

## [4.6.0] - 2026-08-07

Arrangements, effects, rules, and a build mode you use on screen instead of in
a window. This is the release where a bar stops being a row of icons.

### Added — arrangements

A bar is no longer rows and columns with a gap. There are five arrangements,
they all come out of one engine (`Core/Layout.lua`), and the editor preview
asks that same engine — so an arc curves in the window too.

- **Grid** — rows and columns, as before.
- **Staggered** — every other line pushed along by half a cell.
- **Arc** — cells around a circle. Span, start angle and radius are set; a full
  360 closes the ring, and the radius works itself out from the chord of the
  step angle unless you name one.
- **Diagonal** — each cell steps by a fixed offset. Steps, ladders, slants.
- **Puzzle** — every cell exactly where you dragged it. No lattice at all.

With them: **fill order** (rows first or columns first), **reading direction**
on both axes (left to right or right to left, top to bottom or bottom to top),
and **which point the bar is pinned by**. That last one is what people mean by
grow direction: pinned by the centre a bar spreads both ways when it gains a
row, pinned by an edge it grows away from that edge.

Puzzle is not a special case bolted on. Every arrangement adds each cell's own
offset on top of whatever the lattice worked out, so nudging one icon out of a
neat row and building a free-form layout are the **same edit**. There is no
line to cross between "a bar" and "a puzzle".

### Added — per-cell overrides

Any single cell can now carry its own scale, its own offset, its own kind and
its own visibility. One icon in a row at 150%. A tracking bar in among the
icons. A slot hidden while you decide. The overrides travel with the SPELL,
not the position — dragging a cell to another slot takes its settings along,
and re-flowing a grid carries them in the same sequence the spells move in.

### Added — build mode

`/zs build`, the **Build** button on every bar card, or the switch in the
unlock toolbar. Two modes, and the difference is the level you work at:

- **Move bars** — the whole bar is one object. Drag, snap, attach.
- **Build** — every cell is its own object. Drag it (snapped to the bar's
  raster, Alt for free hand), scroll to scale it, Tab through the slots, arrow
  keys to nudge, Delete to empty, right click for kind, hide and reset.

The **spell palette** opens beside it: click a slot, click a spell, and the
selection walks on to the next slot so filling a bar is one click each. Every
Cooldown Manager spell is in it, greyed when it is not talented — a bar can be
built for the spec you are about to switch into.

### Added — effects

The half of a cooldown display you read out of the corner of your eye. All off
by default.

- **Flash** when a cooldown lands, with a pulse count and a colour.
- **An edge** while the spell is up, optionally only in combat.
- **A nag**: a spell that has been ready for N seconds *in combat* starts
  pulsing. For the defensive you keep forgetting.
- **A last-seconds warning** on the auras this addon clocks itself.
- **A glow** while a tracked aura is up, and **greying out** while a cooldown
  runs.

What drives it is Blizzard's own `isActive` with `isOnGCD`, read off the info
table every item frame carries — the field names are taken from working code
on this machine, never guessed. Without the GCD test every spell in the game
"comes off cooldown" every 1.5 seconds and the flash is a strobe. Both fields
can arrive as secret values on 12.0, so both go through `ns.CanCompute` first
and an unreadable state means *do nothing* rather than *guess*.

Remaining time is deliberately **not** read for adopted frames: there is no
field for it and the Cooldown widget's timing is a duration object on this
patch. The option that needs it says so.

### Added — when a bar is on screen

Rules per bar, and every rule is an AND: combat, group size, target, rested,
and six kinds of place (world, dungeon, raid, scenario or delve, battleground,
arena). Every rule defaults to "any", so one you have not set can never be the
reason something is missing. Out of condition, a bar is gone — or dimmed to
whatever you choose, which is what you want while you are still arranging it.

Evaluated on the events that can change the answer and never on a timer. The
instance types are read off working code rather than written from memory, and
a type the client reports that this list has never heard of lets the bar
through: a new instance type in a patch must not make everyone's UI vanish in
the new content.

### Changed — the window

The density pass that was owed. Every setting used to be a filled card 38px
tall with a gap around it; forty of those is a brick wall, and "altbacken, viel
space wasted" was right.

- Rows are **flat**, 28px, separated by a hairline instead of a gap. Only the
  row under the cursor gets a surface.
- Section headings are smaller, their air is above them rather than evenly
  around them, and the fold marker is a drawn plus/minus — the old `v`/`>`
  were two glyph widths and shifted the caption every time a section folded.
- Buttons, switches and steppers all came down a notch to match.
- The bar preview in the middle column now draws the **real arrangement**,
  hit-tested against the real rectangles rather than divided out of a lattice.

### Notes

- Nothing here has been run in the game yet — the client was closed while it
  was built. Statically clean over 24 files.
- Saved settings carry forward untouched: every new key has a default, and a
  bar written before this release is a Grid with no effects and no rules.

## [4.4.0] - 2026-08-06

The bars are on screen, and there is an unlock mode to put them where you
want them. Also: the addon is called **ZwoelfStuff** now.

### The name

`DKstuff` was never right — the addon is not about Death Knights, it is about
cooldowns. It is named after the character it was written on: **Zwölf**, EU
Destromath. Spelled `Zwoelf` everywhere, because a folder name, a slash
command and a saved-variables key are all worse places for an umlaut than a
signature is.

Your settings come with it. The saved variables were migrated on disk; if you
ever see an empty addon, the old file is still sitting next to the new one.

### Added — the display

Everything you arranged in the window now actually renders, and a cell holds
one of exactly two things:

- **A Cooldown Manager cooldown.** It is not drawn — Blizzard's own frame is
  *adopted* and moved onto your cell. That frame has the correct icon, swipe,
  charges, stacks and timing, all computed inside the game where secret values
  are not a problem. Drawing our own would mean reading aura data, which patch
  12.0 forbids outright.
- **An aura proc.** No frame exists to adopt — that is why `Core/Auras.lua`
  exists at all — so the icon is drawn and the clock is ours, started by the
  glow on the ability the aura empowers and running for the duration that was
  *measured* rather than assumed.

The rules for touching Blizzard's frames are not style advice, and they are
taken verbatim from the reference implementation on this machine:

> Never SetParent/SetScale/Hide/Show on Blizzard frames · Never move Blizzard
> frames offscreen · Never write custom keys to Blizzard frame tables · All
> per-frame data in external weak-keyed tables · Unclaimed frames: SetAlpha(0)

Two things follow, and both are visible in the code:

- An adopted frame is still Blizzard's child, so it does **not** inherit our
  scale or our alpha. Per-bar *Scale* is therefore a size multiplier, not a
  `SetScale`, and per-bar opacity is pushed into the frame itself. Anything
  else would have applied to half a bar and silently skipped the other half.
- A cooldown you did not place vanishes with **alpha**, never with `Hide()`.

**It takes the display over, and Settings says what that costs.** Blizzard
lays its viewer out by walking its active frames and placing them in a row; it
has no idea one of them now lives on your bar, so it leaves a hole where that
one used to be. There is no version of this where the original bar still looks
right — so by default the cooldowns you did not place are hidden too. Switch
*Take the display over* off and you get Blizzard's row back, holes included.

### Added — Unlock Mode

Built to work the way EllesmereUI's does, because that is what this addon is
used next to and a second set of rules for "how do I move a thing" is a tax on
the user, not a feature.

- Every bar gets a labelled panel with its **live coordinates**.
- **Drag** it, or select it and **nudge with the arrow keys** — Shift for 10.
- It **snaps** to the screen centre and to the other bars' centres and edges,
  with a guide line showing what it snapped to. **Alt** switches snapping off
  while you drag, because "almost always right" is why there has to be a way
  out in the moment.
- A **cog** on each panel: bar options, centre on screen, centre on one axis,
  switch the bar off.
- **Shift + Right Click** hides the overlay so you can see what is underneath.
  The panel stays, or that would be a one-way door.
- A **grid**, and Escape leaves.

Positions are always the bar's centre offset from the screen centre — one
anchor for everything, which is what makes the readout mean something and
snapping arithmetic instead of a case analysis.

**Bars can be attached to each other.** Snapping puts a bar next to another
one *once*; attaching keeps it there — move the one it hangs on and it comes
along, resize the one it hangs on and it stays flush. That is the difference
between arranging a layout and rearranging it every time you change your mind.
The cog offers it, and afterwards the same menu switches the side. An attached
bar's readout shows what it hangs on, and dragging it adjusts the *offset*
rather than a screen position it no longer owns.

Bars have a real id now, because an attachment has to survive a delete
reshuffling every index below it. Ids are never reused. Deleting a bar sets
whatever hung on it free where it stands, a loop is refused before it can be
made, and both are checked again at login — the menu cannot produce a broken
state, but saved variables are a file on disk and files get edited.

### Added — the proc database is a file now

`Core/KnownProcs.lua`. It is data that grows with every export, and having it
in the middle of six hundred lines of logic made "paste your export here" mean
"edit around the machinery". It ships with the addon, so a fresh install
already knows what the spec's procs are.

- **`/zs auras forget` now works on shipped entries too.** Deleting one that
  the addon carries could only ever last until the file loaded again, so a
  thrown-away entry is remembered as thrown away.
- **`/zs auras remember`** puts every one of them back — the way out of
  forgetting the wrong one that does not involve editing saved variables.

### Removed

**The Aura Display page, and the single-buff window behind it.** An aura is a
cell on a bar now, so a second window showing one buff on its own was two
answers to the same question. `Core/Display.lua` and `Core/Watcher.lua` are
out of the load order, and every setting and command that only fed them is
gone rather than left to rot: `test`, `icon`, `bar`, `size`, `width`,
`height`, `scale`, `add`, `remove`, `list`, `check`, `status`, `scan`, `dump`,
`source`, `glow`, `glowlog`, `glowduration`.

`/zs unlock` and `/zs lock` now mean the bars.

### Fixed

- **A load-order crash, found by reading rather than by running.**
  `EditMode.lua` takes a reference to the design system while it loads, and it
  was listed *above* the file that defines it. The TOC now says so in a
  comment at the line it matters on.
- **Dragging could stick to the cursor.** `OnMouseUp` only fires on the frame
  the button went down on, and you can let go anywhere — including over
  another window or off the edge of the screen.
- **The aura catalogue was rebuilt once per cell.** A talent scan, forty times
  over, for one spec change. Built once per render pass now.
- **A hidden cell still answered the glow that drives it**, so shrinking a
  grid left a clock running on something nobody could see.
- The minimap button shows the addon's own icon instead of whichever aura was
  being tracked — that changed under the user and made the button hard to find
  again on a busy minimap.

## [4.3.0] - 2026-08-06

Auras — the ones Blizzard's Cooldown Manager does not carry.

### The shape of it

What is **shown** is the aura's own icon. What **drives** it underneath is the
action button that lights up while the aura is active. You see Boiling Point;
the addon watches Blood Boil.

That split matters, because an entry carries three things that are not
interchangeable:

| | what it is | what it is for |
| --- | --- | --- |
| `parent` | the ability whose button lights up | drives it on 12.0 |
| `display` | the icon and name to show | a choice, either route |
| `auraID` | the aura itself | drives it on **12.1** |

The aura's real ID is not needed for the glow route at all — we never query
the aura, we draw an icon and run our own clock — so what is displayed is a
*choice*, not a lookup.

### Added

- **An Auras group** in the spell list, with its own filter button.
- **It fills itself.** Every proc this character raises is recorded, per class
  and spec, while you play. No learn mode, no button, no timing. A proc nobody
  knew about announces itself once in chat and is in the list from then on.
- **The duration is measured, and it knows when it is guessing.** The time
  between `GLOW_SHOW` and `GLOW_HIDE` is the duration — but only if the glow
  ran out *on its own*. `UNIT_SPELLCAST_SUCCEEDED` says whether you cast the
  ability just before it went out, and that reading is a floor rather than a
  fact. Confirmed durations are green, floors are orange with a `>`.
  - This also answers a question neither of us could otherwise: **a proc that
    never runs out by itself is a "cast me" hint, not an aura.** No game
    knowledge required, and nothing to look up.
- **`/zs auras export`** prints this spec's set as a block that pastes
  straight into `KNOWN_PROCS`. A glow set belongs to a class and a spec, not to
  a player, so one person playing one spec once is enough for everybody who
  plays it. That is the whole distribution model for this data.
- **Ready for 12.1** (11 Aug 2026). `Auras:Route()` picks the engine when
  `Blizzard_AuraContainer` exists and an aura ID is known, the glow otherwise,
  and switches by itself. Availability is probed by *building* a container —
  the previous version gated on `LoadAddOn("Blizzard_AuraContainer")`, there is
  no such addon, and that gate could never open. Set the aura ID with
  `/zs auras bind <glowID> <auraID>`.
- `/zs auras`, `/zs auras icon <glowID> <spellID>`,
  `/zs auras forget <glowID>`.
- **Tooltips on every spell**, in the list and on the cells. The game's own
  tooltip, via `GameTooltip:SetSpellByID` — what a spell does is Blizzard's
  text to keep current, and anything written here would be a second version of
  it going quietly out of date. Underneath it, only what the game cannot know:
  where the spell already sits on your bar, what actually drives an aura, and
  what a click would do.

### Tried and rejected

**Reading the link out of talent descriptions.** The idea was sound — the text
does name abilities, and matching it against the client's own spell names is
locale-independent, since both sides come from the same client in the same
language.

It answers the wrong question. The description names the ability a talent
**modifies**, not the one that lights up: *Foul Bulwark → Bone Shield* means
"makes Bone Shield stronger". On the one case that could be checked it returned
**Heart Strike** where the confirmed answer is **Blood Boil**. And of the 48
candidates it produced, nearly all were passives that grant no trackable aura
at all.

The scan is kept, demoted: it now runs in the useful direction — *which talent
mentions this ability* — purely to suggest a caption, where being wrong costs a
label and nothing else. Its one real bug is fixed along the way: it kept only
the longest name match per talent, which hid Blood Boil behind Heart Strike.

### Fixed in the first live test

Three bugs the static check could not see, all found by running `/zs auras`
on a real character rather than trusting the code:

- **Every aura reported "no route"** — so nothing could ever have been
  displayed. `Route()` read `entry.parent`, but in the proc store the glowing
  spell is the *key*, not a field. It is passed in explicitly now.
- **The export would have shipped wrong data.** It read the raw recording
  instead of the merged view, so the bundled display was invisible to it and
  the caption fell back to a guess: Blood Boil came out as *Hemostasis*
  instead of *Boiling Point*, and pasting that in would have overwritten the
  one correct entry. It uses the merged view now.
- **A measured duration overwrote the shipped one** — Boiling Point dropped
  from 15s to 4s. Every measurement is a *floor*, because casting the
  empowered ability ends the glow early. Longest wins, including against the
  shipped value.
- `Defile on Defile` — when nothing better is known the icon simply *is* the
  glowing ability, and saying it twice reads as a fault.
- **An error on every login.** `ADDON_LOADED` called `ns.Auras:Seed()`, and
  that function never existed. Nothing was lost — it was the last line of the
  block — but it threw each time. There is no seeding step *by design*: the
  recorder registers itself when the file loads, and the shipped set is merged
  when the list is read, so an addon update brings new data instead of being
  shadowed by a stale copy in saved variables. Every other cross-module call in
  the addon was checked against its definition at the same time; this was the
  only one missing.
- **`/zs reset` no longer erases recorded procs.** They are measurements that
  take hours of playing to collect and cannot be typed back in, so they are not
  settings. `/zs auras forget <glowID>` is how those go away.

### Not done, deliberately

**A hardcoded table of aura-to-ability links.** There is no API for that
relationship, and writing one from memory is exactly what already produced two
wrong spell IDs in this project. `KNOWN_PROCS` ships with **one** entry, and it
was observed. It grows only from an export.

## [4.2.0] - 2026-08-06

Owner review of 4.1.0 — *"schon viel besser!"* — with five things to fix.

### Added

- **Two add buttons instead of one**: *Icon bar* and *Tracking bar*. The two
  are a different thing to build, not a setting you change afterwards — they
  want different sizes, a different default grid and a different place on
  screen — so choosing up front means the first one is already right.
- **The spell list is grouped**: Cooldowns, Utility, Buffs, Buff bars, each
  under its own heading with a count, with filter buttons above to jump
  straight to one. The category comes from
  `Enum.CooldownViewerCategory.Essential / .Utility / .TrackedBuff /
  .TrackedBar`, read off working code on this machine rather than guessed, and
  every lookup is nil-safe: a renamed member costs one heading, not the list.
- **Green for what is already on the selected bar** — a stripe down the left
  edge, the name in green, and the cell it sits in. Only the selected bar: the
  same spell may sit on three others, and marking it here would answer a
  question nobody asked.
- **Greyed out for what the current talent build does not have**, sorted to
  the end of its group. Still pickable, because a bar is often built for the
  build you are about to switch into. Uses
  `C_SpellBook.IsSpellKnownOrInSpellBook` — the reference CDM picker still
  calls the deprecated `IsPlayerSpell`; BigWigs on this client already uses
  the current form. A missing API means "assume known": greying out everything
  would be far worse than greying out nothing.

### Changed

- **One rule under every heading**, spanning the whole window at the same
  height in all three columns — including under ZwoelfStuff itself. Three separate
  lines with three sets of padding never quite agree, and the eye reads the
  disagreement as sloppiness even when the heights match. It lives on a chrome
  frame above the columns, because a texture on the window itself is painted
  *under* its own child frames no matter which layer it claims.
- **A more modern surface set**: a graphite palette with wider steps between
  the levels, a dedicated `well` for anything recessed, and `edge` for a
  card's own outline.
- Empty cells are **recessed wells** rather than raised tiles — a slot waiting
  to be filled reads differently from a button.
- The selected function in the left column is marked with **an accent bar and
  a neutral fill**, not a block of tinted orange that muddied its own label.
- New **soft** button weight: the accent is in the text, not the fill. The two
  add buttons use it, so the bars stay the thing you look at.
- The `Shape` setting is now **Kind**, with *Icon bar* and *Tracking bar*, the
  same words as the buttons that create them.
- The right column is headed **Spells**, not "Cooldowns" — it sat next to a
  middle column with the same title.

### Fixed

- **The spell list showed duplicates** — Anti-Magic Shell twice, Blood Boil
  twice. Several cooldown IDs can point at one spell; the catalogue is keyed
  by spell now, and the live pool wins because it knows which viewer actually
  shows it.
- Two font strings were given both `TOPLEFT` and `RIGHT`, which tells them two
  different vertical positions. Widths instead.

## [4.1.0] - 2026-08-06

The window rebuilt as an app, and made to look like one.

### The shape

Three fixed columns, each with one job:

| Column | What is in it |
| --- | --- |
| left | **the functions** — Cooldowns, Aura Display, Settings, Diagnostics, About, Changelog |
| middle | **every bar you own**, under each other, scrollable, plus *Add new bar* at the bottom of the stack |
| right | **every cooldown**, listed in full — or the settings for one bar while its Options are open |

The left column no longer lists your bars. Listing them there meant picking
one before you could see any of them, which is exactly backwards for a thing
whose whole point is having several.

### Added

- **The middle is the overview.** Each bar is a card that *is* the bar — same
  grid, same order, same sizes — with **Rows** and **Columns** as two sliders
  directly underneath it. Change one and the card changes shape under your
  hand. A grid too wide for the card is scaled to fit rather than clipped, so
  the arrangement stays honest.
- **Add new bar** sits at the bottom of the stack, where the next bar appears.
- **The spell list is always there.** Everything your Cooldown Manager knows,
  searchable, with a manual spell-ID box. Click a cell, click a spell — and
  the selection moves on to the next empty cell by itself, so filling a bar is
  click, click, click rather than click, aim, click, aim.
- **Options per bar**, reached from the card header and shown in the right
  column: name, shape, icon size or bar size, spacing, row gap, scale,
  opacity, border and border colour. *Done* goes back to the spells.
- **A look can be reused** — copy it from another bar in one click, or save it
  as a named preset and apply it to any bar later, deleting presets from the
  same menu. Only sizes, spacing and colours travel; the spells and the grid
  stay with their own bar, because those are what make it that bar.

### Changed

- **Nothing in the window is see-through.** A translucent panel over a moving
  3D world is unreadable, and the depth a glass effect only suggests is now
  done properly with distinct opaque surfaces — work area, window, side
  columns, cards, controls — each one step apart. Hairlines are opaque
  colours, not white at six percent.
- Hover on a spell cell is an outline rather than a white wash, which used to
  dull the very icon it was pointing at.
- The scrollbar shows a thumb and no track, and only when there is something
  to scroll.
- Sliders got a round handle, a thicker track and a live readout; the compact
  variant on the bar cards fits a label, a track and a value on one line.
- Text inputs can carry a placeholder, so an empty box says what it is for
  instead of looking broken.
- Panel text uses the client's UI font everywhere, including inside inputs.

### Fixed

- The command list offered `/zs groups`, `/zs catalog` and `/zs tanks`,
  none of which exist while that stack is parked. A usage list that names a
  missing command is worse than no list.
- The minimap tooltip advertised a right-click that toggled the co-tank panel,
  parked since 4.0.0.
- The About and Changelog pages used Blizzard's scroll template, whose pale
  bar cannot be styled to match anything around it.

### Not yet

Bars still render nothing on screen. That is deliberate and unchanged: the
operation gets signed off first, then the display.

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
- `/zs cdm` — what the Cooldown Manager currently holds, per viewer.
- `/zs bars` — list, add, remove.

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

- **`/zs group status`** — per spell, one of three answers: *slot refused*
  (a bug here, printed with the engine's error), *registered but never seen*
  (the slot is fine, the ID is wrong or the aura has not been up), or
  *bound*. This is what turns "only one icon shows" into something
  actionable in one command.
- Slots the engine refuses now report it in chat instead of disappearing into
  a `pcall`, and they keep their position in the order rather than silently
  closing the gap — a shorter row otherwise looks like a layout setting.

## [3.3.0] - 2026-08-05

### Added

- **`/zs probe <spellID> [seconds]`** — the decisive test for "can this be
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
- `/zs groups`, `/zs group add|remove|list`, `/zs catalog`.
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
  client in `/zs dump`).
- `/zs minimap` plus two options checkboxes to show/hide and lock it.

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
  them. `/zs tanks`, `/zs tanks unlock`, plus a **Co-Tanks** options tab.
- **Engine aura slot for the tracked buff.** `AddAuraFilter` with
  `candidateFilters.includeSpellIDs` binds the real Boiling Point aura — real
  icon, real duration, real stacks — instead of proxying it through the proc
  glow. `/zs source engine` / `/zs source glow` switches; the glow route
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

`/zs dump` run in combat with the buff up reported **0 readable, 18 secret**.
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
- `/zs glowlog` — logs every `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE` with
  spell ID and name, so the right ID is read off the client rather than guessed.
- `/zs glow <spellID or name>` — sets the proc source; a name is resolved via
  `C_Spell.GetSpellInfo`, so no ID is ever hardcoded. `/zs glow off` disables.
- `/zs glowduration <seconds>` — proc length, default 15.
- Proc glow section in the options window, with a live status readout.

### Changed

- Default `glowSpellID` is 50842 (Blood Boil), confirmed from the live client.
- `/zs dump` now also reports: combat state, which APIs actually exist, whether
  the target spell is in the Cooldown Manager data set at all
  (`GetCooldownViewerCategorySet` over all four categories), the current overlay
  state, and the override-spell state.

### Fixed

- **Diagnostics could not tell "API does not exist" from "aura not found".**
  Both printed `not found`. Every API is now reported explicitly.

### Known limitation

Several procs can light up the same button. If Blood Boil glows for another
reason, route 5 cannot tell them apart — the glow is the signal, not the aura.
`/zs glowlog` shows exactly which spell IDs fire, so a more specific source can
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
- `/zs dump` — dumps every entry of all four cooldown viewers (spell ID, name,
  shown state, whether timing is available) and every player buff (readable ones
  with ID and name, secret ones counted with their aura instance), marking any
  icon match. Must be run **while the buff is up**.
- `/zs check` reports all four routes.

## [1.2.0] - 2026-08-05

Boiling Point was still never found. 1.1.0 stopped the errors but not the
silence — because a secret rotational proc is invisible to *both* aura reads.

### Fixed

- **The tracked aura was never detected.** `GetPlayerAuraBySpellID` and
  `GetAuraDataBySpellName` both return nothing for secret-flagged rotational
  procs, no matter how correct the spell ID is. Confirmed in game: `/zs check`
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
- `/zs scan` — lists the buffs an addon is allowed to read and counts the
  secret ones, so "wrong ID" and "secret aura" can be told apart.

### Changed

- `/zs check` now reports all three routes separately, and states whether a
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

- `/zs check <spellID>` — reports whether that aura is findable right now, and
  by which route (ID or name). Distinguishes a wrong spell ID from a broken
  display.
- `/zs status` — what is tracked, what is currently active, and the current
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
- Tabbed settings window (Options / About / Changelog), reachable via `/zs`
  or the addon compartment.
- Full slash command set under `/zs`, `/zwoelfstuff`.

[1.1.0]: https://github.com/zwoelf/ZwoelfStuff/releases/tag/v1.1.0
[1.0.0]: https://github.com/zwoelf/ZwoelfStuff/releases/tag/v1.0.0
