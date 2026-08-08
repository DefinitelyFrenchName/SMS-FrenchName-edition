#!/usr/bin/env python3
"""Verify the edit-region map in docs/project/patch_notes.md against the .bps files.

  python3 tools/checkpatchmap.py         # verify the map
  python3 tools/checkpatchmap.py -v      # ...and print each patch's measured regions

WHY THIS EXISTS. The edit-region map is the document a future patch author
trusts to know what collides with what. It is also the document nobody re-reads:
it was written when there were fourteen patches, and a patch that grows a region
does not announce it. Two of its rows were already wrong when this was written —
patch 3 was described as three "hooks" when two of them are ~97-byte in-place
rewrites, and patch 15 was described as 6 bytes when it changes 7.

WHAT IS CHECKED, and the distinction matters:

  * every documented range is EXACTLY a changed run of `clean -> patched`, and
    every changed run is documented — both directions, so the map can neither
    understate a patch nor invent a region for one;
  * the appended-bank and header columns;
  * **the claim the section exists to make**: that the in-place regions are
    pairwise disjoint. Proven across all 19 tracked standalone patches rather
    than asserted in prose (the variant pairs — 1/1b, 10/10b — are alternatives
    and edit the same bytes by design, so they are excluded by their names);
  * **the flip side, which is the trap in HANDOFF §5**: every bank-appending
    standalone starts its bank at the SAME offset, so applying two of them in
    sequence silently overwrites the first one's code while its hooks still jump
    there. A trap that is only written down is one nobody has re-derived.

WHAT THIS CANNOT SEE: a builder that writes a byte identical to the one already
there. This measures the ARTIFACTS — what a player applies — not the builders'
write sets, and a write that changes nothing collides with nothing.
"""
import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path as _P

