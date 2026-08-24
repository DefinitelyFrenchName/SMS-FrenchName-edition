#!/usr/bin/env python3
"""census_struct_cell.py — who writes a byte of the object struct?

  python3 tools/census_struct_cell.py 0x7C        # the cell under question
  python3 tools/census_struct_cell.py 0x7C -v     # ...and every reached writer

WHY THIS EXISTS. The anime-fighter build line parks state in the object struct's
tail (`+0x79` air-blockstun timer, `+0x7D` hitbox age, `+0x7E` juggle count,
`+0x7F` air budget) and the mash-contest clash wants one more (`+0x7C`). A cell
is only free if the ENGINE never writes it, and "I grepped and found nothing" is
not that claim: a raw byte scan of banks $C0/$C1 for `95 7C` also matches the
operand bytes of unrelated instructions, and it cannot see a writer whose bytes
it does not know to look for. This tool answers the question the way the +0x46
census did in Phase 6 — by DECODING, so a match is a match at an instruction
boundary — and it prints the residual it cannot decide instead of implying zero.

WHAT IT REPORTS, in three parts:

  * REACHED WRITERS — instructions that write the cell and that the recursive
    descent actually reached from a real entry point. This is the measurement.
  * UNREACHED CANDIDATES — byte patterns that would write the cell but sit in
    code the descent never reached (or in data). Each is printed, because an
    absence claim is only as wide as the coverage behind it, and this cartridge
    admits no whole-ROM code map (every descent dies at an indirect dispatch).
  * COVERAGE — how many instructions were reached, so the two numbers above can
    be read against something.

CONTROLS (run every time, before the answer is printed):

  * positive — the same census for `+0x46` (the reaction flag, hundreds of
    writers) and `+0x78` (the throw interpreter's byte6 sink, annotations.md
    $C1:06E5) must each find REACHED writers. A census that finds nothing
    everywhere has stopped working and would pass every cell it can no longer
    see (trap 20, pointed at this tool).
  * framing — the descent must reach a documented instruction whose address is
    known independently (`$C1:0E4F`, the 16-bit `stz $47,X`), and must NOT
    report it as a boundary one byte over. On this CPU "is there an instruction
    here" has no answer until you say where the decoder started (trap 22).

Read-only: opens the clean ROM through smspaths and writes nothing.
"""
import argparse
import sys
from pathlib import Path as _P

