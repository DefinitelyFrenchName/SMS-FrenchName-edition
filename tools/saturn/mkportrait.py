#!/usr/bin/env python3
"""mkportrait.py — convert a 1:1 screen capture into SMS report-card portrait tiles.

The card's portrait is NOT a background image: it is a fixed composition of 31
SPRITES (16x16 and 8x8) at hard-coded screen positions using OBJ tiles
`$00-$43` and OBJ palette 0 (CGRAM row 8). The composition is identical for
every character — only the tile pixels and the palette change. So porting
Saturn's portrait means:

  1. read that composition out of a real card frame (OAM + the OBJ tile base),
  2. sample the supplied capture at each sprite's screen rectangle,
  3. quantise the sampled pixels to 16 colours,
  4. emit 4bpp tiles at the SAME tile numbers plus the palette.

`--render` re-draws the composition from a VRAM/OAM/CGRAM dump so the pipeline
can be validated against a known-good frame before trusting it on new art.

Usage:
  mkportrait.py --render  traces/saturn/vramcard_ur.bin traces/saturn/oamcard_oam.bin \\
                          traces/saturn/cgcard_v6.bin  out.png
  mkportrait.py --convert mockups/saturn_win.png traces/saturn/oamcard_oam.bin \\
                          build/saturn/portrait_saturn.bin build/saturn/portrait_saturn.pal
"""
import sys
from pathlib import Path

TILE_MAX = 0x43          # portrait occupies OBJ tiles $00-$43
OBJ_ROW = 16             # OBJ tiles are addressed in a 16-wide grid


