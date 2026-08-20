#!/usr/bin/env python3
"""EXPERIMENT (not a numbered patch): URANUS air back/front dash — the
ROUTE-INSERTION class.

    python3 tools/exp_airdash2.py <out.sfc>

Phase 3 of the anime-fighter feasibility programme. exp_airbackdash.py proved
the air-dash pattern on Venus, whose jump handlers already call the special
starter ($0958) — the hook merely REROUTED an existing call. Five characters'
jump handlers never call it, so universalizing needs the other variant: hook a
call the handlers DO make and insert the air-dash check behind it. Uranus is
that class's cheapest proof, and cheaper than Venus overall:

  * her jump handlers offer ONLY the normals route (`jsr $0459` — census:
    tools/census_airroutes.py), so the stub wraps THAT call;
  * she already owns the 66 motion (m1, $C1:1535) and the Shadow Dash handler
    ($C1:88C8), so there is NO table relocation, NO motion append and NO entry
    append: the stub reads the pending +0x51 nibble directly — ids 02/03 (44)
    -> air backdash act 0x2B, ids 04/05 (66) -> air front dash act 0x2C.
    Grounded, the stub falls through and the vanilla table entries behave
    exactly as before (her ground dash entries 2/3 stay flag 0x01).

EDITS (file offsets; every one asserted before it is written):

  0x001047  00 00 -> 11 11   Uranus script table $C0:0FF1 + 0x2B*2 -> $C0:1111
  0x001049  00 00 -> 11 11   same for act 0x2C (her jump-fwd/back SHARE $1111)
  0x017A57  00 00 -> 98 82   act 0x2B -> her backdash handler $C1:8298
  0x017A59  00 00 -> C8 88   act 0x2C -> her Shadow Dash handler $C1:88C8
  0x017E9D  20 59 04 -> 20 A0 BF   act 0x06 jump-up   normals call -> stub
  0x017ED0  20 59 04 -> 20 A0 BF   act 0x07 jump-fwd  normals call -> stub
  0x017F03  20 59 04 -> 20 A0 BF   act 0x08 jump-back normals call -> stub
  0x01BFA0  33-byte stub (region asserted zero; disjoint from exp_airbackdash's
            $BF00-$BF98 claims so the two experiments can stack)

Verify: tools/probe_exp_airdash2.lua on this build and on the clean ROM.
"""
import argparse
import hashlib
import sys
from pathlib import Path as _P

REPO = _P(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
from smspaths import clean_rom, require_source, check_not_inplace, fix_checksum

BACK_ACT, FRONT_ACT = 0x2B, 0x2C
SCRIPT_SLOTS = (0x001047, 0x001049)      # $C0:0FF1 + act*2
JUMP_SCRIPT = 0x1111                     # her jump-fwd/back script (shared)
ACT_SLOTS = ((0x017A57, 0x8298), (0x017A59, 0x88C8))   # backdash, Shadow Dash
HOOKS = (0x017E9D, 0x017ED0, 0x017F03)   # `jsr $0459` in jump up / fwd / back
STUB, STUB_ADDR = 0x01BFA0, 0xBFA0

STUB_CODE = bytes([
    0x20, 0x59, 0x04,       # jsr $0459      vanilla normals route, unchanged and FIRST
    0xA6, 0x88,             # ldx $88        $0459 is not proven to preserve X — reload
    0xE2, 0x20,             # sep #$20
    0xB5, 0x16,             # lda $16,X
    0x29, 0x80,             # and #$80       bit7 = grounded
    0xD0, 0x15,             # bne done       grounded: behave exactly as vanilla
    0xB5, 0x51,             # lda $51,X      pending command nibble
    0x29, 0x0E,             # and #$0E
    0xC9, 0x02,             # cmp #$02       ids 02/03 = back double-tap
    0xF0, 0x08,             # beq back
    0xC9, 0x04,             # cmp #$04       ids 04/05 = her own 66
    0xD0, 0x09,             # bne done
    0xA9, FRONT_ACT,        # lda #$2C
    0x80, 0x02,             # bra go
    0xA9, BACK_ACT,         # back: lda #$2B
    0x4C, 0x24, 0x02,       # go: jmp $0224  the act setter rts's for us
    0x60,                   # done: rts
])


def build(src, out):
    rom = bytearray(open(src, "rb").read())
    for off in SCRIPT_SLOTS:
        if rom[off:off + 2] != b"\0\0":
            raise ValueError(f"0x{off:06X}: script slot is not null")
        rom[off:off + 2] = JUMP_SCRIPT.to_bytes(2, "little")
    for off, handler in ACT_SLOTS:
        if rom[off:off + 2] != b"\0\0":
            raise ValueError(f"0x{off:06X}: act slot is not null")
        rom[off:off + 2] = handler.to_bytes(2, "little")
    for off in HOOKS:
        if rom[off:off + 3] != bytes.fromhex("205904"):
            raise ValueError(f"0x{off:06X}: expected jsr $0459, found {rom[off:off + 3].hex()}")
        rom[off:off + 3] = bytes([0x20, STUB_ADDR & 0xFF, STUB_ADDR >> 8])
    if any(rom[STUB:STUB + len(STUB_CODE)]):
        raise ValueError(f"0x{STUB:06X}: stub area is not free")
    rom[STUB:STUB + len(STUB_CODE)] = STUB_CODE
    fix_checksum(rom)
    open(out, "wb").write(rom)
    print(f"wrote {out} from {src} sha1={hashlib.sha1(rom).hexdigest()}  "
          f"[Uranus air back=0x{BACK_ACT:02X} front=0x{FRONT_ACT:02X}, stub ${STUB_ADDR:04X}, {len(STUB_CODE)} B]")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="EXPERIMENT: Uranus air dashes (route insertion).")
    ap.add_argument("out")
    ap.add_argument("src", nargs="?", default=None)
    ap.add_argument("--stacked", action="store_true")
    a = ap.parse_args()
    src = a.src or clean_rom()
    require_source(src, stacked=a.stacked)
    check_not_inplace(src, a.out)
    build(src, a.out)
