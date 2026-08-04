#!/usr/bin/env python3
"""findfont.py — locate a Latin font inside an arbitrary SNES ROM.

Written for patch 16: the maintainer can supply a donor ROM but not the address
of its font, so the address has to be *found* rather than known. The method is
generic — nothing here is Soul Blazer specific.

The idea: a font is not just "tiles that look like letters", it is a RUN of
consecutive glyph cells that share structure. Individual letters are hard to
recognise; a 26-cell run in which every cell is non-blank, every cell inks the
same vertical band, and every cell has a similar ink density is an extremely
strong signature that almost nothing else in a ROM produces. Graphics are either
blank, solid, or structurally inconsistent cell to cell.

Scoring a window of RUN consecutive glyphs:
  * every glyph non-blank, and not all identical
  * ink density per glyph inside [MIN_DENS, MAX_DENS]
  * the set of all-blank ROWS is consistent across glyphs — this is the strongest
    single signal, because it is the font's ascender/descender padding and text
    has it while artwork does not
  * left/right bearing columns blank in most glyphs

Phase matters: a font's glyph size is fixed but the block it lives in can start
at any byte, so every phase 0..cell-1 is scanned. Depth matters too — SNES fonts
are commonly 1bpp (menus) or 2bpp, occasionally 4bpp — so scan each.

SCOPE — what this does NOT handle. It assumes glyphs are stored LINEARLY, one
after another, 8 px wide. That is the normal layout for a ROM-resident font that
gets uploaded to VRAM. It does NOT find:
  * fonts stored as a VRAM SHEET image (glyph n at tile T, its lower half 16
    tiles away) — SMS's own menu font is like that, and this finder scores it
    zero, which is how the limitation was found;
  * glyphs wider than 8 px (SMS's 16x16 menu font again).
Validated on a synthetic 8x16 linear font hidden in 32 KB of noise: located it to
within one glyph (reported $3222 for a font at $3210), and the render at the
reported offset is legible. Localise, then render around the hit to find the exact
phase — the score does not pin the byte, the eye does.

    tools/findfont.py <rom> --bpp 1 --height 16
    tools/findfont.py <rom> --all              # sweep 1/2/4 bpp x 8/16 px
    tools/findfont.py <rom> --show 0x1E340 --bpp 1 --height 16   # render a hit

Rendering a candidate is the proof: if it reads A B C D E ... it is the font.
Nothing is written to the repo — donor ROM contents stay local (asset policy).
"""
import argparse
import os
import sys

POP = bytes(bin(i).count("1") for i in range(256))


