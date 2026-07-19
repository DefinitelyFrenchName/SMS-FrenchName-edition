# Special moves — per-character compendium

**What this is.** The specials companion to the desperation compendium
(`sms_acs_system.md` §6b-6d): per character, every special's input, damage paths,
posture/chip values, and patch coverage — measured with the same rig
(`tools/probe_p13f_desp.lua`, single-roll deterministic, clean ROM, defender at 0x60 HP).
Move names and inputs from the maintainer / Dustloop community wiki
(https://www.dustloop.com/w/SMS — Cloudflare-blocked for our fetcher; values below are
our own measurements).

**Structural ground truth** (see annotations "Special-move record tables"): each
character's dispatcher moves live in a bank-$C1 record table (7-byte records;
record+0 = global index). Button-PAIRED records with misfire acts = the misfire-capable
specials; **single-variant records with misfire 00 = the character's DESPERATION**
(verified live: Mars's "mystery" record 0x11 is Snake Flare, Moon's 0x0C and Venus's
0x16 fire on their desperations — dispatched from the act-machine via the
`lda #act / jsr $04DA / ldy #rec / jsr $0B49` template, e.g. Mars @C1:583C).
Command grabs (360s), DPs, charge-kicks and some rushing strikes fire NO record.
Dispatcher-special counts: Moon 2, Mercury 2, Mars 2, Jupiter 2, Venus 2, Uranus 1,
Neptune 1, Pluto 1, Chibi 1 — plus in-table desperation records for Moon/Mars/Venus/
Chibi (the other five characters' desperation records are not in the walked windows;
their location is open).

Status: **ALL NINE CHARACTERS COMPLETE** (Chibi drafted from wiki + measurements ahead of the maintainer's detail pass — corrections welcome).

---

## Uranus (charID 6)

### World Shaking — 632LP / 632HP (record idx 0x17)

| Variant | Acts | Type | Damage (stand) | vs crouch | Chip | Notes |
|---|---|---|---|---|---|---|
| LP (632+LP) | 61 → 63 | projectile, 1 hit | **9** | 9 | **2** | wave speed ≈3.3 px/f |
| HP (632+HP) | 62 → 64 | projectile, 1 hit | **11** | 11 | **2** | stronger, faster wave (≈4.5 px/f), longer commitment |

**Frame data** (ours measured from act start in 60Hz frames; Dustloop convention ≈ ours+2):

| Variant | Startup (proj spawn) | Attacker total | Post-spawn recovery | On hit | On block (wiki) | Counter dmg (wiki) |
|---|---|---|---|---|---|---|
| LP | 13 (wiki 15) | 50 | 37 (wiki 36) | **+6** (defender stun 36f) | +1 | 18 |
| HP | 17 (wiki 19) | 69 | 52 (wiki 51) | **−10** (stun 34f, long recovery) | −14~ | 21 |

The HP version trades frame safety for damage and wave speed — it is MINUS on hit at
close range (recovery outlasts the hitstun); LP is the safe poke version.

- Posture-blind per-hit (projectile path), like all projectiles measured so far.
- **Guard: Mid/any (verified)** — despite crawling along the ground, it is blocked
  successfully by BOTH standing (chip 2, blockstun 0x0C) and crouching guard (chip 2,
  0x0D); it does reach and hit crouching opponents (9). The "must crouch-block" folk
  memory does not reproduce; wiki "Mid" agrees with the emulator.
- Damage rolls with the normal matrix variance (the maintainer has seen 8s; we logged
  9/11 at this rig's fixed frames — same move, different columns).
- Misfire acts 65 (LP) / 66 (HP) — these are also patch 12's taunt acts for Uranus.
- Guts (patch 13) scales it via the projectile sites: verified family behavior
  (projectile hooks are unconditional).

### Diving Gaia Crash (SPD) — 6248LK / 6248HK (360 recognizer, not in the record table)

| Variant | Acts | Type | Damage | Range (wiki) | Guts Grip L3 |
|---|---|---|---|---|---|
| LK | 67/69 → 6B/6D/6F → **toss act 71** | command grab, single toss | **24** | 56px | **10** |
| HK | 68/6A → 6C/6E/70 → **toss act 71** | command grab, single toss | **32** | 48px | **13** |

**Frame data** (measured): grab connects **1-2 frames after act start** — effectively
instant. Whiff recovery: LK **31f**, HK **35f** total animation (the punishable window).
Full cinematic on hit: LK ~107f, HK ~159f; both leave the victim knocked down for
**~+55 frames of okizeme** after the attacker recovers. Not techable (wiki agrees).
LK trades 8 damage for 8px more range and 4f less whiff recovery.

- Input recognition (§6c of the ACS doc): all four cardinals in any order within
  ~16-20f, LAST direction must be up, button may come on neutral (buffered). The
  canonical 6321478 works because it contains 6-2-4-8; diagonals are never required.
- True command grab: unblockable, applies through the throw-toss site `$C1:082F` with
  holder class 0 — immune to ACS defense and to patch 13's class gate; covered by
  **patch 14 (Guts Grip)** via the shared toss act 0x71 (both variants converge on it,
  so one gate entry covers LK and HK — verified 24→10 and 32→13 at L3).
- The toss act 0x71 is also the finisher of her desperation (which arrives there at
  class 0x18 and is scaled by patch 13 instead — the class byte disambiguates).

### Shadow Dash — 66 (forward dash; structurally a special move)

The maintainer's framing is confirmed by the act map: the forward dash runs on act
**0x60**, inside Uranus's character-specific special-act space (her specials/misfire/
desperation acts occupy 0x61-0x79), while the BACK dash uses the universal act 0x26.
Her "dash" really is a per-character special move that happens to be motion 66.

| | Act | Duration | Distance | Speed | Hurtbox | Skid |
|---|---|---|---|---|---|---|
| Shadow Dash 66 | **0x60** | 14f | ~149px gross / ~143 net | ~10.6 px/f | idx 0x4F (present — NOT invulnerable) | +5f (act 09), 19f total commitment |
| Back dash 44 | 0x26 (universal) | 14f | −36px | ~2.6 px/f | **idx 0x00 all 14 frames = fully INVULNERABLE** | +5f (act 09) |

- The back-dash full invulnerability is the long-documented patch-2/patch-6 fact,
  now trace-confirmed frame-by-frame (hurt idx 0 throughout).
- Shadow Dash is the cancel target of the 2HP infinite — the whole reason this project
  exists. Patch 1 gates the 2HP-recovery→dash cancel; patch 5 shortens the dash to
  ~89px (−1/3); patch 6 optionally adds dash i-frames. See docs/patch_notes.md.
- Wiki lists dash startup 1 — consistent (movement begins on the first act frames).

### 2HK — sliding sweep (command normal, character-specific slide)

| Act | Startup | Active | Slide | Damage | Guard | On hit | Recovery |
|---|---|---|---|---|---|---|---|
| **0x59** | 8f (matches wiki) | **~38f** (wiki says 30 — gap) | **+67-79px** forward | rolls 8 (wiki 10 — same matrix row) | Low | **knockdown** (dact 19→1E→wakeup) | ~19f after actives (wiki 14) |

- During the slide her hurtbox switches to idx **0x39** (low-profile posture box) and
  the hitbox is idx 0x0F for the whole slide — one long active window that travels.
  It connected from 120px starting range in our rig; treat it as a mid-range
  knockdown tool, minus on block (wiki −21~+0 depending on distance).

### Related (documented elsewhere)
- **Desperation "Destructive Carnival"** (632141236HK, rush→grab hybrid, 67/51, lows
  in the rush): `sms_acs_system.md` §6b-6d. Wiki lists damage 67 (exact match) and
  chip 1xN (matches), but guard "Mid" — our crouch-vs-stand block results (11 no-grab
  vs 66+grab) contradict that; see the gap list below.
- **Throws** (wiki cross-check): 4/6HK = the hold-throw, 22, not techable — matches our
  tick-path measurement exactly; 4/6HP = a 24-damage TECHABLE toss (+28 on tech). So
  Uranus has TWO normal throws; our earlier "her throw is hold-type" covered the HK one.

### Wiki cross-check (Dustloop SMS/Uranus/Frame_Data; fetched 2026-07-19)

Strong agreement — several columns independently validate the engine model:

- **Diving Gaia Crash 24/32 and Destructive Carnival 67: exact matches.**
- The wiki's paired `damage | faceHit` columns are our two matrix ROLLS (f.HP "8|10" =
  our far-5HP rolls 8/10), and `counterHit | counterFaceHit` are those rolls countered
  (f.HP "12|14" = our counter-hit measurements 12/14) — the wiki's counter values are
  exactly our **−2 matrix columns**, move by move (WS 12→18, 14→21 fit the same rows).
