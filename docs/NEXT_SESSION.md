# Next-session handoff — 2026-08-03 (field round)

Fast orientation. **Full operational map: `HANDOFF.md`; Saturn brief:
`docs/saturn/PROJECT.md`; test-ROM registry: `docs/saturn/BUILDS.md`; patch
registry: `docs/patch_index.md`; engine subsystems:
`docs/sms_engine_internals.md`.** (Earlier editions of this file are in git
history.)

## Status in one paragraph

The base patch project is done and green. Current work is **SMS + Saturn**:
Saturn is playable in SMS, selected by holding **L+R** on any character slot.
Current build is **v0.14.4**
(`SailorMoonS_REFsaturn_v0.14.4-hidden-stage.sfc`, `8d2d33be…`, regression
57/57) on **REF v.2**. It is **behaviourally identical to v0.14.3** — a 4-byte
diff, the checksum and one version-string character — so there is nothing new to
field-test in it; what it carries is the investigation below. Everything the
project set out to build exists (voice, select line, movelist, the ported stage
and its kanji name, and she now arrives before the round starts), but the
2026-08-03 field round opened **three bugs, none fixed yet**. Fix those first.

## THE THREE OPEN BUGS (field, v0.14.3)

Field verdict: training **good**, 1P-vs-COM **good**, and:

**1. Throw corruption — the important one, and NOT caused by this session's
work (it predates it).** When Saturn is thrown her sprite becomes random tiles;
thrown by a COMMAND throw (Jupiter SPD+P) the corruption spreads into the stage
tiles. **Reproduced headlessly**: `probe_sms_throwbug.lua` (practice, Saturn as
the dummy, P1 throws her). What it shows: acts `1C→1D→1E→20` run normally, her
cels DO stream (banks `$F3/$F4`, plausible lengths), stage-tile VRAM is
untouched for a *normal* throw (0/128 samples), and her downed sprite is still
drawn from tiles that are not hers — another character's hair is visible in it.

*Ruled out, so do not re-walk these:* cel-record validity (115 records, banks all
rebased, no oversize, only record 0 zero-size); cel sizes (her max `0x900` vs
SMS's own `0x9a0`); dropped act-table entries (none); missing cel DMA; and the
blank-cel size theory — poses `$7E-$83` do use the sentinel and it was only
`0x480` against a `0x900` max payload, but enlarging it changed nothing, so that
change was reverted rather than shipped unproven. Also: the `+0x18` byte reads
`$F8` during the throw, which looks like an out-of-range pose index and is not —
it is the pose-record CLASS, and no SMS character's pose table reaches `$F8`.

*Where to look next:* the OAM sprite-layout layer (the `$84:8000` system) for the
victim poses, and how SMS draws a thrown victim at all — if the thrower's
animation supplies the victim's tiles, a ported character would show the
thrower's.

**2. 2P VS: the shell is not replaced, though her sfx play.** So the flag/latch
arms (the sound remap keys off it) but the transform does not. Not reproduced —
the harness's "vscpu" flow is mode `$8D=00` and transforms correctly, so the
failing case is specifically **two human players**, which no probe covers. A
two-pad VS flow is the first thing to build.

**3. Saturn is still reachable in story mode.** The `$8D == 1` guard (v0.14.2)
does not hold in the field. The maintainer's fallback is the right one: **arm
only on Uranus/Neptune/Pluto shells** (charID 6/7/8), the three story cannot
select. It is implemented behind `SHELL_GUARD` but **defaults OFF because it does
not work yet**: in the DMA stub nothing arms at all (the player struct is not
populated at the effects transfer), and in the helper — where the neighbouring
`lda $01,x` for the act demonstrably works — it blocks *every* shell including
6/7/8. Unexplained. **Next step is one measurement:** log `$00,x` at the helper's
gates and see what the id actually reads there.

Forcing Saturn into story (pre-guard) is confirmed bad by the field: graphical
corruption, unresponsiveness at the stage start, broken framing. So blocking her
there is the goal, not a compromise.

## The font is now writable — which unblocks the translation patch

Done in v0.14.0, and the reusable part: the menu font is **two compressed
blocks** (same codec as the movelists) — `$C3:48D0` (kana, general) and
`$C7:07F0` (**kanji**, tiles based at 0x300). The job table at `$C3:BEE0`+ holds
`[src24][dest24][…][flag]` records; the kanji block's source is the only
`F0 07 C7` in the ROM, at `$C3:BEF2`.

Two things to know before touching it:

* **Relocate, never patch in place.** Our encoder is weaker than the original's:
  even the *untouched* kanji block re-encodes to 0x13AD against the original
  0xD5B. `mkkanji.py` decompresses, inserts glyphs, re-encodes, appends to the
  port's bank and rewrites the three pointer bytes.
* **The decompressor's documented entry `$C0:916B` is not the one this path
  uses** — a hook there never fires. Hook the loop setup at **`$C0:91A0`**, where
  the source pointer is still at the start.

`mkkanji.py` renders glyphs from Hiragino at 16x16 and styles them like the
game's own kanji (colour-1 outline, interior vertical ramp). 16 blank slots
remain. **Patch 16 (menu translation) needs exactly this** to add F, J, Q, S, Z.

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
   reduced Latin alphabet. **No longer blocked** — the font path above is the
   missing piece it needed.
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
bash tools/saturn/build_saturn_stage.sh --ref           # + the stage port  <- v0.14.4
SUPERS_SCENE=9 STAGE_NAME=… python3 tools/saturn/mkstage_port.py "$CLEAN" out.sfc
ROM=<rom> tools/run.sh tools/test_regression.lua 900    # the gate before shipping
```

## Session hygiene

Commit per finding; `.sfc` gitignored (rebuild from BPS); never patch in place;
every timing/behaviour claim emulator-verified; temp files in `$CLAUDE_JOB_DIR/tmp`;
all Saturn/Super-S material stays in the `saturn/` subfolders.
