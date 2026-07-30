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
sys.path.insert(0, str(REPO / "tools"))
from smspaths import clean_rom, require_source, check_not_inplace, fix_checksum  # ROM location: $SMS_ROM_DIR -> roms/ -> ../roms/
CLEAN = clean_rom()

# Detection fingerprint (p7) — consumed by tools/mksigs.py to generate the
# regression suite's SIGS table. ONLY bytes invariant across stub-layout and
# bank-stacking changes: the DEFAULT box height 62 — a --h retune changes this byte; rerun mksigs --write
SIG = [(0xAF0DE, 0x3E)]
CLEAN_SHA1 = "bc0e29ee383574443226695215496eb0d09aaa1c"

# Pluto hit table $8A:F0C1 = file 0xAF0C1; box 0x03 at +0x18; height byte at +5.
H_OFF = 0xAF0C1 + 0x03 * 8 + 5
VANILLA_H = 54

def build(src, out, h):
    data = bytearray(open(src, "rb").read())
    if not (data[H_OFF] == VANILLA_H):
        raise ValueError(f"5HP box height site: {data[H_OFF]} (expected {VANILLA_H})")
    data[H_OFF] = h
    fix_checksum(data)
    open(out, "wb").write(data)
    print(f"wrote {out} from {src}: Pluto 5HP hit[0x03] h {VANILLA_H}->{h} "
          f"(bottom {-109 + h}), sha1={sha1(bytes(data)).hexdigest()}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Extend Pluto 5HP hitbox downward to hit crouchers.")
    ap.add_argument("src", nargs="?", default=CLEAN, help="input ROM (clean or a combined build)")
    ap.add_argument("out", nargs="?", default=str(REPO / "build/sms_pluto5hp.sfc"), help="output ROM path")
    ap.add_argument("--h", type=lambda s: int(s, 0), default=62,
                    help="new box height. 54=vanilla, 62=all crouchers except Chibi (default), "
                         "64=all incl Chibi.")
    ap.add_argument("--stacked", action="store_true",
                    help="src is an already-patched ROM (builder chaining); skips the clean-SHA gate")
    a = ap.parse_args()
    if not (VANILLA_H <= a.h <= 90):
        raise ValueError("h should be between vanilla (54) and ~90")
    check_not_inplace(a.src, a.out)
    require_source(a.src, a.stacked)
    build(a.src, a.out, a.h)
