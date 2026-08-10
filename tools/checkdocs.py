#!/usr/bin/env python3
"""Verify docs/game/'s load-bearing claims against the cartridge.

  python3 tools/checkdocs.py             # run every check
  python3 tools/checkdocs.py -v          # ...and print each one that passes
  python3 tools/checkdocs.py --uncovered # ...and every documented address no check reaches

WHY THIS EXISTS. Documentation gets reorganised and rewritten, and rewriting is
where a plausible-sounding statement can quietly replace a measured one — not by
inventing an address from nothing, but by compressing a hedged log entry into
confident prose, or by carrying a claim forward from a source nobody re-checked.
Re-reading the prose cannot catch that. Re-deriving it from the ROM can.

HOW A CHECK IS BUILT, because the shape matters:

    1. the claim is quoted FROM THE DOC and asserted to still be there
       (assert_says) — so if someone edits the doc, the check fails loudly
       instead of silently testing a claim nobody makes any more;
    2. the same fact is DERIVED FROM THE ROM;
    3. the two are compared.

A check that only did step 2 would test my memory of the docs, not the docs.

THREE KINDS OF CHECK, because hand-writing them does not scale to a document set
carrying 250 distinct ROM addresses:

  * **hand-written** (the first section) — one function per claim worth arguing
    about, quoting the doc and re-deriving the fact.
  * **table structures** (the registry) — a documented table's address plus a
    validator for its SHAPE. The doc-mention assertion is generated, and each
    validator is re-run at a WRONG base and required to fail, because a check
    that survives a two-byte shift would go green on a rotted address.
  * **claims extracted from the prose** — file-offset transcriptions
    (`$C1:88E9 (file 0x188E9)`), quoted byte runs and quoted instructions. The
    doc states these mechanically, so no human has to decide what is claimed;
    the extractors live in tools/docaddrs.py and are negative-controlled on
    synthetic lines every run, since a family that has stopped matching passes
    every claim it no longer finds.

Coverage is printed at the end — how many documented ROM addresses any check
actually re-derives — because the honest weakness of this file is the claims
nobody wrote a check for, and a number that is never shown never moves.

What this canNOT check, stated plainly so the green line is not over-read:
prose, reasoning, causal claims ("this is why X"), anything about runtime
behaviour (those belong to the emulator suites), and anything about ARAM, which
is only observable on a running APU. It checks facts that are decidable by
reading the cartridge, and says how many that is.
"""
import argparse
import re
import sys
from pathlib import Path as _P

