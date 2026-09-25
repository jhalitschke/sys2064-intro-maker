#!/usr/bin/env python3
"""Check a tune for memory accesses outside the SID window.

build_disk.py validates the PSID header: load address, size, play address and
the speed bit. It cannot see what the player does once it runs. A tune that
fits $1000-$1FFF may still write over the runtime zero page, the font, the
runtime tables or the scroll text, and the damage only shows as a crash or a
corrupted intro.

This tool disassembles the player from its init and play entry points and
reports every access that leaves the window: writes, reads, and JMP/JSR
targets. The last two matter for a tune that was moved with sidreloc, which
can leave absolute references pointing at the old address range - a tune that
writes nothing out of bounds can still jump straight into the scroll text.

It is a static analysis. Indirect writes ((zp),Y), computed jumps and code
that is reached only through a self-modified address cannot be resolved, so a
clean result is strong evidence, not a proof - listening in the editor stays
the final test. The reported code coverage says how much of the tune was
actually walked; a very low value means the verdict is worth little.

Only the Python standard library is used.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import build_disk as bd

# ---------------------------------------------------------------------------
# Memory layout (mirrors src/shared/memmap.asm)
# ---------------------------------------------------------------------------

ZP_RT_START, ZP_RT_END = 0x02, 0x20     # runtime zero page (exclusive end)
ZP_ED_START, ZP_ED_END = 0x20, 0x40     # editor zero page (exclusive end)

# SID registers are mirrored every 32 bytes up to $d7ff; all of it is fine.
SID_IO_START, SID_IO_END = 0xD400, 0xD800

# Regions a tune must not write to, as (start, end exclusive, label).
FORBIDDEN = [
    (0x0000, 0x0002, "CPU port $00-$01"),
    (0x0400, 0x0800, "screen $0400-$07ff"),
    (0x0801, 0x0FC0, "runtime code $0801-$0fbf"),
    (0x0FC0, 0x1000, "sprite data $0fc0-$0fff"),
    (0x2000, 0x2800, "font $2000-$27ff"),
    (0x2800, 0x2900, "config / runtime work $2800-$28ff"),
    (0x2900, 0x2C00, "runtime tables $2900-$2bff"),
    (0x2C00, 0x4000, "scroll text $2c00-$3fff"),
    (0xD000, 0xD400, "VIC $d000-$d3ff"),
    (0xD800, 0xDC00, "colour RAM $d800-$dbff"),
    (0xDC00, 0xDD00, "CIA 1 $dc00-$dcff"),
    (0xDD00, 0xDE00, "CIA 2 $dd00-$ddff"),
    (0xE000, 0xE400, "runtime RAM under the KERNAL $e000-$e3ff"),
]

# ---------------------------------------------------------------------------
# 6502 instruction table
# ---------------------------------------------------------------------------

IMP, IMM, ZP, ZPX, ZPY, ABS, ABX, ABY, IND, IZX, IZY, REL, ACC = range(13)
SIZE = {IMP: 1, ACC: 1, IMM: 2, ZP: 2, ZPX: 2, ZPY: 2, IZX: 2, IZY: 2, REL: 2,
        ABS: 3, ABX: 3, ABY: 3, IND: 3}

_TABLE = [
    (0x00, "BRK", IMP), (0x01, "ORA", IZX), (0x05, "ORA", ZP), (0x06, "ASL", ZP),
    (0x08, "PHP", IMP), (0x09, "ORA", IMM), (0x0A, "ASL", ACC), (0x0D, "ORA", ABS),
    (0x0E, "ASL", ABS), (0x10, "BPL", REL), (0x11, "ORA", IZY), (0x15, "ORA", ZPX),
    (0x16, "ASL", ZPX), (0x18, "CLC", IMP), (0x19, "ORA", ABY), (0x1D, "ORA", ABX),
    (0x1E, "ASL", ABX), (0x20, "JSR", ABS), (0x21, "AND", IZX), (0x24, "BIT", ZP),
    (0x25, "AND", ZP), (0x26, "ROL", ZP), (0x28, "PLP", IMP), (0x29, "AND", IMM),
    (0x2A, "ROL", ACC), (0x2C, "BIT", ABS), (0x2D, "AND", ABS), (0x2E, "ROL", ABS),
    (0x30, "BMI", REL), (0x31, "AND", IZY), (0x35, "AND", ZPX), (0x36, "ROL", ZPX),
    (0x38, "SEC", IMP), (0x39, "AND", ABY), (0x3D, "AND", ABX), (0x3E, "ROL", ABX),
    (0x40, "RTI", IMP), (0x41, "EOR", IZX), (0x45, "EOR", ZP), (0x46, "LSR", ZP),
    (0x48, "PHA", IMP), (0x49, "EOR", IMM), (0x4A, "LSR", ACC), (0x4C, "JMP", ABS),
    (0x4D, "EOR", ABS), (0x4E, "LSR", ABS), (0x50, "BVC", REL), (0x51, "EOR", IZY),
    (0x55, "EOR", ZPX), (0x56, "LSR", ZPX), (0x58, "CLI", IMP), (0x59, "EOR", ABY),
    (0x5D, "EOR", ABX), (0x5E, "LSR", ABX), (0x60, "RTS", IMP), (0x61, "ADC", IZX),
    (0x65, "ADC", ZP), (0x66, "ROR", ZP), (0x68, "PLA", IMP), (0x69, "ADC", IMM),
    (0x6A, "ROR", ACC), (0x6C, "JMP", IND), (0x6D, "ADC", ABS), (0x6E, "ROR", ABS),
    (0x70, "BVS", REL), (0x71, "ADC", IZY), (0x75, "ADC", ZPX), (0x76, "ROR", ZPX),
    (0x78, "SEI", IMP), (0x79, "ADC", ABY), (0x7D, "ADC", ABX), (0x7E, "ROR", ABX),
    (0x81, "STA", IZX), (0x84, "STY", ZP), (0x85, "STA", ZP), (0x86, "STX", ZP),
    (0x88, "DEY", IMP), (0x8A, "TXA", IMP), (0x8C, "STY", ABS), (0x8D, "STA", ABS),
    (0x8E, "STX", ABS), (0x90, "BCC", REL), (0x91, "STA", IZY), (0x94, "STY", ZPX),
    (0x95, "STA", ZPX), (0x96, "STX", ZPY), (0x98, "TYA", IMP), (0x99, "STA", ABY),
    (0x9A, "TXS", IMP), (0x9D, "STA", ABX), (0xA0, "LDY", IMM), (0xA1, "LDA", IZX),
    (0xA2, "LDX", IMM), (0xA4, "LDY", ZP), (0xA5, "LDA", ZP), (0xA6, "LDX", ZP),
    (0xA8, "TAY", IMP), (0xA9, "LDA", IMM), (0xAA, "TAX", IMP), (0xAC, "LDY", ABS),
    (0xAD, "LDA", ABS), (0xAE, "LDX", ABS), (0xB0, "BCS", REL), (0xB1, "LDA", IZY),
    (0xB4, "LDY", ZPX), (0xB5, "LDA", ZPX), (0xB6, "LDX", ZPY), (0xB8, "CLV", IMP),
    (0xB9, "LDA", ABY), (0xBA, "TSX", IMP), (0xBC, "LDY", ABX), (0xBD, "LDA", ABX),
    (0xBE, "LDX", ABY), (0xC0, "CPY", IMM), (0xC1, "CMP", IZX), (0xC4, "CPY", ZP),
    (0xC5, "CMP", ZP), (0xC6, "DEC", ZP), (0xC8, "INY", IMP), (0xC9, "CMP", IMM),
    (0xCA, "DEX", IMP), (0xCC, "CPY", ABS), (0xCD, "CMP", ABS), (0xCE, "DEC", ABS),
    (0xD0, "BNE", REL), (0xD1, "CMP", IZY), (0xD5, "CMP", ZPX), (0xD6, "DEC", ZPX),
    (0xD8, "CLD", IMP), (0xD9, "CMP", ABY), (0xDD, "CMP", ABX), (0xDE, "DEC", ABX),
    (0xE0, "CPX", IMM), (0xE1, "SBC", IZX), (0xE4, "CPX", ZP), (0xE5, "SBC", ZP),
    (0xE6, "INC", ZP), (0xE8, "INX", IMP), (0xE9, "SBC", IMM), (0xEA, "NOP", IMP),
    (0xEC, "CPX", ABS), (0xED, "SBC", ABS), (0xEE, "INC", ABS), (0xF0, "BEQ", REL),
    (0xF1, "SBC", IZY), (0xF5, "SBC", ZPX), (0xF6, "INC", ZPX), (0xF8, "SED", IMP),
    (0xF9, "SBC", ABY), (0xFD, "SBC", ABX), (0xFE, "INC", ABX),
]
OPS = {op: (mn, mode) for op, mn, mode in _TABLE}

# Writes to an absolute address. The value says how far an index register can
# push the effective address beyond the base.
WRITE_ABS = {0x8D: 0, 0x8E: 0, 0x8C: 0, 0xEE: 0, 0xCE: 0, 0x0E: 0, 0x4E: 0,
             0x2E: 0, 0x6E: 0,
             0x9D: 0xFF, 0x99: 0xFF, 0xFE: 0xFF, 0xDE: 0xFF, 0x1E: 0xFF,
             0x5E: 0xFF, 0x3E: 0xFF, 0x7E: 0xFF}
WRITE_ZP = {0x85, 0x95, 0x86, 0x96, 0x84, 0x94, 0xE6, 0xF6, 0xC6, 0xD6,
            0x06, 0x16, 0x46, 0x56, 0x26, 0x36, 0x66, 0x76}
WRITE_IND = {0x81, 0x91}

# Reads from an absolute address. Read-modify-write instructions are already
# in WRITE_ABS and the write is what matters, so they are left out here.
READ_MNEMONICS = {"LDA", "LDX", "LDY", "CMP", "CPX", "CPY",
                  "ADC", "SBC", "AND", "ORA", "EOR", "BIT"}
READ_ABS = {op for op, (mn, mode) in OPS.items()
            if mn in READ_MNEMONICS and mode in (ABS, ABX, ABY)}


class Report:
    """Result of one check."""

    def __init__(self, asset: bd.SidAsset):
        self.asset = asset
        self.writes: dict[str, list[int]] = {}   # label -> absolute addresses
        self.jumps: list[int] = []               # JMP/JSR targets outside the tune
        self.reads: list[int] = []               # RAM reads from outside the tune
        self.reads_io: list[int] = []            # reads from VIC/CIA/colour RAM
        self.zp_cpu: list[int] = []              # $00/$01: memory configuration
        self.zp_runtime: list[int] = []
        self.zp_editor: list[int] = []
        self.overruns: list[int] = []            # indexed writes reaching past $1fff
        self.indirect = 0
        self.coverage = 0

    @property
    def clean(self) -> bool:
        return not (self.writes or self.zp_cpu or self.zp_runtime or self.jumps
                    or self.reads)

    def lines(self) -> list[str]:
        out = []
        if self.jumps:
            out.append("jumps outside the tune: "
                       + " ".join(f"${a:04x}" for a in self.jumps))
        for label, addrs in sorted(self.writes.items()):
            span = (f"${addrs[0]:04x}" if len(addrs) == 1
                    else f"${min(addrs):04x}-${max(addrs):04x} ({len(addrs)} addresses)")
            out.append(f"writes {label}: {span}")
        if self.reads:
            out.append("reads RAM outside the tune: "
                       + " ".join(f"${a:04x}" for a in self.reads))
        if self.reads_io:
            out.append("reads I/O (usually harmless): "
                       + " ".join(f"${a:04x}" for a in self.reads_io))
        if self.zp_cpu:
            out.append("writes the CPU port (banks I/O and RAM): "
                       + " ".join(f"${z:02x}" for z in self.zp_cpu))
        if self.zp_runtime:
            out.append("writes runtime zero page: "
                       + " ".join(f"${z:02x}" for z in self.zp_runtime))
        if self.zp_editor:
            out.append("writes editor zero page (preview only): "
                       + " ".join(f"${z:02x}" for z in self.zp_editor))
        if self.overruns:
            out.append("indexed write may reach past $1fff: "
                       + " ".join(f"${a:04x},X/Y" for a in self.overruns))
        if self.indirect:
            out.append(f"{self.indirect} indirect (zp),Y write(s) - not resolvable statically")
        return out


def trace(asset: bd.SidAsset) -> Report:
    """Walk the player from init and play, collecting write targets."""
    rep = Report(asset)
    lo = asset.load
    hi = lo + len(asset.payload)
    mem = asset.payload
    seen: set[int] = set()
    abs_writes: set[tuple[int, bool]] = set()
    abs_reads: set[int] = set()
    jumps: set[int] = set()
    zp_writes: set[int] = set()

    def byte(addr: int) -> int | None:
        return mem[addr - lo] if lo <= addr < hi else None

    todo = [asset.init, asset.play]
    while todo:
        pc = todo.pop()
        while True:
            if not lo <= pc < hi or pc in seen:
                break
            op = byte(pc)
            if op not in OPS:
                break                       # illegal opcode: almost certainly data
            mnemonic, mode = OPS[op]
            size = SIZE[mode]
            if pc + size > hi:
                break
            seen.update(range(pc, pc + size))

            if op in WRITE_ABS:
                target = byte(pc + 1) | (byte(pc + 2) << 8)
                abs_writes.add((target, WRITE_ABS[op] != 0))
            elif op in READ_ABS:
                abs_reads.add(byte(pc + 1) | (byte(pc + 2) << 8))
            elif op in WRITE_ZP:
                zp_writes.add(byte(pc + 1))
            elif op in WRITE_IND:
                rep.indirect += 1

            if mode in (ABS, ABX, ABY, IND):
                target = byte(pc + 1) | (byte(pc + 2) << 8)
                if mnemonic in ("JSR", "JMP"):
                    # A relocated tune that still jumps into its old range runs
                    # straight into whatever the intro keeps there.
                    if not lo <= target < hi:
                        jumps.add(target)
                if mnemonic == "JSR":
                    todo.append(target)
                elif mnemonic == "JMP":
                    if mode == ABS:
                        todo.append(target)
                    break                   # indirect jump: cannot follow
            elif mode == REL:
                offset = (byte(pc + 1) ^ 0x80) - 0x80
                todo.append((pc + 2 + offset) & 0xFFFF)

            if mnemonic in ("RTS", "RTI", "BRK"):
                break
            pc += size

    rep.coverage = len(seen)
    for target, indexed in sorted(abs_writes):
        if SID_IO_START <= target < SID_IO_END:
            continue                        # SID registers and their mirrors
        if lo <= target < bd.SID_END:       # own window, including self-modification
            if indexed and target + 0xFF >= bd.SID_END:
                rep.overruns.append(target)
            continue
        for start, end, label in FORBIDDEN:
            if start <= target < end:
                rep.writes.setdefault(label, []).append(target)
                break
        else:
            rep.writes.setdefault("other RAM", []).append(target)

    for target in sorted(abs_reads):
        if SID_IO_START <= target < SID_IO_END:
            continue                        # SID, including the read-only registers
        if lo <= target < bd.SID_END:
            continue
        if 0xD000 <= target < 0xE000:
            rep.reads_io.append(target)     # raster or timer polling: not fatal
        else:
            rep.reads.append(target)

    rep.jumps = sorted(jumps)
    rep.zp_cpu = sorted(z for z in zp_writes if z < ZP_RT_START)
    rep.zp_runtime = sorted(z for z in zp_writes if ZP_RT_START <= z < ZP_RT_END)
    rep.zp_editor = sorted(z for z in zp_writes if ZP_ED_START <= z < ZP_ED_END)
    return rep


def check_file(path: Path, subtune: int | None = None) -> Report:
    """Parse a .sid and trace it. Raises bd.BuildError if the header is bad."""
    return trace(bd.sid_from_psid(path.read_bytes(), subtune))


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("sid", nargs="+", type=Path, help="PSID file(s) to check")
    ap.add_argument("--subtune", type=int, default=None)
    ap.add_argument("-q", "--quiet", action="store_true",
                    help="only report tunes that are not clean")
    args = ap.parse_args(argv)

    failed = 0
    for path in args.sid:
        try:
            rep = check_file(path, args.subtune)
        except bd.BuildError as exc:
            print(f"REJECTED {path}: {exc}")
            failed += 1
            continue
        if rep.clean and args.quiet:
            continue
        verdict = "OK      " if rep.clean else "CONFLICT"
        size = len(rep.asset.payload)
        print(f"{verdict} {size:5d} B  code {rep.coverage:5d} B  {path}")
        for line in rep.lines():
            print(f"         ! {line}")
        if not rep.clean:
            failed += 1
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
