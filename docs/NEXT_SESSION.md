# Next-session handoff — 2026-07-20

Fast orientation. **Full operational map: `HANDOFF.md`; patch registry:
`docs/patch_index.md`; engine subsystems: `docs/sms_engine_internals.md`; per-patch
detail: `docs/patch_notes.md`.**

## THE open item — resume here

**Maintainer field report: "I can't use L+R anymore for in-game training mode" on the
all-patches ROM. NOT reproduced; waiting on their answers.** Investigated 2026-07-20
(commit `1a5963d`, annotations "L+R training-menu report investigated"): on the
delivered v0.21 image (`62ffb174…`) the menu opens in EVERY tested scenario — fresh-boot
Practice entry, L/R press skew 0/2/6/10f, movelist Start open/close, random power-on
RAM, damage-on (mode 5) + KO; the menu also RENDERS (screenshot-identical to the
pre-change build); the bundle BPS round-trips byte-exact; suite 59/59 on it.
Gate recap: `$8D∈{4, 5(+DMGFLAG $7F:F004==0xA5)}` && `$0070==4` && `$01FA==0x80`.

**Prime suspect:** a ROM assembled by chaining standalone BPS files — a since-corrected
patch_index note wrongly blessed that; ALL bank-appending standalones (4, 10/10b, 11,
12, 13, 14) target the same first-free bank **$E8** (verified byte-level), so chained
application clobbers earlier patches' code banks and the classic casualty is exactly
p11's L+R stub. See the new gotcha in HANDOFF §5.

**Questions pending with the maintainer** (asked at end of session):
1. Which file did they test — delivered `v0.21_ALLPATCHES.sfc`, the bundle
   `sms_allpatches_v0.21.bps` applied to clean, or a chained-standalones build?
2. Emulator or console/flashcart (which)?
3. Exact repro: L+R dead from the very start of a Practice match, or only after
   something (KO / Start / Select / mode change)? Practice, not VS (VS never had L+R)?

Tools built for this: `tools/probe_p11_lr.lua` (fresh-boot Practice autopilot — NOTE it
fixes a real trap: P1 must also confirm the dummy's char, P2's pad is inert; plus L+R
skew attempts, movelist preambles, menu screenshot) and `tools/probe_p11_ko_lr.lua`
(mode-5 damage-on + KO, L+R after). Old `probe_p11_nav.lua` stalls at char-select on
current builds and can clobber `traces/training_p11.mss` with a non-match state
(tracked file — restore with git).

## What shipped this session (2026-07-20)

**MEATY status label removed everywhere** (commit `e9c1976`) — pad testing showed it
felt strange-to-detrimental. Removed from BOTH the Lua overlay
(`tools/training/labels.lua`) and patch 10b (`mkpatch10.py`: label id 4 retired, ids
1/2/3/5 stable; M/Y glyphs dropped). GC/REVERSAL/PUNISH/TECH (+Lua-only THROWN/TRADE)
remain. The meaty *detection rule* stays documented in `sms_engine_internals.md`.
- New all-patches build **v0.21** (`62ffb174…`, title tell "v.0.21"); byte-diff vs
  v0.20 confined to p10 bank + title tiles + hook target + checksum. v0.20 bundle pruned.
- `training_test.lua` T4 now asserts the label does NOT fire on the frame-perfect
  infinite; `test_labels_cfg.lua` is now a committed PUNISH scenario (the old untracked
  debug cfg sampled outside the 48f TTL and could never pass).
- Suites after change: **v0.21 = 59 ALL PASS, clean = 41 ALL PASS**, T4/T5/T8 PASS,
  in-ROM label oracle PASS.

The maintainer had announced "two new tasks"; the second was never stated (the L+R
report arrived instead). **Ask about it if they don't bring it up.**

## Current state in one breath

14 patches + 2 variants, registry with status/lifecycle in `docs/patch_index.md`.
Canonical = 1+2+3+4+5 (v0.7, `24aa6b6d…`). Newest all-patches test ROM v0.21.
Regression suite `tools/test_regression.lua` (fingerprint auto-detection, statics,
base-engine locks, per-patch behavioral tests, FULL mode): 59/59 on v0.21, 41/41 clean.
The RE campaign is CLOSED — damage pipeline, ACS, reaction dispatch, danger/ochame,
input recognizers, GC system, throws, specials compendium (`docs/sms_specials.md`) all
decoded and regression-locked. Ochame-inflicting taunt: REJECTED by maintainer.

## Open threads (unchanged backlog)

- Maintainer decisions: patch 6 deprecation, patch 1 vs 1b final gate, Guts knob feel,
  whether p14 `--all-grabs` ever ships. Their side: pad-test v0.21 (indicator
  training-only + MEATY-gone tells).
- Parked trivia: full per-char d48 census (needs boot-fresh rounds; Jupiter=1 Neptune=2
  verified), +0x76 slot meanings, unobserved acts (0x07/0x10/0x14), dizzy handler
  details, ground-vs-air same-throw vertical wiki comparison.
- Rig-limited attested: Jupiter air Power Bomb, Mercury triangle jump.
- Housekeeping nit: CLAUDE.md status banner still describes the 10-patch era.

## Session hygiene

Commit per finding; `git stash -q && git pull --rebase -q && git push -q &&
git stash pop -q` around pushes; `.sfc` gitignored (rebuild from BPS), bundle BPS =
current only; never patch in place; all claims emulator-verified
(`ROM=<build> tools/run.sh <script> <timeout>`); temp files in `$CLAUDE_JOB_DIR/tmp`.
