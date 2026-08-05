#!/usr/bin/env python3
"""mkpatch16.py — menu translation: install a half-width Latin alphabet.

STATUS: STEP 1 WORKS. The 26 glyphs reach VRAM tiles $5C0-$5FF on the button-
config screen and render as a legible A-Z (read back out of VRAM, not out of the
build). The tilemap edits — replacing the Japanese strings — come next and depend
on this.

Two things had to be true at once, which is why this took several attempts:

1. THE ASSET RECORD LAYOUT IN THE OLD NOTES WAS WRONG. A record is not
   [src24][dest24][u16][u16]; it is

       [vram16][len16][src24][dest24]      10 bytes, table at $C3:BE08

   so a block's upload LENGTH sits 2 bytes BEFORE its src pointer, not 8 after.
   Every earlier attempt bumped the wrong field — which is why it "changed
   nothing" for the font while quietly lengthening an unrelated transfer.
   Parsed correctly, 27 of the 58 records match a transfer observed on the
   config screen exactly (vram, len, dest); parsed the old way, none do.
   The field is a BYTE count, not words.

2. THE KANJI BLOCK IS NOT LOADED ON THE SCREEN BEING TRANSLATED. Earlier
   versions of this builder extended the kanji block ($C7:07F0, VRAM $500) and
   tested on the config screen, where its record never runs at all — no transfer
   to VRAM $5000 occurs there, so those glyphs could never have appeared no
   matter how the length was set. The sheet that screen actually loads is
   $C4:2590 -> $7E:C000 -> VRAM $400 (418 tiles), and that is what this patch
   extends.

So: the sheet grows 418 -> 512 tiles, the glyphs land at VRAM $5C0-$5FF (proven
free across the menu screens), and the record's length grows $3480 -> $4000
bytes. $4000 is also the ceiling: the source buffer starts at $7E:C000, so a
longer transfer would run off the end of bank $7E and wrap.

Verification that matters (tools/probe_menu_vram.lua):
  * POKE=1 stamps a pattern into the source past the vanilla transfer's end:
    0/256 bytes arrive on clean, 256/256 with the length raised.
  * on the built ROM, VRAM $5C0-$5FF holds 52 of 64 non-blank tiles — exactly
    26 letters x 2 tiles — against 0 on clean.

    tools/mkpatch16.py <out.sfc>            # from the clean ROM
    tools/mkpatch16.py --stacked <in> <out>
"""
import argparse
import hashlib
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "tools"))
sys.path.insert(0, os.path.join(REPO, "tools", "saturn"))

from smspaths import clean_rom, fix_checksum, next_bank, write_bank   # noqa: E402
import sms_lz                                                          # noqa: E402
import mkhalfwidth                                                     # noqa: E402

CLEAN_SHA1 = "bc0e29ee383574443226695215496eb0d09aaa1c"
# The font sheet the menu screens load at VRAM $400 — NOT the kanji block; see
# the module docstring for why that distinction cost several attempts.
FONT_SRC = 0xC42590               # compressed sheet, 418 tiles
FONT_VRAM = 0x4000                # its VRAM word address
FONT_LEN = 0x3480                 # its vanilla upload length, in BYTES
FONT_DEST = 0x7EC000              # WRAM staging buffer it decompresses into
TILE_BASE = 0x400                 # sheet tile 0 lands at VRAM tile $400
SHEET_W = 16
NEW_TILES = 0x200                 # extend to 512 tiles -> VRAM $400-$5FF
NEW_LEN = NEW_TILES * 32          # = $4000 BYTES; also the ceiling, since
                                  # $7E:C000 + $4000 is exactly the end of bank $7E
GLYPH_ROWS = (0x5C0, 0x5E0)       # two rows of 16, in VRAM tile numbers
INK = 7                           # flat ink colour; the kana use 1-8

# Asset job table: 10-byte records of [vram16][len16][src24][dest24].
REC0 = 0x00BE08                   # in bank $C3 — the first record's vram field
RECSZ = 10
NRECS = 58


def encode_glyph(rows, ink=INK):
    """an 8x16 '#'/'.' glyph -> (top 32-byte tile, bottom 32-byte tile), 4bpp"""
    out = []
    for half in (0, 8):
        t = bytearray(32)
        for y in range(8):
            line = rows[half + y]
            for x in range(8):
                if line[x] != "#":
                    continue
                b = 7 - x
                t[y * 2] |= (ink & 1) << b
                t[y * 2 + 1] |= ((ink >> 1) & 1) << b
                t[16 + y * 2] |= ((ink >> 2) & 1) << b
                t[16 + y * 2 + 1] |= ((ink >> 3) & 1) << b
        out.append(bytes(t))
    return out


def find_record(data, want_src):
    """Locate the asset record whose src is `want_src`. Returns (index, file off
    of the record start). The record is [vram16][len16][src24][dest24]."""
    B3 = 0x030000
    for n in range(NRECS):
        o = B3 + REC0 + n * RECSZ
        src = data[o + 4] | (data[o + 5] << 8) | (data[o + 6] << 16)
        if src == want_src:
            return n, o
    return None, None


