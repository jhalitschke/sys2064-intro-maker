"""VICE end-to-end test driver.

- Starts x64sc with the text remote monitor (memory peeks/pokes, warp,
  screenshots).
- Sends real key presses through the X server (XTEST), so the C64 sees them
  in its keyboard matrix. This also works for code that scans the CIA
  directly (SPACE in the runtime), which -keybuf cannot do.
- Reads PNG screenshots with the standard library only.

Must run under an X server, e.g. `xvfb-run -a`. The key presses need
python-xlib (the only non-stdlib dependency, used by these tests only).
"""
from __future__ import annotations

import os
import re
import socket
import struct
import subprocess
import time
import zlib
from pathlib import Path

try:
    from Xlib import X, XK, display
    from Xlib.ext import xtest
    HAVE_XLIB = True
except ImportError:  # pragma: no cover - reported as skip by the tests
    HAVE_XLIB = False

REPO = Path(__file__).resolve().parents[2]
BUILD = REPO / "build"
X64 = os.environ.get("X64", "x64sc")

PROMPT = re.compile(rb"\(C:\$[0-9a-f]{4}\) ")


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def symbols(name: str) -> dict[str, int]:
    """Labels from build/<name>.sym (written by the Makefile)."""
    text = (BUILD / f"{name}.sym").read_text()
    return {k: int(v, 16) for k, v in re.findall(r"\.label (\w+)=\$([0-9a-f]+)", text)}


