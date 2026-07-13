# patch_notes.md — SMS Uranus balance/feature patches

Target: Bishoujo Senshi Sailor Moon S: Jougai Rantou!? (SFC, Japan),
clean ROM SHA-1 `bc0e29ee383574443226695215496eb0d09aaa1c` (HiROM+FastROM, headerless,
file offset = SNES addr & 0x3FFFFF).

This document covers three independent patches. Each is a separate stackable BPS built
by its own `tools/mkpatchN.py`; their edits are byte-disjoint, so they combine cleanly.

## Deliverables & how they stack

| Patch | What | Builder | Standalone BPS | Patched SHA-1 |
|---|---|---|---|---|
| 1. 1f-link | Uranus infinite → 1-frame link (frame-trap, N=6) | `tools/mkpatch.py 0x04` | `build/sms_uranus_infinite_1f.bps` (+`.ips`) | `c773d99a…` |
| 1b. 1f-link (true combo) | **Alternative to patch 1** — true unblockable 1-frame link (N=5) | `tools/mkpatch.py 0x05` | `build/sms_uranus_infinite_1f_truecombo.bps` (+`.ips`) | `8966c119…` |
| 2. Dash-fix | Remove reversal-dash invincibility | `tools/mkpatch2.py` | `build/sms_dashfix.bps` (+`.ips`) | `07d760fe…` |
| 3. Palettes | Big Zam extended colors + "FrenchName" header | `tools/mkpatch3.py` | `build/sms_palettes.bps` | `291f6474…` |
| 4. Title | Title subtitle → "FrenchName ver. 0.4" | `tools/mkpatch4.py` | `build/sms_title.bps` | `e5dce7d5…` |
| 5. Dash dist | Cut Uranus forward-dash distance ~1/3 | `tools/mkpatch5.py` | `build/sms_dashdist.bps` | `99acb686…` |

Combined builds:
- `build/sms_both.bps` — clean → patch 1 + 2 (stacked SHA-1 `5ae720fe…`)
- `build/sms_full.bps` — clean → patches 1 + 2 + 3 (SHA-1 `eb7b86f8…`)
- `build/sms_full4.bps` — clean → patches 1 + 2 + 3 + 4 (SHA-1 `51c397cb…`)
- `build/sms_full5.bps` — clean → **all five** (SHA-1 `b09a189c…`)
- `build/sms_full5_truecombo.bps` — clean → all five with **patch 1b instead of patch 1**
  (true-combo N=5) + title bumped to `v.0.6`. Playable ROM
  `build/SailorMoonS_FrenchName_v0.6_all5_truecombo.sfc` (SHA-1 `c96c89fb…`).
  Differs from the v0.5 all-five ROM by exactly **16 bytes**: the gate byte
  `0x1BE23` (`04→05`), 11 title-CHR bytes (the `5→6` version glyph), and 4 header
  checksum bytes — zero other gameplay changes.

