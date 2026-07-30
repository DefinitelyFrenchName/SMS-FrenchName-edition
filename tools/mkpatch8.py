#!/usr/bin/env python3
"""Patch 8 (OPTIONAL): make Sailor Venus's 6HP throw mash-escapable on a standard schedule.

Throws in this game are escaped ("teched") by MASHING attack buttons while held, not by a
one-press window: during the hold animation, script steps whose entry byte5 != 0 sample the
victim's freshly-pressed attack buttons (+0x50 & 0xF0) once per frame and increment the
thrower's mash counter (+0x56) at $C1:07CF-07DC; at the toss, $C1:0823 compares the counter
against a global threshold of 2 -> escape (act 0x23, HALF damage) instead of the full throw.

The per-throw "tech window" is therefore the summed duration of the hold steps that sample.
Measured on clean (connect at t=60, an 8-frame engine freeze covers t=62-69):
  Venus 6HP  hold script $C1:6C53: samples t=61 + t=70-75  ->  6-frame window
  Jupiter 6HP hold script $C1:5A07: samples t=61 + t=70-84 -> 15-frame window (standard)
Venus's window is so short that a defender must start mashing within ~1 frame of the grab
(mash-start deadline connect+12 at a 2f press cadence, vs Jupiter's connect+21) — virtually
untechable in practice. Community frame data (Dustloop) agrees: ~6f window vs standard 14-19.

The fix: enable sampling on later hold steps by setting their script-entry byte5 from 00->01.
Each extra step extends the window by that step's animation length (no damage, position, or
timing side effects — byte5 in hold steps is ONLY the sampling gate; the damage byte lives in
the header entry at $6C53+0, untouched):
  --extra 0: vanilla        6-frame window (t=70-75)
  --extra 1: DEFAULT       13-frame window (t=70-82)  — closest to the 12f target the step
             granularity allows; keeps a small edge on the standard 15 (original intent)
  --extra 2:               19-frame window (t=70-88)
  --extra 3:               24-frame window (t=70-93, the whole hold)

Verified in-emulator (techsweep.lua): mash-start deadline moves connect+12 -> connect+19
(Jupiter: +21); unmashed throw identical (same damage 22, same toss frame, same animation).
"""
import argparse
from hashlib import sha1

from pathlib import Path as _P
REPO = _P(__file__).resolve().parent.parent  # repo root (cwd-independent)
import sys
sys.path.insert(0, str(REPO / "tools"))
from smspaths import clean_rom, require_source, check_not_inplace, fix_checksum  # ROM location: $SMS_ROM_DIR -> roms/ -> ../roms/
CLEAN = clean_rom()

# Detection fingerprint (p8) — consumed by tools/mksigs.py to generate the
# regression suite's SIGS table. ONLY bytes invariant across stub-layout and
# bank-stacking changes: the DEFAULT --extra 1 script byte; rerun mksigs --write after retuning
SIG = [(0x16C70, 0x01)]
CLEAN_SHA1 = "bc0e29ee383574443226695215496eb0d09aaa1c"

# Venus throw-hold animation script at $C1:6C53 (file 0x16C53), 8-byte entries per anim step.
# Hold steps = entries 1..5; byte5 of each entry gates mash sampling for that step.
SCRIPT = 0x16C53
EXTRA_OFFS = [SCRIPT + 8 * e + 5 for e in (3, 4, 5)]   # 0x16C70, 0x16C78, 0x16C80

def build(src, out, extra):
    data = bytearray(open(src, "rb").read())
    for off in EXTRA_OFFS:
        if not (data[off] == 0x00):
            raise ValueError(f"script byte5 at 0x{off:05X}: {data[off]:02X} (expected 00)")
    for off in EXTRA_OFFS[:extra]:
        data[off] = 0x01
    fix_checksum(data)
    open(out, "wb").write(data)
    win = {0: "6f (vanilla)", 1: "13f", 2: "19f", 3: "24f"}[extra]
    print(f"wrote {out} from {src}: Venus 6HP tech window {win} "
          f"({extra} extra sampling step(s)), sha1={sha1(bytes(data)).hexdigest()}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Make Venus 6HP throw mash-escapable (standard-ish window).")
    ap.add_argument("src", nargs="?", default=CLEAN, help="input ROM (clean or a combined build)")
    ap.add_argument("out", nargs="?", default=str(REPO / "build/sms_venustech.sfc"), help="output ROM path")
    ap.add_argument("--extra", type=int, default=1, choices=(0, 1, 2, 3),
                    help="extra sampling steps: 0=vanilla 6f, 1=13f (default), 2=19f, 3=24f")
    ap.add_argument("--stacked", action="store_true",
                    help="src is an already-patched ROM (builder chaining); skips the clean-SHA gate")
    a = ap.parse_args()
    check_not_inplace(a.src, a.out)
    require_source(a.src, a.stacked)
    build(a.src, a.out, a.extra)
