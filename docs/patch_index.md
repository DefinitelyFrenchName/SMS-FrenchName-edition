# Patch index — the one-page registry

**What this is.** Every patch in the project, one line each, with status and lifecycle
notes — the at-a-glance map when the per-patch detail in `docs/patch_notes.md` is too
much. Update THIS file whenever a patch is added, revised, or deprecated.

All patches are built by `tools/mkpatchN.py`. The *builders* stack in any order (each
re-detects the next free bank), but the standalone **BPS files do NOT** — every
bank-appending BPS (4, 10/10b, 11, 12, 13, 14) is diffed against the clean ROM and
targets the same first-free bank, so chained BPS application corrupts the earlier
patch (see the ⚠️ note below). Custom combos: chain the builders, diff once.
Regression-guarded by `tools/test_regression.lua` (auto-detects which are present).
Current all-patches build: **v0.22** (`3bb9c829…`, rebuilt 2026-07-30 with the patch-4
credit line; pre-credit hash `52bc7e38…`). Also current: the **REF v.1 reference
bundle** (`sms_reference_v1.bps`, ROM `2873f214…`, title tell "FrenchName REF v.1";
pre-credit hash `bd1104ee…`) = 1b+2+3+4+5+7+8+9+12+13+14 — the maintainer-requested
reference combination (true-combo gate; no p6/p10/p11), and **REF v.2**
(`sms_reference_v2.bps`, ROM `6d79fb5f…`, title tell "FrenchName REF v.2",
recipe `tools/build_ref_v2.sh`) = **v.1 + patch 15 (AUTO removal)**. v.2 exists
because v.1 predates patch 15 and therefore still allows AUTO/ACS in 2P VS and
tournament play. **v.1 is deliberately left byte-identical** — it is a
published artifact with a recorded hash, so v.2 is a new name rather than a
redefinition of the old one.

| # | Name | One-liner | Status | Standalone BPS (`build/`) |
|---|---|---|---|---|
| **1** | 1f-link (meaty) | Uranus infinite → 1-frame meaty link (gate 0x04, N=6): one exact press connects, escapable by reversal/jump — the project's founding patch | **CANONICAL** | `sms_uranus_infinite_1f.bps` |
| 1b | 1f-link (true combo) | Alternative gate 0x05 (N=5): the one frame is a true combo instead of a meaty | ALTERNATE (pick 1 *or* 1b, never both) | `sms_uranus_infinite_1f_truecombo.bps` |
| **2** | No reversal-dash invuln | Removes the invincibility of Uranus's guard-cancel ("reversal") Shadow Dash | CANONICAL | `sms_dashfix.bps` |
| **3** | Palettes + header | Big Zam extended color palettes + "FrenchName" internal header | CANONICAL (cosmetic) | `sms_palettes.bps` |
| **4** | Title subtitle | Title-screen version text (doubles as the naked-eye build tell, e.g. "v.0.19"); since 2026-07-30 also swaps copyright line 1 to BZ's "©MOONLIGHT FIGHT SOCIETY" (line 2 "©ANGEL 1994" untouched; `--no-credit` to opt out) | CANONICAL (cosmetic) | `sms_title.bps` |
| **5** | Dash distance | Uranus forward-dash distance −1/3 (121px → 82px — the builder constants are the source of truth; see patch_notes.md) | CANONICAL | `sms_dashdist.bps` |
| 6 | Dash i-frames | Uranus forward dash gains ~6 strike-invuln frames mid-move | EXPERIMENTAL — tension with patch 2's nerf intent; deprecation candidate | `sms_dashinvuln.bps` |
| 7 | Pluto 5HP vs crouchers | Extends Pluto's 5HP active box down so it connects vs crouching opponents (every croucher except Chibi) | OPTIONAL | `sms_pluto5hp.bps` |
| 8 | Venus throw tech | Venus 6HP throw mash-escape window 6f → 13f (standard-ish) | OPTIONAL | `sms_venustech.bps` |
| 9 | Neptune fireball fix | Deep Submerge hitbox tracks the descending sprite (was stuck at head level) | OPTIONAL (bugfix-flavored) | `sms_neptune_ds.bps` |
| 10 | Combo counter | Live in-match combo counter rendered by the base game (no overlay); 2026-07-25: now also shows vs the CPU (mode-gate fix) | OPTIONAL | `sms_combocounter.bps` |
| 10b | + status labels | Combo counter + GC/REVERSAL/PUNISH/TECH event labels (build flag `--events labels`, same patch slot as 10; MEATY label removed 2026-07-20; 2026-07-25 stuck-label expiry bug fixed) | OPTIONAL (variant of 10) | `sms_combolabels.bps` |
| 11 | Training+ | In-ROM training-mode upgrade: L+R menu, dummy control, recording, HP tools, displays | OPTIONAL | `sms_trainingplus.bps` |
| 12 | Taunts | Taunt on L using each character's native misfire animation | OPTIONAL | `sms_taunt.bps` |
| 13 | Guts (v3.3) | Completing a taunt stacks levels (≤3) that shrink the opponent's SPECIAL/desperation damage vs you (20/40/60%, per-round); level indicator shows in TRAINING only (v3.4) | OPTIONAL | `sms_tauntbuff.bps` |
| 14 | Guts Grip | Companion to 13: the same levels also shrink command-grab damage (SPDs/Giant Swing); inert without 13 | OPTIONAL (requires 13 to do anything) | `sms_gutsgrip.bps` |
| 15 | No AUTO | Removes the AUTO option from the VS button-config screen (モード row made inert, so both players stay マニュアル). Auto binds the specials to L/R, which collides with patch 12's taunt and is banned in tournament play. 6 bytes, no bank use; mirrors what the Big Zam Tournament Edition does | OPTIONAL (recommended alongside 12) | `sms_noauto.bps` |

