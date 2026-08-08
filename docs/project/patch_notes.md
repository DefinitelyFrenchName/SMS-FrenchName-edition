# patch_notes.md — SMS Uranus balance/feature patches

Target: Bishoujo Senshi Sailor Moon S: Jougai Rantou!? (SFC, Japan),
clean ROM SHA-1 `bc0e29ee383574443226695215496eb0d09aaa1c` (HiROM+FastROM, headerless,
file offset = SNES addr & 0x3FFFFF).

This document covers **seventeen shipped patches plus two variants** (1–5 the original
gameplay/cosmetic core, 6–15/17/18 optional; 1b and 10b are variants of 1 and 10), plus
**patch 16 (menu translation), which is IN PROGRESS** — its per-screen mechanism record
lives in `docs/project/menu_text.md` and its section here is a summary. Each patch is a separate
stackable BPS built by its own `tools/mkpatchN.py`; their edits are byte-disjoint, so they
combine cleanly — but **never combine by chaining standalone BPS files** (bank-$E8
clobber; see "Applying" below and `HANDOFF.md` §5). The **100-series** (100 = SMS + Saturn,
101 = her voice pitch) is a different category of work, built by `tools/saturn/` rather
than by `mkpatchN.py`; only 101 has a section here, and 100's detail lives in
`docs/project/saturn/BUILDS.md`. One-page registry with status/lifecycle: `docs/project/patch_index.md`.
**New here? Read `HANDOFF.md` first** — it is the operational map (current state,
deliverables, tooling, findings, gotchas).

**What a player applies is in `release/`**, not `build/`: **Rev. S-02** (ROM
`41d93a53…`) and **Rev. SS-02** (`b96f3fe8…`), each a complete build, hashes generated
by `tools/mkrelease.py`. The per-patch rows below are for assembling your own
combination. ⚠ Note that **both reference builds ship patch 1b, not patch 1** — the
true-combo gate `0x05`.

## Deliverables & how they stack

| Patch | What | Builder | Standalone BPS | Patched SHA-1 |
|---|---|---|---|---|
| 1. 1f-meaty **(not a true link; gate `0x04`)** | Uranus infinite → **1-frame meaty** (N=6): exactly one press connects, and it's an unblockable-by-block meaty (escapable by invincible reversal / jump). The v0.7 "canonical" lineage's gate | `tools/mkpatch.py 0x04` | `build/sms_uranus_infinite_1f.bps` (+`.ips`) | `258ffd4e…` |
| 1b. 1f-link **(true combo; SHIPPED in both reference builds)** | **Alternative to patch 1** — true unblockable 1-frame combo (N=5); wider (2-frame connect: combo@0 + meaty@+1). This is the gate REF v.1/v.2 and Rev. S/SS carry | `tools/mkpatch.py 0x05` | `build/sms_uranus_infinite_1f_truecombo.bps` (+`.ips`) | `deefccec…` |
| 2. Dash-fix | Remove reversal-dash invincibility | `tools/mkpatch2.py` | `build/sms_dashfix.bps` (+`.ips`) | `14f747a7…` |
| 3. Palettes | Sprint / Big Zam extended character colors ( + "FrenchName" rom header for easy rom ID) | `tools/mkpatch3.py` | `build/sms_palettes.bps` | `291f6474…` |
| 4. Title | Title subtitle → "FrenchName ver. X.Y" + copyright line 1 → BZ's "©MOONLIGHT FIGHT SOCIETY" ("©ANGEL 1994" untouched) | `tools/mkpatch4.py` | `build/sms_title.bps` | `f5337f9a…` |
| 5. Dash dist | Cut Uranus forward-dash distance ~1/3 | `tools/mkpatch5.py` | `build/sms_dashdist.bps` | `99acb686…` |
| 6. Dash i-frames **(OPTIONAL)** | Uranus forward dash gains ~6 strike-invuln frames mid-move | `tools/mkpatch6.py` | `build/sms_dashinvuln.bps` (+`.ips`) | `34c5d458…` |
| 7. Pluto 5HP **(OPTIONAL)** | Pluto 5HP hitbox extended down to hit crouchers (all but Chibi) | `tools/mkpatch7.py` | `build/sms_pluto5hp.bps` | `fc757936…` |
| 8. Venus throw tech **(OPTIONAL)** | Venus 6HP throw mash-escape window 6f → 13f (standard-ish; Jupiter=15f) | `tools/mkpatch8.py` | `build/sms_venustech.bps` | `63ce0748…` |
| 9. Neptune fireball **(OPTIONAL)** | Deep Submerge fireball hitbox tracks the descending sprite (was stuck at head level) | `tools/mkpatch9.py` | `build/sms_neptune_ds.bps` | `d5ee12a3…` |
| 10. In-match combo counter **(OPTIONAL)** | Live combo-hit counter rendered by the base game under each attacker's bar (no overlay needed; 2026-07-25 fix: also shows vs the CPU) | `tools/mkpatch10.py` | `build/sms_combocounter.bps` | `be072a5e…` |
| 10b. + status labels **(variant of 10)** | Counter + GC/REVERSAL/PUNISH/TECH event text (MEATY label removed 2026-07-20; 2026-08-06: labels respect `--modes` #86, repeated events refresh the TTL #88, glyph font uploads lazily #93) | `tools/mkpatch10.py --events labels` | `build/sms_combolabels.bps` | `745ea0bc…` |
| 11. Training+ **(OPTIONAL)** | In-ROM training-mode upgrade: L+R menu, dummy control (pose/guard/wakeup/tech), recording+playback, damage/regen/refill, input+ADV display | `tools/mkpatch11.py` | `build/sms_trainingplus.bps` | `a3aba30d…` |
| 12. Taunts **(OPTIONAL)** | Taunt on L: each character's native misfire ("ochame") pratfall, fully vulnerable | `tools/mkpatch12.py` | `build/sms_taunt.bps` | `614f318e…` |
| 13. Guts **(OPTIONAL)** | Completing a taunt stacks levels (≤3) that reduce the opponent's SPECIAL/desperation damage vs you (20/40/60%, per-round; indicator in training only) | `tools/mkpatch13.py` | `build/sms_tauntbuff.bps` | `bafb87d4…` |
| 14. Guts Grip **(OPTIONAL, companion to 13)** | The same Guts levels also reduce command-grab damage (SPDs/Giant Swing); inert without patch 13 | `tools/mkpatch14.py` | `build/sms_gutsgrip.bps` | `5fadcaca…` |
| 15. No AUTO **(in both reference builds)** | Removes the AUTO option from the VS button-config screen (the モード row goes inert, so both players stay マニュアル); AUTO binds specials to L/R, colliding with patch 12's taunt | `tools/mkpatch15.py` | `build/sms_noauto.bps` | `31832e6e…` |
| 16. Menu translation **(IN PROGRESS)** | English menu text: a half-width A-Z installed into the menu font, then per-screen tilemap/record edits behind build gates. **No standalone BPS yet** — see the patch 16 section below and `docs/project/menu_text.md` | `tools/mkpatch16.py` | — | — |
| 17. All stages **(OPTIONAL, in NEITHER reference build)** | The hidden tenth stage (なかよし編集部) becomes selectable, and — where patch 3 is present — joins its random pool | `tools/mkpatch17.py` | `build/sms_allstages.bps` | `e5dd325b…` |
| 18. No ACS in 2P VS **(in both reference builds)** | The A.C.S. stat-redistribution screen is unreachable in 2P VS only; story and vs-COM keep it. Companion to 15, same screen | `tools/mkpatch18.py` | `build/sms_noacs_vs.bps` | `67897bbf…` |

The 100-series is built and gated separately (`tools/saturn/`, gate
`tools/saturn/verify_saturn.sh`): **100 = SMS + Saturn** (currently v0.16.1, hidden
`91639250…`, hidden+stage `c8f7dae8…`, detail in `docs/project/saturn/BUILDS.md`) and
**101 = her voice pitch** (a build flag on 100, shipped and on by default — section at
the end of this file). Their BPS are deliberately **not tracked**: they embed ported
Super S content (`docs/project/patch_index.md` § 100-series).

Combined builds:

> **The two RELEASE builds** (`release/`, one recipe `tools/build_rev.sh s|ss|both`) are
> what a player applies: **Rev. S-02** = 1b+2+3+4+5+7+8+9+12+13+14+15+18, ROM
> `41d93a53…`, and **Rev. SS-02** = the same plus Saturn, ROM `b96f3fe8…`. Their notes
> (`release/RELEASE_NOTES.md`) are generated from the files, so their hashes cannot go
> stale; the bundles below are development artifacts kept for lineage.
>
> **Current bundle:** `build/sms_allpatches_v0.22.bps` — clean → ALL 14 patches (10 as 10b,
> labels on), title tell "v.0.22", ROM `build/SailorMoonS_FrenchName_v0.22_ALLPATCHES.sfc`
> (SHA-1 `e6b999b5…`; re-recorded 2026-08-06 with the batch-2 fixes to patches 10b/11;
> 07-30 hash `3bb9c829…`, pre-credit `52bc7e38…`). Also current:
> `build/sms_reference_v1.bps` — **REF v.1** = 1b+2+3+4+5+7+8+9+12+13+14, title
> "FrenchName REF v.1", ROM `2873f214…` (pre-credit `bd1104ee…`). **2026-07-19 prune:** the historical cumulative bundles listed below
> (`sms_both`, `sms_full*`, the v1.x line, all-patches < v0.19) were deleted from `build/`
> (see `docs/project/patch_index.md`); the entries are kept as historical record of what each
> lineage contained. Custom combinations are rebuilt by chaining the `mkpatchN.py` builders
> (HANDOFF §2), never by chaining standalone BPS.

- `build/sms_both.bps` — clean → patch 1 + 2 (stacked SHA-1 `5ae720fe…`)
- `build/sms_full.bps` — clean → patches 1 + 2 + 3 (SHA-1 `eb7b86f8…`)
- `build/sms_full4.bps` — clean → patches 1 + 2 + 3 + 4 (SHA-1 `51c397cb…`)
- `build/sms_full5.bps` — clean → **all five** (SHA-1 `b09a189c…`)
- `build/sms_full5_truecombo.bps` — clean → all five with **patch 1b instead of patch 1**
  (true-combo N=5) + title `v.0.6`. Playable ROM
  `build/SailorMoonS_FrenchName_v0.6_all5_truecombo.sfc` (SHA-1 `c96c89fb…`).
  Differs from the v0.5 all-five ROM by exactly **16 bytes**: the gate byte
  `0x1BE23` (`04→05`), 11 title-CHR bytes (the `5→6` version glyph), and 4 header
  checksum bytes — zero other gameplay changes.
- `build/sms_full5_v07_canonical.bps` — clean → **all five, CANONICAL** (patch 1 = N=6
  1-frame meaty) + title `v.0.7`. Playable ROM
  `build/SailorMoonS_FrenchName_v0.7_all5.sfc` (SHA-1 `24aa6b6d…`). This is the recommended
  build (highest version = canonical). Same gameplay as the v0.5 all-five ROM (both N=6);
  it only bumps the title version so the latest number is the one to ship.
- `build/sms_full6_v08_dashinvuln.bps` — clean → all five **+ optional patch 6** (dash
  i-frames) + title `v.0.8`. Playable ROM
  `build/SailorMoonS_FrenchName_v0.8_all5_dashinvuln.sfc` (SHA-1 `979db260…`). An
  **experimental** build for evaluating the dash-invuln buff; canonical stays v0.7.
- `build/sms_full7_pluto5hp.bps` — clean → canonical all-five **+ optional patch 7** (Pluto
  5HP). Playable ROM `build/SailorMoonS_FrenchName_v0.7_all5_pluto5hp.sfc` (SHA-1 `8e70f452…`);
  differs from canonical v0.7 by one gameplay byte (`0xAF0DE 54→62`) + checksum.
- `build/sms_full8_venustech.bps` — clean → canonical all-five **+ optional patch 8** (Venus
  throw tech). Playable ROM `build/SailorMoonS_FrenchName_v0.7_all5_venustech.sfc`
  (SHA-1 `3e3cd687…`); differs from canonical v0.7 by one gameplay byte (`0x16C70 00→01`)
  + checksum.
- `build/sms_full9_neptuneds.bps` — clean → canonical all-five **+ optional patch 9** (Neptune
  Deep Submerge fireball). Playable ROM `build/SailorMoonS_FrenchName_v0.7_all5_neptuneds.sfc`
  (SHA-1 `b1c3163f…`); differs from canonical v0.7 by four gameplay bytes (`0xAFD5D/65/6D/75`,
  the fireball hit-box `y_off`) + checksum.

Edit-region map (why they're disjoint):
- Patch 1: `0x1874D/E` + stub `0x1BE20–29` (bank $C1).
- Patch 2: `0x188ED/E` + stub `0x1BE2A–31` (bank $C1, adjacent free bytes).
- Patch 3: bank-$C0 hooks `0x884B` / `0x8998` / `0xA630`, appended bank $E8
  (file 0x280000+), header `0xFFC0` + checksum.
- Patch 4: bank-$C3 hook `0x3B81F`, appended bank ($E8 standalone / $E9 combined),
  header `0xFFC0` + checksum.
- Patch 5: 2 bytes at `0x188EA/EB` (dash X-speed operand), adjacent to but disjoint
  from patch 2's `0x188ED/EE`.
- Patch 6: bank-$C0 hook `0x09CCD` + stub `0x1BE85` (bank $C1, clear of patches 1/2).
- Patch 7: one byte `0xAF0DE` (bank $8A Pluto hit table).
- Patch 8: one byte `0x16C70` (bank $C1 Venus throw-hold script data).
- Patch 9: four bytes `0xAFD5D/65/6D/75` (bank $8A Deep Submerge fireball hit table `$8A:FD51`,
  object-id 0x18 — exclusive; disjoint from every character/projectile table).
- Patch 10/10b: bank-$C0 hooks `0x0D5E8` (HUD producer) + `0x0D56F` (NMI uploader), stubs in
  an appended bank; WRAM `$0816-$08FF` (unused HUD page tail).
- Patch 11: bank-$80 hook `0x08373` (joy_read tail) + `0x0D574` (uploader body), stubs in an
  appended bank; state `$7F:F000+`, recording ring `$7F:E000`.
- Patch 12: bank-$80 hook `0x08377` (edge derivation), stub in an appended bank; zero WRAM.
- Patch 13: bank-$80 hook `0x0837B` (third in the joy_read chain) + indicator hook `0x0D596`,
  8 strike/chip apply sites in bank $C0 (`0xC09C/C16F/C216/C2C5` melee, `0xC47E/C551/C5F8/
  C6A7` projectile), throw sites `0x1082F` (toss) + `0x10D54` (drain tick), stubs in an
  appended bank; state `$7F:F800-F80A`.
- Patch 14: the 7-byte **tails** of the same toss/tick sites (`0x10835` / `0x10D5A` — right
  after patch 13's 6 subtract bytes, byte-disjoint), stub in an appended bank; scratch
  `$7F:F810-F815`, reads patch 13's state read-only.
- Patch 15: 6 bytes on the config screen's mode-row handler (`0x03A863` / `0x03A87A` /
  `0x03A880`), no bank, no WRAM.
- Patch 16 (in progress): the menu font sheet and, per gate, the screen tilemaps/art
  sheets are **relocated into an appended bank** and their asset records repointed —
  record #27's src + its length field `$C3:BF18`; hooks at `$C3:A4DD` (Options loader),
  `$C3:AF8A` (char-select loader) and `$DF:9679` (report card); in-place record edits in
  bank `$C4` (option values, stage names). No WRAM.
- Patch 17: 1 byte `0x03BADE`, plus — only when patch 3 is present — 2 bytes in patch 3's
  own appended bank (`0x2800D3` / `0x2800D9`), located by signature.
- Patch 18: 12 bytes at `0x03BB9E` (the shared mode-1/2 config handler), no bank, no WRAM.

Note: every bank-appending patch (4, 10/10b, 11, 12, 13, 14) auto-detects the **next free
bank** at build time — that's why builders chain cleanly while standalone BPS files (all
diffed vs clean, all targeting $E8) must never be chained.

## Tunable parameters (the knobs)

Every balance/cosmetic value is a builder argument — nothing needs hex editing. Rebuild the
one patch (or re-run the whole chain) after changing a knob; all stack.

| Knob | Builder & flag | Default | Options / effect |
|---|---|---|---|
| **Infinite gate (N)** | `mkpatch.py <gate>` (positional hex) | `0x04` | `0x05` = N5 true combo (2-frame connect); **`0x04` = N6 1-frame meaty (canonical)**; `0x03` = N7 loop removed. Lower gate = more 2HP recovery before the dash cancel. Byte `0x1BE23`. |
| **Dash distance** | `mkpatch5.py … --speed <hex>` | `0x0640` | `0x0B00` vanilla (121px); `0x0780` ≈ 98px (−1/5); **`0x0640` = 82px (−1/3)**; `0x0480` = 59px (−1/2). 8.8 fixed-point X-speed; lower = shorter. Infinite unaffected (dash stops on contact). |
| **Dash i-frames (opt.)** | `mkpatch6.py … --lo <n> --hi <n>` | `5`–`10` | Strike-invuln while the dash frame-counter `+0x5D` is in `[lo,hi]` (1..14). Default ≈ 6 middle frames. Uranus-only, strike-only. |
| **Title text** | `mkpatch4.py … --text "<str>"` | `"FrenchName ver. 0.4"` | The red subtitle (≤20 chars, the font covers A-Z a-z 0-9 space `.`). Bump the version here. |
| **Title style** | `mkpatch4.py … --style <s>` | `white_red` | `white_red` (white core/red outline), `red_white`, `red`. |
| **Title credit line** | `mkpatch4.py … --no-credit` | credit on | Default swaps copyright line 1 to BZ's "©MOONLIGHT FIGHT SOCIETY" (line 2 "©ANGEL 1994" untouched); `--no-credit` keeps the original line and reproduces the pre-2026-07-30 build byte-for-byte. |
| **Pluto 5HP reach (opt.)** | `mkpatch7.py … --h <n>` | `62` | New active-box height: `54` = vanilla (whiffs crouchers), **`62` = hits all crouchers except Chibi**, `64` = all incl. Chibi. Byte `0xAF0DE`. |
| **Venus tech window (opt.)** | `mkpatch8.py … --extra <n>` | `1` | Extra sampling steps on the throw-hold script: `0` = vanilla 6f, **`1` = 13f (default)**, `2` = 19f, `3` = 24f (whole hold). Standard throws ≈ 15f (Jupiter). Bytes `0x16C70/78/80`. |
| **Neptune fireball box (opt.)** | `mkpatch9.py … --yoff <n>` | `-11` | `y_off` of the 4 active hit boxes vs the projectile origin (ball ≈ origin ±11): **`-11` = centred on the ball (tracks the descent)**; more negative biases higher, less negative lower. `-27`/`-60` = vanilla (floats at head level). Bytes `0xAFD5D/65/6D/75`. |
| **Combo counter (opt.)** | `mkpatch10.py … --min-hits <n> --ttl <f> --modes <list>` | `2` / `72` / `0,1,2,4,5` | Counter appears from N hits; lingers `ttl` frames after the last hit; shows only when `$008D` is in `modes` (`all` = every match). |
| **Status labels (opt.)** | `mkpatch10.py … --events labels` | `off` | Also render GC/REVERSAL/PUNISH/TECH text (patch 10b). MEATY label removed 2026-07-20. |
| **Guts reduction (opt.)** | `mkpatch13.py … --l1 <pct> --l2 <pct> --l3 <pct>` | `20/40/60` | % damage reduction per Guts level vs specials/desperations (build-time 3×128 tables). |
| **Guts Grip reduction (opt.)** | `mkpatch14.py … --l1/--l2/--l3`, `--all-grabs` | `20/40/60` / off | Same per-level % vs command grabs; `--all-grabs` extends to EVERY grab path (normal throws + hold ticks). Keep the percentages aligned with patch 13. |
| **Hidden stage (opt.)** | `mkpatch17.py … --no-pool`, `--bgm <N>` | pool on / vanilla music | `--no-pool` unlocks the stage in the menu but leaves patch 3's random default bounded to nine; `--bgm N` gives it another stage's track (its own is `$06`; the nine normal stages hold `$0A`-`$12`). |
| **Menu translation (in progress)** | `mkpatch16.py`, **env gates** `SMS_P16_OPTIONS` / `SMS_P16_DF` / `SMS_P16_STAGES` / `SMS_P16_ACS` / `SMS_P16_SATURN` | font install always on, every screen gate **off** | Each gate turns on one screen's strings; `SMS_P16_ACS` requires `SMS_P16_STAGES` (they share the glyph block), and `SMS_P16_SATURN` (stage 2 → SILENT THRONE OF MESSIAH) is for a future Saturn chain only. |

Patches 2 (dashfix), 3 (palettes), 11 (Training+ — all settings live in its in-game menu;
`--stage` is a dev/debug flag), 12 (taunts), 15 (No AUTO) and 18 (No ACS in 2P VS) have no
balance knobs — they're single-purpose. Example
retune: `python3 tools/mkpatch.py 0x05 build/n5.sfc` (true-combo gate), or
`python3 tools/mkpatch6.py "<clean>" build/tight.sfc --lo 6 --hi 9` (tighter i-frame window).

---

# Patch 1 — Uranus Infinite™ → 1-frame link

Patched ROM SHA-1 `258ffd4e16910c9aff57a6df019b713ffcf87160`.
Deliverables: `build/sms_uranus_infinite_1f.bps` (canonical), `.ips` (convenience),
built by `tools/mkpatch.py 0x04`.

## What this patch does

The Uranus Infinite™ is `[2LP > 2HP > 66]xN` (Dustloop). The load-bearing link is
**2HP canceled into the 66 forward dash**: the dash (action 0x60) may cancel 2HP
(action 0x55) on any frame from the end of hitstop onward — even during remaining
active frames — as long as the attack has connected, and the 66 double-tap buffers
through the move. The rep then continues with a jab whose press window was 7 frames
wide. This patch delays the dash-cancel availability out of 2HP by **6 frames**, which
shrinks the loop's continuation to a **single viable input frame** (a true 1-frame
link). The infinite is *not removed* — a frame-perfect player can still do it.

