#!/usr/bin/env python3
"""Patch 11 (OPTIONAL): in-ROM TRAINING MODE UPGRADE for the base game's Practice mode.

Adds to the native Practice mode (game_mode 4/5), rendered and driven entirely by the
base game (works on hardware): an L+R in-match menu on BG3 controlling
  POSE (stand/crouch/jump) . GUARD (off/all) . WAKEUP (off/jab/throw/backdash)
  TECH (throw-tech mash) . DAMAGE (the native 4<->5 damage switch) . REGEN . REFILL
  RESET (position reset)
The dummy is driven by rewriting P2's pad words after joy_read -- the same input-level
mechanism as the Lua training mode (the oracle), never by forcing action bytes.

Native Practice facts this is built on (probe-verified, docs/annotations.md "patch 11 RE"):
  * $008D: 4 = training, hits connect but HP subtraction is off; 5 = damage on (the
    attract demo also runs at 5 -> gate accepts 5 only when WE set it, via DMGFLAG).
  * $0070 == 4 in any match; $01FA == 0x80 match running / 0xE4 movelist (Start).
    Select exits. Both native functions are preserved (menu eats P1 input while open).
  * HUD producer never runs in Practice (no HUD/timer). BG3 = the pre-staged movelist
    layer, restaged on every Start press -> the patch may paint BG3 freely; TM ($212C,
    0x13 here / 0x17 with BG3) is written by the game only at scene setup, so the patch
    forces 0x17 per-vblank only while its menu is showing.
  * joy_read tail $80:8373: held words stored, press edges not yet derived -- rewriting
    $5C-$5F here is a perfect input override (edges auto-derive; 44 recognizer fires).
  * Bank $7F is untouched in steady-state play -> all state lives at $7F:F000+ (long
    addressing). Boot clears it; MAGIC re-inits defaults on first gated frame.

Hooks (byte-disjoint from patches 1-10; stacking order never matters):
  * $80:8373 joy_read tail -> INPUT stub (all logic; runs every frame, self-gates)
  * $80:D574 uploader body -> UPL2 stub (all VRAM/TM work, vblank; branch-aware replay)

Stages: pipe (plumbing smoke test) / tier1 (full build; default).
"""
import argparse
from hashlib import sha1
import sys
from pathlib import Path as _P
REPO = _P(__file__).resolve().parent.parent  # repo root (cwd-independent)
sys.path.insert(0, str(REPO / "tools"))
from smspaths import clean_rom  # ROM location: $SMS_ROM_DIR -> roms/ -> ../roms/
import asm65816 as A  # noqa: E402
import hudfont  # noqa: E402

CLEAN = clean_rom()
CLEAN_SHA1 = "bc0e29ee383574443226695215496eb0d09aaa1c"

INP = 0x008373
INP_OLD = bytes.fromhex("c220a55c")
INP_CONT = 0x808377
UPL2 = 0x00D574
UPL2_OLD = bytes.fromhex("f0208d1621")
UPL2_CONT_STA = 0x80D579
UPL2_CONT_BEQ = 0x80D596
P10_PROD, P10_PROD_OLD = 0x00D5E8, bytes.fromhex("c210e220")
P10_UPL, P10_UPL_OLD = 0x00D56F, bytes.fromhex("c230ad0608")

# ---------------- $7F:F000 state block ----------------
ST = 0x7FF000
MAGIC = ST + 0x00     # 0xA5 = initialized
FONTUP = ST + 0x01    # font uploaded this visibility episode
VISIBLE = ST + 0x02   # gate result (INPUT -> UPL2)
DMGFLAG = ST + 0x04   # 0xA5 = mode 5 set by us
MENUOPEN = ST + 0x05
CURSOR = ST + 0x06    # 1..8 (row 0 = title)
EATLINGER = ST + 0x07
PREVH_L = ST + 0x08   # raw P1 held shadows (our own edge chain)
PREVH_H = ST + 0x09
EDGE_L = ST + 0x0A
EDGE_H = ST + 0x0B
SIDEBACK = ST + 0x0C  # $5F back-direction bit for P2 (01=Right, 02=Left)
UIVIS = ST + 0x0D     # menu painted & showing (TM keyed to this)
PAINTROW = ST + 0x0E  # 0=font, 1..9=rows, 0xFF idle
CLEARROW = ST + 0x0F  # 0..8 rows, 0xFF idle
PREVUI = ST + 0x10
CURSDIRT = ST + 0x11  # repaint all cursor cells
REDRAW_A = ST + 0x12  # row idx or 0xFF
RESETREQ = ST + 0x13
# settings
SET_POSE = ST + 0x20   # 0 stand, 1 crouch, 2 jump
SET_GUARD = ST + 0x21  # 0 off, 1 all
SET_WAKE = ST + 0x22   # 0 off, 1 jab, 2 throw, 3 backdash
SET_TECH = ST + 0x23   # 0 off, 1 on
SET_DMG = ST + 0x24    # 0 off, 1 on
SET_REGEN = ST + 0x25  # 0 off, 1 on (dummy)
SET_REFILL = ST + 0x26 # 0 off, 1 on (both players)
SET_REC = ST + 0x27    # 0 off, 1 armed (consumed at menu close)
SET_PLAY = ST + 0x28   # 0 off, 1 once, 2 loop
SET_SHOW = ST + 0x29   # 0 off, 1 on (input + advantage display)
SET_P1HP = ST + 0x2A   # 0 full, 1 low (0x17 = desperation range, <=0x18)
SETTINGS = (SET_POSE, SET_GUARD, SET_WAKE, SET_TECH, SET_DMG, SET_REGEN, SET_REFILL,
            SET_REC, SET_PLAY, SET_SHOW, SET_P1HP)
