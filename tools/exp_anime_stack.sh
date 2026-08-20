#!/bin/bash
# exp_anime_stack.sh — the Phase 7 integration stack of the anime-fighter
# feasibility experiments (EXP TIER: no patch number, no SIG, no release).
#
#   tools/exp_anime_stack.sh [budget]     # default air-action budget 2
#   -> build/exp_anime_stack.sfc  (+ build/exp_anime_stack.bps)
#
# Chain (each step --stacked, each asserting its predecessor's bytes):
#   exp_airdash2      Uranus air back/front dash (route insertion)
#   exp_aircancel     dash->normal cancels + the on-hit gatling
#   exp_aircounter    deliberate air-action budget on struct +0x7F
#   exp_juggle        launch/air-hitstun victims stay targetable (2 bytes, GLOBAL)
#   exp_airspecial    Venus/Moon 236P + Venus 623P air-enabled (flag bit0)
# Demo: ROM=build/exp_anime_stack.sfc tools/run.sh tools/demo_airrush.lua 120
set -e
cd "$(dirname "$0")/.."
B="${1:-2}"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
python3 tools/exp_airdash2.py "$T/1.sfc"
python3 tools/exp_aircancel.py "$T/2.sfc" "$T/1.sfc" --stacked
python3 tools/exp_aircounter.py "$T/3.sfc" "$T/2.sfc" --stacked --budget "$B"
python3 tools/exp_juggle.py "$T/4.sfc" "$T/3.sfc" --stacked
python3 tools/exp_airspecial.py build/exp_anime_stack.sfc "$T/4.sfc" --stacked
CLEAN="$(python3 -c 'import sys;sys.path.insert(0,"tools");from smspaths import clean_rom;print(clean_rom())')"
./tools/Flips/flips --create --bps "$CLEAN" build/exp_anime_stack.sfc build/exp_anime_stack.bps >/dev/null
shasum build/exp_anime_stack.sfc
