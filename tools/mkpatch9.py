#!/usr/bin/env python3
"""Patch 9 (OPTIONAL): fix Sailor Neptune's "Deep Submerge" fireball hitbox so it follows
the descending sprite instead of floating at head level.

Deep Submerge (214LP = action 0x62 / 214HP = action 0x63) spawns a projectile object whose
own id is 0x18. Projectiles select their box table from the hit pointer table $8A:C1F1 by
their own +0x00, so object 0x18 uses table $8A:FD51 (file 0xAFD51), which is EXCLUSIVE to this
fireball (pointer idx 24; no character/other projectile shares it).

Measured in-emulator (tools/ds_trace.lua / ds_overlay.lua): the fireball travels a shallow
down-forward arc — its origin (+0x25) descends from y=128 to ~166 while the visible energy
ball stays centered on that origin (ball extent ~ origin +/-11). BUT the hit-box entries were
authored for an UPWARD path: their y_off values grow more negative over the move
(entries 1-3 = -27, entry 4 = -60), i.e. the box climbs while the ball falls. Result: the
hitbox floats 27-60px ABOVE the ball ("mostly stays at head level") and the move whiffs where
it visually connects. This is the reported bug — sprite and hitbox on opposite vertical paths.

Fix: recentre every active hit box on the projectile origin (where the ball is drawn) by
setting each entry's y_off to NEW_YOFF (default -11), keeping height h=22 and the x offsets
untouched. With y_off=-11, h=22 the box spans origin -11..+11 = the ball, and since the box is
now origin-relative-constant it tracks the ball for the whole descent (both LP and HP, which
share object 0x18 / this table). Four bytes; hurt/collision boxes and all other moves untouched.
"""
import sys
import argparse
from hashlib import sha1

from pathlib import Path as _P
REPO = _P(__file__).resolve().parent.parent  # repo root (cwd-independent)
sys.path.insert(0, str(REPO / "tools"))
from smspaths import clean_rom, require_source, check_not_inplace  # ROM location: $SMS_ROM_DIR -> roms/ -> ../roms/
CLEAN = clean_rom()
CLEAN_SHA1 = "bc0e29ee383574443226695215496eb0d09aaa1c"

# Deep Submerge fireball object box table $8A:FD51 = file 0xAFD51 (8-byte entries).
# y_off is byte +4 of each entry. Active hit-box entries are 1,2,3,4.
TABLE = 0xAFD51
ENTRIES = (1, 2, 3, 4)
YOFF = {i: TABLE + i * 8 + 4 for i in ENTRIES}
VANILLA_YOFF = {1: -27, 2: -27, 3: -27, 4: -60}   # signed
VANILLA_H = 22                                     # all four; unchanged by this patch


def s8(v):
    return v & 0xFF


def build(src, out, yoff):
    data = bytearray(open(src, "rb").read())
    for i in ENTRIES:
        got = data[YOFF[i]]
        assert got == s8(VANILLA_YOFF[i]), (
            f"fireball hit[{i}] y_off site 0x{YOFF[i]:05X}: {got:#04x} "
            f"(expected {s8(VANILLA_YOFF[i]):#04x})")
        # sanity: height byte should be the expected 22 (we do NOT change it)
        h = data[TABLE + i * 8 + 5]
        assert h == VANILLA_H, f"fireball hit[{i}] h: {h} (expected {VANILLA_H})"
    for i in ENTRIES:
        data[YOFF[i]] = s8(yoff)
    _fix_checksum(data)
    open(out, "wb").write(data)
    print(f"wrote {out} from {src}: Deep Submerge fireball hit[1..4] y_off "
          f"{{-27,-27,-27,-60}}->{yoff} (box now origin{yoff:+d}..{yoff+VANILLA_H:+d}), "
          f"sha1={sha1(bytes(data)).hexdigest()}")


def _fix_checksum(data):
    # SNES checksum over a power-of-two footprint: pad-region repeated to fill.
    # Fixed 2026-07-30 (issue #9): the old `while chk_size <= size` loop skipped the
    # equality branch and hung on power-of-two sizes, and over-summed 0x380000.
    size = len(data)
    chk_size = max(0x80000, 1 << (size - 1).bit_length())
    if chk_size == size:
        chk = sum(data)
    else:
        half = chk_size // 2
        cd = bytes(data[half:])
        cd = (cd * ((half + len(cd) - 1) // len(cd)))[:half]
        chk = sum(data[:half]) + sum(cd)
    data[0xFFDE] = chk & 0xFF; data[0xFFDF] = chk >> 8 & 0xFF
    data[0xFFDC] = data[0xFFDE] ^ 0xFF; data[0xFFDD] = data[0xFFDF] ^ 0xFF


if __name__ == "__main__":
    ap = argparse.ArgumentParser(
        description="Fix Neptune Deep Submerge fireball hitbox to track the descending sprite.")
    ap.add_argument("src", nargs="?", default=CLEAN, help="input ROM (clean or a combined build)")
    ap.add_argument("out", nargs="?", default=str(REPO / "build/sms_neptune_ds.sfc"), help="output ROM path")
    ap.add_argument("--yoff", type=lambda s: int(s, 0), default=-11,
                    help="new y_off for the 4 active hit boxes (signed; box spans origin+yoff "
                         "for h=22). Default -11 centres the box on the ball. Use larger |value| "
                         "to bias higher, smaller to bias lower.")
    ap.add_argument("--stacked", action="store_true",
                    help="src is an already-patched ROM (builder chaining); skips the clean-SHA gate")
    a = ap.parse_args()
    assert -30 <= a.yoff <= 5, "yoff should be a small signed offset around the origin"
    check_not_inplace(a.src, a.out)
    require_source(a.src, a.stacked)
    build(a.src, a.out, a.yoff)
