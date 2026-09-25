# C64 Intro Maker – Spezifikation & Bauanleitung (für Claude Code)

Ziel: ein C64-Programm (PAL), das **auf dem C64 selbst** läuft. Der Nutzer wählt Musik (SID), Font, Farben und Effekte, gibt Titel und Scrolltext ein, sieht eine Vorschau und speichert das Ergebnis als **eigenständig startbares PRG** auf Diskette.

Grundidee: Editor und Runtime stecken in einem PRG. Das fertige Intro liegt jederzeit komplett im RAM (`$0801`–Textende). „Speichern“ ist ein einziger KERNAL-`SAVE` dieses Bereichs. Es gibt keinen Linker und keine Relocation auf dem C64.

---

## 0. Arbeitsregeln für Claude Code

- Setze die Meilensteine aus Abschnitt 10 **der Reihe nach** um. Nach jedem Meilenstein: `make`, `make test`, `make smoke`, die Screenshots ansehen und mit `M<n>: <Kurzbeschreibung>` committen.
- Baue nur, was hier steht (YAGNI). Wenn etwas unklar ist, notiere es als offene Frage im Commit-Text oder in `docs/QUESTIONS.md`, statt Features zu erfinden.
- Alle Adressen und Konstanten stehen ausschließlich in `src/shared/memmap.asm` und `src/shared/config.asm`. Anderswo gibt es keine Magic Numbers.
- Sichere jede Speichergrenze mit `.errorif` in KickAssembler ab.
- Kommentiere zeitkritischen Code mit Zyklen pro Befehl und der Summe pro Rasterzeile.
- Python ≥ 3.11 mit **nur der Standardbibliothek** (`tomllib`, `struct`, `subprocess`, `unittest`).
- **Keine fremden SIDs oder Fonts committen.** Im Repo liegt nur die selbst geschriebene Testmelodie. Nutzer-Assets kommen mit Lizenzangabe ins Manifest.
- Nur PAL (312 Rasterzeilen, 63 Zyklen/Zeile). NTSC ist out of scope.
- UI-Texte auf Deutsch, in Großbuchstaben, ohne Umlaute (AE/OE/UE). Code-Kommentare kurz und auf Englisch.

---

## 1. Toolchain

| Tool | Zweck | Makefile-Variable |
|---|---|---|
| KickAssembler (Java) | Assembler | `KICKASS ?= kickass` (Wrapper oder `java -jar …/KickAss.jar`) |
| VICE `x64sc` | Emulator, Smoke-Tests | `X64 ?= x64sc` |
| VICE `c1541` | D64 erzeugen | `C1541 ?= c1541` |
| Python 3.11+ | Asset-/Katalog-/Disk-Build | `PYTHON ?= python3` |
| Exomizer | nur M5: Editor-PRG packen | `EXOMIZER ?= exomizer` |

Headless-Umgebung: `x64sc` über `xvfb-run -a` starten, falls kein Display vorhanden ist.

---

## 2. Repo-Struktur

```
Makefile
README.md
docs/SPEC.md                  # diese Datei
src/
  main.asm                    # Stub, Entry-JMP, Imports; -define FIXTURE für Testbuild
  shared/
    memmap.asm                # ALLE Adressen, Grenzen, .errorif
    config.asm                # Config-Block-Layout, Flags, Defaults
  runtime/
    runtime.asm               # runtime_start, Init, Restore, Exit
    irq.asm                   # IRQ-Kette, Double-IRQ (stabiler Raster)
    scroller.asm
    bars.asm                  # Rasterbars + FLD
    sprites.asm
    colorcycle.asm
    tables.asm                # per Assembler generierte Tabellen
  editor/
    editor.asm                # Start, Hauptmenü-Loop
    ui.asm                    # Print-Routinen (direkt in Screen-RAM)
    lists.asm                 # Auswahllisten (Musik, Font)
    textedit.asm              # Titel- und Scrolltext-Editor
    disk.asm                  # LOAD, SAVE, Laufwerksstatus
    fonts.asm                 # ROM-Font kopieren, fett
    irq.asm                   # Editor-IRQ (Musik + KERNAL-Tastatur)
assets/
  manifest.toml
  sids/                       # Nutzer-Assets (.sid / .prg), nicht committen außer Test
  fonts/                      # Nutzer-Assets (.64c / .bin)
  testtune/testtune.asm       # eigene Testmelodie
tools/
  build_disk.py
  test_build_disk.py
build/                        # gitignored
```

