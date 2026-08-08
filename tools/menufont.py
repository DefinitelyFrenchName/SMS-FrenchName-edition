#!/usr/bin/env python3
"""menufont.py — the menu font, as data: compose its 16x16 glyphs and render a
labelled contact sheet so the code -> character table can be read off and fixed.

Why this exists: docs/project/saturn/movelist.md records "Still missing: the code -> glyph
table", and every part of patch 16 (menu translation) needs it — you cannot
inventory a screen's strings, budget a translation, or author a replacement
without knowing which glyph code draws which character. This builds it once.

Layout (verified by rendering, see GLYPH_STRIDE below): a menu glyph is 16x16 =
2x2 tiles, stored as FOUR CONSECUTIVE tiles — code+0,+1 = top row, code+2,+3 =
bottom row. The 21 Latin capitals at $20A..$25E followed immediately by the
button labels at $264 is the check that pins it: 21 glyphs x 4 tiles = $54.

Source of the tiles: a live VRAM capture (tools/probe_menu_survey.lua writes
traces/menu/<TAG>_<frame>.chr, 64 KB) — the doc's glyph codes are VRAM tile
indices, so the capture is the natural coordinate system. The same font also
lives in ROM as two compressed blocks ($C3:48D0 kana, $C7:07F0 kanji, both
round-trip through tools/saturn/sms_lz.py) for when the patch has to WRITE it.

  python3 tools/menufont.py sheet --lo 0x200 --hi 0x400 --out /tmp/sheet.png
  python3 tools/menufont.py blanks            # which slots are free for new glyphs

NOTE: the rendered sheet is game art — keep it local, never commit it (.gitignore
blocks images repo-wide). The derived TABLE is ours and is committed.
"""
import argparse
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "tools"))

TILE_BYTES = 32          # 4bpp
# A 16x16 glyph is 2x2 tiles laid out in a SHEET that is SHEET_W tiles wide:
#   top row  = code, code+1
#   bottom   = code+SHEET_W, code+SHEET_W+1
# NOT four consecutive tiles — that was the first guess and it renders each cell
# as the TOP halves of two adjacent glyphs stacked, which is what the first sheet
# showed. Glyph codes therefore advance by 2 along a row and by 2*SHEET_W a line.
SHEET_W = 16
GLYPH_STRIDE = 2
DEFAULT_CHR = os.path.join(REPO, "traces", "menu", "cfg_1200.chr")


def load_rom_font(which="kana"):
    """The font as it lives in ROM: two compressed blocks that round-trip through
    sms_lz. This is the unambiguous source — a VRAM capture depends on where the
    screen happened to upload the sheet, which is NOT tile 0 (rendering $200+
    from a capture gives noise)."""
    sys.path.insert(0, os.path.join(REPO, "tools", "saturn"))
    import sms_lz
    from smspaths import clean_rom
    src = {"kana": 0x0348D0, "kanji": 0x0707F0}[which] & 0x3FFFFF
    with open(clean_rom(), "rb") as f:
        return sms_lz.decompress(f.read(), src)


def load_chr(path=None):
    path = path or DEFAULT_CHR
    if not os.path.exists(path):
        raise SystemExit(
            f"menufont: no VRAM capture at {path}\n"
            f"  make one:  TAG=cfg EVERY=1200 UNTIL=1200 ROM=<rom> "
            f"tools/run.sh tools/probe_menu_survey.lua 300")
    with open(path, "rb") as f:
        return f.read()


def tile_pixels(chr_data, index):
    """4bpp SNES tile -> 8x8 list of rows of 0-15."""
    base = index * TILE_BYTES
    if base + TILE_BYTES > len(chr_data):
        return [[0] * 8 for _ in range(8)]
    rows = []
    for y in range(8):
        p0 = chr_data[base + y * 2]
        p1 = chr_data[base + y * 2 + 1]
        p2 = chr_data[base + 16 + y * 2]
        p3 = chr_data[base + 16 + y * 2 + 1]
        row = []
        for x in range(8):
            bit = 7 - x
            row.append(((p0 >> bit) & 1) | (((p1 >> bit) & 1) << 1)
                       | (((p2 >> bit) & 1) << 2) | (((p3 >> bit) & 1) << 3))
        rows.append(row)
    return rows


def glyph_pixels(chr_data, code):
    """16x16 pixels for the glyph whose top-left tile is `code`."""
    tl = tile_pixels(chr_data, code)
    tr = tile_pixels(chr_data, code + 1)
    bl = tile_pixels(chr_data, code + SHEET_W)
    br = tile_pixels(chr_data, code + SHEET_W + 1)
    return [tl[y] + tr[y] for y in range(8)] + [bl[y] + br[y] for y in range(8)]


