#!/usr/bin/env python3
"""Patch 11 (OPTIONAL): in-ROM TRAINING MODE UPGRADE for the base game's Practice mode.

Native Practice facts this patch is built on (probe-verified, docs/annotations.md "patch 11 RE"):
  * game_mode $008D: 4 = training (hits connect, HP subtraction gated OFF), 5 = same with
    damage ON (the attract demo also runs at 5 -> we only accept 5 when WE set it).
  * $0070 == 4 while in any match; $01FA == 0x80 while the match is actually running
    (0xE4 = native movelist open via Start; Select exits the mode -- both left untouched).
  * The HUD producer $C0:D5E8 NEVER runs in Practice: no HUD, no timer. BG3 is off
    (TM $212C = 0x13, VS uses 0x17); BG3 CHR digits + palettes ARE loaded; the whole BG3
    tilemap is writable and survives; game writes TM only at scene setup.
  * joy_read tail: at $80:8373 the held words $5C/$5E are stored but press edges are not
    yet derived -- rewriting $5E/$5F here drives P2 perfectly (edges auto-derived next
    frame; 44 backdash recognizer fires; 30Hz press latch behaves).
  * Bank $7F is untouched in steady-state play (scene loads use $7F:0000-5FFF only)
    -> all patch state lives at $7F:F000+ (long addressing, DBR-independent).

Hooks (both byte-disjoint from patches 1-10, so stacking order never matters):
  * $80:8373 joy_read tail  -> INPUT stub: gate + (later) menu FSM + dummy injection
  * $80:D574 uploader body  -> UPL2 stub: vblank-only VRAM work (TM force, font DMA,
    row rendering); replays the displaced `beq/sta $2116` branch-aware.

Build stages (incremental validation, patch-10 discipline):
  pipe = gate + render plumbing only: shows a "TRAINING" row on BG3 while gated.
"""
import argparse
from hashlib import sha1
import sys
sys.path.insert(0, "tools")
import asm65816 as A  # noqa: E402
import hudfont  # noqa: E402

CLEAN = "roms/Bishoujo Senshi Sailormoon S - Jougai Rantou! Shuyaku Soudatsusen (Japan).sfc"
CLEAN_SHA1 = "bc0e29ee383574443226695215496eb0d09aaa1c"

INP = 0x008373                       # joy_read tail: rep #$20 / lda $5C (edge calc follows)
INP_OLD = bytes.fromhex("c220a55c")
INP_CONT = 0x808377

UPL2 = 0x00D574                      # uploader body: beq $D596 / sta $2116
UPL2_OLD = bytes.fromhex("f0208d1621")
UPL2_CONT_STA = 0x80D579             # after the displaced sta $2116
UPL2_CONT_BEQ = 0x80D596             # the displaced beq's target

# patch-10 hook sites -- patch 11 must never touch these (diagnostic only)
P10_PROD, P10_PROD_OLD = 0x00D5E8, bytes.fromhex("c210e220")
P10_UPL, P10_UPL_OLD = 0x00D56F, bytes.fromhex("c230ad0608")

# ---- $7F:F000 state block (boot-cleared once by the game's RAM clear; we re-init on gate) ----
ST = 0x7FF000
MAGIC = ST + 0x00      # 0xA5 = settings initialized
FONTUP = ST + 0x01     # glyphs uploaded this visibility episode
VISIBLE = ST + 0x02    # gate result this frame (written by INPUT stub)
PREVVIS = ST + 0x03    # uploader-side shadow of VISIBLE (transition detect)
DMGFLAG = ST + 0x04    # 0xA5 = mode 5 was set by US (accept gate at $8D==5)

# ---- BG3 real estate ----
BG3_CHR = 0x5000
GLYPH_TILE0 = 0xC7                   # shared window start (patch 10 uses 0xC7-0xD6)
BLANK = 0x2000
TM_ON, TM_OFF = 0x17, 0x13           # mainScreenLayers with/without BG3

# shared-superset font: patch 10's 16 letters in ITS derivation order, then p11 extras
P10_LETTERS = list("GCREVSALPUNIHMTY")
P11_LETTERS = list("BDFJKOW") + [">", "#"]
FONT_LETTERS = P10_LETTERS + P11_LETTERS
assert len(FONT_LETTERS) <= 25, "font exceeds free CHR window 0xC7-0xDF"

TITLE_ROW_ADDR = 0x1000 + 9 * 32 + 4   # BG3 row 9, col 4 (word addr $1124)


def tilew(ch, idx):
    """BG3 tilemap word for a font letter: priority + palette 3 + tile id."""
    return 0x2C00 | (GLYPH_TILE0 + idx[ch])


def _input_stub(stage):
    """INPUT stub body (joy_read tail). 8-bit A inside; DBR forced to $00.
    Computes the gate: VISIBLE = ($8D==4 or ($8D==5 and DMGFLAG)) and $0070==4
    and $01FA==$80. Off-path clears the volatile block (self-healing)."""
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
  lda $008D
  cmp #$04
  beq gmode
  cmp #$05
  bne goff
  lda_l ${DMGFLAG:06X}
  cmp #$A5
  beq gmode
  bra goff
gmode:
  lda $0070
  cmp #$04
  bne goff
  lda $01FA
  cmp #$80
  bne goff
  lda #$01
  sta_l ${VISIBLE:06X}
  bra gend
goff:
  lda #$00
  sta_l ${VISIBLE:06X}
  sta_l ${FONTUP:06X}
  sta_l ${DMGFLAG:06X}
