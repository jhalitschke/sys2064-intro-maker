"""Runtime tests with the fixture image (make fixture)."""
import time
import unittest
import wave
import struct

from helpers import OUT, make, need_display, need_headless
from vice import BUILD, Vice, read_png, screenshot_run, symbols

RASTER_OFFSET = 16          # screenshot y = raster line - 16 (PAL, normal borders)
FLD_FIRST, FLD_END = 131, 211
DISPLAY_X = range(32, 352)  # 40 column display window in the screenshot
FLAG_BARS, FLAG_ALL = 2, 31


def check_frame(path, border, bg=(0, 0, 0)):
    """Returns (issues, bar rows, bar runs) for one fixture screenshot."""
    width, height, px = read_png(path)
    issues, bar_rows = [], []
    for y in range(FLD_FIRST - RASTER_OFFSET, FLD_END - RASTER_OFFSET):
        row = px[y]
        uniform = len(set(row)) == 1
        default = all(row[x] == border for x in range(width) if x not in DISPLAY_X) and \
            all(row[x] == bg for x in DISPLAY_X)
        if uniform and row[0] != border:
            bar_rows.append(y + RASTER_OFFSET)
        elif not default:
            issues.append(f"raster {y + RASTER_OFFSET}: mixed colours {sorted(set(row))[:4]}")
    # outside the FLD gap the side border keeps the border colour
    for y in list(range(51 - RASTER_OFFSET, FLD_FIRST - RASTER_OFFSET)) + \
            list(range(FLD_END - RASTER_OFFSET, 251 - RASTER_OFFSET)):
        if px[y][5] != border:
            issues.append(f"raster {y + RASTER_OFFSET}: border {px[y][5]}")
    runs = []
    for r in bar_rows:
        if runs and runs[-1][1] == r - 1:
            runs[-1][1] = r
        else:
            runs.append([r, r])
    return issues, bar_rows, [tuple(r) for r in runs]


@need_headless
class FlagCombinationTests(unittest.TestCase):
    """Every flag combination: straight full-width bars only inside the FLD
    gap (raster 131-210), no stripes, stable over different frames."""

    @classmethod
    def tearDownClass(cls):
        make("fixture")                       # back to the default fixture

    def test_all_flag_combinations(self):
        OUT.mkdir(parents=True, exist_ok=True)
        border = None
        for flags in range(32):
            with self.subTest(flags=flags):
                make("fixture", FIXTURE_FLAGS=str(flags))
                png = OUT / f"flags{flags:02d}.png"
                # different cycle counts -> different frames / IRQ jitter
                screenshot_run(BUILD / "fixture.prg", png, 20_000_000 + flags * 7919)
                if border is None:
                    border = read_png(png)[2][5][5]
                issues, bar_rows, runs = check_frame(png, border)
                self.assertEqual(issues, [])
                if flags & FLAG_BARS:
                    self.assertGreaterEqual(len(bar_rows), 15)
                else:
                    self.assertEqual(bar_rows, [])
                if flags & 6 == FLAG_BARS:     # bars without sine: fixed 5/32/60
                    self.assertEqual(runs, [(136, 150), (163, 177), (191, 205)])


@need_display
class RuntimeInteractiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        make("fixture")
        cls.sym = symbols("fixture")

    def start(self):
        v = Vice(["-autostartprgmode", "1", "-autostart", str(BUILD / "fixture.prg")])
        v.wait_until(lambda: v.peek(0x01)[0] == 0x35, timeout=30)
        return v

    def test_scroller_speed_and_pause(self):
        v = self.start()
        try:
            seen, pause_ptrs = set(), []
            t0 = time.time()
            # monitor peeks pause the emulation: sample until everything was seen
            while time.time() - t0 < 45 and not (seen == {1, 2, 4} and len(pause_ptrs) > 2):
                lo, hi, _, speed, pause = v.peek(0x02, 5)
                seen.add(speed)
                if pause:
                    pause_ptrs.append((lo | hi << 8, pause))
                time.sleep(0.1)
            self.assertEqual(seen, {1, 2, 4})
            self.assertTrue(pause_ptrs, "pause never seen")
            self.assertEqual(len({p for p, _ in pause_ptrs}), 1, "text moved during pause")
        finally:
            v.quit()

    def test_space_resets(self):
        v = self.start()
        try:
            time.sleep(1)
            v.key("space", hold=0.2, after=3)
            self.assertIn("READY.", v.screen_text(8))
        finally:
            v.quit()

    def test_music_tempo(self):
        """Arpeggio note every 2 frames: the pitch pattern repeats every 120 ms."""
        OUT.mkdir(parents=True, exist_ok=True)
        wav = OUT / "fixture.wav"
        import subprocess
        subprocess.run(["x64sc", "-default", "-pal", "-sounddev", "wav", "-soundarg", str(wav),
                        "-limitcycles", "5000000", "-autostartprgmode", "1",
                        "-autostart", str(BUILD / "fixture.prg")],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
        with wave.open(str(wav)) as w:
            rate, ch, n = w.getframerate(), w.getnchannels(), w.getnframes()
            data = struct.unpack(f"<{n * ch}h", w.readframes(n))[::ch]
        start = next(i for i, s in enumerate(data) if abs(s) > 500) + rate // 2
        win = rate // 100                    # 10 ms windows
        freqs = []
        for i in range(start, start + rate, win):
            seg = data[i:i + win]
            m = sum(seg) / len(seg)
            freqs.append(sum(1 for a, b in zip(seg, seg[1:]) if (a - m) * (b - m) < 0))
        # autocorrelation of the zero crossing pattern: best period in windows
        def score(p):
            return sum(abs(freqs[i] - freqs[i + p]) for i in range(len(freqs) - p)) / (len(freqs) - p)
        best = min(range(4, 30), key=score)
        self.assertEqual(best % 12, 0, f"pattern period {best * 10} ms, expected 120 ms")


if __name__ == "__main__":
    unittest.main()
