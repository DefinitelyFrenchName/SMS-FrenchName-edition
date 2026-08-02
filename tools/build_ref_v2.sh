#!/bin/bash
# Build the REF v.2 reference bundle: REF v.1 + patch 15 (AUTO removal).
#   = 1b(gate 0x05)+2+3+4+5+7+8+9+12+13+14+15
# Rationale: v.1 was defined before patch 15 existed, so AUTO/ACS stayed
# available on it — the maintainer confirmed this and asked for 15 to be folded
# in properly rather than shipped as a side build. v.1 is left untouched: it is
# a published artifact with a recorded hash, so v.2 is a NEW name rather than a
# redefinition of the old one.
# Patch 15 is 6 in-place bytes and appends nothing, so it stacks last safely.
# Usage: tools/build_ref_v2.sh   -> build/SailorMoonS_FrenchName_REF_v2.sfc + .bps
set -euo pipefail
cd "$(dirname "$0")/.."
CLEAN="$(python3 -c 'import sys;sys.path.insert(0,"tools");from smspaths import clean_rom;print(clean_rom())')"
python3 tools/mksigs.py --check   # builder fingerprints must match the suite
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
OUT="build/SailorMoonS_FrenchName_REF_v2.sfc"
python3 tools/mkpatch.py   0x05 "$T/r1.sfc"
python3 tools/mkpatch2.py  --stacked "$T/r1.sfc"  "$T/r2.sfc"
python3 tools/mkpatch3.py  --stacked "$T/r2.sfc"  "$T/r3.sfc"
python3 tools/mkpatch4.py  --stacked "$T/r3.sfc"  "$T/r4.sfc" --text "FrenchName REF v.2"
python3 tools/mkpatch5.py  --stacked "$T/r4.sfc"  "$T/r5.sfc"
python3 tools/mkpatch7.py  --stacked "$T/r5.sfc"  "$T/r7.sfc"
python3 tools/mkpatch8.py  --stacked "$T/r7.sfc"  "$T/r8.sfc"
python3 tools/mkpatch9.py  --stacked "$T/r8.sfc"  "$T/r9.sfc"
python3 tools/mkpatch12.py --stacked "$T/r9.sfc"  "$T/r12.sfc"
python3 tools/mkpatch13.py --stacked "$T/r12.sfc" "$T/r13.sfc"
python3 tools/mkpatch14.py --stacked "$T/r13.sfc" "$T/r14.sfc"
python3 tools/mkpatch15.py --stacked "$T/r14.sfc" "$OUT"
./tools/Flips/flips --create --bps "$CLEAN" "$OUT" build/sms_reference_v2.bps
shasum "$OUT"
