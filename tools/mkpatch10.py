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
from pathlib import Path as _P
REPO = _P(__file__).resolve().parent.parent  # repo root (cwd-independent)
sys.path.insert(0, str(REPO / "tools"))
from smspaths import clean_rom, require_source, check_not_inplace, fix_checksum, trim_banks, next_bank, write_bank  # ROM location: $SMS_ROM_DIR -> roms/ -> ../roms/
import asm65816 as A  # noqa: E402

CLEAN = clean_rom()

# Detection fingerprint (p10) — consumed by tools/mksigs.py to generate the
# regression suite's SIGS table. ONLY bytes invariant across stub-layout and
# bank-stacking changes: JML opcodes at the two HUD hooks (operands vary with bank/stub layout)
SIG = [(0xD56F, 0x5C), (0xD5E8, 0x5C)]
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

# ---- status labels (--events labels) ----
# per-player label state block (8 bytes each) in the verified-free $0900 page:
#   +0 prevAct  +1 conRec (any-constraint recency, sat)  +2 hardRec (hitstun/KD/thrown recency)
#   +3 movePhase (0 none/1 startup/2 active-seen)  +4 hpShadow  +5 labelId  +6 labelTTL  +7 shown
LST = (0x0900, 0x0908)            # P1, P2 label state
GLYPH_FLAG = 0x0910               # glyphs-uploaded-this-episode flag
LSTG = (0x0920, 0x0940)           # per-side glyph staging: dirty(+0) + 8 tile words(+1,+3,..+F)
# label row-7 cells (8 wide) under each player, disjoint from the combo counter's cells
# (counter bottoms at cols 2-3 left / 28-29 right; labels sit between with a gap):
LBL_CELL = (0x10E5, 0x10F2)       # LEFT $10E5-$10EC (col5), RIGHT $10F2-$10F9 (col18)
BLANK = 0x2000
BG3_CHR = 0x5000                  # BG3 CHR base (word); glyph tiles start at slot 0xC7
GLYPH_TILE0 = 0xC7
# id 4 was MEATY — removed 2026-07-20 on player feedback (felt like noise in live play);
# ids kept stable so GC/REVERSAL/PUNISH/TECH bytes and tests are unchanged.
LABELS = {1: "GC", 2: "REVERSAL", 3: "PUNISH", 5: "TECH"}
LABEL_TTL = 48
# id sets for constraint tests
HARD = "hitstun/KD/thrown"        # 0x10-0x20, 0x27-0x29 (hard constraint, for REVERSAL)


def _defender_logic(hp, act, st, ttl, sfx):
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
  lda ${st + 0:04X}
  cmp #$63
  bcs afth{sfx}
  inc ${st + 0:04X}
afth{sfx}:
  lda #${ttl:02X}
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
  cpx #$0A
  bcc t2k{sfx}
  ldx #$09
  lda #$09
t2k{sfx}:
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


import hudfont  # noqa: E402


def _font_and_words():
    """Build the glyph font blob + per-label list of 8 tilemap words (blank-padded)."""
    letters = []
    for s in LABELS.values():
        for c in s:
            if c not in letters:
                letters.append(c)
    blob, idx = hudfont.build_font(letters)
    words = {}
    for lid, s in LABELS.items():
        w = [0x2C00 | (GLYPH_TILE0 + idx[c]) for c in s]
        w += [BLANK] * (8 - len(w))
        words[lid] = w
    return blob, words


def _label_recency(p, sfx):
    """Phase 1: update conRec/hardRec/movePhase for player p from its current act/hitbox."""
    base = 0x1000 if p == 0 else 0x1080
    st = LST[p]
    act, hb = base + 0x01, base + 0x40
    return f"""
  lda ${act:04X}
  cmp #$2B
  bcc mvz{sfx}
  lda ${hb:04X}
  beq mvs{sfx}
  lda #$02
  sta ${st + 3:04X}
  bra mvd{sfx}
mvs{sfx}:
  lda ${st + 3:04X}
  bne mvd{sfx}
  lda #$01
  sta ${st + 3:04X}
  bra mvd{sfx}
mvz{sfx}:
  stz ${st + 3:04X}
mvd{sfx}:
  lda ${act:04X}
  cmp #$0E
  bcc cf{sfx}
  cmp #$21
  bcc cz{sfx}
  cmp #$23
  beq cz{sfx}
  cmp #$27
  bcc cf{sfx}
  cmp #$2A
  bcc cz{sfx}
cf{sfx}:
  lda ${st + 1:04X}
  cmp #$FF
  beq cd{sfx}
  inc ${st + 1:04X}
  bra cd{sfx}
cz{sfx}:
  stz ${st + 1:04X}
cd{sfx}:
  lda ${act:04X}
  cmp #$10
  bcc hf{sfx}
  cmp #$21
  bcc hz{sfx}
  cmp #$27
  bcc hf{sfx}
  cmp #$2A
  bcc hz{sfx}
hf{sfx}:
  lda ${st + 2:04X}
  cmp #$FF
  beq hd{sfx}
  inc ${st + 2:04X}
  bra hd{sfx}
hz{sfx}:
  stz ${st + 2:04X}
hd{sfx}:
"""


