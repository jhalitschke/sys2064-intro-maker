"""Editor tests without disk access (M3), driven with real key presses."""
import time
import unittest

from helpers import (HEADER, OUT, at_menu, make, need_display, select_entry, start_editor,
                     status_line)
from vice import BUILD, symbols

TEXT = 0x2C00
TEXT_MAX = 5118
CONFIG = 0x2800


@need_display
class EditorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        make("disk")
        cls.sym = symbols("editor")
        cls.v = start_editor(BUILD / "intromaker.d64")

    @classmethod
    def tearDownClass(cls):
        cls.v.quit()

    def back_to_menu(self):
        self.v.key("Escape")
        self.assertTrue(at_menu(self.v))

    def test_01_menu(self):
        lines = self.v.screen_text()
        self.assertEqual(lines[0].strip(), HEADER)
        self.assertEqual(lines[2], "1 MUSIC:  NO MUSIC")
        self.assertEqual(lines[3], "2 FONT:   ROM")
        self.assertEqual(lines[7], "6 TITLE STYLE  NONE (1X1)")
        self.assertEqual(lines[8], "7 SCROLLTEXT (0/5118)")
        self.assertEqual(lines[9], "8 LINK PROGRAM")
        self.assertEqual(lines[11], "0 SAVE")
        self.assertEqual(status_line(self.v), "")          # catalog found

    def test_02_colors(self):
        v = self.v
        v.key("3")
        v.key("1")
        v.key("1")
        v.key("4")
        self.assertEqual(v.peek(CONFIG + 4, 4), [2, 0, 1, 8])
        self.assertEqual(v.screen_text(3)[2].split()[-1], "2")
        self.back_to_menu()

    def test_03_effects(self):
        v = self.v
        before = v.peek(CONFIG + 3)[0]
        v.key("4")
        v.key("4")                          # sprites on
        v.key("3")                          # preset 1 -> 2
        v.key("6")                          # speed 2 -> 4
        v.key("6")                          # speed 4 -> 1
        self.assertEqual(v.peek(CONFIG + 3)[0], before ^ 8)
        self.assertEqual(v.peek(CONFIG + 8, 2), [1, 1])
        lines = v.screen_text(8)
        self.assertEqual(lines[5], "4 SPRITES       ON")
        self.assertEqual(lines[4], "3 BAR COLORS    2")
        v.key("6")                          # back to 2
        self.back_to_menu()

    def test_04_title(self):
        v = self.v
        v.key("5")
        v.type("HELLO")
        v.key("Down")                       # second row, column 5
        v.type("X")
        v.key("Left")
        v.key("BackSpace")                  # blanks column 4 of row 2
        title = v.peek(CONFIG + 0x10, 80)
        self.assertEqual(title[:5], [8, 5, 12, 12, 15])
        self.assertEqual(title[44:46], [0x20, 0x18])
        self.back_to_menu()

    def test_05_scrolltext_editing(self):
        v = self.v
        v.key("7")
        v.type("ABCDEF")
        v.key("Left")
        v.key("Left")
        v.type("X")                         # ABCDXEF
        v.key("Left")
        v.key("Left")
        v.key("BackSpace")                  # ABDXEF
        v.key("Home")
        v.type("Z")                         # ZABDXEF
        v.key("F1")
        v.key("F7")                         # control codes
        self.assertEqual(v.peek(TEXT, 10), [26, 0xF1, 0xF8, 1, 2, 4, 24, 5, 6, 0xFF])
        self.assertEqual(v.peek16(self.sym["ed_text_len"]), 9)
        self.assertEqual(v.peek16(self.sym["ed_cur"]), 3)
        # control codes are shown reversed: Z 1 P
        self.assertEqual(v.peek(0x0400 + 3 * 40, 3), [26, 0xB1, 0x90])
        self.assertEqual(v.screen_text(25)[24], "CHARS 9/5118")
        self.back_to_menu()
        self.assertEqual(v.screen_text(9)[8], "7 SCROLLTEXT (9/5118)")

    def test_06_scrolltext_window_and_limit(self):
        v = self.v
        n = TEXT_MAX - 1
        v.poke(TEXT, *([(i % 26) + 1 for i in range(n)] + [0xFF]))
        v.poke(self.sym["ed_text_len"], n & 0xFF, n >> 8)
        v.key("7")
        for _ in range(20):
            v.key("Down", hold=0.05, after=0.1)
        cur, win = v.peek16(self.sym["ed_cur"]), v.peek16(self.sym["ed_win"])
        self.assertEqual(cur, 800)
        self.assertTrue(win <= cur < win + 720 and win % 40 == 0)
        v.type("Q")                         # accepted: 5118
        v.type("R")                         # rejected, border flashes
        self.assertEqual(v.peek16(self.sym["ed_text_len"]), TEXT_MAX)
        self.assertEqual(v.peek(TEXT + TEXT_MAX, 2), [0xFF, 0x00])   # $3fff stays 0
        v.key("Home")
        self.assertEqual(v.peek16(self.sym["ed_win"]), 0)
        # back to a short text for the next tests
        v.poke(TEXT, 8, 9, 0xFF)
        v.poke(self.sym["ed_text_len"], 2, 0)
        self.back_to_menu()

    def test_07_bold_font(self):
        v = self.v
        v.key("2")
        select_entry(v, 1)                  # ROM BOLD
        v.key("Return")
        time.sleep(0.5)
        self.assertEqual(v.screen_text(4)[3], "2 FONT:   ROM BOLD")
        self.assertEqual(v.peek(0x2008, 7), [0x1C, 0x3E, 0x77, 0x7F, 0x77, 0x77, 0x77])

    def test_08_preview_ten_times(self):
        v = self.v
        OUT.mkdir(parents=True, exist_ok=True)
        for i in range(10):
            v.key("9")
            time.sleep(1.2)
            self.assertEqual(v.peek(0x01)[0], 0x35, f"preview {i}: runtime not active")
            v.key("space", hold=0.15, after=0.6)
            self.assertTrue(at_menu(v), f"preview {i}: no menu")
            self.assertEqual(v.peek(0xC6)[0], 0, "keyboard buffer not cleared")
        v.key("9")
        time.sleep(2)
        v.screenshot(OUT / "editor_preview.png")
        self.assertEqual(v.peek(0x0400 + 40, 5), [8, 5, 12, 12, 15])     # title
        v.key("space", hold=0.15, after=0.6)
        # keyboard still works
        v.key("5")
        self.assertEqual(v.screen_text(1)[0], "TITLE")
        self.back_to_menu()

    def test_09_title_style_rom2x2_and_movement(self):
        v = self.v
        v.key("6")
        self.assertEqual(v.screen_text(1)[0], "TITLE STYLE")
        v.key("1")
        self.assertEqual([l.strip() for l in v.screen_text(8)[4:7]],
                         ["NONE (1X1)", "ROM 2X2", "FROM DISK..."])
        select_entry(v, 1)                  # ROM 2X2
        v.key("Return")
        self.assertTrue(v.wait_until(lambda: v.screen_text(1)[0] == "TITLE STYLE", timeout=20))
        self.assertEqual(v.peek(CONFIG + 0x60, 3), [2, 2, 0])
        glyph_map = v.peek(CONFIG + 0x70, 64)
        self.assertEqual(glyph_map[1], 0x40)                 # A: first tiles
        self.assertEqual(sum(1 for g in glyph_map if g), 48)
        self.assertTrue(any(v.peek(0x2200, 32)), "A tiles are empty")
        v.key("2")
        v.key("2")                          # STATIC -> SWING -> SINE
        v.key("3")                          # speed 2 -> 3
        v.key("4")                          # MC colour 1: 11 -> 12
        self.assertEqual(v.peek(CONFIG + 0x63, 4), [12, 12, 2, 3])
        lines = v.screen_text(9)
        self.assertEqual(lines[3], "2 MOVEMENT      SINE")
        self.assertEqual(lines[8], "TITLE CHARS PER LINE: 20")
        self.back_to_menu()
        self.assertEqual(v.screen_text(8)[7], "6 TITLE STYLE  ROM 2X2")
        # preview: "HELLO" in 2x2 tiles, moving up and down
        v.key("9")
        time.sleep(1.5)
        screen = v.peek(0x0400, 9 * 40)
        tiles = [c for c in screen if c >= 0x40 and c != 0xA0]
        self.assertEqual(len(tiles), 6 * 4, "HELLO + X (line 2, test_04) = 6 glyphs x 4 tiles")
        ys = set()
        for _ in range(8):
            ys.add(v.peek(0x19)[0])                     # rt_py
            time.sleep(0.15)
        self.assertGreater(len(ys), 2, "title does not move")
        v.key("space", hold=0.15, after=0.6)
        self.assertTrue(at_menu(v))


if __name__ == "__main__":
    unittest.main()
