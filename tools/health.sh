#!/bin/bash
# health.sh — the single command that answers "is this tree consistent?" (#24)
#
# WHAT IT IS NOT: the gate. The real verification of this project needs three
# things that are deliberately not in the repo — the clean ROM, the Super S donor
# and Mesen — so anything claiming to verify a build without them is lying. Those
# checks live in `tools/run.sh tools/test_regression.lua` and
# `tools/saturn/verify_saturn.sh`, and this script SKIPS them loudly rather than
# pretending. What is left is still worth having: everything that can be checked
# from the source tree alone, in one command, with an exit code.
#
# Three verdict classes, and the distinction matters:
#   FAIL  something is definitely wrong -> exit 1
#   SKIP  needs a ROM / emulator / donor that is not here -> not a failure
#   NOTE  a convention count, reported and never fatal. These exist because five
#         issues (#73 #78 #81 #102 #105) are accreting FASTER than they are
#         fixed, and the reason is that nothing reports them. A number that moves
#         in the wrong direction is the signal; failing the build on 79 working
#         asserts would just get the check deleted.
#
#   tools/health.sh          # checks + notes
#   tools/health.sh --quiet  # only FAIL/SKIP lines
set -uo pipefail
cd "$(dirname "$0")/.."
QUIET=0; [ "${1:-}" = "--quiet" ] && QUIET=1

fails=0
ok()   { [ "$QUIET" = 1 ] || printf '  \033[32mOK\033[0m    %s\n' "$1"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fails=$((fails+1)); }
skip() { printf '  \033[33mSKIP\033[0m  %s\n' "$1"; }
note() { [ "$QUIET" = 1 ] || printf '  note  %s\n' "$1"; }

echo "== generated artifacts are in sync with their sources =="
if out="$(python3 tools/mksigs.py --check 2>&1)"; then ok "$out"; else bad "mksigs: $out"; fi
if out="$(python3 tools/mkrelease.py --check 2>&1)"; then ok "$out"; else bad "mkrelease: $out"; fi
if out="$(python3 tools/mkindex.py --check 2>&1)"; then ok "$out"; else bad "mkindex: $out"; fi
# The knobs table is read from the builders' source, so this one needs no ROM
# and runs everywhere, CI included (trap 18: a documented knob either works or
# does not exist).
if out="$(python3 tools/checkknobs.py 2>&1)"; then ok "knobs table vs builders: $(printf '%s' "$out" | grep -aoE '\([0-9]+ documented knobs.*\)' | tr -d '()')"
else printf '%s\n' "$out" | sed 's/^/    /'; bad "checkknobs: the knobs table disagrees with the builders"; fi
# Same class, same reason (trap 18): the training docs describe a UI whose
# hotkeys, menu rows and labels are all literals in tools/training/.
if out="$(python3 tools/checktrainingdocs.py 2>&1)"; then ok "training docs vs the Lua: $(printf '%s' "$out" | grep -aoE '\([0-9]+ checks[^)]*\)' | tr -d '()')"
else printf '%s\n' "$out" | sed 's/^/    /'; bad "checktrainingdocs: the training docs disagree with tools/training/"; fi
# mkcharmap reads the ROM, so it can only be checked where the ROM exists; a
# hosted runner has none and must SKIP rather than silently pass (#24).
# Guard on the ROM FILE EXISTING, not on clean_rom() merely returning: it hands
# back a path whether or not anything is there, so the old guard passed on a
# hosted runner and both tools then died on the open(). Same class of mistake
# this file exists to prevent — a check that cannot run must SKIP, never fail.
if python3 -c 'import os,sys;sys.path.insert(0,"tools");from smspaths import clean_rom;sys.exit(0 if os.path.exists(clean_rom()) else 1)' >/dev/null 2>&1; then
  if out="$(python3 tools/mkcharmap.py --check 2>&1)"; then ok "$out"; else bad "mkcharmap: $out"; fi
  # the engine page draws instructions by address; --check re-reads every one of
  # them, so a stage that moves cannot stay on the diagram.
  if out="$(python3 tools/mkenginepage.py --check 2>&1)"; then ok "$out"; else bad "mkenginepage: $out"; fi
  # match on the count, not on "ALL PASS": the tool colourises, so an ANSI escape
  # sits between the words and the parenthesis and a naive pattern never matches.
  if cd_out="$(python3 tools/checkdocs.py 2>&1)"; then
    ok "doc claims vs cartridge: $(printf '%s' "$cd_out" | grep -aoE '[0-9]+ checks across [0-9]+ documents') verified"
    # The coverage number is a NOTE for the same reason the convention counts
    # are: it is the honest weakness (claims nobody wrote a check for), and a
    # number that is never printed never moves. Never fatal — failing a build
    # because a document mentions an address is how a census gets deleted.
    note "address coverage: $(printf '%s' "$cd_out" | grep -aoE '[0-9]+ distinct ROM addresses in hand-written pages, [0-9]+ re-derived from the cartridge') (tools/checkdocs.py --uncovered)"
  else
    bad "checkdocs: doc claims disagree with the ROM — run python3 tools/checkdocs.py"
  fi
  # The decode table two tools now share, checked against a DIFFERENT author's
  # disassembler. A table validated only by its own invariants is validated by
  # itself; DisPel is vendored, so the independent comparison is free. It skips
  # itself when the binary is not built.
  if out="$(python3 tools/dis65816_oracle.py 2>&1)"; then
    if printf '%s' "$out" | grep -q SKIP; then
      skip "65816 tables vs DisPel (tools/Dispel/dispel not built)"
    else
      ok "65816 tables vs DisPel: $(printf '%s' "$out" | grep -aoE 'on [0-9]+ consecutive instructions across [0-9]+ ranges')"
    fi
  else
    printf '%s\n' "$out" | sed 's/^/    /'; bad "dis65816: our decode disagrees with DisPel"
  fi
