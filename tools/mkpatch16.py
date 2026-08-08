#!/usr/bin/env python3
"""mkpatch16.py — menu translation: install a half-width Latin alphabet.

STATUS: STEP 1 WORKS (glyphs in VRAM $5C0-$5FF on the button-config screen,
read back out of VRAM) and the step-2 blocker is SOLVED: the Options screen
wipes all of VRAM on entry and its loader never re-uploads the font, so the
builder now hooks that loader (see the OPT_HOOK block) to run the font record
first. Tilemap label translation is gated on SMS_P16_OPTIONS=1.

Two things had to be true at once, which is why this took several attempts:

1. THE ASSET RECORD LAYOUT IN THE OLD NOTES WAS WRONG. A record is not
   [src24][dest24][u16][u16]; it is

       [vram16][len16][src24][dest24]      10 bytes, table at $C3:BE08

   so a block's upload LENGTH sits 2 bytes BEFORE its src pointer, not 8 after.
   Every earlier attempt bumped the wrong field — which is why it "changed
   nothing" for the font while quietly lengthening an unrelated transfer.
   Parsed correctly, 27 of the 58 records match a transfer observed on the
   config screen exactly (vram, len, dest); parsed the old way, none do.
   The field is a BYTE count, not words.

2. THE KANJI BLOCK IS NOT LOADED ON THE SCREEN BEING TRANSLATED. Earlier
   versions of this builder extended the kanji block ($C7:07F0, VRAM $500) and
   tested on the config screen, where its record never runs at all — no transfer
   to VRAM $5000 occurs there, so those glyphs could never have appeared no
   matter how the length was set. The sheet that screen actually loads is
   $C4:2590 -> $7E:C000 -> VRAM $400 (418 tiles), and that is what this patch
   extends.

So: the sheet grows 418 -> 512 tiles, the glyphs land at VRAM $5C0-$5FF (proven
free across the menu screens), and the record's length grows $3480 -> $4000
bytes. $4000 is also the ceiling: the source buffer starts at $7E:C000, so a
longer transfer would run off the end of bank $7E and wrap.

Verification that matters (tools/probe_menu_vram.lua):
  * POKE=1 stamps a pattern into the source past the vanilla transfer's end:
    0/256 bytes arrive on clean, 256/256 with the length raised.
  * on the built ROM, VRAM $5C0-$5FF holds 52 of 64 non-blank tiles — exactly
    26 letters x 2 tiles — against 0 on clean.

    tools/mkpatch16.py <out.sfc>            # from the clean ROM
    tools/mkpatch16.py --stacked <in> <out>
"""
import argparse
import hashlib
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "tools"))
sys.path.insert(0, os.path.join(REPO, "tools", "saturn"))

from smspaths import clean_rom, fix_checksum, next_bank, write_bank, require_source   # noqa: E402
import asm65816                                                        # noqa: E402
import sms_lz                                                          # noqa: E402
import mkhalfwidth                                                     # noqa: E402

# The font sheet the menu screens load at VRAM $400 — NOT the kanji block; see
# the module docstring for why that distinction cost several attempts.
FONT_SRC = 0xC42590               # compressed sheet, 418 tiles
FONT_VRAM = 0x4000                # its VRAM word address
FONT_LEN = 0x3480                 # its vanilla upload length, in BYTES
FONT_DEST = 0x7EC000              # WRAM staging buffer it decompresses into
TILE_BASE = 0x400                 # sheet tile 0 lands at VRAM tile $400
SHEET_W = 16
NEW_TILES = 0x200                 # extend to 512 tiles -> VRAM $400-$5FF
NEW_LEN = NEW_TILES * 32          # = $4000 BYTES; also the ceiling, since
                                  # $7E:C000 + $4000 is exactly the end of bank $7E
GLYPH_ROWS = (0x5C0, 0x5E0)       # two rows of 16, in VRAM tile numbers
INK = 7                           # flat ink colour; the kana use 1-8

# Half-width punctuation, authored here (mkhalfwidth covers A-Z only). Same
# 8x16 '#'-art format; slots take the free tops after Z ($5EA+, bottoms +$10).
PUNCT = {
    ",": ["........"] * 10 + ["..##....", "..##....", "...#....", "..#....."]
         + ["........"] * 2,
    "-": ["........"] * 7 + [".#####..", ".#####.."] + ["........"] * 7,
    "'": ["...##...", "...##...", "....#...", "...#...."] + ["........"] * 12,
}
PUNCT_SLOTS = {",": 0x5EA, "-": 0x5EB, "'": 0x5EC}

# ---- the OPTIONS screen (the first translated screen) ---------------------
# Its tilemap is asset record 19: src $C3:69F0 -> $7E:2000 -> VRAM $0000, a
# 0x800-byte 32x32 map. Located by searching every asset block for the exact map
# words of the COMレベル row, so it is identified by content rather than guessed.
#
# Addressing, all measured off the live screen:
#   entry  = attr | tile, tile is 10 bits
#   BG1 CHR base is word $2000 = tile $200, so MAP tile = VRAM tile - $200
#   a glyph is 2 map rows: bottom entry = top entry + $10
#   a HALF-WIDTH glyph is ONE map column (a full-width one is two)
#   labels start at column 4 with attr $0C00; values occupy columns 22-27
#     right-aligned with attr $1000
# Budgets that follow: 18 columns for a label, 6 for a value.
# Set SMS_P16_OPTIONS=1 to translate the labels (values are runtime-drawn, see
# the NOTE below). The delivery problem that used to gate this is SOLVED — see
# the Options-loader hook.
OPT_TRANSLATE = os.environ.get("SMS_P16_OPTIONS") == "1"

# ---- the Options-loader hook (2026-08-06 finding; the step-2 unblocking) ----
# WHY THE GLYPHS "DID NOT REACH VRAM" ON THE OPTIONS SCREEN: the transition into
# Options CLEARS ALL OF VRAM (fixed-source DMA, len $10000, kicked at $80:8191)
# and then runs the screen's own loader — straight-line code at $C3:A4DD..A50F
# ("lda #idx*2 / sta $1C18 / jsr $824E|$825B" per record) whose six records do
# NOT include the font record. The glyphs seen missing there had been uploaded
# at MAIN-MENU entry and wiped on the way in. The old notes' "Options runs the
# extended transfer" was that menu-entry transfer, misattributed; the
# stale-buffer/ordering theory is DEAD — the designated dump showed $7E:C000
# holds the glyph block both at the transfer instant and after Options settles
# (probe_p16_options_buf.lua).
#
# Asset-record plumbing this hook rides on (all clean-ROM, bank $C3):
#   * pointer tables at $C3:BCCD ("A", 25 entries) and $C3:BCFF ("B", 49
#     entries) map a record INDEX -> 10-byte record; WRAM $1C18 = index*2.
#     The font record $C3:BF16 (this builder's #27 by flat scan) is B index 15.
#   * $C3:82CA = decompress record (JSL $80:927D, DP $00-$05 = src24/dest24)
#     then DMA it (JSL $80:92AD, DP $00-$06 = vram/len/src24). Both primitives
#     are JSL-able, so the stub replays them with build-time constants instead
#     of re-entering bank-$C3 code (which executes from the $03 mirror so that
#     $1C18 hits WRAM — a stub in the appended bank cannot jsr into it).
# The hook replaces the cluster's first "lda #$003E / sta $1C18" (6 bytes) with
# JSL stub + 2 nop; the stub uploads the font FIRST, then re-arms idx 31. Order
# matters: the cluster's big text-sheet record (vram $2C00 len $4D40 = tiles
# $2C0-$529) must keep winning its overlap with the font sheet at tiles
# $400-$529; the glyphs at $5C0-$5FF overlap nothing on this screen.
OPT_HOOK_FILE = 0x03A4DD
OPT_HOOK_OLD = bytes.fromhex("a93e008d181c")
STUB_AT = 0x7F00                  # stub offset inside the appended bank
OPT_SRC = 0xC369F0
OPT_MAP_W = 32
OPT_LABEL_COL = 4
OPT_LABEL_COLS = 18
CHR_BASE_TILE = 0x200
# Row = the TOP half of the glyph pair. The maintainer's strings, 2026-08-05.
OPT_LABELS = ((5, "COM LEVEL"), (8, "TIMER"), (11, "BGM"),
              (14, "SFX"), (17, "VOICES"), (20, "EXIT"))
