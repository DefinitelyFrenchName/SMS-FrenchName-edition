# Next-session handoff — 2026-08-03

Fast orientation. **Full operational map: `HANDOFF.md`; Saturn brief:
`docs/saturn/PROJECT.md`; test-ROM registry: `docs/saturn/BUILDS.md`; patch
registry: `docs/patch_index.md`; engine subsystems:
`docs/sms_engine_internals.md`.** (The 2026-07-30 edition of this file, covering
the base patch project's review remediation, is in git history.)

## Status in one paragraph

The base patch project is done and green. Current work is **SMS + Saturn**:
Saturn is playable in SMS, selected by holding **L+R** on any character slot,
and has been field-tested repeatedly by the maintainer. Current builds are
**v0.13.2** (hashes in BUILDS.md) plus a stage-port variant, all on **REF v.2**
(= REF v.1 + patch 15, AUTO removal; v.1 is deliberately left byte-identical
since it is a published artifact). **Her voice is in** as of v0.13.0 — the last
step of task #44, field-confirmed; v0.13.1 added her **character-select line**
("Yoroshiku"); and v0.13.2 gives her **her own movelist** (#41). The only open
item is the **vertical scroll artefact** on the ported stage (#43) — plus a
listening/looking pass on the last two features, neither of which the maintainer
has seen in normal play yet.

## Voice — DONE (task #44 closed, plus the select line in v0.13.1)

**Field-confirmed** (2026-08-03): the in-match voices are "a bit weird but
definitely the right ones and not distracting". Polish is optional, not blocking.

**v0.13.1 adds her select line.** SMS already voices every sailor on confirm —
`$C0:AE4C` indexes a bank-id table (`$C0:AE75`, 21+charID) and a sound-id table
(`$C0:AE7F`), the bank being one BRR sample uploaded to ARAM `$B700`. All those
sound ids resolve to directory entry 48 (start `$B700`) and the sample ends on
its own end flag, so Saturn needed only the **bank id swapped** — no id change,
no directory patch. Her line came from Super S at ROM `$EC:C12F` (2610 bytes,
7984 Hz). Player identity is not in `$1B1E` (that is the CHARACTER, the
card-portrait trap again), so the three per-player writers of it record the
player in `$7F:F109`. Verified on two shells, both slots, and with nobody armed.

## Historical: the in-match voice work (v0.13.0)

Her four samples (win laugh, 236P, 214P, j.632K) load and play. The mechanism,
the corrections it forced, and the acceptance evidence are all in
**`docs/saturn/sound_scope.md` § PHASE 3**; the short version:

* SMS voices a fighter from a private ARAM bank (P1 `$B700`, P2 `$DB00`) **and**
  a per-character BRR directory that is resident from BOOT at
  `ARAM $34C0 + (charID-1)*32`. Loading her bank alone would have played her
  audio cut at the shell's sample offsets — the earlier scoping note that "no id
  remapping is needed" was right about the bank and wrong about the directory.
* She uses **char 1's** sound ids (49-52) whichever side she is on, and the build
  overwrites char 1's half-record for that player only. The two halves are per
  player, so this can never collide with a real Moon, and it needs **no
  per-shell code at all**.
* Non-Saturn loads restore char 1's record (DIRTY flag `$7F:F107/F108`) —
  without it a Saturn match would leave Moon buzzing until a power cycle.

**What is left for it:** listen. Everything is verified structurally (bytes,
addresses, directory entries, correct player — `probe_sms_voicecheck`,
`voicerestore`, `voicefire`, smoke 228/228, regression 57/57) and the samples
themselves were approved by ear earlier, but nobody has heard the cues *in play*.
Build `SATURN_HIDDEN=1 bash tools/saturn/build_refsaturn.sh`, summon her with
L+R, and check the win laugh and the three specials. `SATURN_VOICE=0` builds
without it if a comparison helps.

## Background: memory, and the shell design

`docs/saturn/memory_and_shell.md` answers "couldn't we just get more memory?" —
written 2026-08-03 at the maintainer's request. ROM is not our constraint (clean
2.50 MB, current build 3.62 MB, 384 KB spare); ARAM is the only hard wall (64 KB,
full — it forced the by-ear voice trim); and the real constraint is that
per-character tables are nine wide and immediately followed by live data, so a
tenth row means relocating a table and repointing every reader. Removing story
mode or moving to a 6 MB ExHiROM cartridge would buy ROM, which we already have,
and would break `file offset = SNES address & 0x3FFFFF` in the second case.

## Open items

**#41 movelist — DONE in v0.13.2.** She has her own list (SAILOR SATURN + her
three specials). It could not be lifted from Super S — that game has neither the
codec nor these tilemaps — so it is authored from SMS's own font and compressed
with `tools/saturn/sms_lz.py`. Full write-up, font tables and the acceptance
matrix: `docs/saturn/movelist.md`.

**#43 stage vertical slide — REPRODUCED, half-diagnosed. Resume here.**

A jump is now measurable (`probe_sms_stagejump.lua`) and shows the mechanism:
during a jump the vertical camera moves **BG1 alone** (vscroll 0 -> -1 -> -2 ->
-3) while BG2/BG3/BG4 stay flat at 0. On a vanilla stage that is invisible
because everything that must track the camera is on BG1 — but the port
deliberately re-cut the layers (moving the high-priority ground cells onto the
other tilemap to fix the palace occlusion), so on this stage the ground sits on a
plane that does not follow the camera.

**Do not call that the diagnosis yet.** That run is on scene `$00`, the pink
crystal stage — P1 = Pluto does NOT select stage 2, so stage choice is not simply
P1's character. **Next step:** force `$7E:008E` to the ported scene (the
documented way to summon a specific stage) and repeat the same measurement. If
BG1 moves and the plane holding the ground does not, the cause is confirmed and
the fix is to make that plane's vscroll follow BG1.

