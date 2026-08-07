# ZwoelfStuff — Handoff

State as of **2026-08-07**, version **4.6.0**. Read this first.

## Where we are

The addon is built around Blizzard's Cooldown Manager. The previous approach —
tracking auras directly — cannot work on this client, and establishing that
took most of a session. Do not restart it.

The window is an app in three fixed columns, and what you arrange in it
**renders on screen**. Bars are placed in unlock mode and taken apart, slot by
slot, in **build mode** — the two are one file and one overlay, at two levels.

A bar is no longer a row of icons. It is an *arrangement*: grid, staggered,
arc, diagonal or **puzzle**, with per-cell scale, offset, kind and visibility
on top of it, effects that react to the cooldown, and rules that decide when it
is on screen at all. See *Arrangements, effects and rules* for which file owns
what, and why none of them can reach the others.

Version 4.6.0 is statically clean over 24 files and **has not been run in the
game** — the client was closed the whole time it was built. The icon work in
4.5.0 WAS confirmed in game; everything added since has not.

## The shape of the window, and why it is that shape

```text
┌──────────────┬────────────────────────────────┬──────────────────┐
│ 208          │ flexible                       │ 292              │
│ FUNCTIONS    │ EVERY BAR, STACKED             │ EVERY SPELL      │
│              │                                │                  │
│ Cooldowns    │  ┌──────────────────────────┐  │  [ Search    ]   │
│ Aura Display │  │ 1. Cooldowns  Options Del│  │  ▣ Bone Shield   │
│ Settings     │  │ ┌──┬──┬──┬──┬──┬──┐      │  │  ▣ Blood Shield  │
│ Diagnostics  │  │ └──┴──┴──┴──┴──┴──┘      │  │  ▣ Death & Decay │
│ About        │  │ Rows ──●── 1  Cols ──●── 6│  │  ▣ Hemostasis    │
│ Changelog    │  └──────────────────────────┘  │  …               │
│              │  ┌──────────────────────────┐  │                  │
│              │  │ 2. …                     │  │  [ID] add by id  │
│              │  └──────────────────────────┘  │  48 cooldowns    │
│              │  [    +  Add new bar       ]   │                  │
└──────────────┴────────────────────────────────┴──────────────────┘
```

Owner's brief, verbatim, because every one of these is load-bearing:

- *"links spalte sind die Funktionen, mitte ist der content den wir bearbeiten,
  bei cooldowns halt die bars. rechte spalte da listen wir wenn wir bei
  cooldowns sind einfach mal alle spells auf!"*
- *"1. bar, da kannste rows und collumns einstellen, total simpel als regler
  darunter. muss nicht groß sein. dann direkt darunter, add new bar. die wird
  dann einfach darunter wieder mit dem regler angezeigt. fertig."*
- *"das add new bar einfach in die mitte! direkt unter die eine bar die da ist"*
- *"die mitte kann man doch scrollen. bars oder icons einfach untereinander"*
- *"die einstell optionen, größe, farben etc. die machen wir als options,
  direkt hinter die regler. da klickste drauf und dann fährt in der rechten
  spalte die einstellungen auf"*
- *"das ist dann für jede bar, oder man kann einstellungen von anderen bars
  übernehmen, oder als preset speichern"*
- *"mehr an apple anlehnen, aber keine transparenzen"*
- *"unten bei + add new bar, mach da 2 buttons, icon bar und tracking bar"*
- *"wenn ich die 1 icon bar angewählt habe, rechts die spells die ich schon
  geadded habe grün markieren?"*
- *"die trennlinien bei den überschriften sollten auf einer linie sein"*
- *"die spell spalte direkt sortieren nach utility, buffs, cooldown manager und
  auras … getrennt mit kleinen überschriften und oben selectoren für schnelles
  filtern"*
- *"spells / buffs die in der aktuellen skillung nicht verfügbar sind, sollten
  ausgegraut sein"*

Three rules fall out of that and must not be quietly undone:

- **The left column lists functions, never bars.** Listing bars there was the
  previous shape and it forced the user to pick one before they could see any
  of them.
