#!/usr/bin/env python3
"""census_onhit_flags.py — dump byte 3 ("flags") of the ten global on-hit
tables at $C0:CDD5..$C0:D015 (stride 0x40, 16 x 4-byte records each).

Phase 0 static companion of the anime-fighter feasibility programme: the
records are documented as [damage][hitstun][hit level][flags] and byte 3 has
never been decoded anywhere in the repo (docs/game/sms_data_architecture.md
names it and stops). This tool prints the raw census so the byte's value set
can be read against the reaction rows probe_juggle.lua observes live.

Read-only: opens the clean ROM via smspaths and writes nothing.

Anchors (positive control): sms_data_architecture.md's decoded sample rows for
table $CDD5 idx 0/2/4/7 — [6,8,1], [10,8,2], [14,8,2], [24,8,2]. The same
check re-run at base+1 must MISMATCH (negative control), else the anchor
proves nothing about the address.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from smspaths import clean_rom

TABLES = [0xCDD5 + i * 0x40 for i in range(10)]     # bank $C0 -> file offset = addr
RECORDS = 16
ANCHORS = {0: (6, 8, 1), 2: (10, 8, 2), 4: (14, 8, 2), 7: (24, 8, 2)}


def read_tables(rom, base_shift=0):
    out = {}
    for t in TABLES:
        recs = []
        for i in range(RECORDS):
            off = t + base_shift + i * 4
            recs.append(tuple(rom[off:off + 4]))
        out[t] = recs
    return out


def anchors_ok(tables):
    t0 = tables[TABLES[0]]
    return all(t0[i][:3] == v for i, v in ANCHORS.items())


def main():
    rom = Path(clean_rom()).read_bytes()

    # negative control first: the anchors must FAIL one byte off
    for shift in (1, 2):
        if anchors_ok(read_tables(rom, shift)):
            print(f"NEGATIVE CONTROL FAILED: anchors also match at base+{shift}")
            return 1
    tables = read_tables(rom)
    if not anchors_ok(tables):
        print("ANCHOR FAILED: documented $CDD5 rows not found — wrong ROM or rotted claim")
        return 1
    print("anchors ok at base, and they fail at base+1/+2 (controls green)")
    print()

    flags_hist = {}
    for t in TABLES:
        print(f"table $C0:{t:04X}")
        for i, (dmg, stun, lvl, fl) in enumerate(tables[t]):
            print(f"  idx {i:2d} (attackID {i*2}/{i*2+1}): dmg={dmg:3d} hitstun={stun:3d} level={lvl:2d} flags={fl:#04x}")
            flags_hist[fl] = flags_hist.get(fl, 0) + 1
        print()

    print("flags byte histogram across all 160 records:")
    for v in sorted(flags_hist):
        print(f"  {v:#04x}: {flags_hist[v]:3d}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
