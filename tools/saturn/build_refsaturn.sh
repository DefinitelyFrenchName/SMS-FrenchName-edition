#!/bin/bash
# Build the COMBINED "SMS + REF v.1 + Saturn" ROM — the project-goal artifact
# (docs/saturn/PROJECT.md). Chains the committed REF v.1 recipe, then stacks
# the Saturn build on top (bank-agnostic since v0.11.5: Saturn occupies the
# first 9 free banks — $F0-$F8 on this base — and chains patch 5's char-select
# confirm hook). Pass SATURN_HIDDEN=1 for the hidden-character variant.
# Usage: tools/saturn/build_refsaturn.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
[ -f build/SailorMoonS_FrenchName_REF_v1.sfc ] || tools/build_ref_v1.sh
SATURN_BASE=build/SailorMoonS_FrenchName_REF_v1.sfc python3 tools/saturn/mksaturn_smoke.py
