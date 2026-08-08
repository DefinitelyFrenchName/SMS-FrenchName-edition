#!/usr/bin/env python3
"""Build patched ROM: gate Uranus 2HP (act 0x55) dash/command-cancel on step tick.

Patch:
  0x1874C: jsr $0952 -> jsr $BE20   (inside Uranus 2HP running-state handler $C1:8744+)
  0x1BE20: stub: sep #$20 / cmp #GATE / bcs +3 / jmp $0952 / rts
A holds the current step tick ($06,X) on entry (returned by helper $C1:04DA).
Cancel commit allowed only when tick < GATE. Vanilla behavior = always allowed.
GATE meanings (on-hit, hit at t=85, hitstop 8, tick 0A..00 at t=94..104):
  GATE 0x0B -> unchanged (tick always < 0x0B)   [sanity]
  GATE 0x09 -> dash-out 95 (+1 frame)           [proof]
  GATE 0x05 -> dash-out 99 (+5 frames)          [1f link, TRUE COMBO — patch 1b, alt]
  GATE 0x04 -> dash-out 100 (+6 frames)         [1f link, 1-frame MEATY — patch 1, default]
  GATE 0x03 -> dash-out 101 (+7 frames)         [loop removed entirely]
N.B. lower gate = more recovery. 0x04 (N=6, canonical) makes the single connecting press a
MEATY on the defender's first actionable frame — unblockable by holding back (hit beats
same-frame block), escapable only by a frame-1/2-invincible reversal. 0x05 (N=5) shifts one
frame earlier so it lands in hitstun (guaranteed true combo, but a 2-frame connect window).
See docs/patch_notes.md "Patch 1" / "Patch 1b".

Always builds FROM THE CLEAN ROM (this is the chain's first patch by design).
Restructured 2026-07-30 (issue #14): main() guard (no work at import), the clean-ROM
SHA gate raises (not assert), and the header checksum is now fixed like every other
builder (standalone ROM/BPS hashes changed accordingly).
"""
import argparse
import hashlib
import sys

from pathlib import Path as _P
REPO = _P(__file__).resolve().parent.parent  # repo root (cwd-independent)
sys.path.insert(0, str(REPO / "tools"))
from smspaths import clean_rom, require_source, check_not_inplace, fix_checksum  # ROM location: $SMS_ROM_DIR -> roms/ -> ../roms/
CLEAN = clean_rom()

# Detection fingerprint (p1) — consumed by tools/mksigs.py to generate the
# regression suite's SIGS table. ONLY bytes invariant across stub-layout and
# bank-stacking changes: jsr $BE20 operand + stub cmp opcode (stub address is FIXED); the gate byte at
# 0x1BE23 is deliberately excluded — the suite reads it separately (0x04/0x05, #29)
SIG = [(0x1874D, 0x20), (0x1874E, 0xBE), (0x1BE22, 0xC9)]




def build(gate, out):
    rom = bytearray(open(CLEAN, "rb").read())

    # call site: jsr $0952 -> jsr $BE20
    if rom[0x1874C:0x1874F] != bytes.fromhex("205209"):
        raise ValueError(f"unexpected call-site bytes: {rom[0x1874C:0x1874F].hex()}")
    rom[0x1874C:0x1874F] = bytes.fromhex("2020BE")

    # stub at $C1:BE20 (file 0x1BE20), previously zero
    if rom[0x1BE14:0x1BE34] != bytes(0x20):
        raise ValueError("stub area not clean")
    stub = bytes([0xE2, 0x20,        # sep #$20
                  0xC9, gate,        # cmp #GATE
                  0xB0, 0x03,        # bcs +3 (to rts)
                  0x4C, 0x52, 0x09,  # jmp $0952
                  0x60])             # rts
    rom[0x1BE20:0x1BE20 + len(stub)] = stub

    fix_checksum(rom)
    open(out, "wb").write(rom)
    print(f"wrote {out} gate=0x{gate:02X} sha1={hashlib.sha1(rom).hexdigest()}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(
        description="Patch 1/1b: gate the Uranus 2HP dash-cancel (always builds from the clean ROM).")
    ap.add_argument("gate", nargs="?", default="0x04",
                    help="cancel gate tick (hex ok): 0x04=meaty (canonical), 0x05=true combo, 0x03=removed")
    ap.add_argument("out", nargs="?", default=str(REPO / "build/sms_patched.sfc"))
    a = ap.parse_args()
    gate = int(a.gate, 0)
    if not 0x00 <= gate <= 0x0B:
        raise SystemExit(f"error: gate {gate:#x} out of range 0x00..0x0B")
    check_not_inplace(CLEAN, a.out)
    require_source(CLEAN)   # unconditional clean-SHA gate
    build(gate, a.out)
