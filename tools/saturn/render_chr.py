#!/usr/bin/env python3
"""render_chr.py — render a VRAM CHR region to a PNG sheet, for reading a font.

The movelist is drawn from a shared font uploaded to BG3 CHR at match load, and
its tilemap stores raw tile indices — so authoring Saturn's list means knowing
which glyph each index is. That is an eyeball question, hence a sheet.

  render_chr.py <vram.bin> <out.png> [--base 0xC000] [--tiles 256] [--bpp 2]
                [--cols 16] [--scale 3]

Tiles are numbered from `base`, which is the CHR base as a BYTE address (VRAM
word address * 2). Each tile is labelled with its index so a glyph can be read
straight off the sheet.
"""
import argparse
import struct
import zlib
from pathlib import Path

# 3x5 digit/letter strips for the index labels, so the sheet is self-describing
GLYPHS = {
    "0": ("111", "101", "101", "101", "111"), "1": ("010", "110", "010", "010", "111"),
    "2": ("111", "001", "111", "100", "111"), "3": ("111", "001", "111", "001", "111"),
    "4": ("101", "101", "111", "001", "001"), "5": ("111", "100", "111", "001", "111"),
    "6": ("111", "100", "111", "101", "111"), "7": ("111", "001", "010", "010", "010"),
    "8": ("111", "101", "111", "101", "111"), "9": ("111", "101", "111", "001", "111"),
    "A": ("111", "101", "111", "101", "101"), "B": ("110", "101", "110", "101", "110"),
    "C": ("111", "100", "100", "100", "111"), "D": ("110", "101", "101", "101", "110"),
    "E": ("111", "100", "111", "100", "111"), "F": ("111", "100", "111", "100", "100"),
}


from gfxlib import decode_tile, write_png  # noqa: E402  (#95)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("vram")
    ap.add_argument("out")
    ap.add_argument("--base", default="0xC000")
    ap.add_argument("--tiles", type=int, default=256)
    ap.add_argument("--bpp", type=int, default=2)
    ap.add_argument("--cols", type=int, default=16)
    ap.add_argument("--scale", type=int, default=3)
    a = ap.parse_args()
    base, S = int(a.base, 0), a.scale
    data = Path(a.vram).read_bytes()
    tsz = 8 * a.bpp
    rows = (a.tiles + a.cols - 1) // a.cols
    CELL = 8 * S + 10                      # tile + label strip
    W, H = a.cols * CELL, rows * CELL
    img = bytearray(b"\x18\x18\x20" * (W * H))

    def put(x, y, r, g, b):
        if 0 <= x < W and 0 <= y < H:
            o = (y * W + x) * 3
            img[o:o + 3] = bytes((r, g, b))

    # 2bpp palette: transparent / mid / light / white on a dark sheet
    PAL = [(24, 24, 32), (110, 110, 130), (190, 190, 205), (255, 255, 255)]
    for t in range(a.tiles):
        cx, cy = (t % a.cols) * CELL, (t // a.cols) * CELL
        px = decode_tile(data, base + t * tsz, a.bpp)
        for y in range(8):
            for x in range(8):
                c = PAL[px[y][x] % len(PAL)]
                for dy in range(S):
                    for dx in range(S):
                        put(cx + x * S + dx, cy + y * S + dy, *c)
        label = f"{t:02X}"
        for i, ch in enumerate(label):
            for gy, rowbits in enumerate(GLYPHS.get(ch, ("000",) * 5)):
                for gx, bit in enumerate(rowbits):
                    if bit == "1":
                        put(cx + 1 + i * 4 + gx, cy + 8 * S + 2 + gy, 255, 210, 80)
    write_png(a.out, W, H, img)
    print(f"{a.out}: {a.tiles} tiles from {a.base} ({a.bpp}bpp), {W}x{H}")


if __name__ == "__main__":
    main()
