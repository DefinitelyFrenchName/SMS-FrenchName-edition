#!/usr/bin/env python3
"""dis65816.py — the 65816 decode tables and recursive descent, shared.

  python3 tools/dis65816.py            # self-check the table, then a census

WHY THIS EXISTS. Two consumers need to know where an instruction STARTS:
`tools/saturn/port_saturn_proc.py`, which may only rewrite the operands of
instructions it has actually reached, and `tools/checkdocs.py`, which asks
whether a documented address is an instruction boundary at all. Both had been
answering it from a private table, and one of those tables was wrong — see
below. One table, validated against an independent disassembler, is the fix.

⚠ THE TABLE IS COMPLETE — all 256 opcodes. That is not tidiness. The table this
replaces was missing seven opcodes entirely (`02 08 0B 2B 42 C4 E4` = COP, PHP,
PHD, PLD, WDM, CPY dp, CPX dp), so a descent that met a `php` died with
`SystemExit: unknown opcode`, and it gave `00` (BRK) length 1 when BRK carries a
signature byte and is 2. A missing entry does not read as "I don't know" at the
call site — it reads as a stop, or as a wrong length that silently reframes
every instruction after it. There is no such thing as a partial length table.

The lengths are written as one 256-entry string, one row of 16 per line, so the
whole table can be read against a datasheet in one pass rather than reassembled
from set membership. `M` and `X` mark the immediates whose width follows the
processor flags (2 bytes when the flag is set, 3 when clear).

VALIDATION. `tools/dis65816_oracle.py` compares `walk()` instruction-for-
instruction against pelrun's DisPel, which is vendored and built at
`tools/Dispel/dispel`. That is an independent implementation by a different
author, which is the only kind of agreement worth having here: a table checked
against itself agrees with itself.
"""
import argparse
import sys
from pathlib import Path as _P

REPO = _P(__file__).resolve().parent.parent

# --------------------------------------------------------------- lengths --
#            0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F
_LEN = (  # 00
    "2" "2" "2" "2" "2" "2" "2" "2" "1" "M" "1" "1" "3" "3" "3" "4"
    # 10
    "2" "2" "2" "2" "2" "2" "2" "2" "1" "3" "1" "1" "3" "3" "3" "4"
    # 20
    "3" "2" "4" "2" "2" "2" "2" "2" "1" "M" "1" "1" "3" "3" "3" "4"
    # 30
    "2" "2" "2" "2" "2" "2" "2" "2" "1" "3" "1" "1" "3" "3" "3" "4"
    # 40
    "1" "2" "2" "2" "3" "2" "2" "2" "1" "M" "1" "1" "3" "3" "3" "4"
    # 50
    "2" "2" "2" "2" "3" "2" "2" "2" "1" "3" "1" "1" "4" "3" "3" "4"
    # 60
    "1" "2" "3" "2" "2" "2" "2" "2" "1" "M" "1" "1" "3" "3" "3" "4"
    # 70
    "2" "2" "2" "2" "2" "2" "2" "2" "1" "3" "1" "1" "3" "3" "3" "4"
    # 80
    "2" "2" "3" "2" "2" "2" "2" "2" "1" "M" "1" "1" "3" "3" "3" "4"
    # 90
    "2" "2" "2" "2" "2" "2" "2" "2" "1" "3" "1" "1" "3" "3" "3" "4"
    # A0
    "X" "2" "X" "2" "2" "2" "2" "2" "1" "M" "1" "1" "3" "3" "3" "4"
    # B0
    "2" "2" "2" "2" "2" "2" "2" "2" "1" "3" "1" "1" "3" "3" "3" "4"
    # C0
    "X" "2" "2" "2" "2" "2" "2" "2" "1" "M" "1" "1" "3" "3" "3" "4"
    # D0
    "2" "2" "2" "2" "2" "2" "2" "2" "1" "3" "1" "1" "3" "3" "3" "4"
    # E0
    "X" "2" "2" "2" "2" "2" "2" "2" "1" "M" "1" "1" "3" "3" "3" "4"
    # F0
    "2" "2" "2" "2" "3" "2" "2" "2" "1" "3" "1" "1" "3" "3" "3" "4"
)
assert len(_LEN) == 256, "the length table must cover every opcode"

IMM_M = frozenset(i for i, c in enumerate(_LEN) if c == "M")   # 09 29 49 69 89 A9 C9 E9
IMM_X = frozenset(i for i, c in enumerate(_LEN) if c == "X")   # A0 A2 C0 E0
LEN = {i: int(c) for i, c in enumerate(_LEN) if c not in "MX"}

