# Changelog

All notable changes to ZwoelfStuff are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!-- 4.12.0 through 4.20.0 shipped without an entry here. The in-game
     changelog in Core/Changelog.lua carried them throughout and is the
     source these were written back from. -->

## [4.30.0] - 2026-08-08

### Fixed

- THE WHOLE BARS FEATURE COULD FAIL TO START, and did. `Namers()` in
  `Core/Auras.lua` filled its own cache slot in place, and `Description()`
  inside its loop asks the client to load a talent's spell data - which answers
  with `SPELL_DATA_LOAD_RESULT`, sometimes synchronously, and that handler
  clears the cache. The table being filled became nil mid-loop and the next
  index threw. It runs under `Boot("Bars")`, so the throw took `Screen:Start`
  with it: bars on screen with no clock, reported as "die bars bewegen sich
  nicht mehr". Built into a local and published at the end now, with a
  generation counter so a list built across an invalidation is returned but
  never cached.

- THE GAME MENU ENTRY FAILED TO START AT ALL: `SetText` before the font was
  set, which raises rather than doing nothing. The rule is written down in
  `Core/Screen.lua`, where the same mistake was made once before.

- THE SPARK WAS NEVER DRAWN, on any bar, in any direction, since it shipped.
  It anchored its own `TOP` and its own `BOTTOM` both to the fill texture's
  `RIGHT` - one point, the middle of that edge - so both of its edges landed
  on the same line: ten pixels wide, zero tall. It spans `TOPRIGHT` to
  `BOTTOMRIGHT` now (and the mirrored pairs for the other three directions).

- THE COUNTDOWN'S POSITION AND NUDGE WERE APPLIED TO A FONT STRING THAT DID
  NOT EXIST YET. A `Cooldown` widget's number is drawn by the engine, which
  does not create the font string until a cooldown is actually running on that
  widget - and styling happens on a render pass, when almost nothing is on
  cooldown. `GetRegions` found nothing, styled nothing, and the engine later
  made its own. New `ns.StyleCountdown` remembers the style against the widget
  and re-applies it from a hook on `SetCooldown` and
  `SetCooldownFromDurationObject`, one frame later - the engine builds the
  number during the draw that follows the call, so an inline pass would still
  find nothing.

- THE STACK AND CHARGE COUNTS NOW MOVE AS FRAMES, not as the font strings
  inside them. Blizzard's own layout owns that text and rewrites its anchor;
  the counter frame around it is anchored once and stays put. And they are
  looked up in both places they live: `item.ChargeCount` and, on frames whose
  `Icon` is a container, `item.Icon.ChargeCount`
  (`EllesmereUICdmHooks.lua:2225-2228`). Looking in one place meant the
  setting silently did nothing on half the frames. Original anchors are
  recorded and restored in `CDM:Release`, the same rule the stripped
  decorations follow.

- THE SPELL NAME'S POSITION AND NUDGE WERE NEVER READ AT ALL. Both renderers
  anchored it hard to `LEFT`. All nine positions and both nudges now apply,
  inside the band the icon leaves - `Layout.LabelAnchor` and
  `Layout.LabelBand`, shared by the drawn cells and the adopted ones so a name
  cannot sit differently depending on which renderer drew it.

### Added

- THE CHARGE COUNT IS ITS OWN TEXT ELEMENT, with the same seven controls as
  the rest: on, font, size, colour, outline, one of nine positions, and a
  nudge on each axis. It shared `stacks` before, on the reasoning that
  Blizzard never puts both numbers on one frame - a cooldown item carries
  `ChargeCount`, a buff item carries `Applications`. True per icon, and beside
  the point across a screen: "charges top left, stacks bottom right" was not
  expressible.

- AND IT IS DRAWN ON OUR OWN CELLS FOR THE FIRST TIME. Adopted icons always
  had Blizzard's own `ChargeCount`; a cell this addon draws had nothing, so
  the same charge spell showed a number on one bar and not on the next. New
  `SPELL_UPDATE_CHARGES` handler and `Screen:RefreshCharges`, which walks only
  the drawn cells - an adopted icon's number is Blizzard's and stays correct
  without us.

- `ns.CanDisplay` in `Core/Secrets.lua`: the one sanctioned route for a secret
  value. `SetFormattedText` declares a secret argument, so the engine formats
  and draws the live count while addon Lua never sees it. Nothing reads the
  number - `isActive` is the clean signal (false only at full charges), so at
  full the answer is the maximum and below it the secret travels from the
  accessor to the setter untouched. Verified against
  `EllesmereUICdmBuffBars.lua:4310-4340` and `:4577-4584`.

- A ZWOELFSTUFF ENTRY IN THE GAME MENU (`Core/GameMenu.lua`), appended under
  the last of Blizzard's own buttons. Appended, never inserted: the menu
  re-anchors its whole pool on each open, so an entry in the middle means
  rewriting Blizzard's offsets on every `Layout` pass for ever. It stands down
  in combat - the click closes a protected panel - and can be switched off in
  Settings.

- NO FRAME TEMPLATE ON IT. `MainMenuFrameButtonTemplate` ships a red plate
  that is never seen on the real entries because all of them are restyled
  afterwards - by Blizzard, or by whichever skin is running. Ours is not in
  that pool, so it wore the raw template: a red slab among grey rows. A bare
  frame has no leftover artwork; the label borrows the neighbouring button's
  font on every `Place`, so it reads as a menu entry under any skin rather
  than as a fixed guess at what the menu looks like.

### Changed

- `ns.TextOffset` and `ns.PlaceText` in `Core/Init.lua`: where one of the nine
  positions actually puts a number, including the 2px inset that keeps an
  outlined glyph off the border. One function, because the two renderers sit
  on the same bar and a position that means something slightly different on
  each is the exact class of bug this styling pass exists to end.

- `Bars:Prepare` migrates `stacks` into `charges` where the new key is absent,
  before `ApplyDefaults` - the same placement, and for the same reason, as the
  `fillSide` migration in 4.27.0. A fresh table with a fresh colour inside it:
  sharing `stacks`' colour would make the two settings one setting again, one
  indirection further down where it is much harder to see.

- `Layout.SparkPoints`, `Layout.LabelAnchor` and `Layout.LabelBand` are pure
  and exported. Both of the anchor bugs above were invisible in a static check
  and needed a bar on screen with a running cooldown to see; the naming is now
  done by functions that take strings and return strings, and reverting
  `SparkPoints` to its old form turns five checks red.

- 243 checks in `/zs test`, up from 166. Three new suites. `GameMenu.TwoLowest`
  and `GameMenu.GapBetween` are pure and exported for exactly the reason
  `EditMode.SnapAxis` is: both fail silently, both need the pause menu open to
  look at, and a rule that cannot be run gets diagnosed by reading.

## [4.29.0] - 2026-08-08

### Added

- DISCORD IN THE LEFT COLUMN, above the version. Clicking it opens the invite
  in a copy box with the whole link already selected. No addon can open a
  browser - the client has no call for it, on purpose - and a row that looked
  like a link and did nothing would be worse than no row.

- The mark next to it is `brand-discord`, drawn here rather than traced from
  Discord's brand kit, and it is NOT their official logo: a chat blob with two
  eyes. Solid rather than the 1.4 stroke the rest of the set uses, because a
  brand mark is solid and an outlined blob is mush at 14 pixels. To use the
  real one, drop Discord's own SVG into the design icons folder as
  `brand-discord.svg` and run the same pipeline; the name is already wired up
  and nothing else changes.

## [4.27.0] - 2026-08-08

### Added

- THE FILL RUNS WHICHEVER WAY YOU WANT - left to right, right to left, bottom
  to top, top to bottom. One setting with four answers where it used to be two
  switches ("Start on the right", "Fill up") you had to combine in your head,
  neither of which named the thing you actually wanted to say.

- TWO OF THE FOUR ARE NEW CAPABILITY, not a relabelling. `SetReverseFill` only
  ever flips a HORIZONTAL bar, so a vertical fill was unreachable whichever way
  the old switch was thrown; the renderer needed `SetOrientation` as well. The
  spark rides the top or bottom edge on a vertical bar now, and the charge
  marks lie across it instead of running down it - three lines parallel to the
  fill divide nothing.

- `/zs test` checks all four land on a DIFFERENT (orientation, reverse) pair,
  that both axes are actually used, and that an unknown name falls back rather
  than returning nil. 166 checks, up from 154.

### Changed

- STACK COLOURS: the rows said `At ... stacks`, which reads as a label that has
  been cut off - that is what an ellipsis in the middle of a phrase looks like.
  They say `From`, and the number is in the control beside them.

- `/zs report` OPENS A BOX YOU CAN COPY OUT OF - every proc the addon has
  watched you set off on this character and spec, with the addon version and
  the client build so the list still means something a month later. Focused
  and fully selected on open, so it is one Ctrl+C. It used to print to the
  chat frame, which is not a way to hand anything over: chat text cannot be
  selected, the colour codes would come with it if it could, and thirty lines
  scroll off the top - which made "export" a command only the person holding
  the source file could use. `/zs auras export` still works and does the same.

### Fixed

- A bar set to start from the right keeps doing so: `fillSide` is converted to
  `fillDirection` in `Bars:Prepare`, before the defaults are applied. Doing it
  in `Migrate` would have left it to `ApplyDefaults` on the next login, which
  would have quietly reset it.

## [4.26.0] - 2026-08-08

### Changed

- THE TEXTURE LIST IS THE ONE FROM THE DESIGN NOW (screen 3a). 368 wide, with
  a search box at the top and the keys explained at the bottom, and it groups:
  `SHIPPED WITH ZWOELFSTUFF` first, `FROM YOUR OTHER ADDONS` after.
  Deliberately not alphabetical across the two - at forty-odd entries that is
  the difference between finding and searching. Which group a name belongs to
  is decided by its PATH, not by its prefix, so it stays right for fonts and
  borders too.