- **Nothing in the window is see-through.** Layering is done with distinct
  opaque surfaces (`canvasBg → windowBg → sidebarBg → surface → surfaceHi →
  control`, plus `well` for anything recessed), one step apart, and hairlines
  are opaque colours rather than white at low alpha.
- **The header rule is ONE line across the whole window**, at `UI.HEADER_H`,
  drawn on a chrome frame above the columns. Do not give each column its own:
  three sets of padding never quite agree and the eye reads it as sloppiness.

## How the display works, and the rule that shapes it

`Core/Screen.lua`. **Two kinds of cell, two mechanisms, and they are not
unifiable** — do not try.

1. **A Cooldown Manager spell is not drawn.** Blizzard's item frame is
   *adopted*: `CDM:Pin(item, anchor, w, h)` holds it against Blizzard's
   relayout, `CDM:ForEachItemEverywhere` finds them, `CDM:ItemSpellID(item)`
   says which is which. Regions on an item frame: `.Icon`, `.Cooldown`,
   `.Applications`, `.ChargeCount.Current`, `.IconShadow`, `.CooldownFlash`.
2. **An aura proc has nothing to adopt.** Its icon is drawn and its clock is
   ours, started by `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW` on `entry.parent`,
   cleared by `_HIDE`, running for `entry.duration`. On 12.1 `Auras:Route()`
   answers `"engine"` instead and that path binds the real aura by `auraID`.

### The Blizzard-frame rules, verbatim from the reference

From the top of `EllesmereUICooldownManager/EllesmereUICdmHooks.lua`:

> Never SetParent/SetScale/Hide/Show on Blizzard frames · Never move Blizzard
> frames offscreen · Never write custom keys to Blizzard frame tables · All
> per-frame data in external weak-keyed tables · Unclaimed frames: SetAlpha(0)

**Two consequences that are easy to get wrong and hard to see:**

- An adopted frame is still Blizzard's child, so it does **not** inherit our
  scale or alpha. A bar's `scale` is therefore a **size multiplier** computed
  in `Metrics()`, never `SetScale`, and per-bar alpha goes into the frame via
  `CDM:SetAlpha`. Using frame scale would style our own cells and silently
  skip every adopted icon.
- Hiding is **alpha 0**, never `Hide()`. `CDM:SetAlpha` hooks `SetAlpha` for
  the same reason `Pin` hooks `SetPoint`: Blizzard reasserts its own on every
  relayout.

### Why it takes the display over

Blizzard's viewer walks its active frames and places them in a row. It does
not know one moved onto our bar, so it leaves a **hole**. There is no version
where the original row still looks right, which is why `takeOverCDM` defaults
to on and hides everything unplaced. The Settings note says what off costs.

### Known and accepted

- **One item frame, one place.** Two bars claiming the same spell: the first
  wins, the second draws a dimmed static icon (`cell.conflict`). It is not
  explained anywhere in the UI yet.
- Our bar frames sit at `MEDIUM`; adopted icons render at their viewer's
  strata, not ours.

## Unlock mode, and build mode

`Core/EditMode.lua`. Two modes, and the difference is the level you work at.

**Move bars.** Panel per bar with live coordinates, drag or arrow keys
(Shift = 10), snapping to the screen centre and other bars' centres and edges
with a guide line, Alt to suspend snapping, a cog menu, Shift + Right Click to
hide the overlay, a grid, Escape to leave. Modelled on EllesmereUI's, because
that is what this addon is used next to.

**Build.** The mover shrinks to a title chip above the bar and every CELL gets
a handle of its own. Drag it (snapped to the bar's `raster`, Alt for free
hand), scroll to scale it, Tab through the slots, arrows to nudge, Delete to
empty, right click for kind / hide / reset. The spell palette opens beside it:
click a slot, click a spell, and the selection walks on to the next slot.
Reachable as `/zs build`, the **Build** button on a bar card, or the switch in
the toolbar.

