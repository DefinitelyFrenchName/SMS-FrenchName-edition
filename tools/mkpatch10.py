#!/usr/bin/env python3
"""Patch 10 (OPTIONAL): in-match COMBO COUNTER (+ GC status) rendered by the base game.

Feasibility result: the in-match HUD is Arch A — a main-loop producer ($C0:D5E8, scanline
101, once/frame) stages tile updates into WRAM $0806-$0815, and an NMI uploader ($C0:D56F,
scanline 237/vblank) flushes them to VRAM. Free resources: WRAM $0816-$08FF unused, big
digit tiles 0-9 already in the HUD CHR (top 0x2C50+N, bottom 0x2C60+N), HUD tilemap rows
0/1/2/7 blank. So the counter needs no new tiles and no NMI surgery — two JML trampolines.

Two hooks (both file offset = SNES & 0x3FFFFF; byte-disjoint from patches 1-9):
  * $C0:D5E8 producer entry -> compute stub (per-frame combo tick + stage digit tiles)
  * $C0:D56F uploader entry -> flush stub (push staged digit tiles to VRAM in vblank)

Combo semantics mirror tools/training/combo.lua: a hit continues the chain only if the
defender had no actionable frame since the last hit (true chain); a hit after >=3 free
frames restarts at 1. Shows from --min-hits (default 2), fades after --ttl frames.

The Lua combo counter is the verification ORACLE (tests/T4 etc. run on the patched ROM).
Build stages via --stage {pipe,combo,full} let the pipeline be validated incrementally.
"""
import argparse
from hashlib import sha1
import sys
sys.path.insert(0, "tools")
import asm65816 as A  # noqa: E402

CLEAN = "roms/Bishoujo Senshi Sailormoon S - Jougai Rantou! Shuyaku Soudatsusen (Japan).sfc"
CLEAN_SHA1 = "bc0e29ee383574443226695215496eb0d09aaa1c"

PROD = 0x00D5E8            # hud_producer entry; first bytes C2 10 E2 20
PROD_OLD = bytes.fromhex("c210e220")
UPL = 0x00D56F            # hud_uploader entry; first bytes C2 30 AD 06 08
UPL_OLD = bytes.fromhex("c230ad0608")

# continuation targets (FastROM mirror $80 of $C0), after the displaced bytes
PROD_CONT = 0x80D5EC      # after rep#$10; sep#$20
UPL_CONT = 0x80D574       # after rep#$30; lda $0806 (the beq)

# WRAM state (free HUD page tail). Per-defender combo blocks + staging.
ST_P1D = 0x08A0   # combo dealt TO P1 (attacker P2 -> RIGHT display): hits,free,ttl,shown,shadow
ST_P2D = 0x08B0   # combo dealt TO P2 (attacker P1 -> LEFT display)
INIT = 0x08C0     # init sentinel byte
STG_L = 0x08D0    # left-display staging: dirty,+1 tt,+3 ot,+5 tb,+7 ob  (tile words)
STG_R = 0x08E0    # right-display staging

# VRAM tilemap cells (word addresses)
L_TOP, L_BOT = 0x10C2, 0x10E2     # left: two top cells $10C2/$10C3, bottoms $10E2/$10E3
R_TOP, R_BOT = 0x10DC, 0x10FC     # right: $10DC/$10DD, $10FC/$10FD


def _defender_logic(hp, act, st, sfx):
    """8-bit A; update one combo block from defender HP/act. min-hits/ttl baked by caller."""
    return f"""
  lda ${hp:04X}
  cmp ${st + 4:04X}
  beq nohp{sfx}
  bcs hpup{sfx}
  lda ${st + 1:04X}
  cmp #$03
  bcc cont{sfx}
  lda #$01
  sta ${st + 0:04X}
  bra afth{sfx}
cont{sfx}:
  inc ${st + 0:04X}
afth{sfx}:
  lda #$48
  sta ${st + 2:04X}
  stz ${st + 1:04X}
  lda ${hp:04X}
  sta ${st + 4:04X}
  bra actn{sfx}
hpup{sfx}:
  stz ${st + 0:04X}
  stz ${st + 1:04X}
  stz ${st + 2:04X}
  lda ${hp:04X}
  sta ${st + 4:04X}
  bra actn{sfx}
nohp{sfx}:
actn{sfx}:
  lda ${act:04X}
  cmp #$0E
  bcc free{sfx}
  cmp #$21
  bcc con{sfx}
  cmp #$23
  beq con{sfx}
  cmp #$27
  bcc free{sfx}
  cmp #$2A
  bcc con{sfx}
free{sfx}:
  lda ${st + 1:04X}
  cmp #$FF
  beq ttl{sfx}
  inc ${st + 1:04X}
  bra ttl{sfx}
con{sfx}:
  stz ${st + 1:04X}
ttl{sfx}:
  lda ${st + 2:04X}
  beq done{sfx}
  dec ${st + 2:04X}
  bne done{sfx}
  stz ${st + 0:04X}
done{sfx}:
"""


