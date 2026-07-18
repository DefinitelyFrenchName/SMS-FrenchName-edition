# The A.C.S. stat system — complete reference

**What this is.** Everything known about the A.C.S. (character-customization) stat system
of Bishoujo Senshi Sailor Moon S: Jougai Rantou!? — the six per-fighter stats, the damage
formula they feed, the misfire ("ochame") mechanic, with every address, table dump, code
excerpt and measured data point. Written so a fresh session (or a human) can build on the
system without re-deriving anything. Clean-ROM SHA-1 `bc0e29ee383574443226695215496eb0d09aaa1c`;
file offset = SNES address & 0x3FFFFF (HiROM).

**Provenance.** Probe-verified on this exact game (2026-07-17/18 sessions; probe scripts
listed in §9). The stat *names* come from the vendor Super-S Lua (commented-out reads,
`vendor/sms-training-mode/SailorMoonS.lua:1650-55`); every *effect* below was measured
here. An earlier note ("ACS stats show no damage-time effect", patch-13 phase-1) was
**wrong** — that sweep was drowned by the damage variance; the identical-roll methodology
(§8) shows real effects and supersedes it.

---

## 1. The stat block

Six bytes per fighter inside the 0x80-byte player struct (P1 `$7E:1000`, P2 `$7E:1080`):

| Offset | P1 addr | P2 addr | Name (vendor) | Measured role |
|---|---|---|---|---|
| +0x70 | `$1070` | `$10F0` | buff_attack | owner's **NORMAL** damage boost |
| +0x71 | `$1071` | `$10F1` | buff_defense | reduces **ALL** damage the owner takes |
| +0x72 | `$1072` | `$10F2` | buff_health | no live effect; presumed load-time max-HP (unverified) |
| +0x73 | `$1073` | `$10F3` | buff_special | owner's **SPECIAL** damage boost |
| +0x74 | `$1074` | `$10F4` | buff_secret | **desperation** damage boost (verified — the desperation's strike component scales 3→5→6 at stat 0/3/7; cinematic drain ticks are NOT stat-scaled) |
| +0x75 | `$1075` | `$10F5` | buff_ochame | special-move **misfire chance** (§5) |

- All six are **0 in every normal mode** (VS, Practice, story vs-COM as observed) — 0 is
  the baseline, not "off". They are presumably populated by the A.C.S. customization
  screen (its menu location / mode value is still unmapped, §7).
- Useful working range is **0–7** for the damage stats (values >7 gave nonsense in
  sweeps — e.g. +0x73 at 15/255 produced *lower* damage than 7, consistent with the
  4-bit column arithmetic in §2 wrapping) and **0–5** for ochame (§5).
- Neighbors, not part of ACS: +0x48 `first_hit_defense` (loaded from the char manifest at
  `$E0:0238+id*2` by char-load `$C0:879B`; controlled retest pending), +0x76 (unknown),
  +0x77 action_strength.

## 2. The damage formula — the 16×16 matrix

Every strike/projectile/chip hit computes:

```
final_damage = MATRIX[ base_damage_class ][ (modifier + 8) & 15 ]
```

**Lookup code** `$C0:D055` (file 0xD055), entered with `$00` = signed modifier low byte,
`$02` = row (base damage class):

```
C0/D055  rep #$30
C0/D057  sta $02          ; row (base damage class)
C0/D059  lda $00
C0/D05B  and #$00FF
C0/D05E  clc / adc #$0008 ; signed modifier -> column: col = (mod + 8) & 15
C0/D062  and #$000F
C0/D065  sta $00
C0/D067  lda $02 / and #$00FF
C0/D06C  asl x4           ; row * 16
C0/D070  clc / adc $00    ; + column  -> index into the matrix
```

**The matrix** `$C0:D081` (file 0xD081) — **CORRECTION 2026-07-18: 1024 bytes, 64 rows
× 16 columns** (rows 16-63 continue the same shape, capping at 0x48=72; row 48 is the
shared single-hit desperation row — see `sms_damage_system.md` §3 for the live-read
proof and the extended dump). Rows 0-15 shown below; columns 0–15.
**Column 8 is neutral**; smaller columns = stronger (up to ~2× base at column 0), larger
= weaker (down to ~¼ base at column 15). One column ≈ ±12%:

```
row  0: 01 01 01 01 01 01 01 01 | 01 01 01 01 01 01 01 01
row  1: 02 02 02 02 02 02 02 01 | 01 01 01 01 01 01 01 01
row  2: 04 04 04 04 04 03 03 03 | 02 02 01 01 01 01 01 01
row  3: 06 06 06 06 06 05 05 04 | 03 02 02 02 02 02 01 01
row  4: 08 08 08 08 07 07 06 05 | 04 03 03 02 02 02 02 02
row  5: 0B 0A 0A 0A 09 09 08 07 | 05 04 03 03 03 03 02 02
row  6: 0D 0C 0C 0C 0B 0A 09 08 | 06 05 04 04 03 03 03 03
row  7: 0F 0E 0E 0E 0D 0C 0B 09 | 07 05 05 04 04 04 03 03
row  8: 11 10 10 10 0F 0E 0C 0A | 08 06 05 05 04 04 04 04
row  9: 13 12 12 12 11 0F 0E 0C | 09 07 06 05 05 05 04 04
row 10: 15 15 14 14 13 11 0F 0D | 0A 08 07 06 05 05 05 05
row 11: 17 17 16 15 14 13 11 0E | 0B 08 07 06 06 06 05 05
row 12: 19 19 18 17 16 14 12 10 | 0C 09 08 07 06 06 06 06
row 13: 1B 1B 1A 19 18 16 14 11 | 0D 0A 09 08 07 07 06 06
row 14: 1D 1D 1C 1B 1A 18 15 12 | 0E 0B 09 08 08 07 07 07
row 15: 20 1F 1E 1D 1C 1A 17 14 | 0F 0C 0A 09 08 08 07 07
```

The **modifier** mixes (mechanism inferred from measurements; exact combination code not
yet disassembled):
- a per-hit **RNG jitter** — the source of this game's damage variance (the same jab rolls
  1–6; the RNG byte is `$7E:0090`, frame-evolving, deterministic from reset with fixed
  input timing — which is why fixed-timing test suites see stable values);
