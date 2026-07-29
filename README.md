# SMS Sailor Moon S balance/feature patch project


### This work would have required orders of magnitude more effort without the remarkable findings and incredible tooling by the community, especially Moonlight Fight Society and especially Sprint: they have been for years the true heroes keeping the dream alive. 

Important: this is a work in progress to offer options to reintroduce Brad in the roster and correct (arguably minor) bugs.
The point is NOT to rebalance the game: it is broken in all the best ways.

The extra features like in-game training mode extension, combo counter and status mentions as well as new feature are experimental and not confirmed desireable.

The project also includes an extensive Mesen training script developed for my specific needs. While it may be adapted for others, it does not aim at replacing existing community training scripts

Some of the memory analysis, all the decisions and a disgusting amount of testing was made by me. However all the assembly heavy lifting and the vast majority of lua scripting was done by Claude. 

Everything implemented relies on a suite of in-emulator end-to-end tests, both automated and human double-checked for edge cases.
Any patch listed as not fully tested has been tested using the automated test suite but the extent of human double-checks does not reach my quality bar... yet.


## Deliverables & how they stack

Target: Bishoujo Senshi Sailor Moon S: Jougai Rantou!? (SFC, Japan),
clean ROM SHA-1 `bc0e29ee383574443226695215496eb0d09aaa1c` (HiROM+FastROM, headerless,
file offset = SNES addr & 0x3FFFFF).

| Patch **(located in build/ )**                                    | What                                                         | Builder                              | Standalone BPS                                         | Patched SHA-1 |
| --------------------------------------------- | ------------------------------------------------------------ | ------------------------------------ | ------------------------------------------------------ | ------------- |
| 1. 1f-meaty **(not true link)**                    | Uranus infinite → **1-frame meaty** (N=6): exactly one press connects, and it's an unblockable-by-block meaty (escapable by invincible reversal / jump) | `tools/mkpatch.py 0x04`              | `build/sms_uranus_infinite_1f.bps` (+`.ips`)           | `c773d99a…`   |
| 1b. 1f-link **(true combo, use 1 OR 1b)**                      | **Alternative to patch 1** — true unblockable 1-frame combo (N=5); wider (2-frame connect: combo@0 + meaty@+1) | `tools/mkpatch.py 0x05`              | `build/sms_uranus_infinite_1f_truecombo.bps` (+`.ips`) | `8966c119…`   |
| 2. Dash-fix                                   | Remove reversal-dash invincibility                           | `tools/mkpatch2.py`                  | `build/sms_dashfix.bps` (+`.ips`)                      | `07d760fe…`   |
| 3. Palettes                                   | Sprint / Big Zam extended character colors ( + "FrenchName" rom header for easy rom ID) | `tools/mkpatch3.py`                  | `build/sms_palettes.bps`                               | `291f6474…`   |
| 4. Title                                      | Title subtitle → "FrenchName ver. X.Y" + copyright line 1 → "©MOONLIGHT FIGHT SOCIETY" | `tools/mkpatch4.py`                  | `build/sms_title.bps`                                  | `f5337f9a…`   |
| 5. Dash dist                                  | Cut Uranus forward-dash distance ~1/3                        | `tools/mkpatch5.py`                  | `build/sms_dashdist.bps`                               | `99acb686…`   |
| 6. Dash i-frames                | Uranus forward dash gains ~6 strike-invuln frames mid-move   | `tools/mkpatch6.py`                  | `build/sms_dashinvuln.bps` (+`.ips`)                   | `34c5d458…`   |
| 7. Pluto 5HP                   | Pluto 5HP hitbox extended down to hit crouchers (all but Chibi) | `tools/mkpatch7.py`                  | `build/sms_pluto5hp.bps`                               | `fc757936…`   |
| 8. Venus throw tech             | Venus 6HP throw mash-escape window 6f → 13f (standard-ish; Jupiter=15f) | `tools/mkpatch8.py`                  | `build/sms_venustech.bps`                              | `63ce0748…`   |
| 9. Neptune fireball           | Deep Submerge fireball hitbox tracks the descending sprite (was stuck at head level) | `tools/mkpatch9.py`                  | `build/sms_neptune_ds.bps`                             | `d5ee12a3…`   |
| 10. In-match combo counter     | Live combo-hit counter rendered by the base game under each attacker's bar (no overlay needed; 2026-07-25 fix: now also shows vs the CPU) | `tools/mkpatch10.py`                 | `build/sms_combocounter.bps`                           | `b819f3d4…`   |
| 10b. + status labels      | Counter + GC/REVERSAL/PUNISH/TECH event text (MEATY label removed 2026-07-20; 2026-07-25 fix: labels now expire correctly) | `tools/mkpatch10.py --events labels` | `build/sms_combolabels.bps`                            | `38faf40c…`   |
| 11. Training+  **(not fully tested)**                 | In-ROM training-mode upgrade: L+R menu, dummy control (pose/guard/wakeup/tech), recording+playback, damage/regen/refill, input+ADV display | `tools/mkpatch11.py`                 | `build/sms_trainingplus.bps`                           | `42add705…`   |
| 12. Taunts                      | Taunt on L: each character's native misfire ("ochame") pratfall, fully vulnerable | `tools/mkpatch12.py`                 | `build/sms_taunt.bps`                                  | `614f318e…`   |
| 13. Guts (Q-style taunts)          | Completing a taunt stacks levels (≤3) that reduce the opponent's SPECIAL/desperation damage vs you (20/40/60%, per-round; indicator in training only) | `tools/mkpatch13.py`                 | `build/sms_tauntbuff.bps`                              | `04e13428…`   |
| 14. Guts Grip **(companion to 13)** | The same Guts levels also reduce command-grab damage (SPDs/Giant Swing); inert without patch 13 | `tools/mkpatch14.py`                 | `build/sms_gutsgrip.bps`                               | `b90b8fd6…`   |

Combined builds (each applies to the clean ROM): `build/sms_allpatches_v0.22.bps` — all 14
patches (10 as 10b), ROM SHA-1 `52bc7e38…`, title tell "v.0.22"; `build/sms_reference_v1.bps`
— the **REF v.1** reference combination 1b+2+3+4+5+7+8+9+12+13+14 (true-combo gate, no
counter/training patches), ROM SHA-1 `bd1104ee…`, title tell "FrenchName REF v.1".
