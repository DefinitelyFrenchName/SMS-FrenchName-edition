#!/usr/bin/env python3
"""Patch 12 (OPTIONAL): TAUNTS on the L button.

Press L (R not held) while grounded and actionable, in any match, and your character
performs her NATIVE failed-special animation — the same per-character misfire ("ochame")
pratfall the game plays in story mode / A.C.S. customization matches when a special whiffs
(fizzle -> embarrassed -> neutral, ~1.8s, fully vulnerable). Works for both players, in
every match type (VS, vs-COM, tournament, story, Practice).

Ground truth (probe-verified, docs/annotations.md "patch 12 RE"):
  * Every special's 8-byte record (bank $C1) carries its misfire act at +6; the native
    roll in the dispatcher $C1:0B49 compares ochame (+0x75) against a threshold table
    indexed by the RNG byte $90. On misfire the engine just sets act = record+6.
    Per-char misfire acts (LP variants), audited clean from standing:
    Moon 6A, Mercury 65, Mars 66, Jupiter 63(!has a hitbox - authentic), Venus 5F,
    Uranus 65, Neptune 66, Pluto 62, ChibiMoon 63.
  * Force-act write set (vendor + patch-11 proven): +01=act, +02=1, +04=act, +06=0, +07=0.
  * joy_read stores held words at $5C-$5F, prev at $64-$67, THEN derives edges — so an
    L press-edge is computable statelessly from the game's own bytes: $5C & ~$64 & 0x20.
  * CPU-driven pads (vs-COM mode 2, attract demo) never carry L/R bits -> no mode gate.
  * L/R are otherwise unused in-match; patch 11's menu chord is L+R (the R-not-held check
    keeps the chord from taunting; p11's input-eat runs BEFORE this hook, so no taunts
    while its menu is open).

Hook: $80:8377 (joy_read, right after `rep #$20 / lda $5C`, displaced bytes
`45 64 25 5C` = `eor $64 / and $5C`, replayed as a raw splice + JML $80:837B).
Byte-disjoint from patches 1-11; with patch 11 present its stub tail JMLs straight into
this hook — natural chain, order-independent. Zero WRAM footprint (no state at all).
"""
import argparse
from hashlib import sha1
import sys
from pathlib import Path as _P
REPO = _P(__file__).resolve().parent.parent  # repo root (cwd-independent)
sys.path.insert(0, str(REPO / "tools"))
from smspaths import clean_rom, require_source, check_not_inplace  # ROM location: $SMS_ROM_DIR -> roms/ -> ../roms/
import asm65816 as A  # noqa: E402

CLEAN = clean_rom()

# Detection fingerprint (p12) — consumed by tools/mksigs.py to generate the
# regression suite's SIGS table. ONLY bytes invariant across stub-layout and
# bank-stacking changes: JML opcode at the joy_read hook (vanilla 45; operands are stub-layout-dependent)
SIG = [(0x8377, 0x5C)]
CLEAN_SHA1 = "bc0e29ee383574443226695215496eb0d09aaa1c"

HOOK = 0x008377
HOOK_OLD = bytes.fromhex("4564255c")   # eor $64 / and $5C (P1 edge derivation)
HOOK_CONT = 0x80837B

# per-character misfire act (LP-version, probe-harvested + audited)
MISFIRE = {1: 0x6A, 2: 0x65, 3: 0x66, 4: 0x63, 5: 0x5F, 6: 0x65, 7: 0x66, 8: 0x62, 9: 0x63}
FALLBACK = 0x2A   # unknown charID -> universal "embarrassed"