- **stat shifts**: attacker's +0x70 (normal hits) or +0x73 (special hits) shift left
  (stronger); defender's +0x71 shifts right (weaker). Effects stack arithmetically in the
  column domain, and can never exceed the row's column-0 cap or column-15 floor.
- The lookup runs **once per landed hit**, immediately before the HP subtraction — the 8
  damage-apply sites (`docs/annotations.md` "patch 13 RE") consume its result via DP `$00`.

**Interaction with the taunt-nerf patch (13 v3):** patch 13 scales the *final* rolled
value at the apply sites, i.e. downstream of this whole computation — ACS boosts and the
Guts nerf compose multiplicatively.

## 3. Measured effects — the data

Identical-roll methodology (§8): each sample reloads the same savestate and lands the
same move at the same frame, so the RNG roll is identical and deltas are pure stat
effect. State `neptune_vs_jupiter.mss` (Neptune P1); jab base roll = **2**, 214LP
fireball base roll = **8**.

| Stat poked | 1 | 3 | 7 | Reading |
|---|---|---|---|---|
| attacker +0x70 (attack), jab | 3 | 3 | 4 | normals boosted, ~+1 column per ~3 stat |
| attacker +0x70, fireball | — | 8 | 8 | **no effect on specials** |
| defender +0x71 (defense), jab | 2 | 1 | 1 | normals reduced |
| defender +0x71, fireball | — | 5 | 4 | **specials reduced too — defense covers everything** |
| attacker +0x73 (special), jab | — | 2 | — | no effect on normals |
| attacker +0x73, fireball | 10 | 14 | 16 | specials boosted, ≈2× at 7 (row cap) |
| attacker +0x74 (secret), fireball | — | 8 | 8 | no effect on regular specials |
| defender +0x72 (health), jab | — | — | 2 | no live effect on damage taken |

(Historic single-shot sweeps with values 15/255 gave *smaller* damage than 7 — treat >7
as out-of-range, consistent with 4-bit column wrap.)

