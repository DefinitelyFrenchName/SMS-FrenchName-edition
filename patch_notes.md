# patch_notes.md — SMS Uranus Infinite™ → 1-frame link

Target: Bishoujo Senshi Sailor Moon S: Jougai Rantou!? (SFC, Japan),
clean ROM SHA-1 `bc0e29ee383574443226695215496eb0d09aaa1c` (HiROM+FastROM, headerless).
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

## Applying

```
flips --apply build/sms_uranus_infinite_1f.bps <clean ROM> <output ROM>
```

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
