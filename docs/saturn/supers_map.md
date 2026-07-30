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
| Anim-script char table | `$C0:0000` (interp `$80:A05C`; NO 0xC0 cmd case) | `$C0:0000` (interp `$80:A381`; adds 0xC0 cmd → `$80:FBB4`) | [P 07-30, live ALL PASS] |
| Pose-record char table | `$84:809C` (writer `$C0:9C96`) | `$84:809F` (writer `$C0:9FC1`) | [P 07-30, live ALL PASS] |
| Cel char table (pose→cels + 5B recs) | `$CB:0000` (resolver `$80:9FB8`, kicker ends `$80:9FB7`) | `$CB:0000` (resolver `$80:A2DD`, kicker `$80:A21A`) | [P 07-30, live ALL PASS] |

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

## Character architecture — the move pipeline [P 07-30, movereq/coverage probes]

**Characters are DATA + shared engine code; there is no per-char "handler block".**
The move-request register is **+0x51** (low nibble = requested move, consumed and
cleared each frame at `$C1:0280/0284`); three producers:

1. **Button handler `$C1:161F`** (JSL): `charID*2` → table `$C1:16F9` (11 e.) →
   7-byte per-char button-map record (Saturn `$C1:174E` = `02 00 04 08 06 00 0a`);
   fresh-press masks ($68/$6A/$6B) select a nibble → +0x51. Also owns the
   double-tap (dash) counters +0x5B..+0x5E.
2. **Command recognizers `$C1:1264`** (via `$13CC` per-char list → spec records,
   e.g. Saturn `$1452` → 5 motion specs; matcher `$C1:1290`, per-recognizer
   progress at +0x5B..): on full match, `$C1:1339` writes the recognizer ordinal
   nibble → +0x51 (`sta $51,X` at `$1352`; +bit0 if button variant).
3. (Universal states write acts directly via the generic act-setter `$C1:0226`.)

**Special starter `$C1:096B`**: consumes the +0x51 nibble against a per-char record
(act list + per-special 16-bit gating flags — observed bits: 0x01 air-only-ish
(+0x16 bit7 & +0x32), 0x02 ground-only, 0x04 projectile slot must be free (checker
`$C1:04EA` tests $1100/$1180), 0x08 desperation gate (mode≠4, clock/$1F5C, HP≤0x18)).
Saturn's special-act lists sit at `$C1:0940-0968` (normals 4C..59, specials
**0x6E-0x7C**); qcf+LP verified live → act 0x6E (request nibble 04 via `$1352`).
Projectile OBJECTS dispatch per-frame at `$C1:1755` via `jsr ($00A6,X)` by the
projectile's own object id → per-object-type act procs (e.g. `$C1:280B` dispatcher
+ `$281D` act table for the qcf-special's projectile).

