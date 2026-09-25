---
name: vice-e2e-testing
description: Run, debug or extend the VICE end-to-end tests of the C64 Intro Maker (tests/e2e) - real key presses via XTEST in a private Xvfb, memory checks via the VICE remote monitor. Use when verifying editor/runtime behaviour in the emulator or adding a test.
---

# VICE end-to-end tests

## Run

```bash
make e2e                      # all files (~10 min)
make e2e E2E=test_editor      # one file: test_runtime, test_editor, test_disk
```

`make e2e` builds disk + fixture, starts a private Xvfb (`xvfb-run -a`) and
sets `E2E_HEADLESS=1`. Without that variable the interactive tests skip.
**Never** run the driver on the user's display: XTEST types into the focused
window. Artefacts (screenshots, wav) go to `build/e2e/`.

Requirements: VICE with ROMs, `python-xlib` (`python3-xlib`).

## Driver (`tests/e2e/vice.py`)

```python
v = Vice(["-autostart", str(d64)])     # x64sc + remote monitor on a free port
v.peek(addr, n) / v.peek16(addr) / v.poke(addr, *bytes)
v.screen_text(rows)                    # screen RAM as text, reverse ignored
v.key("Escape")                        # RUN/STOP; BackSpace=DEL, Home, F1..F7,
v.type("HELLO 123")                    #   Up/Down/Left/Right, Return, space
v.warp(True/False); v.wait_until(cond, timeout)   # warps while waiting
v.screenshot(path); v.quit()
symbols("editor") / symbols("fixture") # labels from build/*.sym
read_png(path)                         # stdlib PNG reader -> rows of RGB
```

Helpers (`tests/e2e/helpers.py`): `start_editor(d64)`, `wait_menu(v)`,
`status_line(v)`, `build_test_disk()` (packed editor + test tune as PRG and
PSID + a ROM-derived italic font, all generated in a temp dir), `make(...)`.

## Rules of thumb

- Keys: press at normal speed (warp makes key repeat fire). Disk operations
  (LOAD/SAVE with true drive emulation take 20+ s) always inside
  `wait_menu`/`wait_until`, which enable warp.
- Every monitor access pauses the emulation; polling loops must allow for
  that (sample until the condition is met, with a generous timeout).
- Quit the editor VICE before loading the same D64 in a second VICE, so the
  image is written back.
- Test methods in one class share a VICE instance and run in name order:
  number them `test_01_...`.
- Check memory (config block `$2800`, text `$2C00`, font `$2000`, editor
  variables via symbols) rather than pixels where possible; for raster
  checks see the `raster-timing` skill.