# dummy runtime
WAKEARMED = ST + 0x30
OSFRAMES = ST + 0x31
OSLO = ST + 0x32
OSHI = ST + 0x33
BDPHASE = ST + 0x34
TECHPHASE = ST + 0x35
REGENT = ST + 0x36
HPSHAD2 = ST + 0x37
REFILLED2 = ST + 0x38   # we refilled P2 during this knockdown -> force standup at 0x1E
REFILLED1 = ST + 0x39
GOTHIT = ST + 0x3A      # P2 has been hit/thrown (guard=afterhit latch, oracle semantics)
# recording/playback (ring at $7F:E000, via WMDATA $2180-83 -- probe-verified free)
RECACTIVE = ST + 0x42
RECPTR = ST + 0x44      # 16-bit byte offset into the ring (2 bytes/frame: $5D,$5C raw)
RECLEN = ST + 0x46      # 16-bit
PLAYPTR = ST + 0x48     # 16-bit
PLAYACTIVE = ST + 0x4A
CAPT_L = ST + 0x4B
CAPT_H = ST + 0x4C
# SHOW displays
WIPED = ST + 0x55       # BG3 rows 0-17 wiped this episode
PMODE = ST + 0x56       # painter mode: 0 = wipe+menu, 1 = wipe-only (SHOW)
TMWANT = ST + 0x57      # computed each frame: BG3 wanted on
CNT1 = ST + 0x58        # frames-actionable counters (advantage approximation)
CNT2 = ST + 0x59
EXCH = ST + 0x5A        # an exchange (constraint) happened since last settle
ADVSIGN = ST + 0x5B
ADVMAG = ST + 0x5C
ADVTTL = ST + 0x5D
ADVDIRTY = ST + 0x5E
INPDIRTY = ST + 0x5F
SHOWPREV_L = ST + 0x60
SHOWPREV_H = ST + 0x61
HPSH1 = ST + 0x62       # HP-readout shadows (SHOW display)
HPSH2 = ST + 0x63
HPDIRTY = ST + 0x64
SCRONES = ST + 0x65
REC_BASE = 0xE000       # WMDATA 16-bit offset within bank $7F ($2183=1)
REC_MAX = 0x0FFE        # 2047 frames ~ 34s

# ---------------- BG3 / font ----------------
BG3_CHR = 0x5000
GLYPH_TILE0 = 0xC7
BLANK = 0x2000
TM_ON, TM_OFF = 0x17, 0x13
P10_LETTERS = list("GCREVSALPUNIHMTY")
P11_LETTERS = list("BDFJKOW") + [">", "-"]
FONT_LETTERS = P10_LETTERS + P11_LETTERS
assert len(FONT_LETTERS) <= 25

# menu geometry: 9 rows on BG3 map rows 4-12, cells cols 3-24 (22 cells/row)
PANEL_ROW0, PANEL_COL, PANEL_W = 4, 3, 22
NROWS = 13
WIPEROWS = 18   # menu-open first blanks BG3 map rows 0-17 full-width (movelist residue)
# per painted row, offsets within the 22 cells: cursor@1, name@3(6), value@10(8)
CUR_OFF, NAME_OFF, VAL_OFF = 1, 3, 10
MENU = [
    ("TRAINING", None, None),                                  # 0: title
    ("POSE",   SET_POSE,  ["STAND", "CROUCH", "JUMP"]),        # 1
    ("GUARD",  SET_GUARD, ["OFF", "ALL", "HIT"]),              # 2 (HIT = after first hit)
    ("WAKEUP", SET_WAKE,  ["OFF", "JAB", "THROW", "DASH"]),    # 3
    ("TECH",   SET_TECH,  ["OFF", "ON"]),                      # 4
    ("DAMAGE", SET_DMG,   ["OFF", "ON"]),                      # 5
    ("REGEN",  SET_REGEN, ["OFF", "ON"]),                      # 6
    ("REFILL", SET_REFILL,["OFF", "ON"]),                      # 7
    ("RECORD", SET_REC,   ["OFF", "ARM"]),                     # 8 (consumed at close)
    ("PLAY",   SET_PLAY,  ["OFF", "ONCE", "LOOP"]),            # 9
    ("SHOW",   SET_SHOW,  ["OFF", "ON"]),                      # 10 (input + adv display)
    ("P1 HP",  SET_P1HP,  ["FULL", "LOW"]),                    # 11 (LOW = desperation range)
    ("RESET",  None,      ["GO"]),                             # 12: action row
]
DMG_ROW, RESET_ROW, P1HP_ROW = 5, 12, 11


def row_addr(i):
    return 0x1000 + (PANEL_ROW0 + i) * 32 + PANEL_COL


def _words(text, width, idx):
    w = []
    for c in text:
        if c == " ":
            w.append(BLANK)
        elif c.isdigit():
            w.append(0x2C50 + int(c))     # resident HUD digit tiles (top half)
        else:
            assert c in idx, f"glyph missing: {c}"
            w.append(0x2C00 | (GLYPH_TILE0 + idx[c]))
    return w + [BLANK] * (width - len(w))


# ================= INPUT stub =================

def _gate():
    set_zeros = "".join(f"  sta_l ${s:06X}\n" for s in SETTINGS)
    return f"""
  lda $008D
  cmp #$04
  beq gmode
  cmp #$05
  bne gofar
  lda_l ${DMGFLAG:06X}
  cmp #$A5
  beq gmode
gofar:
  jmp goff
gmode:
  lda $0070
  cmp #$04
  beq g2
  jmp goff
g2:
  lda $01FA
  cmp #$80
  beq g3
  jmp goffkeep
g3:
  lda #$01
  sta_l ${VISIBLE:06X}
  jmp ginit
goff:
  lda_l ${DMGFLAG:06X}
  cmp #$A5
  bne gof1
  lda $0070
  cmp #$04
  beq gof1
  lda #$04
  sta $008D
  lda #$00
  sta_l ${DMGFLAG:06X}
gof1:
  lda #$FF
  sta_l ${CLEARROW:06X}
  lda #$00
  sta_l ${MENUOPEN:06X}
  sta_l ${EATLINGER:06X}
  sta_l ${WAKEARMED:06X}
  sta_l ${OSFRAMES:06X}
  sta_l ${BDPHASE:06X}
  sta_l ${TECHPHASE:06X}
  sta_l ${REGENT:06X}
  sta_l ${RESETREQ:06X}
  sta_l ${REFILLED2:06X}
  sta_l ${REFILLED1:06X}
goffkeep:
  lda_l ${RECACTIVE:06X}
  beq gkrec
  lda #$00
  sta_l ${RECACTIVE:06X}
  rep #$20
  lda_l ${RECPTR:06X}
  sta_l ${RECLEN:06X}
  sep #$20
gkrec:
  lda #$00
  sta_l ${PLAYACTIVE:06X}
  sta_l ${WIPED:06X}
  sta_l ${TMWANT:06X}
  sta_l ${ADVTTL:06X}
  sta_l ${ADVDIRTY:06X}
  sta_l ${INPDIRTY:06X}
  sta_l ${CNT1:06X}
  sta_l ${CNT2:06X}
  sta_l ${EXCH:06X}
  sta_l ${VISIBLE:06X}
  sta_l ${FONTUP:06X}
  sta_l ${UIVIS:06X}
  sta_l ${MENUOPEN:06X}
  sta_l ${CURSDIRT:06X}
  lda #$FF
  sta_l ${PAINTROW:06X}
  sta_l ${REDRAW_A:06X}
  jmp exit
ginit:
  lda_l ${MAGIC:06X}
  cmp #$A5
  bne doinit
  jmp inited
doinit:
  lda #$A5
  sta_l ${MAGIC:06X}
  lda #$00
{set_zeros}  sta_l ${WAKEARMED:06X}
  sta_l ${OSFRAMES:06X}
  sta_l ${BDPHASE:06X}
  sta_l ${TECHPHASE:06X}
  sta_l ${REGENT:06X}
  sta_l ${RESETREQ:06X}
  sta_l ${GOTHIT:06X}
  sta_l ${UIVIS:06X}
  sta_l ${PREVUI:06X}
  sta_l ${CURSDIRT:06X}
  sta_l ${EATLINGER:06X}
  sta_l ${PREVH_L:06X}
  sta_l ${PREVH_H:06X}
  sta_l ${RECACTIVE:06X}
  sta_l ${PLAYACTIVE:06X}
  sta_l ${WIPED:06X}
  sta_l ${TMWANT:06X}
  sta_l ${ADVTTL:06X}
  rep #$20
  sta_l ${RECLEN:06X}
  sta_l ${RECPTR:06X}
  sta_l ${PLAYPTR:06X}
  sep #$20
  lda #$01
  sta_l ${CURSOR:06X}
  lda #$FF
  sta_l ${PAINTROW:06X}
  sta_l ${CLEARROW:06X}
  sta_l ${REDRAW_A:06X}
inited:
"""


