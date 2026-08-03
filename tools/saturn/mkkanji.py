#!/usr/bin/env python3
"""mkkanji.py — author 16x16 menu-font glyphs for characters SMS lacks.

The menu font is two compressed blocks (codec = tools/saturn/sms_lz.py, the same
one the movelists use):

    $C3:48D0   kana and general glyphs
    $C7:07F0   the KANJI block — tiles based at 0x300, so a tile's data sits at
               (tile - 0x300) * 32

A 16x16 glyph is four tiles: T, T+1, T+0x10, T+0x11. The sheet has 20 blank
glyph slots; four of them ($368-$36E) sit immediately after the existing kanji.

Style, copied from the game's own kanji (時/空/扉): a dark outline in colour 1
with the stroke interior running a light vertical ramp. Reproducing that exactly
from a TTF is not realistic at 16x16, so this uses the same two ingredients —
outline 1, interior ramp — which reads as the same family on screen.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parent.parent.parent
FONT = "/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc"
KANJI_BLOCK = (0xC7, 0x07F0)      # bank, offset
KANJI_TILE_BASE = 0x300
RAMP = [3, 4, 5, 6, 7, 8, 9, 10, 11]      # interior, top to bottom


def render(ch, size=15, dx=0, dy=0):
    """-> 16x16 grid of palette indices."""
    img = Image.new("L", (16, 16), 0)
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(FONT, size)
    bbox = d.textbbox((0, 0), ch, font=f)
    d.text(((16 - (bbox[2] - bbox[0])) // 2 - bbox[0] + dx,
            (16 - (bbox[3] - bbox[1])) // 2 - bbox[1] + dy), ch, font=f, fill=255)
    px = img.load()
    ink = [[px[x, y] > 96 for x in range(16)] for y in range(16)]
    out = [[0] * 16 for _ in range(16)]
    for y in range(16):
        for x in range(16):
            if ink[y][x]:
                out[y][x] = RAMP[min(len(RAMP) - 1, y * len(RAMP) // 16)]
    # outline: any blank pixel touching ink, in colour 1 — the game's own kanji
    # carry that dark edge and without it the glyph looks unrelated to them
    for y in range(16):
        for x in range(16):
            if out[y][x]:
                continue
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < 16 and 0 <= nx < 16 and ink[ny][nx]:
                    out[y][x] = 1
                    break
    return out


def to_tiles(g):
    """-> {tile offset within the glyph: 32 bytes} for T, T+1, T+0x10, T+0x11."""
    out = {}
    for key, (oy, ox) in {0: (0, 0), 1: (0, 8), 0x10: (8, 0), 0x11: (8, 8)}.items():
        data = bytearray(32)
        for y in range(8):
            for x in range(8):
                v = g[oy + y][ox + x]
                b = 7 - x
                data[y * 2] |= (v & 1) << b
                data[y * 2 + 1] |= ((v >> 1) & 1) << b
                data[16 + y * 2] |= ((v >> 2) & 1) << b
                data[16 + y * 2 + 1] |= ((v >> 3) & 1) << b
        out[key] = bytes(data)
    return out


def preview(chars, path, scale=12):
    img = Image.new("RGB", (16 * scale * len(chars), 16 * scale), (16, 16, 24))
    d = ImageDraw.Draw(img)
    for i, ch in enumerate(chars):
        g = render(ch)
        for y in range(16):
            for x in range(16):
                v = g[y][x]
                if not v:
                    continue
                c = (40, 40, 60) if v == 1 else (60 + v * 16,) * 3
                d.rectangle([(i * 16 + x) * scale, y * scale,
                             (i * 16 + x) * scale + scale - 1, y * scale + scale - 1], fill=c)
    img.save(path)
    return path


if __name__ == "__main__":
    chars = sys.argv[1] if len(sys.argv) > 1 else "沈黙玉座"
    out = sys.argv[2] if len(sys.argv) > 2 else "/tmp/kanji.png"
    print("preview:", preview(chars, out))


# ---- patching the font block --------------------------------------------
# The kanji block's ONLY 24-bit pointer in the ROM is at $C3:BEF2 (`F0 07 C7`),
# so relocating it is a three-byte edit. Relocation is necessary rather than
# optional: our encoder is weaker than the original's (the untouched block
# re-encodes to 0x13AD against the original 0xD5B), so nothing can be patched in
# place, changed or not.
KANJI_PTR = 0x00BEF2          # in bank $C3
FREE_SLOTS = [0x368, 0x36A, 0x36C, 0x36E]     # blank, right after the kanji


def patch_font(data, chars, blob_at):
    """Add `chars` to the kanji block, relocate it, repoint. -> (bank, offset)."""
    import sms_lz
    B3 = 0x030000
    src = ((KANJI_BLOCK[0] - 0xC0) << 16) | KANJI_BLOCK[1]
    if bytes(data[B3 + KANJI_PTR:B3 + KANJI_PTR + 3]) != bytes(
            [KANJI_BLOCK[1] & 0xFF, KANJI_BLOCK[1] >> 8, KANJI_BLOCK[0]]):
        raise SystemExit(f"kanji font pointer at $C3:{KANJI_PTR:04X} is not "
                         f"{KANJI_BLOCK[0]:02X}:{KANJI_BLOCK[1]:04X}")
    sheet = bytearray(sms_lz.decompress(bytes(data), src))
    if len(chars) > len(FREE_SLOTS):
        raise SystemExit(f"{len(chars)} glyphs but only {len(FREE_SLOTS)} free slots")
    placed = {}
    for ch, slot in zip(chars, FREE_SLOTS):
        for key, tile in ((0, slot), (1, slot + 1), (0x10, slot + 0x10), (0x11, slot + 0x11)):
            o = (tile - KANJI_TILE_BASE) * 32
            if o + 32 > len(sheet):
                raise SystemExit(f"slot {slot:03X} is outside the kanji block")
            if any(sheet[o:o + 32]):
                raise SystemExit(f"slot {slot:03X} is NOT blank — refusing to "
                                 f"overwrite an existing glyph")
        for key, blob in to_tiles(render(ch)).items():
            tile = slot + key
            o = (tile - KANJI_TILE_BASE) * 32
            sheet[o:o + 32] = blob
        placed[ch] = slot
    packed = sms_lz.encode(bytes(sheet))
    bank, off = blob_at(len(packed))
    data[((bank - 0xC0) << 16) + off:((bank - 0xC0) << 16) + off + len(packed)] = packed
    data[B3 + KANJI_PTR:B3 + KANJI_PTR + 3] = bytes([off & 0xFF, off >> 8, bank])
    return placed, bank, off, len(packed)