- Wiki `c.HP` vs `f.HP` = our proximity-normal discovery (near act 0x45 9/12,
  far 0x43 8/10).
- Startup/recovery figures match ours at a constant +2 convention offset (they count
  from input inclusive; we count from act start).

Gaps found (emulation trusted):
0. **2HK active frames: we measure ~38 (t=22→59), wiki lists 30**; and its listed
   damage 10 vs our rolled 8 (same row, different columns).
1. **World Shaking listed damage 12/14 vs our rolled 9/11** — not a contradiction but a
   sampling difference: the value is a matrix roll; the wiki apparently lists a high
   roll, we log the roll at our fixed frame. Range, not a single number.
2. **Destructive Carnival guard "Mid"** — our measurements say standing block COLLAPSES
   mid-rush (66 + the grab lands) while crouch-block neutralizes it (11, no grab): at
   minimum some rush hits are lows, so "Mid" is wrong or incomplete on the wiki.
3. Wiki lists WS chip 3 vs our 2 — chip rolls too (both ≈ hit/4 of adjacent columns).

## Neptune (charID 7)

### Deep Submerge — 214LP / 214HP (record idx 0x18; the patch-9 projectile)

| Variant | Acts | Damage | vs crouch | Chip | Startup (spawn) | Recovery (wiki) | On block (wiki) |
|---|---|---|---|---|---|---|---|
| LP | 62 → 64 | **8** | 8 | 1 | ~10f (wiki 12) | 36 | ~+1 |
| HP | 63 → 65 | **10** | 10 | 1 | ~13f (wiki 16) | 51 | −14~ |

- **Wiki damage matches exactly (8/10)** — the same safe-LP/committal-HP fireball
  template as Uranus's World Shaking. Chip rolled 1 in our rig (wiki 2 — adjacent
  columns). Misfire acts 66/67 (= her patch-12 taunt).
