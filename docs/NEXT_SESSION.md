# Next-session handoff — 2026-07-21

Fast orientation. **Full operational map: `HANDOFF.md`; patch registry:
`docs/patch_index.md`; engine subsystems: `docs/sms_engine_internals.md`; per-patch
detail: `docs/patch_notes.md`.**

## Status — no open items

**The L+R field report is RESOLVED (2026-07-21):** maintainer confirms L+R opens the
training menu as intended on the latest patches, and the taunt + Guts pipeline
(specials/desperation damage reduction, Q-style) works as intended. The 2026-07-20
investigation (commit `1a5963d`) stands as reference: the delivered v0.21 image was
always clean; the chained-standalone-BPS gotcha (HANDOFF §5) remains the documented trap.

## What shipped this session (2026-07-21)

**Lua training-mode HP-regen bug fixed** (maintainer field report: "life refill only
occurs after a normal hit; special move damage does not trigger refill after 2s").
Root cause was NOT the HP<max trigger: for **projectile specials** the attacker's BODY
never gets an active hitbox (the box lives on the projectile slot $1100), so
`framedata.lua`'s move machine never saw an active phase and every move-end path
required `seenActive` — the attacker stayed classified STARTUP forever after e.g. Deep
Submerge; `combo.lua`'s close gate treats attacker STARTUP as a live threat, so
`combo[2].active` stuck true, and `regen.lua` gates the refill on no-open-combo. A later
normal unstuck it (its real hitbox completed the move machine) — exactly the reported
symptom. **Fix:** one guard in `tools/training/framedata.lua` classify(): a return to a
neutral act now closes the move even with `seenActive == false`. Verified: refill fires
120f after a DS hit (probe `tools/probe_regen_special.lua`, repro + fix traces in
`traces/probe_regen_special.txt`); new regression **T10** in `tools/training_test.lua`
(DS hit → P1 reclassifies NEUTRAL → combo closes → refill; PASS on clean AND v0.21);
full self-test suite T1–T10 green (T1/T2/T2H/T3/T5/T6/T7 on clean, T4/T8/T9 on v0.7).

## Previous session (2026-07-20)

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
- ~~Housekeeping nit: CLAUDE.md status banner still describes the 10-patch era~~ —
  DONE 2026-07-24 (banner updated; patch_notes.md front matter/knobs/applying brought
  up to the 14-patch era, pruned-bundle references corrected in HANDOFF §1/§6).

## Session hygiene

Commit per finding; `git stash -q && git pull --rebase -q && git push -q &&
git stash pop -q` around pushes; `.sfc` gitignored (rebuild from BPS), bundle BPS =
current only; never patch in place; all claims emulator-verified
(`ROM=<build> tools/run.sh <script> <timeout>`); temp files in `$CLAUDE_JOB_DIR/tmp`.
