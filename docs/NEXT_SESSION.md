# Next-session handoff — 2026-07-30

Fast orientation. **Full operational map: `HANDOFF.md`; patch registry:
`docs/patch_index.md`; engine subsystems: `docs/sms_engine_internals.md`; per-patch
detail: `docs/patch_notes.md`.**

## Status

All suites green. Current bundles: **v0.22 all-patches** (`3bb9c829…`) and **REF v.1**
(`2873f214…`) — built by the NEW committed recipes `tools/build_v022.sh` /
`tools/build_ref_v1.sh` (lineage: 52bc7e38/bd1104ee → 19a7fc0d/7ab26db4 credit line →
current, after the 2026-07-30 review-remediation fixes). Canonical is still v0.7
(`24aa6b6d…` — reproduces byte-for-byte with the new builders).

**Review remediation (GitHub issues #2–#57, 2026-07-30):** Batches A–C landed — see
HANDOFF §1 and the issue tracker for per-fix evidence. Highlights: .gitignore ROM-commit
hole closed (#26); regression suite is a real gate (exit codes #2, fixtures #4,
silent-skip detection #7, per-player HP streams #16, gate-aware p1 fingerprint #29);
Guts now resets on timed-out rounds (#21, A/B-proven); builders hardened (checksum #9,
unconditional SHA gate + --stacked #12, src!=out #56, donor validation #8, bank guards
#27, p14 clamp #41, p10 flag validation #37 + 99-cap #36, p11 letter-list derived from
p10 #42 + real minus glyph). **Builder chains now need `--stacked` on every stacked
step** (see the build scripts). Standalone hashes changed for p1/1b/2 (checksum now
fixed, #14), p10/10b, p11, p13, p14 — tables updated everywhere.

## What shipped 2026-07-30

**Patch 4 credit line** (maintainer request): title copyright line 1 →
Big Zam's "©MOONLIGHT FIGHT SOCIETY", pixel-identical (54 tiles lifted from BZ title
VRAM via `tools/probe_title_vram.lua`; 3 extra DMA runs, VRAM tiles 0x0C2–0x0FC);
line 2 "©ANGEL 1994" untouched. Default ON in `mkpatch4.py`; `--no-credit` reproduces
the old build byte-for-byte (`e5dce7d5…`). New `sms_title.bps` → `f5337f9a…`,
regression ALL PASS (40). Geometry + verification: docs/patch_notes_title.md.
New probes: `tools/probe_title_vram.lua` (VRAM/CGRAM/screenshot at title),
`tools/probe_title_ppu.lua` (PPU layer state).

**Tooling de-hardcoded:** all Lua tools now resolve paths at runtime via
`tools/sms_env.lua` (bootstrap one-liner + `ENV.ROOT/TOOLS/TRACE`; HANDOFF §5 has the
rules — tool scripts must live in `tools/`); Python builders anchor to the repo via
`__file__`. Everything runs from any cwd/checkout (macOS still assumed). All 14 builders
re-verified byte-for-byte vs tracked BPS; T1–T10 + regression green. Three stale doc
hashes found & fixed (p11/p13/p14). New: `demo_link_headless.lua` (logs the connect
window to a file, exits — use for verification instead of GUI demo_link).

**ROM location now configurable** (`tools/smspaths.py`, mirrored in `run.sh`):
`$SMS_ROM_DIR` → `roms/` → `../roms/` (above the tree = maintainer's preferred layout,
zero commit risk). All three paths + missing-ROM errors verified; builder hash audit
green post-refactor.

**Cross-platform status:** analysis done (2026-07-30, in-chat): Phase 1 Linux / Phase 2
Windows are approved-in-principle but BLOCKED on test OS access (maintainer will provide
Windows first, later); Phase 3 (pure-Python BPS, MesenCE question) out of scope. Local
toolchain is Apple-Silicon-only (Mesen.app/Flips/Dispel arm64, untracked). Mesen pinned
2.1.1 (upstream archived June 2026; successor MesenCE).

## What shipped this session (2026-07-25)

**Patch 10 field report fixed** (maintainer: combo counter never appears — in 1P-vs-COM,
2P VS and training — and status labels never disappear; seen on v0.21 AND p10 standalone).
Root causes, both in `tools/mkpatch10.py`, both A/B-verified in-emulator:

1. **Stuck labels:** `_label_render`'s expiry branch did `sta shown / bne draw` — `sta`
   sets no flags, so the branch tested the stale Z from the labelId≠shown compare and the
   labelId==0 blank path was **unreachable dead code**. On TTL expiry the same glyphs
   were re-staged forever. Latent since v1, masked while the MEATY label (removed
   2026-07-20) churned labelId on nearly every hit. Fix: `cmp #$00` re-test after the
   store. A/B: pre-fix PUNISH drawn@84 never blanks; fixed blanks@131 (47f = TTL).
2. **Counter dead vs the CPU:** `_mode_gate` default excluded `$008D`=2 (1P-vs-COM).
   Default `--modes` now `0,1,2,4,5`. A/B via mode-poke mid-combo (`probe_p10_vs.lua`).
3. **Not bugs, now documented:** the counter pipeline is healthy in 2P VS (shows only on
   true chains ≥ `--min-hits` 2, by design — same semantics as the Lua counter), and the
   counter can never show in practice/training: the hooked HUD producer `$C0:D5E8` does
   not execute there (`probe_p10_practice.lua`, 0 execs/300f) — p11 and the Lua training
   mode carry their own counters. `--ttl` was a dead knob; now wired (default 72 = old
   hardcode, byte-identical).

**Test-gap closed** (old suites were WRAM-only and stayed green through both bugs):
`test_regression.lua` p10-combo-counter is now a VRAM show→count→clear oracle;
`test_labels.lua` asserts the label row blanks within TTL+10f of the event.
New probes: `tools/probe_p10_vs.lua` (pipeline logger + optional `P10_MODE2_FROM/TO`
mode-poke), `tools/probe_p10_practice.lua`, `tools/probe_title_shot.lua` (title
screenshots). `perf_patch10_cfg.lua` STUB_F recomputed → `$EA:06E6` (was stale).
Rebuilt: `sms_combocounter.bps` (`b819f3d4…`), `sms_combolabels.bps` (`38faf40c…`),
**v0.22** bundle. Perf on v0.22: 2.24% worst-case, glyph upload 3 scanlines — fine.

**REF v.1 reference bundle** (maintainer request): 1b+2+3+4+5+7+8+9+12+13+14 →
`build/sms_reference_v1.bps`, ROM `SailorMoonS_FrenchName_REF_v1.sfc` (`bd1104ee…`),
title tell "FrenchName REF v.1" (uppercase E/R glyphs added to `texttiles.py`).
**Patch 12 kept deliberately:** without it p13's Guts grant is unreachable in normal play
(the only other trigger is a real ochame misfire; all ACS stats are 0 in every normal
mode) and p14 is then inert. Regression 55/55 with expected detection (p1 reads absent —
the fingerprint pins gate 0x04; only the true-combo gate byte differs, no test depends
on it). Title verified by screenshot.

## Current state in one breath

14 patches + 2 variants, registry in `docs/patch_index.md`. Canonical = 1+2+3+4+5
(v0.7). Newest all-patches v0.22; reference bundle REF v.1. Regression suite:
59/59 v0.22, 55/55 REF v.1, 41/41 clean. RE campaign CLOSED.

## NEW PROJECT: "SMS + Saturn" (started 2026-07-30) — prep done, route decision made

**Read `docs/saturn/PROJECT.md` first** (the brief), then `docs/saturn/feasibility.md`
(evidence + Route A recommendation: port Saturn INTO SMS), `docs/saturn/supers_map.md`
(verified Super S map — same engine, globally shifted; every Rosetta claim probed),
`docs/saturn/saturn_notes.md` (dossier: act map, box tables, broken normals + fix).
Fixture: `traces/saturn/saturn_vs_uranus_supers.mss` (force-added). Tools:
`smspaths.supers_rom()`, `extract_supers_boxes.py`, `probe_supers_*.lua`,
`probe_saturn_*.lua`.

**All four de-risk unknowns RESOLVED (2026-07-30 later session; HANDOFF §1):**
guard bug = pose-record class byte, **fixed with 1 byte/move A/B-proven** ($84:9289,
$84:927D — the second also fixes close 5HK); animation pipeline fully decoded
(scripts $C0:0000 / pose records $84:809F / cel tables $CB:0000); cel census 137 KB
contiguous; handler sizing (CORRECTED later same day: per-char proc blocks DO
exist, ~4.3 KB — see the smoke-test section below).
**Route A is GO.** SMS's three animation-layer tables LOCATED + LIVE-VERIFIED
(2026-07-30 third session, probe_sms_animtables.lua ALL PASS): scripts `$C0:0000`
(interp `$80:A05C`), pose records `$84:809C` (writer `$C0:9C96`), cels `$CB:0000`
(resolver `$80:9FB8`) — same bases as Super S; Uranus content byte-identical
across games (cel addr24s relocated only). Port recipe per layer in supers_map
§pipeline (note: SMS interpreter lacks Super S's 0xC0 CMD extension — strip or
back-port Saturn's CMD steps; her scripts carry 67 CMD steps).

**Data-unit extractor DONE (`tools/saturn/extract_saturn_unit.py`):** 18 components,
141.4 KB → `build/saturn/unit/` (gitignored — ROM-derived; manifest.json carries
addresses/sha1s/rebase rules/TODOs). Validations: act table = exactly 128 slots
(0x2105-0x2205), 110 scripted acts all parse in-slice; pose records bounds-checked;
cel census re-derived (115 cels, 140000 streamed bytes); ground-truth tripwires
(pose 6B/20/1D bytes, act 4C script shape, marker box 1B zero-size); boxes_hit
cross-checked 30/30 vs supers_all_boxes.json. Extractor TODOs recorded in the
manifest: palette sizes ASSUMED 0x20; recognizer motion-spec format partial;
special act-list per-char indexing + gating-record base not yet located.

**SMOKE TEST DONE — SATURN ANIMATES AND RENDERS IN SMS** (feasibility §Smoke):
`mksaturn_smoke.py` + `probe_sms_saturn_smoke.lua`, 228/228 ALL PASS, screenshots
traces/saturn/saturn_smoke_idle.png / _walk.png (committed). Object id 0x1C, four data
layers injected (a 4TH layer — OAM sprite layout, $84:8000 system — was found
when she rendered invisible; supers_map §OAM). CORRECTION landed: per-char proc
blocks DO exist (~4.3 KB; Saturn $C1:C6F7; main dispatch $C1:0080/($00A6,X) —
entry 0000 recurses = crash). Two engine rules learned: 7 id-indexed tables share
the object-id namespace; DB-swap patches need WRAM-mirror banks ($80-$BF) when
code writes WRAM DB-absolute (use $A8+n mirrors of appended banks).
**PROC BLOCK PORTED (2026-07-30 fourth session; supers_map §Saturn's proc
block):** `tools/saturn/port_saturn_proc.py` recursive-descent disassembles her 4.4 KB
block ($C1:C6F7-DA3C, self-contained incl. inline records), fixes 384 external
operands via the verified Super S→SMS target map, grafts into bank $EF (full
SMS-$C1 copy) behind a 7-byte main-dispatch hook. Verified: idle/walk 228/228
via her real proc; FOUR special variants complete end-to-end (6E/70, 6F/71 →
projectile id 0x20; 6A/6C, 6B/6D → id 0x22); all 15 request nibbles return to
neutral. Projectile spawns self-clear via despawn placeholder entries
(ids 0x1D-0x2F → $C1:0E23) — fireballs invisible until the projectile-object
port. Her sfx silenced ($80:FBB0 CMD/sound handler has no SMS twin — stubbed).
**PAD-PLAYABLE (same session):** button-map hook + recognizer graft + box
tables landed (supers_map §proc block / pad-input layer): real buttons give all
normals (standing/crouch/air), real qcf motion gives the special, hits connect
both ways. **Tester entry point: `tools/saturn/saturn_test.lua`** (Mesen GUI Script
Window on the mksaturn_smoke ROM — auto-transforms P1 at round start; header has
instructions + known gaps). Next: projectile objects 0x20/0x22 (fireballs
visible; 7-table units, source addresses in saturn_notes), palettes, sfx
(needs an SMS sound-API map), throws/desperation verification, then roster/
char-select + REF bank reconciliation (note: smoke claims banks $E8-$F0).

## Open threads (unchanged backlog)

- Maintainer decisions: patch 6 deprecation, patch 1 vs 1b final gate, Guts knob feel,
  whether p14 `--all-grabs` ever ships. Their side: pad-test v0.22 (counter now visible
  vs COM; labels expire) and REF v.1.
- Parked trivia: full per-char d48 census, +0x76 slot meanings, unobserved acts
  (0x07/0x10/0x14), dizzy handler details, ground-vs-air same-throw wiki comparison.
- Rig-limited attested: Jupiter air Power Bomb, Mercury triangle jump.

## Session hygiene

Commit per finding; `git stash -q && git pull --rebase -q && git push -q &&
git stash pop -q` around pushes; `.sfc` gitignored (rebuild from BPS), bundle BPS =
current only; never patch in place; all claims emulator-verified
(`ROM=<build> tools/run.sh <script> <timeout>`); temp files in `$CLAUDE_JOB_DIR/tmp`.
