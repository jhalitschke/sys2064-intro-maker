"""Shared helpers for the VICE end-to-end tests."""
from __future__ import annotations

import os
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

from vice import BUILD, HAVE_XLIB, REPO, Vice, symbols

sys.path.insert(0, str(REPO / "tools"))
import build_disk  # noqa: E402

HEADER = "C64 INTRO MAKER"
OUT = Path(os.environ.get("E2E_OUT", BUILD / "e2e"))


def need_display(cls):
    """Skip interactive tests without python-xlib or outside `make e2e`.
    XTEST key presses go to the focused window of the X server, so they
    must only ever run inside the private Xvfb started by `make e2e`."""
    if not HAVE_XLIB:
        return unittest.skip("python-xlib not installed")(cls)
    if not os.environ.get("E2E_HEADLESS") or not os.environ.get("DISPLAY"):
        return unittest.skip("run via `make e2e` (private Xvfb)")(cls)
    return cls


def need_headless(cls):
    """VICE windows only inside the private Xvfb of `make e2e`."""
    if not os.environ.get("E2E_HEADLESS") or not os.environ.get("DISPLAY"):
        return unittest.skip("run via `make e2e` (private Xvfb)")(cls)
    return cls


def make(*targets: str, **variables: str):
    args = ["make", "-s", "-C", str(REPO)] + [f"{k}={v}" for k, v in variables.items()]
    subprocess.run(args + list(targets), check=True, stdout=subprocess.DEVNULL)


def at_menu(v: Vice) -> bool:
    return v.screen_text(1)[0].strip() == HEADER


def start_editor(image: Path) -> Vice:
    """Autostart the D64 (warp while loading) and wait for the main menu."""
    v = Vice(["-autostart", str(image)])
    if not v.wait_until(lambda: at_menu(v), timeout=90):
        v.quit()
        raise AssertionError("editor menu did not appear")
    return v


def wait_menu(v: Vice, timeout: float = 120) -> bool:
    """Warp until the main menu is back (after LOAD / SAVE)."""
    return v.wait_until(lambda: at_menu(v), timeout=timeout)


def select_entry(v: Vice, target: int, tries: int = 400):
    """Move the list selection to `target` with CRSR keys, checking the
    editor's selection after every key (keys can get lost or repeat)."""
    addr = symbols("editor")["ed_list_sel"]
    for _ in range(tries):
        sel = v.peek(addr)[0]
        if sel == target:
            return
        v.key("Down" if sel < target else "Up", hold=0.06, after=0.08)
    raise AssertionError(f"list selection stuck at {sel}, wanted {target}")


def status_line(v: Vice) -> str:
    return v.screen_text(25)[24].strip()


# ---- test assets (generated, never committed) -------------------------------

def chargen_rom() -> bytes | None:
    for d in (Path.home() / ".local/share/vice/C64", Path("/usr/share/vice/C64"),
              Path("/usr/lib/vice/C64")):
        for f in sorted(d.glob("chargen*")) if d.is_dir() else []:
            return f.read_bytes()
    return None


