# patch_notes.md — SMS Uranus balance/feature patches

Target: Bishoujo Senshi Sailor Moon S: Jougai Rantou!? (SFC, Japan),
clean ROM SHA-1 `bc0e29ee383574443226695215496eb0d09aaa1c` (HiROM+FastROM, headerless,
file offset = SNES addr & 0x3FFFFF).

This document covers eight independent patches (1–5 gameplay/cosmetic, 6–8 optional/
experimental). Each is a separate stackable BPS built by its own `tools/mkpatchN.py`; their
edits are byte-disjoint, so they combine cleanly. **New here? Read `HANDOFF.md` first** — it is
the operational map (current state, deliverables, tooling, findings, gotchas).

## Deliverables & how they stack

| Patch | What | Builder | Standalone BPS | Patched SHA-1 |
|---|---|---|---|---|
| 1. 1f-link **(CANONICAL)** | Uranus infinite → **1-frame meaty** (N=6): exactly one press connects, and it's an unblockable-by-block meaty (escapable by invincible reversal / jump) | `tools/mkpatch.py 0x04` | `build/sms_uranus_infinite_1f.bps` (+`.ips`) | `c773d99a…` |
| 1b. 1f-link (true combo) | **Alternative to patch 1** — true unblockable 1-frame combo (N=5); wider (2-frame connect: combo@0 + meaty@+1) | `tools/mkpatch.py 0x05` | `build/sms_uranus_infinite_1f_truecombo.bps` (+`.ips`) | `8966c119…` |
| 2. Dash-fix | Remove reversal-dash invincibility | `tools/mkpatch2.py` | `build/sms_dashfix.bps` (+`.ips`) | `07d760fe…` |
| 3. Palettes | Big Zam extended colors + "FrenchName" header | `tools/mkpatch3.py` | `build/sms_palettes.bps` | `291f6474…` |
| 4. Title | Title subtitle → "FrenchName ver. 0.4" | `tools/mkpatch4.py` | `build/sms_title.bps` | `e5dce7d5…` |
| 5. Dash dist | Cut Uranus forward-dash distance ~1/3 | `tools/mkpatch5.py` | `build/sms_dashdist.bps` | `99acb686…` |
| 6. Dash i-frames **(OPTIONAL)** | Uranus forward dash gains ~6 strike-invuln frames mid-move | `tools/mkpatch6.py` | `build/sms_dashinvuln.bps` (+`.ips`) | `34c5d458…` |
| 7. Pluto 5HP **(OPTIONAL)** | Pluto 5HP hitbox extended down to hit crouchers (all but Chibi) | `tools/mkpatch7.py` | `build/sms_pluto5hp.bps` | `fc757936…` |
| 8. Venus throw tech **(OPTIONAL)** | Venus 6HP throw mash-escape window 6f → 13f (standard-ish; Jupiter=15f) | `tools/mkpatch8.py` | `build/sms_venustech.bps` | `63ce0748…` |

Combined builds:
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
| **Pluto 5HP reach (opt.)** | `mkpatch7.py … --h <n>` | `62` | New active-box height: `54` = vanilla (whiffs crouchers), **`62` = hits all crouchers except Chibi**, `64` = all incl. Chibi. Byte `0xAF0DE`. |
| **Venus tech window (opt.)** | `mkpatch8.py … --extra <n>` | `1` | Extra sampling steps on the throw-hold script: `0` = vanilla 6f, **`1` = 13f (default)**, `2` = 19f, `3` = 24f (whole hold). Standard throws ≈ 15f (Jupiter). Bytes `0x16C70/78/80`. |

Patches 2 (dashfix) and 3 (palettes) have no knobs — they're single-purpose. Example
retune: `python3 tools/mkpatch.py 0x05 build/n5.sfc` (true-combo gate), or
`python3 tools/mkpatch6.py "<clean>" build/tight.sfc --lo 6 --hi 9` (tighter i-frame window).

---

# Patch 1 — Uranus Infinite™ → 1-frame link

Patched ROM SHA-1 `c773d99a16910c9aff57a6df019b713ffcf87160`.
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

Patched (standalone) SHA-1 `8966c119d1415f64f4bebd2af9c33f91847cd60b`.
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

