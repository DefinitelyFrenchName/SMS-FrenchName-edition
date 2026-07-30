#!/usr/bin/env python3
"""Patch 13 v3 (OPTIONAL): "GUTS" — completing a taunt NERFS the opponent's specials.

Finish the full misfire pratfall uninterrupted (patch 12's L-taunt, or a real ochame
whiff in A.C.S. play) and gain one guts level, stacking to 3. While you hold levels,
the OPPONENT's SPECIAL and DESPERATION moves deal --l1/--l2/--l3 percent less damage to
you (default 20/40/60) — direct hits, projectiles, and chip alike. Normals and throws
are deliberately untouched. Levels last until the round ends; each player's current
level shows as a small digit in their top screen corner (blank at 0).

Class discrimination (probe-verified): the attacker's +0x44 attack-class byte — lights
0x00-0x03, heavies 0x04-0x07, specials >=0x08/0x0C, supers >=0x12; a projectile slot
carries its own +0x44 (always special-class). The 8 damage-apply sites split into 4
melee paths (class-check the other fighter) and 4 projectile paths (always special).
The native ACS stat +0x73 (buff_special) genuinely scales special damage but only
UPWARD from the VS default of 0 — a nerf below baseline needs these hooks.

Ground truth (probe-verified, docs/annotations.md "patch 13 RE"):
  * Strike/chip damage applies at 8 IDENTICAL sites in bank $C0: `lda $0049,Y / sec /
    sbc $00 / sta $0049,Y` — Y = defender struct, damage staged in DP $00, D = 0.
    Chip flows through the same sites (blocked normals stage 0).
  * Damage has native per-hit VARIANCE (the 16x16 matrix at $C0:D081) — the buff scales
    the final rolled value, exactly as intended.
  * VS round transition signature: both players' HP jump to max AND both acts reset to 0
    on the same frame (nothing else changes) — the per-round reset signal. Immune to
    patch 11's single-player REGEN/REFILL heals. Two edges implement it: the KO edge
    (a player's shadowed prev-HP was 0, now at max) and, since 2026-07-30 (issue #21),
    the TIMEOUT edge (both at max now, at least one shadowed prev-HP below max) —
    before that fix, Guts levels survived a timed-out round (A/B-proven in-emulator,
    tools/probe_p13_timeout.lua).
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
from pathlib import Path as _P
REPO = _P(__file__).resolve().parent.parent  # repo root (cwd-independent)
sys.path.insert(0, str(REPO / "tools"))
from smspaths import clean_rom  # ROM location: $SMS_ROM_DIR -> roms/ -> ../roms/
import asm65816 as A  # noqa: E402
from mkpatch12 import MISFIRE  # single source of truth for the primary misfire acts

CLEAN = clean_rom()
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
MELEE_SITES = (0xC09C, 0xC16F, 0xC216, 0xC2C5)     # player-vs-player hit/chip variants
PROJ_SITES = (0xC47E, 0xC551, 0xC5F8, 0xC6A7)      # projectile hit/chip variants
STRIKE_OLD = bytes.fromhex("b9490038e500")   # lda $0049,Y / sec / sbc $00
# desperation-grab drain ticks (Pluto-style cinematic grabs; also serves Moon/Mars/Chibi
# hold-throws -- the class gate keeps those untouched): lda $0049,Y / sec / sbc $05
TICK_SITE = 0x010D54
TICK_OLD = bytes.fromhex("b9490038e505")
# throw-toss apply site $C1:082F -- same displaced bytes and Y/DP-$05 conventions as the
# tick site, so it shares the tick stub. Normal throws toss with holder +0x44 = 0 and
# pass untouched; Uranus's desperation tosses at +0x44 = 0x18 and gets scaled (v3.2).
TOSS_SITE = 0x01082F
IND_HOOK = 0x00D596                                  # uploader staging-clean exit (every frame, vblank)
IND_OLD = bytes.fromhex("ad0a08f020")                # lda $080A / beq $D5BB
IND_CONT_NE = 0x80D59B                               # branch not taken
IND_CONT_EQ = 0x80D5BB                               # branch taken
IND_CELL = (0x10E1, 0x10FE)                          # BG3 row 7, col 1 (P1) / col 30 (P2)

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
  bne tmo
  lda $10C9
  cmp $10CA
  bne tmo
  jmp rsig
tmo:
  lda $1049
  cmp $104A
  bne nr
  lda $10C9
  cmp $10CA
  bne nr
  lda_l ${PREVHP[0]:06X}
  cmp $104A
  bne rsig
  lda_l ${PREVHP[1]:06X}
  cmp $10CA
  bne rsig
  bra nr
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


def _level_pick(sfx, class_gate):
    """16-bit A/X context. Leaves A = defender's level (nonzero); passthru if not a
    player, level 0, or (class_gate) the attacker's +0x44 is below special class."""
    g1 = g2 = ""
    if class_gate:
        # defender P1 -> attacker is P2 ($10C4); defender P2 -> attacker is P1 ($1044)
        g1 = f"""  lda $10C4
  and #$00FF
  cmp #$0008
  bcs cg1{sfx}
  jmp pass{sfx}
cg1{sfx}:
"""
        g2 = f"""  lda $1044
  and #$00FF
  cmp #$0008
  bcs cg2{sfx}
  jmp pass{sfx}
cg2{sfx}:
"""
    return f"""
  cpy #$1000
  beq lp1{sfx}
  cpy #$1080
  beq lp2{sfx}
  jmp pass{sfx}
lp1{sfx}:
{g1}  lda_l ${LV[0]:06X}
  bra lpd{sfx}
lp2{sfx}:
{g2}  lda_l ${LV[1]:06X}
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
  lda #$0100
  bra tj{sfx}
t1{sfx}:
  lda #$0080
  bra tj{sfx}
t0{sfx}:
  lda #$0000
tj{sfx}:
  sta_l ${SCR16:06X}
{dmg_expr}  cmp #$0080
  bcc dk{sfx}
  lda #$007F
dk{sfx}:
  clc
  adc_l ${SCR16:06X}
  tax
  sep #$20
  lda_lx ${table_long:06X}
  sta_l ${SCR8:06X}
  rep #$20
"""


