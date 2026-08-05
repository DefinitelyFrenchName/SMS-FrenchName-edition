# saturn_notes.md — Sailor Saturn (Super S) dossier

Measured in-emulator on the Super S ROM (fixture `traces/saturn/saturn_vs_uranus_supers.mss`,
P1 Saturn vs P2 Uranus; probes `tools/saturn/probe_saturn_moves.lua` /
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
| 0x74 → 0x76 | **j.632K air special** | spawns projectile id **0x21**; wait-act 0x76 until it clears (was the 0.11.0 crash — see BUILDS 0.11.1) |

- **No forward step-dash**: 66 walks, in Super S too (measured 2026-07-31) —
  the engine's double-tap dash is per-char proc behavior and her proc has none.
  Backdash (universal act 0x26) works.
- **Movement sounds are script-CMD driven** (unlike SMS chars, whose engine
  plays them): CMD args 0x02=jump, 0x06=backdash, 0x08=landing, 0x22=(unused
  fwd-dash-ish act 0x24); mapped in CMD_SND_MAP to SMS natives (0x0C/0x2D/0x0D,
  measured via probe_sms_dashsfx_sat.lua). Hit-reaction args (0x05/0x11/0x12/
  0x16) + starter args (0x23/0x24/0x25) deliberately unmapped (engine paths
  already cover those sounds).
- **Projectiles use OAM palette 2** in both games (attrs x34/x74/xB4/xF4,
  measured mid-flight); Super S's effects palette lives at $E0:B208 (blue).

("active" = frames with nonzero hitbox index +0x40 after press; refine vs hitstop and
the SMS S/A/R conventions in the full pass.)

- Cancellable-recovery set [L, matches measured recoveries]: `{0x41,0x43,0x49,0x4B,
  0x59,0x5B,0x61,0x63}` — 8 acts (every SMS character has 4). 0x43/0x4B presumably
  crouch LP/LK recoveries; 0x59/0x5B/0x61/0x63 unmeasured (jump/dash normals?).
- Her attack acts start ≈0x40 (SMS characters' start ≈0x2B) — numbering differs from
  every SMS cast member; do not assume SMS universal-act boundaries above 0x2A.
- **Specials: acts 0x6E-0x7C** (act list at $C1:0955-0968). Measured (Super S
  qcf+LP live + the SMS proc-port request sweep, probe_sms_saturn_attacks.lua):
  request nibble 04 → **acts 0x6E→0x70** (qcf+LP), 05 → **0x6F→0x71** (HP
  version) — both spawn **projectile OBJECT id 0x20** (a fully-defined 7-table
  object in Super S: proc $C1:280B/table $281D, script $C0:2715, cel ptrs
  $CB:9A03/$CB:CB9A, poses $84:9575, OAM $84:B4A6-B6DA) — Silence Buster
  presumably. Nibbles 08/09 → **acts 0x6A→0x6C / 0x6B→0x6D** spawning
  **projectile id 0x22** (second special). Her "wait" acts (0x70/71, 0x6C/6D)
  re-force themselves each frame until the projectile slot clears. **Recognizer specs DECODED (v0.7.0 session)** — direction encoding is a
  BITMASK (1=fwd, 2=back, 4=down; 5=df, 6=db), spec = [threshold, dir]* pairs +
  [threshold, button-mask] + FF: spec2 = d,df,f+light = **QCF** (nibble 4 ✓
  observed), spec3 = its mirror/heavy variant, spec4 = d,db,b+light = **QCB**
  (nibble 8 ✓ = the wave special), spec5 = b,db,d,df,f,b+button =
  **412364+HP — the desperation — RESOLVED 2026-07-31 (v0.11.2)**: input
  412364 (~8f per direction is comfortable; each step waits up to 15f) then
  **HP** (the spec button mask 0x40 = HP only; punches are 0x10/0x40, kicks
  0x20/0x80 — spec2 qcf mask 0x50 = both P, spec3 mask 0xA0 = both K), at
  HP≤0x18 (the starter's desperation gate). Commit writes request nibble
  0x0A|1 = 0x0B. Full nibble map (ordinal = rec index*2+2, +bit0 heavy):
  2=double-tap-back (spec1), 4/5=qcf+P (spec2), 6/7=632+K (spec3 — the AIR
  special), 8/9=qcb+P (spec4), A/B=desperation (spec5). On startup act 0x78
  (whiffs with quick recovery at range); ON HIT → **act 0x79: a full-screen
  multi-hit rushing sequence** (8 hits, ~15 dmg, P2 in hitstun act 13
  throughout) — verified FRAME-IDENTICAL to Super S (same acts/poses/hitbox
  indices/damage cadence; probe_sms_desp3 vs probe_desp3_supers). Point-blank
  the back+HP ending is eaten by throw priority (authentic).
  **The old "rec5 freezes at [00,05]" mystery**: the port's recognizer payload
  copy was TRUNCATED (HI=0x1616, but spec5's 7 pairs + FF end at 0x161A) —
  pair index 5 read SMS-copy leftovers whose nonzero threshold routed the
  matcher into its hold path, which never increments the timer on a mismatch
  at timer=0. One-line fix: RECOG_PAYLOAD_HI → 0x161B. Super S never froze
  (the old session's Super-S "freeze" was input timing — taps too fast for
  the per-step 15f windows to catch the final back).
  Matcher semantics (decoded $C1:1290): pair [b0,b1]; b0=0 → 15f-timeout step
  (b1=0 neutral-exact, b1 low-nibble=0 button-mask, else dir-exact); b0>0 →
  HOLD dir for ≥b0 frames; b0≥0x80 → dir-BITMASK overlap. Commit when the
  byte after the matched pair is 0xFF; spec head 0xFE = hold-accumulator
  ($C1:1361, reads $69).
- Button-map record $C1:174E `02 00 04 08 06 00 0a`; special gating records per
  supers_map §Character architecture.

## 3. The broken tools — ROOT CAUSE FOUND + FIX VALIDATED (2026-07-30)

**Both far kicks confirmed unblockable, root-caused to two malformed pose records,
and fixed with ONE BYTE each (A/B-proven in-emulator, probe_supers_guardfix.lua):**

| Move | Startup pose | Record @ file | Vanilla | Fix | A/B result |
|---|---|---|---|---|---|
| far 5HK | 0x20 | `0x049289` ($84:9289) | `00 00 17 00` | byte0 `00→09` | HIT@40px → BLOCKED; still HITS vs no-block |
| far 5LK | 0x1D | `0x04927D` ($84:927D) | `00 00 14 00` | byte0 `00→09` | HIT@24px → BLOCKED; still HITS vs no-block |

Mechanism (full chain in supers_map §Pose records & proximity guard): the defender
only enters pre-block pose (act 0x0C/0x0D) when the attacker's current pose has
**class 9** (pose-record byte0, live in +0x18) — that's the "guard-proximity data".
Guard success then requires already being in the pose when hit resolution (which runs
BEFORE the object update each frame) resolves the contact. Saturn's far-kick startup
poses are the ONLY class-0 attack poses in the roster (every other startup announces
class 9), so the guard pose and the hit race on the first active frame and the hit
wins → unblockable at any range her first active frame reaches (5HK: 34-44 px band;
blocked ≥48 because contact then happens one frame after activation).

Refuted along the way: hitbox-flag anomaly (§3, flags are normal), attack-class
overflow (§3b), and the "startup threat-marker BOX arms the guard" variant — poking a
zero-size marker box (0x1B) into the startup pose does NOT trigger guard; the class
byte alone does. (5LP's startup pose 0x6B is `09 1B 50 02` — class 9 plus a
vestigial zero-size box; the box is inert.)

Balance knob #1 is therefore settled: 2 bytes, minimal and playbook-preserving (the
kicks keep range/damage/frame data; they just become guardable like every other
normal). **Close 5HK CONFIRMED FIXED in the SMS port (v0.7.0 flow suite): held
guard at 24px → pre-block 0x0C → blockstun 0x0E, zero damage** — the shared
pose-0x1D fix covers it as predicted.

**P2 projectile graphics note (v0.8.0 session)**: P2-Saturn's fireball uses
tile base **0x130** (second OAM name space, VRAM ≈$7300) — loaded by a
SEPARATE transfer from the P1 effects DMA (not yet traced; needed for the P2
in-ROM select path).
**Throws VERIFIED in the SMS port (v0.7.0)**: close 6HP → her throw acts
**0x68/0x69** (P2 held 0x1C → damaged into hitstun; the acts-68/69 sound site id
0x20 = the throw sfx). She takes throws normally (victim acts 1C/1D/1E).
Other [W] flags to verify: "weird throws" semantics vs SMS conventions; S-tier above Uranus (Zam 2020 tier list);
no documented Saturn infinite (the Uranus infinite carries over from SMS unchanged).

## 3b. Attack classes / damage (measured)

Her +0x44 attack classes are TEXTBOOK SMS: lights cls=0x00, heavies cls=0x04
(damages: 5LP 2, 5LK 3, far 5HP 6, close 5HP 7, 5HK 8). The
"class-overflow causes the unblockable" hypothesis is REFUTED — her classes fit
the on-hit tables fine; the guard bug lives in guard-success data/logic elsewhere.

## 3c. Sprite cels — FULL CENSUS DONE (static, 2026-07-30)

Enumerated from the decoded pipeline (supers_map §pipeline; no emulator needed):
her pose→cels list ($CB:4892, 132 entries) references **115 cels, 136.7 KB total**,
one contiguous region: **$DD:0D40–$DD:FEE0 (50 cels), $DE:0000–$DE:FC60 (51),
$DF:0000–$DF:34E0 (14)**. (The old 5HP DMA data point sits inside the $DD run.)
Whole-character port budget: 137 KB cels + act scripts + 126 pose records (0x1F8 B,
$84:9209) + pose→cels list (0x108 B) + cel records (575 B, $CB:1346) + boxes
(~1.6 KB) + palettes — trivially within SMS's ~1 MB headroom.

## 3d. Animation scripts (decoded; the balance fix lives here)

Act-script table `$C0:2105` (+act*2 → script). Verified against live traces:

| Act | Script | Steps (dur×pose) |
|---|---|---|
| 0x40 5LP | `$C0:234B` | CMD(15) 3f×6B, 3f×15, 4f×16, HOLD |
| 0x48 5LK | `$C0:237D` | CMD(15) 3f×1D, 6f×1C, HOLD |
| 0x4C far 5HK | `$C0:2391` | CMD(14) 7f×20, 10f×21, HOLD |
| 0x4E close 5HK | `$C0:239F` | CMD(14) 6f×1D, 7f×1E, 8f×1F, HOLD |
| 0x44 far 5HP | `$C0:2363` | CMD(14) 9f×3F, 5f×15, 11f×1A, HOLD |
| 0x46 close 5HP | `$C0:2371` | CMD(14) 6f×19, 8f×17, 11f×18, HOLD |

Key contrast: far 5HP announces startup properly (pose 0x3F = class 9, hit 0);
the kicks' startup poses 0x1D/0x20 are class 0 → the §3 bug. **Close 5HK shares
pose 0x1D with far 5LK, so the SAME 2-byte fix covers all three broken normals**
(far 5LK, far 5HK, close 5HK's 25-37px-only guard band). Usage census (whole act
table 0x00-0x6F): pose 0x1D only in acts {48,49,4D,4E,4F}, pose 0x20 only in {4C} —
attack/recovery contexts only, and recoveries carrying class 9 is cast convention
(5LP recovery reuses class-9 poses), so no side effects.

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

## In-match NAMEPLATE — the table is located (2026-08-05)

Field report: the name under the health bar is always the SHELL character's, not
Saturn's.

**Found statically, no emulator involved.** Nameplate letters are tile ids with
A = `$70` (docs/annotations.md), so each name is a searchable byte string. All
nine appear at a fixed stride:

    TABLE at file $D8BA = SNES $C0:D8BA — 9 records of 12 bytes, zero-padded,
    indexed by charID (1..9), with 12 bytes of zeros before and after it.

    id 1 MOON      id 4 JUPITER   id 7 NEPTUNE
    id 2 MERCURY   id 5 VENUS     id 8 PLUTO
    id 3 MARS      id 6 URANUS    id 9 CHIBIMOON

"SATURN" is `82 70 83 84 81 7D` — six tiles, comfortably inside a 12-byte record.
It appears nowhere in the ROM, as expected.

This is the same nine-wide-table shape that has already bitten this project three
times (throw poses `$C1:0881`, win nameplates `$82:E008`, movelists) — but note
the symptom differs: Saturn's id `0x1C` would index far PAST this table and give
garbage, whereas the field sees a correct SHELL name. So the lookup is being made
with the shell's charID, not with `0x1C` — the HUD is set up from the selected
character, independently of the transform. That means the fix is a redirect, not
an out-of-range repair.

⚠ **The hard part is not the table, it is the GLYPHS.** The nameplate font is
**matchup-loaded, not a resident A-Z set** (annotations.md: "G is in no
character's name" — which is why patch 10's status labels upload their own font).
Only the letters the two on-screen names need are present, so what "SATURN"
requires depends on the matchup:

| shell | letters its own name supplies | missing for SATURN |
|---|---|---|
| URANUS | U R A N S | **T** |
| NEPTUNE | N E P T U | **S A R** |
| PLUTO | P L U T O | **S A R N** |

and the opponent's name may or may not cover the rest. A fix that only swaps the
record would therefore render correctly in some matchups and show gaps in others
— so it must upload its own glyphs, exactly as patch 10 did.

**Next:** find the read site that indexes `$C0:D8BA` (a DMA carries the tilemap —
CPU port writes to the nameplate cells are ZERO, 1.29M port writes captured and
none in the window, so the write watch is alive and the transfer is simply DMA),
then hook it per player against the Saturn flag and upload the missing glyphs.

### Fallback (maintainer, 2026-08-05): BLANK the nameplate rather than show the shell's

If drawing "SATURN" proves awkward, the accepted fallback is to draw **nothing**
when she is selected.

This is worth more than its "fallback" billing, because it deletes the expensive
half of the job. The two halves are independent:

| | needs a per-player flag check + record redirect | needs glyph uploads |
|---|---|---|
| show `SATURN` | yes | **yes** — and the missing letters vary by matchup |
| show nothing | yes | **no** |

The redirect is the same hook either way; only the payload differs — a blank
record instead of her name. So the blank version is the *same* change minus the
matchup-dependent font work, which is the part that would otherwise have to
handle URANUS missing only `T` while PLUTO misses `S A R N`.

It is also strictly better than the current behaviour on correctness grounds: a
blank plate is merely absent, whereas the shell's name is actively wrong — it
tells the player they are fighting Uranus when they are not.

⚠ **One thing to verify, not assume:** the records are zero-PADDED, so `$00` is
the pad byte — but that does not prove `$00` renders as blank. The drawing
routine may copy a fixed 12 cells, in which case an all-zero record would draw
twelve copies of tile `$00`, whatever that glyph is. Check what tile `$00` is in
the nameplate CHR before shipping a zero record; if it is not blank, use the
tilemap's own blank (`$2000` per annotations.md) or whatever the surrounding
empty HUD cells contain.

**Suggested staging:** land the blank version first — it is small, correct, and
unblocks the field report — and treat the real name as a later improvement rather
than a prerequisite. That also lets the redirect hook be proven on its own before
any font work is layered on top of it.

### The draw routine, and the blank fix VERIFIED (2026-08-05)

Found statically, then confirmed on screen.

    $C0:D71E  sep #$30
    $C0:D720  lda $1000        ; P1 charID, straight from the player struct
              asl/asl/sta $00/asl/clc/adc $00   ; x12
              tax
              ldy #$0C                          ; 12 cells
              lda #$A2/sta $2116, lda #$10/sta $2117   ; VRAM $10A2 = P1 plate
    $C0:D738  lda $D8AE,X      ; 1-INDEXED: id 0 -> $D8AE = 12 ZERO bytes
              sta $2118, lda #$2C/sta $2119, dey, bne
    $C0:D747  lda $1080        ; then P2, VRAM $10B2

Two consequences:

* **It reads `$1000`/`$1080` — the player struct's charID — at a moment when
  that still holds the SHELL.** So the plate is not an out-of-range read (id
  `0x1C` would land at `$D9FE`, far past the table, and show garbage); it is a
  correct lookup of the wrong character. A redirect fixes it.
* **The plate is drawn by CPU port writes, not DMA.** Worth noting because an
  earlier probe watching exactly this VRAM window reported zero writes while
  capturing 1.29M overall — so that probe was wrong about something, and the
  disassembly is the authority here, not the probe.

**Blank costs nothing to store.** Index 0 already points at `$D8AE`, twelve zero
bytes the game never uses. Forcing the index to 0 therefore blanks the plate with
no new record anywhere.

**VERIFIED, not assumed** (the question flagged earlier — does tile `$00` render
blank?): a throwaway ROM with `lda $1000` replaced by `lda #$00 / nop` was
captured in 1P-vs-COM. P1's plate is **empty**, the opponent's is untouched, and
nothing else in the frame changes. Tile `$00` at attribute `$2C` draws nothing.

⚠ Capture note for anyone repeating this: **practice mode draws no nameplates at
all.** Three earlier captures had no HUD in frame and could answer nothing. Use
row 2 (1P-vs-COM) or 2P VS.

**Implementation, now fully specified:** hook the two `lda` sites and substitute
index 0 when that player is Saturn.

    site A  $C0:D720  `AD 00 10` (lda $1000)  — P1, flag $7F:F100 / latch $7F:F102
    site B  $C0:D747  `AD 00 10`? -> `AD 80 10` (lda $1080) — P2, flag $F101 / latch $F103

Each site is followed by `asl A / asl A`, so a 5-byte window (`lda abs` + two
`asl`) is available for a `jsl` + `nop`, with the stub returning A = index*4 and
the existing `sta $00` continuing unchanged. M and X are 8-bit on entry
(`sep #$30` at `$C0:D71E`). Vanilla is untouched whenever the flag is clear.

### SHIPPED: the blank nameplate (v0.14.10)

Two stubs in the `$EE` bank, hooked at the two charID reads:

    $C0:D720  lda $1000 / asl / asl   ->  jsl EE_NPHOOK1 / nop   (P1)
    $C0:D747  lda $1080 / asl / asl   ->  jsl EE_NPHOOK2 / nop   (P2)

Each stub returns `A = index * 4`: index 0 when that player's Saturn flag or
latch is set, otherwise the struct charID exactly as the vanilla code read it.
The two `asl` the hook swallows are reproduced at the end of the stub, so the
caller's `sta $00` sees precisely what it saw before. M and X are 8-bit on entry
(`sep #$30` at `$C0:D71E`), so no width juggling is needed.

No new data is stored anywhere: index 0 lands on `$D8AE`, the twelve zero bytes
already sitting in front of the table.

**Verified on screen, 1P-vs-COM, Saturn on a Neptune shell:**

| | her plate | opponent's plate |
|---|---|---|
| Saturn armed | **blank** | JUPITER, intact |
| nobody armed (control) | NEPTUNE, normal | JUPITER, intact |

Gates: `test_regression.lua` **ALL PASS (57)**, `verify_saturn.sh QUICK`
**ALL PASS (16)**. Hashes: hidden `a687499e…`, hidden+stage `48c6326d…`.

**Next, if the extra mile is wanted:** the redirect is now proven, so showing
`SATURN` is purely additive — point the index at a new record instead of 0 and
upload the missing glyphs. The glyph half remains the real work, because the
nameplate font is matchup-loaded (URANUS supplies all but `T`; PLUTO lacks
`S A R N`).

### THE EXTRA MILE: her name actually shows (v0.14.10)

There are **two** name tables, which is why P2's plate looks right:

    table A  base $D8AE  — P1, names LEFT-aligned    (read at $C0:D738)
    table B  base $D926  — P2, names RIGHT-aligned   (read at $C0:D75F)

Both are 1-indexed, and **both index-0 slots are twelve free zero bytes**. So the
blank fix and the name fix are the same hook with different data: writing
`SATURN` left-aligned into `$D8AE` and right-aligned into `$D926` turns the blank
plate into her name with **no code change at all**. The stubs still just return
index 0. Those two slots are also the only free ones in reach, since X is 8-bit
at the read.

**The glyph problem does not exist.** The prediction was that `SATURN` would show
gaps, because `docs/annotations.md` recorded the nameplate font as
matchup-loaded. Measured instead — all 26 letter tiles carry glyph data in every
shell's matchup — and corroborated independently by the rendered frame: she reads
`SATURN` on a **Neptune** shell versus Jupiter, where neither displayed name
contains an `S` or an `A`. The old note was an inference from "G is in no
character's name", which is a true fact with a false conclusion attached.
`docs/annotations.md` is corrected.

**Verified, 1P-vs-COM:**

| | her plate | opponent |
|---|---|---|
| shell 6 (Uranus) | **SATURN** | JUPITER |
| shell 7 (Neptune) | **SATURN** | JUPITER |
| shell 8 (Pluto) | all 26 letters present | — |
| nobody armed | NEPTUNE, normal | JUPITER |

Gates: regression **ALL PASS (57)**, `verify_saturn.sh QUICK` **ALL PASS (16)**.
Hashes: hidden `7db39c48…`, hidden+stage `3120d75a…`.

`SATURN_NAMEPLATE=0` reverts to the blank plate; the hook is unchanged either way.