else
  skip "character maps + doc claims (need the clean ROM)"
fi
# Saturn's ported proc block must not move when the shared tables do — the
# builders that consume it have recorded hashes (trap 16: byte-identity is the
# refactor gate). Needs the donor as well as the clean ROM.
if python3 -c 'import os,sys;sys.path.insert(0,"tools");from smspaths import clean_rom,supers_rom;sys.exit(0 if os.path.exists(clean_rom()) and os.path.exists(supers_rom()) else 1)' >/dev/null 2>&1; then
  if out="$(python3 tools/saturn/port_saturn_proc.py --check 2>&1)"; then ok "Saturn proc block: $(printf '%s' "$out" | grep -aoE '[0-9]+ instructions reached.*')"
  else printf '%s\n' "$out" | sed 's/^/    /'; bad "port_saturn_proc: the ported block changed"; fi
else
  skip "Saturn ported block (needs the clean ROM and the Super S donor)"
fi

echo "== every Python tool parses, and imports cleanly enough to be introspected =="
syn=0
for f in $(git ls-files 'tools/**/*.py' 'tools/*.py'); do
  python3 -m py_compile "$f" 2>/dev/null || { bad "syntax: $f"; syn=$((syn+1)); }
done
[ "$syn" = 0 ] && ok "$(git ls-files 'tools/**/*.py' 'tools/*.py' | wc -l | tr -d ' ') Python files compile"

echo "== shell recipes parse =="
shn=0
for f in $(git ls-files 'tools/*.sh' 'tools/**/*.sh'); do
  bash -n "$f" 2>/dev/null || { bad "syntax: $f"; shn=$((shn+1)); }
done
[ "$shn" = 0 ] && ok "$(git ls-files 'tools/*.sh' 'tools/**/*.sh' | wc -l | tr -d ' ') shell scripts parse"

echo "== the release folder is complete and self-consistent =="
REV_S="${SMS_REV_S:-$(python3 -c 'import sys;sys.path.insert(0,"tools");import smspaths;print(smspaths.REV_S)' 2>/dev/null)}"
REV_SS="${SMS_REV_SS:-$(python3 -c 'import sys;sys.path.insert(0,"tools");import smspaths;print(smspaths.REV_SS)' 2>/dev/null)}"
for f in "release/Rev.S-$REV_S.bps" "release/Rev.SS-$REV_SS.bps" release/RELEASE_NOTES.md; do
  [ -f "$f" ] && ok "$f present" || bad "$f missing (tools/build_rev.sh both)"
done
# every build/ or release/ path the NOTES name must exist: those are instructions
# a player follows. Docs elsewhere deliberately keep historical paths (prune
# banner, strikethroughs), so this check is scoped to the generated notes only.
if [ -f release/RELEASE_NOTES.md ]; then
  miss=0
  for p in $(grep -oE '(build|release)/[A-Za-z0-9_.-]+\.bps' release/RELEASE_NOTES.md | sort -u); do
    [ -f "$p" ] || { bad "RELEASE_NOTES names a missing file: $p"; miss=$((miss+1)); }
  done
  [ "$miss" = 0 ] && ok "every .bps named in the release notes exists"
fi

