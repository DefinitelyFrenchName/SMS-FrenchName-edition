#!/usr/bin/env python3
"""EXPERIMENT (not a numbered patch): URANUS air-dash CANCELS and the on-hit
air chain — start routes on authored air acts.

    python3 tools/exp_airdash2.py /tmp/ad.sfc
    python3 tools/exp_aircancel.py --stacked /tmp/ad.sfc <out.sfc>

Phase 4 of the anime-fighter feasibility programme. Two additions on top of
exp_airdash2's air dashes:

1. AIR DASH -> AIR NORMAL. The air-dash acts 0x2B/0x2C get a WRAPPER handler
   (both act slots repointed to $C1:BE85): it runs the vanilla dash handler
   via `jsr` — handlers are rts-shaped THROUGH the tail, since `jmp $0204`
   ends in the tail's rts — then, still airborne and still in the dash,
   offers the directional-jump normals table ($C1:7B19) via `jsr $0459`.
   Because the routes now run AFTER the tail, a same-frame commit would miss
   the tail's anim latch (+0x04), so the wrapper re-runs `jsr $0204` when the
   step reads 0 — the vanilla transition contract, restored by hand.

2. AIR NORMAL on hit -> AIR DASH (the gatling). j.HP's handler tail is
   rerouted through a stub at $C1:BF00 that commits act
   ⚠ Her directional j.HP is act 0x50, NOT 0x51 — measured by pressing X/HP
   from the air dash: the stance records are ordered by ASCENDING BUTTON BIT
   (LP=4F, LK=51, HP=50, HK=52 in $C1:7B19); the engine-internals column
   labeling needs re-deriving. Act 0x50's handler is $C1:85AC, tail 0x0185DD.
   0x2B/0x2C when the attack-connected latch +0x43 is set, the fighter is
   airborne, and a 44/66 double-tap is pending in +0x51 — patch 1's
   hit-confirm mechanism, airborne. On whiff +0x43 is 0 and nothing fires.

Space claims (this stack = clean + exp_airdash2 ONLY; asserted zero before
write): wrapper $C1:BE85 (patch 6's home — patch 6 is NOT in this stack),
stub $C1:BF00 (exp_airbackdash's Venus relocation home — that exp is NOT in
this stack either). The Phase 7 integration builder must rehome these.

⚠ Laws honored: ldx $88 after every vanilla-starter call ($0459 clobbers X —
measured in Phase 3); sep #$20 after $0459 before any 8-bit compare.

Verify: tools/probe_exp_aircancel.lua on this build, on the exp_airdash2
base (negative: dash-cancel dead), and whiff vs hit for the gatling.
"""
import argparse
import hashlib
import sys
from pathlib import Path as _P