# ---- the option VALUES (runtime-drawn; writer found 2026-08-06) -----------
# The values could never be tilemap edits: they are redrawn by $80:8C43, which
# DMAs a self-describing record [vmadd16][len16][rows16][cells...] from bank
# $C4 straight to the BG1 map (2 rows x 10 cells at cols 20-29). One record
# per value PER HIGHLIGHT STATE, selected via four pointer tables at
# $C3:A44F/$A457/$A45B/$A463 (WRAM $1B14/$1B16 = value*2; attr $1000 =
# highlighted, $0C00 = not). The records are UNCOMPRESSED and are the single
# source for the initial draw and every redraw, so translating a value is an
# in-place cell edit — no relocation, no hook. Identified by rendering the
# cells from the screen's own text sheet ($C3:48D0): COM order is
# なかよし/やさしい/ふつう/むずかしい, TIMER あり/なし; BGM/SFX/VOICES are
# numeric. English is centred in the 10-cell field; each record keeps its own
# attr so both highlight palettes survive.
OPT_VALUES = (
    (0x6590, "FRIEND"), (0x65BE, "EASY"), (0x65EC, "NORMAL"), (0x661A, "HARD"),
    (0x64D8, "FRIEND"), (0x6506, "EASY"), (0x6534, "NORMAL"), (0x6562, "HARD"),
    (0x6648, "YES"), (0x6676, "NO"),
    (0x66A4, "YES"), (0x66D2, "NO"),
)

# Asset job table: 10-byte records of [vram16][len16][src24][dest24].
# NOTE (2026-08-08): this is a flat SCAN WINDOW, not the table's real extent. The
# record pool is $C3:BD61-$C3:C04B (74 records), reached through two pointer
# tables — $C3:BCCD (25) and $C3:BCFF (49). Scanning at a 10-byte stride from
# $BE08 finds the last stretch and misses the 16 records before it. Everything
# this builder needs lives inside the window, so the window stays; widen it to
# the pointer tables if a record before $BE08 ever has to be touched.
REC0 = 0x00BE08                   # in bank $C3 — the first record's vram field
RECSZ = 10
NRECS = 58

# ---- the bank-$DF screens (Win/REPORT CARD, Tournament) — 2026-08-06 -------
# Nine screens driven by scripts at $DF ('lda #script / jsr $DF:83E1'); their
# glyphs come from the big text sheet $C3:48D0 (sms_lz), uploaded whole from
# $7F:0000. The sheet has a full-width Latin alphabet missing Q/S/Z and no
# half-width, so this builder (SMS_P16_DF=1 while in bring-up):
#   1. extends the sheet 608 -> 660 tiles with the half-width A-Z (26 tops at
#      sheet tile $260, 26 bottoms at $27A), relocates the packed copy to the
#      patch bank, and repoints the THREE verified $DF script entries
#      (tournament select $DF:8D24, bracket $DF:941B, report $DF:96CC),
#      raising their upload length $5000 -> $5280. The fourth $DF reference
#      ($DF:9B37, an unidentified screen) and the two $C3 records
#      ($C3:BEC0/$BEE8 — char select/config, where the kanji block overwrites
#      the extension's VRAM anyway) keep the ORIGINAL blob, which stays in
#      place untouched.
#   2. rewrites the tournament-select name blocks — uncompressed
#      [vmadd][len][rows][cells...] arrays in bank $DF via the pointer table
#      $DF:8EAC — with the maintainer's names. Cell id on that screen =
#      sheet tile + $A0 (sheet at vmadd $2A00, CHR base $200).
DF_TRANSLATE = os.environ.get("SMS_P16_DF") == "1"
DF_SHEET_SRC = 0xC348D0
DF_SHEET_RAW = 0x4C00             # 608 tiles decompressed
# ⚠ the glyphs cannot sit right after the sheet: on tournament select, script
# entry[4] ($CA6A10 -> VRAM $5000) decompresses OVER tiles $500+ after the
# sheet upload (measured — the first attempt's letters were stomped). So the
# sheet is padded to tile $320 and the glyphs laid out exactly like the menu
# font's $5C0-window (tops at +0, bottoms at +$10, second row at +$20): on the
# vmadd-$2A00 screens (select, report) they land at VRAM $5C0-$5FF — the
# window measured blank there — and cell ids equal the menu convention
# (placed[ch] - $200).
DF_GLYPH_TILE = 0x320             # sheet tile of the first glyph row
DF_SHEET_TILES = 0x360            # padded total
# ⚠ Only the TWO screens that need glyphs are repointed. The third $C348D0
# script entry ($DF:941B, script $9405) was bumped speculatively in the first
# build ("the bracket" — wrong: the bracket is script $A43E) and turned out to
# be the STORY PRE-FIGHT PORTRAIT screen, whose background plane REFERENCES
# the tiles the extension lands on — the maintainer field-reported stray
# letters there (2026-08-06). Blank-but-referenced again; it stays vanilla.
DF_SCRIPT_REFS = (0x1F8D24, 0x1F96CC)             # file offsets of src24 fields
DF_SHEET_AT = 0xA000              # packed extended sheet's offset in the blob
# name blocks: (file offset of block, text) — 12 cells x 2 rows each,
# left-aligned like the Japanese; identified by rendering (docs/menu_text.md).
# ⚠ pointer-table entry 0 ($DF:9211) is the BLANK block (all-zero cells, the
# "no entry" row) — the names start at entry 1.
DF_NAMES = (
    (0x1F902B, "MOON"),    (0x1F9061, "MERCURY"), (0x1F9097, "MARS"),
    (0x1F90CD, "JUPITER"), (0x1F9103, "VENUS"),   (0x1F9139, "CHIBI"),
    (0x1F916F, "PLUTO"),   (0x1F91A5, "NEPTUNE"), (0x1F91DB, "URANUS"),
)

# ---- プレイヤーセレクト -> PLAYER SELECT (tournament select header) --------
# The header is plain cells (rows 5-6, cols 7-24, attr $1000) in the codec-2
# base map — but the screen REDRAWS its queued records every frame, so no
# codec work is needed: a 19th record is queued that overdraws the header.
# Hook: the select screen's own block-copy setup at $DF:8ED3
# ('ldx #$9247 / ldy #$8800', 6 bytes) becomes JSL + 2 nop; the stub copies a
# prepared [vmadd $70A7][len $24][rows 2][cells] record from the patch bank to
# $7F:8900, queues it the way $DF:8126 does (first zero slot in $1CD0, addr +
# bank $7F), restores X/Y and returns — the displaced mvn then runs unchanged.
PS_HOOK_FILE = 0x1F8ED3
PS_HOOK_OLD = bytes.fromhex("a24792a00088")
PS_REC_AT = 0x8700                # the record's offset in the blob
PS_STUB_AT = 0x7FA0
PS_TEXT = "PLAYER SELECT"

