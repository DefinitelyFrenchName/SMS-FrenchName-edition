#!/usr/bin/env python3
"""mkhalfwidth.py — build a half-width (8x16) Latin alphabet for patch 16 from
SMS's OWN 16x16 capitals.

Why this route: the game already contains 21 Latin capitals, so a condensed set
is natively in style and carries no licence question — the same basis on which
this project reuses Big Zam palettes and Super S assets. Measured viable
(docs/menu_text.md "CONDENSING SMS's OWN CAPITALS"): reducing 16->8 with AND of
each column pair yields 2 px stems inside ~6-7 px of ink, which is exactly the
weight of the Tournament Edition's half-width font — a face already proven
legible on this hardware.

Addressing, which is the part that wastes time if taken from the wrong place:

    Latin 'A' lives at KANA-BLOCK tile $16A  ($C3:48D0, decompressed)
    screens that show Latin load that block at base $0A0, hence VRAM $20A
    the button-config screen loads it at $2A0, where $20A is unrelated artwork

So "$20A" in the older notes is a VRAM address on one screen, not a block offset.
tools/menufont_table.py is the authority and states this outright.

Three glyph sources, in order of preference:
  1. CONDENSED   — 17 of the 21 reduce cleanly and are used as-is
  2. REPAIRED    — A M W X: their diagonals thin to 1 px under AND and read
                   raggedly, so they are hand-corrected here
  3. AUTHORED    — F J Q S Z: absent from the game, drawn to match the condensed
                   siblings (2 px stems, same cap band)

    tools/mkhalfwidth.py sheet              # the full A-Z, as ASCII
    tools/mkhalfwidth.py text "MANUAL"      # a string at true size
    tools/mkhalfwidth.py export --out docs/halfwidth_caps.json
"""
import argparse
import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "tools"))
sys.path.insert(0, os.path.join(REPO, "tools", "saturn"))

SHEET_W = 16
KANA_BLOCK = (0xC3, 0x48D0)
CAP_H = 16

# --- hand work -------------------------------------------------------------
# 8x16, '#' = ink. The condensed siblings put stems at x=1..2 and bars out to
# x=6, so these match that band rather than filling the cell edge to edge.
REPAIRED = {
    "A": ("........",
          "...##...",
          "...##...",
          "..####..",
          "..####..",
          "..#..#..",
          ".##..##.",
          ".##..##.",
          ".######.",
          ".######.",
          ".##..##.",
          ".##..##.",
          ".##..##.",
          ".##..##.",
          ".##..##.",
          "........"),
    "M": ("........",
          ".##...##",
          ".###.###",
          ".#######",
          ".#######",
          ".##.#.##",
          ".##.#.##",
          ".##...##",
          ".##...##",
          ".##...##",
          ".##...##",
          ".##...##",
          ".##...##",
          ".##...##",
          ".##...##",
          "........"),
    "W": ("........",
          ".##...##",
          ".##...##",
          ".##...##",
          ".##...##",
          ".##...##",
          ".##...##",
          ".##.#.##",
          ".##.#.##",
          ".#######",
          ".#######",
          ".###.###",
          ".###.###",
          ".##...##",
          ".##...##",
          "........"),
    "X": ("........",
          ".##...##",
          ".##...##",
          ".##...##",
          "..##.##.",
          "..##.##.",
          "..##.##.",
          "....#...",
          "..##.##.",
          "..##.##.",
          "..##.##.",
          ".##...##",
          ".##...##",
          ".##...##",
          ".##...##",
          "........"),
}

AUTHORED = {
    "F": ("........",
          ".######.",
          ".######.",
          ".######.",
          ".##.....",
          ".##.....",
          ".##.....",
          ".#####..",
          ".#####..",
          ".#####..",
          ".##.....",
          ".##.....",
          ".##.....",
          ".##.....",
          ".##.....",
          "........"),
    "J": ("........",
          "...#####",
          "...#####",
          "...#####",
          ".....##.",
          ".....##.",
          ".....##.",
          ".....##.",
          ".....##.",
          ".....##.",
          ".....##.",
          ".##..##.",
          ".##..##.",
          "..####..",
          "...##...",
          "........"),
    "Q": ("........",
          "...##...",
          "..####..",
          "..####..",
          ".##..##.",
          ".##..##.",
          ".##..##.",
          ".##..##.",
          ".##..##.",
          ".##..##.",
          ".##.###.",
          ".##..##.",
          "..#####.",
          "..####.#",
          "...##..#",
          "........"),
    "S": ("........",
          "..#####.",
          ".######.",
          ".##..##.",
          ".##.....",
          ".###....",
          "..####..",
          "...###..",
          "....###.",
          ".....##.",
          ".##..##.",
          ".##..##.",
          ".######.",
          ".#####..",
          "........",
          "........"),
    "Z": ("........",
          ".######.",
          ".######.",
          ".######.",
          "....##..",
          "....##..",
          "...##...",
          "...##...",
          "..##....",
          "..##....",
          ".##.....",
          ".##.....",
          ".######.",
          ".######.",
          ".######.",
          "........"),
}


