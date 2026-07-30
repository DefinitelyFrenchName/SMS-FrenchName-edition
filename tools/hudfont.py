#!/usr/bin/env python3
"""Compact 2bpp HUD glyph font for patch-10 status labels (GC/REVERSAL/PUNISH/TECH).

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
    # patch-11 additions (menu vocabulary; keep the 16 above untouched — patch 10 shares them)
    "B": ["11110","10001","10001","11110","10001","10001","11110"],
    "D": ["11110","10001","10001","10001","10001","10001","11110"],
    "F": ["11111","10000","10000","11110","10000","10000","10000"],
    "J": ["00111","00010","00010","00010","00010","10010","01100"],
    "K": ["10001","10010","10100","11000","10100","10010","10001"],
    "O": ["01110","10001","10001","10001","10001","10001","01110"],
    "W": ["10001","10001","10001","10101","10101","11011","10001"],
    ">": ["10000","11000","11100","11110","11100","11000","10000"],  # menu cursor
    # minus sign (p11 advantage display). Latent bug until 2026-07-30: no glyph
    # existed and glyph_2bpp silently blanked it (issue #39), so negative
    # advantage rendered with no sign.
    "-": ["00000","00000","00000","11110","00000","00000","00000"],
}

COLOR = 3   # 2bpp pixel index for glyph pixels (matches digit outline color)


def glyph_2bpp(ch, color=COLOR):
    """Return the 16-byte 2bpp tile for a letter. Space is a deliberate blank;
    "#" = solid 8x8 backdrop tile in color index 2 (menu panel background).
    Any other unknown character raises (issue #39 — used to blank silently)."""
    if ch == "#":
        return bytes([0x00, 0xFF]) * 8   # every pixel = color 2 (plane1 set)
    out = bytearray(16)
    if ch == " ":
        return bytes(out)
    rows = GLYPHS.get(ch)
    if not rows:
        raise KeyError(f"hudfont: no glyph for {ch!r}")
    for r in range(7):                 # 7 glyph rows, top-aligned at row 0
        bits = rows[r]
        p0 = p1 = 0
        for i, b in enumerate(bits):
            if b == "1":
                x = 1 + i              # x offset 1 (leaves left column blank)
                mask = 1 << (7 - x)
                if color & 1: p0 |= mask
                if color & 2: p1 |= mask
        out[2 * r] = p0
        out[2 * r + 1] = p1
    return bytes(out)


def build_font(letters, color=COLOR):
    """Return (blob, {letter: local_tile_index}) for the given letters, in order.
    color: 2bpp pixel index (patch 10 uses the default 3; patch 11 uses 1 = white --
    the two patches' fonts never coexist on screen: p10 renders only in VS, p11 only
    in training, so the same tile slots may carry different colors per domain)."""
    blob = bytearray()
    idx = {}
    for i, ch in enumerate(letters):
        idx[ch] = i
        blob += glyph_2bpp(ch, color)
    return bytes(blob), idx


if __name__ == "__main__":
    # self-test: render each glyph as ASCII
    for ch in GLYPHS:
        t = glyph_2bpp(ch)
        print(ch + ":")
        for r in range(8):
            p0, p1 = t[2 * r], t[2 * r + 1]
            line = "".join(
                str(((p0 >> (7 - x)) & 1) | (((p1 >> (7 - x)) & 1) << 1)).replace("0", ".")
                for x in range(8))
            print("  " + line)
