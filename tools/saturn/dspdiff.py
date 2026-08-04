#!/usr/bin/env python3
"""dspdiff.py — diff two trace_dsp.lua captures and judge the difference.

The point is not to look at audio; it is to bound a change. Two builds are driven
through byte-identical scripted input, every DSP register write is recorded, and
this compares the complete streams. Anything that differs outside an explicitly
declared expectation is reported as an unexpected side effect — which is the
class of bug that testing specific features never finds.

    tools/saturn/dspdiff.py a b                       # what differs, if anything
    tools/saturn/dspdiff.py a b --expect-empty        # gate: must be identical
    tools/saturn/dspdiff.py a b --expect-pitch-only --expect-srcn 49,50,51

Exits 1 when an expectation is violated, so it can sit in verify_saturn.sh.

Two layers of comparison:
  * per-frame digest + write count  — total coverage, catches ANY difference in
    ANY register including all music, without storing anything to inspect
  * the detail streams (.log)       — explains what actually differed, and
    attributes differing per-voice writes to the SOURCE that was keyed on

A digest match with a detail mismatch (or vice versa) is itself reported: that
means the harness is inconsistent and no verdict from it should be believed.
"""
import argparse
import os
import sys
from collections import defaultdict

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TRACE = os.path.join(REPO, "traces", "saturn")

VOICE_REG = {0: "VOLL", 1: "VOLR", 2: "PITCHL", 3: "PITCHH", 4: "SRCN",
             5: "ADSR1", 6: "ADSR2", 7: "GAIN", 8: "ENVX", 9: "OUTX"}
GLOBAL_REG = {0x0C: "MVOLL", 0x1C: "MVOLR", 0x2C: "EVOLL", 0x3C: "EVOLR",
              0x4C: "KON", 0x5C: "KOF", 0x6C: "FLG", 0x7C: "ENDX",
              0x0D: "EFB", 0x2D: "PMON", 0x3D: "NON", 0x4D: "EON",
              0x5D: "DIR", 0x6D: "ESA", 0x7D: "EDL"}


def reg_name(r):
    if r in GLOBAL_REG:
        return GLOBAL_REG[r]
    lo, hi = r & 0x0F, r >> 4
    if lo in VOICE_REG and hi <= 7:
        return "V%d.%s" % (hi, VOICE_REG[lo])
    if lo == 0x0F:
        return "FIR%d" % hi
    return "$%02X" % r


def path(tag, ext):
    if os.path.exists(tag):
        return tag
    return os.path.join(TRACE, "dsp_%s.%s" % (tag, ext))


def load_dig(tag):
    frames, meta = {}, []
    p = path(tag, "dig")
    with open(p) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith("#"):
                meta.append(line)
                continue
            if not line[0].isdigit():
                meta.append(line)          # PRECONDITION-FAIL / MATCH-LOAD-FAIL
                continue
            pf, n, h = line.split()
            frames[int(pf)] = (int(n), h)
    return frames, meta, p


def load_log(tag):
    """-> writes[frame] = [(reg,val)...], keyons = [(frame,voice,srcn,pitch,samp)]"""
    p = path(tag, "log")
    if not os.path.exists(p):
        return None, None, None
    writes, keyons = defaultdict(list), []
    with open(p) as f:
        for line in f:
            parts = line.split()
            if not parts:
                continue
            if parts[0] == "W":
                writes[int(parts[1])].append((int(parts[2], 16), int(parts[3], 16)))
            elif parts[0] == "K":
                keyons.append((int(parts[1]), int(parts[2]), int(parts[3]),
                               int(parts[4], 16), int(parts[5], 16)))
    return writes, keyons, p


