# PROJECT: "SMS + Saturn" — Sailor Moon S with Sailor Saturn

> **This is the project brief for a multi-session effort** (started 2026-07-30), the
> same role CLAUDE.md played for the original infinite patch. Companion docs in this
> directory: `feasibility.md` (route decision, evidence), `supers_map.md` (the Super S
> ROM/RAM map — verified facts only), `saturn_notes.md` (Saturn's kit, act IDs, frame
> data, balance hooks). Session state: repo `HANDOFF.md` / `docs/project/NEXT_SESSION.md`; test-ROM registry `BUILDS.md`.

## Objective

A game that **plays like Sailor Moon S** — the SMS engine's rules, timings and
idiosyncrasies, carrying the **REF v.2 patch set** (1b+2+3+4+5+7+8+9+12+13+14+15 — v.1 plus
patch 15's AUTO removal, folded in 2026-08-02) —
extended with:

1. **Sailor Saturn as a 10th playable character** (MUST-HAVE). Source material: the
   sequel *Bishoujo Senshi Sailor Moon Super S — Zenin Sanka!! Shuyaku Soudatsusen*
   (SNES, 1996), the only game where she exists.
2. **Extra stages / music / assets from Super S** (NICE-TO-HAVE).

Regardless of implementation route, **Saturn must be documented the way Uranus was**
(act IDs, hitboxes, frame data, damage, the specific broken tools) so she can be
balance-adjusted — in Super S she is the S-tier problem child the way vanilla Uranus
was in SMS.

## The route decision

- **Route A (preferred a priori): port Saturn INTO the SMS ROM.** Keeps every verified
  SMS behavior bit-exact; costs the character-port work (see feasibility.md).
- **Route B: port SMS's values/patches INTO the Super S ROM.** Saturn pre-exists;
  costs re-deriving every patch hook for Super S **plus reverting the sequel's own
  gameplay changes** (it nerfed projectiles/desperations across the shared cast and
  introduced at least one input regression — see feasibility.md §Super S deltas).
- The decision lives in `feasibility.md` with the evidence and the conditions that
  would flip it.

## Ground truth (validated 2026-07-30 — do not re-derive)

- **Super S ROM**: `SailorMoonSuperS Vol2`, HiROM+FastROM (map byte 0x31), 0x300000
  (3 MB), header game code `$FFB3 = 0x4A` (SMS = 0x51), SHA-1
  `1ada34177e7384612ae83464288f3860e4c4426e`, CRC32 `25440331`. Resolved by
  `tools/smspaths.py: supers_rom()` (same `$SMS_ROM_DIR → roms/ → ../roms/` chain).
- **The vendor Lua is dual-game** (`vendor/sms-training-mode/SailorMoonS.lua` — the
  Rosetta Stone): Super S boxes live in bank `$AF` (ptr tables hit `$AF:B000`, hurt
  `$AF:B046`, coll `$AF:B05C`), palette manifests `$E0:ABC4`, input-read hook
  `$80:8347`, object update `$C1:0000` (same as SMS). Table extents = SMS + exactly
  one roster slot. **Saturn box ptrs: hit `$AF:B014`, hurt `$AF:B05A`, coll
  `$AF:B070`.** WRAM player structs presented as identical across games
  ($7E:1000/1080, all offsets incl. ACS +0x70-75). Verified subset: `supers_map.md`.
- **SMS has NO dormant Saturn slot** (full dossier in `feasibility.md` §Route A):
  every roster table is exactly null+9 and packed; six tables need relocation for a
  10th character; on-hit classes 0x1C-0x1F look unclaimed; ~1 MB headroom under the
  4 MB HiROM ceiling.
- **Saturn's kit is structurally different**: her cancellable-recovery act set has
  8 entries (`{0x41,0x43,0x49,0x4B,0x59,0x5B,0x61,0x63}`) vs 4 for every SMS
  character.
- **Why she's broken in Super S** (Super Fighting Wiki): far 5LK and far 5HK are
  UNBLOCKABLE (guard-proximity data never triggers the guard animation), close 5HK
  nearly so (guardable only at ranges 25-37 standing / 25-32 crouching), plus "weird
  throws". S-tier above Uranus. This reads as a data bug in how she was integrated —
  i.e., fixable by data, which is exactly the balance surface we want documented.
- **Prior art**: "Sailor Moon Fighter S" (romhacking.net/hacks/4498) is a large
  Super S hack (rebalance incl. Saturn changes, new characters, translation) —
  proof of Super S hackability and a reference for what others changed.

## Constraints & conventions (inherited from the SMS project)

- All timing/behavior claims validated by frame-advance in Mesen (tools/run.sh
  harness), never inferred. Ground-truth docs updated per finding.
- Never patch ROMs in place; builders + BPS via flips; `--stacked` on chained steps;
  byte-identity audits after refactors; suites green before shipping.
- ROMs never tracked; resolution via `tools/smspaths.py`.
- The repo-wide "no Saturn references in code" rule (HANDOFF §5) has a **scoped
  exception**, and everything not bound to the original SMS lives in dedicated
  `saturn/` subfolders mirroring `docs/project/saturn/`: **`tools/saturn/`** (all
  Saturn/Super-S probes, extractors, port tools, builders — their Lua bootstrap
  uses `/../sms_env.lua`), **`traces/saturn/`** (Super S fixtures, Saturn
  screenshots, probe outputs), **`build/saturn/`** (the smoke ROM + the
  ROM-derived `unit/` bundle; all gitignored via `build/*`). SMS-targeted code
  keeps the rule and the flat layout.
- The maintainer's dedup rule: common tooling centralized, game-/patch-specific
  logic standalone.
- **Doc separation (maintainer, 2026-07-30):** Saturn-the-character material →
  `saturn_notes.md`; Super S EXTRA assets (stages/music/etc.) → `supers_assets.md`;
  shared engine/ROM facts → `supers_map.md`. Keep them apart.
- **ROM space:** ~1 MB free today. Removing STORY MODE entirely (tournament-edition
  style) is on the table if space runs out, but **requires explicit maintainer
  approval before execution** — never assume it.

## Definition of done (whole project)

1. A shippable BPS (against whichever base the route decision picks) whose ROM:
   plays like SMS (SMS engine invariants green in the regression suite), carries the
   REF v.1 behavior set, and offers Saturn on the character select with working
   normals/specials/throws/desperation, palettes, portraits, theme.
2. `saturn_notes.md` grown into a full Uranus-grade dossier: act table, box tables,
   frame data (oracle-validated), damage values, and the documented broken tools
   with tuning knobs (her guard-proximity data first).
3. Balance pass: her unblockable normals made blockable (data fix), then tuning to
   the maintainer's "minimal playbook-preserving nerfs" philosophy.
4. Test estate: Saturn cases in the regression suite (fixtures, frame-data locks,
   desperation compendium entry), builders with SIG fingerprints, recipes committed.
5. Nice-to-have (separate milestone): Super S stages/music selectable.

## Extended scope — CLOSED (2026-08-04)

1. ~~**Menu translation.**~~ **MOVED OUT of this project** (2026-08-03): a
   **standalone patch** in the main line (patch 16), not a Saturn feature, and it
   must work with or without her. Groundwork, budgets and the font inventory are
   in `docs/project/menu_text.md`; the font path that unblocked it is in
   `docs/project/NEXT_SESSION.md`. The maintainer supplies the translations.
2. ~~**Reveal Saturn earlier in the fight.**~~ **DONE (v0.14.1-v0.14.3).**
   - **Must have — delivered:** she is on screen before the round starts. The
     transform happens one frame after the round goes live (f=1856 against
     f=2099), during the ENTRANCE act `$22`, so she is present for
     STAGE 01 / FIRST BATTLE / READY / GO with no shell frame. `EARLY_TRANSFORM`
     drops the `$1E04` intro-sequencer gate and accepts act `$22`, keeping the
     per-round latch and the live-round gate — the two that actually prove a real
     fight load, which is what made the re-timing safe.
   - **Nice to have — DROPPED, with cause:** the entrance animation cannot be
     hers. v0.14.2 preserved the act across the transform so her own entrance
     script would run; the field found her with no animation and **no inputs
     until she was hit**, because her act-`$22` script never completes and the
     intro sequencer therefore never hands control over. v0.14.3 stopped
     preserving it (`EARLY_KEEP_ACT=0`): she stands at neutral through the
     entrance, visible from the first frame. A/B-verified headless
     (`probe_sms_inputcheck.lua`).

## Character select — one variant only (2026-08-04)

The **hidden code is the only variant**; the v0.10.0 visible slot-10 build is
**retired and its code deleted**. Maintainer: "let's keep only the hidden variant
— it solves our story mode issues and we built and tested everything around it."

It was a placeholder anyway (parked cursor glyph, no portrait or name,
post-confirm screens showed the shell), and it added a navigable char-select
entry — the exact surface the story lock exists to avoid. Removal was proven
inert by rebuilding and diffing: **byte-identical ROM** (`76ba6d8c…` hidden,
`03b73cdd…` stage — those are the **v0.11-era retirement pair**, quoted here
only to record that the diff was byte-identical at that moment; current is
v0.16.1, hidden `91639250…` / hidden+stage `c8f7dae8…`), so no version bump. The `-hidden` filename tag and the `H` in
the on-screen version string stay: every recorded hash and doc reference uses
them, and they are a continuity tell. History: `docs/project/saturn/BUILDS.md`
0.10.0/0.11.0, and git.

## DONE — her round-won badge (v0.17.0, 2026-08-09)

She had no **win icon** under the life bar. Fixed: her medallion is Super S's own,
in her own colours, on both players and every shell. Mechanism, as a game fact:
`../../game/annotations.md` § "Round-won badge"; the port's side is below.

**Why nothing showed.** The badge's top-left cell comes from a **ten-entry table
at `$C0:E166`** indexed by `charID*2`; id `$1C` reads `0x38` past it into CODE at
`$C0:E19E`, which yields `$1E0A` → tile `$20A`, past the end of the 512-tile HUD
sheet. Measured on the unfixed build, the four cells really do hold
`1E0A 1E0B 1E1A 1E1B` and the CHR they point at is blank — so "nothing" was luck,
and garbage was equally available.

⚠ **There are EIGHT reads of that table, not two**, and the count was taken before
anything was written: `$DCC1`/`$DCFC` (descriptor, first draw), `$DE4D`/`$DE5D`/
`$DE79`/`$DE8C` (direct `$2118` redraw), `$DFF9`/`$E034` (descriptor, match end).
**Six are P2 or redraw paths** — a two-site fix passes a one-round P1 test, which
is exactly the test anyone writes first. The gate therefore wins TWO rounds on
both sides.

**What ships** (`SATURN_BADGE=0` restores the old behaviour):

* the table is relocated to bank `$EE` as **29 entries**, id 28 = `$38CE`; the
  four 8-bit-X sites re-encode in place (`ldx`/`txa` zero-extends in two fewer
  bytes than `lda`/`and #$00FF`, which is what makes the long read fit), and the
  two 16-bit-X redraw blocks become one `jsl` each to a stub that reproduces them
  verbatim. A build-time tripwire asserts **zero** surviving reads anywhere in the
  image — the throw corruption's lesson, applied before it could cost anything.
* her four tiles go into the HUD sheet's blank window at **`$CE`/`$CF`/`$DE`/`$DF`
  — Super S's own slots**. The donor stores that sheet RAW at `$E0:D2B8` while SMS
  compresses it at `$E0:21E6`, and **503 of its 512 tiles are byte-identical**, so
  this is a graft into the same sheet rather than a port.
* her icon palette (`$E0:B270`, already extracted as `PALETTES["icon"]`) is copied
  to CGRAM shadow `$0530`/`$0538` by the existing transform palette copier.
  Without it her medallion would wear Uranus's, Neptune's or Pluto's colours and
  change with the shell — measured on the unfixed build, which shows Uranus's.

⚠ **Trap 6 came up and was answered:** her tiles ride the HUD sheet's transfer,
and the job record at `$E0:0000` carries **no length** — the DMA is sized by what
the decoder wrote. So the builder asserts the re-encoded sheet still expands to
exactly `0x2000`, and the gate asserts the tiles arrive identically on both sides
and every shell rather than merely arriving on the one that was tested.

⚠ **The stock encoder could not do this.** `sms_lz.encode` is literals plus one
distance-2 RLE trick and *expanded* the sheet from `0xF31` to `0x1B95`, which
would have forced a relocation and a repointed job entry. `encode_lz` (new, an
optimal parse over the format's real back-references) gets it to `0xF0E` — under
the vanilla stream — so the edit stays in place. `encode` is deliberately
untouched: patch 16 and the movelist call it and their hashes are recorded
(trap 21), and both were rebuilt byte-identical to prove it.

## Parked — not open work, worth revisiting (2026-08-04)

Reviewed with the maintainer and explicitly **not** open items. Listed so they
are not rediscovered later as bugs.

* **Sound mapping is approximate.** SMS whoosh/starter sfx stand in for her Super
  S command sounds. Good enough for now; refine per-move if it ever grates.
* **Her voice pitch: IN-MATCH FIXED by patch 101 (shipped, on by default); only
  the CHARACTER-SELECT line still inherits the shell's pitch.** The parked
  investigation below is from before 101 and is kept for its measurements —
  read it knowing the in-match half is closed (`sound_scope.md`, patch 101:
  transposes `$FE/$FE/$FF/$FD` → `$FB`; accepted limitation, a Moon facing her
  is 3 semitones flat).
  Original entry — **MEASURED 2026-08-04, and
  it is narrower than it looked.** `tools/saturn/probe_sms_voicepitch.lua`
  shadows the DSP register file from the SPC's own port writes ($00F2 index /
  $00F3 data — a write callback on `memType.spcDspRegisters` never fires) and
  reads each voice's SRCN + `VxPITCH` at every key-on.
  * **IN MATCH: not shell-dependent at all.** Her voiced specials key on sources
    49/50/51 at `$03E4`/`$041F`/`$03AC` — byte-identical on shells 6, 7 and 8.
    A full diff of every in-match key-on (voice *and* sfx, source and pitch) for
    the same scripted inputs is identical between shells.
  * **CHARACTER-SELECT CONFIRM: shell-dependent, and inherited from vanilla.**
    The confirm voice (srcn 48) plays at `$04E7` on Uranus and `$0582` on Pluto —
    ~2 semitones apart — and **the vanilla character's confirm voice plays at
    exactly the same pitch on the same shell**. So she is not being mispitched;
    she inherits the shell's pitch wholesale, because that path's sound id is
    per-CHARACTER (`21 + charID`, table `$C0:AE75`) and v0.13.1 swaps only the
    BANK id, not the sound id. (`$04A0` appears on every shell and is a shared
    UI blip, not the voice. Shell 7 showed only `$04A0` — either Neptune's voice
    pitch collides with it or that key-on was missed; unresolved, and it does not
    change the finding.)
  * **Also measured, all identical across shells 6 and 8:** every in-match key-on
    (voice *and* sfx, source and pitch) while she ATTACKS, and every one while
    she is STRUCK — the latter as P2, in hitstun for 626 frames, i.e. the other
    ARAM voice bank. Notable side finding: **no voice-bank sample plays when she
    is hit at all — she has no hurt voice** (none was ported), so whatever is
    audible on hit is a hit sfx, not a voice.
  * **NOT reached, and the maintainer is 90% sure the in-fight case IS
    shell-dependent — so treat this as open, not settled:** her WIN LAUGH (a KO
    could not be driven in the time available) and her j.632K voice. The win
    laugh is the strongest remaining candidate, because round-end is a
    per-winner-id path (v0.11.3 hooks per-winner tables there) — the same shape
    as the select voice, which does vary. Also unmeasured: whether the driver
    modulates pitch AFTER key-on.
  * **Cheapest next input is the maintainer's ear**, on two specific A/Bs: pick
    her on Uranus then on Pluto and compare the "Yoroshiku" (my measurement says
    ~2 semitones apart — audible back to back); and do the same special on two
    shells (my measurement says identical). Either result is informative: a
    confirmed in-fight difference means one of the two unmeasured voiced paths.
  * ~~**For her ORIGINAL pitch:** run this same probe against the SUPER S ROM~~
    **DONE** — Super S plays her select line at `$03FE` (7984 Hz) against SMS's
    `$04E7`/`$0533`; that measurement is what set patch 101's target.
    (`sound_scope.md`.) The maintainer also
    reports the extracted samples sounded at or near original pitch, which is a
    second, independent calibration.
  * **Cost of fixing, if ever wanted:** pin the select path to one sound id for
    Saturn at the hook that already runs there. One value, blast radius limited
    to her confirm voice, and **headlessly gateable** — this probe asserts the
    pitch, so "identical on 6/7/8" can be a check. Worth doing only together with
    measuring what Super S plays her select line at, otherwise it swaps one
    arbitrary pitch for another.
* **Balance.** No balance pass has been done; she is a hidden character of
  admittedly rough balance, which is part of why she is shippable. Her data is
  documented Uranus-grade precisely so a pass is possible later.
* ~~**OBJ palette rows 5 and 6 differ** between a Saturn and a vanilla match.~~
  **CLOSED 2026-08-04 — it was a measurement artifact, and chasing it found
  something worth having.** The rows are **dynamic**: the engine reloads them per
  effect. Sampled at five separate moments inside ONE vanilla match, row 6
  alternates between a flat state and a colour ramp (t=218 flat, 632 ramp, 903
  flat, 1244 ramp, 1915 flat). Comparing a Saturn snapshot against a vanilla
  snapshot taken at different instants therefore compares nothing. Two real
  findings came out of the run, both now permanent checks in
  `verify_saturn.sh`:
  * **OBJ pal 6 is the HIT SPARK** (4 sprites, tiles `$1C2..$1C4`, during
    hitstun). The earlier "nothing uses 5/6" came from a practice-only sample
    that never landed a hit. Had her projectiles been moved onto row 6 instead
    of 7, hit sparks would have broken.
  * **OBJ pal 7 really is free** — 0 uses across three full vanilla matches
    including KO and round end, against 1537-1939 uses in the Saturn runs (her
    projectiles). And **Saturn now draws on pal 2 exactly 0 times** where vanilla
    uses it 718-1605 times, which is the v0.14.9 projectile fix confirmed at
    match scale rather than on one practice screen.
  Lesson, and the reason this was worth doing: **a palette census taken in
  practice mode does not see the effects that only a real match produces.**
