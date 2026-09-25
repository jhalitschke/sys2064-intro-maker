#!/usr/bin/env python3
"""Build the C64 Intro Maker disk image.

Reads assets/manifest.toml, validates and converts SIDs and fonts, writes
build/catalog.prg (load address $6000), build/CREDITS.txt and finally the
D64 via c1541. Only the Python standard library is used.
"""
from __future__ import annotations

import argparse
import re
import struct
import subprocess
import sys
import tomllib
from dataclasses import dataclass
from pathlib import Path

# Memory layout (mirrors src/shared/memmap.asm and config.asm)
SID_START = 0x1000
SID_END = 0x2000  # exclusive
FONT_ADDR = 0x2000
FONT_SIZE = 512
CATALOG_ADDR = 0x6000
CATALOG_MAX = 0x0800
REC_SIZE = 48
NAME_LEN = 20
FNAME_MAX = 16
MAX_SIDS = 15
MAX_FONTS = 14  # + 2 built-in fonts = 16 list rows (see docs/QUESTIONS.md)

DISK_NAME = "intro maker,im"
EDITOR_FILE = "intro maker"
CATALOG_FILE = "catalog"

NAME_RE = re.compile(r"^[A-Z0-9 .,!?\-:/()]{1,20}$")
FILE_RE = re.compile(r"^[a-z0-9-]{1,16}$")


class BuildError(Exception):
    """Validation error with a user readable message."""


@dataclass
class SidAsset:
    load: int
    payload: bytes
    init: int
    play: int
    subtune: int
    songs: int = 1


@dataclass
class Entry:
    kind: str  # "sid" or "font"
    name: str
    file: str
    prg: bytes
    author: str
    license: str
    init: int = 0
    play: int = 0
    subtune: int = 0


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def prg(load: int, data: bytes) -> bytes:
    return struct.pack("<H", load) + bytes(data)


def name_to_screencodes(name: str) -> bytes:
    """Upper-case name -> 20 screen codes, padded with spaces."""
    up = name.upper()
    if not NAME_RE.match(up):
        raise BuildError(
            f"Name {name!r}: max. {NAME_LEN} Zeichen aus A-Z 0-9 Leerzeichen . , ! ? - : / ( )")
    out = bytearray()
    for ch in up:
        c = ord(ch)
        if ord("A") <= c <= ord("Z"):
            out.append(c - ord("A") + 1)
        elif c == ord("@"):
            out.append(0)
        elif 0x20 <= c <= 0x3F:
            out.append(c)
        else:  # unreachable because of NAME_RE
            raise BuildError(f"Name {name!r}: Zeichen {ch!r} nicht erlaubt")
    return bytes(out.ljust(NAME_LEN, b"\x20"))


def validate_file(file: str) -> None:
    if not FILE_RE.match(file):
        raise BuildError(f"Dateiname {file!r}: nur a-z 0-9 -, max. {FNAME_MAX} Zeichen, klein geschrieben")


def catalog_filename(file: str) -> bytes:
    """Bytes the C64 passes to SETNAM: PETSCII $41-$5a for letters."""
    validate_file(file)
    return file.upper().encode("ascii")


def c1541_filename(file: str) -> str:
    """c1541 converts lower-case ASCII to PETSCII $41-$5a."""
    validate_file(file)
    return file.lower()


# ---------------------------------------------------------------------------
# SID handling
# ---------------------------------------------------------------------------

def parse_psid(data: bytes) -> dict:
    if len(data) < 0x76:
        raise BuildError("SID-Datei zu kurz fuer einen PSID-Header")
    magic = data[0:4]
    (version, data_offset, load, init, play, songs, start_song, speed) = struct.unpack(
        ">HHHHHHHI", data[4:22])
    return {
        "magic": magic, "version": version, "data_offset": data_offset,
        "load": load, "init": init, "play": play, "songs": songs,
        "start_song": start_song, "speed": speed,
    }


def check_sid_range(load: int, payload: bytes, init: int, play: int) -> None:
    if load != SID_START:
        raise BuildError(
            f"Tune ist auf ${load:04X} gelinkt, erwartet ${SID_START:04X}. "
            "Bitte mit sidreloc nach $1000 verschieben.")
    end = load + len(payload)
    if not payload or end > SID_END:
        raise BuildError(
            f"SID-Daten ${load:04X}-${end - 1:04X} liegen ausserhalb $1000-$1FFF (max. 4 KB)")
    if play == 0:
        raise BuildError("play = 0 wird nicht unterstuetzt (nur Frame-Player)")
    for label, addr in (("init", init), ("play", play)):
        if not load <= addr < end:
            raise BuildError(f"{label}-Adresse ${addr:04X} liegt ausserhalb der Daten")