def glyph_codes(lo, hi):
    """Every glyph top-left tile in [lo,hi): 2 along a row, skipping the row that
    holds the bottom halves."""
    out = []
    for code in range(lo, hi, GLYPH_STRIDE):
        if (code // SHEET_W) % 2 == 0:      # even tile-rows start glyphs
            out.append(code)
    return out


def is_blank(chr_data, code):
    return not any(any(r) for r in glyph_pixels(chr_data, code))


def render_sheet(chr_data, lo, hi, out_path, cols=16, scale=3):
    """Contact sheet of every glyph in [lo, hi), labelled with its code."""
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        raise SystemExit("menufont: needs Pillow for `sheet` (pip3 install Pillow)")
    codes = glyph_codes(lo, hi)
    gw = 16 * scale
    cell_w, cell_h, pad = gw, gw + 10, 4
    rows = (len(codes) + cols - 1) // cols
    img = Image.new("RGB", (cols * (cell_w + pad) + pad, rows * (cell_h + pad) + pad),
                    (24, 24, 32))
    d = ImageDraw.Draw(img)
    for n, code in enumerate(codes):
        cx = pad + (n % cols) * (cell_w + pad)
        cy = pad + (n // cols) * (cell_h + pad)
        px = glyph_pixels(chr_data, code)
        for y in range(16):
            for x in range(16):
                v = px[y][x]
                if v:
                    g = 40 + v * 14
                    for sy in range(scale):
                        for sx in range(scale):
                            img.putpixel((cx + x * scale + sx, cy + 10 + y * scale + sy),
                                         (g, g, g))
        d.text((cx, cy), f"{code:03X}", fill=(150, 190, 255))
    img.save(out_path)
    return len(codes), out_path


def decode_map(src):
    """Decode a compressed screen tilemap and print it as text, with the cell
    budget of every string — the number a translator actually needs.

    Two alignment facts, both found the hard way:
      * glyph rows start at map row 1, not 0 (row 0 holds bottom halves);
      * a screen MIXES alignments — full-width 16x16 text sits on the even
        column grid, but the button-label glyphs sit one tile to the left, so a
        fixed even-column read shows their right halves as unmapped codes.
    So columns are scanned singly and a run is closed on a blank cell.
    """
    sys.path.insert(0, os.path.join(REPO, "tools", "saturn"))
    import sms_lz
    import menufont_table as T
    from smspaths import clean_rom
    m = sms_lz.decompress(open(clean_rom(), "rb").read(), src)
    W = 32
    def word(x, y):
        o = (y * W + x) * 2
        return (m[o] | (m[o + 1] << 8)) & 0x3FF
    print(f"tilemap ${src:06X} -> {len(m):#x} bytes\n")
    print("row  col  cells  text")
    for gy in range(1, 32, 2):
        run, start = [], None
        for gx in range(0, 32):
            t = word(gx, gy)
            ch = T.lookup_vram(t) if t else None
            if t and ch:
                if start is None:
                    start = gx
                run.append(ch)
            elif t == 0 and run:
                print(f"{gy:3d} {start:4d} {len(run):6d}  {''.join(run)}")
                run, start = [], None
        if run:
            print(f"{gy:3d} {start:4d} {len(run):6d}  {''.join(run)}")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=("sheet", "blanks", "decode-map"))
    ap.add_argument("--map", type=lambda s: int(s, 0), default=0x037C00,
                    help="file offset of a compressed 0x800 tilemap (default: "
                         "the VS button-config screen at $C3:7C00)")
    ap.add_argument("--chr", default=None, help="VRAM capture (default: traces/menu/cfg_1200.chr)")
    ap.add_argument("--lo", type=lambda s: int(s, 0), default=0x200)
    ap.add_argument("--hi", type=lambda s: int(s, 0), default=0x400)
    ap.add_argument("--out", default="/tmp/menufont_sheet.png")
    ap.add_argument("--src", choices=("chr", "kana", "kanji"), default="chr")
    ap.add_argument("--cols", type=int, default=16)
    ap.add_argument("--scale", type=int, default=3)
    a = ap.parse_args()
    if a.cmd == "decode-map":
        return decode_map(a.map)
    chr_data = load_chr(a.chr) if a.src == "chr" else load_rom_font(a.src)

    if a.cmd == "sheet":
        n, p = render_sheet(chr_data, a.lo, a.hi, a.out, cols=a.cols, scale=a.scale)
        print(f"rendered {n} glyphs (${a.lo:03X}..${a.hi:03X}) -> {p}")
        return

    runs, start = [], None
    for code in glyph_codes(a.lo, a.hi):
        if is_blank(chr_data, code):
            if start is None:
                start = code
        else:
            if start is not None:
                runs.append((start, code - GLYPH_STRIDE)); start = None
    if start is not None:
        runs.append((start, a.hi - GLYPH_STRIDE))
    total = 0
    print(f"blank 16x16 glyph slots in ${a.lo:03X}..${a.hi:03X}:")
    for lo, hi in runs:
        n = len(glyph_codes(lo, hi + GLYPH_STRIDE))
        total += n
        print(f"  ${lo:03X}..${hi:03X}   {n} slot(s)")
    print(f"  TOTAL: {total} free 16x16 slots")


if __name__ == "__main__":
    main()
