# Next-session handoff — 2026-08-03 (field round; all three bugs closed)

Fast orientation. **Full operational map: `HANDOFF.md`; Saturn brief:
`docs/saturn/PROJECT.md`; test-ROM registry: `docs/saturn/BUILDS.md`; patch
registry: `docs/patch_index.md`; engine subsystems:
`docs/sms_engine_internals.md`.** (Earlier editions of this file are in git
history.)

## Status in one paragraph

The base patch project is done and green. Current work is **SMS + Saturn**:
Saturn is playable in SMS, selected by holding **L+R** on a **Uranus, Neptune or
Pluto** slot (that restriction is the story lock). Current build is **v0.14.8**
(`SailorMoonS_REFsaturn_v0.14.8-hidden-stage.sfc`, `3ea03a21…`, regression
57/57) on **REF v.2**. Everything the project set out to build exists, **all
three field bugs from 2026-08-03 are fixed**, and the follow-up side effect the
maintainer found on v0.14.7 (L+R on a disallowed shell still armed her sfx and
palette) is fixed too. No known open bugs; what remains is the extended scope.

**Where the shell restriction lives now, and why it moved.** v0.14.5 put it in
the helper — at the transform. But the **flag** is set earlier, by the
char-select confirm stub, and the select voice, the in-match sound remap and the
effect-tile/palette override in the DMA stub all key off the **flag**, not the
transform. So a disallowed shell armed everything except the one thing that was
guarded: no Saturn, but her confirm sfx, her palette on most tiles and her sfx.
v0.14.8 applies the rule **where the flag is armed**:

* the confirm stub reads the cursor's charID (`$0000,y`) and only sets the flag
  for 6/7/8;
* it records the confirmed charID per player in `$7F:F10A/F10B`, so the other
  arming route — L+R held as the round loads, where the cursor is gone and the
  player struct is not yet populated — applies the same test in the DMA stub,
  failing closed on a stale value;
* the helper guard stays as the last line.

The generalisable bit: **guard the thing that arms, not the thing that acts.**
A feature with several consumers keyed off one flag is only as gated as that
flag. `probe_sms_shellguard.lua` now reports flag/latch alongside the transform,
so "not Saturn but armed" can no longer read as a pass.

## The mode byte was wrong, and it caused two of the three bugs

`$7E:008D` is **0 = story, 1 = 2P VS, 2 = 1P-vs-COM, 4/5 = training**. Measured
from the game (`probe_sms_menurows.lua`) by two independent discriminators per
menu row — how many cursors move, and which charIDs each can reach:

| row | `$8D` | cursors | roster | mode |
|---|---|---|---|---|
| 0 | 00 | one | 1–5 only | **story** |
| 1 | 01 | two, independent | full 1–8 | **2P VS** |
| 2 | 02 | one + fixed opponent | full | 1P vs COM |
| 4 | 04 | one + dummy (P1 confirms both) | full | practice |

`docs/annotations.md` carried both readings — "0=VS, 1=Story" (from the training
Lua, **wrong**) and "VS 1P-vs-2P = 01" (right) — and the story guard was written
against the wrong one. So `$8D == 1` blocked **2P VS** and never touched story.
Both entries are now corrected, in `annotations.md` and `sms_engine_internals.md`.

## THE BUGS (field, v0.14.3) — all three closed

Field verdict: training **good**, 1P-vs-COM **good**, and:

**1. Throw corruption — FIXED in v0.14.7. A third nine-wide table.**
When a character is thrown, the THROWER's script drives the VICTIM's pose:
`jsr $C1:03DC` returns the *other* object's base, so `$0E` is the victim's
charID, and `$0E*2` indexes a pointer table at **`$C1:0881`** — ten entries,
1-indexed, idx 1–9 being the nine characters' 21-byte pose lists. Saturn is id
**`0x1C`**, so the read lands 0x38 bytes past the table, inside character 2's
pose data, and the "list pointer" is two bytes of pose values.

