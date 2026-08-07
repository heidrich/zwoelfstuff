# ZwoelfStuff — Handoff

State as of **2026-08-07**, version **4.15.0**. Read this first.

**Run `/zs test` before you believe anything below.** ~86 checks in
`Core/SelfTest.lua`, on throwaway configs plus a read-only pass over the real
bars. It never touches saved data. It was written by reverting the fixes in a
scratch copy of `Core/` until it went red, so it is a regression test and not a
decoration — and it can be run **on the desktop**, see *Lessons* below.

## Where we are

The addon is built around Blizzard's Cooldown Manager. The previous approach —
tracking auras directly — cannot work on this client, and establishing that
took most of a session. Do not restart it.

The window is an app in three fixed columns, and what you arrange in it
**renders on screen**. Bars are placed in unlock mode and taken apart, slot by
slot, in **build mode** — the two are one file and one overlay, at two levels.

A bar is no longer a row of icons. It is an *arrangement*: grid, staggered or
**puzzle** (arc and diagonal were removed in 4.8.0), with per-cell scale,
offset, kind and visibility
on top of it, effects that react to the cooldown, and rules that decide when it
is on screen at all. See *Arrangements, effects and rules* for which file owns
what, and why none of them can reach the others.

Version 4.15.0 is statically clean over 25 files and passes its own checks.
Parts of it HAVE now been seen running — see *What is confirmed in game* below,
which is the list that matters, because the rest has only ever been read.

## What is confirmed in game, and what is not

The owner is playing on this build. Split honestly, because "it is written"
and "it works" are different claims and only one of them is worth anything.

**Seen working**

- Icons on a bar come out one size, square, correctly spaced (4.5.0, and the
  lesson that got there is below).
- The window renders: rail, bar cards, the settings column with the new
  Arrangement, Effects and Visibility sections.
- The twenty shipped bar textures appear in the texture list.
- An adopted buff bar renders as a bar — square icon, fill, name — after the
  smear fix.

**Reported broken, then fixed, NOT yet re-checked**

- The spacing model (wide blocks had no gap at all).
- `SetPropagateKeyboardInput` blocked in combat.
- The border sitting on a bar's fill instead of outside it.
- The bar textures were generated one directory ABOVE the repo, so the addon
  registered twenty names pointing at nothing. Fixed and verified as
  uncompressed 32-bit bottom-up 256x64 TGA — the format the client loads.
- **Switching pattern scattered the bar and never gave it back** (4.7.0). The
  root cause and the twelve fixes around it are the next section.

**Covered by `/zs test` — proven by code, not by eye**

Everything the self test asserts is now checked on every run: arrangement
geometry for every pattern, the two coordinate systems, pattern round trips,
the rows and columns sliders, the bar-fill settings, what is shared between
characters and what is not, and the visibility rules against their own
explanations. That is not the same as "seen working" and is not listed as such
— it is the difference between "the maths is right" and "it looks right".

**Written, never run**

- Build mode as a whole: cell handles, dragging, wheel-scaling, the spell
  palette, the tool panel. The MODEL under it is tested; the frames are not.
- Every effect on screen: flash, ready edge, nag, low warning, aura glow, dim.
- The new bar fill on a cell this addon draws itself.
- Drag-and-drop of a spell from the list onto a cell.
- The media previews in the dropdowns.
- The logo as a TGA (header verified, loading not).

## What changed on 2026-08-07, after 4.6.1

Seven releases in one session, all of them driven by owner reports. The three
that changed the SHAPE of the addon, because nothing below makes sense without
them:

**4.9.0 — tracking bars are DRAWN, not adopted.** Blizzard's `TrackedBar`
template is a whole bar: its own border, its own fill, its own two font
strings. None of it is restyleable, which is why the thing on screen never
matched the preview and why a border stayed on a bar set to thickness zero.
The frame is kept alive as a *data source* at alpha 0 and our own StatusBar
mirrors it — `SetMinMaxValues`/`SetValue` passed straight through, nothing
inspected, which is what keeps it legal with secret values. **Icons are still
adopted** and that stays deliberate: there the frame IS the art. See
`Screen:PaintCell`, and `EllesmereUICdmBuffBars.lua:4649` for the same
decision made by the reference.

**4.11.0 — every setting lives under `"Name - Realm"`.** Owner: *"mach ich eine
änderung am ui oder egal was, muss das unter dem charakter namen und server
gespeichert werden"*, because *"sonst wird das pro klasse oder spec ja jedes
mal überschrieben"*. `ns.db` points at the profile; `ns.account` holds the
recorded procs, which are measurements and stay shared. `ns.OpenProfile` is
the only place that knows. **Settings → "Take a layout from"** copies another
character's bars with every cell empty.

