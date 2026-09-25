"""Disk tests (M4/M5): catalog, loading, saving, and the saved intro in a
fresh VICE. Uses the packed editor and generated test assets."""
import subprocess
import time
import unittest

from helpers import (OUT, at_menu, build_test_disk, cleanup, dir_index, linked_programs,
                     make, need_display, select_entry, start_editor, status_line,
                     wait_menu)
from vice import BUILD, Vice, symbols

CONFIG, FONT, TEXT = 0x2800, 0x2000, 0x3000
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

    def tune_plays(self, v):
        a = v.peek(TUNE_TICK + 3)[0]
        time.sleep(0.5)
        return v.peek(TUNE_TICK + 3)[0] != a

    def test_02_load_music(self):
        """The music list stays open and plays the tune for auditioning;
        leaving it keeps the tune selected but silent."""
        v = self.v
        on = self.sym["ed_music_on"]
        v.key("1")
        select_entry(v, 2)                  # PSID TUNE
        v.key("Return")
        self.assertTrue(v.wait_until(lambda: v.peek(on)[0] == 1, timeout=60))
        self.assertEqual(v.screen_text(1)[0], "MUSIC")
        self.assertTrue(self.tune_plays(v), "music does not play in the list")
        v.key("Escape")
        self.assertTrue(at_menu(v))
        self.assertEqual(v.screen_text(3)[2], "1 MUSIC:  PSID TUNE")
        self.assertEqual(v.peek(on)[0], 0)
        self.assertFalse(self.tune_plays(v), "music plays in the menu")
        self.assertEqual(v.peek(CONFIG + 3)[0] & 1, 1)
        self.assertEqual(v.peek(CONFIG + 0x0A, 5), [0x00, 0x10, 0x03, 0x10, 0])

    def test_02b_music_in_preview_only(self):
        v = self.v
        v.key("9")
        time.sleep(1.5)
        self.assertEqual(v.peek(0x01)[0], 0x35)
        self.assertTrue(self.tune_plays(v), "music does not play in the preview")
        v.key("space", hold=0.2, after=0.8)
        self.assertTrue(at_menu(v))
        self.assertEqual(v.peek(self.sym["ed_music_on"])[0], 0)
        self.assertFalse(self.tune_plays(v), "music plays after the preview")

    def test_03_load_font(self):
        v = self.v
        v.key("2")
        select_entry(v, 2)                  # ITALIC ROM
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
        v.key("7")
        v.type("HELLO FROM DISK ")
        v.key("F5")
        v.key("Escape")
        v.key("0")
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
        v.key("0")
        v.type("MYINTRO")
        v.key("Return")
        self.assertTrue(wait_menu(v))
        self.assertEqual(status_line(v), "63, FILE EXISTS,00,00")

    def test_06_save_cancel(self):
        v = self.v
        v.key("0")
        v.type("X")
        v.key("Escape")
        self.assertTrue(at_menu(v))

    def test_07_load_error(self):
        v = self.v
        v.poke(0x6804 + 21, 0x58, 0x58)    # break the name of catalog record 0
        v.key("1")
        select_entry(v, 1)
        v.key("Return")
        self.assertTrue(v.wait_until(lambda: status_line(v) != "", timeout=60))
        self.assertEqual(status_line(v), "LOAD ERROR 62, FILE NOT FOUND,00,00")
        v.key("Escape")
        self.assertTrue(at_menu(v))
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


def pick_from_disk(test, v, menu_key, entries_before_disk, name, menu_first=None,
                   back_to=None):
    """Menu key (+ key inside, e.g. TITLE STYLE -> 1) -> FROM DISK... ->
    directory list -> file `name`. Waits for the screen `back_to` (e.g. the
    music list, which stays open) or the menu."""
    v.key(menu_key)
    if menu_first:
        v.key(menu_first)
    select_entry(v, entries_before_disk)
    v.key("Return")
    test.assertTrue(v.wait_until(
        lambda: v.screen_text(24)[23].startswith("CRSR SELECT"), timeout=60),
        "directory list did not appear")
    select_entry(v, dir_index(test.d64, name))
    v.key("Return")
    if menu_first:
        test.assertTrue(v.wait_until(lambda: v.screen_text(1)[0] != "DISK", timeout=60))
        return
    if back_to:
        test.assertTrue(v.wait_until(lambda: v.screen_text(1)[0] == back_to, timeout=60))
        return
    test.assertTrue(wait_menu(v))


