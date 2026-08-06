# DKstuff — Handoff

State as of **2026-08-06**, version **4.0.0**. Read this first.

## Where we are

The addon was rebuilt around Blizzard's Cooldown Manager. The previous
approach — tracking auras directly — could not work on this client, and that
took most of a session to establish. Do not restart it.

The window was then reshaped into an app: a rail of the owner's bars, the bar
itself in the middle, an inspector on the right for whatever is selected. The
owner has seen it and it is **not accepted yet**.

## THE ONE OPEN TASK: make the window look modern

Owner verdict on the current window, with a side-by-side against EllesmereUI:

> *"sieht so aus, sehr altbacken, viel wasted space, ggf denken leute das ist
> nicht zugehörig. versuch es etwas moderner"*

And the standing requirement behind it:

> *"wir sollten das logisch mit sehr guten ui design angehen. wenn leute es
> nicht nutzen können oder verstehen, verschwenden wir nur arbeit"*

**Do not treat this as polish.** It is the current blocking task, ahead of
rendering and ahead of spells. The agreed order is the owner's:
**UI base → the on-screen display → the spells.**

### What is concretely wrong, read off the screenshot

1. **A vast empty black stage.** The cell grid floats in a ~1000x400 black
   box and occupies maybe a fifth of it. This is the single worst offender.
2. **No header treatment.** EllesmereUI gives every module a title, a
   subtitle, an accent sweep and a tab strip. The bar workspace has a bare
   "Cooldowns" and nothing else, so it reads as unfinished.
3. **The inspector is a small floating card** pinned to the top right with a
   large void beneath it, instead of a full-height column that belongs to the
   window.
4. **The rename box is an unlabelled empty rectangle** next to the title. It
   looks broken rather than optional.
5. **Everything is flat black.** No layered surfaces, no separation between
   chrome and content, nothing that reads as depth.
6. **The rail is text-only** and mostly empty; five entries in a 640px column.
7. **The window is 1060x640 for roughly a quarter of that in content.** Either
   fill it or shrink it.

### The reference

`EllesmereUICooldownManager` — the owner's own screenshots are the brief.
Look at the real thing rather than guessing: distinct surface levels, a
header band, tabs, two-column setting rows that fill the width, icons in the
rail, and controls that sit on panels rather than on the window background.

**Do not copy its colours** (teal/green is theirs). DKstuff is orange
`#FF7A3D` with a cyan `#7EC6D4` accent, already in `UI.C`.

## Next action after that

The editor's *operation* still has not been signed off either — nothing
renders on screen yet, on purpose. Rendering is built only once the owner
accepts both the look and the operation.

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
| `Core/Bars.lua` | the bar data model — grids of cells |
| `Core/Glow.lua` | self-built proc glow, no external library |
| `Core/Display.lua` | the single-aura display (proc-glow route) |
| `Core/Watcher.lua` | the five lookup routes + diagnostics |
| `Core/Minimap.lua` | self-built minimap button |
| `Core/Widgets.lua` | the design system — every control, one look |
| `Core/Changelog.lua` | changelog data |
| `Core/OptionsBars.lua` | the bar workspace: canvas, inspector, spell picker |
| `Core/Options.lua` | the app window: rail, middle, inspector host |

### What `Core/Widgets.lua` already provides

Do not hand-roll any of these again — they exist and are consistent:

`UI.C` (colour tokens) · `UI.Label` / `UI.Hint` · `UI.Button` (with a
`"primary"` style) · `UI.Row` (a card row with a right-aligned control slot)
· `UI.SectionHeader` (optionally a disclosure) · `UI.Toggle` (switch) ·
`UI.Slider` (track + numeric box + wheel) · `UI.Counter` (− n +) ·
`UI.Dropdown` / `UI.Picker` / `UI.MenuButton` (one shared popup, with
per-entry delete and trailing actions) · `UI.Swatch` (colour picker) ·
`UI.Input` · `UI.ScrollArea` (**our own** thin scrollbar — never use
`UIPanelScrollFrameTemplate`, its pale bar cannot be styled to match) ·
`UI.CellGrid` (the editable bar grid: click, drag to swap, right click to
clear, selection ring) · `UI.Page` → a `Grid` with `Section(title, key)`
(collapsible), `Row`, `FullRow`, `Note`, `Wide`, `Layout`, `Refresh`.

Two font helpers, and they are not interchangeable: `ns.StyleUIFont` for
panel text, `ns.StyleFont` (the number font) only for digits drawn on icons.

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

Two things that are easy to get wrong:

- **The frame pool is the ground truth**, not the category API.
  `GetCooldownViewerCategorySet` says where a cooldown *belongs*; Edit Mode
  and per-spec layouts move it somewhere else, and the viewer the frame is
  actually in is what the user sees.
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

`/dks cdm`, 2026-08-06:

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
- **Verify the foundation before building on it.** `/dks cdm` exists precisely
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
- Goal, in the owner's words: **own bars, the owner picks the spells.**
  Blizzard's CDM is the data source behind it, nothing more.

## Open, in order

1. **Make the window look modern.** The blocking task — see the section near
   the top for the owner's verdict and the seven concrete faults.
2. **Owner signs off the operation** of the bar editor.
3. **Render the bars on screen** — adopt the CDM item frames into the cells,
   skin them, position them, make the bar movable.
4. **Logo** — SVG for the repo, TGA for the game. WoW cannot load SVG. PIL is
   installed, no rasteriser. Interim: `## IconTexture: 1380870`.
5. After 12.1 lands: un-park the aura stack and re-test it.

Already done, do not redo: the UI font is wired, the scrollbar is ours,
sections collapse, rows and columns use counters rather than sliders, and the
selected cell has a ring.

## Verification

No Lua interpreter is installed. Use the language server from the VS Code
extension:

```powershell
& "$env:USERPROFILE\.vscode\extensions\sumneko.lua-3.18.2-win32-x64\server\bin\lua-language-server.exe" `
    --check "C:\Users\Christian\Documents\GitHub\DKstuff" --checklevel=Warning --logpath="$env:TEMP\llscheck"
```

Green means syntactically and globally clean. It does **not** mean it runs —
it cannot see the type behind `ns.CreateBorder(...)`, and every bug that cost
time this session passed this check.

WoW API globals must be listed in `.luarc.json` under `diagnostics.globals`.

## Install

```text
C:\Users\Christian\Documents\GitHub\DKstuff                    <- edit here
C:\Games\World of Warcraft\_retail_\Interface\AddOns\DKstuff   <- NTFS junction
```

`/reload` picks up edits. **A file added to or removed from the TOC needs a
full client restart.** The junction was made with `cmd /c mklink /J` —
`New-Item -ItemType SymbolicLink` needs elevation, a junction does not.
