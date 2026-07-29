#!/usr/bin/env python3
"""Patch 7 (OPTIONAL): extend Sailor Pluto's 5HP hitbox downward so it hits crouchers.

Pluto's 5HP (a two-phase move: startup act 0x44 -> overhead active act 0x46) whiffs most of
the cast when they crouch. The active overhead phase uses hit-box index 0x03 in Pluto's hit
table ($8A:F0C1). That box sits high (y_off=-109, h=54 -> spans y -109..-55, i.e. 55-109px
above the feet), so crouching hurtboxes whose top is below y=-55 duck under it.

This patch does ONE thing the user asked for — extend that box DOWNWARD by increasing its
height `h` (top y_off and everything else untouched). Measured crouch-hurtbox tops (y, more
negative = taller): Mars -60, Uranus -59, Neptune -58, Pluto -59, Moon -56 (already hit at
h=54); Mercury/Jupiter -54, Venus -49, Chibi -46 (whiff at h=54). A hit needs the box bottom
(= -109 + h) to reach the crouch top.

  h = 54 (vanilla): bottom -55  -> hits only the tallest crouches
  h = 62 (default): bottom -47  -> hits EVERY crouching character EXCEPT Chibi Moon (top -46)
  h = 64:           bottom -45  -> hits all crouchers including Chibi

Verified in-emulator across the whole cast. Box 0x03 is exclusive to 5HP's active phase, so no
other Pluto move changes; standing hits are unaffected (the box only grows downward). One byte.
"""
import sys
import argparse
from hashlib import sha1

from pathlib import Path as _P
REPO = _P(__file__).resolve().parent.parent  # repo root (cwd-independent)
CLEAN = str(REPO / "roms/Bishoujo Senshi Sailormoon S - Jougai Rantou! Shuyaku Soudatsusen (Japan).sfc")
CLEAN_SHA1 = "bc0e29ee383574443226695215496eb0d09aaa1c"

# Pluto hit table $8A:F0C1 = file 0xAF0C1; box 0x03 at +0x18; height byte at +5.
H_OFF = 0xAF0C1 + 0x03 * 8 + 5
VANILLA_H = 54

def build(src, out, h):
    data = bytearray(open(src, "rb").read())
    assert data[H_OFF] == VANILLA_H, f"5HP box height site: {data[H_OFF]} (expected {VANILLA_H})"
    data[H_OFF] = h
    _fix_checksum(data)
    open(out, "wb").write(data)
    print(f"wrote {out} from {src}: Pluto 5HP hit[0x03] h {VANILLA_H}->{h} "
          f"(bottom {-109 + h}), sha1={sha1(bytes(data)).hexdigest()}")

def _fix_checksum(data):
    size = len(data); chk_size = 0x80000
    while chk_size <= size: chk_size <<= 1
    if chk_size == size:
        chk = sum(data)
    else:
        cd = data[chk_size // 2:]
        while len(cd) < chk_size // 2: cd += cd[len(cd) - chk_size:]
        chk = sum(data[:chk_size // 2]) + sum(cd)
    data[0xFFDE] = chk & 0xFF; data[0xFFDF] = chk >> 8 & 0xFF
    data[0xFFDC] = data[0xFFDE] ^ 0xFF; data[0xFFDD] = data[0xFFDF] ^ 0xFF

if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Extend Pluto 5HP hitbox downward to hit crouchers.")
    ap.add_argument("src", nargs="?", default=CLEAN, help="input ROM (clean or a combined build)")
    ap.add_argument("out", nargs="?", default=str(REPO / "build/sms_pluto5hp.sfc"), help="output ROM path")
    ap.add_argument("--h", type=lambda s: int(s, 0), default=62,
                    help="new box height. 54=vanilla, 62=all crouchers except Chibi (default), "
                         "64=all incl Chibi.")
    a = ap.parse_args()
    assert VANILLA_H <= a.h <= 90, "h should be between vanilla (54) and ~90"
    if a.src == CLEAN:
        assert sha1(open(a.src, "rb").read()).hexdigest() == CLEAN_SHA1, "clean hash mismatch"
    build(a.src, a.out, a.h)
