# Notes for coding agents

C64 Intro Maker: a C64 (PAL) program in KickAssembler. Editor and runtime in
one PRG; saving writes `$0801`–end of text. The specification is
[docs/SPEC.md](docs/SPEC.md); deviations and open points go to
[docs/QUESTIONS.md](docs/QUESTIONS.md); features added after M5 are in
[docs/EXTENSIONS.md](docs/EXTENSIONS.md). User docs: [README.md](README.md).

## Rules

- Everything in the repo is **English**: code, comments, C64 UI texts (upper
  case), tool messages, docs, commit messages.
- All addresses live in `src/shared/memmap.asm`, all other constants in
  `src/shared/config.asm`. No magic numbers elsewhere.
- Guard every memory boundary and table layout with `.errorif`.
- Comment timing-critical code with cycles per instruction and the sum per
  raster line.
- Python tools: standard library only (`tools/`). The e2e tests may use
  `python-xlib` for key presses, nothing else.
- Never commit third-party SIDs or fonts. Test assets are generated at test
  time (see `tests/e2e/helpers.py`).
- YAGNI: build what the spec says; write open questions down instead of
  inventing features.

## Commands

```bash
make                 # build/intromaker.d64 (packed editor + catalog + tune)
make test            # unit tests (tools/)
make fixture         # runtime test image, FIXTURE_FLAGS=<0-31> for effect combos
make smoke           # build/fixture.png + build/editor.png (look at them)
make e2e             # full VICE end-to-end suite (~10 min); E2E=test_editor for one file
```

After a change: `make && make test && make smoke`, look at the screenshots,
run the affected e2e file.

## Headless only

`DISPLAY` may point to the user's real desktop. VICE must always run inside
`xvfb-run` (the Makefile does this). The e2e key presses use XTEST and would
type into whatever window has focus – they refuse to run outside
`make e2e` (`E2E_HEADLESS=1`). Never run the driver against the real display.

## KickAssembler gotchas

- `-o` is relative to the current directory, `-odir` sets where the `.sym`
  file goes (relative paths there are relative to the source). The Makefile
  passes absolute paths and copies `main.sym` to `editor.sym`/`fixture.sym`.
- Labels defined inside a `.macro` are local to it. Tables that code
  references are emitted directly, not from a macro.
- `.const` must be defined before it is used as an immediate; put such
  constants into `config.asm` and check derived table sizes with `.errorif`.
- `!:` / `!+` / `!-` multi-labels: count carefully when branches skip
  several of them.

## Timing facts (verified in x64sc)

- IRQ chain: TOP `$10` (title fine scroll, sprites) – MID 125 – BARS 128 –
  SCROLL `$E8` – BOTTOM `$F8`. Title redraw and colour cycle run in the main
  loop, the bar buffers after the bar loop inside BARS (with `cli`).
- BARS IRQ: double IRQ at lines 128/129, FLD + colour loop covers raster
  131–210, exactly 63 cycles per iteration. The whole block must stay inside
  one page (`.errorif` in `irq.asm`) – a page-crossing branch adds a cycle
  and the raster drifts.
- The colour writes land in the horizontal blank (`BARS_ALIGN` in
  `config.asm`); the restore after the loop happens before the badline of
  raster 211 stalls the CPU.
- Exactly 10 text rows must start before the FLD gap or the scroller leaves
  row 13; with a moving title (YSCROLL 0–7 in the band) `irq_mid` takes care
  of it (see the comment there and `docs/EXTENSIONS.md`).
- Main loop code must not use instructions longer than 6 cycles (entry
  jitter of the double IRQ); IRQs that nest into main-loop work save
  `rt_t0-rt_t3` (`IrqEnterT`).
- The "grey dot" artefact of colour register writes shows where writes
  happen – useful for timing work (see `.claude/skills/raster-timing`).
- Loops over more than 128 bytes must not use `ldx #n-1 … bpl`.

## Skills

Task guides in `.claude/skills/`:

- `vice-e2e-testing` – writing and running the VICE end-to-end tests
- `raster-timing` – checking and tuning the stable raster / FLD loop
- `add-asset` – adding a SID or font to the disk
