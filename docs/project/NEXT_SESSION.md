# Next-session handoff — 2026-08-10 (session close)

**Read this, then `../game/README.md` if the work is about the ROM, or
`patch_index.md` if it is about a patch.** Everything below is current; the
sections further down are this session's detail.

## Where to pick up

1. **Saturn's round-won badge is DONE** (v0.17.0, hidden `3dee7316…`) — closed
   the same day it was raised. Detail: `saturn/PROJECT.md` § "DONE — her
   round-won badge", `saturn/BUILDS.md` 0.17.0, and the game-side mechanism in
   `../game/annotations.md` § "Round-won badge". Three things worth carrying:
   * the badge table at `$C0:E166` has **eight read sites**, six of them P2 or
     redraw paths — the count was taken first, so traps 5/19 were paid forward
     rather than paid for;
   * her tiles were in the donor all along, **stored RAW** at `$E0:D2B8` while
     SMS compresses the same sheet at `$E0:21E6` (503 of 512 tiles identical) —
     which is why every compressed-stream search found nothing;
   * `sms_lz` gained **`encode_lz`**, an optimal parse that beats the vanilla
     stream. `encode` is untouched on purpose (patch 16's hashes), but any future
     sheet edit should reach for the new one.

   **Shipped as Rev. SS-03** (`f71421d8…`, `release/Rev.SS-03.bps`). The fix is
   Saturn-only, so **S stays at 02** (`41d93a53…`, unchanged) and **SS advances
   to 03** — the two revisions are now independent (`smspaths.REV_S` / `REV_SS`).
   The superseded Rev. SS-02 `.bps` (v0.16.1, no badge) was deleted, so `release/`
   holds one thing to apply per side. Rev. S / SS may diverge again the same way:
   only the side whose bytes move gets a new number.

   **And one pre-existing overlap it drew out — cosmetic, one frame, not a
   ruling:** patch 10b's left status label sits at `$10E5-$10EC`, and a player's
   **second** round-won badge occupies `$10C4/$10C5/$10E4/$10E5`; they share
   `$10E5`. But a player has **at most one badge in normal play** — winning the
   second round ends the match (best-of-3, or one round in tournament) — so the
   second badge only exists for the deciding-win frame, at match end. It can
   surface only on **v0.22** (the only bundle with 10b) and only if a status
   label is live at that exact instant. No Saturn build carries 10b. Noted for
   completeness, not as open work.
2. **Patch 16 — menu translation.** The **bracket VS names are DONE**
   (2026-08-11, `SMS_P16_BRACKET`): the screen reads **MOON VS MOON**, verified
   against a clean A/B at the same frame, and with all five gates on together.
   Regression ALL PASS (45); the font-only build still reproduces `c9ad4910…`,
   so the change is purely additive.
   * The blocker was never the records — it was that the work had been aimed at
     the **4bpp BG1/BG2 sheet** while the plate is on **BG3** (2bpp, CHR word
     `$5000`, fed by `$C7:44D1` via codec 2). Glyphs now go in through a **7th
     asset entry** on script `$DF:A43E`, so the un-reversed codec 2 is never
     touched. The script grew 8 bytes, had to move, and lives in the appended
     bank with a 17-byte DB stub in bank `$DF`.
   * ⚠ **Trap 25 (HANDOFF §0):** the `$DF` engine executes from the `$9F`
     mirror, so a stub must sit at `$8000-$FFFF`. The first build used bank
     `$DF`'s largest free run at `$4D85` — below `$8000`, hence open bus, hence
     a garbage script pointer and a silently wrong screen.
   * **Remaining:** the **A.C.S. name card + prompt** — still a session of its
     own: find the `$7F:DC00+` filler, then the font source, string encoding and
     name-substitution site, and only then census a glyph window. Now that BG3
     is understood, check which layer that prompt is on *first*.
3. **Patch 14 — needs a RULING, not a patch.** `--all-grabs` does not scale a
   TECHED throw, so at Guts L3 teching costs more than eating the throw (12 vs
   10, measured). No shipped build passes the flag. The question is yours:
   *should a teched command grab be scaled by Guts at all?* Full brief below.
4. **`checkdocs` — the coverage increment is DONE** (2026-08-10): **87 → 207
   checks**, **116/299 → 190/325** addresses re-derived, runtime 0.30 s. Route
   (b) carried it, because route (a) turned out not to be the cheap one:
   **164 of the 183 uncovered addresses were PROSE ONLY**, so quoting entry
   instructions meant hand-authoring ~151 lines — and a quote stamped from the
   currently documented address is a tautology that can never catch an address
   already wrong. The convention is written into `../game/README.md` for NEW
   prose instead; nothing was retrofitted. Detail below.
   **135 remain uncovered and each now says why**: 111 "no instruction boundary
   reachable here" (mostly genuine data — the bank-`$8A` box tables and such,
   for which there is no honest structural check) and 24 "still holds two bytes
   over — does not pin". That residual is the honest floor of this approach, not
   a to-do list.

