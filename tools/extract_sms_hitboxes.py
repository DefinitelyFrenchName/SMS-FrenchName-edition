#!/usr/bin/env python3
"""Extract hitbox/hurtbox/collision tables from Sailor Moon S (SFC, HiROM, headerless).

Usage: python3 extract_sms_hitboxes.py <rom.sfc> [--json out.json] [--force]
The ROM is VERIFIED against the clean SHA-1 (bc0e29ee…) and the tool refuses to run
on anything else unless --force is given (issue #38 — it used to merely print the
hash it claimed to verify).

Characters are charID 1..9 (Moon..Chibimoon). ID 10 "Saturn" is Sailor Moon Super S
data — NOT in this game; earlier versions invented an entry for her from projectile
table bytes (issue #38), which is why old copies of docs/sms_all_boxes.json carry a
bogus "Saturn" key.
"""
import sys, json
from pathlib import Path as _P
REPO = _P(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
from smspaths import CLEAN_SHA1  # noqa: E402
from boxlib import parse_box_dict as parse_box, strip_copier_header, sha_gate, word  # noqa: E402  (#85)

BANK = 0x0A0000  # file offset of SNES bank $8A
TABLES = {"hit": (0xC1F1, 8), "hurt": (0xC229, 16), "coll": (0xC23D, 8)}
NAMES = {1: "Moon", 2: "Mercury", 3: "Mars", 4: "Jupiter", 5: "Venus",
         6: "Uranus", 7: "Neptune", 8: "Pluto", 9: "Chibimoon"}

def main():
    # argparse (#72): the old hand-parse read argv[1] positionally (a leading flag
    # was consumed as the ROM path) and read --json's value by index (a trailing
    # --json died with a bare IndexError after the whole extraction had run)
    import argparse
    ap = argparse.ArgumentParser(description="Extract SMS hit/hurt/coll box tables.")
    ap.add_argument("rom", help="clean ROM path")
    ap.add_argument("--json", metavar="OUT", default=None, help="write JSON here instead of stdout")
    ap.add_argument("--force", action="store_true", help="extract even if the SHA-1 does not match the clean ROM")
    a = ap.parse_args()
    rom = strip_copier_header(open(a.rom, "rb").read())
    sha_gate(rom, CLEAN_SHA1, a.force, "clean ROM")
    rw = lambda fo: word(rom, fo)

    # read pointer tables (hit table also has projectile entries; chars are 1..9)
    ptrs = {t: [rw(BANK + off + i * 2) for i in range(12)] for t, (off, _) in TABLES.items()}
    out = {}
    for cid in range(1, 10):
        # layout is interleaved per character: hit_c < hurt_c < coll_c < hit_(c+1)
        bounds = {
            "hit": (ptrs["hit"][cid], ptrs["hurt"][cid]),
            "hurt": (ptrs["hurt"][cid], ptrs["coll"][cid]),
            "coll": (ptrs["coll"][cid], ptrs["hit"][cid + 1]),
        }
        char = {}
        for t, (toff, esz) in TABLES.items():
            start, end = bounds[t]
            if end < start:
                raise SystemExit(f"error: inverted {t} pointer range for {NAMES[cid]} "
                                 f"({start:#06x}..{end:#06x}) — pointer table misread")
            n = (end - start) // esz
            boxes = []
            for i in range(n):
                fo = BANK + start + i * esz
                if t == "hurt":
                    boxes.append({"body": parse_box(rom[fo:fo + 8]),
                                  "head": parse_box(rom[fo + 8:fo + 16])})
                else:
                    boxes.append(parse_box(rom[fo:fo + 8]))
            char[t] = {"snes": f"$8A:{start:04X}", "file": hex(BANK + start),
                       "count": n, "boxes": boxes}
        out[NAMES[cid]] = char

    dst = a.json
    text = json.dumps(out, indent=1)
    if dst:
        open(dst, "w").write(text)
        print("wrote", dst, file=sys.stderr)
    else:
        print(text)

if __name__ == "__main__":
    main()
