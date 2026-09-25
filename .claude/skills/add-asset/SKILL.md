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
3. `make` – `build_disk.py` validates and aborts with a message. Common
   rejections and fixes:
   - linked elsewhere than `$1000` → relocate with sidreloc
   - RSID, `play = 0`, speed bit set (CIA timing) → not supported
     (frame-based players called once per PAL frame only)
   - data beyond `$1FFF` → the tune is larger than 4 KB
   - font shorter than 512 bytes (`.64c` without its 2-byte load address)
4. Limits: 15 tunes, 14 fonts (list rows, see `docs/QUESTIONS.md`).
5. Check `build/CREDITS.txt` and, for music, listen in the editor
   (`make run`, key `1`).

File name casing: the catalog stores `file.upper()` (PETSCII `$41-$5A`),
c1541 gets the lower-case name and writes exactly those bytes;
`build_disk.py` verifies the D64 directory after writing.

Licensing: HVSC is an archive, not a permission. Record the author's
permission in `license`.
