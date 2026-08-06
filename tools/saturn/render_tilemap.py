#!/usr/bin/env python3
"""render_tilemap.py — draw a BG tilemap with a CHR set, as a PNG.

Written for the movelist work: authoring Saturn's list means writing tile codes,
and the only trustworthy check that a code is the glyph you meant is to render
the result and read it. Validating the renderer is easy — draw a vanilla
character's decoded tilemap and compare with a screenshot of the real screen.

  render_tilemap.py <tilemap.bin> <vram.bin> <out.png> [--chr 0xA000]
                    [--rows 20] [--scale 2]

The tilemap is standard SNES: 32 entries per row, little-endian words, bits 0-9
tile, 10-12 palette, 13 priority, 14-15 flips. Palettes are drawn as flat greys
per palette index, which is enough to tell the title font (palette 5) from the
body text (palette 3).
"""
import argparse
import struct
import zlib
from pathlib import Path


from gfxlib import decode_tile, write_png  # noqa: E402  (#95)


# one flat colour ramp per palette, so palette differences are visible
RAMPS = {
    3: [(16, 16, 24), (90, 90, 120), (185, 185, 205), (255, 255, 255)],
    5: [(16, 16, 24), (120, 95, 60), (215, 175, 95), (255, 240, 200)],
}
DEFAULT = [(16, 16, 24), (80, 80, 80), (160, 160, 160), (230, 230, 230)]


def render(tilemap, vram, chrbase, rows, scale, cols=32):
    W, H = cols * 8 * scale, rows * 8 * scale
    img = bytearray(b"\x0c\x0c\x14" * (W * H))
    for r in range(rows):
        for c in range(cols):
            o = (r * 32 + c) * 2
            if o + 1 >= len(tilemap):
                continue
            w = tilemap[o] | tilemap[o + 1] << 8
            tile, pal = w & 0x3FF, (w >> 10) & 7
            xf, yf = (w >> 14) & 1, (w >> 15) & 1
            px = decode_tile(vram, chrbase + tile * 16)
            ramp = RAMPS.get(pal, DEFAULT)
            for y in range(8):
                for x in range(8):
                    v = px[7 - y if yf else y][7 - x if xf else x]
                    if v == 0:
                        continue
                    col = ramp[v]
                    for dy in range(scale):
                        for dx in range(scale):
                            X, Y = (c * 8 + x) * scale + dx, (r * 8 + y) * scale + dy
                            if 0 <= X < W and 0 <= Y < H:
                                p = (Y * W + X) * 3
                                img[p:p + 3] = bytes(col)
    return W, H, img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tilemap"); ap.add_argument("vram"); ap.add_argument("out")
    ap.add_argument("--chr", default="0xA000")
    ap.add_argument("--rows", type=int, default=20)
    ap.add_argument("--scale", type=int, default=2)
    a = ap.parse_args()
    tm = Path(a.tilemap).read_bytes()
    vr = Path(a.vram).read_bytes()
    W, H, img = render(tm, vr, int(a.chr, 0), a.rows, a.scale)
    write_png(a.out, W, H, img)
    print(f"{a.out}: {W}x{H}, {a.rows} rows, CHR base {a.chr}")


if __name__ == "__main__":
    main()
