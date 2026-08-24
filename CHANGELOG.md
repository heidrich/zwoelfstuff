# Changelog

All notable changes to ZwoelfStuff are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

This file carries the recent versions. Everything before 4.70.0 lives in
[CHANGELOG-ARCHIVE.md](CHANGELOG-ARCHIVE.md) — the packager posts this whole
file as the GitHub release body and the CurseForge file changelog, and GitHub
stops accepting it at 125,000 characters. When it grows past 100,000, the
oldest versions move over.

## [4.89.0] - 2026-08-23

### Added

- **The raid check reads players without the addon** — buffs where the game
  allows it, gear over the inspect, durability over the channel MRT and
  BigWigs use. Grey means not read — never a no.
- **Enchants column** — how many enchants are missing.
- **A magnifier beside every name** opens a player card: every worn item
  with its level, missing enchants marked, the spec and a talent string
  ready to copy.
- **The talents dock beside the card, drawn** — every chosen one at its
  place on the board, the hero tree below.

### Fixed

- An answer that said nothing about food or flask was drawn as a red cross.
  Not read shows the waiting mark now, per column.
- Two players with the same name on different realms no longer swallow each
  other's addon messages.
- Clearing the group death log holds now — the last pull used to come
  straight back on its own.
- An external a group-mate has not skilled is not asked of them — and a
  refusal names who and why.

## [4.88.1] - 2026-08-22

### Changed

- Casts on you is marked **Beta** — in the menu and on its page.

### Fixed

- The preview above the tabs was empty until something real was casting.
  While the page is open, the three invented casts stand in — the bar draws
  and the alerts fire. With the module off, the band says so.

## [4.88.0] - 2026-08-22

### Added

- **Every ability says what you can do about it** — the mob card marks what
  can be kicked, dispelled or soothed, and what leaves a poison, bleed,
  curse or disease. Searching `kick` lists every mob with a kickable cast.
- **The death log knows the season's mobs** — click your killer's portrait
  for its card. Portraits of season mobs draw immediately.
- The mob card shows the M+ forces a mob is worth.
- New alert and voice token `%spell`: names the cast when the mob has
  exactly one known ability, else it says "something".
- When a new season starts, the addon says once that its mob list needs an
  update.

### Fixed

- The list opens on the dungeon you are standing in on every client
  language, not only English.

## [4.87.0] - 2026-08-22

### Added

- **The mob list is searchable** — type a mob or an ability name. Chips
  narrow the list to bosses, lieutenants or mobs.
- **Dungeons fold to one line each**; the dungeon you are standing in starts
  open, on top. Watched mobs sit in their own group above everything.

### Changed

- A mob the season lists twice under one name is one row now. Watching it
  covers both variants.

### Fixed

- An alert watching a rank the bar ignored could never fire. The bar's
  filters now apply to the bar alone.

### Removed

- The self-learned mob list and its Forget button — the season list
  replaced them.

## [4.86.0] - 2026-08-22

### Added

- **The season's mobs are in the addon.** All 16 dungeons, 462 mobs and 79
  bosses, each with its own portrait, under the dungeon it belongs to.
- **Click a mob for its card** — 3D model, NPC id, level, creature type,
  health, and every ability it casts with the game's own tooltip on each.
- **`/zs tanks auras`** says why the co-tank aura strips are empty.

### Changed

- **The mob list is sorted boss, lieutenant, then mob** within each dungeon,
  and each rank has its own colour.
- **Mob rows answer the cursor** — rank, type and ability count on hover.
  Right-click watches a mob without opening its card.
- **Mob filters are keyed by NPC id** instead of by name, so a picked mob
  matches whatever language the client is in. Filters picked before this keep
  working.
- **The addon is now GPL v2.** The season mob data comes from Mythic Dungeon
  Tools by Nnoggie, which is GPL v2.

### Fixed

- **Casts on you counted players.** Any player casting anything got a bar and
  a line in the mob list. Only enemy NPCs now.
- **Co-tank aura strips could fail without saying so.** A refused aura group
  left an empty container in place and printed nothing.

