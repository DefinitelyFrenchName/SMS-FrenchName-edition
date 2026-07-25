# Next-session handoff — 2026-07-25

Fast orientation. **Full operational map: `HANDOFF.md`; patch registry:
`docs/patch_index.md`; engine subsystems: `docs/sms_engine_internals.md`; per-patch
detail: `docs/patch_notes.md`.**

## Status — no open items

All suites green. Current bundles: **v0.22 all-patches** (`52bc7e38…`, 59/59) and the
**REF v.1 reference bundle** (`bd1104ee…`, 55/55). Canonical is still v0.7 (`24aa6b6d…`).

## What shipped this session (2026-07-25)

**Patch 10 field report fixed** (maintainer: combo counter never appears — in 1P-vs-COM,
2P VS and training — and status labels never disappear; seen on v0.21 AND p10 standalone).
Root causes, both in `tools/mkpatch10.py`, both A/B-verified in-emulator:

1. **Stuck labels:** `_label_render`'s expiry branch did `sta shown / bne draw` — `sta`
   sets no flags, so the branch tested the stale Z from the labelId≠shown compare and the
   labelId==0 blank path was **unreachable dead code**. On TTL expiry the same glyphs
   were re-staged forever. Latent since v1, masked while the MEATY label (removed
   2026-07-20) churned labelId on nearly every hit. Fix: `cmp #$00` re-test after the
   store. A/B: pre-fix PUNISH drawn@84 never blanks; fixed blanks@131 (47f = TTL).
2. **Counter dead vs the CPU:** `_mode_gate` default excluded `$008D`=2 (1P-vs-COM).
   Default `--modes` now `0,1,2,4,5`. A/B via mode-poke mid-combo (`probe_p10_vs.lua`).
3. **Not bugs, now documented:** the counter pipeline is healthy in 2P VS (shows only on
   true chains ≥ `--min-hits` 2, by design — same semantics as the Lua counter), and the
   counter can never show in practice/training: the hooked HUD producer `$C0:D5E8` does
   not execute there (`probe_p10_practice.lua`, 0 execs/300f) — p11 and the Lua training
   mode carry their own counters. `--ttl` was a dead knob; now wired (default 72 = old
   hardcode, byte-identical).

**Test-gap closed** (old suites were WRAM-only and stayed green through both bugs):
`test_regression.lua` p10-combo-counter is now a VRAM show→count→clear oracle;
`test_labels.lua` asserts the label row blanks within TTL+10f of the event.
New probes: `tools/probe_p10_vs.lua` (pipeline logger + optional `P10_MODE2_FROM/TO`
mode-poke), `tools/probe_p10_practice.lua`, `tools/probe_title_shot.lua` (title
screenshots). `perf_patch10_cfg.lua` STUB_F recomputed → `$EA:06E6` (was stale).
Rebuilt: `sms_combocounter.bps` (`b819f3d4…`), `sms_combolabels.bps` (`38faf40c…`),
**v0.22** bundle. Perf on v0.22: 2.24% worst-case, glyph upload 3 scanlines — fine.

**REF v.1 reference bundle** (maintainer request): 1b+2+3+4+5+7+8+9+12+13+14 →
`build/sms_reference_v1.bps`, ROM `SailorMoonS_FrenchName_REF_v1.sfc` (`bd1104ee…`),
title tell "FrenchName REF v.1" (uppercase E/R glyphs added to `texttiles.py`).
**Patch 12 kept deliberately:** without it p13's Guts grant is unreachable in normal play
(the only other trigger is a real ochame misfire; all ACS stats are 0 in every normal
mode) and p14 is then inert. Regression 55/55 with expected detection (p1 reads absent —
the fingerprint pins gate 0x04; only the true-combo gate byte differs, no test depends
on it). Title verified by screenshot.

## Current state in one breath

14 patches + 2 variants, registry in `docs/patch_index.md`. Canonical = 1+2+3+4+5
(v0.7). Newest all-patches v0.22; reference bundle REF v.1. Regression suite:
59/59 v0.22, 55/55 REF v.1, 41/41 clean. RE campaign CLOSED.

## Open threads (unchanged backlog)

- Maintainer decisions: patch 6 deprecation, patch 1 vs 1b final gate, Guts knob feel,
  whether p14 `--all-grabs` ever ships. Their side: pad-test v0.22 (counter now visible
  vs COM; labels expire) and REF v.1.
- Parked trivia: full per-char d48 census, +0x76 slot meanings, unobserved acts
  (0x07/0x10/0x14), dizzy handler details, ground-vs-air same-throw wiki comparison.
- Rig-limited attested: Jupiter air Power Bomb, Mercury triangle jump.

## Session hygiene

Commit per finding; `git stash -q && git pull --rebase -q && git push -q &&
git stash pop -q` around pushes; `.sfc` gitignored (rebuild from BPS), bundle BPS =
current only; never patch in place; all claims emulator-verified
(`ROM=<build> tools/run.sh <script> <timeout>`); temp files in `$CLAUDE_JOB_DIR/tmp`.