@need_display
class DiskBrowserTests(unittest.TestCase):
    """SIDs and fonts loaded from any file on the disk (no catalog)."""
    MUSIC_BEFORE_DISK = 3           # NO MUSIC, TEST TUNE, PSID TUNE
    FONT_BEFORE_DISK = 3            # ROM, ROM BOLD, ITALIC ROM

    @classmethod
    def setUpClass(cls):
        make("disk")
        cls.d64, cls.tmp = build_test_disk()
        cls.v = start_editor(cls.d64)

    @classmethod
    def tearDownClass(cls):
        cls.v.quit()
        cleanup(cls.tmp)

    def music_name(self):
        return self.v.screen_text(3)[2][len("1 MUSIC:  "):]

    def tune_plays(self):
        a = self.v.peek(TUNE_TICK + 3)[0]
        time.sleep(0.5)
        return self.v.peek(TUNE_TICK + 3)[0] != a

    def test_01_scrolling_directory_list(self):
        v = self.v
        v.key("1")
        select_entry(v, self.MUSIC_BEFORE_DISK)
        self.assertEqual(v.screen_text(8)[7].strip(), "FROM DISK...")
        v.key("Return")
        self.assertTrue(v.wait_until(
            lambda: v.screen_text(24)[23].startswith("CRSR SELECT"), timeout=60))
        index = dir_index(self.d64, "raw-psid")
        self.assertGreater(index, 16, "test disk must need scrolling")
        select_entry(v, index)
        screen = v.peek(0x0400 + 4 * 40, 16 * 40)
        reversed_rows = [r for r in range(16) if screen[r * 40] & 0x80]
        self.assertEqual(reversed_rows, [15], "selection must stay in the window")
        self.assertEqual(v.screen_text(20)[19].strip(), "RAW-PSID")
        v.key("Escape")                     # back to the music list
        self.assertTrue(v.wait_until(lambda: v.screen_text(1)[0] == "MUSIC", timeout=20))
        v.key("Escape")
        self.assertTrue(at_menu(v))

    def pick_tune(self, name):
        """FROM DISK in the music list; back in the list (auditioning)."""
        pick_from_disk(self, self.v, "1", self.MUSIC_BEFORE_DISK, name, back_to="MUSIC")

    def leave_list(self):
        self.v.key("Escape")
        self.assertTrue(at_menu(self.v))
        self.assertFalse(self.tune_plays(), "music plays in the menu")

    def test_02_psid_from_disk(self):
        self.pick_tune("raw-psid")
        self.assertTrue(self.tune_plays())
        self.leave_list()
        self.assertEqual(self.music_name().strip(), "TEST AS PSID")
        self.assertEqual(self.v.peek(CONFIG + 0x0A, 5), [0x00, 0x10, 0x03, 0x10, 0])

    def test_03_prg_tune_from_disk(self):
        self.pick_tune("raw-tune")
        self.assertTrue(self.tune_plays())
        self.leave_list()
        self.assertEqual(self.music_name().strip(), "RAW-TUNE")

    def test_04_rejected_tunes_keep_the_old_one(self):
        for name, message in (("raw-rsid", "RSID TUNES ARE NOT SUPPORTED"),
                              ("raw-cia", "CIA TIMED TUNES ARE NOT SUPPORTED"),
                              ("raw-c000", "TUNE MUST LOAD AT $1000")):
            with self.subTest(name=name):
                self.pick_tune(name)
                self.assertEqual(status_line(self.v), message)   # shown in the list
                self.assertTrue(self.tune_plays(), "old tune not auditioned again")
                self.leave_list()
                self.assertEqual(self.music_name().strip(), "RAW-TUNE")

    def test_06_bigfont_from_catalog_and_disk(self):
        v = self.v
        expected = (self.tmp / "build" / "bigfonts" / "big-test.prg").read_bytes()
        v.key("6")
        v.key("1")
        self.assertEqual([l.strip() for l in v.screen_text(8)[4:8]],
                         ["NONE (1X1)", "ROM 2X2", "TEST BIG", "FROM DISK..."])
        select_entry(v, 2)
        v.key("Return")
        self.assertTrue(v.wait_until(lambda: v.screen_text(1)[0] == "TITLE STYLE", timeout=60))
        self.assertEqual(v.screen_text(3)[2], "1 BIG FONT      TEST BIG")
        n = expected[2 + 7]
        self.assertEqual(v.peek(CONFIG + 0x70, 64), list(expected[2 + 8:2 + 72]))
        self.assertEqual(v.peek(0x2200, n * 8), list(expected[2 + 72:2 + 72 + n * 8]))
        v.key("Escape")
        # the same file from the directory
        pick_from_disk(self, v, "6", 3, "raw-big", menu_first="1")
        self.assertTrue(v.wait_until(lambda: v.screen_text(1)[0] == "TITLE STYLE", timeout=60))
        self.assertEqual(v.screen_text(3)[2], "1 BIG FONT      RAW-BIG")
        v.key("Escape")
        # not a big font
        pick_from_disk(self, v, "6", 3, "raw-tune", menu_first="1")
        self.assertTrue(v.wait_until(lambda: v.screen_text(1)[0] == "TITLE STYLE", timeout=60))
        v.key("Escape")
        self.assertEqual(status_line(v), "NOT A BIG FONT FILE")

    def test_05_font_from_disk(self):
        v = self.v
        pick_from_disk(self, v, "2", self.FONT_BEFORE_DISK, "raw-font")
        self.assertEqual(v.screen_text(4)[3], "2 FONT:   RAW-FONT")
        expected = (self.tmp / "italic.64c").read_bytes()[2:514]
        self.assertEqual(v.peek(FONT, 512), list(expected))
        pick_from_disk(self, v, "2", self.FONT_BEFORE_DISK, "raw-short")
        self.assertEqual(status_line(v), "FONT TOO SHORT (512 BYTES NEEDED)")
        self.assertEqual(v.screen_text(4)[3], "2 FONT:   RAW-FONT")


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
                self.assertEqual([l.strip() for l in v.screen_text(6)[4:6]], ["NO MUSIC", "FROM DISK..."])
                v.key("Escape")
            finally:
                v.quit()
        finally:
            cleanup(tmp)


