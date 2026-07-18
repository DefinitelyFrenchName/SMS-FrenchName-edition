# The damage system — complete reference

**What this is.** Everything known about how Bishoujo Senshi Sailor Moon S: Jougai
Rantou!? computes and applies damage: the pipeline, every apply site, the modifier
inputs (RNG, ACS stats, counter-hit, posture), the special paths (throws, drain ticks,
tosses), and what does NOT affect damage (hurtbox contact zone). Companion to
`sms_acs_system.md` (the stat/matrix detail) and `sms_engine_internals.md` §6 (hit
resolution context). Clean-ROM SHA-1 `bc0e29ee383574443226695215496eb0d09aaa1c`; file
offset = SNES address & 0x3FFFFF (HiROM). Probe-verified 2026-07-17/18; probes in §8.

---

## 1. Pipeline overview

```
hit detected ($C0:BFC0 resolution, boxes overlap)
  └─ per-attack on-hit record [dmg, hitstun, level, flags] ($C0:CDD5 + variants CE15…D015)
       └─ variant selected by (attack, defender posture)          [§4]
  └─ modifier accumulation (signed column shift):                 [§3]
       RNG jitter ($7E:0090)  +  ACS stat shifts  +  counter-hit shift
  └─ $C0:D055 lookup → final = TABLE[row][(mod+8)&15]
  └─ ONE of the damage-apply sites subtracts from victim HP       [§2]
```

Exceptions that skip the modifier machinery entirely: throw tosses, throw-tech
knockdowns, hold-throw / desperation-grab drain ticks (§5).

## 2. The damage-apply census (every PC that writes victim HP in combat)

All share the shape `lda $0049,Y / sec / sbc $DP / sta $0049,Y` with Y = victim struct
(`$1000`/`$1080`), D = 0. Death check `cmp #$90 / bcs` (HP underflow → KO).

| Site (file) | Path | Damage DP | Notes |
|---|---|---|---|
| 0xC09C, 0xC16F, 0xC216, 0xC2C5 | melee strike/chip | `$00` | 4 posture-variant sites (§4) |
| 0xC47E, 0xC551, 0xC5F8, 0xC6A7 | projectile strike/chip | `$00` | 4 variants, same idea |
| 0x1082F (`$C1:082F`) | **throw toss** | `$05` | thrower +0x44 = 0 for normal throws, 0x18 for Uranus's desperation toss |
| 0x1084D (`$C1:084D`) | throw tech | `$05` (negated half) | mash-escape success |
| 0x10D54 (`$C1:0D54`) | **hold-drain ticks** | `$05` | Moon/Mars/Chibi hold-throws AND desperation-grab drains (write ≈ $C1:0D61, mode-4 gated) |

Patch 13 (Guts) hooks all of these except the tech site; tick+toss share one stub gated
on holder +0x44 ≥ 0x12 so normal throws stay untouched.

## 3. The modifier — what shifts damage up or down

Final damage = row value shifted by a signed column modifier (column 8 neutral, ~±12%
per column, ~2× cap, ~¼ floor — matrix dump in `sms_acs_system.md` §2). Known inputs:

- **RNG jitter** — `$7E:0090`, frame-evolving, deterministic from reset under fixed
  input timing. THE source of damage variance (same jab rolls 1-6). All comparisons in
  this doc are roll-matched: same savestate + same landing frame = same roll.
- **ACS stats** — attacker +0x70 (normals) / +0x73 (specials) / +0x74 (desperation
  strike portion) shift left; defender +0x71 shifts right. Boost-only from the VS
  default of 0. Detail: `sms_acs_system.md` §3.
- **Counter-hit ("punish") shift** — see §6. Roughly +2-3 columns.
- **NOT an input**: which hurtbox (head/body/legs) the attack contacts — §7.