REPO = _P(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
from smspaths import clean_rom, require_source, check_not_inplace, fix_checksum

WRAP, WRAP_ADDR = 0x01BE85, 0xBE85
STUB, STUB_ADDR = 0x01BF00, 0xBF00
ACT_SLOTS = ((0x017A57, 0x8298), (0x017A59, 0x88C8))   # must hold airdash2's handlers
JHP_TAIL = 0x0185DD                                     # jmp $0204 in act 0x50's handler (dir j.HP)
DIR_JUMP_TABLE = 0x7B19


def asm(base, items):
    """items: bytes-lists, ('label', name), ('b', opcode, target-label) for an
    8-bit branch, or ('w', lo-byte-list, label) unused. Two-pass, returns bytes."""
    for _pass in (0, 1):
        out, labels, fixups = bytearray(), {}, []
        pos = base
        for it in items:
            if isinstance(it, tuple) and it[0] == "label":
                labels[it[1]] = pos
            elif isinstance(it, tuple) and it[0] == "b":
                fixups.append((len(out) + 1, pos + 2, it[2]))
                out += bytes([it[1], 0])
                pos += 2
            else:
                out += bytes(it)
                pos += len(it)
        if _pass:
            for at, nxt, lab in fixups:
                d = labels[lab] - nxt
                assert -128 <= d <= 127, f"branch to {lab} out of range"
                out[at] = d & 0xFF
            return bytes(out)


WRAP_CODE = asm(WRAP_ADDR, [
    [0xC2, 0x10],             # rep #$10
    [0xA6, 0x88],             # ldx $88
    [0xE2, 0x20],             # sep #$20
    [0xB5, 0x01],             # lda $01,X
    [0xC9, 0x2B],             # cmp #$2B
    ("b", 0xF0, "back"),
    [0x20, 0xC8, 0x88],       # jsr $88C8    front-dash frame (body + tail, rts-shaped)
    ("b", 0x80, "post"),
    ("label", "back"),
    [0x20, 0x98, 0x82],       # jsr $8298    back-dash frame
    ("label", "post"),
    [0xC2, 0x10],             # rep #$10     (handler may leave any widths)
    [0xA6, 0x88],             # ldx $88
    [0xE2, 0x20],             # sep #$20
    [0xB5, 0x16],             # lda $16,X
    [0x29, 0x80],             # and #$80
    ("b", 0xD0, "fin"),       # grounded (dash ended on landing) -> no routes
    [0xB5, 0x01],             # lda $01,X
    [0xC9, 0x2B],             # cmp #$2B
    ("b", 0xF0, "routes"),
    [0xC9, 0x2C],             # cmp #$2C
    ("b", 0xD0, "fin"),       # act changed inside the handler -> no routes
    ("label", "routes"),
    [0xA0, DIR_JUMP_TABLE & 0xFF, DIR_JUMP_TABLE >> 8],   # ldy #$7B19
    [0x20, 0x59, 0x04],       # jsr $0459    air normals — THE dash-cancel
    [0xA6, 0x88],             # ldx $88      ($0459 clobbers X — Phase 3's law)
    [0xE2, 0x20],             # sep #$20     ($0459 may change A width)
    [0xB5, 0x02],             # lda $02,X
    ("b", 0xD0, "fin"),       # step != 0: nothing committed
    [0x20, 0x04, 0x02],       # jsr $0204    re-latch the transition (see docstring)
    ("label", "fin"),
    [0x60],                   # rts
])

STUB_CODE = asm(STUB_ADDR, [
    [0xC2, 0x10],             # rep #$10
    [0xA6, 0x88],             # ldx $88
    [0xE2, 0x20],             # sep #$20
    [0xB5, 0x43],             # lda $43,X    attack-connected latch
    ("b", 0xF0, "out"),
    [0xB5, 0x16],             # lda $16,X
    [0x29, 0x80],             # and #$80
    ("b", 0xD0, "out"),       # airborne only
    [0xB5, 0x51],             # lda $51,X
    [0x29, 0x0E],             # and #$0E
    [0xC9, 0x02],             # cmp #$02     44 pending
    ("b", 0xF0, "goback"),
    [0xC9, 0x04],             # cmp #$04     66 pending
    ("b", 0xD0, "out"),
    [0xA9, 0x2C],             # lda #$2C
    ("b", 0x80, "go"),
    ("label", "goback"),
    [0xA9, 0x2B],             # lda #$2B
    ("label", "go"),
    [0x20, 0x24, 0x02],       # jsr $0224    commit; the jmp $0204 below latches it
    ("label", "out"),
    [0x4C, 0x04, 0x02],       # jmp $0204    the handler's original tail
])


def build(src, out):
    rom = bytearray(open(src, "rb").read())
    for off, handler in ACT_SLOTS:
        if rom[off:off + 2] != handler.to_bytes(2, "little"):
            raise ValueError(f"0x{off:06X}: expected exp_airdash2's handler {handler:04X} — stack on that build")
        rom[off:off + 2] = WRAP_ADDR.to_bytes(2, "little")
    if any(rom[WRAP:WRAP + len(WRAP_CODE)]):
        raise ValueError(f"0x{WRAP:06X}: wrapper area is not free")
    rom[WRAP:WRAP + len(WRAP_CODE)] = WRAP_CODE
    if rom[JHP_TAIL:JHP_TAIL + 3] != bytes([0x4C, 0x04, 0x02]):
        raise ValueError(f"0x{JHP_TAIL:06X}: expected jmp $0204, found {rom[JHP_TAIL:JHP_TAIL + 3].hex()}")
    rom[JHP_TAIL:JHP_TAIL + 3] = bytes([0x4C, STUB_ADDR & 0xFF, STUB_ADDR >> 8])
    if any(rom[STUB:STUB + len(STUB_CODE)]):
        raise ValueError(f"0x{STUB:06X}: stub area is not free")
    rom[STUB:STUB + len(STUB_CODE)] = STUB_CODE
    fix_checksum(rom)
    open(out, "wb").write(rom)
    print(f"wrote {out} from {src} sha1={hashlib.sha1(rom).hexdigest()}  "
          f"[wrapper {len(WRAP_CODE)} B @ ${WRAP_ADDR:04X}, gatling stub {len(STUB_CODE)} B @ ${STUB_ADDR:04X}]")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="EXPERIMENT: Uranus air-dash cancels + on-hit air chain.")
    ap.add_argument("out")
    ap.add_argument("src", nargs="?", default=None)
    ap.add_argument("--stacked", action="store_true")
    a = ap.parse_args()
    src = a.src or clean_rom()
    require_source(src, stacked=a.stacked)
    check_not_inplace(src, a.out)
    build(src, a.out)
