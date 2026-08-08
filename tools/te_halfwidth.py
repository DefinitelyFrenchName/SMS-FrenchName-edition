#!/usr/bin/env python3
"""te_halfwidth.py — harvest the Tournament Edition's HALF-WIDTH Latin font.

Why this matters: docs/game/menu_text.md recorded that half-width Latin "already
exists" in SMS's `PRESS "SELECT" TO ACS` banner. It does not — that strip is
proportionally-spaced artwork whose letters straddle tile boundaries, so nothing
can be lifted from it (measured; see the doc). The Big Zam edition is the same.

The **Tournament Edition** (`SMS_BZE_TE.sfc`, distinct from the Big Zam hack) is
different: its title screen draws menu items in a genuine **tile-aligned**
half-width font — one 7 px glyph per 8 px tile, two tiles tall (8x16).

    row $340 decodes letter by letter as  T O U R N A M E N T   M O D E

That is a real font, and it is harvestable.

Detection, not assumption: a text row is a FONT row when its ink runs sit on a
CONSISTENT 8 px grid — one or two distinct start offsets mod 8, and no glyph
wider than a cell. Artwork fails on both counts (the SMS banner's runs start at
all eight offsets and are 16-40 px wide). See is_font_row(): the first version of
this rule demanded `start % 8 == 0` and rejected the real font, whose glyphs
carry a 1 px left bearing so every run starts at offset 1.

Polarity note: these tiles are drawn as a filled cell (colour 1) with the letter
in other indices, so "any non-zero" renders a solid block and hides the glyph.
Ink = non-zero AND != 1.

    tools/te_halfwidth.py rows                     # which rows are font rows
    tools/te_halfwidth.py sheet --row 0x340        # ASCII contact sheet of a row
    tools/te_halfwidth.py extract --out glyphs.json

Source: a VRAM capture of the TE title screen —
    ROM=<TE> OUT=te tools/run.sh tools/probe_title_vram.lua 120
writes traces/titlevram_te_700.bin (the frame-700 dump is the one with the menu).
"""
import argparse
import hashlib
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_CAP = os.path.join(REPO, "traces", "titlevram_te_700.bin")
SHEET_W = 16                      # tiles per row in the CHR sheet
FILL = 1                          # the cell fill colour; the letter is the rest


def load(path):
    with open(path, "rb") as f:
        return f.read()


def tile(d, t):
    """decode one 8x8 4bpp tile -> 8 rows of 8 palette indices"""
    o = t * 32
    b = d[o:o + 32]
    rows = []
    for y in range(8):
        lo, hi = b[y * 2], b[y * 2 + 1]
        lo2, hi2 = b[16 + y * 2], b[16 + y * 2 + 1]
        rows.append([((lo >> (7 - x)) & 1) | (((hi >> (7 - x)) & 1) << 1)
                     | (((lo2 >> (7 - x)) & 1) << 2) | (((hi2 >> (7 - x)) & 1) << 3)
                     for x in range(8)])
    return rows


def glyph(d, t):
    """an 8x16 half-width glyph = tile t (top) + tile t+SHEET_W (bottom), as ink bits"""
    g = tile(d, t) + tile(d, t + SHEET_W)
    return [[1 if (v and v != FILL) else 0 for v in row] for row in g]


def row_strip(d, base):
    """the 16 glyphs of a text row, as one 128x16 ink bitmap"""
    gs = [glyph(d, base + i) for i in range(SHEET_W)]
    return [sum((g[y] for g in gs), []) for y in range(16)]


def ink_runs(strip):
    w = len(strip[0])
    ink = [any(strip[y][x] for y in range(16)) for x in range(w)]
    runs, i = [], 0
    while i < w:
        if ink[i]:
            j = i
            while j + 1 < w and ink[j + 1]:
                j += 1
            runs.append((i, j))
            i = j + 1
        else:
            i += 1
    return runs