---

## 3. Programmfluss

1. `LOAD"*",8` + `RUN` → BASIC-Stub `SYS 2064` → `$0810: JMP editor_start`
2. Der Editor bereitet das Intro-Image im RAM vor: ROM-Font nach `$2000`, Default-Config, leerer Text, Katalog von Disk.
3. Vorschau: `rt_preview=1`, `JSR runtime_start`, Space → Rückkehr in den Editor.
4. Speichern: Operand von `$0810` auf `runtime_start` patchen, `$0801`…Textende+1 speichern, Operand zurückpatchen.
5. Gespeichertes Intro: `LOAD"NAME",8` + `RUN` → `SYS 2064` → `JMP runtime_start`. Space → Reset.

---

## 4. Speicherbelegung (Bank 0)

```
$0002-$001F  ZP Runtime
$0020-$003F  ZP Editor                (KERNAL-ZP $90-$FF unangetastet)
$0400-$07E7  Screen (Runtime + Editor)
$07F8-$07FF  Sprite-Pointer
$0801-$080F  BASIC-Stub "10 SYS2064" (BasicUpstart)
$0810-$0812  JMP <entry>              (Operand wird gepatcht)
$0813-$0FBF  Runtime Code + kleine Daten       .errorif * > $0FC0
$0FC0-$0FFF  Sprite-Daten (Ball, per .for generiert)
$1000-$1FFF  SID (max. 4 KB)          CPU-RAM; VIC sieht hier Char-ROM → egal
$2000-$27FF  Font (genutzt: $2000-$21FF = Zeichen $00-$3F)
$2800-$28FF  Config-Block
$2900-$2BFF  Runtime-Tabellen + Bar-Puffer (page-aligned)
$2C00-$3FFE  Scrolltext, Ende = $FF   → max. 5118 Zeichen
$3FFF        MUSS $00 sein (VIC-Idle-Byte im FLD-Bereich, siehe 6.5)
------------------------------ Save-Ende = Textende + 1
$4000-$5FFF  Editor Code + Daten      .errorif * > $6000
$6000-$67FF  Katalog (von Disk geladen)
$6800-$6FFF  Editor-Variablen/Puffer (Dateiname, Asset-Namen, Status)
```

VIC-Register:
- Runtime: `$D018 = $18` (Screen `$0400`, Charset `$2000`), `$D011 = $1B`, `$D016 = $C8`
- Editor: `$D018 = $14` (Screen `$0400`, ROM-Charset Großbuchstaben)

---

## 5. Config-Block (`$2800`, Teil des gespeicherten Intros)

| Offset | Größe | Inhalt | Default |
|---|---|---|---|
| +$00 | 2 | Magic `"IM"` | |
| +$02 | 1 | Version = 1 | |
| +$03 | 1 | Flags: bit0 MUSIC, bit1 BARS, bit2 BAR_SINE, bit3 SPRITES, bit4 TITLE_CYCLE | BARS+BAR_SINE+TITLE_CYCLE |
| +$04 | 1 | Rahmenfarbe | 0 |
| +$05 | 1 | Hintergrundfarbe | 0 |
| +$06 | 1 | Scrollerfarbe | 1 |
| +$07 | 1 | Titelfarbe (wenn kein Zyklus) | 7 |
| +$08 | 1 | Bar-Preset 0–7 | 0 |
| +$09 | 1 | Start-Scrollspeed 1/2/4 | 2 |
| +$0A | 2 | SID init | $1000 |
| +$0C | 2 | SID play | $1003 |
| +$0E | 1 | Subtune (0-basiert) | 0 |
| +$10 | 80 | Titel, 2×40 Screencodes | Leerzeichen |

