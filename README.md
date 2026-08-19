# ZwoelfStuff

**A tank and group-play addon, from Zwölf — EU-Destromath.**

ZwoelfStuff is a small tank addon with an advanced **death log with live
replay**, **tank unitframes** with taunt requests, a **spell reminder** system,
and **external cooldown requests and answers** that work with one click.

After many years I have built a new addon again, one that serves my own needs
as a tank first, and those of my M+ groups and friends. You will find a lot of
these features in other addons too — but like everybody, I have my own ideas
about what I want in the game. Hence this addon. I hope it is as useful to you
as it is to me.

**This addon is no replacement for EllesmereUI or ElvUI.** I love both of them
and use them for my own UI. This is a collection of the features I like, done
my way. And of course — feature requests and feedback are welcome!

For questions and feature requests, join the Discord:
**<https://discord.gg/mBWHSNNXZS>**

| | |
| --- | --- |
| CurseForge | <https://www.curseforge.com/wow/addons/zwoelfstuff> |
| Wago | <https://addons.wago.io/addons/zwoelfstuff> |
| GitHub | <https://github.com/heidrich/zwoelfstuff> — releases carry the same zip |

## Features

1. **Tank unitframes** — every other tank in the group with their health,
   absorbs and defensives, and a taunt request on the frame.
2. **Spell reminder system** — a line of text on your screen when a buff you
   rely on has fallen off, or while it is up. You write the sentence.
3. **Advanced death log with live replay** — what killed you, played back
   second by second, and what you had that could have stopped it.
4. **External cooldown request** — pick your set, and ask for any external in
   any dungeon or raid with one click.
5. **External cooldown answer** — react in no time to a request: when a tank
   asks for one of *your* cooldowns, a button lights up. You press it.
6. **Tank swap request, and the taunt on click** — one button on the tank
   unitframe, or a macro it writes for your action bar.
7. **Module system** — activate or deactivate any module you like; what is off
   costs nothing and leaves nothing on the screen.
8. **Raid tool bar** — markers, world markers, pings, a ready check and a pull
   timer, on a bar you build yourself.
9. **Auto invite system** — somebody whispers "inv" and they are in the group;
   invite the guild, invite everyone back, disband, from the same page.
10. **Casts on you** — a bar where you are already looking that says what the
    mob in front of you is casting, whether it can be kicked, and marks the
    one that is coming at *you*. With alerts, a voice, and a list of the mobs
    you have met.

Everything is set up in one window: `/zs`.

## The modules

### Tank unitframes

One row per tank in your group — health, absorbs, the defensives they have
running, and who has the boss. The rows sit where you put them; the taunt
button on each row whispers *"%n, please taunt!"* (your own text) and can be
limited to groups or to raids. *Create macro for action bar* writes a `ZS
Taunt` macro so the same request is a keybind. The layout ships as the author
runs it and every part of it is a setting.

### Casts on you

A bar in front of you rather than on a nameplate behind the boss: the icon of
what is being cast, how far along it is, whether it can be interrupted, and a
mark down its left edge while the cast is aimed at **you**. That mark is the
client's own answer — the game draws it, so it is right even though addons
are not allowed to read it.

**Alerts** are reminders: the same page, the same look, the same flash, placed
in Edit mode like every other message. One watches a *kind* of cast (ordinary
mobs, lieutenants, bosses) and *who it is aimed at*, and can be narrowed to
particular mobs by clicking them in the list on the right — that list writes
itself out of what you meet, filed under the place you met it.

**A voice** can speak the line: a recording out of any voice pack your client
has, or the client's own text-to-speech when you have none.

One thing this cannot do, and neither can anything else on this patch: **name
the spell**. Since 12.0 the id and name of a hostile cast are withheld from
addons — they may be handed back to the game to draw and never read. It is
why the boss mods stopped naming dungeon-trash abilities in Midnight. What is
still answerable is shown, and where the game refuses to answer, the page
says so rather than guessing.

### Death log and live replay

Every death you take is kept with its last ten seconds: what hit you, for how
much, what was left, and the mob behind every hit with its face and a tooltip
that sums up what it did to you. The panel on the left lists the defensives
you used, the ones you had and did not use, and the potions and healthstone —
and if you have not told the addon which defensives and consumables are yours,
it offers the two setup pages right there.

**Replay** plays those seconds back on a timeline: your health, the damage on
you, your casts on their own lane, a damage-taken graph underneath, and a line
you can drag. **Deaths in the group** does the same for everybody else in the
group — one list per pull, an overview of the evening (what keeps killing us,
who is falling), and *Share in chat* for the group. Every dungeon and raid is
named, with the Adventure Guide's own tile beside it — click it and the guide
opens on that instance.

### External CD request and answer

Pick the externals you care about — a Pain Suppression, a Life Cocoon, a
battle res, a Bloodlust — and the request panel shows who in the group can
give you one and whether it is ready. One click asks that person, in a whisper
or in the group channel, with a text you set. On the other side, **External CD
answer** lights a button up the moment somebody asks for one of *your*
cooldowns; pressing it casts it on them.

### Reminders

A reminder is a sentence you write, shown while a buff is missing (or while it
is up), where you want it, in the size and colour you want. Which buffs, and
when they count, is up to you.

### Raid bar

Target markers, world markers, a ready check, a pull timer, pings — as one bar
of buttons you arrange, so the raid tools live in one place instead of six
menus.

### Invites

Whisper a keyword and you are in. Guild invites by rank, *invite everyone back*
after a wipe or a break, and *disband* — with the Battle.net whispers handled
the way the client allows.

### Modules, profiles and sharing