## What changed this session (2026-08-10) — checkdocs coverage

**87 → 207 checks; 116/299 → 190/325 addresses re-derived; 0.155 s → 0.30 s.**
Three new families and one shared decoder, in four commits.

* **`tools/dis65816.py`** — one 65816 decode table, replacing
  `port_saturn_proc.py`'s private one, which was **wrong in two ways**: `00`
  (BRK) was listed as 1 byte when it carries a signature byte and is 2, and
  `02 08 0B 2B 42 C4 E4` (COP PHP PHD PLD WDM CPY-dp CPX-dp) were in **no**
  table, so a descent meeting a `php` died on "unknown opcode". Saturn's block
  reaches none of the eight — measured — which is why the port was never
  affected. `tools/dis65816_oracle.py` agrees with pelrun's **DisPel** on
  **5051 consecutive instructions across 9 ranges**; two of the nine are data on
  purpose, since data exercises rare opcodes hand-written code never reaches.
  `port_saturn_proc.py --check` gates the ported block byte-identical
  (`30fcfdbb…`, 1788 reached) and is in `health.sh`.
* **The listing family (+27)** — `docs/game/` carries hand-transcribed rows in
  DisPel's format, `C0/D055  rep #$30`, and **the census could not see them at
  all** because `C0/D055` is not a `$BB:AAAA` token: 25 documented addresses
  were invisible to the very report whose job is to be honest about what nobody
  checked. It is also one of only two families that can catch an address wrong
  TODAY, since a human read the address and typed the instruction independently.
* **Boundary-aware instructions** — the check was
  `ROM[a:a+128].find(bytes)`, which matches inside another instruction's
  operand. Now each part must sit at an instruction boundary, in order (an
  ordered subsequence, because `annotations.md:89` **abridges** a sequence and
  demanding contiguity would fail a true claim).
* **The structural family (+84)** — for prose-only code addresses: three tiers
  (**54** boundary + called/vectored, 1.1% false-pass on random nearby
  addresses; **4** boundary + branch target, 2.1%; **26** boundary alone,
  31.9%), each address enrolled only if its own tier predicate **fails at
  base+1 and base+2**. Tiers print separately because they differ 30x in
  discrimination and a weak number must not ride on a strong one.
* **Table-row binding (+5)** and the convention in `../game/README.md`.