def _edges():
    """EDGE = raw & ~prev, per byte; then prev = raw. Uses P1 held $5C/$5D."""
    return f"""
  lda_l ${PREVH_L:06X}
  eor #$FF
  and $005C
  sta_l ${EDGE_L:06X}
  lda $005C
  sta_l ${PREVH_L:06X}
  lda_l ${PREVH_H:06X}
  eor #$FF
  and $005D
  sta_l ${EDGE_H:06X}
  lda $005D
  sta_l ${PREVH_H:06X}
"""


def _chord():
    """L+R chord (both held + fresh edge on either) toggles the menu."""
    return f"""
  lda $005C
  and #$30
  cmp #$30
  beq chord1
  jmp nochord
chord1:
  lda_l ${EDGE_L:06X}
  and #$30
  bne chord2
  jmp nochord
chord2:
  lda_l ${MENUOPEN:06X}
  bne chclosej
  lda_l ${RECACTIVE:06X}
  beq oprec
  lda #$00
  sta_l ${RECACTIVE:06X}
  rep #$20
  lda_l ${RECPTR:06X}
  sta_l ${RECLEN:06X}
  sep #$20
oprec:
  lda #$00
  sta_l ${PLAYACTIVE:06X}
  lda #$01
  sta_l ${MENUOPEN:06X}
  lda #$01
  sta_l ${CURSOR:06X}
  lda #$00
  sta_l ${PAINTROW:06X}
  sta_l ${PMODE:06X}
  lda #$FF
  sta_l ${CLEARROW:06X}
  sta_l ${REDRAW_A:06X}
  jmp nochord
chclosej:
  lda #$00
  sta_l ${MENUOPEN:06X}
  sta_l ${UIVIS:06X}
  sta_l ${CLEARROW:06X}
  lda #$FF
  sta_l ${PAINTROW:06X}
  sta_l ${REDRAW_A:06X}
  lda #$02
  sta_l ${EATLINGER:06X}
  lda_l ${SET_REC:06X}
  beq ccnorec
  lda #$00
  sta_l ${SET_REC:06X}
  lda #$01
  sta_l ${RECACTIVE:06X}
  rep #$20
  lda #$0000
  sta_l ${RECPTR:06X}
  sep #$20
  jmp nochord
ccnorec:
  lda_l ${SET_PLAY:06X}
  bne ccplay1
  jmp nochord
ccplay1:
  rep #$20
  lda_l ${RECLEN:06X}
  sep #$20
  bne ccplay2
  jmp nochord
ccplay2:
  lda #$01
  sta_l ${PLAYACTIVE:06X}
  rep #$20
  lda #$0000
  sta_l ${PLAYPTR:06X}
  sep #$20
nochord:
  lda_l ${MENUOPEN:06X}
  bne showdone
  lda_l ${SET_SHOW:06X}
  beq showdone
  lda_l ${WIPED:06X}
  bne showdone
  lda_l ${PAINTROW:06X}
  cmp #$FF
  bne showdone
  lda_l ${CLEARROW:06X}
  cmp #$FF
  bne showdone
  lda #$00
  sta_l ${PAINTROW:06X}
  lda #$01
  sta_l ${PMODE:06X}
showdone:
"""