echo "== inputs that are deliberately not in the repo =="
CLEAN="$(python3 -c 'import sys;sys.path.insert(0,"tools");from smspaths import clean_rom;print(clean_rom())' 2>/dev/null)"
[ -f "$CLEAN" ] && ok "clean ROM found" || skip "clean ROM absent — no build or round-trip check (set \$SMS_ROM_DIR)"
SUP="$(python3 -c 'import sys;sys.path.insert(0,"tools");from smspaths import supers_rom;print(supers_rom())' 2>/dev/null)"
[ -f "$SUP" ] && ok "Super S donor found" || skip "Super S donor absent — no Saturn build check"
[ -x tools/Flips/flips ] && ok "flips present" || skip "tools/Flips/flips absent — cannot create or apply patches"
[ -x tools/Mesen.app/Contents/MacOS/Mesen ] && ok "Mesen present" \
  || skip "Mesen absent — the regression suite and the Saturn gate cannot run"

echo "== round-trip: each release patch reproduces its recorded ROM =="
if [ -f "$CLEAN" ] && [ -x tools/Flips/flips ]; then
  for r in "S" "SS"; do
    rev="$REV_S"; [ "$r" = "SS" ] && rev="$REV_SS"
    bps="release/Rev.$r-$rev.bps"; rom="build/SailorMoonS_Rev_$r-$rev.sfc"
    if [ -f "$bps" ] && [ -f "$rom" ]; then
      tmp="$(mktemp)"; ./tools/Flips/flips --apply "$bps" "$CLEAN" "$tmp" >/dev/null 2>&1
      a="$(shasum "$tmp" | cut -d' ' -f1)"; b="$(shasum "$rom" | cut -d' ' -f1)"; rm -f "$tmp"
      [ "$a" = "$b" ] && ok "Rev. $r-$rev round-trips to ${b:0:8}…" \
        || bad "Rev. $r-$rev: patch yields ${a:0:8}… but the ROM is ${b:0:8}…"
    else
      skip "Rev. $r-$rev: no local ROM to compare (tools/build_rev.sh)"
    fi
  done
else
  skip "round-trip needs the clean ROM and flips"
fi

echo "== the Saturn corpus still describes both cartridges =="
if [ -f "$CLEAN" ] && [ -f "$SUP" ]; then
  if out="$(python3 tools/saturn/checksaturndocs.py 2>&1)"; then
    ok "$(printf '%s' "$out" | grep -aoE '\([0-9]+ checks against both cartridges[^)]*\)' | tr -d '()')"
  else
    printf '%s\n' "$out" | sed 's/^/    /'
    bad "checksaturndocs: docs/project/saturn disagrees with the cartridges"
  fi
else
  skip "Saturn corpus (needs the clean ROM and the Super S donor)"
fi

echo "== the patch documents still describe the patches =="
if [ -f "$CLEAN" ] && [ -x tools/Flips/flips ]; then
  if out="$(python3 tools/checkpatchmap.py 2>&1)"; then
    ok "$(printf '%s' "$out" | grep -aoE '\([0-9]+ standalone patches, [0-9]+ changed bytes accounted for\)' | tr -d '()')"
    ok "in-place edits pairwise disjoint; every appended bank at 0x280000 (why BPS must not be chained)"
    ok "$(printf '%s' "$out" | grep -aoE '[0-9]+ "this .bps gives this ROM" claims in the registry documents re-derived')"
  else
    printf '%s\n' "$out" | sed 's/^/    /'
    bad "checkpatchmap: docs/project/patch_notes.md disagrees with build/*.bps"
  fi
else
  skip "edit-region map (needs the clean ROM and flips)"
fi

echo "== conventions (reported, never fatal) =="
note "$(grep -rlE '^\s*assert\b' tools/saturn/*.py 2>/dev/null | wc -l | tr -d ' ') Saturn tools still use bare asserts for guards (#102)"
note "$(grep -rc 'io.open' tools/*.lua tools/saturn/*.lua tools/training/*.lua 2>/dev/null | awk -F: '{s+=$2} END {print s+0}') io.open sites; $(grep -rc 'assert(io.open' tools/*.lua tools/saturn/*.lua tools/training/*.lua 2>/dev/null | awk -F: '{s+=$2} END {print s+0}') wrapped in assert (#105)"
note "$(grep -rl 'CLEAN_SHA1' tools/*.py tools/saturn/*.py 2>/dev/null | wc -l | tr -d ' ') files define CLEAN_SHA1; only smspaths and the builders that READ it need it (#73)"
note "$(grep -rlE 'io\.open\(.*"a"\)' tools/test_*.lua 2>/dev/null | wc -l | tr -d ' ') test suites still append to their log — a verdict read with tail -1 must be this run's (#81)"

echo
if [ "$fails" = 0 ]; then
  printf '\033[32mHEALTHY\033[0m — everything checkable from the source tree agrees.\n'
  printf 'This is NOT the gate: run tools/run.sh tools/test_regression.lua and\n'
  printf 'tools/saturn/verify_saturn.sh for the checks that need a ROM and an emulator.\n'
  exit 0
fi
printf '\033[31m%d FAILURE(S)\033[0m\n' "$fails"
exit 1