| 16 | Menu translation | **IN PROGRESS — step 1 (font install) WORKS.** Translate the menu text; a standalone patch, NOT a Saturn feature, and must work with or without her. A complete half-width A-Z (`tools/mkhalfwidth.py`, condensed from the game's own capitals) is installed into the menu font sheet `$C4:2590` (418 -> 512 tiles, relocated) and reaches **VRAM tiles $5C0-$5FF**, verified by reading VRAM back (52/64 non-blank = 26 letters x 2 tiles, vs 0 on clean). The blocker was the asset-record layout: it is `[vram16][len16][src24][dest24]`, so the upload LENGTH is 2 bytes BEFORE the src pointer (field `$C3:BF18`, $3480 -> $4000 bytes) — earlier attempts bumped the wrong record. Remaining: step 2, the tilemap edits. The **Options** screen is written but **gated OFF** (`SMS_P16_OPTIONS=1`) — the glyphs do not reach VRAM on that screen even though it runs the extended transfer, so enabling it clears the Japanese and draws nothing. Its budgets ARE measured (18 columns a label, 6 a value; tilemap = asset record 19 `$C3:69F0`) and the maintainer's strings fit; the option VALUES cannot be done in the tilemap at all (rewritten at runtime). Win/ACS screens not yet probed. Detail: `docs/menu_text.md` | IN PROGRESS | — |
| 17 | All stages selectable | **IN PROGRESS.** Make the hidden stage (Nakayoshi editorial department) pickable like any other. Mechanism decoded: `$1F59` has exactly ONE reader (`$C3:AA28`) and one writer (`$C3:BADE`); the reader sets the menu list bound `$1C1C` to 16 (flag set) or 18 (flag clear) — word indices, i.e. **0-8 vs 0-9**. So "a range check" and "a flag" are the same thing. One byte: `$C3:BADE` `8D`->`9C` (`sta`->`stz`), as in `sms_patcher.py PATCH_NAKAYOSHI`. ⚠ **Not confirmed in-game** (first A/B was void — see the commit log) and ⚠ **the one byte covers the MENU only**: `$1C1C` is a generic menu-list length and the RANDOM stage picker is not among its readers, so putting the stage in the pool — which the maintainer also wants — needs that picker located first. Detail: `docs/annotations.md` § Hidden stage | IN PROGRESS | — |

### 100-series — the SMS + Saturn body of work

The gap in numbering is deliberate: 100+ is a different CATEGORY of work (a
character ported from Sailor Moon **Super S**), not another balance or UI tweak,
and it is built and gated by a different toolchain — `tools/saturn/`,
`tools/saturn/build_refsaturn.sh` + `build_saturn_stage.sh`, and
`tools/saturn/verify_saturn.sh` (49 checks) rather than `mkpatchN.py` and the
fingerprint-detected regression rows. `test_regression.lua` still runs on these
builds (57/57) — it just does not *detect* them; the Saturn gate is the Saturn
script, deliberately.

**BPS files for 100/101 are NOT tracked**, unlike every patch above. `build/saturn/`
is gitignored deliberately: a patch-100 BPS embeds her ported Super S cels, palettes
and BRR samples, which is game content, and the asset policy (2026-08-04) keeps that
out of the repo entirely. Rebuild from source — the recipes below are committed, and
the hashes here are the check.

| # | Name | One-liner | Status | Build (`build/saturn/`, untracked) |
|---|---|---|---|---|
| **100** | SMS + Saturn | Sailor Saturn playable in SMS, summoned by holding **L+R** while confirming a Uranus/Neptune/Pluto slot (she wears that character as a "shell"). A COMPOSITE, like the REF bundles: her four animation layers + per-char proc block, card portrait, push-collision fix, sfx remap, projectile palette split, her own voice (in-match + character-select line), her own movelist, and a Super S stage ported onto Pluto's slot. Build flags: `SATURN_HIDDEN=1` (the only shipped variant), `SATURN_VOICE=0`, `SATURN_PITCH` (= patch 101) | **CURRENT** — v0.14.15 on REF v.2, hidden `8c5db8e4…` / +stage `e1788e31…`, feature-complete, no open bugs (v0.14.11 fixed the 214P projectile — the effects DMA was sized from the SHELL, so a Neptune shell truncated her effect sheet by 15 tiles; v0.14.12 makes her four palettes follow the confirm button; v0.14.14 finally fixes the thrown sprite — the $C1 COPY's read of the per-victim pose table was never hooked, so Saturn-as-thrower corrupted the victim, field-confirmed; v0.14.15 retunes her slot-3 palette gold -> near-black on measured contrast) | built by `tools/saturn/build_refsaturn.sh` |
| 101 | Saturn voice pitch | Her voices play ~3 semitones sharp because her samples are natively ~6539 Hz and are played at char 1's notes. Corrects the driver's per-sound TRANSPOSE byte for her four sound ids ($FE/$FE/$FF/$FD → $FB), applied and restored on the same DIRTY-flag machinery as her BRR directory. **Flag on 100's builder** (`SATURN_PITCH=1`), not an independent BPS: the transposes ride streams that 100 owns, and applied WITHOUT 100 the same bytes would flatten Sailor Moon by three semitones | **SHIPPED, ON BY DEFAULT** (2026-08-05; this row said "built, not shipped" until 2026-08-05 — synced from HANDOFF §0, which carries the field verdict: her pitch is correct, and a Moon facing her being three semitones flat is the accepted shared-transpose limitation) — measured correct (all four voices land on `$0346` vs the settled `$0345`); `SATURN_PITCH=0` reproduces patch 100 alone byte-for-byte, see patch_notes `sms_saturn_pitch.bps`, 170 B, diffed 100 → 100+101; ROM `30a130e8…` |

