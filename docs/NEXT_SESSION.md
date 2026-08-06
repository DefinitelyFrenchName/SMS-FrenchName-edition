# Next-session handoff — 2026-08-06

## Start here

**Two workstreams are open. The issue-remediation programme is the live one.**

### 1. GitHub issue remediation — IN PROGRESS (started 2026-08-06)

Plan (batches, per-issue verdicts, ordering constraints):
`~/.claude/plans/i-ll-look-into-all-purrfect-blum.md`.

63 open issues from two adversarial cross-model reviews were triaged against
HEAD: **6 already fixed**, 8 partial, 47 valid, 0 fully invalid. Maintainer's
calls: address everything warranted, and Claude comments + closes what is
already fixed or wrongly premised.

| Batch | What | State |
|---|---|---|
| 1 — integrity ("results that can lie") | #79 #81 #82 #83 #59 #60 #65 #66 #13 | **DONE** (`87a5b5a`) |
| 1b — health command + fresh clone | #24 #61 #62 #3, rescoped #63 | **DONE** (`f3b6e68`) |
| 2 — correctness in shipped code | #87 #92 #91 #86 #88 #90 #96 #94 #89 #80 #97 #69 #76 #71 #18 #93; #84 refuted | **DONE** (2026-08-06, one commit per issue from #88 on) |
| 3 — docs/registry drift | #67 #68 #74 #103 #52 #75 | not started |
| 4 — duplication, dead code, conventions | #73 #85 #95 #98 #100 #101 #70 #77 #99 #102 #105 #104 #78 #35 #32 #44 #64 #72 | not started |

