#!/usr/bin/env python3
"""Patch 4: replace the title-screen red subtitle with "FrenchName ver. 0.4",
and swap the first copyright line to the Big Zam edition's "(C)MOONLIGHT FIGHT SOCIETY"
(second line "(C)ANGEL 1994" untouched — it shares tiles/palette with the original).

Mechanism (Big-Zam-style, no LZSS encoder needed): the title CHR loader at $C3:B81F
calls `JSL $80:8C43` (which DMAs all loaded title graphics — including the subtitle —
into VRAM), then PLB/RTL. We repoint that JSL to a stub in an appended bank. The stub
runs the original $80:8C43 (subtitle now in VRAM, still force-blank) then DMAs our 42
custom subtitle tiles over VRAM tiles 0x10D-0x151 plus the 54 credit-line tiles over
0x0C2-0x0FC, then RTLs. Logo, menu, and the second copyright line are untouched.

Builds from any input ROM (clean or the combined build); appended bank + hook operand
are computed from the ROM size, so it stacks with patches 1-3.
"""
import sys
from hashlib import sha1
from pathlib import Path as _P
REPO = _P(__file__).resolve().parent.parent  # repo root (cwd-independent)
sys.path.insert(0, str(REPO / "tools"))
from smspaths import clean_rom, require_source, check_not_inplace, BUNDLE_VERSION, fix_checksum, trim_banks, next_bank, write_bank  # noqa: E402
import texttiles as T  # noqa: E402

CLEAN = clean_rom()

# Detection fingerprint (p4) — consumed by tools/mksigs.py to generate the
# regression suite's SIGS table. ONLY bytes invariant across stub-layout and
# bank-stacking changes: JSL operand low bytes at the title-CHR hook: the stub is structurally FIRST in the
# appended bank (offset 0); vanilla operand is 43 8C. Bank byte varies with stacking.
SIG = [(0x3B820, 0x00), (0x3B821, 0x00)]
CLEAN_SHA1 = "bc0e29ee383574443226695215496eb0d09aaa1c"
HOOK = 0x3B81F           # JSL $808C43 in the title CHR loader tail
HOOK_OLD = bytes.fromhex("22438c80")
TEXT = f"FrenchName v.{BUNDLE_VERSION}"   # default subtitle (single source: smspaths.BUNDLE_VERSION); override with --text
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

# Copyright line 1 (BG1 tilemap rows 23/24, cols 2-29): 3 contiguous VRAM runs covering
# the 54 tiles Big Zam changes. The (C) glyph (0x0C1 top / 0x0D1 bottom) is identical in
# clean and BZ, so it's skipped; line 2 "(C)ANGEL 1994" (tiles 0x0ED-0x11C gaps) is
# untouched. 0x0EC/0x0FC are blank in BZ (the Latin line is shorter than the kanji one).
CREDIT_RUNS = [
    (0x0C2, list(range(0x0C2, 0x0D0))),
    (0x0D2, list(range(0x0D2, 0x0ED))),
    (0x0F0, list(range(0x0F0, 0x0FD))),
]