**4.10.0 — inside a profile, the spells are per spec.** `cfg.cells` is pointed
at `cellsBySpec[class:spec]` by `Bars:BindSpec`. Forty-five call sites are
unchanged because only that one function knows the rule. The consequence, and
it reverses an earlier decision: **the per-cell look belongs to the SLOT, not
the spell** — a slot at 150% is part of a layout every character sees.

Everything else, in one line each: the puzzle got its own coordinate fields
(4.7.0); Arc and Diagonal were removed on the owner's call (4.8.0); the fill
picker now reaches adopted buff bars (4.8.0); "Fill up" was split from "which
end" (4.9.0); the spell list sorts in Blizzard's own order (4.11.1). All twenty-odd
fixes are in CHANGELOG.md with the reasoning.

## The 4.7.0 bug hunt, and the one root cause under it

The owner reported one thing: *"wenn ich diese einstellungen ändere, switchen
die nicht mehr zurück"*. Reading the code that report pointed at turned up
eleven more. All twelve are in the CHANGELOG; three matter for anyone working
on this next.

**One field, two meanings.** `cellOpts[i].x/y` was a POSITION in the puzzle and
an OFFSET from a slot everywhere else. Entering the puzzle wrote positions into
it; every other arrangement then added them to the slot it had worked out, for
ever, and nothing anywhere removed them. The puzzle has `px/py` now, and
`Layout.OffsetKeys/GetOffset/SetOffset` are the only way either pair is
touched — add a third arrangement with its own coordinate system and it goes
through the same three functions.

**A slider must not be able to destroy work.** `SetGrid` compacted every spell
to the front on every change and dropped whatever no longer fitted. Cells keep
their index now, and anything that does not fit is PARKED in `cfg.parked` and
comes home to its own slot when there is room. `Bars:Resized` is the one place
that does it, and it is called from every operation that changes the count.

**A cell is reused for whatever spell lands at its index.** Everything
remembered about the previous one — the aura clock, the effects' "was it ready
a moment ago" — has to be cleared with it. It was not, so a swapped icon
arrived lit up and flashed for a transition that belonged to a spell no longer
on the bar. Anything new that caches per-cell state belongs in the same reset
in `Screen:PaintCell` and `Screen:BlankCell`.

**Owner's verdict on the look, verbatim:** *"ich finde das alles nicht so
dolle was im spiel angezeigt wird"*, and the icon *"ist jetzt auch nicht
cool"*. Both stand. The agreed diagnosis is in *Why it looks weaker than it
should* below.

## Taking the reference apart: what the CDM block actually says

Started 2026-08-07 on the owner's instruction. Read so far:
`EllesmereUICooldownManager.lua` (structure, defaults, hide/restore) and
`EllesmereUICdmBuffBars.lua` (the tracking bars, in full earlier).

### The finding that contradicts our own header

`Core/Screen.lua` carries five rules "verbatim from the reference", one of
which is **"Never move Blizzard frames offscreen"**. That comes from
`EllesmereUICdmHooks.lua` and it is true THERE. But
`EllesmereUICooldownManager.lua:3303` does exactly that, on purpose, and says
why in a way that lands directly on the mirror we shipped in 4.9.0:

> It is parked offscreen rather than Hidden because TBB mirrors min/max/value
> straight off Blizzard's Bar frames — **a hidden viewer stops updating them**.
> The park, not the alpha, is what actually holds: Blizzard's hide-when-
> inactive fade **animates the viewer's alpha back to 1** whenever a tracked
> buff goes active, through a path no hook can see.

Both halves apply to us now:

1. **A hidden viewer stops feeding the mirror.** Our bars are driven by
   `blizzBar:GetValue()`. If the viewer is hidden — by the user in Blizzard's
   Edit Mode, or by Blizzard's own hide-when-inactive — our bar freezes. We
   already warn about hidden viewers (`Screen:WarnIfInvisible`); we do not
   handle it.
2. **Alpha 0 does not hold on the buff-bar viewer.** Blizzard animates it back
   to 1 on the next proc, so Blizzard's own bars draw on top of ours. This is a
   PREDICTED bug in 4.9.0, not yet observed — the owner should be asked whether
   Blizzard's buff bars reappear over ours during a fight.

