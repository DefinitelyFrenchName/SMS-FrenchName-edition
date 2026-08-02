# HANDOFF — SMS Sailor Moon S balance/feature patch project

**Read this first.** §0 is the CURRENT state (SMS + Saturn); §1 onward is the completed base patch project. (New session? `docs/NEXT_SESSION.md` is the 60-second orientation.) It is the operational map: current state, deliverables, how to build,
how to test, what was learned, and the traps. Deep per-patch detail is in
`docs/patch_notes.md`; **how the engine works, by subsystem, is in
`docs/sms_engine_internals.md`** (the synthesis — read it to understand or modify the game);
the A.C.S. stat system in `docs/sms_acs_system.md`; the damage system end-to-end
(counter-hit/punish, posture tables, apply-site census, desperation compendium data) in
`docs/sms_damage_system.md`;
address-level notes in `docs/annotations.md`; the verified ROM map in
`docs/sms_uranus_rom_map.md`. Persistent findings also live in the memory file
`uranus-patch-state.md`.

Game: **Bishoujo Senshi Sailor Moon S: Jougai Rantou!?** (SFC, Japan).
Clean ROM SHA-1 `bc0e29ee383574443226695215496eb0d09aaa1c` (HiROM+FastROM, headerless).
HiROM mapping: **file offset = SNES address & 0x3FFFFF**.
Playable roster (charID): 1 Moon, 2 Mercury, 3 Mars, 4 Jupiter, 5 Venus, 6 Uranus,
7 Neptune, 8 Pluto, 9 Chibi Moon. **Saturn (10) is NOT playable.**

---

## 0. Current state (2026-08-03) — SMS + Saturn

The base patch project below is complete and green; active work is the **SMS +
Saturn** effort (brief: `docs/saturn/PROJECT.md`, test ROMs:
`docs/saturn/BUILDS.md`, next steps: `docs/NEXT_SESSION.md`).

**Saturn is playable in SMS**, summoned by holding **L+R** on any character
slot at select (she wears that character as a "shell"). Field-tested repeatedly
by the maintainer. Current builds are **v0.13.1** + a stage-port variant, all on
**REF v.2**.

**She has her own voice as of v0.13.0** (task #44 closed): her win laugh, 236P,
214P and j.632K, injected as a fifth data layer. SMS voices a fighter from a
private ARAM bank (P1 `$B700`, P2 `$DB00`) **plus** a per-character BRR
directory that is resident from boot at `ARAM $34C0 + (charID-1)*32` — so
loading her samples was only half the job, and the directory needed patching
too. She borrows **char 1's** sound ids on whichever side she plays and the
build overwrites char 1's half-record for that player only (the halves are per
player, so it can never collide with a real Moon), restoring it on any
non-Saturn load. One fixed id set, no per-shell code. Mechanism, corrections and
acceptance evidence: `docs/saturn/sound_scope.md` § PHASE 3. **Field-confirmed
2026-08-03** ("a bit weird but definitely the right ones and not distracting").

**v0.13.1 adds her character-select line** ("Yoroshiku", Super S `$EC:C12F`,
2610 bytes). SMS already voices every sailor on confirm from a bank-id table
(`$C0:AE75`, id = 21 + charID) whose single sample goes to ARAM `$B700` and
plays through a fixed directory entry — so she needed only the bank id swapped,
no sound-id change and no directory patch. The player is identified from the
three per-player writers of `$1B1E`, since `$1B1E` itself names the CHARACTER
and she can wear any shell.

**REF v.2** (2026-08-02, maintainer request) = REF v.1 **+ patch 15 (AUTO
removal)** = 1b+2+3+4+5+7+8+9+12+13+14+15. Recipe `tools/build_ref_v2.sh`, ROM
`6d79fb5f…`, regression 57/57. **v.1 is deliberately unchanged** — it is a
published artifact with a recorded hash, so v.2 is a new name rather than a
redefinition. `tools/saturn/build_refsaturn.sh` now targets v.2 by default
(`REF_VERSION=1` selects the old base).

