"""One-build experiment: point the bracket's codec-1 entry (e1) at OUR 2bpp
glyph tiles for BG3 instead of the 4bpp BG1/BG2 font, and see what breaks.

It answers two questions in a single run:
  * does e3 (the codec-2 BG3 sheet, which runs AFTER e1) clobber word $5800?
  * is the 4bpp font at $2000 actually needed here, or does it survive from the
    tournament SELECT screen (i.e. does this transition clear VRAM)?
If the names render AND the tree text survives, no script relocation is needed.
"""
import sys, hashlib
sys.path.insert(0, 'tools'); sys.path.insert(0, 'tools/saturn')
import sms_lz, mkhalfwidth
from smspaths import clean_rom, fix_checksum, next_bank, write_bank

NAMES = ["MOON","MERCURY","MARS","JUPITER","VENUS","CHIBI","PLUTO","NEPTUNE","URANUS"]
LEFT, RIGHT, STRIDE = 0x1FE119, 0x1FE38F, 0x46
VMADD = (0x7CE0, 0x7CF0)
E1 = (0xDFA43E & 0x3FFFFF) + 1 + 7          # entry e1 (codec-2 e0 is 7 bytes)
BASE_TILE = 0x100                            # first glyph tile in the BG3 sheet
SPAN = 0x32                                  # tiles $100-$131 uploaded contiguously

def enc2bpp(rows, ink=1):
    out = []
    for half in (0, 8):
        t = bytearray(16)
        for y in range(8):
            for x in range(8):
                if rows[half + y][x] != "#":
                    continue
                b = 7 - x
                t[y*2]   |= (ink & 1) << b
                t[y*2+1] |= ((ink >> 1) & 1) << b
        out.append(bytes(t))
    return out

rom = bytearray(open(clean_rom(), 'rb').read())
glyphs, _ = mkhalfwidth.alphabet()
letters = sorted(set("".join(NAMES)))
tops = list(range(BASE_TILE, BASE_TILE + 0x10)) + [BASE_TILE + 0x20, BASE_TILE + 0x21]
assert len(letters) <= len(tops), f"{len(letters)} letters vs {len(tops)} slots"
sheet = bytearray(SPAN * 16)
placed = {}
for ch, top in zip(letters, tops):
    t, b = enc2bpp(glyphs[ch])
    sheet[(top - BASE_TILE)*16:(top - BASE_TILE + 1)*16] = t
    sheet[(top + 0x10 - BASE_TILE)*16:(top + 0x10 - BASE_TILE + 1)*16] = b
    placed[ch] = top
packed = sms_lz.encode_lz(bytes(sheet))
assert sms_lz.decompress(packed, 0, len(sheet)) == bytes(sheet), "round-trip"

bankbase, bank = next_bank(rom)
blob = bytearray(0x10000)
AT = 0x8000                                   # >= $8000 so the $A8 mirror is ROM
blob[AT:AT+len(packed)] = packed
write_bank(rom, bankbase, bytes(blob))

# e1: src -> our stream, vmadd -> $5800 (BG3 tile $100), len -> SPAN*16
rom[E1+0], rom[E1+1], rom[E1+2] = AT & 0xFF, AT >> 8, bank
rom[E1+4], rom[E1+5] = 0x00, 0x58
rom[E1+6], rom[E1+7] = (SPAN*16) & 0xFF, (SPAN*16) >> 8

# the 18 records -> our tile ids
for side, (base, vm) in enumerate(zip((LEFT, RIGHT), VMADD)):
    for i, name in enumerate(NAMES):
        o = base + i*STRIDE
        cells = [rom[o+6+k] | rom[o+7+k] << 8 for k in range(0, 0x20, 2)]
        attr = next((c & 0xFC00 for c in cells if c & 0x3FF), 0x2000)
        span = range(14-len(name), 14) if side == 0 else range(3, 3+len(name))
        new = list(cells)
        for c in range(16):
            if (side == 0 and c <= 13) or (side == 1 and 3 <= c <= 15):
                new[c] = 0
        for c, ch in zip(span, name):
            new[c] = attr | placed[ch]
        for k, w in enumerate(new):
            rom[o+6+k*2], rom[o+7+k*2] = w & 0xFF, w >> 8
            lo = w & 0x3FF
            bw = (attr | (lo + 0x10)) if lo else 0
            rom[o+6+0x20+k*2], rom[o+7+0x20+k*2] = bw & 0xFF, bw >> 8

fix_checksum(rom)
open(sys.argv[1], 'wb').write(rom)
print(f"wrote {sys.argv[1]} sha1={hashlib.sha1(rom).hexdigest()}")
print(f"  {len(letters)} letters -> tiles ${tops[0]:03X}.. ; stream {len(packed)} B at ${bank:02X}:{AT:04X}")
print("  e1 now: vmadd $5800 len $%04X" % (SPAN*16))