## [4.85.1] - 2026-08-19

*Casts on you — the first round of what a real key found.*

### Fixed

- **The spell's name was painted underneath the bar** and had never been
  visible. Everything readable now sits above the fill.
- **Test mode claimed three casts were on screen while the module was off.**
  It now says the module is off.
- **The cast icon had no border, and the bar had two.** The icon has its own
  now.
- **A refused value no longer takes the rest of the bar with it** — the bar
  falls back to the caster's name instead of stopping half-drawn.

### Added

- **"ON YOU" in words** above the cast bar. Words, stripe, both or neither —
  and you choose what they say.

## [4.85.0] - 2026-08-19

### Fixed

- **Thanks to b9ty on CurseForge for the report.** Opening Blizzard's inspect
  window on somebody in your group could show **every equipment slot empty**
  while the 3D model still wore their gear — no error message, and it came
  and went often enough to look like Blizzard's own bug. It was ours.

  The client keeps exactly **one** inspect target. The spec cache — the part
  that knows a priest is Discipline rather than Holy, so the external cooldown
  panel offers the spell they can actually cast — has to ask the server about
  people, and asking moves that one target. It was asking every two seconds
  while you had the window open, and it was also releasing each answer when it
  arrived, including the answers it never asked for. Yours was one of those,
  and releasing it is what emptied the slots.

  It now waits: while the inspect window is open, and for a moment after the
  click that opens it, the queue holds still. Learning resumes the second you
  close the window — nothing is forgotten in the meantime — and an answer this
  addon did not ask for is left where it lies.

### Added

- **Casts on you — a new module, marked *coming soon* and switched off.**
  It ships in this file rather than waiting for a release of its own, because
  the fix above should not wait for it. Everything below works; none of it
  has been through a real week of dungeons yet, the page says so at the top,
  and nothing in it runs until you switch it on. If you would like to help
  find what is wrong with it, turn it on and say so on the Discord.

  What it does: a bar where you are already looking, showing what the mob in
  front of you is casting, how far along it is, whether it can be kicked, and
  a mark down its left edge for the one question a tank actually asks — *is
  that one coming at me*. That mark is not our guess: the client answers it
  and draws it, so it is right even though no line of the addon is allowed to
  look at it. **Test mode** puts three invented casts on screen so you can
  place the bar without a dungeon.
- **Alerts about them, and they are reminders.** A third book on the
  reminders' own type — the list, the preview card, *What it says*, the look,
  the flash, the rules and the edit-mode box are the ones you already know.
  An alert watches a **kind** of cast (ordinary mobs, lieutenants, bosses)
  and **who it is aimed at**, and its words carry both: `%rank casting at
  %who` is the default, `%mob` names the caster. Each alert is placed in Edit
  mode like every other message.
- **Only these mobs.** The right-hand column lists every mob you have seen
  cast something, filed under the place you met it, and it fills itself as
  you play. Click one to narrow the selected alert to it; click it again to
  drop it. This is the part that could not be a list of spells — see below.
- **A voice, and it can be somebody else's.** A line spoken when an alert
  appears, with your own words in it. It plays a **recording** if you pick
  one — anything a voice pack registers with the shared media library shows
  up in the list, so BigWigs +Voice, the DBM packs and their community ones
  are all reachable — and falls back to the client's own text-to-speech when
  you do not. Off until you switch it on, with a wait between lines so three
  mobs starting the same cast is one sentence.

### Changed

- The options window is 30 pixels taller. The rail ran out of room at the
  fourteenth page, exactly as the self test's margin check exists to catch.
- **New Discord.** The invite under *About*, at the foot of the rail and in
  the readme all point at the current server. There is one address written
  down in this addon and everything else reads it, so all three moved
  together.

### Notes

- **The spell being cast cannot be named, by this addon or any other.** Since
  patch 12.0 the id and the name of a hostile unit's cast are withheld from
  addons: they may be handed to the game to draw — which is why every
  nameplate still shows the cast — and may not be read, compared or looked
  up. It is why LittleWigs ships **zero** named trash warnings for Midnight
  where it had 33–38 per War Within dungeon, and why the boss mods identify
  boss abilities by the length of Blizzard's own timer instead. This module
  shows everything that IS answerable and says so where the game refuses.
