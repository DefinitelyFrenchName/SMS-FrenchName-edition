#!/usr/bin/env python3
"""Extract hitbox/hurtbox/collision tables from Sailor Moon SUPER S (Zenin Sanka!!).

Super S counterpart of extract_sms_hitboxes.py, using the vendor Lua's Rosetta
constants (docs/saturn/supers_map.md): box data in bank $AF, pointer tables at
$AF:B000 (hit) / $AF:B046 (hurt) / $AF:B05C (coll), charIDs 1..10 (10 = Sailor
Saturn — playable in THIS game). Same 8-byte box format and interleaved per-char
layout as SMS; the bounds-inversion guard will catch it if that assumption fails.

Usage: python3 tools/saturn/extract_supers_boxes.py [rom] [--json out.json] [--force]
Defaults to smspaths.supers_rom(), SHA-verified.
"""
import sys, json, struct, hashlib
from pathlib import Path as _P
REPO = _P(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO / "tools"))
from smspaths import supers_rom, SUPERS_SHA1  # noqa: E402

BANK = 0x2F0000  # file offset of SNES bank $AF
TABLES = {"hit": (0xB000, 8), "hurt": (0xB046, 16), "coll": (0xB05C, 8)}
NAMES = {1: "Moon", 2: "Mercury", 3: "Mars", 4: "Jupiter", 5: "Venus",
         6: "Uranus", 7: "Neptune", 8: "Pluto", 9: "Chibimoon", 10: "Saturn"}
NCHAR = 10

def s8(b): return b - 256 if b > 127 else b

def parse_box(e):
    return {"x_off_r": s8(e[0]), "w_r": e[1], "x_off_l": s8(e[2]), "w_l": e[3],
            "y_off": s8(e[4]), "h": e[5], "flags": e[6]}

def main():
    argv = sys.argv[1:]
    skip = set()
    if "--json" in argv:
        skip.add(argv.index("--json") + 1)
    args = [a for i, a in enumerate(argv) if not a.startswith("--") and i not in skip]
    path = args[0] if args else supers_rom()
    rom = open(path, "rb").read()
    if len(rom) % 0x8000 == 0x200:
        rom = rom[0x200:]
    h = hashlib.sha1(rom).hexdigest()
    print("SHA-1:", h, file=sys.stderr)
    if h != SUPERS_SHA1 and "--force" not in sys.argv:
        raise SystemExit(f"error: not the Super S ROM (expected {SUPERS_SHA1}); --force to override")
    rw = lambda fo: struct.unpack("<H", rom[fo:fo + 2])[0]

    ptrs = {t: [rw(BANK + off + i * 2) for i in range(NCHAR + 2)] for t, (off, _) in TABLES.items()}
    print("hit ptrs :", " ".join(f"{p:04X}" for p in ptrs["hit"]), file=sys.stderr)
    print("hurt ptrs:", " ".join(f"{p:04X}" for p in ptrs["hurt"]), file=sys.stderr)
    print("coll ptrs:", " ".join(f"{p:04X}" for p in ptrs["coll"]), file=sys.stderr)
    out = {}
    for cid in range(1, NCHAR + 1):
        bounds = {
            "hit": (ptrs["hit"][cid], ptrs["hurt"][cid]),
            "hurt": (ptrs["hurt"][cid], ptrs["coll"][cid]),
            "coll": (ptrs["coll"][cid], ptrs["hit"][cid + 1]),
        }
        char = {}
        for t, (toff, esz) in TABLES.items():
            start, end = bounds[t]
            if end < start:
                raise SystemExit(f"error: inverted {t} range for {NAMES[cid]} "
                                 f"({start:#06x}..{end:#06x}) — layout assumption broken")
            n = (end - start) // esz
            boxes = []
            for i in range(n):
                fo = BANK + start + i * esz
                if t == "hurt":
                    boxes.append({"body": parse_box(rom[fo:fo + 8]),
                                  "head": parse_box(rom[fo + 8:fo + 16])})
                else:
                    boxes.append(parse_box(rom[fo:fo + 8]))
            char[t] = {"snes": f"$AF:{start:04X}", "file": hex(BANK + start),
                       "count": n, "boxes": boxes}
        out[NAMES[cid]] = char

    dst = sys.argv[sys.argv.index("--json") + 1] if "--json" in sys.argv else None
    text = json.dumps(out, indent=1)
    if dst:
        open(dst, "w").write(text)
        print("wrote", dst, file=sys.stderr)
    else:
        print(text)

if __name__ == "__main__":
    main()