def _render_logic(st, stg, minhits, sfx):
    """8-bit A on entry; produce 4 tile words + dirty into stg. Leading-zero blanking."""
    return f"""
  lda ${st + 0:04X}
  cmp #${minhits:02X}
  bcs show{sfx}
  lda ${st + 3:04X}
  beq rdone{sfx}
  stz ${st + 3:04X}
  rep #$20
  lda #$2000
  sta ${stg + 1:04X}
  sta ${stg + 3:04X}
  sta ${stg + 5:04X}
  sta ${stg + 7:04X}
  sep #$20
  lda #$01
  sta ${stg + 0:04X}
  bra rdone{sfx}
show{sfx}:
  cmp ${st + 3:04X}
  beq rdone{sfx}
  sta ${st + 3:04X}
  ldx #$00
t1{sfx}:
  cmp #$0A
  bcc t2{sfx}
  sec
  sbc #$0A
  inx
  bra t1{sfx}
t2{sfx}:
  rep #$20
  and #$00FF
  pha
  clc
  adc #$2C50
  sta ${stg + 3:04X}
  pla
  clc
  adc #$2C60
  sta ${stg + 7:04X}
  sep #$20
  txa
  beq blt{sfx}
  rep #$20
  and #$00FF
  pha
  clc
  adc #$2C50
  sta ${stg + 1:04X}
  pla
  clc
  adc #$2C60
  sta ${stg + 5:04X}
  bra tdn{sfx}
blt{sfx}:
  rep #$20
  lda #$2000
  sta ${stg + 1:04X}
  sta ${stg + 5:04X}
tdn{sfx}:
  sep #$20
  lda #$01
  sta ${stg + 0:04X}
rdone{sfx}:
"""


def _flush_side(stg, top, bot, sfx):
    """16-bit A; if dirty, write 4 tile words to the 2x2 cells, clear dirty."""
    return f"""
  sep #$20
  lda ${stg + 0:04X}
  beq fd{sfx}
  stz ${stg + 0:04X}
  rep #$20
  lda #${top:04X}
  sta $2116
  lda ${stg + 1:04X}
  sta $2118
  lda ${stg + 3:04X}
  sta $2118
  lda #${bot:04X}
  sta $2116
  lda ${stg + 5:04X}
  sta $2118
  lda ${stg + 7:04X}
  sta $2118
  sep #$20
fd{sfx}:
  rep #$20
"""


def _mode_gate(modes):
    """Emit: if $008D not in `modes`, blank both counters and skip compute (bra dorender)."""
    if not modes:
        return ""   # no gate: show in every match (producer self-gates to matches)
    checks = "".join(f"  cmp #${mode:02X}\n  beq gok\n" for mode in modes)
    return f"""
  lda $008D
{checks}
  stz ${ST_P1D + 0:04X}
  stz ${ST_P2D + 0:04X}
  jmp dorender
gok:
"""


