# Changelog

All notable changes to ZwoelfStuff are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.83.0] - 2026-08-15

### Removed

> The bars were taken out and are being **rebuilt from the ground up** in this
> same version — see Added. What follows is what the old implementation cost
> and what it left behind, because the rebuild reads the settings it wrote.

- **The old cooldown bars are gone.** In the owner's words: *"CDM is gone. I will
  put my focus on tank and group play features, and there are a lot of other
  very good CDM addons that do the job better."* Out with them went the
  renderer, the bar editor and its options page, the bar movers in Edit Mode
  and everything that adopted Blizzard's Cooldown Manager frames — around
  8 800 lines, a sixth of Core.
- **What stayed, and why.** `CDM.lua` still reads the Cooldown Manager, and
  four features depend on it: the reminders ask which frame is showing a
  spell and whether it is active, the co-tank panel and the death log read
  its catalogue, and the spell pickers list what it knows. That half of the
  file is untouched. **Edit Mode stays too** — it still places the co-tank
  panel, the taunt bar, requests, answers, the raid bar and the reminders;
  only the bar-building half was removed.
- **Your saved bars are not deleted.** Nothing in this release writes to
  `bars` in your saved variables. Roll back and they are where you left them.

### Added

- **The cooldown bars are back, rebuilt.** Blizzard's Cooldown Manager draws
  the icons and knows the timing — on this patch no addon can do either for
  itself — and this arranges them on bars you build. What is in this release:
  - **A page you can actually see the bar on.** The lattice sits in a band at
    the top, every spell this character can be shown is in the third column,
    and the settings are underneath. The preview is drawn by the same function
    that draws the screen, so a staggered pattern, a bar that fills downwards
    or one that grows leftwards looks here exactly like it looks in play.
  - **Bars, cells, arrangement.** New, duplicate and delete; icons or tracking
    bars; across and down, the pattern, which way it fills and which way it
    grows; sizes, both gaps, and the scale. Deleting a bar releases anything
    that was following it rather than leaving it pointing at nothing.
  - **Your layout is shared, your spells are not.** The arrangement follows the
    bar; which cooldowns sit on it follows the specialisation you are playing,
    the way defensives and reminders already do.
  - **The cooldowns you did not place are made invisible, never hidden.** They
    are Blizzard's frames, and hiding one is what breaks it for the rest of the
    session. There is a switch for it on the page.
  - **Everything is given back.** Switch the module off and every frame goes
    back to Blizzard with the border, shadow and range veil it had before we
    touched it, and its rounded corners back on. The version that shipped
    before the removal recorded nothing before stripping those, so letting go
    left Blizzard's own Cooldown Manager stripped for the rest of the session.
  - **Your bars from 4.82.0 are read as they are.** Nothing rewrites your saved
    variables, so rolling back finds them exactly where you left them.

- **Tracking bars are drawn by the addon again, and everything on them works.**
  A bar-shaped place used to be Blizzard's own tracking-bar frame, borrowed and
  moved. That frame lays *itself* out, which is why so much of the bar page did
  nothing: **Bar height** moved the plate behind the bar and not the bar,
  **Stack count** and **Charges** styled a number nobody was writing, and the
  **spell name** appeared or did not according to Blizzard's template. All four
  are settings now rather than descriptions.
  - **Icons are still Blizzard's frames**, because for an icon borrowing works:
    their square, their swipe, their counters. Only the bar-shaped places
    changed hands, which is the same split the addon had before the rebuild.
  - **The clock is still Blizzard's.** The remaining time on a tracked buff is a
    protected value on this patch — no addon may read it, and this one does not
    try. Blizzard's bar for the same spell keeps running out of sight and its
    length and its number are passed straight through, so the timing is the
    game's and the picture is yours.
  - **What that gives you back:** the name, the stack count, the charge count
    and the remaining time all on one bar, at the size, colour, texture,
    typeface and position you set, with the fill exactly as tall as the bar.
  - **A colour for the part of the bar that is not filled yet.** New on the
    Fill tab: a switch, a colour and an opacity. Until now the empty part of a
    bar showed the plate behind the whole place — the same plate the icon sits
    on — so there was no way to have a dark trough under a bar without
    darkening the icon's background with it. **Off by default**, so no bar you
    have already arranged changes.
  - **Fixed: a flat fill colour drew as pure white.** A bar with no gradient
    was being given a white-to-white ramp on top of its colour, and that ramp
    replaces the colour rather than tinting it. Every flat fill in the addon
    has been white since the ramp was added. A flat look is now the same colour
    at both ends, which is what it always should have been.
  - **Still not there: "Fill up" on a tracking bar.** Making a borrowed value
    grow instead of drain means arithmetic on a protected number. It is left
    switched off rather than half-wired; the setting is not offered.

- **The settings window uses about half the memory it did.** A page with tabs
  used to build all of them the moment you opened it, and five of six are
  behind a tab you may never press. They are built when you press them now.
  Measured: the Cooldowns page cost 652 frames and 13.4 MB to open and now
  costs 116 and 2.4 MB; Co-Tanks went from 724 and 14.9 MB to 272 and 5.7 MB.
  Nothing was removed — everything is still there the moment you ask for it.
  - **Where the memory actually was**, since the number in the game's list
    looks alarming: all sixty-five files of code together are 455 KB, and the
    addon sits at about 3 MB until you open the settings window. Everything
    above that is the window, and a frame in this game cannot be freed once
    made — so a page you opened once is held until you reload.
  - **And the memory used while you play stops growing.** The window is the
    half you can see; the other half is what the addon does many times a second
    with the window shut, and that never stops. Three of those loops made a
    little rubbish on every single tick: a stack count was read in a way that
    built four throwaway functions each time, the ticker that pushes the count
    into a stack band built two throwaway lists a tick, and the buff watcher —
    which runs ten times a second from the moment you log in, whatever you have
    switched on — built three more. All of it is gone; the same work now
    allocates nothing at all. Nothing on screen changes, your machine just
    stops sweeping up after us.

- **Fixed: an error four times a pass on a bar with stack counts.** Asking
  whether Blizzard is showing its own stack counter could throw — the answer is
  sometimes a value the game will not let an addon look at, and looking at it is
  what raises. The whole listener it was called from died with it. It now
  answers "cannot tell", which every caller already knew how to handle: on a
  place the addon draws itself, that means it writes the number itself.

- **You can style ONE place on a bar now, and see which places carry their
  own.** Click a place in the bar picture and the Look, Text, Effects and Fill
  tabs get a **Changing** switch at the top: the whole bar, or just that place.
  Everything underneath it works exactly as it did — every slider, colour and
  menu simply writes where the switch says.
  - **A dot in the corner of a place means it carries a look of its own.** This
    is the thing that had no answer before: you set a colour on the bar, and a
    place that had its own kept it and said nothing. Now the place says so.
  - **"Follow the bar again"** hands one place back to the bar's settings. It
    only clears what this page wrote — anything you set in 4.82.0 is filed
    under the place's position rather than its spell, and the page says so and
    leaves it alone.
  - **Your styling is filed under the SPELL**, so dragging a spell to another
    place on the bar takes its look with it instead of leaving it behind for
    whatever lands there next.

- **Styling a single place on a bar now has one rule instead of two.** A place
  can carry its own look — its own fill colour, its own spark, its own charge
  marks — and it wins over the bar's. Two separate parts of the code decided
  that, which is how a bar ends up wearing one answer at one end and another at
  the other; there is one now, and it knows one level more than either did:
  styling you set on a place is filed under its **spell**, so moving that spell
  along the bar takes its look with it instead of leaving it behind for whatever
  lands there next. Anything you set in 4.82.0 is read exactly as it was and is
  never rewritten. The editor for it is the next piece of work — this is the
  half underneath it, and the note on the fill and look blocks that says "some
  places carry a look of their own" now counts both kinds rather than only the
  old one.

- **The addon now notices when another one is managing your cooldowns.** Two
  addons cannot both hold Blizzard's cooldown frames — whichever loads second
  finds them taken, and what ends up on your screen depends on the order they
  happened to load in. On the first run the welcome window says which addon it
  found and leaves the choice to you; the Cooldowns page names it again in
  full.
  - **A button switches the other one off**, on both surfaces. It asks twice —
    the first press only arms it, and it disarms itself after four seconds,
    because the second press reloads your interface. It switches that addon
    off, switches Cooldowns on here, and reloads. **Nothing is deleted**: it is
    the same tick as in the game's own addon list, and putting it back there
    puts everything back with it. If another addon *needs* the one you are
    switching off, the page says which, because disabling does not cascade and
    that addon would otherwise just stop loading without a word.
  - It reads what each addon says about **itself**, in its own description, so
    the list keeps working for addons that do not exist yet. Addons switched
    off for this character are not counted. Calibrated against 97 installed
    addons: matching on the word "cooldown" alone reports a profession tracker
    whose description mentions crafting cooldowns, so it does not.
- **Cooldowns is a module again**, first in the list and first in the window's
  sidebar. It arrives **switched off**, like the raid bar and the invite tool
  and for a stronger reason: it is the only feature here that reaches for
  frames somebody else may already be holding. The bars themselves are being
  rebuilt — until they land, the switch decides only whether we intend to
  touch those frames at all.

### Fixed

- **The bar width slider did not move the preview.** The card measured a bar's
  *width* against the space it had for *height*: a 250-wide bar in three lines
  came out at 60 and then stayed at 60 however far the slider was dragged. Each
  side is now measured against its own room, at one shared scale so the shape
  stays the bar's — and for an ordinary bar that scale is 1, so what you set is
  what you see.
