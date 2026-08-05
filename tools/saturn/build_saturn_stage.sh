#!/bin/bash
# Saturn + stage PoC in one ROM (committed recipe).
#   tools/saturn/build_saturn_stage.sh [--visible] [--ref]
# Stacks the Super S stage over SMS stage 2 (Pluto's space-time door) on top of
# a Saturn build. The stage patch appends its own bank after Saturn's, so the
# order matters: Saturn first, stage second.
set -e
cd "$(dirname "$0")/../.."
VARIANT=hidden; STEM=SailorMoonS_saturn
for a in "$@"; do
  case "$a" in
    --visible) VARIANT=visible ;;
    --ref) STEM=SailorMoonS_REFsaturn ;;
    # #62: an unrecognised flag used to be ignored, so a typo built the DEFAULT
    # variant and reported success — the one outcome you did not ask for.
    *) echo "error: unknown option '$a' (accepts --visible, --ref)" >&2; exit 1 ;;
  esac
done
if [ "$STEM" = "SailorMoonS_REFsaturn" ]; then
  SATURN_HIDDEN=1 bash tools/saturn/build_refsaturn.sh
elif [ "$VARIANT" = visible ]; then
  SATURN_VISIBLE=1 python3 tools/saturn/mksaturn_smoke.py
else
  SATURN_HIDDEN=1 python3 tools/saturn/mksaturn_smoke.py
fi
VER=$(python3 -c "import re;print(re.search(r'SATURN_VERSION = \"([^\"]+)\"',open('tools/saturn/mksaturn_smoke.py').read()).group(1))")
SUF=""; [ "$VARIANT" = hidden ] && SUF="-hidden"
IN="build/saturn/${STEM}_v${VER}${SUF}.sfc"
OUT="build/saturn/${STEM}_v${VER}${SUF}-stage.sfc"
python3 tools/saturn/mkstage_port.py "$IN" "$OUT" --stacked
echo "stage build: $OUT"