**Positions are pinned-point relative.** `cfg.point` is one of the nine points
and `x`/`y` are that point's offset from the screen centre; `relPoint` is
always `CENTER`. Pinned by the centre a bar spreads both ways when it gains a
row, pinned by an edge it grows away from that edge — that is what people mean
by "grow direction". Snapping still works in CENTRE terms and converts once,
in `OnUpdate`, because "line these two up" is about the shapes and not about
what each one happens to be pinned by. `Screen:CentreOffset` is the
translation; `Screen:CapturePosition` writes back for whatever point is pinned.

Traps already paid for here:

- `OnMouseUp` only fires on the frame the button went down on, so `OnUpdate`
  also checks `IsMouseButtonDown` — for the bar drag AND the cell drag.
- Anything reading `ns.UI` at file scope must load **after** `Core/Widgets.lua`.
- A cell drag moves the cell FRAME directly and only commits on mouse up. A
  full render pass walks Blizzard's frame pools, and running that per mouse
  move is how a smooth drag becomes a stutter.
- `target and SlotRect(target)` keeps only the FIRST return value. Lua's `and`
  truncates; the size came back nil. Use an `if`.

## Arrangements, effects and rules — where each one lives

Three files added in 4.6.0, each one deliberately unable to reach the others:

- **`Core/Layout.lua`** — pure geometry. Given a bar's settings it answers
  "cell 7 sits HERE and is THIS big", in centres, in the bar's own coordinates
  with +y up. Five arrangements: grid, staggered, arc, diagonal, **puzzle**.
  `Screen` takes the bounding box, sizes the bar frame to it and anchors each
  cell by its centre — so a bar is always exactly as big as what it holds, and
  the overlay, snapping and attachment work for a circle as well as for a row.
  Nothing in the file creates a frame or reads the game.

  **Puzzle is not a special case.** Every arrangement adds the cell's own
  offset on top of what the lattice worked out, so nudging one icon out of a
  row and building a free-form layout are the same edit.

- **`Core/Visibility.lua`** — when a bar is on screen. Every rule is an AND and
  every default is "any", so a rule you have not set can never be the reason
  something is missing. Sampled once per event, never polled. The instance
  types (`party`/`raid`/`arena`/`pvp`/`scenario`/`none`) are read off
  `EllesmereUI_Conditions.lua` on this machine, not written from memory, and an
  unknown type lets the bar through on purpose.

- **`Core/Effects.lua`** — flash, edge, nag, warning, greying. Driven by
  `isActive` + `isOnGCD` off the Cooldown Manager info table (field names read
  off `EllesmereUICdmHooks.lua` / `CdmFakeActive.lua`). **Without the GCD test
  every spell "comes off cooldown" every 1.5 seconds and the flash is a
  strobe.** Both fields can be secret on 12.0, so both go through
  `ns.CanCompute` and an unreadable state means *do nothing*, never *guess*.

  Remaining time is deliberately **not** read for adopted frames: there is no
  field for it and the widget's timing is a duration object on this patch. Do
  not go looking for `GetCooldownTimes` — it is not in use by any addon on this
  machine, only in a type-annotation file.

## The one thing to not re-derive

The client is **12.0.7.68974**. Verified from `.build.info` and `Wow.exe`.

| | on 12.0.7 |
| --- | --- |
| Read an aura | blocked — aura fields are secret values (12.0) |
| Hand one to the engine | impossible — `AuraContainer` is **12.1** |

`CreateFrame("AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")`
fails here. EllesmereUI gates every one of its AuraContainer files behind
`select(4, GetBuildInfo()) >= 120100`, and they are all inert on this client.

So on 12.0.7 the *only* sources are Blizzard's Cooldown Manager and the proc
glow. 12.1 content goes live 11 Aug 2026; re-check the parked stack after the
client patch lands.

## Architecture