- **A new bar wears ZS Flat**, for its backdrop and its fill.

- **One nil call left the whole settings half blank.** A card's kind badge is a
  frame with a string inside it, and the card asked the *frame* for `SetText` —
  which does not exist. It threw on the first card of every refresh, so no card
  after it was drawn and none of the controls on the right ever painted their
  value. They filled in one at a time, as you happened to set them.
- **Adding a bar is a + at the top of the list**, where you look when there is
  nothing yet and where it stays whether you have no bars or nine. Duplicating
  and deleting moved onto the cards, because those are things you do to a
  particular bar — a footer button that acts on "whichever one is selected" is
  a button whose consequence you have to look somewhere else to know.
- **With no bars, the settings stand down** and say to press + instead of
  showing a page of controls that have nothing to read.
- **"What it holds" is gone**, from the page header and from the Blizzard tab.
  It printed the Cooldown Manager's whole catalogue into the chat — a
  diagnostic sitting where a page's own verb belongs. `/zs cdm` still prints it.
- **"Who is managing your cooldowns" only appears when somebody is.** A heading
  plus "nothing is wrong" costs a reader exactly as much as a real one.

- **Every bar is a live card again, one under the other.** The left half of the
  page is a column of previews — one per bar, each drawing *itself* rather than
  whichever one is selected — and the settings sit on the right under their
  tabs. The separate preview band is gone: the cards are the preview, and a
  copy of the selected one across the top was the same picture twice.
- **The previews are painted, not diagrammed.** Positions come from the same
  model the renderer asks, and the look from the same two painters the screen
  uses, from the same resolved settings — so the backdrop, the border, the icon
  crop, the fill texture, its colour and its gradient, the fill direction and
  the spell name are the ones your bar actually wears. **And the bars run:** a
  still bar says nothing about which way it fills or where its leading edge
  sits, and drawn part-full it just reads as the wrong length. Draining, it is
  at every length in turn.
  - What a preview **cannot** show is named rather than faked: the cooldown
    sweep and the numbers need Blizzard's own frame, and the counts are values
    this addon is not allowed to read. Nor does a preview fill *upwards* even
    when the setting says so — no bar on screen does, and an editor that agreed
    with a switch the screen ignores would be lying to you.
- **A cell can be dragged again**, and dropped on another to move it, with
  Shift to swap the two. Right-click clears one.

- **The page is split down the middle.** Every bar in a column down the left,
  one under the other, and the settings on the right under their tabs — the
  owner's own layout, and the fix for a list that flowed two-abreast because a
  settings row is half the page wide. The list also **rebuilds itself now**:
  the page is built once, so a row made per bar at build time was the set of
  bars that existed the first time it was opened, and pressing New bar added
  nothing you could see.
- **A bar has a number of places, not a rectangle.** `Rows x across` could
  only ever describe six, twelve or eighteen — never seven. **Places** says it
  outright; across is how many of them sit on a line, and down is what that
  comes to. Bars written before this read exactly as they did.
- **Bar-shaped places stack.** Switching a bar's cells from icons to bars puts
  them one per line, which is the only arrangement anybody means by it — four
  200-pixel bars shoulder to shoulder was the default nobody had changed.
- **A bar-shaped place looked wrong in the preview.** Its spell icon was
  stretched the whole width of the bar and its empty "+" was drawn for a box
  eight times too tall. A place is now told both its sides, and its icon stays
  square at the end the spell icon actually sits at.
- **The Cooldowns page opened with nothing on it.** Twenty-three headings, all
  folded shut, over a preview band one pixel tall — so the bar's name was drawn
  across the first heading, and the button that makes a bar was inside a
  section that opened closed. Three separate faults, none of which stopped the
  page from building:
  - The settings now sit under **six tabs** — Bars, Look, Text, Effects, Fill
    and Blizzard — the same split the co-tank page already wears, and every
    section opens **open**. A tab has already narrowed the page to one subject;
    folding three sections on top of that leaves a list of things the page will
    not show you.
  - The preview band **says how tall it is**, and the tab strip lives in it, so
    what you are editing and the way to the rest of it both stay put while the
    settings scroll.
  - The preview **follows the selection**. Its refresh was written, was
    correct, and was registered nowhere: it drew once when the page was built
    and never again, so picking a second bar left the first one's cells on
    screen under the first one's name.
- **Clicking a bar in the list did nothing, and said so eight times a paint.**
  A row is a frame, and a frame has no click handler at all — the client threw
  the assignment back every time the page was drawn. Rows now have a proper
  way to be clicked, in the one place that knows a frame hears it as a mouse
  release.
- **Every cooldown change threw an error.** The text layer called
  `Claim.MoveCounter`, which does not exist: the name was taken out of a
  comment describing what the *old* implementation used to do by hand. The
  door that does exist is `Claim.Anchor`.
- **Three whole features were silently doing nothing.** Writing to one of
  Blizzard's frames goes through a door that refuses anything it cannot put
  back — which is right, and is silent, so a missing entry is not a warning
  but a dead control. Three were missing: the **font, size and outline of
  every counter** (four text elements, three controls each), **"show
  Blizzard's own countdown"**, and **every gradient on a fill**.
- **The countdown number was never given back.** Blizzard's own counter is a
  region its cooldown owns under no name at all, so the list of parts to
  return on release could not name it — its font, its colour and its position
  stayed ours after the bar let the frame go.
- **The desk now lays a page out instead of only building one.** Every guard
  that watched these pages stopped at "it did not throw", which all three
  faults above pass. The new one asks what is actually on the page: that the
  band has a height, that at least one control is visible once the fold states
  are applied, that every tab has something on it, and that the page carries
  the refresh the window calls. It was checked against all four faults by
  putting each one back.

- **Every language this addon ships was showing mangled text.** All ten
  translated tables had been read as Windows-1252 and written back as UTF-8 at
  some point, which turns each accented letter into two — German showed
  "fÃ¼r" where "für" belonged, and Russian, Korean and both Chinese showed
  whole lines of it. 408 lines across every language. It survived this long
  because the strings are data rather than code, so nothing ever failed, and
  because the self test compared translations against the English list, which
  has no accented letters in it and was perfectly happy.
  - 357 lines are repaired exactly. **51 could not be**: the damage destroyed
    five byte values outright, and no reversal brings back a byte that is not
    there. Those entries have been removed, so they fall back to their English
    original — which is correct text rather than a word with a hole in it —
    and they are listed for re-translation. Russian lost 44, Korean 6, Simplified Chinese 1.

### Changed

- **The welcome window lost its strapline.** "8 features in one addon. Pick
  the ones you want running." sat over eight rows that are the features, each
  with a switch on it — it narrated the thing underneath it, and the number in
  it was a second copy of a list.
- **The sidebar's first heading is gone.** "M+ and raid stuff" sat over
  everything the addon does, which is not a group worth naming — "System" and
  "Info" name a handful of rows each and stay. The air it provided between
  Edit mode and the list stays too.
- **The licence is All Rights Reserved.** The store page has always said so;
  the folder that shipped carried an MIT `LICENSE` beside it, which is the kind
  of contradiction that only gets found by somebody acting on the wrong half of
  it. The About page states the terms now, so they are readable without opening
  a file. The libraries under `Libs/` keep their own — LibStub public domain,
  CallbackHandler BSD, LibSharedMedia LGPL 2.1, LibSerialize MIT, LibDeflate
  zlib. **Releases up to and including 4.82.0 stay MIT**: that grant was given
  and is not being withdrawn.
- **"Active for" moved to the death log page.** It was on the cooldowns
  page — say how long a trinket, potion or racial lasts, because the game
  does not report it — and the death replay still reads it first for every
  press it draws. The number itself is untouched in your account file. The
  list now offers the defensives you picked, plus anything that already
  carries a number.
- **Defensives, consumables, cooldown requests and reminders are per
  specialisation.** What you *pick* follows the spec; where a panel *sits*,
  and its rows, columns and channels, stay on the profile. A window that
  jumped on a spec change would be a worse bug than the one this fixes. A
  spec the client has not named yet writes nothing at all, so an unanswered
  question can never overwrite a real list.

### Fixed

- **"Is this buff up?" could throw a real error in a dungeon.** The one call
  every reminder makes reads two values off Blizzard's own cooldown frame
  inside a `pcall` — and then tested them on the next line, outside it. On this
  patch those values can arrive as *secret*, and testing a secret one is
  exactly what raises. It now reports "cannot be answered", which is the third
  answer that function already promised and every caller already handles. Found
  by a new build check rather than by anybody hitting it.

- **Reminders could not fire at all.** The index that answers "which frame is
  showing this spell" was rebuilt once per render pass by the bars. The bars
  went and its only writer went with them; nothing threw, and the table
  simply stayed empty for the whole session — so every reminder reported
  "Blizzard is not showing this spell", blaming Blizzard's settings for a
  hole of ours. It now rebuilds when the frame pools churn and on the first
  read. No test could have caught it: an empty index and a spell that really
  is untracked are the same answer.
- **`/zs test` was eating your consumables.** The self test set the picked
  list to `nil` to establish a state and left it that way, in a file whose
  own header promises it never touches your settings. Reported as "it does
  not save" — and from the outside that is exactly what it looked like.
