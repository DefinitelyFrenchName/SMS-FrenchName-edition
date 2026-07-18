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

Status: **Uranus complete**; others pending motions from the maintainer.

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
1. **World Shaking listed damage 12/14 vs our rolled 9/11** — not a contradiction but a
   sampling difference: the value is a matrix roll; the wiki apparently lists a high
   roll, we log the roll at our fixed frame. Range, not a single number.
2. **Destructive Carnival guard "Mid"** — our measurements say standing block COLLAPSES
   mid-rush (66 + the grab lands) while crouch-block neutralizes it (11, no grab): at
   minimum some rush hits are lows, so "Mid" is wrong or incomplete on the wiki.
3. Wiki lists WS chip 3 vs our 2 — chip rolls too (both ≈ hit/4 of adjacent columns).

---

## Template for the remaining characters

For each named special: LP/HP variant acts, melee/projectile path, stand/crouch/chip
damage, misfire acts (cross-check the record tables), Guts coverage, and any recognizer
quirks. Pending inputs: Moon ×3, Mercury ×2, Mars ×3, Jupiter ×2, Venus ×3, Pluto ×1,
Chibi ×2 (record idx 0x0A-0x1B), plus any 236236-style supers besides Neptune's.
