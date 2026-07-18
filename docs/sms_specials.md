# Special moves — per-character compendium

**What this is.** The specials companion to the desperation compendium
(`sms_acs_system.md` §6b-6d): per character, every special's input, damage paths,
posture/chip values, and patch coverage — measured with the same rig
(`tools/probe_p13f_desp.lua`, single-roll deterministic, clean ROM, defender at 0x60 HP).
Move names and inputs from the maintainer / Dustloop community wiki
(https://www.dustloop.com/w/SMS — Cloudflare-blocked for our fetcher; values below are
our own measurements).

**Structural ground truth** (see annotations "Special-move record tables"): each
character's misfire-capable specials live in a bank-$C1 record table (7-byte records,
LP/HP variant pairs; record+0 = global index = the move's +0x44 attack class).
Command grabs (360 recognizer), supers and desperations are recognized separately.
Known table sizes: Moon 3, Mercury 2, Mars 3, Jupiter 2, Venus 3, Uranus 1, Neptune 1,
Pluto 1, Chibi 2.

Status: **Uranus, Neptune, Jupiter and Pluto complete**; others pending motions from the maintainer.

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

---

## Template for the remaining characters

For each named special: LP/HP variant acts, melee/projectile path, stand/crouch/chip
damage, misfire acts (cross-check the record tables), Guts coverage, and any recognizer
quirks. Pending inputs: Moon ×3, Mercury ×2, Mars ×3, Venus ×3,
Chibi ×2 (record idx 0x0A-0x1B). DPs/command grabs are NOT in the record tables, so
each character may also hide a 623/360-style move the tables can't reveal — ask the
community list per character. (Neptune's "super" turned out to be her DP; there may be
no true supers besides desperations.)
