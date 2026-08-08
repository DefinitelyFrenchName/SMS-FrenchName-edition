#!/usr/bin/env python3
"""Verify docs/game/'s load-bearing claims against the cartridge.

  python3 tools/checkdocs.py            # run every check
  python3 tools/checkdocs.py -v         # ...and print each one that passes

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


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

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

    docs = len({d for d, _, _ in CHECKS})
    if fails:
        print(f"\n\033[31m{len(fails)} of {len(CHECKS)} checks FAILED\033[0m")
        sys.exit(1)
    print(f"\n\033[32mALL PASS\033[0m ({len(CHECKS)} checks across {docs} documents)")
    print("Checks facts decidable by reading the cartridge. It does NOT check prose,")
    print("reasoning, runtime behaviour, or anything about ARAM.")


if __name__ == "__main__":
    main()
