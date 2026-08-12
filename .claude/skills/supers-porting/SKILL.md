---
name: supers-porting
description: Hard rules for porting content from Bishoujo Senshi Sailor Moon Super S (the donor) into SMS - donor provenance, the shell rule, graft mechanics, the audio port, and cross-game verification. Load for any work touching Saturn, the Rev. SS line, tools/saturn/, or any claim that compares the two cartridges. Sits on the sms-romhacking, snes-romhacking and romhacking-methodology skills.
---

# Super S → SMS porting

Agent-facing rules, IDs `[SSP-NN]`; the human rendition with incidents is
`docs/project/saturn/porting_lessons.md` (ID sets kept identical by
`tools/checkskills.py`). Layers below: `sms-romhacking` (`[SMS-NN]`),
`snes-romhacking` (`[SNES-NN]`), `romhacking-methodology` (`[RH-NN]`). ROM addresses
live in the checked saturn docs (`docs/project/saturn/supers_map.md` etc.), not here.

## 1. Donor provenance

- [SSP-1] SMS and Super S are the SAME ENGINE with small per-routine shifts: byte
  inequality ≠ code inequality (find twins by signature/skeleton). But NOTHING is
  assumed by analogy — the movelist codec and the entire audio engine do not exist in
  the donor. Verify each subsystem before leaning on the identity.
- [SSP-2] Engine object ids are SHIFTED: Super S id N == SMS id N−1 (for N ≥ 0x31).
  Re-base every spawn record in ported code, or the wrong object type runs — worst
  case its proc never returns and the frame update dies (frozen game, music alive).
- [SSP-3] Inherited tooling is donor-derived: treat its Saturn references as
  inapplicable to the SMS image ([SMS-1]), and validate any inherited map on the
  emulator before building on it — never rely on inherited maps alone.
- [SSP-4] Donor fixtures can silently be the WRONG game's dumps — hash-check which
  cartridge a trace/ARAM dump came from before using it as an oracle.
- [SSP-5] Cross-game identity claims are measured per subsystem and stated WITH their
  caveats inline: "scripts byte-identical" held only after stripping the donor's extra
  CMD steps; "cel records same sizes" was 97 of 98. A conclusion asserted in one
  sentence with the caveat two paragraphs later is how the port's foundation rotted.

## 2. The shell rule

- [SSP-6] **THE SHELL RULE**: Saturn wears a host character as a shell, so any fix
  keyed to CHARACTER data works for one shell only and looks like unrelated bugs on
  the others. Test every such fix with AT LEAST TWO shells; prefer per-player keys
  over per-character keys.
- [SSP-7] Guard the thing that ARMS, not the things that act: every consumer keys off
  the summon FLAG, so a restriction placed at the transform leaves the voice, sound
  remap and palette override armed. The rule lives where the flag is SET.
- [SSP-8] Structural locks beat mode interrogation: restrict WHICH SHELLS can arm her
  (the ones story mode cannot reach) rather than asking what mode the game thinks it
  is in — mode checks were defeated in the field.
- [SSP-9] A summoned character's reachable palette slots are 4-7 only (the L+R summon
  chord doubles as the palette modifiers): MASK the slot, never clamp —
  clamping out-of-range slots reproduced the original bug exactly.
- [SSP-10] Transfers sized from the SHELL truncate ported data: one shell's smaller
  effect sheet cut 15 tiles from hers and only that shell showed it ([RH-39]). Force
  the length on the armed path, and verify the ported data is byte-identical in VRAM
  across ALL shells - invariance, not a hardcoded checksum.
- [SSP-11] A visible char-select slot is the exact surface the story lock exists to
  avoid — the hidden summon is the only select variant, by ruling.

## 3. Graft mechanics

- [SSP-12] The build grafts a full COPY of the proc bank: hooks applied to the
  original after the copy protect only half the paths ([RH-37/38]). Assert ZERO
  unhooked reads of any patched table anywhere in the assembled image, at build time.
- [SSP-13] When stacking, take bank copies AFTER other patches' edits to that bank —
  box-data patches edit the real bank, and a copy taken first resurrects vanilla data.
- [SSP-14] A donor sentinel record ("no cel", size 0) is LIVE data in the host: SMS
  does not skip it, and a 0-length DMA wipes all of VRAM ([SNES-16]). Rebase or
  neutralise sentinels explicitly.
