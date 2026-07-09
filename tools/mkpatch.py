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
  GATE 0x04 -> dash-out 100 (+6 frames = final] [1f link]
"""
import hashlib
import sys

CLEAN = "Bishoujo Senshi Sailormoon S - Jougai Rantou! Shuyaku Soudatsusen (Japan).sfc"
CLEAN_SHA1 = "bc0e29ee383574443226695215496eb0d09aaa1c"

gate = int(sys.argv[1], 0) if len(sys.argv) > 1 else 0x04
out = sys.argv[2] if len(sys.argv) > 2 else "build/sms_patched.sfc"

rom = bytearray(open(CLEAN, "rb").read())
assert hashlib.sha1(rom).hexdigest() == CLEAN_SHA1, "clean ROM hash mismatch"

# call site: jsr $0952 -> jsr $BE20
assert rom[0x1874C:0x1874F] == bytes.fromhex("205209"), rom[0x1874C:0x1874F].hex()
rom[0x1874C:0x1874F] = bytes.fromhex("2020BE")

# stub at $C1:BE20 (file 0x1BE20), previously zero
assert rom[0x1BE14:0x1BE34] == bytes(0x20), "stub area not clean"
stub = bytes([0xE2, 0x20,        # sep #$20
              0xC9, gate,        # cmp #GATE
              0xB0, 0x03,        # bcs +3 (to rts)
              0x4C, 0x52, 0x09,  # jmp $0952
              0x60])             # rts
rom[0x1BE20:0x1BE20 + len(stub)] = stub

open(out, "wb").write(rom)
print(f"wrote {out} gate=0x{gate:02X} sha1={hashlib.sha1(rom).hexdigest()}")