- **`/zs test` was also taking spells out of your request panel**, and it
  reported eight failures while doing it. The slot checks used to empty
  `cells` on your own profile, run, and put the old table back. That worked
  until the slots became per-spec: the panel's config now hands out the table
  for the spec you are playing and re-points it on every read, so the empty
  one was discarded by the next line — and the picks and clears that followed
  went into your panel. It deleted Blessing of Sacrifice out of slot 2, put
  Ironbark over slot 3, and overwrote the pre-spec list that a spec you have
  not played yet inherits. Every one of those checks now runs on a profile
  built for it, and the desk harness fails the run if a self test leaves any
  setting changed.
- **The window opened on an empty Settings page.** Clicking any other row and
  coming back filled it in. Building a page happens when you select it, and
  opening the window never selected anything — it just showed the first one.
  That was harmless while the first page was Cooldowns, which had no builder
  at all and was drawn entirely by the frame around it. The bars went, Settings
  moved into first place, and the first thing the addon showed anybody was a
  blank stage. It now opens the first page through the same door every other
  page uses.
- **Unlocking told you about two modes that no longer exist.** `/zs unlock`
  answered with *"Move bars drags whole bars; Build takes them apart slot by
  slot"* — both of them went out with the cooldown bars. It now says what the
  instruction band above the toolbar says: drag a panel, arrow keys nudge it,
  Shift for ten.
- **The minimap note said right-click moves the bars.** It unlocks the panels
  for moving, and has since the bars went.
- **The checks for per-spec settings had never run outside the game.** The
  desk harness left the specialisation API missing, which the addon reads as
  "the client has not said yet" — and in that state every per-spec setting
  falls back to the profile-wide path. The request slots, the defensives and
  the reminders were all being checked through a door they never use in a
  real client. The harness now plays a specialisation, and the eight
  failures above reproduce on the desk instead of in your raid.
- **The changelog page in the options window was blank.** One list, two
  readers, and the older one still called `SetText` on an entry that had
  become a table.
- **Edit Mode lost its instruction line**, and snapping silently snapped to
  nothing: a local read before its own declaration is a different, empty
  variable.

## [4.82.0] - 2026-08-14

### Added

- **The group's deaths, as a log.** Who fell, when, and what ended them — for
  everybody, not just you. A second icon with three skulls opens it, and the
  last pulls are down the right; click one to read it.
- **Click a death and read their last ten seconds** — the same table your own
  death window shows, for whoever the row names. A red mark down the left
  edge of a hit means the game itself calls that damage avoidable.
- **Tonight, across pulls.** What keeps killing the group, counted in PULLS
  rather than moments, and who keeps falling. **Share in chat** sends
  whichever page you are reading.
- **Power Infusion can be requested.** It asks ANY priest — all three
  specialisations have it, so the shadow priest is as good an answer as the
  healer.
- **A What's New screen**, shown once per update.

### Fixed

- **Cooldown requests reached nobody across a realm border.** The macro
  carried the short name; over a realm boundary the game needs
  `Name-Realm` and refused the send with no error. `/zs chat` now says what
  your client allows.
- **A recorded "no" was filed as a clean bill** in the death analysis.
  Nothing on screen looked wrong.

## [4.81.0] - 2026-08-13

### Fixed

- **The external cooldown panel offered spells the person cannot cast.** A
  priest in the group put both Pain Suppression and Guardian Spirit on screen,
  and no priest has both — one belongs to Discipline and the other to Holy.
  The panel checked the class and nothing else. It now reads which
  specialisation each group member is actually playing, asynchronously,
  the way every damage meter does. **Somebody who cannot be read yet keeps
  their icon**: an empty panel while you run into the room would be a worse
  answer than one icon too many. The catalogue never stores a specialisation
  id — it stores which one, and asks the game for the number, so a client
  that renumbers them drops the restriction rather than applying it wrongly.
- **The `Healing on you` lane is gone from the death replay.** It held a
  fifth of the window's height and was usually empty. Heals are still
  recorded and the death window still counts them.

### Added

- **A saved bar now carries the whole bar.** Under *Bars → Reuse*: the sizes,
  spacing and colours as before, and now also the grid it is laid out in, the
  per-cell arrangement, and the spells of the spec you saved it on. Copying
  one bar onto another does the same. **Take the spells too** switches it back
  to the old look-only behaviour for anybody who wants that; where a bar sits
  on screen never travels either way. Presets saved by earlier versions are
  still readable and are still a look.
- **`/zs specs`** — what the game says each specialisation is, and which one
  every request slot is waiting for.

### Changed

- **The description texts on the Raid Bar, Invites and Settings pages are
  translated.** Twenty-four sentences, German for now. Their labels had been
  translated for months and the sentences under them had not, which reads as
  an addon that gave up half way rather than one that is honestly unfinished.

## [4.80.0] - 2026-08-13

### Added

- **Take a cooldown off the bar while it is recharging.** Under *Bars →
  Behaviour → Fading and hiding*. **Ready is always on screen** — the icon
  earns its place by being usable, or by working: press a defensive and it
  stays while its buff is still running, Anti-Magic Shell and Blood Shield
  being the obvious ones, and only goes once there is nothing left but the
  wait. A tracked buff counts as working while it is up, and a proc this addon
  clocks itself is treated the same way, so one setting reads correctly on a
  bar holding all three. Anything the client will not answer for stays where
  it is: an icon that vanished because something could not be *read* is
  indistinguishable from a bug.
- **And the others can close up behind it,** or leave the place empty. Leaving
  it empty is the default and it is the one worth thinking about: a display
  whose icons move as cooldowns come and go has to be re-read every time, and
  "the third one is my stun" is worth more than an empty square costs. Closing
  up **in the row** keeps a grid's shape, so the second row stays the second
  row instead of a defensive being pulled up into the first.
- **A glow that runs round the icon** instead of sitting on it. *Edge style →
  Running squares*, with the count from two to twenty-four. Motion is caught
  by the corner of your eye in a way a steady colour is not, which is the
  whole job of a proc marker.
- **A ready glow that only lights what you can actually pay for.** *Only when
  castable*. Range and target are deliberately ignored — a defensive with
  nothing targeted is not the same as one you are short of the resource for,
  and greying that out would be wrong on every pull.

### Fixed

- **Everything that depended on "is this on cooldown" had been dead on
  Cooldown Manager icons.** The ready flash, the ready edge, the reminder and
  the greying all read one field that this client does not carry at all, so
  they stood down silently — which is exactly what this addon does on purpose
  with a value it may not read, so nothing ever complained. They work again.
- **Settings added after you started playing showed an empty box.** A new
  setting only reaches a profile when that profile is created; a switch reads
  the gap as *off* and looks fine, a dropdown finds nothing to match and draws
  blank. The page now falls back to the default, so it shows what the bar is
  actually doing.
- **Switching tabs kept the scroll position of the tab you left,** which put
  the first heading of the new one half above the visible edge. It reads as a
  clipped layout rather than as a page scrolled by twenty pixels.
- **Two settings that looked like the same one, twice.** *Grey out while
  inactive* and *Grey out on cooldown* never touch the same icon — an aura has
  no cooldown and a Cooldown Manager icon has no "down" — but nothing on the
  page said so. They are now named for the state they mean and each points at
  the other.

## [4.79.0] - 2026-08-13

### Added

- **A proc's buff now identifies itself.** The 12.1 route shows the real aura —
  the game's own icon, the game's own timer, extensions included — but it needs
  the aura's spell ID, and there is no call that gives it. Until now that meant
  somebody had to play each spec and write the pairing down; exactly one shipped.
  It is watched instead. A proc's glow rises when the buff lands and falls when
  it is spent, so the buff is in your aura list at one end and gone at the other;
  the flask, the food and the raid buffs are in both and cancel out. Three procs
  agreeing on one buff, with everything else eliminated, is the buff — and then
  the bar switches from our stopwatch to the game's own timing and says so.

  **Out in the world, not in a dungeon.** Inside instanced content the client
  withholds aura data and the reading simply does not happen. One proc on a
  target dummy is enough, and it is enough for everybody who plays that spec.
- **The aura strips on the co-tank panel sweep.** The round cooldown sweep on
  the icon, drawn by the game from the aura's own duration object — so an aura
  that gets extended mid-fight sweeps to the new end instead of finishing early.
  Under *Co-tanks → Auras → Sweep*, on by default: these strips have never drawn
  live for anybody, so this is a first impression rather than a change.

### Fixed

- **The addon no longer talks as though 12.1 were still coming.** The Auras page
  said the engine "arrives in patch 12.1" on a client that has it, and claimed
  aura data is secret everywhere — where you are standing decides that, and out
  in the world it frequently is not. Both now say what is true, and the page
  explains what is actually left to do.

## [4.78.1] - 2026-08-13

### Fixed

- **The raid check would not stay open.** It appeared while the raid bar
  button was held down and vanished the moment it was let go. A place on the
  raid bar registers for clicks in **both** directions, because a secure one
  has to — with
  `AnyUp` alone a marker never fires for anybody who has *cast on key down*
  switched on, which is the default. The three actions that are not protected
  hang a plain Lua script on that same button, and a script does not care
  about the setting: it heard the press and it heard the release, and it ran
  twice. `Toggle` opened the window on the way down and shut it again on the
  way up, so the only way to see it was to keep holding the mouse down. The
  pull timer and the ready check went out twice for the same reason and simply
  did not look wrong.

  `RaidBar.PressGate` decides it now, and **which edge to drop is not a coin
  flip**: the conventional button acts on the release, so that you can slide
  off it to cancel — but a place is also reachable from the keyboard
  (`CLICK ZwoelfStuffRaidBarN:LeftButton` in `Bindings.xml`), and an up that
  never arrives is a button that never fires. So the gate takes the **first**
  edge it is handed and swallows the matching second one. Both edges, down
  only, up only — the action runs exactly once.

  Two checks, and they do different jobs. `PressGate` is a pure function with
  six cases in the self test, including a scripted `Click()` and a press whose
  release went missing. That alone would not have caught this, because the
  fault was never in a rule — **the harness now takes the click script off the
  real slot, presses it, and counts how often the action ran**, which reports
  `click 2` against the old code. The drag wave shipped a correct rule wired up
  wrong twice; this is the first check that tests the wiring. A third,
  source-level, lists every button that hears both edges together with the
  reason one press runs once — registering both directions is not the bug and
  cannot be forbidden, so it has to be deliberate rather than forbidden.