def glyph_rows(d, off, bpp, height):
    """-> list of `height` ints, each a bitmask of which of the 8 columns have ink.

    Collapsing to "is this pixel non-zero" is deliberate: for finding a font the
    shape matters and the palette does not, and it makes 1/2/4 bpp comparable."""
    rows = []
    if bpp == 1:
        for y in range(height):
            i = off + y
            if i >= len(d):
                return None
            rows.append(d[i])
        return rows
    if bpp == 2:
        for y in range(height):
            i = off + (y // 8) * 16 + (y % 8) * 2
            if i + 1 >= len(d):
                return None
            rows.append(d[i] | d[i + 1])
        return rows
    # 4bpp: two bitplane pairs, 32 bytes per 8x8 tile
    for y in range(height):
        t, yy = y // 8, y % 8
        b = off + t * 32
        i, j = b + yy * 2, b + 16 + yy * 2
        if j + 1 >= len(d):
            return None
        rows.append(d[i] | d[i + 1] | d[j] | d[j + 1])
    return rows


def cell_bytes(bpp, height):
    return {1: height, 2: (height // 8) * 16, 4: (height // 8) * 32}[bpp]


def score_window(glyphs, min_dens, max_dens):
    """-> (score, blank_row_mask) or None if this window is not font-like"""
    n = len(glyphs)
    if any(g is None for g in glyphs):
        return None
    dens = []
    for g in glyphs:
        ink = sum(POP[r] for r in g)
        if ink == 0:
            return None                      # a blank cell breaks the run
        dens.append(ink / (8 * len(g)))
    if not all(min_dens <= x <= max_dens for x in dens):
        return None
    if len({tuple(g) for g in glyphs}) < max(3, n // 4):
        return None                          # near-uniform: a fill pattern, not text
    # consistency of blank rows == the font's vertical padding
    height = len(glyphs[0])
    blank_counts = [sum(1 for g in glyphs if g[y] == 0) for y in range(height)]
    consistent = sum(1 for c in blank_counts if c == 0 or c == n)
    pad = sum(1 for c in blank_counts if c == n)
    if pad == 0:                             # real fonts pad top or bottom
        return None
    # bearings: columns 0 and 7 blank in most glyphs
    left = sum(1 for g in glyphs if not any(r & 0x80 for r in g))
    right = sum(1 for g in glyphs if not any(r & 0x01 for r in g))
    spread = max(dens) - min(dens)
    score = (consistent / height) * 2 + (left + right) / (2 * n) + (1 - min(spread, 1))
    return score, blank_counts


def scan(d, bpp, height, run, min_dens, max_dens, top):
    cb = cell_bytes(bpp, height)
    hits = []
    for phase in range(cb):
        offs = list(range(phase, len(d) - cb * run, cb))
        cache = {}
        i = 0
        while i < len(offs) - run:
            window = []
            ok = True
            for k in range(run):
                o = offs[i + k]
                g = cache.get(o)
                if g is None:
                    g = glyph_rows(d, o, bpp, height)
                    cache[o] = g
                if g is None:
                    ok = False
                    break
                window.append(g)
            if ok:
                s = score_window(window, min_dens, max_dens)
                if s:
                    hits.append((s[0], offs[i], bpp, height))
            i += 1
        cache.clear()
    hits.sort(reverse=True)
    # suppress overlapping hits
    keep = []
    for h in hits:
        if all(abs(h[1] - k[1]) > cb * run // 2 for k in keep):
            keep.append(h)
        if len(keep) >= top:
            break
    return keep


def render(d, off, bpp, height, count):
    for base in range(0, count, 13):
        grp = [off + (base + i) * cell_bytes(bpp, height) for i in range(min(13, count - base))]
        gs = [glyph_rows(d, o, bpp, height) for o in grp]
        gs = [g for g in gs if g]
        if not gs:
            return
        for y in range(height):
            print("  " + " ".join("".join("#" if g[y] & (0x80 >> x) else "." for x in range(8))
                                  for g in gs))
        print()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rom")
    ap.add_argument("--bpp", type=int, default=1, choices=[1, 2, 4])
    ap.add_argument("--height", type=int, default=16, choices=[8, 16])
    ap.add_argument("--run", type=int, default=20, help="consecutive glyphs required")
    ap.add_argument("--min-dens", type=float, default=0.10)
    ap.add_argument("--max-dens", type=float, default=0.60)
    ap.add_argument("--top", type=int, default=8)
    ap.add_argument("--all", action="store_true", help="sweep 1/2/4 bpp x 8/16 px")
    ap.add_argument("--show", type=lambda s: int(s, 0), default=None)
    ap.add_argument("--count", type=int, default=26)
    a = ap.parse_args()
    if not os.path.exists(a.rom):
        sys.exit("no such ROM: %s" % a.rom)
    d = open(a.rom, "rb").read()
    print("%s: %d bytes" % (os.path.basename(a.rom), len(d)))

    if a.show is not None:
        print("rendering %d glyphs at $%06X (%dbpp, %dpx)" % (a.count, a.show, a.bpp, a.height))
        render(d, a.show, a.bpp, a.height, a.count)
        return

    combos = [(b, h) for b in (1, 2, 4) for h in (8, 16)] if a.all else [(a.bpp, a.height)]
    for bpp, height in combos:
        hits = scan(d, bpp, height, a.run, a.min_dens, a.max_dens, a.top)
        print("\n=== %dbpp, %dpx cells, run of %d ===" % (bpp, height, a.run))
        if not hits:
            print("  no font-like runs found")
            continue
        for s, off, _, _ in hits:
            print("  score %.2f  at $%06X   (SNES LoROM ~$%02X:%04X)"
                  % (s, off, 0x80 + (off // 0x8000), 0x8000 + (off % 0x8000)))
        print("  render the best with:  tools/findfont.py %s --show 0x%X --bpp %d --height %d"
              % (a.rom, hits[0][1], bpp, height))


if __name__ == "__main__":
    main()
