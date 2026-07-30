# supers_map.md — Super S (Zenin Sanka!!) ROM/RAM map

Verified facts only; every row is tagged. Sources: [L] = vendor
`sms-training-mode/SailorMoonS.lua` (dual-game, detects `$FFB3`); [P] = probed
in-emulator/from-ROM this repo (date); [W] = web, cited. UNVERIFIED rows are
claims awaiting a probe — do not build on them.

ROM: `SailorMoonSuperS Vol2`, HiROM+FastROM, 0x300000, file offset = SNES & 0x3FFFFF
(same mapping rule as SMS — banks $C0-$EF). SHA-1 `1ada3417…4426e` [P 2026-07-30].

## Cross-game address table (the Rosetta Stone)

| Structure | Sailor Moon S | Super S | Status |
|---|---|---|---|
| Header game code `$FFB3` | 0x51 | 0x4A | [P 07-30] |
| Palette manifest ptr table | `$E0:0238` | `$E0:ABC4` (file 0x20ABC4; null+10 recs, 16 B apart — same format) | [P 07-30] |
| Box data bank | `$AF` bank confirmed via extraction | `$AF` | [P 07-30] |
| Hit-box ptr table | `$8A:C1F1` (28 e.) | `$AF:B000` (char ptrs B072..F32A; extraction green) | [P 07-30] |
| Hurt-box ptr table | `$8A:C229` (10 e.) | `$AF:B046` (11 e., Saturn at B05A) | [P 07-30] |
| Coll-box ptr table | `$8A:C23D` (10 e.) | `$AF:B05C` (11 e.) | [P 07-30] |
| Input-read hook (exec PC) | `$80:8373` | `$80:8347` — SAME instruction bytes (c2 20 a5 5c), relocated −0x2C | [P 07-30] |
| Object update entry | `$C1:0000` | `$C1:0000` | [L] UNVERIFIED |
| State-proc A dispatch | code `$C1:125F`, table `$C1:13C7` (28 e.) | code `$C1:1264`, table `$C1:13CC` | [P 07-30] |
| State-proc B dispatch | code `$C1:15C4`, table `$C1:169B` (10 e.) | code `$C1:1622`, table `$C1:16F9` (**11 e.** — widened for Saturn) | [P 07-30] |
| Saturn (cid 10) box ptrs | — | hit `$AF:EC3A` (30 boxes) / hurt `$AF:ED2A` (93 pairs) / coll `$AF:F2FA` (6) | [P 07-30] |

## WRAM (claimed identical to SMS by [L] — verify per row before use)