| File | Responsibility |
| --- | --- |
| `Core/Init.lua` | namespace, defaults, saved vars, helpers, slash commands |
| `Core/Secrets.lua` | `ns.CanCompute`, `ns.SameValue` — the secret guards |
| `Core/CDM.lua` | the Cooldown Manager layer — viewers, item frames, pinning |
| `Core/Auras.lua` | procs the CDM does not carry — recorded per class+spec |
| `Core/KnownProcs.lua` | the shipped proc database, by class and spec |
| `Core/Bars.lua` | the bar data model — cells, arrangement, per-cell overrides |
| `Core/Layout.lua` | pure geometry: where every cell of a bar ends up |
| `Core/Visibility.lua` | the rules that decide when a bar is on screen |
| `Core/Effects.lua` | flash, edge, nag, warning — what a cell does beyond sitting there |
| `Core/Glow.lua` | self-built proc glow, no external library |
| `Core/Minimap.lua` | self-built minimap button |
| `Core/Widgets.lua` | the design system — every control, one look |
| `Core/Screen.lua` | the bars on screen — adopted CDM frames, drawn aura cells |
| `Core/EditMode.lua` | unlock AND build mode — movers, cell handles, palette, snapping |
| `Core/Changelog.lua` | changelog data |
| `Core/OptionsBars.lua` | the middle (bar cards) and the right column (spells / bar options) |
| `Core/Options.lua` | the app window: the three columns and the secondary pages |

### What `Core/Widgets.lua` already provides

Do not hand-roll any of these again — they exist and are consistent:

**Surfaces** `UI.C` (opaque colour tokens) · `UI.Fill` · `UI.Separator` ·
`UI.Card` (raised panel, `SetActive` for the accent edge) · `UI.Glyph`
(navigation marks drawn from rectangles — no icon files, nothing to 404).

**Controls** `UI.Label` / `UI.Hint` · `UI.Button` (`"primary"` and `"soft"`
styles) · `UI.GhostButton` (label-only, `SetBaseColor` for the resting
colour) · `UI.NavItem` (left column entry) · `UI.ChipRow` (flowing filter
buttons) · `UI.Row` (card row with a right-aligned control slot) ·
`UI.SectionHeader` · `UI.ListHeading` (caption + rule inside a list) ·
`UI.Toggle` · `UI.Slider` · `UI.MiniSlider` (label, track and value on one
line — the bar cards) · `UI.Counter` (− n +) · `UI.Dropdown` / `UI.Picker` /
`UI.MenuButton` (one shared popup, per-entry delete, trailing actions) ·
`UI.Swatch` · `UI.Input` (with placeholder) · `UI.SpellRow` (`SetUsed(cell,
known)` does the green mark and the greying).

**Layout** `UI.ScrollArea` (**our own** thumb, no track — never use
`UIPanelScrollFrameTemplate`, its pale bar cannot be styled to match) ·
`UI.CellGrid` (the editable bar grid: click, drag to swap, right click to
clear, selection ring, hover outline) · `UI.Page` → a `Grid` with
`Section(title, key)` (collapsible when keyed), `Row`, `FullRow`, `Note`,
`Wide`, `Layout`, `Refresh`.

Two font helpers, and they are not interchangeable: `ns.StyleUIFont` for
panel text, `ns.StyleFont` (the number font) only for digits drawn on icons.

### Layout traps in this codebase

- **A font string given both `TOPLEFT` and `RIGHT` is told two different
  vertical positions.** Set a width instead. Costs an afternoon to spot,
  because it renders — just not where it was put. Same for a texture anchored
  `BOTTOMLEFT` and `BOTTOMRIGHT` at different offsets.
- **A texture on the window is painted under the window's own child frames**,
  whatever layer it claims. Anything that must sit over the columns needs its
  own frame with a raised level — that is what `chrome` in `Options.lua` is.
- **`Grid:Row` splits into two columns**; in a narrow column use `FullRow`,
  or a 124px control lands in a 111px slot and shoves its own label out.

### Parked until 12.1 (on disk, out of the TOC)

`Engine.lua`, `Catalog.lua`, `Probe.lua`, `Groups.lua`, `CoTanks.lua`,
`OptionsGroups.lua`. The code is correct; it simply cannot run yet. The TOC
carries the reason next to them.

## How the Cooldown Manager layer works

Blizzard does the work. We take its frames.

```lua
for item in EssentialCooldownViewer.itemFramePool:EnumerateActive() do ... end
item.cooldownID                       -- what it is
C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
  -> { spellID, overrideSpellID, ... }  -- override wins
```