Die Runtime liest **nur** diesen Block, den Font, den SID und den Text. Die Vorschau nutzt denselben Block. Was man sieht, wird also auch gespeichert.

---

## 6. Runtime

### 6.1 Init (`runtime_start`)
`SEI` → `$01=$35` → CIA-IRQs aus (`$DC0D/$DD0D = $7F`, beide lesen) → Raster-IRQ an (`$D01A=1`) → Vektoren `$FFFE` (IRQ) und `$FFFA` (NMI → `RTI`) → Screen löschen (`$0400-$07E7`), Titel nach Zeilen 1–2, Farben setzen → Sprites nach Flag → SID init (wenn MUSIC: `LDA subtune`, `JSR init` über gepatchten Operand) → `$D019` acken → `CLI`.

IRQ-Handler sichern A/X/Y selbst, weil kein KERNAL aktiv ist.

### 6.2 Screen-Layout und Rasterzeilen (YSCROLL = 3)

| Bereich | Screenzeile | Rasterzeilen |
|---|---|---|
| Titel | 1–2 | 59–74 |
| Sprite-Zone | 3–9 (leer) | 75–130 |
| FLD-Lücke mit Bars | – | 131–210 (80 Zeilen) |
| leer | 10–12 | 211–234 |
| **Scroller** | **13** (`$0608`, Farbe `$DA08`) | 235–242 |

Durch das FLD wird Screenzeile 10 erst bei Rasterzeile 211 dargestellt. Der Scroller steht deshalb in **Screenzeile 13**.

### 6.3 IRQ-Kette

| IRQ | Zeile | Aufgaben |
|---|---|---|
| TOP | $10 | `$D016=$C8`, `$D018=$18`, `$D011=$1B`; Sprite-Positionen; Titel-Farbzyklus; Bar-Puffer für diesen Frame berechnen |
| BARS | $80 | Double-IRQ → stabil; 80 Zeilen Loop (6.5); danach `$D011=$1B`, `$D020/$D021` = Config |
| SCROLL | $E8 | `$D016 = $C0 \| xscroll` (38-Spalten-Modus) |
| BOTTOM | $F8 | `$D016=$C8`; SID play (wenn MUSIC); Scroller-Logik; Space-Abfrage |

### 6.4 Scroller
- Pro Frame: `xscroll -= speed`. Bei Unterlauf `+8`, dann Zeile 13 um ein Zeichen nach links schieben und neues Zeichen in Spalte 39 schreiben.
- Textbytes: `$00–$3F` = Screencode. `$F1/$F2/$F4` = Speed 1/2/4. `$F8` = Pause 100 Frames. `$FF` = Ende → Textanfang. Steuercodes werden sofort ausgewertet und das nächste Byte geholt.
- Ist der Text leer (erstes Byte `$FF`), wird ein Leerzeichen ausgegeben (keine Endlosschleife).

### 6.5 Rasterbars in der FLD-Lücke
- **FLD läuft immer**, auch wenn BARS aus ist, damit das Layout identisch bleibt. Pro Zeile YSCROLL so setzen, dass in der nächsten Zeile keine Badline-Bedingung entsteht. In Zeile 210 wieder YSCROLL=3 setzen, dann wird 211 zur Badline für Screenzeile 10.
- Ohne Badlines und Sprites in diesem Bereich hat jede Zeile volle 63 Zyklen. Der Loop ist **exakt 63 Zyklen** pro Iteration: `lda border_buf,x / sta $d020 / lda bg_buf,x / sta $d021 / lda fld_tab,x / sta $d011` + Padding.
- `border_buf`, `bg_buf` und `fld_tab` (je 80 Byte) liegen so, dass **keine Pagegrenze gekreuzt wird** (sonst +1 Zyklus). Mit `.errorif` prüfen.
- Die Puffer werden in IRQ TOP gefüllt: Default Rahmen- und Hintergrundfarbe, darüber 3 Bars à 15 Zeilen aus dem gewählten Preset (Gradient setzt `$D020` und `$D021`, also volle Breite).
- Mit BAR_SINE: Position `bar_sin[(phase + i*43) & 127]` im Bereich 0–65, `phase += 1` pro Frame. Ohne: feste Positionen 5 / 32 / 60.
- 8 Presets à 15 Farben, symmetrische Verläufe. Beispiel Preset 0: `6,6,14,14,3,3,1,1,1,3,3,14,14,6,6`.
- **Im FLD-Bereich zeigt der VIC im Idle-State das Byte bei `$3FFF`.** Es muss `$00` sein, sonst erscheinen Streifen. Der Editor stellt das vor Vorschau und Save sicher.

