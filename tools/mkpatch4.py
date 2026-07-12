#!/usr/bin/env python3
"""Patch 4: replace the title-screen red subtitle with "FrenchName ver. 0.4".

Mechanism (Big-Zam-style, no LZSS encoder needed): the title CHR loader at $C3:B81F
calls `JSL $80:8C43` (which DMAs all loaded title graphics — including the subtitle —
into VRAM), then PLB/RTL. We repoint that JSL to a stub in an appended bank. The stub
runs the original $80:8C43 (subtitle now in VRAM, still force-blank) then DMAs our 42
custom subtitle tiles over VRAM tiles 0x10D-0x151, then RTLs. Only the subtitle tiles
change; logo, menu, and copyright are untouched.

Builds from any input ROM (clean or the combined build); appended bank + hook operand
are computed from the ROM size, so it stacks with patches 1-3.
"""
import sys
from hashlib import sha1
sys.path.insert(0, "tools")
import texttiles as T  # noqa: E402

CLEAN = "Bishoujo Senshi Sailormoon S - Jougai Rantou! Shuyaku Soudatsusen (Japan).sfc"
CLEAN_SHA1 = "bc0e29ee383574443226695215496eb0d09aaa1c"
HOOK = 0x3B81F           # JSL $808C43 in the title CHR loader tail
HOOK_OLD = bytes.fromhex("22438c80")
TEXT = "FrenchName ver. 0.4"   # default subtitle; override with --text
STYLE = "white_red"            # default treatment;  override with --style

# 6 contiguous VRAM runs covering the 42 subtitle tiles (tile ids -> VMADD word = id*16).
RUNS = [
    (0x10D, [0x10D, 0x10E, 0x10F]),
    (0x11D, [0x11D, 0x11E, 0x11F]),
    (0x120, list(range(0x120, 0x130))),
    (0x130, list(range(0x130, 0x140))),
    (0x140, [0x140, 0x141]),
    (0x150, [0x150, 0x151]),
]

def _subtitle_tiles(text, style):
    """Return {tile_id: 32-byte 4bpp} for `text` rendered in `style`."""
    missing = sorted({c for c in text if c not in T.G})
    if missing:
        raise SystemExit(f"error: no glyph(s) for {missing} in texttiles.py — add them there first")
    tops, bots = T.render(text, style)
    m = {}
    for slot, tile in zip(T.ROW13, tops): m[slot] = tile
    for slot, tile in zip(T.ROW14, bots): m[slot] = tile
    return m

