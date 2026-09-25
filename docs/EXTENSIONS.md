# Extensions beyond the original specification

`docs/SPEC.md` describes milestones M0–M5. This document describes what was
added afterwards and how it changes the design. Where both disagree, this
document wins.

## 1. Loading from any disk

The music and font lists end with `FROM DISK...`. It reads the directory of
the current disk (`LOAD"$"` through the load channel into `FILE_BUF`) and
shows all PRG files in a scrolling list. The chosen file is read completely
into `FILE_BUF` (`$7000-$8FFF`, max. 8 KB) with `OPEN`/`CHRIN`, so the music
keeps playing while browsing and a rejected file leaves the old tune intact.

- **Tunes**: PSID files (as copied to the disk, header big-endian, load
  address 0 supported) or PRG files loading at `$1000` (init `$1000`, play
  `$1003`, subtune 0). The same rules as in `build_disk.py`: no RSID, no
  CIA speed bit, load address `$1000`, max. 4 KB, init/play inside the data.
  The tune name comes from the PSID header (else the file name).
- **Fonts**: PRG with load address + at least 512 bytes (`.64c`).
- **Big fonts**: the big font file format below.

All lists scroll (16 visible rows), so the catalog allows 15 fonts again.

## 2. Big title fonts

The title can use the scroll font (1x1, as before) or a **big font** of
W x H characters per glyph (W, H = 1–4), optionally **multicolour**.

- Tiles live in chars `$40-$FF` of the runtime charset at `$2000` (192
  tiles, e.g. 48 glyphs of 2x2). Chars `$00-$3F` stay the scroll font.
- `cfg_big_map` (64 bytes, one per screen code) holds the first tile of each
  glyph (row-major, W x H consecutive tiles), 0 = draw spaces.
- Built in: **ROM 2X2**, generated on the C64 from the ROM font with Scale2x
  (smooth diagonals).
- A title line holds 40 / W glyphs. Big titles are centred per line; 1x1
  titles stay exactly as typed when static.

Big font file (as produced by `build_disk.py`, PRG, load address `$7000`):

```
+0  "BF"   +2 W  +3 H  +4 flags (bit 0 multicolour)  +5 MC colour 1 ($D022)
+6  MC colour 2 ($D023)  +7 n tiles  +8 map[64]  +72 tiles n x 8 bytes
```

Manifest entry:

```toml
[[bigfont]]
name       = "MY BIG FONT"
file       = "big-mine"
src        = "assets/fonts/mine-2x2.64c"   # charset (.64c or .bin)
width      = 2
height     = 2
layout     = "linear"   # glyph g uses chars (g - first) * W * H ...; or "quad": g + 64 * k
first      = 0          # screen code of the first glyph in the charset (linear)
multicolor = false
mc1        = 11
mc2        = 12
license    = "..."
```

Glyphs are taken in the order A–Z, 0–9, `! ? . , - : ' ( ) / + "`, then the
rest, while the 192 tiles last; empty glyphs cost nothing.

## 3. Title movement

`TITLE STYLE` (menu key 6) selects the movement and its speed (1–4):

| Movement | Path |
|---|---|
| STATIC | fixed (1x1: as typed, big: centred) |
| SWING | left/right on a sine |
| SINE | up/down on a sine |
| EIGHT | horizontal figure eight (x: sine, y: double frequency) |
| BUMPER | bouncing ball: y bounces on the floor, x runs between the walls |

The title band is text rows 0–8 (raster 48–119). The fine position uses
XSCROLL/YSCROLL of the band (set in IRQ TOP), the coarse position redraws the
band rows from a pre-rendered title image (`TITLE_IMG`, RAM under the KERNAL).

### Raster details

- IRQ chain: TOP (`$10`) – MID (125) – BARS (128) – SCROLL (`$E8`) – BOTTOM
  (`$F8`).
- The scroller only shows text row 13 at raster 235 if exactly 10 text rows
  start before the FLD gap. With the band YSCROLL `y` row 9 starts at
  `120 + y`; a badline while the previous row is still in RC 7 repeats that
  row instead. IRQ MID at line 125 therefore sets YSCROLL 4 for `y` 0–5 and
  keeps `y` for 6–7 (see `irq_mid`).
- Per-frame work that is not raster-bound runs in the main loop after IRQ
  BOTTOM: redraw of the title (only when the coarse position changes) and the
  colour cycle. The bar buffers are filled right after the bar loop inside
  IRQ BARS with interrupts enabled (SCROLL/BOTTOM may interrupt it). The
  coarse redraw and the new fine values become active together
  (`title_apply`), so a late main loop delays the title by a frame instead of
  shaking it.

## 4. Memory map changes

| Area | Use |
|---|---|
| `$2200-$27FF` | big font tiles (chars `$40-$FF`) |
| `$2800-$28AF` | config block v2 (see below) |
| `$28B0-$28FF` | runtime work area (title layout, colour cycle row) |
| `$2900-$297F` | movement sine table (signed) |
| `$2980-$2BFF` | runtime code segment 2 |
| `$7000-$8FFF` | editor: file buffer (directory, files from disk) |
| `$9000-$99FF` | editor: directory table |
| `$9C00-$9FFF` | editor: Scale2x bit spreading tables |
| `$E000-$E3FF` | runtime: bar buffers, FLD table, sprite/bar sines, title image (RAM under the KERNAL, built at start, not saved) |

Config block v2 (additions, offsets from `$2800`): `+$60` W, `+$61` H,
`+$62` multicolour, `+$63/$64` MC colours, `+$65` movement, `+$66` movement
speed, `+$68` linked program length, `+$6A` its load address, `+$6C` its
start address, `+$70` big font map (64 bytes).

Catalog v2: header `n_sids, n_fonts, n_bigfonts, 0`, records from `+4`
(max. 15 tunes, 15 fonts, 12 big fonts).

## 5. Main menu

```
1 MUSIC  2 FONT  3 COLORS  4 EFFECTS  5 TITLE  6 TITLE STYLE
7 SCROLLTEXT  8 LINK PROGRAM  9 PREVIEW  0 SAVE
```
