#!/usr/bin/env python3
"""Escape matrix: P1 rep timing (sloppy/perfect) x P2 escape (guard/mash/bdash)
on clean and patched ROMs. Verdict per cell.

Rewritten 2026-08-06 (issue #13). The original could print a full matrix of
verdicts without ever having run the emulator: the subprocess call discarded its
exit status, the parse then read `traces/mx.txt` unconditionally — so a previous
run's trace produced a confident, wrong table — and the "STACKED" ROM it named
(`build/sms_stacked.sfc`) is not produced by any builder in the tree, so that
whole column was measuring the clean ROM twice. It also wrote its generated plan
into the TRACKED `tools/trace_plan.lua`, rewriting a versioned file as a side
effect of running an experiment.

Now: the trace is deleted before each run, the run is checked, the ROM must
exist, and the plan goes to a temp file that `trace.lua` picks up via
$TRACE_PLAN.
"""
import argparse
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

P1_STYLES = {
    # pre-patch optimal habits: early buffered 66, early jab press
    'sloppy':  ("[81]={}, [83]={right=true}, [85]={}, [87]={right=true}, [89]={},",
                "[111]={down=true,y=true}, [113]={down=true},"),
    # frame-perfect for the patched build: late 66, press 115
    'perfect': ("[95]={}, [97]={right=true}, [98]={}, [99]={right=true}, [101]={},",
                "[115]={down=true,y=true}, [117]={down=true},"),
}
P2_ESCAPES = {
    'guard': "[70]={right=true, down=true}",
    'mash':  ", ".join(f"[{t}]={{y=true}}, [{t+2}]={{}}" for t in range(90, 140, 4)),
    'bdash': "[116]={right=true}, [117]={}, [119]={right=true}, [121]={}",
}
# The patched column needs a ROM carrying patch 1's gate. Default to the canonical
# build; override with --patched. It is gitignored, so say how to make one.
DEFAULT_PATCHED = "build/SailorMoonS_FrenchName_v0.7_all5.sfc"
TRACE_OUT = REPO / "traces" / "mx.txt"


def run_cell(rom, p1, p2):
    dash, jab = P1_STYLES[p1]
    esc = P2_ESCAPES[p2]
    plan = f"""POKES = {{ {{ t = 5, addr = 0x1021, val = 0xE8 }} }}
PLAN = {{
  [10] = {{ down = true }},
  [60] = {{ down = true, y = true }},
  [62] = {{ down = true }},
  [77] = {{ down = true, x = true }},
  [80] = {{ down = true }},
  {dash}
  {jab}
}}
P2PLAN = {{ {esc} }}
LOGFROM = 55
LOGTO = 260
OUT = "mx.txt"
"""
    env = dict(os.environ)
    if rom:
        env["ROM"] = rom
    with tempfile.NamedTemporaryFile("w", suffix="_trace_plan.lua", delete=False) as fh:
        fh.write(plan)
        env["TRACE_PLAN"] = fh.name
    try:
        # A stale trace is indistinguishable from a fresh one once parsed, so
        # remove it first: no file + a checked run means a parse can only ever
        # read this cell's output.
        if TRACE_OUT.exists():
            TRACE_OUT.unlink()
        subprocess.run([str(REPO / "tools/run.sh"), str(REPO / "tools/trace.lua"), "60"],
                       env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                       timeout=120, check=True, cwd=REPO)
    finally:
        os.unlink(env["TRACE_PLAN"])
    if not TRACE_OUT.exists():
        raise SystemExit(f"error: the run produced no trace at {TRACE_OUT} — "
                         "the emulator started but the script wrote nothing")

    hits, dashf, p2free, prev_hp = [], None, None, None
    for line in TRACE_OUT.read_text().splitlines():
        m = re.match(r't=(\d+) p1\[act=(\w+)', line)
        if not m:
            continue
        t, act = int(m.group(1)), m.group(2)
        hp = int(re.search(r'hp=(\w+)', line).group(1), 16)
        p2a = re.search(r'p2\[act=(\w+)', line).group(1)
        if act == '60' and dashf is None:
            dashf = t
        if prev_hp is not None and hp < prev_hp and t > 90:
            hits.append(t)
        if t > 100 and p2a in ('41', '53', '26', '0D', '0F', '55', '57') and p2free is None:
            p2free = f"{t}:{p2a}"
        prev_hp = hp
    verdict = 'LOOP HOLDS' if hits and not p2free else ('P2 ESCAPED' if p2free else 'loop dropped')
    return dashf, hits, p2free, verdict


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--patched", default=DEFAULT_PATCHED,
                    help=f"ROM carrying patch 1's gate (default: {DEFAULT_PATCHED})")
    a = ap.parse_args()
    patched = REPO / a.patched
    if not patched.is_file():
        raise SystemExit(f"error: patched ROM not found: {a.patched}\n"
                         "  build it first, e.g. the canonical chain in HANDOFF.md §2, "
                         "or pass --patched <rom>")
    roms = {'CLEAN': '', 'PATCHED': str(patched)}
    for p2 in P2_ESCAPES:
        for romtag, style in [('CLEAN', 'sloppy'), ('PATCHED', 'sloppy'), ('PATCHED', 'perfect')]:
            dashf, hits, p2free, verdict = run_cell(roms[romtag], style, p2)
            print(f"{romtag:8s} P1={style:7s} P2={p2:6s} | dash@{dashf} "
                  f"3rd-hit@{hits} P2-action={p2free} => {verdict}")


if __name__ == "__main__":
    sys.exit(main())