### 6.6 Sprite-Sinus
- 8 Hires-Sprites, Ball 21×21 bei `$0FC0` (Pointer `$3F`), Farben aus einer 8er-Tabelle.
- X aus 128er-Tabellen `spr_xlo`/`spr_xhi` (Bereich 24–320, MSB → `$D010`). Y aus `spr_y` (Bereich **76–104**, damit Sprites vor Zeile 127 enden und nicht mit dem Double-IRQ bzw. den Bars kollidieren).
- Phasenversatz 16 pro Sprite, X-Phase +2 und Y-Phase +3 pro Frame.

### 6.7 Titel-Farbzyklus
16er-Farbtabelle, alle 2 Frames `phase+1`. Farb-RAM der Zeilen 1–2 = `cyc[(spalte + phase) & 15]`. Ohne Flag erhalten beide Zeilen die Titelfarbe.

### 6.8 Beenden
- IRQ BOTTOM prüft Space direkt über CIA1 (`$DC00=$7F`, `$DC01` bit 4 = 0) und setzt `exit_req`.
- Die Hauptschleife in `runtime_start` wartet auf `exit_req`:
  - `rt_preview = 0`: `$01=$37`, `JMP $FCE2` (Reset).
  - `rt_preview = 1`: warten bis Space losgelassen, dann **Restore** (`SEI`, `$D01A=0`, `$D019` acken, `$DC0D=$81`, `$D418=0`, `$D015=0`, `$D016=$C8`, `$D011=$1B`, `$01=$37`), Tastaturpuffer leeren (`$C6=0`), `RTS`.
- `rt_preview` ist ein Byte im Runtime-Segment. Vor jedem Save wird es auf 0 gesetzt.

---

## 7. Editor

### 7.1 Start
Laufwerk = `$BA` (bei < 8 → 8). ROM-Font nach `$2000` kopieren (`SEI`, `$01=$33`, 512 Bytes ab `$D000`, zurück auf `$37`). Config-Defaults schreiben, Text = `$FF`, `$3FFF=0`. Editor-IRQ installieren. Katalog `catalog` nach `$6000` laden; bei Fehler 0 Einträge und Hinweis `KATALOG FEHLT`.

### 7.2 Editor-IRQ
CIA1-IRQ aus, **Raster-IRQ** 1× pro Frame (50 Hz, damit die Musik im richtigen Tempo läuft), Vektor `$0314`. Der Handler ackt `$D019`, ruft `play` auf, wenn `music_on` gesetzt ist, und springt dann nach `$EA31` (KERNAL-Tastaturabfrage). Vor jedem LOAD in den SID-Bereich `music_on=0` und `$D418=0` setzen.

### 7.3 Ausgabe
Eigene Print-Routinen schreiben Screencodes direkt nach `$0400` und in den Farb-RAM. Kein `CHROUT`.

### 7.4 Hauptmenü (Tasten 1–8)
```
C64 INTRO MAKER
1 MUSIK:  <name>
2 FONT:   <name>
3 FARBEN
4 EFFEKTE
5 TITEL
6 SCROLLTEXT (<n>/5118)
7 VORSCHAU
8 SPEICHERN
```
Unten bleibt eine Statuszeile frei (Zeile 24) für Meldungen und Laufwerksstatus.