## [4.78.0] - 2026-08-13

### Added

- **Localisation, in eleven languages.** `ns.L` looks a string up by the
  English sentence itself, so a missing translation renders as the English it
  replaces rather than as a raw key — which is what lets nine unfinished
  languages ship without a single broken screen. The language follows the
  client (`enGB` resolves to `enUS`) and can be overridden per profile under
  *Settings → Language*; the list shows how far each translation has got.
  German is complete. French, Spanish (ES and MX), Italian, Portuguese and
  Russian carry the interface and its sentences; Korean, Simplified and
  Traditional Chinese carry the vocabulary. `/zs loca` prints coverage, and
  `/zs loca deDE` prints exactly what is left.
- **A Raid Bar.** Eight raid markers and a clear, eight world markers and a
  clear, the game's four pings, a ready check, a pull timer and the raid check
  window — assembled into a lattice the same way the externals panel is, with
  the list of buttons in the third column. Rows, columns, growth direction,
  icon size, spacing, scale, opacity, border and backdrop, and the first twelve
  places carry a key from the game's own key list.

  Every marker, world marker and ping is a `SecureActionButton` carrying a
  macro, because all three are protected on this patch — verified against MRT,
  which switches to the same route the moment it detects Midnight. It follows
  that the bar cannot be rebuilt in combat: `ApplyLayout` parks the work and
  does it on `PLAYER_REGEN_ENABLED`, and `/zs raidbar` says when it is waiting.
  World markers use the 12.x `worldmarker` button type where the client has it
  and the `/wm` macro where it does not. Slash commands come from the client's
  own `SLASH_*` globals, which are translated on four locales.
- **The raid check window.** Name, item level, durability, food, flask, rune
  and the six group buffs, per group member. Another player's auras are secret
  on this patch, so the facts are **reported, not read**: everybody's client
  answers for itself over the addon channel. `Comm` gained a second wire form
  for it — deliberately shaped so the old decoder rejects it, which is exactly
  how a client one version behind should behave. Somebody without the addon is
  drawn as *no answer*, never as a guess.
- **An invite tool.** Keyword invites on whisper (and optionally say and yell),
  strict or loose matching, guild-only and friends-only filters, auto-accept
  from friends and guild, auto-promote by name, convert to raid at five, invite
  the guild by rank, disband, and invite everybody back afterwards. Every one
  of those is off until it is switched on, and `/zs invite` prints what is
  listening.
- **A memory reading on Diagnostics.** The page says what this addon is doing
  to your client; it could not say what it costs. `UpdateAddOnMemoryUsage`
  walks every loaded addon, so the reading is taken at most once every five
  seconds and the tile shows the last one in between.

### Changed

- **The window is 820 tall instead of 760.** Thirteen pages, four group
  headings and the three outward links leave the rail with 8 spare pixels at
  the old height — it fits, and the next feature would have landed with its
  entry hidden behind the foot. `UI.RailFits` exists to force that decision
  here rather than in a screenshot. Shorter rows or less air between the groups
  were the alternatives, and both spend the design to save the window.
- **The lattice arithmetic is shared.** `ns.LatticeCell` / `ns.LatticeExtent`;
  `Externals.Cell` and `Externals.Extent` are doors onto them. Two panels made
  of squares must not each carry their own copy of which way a row fills.
- **Modules may default to off.** The check that every module defaults to ON
  became "every module has an answer in the defaults" — a module missing from
  that table reads as on, which is the failure worth guarding. The six that
  draw or record something still default on; the raid bar and the invite tool
  do not, and the welcome window is what offers them.

### Fixed

- **A class colour could not be printed.** The death replay formatted a
  healer's name with `%02x` on `colour.r * 255` — a float. Lua 5.1 truncates
  it silently and 5.4 raises; the desktop harness had never executed the line
  because nothing stubbed `RAID_CLASS_COLORS` until the raid check needed it.
  The same latent fault was in the externals and taunt style dumps, where it
  survived only because the default border is black.
- **A row's second line ran under its control.** `UI.Row` has stopped the
  label at the control slot since it was written; the sublabel got one anchor
  and ran the full width of the row. Photographed on the welcome window, where
  the raid bar's blurb was drawn straight through the `NEW` badge — and it
  affects every page in the addon, not that window. The desktop stub now
  counts anchors, so "a piece of text with one anchor has no right-hand edge"
  is a check rather than a screenshot.

### Changed (continued)

- **The third column is built when a page first asks for it.** All five were
  built the moment the window opened — whichever page you were on, and the
  co-tank one even with its module switched off. Measured on the desktop
  harness: `Options:Create` cost 4.6 MB, of which `OptionsBars:BuildSide` was
  2.4 MB (796 frames) and the co-tank inspector 1.7 MB (595 frames). It is now
  2.6 MB, and the rest is paid only by the page that shows it. The page
  *builders* have been lazy for versions; the panes were never brought over.

  That 2.4 MB was read as "the spell palette" for a version, and it is not: the
  desktop has no Cooldown Manager, so the palette out there is a list of
  nothing. Split, it is `BuildOptionsPane` 2.2 MB / 639 frames, `BuildCellPane`
  0.45 MB, and the palette itself 50 KB. `memcheck.lua` now weighs the three
  separately, because a total that gets attributed to the wrong one of its
  parts sends the next session after the wrong file.
- **Every place you can put something into can be dragged out of, swapped, and
  dropped into.** Pick a marker, a spell or a cooldown up out of any list and
  drop it on a place; drop it on a place that is taken and the two swap; pull
  one off into empty space and it comes off. Clicking still works exactly as it
  did — this is the second way in, not a replacement.

  Asked for as the gesture rather than as a feature: *drag and drop everywhere,
  including swapping places, dragging in and dragging out — the natural WoW
  behaviour*, and the point behind it is that a player should not have to work
  out that a list row is clickable.

  `UI.SpellSlot` had answered a drag since it was written and never started
  one: things went in, and the only way out was a right click. It is a drag
  source now, and `UI.DragOutcome` is the pure rule behind every release —
  **drop** onto an empty place, **swap** with a full one, **clear** when you
  let go over open air, **refused** when the two places do not hold the same
  kind of thing.

  Refused is not a detail: the drag machinery keeps one list of every grid in
  the window, so a raid bar place — which holds the word `mark3` — is a
  neighbour of a cooldown cell, which holds a number. Written into each other
  they draw an empty square and say nothing about why. Every grid names its
  kind now, and a place that would refuse the drop does not light up while you
  are dragging over it.

  **Two pages could not be dropped into at all**, and nobody had noticed
  because the click path worked: the raid bar and the externals panel both
  built their slots without an `onPick`, so the slot answered the drag by
  doing nothing. The death log's defensives are marked `ordered = false` —
  those squares are a view of a set sorted by name, so a swap would take both
  out, put both back and change nothing; dragging one out still removes it,
  which is the one thing those squares can say.

  Clicking is untouched everywhere. The rule is guarded by the self test; the
  wiring — which page passes which callback — is not, and that is exactly the
  gap this change was fixing, so it wants a pair of eyes in game.
- **The mouse wheel scrolls the page and nothing else.** It used to change
  whatever number the pointer happened to be over, so reading further down a
  settings page could quietly change a setting on the way. Drag the rail or
  type into the box — both are aimed.

  Every number in the addon is one control (`BuildSlider`), and it bound the
  wheel on both the rail and the value box —
  which on a page you scroll with the wheel is a hole the scroll falls into.
  Unbound rather than swallowed: a frame with `EnableMouseWheel(true)` eats the
  gesture whether or not it does anything with it, so an empty handler would
  have stopped the value changing *and* the page scrolling. No arrow-key
  replacement was invented — `OnArrowPressed` only fires reliably on a
  multi-line edit box, and an unverified binding is a changelog line that turns
  out to be false. The harness now reads the source and fails the build if any
  control takes the wheel again; the eight places that legitimately take it —
  scroll areas, the dropdown popup, paging between deaths, panning the replay,
  capturing a key, and the edit-mode cell handle — are named there with the
  reason each one moves you through something rather than setting something.
- **The raid bar preview drew every button half again too big.** It now draws
  the bar at the size the bar actually is, and follows the icon-size slider
  while you move it.

  The page was
  built as a copy of the externals page, and it copied the constant `SLOT = 40`
  without the calibration behind it: on that page 40 *is* the panel's own
  default cell size, so preview and screen agree by construction. The raid
  bar's button is 26 and its gap 2, so the copy drew 1.54× the size with 4× the
  air. `UI.PreviewSize` replaces the three verbatim copies of that arithmetic
  with one shared, pure function, and the rule is now the one the bar cards
  have always used: **a preview draws what the thing is and only ever shrinks**
  — to fit the page, never past what was asked for. Its floor may not push a
  deliberate 16 back up to 22 either; that would be the same lie in miniature.
  `UI.SpellSlot` gained `Resize`, because the empty `+` took its font from the
  size the slot was *created* at and was the one thing on the page that did not
  shrink with it.