if __name__ == "__main__":
    unittest.main()


@need_display
class LinkTests(unittest.TestCase):
    """Intro linked in front of a program: RUN (BASIC) and SYS (ML), forward
    and overlapping backward moves."""
    CASES = {"link-basic": ("LKBASIC", 5), "link-ml5000": ("LKML5000", 7),
             "link-mlc000": ("LKMLC000", 2)}

    @classmethod
    def setUpClass(cls):
        make("disk")
        cls.d64, cls.tmp = build_test_disk()
        cls.programs = linked_programs()

    @classmethod
    def tearDownClass(cls):
        cleanup(cls.tmp)

    def link(self, v, name):
        v.key("8")
        v.key("1")
        self.assertTrue(v.wait_until(
            lambda: v.screen_text(24)[23].startswith("CRSR SELECT"), timeout=60))
        select_entry(v, dir_index(self.d64, name))
        v.key("Return")
        self.assertTrue(v.wait_until(
            lambda: v.screen_text(1)[0] == "LINK PROGRAM"
            and "MEASURING" not in v.screen_text(25)[24], timeout=120))

    def test_01_link_screen(self):
        v = start_editor(self.d64)
        try:
            self.link(v, "link-basic")
            lines = v.screen_text(10)
            self.assertEqual(lines[2], "1 PROGRAM       LINK-BASIC")
            self.assertEqual(lines[3], "2 START         RUN")
            length = len(self.programs["link-basic"]) - 2
            self.assertEqual(lines[7], f"LOADS TO $0801-${0x0801 + length - 1:04X}")
            v.key("2")
            self.assertEqual(v.screen_text(4)[3], "2 START         SYS $0801")
            v.key("3")
            v.type("C0A")
            v.key("BackSpace")
            v.type("12")
            v.key("Return")
            self.assertEqual(v.screen_text(4)[3], "2 START         SYS $C012")
            self.assertEqual(v.peek(CONFIG + 0x6C, 2), [0x12, 0xC0])
            v.key("2")
            self.assertEqual(v.screen_text(4)[3], "2 START         RUN")
            v.key("4")
            self.assertEqual(v.screen_text(3)[2], "1 PROGRAM       NONE")
            self.assertEqual(v.peek(CONFIG + 0x68, 2), [0, 0])
            v.key("Escape")
            self.assertTrue(at_menu(v))
        finally:
            v.quit()

    def test_02_save_and_start(self):
        v = start_editor(self.d64)
        try:
            v.key("7")
            v.type("LINK TEST ")
            v.key("Escape")
            for prog, (intro, _) in self.CASES.items():
                with self.subTest(save=prog):
                    self.link(v, prog)
                    v.key("Escape")
                    self.assertTrue(at_menu(v))
                    self.assertEqual(v.screen_text(10)[9].strip(), "8 LINK PROGRAM  " + prog.upper())
                    v.key("0")
                    v.type(intro)
                    v.key("Return")
                    self.assertTrue(wait_menu(v, timeout=300))
                    self.assertEqual(status_line(v), "00, OK,00,00")
        finally:
            v.quit()
        for prog, (intro, border) in self.CASES.items():
            with self.subTest(start=prog):
                data = self.programs[prog]
                load = data[0] | data[1] << 8
                f = Vice(["-8", str(self.d64), "-keybuf", f'load"{intro.lower()}",8\\nrun\\n'])
                try:
                    self.assertTrue(f.wait_until(lambda: f.peek(0x01)[0] == 0x35, timeout=120))
                    time.sleep(1)
                    f.key("space", hold=0.2, after=3)
                    self.assertEqual(f.peek(0xD020)[0] & 0x0F, border)
                    if load == 0x0801:
                        self.assertIn("LINKED OK", "\n".join(f.screen_text(10)))
                    body = list(data[2:])
                    for off in (0, len(body) // 2, len(body) - 64):
                        self.assertEqual(f.peek(load + off, 64), body[off:off + 64],
                                         f"{prog} data at +{off}")
                finally:
                    f.quit()