## Lifecycle notes

- **Canonical set** = 1+2+3+4+5 (the original balance+cosmetic core, ROM v0.7 lineage).
  Everything ≥6 is opt-in; the vX.Y "ALLPATCHES" test ROMs carry all of them.
- **Mutually exclusive**: 1 vs 1b (same bytes, different gate value). 10 vs 10b (same
  builder, flag chooses).
- **Dependencies**: 14 reads 13's state (read-only ABI) — stack in any order, but 14
  without 13 is a no-op. **101 is stronger than a no-op without 100: it would be
  actively wrong.** Its four bytes retune sound ids 49-52, which belong to char 1;
  without Saturn's samples loaded behind them that is Sailor Moon's voice, three
  semitones flat. This is why 101 is a build flag rather than a free-standing BPS —
  the dependency is enforced by construction, not by a warning in a table. 13 is playable without 12 only via real ACS-misfire whiffs;
  with 12 the taunt is the intended trigger.
- **Deprecation candidates**: 6 (experimental buff that pulls against patch 2; keep
  only if the maintainer decides dash-invuln is wanted after all). 1b retires whenever
  the canonical gate choice is final.
- ~~Patch 13 indicator → training-only~~ — DONE (v3.4, 2026-07-19).
- **Pruned (2026-07-19)**: all historical cumulative bundles (`sms_full*`,
  `sms_both`, all-patches BPS < v0.19 and the mislabeled v1.x line) — only the
  per-patch standalone BPS above plus the CURRENT `sms_allpatches_vX.Y.bps` are kept.
  Locally kept .sfc: the current ALLPATCHES ROM, `…v0.7_all5.sfc` (the
  non-interference test baseline), and the per-patch standalones the test suites load.
- ⚠️ **Do NOT build a bundle by chaining standalone BPS files** (2026-07-20 correction —
  an earlier note here claimed order-free chaining; that was WRONG). Every
  bank-appending standalone (4, 10/10b, 11, 12, 13, 14) was diffed against the CLEAN
  ROM, so they ALL place their code in the same first-free bank ($E8): applied in
  sequence (which requires overriding the BPS source-checksum error), each one
  **overwrites the previous one's code bank** while the previous hooks still jump
  there — e.g. patch 11's L+R menu silently dies, or the game crashes. Custom
  combinations must be rebuilt by chaining the `mkpatchN.py` builders (each re-detects
  the next free bank), then diffing once against clean.
- Per-patch deep detail (mechanism, changed bytes, verification, version history):
  `docs/patch_notes.md`. Build commands & ROM inventory: `HANDOFF.md`.