BRANCH = frozenset({0x10, 0x30, 0x50, 0x70, 0x90, 0xB0, 0xD0, 0xF0, 0x80})  # rel8
BRL = 0x82                                                                  # rel16
# Instructions after which execution does not continue at addr+len.
TERMINATORS = frozenset({0x60,   # rts
                         0x6B,   # rtl
                         0x40,   # rti
                         0x4C,   # jmp abs
                         0x5C,   # jml long
                         0x6C,   # jmp (abs)
                         0x7C,   # jmp (abs,X)
                         0xDC,   # jml [abs]
                         0x80,   # bra
                         0x82})  # brl
CALLS_ABS = frozenset({0x20, 0x4C})    # 16-bit operand, target in the same bank
CALLS_LONG = frozenset({0x22, 0x5C})   # 24-bit operand


def length(op, m=1, x=1):
    """Byte length of `op` under the given flag state.

    Returns None only for an opcode outside the table, which cannot happen now
    the table is complete — the return exists so a caller that somehow gets one
    must decide what to do rather than receive a plausible guess.
    """
    if op in IMM_M:
        return 2 if m else 3
    if op in IMM_X:
        return 2 if x else 3
    return LEN.get(op)


# ------------------------------------------------------------------ walk --
def walk(rom, start, stop, m=1, x=1):
    """Yield (addr, op, length, m, x) linearly from `start`, tracking REP/SEP.

    Flat file-offset space. The flags yielded are the ones IN EFFECT for that
    instruction; a rep/sep updates them for the next one. Linear, so it will
    happily decode data as code — that is the caller's problem to bound, and
    `descend()` is the one that follows control flow.
    """
    addr = start
    while addr < stop:
        op = rom[addr]
        ln = length(op, m, x)
        if ln is None or addr + ln > stop:
            return
        yield addr, op, ln, m, x
        if op == 0xC2:                       # rep #imm — clears flag bits
            v = rom[addr + 1]
            if v & 0x20:
                m = 0
            if v & 0x10:
                x = 0
        elif op == 0xE2:                     # sep #imm — sets them
            v = rom[addr + 1]
            if v & 0x20:
                m = 1
            if v & 0x10:
                x = 1
        addr += ln


def descend(rom, lo, hi, entries, mx=(1, 1), strict=True, tables=False):
    """Recursive descent over [lo, hi) in flat file-offset space.

    -> {addr: (op, length)} for the instructions actually REACHED. Follows
    branches, brl, and in-range jsr/jmp; stops a trace at a terminator.

    `strict=True` raises on an M/X join conflict (port_saturn_proc's contract —
    there, a wrong flag state means a wrongly-sized operand gets rewritten).
    `strict=False` breaks the offending trace instead, which is what a checker
    needs: a documented address sitting in a data pocket must come back "not a
    boundary", never abort the run.

    `tables` walks a `jmp/jsr (abs,X)` dispatch table whose entries land in
    range. Default OFF: over arbitrary ROM a mis-identified table injects
    garbage entry points, and every boundary derived after that is unsound.
    """
    code, flags, work = {}, {}, []

    def push(addr, m, x):
        if not (lo <= addr < hi):
            return
        if addr in flags:
            pm, px = flags[addr]
            if (pm, px) != (m, x):
                op = rom[addr]
                if (op in IMM_M and m != pm) or (op in IMM_X and x != px):
                    if strict:
                        raise ValueError(f"M/X conflict at {addr:06X}")
            return
        flags[addr] = (m, x)
        work.append((addr, m, x))

    for e in entries:
        push(e, *mx) if isinstance(e, int) else push(*e)

    seen_tables = set()
    while work:
        addr, m, x = work.pop()
        while lo <= addr < hi and addr not in code:
            op = rom[addr]
            ln = length(op, m, x)
            if ln is None or addr + ln > hi:
                if strict and ln is None:
                    raise ValueError(f"unknown opcode {op:02X} at {addr:06X}")
                break
            code[addr] = (op, ln)
            flags[addr] = (m, x)
            if op == 0xC2:
                v = rom[addr + 1]
                m = 0 if v & 0x20 else m
                x = 0 if v & 0x10 else x
            elif op == 0xE2:
                v = rom[addr + 1]
                m = 1 if v & 0x20 else m
                x = 1 if v & 0x10 else x
            if tables and op in (0x7C, 0xFC):
                tbl = (lo & ~0xFFFF) | rom[addr + 1] | rom[addr + 2] << 8
                if lo <= tbl < hi and tbl not in seen_tables:
                    seen_tables.add(tbl)
                    for i in range(64):
                        w = (lo & ~0xFFFF) | rom[tbl + 2 * i] | rom[tbl + 2 * i + 1] << 8
                        if not (lo <= w < hi):
                            break
                        push(w, m, x)
            if op in BRANCH:
                off = rom[addr + 1]
                push(addr + 2 + (off - 256 if off > 127 else off), m, x)
            elif op == BRL:
                off = rom[addr + 1] | rom[addr + 2] << 8
                push(addr + 3 + (off - 65536 if off > 32767 else off), m, x)
            elif op in CALLS_ABS:
                t = (addr & ~0xFFFF) | rom[addr + 1] | rom[addr + 2] << 8
                push(t, m, x)
            if op in TERMINATORS:
                break
            addr += ln
    return code