- THE PREVIEW STRIPS ARE IN THE BAR'S OWN FILL COLOUR, and the full 132 x 14
  the design draws instead of a 76-wide chip. They were painted in the addon's
  accent, which tells you nothing about the bar you are setting up.

- THE CHOSEN ENTRY IS SAID THREE WAYS - a raised ground, a 2px accent bar on
  the left edge, a tick on the right. It was orange text, which in a list of
  grey text is a difference you have to look for.

- The list fades out at the bottom rather than being cut off mid-row.

### Added

- TYPE TO FILTER. Case-insensitive substring on any part of a name. A group
  whose entries are all filtered away loses its heading with them - `/zs test`
  covers that case specifically, because it is the one that looks fine until
  you try it. The rule is `UI.FilterMenuItems`, pure and testable, for the
  same reason the snapping arithmetic is. 154 checks, up from 146.

- The desktop harness opens menus now: a plain one, the media list, and the
  media list mid-filter. Nothing in it opened a popup before, which is the
  largest single piece of the widget layer.

## [4.25.0] - 2026-08-08

### Changed

- RIGHT CLICK THE MINIMAP BUTTON TO MOVE THE BARS. It used to toggle the
  co-tank panel - a module parked until 12.1, so the branch was switched off
  and right click quietly did the same thing as left click. Moving the bars is
  the one thing you come to that button for that is not "open the window", and
  it was two clicks deep. Co-tanks needs another home when it returns.

- SNAPPING IS NOT A SETTING ANY MORE. It is what dragging does. The switch is
  gone from the tools panel, because a switch whose off position makes a
  feature silently do nothing is the switch that gets left off by accident and
  then reported as a broken feature - which is exactly what happened. Hold Alt
  while you drag to place a bar freehand; that is the escape hatch, and it is
  per drag rather than per profile.

### Added

- THE ARITHMETIC CAN BE TESTED NOW. Snapping went wrong three times, and every
  diagnosis was reading the code and reasoning about it, because none of it
  could be RUN - the maths was welded to live frames and saved settings. It is
  split in two: `Snap` measures the bars on screen, `EditMode.SnapAxis` is
  plain numbers in and plain numbers out. `/zs test` puts two bars four pixels
  apart and asserts where the second one lands - centre alignment, edge
  alignment, flush, the screen edge, out of range, the grid fallback, a bar
  beating the grid, and a zero grid step. 146 checks, up from 136.

## [4.24.0] - 2026-08-08

### Fixed

- SNAP TO GRID WAS NEVER ON, AND COULD NOT BE TURNED ON PROPERLY. Edit mode
  fills in any setting your profile is missing - and it carried its own list of
  four keys next to the seven the profile actually declares. `snapToGrid` was
  in one list and not the other, so on any profile older than that key it read
  as nothing at all: switched off, with no way to tell it had never been on.
  It fills from the one list now, and grid snapping is on by default.

- AND THE GRID NEVER DREW A LINE WHEN IT CAUGHT. Snapping to another bar
  showed you the line it lined up with; the grid, which is the one kind that
  always pulls, showed nothing - so the snapping that was working looked like
  the snapping that was not. It draws its line too.

### Added

- BARS SNAP AGAINST EACH OTHER NOW, NOT JUST INTO LINE WITH EACH OTHER. Every
  target used to be an ALIGNMENT - your left edge onto their left edge, your
  middle onto their middle. So two bars could line up but never sit flush side
  by side, which is how a row of bars is actually built. Your edge against
  their edge is a target now, on both axes.

- AND THE SCREEN EDGES CATCH. Pushing a bar into a corner had nothing to snap
  to at all.

### Changed

- THE OVERLAY SAYS WHAT SNAPPING IS DOING. The state lives on two switches in
  a panel you have to open first, and the line above them explained how to
  hold Alt to suspend snapping - while snapping was switched off. It now says
  what it snaps to, or that it is off and where the switch is.

- `/zs test` checks that every key edit mode reads has a profile default. 136
  checks, up from 129; proven by removing `snapToGrid` and watching it go red.

## [4.23.0] - 2026-08-08

### Added

- EVERY BAR CAN BE PINNED ON ITS OWN. A padlock sits under the cog on each
  one. A pinned bar still selects, still opens its settings, still takes a
  cell - it just does not move, by drag, by the arrow buttons or by the arrow
  keys. The bar you have finished placing and the bar you are still placing
  are on screen together, and the finished one is exactly what a stray drag
  lands on. The same switch is in the bar's own settings, so you can see which
  are pinned without going in and looking at each one.

### Changed

- CLICKING A BAR OPENS ITS SETTINGS. The tools panel already followed whichever
  bar was selected, but you had to know that and press Tools first - so
  clicking a bar looked like it did nothing.

- THE NUDGE ARROWS ARE ONE ROW ON A TAB ABOVE THE BAR. As a four-way pad
  inside the box they sat on top of the bar's own name and whatever it was
  drawing, and a small chevron over a spell icon is not readable at any
  colour. Now they have their own strip, flush on the top edge, with the same
  fill and outline as the box: left, right, up, down. One pixel a click, ten
  with Shift, unchanged.

### Fixed

- THE MINIMAP BUTTON IS ACTUALLY ROUND. Its rim and plate were a solid colour
  with a circular mask over them - and a mask works by multiplying a TEXTURE's
  transparency, which a colour fill does not have. So the mask did nothing to
  those two layers and everything to the icon, and the square corners of the
  plate stuck out around the round icon. Both are a real round file now
  (`Media/disc-64` and `disc-128`), tinted where they are used, the same way
  the window's icons work.

- A dead `locked = true` in the bar defaults, read by nothing, is removed. The
  new switch is `pinned` on purpose: reusing the old name would have pinned
  every bar you already own on update, because every saved bar already carries
  it as true.

## [4.22.0] - 2026-08-08

### Changed

- THE REST OF THE DESIGN'S ICONS ARE IN. Sixty-eight were drawn and rendered;
  the last release used eleven of them. Now the plus and minus on every
  stepper, the close cross, the three-dot overflow, the chevron on every
  dropdown and the cross that deletes a saved entry are all the design's own
  marks instead of typed characters. A hyphen and a plus sign sit on different
  baselines in any font, which is why that pair never looked like one control.

- THE LISTS THAT PICK A SHAPE NOW SHOW THE SHAPE. Arrangement, fill order,
  across, down, and the bar's kind draw their mark in front of the word - in
  the open list and on the closed field. "Staggered" and "Puzzle" are both
  just words until you have seen each one once.

- SO DO THE ROWS THAT REPEAT. The six places a bar may show, the four
  conditions, the effects and the media rows each carry their own mark. Six
  rows that differ by one word are a list you read from the top every time;
  with a mark you find the raid switch without reading any of them. Ordinary
  settings rows do NOT get one - a mark next to everything is decoration, and
  decoration next to a real signal makes the signal worth less.

- The cog on each bar is the design's gear, Done wears a padlock, and Move
  bars and Build carry the same two marks in edit mode that they carry in the
  window - so the pair is recognisable in both places.

### Removed

- THE AURA DISPLAY PAGE IS GONE FOR GOOD. It was in the design and never in
  the addon; the auras the Cooldown Manager does not carry are handled where
  the bars are and need no page of their own. The glyph kind that pointed at
  it is removed; the rendered file stays in the icon set.

### Fixed

- EDIT MODE: DONE WAS SITTING ON TOP OF SPELLS. The tool bar was 360 wide, the
  bottom row of buttons ran to 332, and Done - anchored to the right edge -
  started at 276. The two shared 56 pixels whenever you were in build mode,
  which is the only mode where Spells is shown. The bar is 460 now and they no
  longer touch.

### Added

- A CHECK THAT CATCHES A MISSING MARK. An unknown icon name never threw - it
  quietly fell back to four rectangles, which is exactly how the wrong icons
  shipped in the first place. `/zs test` now walks every list that names one
  and fails if it does not resolve. 129 checks, up from 124.

## [4.21.0] - 2026-08-08

### Changed

- THE WINDOW WAS REDRAWN, PROPERLY. You had it designed - colours, sizes,
  spacing, every screen - and this is that design built. The complaint it
  answers is the one you started with: "unuebersichtlich, sieht altbacken
  aus".

- THE SIDE COLUMNS ARE NOW DARKER THAN THE MIDDLE, not lighter. That one
  inversion is most of it: the thing you are working on sits on TOP of the
  window instead of in a trench between two raised walls. The whole palette
  went deeper with it, and orange now appears at most once per column - so
  when it does appear, it means something.

- THERE ARE NO SLIDERS LEFT. Every number is a stepper: minus, the value,
  plus. A slider standing in for a range is only as precise as the pixels it
  happens to be wide, and on a 0-to-1 opacity in a narrow column no exact
  value was reachable by hand. You can still type into the box, and the wheel
  over it still steps.

- THE LEFT COLUMN IS GROUPED - Bars, System, Info - under the addon's mark and
  wordmark, with the version and your client build along the bottom. Seven
  flat entries is a list you read from the top every time.

- THE CARDS SAY WHAT THEY ARE. A numbered chip, the name, and a badge for the
  kind. Rows, Columns and Arrangement moved into a column BESIDE the preview
  instead of a strip under it, so two cards fit where one and a half did.
  Delete moved into the overflow menu, where an action with no undo belongs.

- THE RIGHT COLUMN HAS THREE TABS - Look, Behaviour, Reuse - instead of nine
  sections in one long scroll. And on Settings it is never empty any more:
  point at a setting and the third column explains it. That text used to be a
  wrapped grey paragraph under every single row, which was the largest single
  consumer of space on the page.

- THE PANEL HAS ITS OWN FONT, and that was the single biggest reason it did
  not look like the design. Every string in the window took the CLIENT's face
  - wide and round - while the design is drawn in a narrow grotesk and
  Settings had a font picker that only ever reached the bars. Panel font and
  bar text are now two settings, because a face that is right over a moving 3D
  scene is rarely right for forty rows of settings.

