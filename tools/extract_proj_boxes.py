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
import sys, struct, hashlib

BANK = 0x0A0000  # file offset of SNES bank $8A
PT_HIT = 0xC1F1  # hit pointer table offset within bank
N_PTR = 28       # (C229 - C1F1) / 2
ESZ = 8          # hit-box entry size

ROSTER = {1: "Moon", 2: "Mercury", 3: "Mars", 4: "Jupiter", 5: "Venus",
          6: "Uranus", 7: "Neptune", 8: "Pluto", 9: "Chibimoon"}


def s8(b):
    return b - 256 if b > 127 else b


def parse_box(e):
    return (s8(e[0]), e[1], s8(e[2]), e[3], s8(e[4]), e[5], e[6], e[7])


def main():
    rom = open(sys.argv[1], "rb").read()
    if len(rom) % 0x8000 == 0x200:
        rom = rom[0x200:]  # strip copier header (issue #38: was % 0x100000, never matched)
    h = hashlib.sha1(rom).hexdigest()
    print("SHA-1:", h, file=sys.stderr)
    from pathlib import Path as _P
    sys.path.insert(0, str(_P(__file__).resolve().parent))
    from smspaths import CLEAN_SHA1
    if h != CLEAN_SHA1 and "--force" not in sys.argv:
        raise SystemExit(f"error: not the clean ROM (expected {CLEAN_SHA1}); "
                         "pass --force to extract anyway")
    rw = lambda fo: struct.unpack("<H", rom[fo:fo + 2])[0]

    ptrs = [rw(BANK + PT_HIT + i * 2) for i in range(N_PTR)]
    # distinct table starts, sorted, to bound each table's extent
    starts = sorted(set(p for p in ptrs if p != 0))
    nxt = {}
    for i, s in enumerate(starts):
        nxt[s] = starts[i + 1] if i + 1 < len(starts) else s + 0x30  # last: guess a small span

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
        n = max(0, (end - s) // ESZ)
        owners = [i for i, p in enumerate(ptrs) if p == s]
        owner_str = ",".join(str(o) for o in owners)
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
