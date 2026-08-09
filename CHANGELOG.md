# Changelog

All notable changes to ZwoelfStuff are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.58.2] - 2026-08-09

### Fixed

- **The "Who to ask" boxes were blank.** `UI.Dropdown` hangs its own `Refresh`
  on the row it is given, and the page replaced that hook afterwards instead
  of calling it - so the control never repainted, and the words that say what
  happens when you leave it alone ("The healer of that class") were never
  drawn. Two things wanting one hook: the second has to call the first.

## [4.58.1] - 2026-08-09

### Fixed

- **The externals panel never appeared in Edit Mode.** `ShouldShow` read
  `ns.EditMode.unlocked`, which is a FILE-LOCAL in that module and therefore
  always nil - so the panel stayed hidden while placing and its mover had
  nothing to sit on. Edit Mode calls `Externals:SetPlacing` now, the same door
  the co-tank panel and the reminders are already opened through.
- **Every picked slot is drawn while placing.** The panel hides a slot nobody
  present can fill, and the group you are standing in while arranging it is
  usually nobody at all - so there was nothing on screen to put anywhere.

### Changed

- **The list of externals no longer cares who is in your group.** Owner: "man
  sollte auch ohne das die klassen in der gruppe sind sich sein set
  zusammenstellen koennen". A set is built once, for the dungeons you run all
  week; a list that greys itself out because you are standing alone can only
  be used at the moment you have no time for it. The trailing text is the
  spell's cooldown now - a fact about the spell - and WHO can cast it stays
  where the names are, under "Who to ask".

## [4.58.0] - 2026-08-09

### Added

- **External cooldowns - a fifth module.** The cooldowns somebody ELSE presses
  on you: fourteen spells, cross-checked against Method Raid Tools' own
  `DEFTAR` set ("defensive on a target"), which is the same idea under another
  name. Pick some, arrange them into a panel, place it in Edit Mode, and a
  click whispers whoever in the group can cast it.
- **Who a click asks**, in the owner's words: "in 5 mann dungeons werden
  heiler der klasse angewispert. im raid sollte man das zuweisen koennen." So
  an assignment wins whenever one exists, and with none it is the healer of
  that class - which in a five-man is the only person who has it. An
  assignment to somebody who has left the group falls back to the rule and
  the tooltip says which of the two answered.
- **A slot nobody can fill is not drawn.** The owner's choice: with no
  paladin in the group there is no Blessing of Sacrifice icon on your screen.
  The page's list says "nobody here" beside it so the absence has an
  explanation.
- `/zs externals` prints who each slot would whisper. `/zs externals test`
  shows the panel with nobody around.

### Changed

- **This is deliberately NOT a cooldown tracker**, and that is the whole
  design. MRT shows other people's cooldowns by reading
  `COMBAT_LOG_EVENT_UNFILTERED` - checked in its own `ExCD2.lua`. That log is
  closed to addons on 12.0, and since 12.0.5 another player's INSTANT cast is
  not announced at all. Every one of these spells is instant. "Ironbark, ready
  in 1:12" is a number this addon cannot know, and it would be believed in the
  one moment it matters.
- The welcome window's generation moved to 2, so everybody who has already
  answered is asked once more - about this one entry, marked NEW, and nothing
  else. That is what it was built for.

## [4.57.2] - 2026-08-09

### Added

- **Drag the replay's plot to move along it when zoomed in.** The wheel
  already scrolled it; the hand is the gesture people reach for. The pane
  does BOTH rather than stealing one - at zoom 1, where there is nothing to
  pan to, grabbing the plot still moves the window, which is what it did
  before. It sits at the parent's own frame level, so it is UNDER every mark
  and the icons keep their tooltips.

## [4.57.1] - 2026-08-09

### Fixed

- **The bag scan recognised nothing, ever.** `GetItemInfoInstant` answers the
  class id as its SIXTH return; the code discarded four values after pcall's
  `ok` and took the fifth, which is the ICON - so a texture file id was
  compared against 0 and every potion in the bags was thrown away. Owner:
  "der erkennt die silvermoon health potion nicht". It is `select(6, ...)`
  now, which is how every installed addon writes it and the version that
  cannot be miscounted.