- THE SPELL LIST IS ONE LINE PER SPELL. The grey second line carrying "on this
  bar, cell 2" and the spell ID is gone; what an entry has to say on the right
  is one short thing - which cell it sits in, how long its cooldown is, or
  that your build does not have it. The ID is in the tooltip, where you look
  when you are asking about one of them rather than scanning all of them.

- THE ICONS ARE THE DESIGN'S OWN NOW. Every mark in the window used to be
  built from filled rectangles, which is why they never matched: the design
  draws OUTLINES at 1.4 pixels with round ends - four EMPTY squares for
  Cooldowns, a real circle for About, real diagonals for Edit mode. Rectangles
  cannot draw a circle.

- The client loads neither SVG nor PNG, so the design's 68 drawings are
  rasterised and shipped as TGA - and rendered at the size they are shown at
  rather than scaled between sizes, because a 1.4 pixel stroke does not
  survive being resized. They are white and tinted where they are used, so one
  file serves the dim, the bright and the accent state.

- AND THEY ARE SHARP AT YOUR INTERFACE SCALE. Your interface is not at 1:1 -
  one unit is closer to 1.8 real pixels - so a mark drawn at 14 was being
  stretched to 25 and every fine stroke went soft. Each one now exists at the
  design size AND at double, and the client picks the nearer one and scales
  DOWN instead of up.

- NEW LOGO, and the minimap button wears it.

## [4.20.0] - 2026-08-08

### Changed

- THE NAVIGATION IS STRAIGHTENED OUT. You said it was a muddle - where the
  buttons are, what they are called - and you were right. It had grown rather
  than been designed.

- What was wrong, plainly: "Done" and "Just this one" sat on the SAME spot in
  the top right and swapped places depending on what you were doing, which
  reads as the window moving under your hand. "Options" meant this bar, "Just
  this one" meant this cell, and nothing said how the two were related. And
  from a cell you could not get to its bar at all - Done always threw you back
  to the spell list.

- EACH CARD NOW CARRIES ITS OWN THREE TABS: Spells, Bar, and the cell's own
  name. The thing you are looking at chooses what is being edited, and the
  answer appears beside it. Only the card you are working on lights a tab,
  because three lit cards would claim three things are being edited at once.
  The Cell tab shows the spell it would edit, so you know what it means before
  you press it.

- "Options" is gone - the tab replaced it. Build on screen and Delete stay on
  the right of the header, so a click that changes the view and a click that
  changes the bar are never neighbours.

- A PATH UNDER THE HEADING shows the way back: Spells > Bars 2. Every part is
  clickable, so a cell can reach its bar without going through the spell list.
  It shows only where you can GO, never where you already are - the heading
  below says that, and printing the same word twice one line apart is how the
  old one got confusing.

- AND THE CELL SETTINGS ARE IN EDIT MODE TOO. Colour, size and the fill
  direction now sit in the tool panel, where you are looking at the real bar
  instead of a preview - a colour is something you judge against the screen it
  will live on. Both places write the same setting through the same code, so
  neither can know a value the other does not. A star next to the name means
  that cell wears something of its own.

## [4.19.0] - 2026-08-08

### Changed

- EVERY SLIDER CAN BE TYPED INTO. Click the number, type it, press Enter. It
  was read-only, which meant an exact value could only be reached by dragging
  until the display agreed - and on a 0.05 step that is a game of patience,
  not a setting.

- The unit comes off what you type: "85%", "85" and "85 s" all mean the same
  thing, because people re-type over a value they can see and what they can
  see has a unit on it. Escape puts it back. Both kinds of slider - the big
  ones in the settings and the small Rows and Columns ones on the cards.

- The "x" is gone from the size sliders. 1.00 says it.

- EDIT MODE IS THE FIRST ENTRY IN THE LEFT COLUMN. It was called Unlock Mode
  and it was a lone button at the bottom of the rail, on the argument that it
  is a thing you DO rather than a place you go. True, and beside the point -
  it is the thing this window exists to get you to, and it was the one item on
  the left that did not look like the others.

## [4.18.0] - 2026-08-08

### Changed

- NEW: EVERY CELL CAN BE EDITED ON ITS OWN. Click a cell in a bar card and
  press "Just this one" - colour, opacity, texture, which end the fill starts
  at, whether it fills up, border, backdrop, spark, charge marks, size, shape,
  and its own stack colours. So Bone Shield can be red with bands at five and
  ten while the two bars under it stay exactly as they were.

- EVERYTHING FOLLOWS THE BAR UNTIL YOU TOUCH IT. Change the bar's colour and
  every cell that has not been given its own follows along, including cells
  you edited something ELSE on - a cell that owns its colour still follows the
  bar for everything it does not own. "Follow the bar again" at the bottom
  hands the whole cell back.

- There is no per-setting inherit switch on purpose. Twenty rows each with two
  states to read is a panel nobody can use; one clear way back is better.

- The overrides belong to the SLOT, not to the spell sitting in it - the same
  rule as the size and the nudge. Drag Bone Shield to the top of the bar and
  the red stays where it was, because that is what lets a layout be handed to
  another character at all.

- The card previews it. A cell wearing its own colour is drawn in that colour
  in the editor, not just on screen.

- Text is deliberately not per-cell yet: three elements times seven controls
  each is a panel that cannot be read, and a bar whose cells use four fonts is
  not a design. If one cell needs its own countdown, say so and it gets added.

## [4.17.0] - 2026-08-08

### Changed

- DRAG A SPELL TO SORT A BAR. You asked for drag and drop in the bar cards -
  it was already there, and it was doing the wrong thing, which is very likely
  why it did not feel like sorting.

- It SWAPPED the two cells. Drag the third spell onto the first and you got
  third, second, first: the spell you never touched had moved as well. That is
  right for 'these two are in each other's places' and useless for putting a
  list in order - sorting four spells that way takes six drags and a plan.

- It reorders now. The spell you drag lands where you dropped it and
  everything else keeps its own order, one place along. Sorting a bar is one
  drag per spell.

- Hold SHIFT while dropping for the old swap. Both are worth having; only one
  of them can be the plain drag, and sorting is what you asked for.

- A gap in a bar counts as a position and travels with the sequence rather
  than being quietly filled, so a deliberate hole stays a hole.

- The cell's LOOK does not travel. Scale, nudge and kind belong to the slot,
  so a spell dragged to the front wears the front slot's look - which is the
  whole point of a slot having one.

- The tooltip on a filled cell now says all of this, since a drag nobody knows
  about is a drag nobody uses.

## [4.16.0] - 2026-08-07

### Changed

- NEW: SPARK. A bright line riding the moving edge of a tracking bar's fill.
  Under Bar fill.

- It costs nothing per frame, which is the small nice part: it is anchored to
  the fill's TEXTURE rather than positioned by hand, so the game moves it
  along with the clock and this addon never touches it again.

- NEW: CHARGE MARKS. One line across the fill per boundary between charges -
  three charges get two lines, at a third and two thirds. Its own colour,
  under Bar fill.

- They only appear on a spell that actually HAS more than one charge, so you
  can leave the setting on for a whole bar without marking everything on it.
  And they are anchored to the bar rather than to the fill, so they stay where
  they are while the fill moves past them - the exact opposite of the spark,
  on purpose.

- NOT BUILT, and here is why: keybind text on an icon. It reads like a small
  thing next to these two and it is not. Getting the key for a spell means
  walking every action bar and every binding name, resolving each slot to a
  spell - through macros as well - and then following the bar PAGE as it
  changes with your stance, your form and any vehicle you sit in. That is a
  subsystem, not a setting, and it is the wrong thing to start two days before
  the basics are due. Say the word and it gets built properly after.

- That is all four you picked out of the reference addon.

## [4.15.0] - 2026-08-07

### Changed

- NEW: GLOW IN THE REFRESH WINDOW. The tail of an aura where recasting it
  wastes nothing - pandemic, if you know the word. Under Effects, with its own
  colour.

- THIS ADDON DOES NOT WORK THE WINDOW OUT, and that is the interesting part.
  Doing so means dividing the time left by the full duration, and on this
  patch both of those numbers can be protected - dividing one protected number
  by another is exactly the thing that taints an addon and breaks it. So it is
  not calculated. Blizzard already knows where the window is, because its own
  Cooldown Manager marks it, and this addon simply asks. The question stops
  being arithmetic and becomes a fact somebody else worked out inside the
  game, where the numbers are readable.

- The catch is honest and the panel says it: it only lights for the spells you
  have switched pandemic alerts on for in Blizzard's own Cooldown Manager
  settings. Nothing here can turn that on for you.

- It outranks the plain glows, because it is the one that means press this
  now, and gives way to the last-seconds warning, which is more urgent still.

- Third of the four you picked. The small ones - charge marks, keybind text,
  the spark - are what is left.

## [4.14.0] - 2026-08-07

### Changed

- NEW: ACTIVE FOR. Some things the Cooldown Manager only ever shows as a
  cooldown - a trinket's use effect, a potion, a racial. It knows exactly when
  they come back and nothing at all about how long they LAST, so the one
  number you actually want mid-fight is on screen nowhere. Say how long it
  lasts once, and the cell runs that window every time you press it: our
  sweep, our fill, our timer.

- Settings, under Auras. The list offers the spells that are on your bars,
  because those are the only ones where declaring a window changes anything
  you can see. Zero switches it off.

- It is remembered for the whole ACCOUNT rather than the character, for the
  same reason the recorded procs are: how long a trinket lasts is a fact about
  the trinket, identical on every alt. It is not a piece of user interface.

- A spell the Cooldown Manager already tracks as a buff is left alone. Its own
  clock is measured inside the game and beats a number somebody typed, every
  time.

- The window follows a spell into its other form, so a state set before a
  talent transforms the spell still fires afterwards.

