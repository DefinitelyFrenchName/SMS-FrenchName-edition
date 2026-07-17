#!/usr/bin/env python3
"""Patch 13 (OPTIONAL): "GUTS" — a stacking defense buff earned by completing a taunt.

Q-in-3S style: finish the full misfire pratfall uninterrupted (patch 12's L-taunt, or a
real ochame whiff in A.C.S. play — same animation) and gain one defense level, stacking
to 3. Damage taken (strikes, projectiles, CHIP, throws, teched throws) is reduced by
--l1/--l2/--l3 percent (default 10/25/45). Levels last until the round ends. No HUD
indicator (the pratfall is the tell). Works standalone or with patches 11/12.

Ground truth (probe-verified, docs/annotations.md "patch 13 RE"):
  * Strike/chip damage applies at 8 IDENTICAL sites in bank $C0 (one per on-hit-table
    variant): `lda $0049,Y / sec / sbc $00 / sta $0049,Y` — Y = defender struct, damage
    staged in DP $00, D register = 0. Chip exists for specials and flows through the
    same sites (blocked normals stage 0). Throws: full at $C1:082F (damage in DP $05),
    teched at $C1:084D (adds the negated half).
  * Damage has native per-hit VARIANCE (the 16x16 matrix at $C0:D081) — the buff scales
    the final rolled value, exactly as intended.
  * VS round transition signature: both players' HP jump to max AND both acts reset to 0
    on the same frame (nothing else changes) — the per-round reset signal. Immune to
    patch 11's single-player REGEN/REFILL heals.
  * All 9 characters' misfire acts chain misfire-act -> 0x2A (embarrassed) -> neutral.

Hooks (byte-disjoint from patches 1-12):
  * $80:837B (joy_read, P2 edge derivation; displaced `sta $60 / lda $5E` raw-spliced)
    -> FSM stub: taunt-completion detection + level grant + round reset. Chains after
    patch 12's hook naturally, any install order.
  * 8x JSL thunks over the strike-apply sequences (6 bytes each -> JSL + 2 nop) into ONE
    shared scaling stub (RTL lands on the original `sta $0049,Y`).
  * JSL thunks at the two throw sites (full: 6 bytes; tech: 10 bytes -> JSL + 6 nop).
"""
import argparse
from hashlib import sha1
import sys
sys.path.insert(0, "tools")
import asm65816 as A  # noqa: E402
from mkpatch12 import MISFIRE  # single source of truth for the primary misfire acts

CLEAN = "roms/Bishoujo Senshi Sailormoon S - Jougai Rantou! Shuyaku Soudatsusen (Japan).sfc"
CLEAN_SHA1 = "bc0e29ee383574443226695215496eb0d09aaa1c"

# full per-character misfire-act sets (probe_p12_rec harvest: all specials' record+6)
MISFIRE_SETS = {
    1: [0x6A, 0x6B], 2: [0x65, 0x66], 3: [0x66, 0x67, 0x6C], 4: [0x63, 0x64],
    5: [0x5F, 0x60, 0x65, 0x66], 6: [0x65, 0x66], 7: [0x66, 0x67],
    8: [0x62, 0x63], 9: [0x63, 0x64],
}
assert all(MISFIRE[c] in s for c, s in MISFIRE_SETS.items())

# hooks
FSM_HOOK = 0x00837B
FSM_OLD = bytes.fromhex("8560a55e")      # sta $60 / lda $5E
FSM_CONT = 0x80837F
STRIKE_SITES = (0xC09C, 0xC16F, 0xC216, 0xC2C5, 0xC47E, 0xC551, 0xC5F8, 0xC6A7)
STRIKE_OLD = bytes.fromhex("b9490038e500")   # lda $0049,Y / sec / sbc $00
THROWF_SITE = 0x01082F
THROWF_OLD = bytes.fromhex("b9490038e505")   # lda $0049,Y / sec / sbc $05
THROWT_SITE = 0x01084D
THROWT_OLD = bytes.fromhex("a5054a49ff1a18794900")  # lda $05/lsr/eor#FF/inc/clc/adc $0049,Y

