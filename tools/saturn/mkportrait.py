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


# ---- custom composition for Saturn (capture -> list + tiles + palette) -------
# Measured from mockups/saturn_win.png (a 1:1 Super S report card): her portrait
# occupies x 8..96, y 40..120 — BIGGER than SMS's vanilla box (x 19..90,
# y 48..120), which is why squeezing her through Uranus's 31-sprite silhouette
# clipped the lower-left of her face/hair and the Y of the glaive. We keep the
# Super S screen coordinates 1:1 (both games' cards share the layout) and build
# her own list out of 8x8 sprites: 8x8 needs no tile-grid alignment, so only
# cells that actually contain art cost a sprite AND a tile.
CARD_RECT = (8, 40, 96, 120)       # x0, y0, x1, y1 in capture coordinates
ANCHOR_X, ANCHOR_Y = 0x34, 0x78    # the portrait object's +0x28/+0x2A at the card
# Attr byte semantics (emitter $C0:9BCB): record bytes[4..5] form `attr<<8|tile`;
# bit $0800 (attr bit 3) is a SIZE flag the emitter consumes (it sets the OAM
# high-table size bit) and strips before adding the caller's base ($3000 =
# priority 3, palette 0). Vanilla uses $48 = H-flip + 16x16; ours are 8x8 -> $40.
LIST_ATTR = 0x40
MAX_SPRITES = 110                  # OAM cursor stops at 128 ($C0:9C63)
MAX_TILES = 128                    # P2's portrait starts at tile 128


def bg_colors(px, w, h):
    """The card background is a PATTERN (a lavender heart/lace motif), not a flat
    colour, so 'transparent' is a colour SET learned from clean strips."""
    s = set()
    for y in range(40, min(128, h)):
        for x in range(150, w):
            s.add(px[x, y])
        for x in range(0, 6):
            s.add(px[x, y])
    return s


def opaque_mask(px, bg, rect, size, pad=12):
    """Flood-fill the background inward from the border. Doing it by connectivity
    (rather than 'colour is in the bg set') keeps pixels INSIDE her that happen
    to share a colour with the pattern — no speckled holes. The fill runs on a
    PADDED rect: seeded from the tight crop border alone it cannot reach lace
    motifs that touch the crop edge, and those leaked in as stray blobs."""
    W_IMG, H_IMG = size
    rx0, ry0, rx1, ry1 = rect
    x0, y0 = max(0, rx0 - pad), max(0, ry0 - pad)
    x1, y1 = min(W_IMG, rx1 + pad), min(H_IMG, ry1 + pad)
    W, H = x1 - x0, y1 - y0
    trans = [[False] * W for _ in range(H)]
    stack = []
    for x in range(W):
        for y in (0, H - 1):
            if px[x0 + x, y0 + y] in bg:
                stack.append((x, y))
    for y in range(H):
        for x in (0, W - 1):
            if px[x0 + x, y0 + y] in bg:
                stack.append((x, y))
    while stack:
        x, y = stack.pop()
        if not (0 <= x < W and 0 <= y < H) or trans[y][x]:
            continue
        if px[x0 + x, y0 + y] not in bg:
            continue
        trans[y][x] = True
        stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    return [[not trans[y - y0][x - x0] for x in range(rx0, rx1)]
            for y in range(ry0, ry1)]


def cmd_card(cap_path, list_out, tiles_out, pal_out):
    from PIL import Image
    from collections import Counter
    img = Image.open(cap_path).convert("RGB")
    px, (w, h) = img.load(), img.size
    x0, y0, x1, y1 = CARD_RECT
    bg = bg_colors(px, w, h)
    mask = opaque_mask(px, bg, CARD_RECT, img.size)

    cells = []                       # (col, row) with at least one opaque pixel
    for r in range((y1 - y0 + 7) // 8):
        for c in range((x1 - x0 + 7) // 8):
            if any(mask[r * 8 + dy][c * 8 + dx]
                   for dy in range(8) for dx in range(8)
                   if r * 8 + dy < len(mask) and c * 8 + dx < len(mask[0])):
                cells.append((c, r))
    if len(cells) > MAX_SPRITES or len(cells) > MAX_TILES:
        raise SystemExit(f"composition too big: {len(cells)} cells "
                         f"(max {min(MAX_SPRITES, MAX_TILES)})")

    # palette: index 0 is transparent, 15 colours for the art
    counts = Counter()
    for r in range(len(mask)):
        for c in range(len(mask[0])):
            if mask[r][c]:
                counts[px[x0 + c, y0 + r]] += 1
    art = [c for c, _ in counts.most_common()]
    palette = [(0, 0, 0)] + art[:15]
    while len(palette) < 16:
        palette.append((0, 0, 0))
    dropped = len(art) - 15
    if dropped > 0:
        print(f"note: {dropped} colour(s) quantised away ({len(art)} distinct)")

    def nearest(col):
        best, bi = None, 1
        for i in range(1, 16):
            d = sum((a - b) ** 2 for a, b in zip(col, palette[i]))
            if best is None or d < best:
                best, bi = d, i
        return bi

    tiles = bytearray(32 * len(cells))
    recs = bytearray([len(cells)])
    for tile, (c, r) in enumerate(cells):
        # The sprites are drawn X-FLIPPED (attr bit $40), so store each tile
        # mirrored: tile column 7-dx lands at screen offset dx.
        grid = [[0] * 8 for _ in range(8)]
        for dy in range(8):
            for dx in range(8):
                yy, xx = r * 8 + dy, c * 8 + dx
                if yy < len(mask) and xx < len(mask[0]) and mask[yy][xx]:
                    grid[dy][7 - dx] = nearest(px[x0 + xx, y0 + yy])
        tiles[tile * 32:tile * 32 + 32] = pack_tile(grid)
        sx, sy = x0 + c * 8, y0 + r * 8
        xf, yo = (sx - ANCHOR_X) & 0xFF, (sy - ANCHOR_Y) & 0xFF
        recs += bytes((xf, xf, yo, 0x00, tile, LIST_ATTR))

    Path(list_out).write_bytes(bytes(recs))
    Path(tiles_out).write_bytes(bytes(tiles))
    pb = bytearray()
    for col in palette:
        wv = rgb_to_snes(col)
        pb += bytes((wv & 0xFF, wv >> 8))
    Path(pal_out).write_bytes(bytes(pb))
    print(f"{len(cells)} sprites/tiles (of {((x1-x0)//8)*((y1-y0)//8)} cells), "
          f"{len(recs)} B list, {len(tiles)} B tiles")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    if sys.argv[1] == "--render":
        cmd_render(*sys.argv[2:6])
    elif sys.argv[1] == "--convert":
        cmd_convert(*sys.argv[2:7])
    elif sys.argv[1] == "--card":
        cmd_card(*sys.argv[2:6])
    else:
        raise SystemExit(__doc__)