def _label_detect(p, sfx):
    """Phase 2: assign player p's earned label, priority LOW->HIGH (each overwrites).
    Uses p's prevAct/recency + the DEFENDER's (still last-frame) HP shadow + this-frame
    conRec/movePhase. Runs before shadows/prevAct are finalized."""
    base = 0x1000 if p == 0 else 0x1080
    st = LST[p]
    act = base + 0x01
    d = 1 - p
    dbase = 0x1000 if d == 0 else 0x1080
    dhp, dhb, dst = dbase + 0x49, dbase + 0x40, LST[d]
    return f"""
  ; hit event = defender HP dropped below its (last-frame) shadow
  lda ${dhp:04X}
  cmp ${dst + 4:04X}
  bcs nohit{sfx}
  ; (MEATY, formerly id 4 here at lowest prio, removed 2026-07-20)
  ; PUNISH: defender in recovery of its own move (phase==2 && hitbox==0)
  lda ${dst + 3:04X}
  cmp #$02
  bne nohit{sfx}
  lda ${dhb:04X}
  bne nohit{sfx}
  lda #$03
  sta ${st + 5:04X}
nohit{sfx}:
  ; REVERSAL (higher): attack act just started <=2 frames after leaving hard constraint
  lda ${act:04X}
  cmp #$2B
  bcc chkgc{sfx}
  lda ${st + 2:04X}
  cmp #$03
  bcs chkgc{sfx}
  lda ${st + 0:04X}
  cmp #$2B
  bcs chkgc{sfx}
  lda #$02
  sta ${st + 5:04X}
chkgc{sfx}:
  ; GC (higher): attack act with prevAct in blockstun {0x0E,0x0F}
  lda ${act:04X}
  cmp #$2B
  bcc chktech{sfx}
  lda ${st + 0:04X}
  cmp #$0E
  beq sgc{sfx}
  cmp #$0F
  bne chktech{sfx}
sgc{sfx}:
  lda #$01
  sta ${st + 5:04X}
chktech{sfx}:
  ; TECH (highest): curAct==0x23, prevAct!=0x23
  lda ${act:04X}
  cmp #$23
  bne setttl{sfx}
  lda ${st + 0:04X}
  cmp #$23
  beq setttl{sfx}
  lda #$05
  sta ${st + 5:04X}
setttl{sfx}:
  ; if a label was (re)assigned this frame, refresh TTL (detects change vs shown handled later)
  lda ${st + 5:04X}
  beq ldone{sfx}
  cmp ${st + 7:04X}
  beq ldone{sfx}
  lda #${LABEL_TTL:02X}
  sta ${st + 6:04X}
ldone{sfx}:
"""


def _label_finalize(p, sfx):
    """Phase 3: commit player p's HP shadow + prevAct for next frame."""
    base = 0x1000 if p == 0 else 0x1080
    st = LST[p]
    return f"""
  lda ${base + 0x49:04X}
  sta ${st + 4:04X}
  lda ${base + 0x01:04X}
  sta ${st + 0:04X}
"""


def _label_render(p, words, sfx):
    """TTL tick + stage 8 glyph words for player p's label into LSTG[p]. 8-bit then 16-bit.
    Far jumps use jmp (the case switch exceeds 8-bit branch range)."""
    st = LST[p]
    stg = LSTG[p]
    # build the switch: id -> 8 immediate word stores
    cases = ""
    for lid in sorted(LABELS):
        w = words[lid]
        stores = "".join(
            f"  lda #${w[k]:04X}\n  sta ${stg + 1 + 2 * k:04X}\n" for k in range(8))
        cases += f"""  lda ${st + 5:04X}
  cmp #${lid:02X}
  bne notid{lid}{sfx}
  rep #$20
{stores}  sep #$20
  jmp staged{sfx}
notid{lid}{sfx}:
"""
    blanks = "".join(f"  sta ${stg + 1 + 2 * k:04X}\n" for k in range(8))
    return f"""
  ; TTL tick
  lda ${st + 6:04X}
  beq ttl0{sfx}
  dec ${st + 6:04X}
  bne ttlok{sfx}
  stz ${st + 5:04X}      ; TTL expired -> labelId=0
ttl0{sfx}:
ttlok{sfx}:
  ; render if labelId != shown
  lda ${st + 5:04X}
  cmp ${st + 7:04X}
  bne rchg{sfx}
  jmp rdone{sfx}
rchg{sfx}:
  sta ${st + 7:04X}
  cmp #$00               ; sta sets no flags; Z here is stale from the cmp above
  bne draw{sfx}
  ; labelId==0 -> blank all 8 cells
  rep #$20
  lda #${BLANK:04X}
{blanks}  sep #$20
  lda #$01
  sta ${stg + 0:04X}
  jmp rdone{sfx}
draw{sfx}:
{cases}staged{sfx}:
  lda #$01
  sta ${stg + 0:04X}
rdone{sfx}:
"""


