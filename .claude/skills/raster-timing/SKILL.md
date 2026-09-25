---
name: raster-timing
description: Check or tune the stable raster, FLD gap and raster bars of the C64 Intro Maker runtime (src/runtime/irq.asm, BARS_* in config.asm). Use when bars flicker, have ragged edges, sit on the wrong lines, when stripes appear in the FLD gap, or after changing IRQ code.
---

# Raster timing

## Facts

- BARS IRQ stage 1 at raster 128, stage 2 at 129 (NOP slide, then the
  `lda $d012 / cmp $d012 / beq` trick). The loop then runs raster 131–210,
  exactly 63 cycles per iteration (cycle comments in `irq.asm`).
- `fld_tab` writes YSCROLL `(L + 2) & 7` in line L: never a badline in the
  gap; the last entry restores `$1B`, so raster 211 is the badline of text
  row 10 and the scroller (row 13) appears at 235–242.
- `$3FFF` must be `$00` (idle byte shown in the gap).

## Checks

1. `make fixture FIXTURE_FLAGS=<n>` and a screenshot:
   `xvfb-run -a x64sc -default -pal -warp -sounddev dummy -limitcycles 20000000 -exitscreenshot out.png -autostartprgmode 1 -autostart build/fixture.prg`
   Screenshot y = raster − 16. With bars and without sine, uniform full-width
   rows must be exactly raster 136–150, 163–177, 191–205.
2. `make e2e E2E=test_runtime` checks all 32 flag combinations (every gap row
   either one colour or the default border/background pattern, border colour
   outside the gap) at different cycle counts, i.e. different frames.
3. Drift of one cycle per line shows as diagonal edges: look for a branch
   crossing a page (`bne` +1 cycle). The whole BARS block has an `.errorif`
   for this; keep it at the start of `RT_CODE`.

## Seeing where writes happen

x64sc emulates the VIC-II "grey dot": a write to `$D020/$D021` draws a light
grey pixel at the beam position. To make it visible, temporarily move the
writes into the visible area (e.g. `BARS_ALIGN = 1`): the dots form a vertical
line (stable) or a diagonal (loop is not 63 cycles). Measure the x position
across several `-limitcycles` values – it must not change (no jitter). Then
put `BARS_ALIGN` back so the writes land in the horizontal blank (no dots
visible anywhere, which `check_frame` in `tests/e2e/test_runtime.py`
verifies).

## Tuning knobs (`src/shared/config.asm`)

| Constant | Meaning |
|---|---|
| `BARS_DELAY` | stage-2 wait before the `$d012` compare (standard value 8) |
| `BARS_ALIGN` | `5n+1` cycles before the loop: moves all writes horizontally; 10 = writes in the h-blank and the post-loop restore before the badline at 211 |
| `BARS_NOPS` | extra 2-cycle steps before the loop |
| `BARS_PAD_LOOPS` | padding inside the loop (keep the sum at 63) |

## IRQ budgets

Measure where a handler ends with a monitor breakpoint on the labels
`irq_top_done` / `irq_bottom_done` and read `LIN` from `r`. TOP must end
before raster 128 (currently 76 with all effects).
