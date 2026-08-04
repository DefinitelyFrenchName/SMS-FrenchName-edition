#!/usr/bin/env python3
"""wramdiff.py — diff two trace_wram.lua captures.

Bounds what a 65816 HOOK does to global state, which the DSP differential cannot
see at all. Compares the whole 128 KB of WRAM at every checkpoint and reports the
differing byte ranges as SNES addresses, then compares the watched-write logs so
a difference can be blamed on a specific writer PC.

    tools/saturn/wramdiff.py a b                     # what differs
    tools/saturn/wramdiff.py a b --expect-empty      # gate: nothing may differ
    tools/saturn/wramdiff.py a b --expect-only 7FF107-7FF108
    tools/saturn/wramdiff.py a b --require-addr 7FF107   # sensitivity assertion

Exits 1 when an expectation is violated.

WRAM offsets map to SNES addresses as $7E:0000 + offset, i.e. offset $1F107 is
$7F:F107. Ranges given to --expect-only/--require-addr are SNES addresses.
"""
import argparse
import os
import sys
from collections import defaultdict

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TRACE = os.path.join(REPO, "traces", "saturn")
WSIZE = 0x20000


def snes(off):
    return 0x7E0000 + off


def off_of(addr):
    return addr - 0x7E0000


def path(tag, ext):
    if os.path.exists(tag):
        return tag
    return os.path.join(TRACE, "wram_%s.%s" % (tag, ext))


def load(tag):
    idx, meta, snaps = path(tag, "idx"), [], []
    with open(idx) as f:
        for line in f:
            line = line.strip()
            if line.startswith("snap"):
                _, pf, n = line.split()
                snaps.append((int(pf), int(n)))
            elif line:
                meta.append(line)
    blob = open(path(tag, "bin"), "rb").read()
    return snaps, meta, blob, idx


def load_watch(tag):
    p = path(tag, "watch")
    if not os.path.exists(p):
        return None
    out = []
    with open(p) as f:
        for line in f:
            a = line.split()
            if len(a) == 4:
                out.append((int(a[0]), int(a[1], 16), int(a[2], 16), int(a[3], 16)))
    return out


def ranges(diff_offsets):
    """collapse a sorted offset list into contiguous ranges"""
    out = []
    for o in diff_offsets:
        if out and o == out[-1][1] + 1:
            out[-1][1] = o
        else:
            out.append([o, o])
    return out


