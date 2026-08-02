# Next-session handoff — 2026-08-02

Fast orientation. **Full operational map: `HANDOFF.md`; Saturn brief:
`docs/saturn/PROJECT.md`; test-ROM registry: `docs/saturn/BUILDS.md`; patch
registry: `docs/patch_index.md`; engine subsystems:
`docs/sms_engine_internals.md`.** (The 2026-07-30 edition of this file, covering
the base patch project's review remediation, is in git history.)

## Status in one paragraph

The base patch project is done and green. Current work is **SMS + Saturn**:
Saturn is playable in SMS, selected by holding **L+R** on any character slot,
and has been field-tested repeatedly by the maintainer. Current builds are
**v0.12.7** (hashes in BUILDS.md) plus a stage-port variant, all on **REF v.2** —
REF v.1 **+ patch 15 (AUTO removal)**, folded in this session at the
maintainer's request; **v.1 is deliberately left byte-identical** since it is a
published artifact. Three items are open: her **movelist** (#41), a **vertical
scroll artefact** on the ported stage (#43), and the **voice-sample injection**
(#44) — the one with momentum.

## Where the sound work stands (task #44) — resume here

Everything except the plumbing is done, verified and approved.

**Decided and built.** Her four sounds (win laugh, 236P, 214P, j.632K) are
extracted from the Super S ROM by `tools/saturn/extract_saturn_voice.py`, with
52 ms trimmed off each of the three PROJECTILES and the laugh untouched —
chosen by the maintainer after A/B listening. Output: `saturn_voice.brr`
(9198 bytes for ARAM `$B700`, 18 spare of a 9216 budget) and `saturn_voice.dir`
(four directory entries for ARAM `$3500`). The extractor works from the ROM,
not from a trace dump: the ARAM→ROM mapping is linear, **file offset = ARAM +
`0x2EE17F`**, verified on all four samples.

**Playback rate: settled at ~8 kHz, no resampling needed** — the maintainer
confirmed SMS's own Uranus voices sound correct at that rate, so both games
voice alike.

**What remains — three steps, in order:**

1. **Append her bank.** An IPL block `[size16][dest16=$B700][data…]` plus a
   zero-size terminator carrying entry point `$0800`, in an appended bank, and a
   new record in the table at **`$C0:ECE7`** — entries 31-38 are the existing
   per-character voice banks and **entry 40 onward is zeros**, so an entry can
   be appended without moving anything.
2. **Redirect the bank** to hers when the Saturn flag is set, for whichever
   player she is on. Structurally identical to the card-portrait redirect.
3. **Her directory entries at ARAM `$3500`** — the least understood piece. The
   layout is known (entries 0-3 describe P1's `$B700` region, 4-7 describe P2's
   `$DB00`; 8-15 are a second set over the same regions) but *what writes it per
   match* is not, so her sample sizes may need injecting rather than just her
   samples.

Sounds are triggered per player by id (`$C0:D4F5` sends P1's `+0x78` to APU port
0, P2's to port 1, the global one-shot `$78` to port 2) and the SPC resolves
each id against **that player's** resident bank — so once her bank is loaded for
her player she keeps the same ids and simply speaks in her own voice. **No id
remapping is needed.** Full detail, including what was ruled out and why:
**`docs/saturn/sound_scope.md`**.

## The other two open items

**#41 movelist.** Shows mostly Uranus's list and is incomplete — two specials,
no desperation. Maintainer prefers it lifted from Super S rather than recreated.
It is the pre-staged BG3 tilemap (`$01FA` 0x80→0xE4 on Start, restaged on every
press). Needs: SMS's per-character movelist data + entry count, then the Super S
equivalent.

**#43 stage vertical slide.** On the ported stage only — confirmed by the
maintainer that no other stage does it, on either build — during a jump the
shadows and opponent slide toward the bottom of the screen and return on
landing. Measured: BG1 holds palace+ground and takes the full camera, so "the
ground moves at quarter speed" is ruled out. **Not reproduced:** two probe
attempts failed to make the character jump at all (p1y never leaves `$00C0`), so
the vertical behaviour is unmeasured — do not infer a cause from those runs.
Get a jump to happen first (training-mode tooling, or a mid-jump savestate).

## Three lessons this session paid for

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

## Build commands

```bash
tools/build_ref_v2.sh                                   # REF v.2 = v.1 + patch 15
SATURN_HIDDEN=1 python3 tools/saturn/mksaturn_smoke.py  # standalone Saturn (SATURN_VISIBLE=1 for the non-hidden variant)
SATURN_HIDDEN=1 bash tools/saturn/build_refsaturn.sh    # on REF v.2 (REF_VERSION=1 for v.1)
bash tools/saturn/build_saturn_stage.sh                 # Saturn + the Pluto-slot stage port
python3 tools/saturn/extract_saturn_voice.py            # her trimmed voice bank + directory
ROM=<rom> tools/run.sh tools/test_regression.lua 300    # the gate before shipping anything
```

## Session hygiene

Commit per finding; `.sfc` gitignored (rebuild from BPS); never patch in place;
every timing/behaviour claim emulator-verified (`ROM=<build> tools/run.sh
<script> <timeout>`); temp files in `$CLAUDE_JOB_DIR/tmp`; all Saturn/Super-S
material stays in the `saturn/` subfolders.