REPO = _P(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
import dis65816
from smspaths import clean_rom

C0, C1 = 0x000000, 0x010000
BANKS = (C0, C1 + 0x10000)                 # banks $C0-$C1, flat file offsets
DISPATCH = C1 + 0x00A6                     # 28-entry proc dispatch
FRAME_CTRL = 0x00E255                      # the in-match loop ($C0:E255)

# Every addressing form that can WRITE one struct byte on this engine. The
# struct is reached as dp,X / dp,Y with a 16-bit index and DP = 0 (X = $1000 or
# $1080), as abs,X / abs,Y with the offset in the operand (`sta $0046,Y`), or
# as an absolute naming a player slot outright ($1046). Read forms are
# deliberately absent: this asks who MODIFIES the cell.
#
# ⚠ PLAIN dp IS NOT A STRUCT ACCESS HERE and is excluded on purpose. DP is 0
# during a match and `$78`, `$46` and their neighbours are ordinary global
# direct-page variables — the clash's own sfx request is `sta $78`. Counting
# them made +0x78 report 399 "writers" of a struct cell that the throw
# interpreter touches once.
DP_IDX = {0x95: "sta $%02X,X", 0x94: "sty $%02X,X", 0x96: "stx $%02X,Y",
          0x74: "stz $%02X,X", 0xF6: "inc $%02X,X", 0xD6: "dec $%02X,X",
          0x16: "asl $%02X,X", 0x36: "rol $%02X,X", 0x56: "lsr $%02X,X",
          0x76: "ror $%02X,X"}
ABS_IDX = {0x9D: "sta $%04X,X", 0x99: "sta $%04X,Y", 0x9E: "stz $%04X,X",
           0xFE: "inc $%04X,X", 0xDE: "dec $%04X,X", 0x1E: "asl $%04X,X",
           0x3E: "rol $%04X,X", 0x5E: "lsr $%04X,X", 0x7E: "ror $%04X,X"}
ABS_DIR = {0x8D: "sta $%04X", 0x8C: "sty $%04X", 0x8E: "stx $%04X",
           0x9C: "stz $%04X", 0xEE: "inc $%04X", 0xCE: "dec $%04X"}
# the absolute forms that name a PLAYER slot outright
SLOTS = (0x1000, 0x1080)


def entries(rom):
    """Entry points for the descent: the hardware vectors, the in-match frame
    control, hit resolution, the reaction dispatch's three posture sub-tables,
    the proc dispatch's 28 blocks, and every act handler of all nine characters
    (the act tables are `jmp (tbl,X)` dispatches, which a descent cannot follow
    on its own). Everything else is reached by FOLLOWING calls from these.

    ⚠ `dis65816.call_targets` is deliberately NOT used as an entry set here: it
    is a raw byte scan, so data that happens to hold a `$20` contributes entry
    points inside real instructions, and a descent seeded mid-instruction
    decodes a shifted stream that reports boundaries where there are none. It
    failed the framing control by exactly that route ($C1:0E4F AND $C1:0E50
    both read as boundaries) before this set was narrowed."""
    lo, hi = BANKS
    ents = {a for a in dis65816.vector_targets(rom) if lo <= a < hi}
    ents.add(FRAME_CTRL)
    ents.add(0x00BFC0)                     # hit resolution ($C0:BFC0)
    ents.add(C1 + 0x0000)                  # the per-frame object update (JSL'd)
    ents.add(C1 + 0x06E5)                  # throw-hold script interpreter
    ents.add(C1 + 0x0E26)                  # the reaction dispatch
    for sub in (0x0E83, 0x0E9F, 0x0EBB):   # reaction posture sub-tables
        for n in range(16):
            w = rom[C1 + sub + n * 2] | rom[C1 + sub + n * 2 + 1] << 8
            if w and lo <= C1 + w < hi:
                ents.add(C1 + w)
    procs = []
    for i in range(1, 28):
        w = rom[DISPATCH + i * 2] | rom[DISPATCH + i * 2 + 1] << 8
        if w:
            procs.append(C1 + w)
    ents |= set(procs)
    # act tables: the first `jmp (abs,X)` inside each of the nine character
    # proc blocks names the table; its non-null words are handlers.
    for cid in range(1, 10):
        p = procs[cid - 1]
        for a, op, ln, m, x in dis65816.walk(rom, p, p + 0x20, m=1, x=0):
            if op == 0x7C:
                tbl = C1 + (rom[a + 1] | rom[a + 2] << 8)
                for n in range(0x80):
                    w = rom[tbl + n * 2] | rom[tbl + n * 2 + 1] << 8
                    if w and lo <= C1 + w < hi:
                        ents.add(C1 + w)
                break
    return ents


def descend_closed(rom, ents):
    """Descend, then re-descend from every JSL target found in the code already
    reached, until the reached set stops growing.

    `descend()` follows in-bank jsr/jmp only, and this engine crosses banks
    constantly ($C0 enters $C1 through `jsl $C1:0000` and friends), so a single
    pass leaves most of bank $C1 unreached. The targets come out of DECODED
    instructions, never a byte scan — which is what keeps the framing honest."""
    lo, hi = BANKS
    ents = set(ents)
    code = {}
    while True:
        code = dis65816.descend(rom, lo, hi, sorted(ents), mx=(1, 1), strict=False)
        new = set()
        for addr, (op, ln) in code.items():
            if op == 0x22:                 # jsl
                t = (rom[addr + 1] | rom[addr + 2] << 8 | rom[addr + 3] << 16) & 0x3FFFFF
                if lo <= t < hi and t not in ents:
                    new.add(t)
        if not new:
            return code
        ents |= new


def writers(rom, cell, code):
    """(reached, candidates) — every instruction in `code` that writes `cell`,
    and every byte pattern in the banks that would, whether reached or not."""
    lo, hi = BANKS
    reached, cand = [], []

    def forms(addr, op, ln):
        if op in DP_IDX and rom[addr + 1] == cell:
            return DP_IDX[op] % cell
        if op in ABS_IDX or op in ABS_DIR:
            w = rom[addr + 1] | rom[addr + 2] << 8
            if w == cell or w in (s + cell for s in SLOTS):
                return (ABS_IDX.get(op) or ABS_DIR[op]) % w
        return None

    for addr, (op, ln) in sorted(code.items()):
        f = forms(addr, op, ln)
        if f:
            reached.append((addr, f))
    for addr in range(lo, hi - 3):
        op = rom[addr]
        ln = dis65816.length(op, 1, 1) or 1
        f = forms(addr, op, ln)
        if f and addr not in code:
            cand.append((addr, f))
    return reached, cand


def snes(a):
    return f"${0xC0 + (a >> 16):02X}:{a & 0xFFFF:04X}"


def main():
    ap = argparse.ArgumentParser(description="who writes a struct byte?")
    ap.add_argument("cell", type=lambda v: int(v, 0), help="struct offset, e.g. 0x7C")
    ap.add_argument("-v", "--verbose", action="store_true")
    a = ap.parse_args()

    rom = _P(clean_rom()).read_bytes()
    code = descend_closed(rom, entries(rom))

    # --- framing control: a documented instruction, and its interior byte ---
    doc = C1 + 0x0E4F                       # 16-bit `stz $47,X` (patch 13 docs)
    if doc not in code:
        print(f"FRAMING CONTROL FAILED: {snes(doc)} (documented stz $47,X) not reached")
        return 1
    if doc + 1 in code:
        print(f"FRAMING CONTROL FAILED: {snes(doc + 1)} also reads as a boundary")
        return 1
    print(f"framing control ok: {snes(doc)} reached, {snes(doc + 1)} is not a boundary")

    # --- positive controls: cells the engine demonstrably writes -------------
    for ctl in (0x46, 0x78):
        r, _ = writers(rom, ctl, code)
        if not r:
            print(f"POSITIVE CONTROL FAILED: no reached writer of +0x{ctl:02X}")
            return 1
        print(f"positive control ok: +0x{ctl:02X} has {len(r)} reached writers")
    print(f"coverage: {len(code)} instructions reached in banks $C0-$C1")
    print()

    reached, cand = writers(rom, a.cell, code)
    print(f"== +0x{a.cell:02X} ==")
    print(f"   REACHED WRITERS:      {len(reached)}")
    for addr, f in reached if (a.verbose or len(reached) <= 40) else []:
        print(f"      {snes(addr)}  {f}")
    print(f"   UNREACHED CANDIDATES: {len(cand)}  (byte patterns the descent never reached)")
    for addr, f in cand if (a.verbose or len(cand) <= 40) else []:
        print(f"      {snes(addr)}  {f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
