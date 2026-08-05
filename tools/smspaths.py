"""smspaths.py — locate the ROM source files (never tracked in git).

The ROM directory is resolved in this order:
  1. $SMS_ROM_DIR           (explicit override, any absolute path)
  2. <repo>/roms/           (historical in-tree location; gitignored)
  3. <repo>/../roms/        (a roms folder ABOVE the working tree — the maintainer's
                             preferred layout, so no ROM can ever be committed by accident)

The first candidate that actually contains the clean ROM wins. If none does, the
in-tree default is returned anyway so callers that only *compare* against the path
(e.g. "was I given the clean ROM as src?") keep working; callers that read it get a
normal FileNotFoundError naming the path. tools/run.sh mirrors the same order for
its default ROM.
"""
import os
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CLEAN_NAME = "Bishoujo Senshi Sailormoon S - Jougai Rantou! Shuyaku Soudatsusen (Japan).sfc"
BIGZAM_NAME = "sailor moon s big zam edition (hack).sfc"
# Sailor Moon Super S — Zenin Sanka!! (sequel, same engine family): the Sailor Saturn
# donor for the docs/saturn/ project. HiROM+FastROM, 3MB, header game code $FFB3=0x4A.
SUPERS_NAME = "Bishoujo Senshi Sailor Moon SuperS - Zenin Sanka!! Shuyaku Soudatsusen (Japan).sfc"
CLEAN_SHA1 = "bc0e29ee383574443226695215496eb0d09aaa1c"
SUPERS_SHA1 = "1ada34177e7384612ae83464288f3860e4c4426e"
# Single version source (issue #40): mkpatch4's default subtitle and the bundle build
# script both derive from this — bump it here when cutting a new all-patches build.
BUNDLE_VERSION = "0.22"
# Release revision for the two REFERENCE builds (maintainer, 2026-08-05):
#   Rev. S-XX   — the reference build, no Super S content
#   Rev. SS-XX  — the same plus Saturn (patch 100/101 + patch 17 + the stage port)
# Both carry XX on the title screen, which is the naked-eye tell a pad tester
# reports back. Two digits is the whole namespace; bump it here (or pass
# SMS_REV=NN) and rebuild — `tools/build_rev.sh` is the single recipe.
REV = "01"


def rom_dir():
    """Resolve the ROM directory (see module docstring for the order)."""
    cands = []
    env = os.environ.get("SMS_ROM_DIR")
    if env:
        cands.append(Path(env))
    cands += [REPO / "roms", REPO.parent / "roms"]
    for d in cands:
        if (d / CLEAN_NAME).is_file():
            return d
    return cands[1] if env else cands[0]  # in-tree default for path comparisons


def clean_rom():
    return str(rom_dir() / CLEAN_NAME)


def bigzam_rom():
    return str(rom_dir() / BIGZAM_NAME)


def supers_rom():
    return str(rom_dir() / SUPERS_NAME)


def require_source(src, stacked=False):
    """SHA gate (issue #12): the source is hashed UNCONDITIONALLY — path spelling is
    irrelevant. An exact clean-ROM match passes; anything else needs stacked=True
    (the builder chain passes already-patched ROMs deliberately, via --stacked).
    Returns "clean" or "stacked"."""
    from hashlib import sha1
    h = sha1(open(src, "rb").read()).hexdigest()
    if h == CLEAN_SHA1:
        return "clean"
    if stacked:
        return "stacked"
    raise SystemExit(
        f"error: source ROM hash mismatch — {src}\n"
        f"  got      sha1 {h}\n"
        f"  expected sha1 {CLEAN_SHA1} (clean '{CLEAN_NAME}')\n"
        f"  If you are deliberately stacking onto an already-patched ROM, pass --stacked.")


def check_not_inplace(src, out):
    """In-place patching is forbidden (CLAUDE.md; issue #56)."""
    import os
    if os.path.realpath(src) == os.path.realpath(out):
        raise SystemExit(f"error: src and out are the same file ({src}) — "
                         "in-place patching is forbidden; write the output to a new path")


# ---- shared ROM-image tooling (maintainer's dedup rule: common code that no patch
# ---- alters lives HERE; patch-specific logic stays in each builder) ----

def fix_checksum(data):
    """SNES header checksum over a power-of-two footprint (pad region repeated to
    fill; a power-of-two image sums directly). Single copy since 2026-07-30 — the
    2026-07-30 #9 bug (hang at power-of-two sizes) previously needed 14 fixes."""
    size = len(data)
    chk_size = max(0x80000, 1 << (size - 1).bit_length())
    if chk_size == size:
        chk = sum(data)
    else:
        half = chk_size // 2
        cd = bytes(data[half:])
        cd = (cd * ((half + len(cd) - 1) // len(cd)))[:half]
        chk = sum(data[:half]) + sum(cd)
    data[0xFFDE] = chk & 0xFF; data[0xFFDF] = chk >> 8 & 0xFF
    data[0xFFDC] = data[0xFFDE] ^ 0xFF; data[0xFFDD] = data[0xFFDF] ^ 0xFF


def trim_banks(data):
    """Drop trailing all-zero 64K banks (undo pad-to-boundary from a previous builder)."""
    while len(data) >= 0x10000 and data[-0x10000:] == bytes(0x10000):
        data = data[:-0x10000]
    return data


def next_bank(data):
    """Pad to the next 64K boundary and return (file_offset, snes_bank) of the fresh
    bank a bank-appending patch may claim."""
    bankbase = (len(data) + 0xFFFF) & ~0xFFFF
    while len(data) < bankbase:
        data += b"\x00"
    return bankbase, 0xC0 + (bankbase >> 16)


def write_bank(data, bankbase, blob):
    """Write an appended-bank blob with the issue-#27 guards: must fit one 64K bank,
    and the target region must be virgin (a collision means someone stacked
    standalone BPS files — forbidden; chain the builders)."""
    if len(blob) > 0x10000:
        raise SystemExit(f"error: appended blob {len(blob):#x} bytes exceeds one 64K bank")
    if any(data[bankbase:bankbase + len(blob)]):
        raise SystemExit(f"error: target bank at {bankbase:#x} is already occupied "
                         "(never stack standalone BPS files; chain the builders)")
    data[bankbase:bankbase + len(blob)] = blob
