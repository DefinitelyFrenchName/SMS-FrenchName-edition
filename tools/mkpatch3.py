#!/usr/bin/env python3
"""Patch 3: extended character palettes (extracted from the Big Zam edition) +
"FrenchName" ROM-header identification.

Ports sprntgd's sms_patcher.py palette system (PATCH_PAL hooks + appended code
block + palette data block) exactly, so the added selection code and pointers are
the battle-tested originals. The 30 extra palettes/character are lifted from the
Big Zam ROM's palette block instead of BMP files.

Selection on the character-select screen (per the patcher readme):
  A=color0(default) B=1 Y=2 X=3 ; L+(A/B/Y/X)=4-7 ; R+=8-15 ; Start+=16-31

Also writes the internal ROM header title to "FrenchName" (shows in emulator title
bars / ROM info / flashcart menus) and fixes the SNES checksum.

Builds from any input ROM (clean or the stacked 1f-link+dashfix build): the PATCH_PAL
anchors live in bank $C0, disjoint from our bank-$C1 gameplay patches.
"""
import sys
from hashlib import sha1

from pathlib import Path as _P
REPO = _P(__file__).resolve().parent.parent  # repo root (cwd-independent)
sys.path.insert(0, str(REPO / "tools"))
from smspaths import clean_rom, bigzam_rom, require_source, check_not_inplace, fix_checksum  # ROM location: $SMS_ROM_DIR -> roms/ -> ../roms/
VENDOR = REPO / "vendor/sms-training-mode"


def _vendor():
    """Import sprntgd's patcher on demand (#3).

    `vendor/` is gitignored, so on a fresh clone this module is absent — and
    importing it at module scope made *this whole file* unimportable there.
    tools/mksigs.py imports every builder for its SIG, so one missing third-party
    file broke a command that needs none of it. Deferred, with an error that says
    what to get rather than a ModuleNotFoundError."""
    sys.path.insert(0, str(VENDOR))
    try:
        from sms_patcher import apply_patch, PATCH_PAL, read_int
    except ModuleNotFoundError:
        raise SystemExit(
            "error: sprntgd's sms_patcher.py is not in vendor/sms-training-mode/\n"
            "  Patch 3 is a re-application of that patcher's palette work, so it needs\n"
            "  the original. vendor/ is gitignored (third-party, not ours to vendor):\n"
            "  drop the sms-training-mode tree there and re-run.")
    return apply_patch, PATCH_PAL, read_int

CLEAN = clean_rom()

# Detection fingerprint (p3) — consumed by tools/mksigs.py to generate the
# regression suite's SIGS table. ONLY bytes invariant across stub-layout and
# bank-stacking changes: first bytes of the vendor patcher's 1P palette-map hook (fixed rewrite)
SIG = [(0x884B, 0xA9), (0x884C, 0x0C), (0x884F, 0x65)]
CLEAN_SHA1 = "bc0e29ee383574443226695215496eb0d09aaa1c"
BIGZAM = bigzam_rom()
BZ_SHA1 = "12114423b278d3114a301c5366a7a1811913ba25"   # donor validation (issue #8)
BZ_PAL_BASE = 0x2A0000  # palette block in the Big Zam ROM
BZ_MIN_LEN = BZ_PAL_BASE + 0x1000 * 10                # palette block must be fully present
TITLE = b"FrenchName "  # 11 chars, space-padded

def build(src_path, out_path):
    data = bytearray(open(src_path, "rb").read())
    # trim any padding down to the base 0x280000 image the patcher expects
    if len(data) > 0x280000 and data[0x280000:] == bytes(len(data) - 0x280000):
        data = data[:0x280000]
    bz = open(BIGZAM, "rb").read()
    # donor validation (issue #8): a short/wrong donor must fail loudly, not shift the image
    bzh = sha1(bz).hexdigest()
    if bzh != BZ_SHA1:
        raise SystemExit(f"error: Big Zam donor ROM hash mismatch — {BIGZAM}\n"
                         f"  got sha1 {bzh}\n  expected {BZ_SHA1}")
    if len(bz) < BZ_MIN_LEN:
        raise SystemExit(f"error: Big Zam donor too short ({len(bz):#x} < {BZ_MIN_LEN:#x})")

    # 1) Apply the palette hooks + selection code + appended block (patcher-exact).
    apply_patch, PATCH_PAL, read_int = _vendor()
    apply_patch(data, PATCH_PAL)
    palette_offset = len(data) - 0x10000

    # 2) Copy each character's two default palettes from the manifest (patcher logic).
    pointer_offset = 0x200238
    for chara_id in range(1, 10):
        chara_offset = read_int(data, pointer_offset + 2 * chara_id) + 0x200000
        # Color 1 / Color 2 character palettes
        for ci, ptr_off in ((0, 0x1), (1, 0x4)):
            src = read_int(data, chara_offset + ptr_off, 3) - 0xC00000
            dest = palette_offset + 0x1000 * chara_id + 0x10 + 0x80 * ci
            data[dest:dest + 0x20] = data[src:src + 0x20]
        # Objects (projectile) palette -> both default slots
        src = read_int(data, chara_offset + 0xA, 3) - 0xC00000
        for ci in (0, 1):
            dest = palette_offset + 0x1000 * chara_id + 0x30 + 0x80 * ci
            data[dest:dest + 0x20] = data[src:src + 0x20]
        # Icon palette -> both default slots
        src = read_int(data, chara_offset + 0x7, 3) - 0xC00000
        for ci in (0, 1):
            dest = palette_offset + 0x1000 * chara_id + 0x8 + 0x80 * ci
            data[dest:dest + 0x8] = data[src:src + 0x8]
        # Enable flag on the two defaults
        data[palette_offset + 0x1000 * chara_id] = 1
        data[palette_offset + 0x1000 * chara_id + 0x80] = 1

    # 3) Import the 30 extra slots/character from the Big Zam block (slots 2..31).
    imported = 0
    for chara_id in range(1, 10):
        for slot in range(2, 32):
            src = BZ_PAL_BASE + 0x1000 * chara_id + 0x80 * slot
            dest = palette_offset + 0x1000 * chara_id + 0x80 * slot
            block = bz[src:src + 0x50]  # flag word + icon(4) + char(16) + proj(16)
            data[dest:dest + 0x50] = block
            if block[0] == 1:
                imported += 1

    # 4) Header title + checksum + pad to 4 Mbit boundary (patcher-exact).
    data[0xFFC0:0xFFD5] = b"\xBE\xB0\xD7\xB0\xD1\xB0\xDDS " + TITLE.ljust(11) + b" "
    data += b"\x00" * ((len(data) + 0x7FFFF) // 0x80000 * 0x80000 - len(data))
    fix_checksum(data)

    open(out_path, "wb").write(data)
    print(f"wrote {out_path} from {src_path}: {imported} extra palettes, "
          f"{len(data):#x} bytes, sha1={sha1(bytes(data)).hexdigest()}")


if __name__ == "__main__":
    argv = [x for x in sys.argv[1:] if x != "--stacked"]
    stacked = "--stacked" in sys.argv[1:]
    src = argv[0] if len(argv) > 0 else CLEAN
    out = argv[1] if len(argv) > 1 else str(REPO / "build/sms_palettes.sfc")
    check_not_inplace(src, out)
    require_source(src, stacked)
    build(src, out)
