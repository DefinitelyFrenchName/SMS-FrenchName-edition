# HANDOFF — SMS Sailor Moon S balance/feature patch project

**Read this first.** §0 is the CURRENT state (SMS + Saturn); §1 onward is the completed base patch project. (New session? `docs/project/NEXT_SESSION.md` is the 60-second orientation.) It is the operational map: current state, deliverables, how to build,
how to test, what was learned, and the traps. Deep per-patch detail is in
`docs/project/patch_notes.md`; **how the engine works, by subsystem, is in
`docs/game/sms_engine_internals.md`** (the synthesis — read it to understand or modify the game);
**where the data lives and what shape it is, in `docs/game/sms_data_architecture.md`**
(the four memory maps, the object struct, the record formats);
the A.C.S. stat system in `docs/game/sms_acs_system.md`; the damage system end-to-end
(counter-hit/punish, posture tables, apply-site census, desperation compendium data) in
`docs/game/sms_damage_system.md`;
address-level notes in `docs/game/annotations.md`; the verified ROM map in
`docs/game/sms_quickref.md`. Persistent findings also live in the memory file
`uranus-patch-state.md`.

Game: **Bishoujo Senshi Sailor Moon S: Jougai Rantou!?** (SFC, Japan).
Clean ROM SHA-1 `bc0e29ee383574443226695215496eb0d09aaa1c` (HiROM+FastROM, headerless).
HiROM mapping: **file offset = SNES address & 0x3FFFFF**.
Playable roster (charID): 1 Moon, 2 Mercury, 3 Mars, 4 Jupiter, 5 Venus, 6 Uranus,
7 Neptune, 8 Pluto, 9 Chibi Moon. **Saturn (10) is not in the clean ROM** — she is
ported from Super S and is playable in the **Rev. SS** builds only (§0).

---

## 0. Current state (2026-08-09) — SMS + Saturn = PATCH 100, and the issue backlog

**2026-08-09 (session close) — TWO NEW GAME DOCS, A DRAWN FRAME, AND THE PIPELINE
WRITTEN DOWN.** Four things landed after the checking programme below:

* **`docs/game/sms_sound_system.md`** — the audio path end to end, game-side and
  re-measured: the IPL upload (`$C0:EBD4`/`$C0:EC5E`, a **40-record** block table
  at `$C0:ECE7` whose ids 22-30 are the nine character-select voices), the SPC
  driver — which is **stored in ROM at `ARAM + 0x23F804`**, so its tables are
  ordinary ROM addresses — the sfx table (**95** usable ids), and the pitch
  pipeline. ⚠ **Pitch is per-sound and character-specific**: voices are
  instruments `≥ $30`, which skip the instrument record entirely (SRCN = the
  byte, ADSR and tuning hardcoded), so the only pitch control is a **signed
  transpose byte in each sound's own sequence** — the roster spans −6..+4
  semitones and no two fighters share a set. The doc carries the full census and
  `checkdocs` re-derives every cell of it. Three older numbers were corrected on
  the way (22→40 records, 94→95 ids, and "36 blocks" was counting IPL chunks).
* **A drawn frame page** (`tools/mkenginepage.py`, published at `/frame.html`) —
  see the entry below; its finding, that **hit resolution is not a stage of the
  loop**, corrected `sms_data_architecture.md` §10B.
* **`docs/project/how_patches_are_built.md`** — the build pipeline explained,
  because it was my tooling and documented nowhere. The correction it exists to
  make: a builder writes a COMPLETE patched `.sfc` and **flips DIFFS** it against
  clean to make the `.bps` — it never injects. Its worked example (patch 12's
  hook, stub, bank and hash) is re-derived by `checkpatchmap.py`.
* **Saturn's round-won badge is now recorded as open work** (below).

Checkers at session close: **`checkdocs` 87** (+4 from the badge work: the
tile-word table and the `$E0:0000` job table, both negative-controlled at a wrong
base), `checkpatchmap` (19 patches + 48 hash claims + the pipeline example),
`checkknobs` 15, `checktrainingdocs` 11, `saturn/checksaturndocs` 17. All in
`health.sh`, all negative-controlled.


**2026-08-08 (later) — THE DOC CHECKS ARE NOW GENERATED, AND FIVE MORE ROM FACTS
WERE WRONG.** `checkdocs` went from 31 hand-written checks to **76**, because
hand-writing one per claim does not scale to 254 distinct ROM addresses. Three
mechanisms replace the typing: a **table registry** (15 documented tables, each
declared with a validator for its shape — box pointers, the four animation
layers, the modifier jump tables, the throw structures, the special records, the
menu value records, both cursor-navigation tables); **claims extracted from the
prose** (`tools/docaddrs.py` — file-offset transcriptions, quoted byte runs and
quoted instructions, 30 checks nobody wrote); and an **address census** that
prints how much of `docs/game/` any check actually re-derives (**105/254**, plus
123 in the generated character pages; a `health.sh` NOTE, never fatal, because
the honest weakness of a checker is the claims nobody checked and a number that
is never printed never moves).

⚠ **Every table validator is re-run at a WRONG base and required to fail.** That
one rule is what makes the registry worth having: it forced each check to assert
a *shape* — strides, orderings, cross-table contiguity, the fact that the story
nav table routes to none of 6/7/8 — because "the pointers look plausible"
survives a two-byte shift, and a check that survives a shift would go green on a
rotted address. The extractors get the same treatment on synthetic lines each
run, since a family that has stopped matching passes every claim it no longer
finds.

**And then the SATURN corpus, which is checked against BOTH cartridges** —
`tools/saturn/checksaturndocs.py`, 17 checks (8 cross-game), SKIPped without the
donor. This was the one body of documentation the project *built on*: every
claim in `supers_map.md` became a line in a builder, and none of it was gated.
⚠ **Four claims in the identity paragraph the port rests on did not survive.**
"Universal-act scripts byte-identical" is true only after Super S's `0xC0` CMD
steps are stripped (raw: ~26/43; stripped: **43/43 for five characters**,
41-42 for the rest) — the doc asserted the conclusion in one sentence and the
caveat two paragraphs later. "Cel records same sizes" is **97 of 98** (record 29:
`0x0500` vs `0x04E0`). The cel banks span `$D4-$D6` / `$D6-$D7`, not one each.
And the box-index writer row contradicted itself — `0x9FF1` with shift `+0x32C`,
when `0x9CCD + 0x32C = 0x9FF9`, which is where the identical bytes are. Two
facts were measured and written down while checking: the OAM char table holds
**52 entries in SMS and 53 in Super S** (the extra one corroborating the
object-id shift; the doc said 52 for both), and **Saturn is the only character
whose two palette pointers are stored in descending order**. Her cel census
holds to the byte, with one refinement: contiguous apart from **1,216 bytes of
bank-boundary padding**. Coverage is 25 of the corpus's 244 ROM addresses — the
rest are prose about routines, or `BUILDS.md`, whose subject is the built
artifact rather than either cartridge.

**The same treatment was applied to the PATCH documents, which are checked
against the artifacts rather than the cartridge.** Two more tools, both in
`health.sh`:

* **`tools/checkpatchmap.py`** — applies all 19 tracked standalone `.bps` and
  re-derives the edit-region map from the diffs: every documented range is
  exactly a changed run and every changed run is documented, both ways. It also
  proves the two things the section exists to say — **the in-place regions are
  pairwise disjoint** (measured across all 19, not asserted), and **every
  bank-appending standalone starts its bank at `0x280000`**, which is the whole
  reason a bundle must be built by chaining the BUILDERS and never by applying
  standalone BPS in sequence (§5). And it re-derives every *"this .bps gives
  this ROM"* hash in the registry documents — 47 of them.
* **`tools/checkknobs.py`** — reads every builder's `add_argument` statically
  (`ast`; the parsers live under `if __name__ == "__main__":`, so there is
  nothing to import) and checks the knobs table both ways: documented flags
  exist, builder options are documented, defaults match. Needs no ROM, so
  unlike almost everything here it runs in CI.

