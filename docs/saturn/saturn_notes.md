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
- Manifest `$E0:AC6A`: **first_hit_defense = 1** (SMS: only Jupiter=1, Neptune=2 —
  relevant to the first-hit damage rule), palettes `$E0:B0C8`, anim payload `$E0:F328`.

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

**Far 5HK is empirically unblockable in its effective range.** With P2 HOLDING away
and visibly in pre-block pose (act 0x0C/0x0D): HIT at spacing 34/36/38/40/44 px;
first BLOCKED at 48 px. Control: her 5LP at the same spacings is blocked normally
(P2 reaches blockstun 0x0E/0x0F) — so this is a per-move guard-proximity data bug,
not a rig artifact. [W] attributes it to mismatched guard-distance data ("poor
coding") and also lists **far 5LK** as fully unblockable and close 5HK as guardable
only at 25-37 (stand) / 25-32 (crouch); our 5LK test needs spacings <34 px (its
reach) — REMAINING MEASUREMENT.

Other [W] flags to verify: "weird throws"; S-tier above Uranus (Zam 2020 tier list);
no documented Saturn infinite (the Uranus infinite carries over from SMS unchanged).

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