def sid_from_psid(data: bytes, subtune: int | None = None) -> SidAsset:
    h = parse_psid(data)
    if h["magic"] == b"RSID":
        raise BuildError("RSID-Tunes werden nicht unterstuetzt (brauchen echte CIA/KERNAL-Umgebung)")
    if h["magic"] != b"PSID":
        raise BuildError("keine PSID-Datei")
    if h["play"] == 0:
        raise BuildError("play = 0 wird nicht unterstuetzt (nur Frame-Player)")
    body = data[h["data_offset"]:]
    load = h["load"]
    if load == 0:
        if len(body) < 2:
            raise BuildError("SID-Daten zu kurz")
        load = body[0] | (body[1] << 8)
        body = body[2:]
    init = h["init"] or load
    songs = max(h["songs"], 1)
    if subtune is None:
        subtune = max(h["start_song"], 1) - 1
    if not 0 <= subtune < songs:
        raise BuildError(f"Subtune {subtune} ungueltig (Tune hat {songs} Songs)")
    if h["speed"] & (1 << min(subtune, 31)):
        raise BuildError("Speed-Bit gesetzt (CIA-Timing) wird nicht unterstuetzt")
    check_sid_range(load, body, init, h["play"])
    return SidAsset(load, bytes(body), init, h["play"], subtune, songs)


def sid_from_prg(data: bytes, init: int | None, play: int | None, subtune: int = 0) -> SidAsset:
    if init is None or play is None:
        raise BuildError(".prg-SIDs brauchen init und play im Manifest")
    if len(data) < 3:
        raise BuildError("PRG zu kurz")
    load = data[0] | (data[1] << 8)
    body = data[2:]
    check_sid_range(load, body, init, play)
    if not 0 <= subtune <= 0xFF:
        raise BuildError(f"Subtune {subtune} ungueltig")
    return SidAsset(load, bytes(body), init, play, subtune)


# ---------------------------------------------------------------------------
# Fonts
# ---------------------------------------------------------------------------

def font_from_file(data: bytes, suffix: str) -> bytes:
    suffix = suffix.lower()
    if suffix == ".64c":
        data = data[2:]
    elif suffix != ".bin":
        raise BuildError(f"Font-Format {suffix!r} unbekannt (erlaubt: .64c, .bin)")
    if len(data) < FONT_SIZE:
        raise BuildError(f"Font hat nur {len(data)} Bytes, gebraucht werden {FONT_SIZE}")
    return bytes(data[:FONT_SIZE])


# ---------------------------------------------------------------------------
# Catalog
# ---------------------------------------------------------------------------

def catalog_record(e: Entry) -> bytes:
    fname = catalog_filename(e.file)
    rec = bytearray()
    rec += name_to_screencodes(e.name)
    rec.append(len(fname))
    rec += fname.ljust(FNAME_MAX, b"\x00")
    rec += struct.pack("<HHB", e.init, e.play, e.subtune)
    rec += bytes(REC_SIZE - len(rec))
    assert len(rec) == REC_SIZE
    return bytes(rec)


def build_catalog(sids: list[Entry], fonts: list[Entry]) -> bytes:
    if len(sids) > MAX_SIDS:
        raise BuildError(f"zu viele SIDs ({len(sids)}, max. {MAX_SIDS})")
    if len(fonts) > MAX_FONTS:
        raise BuildError(f"zu viele Fonts ({len(fonts)}, max. {MAX_FONTS})")
    body = bytes([len(sids), len(fonts)])
    for e in sids + fonts:
        body += catalog_record(e)
    if len(body) > CATALOG_MAX:
        raise BuildError("Katalog zu gross")
    return prg(CATALOG_ADDR, body)


# ---------------------------------------------------------------------------
# Manifest
# ---------------------------------------------------------------------------

def _require(item: dict, key: str, where: str):
    if key not in item or item[key] in ("", None):
        raise BuildError(f"{where}: Pflichtfeld {key!r} fehlt")
    return item[key]


