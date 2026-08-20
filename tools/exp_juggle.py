#!/usr/bin/env python3
"""EXPERIMENT (not a numbered patch): JUGGLES — launched victims stay
targetable.

    python3 tools/exp_juggle.py <out.sfc> [src --stacked]

Phase 6 of the anime-fighter feasibility programme, on gate G1's best-case
branch. Phase 0 proved the whole re-hit pipeline works once +0x46 bit7 is
clear (hit resolves at the $C0:C00A gate, the AIR reaction row re-dispatches
coherently, fresh launch velocities land). This build makes that real with
TWO BYTES — the +0x46 write census over the reaction-handler region
($C1:0E80-$1200) found exactly 18 immediate `lda #vv / sta $46,X` writers
(10x #$20 ground stuns, 6x #$A0, 2x #$E0 throws) and the six #$A0 handlers
stage, in order: act 0x19 (knockdown), 0x1B (LAUNCH), 0x1A (heavy knockdown),
0x18 (electric), 0x17 (flame), 0x16 (AIR HITSTUN). Flipped here:

  0x010FA9  A0 -> 20   the act-0x1B LAUNCH handler ($C1:0FA8)
  0x0110A1  A0 -> 20   the act-0x16 AIR-HITSTUN handler ($C1:10A0)

Knockdowns (0x19/0x1A), flame/electric (0x17/0x18) and the throw states
(0xE0) keep their protection; the landing handler still clears +0x46 on
touchdown, and hit resolution is untouched.

⚠ These handlers are GLOBAL — every character's launches change [SMS-4].
That is the point of a total-conversion experiment and is why this stays
exp-tier until the maintainer rules on the policy (infinite-juggle bound,
OTG rules for a 1B landing, whether flame/electric should juggle too).

Verify: tools/probe_juggle.lua MODE=clean (pinned) on this build — the
re-hits that needed +0x46 pokes on the clean ROM must now happen with NO
pokes; the same run on the clean ROM stays at zero.
"""
import argparse
import hashlib
import sys
from pathlib import Path as _P

REPO = _P(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
from smspaths import clean_rom, require_source, check_not_inplace, fix_checksum

EDITS = (
    (0x010FA9, "act 0x1B launch handler ($C1:0FA8)"),
    (0x0110A1, "act 0x16 air-hitstun handler ($C1:10A0)"),
)


def build(src, out):
    rom = bytearray(open(src, "rb").read())
    for off, name in EDITS:
        if rom[off - 1] != 0xA9 or rom[off] != 0xA0 or rom[off + 1:off + 3] != bytes([0x95, 0x46]):
            raise ValueError(f"{name}: expected lda #$A0 / sta $46,X at 0x{off - 1:06X}")
        rom[off] = 0x20
        print(f"  {name}: lda #$A0 -> lda #$20 at 0x{off:06X}")
    fix_checksum(rom)
    open(out, "wb").write(rom)
    print(f"wrote {out} from {src} sha1={hashlib.sha1(rom).hexdigest()}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="EXPERIMENT: juggle-enable launch/air-hitstun reactions.")
    ap.add_argument("out")
    ap.add_argument("src", nargs="?", default=None)
    ap.add_argument("--stacked", action="store_true")
    a = ap.parse_args()
    src = a.src or clean_rom()
    require_source(src, stacked=a.stacked)
    check_not_inplace(src, a.out)
    build(src, a.out)