The chain from there, all measured: garbage poses (**`$F6`**, against her
table's last real pose `$83`) → an out-of-range index into her pose→spritelist
table in the OAM layer, whose first byte is a sprite **COUNT** → the emitter
writes **102 identical sprites and floods OAM**. That is the "random tiles".

Fix: hook the list read at both sites (`$C1:0740` normal, `$C1:0C5C`
command/carry — byte-identical in shape) and, for victim id `0x1C` only, read
her own list. Her list is **lifted, not authored**: Super S's twin table at
`$C1:0883` has ELEVEN entries and idx 10 is hers, and the nine shared lists are
**byte-identical across the games** — which is what proves the step semantics
match and justifies lifting.

A/B on the same throw (`probe_sms_throwoam.lua`, dummy as Saturn vs as the plain
shell):

| build | Saturn's poses | max sprites |
|---|---|---|
| v0.14.6 | `95 / 78 / 46 / F6` | **127 — OAM flood** |
| v0.14.7 | `73 / 74 / 75 / 6F / 70` | 57 (vanilla: 60) |

Those are list indices 12/13/14/8/9 — exactly the indices vanilla uses into its
own list. Stage-tile VRAM 0% changed; regression 57/57 including the two SPD
command-throw tests.

**The command throw is verified too (v0.14.8).** The harness could not land
Jupiter's SPD until the maintainer gave the minimum input: **6 2 4 8 + P**, with
the 8 and the P allowed on the same frame, at **contact** range (the regression
suite's longer `6321478` does come out, but its up-steps make him jump and it
always whiffed). That confirms `$C1:0C5C` is the command/carry site
(`site1=0 site2=136`) and reproduces the worse field symptom:

| build | Saturn's poses (SPD) | max sprites | stage-tile VRAM |
|---|---|---|---|
| v0.14.6 | `20 / E2 / 17 / C2` | **127 — flood** | **92% changed** |
| v0.14.8 | `02 / 01 / 07 / 76` | 51 (vanilla 55) | 0% |

Uranus's SPD is the same motion with K.

*Two bugs paid for on the way, both caught by the A/B rather than by reasoning:*
a `plb` inside a JSL'd stub pops the **return address**, not the saved DB (it
stalled every throw, vanilla victims included — the vanilla arm of the A/B is
what exposed it); and **`lda long,Y` does not exist on the 65816** — `$BF` is
long,**X**, so the read indexed with the thrower's object base and returned her
list[0] every frame.

**2. 2P VS: the shell is not replaced, though her sfx play — FIXED in v0.14.6.**
Root cause: the story guard's `$8D == 1` test *is* 2P VS (see the mode-byte
section above), so the DMA stub force-cleared the latch and the helper was never
reached. The flag itself is set earlier, by the char-select confirm hook — and
the sound remap and the select voice both key off the flag, not the latch, which
is exactly why her sfx and her confirm sfx played over an untransformed shell.
Fix = one byte, `cmp #$01` → `cmp #$00`.

Reproduced headlessly for the first time by `probe_sms_shellguard.lua MODE=vs`,
which drives a **real two-pad VS** — P1 and P2 each confirm with their own pad,
which no earlier probe did (they drove pad 1 and poked the second cursor). On
v0.14.5 it reports `gate_hits=0`: the helper never runs at all. On v0.14.6, with
P1 on Uranus and P2 on Neptune: L+R on P1 → P1 only, on P2 → P2 only, on both →
a Saturn mirror.

**3. Saturn reachable in story mode — FIXED in v0.14.5, residual closed in
v0.14.6.** The `$8D == 1` guard (v0.14.2) did not hold in the field — now known
to be because it was testing 2P VS, not story. The maintainer's fallback is now the lock:
**arm only on Uranus/Neptune/Pluto shells** (charID 6/7/8), the three story
cannot select. `SHELL_GUARD` **defaults ON**.

