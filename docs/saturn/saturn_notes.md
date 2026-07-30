# saturn_notes.md — Sailor Saturn (Super S) dossier

Measured in-emulator on the Super S ROM (fixture `traces/saturn_vs_uranus_supers.mss`,
P1 Saturn vs P2 Uranus; probes `tools/probe_saturn_moves.lua` /
`probe_saturn_unblockable.lua`) unless tagged [W] (web, newchallenger.net Super S page)
or [L] (vendor Lua). This grows into the Uranus-grade balance dossier (template §5).

## 1. Identity & loading

- charID **10 (0x0A)**; loads into a live match via the standard char-select pokes
  (`$1B40=10`) — measured 2026-07-30. Struct at `$7E:1000` behaves exactly like SMS
  (act/step/pos/HP/box indices/ACS offsets all live).
- Box tables (extracted, `docs/saturn/supers_all_boxes.json`): **30 hit boxes**
  (`$AF:EC3A`), **93 hurt pairs** (`$AF:ED2A`), **6 collision** (`$AF:F2FA`).
  Same 8-byte box format as SMS.
- Manifest `$E0:AC6A`: **first_hit_defense = 1** (SMS: only Jupiter=1, Neptune=2),
  palettes pal1 `$E0:B0C8` / pal2 `$E0:B0A8` / icon `$E0:B270` / obj `$E0:B208`.
  NOTE: the record's last field is `$E0:F328` for ALL TEN characters — in Super S it
  is NOT the per-char anim payload (SMS semantics changed); the real payload location
  is an open question (find it at runtime: watch what fills `$7E:6A00` during her load).
- Dispatch entries (both tables are SMS's structures widened to 11): recognizer record
  `$C1:1452` = `145E 15F1 15FA 1603 160C FFFF` — **5 command recognizers, the exact
  SMS shape** (Uranus has 5+FFFF too); state-proc-B record `$C1:174E` (7 bytes,
  `02 00 04 08 06 00 0a`). Dispatch tables: `$C1:13CC` (SMS `$13C7`+5) and `$C1:16F9`
  (SMS `$169B`; exactly 11 entries — the roster-widening signature).

## 2. Act map (measured so far)

| Act pair (attack→recovery) | Move | Notes |
|---|---|---|
| 0x40 → 0x41 | 5LP (far+close share act) | far: active idx window t+2..19, neutral @20 |
| 0x44 → 0x45 | far 5HP | active 11..47, neutral @48 — enormous duration |
| 0x46 → 0x47 | close 5HP | active 2..47 |
| 0x48 → 0x49 | 5LK | reach < 34px (never connected at 34+); active 5..11 far |
| 0x4C → 0x4D | far 5HK | **the broken one** — see §3; active 9..19, neutral @33 |
| 0x4E → 0x4F | close 5HK | comes out at ≤32px |

("active" = frames with nonzero hitbox index +0x40 after press; refine vs hitstop and
the SMS S/A/R conventions in the full pass.)

- Cancellable-recovery set [L, matches measured recoveries]: `{0x41,0x43,0x49,0x4B,
  0x59,0x5B,0x61,0x63}` — 8 acts (every SMS character has 4). 0x43/0x4B presumably
  crouch LP/LK recoveries; 0x59/0x5B/0x61/0x63 unmeasured (jump/dash normals?).
- Her attack acts start ≈0x40 (SMS characters' start ≈0x2B) — numbering differs from
  every SMS cast member; do not assume SMS universal-act boundaries above 0x2A.

## 3. The broken tools (measured + [W])

**Far 5HK is empirically unblockable — against BOTH guards.** With P2 holding
away (stand block) OR down-away (crouch block), visibly in pre-block pose: HIT at
34-44 px; first blocked at 48 px. Control: 5LP at identical spacings blocks both
ways. So it is not a high/low issue and not a hitbox-flag anomaly (her kick boxes
carry the cast-normal flags vocabulary {02,03,05}; the only flags outlier in the
whole game is Mercury hit[3]=0x3B, unrelated). The defect lives in whatever decides
guard SUCCESS per move (guard-range/level data) — locating that table is
next-session probe #3 and balance knob #1. [W] attributes it to mismatched guard-distance data ("poor
coding") and also lists **far 5LK** as fully unblockable and close 5HK as guardable
only at 25-37 (stand) / 25-32 (crouch); our 5LK test needs spacings <34 px (its
reach) — REMAINING MEASUREMENT.

Other [W] flags to verify: "weird throws"; S-tier above Uranus (Zam 2020 tier list);
no documented Saturn infinite (the Uranus infinite carries over from SMS unchanged).

## 3b. Attack classes / damage (measured)

Her +0x44 attack classes are TEXTBOOK SMS: lights cls=0x00, heavies cls=0x04
(damages: 5LP 2, 5LK 3, far 5HP 6, close 5HP 7, 5HK 8). The
"class-overflow causes the unblockable" hypothesis is REFUTED — her classes fit
the on-hit tables fine; the guard bug lives in guard-success data/logic elsewhere.

## 3c. Sprite cels (port budget seed)

Cels stream uncompressed from ROM per frame (see supers_map §pipeline). Known so
far: **5HP cels at $DD:7C60-9600 (~6.6 KB)**. Full census: run
probe_supers_dmacensus.lua while driving each move (next session, mechanical).

## 4. Reference: what changed around her in Super S [W]

Projectiles/desperations nerfed across the shared cast; Neptune charge-input
regression breaks her guard cancels; Chibi buffed; no SMS bugfixes. Prior-art
rebalance: "Sailor Moon Fighter S" (romhacking.net/hacks/4498) changed her Death
Drive Break input (412364+HP → 632146+HK), sped Silence Buster, added a counter.

## 5. Dossier TODO (the Uranus-grade template)

- [ ] Full act table incl. crouch/jump/dash normals, specials, desperation (record
      dispatcher: find the Super S `$C1:0B49` equivalent), throws (the "weird" ones).
- [ ] Frame data per move, oracle conventions (S excl. first active, hitstop-excluded
      counts, advantage) — port the training framedata rig (hook `$80:8347`).
- [ ] Hitbox visualization (retarget hud_boxes to bank $AF tables).
- [ ] Damage values + attack classes (+0x44) per move; whether she claims on-hit
      classes beyond 0x1F.
- [ ] Guard-proximity data: LOCATE the per-move guard-distance table that far
      5LK/5HK get wrong — this is balance knob #1 (make them blockable).
- [ ] Throws: type, ranges, techability (vs SMS mash-tech system).
- [ ] Desperation: trigger conditions, damage, chip.
- [ ] Sprite/anim payload: manifest at `$E0:ABC4 + 10*2`, LZSS payload address/size
      (for Route A porting budget).