## Changed bytes (12 total)

| File offset | SNES addr | Old | New | Meaning |
|---|---|---|---|---|
| 0x1874D | $C1:874D | 52 | 20 | operand of `jsr` in Uranus 2HP handler: `jsr $0952` → `jsr $BE20` |
| 0x1874E | $C1:874E | 09 | BE | (second operand byte) |
| 0x1BE20 | $C1:BE20 | 00 | E2 | stub: `sep #$20` |
| 0x1BE21 | $C1:BE21 | 00 | 20 | |
| 0x1BE22 | $C1:BE22 | 00 | C9 | `cmp #$04` |
| 0x1BE23 | $C1:BE23 | 00 | 04 | **the gate value** (tick threshold) |
| 0x1BE24 | $C1:BE24 | 00 | B0 | `bcs +3` |
| 0x1BE25 | $C1:BE25 | 00 | 03 | |
| 0x1BE26 | $C1:BE26 | 00 | 4C | `jmp $0952` (tail-call the original cancel-commit routine) |
| 0x1BE27 | $C1:BE27 | 00 | 52 | |
| 0x1BE28 | $C1:BE28 | 00 | 09 | |
| 0x1BE29 | $C1:BE29 | 00 | 60 | `rts` |

The stub lives in a 58-byte zero region (0x1BE0E–0x1BE47) between two data blobs at
the end of bank $C1's code. A Lua read-watch over 20,000 frames of gameplay (attract
demo battles, menus, live matches) recorded **zero** accesses to this region on the
clean ROM.

## Mechanism (reverse-engineered)

- Every action of every character has a per-character handler in bank $C1, dispatched
  per frame. Uranus's 2HP (act 0x55) handler is at `$C1:871C`; its running branch:
  `lda #$56 / jsr $04DA` (advance animation; switch to recovery act 0x56 when the
  step tick underflows), `ldy #$7B25 / jsr $0952` (command-cancel check),
  `jsl $80BFBB` (hit check).
- `$C1:0952` = command-cancel commit: requires the **attack-connected flag**
  (player+0x43, cleared at move start, set on connect) — this is why the dash cancel
  only works after a hit/block — then reads the pending command slot (player+0x51/53,
  set by the 66 recognizer state machine at $105D/$105E) and commits the action from
  the per-character table at `$C1:7B25` (Uranus: backdash 0x26, dash 0x60, specials
  0x61/0x62, super 0x72...). Entry `$C1:0958` skips the connected check (used by
  neutral states — neutral dashes are unaffected by this patch).
- Helper `$C1:04DA` conveniently returns with **A = current step tick** (`$06,X`,
  counts down within each animation step). The stub exploits this: after `jsr $04DA`,
  A holds the tick, so gating costs only a compare.
- On a chained point-blank 2HP: hit lands with the active step's tick at 0x0A;
  hitstop freezes 8 frames; ticks 09→00 run on the following frames. The vanilla
  dash fires on the first unfrozen frame (tick 09). The stub allows the commit only
  when tick < 4, i.e. exactly 6 frames later.

## The arithmetic (all values measured by frame-advance; savestate-driven traces)

Rep anatomy on the clean ROM (t = frames from the rep's 2LP press; P1 point-blank):
- 2LP press t=0 → hit t=4 (dmg 3, light stun)
- chain 2HP press t=17 → hit t=25 (dmg 7, heavy stun; P2 escapes such that a
  follow-up hit lands ≤ t=60, i.e. hit-frame 120 absolute in our traces, wins even
  against a block raised the same frame; t=61+ is blocked)
- buffered 66 → dash fires t=34 (first post-hitstop frame; cancels remaining active
  frames of 2HP directly)
- dash = 14 frames + landing; all presses during dash and the first landing frame are
  lost; earliest next-jab press = dash-out + 15, jab starts press+1, hits start+4.

Clean windows (absolute frames from our fixed trace, 2LP@60):
dash-out 94 → viable next-jab presses **109..115** (7 frames), giving jab starts
110..116 and hits 114..120 (deadline 120).

Patch: delay dash-out by N ⇒ every downstream event shifts +N against the fixed
deadline ⇒ press window shrinks to 7−N. For a 1-frame link: **N = 6**
(dash-out 94→100, landing 114-118, single press 115 → start 116 → hit 120).
N = 7 would push the earliest hit to 121 (blocked) and make the loop impossible,
violating the requirement that a frame-perfect re-press still connects.

Gate derivation: dash-out 100 = hit(85) + hitstop(8) + 1 + 6 ⇔ step tick = 3 ⇔
allow commit iff tick < 4 ⇒ `cmp #$04`.

Bonus (measured): the pending 66 command expires after ~2-3 unfrozen frames, so an
early-buffered 66 now **expires before the gate opens** — the second forward tap must
land within ~[gate−2, gate] (3-frame precision) instead of "anywhere during 2HP".

## Verification matrix (all in-emulator, Mesen2 testrunner, deterministic RAM)

1. **+1 proof**: gate 0x09 → dash-out moved 94→95 (exactly +1); no-op gate 0x0B →
   byte-identical behavior to clean. Mechanism proven before applying N=6.
2. **(a) old timing fails**: on the patched ROM, 66 buffered early → dash never comes
   (command expires); next-jab presses 112-114 lost, 116-117 blocked by P2.
3. **(b) frame-perfect works**: press 115 → hit 120 → combo. Full scripted
   **3-rep infinite** vs a down-back-holding P2: 7 consecutive hits at frames
   64, 85, 120, 141, 176, 197, 232 — every link on its single viable frame, P2 never
   entered blockstun, HP 0x60→0x3F.
4. **(c) no side effects**:
   - Whiff traces of 2LP/2HP/2LK/2HK and neutral 66 dash: per-frame logs byte-identical
     clean vs patched.
   - 2HP on hit without dash input: byte-identical.
   - Stub executes ONLY while Uranus is in act 0x55 (exec-watch); zero executions
     during an entire Moon-vs-Moon session (Moon's own 2HP dash-cancel timing
     unchanged — her act 0x55 has its own handler at a different address).
   - Whiffed/blocked-state gating (connected flag) untouched.
5. **BPS round-trip**: `flips --apply` on a fresh verified clean ROM reproduces the
   tested build byte-for-byte.

Known intentional scope: the +6 delay applies to ALL command cancels out of 2HP
(backdash/specials/super share the same commit call) — this is the "increased
effective recovery of 2HP" requested. If 2HP connects meaty (late in its active
window), the remaining ticks are fewer and the delay is correspondingly smaller;
irrelevant to the infinite (which requires point-blank first-active-frame hits) and
to whiffs (no connect flag → no cancel at all, unchanged from vanilla).

## Addendum: reactive-opponent escape matrix (post-release QA)

Scripted dummy attempting escapes between reps ([2LP > 2HP > 66 > 2LP] boundary),
P2 in hitstun until frame 119, deadline hit-frame 120. "Sloppy" = pre-patch optimal
habits (66 buffered during hitstop, jab pressed at the old earliest frame).

| ROM | P1 timing | P2 escape | Outcome |
|---|---|---|---|
| clean | sloppy | guard / jab-mash / backdash | **loop holds** (dash@94, next hit 116, P2 never free) |
| patched | sloppy | guard / jab-mash / backdash | **loop collapses** — buffered 66 expired, no dash at all; P2 blocks or backdashes away |
| patched | frame-perfect | guard | holds — P2's block (0D) raised on 120 is stuffed by the same-frame hit |
| patched | frame-perfect | jab mash | holds — P2's single free frame press never lands |
| patched | frame-perfect | backdash | holds — reversal backdash (0x26) commits on 120, stuffed by same-frame hit before its invuln frames |

Crouching defenders: identical 1-frame link (press 115 only; duck hitstun 0x14/0x15
escape timing matches standing).