# ---- the REPORT CARD (Win screen) labels -----------------------------------
# The screen's text is a tilemap blob ($C8:703C, the second, unreversed codec)
# decompressed to $7F:0000; the match numbers are inserted by $DF:9732 and the
# map is uploaded ONCE by 'sep #$10 / ldy #$00 / jsr $84F9' at $DF:9679. The
# labels are translated by hooking those 7 bytes with a JSL to a generated
# straight-line stub that rewrites the label cells in $7F:0000 AFTER the
# numbers went in, then replays $84F9's Y=0 upload (src $7F:0000, vmadd
# $7000, len $0800) inline — codec 2 never needs decoding. Spans/attrs read
# off the live map dump (docs/menu_text.md § screen census).
# (top_map_row, start_col, old_span_last_col, attr, text)
DF_REPORT_HOOK = 0x1F9679
DF_REPORT_OLD = bytes.fromhex("e210a00020f984")
REPORT_AT = 0x9000                # stub offset in the blob
DF_REPORT_LABELS = (
    (9,  12, 21, 0x0C00, "KO TIME"),
    (11, 12, 21, 0x0C00, "HIT COUNT"),
    (13, 13, 20, 0x0C00, "DAMAGE"),
    (16, 13, 18, 0x0C00, "BEST"),
    (18, 12, 19, 0x0C00, "WIN COUNT"),
    (20, 11, 20, 0x1000, "KO TIME"),
    (22, 11, 20, 0x1000, "HIT COUNT"),
    (24, 12, 19, 0x1000, "DAMAGE"),
)

# ---- stage names (SMS_P16_STAGES=1) ----------------------------------------
# Drawn on the VS config screen's stage row by the $80:8C43 record renderer:
# 20 records in bank $C4 (10 stages x normal/highlight, $66 apart, stride
# $CC), each [vmadd $02E4][len $30][rows 2][24x2 cells], name centred.
# Attrs $0C00 normal / $1000 highlighted, kept per record. The config screen
# inherits CHAR SELECT's VRAM (no loader of its own), so the half-width block
# is delivered by hooking the char-select cluster's first load ($C3:AF8A) to
# DMA an uncompressed 64-tile copy from the patch bank to VRAM $5C0 — the
# same window every other screen uses, so cell ids stay placed[ch] - $200.
# Strings: the maintainer's 2026-08-06 long forms, CAPS (his ruling), with
# the two over-24 names trimmed to exact fits.
STAGES_TRANSLATE = os.environ.get("SMS_P16_STAGES") == "1"
# SMS_P16_SATURN=1: stage 2's name becomes the Saturn build's SILENT THRONE OF
# MESSIAH instead of SPACE-TIME DOOR. Default OFF (maintainer, 2026-08-06):
# the default Saturn build does not carry patch 16, so the flag is only for a
# future Saturn chain that stacks this patch — never set it elsewhere.
SATURN_STAGE = os.environ.get("SMS_P16_SATURN") == "1"
STAGE_REC0 = 0x045A98             # stage 0, normal; +$66 highlight; +$CC next
STAGE_NAMES = (
    "CRYSTAL TOKYO, EVENING",
    "SILVER MILLENIUM",
    "SPACE-TIME DOOR",
    "KAIOUSHUU PARK",
    "FOUNTAIN PARK, DAY",
    "JUUBAN SHOPPING STREET",
    "HIKAWA SHRINE",
    "CRYSTAL TOKYO, NIGHT",
    "FOUNTAIN PARK, NIGHT",
    "NAKAYOSHI EDITORIAL DEPT",
)
CS_HOOK_FILE = 0x03AF8A           # char-select cluster: lda #$001A / sta $1C18
CS_HOOK_OLD = bytes.fromhex("a91a008d181c")
CS_BLOCK_AT = 0x8800              # uncompressed 64-tile glyph block in the blob
CS_STUB_AT = 0x7F60

# The config screen's ROW LABELS live in the $C3:7C00 tilemap (record A idx
# 12, rec $C3:BEF8, loaded by the char-select cluster to VRAM $0000). One
# relocated tilemap edit covers everything: both マニュアル columns, the row
# labels, and ステージ. The baked stage NAME at rows 23-24 is left alone —
# the stage records overdraw it. (top_row, start_col, last_col, text); attr
# read from the map.
CFG_MAP_SRC = 0xC37C00
CFG_MAP_REF = 0x03BEFC            # the record's src24 field
CFG_MAP_AT = 0x4000               # relocated packed map's offset in the blob
# ---- the A.C.S. screen (SMS_P16_ACS=1) -------------------------------------
# The stat wheel's labels (必殺技/攻撃/?/体力/防御/おちゃめ) are RASTER text
# inside the screen's art sheet $C23400 (VRAM $300-$3FF via map $C23EB0) —
# not tile-aligned, so the edit is erase+stamp on pixels: each label's box is
# cleared to colour 0 and the English stamped in the kana's fill colour, then
# the sheet is re-encoded, relocated, and record idx3B's src repointed. The
# boxes were measured off a coordinates-annotated pixel dump; all sit OUTSIDE
# the wheel circle. DESP replaces the "?" and is wider than it — the extra
# columns land on blank art cells that exist in the map.
# ⚠ NO glyph-block hook on this screen: raster labels need no font tiles, and
# a first attempt that uploaded the block to VRAM $5C0 drew GARBAGE along the
# bottom bar — the runtime-written prompt area references those tiles through
# another BG's CHR base (blank-but-referenced; trap 2's VRAM cousin). The name
# card and the prompt line are runtime-drawn (deferred — docs/menu_text.md);
# when they're done, their glyph window needs a real census first.
ACS_TRANSLATE = os.environ.get("SMS_P16_ACS") == "1"
ACS_SHEET_SRC = 0xC23400
ACS_SHEET_REF = 0x03BDA8          # record idx3B's src24 field
ACS_MAP_SRC = 0xC23EB0
ACS_SHEET_AT = 0x5000             # relocated packed sheet's offset in the blob
# (erase box x0,y0,x1,y1 in map pixels; stamp text at sx,sy)
ACS_LABELS = (
    ((150, 51, 205, 68), "SP", 170, 52),
    ((104, 75, 142, 93), "ATK", 108, 76),
    ((212, 74, 232, 93), "DESP", 206, 76),
    ((104, 123, 142, 140), "HP", 112, 124),
    ((212, 123, 246, 140), "DEF", 216, 124),
    ((146, 152, 220, 168), "SILLY", 163, 152),
)
ACS_INK = 8                       # the kana fill colour in this sheet

