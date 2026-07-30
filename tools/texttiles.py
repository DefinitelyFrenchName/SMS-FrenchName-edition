#!/usr/bin/env python3
"""Render a short string into SNES 4bpp title-subtitle tiles.

Emits the CHR bytes for the 21-column subtitle strip (tilemap rows 13/14), i.e. for each
column a top 8x8 tile (row 13 slot) and a bottom 8x8 tile (row 14 slot), using the
subtitle's palette 0 (idx1=red, idx2=pink, idx3=white).

Hand-drawn 8-wide glyphs (only the letters in "DefinitelyFrenchName" plus space) so the
mockup is crisp pixel art rather than thresholded TTF. Baseline at row 12 of a 16-row cell.
"""

# Each glyph: list of 8-wide rows ('#'=core). Baseline convention: every glyph's last
# row sits on BASE (row 11); ascenders/caps are taller and start higher; the descender
# on 'y' extends below BASE. top is derived so all baselines align.
BASE = 11
G = {}
def d(ch, rows, drop=0):
    # drop = rows extending BELOW the baseline (descenders). Non-descender bottom == BASE.
    top = BASE - (len(rows) - 1) + drop
    G[ch] = (rows, top)

# Uppercase / digits (cap height 9): bottom on BASE
d('D', ["#####...","##..##..","##...##.","##...##.","##...##.","##...##.","##...##.","##..##..","#####..."])
d('E', ["#######.","##......","##......","#####...","##......","##......","##......","##......","#######."])
d('F', ["#######.","##......","##......","#####...","##......","##......","##......","##......","##......"])
d('R', ["######..","##...##.","##...##.","##...##.","######..","##.##...","##..##..","##...##.","##...##."])
d('N', ["##...##.","###..##.","####.##.","##.####.","##..###.","##...##.","##...##.","##...##.","##...##."])
d('0', [".####...","##..##..","##..##..","##..##..","##..##..","##..##..","##..##..","##..##..",".####..."])
d('1', ["..##....",".###....","..##....","..##....","..##....","..##....","..##....","..##....",".####..."])
d('2', [".####...","##..##..","....##..","...##...","..##....",".##.....","##......","##......","######.."])
d('3', [".####...","##..##..","....##..","..###...","....##..","....##..","....##..","##..##..",".####..."])
d('4', ["...###..","..####..",".##.##..","##..##..","##..##..","########","....##..","....##..","....##.."])
d('5', ["######..","##......","##......","#####...","....##..","....##..","....##..","##..##..",".####..."])
d('6', [".####...","##..##..","##......","#####...","##..##..","##..##..","##..##..","##..##..",".####..."])
d('7', ["######..","....##..","....##..","...##...","...##...","..##....","..##....","..##....","..##...."])
d('8', [".####...","##..##..","##..##..",".####...","##..##..","##..##..","##..##..","##..##..",".####..."])
d('9', [".####...","##..##..","##..##..","##..##..",".#####..","....##..","....##..","##..##..",".####..."])

# Lowercase x-height (7): bottom on BASE
d('e', [".####...","##..##..","##..##..","######..","##......","##..##..",".####..."])
d('a', [".####...","....##..",".#####..","##..##..","##..##..","##.###..",".###.##."])
d('c', [".####...","##..##..","##......","##......","##......","##..##..",".####..."])
d('m', ["##.##...","########","##.##.##","##.##.##","##.##.##","##.##.##","##.##.##"])
d('n', ["#.###...","##..##..","##..##..","##..##..","##..##..","##..##..","##..##.."])
d('r', ["#.###...","##..##..","##......","##......","##......","##......","##......"])
d('v', ["##...##.","##...##.","##...##.",".##.##..",".##.##..","..###...","..###..."])
# Ascenders (9): bottom on BASE
d('h', ["##......","##......","##.###..","###..##.","##...##.","##...##.","##...##.","##...##.","##...##."])
d('l', ["###.....",".##.....",".##.....",".##.....",".##.....",".##.....",".##.....",".##.....",".###...."])
d('t', [".##.....",".##.....","#####...",".##.....",".##.....",".##.....",".##.....",".##..##.","..####.."])
d('i', ["##......","........","##......","##......","##......","##......","##......"])
d('f', ["..###...",".##..##.",".##.....","#####...",".##.....",".##.....",".##.....",".##.....",".##....."])
# Descender: x-height body + tail below BASE
d('y', ["##...##.","##...##.","##...##.","##...##.",".######.","....##..","...##...","####...."], drop=2)
# Punctuation
d('.', ["##......","##......"])
d(' ', ["........"])

def _cell(ch):
    """Return a 16-row x 8-col grid of palette indices for one character cell."""
    rows, top = G.get(ch, G[' '])
    grid = [[0]*8 for _ in range(16)]
    for i, r in enumerate(rows):
        y = top + i
        if 0 <= y < 16:
            for x in range(min(8, len(r))):
                if r[x] == '#':
                    grid[y][x] = 1  # core (colored later)
    return grid

