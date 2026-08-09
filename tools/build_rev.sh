#!/bin/bash
# build_rev.sh — the two REFERENCE builds, the things a player is meant to apply.
#
#   tools/build_rev.sh s     -> Rev. S-XX   (no Super S content)
#   tools/build_rev.sh ss    -> Rev. SS-XX  (the same, plus Saturn)
#   tools/build_rev.sh both  -> both
#
# Each side's revision comes from smspaths.REV_S / REV_SS (override with
# SMS_REV_S / SMS_REV_SS) and names that side's ROM, its .bps in release/, and its
# subtitle on the title screen — the naked-eye tell a pad tester quotes back, so
# it must never be stale.
#
# ⚠ The two revisions are INDEPENDENT (2026-08-09): S is 02, SS is 03, because the
# round-won badge changed the Saturn side only. That is the versioning rule, not
# drift — see smspaths.py. Keeping the shared patch chain in ONE script is still
# what guarantees the two references can't silently diverge in their common
# bytes; only the numbers differ, because SS carries content S does not.
#
# Rev. S-XX carries REF v.2's patch set plus 18 (no ACS in 2P VS, the companion
# to 15): 1b+2+3+4+5+7+8+9+12+13+14+15+18.
# REF v.1 and v.2 keep their own recipes and hashes: they are published
# artifacts, so this is a NEW name, not a redefinition.
#
# Rev. SS-XX = that same chain, retitled, plus the Saturn build and its ported
# stage. **Patch 17 (all stages selectable) is in NEITHER reference** — it stays
# an optional standalone in build/ (maintainer, 2026-08-05). If it is ever
# wanted here, SATURN_ALLSTAGES=1 on the Saturn step is the whole change.
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-both}"
REV_S="${SMS_REV_S:-$(python3 -c 'import sys;sys.path.insert(0,"tools");import smspaths;print(smspaths.REV_S)')}"
REV_SS="${SMS_REV_SS:-$(python3 -c 'import sys;sys.path.insert(0,"tools");import smspaths;print(smspaths.REV_SS)')}"
CLEAN="$(python3 -c 'import sys;sys.path.insert(0,"tools");from smspaths import clean_rom;print(clean_rom())')"
mkdir -p release

build_chain() {   # build_chain <subtitle> <out.sfc>
  local title="$1" out="$2"
  local T; T="$(mktemp -d)"; trap 'rm -rf "$T"' RETURN
  python3 tools/mkpatch.py   0x05 "$T/r1.sfc"                       # 1b true-combo gate
  python3 tools/mkpatch2.py  --stacked "$T/r1.sfc"  "$T/r2.sfc"
  python3 tools/mkpatch3.py  --stacked "$T/r2.sfc"  "$T/r3.sfc"
  python3 tools/mkpatch4.py  --stacked "$T/r3.sfc"  "$T/r4.sfc" --text "$title"
  python3 tools/mkpatch5.py  --stacked "$T/r4.sfc"  "$T/r5.sfc"
  python3 tools/mkpatch7.py  --stacked "$T/r5.sfc"  "$T/r7.sfc"
  python3 tools/mkpatch8.py  --stacked "$T/r7.sfc"  "$T/r8.sfc"
  python3 tools/mkpatch9.py  --stacked "$T/r8.sfc"  "$T/r9.sfc"
  python3 tools/mkpatch12.py --stacked "$T/r9.sfc"  "$T/r12.sfc"
  python3 tools/mkpatch13.py --stacked "$T/r12.sfc" "$T/r13.sfc"
  python3 tools/mkpatch14.py --stacked "$T/r13.sfc" "$T/r14.sfc"
  python3 tools/mkpatch15.py --stacked "$T/r14.sfc" "$T/r15.sfc"
  python3 tools/mkpatch18.py --stacked "$T/r15.sfc" "$out"   # companion to 15
}

python3 tools/mksigs.py --check      # builder fingerprints must match the suite
python3 tools/mkindex.py --check     # tools/ index must match the tree (#103)
# Preflight (#60): fail in a second, not after a 13-step chain. flips is gitignored
# (a local drop-in), so "missing" is the normal state of a fresh clone.
[ -x tools/Flips/flips ] || { echo "error: tools/Flips/flips missing or not executable — see HANDOFF.md §2" >&2; exit 1; }

if [ "$MODE" = s ] || [ "$MODE" = both ]; then
  OUT="build/SailorMoonS_Rev_S-$REV_S.sfc"
  build_chain "FrenchName Rev. S-$REV_S" "$OUT"
  ./tools/Flips/flips --create --bps "$CLEAN" "$OUT" "release/Rev.S-$REV_S.bps" >/dev/null
  echo "Rev. S-$REV_S   $(shasum "$OUT" | cut -d' ' -f1)  -> release/Rev.S-$REV_S.bps"
fi

if [ "$MODE" = ss ] || [ "$MODE" = both ]; then
  # intermediates stay in a temp dir: build/ should hold the two finished ROMs,
  # not the two half-built ones they are easy to confuse with
  S="$(mktemp -d)"; trap 'rm -rf "$S"' EXIT
  build_chain "FrenchName Rev. SS-$REV_SS" "$S/base.sfc"
  # Saturn stacks on that base: patch 100 + 101 + nameplate + her throw fix +
  # her round-won badge (v0.17.0), then her ported stage on slot 2.
  SATURN_HIDDEN=1 SATURN_BASE="$S/base.sfc" \
    python3 tools/saturn/mksaturn_smoke.py "$S/saturn.sfc" >/dev/null
  OUT="build/SailorMoonS_Rev_SS-$REV_SS.sfc"
  python3 tools/saturn/mkstage_port.py "$S/saturn.sfc" "$OUT" --stacked >/dev/null
  ./tools/Flips/flips --create --bps "$CLEAN" "$OUT" "release/Rev.SS-$REV_SS.bps" >/dev/null
  echo "Rev. SS-$REV_SS  $(shasum "$OUT" | cut -d' ' -f1)  -> release/Rev.SS-$REV_SS.bps"
fi