REPO = _P(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
from smspaths import clean_rom  # noqa: E402

NOTES = REPO / "docs" / "project" / "patch_notes.md"
FLIPS = REPO / "tools" / "Flips" / "flips"
HEADER = range(0xFFC0, 0x10000)
APPENDED = 0x280000                      # the clean image ends here

ROW = re.compile(r"^\|\s*\*\*([0-9]+b?)\*\*\s*\|\s*`([^`]+\.bps)`\s*\|(.*?)\|(.*?)\|(.*?)\|\s*$")
RANGE = re.compile(r"`0x([0-9A-F]{5})(?:-([0-9A-F]{5}))?`")


class Fail(Exception):
    pass


def parse_map():
    """[(patch, bps, [(lo, hi_inclusive), …], appended-or-None, header-class)]"""
    rows = []
    for line in NOTES.read_text(encoding="utf-8").splitlines():
        m = ROW.match(line)
        if not m:
            continue
        patch, bps, regions, appended, header = m.groups()
        rr = [(int(a, 16), int(b or a, 16)) for a, b in RANGE.findall(regions)]
        app = re.search(r"@ `0x([0-9A-F]+)`", appended)
        rows.append((patch, bps, rr, int(app.group(1), 16) if app else None,
                     "title" if "title" in header else "checksum"))
    if not rows:
        raise Fail("no edit-region rows found — has the table's shape changed?")
    return rows


def apply_bps(bps, out):
    r = subprocess.run([str(FLIPS), "--apply", str(REPO / "build" / bps), clean_rom(), out],
                       capture_output=True)
    if r.returncode:
        raise Fail(f"flips could not apply {bps}: {r.stderr.decode().strip()}")
    return open(out, "rb").read()


def changed_runs(clean, patched):
    """Contiguous [lo, hi] runs that differ, below the appended banks and outside
    the header — the two regions every patch touches and no map should repeat."""
    out, n, block = [], min(len(patched), APPENDED), 0x1000
    for base in range(0, n, block):        # 2.5 MB byte-at-a-time is 19x too slow
        end = min(base + block, n)
        if clean[base:end] == patched[base:end]:
            continue
        i = base
        while i < end:
            if clean[i] != patched[i]:
                j = i
                while j < end and clean[j] != patched[j]:
                    j += 1
                if i not in HEADER:
                    # a run that ends exactly on a block edge continues in the next
                    if out and out[-1][1] == i - 1:
                        out[-1] = (out[-1][0], j - 1)
                    else:
                        out.append((i, j - 1))
                i = j
            else:
                i += 1
    return out


def measure(rows, clean, tmp, verbose=False):
    """Compare each row against its artifact; return {patch: set(offsets)}."""
    fails, sets = [], {}
    for patch, bps, doc_rr, doc_app, doc_hdr in rows:
        try:
            patched = apply_bps(bps, f"{tmp}/{bps}.sfc")
        except Fail as e:
            fails.append(str(e))
            continue
        got = changed_runs(clean, patched)
        sets[patch] = {o for lo, hi in got for o in range(lo, hi + 1)}
        if verbose:
            print(f"  patch {patch:<4} " + " · ".join(
                f"0x{lo:05X}-{hi:05X}" if hi > lo else f"0x{lo:05X}" for lo, hi in got))
        if got != doc_rr:
            missing = [r for r in got if r not in doc_rr]
            phantom = [r for r in doc_rr if r not in got]
            fails.append(
                f"patch {patch}: the map does not match {bps}"
                + (f" — undocumented: {['0x%05X-%05X' % r for r in missing]}" if missing else "")
                + (f" — documented but unchanged: {['0x%05X-%05X' % r for r in phantom]}"
                   if phantom else ""))
        app = APPENDED if len(patched) > APPENDED else None
        if app != doc_app:
            fails.append(f"patch {patch}: appended bank {app and hex(app)} "
                         f"but the map says {doc_app and hex(doc_app)}")
        hdr = "title" if any(clean[o] != patched[o] for o in range(0xFFC0, 0xFFDC)) else "checksum"
        if hdr != doc_hdr:
            fails.append(f"patch {patch}: header is {hdr}, the map says {doc_hdr}")
    return sets, fails


def disjointness(sets):
    """The claim the map exists to make. Variants (1b of 1, 10b of 10) are
    alternatives by naming convention and edit the same bytes deliberately."""
    fails, ids = [], sorted(sets)
    base = lambda p: p.rstrip("ab")
    for i, x in enumerate(ids):
        for y in ids[i + 1:]:
            if base(x) == base(y):
                continue
            overlap = sets[x] & sets[y]
            if overlap:
                fails.append(f"patches {x} and {y} both edit "
                             f"{['0x%05X' % o for o in sorted(overlap)[:4]]} — the map claims "
                             "the in-place regions are pairwise disjoint")
    return fails


def selftests(rows, clean, tmp):
    """Negative controls: the comparison must catch a map that is wrong, and the
    disjointness prover must catch an overlap. A checker whose failure path has
    never run is a checker nobody has tested."""
    bad = []
    patch, bps, rr, app, hdr = rows[0]
    moved = [(rr[0][0] + 1, rr[0][1] + 1)] + rr[1:]
    _, fails = measure([(patch, bps, moved, app, hdr)], clean, tmp)
    if not fails:
        bad.append("a region shifted by one byte was not caught")
    _, fails = measure([(patch, bps, rr, 0x123456, hdr)], clean, tmp)
    if not fails:
        bad.append("a wrong appended-bank offset was not caught")
    if not disjointness({"x": {1, 2, 3}, "y": {3, 4}}):
        bad.append("an overlap between two patches was not caught")
    if disjointness({"1": {1, 2}, "1b": {1, 2}}):
        bad.append("the variant pair 1/1b was reported as an overlap")
    return bad


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    if not FLIPS.exists():
        print("checkpatchmap: flips is not present — see docs/project/toolchain.md")
        sys.exit(2)
    clean = open(clean_rom(), "rb").read()
    rows = parse_map()

    with tempfile.TemporaryDirectory() as tmp:
        sets, fails = measure(rows, clean, tmp, args.verbose)
        fails += disjointness(sets)
        fails += [f"SELF-TEST: {b}" for b in selftests(rows, clean, tmp)]

    appending = {p for p, _, _, a, _ in rows if a is not None}
    if fails:
        for line in fails:
            print(f"  \033[31mFAIL\033[0m  {line}")
        print(f"\n\033[31m{len(fails)} problems\033[0m in the edit-region map")
        sys.exit(1)
    print(f"\033[32mALL PASS\033[0m ({len(rows)} standalone patches, "
          f"{sum(len(s) for s in sets.values())} changed bytes accounted for)")
    print(f"  in-place regions are pairwise disjoint (variants 1/1b and 10/10b aside)")
    print(f"  {len(appending)} bank-appending patches, all starting at 0x{APPENDED:X} — "
          "which is why standalone BPS must never be chained (HANDOFF §5)")


if __name__ == "__main__":
    main()
