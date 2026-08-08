#!/usr/bin/env python3
"""mkmovelist.py — build Saturn's movelist tilemap and compress it.

SMS draws a character's movelist from a compressed 0x800-byte BG3 tilemap chosen
by `$E0:021A + charID*3`. Super S does not share the format, so hers is authored
here from SMS's own font and encoded with tools/saturn/sms_lz.py.

Everything below was measured, not guessed (docs/project/saturn/movelist.md):

  * text is 8x16 — every line is two tile rows, the lower tile always +0x10;
  * the title uses palette 5 (attribute byte $34), body text palette 3 ($0D);
  * roman caps are a reduced alphabet at $090 (A-J, L-P, R) and $0B0 (S-W, Y, !)
    — there is no K, Q, X or Z, which is fine for SAILOR SATURN;
  * katakana are gojuon-ordered: code = $100 + (i//16)*$20 + (i%16);
  * the dakuten/handakuten set is REDUCED (only what the game uses) and the
    small kana are ィェャュョッー at $180-$186;
  * input icons are 2 tiles wide, and the arrow set is only ⬇ ↘ ➡ — left and up
    are the same glyphs FLIPPED, which for a 2-tile glyph also swaps the halves.

Base: Moon's list, because she is the only vanilla character with three moves,
so her frame and row positions already fit Saturn. Only the text rows are
rewritten; the title's right-hand 右向きの時 line is left exactly as it is,
since it is identical for all nine.
"""
import argparse
import importlib.util
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO / "tools"))
from smspaths import clean_rom                                        # noqa: E402

_spec = importlib.util.spec_from_file_location("sms_lz", REPO / "tools" / "saturn" / "sms_lz.py")
sms_lz = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(sms_lz)

MOVELIST_TABLE = 0x20021A          # file offset of $E0:021A; entry = +charID*3
BASE_CHAR = 1                      # Moon — the only vanilla list with three moves

ATTR_TITLE = 0x34                  # palette 5, priority
# Palette 3 AND PRIORITY. The priority bit is not cosmetic here: $2105 has the
# mode-1 BG3-priority bit set, so a BG3 tile WITHOUT priority renders behind the
# stage and is invisible on any bright background. Dropping it produced a
# movelist whose title showed and whose body did not.
ATTR_BODY = 0x2D                   # palette 3, priority

ROMAN = {c: 0x090 + i for i, c in enumerate("ABCDEFGHIJ")}
ROMAN.update({c: 0x09A + i for i, c in enumerate("LMNOP")})
ROMAN["R"] = 0x09F
ROMAN.update({c: 0x0B0 + i for i, c in enumerate("STUVW")})
ROMAN["Y"], ROMAN["!"] = 0x0B5, 0x0B6

_GOJUON = ("アイウエオカキクケコサシスセソタチツテトナニヌネノ"
           "ハヒフヘホマミムメモヤユヨラリルレロワヲン")