- **"At you" has two halves and the module uses both.** The certain one is
  the client's: it draws the mark on the bar and never tells us. The other is
  a best-effort read of the target's role and class, which a dungeon can
  withhold — so alerts have a fifth choice, *at somebody the game will not
  name*, and it is **on** by default. A warning you never got because a value
  was withheld is worse than a spare one.

## [4.84.0] - 2026-08-17

### Added

- **The answer bar gets alerts — and they are reminders.** A new *Alerts*
  tab on the answer page is the reminders page, one for one — the list, the
  preview card, *What it says*, *What it watches*, the look, the flash, the
  rules — on a book of its own that fires when **somebody asks you** for the
  spell. The right-hand column lists your answer spells; click or drag one
  onto the slot. The words carry the asker: `%who asks for %spell` is the
  default and both tokens are filled in when it fires. **When it comes down
  is yours to pick** — when answered or run out, after a number of seconds,
  or after a number of flashes; casting the answer takes it down early under
  every one. Each alert is placed in Edit mode like every reminder. Under
  the hood the reminders became a class with two instances, so the two
  cannot drift; the Reminders page itself is unchanged.
- **The answer bar gets its display conditions** — the same *When to show
  it* block the reminders and the bars carry: always / only when… / never,
  combat, group, target, rested, the six kinds of place, and — new for every
  rule in the addon — **the role you are playing**: as a tank, as a healer,
  as damage, three switches. The old *Only in dungeons and raids* switch is
  folded into that rule (every place but the open world) and is gone as a
  switch of its own. The rule is applied as opacity, so a rule about combat
  can flip mid-fight; *Otherwise* sets what a hidden bar looks like.
- **The answer bar's look, the parts that had no control:** *Opacity when
  asked* (the lit state, beside the resting one), *Name size*, *Show the
  key*, and the shout's *Ring colour* and *Ring thickness*. Asked for on
  Discord.
- **One builder for "when to show it".** The block was typed out on the
  cooldowns page and again on the reminders page; both read from the same
  builder now, so every page with a rule shows the same rows in the same
  order — the reminders page shows the role and rested rules for the first
  time.

### Removed

- **Routes** (MDT pull badges on nameplates, parked since 4.42) is gone from
  the source. Brought back for one evening as an experiment, it measured the
  last doors shut: 12.1 refuses the combat log outright, and a cast names the
  kind of mob, not which one — and only once it is already casting. Nothing
  leads to "this mob is pull 7", and pull trackers without that exist in
  plenty. A `routes` table left in your profile by 4.4x is removed.

## [4.83.0] - 2026-08-16

### Changed

- **The Cooldown Manager is temporarily disabled** — we are not satisfied
  with the result.
- **One look, out of the box.** Every background and every border in the addon
  — icons, bars, plates, troughs, panels — is now **#1a1a1a and opaque**, and
  everything the addon writes on the screen is set in **Expressway, outlined,
  never under 10 pixels**. Owner: *"wir müssen den usern direkt vom start weg
  eine schöne UI anbieten."*
  - **It was one decision written down fourteen times**, in fourteen files, as
    the literal `{ 0, 0, 0 }` — which is not fourteen settings, it is one
    setting that cannot be changed. It is named once now and asked for by
    name; a new module that types black instead fails the desk on the first
    run.
  - **Two automatics went out.** Bar text used to fall back to "whatever your
    other addons happen to have registered", and tracking-group text was drawn
    in Blizzard's number face — so a group and a bar side by side were set in
    two different fonts and no setting anywhere said so. There is one screen
    face now, and one control that sets it.
  - **The "Bar text" control is back.** It had a default, a translation and a
    reader, and the row that set it had gone missing — the one setting that
    decides what every bar is written in could only be changed by editing a
    saved-variables file.
  - **The minimum text size moved from 6 to 10.** Six is where a number stops
    being legible at all; ten is where it starts being worth putting on
    screen. A size stored below it is clamped as it is read — nothing rewrites
    a number you typed.
  - **Two colours deliberately stayed.** The co-tank panel's aura strips keep
    their red and green edges — that line is the only thing that says which
    strip you are looking at — and the cooldown sweep keeps its black, because
    a grey veil makes a ready icon and a spent one look more alike.
  - **Your existing profile is brought along, once.** Anything still wearing an
    older default moves to the new one; **anything you picked yourself stays
    exactly where it is**, and it happens once per profile rather than every
    login. **Settings › Standard look** is the same rule with force, for when
    you want it all back on purpose. It reports how many settings it moved
    rather than saying "done".
  - **The options window is unchanged.** It has its own face and its own
    palette; this is about what the addon draws out on the screen.
  - **We do not ship Expressway.** If your client has it — most UI addons
    install it — you get it. If not, the closest narrow grotesk you do have is
    used instead of Blizzard's serif.
