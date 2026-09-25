"""Unit tests for check_sid.py (generate their own test data)."""
import struct
import unittest

import build_disk as bd
import check_sid as cs

LOAD = 0x1000


def psid(payload: bytes, init_off: int = 0, play_off: int | None = None) -> bytes:
    """PSID around a hand written player at $1000."""
    play = LOAD + (play_off if play_off is not None else len(payload) - 1)
    header = b"PSID" + struct.pack(">HHHHHHHI", 2, 0x7C, LOAD, LOAD + init_off,
                                   play, 1, 1, 0)
    return header.ljust(0x7C, b"\x00") + payload


def report(payload: bytes, **kw) -> cs.Report:
    return cs.trace(bd.sid_from_psid(psid(payload, **kw)))


# A player that only touches the SID and then returns.
CLEAN = bytes([0xA9, 0x0F,              # LDA #$0f
               0x8D, 0x18, 0xD4,        # STA $d418
               0x60,                    # RTS
               0xAD, 0x00, 0xD4,        # LDA $d400
               0x8D, 0x01, 0xD4,        # STA $d401
               0x60])                   # RTS


class CleanTests(unittest.TestCase):
    def test_sid_writes_are_fine(self):
        rep = report(CLEAN, play_off=6)
        self.assertTrue(rep.clean)
        self.assertEqual(rep.lines(), [])

    def test_sid_mirrors_are_fine(self):
        # STA $d520,X - still the SID, mirrored every 32 bytes up to $d7ff
        rep = report(bytes([0x9D, 0x20, 0xD5, 0x60]), play_off=3)
        self.assertTrue(rep.clean)

    def test_self_modification_inside_the_window_is_fine(self):
        rep = report(bytes([0x8D, 0x50, 0x1F, 0x60]), play_off=3)
        self.assertTrue(rep.clean)

    def test_coverage_counts_the_traced_bytes(self):
        rep = report(CLEAN, play_off=6)
        self.assertEqual(rep.coverage, len(CLEAN))

    def test_play_is_traced_as_well_as_init(self):
        # init returns at once, the offending write sits in play only
        payload = bytes([0x60,                      # $1000 RTS (init)
                         0x8D, 0x20, 0xD0,          # $1001 STA $d020
                         0x60])
        rep = report(payload, init_off=0, play_off=1)
        self.assertIn("VIC $d000-$d3ff", rep.writes)


class ConflictTests(unittest.TestCase):
    def test_font_write(self):
        rep = report(bytes([0x8D, 0x00, 0x20, 0x60]), play_off=3)
        self.assertFalse(rep.clean)
        self.assertEqual(rep.writes["font $2000-$27ff"], [0x2000])

    def test_scroll_text_write(self):
        rep = report(bytes([0x8D, 0x00, 0x30, 0x60]), play_off=3)
        self.assertIn("scroll text $2c00-$3fff", rep.writes)

    def test_runtime_code_write(self):
        rep = report(bytes([0x8D, 0x00, 0x09, 0x60]), play_off=3)
        self.assertIn("runtime code $0801-$0fbf", rep.writes)

    def test_runtime_zero_page_write(self):
        rep = report(bytes([0x85, 0x05, 0x60]), play_off=2)
        self.assertFalse(rep.clean)
        self.assertEqual(rep.zp_runtime, [0x05])

    def test_editor_zero_page_is_reported_but_not_fatal(self):
        rep = report(bytes([0x85, 0x25, 0x60]), play_off=2)
        self.assertTrue(rep.clean)           # runtime is what matters
        self.assertEqual(rep.zp_editor, [0x25])
        self.assertTrue(any("editor zero page" in line for line in rep.lines()))

    def test_cia_write(self):
        rep = report(bytes([0x8D, 0x04, 0xDC, 0x60]), play_off=3)
        self.assertIn("CIA 1 $dc00-$dcff", rep.writes)

    def test_indexed_write_may_leave_the_window(self):
        # STA $1f80,X reaches up to $207f
        rep = report(bytes([0x9D, 0x80, 0x1F, 0x60]), play_off=3)
        self.assertEqual(rep.overruns, [0x1F80])

    def test_indirect_writes_are_counted(self):
        rep = report(bytes([0x91, 0xFB, 0x60]), play_off=2)
        self.assertEqual(rep.indirect, 1)
        self.assertTrue(any("indirect" in line for line in rep.lines()))


