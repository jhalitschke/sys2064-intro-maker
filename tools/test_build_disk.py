"""Unit tests for build_disk.py (generate their own test data)."""
import shutil
import struct
import tempfile
import unittest
from pathlib import Path

import build_disk as bd


def make_psid(payload=b"\x60" * 16, load=0x1000, init=0x1000, play=0x1003,
              songs=1, start=1, speed=0, magic=b"PSID", embed_load=False):
    header = magic + struct.pack(">HHHHHHHI", 2, 0x7C, 0 if embed_load else load,
                                 init, play, songs, start, speed)
    header += b"\x00" * (0x7C - len(header))
    body = (struct.pack("<H", load) if embed_load else b"") + payload
    return header + body


class PsidTests(unittest.TestCase):
    def test_parse_header(self):
        h = bd.parse_psid(make_psid(songs=3, start=2))
        self.assertEqual(h["magic"], b"PSID")
        self.assertEqual(h["load"], 0x1000)
        self.assertEqual(h["play"], 0x1003)
        self.assertEqual(h["songs"], 3)
        self.assertEqual(h["start_song"], 2)

    def test_basic(self):
        s = bd.sid_from_psid(make_psid())
        self.assertEqual((s.load, s.init, s.play, s.subtune), (0x1000, 0x1000, 0x1003, 0))
        self.assertEqual(len(s.payload), 16)

    def test_load_zero_uses_embedded_address(self):
        s = bd.sid_from_psid(make_psid(embed_load=True))
        self.assertEqual(s.load, 0x1000)
        self.assertEqual(len(s.payload), 16)

    def test_init_zero_means_load(self):
        s = bd.sid_from_psid(make_psid(init=0))
        self.assertEqual(s.init, 0x1000)

    def test_subtune_default_is_startsong_minus_one(self):
        self.assertEqual(bd.sid_from_psid(make_psid(songs=4, start=3)).subtune, 2)
        self.assertEqual(bd.sid_from_psid(make_psid(songs=4, start=3), subtune=1).subtune, 1)

    def test_rejects_rsid(self):
        with self.assertRaisesRegex(bd.BuildError, "RSID"):
            bd.sid_from_psid(make_psid(magic=b"RSID"))

    def test_rejects_play_zero(self):
        with self.assertRaisesRegex(bd.BuildError, "play = 0"):
            bd.sid_from_psid(make_psid(play=0))

    def test_rejects_speed_bit(self):
        with self.assertRaisesRegex(bd.BuildError, "Speed"):
            bd.sid_from_psid(make_psid(speed=1))
        # speed bit of another subtune is fine
        bd.sid_from_psid(make_psid(songs=2, start=1, speed=2))

    def test_rejects_wrong_load_address_with_sidreloc_hint(self):
        with self.assertRaisesRegex(bd.BuildError, "sidreloc"):
            bd.sid_from_psid(make_psid(load=0x0c00, init=0x0c00, play=0x0c03))

    def test_rejects_data_beyond_1fff(self):
        with self.assertRaisesRegex(bd.BuildError, "ausserhalb"):
            bd.sid_from_psid(make_psid(payload=b"\x60" * 0x1001))

    def test_accepts_exactly_4k(self):
        bd.sid_from_psid(make_psid(payload=b"\x60" * 0x1000))

    def test_rejects_init_or_play_outside_data(self):
        with self.assertRaisesRegex(bd.BuildError, "init"):
            bd.sid_from_psid(make_psid(init=0x1800))
        with self.assertRaisesRegex(bd.BuildError, "play"):
            bd.sid_from_psid(make_psid(play=0x1010))

    def test_rejects_bad_subtune(self):
        with self.assertRaises(bd.BuildError):
            bd.sid_from_psid(make_psid(songs=2), subtune=2)

    def test_prg_sid(self):
        s = bd.sid_from_prg(b"\x00\x10" + b"\x60" * 8, 0x1000, 0x1003)
        self.assertEqual((s.load, s.init, s.play), (0x1000, 0x1000, 0x1003))
        with self.assertRaisesRegex(bd.BuildError, "init und play"):
            bd.sid_from_prg(b"\x00\x10\x60", None, 0x1003)
        with self.assertRaisesRegex(bd.BuildError, "sidreloc"):
            bd.sid_from_prg(b"\x00\x20\x60", 0x2000, 0x2000)


class FontTests(unittest.TestCase):
    def test_64c_strips_load_address(self):
        data = b"\x00\x38" + bytes(range(256)) * 4
        f = bd.font_from_file(data, ".64c")
        self.assertEqual(len(f), 512)
        self.assertEqual(f[:3], b"\x00\x01\x02")

    def test_bin(self):
        self.assertEqual(len(bd.font_from_file(bytes(2048), ".bin")), 512)

    def test_too_short(self):
        with self.assertRaises(bd.BuildError):
            bd.font_from_file(bytes(511), ".bin")
        with self.assertRaises(bd.BuildError):
            bd.font_from_file(bytes(513), ".64c")


