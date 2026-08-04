#!/usr/bin/env python3
"""halfwidth_render.py — render the half-width alphabet to a PNG for eyeballing.

Reads the glyphs from tools/mkhalfwidth.py directly (not from the exported JSON)
so it always shows the CURRENT state of the hand-edited REPAIRED/AUTHORED tables
— edit a glyph, re-run this, see it. That is the loop this exists for.

    tools/halfwidth_render.py                       # -> /tmp/halfwidth.png
    tools/halfwidth_render.py --out foo.png --strings "MODE,STAGE,MANUAL"

Colour codes provenance: white = condensed from the game's own capitals,
amber = repaired by hand, cyan = authored. The bottom panel puts the vanilla
full-width kana next to the half-width Latin on the same cell grid, which is the
whole argument for half-width in one picture.

Output is game-derived art: keep it local, never commit it (.gitignore blocks
images repo-wide — asset policy 2026-08-04).
"""
import argparse
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "tools"))
sys.path.insert(0, os.path.join(REPO, "tools", "saturn"))

from PIL import Image, ImageDraw                      # noqa: E402
import mkhalfwidth                                    # noqa: E402

BG = (16, 16, 24)
GREY = (120, 124, 140)
COL = {"condensed": (236, 240, 248), "repaired": (255, 206, 120), "authored": (120, 220, 255)}
# vanilla katakana for the budget comparison, codes from menufont_table.py
KANA_CODES = {"マ": 0x140, "ニ": 0x10E, "ュ": 0x14A, "ア": 0x0C6, "ル": 0x162,
              "モ": 0x146, "ー": 0x0C4, "ド": 0x10A}


def kana_glyphs():
    from smspaths import clean_rom
    import sms_lz
    rom = open(clean_rom(), "rb").read()
    bank, off = mkhalfwidth.KANA_BLOCK
    blk = sms_lz.decompress(rom, ((bank & 0x3F) << 16) | off, 0x8000)
    W = mkhalfwidth.SHEET_W

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

    out = {}
    for ch, code in KANA_CODES.items():
        tl, tr = tile(code), tile(code + 1)
        bl, br = tile(code + W), tile(code + W + 1)
        g = [tl[y] + tr[y] for y in range(8)] + [bl[y] + br[y] for y in range(8)]
        out[ch] = ["".join("#" if v else "." for v in row) for row in g]
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="/tmp/halfwidth.png")
    ap.add_argument("--strings", default="MODE,STAGE,MANUAL,TOURNAMENT")
    ap.add_argument("--compare", default="マニュアル|MANUAL")
    a = ap.parse_args()

    G, PROV = mkhalfwidth.alphabet()
    KG = kana_glyphs()
    S = 4
    im = Image.new("RGB", (1180, 760), BG)
    dr = ImageDraw.Draw(im)

    def blit(g, x, y, s, col, w=8):
        for yy in range(16):
            for xx in range(w):
                if g[yy][xx] == "#":
                    dr.rectangle([x + xx * s, y + yy * s, x + xx * s + s - 1, y + yy * s + s - 1],
                                 fill=col)

    n = {k: sum(1 for v in PROV.values() if v == k) for k in COL}
    dr.text((24, 18), "SMS half-width capitals — %d condensed, %d repaired, %d authored"
            % (n["condensed"], n["repaired"], n["authored"]), fill=(236, 240, 248))
    for i, (k, c) in enumerate(COL.items()):
        dr.rectangle([24 + i * 150, 44, 36 + i * 150, 54], fill=c)
        dr.text((42 + i * 150, 43), k, fill=GREY)

    for row, letters in enumerate(("ABCDEFGHIJKLM", "NOPQRSTUVWXYZ")):
        for i, ch in enumerate(letters):
            if ch not in G:
                continue
            x, y = 30 + i * 86, 80 + row * 100
            dr.rectangle([x - 2, y - 2, x + 8 * S + 1, y + 16 * S + 1], outline=(46, 48, 60))
            blit(G[ch], x, y, S, COL[PROV[ch]])
            dr.text((x + 12, y + 16 * S + 6), ch, fill=GREY)

    yb = 300
    dr.text((24, yb), "Your strings, at TRUE SIZE (1x) and 3x:", fill=(236, 240, 248))
    yb += 22
    for s in a.strings.split(","):
        s = s.strip().upper()
        x = 30
        for ch in s:
            if ch in G:
                blit(G[ch], x, yb, 1, COL[PROV[ch]])
            x += 8
        x2 = 140
        for ch in s:
            if ch in G:
                blit(G[ch], x2, yb - 8, 3, COL[PROV[ch]])
            x2 += 24
        dr.text((x2 + 24, yb - 2), "%d half-cells = %.1f full-width cells" % (len(s), len(s) / 2),
                fill=GREY)
        yb += 56

    jp, lat = a.compare.split("|")
    yc = 560
    dr.text((24, yc), "Budget: vanilla full-width vs half-width, same cell grid",
            fill=(236, 240, 248))
    yc += 24
    for label, text, is_kana in (("vanilla", jp, True), ("half-width", lat, False)):
        dr.text((30, yc + 14), label, fill=GREY)
        x = 140
        for ch in text:
            w = 16 if is_kana else 8
            dr.rectangle([x, yc, x + w * 3 - 1, yc + 16 * 3 - 1], outline=(60, 64, 80))
            g = KG.get(ch) if is_kana else G.get(ch)
            if g:
                blit(g, x, yc, 3, (200, 206, 220) if is_kana else COL[PROV[ch]], w=w)
            x += w * 3
        cells = len(text) if is_kana else (len(text) + 1) // 2
        dr.text((x + 16, yc + 18), "%d cells" % cells, fill=GREY)
        yc += 68
    dr.text((30, yc + 6), "%s needs %d of the %d cells the Japanese occupies."
            % (lat, (len(lat) + 1) // 2, len(jp)), fill=(160, 230, 160))

    im.save(a.out)
    print("wrote %s" % a.out)


if __name__ == "__main__":
    main()