def boundaries(rom, lo, hi, entries, mx=(1, 1), tables=False):
    """The reached instruction START addresses — descend() without the lengths."""
    return set(descend(rom, lo, hi, entries, mx, strict=False, tables=tables))


# ------------------------------------------------------- reference census --
def call_targets(rom):
    """{file offset: how many jsr/jmp/jsl/jml operands in the image name it}.

    ⚠ A RAW BYTE SCAN, not a disassembly: every occurrence of $20/$4C/$22/$5C is
    treated as an opcode, so data that happens to hold those bytes contributes
    false targets. That is deliberate — the alternative needs a whole-ROM code
    map, which this cartridge does not admit (every descent dies at an indirect
    dispatch). The cost is measured rather than argued: `checkdocs` reports how
    often the resulting predicate holds at an address that is merely NEARBY, and
    that number is what says whether it discriminates.

    Built with bytes.find loops because a per-byte Python loop over 2.5 MB is
    an order of magnitude slower and this runs inside health.sh.
    """
    import collections
    out = collections.Counter()
    n = len(rom)
    for op in (0x20, 0x4C):
        b, i = bytes([op]), 0
        while True:
            i = rom.find(b, i, n - 3)
            if i < 0:
                break
            out[(i & ~0xFFFF) | rom[i + 1] | rom[i + 2] << 8] += 1
            i += 1
    for op in (0x22, 0x5C):
        b, i = bytes([op]), 0
        while True:
            i = rom.find(b, i, n - 4)
            if i < 0:
                break
            out[(rom[i + 1] | rom[i + 2] << 8 | rom[i + 3] << 16) & 0x3FFFFF] += 1
            i += 1
    return out


def vector_targets(rom):
    """The native/emulation hardware vectors ($00:FFE4-$FFFE), as file offsets.

    A routine reached only through a vector — the NMI body is one — has no `jsr`
    naming it anywhere, so without these it would read as unreferenced.
    """
    out = set()
    for a in range(0xFFE4, 0x10000, 2):
        t = rom[a] | rom[a + 1] << 8
        if t >= 0x8000:
            out.add(t & 0x3FFFFF)
    return out


# ----------------------------------------------------------------- check --
def selftest():
    """Table invariants that would catch a typo in the 256-character block.

    Deliberately NOT "every entry equals what I wrote": that is the table
    checked against itself. These are cross-cutting shapes plus a handful of
    opcodes whose length this project has actually been burned by.
    """
    bad = []
    if len(LEN) + len(IMM_M) + len(IMM_X) != 256:
        bad.append("the three tables do not partition 256 opcodes")
    if sorted(IMM_M) != [0x09, 0x29, 0x49, 0x69, 0x89, 0xA9, 0xC9, 0xE9]:
        bad.append(f"IMM_M is {sorted(hex(o) for o in IMM_M)}")
    if sorted(IMM_X) != [0xA0, 0xA2, 0xC0, 0xE0]:
        bad.append(f"IMM_X is {sorted(hex(o) for o in IMM_X)}")
    # column regularities of the 65816 map: every $x3/$x7 is 2, every $xF is 4
    for col, want in ((0x03, 2), (0x07, 2), (0x0F, 4)):
        off = [o for o in range(col, 256, 16) if LEN.get(o) != want]
        if off:
            bad.append(f"column {col:02X} should be all {want}: {[hex(o) for o in off]}")
    # the eight the old table got wrong — the regression this module exists for
    for op, want in ((0x00, 2), (0x02, 2), (0x08, 1), (0x0B, 1),
                     (0x2B, 1), (0x42, 2), (0xC4, 2), (0xE4, 2)):
        if LEN.get(op) != want:
            bad.append(f"opcode {op:02X} should be {want}, is {LEN.get(op)}")
    for op in TERMINATORS | BRANCH | {BRL}:
        if length(op) is None:
            bad.append(f"control-flow opcode {op:02X} has no length")
    return bad


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--census", action="store_true",
                    help="reference-target census over the clean ROM")
    args = ap.parse_args()

    bad = selftest()
    for b in bad:
        print(f"  \033[31mFAIL\033[0m  {b}")
    if bad:
        sys.exit(1)
    print(f"\033[32mtable OK\033[0m — 256 opcodes, "
          f"{len(IMM_M)} M-width, {len(IMM_X)} X-width immediates")

    if args.census:
        sys.path.insert(0, str(REPO / "tools"))
        from smspaths import clean_rom
        rom = open(clean_rom(), "rb").read()
        ct, vt = call_targets(rom), vector_targets(rom)
        print(f"  {len(ct)} distinct reference targets, {sum(ct.values())} sites; "
              f"{len(vt)} vector targets")


if __name__ == "__main__":
    main()