**Per-char proc blocks — CORRECTION (2026-07-30, smoke-test session).** The main
object loop (`JSL $C1:0000`, both games) dispatches EVERY object by id:
`jsr ($00A6,X)` at `$C1:0080` (SMS; same table addr in Super S). **Table entries
1-9/10 are per-character proc blocks of ~4.2-5.3 KB each** (SMS: Moon `$270B` …
Chibi `$AE47`; Super S adds **Saturn `$C6F7`**, ≈4.3 KB, ids 11+ = projectile
procs). The earlier "no handler block exists" conclusion was WRONG — the
exec-coverage diff missed the blocks because the idle BASELINE already executes
them (they're the character's per-frame state driver); the 630 B "exclusive"
figure was only the paths idle doesn't touch. The earlier coverage clusters
`$C1:C9C4-CE64`/`$C1:D6FA-D76B` are fragments of Saturn's block. Route A porting
cost: her ~4.3 KB proc block relocated + call fixups (still bounded and
enumerable; the smoke test borrows Uranus's proc for universal acts meanwhile).
An id with a 0000 proc entry `jsr $0000` = recursive main-loop re-entry = stack
overflow (measured the hard way).

## Saturn's proc block — PORTED [P 07-30, proc-port session]

Her ~4.4 KB per-char proc block ($C1:C6F7-$DA3C + act jump table $C706, 86 per-act
procs) is ported by `tools/saturn/port_saturn_proc.py`:

- **Recursive-descent disassembly** from the dispatch + all act-table targets
  (M/X tracked via REP/SEP; 1788 instructions reached; data pockets between procs
  preserved byte-exact). The block is **self-contained**: its per-move records
  (special gating/act-lists at $C806-C922, misfire/extra records at $D9F3-DA3B)
  live inside it and are referenced by `ldy #imm` — all internal.
- **384 external operands fixed up** (48 unique bank-$C1 targets, mapped to SMS by
  signature/skeleton match at regional deltas −2/−25/−5; two JSLs: $80:C115 →
  $80:BFBB (the box-data helper; only operand bytes differ incl. box bank
  $AF→$8A) and $80:FBB0 → $80:9FB7 bare-RTL stub ($FBB0→$FBB4 is the Super S
  sound/CMD handler with NO SMS twin — her sfx are silenced, TODO).
- **Graft**: appended bank $EF = full SMS-$C1 copy + her fixed block at its
  original in-bank offsets. Internal refs verbatim; engine jsr's hit the copied
  SMS routines (PB=$EF, plain rts works); phk/plb data readers (special starter,
  ochame dispatcher $0B49) resolve to her grafted records. Entry: 7-byte hook at
  the main dispatch $C1:007C → JSL $EF:DB00 helper (id 0x1C → jsr $C6F7; others →
  4-byte $C1 stub `jsr ($00A6,X)/rtl` at $C1:0B01, the 0AFD FF-run tail).
- **Projectiles**: her specials SPAWN objects with Super S ids (0x20 = qcf
  LP/HP fireball — a fully-defined 7-table object in Super S; 0x22 = another).
  Until those objects are ported, all free-id proc entries (0x1D-0x2F) point at
  the engine despawn tail ($C1:0E23 `stz $00,X/rts`): spawns self-clear, and her
  "hold act until projectile dies" handlers complete. Her act-0x70/71 waiters
  otherwise re-force the act every frame — an inert projectile wedges the move
  (measured).

Verified: idle/walk 228/228 ALL PASS through her real proc; specials qcf-LP
(6E→70) and qcf-HP (6F→71) complete with projectile spawn/despawn; act handlers
return to neutral. Request-nibble → act map measured via +0x51 pokes
(probe_sms_saturn_attacks.lua).

**Pad-input layer (same session): PLAYABLE.** Three more integrations, all
verified by probe_sms_saturn_pad.lua (buttons → correct normals 40-4D + crouch
58/59/64/65 + air 53; real qcf motion → special 6E/70; her hits CONNECT and she
takes hits):
- **Button-map hook**: 11-byte head at `$C1:15C4` → JSL $E8 stub. Both this and
  the recognizer hook use RETURN-ADDRESS SURGERY (stub adds N to the JSL return
  on the stack) — the recognizer hook's 7 post-JSL bytes at `$C1:1263` become a
  DATA slot holding her button record `02 00 04 08 06 00 0a`.
- **Recognizer graft**: her motion specs ($C1:1452-1615) grafted into the $EF
  bank-copy at original offsets; copied-table entry $EF:13FF → her list; for id
  0x1C the stub skips the REAL dispatch entirely (surgery +0x26 to its plb/rts —
  avoids per-frame +0x5B state stomps) and runs the FULL copied dispatch via a
  4-byte $EF trampoline entering at the routine's OWN prologue $125C (phk in
  bank $EF sets DB=$EF; its tail plb/rts self-balances — entering past the
  prologue corrupts the stack, measured).
- **Box tables**: appended bank $F0 = full bank-$8A copy read via WRAM-mirror
  DB $B0 (6× `plb #$8A`→`#$B0` at $BFD2/$C004/$C36F/$C3A8/$C3E6/$C74F); widened
  0x30-entry ptr tables at $F0:8100/8160/81C0 (7 read-operand patches at
  $BFDF/$C37C/$C3B7/$C015/$C3F7/$C764/$C795) + her box data at $F0:8230+.
  NOTE for final integration: p7/p9 patch box data in REAL $8A — the copy must
  be taken AFTER their edits when stacking.

## Projectile objects — PORTED (visible fireballs) [P 07-30, projectile session]

Projectiles do NOT stream cels (both games): their tiles are STATIC in the OBJ
effects VRAM region (tile base 0xA0 = VRAM $6A00; loaded at match start,
COMPRESSED in ROM — source/decompressor unmapped, smoke uses a fixture VRAM dump
uploaded at runtime: probe_supers_effecttiles.lua → traces/saturn/
supers_effecttiles.bin). Saturn's fireball = 6 OAM sprites (tiles 0xA0/0xEE ×
flip variants).