def _glyph_upload(font_addr, font_bank, font_size):
    """Flush-stub prologue: one-time-per-episode DMA of the glyph font to BG3 CHR (vblank)."""
    dst = BG3_CHR + GLYPH_TILE0 * 8
    return f"""
  sep #$20
  lda ${GLYPH_FLAG:04X}
  bne skipup
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
  sta ${GLYPH_FLAG:04X}
skipup:
  rep #$20
"""


def _flush_label(p, sfx):
    """Flush a player's 8-cell label glyph row to VRAM if dirty. 16-bit A on entry/exit."""
    stg = LSTG[p]
    cell = LBL_CELL[p]
    writes = "".join(f"  lda ${stg + 1 + 2 * k:04X}\n  sta $2118\n" for k in range(8))
    return f"""
  sep #$20
  lda ${stg + 0:04X}
  beq lf{sfx}
  stz ${stg + 0:04X}
  rep #$20
  lda #${cell:04X}
  sta $2116
{writes}  sep #$20
lf{sfx}:
  rep #$20
"""


def _label_gate(modes):
    """Emit: if $008D not in `modes`, skip the whole label pipeline (jmp lblskip).

    `_mode_gate`'s excluded path jumps to `dorender`, which blanks the counters —
    but the label recency/detect/finalize/render chain is concatenated AFTER the
    render blocks, so it still ran every frame in a mode the user excluded (#86).
    Default `--modes` is 0,1,2,4,5, so the excluded mode in practice is 3 —
    TOURNAMENT, which is exactly where you would least want it.
    """
    if not modes:
        return ""
    checks = "".join(f"  cmp #${mode:02X}\n  beq lok\n" for mode in modes)
    return f"""
  lda $008D
{checks}
  jmp lblskip
lok:
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


def build(src, out, stage="full", minhits=2, ttl=72, modes=(0x00, 0x01, 0x02, 0x04, 0x05),
          events="off"):
    if not 1 <= ttl <= 255:
        raise ValueError("ttl must be 1..255 frames")
    data = bytearray(open(src, "rb").read())
    data = trim_banks(data)
    if not (data[PROD:PROD + 4] == PROD_OLD):
        raise ValueError(f"producer hook bytes: {data[PROD:PROD+4].hex()}")
    if not (data[UPL:UPL + 5] == UPL_OLD):
        raise ValueError(f"uploader hook bytes: {data[UPL:UPL+5].hex()}")

    bankbase, bank = next_bank(data)
    labels = (events == "labels") and stage == "full"
    font_blob, label_words = _font_and_words() if labels else (b"", {})

    # ---- COMPUTE stub (producer hook): tick both defenders, stage both displays ----
    label_compute = ""
    if labels:
        label_compute = (
            _label_recency(0, "ra") + _label_recency(1, "rb")
            + _label_detect(0, "da") + _label_detect(1, "db")
            + _label_finalize(0, "fa") + _label_finalize(1, "fb")
            + _label_render(0, label_words, "na")   # P1 label -> LEFT-side label cells
            + _label_render(1, label_words, "nb")   # P2 label -> RIGHT-side label cells
            # re-arm glyph upload when both labels idle (survives per-match CHR reloads)
            + f"""
  lda ${LST[0] + 5:04X}
  ora ${LST[1] + 5:04X}
  bne glok
  stz ${GLYPH_FLAG:04X}
glok:
"""
        )
    if stage == "pipe":
        compute_src = ""   # pipeline test: no compute; flush writes a fixed pattern
    else:
        compute_src = (
            _mode_gate(modes if stage == "full" else None)
            + _defender_logic(0x1049, 0x1001, ST_P1D, ttl, "a")
            + _defender_logic(0x10C9, 0x1081, ST_P2D, ttl, "b")
            + "dorender:\n"
            + _render_logic(ST_P2D, STG_L, minhits, "l")   # P2 defender -> LEFT (attacker P1)
            + _render_logic(ST_P1D, STG_R, minhits, "r")   # P1 defender -> RIGHT (attacker P2)
            + (_label_gate(modes) if (labels and stage == "full") else "")
            + label_compute
            + ("lblskip:\n" if (labels and stage == "full") else "")
        )
    label_init = ""
    if labels:
        label_init = (
            f"  stz ${GLYPH_FLAG:04X}\n"
            + "".join(f"  stz ${LST[p] + k:04X}\n" for p in (0, 1) for k in range(8))
            + f"  lda $1049\n  sta ${LST[0] + 4:04X}\n"
            + f"  lda $10C9\n  sta ${LST[1] + 4:04X}\n"
            + f"  stz ${LSTG[0]:04X}\n  stz ${LSTG[1]:04X}\n"
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
{label_init}go:
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

    def make_flush(font_addr):
        upload = _glyph_upload(font_addr, bank, len(font_blob)) if labels else ""
        labelflush = (_flush_label(0, "la") + _flush_label(1, "lb")) if labels else ""
        return f"""
  rep #$30
{upload}{flush_body}{labelflush}
  sep #$20
  rep #$20
  lda $0806
  jml ${UPL_CONT:06X}
