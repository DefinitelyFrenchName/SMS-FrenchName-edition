# patch_notes_dashfix.md — Remove reversal forward-dash invincibility (SMS Uranus)

Target: Bishoujo Senshi Sailor Moon S: Jougai Rantou!? (SFC, Japan),
clean ROM SHA-1 `bc0e29ee383574443226695215496eb0d09aaa1c`.
Patched (dashfix only) SHA-1 `07d760fea31b727dd30200d59f1239404fc1ab7b`.
Stacked (1f-link + dashfix) SHA-1 `5ae720fe0d3b6613555028d1bf33cf8642f85e3a`.

Deliverables (built by `tools/mkpatch2.py`):
- `build/sms_dashfix.bps` — clean ROM → dash-fix (canonical, checksummed)
- `build/sms_dashfix.ips` — same change, checksum-free; **stacks onto the 1f-link
  patched ROM** (verified byte-exact against the stacked reference build)
- `build/sms_both.bps` — clean ROM → both patches, for convenience

## The bug (community: "bugged reversal forward dash")

Uranus's 66 forward dash (action 0x60), performed as a reversal out of knockdown
wakeup (and any other state that allows a command reversal), is fully invincible for
its entire duration. A neutral 66 is not. Dustloop describes it as the dash "gaining
the invincible properties of backdash" — mechanically that turns out to be wrong:

## Root cause (found, verified at code level)

- On knockdown, the hit-resolution code (`$C1:0F8D` writes) sets **player+0x46
  (hurt_state) = 0xA0** — the "untargetable while knocked down" status. It stays set
  through the whole knockdown → lying down → stand-up chain (actions 0x19/0x1E/0x20),
  during which the character also has no hurtbox.
- The engine convention is that **every volitional action's handler clears +0x46 in
  its step-0 init** (`stz $46,X`): verified in all of Uranus's attack handlers
  (e.g., 2HP at `$C1:872A-872E`), her other movement handlers (`$C1:88FF`,
  `$C1:8930`), the landing handler (clear at `$C1:7F1A`), the neutral state
  (`$C1:7D2F`) — and, decisively, **Moon's forward-dash handler**: her reversal dash
  shows +0x46 = A0 only on the 1-frame step-0 carryover, then 00.
- **Uranus's forward-dash handler (`$C1:88C8`) is missing the `stz $46,X`** in its
  step-0 init (which sets sfx `$78`=0x2D, flags +0x54=0x0009, hop velocity FEC0,
  gravity 0x40, X-speed 0x0B via `jsr $0389`). So a reversal dash carries the
  knockdown untargetability until the landing handler finally clears it — the entire
  14-frame, full-screen dash.
- Causality proven by poke: zeroing $1046 mid-reversal-dash makes a meaty attack
  connect (air hitstun) on the otherwise-invincible clean ROM.
- Note: backdash (0x26) is invincible **by design** via its animation script using
  hurtbox index 0 — unrelated mechanism, untouched by this patch.

## The fix (restores the engine-standard clear; 10 bytes)

Reroute the step-0-only `jsr $0389` through a stub that performs the original call
and then the missing clear — exactly what every other handler does:

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

Stub lives in the same verified-unused zero region as the 1f-link stub
($C1:BE0E–BE47; zero accesses over 20k frames of vanilla gameplay), at BE2A —
**byte-disjoint from the 1f-link patch** (0x1874D/E + 0x1BE20-29), so both stack.
Width safety: `$0389` and the following `$0336` both begin with `rep #$30`, so the
stub's exit state (M=1) matches the handler's step≠0 calling convention.

Coverage of "all reversal contexts": the clear is at the **sink** (the dash's own
init), so any entry path with stale +0x46 is covered by construction — wakeup after
sweeps, throws, air-juggle knockdowns (all converge to stand-up 0x20), and any other
reversal-capable state. Air-reset landings were already safe on clean (landing
handler clears +0x46). The one-frame step-0 carryover remains, identical to Moon's
dash and to every attack — engine-normal behavior.

## Verification (Mesen2 testrunner, deterministic RAM, savestate traces)

1. **Repro on clean**: sweep → wakeup at t=159 → reversal dash → P2 meaty
   (which provably hits a non-dashing wakeup at t=161) passes through harmlessly;
   $1046 = A0 for the dash's entire duration.
2. **On dashfix ROM**: identical scenario → meaty connects at t=161, knocking Uranus
   out of the dash. Same on the stacked ROM.
3. **No side effects** (clean vs dashfix, per-frame logs byte-identical):
   neutral forward dash; neutral backdash; **reversal backdash** (design invuln
   intact); whiff traces of 2LP/2HP/2LK/2HK.
4. **Moon-vs-Moon session**: stub never executes (exec-watch = 0); her reversal dash
   unchanged.
5. **1f-link regression on the stacked ROM**: dash-out still 100, only press 115
   continues the infinite (114 lost, 116 blocked) — both patches fully functional
   together.
6. BPS/IPS round-trips: clean→dashfix (bps), dashfix-ips-on-1f-link == stacked
   reference, clean→both (bps) — all byte-exact.

## Applying

```
flips --apply build/sms_dashfix.bps  <clean ROM>          <out>   # dash fix only
flips --apply build/sms_dashfix.ips  <1f-link ROM>        <out>   # stack on 1f-link
flips --apply build/sms_both.bps     <clean ROM>          <out>   # both fixes
```
