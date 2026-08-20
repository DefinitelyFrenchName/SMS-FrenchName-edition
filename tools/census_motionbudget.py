#!/usr/bin/env python3
"""census_motionbudget.py — per-character motion-list budget vs the 7-motion
nibble cap. (Phase 1 of the anime-fighter feasibility programme; gate G5 —
a character already at 7/7 without a 66 script cannot take a recognizer-driven
forward dash and needs a different input mechanism.)

Command ids are a nibble in +0x51 and motion N yields id 2N+2 (+1 heavy), so
ids 2..15 give at most SEVEN motions (N = 0..6). This tool walks the motion
pointer lists at $C1:13C7 + charID*2 (interpreter $C1:128B; scripts are 2-byte
[timeout][input mask] steps, $FF-terminated; mask bit0 fwd, bit1 back, bit2
down, bit3 up, high nibble buttons) and reports, per character: motions used,
slots free, whether a 66 (fwd double-tap) script is present, and each script's
step masks.

Controls:
  + motion 0 must be the shared 44 backdash script, byte-identical on all nine
    (documented: $C1:1445, (00,00)(00,02)(00,00)(00,02)).
  + Venus must have exactly 5 motions and Uranus a 66 at $C1:1535
    (both measured by tools/exp_airbackdash.py).
  - the same parse one byte off the list pointer must NOT reproduce the
    shared-motion-0 anchor.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from smspaths import clean_rom

C1 = 0x010000
LISTS = C1 + 0x13C7
NAMES = {1: "Moon", 2: "Mercury", 3: "Mars", 4: "Jupiter", 5: "Venus",
         6: "Uranus", 7: "Neptune", 8: "Pluto", 9: "ChibiMoon"}
BACKDASH_44 = bytes([0, 0x00, 0, 0x02, 0, 0x00, 0, 0x02, 0xFF])
CAP = 7


def word(rom, off):
    return rom[off] | rom[off + 1] << 8


def script(rom, ptr):
    """The raw script bytes at $C1:ptr, through the $FF terminator."""
    off, out = C1 + ptr, bytearray()
    while rom[off] != 0xFF:
        out += rom[off:off + 2]
        off += 2
        if len(out) > 40:
            return None                      # runaway: not a script
    return bytes(out) + b"\xff"


def is_66(s):
    """fwd-only double tap: masks (00,01,00,01), any timeouts."""
    return (s is not None and len(s) == 9
            and [b & 0x0F for b in s[1:8:2]] == [0x00, 0x01, 0x00, 0x01])


def motions(rom, cid, shift=0):
    lst = word(rom, LISTS + cid * 2) + shift
    out, off = [], C1 + lst
    while True:
        p = word(rom, off)
        if p == 0xFFFF:
            return lst, out
        out.append(p)                        # $0000 entries are skipped slots
        off += 2
        if len(out) > 16:
            return lst, out                  # runaway: caller's controls object


def main():
    rom = Path(clean_rom()).read_bytes()
    fails = []

    # negative control: one byte off, motion 0 must not be the 44 anchor
    for cid in (1, 6):
        _, ms = motions(rom, cid, shift=1)
        if ms and ms[0] and script(rom, ms[0]) == BACKDASH_44:
            fails.append(f"negative control: shifted list for id {cid} still anchors the 44")

    print(f"{'char':<10} {'list':>5}  used/{CAP}  66?  scripts")
    for cid in range(1, 10):
        name = NAMES[cid]
        lst, ms = motions(rom, cid)
        used = sum(1 for p in ms if p)
        has66 = any(is_66(script(rom, p)) for p in ms if p)
        descs = []
        for n, p in enumerate(ms):
            if not p:
                descs.append(f"m{n}:--")
                continue
            s = script(rom, p)
            masks = "".join(f"{b:02X}" for b in s[1:-1:2]) if s else "??"
            descs.append(f"m{n}@${p:04X}:{masks}")
        print(f"{name:<10} ${lst:04X}   {used}/{CAP}    {'Y' if has66 else '-'}   " + " ".join(descs))

        m0 = script(rom, ms[0]) if ms and ms[0] else None
        if m0 != BACKDASH_44:
            fails.append(f"{name}: motion 0 is not the shared 44 backdash script")
        if name == "Venus" and used != 5:
            fails.append(f"Venus motions {used} != 5 (exp_airbackdash's measured figure)")
        if name == "Uranus" and not (len(ms) > 1 and ms[1] == 0x1535 and is_66(script(rom, ms[1]))):
            fails.append("Uranus: motion 1 is not the 66 at $1535")

    if fails:
        print("\nCONTROL FAILURES:")
        for f in fails:
            print("  " + f)
        return 1
    print("\ncontrols green: shared-44 anchor on all nine, Venus=5, Uranus 66@$1535, shifted-list negative")
    return 0


if __name__ == "__main__":
    sys.exit(main())