- **The spell picker builds one row per line you can see, not per spell there
  is.** It held a `UI.SpellRow` for every catalogue entry and kept it for the
  session — around a hundred buttons, each with an icon, two strings and a
  badge, for a column that shows a dozen at a time. It now builds the plan (one
  small table a line) and draws only the lines inside the column, re-filling
  them as it scrolls. Used by three pages: bars, reminders and the death log.

  Measured with a 200-spell catalogue held up to it, which is what the harness
  could never do before: the whole pane is 166 KB / 34 frames, against 2.25 MB
  / 400 frames for 200 bare rows. `UI.VisibleRange` is the arithmetic, and it
  is pure — the harness answers `GetHeight` with a constant, so a check that
  went through the real column would be asking the stub rather than the sum.
  `UI.ScrollArea` gained `OnScrolled` for it: one door for the three moments
  that move the window over a list, rather than every caller hooking the
  thumb's own handler and depending on the order.

## [4.77.0] - 2026-08-12

### Added

- **The addon is on Wago as well as CurseForge.** Same build, from the same
  release — take whichever you already use.
- **About says where to get it, and how to reach us.** Both stores under
  *Where to get it*, and **Discord** in the page header. None of them can open
  your browser — no addon may hand a URL to one — so each puts the address in a
  box you can copy from.
- **A bar you switched off says so in the list.** A `HIDDEN` badge on the card
  head, with the reason in its tooltip. Only settled reasons appear — switched
  off, or set to never show. `Visibility:Fixed` is the one place that decides
  which those are, and it takes the wording from `Visibility:Explain`, so the
  badge and the panel cannot word it differently. Combat, target and spec are
  deliberately excluded: the list is not redrawn when you pull, and a stale
  badge on a settings page is worse than none.

### Changed

- **Edit mode's mode pair is lit, not tinted.** `UI.Button:SetActive` gives the
  current mode the same `accentSoft` bed the chip row and the CURRENT badge use.
  It was a dimmed label before — the channel `SetEnabled` already uses for "you
  cannot press this", so the mode that was merely not current read as dead.
- **The welcome window has a visible second exit.** *Not now*, a ghost beside
  *Let's go*. Escape has always closed it and always counted as answered; a
  keypress nobody is told about is not an exit.

### Fixed

- **"Four features in one addon" over six switches.** Both the welcome window
  and the Modules note on the Settings page typed the number while the rows
  under them were built from the registry. `Modules:Count()` counts it now, and
  a check makes sure `Modules.GENERATION` covers every module's `since` — a
  module added without that bump is never offered to anybody, silently.

## [4.76.0] - 2026-08-11

### Changed

- **Every number is a slider again — a track with the value beside it.** The
  design this window was built to said *"no more sliders, every number is a
  stepper"*, and the reason it gave was precision: a track standing in for a
  range has only as many stops as the column leaves it. That objection is
  answered and has been since 4.19.0 — the value is an **edit box**. Click it
  and type, or roll the wheel one step at a time. What the stepper could not do
  is say *where in the range* you are: "Icon size 44" is a number without a
  scale. Four ways in now — drag the track, click it, wheel over either half,
  or type. There is still exactly **one** numeric control in the addon, so
  every page, every panel and Edit mode got this at once.
- **The value field has an edge.** It is the darkest tone in the window, which
  is meant to say "here is a value you can change" — but in the inspector it
  stood on a ground one and a half percent lighter than itself and said
  nothing. Nobody noticed while two buttons flanked it.
- **A page's actions are in the header band now, beside its title.** They used
  to be a column of buttons *inside* the page, next to that page's preview — so
  the same kind of thing sat in a different place depending on which entry in
  the list you had clicked, and where they existed they ate a third of the
  width the preview needed. **Move bars / Build** on Cooldowns, **Make the
  macro / What a taunt would say** on Co-Tanks, **Set keys / Test mode** on
  External CD request, **Set keys / What every cell would cast** on External CD
  answer, **Open it / Share in chat** on the Death-log.
- **The slots, the offered spells and the co-tank preview have their whole band
  back**, and each band is only as tall as what is actually in it. A one-row
  panel used to hold a band four buttons deep with nothing in three quarters of
  it.
- **A button that belongs to one block stayed with that block.** *Who would be
  asked* prints the "Who to ask" list out loud, so it stands under that list
  rather than four sections above it.
- **Moving a panel is one door, not two.** The per-page *Move the panel* and
  *Move the bar* buttons opened the same edit mode the first entry in the list
  opens. The pages say where that is instead.
- **About is a page rather than a wall of text.** The mark, the name, why it
  exists and the three facts anybody is asked for — author, version, client —
  stand in a block at the top; the credits and the "what the client will not
  let it do" paragraphs are two named sections under it, and the commands are a
  list in two columns.
- **Diagnostics opens with four readings**: how many cooldowns the Cooldown
  Manager holds, how many cells on your bars are filled, how sharp the marks in
  this window are, and whether another cooldown addon is fighting for the same
  frames. All four are measured on your machine.
- **Settings has no right-hand column.** It was a panel 400 pixels wide
  standing empty until you pointed at something, to show two lines that fit
  under the row perfectly well. The sentences are on the page now.
- **The sidebar is tidy at the bottom.** *Discord* is a row like every other
  row: its word starts where every other word in that column starts, it lights
  up under the mouse the way its neighbours do, and it has air above it.
- **The window ground has an up and a down.** One vertical gradient over a flat
  colour. Three columns of three flat colours read as a wall.
- **Cards, buttons and menus have depth.** Two pixels of darkening inside the
  edge turn a card into a shallow tray, and menus cast a shadow instead of
  saying "I am on top of the page" with the same bright outline that marks the
  selected row inside them. Not under every settings row: forty trays stacked
  up is the brick wall this window was rebuilt to get rid of.
- **The window can be seen through — 94% by default, adjustable under
  Settings.** One alpha on the outermost frame. Fading each layer separately
  would multiply the values wherever two overlap, and no surface would keep a
  colour you could predict. The floor is 70%: a window you cannot see is a
  window you cannot close.

### Fixed

- **A number could land outside its own slider.** Snapping rounds to the
  *nearest* step, and the range was only clamped before that — so a range of
  0 to 1 in steps of 0.4 turned a typed 1 into 1.2. Pinned by a check that goes
  red if the second clamp is ever removed.
- **Dragging repainted sixty times a second even when nothing moved.** A 96px
  track carrying 42 steps lands on the same step for most frames of a drag, and
  each one rebuilt the bar it belongs to. It now only redraws when the snapped
  value actually changes.
- **The command list was written twice and the second copy had gone stale.**
  About still advertised `/zs text` and had never heard of `/zs build`,
  `/zs modules`, `/zs report`, `/zs skin`, `/zs test`, `/zs taunt` or
  `/zs death`. There is one list now — the chat help and the About page both
  draw it — and a check fails if it ever names a command with no handler
  behind it.

### Removed

- **The plus and minus buttons, and their eight mark files.** The track
  replaced them; leaving the artwork in would have shipped 80 KB that nothing
  draws.

## [4.75.0] - 2026-08-11

### Changed

- **The alternating light/dark grounds are gone.** They were meant to group a
  setting with its own sentence without drawing a line — the mechanism another
  UI uses, and a sound one. It does not survive this window: a stripe is
  anchored across the full content width, but half of every page stands in
  **two columns** of half-width rows, so one stripe ran under a pair that has
  nothing to do with each other and the alternation stopped meaning anything.
  Grouping is done with air now: a sentence sits close to the setting above it
  and twice as far from whatever comes next.
- **Labels start on the same line as the headings again.** The 14-pixel indent
  existed to keep text off the edge of a stripe. Without one it was the thing
  that had been complained about in the first place — space at the front of
  every line, and labels not lining up with anything.
- **Arial Narrow is the default font again, for the window and for bar text.**
  The version before this took Expressway from whichever other addon had
  installed it. Two things were wrong with that: the file is the **bold** cut
  whatever it calls itself, so the window came out heavier than it is drawn,
  and a default that depends on which *other* addons you have is not a default
  — two players on the same version saw different type. Expressway is still in
  the picker under **Settings** for anyone who wants it. An existing profile
  keeps the bar font stored in it; a default does not reach into a saved
  setting.

### Added

- **About names the addons this one was written by reading** — EllesmereUI,
  ElvUI, BigWigs, Method Raid Tools, Mythic Dungeon Tools, Details!, WeakAuras,
  Plater, LibOpenRaid — and says exactly what was taken from them: no code,
  facts about the game's API that are documented nowhere else. The same words
  the README carries, in the place a player will actually see them.

## [4.74.0] - 2026-08-11

### Changed

- **Room around the words.** Every setting sits on a ground of its own now, so
  it gets padding inside that ground instead of starting on its edge: 14 either
  side, taller rows, and a real gap under a heading instead of three pixels. A
  note lined up with the labels above it also used to run the same distance off
  the right-hand edge — an indent is padding on both sides now.
- **Headings are no longer painted in the brightest white in the palette.** The
  panel font is a bold face, and full white on top of it was three emphases for
  one thing.

> Still being worked on: the spacing is closer but not right yet.

## [4.73.0] - 2026-08-11

### Changed

- **There are no lines between settings any more.** A setting and its
  explanation share a ground of their own, and consecutive blocks alternate
  between two shades. A line is a thing you have to look at; a change of ground
  is one you do not — the eye reads the stripes and never resolves an edge. The
  grouping that took a hairline to state is now simply what the surface says.