# $7F:F800 state block (clear of round-intro scratch and patch 11's E000/F000)
ST = 0x7FF800
MAGIC = ST + 0x00
LV = (ST + 0x01, ST + 0x02)        # P1, P2 buff level 0-3
FSMS = (ST + 0x03, ST + 0x04)      # taunt FSM state 0/1/2
PREVHP = (ST + 0x05, ST + 0x06)
SCR16 = ST + 0x08                  # 16-bit scratch (clamped damage)
SCR8 = ST + 0x0A                   # scaled damage byte


def _inset(base, yes, no, sfx):
    """A-destroying test: is <base>'s current act in its char's misfire set?
    All exits via jmp (far-safe)."""
    out = ""
    k = 0
    for cid in sorted(MISFIRE_SETS):
        acts = MISFIRE_SETS[cid]
        out += f"  lda ${base:04X}\n  cmp #${cid:02X}\n  bne ic{cid}{sfx}\n"
        for a in acts:
            out += f"""  lda ${base + 1:04X}
  cmp #${a:02X}
  bne ia{k}{sfx}
  jmp {yes}
ia{k}{sfx}:
"""
            k += 1
        out += f"  jmp {no}\nic{cid}{sfx}:\n"
    out += f"  jmp {no}\n"
    return out


def _fsm_player(p, sfx):
    base = 0x1000 + p * 0x80
    lv, fs = LV[p], FSMS[p]
    return f"""
  lda_l ${fs:06X}
  bne d1{sfx}
  jmp f0{sfx}
d1{sfx}:
  cmp #$01
  bne d2{sfx}
  jmp f1{sfx}
d2{sfx}:
  lda ${base + 1:04X}
  cmp #$2A
  bne d2a{sfx}
  jmp fdone{sfx}
d2a{sfx}:
  cmp #$05
  bcc grant{sfx}
  cmp #$21
  beq grant{sfx}
  cmp #$0C
  beq grant{sfx}
  cmp #$0D
  beq grant{sfx}
  lda #$00
  sta_l ${fs:06X}
  jmp fdone{sfx}
grant{sfx}:
  lda_l ${lv:06X}
  cmp #$03
  bcs gcap{sfx}
  inc_a
  sta_l ${lv:06X}
gcap{sfx}:
  lda #$00
  sta_l ${fs:06X}
  jmp fdone{sfx}
f1{sfx}:
  lda ${base + 1:04X}
  cmp #$2A
  bne f1b{sfx}
  lda #$02
  sta_l ${fs:06X}
  jmp fdone{sfx}
f1b{sfx}:
{_inset(base, f"fdone{sfx}", f"f1x{sfx}", "s" + sfx)}f1x{sfx}:
  lda #$00
  sta_l ${fs:06X}
  jmp fdone{sfx}
f0{sfx}:
{_inset(base, f"f0y{sfx}", f"fdone{sfx}", "z" + sfx)}f0y{sfx}:
  lda #$01
  sta_l ${fs:06X}
fdone{sfx}:
"""


def _fsm_stub():
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
  jmp goff
g1:
  lda_l ${MAGIC:06X}
  cmp #$A5
  beq inited
  lda #$A5
  sta_l ${MAGIC:06X}
  lda #$00
  sta_l ${LV[0]:06X}
  sta_l ${LV[1]:06X}
  sta_l ${FSMS[0]:06X}
  sta_l ${FSMS[1]:06X}
  lda $1049
  sta_l ${PREVHP[0]:06X}
  lda $10C9
  sta_l ${PREVHP[1]:06X}
inited:
  lda_l ${PREVHP[0]:06X}
  bne rs2
  lda $1049
  cmp $104A
  bne rs2
  jmp rsig
rs2:
  lda_l ${PREVHP[1]:06X}
  bne nr
  lda $10C9
  cmp $10CA
  bne nr
rsig:
  lda $1001
  bne nr
  lda $1081
  bne nr
  lda #$00
  sta_l ${LV[0]:06X}
  sta_l ${LV[1]:06X}
  sta_l ${FSMS[0]:06X}
  sta_l ${FSMS[1]:06X}