⚠ **One live defect found, and it was the opposite of what was reported to me.**
`sms_acs_system.md:35` says ``$C3:BB60` (`jsr ($BB6D,x)` … at `$C3:BB69`)``; the
instruction is at `$C3:BB69`, nine bytes on. **The doc is right** — it names the
correct address in its own text — and the *extractor* bound the quote to the
preceding token, with the 128-byte window hiding the mismatch. The check now
binds where the line says. Reading the ROM is what settled it.

⚠ **Three negative controls were wrong before they were right, and that is the
whole lesson of the session.** The oracle's first control seeded our walk 8-bit
where DisPel is 16-bit — vacuous, because every sampled range opens with
`rep #$30`, which resets both widths on instruction one. The identity gate's
first control lengthened `AD`, an opcode the Saturn block never reaches. The
structural family's interior-byte control was anchored on `$C0:9CB2`, which has
**zero call sites** — the real entry is `$C0:9C96` and from there the "operand
byte" is an ordinary `lda $05,x`. Every one of them looked like a control and
tested nothing. **Take the victim from the workload's own reached set, and check
the framing before trusting a verdict about a byte.**

⚠ **A relaxation invented a claim, which is why guard 6 exists.** With five
guards, the table-row rule bound `sta $0005,y` to `$C1:0881` — the throw pose
POINTER TABLE (`00 00 95 08 aa 08 …`). The row describes code at the read sites
it also names; the real instruction is at `$C1:0747`. The check would have gone
**red for a reason nobody wrote**. Guard 6 — the quote must precede any other
address token in the row — refuses exactly that row and keeps all five true
binds, including `$80:BFBB`, whose row names a second address *after* the quote.

The floor and ceilings the controls gate on are set **from the run recorded
beside them**, never typed from a plan: a ceiling copied out of a planning
document is a guess promoted to a gate, and would stay green while the predicate
drifted underneath it.

## What changed this session (2026-08-09)

**Saturn v0.17.0 — her round-won badge**, raised and closed the same day; the
detail is in item 1 above, `saturn/PROJECT.md` and `saturn/BUILDS.md` 0.17.0.
`SATURN_BADGE=0` differs from v0.16.1 by exactly the two version-string bytes,
patch 16 rebuilds byte-identical on both its recorded hashes, and the gate is
**ALL PASS (60 checks)** with seven new ones. Two systems nobody had written
down came out of it and are now in `docs/game/`: the **in-match asset job table
at `$E0:0000`** and the **HUD CHR sheet at `$E0:21E6`**. `checkdocs` is at **87**.

Before that, four things that were documentation and checking only:

* **`docs/game/sms_sound_system.md`** — the audio system, game-side, re-measured.
  The APU upload, the SPC driver (**stored in ROM at `ARAM + 0x23F804`**, which is
  what makes any of it checkable), the sfx table, and the pitch pipeline. The
  headline: **voices are instruments `≥ $30`**, which skip the instrument record
  entirely, so the only pitch control is a **signed transpose byte per sound** —
  character-specific, −6..+4 across the roster, full census in the doc and every
  cell of it re-derived by `checkdocs`. Corrected three carried-forward numbers:
  the block table has **40** records (not 22), there are **95** usable sfx ids
  (not 94), and "36 blocks in bank `$E7`" was counting IPL chunks, not records.
* **A drawn frame page** — `tools/mkenginepage.py`, published at `/frame.html`,
  and the disassembly behind it corrected `sms_data_architecture.md` §10B: the
  loop is `$C0:E255`, and **hit resolution is not one of its stages** (192 call
  sites, all in bank `$C1` — the attacker's own proc calls it, which is why a
  reaction lands a frame later). Seven routines gained names; three stages are
  recorded as unidentified.
* **`docs/project/how_patches_are_built.md`** — the pipeline, end to end, with a
  worked example that `checkpatchmap.py` re-derives from the shipped patch.
* **Saturn's round-won badge** recorded as open work (above).

Two page-craft lessons worth keeping, both from the frame page: **SVG text
neither wraps nor shrinks**, so the generator now measures every string and
refuses to emit a figure that overlaps, overflows or silently ellipsises; and **a
text class styled only inside a container renders black elsewhere**, which is
invisible on the dark theme — the audit now requires every text class to be
styled on its own.

## What changed this session (2026-08-08, later — the generated checks)

`checkdocs` went from **31 hand-written checks to 76**, and the way it grows is
now three mechanisms rather than typing:

* **A table registry** — 15 documented tables, each declared with a validator
  for its SHAPE (box pointer tables, the four animation layers, the modifier
  jump tables, the throw structures, the special records, the menu value
  records, both cursor-navigation tables). The doc-mention assertion is
  generated, and **every validator is re-run at a wrong base and required to
  fail**. That is why the invariants are strides, orderings and cross-table
  contiguity rather than "the pointers look plausible": plausibility survives a
  two-byte shift, so a check built on it would go green on a rotted address.
* **Claims extracted from the prose** (`tools/docaddrs.py`) — file-offset
  transcriptions, quoted byte runs, quoted instructions (encoded by a small
  65816 subset, looked for at the address or inside the routine starting
  there). 30 checks nobody wrote. Both extractors are negative-controlled on
  synthetic lines every run, because a family that has stopped matching passes
  every claim it no longer finds.
* **A census with a printed number** — every `$BB:AAAA` token in `docs/`,
  classified by whether the cartridge can decide anything about it. `docs/game/`
  is at **105/254** re-derived (+123 in the generated character pages, 42 RAM,
  2 in appended banks). It is a `health.sh` NOTE, never fatal.

**Five documented ROM facts did not survive being re-derived** (all re-measured
by hand, then locked by a check):

| Was documented | Actually |
|---|---|
| special-move record = 8 bytes, `+7 strength-ish` | **7 bytes**; +7 is the next record's attackID, masked off by a 16-bit `lda $0006,Y` |
| `stz $47,X` at `$C1:0E51` (4 places, 3 docs) | **`$C1:0E4F`** — two bytes late |
| config dispatcher `jmp ($BB6D,x)` | **`jsr`** (`$C3:BB69`, opcode `fc`) |
| bank-`$DF` engine: nine screens (mkpatch16 comment) | **eight** call sites, eight ids |
| Uranus toss Y `-$FA80` | **`−$0580`** (`$FA80` is the word) |

