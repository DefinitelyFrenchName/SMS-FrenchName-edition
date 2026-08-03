# Next-session handoff — 2026-08-03 (evening)

Fast orientation. **Full operational map: `HANDOFF.md`; Saturn brief:
`docs/saturn/PROJECT.md`; test-ROM registry: `docs/saturn/BUILDS.md`; patch
registry: `docs/patch_index.md`; engine subsystems:
`docs/sms_engine_internals.md`.** (Earlier editions of this file are in git
history.)

## Status in one paragraph

The base patch project is done and green. Current work is **SMS + Saturn**:
Saturn is playable in SMS, selected by holding **L+R** on any character slot,
and has been field-tested repeatedly by the maintainer. Current build is
**v0.13.3** (hashes in BUILDS.md), on **REF v.2** (= REF v.1 + patch 15, AUTO
removal; v.1 is deliberately left byte-identical since it is a published
artifact). **Every bug on the list is now closed**: her voice (#44), her
character-select line, her movelist (#41 — field-confirmed clean this session)
and the ported stage's jump slide (#43 — root-caused and fixed this session).
What remains is the **extended scope** the maintainer set out below.

## Field verification received 2026-08-03

- **Movelist is clean** in normal play. The priority-bit fix holds on a real
  screen; #41 is closed for good.
- **Select voice: no regression.** The bank-id swap behaves, other characters
  unaffected.

## #43 — DONE this session

The ported stage's jump slide is fixed in **v0.13.3**. One-paragraph version:
objects are drawn at the FULL camera, but the scroll routine the port borrowed
from stage 0 gives the ground plane only **camera/4** — so a 12 px jump drops the
fighters and their shadows 12 px and the ground 3. Vanilla stage 0 does exactly
the same thing (byte-identical traces); it is invisible there because its ground
is flat grass, while the ported stage has a hard floor line at the fighters'
feet. The fix rewrites stage 2's own routine at `$C0:B454` (the only routine that
stage selects) with a 1:1 vertical. Verified: background shift +3 → +11, equal to
the sprites'; scene `$00` byte-identical on the same ROM; regression 57/57. Full
detail, including the scroll-block map and the five probe traps it cost:
`docs/saturn/supers_assets.md` §#43.

**Deliberately left open:** the horizontal rate has the same shape (the ground
moves at camera/4 while walking, so fighters slide over it horizontally too).
Also vanilla, not in the field report, and one `lsr` pair from 1:1 — the
maintainer's call, measurement is in §#43.

## Extended scope (maintainer, 2026-08-03) — the actual next work

Recorded in full in `docs/saturn/PROJECT.md` § Extended scope. Neither blocks a
release; Saturn is a hidden character of admittedly rough balance, which is
precisely why she ships without them.

1. **Menu translation (minor).** Partial or complete translation of menu text.
   Some of it reportedly exists in the tournament edition — look there first
   rather than authoring from scratch. The tooling is in place: SMS's font tables
   and the `$C0:916B` codec were decoded and made re-encodable for the movelist
   (`tools/saturn/sms_lz.py`, `mkmovelist.py`, `docs/saturn/movelist.md`).
2. **Show Saturn EARLIER in the fight (major, not a blocker).** Today the shell
   is swapped for Saturn at the round load, so her player watches someone else
   through the pre-round sequence. The maintainer: the change moment is
   *distracting and downright penalizing* for the player who picked her.
   - **Must have:** Saturn on screen **before round start**.
   - **Nice to have:** the entrance animation preserved as hers.
   Known hazard, so this is a re-timing job rather than a new mechanism: arming
   the transform earlier is exactly what the per-round latches were introduced to
   prevent (BUILDS 0.10.0 — a flag set before load could reach the helper during
   the load/dialogue window). Find the earliest point where her four data layers
   and effect tiles are resident and the object struct is stable, and move the
   swap there.

## Background: memory, and the shell design

`docs/saturn/memory_and_shell.md` answers "couldn't we just get more memory?" —
ROM is not our constraint (clean 2.50 MB, current build 3.62 MB, 384 KB spare);
ARAM is the only hard wall (64 KB, full — it forced the by-ear voice trim); and
the real constraint is that per-character tables are nine wide and immediately
followed by live data, so a tenth row means relocating a table and repointing
every reader. This is directly relevant to scope item 2: the swap-at-load design
exists because she is a shell, not a tenth character.

## Lessons these sessions paid for

1. **Anything keyed to one character silently works for that shell only.**
   Saturn can be summoned over ANY of the nine. Test any per-character fix with
   at least two shells.
2. **"Nothing points at it and it never changes" does not mean memory is free.**
   Ask where the bytes came from; on this console everything is uploaded from ROM.
3. **Equal byte cuts are not equal proportional cuts.** Listening picked
   differently from the arithmetic when trimming her voice samples.
4. **A convention that holds in one engine context does not hold in all of them.**
   `$88` is the current object in the proc helper but not during script
   interpretation. Check where a value is *set*, not just where it reads fine.
5. **A test that infers layout from ROM size breaks when the layout changes.**
6. **Do not measure a moving character against a moving background by pixel
   correlation** (new, #43). The dummy's idle bob is worth ±8 px of apparent
   shift and nearly buried the diagnosis. Take it from OAM with the animation
   state held equal.
7. **The layer that fails to track is not always the one that was re-cut** (new,
   #43). The prior hypothesis blamed the port's layer re-cut; the ground was on
   the right plane all along and the fault was the *rate*.

## Build commands

```bash
tools/build_ref_v2.sh                                   # REF v.2 = v.1 + patch 15
SATURN_HIDDEN=1 python3 tools/saturn/mksaturn_smoke.py  # standalone Saturn (SATURN_VISIBLE=1 for the non-hidden variant)
SATURN_HIDDEN=1 bash tools/saturn/build_refsaturn.sh    # on REF v.2 (REF_VERSION=1 for v.1)
bash tools/saturn/build_saturn_stage.sh --ref           # Saturn + the Pluto-slot stage port, on REF  <- v0.13.3
python3 tools/saturn/extract_saturn_voice.py            # her trimmed voice bank + directory
ROM=<rom> tools/run.sh tools/test_regression.lua 900    # the gate before shipping anything
STAGE=2 CHAR=8 TAG=x ROM=<rom> tools/run.sh tools/saturn/probe_sms_stagejump.lua 400   # stage scroll/camera (WALK=1 for the horizontal axis)
```

## Session hygiene

Commit per finding; `.sfc` gitignored (rebuild from BPS); never patch in place;
every timing/behaviour claim emulator-verified (`ROM=<build> tools/run.sh
<script> <timeout>`); temp files in `$CLAUDE_JOB_DIR/tmp`; all Saturn/Super-S
material stays in the `saturn/` subfolders.