def _menu_fsm():
    """Navigation + value edit while MENUOPEN; eats all P1 input."""
    # left/right value adjust: per-row chain
    adj = ""
    for i, (name, setaddr, vals) in enumerate(MENU):
        if i == 0:
            continue
        if i == RESET_ROW:
            adj += f"""
  lda_l ${CURSOR:06X}
  cmp #${i:02X}
  bne adj{i}
  lda #$01
  sta_l ${RESETREQ:06X}
  jmp adjdone
adj{i}:
"""
            continue
        mx = len(vals) - 1
        dmgfx = ""
        if i == P1HP_ROW:
            dmgfx = f"""
  lda_l ${SET_P1HP:06X}
  bne p1hplow
  lda $104A
  sta $1049
  bra p1hpfx
p1hplow:
  lda #$17
  sta $1049
p1hpfx:
"""
        if i == DMG_ROW:
            dmgfx = f"""
  lda_l ${SET_DMG:06X}
  bne dmgon
  lda #$04
  sta $008D
  lda #$00
  sta_l ${DMGFLAG:06X}
  bra dmgfx
dmgon:
  lda #$05
  sta $008D
  lda #$A5
  sta_l ${DMGFLAG:06X}
dmgfx:
"""
        adj += f"""
  lda_l ${CURSOR:06X}
  cmp #${i:02X}
  bne adj{i}
  lda_l ${EDGE_H:06X}
  and #$01
  beq lft{i}
  lda_l ${setaddr:06X}
  inc_a
  cmp #${mx + 1:02X}
  bne st{i}
  lda #$00
st{i}:
  sta_l ${setaddr:06X}
  bra fx{i}
lft{i}:
  lda_l ${setaddr:06X}
  bne dn{i}
  lda #${mx + 1:02X}
dn{i}:
  dec_a
  sta_l ${setaddr:06X}
fx{i}:
{dmgfx}  lda_l ${CURSOR:06X}
  sta_l ${REDRAW_A:06X}
  jmp adjdone
adj{i}:
"""
    return f"""
  lda_l ${MENUOPEN:06X}
  bne fsm1
  jmp fsmclosed
fsm1:
  lda_l ${EDGE_H:06X}
  and #$08
  beq noup
  lda_l ${CURSOR:06X}
  dec_a
  bne upok
  lda #${NROWS - 1:02X}
upok:
  sta_l ${CURSOR:06X}
  lda #$01
  sta_l ${CURSDIRT:06X}
noup:
  lda_l ${EDGE_H:06X}
  and #$04
  beq nodn
  lda_l ${CURSOR:06X}
  inc_a
  cmp #${NROWS:02X}
  bne dnok
  lda #$01
dnok:
  sta_l ${CURSOR:06X}
  lda #$01
  sta_l ${CURSDIRT:06X}
nodn:
  lda_l ${EDGE_H:06X}
  and #$03
  bne adjust
  jmp eat
adjust:
{adj}adjdone:
eat:
  lda #$00
  sta $005C
  sta $005D
  jmp fsmdone
fsmclosed:
  lda_l ${EATLINGER:06X}
  beq fsmdone
  dec_a
  sta_l ${EATLINGER:06X}
  lda #$00
  sta $005C
  sta $005D
fsmdone:
"""


def _actionable(src_label, ok_label, fail_label, sfx):
    """A holds an act id: branch to ok if actionable (<=4, 0C, 0D, 0x21), else fail."""
    return f"""
  cmp #$05
  bcc {ok_label}
  cmp #$0C
  beq {ok_label}
  cmp #$0D
  beq {ok_label}
  cmp #$21
  beq {ok_label}
  jmp {fail_label}
"""


def _reset():
    """Position reset: guarded on both players actionable + no hitstop; Lua write set."""
    return f"""
  lda_l ${RESETREQ:06X}
  bne rs0
  jmp rsdone
rs0:
  lda #$00
  sta_l ${RESETREQ:06X}
  lda $104D
  bne rsfail
  lda $10CD
  bne rsfail
  lda $1001
{_actionable("", "rsp2", "rsdone", "r1")}
rsp2:
  lda $1081
{_actionable("", "rsgo", "rsdone", "r2")}
rsgo:
  stz $1001
  stz $1002
  stz $1004
  stz $1006
  stz $1007
  stz $1081
  stz $1082
  stz $1084
  stz $1086
  stz $1087
  lda #$C8
  sta $1021
  stz $1022
  lda #$10
  sta $10A1
  lda #$01
  sta $10A2
  lda #$00
  sta_l ${WAKEARMED:06X}
  sta_l ${OSFRAMES:06X}
  sta_l ${BDPHASE:06X}
  sta_l ${TECHPHASE:06X}
  sta_l ${GOTHIT:06X}
rsfail:
rsdone:
"""


def _dummy():
    """Side detect + wakeup arm/fire + injection priority chain (writes $5E/$5F)."""
    return f"""
  rep #$20
  lda $10A1
  cmp $1021
  sep #$20
  bcs sbr
  lda #$02
  bra sbw
sbr:
  lda #$01
sbw:
  sta_l ${SIDEBACK:06X}
  lda $1081
  cmp #$19
  bcc wa1
  cmp #$21
  bcc arm
wa1:
  cmp #$27
  bcc wadone
  cmp #$2A
  bcs wadone
arm:
  lda #$01
  sta_l ${WAKEARMED:06X}
wadone:
  lda $1081
  cmp #$10
  bcc gh1
  cmp #$19
  bcc ghset
gh1:
  cmp #$1B
  bcc ghdone
  cmp #$1E
  bcs ghdone
ghset:
  lda #$01
  sta_l ${GOTHIT:06X}
ghdone:
  lda_l ${WAKEARMED:06X}
  beq nofire
  lda $1081
{_actionable("", "fire", "nofire", "wf")}
fire:
  lda #$00
  sta_l ${WAKEARMED:06X}
  lda_l ${SET_WAKE:06X}
  beq nofire
  cmp #$01
  bne wthrow
  lda #$03
  sta_l ${OSFRAMES:06X}
  lda #$40
  sta_l ${OSHI:06X}
  lda #$00
  sta_l ${OSLO:06X}
  bra nofire
wthrow:
  cmp #$02
  bne wbd
  lda #$03
  sta_l ${OSFRAMES:06X}
  lda_l ${SIDEBACK:06X}
  eor #$03
  sta_l ${OSHI:06X}
  lda #$40
  sta_l ${OSLO:06X}
  bra nofire
wbd:
  lda #$06
  sta_l ${BDPHASE:06X}
nofire:
  lda_l ${RECACTIVE:06X}
  bne dorec
  jmp injplay
dorec:
  lda $005D
  sta_l ${CAPT_H:06X}
  lda $005C
  sta_l ${CAPT_L:06X}
  lda #$01
  sta $2183
  rep #$20
  lda_l ${RECPTR:06X}
  clc
  adc #${REC_BASE:04X}
  sta $2181
  sep #$20
  lda_l ${CAPT_H:06X}
  sta $2180
  lda_l ${CAPT_L:06X}
  sta $2180
  rep #$20
  lda_l ${RECPTR:06X}
  inc_a
  inc_a
  sta_l ${RECPTR:06X}
  cmp #${REC_MAX:04X}
  sep #$20
  bcc recok
  lda #$00
  sta_l ${RECACTIVE:06X}
  rep #$20
  lda_l ${RECPTR:06X}
  sta_l ${RECLEN:06X}
  sep #$20
recok:
  lda #$00
  sta $005C
  sta $005D
  lda_l ${CAPT_H:06X}
  sta $005F
  lda_l ${CAPT_L:06X}
  sta $005E
  jmp injdone
injplay:
  lda_l ${PLAYACTIVE:06X}
  bne doplay
  jmp injos0
doplay:
  lda #$01
  sta $2183
  rep #$20
  lda_l ${PLAYPTR:06X}
  clc
  adc #${REC_BASE:04X}
  sta $2181
  sep #$20
  lda $2180
  sta $005F
  lda $2180
  sta $005E
  rep #$20
  lda_l ${PLAYPTR:06X}
  inc_a
  inc_a
  sta_l ${PLAYPTR:06X}
  cmp_l ${RECLEN:06X}
  sep #$20
  bcc playok
  lda_l ${SET_PLAY:06X}
  cmp #$02
  beq ploop
  lda #$00
  sta_l ${PLAYACTIVE:06X}
  bra playok
ploop:
  rep #$20
  lda #$0000
  sta_l ${PLAYPTR:06X}
  sep #$20
playok:
  jmp injdone
injos0:
  lda_l ${OSFRAMES:06X}
  beq injbd
  dec_a
  sta_l ${OSFRAMES:06X}
  lda_l ${OSHI:06X}
  sta $005F
  lda_l ${OSLO:06X}
  sta $005E
  jmp injdone
injbd:
  lda_l ${BDPHASE:06X}
  beq injtech
  cmp #$05
  beq bdneu
  lda_l ${SIDEBACK:06X}
  sta $005F
  stz $005E
  bra bddec
bdneu:
  stz $005F
  stz $005E
bddec:
  lda_l ${BDPHASE:06X}
  dec_a
  sta_l ${BDPHASE:06X}
  jmp injdone
injtech:
  lda_l ${SET_TECH:06X}
  beq injguard
  lda $1081
  cmp #$1B
  beq tmash
  cmp #$1C
  beq tmash
  bra injguard
tmash:
  lda_l ${TECHPHASE:06X}
  inc_a
  sta_l ${TECHPHASE:06X}
  and #$01
  beq toff
  lda #$80
  sta $005E
  stz $005F
  jmp injdone
toff:
  stz $005E
  stz $005F
  jmp injdone
injguard:
  lda_l ${SET_GUARD:06X}
  beq injpose
  cmp #$01
  beq doguard
  lda_l ${GOTHIT:06X}
  beq injpose
doguard:
  lda_l ${SIDEBACK:06X}
  ora #$04
  sta $005F
  stz $005E
  jmp injdone
injpose:
  lda_l ${SET_POSE:06X}
  beq injdone
  cmp #$01
  bne pjump
  lda #$04
  sta $005F
  stz $005E
  bra injdone
pjump:
  lda #$08
  sta $005F
  stz $005E
injdone:
"""


