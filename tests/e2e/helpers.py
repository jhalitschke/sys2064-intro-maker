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

from vice import BUILD, HAVE_XLIB, REPO, Vice

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
    })
    return files


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