Their answer, in order: park the viewer at `-10000, 10000` (position, never
`Hide`); hook `SetPoint`, `SetAllPoints` AND `SetParent` to re-park, because
the last two strand the frame without ever calling the first; **defer the
re-park by one frame** (`C_Timer.After(0)`) because Blizzard re-anchors from
inside an Edit Mode layout pass that goes on to move protected systems, and
re-parking inline carries taint into it; in combat set alpha only and flush on
`PLAYER_REGEN_ENABLED`, because the frame is protected; and run a 10 Hz
integrity check that reads where the viewer actually is, with a **tolerant**
compare — exact equality failed every pass on a scaled UI and re-parked
forever.

### What the spell picker said — the whole of 4.12.0

`EllesmereUICdmSpellPicker.lua` is 2034 lines and it describes BOTH of the
things the owner reported. Five distinct causes, none of them guessed.

**The sorting.** Two faults, and the second is the bigger one.

1. Our `Catalogue` numbered every category from 1, so the first Cooldown and
   the first Utility both scored 1 and the sort fell through to the name —
   which interleaved the groups alphabetically. The reference gives each
   viewer a **band of 10000** (`:288`). `CDM:ViewerRank` does that now.
2. Our live pass supplied **no order at all**, with a comment claiming "a
   frame pool is not a sorted list". That comment was wrong: every item frame
   carries **`frame.layoutIndex`**, which is the position Blizzard lays the
   row out by (`:282`). The live pass now supplies `rank * 10000 + layoutIndex`
   and wins over the static list, exactly as the reference does.
3. The static half came from `GetCooldownViewerCategorySet`, which does not
   know what the user arranged: a spell dragged to **Not Displayed** stays in
   that set forever, so our picker kept offering spells the owner had removed.
   `CooldownViewerSettings:GetDataProvider():GetOrderedCooldownIDs()`
   (`:453-501`) IS the arrangement — hidden entries report a category we do
   not map, so they drop out by themselves. `CDM:ForEachCatalogued` prefers it
   and falls back to the category sets, every step `pcall`-guarded, because
   the provider only exists once Blizzard's settings frame has been built.

**The tracking.** `info.overrideSpellID or info.spellID` was one line and
three bugs.

1. **The override goes stale.** Blizzard keeps reporting one after the talent
   providing it is gone (`:483-493`). Guarded now by asking whether the player
   actually has it. NOTE: the reference asks `IsPlayerSpell`, which is
   **deprecated** on this build — `C_SpellBook.IsSpellKnown` is the current
   spelling and what the installed addons use (27 call sites vs 21 for
   `IsSpellKnownOrInSpellBook`).
2. **The frame knows better than the info table** (`:158-161`). Under a
   transform, `frame:GetSpellID()` returns the form that exists in the world.
   It is now step one, with `GetAuraSpellID` behind it for bar frames.
3. **An active aura answers with a secret** (`:131-141`), so resolution fell
   through to the generic spec entry — the icon changed into something
   unrecognisable for exactly as long as the buff was up. The last CLEAN read
   is cached per `cooldownID` and reused. It self-heals: any later clean read
   overwrites it.

**And the consequence nobody would have predicted:** a stored spell must be
indexed under **every form of itself**, or a talent transform orphans the cell
— the spell is on screen and the bar goes blank (`:322-339`, `FindVariantIndex`
matching by family). `CDM:VariantFamily` / `CDM:SameSpell` do that, and
`Screen.RebuildItemIndex` indexes all four forms with **the exact ID winning
and the derived ones only filling gaps** — the reference is explicit about
why (`:71-79`): two spells of one family can be tracked at once, and without
that rule whichever came out of the pool first answers for both.

One trap this created: the order is now **absolute**, so the old `or 9999`
sentinel for "no order" sits INSIDE the first viewer's band. It is
`math.huge` in both sorts (`CDM.lua`, `OptionsBars.lua`). A fixed sentinel
cannot work once the key is banded.

`Core/Catalog.lua` got the same resolver, but it is **parked out of the TOC**
until 12.1, so that half is inert today and correct when it returns.

### The settings, taken apart — 2026-08-07

Their tracking-bar vocabulary is **93 fields** (`grep -oE "cfg[.][a-zA-Z_]+"
EllesmereUICdmBuffBars.lua`), their icon-bar defaults another ~40
(`EllesmereUICooldownManager.lua:527`). Ours is 52 bar fields + 16 effects.
The gap is not evenly spread, and most of it is not worth closing.

**What they have that is genuinely missing here** — ranked by what it is worth
to a Blood tank, which is the only ranking that matters for this addon:

