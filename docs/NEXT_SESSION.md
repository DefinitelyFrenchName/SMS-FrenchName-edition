# Next-session handoff — 2026-07-16

Fast orientation for whoever (human or a future Fable session) picks this up. **For the full
operational map read `HANDOFF.md`; for how the engine works read `docs/sms_engine_internals.md`.**
This note is just "where we are and what's live right now."

## TL;DR

Everything is green and pushed (`main` == `origin/main`, latest `cc3ac47`). The project has
**10 ROM patches** (canonical v0.7 = 1–5; optional experimental 6–10) plus a **full Mesen-Lua
training mode**. Nothing is broken or half-done. No open bugs.

## What this session did (the recent arc)

- **Patch 8** — Venus 6HP throw made mash-escapable (6f → 13f window); reverse-engineered the
  whole mash-tech mechanism ($C1:07CF sampler / $C1:0823 toss decision, thrower +0x56).
- **Training mode** (`tools/training/`, pure Mesen Lua, no ROM edits) — grew to the full
  feature set: SF6 frame meter, recordable dummy + GC trainer, input piano roll, event labels,
  combo counter (tight-link/1F coloring), hitbox viewer, frozen timer, HP regen, KO auto-reset,
  keyboard menu + pad controls. Validated by a headless oracle suite (`tools/training_test.lua`,
  32+ checks). Distributed as `build/sms_training_mode.zip` (+ `docs/training_{install,usage}.md`).
- **Patch 9** (other session, merged) — Neptune Deep Submerge fireball hitbox tracks the sprite.
- **Patch 10** — the big one: **in-match combo counter + status labels rendered by the base
  game** (no overlay, works on hardware). Full RE of the in-match HUD (Arch A: producer
  `$C0:D5E8` → WRAM staging → NMI uploader `$C0:D56F`). `--events labels` adds
  GC/MEATY/REVERSAL/PUNISH/TECH as text. **Measured performance: ~2.6% CPU, frame-identical to
  clean = zero lag** (the emphasized deliverable).
- **All-patches test ROM** `SailorMoonS_FrenchName_v1.0_ALLPATCHES.sfc` (SHA-1 `f20f2883`).
- **Docs** — wrote `docs/sms_engine_internals.md` (the subsystem synthesis) and this note.
- **Two feedback fixes** — projectile hitbox-viewer flicker (garbage roster-only hurt table →
  draw hit box only for ids ≥10) and HP-regen life-bar red gaps (bar fill is per-cell PALETTE;
  producer only repaints the boundary during a drain → regen now repaints the full bar to VRAM).

## Solid / don't re-verify (measured, not inferred)

- All 10 patches stack cleanly (byte-disjoint) and the all-patches ROM boots + plays.
- Patch 10 counter/labels match the training-mode Lua **frame-for-frame** (oracle-tested) and
  add zero lag (frame-identical soak, 1500 frames).
- The engine map in `sms_engine_internals.md` / `annotations.md` is verified in-emulator.

## Open threads / possible next work (nothing urgent)

- **Fold experimental patches into canonical?** 6 (dash i-frames), 7 (Pluto 5HP), 8, 9, 10 are
  off by default, awaiting a maintainer decision on whether any join a future canonical build.
  If folding: bump the title version (`mkpatch4.py --text`) for the pad-tester's naked-eye tell.
- **Neptune fireball act-0x02 gap** — the fireball's attack box is index 0 during its dissipation
  phase (documented in `sms_engine_internals.md` §9). Making it hit through the transition is a
  *gameplay change* (animation-script edit) the maintainer declined; left as-is intentionally.
- **Patch 10 knobs** — `--min-hits`, `--ttl`, `--modes`, `--events`. Labels default off. PUNISH
  is the least-exact detection (documented); revisit if it misfires in play.
- **Dash distance** (patch 5) may still be retuned (`mkpatch5.py --speed`).

## Orientation — which doc for what

| Need | Read |
|---|---|
| Operational map, build/test, patch table, gotchas | `HANDOFF.md` |
| How a subsystem works (to understand/modify the game) | `docs/sms_engine_internals.md` |
| Exact addresses (the phone book) | `docs/annotations.md` |
| Per-patch detail (what each changed + why) | `docs/patch_notes.md` |
| Training-mode use / install | `docs/training_{usage,install}.md` |
| Recalled facts across sessions | memory files (see `MEMORY.md` index) |

## Critical gotchas (these bite)

- `emu.setInput` port is the **3rd** arg; savestate load/save only inside an exec callback on
  `$80:8353`; GUI refuses a savestate whose ROM tag ≠ open ROM (headless is permissive);
  `takeScreenshot` does **not** composite the ScriptHud overlay (console-surface draws do show).
- Button map **Y=LP X=HP B=LK A=HK**. Invuln = **empty hurtbox (idx 0)**, not a flag.
- **Provenance rule:** `vendor/sms-training-mode/` tooling is from Sailor Moon *Super S* — never
  trust it for Saturn (not in this game) or unverified addresses; validate on emulator.
- The mini-assembler `tools/asm65816.py` tracks M/X flags for immediate width (`ldx #$00` must be
  16-bit when X is 16-bit) and has 8-bit branches only (far conditional → `bne skip; jmp far`).

## Session hygiene

- **Commit per finding; `git pull --rebase` before pushing** (commits from parallel work can
  interleave). `.sfc` builds are gitignored (rebuild from BPS); force-add BPS + the training zip.
- **Headless test harness is shared scratch** (`tools/trace_plan.lua`, `coltest_cfg.lua`,
  `training_test_cfg.lua`) — if another session runs concurrently, don't run emulator tests at
  the same time (they'd clobber each other's configs). Solo now, so moot.
- Run the training suite before shipping training changes:
  `for T in T1 T2 T2H T3 T5 T6 T7; do echo "TEST=\"$T\"">tools/training_test_cfg.lua; ROM=<clean> tools/run.sh tools/training_test.lua 250; done`
  (T4/T8/T9 need a v0.7-family ROM). Patch-10 label oracle: `tools/test_labels.lua`; perf:
  `tools/perf_patch10.lua`.
