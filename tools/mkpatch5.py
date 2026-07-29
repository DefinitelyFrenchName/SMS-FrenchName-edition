#!/usr/bin/env python3
"""Patch 5: halve Uranus's forward-dash travel distance.

The dash handler ($C1:88C8) sets the dash X-speed via `LDA #$0B00` (0x0B00 = 11.0
px/frame) at file 0x188E9, then runs for a fixed 14-frame duration. Halving the SPEED
(not the duration) halves the neutral travel distance while leaving every frame timing
untouched — so the 2HP>66 infinite is preserved exactly as a 1-frame link (verified: the
dash stops on contact with the opponent in the loop, so its reduced top speed never
matters there; the frame-perfect rep lands the identical 7 hits on the identical frames).

  0x0B00 (11.0 px/f) -> 0x0640 (6.25 px/f)  =>  neutral dash 121px -> 82px (~ -1/3).

Only 2 bytes; byte-disjoint from patches 1-4 (patch 2's reversal-fix edit is at the
adjacent 0x188ED/EE, untouched here). Builds from any input ROM so it stacks.
"""
import sys
from hashlib import sha1

from pathlib import Path as _P
REPO = _P(__file__).resolve().parent.parent  # repo root (cwd-independent)
CLEAN = str(REPO / "roms/Bishoujo Senshi Sailormoon S - Jougai Rantou! Shuyaku Soudatsusen (Japan).sfc")
CLEAN_SHA1 = "bc0e29ee383574443226695215496eb0d09aaa1c"
SITE = 0x188E9              # LDA #$0B00  (dash X-speed)
OLD = bytes.fromhex("a9000b")
NEW_SPEED = 0x0640          # 6.25 px/f  (~ -1/3 distance: 121px -> 82px)

def build(src_path, out_path, speed=NEW_SPEED):
    data = bytearray(open(src_path, "rb").read())
    assert data[SITE:SITE+3] == OLD, f"dash-speed site: {data[SITE:SITE+3].hex()}"
    data[SITE+1] = speed & 0xFF
    data[SITE+2] = (speed >> 8) & 0xFF
    # header + checksum (only matters for a standalone base image; harmless when stacked)
    if data[0xFFC0:0xFFC8] == b"\xBE\xB0\xD7\xB0\xD1\xB0\xDDS":
        pass  # keep whatever title/header the input already has
    _fix_checksum(data)
    open(out_path, "wb").write(data)
    print(f"wrote {out_path} from {src_path}: dash speed 0x0B00->{speed:#06x}, "
          f"sha1={sha1(bytes(data)).hexdigest()}")

def _fix_checksum(data):
    size = len(data); chk_size = 0x80000
    while chk_size <= size: chk_size <<= 1
    if chk_size == size:
        chk = sum(data)
    else:
        cd = data[chk_size//2:]
        while len(cd) < chk_size//2: cd += cd[len(cd)-chk_size:]
        chk = sum(data[:chk_size//2]) + sum(cd)
    data[0xFFDE] = chk & 0xFF; data[0xFFDF] = chk >> 8 & 0xFF
    data[0xFFDC] = data[0xFFDE] ^ 0xFF; data[0xFFDD] = data[0xFFDF] ^ 0xFF

if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description="Uranus forward-dash distance nerf (via X-speed).")
    ap.add_argument("src", nargs="?", default=CLEAN, help="input ROM (clean or a combined build)")
    ap.add_argument("out", nargs="?", default=str(REPO / "build/sms_dashdist.sfc"), help="output ROM path")
    ap.add_argument("--speed", type=lambda s: int(s, 0), default=NEW_SPEED,
                    help="dash X-speed (8.8 fixed-point). 0x0B00=vanilla 121px, 0x0780~98px (-1/5), "
                         "0x0640=82px (-1/3, default), 0x0480=59px (-1/2). Lower = shorter dash.")
    a = ap.parse_args()
    if a.src == CLEAN:
        assert sha1(open(a.src, "rb").read()).hexdigest() == CLEAN_SHA1, "clean hash mismatch"
    build(a.src, a.out, a.speed)