### 7.5 Listen (Musik, Font)
Max. 16 Einträge in den Zeilen 4–19, Markierung durch reverse Zeile. CRSR hoch/runter wählt, RETURN übernimmt, RUN/STOP geht zurück.
- Musik: Der erste Eintrag ist `KEINE MUSIK` (MUSIC-Flag aus), danach folgen die Katalog-SIDs. Bei Auswahl: Musik stoppen, laden, init/play/subtune in die Config übernehmen, MUSIC-Flag setzen, init aufrufen, Musik an.
- Font: `ROM` und `ROM FETT` (Byte `b | (b >> 1)`) sind eingebaut, danach folgen die Katalog-Fonts (512 Bytes nach `$2000`).

### 7.6 Farben
Tasten 1–4 schalten Rand, Hintergrund, Scroller und Titel jeweils +1 (mod 16). Neben jedem Label steht ein Farbblock (reverses Leerzeichen).

### 7.7 Effekte
1 Rasterbars an/aus · 2 Bar-Sinus an/aus · 3 Bar-Farben (Preset 1–8) · 4 Sprites an/aus · 5 Titel-Farbzyklus an/aus · 6 Scroll-Speed 1/2/4

### 7.8 Titel-Editor
Überschreibmodus, 80 Zeichen in 2 Zeilen, Cursor-Tasten, RUN/STOP zurück.

### 7.9 Scrolltext-Editor
- Einfügemodus, Anzeige in den Zeilen 3–20 (720 Zeichen). Das Fenster scrollt zeilenweise mit, damit der Cursor sichtbar bleibt.
- Eingabe über `GETIN` (`$FFE4`). Es werden nur PETSCII `$20–$5F` akzeptiert: `$20–$3F` bleibt gleich, `$40–$5F` wird zu `-$40` → Screencodes `$00–$3F`.
- F1/F3/F5 fügen Speed 1/2/4 ein (`$F1/$F2/$F4`), F7 fügt eine Pause ein (`$F8`). Anzeige als reverse `1`/`2`/`4`/`P`.
- CRSR ←/→/↑/↓ (±1 / ±40), DEL löscht links vom Cursor, HOME springt an den Anfang, RUN/STOP geht zurück.
- Beim Maximum (5118) werden Eingaben ignoriert und der Rahmen blitzt kurz.
- Die Statuszeile zeigt `ZEICHEN n/5118  F1 F3 F5 SPEED  F7 PAUSE  STOP ZURUECK`.

### 7.10 Vorschau
`$3FFF=0` sicherstellen, Text terminieren, `rt_preview=1`, `JSR runtime_start`. Danach Editor-IRQ neu installieren, `$D018=$14` setzen und das Menü neu zeichnen.

### 7.11 Speichern
1. Dateiname eingeben (1–16 Zeichen, PETSCII `$20–$5F`). RUN/STOP bricht ab.
2. `rt_preview=0`, `$3FFF=0`, Text terminieren. Operand bei `$0811/$0812` auf `runtime_start` setzen.
3. `SETNAM`, `SETLFS(1, dev, 0)`, Startzeiger `$FB/$FC = $0801`, `LDA #$FB`, X/Y = Textende+1, `JSR $FFD8`.
4. Operand wieder auf `editor_start` setzen.
5. Laufwerksstatus lesen (Kanal 15, bis `$0D`) und in Zeile 24 anzeigen (z. B. `00, OK`, `63, FILE EXISTS`, `72, DISK FULL`).
6. **Kein `@0:`-Overwrite** (1541-Replace-Bug). Existiert die Datei schon, wird einfach der Status gezeigt.

### 7.12 Laden
`SETNAM`, `SETLFS(1, dev, 1)`, `LDA #0`, `JSR $FFD5`. Ist Carry gesetzt, `LADEFEHLER` plus Laufwerksstatus anzeigen.

---

## 8. Assets, Manifest, Katalog

