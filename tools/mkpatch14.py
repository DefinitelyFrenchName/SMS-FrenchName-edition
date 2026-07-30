#!/usr/bin/env python3
"""Patch 14 (OPTIONAL): "GUTS GRIP" — Guts levels also nerf COMMAND GRABS.

Companion to patch 13 (Guts). Patch 13's specials-nerf cannot see command grabs:
Uranus's SPD (6321478HK) tosses 32 through the throw path and Jupiter's SPD
(6321478HP) drains 5x6 through the hold-tick path, both with holder attack-class
+0x44 = 0 — indistinguishable from normal throws at the apply sites, so the
class >= 0x12 gate exempts them (probe-verified byte-identical at Guts L3).

This patch closes that hole as a SEPARATE, byte-disjoint, order-independent patch:
while a player holds Guts levels (patch 13's state, read-only), incoming
command-grab damage is reduced by the same --l1/--l2/--l3 percentages. Normal
throws and hold-throws stay exempt (per-character grab act gate); --all-grabs
switches to nerfing EVERY grab-path damage instead (normal throws included).
Without patch 13 in the ROM the state magic never appears and this patch is inert.

Mechanism — the two grab apply sites share the tail
    cmp #$90 / bcs death / sta $0049,Y            (7 bytes)
immediately AFTER the 6 damage-subtract bytes patch 13 hooks. We hook the tail:
    jsl stub / bcs (death, displacement-2) / nop
The stub receives A = hp_after (8-bit, M=1 guaranteed by the original cmp #$90),
recovers dmg = hp_before - A (hp not yet stored), gates on
    p13 MAGIC valid  AND  victim's LV >= 1  AND  holder +0x44 < 0x12
    AND (unless --all-grabs) holder (charID, act) in the command-grab table,
rescales, and exits through cmp #$90 (+ conditional sta, which preserves carry)
so the relocated inline bcs sees the exact original death semantics.

Command-grab table (probe-verified apply-time acts): Uranus (char 6) toss act 0x71
(both SPD strengths AND her desperation slam converge there — the class<0x12 gate
disambiguates the latter), Jupiter (char 4) carry-tick acts 0x70 (Giant Swing HP,
5 ticks) and 0x6F (Giant Swing LP, 4 ticks). Other characters' command grabs (if
any) can be added to GRAB_ACTS once their inputs are identified.

State ABI (patch 13, read-only): $7F:F800 magic 0xA5, $7F:F801/F802 = P1/P2 level.
Own scratch: $7F:F810-F815 (disjoint from patch 13's F800-F80A).
"""
import argparse
from hashlib import sha1
import sys
from pathlib import Path as _P
REPO = _P(__file__).resolve().parent.parent  # repo root (cwd-independent)
sys.path.insert(0, str(REPO / "tools"))
from smspaths import clean_rom  # ROM location: $SMS_ROM_DIR -> roms/ -> ../roms/
import asm65816 as A  # noqa: E402

CLEAN = clean_rom()

# apply-site tails (site+6 of the toss/tick sites patch 13 hooks at +0)
TOSS_TAIL = 0x10835
TOSS_OLD = bytes.fromhex("c990b039994900")   # cmp #$90 / bcs +0x39 / sta $0049,Y
TICK_TAIL = 0x10D5A
TICK_OLD = bytes.fromhex("c990b005994900")   # cmp #$90 / bcs +0x05 / sta $0049,Y

# patch 13 state (read-only) + own scratch
MAGIC = 0x7FF800
LV = (0x7FF801, 0x7FF802)
ST14 = 0x7FF810
SCRF = ST14 + 0    # final hp value handed to the exit sequence
SCRL = ST14 + 1    # victim's level 1-3
SCRD = ST14 + 2    # raw damage
SCRS = ST14 + 3    # scaled damage
SCR16 = ST14 + 4   # 16-bit scratch

# (charID, apply-act) pairs that count as command-grab damage
GRAB_ACTS = ((6, 0x71), (4, 0x70), (4, 0x6F))


def make_tables(pcts):
    blob = bytearray()
    for pct in pcts:
        for d in range(128):
            s = round(d * (100 - pct) / 100)
            blob.append(max(1, s) if d >= 1 else 0)
    return bytes(blob)