def parse_spec(s):
    """'7FF107-7FF108,7E0010' -> list of (lo,hi) WRAM offsets"""
    out = []
    for part in s.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            a, b = part.split("-")
            out.append((off_of(int(a, 16)), off_of(int(b, 16))))
        else:
            v = off_of(int(part, 16))
            out.append((v, v))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("a")
    ap.add_argument("b")
    ap.add_argument("--expect-empty", action="store_true")
    ap.add_argument("--expect-only", default=None,
                    help="comma list of SNES addr/ranges that MAY differ")
    ap.add_argument("--require-addr", default=None,
                    help="SNES addr/ranges that MUST differ — the sensitivity "
                         "assertion, so an empty diff is never confused with a "
                         "differ that cannot see anything")
    ap.add_argument("--max-report", type=int, default=20)
    a = ap.parse_args()

    sa, ma, ba, pa = load(a.a)
    sb, mb, bb, pb = load(a.b)
    print("A  %s" % pa)
    for m in ma:
        print("     %s" % m)
    print("B  %s" % pb)
    for m in mb:
        print("     %s" % m)

    bad = [m for m in ma + mb if "FAIL" in m or "TIMEOUT" in m]
    if bad:
        print("\nHARNESS FAILURE in a capture — no verdict is possible:")
        for m in bad:
            print("   %s" % m)
        return 1
    if not sa or not sb:
        print("\nEMPTY CAPTURE — no snapshots recorded. Broken harness, not evidence.")
        return 1
    for tag, s, blob in ((a.a, sa, ba), (a.b, sb, bb)):
        if len(blob) != len(s) * WSIZE:
            print("\nTRUNCATED CAPTURE %s: %d snapshots but %d bytes (expected %d)"
                  % (tag, len(s), len(blob), len(s) * WSIZE))
            return 1

    fa = {pf: n for pf, n in sa}
    fb = {pf: n for pf, n in sb}
    common = sorted(set(fa) & set(fb))
    print("\ncheckpoints: A=%d B=%d common=%d" % (len(sa), len(sb), len(common)))
    if set(fa) != set(fb):
        print("  WARNING: checkpoint frames differ — comparing the common ones only")

    all_diff = defaultdict(list)     # offset -> [(pf, va, vb)]
    for pf in common:
        va = ba[fa[pf] * WSIZE:(fa[pf] + 1) * WSIZE]
        vb = bb[fb[pf] * WSIZE:(fb[pf] + 1) * WSIZE]
        if va == vb:
            continue
        for o in range(WSIZE):
            if va[o] != vb[o]:
                all_diff[o].append((pf, va[o], vb[o]))

    print("distinct WRAM bytes that ever differ: %d" % len(all_diff))
    if all_diff:
        rs = ranges(sorted(all_diff))
        print("differing ranges (SNES addresses), %d total:" % len(rs))
        for lo, hi in rs[:a.max_report]:
            first = all_diff[lo][0]
            print("   $%06X-$%06X  (%d bytes)  first at f%d: A=$%02X B=$%02X"
                  % (snes(lo), snes(hi), hi - lo + 1, first[0], first[1], first[2]))
        if len(rs) > a.max_report:
            print("   ... %d more ranges" % (len(rs) - a.max_report))
        percp = defaultdict(int)
        for o, hits in all_diff.items():
            for pf, _, _ in hits:
                percp[pf] += 1
        print("bytes differing per checkpoint: %s"
              % ", ".join("f%d:%d" % (p, percp[p]) for p in sorted(percp)))

    # watched writes: attribute a difference to a writer
    wa, wb = load_watch(a.a), load_watch(a.b)
    if wa is not None and wb is not None:
        print("\nwatched writes: A=%d B=%d" % (len(wa), len(wb)))
        if wa != wb:
            n = 0
            for i in range(max(len(wa), len(wb))):
                x = wa[i] if i < len(wa) else None
                y = wb[i] if i < len(wb) else None
                if x == y:
                    continue
                # the watch log already records SNES addresses (Mesen hands the
                # callback the CPU address even though the range is given in WRAM
                # offsets) — converting again would print $FDF100 for $7FF100
                fmt = lambda t: "--" if t is None else \
                    "f%d $%06X<=$%02X by PC $%06X" % (t[0], t[1], t[2], t[3])
                print("   A: %-44s B: %s" % (fmt(x), fmt(y)))
                n += 1
                if n >= a.max_report:
                    print("   ...")
                    break
        else:
            print("   identical")

    # ---- judge -------------------------------------------------------------
    print()
    if a.require_addr:
        want = parse_spec(a.require_addr)
        hit = any(any(lo <= o <= hi for lo, hi in want) for o in all_diff)
        if not hit:
            print("VERDICT: FAIL")
            print("   %s was expected to differ and did not — the differ cannot see"
                  " a change it is pointed at, so it proves nothing about changes it"
                  " is NOT pointed at" % a.require_addr)
            return 1
        if not (a.expect_empty or a.expect_only):
            print("VERDICT: PASS — required addresses differ (sensitivity confirmed)")
            return 0

    if not (a.expect_empty or a.expect_only):
        print("no expectation declared — reporting only")
        return 0

    fails = []
    if a.expect_empty and all_diff:
        fails.append("expected identical WRAM, got %d differing bytes" % len(all_diff))
    if a.expect_only:
        allow = parse_spec(a.expect_only)
        stray = [o for o in all_diff if not any(lo <= o <= hi for lo, hi in allow)]
        if stray:
            rs = ranges(sorted(stray))
            fails.append("%d bytes differ outside the declared set, in %d ranges: %s"
                         % (len(stray), len(rs),
                            ", ".join("$%06X-$%06X" % (snes(l), snes(h)) for l, h in rs[:8])))

    if fails:
        print("VERDICT: FAIL")
        for f in fails:
            print("   %s" % f)
        return 1
    print("VERDICT: PASS — every difference is inside the declared expectation")
    return 0


if __name__ == "__main__":
    sys.exit(main())