Batch 2 findings that generalise (detail in the per-issue commits):
* **The #46 "fixed" pattern never worked** — an error (assert included) thrown
  inside a Mesen memory callback is swallowed with no message, so
  react_test.lua's assert hung to timeout exactly like the unfixed sibling.
  The only reporting form is print + emu.stop(1) (probe_chr.lua's). More
  assert(io.open…) sites inside callbacks remain for the #105 sweep.
* **inputprobe.lua had never logged anything** — its range covered bank $00
  while this game reads pads from the $80 FastROM mirror. The filed
  double-registration was real but unreachable. Hook both bank images.
* **A "both labels idle" re-arm is load-bearing for per-match CHR reloads**
  (#93): the fix had to move the cost to a lazy uploader, not narrow the
  re-arm to a transition — that would draw match 2's first label with a
  wiped font.

⚠ **Ordering constraints that still apply:** #87 before #98 (same functions);
#99 must not be swept with `sed` — four of its twelve sites sit inside gating
suites; #85/#95/#98/#100 quote stale acceptance hashes, re-baseline first.

**Convention from here: ONE COMMIT PER ISSUE** (`Fixes #NN`). The first two
batches are multi-issue commits — the maintainer chose to leave them rather than
split history that was verified as a whole.

### 2. Patch 16, step 2 — menu translation, unchanged since 2026-08-05

Still blocked on one screen; the next action is still a single WRAM dump. See
item 2 below.

## What a new session must know first

* **`tools/health.sh`** is the one consistency command — generated artifacts in
  sync, syntax, release folder, release `.bps` round-trip. It **SKIPS** anything
  needing the ROM/donor/emulator and says so. CI runs it
  (`.github/workflows/health.yml`); a green tick there is **not** a verified
  build. Acquisition for the four external pieces: `docs/toolchain.md`.
* **Suite counts moved** (patches 15/17/18 are now inside the gates, and two
  config-screen tests were added): clean **45**, Rev. S-02 / Rev. SS-02 **60**,
  Saturn gate **53 checks**.
* **`traces/regression.txt` is truncated per run** and its header names the ROM.
  Reading `tail -1` is finally safe — it was not before #81.
* **The release artifacts have not moved a byte** through all of this: Rev. S-02
  `41d93a53…`, Rev. SS-02 `b96f3fe8…`, both still reproducing from
  `tools/build_rev.sh both`. Reverting to the released state is always a clean
  escape hatch.
* **One artifact did change:** patch 10b (`sms_combolabels.bps`), ROM
  `920652df…` -> `4899790a…` when its label pipeline was brought under
  `--modes` (#86), then -> `83defe1e…` when repeated events were made to
  refresh the label TTL (#88), then -> `745ea0bc…` when the glyph font
  became a lazy upload (#93). Patch 10 proper is byte-identical.

## The lesson from the remediation so far

**A "cross-model verified" issue can still be false.** #84 (training HP toggle
wipes both players' Guts levels) was confirmed by both review models against the
cited lines — and does not reproduce. I wrote the fix first, then built the test
to prove it was needed; the test passed on the UNFIXED build. Instrumenting the
decisive frames showed why, twice over: patch 11 hooks ahead of patch 13, so
patch 13 latches `PREVHP` in the same frame the HP changes (`p1hp 17->60` and
`prev0 17->60` together), and `rsig` additionally needs both action IDs at 0
while P1 sits in act `$21` with the menu open. **The evidence in that issue is
accurate line by line; what it missed is the frame ordering BETWEEN two files.**
The fix was reverted and the test kept as a pin.

So: for every issue in the remaining batches, **build the failing case before
the fix**, and prove the working path is unchanged after (byte-identical
rebuild, or the suite's counts and verdicts unmoved). One fix has already been
withdrawn on that basis, and one gate check (#66's structural floor) was caught
breaking a working chain within minutes of landing.

## Everything below is the 2026-08-05 state, still accurate for patch 16 / Saturn

**1. Saturn's 214P projectile — FIXED (v0.14.11, 2026-08-05).** It was a
**per-shell truncation of her effect sheet**, not a bad sprite list. Her
0x1040-byte sheet is staged over the shell's in `$7F:0000`, but the DMA that
follows was sized from the **shell's own** sheet: Uranus `$11C0`, Pluto `$10C0`,
**Neptune `$0E60`** — so on Neptune the last 15 tiles (`$113-$121`) never
reached VRAM, and the travel pose draws 7 of its 12 sprites from that range.
Hence *two disconnected pieces*, on Neptune, intact on Uranus. The armed path of
the DMA stub now forces the length too (`sta $004305`). Verified byte-identical
to the decoder output on shells 6/7/8; gate 49/49, regression 57/57. Detail:
`docs/saturn/BUILDS.md` § "214P projectile: SOLVED".

**2. Patch 16 (menu translation) — STEP 1 DONE (2026-08-05).** The 26
half-width glyphs now reach **VRAM tiles $5C0-$5FF** and render as a legible A-Z,
read back out of VRAM. It was the same bug class as the projectile after all — a
LENGTH coming from the wrong place — plus a second, independent mistake:

* **The asset record layout in the old notes was wrong.** A record is
  `[vram16][len16][src24][dest24]` (table `$C3:BE08`), so a block's upload length
  sits **2 bytes BEFORE its src pointer**, not 8 after. Earlier attempts bumped
  the next record's field. Parsed correctly, 27 of 58 records match an observed
  transfer exactly; parsed the old way, none do. The field is BYTES.
* **The kanji block is not loaded on the screen being translated.** No transfer
  to VRAM `$5000` happens on the config screen at all, so glyphs put there could
  never appear. That screen's sheet is `$C4:2590` -> `$7E:C000` -> VRAM `$400`,
  and `mkpatch16.py` now extends that one (418 -> 512 tiles), with the length
  field at **`$C3:BF18`** raised `$3480` -> `$4000` (the ceiling — the source is
  `$7E:C000`, so more would run off the end of bank `$7E`).

**Remaining: step 2, the tilemap edits — and the first one is BLOCKED.** The
Options screen is written and **gated OFF by default** (`SMS_P16_OPTIONS=1`),
because enabling it clears the Japanese and draws nothing: **the glyphs do not
reach VRAM on that screen**, even though it runs the extended transfer
(`vram $4000 len $4000 src $7E:C000`, confirmed on the built ROM) and record 27
is the only record staging into that buffer. Screen-specific — most likely the
upload precedes that screen's decompression and carries a stale buffer.
**NEXT: dump WRAM `$7E:C000+$3800` on the Options screen** (absent from the
BUFFER = ordering; present = the fault is after the transfer).

Everything else for Options is ready: its tilemap is **asset record 19**
(`$C3:69F0`), budgets are measured (**18 columns for a label, 6 for a value**;
half-width glyph = ONE map column), the maintainer's strings all fit, and the
addressing is known (MAP tile = VRAM tile − `$200`; glyph = 2 rows,
`bottom = top + $10`; labels attr `$0C00`, values `$1000`).
⚠ `tools/menutext_check.py` only knows the STAGE names — it does not validate
these; the Options budgets were measured off the live tilemap.
⚠ **The VALUES cannot be done in the tilemap at all** — they are rewritten at
runtime as the player cycles a setting, so English baked into the map is
overwritten on first input. That writer is still to be found.

**Screen coverage:** Options and Tournament both load the same sheet the font
install extends (record 27), so no second install is needed for them. The **win**
and **ACS** screens are NOT yet probed — neither is reachable from the title menu
(one needs a KO, the other SELECT at char select), so their sheets are unknown.
Priority order (maintainer): Options, Win, ACS, Tournament. Story is out of
scope. プレイヤーセレクト on the *illustrated char-select* is off-limits (part of
the artwork, rainbow-animated) — but the one on the Tournament screen is plain
text and DOES need translating, as do that screen's per-line character names.

⚠ Verify with `tools/probe_menu_vram.lua`, which dumps **on the font transfer**,
not at the end of the run — a dump taken on the final screen reads identical on
clean and patched ROMs because a later upload has overwritten the region. Use
`POKE=1` for the positive control (0/256 bytes arrive on clean, 256/256 patched);
without it, a clean-vs-patched diff proves nothing, since both are zero there.

**3. Nameplate — DONE** (v0.14.10): her plate reads SATURN, vanilla untouched,
regression 57/57. `SATURN_NAMEPLATE=0` reverts to blank.

**4. Thrown sprite — FIXED (v0.14.14), field-confirmed.** v0.14.7 fixed the OAM flood; the sprite
stayed wrong until now and no build v0.14.8→v0.14.13 differed by a pixel. The
v0.14.7 hook covered the two reads in `$C1` on the basis that the ROM has exactly
two — true of the CLEAN ROM, false of the BUILD, because bank `B_C1` is a full
copy of `$C1` taken BEFORE the hook is applied. With **Saturn as the thrower**
her proc ran out of that copy's unhooked read. Repro: Saturn vs Saturn, 6P.
The gate now covers Saturn-as-thrower and the builder asserts no unhooked read
survives anywhere in the image.

**5. Patch 17 (all stages selectable) — DONE and confirmed (2026-08-05).**
`tools/mkpatch17.py`; standalone `build/sms_allstages.bps` (`e5dd325b…`),
playable bundle `build/sms_ref_v2_allstages.bps` = REF v.2 + 17 (`e8fc6045…`).
Two edits, both verified in-emulator:
* **menu bound** — `$C3:BADE` `8D` -> `9C` (`sta $1F59` -> `stz`). The reader
  `$C3:AA28` sets `$1C1C` to 16 or 18, which the shared navigator treats as the
  INCLUSIVE max word index: 0-8 vs 0-9. 9 stages reachable on clean, 10 patched;
  index 18 loads the stage and the menu draws なかよし編集部.
* **random pool** — the picker was patch 3's own rider (`$E8:00CD`,
  `lda $B1 / A %= 9 / asl / sta $8E`), not retail code; retail has no random
  stage picker at all. Both `#$0009` operands -> `#$000A`, found BY SIGNATURE in
  the image being built. RNG forced to 9: stage 0 before, stage 9 after; RNG 8
  identical on both (the control that proves the poke reached the picker).
* The **independent control** is the game's own cheat: hold **X+L+R** over the
  title (`$C3:B8B4`, latch ~f622) and a CLEAN ROM already shows ten stages.
* ⚠ A menu screenshot taken on the frame the index lands shows the PREVIOUS
  stage's name (the name is queued to VRAM) — that artifact read exactly like
  "the tenth entry is mislabelled". Settle ~40 frames.
* **Field verdict: patch 17 is clean, and stays OPTIONAL.** v0.15.0 (Saturn +
  patch 17) was built, played and retired the same day — the stage is "a bit
  distracting visually" — so it is in neither REF nor patch 100. The Saturn
  builder keeps the hook, off (`SATURN_ALLSTAGES=1` opts in and tags the
  on-screen version **S**; `SATURN_STAGE_BGM=<byte>` swaps that stage's music),
  and reproduces v0.14.15 byte-for-byte without it. Play it via
  `sms_allstages.bps` or `sms_ref_v2_allstages.bps`.

**6. Her four palettes — DONE** (v0.14.12, retuned v0.14.15, maintainer request). Her transform
copied palette 0 unconditionally and threw away the slot the character select
had loaded. Two things to know before touching this again: **Super S ships only
TWO palettes per character** (the "four manifest palette pointers" are char pal
0, char pal 1, the 8-byte icon palette and the effects palette), so slots 2/3
are authored here by rotating only her costume ramp; and **a Saturn player can
never reach slots 0-3**, because summoning her needs L+R and L/R are patch 3's
palette modifiers — her slots are 4-7, so the copier MASKS rather than clamps.
Clamping was the first cut and it reproduced the original bug exactly.

**7. Her ground throws — FIXED (v0.16.1, 2026-08-05), field-reported.**
Two faults, both **inherited from Super S** (byte patterns confirmed identical
in that ROM before anything was touched), both reproduced by probe before being
diagnosed:
* **wrong buttons** — the close-throw table is 4 x 8 bytes indexed by attack
  button (`$C1:C84A`, consumed by `$C1:055A`; index 2 = HP, 3 = HK, the record's
  last byte is the act) and hers had the close grab (`$68`) and the shoulder
  throw (`$7B`) in each other's slots. Swapped wholesale, so each keeps its own
  range/gating fields.
* **wrong direction, fixed as an INPUT SWAP** — 6 and 4 are read the other way
  round for that one throw; the animation, the turn-around and the toss velocity
  stay vanilla. The direction is the thrower's FACING (`$C1:0619 lda $50,x /
  and #$01 / eor #$01 / sta $09,x`), so a 19-byte stub at `$DA90` in her `$C1`
  copy re-inverts that bit when DP `$07` (the act the record just supplied) is
  `$7B`. Scoped by act, confined to her copy.
* ⚠ **v0.16.0 got the direction wrong and was retired the same day.** It negated
  her toss record's X velocity instead. The measured outcome was IDENTICAL — and
  it read wrong in play, because she no longer turned around. **Matching the
  measurement is not the same as matching the request:** the ask was "map 6HP to
  4HP", not "make the victim land in front".
* ⚠ **The obvious lead was wrong.** Her button-map record (`$C1:174E` =
  `02 00 04 08 06 00 0a`) differs from the common record by exactly one swapped
  pair, which reads like the answer — but the +0x51 move-request pipeline is
  never written during a throw, so it is unrelated. Measuring the act-setter's
  CALLER (stack return address) is what found the real table.
* Knob `SATURN_THROWFIX=0`. Gate grew to 53 checks — the three new ones assert
  the DIRECTION as well as the act, because an act-only check passes on a build
  that still throws backwards.

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

## Releases — start here (2026-08-05)

What a player applies lives in **`release/`**, not `build/`:
**Rev. S-NN** (the reference build, no Super S content) and **Rev. SS-NN** (the
same plus Saturn). `NN` is `smspaths.REV`, printed on the title screen as
`FrenchName Rev. S-NN` / `FrenchName Rev. SS-NN` — the tell a pad tester quotes.
One recipe builds both (`tools/build_rev.sh s|ss|both`) so they cannot drift;
the notes (`release/RELEASE_NOTES.md`) are generated by `tools/mkrelease.py`
(`--check` to fail on staleness). Neither reference carries **patch 17** — it is
optional and lives in `build/sms_allstages.bps`.

Current: **Rev. 02** (`41d93a53…` / `b96f3fe8…`) = REF v.2's patch set **+ 18**
(no ACS in 2P VS), plus Saturn for SS. Rev. 01 was superseded before release —
it predates patch 18 — and its `.bps` are gone from `release/`, because a
revision names one set of bytes for good.

## Status in one paragraph

The base patch project is done and green. **SMS + Saturn is feature-complete with
no open bugs.** Current build is **v0.16.1**
(`SailorMoonS_REFsaturn_v0.16.1-hidden-stage.sfc`, `c8f7dae8…`, hidden
`91639250…`) on **REF v.2** — patch 100 + 101 + the nameplate, the projectile
fix, her four selectable palettes and **her two ground throws fixed** (both
faults inherited from Super S: the throws were on each other's buttons and the
shoulder throw's toss velocity was negative). (v0.15.0 = v0.14.15 + patch 17 was
built and retired the same day: the maintainer found the stage visually
distracting.) She is summoned by holding **L+R** while confirming a **Uranus, Neptune or
Pluto** slot — the only char-select variant now; the visible slot-10 build was
retired 2026-08-04 and deleted. Gates: `tools/saturn/verify_saturn.sh` (53
checks, ALL PASS; `QUICK=1` for a ~4-min subset) and `tools/test_regression.lua`
(**60/60** since patches 15/17/18 came under the gates and the two config-screen
tests were added; it was 57/57 before 2026-08-06). Maintainer's verdict on the current build: "perfectly acceptable for
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
bash tools/saturn/build_saturn_stage.sh --ref           # + the stage port <- v0.16.1
tools/build_rev.sh both                                 # the two RELEASE builds
tools/saturn/verify_saturn.sh                           # 53 checks, the gate
QUICK=1 tools/saturn/verify_saturn.sh                   # ~4 min subset
ROM=<rom> tools/run.sh tools/test_regression.lua 900    # 60/60 (45 on clean)
tools/health.sh                                         # no ROM/emulator needed
python3 tools/mkpatch16.py <out.sfc>                     # patch 16 (font install)
```

## Session hygiene

Commit per finding; `.sfc` gitignored (rebuild from BPS); **never commit game
imagery or audio** (`.gitignore` blocks both repo-wide — asset policy, 2026-08-04:
screenshots never, savestates yes); never patch in place; every timing/behaviour
claim emulator-verified; all Saturn/Super-S material stays in the `saturn/`
subfolders.
