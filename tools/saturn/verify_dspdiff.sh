#!/bin/bash
# verify_dspdiff.sh — self-check the DSP differential harness BEFORE trusting it.
#
# An empty diff is only meaningful from a differ that is known to be (a)
# deterministic, (b) not perturbed by its own instrumentation, and (c) able to
# see a change it is pointed at. This project has repeatedly been bitten by
# probes that reported nothing because they were broken, so the harness proves
# all three on every run, plus that its verdict can actually come out FAIL:
#
#   1 DETERMINISM   same ROM, same config, twice        -> must be identical
#   2 INERTNESS     poke the VANILLA transposes back    -> must be identical
#                   (proves a divergence is the VALUE, not the act of poking)
#   3 SENSITIVITY   poke the proposed retune            -> V4.PITCHL must differ
#   4 NEGATIVE      demand "identical" of a known-different pair -> must FAIL
#
# Only after all four pass is a comparison of two real builds worth reading.
#
#   ROM=<saturn build> tools/saturn/verify_dspdiff.sh
set -u
cd "$(dirname "$0")/../.."
ROM="${ROM:-build/saturn/SailorMoonS_REFsaturn_v0.14.9-hidden-stage.sfc}"
SHELL_ID="${SHELL_ID:-6}"
FRAMES="${FRAMES:-900}"
fail=0

[ -f "$ROM" ] || { echo "no such ROM: $ROM"; exit 1; }

run() {
  local tag="$1" list="${2:-}"
  rm -f "traces/saturn/dsp_$tag.dig" "traces/saturn/dsp_$tag.log"
  if [ -n "$list" ]; then
    TAG="$tag" SHELL_ID="$SHELL_ID" FRAMES="$FRAMES" ROM="$ROM" POKE_LIST="$list" \
      tools/run.sh tools/saturn/trace_dsp.lua 700 >/dev/null 2>&1
  else
    TAG="$tag" SHELL_ID="$SHELL_ID" FRAMES="$FRAMES" ROM="$ROM" \
      tools/run.sh tools/saturn/trace_dsp.lua 700 >/dev/null 2>&1
  fi
  if [ ! -s "traces/saturn/dsp_$tag.dig" ]; then
    echo "CAPTURE FAILED: traces/saturn/dsp_$tag.dig missing or empty"
    fail=1
  fi
}

# $1 = label, $2 = "pass"|"fail" (the REQUIRED outcome), rest = dspdiff args.
# Taking the required outcome as an argument is what lets check 4 assert that a
# FAIL verdict is reachable at all: a gate that cannot fail is not a gate, and
# the first version of this script cheerfully printed ALL PASS through three
# Python tracebacks because it read `tail`'s exit status instead of the differ's.
check() {
  local label="$1" want="$2"; shift 2
  local out rc
  out="$(tools/saturn/dspdiff.py "$@" 2>&1)"; rc=$?
  echo "--- $label (must $want) ---"
  echo "$out" | tail -4
  if [ "$want" = pass ] && [ "$rc" -ne 0 ]; then echo "  !! expected PASS, got exit $rc"; fail=1; fi
  if [ "$want" = fail ] && [ "$rc" -eq 0 ]; then echo "  !! expected FAIL, got exit 0"; fail=1; fi
  echo
}

echo "=== capturing (ROM=$(basename "$ROM"), shell $SHELL_ID, $FRAMES frames) ==="
run v1    ""
run v2    ""
run vnoop "FE,FE,FF,FD"
run vfix  "FB,FB,FB,FB"
echo

if [ "$fail" != 0 ]; then
  echo "HARNESS SELF-CHECK: FAILED during capture — no diff from this run means anything"
  exit 1
fi

check "1 DETERMINISM"            pass v1 v2    --expect-empty
check "2 INERTNESS (no-op poke)" pass v1 vnoop --expect-empty
check "3 SENSITIVITY"            pass v1 vfix  --require-reg V4.PITCHL
check "3b PITCH-ONLY"            pass v1 vfix  --expect-pitch-only
check "4 NEGATIVE CONTROL"       fail v1 vfix  --expect-empty

if [ "$fail" = 0 ]; then
  echo "HARNESS SELF-CHECK: ALL PASS — comparisons from it can be believed"
else
  echo "HARNESS SELF-CHECK: FAILED — do not trust any diff from this harness"
fi
exit $fail