nr:
  lda $1049
  sta_l ${PREVHP[0]:06X}
  lda $10C9
  sta_l ${PREVHP[1]:06X}
{_fsm_player(0, "a")}{_fsm_player(1, "b")}  jmp exit
goff:
  lda #$00
  sta_l ${MAGIC:06X}
  sta_l ${LV[0]:06X}
  sta_l ${LV[1]:06X}
  sta_l ${FSMS[0]:06X}
  sta_l ${FSMS[1]:06X}
exit:
  plb
  rep #$30
  ply
  plx
  pla
  plp
"""
    # builder appends raw: 85 60 A5 5E + JML $80:837F


def _level_pick(sfx):
    """16-bit A/X context. Leaves A = level(0-3) of the defender in Y; passthru if not a player."""
    return f"""
  cpy #$1000
  beq lp1{sfx}
  cpy #$1080
  beq lp2{sfx}
  jmp pass{sfx}
lp1{sfx}:
  lda_l ${LV[0]:06X}
  bra lpd{sfx}
lp2{sfx}:
  lda_l ${LV[1]:06X}
lpd{sfx}:
  and #$00FF
  bne lpk{sfx}
  jmp pass{sfx}
lpk{sfx}:
"""


def _scale_core(dmg_expr, sfx, table_long):
    """16-bit A/X. A = level (1-3) on entry. Computes SCR8 = table[level][clamp(dmg)].
    dmg_expr = asm lines leaving 16-bit A = raw damage (masked)."""
    return f"""
  dec_a
  beq t0{sfx}
  cmp #$0001
  beq t1{sfx}
  lda #$0080
  bra tj{sfx}
t1{sfx}:
  lda #$0040
  bra tj{sfx}
t0{sfx}:
  lda #$0000
tj{sfx}:
  sta_l ${SCR16:06X}
{dmg_expr}  cmp #$0040
  bcc dk{sfx}
  lda #$003F
dk{sfx}:
  clc
  adc_l ${SCR16:06X}
  tax
  sep #$20
  lda_lx ${table_long:06X}
  sta_l ${SCR8:06X}
  rep #$20
"""


def _strike_stub(table_long, dmg_dp):
    """Shared by the 8 strike sites (dmg_dp=0) and the throw-full site (dmg_dp=5)."""
    sfx = "s" if dmg_dp == 0 else "t"
    dmg_expr = f"  lda ${dmg_dp:04X}\n  and #$00FF\n"
    return f"""
  php
  rep #$30
  phx
{_level_pick(sfx)}{_scale_core(dmg_expr, sfx, table_long)}  plx
  plp
  lda_y $0049
  sec
  sbc_l ${SCR8:06X}
  rtl
pass{sfx}:
  plx
  plp
  lda_y $0049
  sec
  sbc ${dmg_dp:04X}
  rtl
"""


def _tech_stub(table_long):
    dmg_expr = "  lda $0005\n  and #$00FF\n  lsr_a\n"
    return f"""
  php
  rep #$30
  phx
{_level_pick("h")}{_scale_core(dmg_expr, "h", table_long)}  plx
  plp
  sep #$20
  lda_l ${SCR8:06X}
  eor #$FF
  inc_a
  clc
  adc_y $0049
  rtl
passh:
  plx
  plp
  sep #$20
  lda $0005
  lsr_a
  eor #$FF
  inc_a
  clc
  adc_y $0049
  rtl
