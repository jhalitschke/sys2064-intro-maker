# Open questions / deviations

Places where the specification is unclear or contradictory, and how they are
handled for now.

1. **Language.** The original spec asked for German UI texts. On request the
   whole repository (code, UI texts, tool messages, docs) is English;
   `docs/SPEC.md` is an English translation of the original.
2. **Font list > 16 entries.** The spec allows 15 catalog fonts, but the list
   has only 16 rows (4-19) and 2 built-in fonts. `build_disk.py` therefore
   limits fonts to 14 (`CAT_MAX_FONTS`). The alternative would be a
   scrolling list.
3. **`$3FFF` in saved intros.** The save range ends at end of text + 1, so
   `$3FFF` is usually not part of the saved file and contains whatever the
   RAM holds after a reset. `runtime_start` therefore also clears `$3FFF`
   (it is never part of the text: the terminator is at `$3FFE` at most).
4. **Reset path.** Before `JMP $FCE2` the runtime additionally disables the
   raster IRQ, sprites and SID volume (with `SEI`), so no IRQ can hit the
   switched-in KERNAL between `$01=$37` and the reset code.
5. **Scroll text status line.** `CHARS n/5118  F1 F3 F5 SPEED  F7 PAUSE  STOP BACK`
   has more than 40 characters. The editor shows the key hints in row 23 and
   `CHARS n/5118` in the status row 24.
6. **DEL in the title editor.** The spec only says "overwrite mode". DEL moves
   the cursor left and blanks that character.
7. **Smoke test cycles.** The unpacked editor (73 blocks) needs more than
   40 M cycles to autostart from the D64 with the standard KERNAL loader;
   `make smoke` uses 80 M cycles for the editor screenshot.