Shipped for Saturn recently: card portrait (art, layout and palette),
push-collision fix, corrected sfx mapping, a Super S stage ported onto Pluto's
slot, and her voice — extracted, approved, and now injected and playing. Open:
movelist (#41) and a stage vertical-scroll artefact (#43).

**Four traps this project paid for — they generalise:**

1. **Per-character fixes must be tested with at least TWO shells.** Saturn can
   be summoned over any of the nine. A hook keyed to *Uranus's* sprite-list
   pointer worked only for that shell and looked like two unrelated bugs.
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

---

## 1. Current state (2026-07-30) — all green

Sixteen patch entries (14 patches + 2 variants), all built and suite-verified. The
**canonical** shipping build is **v0.7**; the newest all-patches test ROM is **v0.22**.

**2026-07-30 — patch 4 credit line (maintainer request):** `mkpatch4.py` now also swaps
title-screen copyright line 1 to the Big Zam edition's **"©MOONLIGHT FIGHT SOCIETY"**
(pixel-identical — 54 tiles lifted verbatim from BZ title VRAM, 3 extra DMA runs over
VRAM tiles 0x0C2–0x0FC; line 2 "©ANGEL 1994" untouched, © glyph shared/skipped).
Default ON; `--no-credit` reproduces the old subtitle-only build byte-for-byte
(`e5dce7d5…`). New standalone `sms_title.bps` → ROM `f5337f9a…`, regression ALL PASS
(40). Detail: docs/patch_notes_title.md. **Both bundles rebuilt with the credit line
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
  bundle recipes `tools/build_v022.sh` / `tools/build_ref_v1.sh` (#10) reflect this.
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
  Bundles: v0.22 `3bb9c829…`, REF v.1 `2873f214…`. Canonical v0.7 `24aa6b6d…`
  unchanged (reproduced byte-for-byte with the new builders).
- Suite-count note: v0.22 full run counts differ slightly from the 07-25 numbers only
  via EXPECT cfg (58 + static-expect-all = 59) — see §4.

**2026-07-30 — "SMS + Saturn" project started (docs/saturn/):** prep + first probes
done. Super S ROM validated (SHA 1ada3417…, resolved via smspaths.supers_rom());
engines proven same-but-shifted (char loader +0x18, on-hit +0x12A, matrix +0x148 with
identical contents; WRAM identical — all probed); Saturn loads via char-select poke
(fixture traces/saturn/saturn_vs_uranus_supers.mss), her box tables extracted
(docs/saturn/supers_all_boxes.json), her far-5HK unblockable CONFIRMED empirically
(hits through held guard 34-44px; 5LP control blocks). Route recommendation: **A —
port Saturn into SMS** (docs/saturn/feasibility.md has the evidence + de-risk probes).
Saturn-reference rule §5 has a scoped exception for this project.

**2026-07-30 (later session) — all four Route A de-risk unknowns RESOLVED:**
(1) **Guard bug root-caused + fixed**: proximity guard is armed by the pose-record
class byte (class 9 = threat; system in docs/saturn/supers_map.md §Pose records);
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
ALL PASS, idle/walk animate, sprites fully coherent (traces/saturn/saturn_smoke_*.png,
committed; Uranus palette — palettes unported). En route: a 4TH animation layer
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
`docs/NEXT_SESSION.md`).

**2026-07-24/25 housekeeping:**
- **Git history was REWRITTEN** (`git filter-repo`, force-pushed): `mockups/` (title-screen
  PNGs containing copyrighted art) was purged from every commit and is now gitignored —
  **every commit hash changed**, so hashes quoted in docs/notes from before 2026-07-24
  refer to the pre-rewrite history and won't resolve. Any stale clone must re-clone or
  hard-reset to the new remote, never push its old history back.
- `patch11-training-rom` was **merged into `main` and deleted** — `main` is the only
  branch and carries everything (all 14 patches, tooling, docs).
- Maintainer added a root **`README.md`** (public-facing intro + a copy of the
  deliverables table — keep it in sync with `docs/patch_notes.md` when patches change).
- Docs refreshed to the 14-patch era: patch_notes.md front matter (deliverables/
  edit-region map/knobs/applying incl. the 2026-07-19 bundle prune), CLAUDE.md banner.

> One-page registry with status/lifecycle (deprecation candidates, exclusivity,
> dependencies): **docs/patch_index.md** — keep it updated when patches change.

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

### Playable ROMs (all in `build/`; `.sfc` are gitignored, rebuild from BPS)
> **2026-07-19 prune:** historical bundles and superseded all-patches BPS/ROMs were deleted (see docs/patch_index.md); rows below describing them are historical record. Kept: per-patch standalone BPS, current all-patches BPS/ROM, and `…v0.7_all5.sfc` (NI-test baseline).
- **`SailorMoonS_FrenchName_v0.7_all5.sfc`** — SHA-1 `24aa6b6d…` — **CANONICAL** (patches 1–5).
- `SailorMoonS_FrenchName_v0.6_all5_truecombo.sfc` — `c96c89fb…` — N=5 true-combo alternative.
- `SailorMoonS_FrenchName_v0.8_all5_dashinvuln.sfc` — `979db260…` — canonical + patch 6 (experimental).
- `SailorMoonS_FrenchName_v0.7_all5_pluto5hp.sfc` — `8e70f452…` — canonical + patch 7 (experimental).
- `SailorMoonS_FrenchName_v0.7_all5_venustech.sfc` — `3e3cd687…` — canonical + patch 8 (experimental).
- `SailorMoonS_FrenchName_v1.0_ALLPATCHES.sfc` — `f20f2883…` — **ALL 10 patches** (canonical 1-5 + optional 6-10, labels on); BPS `build/sms_allpatches_v1.0.bps`.
- `SailorMoonS_FrenchName_v0.7_all5_neptuneds.sfc` — `b1c3163f…` — canonical + patch 9 (experimental).
- `SailorMoonS_FrenchName_v0.7_all5_trainingplus.sfc` — `09106a07…` — canonical + patch 11 (BPS `build/sms_full11_trainingplus.bps`).
- `SailorMoonS_FrenchName_v1.1_ALLPATCHES.sfc` — `be2cb752…` — patches 1-11 (BPS `build/sms_allpatches_v1.1.bps`).
- **`SailorMoonS_FrenchName_v0.22_ALLPATCHES.sfc`** — `3bb9c829…` — **ALL 14 patches, newest test ROM** (BPS `build/sms_allpatches_v0.22.bps`, title v.0.22; built by `tools/build_v022.sh`; lineage: `52bc7e38…` 07-25 fixes → `19a7fc0d…` 07-30 credit line → `3bb9c829…` 07-30 review-remediation fixes).
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
#   tools/build_v022.sh  /  tools/build_ref_v1.sh
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
Headless self-tests: `tools/training_test.lua` (T1–T10, see its header) — T1/T2/T2H/T3/
T5/T6/T7/T10 run on the clean ROM, T4/T8/T9 need a v0.7-family ROM (T10 also passes on
v0.21). T10 locks the 2026-07-21 fix: projectile specials (body never goes active — the
hitbox lives on the projectile slot) must still close their framedata move instance at
neutral, else the attacker sticks in STARTUP, the combo never closes, and HP regen never
fires ("refill only after a normal hit" field report; fix in framedata.lua classify()). Architecture: modules share a ctx
with hook lists; add a feature = one file in tools/training/ + one MODULES entry (main.lua).
Key API facts probed (tools/probe_*.lua): +0x4D=hitstop countdown / +0x43=connect latch;
inputPolled precedes exec@$80:8353; getInput is clean if read before setInput; ScriptHud
size degenerate headless; screenshots don't composite ScriptHud (console surface only).

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
Green: v0.22 = 59 tests, REF v.1 = 55, clean = 41, clean+FULL ≈ 50 (dual-mode expectations flip
with detection; patch tests skip when absent). Engine-rule locks: death-underflow
pair, GC-gate-immediate, backdash-GC, prejump throw-vulnerability, danger threshold,
clock desperation trigger, first-hit-defense pair; statics for matrix, desperation
records, modifier handlers, char-loader. `FULL = true` in the cfg adds the
whole-roster desperation crouch sweep + chip signatures (Pluto strike-throw 1,
Moon zero-chip, Mars full-chip). Patch 9 now has a BEHAVIORAL dual-mode test
(DS vs crouching Chibi connects t<=38 patched / t>=41 vanilla).

**Other tools:** `extract_sms_hitboxes.py` → `docs/sms_all_boxes.json` (per-char box tables);
`extract_proj_boxes.py` (projectile/object box tables, idx 10–27); `ds_trace.lua` /
`ds_overlay.lua` / `ds_hittest.lua` / `ds_clash.lua` (Neptune Deep Submerge fireball: log
projectile slot, draw its live hitbox vs sprite, hit-test a posed target, and a Neptune-mirror
two-fireball clash demo — patch 9 workhorses; states `neptune_vs_{jupiter,chibi,neptune}.mss`);
`tools/Dispel/dispel` disassembler (**build once**: `cc -O2 -o dispel main.c 65816.c` in
`tools/Dispel/`); `texttiles.py` + `mockup.lua` (title font); `mkpatch3` reuses
`vendor/sms-training-mode/sms_patcher.py` for the palette port.

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
- **The extractors cover charIDs 1-9 only** — id 10 "Saturn" is a Sailor Moon Super S
  carry-over that is NOT in this game (no assets ever found despite decades of community
  digging); pre-2026-07-30 extractor versions invented a bogus "Saturn" JSON entry from
  projectile-table bytes (fixed, issue #38). Rule: no SMS-targeted code refers to
  Saturn except explicit warnings like this one. **Scoped exception (2026-07-30): the
  "SMS + Saturn" project** — everything Saturn/Super-S lives in dedicated
  subfolders: `docs/saturn/`, `tools/saturn/`, `traces/saturn/`, `build/saturn/`
  (see `docs/saturn/PROJECT.md` §conventions). Saturn Lua tools bootstrap with
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
# rebuild any BPS and confirm round-trip (current bundles):
./tools/Flips/flips --apply build/sms_allpatches_v0.22.bps "$CLEAN" /tmp/rt.sfc  # sha == 3bb9c829…
./tools/Flips/flips --apply build/sms_reference_v1.bps     "$CLEAN" /tmp/rt.sfc  # sha == 2873f214…
# or rebuild either bundle from source (the committed recipes):
tools/build_v022.sh    # -> 3bb9c829…
tools/build_ref_v1.sh  # -> 2873f214…
```

---

## 7. Repo layout (post-reorg)
```
CLAUDE.md, HANDOFF.md, README.md, .gitignore   ← root only
roms/     clean JP ROM + Big Zam ROM (gitignored; may live in ../roms/ or $SMS_ROM_DIR instead — see §2)
docs/     patch_notes.md, annotations.md, sms_uranus_rom_map.md, sms_all_boxes.json, spec, PDF
tools/    mkpatch*.py, all test/demo .lua, run.sh, coltest, texttiles, Dispel/, Mesen.app, Flips/
traces/   savestates (.mss) + trace outputs (gitignored; key states force-added)
build/    patched .sfc (gitignored) + .bps/.ips patches (tracked)
vendor/   sms-training-mode (RAM map + palette patcher)
```

---

## 8. Open threads / possible future work
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