- **You could not type in a search field.** An EditBox built from Lua has no
  mouse: Blizzard's `InputBoxTemplate` enables it in XML, and every addon that
  builds one without the template turns it on by hand - AceGUI's
  MultiLineEditBox, its slider box, BugSack's. Ours did neither, so the field
  drew, showed its placeholder and could never be given focus by the only
  gesture anybody tries. Menus with a filter now open with the box already
  focused, which is what their own footer has been promising, and the keyboard
  is handed back when the menu closes.

### Added

- **Drag an item out of your bags onto a consumable slot.** The owner asked
  for it and it is the gesture the game's own action bars use. Both doors are
  wired, because the client offers two: releasing a drag, and clicking a slot
  while carrying something. This path reads the id off the CURSOR, so it does
  not depend on the bag scan seeing the item at all.

### Changed

- The desktop harness has bags now. It had none, so the consumable code
  returned at its first guard and every test of it was vacuous - which is
  exactly how the class-id bug shipped. Its fixture holds a healthstone, a
  potion, a sword and a hearthstone: the last two have use effects and are not
  consumables, so a filter reading the wrong field is caught by the fixture
  rather than by the owner.

## [4.57.0] - 2026-08-09

### Changed

- **The event list in the death window scrolls, and it no longer drops hits.**
  The rows were placed at absolute offsets inside a window of fixed height,
  with a hard cap of twelve to stop them running off the bottom - so the
  deaths with the most to say were the ones losing rows. The list has an AREA
  now: its top follows the verdict, its bottom sits on the footer, and what
  does not fit is scrolled to. It opens at the BOTTOM, because the row that
  matters is the last one.
- **The footer no longer draws across the last hit.** Same fault, other half:
  with a four-line verdict and ten hits, "What you had, by our own clock" was
  printed straight over the killing blow. The list's bottom is anchored to the
  footer, which grows upward, so neither can be drawn over the other whatever
  either of them contains.
- The rows are POOLED and built when needed rather than twelve up front, and
  they are eight pixels narrower than the column - which is the room the
  scroll rail sits in. Without that the right-hand numbers, which are what the
  table is read for, would be under it.

### Fixed

- **A wheel over a list that cannot scroll is handed back instead of
  swallowed.** `EnableMouseWheel` takes the gesture whether or not there is
  anything to move, and in this window the wheel is how you page between
  deaths - so a death with three hits would have eaten it over the largest
  part of the window. `UI.ScrollArea` now offers `OnIdleWheel` for exactly
  that, and the contract is checked in the self test.

## [4.56.2] - 2026-08-09

### Fixed

- **Every mark in the window was soft, and it was one comparison.** The rule
  that picks which cut of an icon to load asked
  `UIParent:GetEffectiveScale() > 1.25` - a number that is never above 1.25 on
  a real machine, since 1440p sits around 0.53 to 0.75. So the SMALLEST cut
  was loaded on every screen there is: a 22-pixel drawing stretched across 43
  real pixels in a card header, a 14 across 21 in a row. No amount of care in
  the art fixes that; the file was simply too small.

  What decides it is how many physical pixels one interface unit covers -
  `GetPhysicalScreenSize()` over `GetScreenWidth()`, the same ratio
  EllesmereUI computes for the same reason, guard included: that call answers
  0 or nil while the display mode is changing.

  Two facts were measured rather than assumed on the way: the number in a
  file's name is the DRAWING inside it, not the file (`-14` is a 16x16 image),
  and the design's own pairing is 14-into-16 and 28-into-32 - which is exactly
  the slack the chooser now allows, so it never loads a 64x64 texture to draw
  16 pixels.

  `UI.IconCutFor` is pure and tested at eight densities: a rule that is a
  screen measurement cannot be checked by reading it, which is how this
  survived so long.

### Added

- **Diagnostics reports the icon sharpness** - pixels per unit and which two
  cuts that picks. "Sieht matschig aus" is not something a screenshot can
  settle, and now it does not have to.

