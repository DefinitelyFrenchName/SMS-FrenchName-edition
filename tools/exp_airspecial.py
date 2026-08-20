#!/usr/bin/env python3
"""EXPERIMENT (not a numbered patch): AIR-ENABLE two existing ground specials.

    python3 tools/exp_airspecial.py <out.sfc>

Phase 2 of the anime-fighter feasibility programme (gate G3): what does a
GROUND-special handler do when its act starts AIRBORNE? If the answer is
"something coherent", air specials for the whole roster are table appends plus
route insertion; if handlers hard-assume the ground, air specials must be
authored acts (the exp_airbackdash 0x2B/0x2C pattern).

THE EDIT IS FOUR FLAG BYTES — bit0 (ground-only) cleared, everything else kept:

  Venus  236P Crescent Beam  entries 2/3 (acts 5B/5C)  flags 05 -> 04
  Moon   236P                entries 4/5 (acts 61/62)  flags 05 -> 04

  0x016C23 / 0x016C25   Venus $C1:6C1F + entry*2 (flag = the low byte)
  0x012834 / 0x012836   Moon  $C1:282C + entry*2

Why these two: both characters' jump handlers already end with
`ldy #<table> / jsr $0958` (tools/census_airroutes.py — Venus $6C1F, Moon
$282C), so no route insertion is needed and the measurement isolates HANDLER
PHYSICS from everything else. Why clearing bit0 is safe HERE when it was the
measured trap for the backdash (see exp_airbackdash.py "THE ROUTE NOT TAKEN"):
the re-fire loop needs the started act to re-offer its own start route within
the ~2-frame +0x51 latch (measured, traces/airphys_airspec_d8.txt), and these
entries keep bit2 — the projectile-slot gate — so a retry after the projectile
spawns is rejected by the engine's own data. The probe still watches for step
pinning, and the grounded A/B control must stay frame-identical.

Verify: tools/probe_exp_airspecial.lua on this build (air start + grounded
A/B) and on the clean ROM (negative: the same air input produces nothing).
"""
import argparse
import hashlib
import sys
from pathlib import Path as _P

REPO = _P(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
from smspaths import clean_rom, require_source, check_not_inplace, fix_checksum

# --- measured against the clean ROM; file offset = SNES & 0x3FFFFF
EDITS = (
    # (offset, expected act at offset+1, expected old flags, name)
    # projectile family — bit2 (slot gate) kept, self-guarding against re-fire:
    (0x016C23, 0x5B, 0x05, "Venus 236LP entry 2"),
    (0x016C25, 0x5C, 0x05, "Venus 236HP entry 3"),
    (0x012834, 0x61, 0x05, "Moon 236LP entry 4"),
    (0x012836, 0x62, 0x05, "Moon 236HP entry 5"),
    # strike family — flag becomes 0x00 (no restriction at all); safe per the
    # measured latch rule (traces/airphys_airspec_d8.txt): a re-fire needs the
    # RUNNING act to re-offer the start route, and special acts offer none:
    (0x016C2B, 0x67, 0x01, "Venus 623LP entry 6"),
    (0x016C2D, 0x68, 0x01, "Venus 623HP entry 7"),
)


def build(src, out):
    rom = bytearray(open(src, "rb").read())
    for off, act, oldflags, name in EDITS:
        if rom[off + 1] != act:
            raise ValueError(f"{name}: expected act {act:02X} at 0x{off + 1:06X}, found {rom[off + 1]:02X}")
        if rom[off] != oldflags:
            raise ValueError(f"{name}: expected flags {oldflags:02X} at 0x{off:06X}, found {rom[off]:02X}")
        rom[off] = oldflags & ~0x01        # clear bit0 (ground-only); keep the rest
        print(f"  {name}: flags {oldflags:02X} -> {oldflags & ~0x01:02X} at 0x{off:06X} (act {act:02X})")
    fix_checksum(rom)
    open(out, "wb").write(rom)
    print(f"wrote {out} from {src} sha1={hashlib.sha1(rom).hexdigest()}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="EXPERIMENT: air-enable Venus/Moon 236P.")
    ap.add_argument("out")
    ap.add_argument("src", nargs="?", default=None)
    ap.add_argument("--stacked", action="store_true")
    a = ap.parse_args()
    src = a.src or clean_rom()
    require_source(src, stacked=a.stacked)
    check_not_inplace(src, a.out)
    build(src, a.out)
