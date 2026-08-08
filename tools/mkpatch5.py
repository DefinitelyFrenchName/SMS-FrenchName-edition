#!/usr/bin/env python3
"""Patch 5: reduce Uranus's forward-dash travel distance.

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
sys.path.insert(0, str(REPO / "tools"))
from smspaths import clean_rom, require_source, check_not_inplace, fix_checksum  # ROM location: $SMS_ROM_DIR -> roms/ -> ../roms/
CLEAN = clean_rom()

# Detection fingerprint (p5) — consumed by tools/mksigs.py to generate the
# regression suite's SIGS table. ONLY bytes invariant across stub-layout and
# bank-stacking changes: the DEFAULT dash speed 0x0640 — a --speed retune changes these bytes; rerun
# tools/mksigs.py --write after retuning or detection reads p5 absent
SIG = [(0x188EA, 0x40), (0x188EB, 0x06)]
SITE = 0x188E9              # LDA #$0B00  (dash X-speed)
OLD = bytes.fromhex("a9000b")
NEW_SPEED = 0x0640          # 6.25 px/f  (~ -1/3 distance: 121px -> 82px)

SPEED_MIN, SPEED_MAX = 0x0400, 0x0B00      # -1/2 .. vanilla, the tested band


def build(src_path, out_path, speed=NEW_SPEED):
    # The two stores below MASK, so an out-of-range value used to write a
    # silently wrong dash speed (#91). Reject what cannot be represented; only
    # warn outside the tested band, which is a legitimate thing to experiment
    # with and not ours to forbid.
    if not 0 < speed <= 0xFFFF:
        raise SystemExit(f"error: --speed {speed:#x} does not fit the 16-bit fixed-point "
                         f"field (expected 0 < speed <= 0xffff)")
    if not SPEED_MIN <= speed <= SPEED_MAX:
        print(f"warning: --speed {speed:#06x} is outside the tested band "
              f"{SPEED_MIN:#06x}..{SPEED_MAX:#06x} (vanilla is 0x0b00) — building anyway")
    data = bytearray(open(src_path, "rb").read())
    if not (data[SITE:SITE+3] == OLD):
        raise ValueError(f"dash-speed site: {data[SITE:SITE+3].hex()}")
    data[SITE+1] = speed & 0xFF
    data[SITE+2] = (speed >> 8) & 0xFF
    # keep whatever title/header the input already has; just refresh the checksum
    fix_checksum(data)
    open(out_path, "wb").write(data)
    print(f"wrote {out_path} from {src_path}: dash speed 0x0B00->{speed:#06x}, "
          f"sha1={sha1(bytes(data)).hexdigest()}")


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description="Uranus forward-dash distance nerf (via X-speed).")
    ap.add_argument("src", nargs="?", default=CLEAN, help="input ROM (clean or a combined build)")
    ap.add_argument("out", nargs="?", default=str(REPO / "build/sms_dashdist.sfc"), help="output ROM path")
    ap.add_argument("--speed", type=lambda s: int(s, 0), default=NEW_SPEED,
                    help="dash X-speed (8.8 fixed-point). 0x0B00=vanilla 121px, 0x0780~98px (-1/5), "
                         "0x0640=82px (-1/3, default), 0x0480=59px (-1/2). Lower = shorter dash.")
    ap.add_argument("--stacked", action="store_true",
                    help="src is an already-patched ROM (builder chaining); skips the clean-SHA gate")
    a = ap.parse_args()
    check_not_inplace(a.src, a.out)
    require_source(a.src, a.stacked)
    build(a.src, a.out, a.speed)
