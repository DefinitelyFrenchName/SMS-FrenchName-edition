# Next-session handoff — 2026-08-05

## Start here: ONE open item (patch 16). The other two are done.

**1. Saturn's 214P projectile — FIXED (v0.14.11, 2026-08-05).** It was a
**per-shell truncation of her effect sheet**, not a bad sprite list. Her
0x1040-byte sheet is staged over the shell's in `$7F:0000`, but the DMA that
follows was sized from the **shell's own** sheet: Uranus `$11C0`, Pluto `$10C0`,
**Neptune `$0E60`** — so on Neptune the last 15 tiles (`$113-$121`) never
reached VRAM, and the travel pose draws 7 of its 12 sprites from that range.
Hence *two disconnected pieces*, on Neptune, intact on Uranus. The armed path of
the DMA stub now forces the length too (`sta $004305`). Verified byte-identical
to the decoder output on shells 6/7/8; gate 45/45, regression 57/57. Detail:
`docs/saturn/BUILDS.md` § "214P projectile: SOLVED".

**2. Patch 16 (menu translation)** — now the only open item. A complete
half-width A-Z exists and every string fits its cell budget; the font block
extends and round-trips, but nothing carries the extra tiles to VRAM. The
transfer covering that region is `vram $4000 len $3480 src $7E:C000`, staged in
direct page `$02`. Find what feeds that length.
⚠ **Read the projectile post-mortem first — it is probably the same bug.** That
one was also "the data is right but nothing carries it to VRAM", and the answer
was that a *length* came from the wrong source. `tools/saturn/probe_saturn_fxdma.lua`
already dumps every VRAM DMA of a load (dest + length + source) from direct page,
which is exactly the map this needs; hook it at **`$80:92A4`**, not `$C0:92A4`.

**3. Nameplate — DONE** (v0.14.10): her plate reads SATURN, vanilla untouched,
regression 57/57. `SATURN_NAMEPLATE=0` reverts to blank.

## The lesson this session paid for repeatedly

Probes and conclusions kept being wrong for one reason: **an instrument was
trusted before it was shown to distinguish a known-good case from a known-bad
one.** Blank VRAM looked like a finding until a vanilla control reproduced it; a
build A/B looked conclusive until the maintainer saw both frames were broken; a
register hook reported zero because it was on the wrong bank. Before believing
any measurement here, make it detect something you already know is there.

The projectile fix closed that loop concretely, and its four failure modes are
worth knowing before writing the next probe:

* **`tile * 32` is not a VRAM address.** The OBJ name base is word `$6000`
  (byte `$C000`), second name table at word `$7000`. The whole "blank VRAM"
  signature was read out of unrelated memory.
* **Her sprite list is emitted on ALTERNATE frames.** A capture triggered N
  frames after an event lands on an empty frame half the time — one such capture
  returned zero palette-7 sprites and three unrelated ones that looked plausible.
  Trigger on the thing you want to see (`n_palette7 >= 8`), not on a delay.
* **`emu.getState()` throws inside a memory callback here**, silently killing the
  hook. If the counter is incremented after that call, a dead probe reports
  "0 events" instead of an error. Increment first; never let a probe's own
  bookkeeping sit downstream of a call that can throw.
* **This code runs from the FastROM mirror: hook `$80:xxxx`, not `$C0:xxxx`.**

And the gate lesson: `verify_saturn.sh` passed on the broken build for two
weeks. It now asserts her effect sheet is **identical across shells** —
cross-shell invariance rather than a hardcoded checksum, so it survives changes
to her art — and that check was sanity-checked against v0.14.8, where it fails.



Fast orientation. **Full operational map: `HANDOFF.md`; Saturn brief:
`docs/saturn/PROJECT.md`; test-ROM registry: `docs/saturn/BUILDS.md`; patch
registry: `docs/patch_index.md`; engine subsystems:
`docs/sms_engine_internals.md`.** (Earlier editions of this file are in git
history.)

## Status in one paragraph

The base patch project is done and green. **SMS + Saturn is feature-complete with
no open bugs.** Current build is **v0.14.11**
(`SailorMoonS_REFsaturn_v0.14.11-hidden-stage.sfc`, `b180790a…`, hidden
`dacb1c65…`) on **REF v.2** — patch 100 + 101 + the nameplate + the projectile
fix. She is summoned by holding **L+R** while confirming a **Uranus, Neptune or
Pluto** slot — the only char-select variant now; the visible slot-10 build was
retired 2026-08-04 and deleted. Gates: `tools/saturn/verify_saturn.sh` (46
checks, ALL PASS; `QUICK=1` for a ~4-min subset) and `tools/test_regression.lua`
(57/57). Maintainer's verdict on the current build: "perfectly acceptable for
playing".

## Everything below this line is SUPERSEDED — kept for its technical detail

