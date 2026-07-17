# HANDOFF — SMS Sailor Moon S balance/feature patch project

**Read this first.** (New session? `docs/NEXT_SESSION.md` is the 60-second orientation.) It is the operational map: current state, deliverables, how to build,
how to test, what was learned, and the traps. Deep per-patch detail is in
`docs/patch_notes.md`; **how the engine works, by subsystem, is in
`docs/sms_engine_internals.md`** (the synthesis — read it to understand or modify the game);
address-level notes in `docs/annotations.md`; the verified ROM map in
`docs/sms_uranus_rom_map.md`. Persistent findings also live in the memory file
`uranus-patch-state.md`.

Game: **Bishoujo Senshi Sailor Moon S: Jougai Rantou!?** (SFC, Japan).
Clean ROM SHA-1 `bc0e29ee383574443226695215496eb0d09aaa1c` (HiROM+FastROM, headerless).
HiROM mapping: **file offset = SNES address & 0x3FFFFF**.
Playable roster (charID): 1 Moon, 2 Mercury, 3 Mars, 4 Jupiter, 5 Venus, 6 Uranus,
7 Neptune, 8 Pluto, 9 Chibi Moon. **Saturn (10) is NOT playable.**

---

## 1. Current state (2026-07-16) — everything green

Ten patches, all built and verified in-emulator. The **canonical** shipping build is **v0.7**.

| # | Patch | Builder | Standalone BPS |
|---|---|---|---|
| 1 | **Infinite → 1-frame meaty (CANONICAL)** | `mkpatch.py 0x04` | `build/sms_uranus_infinite_1f.bps` |
| 1b | Infinite → true 1-frame combo (alt) | `mkpatch.py 0x05` | `build/sms_uranus_infinite_1f_truecombo.bps` |
| 2 | Remove reversal-dash invincibility | `mkpatch2.py` | `build/sms_dashfix.bps` |
| 3 | Big Zam palettes + "FrenchName" header | `mkpatch3.py` | `build/sms_palettes.bps` |
| 4 | Title subtitle text | `mkpatch4.py` | `build/sms_title.bps` |
| 5 | Forward-dash distance −1/3 | `mkpatch5.py` | `build/sms_dashdist.bps` |
| 6 | Forward-dash i-frames (OPTIONAL) | `mkpatch6.py` | `build/sms_dashinvuln.bps` |
| 7 | Pluto 5HP hits crouchers (OPTIONAL) | `mkpatch7.py` | `build/sms_pluto5hp.bps` |
| 8 | Venus 6HP throw tech window 6f→13f (OPTIONAL) | `mkpatch8.py` | `build/sms_venustech.bps` |
| 9 | Neptune Deep Submerge fireball hitbox tracks sprite (OPTIONAL) | `mkpatch9.py` | `build/sms_neptune_ds.bps` |
| 10 | In-match combo counter, base game (OPTIONAL) | `mkpatch10.py` | `build/sms_combocounter.bps` |
| 10b | + status labels GC/MEATY/REVERSAL/PUNISH/TECH (OPTIONAL) | `mkpatch10.py --events labels` | `build/sms_combolabels.bps` |
| 11 | **In-ROM training mode upgrade** (L+R menu, dummy control, recording, displays; OPTIONAL) | `mkpatch11.py` | `build/sms_trainingplus.bps` |
| 12 | **Taunts on L** (native per-char misfire animations; OPTIONAL) | `mkpatch12.py` | `build/sms_taunt.bps` |

### Playable ROMs (all in `build/`; `.sfc` are gitignored, rebuild from BPS)
- **`SailorMoonS_FrenchName_v0.7_all5.sfc`** — SHA-1 `24aa6b6d…` — **CANONICAL** (patches 1–5).
- `SailorMoonS_FrenchName_v0.6_all5_truecombo.sfc` — `c96c89fb…` — N=5 true-combo alternative.
- `SailorMoonS_FrenchName_v0.8_all5_dashinvuln.sfc` — `979db260…` — canonical + patch 6 (experimental).
- `SailorMoonS_FrenchName_v0.7_all5_pluto5hp.sfc` — `8e70f452…` — canonical + patch 7 (experimental).
- `SailorMoonS_FrenchName_v0.7_all5_venustech.sfc` — `3e3cd687…` — canonical + patch 8 (experimental).
- `SailorMoonS_FrenchName_v1.0_ALLPATCHES.sfc` — `f20f2883…` — **ALL 10 patches** (canonical 1-5 + optional 6-10, labels on); BPS `build/sms_allpatches_v1.0.bps`.
- `SailorMoonS_FrenchName_v0.7_all5_neptuneds.sfc` — `b1c3163f…` — canonical + patch 9 (experimental).
- `SailorMoonS_FrenchName_v0.7_all5_trainingplus.sfc` — `09106a07…` — canonical + patch 11 (BPS `build/sms_full11_trainingplus.bps`).
- `SailorMoonS_FrenchName_v1.1_ALLPATCHES.sfc` — `be2cb752…` — patches 1-11 (BPS `build/sms_allpatches_v1.1.bps`).
- **`SailorMoonS_FrenchName_v1.2_ALLPATCHES.sfc`** — `048bd49f…` — **ALL 12 patches** (BPS `build/sms_allpatches_v1.2.bps`, title v.1.2).

Each ROM's BPS is `build/sms_full5_v07_canonical.bps` / `sms_full5_truecombo.bps` /
`sms_full6_v08_dashinvuln.bps` / `sms_full7_pluto5hp.bps` / `sms_full8_venustech.bps` /
`sms_full9_neptuneds.bps`.

---

## 2. How to build

