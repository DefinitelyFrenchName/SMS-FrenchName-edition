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
       defender +0x48 first-hit defense  +  ACS stat shifts  +  counter-hit shift
  └─ $C0:D055 lookup → final = TABLE[row][(mod+8)&15]
  └─ ONE of the damage-apply sites subtracts from victim HP       [§2]
```

Exceptions that skip the modifier machinery entirely: throw tosses, throw-tech
knockdowns, hold-throw / desperation-grab drain ticks (§5).

## 2. The damage-apply census (every PC that writes victim HP in combat)

All share the shape `lda $0049,Y / sec / sbc $DP / sta $0049,Y` with Y = victim struct
(`$1000`/`$1080`), D = 0. Death check `cmp #$90 / bcs` (HP underflow → KO).

**The death rule (verified 2026-07-19): HP 0 is SURVIVABLE — death is underflow, not
zero.** Chip 1 against a 1-HP defender writes exactly 0 and they fight on (normal
blockstun, no KO); chip 2 against 1 HP underflows to 0xFF and triggers the full KO
chain (acts 0x1A→0x1E→0x1F, then a second write zeroes the corpse's HP). Corollaries:
- **Chip CAN kill** whenever chip > remaining HP (community "no chip kill" is per-move,
  not per-engine).
- Moves whose chip floors at 1 (e.g. Pluto's Dimension Dance) can never KO a defender
  with ≥1 HP — but a 0-HP survivor dies to ANY next hit, chip included (0−1 wraps).
- A 0-HP-alive state is reachable in real play and the life bar shows empty.
- Independently confirmed by the community: the game-wide Dustloop frame-data page
  states "You live on 0 health, must be reduced to below 0".

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

Final damage = MATRIX64[row][8 + modifier] — a 64-row × 16-column table (column 8
neutral, smaller = stronger; rows 0-15 dumped in `sms_acs_system.md` §2).

**THE MODIFIER, FULLY DISASSEMBLED (2026-07-19 — supersedes every "RNG jitter" claim):**
the composition code is 11 near-identical handlers at file 0xCAED-0xCD6D, template:

```
if $8D == 4 -> no-damage exit ($CD6A)          ; practice mode
mod  = (defender+0x18 bit0) ? -2 : 0           ; COUNTER-HIT FLAG (the -2 columns)
mod += defender+0x48                            ; FIRST-HIT DEFENSE (see below)
mod += defender+0x71                            ; ACS defense
mod -= attacker stat                            ; $70 normals / $73 specials / $74 desperations
mod -= 1                                        ; (present in the dec_a handler variants)
row  = attacker+0x45
jsr/jmp $D055                                   ; damage = MATRIX[row][(mod+8)&15]
```

Verified numerically live (Uranus 5HP: d48=1 → mod 0 → row8 col8 = 8; d48=0 → −1 →
col7 = 10). Handler flavors: 3 stats × dec/no-dec `jmp` HIT handlers, plus 5 `jsr`
tail handlers — the tails implement **chip = damage>>2, floor 1** (our measured chip
law, in literal code) and, on three desperation handlers, **damage clamped to the
defender's remaining HP** (`if hp < dmg then dmg = hp`) — the "cannot kill" mechanism
behind Dimension Dance's no-chip-kill in code form.

- **THE OURS-VS-WIKI OFFSET, UNIFIED**: every systematic damage difference between
  this project's tables and Dustloop's (37 vs 48, 9/11 vs 12/14, chip 9 vs 12...) is
  the d48 state — our rigs measured FRESH defenders (d48=1, +1 column = weaker hits),
  the wiki measured mid-match (d48=0, the natural state after any hit). Verified:
  Venus/Neptune desperation chip with d48 poked to 0 reads exactly the wiki's 12.
  Neither source was wrong; they sampled different states of the same deterministic
  system. (The wiki's ×2/×5 multi-chip HIT COUNTS remain unreproduced — flagged.)
- **THERE IS NO RNG IN DAMAGE.** The historical "variance"/"roll" is defender
  **+0x48, the first-hit defense**: loaded 1 at character init, it grants +1 modifier
  column until the defender is first hit, then is cleared — by a 16-bit
  `stz $47,X` at `$C1:0E51` that zeroes hitstun-staging +0x47 AND +0x48 together (a
  two-byte side effect). Every "roll pair" ever measured (ours and the wiki's
  damage|faceHit columns) is exactly d48=1 vs d48=0 — two adjacent matrix columns.
  Damage is fully deterministic. **+0x48 is PER-CHARACTER** (manifest byte):
  Jupiter 1, Neptune 2 (verified — fresh Neptune takes 6 where a d48=1 defender takes
  8: two columns of first-hit protection); remaining characters' manifest values need
  boot-fresh rounds to census (mid-match saves carry hit history).
- **Counter-hit** = defender +0x18 bit0 (set during attack-family acts): literal
  `lda #$FE` = −2 columns.
- **ACS stats** — attacker +0x70/+0x73/+0x74 chosen PER HANDLER (this is where
  +0x74 = desperation-only is decided); defender +0x71 added.
- **NOT inputs**: hurtbox contact zone (§7), and $7E:0090 (the RNG is real but feeds
  other systems — ochame rolls — not damage).

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
- Single-hit desperations always land on the same column across repeated rolls. Read
  correctly (§3): there is no jitter anywhere — normals' apparent spread was the
  defender's +0x48 first-hit defense, and desperations show none because that pair does
  not apply to them.

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
  NOT scaled by ACS stats (attacker +0x74 nor defender +0x71 verified), NOT
  counter-boosted, posture-independent. (Patch 13 scales them via its own table hook.)
- **Command-grab specials use these paths too** (probe: 360-input at 2 frames/step —
  3f/step is too slow and produces a normal instead): **Uranus SPD** (6321478HK, acts
  68-71) = a single TOSS 32 through `$C1:082F`; **Jupiter SPD** (6321478HP, acts
  6E-71) = an airborne CARRY (victim held 72px up) draining 5×6=30 through the tick
  site. Both apply with holder +0x44 = **0** — indistinguishable from normal throws at
  the apply site by class byte alone (act-set gating would be needed to treat them
  differently).
- None of these paths respect ACS +0x71 defense (throw 20→20, Uranus SPD 32→32,
  Jupiter SPD 30→30 at defense 7) — "defense" in this game means the matrix modifier,
  nothing more.
- **Column-wrap quirk:** the lookup masks `(mod+8)&15` without clamping, so a large
  right-shift (e.g. defense 7) on an already-weak-rolled hit wraps to the STRONG
  columns: heavy normal 8 → 23 measured roll-matched. See sms_acs_system.md §1.
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