Edit-region map (why they're disjoint):
- Patch 1: `0x1874D/E` + stub `0x1BE20–29` (bank $C1).
- Patch 2: `0x188ED/E` + stub `0x1BE2A–31` (bank $C1, adjacent free bytes).
- Patch 3: bank-$C0 hooks `0x884B` / `0x8998` / `0xA630`, appended bank $E8
  (file 0x280000+), header `0xFFC0` + checksum.
- Patch 4: bank-$C3 hook `0x3B81F`, appended bank ($E8 standalone / $E9 combined),
  header `0xFFC0` + checksum.
- Patch 5: 2 bytes at `0x188EA/EB` (dash X-speed operand), adjacent to but disjoint
  from patch 2's `0x188ED/EE`.

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

## Why this exists

Patch 1 (gate `0x04`, N=6) makes the `2HP > 66 > 2LP` loop require a frame-perfect
re-press, but it is a **frame trap, not a true combo**: on the frame-perfect rep the
defender momentarily *recovers into a block-ready state* before the follow-up 2LP
arrives, so simply holding down-back escapes the loop. That is the "one reactable
frame" the tester observed. A real 1-frame link should be an *unblockable* true combo
that a frame-perfect attacker lands regardless of what the defender holds.

The fix is one byte: shift the recovery gate from N=6 (`0x04`) to **N=5 (`0x05`)**,
so the dash-cancelled 2LP comes out one frame earlier and connects while the defender
is still in hitstun.

## Measured proof (Mesen frame-advance, uranus_vs_jupiter savestate)

Defender takes the 2HP clean, then holds **down-back** trying to block the follow-up 2LP.
Player-2 action-state per frame (`0x13`=heavy body hitstun, `0x0D`=**crouch block**,
`0x12`=light body hitstun / got hit):

| Build | P2 state around the follow-up | Result |
|---|---|---|
| Patch 1 (N=6, gate `0x04`) | `…13 13 13` → **`0D` (crouch block)** → `12` | defender reaches a **block-ready frame** → escapable by holding down-back = frame trap |
| Patch 1b (N=5, gate `0x05`) | `…13 13 13` → `12` (**no `0D`**) | defender **never leaves hitstun** → 2LP connects even while holding down-back = true unblockable combo |

Both variants still kill the *bufferable* (sloppy-input) infinite — the gating machinery
is identical, only the threshold moves by one; a non-frame-perfect press is rejected in
both. N=5 is the strictly better fix: same removal of the mash-buffer, but the intended
frame-perfect link is now a genuine combo instead of a blockable trap. (The full-removal
option, N=7 / gate `0x03`, was declined in favour of this.)

## Proof: the guaranteed combo is exactly one frame

`tools/demo_link.lua` reloads one savestate and replays the verified sequence
`2LP > 2HP > 66 > (follow-up 2LP)`, pressing the follow-up on frame `114 + LINK_OFFSET`
(opponent takes the setup, then holds down-back). Reloading makes every attempt
byte-identical, so the press frame is the only variable. The verdict is keyed on **P2's
action on the exact frame the follow-up connects** — the honest discriminator between a true
combo and a meaty. Deterministic result on the N=5 build, 3/3 attempts each:

| Offset | Follow-up 2LP | P2 on hit frame | Outcome |
|---|---|---|---|
| `-1` (`demo_link_early.lua`) | 1 frame early | — | **MOVE DROPPED** — 2LP never comes out (edge lost in dash recovery; no buffer) |
| `0`  (`demo_link.lua`) | only valid frame | **hitstun (0x13)** | **TRUE COMBO** — inescapable (a mashed reversal still can't act) |
| `+1` (`demo_link_late.lua`) | 1 frame late | **recovered (0x00 / crouch-block 0x0D)** | **MEATY** — still connects via the engine's hit-beats-same-frame-block rule, but P2 has recovered, so it is **not a true combo** (an invincible reversal / jump-out escapes it) |
| `+2` (`demo_link_blocked.lua`) | 2 frames late | crouch-block, no chip | **BLOCKED** — zero damage, loop stops |

So the **guaranteed true combo is exactly one frame** (offset 0 — hit while the opponent is
still in hitstun). Because of the same-frame-meaty quirk the follow-up still *connects* at
`+1` (against a non-invincible defender), making the practical *connect* window two frames;
clean block starts at `+2`. That +1 meaty is engine-wide priority behaviour and cannot be
removed without also killing the true combo (it is just "the hitstun boundary + 1").
Run headless: `ROM=build/SailorMoonS_FrenchName_v0.6_all5_truecombo.sfc tools/run.sh tools/demo_link_early.lua`
(and `_late`, and `tools/demo_link.lua` for on-time). In the Mesen GUI, open the v0.6 ROM
first, then run a wrapper; the demos load `traces/uranus_vs_jupiter_v06.mss` themselves —
that state is **tagged to the v0.6 ROM**, which matters because Mesen's GUI refuses a
savestate tagged to a different build (regenerate for another ROM by loading any match state
then `emu.createSavestate()`). `tools/demo_truecombo.lua` is the companion
that shows the on-time loop being unblockable while the opponent holds down-back.

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

# Applying (summary)

```
# individual
flips --apply build/sms_uranus_infinite_1f.bps <clean ROM> <out>   # patch 1
flips --apply build/sms_dashfix.bps            <clean ROM> <out>   # patch 2
flips --apply build/sms_palettes.bps           <clean ROM> <out>   # patch 3
flips --apply build/sms_title.bps              <clean ROM> <out>   # patch 4
flips --apply build/sms_dashdist.bps           <clean ROM> <out>   # patch 5

# combined
flips --apply build/sms_both.bps  <clean ROM> <out>   # patches 1 + 2
flips --apply build/sms_full.bps  <clean ROM> <out>   # patches 1 + 2 + 3
flips --apply build/sms_full4.bps <clean ROM> <out>   # patches 1 + 2 + 3 + 4
flips --apply build/sms_full5.bps <clean ROM> <out>   # patches 1 + 2 + 3 + 4 + 5

# stacking IPS onto an already-patched ROM (checksum-free variants)
flips --apply build/sms_dashfix.ips <1f-link ROM> <out>
```

Standalone per-patch write-ups remain at `patch_notes_dashfix.md`, `patch_notes_palettes.md`,
and `patch_notes_title.md`; this file is the consolidated reference.