"""

    # assemble: compute stub first, then flush stub, then font blob (forward ref → 2-pass)
    compute_bytes, _ = A.assemble(compute_asm.splitlines(), bankbase & 0xFFFF, bank)
    flush_off = (bankbase & 0xFFFF) + len(compute_bytes)
    flush_bytes, _ = A.assemble(make_flush(0).splitlines(), flush_off, bank)
    font_off = (bankbase & 0xFFFF) + len(compute_bytes) + len(flush_bytes)
    if labels:
        flush_bytes, _ = A.assemble(make_flush(font_off).splitlines(), flush_off, bank)
        font_off = (bankbase & 0xFFFF) + len(compute_bytes) + len(flush_bytes)

    blob = bytearray(compute_bytes) + flush_bytes + font_blob
    write_bank(data, bankbase, blob)   # 64K-fit + virgin-bank guards (#27)

    # repoint the two hooks (JML into the appended bank)
    ca = bankbase & 0xFFFF
    data[PROD:PROD + 4] = bytes([0x5C, ca & 0xFF, (ca >> 8) & 0xFF, bank])
    data[UPL:UPL + 4] = bytes([0x5C, flush_off & 0xFF, (flush_off >> 8) & 0xFF, bank])
    # (UPL_OLD was 5 bytes; byte at UPL+4 = 0x08 is orphaned, skipped by the jml)

    data[0xFFC0:0xFFD5] = b"\xBE\xB0\xD7\xB0\xD1\xB0\xDDS FrenchName  "
    data += b"\x00" * ((len(data) + 0x7FFFF) // 0x80000 * 0x80000 - len(data))
    fix_checksum(data)
    open(out, "wb").write(data)
    print(f"wrote {out} from {src}: stage={stage} bank={bank:#04x} "
          f"compute={len(compute_bytes)}B flush={len(flush_bytes)}B, "
          f"{len(data):#x} bytes, sha1={sha1(bytes(data)).hexdigest()}")




if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="In-match combo counter (base game).")
    ap.add_argument("src", nargs="?", default=CLEAN)
    ap.add_argument("out", nargs="?", default=str(REPO / "build/sms_combocounter.sfc"))
    ap.add_argument("--stage", choices=["pipe", "combo", "full"], default="full",
                    help="pipe=fixed-pattern pipeline test; full=combo counter")
    ap.add_argument("--min-hits", type=int, default=2)
    ap.add_argument("--ttl", type=int, default=72)
    ap.add_argument("--modes", default="0,1,2,4,5",
                    help="game_mode ($008D) values to show in, comma hex/dec; "
                         "'all' = every match (default 0,1,2,4,5 = VS + vs-COM + training)")
    ap.add_argument("--events", choices=["off", "labels"], default="off",
                    help="off = combo counter only (default); labels = also show "
                         "GC/REVERSAL/PUNISH/TECH status text")
    ap.add_argument("--stacked", action="store_true",
                    help="src is an already-patched ROM (builder chaining); skips the clean-SHA gate")
    a = ap.parse_args()
    check_not_inplace(a.src, a.out)
    require_source(a.src, a.stacked)
    # flag validation (issue #37): reject instead of silently dropping/truncating
    if a.events == "labels" and a.stage != "full":
        raise SystemExit("error: --events labels requires --stage full "
                         f"(got --stage {a.stage}); labels ride the full counter pipeline")
    if not 1 <= a.min_hits <= 99:
        raise SystemExit(f"error: --min-hits {a.min_hits} out of range 1..99 (display caps at 99)")
    if not 1 <= a.ttl <= 255:
        raise SystemExit(f"error: --ttl {a.ttl} out of range 1..255 frames")
    modes = () if a.modes.strip().lower() == "all" else tuple(int(m, 0) for m in a.modes.split(","))
    if any(not 0 <= m <= 255 for m in modes):
        raise SystemExit(f"error: --modes values must be 0..255 ($008D is one byte): {a.modes}")
    build(a.src, a.out, a.stage, a.min_hits, a.ttl, modes, a.events)
