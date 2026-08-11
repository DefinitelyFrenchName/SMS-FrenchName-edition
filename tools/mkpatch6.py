#!/usr/bin/env python3
"""Patch 6 (OPTIONAL): make Uranus's forward dash invulnerable for all but its
first two and last two frames.

Compensates the -1/3 forward-dash distance nerf (patch 5) with a defensive
window, WITHOUT re-introducing the reversal-dash bug patch 2 fixed (that was the
+0x46 flag; this is a different mechanism). Off by default.

Mechanism (measured): invulnerability in this engine = an EMPTY hurtbox (index
0). The back-dash is invincible for all its frames precisely because its
animation uses hurtbox index 0; the forward dash keeps a real hurtbox (0x4F) the
whole way. The per-frame box writer at $C0:9CCD does `sta $41,X` from the
animation table, so the hook goes there:

  0x09CCD: `95 41 B1 10` (sta $41,X ; lda ($10),Y)  ->  `22 85 BE C1` (jsl $C1:BE85)

⚠ THE OLD --lo/--hi WINDOW WAS NOT MEASURING DASH FRAMES, and the knobs are gone
with it. It gated on +0x5D, described here as "the dash-frame counter (1..14)".
+0x5D is really the motion recognizer's timer for motion 1, it free-runs and
RESETS at $0F ($C1:1618), and its value on the dash's first frame depends on the
INPUT RHYTHM: measured 04 with the second tap 9 frames after the first, 06 with
it 11 frames after. It also wraps mid-dash (04..0F,00,01). So the shipped
"frames 5..10" was really "dash frames 2..7 if you tapped one way, something
else if you tapped another" -- a window that moved with the player's hands.

What the dash actually is, measured frame by frame on the clean ROM:

  frame  1     step 0, still grounded, velocities not yet set
  frame  2     airborne, vy -320 (the hop), +0x06 still 0
  frames 3-12  airborne, +0x06 = $80 (the animation is `1f pose $70 | HOLD`),
               vy climbing -256 -> +320 under gravity 64
  frame 13     airborne, vy +384
  frame 14     grounded again, vy 0

which gives the requested window with no frame counter at all:

  +0x06 == 0        -> the first two frames      (skip)
  +0x16 bit7 set    -> the last frame, grounded  (skip)
  vy >= +384        -> the frame before landing  (skip)
  otherwise         -> hurtbox 0, invulnerable   (frames 3..12)

Strike-only, exactly like the back-dash: the collision/throw box is untouched,
so throws still catch her. The vy threshold is safe against patch 5, which
changes the dash's X velocity only -- vy (-320) and gravity ($40) are set by the
same handler and asserted below.
"""
import sys
import argparse
from hashlib import sha1

from pathlib import Path as _P
REPO = _P(__file__).resolve().parent.parent  # repo root (cwd-independent)
sys.path.insert(0, str(REPO / "tools"))
from smspaths import clean_rom, require_source, check_not_inplace, fix_checksum  # ROM location: $SMS_ROM_DIR -> roms/ -> ../roms/
CLEAN = clean_rom()

# Detection fingerprint (p6) — consumed by tools/mksigs.py to generate the
# regression suite's SIGS table. ONLY bytes invariant across stub-layout and
# bank-stacking changes: jsl $C1:BE85 at the box-index writer (stub address is FIXED)
SIG = [(0x9CCD, 0x22), (0x9CCE, 0x85), (0x9CCF, 0xBE)]

HOOK = 0x09CCD                       # sta $41,X ; lda ($10),Y   (C0:9CCD)
HOOK_OLD = bytes.fromhex("9541b110")
STUB = 0x1BE85                       # C1:BE85 (69-byte free block)
JSL = bytes([0x22, 0x85, 0xBE, 0xC1])  # jsl $C1:BE85