### 8.1 `assets/manifest.toml`
```toml
[[sid]]
name    = "TESTMELODIE"        # max. 20 Zeichen: A-Z 0-9 Leerzeichen . , ! ? - : / ( )
file    = "tune-test"          # Diskname: a-z 0-9 -, max. 16, KLEIN geschrieben
src     = "build/testtune.prg" # .sid (PSID) oder .prg
init    = 0x1000               # nur bei .prg Pflicht
play    = 0x1003
subtune = 0
author  = "Jochen"
license = "eigene Produktion"

[[font]]
name    = "BEISPIEL"
file    = "font-beispiel"
src     = "assets/fonts/beispiel.64c"   # .64c (2 Byte Ladeadr. + Daten) oder .bin
author  = "…"
license = "…"                           # Pflichtfeld, sonst Build-Abbruch
```

### 8.2 `tools/build_disk.py` (Validierung → Abbruch mit klarer Meldung)
- **SID (.sid)**: PSID-Header big-endian parsen (magic, dataOffset, load, init, play, songs, startSong, speed). Load = 0 bedeutet, dass die ersten 2 Datenbytes die Ladeadresse sind (little-endian). Init = 0 bedeutet init = load.
  - Abgelehnt werden: `RSID`, play = 0, Speed-Bit gesetzt (CIA-Timing), Daten außerhalb `$1000–$1FFF`, init oder play außerhalb der Daten.
  - Nicht auf `$1000` gelinkte Tunes werden mit dem Hinweis auf `sidreloc` abgelehnt. Das Tool selbst relocatet nicht.
  - Subtune-Default = startSong − 1.
- **SID (.prg)**: Ladeadresse aus den ersten 2 Bytes, init/play aus dem Manifest, gleiche Bereichsprüfung.
- **Font**: Ladeadresse von `.64c` entfernen, die ersten 512 Bytes verwenden (weniger ist ein Fehler), als PRG mit Ladeadresse `$2000` ausgeben.
- Max. 15 SIDs und 15 Fonts.
- **Namen**: in Großbuchstaben → Screencodes (`A–Z` → 1–26, `$20–$3F` bleibt gleich, `@` → 0), mit Leerzeichen auf 20 aufgefüllt.
- **Dateinamen**: Im Katalog stehen die Bytes von `file.upper()` (PETSCII `$41–$5A`). An `c1541` wird der Name **klein** übergeben, dann schreibt c1541 genau diese Bytes. Wer das verwechselt, bekommt geshiftete Zeichen und LOAD findet nichts.
- **Katalog** `build/catalog.prg`, Ladeadresse `$6000`:
  ```
  +0  n_sids   +1  n_fonts
  +2  n_sids × 48 Byte, dann n_fonts × 48 Byte
  Record: +0 name[20] Screencodes | +20 fnlen | +21 filename[16] PETSCII
          +37 init lo/hi | +39 play lo/hi | +41 subtune | +42..47 = 0
  ```
- **Disk** über `subprocess` mit `c1541`: `-format "intro maker,im" d64 build/intromaker.d64`, dann als erste Datei `intro maker` (Editor), danach `catalog` und die Assets.
- Zusätzlich wird `build/CREDITS.txt` (Name, Autor, Lizenz) erzeugt.
- **Unit-Tests** (`tools/test_build_disk.py`, erzeugen Testdaten selbst): PSID-Parsing inkl. load = 0, Ablehnungsfälle, Screencode-Konvertierung, Katalog-Bytelayout, Dateinamen-Casing.

### 8.3 Testmelodie
`assets/testtune/testtune.asm`, Ladeadresse `$1000`, init `$1000`, play `$1003`. Eine kurze Arpeggio-Schleife auf Stimme 1. Eigene Arbeit, darf ins Repo.

---

## 9. Build & Tests

| Target | Wirkung |
|---|---|
| `make` / `make disk` | testtune → editor.prg → `build_disk.py` → `build/intromaker.d64` |
| `make fixture` | `kickass src/main.asm -define FIXTURE` → `build/fixture.prg`: Entry `jsr font_copy_rom; jmp runtime_start`, Test-Config (alle Effekte an, Musik an), Testtitel, Testtext mit allen Steuercodes, Testmelodie per `.import binary` bei `$1000` |
| `make run` / `make run-fixture` | `x64sc -autostart …` |
| `make test` | `python3 -m unittest discover tools` |
| `make smoke` | Screenshots von Fixture und Editor (siehe unten) |
| `make clean` | `build/` löschen |

