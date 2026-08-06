#!/usr/bin/env python3
"""Render a SNES BG layer (4bpp tiles + tilemap) to a PNG.

Used to identify stages offline: both games store a stage as
[tileset -> VRAM $2000, tilemap -> $0000, tilemap -> $0800], so a decompressed
triplet can be drawn without booting anything. Colours are a grey ramp unless a
palette dump is supplied — enough to recognise a stage by shape.

  render_stage.py <tiles.bin> <map.bin> <out.png> [pal.bin] [tilebase]

`tilebase` is the VRAM word address the tileset was uploaded to (default $2000),
because tilemap entries index tiles from VRAM $0000.
"""
import sys
from pathlib import Path


import sys as _sys
_sys.path.insert(0, str(Path(__file__).resolve().parent))
from gfxlib import decode_tile, snes_to_rgb, tm_entry  # noqa: E402  (#95)


def tile_pixels(data, idx):
    """4bpp SNES tile -> 8x8 of palette indices (blank when out of range)."""
    o = idx * 32
    if idx < 0 or o + 32 > len(data):
        return [[0] * 8 for _ in range(8)]
    return decode_tile(data, o, 4)


def render(tiles, tmap, pal=None, tilebase=0x2000, cols=64, rows=32):
    from PIL import Image
    img = Image.new("RGB", (cols * 8, rows * 8), (0, 0, 0))
    px = img.load()
    # tilemap entries index VRAM from 0; our tileset starts at `tilebase` words
    # = tilebase/16 tiles (a 4bpp tile is 16 words).
    first = tilebase // 16
    for r in range(rows):
        for c in range(cols):
            e = r * cols + c
            if e * 2 + 1 >= len(tmap):
                continue
            v = tmap[e * 2] | (tmap[e * 2 + 1] << 8)
            t, p, hf, vf = tm_entry(v)
            grid = tile_pixels(tiles, t - first)
            for y in range(8):
                for x in range(8):
                    val = grid[7 - y if vf else y][7 - x if hf else x]
                    if pal:
                        i = (p * 16 + val) * 2
                        col = snes_to_rgb(pal[i] | (pal[i + 1] << 8)) if i + 1 < len(pal) else (0, 0, 0)
                    else:
                        col = (val * 17,) * 3
                    px[c * 8 + x, r * 8 + y] = col
    return img


if __name__ == "__main__":
    tiles = Path(sys.argv[1]).read_bytes()
    tmap = Path(sys.argv[2]).read_bytes()
    pal = Path(sys.argv[4]).read_bytes() if len(sys.argv) > 4 and sys.argv[4] != "-" else None
    base = int(sys.argv[5], 0) if len(sys.argv) > 5 else 0x2000
    render(tiles, tmap, pal, base).save(sys.argv[3])
    print("wrote", sys.argv[3])
