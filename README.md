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

**Most people want one of the two reference builds in
[`release/`](release/RELEASE_NOTES.md).** Each is complete — you apply it and
play; nothing is stacked on top:

| | |
|---|---|
| **Rev. S-NN** | the reference build, no Super S content |
| **Rev. SS-NN** | the same, plus **Sailor Saturn** (hold L+R while confirming Uranus, Neptune or Pluto) |

`NN` is the revision, and it is printed on the title screen — quote it (or the
ROM SHA-1) in any bug report. Hashes and contents:
[`release/RELEASE_NOTES.md`](release/RELEASE_NOTES.md), which is generated from
the files themselves so it cannot go stale.

1. Obtain the clean ROM: *Bishoujo Senshi Sailor Moon S: Jougai Rantou!?* (SFC, Japan) —
   verify SHA-1 `bc0e29ee383574443226695215496eb0d09aaa1c`. ROMs are never distributed here.
2. Get [Floating IPS (flips)](https://github.com/Alcaro/Flips) (or any BPS patcher).
3. Apply a `.bps` to the clean ROM, e.g.
   `flips --apply release/Rev.SS-02.bps "<clean>.sfc" out.sfc`
4. Verify the output SHA-1 against [`release/RELEASE_NOTES.md`](release/RELEASE_NOTES.md).

The individual patches below stay in `build/` for anyone assembling their own
combination — see the warning in the release notes about chaining them.

Setting up (what the repo does not ship, and where to get it): [docs/project/toolchain.md](docs/project/toolchain.md) — then run `tools/health.sh`.

**Two of the game docs are readable in a browser, drawn:**

* [the data architecture](https://definitelyfrenchname.github.io/SMS-FrenchName-edition/)
  — memory maps, the object struct byte by byte, and the record formats the engine
  walks (`tools/mkarchpage.py`; as text,
  [docs/game/sms_data_architecture.md](docs/game/sms_data_architecture.md)).
* [one frame, as the cartridge runs it](https://definitelyfrenchname.github.io/SMS-FrenchName-edition/frame.html) — the in-match loop
  disassembled stage by stage, and every patch pinned to the stage it changes
  (`tools/mkenginepage.py`; as text, that file's §10B).

Docs come in two halves: **[docs/game/](docs/game/)** is analysis of the
**original ROM** — useful to anyone hacking this game, whatever they think of
this edition — and **[docs/project/](docs/project/)** is this edition's own
record.

Deeper docs: [docs/project/patch_index.md](docs/project/patch_index.md) (one-line registry, status,
lifecycle), [docs/project/patch_notes.md](docs/project/patch_notes.md) (per-patch mechanism + verification),
[HANDOFF.md](HANDOFF.md) (operational map: build, test, gotchas),
[docs/game/sms_engine_internals.md](docs/game/sms_engine_internals.md) (how the engine works),
[docs/game/sms_data_architecture.md](docs/game/sms_data_architecture.md) (where the data lives:
memory maps, the object struct, the record formats).
Training mode (pure Lua, no ROM patching): [docs/project/training_install.md](docs/project/training_install.md).

## Deliverables & how they stack

Target: Bishoujo Senshi Sailor Moon S: Jougai Rantou!? (SFC, Japan),
clean ROM SHA-1 `bc0e29ee383574443226695215496eb0d09aaa1c` (HiROM+FastROM, headerless,
file offset = SNES addr & 0x3FFFFF).

ROMs are never tracked in git. The tooling looks for them in `$SMS_ROM_DIR`, then
`roms/` inside the tree, then `../roms/` **above** the tree — the recommended spot, so
no ROM can end up in a commit.

| Patch **(located in build/ )**                             | What                                                         | Builder                              | Standalone BPS                                         | Patched SHA-1 |
| ---------------------------------------------------------- | ------------------------------------------------------------ | ------------------------------------ | ------------------------------------------------------ | ------------- |
| 1. 1f-meaty **(not true link)**                            | Uranus infinite → **1-frame meaty** (N=6): exactly one press connects, and it's an unblockable-by-block meaty (escapable by invincible reversal / jump) | `tools/mkpatch.py 0x04`              | `build/sms_uranus_infinite_1f.bps` (+`.ips`)           | `258ffd4e…`   |
| 1b. 1f-link **(true combo, use 1 OR 1b)**                  | **Alternative to patch 1** — true unblockable 1-frame combo (N=5); wider (2-frame connect: combo@0 + meaty@+1) | `tools/mkpatch.py 0x05`              | `build/sms_uranus_infinite_1f_truecombo.bps` (+`.ips`) | `deefccec…`   |
| 2. Dash-fix                                                | Remove reversal-dash invincibility                           | `tools/mkpatch2.py`                  | `build/sms_dashfix.bps` (+`.ips`)                      | `14f747a7…`   |
| 3. Sprint's Palettes                                       | Sprint / Big Zam extended character colors ( + "FrenchName" rom header for easy rom ID) | `tools/mkpatch3.py`                  | `build/sms_palettes.bps`                               | `291f6474…`   |
| 4. Title                                                   | Title subtitle → "FrenchName ver. X.Y" + copyright line 1 → "©MOONLIGHT FIGHT SOCIETY" | `tools/mkpatch4.py`                  | `build/sms_title.bps`                                  | `7f9e8c76…`   |
| 5. Dash dist                                               | Cut Uranus forward-dash distance ~1/3                        | `tools/mkpatch5.py`                  | `build/sms_dashdist.bps`                               | `99acb686…`   |
| 6. Dash i-frames                                           | Uranus forward dash gains ~6 strike-invuln frames mid-move   | `tools/mkpatch6.py`                  | `build/sms_dashinvuln.bps` (+`.ips`)                   | `34c5d458…`   |
| 7. Pluto 5HP                                               | Pluto 5HP hitbox extended down to hit crouchers (all but Chibi) | `tools/mkpatch7.py`                  | `build/sms_pluto5hp.bps`                               | `fc757936…`   |
| 8. Venus throw tech                                        | Venus 6HP throw mash-escape window 6f → 13f (standard-ish; Jupiter=15f) | `tools/mkpatch8.py`                  | `build/sms_venustech.bps`                              | `63ce0748…`   |
| 9. Neptune fireball                                        | Deep Submerge fireball hitbox tracks the descending sprite (was stuck at head level) | `tools/mkpatch9.py`                  | `build/sms_neptune_ds.bps`                             | `d5ee12a3…`   |
| 10. In-match combo counter (EXPERIMENTAL, not-recommended) | Live combo-hit counter rendered by the base game under each attacker's bar (no overlay needed; 2026-07-25 fix: now also shows vs the CPU) | `tools/mkpatch10.py`                 | `build/sms_combocounter.bps`                           | `be072a5e…`   |
| 10b. + status labels (**EXPERIMENTAL, not-recommended**)   | Counter + GC/REVERSAL/PUNISH/TECH event text (MEATY label removed 2026-07-20; 2026-07-25 fix: labels now expire correctly; 2026-08-06 fixes: labels now respect `--modes` so they stay off in Tournament, a repeated event now refreshes its label's lifetime, and the glyph font uploads lazily instead of every idle vblank) | `tools/mkpatch10.py --events labels` | `build/sms_combolabels.bps`                            | `745ea0bc…`   |
| 11. Training+ (**EXPERIMENTAL, not-recommended**)          | In-ROM training-mode upgrade: L+R menu, dummy control (pose/guard/wakeup/tech), recording+playback, damage/regen/refill, input+ADV display | `tools/mkpatch11.py`                 | `build/sms_trainingplus.bps`                           | `a3aba30d…`   |
| 12. Taunts                                                 | Taunt on L: each character's native misfire ("ochame") pratfall, fully vulnerable | `tools/mkpatch12.py`                 | `build/sms_taunt.bps`                                  | `614f318e…`   |
| 13. Guts (Q-style taunts)                                  | Completing a taunt stacks levels (≤3) that reduce the opponent's SPECIAL/desperation damage vs you (20/40/60%, per-round; indicator in training only) | `tools/mkpatch13.py`                 | `build/sms_tauntbuff.bps`                              | `bafb87d4…`   |
| 14. Guts Grip **(companion to 13)**                        | The same Guts levels also reduce command-grab damage (SPDs/Giant Swing); inert without patch 13 | `tools/mkpatch14.py`                 | `build/sms_gutsgrip.bps`                               | `5fadcaca…`   |
| 15. No AUTO                                                | Removes the AUTO option from the VS button-config screen (Auto binds specials to L/R, colliding with patch 12's taunt) | `tools/mkpatch15.py`                 | `build/sms_noauto.bps`                                 | `31832e6e…`   |
| 16. Menu translation **(EXPERIMENTAL, IN PROGRESS)**       | English menu text — a half-width A-Z built from the game's own capitals, then per-screen edits. Options, tournament select, report card, stage names, VS config, A.C.S. wheel and PLAYER SELECT are done behind build gates; the bracket VS names and the A.C.S. prompt are not. No BPS yet — see [docs/project/menu_text.md](docs/project/menu_text.md) | `tools/mkpatch16.py`                 | *(none yet)*                                           | —             |
| 18. No ACS in 2P VS                                        | Removes the A.C.S. stat-customisation screen from 2P VS only (companion to 15; story and vs-COM keep it) | `tools/mkpatch18.py`                 | `build/sms_noacs_vs.bps`                               | `67897bbf…`   |
| 17. All stages                                             | Unlocks the hidden tenth stage (なかよし編集部) in the stage select, and — where patch 3 is present — in its random default pool | `tools/mkpatch17.py`                 | `build/sms_allstages.bps`                              | `e5dd325b…`   |

Combined builds (each applies to the clean ROM): `build/sms_allpatches_v0.22.bps` — all 14
patches (10 as 10b), ROM SHA-1 `e6b999b5…`, title tell "v.0.22"; `build/sms_reference_v1.bps`
— the **REF v.1** reference combination 1b+2+3+4+5+7+8+9+12+13+14 (true-combo gate, no
counter/training patches), ROM SHA-1 `2873f214…`, title tell "FrenchName REF v.1";
`build/sms_reference_v2.bps` — **REF v.2** = REF v.1 + patch 15 (No AUTO), ROM SHA-1
`6d79fb5f…`, title tell "FrenchName REF v.2", recipe `tools/build_ref_v2.sh` — this is the
default base for the Saturn build (`tools/saturn/build_refsaturn.sh`).
v0.22 and REF v.1 rebuilt 2026-07-30 with the patch-4 "©MOONLIGHT FIGHT SOCIETY" credit line
(the visible tell vs the pre-credit builds `52bc7e38…` / `bd1104ee…`).
`build/sms_ref_v2_allstages.bps` = REF v.2 + patch 17, ROM SHA-1 `e8fc6045…`.

**Sailor Saturn** (ported from *Sailor Moon Super S*) is the 100-series and is built
by `tools/saturn/`, not by a `mkpatchN.py` — she rides in **Rev. SS** only. Her patches
are deliberately **not** tracked as `.bps`, because they embed ported game content;
rebuild from source (`tools/saturn/build_refsaturn.sh`, gate
`tools/saturn/verify_saturn.sh`). Detail: [docs/project/saturn/BUILDS.md](docs/project/saturn/BUILDS.md).