Her three projectile objects (Super S ids kept — free in SMS): **0x20/0x21**
(qcf LP/HP wave) and **0x22** (second special). Per-object port surface:
scripts `$C0:2715/2725/2735` (CMD-free → verbatim at original $E8 offsets),
shared pose records `$84:9575` (24), shared OAM blob `$84:B4A6-B6DA` (→
$F0:B4A6 via the $B0 mirror), shared hit boxes `$AF:F552` (→ $F0:8920), procs
`$C1:280B/28D3/29A6` with act tables — block $280B-**$2B60** grafted into $EF
(323 instructions, 42 operand fixups; new JSL twin verified: $80:C494 →
$80:C352, the projectile-flavor box helper). Dispatch: proc-table entries →
5-byte mini-stub in the button hook's skipped bytes ($C1:15C8: JSL $EF:DB30 /
RTS) → tramp3 re-dispatches by id (rep #$10 FIRST — the projectile loop
dispatches with 8-bit X, measured). Gotcha that cost a debug cycle: the wave's
act table extends past $2A80 (acts 3/4 at $2A8E/$2ACA) — a truncated graft
executes stale copy bytes mid-handler (garbage act 9, projectile never dies,
her wait-act wedges).

Verified: qcf fireball travels ~90 px, animates poses 0-3, hits at range from a
REAL pad motion, despawns; wave special (both strengths) completes; remaining
free ids keep the despawn placeholder.

## Effect tiles — load path found [P 07-30, effectload probe]

The static OBJ effect tiles (VRAM $6A00+, tiles 0xA0-0xFF — fireball art etc.)
are loaded at match start: DECOMPRESSED into WRAM **$7F:0000** (0x1040 bytes)
then DMA'd to VRAM $6A00 (one ch0 transfer). The decompressor drives a
RAM-resident `MVN $7F,$E2 / RTL` stub at $00:00C8 (LZ/RLE with MVN literal
bursts); Saturn's compressed source sits in **bank $E2 (~$E2:FC42)**. The
per-char source pointer table is not yet located. STRONG HYPOTHESIS for the
SMS side: the manifest record's final field (the "anim payload" pointer,
decompressed via `$C0:916B` to $7E:6A00 per CLAUDE.md's original notes) is
SMS's own compressed effect-tile blob — i.e. the char-load integration point
for her effects is the 10th manifest entry + an appended compressed blob (or a
raw-copy patch of the loader). Until then the smoke uses the fixture VRAM dump
at runtime. Verify the SMS hypothesis before building on it.

## OAM sprite-layout — the 4TH animation layer [P 07-30, smoke-test session]

Boxes/cels alone don't render a fighter; the OAM layout is a separate id-indexed
layer (found when smoke-test Saturn was invisible):

- **Renderer** (SMS `$C0:9A0E`, per frame): walks the draw-order list at `$0B00`
  with **DB=$84**; `object id ×3` indexes **char table `$84:8000`** (52 entries,
  3 B each: `[ptr16, bank]`) → `plb bank` → `pose ×2` indexes the pose→spritelist
  table at `ptr` → list = `[count, count × 6-byte records]`. Super S twin
  `$C0:9AA0` (long-pointer plumbing, same data shapes).
- **Record format** (6 B): `[x_off, x_off_flipped, y_off, attr-ish, tile, 
  attr-ish_flipped]`; consumed by emitters (SMS `$80:9B17` normal / `$80:9BCB`
  X-flip; Super S `$9C47`/`$9CF1`): OAM tile word = bytes[3..4] XBA'd (bit 0x0800
  = size flag, stripped) + the struct tile/attr base (+0x0A word, attr bits from
  +0x08<<9); screen pos = record offset + struct +0x28/+0x2A.
- **Per-char blobs**: each char's `[bank:ptr]` points at a self-contained blob in
  its own bank (SMS Jupiter `$87:8000`, Uranus `$8A:8000`…; **Super S Saturn
  `$87:8000`-`$87:BE5E`, 15.6 KB**, ~19-25 sprites/pose).
- **CRITICAL mirror rule**: the emitters WRITE the OAM shadow (`sta $0200,X` etc.)
  and the renderer reads the draw list via DB-absolute addressing → the entry's
  bank byte MUST be a **$80-$BF bank** (low half mirrors WRAM). Appended-bank data
  is reachable via the mirror: bank `$E8+n` upper half ≡ bank `$A8+n` upper half.
  (Smoke bug: bank byte $EE silently discarded every OAM write into ROM.)

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