Two documentation fixes fell out of it: `mkcharmap.py` printed toss records and
hold scripts under one heading (so a toss header's DAMAGE read as the hold
step's mash-sampling flag) and now splits them on the `$FF` marker the
interpreter itself dispatches on; and `menu_system.md` gained the option-value
pointer tables (`$C3:A44F`), which had only ever existed in the patch log.

⚠ **The lesson worth carrying: an invariant that cannot fail at the wrong
address is not checking the address.** Writing the negative control first is
what forced every table check to assert a shape instead of a plausibility.

**And the SATURN corpus, checked against BOTH cartridges** —
`tools/saturn/checksaturndocs.py`, **17 checks, 8 of them cross-game**, SKIPped
without the donor. It was the one body of documentation this project *built on*
and the only one gated by nothing.

| Was documented | Actually |
|---|---|
| universal-act scripts "byte-identical" | ~26/43 raw; **43/43 for five characters** once Super S's `0xC0` CMD steps are stripped |
| cel records "same sizes" | **97 of 98** — record 29 is `0x0500` vs `0x04E0` |
| cel banks "SMS `$D4` vs Super S `$D6`" | spans `$D4-$D6` and `$D6-$D7` |
| box-index writer `0x9FF1`, shift `+0x32C` | `0x9CCD + 0x32C = 0x9FF9`, and that is where the bytes are |
| OAM char table "52 entries" (both games) | **52 in SMS, 53 in Super S** — the extra one is the object-id shift's inserted type |
| her cels "contiguous" | contiguous **apart from 1,216 bytes of bank-boundary padding** |

Also measured and now written down: **Saturn is the only character whose two
palette pointers are stored in descending order**, and the Saturn tooling's
"pal1/pal2" are the game docs' "palette 0/1" (same bytes, different base).
Coverage: **25 of the corpus's 244 ROM addresses**. The rest is prose about
routines or `BUILDS.md`, whose subject is the built ROM rather than either
cartridge — so the honest ceiling here is low, and the checks that exist are the
ones the port actually rests on.

**Then the same treatment for the PATCH documents — checked against the
artifacts, not the cartridge.** Two more tools, both in `health.sh`:

* **`tools/checkpatchmap.py`** (needs the ROM + flips, ~1 s): applies all 19
  tracked standalone `.bps`, re-derives the edit-region map from the diffs both
  ways, and proves what the section is *for* — **the in-place regions are
  pairwise disjoint**, and **every bank-appending standalone starts at
  `0x280000`** (the reason chaining standalone BPS is forbidden). Also
  re-derives the 47 *"this .bps gives this ROM"* hashes in the registry docs.
* **`tools/checkknobs.py`** (needs nothing — runs in CI): reads every builder's
  `add_argument` statically and checks the knobs table both ways — documented
  flags exist, builder options are documented, defaults match.

| Was documented | Actually |
|---|---|
| patch 3: three bank-`$C0` "hooks" | two of them are **~97-byte in-place rewrites** |
| patch 15: 6 bytes | **7** (its own edit table listed 3+3+1) |
| patches 10/10b: header not mentioned | they **stamp the header title** |
| patch 4 standalone `f5337f9a…` (4 places) | **`7f9e8c76…`** (`--no-credit`: `1ac091e7…`) |
| knobs: patch 4 `--text` default `"FrenchName ver. 0.4"` | **`FrenchName v.0.22`** — `f"FrenchName v.{BUNDLE_VERSION}"` |

**And the training docs, read back out of the Lua** —
`tools/checktrainingdocs.py`, 11 checks, no ROM needed (CI). Hotkeys, menu rows,
labels, the package inventory and the self-test ids, each verified BOTH ways,
plus one check with no doc side: every hotkey must be bound to an action
something registers, since a key wired to a missing action is silently dead.

| Was documented | Actually |
|---|---|
| a **MEATY** label | removed 2026-07-20 (noise in live play); `labels.lua` says so, `training_test.lua` asserts it never fires |
| Lua menu: `gc chance` after `trigger` | the menu paints it after `ko reset` |
| patch 11 menu: `P1 HP` above `SHOW` | the ROM paints `SHOW` first |

⚠ A menu table in a doc **is** a claim about scroll order — it is what a reader
counts key presses against, so a row in the wrong place is a wrong instruction,
not a cosmetic slip.

⚠ **A recorded hash is a claim about a build, and a build includes its
DEFAULTS.** Patch 4's builder never
changed behaviour; its default subtitle did, when the bundle version became a
single source. Everything downstream — the standalone hash in four documents,
the knobs row — kept the pre-centralisation values. This is trap 15 (a builder
change invalidates every recorded recipe that contains it) reaching one step
further: *a default is part of the recipe.*

## What changed this session (2026-08-08)

* **`docs/` is split in two.** `docs/game/` is analysis of the retail ROM and is
  meant to be liftable by anyone hacking this game; `docs/project/` is this
  edition's own record. Rule for new files: *would this still be true, and still
  useful, to someone who had never heard of this project?*
* **New: `docs/game/sms_data_architecture.md`** — where the data lives and what
  shape it is, by memory (cartridge/WRAM/VRAM/ARAM), plus the object struct, the
  record catalogue, the pipelines, and §13, the list of what is NOT decoded.
* **New: `docs/game/characters/`** — a generated page per fighter
  (`tools/mkcharmap.py`, `--check`-gated), holding only what differs per
  character.
* **New: `docs/game/menu_system.md`** — the menu/font/text system as a reference;
  `menu_text.md` stays in `project/` as patch 16's log, and the game doc is
  authoritative where they overlap.
* **`sms_uranus_rom_map.md` retired → `sms_quickref.md`**, a one-page address
  card. The old name was a lie (one section of seven was Uranus-specific) and
  renaming alone would have kept a near-duplicate.
* **New: `tools/checkdocs.py`** — 31 checks that re-derive documented claims from
  the cartridge, negative-controlled, wired into `health.sh` (ROM-gated).
* **The page is published**: <https://definitelyfrenchname.github.io/SMS-FrenchName-edition/>,
  generated in CI by `tools/mkarchpage.py` (`--standalone` for a local export;
  the PDF is `--print-to-pdf` over that file).
* Registry sync: patch_notes gained patches 15/16/17/18 and the 100-series;
  patch 101 is recorded as SHIPPED; Saturn hashes corrected to v0.16.1.

### Corrections to ROM facts (all re-verified by hand, then by `checkdocs`)

| Was documented | Actually |
|---|---|
| 58 asset job records at `$C3:BE08` | **74**, `$C3:BD61-$C04B`, via two pointer tables (25 + 49) |
| nine on-hit variant tables | **ten** — `$C0:CED5` was missing everywhere |
| manifest = 22 B, four palettes | **16 B**: defense byte + five 24-bit pointers, **two** palettes |
| first-hit defense partly censused | complete: **Jupiter 1, Neptune 2, rest 0** |
| per-character proc blocks "~4.3 KB each" | exact, via the **`$C1:00A6` dispatch** (28 entries) |
| clean ROM "3 MB" | **2.5 MB** (40 banks, `$C0-$E7`); 3 MB is the patched size |

---

**2026-08-08 — DOCUMENTATION SYNC, no code or artifact changed.** The registry
docs had drifted from the artifacts: `patch_notes.md`'s deliverables table
stopped at patch 14 (15/17/18 missing, **16 had no section at all**) and still
called patch 101 "BUILT, NOT SHIPPED"; `patch_index.md` carried Saturn v0.14.15
hashes and a 49-check gate. All corrected, and **every number was re-measured
rather than transcribed** — releases `41d93a53…`/`b96f3fe8…`, Saturn dev build
`91639250…` (v0.16.1), patches 15/17/18 `31832e6e…`/`e5dd325b…`/`67897bbf…`,
patch 16 `c9ad4910…` (font only) / `257598c8…` (all four gates), Saturn gate
**ALL PASS (53 checks)**. Two audits swept the rest of `docs/` for claims HEAD
contradicts (~45 fixes: pruned bundles still in "Applying" blocks, deleted
builder knobs, resolved "open unknowns", the no-RNG-in-damage correction).
⚠ **A stale generated file was blocking the release builder** — `tools/README.md`
was out of date and `tools/build_rev.sh` preflights `mkindex --check`, so
`build_rev.sh both` aborted before building anything. Regenerated.

**2026-08-08 — A REAL DEFECT CAME OUT OF THAT AUDIT: patch 14's `--all-grabs`
knob needs going over.** Writing the data-architecture doc corrected five ROM
facts, which raised the fair question "did any shipped patch believe the wrong
one?". Four were docs-only (details in `HANDOFF.md` §0). The fifth line of
enquiry found this, measured on `clean + 13 + 14 --all-grabs` at Guts L3 using
patch 13's own throw phases:

| | patch 13 alone | + `--all-grabs` |
|---|---|---|
| throw that LANDS | 24 | **10** (scaled ✓) |
| throw that is **TECHED** | 12 | **12** (not scaled ✗) |

`$C1:0823` splits on the victim's mash count into two branches that both take
damage from DP `$05`, and only the landing one (`$C1:082F`) is hooked. So at high
Guts levels **teching costs the victim more than eating the throw**. **No shipped
build is affected** — every recipe calls `mkpatch14.py` bare — and this is
correct, deliberate behaviour for patch 13 alone. It is an incompleteness only in
patch 14's wider claim. Detail: `docs/project/patch_notes.md` § Patch 14.

**NEXT SESSION: TWO items — patch 16 is still the main work; patch 14 needs a
ruling before any code moves.** Patch 16 remains the active feature work;
patch 14 is a correctness review whose first step is a decision, not a patch.
**2026-08-06 shipped:** Options labels +
values (`SMS_P16_OPTIONS`), tournament select names + REPORT CARD labels
(`SMS_P16_DF`), stage names in caps + the char-select/config glyph delivery
(`SMS_P16_STAGES`) — all verified in-emulator, regression 45/45 at every
step. **Also shipped later the same day:** the whole VS config screen (row labels
via the relocated `$C3:7C00` map + all EIGHT MANUAL/AUTO records), the ACS
wheel (raster erase+stamp in the relocated `$C23400` art sheet — NO glyph
hook there, the runtime prompt bar references the blank `$5C0` tiles
through another BG's CHR base), PLAYER SELECT (a queued 19th row record —
no codec-2 work needed), and `SMS_P16_SATURN=1` for the Saturn stage name
(default OFF, maintainer's ruling — only for a future Saturn chain that
stacks this patch). **Remaining:** bracket VS names (script `$DF:A43E`,
port-written, no DMA trace — needs a VRAM write-watch); ACS name card +
prompt (runtime-drawn with name substitution; glyph window needs a census
first — the `$5C0` trap). Codec 2 (`$80:8E9A`) is partially decoded
(tile-unit codec, XOR row filters, 2-bit command stream) but nothing
shipped needs it. All mechanisms and traps: `docs/project/menu_text.md`. The issue-remediation programme is
COMPLETE (all 61 review issues resolved, tracker empty — record and lessons:
`HANDOFF.md` §0 + traps 12-18); everything else ships green. Dormant
maintainer options, not tasks: HANDOFF §8's fold-6/7/8-into-canonical and
the dash-distance retune.

---

## Patch 16 — where it stands

**Step 1 (font install) WORKS.** The half-width A-Z (built by
`tools/mkhalfwidth.py`, condensed from the game's own capitals) is installed
into the menu font sheet `$C4:2590` (extended 418 -> 512 tiles, relocated)
and **reaches VRAM tiles `$5C0-$5FF`** — read back out of VRAM, 56/64 (52/64
when it was 26 letters; today 29 glyphs, three with a blank half) vs 0 on clean. Builder: `tools/mkpatch16.py
<out.sfc>` (standalone A/B: clean -> `c9ad4910…` as of 2026-08-08; `d8f4ff1d…`
was the font-install-only build before the Options hook). Two
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
cell edits, verified through both highlight states. Builder A/B **on 2026-08-06**:
base `206fee3d…`, full Options translation `3cba4171…` (the builder has grown
since — see the 08-08 hashes above).

**Everything else for Options is ready:**
* Its tilemap is **asset record 19** (`$C3:69F0`).
* Budgets are measured off the live tilemap: **18 columns for a label, 6 for
  a value**; a half-width glyph is ONE map column. The maintainer's strings
  all fit.
* Addressing: MAP tile = VRAM tile − `$200`; a glyph is 2 rows,
  `bottom = top + $10`; labels attr `$0C00`, values `$1000`.
* The option VALUES are indeed not tilemap work — they are drawn by
  `$80:8C43` from self-describing records in bank `$C4` (uncompressed;
  found and translated 2026-08-06, see `docs/project/menu_text.md` § Values).

**Screen coverage (maintainer priority: Options ✓, Win, ACS, Tournament; story
out of scope):**
* **ALL FOUR screens are now probed** (`tools/probe_p16_screens.lua`, routes
  win/acs/tournament; full table in `docs/project/menu_text.md` § Screen census).
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

## Patch 14 — what "going over it" means

**Start with the decision, not the code.** The bug report writes itself, but the
fix does not: *should a teched command grab be scaled by Guts at all?* Both
answers are defensible — scaling it keeps the nerf honest, not scaling it keeps
teching a pure reward — and the code cannot choose. Nothing below is worth doing
until that is settled.

Then, in this order:

1. **Measure the one thing still inferred.** The default scope (command grabs
   only) *looks* unexposed because Uranus's SPD scripts toss immediately with no
   mash-sampling steps, so `+0x56` should never reach 2. That is read off the
   scripts, **not measured**. Drive an SPD and try to tech it. If it can be
   teched, the default build is exposed too and this stops being an optional-knob
   issue. (Related loose end found while reading: several per-character sites
   *set* `+0x56` to small constants — `a9 01 95 56` in Uranus's block at
   `$C1:8891`, `a9 04` in Moon's, `a9 06` in Mars's. That does not fit a plain
   mash counter and is not explained anywhere. Understand it before trusting any
   reasoning about when the tech branch is reachable.)
2. **Re-census the damage paths for patch 14's OWN scope** rather than inheriting
   patch 13's list — that inheritance is the root cause. Every writer of the HP
   field in the ROM, measured 2026-08-08, is: the 8 strike/chip sites patch 13
   hooks (`$C0:C09C/C16F/C216/C2C5/C47E/C551/C5F8/C6A7`), the throw toss
   (`$C1:0839`), **the throw tech (`$C1:085B`) — unhooked**, the drain tick's two
   stores (`$C1:0D5E` and its zero-clamp at `$C1:0D65`), and a scripted zeroing at
   **`$C1:0A62`** (`lda #$00 / sta $0049,Y`, next to a `$1E08` compare and a
   `+0x16 |= 0x20`) which **nobody has identified** — find out what it is before
   deciding it does not matter.
3. **If the ruling is "scale it":** the tech branch's tail (`$C1:0857 cmp #$90 /
   bcs / sta $0049,Y`) has the same 7-byte shape as the two tails patch 14 already
   hooks, so the existing stub pattern applies almost unchanged. Mind that the
   tech path *adds* a negated half rather than subtracting, so the stub's
   "recover dmg from hp_before − A" arithmetic needs its sign checked, not
   copied.
4. **Fix the test, don't break it.** `test_p13_guts.lua`'s `tech-immune` phase
   asserts `dealt == 12` and is *correct* for patch 13 alone. It must become
   dual-mode (12 without patch 14 or without `--all-grabs`, scaled with it) —
   the same shape as the suite's other dual-mode rows. A fix that simply makes
   that phase fail has broken a true assertion.
5. **Prove the shipped builds did not move.** The default (no `--all-grabs`) path
   must rebuild **byte-identically**: Rev. S-02 `41d93a53…`, Rev. SS-03
   `f71421d8…`. That is the gate that says this was a knob fix and not a
   balance change.

**The rule this came from, worth carrying:** patch 14 inherited patch 13's site
list instead of re-deriving one for its own, wider claim. **A patch that widens
another patch's scope must re-census the paths for the new scope.** It is trap 5
(count the sites in the image you ship) applied to scope rather than to banks.

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
tools/saturn/verify_saturn.sh                           # 60 checks (QUICK=1 ~4 min)
ROM=<rom> tools/run.sh tools/test_regression.lua 900    # 60/60 (45 on clean)
tools/health.sh                                         # no ROM/emulator needed
python3 tools/mkpatch16.py <out.sfc>                    # patch 16 (font install)
ROM=<p16 build> POKE=1 tools/run.sh tools/probe_menu_vram.lua   # step-1 verify
```

## Session hygiene

**The measurement rule first — `CLAUDE.md` §"THE MEASUREMENT RULE": any data
comes from measurements, never guesses, and being sure is the signal to measure
rather than the licence to skip. No number reaches a doc, a commit or a plan
without a run that produced it this session; a number someone else reports is a
filed count, not a measurement.**
Then: commit per finding; `.sfc` gitignored (rebuild from BPS); **never commit game
imagery or audio** (screenshots never, savestates yes); never patch in place;
every timing/behaviour claim emulator-verified; all Saturn/Super-S material
stays in the `saturn/` subfolders; during multi-agent work, `git add`
explicit paths only. (Earlier editions of this file are in git history —
including the full remediation batch tables.)