| theirs | fields | worth |
|---|---|---|
| ~~stack thresholds~~ — **BUILT in 4.13.0**, three bands. Ticks and a stack-driven fill length were left out | 14 | **Bone Shield.** Was the single biggest win available |
| ~~pandemic glow~~ — **BUILT in 4.15.0** as one effect. Their five glow styles, speed, thickness and line count were left out | 10 | was high: the other half of "when do I press it" |
| ~~custom active states~~ — **BUILT in 4.14.0** as "Active for". Their per-spell menu, glow styling and 12.1 engine-slot driver were left out | — | was **high, and nothing else here could do it** |
| charge hash lines across the fill | 5 | medium, cheap to build |
| keybind text on an icon, with size/offset/align/colour | 6 | medium |
| style presets, saved per profile and applied by name | — | medium, and see the note below |
| spark, gradient fill, vertical bars, decimals below N seconds, custom duration | ~12 | low each |
| name/timer/stack text with independent position, size and offset | 14 | low: three of ours are booleans, and that is a deliberate simplification |

**The style-preset idea is worth stealing for its SHAPE, not its feature.**
`TBB_STYLE_KEYS` (`EllesmereUICdmBuffBars.lua:1511`) is an explicit list of
which of the 93 keys are *look* and which are *identity or position*, and
`CopyTBBStyle` copies key-exact **including nil**, so two bars resolve
defaults identically. We already made the same distinction the hard way in
4.10.0 (the look belongs to the SLOT, the spell does not) but we have no such
list — `Bars:CopyLayoutFrom` names what to DROP instead of what to copy, which
is the fragile direction: a field added tomorrow is silently copied.

**Where we are already better, and should not "fix" it:**

- **Arrangements.** They have rows, spacing and a vertical flag. We have grid,
  staggered and a free puzzle with per-cell scale, offset, kind and
  visibility. Nothing in their file approaches it.
- **One bar, mixed cell kinds.** A tracking bar sitting among icons is ours
  alone; theirs are three fixed bar types.
- **Visibility.** Ours is a rule set (`ns.SHOW_*` in `Core/Visibility.lua`);
  theirs is six booleans (`visHideHousing`, `visOnlyInstances`,
  `visHideMounted`, `visHideNoTarget`, `visHideNoEnemy`, `barVisibility`).
  Ours also has a fade factor rather than a hard hide.
- **The self test.** They have none.

### The trick that makes stack colours legal — 4.13.0

Worth its own heading, because it generalises and nothing else in this
codebase does it yet.

**A secret value may be passed but never compared.** So do not compare it.
`StatusBar:SetMinMaxValues(N - 1, N)` plus `SetValue(count)` makes the C layer
do the comparison: the bar reads empty below N and full at or above it. Any
"is this number past that number" question can be asked this way, and the
answer comes back as geometry rather than as a boolean.

Two consequences that are easy to get wrong:

1. **With several thresholds crossed, every overlay is full at once**, so
   "highest wins" cannot be an `if` — there is nothing readable to branch on.
   It is DRAW ORDER: overlay *i* is parented to overlay *i-1* (a child always
   renders above its parent) and the list is sorted ascending, so the highest
   crossed one paints last. `Bars:StackThresholds` sorts for that reason, and
   the self test guards it — an unsorted list does not throw, it just looks
   slightly wrong.
2. **The overlay anchors to the fill's TEXTURE**, not to the fill frame, so it
   recolours only the filled part and the bar keeps its length from the clock.
   `SetStatusBarTexture` replaces the texture object, so it must be re-anchored
   after every texture change.

The count itself comes from `CDM:ItemStacks` — `item.auraDataCached.applications`
first because it reads without erroring on every client, then the
aura-instance query as a fallback, guarded by `ns.CanCompute` on the instance
ID because that call hard-errors on restricted units
(`EllesmereUICdmBuffBars.lua:3259`). `nil` means unknowable and the renderer
holds its last state rather than reporting zero, which would flash the bar
back to its base colour.

Not built: their tick marks, `stackBasedBar` (fill length driven by stacks
rather than time), and multi-band editing beyond three fixed rows.

### Active for — where it lives, and the one trap in it

`ns.account.activeStates[spellID] = seconds`, account-wide beside the procs
for the same reason: how long a trinket lasts is a fact about the trinket.

The trigger is `UNIT_SPELLCAST_SUCCEEDED`, which `Core/Auras.lua` already
listened to for the proc recorder — the press IS the event, because there is
no aura to watch and on this patch none may be read.

**THE OVERLAY IS DRAWN BY THE RENDER PASS, NOT BY THE TRIGGER.** This was the
second attempt. The first built and styled the overlay inside
`StartCustomActive`, and it was wrong twice over: `PaintCell`'s adopt branch
ends with `cell.aura:Hide()` on every pass, so the next render — and there are
many — wiped the window; and it duplicated the geometry the render pass
already does, which is how two renderers drift apart. Now the trigger only
records `cell.customEnds` and asks for one repaint, and the adopt branch draws
the overlay when the window is live. One renderer.