class ReferenceTests(unittest.TestCase):
    """Reads and jumps leaving the window - the sidreloc leftovers."""

    def test_jump_outside_the_tune(self):
        rep = report(bytes([0x4C, 0x57, 0x31]), play_off=0)   # JMP $3157
        self.assertFalse(rep.clean)
        self.assertEqual(rep.jumps, [0x3157])
        self.assertTrue(any("jumps outside" in line for line in rep.lines()))

    def test_jsr_outside_the_tune(self):
        rep = report(bytes([0x20, 0x00, 0x39, 0x60]), play_off=3)
        self.assertEqual(rep.jumps, [0x3900])

    def test_jump_inside_the_tune_is_fine(self):
        rep = report(bytes([0x4C, 0x03, 0x10, 0x60]), play_off=3)
        self.assertTrue(rep.clean)
        self.assertEqual(rep.jumps, [])

    def test_read_outside_the_tune(self):
        rep = report(bytes([0xAD, 0x36, 0x39, 0x60]), play_off=3)  # LDA $3936
        self.assertFalse(rep.clean)
        self.assertEqual(rep.reads, [0x3936])

    def test_indexed_read_outside_the_tune(self):
        rep = report(bytes([0xBD, 0x00, 0x36, 0x60]), play_off=3)  # LDA $3600,X
        self.assertEqual(rep.reads, [0x3600])

    def test_read_inside_the_tune_is_fine(self):
        rep = report(bytes([0xAD, 0x00, 0x10, 0x60]), play_off=3)
        self.assertTrue(rep.clean)
        self.assertEqual(rep.reads, [])

    def test_sid_read_is_fine(self):
        rep = report(bytes([0xAD, 0x1B, 0xD4, 0x60]), play_off=3)  # LDA $d41b
        self.assertTrue(rep.clean)
        self.assertEqual(rep.reads, [])
        self.assertEqual(rep.reads_io, [])

    def test_io_read_is_reported_but_not_fatal(self):
        rep = report(bytes([0xAD, 0x12, 0xD0, 0x60]), play_off=3)  # LDA $d012
        self.assertTrue(rep.clean)
        self.assertEqual(rep.reads_io, [0xD012])
        self.assertTrue(any("reads I/O" in line for line in rep.lines()))

    def test_read_modify_write_counts_as_a_write(self):
        rep = report(bytes([0xEE, 0x24, 0x39, 0x60]), play_off=3)  # INC $3924
        self.assertIn("scroll text $2c00-$3fff", rep.writes)
        self.assertEqual(rep.reads, [])


class TraceTests(unittest.TestCase):
    def test_follows_jsr(self):
        payload = bytes([0x20, 0x06, 0x10,          # $1000 JSR $1006
                         0x60,                      # $1003 RTS
                         0xEA, 0xEA,                # padding
                         0x8D, 0x00, 0x20,          # $1006 STA $2000
                         0x60])
        rep = report(payload, play_off=3)
        self.assertIn("font $2000-$27ff", rep.writes)

    def test_follows_branch(self):
        payload = bytes([0xD0, 0x01,                # $1000 BNE $1003
                         0x60,                      # $1002 RTS
                         0x8D, 0x00, 0x20,          # $1003 STA $2000
                         0x60])
        rep = report(payload, play_off=6)
        self.assertIn("font $2000-$27ff", rep.writes)

    def test_stops_at_data(self):
        # $ff is not a documented opcode: the walk must stop instead of
        # inventing writes from what is really music data
        payload = bytes([0x60, 0xFF, 0x8D, 0x00, 0x20])
        rep = report(payload, play_off=0)
        self.assertTrue(rep.clean)
        self.assertEqual(rep.coverage, 1)


class HeaderTests(unittest.TestCase):
    def test_rejects_rsid(self):
        data = bytearray(psid(CLEAN, play_off=6))
        data[0:4] = b"RSID"
        with self.assertRaises(bd.BuildError):
            cs.trace(bd.sid_from_psid(bytes(data)))

    def test_rejects_wrong_load_address(self):
        header = b"PSID" + struct.pack(">HHHHHHHI", 2, 0x7C, 0x2000, 0x2000,
                                       0x2003, 1, 1, 0)
        with self.assertRaises(bd.BuildError):
            cs.trace(bd.sid_from_psid(header.ljust(0x7C, b"\x00") + CLEAN))


if __name__ == "__main__":
    unittest.main()