def build(src, out, stage="full", minhits=2, ttl=72, modes=(0x00, 0x01, 0x04, 0x05)):
    data = bytearray(open(src, "rb").read())
    while len(data) >= 0x10000 and data[-0x10000:] == bytes(0x10000):
        data = data[:-0x10000]
    assert data[PROD:PROD + 4] == PROD_OLD, f"producer hook bytes: {data[PROD:PROD+4].hex()}"
    assert data[UPL:UPL + 5] == UPL_OLD, f"uploader hook bytes: {data[UPL:UPL+5].hex()}"

    bankbase = (len(data) + 0xFFFF) & ~0xFFFF
    while len(data) < bankbase:
        data += b"\x00"
    bank = 0xC0 + (bankbase >> 16)

    # ---- COMPUTE stub (producer hook): tick both defenders, stage both displays ----
    if stage == "pipe":
        compute_src = ""   # pipeline test: no compute; flush writes a fixed pattern
    else:
        compute_src = (
            _mode_gate(modes if stage == "full" else None)
            + _defender_logic(0x1049, 0x1001, ST_P1D, "a")
            + _defender_logic(0x10C9, 0x1081, ST_P2D, "b")
            + "dorender:\n"
            + _render_logic(ST_P2D, STG_L, minhits, "l")   # P2 defender -> LEFT (attacker P1)
            + _render_logic(ST_P1D, STG_R, minhits, "r")   # P1 defender -> RIGHT (attacker P2)
        )
    compute_asm = f"""
  php
  rep #$30
  pha
  phx
  phy
  sep #$20
  lda ${INIT:04X}
  cmp #$A5
  beq go
  lda #$A5
  sta ${INIT:04X}
  lda $1049
  sta ${ST_P1D + 4:04X}
  lda $10C9
  sta ${ST_P2D + 4:04X}
  stz ${ST_P1D + 0:04X}
  stz ${ST_P1D + 1:04X}
  stz ${ST_P1D + 2:04X}
  stz ${ST_P1D + 3:04X}
  stz ${ST_P2D + 0:04X}
  stz ${ST_P2D + 1:04X}
  stz ${ST_P2D + 2:04X}
  stz ${ST_P2D + 3:04X}
  stz ${STG_L + 0:04X}
  stz ${STG_R + 0:04X}
go:
{compute_src}
  rep #$30
  ply
  plx
  pla
  plp
  rep #$10
  sep #$20
  jml ${PROD_CONT:06X}
"""

    # ---- FLUSH stub (uploader hook): push staged tiles to VRAM in vblank ----
    if stage == "pipe":
        flush_body = f"""
  rep #$20
  lda #${L_TOP:04X}
  sta $2116
  lda #$2C51
  sta $2118
  lda #$2C52
  sta $2118
  lda #${L_BOT:04X}
  sta $2116
  lda #$2C61
  sta $2118
  lda #$2C62
  sta $2118
"""
    else:
        flush_body = (
            _flush_side(STG_L, L_TOP, L_BOT, "l")
            + _flush_side(STG_R, R_TOP, R_BOT, "r")
        )
    flush_asm = f"""
  rep #$30
{flush_body}
  sep #$20
  rep #$20
  lda $0806
  jml ${UPL_CONT:06X}
"""

    # assemble: compute stub first, then flush stub, both in the appended bank
    compute_bytes, _ = A.assemble(compute_asm.splitlines(), bankbase & 0xFFFF, bank)
    flush_off = (bankbase & 0xFFFF) + len(compute_bytes)
    flush_bytes, _ = A.assemble(flush_asm.splitlines(), flush_off, bank)

    blob = bytearray(compute_bytes) + flush_bytes
    data[bankbase:bankbase + len(blob)] = blob

    # repoint the two hooks (JML into the appended bank)
    ca = bankbase & 0xFFFF
    data[PROD:PROD + 4] = bytes([0x5C, ca & 0xFF, (ca >> 8) & 0xFF, bank])
    data[UPL:UPL + 4] = bytes([0x5C, flush_off & 0xFF, (flush_off >> 8) & 0xFF, bank])
    # (UPL_OLD was 5 bytes; byte at UPL+4 = 0x08 is orphaned, skipped by the jml)

    data[0xFFC0:0xFFD5] = b"\xBE\xB0\xD7\xB0\xD1\xB0\xDDS FrenchName  "
    data += b"\x00" * ((len(data) + 0x7FFFF) // 0x80000 * 0x80000 - len(data))
    _fix_checksum(data)
    open(out, "wb").write(data)
    print(f"wrote {out} from {src}: stage={stage} bank={bank:#04x} "
          f"compute={len(compute_bytes)}B flush={len(flush_bytes)}B, "
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
    ap = argparse.ArgumentParser(description="In-match combo counter (base game).")
    ap.add_argument("src", nargs="?", default=CLEAN)
    ap.add_argument("out", nargs="?", default="build/sms_combocounter.sfc")
    ap.add_argument("--stage", choices=["pipe", "combo", "full"], default="full",
                    help="pipe=fixed-pattern pipeline test; full=combo counter")
    ap.add_argument("--min-hits", type=int, default=2)
    ap.add_argument("--ttl", type=int, default=72)
    ap.add_argument("--modes", default="0,1,4,5",
                    help="game_mode ($008D) values to show in, comma hex/dec; "
                         "'all' = every match (default 0,1,4,5 = VS + training)")
    a = ap.parse_args()
    if a.src == CLEAN:
        assert sha1(open(a.src, "rb").read()).hexdigest() == CLEAN_SHA1, "clean hash mismatch"
    modes = () if a.modes.strip().lower() == "all" else tuple(int(m, 0) for m in a.modes.split(","))
    build(a.src, a.out, a.stage, a.min_hits, a.ttl, modes)