# The マニュアル/オート VALUES are runtime records (bank $C4, same renderer as
# the option values) that overdraw the baked map columns on entry — found by
# searching for the マニ cell run: [vmadd $00A1|$00B5][len $14][rows 2].
# both highlight sets (pointer tables $C3:B58D = attr $0C00, $C3:B581 = $1000)
CFG_VALUES = (
    (0x0458CC, "MANUAL"), (0x045956, "MANUAL"),
    (0x0458FA, "AUTO"),   (0x045984, "AUTO"),
    (0x0459E0, "MANUAL"), (0x045A3C, "MANUAL"),
    (0x045A0E, "AUTO"),   (0x045A6A, "AUTO"),
)
CFG_LABELS = (
    (5,  1,  10, "MANUAL"),
    (5,  21, 30, "MANUAL"),
    (5,  13, 18, "MODE"),
    (7,  12, 19, "LP"),
    (9,  12, 19, "HP"),
    (11, 12, 19, "LK"),
    (13, 12, 19, "HK"),
    (15, 10, 21, "LSP"),
    (17, 10, 21, "HSP"),
    (21, 12, 19, "STAGE"),
)


def encode_glyph(rows, ink=INK):
    """an 8x16 '#'/'.' glyph -> (top 32-byte tile, bottom 32-byte tile), 4bpp"""
    out = []
    for half in (0, 8):
        t = bytearray(32)
        for y in range(8):
            line = rows[half + y]
            for x in range(8):
                if line[x] != "#":
                    continue
                b = 7 - x
                t[y * 2] |= (ink & 1) << b
                t[y * 2 + 1] |= ((ink >> 1) & 1) << b
                t[16 + y * 2] |= ((ink >> 2) & 1) << b
                t[16 + y * 2 + 1] |= ((ink >> 3) & 1) << b
        out.append(bytes(t))
    return out


def opt_stub(bank):
    """The Options-loader hook stub: upload the (patched) font record, then do
    the displaced first load of the cluster. Runs via JSL from the $03 mirror;
    everything bank-sensitive is immediate or long-addressed."""
    return f"""
  rep #$20
  lda #$0000
  sta_dp $00
  lda #${bank:04X}
  sta_dp $02
  lda #$7EC0
  sta_dp $04
  sep #$20
  jsl $80927D
  rep #$20
  lda #$4000
  sta_dp $00
  lda #$4000
  sta_dp $02
  lda #$C000
  sta_dp $04
  sep #$20
  lda #$7E
  sta_dp $06
  jsl $8092AD
  rep #$30
  lda #$003E
  sta_l $7E1C18
  rtl
"""
    # DP layout: decompress src24 at $00-$02, dest24 at $03-$05 (the two word
    # writes at $02/$04 lay down src-bank + dest $7E:C000 in one go); DMA
    # vram/len/src24 at $00/$02/$04-$06 — exactly $C3:82CA's calling convention.


def cs_stub(bank, arm):
    """Loader-cluster hook: DMA the uncompressed half-width block from the
    patch bank to VRAM $5C0 (via $80:92AD, DP $00-$06), then the displaced
    first record load (arm = the cluster's own first index*2)."""
    return f"""
  rep #$20
  lda #$5C00
  sta_dp $00
  lda #$0800
  sta_dp $02
  lda #${CS_BLOCK_AT:04X}
  sta_dp $04
  sep #$20
  lda #${bank:02X}
  sta_dp $06
  jsl $8092AD
  rep #$30
  lda #${arm:04X}
  sta_l $7E1C18
  rtl
"""


def ps_stub(bank):
    """Tournament-select hook: copy the PLAYER SELECT record to $7F:8900,
    queue it (first zero slot in $1CD0, the $DF:8126 convention), restore the
    displaced X/Y and return."""
    return f"""
  rep #$30
  ldx #$0000
copy:
  lda_lx ${bank:02X}{PS_REC_AT:04X}
  sta_lx $7F8900
  inx
  inx
  cpx #$004E
  bcc copy
  ldy #$0000
scan:
  lda_y $1CD0
  beq free
  iny
  iny
  iny
  iny
  bra scan
free:
  lda #$8900
  sta_y $1CD0
  lda #$007F
  sta_y $1CD2
  ldx #$9247
  ldy #$8800
  rtl
"""


def report_stub(placed):
    """The REPORT CARD hook stub: rewrite the label cells in the staged map at
    $7F:0000, then replay $84F9's Y=0 upload inline. Straight-line generated
    code — one lda/sta_l per cell. Ends in $84F9's exit state (sep #$30)."""
    lines = ["  rep #$20"]
    for row, start, last, attr, text in DF_REPORT_LABELS:
        for c in range(start, max(start + len(text), last + 1)):
            i = c - start
            if i < len(text) and text[i] != " ":
                t = attr | (placed[text[i]] - 0x200)
                top, bot = t, t + 0x10
            elif i < len(text):
                top = bot = 0
            else:
                top = bot = 0
            for r, w in ((row, top), (row + 1, bot)):
                addr = 0x7F0000 + (r * 32 + c) * 2
                lines.append("  lda #$%04X" % w)
                lines.append("  sta_l $%06X" % addr)
    lines += [
        "  sep #$30",          # $84F9's own entry width
        "  lda #$01",
        "  sta $4300",
        "  lda #$00",
        "  sta $2116",
        "  lda #$70",
        "  sta $2117",
        "  lda #$18",
        "  sta $4301",
        "  lda #$00",
        "  sta $4302",
        "  lda #$00",
        "  sta $4303",
        "  lda #$7F",
        "  sta $4304",
        "  lda #$00",
        "  sta $4305",
        "  lda #$08",
        "  sta $4306",
        "  lda #$01",
        "  sta $420B",
        "  rtl",
    ]
    return "\n".join(lines)


def find_record(data, want_src):
    """Locate the asset record whose src is `want_src`. Returns (index, file off
    of the record start). The record is [vram16][len16][src24][dest24]."""
    B3 = 0x030000
    for n in range(NRECS):
        o = B3 + REC0 + n * RECSZ
        src = data[o + 4] | (data[o + 5] << 8) | (data[o + 6] << 16)
        if src == want_src:
            return n, o
    return None, None