Patched (dashfix only) SHA-1 `07d760fea31b727dd30200d59f1239404fc1ab7b`.
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

# Patch 3 — Extended palettes (Big Zam extraction) + "FrenchName" header

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

# Patch 4 — Title subtitle → "FrenchName ver. 0.4"

Patched (title only) SHA-1 `e5dce7d5130909fc0e125ea621a11a10d2ded04e`.
Deliverables: `build/sms_title.bps` (clean → subtitle + header), `build/sms_full4.bps`
(clean → all four). Built by `tools/mkpatch4.py` (+ `tools/texttiles.py`).

## What this patch does

Replaces the red Japanese subtitle (場外乱闘!? 主役争奪戦) with **"FrenchName ver. 0.4"** —
white glyphs, red outline, in the subtitle's own palette. Sailor Moon logo, all menu items,
and both copyright lines untouched. Validated against a true-to-resolution mockup first; the
patched ROM's subtitle band is **pixel-identical** to the approved mockup.

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

## Changed bytes

- **0x3B81F–0x3B822**: `22 43 8C 80` (`JSL $80:8C43`) → `JSL` to the stub (bank/addr computed
  from ROM size: `$E8:0000` standalone / `$E9:0000` combined).
- **Appended bank** ($E8/$E9): 195-byte DMA stub (calls `$80:8C43`, then 6 DMA runs) + 1344
  bytes of custom tile data.
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
- **No gameplay regression on `sms_full4`**: 1f-link dash-out@100 / press-115-only; reversal
  meaty connects (P1 → hitstun 0x16); palette selection still distinct (A vs Y CGRAM differ).
- **BPS round-trips**: reproduces both builds byte-exact from clean.

Hook safety: the stub runs once during title-load force-blank, calls the original loader
first, and only adds DMAs; it never executes during matches.

---

# Patch 5 — Halve the forward-dash distance

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

*(A related observation, NOT changed: the fireball's **hurtbox** (its vulnerability, for players
who try to destroy the fireball) uses the separate hurt table and may share the same
authored-upward mismatch; left untouched since the request was the hitbox. One-flag follow-up if
wanted.)*

---

# Applying (summary)

```
# individual
flips --apply build/sms_uranus_infinite_1f.bps <clean ROM> <out>   # patch 1
flips --apply build/sms_dashfix.bps            <clean ROM> <out>   # patch 2
flips --apply build/sms_palettes.bps           <clean ROM> <out>   # patch 3
flips --apply build/sms_title.bps              <clean ROM> <out>   # patch 4
flips --apply build/sms_dashdist.bps           <clean ROM> <out>   # patch 5
flips --apply build/sms_dashinvuln.bps         <clean ROM> <out>   # patch 6 (optional)
flips --apply build/sms_pluto5hp.bps           <clean ROM> <out>   # patch 7 (optional)
flips --apply build/sms_venustech.bps          <clean ROM> <out>   # patch 8 (optional)
flips --apply build/sms_neptune_ds.bps         <clean ROM> <out>   # patch 9 (optional)

# combined
flips --apply build/sms_both.bps  <clean ROM> <out>   # patches 1 + 2
flips --apply build/sms_full.bps  <clean ROM> <out>   # patches 1 + 2 + 3
flips --apply build/sms_full4.bps <clean ROM> <out>   # patches 1 + 2 + 3 + 4
flips --apply build/sms_full5.bps <clean ROM> <out>   # patches 1 + 2 + 3 + 4 + 5
flips --apply build/sms_full6_v08_dashinvuln.bps <clean ROM> <out>  # canonical + patch 6
flips --apply build/sms_full7_pluto5hp.bps       <clean ROM> <out>  # canonical + patch 7
flips --apply build/sms_full8_venustech.bps      <clean ROM> <out>  # canonical + patch 8
flips --apply build/sms_full9_neptuneds.bps      <clean ROM> <out>  # canonical + patch 9

# stacking IPS onto an already-patched ROM (checksum-free variants)
flips --apply build/sms_dashfix.ips <1f-link ROM> <out>
```

Standalone per-patch write-ups remain at `patch_notes_dashfix.md`, `patch_notes_palettes.md`,
and `patch_notes_title.md`; this file is the consolidated reference.
