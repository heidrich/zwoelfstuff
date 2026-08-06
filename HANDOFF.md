# ZwoelfStuff — Handoff

State as of **2026-08-06**, version **4.5.0**. Read this first.

## Where we are

The addon is built around Blizzard's Cooldown Manager. The previous approach —
tracking auras directly — cannot work on this client, and establishing that
took most of a session. Do not restart it.

The window is an app in three fixed columns, and what you arrange in it now
**renders on screen**, with an unlock mode to place it. Written, statically
clean, **not yet run in the game** — the client was open the whole time it was
built, so nothing here has been seen working.

The addon was renamed from `DKstuff` to **ZwoelfStuff** in this session: repo
folder, TOC, saved-variables key, slash command (`/zs`), junction, and the
saved-variables file on disk. See *Open, in order* for the one step that is
still owed.

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

## Unlock mode

`Core/EditMode.lua`, modelled on EllesmereUI's because that is what this addon
is used next to. Panel per bar with live coordinates, drag or arrow keys
(Shift = 10), snapping to the screen centre and other bars' centres and edges
with a guide line, Alt to suspend snapping, a cog menu, Shift + Right Click to
hide the overlay, a grid, Escape to leave.

**Positions are always centre-relative** — `point`/`relPoint` are forced to
`CENTER` and `x`/`y` are the offset from the screen centre. That is what makes
the readout meaningful and snapping arithmetic rather than a case analysis.

Two traps already paid for here: `OnMouseUp` only fires on the frame the
button went down on (so `OnUpdate` also checks `IsMouseButtonDown`), and
anything reading `ns.UI` at file scope must load **after** `Core/Widgets.lua`.

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
| `Core/Bars.lua` | the bar data model — grids of cells |
| `Core/Glow.lua` | self-built proc glow, no external library |
| `Core/Minimap.lua` | self-built minimap button |
| `Core/Widgets.lua` | the design system — every control, one look |
| `Core/Screen.lua` | the bars on screen — adopted CDM frames, drawn aura cells |
| `Core/EditMode.lua` | unlock mode — movers, snapping, guides, the cog menu |
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


1. **The icons on screen are still wrong, and the next step is measurement,
   not another guess.** `/zs skin` now prints every pinned icon as *asked for
   vs actually there* — size and anchor, with the mismatch spelled out. Run it
   and read that first. What is already known from running it:
   - `UI-CooldownManager-OORshadow` sat at alpha 0.5 on a self-cast spell.
     Stripped by atlas prefix now, and the alpha is **hooked**, because it is
     driven by range and Blizzard writes it back when you move.
   - The mask was back to Blizzard's rounded `130871` after a one-time strip.
     These frames come out of a pool and are re-decorated when handed out, so
     stripping runs on **every** skin pass now.
   - Sizing the item FRAME is not enough: each viewer anchors its own icon
     texture its own way. `item.Icon` and `item.Cooldown` are told to fill the
     frame on every pass. **This is the fix that has not been seen working
     yet.** If the icons are still uneven after it, `/zs skin` will say
     whether the frames themselves are wrong (somebody is overwriting us) or
     only the art inside them (anchoring, again).
2. **The owner's design notes on the window**, not yet done: it still reads
   "altbacken", too much wasted space. The rail is 168 and the settings column
   400 now, window 1360x760 — that was the width complaint, not the density
   one. Row height, section spacing and the card padding are untouched.
3. **Owner-side data**: confirm the remaining proc durations by letting one
   run out *without* casting the ability, then `/zs auras export` for Blood
   and paste it into `Core/KnownProcs.lua`. Then Frost and Unholy.
4. **Tank ideas** — the owner has a list and asked to keep them until the
   basics are done. `Core/CoTanks.lua` is written and parked; it returns with
   12.1 on 11 Aug.
5. **Logo** — SVG for the repo, TGA for the game. WoW cannot load SVG. PIL is
   installed, no rasteriser. Interim: `## IconTexture: 1380870`.
6. After 12.1 lands: un-park the aura stack and re-test it.

Everything is committed and pushed to `github.com/heidrich/zwoelfstuff`.

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