**RESOLVED (read-watch, 2026-07-18): the matrix is 64×16, not 16×16** — file
0xD081-0xD480 (1024 bytes; code resumes ≈0xD4A1). The live reader is the 16-bit load
at **`$80:D07B`** inside the $D055 lookup routine, which executes from **bank $80**
(exec-watching $C0:D055 catches nothing — the ROM's low 64K runs at $80:xxxx).
Verified reads: Jupiter 2HP → row 10 col 7 = 0x0D (13 dealt ✓); Jupiter desperation →
row 48 col 8 = 0x30 (48 ✓); vs croucher row 48 col 7 = 0x3E (62 ✓); Venus desperation
row 48 col 9 = 0x25 (37 ✓). **Row 48 is the shared single-hit desperation row**; the
per-move damage differences are base-COLUMN biases (Jupiter/Mercury/Moon c8,
Venus/Neptune c9, Mars c10). Row 48: `72 72 72 72 72 72 72 62 | 48 37 32 28 26 24 24
23` (cap 0x48=72 at c0-c6). This makes the shift arithmetic exact:
- **Counter-hit = −2 columns** (desperations: c8→c6=72, c9→c7=62, c10→c8=48 all match;
  normals: Uranus 5HP row 8 rolls c7/c8=10/8 → counters c5/c6=14/12 ✓).
- **Crouching defender = −1 column** on desperations (c8→c7, c9→c8, c10→c9 ✓). For
  normals, crouch hits route through a different apply site / on-hit record, so the
  crouch delta there is per-move record data, not necessarily a pure column shift.
- Single-hit desperations showed no RNG column jitter across repeated rolls (always
  the same column), unlike normals — desperation hits appear jitter-exempt.

## 4. Defender posture selects the on-hit values

- Same move, crouching defender → different (usually higher) value: Uranus 2LP 2/3 →
  3/4, 2HP 5/7 → 7/9; single-hit desperations Mercury/Jupiter 48 → 62, Venus 37 → 48.
- **Prejump counts as crouching** (Venus strike on a jump-squat defender deals her
  crouch value).
- **Air defender uses the stand-class value** (Mercury/Jupiter 48 on a rising defender).
- The 4 melee apply sites ARE the (attack, defender-posture) table variants made
  visible: observed mapping — Uranus standing normals → site 0xC09C (write pc
  `80C0A5`); her crouching normals vs a STANDING defender → site 0xC16F (`80C178`);
  crouching-vs-crouching → back to 0xC09C; Moon's and Jupiter's 5HP → 0xC16F.
- **Proximity normals are distinct moves**: Uranus far 5HP = act 0x43 (8/10), close 5HP
  = act 0x45 (9/12). A second reason community lists show two values per normal.

## 5. Paths outside the matrix

- **Throw tosses** (`$C1:082F`): fixed-ish values (Moon/Neptune normal throws tossed 20
  in our rig), thrower class byte 0 at toss time. Uranus's desperation is the only
  desperation using this path (toss 32 at class 0x18).
- **Drain ticks** (`$C1:0D54`): 3-4 HP per ~12 frames + a big finisher (Pluto: 11).
  NOT scaled by ACS stats, NOT counter-boosted, posture-independent. (Patch 13 scales
  them via its own table hook.)
- **Throw tech** (`$C1:084D`): negated half-damage refund path on mash escape.

## 6. Counter-hit / punish system

**It exists, and it is act-scoped.** A hit landing while the victim is inside an
attack-family act (a normal's act from startup THROUGH recovery, a special/misfire/taunt
act) takes bonus damage; the bonus expires the instant the move chains into the
universal recovery-tail act 0x2A.

Normals (roll-matched):

| Hit | vs idle | vs victim-in-move | act at impact |
|---|---|---|---|
| Uranus 5HP | 8 / 10 | **12 / 14** | Jupiter 5HP startup |
| Uranus 2HP (vs croucher) | 7 / 9 | **11 / 12** | crouched 2LP startup |
| Moon 5HP | 6 | **9** | taunt act, 15f AND 25f deep |
| Moon 5HP | 6 | 6 (no bonus) | 0x2A tail |

Desperations (defender mid-taunt-act at impact, v0.16 rig, Guts level 0 = clean-equal):

| Desperation | Normal | Punish | Delta |
|---|---|---|---|
| Moon (projectile) | 48 | **72** | +50% |
| Mercury (strike) | 48 | **72** | +50% |
| Mars (projectile) | 32 | **48** | +50% |
| Jupiter (strike) | 48 | **72** | +50% |
| Venus (strike) | 37 | **62** | +68% |
| Neptune (strike) | 37 | **62** | +68% |
| Uranus (rush→grab) | 67 | **67** | ±0 (see below) |
| Pluto (drain grab) | 48 | **50** | opener 3→5 only |
| Chibi (air barrage) | 52 | **54** | first hit 8→10 only |

Structural rules extracted from the table:

- The bonus applies to BOTH melee and projectile apply paths.
- **Only the first hit of a string can counter** — subsequent hits land on a victim in
  hitstun (acts 0x11/0x13), which is not an attack act.
- Hits whose base value sits at the row floor don't visibly change (Uranus's 1-damage
  rush opener countered for... 1).
- Drain ticks and tosses are immune (they bypass the modifier machinery; the victim is
  in the held act 0x1C anyway).
- Practical: single-hit desperations are the game's premium punish tools (+16 to +25
  damage on a real punish); multi-hit desperations gain almost nothing.

## 7. What does NOT change damage: hurtbox contact zone

Community folklore lists head/body values for normals. Tested and refuted:

- Attacker levitated (+12/+24 px via per-frame y-poke) so the SAME normal contacts a
  standing defender's torso vs head zone: identical damage on matched rolls (5LP 3-3-3,
  5HP 8-8).
- Moon's desperation projectile flown at forehead (dy−52) / torso (default) / shin
  (dy−6) height of a standing defender: 48 at every height.
- Uranus's 18-hit rush: per-hit values byte-identical stand-vs-crouch (only hit COUNT
  changes with the smaller crouch hurtbox).

The dual community values are real but come from §4 (posture variants) and §4's
proximity normals — not from which box is touched.

## 8. Tooling / reproduction

- `tools/probe_hitzone.lua` (+`_cfg`): fixed-frame normals, ALIFT attacker levitation,
  CROUCH/DBTN/DPH defender activity control, per-write logging with acts+y.
- `tools/probe_p13f_desp.lua` (+`_cfg`): desperation driver — side-aware motion input,
  NEUTRALBTN (avoid throw overlap), DEFJUMP/CROUCH/DTAUNT defender control, PROJY
  projectile-height pinning, path classification per HP write.
- Methodology: reload the same savestate per sample; identical input timing ⇒ identical
  RNG roll ⇒ deltas are pure variable effect. Always log the victim act at impact —
  attack acts displace hurtboxes and silently turn comparisons into whiffs.
- Counter-hit rig note: the v0.16 L-taunt is a convenient hitboxless attack-act for the
  victim; an interrupted taunt grants no Guts level, so damage stays clean-ROM-equal
  (non-interference proven bit-exact at level 0).

## 9. Interaction with the Guts patch (13)

Patch 13 scales the FINAL value at the apply sites — downstream of everything above, so
ACS boosts, posture variants, and counter-hits all compose multiplicatively with it.
A countered Jupiter desperation vs Guts L3: 72 × 40% ≈ 29 (floor 1 per table entry).