- **Descending arc, but Mid at every range (verified)**: contact height measured −62px
  at 40 range falling to −30px at 110 — yet standing block, crouch block, and crouching
  contact all behave normally at max range (chip 1 / chip 1 / hit 8). The arc changes
  where it touches, never the guard requirement — and the 32px contact-height swing
  with identical damage is another proof that contact zone doesn't affect damage.
- This is patch 9's object 0x18 (hitbox-tracks-sprite fix).

### Splash Edge — 623LP / 623HP (DP; separate recognizer — NOT in the record table)

| Variant | Acts | Startup | Hits | Damage | Chip | On block (wiki) |
|---|---|---|---|---|---|---|
| LP | 68 | **3f** (= wiki) | 1 | **9** (wiki row 12/10) | 2 | −4 /D |
| HP | 69 → 6B | **4f** (= wiki) | 2 | **11+8 = 19** (wiki 14+8) | 2+2 | −22 /D |

- **Fully INVULNERABLE from frame 1 through the first active window** (hurtbox idx 0x00
  in the trace) — a true reversal DP. The wiki does not list this; our addition.
  The HP version's rising second phase (act 0x6B, hitbox 0x0D) is vulnerable (hurt 0x3C).
- Like the SPDs and desperations, the DP does NOT go through the $C1:0B49 special
  dispatcher (no record fires) — which is why Neptune's record table has only Deep
  Submerge, and why the earlier "236236 super" was really a sloppy-input Splash Edge HP
  (236236 contains 623; that misidentification is now resolved everywhere).

### Neck Throw — 4/6HP, ground AND air (techable)

- Ground: acts 5D-5F, toss **20**, techable (wiki: +16 on tech). **Air version verified
  identical**: three different air-to-air timings all produced the same acts and the
  same 20 — confirming the community claim (wiki lists j.4/6HP as an identical row).