| Address | Meaning | Status |
|---|---|---|
| `$7E:1000` / `$7E:1080` | P1/P2 player structs — offsets live in-match (charID/act/step/pos/boxidx/HP/maxHP/ACS) | [P 07-30] |
| `$7E:008D` | game mode (1 = 2P VS observed) | [P 07-30] |
| `$7E:0070` | in-match flag = 4 in-match | [P 07-30] |
| `$7E:0802-0804` | round clock (frame/ones/tens; 60s default observed) | [P 07-30] |
| `$7E:1B40/1B80` | char-select cursors — poking 10/6 selected Saturn/Uranus | [P 07-30] |
| `$7E:00A4/$7E:00AC` | Super-S-specific exit-detect pair (the Lua's freeze workaround) | [L] |

## Saturn behavioural data (from [L], to verify in Phase 2)

- Cancellable light-recovery acts: `{0x41,0x43,0x49,0x4B,0x59,0x5B,0x61,0x63}` — 8
  entries vs 4 for every SMS character.

## Known gameplay deltas vs SMS [W: newchallenger.net Super S page]

- Projectiles/desperations weakened across the shared cast (Moon/Mercury/Mars/
  Venus/Jupiter lost their useful fireballs; DM damage cut, e.g. Moon 48→40).
- Neptune's new charge fireball input overrides her DP → wrong guard cancels
  (system-level regression).
- Chibi Moon buffed (Twinkle Yell). No SMS bug fixes carried in. Saturn added.
- "Ability Customize System" (ACS points UI) exposed in most modes.

## Relocated SMS structures found in Super S [P 07-30, signature hunt]

| Structure | SMS file off | Super S file off | Shift | Content |
|---|---|---|---|---|
| Char loader body | 0x87D0 | 0x87E8 | +0x18 | first 48 B identical |
| On-hit tables | 0xCDD5 | 0xCEFF | +0x12A | first 0x40 identical |
| Damage matrix | 0xD081 | 0xD1C9 | +0x148 | rows 10 & 48 identical |
| Box-index writer | $C0:9CCD ctx | 0x9FF1 ctx | +0x32C | 16 B identical |
| joy_read tail | 0x8373 | 0x8347 | −0x2C | 4 B identical |

NOT found byte-exact (changed in Super S, consistent with the wiki's gameplay deltas):
modifier handlers (0xCAED), Moon's desperation record, hit-resolution head (0xBFC0),
the 8× melee apply sequence (only 1 exact match — apply-site pattern changed),
2HP cancel-commit context. Bank-level similarity: $C0 28%, $C1 14%, $C3 61%, most
data banks <13% (globally shifted, locally identical where hunted).

## Saturn manifest [P 07-30]

`$E0:AC6A` (via ptr table idx 10): **first_hit_defense = 1** (only Jupiter=1,
Neptune=2 in SMS), pal1 `$E0:B0C8`, anim payload `$E0:F328`.

## Manifest semantics delta [P 07-30]

Super S manifest records keep SMS's 16-byte layout for d48 + the four palette
pointers, but the final 3-byte field is `$E0:F328` for ALL characters — NOT the
per-char anim payload SMS stores there. Per-char animation payload location in
Super S: UNKNOWN (runtime method: read-watch the `$7E:6A00` expansion during load).

## Bank $C1 comparison note [P 07-30]

16-byte shingle analysis: 25% of Super S bank $C1 exists verbatim in SMS's, 63%
"novel" — but the novelty is dominated by shifted absolute operands (the identical
joy_read demonstrates code equality despite byte inequality). Handler-block
identification/sizing therefore needs disassembly along Saturn's act dispatch,
not byte matching. Largest contiguous novel runs are ≤0x250 B (scattered).

## Pose records & the proximity-guard system [P 07-30, guardfind/posetiming/guardfix probes]

The per-frame box/status writer is `$C0:9FC1` (JSL; loops objects $1000..$1180, data
bank $84). Per object: `charID*2` indexes a **pointer table `$84:809F`** (12 entries,
null+11) → per-character **pose-record array**, 4 bytes per pose, indexed by the pose
id in `+0x05` (×4): `[class → +0x18, hit idx → +0x40, hurt idx → +0x41, coll idx →
+0x42]`. Pose ids are set by the animation scripts; the records are the single source
for boxes AND the pose "class".

- **Class byte vocabulary** (byte0, observed whole-roster): {0,2,4,6,8,9,11,13}.
  **Class 9 = attack-threat**: arms the opponent's proximity guard (Uranus has 17
  hitbox-less class-9 poses — startup announcements). The defender holding away enters
  pre-block act 0x0C/0x0D the same frame the attacker's pose class turns 9.
- **Guard success is decided attacker-side at hit resolution** and requires the
  defender to ALREADY be in act 0x0C/0x0D: block verdict writer `$80:C43B` (writes
  pending code 02/04), hit verdict writer `$80:C2ED` (codes 06+). Hit resolution runs
  BEFORE the `$C1:0000` object update within a frame, so a threat announced only on
  the first active frame loses the race and the move hits through held guard.
- **Victim reaction applier `$C1:0E2B`** (JSL; per player): consumes pending-hit code
  `+0x47`, dispatches through 3 jump tables — `$C1:0E88` (standing), `$C1:0EA4`
  (crouching, +0x54 bit2), `$C1:0EC0` (guard-incapable, +0x16 bit7 clear) — whose
  entries are act stubs (block 0x0E/0x0F, hitstun 0x10-0x16, knockdowns 0x17-0x1B)
  ending in the commit hub `$C1:10AE` (`sta $01,X` etc.).
- Pose-record arrays (bank $84): Moon `80E5`, Mercury `82D1`, Mars `84B1`, Jupiter
  `86B5`, Venus `88B9`, Uranus `8A99`, Neptune `8C79`, Pluto `8EB9`, Chibi `9071`,
  **Saturn `9209` (126 poses)**, end `9401`.
- Zero-size "marker" hit boxes exist (e.g. Saturn hit[0x1A-0x1C], w=h=0): carried by
  some startup poses alongside class 9; they never connect (no area) — the guard
  trigger is the CLASS byte, not the box (A/B-proven: marker box alone ≠ trigger,
  class 9 alone = trigger).

## Sprite/animation pipeline [P 07-30, DMA census + streamer probes]

- **Cel graphics STREAM per-frame from ROM, uncompressed** — no decompressed anim
  buffer (the WRAM $6A00 write-watch caught nothing; the manifest anim field is
  vestigial — never read during load; $E0:F328 never read at all).
- Two fixed streamer sites configure the per-player cel DMA every frame:
  **P1 `$80:A244`, P2 `$80:A29F`** ($43n4 bank writes, B-bus $2118). Sources roam
  ROM banks by animation: fighters observed streaming from banks **$D6, $DD, $DE**
  (~1.2 KB/frame each); effects/projectiles from $DF; OAM shadow $7E:0200 → $2104,
  CGRAM shadow $7E:0500 → $2122, each DMA'd per frame.
- **Saturn's 5HP cels: bank $DD, src 0x7C60..0x9600** (attack-window census).
  Full per-move cel census = drive each move under probe_supers_dmacensus.lua.
- NEXT: Dispel `$80:A244/A29F` to find the per-frame cel-address tables (per
  act/step) — that table + the cel blocks + the animation scripts are the Route A
  port unit for graphics. (Callback gotcha recorded: register bus watches on BOTH
  bank $00 and $80 mirrors — $80-DB writes land at $80xxxx bus addresses.)