Smoke-Test (Exitcode von VICE ignorieren, `-limitcycles` beendet mit Fehlercode):
```
x64sc -default -pal -warp -sounddev dummy -limitcycles 20000000 \
      -exitscreenshot build/fixture.png -autostartprgmode 1 -autostart build/fixture.prg
x64sc -default -pal -warp -sounddev dummy -limitcycles 40000000 \
      -exitscreenshot build/editor.png -autostart build/intromaker.d64
```
Claude Code prüft die PNGs visuell. Tastatur-Automation per `-keybuf` ist optional. Wenn sie nicht zuverlässig greift, genügt der manuelle Test.

---

## 10. Meilensteine & Abnahme

**M0 – Gerüst**
Makefile, `memmap.asm`, `config.asm` mit allen `.errorif`, Testmelodie, `build_disk.py` + Tests, D64 wird gebaut.
Abnahme: `make test` grün, `make disk` erzeugt eine D64 mit `intro maker` (vorerst Platzhalter), `catalog` und `tune-test`.

**M1 – Runtime-Basis (Fixture)**
IRQ-Kette, Screen-Layout, Titel statisch, Scroller mit allen Steuercodes, Musik.
Abnahme: Screenshot zeigt Titel und Scroller in Zeile 13, die Testmelodie läuft im richtigen Tempo, Pause und Speedwechsel sichtbar, Space → Reset.

**M2 – Effekte**
Stabiler Raster, FLD + Bars mit Presets und Sinus, Sprite-Sinus, Titel-Farbzyklus.
Abnahme: Bars ohne Flackern und mit geraden Kanten in x64sc, der Scroller bleibt in Zeile 13 ruhig, keine Streifen in der FLD-Lücke. Jede Flag-Kombination in der Fixture-Config getestet. Zyklenbudget je IRQ als Kommentar dokumentiert.

**M3 – Editor ohne Disk**
Editor-IRQ, Hauptmenü, Farben, Effekte, Titel- und Scrolltext-Editor, Fonts ROM/ROM FETT, Vorschau hin und zurück (beliebig oft).
Abnahme: Eingaben erscheinen in der Vorschau, nach 10× Vorschau/Zurück hängt nichts und die Tastatur funktioniert.

**M4 – Disk**
Katalog laden, Musik- und Font-Liste mit Laden, Musik im Menü, Speichern mit Laufwerksstatus.
Abnahme: Ein gespeichertes Intro startet in einem frischen VICE per `LOAD"NAME",8` / `RUN` und ist identisch zur Vorschau. Doppelter Dateiname zeigt `63, FILE EXISTS`.

**M5 – Feinschliff**
Editor-PRG mit `exomizer sfx sys` packen, README (Bedienung, Asset-Manifest, Lizenzhinweis: HVSC ist ein Archiv und keine Freigabe).
Abnahme: Das gepackte Editor-PRG startet von der D64 und verhält sich wie in M4.

---

## 11. Bekannte Fallstricke (Checkliste)

- `$3FFF ≠ 0` → Streifen in der FLD-Lücke.
- Pagegrenze in den Tabellen des Bar-Loops → +1 Zyklus, der Raster läuft weg.
- Sprites unterhalb von Zeile 126 → DMA stiehlt Zyklen im Double-IRQ bzw. Bar-Loop.
- SID laden, während `play` im IRQ läuft → Absturz. Vorher `music_on=0` setzen.
- CIA-IRQ im Editor aktiv → Musik läuft mit 60 Hz statt 50 Hz.
- Taste Space aus der Vorschau landet im Tastaturpuffer → `$C6=0` nach der Rückkehr.
- Operand bei `$0810` nicht zurückgepatcht → der Editor startet nach dem Speichern die Runtime.
- Dateinamen-Casing zwischen Katalog und c1541 (siehe 8.2).
- `-limitcycles` beendet VICE mit Fehlercode → im Makefile ignorieren.