Blizzard's frame is untouched throughout — the overlay is raised by frame
level, never by hiding or fading the adopted icon
(`EllesmereUICdmFakeActive.lua:6-9`). If the addon is unloaded mid-window,
what is left behind is Blizzard's display exactly as it was.

The window is closed by the fill's own `OnUpdate`, because nothing else knows:
there is no event at the end of a number somebody typed.

Not built: their per-spell right-click menu, per-state glow styling, and the
12.1 engine-slot driver that reads a real aura's remaining time for the
built-in rules.

### The refresh window is ASKED, not calculated — 4.15.0

The third piece of the same lesson as the stack colours, and the strongest
form of it: **when the arithmetic is forbidden, find who already did it.**

Pandemic is "remaining <= 0.3 * duration". Both numbers can be secret on this
patch, and dividing one secret by another is precisely the taint everything
here is built to avoid. There is no clever way to do that division.

Blizzard's Cooldown Manager marks the window itself, through two methods on
the item frame: **`ShowPandemicStateFrame` / `HidePandemicStateFrame`**.
`CDM:HookPandemic` hooks both and keeps a weak-keyed frame -> boolean;
`CDM:InPandemic` reads it. No arithmetic anywhere
(`EllesmereUICdmBuffBars.lua:81-128`).

Three things worth keeping in mind:

1. **It depends on a BLIZZARD setting.** The methods only fire for auras the
   user has pandemic alerts enabled for, in Blizzard's own options. Nothing we
   can do about it, so the panel says so rather than leaving "I switched it on
   and nothing happens" unanswerable.
2. **The hook bodies are at FILE SCOPE, deliberately.** A `hooksecurefunc`
   callback is billed to the addon whose execution context created the
   closure, so a body built inside a render pass can bill ANOTHER addon for
   every one of our repaints. The reference found this by bisection and says
   so at its own hook site.
3. **Hooked per claimed frame, not per live frame.** Idempotent, so calling it
   every render pass costs one table read, and it is bounded by the number of
   cells rather than by everything the game tracks.

Their Lifebloom fallback — for auras Blizzard never flags — was NOT copied. It
reads `duration`/`expirationTime` off a named aura scan with a secret guard
that bails out, so it is a special case for one druid spell that degrades to
nothing on exactly the content where it matters.

Not built: their five glow styles, glow speed, thickness, line count and the
"Blizzard Default" pass-through that leaves Blizzard's own marker showing.

### The 12.1 aura engine: what today's reading ADDS to `Core/Engine.lua`

`Core/Engine.lua` is parked and its contract is already correct — it was
written against these files and points 1, 2, 4 and 5 of its header match
`EllesmereUI_AuraKit.lua` exactly. Do not rewrite it. These are the gaps:

1. **A container must be SHOWN to be processed.** The engine parses auras from
   a run-when-visible OnUpdate. `EllesmereUICdmTbbDecimals.lua:258` hosts its
   container on a 1px frame that is *shown at alpha 0* — never hidden. This is
   the SAME rule as the buff-bar park finding above: in this system **hidden
   means no data**, everywhere. Alpha is the only safe off switch.
2. **Unanchored is a silent death.** `spec.point` is required; an unanchored
   container "builds, binds slots, and then never processes a single aura"
   (`:310-313`). Ours anchors already — keep it, and now we know why.
3. **A hidden one-slot container is a legal DATA SOURCE for text.** This is
   the technique we do not have: declare a slot filtered to the spell
   (`candidateFilters = { includeSpellIDs = {...} }`), create a FontString
   *inside* the button, hand it to `SetDurationText`, and then **copy its
   string out** to our own bar's timer each tick. That renders the countdown
   of an aura nobody may read — including decimals — without ever touching a
   secret. `EllesmereUICdmTbbDecimals.lua:280-306`.
4. **Two slots must never claim the same spell ID.** Spell families share one
   `cooldownInfo` (ritual + art chains list each other in `linkedSpellIDs`),
   and family-wide filters on two bars made the engine bind the live aura to
   whichever slot it liked — **the losing bar showed nothing at all**. Their
   fix is a two-pass claim: saved identity claims its ids first, enrichment
   only fills unclaimed ones (`:204-253`). Our `VariantFamily` expansion has
   exactly this failure mode waiting for it.
5. **`AddAuraGroup` costs ~4-6ms each** — it eagerly builds a 10-button batch.
   Monolithic builds spike proportionally to group count, which is why they
   split shell/add/finish and drain it through an 8ms-budgeted queue
   (`EllesmereUI_AuraKit.lua:866-872`, `:963`).