def _effects():
    """HP regen (dummy) + KO refill (both). Constraint chain mirrors patch 10's."""
    def constrained(act, ok, fail, sfx):
        return f"""
  lda ${act:04X}
  cmp #$0E
  bcc {fail}
  cmp #$21
  bcc {ok}
  cmp #$23
  beq {ok}
  cmp #$27
  bcc {fail}
  cmp #$2A
  bcc {ok}
  bra {fail}
"""
    return f"""
  lda_l ${SET_REGEN:06X}
  beq rgshad
  lda $10C9
  cmp $10CA
  bcs rgshad
  cmp_l ${HPSHAD2:06X}
  bcs rg1
  lda #$78
  sta_l ${REGENT:06X}
rg1:
{constrained(0x1081, "rghold", "rgtick", "rg")}
rghold:
  lda #$78
  sta_l ${REGENT:06X}
  bra rgshad
rgtick:
  lda_l ${REGENT:06X}
  beq rgshad
  dec_a
  sta_l ${REGENT:06X}
  bne rgshad
  lda $10CA
  sta $10C9
rgshad:
  lda $10C9
  sta_l ${HPSHAD2:06X}
  lda_l ${SET_REFILL:06X}
  bne dorf
  jmp rfdone
dorf:
  lda $10C9
  bne rfs2
  lda $1081
  cmp #$10
  bcc rfs2
  cmp #$2A
  bcs rfs2
  lda $10CA
  sta $10C9
  lda #$01
  sta_l ${REFILLED2:06X}
rfs2:
  lda_l ${REFILLED2:06X}
  beq rfp1
  lda $1081
  cmp #$1E
  bne rfp1
  lda #$20
  sta $1081
  sta $1084
  lda #$01
  sta $1082
  stz $1086
  stz $1087
  lda #$00
  sta_l ${REFILLED2:06X}
rfp1:
  lda $1049
  bne rfs1
  lda $1001
  cmp #$10
  bcc rfs1
  cmp #$2A
  bcs rfs1
  lda $104A
  sta $1049
  lda #$01
  sta_l ${REFILLED1:06X}
rfs1:
  lda_l ${REFILLED1:06X}
  beq rfdone
  lda $1001
  cmp #$1E
  bne rfdone
  lda #$20
  sta $1001
  sta $1004
  lda #$01
  sta $1002
  stz $1006
  stz $1007
  lda #$00
  sta_l ${REFILLED1:06X}
rfdone:
  lda $1001
  cmp #$04
  bcc a1ok
  cmp #$0C
  beq a1ok
  cmp #$0D
  beq a1ok
  lda #$00
  sta_l ${CNT1:06X}
  bra a1d
a1ok:
  lda_l ${CNT1:06X}
  cmp #$FF
  beq a1d
  inc_a
  sta_l ${CNT1:06X}
a1d:
  lda $1081
  cmp #$04
  bcc a2ok
  cmp #$0C
  beq a2ok
  cmp #$0D
  beq a2ok
  lda #$00
  sta_l ${CNT2:06X}
  bra a2d
a2ok:
  lda_l ${CNT2:06X}
  cmp #$FF
  beq a2d
  inc_a
  sta_l ${CNT2:06X}
a2d:
  lda $1001
  cmp #$0E
  bcc ex1
  cmp #$2A
  bcs ex1
  lda #$01
  sta_l ${EXCH:06X}
ex1:
  lda $1081
  cmp #$0E
  bcc ex2
  cmp #$2A
  bcs ex2
  lda #$01
  sta_l ${EXCH:06X}
ex2:
  lda_l ${EXCH:06X}
  bne adv0
  jmp advttl
adv0:
  lda_l ${CNT1:06X}
  beq advttlj
  lda_l ${CNT2:06X}
  beq advttlj
  cmp #$01
  beq settle2
  lda_l ${CNT1:06X}
  cmp #$01
  beq settle1
advttlj:
  jmp advttl
settle2:
  lda_l ${CNT1:06X}
  cmp #$02
  bcc advttlj
  dec_a
  cmp #$0A
  bcc s2ok
  lda #$09
s2ok:
  sta_l ${ADVMAG:06X}
  lda #$00
  sta_l ${ADVSIGN:06X}
  bra setshow
settle1:
  lda_l ${CNT2:06X}
  cmp #$02
  bcc advttlj
  dec_a
  cmp #$0A
  bcc s1ok
  lda #$09
s1ok:
  sta_l ${ADVMAG:06X}
  lda #$01
  sta_l ${ADVSIGN:06X}
setshow:
  lda #$5A
  sta_l ${ADVTTL:06X}
  lda #$01
  sta_l ${ADVDIRTY:06X}
  lda #$00
  sta_l ${EXCH:06X}
advttl:
  lda_l ${ADVTTL:06X}
  beq tmw
  dec_a
  sta_l ${ADVTTL:06X}
  bne tmw
  lda #$01
  sta_l ${ADVDIRTY:06X}
tmw:
  lda_l ${UIVIS:06X}
  bne tmwant1
  lda_l ${SET_SHOW:06X}
  beq tmwant0
  lda_l ${WIPED:06X}
  beq tmwant0
tmwant1:
  lda #$01
  sta_l ${TMWANT:06X}
  bra tmwd
tmwant0:
  lda #$00
  sta_l ${TMWANT:06X}
tmwd:
"""