- [SSP-15] Truncated grafts fail LATE and silently: a code graft cut short executes
  stale copy bytes mid-handler; a data graft one pair short parks a state machine in a
  hold path forever. Bound every copied block by the donor's own end markers, not by
  where the interesting part seemed to stop.
- [SSP-16] LIFT donor tables rather than authoring where possible — byte-identical
  shared rows are the proof the semantics match. Before fixing an inherited fault,
  confirm it byte-identical in the DONOR ROM, so the fix corrects the original game
  and not the port. And faithful ≠ bug: verify odd behaviour against the donor before
  "fixing" it.
- [SSP-17] Scene scripts have four parts; only the sprite-attribute byte may be
  carried across from the donor — the other parts are host-side ids and porting them
  hangs the round load.
- [SSP-18] Stages are SWAPPED, not added: the scene pointer table is exactly ten
  entries with the scripts immediately after — [SMS-3]'s shape outside the character
  tables.

## 4. The audio port

- [SSP-19] The per-character BRR directory is resident from BOOT and never refreshed
  per match: loading her bank under borrowed ids plays audio cut at the SHELL's
  offsets. Patch the directory too, and restore any borrowed rows (dirty-flag gated)
  on non-Saturn loads, or the borrowed character buzzes for the rest of the session.
- [SSP-20] The relocating uploader adds a DP offset to every destination — never
  append to that stream directly, or the block lands 16 bytes high.
- [SSP-21] Her samples have TWO native rates — a measurement of one set is NOT
  confirmation of the other ([RH-33]).
- [SSP-22] The driver plays samples as NOTES ON A SCALE: pitch is one signed transpose
  byte per sound, character-specific. The DSP's SRCN register names the sample that
  ACTUALLY played — "which sound is this" is a measurement, never an inference; every
  wrong turn in the sound work came from reasoning about where a sample ought to live.
- [SSP-23] Borrowing an existing character's PER-PLAYER sound ids covers all nine
  shells with no per-shell code — it dodges [SSP-6] by construction (the halves are
  per player, so a real copy of that character on the other side never collides).
- [SSP-24] Super S ships exactly TWO palettes per character (the other manifest
  pointers are the icon and effects palettes); extra costume palettes must be
  AUTHORED (rotate only the costume ramp - the usual donor of extras has no Saturn).
  Saturn is the only character whose two palette pointers are stored DESCENDING. And
  donor and host can ship the SAME asset raw vs compressed — search both forms before
  concluding an asset is absent ([RH-30]'s cousin: ask what form the bytes took).

## 5. Cross-game verification and constraints

- [SSP-25] Cross-game doc checks run against BOTH cartridges, SKIP loudly when the
  donor is absent ([RH-55]), and carry their own negative control: the same image
  handed in twice MUST fail, or the check compares nothing.
- [SSP-26] Ported code blocks are gated byte-identical (`port_saturn_proc.py --check`)
  and the decode table behind the porter is oracle-validated against an independent
  disassembler ([SNES-13]).
- [SSP-27] Port bundles are UNTRACKED (they embed donor cels/palettes/samples):
  rebuild from source behind the named gate script. The verify gate
  (`tools/saturn/verify_saturn.sh`) is sanity-checked against known-bad builds — a
  gate that cannot fail is not a gate ([RH-25]).
- [SSP-28] The constraint model: ROM is NOT scarce (hundreds of KB spare), ARAM is the
  only hard wall ([SNES-25]), and the real cost of a tenth character is nine-wide
  LAYOUT ([SMS-3]) — "more ROM" solves nothing here.

## Pre-flight checklist

Any Saturn-visible change: tested on ≥2 shells? ([SSP-6]) Keyed per-player? Guard at
the arming flag? ([SSP-7])
Porting code/data: spawn ids re-based? ([SSP-2]) Sentinels handled? ([SSP-14]) Block
bounded by donor end markers? ([SSP-15]) Confirmed in the donor first? ([SSP-16])
Building: proc-bank copy taken after other edits? ([SSP-13]) Zero unhooked reads
asserted in the assembled image? ([SSP-12]) Gate run, and known-bad still fails?
([SSP-27])
Audio: directory patched and borrowed rows restored? ([SSP-19]) Verified via SRCN, not
inference? ([SSP-22])