- BLIZZARD'S ICON IS NEVER TOUCHED - not its transparency, not its cooldown,
  not its parent. The window is drawn on a layer above it and taken away
  again, so if this addon is ever unloaded mid-window what is left behind is
  Blizzard's display exactly as it was. That is the reference addon's
  arrangement and it is the only one that cannot leave a mess.

- Second of the four you picked. Pandemic glow and the small ones - charge
  marks, keybind text, the spark - are still to come.

## [4.13.0] - 2026-08-07

### Changed

- NEW: STACK COLOURS. A tracking bar changes colour once the stack count
  reaches a number you pick, with three bands. This is the Bone Shield
  setting, and it is the thing the reference addon has that was worth having
  most.

- Below the lowest band the bar wears its normal Bar fill colour - so the way
  to say 'warn me under five' is a red fill with a band at 5 in your usual
  colour. There is no separate 'below' mode to get the wrong way round. Set a
  band's count to 0 to switch it off.

- WHY THIS WORKS AT ALL, because it is not obvious and it is the reason nobody
  else's addon does it on this patch: since 12.0 the stack count can arrive as
  a protected value. An addon may pass one along but may never compare it, add
  to it, or even test it for true - doing so taints the addon. So this addon
  does not compare it. Each band is a bar whose range is set to exactly the
  number you chose, the count is handed to the game, and the GAME decides
  whether it has been crossed. The comparison happens where it is allowed to
  happen.

- With several bands crossed at once, which colour wins cannot be decided by
  an if - there is nothing an addon may look at. It is decided by what is
  painted last: each band sits on top of the one below it, so the highest one
  you have crossed covers the rest. The approach is EllesmereUI's and it is
  the only legal way to do this.

- This is the first of four things you picked out of that addon. Custom active
  states, pandemic glow and the small ones - charge marks, keybind text, the
  spark - are next.

## [4.12.0] - 2026-08-07

### Changed

- You asked us to take the reference addon's Cooldown Manager apart instead of
  guessing. Its spell picker turned out to describe both of the things you
  reported - the list being wrong and the tracking being wrong - and it names
  five separate causes. All five are fixed here.

- FIXED, reported: the list mixed the groups together. Every group was
  numbered from 1, so the first Cooldown and the first Utility both scored 1
  and the tie fell through to the name - which interleaved them
  alphabetically. Each group owns its own range now, and can never reach into
  the next one.

- FIXED, and this is the bigger half: the icons actually on your screen
  contributed no order at all. Their order was taken from a static list
  instead, when every one of those frames carries its own layout position -
  the number Blizzard lays the row out by. That number is now what the picker
  sorts by, so the list reads in the order you are looking at.

- FIXED: the list offered spells you had already removed. Spells dragged to
  'Not Displayed' in Blizzard's own Cooldown Manager settings stay in the
  static category list forever, so they kept turning up here. The arrangement
  is read from Blizzard's settings directly now - what you hid stays hidden,
  and the order you dragged things into is the order you get.

- FIXED, reported: 'so many tracking errors'. A spell that a talent replaces
  changes the ID its frame reports - Frostbolt becoming Glacial Spike is the
  everyday case - and a cell holding the old ID simply stopped finding it. The
  spell was on screen and the cell went blank. A spell is now indexed under
  every form of itself, so a cell keeps it through the transform.

- FIXED: an override left behind by a talent you no longer have was still
  believed. Blizzard keeps reporting one after the talent is gone, so a cell
  would show a spell you cannot cast, with the wrong name and the wrong icon.
  It is only taken now when the game agrees you actually have it.

- FIXED, and this one was invisible until you knew where to look: while a buff
  was UP, its frame answers with a protected value that no addon may read - so
  resolution fell through to a generic entry for your spec. The icon changed
  into something unrecognisable for exactly as long as the buff lasted, then
  changed back. The last readable answer is remembered per cooldown and
  reused, which also means it corrects itself the moment you respec.

- The self test grew a 'Spell identity' section covering all of it - twenty
  more checks, two of which read your live Cooldown Manager without touching
  it. They were confirmed by putting the old bugs back and watching the suite
  go red.

## [4.11.1] - 2026-08-07

### Fixed

- **The spell list was sorted alphabetically, which matched nothing.** The
  panel says "From your Cooldown Manager" at the top, and the Cooldown Manager
  has an order of its own â€” the one you arranged in Blizzard's Edit Mode and
  the one the icons appear in on screen. The picker now uses that order:
  `GetCooldownViewerCategorySet` returns the category already sorted, so the
  index is recorded and sorted by. What you cannot cast still goes last within
  its group â€” worth listing for a build you are about to switch into, not
  worth scrolling past. Names only break ties now, which also stops a German
  client filing its umlauts after Z.
- **The list footer counted everything as "cooldowns".** Four of its six
  groups are not: utility, buffs, buff bars and recorded auras. It counts
  entries now and says so.

## [4.11.0] - 2026-08-07

### Changed

- **Every setting is now saved under the character and realm that made it.**
  Owner's rule: *"mach ich eine Ã¤nderung am ui oder egal was, muss das unter
  dem charakter namen und server gespeichert werden"* â€” with the reason given
  in the same breath: *"sonst wird das pro klasse oder spec ja jedes mal
  Ã¼berschrieben"*. That is correct and no keying by class or spec can fix it;
  two characters of one class were writing over each other. The profile key is
  `"Name - Realm"`, the same one EllesmereUI uses on this client. Your existing
  settings become the profile of the character you are on when 4.11.0 first
  loads.
  Version 6's per-spec split survives *inside* a profile: the spec you are in
  decides which spells its bars hold, so an offspec keeps its own picks.
- **The recorded procs stay shared by the whole account.** They are not a UI
  setting: they are measurements that take hours of play to collect, are
  identical for anyone of that class and spec, and cannot be typed back in.
  Filing them per character would make every alt start the recording again
  from nothing.

### Added

- **"Take a layout from" in Settings.** The other half of per-character
  settings, and the owner asked for it in the same breath: pick another
  character and their bars arrive here â€” arrangements, sizes, looks, rules and
  positions â€” with every cell EMPTY. The spells stay behind on purpose: a
  Death Knight's cooldowns are not castable on a Paladin, and copying them is
  the bug this split exists to prevent. Attachments are re-pointed at the new
  bars' ids rather than left aiming at numbers from another profile.

### Fixed

- **The first fight on a new character read as a wall of errors.** Every proc
  the recorder had never seen printed its own line â€” reported as *"sooo viele
  tracking fehler bei allen klassen und spells und buffs"*. Nothing was
  wrong: that is the recorder doing its job, and it was announcing each
  discovery in the middle of a pull. They are collected now and reported once,
  a few seconds after the last one arrives.

## [4.10.0] - 2026-08-07

### Fixed

- **A Paladin was shown a row of Death Knight cooldowns.** The saved variables
  are account-wide, so every character got whatever the last one had picked.
  Owner's rule, and it is the right one: *"das layout muss gespeichert werden,
  aber nicht die spells"*. So a bar is two things now. Everything about how it
  LOOKS and where it sits â€” the arrangement, sizes, colours, rules, per-cell
  overrides â€” stays shared by every character, because that is a user
  interface you built once and want everywhere. What each cell HOLDS is filed
  per class and spec, the same key the proc registry has always used. Two
  characters of the same class and spec share their picks, which is help
  rather than harm.
  Existing bars are adopted by the first character that can identify its own
  spec, which is the character that made them â€” never while the client still
  answers 0, because that would file them where nothing would look again.

### Changed

- **The per-cell look now belongs to the SLOT, not to the spell.** A reversal,
  and it follows directly from the rule above: a slot scaled to 150% is part
  of a layout every character sees, so dragging a spell on one of them must
  not rearrange it for the rest. Moving and removing cells therefore move the
  spells and leave the slots alone.

### Removed

- **`Core/Glow.lua`.** The expanding proc ring went with the single-aura
  window in 4.4.0 and nothing has called it since â€” 117 lines loaded on every
  login for nothing. In the git history if it is ever wanted.

## [4.9.0] - 2026-08-07

Answering *"kann man nicht schauen wie das elle ui lÃ¶st?"* â€” yes, and it
changed the architecture. `EllesmereUICdmBuffBars.lua` was read rather than
guessed at, and it settles two things this addon had wrong.

### Changed

- **Tracking bars are now DRAWN, not adopted.** Blizzard's TrackedBar template
  is a whole bar â€” its own border, its own fill, its own two font strings â€”
  and none of it is ours to restyle. That is why the bar on screen never
  matched the preview and why a border stayed on a bar whose thickness was set
  to zero: there is no amount of stripping that turns somebody else's template
  into your design. Blizzard's frame is now kept alive as a *data source* at
  alpha 0, and the bar is drawn here with its value taken straight from
  Blizzard's StatusBar â€” `SetMinMaxValues`/`SetValue` passed through, nothing
  inspected or computed, which is what keeps it legal with secret values. The
  reference does exactly this: *"reads min/max/value from Blizzard's Bar â€”
  zero duration computation"* (EllesmereUICdmBuffBars.lua:4649).
  Blizzard's timer text is copied across so nothing is lost; the second
  FontString on the StatusBar is the timer, counted rather than named because
  they have none (ibid. 3407).
  **Icons are still adopted** and that is deliberate â€” there the frame IS the
  art, its icon is correct for the talent you have, and drawing our own would
  mean reading aura data.

### Fixed

- **"Fill up" moved the bar to the other end instead of making it fill up.**
  Reported: *"fillup richtung stimmt nicht"*. It was one setting doing the
  wrong one of two jobs â€” the label promised a direction in TIME and the code
  called `SetReverseFill`, which is a direction in SPACE. They are two
  settings now: **Start on the right** (which end the fill sits at) and
  **Fill up** (grows as time passes instead of draining). A profile that had
  the old one switched on gets **Fill up**, because that is what its label
  said it was.

### Migration

Saved variables move to version 5.

## [4.8.0] - 2026-08-07

### Fixed