- **The window uses the font you already have.** If any of your other addons
  ships **Expressway** it is registered with LibSharedMedia, and it is now the
  default here. The settings page had been *showing* it as the default for
  months while the window was drawn in Arial Narrow, because nothing ever asked
  for it. Nothing is bundled: the file stays where it was installed, and on a
  client that has none of them Arial Narrow is used exactly as before. Any font
  your addons register can be picked under **Settings**.
- **About says what this addon is** — the same words the README opens with,
  from its author — and spells his name properly.

## [4.72.0] - 2026-08-10

### Changed

- **You can see at a glance which features are running.** A green light next
  to a feature in the list on the left means it is on; **OFF** in red means it
  is not. It used to be the word OFF in the faintest grey there is.
- **Section headings are bigger than the settings under them.** They were
  smaller - the one word that says what a block of settings *is* was the
  faintest thing in it.
- **The explanations line up with everything else.** They were indented by
  eight pixels and nothing else on the page was, so every paragraph started in
  a different place from the rows around it.
- **A line no longer runs between a setting and its own explanation.** The
  hairline that closes a block now sits under the pair, where it separates one
  group from the next instead of cutting one in half. And there is room to
  breathe above and below every paragraph.
- **Set keys is a button in Edit Mode**, in the box with the rest. It was only
  reachable from two settings pages. Edit Mode closes as it opens, because
  both put squares over the same panels and only one of them can have your
  clicks.

### Fixed

- **The empty Keys section on the External CD request page.** Its two
  sentences were being handed to the last row of the section above it and
  shown in that row's tooltip instead - so the heading was left standing over
  nothing. Every section that opens with a paragraph was affected.

## [4.71.0] - 2026-08-10

### Added

- **Lust and a battle resurrection can be asked for - one slot each.** Drag
  **Lust** onto the panel and the click asks whoever in your group has one:
  Bloodlust, Heroism, Time Warp, Primal Rage or Fury of the Aspects. **Bres**
  is the same for Rebirth, Raise Ally, Intercession and Soulstone. One slot
  rather than one per class, because "who can lust" is one question and you
  should not have to fill five places to cover the groups you might walk
  into.
  Everything else on the panel is cast *on* you - lust is cast on the room
  and a battle res on your corpse - but the reason they belong here is the
  same: it is somebody else's cooldown, and asking out loud mid-pull is the
  part that does not happen.
- **On the answering side each class gets its own.** A mage's cell is Time
  Warp, a warlock's is Soulstone, and a shaman gets whichever lust his
  faction gave him. One press on the asker's side lights the right cell on
  everybody's.

### Changed

- **The co-tanks page is built like the other two.** The preview and the two
  buttons that act on it - **Make the macro** and **What a taunt would say** -
  sit in a band at the top that stays put while the settings scroll. The
  buttons were at the very bottom of the page.
- **Its settings stand in two columns** instead of one per line. Every row on
  that page was full width, which is what made it feel like a form rather
  than a settings page.

## [4.70.0] - 2026-08-10

### Changed

- **The two pages say what they are: External CD request and External CD
  answer.** One asks for a cooldown, the other answers somebody asking - they
  are two ends of one thing and used to be called "External cooldowns" and
  "Answering", which named neither end. Older entries in this file keep the
  names they shipped under.
- **The answer page is built like the request page.** The spells you offer
  sit in a band at the top that does not scroll, with the three things you do
  to the bar - **Move the bar**, **Set keys**, **What every cell would cast** -
  stacked beside them. They were at the very bottom, past every setting on the
  page.
- **Which spells you offer is a row of icons now**, not a stack of full-width
  toggles. Click one to stop offering it; it goes grey and stays where it is.
- **The settings stand in two columns** instead of one per line, which is what
  the rest of the window does.
- **A long page name cannot run off the sidebar** any more. It has a right
  edge now, so it is shortened rather than drawn over the OFF badge beside it.

## [4.69.0] - 2026-08-10

### Changed

- **A button is a button everywhere now.** Actions were drawn three different
  ways - a solid one, an outlined one, and bare text with no surface at all -
  so the same kind of thing looked like three kinds of thing. They all have a
  surface now.
- **The orange is rare again.** Fourteen buttons were painted in the accent,
  including "Delete this profile" and "Reset all settings" - the two loudest
  things in the window were the two destructive ones. Three are left, each
  one finishing something you started.
- **Buttons are as wide as their words.** Fifteen different widths were typed
  by hand at the call sites and none of them was measured, so a label that
  grew got clipped and a short one sat in a slab. One rule: the words plus
  their padding.
- **Half the prose is gone.** Forty-eight notes said what the game will not
  allow and why; they now say what the setting does, in a sentence or two.

## [4.68.1] - 2026-08-10

### Fixed

- **There is a way out of the key mode that you can see.** A **Done** button
  in the banner, and Escape now works from anywhere in the mode rather than
  only while a square is waiting for a key. Nothing is "saved" on the way out
  - every key is written the moment you press it - which is why it says Done
  and not Save. A fight ends the mode by itself, because keys cannot be bound
  in combat.

## [4.68.0] - 2026-08-10

### Changed

- **Setting a key is a mode on the screen now, not a list of rows.** Press
  **Set keys** and the panel comes out with a square over every place: click
  one, press the key, Escape when you are done. A key belongs to a place on
  the screen, and a row called "Slot 3" asks you to hold a picture of the
  panel in your head and count. The squares are their own frames on top -
  an answer cell is a spell button, and a click that reached it would cast.
- **The buttons on a page stand one under the other**, all one width. Three
  boxes shoulder to shoulder, each a different size, read as a toolbar
  somebody stopped styling; stacked they read as what they are - the short
  list of things the page can do. On the externals page they are a column
  beside the preview rather than a row above it.

## [4.67.0] - 2026-08-10

### Added

- **A release can announce itself in a Discord channel.** A webhook rather
  than a bot - no account to host and no permissions to hand out, just a URL
  a channel gives you. Set `DISCORD_WEBHOOK` in the repository's secrets and
  a tag posts its own release notes; leave it unset and nothing happens at
  all, which is what a fork gets. It never fails the release: the addon is on
  CurseForge by the time it speaks.

- **The keys are set in the addon now**, beside the slots they press: a Keys
  section on the External cooldowns page and on the Answering page, eight rows
  each. Click one, press the key, done - right-click clears it, and it says
  what the key was taken from if it was on something else. These write the
  game's own bindings with the same two calls its key panel makes, so they
  show up there too and survive a reload without this addon keeping a copy of
  anything. Out of combat only, because the game does not allow a key to be
  re-bound during a fight - and it says so rather than doing nothing.

### Changed

- **"Let's go" on the welcome window opens the addon.** It asks which
  features you want; closing onto an empty screen leaves you exactly where you
  were, with a settings window you have not found yet. Escape still just
  closes - one is "yes, show me", the other is "not now".
- **Edit Mode hands the window back.** Going in from the addon and coming out
  again reopens it. Going in from the minimap or from `/zs unlock` opens
  nothing, because there was nothing to hide. One rule rather than two: Edit
  Mode gives back what it took.

## [4.66.2] - 2026-08-10

### Changed

- **The changelog page reads as releases now, not as one long list.** A rule
  between them, air around it, a dot instead of a hyphen in front of each
  line - a hyphen sits on the baseline and at three lines of wrapped text it
  reads as punctuation - and the version you are actually running is marked
  **INSTALLED**, which is the first thing you look for after an update and the
  one thing a date does not answer.

## [4.66.1] - 2026-08-10

### Fixed

- **A taunt cell now taunts what that tank is fighting.** It was cast on your
  own target, which in a pull with adds is a different creature and a taunt
  wasted. His target when it can be taunted, yours when it cannot, so there is
  no press that does nothing. This is the one place in the addon that
  addresses somebody by unit rather than by name - "his target" has no name
  form - and the bar is rebuilt on every roster change because of it.

### Added

- **Keys for the external cooldown slots.** The first eight places on the
  panel, in the game's own key bindings under ZwoelfStuff. Bound to the PLACE
  rather than to the spell, because what sits in the third slot changes as
  people come and go - and pressing one with nothing in it says so instead of
  going quiet. Answer cells go from six keys to eight.
- **A quick menu on the answer bar.** A small button that appears when the
  mouse is over the bar and sets who you answer right there: the group forms,
  somebody picks up a second tank, and the settings window is on the other
  side of the screen. Clicking a name picks that person and switches to the
  mode that reads the list, because doing one without the other is a click
  that changes nothing.

### Changed

- **"Tank stuff" is now "M+ and raid stuff"** in the settings rail and in
  `/zs`.

## [4.66.0] - 2026-08-10

### Fixed

- **A cell lit up, took the press, and cast nothing - in silence.** The button
  listened for the mouse coming back UP only. Blizzard's own click handler
  compares the press it received against the game's "cast on key down"
  setting and RETURNS when they disagree: no cast, no error, no message of
  any kind. That setting is on by default, so the feature was never once
  going to work. Both directions are registered now, exactly as MRT and
  EllesmereUI do on every casting button they own, and it works whichever way
  the setting is set. The click is also written into the numbered attributes
  the game looks at first.
- **A taunt cell cast your taunt ON THE TANK WHO ASKED.** A taunt request
  means take the boss, so the spell belongs on your own target - aimed at a
  friendly player it does nothing, and says nothing. The two kinds of request
  are two different lines now, and the tooltip says which.
