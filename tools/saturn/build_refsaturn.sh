#!/bin/bash
# Build the COMBINED "SMS + REF v.1 + Saturn" ROM — the project-goal artifact
# (docs/project/saturn/PROJECT.md). Chains the committed REF v.1 recipe, then stacks
# the Saturn build on top (bank-agnostic since v0.11.5: Saturn occupies the
# first 9 free banks — $F0-$F8 on this base — and chains patch 5's char-select
# confirm hook). Pass SATURN_HIDDEN=1 for the hidden-character variant.
# Usage: tools/saturn/build_refsaturn.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# REF_VERSION=1 selects the original bundle; default is v.2 (adds patch 15,
# AUTO removal). v.1 stays buildable because it is a published artifact.
REF="${REF_VERSION:-2}"
# Freshness gate (#59). "The file exists" is not "the file is the REF bundle": a
# truncated, half-written or hand-edited .sfc was accepted silently and Saturn was
# then grafted onto it. Both REF bundles are FROZEN published artifacts, so their
# hashes are the right thing to assert — a mismatch means either the file is
# damaged or the recipe moved, and both are things to hear about loudly.
REF_SHA1_1=2873f21478192bda22b6413233eaff40818307ba
REF_SHA1_2=6d79fb5f3ac167dd2c24eee161ce4054a3bab8a2
REFROM="build/SailorMoonS_FrenchName_REF_v${REF}.sfc"
eval "want=\$REF_SHA1_$REF"
if [ -f "$REFROM" ]; then
  got="$(shasum "$REFROM" | cut -d' ' -f1)"
  if [ "$got" != "$want" ]; then
    echo "build_refsaturn: $REFROM is not REF v.$REF — rebuilding" >&2
    echo "  expected $want" >&2
    echo "  got      $got" >&2
    rm -f "$REFROM"
  fi
fi
[ -f "$REFROM" ] || "tools/build_ref_v${REF}.sh"
got="$(shasum "$REFROM" | cut -d' ' -f1)"
[ "$got" = "$want" ] || { echo "build_refsaturn: REF v.$REF rebuild produced $got, expected $want" >&2; exit 1; }
SATURN_BASE="build/SailorMoonS_FrenchName_REF_v${REF}.sfc" python3 tools/saturn/mksaturn_smoke.py
