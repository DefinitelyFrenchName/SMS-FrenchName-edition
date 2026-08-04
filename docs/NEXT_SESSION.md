# Next-session handoff — 2026-08-04

Fast orientation. **Full operational map: `HANDOFF.md`; Saturn brief:
`docs/saturn/PROJECT.md`; test-ROM registry: `docs/saturn/BUILDS.md`; patch
registry: `docs/patch_index.md`; engine subsystems:
`docs/sms_engine_internals.md`.** (Earlier editions of this file are in git
history.)

## Status in one paragraph

The base patch project is done and green. **SMS + Saturn is feature-complete with
no open bugs.** Current build is **v0.14.9**
(`SailorMoonS_REFsaturn_v0.14.9-hidden-stage.sfc`, `03b73cdd…`) on **REF v.2**.
She is summoned by holding **L+R** while confirming a **Uranus, Neptune or Pluto**
slot — the only char-select variant now; the visible slot-10 build was retired
2026-08-04 and deleted. Gates: `tools/saturn/verify_saturn.sh` (45 checks, ALL
PASS; `QUICK=1` for a ~4-min subset) and `tools/test_regression.lua` (57/57).
Maintainer's verdict on the current build: "perfectly acceptable for playing".

## The two open work items — both DEFERRED by the maintainer, neither blocking

### 1. Voice pitch — targets settled, mechanism half-traced, cost unknown

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