6. **Creating a container in combat is legal since build 68914.** Any
   in-combat guard written before that is now costing us a rebuild.
7. **`updateInterval` is a binding-level knob** since the 68914 schema:
   `BuildDurationTextOpts(formatter, colorCurve, 0.05)`, not a container one.

### What they have that we do not

Their per-bar vocabulary, from `DEFAULTS` at `:527` and the `cfg.` inventory of
the buff-bars file. Ranked by what it is worth to a Blood tank:

1. **Stack thresholds** — the bar changes colour past N stacks. That is Bone
   Shield, and it is the single biggest win available.
2. **Pandemic glow** — glows while the buff is inside its refresh window.
   Mode, colour, thickness, style, speed, background.
3. **Charge hash lines** — separators across the fill, one per charge.
4. **Keybind text on an icon**, with size, offset, alignment and colour.
5. Spark, gradient fills, vertical orientation, decimals below N seconds,
   custom duration, per-bar background (behind the whole bar, not per icon),
   custom icon shapes, tooltip on hover, five glow types including a
   resource-aware one, suppress GCD.

Their visibility conditions we lack: **hide while mounted**, **hide with no
enemy target**, instances-only, and a housing rule.

### Structural differences, stated so they are not mistaken for bugs

- **They REPLACE Blizzard's icon bars; we adopt them.** Their `cdmBars` block
  is commented "our replacement for Blizzard CDM" with `hideBlizzard = true`.
  Ours is deliberate and still correct for icons — the frame IS the art there
  — but it is a different architecture, not a lesser version of theirs.
- **They keep per-spec PROFILES** (`spec = {}`, `activeSpecKey`,
  "Per-Spec Profile Helpers" at `:1678`). We key per character and split the
  spells per spec inside that, which is the owner's rule.

### Not read yet

`EUI_CooldownManager_Options.lua` (19 764 lines — the labels are inventoried,
the code behind them is not), `EllesmereUICdmSpellPicker.lua` (2 034 —
relevant to the sorting the owner reported), `EllesmereUICdmFakeActive.lua`
(1 530 — how they preview a bar that is not active), and
`EllesmereUICooldownManager.lua` beyond the sections named above.

## Why it looks weaker than it should

Three reasons, and only the third is fixable by trying harder.

1. **There is no layout engine.** No flex, no grid, no auto-height. Margin
   collapsing had to be implemented by hand in `Grid:Layout` this session.
2. **The primitives are poor.** Colour rectangles, textures, font strings,
   masks. No radii, no shadows, no blur. Everything modern-looking has to
   arrive as an image file.
3. **It cannot be seen from here.** Every visual judgement this session came
   out of the owner's screenshots. That is why the spacing was wrong: not a
   skill gap, a feedback gap.

The agreed way out, in the order agreed with the owner:

- **Ship art instead of drawing rectangles.** Verified this session:
  EllesmereUI's border files are all **256x32** — WoW's nine-slice strip,
  eight 32x32 tiles in a row — and `edgeSize` values in the wild are 1, 8, 10,
  12, 14, 16, 32. So real rounded corners with soft shadows ARE deliverable as
  generated TGA, and they plug straight into the border texture picker that
  already exists. This is the honest answer to the owner's border-radius
  request: art, not a slider, because WoW has no radius property.
- **A token layer** (`Core/Design.lua`): the window currently uses seven font
  sizes and a dozen hand-picked spacings, every one of them guessed
  individually.
- **A specimen sheet**, as a PNG that can be looked at from here and a
  `/zs design` page in game.
- **`LibZSLayout-1.0`** as a standalone LibStub library other addons could
  use — the box model, stacks, grid, content sizing and dirty-marking that
  WoW lacks. Written twice by hand already (`Grid` in Widgets, `Core/Layout`
  for the bars), so extracting it is tidying rather than inventing.

**Owner's decision on sequencing (2026-08-07):** *"also das layout system
machen wir mal wenn wir bock haben, erstmal fixen wir das addon, das hat 1000
bugs"*. So: bug-fixing first, design system when it is wanted, library after
that.

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
| `Core/MediaLibrary.lua` | the twenty bar textures this addon ships, into LibSharedMedia |
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

- **A comment asserting the data is not there is a claim, not a fact.** Our
  live pass carried "a frame pool is not a sorted list" as its reason for
  supplying no order — and every one of those frames had a `layoutIndex` on
  it the whole time. The wrong list the owner reported was a comment nobody
  re-checked. Verify the negative before you build a fallback around it.