> ⚠ **Voice pitch is DONE and SHIPPED** as patch 101, on by default since
> 2026-08-05 (HANDOFF §0 carries the field verdict). The sections below describe
> it as deferred and, further down, as blocked behind "one routine shared with
> the music" — that blocker was a misread PC and is gone. Read them for the
> measured targets and the harness notes, not for status.

### 1. Voice pitch — BUILT as PATCH 101, not shipped; one finding to settle

**Done since:** the Super S work is now **patch 100** and the pitch fix **patch
101** (`SATURN_PITCH=1`, off by default). 101 is implemented, measured and
gate-clean — see `docs/patch_notes.md` "Patch 101" for the full verification
table. Byte-neutrality of 100, REF v.1 and REF v.2 was re-proven by rebuild.

**The one thing blocking it:** retuning her voices also moves DSP voices 1/2/6 —
which hold *music* sources — by exactly the intervals applied to her sounds, at
~84 frames of 900. Either her sfx is layered across several DSP voices (correct
behaviour) or an sfx pitch shadow is being flushed onto a music voice (audible
detune). Settle it by reading the channel allocator at `$0AF7`/`$0B1E`, or by
listening to `sms_saturn_pitch.bps` applied and not.

**Second decision for the maintainer:** the transpose is shared, so P1 Saturn +
P2 Sailor Moon cannot both be right — with 101 on, that Moon is 3 semitones flat.

**Harness note:** across builds whose LOAD duration differs, use
`dspdiff.py --semantic` (ordered key-on sequence, shift-immune). A frame-aligned
diff desynchronises by ~3 frames because extra load-time work moves the audio
phase relative to match start.

Original notes below.

### 1b. Voice pitch — MECHANISM SOLVED 2026-08-04; in-match fix measured

**The blocker below was a misreading and is gone.** `$131D`/`$1327` are not a
pitch routine — they are the `INC Y` inside an unrolled DSP shadow flush
(`$12F4`). Pitch is **per-sound NOTE data**: one **transpose byte** per sound id,
one semitone per unit. Full decode, addresses and the ROM home of the driver
(file offset = ARAM + `0x23F804`) are in `docs/saturn/sound_scope.md` § "SOLVED
(mechanism + measured fix)". New tool: `tools/saturn/spc700dis.py`.

* **In-match voices: fix measured.** Her four ids (49-52, char 1's) all want
  transpose **`$FB`**. Poking them lands every voice on `$0346` — 0.5 cents from
  the settled `$0345` target (`tools/saturn/probe_sms_voicetranspose.lua`, PASS).
  The driver is not re-uploaded mid-match, so a ROM change is stable.
* **What is left is the gating, not the retune.** Those ids are Moon's, so the
  bytes must swap in and out exactly as her directory record already does
  (DIRTY flag `$7F:F107`/`F108`). Estimated: two spare audio-table records
  (52/53 free) + two `ipl()` streams + two `_load` calls. ⚠ Not on the P2
  directory stream — that path is relocated by dp `$10`.
* **Select line: derived, NOT measured.** All nine select sequences are identical
  apart from transpose, so she can just *request Mars's id 58* (already `$FE`,
  the exact target) — zero data change. But the confirm voice would not fire in
  any harness config tried, so this is unverified; and the `$0582` figure the
  original select measurement rests on looks like an sfx (srcn 128, sample
  `$9C00`), which deserves a second look first.

Original notes below, kept because the targets still stand:

Her voices play **sharp**. Both targets are measured and confirmed (the select
line by the maintainer's own spectral analysis):

| | current | target | sharp by |
|---|---|---|---|
| in-fight voices (srcn 49/50/51) | `$03E4` `$041F` `$03AC` | **`$0345`** (6539 Hz) | +3 / +4 / +2 st |
| character-select "Yoroshiku" | `$04E7` Uranus / `$0582` Pluto | **`$03E4`** (7781 Hz) | +4 / +6 st |

Both targets sit on the driver's own semitone grid, `$03E4` being exactly +3
steps above `$0345`, so no off-grid value is needed.

**Why it is not done: pitch is emitted from ONE routine shared with all music** —
SPC `$131D` (low byte) / `$1327` (high byte). The 65816 only sends a sound id;
everything about pitch happens inside the SPC driver, which this project has
only ever used through its WRAM API (`$78`/`$1078`/`$10F8`).

**Next step:** disassemble the driver around `$131D` to find where the VALUE
arrives from. If it is a per-sound table — likely for a driver of this era — the
fix is a few bytes on her ids and low risk. If her voices are played as notes in
a sequence, the pitch lives in sequence data and it is more entangled. The driver
is uploaded to ARAM at boot, so the table has a ROM home to patch.
⚠ ARAM is this project's one hard memory wall (`docs/saturn/memory_and_shell.md`),
and a mistake here is audible across the whole soundtrack.

Maintainer's position: probably not worth it for a hidden character, but curious
what the driver would yield. Treat as exploration, not committed work.

### 2. Patch 16 — menu translation. Strings validated; the maintainer wants half-width explored

Groundwork is DONE and the first screen is ready to build (see below). The
maintainer wants to **explore half-width letters first**, which is a bigger job:
it needs room made, not just glyphs drawn.

**Ready now, full width:** eleven stage names validated by
`tools/menutext_check.py` (budget, glyph availability, centred tile encoding).
**Only `S` and `.` need authoring** — 4 of the 10 free half-slots, no relocation.
Plus the VS button-config labels the maintainer supplied: `LP` `HP` `LK` `HK`
`L.SP` `H.SP`, `MODE`, `MANUAL`, `STAGE`; `1P`/`2P` unchanged.

**The half-width question.** Half-width Latin already EXISTS — the
`PRESS "SELECT" TO ACS` strip is individually addressable, 1 tile wide and 2
tall, giving **P R E S L C T O A**. Half-width would double every label's budget.
But a full 26-letter half-width alphabet needs 26 half-slots and only **10** are
free in place. The rest means extending the kanji block (`mkkanji.py` already
decompresses, inserts, re-encodes and relocates it — that is how v0.14.0 added
the stage kanji) and growing into the VRAM beyond it.
⚠ **The survey read VRAM `$3C0-$3EE` as blank — that is evidence, not proof.**
Prove it is genuinely unused before relying on it; this project has already been
burned by an ARAM region that passed "nothing points at it" and was still live.

**Also still unlocated:** `プレイヤーセレクト` and the title text are NOT in the
compressed tilemaps (only 1 of the 21 screen maps is a text screen). Finding them
is input-free work.

## What this session established (so it is not re-derived)

* **The menu font's code -> glyph table exists** (`tools/menufont_table.py`),
  validated by decoding a real screen and by the font's own layout maps. Glyphs
  are 2x2 tiles in a **16-tile-wide sheet**; kana block -> VRAM `+$0A0`, kanji
  `+$300`. `tools/menufont.py` builds/checks it (`sheet`, `blanks`, `decode-map`).
* **The compressed-asset job table is at `$C3:BE02`** (not `$BEE0`): 59 records of
  `[src24][dest24][u16][u16]`. 21 blocks decode to 0x800 (a screen); only
  `$C3:7C00` is text.
* **Her samples have TWO native rates** — in-fight ~6539 Hz, select line ~8000 Hz.
  That dissolved a long-standing contradiction: the old "8 kHz" A/B had
  calibrated the SELECT line only.
* **The full-width alphabet is 22 of 26.** Missing: **J Q S Z**. `F` exists (digit
  run, `$228`) and matches the alphabet's weight.
* **OBJ palette 6 is the hit spark**; pal 7 is genuinely free (0 uses across three
  full vanilla matches) and now carries her projectiles.

## Traps this run paid for — they generalise

1. **A probe that reports nothing is usually broken.** Hit three times: a DSP
   register write-callback that never fires (shadow the SPC's `$F2`/`$F3` port
   writes instead), an anchor string that silently failed to match so an edit
   never applied, and a filter that hid every result.
2. **Identify a thing by its ADDRESS, not by a plausible property.** A Super S
   "voice" identified by having a steady pitch was an sfx; reading each source's
   sample address from the BRR directory settled it. That retraction cost a whole
   wrong conclusion.
3. **A measurement in one mode does not generalise.** A palette census run in
   PRACTICE never lands a KO, so it missed that pal 6 is the hit spark — and had
   we moved her projectiles onto row 6, hit sparks would have broken game-wide.
4. **"Is this slot zero?" is not "is this slot free."** A stub slot that passed a
   zero-check was overwritten later in the same bank build; the builder now reads
   the stub back out of the assembled image.
5. **Assert the precondition before believing the verdict.** "SHELL_GUARD blocks
   6/7/8" was three sessions of mystery; the harness had never actually selected
   6/7/8.
6. **When a doc contradicts itself, measure — do not pick a side.** `$8D` was
   documented both ways; choosing wrong caused two field bugs that looked
   unrelated.
7. **`lda long,Y` does not exist on the 65816** (`$BF` is long,X), and a `plb`
   inside a JSL'd stub pops the RETURN ADDRESS, not the saved DB.

## Build & verify

```bash
tools/build_ref_v2.sh                                   # REF v.2 = v.1 + patch 15
SATURN_HIDDEN=1 bash tools/saturn/build_refsaturn.sh    # Saturn on REF v.2
bash tools/saturn/build_saturn_stage.sh --ref           # + the stage port <- v0.14.9
tools/saturn/verify_saturn.sh                           # 45 checks, the gate
QUICK=1 tools/saturn/verify_saturn.sh                   # ~4 min subset
ROM=<rom> tools/run.sh tools/test_regression.lua 900    # 57/57
```

## Session hygiene

Commit per finding; `.sfc` gitignored (rebuild from BPS); **never commit game
imagery or audio** (`.gitignore` blocks both repo-wide — asset policy, 2026-08-04:
screenshots never, savestates yes); never patch in place; every timing/behaviour
claim emulator-verified; all Saturn/Super-S material stays in the `saturn/`
subfolders.