Every module has a switch on the *Modules* page and is off without a trace.
Settings live in **profiles**: name a set, point several characters at it, and
share it as a string that somebody else pastes in. Nothing they already have is
thrown away on import.

The **Cooldown Manager** module (cooldowns on bars you arrange yourself) is
temporarily disabled since 4.83.0 — we are not satisfied with the result yet.

## Usage

`/zs` opens the window. Everything is in it; the commands are shortcuts.

| Command | Effect |
| --- | --- |
| `/zs` | open the window |
| `/zs unlock` / `lock` | move the frames around the screen |
| `/zs modules` | the module switches |
| `/zs tanks` | the tank unitframes (`unlock` moves them, `test` fakes a raid) |
| `/zs taunt` | the taunt request (`ask` sends one) |
| `/zs death` | your death log (`raid` the group's, `share` to chat, `clear`) |
| `/zs externals` | the request panel (`test` fills it) |
| `/zs raidbar` | the raid bar |
| `/zs invite` | invites (`guild`, `back`, `disband`) |
| `/zs reminders` | every reminder, and why each one is or is not up |
| `/zs news` | what changed in this version |
| `/zs minimap` | show, hide, lock or unlock the minimap button |
| `/zs test` | run the addon's own checks and report failures |
| `/zs reset` | reset the profile you are using |

`/zs reset` touches **only the profile in use**, never the whole file.

## Verification

In the game, `/zs test` runs the addon's own checks — over two thousand of them,
on the model and the rules, and it puts every setting back afterwards. It says
nothing about how anything *looks*; that is still a pair of eyes on a screen.

The same checks run on the desk before every commit, under a harness that
stands in for the client and adds its own guards — layout, localisation,
frame contracts, memory. That harness is deliberately not in this repository.

## Standing on other people's shoulders

This addon was written by reading other addons — **EllesmereUI**, **ElvUI**,
**BigWigs**, **Method Raid Tools**, **Mythic Dungeon Tools**, **Details!**,
**WeakAuras**, **Plater**, **LibOpenRaid**, **Raider.IO** and a few more. Their
authors have our thanks.

**No code was copied from any of them.** What we took is a different thing:
*facts about the game's API.* Which field a table actually carries, which event
fires first, which call answers on a fresh login and which one returns nothing
until a frame later, which values the client withholds in a dungeon. None of
that is documented anywhere, and on a patch that keeps closing doors it is
often not discoverable at all except by reading code that already works.

So the comments in `Core/` cite those addons by name and by line, and they say
"read off working code" rather than pretending we knew. A number nobody can
re-check is a number that quietly goes wrong two patches later.

If you are one of those authors and you would rather not be named here, say so
and we will take the citation out.

## Developing

The repository is the addon: link or copy it into
`Interface\AddOns\ZwoelfStuff`, edit, `/reload` in game. After adding a **new
file** to the TOC, restart the client fully rather than relying on `/reload`.

`CHANGELOG.md` is written by hand and is what a player reads on the project
page and on every release; the versions before 4.70.0 are in
[CHANGELOG-ARCHIVE.md](CHANGELOG-ARCHIVE.md). A tag builds and uploads the
release — see `.github/workflows/release.yml` and `.pkgmeta`.

Static analysis via the Lua language server. **Do not write the version into
the path** — the extension updates itself, and a pinned path stops working
without saying why:

```powershell
$ls = (Get-ChildItem "$env:USERPROFILE\.vscode\extensions\sumneko.lua-*\server\bin\lua-language-server.exe" |
       Sort-Object FullName | Select-Object -Last 1).FullName
& $ls --check "$PSScriptRoot" --checklevel=Warning --logpath="$env:TEMP\llscheck"
```

## Embedded libraries

| Library | Licence | Why |
| --- | --- | --- |
| LibStub | Public domain | Loader the others need |
| CallbackHandler-1.0 | BSD | LibSharedMedia dependency |
| LibSharedMedia-3.0 | LGPL v2.1 | Fonts, bar textures, border textures |
| LibSerialize | MIT | Turns a profile into bytes for a share string |
| LibDeflate | zlib | Compresses those bytes and makes them printable |

The rest of this addon is built from scratch on purpose — the window, the
widgets, the look. These five are the exceptions, and none of them is there to
save effort.

**LibSharedMedia is a registry, not a design.** Every UI addon on a machine
registers what it ships into it, so asking it for the list shows you the media
you already have, under the names you already know. Shipping our own instead
would give you a second, smaller, unfamiliar set with the one you wanted
missing.

**LibSerialize and LibDeflate are the pair every addon that shares a string
uses** — WeakAuras, Plater, MDT and EllesmereUI all reach for exactly these
two. A hand-written serializer is a worse copy of a solved problem, and the one
place it would show is somebody else's string failing to open with no way to
tell whose fault it was.

> A note on LibDeflate's licence, because getting it wrong is easy: the
> `LICENSE.txt` sitting beside it in one of the addons on this machine is the
> **LGPL**, which is *not* its licence — `LibDeflate.lua` says **zlib** in its
> own header. Copying the file that happens to sit next to a library is how a
> project ends up claiming the wrong terms.

Their licences stay with them. Our own code is **All Rights Reserved** — see
[LICENSE](LICENSE).

## Credits

Addon Author: **Zwölf** — EU Destromath

License: **All Rights Reserved**, © 2026 Christian McCain. Play with it, back
it up, take it apart to see how it works. Republishing it, selling it or
distributing a changed copy needs written permission first. The libraries under
`Libs/` keep their own terms.

Releases up to and including 4.82.0 were published under the MIT License. That
grant stands for those versions; these terms begin at 4.83.0.
