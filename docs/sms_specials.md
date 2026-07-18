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
| LP (632+LP) | 61 → 63 | projectile, 1 hit | **9** | 9 | **2** | faster arrival (hit t=40 from 70px) |
| HP (632+HP) | 62 → 64 | projectile, 1 hit | **11** | 11 | **2** | stronger, slightly slower (t=43) |

- Posture-blind per-hit (projectile path), like all projectiles measured so far.
- Damage rolls with the normal matrix variance (the maintainer has seen 8s; we logged
  9/11 at this rig's fixed frames — same move, different columns).
- Misfire acts 65 (LP) / 66 (HP) — these are also patch 12's taunt acts for Uranus.
- Guts (patch 13) scales it via the projectile sites: verified family behavior
  (projectile hooks are unconditional).

### Diving Gaia Crash (SPD) — 6248LK / 6248HK (360 recognizer, not in the record table)

| Variant | Acts | Type | Damage | Guts Grip L3 |
|---|---|---|---|---|
| LK | 67/69 → 6B/6D/6F → **toss act 71** | command grab, single toss | **24** | **10** |
| HK | 68/6A → 6C/6E/70 → **toss act 71** | command grab, single toss | **32** | **13** |

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
- **Desperation** (632141236HK, rush→grab hybrid, 67/51, lows in the rush):
  `sms_acs_system.md` §6b-6d.
- **Normal throw**: hold-type, ~22 via the tick path (§6c note).

---

## Template for the remaining characters

For each named special: LP/HP variant acts, melee/projectile path, stand/crouch/chip
damage, misfire acts (cross-check the record tables), Guts coverage, and any recognizer
quirks. Pending inputs: Moon ×3, Mercury ×2, Mars ×3, Jupiter ×2, Venus ×3, Pluto ×1,
Chibi ×2 (record idx 0x0A-0x1B), plus any 236236-style supers besides Neptune's.