def build(src_path, out_path, stacked=False):
    require_source(src_path, stacked)   # the series' #12/#66 gate (was a hand-rolled copy)
    data = bytearray(open(src_path, "rb").read())

    # Locate the record BEFORE touching anything: its src field IS the block's
    # only pointer, so writing the pointer first would make the search fail.
    n, rec = find_record(data, FONT_SRC)
    if rec is None:
        raise SystemExit("no asset record points at the font sheet $%06X — has "
                         "another patch moved it?" % FONT_SRC)
    vram = data[rec] | (data[rec + 1] << 8)
    old_len = data[rec + 2] | (data[rec + 3] << 8)
    dest = data[rec + 7] | (data[rec + 8] << 8) | (data[rec + 9] << 16)
    if (vram, old_len, dest) != (FONT_VRAM, FONT_LEN, FONT_DEST):
        raise SystemExit("record #%d reads vram $%04X len $%04X dest $%06X, "
                         "expected $%04X/$%04X/$%06X — the table layout or the "
                         "asset has changed"
                         % (n, vram, old_len, dest, FONT_VRAM, FONT_LEN, FONT_DEST))
    # A longer transfer must not run off the end of the source bank.
    if (dest & 0xFFFF) + NEW_LEN > 0x10000:
        raise SystemExit("length $%04X would read past the end of bank $%02X "
                         "from $%04X" % (NEW_LEN, dest >> 16, dest & 0xFFFF))

    src = FONT_SRC & 0x3FFFFF
    sheet = bytearray(sms_lz.decompress(bytes(data), src, 0x8000))
    old_tiles = len(sheet) // 32
    if old_tiles != 418:
        raise SystemExit("font sheet is %d tiles, expected 418 — it has moved "
                         "or been patched" % old_tiles)
    sheet += bytes(NEW_TILES * 32 - len(sheet))          # extend, zero-filled

    glyphs, prov = mkhalfwidth.alphabet()
    letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    placed = {}
    for i, ch in enumerate(letters):
        row, col = divmod(i, SHEET_W)
        top = GLYPH_ROWS[row] + col
        bot = top + SHEET_W
        for tile in (top, bot):
            o = (tile - TILE_BASE) * 32
            if any(sheet[o:o + 32]):
                raise SystemExit("tile $%03X is not blank — refusing to overwrite" % tile)
        tt, bb = encode_glyph(glyphs[ch])
        sheet[(top - TILE_BASE) * 32:(top - TILE_BASE) * 32 + 32] = tt
        sheet[(bot - TILE_BASE) * 32:(bot - TILE_BASE) * 32 + 32] = bb
        placed[ch] = top
    for ch, top in PUNCT_SLOTS.items():
        bot = top + SHEET_W
        for tile in (top, bot):
            o = (tile - TILE_BASE) * 32
            if any(sheet[o:o + 32]):
                raise SystemExit("tile $%03X is not blank — refusing to overwrite" % tile)
        tt, bb = encode_glyph(PUNCT[ch])
        sheet[(top - TILE_BASE) * 32:(top - TILE_BASE) * 32 + 32] = tt
        sheet[(bot - TILE_BASE) * 32:(bot - TILE_BASE) * 32 + 32] = bb
        placed[ch] = top

    packed = sms_lz.encode(bytes(sheet))
    assert sms_lz.decompress(packed, 0, len(sheet)) == bytes(sheet), "font round-trip failed"

    # ---- the OPTIONS screen's tilemap (opt-in; see OPT_TRANSLATE) ----
    on, orec, packed_map = None, None, None
    if OPT_TRANSLATE:
     on, orec = find_record(data, OPT_SRC)
     if orec is None:
         raise SystemExit("no asset record points at the options tilemap $%06X" % OPT_SRC)
     omap = bytearray(sms_lz.decompress(bytes(data), OPT_SRC & 0x3FFFFF, 0x4000))
     if len(omap) != 0x800:
         raise SystemExit("options tilemap is %#x bytes, expected 0x800" % len(omap))

     def _cell(r, c):
         return (r * OPT_MAP_W + c) * 2

     def _get(r, c):
         o = _cell(r, c)
         return omap[o] | (omap[o + 1] << 8)

     def _put(r, c, w):
         o = _cell(r, c)
         omap[o], omap[o + 1] = w & 0xFF, (w >> 8) & 0xFF

     blank = _get(0, 0)
     if blank & 0x03FF:
         raise SystemExit("map cell (0,0) is not blank — cannot use it as the clear value")
     for row, text in OPT_LABELS:
         attr = _get(row, OPT_LABEL_COL) & ~0x03FF & 0xFFFF
         if len(text) > OPT_LABEL_COLS:
             raise SystemExit("%r is %d columns, budget is %d"
                              % (text, len(text), OPT_LABEL_COLS))
         for c in range(OPT_LABEL_COL, OPT_LABEL_COL + OPT_LABEL_COLS):
             _put(row, c, blank)
             _put(row + 1, c, blank)
         for i, ch in enumerate(text):
             if ch == " ":
                 continue
             t = placed[ch] - CHR_BASE_TILE
             if t > 0x03FF:
                 raise SystemExit("glyph %r maps to tile $%03X, past the 10-bit field" % (ch, t))
             _put(row, OPT_LABEL_COL + i, attr | t)
             _put(row + 1, OPT_LABEL_COL + i, attr | (t + 0x10))
     packed_map = sms_lz.encode(bytes(omap))
     assert sms_lz.decompress(packed_map, 0, len(omap)) == bytes(omap), "options map round-trip failed"

     # value records: in-place cell edits in bank $C4 (see OPT_VALUES)
     for head, text in OPT_VALUES:
         o = 0x040000 + head
         vmadd = data[o] | (data[o + 1] << 8)
         ln = data[o + 2] | (data[o + 3] << 8)
         nrows = data[o + 4] | (data[o + 5] << 8)
         if (ln, nrows) != (0x14, 2) or vmadd not in (0x00B4, 0x0114):
             raise SystemExit("value record $C4:%04X reads vmadd=$%04X len=$%04X "
                              "rows=%d — layout changed" % (head, vmadd, ln, nrows))
         cells = o + 6
         attr = 0
         for i in range(20):
             w = data[cells + i * 2] | (data[cells + i * 2 + 1] << 8)
             if w & 0x03FF:
                 attr = w & 0xFC00
                 break
         if not attr:
             raise SystemExit("value record $C4:%04X has no glyph cells" % head)
         if len(text) > 10:
             raise SystemExit("%r is %d cells, the value field is 10" % (text, len(text)))
         start = (10 - len(text)) // 2
         for c in range(10):
             top = bot = 0
             i = c - start
             if 0 <= i < len(text):
                 t = placed[text[i]] - CHR_BASE_TILE
                 top, bot = attr | t, attr | (t + 0x10)
             for r, w in ((0, top), (1, bot)):
                 off = cells + (r * 10 + c) * 2
                 data[off], data[off + 1] = w & 0xFF, w >> 8

    # ---- the $DF screens (see the DF_TRANSLATE block above) ----------------
    packed_df = None
    if DF_TRANSLATE:
        big = bytearray(sms_lz.decompress(bytes(data), DF_SHEET_SRC & 0x3FFFFF, 0x8000))
        if len(big) != DF_SHEET_RAW:
            raise SystemExit("big text sheet is %#x bytes, expected %#x"
                             % (len(big), DF_SHEET_RAW))
        big += bytes((DF_SHEET_TILES - DF_SHEET_RAW // 32) * 32)
        for ch in placed:
            # same relative layout as the menu font's $5C0 window; ink 1 — the
            # colour the kana on these screens use (7 renders near-white here)
            t = DF_GLYPH_TILE + (placed[ch] - GLYPH_ROWS[0])
            tt, bb = encode_glyph(glyphs.get(ch) or PUNCT[ch], ink=1)
            big[t * 32:t * 32 + 32] = tt
            big[(t + 0x10) * 32:(t + 0x10) * 32 + 32] = bb
        packed_df = sms_lz.encode(bytes(big))
        assert sms_lz.decompress(packed_df, 0, len(big)) == bytes(big), \
            "df sheet round-trip failed"
        # guards first, so a failed build writes nothing
        for ref in DF_SCRIPT_REFS:
            if bytes(data[ref:ref + 3]) != bytes.fromhex("d048c3") or data[ref + 3] == 0:
                raise SystemExit("script entry at %#x does not reference the "
                                 "sheet — layout changed" % ref)
            ln = data[ref + 6] | (data[ref + 7] << 8)
            if ln != 0x5000:
                raise SystemExit("script entry at %#x len=$%04X, expected $5000"
                                 % (ref, ln))
        for off, text in DF_NAMES:
            vmadd = data[off] | (data[off + 1] << 8)
            ln = data[off + 2] | (data[off + 3] << 8)
            nrows = data[off + 4] | (data[off + 5] << 8)
            if (vmadd, ln, nrows) != (0, 0x18, 2):
                raise SystemExit("name block %#x header %04X/%04X/%d unexpected"
                                 % (off, vmadd, ln, nrows))
            if len(text) > 12:
                raise SystemExit("%r exceeds the 12-cell name row" % text)
        for off, text in DF_NAMES:
            cells = off + 6
            attr = 0
            for i in range(24):
                w = data[cells + i * 2] | (data[cells + i * 2 + 1] << 8)
                if w & 0x03FF:
                    attr = w & 0xFC00
                    break
            if not attr:
                raise SystemExit("name block %#x has no glyph cells" % off)
            for c in range(12):
                top = bot = 0
                if c < len(text) and text[c] != " ":
                    # sheet at vmadd $2A00, CHR base $200: cell = sheet + $A0,
                    # which lands on the menu convention (placed - $200)
                    t = DF_GLYPH_TILE + (placed[text[c]] - GLYPH_ROWS[0]) + 0xA0
                    top = attr | t
                    bot = attr | (t + 0x10)
                for r, w in ((0, top), (1, bot)):
                    o2 = cells + (r * 12 + c) * 2
                    data[o2], data[o2 + 1] = w & 0xFF, w >> 8

    # Relocation is mandatory even for unchanged data: this project's encoder is
    # weaker than the original's, so the block cannot be written back in place.
    # Both relocated blocks share one appended bank: the font at $0000 and the
    # options map at $8000. Relocation is mandatory for either -- our encoder is
    # weaker than the original's, so even unchanged data cannot be written back
    # in place.
    MAP_AT = 0x8000
    if len(packed) > STUB_AT:
        raise SystemExit("packed font (%#x) would overlap the stub slot at %#x"
                         % (len(packed), STUB_AT))
    if packed_map and len(packed_map) > 0x10000 - MAP_AT:
        raise SystemExit("packed options map (%#x) overruns the bank" % len(packed_map))
    base, bank = next_bank(data)
    stub, _ = asm65816.assemble(opt_stub(bank).splitlines(), STUB_AT, bank)
    if STUB_AT + len(stub) > MAP_AT:
        raise SystemExit("stub (%#x bytes) overruns the map slot" % len(stub))
    stage_names = list(STAGE_NAMES)
    if SATURN_STAGE:
        stage_names[2] = "SILENT THRONE OF MESSIAH"
    csstub = csblock = None
    if STAGES_TRANSLATE:
        if bytes(data[CS_HOOK_FILE:CS_HOOK_FILE + 6]) != CS_HOOK_OLD:
            raise SystemExit("char-select hook site reads %s, expected %s"
                             % (bytes(data[CS_HOOK_FILE:CS_HOOK_FILE + 6]).hex(),
                                CS_HOOK_OLD.hex()))
        for i, name in enumerate(stage_names):
            if len(name) > 24:
                raise SystemExit("%r is %d chars, the stage row is 24" % (name, len(name)))
            for v in (0, 1):
                off = STAGE_REC0 + i * 0xCC + v * 0x66
                vmadd = data[off] | (data[off + 1] << 8)
                ln = data[off + 2] | (data[off + 3] << 8)
                nrows = data[off + 4] | (data[off + 5] << 8)
                if (vmadd, ln, nrows) != (0x02E4, 0x30, 2):
                    raise SystemExit("stage record %#x header %04X/%04X/%d unexpected"
                                     % (off, vmadd, ln, nrows))
        for i, name in enumerate(stage_names):
            for v in (0, 1):
                off = STAGE_REC0 + i * 0xCC + v * 0x66
                cells = off + 6
                attr = 0
                for k in range(48):
                    w = data[cells + k * 2] | (data[cells + k * 2 + 1] << 8)
                    if w & 0x03FF:
                        attr = w & 0xFC00
                        break
                if not attr:
                    raise SystemExit("stage record %#x has no glyph cells" % off)
                start = (24 - len(name)) // 2
                for c in range(24):
                    j = c - start
                    top = bot = 0
                    if 0 <= j < len(name) and name[j] != " ":
                        t = placed[name[j]] - 0x200
                        top, bot = attr | t, attr | (t + 0x10)
                    for r, w in ((0, top), (1, bot)):
                        o2 = cells + (r * 24 + c) * 2
                        data[o2], data[o2 + 1] = w & 0xFF, w >> 8
        # the config-row labels: relocated tilemap edit (see CFG_LABELS)
        if bytes(data[CFG_MAP_REF:CFG_MAP_REF + 3]) != bytes.fromhex("007cc3"):
            raise SystemExit("config map record src reads %s, expected 007cc3"
                             % bytes(data[CFG_MAP_REF:CFG_MAP_REF + 3]).hex())
        cmap = bytearray(sms_lz.decompress(bytes(data), CFG_MAP_SRC & 0x3FFFFF, 0x4000))
        if len(cmap) != 0x800:
            raise SystemExit("config map is %#x bytes, expected 0x800" % len(cmap))
        for row, start, last, text in CFG_LABELS:
            attr = 0
            for c in range(start, last + 1):
                w = cmap[(row * 32 + c) * 2] | (cmap[(row * 32 + c) * 2 + 1] << 8)
                if w & 0x03FF:
                    attr = w & 0xFC00
                    break
            if not attr:
                raise SystemExit("config label at row %d has no glyph cells" % row)
            tstart = start + (last - start + 1 - len(text)) // 2
            for c in range(start, last + 1):
                j = c - tstart
                top = bot = 0
                if 0 <= j < len(text) and text[j] != " ":
                    t = placed[text[j]] - 0x200
                    top, bot = attr | t, attr | (t + 0x10)
                for r, w in ((row, top), (row + 1, bot)):
                    o2 = (r * 32 + c) * 2
                    cmap[o2], cmap[o2 + 1] = w & 0xFF, w >> 8
        packed_cmap = sms_lz.encode(bytes(cmap))
        assert sms_lz.decompress(packed_cmap, 0, len(cmap)) == bytes(cmap), \
            "config map round-trip failed"
        # the MANUAL/AUTO value records (overdraw the map columns on entry)
        for off, text in CFG_VALUES:
            vmadd = data[off] | (data[off + 1] << 8)
            ln = data[off + 2] | (data[off + 3] << 8)
            nrows = data[off + 4] | (data[off + 5] << 8)
            if vmadd not in (0x00A1, 0x00B5) or (ln, nrows) != (0x14, 2):
                raise SystemExit("config value record %#x header %04X/%02X/%d "
                                 "unexpected" % (off, vmadd, ln, nrows))
            cells = off + 6
            attr = 0
            for k in range(20):
                w = data[cells + k * 2] | (data[cells + k * 2 + 1] << 8)
                if w & 0x03FF:
                    attr = w & 0xFC00
                    break
            if not attr:
                raise SystemExit("config value record %#x has no glyph cells" % off)
            start = (10 - len(text)) // 2
            for c in range(10):
                j = c - start
                top = bot = 0
                if 0 <= j < len(text):
                    t = placed[text[j]] - 0x200
                    top, bot = attr | t, attr | (t + 0x10)
                for r, w in ((0, top), (1, bot)):
                    o2 = cells + (r * 10 + c) * 2
                    data[o2], data[o2 + 1] = w & 0xFF, w >> 8
        # the uncompressed glyph block the hook uploads (VRAM-order $5C0-$5FF)
        csblock = bytearray(0x800)
        for ch, top in placed.items():
            tt, bb = encode_glyph(glyphs.get(ch) or PUNCT[ch], ink=1)
            csblock[(top - 0x5C0) * 32:(top - 0x5C0) * 32 + 32] = tt
            csblock[(top - 0x5C0 + 0x10) * 32:(top - 0x5C0 + 0x10) * 32 + 32] = bb
        csstub, _ = asm65816.assemble(cs_stub(bank, 0x1A).splitlines(), CS_STUB_AT, bank)
        if CS_STUB_AT + len(csstub) > MAP_AT:
            raise SystemExit("cs stub (%#x bytes) overruns the map slot" % len(csstub))
        if STUB_AT + len(stub) > CS_STUB_AT:
            raise SystemExit("options stub overruns the cs stub slot")

    astub = packed_acs = None
    if ACS_TRANSLATE:
        if not STAGES_TRANSLATE:
            raise SystemExit("SMS_P16_ACS needs SMS_P16_STAGES (shares the glyph block)")
        if bytes(data[ACS_SHEET_REF:ACS_SHEET_REF + 3]) != bytes.fromhex("0034c2"):
            raise SystemExit("ACS sheet record src reads %s, expected 0034c2"
                             % bytes(data[ACS_SHEET_REF:ACS_SHEET_REF + 3]).hex())
        amap = sms_lz.decompress(bytes(data), ACS_MAP_SRC & 0x3FFFFF, 0x4000)
        asheet = bytearray(sms_lz.decompress(bytes(data), ACS_SHEET_SRC & 0x3FFFFF, 0x8000))
        if len(asheet) != 0x2000:
            raise SystemExit("ACS art sheet is %#x bytes, expected 0x2000" % len(asheet))

        def acs_tile(px, py):
            w = amap[((py // 8) * 32 + px // 8) * 2] \
                | (amap[((py // 8) * 32 + px // 8) * 2 + 1] << 8)
            vt = (w & 0x3FF) + 0x200
            return vt - 0x300 if 0x300 <= vt < 0x400 else None

        def acs_set(px, py, v):
            t = acs_tile(px, py)
            if t is None:
                raise SystemExit("ACS pixel (%d,%d) is not on the art sheet" % (px, py))
            o = t * 32 + (py % 8) * 2
            b = 7 - (px % 8)
            m = 0xFF ^ (1 << b)
            for plane, off in ((0, o), (1, o + 1), (2, o + 16), (3, o + 17)):
                asheet[off] = (asheet[off] & m) | (((v >> plane) & 1) << b)

        # tiles must be UNIQUE in the map, or an edit bleeds elsewhere
        touched = set()
        for (x0, y0, x1, y1), text, sx, sy in ACS_LABELS:
            for py in range(y0, y1):
                for px in range(x0, x1):
                    touched.add(acs_tile(px, py))
            for i in range(len(text)):
                for py in range(sy, sy + 16):
                    for px in range(sx + i * 8, sx + i * 8 + 8):
                        touched.add(acs_tile(px, py))
        counts = {}
        for k in range(0x400):
            w = amap[k * 2] | (amap[k * 2 + 1] << 8)
            vt = (w & 0x3FF) + 0x200
            if 0x300 <= vt < 0x400:
                counts[vt - 0x300] = counts.get(vt - 0x300, 0) + 1
        shared = [t for t in touched if t is not None and counts.get(t, 0) > 1]
        if shared:
            raise SystemExit("ACS label tiles are shared in the map: %s"
                             % ["%02X" % t for t in sorted(shared)])
        for (x0, y0, x1, y1), text, sx, sy in ACS_LABELS:
            for py in range(y0, y1):
                for px in range(x0, x1):
                    acs_set(px, py, 0)
            for i, ch in enumerate(text):
                rows = glyphs.get(ch) or PUNCT[ch]
                for gy in range(16):
                    for gx in range(8):
                        if rows[gy][gx] == "#":
                            acs_set(sx + i * 8 + gx, sy + gy, ACS_INK)
        packed_acs = sms_lz.encode(bytes(asheet))
        assert sms_lz.decompress(packed_acs, 0, len(asheet)) == bytes(asheet), \
            "ACS sheet round-trip failed"
        astub = True   # no code on this screen — raster labels need no font

    rstub = None
    if DF_TRANSLATE:
        if bytes(data[DF_REPORT_HOOK:DF_REPORT_HOOK + 7]) != DF_REPORT_OLD:
            raise SystemExit("report-card hook site reads %s, expected %s"
                             % (bytes(data[DF_REPORT_HOOK:DF_REPORT_HOOK + 7]).hex(),
                                DF_REPORT_OLD.hex()))
        rstub, _ = asm65816.assemble(report_stub(placed).splitlines(), REPORT_AT, bank)
        if REPORT_AT + len(rstub) > DF_SHEET_AT:
            raise SystemExit("report stub (%#x bytes) overruns the DF sheet slot"
                             % len(rstub))
        # PLAYER SELECT header record + queue stub
        if bytes(data[PS_HOOK_FILE:PS_HOOK_FILE + 6]) != PS_HOOK_OLD:
            raise SystemExit("PLAYER SELECT hook site reads %s, expected %s"
                             % (bytes(data[PS_HOOK_FILE:PS_HOOK_FILE + 6]).hex(),
                                PS_HOOK_OLD.hex()))
        psrec = bytearray([0xA7, 0x70, 0x24, 0x00, 0x02, 0x00])
        start = (18 - len(PS_TEXT)) // 2
        for row in (0, 1):
            for c in range(18):
                j = c - start
                w = 0
                if 0 <= j < len(PS_TEXT) and PS_TEXT[j] != " ":
                    t = placed[PS_TEXT[j]] - 0x200 + (0x10 if row else 0)
                    w = 0x1000 | t
                psrec += bytes([w & 0xFF, w >> 8])
        psstub, _ = asm65816.assemble(ps_stub(bank).splitlines(), PS_STUB_AT, bank)
        if PS_STUB_AT + len(psstub) > MAP_AT:
            raise SystemExit("ps stub (%#x bytes) overruns the map slot" % len(psstub))
    blob = bytearray(0x10000)
    blob[0:len(packed)] = packed
    blob[STUB_AT:STUB_AT + len(stub)] = stub
    if packed_map:
        if MAP_AT + len(packed_map) > PS_REC_AT:
            raise SystemExit("packed options map (%#x) overruns the ps-record slot"
                             % len(packed_map))
        blob[MAP_AT:MAP_AT + len(packed_map)] = packed_map
    if rstub:
        blob[REPORT_AT:REPORT_AT + len(rstub)] = rstub
        blob[PS_STUB_AT:PS_STUB_AT + len(psstub)] = psstub
        if PS_REC_AT + len(psrec) > CS_BLOCK_AT:
            raise SystemExit("ps record overruns the glyph-block slot")
        blob[PS_REC_AT:PS_REC_AT + len(psrec)] = psrec
    if csstub:
        blob[CS_STUB_AT:CS_STUB_AT + len(csstub)] = csstub
        blob[CS_BLOCK_AT:CS_BLOCK_AT + len(csblock)] = csblock
        if CFG_MAP_AT + len(packed_cmap) > ACS_SHEET_AT:
            raise SystemExit("packed config map (%#x) overruns the ACS sheet slot"
                             % len(packed_cmap))
        if len(packed) > CFG_MAP_AT:
            raise SystemExit("packed font (%#x) overruns the config map slot"
                             % len(packed))
        blob[CFG_MAP_AT:CFG_MAP_AT + len(packed_cmap)] = packed_cmap
    if astub:
        if ACS_SHEET_AT + len(packed_acs) > STUB_AT:
            raise SystemExit("packed ACS sheet (%#x) overruns the stub slot"
                             % len(packed_acs))
        blob[ACS_SHEET_AT:ACS_SHEET_AT + len(packed_acs)] = packed_acs
    if packed_df:
        if DF_SHEET_AT + len(packed_df) > 0x10000:
            raise SystemExit("packed DF sheet (%#x) overruns the bank" % len(packed_df))
        blob[DF_SHEET_AT:DF_SHEET_AT + len(packed_df)] = packed_df
    write_bank(data, base, bytes(blob))
    # hook the Options loader's first record load (see OPT_HOOK_FILE block)
    if bytes(data[OPT_HOOK_FILE:OPT_HOOK_FILE + 6]) != OPT_HOOK_OLD:
        raise SystemExit("Options loader at $C3:%04X reads %s, expected %s — "
                         "another patch has touched it"
                         % (OPT_HOOK_FILE & 0xFFFF,
                            bytes(data[OPT_HOOK_FILE:OPT_HOOK_FILE + 6]).hex(),
                            OPT_HOOK_OLD.hex()))
    data[OPT_HOOK_FILE:OPT_HOOK_FILE + 6] = bytes(
        [0x22, STUB_AT & 0xFF, STUB_AT >> 8, bank, 0xEA, 0xEA])
    data[rec + 4] = 0x00
    data[rec + 5] = 0x00
    data[rec + 6] = bank
    data[rec + 2] = NEW_LEN & 0xFF
    data[rec + 3] = NEW_LEN >> 8
    if orec is not None:
        data[orec + 4] = MAP_AT & 0xFF
        data[orec + 5] = MAP_AT >> 8
        data[orec + 6] = bank
    if packed_df:
        DF_NEW_LEN = DF_SHEET_TILES * 32
        for ref in DF_SCRIPT_REFS:
            data[ref] = DF_SHEET_AT & 0xFF
            data[ref + 1] = DF_SHEET_AT >> 8
            data[ref + 2] = bank
            data[ref + 6] = DF_NEW_LEN & 0xFF
            data[ref + 7] = DF_NEW_LEN >> 8
        # the report-card hook: 'sep #$10 / ldy #$00 / jsr $84F9' -> JSL stub
        data[DF_REPORT_HOOK:DF_REPORT_HOOK + 7] = bytes(
            [0x22, REPORT_AT & 0xFF, REPORT_AT >> 8, bank, 0xEA, 0xEA, 0xEA])
        # the PLAYER SELECT hook: 'ldx #$9247 / ldy #$8800' -> JSL stub
        data[PS_HOOK_FILE:PS_HOOK_FILE + 6] = bytes(
            [0x22, PS_STUB_AT & 0xFF, PS_STUB_AT >> 8, bank, 0xEA, 0xEA])
    if csstub:
        data[CS_HOOK_FILE:CS_HOOK_FILE + 6] = bytes(
            [0x22, CS_STUB_AT & 0xFF, CS_STUB_AT >> 8, bank, 0xEA, 0xEA])
        data[CFG_MAP_REF] = CFG_MAP_AT & 0xFF
        data[CFG_MAP_REF + 1] = CFG_MAP_AT >> 8
        data[CFG_MAP_REF + 2] = bank
    if astub:
        data[ACS_SHEET_REF] = ACS_SHEET_AT & 0xFF
        data[ACS_SHEET_REF + 1] = ACS_SHEET_AT >> 8
        data[ACS_SHEET_REF + 2] = bank

    fix_checksum(data)
    open(out_path, "wb").write(bytes(data))
    print("patch 16 (font install)")
    print("  font sheet: %d -> %d tiles, %d bytes packed" % (old_tiles, NEW_TILES, len(packed)))
    print("  relocated to bank $%02X, record #%d src repointed" % (bank, n))
    print("  upload length $%04X -> $%04X BYTES (field at $C3:%04X)"
          % (old_len, NEW_LEN, rec - 0x030000 + 2))
    print("  %d glyphs at VRAM tiles $%03X-$%03X / $%03X-$%03X"
          % (len(placed), GLYPH_ROWS[0], GLYPH_ROWS[0] + 15, GLYPH_ROWS[1], GLYPH_ROWS[1] + 9))
    print("  options loader hooked ($C3:%04X -> $%02X:%04X, %dB stub): font "
          "re-uploaded after the transition's VRAM clear"
          % (OPT_HOOK_FILE & 0xFFFF, bank, STUB_AT, len(stub)))
    if OPT_TRANSLATE:
        print("  options screen: record #%d relocated, %d labels translated (%s)"
              % (on, len(OPT_LABELS), ", ".join(t for _, t in OPT_LABELS)))
        print("  option values: %d records edited in place (%s)"
              % (len(OPT_VALUES), ", ".join(sorted(set(t for _, t in OPT_VALUES)))))
    else:
        print("  options screen: labels NOT translated (SMS_P16_OPTIONS=1 to enable)")
    if DF_TRANSLATE:
        print("  $DF screens: sheet extended 608 -> %d tiles (%d bytes packed at "
              "$%02X:%04X), 3 scripts repointed, %d tournament names translated"
              % (DF_SHEET_TILES, len(packed_df), bank, DF_SHEET_AT, len(DF_NAMES)))
        print("  report card: hook $DF:9679 -> $%02X:%04X (%dB stub), %d labels"
              % (bank, REPORT_AT, len(rstub), len(DF_REPORT_LABELS)))
    else:
        print("  $DF screens (tournament/report): NOT translated (SMS_P16_DF=1)")
    if STAGES_TRANSLATE:
        print("  stage names: 20 records rewritten (10 stages x 2 states); "
              "char-select hook $C3:AF8A -> $%02X:%04X uploads the glyph block"
              % (bank, CS_STUB_AT))
        print("  config rows: %d labels in the relocated $C3:7C00 map (%s)"
              % (len(CFG_LABELS), ", ".join(t for _, _, _, t in CFG_LABELS)))
    else:
        print("  stage names: NOT translated (SMS_P16_STAGES=1 to enable)")
    if ACS_TRANSLATE:
        print("  ACS wheel: %d labels raster-edited in the relocated art sheet (%s)"
              % (len(ACS_LABELS), ", ".join(t for _, t, _, _ in ACS_LABELS)))
    else:
        print("  ACS wheel: NOT translated (SMS_P16_ACS=1 to enable)")
    print("  -> %s  sha1 %s" % (out_path, hashlib.sha1(bytes(data)).hexdigest()))
    json.dump({c: placed[c] for c in sorted(placed)},
              open(os.path.join(REPO, "docs", "halfwidth_tiles.json"), "w"), indent=1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stacked", action="store_true")
    ap.add_argument("paths", nargs="+")
    a = ap.parse_args()
    if a.stacked:
        if len(a.paths) != 2:
            raise SystemExit("--stacked needs <in> <out>")
        src, out = a.paths
        if os.path.abspath(src) == os.path.abspath(out):
            raise SystemExit("src == out")
    else:
        src, out = clean_rom(), a.paths[0]
    build(src, out, a.stacked)


if __name__ == "__main__":
    main()
