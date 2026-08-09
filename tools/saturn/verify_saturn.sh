#!/bin/bash
# verify_saturn.sh — the full headless regression path for the Saturn port.
#
# v0.14.5 -> v0.14.9 touched five separate subsystems (the shell/story guard, the
# game-mode gate, the thrown-pose table, the flag-arming path and the projectile
# palette), and the checks for each were ad-hoc shell one-liners. This is them,
# made repeatable and turned into a gate: it exits 1 if anything fails.
#
#   tools/saturn/verify_saturn.sh                  # current build, full matrix
#   ROM=<rom> tools/saturn/verify_saturn.sh        # a specific ROM
#   QUICK=1 tools/saturn/verify_saturn.sh          # smaller matrix, ~4 min
#
# Every check asserts a MEASURED string, never just "the probe exited 0" — a probe
# that reports nothing is usually broken, not evidence of nothing (HANDOFF §5).
set -uo pipefail
cd "$(dirname "$0")/../.."

# Default ROM: the SHIPPED artifact for the current release revision (#79). It used
# to be a hardcoded intermediate that had to be hand-edited at every version bump —
# and was, three times in one day — so a stale default silently verified an obsolete
# build. smspaths.REV is the single source the release recipe uses.
REV="${SMS_REV:-$(python3 -c 'import sys;sys.path.insert(0,"tools");import smspaths;print(smspaths.REV)')}"
ROM="${ROM:-build/SailorMoonS_Rev_SS-$REV.sfc}"
[ -f "$ROM" ] || { echo "verify_saturn: ROM not found: $ROM" >&2
                   echo "  (default is the Rev. SS-$REV release build; pass ROM=<file> for another)" >&2
                   exit 1; }
QUICK="${QUICK:-0}"
T=traces/saturn
pass=0; fail=0; failed=()
rc=0

ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n     expected: %s\n     got:      %s\n' "$1" "$2" "${3:-<nothing>}"; fail=$((fail+1)); failed+=("$1"); }

# run <trace-file> <command...> — the ONLY way this script starts an emulator (#79).
# It deletes the trace the following check will read, runs the command, and records
# the exit status in $rc. Both halves matter: without the delete, a run that never
# starts (missing binary, bad ROM path) leaves the PREVIOUS run's trace in place and
# `tail -1` reports its verdict; without $rc, a crash mid-run is indistinguishable
# from a pass. Env assignments go through `env` so they are arguments, not a prefix.
run() {
  local trace="$1"; shift
  rm -f "$trace"
  "$@" >/dev/null 2>&1
  rc=$?
}

# check <name> <expected-substring> <file> [grep-filter]
# Three distinct failure modes, reported distinctly: the run died, the run produced
# no trace, or the trace holds the wrong verdict. They used to collapse into one
# empty "got: <nothing>".
check() {
  local name="$1" want="$2" file="$3" filt="${4:-.}"
  if [ "$rc" -ne 0 ]; then bad "$name" "$want" "the emulator exited $rc — no verdict produced"; return; fi
  if [ ! -f "$file" ]; then bad "$name" "$want" "no trace written at $file"; return; fi
  local got; got="$(grep -E "$filt" "$file" | tail -1)"
  case "$got" in
    *"$want"*) ok "$name";;
    *) bad "$name" "$want" "${got:-<no line matched /$filt/ in $file>}";;
  esac
}

echo "verify_saturn: $ROM"
echo "== base engine + patch regression =="
run traces/regression.txt env ROM="$ROM" tools/run.sh tools/test_regression.lua 900
check "regression suite" "ALL PASS" traces/regression.txt "ALL PASS|FAIL"

echo "== L+R arming: shell guard, story lock, per-mode =="
# flag/latch matter as much as the transform: the select voice, the sound remap
# and the effect-tile/palette override all key off the FLAG (v0.14.8 field bug)
modes="vs vscom practice story"; shells="6 7 8 1 4 9"
[ "$QUICK" = 1 ] && { modes="vs story"; shells="6 1"; }
for m in $modes; do for sh in $shells; do
  run "$T/shellguard_v_${m}_$sh.txt" env MODE=$m SHELL_ID=$sh XFORM_OFF=0x4A \
    TAG=v_${m}_$sh ROM="$ROM" tools/run.sh tools/saturn/probe_sms_shellguard.lua 600
  case "$m:$sh" in
    story:*)            want="SATURN=none  flag=00" ;;   # story never arms
    *:6|*:7|*:8)        want="SATURN=P1  flag=A5" ;;     # allowed shells arm
    *)                  want="SATURN=none  flag=00" ;;   # and nothing else does
  esac
  check "$m shell $sh" "$want" "$T/shellguard_v_${m}_$sh.txt" "FINAL"
