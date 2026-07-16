# Next-session handoff — 2026-07-17

Fast orientation. **Full operational map: `HANDOFF.md`; engine subsystems:
`docs/sms_engine_internals.md`; per-patch detail: `docs/patch_notes.md`.**

## TL;DR

**Patch 11 (the in-ROM training mode challenge) is DONE** on branch `patch11-training-rom`
— built, oracle-tested (50+ checks ALL PASS), perf-proven (3.4% worst, VS byte-inert),
packaged (`build/sms_trainingplus.bps`, showcase `build/sms_allpatches_v1.1.bps`).
Awaiting the maintainer's pad test + merge decision. `main` still has patches 1-10 only.

## What patch 11 is

The base game's Practice mode upgraded in-ROM (works on hardware): **L+R opens a menu**
(BG3-rendered) with POSE / GUARD(off/all/afterhit) / WAKEUP(jab/throw/44-dash) / TECH-mash
/ DAMAGE (the native mode-4↔5 hp switch) / REGEN / REFILL(no-KO) / RECORD+PLAY (34s input
recording into a $7F:E000 WMDATA ring, puppet-record) / SHOW (live input display + ADV ±N)
/ RESET. Dummy driven by rewriting P2's pad words at the joy_read tail ($80:8373 hook) —
the Lua trainer's mechanism, in 65816. Second hook $80:D574 (vblank) does all VRAM/TM work.
Native Start=movelist / Select=exit preserved. See `docs/trainingplus.md` (dedicated guide) and `docs/patch_notes.md` Patch 11 for the
pad guide, the RE facts (mode 4/5 semantics, dead HUD producer, BG3=movelist layer,
TM management, KO-latch standup trick, bank-$7F state) and the full verification list.

## For the maintainer (pad checklist)

1. Apply `build/sms_allpatches_v1.1.bps` to the clean ROM (or rebuild:
   `python3 tools/mkpatch11.py <src> <out>` stacks on anything).
2. Title should read "FrenchName v.1.1". Enter Practice (menu: down, right, start).
3. L+R → menu (≈0.5s). Feel: navigation, value edits, DAMAGE on → hits drain HP,
   REFILL keeps everyone alive, RECORD/ARM → close → puppet the dummy → L+R → PLAY LOOP.
4. Start (movelist) and Select (exit) must behave exactly as vanilla, menu closed.
5. VS / story modes must feel identical to v1.0 (they are byte-identical per frame).

## Open threads

- **Merge decision**: fold `patch11-training-rom` into main? (Everything committed there;
  docs/annotations "patch 11 RE" section documents all new engine facts.)
- Recording doesn't mirror on side swap (documented); facing-relative encode is the one
  known enhancement candidate, needs a bit-swap layer at record+playback.
- ADV readout is ±1-approximate vs Lua framedata conventions (documented, by design).
- Old open threads (fold experiments into canonical, Neptune act-0x02 gap, dash retune)
  unchanged from 2026-07-16.

## Session hygiene

Unchanged (commit per finding, pull-rebase before push, .sfc gitignored — rebuild from
BPS, shared headless-harness scratch files). Patch-11 test entry points:
`tools/test_p11_tier1.lua` (suite), `tools/perf_patch11.lua` (+`_cfg`), probes
`tools/probe_p11_*.lua`, savestate `traces/training_p11.mss` (clean-ROM Practice match).
