# PROJECT: "SMS + Saturn" — Sailor Moon S with Sailor Saturn

> **This is the project brief for a multi-session effort** (started 2026-07-30), the
> same role CLAUDE.md played for the original infinite patch. Companion docs in this
> directory: `feasibility.md` (route decision, evidence), `supers_map.md` (the Super S
> ROM/RAM map — verified facts only), `saturn_notes.md` (Saturn's kit, act IDs, frame
> data, balance hooks). Session state: repo `HANDOFF.md` / `docs/NEXT_SESSION.md`; test-ROM registry `BUILDS.md`.

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
  `saturn/` subfolders mirroring `docs/saturn/`: **`tools/saturn/`** (all
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
   in `docs/menu_text.md`; the font path that unblocked it is in
   `docs/NEXT_SESSION.md`. The maintainer supplies the translations.
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
`03b73cdd…` stage), so no version bump. The `-hidden` filename tag and the `H` in
the on-screen version string stay: every recorded hash and doc reference uses
them, and they are a continuity tell. History: `docs/saturn/BUILDS.md`
0.10.0/0.11.0, and git.

## Parked — not open work, worth revisiting (2026-08-04)

Reviewed with the maintainer and explicitly **not** open items. Listed so they
are not rediscovered later as bugs.

* **Sound mapping is approximate.** SMS whoosh/starter sfx stand in for her Super
  S command sounds. Good enough for now; refine per-move if it ever grates.
* **Her voice pitch varies with the shell character.** Known and accepted — she
  borrows char 1's sound ids on whichever side she plays and the shell's own
  pitch rides along. Same verdict.
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