def _tick_stub(table_long):
    """Desperation-grab drain ticks: victim in Y, per-tick damage in DP $05. Scale only
    when the HOLDER's +0x44 is desperation-class (>=0x12) -- normal hold-throws pass."""
    g1 = """  lda $10C4
  and #$00FF
  cmp #$0012
  bcs tg1
  jmp passk
tg1:
"""
    g2 = """  lda $1044
  and #$00FF
  cmp #$0012
  bcs tg2
  jmp passk
tg2:
"""
    lp = f"""
  cpy #$1000
  beq tlp1
  cpy #$1080
  beq tlp2
  jmp passk
tlp1:
{g1}  lda_l ${LV[0]:06X}
  bra tlpd
tlp2:
{g2}  lda_l ${LV[1]:06X}
tlpd:
  and #$00FF
  bne tlpk
  jmp passk
tlpk:
"""
    dmg_expr = "  lda $0005\n  and #$00FF\n"
    return f"""
  php
  rep #$30
  phx
{lp}{_scale_core(dmg_expr, "k", table_long)}  plx
  plp
  lda_y $0049
  sec
  sbc_l ${SCR8:06X}
  rtl
passk:
  plx
  plp
  lda_y $0049
  sec
  sbc $0005
  rtl
"""


def _strike_stub(table_long, class_gate):
    """Shared scaling stub: class_gate=True for the 4 melee sites (attacker must be
    special-class), False for the 4 projectile sites (always special)."""
    sfx = "m" if class_gate else "p"
    dmg_expr = "  lda $0000\n  and #$00FF\n"
    return f"""
  php
  rep #$30
  phx
{_level_pick(sfx, class_gate)}{_scale_core(dmg_expr, sfx, table_long)}  plx
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
  sbc $0000
  rtl
"""


def _ind_player(p, sfx):
    cell = IND_CELL[p]
    return f"""
  rep #$20
  lda #${cell:04X}
  sta $2116
  sep #$20
  lda_l ${LV[p]:06X}
  rep #$20
  and #$00FF
  bne iv{sfx}
  lda #$2000
  bra iw{sfx}
iv{sfx}:
  clc
  adc #$2C50
iw{sfx}:
  sta $2118
"""


def _ind_stub():
    """Vblank, every frame: draw each player's buff level as a small HUD digit
    (blank at level 0). v3.4: TRAINING-ONLY — gated on game mode $8D in {4,5}
    (practice with damage off/on) in addition to the in-match flag; in VS/story the
    indicator never draws (the buff itself still works everywhere). Redrawn per
    frame, so wipes/restages never leave it stale."""
    return f"""
  php
  pha
  sep #$20
  lda $0070
  cmp #$04
  beq indm
  jmp indout
indm:
  lda $008D
  cmp #$04
  beq ind1
  cmp #$05
  beq ind1
  jmp indout
ind1:
  lda #$80
  sta $2115
{_ind_player(0, "a")}{_ind_player(1, "b")}  sep #$20
indout:
  rep #$20
  pla
  plp
  lda $080A
  beq indeq
  jml ${IND_CONT_NE:06X}
indeq:
  jml ${IND_CONT_EQ:06X}
"""


