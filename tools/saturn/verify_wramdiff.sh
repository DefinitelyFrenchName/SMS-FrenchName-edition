#!/bin/bash
# verify_wramdiff.sh — self-check the WRAM differential harness before trusting it.
#
# Same discipline as verify_dspdiff.sh, for the other state vector. An empty WRAM
# diff is a strong claim ("this hook touched nothing global"), so the harness has
# to prove it can produce a non-empty one:
#
#   1 DETERMINISM   same ROM, vanilla session, twice  -> all 128 KB identical
#   2 SENSITIVITY   inject one known byte             -> found, and ONLY it
#   3 NEGATIVE      demand "identical" of that pair   -> must FAIL
#
# Check 2 injects into $7F:F1FF — inside the project's own state page, unused by
# the current design — so the sensitivity probe cannot itself perturb the game.
#
#   ROM=<saturn build> tools/saturn/verify_wramdiff.sh
set -u
cd "$(dirname "$0")/../.."
ROM="${ROM:-build/saturn/SailorMoonS_REFsaturn_v0.14.9-hidden-stage.sfc}"
SHELL_ID="${SHELL_ID:-6}"
FRAMES="${FRAMES:-900}"
fail=0

[ -f "$ROM" ] || { echo "no such ROM: $ROM"; exit 1; }

run() {
  local tag="$1" poke="${2:-}"
  rm -f "traces/saturn/wram_$tag".{bin,idx,watch}
  if [ -n "$poke" ]; then
    TAG="$tag" SATURN=0 SHELL_ID="$SHELL_ID" FRAMES="$FRAMES" ROM="$ROM" POKE_WRAM="$poke" \
      tools/run.sh tools/saturn/trace_wram.lua 900 >/dev/null 2>&1
  else
    TAG="$tag" SATURN=0 SHELL_ID="$SHELL_ID" FRAMES="$FRAMES" ROM="$ROM" \
      tools/run.sh tools/saturn/trace_wram.lua 900 >/dev/null 2>&1
  fi
  if [ ! -s "traces/saturn/wram_$tag.idx" ] || [ ! -s "traces/saturn/wram_$tag.bin" ]; then
    echo "CAPTURE FAILED: traces/saturn/wram_$tag.{idx,bin} missing or empty"; fail=1
  fi
}

check() {
  local label="$1" want="$2"; shift 2
  local out rc
  out="$(tools/saturn/wramdiff.py "$@" 2>&1)"; rc=$?
  echo "--- $label (must $want) ---"
  echo "$out" | tail -4
  if [ "$want" = pass ] && [ "$rc" -ne 0 ]; then echo "  !! expected PASS, got exit $rc"; fail=1; fi
  if [ "$want" = fail ] && [ "$rc" -eq 0 ]; then echo "  !! expected FAIL, got exit 0"; fail=1; fi
  echo
}

echo "=== capturing (ROM=$(basename "$ROM"), shell $SHELL_ID, vanilla session) ==="
run u1 ""
run u2 ""
run upk "1F1FF:5A"
echo

if [ "$fail" != 0 ]; then
  echo "HARNESS SELF-CHECK: FAILED during capture — no diff from this run means anything"
  exit 1
fi

check "1 DETERMINISM"      pass u1 u2  --expect-empty
check "2 SENSITIVITY"      pass u1 upk --require-addr 7FF1FF
check "2b ONLY THAT BYTE"  pass u1 upk --expect-only 7FF1FF
check "3 NEGATIVE CONTROL" fail u1 upk --expect-empty

if [ "$fail" = 0 ]; then
  echo "HARNESS SELF-CHECK: ALL PASS — comparisons from it can be believed"
else
  echo "HARNESS SELF-CHECK: FAILED — do not trust any diff from this harness"
fi
exit $fail