- Neptune has only ONE throw (the maintainer's belief, wiki-confirmed) — unlike
  Uranus's HK-hold + HP-toss pair.

### c.HK — two hits, second is an OVERHEAD (confirmed)

| Hit | Act | Startup | Damage | Guard |
|---|---|---|---|---|
| 1 | 4A (hitbox 0x05) | 9f from act start | rolls 6 (wiki 8) | Mid |
| 2 | 4B (hitbox 0x18) | +29f | **10** | **High (overhead)** |

Empirical proof: vs a crouch-blocking defender, hit 1 is blocked for 0 chip (crouch-
blockstun act 0x0D) and **hit 2 connects clean for 13** — exactly the wiki's faceHit
value, revealing that column as the vs-crouch posture value. vs standing block both
hits are blocked (0 chip — normals don't chip). Tested vs Jupiter; the "on all
characters" claim is plausible (act/box driven) but not yet swept per-character.

### Dragon Rise (desperation) — wiki gaps

Our deterministic measurement: **single hit 37** (row 48 col 9, jitter-exempt) at every
range tested (25/35/40/60), chip **9** single. Wiki lists 48 damage / chip 12×2 — 48,
62 (faceHit) and 72 (counter) are the adjacent row-48 columns c8/c7/cap, so the damage
disagreement is column sampling again, but the second chip instance never reproduced in
our rig. Emulation trusted; flagged.

## Jupiter (charID 4)

### Supreme Thunder — [4]6LP / [4]6HP (charge; record idx 0x12)

| Variant | Acts | Damage | Chip (wiki) | Startup (wiki) | Recovery (wiki) | On block (wiki) |
|---|---|---|---|---|---|---|
| LP | 61 | **13** (wiki 10/13) | 2 | 13 | 31 | +6~ /D |
| HP | 62 | **16** (wiki 12/16) | 3 | 16 | 41 | −4~ /D |

- A sonic-boom **charge** input: hold back ~25-39 frames (24f charge fails, 39f works
  in our rig), then 6+P. The strongest plain fireball measured so far (13/16 vs
  Neptune's 8/10) and it KNOCKS DOWN (wiki /D). Our deterministic rolls equal the
  wiki's faceHit column; same matrix rows.
- **Hits high — CROUCHING AVOIDS IT COMPLETELY** (maintainer's read, verified): the
  boom flies at −68px and whiffed a crouching Venus outright (no block needed). The
  patch-7 crouch-hurtbox survey tops out at −60 (Mars), so it geometrically clears
  ALL nine crouchers. A pure anti-standing/anti-jump tool.
- Misfire acts 63/64 (= her patch-12 taunt).

### Coconut Cyclone — j.632LP / j.632HP (air fireball; record idx 0x13)

- The maintainer's description is exactly right and trace-confirmed: the falling
  fireball has **no hitbox in flight** — the hit registers only at GROUND IMPACT
  (our hit log: contact at floor height ~140px out for HP; whiffs at 30-100px).
- Measured HP: **12** (wiki 10/12 LP/HP). Wiki: startup 16/19, actives 24/40, chip
  2×3 / 3×5, and enormous advantage (+34~+59 on block) — a delayed-oki zoning tool.
- Misfire acts 69/6A.

### Giant Swing — 6248LP / 6248HP (360 command grab; not in the record table)

| Variant | Carry act | Ticks | Damage | Range (wiki) | Guts Grip L3 |
|---|---|---|---|---|---|
| LP | **0x6F** | 4×6 | **24** | 64px | **8** (v0.19 fix) |
| HP | **0x70** | 5×6 | **30** | 56px | 10 |

- Wiki damage matches exactly (24/30); unblockable, untechable, airborne carry
  (victim held 72px up) draining through the tick site at holder class 0.
- **Patch-14 gap found here and fixed in v0.19**: the LP version's carry act 0x6F was
  not in GRAB_ACTS (only HP's 0x70) — LP Giant Swing escaped Guts Grip. Both acts are
  now gated (verified 24→8, 30→10 at L3). LP trades 6 damage for 8px more range.

### Double Axel — 236LK / 236HK (lariat; separate recognizer, no record)

| Variant | Act | Startup | Hits (ours) | Damage/hit | Wiki actives |
|---|---|---|---|---|---|
| LK | 0x6B | **3f** (= wiki) | 2 connected | 5 (wiki 4/5) | 2×13 cycles |
| HK | 0x6C | **5f** (= wiki) | 1 connected | 16 (wiki 12/16) | 4×13 cycles |

- **Steerable — the maintainer was right**: neutral spin is stationary, but HOLDING
  forward or back drifts her ~±1.5 px/f for the whole spin (verified both directions;
  the earlier "stationary" note was a rig artifact — the stick had been released).
  A walking lariat in the Zangief tradition after all.
- **Half-body invincibility — confirmed with geometry**: the spin swaps to dedicated
  hurtboxes (idx 0x44-0x48) whose tops sit at **−34px**, vs −76px standing — the head
  and upper torso are invulnerable for the whole spin. Every fireball flight height
  we've measured (−40 to −64px) passes clean over it: it is a fireball-dodging lariat.
- Wiki: LK is PLUS on block (+1~+23); HK −25~+7 with knockdown; chip 1×13 / 3×13.

### Power Bomb — c.4/6HP throw (ground and, per wiki, air)

- Ground: grab → toss **28** (act 5E), techable, +23 on tech — wiki-exact.
- Air version: wiki lists j.4/6HP as an identical row (28, techable). Our rig produced
  j.HP instead at three air timings — air-throw adjacency is finicky; taken on
  wiki+maintainer authority, unverified locally.

### Lightning Strike (desperation) — cross-check

Ours: single strike 48 (wiki 48 ✓ exact), blocked = 3 hits × 12 chip — **the wiki's
"12×3" chip matches our block measurement exactly** (a rare full convergence on the
multi-hit-on-block phenomenon). Wiki startup 37, −17/D on block.

## Pluto (charID 8)

### Dead Scream — 41236LP / 41236HP (record idx 0x19)

| Variant | Act | Behavior | Damage | Chip (wiki) | Wiki startup/active/recovery |
|---|---|---|---|---|---|
| LP | 60 | traveling ground-level fireball (slot id 0x19) | **12** (wiki exact) | 3 | 15 / 26 / 36 |
| HP | 61 | **STATIC fireball ~80px in front** | **14** (wiki exact) | 3×3 | 21 / **53** / **82** |

- The maintainer's description confirmed in full: HP materializes at a fixed spot ~80px
  ahead and SITS there (slot alive 50f+ in the trace; wiki actives 53) — and therefore
  **whiffs point-blank** (no contact at ≤22px). Huge recovery (82) — a placed zoning
  tool, not a poke. Multi-chips on block (3×3), hard knockdown per wiki.
- **LP also whiffs point-blank** (verified at 22px — same spawn offset) and per wiki
  prose stops just before fullscreen. Never guard-cancel with it up close.
- Misfire acts 62/63 (= her patch-12 taunt).

### Strict Sweep — [4]6LK / [4]6HK (charge; TRUE OVERHEAD, forward-moving, low-invulnerable)

| Variant | Acts | Startup (wiki) | Hits | Damage | vs crouch-guard |
|---|---|---|---|---|---|
| LK | 65→66 | 23 | 2 (13+10 ours; wiki 10*10) | 23 | **hits through (10)** |
| HK | 65→67 | 32 | 2 (wiki 12*12; our lone 16 = spacing) | 16-24 | **hits through (16)** |

- **Overhead confirmed on both strengths** (crouch-blocking defenders take the full
  hit; wiki guard "High" agrees).
- **Moves forward ~138px** across the move (position traced) — a charge-released
  advancing flip kick.
- **Half-body invulnerability = the LOWER half** (opposite of Jupiter's lariat): during
  the active flip her hurtboxes span only −113..−71px (airborne body), so sweeps and
  lows whiff clean underneath. Startup boxes are normal-sized. Wiki prose gives the
  windows: LK 7~28F, HK 24~42F, and notes the HK clears low fireballs (consistent with
  our geometry) — community nickname "Pole Vault".
- Misfire: none observed live (charge specials share the record?) — its acts 65-67 sit
  outside the dispatcher path like other charge/DP moves... (records only cover Dead
  Scream; Strict Sweep fires no REC — same non-dispatcher family as DPs/360s.)

### Throw — c.4/6HK (her only throw; HOLD-type)

- **Hold-throw**: 5 drain ticks × 4 = **20** in our rig (wiki 22 — tick-roll variance),
  act 0x5C, untechable (hold-throws always are), +28 oki per wiki. Pluto joins
  Moon/Mars/Chibi/Uranus-HK in the hold-thrower club.

### c.HP — the "sometimes-overhead" (patch 7's target), now fully decoded

Wiki lists it as guard **High**, 11 damage (our 14 = their faceHit column). The
per-posture matrix vs the cast is richer than a plain overhead:

| Defender state | Result |
|---|---|
| standing block | **blocked** (0 chip) |
| plain crouch (Moon, tall croucher) | **hit 14** |
| crouch-BLOCK Moon | **total whiff** — the crouch-guard pose uses a LOWER hurtbox than plain crouch |
| crouch-BLOCK Mars (tallest crouch) | **full hit 14 — true overhead** |
| short crouchers (Mercury/Jupiter/Venus/Chibi) | whiffs entirely (patch-7 geometry: box bottom −55 vs crouch tops) |

So "overhead on some of the cast, whiffs on others" is exactly right, with the extra
twist that guard pose vs plain crouch matters per character. **Patch 7** extends the
active box downward (h 54→62) to make it hit every croucher except Chibi.
Wiki-prose gap: their list of crouchers it hits (Mars/Pluto/Neptune/Uranus) omits
Moon — we hit plain-crouching Moon for 14 live, and the patch-7 box survey agrees.

### Backdash (44) — per-character stats confirmed

Act 0x26 like everyone, but **20 frames fully invulnerable** (hurt idx 0 from t+1
through the dash; wiki "1~20F strike/projectile/throw invulnerable" matches exactly) vs
Uranus's 14f — backdash invuln IS per-character. Travel 37px + 5f skid. (Wiki "Move
Distance: 100" is in unknown units; our 37 game-pixels is the trace value.) Wiki prose
also claims normals cancel into backdash (lights ~−6F, heavies ~+6F) — untested here.

### Related
- **Desperation "Dimension Dance"** (632146HP): `sms_acs_system.md` §6b-6d — the
  blockable strike-throw (1 chip, no grab on block; wiki chip 1 matches). Wiki adds
  +15~+20 on block, and its "cannot chip kill" is now mechanically explained: chip
  floors at 1, and the engine's death rule is UNDERFLOW (hp 0 = alive), so a 1-chip
  move can only ever park a ≥1-HP defender at 0 — see sms_damage_system.md §2.
  Wiki prose bonus: it whiffs on crouching Chibi AND Venus, giving Pluto a
  character-specific infinite (c.LP c.LP HP > desperation) — this game's OTHER
  documented infinite, cousin to the Uranus one this project began with.

## Mars (charID 3)

### Fire Soul Bird — 41236LP / 41236HP (record idx 0x0F)

| Variant | Act | Damage | Chip | Wiki startup/recovery |
|---|---|---|---|---|
| LP | 64 | **10** (wiki 8/10) | 2 | 10 / 36 |
| HP | 65 | **13** (wiki 10/13) | 2 | 14 / 51 |

- The upward-arc fireball: contact measured at **−65px** height at 70px range (it caught
  a STANDING defender's head zone on the way up) — an anti-air-capable trajectory, LP/HP
  arcs differing per the maintainer. Knocks down (wiki /D). Misfire acts 66/67
  (= her patch-12 taunt).

### Snake Fire — 41236LK / 41236HK (record idx 0x10)

| Variant | Act | Damage | Chip (wiki) | Wiki startup/recovery |
|---|---|---|---|---|
| LK | 6A | **10** (wiki exact) | 2 | 11 / 31 |
| HK | 6B | **12** (wiki exact) | 3 | 13 / 50 |

- Ground-level fireball (contact at floor height), **hard knockdown** as the maintainer
  said (wiki /D). Misfire acts 6C/6D. A punch/kick fireball PAIR on the same motion —
  unique so far (41236P = arc, 41236K = ground).

### Fire Heel Drop — 214LK / 214HK (no dispatcher record)

| Variant | Acts | Hits | Damage | Chip on block |
|---|---|---|---|---|
| LK | 70→72 | 2 | **8+12 = 20** (wiki exact) | 2+3 |
| HK | 71→73 | up to 2 (wiki 14, 16 2nd) | ours 18 single (= wiki faceHit) | **3+4 = 7** (wiki exact) |

- Forward-traveling flip kick, **hard knockdown** — but **NOT an overhead**: both
  standing and crouching guard block it (7 chip either way; wiki guard "Mid" agrees —
  the maintainer's overhead hunch is refuted by both sources). It double-hits on block
  (1→2 hits, the familiar phenomenon).
- Fires no dispatcher record (the DP/360/charge-family recognizer).
- Class bytes climb to 0x10 on the HK — highest non-desperation melee class seen.

### Throws — two, one of each type

| Throw | Type | Damage | Techable | Air |
|---|---|---|---|---|
| **Hundred-Slap Fury** c.4/6HP | HOLD (12 ticks × 2) | **24** (wiki exact) | No | ground only |
| **Frankensteiner** c.4/6HK | toss | **24** ground / **28 air** (both wiki-exact) | Yes (+11 oki) | **yes — and stronger airborne** |

- Hundred-Slap is THE Mars hold-throw from the patch-13 exemption lore, now named.
- The air Frankensteiner dealing MORE than grounded (28 vs 24) is confirmed
  independently by wiki and emulator — first air-stronger throw found.

### Related
- **Desperation "Mars Snake Flare"** (6321412HK): §6b-6d — projectile 32 (wiki exact),
  chip 8×N (wiki) = our measured 4×8 blocked. Wiki: startup 19, −31 on block.
- **Record 0x11 — mystery SOLVED**: it is Snake Flare's own dispatch record (verified:
  the desperation fires REC @C1:586D live). The handler at C1:583C stages act 0x75 and
  dispatches it, reached from the act-machine branch at C1:5890. Single-variant +
  no-misfire is the desperation-record signature (Moon 0x0C, Venus 0x16, Chibi 0x1B
  follow the same pattern). Nothing unused after all.

## Venus (charID 5)

### Crescent Beam — 236LP / 236HP (record idx 0x14)

| Variant | Act | Damage | Chip | Wiki startup/recovery |
|---|---|---|---|---|
| LP | 5D | **8** (wiki exact) | 2 | 11 / 36 |
| HP | 5E | **10** (wiki exact) | 2 | 15 / 51 |

- Horizontal beam at **−68px flight height** (same altitude as Supreme Thunder) —
  **crouching avoids it completely** (verified: zero contact vs a croucher), exactly
  as the maintainer said. Anti-stander/anti-jumper only. Misfire acts 5F/60.

### Wink Chain Sword — [2]8LP / [2]8HP (charge down-up; record idx 0x15)

| Variant | Act | Damage | Spawn distance | Chip | Wiki recovery / on block |
|---|---|---|---|---|---|
| LP | 63 | **8** (wiki 10 col) | **32px** | 2 | **3** / +34~ |
| HP | 64 | **9** (wiki 12 col) | **64px** | 2-3 | **7** / +30~ |

- A ground-to-sky pillar rising from floor height at a fixed distance — and the
  button-dependent distance is literally encoded in the record payload (byte 2:
  LP 0x20 = 32px, HP 0x40 = 64px). The maintainer's description matches the data
  structure itself.
- **Guard: Mid confirmed** — both standing and crouching block it for 2 chip (the
  "might hit low" hypothesis is refuted; wiki Mid agrees). Rig note: the stand-block
  test needs a DELAYED guard hold — a defender holding back during the charge walks
  out of the pillar's fixed spot and the move whiffs entirely (which itself documents
  the pillar's core weakness: it does not track).
- Wiki's near-zero recovery (3/7 frames) makes it hugely plus on block — a trap/oki
  pillar, not a projectile duel tool. Misfire acts 65/66 (= her patch-12 taunt).

### Love-Me Chain — 623LP / 623HP (DP family; no dispatcher record)

| Variant | Act | Hits (ours) | Total | Wiki actives / on block |
|---|---|---|---|---|
| LP | 67 | 4 × 5-6 | **23** | 4×6 / −15~+1 |
| HP | 68 | 3 × 6-8 | **22** | 5×6 / −29~−9 |

- The multi-hit chain-whip strike, anti-air per the community; class 0x08, chips
  1-2 per hit on block, minus on block. No invulnerability observed in the hurtbox
  trace (unlike Neptune's Splash Edge) — its anti-air value is reach/actives, not
  invuln.

### Throws — one of each type

| Throw | Type | Damage | Techable | Wiki oki |
|---|---|---|---|---|
| **Huracanrana** c.4/6HP | toss (victim carried airborne mid-throw) | **22** (wiki exact) | Yes | +18 on tech |
| **Machine Gun Knee** c.4/6HK | **HOLD — 5 knees × 4** | **20** (wiki exact) | No | **+41** |

- Machine Gun Knee is the sixth confirmed hold-throw (Moon, Mars-HP, Chibi, Uranus-HK,
  Pluto-HK, Venus-HK) — the kick-button hold-throw pattern is now clearly the
  house style.

### Related
- **Desperation "Chain Explosive"** (4123632HP, record 0x16): §6b-6d — strike 37
  deterministic in our rig (wiki 48 = the adjacent row-48 column, same story as
  Neptune's Dragon Rise). Wiki chip 12×5 vs our measured single 9 — unreproduced,
  flagged like Neptune's.

## Moon (charID 1)

### Moon Tiara Action — 236LP / 236HP (record idx 0x0A)

| Variant | Act | Damage | Chip | Wiki startup/recovery/on-block |
|---|---|---|---|---|
| LP | 63 | **10** (wiki exact) | 2 | 11 / 31 / +6~ |
| HP | 64 | **12** (wiki exact) | 3 | 15 / 46 / −9~ |

- Flies at **−56px** — low enough to clip crouchers, and **Mid confirmed** (crouch-block
  chips 3; the maintainer's read was right). Misfire acts 6A/6B (= her patch-12 taunt).

### Moon Spiral Heart Attack — j.214LP / j.214HP (record idx 0x0B)

- **Horizontal confirmed — at whatever height Moon casts it**: the slot flies at
  constant Y equal to her altitude at the moment of release (traced at both apex and
  late-jump casts). Casting also **recoils her backward ~40px** — it doubles as an
  air-retreat tool.
- In our rig it never reached a grounded target from a jump; the wiki lists it guard
  **High**, 8/10, +18~ on block (LP), recovery "until landing". Wiki prose: the HP
  projectile GROWS mid-flight and shoves Moon to screen edge; LP barely recoils.
- **Backdash-cancel tech (wiki prose, VERIFIED live)**: Moon's backdash cancels into
  her air specials — traced: backdash act 0x26 (invulnerable) → Heart act at ~8f in,
  projectile spawning at **−80px** (vs −164 from a jump cast — nearly standing-head
  height!) while she sails backward. Wiki: ~+28f (LP) / +8f (HP) when done this way —
  the "bait jump-ins like a DP" tool. Her backdash also self-cancels (17f window, up
  to 4 chained; input 42144 hold-4 for a reliable double).
- Misfire act 6C (both variants share it).

### Sonic Cry — [2]8LP / [2]8HP (charge; strike family, no dispatcher record)

| Variant | Act | Hits | Wiki | Notes |
|---|---|---|---|---|
| LP | 68 | 3×6=18 connected (wiki up to 6×7) | startup 16, ~−5 | multi-hit riser |
| HP | 69 | single 12 connected (wiki 12 + up to ×23!) | startup 10, **−44/D** | the commitment version |

- Charge time is LONGER than Venus's Wink (a ~45f charge fails, ~55-60f works) —
  charge minimums are per-character.
- **Startup-invulnerable reversal confirmed**: hurtbox idx 0x00 for ~9 frames of
  startup (traced), then active with dedicated boxes 0x37/0x38 — wiki prose "good
  invincibility" verified.

### Throws

| Throw | Type | Damage | Techable | Wiki oki |
|---|---|---|---|---|
| **Headbutt** c.4/6HP | **HOLD — 4 headbutts × 5** | **20** (wiki exact) | No | **+41** |
| **Rabbit Flip** c.4/6HK | toss (flip carry) | **20** ground / **24 air** (wiki) | Yes | +11 on tech |

- Headbutt is the patch-13-lore Moon hold-throw, now named. Rabbit Flip's air version
  is stronger (24 vs 20), matching the Mars Frankensteiner pattern.
- Hold-throw button pattern refined: inner senshi hold on HP (Moon, Mars), outers on HK
  (Uranus, Pluto, Venus... Venus is inner-adjacent but holds on HK — pattern imperfect).

### Dash Jump — 66 (character-specific movement, act 0x60)

- Her "forward dash" is a **leaping hop**: act 0x60 (character-special act space, like
  Uranus's Shadow Dash), ~30 frames, **~200px of travel** — the longest movement in the
  game measured so far — and it sails THROUGH the opponent's position (crossup
  potential). Wiki lists it with startup 1.
- Wiki prose warning worth keeping: the 66 buffer window is ~15 frames, so shimmying
  in neutral triggers accidental hops — "a move you'll use often whether you mean to
  or not".

### 2HK — the fireball-limbo sweep (maintainer's note, quantified)

During 2HK (act 0x59) her hurtboxes drop to tops of **−44/−50px** vs −82 standing:
she ducks clean under Supreme Thunder and Crescent Beam (−68 flight), and even her own
Tiara altitude (−56) — losing only to ground-level projectiles (World Shaking, Snake
Fire, close Deep Submerge at −30). Low, knockdown, 8 damage (wiki).

### Related
- **Desperation "Silver Crystal Operation"** (2363214HK, record 0x0C): §6b-6d —
  projectile 48 (wiki exact). **Wiki gap: their table lists chip 12×N and their prose
  says "good chip damage"; we measured ZERO chip** (130f of blockstun, no HP writes —
  the engine's one flagged no-chip projectile). Emulation trusted; worth a community
  correction. Wiki prose adds: highly invulnerable through the fall as a reversal, and
  the shrinking pillar shields her from projectiles while falling (it can no longer
  hit, but hitting HER requires a late, well-timed shot or a disjointed normal).

## Mercury (charID 2)

### Bubble Spray — [4]6LP / [4]6HP (charge; record idx 0x0D)

| Variant | Damage | Chip | Wiki startup/recovery | Notes |
|---|---|---|---|---|
| LP | **8** (wiki exact) | 2 | 12 / 31 | VERY slow bubble (~1.7 px/f — 40f to cross 70px) |
| HP | **10** (wiki exact) | 2 | 16 / 41 | faster |

- Horizontal at −56px (clips crouchers), Mid. The community's "Bubbles" — the slow LP
  float is the setplay tool. Misfire acts 65/66 (= her patch-12 taunt).

### Mercury Aqua Mirage — **2369LP / 2369HP** (record idx 0x0E)

| Variant | Act | Damage | Chip | Wiki startup/recovery |
|---|---|---|---|---|
| LP | 69 | **12** (wiki exact) | 3 | 8 / 36 |
| HP | 6A | **14** (wiki exact) | 3 | 12 / 49 |

- **Input corrected via wiki: 2369 (quarter-circle ending UP-FORWARD), not 236** — the
  9 is mandatory; plain 236P produces a normal (verified exhaustively). Fitting for a
  sharp upward fireball: it rises from floor height (contact at −1px close in). Her
  STRONGEST fireball (12/14 beats Bubble's 8/10) with fast startup. Misfire 6B/6C.

### Reverse Break Step — 623LK / 623HK (no dispatcher record)

| Variant | Act | Hits | Wiki | Chip (wiki) |
|---|---|---|---|---|
| LK | 5F | ours 2×4 (wiki up to 4×9) | −7~+1 | 1×7 |
| HK | 60 | ours single 12 (wiki actives 4,3×13,4) | −22/D | **3×15** |

- **The invulnerability question settled: it HAS real invuln** — hurtbox absent for
  ~12 frames from act start THROUGH the first active frames (traced), then dedicated
  spin hurtboxes for the long tail. "Little, maybe none" undersold it; it's a genuine
  reversal layer, though the extended spin is exposed. The HK's 3×15 chip makes it a
  corner chip machine per the wiki.

### DDT — c.4/6HP (her only throw; ground and air)

- Toss **24** ground / **28 air** — both wiki-exact; the air-stronger pattern's third
  member (Mars Frankensteiner, Moon Rabbit Flip). Techable, with a wiki quirk: the
  thrower is briefly invincible on the opponent's tech (−6 but safe).

### Triangle Jump — 7/9 near a wall (wiki-listed movement)

- Chun-Li-style wall jump, 8f recovery per the wiki table. Not rig-tested (movement
  tech; noted on maintainer + wiki authority).

### Related
- **Desperation "Water Bullet"** (632146HK): §6b-6d — strike 48 (wiki exact). The
  maintainer's "has some invincibility" verified and then some: **12f startup invuln
  AND a fully hurtbox-less ACTIVE phase** (hitboxes 0x11/0x12 cycling with no hurtbox
  at all), separated by only a ~6f vulnerable gap. One of the safest desperation
  strikes in the game structurally — the wiki's −55 on block is its only real tax.

## Chibi Moon (charID 9)

*(Drafted from wiki + emulator ahead of the maintainer's detail session; flag anything off.)*

### Pink Sugar Heart Attack — [4]6LP / [4]6HP (charge; record idx 0x1A)

| Variant | Act | Damage | Chip | Wiki startup/recovery |
|---|---|---|---|---|
| LP | 61 | **10** (wiki exact) | 2 | 18 / 36 |
| HP | 62 | **12** (wiki exact) | 2-3 | 23 / 51 |

- Slim, long-hitbox heart beam at −52px; wiki prose is candid that it's her least-used
  tool (slow LP, chip utility only). Misfire acts 63/64 (= her patch-12 taunt).

### Swinging Marshmallow — j.2LK / j.2HK (air dive; strike family, no record)

| Variant | Act | Damage | Wiki |
|---|---|---|---|
| LK | 65 | **8** (wiki exact) | High /D, −19~−10, the close version |
| HK | 66 | **10** (wiki exact) | High /D, faster fall, whiffs point-blank |

- The butt-dive: **overhead, knockdown**, and as an air special it is
  **backdash-cancelable** — with her backdash that makes it a fully invincible
  approach-mixup engine (wiki prose). Unique to her along with the double jump.

### Throw — c.4/6HP (her only throw; HOLD-type)

- **10 rapid ticks × 2 = 20** (act 5A, ~4f cadence — the fastest tick rhythm measured),
  **untechable**, +13 oki. The wiki's blunt assessment: her most consistent damage.
  Third and final patch-13-lore hold-thrower confirmed (Moon, Mars, Chibi — all on HP).

### Movement — the real kit

- **Backdash 44: 26 frames fully invulnerable (VERIFIED — hu=00 t+1..t+26), 78px per
  wiki, vulnerable only on frame 27 — and it self-cancels on frame 26**: Chibi is the
  only character able to chain backdashes indefinitely while remaining invincible
  (hold the second back input to buffer). Longest backdash invuln in the game
  (Uranus 14f, Pluto 20f, Chibi 26f).
- **Double jump j.7/8/9**: a character-specific COMMAND (like Mercury's triangle
  jump), not a special — hold the direction (no tap needed), available through frame
  27 of the first jump. Cast-unique with the dive.
- 2LK hits low and its recovery is JUMP-CANCELABLE (wiki) — the low→instant-overhead
  blender starter; 2HP is one of the game's few low 2HPs.
- **2HK is a sliding sweep** (maintainer's read, verified): act 0x58, one traveling
  active window of ~40 frames (hitbox 0x0E) carrying her **~102px forward** — longer
  than Uranus's slide (67-79px). 9 damage wiki-exact, low, knockdown.

### 5LP — the double-play quirk (maintainer's hypothesis, CONFIRMED)

The fastest normal in the game (2f startup, wiki) really does **play twice**: the move
runs act 0x40 with an active hitbox window (t+1..t+3), then chains into act 0x41 and
puts the SAME hitbox out again (t+17..t+21) — animation and hitbox both, on hit and on
whiff alike. Damage applies only once in practice (2), because the first hit's stun
covers the second window — but the second window is a REAL hitbox, so against an
opponent who walks into range between windows it could in principle connect alone.
Extra jank: the second hitbox OUTLIVES the move — it stays active for ~2 frames after
her act returns to neutral (hb=01 with act 0x00 in the trace). Tiny range and 2 damage
keep it a curiosity, exactly as the maintainer said — but it is now a frame-documented
engine oddity.

### Related
- **Desperation "Luna P Attack"** (j.63214HP, record idx 0x1B): §6b-6d — air barrage
  52 (7×6-8 measured; 24 vs crouchers, first-hit-only counter 54). Wiki mechanics:
  Luna P bounces a figure-8 anchored to her cast position (vary cast height!), grants
  a 27f guaranteed action, EATS projectiles in flight, chips 1×N, blockable by either
  guard, and — as an air move — is backdash-cancelable. The wiki's matchup notes list
  the counterplays (GC specials, invincible moves threading through).

---

## Template for the remaining characters

For each named special: LP/HP variant acts, melee/projectile path, stand/crouch/chip
damage, misfire acts (cross-check the record tables), Guts coverage, and any recognizer
quirks. **No characters pending — the compendium is complete.** Remaining open items
live in the per-character sections (wiki gaps, Mercury/Jupiter/Uranus/Neptune/Pluto
desperation-record locations, triangle-jump and double-jump rig tests). DPs/command grabs are NOT in the record tables, so
each character may also hide a 623/360-style move the tables can't reveal — ask the
community list per character. (Neptune's "super" turned out to be her DP; there may be
no true supers besides desperations.)