def make_tables(pcts):
    blob = bytearray()
    for pct in pcts:
        for d in range(128):
            s = round(d * (100 - pct) / 100)
            blob.append(max(1, s) if d >= 1 else 0)
    return bytes(blob)


def build(src, out, pcts=(20, 40, 60)):
    data = bytearray(open(src, "rb").read())
    while len(data) >= 0x10000 and data[-0x10000:] == bytes(0x10000):
        data = data[:-0x10000]
    assert data[FSM_HOOK:FSM_HOOK + 4] == FSM_OLD, f"fsm hook: {data[FSM_HOOK:FSM_HOOK+4].hex()}"
    for s in MELEE_SITES + PROJ_SITES:
        assert data[s:s + 6] == STRIKE_OLD, f"strike site {s:#x}: {data[s:s+6].hex()}"
    assert data[TICK_SITE:TICK_SITE + 6] == TICK_OLD, f"tick site: {data[TICK_SITE:TICK_SITE+6].hex()}"
    assert data[TOSS_SITE:TOSS_SITE + 6] == TICK_OLD, f"toss site: {data[TOSS_SITE:TOSS_SITE+6].hex()}"
    assert data[IND_HOOK:IND_HOOK + 5] == IND_OLD, f"indicator hook: {data[IND_HOOK:IND_HOOK+5].hex()}"

    bankbase = (len(data) + 0xFFFF) & ~0xFFFF
    while len(data) < bankbase:
        data += b"\x00"
    bank = 0xC0 + (bankbase >> 16)

    tables = make_tables(pcts)
    table_long = (bank << 16) | (bankbase & 0xFFFF)
    off = (bankbase & 0xFFFF) + len(tables)

    fsm_body, _ = A.assemble(_fsm_stub().splitlines(), off, bank)
    fsm_tail = FSM_OLD + bytes([0x5C, FSM_CONT & 0xFF, (FSM_CONT >> 8) & 0xFF, FSM_CONT >> 16])
    melee_off = off + len(fsm_body) + len(fsm_tail)
    melee_body, _ = A.assemble(_strike_stub(table_long, True).splitlines(), melee_off, bank)
    proj_off = melee_off + len(melee_body)
    proj_body, _ = A.assemble(_strike_stub(table_long, False).splitlines(), proj_off, bank)
    tick_off = proj_off + len(proj_body)
    tick_body, _ = A.assemble(_tick_stub(table_long).splitlines(), tick_off, bank)
    ind_off = tick_off + len(tick_body)
    ind_body, _ = A.assemble(_ind_stub().splitlines(), ind_off, bank)

    blob = tables + fsm_body + fsm_tail + melee_body + proj_body + tick_body + ind_body
    data[bankbase:bankbase + len(blob)] = blob

    def jsl(addr16):
        return bytes([0x22, addr16 & 0xFF, (addr16 >> 8) & 0xFF, bank])
    data[FSM_HOOK:FSM_HOOK + 4] = bytes([0x5C, off & 0xFF, (off >> 8) & 0xFF, bank])
    for s in MELEE_SITES:
        data[s:s + 6] = jsl(melee_off) + b"\xEA\xEA"
    for s in PROJ_SITES:
        data[s:s + 6] = jsl(proj_off) + b"\xEA\xEA"
    data[TICK_SITE:TICK_SITE + 6] = jsl(tick_off) + b"\xEA\xEA"
    data[TOSS_SITE:TOSS_SITE + 6] = jsl(tick_off) + b"\xEA\xEA"
    data[IND_HOOK:IND_HOOK + 4] = bytes([0x5C, ind_off & 0xFF, (ind_off >> 8) & 0xFF, bank])
    # IND_OLD was 5 bytes; the byte at IND_HOOK+4 (0x20) is orphaned, skipped by the jml

    data += b"\x00" * ((len(data) + 0x7FFFF) // 0x80000 * 0x80000 - len(data))
    _fix_checksum(data)
    open(out, "wb").write(data)
    print(f"wrote {out} from {src}: pcts={pcts} bank={bank:#04x} fsm={len(fsm_body)}B "
          f"melee={len(melee_body)}B proj={len(proj_body)}B tick={len(tick_body)}B ind={len(ind_body)}B, "
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
    ap.add_argument("out", nargs="?", default=str(REPO / "build/sms_tauntbuff.sfc"))
    ap.add_argument("--l1", type=int, default=20, help="level-1 damage reduction percent")
    ap.add_argument("--l2", type=int, default=40)
    ap.add_argument("--l3", type=int, default=60)
    a = ap.parse_args()
    if a.src == CLEAN:
        assert sha1(open(a.src, "rb").read()).hexdigest() == CLEAN_SHA1, "clean hash mismatch"
    build(a.src, a.out, (a.l1, a.l2, a.l3))
