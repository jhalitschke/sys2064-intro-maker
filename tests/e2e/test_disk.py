"""Disk tests (M4/M5): catalog, loading, saving, and the saved intro in a
fresh VICE. Uses the packed editor and generated test assets."""
import subprocess
import time
import unittest

from helpers import (OUT, at_menu, build_test_disk, cleanup, make, need_display,
                     start_editor, status_line, wait_menu)
from vice import BUILD, Vice, symbols

CONFIG, FONT, TEXT = 0x2800, 0x2000, 0x2C00
TUNE_TICK = 0x10C6                 # test tune frame counters


@need_display
class DiskTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        make("disk")
        cls.sym = symbols("editor")
        cls.d64, cls.tmp = build_test_disk()
        cls.v = start_editor(cls.d64)

    @classmethod
    def tearDownClass(cls):
        cls.v.quit()
        cleanup(cls.tmp)

    def test_01_catalog_lists(self):
        v = self.v
        self.assertEqual(status_line(v), "")
        v.key("1")
        lines = v.screen_text(8)
        self.assertEqual([l.strip() for l in lines[4:7]], ["NO MUSIC", "TEST TUNE", "PSID TUNE"])
        v.key("Escape")
        v.key("2")
        lines = v.screen_text(8)
        self.assertEqual([l.strip() for l in lines[4:7]], ["ROM", "ROM BOLD", "ITALIC ROM"])
        v.key("Escape")
        self.assertTrue(at_menu(v))

    def test_02_load_music(self):
        v = self.v
        v.key("1")
        v.key("Down")
        v.key("Down")                       # PSID TUNE
        v.key("Return")
        self.assertTrue(wait_menu(v))
        self.assertEqual(v.screen_text(3)[2], "1 MUSIC:  PSID TUNE")
        self.assertEqual(v.peek(self.sym["ed_music_on"])[0], 1)
        self.assertEqual(v.peek(CONFIG + 3)[0] & 1, 1)
        self.assertEqual(v.peek(CONFIG + 0x0A, 5), [0x00, 0x10, 0x03, 0x10, 0])
        a = v.peek(TUNE_TICK + 3)[0]
        time.sleep(0.5)
        self.assertNotEqual(v.peek(TUNE_TICK + 3)[0], a, "music does not play in the menu")

    def test_03_load_font(self):
        v = self.v
        v.key("2")
        v.key("Down")
        v.key("Down")
        v.key("Return")
        self.assertTrue(wait_menu(v))
        self.assertEqual(v.screen_text(4)[3], "2 FONT:   ITALIC ROM")
        expected = (self.tmp / "italic.64c").read_bytes()[2:]
        self.assertEqual(v.peek(FONT, 512), list(expected))

    def test_04_save(self):
        v = self.v
        v.key("5")
        v.type("SAVED INTRO")
        v.key("Escape")
        v.key("6")
        v.type("HELLO FROM DISK ")
        v.key("F5")
        v.key("Escape")
        v.key("8")
        v.type("MYINTRO")
        v.key("Return")
        self.assertTrue(wait_menu(v))
        self.assertEqual(status_line(v), "00, OK,00,00")
        self.assertEqual(v.peek16(0x0811), self.sym["editor_start"], "entry operand not restored")
        self.assertEqual(v.peek(self.sym["rt_preview"])[0], 0)
        type(self).saved = {
            "config": v.peek(CONFIG, 0x60), "font": v.peek(FONT, 512),
            "text": v.peek(TEXT, 18), "sid": v.peek(0x1000, 0xC6)}

    def test_05_save_existing_name(self):
        v = self.v
        v.key("8")
        v.type("MYINTRO")
        v.key("Return")
        self.assertTrue(wait_menu(v))
        self.assertEqual(status_line(v), "63, FILE EXISTS,00,00")

    def test_06_save_cancel(self):
        v = self.v
        v.key("8")
        v.type("X")
        v.key("Escape")
        self.assertTrue(at_menu(v))

    def test_07_load_error(self):
        v = self.v
        v.poke(0x6002 + 21, 0x58, 0x58)    # break the name of catalog record 0
        v.key("1")
        v.key("Down")
        v.key("Return")
        self.assertTrue(wait_menu(v))
        self.assertEqual(status_line(v), "LOAD ERROR 62, FILE NOT FOUND,00,00")
        self.assertEqual(v.screen_text(3)[2], "1 MUSIC:  NO MUSIC")

    def test_08_saved_intro_in_fresh_vice(self):
        """LOAD"MYINTRO",8 / RUN shows the same intro as the preview."""
        saved = type(self).saved
        self.v.quit()                       # detach the image (flush writes)
        f = Vice(["-8", str(self.d64), "-keybuf", 'load"myintro",8\\nrun\\n'])
        try:
            self.assertTrue(f.wait_until(lambda: f.peek(0x01)[0] == 0x35, timeout=90))
            time.sleep(2)
            OUT.mkdir(parents=True, exist_ok=True)
            f.screenshot(OUT / "fresh_intro.png")
            self.assertEqual(f.peek16(0x0811), self.sym["runtime_start"])
            self.assertEqual(f.peek(CONFIG, 0x60), saved["config"])
            self.assertEqual(f.peek(FONT, 512), saved["font"])
            self.assertEqual(f.peek(TEXT, 18), saved["text"])
            self.assertEqual(f.peek(0x0400 + 40, 11), saved["config"][0x10:0x10 + 11])
            self.assertEqual(f.peek(0x3FFF)[0], 0)
            a = f.peek(TUNE_TICK + 3)[0]
            time.sleep(0.5)
            self.assertNotEqual(f.peek(TUNE_TICK + 3)[0], a, "music does not play")
            f.key("space", hold=0.2, after=3)
            self.assertIn("READY.", f.screen_text(8))
        finally:
            f.quit()


@need_display
class CatalogMissingTests(unittest.TestCase):
    def test_catalog_missing(self):
        make("disk")
        _, tmp = build_test_disk()
        try:
            d64 = tmp / "nocat.d64"
            subprocess.run(["c1541", "-format", "nocat,nc", "d64", str(d64), "-write",
                            str(BUILD / "editor.exo.prg"), "intro maker"],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            v = start_editor(d64)
            try:
                self.assertEqual(status_line(v), "CATALOG MISSING")
                v.key("1")
                self.assertEqual([l.strip() for l in v.screen_text(6)[4:6]], ["NO MUSIC", ""])
                v.key("Escape")
            finally:
                v.quit()
        finally:
            cleanup(tmp)


if __name__ == "__main__":
    unittest.main()