Three things that are easy to get wrong:

- **The frame pool is the ground truth**, not the category API.
  `GetCooldownViewerCategorySet` says where a cooldown *belongs*; Edit Mode
  and per-spec layouts move it somewhere else, and the viewer the frame is
  actually in is what the user sees.
- **Several cooldown IDs can point at one spell.** `CDM:Catalogue()` is keyed
  by spell for that reason — keying by cooldown listed Anti-Magic Shell three
  times. Each entry carries `viewer` (the group it is shown in) and `known`
  (`C_SpellBook.IsSpellKnownOrInSpellBook`, which is what greys a row out).
- **Blizzard re-anchors its items on every layout pass.** Setting a position
  once does not survive. `CDM:Pin` hooks `SetPoint` and `SetSize` and
  re-asserts from inside the hook, with a recursion guard because our own
  calls re-enter it.

Reference implementations on this machine, version-matched — read these
before inventing anything:

- `EllesmereUICooldownManager/EllesmereUICdmHooks.lua`
- `EllesmereUICooldownManager/EllesmereUICdmBuffBars.lua`
- `EllesmereUIActionBars/EllesmereUIActionBars.lua` (category enumeration)

## Measured on this character

`/zs cdm`, 2026-08-06:

```text
Cooldowns:  2 items (Dancing Rune Weapon 49028, one unresolved)
Utility:    4 items (Icebound Fortitude 48792, Lichborne 49039,
                     Vampiric Blood 55233, Anti-Magic Shell 48707)
Buffs:      2 items (both unresolved, hidden)
Buff bars:  4 items (Death and Decay 43265, Bone Shield 195181,
                     Blood Shield 77535, Hemostasis 273946)
Catalogue: 48 entries, 12 live frames
```

Note **Death and Decay 43265 sits in Buff bars** — the CDM already tracks the
standing-in-it state, which is what the owner was hunting spell IDs for.
"unresolved" frames are pooled but carry no cooldownID yet.

## Auras: how the proc registry works

An aura outside the Cooldown Manager's data set cannot be read on 12.0. The
only legal signal is the **proc glow**, so an entry splits into three things
that are not interchangeable:

| field | what it is | drives |
| --- | --- | --- |
| `parent` | the ability whose action button lights up | 12.0 |
| `display` | the icon and name shown — a **choice**, not a lookup | both |
| `auraID` | the aura itself | **12.1** `AuraContainer` |

`Auras:Route()` picks engine when the frame type exists and an `auraID` is
known, glow otherwise. Nothing has to be rewritten when 12.1 lands.

**The registry is observed, never written from memory.** Glows are recorded
per `CLASS:specID` while playing, and `/zs auras export` prints the set as a
block for `KNOWN_PROCS`. A glow set belongs to a class and a spec, so one
player, one spec, one session covers everybody who plays it. `KNOWN_PROCS`
ships with **one** entry. Add to it only from an export, and only when the
duration is not stamped `[duration UNCONFIRMED]`.

### How the duration is measured, and the two traps in it

Two readings, kept apart, and `duration` is the **maximum of everything**:

| | how it ends | worth |
| --- | --- | --- |
| `floor` | the ability was cast (`UNIT_SPELLCAST_SUCCEEDED` within 0.5s) | "at least this long" |
| `expired` | no cast seen — it ran out | the real duration |

Confirmed = `expired >= floor`. A shorter natural expiry than something we
already saw cut short means the two readings **disagree**, and a disagreement
is not a fact.

Both traps were hit live and cost real numbers:

- **A natural expiry used to win outright.** One 2s reading wiped a 15s value.
  Cause: Boiling Point *changes* Blood Boil, so the cast reports a different
  spell ID and "no cast seen" was never proof that it ran out. Hence the max
  rule.
- **A floor used to overwrite the shipped value**, dropping a shipped 15s to a
  measured 4s. Every measurement is a floor unless proven otherwise.

### Do not re-try: reading the link out of talent descriptions