gend:
  plb
  rep #$30
  ply
  plx
  pla
  plp
"""
    # builder appends raw: C2 20 A5 5C ; JML $808377


def _upl2_stub(stage, font_addr, font_bank, font_size, idx):
    """UPL2 stub body (vblank). Preserves A + flags around all work; replays the
    displaced beq/sta branch-aware at the end. All VRAM/DMA/TM writes live here."""
    dst = BG3_CHR + GLYPH_TILE0 * 8
    title = "TRAINING"
    draw_title = "".join(
        f"  lda #${tilew(c, idx):04X}\n  sta $2118\n" for c in title)
    blank_title = "".join("  sta $2118\n" for _ in title)
    return f"""
  php
  pha
  phx
  phy
  sep #$20
  lda_l ${VISIBLE:06X}
  cmp_l ${PREVVIS:06X}
  bne dotrans
  jmp steady
dotrans:
  lda_l ${VISIBLE:06X}
  sta_l ${PREVVIS:06X}
  cmp #$01
  beq turnon
  lda #${TM_OFF:02X}
  sta $212C
  lda #$80
  sta $2115
  rep #$20
  lda #${TITLE_ROW_ADDR:04X}
  sta $2116
  lda #${BLANK:04X}
{blank_title}  sep #$20
  jmp steady
turnon:
  lda #$80
  sta $2115
  lda #$01
  sta $4300
  lda #$18
  sta $4301
  lda #${font_bank:02X}
  sta $4304
  rep #$20
  lda #${dst:04X}
  sta $2116
  lda #${font_addr:04X}
  sta $4302
  lda #${font_size:04X}
  sta $4305
  sep #$20
  lda #$01
  sta $420B
  lda #$01
  sta_l ${FONTUP:06X}
  rep #$20
  lda #${TITLE_ROW_ADDR:04X}
  sta $2116
{draw_title}  sep #$20
steady:
  lda_l ${VISIBLE:06X}
  beq notm
  lda #${TM_ON:02X}
  sta $212C
notm:
  rep #$30
  ply
  plx
  pla
  plp
  beq far96
  sta $2116
  jml ${UPL2_CONT_STA:06X}
far96:
  jml ${UPL2_CONT_BEQ:06X}
"""


def build(src, out, stage="pipe"):
    data = bytearray(open(src, "rb").read())
    while len(data) >= 0x10000 and data[-0x10000:] == bytes(0x10000):
        data = data[:-0x10000]
    assert data[INP:INP + 4] == INP_OLD, f"input hook bytes: {data[INP:INP+4].hex()}"
    assert data[UPL2:UPL2 + 5] == UPL2_OLD, f"upl2 hook bytes: {data[UPL2:UPL2+5].hex()}"
    for site, old, name in ((P10_PROD, P10_PROD_OLD, "p10-producer"),
                            (P10_UPL, P10_UPL_OLD, "p10-uploader")):
        if data[site:site + len(old)] != old and data[site] != 0x5C:
            print(f"WARNING: unexpected bytes at {name} ({data[site:site+len(old)].hex()})")

    bankbase = (len(data) + 0xFFFF) & ~0xFFFF
    while len(data) < bankbase:
        data += b"\x00"
    bank = 0xC0 + (bankbase >> 16)

    font_blob, idx = hudfont.build_font(FONT_LETTERS)

    # bank layout: [font][input stub + raw tail][upl2 stub] -- font first = no forward refs
    font_off = bankbase & 0xFFFF
    inp_off = font_off + len(font_blob)
    inp_body, _ = A.assemble(_input_stub(stage).splitlines(), inp_off, bank)
    inp_tail = INP_OLD + bytes([0x5C, INP_CONT & 0xFF, (INP_CONT >> 8) & 0xFF, INP_CONT >> 16])
    upl_off = inp_off + len(inp_body) + len(inp_tail)
    upl_body, _ = A.assemble(
        _upl2_stub(stage, font_off, bank, len(font_blob), idx).splitlines(), upl_off, bank)

    blob = font_blob + inp_body + inp_tail + upl_body
    data[bankbase:bankbase + len(blob)] = blob

    data[INP:INP + 4] = bytes([0x5C, inp_off & 0xFF, (inp_off >> 8) & 0xFF, bank])
    data[UPL2:UPL2 + 4] = bytes([0x5C, upl_off & 0xFF, (upl_off >> 8) & 0xFF, bank])
    # UPL2_OLD was 5 bytes; the byte at UPL2+4 (0x21) is orphaned, skipped by the jml

    data += b"\x00" * ((len(data) + 0x7FFFF) // 0x80000 * 0x80000 - len(data))
    _fix_checksum(data)
    open(out, "wb").write(data)
    print(f"wrote {out} from {src}: stage={stage} bank={bank:#04x} "
          f"font={len(font_blob)}B input={len(inp_body)}B upl2={len(upl_body)}B, "
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
    ap = argparse.ArgumentParser(description="In-ROM training mode upgrade (patch 11).")
    ap.add_argument("src", nargs="?", default=CLEAN)
    ap.add_argument("out", nargs="?", default="build/sms_trainingplus.sfc")
    ap.add_argument("--stage", choices=["pipe"], default="pipe")
    a = ap.parse_args()
    if a.src == CLEAN:
        assert sha1(open(a.src, "rb").read()).hexdigest() == CLEAN_SHA1, "clean hash mismatch"
    build(a.src, a.out, a.stage)
