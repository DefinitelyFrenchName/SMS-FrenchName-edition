#!/usr/bin/env python3
"""Patch 6 (OPTIONAL): give Uranus's forward dash a short mid-move invulnerability window.

Compensates the -1/3 forward-dash distance nerf (patch 5) with a small defensive window,
WITHOUT re-introducing the reversal-dash bug patch 2 fixed (that was the +0x46 flag; this is
a different mechanism). Off by default — a separate stackable patch.

Mechanism (measured): invulnerability in this engine = an EMPTY hurtbox (hurtbox index 0).
The back-dash is invincible for all 14 frames precisely because its animation uses hurtbox
index 0; the forward dash keeps a real hurtbox (0x4F) the whole way. The per-frame box writer
at $C0:9CCD does `sta $41,X` (hurtbox idx) from the animation table. We hook right there:

  0x09CCD: `95 41 B1 10` (sta $41,X ; lda ($10),Y)  ->  `22 85 BE C1` (jsl $C1:BE85)

Stub at $C1:BE85 does the displaced store, then — only for Uranus (charID +0x00 == 6) in a
forward dash (act +0x01 == 0x60) whose dash-frame counter (+0x5D, the 66 recognizer timer,
which runs 1..14 across the dash) is within [LO,HI] — forces the hurtbox to 0 (invulnerable),
then does the displaced collbox load and returns. Strike-only invuln, exactly like the
back-dash (the collision/throw box is untouched, so throws still catch her).

Default window = dash frames 5..10 (six frames of strike invuln mid-dash). Tunable via
--lo/--hi. Byte-disjoint from patches 1-5 (hook in bank $C0 at 0x9CCD; stub in the C1:BE85
free block, clear of the 1f-link/dashfix stubs at BE20-31). Builds from any input ROM.
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

HOOK = 0x09CCD                       # sta $41,X ; lda ($10),Y   (C0:9CCD)
HOOK_OLD = bytes.fromhex("9541b110")
STUB = 0x1BE85                       # C1:BE85 (69-byte free block)
JSL = bytes([0x22, 0x85, 0xBE, 0xC1])  # jsl $C1:BE85

def build_stub(lo, hi):
    # branches all target the shared exit label "skip" (the displaced `lda ($10),Y`).
    # layout is fixed-size, so the offsets below are constant regardless of lo/hi values.
    return bytes([
        0x95, 0x41,        # sta $41,X          ; displaced hurtbox store
        0xB5, 0x00,        # lda $00,X          ; charID
        0xC9, 0x06,        # cmp #$06
        0xD0, 0x12,        # bne skip           ; not Uranus
        0xB5, 0x01,        # lda $01,X          ; action
        0xC9, 0x60,        # cmp #$60
        0xD0, 0x0C,        # bne skip           ; not forward dash
        0xB5, 0x5D,        # lda $5D,X          ; dash-frame counter (1..14)
        0xC9, lo,          # cmp #LO
        0x90, 0x06,        # bcc skip           ; frame < LO
        0xC9, hi + 1,      # cmp #HI+1
        0xB0, 0x02,        # bcs skip           ; frame > HI
        0x74, 0x41,        # stz $41,X          ; empty hurtbox => invulnerable
        # skip:
        0xB1, 0x10,        # lda ($10),Y        ; displaced collbox load
        0x6B,              # rtl
    ])

def build(src, out, lo, hi):
    data = bytearray(open(src, "rb").read())
    assert data[HOOK:HOOK+4] == HOOK_OLD, f"hook site: {data[HOOK:HOOK+4].hex()}"
    stub = build_stub(lo, hi)
    assert data[STUB:STUB+len(stub)] == bytes(len(stub)), "stub area not clean"
    data[HOOK:HOOK+4] = JSL
    data[STUB:STUB+len(stub)] = stub
    _fix_checksum(data)
    open(out, "wb").write(data)
    print(f"wrote {out} from {src}: fwd-dash invuln frames {lo}-{hi}, sha1={sha1(bytes(data)).hexdigest()}")

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
    ap = argparse.ArgumentParser()
    ap.add_argument("src", nargs="?", default=CLEAN)
    ap.add_argument("out", nargs="?", default=str(REPO / "build/sms_dashinvuln.sfc"))
    ap.add_argument("--lo", type=lambda s: int(s, 0), default=5, help="first invuln dash-frame (default 5)")
    ap.add_argument("--hi", type=lambda s: int(s, 0), default=10, help="last invuln dash-frame (default 10)")
    ap.add_argument("--stacked", action="store_true",
                    help="src is an already-patched ROM (builder chaining); skips the clean-SHA gate")
    a = ap.parse_args()
    assert 1 <= a.lo <= a.hi <= 14, "window must be within dash frames 1..14"
    check_not_inplace(a.src, a.out)
    require_source(a.src, a.stacked)
    build(a.src, a.out, a.lo, a.hi)
