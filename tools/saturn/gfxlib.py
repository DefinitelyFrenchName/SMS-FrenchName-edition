"""gfxlib.py — the Saturn image tools' shared graphics primitives (#95).

Four renderers each re-implemented SNES colour conversion, planar tile
decoding and PNG emission; a colour-maths fix had to be made in up to four
places. The primitives live here once; layout/CLI stays per-tool.

All functions are verbatim moves — the #95 refactor was gated on a property
test proving old and new agree over the full 15-bit colour domain, random
tiles (2bpp/4bpp, in- and out-of-bounds) and identical PNG bytes.
"""
import struct
import zlib
from pathlib import Path


def snes_to_rgb(w):
    """15-bit BGR word -> (r, g, b) 0..255."""
    return (((w & 0x1F) * 255) // 31, (((w >> 5) & 0x1F) * 255) // 31,
            (((w >> 10) & 0x1F) * 255) // 31)


def rgb_to_snes(c):
    """(r, g, b) 0..255 (clamped) -> 15-bit BGR word."""
    r, g, b = (min(255, max(0, v)) * 31 // 255 for v in c[:3])
    return r | (g << 5) | (b << 10)


def decode_tile(data, off, bpp=2):
    """Planar SNES tile at byte offset `off` -> 8x8 list of palette indices.

    bpp 2 or 4 (plane pairs at off, off+16). Out-of-range access raises
    IndexError — callers wanting blank-on-OOB check bounds themselves."""
    px = [[0] * 8 for _ in range(8)]
    for plane in range(0, bpp, 2):
        base = off + plane * 8
        for y in range(8):
            lo, hi = data[base + y * 2], data[base + y * 2 + 1]
            for x in range(8):
                bit = 7 - x
                v = ((lo >> bit) & 1) | (((hi >> bit) & 1) << 1)
                px[y][x] |= v << plane
    return px


def tm_entry(v):
    """BG tilemap word -> (tile, palette, hflip, vflip)."""
    return v & 0x3FF, (v >> 10) & 7, bool(v & 0x4000), bool(v & 0x8000)


def write_png(path, w, h, rgb):
    """Write an 8-bit RGB PNG from a flat [r,g,b,...] list (no PIL needed)."""
    raw = b"".join(b"\x00" + bytes(rgb[y * w * 3:(y + 1) * w * 3]) for y in range(h))

    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))
    Path(path).write_bytes(b"\x89PNG\r\n\x1a\n"
                           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                           + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