"""


def make_tables(pcts):
    blob = bytearray()
    for pct in pcts:
        for d in range(64):
            s = round(d * (100 - pct) / 100)
            blob.append(max(1, s) if d >= 1 else 0)
    return bytes(blob)


def build(src, out, pcts=(10, 25, 45)):
    data = bytearray(open(src, "rb").read())
    while len(data) >= 0x10000 and data[-0x10000:] == bytes(0x10000):
        data = data[:-0x10000]
    assert data[FSM_HOOK:FSM_HOOK + 4] == FSM_OLD, f"fsm hook: {data[FSM_HOOK:FSM_HOOK+4].hex()}"
    for s in STRIKE_SITES:
        assert data[s:s + 6] == STRIKE_OLD, f"strike site {s:#x}: {data[s:s+6].hex()}"
    assert data[THROWF_SITE:THROWF_SITE + 6] == THROWF_OLD, "throw-full site"
    assert data[THROWT_SITE:THROWT_SITE + 10] == THROWT_OLD, "throw-tech site"

    bankbase = (len(data) + 0xFFFF) & ~0xFFFF
    while len(data) < bankbase:
        data += b"\x00"
    bank = 0xC0 + (bankbase >> 16)

    tables = make_tables(pcts)
    table_long = (bank << 16) | (bankbase & 0xFFFF)
    off = (bankbase & 0xFFFF) + len(tables)

    fsm_body, _ = A.assemble(_fsm_stub().splitlines(), off, bank)
    fsm_tail = FSM_OLD + bytes([0x5C, FSM_CONT & 0xFF, (FSM_CONT >> 8) & 0xFF, FSM_CONT >> 16])
    strike_off = off + len(fsm_body) + len(fsm_tail)
    strike_body, _ = A.assemble(_strike_stub(table_long, 0).splitlines(), strike_off, bank)
    throwf_off = strike_off + len(strike_body)
    throwf_body, _ = A.assemble(_strike_stub(table_long, 5).splitlines(), throwf_off, bank)
    throwt_off = throwf_off + len(throwf_body)
    throwt_body, _ = A.assemble(_tech_stub(table_long).splitlines(), throwt_off, bank)

    blob = tables + fsm_body + fsm_tail + strike_body + throwf_body + throwt_body
    data[bankbase:bankbase + len(blob)] = blob

    def jsl(addr16):
        return bytes([0x22, addr16 & 0xFF, (addr16 >> 8) & 0xFF, bank])
    data[FSM_HOOK:FSM_HOOK + 4] = bytes([0x5C, off & 0xFF, (off >> 8) & 0xFF, bank])
    for s in STRIKE_SITES:
        data[s:s + 6] = jsl(strike_off) + b"\xEA\xEA"
    data[THROWF_SITE:THROWF_SITE + 6] = jsl(throwf_off) + b"\xEA\xEA"
    data[THROWT_SITE:THROWT_SITE + 10] = jsl(throwt_off) + b"\xEA" * 6

    data += b"\x00" * ((len(data) + 0x7FFFF) // 0x80000 * 0x80000 - len(data))
    _fix_checksum(data)
    open(out, "wb").write(data)
    print(f"wrote {out} from {src}: pcts={pcts} bank={bank:#04x} fsm={len(fsm_body)}B "
          f"strike={len(strike_body)}B throwf={len(throwf_body)}B throwt={len(throwt_body)}B, "
          f"{len(data):#x} bytes, sha1={sha1(bytes(data)).hexdigest()}")


def _fix_checksum(data):
    size = len(data); chk_size = 0x80000
    while chk_size <= size: chk_size <<= 1
    if chk_size == size:
        chk = sum(data)
    else:
        cd = data[chk_size // 2:]
        while len(cd) < chk_size // 2: cd += cd[len(cd) - chk_size:]
        chk = sum(data[:chk_size // 2]) + sum(cd)
    data[0xFFDE] = chk & 0xFF; data[0xFFDF] = chk >> 8 & 0xFF
    data[0xFFDC] = data[0xFFDE] ^ 0xFF; data[0xFFDD] = data[0xFFDF] ^ 0xFF


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Guts: taunt-completion defense buff (patch 13).")
    ap.add_argument("src", nargs="?", default=CLEAN)
    ap.add_argument("out", nargs="?", default="build/sms_tauntbuff.sfc")
    ap.add_argument("--l1", type=int, default=10, help="level-1 damage reduction percent")
    ap.add_argument("--l2", type=int, default=25)
    ap.add_argument("--l3", type=int, default=45)
    a = ap.parse_args()
    if a.src == CLEAN:
        assert sha1(open(a.src, "rb").read()).hexdigest() == CLEAN_SHA1, "clean hash mismatch"
    build(a.src, a.out, (a.l1, a.l2, a.l3))
