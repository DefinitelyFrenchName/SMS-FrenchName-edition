# Next-session handoff — 2026-08-03 (late)

Fast orientation. **Full operational map: `HANDOFF.md`; Saturn brief:
`docs/saturn/PROJECT.md`; test-ROM registry: `docs/saturn/BUILDS.md`; patch
registry: `docs/patch_index.md`; engine subsystems:
`docs/sms_engine_internals.md`.** (Earlier editions of this file are in git
history.)

## Status in one paragraph

The base patch project is done and green. Current work is **SMS + Saturn**:
Saturn is playable in SMS, selected by holding **L+R** on any character slot,
field-tested repeatedly. Current build is **v0.13.9**
(`SailorMoonS_REFsaturn_v0.13.9-hidden-stage.sfc`, `a63f7a06…`, regression
57/57) on **REF v.2**. Everything on the bug list is closed and
field-confirmed: her voice, her character-select line, her movelist, the ported
stage (#43), and the stage's name. What remains is **one small task** (four font
glyphs) plus the maintainer's **extended scope**.

## THE ONE OPEN TASK: four kanji

The ported stage is currently named **サイレントメシア** — a proof-of-concept
written with glyphs the font already has, confirmed on the pad ("reads correctly
and cause no side effect I could trigger"). The intended name is
**沈黙のメシアの玉座**, which needs four characters the font lacks: **沈, 黙, 玉,
座** (の, メ, シ, ア exist).

Everything except the glyphs is done and proven:

* `mkstage_port.py` writes stage names — `STAGE_NAME` (env-overridable) plus a
  `GLYPH` table of tile codes. It refuses a character the font lacks rather than
  drawing a wrong one, so it will error on those four until they exist.
* The name field holds **12 glyphs**; 沈黙のメシアの玉座 is 9.
* The font sheet has **20 free 16×16 slots**, four of them (`$368`-`$36E`) right
  after the existing kanji.

**The missing link:** where the menu font comes from. It is not raw in ROM and
not DMA'd from ROM — logging every VRAM DMA from boot shows the CHR arriving in
0x40-byte chunks from a **WRAM staging buffer at `$7E:3640`+**. So the chain is
`ROM → (decompress) → $7E:3640 → VRAM`, and the open question is what fills that
buffer. Catch the block move or decompressor call that writes it — the same hunt
that found `$C3:7C00` for the screen's tilemap. `probe_menu_survey.lua` takes
`MINLEN` to filter the DMA log to large transfers.

Two things to check first, both cheap:

1. The **tournament edition**'s 7.3 KB diff is in bank `$C4` — the same bank as
   the name records. If it renamed stages, it is a worked example of this exact
   edit, and possibly of extending the font.
2. Extending the font is **shared work with the translation patch** (planned
   patch 16), which needs F, J, Q, S, Z for English. Solve it once.

## Where the stage work landed

`docs/saturn/supers_assets.md` §#43 has the full account. Short version, because
it cost four rounds and the lesson generalises: **read the game's own data before
reasoning about its limits.** SMS ships its own Silver Millennium (scene 1) and
composes it exactly like Super S; the port had simply never carried the scene
script's `$8F` byte, which sets sprite OBJ priority — `0x18` on nine of ten
stages, `0x10` on stage 2 alone, the slot the port targets. That one byte is why
the castle covered the fighters, why priority bits got stripped, and why every
"clever" fix after that was working around a missing configuration byte. The
port now carries `$8F` and picks a stock scroll routine per source scene; the
merges, plane splits, tile compositing and rewritten scroll code are all deleted.

Decisions recorded: stages are **swapped, not added** (the scene table is exactly
10 entries with the scripts immediately after it; the maintainer: "adding them is
like adding characters"). The space-time door is the slot;
**Silent Throne of the Messiah** (Super S scene 8) takes it; its BGM stays the
space-time door's. `SUPERS_SCENE` defaults to 8. The other three candidates
(Silver Millennium 1, Dead Moon day 0, Dead Moon night 9) are one env var away
and their ROMs are in `build/saturn/stagecandidate_*.sfc`.

## Extended scope (maintainer, 2026-08-03)

1. **Menu translation — standalone patch 16, not a Saturn feature.** Groundwork
   in `docs/menu_text.md`, including the screen's compressed tilemap at
   `$C3:7C00` (the movelist codec, `sms_lz.py` round-trips it) and the font's
   reduced Latin alphabet. Blocked on the same font question as the kanji above.
2. **Show Saturn BEFORE round start** instead of swapping the shell at the round
   load — "distracting and downright penalizing" for her player. Entrance
   animation is nice-to-have. Hazard: arming the transform earlier is what the
   per-round latches were introduced to prevent.

## Lessons this run paid for

1. **Read the game's own data first.** Every question about the ported stage —
   layer split, priority, scroll rates, sprite priority — was answerable by
   dumping SMS's own copy of that stage.
2. **A run of zeros after a string is not a terminator.** The stage-name records
   are fixed 24-word fields with the name *centred* by zero padding. Reading it
   as terminated made a longer name overrun into the next record, corrupting the
   screen and hanging the game a second after the stage was selected. Comparing
   two records would have shown it at once.
3. **A 64×32 tilemap is TWO 32×32 screens** (right half at +0x800), not 64-entry
   rows. Reading it wrong made three analyses contradict each other.
4. **Don't measure a moving character against a moving background by pixel
   correlation** — the dummy's idle bob is worth ±8 px. Take it from OAM with the
   animation state held equal.

## Build commands

```bash
tools/build_ref_v2.sh                                   # REF v.2 = v.1 + patch 15
SATURN_HIDDEN=1 bash tools/saturn/build_refsaturn.sh    # Saturn on REF v.2
bash tools/saturn/build_saturn_stage.sh --ref           # + the stage port  <- v0.13.9
SUPERS_SCENE=9 STAGE_NAME=… python3 tools/saturn/mkstage_port.py "$CLEAN" out.sfc
ROM=<rom> tools/run.sh tools/test_regression.lua 900    # the gate before shipping
```

## Session hygiene

Commit per finding; `.sfc` gitignored (rebuild from BPS); never patch in place;
every timing/behaviour claim emulator-verified; temp files in `$CLAUDE_JOB_DIR/tmp`;
all Saturn/Super-S material stays in the `saturn/` subfolders.
