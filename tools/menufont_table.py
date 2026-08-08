#!/usr/bin/env python3
"""menufont_table.py — the menu font's glyph-code -> character table.

docs/project/saturn/movelist.md recorded "Still missing: the code -> glyph table"; this
is it. Read off rendered contact sheets (tools/menufont.py sheet) and then
VALIDATED by decoding a real screen tilemap through it and checking the result
against the strings the game is known to show (see `menufont.py decode-map`).

Coordinates. A glyph is 16x16 = 2x2 tiles in a 16-tile-wide sheet, so codes step
by 2 along a row and rows of glyphs are 0x20 apart. Two compressed blocks supply
the sheet and land at different VRAM bases:

    kana/general block  $C3:48D0 -> VRAM tile code = block code + KANA_BASE
    kanji block         $C7:07F0 -> VRAM tile code = block code + KANJI_BASE

Cross-checks that pin those bases: Latin 'A' is block $16A and the screens use
$20A; the blank run measured at block $068+ is the $368+ the survey saw.

Tables are BLOCK-relative. Use vram() / from_vram() to convert.
"""

KANA_BASE = 0x0A0
KANJI_BASE = 0x300

# --- kana / general block ($C3:48D0) ---------------------------------------
KANA = {
    0x002: "い", 0x004: "う", 0x006: "え", 0x008: "お",
    0x00A: "か", 0x00C: "き", 0x00E: "く",
    0x020: "こ", 0x022: "が", 0x024: "げ", 0x026: "ご",
    0x028: "さ", 0x02A: "し", 0x02C: "す", 0x02E: "せ",
    0x040: "そ", 0x042: "じ", 0x044: "ず", 0x046: "ち",
    0x048: "っ", 0x04A: "て", 0x04C: "と", 0x04E: "な",
    0x060: "に", 0x062: "の", 0x064: "ひ", 0x066: "ふ",
    0x068: "へ", 0x06A: "ば", 0x06C: "び", 0x06E: "ぶ",
    0x080: "だ", 0x082: "ぱ", 0x084: "ま", 0x086: "む",
    0x088: "や", 0x08A: "よ", 0x08C: "ゃ", 0x08E: "ゆ",
    0x0A0: "ょ", 0x0A2: "ら", 0x0A4: "り", 0x0A6: "る",
    0x0A8: "れ", 0x0AA: "わ", 0x0AC: "を", 0x0AE: "ん",
    0x0C0: "ぃ", 0x0C2: "っ", 0x0C4: "ー", 0x0C6: "ア",
    0x0C8: "イ", 0x0CA: "ウ", 0x0CC: "オ", 0x0CE: "ィ",
    0x0E0: "キ", 0x0E2: "ク", 0x0E4: "コ", 0x0E6: "サ",
    0x0E8: "シ", 0x0EA: "ス", 0x0EC: "セ", 0x0EE: "ジ",
    0x100: "ズ", 0x102: "タ", 0x104: "チ", 0x106: "テ",
    0x108: "ト", 0x10A: "ド", 0x10C: "ナ", 0x10E: "ニ",
    0x120: "ヌ", 0x122: "ネ", 0x124: "ノ", 0x126: "バ",
    0x128: "ブ", 0x12A: "ベ", 0x12C: "ピ", 0x12E: "プ",
    0x140: "マ", 0x142: "ミ", 0x144: "ム", 0x146: "モ",
    0x148: "ャ", 0x14A: "ュ", 0x14C: "ョ", 0x14E: "ラ",
    0x160: "リ", 0x162: "ル", 0x164: "レ", 0x166: "ン", 0x168: "ヴ",
    # Latin capitals, the ALPHABET style
    0x16A: "A", 0x16C: "B", 0x16E: "C",
    0x180: "D", 0x182: "E", 0x184: "G", 0x186: "H",
    0x188: "I", 0x18A: "K", 0x18C: "L", 0x18E: "M",
    0x1A0: "N", 0x1A2: "O", 0x1A4: "P", 0x1A6: "R",
    0x1A8: "T", 0x1AA: "U", 0x1AC: "V", 0x1AE: "W",
    0x1C0: "X", 0x1C2: "Y",
    # BUTTON labels — a second style, not usable as an alphabet
    0x1C4: "[A]", 0x1C6: "[B]", 0x1C8: "[X]",
    0x1CA: "[Y]", 0x1CC: "[L]", 0x1CE: "[R]",
    # digits, style 1
    0x1E0: "0", 0x1E2: "1", 0x1E4: "2", 0x1E6: "3",
    0x1E8: "4", 0x1EA: "5", 0x1EC: "6", 0x1EE: "7",
    0x200: "8", 0x202: "9",
    # digits, style 2 — and an F in the SAME style (see MISSING below)
    0x204: "0", 0x206: "1", 0x208: "2", 0x20A: "3",
    0x20C: "4", 0x20E: "5", 0x220: "6", 0x222: "7",
    0x224: "8", 0x226: "9", 0x228: "F",
    # $22E is the EVENING marker 夕, not katakana タ — the two letterforms are
    # near-identical, but katakana タ has its own slot at $102, and this one sits
    # in the marker group beside ◆ and pairs with 昼/夜 on the stage names
    # (stage 0 = Crystal Tokyo evening, stage 7 = the same stage at night).
    0x22A: "◆", 0x22C: "メ", 0x22E: "夕",
    0x240: "夜", 0x242: "昼", 0x244: "強", 0x246: "弱",
    0x248: "勝", 0x24A: "あ", 0x24C: "▶", 0x24E: "ー",
}