It works mechanically and it is locale-independent (match the client's own
spell names against the client's own description text). It answers the **wrong
question**: the text names the ability a talent *modifies*, not the one that
lights up. Measured on this character — 48 candidates, nearly all passives
with no trackable aura, and for Boiling Point it returned **Heart Strike**
where the confirmed answer is **Blood Boil**.

The scan survives, demoted to suggesting a caption in the reverse direction
(*which talent mentions this ability*), where being wrong costs a label.

## Lessons that cost real time — do not repeat

- **Never guess a WoW API, and never guess a spell ID.** Grep
  `C:\Games\World of Warcraft\_retail_\Interface\AddOns` first: working,
  version-matched code beats documentation and beats memory. Two IDs were
  asserted from a database summary and both were wrong.
- **A defensive wrapper around an unverified call hides a total failure.**
  Twice in one day: a `pcall` around `AddAuraFilter`/`AddAuraFrame` (functions
  that do not exist) and a `LoadAddOn("Blizzard_AuraContainer")` gate (an addon
  that does not exist) each disabled entire features silently. Check existence
  *loudly*, then wrap.
- **Verify the foundation before building on it.** `/zs cdm` exists precisely
  so the next layer is not built on an assumption.
- **One broken feature must not take the others down.** The login handler ran
  the features in a straight line; one error killed the minimap button and the
  co-tank panel too. Each boots independently now.
- **`ns.CreateBorder` returns a table of textures, not a frame.** It has
  `SetColor`, `SetShown`, `Show`, `Hide` — and nothing else from the frame API.
- Container-style engine frames come **mouse-enabled** and will swallow clicks
  meant for the frame underneath, which is how "unlock" looked broken.

## Owner feedback that shaped this

- *"das ist kein gutes ui"* — the settings window was a flat list of steppers
  and checkboxes. Rebuilt as a panel with a sidebar, card rows and real
  controls (`Core/Widgets.lua`).
- *"ich muss einfach anklicken, spell eingeben und ggf mit drag and drop
  sortieren"* — hence the cell grid, not a list with arrow buttons.
- *"ich sollte reihen und spalten adden können, und das sollte man dann auch
  direkt sehen"* — hence the grid in the options *being* the bar.
- *"du bastelst komplett am ziel vorbei"* — stop building infrastructure the
  owner cannot see. Ship something operable, get it judged, then extend.
- *"sieht so aus, sehr altbacken, viel wasted space, ggf denken leute das ist
  nicht zugehörig"* — the verdict on 4.0.0's window. What it was: a rail of
  bars, one bar on a vast empty stage, a small floating inspector. What
  replaced it is the three-column shape at the top of this file.
- *"wenn leute es nicht nutzen können oder verstehen, verschwenden wir nur
  arbeit"* — the standing bar for anything in this window.
- Goal, in the owner's words: **own bars, the owner picks the spells.**
  Blizzard's CDM is the data source behind it, nothing more.

## Open, in order

**The schedule, from the owner on 2026-08-06:** heavy work over the weekend of
8-9 Aug, and **every basic finished by Wednesday 12 Aug** — because patch 12.1
lands on **11 Aug** and the 12.1 features go in after that, not instead of the
basics. The parked stack (`Engine`, `Catalog`, `Probe`, `Groups`, `CoTanks`,
`OptionsGroups`) is what waits for it, plus the owner's tank ideas, which they
deliberately held back until the basics stand.

1. **Run 4.6.0 in the game.** None of the arrangement engine, build mode,
   effects or visibility rules has been seen working — the client was closed
   the whole time it was built. First pass to make: open `/zs`, switch a bar to
   **Arc**, check the preview curves and the screen agrees; then `/zs build`,
   drag a cell, scroll it, and confirm the bar frame resizes around it on mouse
   up. Then switch **Flash** on and watch one cooldown land.
2. **Owner-side data**: confirm the remaining proc durations by letting one run
   out *without* casting the ability, then `/zs auras export` for Blood and
   paste it into `Core/KnownProcs.lua`. Then Frost and Unholy.
3. **Tank ideas** — the owner has a list, held back until the basics stand.
4. **Logo** — SVG for the repo, TGA for the game. WoW cannot load SVG.
   Interim: `## IconTexture: 1380870`.
5. After 12.1 lands: un-park the aura stack and re-test it.

### The window density pass is DONE, and what it changed

The complaint was *"altbacken, viel space wasted"*. The cause was that every
single setting was a filled card 38px tall with a gap around it — forty of
those is a brick wall however good the colours are.

What replaced it, in `Core/Widgets.lua`: rows are **flat**, 28px, separated by
a one-pixel hairline instead of a gap, and only the row under the cursor gets a
surface. Section headings are smaller with their air ABOVE them, and the fold
marker is a drawn plus/minus — `v` and `>` are two different glyph widths and
shifted the caption every time a section folded. Buttons, switches and steppers
all came down one notch.

`UI.CellGrid` no longer lays itself out. It asks `ns.Layout.Build` — the same
engine the screen uses — and hit-tests the cursor against the real rectangles.
A second implementation would have drifted from the first the day either
changed, and an arc has no columns to divide by anyway.

### The icons are FIXED, and the lesson cost a day

Adopted icons came out at different sizes and shoved into each other, and
`/zs skin` reported every one of them as a correct 36x36. Both were true:

**A frame's width is measured in its OWN coordinate space.** Blizzard scales
its item frames — its Cooldown Manager has a size slider in Edit Mode — and on
one live bar there were four different scales at once: 1.30, 1.10, 1.10, 0.90,
against a cell at 0.64. A frame at scale 1.3 reports 36 and draws 47. Every
check passed while nothing matched.

So: both reports read `GetEffectiveScale` and print **screen pixels**, the
pinned size is compensated by the ratio between the frame's effective scale and
the cell's, and `SetScale` is hooked so a later rescale re-asserts. Anchoring
needs no correction — a point resolves in screen space already.

Three other things had to be true first, all found the same way:
`UI-CooldownManager-OORshadow` at alpha 0.5 (an out-of-range veil on a
self-cast spell); the rounded mask, which had to be **removed from the icon**
rather than redefined; and the icon texture, which has to be told to fill the
frame because each viewer anchors its own.

**The rule this leaves behind:** with these frames, nothing is one-time. Anchor,
size, alpha, mask, scale and the icon's own anchoring all come back when the
pool hands the frame out again. Everything is re-applied on every skin pass and
hooked where Blizzard writes it back. And when a measurement disagrees with the
screen, **the measurement is wrong** — the owner said so three times before I
looked at the right number.

### Known, decided, do not re-litigate

- **EllesmereUICooldownManager must stay off.** There is one set of Cooldown
  Manager item frames and both addons adopt them; they fight per frame. The
  addon detects this itself and says so once, and Diagnostics shows it
  standing.
- **The bars take over Blizzard's display** by default, because its viewer
  lays itself out without knowing an icon left and would show a hole.
  Settings can switch it off and says what that costs.
- **Libraries are allowed here** — the owner said so explicitly for WoW
  addons. LibSharedMedia is a registry, not a look. The window and the
  widgets stay self-built.

## Verification

No Lua interpreter is installed. Use the language server from the VS Code
extension:

```powershell
& "$env:USERPROFILE\.vscode\extensions\sumneko.lua-3.18.2-win32-x64\server\bin\lua-language-server.exe" `
    --check "C:\Users\Christian\Documents\GitHub\ZwoelfStuff" --checklevel=Warning --logpath="$env:TEMP\llscheck"
```

Green means syntactically and globally clean. It does **not** mean it runs —
it cannot see the type behind `ns.CreateBorder(...)`, and every bug that cost
time this session passed this check.

WoW API globals must be listed in `.luarc.json` under `diagnostics.globals`.

## Install

```text
C:\Users\Christian\Documents\GitHub\ZwoelfStuff                    <- edit here
C:\Games\World of Warcraft\_retail_\Interface\AddOns\ZwoelfStuff   <- NTFS junction
```

`/reload` picks up edits. **A file added to or removed from the TOC needs a
full client restart.** The junction was made with `cmd /c mklink /J` —
`New-Item -ItemType SymbolicLink` needs elevation, a junction does not.