def _player(base, held, prev, sfx):
    """One player's taunt check + act write. 8-bit A, DBR=$00."""
    chain = ""
    for cid, act in sorted(MISFIRE.items()):
        chain += f"""  cmp #${cid:02X}
  bne c{cid}{sfx}
  lda #${act:02X}
  bra tset{sfx}
c{cid}{sfx}:
"""
    return f"""
  lda ${held:04X}
  and #$10
  beq r0{sfx}
  jmp no{sfx}
r0{sfx}:
  lda ${prev:04X}
  eor #$FF
  and ${held:04X}
  and #$20
  bne l1{sfx}
  jmp no{sfx}
l1{sfx}:
  lda ${base + 0x4D:04X}
  beq h0{sfx}
  jmp no{sfx}
h0{sfx}:
  lda ${base + 0x01:04X}
  cmp #$05
  bcc a0{sfx}
  jmp no{sfx}
a0{sfx}:
  lda ${base + 0x00:04X}
{chain}  lda #${FALLBACK:02X}
tset{sfx}:
  sta ${base + 0x01:04X}
  sta ${base + 0x04:04X}
  lda #$01
  sta ${base + 0x02:04X}
  stz ${base + 0x06:04X}
  stz ${base + 0x07:04X}
no{sfx}:
"""


def _stub():
    return f"""
  php
  rep #$30
  pha
  phx
  phy
  phb
  sep #$20
  lda #$00
  pha
  plb
  lda $0070
  cmp #$04
  beq g1
  jmp exit
g1:
  lda $01FA
  cmp #$80
  beq g2
  jmp exit
g2:
{_player(0x1000, 0x005C, 0x0064, "a")}{_player(0x1080, 0x005E, 0x0066, "b")}exit:
  plb
  rep #$30
  ply
  plx
  pla
  plp
"""


def build(src, out):
    data = bytearray(open(src, "rb").read())
    while len(data) >= 0x10000 and data[-0x10000:] == bytes(0x10000):
        data = data[:-0x10000]
    assert data[HOOK:HOOK + 4] == HOOK_OLD, f"hook bytes: {data[HOOK:HOOK+4].hex()}"

    bankbase = (len(data) + 0xFFFF) & ~0xFFFF
    while len(data) < bankbase:
        data += b"\x00"
    bank = 0xC0 + (bankbase >> 16)

    off = bankbase & 0xFFFF
    body, _ = A.assemble(_stub().splitlines(), off, bank)
    tail = HOOK_OLD + bytes([0x5C, HOOK_CONT & 0xFF, (HOOK_CONT >> 8) & 0xFF, HOOK_CONT >> 16])
    blob = body + tail
    # bank guards (issue #27): the appended stub+data must fit one 64K bank, and the
    # target region must be virgin (a collision means stacking standalone BPS — forbidden)
    if len(blob) > 0x10000:
        raise SystemExit(f"error: appended blob {len(blob):#x} bytes exceeds one 64K bank")
    if any(data[bankbase:bankbase + len(blob)]):
        raise SystemExit(f"error: target bank at {bankbase:#x} is already occupied "
                         "(never stack standalone BPS files; chain the builders)")
    data[bankbase:bankbase + len(blob)] = blob
    data[HOOK:HOOK + 4] = bytes([0x5C, off & 0xFF, (off >> 8) & 0xFF, bank])

    data += b"\x00" * ((len(data) + 0x7FFFF) // 0x80000 * 0x80000 - len(data))
    _fix_checksum(data)
    open(out, "wb").write(data)
    print(f"wrote {out} from {src}: bank={bank:#04x} stub={len(body)}B "
          f"{len(data):#x} bytes, sha1={sha1(bytes(data)).hexdigest()}")


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
    ap = argparse.ArgumentParser(description="Taunts on the L button (patch 12).")
    ap.add_argument("src", nargs="?", default=CLEAN)
    ap.add_argument("out", nargs="?", default=str(REPO / "build/sms_taunt.sfc"))
    ap.add_argument("--stacked", action="store_true",
                    help="src is an already-patched ROM (builder chaining); skips the clean-SHA gate")
    a = ap.parse_args()
    check_not_inplace(a.src, a.out)
    require_source(a.src, a.stacked)
    build(a.src, a.out)
