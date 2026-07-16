#!/usr/bin/env python3
"""Compact 2bpp HUD glyph font for patch-10 status labels (GC/MEATY/REVERSAL/PUNISH/TECH).

BG3 in this game is 2bpp (mode 1), CHR base word 0x5000. Each glyph is an 8x8 tile packed
2bpp (16 bytes: per row, byte0=plane0, byte1=plane1). We draw 5x7 uppercase letters in
color index 3 (the bright outline color the digit tiles use), index 0 = transparent.

Only the letters the label set needs are defined; add rows to GLYPHS for more.
"""

# 5-wide x 7-tall bitmaps (each row = 5 bits, MSB = leftmost of the 5). Drawn at x offset 1.
GLYPHS = {
    "G": ["01110","10001","10000","10111","10001","10001","01111"],
    "C": ["01110","10001","10000","10000","10000","10001","01110"],
    "M": ["10001","11011","10101","10101","10001","10001","10001"],
    "E": ["11111","10000","10000","11110","10000","10000","11111"],
    "A": ["01110","10001","10001","11111","10001","10001","10001"],
    "T": ["11111","00100","00100","00100","00100","00100","00100"],
    "Y": ["10001","10001","01010","00100","00100","00100","00100"],
    "R": ["11110","10001","10001","11110","10100","10010","10001"],
    "V": ["10001","10001","10001","10001","10001","01010","00100"],
    "S": ["01111","10000","10000","01110","00001","00001","11110"],
    "L": ["10000","10000","10000","10000","10000","10000","11111"],
    "P": ["11110","10001","10001","11110","10000","10000","10000"],
    "U": ["10001","10001","10001","10001","10001","10001","01110"],
    "N": ["10001","11001","10101","10011","10001","10001","10001"],
    "I": ["11111","00100","00100","00100","00100","00100","11111"],
    "H": ["10001","10001","10001","11111","10001","10001","10001"],
}

COLOR = 3   # 2bpp pixel index for glyph pixels (matches digit outline color)


def glyph_2bpp(ch):
    """Return the 16-byte 2bpp tile for a letter, or all-zero for space/unknown."""
    rows = GLYPHS.get(ch)
    out = bytearray(16)
    if not rows:
        return bytes(out)
    for r in range(7):                 # 7 glyph rows, top-aligned at row 0
        bits = rows[r]
        p0 = p1 = 0
        for i, b in enumerate(bits):
            if b == "1":
                x = 1 + i              # x offset 1 (leaves left column blank)
                mask = 1 << (7 - x)
                if COLOR & 1: p0 |= mask
                if COLOR & 2: p1 |= mask
        out[2 * r] = p0
        out[2 * r + 1] = p1
    return bytes(out)


def build_font(letters):
    """Return (blob, {letter: local_tile_index}) for the given letters, in order."""
    blob = bytearray()
    idx = {}
    for i, ch in enumerate(letters):
        idx[ch] = i
        blob += glyph_2bpp(ch)
    return bytes(blob), idx


if __name__ == "__main__":
    # self-test: render each glyph as ASCII
    for ch in GLYPHS:
        t = glyph_2bpp(ch)
        print(ch + ":")
        for r in range(8):
            p0, p1 = t[2 * r], t[2 * r + 1]
            line = "".join(
                (str(((p0 >> (7 - x)) & 1) | (((p1 >> (7 - x)) & 1) << 1)) or ".").replace("0", ".")
                for x in range(8))
            print("  " + line)