- **A picked texture never reached an adopted buff bar.** Reported: *"die
  texturen werden nicht Ã¼bernommen"*, and exactly right â€” Blizzard's
  TrackedBar template carries its own StatusBar, and this addon had never
  touched it. What was on screen was Blizzard's gradient and no setting here
  could change it. It now takes the bar fill's texture, colour and opacity,
  so the bar Blizzard draws and the bar this addon draws wear the same
  settings. The StatusBar is located rather than assumed: the field name
  first, then a walk of the child frames, so a member renamed in a patch
  costs the fill and never an error.
- **The Cooldown Manager could only be found once.** `IsAvailable` cached a
  NEGATIVE answer for the session. The usual reason for that answer is that
  Blizzard's Cooldown Manager has not been switched on yet â€” which is exactly
  what the addon then told you to go and do, and then refused to notice you
  had done. Only a positive answer is cached now.
- **Releasing a frame left Blizzard's own display stripped.** Every decoration
  this addon silences â€” borders, shadows, the out-of-range veil â€” was pinned
  at alpha zero by a hook that never stopped. Switch the takeover off, or move
  a spell off a bar, and Blizzard got back an icon with its decorations
  permanently removed until a reload. What each region looked like before is
  now recorded and restored, the rounded-corner mask included.
- **A released frame lost its border for good.** `PaintBorder` never showed the
  chrome frame it paints into, and releasing hides it â€” so a spell that left a
  bar and came back had no border for the rest of the session while the
  addon carefully set textures on a frame nobody could see.
- **"Centre on screen" did not centre an edge-pinned bar** â€” it wrote 0 into
  the pinned point's offset, which puts that edge on the centre line. The menu
  entry and the three tool buttons now translate the same way the drag always
  did.
- **Hiding the overlay was a dead end.** It hides every mover, so the
  Shift-right-click that got you there cannot get you back, and the only
  button that can still read "Hide overlay". It follows the state now.
- **Selecting a smaller bar left the selection past its end** â€” "slot 9 of 6",
  with the arrow keys nudging a cell that does not exist.

### Removed

- **Arc and Diagonal.** The owner reported that they threw errors and did not
  look good; both were true enough that keeping them was not worth the six
  settings they cost. The geometry itself was correct and tested, so if either
  ever returns the fault to look for is in the panel around it. A saved bar
  still on one is migrated onto Grid with its cells intact, and the self test
  now asserts that neither is offered again.
- **The "Build on screen" row in the settings panel.** It was a second button
  for what the bar card already does, on a page you have to open first, and
  its control sat on top of its own sublabel. The card's button is renamed to
  **Build on screen** and is now the only way in.

### Changed

- The Backdrop section says where the plate is actually visible. It sits
  BEHIND the icon, and spell art is opaque â€” so on a square icon you will
  never see it, whatever texture is picked. That was the other half of "the
  textures are not applied", and it is a fact about the layer rather than a
  bug.

## [4.7.0] - 2026-08-07

A bug-fix release with two additions that exist because of the bugs. Nine
defects, one of them reported from the game and the other eight found by
reading the code that the reported one pointed at.

### Fixed

- **Switching pattern scattered the bar, permanently.** Reported: change the
  arrangement and it does not come back. Entering the puzzle wrote each cell's
  spread-out POSITION into the same two fields a nudge uses, and every other
  arrangement adds a nudge on top of the slot it worked out â€” so coming back
  to a grid displaced every cell by where the puzzle had put it, for ever,
  with nothing anywhere that would remove it. The puzzle now has two
  coordinate fields of its own. Neither arrangement can see the other's, so
  moving into the puzzle, arranging it, going back to a grid and returning now
  finds the puzzle exactly as it was left.
- **The Columns slider destroyed the arrangement.** Every change compacted
  every spell to the front, which meant a deliberate hole in a row was gone
  after one drag and there was no way back. Cells now keep their index, so
  6 â†’ 12 â†’ 6 returns exactly what was there.
- **The Columns slider deleted spells.** Shrinking a grid dropped whatever no
  longer had a cell. Anything that does not fit is now parked and comes back
  to its own slot the moment the bar is big enough again â€” a slider you drag
  to see what it looks like must not be able to lose your work.
- **Moving into the puzzle flattened every arrangement that was not a grid.**
  It re-derived a plain row out of rows and columns, so an arc arrived as a
  line. The puzzle is now seeded from where the cells actually are.
- **Coming back from the puzzle re-shaped the lattice.** A 3Ã—2 grid returned
  as a row of six. Rows and columns were never touched while the bar was away,
  so they are simply left alone now.
- **The Opacity slider moved half a bar.** It was applied to adopted Cooldown
  Manager frames and not to the cells this addon draws itself, so a mixed bar
  faded unevenly.
- **A swapped spell arrived lit up.** Cells are reused for whatever spell ends
  up at their index, and the aura clock and the effects' "was it ready a
  moment ago" were not reset with them â€” so a moved icon could show the
  previous spell's sweep and fire a ready-flash for a transition that belonged
  to a spell no longer on the bar.
- **Effects were inverted on auras this addon draws.** "Ready" was read as
  "the buff is NOT up", so the ready glow lit every proc that was down and the
  ready flash fired when one ran out rather than when it landed. An aura cell
  has no cooldown to be ready; the cooldown effects now stand down there, and
  the flash fires when the proc arrives.
- **The editor explained a rule the renderer did not apply.** In an instance
  type this addon has never heard of, the visibility panel named "not in this
  kind of place" as the reason a bar was hidden â€” while the renderer,
  correctly, showed it. One shared test now answers both.
- **Bar settings hid themselves.** Turning one cell of an icon bar into a
  tracking bar in build mode gave you a cell whose width, height, name and
  fill settings were all hidden on the page that owns it.

### Added

- **Tracking bars this addon draws have a fill.** They had none: a bar-shaped
  aura was a square icon and a hole beside it. It is a real status bar, it
  wears any LibSharedMedia texture â€” the twenty shipped here included â€” and it
  drains on the clock this addon owns. Colour, opacity, texture and a fill-up
  direction, with the texture defaulting to the backdrop's so a bar reads as
  one object. Adopted buff bars bring Blizzard's own and ignore all of it,
  which the panel says out loud.
- **`/zs test`.** Forty-eight checks that can only run inside the game, which
  is every check this addon has: arrangement geometry, the two coordinate
  systems, pattern round trips, the rows and columns sliders, the visibility
  rules against their own explanations, and a read-only pass over your bars.
  It runs on throwaway configs and never touches your data. Against the code
  as it stood this morning it reports eight failures â€” that is what a
  regression test is for.
- **Straighten.** Under Arrangement, and only when there is something to
  undo: puts every cell back where the pattern wants it, leaving the puzzle's
  own positions alone.

### Migration

Saved variables move to version 3. A bar already in the puzzle has its
positions carried across with certainty. On any other arrangement a leftover
offset cannot be told apart from one you meant, so those are counted and
reported once at login, with a pointer to Straighten â€” reported rather than
guessed at.

## [4.6.1] - 2026-08-07

### Added

- **Twenty bar textures, shipped.** Flat, Smooth, Velvet, Charcoal, Gloss,
  Glass, Steel, Bevel, Inset, Neon, Outline, Ridged, Aluminium, Stripes,
  Blocks, Pixel, Cylinder, Hairline, Split and Frost. They go into
  LibSharedMedia under a `ZS` prefix, so they sit next to everything ElvUI,
  WeakAuras and the rest registered â€” and they are available to those addons
  in return. Generated rather than drawn: each one is a formula for "how
  bright is this bar at this height", and they are white-based because a bar
  texture is tinted by whoever draws it.
- **Drag a spell from the list onto a cell.** It genuinely was not
  implemented â€” clicking worked and always has, but picking a spell up and
  putting it where you want it is the gesture people reach for first. The
  cell under the cursor lights up while you drag, across every card.
- **A tool panel in unlock mode.** Grid and its step, snap to it, snapping and
  how far it catches, dim, permanent coordinates â€” saved, because they are
  working habits. Plus the selected bar's pattern, shape, sizes, spacing,
  scale and centring.
- **A logo.** A cooldown sweep closing around a two-tone 12.

### Changed

- **The bar card is a real preview.** It paints with the bar's own backdrop,
  texture, border and crop, through the same two functions that paint the
  thing on screen â€” so picking a texture shows you that texture, in the
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

### Added â€” arrangements

A bar is no longer rows and columns with a gap. There are five arrangements,
they all come out of one engine (`Core/Layout.lua`), and the editor preview
asks that same engine â€” so an arc curves in the window too.

- **Grid** â€” rows and columns, as before.
- **Staggered** â€” every other line pushed along by half a cell.
- **Arc** â€” cells around a circle. Span, start angle and radius are set; a full
  360 closes the ring, and the radius works itself out from the chord of the
  step angle unless you name one.
- **Diagonal** â€” each cell steps by a fixed offset. Steps, ladders, slants.
- **Puzzle** â€” every cell exactly where you dragged it. No lattice at all.

With them: **fill order** (rows first or columns first), **reading direction**
on both axes (left to right or right to left, top to bottom or bottom to top),
and **which point the bar is pinned by**. That last one is what people mean by
grow direction: pinned by the centre a bar spreads both ways when it gains a
row, pinned by an edge it grows away from that edge.

Puzzle is not a special case bolted on. Every arrangement adds each cell's own
offset on top of whatever the lattice worked out, so nudging one icon out of a
neat row and building a free-form layout are the **same edit**. There is no
line to cross between "a bar" and "a puzzle".

### Added â€” per-cell overrides

Any single cell can now carry its own scale, its own offset, its own kind and
its own visibility. One icon in a row at 150%. A tracking bar in among the
icons. A slot hidden while you decide. The overrides travel with the SPELL,
not the position â€” dragging a cell to another slot takes its settings along,
and re-flowing a grid carries them in the same sequence the spells move in.

### Added â€” build mode

