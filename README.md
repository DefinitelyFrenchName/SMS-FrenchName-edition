# SMS Sailor Moon S balance/feature patch project


### This work would have required orders of magnitude more effort without the remarkable findings and incredible tooling by the community, especially Moonlight Fight Society and especially Sprint: they have been for years the true heroes keeping the dream alive. 

Important: this is a work in progress to offer options to reintroduce Brad in the roster and correct (arguably minor) bugs.
The point is NOT to rebalance the game: it is broken in all the best ways.

The extra features like in-game training mode extension, combo counter and status mentions as well as new feature are experimental and not confirmed desireable.

The project also includes an extensive Mesen training script developed for my specific needs. While it may be adapted for others, it does not aim at replacing existing community training scripts

Some of the memory analysis, all the decisions and a disgusting amount of testing was made by me. However all the assembly heavy lifting and the vast majority of lua scripting was done by Claude. 

Everything implemented relies on a suite of in-emulator end-to-end tests, both automated and human double-checked for edge cases.
Any patch listed as not fully tested has been tested using the automated test suite but the extent of human double-checks does not reach my quality bar... yet.


## Get started (applying a patch)

1. Obtain the clean ROM: *Bishoujo Senshi Sailor Moon S: Jougai Rantou!?* (SFC, Japan) —
   verify SHA-1 `bc0e29ee383574443226695215496eb0d09aaa1c`. ROMs are never distributed here.