## [4.56.1] - 2026-08-09

### Fixed

- **The two numbers on an aura icon can be given a font.** They were the only
  text this addon draws with no way to choose its face - and worse, they were
  fonted twice: hard-coded to the shared bar font in the 12.0 renderer and to
  the OPTIONS WINDOW's font in the 12.1 engine path, so the same two numbers
  changed typeface depending on which patch drew them. One picker, one
  outline, both renderers, and the face is part of the container signature so
  picking one takes effect at once.
- **`Visibility:Start()` and the spec-key cache moved out of `Screen:Start()`
  and into the machinery.** Both are shared - a reminder's "only in combat"
  reads the same evaluator, and the spec key is the name the measured cooldown
  lengths and the recorded procs are filed under. Started inside the Cooldowns
  module they would have stopped existing for anybody who switched the bars
  off: reminders on a state nobody sampled, and a death log reading Blood's
  measurements while you played Frost.

## [4.56.0] - 2026-08-09

### Added

- **Four features, four switches.** `Core/Modules.lua` is a registry of what
  this addon actually is - Cooldowns, Co-Tanks, Reminders, Death-log - and
  each one can be off. A module that is off boots NOTHING: no frame, no
  event, no listener. `Boot` runs once and only for a module that is on;
  `Apply` runs on every flip and puts the world in the state the switch says.
  Unregistering was deliberately not the mechanism - Blizzard's callback
  registries here have no way back out, so a module that had truly unhooked
  itself could never be switched on again without a reload.
- **The welcome window**, once per character, and once more when an update
  brings a module that character has never been offered. `Modules.WelcomeDue`
  is the rule and it is pure, so the case that is easy to get wrong is
  tested: a generation bumped with no new module must not open a window in
  anybody's face.
- `/zs modules` lists what is running and switches one by name; `/zs welcome`
  reopens the window. There is a button for it under Settings.

### Changed

- **What is NOT a module**: the Cooldown Manager reader, the profile store,
  the minimap button and the game-menu entry. Switching the bars off must not
  take the spell catalogue with it - a reminder asks it whether a buff is up,
  and the death log builds its defensives out of it.
- **Off means Blizzard gets its icons back.** Every icon on a bar is one of
  Blizzard's own frames; a hidden bar still holds them, so hiding alone would
  have left the Cooldown Manager empty as well. `Screen:ModuleOff` releases
  them, and both callers - the render pass and unlock mode - ask it.
- **A switched-off page stays in the rail, greyed**, with the switch on it.
  One overlay drawn once and moved between pages rather than four copies of
  "this is off", and it swallows the clicks that greying promises it does.
  Its third column goes away with it: a live spell palette beside a greyed
  page would be half a state, and the live half edits settings for something
  that is not running.
- **Edit Mode hides the movers of a module that is not running**, handles
  included - the frames still exist once a module has run at all, so "is
  there a panel" is not the same question as "is this feature on".
- `Reminders:Explain` reports the module switch FIRST. A page explaining at
  length why one reminder is not firing, while the whole module is off, sends
  somebody reading their own trigger for a fault that is not there.

## [4.55.1] - 2026-08-09

### Changed

- **The Sharing row is full width and the buttons have air above them.**
  Half-width put a 150-pixel menu in the middle of the line with its label
  stranded at the far left, and the button strip underneath then read as part
  of that setting. `Grid:Buttons` took a `padTop` for it - pads collapse with
  the neighbour's, so a strip that wants air has to ask for a real amount.

## [4.55.0] - 2026-08-09

### Changed

- **"Deaths" is "Death-log", with a skull in the rail.** `UI.Glyph` grew a
  `RAW_TEXTURES` branch for marks that are the client's own art - one entry,
  and it earns it: the rail's skull is the same picture as the skull on the
  screen, and drawing a second one out of rectangles would be two marks for
  one feature.