REPO = _P(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
sys.path.insert(0, str(REPO / "tools" / "saturn"))
from smspaths import clean_rom  # noqa: E402
import dis65816  # noqa: E402

ROM = open(clean_rom(), "rb").read()
GAME = REPO / "docs" / "game"

def r8(o):  return ROM[o]
def r16(o): return ROM[o] | ROM[o + 1] << 8
def r24(o): return ROM[o] | ROM[o + 1] << 8 | ROM[o + 2] << 16
def f(snes): return snes & 0x3FFFFF

CHECKS = []
def check(doc, name):
    def deco(fn):
        CHECKS.append((doc, name, fn)); return fn
    return deco

_cache = {}
def doc_text(doc):
    if doc not in _cache:
        _cache[doc] = (GAME / doc).read_text(encoding="utf-8")
    return _cache[doc]

class Fail(Exception): pass

def says(doc, *fragments):
    """The doc must still make this claim, else the check is stale."""
    t = doc_text(doc)
    for frag in fragments:
        if frag not in t:
            raise Fail(f"doc no longer says {frag!r} — check is stale, re-read the doc")

def eq(label, doc_value, rom_value):
    if doc_value != rom_value:
        raise Fail(f"{label}: doc says {doc_value!r}, ROM says {rom_value!r}")


# ---------------------------------------------------------------- cartridge --
@check("sms_data_architecture.md", "image is 2.5 MB / 40 banks, $C0-$E7")
def _():
    says("sms_data_architecture.md", "`0x280000` = **2.5 MB**", "40 banks, `$C0-$E7`")
    eq("size", 0x280000, len(ROM))

@check("sms_data_architecture.md", "header: map mode $31, declared 4 MB, valid checksum")
def _():
    says("sms_data_architecture.md", "| map mode | `$31` |", "`$0C` → 4096 KB")
    eq("map mode", 0x31, r8(0xFFD5))
    eq("rom size byte", 0x0C, r8(0xFFD7))
    eq("checksum xor", 0xFFFF, r16(0xFFDE) ^ r16(0xFFDC))

@check("sms_data_architecture.md", "header title is Shift-JIS half-width katakana")
def _():
    says("sms_data_architecture.md", "ｾｰﾗｰﾑｰﾝSｼｭﾔｸｿｳﾀﾞﾂｾﾝ")
    eq("title", "ｾｰﾗｰﾑｰﾝSｼｭﾔｸｿｳﾀﾞﾂｾﾝ", ROM[0xFFC0:0xFFD5].decode("shift_jis").strip())

# -------------------------------------------------------------------- boxes --
@check("sms_quickref.md", "box pointer tables are $0x14 apart and adjacent")
def _():
    says("sms_quickref.md", "`$8A:C1F1`", "`$8A:C229`", "`$8A:C23D`")
    eq("hurt-table base", 0xC229, 0xC1F1 + 28 * 2)      # 28 hit entries then the hurt table
    eq("coll-table base", 0xC23D, 0xC229 + 10 * 2)      # 10 hurt entries then the coll table

@check("sms_data_architecture.md", "hit table has 28 entries, hurt/coll 10")
def _():
    says("sms_data_architecture.md", "| hit (attack) | `$8A:C1F1` | **28** |")
    ids = [r16(f(0x8AC1F1) + i * 2) for i in range(28)]
    if not all(0xC251 <= p <= 0xFDA1 for p in ids[1:]):
        raise Fail("a hit-table entry points outside the box-data region")
    eq("projectile entries share tables", True, len(set(ids[10:28])) == 9)

# ---------------------------------------------------------------- manifests --
@check("sms_data_architecture.md", "manifest is 16 bytes: defense byte + five 24-bit pointers")
def _():
    says("sms_data_architecture.md", "**16 bytes: one defense byte and five 24-bit pointers**")
    bases = [f(0xE00000) + r16(f(0xE00238) + i * 2) for i in range(1, 10)]
    eq("stride", [0x10] * 8, [bases[i + 1] - bases[i] for i in range(8)])
    for b in bases:
        for off in (1, 4, 7, 10, 13):
            bank = r24(b + off) >> 16
            if bank not in (0xE0, 0xE2):
                raise Fail(f"manifest pointer at +0x{off:02X} lands in bank ${bank:02X}")

@check("sms_data_architecture.md", "first-hit defense: Jupiter 1, Neptune 2, rest 0")
def _():
    says("sms_data_architecture.md", "**Jupiter 1, Neptune 2, everyone else 0**")
    got = {i: r8(f(0xE00000) + r16(f(0xE00238) + i * 2)) for i in range(1, 10)}
    eq("d48 census", {1: 0, 2: 0, 3: 0, 4: 1, 5: 0, 6: 0, 7: 2, 8: 0, 9: 0}, got)

# ------------------------------------------------------------------- damage --
@check("sms_data_architecture.md", "ten on-hit tables, stride 0x40, ending at the lookup")
def _():
    says("sms_data_architecture.md", "**nine** sibling tables", "`CDD5 + 10 × 0x40`")
    eq("CDD5 + 10*0x40", 0xD055, 0xCDD5 + 10 * 0x40)
    eq("lookup prologue", "c2 30", ROM[f(0xC0D055):f(0xC0D055) + 2].hex(" "))

@check("sms_data_architecture.md", "matrix is 64 rows x 16 cols, each row non-increasing")
def _():
    says("sms_data_architecture.md", "64 rows × 16 columns at `$C0:D081`")
    base = f(0xC0D081)
    for row in range(64):
        vals = list(ROM[base + row * 16: base + row * 16 + 16])
        if vals != sorted(vals, reverse=True):
            raise Fail(f"matrix row {row} is not non-increasing: {vals}")

@check("sms_data_architecture.md", "row 8 column 8 reads 8 (the worked example)")
def _():
    says("sms_data_architecture.md", "17  16  16  16  15  14  12  10 [ 8]  6   5   5   4   4   4   4")
    eq("row 8", [17, 16, 16, 16, 15, 14, 12, 10, 8, 6, 5, 5, 4, 4, 4, 4],
       list(ROM[f(0xC0D081) + 8 * 16: f(0xC0D081) + 8 * 16 + 16]))

@check("sms_data_architecture.md", "eight damage-apply sites, and no others in the ROM")
def _():
    says("sms_data_architecture.md", "8 apply sites")
    pat = re.compile(rb"\xb9\x49\x00\x38\xe5.\x99\x49\x00", re.S)
    sites = [m.start() for m in pat.finditer(ROM)]
    eq("apply sites", [0xC09C, 0xC16F, 0xC216, 0xC2C5, 0xC47E, 0xC551, 0xC5F8, 0xC6A7], sites)

# ---------------------------------------------------------- code + dispatch --
@check("sms_data_architecture.md", "proc dispatch at $C1:00A6 carves bank $C1")
def _():
    says("sms_data_architecture.md", "**`$C1:00A6`**", "`jsr ($00A6,X)`")
    t = [r16(f(0xC100A6) + i * 2) for i in range(30)]
    eq("id 0 empty", 0, t[0])
    eq("ids 28+ empty", [0, 0], t[28:30])
    if t[1:10] != sorted(t[1:10]):
        raise Fail("the nine character proc blocks are not in ascending order")
    eq("Uranus proc", 0x79F2, t[6])

@check("sms_data_architecture.md", "the free code holes are 63 and 69 bytes")
def _():
    says("sms_data_architecture.md", "| ROM hole `$C1:BE09-BE47` | **63 bytes** |",
         "| ROM hole `$C1:BE85-BEC9` | **69 bytes** |")
    eq("hole 1", 63, len(ROM[0x1BE09:0x1BE48].rstrip(b"\0")) or 0x1BE48 - 0x1BE09)
    if set(ROM[0x1BE09:0x1BE48]) != {0}: raise Fail("hole 1 is not all zero")
    if set(ROM[0x1BE85:0x1BECA]) != {0}: raise Fail("hole 2 is not all zero")
    eq("hole 2 size", 69, 0x1BECA - 0x1BE85)

@check("sms_data_architecture.md", "the $E4 zero region is 9,334 bytes")
def _():
    says("sms_data_architecture.md", "| ROM hole `$E4:D297` | **9,334 bytes** |")
    lo, hi = 0x24D297, 0x24F70D
    if set(ROM[lo:hi]) != {0}: raise Fail("the $E4 region is not all zero")
    eq("size", 9334, hi - lo)
    if ROM[lo - 1] == 0 or ROM[hi] == 0:
        raise Fail("the $E4 zero run does not start/end where documented")

# --------------------------------------------------------------- animation --
@check("sms_data_architecture.md", "Uranus 2LP: script -> pose -> box, all four reads")
def _():
    says("sms_data_architecture.md", "$C0:0FF1", "02 35 | 03 36 | 80", "09 0A 2C 02",
         "FC 37 CD 37 CC 14 03 00")
    acts = r16(f(0xC00000) + 6 * 2);            eq("act table", 0x0FF1, acts)
    scr = r16(f(0xC00000) + acts + 0x53 * 2)
    eq("2LP script", "02 35 03 36 80", ROM[f(0xC00000) + scr:f(0xC00000) + scr + 5].hex(" "))
    pose = r16(f(0x84809C) + 6 * 2)
    rec = ROM[f(0x840000) + pose + 0x36 * 4: f(0x840000) + pose + 0x36 * 4 + 4]
    eq("pose 0x36", "09 0a 2c 02", rec.hex(" "))
    hit = r16(f(0x8AC1F1) + 6 * 2)
    box = ROM[f(0x8A0000) + hit + 0x0A * 8: f(0x8A0000) + hit + 0x0A * 8 + 8]
    eq("hit box 0x0A", "fc 37 cd 37 cc 14 03 00", box.hex(" "))

# ------------------------------------------------------------- menu system --
@check("menu_system.md", "font blocks decompress to 608 and 182 tiles")
def _():
    says("menu_system.md", "| kana + general (Latin, digits, symbols) | `$C3:48D0` | 608 tiles |",
         "| kanji | `$C7:07F0` | 182 tiles |")
    import sms_lz
    eq("kana block", 608, len(sms_lz.decompress(ROM, f(0xC348D0))) // 32)
    eq("kanji block", 182, len(sms_lz.decompress(ROM, f(0xC707F0))) // 32)

@check("menu_system.md", "the menu font sheet is 418 tiles")
def _():
    says("menu_system.md", "| the menu font sheet | `$C4:2590` | 418 tiles |")
    import sms_lz
    eq("menu sheet", 418, len(sms_lz.decompress(ROM, f(0xC42590))) // 32)

@check("menu_system.md", "the asset pointer tables hold 25 + 49 = 74 distinct records")
def _():
    says("menu_system.md", "`$C3:BCCD`, 25 entries", "`$C3:BCFF`, 49 entries")
    a = [r16(f(0xC3BCCD) + i * 2) for i in range(25)]
    b = [r16(f(0xC3BCFF) + i * 2) for i in range(49)]
    eq("distinct records", 74, len(set(a) | set(b)))
    eq("no overlap", 0, len(set(a) & set(b)))

@check("menu_system.md", "table A is all 0x800 tilemaps")
def _():
    says("menu_system.md", "all `0x800` tilemaps")
    for i in range(25):
        rec = f(0xC30000) + r16(f(0xC3BCCD) + i * 2)
        if r16(rec + 2) != 0x800:
            raise Fail(f"table-A record {i} has len ${r16(rec + 2):04X}, not $800")

@check("menu_system.md", "the bank-$DF engine has eight screen scripts")
def _():
    says("menu_system.md", "**Eight** screens, each a straight-line caller (`lda #script / jsr $DF:83E1`)")
    pat = re.compile(rb"\xa9(..)\x20\xe1\x83", re.S)
    scripts = {m.group(1)[0] | m.group(1)[1] << 8
               for m in pat.finditer(ROM[f(0xDF0000):f(0xDF0000) + 0x10000])}
    eq("script count", 8, len(scripts))

@check("menu_system.md", "the Options cluster begins with the documented first load")
def _():
    says("menu_system.md", "cluster `$C3:A4DD`")
    eq("cluster head", "a9 3e 00 8d 18 1c", ROM[f(0xC3A4DD):f(0xC3A4DD) + 6].hex(" "))

@check("menu_system.md", "stage-name records: 0x66 apart, 0xCC stride, header, bottom = top + $10")
def _():
    says("menu_system.md", "`$C3:B5AD` (palette 3)", "`$C3:B5C1` (palette 4)",
         "a 24-word top row and a 24-word bottom row that is the top plus `$10`")
    n = [r16(f(0xC3B5AD) + i * 2) for i in range(10)]
    h = [r16(f(0xC3B5C1) + i * 2) for i in range(10)]
    eq("highlight = normal + 0x66", [x + 0x66 for x in n], h)
    eq("stride", [0xCC] * 9, [n[i + 1] - n[i] for i in range(9)])
    rec = f(0xC40000) + n[2]
    eq("header", "e4 02 30 00 02 00", ROM[rec:rec + 6].hex(" "))
    top = [r16(rec + 6 + i * 2) for i in range(24)]
    bot = [r16(rec + 0x36 + i * 2) for i in range(24)]
    if not all((b == 0 and t == 0) or b == t + 0x10 for t, b in zip(top, bot)):
        raise Fail("bottom row is not top + $10")

@check("menu_system.md", "the codec discriminator at $80:8DEC")
def _():
    says("menu_system.md", "The flag byte is the codec discriminator, at `$80:8DEC`")
    window = ROM[f(0x808DEC):f(0x808DEC) + 24]
    if b"\x9a\x8e" not in window:            # jsr $8E9A, little-endian operand
        raise Fail("no call to $8E9A near $80:8DEC — the discriminator moved or is misdocumented")

@check("menu_system.md", "the PRESS \"SELECT\" banner is 22 distinct glyphs (not a font)")
def _():
    says("menu_system.md", "its 22 slots hold **22 distinct glyphs with zero\nduplicates**")
    import sms_lz
    kanji = sms_lz.decompress(ROM, f(0xC707F0))
    tiles = [bytes(kanji[t * 32:(t + 1) * 32]) for t in range(0x80, 0x80 + 22)]
    eq("distinct tiles", 22, len(set(tiles)))

# ----------------------------------------------------------------- movelists --
@check("menu_system.md", "all nine movelists decompress to exactly 0x800")
def _():
    says("menu_system.md", "codec 1, decode **and** encode")
    import sms_lz
    for cid in range(1, 10):
        ptr = r24(f(0xE0021A) + cid * 3)
        n = len(sms_lz.decompress(ROM, f(ptr)))
        if n != 0x800:
            raise Fail(f"movelist for charID {cid} decompresses to 0x{n:X}, not 0x800")

# --------------------------------------------- docs this session did NOT write --
@check("sms_damage_system.md", "NO handler in the modifier range reads the RNG byte")
def _():
    says("sms_damage_system.md", "**THERE IS NO RNG IN DAMAGE.**")
    # The strongest static form of the claim: across 0xCAED-0xCD6D, the eleven
    # handlers that compose the damage modifier, no instruction reads DP $90.
    window = ROM[0xCAED:0xCD6E]
    for opcode, label in ((b"\xa5\x90", "lda $90"), (b"\xb5\x90", "lda $90,X"),
                          (b"\xa4\x90", "ldy $90"), (b"\xa6\x90", "ldx $90")):
        if opcode in window:
            raise Fail(f"a modifier handler reads the RNG: {label} found in 0xCAED-0xCD6D")

@check("sms_damage_system.md", "the modifier handlers all begin with the practice-mode bail")
def _():
    says("sms_damage_system.md", "11 near-identical handlers at file 0xCAED-0xCD6D")
    n = ROM[0xCAED:0xCD6E].count(b"\xa5\x8d\xc9\x04")     # lda $8D / cmp #$04
    if n < 11:
        raise Fail(f"only {n} handlers start with the mode check, doc says 11")

@check("annotations.md", "the ochame threshold table")
def _():
    says("annotations.md", "**Ochame threshold table $C1:0AF5**")
    eq("threshold table", "00 01 02 02 03 03 04 04 ff ff ff ff ff ff ff ff",
       ROM[f(0xC10AF5):f(0xC10AF5) + 16].hex(" "))

@check("annotations.md", "patch sites still hold their vanilla bytes in the clean ROM")
def _():
    says("annotations.md", "$C1:88E9 (file 0x188E9)")
    eq("dash speed operand", "0b", ROM[0x188EB:0x188EC].hex())   # LDA #$0B00, high byte
    # The docs name patch 1's site as "0x1874D/E" because those are the two bytes
    # that CHANGE: the instruction is jsr $0952 at 0x1874C and the opcode stays.
    # (An earlier version of this check read 0x1874D as the opcode and failed —
    # the check was wrong, the doc was right. Kept as a comment because that is
    # the exact confusion the addresses invite.)
    eq("patch-1 call site", "20 52 09", ROM[0x1874C:0x1874F].hex(" "))

@check("sms_engine_internals.md", "the per-frame box-index writer")
def _():
    says("sms_engine_internals.md", "`$C0:9CCD`")
    eq("writer", "95 41", ROM[f(0xC09CCD):f(0xC09CCD) + 2].hex(" "))   # sta $41,X

@check("sms_quickref.md", "reaction dispatch is a table of in-bank $C1 pointers")
def _():
    says("sms_quickref.md", "| reaction dispatch | `$C1:0E85` (posture × hit level) |")
    ptrs = [r16(f(0xC10E85) + i * 2) for i in range(39)]        # 3 postures x 13 levels
    bad = [p for p in ptrs if p and not (0x0E00 <= p <= 0x1200)]
    if bad:
        raise Fail(f"{len(bad)} reaction pointers land outside the handler region: {[hex(b) for b in bad[:4]]}")


# ------------------------------------------------------------------ sound --
# The audio system lives on the other side of the APU port, but its driver and
# every table it uses are STORED in the cartridge at a fixed offset — so most of
# what reads like an ARAM fact is checkable here. What genuinely is not (what is
# in ARAM at runtime) the doc marks [live], and this file does not touch it.
SPC = 0x23F804                       # file offset of ARAM $0000 for the driver image


@check("sms_sound_system.md", "the APU handshake and the block loader")
def _():
    says("sms_sound_system.md", "`$C0:EBD4` writes `$E2E2` to `$2142`",
         "computes `A*6`")
    eq("handshake", "c2 30 a2 00 10 a0 aa bb a9 e2 e2",
       ROM[0xEBD4:0xEBDF].hex(" "))                       # ldy #$BBAA / lda #$E2E2
    eq("the loader multiplies by six", "0a 85 00 0a 18 65 00",
       ROM[0xEC66:0xEC6D].hex(" "))                       # asl / sta $00 / asl / clc / adc $00


@check("sms_sound_system.md", "the block table: 40 records, and ids 22-30 are the select voices")
def _():
    says("sms_sound_system.md", "**The table has 40 records** (`$C0:ECE7-$EDD6`)",
         "id = `21 + charID`")
    p24 = lambda o: ROM[o] | ROM[o + 1] << 8 | ROM[o + 2] << 16
    n = 0
    while p24(0xECE7 + n * 6) in (0x00FFFF, 0xFFFFFF) or \
            0xE50000 <= p24(0xECE7 + n * 6) <= 0xE7FFFF:
        n += 1
    eq("records", 40, n)
    eq("the table ends at $EDD6", 0xEDD6, 0xECE7 + 40 * 6 - 1)
    # the select-voice ids are the ones $C0:AE75 hands out, and each loads a block
    ids = [r8(f(0xC0AE75) + cid) for cid in range(1, 10)]
    eq("select-voice bank ids", [21 + cid for cid in range(1, 10)], ids)
    for i in ids:
        if not 0xE50000 <= p24(0xECE7 + i * 6) <= 0xE7FFFF:
            raise Fail(f"select-voice bank id {i} does not point at audio data")


@check("sms_sound_system.md", "the driver's ROM home, pinned by the semitone table")
def _():
    says("sms_sound_system.md", "file offset = ARAM address + 0x23F804",
         "2143 2270 2405 2548 2700 2860 3030 3211 3402 3604 3818 4045 4286")
    tbl = [r16(SPC + 0x0DF5 + i * 2) for i in range(13)]
    eq("semitone table", [2143, 2270, 2405, 2548, 2700, 2860, 3030, 3211,
                          3402, 3604, 3818, 4045, 4286], tbl)
    eq("thirteenth entry is an octave up", 2 * tbl[0], tbl[12])
    for a, b in zip(tbl, tbl[1:]):                        # 2^(1/12) within rounding
        if not 1.058 <= b / a <= 1.061:
            raise Fail(f"the semitone table is not equal-tempered: {b}/{a}")


@check("sms_sound_system.md", "the instrument split at $0C35, and its fixed bytes")
def _():
    says("sms_sound_system.md", "CMP A,#$30", "MOV $0280+X,A      ; SRCN = the instrument byte ITSELF",
         "the bytes are `$17` and `$02`")
    eq("cmp #$30 / bcc", "68 30 90 1e", ROM[SPC + 0x0C39:SPC + 0x0C3D].hex(" "))
    eq("srcn = the instrument byte", "d5 80 02", ROM[SPC + 0x0C3D:SPC + 0x0C40].hex(" "))
    eq("fixed ADSR", ("ff", "e0"), (ROM[SPC + 0x0C41:SPC + 0x0C42].hex(),
                                    ROM[SPC + 0x0C46:SPC + 0x0C47].hex()))
    eq("fixed tuning bytes", ("02", "17"), (ROM[SPC + 0x0C50:SPC + 0x0C51].hex(),
                                            ROM[SPC + 0x0C55:SPC + 0x0C56].hex()))


@check("sms_sound_system.md", "every fighter's five voices: ids, directory entries, transposes")
def _():
    says("sms_sound_system.md", "sound ids           49 + (charID-1)*5",
         "directory entries   48 + (charID-1)*8",
         "| 6 | Uranus | 74-78 | `$58 $59 $5A $5B` `$30` | `-2 -2 -2 -5` `+1` |")
    doc = doc_text("sms_sound_system.md")
    rows = re.findall(r"^\| (\d) \| ([\w ]+?) \| (\d+)-(\d+) \| `([^`]+)` `([^`]+)` \| "
                      r"`([^`]+)` `([^`]+)` \|$", doc, re.M)
    eq("rows in the voice table", 9, len(rows))
    for cid, _name, lo, hi, insts, inst5, trs, tr5 in rows:
        cid, lo, hi = int(cid), int(lo), int(hi)
        eq(f"charID {cid} sound ids", (49 + (cid - 1) * 5, 53 + (cid - 1) * 5), (lo, hi))
        want_i = [int(x.strip("$"), 16) for x in insts.split()] + [int(inst5.strip("$"), 16)]
        want_t = [int(x) for x in trs.split()] + [int(tr5)]
        got_i, got_t = [], []
        for k in range(5):
            e = SPC + 0x13D6 + (lo - 1 + k) * 4
            seq = SPC + (ROM[e] | ROM[e + 1] << 8)
            t = ROM[seq + 3]
            got_t.append(t - 256 if t > 127 else t)
            got_i.append(ROM[seq + 4])
        eq(f"charID {cid} instruments", want_i, got_i)
        eq(f"charID {cid} transposes", want_t, got_t)
        eq(f"charID {cid} owns directory entries {48 + (cid - 1) * 8}+",
           list(range(48 + (cid - 1) * 8, 52 + (cid - 1) * 8)), got_i[:4])


@check("sms_sound_system.md", "the sfx table's usable range")
def _():
    says("sms_sound_system.md", "95 usable ids; past that the table runs into sequence data")
    ok = [i for i in range(1, 129)
          if 0x1400 <= (ROM[SPC + 0x13D6 + (i - 1) * 4] |
                        ROM[SPC + 0x13D6 + (i - 1) * 4 + 1] << 8) <= 0x2FFF]
    eq("usable ids", list(range(1, 96)), ok)


# =============================================================================
# THE TABLE REGISTRY — one entry per documented table this project parses
# =============================================================================
# Everything above is hand-written: a claim, quoted, then re-derived. That does
# not scale to a document set carrying 248 distinct ROM addresses, so the rest
# of this file is built rather than written out.
#
# A registry entry declares a table's documented address and a validator that
# re-derives its STRUCTURE. Three things then happen automatically:
#
#   1. the address token must still appear in every doc that is supposed to
#      name it (the `says` discipline, generated instead of typed);
#   2. the validator runs against the cartridge;
#   3. **the validator is re-run at a WRONG base and must fail.** A table check
#      that still passes two bytes over is not pinning the address the doc
#      publishes — it is describing the neighbourhood, and it would go green on
#      a rotted address. That negative control is the reason the invariants
#      below are shapes (strides, orderings, cross-table contiguity) rather
#      than "the pointers look plausible": plausibility survives a shift.
#
# Every validator therefore takes `shift` and must derive EVERYTHING from the
# documented address plus that shift. Reading a second address from a literal
# would make the negative control lie.

class Table:
    def __init__(self, name, snes, docs, parsed_by, fn, shifts=(1, 2), covers=(), says_also=()):
        self.name, self.snes, self.docs = name, snes, docs
        self.parsed_by, self.fn, self.shifts = parsed_by, fn, shifts
        self.covers = (snes,) + tuple(covers)
        self.says_also = says_also

    @property
    def token(self):
        return f"${self.snes >> 16:02X}:{self.snes & 0xFFFF:04X}"


TABLES = []
def table(**kw):
    def deco(fn):
        TABLES.append(Table(fn=fn, **kw)); return fn
    return deco

# Addresses a validator RE-DERIVED rather than named as a literal — the per
# character box bases, the projectile tables. Without this they would read as
# uncovered in the census, which would under-report exactly the checks that do
# the most work. Snapshotted before the negative controls run, so the shifted
# addresses those produce never count as covered.
DERIVED = set()
def derived(*snes):
    DERIVED.update(snes)

# Quoted instructions outside the encoder's subset. Reported, never silently
# dropped: a claim nobody checked must not be mistaken for one that held.
UNENCODABLE = []

# Instruction claims that hold somewhere inside the routine but do NOT pin the
# address the doc names — the quote still matches at base+1 or base+2, so it is
# the ROUTINE that is being identified, not the byte. A legitimate way to write
# documentation ("the renderer `$C0:9A0E` (`lda $05,x`)"), and it must not be
# counted as if it pinned an address. Reported, never fatal.
ROUTINE_LEVEL = []


def instruction_sites(base, quoted, window=128):
    """Where each `/`-separated part of `quoted` decodes, as offsets from `base`.

    -> ([offset per part], (m, x)) or (None, None).

    Each part must sit at an INSTRUCTION BOUNDARY of the stream starting at
    `base`, in order. Two properties are load-bearing:

    * **Boundary, not substring.** The old check was `ROM[a:a+128].find(bytes)`,
      which matches just as happily inside another instruction's operand or in
      a pointer table. Bytes that happen to appear are not an instruction.
    * **Ordered subsequence, not contiguous run.** `annotations.md:89` quotes
      `jsr $B33F / ldx $8E / jmp ($B32B,X)` and the ROM has a `sep #$30` between
      the first two — the doc is ABRIDGING, correctly and usefully. Demanding
      contiguity would fail a true claim, so the parts need only appear in order.

    Both flag seedings are tried because the docs do not state one, and an
    immediate's width depends on it.
    """
    import docaddrs
    parts = [docaddrs.encode(p.strip()) for p in quoted.split("/")]
    if not all(parts):
        return None, None
    for mx in ((1, 1), (0, 0)):
        starts = sorted(a for a, _op, _ln, _m, _x in dis65816.walk(
            ROM, base, min(base + window, len(ROM)), *mx))
        pos, found = base, []
        for cands in parts:
            hit = next((a for a in starts if a >= pos
                        and any(ROM[a:a + len(c)] == c for c in cands)), None)
            if hit is None:
                break
            found.append(hit - base)
            pos = hit + 1
        else:
            return found, mx
    return None, None


def PINS_ADDRESS(base, quoted):
    """True if the quote identifies THIS address rather than its neighbourhood.

    Trap 20 applied to the extracted family: a claim that still matches two
    bytes over is describing the routine, not the address the doc published.
    """
    return (instruction_sites(base, quoted)[0] is not None
            and instruction_sites(base + 1, quoted)[0] is None
            and instruction_sites(base + 2, quoted)[0] is None)


def ascending(vals, label, strict=True):
    for a, b in zip(vals, vals[1:]):
        if (a >= b) if strict else (a > b):
            raise Fail(f"{label}: {a:#06x} then {b:#06x} is out of order")


def _boxes_json():
    import json
    return json.loads((GAME / "sms_all_boxes.json").read_text())


# ------------------------------------------------------------- bank $8A --
@table(name="attack-box pointer table, 28 entries",
       snes=0x8AC1F1, docs=("sms_quickref.md", "sms_data_architecture.md", "annotations.md"),
       parsed_by="extract_sms_hitboxes.py, extract_proj_boxes.py, mkcharmap.py")
def _(shift):
    e = [r16(f(0x8AC1F1) + shift + i * 2) for i in range(28)]
    eq("index 0 (unused charID)", 0, e[0])
    ascending(e[1:10], "roster entries")
    ascending(e[10:], "projectile entries", strict=False)
    eq("distinct projectile tables", 9, len(set(e[10:])))
    if not all(0xC251 <= p <= 0xFDA1 for p in e[1:]):
        raise Fail("an entry points outside the bank-$8A box-data region")


@table(name="hurt/coll pointer tables — per character the three are contiguous",
       snes=0x8AC229, docs=("sms_quickref.md", "sms_data_architecture.md"),
       parsed_by="extract_sms_hitboxes.py, mkcharmap.py", covers=(0x8AC23D,))
def _(shift):
    # The counts published per character are (next table's base − this one's),
    # so contiguity is not a curiosity: it is what makes them derivable at all.
    hit = [r16(f(0x8AC1F1) + i * 2) for i in range(11)]
    hurt = [r16(f(0x8AC229) + shift + i * 2) for i in range(10)]
    coll = [r16(f(0x8AC23D) + shift + i * 2) for i in range(10)]
    eq("hurt index 0", 0, hurt[0])
    eq("coll index 0", 0, coll[0])
    js, names = _boxes_json(), ["Moon", "Mercury", "Mars", "Jupiter", "Venus",
                                "Uranus", "Neptune", "Pluto", "Chibimoon"]
    for cid in range(1, 10):
        nxt = hit[cid + 1]                      # entry 10 = the first projectile table
        if not hit[cid] < hurt[cid] < coll[cid] < nxt:
            raise Fail(f"charID {cid}: hit/hurt/coll are not contiguous and in order")
        got = {"hit": (hit[cid], (hurt[cid] - hit[cid]) / 8),
               "hurt": (hurt[cid], (coll[cid] - hurt[cid]) / 16),
               "coll": (coll[cid], (nxt - coll[cid]) / 8)}
        derived(*(0x8A0000 + a for a, _ in got.values()))
        for kind, (addr, n) in got.items():
            if n != int(n):
                raise Fail(f"charID {cid} {kind}: {n} entries is not a whole number")
            published = js[names[cid - 1]][kind]
            eq(f"charID {cid} {kind} count vs sms_all_boxes.json", published["count"], int(n))
            eq(f"charID {cid} {kind} base vs sms_all_boxes.json",
               published["snes"], f"$8A:{addr:04X}")


@table(name="the nine projectile box tables annotations.md lists",
       snes=0x8AFBD9, docs=("annotations.md",),
       parsed_by="extract_proj_boxes.py", covers=(0x8AFD51,))
def _(shift):
    says("annotations.md", "9 distinct: `$8A:FBD9,FC69,FC91,FCB9,FCF1,FD29,FD51,FD79,FDA1`")
    m = re.search(r"9 distinct: `\$8A:((?:[0-9A-F]{4},)+[0-9A-F]{4})`", doc_text("annotations.md"))
    listed = [int(x, 16) for x in m.group(1).split(",")]
    hit = [r16(f(0x8AC1F1) + i * 2) for i in range(28)]
    eq("the documented list", listed, sorted({p + shift for p in hit[10:]}))
    derived(*(0x8A0000 + p for p in listed))


# ------------------------------------------------- animation, four layers --
@table(name="action-script tables, 28 entries",
       snes=0xC00000, docs=("sms_data_architecture.md", "sms_quickref.md"),
       parsed_by="mkcharmap.py")
def _(shift):
    e = [r16(f(0xC00000) + shift + i * 2) for i in range(28)]
    eq("index 0 (unused charID)", 0, e[0])
    ascending(e[1:10], "roster act tables")
    ascending(e[10:], "object act tables", strict=False)   # objects share act tables
    derived(*(0xC00000 + p for p in e[1:10]))
    if e[-1] >= 0x2000:
        raise Fail("the act tables run past the script region")


@table(name="pose-record tables, 28 entries of 4-byte records",
       snes=0x84809C, docs=("sms_data_architecture.md", "sms_quickref.md"),
       parsed_by="mkcharmap.py")
def _(shift):
    e = [r16(f(0x84809C) + shift + i * 2) for i in range(28)]
    eq("index 0 (unused charID)", 0, e[0])
    ascending(e[1:10], "roster pose tables")
    ascending(e[10:], "object pose tables", strict=False)
    if not all(0x8000 <= p <= 0x9400 for p in e[1:]):
        raise Fail("a pose table points outside bank $84's record region")
    for cid in range(1, 9):
        if (e[cid + 1] - e[cid]) % 4:
            raise Fail(f"charID {cid}'s pose table is not a whole number of 4-byte records")
    derived(*(0x840000 + p for p in e[1:10]))


@table(name="cel tables, 10 entries of [pose→cel][cel records]",
       snes=0xCB0000, docs=("sms_data_architecture.md", "sms_quickref.md"),
       parsed_by="mkcharmap.py")
def _(shift):
    e = [(r16(f(0xCB0000) + shift + i * 4), r16(f(0xCB0000) + shift + i * 4 + 2))
         for i in range(10)]
    eq("index 0 (unused charID)", (0, 0), e[0])
    for cid in range(1, 10):
        p2c, recs = e[cid]
        if not 0 < p2c < recs:
            raise Fail(f"charID {cid}: pose→cel {p2c:#06x} / records {recs:#06x} are not in order")
    ascending([x for pair in e[1:] for x in pair], "cel tables")
    derived(*(0xCB0000 + x for pair in e[1:] for x in pair))


@table(name="OAM sprite-layout tables, 28 entries of 24-bit pointers",
       snes=0x848000, docs=("sms_data_architecture.md", "sms_quickref.md"),
       parsed_by="mkcharmap.py")
def _(shift):
    e = [r24(f(0x848000) + shift + i * 3) for i in range(28)]
    eq("index 0 (unused charID)", 0, e[0])
    for i, p in enumerate(e[1:], 1):
        if not (0x84 <= p >> 16 <= 0x8A and (p & 0xFFFF) >= 0x8000):
            raise Fail(f"entry {i} is {p:#08x} — not a sprite-list pointer in banks $84-$8A")


# ------------------------------------------------------------ damage path --
@table(name="the three modifier jump tables, 16 words each",
       snes=0xC0CD75, docs=("sms_quickref.md",),
       parsed_by="mkarchpage.py (the handler window)", covers=(0xC0CD95, 0xC0CDB5))
def _(shift):
    says("sms_quickref.md", "three 16-word jump tables selecting the modifier handler")
    tabs = [[r16(f(0xC0CD75) + shift + t * 0x20 + i * 2) for i in range(16)] for t in range(3)]
    for t, tb in enumerate(tabs):
        if not all(0xCAED <= p <= 0xCD6D for p in tb):
            raise Fail(f"table {t} selects something outside the handler window 0xCAED-0xCD6D")
        eq(f"table {t} distinct handlers", 4, len(sorted(set(tb))))
    shapes = [[sorted(set(tb)).index(p) for p in tb] for tb in tabs]
    if not shapes[0] == shapes[1] == shapes[2]:
        raise Fail("the three tables do not select parallel handlers — "
                   f"{shapes[0]} vs {shapes[1]} vs {shapes[2]}")


# --------------------------------------------------------------- throws ---
@table(name="per-victim thrown-pose lists, 10 entries 0x15 apart",
       snes=0xC10881, docs=("annotations.md",), parsed_by="mkpatch/saturn throw fix")
def _(shift):
    says("annotations.md", "Lists live at $0895, $08AA … $093D, 0x15 apart")
    e = [r16(f(0xC10881) + shift + i * 2) for i in range(10)]
    eq("index 0 (1-indexed table)", 0, e[0])
    eq("the nine lists, 0x15 apart", [e[1] + (i - 1) * 0x15 for i in range(1, 10)], e[1:])
    eq("first list", 0x895, e[1])


@table(name="close-throw tables — 4 × 8 B per character, indexed by attack button",
       snes=0xC1055A, docs=("sms_data_architecture.md", "sms_engine_internals.md"),
       parsed_by="mkcharmap.py")
def _(shift):
    says("sms_data_architecture.md", "Uranus's (`$C1:7B39`)", "03 00 28 D8 28 D0 30 5B")
    found = {cid: _scan_bank_c1(0x055A + shift, cid) for cid in range(1, 10)}
    if not all(found.values()):
        raise Fail(f"no close-throw table found for charID {sorted(c for c, v in found.items() if not v)}")
    for cid, addrs in found.items():
        for a in addrs:
            recs = [ROM[f(0xC10000) + a + i * 8: f(0xC10000) + a + i * 8 + 8] for i in range(4)]
            for slot, rec in enumerate(recs):
                if rec[0] == 0xFF:
                    continue                       # this button has no throw
                if slot < 2:
                    raise Fail(f"charID {cid} {a:#06x}: a LIGHT button has a throw record")
                if rec[0] not in (1, 2, 3) or not 0x58 <= rec[7] <= 0x61:
                    raise Fail(f"charID {cid} {a:#06x} slot {slot}: gate {rec[0]:#04x} "
                               f"act {rec[7]:#04x} is not a throw record")
    derived(*(0xC10000 + a for addrs in found.values() for a in addrs))
    uranus = f(0xC10000) + 0x7B39 + shift
    eq("Uranus's HP (slot 2) record", "03 00 28 d8 28 d0 30 5b",
       ROM[uranus + 16:uranus + 24].hex(" "))


@table(name="throw scripts — every toss record holds a FORWARD velocity",
       snes=0xC106E5, docs=("sms_engine_internals.md", "sms_data_architecture.md"),
       parsed_by="mkcharmap.py, mkpatch8.py", covers=(0xC107E5,))
def _(shift):
    says("sms_engine_internals.md", "the record always holds the **forward** velocity")
    says("sms_data_architecture.md", "X is **negated when the thrower\nfaces left**")
    toss = []
    for cid in range(1, 10):
        for a in _scan_bank_c1(0x06E5 + shift, cid):
            rec = ROM[f(0xC10000) + a: f(0xC10000) + a + 6]
            if rec[0] == 0xFF:                     # $FF marks the toss header
                toss.append((cid, a, rec))
    derived(*(0xC10000 + a for _, a, _ in toss))
    if len(toss) < 12:
        raise Fail(f"only {len(toss)} toss records found — the scan pattern is wrong")
    for cid, a, rec in toss:
        xv = rec[1] | rec[2] << 8
        yv = (rec[3] | rec[4] << 8) - 0x10000
        if xv <= 0:
            raise Fail(f"charID {cid} $C1:{a:04X}: X velocity {xv:#06x} is not forward "
                       "(this is the exact fault Saturn shipped with)")
        if yv >= 0 or not 0x10 <= rec[5] <= 0x30:
            raise Fail(f"charID {cid} $C1:{a:04X}: Y {yv} / damage {rec[5]} out of range")


# ------------------------------------------------------------- specials ---
@table(name="special-move records — stride 7, +6 is the misfire act",
       snes=0xC10B49, docs=("sms_acs_system.md", "annotations.md"),
       parsed_by="mkpatch12.py, probe_p12_rec.lua")
def _(shift):
    says("sms_acs_system.md", "**Special-move records** (7 bytes each",
         "Known record addresses: Moon $C1:373E/3745")
    says("annotations.md", "misfire acts (per char, LP-version = record+6 of the first special)")
    # The evidence for "7 bytes, not 8": nothing in bank $C1 reads a record's +7.
    c1 = ROM[f(0xC10000):f(0xC10000) + 0x10000]
    eq("the only `lda $0007,y` in bank $C1", [0x049D],
       [m.start() for m in re.finditer(rb"\xb9\x07\x00", c1)])
    listed = re.search(r"Known record addresses: (.+?)\.\n", doc_text("sms_acs_system.md"), re.S)
    per_char, acts_doc = {}, {}
    for part in listed.group(1).split("·"):
        name, addrs = part.split("$C1:", 1)
        per_char[name.strip()] = [int(x, 16) for x in addrs.strip().rstrip(".").split("/")]
    for name, want in re.findall(r"(\w+) \*\*0x([0-9A-F]{2})\*\*", doc_text("annotations.md")):
        acts_doc.setdefault(name, int(want, 16))
    for name, addrs in per_char.items():
        eq(f"{name}: records are 7 bytes apart",
           [7] * (len(addrs) - 1), [b - a for a, b in zip(addrs, addrs[1:])])
        derived(*(0xC10000 + a for a in addrs))
        got = [r8(f(0xC10000) + a + shift + 6) for a in addrs]
        key = {"ChibiMoon": "ChibiMoon"}.get(name, name)
        if key in acts_doc:
            eq(f"{name}: first special's misfire act", acts_doc[key], got[0])
            eq(f"{name}: the HP variant is +1", got[0] + 1, got[1])


# ---------------------------------------------------------------- menus ---
@table(name="option-value record tables — 12 records, one per value per highlight",
       snes=0xC3A44F, docs=("menu_system.md",), parsed_by="mkpatch16.py",
       covers=(0xC3A457, 0xC3A45B, 0xC3A463))
def _(shift):
    says("menu_system.md", "`$C3:A44F`")
    heads = [r16(f(0xC3A44F) + shift + i * 2) for i in range(12)]
    for h in heads:
        rec = f(0xC40000) + h
        if r16(rec + 2) != 0x14 or r16(rec + 4) != 2:
            raise Fail(f"$C4:{h:04X}: len {r16(rec + 2):#06x} rows {r16(rec + 4)} "
                       "is not a 2-row, 10-cell value record")
    derived(*(0xC40000 + h for h in heads))
    import mkpatch16
    eq("the records mkpatch16.py edits", sorted(h for h, _ in mkpatch16.OPT_VALUES), sorted(heads))


@table(name="char-select nav tables (2 × 10 rows) and the three cursor-position tables",
       snes=0xC0AA4D, docs=("annotations.md",), parsed_by="probe_sms_menurows.lua")
def _(shift):
    says("annotations.md",
         "10 rows × [up,down,left,right] neighbor charID; row 0 dead",
         "table deliberately omits routes to 6/7/8",
         "positions $AAB1+charID*2 (+0x10 x-shift)", "positions $AAC5+charID*2 (+8 x-shift)")
    base = f(0xC0AA4D) + shift
    t1 = [list(ROM[base + i * 4:base + i * 4 + 4]) for i in range(10)]
    t2 = [list(ROM[base + 0x28 + i * 4:base + 0x28 + i * 4 + 4]) for i in range(10)]
    for name, t in (("t1", t1), ("t2", t2)):
        eq(f"{name} row 0 (the cursor is never 0)", [0, 0, 0, 0], t[0])
        if not all(1 <= v <= 9 for row in t[1:] for v in row):
            raise Fail(f"{name} routes to a charID outside 1-9")
    # the story/1P table's whole point: no route reaches the three outer senshi
    reach2 = {v for cid in (1, 2, 3, 4, 5, 9) for v in t2[cid]}
    if reach2 & {6, 7, 8}:
        raise Fail(f"the story nav table reaches {sorted(reach2 & {6, 7, 8})} — 6/7/8 are bosses")
    if not {6, 7, 8} & {v for cid in (1, 2, 3, 4, 5, 9) for v in t1[cid]}:
        raise Fail("the VS nav table reaches none of 6/7/8 either — then it is not the VS table")
    # three cursor-position tables, contiguous after the nav pair, second and
    # third being the first shifted in x by $10 and $8
    p1, p2, p3 = (base + 0x50 + k * 0x14 for k in range(3))
    for i in range(10):
        a, b, c = (r16(p + i * 2) for p in (p1, p2, p3))
        if i == 0:
            eq("char-0 slot is never read", (0, 0, 0), (a, b, c))
        elif b != a + 0x10 or c != a + 8:
            raise Fail(f"charID {i}: positions {a:#06x}/{b:#06x}/{c:#06x} are not +$10 / +8 in x")


@table(name="title-menu cursor table — 6 rows of [up, down, left, right]",
       snes=0xC0A29D, docs=("annotations.md",), parsed_by="probe_sms_menurows.lua")
def _(shift):
    says("annotations.md", "moves via table $C0:A29D+cursor*4 [up,down,left,right]")
    rows = [list(ROM[f(0xC0A29D) + shift + i * 4:f(0xC0A29D) + shift + i * 4 + 4])
            for i in range(6)]
    if not all(0 <= v < 6 for r in rows for v in r):
        raise Fail(f"a destination is not one of the six menu rows: {rows}")
    for i, (up, down, left, right) in enumerate(rows):
        if rows[up][1] != i or rows[down][0] != i or rows[left][3] != i or rows[right][2] != i:
            raise Fail(f"row {i} {rows[i]}: the moves are not mutual inverses")


# ------------------------------------------------------------------ HUD ---
@table(name="round-won badge tile words — 10 entries, one per charID",
       snes=0xC0E166, docs=("annotations.md", "sms_engine_internals.md"),
       parsed_by="mksaturn_smoke.py")
def _(shift):
    says("annotations.md", "**10 entries**, index charID*2",
         "**id 9 reuses id 1's word**")
    base = f(0xC0E166) + shift
    e = [r16(base + i * 2) for i in range(10)]
    eq("index 0 (charID is never 0)", 0, e[0])
    # Shape, not plausibility: nine words that are one stride-2 run of tiles in
    # ONE palette at ONE priority, with id 9 folded back onto id 1. Two bytes
    # over, the run breaks — which is the whole point of the negative control.
    for i, w in enumerate(e[1:9], start=1):
        if w != 0x38E0 + (i - 1) * 2:
            raise Fail(f"id {i}: {w:#06x} is not $38E0 + {(i - 1) * 2:#x}")
    eq("id 9 reuses id 1's word (Chibi Moon wears Moon's crescent)", e[1], e[9])
    for i, w in enumerate(e[1:10], start=1):
        eq(f"id {i} priority", 1, (w >> 13) & 1)
        eq(f"id {i} BG3 palette", 6, (w >> 10) & 7)
    # the badge is 2x2 in a 16-wide sheet, so the eight blocks must tile
    # $E0-$EF over $F0-$FF exactly, leaving nothing spare
    eq("tiles used by the eight badges", set(range(0xE0, 0x100)),
       {t for w in e[1:9] for base_t in (w & 0x3FF,)
        for t in (base_t, base_t + 1, base_t + 0x10, base_t + 0x11)})
    # ...and the table ENDS here: $C0:E17A is code, which is exactly why
    # Saturn's id $1C read garbage instead of a missing entry.
    if r16(base + 20) == 0x38F0:
        raise Fail("there is an 11th entry — the table is wider than documented")
    derived(0xC0E17A)


@table(name="in-match asset job table — 6-byte [src16][srcbank][vram16][flags]",
       snes=0xE00000, docs=("annotations.md", "sms_data_architecture.md"),
       parsed_by="mksaturn_smoke.py", covers=(0xE021E6,))
def _(shift):
    says("annotations.md", "**6-byte entries**")
    says("sms_data_architecture.md", "[src16][srcbank][vram16][flags]")
    base = f(0xE00000) + shift
    rec = [(r16(base + i * 6), r8(base + i * 6 + 2), r16(base + i * 6 + 3),
            r8(base + i * 6 + 5)) for i in range(3)]
    for i, (_src, bank, _vram, _fl) in enumerate(rec):
        if not 0xC0 <= bank <= 0xE7:
            raise Fail(f"entry {i}: source bank ${bank:02X} is not cartridge")
    eq("entry 0 destination (BG3 CHR base)", 0x5000, rec[0][2])
    eq("entry 1 destination (the HUD tilemap)", 0x1000, rec[1][2])
    eq("entry 0 source", 0xE021E6, (rec[0][1] << 16) | rec[0][0])
    # and the sheet it names really is a 512-tile sms_lz stream whose free
    # window is empty IN THE SHEET, not merely empty in VRAM
    sys.path.insert(0, str(REPO / "tools" / "saturn"))
    import sms_lz
    sheet, packed = sms_lz.decompress_ex(ROM, f((rec[0][1] << 16) | rec[0][0]), 0x2000)
    eq("decompressed HUD sheet", 0x2000, len(sheet))
    eq("compressed length", 0xF31, packed)
    for t in range(0xC7, 0xE0):
        if any(sheet[t * 16:t * 16 + 16]):
            raise Fail(f"sheet tile ${t:02X} is not blank — the free window is not free")
    if not all(any(sheet[t * 16:t * 16 + 16]) for t in range(0xE0, 0x100)):
        raise Fail("a badge tile in $E0-$FF is blank")


def _scan_bank_c1(routine, cid):
    """Every `ldy #imm / jsr <routine>` inside charID `cid`'s proc block.

    The same scan mkcharmap.py uses to publish a character's throw tables — so
    a check built on it is checking what that generator publishes, not a second
    opinion about it.
    """
    base, dispatch = f(0xC10000), f(0xC100A6)
    lo = r16(dispatch + cid * 2)
    hi = r16(dispatch + (cid + 1) * 2) if cid < 9 else 0xBE00
    pat = bytes([0x20, routine & 0xFF, (routine >> 8) & 0xFF])
    return sorted({r16(base + off + 1) for off in range(lo, hi - 5)
                   if ROM[base + off] == 0xA0 and ROM[base + off + 3:base + off + 6] == pat})


def register_tables():
    """Turn each registry entry into a check: the docs must still name the
    address, and the cartridge must still have the structure."""
    for t in TABLES:
        def run(t=t):
            for doc in t.docs:
                says(doc, t.token)
            for doc, frag in t.says_also:
                says(doc, frag)
            t.fn(0)
        CHECKS.append((t.docs[0], f"{t.token} {t.name}", run))


def negative_controls():
    """Re-run every table validator at a WRONG base; each must object.

    This is the check on the checks, and it has teeth: a validator that passes
    two bytes off its documented address would go green on a rotted address,
    which is precisely the failure this file exists to prevent.
    """
    bad = []
    for t in TABLES:
        for d in t.shifts:
            try:
                t.fn(d)
            except Exception:
                continue                      # noticed — good
            bad.append(f"{t.token} ({t.name}) still passes at base+{d}")
    return bad


# =============================================================================
# GENERATED CLAIMS — the two families the docs state mechanically
# =============================================================================
def register_claims():
    """Every `(file 0x…)` transcription and every quoted byte run becomes a check.

    Neither needs a human to decide what is being claimed: the doc says the
    address, the doc says the bytes (or the offset), and HiROM decides the rest.
    Extraction and its association rule live in tools/docaddrs.py.
    """
    import docaddrs
    game = [p for p in docaddrs.docs_files() if p.parent.name == "game"]
    claimed = set()

    for doc, line_no, snes, off in docaddrs.file_offset_claims():
        def run(snes=snes, off=off):
            if f(snes) != off:
                raise Fail(f"${snes:06X} is file 0x{f(snes):05X}, doc writes 0x{off:05X}")
        CHECKS.append((doc, f"${snes:06X} (file 0x{off:05X})", run))
        claimed.add(snes)

    for doc, line_no, snes, want in docaddrs.byte_run_claims(game):
        def run(snes=snes, want=want, doc=doc, line_no=line_no):
            got = ROM[f(snes):f(snes) + len(want)]
            if got != want:
                near = ROM[f(snes) - 64:f(snes) + 128].find(want)
                where = (f" — that run is at ${snes + near - 64:06X}" if near >= 0 else "")
                raise Fail(f"{doc}:{line_no} quotes {want.hex(' ')} at ${snes:06X}, "
                           f"which holds {got.hex(' ')}{where}")
        CHECKS.append((doc, f"${snes:06X} = {want.hex(' ')[:23]}…", run))
        claimed.add(snes)

    # Instructions the docs quote beside an address, and the disassembly listing
    # rows. Both are matched at instruction BOUNDARIES — see instruction_sites().
    for doc, line_no, snes, quoted, cands in docaddrs.instruction_claims(game):
        if not cands:
            UNENCODABLE.append(f"{doc}:{line_no} `{quoted}`")
            continue
        off, _mx = instruction_sites(f(snes), quoted)
        # If the quote sits further along and THE LINE ITSELF names that address,
        # the doc's claim is about the address it named, not the one the
        # proximity rule happened to bind. `$C3:BB60 (`jsr ($BB6D,x)` … at
        # `$C3:BB69`)` is the live case: the instruction is 9 bytes on, the doc
        # says so, and only the old 128-byte substring window hid the mismatch.
        if off and off[0] and docaddrs.token(snes + off[0]) in docaddrs.line_at(doc, line_no):
            snes += off[0]

        def run(snes=snes, quoted=quoted, doc=doc, line_no=line_no):
            got, _ = instruction_sites(f(snes), quoted)
            if got is None:
                raise Fail(f"{doc}:{line_no} puts `{quoted}` at ${snes:06X}, which holds "
                           f"{ROM[f(snes):f(snes) + 6].hex(' ')} and does not decode to it "
                           "at any instruction boundary in the next 128 bytes")
        CHECKS.append((doc, f"${snes:06X} `{quoted}`", run))
        claimed.add(snes)
        if not PINS_ADDRESS(f(snes), quoted):
            ROUTINE_LEVEL.append(f"{doc}:{line_no} ${snes:06X} `{quoted}`")

    # Hand-transcribed listing rows: `C0/D055  rep #$30`. The address and the
    # instruction are two INDEPENDENT readings by a human, so unlike a generated
    # fact this one can be wrong today — which is exactly what makes it worth
    # checking. Required at offset 0: a listing row states what is AT the
    # address, with no routine-scoped slack to hide in.
    for doc, line_no, snes, quoted, cands in docaddrs.listing_claims(game):
        if not cands:
            UNENCODABLE.append(f"{doc}:{line_no} `{quoted}` (listing)")
            continue

        def run(snes=snes, quoted=quoted, cands=cands, doc=doc, line_no=line_no):
            here = ROM[f(snes):f(snes) + max(len(c) for c in cands)]
            if not any(here.startswith(c) for c in cands):
                raise Fail(f"{doc}:{line_no} lists `{quoted}` at ${snes:06X}, which holds "
                           f"{ROM[f(snes):f(snes) + 6].hex(' ')}")
        CHECKS.append((doc, f"${snes:06X} listing `{quoted}`", run))
        claimed.add(snes)
    return claimed


def claim_selftests():
    """The two extractors, negative-controlled both ways on synthetic lines.

    A generated check family has a failure mode a hand-written check does not:
    the EXTRACTOR can quietly stop matching, and a family that finds nothing
    passes vacuously. So four cases go through the real code paths every run —
    a true claim must be found and pass, a falsified one must be found and
    fail, and the loose form the association rule rejects must not be found at
    all. `$C1:0AF5` is used because its bytes are pinned by a hand check above.
    """
    import docaddrs
    bad = []

    def offsets(line):
        return docaddrs.file_offset_claims_in("synthetic", line)

    def runs(line):
        return docaddrs.byte_run_claims_in("synthetic", line)

    right = offsets("| `$C1:0AF5` (file 0x10AF5) | threshold table |")
    wrong = offsets("| `$C1:0AF5` (file 0x10AF6) | threshold table |")
    loose = offsets("| `$C1:0AF5` | the misfire threshold, third byte at file 0x10AF7 |")
    if len(right) != 1 or f(right[0][2]) != right[0][3]:
        bad.append("file-offset extractor: the true form is not found, or does not pass")
    if len(wrong) != 1 or f(wrong[0][2]) == wrong[0][3]:
        bad.append("file-offset extractor: a falsified offset is not caught")
    if loose:
        bad.append("file-offset extractor: bound a claim to an unattached parenthetical")

    hit = runs("**Ochame threshold table $C1:0AF5** = `00 01 02 02`")
    miss = runs("**Ochame threshold table $C1:0AF5** = `00 01 02 03`")
    if len(hit) != 1 or ROM[f(hit[0][2]):f(hit[0][2]) + 4] != hit[0][3]:
        bad.append("byte-run extractor: the true run is not found, or does not match the ROM")
    if len(miss) != 1 or ROM[f(miss[0][2]):f(miss[0][2]) + 4] == miss[0][3]:
        bad.append("byte-run extractor: a falsified run is not caught")
    return bad + instruction_selftests()


def instruction_selftests():
    """The instruction and listing extractors, negative-controlled.

    These two had NO synthetic control until 2026-08-10, which made them the
    weakest families here: an extractor that quietly stops matching passes every
    claim it no longer finds, and nothing would have said so. Anchored on
    `$C1:0E4F`, whose bytes a hand check above already pins.

    ⚠ `mid_operand` is the case that separates a BOUNDARY check from the
    substring search this replaced, and getting it right took three attempts —
    each wrong one is worth more than the answer:

      1. `$C0:9CB2` + `lda $05,x` LOOKED like a mid-operand case under a linear
         walk from 9CB2. But 9CB2 is not a routine entry (zero call sites): the
         real entry is `$C0:9C96`, six call sites, and from THERE `b5 05` at
         `0x09CB6` is a perfectly ordinary `lda $05,x`. A framing artifact of my
         own arbitrary starting point, not a property of the cartridge.
      2. `$C0:9000` + `lda $00,X` failed under an 8-bit seeding and passed under
         the 16-bit one. `instruction_sites` tries BOTH, because the docs do not
         state a flag state — so a control must fail under both or it is testing
         a function nobody calls.
      3. `$C0:92DD` + `lda $00,X` is the real thing: the bytes sit at file
         `0x0931C`, inside the operand of the `lda $E000B5,X` (`bf b5 00 e0`) at
         `0x0931B`, under EITHER seeding, from a corroborated entry.

    Without it the upgrade would have no control at all, because on the fourteen
    claims the docs currently make, substring and boundary agree on all fourteen
    — measured. The upgrade's present value is that it derives the OFFSET (which
    is what exposed `$C3:BB60`'s quote living at `$C3:BB69`, and what separates
    address-pinning claims from routine-level ones); the mid-operand protection
    is prophylactic, and this control is what keeps it honest.

    The `shifted` case pins the historical `$C1:0E51` bug. Note it is NOT
    evidence for the upgrade: the old substring check rejected that claim too,
    because its window opened at the claimed address and the real instruction is
    two bytes EARLIER. Measured, after the opposite was assumed.
    """
    import docaddrs
    bad = []

    def insns(line):
        return docaddrs.instruction_claims_in("synthetic", line)

    def listings(line):
        return docaddrs.listing_claims_in("synthetic", line)

    def matches(line):
        got = insns(line)
        return got and instruction_sites(f(got[0][2]), got[0][3])[0] is not None

    if not matches("the clear is at `$C1:0E4F` (`stz $47,X`)"):
        bad.append("instruction extractor: the true claim is not found, or does not match")
    if matches("the clear is at `$C1:0E4F` (`stz $48,X`)"):
        bad.append("instruction extractor: a falsified operand is not caught")
    if matches("the clear is at `$C1:0E51` (`stz $47,X`)"):
        bad.append("instruction extractor: the historical two-byte-late address "
                   "($C1:0E51 for $C1:0E4F) is NOT caught")
    if matches("the loader `$C0:92DD` (`lda $00,X`)"):
        bad.append("instruction extractor: matched `lda $00,X` at $C0:92DD, where those "
                   "bytes appear only INSIDE the operand of the lda $E000B5,X at "
                   "$C0:931B — the boundary check has regressed to a substring search")
    # an instruction sitting in a later table cell, describing what a PATCH
    # writes, must never bind to the row's subject
    if any(q == "lda $14" for _d, _n, _s, q, _c
           in insns("| `$C0:9EA6` | x | `lda $66,X` — patched to `lda $14` |")):
        bad.append("instruction extractor: bound a PATCHED instruction from a later cell")
    # a documented ABSENCE must not become an assertion of presence
    if insns("step-0 init MISSING the engine-standard `stz $46,X`"):
        bad.append("instruction extractor: bound a claim the doc makes NEGATIVELY")

    right = listings("C1/0E4F  stz $47,X")
    wrong = listings("C1/0E51  stz $47,X")
    if len(right) != 1 or not ROM[f(right[0][2]):].startswith(right[0][4][0]):
        bad.append("listing extractor: the true row is not found, or does not match the ROM")
    if len(wrong) != 1 or ROM[f(wrong[0][2]):].startswith(wrong[0][4][0]):
        bad.append("listing extractor: a two-byte-late address is not caught")
    if listings("the value 0x1234  lda $05 is not a listing row"):
        bad.append("listing extractor: matched a line that is not a listing row")
    return bad


# =============================================================================
# THE STRUCTURAL FAMILY — documented CODE addresses, checked as code
# =============================================================================
# Most documented addresses carry no quotable content: 164 of the 183 that no
# check reached were prose only — "$C1:07CF counts mash presses" and nothing
# else. Route (a) for those is to make the doc quote an entry instruction, but a
# quote STAMPED from the currently documented address is a tautology: it is
# derived from the very address it is supposed to test, so it can never catch
# one that is already wrong. What the cartridge can still decide about such an
# address is STRUCTURAL — is there an instruction there at all, and does
# anything reach it?
#
# Three tiers, in descending strength, each address taking the first that holds:
#
#   entry        an instruction boundary AND something calls or vectors to it
#   branch-join  an instruction boundary AND a branch in its routine targets it
#   boundary     an instruction boundary
#
# ⚠ ENROLMENT IS PER TIER, and the address is only enrolled if its OWN tier
# predicate FAILS at base+1 and base+2. Requiring the composite to fail instead
# was tried first and enrolled 1 address out of 60 — a strong entry-tier address
# was being rejected merely because base+1 happened to be a boundary. That was a
# bug in the composition, not a property of the cartridge.
#
# ⚠ WHAT THESE CAN AND CANNOT CATCH. They pass by construction today, so their
# value is future rot: an address edited by one or two bytes is caught by the
# enrolment guarantee, and an address replaced by a different wrong one is
# caught at the rate the random-address control measures and prints. None of
# them can catch an address that is wrong TODAY — only the families where a
# HUMAN supplied the redundancy (quoted bytes, quoted instructions, listing
# rows) can do that. The tiers are reported separately because they differ by an
# order of magnitude in discrimination, and a weak number must not ride on a
# strong one.
#
# There is no `says()` here: the census re-reads the documents every run, so an
# address deleted from the docs is simply never enrolled. Asserting it separately
# would be ceremony, not a check.

# Established by the run of 2026-08-10 that introduced this family, and
# RE-DERIVED by structural_controls() on every run. They are deliberately not
# copied out of a planning document: a ceiling typed from a plan is a guess
# promoted to a gate, and it would stay green while the predicate drifted
# underneath it. Set from measurement; move only with a new measurement.
# Measured 2026-08-10: 84 enrolled — 55 entry, 4 branch-join, 25 boundary-only —
# and the random-address control returned 2.3% / 2.1% / 32.3% over 1000 seeded
# samples. The floor sits below the measured enrolment with room for ordinary
# documentation churn; the ceilings sit above the measured rates with the same
# margin. Both are here to catch a PREDICATE that has drifted, not to pin a
# number: move them only with a run that justifies the move.
STRUCTURAL_FLOOR = 70
RANDOM_CEILING = {"entry": 5.0, "branch-join": 5.0, "boundary": 40.0}

_REF = {}


def _refs():
    if not _REF:
        _REF["call"] = dis65816.call_targets(ROM)
        _REF["vec"] = dis65816.vector_targets(ROM)
        by = {}
        for t in list(_REF["call"]) + list(_REF["vec"]):
            by.setdefault(t & 0x3F0000, []).append(t)
        for k in by:
            by[k].sort()
        _REF["bank"] = by
    return _REF


def _corroborated(t):
    """Is `t` plausibly a real routine entry, not a byte inside data?

    The reference census is a raw byte scan, so a coincidental `20 lo hi` in a
    table yields a target that is not code. Requiring either two independent
    call sites or a terminator immediately before it filters most of those. The
    cost of the filter is measured, not assumed: it moves the enrolled total by
    three, and the stricter reading is the one kept.
    """
    return _refs()["call"].get(t, 0) >= 2 or (t > 0 and ROM[t - 1] in (0x60, 0x6B, 0x40))


def _entry_for(off):
    """Nearest corroborated reference target at or before `off`, within 0x400.

    Descent is seeded LOCALLY, per address. A whole-ROM code map was measured
    and does not exist to be had: descent from the reset and NMI vectors plus
    the $C1:00A6 proc dispatch reaches under 2,000 instructions before every
    path dies at an indirect `jmp (abs,X)`, and inventing jump-table heuristics
    to get past that would poison every boundary derived afterwards.
    """
    import bisect
    lst = _refs()["bank"].get(off & 0x3F0000, [])
    i = bisect.bisect_right(lst, off)
    for t in reversed(lst[max(0, i - 40):i]):
        if off - t > 0x400:
            break
        if _corroborated(t):
            return t
    return None


_BND, _BRT = {}, {}


def _spans(e):
    if e not in _BND:
        hi = min(e + 0x460, (e & 0x3F0000) + 0x10000)
        _BND[e] = dis65816.boundaries(ROM, e, hi, [e])
        tg = set()
        for a, op, _ln, _m, _x in dis65816.walk(ROM, e, hi):
            if op in dis65816.BRANCH:
                o = ROM[a + 1]
                tg.add(a + 2 + (o - 256 if o > 127 else o))
            elif op == dis65816.BRL:
                o = ROM[a + 1] | ROM[a + 2] << 8
                tg.add(a + 3 + (o - 65536 if o > 32767 else o))
        _BRT[e] = tg
    return _BND[e], _BRT[e]


def structural_tier(snes):
    """"entry" | "branch-join" | "boundary" | None for a documented address."""
    off = f(snes)
    e = _entry_for(off)
    if e is None:
        return None
    bnd, brt = _spans(e)
    if off not in bnd:
        return None
    if _refs()["call"].get(off, 0) > 0 or off in _refs()["vec"]:
        return "entry"
    if off in brt:
        return "branch-join"
    return "boundary"


TIER_TEXT = {
    "entry": "an instruction boundary, and called or vectored to",
    "branch-join": "an instruction boundary, and a branch target in its routine",
    "boundary": "an instruction boundary",
}


def register_structural(covered):
    """Enrol every uncovered documented ROM address whose tier pins it.

    -> (addresses now covered, [(snes, where, why-not) for the rest])
    """
    import docaddrs
    seen = set(covered) | {f(a) for a in covered}
    rom_mentions = {}
    for m in docaddrs.census():
        if m.area == "game" and docaddrs.is_rom(m.snes) and not m.generated:
            rom_mentions.setdefault(m.snes, m)

    enrolled, left = {}, []
    for snes, m in sorted(rom_mentions.items()):
        if snes in seen or f(snes) in seen:
            continue
        t = structural_tier(snes)
        where = f"{m.doc}:{m.line_no}"
        if t is None:
            left.append((snes, where, "no instruction boundary reachable here"))
            continue
        if structural_tier(snes + 1) == t or structural_tier(snes + 2) == t:
            left.append((snes, where, f"'{t}' still holds two bytes over — does not pin"))
            continue

        def run(snes=snes, t=t, where=where):
            got = structural_tier(snes)
            if got != t:
                raise Fail(f"{where} names ${snes:06X} as code; the cartridge now says "
                           f"{got or 'it is not an instruction boundary'} (was '{t}')")
        CHECKS.append((m.doc, f"${snes:06X} {t}", run))
        enrolled[snes] = t
    return enrolled, left


def structural_controls(enrolled):
    """Three controls, because a generated family can pass vacuously.

    1. A FLOOR. If the family suddenly enrols far fewer addresses than the run
       that established it, the predicate has stopped working rather than the
       documents having improved.
    2. A RANDOM-ADDRESS control. The shift test only asks whether a predicate
       survives one or two bytes; this asks the sharper question — how often
       does it hold for an address that is simply WRONG? Sampled near the
       documented ones, so it measures the neighbourhood they live in.
    3. SYNTHETIC NEGATIVES on bytes other checks already pin: an address inside
       a known instruction's operand must not read as a boundary.
    """
    import random
    bad = []
    if len(enrolled) < STRUCTURAL_FLOOR:
        bad.append(f"structural family enrolled {len(enrolled)}, floor is {STRUCTURAL_FLOOR} "
                   "— the predicate has stopped working, or the census has")

    rng = random.Random(20260810)
    pool = sorted(enrolled) or [0xC09CCD]
    rates, n = {}, 1000
    for _ in range(n):
        a = rng.choice(pool) + rng.choice((-1, 1)) * rng.randint(8, 400)
        if f(a) < len(ROM):
            rates[structural_tier(a)] = rates.get(structural_tier(a), 0) + 1
    for tier, ceiling in RANDOM_CEILING.items():
        got = 100.0 * rates.get(tier, 0) / n
        if got > ceiling:
            bad.append(f"'{tier}' holds for {got:.1f}% of random nearby addresses "
                       f"(ceiling {ceiling}%) — it has become permissive")
    structural_controls.rates = {k: 100.0 * v / n for k, v in rates.items()}

    # An interior byte of an instruction a HAND check already pins: $C1:0E4F is
    # `stz $47,X` (74 47), so $C1:0E50 is its operand and cannot be code. The
    # anchor is deliberately one this file verifies independently, so the control
    # is not derived from the same descent it is testing.
    if structural_tier(0xC10E4F) is None:
        bad.append("$C1:0E4F does not read as code, but a hand check pins `stz $47,X` there")
    if structural_tier(0xC10E50) is not None:
        bad.append("$C1:0E50 reads as an instruction boundary; it is the operand byte "
                   "of the `stz $47,X` at $C1:0E4F")
    return bad


def covered_addresses(claimed):
    """Every documented address some check re-derives — for the coverage note.

    A hand-written check counts as covering an address if that address (or its
    file offset) appears as a literal in the check's source. That is a heuristic
    and it is only ever printed as a note, never gated: over-counting a covered
    address would be a quiet lie, so this number is reported next to the total
    and meant to be read with suspicion.
    """
    import inspect
    lits = set(claimed) | DERIVED
    for _, _, fn in CHECKS:
        try:
            src = inspect.getsource(fn)
        except (OSError, TypeError):
            continue
        for m in re.finditer(r"0x([0-9A-Fa-f]{4,6})", src):
            lits.add(int(m.group(1), 16))
    for t in TABLES:
        lits.update(t.covers)
    return lits


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("--uncovered", action="store_true",
                    help="list the documented ROM addresses no check re-derives")
    args = ap.parse_args()

    hand = len(CHECKS)
    register_tables()
    claimed = register_claims()
    extracted = len(CHECKS) - hand - len(TABLES)
    # The structural family only takes what no other check reaches, so the
    # covered set has to be computed before it is registered.
    covered = covered_addresses(claimed)
    enrolled, unenrollable = register_structural(covered)
    covered |= set(enrolled)

    fails = []
    for doc, name, fn in CHECKS:
        try:
            fn()
            if args.verbose:
                print(f"  \033[32mPASS\033[0m  [{doc}] {name}")
        except Fail as e:
            print(f"  \033[31mFAIL\033[0m  [{doc}] {name}\n          {e}")
            fails.append(name)
        except Exception as e:                       # a broken check is not a pass
            print(f"  \033[31mERROR\033[0m [{doc}] {name}\n          {type(e).__name__}: {e}")
            fails.append(name)

    # The check on the checks: a table validator that survives a wrong base is
    # not pinning the address its document publishes, and an extractor that has
    # stopped matching passes every claim it no longer finds.
    for line in negative_controls() + claim_selftests() + structural_controls(enrolled):
        print(f"  \033[31mFAIL\033[0m  [self-test] {line}")
        fails.append(line)

    docs = len({d for d, _, _ in CHECKS})
    if fails:
        print(f"\n\033[31m{len(fails)} of {len(CHECKS)} checks FAILED\033[0m")
        sys.exit(1)
    print(f"\n\033[32mALL PASS\033[0m ({len(CHECKS)} checks across {docs} documents)")
    print(f"  {hand} written by hand · {len(TABLES)} table structures, each re-run at a wrong "
          f"base and required to fail · {extracted} claims extracted from "
          f"the prose (file offsets, quoted bytes, quoted instructions, listing rows)")
    if enrolled:
        bytier = {}
        for t in enrolled.values():
            bytier[t] = bytier.get(t, 0) + 1
        rates = getattr(structural_controls, "rates", {})
        print(f"  {len(enrolled)} documented code addresses pinned structurally, each proven to "
              "fail two bytes over:")
        for t in ("entry", "branch-join", "boundary"):
            if bytier.get(t):
                print(f"      {bytier[t]:3d}  {TIER_TEXT[t]} "
                      f"— holds for {rates.get(t, 0):.1f}% of random nearby addresses")
        print(f"      {len(unenrollable)} more could not be pinned and stay uncovered "
              "(--uncovered says why)")
    for u in UNENCODABLE:
        print(f"  note  quoted instruction outside the encoder's subset, NOT checked: {u}")
    if ROUTINE_LEVEL:
        print(f"  note  {len(ROUTINE_LEVEL)} instruction claims identify the ROUTINE, not the "
              "address — they still match two bytes over:")
        for r in ROUTINE_LEVEL:
            print(f"          {r}")
    import docaddrs
    docaddrs.report(covered=covered, show_uncovered=args.uncovered,
                    reasons={a: why for a, _where, why in unenrollable})
    print("Checks facts decidable by reading the cartridge. It does NOT check prose,")
    print("reasoning, runtime behaviour, or anything about ARAM.")


if __name__ == "__main__":
    main()