def load_caps():
    """the 21 in-game capitals, condensed 16->8 by AND of each column pair"""
    from smspaths import clean_rom
    import sms_lz
    rom = open(clean_rom(), "rb").read()
    bank, off = KANA_BLOCK
    blk = sms_lz.decompress(rom, ((bank & 0x3F) << 16) | off, 0x8000)

    def tile(t):
        o = t * 32
        b = blk[o:o + 32]
        rows = []
        for y in range(8):
            lo, hi = b[y * 2], b[y * 2 + 1]
            lo2, hi2 = b[16 + y * 2], b[16 + y * 2 + 1]
            rows.append([((lo >> (7 - x)) & 1) | (((hi >> (7 - x)) & 1) << 1)
                         | (((lo2 >> (7 - x)) & 1) << 2) | (((hi2 >> (7 - x)) & 1) << 3)
                         for x in range(8)])
        return rows

    src = open(os.path.join(REPO, "tools", "menufont_table.py")).read()
    codes = {int(k, 16): v for k, v in re.findall(r'0x([0-9A-Fa-f]{3}):\s*"([A-Z])"', src)
             if 0x160 <= int(k, 16) <= 0x1C3}
    out = {}
    for code, ch in codes.items():
        tl, tr = tile(code), tile(code + 1)
        bl, br = tile(code + SHEET_W), tile(code + SHEET_W + 1)
        g16 = [tl[y] + tr[y] for y in range(8)] + [bl[y] + br[y] for y in range(8)]
        # AND: a column pair inks only if BOTH halves do. OR closes the counters
        # and drop-odd is noisier — measured, see docs/menu_text.md.
        out[ch] = ["".join("#" if (g16[y][2 * x] and g16[y][2 * x + 1]) else "."
                           for x in range(8)) for y in range(CAP_H)]
    return out


def alphabet():
    caps = load_caps()
    glyphs, prov = {}, {}
    for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
        if ch in REPAIRED:
            glyphs[ch], prov[ch] = list(REPAIRED[ch]), "repaired"
        elif ch in AUTHORED:
            glyphs[ch], prov[ch] = list(AUTHORED[ch]), "authored"
        elif ch in caps:
            glyphs[ch], prov[ch] = caps[ch], "condensed"
    return glyphs, prov


def show(glyphs, order, per=13):
    for i in range(0, len(order), per):
        grp = [c for c in order[i:i + per] if c in glyphs]
        print("  " + " ".join("   %s    " % c for c in grp))
        for y in range(CAP_H):
            print("  " + " ".join(glyphs[c][y] for c in grp))
        print()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["sheet", "text", "export"])
    ap.add_argument("arg", nargs="?", default="")
    ap.add_argument("--out", default=os.path.join(REPO, "docs", "halfwidth_caps.json"))
    a = ap.parse_args()
    glyphs, prov = alphabet()
    missing = [c for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" if c not in glyphs]
    if a.cmd == "sheet":
        n = {k: sum(1 for v in prov.values() if v == k) for k in ("condensed", "repaired", "authored")}
        print("A-Z: %d glyphs  (condensed %d, repaired %d, authored %d)%s\n"
              % (len(glyphs), n["condensed"], n["repaired"], n["authored"],
                 "  MISSING: " + "".join(missing) if missing else ""))
        show(glyphs, "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    elif a.cmd == "text":
        s = (a.arg or "MANUAL").upper()
        cells = [glyphs.get(c) for c in s]
        print('"%s"  -> %d cells\n' % (s, len(s)))
        for y in range(CAP_H):
            print("  " + "".join(g[y] if g else "........" for g in cells))
    else:
        json.dump({"glyphs": {c: glyphs[c] for c in sorted(glyphs)},
                   "provenance": prov}, open(a.out, "w"), indent=1)
        print("wrote %d glyphs -> %s" % (len(glyphs), a.out))


if __name__ == "__main__":
    main()