- **Co-Tanks are called Tank Unitframes** — in the sidebar, in Edit Mode, in
  the module list — because that is what they are in the vocabulary every
  player already has. Nothing in your saved profile changes name.
- **The tank unitframes ship set up the way the author runs them:** your own
  row in the stack, only inside a dungeon or raid, rows of 30 with air between
  them growing *up* from below the middle of the screen, the flat bar
  texture, a white name, larger debuffs and a centred combat mark. A profile
  you have already tuned is not touched — these are the defaults a fresh one
  starts from.
- **The taunt button can be limited to raids.** A dungeon has one tank, and a
  button asking the other one to take it is asking nobody. *Only in a raid*
  sits beside *Only in a group*, off by default. **Create macro for action
  bar** — the button that writes *ZS Taunt* — moved from the page header down
  to the icon it writes.
- **The default chat lines are English.** *"%n, please taunt!"* and *"%s
  please!"* were German in an addon that ships in English; anything you typed
  yourself is kept.
- **The pages say less about themselves.** *"To move it, open Edit mode"*,
  *"The button is placed in Edit mode like everything else"*, *"Pick from
  the list on the right"*, the *Keys* paragraphs on three pages, and *"Your
  client has Blizzard's aura engine"* are gone — the list *is* on the right,
  Edit mode *is* at the top of the rail, and a sentence about the absence of
  a problem is not a setting. Reports meant for the desk (*What a taunt would
  say*, *What every cell would cast*, *What is listening*) left the page
  headers; the slash commands still print them.
- **The Invites page is two columns again.** Every switch used to be followed
  by a paragraph, so no two could share a line and ten yes-or-nos ran down one
  side of an empty page. Each switch carries its one line underneath it now;
  the three things the page *does* — invite the guild, invite everyone back,
  disband — moved into its header.
- **The death window has a third column.** What you pressed, what you still
  had and did not press, and everything else you cast are rows down the
  left now — icon, name, seconds before the end or *ready / 25s / none* —
  the way the session's deaths are rows down the right. They used to be
  sentences with icons in them over the table and a strip of chips under it,
  and the header read as one block. *"What you had, by our own clock"* is
  **Unused defensives**, and it no longer lists the ones you did use with a
  cooldown as if the press had never happened. The legend under the table
  says what it means in six words: *grey your health, red the damage taken*.
- **A potion is pictured as the potion you drank.** The line at the top used
  to show the generic icon of the spell a Silvermoon Health Potion casts;
  the list at the bottom read the item and showed the bottle. One picture
  now, everywhere — the panel, the verdict, the replay's bars.
- **A Healthstone counts as a defensive.** On this patch pressing one fires
  *"Use Healthstone"*, which is not the spell the client names for the item,
  so the press sat in the rotation row of the replay while the log called
  the stone ready and unused. It is recognised by name as well as by spell
  now, and gets its bar in the defensives lane.
- **The replay draws the damage you took as a graph** under the defensives
  lane — one column per slice of the visible seconds, red for what landed and
  a lighter cap for the overkill, scrolling and zooming with the plot and
  filling in as the line passes. A **Graph** switch beside Zoom hides it,
  remembered per profile.