done; done
run "$T/shellguard_v_advstory.txt" env MODE=story SHELL_ID=6 STORY_SHELL=1 \
  XFORM_OFF=0x4A TAG=v_advstory ROM="$ROM" tools/run.sh tools/saturn/probe_sms_shellguard.lua 600
check "story with charID 6 FORCED (mode guard)" "SATURN=none" "$T/shellguard_v_advstory.txt" "FINAL"

if [ "$QUICK" != 1 ]; then
  echo "== 2P VS, both pads =="
  for h in p1 p2 both; do
    case $h in p1) want="SATURN=P1 ";; p2) want="SATURN=P2 ";; both) want="SATURN=P1+P2";; esac
    run "$T/shellguard_v_hold_$h.txt" env MODE=vs SHELL_ID=6 P2SHELL=7 HOLD=$h \
      XFORM_OFF=0x4A TAG=v_hold_$h ROM="$ROM" tools/run.sh tools/saturn/probe_sms_shellguard.lua 600
    check "2P VS L+R on $h" "$want" "$T/shellguard_v_hold_$h.txt" "FINAL"
  done
fi

echo "== throws: Saturn as the victim (OAM flood + stage-tile VRAM) =="
for cmd in 0 1; do for sat in 1 0; do
  n=$([ "$sat" = 1 ] && echo saturn || echo vanilla)
  k=$([ "$cmd" = 1 ] && echo command || echo normal)
  run "$T/v_throw_${k}_$n.txt" env CMD=$cmd SATURN=$sat TAG=v_throw_${k}_$n \
    ROM="$ROM" tools/run.sh tools/saturn/probe_sms_throwoam.lua 700
  check "$k throw, $n victim" "(healthy)" "$T/v_throw_${k}_$n.txt" "FINAL|NEVER"
  check "$k throw, $n victim: stage tiles" "stage-tile VRAM changed 0%" \
    "$T/v_throw_${k}_$n.txt" "FINAL"
done; done

echo "== projectile palettes: hers on her own row, the opponent's untouched =="
run "$T/v_pal_hers.txt" env SATP1=1 SATURN=1 DUMMY=4 TAG=v_pal_hers ROM="$ROM" \
  tools/run.sh tools/saturn/probe_sms_objpal.lua 700
check "her projectile uses OBJ pal 7" "+08=1F" "$T/v_pal_hers.txt" "proj slot"
run "$T/v_pal_vs.txt" env SATURN=1 TAG=v_pal_vs ROM="$ROM" \
  tools/run.sh tools/saturn/probe_sms_objpal.lua 700
check "opponent's projectile still on OBJ pal 2" "+08=1A" "$T/v_pal_vs.txt" "proj slot"

echo "== effect sheet reaches VRAM in full, on every shell =="
# v0.14.11. Her sheet is staged over the shell's, but the DMA that follows was
# sized from the SHELL's own sheet: Uranus $11C0 / Pluto $10C0 are big enough,
# NEPTUNE is $0E60, so 15 tiles ($113-$121) never arrived and her 214P
# projectile lost 7 of its 12 sprites ("two disconnected blue pieces").
# Asserting CROSS-SHELL INVARIANCE rather than a fixed checksum: the sheet is
# the same data on every shell, so the sums must agree. Sanity-checked against
# the known-bad v0.14.8, where shells 6 and 7 disagree — a check that cannot
# fail is not a check.
fxshells="6 7 8"; [ "$QUICK" = 1 ] && fxshells="6 7"
fxsums=""
for sh in $fxshells; do
  run "$T/fxsheet_$sh.txt" env SHELL_ID=$sh ROM="$ROM" \
    tools/run.sh tools/saturn/probe_saturn_fxsheet.lua 500
  s=""; [ "$rc" -eq 0 ] && s="$(grep -E '^FXSHEET' "$T/fxsheet_$sh.txt" 2>/dev/null | tail -1)"
  case "$s" in
    *sum=*) fxsums="$fxsums${s##*sum=} ";;
    *)      bad "effect sheet, shell $sh" "an FXSHEET line" "$s"; fxsums="$fxsums MISSING ";;
  esac