Human-tolerance summary per rep on the patched build:
- 66 completion window: ~10+ frames → **3 frames** (98-100; earlier expires, later
  can't combo)
- next-jab press window: 7-8 frames → **1 frame** (115)

Naked-eye A/B test without TAS tools: buffer the 66 *during the 2HP hitstop*
(double-tap immediately after the hit connects). Clean ROM: dash comes out
automatically at the earliest cancel frame. Patched ROM: the buffered input expires
and **no dash comes out at all** — Uranus finishes 2HP recovery. That input-expiry
difference is the patch working; a passive training dummy will otherwise make any
timing "look like" the infinite still works, because late hits still connect on a
non-blocking target.

## Intentional knock-on effects (endorsed as balance)

The +6f delay shifts the whole rep against the fixed hitstun deadline, so cancels that
had slack lose it. Measured, and kept as balance features:
- **Dash → 2HK ender**: on clean it's a true combo (2HK hits frame 118); on the patched
  build the earliest 2HK hits frame 124 and is blockable. The ender is no longer
  guaranteed.
- **Blocked-2HP → dash pressure / SPD mixup**: the dash now starts 6 frames later, giving
  the defender 6 extra reaction frames before the mixup arrives.
- **Not affected**: the dash itself, its landing, neutral 66→anything, and dash→throw /
  dash→SPD input streams are byte-identical to clean (grabs never combo off hitstun, so
  the deadline shift doesn't touch them). Whiffed 2HP has no connect flag → no cancel at
  all → unchanged.
- No single gate value keeps the 2HK ender comboing *and* makes the jab loop 1-frame;
  the ender had more slack than the jab by construction. The gate is one byte
  (`0x1BE23`) if a different trade-off is ever wanted (smaller N widens the jab window).

---

# Patch 1b — 1f-link, true-combo variant (N=5)  *(alternative to patch 1)*

Patched (standalone) SHA-1 `deefccecd1415f64f4bebd2af9c33f91847cd60b`.
Deliverables: `build/sms_uranus_infinite_1f_truecombo.bps` (+`.ips`), built by
`tools/mkpatch.py 0x05`. **Apply this instead of patch 1, not on top of it** — both
write the same gate byte at `0x1BE23`.

## Why this exists (and why patch 1 is the canonical default)

Both gates make the `2HP > 66 > 2LP` loop require a frame-perfect re-press and equally kill
the bufferable/mash version (the gating machinery is identical; only the threshold moves by
one). The difference is *what the single connecting frame is*:

- **N=6 (gate `0x04`, patch 1, CANONICAL):** the one connecting frame is a **meaty** — the
  follow-up 2LP lands on the defender's first frame out of hitstun (crouch-block frame `0x0D`)
  and the engine's *hit-beats-same-frame-block* rule makes it connect. So it is **unblockable
  by holding back**, but a frame-1-invincible reversal or a jump-out can escape it. Exactly one
  press connects (`…114:DROP 115:MEATY 116:BLOCK…`).
- **N=5 (gate `0x05`, patch 1b):** shifts the dash one frame earlier so the 2LP lands while the
  defender is still in hitstun (`0x13`) → a **guaranteed true combo** (nothing escapes). But the
  same-frame quirk means one frame later still connects as a meaty, so the *connect* window is
  two frames (`…114:COMBO 115:MEATY 116:BLOCK…`).

> **History note:** N=6 was earlier mischaracterised in this doc as a "frame trap / blockable."
> That was a measurement-labelling error — the follow-up actually connects as a meaty via the
> same-frame rule; holding down-back does **not** escape it. The demo's verdict now keys on the
> defender's action on the exact hit frame, which resolves the confusion.

Per the maintainer's call, the **1-frame meaty (N=6) is the canonical default**: it is a true
1-frame link (single connecting press) and the meaty leaves a skill-based out (invincible
reversal / jump), which is the preferred balance. N=5 (true combo) remains a shipped
alternative for anyone who wants the follow-up guaranteed. (Full-removal N=7 / gate `0x03`
was declined.)

## Proof: the connect window, auto-measured

`tools/demo_link.lua` **auto-calibrates**: it reloads one savestate and replays the verified
sequence `2LP > 2HP > 66 > (follow-up 2LP)` once for every press frame in a sweep, opponent
holding down-back, and classifies each by **P2's action on the frame the hit connects** —
`DROP` (2LP never comes out), `COMBO` (hit in hitstun), `MEATY` (hit after P2 recovered;
connects via the engine's hit-beats-same-frame-block rule), `BLOCK` (guarded, no damage). It
then reports the exact window for whatever gate the loaded ROM has — no hand-tuned frame.
Deterministic, verified on both builds:

| Build | Sweep result | Window |
|---|---|---|
| **N=6 canonical (v0.7)** | …114:DROP **115:MEATY** 116:BLOCK… | **1-frame MEATY** — one press connects, unblockable by block, escapable by invincible reversal / jump. No true-combo frame. |
| N=5 true-combo (v0.6) | …114:COMBO 115:MEATY 116:BLOCK… | 1 true-combo frame **+** 1 meaty frame = 2-frame connect. |

So N=6 is a genuine **1-frame link** (single connecting frame); the connect is a meaty rather
than a true combo, which is the intended balance (holding back never works; a frame-1
invincible reversal or jump-out does). N=5 trades a second (meaty) connect frame for making
the first frame a guaranteed true combo. The meaty is engine-wide priority behaviour and is
inherent to the same-frame rule.

Run headless: `ROM=build/SailorMoonS_FrenchName_v0.7_all5.sfc tools/run.sh tools/demo_link.lua`.
In the Mesen GUI, open the ROM, then Script Window → `tools/demo_link.lua` → Run; it loads a
matching savestate itself (`traces/uranus_vs_jupiter_v07.mss` by default — states are **tagged
to a ROM**, and Mesen's GUI refuses a mismatched one; pass `LINK_STATE` for another build).
Wrappers `demo_link_early/late/blocked.lua` loop a single attempt at `valid ± n` for a big
verdict; `tools/demo_truecombo.lua` shows the loop being unblockable while P2 holds down-back.

## Wake-up reactions vs the N=6 meaty — the full risk/reward matrix

`tools/react_test.lua` (wrappers `react_{backdash,njump,bjump,grab,jab,chibi5lp,dp}.lua`)
drives the meaty and has the defender attempt a reaction on its wake-up frame, reporting
**HIT** (meaty wins) / **TRADE** (both hit) / **WIN** (defender punishes Uranus) / **BLOCK** /
**ESCAPE** by reading both players' states on the exchange. Set `REACT_MFV = n` to shift the
meaty's press frame (115 = frame-perfect). Verified across characters/options:

| Defender wake-up option | Frame-perfect (`115`) | 1 frame late (`116`) |
|---|---|---|
| Hold block (stand/crouch) | **HIT** — meaty beats same-frame block | **BLOCK** — fully guarding (2LP is mid, blockable standing too) |
| Neutral jump | **HIT** | **HIT** — still can't leave the ground in time |
| 2LP / jab | **HIT** | **HIT** |
| Chibi Moon 5LP (fastest poke) | **HIT** | **HIT** — (needs press `118` to **TRADE**) |
| Back jump | **HIT** | **BLOCK** — up-back resolves to a guard |
| Reversal back-dash | **HIT** — comes out (`0x26`) but no frame-1 invuln | **ESCAPE** — back-dash comes out, both safe |
| 6HP command grab | **HIT** — frame-1 grab, but the strike wins the same wake frame | **WIN** — the frame-1 throw grabs Uranus (she enters *Held* `0x1C`) |
| Neptune DP (`623+HP`) | **HIT** — 2LP hits the DP's vulnerable frame-1 startup (`0x69`) | **WIN** — DP is invincible from frame 2, whiffs the 2LP, **knocks Uranus down** |

**Reading it:** the frame-perfect meaty lands on the defender's single actionable frame (120)
and beats **everything** — even the fastest poke and an invincible reversal (the DP's frame 1
isn't yet invincible). But a **one-frame-late** meaty is punished across the board: blocked
(block / back-jump), escaped (back-dash), or outright beaten (grab throw, DP knockdown). Only
neutral-jump and jab still lose to a 1-late meaty, and even Chibi's 5LP trades at 2-late.

So the balance lands exactly where intended: **the infinite exists only if you are literally
frame-perfect every rep; the instant you are off by a frame you are blockable, throwable, or
reversal-punishable** (and blockstun opens guard-cancel options besides). This is why N=6 (the
1-frame meaty) is canonical — it preserves the execution ceiling without being oppressive.

*(These late-meaty outcomes were found in live testing by the maintainer and reproduced here;
the harness verdicts — throw via the `0x1C` Held state, and trade detection — were fixed to
match.)*

## Every changed byte

Identical to patch 1 except the single gate operand:

| File offset | Clean | Patch 1 (N=6) | Patch 1b (N=5) | Meaning |
|---|---|---|---|---|
| `0x1874C–E` | `20 52 09` | `20 20 BE` | `20 20 BE` | `jsr $0952` → `jsr $BE20` (hook) |
| `0x1BE20–29` | `00…` | stub | stub | `sep #$20; cmp #GATE; bcs +3; jmp $0952; rts` |
| `0x1BE23` | — | `04` | **`05`** | gate = N (recovery frames before dash-cancel is allowed) |

---

# Patch 2 — Remove reversal forward-dash invincibility

Patched (dashfix only) SHA-1 `14f747a7a31b727dd30200d59f1239404fc1ab7b`.
Deliverables: `build/sms_dashfix.bps` (clean → dash-fix), `build/sms_dashfix.ips`
(checksum-free, **stacks onto the 1f-link ROM**), `build/sms_both.bps` (clean → patch 1+2).
Built by `tools/mkpatch2.py`.

## The bug (community: "bugged reversal forward dash")

Uranus's 66 forward dash (action 0x60), performed as a reversal out of knockdown wakeup
(and any other state that allows a command reversal), is fully invincible for its entire
duration. A neutral 66 is not. Dustloop calls it the dash "gaining the invincible
properties of backdash" — mechanically that framing is wrong (see root cause).

## Root cause (found, verified at code level)

- On knockdown, the hit-resolution code (writer at `$C1:0F8D`) sets **player+0x46
  (hurt_state) = 0xA0** — the "untargetable while knocked down" status. It persists
  through the whole knockdown → lying → stand-up chain (actions 0x19/0x1E/0x20), during
  which the character also has no hurtbox.
- Engine convention: **every volitional action's handler clears +0x46 in its step-0 init**
  (`stz $46,X`). Verified across Uranus's attack handlers (e.g., 2HP at `$C1:872A`), her
  other movement handlers (`$C1:88FF`, `$C1:8930`), the landing handler (`$C1:7F1A`), the
  neutral state (`$C1:7D2F`) — and decisively in **Moon's forward-dash handler**, whose
  reversal dash shows +0x46 = A0 only on the 1-frame step-0 carryover, then 00.
- **Uranus's forward-dash handler (`$C1:88C8`) is missing that `stz $46,X`.** So a reversal
  dash carries the knockdown untargetability until the landing handler finally clears it —
  the entire 14-frame, full-screen dash.
- Causality proven by poke: zeroing $1046 mid-reversal-dash makes a meaty attack connect
  on the otherwise-invincible clean ROM.
- Note: backdash (0x26) is invincible **by design** via its animation script using hurtbox
  index 0 — an unrelated mechanism, untouched by this patch.

## The fix (restores the engine-standard clear; 10 bytes)

Reroute the step-0-only `jsr $0389` through a stub that performs the original call and
then the missing clear — exactly what every other handler already does:

| File offset | SNES addr | Old | New | Meaning |
|---|---|---|---|---|
| 0x188ED | $C1:88ED | 89 | 2A | `jsr $0389` → `jsr $BE2A` (operand lo) |
| 0x188EE | $C1:88EE | 03 | BE | (operand hi) |
| 0x1BE2A | $C1:BE2A | 00 | 20 | stub: `jsr $0389` (original X-speed call) |
| 0x1BE2B | $C1:BE2B | 00 | 89 | |
| 0x1BE2C | $C1:BE2C | 00 | 03 | |
| 0x1BE2D | $C1:BE2D | 00 | E2 | `sep #$20` |
| 0x1BE2E | $C1:BE2E | 00 | 20 | |
| 0x1BE2F | $C1:BE2F | 00 | 74 | `stz $46,X` — the missing hurt-state clear |
| 0x1BE30 | $C1:BE30 | 00 | 46 | |
| 0x1BE31 | $C1:BE31 | 00 | 60 | `rts` |

Stub sits in the same verified-unused zero region as patch 1's stub ($C1:BE0E–BE47; zero
accesses over 20k frames of vanilla gameplay), at BE2A — **byte-disjoint from patch 1**
(0x1874D/E + 0x1BE20–29), so they stack. Width safety: `$0389` and the following `$0336`
both begin with `rep #$30`, so the stub's exit state (M=1) matches the handler's step≠0
calling convention.

Coverage of "all reversal contexts": the clear is at the **sink** (the dash's own init),
so any entry path with stale +0x46 is covered by construction — wakeup after sweeps,
throws, air-juggle knockdowns (all converge to stand-up 0x20), etc. Air-reset landings
were already safe (landing handler clears +0x46). The 1-frame step-0 carryover remains,
identical to Moon's dash and every attack.

## Verification

- **Repro on clean**: sweep → wakeup t=159 → reversal dash → P2 meaty (which provably hits
  a non-dashing wakeup at t=161) passes through harmlessly; $1046 = A0 for the whole dash.
- **On dashfix / stacked ROM**: identical scenario → meaty connects at t=161 (P1 → hitstun
  0x16), knocking Uranus out of the dash.
- **No side effects** (clean vs dashfix, per-frame logs byte-identical): neutral forward
  dash; neutral backdash; **reversal backdash** (design invuln intact); whiff traces of
  2LP/2HP/2LK/2HK.
- **Moon-vs-Moon session**: stub never executes (exec-watch = 0); her reversal dash
  unchanged.
- **Patch 1 still functional on the stacked ROM**: dash-out@100, only press-115 continues
  the loop.
- BPS/IPS round-trips: clean→dashfix, dashfix-ips-on-1f-link == stacked reference,
  clean→both — all byte-exact.

---

# Patch 3 — Extended palettes from Sprint (Big Zam extraction) + "FrenchName" header

Patched (palettes only) SHA-1 `291f6474cc0470dde388b73e8aba8bf0bf2d44de`; full (all three)
`eb7b86f8f4196281e7144deeb77b96430d458e03`. Output ROMs are 3 MB.
Deliverables: `build/sms_palettes.bps` (clean → palettes + header), `build/sms_full.bps`
(clean → all three fixes). Built by `tools/mkpatch3.py`.

## What this patch does

1. **Extended character palettes** — up to 32 colors/character, 12 populated (2 defaults +
   10 extras), selectable on character select. This is the Big Zam edition's feature; the
   90 extra palettes (9 characters × 10) are **extracted from the Big Zam ROM** and
   re-inserted, so they render identically.
2. **"FrenchName" ROM-header title** (offset 0xFFC0) — shows in emulator title bars,
   ROM-info dialogs, and flashcart menus. SNES checksum recomputed.

## Provenance & mechanism

Reuses sprntgd's `sms_patcher.py` palette system (`vendor/sms-training-mode/`), which is
also what built the Big Zam edition (confirmed: BZ's non-custom diffs match the patcher's
hook sites exactly). `tools/mkpatch3.py` imports the patcher's `apply_patch`, `PATCH_PAL`,
and `read_int` and applies them non-interactively, so the injected code and pointers are
the battle-tested originals — only the color *data* differs (Big Zam's, not BMP files).

Hook sites (all bank $C0, verified disjoint from the bank-$C1 gameplay patches — the only
base-region bytes patch 3 changes):
- **0x884B–0x88AC** — 1P palette-load map hook (redirects to the per-slot palette block).
- **0x8998–0x89F9** — 2P palette-load map hook.
- **0xA630** — character-select confirm hook → `JSL $E8:000A` (palette select + default
  stage select).
- Appended bank **$E8** (file 0x280000): selection/stage code at 0x28000A, then the palette
  data block from 0x281000. Per character `0x1000` bytes = 32 slots × `0x80`; slot layout
  `[enable-flag word, pad, icon 4×BGR555 @+0x8, character 16 @+0x10, projectile 16 @+0x30]`.
  Defaults (slots 0–1) copied from each character's manifest ($E0:0238+id*2); extras
  (slots 2–11) lifted from the Big Zam block at file 0x2A0000.
- **0xFFC0** header title, **0xFFDC/DE** checksum.

## Selection (character-select screen)

The patch repurposes **Start / L / R as color-range modifiers**, so you now confirm a
character with a **face button**, and that button (+modifier) picks the color:

| Buttons | Color |
|---|---|
| A | 0 (default 1) |
| B | 1 (default 2) |
| Y | 2 |
| X | 3 |
| L + A/B/Y/X | 4–7 |
| R + A/B/Y/X | 8–15 |
| Start + A/B/Y/X | 16–31 |

Big Zam populates colors 0–11 (A/B/Y/X, L+A/B/Y/X, R+A, R+B); higher slots fall back to the
two defaults.

Bundled rider (part of the same indivisible patcher blob, kept as-is per request):
**random stage default** — stage select defaults to random; holding a direction while P2
confirms picks the home stage.

Roster note: the patcher (and thus Big Zam and this patch) covers **Moon…Chibimoon**
(9 characters). Saturn is a Super S character, not in this game, so she has no extended
palettes — correct and expected.

## Verification (CGRAM / screenshot)

- **Selection works**: drove real character-select confirms (A/B/Y/X, L+A, R+A) for Uranus
  on the palettes ROM, reached a live match, dumped CGRAM. Uranus's character palette
  (CGRAM indices 128–142) + projectile (164–174) **differ per confirming button; all six
  tested selections are distinct**. Screenshots confirm visible recolor (A = default navy,
  R+A = silver).
- **Faithful extraction**: `sms_palettes` and `sms_full` produce **byte-identical CGRAM**
  for every selection.
- **Header**: applied ROM header reads `…S FrenchName`.
- **No gameplay regression on the combined build** (`sms_full`, savestate-driven): 1f-link
  dash-out@100 / press-115-only; reversal-dash meaty connects; base-region diff
  stacked→full = only the four bank-$C0 hook sites + header, bank-$C1 patch bytes intact.
- **BPS round-trips**: `flips --apply` on a fresh clean ROM reproduces both builds byte-exact.

On-screen title text (the harder graphics job flagged here originally) is now shipped as
**Patch 4** below.

---

# Patch 4 — Title subtitle → "FrenchName ver. 0.4" + Big Zam credit line

Patched (title only) SHA-1 `f5337f9adfaf7adcd10aaecbc3e6ea8c525e4df3`
(2026-07-30, credit line included; `--no-credit` reproduces the previous
subtitle-only build `e5dce7d5…` byte-for-byte).
Deliverables: `build/sms_title.bps` (clean → subtitle + credit + header),
`build/sms_full4.bps` (clean → all four). Built by `tools/mkpatch4.py`
(+ `tools/texttiles.py`).

## What this patch does

Replaces the red Japanese subtitle (場外乱闘!? 主役争奪戦) with **"FrenchName ver. 0.4"** —
white glyphs, red outline, in the subtitle's own palette. Validated against a
true-to-resolution mockup first; the patched ROM's subtitle band is **pixel-identical** to
the approved mockup.

**2026-07-30 addition:** the first copyright line (©武内直子・講談社・テレビ朝日・東映動画)
is replaced with the Big Zam edition's **"©MOONLIGHT FIGHT SOCIETY"**, pixel-identical to
BZ (tiles lifted verbatim from its title-screen VRAM). The second line **"©ANGEL 1994" is
untouched** (BZ keeps it too), as are the Sailor Moon logo and all menu items. The © glyph
tiles are shared between the two lines' style and identical in clean vs BZ, so they're
skipped. Disable with `--no-credit`.

## Mechanism (Big-Zam-style runtime overwrite; no LZSS encoder)

Title graphics are LZSS-compressed → WRAM staging → DMA'd to VRAM during force-blank. We
don't recompress (the subtitle blob is byte-identical to Big Zam's — BZ doesn't touch it
either); we overwrite the tiles in VRAM right after the game loads them:
- The title CHR loader tail at **`$C3:B81F`** runs `JSL $80:8C43` (DMAs all title graphics
  to VRAM), then `PLB; RTL`.
- We repoint that `JSL` to a **stub in an appended bank**: it calls the original `$80:8C43`
  (subtitle now in VRAM, still force-blank), then DMAs our 42 custom tiles over their VRAM
  slots, then `RTL`s.

VRAM CHR base for BG1 is word `0x2000`, so tile *T* is at word `0x2000 + T*16`. The subtitle
is 42 tiles across tilemap rows 13-14 (each column = a 16px glyph split top/bottom), forming
6 contiguous VRAM runs (0x10D–0x10F, 0x11D–0x11F, 0x120–0x12F, 0x130–0x13F, 0x140–0x141,
0x150–0x151; the gaps are copyright/other tiles, skipped).

The credit line uses the same mechanism: copyright line 1 occupies BG1 tilemap rows 23-24
(cols 2-29, words `18C1…`, palette 6), copyright line 2 rows 25-26 — the tilemap is
**identical** in clean and BZ; BZ only swaps CHR contents. The 54 changed tiles form 3
contiguous VRAM runs (0x0C2–0x0CF, 0x0D2–0x0EC, 0x0F0–0x0FC; 0x0C1/0x0D1 = the © glyph,
identical in both, skipped; 0x0EC/0x0FC are blank in BZ — the Latin line is shorter than
the kanji line, so blanking the tail is required). Tile data is embedded in `mkpatch4.py`
(`CREDIT_TILES_HEX`), extracted from BZ title VRAM via `tools/probe_title_vram.lua` (the
BZ ROM stores these tiles only in a packed/injected form — raw/2bpp/plane searches all
miss — so a one-time VRAM lift is the faithful source). Palette 6 verified identical
clean vs BZ, so colors match by construction.

## Changed bytes

- **0x3B81F–0x3B822**: `22 43 8C 80` (`JSL $80:8C43`) → `JSL` to the stub (bank/addr computed
  from ROM size: `$E8:0000` standalone / `$E9:0000` combined).
- **Appended bank** ($E8/$E9): 276-byte DMA stub (calls `$80:8C43`, then 9 DMA runs) + 3072
  bytes of tile data (42 subtitle + 54 credit tiles × 32B). With `--no-credit`: 195-byte
  stub (6 runs) + 1344 bytes, byte-identical to the pre-2026-07-30 build.
- **0xFFC0** header, **0xFFDC/DE** checksum.

Glyphs are generated by `tools/texttiles.py` (hand-drawn 8×16 proportional pixel font,
baseline-normalized, white-core/red-outline). Changing the text/style regenerates the tiles
and `mkpatch4.py` re-lays the DMA runs automatically.

## Verification

- **Pixel-exact**: patched title subtitle band (y=100–122) identical to the approved mockup
  on both `sms_title` and `sms_full4` (`ImageChops` bbox = None).
- **Isolation**: exactly **42 VRAM tiles changed**, all within the subtitle set; all BG
  tilemaps (VRAM 0x0000–0x3FFF) byte-identical; logo CHR unchanged (the logo-band screenshot
  difference is only the logo's animation phase).
- **Credit line (2026-07-30)**: patched title VRAM diff vs clean = exactly **96 tiles**
  (42 subtitle + 54 credit), zero unexpected; the 54 credit tiles are **byte-identical to
  the Big Zam dump**; tilemaps (0x0000–0x3FFF), VRAM 0x8000+, and CGRAM all identical to
  clean; "©ANGEL 1994" tiles untouched. Title screenshot confirms
  ©MOONLIGHT FIGHT SOCIETY / ©ANGEL 1994 (`traces/titlevram_patched_700.png`).
  Regression suite on the new standalone: **ALL PASS (40)**.
- **No gameplay regression on `sms_full4`**: 1f-link dash-out@100 / press-115-only; reversal
  meaty connects (P1 → hitstun 0x16); palette selection still distinct (A vs Y CGRAM differ).
- **BPS round-trips**: reproduces both builds byte-exact from clean.

Hook safety: the stub runs once during title-load force-blank, calls the original loader
first, and only adds DMAs; it never executes during matches.

---

# Patch 5 — Reduce the forward-dash distance

Patched (standalone) SHA-1 `99acb686…`; all-five `b09a189c…`.
Deliverables: `build/sms_dashdist.bps` (clean → dash distance only), `build/sms_full5.bps`
(clean → all five). Built by `tools/mkpatch5.py`.

## What this patch does

Uranus's forward dash (`66`, action 0x60) is nearly full-screen — one of the reasons she
stays oppressive even after the other fixes. This cuts its neutral travel by roughly a third
(**121px → 82px**) while leaving the 2HP>66 infinite fully intact as a 1-frame link.

## Mechanism (2 bytes)

The dash handler (`$C1:88C8`) sets the dash X-speed with `LDA #$0B00` (0x0B00 = 11.0
px/frame) at file **0x188E9**, then runs for a **fixed 14-frame duration**. The distance is
`speed × duration`; the duration is state-driven, not speed-driven. So lowering the *speed*
(`0x0B00 → 0x0640`, 6.25 px/f) shrinks the distance and changes **no frame timing at all**.

- 0x188EA: `00` → `40`
- 0x188EB: `0B` → `06`   (`LDA #$0640`)

Byte-disjoint from patch 2's reversal hook (0x188ED/EE) and everything else.

## Why the infinite survives

In the loop the dash cancels 2HP and re-closes the small gap to the opponent — and it
**stops on contact** with the opponent's pushbox, so its reduced top speed never matters
there (the gap is ~24-32px, easily covered within 14 frames even at 4.5 px/f). Because the
duration and all timing are unchanged, the whole rep is frame-for-frame identical.

## Verification

- **Distance**: neutral dash 121px → 82px (~68%, i.e. -1/3). Backdash (0x26, separate
  handler) **unchanged** (50px both).
- **1-frame link intact on the all-five build**: frame-perfect rep connects (press 115 →
  hit 120), one-frame-late fails (press 116 blocked) — identical to pre-patch-5; a scripted
  3-rep frame-perfect infinite lands the **identical 7 hits on the identical frames**
  (64/85/120/141/176/197/232) as the full-speed dash.
- **Reversal fix intact**: with the dash coming out on wakeup, the meaty connects (P1 →
  hitstun) — the reversal dash is still non-invincible.
- **BPS round-trips** reproduce both builds byte-exact from clean.

## Tuning

The speed is one 16-bit operand (`0x188EA/EB`); e.g. `0x0480`→59px (half), `0x0640`→82px (shipped, -1/3),
`0x0700`→91px. Adjust in `tools/mkpatch5.py` (`NEW_SPEED`) and rebuild if you want a
different fraction.

## Watching the 1-frame link (demo)

`tools/demo_infinite.lua` (Mesen GUI Script Window, while in a Uranus match) plays the
frame-perfect infinite so you can *see* it still works — it snaps to point-blank and loops
`[2LP > 2HP > 66]xN` against a P2 that's held in guard-after-first-hit (proving the loop is
a true lock, not a blockstring), auto-restarting before a KO. It's the exact per-rep timing
a human would need: one 1-frame jab link + one frame-perfect 66.

---

# Patch 6 — Forward-dash i-frames (OPTIONAL / experimental)

Patched (standalone) SHA-1 `34c5d45810e4ac49bb7ed396bf7e0c5b6db34ed4`. Built by
`tools/mkpatch6.py` (`--lo/--hi` tune the window). **Off by default** — canonical stays v0.7;
the v0.8 build (`build/SailorMoonS_FrenchName_v0.8_all5_dashinvuln.sfc`) folds it in for
evaluation.

## Rationale
The distance nerf (patch 5) made Uranus's forward dash weaker as an approach. This gives it a
short **strike-invulnerability** window mid-move as compensation — a smaller version of the
back-dash's advantage (all characters' back-dash is invuln for its full 14 frames).

## Mechanism (measured, not the +0x46 bug)
Invulnerability in this engine = an **empty hurtbox** (hurtbox index `0`). The back-dash is
invincible precisely because its animation uses hurtbox index 0 for all 14 frames; the forward
dash keeps a real hurtbox (`0x4F`) throughout. The per-frame box writer at **`$C0:9CCD`** does
`sta $41,X` (hurtbox idx) from the animation table. We hook there:

```
0x09CCD:  95 41 B1 10   (sta $41,X ; lda ($10),Y)   ->   22 85 BE C1   (jsl $C1:BE85)
```

Stub at `$C1:BE85` (in the free block clear of the patch-1/2 stubs at `BE20-31`) does the
displaced store, then — **only for Uranus** (`+0x00 == 6`) in a **forward dash** (`+0x01 ==
0x60`) whose **dash-frame counter `+0x5D`** (the 66-recognizer timer, which runs 1..14 across
the dash) is in the window — forces `+0x41 = 0` (empty hurtbox), then does the displaced
collbox load and `rtl`. This is **strike-only** invuln, exactly like the back-dash: the
collision/throw box is untouched, so throws still catch her.

Measured window with `--lo 5 --hi 10`: `+0x5D` reads 06–0B at frame end (the counter is read
one tick before its displayed value), i.e. **~6 invulnerable frames in the middle** of the
14-frame dash. Charge/character-gated, so no other character's dash is affected.

## Verification (on the v0.8 build)
- **Hurtbox goes empty on exactly the window frames** and returns to `0x4F` before/after
  (frame-advance trace of `+0x41`).
- **No spillover on the infinite:** `demo_link` still reports a single **MEATY** connect frame
  (1-frame link unchanged).
- **No spillover on the reversal matrix:** the frame-perfect meaty still HITs every option, and
  a 1-frame-late meaty is still **punished** (Neptune DP → knockdown, Mars grab → throw). The
  invuln window sits during the dash approach (opponent in hitstun), ~15 frames before Uranus's
  punishable 2LP recovery, so it changes none of the risk/reward.
- **Byte-disjoint** from patches 1–5 (bank-`$C0` hook `0x9CCD` + stub `0x1BE85`); stacks freely.

---

# Patch 7 — Pluto 5HP hits crouchers (OPTIONAL / experimental)

Patched (standalone) SHA-1 `fc757936cfc822621233436e9410b3b24548cd83`. Built by
`tools/mkpatch7.py` (`--h` tunes the reach). **Off by default.** Test build:
`build/SailorMoonS_FrenchName_v0.7_all5_pluto5hp.sfc`.

## What & why
Pluto's 5HP is a two-phase move — startup (act `0x44`, boxes 01/04/14) into an overhead
active phase (act `0x46`, hit-box index **`0x03`**). That active box sits high (y `-109..-55`,
i.e. 55–109px above the feet), so it **whiffs crouching opponents** whose hurtbox tops are
below `-55`. The request: extend that box straight down so it connects on crouchers.

## Mechanism (measured)
`hit[0x03]` in Pluto's hit table (`$8A:F0C1`, box at `+0x18`, height byte at file `0xAF0DE`).
The patch increases only its height `h` (top/x/flags untouched → a pure downward extension):

| `h` | box bottom | who it hits crouching |
|---|---|---|
| 54 (vanilla) | −55 | only the tallest crouches (Mars/Uranus/Neptune/Pluto/Moon) |
| **62 (default)** | −47 | **every crouching character EXCEPT Chibi Moon** |
| 64 | −45 | all crouchers including Chibi |

The "all but Chibi" outcome falls out of the geometry: measured crouch-hurtbox tops are Mars
−60 … Moon −56 … Mercury/Jupiter −54, Venus −49, **Chibi −46** (uniquely the shortest). A
bottom of −47 reaches every top except Chibi's −46.

## Verification (test build)
- **All 8 playable crouchers HIT except Chibi** (Moon, Mercury, Mars, Jupiter, Venus, Uranus,
  Neptune, Pluto-mirror hit; Chibi whiffs) — confirmed in-emulator, one state per matchup.
- **No regression:** standing opponents still hit (the box only grows downward; top unchanged).
- **No side effects:** box `0x03` is exclusive to 5HP's active phase (act `0x46`) — Pluto's
  other moves use different box indices (02 / 05 / 01·04·14), so nothing else changes.
- **One byte** (`0xAF0DE`) + checksum; byte-disjoint from patches 1–6.

*(Saturn is not a playable character in this game, so she is not a crouching opponent.)*

---

# Patch 8 — Venus 6HP throw: standard-ish mash-escape window (OPTIONAL / experimental)

**Deliverables:** `tools/mkpatch8.py` (builder, stacks onto any input ROM),
`build/sms_venustech.bps` (standalone, patched SHA-1 `63ce0748…`),
`build/sms_full8_venustech.bps` (canonical v0.7 + this, SHA-1 `3e3cd687…`,
ROM `build/SailorMoonS_FrenchName_v0.7_all5_venustech.sfc`).

## What this patch does
Venus's 6HP proximity throw is the least escapable throw in the game: the mash-escape
("tech") sampling window is **6 frames** where the standard is ~15 (Jupiter measured; the
community's Dustloop numbers — Venus ~6f vs standard 14–19 — agree once measurement
conventions line up). This patch extends her sampling window to **13 frames** (closest the
animation-step granularity allows to the 12-frame design target), keeping a small edge over
standard throws as the original design intended. Nothing else about the throw changes:
same damage (22), same hold/toss timing, same animation, and an un-mashed throw is
frame-for-frame identical (verified byte-identical trace).

## Changed bytes (1 gameplay + checksum)

| File offset | SNES addr | Old | New | Meaning |
|---|---|---|---|---|
| `0x16C70` | `$C1:6C70` | `00` | `01` | byte5 of throw-hold script entry 3 (step 06): enable mash sampling during that step |
| `0xFFDC/DE` | header | — | — | checksum + complement (auto) |

`--extra 2/3` additionally set `0x16C78` / `0x16C80` (entries 4/5, steps 08/0A) for 19f/24f
windows.

## Mechanism (reverse-engineered, all measured in-emulator)
Throws in this game are escaped by **mashing attack buttons**, not by a one-press window:

1. **Connect** (`$C1:0612–65F`): on grab, the victim is set to act `0x1C` (Held), `+0x46=0xA0`,
   and the **thrower's mash counter `+0x56` is zeroed** by the per-character hold handler
   (Venus: `$C1:772C`). An ~8-frame engine freeze follows the connect.
2. **Sampling** (`$C1:07CF–07DC`, inside the script-driven victim-drag routine): on every
   non-frozen frame whose hold-script entry has **byte5 ≠ 0**, if the victim has a freshly
   pressed attack button (`+0x50 & 0xF0`), the thrower's `+0x56` increments. The victim's
   `+0x50` press bits latch on the 30Hz input tick, so ~1 press per 2 frames is the max
   useful mash rate.
3. **Decision** (`$C1:0823–871`, at the toss): `+0x56 >= 2` → victim gets act `0x23`
   (throw tech) and takes **half damage**, both recover; else act `0x1D` (thrown) and full
   damage. The threshold (2) and damage-halving are global; **the only per-throw variable is
   which hold steps sample** — i.e. the script bytes this patch sets.

The hold animation script (8-byte entries per animation step, interpreter `$C1:06E5`,
indexed by thrower `+0x07`) lives at `$C1:6C53` for Venus (only reader of these bytes;
verified by operand scan of bank $C1 + ROM read-watch). Entry byte5 doubles as the damage
value **only** in the header entry (offset +0, read at toss time) — in hold steps it is
purely the sampling gate, so setting it on entries 3–5 has no damage side effect.

Measured sampling schedules (connect at t=60, freeze t=62–69):

| Throw | Script | Sampling frames | Window | Mash-start deadline (2f cadence) |
|---|---|---|---|---|
| Venus 6HP clean | `$C1:6C53` | 61, 70–75 | 6f | connect+12 |
| **Venus 6HP patched** | 〃 (byte5 of entry 3 set) | 61, 70–82 | **13f** | **connect+19** |
| Jupiter 6HP (standard ref) | `$C1:5A07` | 61, 70–84 | 15f | connect+21 |

## Verification matrix (all in-emulator, `tools/techsweep.lua`)
- **Window widened:** press-frame sweep TECHED band `[55..72]` → `[55..79]` (P1 Venus);
  P2-side Venus `[55..80]` (1f input-parity difference, both sides covered).
- **Standard throws unchanged:** Jupiter sweep on patched ROM identical to clean (`[55..81]`).
- **Un-mashed throw unchanged:** full trace clean vs patched **byte-identical** (damage 22,
  toss at connect+34, same act/step/sprite sequence).
- **Mash mechanism intact:** threshold still 6 presses @ gap-2 from connect+1; tech commit
  still `0x23` at the toss frame, normal recovery for both.
- **Naked-eye A/B tell:** mash starting at connect+16 → ESCAPES (half damage) on patched,
  THROWN (full damage) on clean.
- **Full chain:** on `v0.7_all5_venustech`, `demo_link.lua` still reports a single MEATY
  frame (infinite patch untouched) and the Venus window is as above.
- **BPS round-trip:** both BPS re-apply to SHA-1s `63ce0748…` / `3e3cd687…`.
- **Byte-disjoint:** combined ROM differs from canonical v0.7 by `0x16C70` + checksum only.

*(Tooling provenance note: throw action IDs were cross-checked against the game itself, not
the inherited Super S training Lua; its "mash A while mash_time<14" auto-tech is a heuristic
from the other game.)*

---

# Patch 9 — Neptune "Deep Submerge" fireball hitbox follows the sprite (OPTIONAL / experimental)

Builder: `tools/mkpatch9.py` · standalone `build/sms_neptune_ds.bps` · combined
`build/sms_full9_neptuneds.bps` → `SailorMoonS_FrenchName_v0.7_all5_neptuneds.sfc`
(sha1 `b1c3163f…`). OFF by default; canonical stays v0.7.

## What & why
Neptune's **Deep Submerge** projectile (214LP = action `0x62`, 214HP = action `0x63`) is the
famously bugged move: the fireball **sprite descends** on a down-forward arc, but its
**hitbox floats at head level** and doesn't follow — so it whiffs where it visually connects
and connects where the ball isn't. This patch makes the hitbox track the ball for the whole
descent. Sprite trajectory is treated as ground truth (the fix aligns the box to it).

## Mechanism (measured in-emulator)
- Deep Submerge spawns a **projectile object** into slot `$7E:1100`/`$7E:1180` (P1/P2). A
  projectile picks its box table from the hit pointer table `$8A:C1F1` by its **own** `+0x00`
  object id (not the owner's char id). Both LP and HP spawn object id **`0x18`** → hit table
  **`$8A:FD51`** (file `0xAFD51`), which is **exclusive to this fireball** (pointer idx 24; no
  character or other projectile shares it).
- Box position is `screenY = origin_Y(+0x25) + y_off`. Traced (`tools/ds_trace.lua`): the
  fireball's origin `+0x25` **descends** y=128→166 (Yvel +512 LP / +768 HP) while the visible
  ball stays **centred on that origin** (extent ≈ origin ±11). But the hit-box `y_off` values
  were authored for an **upward** path — they climb over the move: entries `1,2,3 = -27`,
  entry `4 = -60`. So the box rises while the ball falls → the box floats 27–60px **above** the
  ball ("mostly stays at head level"). Sprite and hitbox on opposite vertical paths = the bug.
- Overlay (`tools/ds_overlay.lua`) renders the actual box vs the ball: vanilla box sits at
  chest/head height with the ball down on the grass; on the last active frame (box 4) they are
  ~40px apart, zero overlap.

## Changed bytes (4 gameplay + checksum)
Recentre every active hit box on the origin (where the ball is drawn): set each entry's
`y_off` (byte +4) to **`-11`** (`0xF5`), keep height `h=22` and the x offsets. With `y_off=-11,
h=22` the box spans origin −11..+11 = the ball, and being origin-relative-constant it now tracks
the ball for the entire descent (LP and HP share the table).

| file offset | entry | field | vanilla | patched |
|---|---|---|---|---|
| `0xAFD5D` | hit[1] | y_off | `-27` (0xE5) | `-11` (0xF5) |
| `0xAFD65` | hit[2] | y_off | `-27` (0xE5) | `-11` (0xF5) |
| `0xAFD6D` | hit[3] | y_off | `-27` (0xE5) | `-11` (0xF5) |
| `0xAFD75` | hit[4] | y_off | `-60` (0xC4) | `-11` (0xF5) |

Tunable: `mkpatch9.py --yoff <n>` (default `-11`; more negative biases the box higher, less
negative lower). Only the hit boxes change — the fireball's hurt/collision boxes are untouched.

## Verification (in-emulator, both LP and HP)
- **Tracking:** patched overlay shows the box centred on the ball every active frame across the
  descent (vs vanilla floating high). Both LP (boxes 1–4) and HP (boxes 1–2, same table).
- **Connects at the true position/time:** crouching Chibi Moon — patched connects at **t=44**
  with the ball at its real low position (Y=164, box 153–175); vanilla only connects at **t=52**
  (8f later) after the ball travels deep onto Chibi and via the stray high box. Standing targets
  (Chibi, Jupiter) still hit — full-height hurtboxes are unaffected.
- **No side effects:** combined ROM differs from canonical v0.7 by **exactly 6 bytes** — the 4
  `y_off` bytes above + 2 checksum bytes. Neptune's normals/DP/super and every other
  character's projectile are byte-identical (table `$8A:FD51` is fireball-exclusive).
- **BPS round-trip:** `sms_full9_neptuneds.bps` re-applies to sha1 `b1c3163f…`.
- **Impact (surface for the pad):** this is a legitimacy fix but changes coverage — the fireball
  now reliably hits low/crouching targets where the ball passes, and loses the *phantom*
  head-level hit (it no longer clips targets the ball visually flies under). No damage/startup
  change.

## Hurtbox? There isn't one to fix (verified at the disassembly)
Investigated whether the fireball needs a matching hurtbox fix. It does **not** — projectiles
have **no functional hurtbox**. The projectile-collision routine `$C0:C352` resolves the
fireball's hittable/clashable region from its **HIT box** (`$8A:C1F1[objid]`, `+0x40`) — the
same box used both to strike a player *and* to clash another projectile (branch `C395–C3D2`
reads both projectiles' hit boxes) — plus the opponent's hurt box (`$8A:C229[char]`, `+0x41`).
It **never reads the projectile's own `+0x41`**. And the hurt/coll pointer tables are
roster-only (10 entries each; only the HIT table was extended to 28 for projectiles), so object
id `0x18` has no hurt/coll table at all — the `+0x41`/`+0x42` values the shared box-writer
copies from anim data are **vestigial** (never read). Empirically the fireball survives its full
natural lifetime while the opponent attacks it (not destructible by normals). So patch 9's
hit-box fix already makes the fireball consistent **both offensively and defensively** — a clash
now lands at the ball's true position too. No further bytes to change.

---

# Patch 10 — in-match combo counter (base game) (OPTIONAL / experimental)

**Deliverables:** `tools/mkpatch10.py`, `build/sms_combocounter.bps` (standalone, patched
SHA-1 `be072a5e…` since the 2026-07-25 fixes; historical pre-fix `ccdd1510…`),
`build/sms_full10_combo.bps` (canonical v0.7 + this, ROM
`build/SailorMoonS_FrenchName_v0.7_all5_combo.sfc`, SHA-1 `b0d5500f…`, historical). Answers
the feasibility question "can the training-mode combo counter live in the ROM?" — **yes**,
and the measured cost is negligible.

> **2026-07-25 — two field-reported bugs fixed** (maintainer: "counter never appears,
> labels never disappear"; both root-caused in-emulator, `tools/probe_p10_vs.lua`):
> 1. **Stuck labels (10b):** in `_label_render` the expiry branch tested a stale Z flag
>    (`sta` sets no flags after the `cmp shown`), so the labelId==0 blank path was
>    unreachable — on TTL expiry the same glyphs were re-staged forever. Latent since v1;
>    masked while the (removed 2026-07-20) MEATY label churned labelId every few hits.
>    Fixed with a `cmp #$00` re-test; A/B verified (pre-fix: PUNISH drawn @84 never blanks;
>    fixed: blanks @131 = 47f TTL). `test_labels.lua` now has a VRAM expiry oracle.
> 2. **Counter dead vs the CPU:** the mode gate excluded `$008D`=2 (1P-vs-COM) — the mode
>    most play happens in. Default `--modes` is now `0,1,2,4,5`; A/B verified mid-combo
>    (mode poked to 2: pre-fix counter zeroed, fixed counter live).
>
> Also verified: the counter pipeline is **healthy in 2P VS** (mode 1) on old and new
> builds — WRAM→staging→VRAM all fire on a true chain (probe + new regression VRAM
> oracle). And the counter **cannot show in practice/training** ($008D 4/5): the HUD
> producer `$C0:D5E8` this patch hooks never executes there (`probe_p10_practice.lua`,
> 0 execs/300f) — architectural hook-site limit; the gate's 4/5 entries are inert. The
> in-ROM p11 training mode and the Lua training overlay have their own counters.
> `--ttl` was also a dead knob (hardcoded `#$48`); now wired (default 72 unchanged).

## What it does
Renders a live **combo-hit counter** (big yellow digits, up to 99) under the attacker's
health bar — left when P1 combos, right when P2 combos — using the base game's own HUD, so
it shows on real hardware and any emulator with **no Lua overlay**. Counts true chains only
(defender never actionable between hits), exactly like `tools/training/combo.lua`: a hit
after ≥3 free frames restarts at 1; shows from `--min-hits` (default 2), fades after `--ttl`
frames. Mode-gated via `--modes` (default `$008D` ∈ {0,1,2,4,5} = VS, 1P-vs-COM; the 4/5
practice entries are inert — the hooked producer doesn't run there, see fix note above).

## Mechanism (Arch A — reverse-engineered, no new tiles, no NMI surgery)
The in-match HUD is a staging-buffer design: a **main-loop producer `$C0:D5E8`** (scanline
101, once/frame) computes bar+timer tile updates into WRAM `$0806-$0815`; an **NMI uploader
`$C0:D56F`** (scanline 237, vblank) flushes them to VRAM. Patch 10 adds two JML trampolines:
- **compute** (producer hook): per-frame combo tick over both player structs (`+0x49` HP for
  hit detection via a shadow byte, `+0x01` act for the actionable/true-chain test), storing
  state + digit tiles into the **unused HUD page tail `$0816-$08FF`**;
- **flush** (uploader hook): pushes the staged digit tile words to free tilemap cells in
  vblank.
  Big digit tiles 0-9 already exist in the HUD CHR (`0x2C50+N` top, `0x2C60+N` bottom — the
  timer's tiles), and HUD tilemap rows 6-7 are blank, so **no graphics are added** — the patch
  is pure code + WRAM. Full RE map in `docs/game/annotations.md` ("In-match HUD rendering").

## Changed bytes (2 hooks + header/checksum; appended bank for the stubs)

| File offset | SNES addr | Old | New | Meaning |
|---|---|---|---|---|
| `0x0D5E8` | `$C0:D5E8` | `C2 10 E2 20` | `5C ll hh bk` | producer entry → JML compute stub |
| `0x0D56F` | `$C0:D56F` | `C2 30 AD 06` | `5C ll hh bk` | uploader entry → JML flush stub |
| appended bank | `$E8/$EA:0000` | — | ~700 B | compute + flush stubs (auto-placed past ROM end) |
| `0xFFC0`, `0xFFDC/DE` | header | — | — | FrenchName header + checksum |

Byte-disjoint from patches 1–9 (they touch `0x1874D`, `0x188EA-EE`, `0x9CCD`, `0x884B/8998/
A630`, `0x3B81F`, `0xAF0DE`, `0x16C70`, `0xAFD5D-75`; stubs `0x1BE20-31/0x1BE85`). WRAM
scratch `$08A0-$08FF` verified unused; VRAM cells (`$10C2/C3/E2/E3`, `$10DC/DD/FC/FD`) are
blank tilemap cells the game never writes in-match.

## Performance (the measured answer)
Over the infinite-rep scenario (`cpu.cycleCount` deltas): **compute stub mean 191 / max 254
cycles/frame** (main loop, scanline 101 — huge headroom before vblank), **flush stub 44
cycles/frame** (vblank, trivial). Frame budget ≈ 40,951 cycles → **~0.57 % overhead**.
Definitive lag test: clean vs patched with identical scripted inputs — the two players'
gameplay RAM (`$1000-$10FF`) and the round timer are **frame-identical** the entire scenario
⇒ **zero added lag frames, zero gameplay change** (the patch only reads structs and writes
its own scratch + free VRAM cells).

## Verification (`tools/test_patch10.lua`, headless)
- **Oracle equivalence:** the ROM counter (`$08B0`) equals the Lua combo module's count
  frame-for-frame across the infinite rep (0 mismatches), peaking at 3.
- **Digit render:** poked values stage the correct tile words — `3`→ones `2C53`/tens blank
  (leading-zero suppression), `15`→`2C51`+`2C55`, `7`→`2C57`; visually confirmed on-screen
  (screenshots: live "3", poked "15"/"8" on both sides).
- **Gating:** in a disallowed mode the counter blanks (pre-2026-07-25 this wrongly
  included `$008D`=2 = 1P-vs-COM; mode 2 is now allowed by default).
- **Non-interference / no lag:** frame-identical gameplay RAM + timer clean vs patched.
- **Packaging:** BPS round-trip SHA-1 `be072a5e…`; hooks byte-disjoint from patches 1–9.

## Knob
| Knob | Flag | Default | Effect |
|---|---|---|---|
| Min hits to show | `mkpatch10.py --min-hits` | `2` | counter appears from N hits |
| Display TTL | `mkpatch10.py --ttl` | `72` | frames the count lingers after the last hit |
| Mode gate | `mkpatch10.py --modes` | `0,1,2,4,5` | `$008D` values to show in; `all` = every match |

## Status labels (`--events labels`)

Adds on-screen text under each attacker for the training-mode events — **GC, REVERSAL,
PUNISH, TECH** (THROW TECH shortened to TECH) — rendered by the base game. Same two hooks as
the counter (extended stubs); detection mirrors `tools/training/labels.lua` and is validated
against it as the oracle.

> **2026-07-20 — MEATY label removed** (from BOTH this patch and the Lua overlay): pad
> testing showed it felt at best very strange to players and at times detrimental in live
> play. Label id 4 is retired (ids 1/2/3/5 kept stable), the M/Y glyphs drop out of the
> font, and the detection block is gone from the stub; the meaty *detection rule* itself
> (hit ≤2f after the defender left constraint) remains documented in
> `sms_engine_internals.md` as engine knowledge. `training_test.lua` T4 now asserts the
> label does NOT fire on the frame-perfect infinite.

- **Glyphs:** the in-match nameplate font is matchup-dependent (**G appears in no character's
  name**), so a compact 2bpp uppercase font (`tools/hudfont.py`, the ~16 letters the label set
  needs) is uploaded once per label-episode via DMA to **free BG3 CHR slots `0xC7-0xDF`**
  (verified zero across 5 matchups). Re-armed when both labels idle → survives per-match CHR
  reloads. Label text renders to free row-7 tilemap cells (`$10E5+` left / `$10F2+` right),
  disjoint from the counter's cells.
- **Detection** (in the producer stub, no new hooks): per-player `prevAct`, constraint-recency
  (any / hard), a 3-state move-phase, and an HP shadow. GC = attack act with prevAct in
  blockstun; REVERSAL = attack ≤2f after leaving hard constraint; PUNISH = hit while the
  defender is in its own move's recovery (move-phase active-seen, hitbox gone);
  TECH = act→0x23. Priority TECH>GC>REVERSAL>PUNISH.
- **Verification:** each label fires iff the Lua fires it, across scripted scenarios — GC (Mars
  fireball out of blocked 2HP), TECH (throw mash), REVERSAL (wakeup jab), PUNISH (hit during
  2HP recovery). `tools/test_labels.lua` + scenario cfgs; the frame-perfect infinite is the
  MEATY *negative* scenario (no label) since 2026-07-20.

### Performance (labels build) — the measured lag answer
`tools/perf_patch10.lua` over the heavy scenario (infinite rep + labels firing):

| Metric | Value |
|---|---|
| compute stub | mean 508 / max 825 cyc/frame (main loop, scanline 101) |
| flush stub | mean 140 / max 245 cyc/frame (vblank) |
| worst-case cost | **2.62 %** of the ~40,853-cycle frame |
| glyph-upload span | 3 scanlines (vblank ≈ 38 — fits with margin) |
| **lag** | clean-vs-labels gameplay RAM + timer **frame-identical**; 1500-frame soak signature-identical ⇒ **zero dropped frames** |

The 2.62 % is well within the frame's headroom (proven: no frame ever diverges from clean), so
there is **no noticeable lag** — the definitive test is frame-identity, not the percentage.

## Knob (labels)
| Knob | Flag | Default | Effect |
|---|---|---|---|
| Status labels | `mkpatch10.py --events` | `off` | `labels` = also show GC/REVERSAL/PUNISH/TECH text |

Standalone `build/sms_combolabels.bps` (ROM SHA-1 `745ea0bc…`; was `920652df…`
until 2026-08-06, then `4899790a…` after #86's `--modes` gate, `83defe1e…`
after #88's TTL-refresh fix, and this after #93's lazy glyph upload), combined
`build/sms_full10_combolabels.bps` (ROM `…_v0.7_all5_combolabels.sfc`). Same two hooks as the
counter (`0x0D56F`, `0x0D5E8`) — byte-disjoint from patches 1–9.

**TTL refresh (#88, 2026-08-06):** a repeated event of the kind already shown now
refreshes the label's 48-frame lifetime. Detection sets a per-player
"assigned this frame" flag (`$0911`/`$0912`); `setttl` keys on that flag instead
of comparing against the SHOWN label, which had silently suppressed the refresh
on repeats (the code's own comment promised the refresh). Verified by
`tools/probe_p88_ttlrefresh.lua`: with the TECH detector forced every frame,
unfixed decays 47→0 and blanks at fire+47; fixed pins the TTL at 47 and never
blanks. One-shot expiry unchanged (`test_labels.lua` drawn@84 blank@131 PASS).

**Lazy glyph upload (#93, 2026-08-06):** the font DMA fires only when label
cells are about to be flushed (a staging row dirty or a label shown), instead
of every vblank in which both labels sat idle — which was most of the match.
The producer still re-arms `GLYPH_FLAG` on idle frames, because that is what
survives per-match CHR reloads (a transition-only re-arm would leave match 2's
first label drawing with a wiped font). Measured by
`tools/probe_p93_glyphdma.lua`: 300 uploads per 300 idle frames before, 0
after, with 2 per label episode (first draw + expiry blank); render oracle
unchanged (drawn@84 blank@131).

---

# Applying (summary)

Every standalone BPS applies to the **clean ROM** (SHA-1 `bc0e29ee…`). Pick ONE per slot:

```
# individual (each onto the clean ROM)
flips --apply build/sms_uranus_infinite_1f.bps <clean ROM> <out>   # patch 1  (or _truecombo for 1b)
flips --apply build/sms_dashfix.bps            <clean ROM> <out>   # patch 2
flips --apply build/sms_palettes.bps           <clean ROM> <out>   # patch 3
flips --apply build/sms_title.bps              <clean ROM> <out>   # patch 4
flips --apply build/sms_dashdist.bps           <clean ROM> <out>   # patch 5
flips --apply build/sms_dashinvuln.bps         <clean ROM> <out>   # patch 6  (optional)
flips --apply build/sms_pluto5hp.bps           <clean ROM> <out>   # patch 7  (optional)
flips --apply build/sms_venustech.bps          <clean ROM> <out>   # patch 8  (optional)
flips --apply build/sms_neptune_ds.bps         <clean ROM> <out>   # patch 9  (optional)
flips --apply build/sms_combocounter.bps       <clean ROM> <out>   # patch 10 (optional; or sms_combolabels.bps for 10b)
flips --apply build/sms_trainingplus.bps       <clean ROM> <out>   # patch 11 (optional)
flips --apply build/sms_taunt.bps              <clean ROM> <out>   # patch 12 (optional)
flips --apply build/sms_tauntbuff.bps          <clean ROM> <out>   # patch 13 (optional)
flips --apply build/sms_gutsgrip.bps           <clean ROM> <out>   # patch 14 (optional; inert without 13)

# everything at once (the current bundle)
flips --apply build/sms_allpatches_v0.22.bps   <clean ROM> <out>   # ALL 14 patches (10b labels on)
# the REF v.1 reference combination (1b+2+3+4+5+7+8+9+12+13+14)
flips --apply build/sms_reference_v1.bps       <clean ROM> <out>   # -> sha 2873f214…

# stacking IPS onto an already-patched ROM — ONLY the fixed-address patches ship .ips
# (1/1b, 2, 6: no appended bank, checksum-free, safe to stack):
flips --apply build/sms_dashfix.ips <1f-link ROM> <out>
```

> ⚠️ **NEVER build a combination by applying standalone BPS files in sequence.** Every
> bank-appending standalone (4, 10/10b, 11, 12, 13, 14) is diffed against CLEAN and places
> its code in the same first-free bank ($E8) — chained application (which already requires
> overriding the source-checksum error) makes each patch overwrite the previous one's code
> bank while the old hooks still jump there (crash, or silently dead features — e.g.
> patch 11's L+R menu). **Custom combinations = chain the `mkpatchN.py` builders** (each
> re-detects the next free bank), then diff once against clean (HANDOFF §2).

Historical cumulative bundles (`sms_both`, `sms_full*`, the v1.x line) were pruned from
`build/` on 2026-07-19 — where a per-patch section below names one as its "showcase"/
"combined" deliverable, read it as historical record; the current bundle is
`sms_allpatches_v0.22.bps`. Standalone per-patch write-ups remain at
`patch_notes_dashfix.md`, `patch_notes_palettes.md`, and `patch_notes_title.md`; this file
is the consolidated reference.

---

# Patch 11 (OPTIONAL) — In-ROM training mode upgrade ("Training+")

**User guide: `docs/project/trainingplus.md`** (install, menu reference, drills, internals summary).

**Builder:** `tools/mkpatch11.py [src] [out] [--stage pipe|tier1]` (stacks on any patch 1-10 ROM, any order)
**Standalone BPS:** `build/sms_trainingplus.bps` (clean+11, ROM sha1 `a3aba30d…`;
was `e9ac2205…` until 2026-08-06 — #90: a position reset requested during
hitstop or a non-actionable state now stays pending and lands on the first
actionable frame instead of being silently swallowed; the request byte is
consumed at `rsgo:`, after the guards. Pinned by `test_p11_tier1.lua`'s
`reset-hitstop` phase: on the old build the request died in hitstop —
`req+3=0`, no teleport — now `ALL PASS (65)`.)
**Canonical+11 BPS:** `build/sms_full11_trainingplus.bps` (v0.7 five + 11, sha1 `09106a07…`)
**Showcase BPS:** `build/sms_allpatches_v1.1.bps` = patches 1-10 + 11, title "FrenchName v.1.1" (sha1 `be2cb752…`)

## What it is

The base game's Practice mode (title menu: down, right → Practice), upgraded **inside the
ROM** — everything below renders and runs on real hardware, no emulator or Lua needed. The
Lua training mode (`tools/training/`) remains the precision tool and served as the
frame-exact oracle for every feature here.

## Pad guide (in a Practice match)

- **L+R** (shoulders, together): open/close the training menu. While open, P1's inputs go
  to the menu (cursor ↑/↓, value ←/→) and the fighter stands still. Start/Select are eaten
  while open; when closed, **Start = native movelist, Select = exit** work as always.
- Menu rows:
  | Row | Values | Effect |
  |---|---|---|
  | POSE | STAND / CROUCH / JUMP | dummy holds the pose (STAND = a P2 pad still works) |
  | GUARD | OFF / ALL / HIT | ALL = always blocks; HIT = blocks after the first hit/throw |
  | WAKEUP | OFF / JAB / THROW / DASH | dummy's reversal on wakeup (DASH = 44 backdash) |
  | TECH | OFF / ON | dummy mashes throw-tech (HK every 2f, the measured optimal rate) |
  | DAMAGE | OFF / ON | the game's own mode 4↔5 switch: hits always connect; ON makes HP drop |
  | REGEN | OFF / ON | dummy heals to full 2s after the last hit (needs DAMAGE ON to matter) |
  | REFILL | OFF / ON | nobody dies: HP refills during the knockdown, normal wakeup, no KO |
  | RECORD | OFF / ARM | ARM then close: your pad puppets the DUMMY and is recorded (~34s max); L+R stops |
  | PLAY | OFF / ONCE / LOOP | replay the recording into the dummy on menu close |
  | SHOW | OFF / ON | live input display (U/D/L/R + LP/LK/HP/HK) + advantage readout (ADV ±N) |
  | RESET | GO (press ←/→) | both fighters snap to start positions (only when both are neutral) |
- Settings persist while the console is on (survive rematches; reset on power cycle).

## How it works (RE summary — details in docs/game/annotations.md "patch 11 RE")

Two JML trampolines, byte-disjoint from patches 1-10 (stacking order never matters):
- **$80:8373** (joy_read tail, after held words, before edge derivation) → INPUT stub:
  gate + menu FSM + dummy injection + effects. The dummy is driven by rewriting P2's raw
  pad words `$5E/$5F` — the game derives press edges itself, the 30Hz latch and the 44
  recognizer behave exactly as with a real pad (same mechanism as the Lua oracle).
- **$80:D574** (HUD uploader body, NMI scanline 237) → UPL2 stub: ALL VRAM work (font DMA,
  BG3 painting, TM management), branch-aware replay of the displaced `beq/sta $2116`.

Key native facts the patch stands on (all probe-verified this session):
- Mode 4 connects hits but skips only the HP subtraction; poking `$008D=5` enables damage
  (the DAMAGE row). The attract demo also runs at mode 5, so the gate accepts 5 only
  with the patch's own flag set. Gate = `$0070==4` (in-match) + `$01FA==0x80` (running).
- The HUD producer **never runs** in Practice → no HUD/timer natively; **BG3 is the
  pre-staged movelist layer with TM off** (0x13). The patch paints BG3 freely (wipes rows
  0-17 before showing, invisible while TM is off), forces TM=0x17 per vblank only while
  its UI is visible, and the native movelist restages itself on every Start press.
- All state lives in **$7F:F000+** (bank $7F is untouched by the game in steady-state
  play; scene loads use $7F:0000-5FFF only). Recording ring at **$7F:E000** via the
  WMDATA port $2180-83 (game never touches it). Boot's RAM clear re-inits everything.
- KO prevention: the KO latch reads neither struct HP nor $0800/1 — a refilled dummy
  still hits act 0x1F. Fix: refill during the KD **and force the engine's own standup
  act 0x20 at the 0x1E frame** (probe-proven clean recovery).
- Font: 25 glyphs (patch 10's 16 letters + BDFJKOW + '>' + '-') DMA'd to the free BG3 CHR
  window 0xC7-0xDF, drawn in **white** (color 1 — patch 10 uses color 3, but the two
  patches' fonts never coexist: p10 renders only in VS, p11 only in Practice).

## Limitations (documented, by design)

- **ADV is an approximation**: dual frames-since-neutral counters, settle on the later
  player's first neutral frame; can read ±1 vs the Lua framedata conventions and doesn't
  handle projectile pressure. The Lua trainer is the precision tool.
- Recordings store raw pad words — they do **not** mirror when sides swap (use RESET to
  restore positions before replaying). Movelist/exit stops an active recording.
- The menu takes ~0.5s to appear (font DMA + 18-row wipe + 12 rows, one item per vblank,
  invisible until complete).

## Measured performance

`tools/perf_patch11.lua` (+`_cfg`): INPUT stub mean ~500-600 / max 705 cyc; UPL2 mean
~150-270 / max 691 cyc; vblank span ≤ 4 scanlines (of ~37). Worst combined stub cost
**3.4% of a 40850-cyc frame** (ceiling 5%). 5000-frame all-features-on soak: state sane,
no corruption. **VS/story: byte-inert** — NI-1 frame-identity (structs hashed per frame
over the scripted infinite rep) is byte-identical v0.7 vs v0.7+11.

## Verification (all green, `traces/p11_*.txt`)

- `tools/test_p11_tier1.lua` — 50+ checks across 14 phases on the patched ROM (guard,
  afterhit, poses, tech-mash w/ mash counter, wakeup jab/dash, regen timing, refill
  no-KO + recovery, reset, record→puppet→loop-playback E2E, SHOW displays incl. VRAM
  asserts, full menu UX incl. input eating + movelist protection). ALL PASS on the
  standalone and on the v1.1 showcase ROM.
- NI-1 VS frame-identity; NI-3: `demo_link` (patch-1 single MEATY frame 115 intact) and
  `test_patch10.lua` (counter oracle green) on the v1.1 showcase; both stacking orders
  with patch 10 build+boot clean.
- Screenshots: `traces/p11_menu.png` (menu), `traces/p11_demo_show.png` /
  `p11_demo_adv.png` (input display + ADV 6 vs the oracle's +6 scenario).

---

# Patch 12 (OPTIONAL) — Taunts on the L button

**Builder:** `tools/mkpatch12.py [src] [out]` (stacks on any patch 1-11 ROM, any order)
**Standalone BPS:** `build/sms_taunt.bps` (clean+12, ROM sha1 `614f318e…`)
**Showcase BPS:** `build/sms_allpatches_v1.2.bps` = patches 1-12, title "FrenchName v.1.2" (sha1 `048bd49f…`)

## What it is

Press **L** (with R not held) while grounded and actionable, in any match type (VS, vs-COM,
tournament, story, Practice), and your character performs her **native failed-special
animation** — the same per-character misfire pratfall the game plays in story mode / A.C.S.
customization matches when the "ochame" stat makes a special whiff. Fizzle → embarrassed →
neutral, ~1.8 s, **fully vulnerable the whole time** (a jab interrupts it — that's the
taunt risk). Both players can taunt. No advantage is granted (a possible later addition).

Special case, kept deliberately: **Jupiter's misfire has a real attack box** (her fizzled
thunder zaps point-blank) — that is the authentic native animation, so her taunt can hit.

## The RE that made it 1:1 native (docs/game/annotations.md "patch 12 RE")

The misfire mechanic was fully located: every special's 8-byte record in bank $C1 carries
its **misfire act at +6**; the dispatcher `$C1:0B49` rolls `threshold[$C1:0AF5 + ($90 &
15)] < ochame(+0x75)` and, on failure, simply sets the fighter's act to record+6. The
taunt writes exactly those per-character acts (LP-variants, all 9 harvested live and
audited): Moon 6A, Mercury 65, Mars 66, Jupiter 63, Venus 5F, Uranus 65, Neptune 66,
Pluto 62, ChibiMoon 63. The game's RNG byte ($7E:0090) was located as a bonus.

## Mechanics

One 314-byte stub, hook at **$80:8377** (joy_read's edge-derivation; displaced `eor $64 /
and $5C` raw-spliced back). The L press-edge is computed **statelessly** from the game's
own held/prev pad words — the patch has **zero WRAM footprint**. Gate: `$0070==4` (in a
match) and `$01FA==0x80` (running), taunter act ≤ 0x04, no hitstop, R not held. The act
write is the engine-proven force set (+01/+04=act, +02=1, +06/07=0).

Coexistence with patch 11 (Training+): byte-disjoint hooks — p11's input stub JMLs
straight into p12's hook, either install order. The **L+R menu chord never taunts** (R
held blocks it) and the menu's input-eat blocks taunts while it is open. A recorded L
press replays as a dummy taunt (feature). Quirk: pressing L a beat before R when opening
the menu can fire a taunt first — cosmetic.

## Verification (all green, `traces/p12_*.txt`)

- Solo suite 13/13 (`tools/test_p12_taunt.lua`, MODE="solo"): both players taunt + recover,
  chain into 0x2A, edge-only (held L = one taunt), L+R blocked, airborne/hitstun blocked,
  vulnerability (P2 jab interrupts the taunt), Chibi 0x63 + Pluto 0x62 in VS mode.
- Coexist suite 5/5 (MODE="coexist") in **both** stacking orders with patch 11.
- NI-1 VS frame-identity (v0.7 vs v0.7+12, no-L plan, byte-identical); boot→match E2E;
  both suites + the p11 suite ALL PASS on the v1.2 showcase; BPS round-trips verified.
- Probes: `tools/probe_p12_{acts,ochame,rec,com}.lua` (act audit + screenshots, the live
  ochame whiff demo, the record harvest, the CPU-pad L/R check: mode 2 vs-COM = 0 hits).

---

# Patch 13 (OPTIONAL) — "Guts": stacking defense buff on taunt completion

**Builder:** `tools/mkpatch13.py [src] [out] [--l1 20 --l2 40 --l3 60]` (stacks on any patch 1-12 ROM, any order)
**QA verification note (v0.14):** the specials-nerf was re-verified end-to-end on the
maintainer's image with real taunts (fireball 6 baseline -> 2 at L3, identical timing).
If levels seem inert while using the Lua trainer alongside: the trainer's savestate-based
resets (position reset, KO auto-reset, slot reloads) restore ALL RAM including $7F —
**buff levels silently revert with the state; trust the corner digit**. Also remember
only attack-class >= 0x08 moves are nerfed (dash attacks / command normals are not
specials). Training+ additionally gained a **P1 HP FULL/LOW menu row** (LOW = 0x17,
under the 0x18 desperation threshold) for desperation testing.

**Known limitation (found 2026-07-18, maintainer QA vindicated) — closed by patch 14:**
command-grab specials — Uranus SPD 6321478HK (toss 32) and Jupiter SPD 6321478HP
(airborne carry, 5×6 drain) — apply their damage through the throw-toss/tick sites with
holder class byte 0, indistinguishable from normal throws, so the ≥0x12 gate does NOT
scale them. The maintainer's original "SPD numbers were the same" report was accurate.
Per the maintainer's direction this is covered by the separate **patch 14 "Guts Grip"**
(below) rather than another patch-13 revision.

**v3.4 (training-only indicator — maintainer's standing request):** the corner
level-indicator now draws ONLY in training mode (game mode $8D in {4,5} = practice
with damage off/on, in addition to the in-match flag); in VS/story it never renders.
The buff itself is unchanged everywhere. Attract mode technically passes the gate but
levels are always 0 there (blank). Suite: indicator phases (training state) unchanged
+ new p13-indicator-vs-hidden negative lock in the regression suite.

**v3.3 (wide scaling tables):** the 64×16 damage-matrix discovery (sms_damage_system.md
§3) revealed the matrix caps at 0x48=72 — above the Guts tables' 64-entry range, so a
counter-hit desperation (72) was being scaled as if it were 63 (clamped, mildly under-
scaled — never out-of-bounds). v3.3 widens the tables to 3×128 and the clamp to 0x7F:
every value the engine can produce now scales exactly (72 at L3 = 29, verified by the
regression suite's cross-patch test).

**v3.2 (Uranus toss coverage + full compendium):** probing all 9 desperations (see
sms_acs_system.md §6b) found one more bypass: Uranus's desperation is a rush→grab hybrid
whose 32-damage finisher goes through the throw-toss apply site $C1:082F — the site v3
had deliberately un-hooked. The toss site displaces the same 6 bytes with the same
Y/DP-$05 conventions as the drain-tick site, so v3.2 re-hooks it with the SAME
holder-class >= 0x12 stub: Uranus desperation 67 -> 34 at L3 (rush hits and toss 32->13
all table-exact); normal throws still toss at +0x44 = 0 and pass untouched (Neptune
normal throw 20 -> 20 at L3, verified). Everything else already covered: Jupiter/
Mercury/Venus single strikes at class 0x12-0x14, Moon/Mars/Chibi projectile-type through
the unconditional projectile hooks, Pluto via the v3.1 tick hook. Neptune's desperation
(corrected input 6236236HP) is a single HP-gated 37-damage strike at class 0x12 — covered
by the class gate like Venus/Mercury; the ungated 19-damage chain the first sweep hit was
her regular super under the wrong input.

**v3.1 (desperation coverage):** the maintainer's motion list enabled real desperation
testing, which exposed the gap they had reported: cinematic-grab desperations (Pluto
traced fully) deal ~94%% of their damage as HOLD-DRAIN TICKS through the hold-throw tick
site $C1:0D54 — bypassing the strike hooks. v3.1 adds a JSL thunk there with a
holder-class >= 0x12 gate: desperation drains scale (Pluto: 48 -> 19 at L3, every tick
exact incl. the 11-damage finisher -> 4), normal Moon/Mars/Chibi hold-throws verified
byte-identical. Bonus RE: +0x74 buff_secret = desperation strike-damage boost (3->5->6
at stat 0/3/7); drain ticks are not stat-scaled.

**v3 (QA pivot):** Guts no longer boosts general defense — **completing a taunt now
NERFS the opponent's SPECIAL and DESPERATION damage against you** (20/40/60% per level,
knobs; direct hits + projectiles + chip; normals and throws deliberately untouched).
Class check = the attacker's +0x44 attack-class byte (lights 0x00-0x03, heavies
0x04-0x07, specials >=0x08, supers >=0x12; projectile slots carry their own — the 4
projectile apply-sites always scale, the 4 melee sites gate on the other fighter's
class). QA probes also established: the ACS stat **+0x73 (buff_special) genuinely
scales special damage (8 -> 16 at stat 7) but only upward from the VS floor of 0** —
the maintainer's leverage-ACS idea validated in mechanism, impossible in direction,
hence the hook route. And the v2 "throws sometimes unscaled" mystery: Moon, Mars and
ChibiMoon use per-tick HOLD throws applying damage at a third site **$C1:0D61** the v2
build never hooked (standard throws $C1:083C = Mercury/Jupiter/Venus/Uranus/Neptune) —
moot in v3 since throws are out of scope.
**v2 (QA feedback):** defaults raised to **20/40/60** (the engine's damage variance — jabs
roll 1-6 — made 10/25 imperceptible on light hits), and a **buff-level indicator** was
added: each player's current level (1-3) as a small HUD digit at their top corner (BG3
row 7, cols 1/30; hook `$80:D596`, the uploader's every-frame exit, redrawn per vblank so
wipes/restages never leave it stale; blank at level 0; visible in VS always, in Practice
whenever Training+ shows BG3).
**Standalone BPS:** `build/sms_tauntbuff.bps` (clean+13, ROM sha1 `bafb87d4…`)
**Showcase BPS:** `build/sms_allpatches_v0.11.bps` = patches 1-13, title "FrenchName v.0.11" (sha1 `be476410…`)

## What it is

Q-in-3S-style guts: **complete a full taunt pratfall uninterrupted** (patch 12's L-taunt —
or a genuine ochame whiff in A.C.S. play, same animation) and gain one **defense level,
stacking to 3** (getting hit out of the taunt grants nothing). Damage you take is reduced
by **20% / 40% / 60%** per level (build knobs `--l1/--l2/--l3` for tuning), covering
normal hits, projectiles, **chip damage**, throws, and teched throws, with a floor of 1.
Levels last **until the round ends**; no on-screen indicator (the ~1.8 s pratfall is the
tell). Works standalone (real whiffs only) or with patches 11/12.

## How it works (RE detail in docs/game/annotations.md "patch 13 RE")

- **Grant FSM** (hook `$80:837B`, third in the joy_read chain after patches 11/12, any
  install order): per player, idle → in-misfire-act (full per-character act sets from the
  patch-12 record harvest) → embarrassed (0x2A) → first actionable frame = grant. Any
  other transition = no grant. Round reset = the probe-found VS signature: a player's HP
  rising **from exactly 0 to max** while both acts are 0 (immune to Training+'s
  REGEN/REFILL heals, which never heal from 0 with a neutral act).
- **Damage scaling**: the engine applies all strike/chip damage through **8 identical
  6-byte sequences** in bank $C0 (`lda $0049,Y / sec / sbc $00`, defender in Y, damage
  staged in DP $00) — each is replaced by a `JSL` into **one shared stub** that looks up
  `table[level][damage]` (3×64-byte build-time tables) and performs the same subtract;
  `RTL` lands on the original `sta`. Throws get the same treatment at their two apply
  sites (`$C1:082F` full / `$C1:084D` teched — the tech path scales the halved value).
  Level 0 is a bit-exact passthrough. Cost: ~60 cycles per hit *landed*, zero otherwise.
- The engine's native **per-hit damage variance** (the 16×16 matrix at `$C0:D081`, RE'd
  this session) applies before our scaling — the buff reduces the final rolled value.

## Interactions & limitations

- Jupiter's taunt can still hit (patch 12 behavior); if it connects, the taunt was
  interrupted-by-engine? No — hitting someone doesn't leave the misfire act, so the grant
  still lands when the animation finishes. Getting hit *during* it forfeits, as designed.
- A **time-over** round end does not match the reset signature (nobody's HP was 0) — buff
  levels would carry into the next round in that rare case. Documented, deliberate cut.
- In Practice, Training+'s RESET row does not clear levels (positions-only reset); toggle
  DAMAGE or re-enter the mode to zero them.

## Verification (all green, `traces/p13_*.txt`)

- Solo suite (`tools/test_p13_guts.lua`, misfire acts force-played): grant-on-completion,
  no-grant-on-interrupt, stack 1→2→3 + cap, **exact per-level damage** on deterministic
  rolls (strike 5→4/4/3; throw 24→13; tech 12→7; chip 2→1 floor), P1-as-defender, round
  reset (held mid-round, cleared at round 2).
- Stack suite on 11+12+13 in **both** install orders: real L-taunt E2E grant, interrupted
  taunt denied. p11 + p12 suites ALL PASS on the triple stack and on the v0.11 ROM.
- NI-1 frame-identity **with live hits** (level-0 passthrough bit-exact vs v0.7); boot
  E2E; BPS round-trips verified.


---

# Patch 14 — "Guts Grip": Guts levels also nerf command grabs (OPTIONAL, companion to 13)

**Deliverables:** `tools/mkpatch14.py`, `build/sms_gutsgrip.bps` (standalone SHA-1
`5fadcaca…`). In v0.18+ all-patches builds.

## What
While a player holds Guts levels (patch 13's taunt-completion stacks), incoming
**command-grab** damage is reduced by the same percentages (`--l1/--l2/--l3`, default
20/40/60). Verified: Uranus SPD 32 → 13 at L3, Jupiter SPD 5×6=30 → 5×2=10 at L3;
normal throws stay exempt (Neptune toss 20 → 20 at L3); no double-scaling with patch 13
(Uranus desperation stays 34, Pluto stays 19 at L3). Without patch 13 in the ROM the
patch is inert (the state magic never appears) — verified byte-identical behavior.

## Why a separate patch
The maintainer asked for grab coverage as its own patch aligned on the Guts reduction
(not a patch-13 revision). It reads patch 13's state ($7F:F800 magic, $7F:F801/F802
levels) READ-ONLY and keeps its own knobs/tables, so the two stack in any order.

## Mechanism (byte-disjoint from patch 13 at the same sites)
The toss ($C1:082F) and tick ($C1:0D54) apply sites share the 7-byte tail
`cmp #$90 / bcs death / sta $0049,Y` right AFTER the 6 subtract bytes patch 13 hooks.
Patch 14 hooks the tail: `jsl stub / bcs death(disp−2) / nop`. The stub recovers
dmg = hp_before − A (hp not yet stored), gates on magic + victim level + holder
class < 0x12 (so patch-13-scaled desperations pass through) + the command-grab act
table, rescales via its own 3×128 tables, and exits through `cmp #$90` with a
conditional `sta` (which preserves carry) so the relocated `bcs` keeps exact death
semantics. Scratch $7F:F810-F815 (disjoint from patch 13's F800-F80A).

## Command-grab table & knobs
`GRAB_ACTS = ((6, 0x71), (4, 0x70), (4, 0x6F))` — Uranus toss act (both SPD strengths
and her desperation slam converge there; the class gate disambiguates) and Jupiter's
carry-tick acts for Giant Swing HP (0x70, 5 ticks) and LP (0x6F, 4 ticks — the LP gap
was found while measuring her kit and fixed in v0.19: 24→8 at L3). Other characters'
command grabs can be added once their inputs are identified (send motions!).
`--all-grabs` switches to nerfing EVERY grab-path damage (normal throws + hold-throw
ticks included) for those who want throws covered too.

### ⚠ `--all-grabs` does NOT cover a TECHED throw (measured 2026-08-08)

**The knob scales a throw that lands and not one that is teched, and at high Guts
levels that inverts the incentive: teching costs the victim MORE than eating it.**

Measured on `clean + 13 + 14 --all-grabs`, Guts L3 (60%), with patch 13's own
throw phases (`tools/test_p13_guts.lua`, states as in that suite):

| | patch 13 alone | + patch 14 `--all-grabs` |
|---|---|---|
| throw that lands | 24 | **10** (scaled ✓) |
| throw that is **teched** | 12 | **12** (unscaled ✗) |

**Why.** `$C1:0823` splits on the victim's mash count (`lda $56,X / cmp #$02 /
bpl`), and the two outcomes are *separate branches* that both read the damage from
DP `$05`:

```
$C1:082F  lda $0049,Y / sec / sbc $05 …    ← lands.  patch 13 hooks +0, patch 14 the tail +6
$C1:084D  lda $05 / lsr / eor #$FF / inc a
$C1:0854  adc $0049,Y …                    ← teched. hooked by NEITHER patch
```

The tech branch never passes through the hooked site, so it halves the *unscaled*
damage. This is **correct and deliberate for patch 13 alone** — normal throws are
out of its scope, and `test_p13_guts.lua`'s `tech-immune` phase pins exactly that
("throws untouched"). It is an incompleteness only in patch 14's `--all-grabs`,
whose whole claim is that every grab path is covered.

**Blast radius: no shipped build.** All four recipes (`build_rev.sh`,
`build_ref_v1/v2.sh`, `build_v022.sh`) call `mkpatch14.py` with no flags, so
Rev. S-02, Rev. SS-02, REF v.1/v.2 and v0.22 are unaffected. The **default**
scope (command grabs) also appears unexposed: Uranus's SPD scripts toss
immediately with no mash-sampling steps, so the tech branch should be
unreachable for them — *that part is inferred from the scripts, not measured, and
should be measured before anyone relies on it.*

**Fixing it** means hooking the tech branch too (its tail `$C1:0857
cmp #$90 / bcs / sta` has the same shape as the two sites already hooked), and
deciding a question that is the maintainer's, not the code's: should a teched
command grab be scaled by Guts at all? Left open deliberately.

⚠ The general lesson is trap 5 again, in a new costume: **patch 13's site census
was complete, and patch 14 inherited its site list rather than re-deriving one
for its own, wider claim.** A patch that widens another patch's scope must
re-census the paths for the new scope.

## Verification
Regression suite (`tools/test_regression.lua`): v0.18 = 42 tests ALL PASS incl.
p14-spd-uranus-scaled (13), p14-spd-jupiter-scaled (5×2), throw exemption at L3,
desperation no-double-scaling, base SPD invariants at level 0; clean = 25, v0.17 = 39.


# Patch 15 — remove the AUTO option (button-config screen)

**Why.** The VS config screen's モード row toggles マニュアル / オート; Auto binds
the special moves to **L and R**. That collides head-on with patch 12 (taunt =
L press) and is disallowed in tournament play. The maintainer asked for the
same removal the **Big Zam Tournament Edition** ships.

**Ground truth.** TE is built on Big Zam; diffing the two isolates 11 changed
regions, of which exactly three sit inside the config screen's mode-row
handler. The handler is dispatch entry 0 of the table at `$C3:A839` (eight
entries = the screen's eight rows: モード, 弱/強パンチ, 弱/強キック, 弱/強必殺
モード, ステージ). The same bytes are present in the clean ROM, so the edit
applies anywhere in our lineage.

**The edit** (6 bytes, file offsets):

| Offset | Vanilla | Patched | Effect |
|---|---|---|---|
| `0x03A863` | `9D 06 00` `sta $0006,X` | `EA EA EA` | never commits the new mode |
| `0x03A87A` | `9D 04 00` `sta $0004,X` | `EA EA EA` | never writes it back to the working copy |
| `0x03A880` | `F0` `beq $A8B9` | `80` `bra $A8B9` | skips the "value changed" tail entirely |

**Verified (headless A/B, `tools/saturn/probe_sms_noauto.lua`).** Vanilla:
mashing RIGHT on the mode row flips P1 to **オート** and the two 必殺モード rows
gain `L` / `R` assignments. Patched: the row stays **マニュアル** and those rows
stay `-` `-`, matching the untouched P2 column; the screen still advances into
a normal match. Other rows are untouched code.

**Regression test (added 2026-08-05).** `p15-mode-row-inert`, dual-mode, from
the fixture `traces/config_vs_clean.mss`: press RIGHT **once** on the モード row
and read P1's committed mode at `$1806` — vanilla commits `2` (オート), patched
stays `0` (マニュアル). Two things had to be right for it to mean anything, and
each cost a wrong reading first: **every column has its own row cursor**
(`$1800` P1, `$1880` P2 — the mode-row handler firing proves nothing about P1,
since it also fires for whichever column is on row 0), and the row has **two**
values, so mashing RIGHT lands on either by parity and an even count is
indistinguishable from an inert row. Negative-controlled: forcing detection to
"p15 present" on a clean ROM makes it fail with `got $1806=2`.

**Scope.** No bank use, no WRAM, byte-disjoint from patches 1-14 — stacks
anywhere (`tools/mkpatch15.py`, `--stacked` supported). **In both reference
builds** (REF v.2 onward, and Rev. S/SS).

---

# Patch 16 — menu translation (IN PROGRESS)

**Status (2026-08-08): the font install and five screens are done and
in-emulator verified; two runtime-drawn text surfaces remain.** This is the
project's only active work item. This section is the summary; the mechanism
record — every screen's loader, every trap paid for — is `docs/project/menu_text.md`,
which is the file to read before touching the builder.

**Why it is a standalone patch, not a Saturn feature** (maintainer, 2026-08-03):
it builds from clean like every other `mkpatchN.py` and must work with or
without her.

## The font install (always on)

The game's menu font has no usable half-width Latin — the
`PRESS "SELECT" TO ACS` banner looks like one but is proportional artwork stored
as tiles (22 slots, 22 *distinct* glyphs for a string that repeats S four times).
So a half-width A-Z was **built from the game's own capitals**
(`tools/mkhalfwidth.py`: 17 condensed by ANDing column pairs, 4 repaired, 5
authored — F J Q S Z), plus the punctuation the strings need. No foreign font,
no licence surface.

Delivery, and the two facts that cost the most:

* **The asset-record layout is `[vram16][len16][src24][dest24]`** (10 bytes,
  table at `$C3:BE08`) — a block's upload **length sits 2 bytes BEFORE its src
  pointer**. Every earlier attempt to grow the transfer wrote into the *next*
  record and silently lengthened an unrelated upload. The font sheet is
  `$C4:2590` (record #27); its length field `$C3:BF18` goes `$3480 → $4000`,
  which is the ceiling — the source is `$7E:C000`, so more runs off bank `$7E`.
* **The sheet is relocated, not patched in place** (418 → 512 tiles, re-encoded
  into the appended bank), because this project's encoder is weaker than the
  original's: even an untouched block re-encodes larger.

Glyphs land at **VRAM tiles `$5C0-$5FF`** — a region proved free on every menu
screen and first used at match load (`tools/probe_vram_free.lua`), which is a
pass for menu text and would not be for anything persisting into gameplay.

## The screens, and their gates

Every screen's strings are **off by default**; each gate turns on one screen.

| Gate | What it translates |
|---|---|
| *(none — always on)* | the font install, plus the Options-loader hook that re-uploads it |
| `SMS_P16_OPTIONS` | the six Options labels **and** all 12 option-value records |
| `SMS_P16_DF` | tournament select names (9) + the REPORT CARD labels (8) + PLAYER SELECT |
| `SMS_P16_STAGES` | the 10 stage names (×2 highlight states), the whole VS config screen, and the char-select glyph delivery |
| `SMS_P16_ACS` | the A.C.S. wheel labels (**requires `SMS_P16_STAGES`** — shared glyph block) |
| `SMS_P16_SATURN` | stage 2 → `SILENT THRONE OF MESSIAH`; **default off**, for a future Saturn chain that stacks this patch |

Four mechanisms are worth knowing, because they are what the screens differ by:

1. **Options** is a `$C3` cluster screen. Its transition **clears all 64 KB of
   VRAM** (fixed-source DMA at `$80:8191`) and its loader (`$C3:A4DD`) never
   re-uploads the font — so the glyphs, which do arrive at *main-menu* entry,
   were simply gone. Fix: the loader's first record load is JSL-hooked to a
   60-byte stub that replays the two JSL-able primitives (`$80:927D`
   decompress, `$80:92AD` DMA) for the font FIRST, preserving order so the
   screen's own text sheet keeps winning their overlap.
2. **Option values** are not tilemap data: `$80:8C43` draws self-describing
   records `[vmadd16][len16][rows16][cells…]` from bank `$C4`, one per value
   **per highlight state**, selected by four pointer tables at
   `$C3:A44F/A457/A45B/A463`. They are uncompressed, so translating them is a
   12-record in-place cell edit.
3. **Win (REPORT CARD) and Tournament share a separate engine** in bank `$DF`
   (`$DF:83CE`) that bypasses the `$C3` clusters entirely: nine screens, each a
   straight-line script, with **two codecs** — the familiar `sms_lz` for
   flag≠0 blobs and a second, still-unreversed one (`$80:8E9A`) for the rest.
   Nothing shipped needs codec 2: the report card is edited by a stub *between*
   its decompress and its upload (`$DF:9679`), the same seam the match numbers
   go in, and the tournament rows are uncompressed blocks.
4. **The A.C.S. wheel** labels are raster-edited into the relocated art sheet.
   ⚠ **No glyph hook on that screen** — its runtime prompt bar references the
   blank `$5C0` tiles through another BG's CHR base, so uploading glyphs there
   corrupts the prompt.

## Builds (measured 2026-08-08)

| build | ROM SHA-1 |
|---|---|
| clean → patch 16, font install only | `c9ad4910…` |
| clean → patch 16, all four screen gates on | `257598c8…` |

(Lineage, for anyone reading older notes: `d8f4ff1d…` was the font-install-only
build before the Options hook existed, `206fee3d…`/`3cba4171…` the base and
full-Options pair recorded on 2026-08-06.) **No standalone BPS is tracked yet** —
the patch is still moving, and a tracked BPS is a promise about bytes.

## Verification

Each screen was verified **in-emulator**, not from the build: the glyph census
in VRAM `$5C0-$5FF` goes 0/64 → **56/64** across the hooking transfer and stays
there settled; Options renders its six English labels and both highlight states
of its values; the report card renders KO TIME / HIT COUNT / DAMAGE / BEST / WIN
COUNT with its numbers and colours intact; the stage row renders
`CRYSTAL TOKYO, EVENING` and cycles to `FOUNTAIN PARK, DAY`. Regression stayed
**45/45** at every step. The Options screen is **field-confirmed** (2026-08-06):
legibility "excellent", repeated entry/exit and value cycling clean. The letters
sit on a slightly wobbly baseline — per-letter variance from the condensation —
and the maintainer likes it ("a fun, childish look"), so it stays.

⚠ **Verify with `tools/probe_menu_vram.lua`, which dumps ON the font transfer,**
not at the end of a run: a final-screen dump reads identical on clean and
patched ROMs because a later upload overwrites the region. `POKE=1` is the
positive control (0/256 bytes arrive clean, 256/256 patched).

## What remains

* **Bracket VS names.** Map cells in the small font, baked as Moon-vs-Moon
  inside the codec-2 blob `$C7:3BBD` and rewritten per entrant by a runtime
  builder that has not been found; a VRAM write-watch at screen entry catches
  nothing because codec 2 flushes by DMA. Next: arm the watch and force a
  bracket-advance redraw, or find the builder statically. Translating them also
  needs glyph delivery on that screen — the plan is to extend the small-font
  blob (`$C2:27E0`) and bump only `$DF:A43E`'s length field.
* **The A.C.S. name card and prompt.** Not map data at all: a **dynamic glyph
  blitter** (`$80:9583`, queue-driven, `$20` bytes at a time into BG3 CHR) fed
  from a staging area at `$7F:DC00+` that per-byte write watches never see.
  This is the game's variable-text engine — the same machinery the story
  dialogue uses — which is why the prompt can substitute a character's name.
  Finding what fills `$7F:DC00+` yields the font source; only then is an English
  prompt authorable, and it would want proportional glyphs. Until then the
  Japanese prompt stays, which the maintainer has accepted.

Story-mode text is **out of scope** (maintainer).

⚠ **Three laws this screen family taught, the hard way:** a screen transition
may clear ALL of VRAM and reload only its own list; **blank ≠ unreferenced** (a
screen can reference blank tiles through another BG's CHR base — three separate
instances now, incl. the story pre-fight portrait screen `$DF:9405`, whose stray
letters were a field report); and a runtime record will overdraw baked text, so
a tilemap-only edit of a *value* is not enough.

---

# Patch 17 — every stage selectable (hidden stage unlocked)

**Why.** The tenth stage — **なかよし編集部**, the Nakayoshi editorial
department — is finished retail content that the game hides behind a button
code. The maintainer wants it selectable like any other stage, **and** in the
random pool.

## 1. The menu bound — 1 byte, always applied

The stage row of the VS config screen is dispatch entry 7 of the table at
`$C3:A839`; its handler is `$C3:AA1A`:

```
$C3:AA1C  ldx $1B00 / lda $0038,x     ; the live index — pointer-addressed,
                                      ; which is why a flat WRAM sweep for it failed
$C3:AA28  lda $1F59 / and #$00FF / beq +5
          lda #$0010        ; flag SET   -> nine stages
          bra +3
          lda #$0012        ; flag CLEAR -> ten stages
$C3:AA38  sta $1C1C
$C3:AA3B  jsr $B131         ; the shared list navigator
```

`$1C1C` is the navigator's **inclusive max index in WORD units** — `$C3:8002`
wraps up to 0 when the value equals it, `$C3:801A` wraps down to it — so 16 =
stages 0-8 and 18 = stages 0-9. It is a *generic* menu-list bound (five writers
in `$C3`, two readers), so each menu sets its own and this edit touches only the
stage list.

The flag has exactly one writer:

| Offset | Vanilla | Patched | Effect |
|---|---|---|---|
| `0x03BADE` | `8D` `sta $1F59` | `9C` `stz $1F59` | flag always clear = ten stages |

Same byte as `vendor/sms-training-mode/sms_patcher.py PATCH_NAKAYOSHI`. Same
length, no relocation, no bank use.

**Where the flag comes from — the retail unlock.** `$C3:BADA` latches
`$1C5A >> 1`, and `$1C5A` is a small screen-state variable that a button check
leaves at **0 only while a combo is held**: `$C3:B8B4` tests `$5C & $0070` =
**X+L+R** (`$C0:AE00` tests L+R for a different cheat). Hold X+L+R over the
title sequence on an unmodified ROM and the tenth stage is already there. That
is the patch's independent control (below) — the edit does not invent a stage,
it removes the condition.

## 2. The random pool — 2 bytes, applied when patch 3 is present

Patch 3 carries a rider that defaults the stage to a random one when P2
confirms, and that picker **bounds itself** — it never reads `$1C1C`, which is
why the menu byte alone cannot put the stage in the pool:

```
$E8:00CD  lda $B1 / and #$00FF
          cmp #$0009 / bcc + / sec / sbc #$0009 / bra -    ; A %= 9
          asl / sta $8E                                    ; scene id
```

Both `#$0009` operands become `#$000A`. The rider lives inside patch 3's
injected bank-`$E8` blob, so `mkpatch17.py` locates it **by signature in the
image being built**, not at a fixed offset, and reports it as skipped when
absent. On a clean ROM it *is* absent: retail has no random stage picker at all
(`$8E` is written from the menu selection, from a story table at
`$C0:E9D9`/`$C0:E9F9`, or from `$C2:C009`).

## Verification (headless Mesen, `tools/probe_p17_stagelist.lua` + `probe_p17_randompool.lua`)

The first attempt at this measurement was void — it swept WRAM for "a byte that
cycles" and never proved it had reached the stage row. Both probes now assert
their precondition with an exec hook before reporting anything.

| Run | ROM | Result |
|---|---|---|
| menu, control | clean | **9** stages reachable, `$1F59`=1 |
| menu, **retail unlock** (`COMBO=1`, X+L+R held to the latch at ~f622) | **clean** | **10** stages, `$1F59`=0 |
| menu | clean + p17 | **10** stages, `$1F59`=0 |
| menu | REF v.2 | 9 stages |
| menu | REF v.2 + p17 | **10** stages |
| match on index 18 | clean + p17 / REF v.2 + p17 | loads: `$8E`=18, HP 96/96, the editorial-department stage on screen |
| menu name at index 18 | REF v.2 + p17 | draws **なかよし編集部** |
| pool, control `RNG=8` | REF v.2 ± pool edit | `$8E`=16 on **both** — proves the poke reaches the picker |
| pool, `RNG=9` | REF v.2, pool edit off | `$8E`=0 (stage 0) — 9 is unreachable |
| pool, `RNG=9` | REF v.2 + p17 | **`$8E`=18** (stage 9), adopted by the config screen |

Rather than sample the random default over many runs to argue "9 never comes
up", the probe forces the RNG byte the picker is about to read (exec hook on the
`lda $B1`), which makes each build one deterministic run.

Regression: **42/42** on clean + p17 (identical to clean), **57/57** on
REF v.2 + p17 (identical to REF v.2).

⚠ **Two traps this patch paid for.**
1. **The stage name is queued to VRAM, not drawn on the spot.** A screenshot
   taken on the frame the index lands shows the *previous* stage's name — the
   first capture at index 18 showed index 8's 噴水公園◇夜 and reads exactly like
   "the tenth entry is mislabelled". Let the transfer settle (~40 frames) before
   believing a menu capture.
2. **`$1C1C` is an inclusive max, not a count.** Reading it as a length inverts
   the whole mechanism (and makes the retail cheat look like it *removes* a
   stage). The two navigator readers settle it.

## BGM — the hidden stage has its OWN track (`--bgm N`, default vanilla)

Ten pointers at **`$E0:017A`** address the scene records (`$018E`…`$020D`), and
each record's **last byte is its music track**:

| idx | stage | record | BGM | byte |
|---|---|---|---|---|
| 0 | CR. TOKYO ◆夕 | `$E0:018E` | `$12` | `0x20019C` |
| 1 | S. MILLENIUM | `$E0:019D` | `$0A` | `0x2001AB` |
| 2 | TIME DOOR | `$E0:01AC` | `$0F` | `0x2001BA` |
| 3 | KAIOSHU PARK | `$E0:01BB` | `$11` | `0x2001C9` |
| 4 | FOUNTAIN ◆昼 | `$E0:01CA` | `$0B` | `0x2001D6` |
| 5 | SHOP. STREET | `$E0:01D7` | `$0D` | `0x2001E3` |
| 6 | SHRINE | `$E0:01E4` | `$0C` | `0x2001F0` |
| 7 | CR. TOKYO ◆夜 | `$E0:01F1` | `$0E` | `0x2001FF` |
| 8 | FOUNTAIN ◆夜 | `$E0:0200` | `$10` | `0x20020C` |
| 9 | **EDITOR. DEPT** | `$E0:020D` | **`$06`** | `0x200219` |

The nine normal stages hold a contiguous run `$0A`-`$12`; the hidden stage's
`$06` sits outside it, so **it has a tune of its own** rather than borrowing one.
It plays: 36 DSP key-ons over 480 frames across **all eight** voices, where
stage 8 uses 51 across six (`$D2`).

**That the byte is the track id was measured, not inferred from the vendor
patcher.** Building with `--bgm 0x10` (stage 8's track) and digesting the
key-on sequence:

| run | key-ons | voices | digest |
|---|---|---|---|
| stage 9, vanilla BGM | 36 | `$FF` | `9A742001` |
| stage 9, vanilla BGM (repeat) | 36 | `$FF` | `9A742001` |
| stage 8 | 51 | `$D2` | `158EEB67` |
| **stage 9 with `--bgm 0x10`** | 50 | `$D2` | `732D5677` |
| stage 8 on the `--bgm` build (control) | 51 | `$D2` | `158EEB67` |

Stage 9 takes on stage 8's voice profile, and stage 8 digests **byte-identical**
across the two builds — so the edit moves that stage's music and nothing else.
(The two `$D2` digests differ by one key-on: a phase offset, not a different
tune.) So `--bgm N` with any id from the table above plays that stage's music on
the hidden stage.

## Scope

Two byte writes (one on a clean ROM), no bank use, no WRAM, no hooks — stacks
anywhere (`tools/mkpatch17.py`, `--stacked` supported). Knobs: `--no-pool`
(leave the random default bounded to nine), `--bgm N`. Standalone
`build/sms_allstages.bps` → `e5dd325b…`; playable test bundle
`build/sms_ref_v2_allstages.bps` = REF v.2 + patch 17 → `e8fc6045…`.

**Field verdict (2026-08-05): clean, and it stays OPTIONAL.** The Saturn line
was rebuilt as v0.15.0 with patch 17 folded in, played, and retired the same
day — the maintainer finds the tenth stage "a bit distracting visually", so it
is in neither REF nor patch 100. The Saturn builder keeps the capability behind
`SATURN_ALLSTAGES=1` (off by default), applied by calling `mkpatch17.apply_to()`
rather than carrying a second copy of the bytes, with `SATURN_STAGE_BGM=<byte>`
as the `--bgm` knob; an opted-in build tags its on-screen version **S**
(`v0.14.15HRS`) so it cannot be mistaken for the shipped one in a field report.
Both directions were byte-checked at the time: the default rebuilt v0.14.15
**exactly** (`8c5db8e4…`/`e1788e31…`), and the opted-in build differed from it by
**six** bytes — patch 17's three, the version tag, the checksum. (The Saturn line
has since advanced to **v0.16.1**, hidden `91639250…` / +stage `c8f7dae8…`, which
is what the builder reproduces today; the hook is still off by default.) Play
patch 17 instead via `sms_allstages.bps` or `sms_ref_v2_allstages.bps`.

---

# Patch 18 — no ACS in 2P VS

**Why.** The **A.C.S.** (Ability Customize System) screen redistributes a
character's stats before the fight — 攻撃 / 防御 / 体力 / 必殺技 / おちゃめ.
Fine in single player; not something that belongs in a match between two people,
for the same reason patch 15 removes AUTO. Companion to 15, same screen.

**Where the door is** (measured, `tools/probe_acs_select.lua` — the probe presses
SELECT and reports the menu state and a screenshot, and asserts it reached the
config screen first). The VS config screen hands off through a per-game-mode
dispatcher:

```
$C3:BB60  jsr $BBCA / lda $8D / asl / tax / jmp ($BB6D,x)
$C3:BB6D  table: $BB77 $BB93 $BB93 $BBAF $BBBA      ; modes 0..4
```

`$8D` is the game mode (0 story, **1 = 2P VS**, 2 vs-COM, 3/4 …), and **modes 1
and 2 share one handler** at `$C3:BB93`:

```
$BB93  jsl $809737 / lda $1838 / sta $8E / sep #$20
$BB9E  lda $1C02 / cmp #$02 / beq $BBAA     ; $1C02 == 2 means SELECT was pressed
$BBA5  lda #$00 / sta $8A / rts             ; -> start the match
$BBAA  lda #$05 / sta $8A / rts             ; -> menu state $05 = ACS
```

Menu state `$05` has exactly **two writers in the whole ROM** — `$C3:BB8E` (the
story handler) and `$C3:BBAA` (this one) — so closing this branch for mode 1
closes the only versus door, and story/vs-COM keep theirs.

**The edit** — 12 bytes at `0x03BB9E`, in place, no bank and no stub. Because
modes 1 and 2 share the handler, the mode is re-tested inside it:

| Offset | Vanilla | Patched |
|---|---|---|
| `$BB9E` | `AD 02 1C` `lda $1C02` | `A5 8D` `lda $8D` |
| | `C9 02` `cmp #$02` | `3A` `dec a` — Z iff mode 1 |
| | `F0 05` `beq $BBAA` | `F0 12` `beq $BBB5` — 2P VS: start the match |
| `$BBA5` | `A9 00 / 85 8A / 60` | `AD 02 1C` `lda $1C02` |
| | | `C9 02` `cmp #$02` |
| | | `D0 0B` `bne $BBB5` — not SELECT: start the match |

`$BBAA` (the ACS branch) is untouched and is now reached by falling through. The
replaced tail was this handler's own `lda #$00 / sta $8A / rts`; the patched code
branches instead to the **identical** tail at `$C3:BBB5` inside the mode-3
handler — same instructions, same 8-bit A (both paths `sep #$20` first), and
nothing in the bank jumps into the replaced bytes (scanned for jmp/jsr/indirect
references). Modes other than 1 execute exactly as before.

**Verified in-emulator**, four cells, each with the screen captured:

| ROM | mode | SELECT on the config screen |
|---|---|---|
| clean | 2P VS | menu state `$05` — **ACS opens** |
| clean | vs-COM | `$05` — ACS opens |
| **patched** | **2P VS** | **`$00` — the match starts; no ACS** |
| **patched** | vs-COM | `$05` — **ACS still opens** (the control) |

The vs-COM row is what proves the patch removed a *mode's* access rather than
breaking SELECT. Regression: **42/42** on clean + p18, identical to clean.

⚠ The screen still reads `PRESS "SELECT" TO ACS`, because that strip is part of
its compressed tilemap — the same shape as patch 15, where the モード row still
displays マニュアル. The option is inert, not erased.

⚠ Probe note: in **1P-vs-COM the second character is confirmed by P1's pad**, not
P2's (P2 is inert there, exactly as in Practice). A harness that mashes P2 stalls
on character select and reports "never reached the config screen".

**Regression tests (added 2026-08-05).** Two, both dual-mode:
`p18-no-acs-in-2p-vs` presses SELECT from `traces/config_vs_clean.mss` and reads
the menu state — vanilla `$05` (ACS), patched `$00` (the match starts); and
`p18-acs-kept-in-vs-com` does the same from `traces/config_com_clean.mss` and
expects `$05` on **every** build. The second is what stops the first from being
satisfiable by breaking SELECT outright. Negative-controlled: forcing detection
to "p18 present" on a clean ROM fails with `got $8A=05`.

**Scope.** 12 bytes, no bank use, no WRAM, byte-disjoint from every other patch —
stacks anywhere (`tools/mkpatch18.py`, `--stacked` supported). Standalone
`build/sms_noacs_vs.bps` → `67897bbf…`. **In both reference builds from Rev. 02**
(maintainer, 2026-08-05), chained straight after patch 15 — the two belong
together: same screen, same reason.

---

# Patch 101 — Saturn voice pitch (`SATURN_PITCH=1`)

**Status: SHIPPED, ON BY DEFAULT** (2026-08-05) — it rides in Rev. SS-02. The
"held pending a listening test" state below was resolved by that test: the field
verdict is that her pitch is correct, and the one accepted limitation is that a
**Moon facing her is three semitones flat** (the shared-transpose limitation, see
the last section). `SATURN_PITCH=0` builds patch 100 alone and reproduces
`03b73cdd…` byte-for-byte. The "voices 1/2/6" finding below stays **recorded but
un-chased** — the listening A/B is what cleared it.

## What

Saturn's voices play about three semitones sharp. Her samples are natively
~6539 Hz but are requested through **char 1's sound ids (49-52)**, which carry
Sailor Moon's note values. Patch 101 corrects the four notes.

## Mechanism

Pitch in this SPC driver is per-sound NOTE data, not a per-sample rate. Each
sound id's sequence header carries a **TRANSPOSE byte** at `seq+3`, worth exactly
one semitone per unit (full decode: `docs/project/saturn/sound_scope.md`). Her four:

| id | move | ARAM | vanilla | patched | measured pitch |
|---|---|---|---|---|---|
| 49 | win laugh | `$1C91` | `$FE` | `$FB` | (never fires in the test window) |
| 50 | 236P | `$1CAB` | `$FE` | `$FB` | `$03E4` → `$0346` |
| 51 | 214P | `$1CB6` | `$FF` | `$FB` | `$041F` → `$0346` |
| 52 | j.632K | `$1CC1` | `$FD` | `$FB` | `$03AC` → `$0346` |

All four converge on `$FB` because her four samples share one native rate. The
result is `$0346` against the maintainer-settled target `$0345` — one LSB, 0.5
cents, because the driver interpolates between semitone-table entries and rounds.

**Delivery.** The four bytes live in the SPC driver, which is uploaded to ARAM,
so they are written as **four 1-byte IPL blocks appended to streams patch 100
already sends**: her directory streams on a Saturn load, char 1's restore streams
on a non-Saturn load. The apply/restore gating is therefore 100's existing
DIRTY-flag machinery, unchanged — 101 adds no hook, no flag and no table record.

⚠️ **Two traps paid for here.**
1. **A stream of its own costs an audio phase shift.** The first implementation
   used two extra table records, two extra IPL streams and a ~111-byte sync stub.
   It worked, but the extra upload at character load shifted the whole audio
   timeline ~3 frames relative to match start — inaudible in itself, but it
   desynchronises every future `trace_dsp` comparison of a Saturn session. Riding
   the existing streams adds 20 bytes to an upload that already happens.
2. **P2's streams are relocated by dp `$10` = `$0010`,** so the blocks in them are
   written 16 bytes LOW to land on the right addresses.

Stream slots are respaced (`0x2600/2640/2680/26C0` instead of `.../2620/2640/2660`)
**only when 101 is built in**, so a 100-without-101 build stays byte-identical to
the shipped v0.14.9.

## Why a build flag, not an independent BPS

Patch 14 is *inert* without 13. **101 without 100 would be actively wrong**: the
same four bytes retune sound ids 49-52, which belong to char 1 — with no Saturn
samples behind them, that is Sailor Moon's voice, three semitones flat, in a ROM
where Saturn does not exist. A flag makes the dependency unbuildable-around
rather than a warning someone can ignore. The standalone BPS
(`build/saturn/sms_saturn_pitch.bps`, 170 B) is diffed **100 → 100+101** for
distribution and A/B, exactly as patch 10b is diffed within its own slot.

## Verification

Base `03b73cdd…` (patch 100) → `30a130e893d2…` (100+101); 150 bytes differ. BPS
round-trips to the same hash.

| check | result |
|---|---|
| patch 100 rebuilt with 101's code present but OFF | **byte-identical**, `03b73cdd…` |
| REF v.1 / v.2 rebuilt | **byte-identical**, `2873f214…` / `6d79fb5f…` |
| Saturn session, semantic DSP diff (shell 6) | key-on sequence identical, **0 structural**; only srcn 49/50/51 change, all to `$0346` |
| same, shell 8 (the two-shells rule) | identical result |
| **vanilla** session, DSP frame-aligned diff | **byte-identical** (47378 writes) |
| **vanilla** session, WRAM diff | **byte-identical**, all 128 KB × 10 checkpoints |
| **Saturn** session, WRAM diff | **byte-identical** — the transposes live in ARAM, so WRAM must not move |
| `test_regression.lua` | **ALL PASS (57)** |
| `verify_saturn.sh` | **ALL PASS (45 checks)** — the gate as it stood on 2026-08-05; it has since grown to 53 |

Note the oracle: across builds whose LOAD duration differs, a frame-aligned DSP
diff desynchronises (see trap 1) — use `dspdiff.py --semantic`, which compares the
ordered key-on sequence and is shift-immune.

## The "voices 1/2/6" finding — narrowed 2026-08-04, then CLEARED by the field test

Measured with `tools/saturn/probe_sms_voicechan.lua`, which watches the driver's
PER-CHANNEL state (`$0240+X` transpose, `$02B0+X` pitch shadow) instead of the DSP
output. Three things are now settled and one is not.

**1. It is NOT layered sfx.** Her transposes (`$FD`/`$FE`/`$FF`, and `$FB` when
patched) appear on **logical channel 12 only** — the channel her sfx table entry
selects, mapping to DSP voice 4. Channels 10/11/13 carry other sfx's transposes
(`$04`/`$0A`/`$00`), never hers. The benign reading is dead.

**2. It is far smaller than first reported.** The original "~84 frames" counted DSP
register writes, but the flush at `$12F4` re-pushes the same shadow every tick, so
one wrong value is smeared over many frames. At the shadow level — where the pitch
is actually computed — the music channels differ at **exactly one write each**:
ch 1 and ch 2 at one position of 205, ch 6 at one of 86. Write counts are identical.
So the artefact is *three perturbed music notes in a 900-frame session*, not a
sustained detune.

**3. Patch 101 does not create it; it changes it.** The perturbed music value is a
FUNCTION of her transpose (it differs between `$FD` and `$FB`), so it is already
displaced in vanilla — by her vanilla transpose. An idle run in which she never
voices produces different music-channel streams again. The cross-talk is the
driver's, and it is pre-existing; 101 alters what the wrong note is, not whether
there is one.

**Not settled: the path.** The note converter `$0D6D` is clean per channel — both
its callers (`$10AD`, `$1215`) set `$38` first, X is pushed/popped, and the stale
high byte of `$E7`/`$E8` cannot reach the result (the `ADDW` carry propagates
upward only). So the contamination enters through `$0300+X` / `$0400+X` or through
the music sequence's own timing, and finding it needs the sequence interpreter
read rather than the converter.

**What closed it:** the listening A/B of `sms_saturn_pitch.bps` applied and not
(maintainer, 2026-08-05). The question was whether three single-note
perturbations per ~15 seconds are audible at all — and since the vanilla build
already perturbs those same notes by a different amount, the honest comparison
was "does it sound worse", not "does it sound wrong". It did not, so 101 shipped
on by default and the path stays un-chased.

## Known limitation, independent of the above

The transpose lives in a **shared** sfx sequence, so **P1 Saturn + P2 Sailor Moon
cannot both be right**: whichever transposes are loaded apply to both. With 101
on, a Moon facing a Saturn hears his own voice three semitones flat. Niche — Moon
is not a shell and this is a hidden character — but it is a real regression in
that one matchup and the maintainer should decide it explicitly.