- **The replay has the same panel down its left**, in place of the
  *"Defensives used:"* strip under the plot. **Left button held over the plot
  scrubs**: the yellow line goes where the hand goes, the replay pauses under
  it, and zoomed in the band follows the line. The wheel still pans.
- **The mob in the hover tip is a portrait, not a turning model** — in the
  death window, the replay and the group death log.
- **Every hit row wears the face of what did it**, in front of the WHEN
  column, in the death window and in a group death opened from the log —
  point at it for the same enemy tip the other windows show. Deaths recorded
  before this update are brought up to date when they are shown: a potion
  gets its bottle, a Healthstone its bar.
- **The real logos.** CurseForge, Wago, GitHub and Discord each wear their
  own mark now — the official vector marks, rasterised at every size the
  addon draws — in the sidebar's foot, on the About page and along the foot
  of the welcome window, where the four links are new. GitHub is linked for
  the first time.
- **The side lists name the place and show it.** Every death in the death
  window's list, and every pull in the group log's, carries a third line:
  the dungeon or raid by name with the Adventure Guide's own tile beside it
  — **click the tile and the guide opens on that instance.** The tile is a
  column of its own, as tall as the row and in its true shape; the name is
  in the blue every place in the addon wears. The columns grew wider for it,
  the rows taller, and every line in them is one size. Recorded from now on:
  an older entry knows only "Dungeon".
- **A group death opened from the log** shows the mob's face in front of its
  name in *Killed by* and *The hit that mattered*, the enemy tip on both, and
  the ability with its icon in front and its tooltip — the same as every row
  under them. The **Killing blow** line at the foot of the log (it was *What
  did the killing*) is built the same way: every mob wears its face, every
  name and every ability answers the mouse. The place in the header is blue.
  A mob this death kept no picture of borrows its face from any other kept
  pull.
- **The replay names its killer with a face.** *Replay - killed by* carries
  the mob's face in front of its name and the enemy tip on both; the place
  under it is blue. The **Graph** switch sits above *Play*, on the graph's
  own edge, instead of at the far end of the control row.
- **The evening's tally has pictures.** *What keeps killing us* shows each
  mob's face, *Who is falling* each player's spec or class icon, in a column
  between the count and the name.
- **The welcome window says what the addon is**: *A Tank and Group Play
  addon*, under the name.
- **Nothing picked is a door.** Open the death log with no defensives or no
  consumables chosen and the panel offers *Set up your defensives* / *Set up
  your consumables* — one for each half that is empty — straight to the page.
- **The reminder list shows which one is picked.** Each name sits on a chip
  and the chosen one is lit, the same way the filter chips over the spell
  list are; one orange word in a row of grey ones did not read as a choice.
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

- **The group log's pulls forgot their place on /reload.** The dungeon's name
  and its guide tile were recorded and shown, and gone after the next reload:
  the full pull was written without them while the evening's thin copy kept
  them. Both copies carry them now, and pulls saved in between take theirs
  from the evening's copy of the same pull.
- **The co-tank trough had missed the standard look.** The step that moves
  the empty part of the bar to #1a1a1a opaque joined the migration one commit
  after the migration had already run on the author's profile, so his panel
  kept the old 12% trough while the desk reported the move complete. It runs
  now, once, and only for a trough still wearing the old value.
- **The Edit Mode tools are back.** The grid and its step, snap-to-grid, how
  far a snap catches, the screen dim and the coordinates had gone out with
  the old bars page - though they are about placing panels, which Edit Mode
  still does all day. A **Tools** button on the Edit Mode toolbar opens them
  again.
- **`/zs test` no longer fails during a fight.** Five checks moved real key
  bindings or asserted a bar "waiting for combat" — run *in* combat, the
  game refuses the former and grants the latter, and all five went red on a
  healthy client. They say "not checked: in combat" now, like every other
  check that needs a world it is not in.
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

---

Older versions: [CHANGELOG-ARCHIVE.md](CHANGELOG-ARCHIVE.md).