def _input_stub(stage):
    body = _gate()
    if stage != "pipe":
        body += _edges() + _chord() + _menu_fsm() + _reset() + _dummy() + _effects()
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
{body}exit:
  plb
  rep #$30
  ply
  plx
  pla
  plp
"""


# ================= UPL2 stub =================

def _paint_row_block(i, idx, tag):
    """Emit: set VRAM addr + write the row's 22 words (cursor branch + value switch)."""
    name, setaddr, vals = MENU[i]
    out = f"""
  rep #$20
  lda #${row_addr(i):04X}
  sta $2116
"""
    if i == 0:  # title: TRAINING centered at offset 7
        w = [BLANK] * 7 + _words("TRAINING", 8, idx) + [BLANK] * 7
        for word in w:
            out += f"  lda #${word:04X}\n  sta $2118\n"
        out += f"  sep #$20\n  jmp {tag}done\n"
        return out
    # offset 0: blank
    out += f"  lda #${BLANK:04X}\n  sta $2118\n"
    # offset 1: cursor
    out += f"""
  sep #$20
  lda_l ${CURSOR:06X}
  cmp #${i:02X}
  rep #$20
  beq {tag}cur{i}
  lda #${BLANK:04X}
  bra {tag}cw{i}
{tag}cur{i}:
  lda #${0x2C00 | (GLYPH_TILE0 + idx['>']):04X}
{tag}cw{i}:
  sta $2118
"""
    # offset 2: blank; 3-8: name
    out += f"  lda #${BLANK:04X}\n  sta $2118\n"
    for word in _words(name, 6, idx):
        out += f"  lda #${word:04X}\n  sta $2118\n"
    # offset 9: blank
    out += f"  lda #${BLANK:04X}\n  sta $2118\n"
    # offsets 10-17: value switch
    if setaddr is None:  # RESET row: static value
        for word in _words(vals[0], 8, idx):
            out += f"  lda #${word:04X}\n  sta $2118\n"
    else:
        # dispatch in 8-bit with rep-before-branch (rep preserves Z), cases run in 16-bit
        out += f"  sep #$20\n  lda_l ${setaddr:06X}\n"
        for vi in range(len(vals)):
            out += f"""  cmp #${vi:02X}
  rep #$20
  bne {tag}n{i}_{vi}
  jmp {tag}c{i}_{vi}
{tag}n{i}_{vi}:
  sep #$20
"""
        out += f"  rep #$20\n  jmp {tag}c{i}_0\n"   # corrupt value -> render as value 0
        for vi, v in enumerate(vals):
            out += f"{tag}c{i}_{vi}:\n"
            for word in _words(v, 8, idx):
                out += f"  lda #${word:04X}\n  sta $2118\n"
            out += f"  jmp {tag}vdn{i}\n"
        out += f"{tag}vdn{i}:\n"
    # offsets 18-21: pad blanks
    for _ in range(4):
        out += f"  lda #${BLANK:04X}\n  sta $2118\n"
    out += f"  sep #$20\n  jmp {tag}done\n"
    return out