- **The defensives are SLOTS, at the top of the page.** `UI.SpellSlot` in a
  grid, so a spell is dragged out of the right-hand list and dropped, and
  right-click clears it - the same gesture the cooldown bars use. The list is
  the only thing on the page that is *work*; the switches under it are set
  once and were standing in front of it. The slots are a VIEW of the picked
  set, sorted by name: a defensive is picked or it is not, and giving it a
  position would be a second thing to keep in step.
- **Consumables use the same slots.** They cannot be dragged in - the spell
  list holds no items - so an empty one opens a menu of what is in your bags.
  `UI.SpellSlot` took two optional hooks for it (`texture`, `tooltip`) rather
  than growing a second slot widget.
- **The settings pair two to a line** (`tooltipNotes = true`, like the bars
  page): every paragraph moved onto its row as a hover explanation. Three
  toggles used to fill a screen and a half with the right half of every line
  empty.

## [4.54.0] - 2026-08-09

### Removed

- **The Timeline module.** `Core/Busters.lua` and `Core/OptionsBusters.lua`
  are gone, with their page, their Edit Mode mover, their slash command and
  their tests. The owner's call: *"wir nehmen timeline als eigenes modul
  raus, das ist ja jetzt im death log drin"*. What the panel drew live was
  the fight's next scheduled hit; the replay answers the same question
  afterwards with everything the panel could never show. The defensives list
  it carried was always read by the death window - it moved, it was not lost.

### Added

- **Consumables are defensives.** `ns.db.rescueItems` is a picked list like
  `ns.db.defensives`, seeded once with healthstone and the two current
  healing potions - `nil` means "never seen", which is not the same as a
  list emptied on purpose, so a potion thrown out stays thrown out.
  - They are judged in **one list with the spells**: an `avail` entry carries
    a `spellID` or an `itemID` and nothing downstream cares which. The old
    shape had a second list for "what was in the bags", so one question had
    two answers on one window. `Death.Analyse` lost its `items` parameter.
  - An item's cooldown is a **fact**, not an estimate: `C_Item.GetItemCooldown`
    is readable on this patch. `Death.ItemReady` returns it; the count comes
    from `C_Item.GetItemCount`, and carrying none is worded as "none" rather
    than as a cooldown.
  - `Death.BagConsumables` offers whatever is in the bags right now with a
    use-spell and class id 0 - not a shipped list of item ids, which goes out
    of date every patch.
  - Drinking one is a cast: `DefensiveSpells()` maps each picked item to its
    spell through `C_Item.GetItemSpell`, so a potion gets a **bar** in the
    replay instead of appearing in the rotation row as an unnamed press.
- **The Deaths page carries the spell list as its third column**
  (`OptionsDeaths:BuildSide`, on the same `BuildSpellPane` the bars and
  reminders use). Click a spell to judge it as a defensive, click again to
  stop. Picking out of a dropdown of forty names was the worst part of it.
- `UI.MakeRowAnItem` - a row with an item's icon and the client's item
  tooltip, the same rule spells already get.

### Fixed

- **`ns.version` was a second, drifting copy of the version number** - it
  said 4.50.0 while the TOC said 4.53.0, and it is what the window shows,
  the About page prints and a shared profile is stamped with. It reads
  `C_AddOns.GetAddOnMetadata` now.

## [4.53.0] - 2026-08-09

### Changed

- **Only picked defensives get bars; the rest of the rotation gets a row of
  its own.** The owner: *"normale spells brauchen eigentlich keinen balken,
  nur def cds die man einstellt. das verwirrt nur."* He is right - a bar
  means "this was up for this long", and a Death Strike has nothing that is
  up, so drawing one off its tooltip's number invented a state that does not
  exist. Non-defensive casts are icons on `LANE_CAST_Y`, directly under the
  axis, each on a hairline reaching up to it.
- **A drop line from the axis to every bar**, standing on the moment it was
  cast, in the bar's own colour: *"auch fehlt so ein mittelstrich zur
  timeline, das man sieht wann die losgehen"*. Only for bars that start
  inside the view - one clamped to the left edge started off screen, and a
  line there would point at a moment that is not under it.
