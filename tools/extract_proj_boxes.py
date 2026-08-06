#!/usr/bin/env python3
"""Dump the PROJECTILE / object box tables from Sailor Moon S (SFC, HiROM, headerless).

The hit pointer table $8A:C1F1 has 28 words. Indices 1..9 are the playable roster
(extract_sms_hitboxes.py handles those); the entries beyond that index the box tables
used by projectile objects ($7E:1100/1180), selected by the projectile's own +0x00 id.
This tool dumps every pointer-table entry and the box entries each one spans, so we can
identify Neptune's Deep Submerge fireball table and read its y_off/h bytes.

Usage: python3 extract_proj_boxes.py <rom.sfc>
Verified against SHA-1 bc0e29ee383574443226695215496eb0d09aaa1c.
"""
import sys

BANK = 0x0A0000  # file offset of SNES bank $8A
PT_HIT = 0xC1F1  # hit pointer table offset within bank
N_PTR = 28       # (C229 - C1F1) / 2
ESZ = 8          # hit-box entry size

ROSTER = {1: "Moon", 2: "Mercury", 3: "Mars", 4: "Jupiter", 5: "Venus",
          6: "Uranus", 7: "Neptune", 8: "Pluto", 9: "Chibimoon"}



def main():
    from pathlib import Path as _P
    sys.path.insert(0, str(_P(__file__).resolve().parent))
    from smspaths import CLEAN_SHA1
    from boxlib import parse_box_tuple as parse_box, strip_copier_header, sha_gate, word  # (#85)
    rom = strip_copier_header(open(sys.argv[1], "rb").read())
    sha_gate(rom, CLEAN_SHA1, "--force" in sys.argv, "clean ROM")
    rw = lambda fo: word(rom, fo)

    ptrs = [rw(BANK + PT_HIT + i * 2) for i in range(N_PTR)]
    # distinct table starts, sorted, to bound each table's extent. Each table ends
    # where the next one starts; the LAST has no following pointer to bound it and
    # no documented neighbour in bank $8A (#71), so its extent is UNKNOWN — it is
    # previewed below with an explicit marker instead of an invented count.
    PREVIEW = 6                     # entries shown for the unbounded final table
    starts = sorted(set(p for p in ptrs if p != 0))
    nxt = {}
    for i, s in enumerate(starts):
        nxt[s] = starts[i + 1] if i + 1 < len(starts) else None

    print("hit pointer table $8A:C1F1 (28 entries):")
    for i, p in enumerate(ptrs):
        tag = ROSTER.get(i, "")
        note = ""
        if i == 0:
            note = "(null)"
        elif i == 10:
            note = "<- was 'Saturn' slot; NOT in this game -> first projectile/object table"
        elif i >= 11:
            note = "<- projectile/object table"
        print(f"  idx {i:2d}: $8A:{p:04X}  file 0x{BANK+p:05X}  {tag:9s} {note}")

    print("\ndistinct tables and their box entries:")
    for s in starts:
        end = nxt[s]
        owners = [i for i, p in enumerate(ptrs) if p == s]
        owner_str = ",".join(str(o) for o in owners)
        if end is None:
            n = PREVIEW
            print(f"\n$8A:{s:04X} (file 0x{BANK+s:05X})  used by pointer idx [{owner_str}]  "
                  f"extent UNKNOWN (final table, nothing bounds it) — "
                  f"first {PREVIEW} entries as a preview, NOT a derived count:")
        else:
            n = max(0, (end - s) // ESZ)
            # ~: the span to the next pointer start is an upper bound — for the
            # roster tables it also contains that character's hurt/coll data
            print(f"\n$8A:{s:04X} (file 0x{BANK+s:05X})  used by pointer idx [{owner_str}]  ~{n} entries:")
        for j in range(n):
            fo = BANK + s + j * ESZ
            b = parse_box(rom[fo:fo + ESZ])
            yb = b[4]
            hb = b[5]
            span = f"y {yb}..{yb+hb}" if hb else "(empty)"
            print(f"    [{j:2d}] xr={b[0]:4d} wr={b[1]:3d} xl={b[2]:4d} wl={b[3]:3d} "
                  f"y_off={b[4]:4d} h={b[5]:3d} flags={b[6]:#04x}  {span}")


if __name__ == "__main__":
    main()