def build(src_path, out_path, stacked=False):
    data = bytearray(open(src_path, "rb").read())
    sha = hashlib.sha1(data).hexdigest()
    if not stacked and sha != CLEAN_SHA1:
        raise SystemExit("source is not the clean ROM (%s); pass --stacked to "
                         "build on top of another patch" % sha[:12])

    # Locate the record BEFORE touching anything: its src field IS the block's
    # only pointer, so writing the pointer first would make the search fail.
    n, rec = find_record(data, FONT_SRC)
    if rec is None:
        raise SystemExit("no asset record points at the font sheet $%06X — has "
                         "another patch moved it?" % FONT_SRC)
    vram = data[rec] | (data[rec + 1] << 8)
    old_len = data[rec + 2] | (data[rec + 3] << 8)
    dest = data[rec + 7] | (data[rec + 8] << 8) | (data[rec + 9] << 16)
    if (vram, old_len, dest) != (FONT_VRAM, FONT_LEN, FONT_DEST):
        raise SystemExit("record #%d reads vram $%04X len $%04X dest $%06X, "
                         "expected $%04X/$%04X/$%06X — the table layout or the "
                         "asset has changed"
                         % (n, vram, old_len, dest, FONT_VRAM, FONT_LEN, FONT_DEST))
    # A longer transfer must not run off the end of the source bank.
    if (dest & 0xFFFF) + NEW_LEN > 0x10000:
        raise SystemExit("length $%04X would read past the end of bank $%02X "
                         "from $%04X" % (NEW_LEN, dest >> 16, dest & 0xFFFF))

    src = FONT_SRC & 0x3FFFFF
    sheet = bytearray(sms_lz.decompress(bytes(data), src, 0x8000))
    old_tiles = len(sheet) // 32
    if old_tiles != 418:
        raise SystemExit("font sheet is %d tiles, expected 418 — it has moved "
                         "or been patched" % old_tiles)
    sheet += bytes(NEW_TILES * 32 - len(sheet))          # extend, zero-filled

    glyphs, prov = mkhalfwidth.alphabet()
    letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    placed = {}
    for i, ch in enumerate(letters):
        row, col = divmod(i, SHEET_W)
        top = GLYPH_ROWS[row] + col
        bot = top + SHEET_W
        for tile in (top, bot):
            o = (tile - TILE_BASE) * 32
            if any(sheet[o:o + 32]):
                raise SystemExit("tile $%03X is not blank — refusing to overwrite" % tile)
        tt, bb = encode_glyph(glyphs[ch])
        sheet[(top - TILE_BASE) * 32:(top - TILE_BASE) * 32 + 32] = tt
        sheet[(bot - TILE_BASE) * 32:(bot - TILE_BASE) * 32 + 32] = bb
        placed[ch] = top

    packed = sms_lz.encode(bytes(sheet))
    assert sms_lz.decompress(packed, 0, len(sheet)) == bytes(sheet), "font round-trip failed"

    # Relocation is mandatory even for unchanged data: this project's encoder is
    # weaker than the original's, so the block cannot be written back in place.
    base, bank = next_bank(data)
    write_bank(data, base, packed + bytes((0x10000 - len(packed)) % 0x10000))
    data[rec + 4] = 0x00
    data[rec + 5] = 0x00
    data[rec + 6] = bank
    data[rec + 2] = NEW_LEN & 0xFF
    data[rec + 3] = NEW_LEN >> 8

    fix_checksum(data)
    open(out_path, "wb").write(bytes(data))
    print("patch 16 (font install)")
    print("  font sheet: %d -> %d tiles, %d bytes packed" % (old_tiles, NEW_TILES, len(packed)))
    print("  relocated to bank $%02X, record #%d src repointed" % (bank, n))
    print("  upload length $%04X -> $%04X BYTES (field at $C3:%04X)"
          % (old_len, NEW_LEN, rec - 0x030000 + 2))
    print("  %d glyphs at VRAM tiles $%03X-$%03X / $%03X-$%03X"
          % (len(placed), GLYPH_ROWS[0], GLYPH_ROWS[0] + 15, GLYPH_ROWS[1], GLYPH_ROWS[1] + 9))
    print("  -> %s  sha1 %s" % (out_path, hashlib.sha1(bytes(data)).hexdigest()))
    json.dump({c: placed[c] for c in sorted(placed)},
              open(os.path.join(REPO, "docs", "halfwidth_tiles.json"), "w"), indent=1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stacked", action="store_true")
    ap.add_argument("paths", nargs="+")
    a = ap.parse_args()
    if a.stacked:
        if len(a.paths) != 2:
            raise SystemExit("--stacked needs <in> <out>")
        src, out = a.paths
        if os.path.abspath(src) == os.path.abspath(out):
            raise SystemExit("src == out")
    else:
        src, out = clean_rom(), a.paths[0]
    build(src, out, a.stacked)


if __name__ == "__main__":
    main()