Three probe traps this cost, all now in the probe's header and
`docs/saturn/supers_assets.md`: `$01FA == $80` does not mean the pads work (the
entrance and the "GO!" banner come first — wait ~120 frames past neutral); BG
scroll registers are write-only so shadowing them captures nothing, and Mesen's
`emu.getState()` is a FLAT table with dotted keys (`ppu.layers[0].vscroll`); and
a nil inside a step function makes a probe print "done" having logged nothing,
which reads exactly like "the game did nothing".

## Lessons these sessions paid for

1. **Anything keyed to one character silently works for that shell only.**
   Saturn can be summoned over ANY of the nine. The card portrait was gated on
   *Uranus's* sprite-list pointer and was dead for every other shell — which
   presented as two apparently different bugs and cost several rounds of
   guessing. **Test any per-character fix with at least two shells.**
2. **"Nothing points at it and it never changes" does not mean memory is free.**
   The candidate ARAM region for extra samples passed exactly those two tests
   and was still live: a provenance check found its bytes in ROM bank `$E4`,
   uploaded by a path outside the audio table. On a console where everything is
   uploaded from ROM, **ask where the bytes came from** — cheap and decisive.
3. **Equal byte cuts are not equal proportional cuts.** Spreading a trim evenly
   over four samples looked better arithmetically and was worse by ear, because
   the shortest sample paid the largest proportion. Listening picked differently
   from the maths.
4. **A convention that holds in one engine context does not hold in all of
   them.** `$88` is the current object in the proc helper, so the voice hook
   copied `ldx $88` — but at script-interpretation time it holds whatever object
   last set it, and her voice came out of the opponent's slot. The interpreter
   already had the answer in X. Check where a value is *set*, not just where it
   is read successfully.
5. **A test that infers layout from ROM size breaks when the layout changes.**
   The smoke probe located her banks as `romsize - 9 * 0x10000`; a tenth bank
   turned every frame into a "mismatch" that looked like a ROM regression and was
   a probe bug. It now reads the bank out of the ROM (the interpreter's data-bank
   operand), which cannot drift.

## Build commands

```bash
tools/build_ref_v2.sh                                   # REF v.2 = v.1 + patch 15
SATURN_HIDDEN=1 python3 tools/saturn/mksaturn_smoke.py  # standalone Saturn (SATURN_VISIBLE=1 for the non-hidden variant)
SATURN_HIDDEN=1 bash tools/saturn/build_refsaturn.sh    # on REF v.2 (REF_VERSION=1 for v.1)
bash tools/saturn/build_saturn_stage.sh --ref           # Saturn + the Pluto-slot stage port, on REF
python3 tools/saturn/extract_saturn_voice.py            # her trimmed voice bank + directory
ROM=<rom> tools/run.sh tools/test_regression.lua 300    # the gate before shipping anything
```

## Session hygiene

Commit per finding; `.sfc` gitignored (rebuild from BPS); never patch in place;
every timing/behaviour claim emulator-verified (`ROM=<build> tools/run.sh
<script> <timeout>`); temp files in `$CLAUDE_JOB_DIR/tmp`; all Saturn/Super-S
material stays in the `saturn/` subfolders.