**And the TRAINING docs, checked against the Lua package** —
`tools/checktrainingdocs.py`, 11 checks, no ROM (so it runs in CI), covering the
Lua trainer and patch 11's in-ROM menu. ⚠ It found a **MEATY label the usage doc
still promised**, gone since 2026-07-20 (`labels.lua` says so in its header and
`training_test.lua` asserts it never fires — only the doc had not been told),
and **two menu row orders that did not match the menus** (the Lua trainer's
`gc chance`, patch 11's `SHOW`/`P1 HP`). A menu table in a doc is a claim about
scroll order, which is what a reader counts key presses against.

⚠ **They found four more wrong things.** Patch 3 was described as three "hooks"
when two of them are **~97-byte in-place rewrites**; patch 15 changes **7 bytes,
not 6**; patches **10/10b stamp the header title** and were not documented as
touching the header; and **patch 4's recorded SHA-1 was stale in four places**
(`7f9e8c76…`, not `f5337f9a…`). The last two are one story: patch 4's builder
never changed, its **default subtitle** did, when the bundle version became a
single source — and the knobs table still carried the pre-centralisation default
(`"FrenchName ver. 0.4"`). **A recorded hash is a claim about a build, and a
build includes its defaults.**

⚠ **Five documented facts died** (re-measured by hand, then locked): a
special-move record is **7 bytes, not 8** — the "+7 strength-ish" field is the
next record's attackID, masked off by a 16-bit `lda $0006,Y`; the 16-bit
`stz $47,X` is at **`$C1:0E4F`**, not `$C1:0E51` (four places, three documents);
the config dispatcher's tail is **`jsr ($BB6D,X)`**, not `jmp`; the bank-`$DF`
engine has **eight** screens, not nine (a builder comment); and Uranus's toss Y
velocity is **−$0580**, written `-$FA80` in one doc. Two fixes fell out:
`mkcharmap.py` printed toss records and hold scripts under one heading, so a
toss header's *damage* read as the hold step's mash-sampling flag (now split on
the `$FF` marker the interpreter itself dispatches on), and `menu_system.md`
gained the option-value pointer tables, which had only existed in the patch log.

**2026-08-08 (session close) — DOCS RESTRUCTURED, AND THEY ARE NOW CHECKED
AGAINST THE CARTRIDGE.** `docs/` is split: **`docs/game/`** is analysis of the
retail ROM, meant to be liftable by anyone hacking this game, and
**`docs/project/`** is this edition's record (`saturn/` sits there whole). New in
`game/`: `sms_data_architecture.md` (the four memories, the object struct, the
record catalogue, the pipelines, and §13 — what is *not* decoded), `menu_system.md`
(the front end as a reference; `menu_text.md` stays in `project/` as patch 16's
log), `characters/` (a generated page per fighter), and `sms_quickref.md`, which
replaces the misnamed `sms_uranus_rom_map.md` — one of its seven sections was
Uranus-specific, so renaming alone would have kept a near-duplicate.

**`tools/checkdocs.py` is the new gate that matters here: 31 checks that
re-derive documented claims from the ROM**, each asserting the claim is still in
the doc before testing it, negative-controlled both ways, and wired into
`health.sh` (ROM-gated, SKIP not silent-pass). It exists because rewriting
documentation is exactly where a plausible sentence can replace a measured one.
It found one error on its first run — **mine, in the check, not in the docs**.
Two other generated things joined the same discipline: `tools/mkcharmap.py`
(`--check`) and the GitHub Pages workflow, which renders
`tools/mkarchpage.py` on every push rather than committing a built page
(<https://definitelyfrenchname.github.io/SMS-FrenchName-edition/>). **A second
page joined it 2026-08-09** — `tools/mkenginepage.py` at `/frame.html`, one
in-match frame disassembled stage by stage with every patch pinned to the stage
it hooks; it is linked from `docs/game/README.md`, the quickref card,
`sms_engine_internals.md` §3 and `sms_data_architecture.md` §10B, because a page
nothing links to is a page nobody finds.

⚠ **Six documented ROM facts were wrong and are corrected** (all re-verified by
hand, then locked by `checkdocs`): the asset job table is **74 records** across
two pointer tables, not 58 at `$C3:BE08`; there are **ten** on-hit variant tables
(`$C0:CED5` was missing everywhere); the manifest is **16 bytes — a defense byte
and five pointers**, with **two** palettes, not 22 bytes and four; the
first-hit-defense census is complete (**Jupiter 1, Neptune 2, rest 0**); bank
`$C1` is carved by the **`$C1:00A6` proc dispatch**; and the clean image is
**2.5 MB**, not 3 MB — 3 MB is the *patched* size, and that figure was hardcoded
prose inside `mkrelease.py`, the generator whose whole job is not transcribing.

**The one behavioural finding is patch 14's, and it is unfixed by choice** —
`--all-grabs` does not scale a TECHED throw (measured: 24→10 landed, 12 teched at
Guts L3, so teching costs more than eating it). No shipped build passes the flag.
It needs a maintainer ruling before code moves: `docs/project/NEXT_SESSION.md`
§ "Patch 14 — what going over it means".

**2026-08-08 — DOCUMENTATION SYNC (maintainer request), everything re-measured.**
The registry docs had drifted from the artifacts in three ways, all now fixed:
`docs/project/patch_notes.md` still called patch **101** "BUILT, NOT SHIPPED" (it ships, on
by default, and the listening A/B that cleared it is recorded); its deliverables
table **stopped at patch 14**, so 15/17/18 were absent and **16 had no section at
all**; and `docs/project/patch_index.md` still carried Saturn **v0.14.15** hashes and a
**49**-check gate. Nothing was transcribed — every number written was produced by a
run today: both releases rebuild to `41d93a53…` / `b96f3fe8…`, the Saturn dev build
to `91639250…` (v0.16.1), patches 15/17/18 to `31832e6e…` / `e5dd325b…` /
`67897bbf…` (each tracked BPS round-tripping to the same), patch 16 to `c9ad4910…`
(font only) and `257598c8…` (all four screen gates), and
`tools/saturn/verify_saturn.sh` to **ALL PASS (53 checks)**.
⚠ **A stale GENERATED file was blocking the release builder**: `tools/README.md` was
out of date (from the maintainer's `mkpatch5.py` docstring edit), and
`tools/build_rev.sh` preflights `mkindex --check`, so `build_rev.sh both` aborted
before building anything. Regenerated. This is trap 17 in its intended form — the
generated check caught real drift, and it caught it by refusing to build.
⚠ **Terminology corrected throughout:** "canonical" names the **v0.7 lineage**, not
what ships. Both reference builds and both releases carry patch **1b** (gate `0x05`,
true combo), never patch 1.

**2026-08-08 — NEW REFERENCE DOC: `docs/game/sms_data_architecture.md`** (maintainer
request) — where the game's data lives and what shape it is, organised by the four
memories (cartridge, work RAM, video RAM, audio RAM) rather than by discovery
order: the bank map, the object struct byte by byte, box data, manifests, the
record catalogue, the four pipelines, an inventory of free space, and §13, an
explicit list of what is **not** decoded. A visual companion renders the memory
maps as SVG (`tools/mkarchpage.py`, published as an Artifact). Censusing the ROM
for it disproved five doc claims, each re-verified by hand: the asset job table is
**74 records** across two pointer tables (not 58 — a flat-scan artifact); there are
**ten** on-hit variant tables (`$C0:CED5` was missing everywhere); the manifest is
**16 bytes, five pointers, two palettes** (not 22/four); the **first-hit-defense
census is complete** (Jupiter 1, Neptune 2, rest 0); and bank `$C1` is carved by a
previously undocumented **28-entry proc dispatch at `$C1:00A6`** that gives every
character's proc block an exact address.

**AND THAT AUDIT FOUND A REAL DEFECT — patch 14's `--all-grabs` misses the throw
TECH branch.** The fair question after correcting five ROM facts is "did a shipped
patch believe a wrong one?". Four were docs-only: the ten-table correction could
not have hidden a Guts hook (proved by enumerating **every** HP writer in the ROM —
13 sites, all accounted for), and patch 3 never indexes the manifest with a slot
≥ 2 because it replaces the vanilla palette fetch outright. But re-censusing the
grab paths showed `$C1:0823` splits on the mash count into two branches that both
read damage from DP `$05`, and **only the landing branch is hooked**. Measured at
Guts L3: a throw that lands scales **24 → 10**, a throw that is **teched stays
12** — so teching costs the victim more than eating it. Correct and deliberate for
patch 13 alone (its `tech-immune` test pins it); an incompleteness only in patch
14's wider claim. **No shipped build passes `--all-grabs`**, so Rev. S-02 /
SS-02 / REF v.1 / v.2 / v0.22 are unaffected. **Not fixed — it needs a maintainer
ruling first** (should a teched command grab be scaled at all?); the full brief is
`docs/project/NEXT_SESSION.md` § "Patch 14 — what going over it means", detail in
`docs/project/patch_notes.md` § Patch 14.
⚠ **Trap 19, and it is trap 5 applied to scope:** patch 14 inherited patch 13's
apply-site list instead of re-deriving one for its own, wider claim. **A patch
that widens another patch's scope must re-census the paths for the new scope.**

**Numbering (2026-08-04, maintainer):** the whole Super S body of work is
**patch 100**, and the voice-pitch correction is **patch 101**. The gap from 16
is deliberate — 100+ is a different CATEGORY of work, built and gated by
`tools/saturn/` rather than by `mkpatchN.py` and the fingerprint-detected
regression rows. Registry rows: `docs/project/patch_index.md`. Renumbering is
documentation only: REF v.1 (`2873f214…`), REF v.2 (`6d79fb5f…`) and patch 100
(`03b73cdd…`) were all rebuilt and are **byte-identical**.

**Patch 101 (voice pitch) is SHIPPED and ON BY DEFAULT** (2026-08-05). Field
verdict: her pitch is correct; a Moon facing her is three semitones flat (the
shared-transpose limitation — the sound ids are char 1's — **accepted**); other
characters show no downpitch or only mild. `SATURN_PITCH=0` builds patch 100
alone and reproduces `03b73cdd…` byte-for-byte. One finding stays recorded but
un-chased: the retune also moves DSP voices 1/2/6 by the same intervals; the
field test is what cleared it. Detail: `docs/project/patch_notes.md` "Patch 101".

**The nameplate shows SATURN** (2026-08-05). The name under the health bar used
to be the shell's. Two `$EE` stubs at the two charID reads (`$C0:D720`/`$C0:D747`)
return index 0 for her, and her name is written into the two tables' free index-0
slots — `$D8AE` left-aligned for P1, `$D926` right-aligned for P2. No glyph work
was needed: the nameplate alphabet turned out to be fully resident, correcting a
note in `docs/game/annotations.md`. `SATURN_NAMEPLATE=0` gives a blank plate instead.

The base patch project below is complete and green; active work is the **SMS +
Saturn** effort (brief: `docs/project/saturn/PROJECT.md`, test ROMs:
`docs/project/saturn/BUILDS.md`, next steps: `docs/project/NEXT_SESSION.md`).

**Saturn is playable in SMS**, summoned by holding **L+R** while confirming a
**Uranus, Neptune or Pluto** slot (she wears that character as a "shell"). The
hidden code is the **only** char-select variant — the v0.10.0 visible slot-10
build was retired 2026-08-04 and its code deleted (a placeholder that added the
one char-select surface the story lock exists to avoid; removal proven inert by a
byte-identical rebuild). Current build on **REF v.2** is **v0.16.1**: hidden
`91639250…`, hidden+stage `c8f7dae8…` — patch 100 + 101 + the nameplate,
the projectile fix, her selectable palettes (all below) and **her two ground
throws fixed** (§ below). **v0.15.0 (= v0.14.15 + patch 17) was built, played
and RETIRED the same day** — the maintainer found
the tenth stage visually distracting, so patch 17 stays optional and standalone;
the builder still reproduces v0.14.15 byte-for-byte with the hook in place but
off (`SATURN_ALLSTAGES=1` opts in and tags the version **S**). The previous
v0.14.9 pair `7db39c48…`/`3120d75a…` still rebuilds byte-for-byte from the prior
builder revision.

**HER GROUND THROWS ARE FIXED (v0.16.1, 2026-08-05) — both faults inherited
from Super S.** Field report: the two throws are on each other's buttons, and
the punch grab's 6/4 directions are reversed as well. Both reproduced before
anything was touched. The first lead was **a red herring worth recording**: her
button-map record (`$C1:174E`) differs from the common one by exactly one
swapped pair, which looks like the answer — but the +0x51 move-request pipeline
is never written during a throw at all, so it is unrelated. What decides is a
**4 x 8-byte close-throw table indexed by attack button** (`$C1:C84A` via
`$C1:055A`; index 2 = HP, 3 = HK, the record's last byte is the act), and hers
has the two throws in each other's slots. The direction is a second, separate
datum: `$C1:07E5` reads a 5-byte toss record and **negates X for a left-facing
thrower**, so the record holds the FORWARD velocity — hers is `$FA80` = -1408,
i.e. backwards, where every SMS record is positive. Fixed by swapping the two
records, and the direction by **reading 6 and 4 the other way round for that one
throw** — a 19-byte stub in her `$C1` copy re-inverts the facing bit at
`$C1:0619` when the act is `$7B`, leaving the animation, the turn-around and the
toss velocity vanilla. ⚠ **v0.16.0 got the direction wrong and is retired:** it
negated her toss velocity instead, which produced the *same measured outcome*
and still read wrong in play, because she no longer turned around. **Matching
the measurement is not the same as matching the request** — the ask was "map 6HP
to 4HP", not "make the victim land in front". Both byte patterns were confirmed
byte-identical in the **Super S ROM** first, so this corrects the original game,
not the port. Mechanism: `docs/game/sms_engine_internals.md` §8; detail:
`docs/project/saturn/BUILDS.md` 0.16.1. `SATURN_THROWFIX=0` restores the old behaviour.

**The 214P projectile bug is FIXED (v0.14.11, 2026-08-05).** It was a
**per-shell truncation of her effect sheet**: the build stages her 0x1040-byte
sheet over the shell's in `$7F:0000`, but the DMA that follows was sized from
the **shell character's own** sheet — Uranus `$11C0` and Pluto `$10C0` are big
enough, **Neptune is `$0E60`**, so 15 tiles (`$113-$121`) never reached VRAM and
kept whatever the previous match left there. Her 214P travel pose draws 7 of its
12 sprites from exactly that range, which is the field report *two disconnected
blue pieces instead of one shape* — on a Neptune shell, intact on Uranus. Fix:
the DMA stub's armed path also forces the length (`sta $004305`), proved safe in
both directions from the full round-load DMA map. Verified: her sheet is now
byte-identical to the decoder output in VRAM on shells 6/7/8 (130/130 tiles;
Neptune was 115/130) and the projectile composes as one flame. The **P2** side
was measured too, not assumed: P2-as-Saturn was equally broken and now matches
P1 exactly — and since P2's own transfer is `$0FC0`, P2 was short on *every*
shell. Detail, and the four instrumentation failures that made this take five
attempts, in `docs/project/saturn/BUILDS.md` § "214P projectile: SOLVED".

**THE THROW CORRUPTION IS FIXED FOR REAL (v0.14.14, 2026-08-05).** v0.14.7
fixed the OAM flood; the sprite stayed wrong until now, and no build between
v0.14.8 and v0.14.13 differed by a pixel. Cause: v0.14.7 hooked the two reads of
the per-victim thrown-pose table on the documented basis that the ROM has
**exactly two** — true of the CLEAN ROM, false of the BUILD. Bank `B_C1` is a
full copy of `$C1` carrying her ported proc block, and **the copy is taken before
the hook is applied**, so it kept two vanilla reads (`$F7:0735`/`$F7:0C51`).
**With SATURN AS THE THROWER** her proc runs out of that copy, the unhooked read
indexes the ten-entry table with charID `$1C` (0x38 bytes past — the original
bug), and the victim's pose is garbage. Saturn vs Saturn with 6P is the clearest
case: poses `$55/$88/$B5`, the stub never entered, screen-wide debris. A vanilla
thrower was always fine, which is why every A/B built on "Jupiter throws Saturn"
passed. Fix: hook the same two in-bank offsets in `B_C1`; the builder now asserts
**no** read of that table is left unhooked anywhere in the assembled image.
⚠ **Generalises: patch a bank and you must patch its COPIES, and "N sites exist"
is a claim about a specific image — re-verify it against the one you ship.**
Detail: `docs/project/saturn/BUILDS.md` § "ROOT CAUSE AND FIX (v0.14.14)".

**Her palettes follow the confirm button as of v0.14.12** (maintainer request).
Her transform copied palette 0 unconditionally, overwriting the slot the
character select had loaded — she looked identical on every button and her
second canon Super S palette, embedded since v0.5.0, had never been on screen.
Two facts made this less obvious than it looks: **Super S ships only TWO
palettes per character** (both games' char-select dedup writes 0 or 1; the
"four manifest palette pointers" are char pal 0, char pal 1, the 8-byte icon
palette and the effects palette), and **a Saturn player can never reach slots
0-3** — summoning her needs L+R held, and L/R are patch 3's palette modifiers,
so her reachable slots are 4-7. The copier now reads `$1D02`/`$1D05` and MASKS
the slot, giving A=violet B=blue Y=green X=near-black (gold until v0.14.15 — the field found it low-contrast; teal was rejected on measurement, it separates by hue not luminance); slots 2/3 are authored by
rotating only her costume ramp, since Big Zam has no Saturn to lift extras from.
Verified per button and on both players. Detail: `docs/project/saturn/BUILDS.md` v0.14.12.

⚠ **The earlier "root signature" was measured through the wrong VRAM.** It
resolved a sprite's tiles as `tile * 32`; the OBJ name base is word `$6000` with
the second name table at `$7000`. Correctly resolved, all 12 sprites always
pointed at valid tiles. It did name the right sprites, though — that part stands.

**Gate before shipping anything: `tools/saturn/verify_saturn.sh`** — 60 checks
(regression suite, L+R arming across modes x shells incl. flag/latch, story lock,
2P VS on both pads, throws normal + command with OAM-flood and stage-VRAM
assertions, the projectile palette split, **her effect sheet's cross-shell
invariance**, **her four selectable palettes**, **throws with SATURN AS THE THROWER**, the lrmodes harness, a randomised stress match, and an OBJ-palette
census over a full match). Exits 1 on failure; `QUICK=1` for a ~4-minute subset.
Sanity-checked against known-bad builds: on v0.14.6 the quick matrix fails 7 of
16, and on v0.14.8 the new effect-sheet check fails — a gate that cannot fail is
not a gate. That check was added *because* the 45-check gate passed on the build
carrying the projectile bug for two weeks.

**Patch 17 (all stages selectable) is DONE and confirmed (2026-08-05).** The
tenth stage — なかよし編集部, the Nakayoshi editorial department — is selectable
like any other and joins the random pool. Two edits: one byte turns the menu
bound's `sta $1F59` into `stz` (`$C3:BADE`), and patch 3's random-stage rider,
which bounds itself with `A %= 9`, gets both operands raised to 10 — located by
signature in the image being built, since retail has **no** random stage picker
at all. Measured: 9 stages clean vs 10 patched, the stage loads, the menu draws
its name; RNG forced to 9 gives stage 0 without the pool edit and stage 9 with
it. The independent control is the game's own cheat: holding **X+L+R** over the
title (`$C3:B8B4`) gives the same ten stages on a CLEAN ROM, so the patch
removes a condition rather than inventing content. `build/sms_allstages.bps`
(`e5dd325b…`), playable bundle `build/sms_ref_v2_allstages.bps` = REF v.2 + 17
(`e8fc6045…`); regression 42/42 clean+17 and 57/57 REF v.2+17. **Not folded into
REF v.2 or the Saturn line** — that renames a published artifact, maintainer's
call — and the maintainer, having played v0.15.0, ruled it **out** of both:
the stage is "a bit distracting visually", so patch 17 stays optional. The
Saturn builder keeps the hook off by default (`SATURN_ALLSTAGES=1` opts in,
tagging the version **S**), and reproduces v0.14.15 byte-for-byte without it.
Detail: `docs/project/patch_notes.md` § Patch 17, `docs/project/saturn/BUILDS.md` 0.15.0.

**RELEASES — two reference builds (2026-08-05, maintainer request).** `build/`
holds every patch flat, which is right for development and wrong for a player,
so the two things anyone actually applies now live in **`release/`**:

| | |
|---|---|
| **Rev. S-NN** | the reference build, no Super S content (REF v.2's patch set + 18) |
| **Rev. SS-NN** | the same, plus Saturn (patch 100/101 + her ported stage) |

**Rev. 02** is current (`41d93a53…` / `b96f3fe8…`); **01 was superseded before
release** — it predates patch 18, and a revision names one set of bytes for good,
which is the whole point of printing it on the title screen. Its `.bps` are gone
from `release/` so there is only ever one thing to apply.

`NN` comes from `smspaths.REV` (override `SMS_REV=NN`) and is printed on the
**title screen** — the naked-eye tell a pad tester quotes back. One recipe builds
both, `tools/build_rev.sh s|ss|both`, so the two cannot drift apart: they are the
same patch chain up to the subtitle and the Super S additions. Release notes are
**generated** (`tools/mkrelease.py`, `--check` in CI-style use) because this
project has already shipped three stale doc hashes; every hash there is measured
from the file it names. REF v.1 and v.2 keep their own recipes — published
artifacts are never redefined. Rev. 01 was REF v.2 / Saturn v0.16.1 retitled and
nothing else — measured, the whole diff being patch 4's bank `$E9` plus the
checksum; Rev. 02 adds patch 18 (12 bytes) on top of that.
**Patch 17 is in NEITHER** (maintainer, 2026-08-05): it stays an optional
standalone in `build/sms_allstages.bps`. If it is ever wanted in the Super S
reference, `SATURN_ALLSTAGES=1` on the Saturn step is the whole change.
⚠ The title font had no `S` or `-`; both were authored in `texttiles.py`. The
strip is **168 px** and "FrenchName Rev. SS-99" renders **146 px**, so the
naming has 22 px to spare — two digits is nowhere near the limit.

**GITHUB ISSUE REMEDIATION — COMPLETE (2026-08-06, single day).** 63 open
issues from two adversarial cross-model reviews (#2-#58 in 2026-07-28,
#59-#105 in 2026-08-04) were triaged against HEAD (6 already fixed, 8
partial, 47 valid), then all 61 real issues resolved across four batches;
the maintainer closed the two tracking meta-issues (#57/#106) and the
tracker is EMPTY. Per-issue verdicts live in the `Fixes #NN` commits and on
the closed issues; the generalisable lessons are traps 12-18 below. The
tree-wide machine-specific-path sweep that followed found and fixed three
stragglers (17cefe6).

**THE PROGRAMME IS COMPLETE (2026-08-06):** all 61 real issues from both
adversarial reviews are resolved; only the two tracking meta-issues (#57,
#106) remain open. **Batch 4** (duplication/dead code/conventions — 18
issues) closed it out: boxlib.py + saturn/gfxlib.py dedups, mksaturn_smoke's
three ad-hoc assemblers replaced by asm65816 (byte-identity-gated incl. all
env variants; two lesser assembler-class sites recorded on #98 as follow-up),
hitstun unified at 0x10-0x18 across 12 hand-rolled sites, 77 saturn bare
asserts and 237 silent io.open sites swept, #35 closed by measurement
(~2.2 µs/frame for the whole HUD), trainer.lua kept deliberately standalone
(maintainer decision). Earlier: **batch 1** (integrity — #79 #81 #82 #83 #59
#60 #65 #66 #13), **batch 1b** (#24 #61 #62 #3, #63 rescoped), **batch 3**
(docs/registry — #67 #68 #74 #103 #52 #75; mkindex recursive +
self-checking, run.sh takes `$MESEN`, scriptTimeout measured INERT under
--testrunner, 50 probe headers corrected), and **batch 2**
(2026-08-06: #87 #92 #91 #86, then one commit per issue for #88 #90 #96 #94
#89 #80 #97 #69 #76 #71 #18 #93; #84 refuted by measurement). Convention:
**one commit per issue** (`Fixes #NN`) — the two batch commits are deliberate
exceptions the maintainer chose to keep rather than split verified history.
Batch-2 artifacts that moved: p10b `745ea0bc…` (#86/#88/#93 chain), p11
`a3aba30d…` (#90); suite growth: tier1 65 checks (reset-hitstop), training
T11 (reload clears framedata), plus probes p88/p89/p93.

Two findings from batch 1 that changed how this repo is verified:
* **The published verification procedure could report a run that never
  happened.** `mkrelease.py` writes "run the regression suite, then
  `verify_saturn.sh`" into the release notes; the suite APPENDED to
  `traces/regression.txt` and the gate discarded the emulator's exit status and
  read `tail -1` of it. Both halves are fixed — the log truncates and names its
  ROM, and `run()` in the gate deletes each trace and records the exit status.
* **A gate check had been passing on a trace no run produced.** The stress check
  read `stress_1m.txt` while the run writes `stress_7m.txt` (the probe names its
  log by seed). It had been green on a leftover from an old experiment.

⚠ **A "cross-model verified" issue can still be false** — #84 was confirmed by
both models against the cited lines and does not reproduce; the fix was written,
disproved by its own test, and reverted (detail: trap 11 below and the #84
issue thread). For
the remaining batches: build the failing case BEFORE the fix, and prove the
working path is unchanged after.

**SATURN'S ROUND-WON BADGE IS DONE (v0.17.0, 2026-08-09)** — her medallion is
Super S's own, in her own colours, on both players and every shell.
`3dee7316…` (hidden, on REF v.2). Brief: `docs/project/saturn/PROJECT.md`
§ "DONE — her round-won badge"; the game-side mechanism is now in
`docs/game/annotations.md` § "Round-won badge".

The badge's top-left cell comes from a **ten-entry table at `$C0:E166`**
(`charID*2`; the code derives the other three cells as `T+1`/`T+$10`/`T+$11`, and
P2 ORs `#$0400` to move BG3 palette 6 to 7). Id `$1C` read **0x38 past the end,
into code** — measured, her cells held `1E0A 1E0B 1E1A 1E1B`, pointing at a tile
past the 512-tile sheet whose CHR happens to be blank. "Nothing" was luck.

⚠ **EIGHT read sites, not two, and six of them are P2 or redraw paths** — so a
two-site fix would pass the one-round P1 test anyone writes first. The count was
taken before a line of the fix was written, and a build-time tripwire asserts
zero surviving reads anywhere in the image. That is traps 5/19 being *paid
forward* instead of paid for.

⚠ **Her tiles were in the donor all along, stored RAW** — Super S keeps the
in-match HUD sheet uncompressed at `$E0:D2B8` while SMS compresses it at
`$E0:21E6`, and **503 of the two sheets' 512 tiles are byte-identical**. Every
compressed-stream search came back empty for that reason alone. Her medallion
goes into SMS's own sheet at `$CE`/`$CF`/`$DE`/`$DF` — Super S's own slots, blank
in SMS. Two previously undocumented systems fell out and are now in `docs/game/`:
the **in-match asset job table at `$E0:0000`** (6-byte `[src16][srcbank][vram16]
[flags]`, nothing to do with the `$C3` records) and that sheet.

⚠ **Trap 6 applied and answered:** the job record carries **no length** — the DMA
is sized by what the decoder wrote — so the builder asserts the re-encoded sheet
still expands to exactly `0x2000`, and the gate asserts the tiles arrive
identically on both sides and every shell rather than on the one that was tested.

⚠ **A new compressor was needed and the old one was left alone.**
`sms_lz.encode` is literals plus one distance-2 RLE trick; it *expanded* the
sheet from `0xF31` to `0x1B95`, which would have forced a relocation. New
`encode_lz` (an optimal parse over the format's real back-references) reaches
`0xF0E` — smaller than the vanilla stream — so the edit stays in place. `encode`
is deliberately untouched because patch 16 and the movelist call it and their
hashes are recorded (trap 21); both patch-16 hashes rebuild byte-identical.
`SATURN_BADGE=0` differs from v0.16.1 by **exactly the two version-string bytes**.

**One pre-existing overlap this drew out — cosmetic, one frame, not open work:**
patch 10b's left status label occupies `$10E5-$10EC`, and a player's **second**
round-won badge occupies `$10C4/$10C5/$10E4/$10E5`; they share `$10E5`. But a
player holds **at most one badge in normal play** — the second round win ends the
match (best-of-3, or one round in tournament) — so the second badge exists only
for the deciding-win frame at match end. It can surface only on **v0.22** (the
one bundle with 10b) with a status label live at that instant; no Saturn build
carries 10b. Recorded for completeness.

**Open work — patch 16 is the ONLY active item (next session is dedicated to
it; full brief in `docs/project/NEXT_SESSION.md`). Dormant maintainer options, not
tasks: §8's fold-6/7/8-into-canonical and dash-distance retune.**

**Patch 16 — menu translation. Step 1 DONE; step 2's Options screen WORKS
(2026-08-06).** The half-width A-Z reaches VRAM (tiles `$5C0-$5FF`, read back
out of VRAM, 56/64 non-blank vs 0 on clean — 52/64 in entries written before the
punctuation glyphs were added). Two things had been wrong and both
are fixed: the asset-record layout is `[vram16][len16][src24][dest24]` — the
upload LENGTH sits 2 bytes BEFORE the src pointer (field `$C3:BF18`, `$3480` ->
`$4000`), and the kanji block is not loaded on the screen being translated
(that screen's sheet is `$C4:2590`).
**The Options blocker is solved, and the diagnosis rewrote the record:** the
designated buffer dump showed `$7E:C000` staged correctly the whole time — the
glyphs DID reach VRAM, at MAIN-MENU entry (the transfer earlier attributed to
Options), and the Options transition **clears all 64KB of VRAM** (fixed-source
DMA at `$80:8191`) then runs its own loader (`$C3:A4DD`, straight-line
`lda #idx*2 / sta $1C18 / jsr` per record) which never re-uploads the font.
Fix in `mkpatch16.py` (always on): the loader's first load is JSL-hooked to a
60-byte stub that replays the two JSL-able primitives (`$80:927D` decompress,
`$80:92AD` DMA) for the font record FIRST — order preserved so the screen's
text sheet (`$C3:48D0` -> tiles `$2C0-$529`) keeps winning the overlap.
Verified: VRAM census 0/64 -> 52/64 across the stub's transfer, settled;
`SMS_P16_OPTIONS=1` renders the six English labels (screenshot-checked);
button-config re-verifies green on the hooked build. Mechanism + asset-record
plumbing (pointer tables `$C3:BCCD`/`$BCFF`, font = B index 15):
`docs/game/menu_system.md` (how the system works) and `docs/project/menu_text.md`
(this patch's working record); probe: `tools/probe_p16_options_buf.lua`.
The option **values** are translated too (2026-08-06): the runtime writer is
`$80:8C43`, drawing self-describing records `[vmadd][len][rows][cells]` from
bank `$C4` via pointer tables `$C3:A44F/$A457/$A45B/$A463` ($1B14/$1B16 =
value*2, one record per value per highlight state) — uncompressed, so 12
in-place cell edits (`OPT_VALUES`). Verified in-emulator through both
highlight states + all 12 decoded from the built ROM.
**Win and ACS are not yet probed**; Tournament's sheet needs re-checking (the
"shares the extended sheet" note predates the loader finding). Priority:
Options ✓, Win, ACS, Tournament; story out of scope.

*(The voice-pitch item that stood here is DONE — patch 101, shipped and on by
default. The "one routine shared with the music" that blocked it was a misread
PC: `$131D`/`$1327` are the `INC Y` inside a DSP shadow flush and compute
nothing. Pitch is per-sound NOTE data.)*

**Guard the thing that ARMS, not the thing that acts (v0.14.8).** The shell
restriction started life in the helper, at the transform — but the select voice,
the in-match sound remap and the effect-tile/palette override all key off the
**flag**, which the char-select confirm stub sets much earlier. A disallowed
shell therefore armed everything except the one thing that was guarded. The rule
now lives at the confirm (cursor charID `$0000,y`), the confirmed id is recorded
in `$7F:F10A/F10B` so the round-load arming route can apply the same test, and
the helper guard is the last line. A feature with several consumers keyed off one
flag is only as gated as that flag.

**She has her own voice as of v0.13.0** (task #44 closed): her win laugh, 236P,
214P and j.632K, injected as a fifth data layer. SMS voices a fighter from a
private ARAM bank (P1 `$B700`, P2 `$DB00`) **plus** a per-character BRR
directory that is resident from boot at `ARAM $34C0 + (charID-1)*32` — so
loading her samples was only half the job, and the directory needed patching
too. She borrows **char 1's** sound ids on whichever side she plays and the
build overwrites char 1's half-record for that player only (the halves are per
player, so it can never collide with a real Moon), restoring it on any
non-Saturn load. One fixed id set, no per-shell code. Mechanism, corrections and
acceptance evidence: `docs/project/saturn/sound_scope.md` § PHASE 3. **Field-confirmed
2026-08-03** ("a bit weird but definitely the right ones and not distracting").

**v0.13.1 adds her character-select line** ("Yoroshiku", Super S `$EC:C12F`,
2610 bytes). SMS already voices every sailor on confirm from a bank-id table
(`$C0:AE75`, id = 21 + charID) whose single sample goes to ARAM `$B700` and
plays through a fixed directory entry — so she needed only the bank id swapped,
no sound-id change and no directory patch. The player is identified from the
three per-player writers of `$1B1E`, since `$1B1E` itself names the CHARACTER
and she can wear any shell. **Field-confirmed.**

**v0.13.2 gives her HER OWN MOVELIST** (#41). It could not be lifted: Super S has
neither `$C0:916B`'s codec nor these tilemaps — the first Saturn asset where the
two games genuinely diverge. So the codec was decoded and made writable
(`tools/saturn/sms_lz.py`; all nine vanilla lists decode to exactly 0x800 and
both encoders round-trip) and her list is authored from SMS's own font
(`tools/saturn/mkmovelist.py`), 595 compressed bytes selected by a per-player
hook on the two table reads at `$C0:8B59` / `$C0:8B81`. Detail and font tables:
`docs/project/saturn/movelist.md`. **Not yet seen by the maintainer in normal play** —
check it on a BRIGHT stage, since the one bug it hid was body text missing the
priority bit and rendering behind the background.

**#43 (the ported stage) is FIXED in v0.13.6 — by reading SMS's own copy of the
stage.** SMS ships this stage already (scene 1 = its Silver Millennium), and it
composes it exactly like Super S: sky BG1.0, palace BG2.1, ground BG1.1, with
the fighters drawn over the priority-1 ground. That is possible because SMS
draws its fighters at **OBJ priority 3 on nine of ten stages** — and at **2 only
on stage 2**, the slot the port targets. The source is the scene script, which
has FOUR parts rather than two (`[records..FF][palettes..FF][third list..FF]
[$6F][$8F][$A2]`, read at `$C0:85C8-85FC`); `$8F` is the sprite-attribute byte
and the port never carried it. That one byte is why the castle covered the
fighters, why the priority bits were stripped, and why every layering fix since
was working around a missing configuration byte. v0.13.6 copies `$8F`
(0x10→0x18) and repoints the scroll entry to `$C0:B42F` (SMS's own routine for
this stage) — no priority stripping, layer merge, plane swap, tile compositing
or rewritten scroll code. It now matches SMS's own version measurement for
measurement. **v0.13.5 was a bad build** (broke scrolling speed and input) and
is reverted. `docs/project/saturn/supers_assets.md` §#43.

**Field-confirmed 2026-08-03:** her **movelist renders clean** in normal play
(#41 closed) and the **character-select voice shows no regression**.

**REF v.2** (2026-08-02, maintainer request) = REF v.1 **+ patch 15 (AUTO
removal)** = 1b+2+3+4+5+7+8+9+12+13+14+15. Recipe `tools/build_ref_v2.sh`, ROM
`6d79fb5f…`, regression 57/57. **v.1 is deliberately unchanged** — it is a
published artifact with a recorded hash, so v.2 is a new name rather than a
redefinition. `tools/saturn/build_refsaturn.sh` now targets v.2 by default
(`REF_VERSION=1` selects the old base).

Shipped for Saturn recently: card portrait (art, layout and palette),
push-collision fix, corrected sfx mapping, a Super S stage ported onto Pluto's
slot, her voice (in-match and the character-select line), and **her own
movelist** — authored from SMS's font, since Super S shares neither the codec nor
the data — and the stage's jump slide (#43). Next: the extended scope (menu
translation; showing Saturn before round start).

**Why she wears a shell rather than being a tenth character** — and why more
ROM would not change that: `docs/project/saturn/memory_and_shell.md` (the four memories
with measured budgets, the nine-wide-table census, and what a true tenth entry
would actually cost). Short version: ROM is not scarce (384 KB spare), ARAM is
the only hard wall, and the real constraint is per-character tables sized to nine
and immediately followed by live data.

**Twenty-one traps this project paid for — they generalise** (12-18 are the
2026-08-06 issue-remediation programme's distillate, per-issue evidence in
the `Fixes #NN` commits; 19 came out of the 2026-08-08 data-architecture audit,
and 20-21 out of the generated doc and patch checks the same day):

1. **Per-character fixes must be tested with at least TWO shells.** Saturn can
   be summoned over Uranus, Neptune or Pluto (over any of the nine before
   v0.14.5). A hook keyed to *Uranus's* sprite-list pointer worked only for that
   shell and looked like two unrelated bugs. **Paid for twice:** the 214P
   projectile bug (v0.14.11) appeared only on Neptune, so five build bisections
   run on one shell all correctly reported "identical" and one of them was
   published as a finding before being retracted.
2. **Unreferenced, unchanging memory is not free memory.** A candidate ARAM
   region passed both "nothing points at it" and "identical across runs" and was
   still live — proven by finding its bytes in ROM bank `$E4`. Ask where bytes
   came from; on this console everything is uploaded from ROM.
3. **Data handed to a vanilla routine must respect the WRAM-mirror rule.** The
   sprite emitter writes the OAM shadow with plain absolute stores, so a list in
   bank `$EE` (no WRAM mirror) vanished entirely; it needs the `$AE` alias.
4. **An engine convention verified in one context is not verified in another.**
   `$88` is the current object in the proc dispatch, so the voice hook reused
   `ldx $88` — but during script interpretation it holds whatever object last
   set it, and Saturn's voice came out of the opponent's slot. The interpreter
   already had the object base in X. Check where a value gets SET.
5. **Patch a bank and you must patch its COPIES.** The build grafts a full copy
   of `$C1` into an appended bank for Saturn's proc; a hook applied to `$C1`
   after that copy is taken protects only half the paths. "The ROM has exactly
   two of these" was measured on the CLEAN ROM and was false of the artifact
   — the throw corruption survived four sessions behind that one assumption.
   Count sites in the image you SHIP.
6. **A per-player OVERRIDE is only as complete as the transfer that carries it.**
   Staging her effect sheet over the shell's was correct and provably byte-exact
   in WRAM — and 15 tiles still never reached VRAM, because the DMA's LENGTH came
   from the shell. When you substitute data, ask what else was sized from the
   thing you replaced. (v0.14.11; the same question is open for patch 16.)
7. **Address a tile through the OBJ name base, never as `tile * 32`.** Base is
   word `$6000` (byte `$C000`), second name table at word `$7000`. A whole "root
   signature" was measured out of unrelated VRAM this way.
8. **Sprite lists are emitted on ALTERNATE frames.** A capture triggered N frames
   after an event lands on an empty frame half the time. Trigger on the thing you
   want to see, not on a delay — and note `emu.getState()` throws inside a memory
   callback here, silently killing the hook, so never let a probe's own counter
   sit downstream of it.
9. **A probe that reports nothing is usually broken, not evidence of nothing.**
   Three separate cases this session: a movelist search that missed because a
   tilemap interleaves tile+attribute; "the character never jumps", which was the
   entrance and the GO! banner rather than an input fault (the pad read correctly
   the whole time); and a step function that threw on a nil and printed "done"
   having logged only its header. Prove the harness sees the thing before
   concluding the game does not do it. **Corollary (2026-08-03): a probe that
   reports a feature REFUSING everything is usually not testing what it thinks
   it selected.** SHELL_GUARD "blocked 6/7/8" because the harness's char poke
   never survived the load; one exec hook reading the byte the guard reads
   settled it. Assert the precondition (here: `$1000` == the shell you asked
   for) before trusting the verdict.
11. **A verified issue report can still be false, and the evidence can be
   accurate.** #84 was filed by one model, confirmed by another against the cited
   lines, and does not reproduce: every quoted line says what it is quoted as
   saying, but the failure needs a frame ordering BETWEEN two files that neither
   file shows. The fix was written first and disproved by its own test on the
   UNFIXED build. Build the failing case before the fix; if it passes without
   the fix, you have learned something better than a patch.
10. **Matching the measurement is not the same as matching the request.** The
   throw-direction fix (v0.16.0) made the victim land on the correct side and
   passed every check written for it — and was wrong, because the maintainer had
   asked to *swap which input triggers which throw*, not to change where the
   victim goes. The two differ by one visible thing the metric never captured:
   whether she turns around. When a request names a MECHANISM ("map 6HP to
   4HP"), implement that mechanism; a different mechanism with the same
   measurable outcome is a different feature.
12. **Anything thrown inside a Mesen memory callback dies WITHOUT A MESSAGE —
   assert included.** #46's celebrated `assert(io.open(...))` fix never worked:
   the "fixed" script hung to timeout exactly like the unfixed one, message
   swallowed (#80, measured). The only reporting form in that context is
   `print(...); emu.stop(1)`. Corollary of trap 8, now the rule: nothing that
   can throw belongs in a memory callback without its own escape hatch — and a
   fix whose effect was never OBSERVED (only reasoned about) is not fixed.
13. **Before fixing a probe's reported defect, prove the probe does ANYTHING.**
   inputprobe's filed bug (double-registered callbacks) was real — and
   unreachable, because the probe had never logged a single line in its life:
   its range covered bank $00 while this game reads pads from the $80 mirror
   (#97). Sharpens trap 9: run the tool and demand output BEFORE reading its
   code for the filed defect, or you will fix dead code correctly.
14. **Before narrowing a "wasteful" trigger, find out what the waste protects —
   then move the COST, not the trigger.** The label glyph font re-uploaded
   every idle vblank (#93); the obvious fix (re-arm on transition instead of
   every idle frame) would have drawn match 2's first label with a wiped font,
   because the per-frame re-arm is what survives per-match CHR reloads. The
   shipped fix kept the re-arm and made the upload lazy instead.
15. **A builder change invalidates every recorded RECIPE that contains it —
   check what a builder feeds before touching it.** Batch 2's fixes to
   patches 10b/11 silently broke `build_v022.sh`'s recorded hash; nothing
   flagged it until the recipe was re-run for an unrelated reason. Rule: on
   changing a builder, enumerate the bundles whose recipes chain it, rebuild
   them, and either re-record as lineage (the maintainer's precedent — v0.22
   `3bb9c829` → `e6b999b5`) or surface the decision. Published artifacts are
   still never redefined; recipes drift, artifacts don't.
16. **Byte-identity is the refactor gate — and it must cover EVERY variant
   path, not the default.** The whole batch-4 dedup (boxlib, gfxlib, five
   rounds of assembler conversion, the assert and dead-code sweeps) was safe
   because every change was gated on unchanged output hashes INCLUDING each
   env knob that alters emitted bytes (SHELL_GUARD/STORY_GUARD/SATURN_VOICE/
   …/stacked SATURN_BASE — ten whole-ROM A/Bs for #98 alone). A default-path
   A/B is trap 1 wearing builder clothes: knob-gated bytes are the shells.
17. **Counts in filed issues are stale in BOTH directions — re-measure at HEAD
   before working one.** Bare asserts: filed 66, found 77. Dead CLEAN_SHA1:
   filed 13, found 16. "Two remaining" assembler sites undercounted twice
   (parts 4 AND 5 each found more). Conventions accrete violations unless a
   generated `--check` is wired into the gates — mksigs held for months while
   hand-counts rotted, and mkindex `--check` caught its first real staleness
   within an hour of landing. Sweep + enforcement land together or the sweep
   is a snapshot.
18. **A documented knob either works or does not exist — and "works" is a
   measurement.** `reversal_lead` was documented in two user docs and read by
   nothing (#18, deleted); `--debug.scriptWindow.scriptTimeout` was passed on
   every run and measured INERT under --testrunner — every Lua entry is capped
   at a hard 1 s whatever value is given (#52, flag removed). The flip side is
   equally valid: #35 was closed BY measurement (the whole HUD stack costs
   ~2.2 µs/frame), because its own bar forbade landing unmeasured
   optimization. Measure the knob, then keep it, fix it, or delete it —
   never leave it documented and dead.
19. **A patch that widens another patch's scope must RE-CENSUS the paths for the
   new scope.** Patch 13 hooks the damage-apply sites for specials and
   desperations, and its site list is complete for that. Patch 14 reused that
   list while claiming something wider ("`--all-grabs` nerfs EVERY grab path"),
   and the throw-TECH branch — a *separate* branch of `$C1:0823` that never
   passes through the hooked site — was never in patch 13's scope to begin with,
   so it was never in the inherited list. Measured result: at Guts L3 a landed
   throw scales 24 → 10 while a teched one stays 12, inverting the incentive to
   tech. This is trap 5 ("count the sites in the image you SHIP") applied to
   scope instead of to banks, and it is worth stating separately because the
   inherited list was *correct* — correct for a smaller claim. When you widen a
   claim, re-derive the evidence for it; do not inherit evidence gathered for
   the narrower one. (Found 2026-08-08; unfixed pending a maintainer ruling.)
20. **A check that cannot fail at the WRONG address is not checking the
   address.** Every table check in `checkdocs` is re-run at base ±1/±2 and must
   object; writing that negative control first is what turned each one from "the
   pointers look plausible" — which survives a two-byte shift, and would have
   gone green on a rotted address — into a claim about a *shape*: strides,
   orderings, cross-table contiguity, "the story nav table routes to none of
   6/7/8". The same rule caught the other half: generated check families are
   negative-controlled on synthetic lines, because an extractor that quietly
   stops matching passes every claim it no longer finds, and a family that finds
   nothing is indistinguishable from a family that verified everything. This is
   trap 18 ("a documented knob either works or does not exist") pointed at the
   verification layer itself.
21. **A recorded hash is a claim about a build, and a build includes its
   DEFAULTS.** Patch 4's standalone SHA-1 was stale in four documents and its
   knobs row named a default subtitle from two versions earlier — and the
   builder's behaviour had never changed. What changed was `--text`'s default,
   when the bundle version became a single source (`f"FrenchName
   v.{BUNDLE_VERSION}"`), which silently moved every hash of a default build.
   Trap 15 says a builder change invalidates the recipes that contain it; this
   is one step further out — **a default is part of the recipe**, so centralising
   a constant is a builder change even when no code moves. Enumerate what a
   default feeds before you make it a variable.

---

## 1. The base patch project (record as of 2026-07-30) — all green

> **Read §0 for the current state.** This section is the base project's record and its
> counts are of that date: sixteen patch entries (14 patches + 2 variants). Since then
> patches **15, 17 and 18** shipped and **16** (menu translation) is in progress, so the
> registry is nineteen entries (17 patches + 2 variants) plus the 100-series —
> `docs/project/patch_index.md` is the authority. "Canonical v0.7" names the original **lineage**;
> what ships today is `release/` Rev. S-02 / SS-02, which carry patch **1b**.

**2026-07-30 — patch 4 credit line (maintainer request):** `mkpatch4.py` now also swaps
title-screen copyright line 1 to the Big Zam edition's **"©MOONLIGHT FIGHT SOCIETY"**
(pixel-identical — 54 tiles lifted verbatim from BZ title VRAM, 3 extra DMA runs over
VRAM tiles 0x0C2–0x0FC; line 2 "©ANGEL 1994" untouched, © glyph shared/skipped).
Default ON; `--no-credit` reproduces the old subtitle-only build byte-for-byte
(`e5dce7d5…`). New standalone `sms_title.bps` → ROM `f5337f9a…` *(both hashes are
of that date; the default subtitle now carries `BUNDLE_VERSION`, so today's are
`7f9e8c76…` / `1ac091e7…`)*, regression ALL PASS
(40). Detail: docs/project/patch_notes_title.md. **Both bundles rebuilt with the credit line
(2026-07-30, same recipes — pre-rebuild recipes first re-validated byte-for-byte
against the old hashes):** v0.22 `52bc7e38…` → **`19a7fc0d…`**, REF v.1 `bd1104ee…` →
**`7ab26db4…`**; diffs vs the old bundles confined to patch 4's bank $E9 + checksum;
suites green (59/59 v0.22 incl. EXPECT=all, 55/55 REF); title tells unchanged — the
credit line is the naked-eye tell for the rebuilt ROMs.

**2026-07-30 — tooling de-hardcoded (repo-relative paths):** all 124 Lua tools now
bootstrap `tools/sms_env.lua` (runtime repo-root discovery; see §5) and every Python
builder anchors to the repo via `__file__` — the whole toolchain runs from any cwd and
any checkout location (still macOS-assumed). Verified: all 14 builders reproduce their
tracked-BPS ROMs byte-for-byte from a foreign cwd; demo_link (new headless wrapper
`demo_link_headless.lua`) reports the canonical single-MEATY window; training suite
T1–T10 green on v0.7; regression ALL PASS on clean. Bonus: the builder hash audit
exposed three STALE doc hashes, now fixed (p11 `42add705`→`574d4948`, p13
`04e13428`→`6be3d788`, p14 `b90b8fd6`→`0ce0806f` — the BPS had been rebuilt in later
QA rounds without updating the docs; the tracked BPS were always self-consistent).

**2026-07-30 — configurable ROM location:** the clean/Big Zam ROM directory is now
resolved at runtime (`tools/smspaths.py` + `run.sh`): `$SMS_ROM_DIR` → `roms/` →
`../roms/` (above the tree, the maintainer's preferred anti-commit layout). All three
paths + the missing-ROM error verified; full 16-output builder hash audit green after
the refactor.

**2026-07-30 — adversarial-review remediation (issues #2–#57), batches A–C:** see the
GitHub tracker for per-issue evidence; every fix commented and auto-verifiable ones
closed. Key operational changes:
- **`--stacked` is now REQUIRED on every chained builder step** (unconditional SHA gate,
  #12); `src == out` is rejected (#56); the §2 chain examples and the new committed
  bundle recipes `tools/build_v022.sh` / `tools/build_ref_v1.sh` /
  `tools/build_ref_v2.sh` (#10) reflect this.
- **Dedup policy (maintainer ruling, 2026-07-30):** common tooling that no patch alters
  is CENTRALIZED (smspaths.py: ROM paths, SHA gates, `fix_checksum`, `trim_banks`,
  `next_bank`/`write_bank`; probelib.lua: emulator-access helpers for the standalone
  suites; sms_env.lua: Lua path discovery; mksigs.py: detection fingerprints) —
  patch-specific logic stays in each standalone builder, and no object-model
  abstractions are introduced that don't NEED to exist (argparse blocks stay
  per-builder; one-shot archival probes keep their local helpers).
- Regression suite is a real gate: exits 1 on failure (#2), pre-flights fixtures (#4,
  the 6 missing ones are force-added), detects never-fired checks (#7), tracks HP
  per-player (#16), detects both p1 gates (#29 — REF reads p1=Y(gate 05)).
- Guts resets on TIMED-OUT rounds (#21, A/B frame-advance proof, probe_p13_timeout.lua).
- Builders: checksum fix in all 14 (#9 — hung at power-of-two sizes), donor validation
  (#8), bank guards (#27), p14 damage-table clamp (#41), p10 counter caps at 99 + flag
  validation (#36/#37), p11 glyph list derived from p10 (#42; fixed a real bundle bug —
  label episodes re-uploaded T over p11's M slot — and gave the ADV display a real
  minus glyph that had silently rendered blank).
- STANDALONE HASHES CHANGED: p1 `258ffd4e`, p1b `deefccec`, p2 `14f747a7` (checksum now
  fixed, #14 — chain outputs unaffected since later builders recompute it), p10
  `be072a5e`, p10b `920652df`, p11 `e9ac2205`, p13 `bafb87d4`, p14 `5fadcaca`.
  (Moved again on 2026-08-06: p10b to `4899790a…` when the label pipeline was
  brought under `--modes` — issue #86 — then to `83defe1e…` when repeated
  events were made to refresh the label TTL — issue #88 — then to `745ea0bc…`
  when the glyph font became a lazy upload instead of one DMA per idle vblank
  — issue #93; p11 to `a3aba30d…` when a reset requested during hitstop
  stopped being swallowed — issue #90. The list above is the 07-30 record.)
  Bundles: v0.22 `3bb9c829…` (since 08-06: `e6b999b5…`), REF v.1 `2873f214…`. Canonical v0.7 `24aa6b6d…`
  unchanged (reproduced byte-for-byte with the new builders).
- Suite-count note: v0.22 full run counts differ slightly from the 07-25 numbers only
  via EXPECT cfg (58 + static-expect-all = 59) — see §4.

**2026-07-30 — "SMS + Saturn" project started (docs/project/saturn/):** prep + first probes
done. Super S ROM validated (SHA 1ada3417…, resolved via smspaths.supers_rom());
engines proven same-but-shifted (char loader +0x18, on-hit +0x12A, matrix +0x148 with
identical contents; WRAM identical — all probed); Saturn loads via char-select poke
(fixture traces/saturn/saturn_vs_uranus_supers.mss), her box tables extracted
(docs/project/saturn/supers_all_boxes.json), her far-5HK unblockable CONFIRMED empirically
(hits through held guard 34-44px; 5LP control blocks). Route recommendation: **A —
port Saturn into SMS** (docs/project/saturn/feasibility.md has the evidence + de-risk probes).
Saturn-reference rule §5 has a scoped exception for this project.

**2026-07-30 (later session) — all four Route A de-risk unknowns RESOLVED:**
(1) **Guard bug root-caused + fixed**: proximity guard is armed by the pose-record
class byte (class 9 = threat; system in docs/project/saturn/supers_map.md §Pose records);
Saturn's far-kick startup poses are the roster's only class-0 attack poses. **Fix =
1 byte per move** ($84:9289 far 5HK / $84:927D far 5LK+close 5HK, 00→09),
A/B-validated: blocked when guarded, still hits when not. (2) **Animation pipeline
fully decoded** (3 layers: scripts $C0:0000 → pose records $84:809F → cel tables
$CB:0000 + DMA kicker $80:A21A); (3) **Saturn cel census done**: 115 cels, 136.7 KB
contiguous $DD:0D40-$DF:34E0; (4) **"handler block" doesn't exist** — the engine is
data-driven (+0x51 move-request pipeline, generic starters/interpreters); exec-
coverage bounds her exclusive code at ~630 B (1 of 5 specials driven; ≤2-3 KB
extrapolated). New probes: probe_supers_guardfind/guardpose/posetiming/guardfix/
movereq/coverage.lua. Route A confidence: HIGH. SMS's three animation-layer twins
located + live-verified (scripts $C0:0000 / poses $84:809C / cels $CB:0000;
probe_sms_animtables.lua 241/241 ALL PASS; Uranus content byte-identical across
games). **Port bundle extractor: `tools/saturn/extract_saturn_unit.py`** → 19 components,
157 KB, `build/saturn/unit/` (gitignored) with manifest (rebase rules, guard-fix
offsets, TODOs); tripwire-asserted against the measured ground truth.

**2026-07-30 (same day, smoke milestone) — SATURN ANIMATES + RENDERS IN SMS:**
`tools/saturn/mksaturn_smoke.py` (from-clean scaffold builder, NOT a patch) injects her
four data layers as free object id 0x1C; `probe_sms_saturn_smoke.lua` = 228/228
ALL PASS, idle/walk animate, sprites fully coherent (traces/saturn/saturn_smoke_*.png
— regenerate locally; screenshots are game art and are NOT committed, see
.gitignore; Uranus palette — palettes unported). En route: a 4TH animation layer
(OAM sprite layout, $84:8000 table system) discovered + decoded + extracted, and
a CORRECTION: per-char proc blocks DO exist (~4.3 KB each; Saturn $C1:C6F7; the
07-30 'no handler block' claim was a baseline-contaminated measurement). Full
detail: feasibility §Smoke, supers_map §OAM + §per-char proc blocks.

**2026-07-25 — patch 10 field report fixed + REF v.1 bundle:**
- Maintainer reported the combo counter never appears and status labels never disappear
  (v0.21 + p10 standalone). Two root causes, both fixed in `mkpatch10.py` and A/B-verified
  in-emulator (`tools/probe_p10_vs.lua`): (1) label expiry tested a stale Z flag after
  `sta` — blank path unreachable, labels stuck forever once MEATY (removed 07-20) no
  longer churned them; (2) the counter's mode gate excluded `$008D`=2 (1P-vs-COM) — dead
  in the most-played mode. Default `--modes` now `0,1,2,4,5`; `--ttl` knob wired (was
  dead). Counter verified healthy in 2P VS pre- and post-fix (true chains only, by
  design); it can NEVER show in practice — the hooked producer `$C0:D5E8` doesn't run
  there (`probe_p10_practice.lua`; p11/Lua training modes have their own counters).
- New oracles: `test_regression.lua` p10-combo-counter now asserts VRAM show→count→clear;
  `test_labels.lua` asserts the label blanks within TTL+10f. Old tests were WRAM-only and
  stayed green through both bugs.
- **v0.22** all-patches bundle (`52bc7e38…`, title "v.0.22") = 59/59; labels PASS
  (drawn@84 blank@131); perf 2.24% worst-case. `perf_patch10_cfg.lua` STUB_F recomputed
  (`$EA:06E6`).
- **REF v.1 reference bundle** (maintainer request): 1b+2+3+4+5+7+8+9+12+13+14 —
  true-combo gate, no p6/p10/p11. Patch 12 kept: without it p13's Guts grant is
  unreachable in normal play (misfire needs ochame stat, 0 in all normal modes) and p14
  is inert. `build/sms_reference_v1.bps`, ROM `bd1104ee…`, title "FrenchName REF v.1"
  (uppercase E/R glyphs added to `texttiles.py`), regression 55/55 (detection:
  p1 reads absent — fingerprint pins gate 0x04, harmless).
The 2026-07-20 "L+R doesn't open the p11 menu" field report is **RESOLVED** — maintainer
confirms L+R, taunts, and the Guts specials/desperation nerf all work as intended on the
latest patches. 2026-07-21: fixed a Lua training-mode bug where HP regen never fired
after projectile-special damage (framedata move machine stuck; see §4 and
`docs/project/NEXT_SESSION.md`).

**2026-07-24/25 housekeeping:**
- **Git history was REWRITTEN TWICE** (`git filter-repo`, force-pushed).
  **2026-07-24:** `mockups/` (title-screen PNGs containing copyrighted art) purged.
  **2026-08-04:** ALL remaining image blobs purged — ten paths, including three at
  pre-reorg locations (`traces/saturn_smoke_*.png`) that a HEAD-only cleanup would
  have missed; removal was done by extension GLOB across all history, not by path
  list, so nothing could be overlooked. Verified: HEAD tree byte-identical before
  and after (`bf0ddc2f…`), zero image paths in all history, 293 commits in and 293
  out. **Every commit hash changed at BOTH rewrites**, so any hash quoted in
  docs/notes from before 2026-08-04 refers to superseded history and won't resolve. Any stale clone must re-clone or
  hard-reset to the new remote, never push its old history back.
- `patch11-training-rom` was **merged into `main` and deleted** — `main` is the only
  branch and carries everything (all 14 patches, tooling, docs).
- Maintainer added a root **`README.md`** (public-facing intro + a copy of the
  deliverables table — keep it in sync with `docs/project/patch_notes.md` when patches change).
- Docs refreshed to the 14-patch era: patch_notes.md front matter (deliverables/
  edit-region map/knobs/applying incl. the 2026-07-19 bundle prune), CLAUDE.md banner.

> One-page registry with status/lifecycle (deprecation candidates, exclusivity,
> dependencies): **docs/project/patch_index.md** — keep it updated when patches change.

| # | Patch | Builder | Standalone BPS |
|---|---|---|---|
| 1 | **Infinite → 1-frame meaty (CANONICAL)** | `mkpatch.py 0x04` | `build/sms_uranus_infinite_1f.bps` |
| 1b | Infinite → true 1-frame combo (alt) | `mkpatch.py 0x05` | `build/sms_uranus_infinite_1f_truecombo.bps` |
| 2 | Remove reversal-dash invincibility | `mkpatch2.py` | `build/sms_dashfix.bps` |
| 3 | Big Zam palettes + "FrenchName" header | `mkpatch3.py` | `build/sms_palettes.bps` |
| 4 | Title subtitle text + BZ "©MOONLIGHT FIGHT SOCIETY" credit line | `mkpatch4.py` | `build/sms_title.bps` |
| 5 | Forward-dash distance −1/3 | `mkpatch5.py` | `build/sms_dashdist.bps` |
| 6 | Forward-dash i-frames (OPTIONAL) | `mkpatch6.py` | `build/sms_dashinvuln.bps` |
| 7 | Pluto 5HP hits crouchers (OPTIONAL) | `mkpatch7.py` | `build/sms_pluto5hp.bps` |
| 8 | Venus 6HP throw tech window 6f→13f (OPTIONAL) | `mkpatch8.py` | `build/sms_venustech.bps` |
| 9 | Neptune Deep Submerge fireball hitbox tracks sprite (OPTIONAL) | `mkpatch9.py` | `build/sms_neptune_ds.bps` |
| 10 | In-match combo counter, base game (OPTIONAL) | `mkpatch10.py` | `build/sms_combocounter.bps` |
| 10b | + status labels GC/REVERSAL/PUNISH/TECH (OPTIONAL; MEATY label removed 2026-07-20) | `mkpatch10.py --events labels` | `build/sms_combolabels.bps` |
| 11 | **In-ROM training mode upgrade** (L+R menu, dummy control, recording, displays; OPTIONAL) | `mkpatch11.py` | `build/sms_trainingplus.bps` |
| 12 | **Taunts on L** (native per-char misfire animations; OPTIONAL) | `mkpatch12.py` | `build/sms_taunt.bps` |
| 13 | **"Guts" v3** — taunt completion nerfs the opponent's SPECIALS/desperations (20/40/60%, per-round, stack 3; OPTIONAL) | `mkpatch13.py --l1/--l2/--l3` | `build/sms_tauntbuff.bps` |
| 14 | **"Guts Grip"** — Guts levels also nerf COMMAND GRABS (companion to 13, inert without it; `--all-grabs` extends to all throws; OPTIONAL) | `mkpatch14.py --l1/--l2/--l3 [--all-grabs]` | `build/sms_gutsgrip.bps` |
| 15 | Remove the AUTO option from the VS button-config screen (OPTIONAL; in REF v.2) | `mkpatch15.py` | `build/sms_noauto.bps` |
| 17 | **All stages selectable** — the hidden なかよし編集部 stage, in the menu and in the random pool (OPTIONAL; `--no-pool`, `--bgm N`) | `mkpatch17.py` | `build/sms_allstages.bps` |
| 18 | **No ACS in 2P VS** — the stat-customisation screen is unreachable in versus only (companion to 15; story/vs-COM keep it) | `mkpatch18.py` | `build/sms_noacs_vs.bps` |

### Playable ROMs (all in `build/`; `.sfc` are gitignored, rebuild from BPS)
> **2026-07-19 prune:** historical bundles and superseded all-patches BPS/ROMs were deleted (see docs/project/patch_index.md); rows below describing them are historical record. Kept: per-patch standalone BPS, current all-patches BPS/ROM, and `…v0.7_all5.sfc` (NI-test baseline).
- **`SailorMoonS_FrenchName_v0.7_all5.sfc`** — SHA-1 `24aa6b6d…` — **CANONICAL** (patches 1–5).
- `SailorMoonS_FrenchName_v0.6_all5_truecombo.sfc` — `c96c89fb…` — N=5 true-combo alternative.
- `SailorMoonS_FrenchName_v0.8_all5_dashinvuln.sfc` — `979db260…` — canonical + patch 6 (experimental).
- `SailorMoonS_FrenchName_v0.7_all5_pluto5hp.sfc` — `8e70f452…` — canonical + patch 7 (experimental).
- `SailorMoonS_FrenchName_v0.7_all5_venustech.sfc` — `3e3cd687…` — canonical + patch 8 (experimental).
- `SailorMoonS_FrenchName_v1.0_ALLPATCHES.sfc` — `f20f2883…` — **ALL 10 patches** (canonical 1-5 + optional 6-10, labels on); BPS `build/sms_allpatches_v1.0.bps`.
- `SailorMoonS_FrenchName_v0.7_all5_neptuneds.sfc` — `b1c3163f…` — canonical + patch 9 (experimental).
- `SailorMoonS_FrenchName_v0.7_all5_trainingplus.sfc` — `09106a07…` — canonical + patch 11 (BPS `build/sms_full11_trainingplus.bps`).
- `SailorMoonS_FrenchName_v1.1_ALLPATCHES.sfc` — `be2cb752…` — patches 1-11 (BPS `build/sms_allpatches_v1.1.bps`).
- **`SailorMoonS_FrenchName_v0.22_ALLPATCHES.sfc`** — `e6b999b5…` — **ALL 14 patches, newest test ROM** (BPS `build/sms_allpatches_v0.22.bps`, title v.0.22; built by `tools/build_v022.sh`; lineage: `52bc7e38…` 07-25 fixes → `19a7fc0d…` 07-30 credit line → `3bb9c829…` 07-30 review-remediation fixes → `e6b999b5…` 08-06 batch-2 fixes to patches 10b/11, maintainer-approved re-record).
- **`SailorMoonS_FrenchName_REF_v1.sfc`** — `2873f214…` — **REF v.1 reference bundle** 1b+2+3+4+5+7+8+9+12+13+14 (BPS `build/sms_reference_v1.bps`, title "FrenchName REF v.1"; built by `tools/build_ref_v1.sh`; lineage: `bd1104ee…` → `7ab26db4…` credit line → `2873f214…` review fixes).
- `SailorMoonS_FrenchName_v0.21_ALLPATCHES.sfc` — `62ffb174…` — previous build (BPS `build/sms_allpatches_v0.21.bps`, title v.0.21; MEATY status label removed from patch 10b; p10 counter/label bugs present).
- `SailorMoonS_FrenchName_v0.20_ALLPATCHES.sfc` — `9b0ae040…` — previous build (BPS `build/sms_allpatches_v0.20.bps`; Guts v3.4 = level indicator training-only).
- `SailorMoonS_FrenchName_v0.18_ALLPATCHES.sfc` — `86b7f44c…` — previous build (BPS `build/sms_allpatches_v0.18.bps`).
- `SailorMoonS_FrenchName_v0.17_ALLPATCHES.sfc` — `bccb0182…` — previous build (BPS `build/sms_allpatches_v0.17.bps`).
- `SailorMoonS_FrenchName_v0.16_ALLPATCHES.sfc` — `cf96aa05…` — previous build (BPS `build/sms_allpatches_v0.16.bps`).
- `SailorMoonS_FrenchName_v0.15_ALLPATCHES.sfc` — `30fd7b6e…` — previous build (BPS `build/sms_allpatches_v0.15.bps`).
- `SailorMoonS_FrenchName_v0.14_ALLPATCHES.sfc` — `4591034a…` — previous build (BPS `build/sms_allpatches_v0.14.bps`).
- `SailorMoonS_FrenchName_v0.13_ALLPATCHES.sfc` — `e1b03969…` — previous build (BPS `build/sms_allpatches_v0.13.bps`).
- `SailorMoonS_FrenchName_v0.12_ALLPATCHES.sfc` — `6683215a…` — previous QA build (Guts v2 general defense buff; BPS `build/sms_allpatches_v0.12.bps`).
- `SailorMoonS_FrenchName_v0.11_ALLPATCHES.sfc` — `be476410…` — previous QA build (Guts at 10/25/45, no indicator; BPS `build/sms_allpatches_v0.11.bps`).
- `SailorMoonS_FrenchName_v0.10_ALLPATCHES.sfc` — `f75efa04…` — patches 1-12, the maintainer's mid-QA build (BPS `build/sms_allpatches_v0.10.bps`).
- `SailorMoonS_FrenchName_v1.2_ALLPATCHES.sfc` — `048bd49f…` — ALL 12 patches (BPS `build/sms_allpatches_v1.2.bps`, title v.1.2).

The historical cumulative BPS these rows name (`sms_full*`, the v1.x line, all-patches
< v0.19) were deleted in the 2026-07-19 prune — rebuild any lineage by chaining the
`mkpatchN.py` builders (§2). Kept BPS: the per-patch standalones + the current bundles
(`sms_allpatches_v0.22.bps`, `sms_reference_v1.bps`).

---

## 2. How to build

> **The mechanics, explained**: `docs/project/how_patches_are_built.md` — what a
> `mkpatchN.py` actually does to the ROM, what `tools/asm65816.py` is for, how a
> hook and its appended bank work, and what `flips` does (it diffs; it does not
> inject). Read it before writing patch 19.


All builders are Python, run from any cwd, and take `(src, out)` positionals (stacking
onto any input ROM). `mkpatch.py` reads the clean ROM only. BPS via `tools/Flips/flips`.

**ROM location (never tracked in git):** builders and `run.sh` resolve the ROM directory
as **`$SMS_ROM_DIR` → `<repo>/roms/` → `<repo>/../roms/`** (`tools/smspaths.py`; first
dir actually containing the clean ROM wins). Keeping the ROM folder *above* the working
tree (`../roms/`) is the maintainer's preferred layout — no ROM can ever be committed by
accident. The filenames are fixed (clean + Big Zam, exact names in `smspaths.py`); only
the directory moves.

```bash
# resolve the clean ROM the same way the tooling does ($SMS_ROM_DIR -> roms/ -> ../roms/):
CLEAN="$(python3 -c 'import sys;sys.path.insert(0,"tools");from smspaths import clean_rom;print(clean_rom())')"
# rebuild the canonical v0.7 chain (N=6). Since 2026-07-30 every stacked step needs
# --stacked (the SHA gate is unconditional; a non-clean src without it is an error):
python3 tools/mkpatch.py  0x04            /tmp/s1.sfc
python3 tools/mkpatch2.py --stacked /tmp/s1.sfc     /tmp/s2.sfc
python3 tools/mkpatch3.py --stacked /tmp/s2.sfc     /tmp/s3.sfc
python3 tools/mkpatch4.py --stacked /tmp/s3.sfc     /tmp/s4.sfc --text "FrenchName v.0.7" --no-credit
python3 tools/mkpatch5.py --stacked /tmp/s4.sfc     /tmp/s5.sfc   # (patch 6/7 optional: mkpatch6/7.py)
./tools/Flips/flips --create --bps "$CLEAN" /tmp/s5.sfc build/out.bps
# current bundles have committed one-command recipes:
#   tools/build_v022.sh  /  tools/build_ref_v1.sh  /  tools/build_ref_v2.sh
```

### Tunable knobs (all builder flags — no hex editing; full table in patch_notes.md)
| Knob | Flag | Default | Options |
|---|---|---|---|
| Infinite gate (N) | `mkpatch.py <gate>` | `0x04` | `0x05`=true combo, `0x04`=meaty (canon), `0x03`=removed |
| Dash distance | `mkpatch5.py --speed` | `0x0640` | `0x0B00` vanilla … `0x0480` (−½) |
| Dash i-frames | `mkpatch6.py --lo/--hi` | `5`–`10` | any window in dash frames 1..14 |
| Title text/style | `mkpatch4.py --text/--style` | — | `white_red`/`red_white`/`red` |
| Title credit line | `mkpatch4.py --no-credit` | credit on | default swaps copyright line 1 to BZ's "©MOONLIGHT FIGHT SOCIETY" ("©ANGEL 1994" untouched); flag restores the original line |
| Pluto 5HP reach | `mkpatch7.py --h` | `62` | `54`=vanilla, `62`=all but Chibi, `64`=all |
| Venus tech window | `mkpatch8.py --extra` | `1` | `0`=vanilla 6f, `1`=13f, `2`=19f, `3`=24f (standard≈15f) |
| Neptune fireball box y_off | `mkpatch9.py --yoff` | `-11` | box vs origin; `-11`=centred on ball, more neg=higher |

---

## 3. Key gameplay findings (the operational knowledge)

- **The infinite `[2LP > 2HP > 66]xN`.** The patch gates the 2HP→66 dash cancel on a step
  tick (byte `0x1BE23` in the patch-1 stub). Two shipped tunings:
  - **N=6 (gate `0x04`, canonical):** the single connecting press is a **meaty** — the
    follow-up 2LP lands on the defender's first out-of-hitstun frame and the engine's
    **"hit beats same-frame block"** rule makes it connect. Unblockable by holding back.
  - **N=5 (gate `0x05`, alt):** one frame earlier → hit lands *in hitstun* = guaranteed true
    combo, but a 2-frame *connect* window (combo@0 + meaty@+1).
  - ⚠️ N=6 was once mislabelled a "blockable frame trap" — **wrong**; that was a verdict bug.
    Holding down-back does NOT escape a frame-perfect N=6 meaty.
- **Reversal matrix (measured, whole cast).** A **frame-perfect** meaty beats *everything*
  (even Chibi 5LP, the fastest poke, and Neptune's DP whose invuln starts frame 2 not 1). A
  **1-frame-late** meaty is punished: block/back-jump → BLOCK, back-dash → ESCAPE, 6HP grab →
  Uranus THROWN, Neptune DP → Uranus KNOCKED DOWN. So the infinite is real only under
  frame-perfect execution; any slip is blockable/throwable/reversal-punishable. This is the
  design goal and why N=6 is canonical.
- **Invulnerability mechanism.** Invuln = **empty hurtbox** (hurtbox index 0), NOT a flag. The
  back-dash is invincible because its animation uses index 0 for all 14 frames. Patch 6 uses
  this: it forces `+0x41=0` during Uranus's forward-dash frames 5–10 (strike-only, throws still
  catch). The reversal-dash *bug* (patch 2) was a different thing — the `+0x46` untargetable
  flag lingering from knockdown; fixed by adding `stz $46,X` to the dash's step-0 init.
- **Throw teching is mash-based, not a one-press window.** During a throw hold, script-driven
  steps sample the victim's fresh attack presses (`+0x50 & 0xF0`, latched at 30Hz) and count
  them in the **thrower's `+0x56`** (`$C1:07CF`); at the toss, count ≥ 2 → victim act `0x23`
  (tech, HALF damage) else `0x1D` (thrown, full) — `$C1:0823`. Threshold is global; the
  per-throw "window" = which hold-anim steps sample (script entry byte5 ≠ 0, scripts in bank
  $C1, interpreter `$C1:06E5`). Venus 6HP sampled 6f (vs Jupiter's standard 15f) → patch 8
  sets one script byte (`0x16C70`) to make it 13f. Full map in annotations.md + patch_notes.md
  Patch 8.
- **Hitboxes.** Box format = `[x_off_r, w_r, x_off_l, w_l, y_off, h, flags, ?]` (8 bytes).
  `y_off` negative = above the feet (origin at feet, +y down). Extend a box *down* = increase
  `h`. Per-char box tables in bank `$8A`; the per-frame box-index writer is `$C0:9CCD`
  (`sta $41,X` from the animation table). Pluto's 5HP is two-phase (act `0x44` startup →
  act `0x46` active, hit-box `0x03`); patch 7 raises that box's `h` so it reaches crouchers.
- **Projectiles** live in slots `$7E:1100`/`1180` and pick their box table by their **own**
  `+0x00` object id (not the owner's char). The hit pointer table `$8A:C1F1` has 28 entries:
  1–9 roster, 10–27 = 9 distinct projectile/object tables (`$8A:FBD9..FDA1`); dump with
  `tools/extract_proj_boxes.py`. **Neptune's Deep Submerge** (214LP `0x62` / 214HP `0x63`)
  spawns object id `0x18` → table `$8A:FD51` (exclusive). Its hitbox was authored for an upward
  arc while the ball falls (origin `+0x25` descends 128→166, box `y_off` climbs -27→-60), so the
  hitbox floats above the sprite; **patch 9** recentres the box on the ball (`y_off → -11`).
  Measured with `ds_trace.lua` / `ds_overlay.lua` / `ds_hittest.lua`.

---

## 4. Tooling & test harness

**Emulator:** `tools/Mesen.app` (macOS). Headless runner: `tools/run.sh` —
`ROM="<rom>" tools/run.sh <script.lua> [timeout_seconds]`. It forces
`--snes.ramPowerOnState=AllZeros` and controller ports.

**Test/demo Lua scripts** (in `tools/`; each has a header explaining use):
- `demo_link.lua` — **auto-calibrating** 1-frame-link proof: sweeps the follow-up press frame
  and reports the connect window (DROP/COMBO/MEATY/BLOCK) for whatever gate the ROM has.
  Wrappers `demo_link_early/late/blocked.lua` loop a single attempt at `valid ± n`.
- `demo_truecombo.lua` / `demo_infinite.lua` — live loop demos (P1+P2 scripted).
- `react_test.lua` + `react_{backdash,njump,bjump,grab,jab,chibi5lp,dp}.lua` — wake-up reaction
  vs the meaty; verdict = HIT/TRADE/WIN/BLOCK/ESCAPE (reads both players). `REACT_MFV=116` for
  a 1-late meaty.
- `trainer.lua` — interactive GUI trainer (you = P1, configurable dummy).
- `trace.lua` + `trace_plan.lua` — general scripted-input logger (config in trace_plan.lua:
  STATE/PLAN/P2PLAN/POKES/LOGFROM/LOGTO/OUT; `EXTRA=true` logs +0x45–48). The workhorse for
  measurement.
- `coltest.lua` + `coltest_cfg.lua` — **navigate char-select and save a match savestate**
  (set CHARA/CHAR2/SAVE, run on the target ROM → writes `traces/<SAVE>`).
- `techsweep.lua` + `techsweep_cfg.lua` — **throw-tech measurement**: reload-per-attempt sweep
  of the defender's mash-start frame (or mash count, `VARY="MASH"`), classifies
  TECHED/THROWN/NOTHROW per attempt. The patch-8 workhorse; see its header for knobs.
- `techfind.lua` (+ optional `techfind_cfg.lua`) — throw instrumentation: logs defender
  actionID writes with writer PC, mash-counter (+0x56) writes, sampling instants (exec watch
  on $C1:07D3), optional ROM script-read watch (SCRIPT_LO/HI).

### Training mode (tools/training.lua + tools/training/ package) — pure Lua, no ROM edits
A modern training mode: **SF6-style frame meter** (per-frame classes both players, segment
counts, advantage badge, hitstop dimmed, invuln/cancel strips, freeze model), **recordable
dummy** (4 facing-normalized slots, triggers: manual/loop/wakeup/blockstun/hitstun/random),
dummy layers (guard/tech-mash/wakeup/pose), **input piano roll**, event labels
(GC/REVERSAL/PUNISH/THROW TECH/THROWN/TRADE — generated from labels.lua), combo counter (reset-aware),
**hitbox viewer** (live bank-$8A reads, pixel-verified), keyboard menu (M) + pad controls
(hold R = drive dummy, Select = record). Frame-data conventions: S excludes the first
active frame (Dustloop; toggle to SF6 display in menu), counts exclude hitstop, advantage
= neutral-frame delta (oracle-validated: 2LP S4 A5 R4 +6, 2HP S8 A12 R7). GUI: open a match,
run tools/training.lua in the Script Window (enable file access for slot/settings persistence).
Headless self-tests: `tools/training_test.lua` (T1–T11, see its header) — T1/T2/T2H/T3/
T5/T6/T7/T10/T11 run on the clean ROM, T4/T8/T9 need a v0.7-family ROM (T10 also passes
on v0.21). T11 pins the #96 fix: a savestate reload must clear framedata's
lastMove/lastAdv/pend (the reset path #15 was closed on had left them stale). T10 locks the 2026-07-21 fix: projectile specials (body never goes active — the
hitbox lives on the projectile slot) must still close their framedata move instance at
neutral, else the attacker sticks in STARTUP, the combo never closes, and HP regen never
fires ("refill only after a normal hit" field report; fix in framedata.lua classify()). Architecture: modules share a ctx
with hook lists; add a feature = one file in tools/training/ + one MODULES entry (main.lua).
Key API facts probed (tools/probe_*.lua): +0x4D=hitstop countdown / +0x43=connect latch;
inputPolled precedes exec@$80:8353; getInput is clean if read before setInput; ScriptHud
size degenerate headless; screenshots don't composite ScriptHud (console surface only).

**One-command consistency check: `tools/health.sh`** (#24). Everything checkable
from the source tree alone — `mksigs --check`, `mkrelease --check`, Python/shell
syntax, the release folder, and a round-trip of each release `.bps` against its
recorded ROM. It **SKIPS** whatever needs the clean ROM, the Super S donor, flips
or Mesen and says so, because a check that silently passes when its input is
absent is the thing this repo keeps getting bitten by. Also prints `note` lines
counting the accreting conventions (#73/#81/#102/#105) — reported, never fatal:
failing a build on 79 working asserts is how a check gets deleted. CI runs it
(`.github/workflows/health.yml`); a green tick there is **not** a verified build.
Acquisition for the four external pieces: `docs/project/toolchain.md`.

**Regression suite (run before shipping any build):** `tools/test_regression.lua` —
auto-detects which patches are in the ROM via PRG-ROM fingerprints. **The fingerprints
are GENERATED**: each builder exports `SIG = [(offset, byte), ...]` (layout/stacking-
invariant bytes only) and `tools/mksigs.py --write` renders the suite's SIGS block
(`--check` verifies sync; both build scripts run it). Never hand-edit the SIGS block or
pin stub-layout operand bytes — a hand-pinned byte silently skipped all 11 p13 tests on
2026-07-30 when a stub change shifted it. After changing a builder's hooks or knob
defaults (p5/p7/p8/p9 SIGs pin the defaults), update its SIG and rerun mksigs --write.
The suite then runs base-game
engine invariants (deterministic damage, counter-hit −2 columns, posture, throws,
desperation types, dash distance) plus per-patch nominal+edge tests (incl. cross-patch
counter-hit×Guts, p8 tech-window dual-mode, p13 round-reset, the full 9-character
desperation compendium + crouch edges). `ROM=<build> tools/run.sh
tools/test_regression.lua 900`; optional cfg `EXPECT="clean"|"all"`, `ONLY="pattern"`.
Green (2026-08-05, after the two config-screen tests were added): clean = **45**,
Rev. S-02 / Rev. SS-02 = **60**; historically v0.22 = 59, REF v.1 = 55, clean = 41.
clean+FULL ≈ 50 (dual-mode expectations flip
with detection; patch tests skip when absent). Engine-rule locks: death-underflow
pair, GC-gate-immediate, backdash-GC, prejump throw-vulnerability, danger threshold,
clock desperation trigger, first-hit-defense pair; statics for matrix, desperation
records, modifier handlers, char-loader. `FULL = true` in the cfg adds the
whole-roster desperation crouch sweep + chip signatures (Pluto strike-throw 1,
Moon zero-chip, Mars full-chip). Patch 9 now has a BEHAVIORAL dual-mode test
(DS vs crouching Chibi connects t<=38 patched / t>=41 vanilla).

**Other tools:** `extract_sms_hitboxes.py` → `docs/game/sms_all_boxes.json` (per-char box tables);
`extract_proj_boxes.py` (projectile/object box tables, idx 10–27); `ds_trace.lua` /
`ds_overlay.lua` / `ds_hittest.lua` / `ds_clash.lua` (Neptune Deep Submerge fireball: log
projectile slot, draw its live hitbox vs sprite, hit-test a posed target, and a Neptune-mirror
two-fireball clash demo — patch 9 workhorses; states `neptune_vs_{jupiter,chibi,neptune}.mss`);
`tools/Dispel/dispel` disassembler (**build once**: `cc -O2 -o dispel main.c 65816.c` in
`tools/Dispel/`); `texttiles.py` + `mockup.lua` (title font); `mkpatch3` reuses
`vendor/sms-training-mode/sms_patcher.py` for the palette port.

**Config-screen fixtures** (force-added): `config_vs_clean.mss` (2P VS, `$8D=1`)
and `config_com_clean.mss` (1P vs COM, `$8D=2`), both taken on the CLEAN ROM at
the button-config screen with **P1's cursor on row 0** — the state patches 15 and
18 are tested from. Regenerate with
`ROM=<clean> MENU=1 SAVE=config_vs_clean.mss tools/run.sh tools/probe_acs_select.lua 250`
(`MENU=2` for the vs-COM one). ⚠ `emu.createSavestate()` **throws in an endFrame
callback** — it must be called from a CPU-exec context, which is why that probe
writes the state from a hook on `$80:8353`, the same site the suite loads from.

**Savestates** (`traces/`, gitignored except force-added ones): `*_v07.mss` are tagged to the
canonical ROM (`uranus_vs_{jupiter,mars,neptune,chibi}_v07`, `pluto_vs_chibi_v07`,
`pluto_vs_1..7,10`); `uranus_vs_jupiter_v06` (N=5 ROM); `uranus_vs_jupiter_f5` (headless
self-tests); `venus_vs_jupiter_clean` / `jupiter_vs_venus_clean` (clean ROM, patch-8
techsweep both ways). The four `_v06`/`_v07` Uranus states + Mars/Neptune/Chibi + the two
Venus states are **force-added to git** so the demos work. Patch 9 adds
`neptune_vs_jupiter.mss` / `neptune_vs_chibi.mss` (Neptune=P1, force-added) for the Deep
Submerge fireball demos.

---

## 5. Critical gotchas (these cost real debugging time)

- **Mesen `setInput` port is the 3rd arg**, not the 2nd (a Mesen bug discards param 2):
  `emu.setInput(buttons, 0, port)` — port 0 = P1, 1 = P2. Writing `(tbl, 1)` silently drives P1.
- **Asset policy (maintainer ruling, 2026-08-04), spelled out in `.gitignore`:**
  **screenshots and any game imagery are NEVER tracked** — an emulator capture is
  game art just as much as a ROM is, and `git add -f` is not an escape hatch (nine
  PNGs reached the public repo that way before the rule was made repo-wide).
  Nothing depends on them: all 107 `.png` opens in `tools/` are write-only.
  **Savestates (.mss) ARE kept**, deliberately: they embed WRAM/VRAM but are not
  directly accessible content the way a picture is, and 152 files call
  `loadSavestate`. If imagery ever has to be kept, the plan is two repos — a clean
  public one and a private one for savestates and other assets.
- **NEVER build a bundle by chaining standalone BPS files** (an old patch_index note
  wrongly blessed this): every bank-appending standalone (4, 10/10b, 11, 12, 13, 14) is
  diffed against CLEAN and targets the SAME first-free bank $E8 — chained application
  (needs checksum override) makes each patch overwrite the previous one's code bank while
  the old hooks still jump there (classic casualty: p11's L+R stub → menu dead). Custom
  combos: chain the `mkpatchN.py` builders (each re-detects the next free bank), diff once.
- **`probe_p11_nav.lua` stalls at Practice char-select on current builds** (P1 must also
  confirm the DUMMY's char — P2's pad is inert in Practice; the old step list mashes P2)
  and its `sf>600` fallback then **saves a non-match state over `traces/training_p11.mss`**
  (tracked — restore with git if clobbered). `probe_p11_lr.lua` has the fixed autopilot.
- **Savestate ROM-tag:** the Mesen **GUI refuses** a savestate whose embedded ROM doesn't match
  the open ROM; the **headless testrunner is permissive** and loads anything. So any GUI demo
  that `emu.loadSavestate`s a file needs a state tagged to that exact build. Regenerate one by
  loading any state then `emu.createSavestate()` while running the target ROM.
- **Script paths are repo-relative since 2026-07-30** via `tools/sms_env.lua` (every Lua
  tool bootstraps it and uses `ENV.ROOT/TOOLS/TRACE`; discovery order: script dir from
  `package.path` → `$SMS_ROOT` → `$PWD` → ROM-path walk-up, validated by `HANDOFF.md`
  presence). Mesen's process cwd is NOT the shell cwd (relative `io.open` fails even under
  `run.sh`), which is why paths were absolute historically — never hardcode them again.
  Tool scripts must live in `tools/` for the bootstrap line to find `sms_env.lua`; a
  script elsewhere must set `SMS_ROOT` or load a repo ROM. Python builders are anchored
  to the repo via `__file__` (`REPO`) and run from any cwd. `fixpaths.sh` (old zip fixer)
  is obsolete.
- **The extractors cover charIDs 1-9 only** — id 10 "Saturn" has **no data in the clean
  ROM** (none was ever found, despite decades of community digging), and that is still
  true however many Rev. SS builds exist: the Saturn you can play is data this project
  ADDS from Super S, not data found here. Pre-2026-07-30 extractor versions invented a
  bogus "Saturn" JSON entry from projectile-table bytes (fixed, issue #38). Rule: no
  SMS-targeted code reads a charID 10 out of the base game. **Scoped exception (2026-07-30): the
  "SMS + Saturn" project** — everything Saturn/Super-S lives in dedicated
  subfolders: `docs/project/saturn/`, `tools/saturn/`, `traces/saturn/`, `build/saturn/`
  (see `docs/project/saturn/PROJECT.md` §conventions). Saturn Lua tools bootstrap with
  `/../sms_env.lua`; `sms_env.lua` root discovery walks up from subfolders.
- **Box-index writer order:** `$C0:9CCD` sets `+0x41` (hurtbox) every frame from animation data,
  and it runs a per-object batch. To override a hurtbox you must write it *after* that (patch 6
  hooks the writer itself). Frame counters: the forward-dash frame index is `+0x5D` (1..14; read
  one tick before its end-of-frame value).
- **Forward-dash input** (66) needs the 66-recognizer to settle — from a fresh savestate, tap
  fwd/release/fwd around frames 58/60, not immediately after load, or you get a walk.
- **Move phases:** several moves are multi-phase with different action IDs and boxes (e.g.
  Pluto 5HP `0x44`→`0x46`). When identifying "the hitbox," dump the active box *at the hit
  frame* with `+0x40`/`+0x41` — don't trust a single frame sample.
- Button map (empirically): **Y=LP, X=HP, B=LK, A=HK** (the training-mode Lua comment was wrong).

---

## 6. Verify quickly

```bash
# 1-frame-link window on the canonical build (expect a single MEATY frame, no COMBO;
# writes traces/demo_link_out.txt and exits — plain demo_link.lua is the GUI variant):
ROM="build/SailorMoonS_FrenchName_v0.7_all5.sfc" tools/run.sh tools/demo_link_headless.lua
# Venus throw-tech window (patch 8): expect TECH [55..72] clean, [55..79] patched:
ROM="build/sms_venustech.sfc" tools/run.sh tools/techsweep.lua 500   # → traces/techsweep_out.txt
# reversal outcome (frame-perfect vs +1 late):
# edit a react_*.lua or pass REACT_MFV; see react_test.lua header.
# patch 11 (in-ROM training mode) feature suite + perf:
ROM="build/sms_trainingplus.sfc" tools/run.sh tools/test_p11_tier1.lua 260   # -> traces/p11_tier1.txt ALL PASS
ROM="build/sms_trainingplus.sfc" tools/run.sh tools/perf_patch11.lua 200     # -> traces/p11_perf.txt PERF PASS
# patch 13 (guts buff) suites (MODE="solo"/"stack" in cfg):
ROM="build/sms_tauntbuff.sfc" tools/run.sh tools/test_p13_guts.lua 400
# patch 12 (taunts) suites:
ROM="build/sms_taunt.sfc" tools/run.sh tools/test_p12_taunt.lua 200          # MODE="solo" in cfg
# patch 17 (all stages): 9 reachable on clean, 10 patched; COMBO=1 reproduces the
# retail X+L+R unlock on the CLEAN ROM (the independent control):
ROM="build/sms_allstages.sfc" TAG=p17 tools/run.sh tools/probe_p17_stagelist.lua 240
ROM="build/SailorMoonS_FrenchName_REF_v2_allstages.sfc" TAG=pool RNG=9 \
  tools/run.sh tools/probe_p17_randompool.lua 400   # -> $8E=18 (stage 9)
# rebuild any BPS and confirm round-trip (current bundles):
./tools/Flips/flips --apply build/sms_allpatches_v0.22.bps "$CLEAN" /tmp/rt.sfc  # sha == e6b999b5…
./tools/Flips/flips --apply build/sms_reference_v1.bps     "$CLEAN" /tmp/rt.sfc  # sha == 2873f214…
# or rebuild either bundle from source (the committed recipes):
tools/build_v022.sh    # -> e6b999b5…
tools/build_ref_v1.sh  # -> 2873f214…
tools/build_ref_v2.sh  # -> 6d79fb5f…  (REF v.1 + patch 15; base for the Saturn build)
```

---

## 7. Repo layout (post-reorg)
```
CLAUDE.md, HANDOFF.md, README.md, .gitignore   ← root only
roms/     clean JP ROM + Big Zam ROM (gitignored; may live in ../roms/ or $SMS_ROM_DIR instead — see §2)
docs/     game/ (the ROM: architecture, quickref, annotations, boxes, characters/)
          project/ (this edition: patch_notes, patch_index, handoff, saturn/)
tools/    mkpatch*.py, all test/demo .lua, run.sh, coltest, texttiles, Dispel/, Mesen.app, Flips/
traces/   savestates (.mss) + trace outputs (gitignored; key states force-added)
build/    patched .sfc (gitignored) + .bps/.ips patches (tracked)
vendor/   sms-training-mode (RAM map + palette patcher)
```

---

## 8. Open threads / possible future work
- **Patch 14 `--all-grabs` misses the throw-TECH branch** (measured 2026-08-08, while
  auditing whether the data-architecture doc's corrections implied wrong code). At Guts
  L3 a landed throw scales 24→10, a teched one stays 12 — teching costs the victim more
  than eating it. `$C1:0823` splits into two branches and only the landing one is hooked.
  **No shipped build passes `--all-grabs`**, and the default command-grab scope looks
  unexposed (those scripts toss with no mash sampling — inferred, not measured). Fixing
  it needs a maintainer ruling first: should a teched command grab be scaled at all?
  Detail: `docs/project/patch_notes.md` § Patch 14.
- **The A.C.S. screen's POINT BUDGET was never censused** — how many points the
  customization screen hands out, and what it lets you spend them on. Everything else
  about the system is measured (`docs/game/sms_acs_system.md`); this one line of it is
  not. Recorded here 2026-08-09 because the game doc's resolved-unknowns section was
  trimmed and this was the only open item hiding in it.
- **Dash distance** (patch 5): maintainer said −1/3 "feels much better" but *may* retune later.
  One flag: `mkpatch5.py --speed`. Infinite is unaffected by dash speed (dash stops on contact).
- **Patch 6 (dash i-frames)**, **patch 7 (Pluto 5HP)** and **patch 8 (Venus throw tech)** are
  experimental, off by default — awaiting a decision on whether to fold into a future
  canonical.
- If folding experiments into canonical, bump the title version (`mkpatch4.py --text`) for a
  naked-eye A/B tell — the maintainer is a pad tester who values on-screen version + ROM hashes.
- **RESOLVED (2026-07-21): the "L+R doesn't open the training menu" field report** —
  maintainer confirms L+R works as intended on the latest patches (taunts + Guts
  Q-style specials/desperation nerf also confirmed working). The 2026-07-20
  investigation (probes `tools/probe_p11_lr.lua` / `tools/probe_p11_ko_lr.lua`, gate
  recap `$8D∈{4,5(+DMGFLAG $7F:F004==A5)} && $0070==4 && $01FA==0x80`) stands as
  reference; the chained-standalone-BPS trap remains documented in §5.
- Other shipped behavior: measured, no open bugs.