## Sprite/animation pipeline — FULLY DECODED [P 07-30, streamer disasm + static census]

Three ROM layers drive all fighter animation; each is statically enumerable:

1. **Animation scripts** (interpreter `$80:A381`, JSL; data bank $C0):
   `charID*2` indexes **`$C0:0000`** → per-char act-script pointer table (indexed by
   act×2, act read from +0x04) → script = 2-byte steps `[duration-1 | ctrl, pose id]`.
   Ctrl bits in byte0: `0x40`=loop to script start (resets cursor +0x07), `0x80`=hold
   (stores negative duration → animation frozen until act change), `0xC0`=command
   (byte1 → `jsr $80:FBB4`, then continue; used at attack starts — sfx?). Duration
   countdown lives in +0x06, script cursor in +0x07, pose id lands in **+0x05**.
   Gated off during hitstop via +0x16 bit 4.
2. **Pose records** (writer `$C0:9FC1`; bank $84): see §Pose records above —
   pose id → `[class, hit, hurt, coll]` (class → +0x18, boxes → +0x40-42).
3. **Cel resolver + streamer** (resolver `$80:A2DD`, JSL; data bank $CB):
   `charID*4` indexes **`$CB:0000`** → two pointers: (a) pose→cels list, 2 B/pose
   `(celA, celB)`; (b) cel records, **5 B/cel `[addr24, size16]`**. Resolved into the
   player struct: celA → +0x0C..0x0E (24-bit ROM src) + size +0x12/13; celB (if ≠0)
   → +0x0F..0x11 + +0x14/15. The per-frame DMA kicker **`$80:A21A`** (the previously
   noted "streamer sites" `$80:A244`/`$80:A29F` are its P1/P2 halves) uploads
   P1 → VRAM word $6000, P2 → $6500 (B-bus $2118), one or two runs per player.

Cel graphics stream per-frame from ROM, uncompressed — no decompressed buffer; the
manifest anim field is vestigial (never read; $E0:F328 never read at all).
OAM shadow $7E:0200 → $2104, CGRAM shadow $7E:0500 → $2122, each DMA'd per frame.
(Callback gotcha: register bus watches on BOTH bank $00 and $80 mirrors.)

Per-char table entries (anim-script base / pose→cels / cel records):
Moon `$C0:006A`/`$CB:4000`/`$CB:002C`, Mercury `043A`/`40F6`/`0234`, Mars
`079D`/`41E6`/`045A`, Jupiter `0B60`/`42E8`/`06AD`, Venus `0F68`/`43EA`/`0905`,
Uranus `1299`/`44DA`/`0CC0`, Neptune `167E`/`45CA`/`0ECD`, Pluto `1A3B`/`46EA`/`1161`,
Chibi `1DD2`/`47C6`/`0B1C`, **Saturn `2105`/`4892`/`1346`**, plus a 12th slot
`252B`/`499A`/`00CB` (unidentified — boss/extra?).

**Route A graphics port unit per character** = act-script table + scripts (bank $C0)
+ pose records (bank $84) + pose→cels list + cel records (bank $CB) + the cel blocks
themselves.

**SMS twins LOCATED + LIVE-VERIFIED (2026-07-30, probe_sms_animtables.lua on clean
SMS, 241/241 frames ALL PASS incl. attack poses):** same three layers at the same
table bases — scripts `$C0:0000` (interpreter `$80:A05C`; SMS lacks Super S's 0xC0
command extension — Saturn's CMD steps need handling at port time: strip or
back-port), pose records `$84:809C` (writer `$C0:9C96`), cels `$CB:0000` (resolver
`$80:9FB8`). All tables are null+9 packed (id-10 "entries" are adjacent data — no
dormant slot, as established). **Cross-game content identity (Uranus): pose-record
array 100% byte-identical (all 115 SMS poses; Super S appended 5), universal-act
scripts byte-identical, pose→cels lists identical, cel records same sizes with only
addr24 relocated (SMS bank $D4 vs Super S $D6).** Port recipe per layer: pose
records verbatim (+ the 2 guard-fix bytes), pose→cels verbatim, cel records with
addr24 rebased to wherever her 137 KB cel block lands in SMS, scripts verbatim
minus/with the CMD delta, plus 11th entries in the three char tables (relocation
per the §Route A table list).