## 4. Where the stats are read (known code sites)

- **Ochame** +0x75: read at `$C1:0B69` (inside the special dispatcher, §5). The one
  ACS read with its full code path mapped.
- The damage-stat reads (+0x70/+0x71/+0x73) happen somewhere between the on-hit table
  dispatch and the `$D055` lookup — **not yet pinpointed** (find them by read-watching
  `$1070/$1071/$1073` during a hit; they will fire once per landed hit). The lookup
  itself and the apply sites are fully mapped. NOTE: the lookup routine EXECUTES from
  bank $80 ($80:D055; matrix read at $80:D07B) — exec-watch $80:D055, not $C0:D055.

## 5. The ochame / misfire system (fully reverse-engineered)

**Trigger point:** the special-move dispatcher `$C1:0B49` (file 0x10B49) runs for every
*recognized* special, X = fighter struct, Y = the special's 8-byte record (bank $C1,
accessed with DB=$C1 via phk/plb):

```
C1/0B49  rep #$30 ; phb ; phk ; plb
C1/0B4E  lda $0000,Y -> $00     ; record+0: attackID (also -> +0x44 attack class)
C1/0B53  lda $0002,Y -> $02
C1/0B58  lda $0004,Y -> $04
C1/0B5D  lda $0006,Y -> $06     ; record+6: THE MISFIRE ACT (0 = cannot misfire)
C1/0B62  and #$00FF ; beq $0B8F ; no misfire act -> skip roll
C1/0B67  lda $75,X  ; and #$00FF ; beq $0B8F   ; ochame 0 -> never
C1/0B6E  sta $0E
C1/0B70  lda $90 ; and #$000F ; tay            ; RNG byte $0090, low nibble
C1/0B76  lda $0AF5,Y ; and #$00FF              ; threshold table (below)
C1/0B7C  cmp $0E ; bpl $0B8F                   ; threshold >= ochame -> NO misfire
C1/0B80  lda $00 ; ora #$FF00 ; sta $00        ; mark the act word (misfire flag)
C1/0B87  lda $06 ; jsr $0224                   ; act = record+6  ($C1:0224 = sta $01,X / stz $02,X)
C1/0B8C  jsr $010E
```

**Threshold table** `$C1:0AF5` (16 bytes, indexed by `rand & 15`):
`00 01 02 02 03 03 04 04 FF FF FF FF FF FF FF FF`
Misfire iff `table[rand&15] < ochame` → effective ochame range **0–5**:

| ochame | 0 | 1 | 2 | 3 | 4 | ≥5 |
|---|---|---|---|---|---|---|
| misfire chance | 0% | 6.25% | 12.5% | 25% | 37.5% | **50% (hard cap — 8 slots are 0xFF)** |

**Special-move records** (8 bytes each, bank $C1; harvested by capturing Y at `$C1:0B49`):
`[+0 attackID, +1 variant (0=LP,1=HP), +2 ?, +3 ?, +4 ?, +5 ?, +6 misfire act, +7 strength-ish]`.
Known record addresses: Moon $C1:373E/3745 · Mercury $C1:4786/478D · Mars $C1:5851/5858/585F ·
Jupiter $C1:6AD0/6AD7 · Venus $C1:79BD/79C4/79CB/79D2 · Uranus $C1:8D6A/8D71 ·
Neptune $C1:9DF6/9DFD · Pluto $C1:AE33/AE3A · ChibiMoon $C1:BDF0/BDF7.

**Per-character misfire acts** (record+6; LP variant first — the full sets):

| cid | Character | Misfire acts | cid | Character | Misfire acts |
|---|---|---|---|---|---|
| 1 | Moon | 6A, 6B | 6 | Uranus | 65, 66 |
| 2 | Mercury | 65, 66 | 7 | Neptune | 66, 67 |
| 3 | Mars | 66, 67, 6C | 8 | Pluto | 62, 63 |
| 4 | Jupiter | 63, 64 (**both carry a real hitbox** — her fizzle zaps point-blank) | 9 | ChibiMoon | 63, 64 |
| 5 | Venus | 5F, 60, 65, 66 | | | |