# "(C)MOONLIGHT FIGHT SOCIETY" 4bpp tile data, lifted verbatim from the Big Zam edition's
# title-screen VRAM (traces/titlevram_bz_700.bin via tools/probe_title_vram.lua) so it
# renders pixel-identically. BZ stores these only in a packed/injected form, hence the
# VRAM extraction. Order matches CREDIT_RUNS. Palette 6 verified identical clean vs BZ.
CREDIT_TILES_HEX = [
    "000000c0c0e000d010e800f8089c081c000000c000e020f010f890f8089c081c",  # tile 0x0C2
    "0000000000600090609000f850f850f800000000006060f060f050f850f850f8",  # tile 0x0C3
    "0000000000300049314a00fb52ff52ff0000000000303079317b51fb52ff52ff",  # tile 0x0C4
    "00000000007c0082867900870103010300000000007c7cfe86ff028701030103",  # tile 0x0C5
    "00000000000700181827003820f020f0000000000007071f183f103820f020f0",  # tile 0x0C6
    "0000000000c3002462950077123f123f0000000000c3c3e762f72277123f123f",  # tile 0x0C7
    "0000000000010082814200c341e32173000000000001018381c381c341e32173",  # tile 0x0C8
    "00000000002000d020d000f020f020f000000000002020f020f020f020f020f0",  # tile 0x0C9
    "00000000004000a343a400ef48fc48fc00000000004040e343e744ef48fc48fc",  # tile 0x0CA
    "0000000000fc000300fd00010001003d0000000000fcfcff00fd00010001003d",  # tile 0x0CB
    "0000000000800041804100c180c180ff00000000008080c180c180c180c180ff",  # tile 0x0CC
    "0000000000bf0040847b00ce84ce84ce0000000000bfbfff84ff84ce84ce84ce",  # tile 0x0CD
    "0000000000810042018200030103010300000000008181c30183010301030103",  # tile 0x0CE
    "0000000000f9000601fa0083018301f30000000000f9f9ff01fb0183018301f3",  # tile 0x0CF
    "081c089c00f810e800d0c0e000c00000081c089c90f810f820f000e000c00000",  # tile 0x0D2
    "48fd48fd00fd45aa00aa42e70042000048fd48fd48fd45ef45ef00e700420000",  # tile 0x0D3
    "92ff92ff00ff11aa00aa10390010000092ff92ff92ff11bb11bb003900100000",  # tile 0x0D4
    "0103010300030285007978fe00780000010301030103028786ff00fe00780000",  # tile 0x0D5
    "20f020f000f010280027071f0007000020f020f020f01038183f001f00070000",  # tile 0x0D6
    "123f123f003f2255009582e700820000123f123f123f227762f700e700820000",  # tile 0x0D7
    "113b113b001f050a000a030700030000113b113b091f050f050f000700030000",  # tile 0x0D8
    "20f020f000f020d000df3fff003f000020f020f020f020f020ff00ff003f0000",  # tile 0x0D9
    "48fc48fc00fc44aa00a541e30041000048fc48fc48fc44ee42e700e300410000",  # tile 0x0DA
    "3c7f043f000f040b00fbf8fd00f800003c7f043f040f040f04ff00fd00f80000",  # tile 0x0DB
    "ffff80ff00c18041004180c100800000ffff80ff80c180c180c100c100800000",  # tile 0x0DC
    "84ce84ce00ce844a004a84ce0084000084ce84ce84ce84ce84ce00ce00840000",  # tile 0x0DD
    "0103010300030102000201030001000001030103010301030103000300010000",  # tile 0x0DE
    "f1fb01f3008301820082018300010000f1fb01f3018301830183008300010000",  # tile 0x0DF
    "000000000003008c0c9300bc20f020f0000000000003038f0c9f10bc20f020f0",  # tile 0x0E0
    "0000000000f2000d02f50007020702f70000000000f2f2ff02f70207020702f7",  # tile 0x0E1
    "000000000002000502050007020702ff000000000002020702070207020702ff",  # tile 0x0E2
    "0000000000fe000110ee0038103810380000000000fefeff10fe103810381038",  # tile 0x0E3
    "0000000000030004040b000e040e02070000000000030307040f040e040e0207",  # tile 0x0E4
    "0000000000c1002606c9000e081c081c0000000000c1c1e706cf040e081c081c",  # tile 0x0E5
    "0000000000f0000818e4001c040f040f0000000000f0f0f818fc081c040f040f",  # tile 0x0E6
    "00000000001f0020205f00e080c080c000000000001f1f3f207f40e080c080c0",  # tile 0x0E7
    "00000000002700d8245b007e247e247f00000000002727ff247f247e247e247f",  # tile 0x0E8
    "0000000000ef001001ee0003010301c30000000000efefff01ef0103010301c3",  # tile 0x0E9
    "0000000000e8001404ea008e028702870000000000e8e8fc04ee048e02870287",  # tile 0x0EA
    "0000000000200050205000e080c080c00000000000202070207040e080c080c0",  # tile 0x0EB
    "0000000000000000000000000000000000000000000000000000000000000000",  # tile 0x0EC
    "20f120f000f010a80097078f0007000020f120f020f010b8089f008f00070000",  # tile 0x0F0
    "f3ff12ff003f122d00ede2f700e20000f3ff12ff123f123f12ff00f700e20000",  # tile 0x0F1
    "feff02ff000702050005020700020000feff02ff020702070207000700020000",  # tile 0x0F2
    "1038103800381028002810380010000010381038103810381038003800100000",  # tile 0x0F3
    "01030001000000000007070f0007000001030001000000000007000f00070000",  # tile 0x0F4
    "089c88dc00fc44aa00a981c700810000089c88dc48fc44ee46ef00c700810000",  # tile 0x0F5
    "040f040f000f081400e4e0f800e00000040f040f040f081c18fc00f800e00000",  # tile 0x0F6
    "80c080c000c040a0005f1f3f001f000080c080c080c040e0207f003f001f0000",  # tile 0x0F7
    "277f247f007e245a005b27ff00270000277f247f247e247e247f00ff00270000",  # tile 0x0F8
    "c1e301c30003010200e2e1f300e10000c1e301c30103010301e300f300e10000",  # tile 0x0F9
    "0183018300830182008201830001000001830183018301830183008300010000",  # tile 0x0FA
    "0080008000800080008000800000000000800080008000800080008000000000",  # tile 0x0FB
    "0000000000000000000000000000000000000000000000000000000000000000",  # tile 0x0FC
]

