#!/usr/bin/env python3
"""Extract hitbox/hurtbox/collision tables from Sailor Moon S (SFC, HiROM, headerless).

Usage: python3 extract_sms_hitboxes.py <rom.sfc> [--json out.json]
Verified against SHA-1 bc0e29ee383574443226695215496eb0d09aaa1c.
"""
import sys, json, struct, hashlib

BANK = 0x0A0000  # file offset of SNES bank $8A
TABLES = {"hit": (0xC1F1, 8), "hurt": (0xC229, 16), "coll": (0xC23D, 8)}
NAMES = {1: "Moon", 2: "Mercury", 3: "Mars", 4: "Jupiter", 5: "Venus",
         6: "Uranus", 7: "Neptune", 8: "Pluto", 9: "Chibimoon", 10: "Saturn"}

def s8(b): return b - 256 if b > 127 else b

def parse_box(e):
    return {"x_off_r": s8(e[0]), "w_r": e[1], "x_off_l": s8(e[2]), "w_l": e[3],
            "y_off": s8(e[4]), "h": e[5], "flags": e[6]}

def main():
    rom = open(sys.argv[1], "rb").read()
    if len(rom) % 0x100000 == 0x200:
        rom = rom[0x200:]  # strip copier header
    print("SHA-1:", hashlib.sha1(rom).hexdigest(), file=sys.stderr)
    rw = lambda fo: struct.unpack("<H", rom[fo:fo + 2])[0]

    # read pointer tables (hit table also has projectile entries; chars are 1..10)
    ptrs = {t: [rw(BANK + off + i * 2) for i in range(12)] for t, (off, _) in TABLES.items()}
    out = {}
    for cid in range(1, 11):
        # layout is interleaved per character: hit_c < hurt_c < coll_c < hit_(c+1)
        bounds = {
            "hit": (ptrs["hit"][cid], ptrs["hurt"][cid] if cid <= 9 else ptrs["hit"][cid] + 0xA8),
            "hurt": (ptrs["hurt"][cid], ptrs["coll"][cid]) if cid <= 9 else (None, None),
            "coll": (ptrs["coll"][cid], ptrs["hit"][cid + 1]) if cid <= 9 else (None, None),
        }
        char = {}
        for t, (toff, esz) in TABLES.items():
            start, end = bounds[t]
            if start is None:
                char[t] = {"note": "no entry for this id in table"}
                continue
            n = max(0, (end - start) // esz)
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

    dst = sys.argv[sys.argv.index("--json") + 1] if "--json" in sys.argv else None
    text = json.dumps(out, indent=1)
    if dst:
        open(dst, "w").write(text)
        print("wrote", dst, file=sys.stderr)
    else:
        print(text)

if __name__ == "__main__":
    main()