def _side(sfx, vic_hp, holder, lv, table_long, all_grabs):
    """One victim-side block. Entry: 8-bit A, 16-bit XY. Exits: jmp fin (SCRF holds
    the final hp; default already staged = passthrough)."""
    gate = ""
    if not all_grabs:
        k = 0
        for cid, act in GRAB_ACTS:
            gate += f"""  lda_l ${holder:06X}
  cmp #${cid:02X}
  bne ga{k}{sfx}
  lda_l ${holder + 1:06X}
  cmp #${act:02X}
  beq gy{sfx}
ga{k}{sfx}:
"""
            k += 1
        gate += f"  jmp fin\ngy{sfx}:\n"
    return f"""
v{sfx}:
  lda_l ${lv:06X}
  bne lv{sfx}
  jmp fin
lv{sfx}:
  cmp #$04
  bcc lw{sfx}
  jmp fin
lw{sfx}:
  sta_l ${SCRL:06X}
  lda_l ${holder + 0x44:06X}
  cmp #$12
  bcc cl{sfx}
  jmp fin
cl{sfx}:
{gate}  lda_l ${vic_hp:06X}
  sec
  sbc_l ${SCRF:06X}
  sta_l ${SCRD:06X}
  rep #$30
  lda_l ${SCRL:06X}
  and #$00FF
  dec_a
  xba
  lsr_a
  sta_l ${SCR16:06X}
  lda_l ${SCRD:06X}
  and #$00FF
  clc
  adc_l ${SCR16:06X}
  tax
  sep #$20
  lda_lx ${table_long:06X}
  sta_l ${SCRS:06X}
  lda_l ${vic_hp:06X}
  sec
  sbc_l ${SCRS:06X}
  sta_l ${SCRF:06X}
  jmp fin
"""


def _stub(table_long, all_grabs):
    return f"""
  sta_l ${SCRF:06X}
  php
  sep #$20
  rep #$10
  lda_l ${MAGIC:06X}
  cmp #$A5
  beq m1
  jmp fin
m1:
  cpy #$1000
  beq j1
  cpy #$1080
  beq j2
  jmp fin
j1:
  jmp v1
j2:
  jmp v2
{_side("1", 0x7E1049, 0x7E1080, LV[0], table_long, all_grabs)}
{_side("2", 0x7E10C9, 0x7E1000, LV[1], table_long, all_grabs)}
fin:
  sep #$20
  plp
  lda_l ${SCRF:06X}
  cmp #$90
  bcc dost
  rtl
dost:
  sta_y $0049
  rtl
"""


def build(src, out, pcts=(20, 40, 60), all_grabs=False):
    data = bytearray(open(src, "rb").read())
    while len(data) >= 0x10000 and data[-0x10000:] == bytes(0x10000):
        data = data[:-0x10000]
    assert data[TOSS_TAIL:TOSS_TAIL + 7] == TOSS_OLD, f"toss tail: {data[TOSS_TAIL:TOSS_TAIL+7].hex()}"
    assert data[TICK_TAIL:TICK_TAIL + 7] == TICK_OLD, f"tick tail: {data[TICK_TAIL:TICK_TAIL+7].hex()}"

    bankbase = (len(data) + 0xFFFF) & ~0xFFFF
    while len(data) < bankbase:
        data += b"\x00"
    bank = 0xC0 + (bankbase >> 16)

    tables = make_tables(pcts)
    table_long = (bank << 16) | (bankbase & 0xFFFF)
    stub_off = (bankbase & 0xFFFF) + len(tables)
    body, _ = A.assemble(_stub(table_long, all_grabs).splitlines(), stub_off, bank)

    blob = tables + body
    data[bankbase:bankbase + len(blob)] = blob

    jsl = bytes([0x22, stub_off & 0xFF, (stub_off >> 8) & 0xFF, bank])
    data[TOSS_TAIL:TOSS_TAIL + 7] = jsl + bytes([0xB0, 0x37, 0xEA])
    data[TICK_TAIL:TICK_TAIL + 7] = jsl + bytes([0xB0, 0x03, 0xEA])

    data += b"\x00" * ((len(data) + 0x7FFFF) // 0x80000 * 0x80000 - len(data))
    _fix_checksum(data)
    open(out, "wb").write(data)
    print(f"wrote {out} from {src}: pcts={pcts} all_grabs={all_grabs} bank={bank:#04x} "
          f"stub={len(body)}B, {len(data):#x} bytes, sha1={sha1(bytes(data)).hexdigest()}")


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
    ap = argparse.ArgumentParser(description="Guts Grip: Guts levels nerf command grabs (patch 14).")
    ap.add_argument("src", nargs="?", default=CLEAN)
    ap.add_argument("out", nargs="?", default=str(REPO / "build/sms_gutsgrip.sfc"))
    ap.add_argument("--l1", type=int, default=20, help="level-1 reduction percent")
    ap.add_argument("--l2", type=int, default=40)
    ap.add_argument("--l3", type=int, default=60)
    ap.add_argument("--all-grabs", action="store_true",
                    help="nerf ALL grab-path damage (normal throws and hold-throws included)")
    args = ap.parse_args()
    build(args.src, args.out, (args.l1, args.l2, args.l3), args.all_grabs)