`/zs build`, the **Build** button on every bar card, or the switch in the
unlock toolbar. Two modes, and the difference is the level you work at:

- **Move bars** â€” the whole bar is one object. Drag, snap, attach.
- **Build** â€” every cell is its own object. Drag it (snapped to the bar's
  raster, Alt for free hand), scroll to scale it, Tab through the slots, arrow
  keys to nudge, Delete to empty, right click for kind, hide and reset.

The **spell palette** opens beside it: click a slot, click a spell, and the
selection walks on to the next slot so filling a bar is one click each. Every
Cooldown Manager spell is in it, greyed when it is not talented â€” a bar can be
built for the spec you are about to switch into.

### Added â€” effects

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
table every item frame carries â€” the field names are taken from working code
on this machine, never guessed. Without the GCD test every spell in the game
"comes off cooldown" every 1.5 seconds and the flash is a strobe. Both fields
can arrive as secret values on 12.0, so both go through `ns.CanCompute` first
and an unreadable state means *do nothing* rather than *guess*.

Remaining time is deliberately **not** read for adopted frames: there is no
field for it and the Cooldown widget's timing is a duration object on this
patch. The option that needs it says so.

### Added â€” when a bar is on screen

Rules per bar, and every rule is an AND: combat, group size, target, rested,
and six kinds of place (world, dungeon, raid, scenario or delve, battleground,
arena). Every rule defaults to "any", so one you have not set can never be the
reason something is missing. Out of condition, a bar is gone â€” or dimmed to
whatever you choose, which is what you want while you are still arranging it.

Evaluated on the events that can change the answer and never on a timer. The
instance types are read off working code rather than written from memory, and
a type the client reports that this list has never heard of lets the bar
through: a new instance type in a patch must not make everyone's UI vanish in
the new content.

### Changed â€” the window

The density pass that was owed. Every setting used to be a filled card 38px
tall with a gap around it; forty of those is a brick wall, and "altbacken, viel
space wasted" was right.

- Rows are **flat**, 28px, separated by a hairline instead of a gap. Only the
  row under the cursor gets a surface.
- Section headings are smaller, their air is above them rather than evenly
  around them, and the fold marker is a drawn plus/minus â€” the old `v`/`>`
  were two glyph widths and shifted the caption every time a section folded.
- Buttons, switches and steppers all came down a notch to match.
- The bar preview in the middle column now draws the **real arrangement**,
  hit-tested against the real rectangles rather than divided out of a lattice.

### Notes

- Nothing here has been run in the game yet â€” the client was closed while it
  was built. Statically clean over 24 files.
- Saved settings carry forward untouched: every new key has a default, and a
  bar written before this release is a Grid with no effects and no rules.

## [4.4.0] - 2026-08-06

The bars are on screen, and there is an unlock mode to put them where you
want them. Also: the addon is called **ZwoelfStuff** now.

### The name

`DKstuff` was never right â€” the addon is not about Death Knights, it is about
cooldowns. It is named after the character it was written on: **ZwÃ¶lf**, EU
Destromath. Spelled `Zwoelf` everywhere, because a folder name, a slash
command and a saved-variables key are all worse places for an umlaut than a
signature is.

Your settings come with it. The saved variables were migrated on disk; if you
ever see an empty addon, the old file is still sitting next to the new one.

### Added â€” the display

Everything you arranged in the window now actually renders, and a cell holds
one of exactly two things:

- **A Cooldown Manager cooldown.** It is not drawn â€” Blizzard's own frame is
  *adopted* and moved onto your cell. That frame has the correct icon, swipe,
  charges, stacks and timing, all computed inside the game where secret values
  are not a problem. Drawing our own would mean reading aura data, which patch
  12.0 forbids outright.
- **An aura proc.** No frame exists to adopt â€” that is why `Core/Auras.lua`
  exists at all â€” so the icon is drawn and the clock is ours, started by the
  glow on the ability the aura empowers and running for the duration that was
  *measured* rather than assumed.

The rules for touching Blizzard's frames are not style advice, and they are
taken verbatim from the reference implementation on this machine:

> Never SetParent/SetScale/Hide/Show on Blizzard frames Â· Never move Blizzard
> frames offscreen Â· Never write custom keys to Blizzard frame tables Â· All
> per-frame data in external weak-keyed tables Â· Unclaimed frames: SetAlpha(0)

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
right â€” so by default the cooldowns you did not place are hidden too. Switch
*Take the display over* off and you get Blizzard's row back, holes included.

### Added â€” Unlock Mode

Built to work the way EllesmereUI's does, because that is what this addon is
used next to and a second set of rules for "how do I move a thing" is a tax on
the user, not a feature.

- Every bar gets a labelled panel with its **live coordinates**.
- **Drag** it, or select it and **nudge with the arrow keys** â€” Shift for 10.
- It **snaps** to the screen centre and to the other bars' centres and edges,
  with a guide line showing what it snapped to. **Alt** switches snapping off
  while you drag, because "almost always right" is why there has to be a way
  out in the moment.
- A **cog** on each panel: bar options, centre on screen, centre on one axis,
  switch the bar off.
- **Shift + Right Click** hides the overlay so you can see what is underneath.
  The panel stays, or that would be a one-way door.
- A **grid**, and Escape leaves.

Positions are always the bar's centre offset from the screen centre â€” one
anchor for everything, which is what makes the readout mean something and
snapping arithmetic instead of a case analysis.

**Bars can be attached to each other.** Snapping puts a bar next to another
one *once*; attaching keeps it there â€” move the one it hangs on and it comes
along, resize the one it hangs on and it stays flush. That is the difference
between arranging a layout and rearranging it every time you change your mind.
The cog offers it, and afterwards the same menu switches the side. An attached
bar's readout shows what it hangs on, and dragging it adjusts the *offset*
rather than a screen position it no longer owns.

Bars have a real id now, because an attachment has to survive a delete
reshuffling every index below it. Ids are never reused. Deleting a bar sets
whatever hung on it free where it stands, a loop is refused before it can be
made, and both are checked again at login â€” the menu cannot produce a broken
state, but saved variables are a file on disk and files get edited.

### Added â€” the proc database is a file now

`Core/KnownProcs.lua`. It is data that grows with every export, and having it
in the middle of six hundred lines of logic made "paste your export here" mean
"edit around the machinery". It ships with the addon, so a fresh install
already knows what the spec's procs are.

- **`/zs auras forget` now works on shipped entries too.** Deleting one that
  the addon carries could only ever last until the file loaded again, so a
  thrown-away entry is remembered as thrown away.
- **`/zs auras remember`** puts every one of them back â€” the way out of
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
  the button went down on, and you can let go anywhere â€” including over
  another window or off the edge of the screen.
- **The aura catalogue was rebuilt once per cell.** A talent scan, forty times
  over, for one spec change. Built once per render pass now.
- **A hidden cell still answered the glow that drives it**, so shrinking a
  grid left a clock running on something nobody could see.
- The minimap button shows the addon's own icon instead of whichever aura was
  being tracked â€” that changed under the user and made the button hard to find
  again on a busy minimap.

## [4.3.0] - 2026-08-06

Auras â€” the ones Blizzard's Cooldown Manager does not carry.

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

The aura's real ID is not needed for the glow route at all â€” we never query
the aura, we draw an icon and run our own clock â€” so what is displayed is a
*choice*, not a lookup.

### Added

- **An Auras group** in the spell list, with its own filter button.
- **It fills itself.** Every proc this character raises is recorded, per class
  and spec, while you play. No learn mode, no button, no timing. A proc nobody
  knew about announces itself once in chat and is in the list from then on.
- **The duration is measured, and it knows when it is guessing.** The time
  between `GLOW_SHOW` and `GLOW_HIDE` is the duration â€” but only if the glow
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
  and switches by itself. Availability is probed by *building* a container â€”
  the previous version gated on `LoadAddOn("Blizzard_AuraContainer")`, there is
  no such addon, and that gate could never open. Set the aura ID with
  `/zs auras bind <glowID> <auraID>`.
- `/zs auras`, `/zs auras icon <glowID> <spellID>`,
  `/zs auras forget <glowID>`.
- **Tooltips on every spell**, in the list and on the cells. The game's own
  tooltip, via `GameTooltip:SetSpellByID` â€” what a spell does is Blizzard's
  text to keep current, and anything written here would be a second version of
  it going quietly out of date. Underneath it, only what the game cannot know:
  where the spell already sits on your bar, what actually drives an aura, and
  what a click would do.

### Tried and rejected

**Reading the link out of talent descriptions.** The idea was sound â€” the text
does name abilities, and matching it against the client's own spell names is
locale-independent, since both sides come from the same client in the same
language.

It answers the wrong question. The description names the ability a talent
**modifies**, not the one that lights up: *Foul Bulwark â†’ Bone Shield* means
"makes Bone Shield stronger". On the one case that could be checked it returned
**Heart Strike** where the confirmed answer is **Blood Boil**. And of the 48
candidates it produced, nearly all were passives that grant no trackable aura
at all.

The scan is kept, demoted: it now runs in the useful direction â€” *which talent
mentions this ability* â€” purely to suggest a caption, where being wrong costs a
label and nothing else. Its one real bug is fixed along the way: it kept only
the longest name match per talent, which hid Blood Boil behind Heart Strike.

### Fixed in the first live test

Three bugs the static check could not see, all found by running `/zs auras`
on a real character rather than trusting the code:

- **Every aura reported "no route"** â€” so nothing could ever have been
  displayed. `Route()` read `entry.parent`, but in the proc store the glowing
  spell is the *key*, not a field. It is passed in explicitly now.
- **The export would have shipped wrong data.** It read the raw recording
  instead of the merged view, so the bundled display was invisible to it and
  the caption fell back to a guess: Blood Boil came out as *Hemostasis*
  instead of *Boiling Point*, and pasting that in would have overwritten the
  one correct entry. It uses the merged view now.
