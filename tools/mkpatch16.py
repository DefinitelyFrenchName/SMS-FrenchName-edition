#!/usr/bin/env python3
"""mkpatch16.py — menu translation: install a half-width Latin alphabet.

STATUS: INCOMPLETE. The ROM side works — the block is extended, the glyphs are
in it, it re-encodes, round-trips, relocates and the record is repointed. But the
extra tiles DO NOT REACH VRAM: a capture of the button-config screen on the built
ROM still shows the font ending at tile $5B5, exactly as vanilla. Do not treat
this as a working patch.

What is known about why, so the next session does not re-derive it:
  * `u16b` in the asset record is NOT the upload length. Bumping it $0800 ->
    $1000 changed nothing, and neither value corresponds to the 182 tiles that
    actually arrive (182 tiles = 2912 words = $0B60).
  * the record's dst is $7E:2000, a WRAM staging buffer — decompression target,
    not the VRAM destination. Something else moves staged bytes to VRAM.
  * probe_menu_survey's DMA log does not show the font upload at all (54
    transfers, all len=$0040 to low VRAM = tilemaps). So the upload happens by a
    route that hook does not observe — another channel, a different code site, or
    PPU-port writes rather than DMA.
  * NEXT STEP: find the real upload. Watch writes to $2116/$2117 (VRAM address)
    and $2118/$2119 (VRAM data) around the font load, or find the code that reads
    $7E:2000. The length lives there, not in the asset record.

STEP 1 of the patch: get the glyphs into the game's font and onto VRAM. The
tilemap edits (replacing Japanese strings with English) come after, and depend on
this working first.

Where the glyphs go
-------------------
The menu font is two compressed blocks. The KANJI block ($C7:07F0) decompresses
to 182 tiles ($300-$3B5 block-relative) and lands at VRAM tile $500, so its
block-relative $3C0-$3FF would land at VRAM $5C0-$5FF — the run proved free on
every menu screen by tools/probe_vram_free.lua (it is reused by the match, which
is fine: a menu font never has to survive gameplay).

The block's four existing blank slots ($368-$36E) are not enough. A 16x16 slot
holds two half-width glyphs, so they would give 8 — against 26 needed. Hence the
block is EXTENDED from 182 to 256 tiles rather than filled.

Relocation is mandatory, not a choice: this project's encoder is weaker than the
original's (the untouched block re-encodes larger), so the block cannot be
written back in place even unchanged. Its only 24-bit pointer is at $C3:BEF2,
which makes repointing a three-byte edit. That groundwork is mkkanji.py's.

Worth knowing: that "only 24-bit pointer" at $C3:BEF2 IS the src field of asset
record #24 ($BE02 + 24*10 = $BEF2). They are the same three bytes, not two
independent things — so the record must be located BEFORE the pointer is written,
or the search finds nothing.

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
KANJI_SRC = (0xC7, 0x07F0)        # bank, offset — the compressed kanji block
KANJI_PTR = 0x00BEF2              # its ONLY 24-bit pointer, in bank $C3
TILE_BASE = 0x300                 # block tile 0 is $300
SHEET_W = 16
NEW_TILES = 0x100                 # extend the block to $300-$3FF
GLYPH_ROWS = (0x3C0, 0x3E0)       # two rows of 16 half-width glyphs
INK = 7                           # flat ink colour; the kana use 1-8

# The asset job table entry for this block, in case the upload length has to grow
JOB_TBL = 0x00BE02                # in bank $C3, 10-byte records


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


def build(src_path, out_path, stacked=False):
    data = bytearray(open(src_path, "rb").read())
    sha = hashlib.sha1(data).hexdigest()
    if not stacked and sha != CLEAN_SHA1:
        raise SystemExit("source is not the clean ROM (%s); pass --stacked to "
                         "build on top of another patch" % sha[:12])

    B3 = 0x030000
    want = bytes([KANJI_SRC[1] & 0xFF, KANJI_SRC[1] >> 8, KANJI_SRC[0]])
    if bytes(data[B3 + KANJI_PTR:B3 + KANJI_PTR + 3]) != want:
        raise SystemExit("kanji font pointer at $C3:%04X is not %02X:%04X — has "
                         "another patch already moved it?"
                         % (KANJI_PTR, KANJI_SRC[0], KANJI_SRC[1]))

    src = ((KANJI_SRC[0] - 0xC0) << 16) | KANJI_SRC[1]
    sheet = bytearray(sms_lz.decompress(bytes(data), src, 0x8000))
    old_tiles = len(sheet) // 32
    if old_tiles != 0xB6:
        raise SystemExit("kanji block is %d tiles, expected 182 — it has moved "
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

    # Find the upload record BEFORE touching anything: $C3:BEF2 — described in
    # mkkanji.py as the block's "only 24-bit pointer" — is in fact the src field
    # of asset-table record #24 ($BE02 + 24*10 = $BEF2). They are the same three
    # bytes. Writing the pointer first and then searching for the old value finds
    # nothing, which is exactly what the first version of this builder did.
    rec = None
    for n in range(59):
        o = B3 + JOB_TBL + n * 10
        s = data[o] | (data[o + 1] << 8) | (data[o + 2] << 16)
        if s == ((KANJI_SRC[0] << 16) | KANJI_SRC[1]):
            rec = (n, o)
            break
    if rec is None:
        raise SystemExit("no asset-table record points at the kanji block")
    n, o = rec
    if o != B3 + KANJI_PTR:
        raise SystemExit("record #%d is at $C3:%04X, not the expected $C3:%04X"
                         % (n, o - B3, KANJI_PTR))

    base, bank = next_bank(data)
    write_bank(data, base, packed + bytes((0x10000 - len(packed)) % 0x10000))
    data[o] = 0x00
    data[o + 1] = 0x00
    data[o + 2] = bank
    old_len = data[o + 8] | (data[o + 9] << 8)
    new_len = NEW_TILES * 32 // 2                        # VRAM transfers are in WORDS
    data[o + 8] = new_len & 0xFF
    data[o + 9] = new_len >> 8

    fix_checksum(data)
    open(out_path, "wb").write(bytes(data))
    print("patch 16 (font install)")
    print("  kanji block: %d -> %d tiles, %d bytes packed" % (old_tiles, NEW_TILES, len(packed)))
    print("  relocated to bank $%02X, pointer at $C3:%04X repointed" % (bank, KANJI_PTR))
    print("  asset record #%d: upload length $%04X -> $%04X words" % (n, old_len, new_len))
    print("  %d glyphs at block tiles $%03X-$%03X / $%03X-$%03X  (VRAM $5C0+)"
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