def load_entries(manifest: dict, root: Path) -> tuple[list[Entry], list[Entry]]:
    sids: list[Entry] = []
    fonts: list[Entry] = []
    seen: set[str] = set()
    for kind in ("sid", "font"):
        for idx, item in enumerate(manifest.get(kind, [])):
            where = f"[[{kind}]] #{idx + 1}"
            name = _require(item, "name", where)
            file = _require(item, "file", where)
            src = _require(item, "src", where)
            lic = _require(item, "license", where)
            author = item.get("author", "unbekannt")
            where = f"{where} ({name})"
            try:
                name_to_screencodes(name)
                validate_file(file)
                if file in seen or file in (CATALOG_FILE, EDITOR_FILE):
                    raise BuildError(f"Dateiname {file!r} doppelt vergeben")
                seen.add(file)
                path = root / src
                if not path.is_file():
                    raise BuildError(f"Quelldatei {src} nicht gefunden")
                data = path.read_bytes()
                if kind == "sid":
                    sub = item.get("subtune")
                    if path.suffix.lower() == ".sid":
                        s = sid_from_psid(data, sub)
                    elif path.suffix.lower() == ".prg":
                        s = sid_from_prg(data, item.get("init"), item.get("play"), sub or 0)
                    else:
                        raise BuildError("SID-Format unbekannt (erlaubt: .sid, .prg)")
                    sids.append(Entry("sid", name, file, prg(s.load, s.payload), author, lic,
                                      s.init, s.play, s.subtune))
                else:
                    f = font_from_file(data, path.suffix)
                    fonts.append(Entry("font", name, file, prg(FONT_ADDR, f), author, lic))
            except BuildError as exc:
                raise BuildError(f"{where}: {exc}") from None
    return sids, fonts


def credits_text(sids: list[Entry], fonts: list[Entry]) -> str:
    lines = ["C64 INTRO MAKER - CREDITS", ""]
    for title, entries in (("MUSIK", sids), ("FONTS", fonts)):
        lines.append(title)
        if not entries:
            lines.append("  (keine)")
        for e in entries:
            lines.append(f"  {e.name.upper():<20}  {e.author}  |  Lizenz: {e.license}")
        lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# D64
# ---------------------------------------------------------------------------

def _d64_offset(track: int, sector: int) -> int:
    off = 0
    for t in range(1, track):
        off += 21 if t <= 17 else 19 if t <= 24 else 18 if t <= 30 else 17
    return (off + sector) * 256


def read_d64_directory(image: bytes) -> list[tuple[bytes, int]]:
    """Return (filename bytes without $a0 padding, file type) per entry."""
    entries = []
    track, sector = 18, 1
    visited = set()
    while track and (track, sector) not in visited:
        visited.add((track, sector))
        blk = image[_d64_offset(track, sector):][:256]
        for i in range(8):
            e = blk[i * 32:(i + 1) * 32]
            if e[2] == 0:
                continue
            entries.append((e[5:21].rstrip(b"\xa0"), e[2]))
        track, sector = blk[0], blk[1]
    return entries


def make_disk(c1541: str, out: Path, editor: Path, files: list[tuple[Path, str]]) -> None:
    if out.exists():
        out.unlink()
    cmd = [c1541, "-format", DISK_NAME, "d64", str(out), "-write", str(editor), EDITOR_FILE]
    for path, name in files:
        cmd += ["-write", str(path), name]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0 or not out.exists():
        raise BuildError(f"c1541 fehlgeschlagen:\n{res.stdout}{res.stderr}")
    names = [n for n, _ in read_d64_directory(out.read_bytes())]
    expected = [EDITOR_FILE.upper().encode()] + [n.upper().encode() for _, n in files]
    if names != expected:
        raise BuildError(f"D64-Verzeichnis unerwartet: {names} statt {expected}")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--manifest", default="assets/manifest.toml")
    ap.add_argument("--root", default=".", help="base directory for 'src' paths")
    ap.add_argument("--editor", default="build/editor.prg")
    ap.add_argument("--build", default="build")
    ap.add_argument("--out", default="build/intromaker.d64")
    ap.add_argument("--c1541", default="c1541")
    args = ap.parse_args(argv)

    build = Path(args.build)
    try:
        with open(args.manifest, "rb") as fh:
            manifest = tomllib.load(fh)
        sids, fonts = load_entries(manifest, Path(args.root))
        catalog = build_catalog(sids, fonts)
        build.mkdir(parents=True, exist_ok=True)
        (build / "sids").mkdir(exist_ok=True)
        (build / "fonts").mkdir(exist_ok=True)
        cat_path = build / "catalog.prg"
        cat_path.write_bytes(catalog)
        files = [(cat_path, CATALOG_FILE)]
        for e in sids + fonts:
            p = build / f"{e.kind}s" / f"{e.file}.prg"
            p.write_bytes(e.prg)
            files.append((p, c1541_filename(e.file)))
        (build / "CREDITS.txt").write_text(credits_text(sids, fonts), encoding="utf-8")
        make_disk(args.c1541, Path(args.out), Path(args.editor), files)
    except (BuildError, tomllib.TOMLDecodeError, OSError) as exc:
        print(f"build_disk: FEHLER: {exc}", file=sys.stderr)
        return 1
    print(f"build_disk: {args.out} ({len(sids)} SIDs, {len(fonts)} Fonts)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