def build(src_path, out_path, text=TEXT, style=STYLE):
    data = bytearray(open(src_path, "rb").read())
    # trim trailing all-zero padding to a 64K boundary base
    while len(data) >= 0x10000 and data[-0x10000:] == bytes(0x10000):
        data = data[:-0x10000]
    assert data[HOOK:HOOK+4] == HOOK_OLD, f"hook bytes: {data[HOOK:HOOK+4].hex()}"

    tiles = _subtitle_tiles(text, style)
    # tile data laid out group by group, in run order
    tiledata = bytearray()
    run_srcoff = []  # source offset (within our data blob) for each run
    for _, ids in RUNS:
        run_srcoff.append(len(tiledata))
        for tid in ids:
            tiledata += tiles[tid]

    # --- assemble the stub ---
    # appended bank starts at a 64K boundary; stub first, tiles after.
    bankbase = (len(data) + 0xFFFF) & ~0xFFFF
    while len(data) < bankbase:
        data += b"\x00"
    stub_snes_bank = 0xC0 + (bankbase >> 16)
    stub_addr = bankbase & 0xFFFF          # == 0x0000
    tiles_fileoff = None  # fill after we know stub length

    def asm(tiles_off):
        b = bytearray()
        tbank = 0xC0 + (tiles_off >> 16)
        taddr = tiles_off & 0xFFFF
        b += bytes([0x08])                       # PHP
        b += bytes([0x8B])                       # PHB
        b += bytes([0x22, 0x43, 0x8C, 0x80])     # JSL $808C43 (original load)
        b += bytes([0xE2, 0x20])                 # SEP #$20  (8-bit A)
        b += bytes([0xC2, 0x10])                 # REP #$10  (16-bit X/Y, harmless)
        b += bytes([0xA9, 0x80, 0x8D, 0x15, 0x21])  # LDA #$80; STA $2115 (VMAIN word-inc)
        b += bytes([0xA9, 0x01, 0x8D, 0x00, 0x43])  # LDA #$01; STA $4300 (mode 1: 2118/2119)
        b += bytes([0xA9, 0x18, 0x8D, 0x01, 0x43])  # LDA #$18; STA $4301 (dest $2118)
        b += bytes([0xA9, tbank, 0x8D, 0x04, 0x43]) # LDA #tbank; STA $4304 (src bank)
        VBASE = 0x2000  # BG1 CHR base (word); tile T CHR is at word VBASE + T*16
        for (vmadd, ids), soff in zip(RUNS, run_srcoff):
            size = len(ids) * 32
            src = (taddr + soff) & 0xFFFF
            vword = VBASE + vmadd * 16
            # SEP #$20 already; VMADD & src & size need 16-bit stores -> REP #$20 around them
            b += bytes([0xC2, 0x20])                       # REP #$20
            b += bytes([0xA9, vword & 0xFF, (vword >> 8) & 0xFF, 0x8D, 0x16, 0x21])  # LDA #vword; STA $2116
            b += bytes([0xA9, src & 0xFF, (src >> 8) & 0xFF, 0x8D, 0x02, 0x43])      # LDA #src; STA $4302
            b += bytes([0xA9, size & 0xFF, (size >> 8) & 0xFF, 0x8D, 0x05, 0x43])    # LDA #size; STA $4305
            b += bytes([0xE2, 0x20])                       # SEP #$20
            b += bytes([0xA9, 0x01, 0x8D, 0x0B, 0x42])     # LDA #$01; STA $420B (trigger DMA0)
        b += bytes([0xAB])                       # PLB
        b += bytes([0x28])                       # PLP
        b += bytes([0x6B])                       # RTL
        return bytes(b)

    # two-pass: length is stable regardless of tiles_off value, so compute directly
    stub = asm(0)  # placeholder to get length
    tiles_fileoff = bankbase + len(stub)
    stub = asm(tiles_fileoff)                    # real, with correct source bank/addr

    blob = bytearray(stub) + tiledata
    data[bankbase:bankbase + len(blob)] = blob

    # repoint the hook JSL to the stub
    data[HOOK:HOOK+4] = bytes([0x22, stub_addr & 0xFF, (stub_addr >> 8) & 0xFF, stub_snes_bank])

    # header title (keep FrenchName identity) + checksum + pad to power-of-two-ish
    data[0xFFC0:0xFFD5] = b"\xBE\xB0\xD7\xB0\xD1\xB0\xDDS FrenchName  "
    data += b"\x00" * ((len(data) + 0x7FFFF) // 0x80000 * 0x80000 - len(data))
    _fix_checksum(data)

    open(out_path, "wb").write(data)
    print(f"wrote {out_path} from {src_path}: stub@bank {stub_snes_bank:#04x} "
          f"({len(stub)}B) + {len(tiledata)}B tiles, {len(data):#x} bytes, "
          f"sha1={sha1(bytes(data)).hexdigest()}")

def _fix_checksum(data):
    size = len(data); chk_size = 0x80000
    while chk_size <= size: chk_size <<= 1
    if chk_size == size:
        chk = sum(data)
    else:
        cd = data[chk_size//2:]
        while len(cd) < chk_size//2: cd += cd[len(cd)-chk_size:]
        chk = sum(data[:chk_size//2]) + sum(cd)
    data[0xFFDE] = chk & 0xFF; data[0xFFDF] = chk >> 8 & 0xFF
    data[0xFFDC] = data[0xFFDE] ^ 0xFF; data[0xFFDD] = data[0xFFDF] ^ 0xFF

if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(
        description="Patch the title subtitle. Bump the version by changing --text.")
    ap.add_argument("src", nargs="?", default=CLEAN, help="input ROM (clean or combined build)")
    ap.add_argument("out", nargs="?", default="build/sms_title.sfc", help="output ROM path")
    ap.add_argument("--text", default=TEXT,
                    help=f'subtitle text, <=21 chars (default: "{TEXT}")')
    ap.add_argument("--style", default=STYLE, choices=["white_red", "red_white", "red"],
                    help=f"glyph treatment (default: {STYLE})")
    a = ap.parse_args()
    if a.src == CLEAN:
        assert sha1(open(a.src, "rb").read()).hexdigest() == CLEAN_SHA1, "clean hash mismatch"
    build(a.src, a.out, a.text, a.style)