- **The "What you pressed" caption is gone** - *"das sieht jeder"*.
- **`UI.SpellChips`**: a list of spells is now laid out (icon, name, the
  client's own tooltip, flowing and wrapping into rows) instead of written
  into a font string with inline icons. Six inline escapes in a wrapping
  sentence wrap wherever they like and strand a name on the next line
  without its icon, which is exactly what the death window's footer did.
  One implementation, used by that footer and the replay's legend.

## [4.52.0] - 2026-08-09

### Added

- **A fourth source for a bar's length: the spell's own tooltip.** The owner,
  looking at two defensives still drawing as marks: *"viele def cds haben
  FESTE zeiten, die auch so in den tooltips stehen"*. He is right, and this
  is not the rule against guessing - it is the opposite of it. The client
  writes the number in `C_Spell.GetSpellDescription` itself (BigWigs reads
  the same call), so reading it is asking, exactly like asking for a name or
  an icon.
  - `ns.SpellDuration` is tried **last**, after the measured window, the
    number you set and the measured store: a tooltip says what is *supposed*
    to happen - before talents, before haste, before the hit that cut it
    short. `Replay.LengthNote` names the source on hover.
  - **The unit word comes from the client too.** `SECONDS_ABBR` /
    `D_SECONDS` are Blizzard's own formats in whatever language is installed
    (`"%d |4Sekunde:Sekunden;"`), so both forms are extracted and neither was
    typed here. `ns.DurationWords` and `ns.DurationInText` are pure and
    tested against German, English and minutes; the word is escaped before
    it is used as a pattern, because `Sek.` carries a dot and an unescaped
    one matches anything.

## [4.51.2] - 2026-08-09

### Added

- **`/zs death cds`** - why a press has no bar under it. Four causes wear
  that one symptom: the Cooldown Manager is not up, its buff viewers hold
  nothing (so no window can ever be recorded, however long you play), the
  item spell ids are secret, or the death on screen predates the recorder
  and carries no windows. `History:Dump` reports **the switch first and
  then everything else anyway** - a diagnostic that stops at the first
  problem answers one question and leaves three, and on the desktop harness
  it would never exercise its own body.

### Changed

- **"Your casts" is its own line**, not the tail of `No defensive was used -
  you cast …`. A rotation of seven abilities wrapped that sentence over
  three lines and the judgement vanished into the middle of the evidence.
  The cast list is now printed whenever there were casts, including under
  `Defensives used:`.

## [4.51.1] - 2026-08-09

### Changed

- **The availability footer writes only what it knows.** `ready` and
  `25s to go` are answers; "no known cooldown" and "not cast since login"
  are the addon saying it cannot tell, once per defensive, in the space
  where the answer should be. The owner read that footer and said they can
  go. The name and its icon stay.
- **Inline spell icons are line-height, not 14 pixels.** `|T…:0:0:…|t` sizes
  the icon to the font's line box; a fixed height taller than the line hangs
  out of the top of it, which is exactly what it did.
- **The faces on the replay are 30px** (were 20): a creature model is a
  whole silhouette in a square, and below about this it is not recognisable
  as anything.
- **"What you pressed" sits above its bars**, where the other two lanes
  carry their names. The bar stack starts 14px lower to make the gap.

## [4.51.0] - 2026-08-09

### Added

- **Defensive durations are MEASURED.** The press bars drew as stubs because
  their only source was the "active for N seconds" number a person can type
  in on the Auras page, and nobody types it in. `History.lua` now polls
  Blizzard's **buff viewers** ten times a second and records the window
  between a tracked buff going active and going inactive - our own clock
  over a value this patch withholds, the same trick the proc recorder plays
  with the glow events. Only the buff viewers, deliberately: an icon in the
  cooldown viewers is "active" for reasons of its own, and a Shield Wall
  drawn three minutes long because its *cooldown* was running would be a
  confident lie.
  - `History.PushActive` keeps a window only if it lasted between 0.5s and
    120s; `History.WindowFor` pairs a window with the press that opened it
    (0.5s early to 2.0s late, newest first, variant-aware) and answers with
    no end when the buff was **still up at the death** - which the replay
    draws as a bar running to the killing blow.
  - `History.NoteMeasured` keeps the longest window ever seen per spec, so a
    death restored from disk can still draw a length somebody observed.
  - `Replay.BarLength` asks in order: this press's own window, the number
    you set, the measured store. None answering is still a marker with no
    length - never a guess - and `Replay.LengthNote` says on hover which of
    the four it was.

- **A face over every hit and every heal.** `Death.ReadRecap` now extracts
  creature/display art **per event**, keyed by the source's name so a hit
  that carries no readable id inherits the face found on another hit from
  the same named mob. Mob faces are `PlayerModel:SetCreature` (built lazily,
  one per mark that has art); healer faces are `SetPortraitTexture` against
  the unit token the name resolves to - proven in shipping code (oUF's
  portrait element, EllesmereUI unit frames, BigWigs). No unit, no face: we
  do not know what that person looks like and will not invent one.

### Changed

- **The single killer portrait in the replay's corner is gone.** With ten
  mobs on you it answered for all of them and therefore for none. Its
  tooltip facts moved onto the per-hit marks (`Replay.SourceSummary`, was
  `KillerSummary`).
- **The damage columns stand clear of the axis** (`COLUMN_LIFT`), so the
  seconds written on the line stay readable under twenty of them.
- **"Defensives used"**, not "pressed" - and every spell named in the UI
  carries its icon and its tooltip: inline in the verdict and the
  availability footer (a wrapped font string cannot hold a hover target),
  and as real chips with the client's tooltip in the replay's legend. The
  analysis carries `{ spellID, name }` pairs everywhere it used to carry
  bare names, because only the id can produce either. `Death.PlainText`
  strips the inline icons on the way to chat, where the escape sequence
  would arrive as punctuation or not at all.
- The replay window is taller (576) and **"What you pressed" sits under its
  own bars** rather than at a fixed offset that landed on the third row -
  which nothing reached while every bar was a stub.

## [4.50.0] - 2026-08-09

### Added

- **Your presses are bars, not icons.** Each starts where you cast it and
  runs for as long as it is up, so "was it still there when the hit landed"
  is answerable by looking. Overlapping bars stack onto rows
  (`Replay.StackRows`, greedy by start time) and each keeps its own colour.
  **Where the duration comes from**: this addon measures durations and never
  assumes them (see `KnownProcs.lua`). Aura data is secret on this patch, so
  the source is the "active for N seconds" number you can set yourself on
  the Auras page. Unset, the press draws as a marker with no length rather
  than an invented one.

- **Zoom, and the wheel scrolls the plot.** Six presses inside two tenths of
  a second cannot be drawn apart at any icon size, so the plot shows less
  time instead (`Replay.View`, up to 8x). While playing the view walks with
  the playhead; scrolling takes it off that until Restart or Stop hands it
  back. At zoom 1 the view never moves, so the normal case costs one
  comparison per frame rather than sixty-eight re-anchors.

### Changed

- **The axis** is three pixels rather than one and carries its seconds **on**
  the line, on a patch of the window's own background, with half-second
  marks between them. The scale follows the zoom: twelve seconds on screen
  gets a label every two, a second and a half gets one every half.

- **The killer's portrait** is small and sits on the damage lane instead of
  filling the window's corner - in a dungeon twenty things are hitting you
  and one large face claimed the whole picture for one of them.

- The health bar is **red**, the **boxes around the icons are gone**, and the
  **Speed label sits next to its slider** rather than eighty pixels away.

### Fixed

- **A heal was recognised by two event names written from memory**
  (`SPELL_HEAL`, `SPELL_PERIODIC_HEAL`). It is now anything the client calls
  HEAL - if the recap says `SPELL_HEAL_ABSORBED` or anything else in that
  family, a heal would have been drawn as damage and counted into the wrong
  total.

## [4.49.0] - 2026-08-09

### Added

- **A third lane on the replay: healing on you.** The amount, the spell's
  icon and **who cast it**, in their class colour where the client will
  give it (`UnitClass` answers for someone in your group and nothing else,
  so it is asked under pcall and the plain name is the fallback). Healing
  used to be a green column among the red ones; "was anybody healing me" is
  its own question and now it has its own row. The window is taller for it,
  and worth it.

- **The killer's portrait on the replay**, with what he did to you on the
  hover: hits, total, biggest, and which of his abilities landed
  (`Replay.KillerSummary`, summed from the events already read). What else
  a mob *can* do is not something the client will tell an addon on this
  patch - there is no call for an arbitrary NPC's abilities, and a mob
  inside a dungeon withholds even its name. The tooltip says so instead of
  leaving a gap.

- **"Your health"** over the health bar. It is the only bar in the window
  and it was being read as the mob's.

### Changed

- **Speed is a slider** (a quarter to triple), and **the death window's
  size is a slider**. Both were buttons walking a fixed list; a quarter and
  a half are different things to want, and dragging to one beats clicking
  past three others to reach it.

### Fixed

- **The death window drew through the replay in front of it.** Two movable
  windows in one frame strata: the window's children sit above the other
  window's background, so its buttons punched through. Both are `SetToplevel`
  now - whichever is clicked comes forward - and opening a replay raises it
  without needing a click.

## [4.48.0] - 2026-08-09

### Added

- **How many deaths to keep is a setting** on the Deaths page - three to
  fifty, ten by default, per profile. They are kept for this character and
  survive logging out, so the number is how far back you want to be able to
  look. Lowering it trims the list **immediately** (`Death.Trim`): a list
  that keeps forty for the rest of the evening after being told ten is a
  setting that appears to do nothing. The cap is also applied on the way
  back **in**, because a list read off disk can be longer than what the
  setting says now.

- **The side list scrolls.** It shows twelve at a time - the pool is sized
  to the window, not to the setting, so asking for fifty does not build
  fifty frames to show twelve. The wheel over the list scrolls it; the
  wheel over the analysis still steps through deaths, and doing so keeps
  the death being read in view (`Death.ScrollTo`). The heading says "23
  deaths - scroll for more" rather than leaving the wheel to be discovered.

## [4.47.1] - 2026-08-09

### Added

- **Restart on the replay** - from the top, running. **Stop** rewinds and
  waits, which is what you want when you are about to point at something;
  Restart is what you want when you just missed it.

### Fixed

- **Play at the end of a replay did nothing.** The clock had already run
  out, so un-pausing it changed nothing on screen - a button that looks
  live and moves nothing reads as broken. There, and only there, Play now
  means play it again (`Replay.PlayAction`).

## [4.47.0] - 2026-08-09

### Added

- **REPLAY**, in a window of its own (`Core/Replay.lua`). A time axis down
  the middle, what came in above it, **what you pressed below it**. Play,
  pause, stop, and a speed button from a quarter to double. Every mark
  carries its icon, its number and the client's own tooltip; a health bar
  across the top drains as the playhead crosses them; a defensive of your
  own is drawn in the accent colour. Anybody looking at a bare lower lane
  can see that no defensive was pressed - which is what the window is for.

- **What you pressed** is now part of a death. It comes from
  `UNIT_SPELLCAST_SUCCEEDED` for "player" (`ns.History`), **not** the combat
  log - that is closed to addons on this patch. `Death.Storyline` merges it
  with the incoming events into one order, tie-breaking a press before the
  hit it answered. The verdict says the result in one line: "You pressed
  nothing in those seconds", "No defensive was pressed - you cast Death
  Strike, Heart Strike", or the defensives you did use.

- **The row bar is a health bar now.** It was the health left after each
  event, drawn in red, which said nothing about the hit itself. It is the
  health you had **going in**, split: slate for what was left, red for what
  the hit took, green for what a heal gave. `Death.RowSpans` is the rule,
  clamped so an overkill cannot draw past the end of the row.

- **The event table has a head**: When, What hit you, Damage, Health left -
  and a line above it saying what the bar behind each row means.

- **Damage and health left carry their percentage** and sit in the row
  rather than only in the hover. "107.9k" is a scratch on one tank and a
  third of another; "68%" is the same sentence on every character. On the
  killing blow the last column says how far past zero the hit went.

- **A Size button beside Share**, cycling 70 → 130 percent, saved per
  profile. The moment you want this window smaller is the moment it is in
  front of you.

### Fixed

- **A reload took your deaths, and the skull with them.** The list was kept
  for the session only, which is a defensible rule for an evening and a
  wrong one for a `/reload` - which happens after every settings change,
  every addon update and every error. The last ten are written to the saved
  variables **per character** and read back at login. Only readable values
  go in, copied field by field rather than the live table being handed
  over: a secret value in a saved variable throws at logout, when nobody is
  watching. A death nothing could be read out of is not stored at all. The
  verdict is **not** stored - it is derived from the events on the way back
  in, so a better verdict written later applies to the deaths already on
  disk.

- **The divider had all the air on one side.** The verdict, the Close
  button and the defensives line ran straight into it while the list had a
  full gutter. Even margins on both sides now.

- **The picked defensives were a column of same-grey names.** The picker
  has shown icons and the client's tooltip since 4.44.1; the list of what
  you picked did not. Both come from `UI.MakeRowASpell` now, one rule in one
  place, and the next list of spells calls it instead of growing its own.

## [4.46.0] - 2026-08-09

### Added

- **The session's deaths in a list**, down the right side of the window:
  time, where it happened, who did it, newest at the top. Click one to read
  it; the selected row carries the accent bar. The mouse wheel steps through
  them. **Clear list** underneath empties the session, and asks once first -
  there is no undo, and a mis-click during a wipe would take the analysis
  you were about to read.

- **Where it happened**, recorded with every death and shown under the
  title: `M+12 - Ara-Kara, City of Echoes - Avanoxx`, `Raid - Nerub-ar
  Palace (Heroic)`, `Open world - Duskwood`. The keystone level comes from
  `C_ChallengeMode`, the boss's name from `ENCOUNTER_START` - so a wipe on
  a boss says the boss and a death on the trash before it does not. It
  travels with the chat share. The short form ("M+12", "Avanoxx") is what
  the side list shows.

- **The killer's portrait** beside the title, a `PlayerModel` pointed at
  the creature id off the recap - the call MDT uses for its enemy tooltips,
  with a display id and an npc id parsed out of a readable GUID as the
  other two doors. None of them answering hides the block and slides the
  header back to the margin: no empty box.

- **A tooltip on every hit row** - the client's own spell tooltip where the
  recap named a readable id, and underneath it the damage, the overkill and
  the health left afterwards. A melee swing has no spell to ask about and
  says what it knows itself.

- **Where the share goes is a setting**: the group you are in (as before),
  or party, raid, instance, guild, say, yell outright. A channel that is
  not available prints to your own chat frame **and says which one was
  missing** - a share that quietly goes nowhere is the one failure this
  must not have.

- `/zs death clear` empties the list from the command line.

### Changed

- **The pager arrows are gone**, replaced by the list: two ways to walk the
  same ten deaths is one too many, and the list shows where you are instead
  of counting for you.

## [4.45.0] - 2026-08-09

### Added

- **The skull on the screen.** A small icon that appears with your first
  death of the session and counts them in its corner. Click opens the death
  window. Drag it wherever you want, any time - or lock it on the Deaths
  page. It never shows before anything has happened.

- **The window keeps the last ten deaths** of the session, and the arrows
  beside its close cross page through them. Share posts the death you are
  looking at, not blindly the newest. A capture retried for the same death
  replaces its entry rather than listing one fall twice.

- **The rows tell the whole story now**: every hit carries an icon - a
  melee swing gets the sword rather than a hole - and the attacker's name
  in quiet grey beside the spell's. The verdict names the killer too:
  "Melee from Heavyweight Golem for 109.5k". The chat share leads with
  "killed by".

### Fixed

- **The row list honours its own subtitle.** The recap hands over more
  history than "the last seconds" - the first live death showed hits from
  five minutes earlier under a heading promising ten seconds. Rows outside
  the window are kept off; when nothing recent is readable, the heading
  says so instead of lying.

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