def italic_font(rom: bytes) -> bytes:
    """Derived from the ROM font at test time: rows shifted to the right."""
    out = bytearray()
    for c in range(64):
        for r in range(8):
            out.append(rom[c * 8 + r] >> ((7 - r) // 3))
    return bytes(out)


def big_font_2x2(rom: bytes) -> bytes:
    """Linear 2x2 charset (64 glyphs x 4 chars) from the ROM font, pixels
    doubled (derived at test time)."""
    def double(b):
        w = 0
        for i in range(8):
            if b & (0x80 >> i):
                w |= 0xC000 >> (2 * i)
        return w
    out = bytearray()
    for g in range(64):
        rows = [double(rom[g * 8 + r]) for r in range(8)]
        tall = [x for x in rows for _ in range(2)]            # 16 rows
        for ty in range(2):
            for tx in range(2):
                for r in range(8):
                    w = tall[ty * 8 + r]
                    out.append((w >> 8) & 0xFF if tx == 0 else w & 0xFF)
    return bytes(out)


def psid_from_prg(prg: bytes) -> bytes:
    """Wrap a $1000 PRG tune into a PSID v2 file with load address 0."""
    hdr = b"PSID" + struct.pack(">HHHHHHHI", 2, 0x7C, 0, 0x1000, 0x1003, 1, 1, 0)
    hdr += b"TEST AS PSID".ljust(32, b"\0") + b"TEST".ljust(32, b"\0") + b"2026".ljust(32, b"\0")
    return hdr.ljust(0x7C, b"\0") + prg


def build_test_disk() -> tuple[Path, Path]:
    """D64 with the packed editor, 2 tunes (PRG + PSID) and 1 font.
    Returns (d64, tmpdir)."""
    tmp = Path(tempfile.mkdtemp(prefix="im-e2e-"))
    rom = chargen_rom()
    if rom is None:
        raise unittest.SkipTest("no VICE chargen ROM found")
    (tmp / "italic.64c").write_bytes(b"\x00\x20" + italic_font(rom))
    (tmp / "big.bin").write_bytes(big_font_2x2(rom))
    (tmp / "tune.sid").write_bytes(psid_from_prg((BUILD / "testtune.prg").read_bytes()))
    (tmp / "manifest.toml").write_text(f"""
[[sid]]
name = "TEST TUNE"
file = "tune-test"
src = "{BUILD / 'testtune.prg'}"
init = 0x1000
play = 0x1003
license = "own work"

[[sid]]
name = "PSID TUNE"
file = "tune-psid"
src = "{tmp / 'tune.sid'}"
license = "own work"

[[font]]
name = "ITALIC ROM"
file = "font-italic"
src = "{tmp / 'italic.64c'}"
license = "test only"

[[bigfont]]
name = "TEST BIG"
file = "big-test"
src = "{tmp / 'big.bin'}"
width = 2
height = 2
license = "test only"
""")
    d64 = tmp / "test.d64"
    rc = build_disk.main(["--manifest", str(tmp / "manifest.toml"), "--root", str(REPO),
                          "--editor", str(BUILD / "editor.exo.prg"),
                          "--build", str(tmp / "build"), "--out", str(d64)])
    if rc:
        raise AssertionError("build_disk failed")
    add_raw_files(d64, tmp)
    return d64, tmp


# raw files for the disk browser (written as they are, no catalog entry)
DUMMIES = 12


def raw_files(tmp: Path) -> dict[str, bytes]:
    tune = (BUILD / "testtune.prg").read_bytes()
    psid = psid_from_prg(tune)
    rsid = b"RSID" + psid[4:]
    cia = bytearray(psid)
    cia[0x15] = 1                                   # speed bit of song 1
    files = {f"dummy-{i:02d}": b"\x01\x08" + bytes(10) for i in range(DUMMIES)}
    files.update({
        "raw-psid": psid,
        "raw-tune": tune,
        "raw-font": (tmp / "italic.64c").read_bytes(),
        "raw-rsid": rsid,
        "raw-cia": bytes(cia),
        "raw-c000": b"\x00\xc0" + tune[2:],
        "raw-short": b"\x00\x20" + bytes(100),
        "raw-big": (tmp / "build" / "bigfonts" / "big-test.prg").read_bytes(),
    })
    files.update(linked_programs())
    return files


def basic_prg(lines: list[tuple[int, bytes]]) -> bytes:
    """Tokenised BASIC program at $0801 from (line number, token bytes)."""
    addr, out = 0x0801, bytearray()
    for num, body in lines:
        nxt = addr + 4 + len(body) + 1
        out += struct.pack("<HH", nxt, num) + body + b"\x00"
        addr = nxt
    return struct.pack("<H", 0x0801) + bytes(out) + b"\x00\x00"


POKE, PRINT, REM = 0x97, 0x99, 0x8F


def linked_programs() -> dict[str, bytes]:
    """Programs to link in front of: BASIC (RUN), ML with overlapping move,
    ML high up. Each sets the border colour so the test can see it ran."""
    pad = [(100 + i, bytes([REM]) + b" " + b"X" * 70) for i in range(120)]   # ~9 KB
    basic = basic_prg([(10, bytes([POKE]) + b"53280,5"),
                       (20, bytes([PRINT]) + b'"LINKED OK"')] + pad + [(999, b"\x80")])
    def ml(load: int, size: int, colour: int) -> bytes:
        code = bytes([0xA9, colour, 0x8D, 0x20, 0xD0, 0x4C, load & 0xFF, (load >> 8) + 0])
        code = code[:5] + bytes([0x4C, (load + 5) & 0xFF, (load + 5) >> 8])
        body = code + bytes((i * 7 + 3) & 0xFF for i in range(len(code), size))
        return struct.pack("<H", load) + body
    return {"link-basic": basic, "link-ml5000": ml(0x5000, 0x3000, 7),
            "link-mlc000": ml(0xC000, 0x0800, 2)}


def add_raw_files(d64: Path, tmp: Path):
    args = ["c1541", "-attach", str(d64)]
    for name, data in raw_files(tmp).items():
        path = tmp / f"{name}.raw"
        path.write_bytes(data)
        args += ["-write", str(path), name]
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def dir_index(d64: Path, name: str) -> int:
    """Position of a PRG file in the directory list of the editor."""
    names = [n.decode("latin1") for n, t in build_disk.read_d64_directory(d64.read_bytes())
             if t & 7 == 2]
    return names.index(name.upper())


def cleanup(tmp: Path):
    shutil.rmtree(tmp, ignore_errors=True)


def settle(seconds: float):
    time.sleep(seconds)