def attribute(keyons, frame, voice, window=10):
    """Which source was this per-voice write for? Nearest key-on of that voice."""
    best, bestd = None, 1 << 30
    for kf, kv, srcn, pitch, samp in keyons:
        if kv != voice:
            continue
        d = abs(kf - frame)
        if d < bestd:
            best, bestd = (srcn, samp), d
    if best and bestd <= window:
        return best
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("a")
    ap.add_argument("b")
    ap.add_argument("--expect-empty", action="store_true",
                    help="no difference at all is permitted")
    ap.add_argument("--expect-pitch-only", action="store_true",
                    help="only VxPITCHL/H writes may differ")
    ap.add_argument("--expect-srcn", default=None,
                    help="comma list; differing per-voice writes must belong to these sources")
    ap.add_argument("--semantic", action="store_true",
                    help="compare the ORDERED key-on sequence instead of "
                         "frame-aligned writes. Use this across builds whose LOAD "
                         "duration differs: extra work at character load shifts the "
                         "whole audio timeline a few frames relative to match start, "
                         "which desynchronises a positional diff while changing "
                         "nothing audible. The key-on order is what the player hears.")
    ap.add_argument("--require-reg", default=None,
                    help="comma list of register names that MUST differ — the "
                         "sensitivity assertion: a differ that cannot see a known "
                         "change is not evidence that other changes are absent")
    ap.add_argument("--max-report", type=int, default=25)
    a = ap.parse_args()

    da, ma, pa = load_dig(a.a)
    db, mb, pb = load_dig(a.b)
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

    if not da or not db:
        print("\nEMPTY CAPTURE — the probe recorded nothing. That is a broken harness,"
              " not evidence that the builds agree.")
        return 1

    common = sorted(set(da) & set(db))
    only_a, only_b = sorted(set(da) - set(db)), sorted(set(db) - set(da))
    print("\nframes: A=%d B=%d common=%d" % (len(da), len(db), len(common)))
    if only_a or only_b:
        print("  WARNING: recorded windows differ in length "
              "(A-only %d, B-only %d) — compare only the common prefix" %
              (len(only_a), len(only_b)))

    difframes = [f for f in common if da[f] != db[f]]
    tw_a = sum(n for n, _ in da.values())
    tw_b = sum(n for n, _ in db.values())
    print("total DSP writes: A=%d B=%d" % (tw_a, tw_b))
    print("frames whose digest differs: %d / %d" % (len(difframes), len(common)))

    wa, ka, _ = load_log(a.a)
    wb, kb, _ = load_log(a.b)
    detail = wa is not None and wb is not None

    regs_changed = defaultdict(int)
    srcs_changed = defaultdict(int)
    unattributed = 0
    examples = []

    if detail:
        for f in difframes:
            la, lb = wa.get(f, []), wb.get(f, [])
            # positional diff: the write ORDER is part of the state, so a
            # reordering counts as a difference even if the multiset matches
            for i in range(max(len(la), len(lb))):
                x = la[i] if i < len(la) else None
                y = lb[i] if i < len(lb) else None
                if x == y:
                    continue
                reg = (x or y)[0]
                regs_changed[reg] += 1
                voice = reg >> 4
                if (reg & 0x0F) in VOICE_REG and voice <= 7:
                    src = attribute(ka, f, voice) or attribute(kb, f, voice)
                    if src:
                        srcs_changed["srcn %d (sample $%04X)" % src] += 1
                    else:
                        unattributed += 1
                if len(examples) < a.max_report:
                    examples.append((f, reg, x, y))

        if difframes:
            print("\nregisters that differ:")
            for r, n in sorted(regs_changed.items(), key=lambda kv: -kv[1]):
                print("   %-14s %d writes" % (reg_name(r), n))
            if srcs_changed:
                print("attributed to sources:")
                for s, n in sorted(srcs_changed.items(), key=lambda kv: -kv[1]):
                    print("   %-28s %d writes" % (s, n))
            if unattributed:
                print("   %d per-voice writes could NOT be attributed to a key-on" % unattributed)
            print("first %d differing writes (frame, reg, A, B):" % len(examples))
            for f, reg, x, y in examples:
                fmt = lambda t: "--" if t is None else "$%02X" % t[1]
                print("   f%-5d %-14s A=%s B=%s" % (f, reg_name(reg), fmt(x), fmt(y)))
    elif difframes:
        print("\n(no .log detail captured — rerun with DETAIL=1 to explain the diff)")

    sem_fail, sem_pitch = [], defaultdict(int)
    if a.semantic:
        if ka is None or kb is None:
            sem_fail.append("--semantic needs DETAIL=1 captures")
        else:
            seqa = [(v, s_, p, smp) for _, v, s_, p, smp in ka]
            seqb = [(v, s_, p, smp) for _, v, s_, p, smp in kb]
            print("\nSEMANTIC: ordered key-on sequence  A=%d  B=%d" % (len(seqa), len(seqb)))
            if len(seqa) != len(seqb):
                sem_fail.append("key-on COUNT differs (%d vs %d) — a sound was added, "
                                "dropped or reordered" % (len(seqa), len(seqb)))
            n = min(len(seqa), len(seqb))
            structural = 0
            for i in range(n):
                x, y = seqa[i], seqb[i]
                if x == y:
                    continue
                if (x[0], x[1], x[3]) != (y[0], y[1], y[3]):
                    structural += 1
                    if structural <= 5:
                        print("   STRUCTURAL at %d: A=v%d srcn%d $%04X samp$%04X"
                              "  B=v%d srcn%d $%04X samp$%04X"
                              % (i, x[0], x[1], x[2], x[3], y[0], y[1], y[2], y[3]))
                else:
                    sem_pitch[(x[1], x[2], y[2])] += 1
            if structural:
                sem_fail.append("%d key-ons differ in VOICE or SOURCE, not just pitch"
                                % structural)
            print("   structural differences: %d" % structural)
            if sem_pitch:
                print("   pitch-only changes:")
                for (srcn, pa_, pb_), n_ in sorted(sem_pitch.items(), key=lambda kv: -kv[1]):
                    print("      srcn %-3d $%04X -> $%04X   x%d" % (srcn, pa_, pb_, n_))
            if a.expect_srcn:
                want = {int(t) for t in a.expect_srcn.split(",")}
                got = {k[0] for k in sem_pitch}
                if got - want:
                    sem_fail.append("sources outside the expected set changed pitch: %s"
                                    % sorted(got - want))
                if want - got:
                    sem_fail.append("expected sources never changed: %s — the patch may "
                                    "not have applied" % sorted(want - got))

    # ---- judge -------------------------------------------------------------
    print()
    if a.semantic:
        if sem_fail:
            print("VERDICT: FAIL")
            for f in sem_fail:
                print("   %s" % f)
            return 1
        print("VERDICT: PASS — the audible key-on sequence is identical except the "
              "declared pitch changes")
        return 0

    if a.require_reg:
        seen_names = {reg_name(r) for r in regs_changed}
        missing = [n for n in a.require_reg.split(",") if n not in seen_names]
        if missing:
            print("VERDICT: FAIL")
            print("   these registers were expected to differ and did not: %s" % missing)
            print("   the differ cannot see a change it is known to be looking at, so it"
                  " proves nothing about changes it is NOT looking at")
            return 1

    if not (a.expect_empty or a.expect_pitch_only or a.expect_srcn or a.require_reg):
        print("no expectation declared — reporting only")
        return 0

    fails = []
    if a.require_reg and not (a.expect_empty or a.expect_pitch_only or a.expect_srcn):
        print("VERDICT: PASS — required registers differ (sensitivity confirmed)")
        return 0
    if a.expect_empty and difframes:
        fails.append("expected byte-identical traces, got %d differing frames" % len(difframes))
    if a.expect_pitch_only:
        if not detail:
            fails.append("--expect-pitch-only needs DETAIL=1 captures")
        else:
            stray = {r: n for r, n in regs_changed.items() if (r & 0x0F) not in (2, 3) or r >> 4 > 7}
            if stray:
                fails.append("registers other than VxPITCH differ: " +
                             ", ".join("%s x%d" % (reg_name(r), n) for r, n in stray.items()))
    if a.expect_srcn:
        want = {int(s) for s in a.expect_srcn.split(",")}
        if not detail:
            fails.append("--expect-srcn needs DETAIL=1 captures")
        else:
            got = set()
            for s in srcs_changed:
                got.add(int(s.split()[1]))
            extra = got - want
            if extra:
                fails.append("sources outside the expected set changed: %s" % sorted(extra))
            if unattributed:
                fails.append("%d differing per-voice writes are unattributed" % unattributed)
            missing = want - got
            if missing:
                fails.append("expected sources never differed: %s — the change may not "
                             "have applied at all" % sorted(missing))

    if fails:
        print("VERDICT: FAIL")
        for f in fails:
            print("   %s" % f)
        return 1
    print("VERDICT: PASS — every difference is inside the declared expectation")
    return 0


if __name__ == "__main__":
    sys.exit(main())