done
fxuniq="$(printf '%s\n' $fxsums | sort -u | wc -l | tr -d ' ')"
if [ "$fxuniq" = 1 ]; then
  ok "effect sheet identical across shells $fxshells ($(printf '%s' $fxsums | head -c 9))"
else
  bad "effect sheet identical across shells $fxshells" "one checksum" "$fxsums"
fi

echo "== throws with SATURN AS THE THROWER (the \$C1-copy path) =="
# v0.14.14. Every throw test above uses a VANILLA thrower, and that is exactly
# why the copy bug shipped: with Saturn throwing, her proc runs out of the $C1
# COPY, whose read of the per-victim pose table was never hooked. The stub was
# then never entered and the victim got a pose from past the ten-entry table --
# screen-wide debris. Assert the stub IS entered and the index stays inside her
# 21-byte list. Negative-controlled: v0.14.13 reports stub-never-entered.
for m in 1 0; do
  n=$([ "$m" = 1 ] && echo "saturn thrower (mirror)" || echo "vanilla thrower")
  run "$T/throwidx_v_idx_$m.txt" env MIRROR=$m SHELL_ID=7 TAG=v_idx_$m ROM="$ROM" \
    tools/run.sh tools/saturn/probe_saturn_throwidx.lua 700
  check "thrown-pose index, $n" "THROWIDX PASS" "$T/throwidx_v_idx_$m.txt" "THROWIDX"
done

echo "== her four palettes follow the confirm button =="
# v0.14.12. Her transform used to copy palette 0 unconditionally, throwing away
# the slot the character select had loaded, so she looked identical on every
# button. Note the slots are 4-7, not 0-3: summoning her needs L+R held, and L/R
# are patch 3's palette modifiers — a build that only handled 0-3 would ship
# with one palette again. Asserting the four CGRAM rows are DISTINCT (the
# complement of the effect-sheet check just above, which asserts sameness).
palbtns="a b y x"; [ "$QUICK" = 1 ] && palbtns="a y"
palrows=""
for b in $palbtns; do
  run "$T/palslot_$b.txt" env PALBTN=$b SHELL_ID=6 ROM="$ROM" \
    tools/run.sh tools/saturn/probe_saturn_palslot.lua 500
  r=""; [ "$rc" -eq 0 ] && r="$(grep -E '^PALSLOT' "$T/palslot_$b.txt" 2>/dev/null | tail -1)"
  case "$r" in
    *cgram=*) palrows="$palrows${r##*cgram=} ";;
    *)        bad "palette, button $b" "a PALSLOT line" "$r"; palrows="$palrows MISSING ";;
  esac
done
paln="$(printf '%s\n' $palrows | wc -l | tr -d ' ')"
paluniq="$(printf '%s\n' $palrows | sort -u | wc -l | tr -d ' ')"
if [ "$paluniq" = "$paln" ]; then
  ok "palettes distinct across buttons $palbtns ($paluniq of $paln)"
else
  bad "palettes distinct across buttons $palbtns" "$paln distinct rows" "$paluniq distinct"
fi

echo "== her round-won badge (both sides, every shell) =="
# v0.17.0. Taking a round showed nothing on her side: the badge's tile word comes
# from a TEN-entry table at $C0:E166 indexed by charID*2, and id $1C reads 0x38
# past it into code. The badge is drawn from EIGHT read sites, and six of them
# are P2 or redraw paths -- so this runs both sides and wins TWO rounds, because
# a fix that patched only the two first-draw sites passes a one-round P1 test.
# Negative-controlled: on v0.16.1 every dimension reports BAD (the cells hold
# $1E0A, the CHR tiles are blank and CGRAM holds the SHELL's icon palette).
bshells="6 7 8"; [ "$QUICK" = 1 ] && bshells="6"
bsums=""
for side in p1 p2; do for sh in $bshells; do
  run "$T/winbadge_v_${side}_$sh.txt" env SIDE=$side SHELL_ID=$sh TAG=v_${side}_$sh \
    ROM="$ROM" tools/run.sh tools/saturn/probe_saturn_winbadge.lua 2600
  check "round-won badge, $side on shell $sh" "FINAL PASS" \
    "$T/winbadge_v_${side}_$sh.txt" "FINAL|PRECONDITION|TIMEOUT"
  s=""; [ "$rc" -eq 0 ] && s="$(grep -E '^FINAL' "$T/winbadge_v_${side}_$sh.txt" 2>/dev/null | tail -1)"
  case "$s" in *chrsum=*) bsums="$bsums${s##*chrsum=} ";; *) bsums="$bsums MISSING ";; esac
