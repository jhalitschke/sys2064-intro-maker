---
name: add-asset
description: Add a SID tune or a font to the C64 Intro Maker disk via assets/manifest.toml and tools/build_disk.py, including validation rules and licensing. Use when the user wants new music or fonts on the disk or build_disk.py rejects an asset.
---

# Adding a SID or font

1. Put the file into `assets/sids/` or `assets/fonts/` (git-ignored – never
   commit third-party files; only the own test tune is in the repo).
2. Add an entry to `assets/manifest.toml` (or a private manifest used with
   `make MANIFEST=path`):
   - `name`: max. 20 chars, `A-Z 0-9 space . , ! ? - : / ( )` (upper-cased)
   - `file`: disk name, `a-z 0-9 -`, max. 16, lower case, unique
   - `src`: path relative to the repo root
   - `license` is required, `author` recommended
   - `.prg` tunes need `init` and `play`; PSIDs take them from the header
3. `python3 tools/check_sid.py <file>` – the header checks of
   `build_disk.py` only see load address, size and speed bit. This traces the
   player from init and play and reports writes, reads and JMP/JSR targets
   that leave `$1000-$1FFF`: runtime zero page, font, runtime tables, scroll
   text, VIC or CIA. A tune that passes the build but fails here corrupts the
   intro at run time. Reads and jumps matter after a sidreloc run, which
   leaves behind the references it cannot prove are addresses.
   Static analysis - a clean result is strong evidence, not a proof, and a
   low reported code coverage makes it worth little. Listen in the editor.
4. `make` – `build_disk.py` validates and aborts with a message. Common
   rejections and fixes:
   - linked elsewhere than `$1000` → relocate with sidreloc
   - RSID, `play = 0`, speed bit set (CIA timing) → not supported
     (frame-based players called once per PAL frame only)
   - data beyond `$1FFF` → the tune is larger than 4 KB
   - font shorter than 512 bytes (`.64c` without its 2-byte load address)
5. Limits: 15 tunes, 14 fonts (list rows, see `docs/QUESTIONS.md`).
6. Check `build/CREDITS.txt` and, for music, listen in the editor
   (`make run`, key `1`).

File name casing: the catalog stores `file.upper()` (PETSCII `$41-$5A`),
c1541 gets the lower-case name and writes exactly those bytes;
`build_disk.py` verifies the D64 directory after writing.

Licensing: HVSC is an archive, not a permission. Record the author's
permission in `license`.
