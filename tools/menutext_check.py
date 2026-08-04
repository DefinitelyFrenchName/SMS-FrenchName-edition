#!/usr/bin/env python3
"""menutext_check.py — validate proposed menu/stage strings against the font and
the cell budget, and emit the tile encoding a patch would write.

Every string in this game is a run of tile codes in a tilemap, so "does this
translation fit" is three mechanical questions: is it within the cell budget, is
every character in the font, and where does it sit once centred. This answers all
three before anyone edits a ROM.

  python3 tools/menutext_check.py stages        # the ten stage names + Saturn's

Glyphs that do not exist yet are reported as MUST AUTHOR and given a provisional
code from the free-slot list, so the encoding can be produced now and the glyph
drawn later.
"""
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "tools"))
import menufont_table as T  # noqa: E402

STAGE_CELLS = 12          # 24 words per row, 2 words per full-width glyph

# Provisional codes for glyphs that have to be drawn, taken from the free
# full-width slots (menufont_table.FREE_FULL_SLOTS).
PLANNED = {"S": 0x368, ".": 0x36A}

# The maintainer's proposal, 2026-08-04. Index = stage number.
STAGES = [
    "CR. TOKYO ◆夕",
    "S. MILLENIUM",
    "TIME DOOR",
    "KAIOSHU PARK",
    "FOUNTAIN ◆昼",
    "SHOP. STREET",
    "SHRINE",
    "CR. TOKYO ◆夜",
    "FOUNTAIN ◆夜",
    "EDITOR. DEPT",
]
SATURN_STAGE = "SLNT. THRONE"   # replaces stage 2 (時空の扉) in the Saturn build


def code_for(ch):
    """(vram_code, status) for one character. ' ' is a blank cell, not a glyph."""
    if ch == " ":
        return 0, "blank"
    c = T.CHAR_TO_VRAM.get(ch)
    if c is not None:
        return c, "ok"
    if ch in PLANNED:
        return PLANNED[ch], "author"
    return None, "MISSING"


def check(name, text, budget=STAGE_CELLS):
    cells = list(text)
    codes, need, bad = [], set(), []
    for ch in cells:
        c, st = code_for(ch)
        if st == "MISSING":
            bad.append(ch)
            codes.append(None)
        else:
            if st == "author":
                need.add(ch)
            codes.append(c)
    fits = len(cells) <= budget
    return {"text": text, "n": len(cells), "fits": fits,
            "author": sorted(need), "unknown": bad, "codes": codes}


def encode_row(codes, budget=STAGE_CELLS):
    """Centre the glyphs in `budget` cells and emit the 2*budget words of the
    TOP row — the record's actual payload. (The name is centred by zero padding
    in the vanilla records; the game does not centre at runtime.)"""
    pad = (budget - len(codes)) // 2
    cells = [0] * pad + codes + [0] * (budget - pad - len(codes))
    words = []
    for c in cells:
        if not c:
            words += [0, 0]
        else:
            words += [c, c + 1]          # top-left, top-right of the 2x2 glyph
    return words


def main():
    what = sys.argv[1] if len(sys.argv) > 1 else "stages"
    if what != "stages":
        raise SystemExit("usage: menutext_check.py stages")
    rows = [(f"stage {i}", s) for i, s in enumerate(STAGES)]
    rows.append(("saturn (stage 2)", SATURN_STAGE))
    allneed, fail = set(), 0
    print(f"budget: {STAGE_CELLS} full-width cells per stage name\n")
    print(f"{'':17} {'cells':>5}  {'':4} text")
    for label, text in rows:
        r = check(label, text)
        mark = "ok  " if r["fits"] and not r["unknown"] else "FAIL"
        if not (r["fits"] and not r["unknown"]):
            fail += 1
        allneed |= set(r["author"])
        print(f"{label:17} {r['n']:>5}  {mark} {text}"
              + (f"   <- no glyph for {r['unknown']}" if r["unknown"] else ""))
    print()
    if allneed:
        print("MUST AUTHOR before this ships: " + ", ".join(f"'{c}'" for c in sorted(allneed)))
        for c in sorted(allneed):
            print(f"   '{c}' -> provisional slot ${PLANNED[c]:03X}")
        used = 2 * len(allneed)
        print(f"   uses {used} of {sum(len(v) for v in T.FREE_HALF_SLOTS.values())} "
              f"free half-slots — no relocation needed")
    print(f"\n{len(rows) - fail}/{len(rows)} strings ready.")


if __name__ == "__main__":
    main()