- **A sort key that becomes absolute invalidates every sentinel.** Banding the
  order by viewer (`rank * 10000`) turned the old `or 9999` "unordered" marker
  into a value INSIDE the first band. Grep the sentinel when the scale of a
  key changes; `math.huge` is the only one that survives a rescale.
- **One line can carry three bugs.** `info.overrideSpellID or info.spellID`
  was stale-override, ignored-frame and secret-fallthrough at once. When a
  reference addon wraps a one-liner in 200 lines, the 200 lines are the
  requirements — read them before deciding it is over-engineering.
- **One field with two meanings is a bug waiting for a switch.** A cell's
  `x/y` meant "position" in one arrangement and "offset from a slot" in every
  other, so changing arrangement silently reinterpreted the number. It looked
  economical and it cost a whole class of defect. If two things are measured
  from different origins, give them different fields — the storage is free and
  the confusion is not.
- **A setting that can DELETE work has to be reversible.** The Columns slider
  dropped every spell that no longer had a cell. People drag a slider to see
  what it does; that must never be the destructive path. Park it, do not
  delete it.
- **Reset per-cell state wherever a cell can change what it holds.** Frames are
  pooled and reused by index, so an aura clock and an effect state machine
  outlive the spell they were about. A stale flag shows up as a phantom flash
  or an icon that arrives already lit.
- **Write the test by breaking the code again.** The self test was validated by
  reverting the fixes in a scratch copy of `Core/` and confirming it went from
  48/0 to 40/8. A test that has only ever been seen green proves nothing about
  what it would catch.
- **Read the API before calling it, including your own.** `UI.Dropdown` takes
  its option list as a table OR A FUNCTION with `cfg.emptyText`; an `items`
  and `placeholder` pair was invented from memory and would have shipped a
  dead control. The rule about not guessing WoW APIs applies to this codebase
  too — it is 15 000 lines and nobody remembers it exactly.
- **`.luarc.json` uses FLAT dotted keys.** Adding a nested `diagnostics`
  object beside `"diagnostics.globals"` silently replaced the setting, dropped
  sixty declared globals and turned four added names into 405 warnings.
- **A per-item chat print is a wall of text on somebody else's character.**
  The proc recorder announced every new discovery on its own line; the first
  fight on a fresh alt read as "sooo viele tracking fehler". Collect and say
  it once.
- **The language server ships a Lua runtime.**
  `lua-language-server.exe -E script.lua` runs plain Lua 5.5. With a stub for
  `CreateFrame` and a handful of globals, the whole model layer — Layout, Bars,
  Visibility, Effects — runs and the self test can be executed on the desktop
  before anybody logs in. The harness is a throwaway; the technique is not.
- **Generated files land where the SHELL is, not where the repo is.** Twenty
  bar textures were written one directory above the repo and the commit that
  announced them contained none of them — the addon registered twenty names
  pointing at nothing. `cd` into the repo in the same command, and check that
  a generated file is actually in the commit before saying it shipped.
- **A TGA the client will load is uncompressed, 32-bit, bottom-up origin, and
  power-of-two.** A top-down origin or RLE compression is the usual reason a
  texture comes out blank with no error at all. Read bytes 2, 16 and 17 of the
  header rather than trusting the writer.
- **Lua does not accept `\A` as an escape.** The icon path went into
  `Init.lua` with single backslashes through a Python rewrite; the whole file
  would have failed to parse at login. Any path written by a script needs its
  backslashes doubled for Lua AND for the script's own string rules.
- **`and` truncates multiple return values.** `local x, y, w, h = target and
  SlotRect(target)` keeps only x. Use an `if`.
- **`SetPropagateKeyboardInput` is protected in combat.** There is no way
  around it; guard the call and give up the feature for the duration.

### Older, and still true


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
basics.

1. **PARK THE BUFF-BAR VIEWER, or confirm it is not needed.** The first
   finding out of the reference (see *Taking the reference apart*) predicts a
   bug in what shipped in 4.9.0: alpha 0 does not hold on that viewer, because
   Blizzard animates it back to 1 on the next proc, so its bars can draw over
   ours in combat. **Ask the owner first** — do Blizzard's buff bars reappear
   during a fight? If yes, build the park exactly as written up there: position
   not Hide, three hooks, a one-frame defer, alpha-only in combat, and a 10 Hz
   integrity check with a tolerant compare. The same section explains why a
   HIDDEN viewer would freeze our mirror rather than empty it — that half needs
   handling either way.