def _credit_tiles():
    """Return {tile_id: 32-byte 4bpp} for the Big Zam credit line."""
    ids = [tid for _, run in CREDIT_RUNS for tid in run]
    assert len(ids) == len(CREDIT_TILES_HEX)
    return {tid: bytes.fromhex(h) for tid, h in zip(ids, CREDIT_TILES_HEX)}

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

def build(src_path, out_path, text=TEXT, style=STYLE, credit=True):
    data = bytearray(open(src_path, "rb").read())
    # trim trailing all-zero padding to a 64K boundary base
    data = trim_banks(data)
    assert data[HOOK:HOOK+4] == HOOK_OLD, f"hook bytes: {data[HOOK:HOOK+4].hex()}"

    tiles = _subtitle_tiles(text, style)
    runs = list(RUNS)
    if credit:
        tiles.update(_credit_tiles())
        runs += CREDIT_RUNS
    # tile data laid out group by group, in run order
    tiledata = bytearray()
    run_srcoff = []  # source offset (within our data blob) for each run
    for _, ids in runs:
        run_srcoff.append(len(tiledata))
        for tid in ids:
            tiledata += tiles[tid]

    # --- assemble the stub ---
    # appended bank starts at a 64K boundary; stub first, tiles after.
    bankbase, stub_snes_bank = next_bank(data)
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
        for (vmadd, ids), soff in zip(runs, run_srcoff):
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
    write_bank(data, bankbase, blob)   # 64K-fit + virgin-bank guards (#27)

    # repoint the hook JSL to the stub
    data[HOOK:HOOK+4] = bytes([0x22, stub_addr & 0xFF, (stub_addr >> 8) & 0xFF, stub_snes_bank])

    # header title (keep FrenchName identity) + checksum + pad to power-of-two-ish
    data[0xFFC0:0xFFD5] = b"\xBE\xB0\xD7\xB0\xD1\xB0\xDDS FrenchName  "
    data += b"\x00" * ((len(data) + 0x7FFFF) // 0x80000 * 0x80000 - len(data))
    fix_checksum(data)

    open(out_path, "wb").write(data)
    print(f"wrote {out_path} from {src_path}: stub@bank {stub_snes_bank:#04x} "
          f"({len(stub)}B) + {len(tiledata)}B tiles, {len(data):#x} bytes, "
          f"sha1={sha1(bytes(data)).hexdigest()}")


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(
        description="Patch the title subtitle. Bump the version by changing --text.")
    ap.add_argument("src", nargs="?", default=CLEAN, help="input ROM (clean or combined build)")
    ap.add_argument("out", nargs="?", default=str(REPO / "build/sms_title.sfc"), help="output ROM path")
    ap.add_argument("--text", default=TEXT,
                    help=f'subtitle text, must fit the 168px strip (proportional font; default: "{TEXT}")')
    ap.add_argument("--style", default=STYLE, choices=["white_red", "red_white", "red"],
                    help=f"glyph treatment (default: {STYLE})")
    ap.add_argument("--no-credit", action="store_true",
                    help='keep the original first copyright line (skip the Big Zam '
                         '"(C)MOONLIGHT FIGHT SOCIETY" swap)')
    ap.add_argument("--stacked", action="store_true",
                    help="src is an already-patched ROM (builder chaining); skips the clean-SHA gate")
    a = ap.parse_args()
    check_not_inplace(a.src, a.out)
    require_source(a.src, a.stacked)
    build(a.src, a.out, a.text, a.style, credit=not a.no_credit)