# --- kanji block ($C7:07F0) -------------------------------------------------
# $080 onward is a PRE-COMPOSED half-width strip, 'PRESS "SELECT" TO ACS', not
# an alphabet: those cells hold two letters each and cannot be recombined.
KANJI = {
    0x000: "十", 0x002: "番", 0x004: "川", 0x006: "神",
    0x008: "王", 0x00A: "州", 0x00C: "水", 0x00E: "海",
    0x020: "商", 0x022: "店", 0x024: "社", 0x026: "編",
    0x028: "公", 0x02A: "園", 0x02C: "必", 0x02E: "殺",
    0x040: "街", 0x042: "噴", 0x044: "集", 0x046: "部",
    0x048: "時", 0x04A: "空", 0x04C: "扉", 0x04E: "火",
    0x060: "数", 0x062: "残", 0x064: "ッ", 0x066: "パ",
}

# Latin capitals the font does NOT have at FULL width (16x16) — the size menu
# labels are set in. Verified by rendering every glyph in both blocks.
# F is NOT missing: it sits at kana block $228 (VRAM $2C8), after the second
# digit run, and a side-by-side render against B/E/H shows the same stroke
# weight and cap height — it sets as part of the alphabet. docs/game/menu_text.md had
# listed it missing, from a survey that never rendered the digit run.
# So the full-width alphabet has 22 of 26; four must be authored.
MISSING = ("J", "Q", "S", "Z")

# HALF-WIDTH (8x16) Latin exists too, but ONLY as the pre-composed
# 'PRESS "SELECT" TO ACS' strip in the kanji block ($080+). Rendering it a tile
# at a time shows the letters ARE individually addressable — 1 tile wide, 2 tall
# — so these nine are available at half width even though the strip reads as one
# phrase. Useful two ways: half-width text would double a label's character
# budget, and the half-width S is a faithful model for drawing the full-width S.
HALFWIDTH_STRIP = 0x080          # kanji-block code of the first tile
HALFWIDTH_LETTERS = ("P", "R", "E", "S", "L", "C", "T", "O", "A")

# Blank slots usable WITHOUT relocating anything. Counted the way the sheet is
# actually arranged: a glyph is 2x2 tiles at (t, t+1, t+SHEET_W, t+SHEET_W+1), so
# a HALF-width glyph needs (t, t+SHEET_W) blank and a FULL-width one needs two
# adjacent half-slots.
#   kana  $0A0-$0A1   2 half-slots  = 1 full-width glyph
#   kanji $368-$36F   8 half-slots  = 4 full-width glyphs
#   TOTAL            10 half-slots  = 5 full-width glyphs
# CORRECTION: an earlier count said 10 FULL-width slots by also counting
# $3A6-$3AF. Those tiles are blank but their BOTTOM halves fall past the end of
# the 182-tile kanji block, so they are not usable until the block is extended.
# Extending is a solved operation — mkkanji.py already decompresses, inserts,
# re-encodes and relocates this exact block (that is how v0.14.0 added the stage
# kanji) — and the menu survey read VRAM $3C0-$3EE as blank, i.e. roughly 57
# tiles of apparent headroom beyond the block to grow into. "Read as blank" is
# evidence, not proof, so anything relying on it needs checking first.
FREE_HALF_SLOTS = {"kana": (0x0A0, 0x0A1),
                   "kanji": tuple(range(0x368, 0x370))}
FREE_FULL_SLOTS = {"kana": (0x0A0,),
                   "kanji": (0x368, 0x36A, 0x36C, 0x36E)}


def vram(code, block="kana"):
    return code + (KANA_BASE if block == "kana" else KANJI_BASE)


def from_vram(code):
    """VRAM tile code -> (block, block-relative code)."""
    if code >= KANJI_BASE:
        return "kanji", code - KANJI_BASE
    return "kana", code - KANA_BASE


def lookup_vram(code):
    """VRAM tile code -> character, or None."""
    block, rel = from_vram(code)
    return (KANJI if block == "kanji" else KANA).get(rel)


CHAR_TO_VRAM = {}
for _rel, _ch in KANA.items():
    CHAR_TO_VRAM.setdefault(_ch, vram(_rel, "kana"))
for _rel, _ch in KANJI.items():
    CHAR_TO_VRAM.setdefault(_ch, vram(_rel, "kanji"))
