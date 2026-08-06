#!/bin/bash
# Build the v0.22 ALL-PATCHES bundle (patches 1-14, 10 as 10b/labels) from the clean ROM.
# The committed, executable recipe for the shipped bundle (issue #10). The chain order
# matters for bank layout; builders re-detect the next free bank at each step.
# Usage: tools/build_v022.sh   -> build/SailorMoonS_FrenchName_v0.22_ALLPATCHES.sfc + .bps
set -euo pipefail
cd "$(dirname "$0")/.."
CLEAN="$(python3 -c 'import sys;sys.path.insert(0,"tools");from smspaths import clean_rom;print(clean_rom())')"
python3 tools/mksigs.py --check   # builder fingerprints must match the suite (#33 follow-up)
python3 tools/mkindex.py --check  # tools/ index must match the tree (#103)
# Preflight (#60): fail in a second, not after a 13-step chain. flips is gitignored
# (a local drop-in), so "missing" is the normal state of a fresh clone.
[ -x tools/Flips/flips ] || { echo "error: tools/Flips/flips missing or not executable — see HANDOFF.md §2" >&2; exit 1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
OUT="build/SailorMoonS_FrenchName_v0.22_ALLPATCHES.sfc"
python3 tools/mkpatch.py   0x04 "$T/s1.sfc"
python3 tools/mkpatch2.py  --stacked "$T/s1.sfc"  "$T/s2.sfc"
python3 tools/mkpatch3.py  --stacked "$T/s2.sfc"  "$T/s3.sfc"
# FROZEN recipe (#61). This script hardcodes v0.22 in its output names, so a
# derived subtitle would silently produce a bundle whose title and filename
# disagree the moment BUNDLE_VERSION moves. Assert instead, and pin the text.
V="$(python3 -c 'import sys;sys.path.insert(0,"tools");from smspaths import BUNDLE_VERSION;print(BUNDLE_VERSION)')"
[ "$V" = "0.22" ] || { echo "error: build_v022.sh is the frozen v0.22 recipe but BUNDLE_VERSION=$V" >&2
                       echo "       copy it to build_v0NN.sh for the new bundle" >&2; exit 1; }
python3 tools/mkpatch4.py  --stacked "$T/s3.sfc"  "$T/s4.sfc" --text "FrenchName v.0.22"
python3 tools/mkpatch5.py  --stacked "$T/s4.sfc"  "$T/s5.sfc"
python3 tools/mkpatch6.py  --stacked "$T/s5.sfc"  "$T/s6.sfc"
python3 tools/mkpatch7.py  --stacked "$T/s6.sfc"  "$T/s7.sfc"
python3 tools/mkpatch8.py  --stacked "$T/s7.sfc"  "$T/s8.sfc"
python3 tools/mkpatch9.py  --stacked "$T/s8.sfc"  "$T/s9.sfc"
python3 tools/mkpatch10.py --stacked "$T/s9.sfc"  "$T/s10.sfc" --events labels
python3 tools/mkpatch11.py --stacked "$T/s10.sfc" "$T/s11.sfc"
python3 tools/mkpatch12.py --stacked "$T/s11.sfc" "$T/s12.sfc"
python3 tools/mkpatch13.py --stacked "$T/s12.sfc" "$T/s13.sfc"
python3 tools/mkpatch14.py --stacked "$T/s13.sfc" "$OUT"
./tools/Flips/flips --create --bps "$CLEAN" "$OUT" build/sms_allpatches_v0.22.bps
shasum "$OUT"