def _upl2_stub(stage, font_addr, font_bank, font_size, idx):
    dst = BG3_CHR + GLYPH_TILE0 * 8
    if stage == "pipe":
        # (pipe retains the phase-2 smoke behavior: title row while gated)
        body = f"""
  lda_l ${VISIBLE:06X}
  beq pnotvis
  lda_l ${FONTUP:06X}
  bne pfontok
  jmp dofont
pfontok:
pnotvis:
  jmp tmmgmt
dofont:
{_font_dma(font_addr, font_bank, font_size, dst)}
{_paint_row_block(0, idx, "pp")}
ppdone:
  lda #$01
  sta_l ${UIVIS:06X}
  jmp tmmgmt
"""
        return _upl2_wrap(body)

    # full painter: priority clear > paint > cursorpass > redraw
    clear_rows = ""
    for i in range(NROWS):
        # NB: keep tracker/runtime widths in sync at each label (sep after every block)
        clear_rows += f"""
  cmp #${i:02X}
  bne clr{i}
  rep #$20
  lda #${row_addr(i):04X}
  sta $2116
  jmp clrw
clr{i}:
  sep #$20
"""
    paint_chain = ""
    for i in range(NROWS):
        paint_chain += f"""
  cmp #${i:02X}
  bne pnt{i}
  jmp pntb{i}
pnt{i}:
"""
    redraw_chain = ""
    for i in range(NROWS):
        redraw_chain += f"""
  cmp #${i:02X}
  bne rd{i}
  jmp pntb{i}
rd{i}:
"""
    wipe_chain = ""
    for i in range(WIPEROWS):
        wipe_chain += f"""
  cmp #${i:02X}
  bne wp{i}
  rep #$20
  lda #${0x1000 + i * 32:04X}
  sta $2116
  jmp wipew
wp{i}:
  sep #$20
"""
    paint_blocks = ""
    for i in range(NROWS):
        paint_blocks += f"pntb{i}:\n" + _paint_row_block(i, idx, f"p{i}_") + f"p{i}_done:\n  jmp painted\n"
    cursor_cells = ""
    for i in range(1, NROWS):
        cursor_cells += f"""
  rep #$20
  lda #${row_addr(i) + CUR_OFF:04X}
  sta $2116
  sep #$20
  lda_l ${CURSOR:06X}
  cmp #${i:02X}
  rep #$20
  beq cc{i}
  lda #${BLANK:04X}
  bra ccw{i}
cc{i}:
  lda #${0x2C00 | (GLYPH_TILE0 + idx['>']):04X}
ccw{i}:
  sta $2118
  sep #$20
"""
    body = f"""
  lda_l ${CLEARROW:06X}
  cmp #$FF
  bne doclear
  jmp clrskip
doclear:
{clear_rows}  jmp tmmgmt
clrw:
  rep #$20
  lda #${BLANK:04X}
{"".join("  sta $2118" + chr(10) for _ in range(PANEL_W))}  sep #$20
  lda_l ${CLEARROW:06X}
  inc_a
  cmp #${NROWS:02X}
  bne clrnx
  lda #$FF
clrnx:
  sta_l ${CLEARROW:06X}
  jmp tmmgmt
clrskip:
  lda_l ${VISIBLE:06X}
  bne vis1
  jmp tmmgmt
vis1:
  lda_l ${PAINTROW:06X}
  cmp #$FF
  bne dopaint
  jmp nopaint
dopaint:
  cmp #$00
  bne pwipe
  lda_l ${FONTUP:06X}
  bne pfok
  jmp dofont
pfok:
  lda #$01
  sta_l ${PAINTROW:06X}
  jmp tmmgmt
pwipe:
  cmp #${WIPEROWS + 1:02X}
  bcc dowipe
  jmp prow
dowipe:
  dec_a
{wipe_chain}  jmp tmmgmt
wipew:
  rep #$20
  lda #${BLANK:04X}
{"".join("  sta $2118" + chr(10) for _ in range(32))}  sep #$20
  lda_l ${PAINTROW:06X}
  inc_a
  sta_l ${PAINTROW:06X}
  cmp #${WIPEROWS + 1:02X}
  bne wdone
  lda_l ${PMODE:06X}
  beq wdone
  lda #$FF
  sta_l ${PAINTROW:06X}
  lda #$01
  sta_l ${WIPED:06X}
  sta_l ${INPDIRTY:06X}
  sta_l ${ADVDIRTY:06X}
  sta_l ${HPDIRTY:06X}
wdone:
  jmp tmmgmt
prow:
  sec
  sbc #${WIPEROWS + 1:02X}
{paint_chain}  jmp tmmgmt
painted:
  sep #$20
  lda_l ${PAINTROW:06X}
  cmp #$FF
  beq pfromrd
  inc_a
  cmp #${WIPEROWS + NROWS + 1:02X}
  bne pnx
  lda #$FF
  sta_l ${PAINTROW:06X}
  lda #$01
  sta_l ${UIVIS:06X}
  sta_l ${WIPED:06X}
  sta_l ${INPDIRTY:06X}
  sta_l ${ADVDIRTY:06X}
  sta_l ${HPDIRTY:06X}
pfromrd:
  jmp tmmgmt
pnx:
  sta_l ${PAINTROW:06X}
  jmp tmmgmt
nopaint:
  lda_l ${CURSDIRT:06X}
  bne docurs
  jmp nocurs
docurs:
  lda #$00
  sta_l ${CURSDIRT:06X}
{cursor_cells}  jmp tmmgmt
nocurs:
  lda_l ${REDRAW_A:06X}
  cmp #$FF
  beq nordrw
  pha
  lda #$FF
  sta_l ${REDRAW_A:06X}
  pla
{redraw_chain}  jmp tmmgmt
nordrw:
  jmp disp
dofont:
{_font_dma(font_addr, font_bank, font_size, dst)}
  jmp tmmgmt

disp:
  lda_l ${SET_SHOW:06X}
  bne d1
  jmp tmmgmt
d1:
  lda_l ${WIPED:06X}
  bne d2
  jmp tmmgmt
d2:
  lda_l ${INPDIRTY:06X}
  bne dinp
  lda $005C
  cmp_l ${SHOWPREV_L:06X}
  bne dinp
  lda $005D
  cmp_l ${SHOWPREV_H:06X}
  bne dinp
  jmp dadv
dinp:
  lda #$00
  sta_l ${INPDIRTY:06X}
  lda $005C
  sta_l ${SHOWPREV_L:06X}
  lda $005D
  sta_l ${SHOWPREV_H:06X}
  rep #$20
  lda #$1264
  sta $2116
  sep #$20
  lda $005D
  and #$08
  rep #$20
  bne lit0
  lda #$2000
  bra wr0
lit0:
  lda #$WORD_U
wr0:
  sta $2118
  sep #$20
  lda $005D
  and #$04
  rep #$20
  bne lit1
  lda #$2000
  bra wr1
lit1:
  lda #$WORD_D
wr1:
  sta $2118
  sep #$20
  lda $005D
  and #$02
  rep #$20
  bne lit2
  lda #$2000
  bra wr2
lit2:
  lda #$WORD_L
wr2:
  sta $2118
  sep #$20
  lda $005D
  and #$01
  rep #$20
  bne lit3
  lda #$2000
  bra wr3
lit3:
  lda #$WORD_R
wr3:
  sta $2118
  lda #$2000
  sta $2118
  sep #$20
  lda $005D
  and #$40
  rep #$20
  bne lit5
  lda #$2000
  bra wr5
lit5:
  lda #$WORD_L
wr5:
  sta $2118
  sep #$20
  lda $005D
  and #$40
  rep #$20
  bne lit6
  lda #$2000
  bra wr6
lit6:
  lda #$WORD_P
wr6:
  sta $2118
  lda #$2000
  sta $2118
  sep #$20
  lda $005D
  and #$80
  rep #$20
  bne lit8
  lda #$2000
  bra wr8
lit8:
  lda #$WORD_L
wr8:
  sta $2118
  sep #$20
  lda $005D
  and #$80
  rep #$20
  bne lit9
  lda #$2000
  bra wr9
lit9:
  lda #$WORD_K
wr9:
  sta $2118
  lda #$2000
  sta $2118
  sep #$20
  lda $005C
  and #$40
  rep #$20
  bne lit11
  lda #$2000
  bra wr11
lit11:
  lda #$WORD_H
wr11:
  sta $2118
  sep #$20
  lda $005C
  and #$40
  rep #$20
  bne lit12
  lda #$2000
  bra wr12
lit12:
  lda #$WORD_P
wr12:
  sta $2118
  lda #$2000
  sta $2118
  sep #$20
  lda $005C
  and #$80
  rep #$20
  bne lit14
  lda #$2000
  bra wr14
lit14:
  lda #$WORD_H
wr14:
  sta $2118
  sep #$20
  lda $005C
  and #$80
  rep #$20
  bne lit15
  lda #$2000
  bra wr15
lit15:
  lda #$WORD_K
wr15:
  sta $2118
  sep #$20
dadv:
  lda_l ${ADVDIRTY:06X}
  bne dadv1
  jmp dhp
dadv1:
  lda #$00
  sta_l ${ADVDIRTY:06X}
  lda_l ${ADVTTL:06X}
  bne advdraw
  rep #$20
  lda #$1276
  sta $2116
  lda #$2000
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  lda #$129B
  sta $2116
  lda #$2000
  sta $2118
  sep #$20
  jmp dhp
advdraw:
  rep #$20
  lda #$1276
  sta $2116
  lda #$WORD_A
  sta $2118
  lda #$WORD_D
  sta $2118
  lda #$WORD_V
  sta $2118
  lda #$2000
  sta $2118
  sep #$20
  lda_l ${ADVSIGN:06X}
  rep #$20
  bne sgm
  lda #$2000
  bra sgw
sgm:
  lda #$WORD_MINUS
sgw:
  sta $2118
  sep #$20
  lda_l ${ADVMAG:06X}
  rep #$20
  and #$00FF
  clc
  adc #$2C50
  sta $2118
  lda #$129B
  sta $2116
  sep #$20
  lda_l ${ADVMAG:06X}
  rep #$20
  and #$00FF
  clc
  adc #$2C60
  sta $2118
  sep #$20
  jmp dhp
dhp:
  lda_l ${HPDIRTY:06X}
  bne dohp
  lda $1049
  cmp_l ${HPSH1:06X}
  bne dohp
  lda $10C9
  cmp_l ${HPSH2:06X}
  bne dohp
  jmp tmmgmt
dohp:
  lda #$00
  sta_l ${HPDIRTY:06X}
  lda $1049
  sta_l ${HPSH1:06X}
  lda $10C9
  sta_l ${HPSH2:06X}
  lda #$80
  sta $2115
{_hp_render(0)}{_hp_render(1)}  jmp tmmgmt
{paint_blocks}"""
    body = (body
            .replace("$WORD_A", f"${0x2C00 | (GLYPH_TILE0 + idx['A']):04X}")
            .replace("$WORD_D", f"${0x2C00 | (GLYPH_TILE0 + idx['D']):04X}")
            .replace("$WORD_V", f"${0x2C00 | (GLYPH_TILE0 + idx['V']):04X}")
            .replace("$WORD_L", f"${0x2C00 | (GLYPH_TILE0 + idx['L']):04X}")
            .replace("$WORD_P", f"${0x2C00 | (GLYPH_TILE0 + idx['P']):04X}")
            .replace("$WORD_K", f"${0x2C00 | (GLYPH_TILE0 + idx['K']):04X}")
            .replace("$WORD_H", f"${0x2C00 | (GLYPH_TILE0 + idx['H']):04X}")
            .replace("$WORD_U", f"${0x2C00 | (GLYPH_TILE0 + idx['U']):04X}")
            .replace("$WORD_R", f"${0x2C00 | (GLYPH_TILE0 + idx['R']):04X}")
            .replace("$WORD_MINUS", f"${0x2C00 | (GLYPH_TILE0 + idx['-']):04X}"))
    return _upl2_wrap(body)