def is_font_row(strip):
    """A font row sits on a CONSISTENT 8 px grid; artwork does not.

    Not "every run starts at a multiple of 8" — that was the first rule and it
    rejected the real font, because these glyphs carry a 1 px left bearing so
    every run starts at offset 1 (`starts_mod8=[1]`, a single value). A uniform
    non-zero offset is still a grid. What actually distinguishes artwork is that
    its runs start at MANY different offsets and are wider than a cell.

    Runs wider than 8 px are ignored when judging: a font row may also contain a
    solid rule or border, and that should not disqualify it."""
    runs = ink_runs(strip)
    if not runs:
        return False, runs
    glyphs = [(a, b) for a, b in runs if b - a + 1 <= 8]
    if len(glyphs) < 4:
        return False, runs
    return len({a % 8 for a, _ in glyphs}) <= 2, runs


def cmd_rows(d, lo, hi):
    print("scanning tile rows $%03X-$%03X for tile-aligned half-width font rows" % (lo, hi))
    for base in range(lo, hi, SHEET_W * 2):      # every other row: tops only
        strip = row_strip(d, base)
        ok, runs = is_font_row(strip)
        if not runs:
            continue
        widths = [b - a + 1 for a, b in runs]
        print("  $%03X/%03X  %-5s runs=%-3d starts_mod8=%-18s widths=%s"
              % (base, base + SHEET_W, "FONT" if ok else "art", len(runs),
                 sorted({a % 8 for a, _ in runs}), widths[:12]))


def cmd_sheet(d, base):
    gs = [(base + i, glyph(d, base + i)) for i in range(SHEET_W)]
    gs = [(t, g) for t, g in gs if any(any(r) for r in g)]
    for k in range(0, len(gs), 8):
        grp = gs[k:k + 8]
        print("  " + "  ".join("$%03X    " % t for t, _ in grp))
        for y in range(16):
            print("  " + "  ".join("".join("#" if v else "." for v in g[y]) for _, g in grp))
        print()


def cmd_extract(d, lo, hi, out):
    """every distinct glyph from every FONT row, keyed by content hash"""
    found, order = {}, []
    for base in range(lo, hi, SHEET_W * 2):
        strip = row_strip(d, base)
        ok, runs = is_font_row(strip)
        if not (ok and runs):
            continue
        for i in range(SHEET_W):
            t = base + i
            g = glyph(d, t)
            if not any(any(r) for r in g):
                continue
            key = hashlib.sha1(bytes(v for r in g for v in r)).hexdigest()[:10]
            if key not in found:
                found[key] = {"tile": t, "rows": ["".join(str(v) for v in r) for r in g],
                              "label": None}
                order.append(key)
    data = {"source": "TE title VRAM", "glyphs": [found[k] for k in order]}
    with open(out, "w") as f:
        json.dump(data, f, indent=1)
    print("extracted %d distinct half-width glyphs from font rows -> %s" % (len(order), out))
    print("labels are null: identify them from the on-screen strings, then this")
    print("becomes a code->glyph table the way menufont_table.py did for 16x16.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["rows", "sheet", "extract"])
    ap.add_argument("--cap", default=DEFAULT_CAP)
    ap.add_argument("--lo", type=lambda s: int(s, 0), default=0x300)
    ap.add_argument("--hi", type=lambda s: int(s, 0), default=0x460)
    ap.add_argument("--row", type=lambda s: int(s, 0), default=0x340)
    ap.add_argument("--out", default=os.path.join(REPO, "docs", "game", "te_halfwidth.json"))
    a = ap.parse_args()
    if not os.path.exists(a.cap):
        sys.exit("no capture at %s — run probe_title_vram.lua on SMS_BZE_TE.sfc first" % a.cap)
    d = load(a.cap)
    if a.cmd == "rows":
        cmd_rows(d, a.lo, a.hi)
    elif a.cmd == "sheet":
        cmd_sheet(d, a.row)
    else:
        cmd_extract(d, a.lo, a.hi, a.out)


if __name__ == "__main__":
    main()