- **A measured duration overwrote the shipped one** â€” Boiling Point dropped
  from 15s to 4s. Every measurement is a *floor*, because casting the
  empowered ability ends the glow early. Longest wins, including against the
  shipped value.
- `Defile on Defile` â€” when nothing better is known the icon simply *is* the
  glowing ability, and saying it twice reads as a fault.
- **An error on every login.** `ADDON_LOADED` called `ns.Auras:Seed()`, and
  that function never existed. Nothing was lost â€” it was the last line of the
  block â€” but it threw each time. There is no seeding step *by design*: the
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

Owner review of 4.1.0 â€” *"schon viel besser!"* â€” with five things to fix.

### Added

- **Two add buttons instead of one**: *Icon bar* and *Tracking bar*. The two
  are a different thing to build, not a setting you change afterwards â€” they
  want different sizes, a different default grid and a different place on
  screen â€” so choosing up front means the first one is already right.
- **The spell list is grouped**: Cooldowns, Utility, Buffs, Buff bars, each
  under its own heading with a count, with filter buttons above to jump
  straight to one. The category comes from
  `Enum.CooldownViewerCategory.Essential / .Utility / .TrackedBuff /
  .TrackedBar`, read off working code on this machine rather than guessed, and
  every lookup is nil-safe: a renamed member costs one heading, not the list.
- **Green for what is already on the selected bar** â€” a stripe down the left
  edge, the name in green, and the cell it sits in. Only the selected bar: the
  same spell may sit on three others, and marking it here would answer a
  question nobody asked.
- **Greyed out for what the current talent build does not have**, sorted to
  the end of its group. Still pickable, because a bar is often built for the
  build you are about to switch into. Uses
  `C_SpellBook.IsSpellKnownOrInSpellBook` â€” the reference CDM picker still
  calls the deprecated `IsPlayerSpell`; BigWigs on this client already uses
  the current form. A missing API means "assume known": greying out everything
  would be far worse than greying out nothing.

### Changed

- **One rule under every heading**, spanning the whole window at the same
  height in all three columns â€” including under ZwoelfStuff itself. Three separate
  lines with three sets of padding never quite agree, and the eye reads the
  disagreement as sloppiness even when the heights match. It lives on a chrome
  frame above the columns, because a texture on the window itself is painted
  *under* its own child frames no matter which layer it claims.
- **A more modern surface set**: a graphite palette with wider steps between
  the levels, a dedicated `well` for anything recessed, and `edge` for a
  card's own outline.
- Empty cells are **recessed wells** rather than raised tiles â€” a slot waiting
  to be filled reads differently from a button.
- The selected function in the left column is marked with **an accent bar and
  a neutral fill**, not a block of tinted orange that muddied its own label.
- New **soft** button weight: the accent is in the text, not the fill. The two
  add buttons use it, so the bars stay the thing you look at.
- The `Shape` setting is now **Kind**, with *Icon bar* and *Tracking bar*, the
  same words as the buttons that create them.
- The right column is headed **Spells**, not "Cooldowns" â€” it sat next to a
  middle column with the same title.

### Fixed

- **The spell list showed duplicates** â€” Anti-Magic Shell twice, Blood Boil
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
| left | **the functions** â€” Cooldowns, Aura Display, Settings, Diagnostics, About, Changelog |
| middle | **every bar you own**, under each other, scrollable, plus *Add new bar* at the bottom of the stack |
| right | **every cooldown**, listed in full â€” or the settings for one bar while its Options are open |

The left column no longer lists your bars. Listing them there meant picking
one before you could see any of them, which is exactly backwards for a thing
whose whole point is having several.

### Added

- **The middle is the overview.** Each bar is a card that *is* the bar â€” same
  grid, same order, same sizes â€” with **Rows** and **Columns** as two sliders
  directly underneath it. Change one and the card changes shape under your
  hand. A grid too wide for the card is scaled to fit rather than clipped, so
  the arrangement stays honest.
- **Add new bar** sits at the bottom of the stack, where the next bar appears.
- **The spell list is always there.** Everything your Cooldown Manager knows,
  searchable, with a manual spell-ID box. Click a cell, click a spell â€” and
  the selection moves on to the next empty cell by itself, so filling a bar is
  click, click, click rather than click, aim, click, aim.
- **Options per bar**, reached from the card header and shown in the right
  column: name, shape, icon size or bar size, spacing, row gap, scale,
  opacity, border and border colour. *Done* goes back to the spells.
- **A look can be reused** â€” copy it from another bar in one click, or save it
  as a named preset and apply it to any bar later, deleting presets from the
  same menu. Only sizes, spacing and colours travel; the spells and the grid
  stay with their own bar, because those are what make it that bar.

### Changed

- **Nothing in the window is see-through.** A translucent panel over a moving
  3D world is unreadable, and the depth a glass effect only suggests is now
  done properly with distinct opaque surfaces â€” work area, window, side
  columns, cards, controls â€” each one step apart. Hairlines are opaque
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
| Read an aura | blocked â€” aura fields are secret values |
| Hand one to the engine | impossible â€” `AuraContainer` arrives in **12.1** |

Measured on the live client: `CreateFrame("AuraContainer", â€¦)` fails, and
EllesmereUI gates every one of its own AuraContainer files behind
`select(4, GetBuildInfo()) >= 120100`. So the proc-glow route was never a
workaround for a broken lookup â€” it was the only thing possible.

Blizzard's **Cooldown Manager** already solved this. It knows every tracked
cooldown and buff, owns frames that display them with correct icons, swipes,
charges, stacks and timing, and does it inside the game where secret values
are not a problem. Every addon that "does cooldowns" on this patch works the
same way â€” it parses nothing and restyles Blizzard's item frames. EllesmereUI
says so in one line at the top of its own CDM file: *"Does NOT parse secret
values, works around restricted APIs."*

### Added

- **`Core/CDM.lua`** â€” the Cooldown Manager layer: finds the four viewers,
  enumerates their live item frames, resolves what each one is, and pins them
  where we want against Blizzard's own re-anchoring.

  Two details taken from the reference rather than invented: the **frame pool
  is the ground truth** for what is displayed (the static category API says
  where a cooldown *belongs*, but Edit Mode and per-spec layouts move it), and
  Blizzard re-anchors constantly, so position and size are held by hooking
  `SetPoint` and `SetSize` and re-asserting.
- **`Core/Bars.lua`** â€” a bar is a grid of cells, each holding one spell.
  Cells are stored in reading order, so changing the column count re-wraps
  what is there instead of scrambling it, and shrinking a grid compacts rather
  than silently dropping the cells that no longer exist.
- **The bar editor** â€” pick the bar, set rows and columns, see the grid, fill
  it. The grid on the options page *is* the bar: same rows, same columns, same
  order, nothing to translate. Click an empty cell to choose a spell, drag one
  cell onto another to swap, right click to clear.
- **Spell picker** sourced from the Cooldown Manager, so anything in the list
  is guaranteed to have working timing. Manual IDs still accepted.
- `/zs cdm` â€” what the Cooldown Manager currently holds, per viewer.
- `/zs bars` â€” list, add, remove.

### Parked until 12.1

`Engine`, `Catalog`, `Probe`, `Groups`, `CoTanks` and `OptionsGroups` are out
of the TOC. They are inert on a 12.0 client, not wrong â€” the reason is written
next to them in the TOC. The proc-glow display for Boiling Point stays, since
that buff is not in the Cooldown Manager data set and this is the only way to
see it.

### Not yet

Bars render nothing on screen. The editor comes first, and is signed off
first â€” building on unverified foundations cost this project two full rounds
already.

## [3.4.0] - 2026-08-05

### Fixed

- **The aura engine reported itself unavailable on every client.** Every
  engine-backed feature was therefore dead: the display's aura slot, the
  co-tank aura strips, and every tracking group. The only thing that ever
  worked was the proc-glow route â€” which is why a group with several spells
  showed exactly one icon, and that icon was the classic display, not the
  group.

  The availability check began with
  `C_AddOns.LoadAddOn("Blizzard_AuraContainer")` and returned false when it
  failed. **There is no such addon.** `AuraContainer` and
  `CustomAuraContainerTemplate` are built into the client; every reference
  implementation on this machine simply calls `CreateFrame` â€” EllesmereUI
  gates on the build number, NorthernSkyRaidTools pcalls the creation. The
  gate could never open, on any client, ever.

  The check now builds a container, verifies `AddAuraGroup`, `AddAuraSlot`
  and `SetUnit` exist on it, and caches that. When it says no it now says
  *why*, instead of a bare "not available" that reads like a client problem.

### Added

