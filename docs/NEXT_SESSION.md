# Next-session handoff — 2026-08-06 (session close)

**NEXT SESSION IS DEDICATED TO PATCH 16 (menu translation), step 2.** It is
the only active work item in the project. The issue-remediation programme is
COMPLETE (all 61 review issues resolved, tracker empty — record and lessons:
`HANDOFF.md` §0 + traps 12-18); everything else ships green. Dormant
maintainer options, not tasks: HANDOFF §8's fold-6/7/8-into-canonical and
the dash-distance retune.

---

## Patch 16 — where it stands

**Step 1 (font install) WORKS.** The half-width A-Z (built by
`tools/mkhalfwidth.py`, condensed from the game's own capitals) is installed
into the menu font sheet `$C4:2590` (extended 418 -> 512 tiles, relocated)
and **reaches VRAM tiles `$5C0-$5FF`** — read back out of VRAM, 52/64
non-blank (26 letters x 2 tiles) vs 0 on clean. Builder: `tools/mkpatch16.py
<out.sfc>` (standalone A/B: clean -> `d8f4ff1d…` with today's tree). Two
hard-won facts behind it:

* **The asset-record layout is `[vram16][len16][src24][dest24]`** (job table
  `$C3:BE08`) — the upload LENGTH sits 2 bytes BEFORE the src pointer, not 8
  after. The extended sheet's length field is at `$C3:BF18`, raised
  `$3480 -> $4000` (the ceiling: source is `$7E:C000`, more runs off bank
  `$7E`).
* **The kanji block is NOT loaded on the config screen** — no transfer to
  VRAM `$5000` happens there, so glyphs placed in it can never show. The
  screen's sheet is `$C4:2590 -> $7E:C000 -> VRAM $400`.

**Step 2: the Options screen WORKS (2026-08-06 — the designated next action
was run and answered).** The dump showed the buffer staged correctly the whole
time; the real mechanism was found with a per-frame VRAM census + unfiltered
DMA log (`tools/probe_p16_options_buf.lua`): the glyphs reach VRAM at
**main-menu entry**, the Options transition **clears all 64KB of VRAM**
(fixed-source DMA at `$80:8191`), and the Options loader (`$C3:A4DD`) never
re-uploads the font — the "Options runs the extended transfer" note was that
menu-entry transfer, misattributed. Fix (always on in `mkpatch16.py`): the
loader's first record load is JSL-hooked to a stub that uploads the font
first. `SMS_P16_OPTIONS=1` now renders the six English labels
(screenshot-verified); button-config still green on the hooked build.
Values are DONE too (same day): the runtime writer is `$80:8C43` + record
tables at `$C3:A44F..A46B`; records uncompressed in bank `$C4`, 12 in-place
cell edits, verified through both highlight states. Builder A/B today: base
`206fee3d…`, full Options translation `3cba4171…`.

**Everything else for Options is ready:**
* Its tilemap is **asset record 19** (`$C3:69F0`).
* Budgets are measured off the live tilemap: **18 columns for a label, 6 for
  a value**; a half-width glyph is ONE map column. The maintainer's strings
  all fit.
* Addressing: MAP tile = VRAM tile − `$200`; a glyph is 2 rows,
  `bottom = top + $10`; labels attr `$0C00`, values `$1000`.
* The option VALUES are indeed not tilemap work — they are drawn by
  `$80:8C43` from self-describing records in bank `$C4` (uncompressed;
  found and translated 2026-08-06, see `docs/menu_text.md` § Values).

**Screen coverage (maintainer priority: Options ✓, Win, ACS, Tournament; story
out of scope):**
* **ALL FOUR screens are now probed** (`tools/probe_p16_screens.lua`, routes
  win/acs/tournament; full table in `docs/menu_text.md` § Screen census).
  Short version: ACS = cluster `$C3:9CF2` (+ its own small font at `$4000`);
  Win (REPORT CARD) and Tournament both run on a **bank `$DF` loader**
  (`$DF:83CE`) that bypasses the `$C3` clusters and the `$80:92D2` uploader
  entirely — decoding that system is the next work item. The ACS door is the
  VS config screen's SELECT (press it once the mode-row handler `$83:A849`
  executes; it transitions on its own).
* プレイヤーセレクト on the *illustrated* char-select is OFF-LIMITS (artwork,
  rainbow-animated); the plain-text one on the Tournament screen DOES need
  translating, as do that screen's per-line character names.
* Neither プレイヤーセレクト nor the title text is in the 21 compressed
  screen tilemaps (only `$C3:7C00` is a text screen) — finding them is
  input-free work.

**Verification traps, already paid for:**
* Verify with `tools/probe_menu_vram.lua`, which dumps **on the font
  transfer**, not at the end of the run — a final-screen dump reads identical
  on clean and patched ROMs because a later upload overwrites the region.
  Use `POKE=1` for the positive control (0/256 bytes arrive clean, 256/256
  patched); without it a clean-vs-patched diff proves nothing.
* `tools/menutext_check.py` only knows the STAGE names — it does not
  validate the Options budgets (those were measured off the live tilemap).
* Menu-font reference tooling: `tools/menufont.py` (`sheet`/`blanks`/
  `decode-map`), `tools/menufont_table.py` (code -> glyph, validated);
  glyphs are 2x2 tiles in a 16-tile-wide sheet, kana block -> VRAM `+$0A0`,
  kanji `+$300`. The FULL-width alphabet is 22/26 (missing J Q S Z).

---

## State of everything else (2026-08-06, end of the remediation session)

* **Remediation COMPLETE.** 61 issues over four batches, one commit per
  issue from batch 2 on; #84 refuted and #35 closed by measurement; #64
  closed as already fixed. Lessons: HANDOFF traps 12-18. The
  machine-specific-path sweep that closed the session found zero remaining
  references (three fixed: two home-relative plan-file pointers in the docs,
  one hand-staged `/tmp` probe oracle — now
  `mkmovelist.py --raw build/saturn/saturn_tm.bin` with `ML_RAW` override).
* **Releases untouched throughout:** Rev. S-02 `41d93a53…`, Rev. SS-02
  `b96f3fe8…`, still reproducing from `tools/build_rev.sh both` after every
  builder refactor. Saturn is feature-complete at v0.16.1 with no open bugs.
* **Artifacts that moved this session:** patch 10b `745ea0bc…` (#86 modes
  gate -> #88 TTL refresh -> #93 lazy glyph upload), patch 11 `a3aba30d…`
  (#90 reset-during-hitstop), **v0.22 re-recorded as lineage** (maintainer
  decision): `52bc7e38 -> 19a7fc0d -> 3bb9c829 -> e6b999b5`, regression on
  it ALL PASS (63).
* **Suite counts:** clean **45**, Rev. S-02 / Rev. SS-02 **60**, Saturn gate
  **53**, p11 tier1 **65** (new reset-hitstop phase), training self-tests
  **T1-T11** (T11 = reload clears framedata).
* **New shared modules:** `tools/boxlib.py`, `tools/saturn/gfxlib.py`;
  `asm65816` now covers jsl/DP/(dp),Y/stack-relative/abs-X/brl/mvn/jsr and
  mksaturn_smoke's runtime-fixup assembler class is EMPTY (5 conversion
  rounds, all byte-identity-gated incl. env variants).
* **Harness facts:** `run.sh` resolves the emulator via `$MESEN` (per-OS
  default); its old scriptTimeout flag was measured INERT under
  `--testrunner` (every Lua entry is hard-capped at 1 s regardless);
  `mkindex --check` guards the tools index from the gates and health.

## Build & verify

```bash
tools/build_rev.sh both                                 # the two RELEASE builds
tools/build_ref_v2.sh                                   # REF v.2 (Saturn base)
SATURN_HIDDEN=1 bash tools/saturn/build_refsaturn.sh    # Saturn on REF v.2
tools/saturn/verify_saturn.sh                           # 53 checks (QUICK=1 ~4 min)
ROM=<rom> tools/run.sh tools/test_regression.lua 900    # 60/60 (45 on clean)
tools/health.sh                                         # no ROM/emulator needed
python3 tools/mkpatch16.py <out.sfc>                    # patch 16 (font install)
ROM=<p16 build> POKE=1 tools/run.sh tools/probe_menu_vram.lua   # step-1 verify
```

## Session hygiene

Commit per finding; `.sfc` gitignored (rebuild from BPS); **never commit game
imagery or audio** (screenshots never, savestates yes); never patch in place;
every timing/behaviour claim emulator-verified; all Saturn/Super-S material
stays in the `saturn/` subfolders; during multi-agent work, `git add`
explicit paths only. (Earlier editions of this file are in git history —
including the full remediation batch tables.)