All misfire animations chain `misfire-act → 0x2A (embarrassed) → neutral`, ~103–113
frames, no hitbox (except Jupiter's), fully vulnerable. Forcing one from a neutral,
grounded state via the standard act write (`+0x01=act, +0x02=1, +0x04=act, +0x06=0,
+0x07=0`) is proven safe — that IS patch 12's taunt.

**RNG byte `$7E:0090`:** evolves per frame, deterministic from power-on with fixed
inputs. Only consumer mapped so far: this misfire roll (low nibble) — the damage-modifier
jitter (§2) presumably also draws from it or its neighbors `$0090-$0098` (a visible
LFSR-ish cluster in round-transition diffs).

## 6. Manipulating the system from patches / Lua

- **Poke timing:** all six stats are plain WRAM bytes, safe to write any time (NMI-side
  hooks like the patch-11/12/13 joy_read chain, Lua endFrame, anywhere). Effects are
  consumed per-event: damage stats at each landed hit, ochame at each special input.
- **Boost-only:** 0 is the floor for every stat — you can strengthen an owner or make
  them clumsy, but you cannot push a stat's effect below the game's baseline. (A
  *reduction* mechanic must either raise the victim's opposing stat — e.g. defense — or
  hook the damage-apply sites like patch 13 v3.)
- **Persistence:** struct bytes survive within a match; round transitions re-init the
  structs (both fighters' HP→max and acts→0 on the same frame — the round signature), so
  per-round mechanics must re-apply or track levels externally (patch 13 keeps levels in
  `$7F:F800` and writes effects per-event instead).
- **Mode caveats:** mode 4 (Practice, DAMAGE off) skips only the HP subtraction — the
  matrix lookup still runs but its result is discarded; ochame misfires still occur.
  Desperation moves are additionally hard-skipped in mode 4 and gated on HP ≤ 0x18
  elsewhere (Training+ has a P1 HP FULL/LOW row for this).
- **Known-good building blocks:** patch 12 (`tools/mkpatch12.py`) exports the MISFIRE
  act table; patch 13 (`tools/mkpatch13.py`) has the grant FSM (taunt-completion →
  levels in `$7F:F800`), the per-round reset, the corner-digit indicator, and JSL thunks
  at every damage-apply site — all reusable payload-agnostically.

## 6b. Desperation compendium (all 9 characters, probe-measured)

Motions courtesy of the maintainer (numpad, HP=X button, HK=A button); trigger for the
gated ones: performer HP <= 0x18 (25%) — poke struct hp AND display `$0800` (the <10 s
clock alternative is untested). Measured on the clean ROM, defender at 0x60 HP, standing,
fixed input timing (single roll; Uranus re-rolled at a second timing: identical).
Probe: `tools/probe_p13f_desp.lua` (side-aware motion driver, per-write path
classification, act/a44-at-write logging). "Covered" = scaled by Guts (patch 13 v3.2).

| Char (motion) | Type | Acts (+0x44 at hit) | Dmg stand | Dmg crouch | Paths | HP-gated | Covered |
|---|---|---|---|---|---|---|---|
| Moon 2363214HK | projectile, 1 hit | 6D-70 | **48** | **48** | PROJ ×1 | yes | yes (proj) |
| Mercury 632146HK | strike, 1 hit | …6F (0x12) | **48** | **62** | MELEE ×1 | yes | yes (class) |
| Mars 6321412HK | projectile, 1 hit | 74-75 | **32** | **32** | PROJ ×1 | yes | yes (proj) |
| Jupiter 2141236HP | **strike**, 1 hit | 72-74 (0x14) | **48** | **62** | MELEE ×1 | yes | yes (class) |
| Venus 4123632HP | strike, 1 hit | 69 (0x12) | **37** | **48** | MELEE ×1 | yes | yes (class) |
| Uranus 632141236HK | **rush→grab hybrid** | 71-79 (0x18) | **67** | **51** | MELEE ×18 (35) + TOSS 32 | yes | yes (class + toss v3.2) |
| Neptune **6236236HP** | strike, 1 hit | 70-73 (0x12) | **37** | **37** | MELEE ×1 | yes | yes (class) |
| Pluto 632146HP | **cinematic drain grab** | 6A-6C (0x18) | **48** | **49** | MELEE 3 + TICK ×12 (45, finisher 11) | yes | yes (tick v3.1) |
| Chibi j.63214HP | air projectile barrage | 6B-6D | **52** | **24** | PROJ ×7 (6-8 each) | yes | yes (proj) |

**Punish/counter-hit damage** (see `sms_damage_system.md` §6 for the full system):
landing a desperation on an opponent inside their own move's act gives +50-68% on the
matrix-passing hits — Moon/Mercury/Jupiter 48→72, Mars 32→48, Venus/Neptune 37→62;
multi-hit desperations gain almost nothing (first hit only: Pluto 48→50, Chibi 52→54,
Uranus 67→67 — his 1-damage rush opener sits at the row floor).

**Posture, not hitbox, selects the damage** (one roll per cell, same rig). The
crouch-vs-stand differences come from the defender's POSTURE STATE at impact picking a
different per-move on-hit table (`$C0:CDD5` + variants `CE15…D015`), NOT from which
hurtbox (body vs head) the attack touches. Evidence:

- Single-hit STRIKES deal *more* vs crouchers (Mercury/Jupiter 48→62, Venus 37→48,
  Pluto's opener 3→4; Neptune's 37 unchanged — per-move table values, not a multiplier).
- **Head-box test refuted**: Moon's desperation projectile poked to fly at forehead
  height (sy = dy−52) vs torso (default, 64px up) vs shins (dy−6) of a STANDING
  defender — 48 damage at every contact height.
- If the crouch bump were "the head box moved into the attack path", Uranus's 18 rush
  hits would also get it vs crouchers; instead their per-hit values are identical
  stand-vs-crouch (only the hit COUNT drops, 18→10).
- AIR hits use the stand-class value: Mercury and Jupiter connecting on a rising
  defender (24-33px up) still deal 48; at full jump apex Jupiter just whiffs.
- **Prejump counts as crouching**: Venus's strike on a defender in jump squat (act 0x05)
  deals 48 — her crouch value, not her stand 37.
- Projectiles are posture-blind per-hit (Moon 48 everywhere, Mars 32); multi-hit moves
  LOSE hits to the shorter crouching hurtbox (Uranus 18→10 = 67→51; Chibi 7→4 = 52→24);
  Pluto's drain ticks are posture-independent (45 either way).
- Bonus: **Venus's desperation has an anti-air component** — vs a defender 64px
  airborne it connects through the PROJECTILE apply path (act 0x6A instead of the
  grounded 0x69 melee hit) for the same 37.

Per-character notes:

- **Uranus (the user's question: grab or strike?): both.** Acts 72-75 are an ~18-hit
  autocombo rush (1-2 damage each, one 10-damage launcher near the end), then act 76
  connects the grab (victim act 0x1C), acts 77-79 the cinematic, and act 0x71 applies a
  **32-damage TOSS through the throw path `$C1:082F`** — the only desperation using it.
  All hits carry +0x44 = 0x18 including the toss.
  - **vs crouching**: per-hit damage is UNCHANGED; the total drops 67→51 because only
    ~10 of the 18 rush hits connect on the shorter crouching hurtbox (toss still 32).
    So "no body/head damage difference" is right — posture changes hit COUNT, not values.
  - Damage is roll-stable: two RNG timings both gave 67 with identical per-hit values.
  - A field reading of "~34" is consistent with the rush whiffing (range/character
    hurtbox) and essentially only the 32-toss + a stray hit or two connecting.
- **Jupiter (the user's other question): pure strike** — one 48-damage melee hit,
  class 0x14, no grab state at any point.
- **Neptune — resolved (corrected input 6236236HP)**: the first sweep used 236236HP,
  which is her regular ungated super (chain 69→6F, 2 hits, 19 damage, classes
  0x08/0x0C, identical at full HP). With the maintainer's corrected **6236236** input
  her real desperation appears: acts 70-73, class 0x12, single 37-damage strike,
  properly HP-gated (full-HP control gives a normal instead: acts 42/43, 7 damage).
- **Motion-overlap pitfall** (cost us two wrong classifications): Moon's and Neptune's
  motions end in a direction; pressing the button with that direction held at close
  range triggers the NORMAL THROW instead (Moon act 5C, Neptune acts 5D-5F, toss 20,
  +0x44 = 0 at toss — the a44=0 signature is how normal-throw tosses stay exempt from
  Guts). Press the button on neutral (motion stays buffered) to get the real move.
- Full-HP control runs for all 8 gated characters produced only small stray normal hits
  (8-12) or whiffs — none of the desperation act chains appear above 25% HP.

## 7. Open unknowns (probe before relying on)

1. **Where/how the ACS screen sets the stats** — the customization UI's menu entry, mode
   value, and its point budget are unmapped (title menu: Story/1Pvs2P/1PvsCom/Tournament/
   Practice/Options — probably inside 1PvsCom or Tournament setup).
2. ~~+0x74 buff_secret~~ — **RESOLVED**: boosts desperation damage (strike component
   only). Desperation motions provided by the maintainer (numpad, HP=X HK=A):
   Moon 2363214HK · Mercury 632146HK · Mars 6321412HK · Jupiter 2141236HP ·
   Venus 4123632HP · Uranus 632141236HK · Neptune 6236236HP · Pluto 632146HP ·
   Chibi j.63214HP. Gate: performer HP ≤ 0x18 **or <10 s on the clock** (per the
   maintainer; the HP path is verified — poke struct hp AND display `$0800`).
   **Desperation anatomy (Pluto traced end-to-end):** attack-class +0x44 = 0x18
   (≥0x12 ✓); a *cinematic grab*: initial strike hit through the normal apply sites,
   then victim act 0x1C (HELD) drained 3-4 HP per ~12 frames through the hold-throw
   tick site `$C1:0D54-0D6F` (write ≈ $C1:0D61; per-tick damage in DP $05, mode-4
   gated, hp-underflow death path at $C1:0D63) — ~48 of ~51 total damage is drain.
   Patch 13 v3.1 hooks the tick site with a holder-class ≥0x12 gate (normal
   Moon/Mars/Chibi hold-throws pass through untouched, verified byte-identical).
   **All 9 desperations are now typed and measured — see §6b** (incl. stand-vs-crouch
   damage). Remaining sub-question: the <10 s clock trigger path is untested for everyone.
3. **+0x72 buff_health** — needs testing at character load, not mid-match.
4. **+0x76** — unknown byte between secret/ochame block and action_strength.
5. **The exact modifier-composition code** (where RNG + stats merge into `$00` before
   `$C0:D055`) and the damage-stat read PCs (§4).
6. **+0x48 first_hit_defense** — retest with the controlled methodology.

## 8. Methodology (reuse this)

**Identical-roll sampling:** the damage variance is deterministic from reset given fixed
input timing. To isolate a variable: reload the same savestate per sample, poke the
variable, land the same move at the same frame counter — the matrix roll is identical, so
any damage delta is the variable's effect. Naive sweeps without reloads (different frames
= different rolls) produce noise that can hide effects entirely — this is exactly the
error that produced the earlier wrong "stats are inert" conclusion.

## 9. Tooling index

- `tools/probe_p13d_stats.lua` (+`_cfg`) — the controlled stat sweeper (MEASURES list).
- `tools/probe_p13b_acs.lua` — the first (uncontrolled) specials sweep; superseded.
- `tools/probe_p12_ochame.lua` — live misfire-rate demo (poke ochame, watch whiffs).
- `tools/probe_p12_rec.lua` — special-record harvester (captures Y at `$C1:0B49`).
- `tools/probe_p12_acts.lua` — misfire-act auditor (forces acts, verifies recovery).
- `tools/probe_p13b_class.lua` — attack-class (+0x44) census at the damage-apply sites.
- Related docs: `docs/sms_engine_internals.md` §6 (damage path) & §10 (Practice mode);
  `docs/annotations.md` ("patch 12 RE", "patch 13 RE", "A.C.S. stat system" sections);
  `docs/patch_notes.md` patches 12–13.