- **Spells your spec cannot cast were offered.** A holy priest was given a
  Pain Suppression cell that could only ever fail quietly, and worse, told the
  group that his Pain Suppression was ready - a spell with no cooldown running
  reads as available. The bar and every report now ask the spellbook. A filter
  that would remove EVERYTHING is refused instead: at a login or a talent
  swap the book is briefly unreadable, and one cell too many beats an empty
  bar.

### Added

- **Who gets a row is yours to decide.** The tanks, as before - or everybody
  in the group, which is the answer when nobody assigned roles, or people you
  name yourself in the order you want them. With a row count to go with it.
- **Keys.** Six cells can carry a binding, in the game's own key list under
  ZwoelfStuff, and the key shows in the corner of the cell. A binding cannot
  cast - that is the same wall this feature is built around - so these press
  the button for you, which is the one door from a keyboard to a spell an
  addon is allowed to open.
- **Taking the target as well**, off by default: the cast does not need it,
  and a healer who clicks a cell keeps healing whoever they were healing.
- **`/zs answers` is a report now.** It prints the switches, the game's
  cast-on-key-down setting, who has a row and why, and for every cell the
  macro line it would actually run - read off the button rather than from what
  the addon believes it wrote. Three separate causes of a silent click have
  been found by reading code; each one would have been a single line here.

## [4.65.3] - 2026-08-10

### Fixed

- **Clicking an answer cell did nothing across a realm boundary.** The macro
  addressed the short name, and `/cast [@Akui]` reaches nobody when Akui is on
  another realm - no target, no cast, no error. Every group member now carries
  the name a macro can actually address, with the realm on it only when it is
  a different one.
- **The co-tank panel crashed on 12.0 secret values, and took Edit Mode with
  it.** `UnitInRange` answers a SECRET boolean for a group member, and testing
  a secret raises. It never happened on one machine and happened every login
  on another, which is the shape of every secret-value bug so far: what is
  withheld depends on where you are standing. Every unit query in that
  snapshot goes through one guard now, and a withheld answer becomes the
  NEUTRAL one - unknown range is in range, because greying somebody out on a
  value the client refused to give is the display lying with confidence.
- **The keybinding never appeared in the game's key list.** `Bindings.xml` was
  listed in the TOC, so the UI XML parser read it instead of the bindings
  parser, and every line came back as "Unrecognized XML: Binding". The game
  loads a file of that name from the addon root by itself. Checked against
  five installed addons; not one of them lists it.

## [4.65.2] - 2026-08-10

### Fixed

- **A spell you switched off under "What you can be asked for" could not be
  switched back on.** Written `on and nil or false`, which never yields nil in
  Lua - `true and nil` is nil, nil is false, so `or false` takes over
  whichever way the switch went. It stored `false` either way: off exactly
  once, and never back.
- **The same line, twice.** The stand-in cell drawn while placing the bar was
  given a macro aimed at a player called "Tank" for the same reason - the
  exact thing the comment beside it says must never happen. Both are plain
  `if`s now, and the self test switches a spell off and on again through the
  real setter.

## [4.65.1] - 2026-08-10

### Fixed

- **The taunt button could not be moved in Edit Mode.** It had a mover, a cog
  and a padlock, and nothing dragged it: the drag was a hand-written pair of
  lines beside a hand-written list of movers, and the third panel was only
  added to one of them. Both now come off **one list**, so a panel that can be
  placed is a panel that can be dragged, by construction rather than by
  remembering.
- **The externals panel jumped back every time Edit Mode closed.** The
  position was worked out again from `GetCenter()` minus `UIParent:GetCenter()`
  - and those are in different units the moment the panel carries a scale of
  its own. Nothing else moves that frame, so it is simply not re-measured any
  more. Same fix on the taunt button and the answer bar.
- **The answer bar was invisible in Edit Mode.** Standing alone there are no
  tanks to build cells for, so it correctly drew nothing - which is useless
  when the point of Edit Mode is to decide where it goes. A stand-in cell is
  drawn while placing, and it deliberately carries **no macro**: a cell aimed
  at nobody must do nothing when clicked rather than fire at whatever you have
  targeted.
- **The taunt button had no look settings at all**, while a note on the page
  said they were "under Look on the right" - which is the co-tank panel's look
  and writes a different table. Opacity, icon zoom, border thickness, colour
  and texture, backdrop and its colour and opacity are on the page now.
- **A profile from before the slots existed threw on login.** Two migrations
  live in one function, and they were read newest-first: the lattice one
  deletes `count`, and the older list one then did arithmetic on it. Oldest
  first now, with a check that opens exactly that profile.
- `/zs externals` and `/zs taunt` print what the thing is actually painted
  with. "The colour does nothing" has two very different causes - a setting
  that never reached the painter, and a black line on a black plate - and one
  line now tells them apart.

## [4.65.0] - 2026-08-10

### Added

- **Answering** - a sixth module, and the other end of the External cooldowns
  panel. A tank asks for one of your cooldowns; the cell for that spell **on
  that tank** lights up, and clicking it casts. Your own taunt answers a
  tank-swap request the same way.
- **The addon channel** (`Core/Comm.lua`). Invisible, versioned and
  structured, so a request is a button rather than a line to read. The chat
  sentence still goes out for everybody who does not run the addon.
- **Somebody else's cooldown, finally.** The owner's idea, and it gets past a
  wall this addon has had since 4.58.0: a foreign cooldown cannot be *read* on
  this patch, but the person who owns it can *say* it - and their own client
  knows it exactly. So an externals slot now shows a real cooldown swipe for
  the person it would ask. The **duration travels with the message** rather
  than being assumed from a table, because talents move it: Lay on Hands is
  ten minutes, or eight with Unbreakable Spirit.
- Somebody who does not run the addon reports nothing, and their slot shows
  **nothing** - not a hopeful clock.
- A green ring on your slot when somebody is actually casting what you asked
  for. It is sent when the spell goes out, not when they click, so it means
  "it is happening".

### Known limits, on the page itself

- **Only people who also run ZwoelfStuff** can light up. That is the trade for
  everything above.
- **The addon never casts.** You press the cell and the game casts. That is
  also why the bar stands there permanently and only brightens: which spell a
  cell casts, and on whom, is written while you are out of combat, and the
  game does not allow it to be rewritten during a fight. The cells are named
  when the group changes - which is exactly when the owner asked whether they
  could be.
- The bar is **off until you switch it on**. Until then a request is printed
  once, naming the switch, so a feature that would silently do nothing says
  what it is instead.

## [4.64.0] - 2026-08-10

### Added

- **Three ways to ask the other tank for a taunt**, and they all run the same
  line. Owner: "kann man das nicht einbauen, also fertiges dynamisches macro,
  und als button zum stylen mit icon auswahl?"
  - **A button on your screen.** Placed in Edit Mode like everything else this
    addon draws, with the same cog and padlock the panels have, painted by the
    bar's own painters. Off by default.
  - **A keybinding.** The game's own Key Bindings window has a **ZwoelfStuff**
    section with *Ask the other tank to taunt* in it - no macro needed.
  - **A macro the addon writes and keeps.** "Make the macro" on the Co-Tanks
    page creates **ZS Taunt** with your chosen icon and updates it in place
    afterwards; drag it onto a bar once and it stays right.
- **An icon picker.** Your class taunt is the default and the likely icons sit
  on their own row at the top; the rest of the game's macro icons are a paged
  grid under them. No search box, and that is a decision: this client answers
  `GetMacroIcons` with file IDs and no names at all, which is exactly why
  Blizzard's own picker is a nameless grid you page through.

### Changed

- The taunt button belongs to the **Co-Tanks module**: one switch turns off
  the panel, the announce and the button together, and its mover reads that
  same switch.
- The button's border and backdrop are the **bar's settings under the bar's
  key names**, so `ns.PaintSurface` and `ns.PaintBorder` paint it without
  knowing what it is. There is still exactly one renderer in this addon.
- The self test pins what cannot be seen: that the macro name fits the game's
  sixteen-character limit (over it, every press would make another macro), that
  the keybinding has a global to call and strings to show, and that the icon
  pager does not run off the end of the last page.

## [4.63.0] - 2026-08-10

### Added

- **The taunt announce** (roadmap item 6, the owner's own order: 10, then 6,
  then 1). Press your taunt and one line goes out in chat, so the other tank
  knows you took it. Settings are on the Co-Tanks page, under **Taunts**.
- The message is yours to write: `%t` is what you taunted, `%s` is the taunt
  you pressed, `%n` is the other tank. A placeholder nothing filled comes out
  of the sentence rather than being read out as "%t" by somebody mid-pull.
- **`/zs taunt ask`** tells the other tank to take it - the other half of a
  swap, and the half an addon can actually do something about. Put it in a
  macro and give it a key.
- `/zs taunt` prints what your next taunt would say, who it thinks the other
  tank is, and which channels it would go out on.
- **It is off until you ask for it.** An addon that starts writing in party
  chat after an update is the worst surprise it could hand somebody, and the
  self test checks that promise rather than trusting it.
- Two presses inside two seconds are one announce. A taunt that misses is
  pressed again immediately, and a tank who spams his own group over it
  switches the feature off and never comes back.

### Changed

- **`Core/Chat.lua`** - which channel a message actually goes on, in one
  place. It was written inside the externals panel and now has a second
  caller; a second copy of those rules would be a second chance to get the
  one that matters wrong. (`/p` is NOT party chat in a dungeon from the
  finder - that group talks on INSTANCE_CHAT and a message to PARTY arrives
  nowhere, silently.) The externals panel keeps every name it had.
