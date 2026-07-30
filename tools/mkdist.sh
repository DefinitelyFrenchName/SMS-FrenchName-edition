#!/bin/bash
# mkdist.sh — generate the training-mode distribution zip FROM THE LIVE TREE.
# Replaces the tracked build/sms_training_mode.zip, which was a stale binary fork
# (issue #6: it shipped pre-fix framedata, the removed MEATY label, and the old
# hardcoded-path scheme). Attach the output to a GitHub release; don't track it.
# Usage: tools/mkdist.sh [out.zip]   (default: build/sms_training_mode.zip, untracked)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-build/sms_training_mode.zip}"
rm -f "$OUT"
FILES=(
  tools/training.lua tools/training_cfg.lua tools/training_test.lua
  tools/training_test_cfg.lua tools/run.sh tools/sms_env.lua
  tools/training/
  traces/venus_vs_jupiter_clean.mss traces/jupiter_vs_venus_clean.mss
  traces/uranus_vs_jupiter_v07.mss traces/uranus_vs_jupiter_tm.mss
  docs/training_install.md docs/training_usage.md
  HANDOFF.md
)
# HANDOFF.md is sms_env.lua's root marker — required for path discovery in an extract.
zip -r "$OUT" "${FILES[@]}" >/dev/null
echo "wrote $OUT:"
unzip -l "$OUT" | tail -1
echo "verify: per-member diff vs tree should be empty:"
echo "  unzip -d /tmp/distchk '$OUT' && diff -r /tmp/distchk/tools/training tools/training"
