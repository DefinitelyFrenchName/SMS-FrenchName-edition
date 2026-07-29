#!/usr/bin/env python3
"""Dash-fix: add the missing `stz $46,X` to Uranus's forward-dash (act 0x60)
handler step-0 init at $C1:88C8.

Root cause: knockdown sets player+0x46 = 0xA0 (untargetable). Every other
action handler (all attacks; other characters' dashes, e.g. Moon's) clears
+0x46 in its step-0 init. Uranus's dash handler lacks the clear, so a reversal
dash keeps knockdown invincibility for its entire duration.

Patch:
  0x188ED/EE: jsr $0389 -> jsr $BE2A   (step-0-only X-speed call, rerouted)
  0x1BE2A:    stub: jsr $0389 / sep #$20 / stz $46,X / rts
Byte-disjoint from the 1f-link patch (0x1874D/E, 0x1BE20-29) - both stack.
"""
import hashlib
import sys

from pathlib import Path as _P
REPO = _P(__file__).resolve().parent.parent  # repo root (cwd-independent)
CLEAN = str(REPO / "roms/Bishoujo Senshi Sailormoon S - Jougai Rantou! Shuyaku Soudatsusen (Japan).sfc")
CLEAN_SHA1 = "bc0e29ee383574443226695215496eb0d09aaa1c"

src = sys.argv[1] if len(sys.argv) > 1 else CLEAN
out = sys.argv[2] if len(sys.argv) > 2 else str(REPO / "build/sms_dashfix.sfc")

rom = bytearray(open(src, "rb").read())
if src == CLEAN:
    assert hashlib.sha1(rom).hexdigest() == CLEAN_SHA1, "clean ROM hash mismatch"

# call site inside dash handler step-0: jsr $0389 -> jsr $BE2A
assert rom[0x188EC:0x188EF] == bytes.fromhex("208903"), rom[0x188EC:0x188EF].hex()
rom[0x188EC:0x188EF] = bytes.fromhex("202ABE")

# stub at $C1:BE2A (file 0x1BE2A), previously zero
assert rom[0x1BE2A:0x1BE32] == bytes(8), "stub area not clean"
stub = bytes([0x20, 0x89, 0x03,  # jsr $0389   (original call, 16-bit A preserved)
              0xE2, 0x20,        # sep #$20
              0x74, 0x46,        # stz $46,X   (the missing hurt-state clear)
              0x60])             # rts
rom[0x1BE2A:0x1BE2A + len(stub)] = stub

open(out, "wb").write(rom)
print(f"wrote {out} from {src} sha1={hashlib.sha1(rom).hexdigest()}")
