# Handoff: ZwoelfStuff — Optionsfenster, Token-Satz, Logo

## Overview

Neuentwurf des Optionsfensters von **ZwoelfStuff** (WoW-Addon, Lua, Repo `heidrich/zwoelfstuff`),
plus ein Token-Satz und ein neues Logo. Ausgangsproblem in den Worten des Auftraggebers:
„unübersichtlich, sieht altbacken aus".

Drei Eingriffe tragen das Ergebnis:

1. **Farbe wird sparsam verteilt.** Orange erscheint höchstens einmal pro Spalte —
   aktiver Nav-Eintrag, gewählte Bar, primäre Aktion. Alles andere ist neutral.
2. **Keine Slider mehr.** Jeder Zahlenwert ist ein Stepper (22 + 52 + 22 px).
   Das entspricht ohnehin der Regel aus eurer README („Steppers instead of sliders").
3. **Die dritte Spalte ist nie leer.** Bei den Bars der Inspector, auf Settings die
   Erklärung zur markierten Zeile. Damit entfällt die Hilfezeile unter jedem Regler.

## About the Design Files

Die Datei `ZwoelfStuff UI.dc.html` in diesem Bundle ist eine **Design-Referenz in HTML** —
ein Prototyp, der Aussehen und Verhalten zeigt. Sie ist **kein Code zum Übernehmen**.

Die Aufgabe ist, diese Entwürfe im bestehenden Lua-Frame-System des Addons nachzubauen:
`Core/Widgets.lua` (Design-System), `Core/Options.lua` (Fensterschale),
`Core/OptionsBars.lua` (mittlere und rechte Spalte). Jede Angabe unten ist in Pixeln
und Ankerbeziehungen formuliert, weil es in WoW kein Layout gibt.

Die Datei im Browser öffnen: `ZwoelfStuff UI.dc.html` (braucht `support.js` daneben).

## Fidelity

**High-fidelity.** Endgültige Farben, Typografie, Abstände und Maße. Pixelgenau nachbauen.
Der einzige Platzhalter ist Spell-Art (farbige Kacheln statt echter Icons) und der
Spielhintergrund in der Edit-Mode-Ansicht.

---

## Design Tokens

Ersetzt den Block `local C = { ... }` in `Core/Widgets.lua`. Die Akzente bleiben unverändert;
die Neutralen gehen tiefer, und **sidebarBg wird dunkler als windowBg** statt heller —
dadurch liegt der Inhalt oben statt in einer Mulde.

```lua
local C = {
    canvasBg   = { 0.039, 0.043, 0.051 },  -- #0A0B0D  hinter dem Fenster
    windowBg   = { 0.071, 0.078, 0.094 },  -- #121418  Fenster, mittlere Spalte
    sidebarBg  = { 0.055, 0.063, 0.075 },  -- #0E1013  Rail UND Inspector
    well       = { 0.043, 0.051, 0.063 },  -- #0B0D10  Vorschaufläche, Eingabe, Overlay
    surface    = { 0.098, 0.110, 0.129 },  -- #191C21  Karte, aktive Nav-Zeile
    control    = { 0.129, 0.145, 0.169 },  -- #21252B  Stepper, Select, Chip
    controlHi  = { 0.200, 0.224, 0.255 },  -- #333941  Control unter dem Cursor
    separator  = { 0.122, 0.137, 0.165 },  -- #1F232A  Hairline (opak, nicht Weiss mit Alpha)
    edge       = { 0.165, 0.184, 0.216 },  -- #2A2F37  Kartenumriss, Fensterkante

    accent     = { 1.000, 0.478, 0.239 },  -- #FF7A3D
    accentSoft = { 0.180, 0.118, 0.082 },  -- #2E1E15  Toggle-Track an, Badge-Grund
    accentCool = { 0.494, 0.776, 0.831 },  -- #7EC6D4  Verweise, Kategorie-Badges
    inUse      = { 0.404, 0.788, 0.443 },  -- #67C971  NUR "liegt schon auf der Leiste"
    inUseSoft  = { 0.086, 0.149, 0.106 },  -- #16261B
    danger     = { 0.898, 0.353, 0.318 },  -- #E5645A  NUR zerstörende Aktionen
    warning    = { 0.890, 0.702, 0.255 },  -- #E3B341  Log-Level WARN

    text       = { 0.937, 0.945, 0.957 },  -- #EFF1F4  Titel, Werte, aktive Zeile
    textBody   = { 0.788, 0.812, 0.847 },  -- #C9CFD8  Zeilen-Labels im Inspector
    textDim    = { 0.608, 0.639, 0.686 },  -- #9BA3AF  sekundär, inaktive Nav
    textFaint  = { 0.384, 0.416, 0.463 },  -- #626A76  Meta, Sublines
    textGhost  = { 0.306, 0.337, 0.380 },  -- #4E5661  Eyebrows, deaktiviert
}
```

### Farbregeln

| Regel | Warum |
| --- | --- |
| `accent` höchstens **einmal pro Spalte** sichtbar | Drei Orangetöne nebeneinander heben sich gegenseitig auf |
| `inUse` ausschliesslich für "schon auf der Leiste" | Grün als Dekoration zerstört die Zustandsbedeutung |
| `danger` nur auf Löschen/Zurücksetzen | Sonst wird Rot zu Dekoration |
| Hairlines sind **opake** Farben, eine Stufe neben dem Grund | Weiss mit 6 % Alpha über einer 3D-Szene ist nicht stabil |

### Maße

```lua
UI.WINDOW_W    = 1360
UI.WINDOW_H    = 760
UI.RAIL_W      = 168
UI.CONTENT_W   = 792   -- 1360 - 168 - 400
UI.INSPECTOR_W = 400

UI.HEADER_H    = 62    -- unverändert
UI.ROW_H       = 28    -- unverändert
UI.SECTION_H   = 32
UI.CARD_HEAD_H = 40
UI.NAV_ITEM_H  = 30
UI.CONTROL_H   = 24    -- Select, Button
UI.STEPPER_H   = 22

UI.PAD    = 16   -- war 14; jetzt auf der Vierer-Reihe
UI.GAP    = 8
UI.RADIUS = 0
```

Abstandsreihe: **4 · 8 · 12 · 16 · 20 · 24**. Nur diese sechs Werte für Layout-Lücken und
Container-Innenabstände. Innenabstände *von Bedienelementen* gehören zum Element selbst
und zählen nicht zur Reihe: Button 12, Chip/Badge 6–8, Stepper 0.

### Schrift — sieben Größen werden fünf

| Rolle | px | Gewicht | Einsatz |
| --- | --- | --- | --- |
| title | 20 | 600 | Seitentitel im Kopfband |
| card | 15 | 600 | Bar-Name, Inspector-Titel |
| row | 13 | 400 | Zeilen-Labels, Nav, Listen |
| meta | 12 | 400 | Sublines, Hinweise |
| eyebrow | 10 | 600 | Sektionsköpfe, Badges — IMMER Versalien, Sperrung .14em |

Panel-Schrift bleibt eine schmale Grotesk (**Expressway** ist richtig), Zahlen in Feldern
dieselbe Familie mit Tabellenziffern. Zahlen **auf Icons** weiterhin über den Zahlen-Helfer
mit `OUTLINE` — die beiden sind nicht austauschbar. 10 px ist die Untergrenze.

---

## Screens

Alle Screens liegen als Karten im Board `ZwoelfStuff UI.dc.html`, jeweils mit ihrer ID.

### 1a — Cooldowns, Hauptansicht (Referenz-Screen)

Drei Spalten, Kopfband 62 in jeder Spalte, Trennlinie überall auf derselben Höhe.

**Rail (168)** — Grund `sidebarBg`, rechte Kante 1 px `separator`.
- Kopf 62: Logo 26 × 26, dann Wortmarke 15/600 (`text`) und darunter `EU DESTROMATH` 10 Mono `textGhost`. Innenabstand 16.
- Nav ab y = −62 − 16, drei Gruppen mit Eyebrow (`BARS` / `SYSTEM` / `INFO`), Abstand zwischen Gruppen 18.
- Nav-Zeile 30 hoch, Innenabstand links 8, Icon 14, Lücke 10, Label 13.
  Aktiv: Grund `surface`, Label `text`, plus 2 px `accent` an der linken Kante der Zeile.
  Inaktiv: kein Grund, Label `textDim`.
- Fuss 38, Oberkante 1 px `separator`, links Version, rechts Client-Version, beide 10.5 Mono `textGhost`.

**Content (792)** — Grund `windowBg`, Innenabstand 20.
- Kopf 62: links Titel 20/600 + Subline 12 `textFaint` (Abstand 6). Rechts zwei Ghost-Buttons 26 hoch (`Move bars`, `Build`), Grund `surface`, 1 px `edge`, Lücke 6.
- Bar-Karten 752 breit, Abstand 14, Grund `surface`, 1 px `separator`.
  Gewählte Karte: 1 px `edge` **und** 3 px `accent` als Balken an der linken Kante.
- Kartenkopf 40, Innenabstand links 12 / rechts 8, Elemente mit Lücke 11:
  Griff (6 Punkte) · Index-Chip 20 × 20 (`control`, Mono 11; gewählt: `accent`-Grund, `windowBg`-Ziffer) ·
  Name 15/600 · Kind-Badge (Mono 10 Versalien, `accentCool` auf `#152227`) · Dehnfuge ·
  **`Icon options` / `Bar options`** · `Build on screen` (`accentCool`) · `Options` · Überlauf-Menü 24 × 24.
- Kartenkörper: Innenabstand 16, links die Vorschau (Rest der Breite, 112 hoch, Grund `well`, 1 px `separator`,
  Innenabstand 14), rechts eine 212 breite Spalte mit drei 28er Zeilen: Rows, Columns, Arrangement.
- Unter den Karten eine 40 hohe Zeile mit 1 px `separator` und zwei Ghost-Aktionen (`Icon bar`, `Tracking bar`),
  getrennt durch einen 1 px Steg 14 hoch.

**Inspector (400)** — Grund `sidebarBg`, linke Kante 1 px `separator`.
- Kopf 62: links Bar-Name 15/600 + Subline 11 `textGhost`; rechts `Done` (26 hoch, `accent`-Grund,
  `windowBg`-Text) und ein 24 × 24 Schliessen-Icon.
- Tab-Leiste 34: drei gleich breite Tabs (`Look` · `Behaviour` · `Reuse`), Unterkante 1 px `separator`,
  aktiver Tab mit 2 px `accent` bündig auf dieser Linie.
- Körper: Innenabstand seitlich 16, damit 368 nutzbare Breite.
  Sektionskopf 32: Eyebrow, dann Lücke 10, dann eine 1 px Hairline bis zur rechten Kante.
  Zeile 28, Unterkante 1 px `separator` (letzte Zeile einer Sektion ohne Linie).

### 1b — Inspector ohne Tabs (Alternative)
Alle Sektionen offen, oben eine 34 hohe Sprungleiste mit Chips (Mono 9.5 Versalien).
Gleiche Zeilen wie 1a. **Noch nicht entschieden** — 1a oder 1b, Aufwand ist identisch.

### 1c — Spell-Picker (rechte Spalte im Listen-Modus)
Suche 28 hoch, darunter Filter-Chips 22, dann Gruppen (`COOLDOWNS` / `UTILITY` / …).
Zeile 32: Icon 22, Name 13, rechts Cooldown-Dauer 11 Mono.
Bereits platzierte Spells: Name in `inUse`, rechts ein Chip `CELL n` (`inUse` auf `inUseSoft`).
Nicht im Talentbuild: Alpha 0.42, Label `NOT IN BUILD`, ans Gruppenende sortiert, weiter wählbar.
Fuss 52: `Spell ID`-Eingabe plus `Add`.

### 1d — Leerer Zustand
Mittlere Spalte, Block 440 breit, vertikal zentriert. Eyebrow → Satz 22/600 → Absatz 13.5 →
zwei Buttons 30 hoch → Hairline → drei Presets als 40er Zeilen mit Miniatur-Raster links.

### 1e — Settings
Zeilen wie im Inspector, aber über die volle Content-Breite. Die markierte Zeile bekommt
`surface` als Grund über die volle Breite (negativer Innenabstand von 10 auf beiden Seiten).
**Die dritte Spalte zeigt die Erklärung zur markierten Zeile** — Titel, zwei Absätze,
Hairline, ein Slash-Befehl in einem `well`-Kasten.

### 1f — Diagnostics
Vier Kennzahlen-Karten 72 hoch nebeneinander (Lücke 12), darunter ein Balkendiagramm 64 hoch
(8 px Balken, Lücke 2, Ausreisser in `accent`), darunter das Log als 30er Zeilen:
Zeitstempel 56 breit Mono 11 · Level-Chip 44 breit · Meldung.
Rechte Spalte: Detail zur gewählten Zeile plus betroffene Dateien.

### 1g — About + Changelog
Content: About-Block (Logo 64, Name 18/600, Absatz, drei Metafelder), Hairline,
dann Releases als 34er Zeilen (Version 56 Mono · Datum 76 Mono · Zusammenfassung · Badge).
Rechte Spalte: Notizen der gewählten Version, gruppiert nach `REMOVED` / `CHANGED` / `FIXED`,
jeder Punkt mit 2 px Farbstrich links (`danger` / `accentCool` / `inUse`).

### 1h — Edit Mode / On-Screen-Overlay
Alles opak auf `well` mit 1 px `edge`. Snap-Linien 1 px `accentCool` bei 55 % Alpha,
Beschriftung 10 Mono. Bar-Panel 22 hoch über der Bar. Gewählte Zelle: 1 px `accent` plus
6 × 6 Anfasser unten rechts. Spell-Palette 280 breit rechts. Werkzeugleiste unten mittig,
44 hoch, aktiver Modus mit `accentSoft`-Grund und `accent`-Text.

### 3a — Textur-Dropdown (gewählt)
Overlay 368 breit, direkt unter der Select-Zeile, Grund `well`, 1 px `#3C424B`
(eine Stufe heller als `edge`, damit es über der Seite liegt — es gibt keine Schatten).
- Kopf 38: Suche, rechts `ESC`.
- Liste 404 hoch, scrollend. Zeile 28: Name 13 links, Vorschaustreifen **132 × 14** rechts.
- Gruppen: `SHIPPED WITH ZWOELFSTUFF` zuerst, danach `FROM YOUR OTHER ADDONS`.
  Bewusst **nicht** alphabetisch — bei 46 Einträgen ist das der Unterschied zwischen Finden und Suchen.
- Gewählter Eintrag: Grund `surface`, 2 px `accent` links, Name in `accent`, Häkchen rechts.
- Scrollbalken 6 breit, Griff 4 breit `#3C424B`.
- Auslauf unten 16 hoch: eine Textur mit `SetGradient` auf Alpha (kein Blur).
- Fuss 32: `Scroll or type to filter`, rechts `↑↓ ENTER`.

Die Vorschaustreifen sind in der **Füllfarbe der Bar** eingefärbt, nicht in Orange —
man wählt eine Textur, um zu sehen, wie diese Bar aussehen wird.
Dasselbe Muster gilt für Schrift- und Rahmen-Auswahl (dieselben LibSharedMedia-Listen).

---

## Komponenten

### Stepper (ersetzt jeden Slider)
```
[ − ] [  wert  ] [ + ]
 22      36|52    22      alles 22 hoch, Lücke 1
```
- Tasten: Grund `control`, Glyph 13. Am Anschlag: Glyph `textGhost` und nicht klickbar.
- Wertfeld: Grund `well`, Mono 12 `text`, zentriert. 36 breit in der Kartenspalte, 52 im Inspector.
- Gesamtbreite Inspector: 22 + 52 + 22 = **96**, rechtsbündig in der 368er Zeile.
  Das Label bekommt damit 368 − 96 − 8 = **264** und läuft nie hinaus.

### Select
24 hoch, Grund `control`, 1 px `edge`, Innenabstand 8, Text 12.5 `text`, Chevron 9 `textFaint` rechts.
Breite 168 im Inspector, 124 in der Kartenspalte, 240 auf Settings.
Offen: 1 px `accent` als Rahmen, Chevron gedreht, Overlay siehe 3a.

### Toggle
32 × 18, quadratisch. Aus: Track `control`, Knopf 14 × 14 `textGhost` links.
An: Track `accentSoft`, Knopf 14 × 14 `accent` rechts. Kein Radius, keine Animation nötig.

### Badge
Mono 10 Versalien, Sperrung .1em, Innenabstand 4 / 6.
Kategorie: `accentCool` auf `#152227`. Zustand: `inUse` auf `inUseSoft`. Aktuell: `accent` auf `accentSoft`.

### Button
26 hoch (30 im Leerzustand), Innenabstand 12–14.
Primär: Grund `accent`, Text `windowBg`, 600. Normal: Grund `surface`, 1 px `edge`, Text `text`.
Ghost: kein Grund, Text `textDim`. Verweis: kein Grund, Text `accentCool`.

---

## Nine-Slice

Jeder Streifen **256 × 32**, acht Kacheln à 32 × 32, Kachelreihenfolge wie im Referenz-Addon.
Nichts davon ist Pflicht — der ganze Entwurf läuft auf der Ein-Pixel-Linie, die ihr schon habt.

| Name | edgeSize | Inhalt |
| --- | --- | --- |
| `zs-hairline` | 1 | bereits vorhanden, bleibt Default |
| `zs-plate` | 8 | 1 px `edge` aussen, 2 px Abdunklung innen |
| `zs-soft` | 12 | wie plate, zusätzlich 3 px Eckenradius |
| `zs-shadow` | 16 | Schwarz .55 → 0 über 12 px, für Overlays |
| `zs-accent-edge` | 8 | 1 px `accent`, nur für die gewählte Bar |

---

## Anker — die drei Fallen aus eurer eigenen Liste

1. **Kein FontString bekommt TOPLEFT und RIGHT zugleich.** Jede Textzeile hier hat eine feste
   Breite: Rail 136, Content 752, Inspector 368.
2. **Die Trennlinie unter dem Kopfband** liegt in jeder Spalte auf y = −62 vom Fensteroberrand
   und wird auf einem eigenen Frame **über** den Spalten gezeichnet, nicht auf dem Fenster.
3. **Kein Bedienelement ist breiter als sein Slot.** Stepper 96, Select 168, Toggle 32 —
   alle rechtsbündig in 368, Label bekommt den Rest.

---

## Assets

`Media/logo-512.png` · `logo-256.png` · `logo-128.png` · `logo-64.png` · `logo-32.png` · `logo-24.png` · `logo-16.png`

Transparente Ecken, Kreis füllt die Fläche. Aufbau, relativ zur Kantenlänge S:

| Ebene | Geometrie | Farbe |
| --- | --- | --- |
| rim | Kreis r = 0.5 S | `#FF7A3D` |
| plate | Kreis r = 0.4375 S | `#0B0D10` |
| track | Kreisring r = 0.3125 S, Strich 3/64 S — **nur ab S = 32** | `#243038` |
| sweep | Tortenstück r = 0.3125 S, 150° ab zwölf Uhr im Uhrzeigersinn | `#FF7A3D` |
| hub | Kreis r = 0.0859 S | `#0B0D10` |

Unter 32 px entfällt `track` — drei Flächen bleiben, das trägt bis 16 px. Die mitgelieferten PNGs folgen dieser einen Schwelle: 512, 256, 128, 64 und 32 mit Ring, 24 und 16 ohne. Der Fensterkopf zeichnet bei 26, also ohne.

**Minimap-Button:** keine Änderung nötig. Die drei Ebenen in `Core/Minimap.lua`
(Rim, Platte, Icon, alle mit `TempPortraitAlphaMask`) sind genau dieser Aufbau.
Es reicht, `ns.ICON_TEXTURE` auf die neue Datei zu zeigen.

**Wortmarke:** `zwoelfstuff`, klein geschrieben, `zwoelf` in `text` mit Gewicht 600,
`stuff` in `textFaint` mit Gewicht 400. Primäres Lockup: Zeichen oben, Wortmarke darunter.

### Icons

`icons/` enthält 71 Dateien — jedes Zeichen aus Fenster, Nav, Kartenköpfen, Kontextmenüs
und Options-Listen: Anordnung (`layout-*`), Leserichtung (`flow-*`, `dir-*`), Zellenart (`kind-*`),
Zellen-Aktionen (`cell-*`), Sichtbarkeitsregeln (`cond-*`, `place-*`), Effekte (`effect-*`),
Presets (`preset-*`), Medien (`media-*`) und Overlay-Menü (`menu-*`). Format: Strichstärke **1.4**
auf **14 × 14**, runde Enden, `currentColor`, nie gefüllt. Ausnahmen sind `action-grip` und
`action-overflow` — Punkte, also gefüllt.

Größen im Fenster: **14** in kleinen Buttons und Nav-Zeilen, **16** neben Fliesstext,
**22** im Kopfband. Farbe: `textDim` in Ruhe, `text` unter dem Cursor, `accent` wenn aktiv.

WoW rendert kein SVG. Für den Client müssen die Zeichen als PNG vorliegen — bei den
Zielgrößen 14, 16 und 22 gerendert, nicht skaliert, sonst verwischen die Striche.
Sag Bescheid, dann liefere ich die PNG-Sätze mit.

`logo.svg` ist die Vektorquelle der Scheibe, `logo-small.svg` ohne Ring (unter 32 px),
`logo-inverse.svg` für helle Flächen.

**Spell-Art** im Prototyp sind farbige Platzhalter-Kacheln. Im Addon kommen dort die
adoptierten Cooldown-Manager-Frames hin.

---

## Files

| Datei | Was |
| --- | --- |
| `ZwoelfStuff UI.dc.html` | Alle Screens als Board. IDs 1a–1k, 3a/3b. Im Browser öffnen. |
| `support.js` | Laufzeit für die HTML-Datei. Muss danebenliegen. |
| `Media/logo-*.png` | Logo in sieben Größen, für den Client |
| `icons/*.svg` | Alle UI-Icons als Einzeldateien, plus Logo in drei Varianten |
| `icons/preview.html` | Kontaktbogen aller Icons |

## Offene Entscheidungen

1. Inspector mit Tabs (`1a`) oder alles offen mit Sprungleiste (`1b`).
2. Ob die Nine-Slice-Streifen überhaupt gebaut werden — der Entwurf braucht sie nicht.
3. Ob die Aura-Display-Seite denselben Aufbau bekommt (noch nicht entworfen).