2. **CARRY ON TAKING THE REFERENCE APART.** The owner's instruction, and the
   reasoning is proven: every time this session stopped guessing and read
   `C:\Games\World of Warcraft\_retail_\Interface\AddOns\EllesmereUICooldownManager\`
   it produced a better answer than anything reasoned from first principles.
   It settled the bar architecture (4.9.0), the fill semantics (4.9.0) and the
   park finding above.

   What is already known, so it is not re-derived:

   | file | lines | what it holds |
   |---|---|---|
   | `EllesmereUICdmBuffBars.lua` | 5734 | tracking bars. `:4649` mirror, `:4725` IsActive-not-IsShown, `:3407` the 2nd FontString is the timer, `:4088` `SetTimerDuration` + `StatusBarTimerDirection.ElapsedTime`, `:3635` + `:4807` smooth fill via `SetValue(v, Enum.StatusBarInterpolation.ExponentialEaseOut)`, `:2322` spark anchoring, `:2471` `SetReverseFill` |
   | `EllesmereUICdmHooks.lua` | 9009 | the icon side and the taint rules |
   | `EllesmereUICooldownManager.lua` | 9701 | the viewers. READ: structure, `:527` defaults, `:3303` hide/restore + the park. Unread: `:3041` forcing Blizzard's Edit Mode settings, `:3815` building a bar, `:4369` icon layout, `:5183` custom icon shapes, `:7230` the tick hot path |
   | `EUI_CooldownManager_Options.lua` | 19764 | their options page. Labels extracted; the code behind them **not read** |
   | `EllesmereUICdmSpellPicker.lua` | 2034 | **READ, and it paid for itself** — `:40` secret-safe ID test, `:51`/`:58` base + override, `:80` variant store (exact overwrites, derived fill gaps), `:131` the clean-SID-per-cooldownID cache, `:163` the five-step canonical resolve, `:244` order from `layoutIndex` + a 10000 band per viewer, `:453` the settings data provider (respects the user arrangement, drops Hidden), `:512` the picker list itself |
   | `EllesmereUICdmFakeActive.lua` | 1530 | how they preview a bar that is not active |

   Their per-bar setting vocabulary is already inventoried (grep `cfg%.`
   in the buff-bars file). What we do NOT have and they do:
   **stack thresholds** (bar changes colour past N stacks — that is Bone
   Shield, and the single biggest win for a Blood tank), **pandemic glow**,
   **charge hash lines**, **spark**, **gradient fills**, **vertical bars**,
   **five glow types** including a resource-aware one, **decimals below N
   seconds**, **suppress GCD**, **custom duration**, **per-spec bar sets**.

   The spell picker is DONE and produced 4.12.0 — see *What the spell picker
   said* below. The settings sweep is DONE — see *The settings, taken apart*.
   `EllesmereUICdmFakeActive.lua` turned out NOT to be a preview engine: it is
   **custom active states**, a user-defined "this is active for N seconds
   after I press it" for trinkets, potions and racials that Blizzard's CDM
   never reports as buffs. Nothing here can do that, and it is on the
   candidate list. Still unread: the bodies behind
   `EUI_CooldownManager_Options.lua` (19764 lines; the labels and the
   structure are extracted, the code is not) and the five marked sections of
   `EllesmereUICooldownManager.lua`.

3. **Smooth fill for the mirror**, already found and not yet built:
   `SetValue(value, Enum.StatusBarInterpolation.ExponentialEaseOut)`. The
   mirror in `Screen.RefreshFill` sets raw values every frame, so it steps
   where it could glide. One argument.

4. **Bug hunt, continued.** 4.7.0–4.11.1 swept `Layout`, `Bars`, `Screen`,
   `Effects`, `Visibility`, `CDM`, `Media`, `Minimap` and the parts of
   `Widgets`/`OptionsBars`/`EditMode` those touch. **Not yet swept:**
   `Auras.lua`, `Options.lua`, and the rest of `EditMode.lua` (the palette and
   the tool panel). Extend `/zs test` with every rule that turns out to be
   checkable — a fix without a check comes back.
5. **"The background shows through the circle"** — reported with a screenshot,
   diagnosis deliberately NOT guessed. `/zs skin` now reports which template a
   frame came from and walks its child frames; ask for that output rather than
   reasoning about it. Guessing here cost a day once already.
6. **Owner-side data**: confirm the remaining proc durations by letting one run
   out *without* casting the ability, then `/zs auras export` for Blood and
   paste it into `Core/KnownProcs.lua`. Then Frost and Unholy.
7. **A better logo.** The owner does not like the current one and is going to
   ask Claude Design. Bring back a PNG or SVG; converting it to a game-ready
   TGA is a two-minute job (see `Media/`, and the header rules under
   *Verification*).
8. **Tank ideas** — the owner has a list, held back until the basics stand.
9. After 12.1 lands: un-park the aura stack and re-test it.

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