def _hp_render(p):
    hp = 0x1049 if p == 0 else 0x10C9
    top = 0x1284 if p == 0 else 0x1296
    bot = 0x12A4 if p == 0 else 0x12B6
    s = f"h{p}"
    return f"""
  rep #$10
  ldx #$0000
  sep #$20
  lda ${hp:04X}
hpt{s}:
  cmp #$0A
  bcc hpd{s}
  sec
  sbc #$0A
  inx
  bra hpt{s}
hpd{s}:
  sta_l ${SCRONES:06X}
  rep #$20
  lda #${top:04X}
  sta $2116
  txa
  clc
  adc #$2C50
  sta $2118
  lda_l ${SCRONES:06X}
  and #$00FF
  clc
  adc #$2C50
  sta $2118
  lda #${bot:04X}
  sta $2116
  txa
  clc
  adc #$2C60
  sta $2118
  lda_l ${SCRONES:06X}
  and #$00FF
  clc
  adc #$2C60
  sta $2118
  sep #$20
"""


def _font_dma(font_addr, font_bank, font_size, dst):
    return f"""
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
"""


def _upl2_wrap(body):
    return f"""
  php
  pha
  phx
  phy
  sep #$20
{body}tmmgmt:
  sep #$20
  lda_l ${TMWANT:06X}
  cmp_l ${PREVUI:06X}
  bne tmchg
  jmp tmsteady
tmchg:
  lda_l ${TMWANT:06X}
  sta_l ${PREVUI:06X}
  beq tmoff
  jmp tmsteady
tmoff:
  lda #${TM_OFF:02X}
  sta $212C
  rep #$20
  lda #$1264
  sta $2116
  lda #${BLANK:04X}
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  lda #$1284
  sta $2116
  lda #${BLANK:04X}
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  lda #$12A4
  sta $2116
  lda #${BLANK:04X}
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sta $2118
  sep #$20
tmsteady:
  lda_l ${TMWANT:06X}
  beq tmdone
  lda #${TM_ON:02X}
  sta $212C
tmdone:
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


def build(src, out, stage="tier1"):
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

    font_blob, idx = hudfont.build_font(FONT_LETTERS, color=1)   # white (visible everywhere)
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

    data += b"\x00" * ((len(data) + 0x7FFFF) // 0x80000 * 0x80000 - len(data))
    _fix_checksum(data)
    open(out, "wb").write(data)
    print(f"wrote {out} from {src}: stage={stage} bank={bank:#04x} "
          f"font={len(font_blob)}B input={len(inp_body)}B upl2={len(upl_body)}B, "
          f"{len(data):#x} bytes, sha1={sha1(bytes(data)).hexdigest()}")
    print(f"  stubs: INPUT={bank:02X}{inp_off:04X} UPL2={bank:02X}{upl_off:04X}")


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
    ap.add_argument("out", nargs="?", default=str(REPO / "build/sms_trainingplus.sfc"))
    ap.add_argument("--stage", choices=["pipe", "tier1"], default="tier1")
    a = ap.parse_args()
    if a.src == CLEAN:
        assert sha1(open(a.src, "rb").read()).hexdigest() == CLEAN_SHA1, "clean hash mismatch"
    build(a.src, a.out, a.stage)
