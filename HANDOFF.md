# DKstuff — Handoff

State as of **2026-08-06**, version **4.0.0**. Read this first.

## Where we are

The addon was rebuilt around Blizzard's Cooldown Manager. The previous
approach — tracking auras directly — could not work on this client, and that
took most of a session to establish. Do not restart it.

**Next action: the owner tests the bar editor** (`/dks` → Bars) and says what
is wrong with the *operation*. Nothing renders on screen yet, on purpose. The
rendering is built only after the editor is signed off.

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
| `Core/OptionsBars.lua` | the bar editor + spell picker |
| `Core/Options.lua` | the settings window |

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

1. **Owner tests the editor.** Fix what is wrong with the operation.
2. **Render the bars on screen** — adopt the CDM item frames into the cells,
   skin them, position them, make the bar movable.
3. **UI debts still outstanding**: Blizzard's scrollbars clash inside a custom
   panel; `ns.StyleUIFont` exists but nothing uses it yet (panel text still
   uses the *number* font, which is wrong for body text); no row hover; the
   sliders are narrow; no icons in the sidebar.
4. **Logo** — SVG for the repo, TGA for the game. WoW cannot load SVG. PIL is
   installed, no rasteriser. Interim: `## IconTexture: 1380870`.
5. After 12.1 lands: un-park the aura stack and re-test it.

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