2. Get [Floating IPS (flips)](https://github.com/Alcaro/Flips) (or any BPS patcher).
3. Apply a `.bps` from `build/` to the clean ROM, e.g.
   `flips --apply build/sms_allpatches_v0.22.bps "<clean>.sfc" out.sfc`
4. Verify the output SHA-1 against the tables below / [docs/patch_index.md](docs/patch_index.md).

Deeper docs: [docs/patch_index.md](docs/patch_index.md) (one-line registry, status,
lifecycle), [docs/patch_notes.md](docs/patch_notes.md) (per-patch mechanism + verification),
[HANDOFF.md](HANDOFF.md) (operational map: build, test, gotchas),
[docs/sms_engine_internals.md](docs/sms_engine_internals.md) (how the engine works).
Training mode (pure Lua, no ROM patching): [docs/training_install.md](docs/training_install.md).

## Deliverables & how they stack

Target: Bishoujo Senshi Sailor Moon S: Jougai Rantou!? (SFC, Japan),
clean ROM SHA-1 `bc0e29ee383574443226695215496eb0d09aaa1c` (HiROM+FastROM, headerless,
file offset = SNES addr & 0x3FFFFF).

ROMs are never tracked in git. The tooling looks for them in `$SMS_ROM_DIR`, then
`roms/` inside the tree, then `../roms/` **above** the tree — the recommended spot, so
no ROM can end up in a commit.

| Patch **(located in build/ )**                                    | What                                                         | Builder                              | Standalone BPS                                         | Patched SHA-1 |
| --------------------------------------------- | ------------------------------------------------------------ | ------------------------------------ | ------------------------------------------------------ | ------------- |
| 1. 1f-meaty **(not true link)**                    | Uranus infinite → **1-frame meaty** (N=6): exactly one press connects, and it's an unblockable-by-block meaty (escapable by invincible reversal / jump) | `tools/mkpatch.py 0x04`              | `build/sms_uranus_infinite_1f.bps` (+`.ips`)           | `258ffd4e…`   |
| 1b. 1f-link **(true combo, use 1 OR 1b)**                      | **Alternative to patch 1** — true unblockable 1-frame combo (N=5); wider (2-frame connect: combo@0 + meaty@+1) | `tools/mkpatch.py 0x05`              | `build/sms_uranus_infinite_1f_truecombo.bps` (+`.ips`) | `deefccec…`   |
| 2. Dash-fix                                   | Remove reversal-dash invincibility                           | `tools/mkpatch2.py`                  | `build/sms_dashfix.bps` (+`.ips`)                      | `14f747a7…`   |
| 3. Sprint's Palettes                                   | Sprint / Big Zam extended character colors ( + "FrenchName" rom header for easy rom ID) | `tools/mkpatch3.py`                  | `build/sms_palettes.bps`                               | `291f6474…`   |
| 4. Title                                      | Title subtitle → "FrenchName ver. X.Y" + copyright line 1 → "©MOONLIGHT FIGHT SOCIETY" | `tools/mkpatch4.py`                  | `build/sms_title.bps`                                  | `f5337f9a…`   |
| 5. Dash dist                                  | Cut Uranus forward-dash distance ~1/3                        | `tools/mkpatch5.py`                  | `build/sms_dashdist.bps`                               | `99acb686…`   |
| 6. Dash i-frames                | Uranus forward dash gains ~6 strike-invuln frames mid-move   | `tools/mkpatch6.py`                  | `build/sms_dashinvuln.bps` (+`.ips`)                   | `34c5d458…`   |
| 7. Pluto 5HP                   | Pluto 5HP hitbox extended down to hit crouchers (all but Chibi) | `tools/mkpatch7.py`                  | `build/sms_pluto5hp.bps`                               | `fc757936…`   |
| 8. Venus throw tech             | Venus 6HP throw mash-escape window 6f → 13f (standard-ish; Jupiter=15f) | `tools/mkpatch8.py`                  | `build/sms_venustech.bps`                              | `63ce0748…`   |
| 9. Neptune fireball           | Deep Submerge fireball hitbox tracks the descending sprite (was stuck at head level) | `tools/mkpatch9.py`                  | `build/sms_neptune_ds.bps`                             | `d5ee12a3…`   |
| 10. In-match combo counter (experimental, not-recommended)    | Live combo-hit counter rendered by the base game under each attacker's bar (no overlay needed; 2026-07-25 fix: now also shows vs the CPU) | `tools/mkpatch10.py`                 | `build/sms_combocounter.bps`                           | `be072a5e…`   |
| 10b. + status labels (experimental, not-recommended)      | Counter + GC/REVERSAL/PUNISH/TECH event text (MEATY label removed 2026-07-20; 2026-07-25 fix: labels now expire correctly) | `tools/mkpatch10.py --events labels` | `build/sms_combolabels.bps`                            | `920652df…`   |
| 11. Training+ (experimental, not-recommended)                | In-ROM training-mode upgrade: L+R menu, dummy control (pose/guard/wakeup/tech), recording+playback, damage/regen/refill, input+ADV display | `tools/mkpatch11.py`                 | `build/sms_trainingplus.bps`                           | `e9ac2205…`   |
| 12. Taunts                      | Taunt on L: each character's native misfire ("ochame") pratfall, fully vulnerable | `tools/mkpatch12.py`                 | `build/sms_taunt.bps`                                  | `614f318e…`   |
| 13. Guts (Q-style taunts)          | Completing a taunt stacks levels (≤3) that reduce the opponent's SPECIAL/desperation damage vs you (20/40/60%, per-round; indicator in training only) | `tools/mkpatch13.py`                 | `build/sms_tauntbuff.bps`                              | `bafb87d4…`   |
| 14. Guts Grip **(companion to 13)** | The same Guts levels also reduce command-grab damage (SPDs/Giant Swing); inert without patch 13 | `tools/mkpatch14.py`                 | `build/sms_gutsgrip.bps`                               | `5fadcaca…`   |
| 15. No AUTO                      | Removes the AUTO option from the VS button-config screen (Auto binds specials to L/R, colliding with patch 12's taunt) | `tools/mkpatch15.py`                 | `build/sms_noauto.bps`                                 | `31832e6e…`   |
| 17. All stages                   | Unlocks the hidden tenth stage (なかよし編集部) in the stage select, and — where patch 3 is present — in its random default pool | `tools/mkpatch17.py`                 | `build/sms_allstages.bps`                              | `e5dd325b…`   |

Combined builds (each applies to the clean ROM): `build/sms_allpatches_v0.22.bps` — all 14
patches (10 as 10b), ROM SHA-1 `3bb9c829…`, title tell "v.0.22"; `build/sms_reference_v1.bps`
— the **REF v.1** reference combination 1b+2+3+4+5+7+8+9+12+13+14 (true-combo gate, no
counter/training patches), ROM SHA-1 `2873f214…`, title tell "FrenchName REF v.1".
Both rebuilt 2026-07-30 with the patch-4 "©MOONLIGHT FIGHT SOCIETY" credit line (the
visible tell vs the pre-credit builds `52bc7e38…` / `bd1104ee…`).
`build/sms_reference_v2.bps` = REF v.1 + patch 15, ROM SHA-1 `6d79fb5f…`;
`build/sms_ref_v2_allstages.bps` = REF v.2 + patch 17, ROM SHA-1 `e8fc6045…`.
