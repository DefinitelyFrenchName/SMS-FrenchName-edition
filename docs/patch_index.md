# Patch index — the one-page registry

**What this is.** Every patch in the project, one line each, with status and lifecycle
notes — the at-a-glance map when the per-patch detail in `docs/patch_notes.md` is too
much. Update THIS file whenever a patch is added, revised, or deprecated.

All patches are independent stackable BPS files built by `tools/mkpatchN.py`,
byte-disjoint by design (any install order; regression-guarded by
`tools/test_regression.lua`, which auto-detects which are present).
Current all-patches build: **v0.19** (`53bae682…`).

| # | Name | One-liner | Status | Standalone BPS (`build/`) |
|---|---|---|---|---|
| **1** | 1f-link (meaty) | Uranus infinite → 1-frame meaty link (gate 0x04, N=6): one exact press connects, escapable by reversal/jump — the project's founding patch | **CANONICAL** | `sms_uranus_infinite_1f.bps` |
| 1b | 1f-link (true combo) | Alternative gate 0x05 (N=5): the one frame is a true combo instead of a meaty | ALTERNATE (pick 1 *or* 1b, never both) | `sms_uranus_infinite_1f_truecombo.bps` |
| **2** | No reversal-dash invuln | Removes the invincibility of Uranus's guard-cancel ("reversal") Shadow Dash | CANONICAL | `sms_dashfix.bps` |
| **3** | Palettes + header | Big Zam extended color palettes + "FrenchName" internal header | CANONICAL (cosmetic) | `sms_palettes.bps` |
| **4** | Title subtitle | Title-screen version text (doubles as the naked-eye build tell, e.g. "v.0.19") | CANONICAL (cosmetic) | `sms_title.bps` |
| **5** | Dash distance | Uranus forward-dash distance −1/3 (~145 → ~89px) | CANONICAL | `sms_dashdist.bps` |
| 6 | Dash i-frames | Uranus forward dash gains ~6 strike-invuln frames mid-move | EXPERIMENTAL — tension with patch 2's nerf intent; deprecation candidate | `sms_dashinvuln.bps` |
| 7 | Pluto 5HP vs crouchers | Extends c.HP's active box down so the semi-overhead hits every croucher except Chibi | OPTIONAL | `sms_pluto5hp.bps` |
| 8 | Venus throw tech | Venus 6HP throw mash-escape window 6f → 13f (standard-ish) | OPTIONAL | `sms_venustech.bps` |
| 9 | Neptune fireball fix | Deep Submerge hitbox tracks the descending sprite (was stuck at head level) | OPTIONAL (bugfix-flavored) | `sms_neptune_ds.bps` |
| 10 | Combo counter | Live in-match combo counter rendered by the base game (no overlay) | OPTIONAL | `sms_combocounter.bps` |
| 10b | + status labels | Combo counter + GC/MEATY/REVERSAL/PUNISH/TECH event labels (build flag `--events labels`, same patch slot as 10) | OPTIONAL (variant of 10) | `sms_combolabels.bps` |
| 11 | Training+ | In-ROM training-mode upgrade: L+R menu, dummy control, recording, HP tools, displays | OPTIONAL | `sms_trainingplus.bps` |
| 12 | Taunts | Taunt on L using each character's native misfire animation | OPTIONAL | `sms_taunt.bps` |
| 13 | Guts (v3.3) | Completing a taunt stacks levels (≤3) that shrink the opponent's SPECIAL/desperation damage vs you (20/40/60%, per-round) | OPTIONAL | `sms_tauntbuff.bps` |
| 14 | Guts Grip | Companion to 13: the same levels also shrink command-grab damage (SPDs/Giant Swing); inert without 13 | OPTIONAL (requires 13 to do anything) | `sms_gutsgrip.bps` |

## Lifecycle notes

- **Canonical set** = 1+2+3+4+5 (the original balance+cosmetic core, ROM v0.7 lineage).
  Everything ≥6 is opt-in; the vX.Y "ALLPATCHES" test ROMs carry all of them.
- **Mutually exclusive**: 1 vs 1b (same bytes, different gate value). 10 vs 10b (same
  builder, flag chooses).
- **Dependencies**: 14 reads 13's state (read-only ABI) — stack in any order, but 14
  without 13 is a no-op. 13 is playable without 12 only via real ACS-misfire whiffs;
  with 12 the taunt is the intended trigger.
- **Deprecation candidates**: 6 (experimental buff that pulls against patch 2; keep
  only if the maintainer decides dash-invuln is wanted after all). 1b retires whenever
  the canonical gate choice is final.
- **Known pending tweak**: patch 13's corner level-indicator is slated to become
  training-mode-only "down the line" (maintainer note, unscheduled).
- **Pruned (2026-07-19)**: all historical cumulative bundles (`sms_full*`,
  `sms_both`, all-patches BPS < v0.19 and the mislabeled v1.x line) — only the
  per-patch standalone BPS above plus the CURRENT `sms_allpatches_vX.Y.bps` are kept;
  any bundle is rebuildable by chaining the standalones (order-free). Locally kept
  .sfc: the current ALLPATCHES ROM, `…v0.7_all5.sfc` (the non-interference test
  baseline), and the per-patch standalones the test suites load.
- Per-patch deep detail (mechanism, changed bytes, verification, version history):
  `docs/patch_notes.md`. Build commands & ROM inventory: `HANDOFF.md`.
