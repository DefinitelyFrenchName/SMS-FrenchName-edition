#!/usr/bin/env python3
"""EXPERIMENT (not a numbered patch): a DELIBERATE air-action budget.

    python3 tools/exp_airdash2.py /tmp/ad.sfc
    python3 tools/exp_aircancel.py /tmp/ac.sfc /tmp/ad.sfc --stacked
    python3 tools/exp_aircounter.py <out.sfc> /tmp/ac.sfc --stacked [--budget N]

Phase 5 of the anime-fighter feasibility programme. The one-air-dash-per-jump
limit the exps had so far was ACCIDENTAL (the dash acts offered no dash
routes); an anime fighter needs a deliberate, tunable budget. This build:

  * counter cell = player struct byte **+0x7F** — measured free: the busy-
    segment write census (tools/probe_airfree.lua) shows only the round
    re-init block writes touch it (count == the 8-sweep baseline), and a
    poked 0xA5 SURVIVES 1400 busy frames on both structs. Round transitions
    therefore RESET it for free ([SMS-16] as a feature). ⚠ Boot path
    unwatched — promotion beyond exp tier owes the [SMS-33] full watch.
  * both air-dash commit sites gain the gate: exp_airdash2's jump stub
    ($C1:BFA0) and exp_aircancel's gatling stub ($C1:BF00) are REWRITTEN
    (old bytes asserted first) as budget-aware versions — commit only while
    `+0x7F < N`, `inc $7F,X` on commit. The act is now COMPUTED from the
    nibble (`lsr / beq / cmp #$03 / bcs / adc #$2A` -> 0x2B/0x2C), which
    pays for the budget bytes.
  * landing resets it: the landing handler's `jsr $0958` (0x017F40) is
    rerouted through a 9-byte stub (`sep #$20 / ldx $88 / stz $7F,X /
    jmp $0958`) at $C1:BF30. The sep matters: a 16-bit stz would also clear
    +0x80 = P2's charID.

Default N=1: one air action (dash) per airborne period. --budget 2 allows the
dash -> j.HP -> hit -> dash chain exactly once.

Verify: tools/probe_exp_aircounter.lua at N=1 and N=2.
"""
import argparse
import hashlib
import sys
from pathlib import Path as _P