KANA = {c: 0x100 + (i // 16) * 0x20 + (i % 16) for i, c in enumerate(_GOJUON)}
# the reduced dakuten/handakuten set, read off the font sheet and cross-checked
# against vanilla text (グ from キング, ド from ワールド, パ from スパイラル)
KANA.update({"ガ": 0x14E, "グ": 0x14F, "ゴ": 0x160, "ジ": 0x161, "ズ": 0x162,
             "ダ": 0x163, "デ": 0x164, "ド": 0x165, "バ": 0x166, "ビ": 0x167,
             "ブ": 0x168, "ボ": 0x169, "パ": 0x16A, "ピ": 0x16B, "プ": 0x16C})
KANA.update({"ィ": 0x180, "ェ": 0x181, "ャ": 0x182, "ュ": 0x183, "ョ": 0x184,
             "ッ": 0x185, "ー": 0x186})

ICON = {"down": 0x1A4, "dnfwd": 0x1A6, "fwd": 0x1A8, "plus": 0x1AA,
        "naka": 0x1A0, "ju": 0x1AC, "mp": 0x1AE,
        "K": 0x1C6, "k": 0x1C0, "P": 0x1C4, "p": 0x1C2, "or": 0x1CA}


def word(tile, attr, xflip=False, yflip=False):
    return (tile & 0x3FF) | (attr << 8) | (0x4000 if xflip else 0) | (0x8000 if yflip else 0)


class Map:
    """A 32x32 tilemap, addressed in rows; writes lay down both halves of the
    8x16 text automatically."""

    def __init__(self, data):
        self.d = bytearray(data)

    def put(self, row, col, w):
        o = (row * 32 + col) * 2
        self.d[o] = w & 0xFF
        self.d[o + 1] = w >> 8

    def clear(self, row, c0=0, c1=32):
        for r in (row, row + 1):
            for c in range(c0, c1):
                self.put(r, c, 0)

    def text(self, row, col, s, attr):
        """One line of 8x16 text; unknown characters raise rather than render junk."""
        for ch in s:
            if ch == " ":
                col += 1
                continue
            t = ROMAN.get(ch) if attr == ATTR_TITLE else KANA.get(ch)
            if t is None:
                raise SystemExit(f"no glyph for {ch!r} — check the font tables")
            self.put(row, col, word(t, attr))
            self.put(row + 1, col, word(t + 0x10, attr))
            col += 1
        return col

    def icon(self, row, col, name, xflip=False, yflip=False):
        """A 2-tile-wide, 2-row-tall icon. Flipping one also swaps its halves —
        horizontally the two columns exchange, vertically the two rows do."""
        c = ICON[name]
        top = (c + 0x10, c + 0x11) if yflip else (c, c + 1)
        bot = (c, c + 1) if yflip else (c + 0x10, c + 0x11)
        if xflip:
            top, bot = (top[1], top[0]), (bot[1], bot[0])
        for i in (0, 1):
            self.put(row, col + i, word(top[i], ATTR_BODY, xflip, yflip))
            self.put(row + 1, col + i, word(bot[i], ATTR_BODY, xflip, yflip))
        return col + 2

    def motion(self, row, col, seq, button):
        """seq: numpad digits from {2,3,6,4,1,8}. button: 'P' or 'K'."""
        ARROW = {"2": ("down", False, False), "3": ("dnfwd", False, False),
                 "6": ("fwd", False, False), "1": ("dnfwd", True, False),
                 "4": ("fwd", True, False), "8": ("down", False, True)}
        for ch in seq:
            nm, xf, yf = ARROW[ch]
            col = self.icon(row, col, nm, xf, yf)
        col = self.icon(row, col, "plus")
        col = self.icon(row, col, button)                 # strong version
        col = self.icon(row, col, "or")
        col = self.icon(row, col, button.lower())         # weak version
        return col


def build():
    rom = Path(clean_rom()).read_bytes()
    o = MOVELIST_TABLE + BASE_CHAR * 3
    ptr = rom[o] | rom[o + 1] << 8 | rom[o + 2] << 16
    m = Map(sms_lz.decompress(rom, ptr & 0x3FFFFF, 0x800))

    # title: replace the name only, leaving the 右向きの時 line untouched
    m.clear(5, 0, 20)
    m.text(5, 3, "SAILORSATURN", ATTR_TITLE)

    rows = [
        (9, "サイレンス バスター", "236", "P", None),
        (13, "プレス クラッシャー", "632", "K", "jump"),
        (17, "デス リボン レボリューション", "214", "P", None),
    ]
    for row, name, seq, button, prefix in rows:
        m.clear(row, 0, 32)
        m.text(row, 3, name, ATTR_BODY)
        m.clear(row + 2, 0, 32)
        col = 5
        if prefix == "jump":
            col = m.icon(row + 2, col, "ju")
            col = m.icon(row + 2, col, "mp")
            col = m.icon(row + 2, col, "naka")
        m.motion(row + 2, col, seq, button)
    return bytes(m.d)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(REPO / "build" / "saturn" / "saturn_movelist.bin"))
    ap.add_argument("--raw", help="also write the uncompressed tilemap here")
    a = ap.parse_args()
    tm = build()
    enc = sms_lz.encode(tm)
    back = sms_lz.decompress(enc, 0, 0x800)
    if back != tm:
        raise SystemExit("round-trip failed — the encoder and tilemap disagree")
    out = Path(a.out); out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(enc)
    if a.raw:
        Path(a.raw).write_bytes(tm)
    print(f"wrote {out}: {len(enc)} bytes compressed (0x800 expanded, round-trip OK)")


if __name__ == "__main__":
    main()