done; done
# Trap 6, the question her 214P projectile answered the hard way: her tiles ride
# the HUD sheet's transfer, so assert the sheet arrives IDENTICALLY on every
# shell rather than merely arriving on the one that was tested.
buniq="$(printf '%s\n' $bsums | sort -u | wc -l | tr -d ' ')"
if [ "$buniq" = 1 ] && [ "${bsums%% *}" != "MISSING" ] && [ "${bsums%% *}" != "0" ]; then
  ok "badge tiles identical across sides/shells (chrsum $(printf '%s' $bsums | head -c 6))"
else
  bad "badge tiles identical across sides/shells" "one non-zero checksum" "$bsums"
fi

echo "== her ground throws: right button, right direction =="
# v0.16.0. Both faults were INHERITED FROM SUPER S, so nothing in the port would
# have caught them: the two throws sat on each other's buttons, and the shoulder
# throw's toss velocity was negative (6 sent the victim behind, 4 in front).
# Assert the mapping AND the direction — a check on the act alone would pass on
# a build that still threw backwards.
thr="6hp:\$7B:right->right 6hk:\$68:right->right"
[ "$QUICK" != 1 ] && thr="$thr 4hp:\$7B:right->left 4hk:\$68:right->left"
for t in $thr; do
  i="${t%%:*}"; rest="${t#*:}"; a="${rest%%:*}"; sd="${rest#*:}"
  run "$T/throwmap_v_thr_$i.txt" env SATURN=1 SHELL_ID=6 INPUT=$i TAG=v_thr_$i \
    ROM="$ROM" tools/run.sh tools/saturn/probe_throwmap.lua 120
  check "throw $i -> act $a, victim $sd" "firstact=$a side=$sd" \
    "$T/throwmap_v_thr_$i.txt" "THROWVERDICT"
done

if [ "$QUICK" != 1 ]; then
  echo "== L+R coverage (independent harness) =="
  # story is expected to REFUSE her; probe_sms_lrmodes judges against its own mode
  for m in practice vscom story; do
    run "$T/lrmodes_$m.txt" env MODE=$m SHELL_ID=6 ROM="$ROM" \
      tools/run.sh tools/saturn/probe_sms_lrmodes.lua 500
    check "lrmodes $m shell 6" "LR PASS" "$T/lrmodes_$m.txt" "FINAL"
  done

  echo "== stress: wedge / VRAM corruption over a full match =="
  # The probe names its log stress_<SEED>[m].txt, so SEED=7 MIRROR=1 writes
  # stress_7m.txt. This check read stress_1m.txt — a file no run in this script
  # has ever produced — and passed for as long as the seed has been 7, on a trace
  # left behind by an old SEED=1 experiment. Caught the first time `run` deleted
  # the file it was about to read. This is exactly the class #79 is about.
  run "$T/stress_7m.txt" env MIRROR=1 SEED=7 ROM="$ROM" \
    tools/run.sh tools/saturn/probe_sms_stress.lua 400
  check "randomised mirror match" "ENDED CLEANLY" "$T/stress_7m.txt" "ENDED|WEDGE"

  echo "== OBJ palette census over a FULL match (KO + round end included) =="
  # A practice-mode sample said pals 5/6/7 were all unused; over a full match
  # pal 6 turns out to be the HIT SPARK. So the row her projectiles moved onto
  # has to be re-proved at match scale, not assumed — if anything vanilla ever
  # draws with pal 7, v0.14.9 picked the wrong row.
  run "$T/stress_1.txt" env PALHIST=1 VANILLA=1 SEED=1 ROM="$ROM" \
    tools/run.sh tools/saturn/probe_sms_stress.lua 500
  check "OBJ pal 7 is free in vanilla (her projectiles' row)" "pal7=0" \
    "$T/stress_1.txt" "PALETTE CENSUS"
  PALHIST=1 SEED=1 ROM="$ROM" \
    tools/run.sh tools/saturn/probe_sms_stress.lua 500 >/dev/null 2>&1
  check "Saturn never draws on OBJ pal 2 (the opponent's row)" "pal2=0 pal3" \
    "$T/stress_1.txt" "PALETTE CENSUS"
fi

echo
if [ "$fail" -eq 0 ]; then
  printf '\033[32mALL PASS\033[0m (%d checks)\n' "$pass"; exit 0
fi
printf '\033[31m%d FAILED\033[0m of %d: %s\n' "$fail" "$((pass+fail))" "${failed[*]}"; exit 1