All builders are Python, run from the repo root, and take `(src, out)` positionals (stacking
onto any input ROM). `mkpatch.py` reads the clean ROM only. BPS via `tools/Flips/flips`.

```bash
CLEAN="roms/Bishoujo Senshi Sailormoon S - Jougai Rantou! Shuyaku Soudatsusen (Japan).sfc"
# rebuild the canonical v0.7 chain (N=6):
python3 tools/mkpatch.py  0x04            /tmp/s1.sfc
python3 tools/mkpatch2.py /tmp/s1.sfc     /tmp/s2.sfc
python3 tools/mkpatch3.py /tmp/s2.sfc     /tmp/s3.sfc
python3 tools/mkpatch4.py /tmp/s3.sfc     /tmp/s4.sfc --text "FrenchName v.0.7"
python3 tools/mkpatch5.py /tmp/s4.sfc     /tmp/s5.sfc         # (patch 6/7 optional: mkpatch6/7.py)
./tools/Flips/flips --create --bps "$CLEAN" /tmp/s5.sfc build/out.bps
```

### Tunable knobs (all builder flags — no hex editing; full table in patch_notes.md)
| Knob | Flag | Default | Options |
|---|---|---|---|
| Infinite gate (N) | `mkpatch.py <gate>` | `0x04` | `0x05`=true combo, `0x04`=meaty (canon), `0x03`=removed |
| Dash distance | `mkpatch5.py --speed` | `0x0640` | `0x0B00` vanilla … `0x0480` (−½) |
| Dash i-frames | `mkpatch6.py --lo/--hi` | `5`–`10` | any window in dash frames 1..14 |
| Title text/style | `mkpatch4.py --text/--style` | — | `white_red`/`red_white`/`red` |
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
(MEATY/REVERSAL/PUNISH/COUNTER/THROW TECH/THROWN/TRADE), combo counter (reset-aware),
**hitbox viewer** (live bank-$8A reads, pixel-verified), keyboard menu (M) + pad controls
(hold R = drive dummy, Select = record). Frame-data conventions: S excludes the first
active frame (Dustloop; toggle to SF6 display in menu), counts exclude hitstop, advantage
= neutral-frame delta (oracle-validated: 2LP S4 A5 R4 +6, 2HP S8 A12 R7). GUI: open a match,
run tools/training.lua in the Script Window (enable file access for slot/settings persistence).
Headless self-tests: `tools/training_test.lua` (T1/T2/T2H/T3/T4/T5, see its header) — run all
with the loop in its header; T4 needs a v0.7-family ROM. Architecture: modules share a ctx
with hook lists; add a feature = one file in tools/training/ + one MODULES entry (main.lua).
Key API facts probed (tools/probe_*.lua): +0x4D=hitstop countdown / +0x43=connect latch;
inputPolled precedes exec@$80:8353; getInput is clean if read before setInput; ScriptHud
size degenerate headless; screenshots don't composite ScriptHud (console surface only).

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
- **Savestate ROM-tag:** the Mesen **GUI refuses** a savestate whose embedded ROM doesn't match
  the open ROM; the **headless testrunner is permissive** and loads anything. So any GUI demo
  that `emu.loadSavestate`s a file needs a state tagged to that exact build. Regenerate one by
  loading any state then `emu.createSavestate()` while running the target ROM.
- **Scripts use absolute paths** (`/Users/koneko/Developer/SailorMoonS/...`). The shipped test
  zip includes `fixpaths.sh` to repoint them if extracted elsewhere. On this machine, run from
  the repo.
- **`extract_sms_hitboxes.py` skips Saturn's hurt/coll** (cid>9 → bounds undefined). Saturn
  isn't playable, so this rarely matters, but her hurt boxes aren't in the JSON.
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
# 1-frame-link window on the canonical build (expect a single MEATY frame):
ROM="build/SailorMoonS_FrenchName_v0.7_all5.sfc" tools/run.sh tools/demo_link.lua
# Venus throw-tech window (patch 8): expect TECH [55..72] clean, [55..79] patched:
ROM="build/sms_venustech.sfc" tools/run.sh tools/techsweep.lua 500   # → traces/techsweep_out.txt
# reversal outcome (frame-perfect vs +1 late):
# edit a react_*.lua or pass REACT_MFV; see react_test.lua header.
# patch 11 (in-ROM training mode) feature suite + perf:
ROM="build/sms_trainingplus.sfc" tools/run.sh tools/test_p11_tier1.lua 260   # -> traces/p11_tier1.txt ALL PASS
ROM="build/sms_trainingplus.sfc" tools/run.sh tools/perf_patch11.lua 200     # -> traces/p11_perf.txt PERF PASS
# patch 12 (taunts) suites:
ROM="build/sms_taunt.sfc" tools/run.sh tools/test_p12_taunt.lua 200          # MODE="solo" in cfg
# rebuild any BPS and confirm round-trip:
./tools/Flips/flips --apply build/sms_full5_v07_canonical.bps "$CLEAN" /tmp/rt.sfc  # sha == 24aa6b6d…
```

---

## 7. Repo layout (post-reorg)
```
CLAUDE.md, HANDOFF.md, .gitignore   ← root only
roms/     clean JP ROM + Big Zam ROM (source assets; gitignored contents but tracked)
docs/     patch_notes.md, annotations.md, sms_uranus_rom_map.md, sms_all_boxes.json, spec, PDF
tools/    mkpatch*.py, all test/demo .lua, run.sh, coltest, texttiles, Dispel/, Mesen.app, Flips/
traces/   savestates (.mss) + trace outputs (gitignored; key states force-added)
build/    patched .sfc (gitignored) + .bps/.ips patches (tracked)
mockups/  title-screen mockups
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
- No open bugs. All shipped behavior is measured, not inferred.