class Vice:
    def __init__(self, args: list[str]):
        self.port = free_port()
        self.proc = subprocess.Popen(
            [X64, "-default", "-pal", "-sounddev", "dummy", "-remotemonitor",
             "-remotemonitoraddress", f"ip4://127.0.0.1:{self.port}"] + args,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.sock = None
        for _ in range(100):
            try:
                self.sock = socket.create_connection(("127.0.0.1", self.port))
                break
            except OSError:
                time.sleep(0.1)
        if self.sock is None:
            self.proc.kill()
            raise RuntimeError("cannot connect to the VICE remote monitor")
        self.sock.settimeout(5)
        self.in_mon = True
        self.disp = display.Display() if HAVE_XLIB else None
        time.sleep(0.5)
        self.cmd("x")

    # ---- remote monitor ---------------------------------------------------
    def _drain(self):
        self.sock.settimeout(0.2)
        try:
            while self.sock.recv(65536):
                pass
        except (socket.timeout, BlockingIOError):
            pass
        self.sock.settimeout(5)

    def _read_prompts(self, count: int) -> str:
        buf = b""
        while True:
            try:
                chunk = self.sock.recv(65536)
            except socket.timeout:
                break
            if not chunk:
                break
            buf += chunk
            if buf.endswith(b") ") and len(PROMPT.findall(buf)) >= count:
                break
        return buf.decode("latin1")

    def cmd(self, command: str) -> str:
        """Send one monitor command. Entering the monitor from a running
        machine prints an extra prompt first."""
        self._drain()
        self.sock.sendall((command + "\n").encode())
        if command.strip() == "x":
            self.in_mon = False
            time.sleep(0.05)
            return ""
        count = 1 if self.in_mon else 2
        self.in_mon = True
        return self._read_prompts(count)

    def mon(self, *commands: str) -> list[str]:
        out = [self.cmd(c) for c in commands]
        self.cmd("x")
        return out

    def peek(self, addr: int, n: int = 1) -> list[int]:
        out = self.mon(f"m {addr:04x} {addr + n - 1:04x}")[0]
        vals: list[int] = []
        for line in out.splitlines():
            m = re.search(r">C:([0-9a-f]{4})((?:\s{1,2}[0-9a-f]{2})+)", line)
            if m:
                vals += [int(v, 16) for v in m.group(2).split()]
        return vals[:n]

    def peek16(self, addr: int) -> int:
        lo, hi = self.peek(addr, 2)
        return lo | hi << 8

    def poke(self, addr: int, *vals: int):
        for off in range(0, len(vals), 64):
            chunk = vals[off:off + 64]
            self.cmd(f"> {addr + off:04x} " + " ".join(f"{v:02x}" for v in chunk))
        self.cmd("x")

    def screenshot(self, path: Path):
        self.mon(f'screenshot "{path}" 2')

    def warp(self, on: bool):
        self.mon("warp " + ("on" if on else "off"))

    def wait_until(self, cond, timeout: float = 90, warp: bool = True) -> bool:
        if warp:
            self.warp(True)
        t0 = time.time()
        ok = False
        while time.time() - t0 < timeout:
            time.sleep(0.3)
            if cond():
                ok = True
                break
        if warp:
            self.warp(False)
        time.sleep(0.3)
        return ok

    # ---- keyboard (XTEST) -------------------------------------------------
    KEYSYMS = {" ": "space", ".": "period", ",": "comma", "-": "minus", "!": "exclam",
               ":": "colon", "/": "slash", "?": "question", "(": "parenleft",
               ")": "parenright"}

    def key(self, name: str, hold: float = 0.08, after: float = 0.15):
        """Press an X key: letters/digits, 'space', 'Return', 'Escape' (RUN/STOP),
        'BackSpace' (DEL), 'Home', 'Up'/'Down'/'Left'/'Right', 'F1'..'F7'."""
        code = self.disp.keysym_to_keycode(XK.string_to_keysym(name))
        xtest.fake_input(self.disp, X.KeyPress, code)
        self.disp.sync()
        time.sleep(hold)
        xtest.fake_input(self.disp, X.KeyRelease, code)
        self.disp.sync()
        time.sleep(after)

    def type(self, text: str):
        for ch in text:
            self.key(ch.lower() if ch.isalnum() else self.KEYSYMS[ch])

    # ---- screen -----------------------------------------------------------
    def screen_text(self, rows: int = 25) -> list[str]:
        """Screen RAM as text (reverse video ignored)."""
        mem = self.peek(0x0400, rows * 40)
        lines = []
        for r in range(rows):
            line = ""
            for c in mem[r * 40:(r + 1) * 40]:
                c &= 0x7F
                line += chr(c + 64) if 1 <= c <= 26 else "@" if c == 0 else chr(c) if c < 0x40 else "?"
            lines.append(line.rstrip())
        return lines

    def quit(self):
        try:
            self.sock.sendall(b"quit\n")
        except OSError:
            pass
        try:
            self.proc.wait(5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        self.sock.close()
        if self.disp is not None:
            self.disp.close()
            self.disp = None


def read_png(path: Path) -> tuple[int, int, list[list[tuple[int, int, int]]]]:
    """Minimal PNG reader (8 bit RGB/RGBA, not interlaced) -> rows of RGB."""
    data = Path(path).read_bytes()
    pos, idat, width = 8, b"", 0
    while pos < len(data):
        length, = struct.unpack(">I", data[pos:pos + 4])
        ctype = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if ctype == b"IHDR":
            width, height, depth, color, _, _, interlace = struct.unpack(">IIBBBBB", body)
            if depth != 8 or color not in (2, 6) or interlace:
                raise ValueError("unsupported PNG format")
            bpp = 3 if color == 2 else 4
        elif ctype == b"IDAT":
            idat += body
        pos += 12 + length
    raw = zlib.decompress(idat)
    stride = width * bpp
    rows, prev = [], bytearray(stride)
    for y in range(height):
        f = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if f == 1:
                line[i] = (line[i] + a) & 0xFF
            elif f == 2:
                line[i] = (line[i] + b) & 0xFF
            elif f == 3:
                line[i] = (line[i] + (a + b) // 2) & 0xFF
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 0xFF
        rows.append([tuple(line[x * bpp:x * bpp + 3]) for x in range(width)])
        prev = line
    return width, height, rows


def screenshot_run(prg_or_image: Path, out: Path, cycles: int, prg: bool = True):
    """Run VICE in warp until -limitcycles and save a screenshot (smoke style)."""
    args = [X64, "-default", "-pal", "-warp", "-sounddev", "dummy",
            "-limitcycles", str(cycles), "-exitscreenshot", str(out)]
    if prg:
        args += ["-autostartprgmode", "1"]
    subprocess.run(args + ["-autostart", str(prg_or_image)],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