REPO = _P(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
from smspaths import clean_rom, require_source, check_not_inplace, fix_checksum

JSTUB, JSTUB_ADDR = 0x01BFA0, 0xBFA0     # exp_airdash2's jump-handler stub, rewritten
GSTUB, GSTUB_ADDR = 0x01BF00, 0xBF00     # exp_aircancel's gatling stub, rewritten
RSTUB, RSTUB_ADDR = 0x01BF30, 0xBF30     # landing-reset stub (new)
LAND_HOOK = 0x017F40                      # jsr $0958 in the landing handler $C1:7F0C
CTR = 0x7F


def asm(base, items):
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
                assert -128 <= d <= 127, f"branch to {lab} out of range ({d})"
                out[at] = d & 0xFF
            return bytes(out)


def gate_and_commit(budget, tail):
    """The shared budget-gated nibble->act commit sequence."""
    return [
        [0xB5, CTR],          # lda $7F,X     the air-action counter
        [0xC9, budget],       # cmp #N
        ("b", 0xB0, "done"),  # bcs: budget spent
        [0xB5, 0x51],         # lda $51,X
        [0x29, 0x0F],         # and #$0F
        [0x4A],               # lsr           ids 2/3 -> 1, 4/5 -> 2
        ("b", 0xF0, "done"),
        [0xC9, 0x03],         # 3+ = not a dash id
        ("b", 0xB0, "done"),
        [0x69, 0x2A],         # adc #$2A      carry clear here -> act 0x2B / 0x2C
        [0xF6, CTR],          # inc $7F,X
        [0x20, 0x24, 0x02],   # jsr $0224     commit
        ("label", "done"),
    ] + tail


JSTUB_OLD_HEAD = bytes([0x20, 0x59, 0x04, 0xA6, 0x88])   # exp_airdash2's stub opening
GSTUB_OLD_HEAD = bytes([0xC2, 0x10, 0xA6, 0x88, 0xE2])   # exp_aircancel's stub opening


def jstub(budget):
    return asm(JSTUB_ADDR, [
        [0x20, 0x59, 0x04],   # jsr $0459   vanilla normals route first
        [0xA6, 0x88],         # ldx $88     ($0459 clobbers X)
        [0xE2, 0x20],         # sep #$20
        [0xB5, 0x16],         # lda $16,X
        [0x29, 0x80],
        ("b", 0xD0, "done"),  # grounded -> vanilla only
    ] + gate_and_commit(budget, [[0x60]]))                 # done: rts


def gstub(budget):
    return asm(GSTUB_ADDR, [
        [0xC2, 0x10],         # rep #$10
        [0xA6, 0x88],         # ldx $88
        [0xE2, 0x20],         # sep #$20
        [0xB5, 0x43],         # lda $43,X   attack-connected latch
        ("b", 0xF0, "done"),
        [0xB5, 0x16],         # airborne only
        [0x29, 0x80],
        ("b", 0xD0, "done"),
    ] + gate_and_commit(budget, [[0x4C, 0x04, 0x02]]))     # done: jmp $0204 (the tail)


RSTUB_CODE = asm(RSTUB_ADDR, [
    [0xE2, 0x20],             # sep #$20    (a 16-bit stz would clear P2's +0x00)
    [0xA6, 0x88],             # ldx $88
    [0x74, CTR],              # stz $7F,X   landing: budget back
    [0x4C, 0x58, 0x09],       # jmp $0958   the vanilla call (its rts returns for us)
])


def build(src, out, budget):
    rom = bytearray(open(src, "rb").read())
    for off, head, name in ((JSTUB, JSTUB_OLD_HEAD, "jump stub"), (GSTUB, GSTUB_OLD_HEAD, "gatling stub")):
        if bytes(rom[off:off + len(head)]) != head:
            raise ValueError(f"0x{off:06X}: {name} head mismatch — stack on exp_aircancel's build")
    new_j, new_g = jstub(budget), gstub(budget)
    assert len(new_j) <= 42, f"jump stub {len(new_j)} B > 42"
    rom[JSTUB:JSTUB + 42] = b"\0" * 42
    rom[JSTUB:JSTUB + len(new_j)] = new_j
    rom[GSTUB:GSTUB + 0x28] = b"\0" * 0x28
    rom[GSTUB:GSTUB + len(new_g)] = new_g
    assert GSTUB + len(new_g) <= RSTUB, "gatling stub grew into the reset stub"
    if any(rom[RSTUB:RSTUB + len(RSTUB_CODE)]):
        raise ValueError(f"0x{RSTUB:06X}: reset-stub area is not free")
    rom[RSTUB:RSTUB + len(RSTUB_CODE)] = RSTUB_CODE
    if rom[LAND_HOOK:LAND_HOOK + 3] != bytes([0x20, 0x58, 0x09]):
        raise ValueError(f"0x{LAND_HOOK:06X}: expected jsr $0958 in the landing handler")
    rom[LAND_HOOK:LAND_HOOK + 3] = bytes([0x20, RSTUB_ADDR & 0xFF, RSTUB_ADDR >> 8])
    fix_checksum(rom)
    open(out, "wb").write(rom)
    print(f"wrote {out} from {src} sha1={hashlib.sha1(rom).hexdigest()}  "
          f"[budget N={budget}, counter +0x{CTR:02X}, jstub {len(new_j)} B, gstub {len(new_g)} B]")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="EXPERIMENT: deliberate air-action budget.")
    ap.add_argument("out")
    ap.add_argument("src", nargs="?", default=None)
    ap.add_argument("--stacked", action="store_true")
    ap.add_argument("--budget", type=int, default=1)
    a = ap.parse_args()
    src = a.src or clean_rom()
    require_source(src, stacked=a.stacked)
    check_not_inplace(src, a.out)
    build(src, a.out, a.budget)