class NameTests(unittest.TestCase):
    def test_screencodes(self):
        sc = bd.name_to_screencodes("Ab 1.(Z)")
        self.assertEqual(len(sc), 20)
        self.assertEqual(sc[:8], bytes([1, 2, 0x20, 0x31, 0x2E, 0x28, 26, 0x29]))
        self.assertEqual(sc[8:], b"\x20" * 12)

    def test_all_allowed_punctuation(self):
        bd.name_to_screencodes(".,!?-:/()")

    def test_rejects_invalid(self):
        for bad in ("", "X" * 21, "UMLAUT Ä", "A_B", "A@B"):
            with self.assertRaises(bd.BuildError, msg=bad):
                bd.name_to_screencodes(bad)


class FilenameTests(unittest.TestCase):
    def test_catalog_uses_upper_petscii(self):
        self.assertEqual(bd.catalog_filename("tune-test"), b"TUNE-TEST")
        self.assertTrue(all(0x41 <= b <= 0x5A for b in bd.catalog_filename("abc")))

    def test_c1541_gets_lower_case(self):
        self.assertEqual(bd.c1541_filename("tune-test"), "tune-test")

    def test_rejects_invalid(self):
        for bad in ("Tune", "a b", "x" * 17, "", "a_b"):
            with self.assertRaises(bd.BuildError, msg=bad):
                bd.validate_file(bad)


class CatalogTests(unittest.TestCase):
    def entry(self, kind, name, file, init=0, play=0, subtune=0):
        return bd.Entry(kind, name, file, b"", "me", "mine", init, play, subtune)

    def test_layout(self):
        sids = [self.entry("sid", "Tune", "tune-a", 0x1000, 0x1003, 2)]
        fonts = [self.entry("font", "Font", "font-b"), self.entry("font", "F2", "c")]
        cat = bd.build_catalog(sids, fonts)
        self.assertEqual(cat[:2], b"\x00\x60")
        body = cat[2:]
        self.assertEqual(body[0], 1)
        self.assertEqual(body[1], 2)
        self.assertEqual(len(body), 2 + 3 * 48)
        rec = body[2:50]
        self.assertEqual(rec[0:20], bd.name_to_screencodes("TUNE"))
        self.assertEqual(rec[20], 6)
        self.assertEqual(rec[21:37], b"TUNE-A" + bytes(10))
        self.assertEqual(rec[37:42], bytes([0x00, 0x10, 0x03, 0x10, 2]))
        self.assertEqual(rec[42:48], bytes(6))
        font = body[50:98]
        self.assertEqual(font[20], 6)
        self.assertEqual(font[21:27], b"FONT-B")
        self.assertEqual(font[37:48], bytes(11))
        self.assertEqual(body[98 + 20], 1)

    def test_limits(self):
        with self.assertRaises(bd.BuildError):
            bd.build_catalog([self.entry("sid", "S", f"s{i}") for i in range(16)], [])
        with self.assertRaises(bd.BuildError):
            bd.build_catalog([], [self.entry("font", "F", f"f{i}") for i in range(15)])


class ManifestTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def test_license_is_mandatory(self):
        (self.tmp / "t.prg").write_bytes(b"\x00\x10\x60\x60\x60\x60")
        manifest = {"sid": [{"name": "T", "file": "t", "src": "t.prg",
                             "init": 0x1000, "play": 0x1003}]}
        with self.assertRaisesRegex(bd.BuildError, "license"):
            bd.load_entries(manifest, self.tmp)
        manifest["sid"][0]["license"] = "own"
        sids, fonts = bd.load_entries(manifest, self.tmp)
        self.assertEqual(len(sids), 1)
        self.assertEqual(sids[0].prg[:2], b"\x00\x10")

    def test_duplicate_file(self):
        (self.tmp / "f.bin").write_bytes(bytes(512))
        f = {"name": "F", "file": "f", "src": "f.bin", "license": "x"}
        with self.assertRaisesRegex(bd.BuildError, "doppelt"):
            bd.load_entries({"font": [f, dict(f)]}, self.tmp)

    def test_font_prg_has_load_address_2000(self):
        (self.tmp / "f.64c").write_bytes(b"\x00\x30" + bytes(600))
        _, fonts = bd.load_entries(
            {"font": [{"name": "F", "file": "f", "src": "f.64c", "license": "x"}]}, self.tmp)
        self.assertEqual(fonts[0].prg[:2], b"\x00\x20")
        self.assertEqual(len(fonts[0].prg), 514)


class D64Tests(unittest.TestCase):
    def test_directory_reader(self):
        image = bytearray(174848)
        off = bd._d64_offset(18, 1)
        self.assertEqual(off, 0x16600)
        entry = bytearray(32)
        entry[2] = 0x82
        entry[5:21] = b"CATALOG".ljust(16, b"\xa0")
        image[off:off + 32] = entry
        self.assertEqual(bd.read_d64_directory(bytes(image)), [(b"CATALOG", 0x82)])


if __name__ == "__main__":
    unittest.main()
