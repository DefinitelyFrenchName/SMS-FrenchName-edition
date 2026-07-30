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

Restructured 2026-07-30 (issue #14): main() guard (no work at import), unconditional
SHA gate with --stacked for chaining, src!=out guard, and the header checksum is now
fixed like every other builder (standalone ROM/BPS hashes changed accordingly).
"""
import argparse
import hashlib
import sys

from pathlib import Path as _P
REPO = _P(__file__).resolve().parent.parent  # repo root (cwd-independent)
sys.path.insert(0, str(REPO / "tools"))
from smspaths import clean_rom, require_source, check_not_inplace  # ROM location: $SMS_ROM_DIR -> roms/ -> ../roms/
CLEAN = clean_rom()


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


def build(src, out):
    rom = bytearray(open(src, "rb").read())

    # call site inside dash handler step-0: jsr $0389 -> jsr $BE2A
    if rom[0x188EC:0x188EF] != bytes.fromhex("208903"):
        raise ValueError(f"unexpected call-site bytes: {rom[0x188EC:0x188EF].hex()}")
    rom[0x188EC:0x188EF] = bytes.fromhex("202ABE")

    # stub at $C1:BE2A (file 0x1BE2A), previously zero
    if rom[0x1BE2A:0x1BE32] != bytes(8):
        raise ValueError("stub area not clean")
    stub = bytes([0x20, 0x89, 0x03,  # jsr $0389   (original call, 16-bit A preserved)
                  0xE2, 0x20,        # sep #$20
                  0x74, 0x46,        # stz $46,X   (the missing hurt-state clear)
                  0x60])             # rts
    rom[0x1BE2A:0x1BE2A + len(stub)] = stub

    _fix_checksum(rom)
    open(out, "wb").write(rom)
    print(f"wrote {out} from {src} sha1={hashlib.sha1(rom).hexdigest()}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Patch 2: remove reversal-dash invincibility.")
    ap.add_argument("src", nargs="?", default=CLEAN)
    ap.add_argument("out", nargs="?", default=str(REPO / "build/sms_dashfix.sfc"))
    ap.add_argument("--stacked", action="store_true",
                    help="src is an already-patched ROM (builder chaining); skips the clean-SHA gate")
    a = ap.parse_args()
    check_not_inplace(a.src, a.out)
    require_source(a.src, a.stacked)
    build(a.src, a.out)