- **`/zs group status`** â€” per spell, one of three answers: *slot refused*
  (a bug here, printed with the engine's error), *registered but never seen*
  (the slot is fine, the ID is wrong or the aura has not been up), or
  *bound*. This is what turns "only one icon shows" into something
  actionable in one command.
- Slots the engine refuses now report it in chat instead of disappearing into
  a `pcall`, and they keep their position in the order rather than silently
  closing the gap â€” a shorter row otherwise looks like a layout setting.

## [3.3.0] - 2026-08-05

### Added

- **`/zs probe <spellID> [seconds]`** â€” the decisive test for "can this be
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
  proxy frame the addon moves, and engine containers come mouse-enabled â€” only
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
- **Sidebar navigation** â€” Tracking Groups, Aura Display, Co-Tank Panel,
  General, Diagnostics, About, Changelog â€” with a titled content area and a
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
- Changelog data moved to `Core/Changelog.lua` â€” it only grows, and it is data,
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
  never had `Hide` / `Show` / `SetShown` â€” the group anchor called `Hide()` on
  its outline and hit a nil. The three visibility methods now exist on the
  border helper, where they belonged all along.
- **One broken feature disabled every feature after it.** The login handler ran
  Display â†’ Watcher â†’ Groups â†’ Co-Tanks â†’ Minimap in one straight line, so the
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
fell back to the proc-glow route â€” which is why route 5 looked like the only
thing that worked.

A second, independent bug in the same code: the container was given its unit
*before* its content. Unit assignment re-evaluates event registrations, and
those are gated on the container already having groups or slots, so
`UNIT_AURA` stayed unregistered and the container never updated. Content
first, unit last, then `UpdateAllAuras()`.

Both are documented as rules 1â€“5 at the top of `Core/Engine.lua`.

### Added

- **Tracking groups.** Any number of them, icons or bars, each with its own
  spells, unit, filter, position, size, colours and text settings.
- **Arrangement.** Grows rightwards or leftwards, rows downwards or upwards,
  fills by rows or by columns, wraps after any number for a grid. All of it
  applies live, in combat included â€” layout only touches frames the addon
  owns.
- **Two ordering modes.** *My order* gives every spell one fixed engine slot
  that never moves, so a missing aura leaves its place empty instead of
  letting the next one slide in; bars can show spell names, because the slot's
  spell ID is ours and therefore plain. *Auto* uses one engine group with
  engine sorting: compact, but positions move and no name can be shown â€” which
  aura sits in which button is exactly the secret the engine keeps.
- **Spell browser.** Reads the running client: the talents you have actually
  purchased (walked through `C_Traits` from the active loadout), every
  spellbook skill line â€” including the specs you are **not** playing, which
  come back with a non-zero `offSpecID` â€” and Blizzard's own Cooldown Manager
  data set. Nothing is hardcoded, so it follows every respec and every patch by
  itself. Search by name or ID; talented spells are marked and sorted first.
  Manual spell IDs still work.
- **Bars that actually drain.** `button:SetDurationBar(bar, opts)` hands a
  StatusBar to the engine, which drains it from the aura's own duration, GPU
  side. It works for auras no addon may read.
- `/zs groups`, `/zs group add|remove|list`, `/zs catalog`.
- `Core/Widgets.lua` â€” the option controls, shared between pages: steppers,
  segmented choices, colour swatches, scroll areas. Still no external library.

### Fixed

- **Co-tank size steppers changed nothing.** They fell through to the shared
  stepper's default apply action, which re-lays-out the classic display â€” the
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
  both are visible at first â€” compare them and switch off whichever you do not
  want.
- Rebuilding a group only happens when something *baked into the widgets*
  changes (style, colours, fonts, spell list). Position, size, spacing, growth
  and wrapping are live, because the engine buttons are anchored to proxy
  frames the addon owns and moves.

## [2.1.0] - 2026-08-05

### Added

- **Minimap button.** Left click opens the settings, right click toggles the
  co-tank panel, drag moves it around the minimap edge (the angle is saved).
  Self-built, no LibDBIcon â€” the round shape comes from
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
  Auras on other players are secret exactly like your own â€” a co-tank's boss
  debuff stacks cannot be read by an addon at all â€” so each row owns two
  `AuraContainer`s (HARMFUL and HELPFUL) and the engine binds, shows and times
  them. `/zs tanks`, `/zs tanks unlock`, plus a **Co-Tanks** options tab.
- **Engine aura slot for the tracked buff.** `AddAuraFilter` with
  `candidateFilters.includeSpellIDs` binds the real Boiling Point aura â€” real
  icon, real duration, real stacks â€” instead of proxying it through the proc
  glow. `/zs source engine` / `/zs source glow` switches; the glow route
  remains and still drives the proc flash.
- `Core/Engine.lua` â€” the shared engine layer, with a cached availability probe
  and a combat-lock guard, so both features degrade instead of erroring.

### Fixed

- **The options window clipped its last section.** The proc glow row was added
  without raising the window height. The height is now derived from a written
  content budget, with a comment saying to recount it when adding a section.
- Five reserved aura rows left a large empty gap above the input; now three.
- The inactive greyed-out state dimmed the whole root frame, which would have
  dimmed the engine's aura button along with it â€” engine-bound children inherit
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
Not just Boiling Point â€” *every* buff on the player was secret. The four
cooldown viewers meanwhile handed out plain spell IDs and readable
`auraInstanceID`s (Death and Decay, Bone Shield, Blood Shield, Hemostasis,
Dancing Rune Weapon), but none of them was Boiling Point.

So the conclusion is not "our lookup is broken". It is: **the buff itself
cannot be read by any addon.** Aura identification is closed, and the one
sanctioned channel that stays open â€” the Cooldown Manager â€” does not carry
this spell. That is exactly the gap this addon exists to fill.

### Added

- **Route 5: proc glow.** Boiling Point empowers Blood Boil, and
  `C_SpellActivationOverlay.IsSpellOverlayed(50842)` is a plain boolean that
  never touches aura data. The display is driven off that, with timing from our
  own clock and our own duration constant â€” plain numbers we own, so the swipe
  and the countdown work normally.
  This is the same combat-safe technique `EllesmereUIAuraBuffReminders` uses for
  beacons it cannot read either ("Standalone Beacon Reminders â€”
  IsSpellOverlayed-based, combat-safe").
- `/zs glowlog` â€” logs every `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE` with
  spell ID and name, so the right ID is read off the client rather than guessed.
- `/zs glow <spellID or name>` â€” sets the proc source; a name is resolved via
  `C_Spell.GetSpellInfo`, so no ID is ever hardcoded. `/zs glow off` disables.
- `/zs glowduration <seconds>` â€” proc length, default 15.
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
reason, route 5 cannot tell them apart â€” the glow is the signal, not the aura.
`/zs glowlog` shows exactly which spell IDs fire, so a more specific source can
be chosen when one exists.

## [1.3.0] - 2026-08-05

Still not found in game â€” all three routes reported `not found`. This release
widens the search and, more importantly, adds the diagnosis that shows what
actually exists instead of testing one hypothesis at a time.

### Fixed

- The cooldown viewer route only searched `BuffIconCooldownViewer` and
  `BuffBarCooldownViewer`. It now searches all four viewers, adding
  `EssentialCooldownViewer` and `UtilityCooldownViewer` â€” a proc can be
  registered in those categories too.

### Added

- **Fourth route: icon match.** The icon of *our* spell ID is always plain, so
  comparing it against a readable aura icon is legal. Catches secret auras that
  keep a readable icon. Last in priority, because two buffs can share an icon.
- `/zs dump` â€” dumps every entry of all four cooldown viewers (spell ID, name,
  shown state, whether timing is available) and every player buff (readable ones
  with ID and name, secret ones counted with their aura instance), marking any
  icon match. Must be run **while the buff is up**.
- `/zs check` reports all four routes.

## [1.2.0] - 2026-08-05

Boiling Point was still never found. 1.1.0 stopped the errors but not the
silence â€” because a secret rotational proc is invisible to *both* aura reads.

### Fixed

- **The tracked aura was never detected.** `GetPlayerAuraBySpellID` and
  `GetAuraDataBySpellName` both return nothing for secret-flagged rotational
  procs, no matter how correct the spell ID is. Confirmed in game: `/zs check`
  reported `not found` on both routes while the buff was up.

### Added

- **Third lookup route: Blizzard's cooldown viewer buff frames**
  (`BuffIconCooldownViewer`, `BuffBarCooldownViewer`). Their item frames still
  bind such procs and expose a plain `auraInstanceID` plus `auraDataUnit` â€”
  which is enough for presence, duration and stacks. Matching goes through
  `C_CooldownViewer.GetCooldownViewerCooldownInfo`, comparing `spellID`,
  `overrideSpellID`, `linkedSpellIDs` and finally the spell name.
  The irony: the Cooldown Manager refuses to let you *add* this buff, yet it
  knows exactly when it is up.
- `/zs scan` â€” lists the buffs an addon is allowed to read and counts the
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
  fields into *secret values*, and tainted code â€” which every addon is â€” may
  not use a secret as a table key. Matching `tracked[aura.spellId]` did exactly
  that. The whole scan-and-compare design was invalid on 12.x.

### Changed

- **Aura lookup reversed.** Instead of scanning auras and comparing their spell
  IDs, the spell ID now goes *into* the query via
  `C_UnitAuras.GetPlayerAuraBySpellID`. No secret is ever read.
- **Fallback lookup by spell name** via `C_UnitAuras.GetAuraDataBySpellName`,
  for auras whose applied ID differs from the tooltip or talent ID.
- **Cooldown swipe armed from a DurationObject**
  (`C_UnitAuras.GetAuraDuration` â†’ `Cooldown:SetCooldownFromDurationObject`).
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

- `/zs check <spellID>` â€” reports whether that aura is findable right now, and
  by which route (ID or name). Distinguishes a wrong spell ID from a broken
  display.
- `/zs status` â€” what is tracked, what is currently active, and the current
  display settings.
- **Diagnose** button in the options window, running both of the above.

### Removed

- The "red timer in the last 3 seconds" option. It required comparing a secret
  value against a threshold, which is not permitted.

## [1.0.0] - 2026-08-05

### Added

- Isolated aura display â€” shows a single buff the Cooldown Manager cannot
  track, because it only offers spells from its own `C_CooldownViewer` data set.
- Ships tracking spell **1265968** (Boiling Point, Blood Death Knight, 15s).
- Two display modes: **icon** with cooldown swipe, stack count and remaining
  time, or **bar** with an icon plus a status bar and spell name.
- **Always show** option that keeps the display on screen while the aura is
  down, greyed out and desaturated.
- Self-built proc glow (expanding ring plus flash) and an optional proc sound.
- Movable and lockable display with a 15 second test preview for positioning,
  plus a reset-position action.
- Additional spell IDs can be tracked; the list doubles as a priority order â€”
  the first entry present on the player wins.
- Tabbed settings window (Options / About / Changelog), reachable via `/zs`
  or the addon compartment.
- Full slash command set under `/zs`, `/zwoelfstuff`.

[1.1.0]: https://github.com/zwoelf/ZwoelfStuff/releases/tag/v1.1.0
[1.0.0]: https://github.com/zwoelf/ZwoelfStuff/releases/tag/v1.0.0