The previous session's "it blocks every shell including 6/7/8" was a **harness
artifact, not a code fault**. The one measurement it asked for
(`tools/saturn/probe_sms_shellguard.lua`, an exec hook on the guard's own
`lda $00,x`) shows D=0, X=`$1000`/`$1080`, and `$00,x` reading the true shell —
`06` for a Uranus shell, `04` for a Jupiter one. The guard always read the right
byte; the *flow* that "selected 6" was loading charID **1**, because it pokes
`$1B40` once and then mashes A/Start through a second selection screen that
reuses that cursor. The probe now holds the poke for the whole load.

Measured on the shipping v0.14.6 stage build (modes named from the corrected
map — the v0.14.5 notes used the old, swapped names):

| flow | shell 6 / 7 / 8 | shell 1 / 4 |
|---|---|---|
| 2P VS | transforms | refused |
| 1P vs COM | transforms | refused |
| practice | transforms | refused |
| story | refused | refused |

plus story with charID 6 **forced** in (`STORY_SHELL=1`, a `$1B40` poke the UI
cannot produce): refused, `gate_hits=0`.

Why the shell test is the deeper lock and not a workaround: on a build with
`STORY_GUARD=0` the latch still **arms** and the helper still runs every frame,
and the guard refuses all of it — story simply has no outer senshi to arm on, so
the lock never has to ask what mode the game thinks it is in. `STORY_GUARD` is
kept as a second layer, and since v0.14.6 it tests the right mode, which is what
closes the forced-charID-6 residual the shell test cannot see.

Forcing Saturn into story (pre-guard) is confirmed bad by the field: graphical
corruption, unresponsiveness at the stage start, broken framing. So blocking her
there is the goal, not a compromise.

*Side finding, not a bug:* in practice, P1 confirms BOTH cursors, so holding L+R
through both confirms arms both players (writer `$F6:C265`, the confirm stub,
which arms per cursor by design). With a Uranus dummy that gives a Saturn
mirror — useful, and it is how you get a Saturn dummy to train against.

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
5. **Assert the precondition before believing the verdict.** "SHELL_GUARD blocks
   6/7/8" was three sessions of an unexplained result, and the explanation was
   that the harness never selected 6/7/8 in the first place. A probe that reports
   a feature refusing *everything* is usually not testing what it thinks it
   selected — check `$1000` against the shell you asked for before drawing a
   conclusion, and when a byte's value is in doubt, hook the instruction that
   reads it rather than reasoning about it.
6. **When a doc contradicts itself, stop and measure — do not pick a side.**
   `annotations.md` said both "0=VS, 1=Story" and "VS 1P-vs-2P = 01". A guard was
   written against the wrong one and produced two field bugs that looked
   unrelated for a week. The measurement that settled it took one probe and ten
   minutes, and it works by finding a discriminator the game itself exposes
   (cursor count and reachable roster), not by trusting any label.
7. **A/B against the vanilla path, always.** Both bugs introduced while fixing
   the throw were invisible in the Saturn arm alone and obvious in the vanilla
   one: a stalled throw looked like "the fix worked, no flood" until the vanilla
   dummy stalled identically. An A/B harness is not a nicety here; it is the only
   thing that distinguishes "fixed" from "broken in a quieter way".
8. **Check the addressing mode exists before assuming symmetry.** `lda long,X`
   exists; `lda long,Y` does not. The assembled `$BF` silently indexed with the
   wrong register and returned a plausible-looking constant.
9. **"Is this slot zero?" does not mean "is this slot free."** The first stub
   slot passed a zero-check at emission and was overwritten later in the same
   bank build, so the hook jumped into data. Read the bytes back out of the
   ASSEMBLED image — that tripwire is now in the builder.
10. **Name harness modes after what you measured, not what you assumed.** The
   probes' "vscpu" mode was story and their "story" mode was 2P VS, so a correct
   result was filed under the wrong heading and a real bug hid behind a passing
   test. Mode names in `probe_sms_shellguard.lua` now come from the measured
   row→mode map.

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