# ⚠ TWO THINGS THE FIRST BUILD GOT WRONG, both measured rather than reasoned:
#   * the compare must be SIGNED. `cmp #$0180` on a 16-bit vy treats the rising
#     half of the hop (vy negative, $FEC0..$FFC0) as a huge unsigned number, so
#     every frame before the apex was skipped and the window came out 8..13.
#   * the stub sees the PREVIOUS frame's velocity. The box writer runs before the
#     physics, so at dash frame N it reads the vy that frame N-1 ended with --
#     which is why the threshold is +320 (frame 12's value) and not +384
#     (frame 13's). The same one-frame lag is what makes the GROUNDED test
#     exclude frames 1 AND 2 at the start: at frame 2 it still sees frame 1
#     standing on the floor.
VY_LAND = 0x0140                     # +320: the value the frame before landing ends with


def build_stub():
    # every branch targets the shared exit "skip" (the displaced `lda ($10),Y`)
    # at offset 37; the layout is fixed, so these offsets are constants.
    return bytes([
        0x95, 0x41,              # sta $41,X      ; displaced hurtbox store
        0xB5, 0x00,              # lda $00,X      ; charID
        0xC9, 0x06,              # cmp #$06
        0xD0, 0x1D,              # bne skip       ; not Uranus
        0xB5, 0x01,              # lda $01,X      ; action
        0xC9, 0x60,              # cmp #$60
        0xD0, 0x17,              # bne skip       ; not the forward dash
        0xB5, 0x16,              # lda $16,X
        0x29, 0x80,              # and #$80       ; grounded: dash frames 1, 2 and 14
        0xD0, 0x11,              # bne skip
        0xB5, 0x33,              # lda $33,X      ; vy HIGH byte, still 8-bit
        0x30, 0x0B,              # bmi invuln     ; negative = rising, always invulnerable
        0xC2, 0x20,              # rep #$20
        0xB5, 0x32,              # lda $32,X      ; vy, 16-bit
        0xC9, VY_LAND & 0xFF, VY_LAND >> 8,       # cmp #$0140
        0xE2, 0x20,              # sep #$20       ; SEP leaves carry alone
        0xB0, 0x02,              # bcs skip       ; about to land
        # invuln:
        0x74, 0x41,              # stz $41,X      ; empty hurtbox => invulnerable
        # skip:
        0xB1, 0x10,              # lda ($10),Y    ; displaced collbox load
        0x6B,                    # rtl
    ])

# The dash handler's own constants, which the vy threshold depends on. If a
# future patch retunes the hop, this must fail rather than silently shift the
# window: $C1:88DF `lda #$FEC0` (vy -320) and $C1:88E4 `lda #$0040` (gravity).
DASH_VY = (0x188DF, bytes.fromhex("a9c0fe"))
DASH_GRAV = (0x188E4, bytes.fromhex("a94000"))


def build(src, out):
    data = bytearray(open(src, "rb").read())
    if not (data[HOOK:HOOK+4] == HOOK_OLD):
        raise ValueError(f"hook site: {data[HOOK:HOOK+4].hex()}")
    for off, want in (DASH_VY, DASH_GRAV):
        if bytes(data[off:off+3]) != want:
            raise ValueError(f"the dash hop changed at 0x{off:05X}: "
                             f"{bytes(data[off:off+3]).hex()} != {want.hex()} -- the "
                             "invulnerability window is derived from vy and gravity")
    stub = build_stub()
    if not (data[STUB:STUB+len(stub)] == bytes(len(stub))):
        raise ValueError("stub area not clean")
    data[HOOK:HOOK+4] = JSL
    data[STUB:STUB+len(stub)] = stub
    fix_checksum(data)
    open(out, "wb").write(data)
    print(f"wrote {out} from {src}: fwd-dash invulnerable except the first two "
          f"and last two frames, sha1={sha1(bytes(data)).hexdigest()}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("src", nargs="?", default=CLEAN)
    ap.add_argument("out", nargs="?", default=str(REPO / "build/sms_dashinvuln.sfc"))
    # --lo/--hi are GONE, not defaulted: they gated on +0x5D, which is the motion
    # recognizer's free-running timer and not a dash-frame counter, so the window
    # they named moved with the player's input rhythm. See the module docstring.
    ap.add_argument("--stacked", action="store_true",
                    help="src is an already-patched ROM (builder chaining); skips the clean-SHA gate")
    a = ap.parse_args()
    check_not_inplace(a.src, a.out)
    require_source(a.src, a.stacked)
    build(a.src, a.out)
