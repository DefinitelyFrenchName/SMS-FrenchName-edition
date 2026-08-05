#!/bin/bash
# Build the REF v.1 reference bundle: 1b(gate 0x05)+2+3+4+5+7+8+9+12+13+14 — the
# maintainer-requested combination (true-combo gate; no p6/p10/p11). Committed,
# executable recipe (issue #10). Patch 12 is required: without it p13's Guts grant is
# unreachable in normal play and p14 is inert.
# Usage: tools/build_ref_v1.sh   -> build/SailorMoonS_FrenchName_REF_v1.sfc + .bps
set -euo pipefail
cd "$(dirname "$0")/.."
CLEAN="$(python3 -c 'import sys;sys.path.insert(0,"tools");from smspaths import clean_rom;print(clean_rom())')"
python3 tools/mksigs.py --check   # builder fingerprints must match the suite (#33 follow-up)
# Preflight (#60): fail in a second, not after a 13-step chain. flips is gitignored
# (a local drop-in), so "missing" is the normal state of a fresh clone.
[ -x tools/Flips/flips ] || { echo "error: tools/Flips/flips missing or not executable — see HANDOFF.md §2" >&2; exit 1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
OUT="build/SailorMoonS_FrenchName_REF_v1.sfc"
python3 tools/mkpatch.py   0x05 "$T/r1.sfc"
python3 tools/mkpatch2.py  --stacked "$T/r1.sfc"  "$T/r2.sfc"
python3 tools/mkpatch3.py  --stacked "$T/r2.sfc"  "$T/r3.sfc"
python3 tools/mkpatch4.py  --stacked "$T/r3.sfc"  "$T/r4.sfc" --text "FrenchName REF v.1"
python3 tools/mkpatch5.py  --stacked "$T/r4.sfc"  "$T/r5.sfc"
python3 tools/mkpatch7.py  --stacked "$T/r5.sfc"  "$T/r7.sfc"
python3 tools/mkpatch8.py  --stacked "$T/r7.sfc"  "$T/r8.sfc"
python3 tools/mkpatch9.py  --stacked "$T/r8.sfc"  "$T/r9.sfc"
python3 tools/mkpatch12.py --stacked "$T/r9.sfc"  "$T/r12.sfc"
python3 tools/mkpatch13.py --stacked "$T/r12.sfc" "$T/r13.sfc"
python3 tools/mkpatch14.py --stacked "$T/r13.sfc" "$OUT"
./tools/Flips/flips --create --bps "$CLEAN" "$OUT" build/sms_reference_v1.bps
shasum "$OUT"