- Writing a sentence is one pass with a function replacement now, so a mob
  called "%n the Devourer" cannot be read as a placeholder by a substitution
  that comes after it - because none does.
- **Who is in your group** moved to `ns.Roster` in Init.lua. The taunt
  announce asks the same list a different question - "who is the other tank" -
  and two walks over one party would be two chances to disagree about who is
  in it.

### Known limits, stated on the page itself

- **It cannot tell you when the OTHER tank taunts.** Since 12.0.5 another
  player's instant cast is not announced to addons at all, the combat log is
  closed, and every taunt in the game is instant. Anything claiming to show
  you the co-tank's taunt on this patch is guessing. Yours is readable, which
  is why this says yours out loud instead.
- **"Swap at X stacks" is not possible**, and will not be in 12.1 either: a
  foreign aura's value cannot be read, only displayed.

## [4.62.0] - 2026-08-10

### Added

- **A panel's mover has a cog and a padlock**, the same two a bar's mover has.
  Owner, with a screenshot of the externals mover: "hier fehlt noch das
  zahnrad fuer einstellungen und das lock item!" The two kinds of mover are
  one idea, and having half the controls on one of them was something to
  discover rather than to learn.
- The cog carries **Centre on screen**, **Centre horizontally**, **Centre
  vertically**, **Pin in place**, **Settings** - which leaves edit mode and
  opens that panel's own page - and **Switch off**, which switches the module
  off from where you are looking at it.
- **Pinned means it does not move.** It still selects, it still opens its
  settings; it is simply not what a stray drag lands on. The co-tank panel's
  own drag honours it too, which is a second door to the same frame.
- Both controls sit on a **strip above the box** rather than in a corner of
  it. A panel can be one icon square - a single-slot externals panel is forty
  pixels - and two twenty-pixel buttons do not fit inside that at all.

### Changed

- `CreatePanelMover` takes one spec table now: label, origin, apply, config,
  page, module. Built once, so the co-tank panel and the externals panel got
  the cog and the padlock in the same change rather than one of them getting
  it and the other waiting for somebody to notice.
- The self test checks both movers carry both controls, that a pinned panel
  refuses the drag - through the real handler, not a restatement of the rule -
  and that the two keys behind the cog name a page and a module that exist.
  Both are strings handed to something that quietly does nothing when it does
  not recognise them.

## [4.61.0] - 2026-08-10

### Fixed

- **The slots on the External cooldowns page were not drawn at all**, which
  read as lost saved data: an empty band over a "Who to ask" list that still
  named the spells. Owner: "nach rl ist mein preset von meinen external cds
  immer weg." Nothing was ever lost. The frame the slots sit in had ONE
  anchor point and a height and no width, so its rectangle could not be
  worked out - and a frame like that is not drawn, and neither are its
  children. The band's own eyebrow and hairline are regions of the band
  itself, so they kept drawing and hid what had happened.
- **A chat channel you switched off came back at the next login.** It was
  listed in the defaults, and a channel that is off is stored by being
  missing - so the default filled it back in every time. The same rule the
  welcome window follows: what the player answered is not something to have a
  default for.

### Added

- **Rows and columns, the two words a cooldown bar uses.** Owner: "anzahl rows
  fehlt! wie die cdm einstellungen, reihe und spalten anzahl." Rows times
  columns is how many places there are, so the count is not a separate setting
  that could disagree with the line width any more. A panel written before
  this reads its old count and line width once, becomes the same shape, and
  drops them.
- **The preview in the band IS the panel's lattice**, laid out by the same
  function the panel uses - `Externals.Cell` - so what you arrange is the
  shape you get. It shrinks to fit the page rather than clipping or scrolling:
  a lattice you cannot see all of is not a preview of anything.
- **Move the panel, Test mode and Who would be asked sit in the band**, with
  the slots they act on. Owner: "auch sollte der test mode button etc da mit
  hoch." Test mode says which state it is in rather than looking the same
  either way.

### Changed

- **What you say moved directly under Who to ask**, at the owner's word, and
  everything about how the panel LOOKS follows after it. Who you ask and what
  you say to them are one thought; borders and backdrops are a different
  afternoon.
- `/zs externals` prints the lattice and every slot in it, filled or empty.
  "My panel is empty" has two completely different causes - nothing saved or
  nothing drawn - and one line now tells them apart.
- One "Who to ask" row is built per spell that exists rather than per slot
  that could exist. A spell lives in exactly one slot, so fourteen is the real
  ceiling however large the lattice gets.

## [4.60.2] - 2026-08-09

### Added

- **The externals preview stays put while the settings scroll under it.**
  Owner: "vorschau sticky machen! sprich content darunter scrollt." It is the
  thing being edited, and the rows below it are the settings for it - watching
  your own slots while you change how they look is what a preview is for.
- `UI.Page` grew an `opts.sticky` band for it: a strip at the top that does
  not scroll, filled by the page and measured by it. The scroll area starts
  below the band and clips its own children, so nothing can be drawn into it
  from underneath.
- The band is as tall as the slot rows actually shown, re-measured whenever
  the count changes. Sized for all twenty-four it would hold a third of the
  page empty for slots nobody asked for.

## [4.60.1] - 2026-08-09

### Changed

- **"Who to ask" sits directly under the slots**, at the owner's word. It
  belongs there: those rows and the slots above them are the same decision
  seen twice - which spells do I want, and who gives me each one. Everything
  below is what the panel looks like, which is a different afternoon.

## [4.60.0] - 2026-08-09

### Added

- **The externals panel is styled like a cooldown bar**, because the owner
  asked for exactly that: "genau wie die anderen optionen beim cdm". Scale,
  opacity, icon zoom, border thickness/colour/texture, backdrop
  show/colour/opacity/texture - the same rows, the same words.
- **And it is not a second renderer.** The settings are stored under the SAME
  key names a bar uses, so `ns.PaintSurface` and `ns.PaintBorder` paint the
  panel without knowing what a panel is. A change to how a border is drawn
  reaches both without anybody remembering there are two places - which is the
  fault this addon has already paid for twice, once in the aura strips and
  once in the death window's preview.
- The self test checks every one of those key names against
  `ns.BAR_STYLE_KEYS`. Rename one and the painters would quietly keep using
  the defaults while the setting appeared to do nothing.

### Changed

- The hover outline on a panel icon is the panel's own, drawn above the
  border: it says "this is the one you are about to press", and it has to be
  visible whatever border you chose - including none.

## [4.59.1] - 2026-08-09

### Changed

- **The channel is a MULTIPLE choice.** Owner: "wir brauchen hier eine
  mehrfachauswahl, sorry, das hab ich falsch kommuniziert." A whisper to the
  one person who can cast it AND a line in party chat is a reasonable thing to
  want - the first is aimed, the second is insurance. Chips rather than a
  select, because five yes-or-no answers all need to be visible at once, which
  a dropdown showing one line cannot do however it is worded.
- **Two choices that come out the same are sent once.** "Raid warning" and
  "Party or raid" both resolve to `RAID` for somebody without assist, and one
  sentence twice in one channel is a person spamming their own group because
  of a setting they thought was two different things.
- **A whisper with nobody to whisper no longer stops the rest.** It is dropped
  and the other channels still carry the message; only when it is the ONLY
  channel is the press refused.
- **The last channel cannot be switched off.** A button that sends nowhere is
  not a setting, and the click that emptied it is the one nobody notices
  making.
- `UI.ChipRow` grew an `isOn` predicate beside its `current` one, so the same
  widget does both the filter shape it was built for and this one.

## [4.59.0] - 2026-08-09

### Changed

- **The externals panel is SLOTS now, the way the cooldown bars are.** It was
  an ordered list, which is why "how many slots" changed nothing and why there
  was no empty third slot to click on. There is a count, a sparse table of
  what is in each place, and a profile written before this pours its old list
  into the slots once.
- **Click a slot and it stays marked**, and the next spell you click in the
  list goes into THAT one - the same gesture the Cooldowns page runs on. A
  marked slot is cleared once it is used, or the next click would overwrite
  what the last one just placed.
- **A spell can only be in one slot.** Putting it somewhere else moves it
  rather than leaving a second copy, which would whisper twice for one click.
- Taking the count down and back up gives you what you had: a slot beyond the
  count keeps its spell, the same rule a shrunk bar follows.

### Added

- **Where the message goes**: whisper, party or raid, raid warning, say, yell.
  **"Party or raid" picks the right one for the group you are actually in** -
  and that is the point of it: `/p` is NOT the party channel in a dungeon from
  the group finder. That group talks on `INSTANCE_CHAT`, and a message sent to
  `PARTY` there arrives nowhere at all, silently. `IsInGroup(2)` is the test,
  taken from BigWigs, which picks its channel exactly this way.
- A raid warning outside a raid, or without assist, falls back to the group
  rather than refusing - the message still wants to arrive - and says which.
- **`%n` in the message is the person being asked**, next to `%s` for the
  spell. Worth having in party chat, where "Ironbark bitte!" asks nobody in
  particular. With nobody to name, the placeholder is removed rather than
  printed.

### Fixed

- `gsub` answers a string AND a count, and handing that pair straight to
  another `gsub` makes the count its LIMIT - "replace at most 0 times". The
  message went out with a literal `%s` in it. Caught by the self test, which
  is the only reason it is in this section rather than in a screenshot.
- A client with no chat API is a sentence now, not an error thrown under the
  cursor.

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
