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
CLEAN_SHA1 = "bc0e29ee383574443226695215496eb0d09aaa1c"


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