def read_oam(path):
    """-> [(x, y, tile, attr, is16)] for the portrait sprites only."""
    o = Path(path).read_bytes()
    out = []
    for i in range(128):
        x, y, t, a = o[i * 4], o[i * 4 + 1], o[i * 4 + 2], o[i * 4 + 3]
        hb = o[512 + i // 4]
        bits = (hb >> ((i % 4) * 2)) & 3
        if y < 0xE0 and t <= TILE_MAX and (a & 0x01) == 0:
            out.append((x + (0x100 if bits & 1 else 0), y, t, a, bool(bits & 2)))
    return out


def tile_pixels(vram, tile):
    """4bpp SNES tile -> 8x8 palette indices."""
    base = tile * 32
    px = [[0] * 8 for _ in range(8)]
    for row in range(8):
        p0, p1 = vram[base + row * 2], vram[base + row * 2 + 1]
        p2, p3 = vram[base + 16 + row * 2], vram[base + 16 + row * 2 + 1]
        for col in range(8):
            bit = 7 - col
            px[row][col] = (((p0 >> bit) & 1) | (((p1 >> bit) & 1) << 1)
                            | (((p2 >> bit) & 1) << 2) | (((p3 >> bit) & 1) << 3))
    return px


def pack_tile(px):
    """8x8 palette indices -> 32-byte 4bpp SNES tile."""
    out = bytearray(32)
    for row in range(8):
        p0 = p1 = p2 = p3 = 0
        for col in range(8):
            v = px[row][col] & 0x0F
            bit = 7 - col
            p0 |= (v & 1) << bit
            p1 |= ((v >> 1) & 1) << bit
            p2 |= ((v >> 2) & 1) << bit
            p3 |= ((v >> 3) & 1) << bit
        out[row * 2], out[row * 2 + 1] = p0, p1
        out[16 + row * 2], out[16 + row * 2 + 1] = p2, p3
    return bytes(out)


def sprite_tiles(t, is16):
    """Tile numbers making up a sprite, as (dx, dy, tile) in 8px units."""
    if not is16:
        return [(0, 0, t)]
    return [(0, 0, t), (8, 0, t + 1), (0, 8, t + OBJ_ROW), (8, 8, t + OBJ_ROW + 1)]


def snes_to_rgb(w):
    r, g, b = w & 0x1F, (w >> 5) & 0x1F, (w >> 10) & 0x1F
    return (r * 255 // 31, g * 255 // 31, b * 255 // 31)


def rgb_to_snes(c):
    r, g, b = (min(255, max(0, v)) * 31 // 255 for v in c[:3])
    return r | (g << 5) | (b << 10)


def cmd_render(vram_path, oam_path, cg_path, out_path):
    from PIL import Image
    vram = Path(vram_path).read_bytes()
    cg = Path(cg_path).read_bytes()
    pal = [snes_to_rgb(cg[256 + 2 * i] | cg[257 + 2 * i] << 8) for i in range(16)]
    img = Image.new("RGB", (256, 224), (255, 0, 255))
    px = img.load()
    for x, y, t, a, is16 in read_oam(oam_path):
        flipx, flipy = bool(a & 0x40), bool(a & 0x80)
        size = 16 if is16 else 8
        for dx, dy, tn in sprite_tiles(t, is16):
            tp = tile_pixels(vram, tn)
            for r in range(8):
                for c in range(8):
                    v = tp[r][c]
                    if v == 0:
                        continue
                    ox, oy = dx + c, dy + r
                    if flipx:
                        ox = size - 1 - ox
                    if flipy:
                        oy = size - 1 - oy
                    sx, sy = x + ox, y + oy
                    if 0 <= sx < 256 and 0 <= sy < 224:
                        px[sx, sy] = pal[v]
    img.save(out_path)
    print(f"rendered {out_path} from {len(read_oam(oam_path))} sprites")


def coverage(sprites):
    """Screen pixels the composition actually draws, as {(x, y): (tile, r, c)}."""
    cov = {}
    for x, y, t, a, is16 in sprites:
        flipx, flipy = bool(a & 0x40), bool(a & 0x80)
        size = 16 if is16 else 8
        for dx, dy, tn in sprite_tiles(t, is16):
            for r in range(8):
                for c in range(8):
                    ox, oy = dx + c, dy + r
                    if flipx:
                        ox = size - 1 - ox
                    if flipy:
                        oy = size - 1 - oy
                    cov[(x + ox, y + oy)] = (tn, r, c)
    return cov


def best_offset(img, cov, span=8):
    """Slide the composition over the capture and keep the offset that captures
    the most of the figure. The card background is a light patterned lilac, so
    "not the background colour" is a useless cue (it counts the pattern); the
    reliable signal is DARK pixels — her hair, outline and glaive shaft."""
    src = img.load()
    w, h = img.size
    best, bestoff = -1, (0, 0)
    for dy in range(-span, span + 1):
        for dx in range(-span, span + 1):
            n = 0
            for (x, y) in cov:
                sx, sy = x + dx, y + dy
                if 0 <= sx < w and 0 <= sy < h and sum(src[sx, sy]) < 240:
                    n += 1
            if n > best:
                best, bestoff = n, (dx, dy)
    return bestoff, best, None


def cmd_convert(cap_path, oam_path, tiles_out, pal_out, offset="0,0"):
    from PIL import Image
    img = Image.open(cap_path).convert("RGB")
    src = img.load()
    sprites = read_oam(oam_path)
    # Both games draw the card portrait at the SAME screen position, so the
    # default sampling offset is none. (An auto-align pass was tried and
    # rejected: the card's patterned lilac background defeats a
    # "not-background" cue, and a dark-pixel cue drags the frame onto her hair.)
    odx, ody = (int(v) for v in offset.split(","))
    if (odx, ody) != (0, 0):
        print(f"sampling offset ({odx:+d},{ody:+d})")
    # 1) collect every pixel the composition will actually show
    samples = {}
    for x, y, t, a, is16 in sprites:
        flipx, flipy = bool(a & 0x40), bool(a & 0x80)
        size = 16 if is16 else 8
        for dx, dy, tn in sprite_tiles(t, is16):
            for r in range(8):
                for c in range(8):
                    ox, oy = dx + c, dy + r
                    if flipx:
                        ox = size - 1 - ox
                    if flipy:
                        oy = size - 1 - oy
                    sx, sy = x + ox + odx, y + oy + ody
                    if 0 <= sx < img.size[0] and 0 <= sy < img.size[1]:
                        samples[(tn, r, c)] = src[sx, sy]
    # 2) build a 16-colour palette: index 0 must be the transparent/background
    #    colour (the most common one along the composition's outer edge)
    from collections import Counter
    counts = Counter(samples.values())
    edge = Counter()
    for (tn, r, c), col in samples.items():
        if r in (0, 7) or c in (0, 7):
            edge[col] += 1
    bg = edge.most_common(1)[0][0]
    palette = [bg] + [c for c, _ in counts.most_common() if c != bg][:15]
    while len(palette) < 16:
        palette.append((0, 0, 0))

    def nearest(col):
        if col == bg:
            return 0
        best, bi = None, 1
        for i, p in enumerate(palette):
            if i == 0:
                continue
            d = sum((a - b) ** 2 for a, b in zip(col, p))
            if best is None or d < best:
                best, bi = d, i
        return bi

    # 3) emit tiles
    tiles = bytearray(32 * (TILE_MAX + 1 + OBJ_ROW))
    for tn in sorted({k[0] for k in samples}):
        grid = [[0] * 8 for _ in range(8)]
        for r in range(8):
            for c in range(8):
                col = samples.get((tn, r, c))
                grid[r][c] = nearest(col) if col is not None else 0
        tiles[tn * 32:tn * 32 + 32] = pack_tile(grid)
    Path(tiles_out).write_bytes(bytes(tiles))
    pal_bytes = bytearray()
    for c in palette:
        w = rgb_to_snes(c)
        pal_bytes += bytes((w & 0xFF, w >> 8))
    Path(pal_out).write_bytes(bytes(pal_bytes))
    used = len({c for c in samples.values()})
    print(f"wrote {tiles_out} ({len(tiles)} B) and {pal_out}; "
          f"{used} distinct colours in the capture -> 16 (bg {bg})")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    if sys.argv[1] == "--render":
        cmd_render(*sys.argv[2:6])
    elif sys.argv[1] == "--convert":
        cmd_convert(*sys.argv[2:7])
    else:
        raise SystemExit(__doc__)