def _style(grid, mode):
    """Apply a color/outline treatment. grid = 16 x W core mask -> 16 x W palette indices."""
    RED, PINK, WHITE = 1, 2, 3
    H = len(grid); W = len(grid[0])
    out = [[0]*W for _ in range(H)]
    def outline(neigh, col):
        for y in range(H):
            for x in range(W):
                if grid[y][x]:
                    for dy,dx in neigh:
                        ny,nx=y+dy,x+dx
                        if 0<=ny<H and 0<=nx<W and not grid[ny][nx]: out[ny][nx]=col
    def fill(col):
        for y in range(H):
            for x in range(W):
                if grid[y][x]: out[y][x]=col
    N8 = ((1,0),(0,1),(1,1),(-1,0),(0,-1),(1,-1),(-1,1),(-1,-1))
    N4 = ((1,0),(0,1),(-1,0),(0,-1))
    if mode == "red":
        fill(RED)
    elif mode == "white_red":       # white core, red outline
        outline(N8, RED); fill(WHITE)
    elif mode == "red_white":       # red core, white outline (closest to original)
        outline(N4, WHITE); fill(RED)
    else:
        raise ValueError(f"texttiles: unknown style {mode!r} (red / white_red / red_white)")
    return out

def _glyph_cols(ch):
    """Return the glyph as a list of columns (each 16 ints), trimmed to its ink width."""
    grid = _cell(ch)  # 16x8 core mask
    # find inked column extent
    cols = [x for x in range(8) if any(grid[y][x] for y in range(16))]
    if not cols:  # space
        return [[0]*16 for _ in range(3)]  # 3px space
    lo, hi = min(cols), max(cols)
    out = []
    for x in range(lo, hi+1):
        out.append([grid[y][x] for y in range(16)])
    return out

def render(text, mode="red_white", ncells=21, gap=1):
    """Proportional layout across a (ncells*8)-wide x 16 strip, centered, then sliced into
    per-column top/bottom tiles. Returns (top_tiles, bottom_tiles)."""
    W = ncells * 8
    # build core strip
    glyphs = []
    for ch in text:
        glyphs.append(_glyph_cols(ch))
    total = sum(len(g) for g in glyphs) + gap*(len(glyphs)-1)
    if total > W:
        raise SystemExit(f"error: text {text!r} renders {total}px wide but the subtitle "
                         f"strip is {W}px — shorten it (the limit is pixels, not "
                         "characters; issue #40)")
    x0 = max(0, (W - total)//2)
    core = [[0]*W for _ in range(16)]
    x = x0
    for g in glyphs:
        for gc in g:
            if 0 <= x < W:
                for y in range(16):
                    core[y][x] = gc[y]
            x += 1
        x += gap
    # style the whole strip (outline computed across glyph boundaries -> clean joins)
    styled = _style(core, mode)  # 16 x W palette indices
    # slice into ncells columns of 8px
    tops, bots = [], []
    for c in range(ncells):
        colgrid = [[styled[y][c*8+x] for x in range(8)] for y in range(16)]
        tops.append(_to4bpp(colgrid[0:8]))
        bots.append(_to4bpp(colgrid[8:16]))
    return tops, bots

def _to4bpp(grid8):
    """8x8 palette-index grid -> 32-byte SNES 4bpp tile (planes 0/1 interleaved, 2/3 after)."""
    out = bytearray(32)
    for y in range(8):
        b0=b1=b2=b3=0
        for x in range(8):
            px = grid8[y][x] & 0xF
            bit = 7-x
            b0 |= ((px>>0)&1)<<bit
            b1 |= ((px>>1)&1)<<bit
            b2 |= ((px>>2)&1)<<bit
            b3 |= ((px>>3)&1)<<bit
        out[y*2]=b0; out[y*2+1]=b1; out[16+y*2]=b2; out[16+y*2+1]=b3
    return bytes(out)

# The VRAM tile slots for the 21 subtitle columns (from investigation).
ROW13 = [0x10D,0x10E,0x10F]+list(range(0x120,0x130))+[0x140,0x141]
ROW14 = [0x11D,0x11E,0x11F]+list(range(0x130,0x140))+[0x150,0x151]
if len(ROW13) != 21 or len(ROW14) != 21:
    raise ValueError("subtitle slot tables must be 21 columns each")

if __name__ == "__main__":
    import sys, json
    text = sys.argv[1] if len(sys.argv)>1 else "DefinitelyFrenchName"
    mode = sys.argv[2] if len(sys.argv)>2 else "red_white"
    tops, bots = render(text, mode)
    # emit as hex lines: "<vram_tile_hex> <32-byte-hex>"
    out = []
    for slot, tile in zip(ROW13, tops): out.append(f"{slot:03X} {tile.hex()}")
    for slot, tile in zip(ROW14, bots): out.append(f"{slot:03X} {tile.hex()}")
    from pathlib import Path as _P
    REPO = _P(__file__).resolve().parent.parent  # repo root (cwd-independent)
    open(str(REPO / "traces/subtitle_tiles.txt"), "w").write("\n".join(out))
    print(f"rendered '{text}' mode={mode}: {len(out)} tiles -> traces/subtitle_tiles.txt")
