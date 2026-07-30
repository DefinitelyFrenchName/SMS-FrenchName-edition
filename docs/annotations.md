# annotations.md — address → label/comment (running log)

All SNES addresses unless noted. File offset = SNES & 0x3FFFFF (HiROM, headerless).
Sources: sms_uranus_rom_map.md (ground truth), vendor/sms-training-mode/SailorMoonS.lua,
and findings made in this project (marked NEW, with evidence).

## WRAM

| Address | Label | Comment | Source |
|---|---|---|---|
| $7E:008D | game_mode | 0=VS, 1=Story, 4=Training (5=training pause helper) | training Lua `mem_game_mode` |
| $7E:0802 | game_timer_bcd | round timer BCD (training Lua freezes it) | training Lua |
| $7E:1000 | p1 struct | player struct base P1 (0x80 bytes); P2 $7E:1080; base formula 0x7E0F80+n*0x80 | ground truth |
| +0x00 | charID | 1=Moon…6=Uranus…9=Chibimoon (10 "Saturn" = Super S carry-over, not in this game) | ground truth |
| +0x01 | actionID | current move/state; universal 0x00–0x2A (list in training Lua mem_player_action) | ground truth |
| +0x02 | action_started/step | word; training Lua writes 0x0001 when forcing action | training Lua |
| +0x04 | actionID mirror | written together with +0x01 by training Lua | training Lua |
| +0x05 | action_sprite | | training Lua |
| +0x06/07 | action tick/frame | word; zeroed when forcing action | ground truth + Lua |
| +0x09 | facing | flip X | ground truth |
| +0x18 | action_flags | 1=attack | training Lua |
| +0x20/24 | X/Y pos | 32-bit subpixel | ground truth |
| +0x30/32/34 | Xvel/Yvel/gravity | 16-bit | ground truth |
| +0x40 | hitbox idx | attack box index, 0=none; indexes bank $8A tables | ground truth |
| +0x41 | hurtbox idx | pair index (16B entries) | ground truth |
| +0x42 | collision idx | push box | ground truth |
| +0x43 | attack_connected | latch, set on connect (NOT hitstop — that is +0x4D); resolved 2026-07-30, see line ~191 + sms_engine_internals.md | ground truth |
| +0x44 | attackID | indexes damage tables at $C0:CDD5+ via (id>>1)*4 | ground truth |
| +0x46 | hurt_state | | training Lua |
| +0x47 | hitstun? | per CLAUDE.md | ground truth |
| +0x48 | first_hit_defense | loaded from char manifest | ground truth |
| +0x49/4A | HP/MaxHP | | ground truth |
| +0x4D | hitstop | per training Lua comment | training Lua |
| +0x50 | buttons_held | 1=L,2=R,4=D,8=U,0x10=LP,0x20=LK,0x40=HP,0x80=HK | training Lua |
| +0x52 | buttons (alt) | same bit layout | training Lua |
| +0x54 | normal_action flags | 1=back,2=fwd,4=duck,8=jump,0x10=LP,0x20=LK,0x40=HP,0x80=HK | training Lua |
| +0x5B..0x68 | command timers/states | pairs per special; Uranus grab at +0x63/64 etc. | training Lua |
| +0x70..0x75 | stat buffs | attack/defense/health/special/secret/ochame (NOT input buffer) | training Lua |
| +0x77 | action_strength | 7=LP, 8=LK, 9=HP, 10=HK | training Lua |
| $7E:6A00 | anim_staging? | char-specific payload expanded here by $C0:916B | ground truth (suspected animation data) |

## Uranus action IDs (from training Lua neutral_state — "cancellable recovery animations (light attacks)")
0x42, 0x48, 0x54, 0x58 — the four light-normal recovery states (stand/crouch LP/LK; exact mapping TBD empirically).

## Projectile objects & their box tables (Deep Submerge, patch 9)
- Projectile slots `$7E:1100` (P1) / `$7E:1180` (P2): same 0x80-byte struct as fighters; alive
  when `+0x00 != 0 && < 0x80`. The box_writer_batch ($C0:9CA4) loops these two slots too.
- A projectile selects its box table from `$8A:C1F1` (hit) by its **own** `+0x00` object id, not
  the owner's char. The hit pointer table has **28 entries**: idx 1–9 = roster, idx 10–27 =
  projectile/object tables (9 distinct: `$8A:FBD9,FC69,FC91,FCB9,FCF1,FD29,FD51,FD79,FDA1`).
  Dump with `tools/extract_proj_boxes.py`.
- **Neptune Deep Submerge** (fireball): 214LP = action `0x62`, 214HP = action `0x63`; both spawn
  object id **`0x18`** → hit table **`$8A:FD51`** (file `0xAFD51`), exclusive (pointer idx 24).
  Traced: origin `+0x25` descends 128→166 (Yvel +512/+768) while the ball stays centred on the
  origin, but hit entries `1,2,3` had `y_off=-27` and `4` had `y_off=-60` (authored for an
  UPWARD arc) → hitbox floats above the ball. Patch 9 sets entries 1–4 `y_off=-11` (keep h=22)
  so the box tracks the ball. Tools: `ds_trace.lua`, `ds_overlay.lua`, `ds_hittest.lua`.
- Tooling fix: the training-mode overlay (`hud_boxes.lua`) drew projectiles from the owner's
  char table; corrected to use the projectile's own `+0x00` (guard now allows ids up to 0x7F).
- **Projectile collision `$C0:C352`** (disassembled): resolves the projectile's **HIT** box from
  `$8A:C1F1[+0x00]` + `+0x40` and tests it vs (a) the OTHER projectile's HIT box `C395-C3D2`
  (projectile-vs-projectile clash) and (b) the player's HURT box `$8A:C229[char]` + `+0x41`
  (`C3D5-C42E`). It **never reads the projectile's own `+0x41`**. The HURT and COLL pointer
  tables are **roster-only (10 entries each** — `C229..C23D`, `C23D..C251`); only HIT was
  extended to 28. So projectiles have **no functional hurt/coll box** — their `+0x41`/`+0x42`
  (written by the shared box-writer) are vestigial. A projectile's hit box doubles as its
  hittable/clashable region → patch 9's hit-box fix covers offense AND clash.

## ROM (ground truth recap — see sms_uranus_rom_map.md)
- $8A:C1F1/C229/C23D box pointer tables; Uranus boxes $8A:E3E1/E489/E999.
- $C0:BFC0 hit check; $C0:CDD5+ damage tables `[dmg, hitstun, level, flags]` — GLOBAL, do not patch.
- $C1:0000 per-frame object update (state procs ≈ $C1:122A, $C1:15BD).
- $C0:879B char load; manifest ptrs $E0:0238+id*2; $C0:916B copies/expands one payload to $7E:6A00.

## Harness notes (Mesen2 2.1.1, macOS arm64, testrunner mode)
- `Mesen --testrunner --timeout=N <rom> <script.lua> [--debug.scriptWindow.allowIoOsAccess=true] [--snes.port1.type=SnesController --snes.port2.type=SnesController]`
  Config switches use reflection over the C# Configuration tree (case-insensitive).
- Lua: `emu.addMemoryCallback(cb, emu.callbackType.write|exec, start, end, emu.cpuType.snes, emu.memType.snesWorkRam|snesMemory)`;
  cb gets (addr, value); PC via `emu.getState()["cpu.k"]/["cpu.pc"]` (also cpu.dbr, etc.).
- `emu.createSavestate()/emu.loadSavestate(str)` ONLY legal inside an exec memory callback on the main CPU.
- Input: `emu.setInput({a=..,b=..,x=..,y=..,l=..,r=..,up=..,down=..,left=..,right=..,start=..,select=..}, port)` inside an `emu.eventType.inputPolled` event callback.
- WRAM $7E:0000-1FFF is mirrored in bank $00 — hook writes via memType snesWorkRam (absolute) to catch all mirrors.

## Title menu / input system (NEW, verified by probe + disassembly)
| Address | Label | Comment |
|---|---|---|
| $00:8353 (code $C0/80:8353) | joy_read | NMI-side: copies $4218-421B to DP; computes press edges |
| DP $5C/$5D | joy1_held | word, JOY1 (B=0x8000 Y=0x4000 Sel=0x2000 St=0x1000 U=0x800 D=0x400 L=0x200 R=0x100 A=0x80 X=0x40 L=0x20 R=0x10) |
| DP $5E/$5F | joy2_held | word, JOY2 |
| DP $60 | joy1_press | newly-pressed edge word, recomputed EVERY frame (1-frame lifetime) |
| DP $62 | joy2_press | ditto JOY2 |
| DP $64/$66 | joy1/2_prev | previous frame values |
| $7E:1B10 | title_cursor | 0=Story 1=1Pvs2P 2=1PvsCom 3=Tournament 4=Practice 5=Options; moves via table $C0:A29D+cursor*4 [up,down,left,right] |
| $7E:1B14 | demo_countdown | decremented in $C0:A337; 0 → auto-demo |
| $C0:A2CC | title_move_cursor | applies d-pad edges to $1B10; **polled only every ~4 frames** — 1-frame edges are usually missed; navigation must pulse until $1B10 changes (closed loop) |
| $C0:A337 | title_confirm_check | confirm = $60 & 0x5080 (Start / Y / A) |

Harness gotchas (verified):
- Mesen2 SNES `RamPowerOnState` defaults to Random → nondeterministic boots. Always pass `--snes.ramPowerOnState=AllZeros`.
- `emu.setInput` port indices are 0-based (port 0 = P1) — confirmed by $4219 latching start+down set on port 0.

### Mesen 2.1.1 setInput port bug (critical harness note)
`LuaApi::SetInput` does `ForceParamCount(3)` then `lua_settop(lua, 4)`, so the
documented 2nd parameter (port) is DISCARDED and always reads as 0. The port is
effectively the **3rd** argument: `emu.setInput(buttons, 0, port)` with port 0=JOY1, 1=JOY2.
Verified: setInput({start},0,0)+setInput({down},0,1) → $4219=10, $421B=04.
Consequence: any second setInput call written as (tbl, 1) silently clobbers port 0.

### Title menu poll cadence
Menu handler consumes 1-frame press edges ($60) only on some frames; period-4 press
pulses can phase-lock and never register. Use period-7 (3 on / 4 off) pulses — verified
every pulse registers at the title menu.

## Character select / VS flow (NEW)
| Address | Label | Comment |
|---|---|---|
| $7E:1B40 | charsel_p1_cursor | holds charID under cursor (1=Moon..10); spatial movement over group photo |
| $7E:1B42 | charsel_p1_confirmed | 1 after P1 confirms |
| $7E:1B80 | charsel_p2_cursor | P2 equivalent |
Flow: title (cursor $1B10=1 = 1P vs 2P, confirm Start) → char select → VS config screen
(button map + stage) → Start → match. Poking $1B40 before confirm is a reliable way to
select a character headlessly — but ONLY to a mode-legal charID: story/1P mode
restricts the roster (see move-t2 below); poking 6/7/8 there crashes even vanilla.

Char-select engine (decoded 2026-07-31, saturn v0.10.0 work; code runs from the
$80 FastROM mirror — exec watchpoints need $80:xxxx):
| Address | Label | Comment |
|---|---|---|
| $C0:A58E | charsel_move_t1 | movement, nav table $AA4D; serves BOTH cursors in VS AND practice (Y=$1B40/$1B80); X=charID*4; pad via [$FE]→DP $60/$62 (edge-triggered) |
| $C0:A5DF | charsel_move_t2 | story/1P variant, nav table $AA75 — table deliberately omits routes to 6/7/8 (outer senshi are story bosses, no player story data) |
| $C0:AA4D/AA75 | charsel_nav_t1/t2 | 10 rows × [up,down,left,right] neighbor charID; row 0 dead (cursor never 0); self-reference = no move; sfx $78=4 on move |
| $C0:A77D | charsel_draw_blk1 | P1 cursor sprite; positions $AA9D+charID*2 (packed x,y); count byte $AAD9, sprite def $AADA, attr $07=0x30, emitter jsr $9B17 |
| $C0:A7A4/A7F2/A819 | charsel_draw_blk2a/b/c | second cursor (VS P2 / practice dummy); positions $AAB1+charID*2 (+0x10 x-shift), defs $AAE1/$AAE8/$AAEF (tiles 02/04/06) |
| $C0:A7CB | charsel_draw_blk3 | story single cursor; positions $AAC5+charID*2 (+8 x-shift) |
| $C0:A630 | charsel_confirm | per-player per-frame; A/Y/Start (mask $5080, normal pal) or B/X ($8040, alt pal); $78=3; dedup $A693/$A6C4 sets samechar→alt palette |
| — | position tables | each table's char-0 word is never read (reads 1-indexed) = the PREVIOUS table's free char-10 slot; UI sprites emitted via $9B17 are QUEUED (direct $0200 shadow pokes get E0-cleared later in the frame) |

## Uranus crouching LP (2LP) — measured lifecycle (Mesen frame-advance, savestate uranus_vs_moon.mss)
Buttons: Y=LP, X=LK, B=HP, A=HK. Crouching attacks: 2LP=0x53, 2LK=0x55? (X→0x55 str8),
2HP=0x57 (str9), 2HK=0x59 (str10). 2LP recovery state = 0x54 (cancellable, in Lua neutral list).

Whiff timeline (press at t=60):
- t=60 action start (act=0x53, step-0, nothing processed)
- t=61-63 startup anim: sprite 0x35, dur loaded into $1006=2 (3 frames), $1007=2
- t=64-67 active: sprite 0x36, hitbox idx 0x0A, $1006 init 3 ($1007=4, 4 frames)
- t=68 act→0x54 step-0 (hitbox persists this frame → active is 5f total, matches Dustloop)
- t=69-72 recovery anim: sprite 0x35, $1006 init 3 (4 frames)
- t=73 act→0x03 crouch neutral
Dustloop cross-check (2LP): dmg 3 ✓, startup 4 ✓, active 5 ✓, recovery 6, +6 on hit ✓.

On-hit (P1 next to P2, press t=60): hit lands t=64, dmg 3; hitstop freezes P1 tick 8 frames
(t=65-72); act 0x54 at t=76-80; neutral t=81. P2: act=0x12 hitstun t=65-86, act 00 at 87,
hurt flag clears 88; first frame a raised block actually protects = vs hit landing t=88.

Cancel mechanics (measured):
- Press edges during 0x53 (t=66/70/74) are LOST — no buffer into recovery.
- 0x54 cancels into a new 2LP on ANY frame: press on step-0 frame (76) latches and starts
  jab next frame (77); press on 77+ starts SAME frame. Jab start S hits at S+4.
- Infinite window today: press 76..83 (8 frames), jab starts S∈{77..83}, hit ≤87 wins
  (hit@87 beats P2's block raised same frame; press@84 → hit@88 → BLOCKED).

Patch arithmetic: delay availability of the cancel by N frames (add N non-cancellable
recovery frames to 2LP before 0x54): earliest start 77+N ≤ 83 → N=6 gives unique start
frame 83 (presses 82/83 both map to it — engine's step-0 latch), hit on 87 = last winning
frame → true 1-frame link. N=7 makes the loop impossible (would violate DoD 3b).

## REVISED TARGET (2026-07-10): 2HP > 66 dash cancel — measured mechanics
Button mapping CORRECTION: **Y=LP, X=HP, B=LK, A=HK** (SF2-SNES layout; the training-Lua
strength comment "8=LK 9=HP" is wrong — verified empirically by damage/frame data).
Crouching actions: 2LP=0x53(rec 0x54), 2HP=0x55(rec 0x56), 2LK=0x57(rec 0x58), 2HK=0x59.
Lua "neutral" list {42,48,54,58} = light-attack recoveries (5LP,5LK,2LP,2LK) — 2HP's 0x56
is NOT in it; the dash cancel is a separate mechanism.

2HP (0x55) measured (matches Dustloop 8/12/9 dmg7): press t=60, startup 61-67 (spr 0x35,
dur 6), active 68-78 + step0 (spr 0x6C, hitbox 0x13, dur 0x0A), rec 0x56 79-86, neutral 87.
On hit: dmg 7, P2 act 0x13 heavy hitstun ~34f (hit@68 → free@103), P1 hitstop 8f.

Forward dash = action 0x60 ("Shadow Dash"): 66 double-tap; recognizer = $105D timer/$105E
state (1→2 on fwd, →3 on release, dash on 2nd fwd); 14f dash + landing 0x09 + ~5f.
Dash-cancel gate (measured via 66-completion sweep during 2LP>2HP rep, hit@85):
- ILLEGAL during 2HP startup / pre-hit (66 completed @83 expired unused; buffer lifetime finite)
- LEGAL from first frame after hitstop (dash fires @94 = hit85+hitstop8+1, canceling
  remaining ACTIVE frames directly — 0x56 never entered) through 0x56 recovery.
- 66 completed during hitstop → dash at 94; completed later → instant dash.

Rep timing [2LP>2HP>66] (P1@0xE8, P2@0x100): 2LP@60 hit 64 → chain 2HP@77 hit 85 →
buffered dash out D=94 → dash 94-107 → landing 108-112 → presses ≤108 LOST, earliest
jab press 109 → start 110 → hit 114. P2 (heavy stun from 85) escapes: hit ≤120 wins
(same-frame-as-block hit wins), 121+ blocked.
Window today: presses 109-115 (7 frames), starts 110-116, hits 114-120.

**N = 6**: delay dash-out to 100 → landing 114-118, single viable press 115 → start 116 →
hit 120. N=7 → hit 121 → loop impossible (violates DoD 3b). Patch surface = the dash
TRIGGER code's gate (script durations don't gate it — dash cancels mid-active).

## Dash-cancel machinery (NEW — the patch surface)
| Address | Label | Comment |
|---|---|---|
| $C1:0224 | set_action | universal action setter (A = new actionID); all $1001 writes at $C1:022C |
| $C1:04DA | anim_advance_or | A=next action; returns A = step tick ($06,X) if ≥0, else switches action |
| $C1:04E8 | own_projectile_alive | carry set if $1100/$1180 object active |
| $C1:0952 | cmd_cancel_commit | requires connected flag $43,X≠0; reads pending cmd $51/$53,X nibble; flags word from table[Y]; commits table action via $0224. Entry $C1:0958 skips the connected check (neutral states) |
| $C1:7B25 | uranus_cancel_tbl | words [flags, action]: slots→ 0x26 backdash, 0x60 dash, 0x61/0x62, 0x72 super, 0x67/0x68; flags: 1=ground, 2=air, 4=no-own-projectile, 8=desperation(HP≤0x18, skipped in training mode $8D==4) |
| $C1:871C | uranus_2HP_handler | step-0 inits dmg7/atkID4/str8/flags $44, clears $43; running: jsr $04DA(→0x56), ldy #$7B25, jsr $0952, jsl $80BFBB |
| player+0x43 | attack_connected | cleared at attack start, set on connect; gates hit-confirm cancels (NOT hitstop) |
| player+0x51/0x53 | pending_cmd | command slot nibble from the 66/motion recognizers; expires in ~2-3 unfrozen frames |
| $C1:BE0E-BE47 | free_space | 58 zero bytes between data blobs; 20k-frame read-watch: never accessed. PATCH STUB at $C1:BE20 |

## PATCH (shipped): build/sms_uranus_infinite_1f.bps
0x1874D/E: jsr $0952 → jsr $BE20; stub at 0x1BE20: sep #$20; cmp #$04; bcs rts; jmp $0952.
Gates 2HP command-cancel on step tick < 4 = dash-out +6 frames = 1f-link loop.
Full derivation, changed bytes, and verification matrix in patch_notes.md.

## Reversal-dash invincibility bug (NEW — root-caused and patched)
| Address | Label | Comment |
|---|---|---|
| player+0x46 | hurt_state | 0xA0 = untargetable (set on knockdown by $C1:0F8D writer); hit-check skips defender while set |
| $C1:88C8 | uranus_fdash_handler | act 0x60; step-0 init MISSING the engine-standard `stz $46,X` (Moon's dash has it; all attack handlers have it) → reversal dash keeps knockdown invuln |
| $C1:7F1A / $C1:7D2F | clears of +0x46 | landing (act 09) and neutral handlers clear it — why the bug only spans the dash itself |
| $C1:0389 | set_xspeed | rep #$30-safe helper; dash calls it with 0x0B00 (11px/f) |
| $C1:BE2A | dashfix stub | jsr $0389; sep #$20; stz $46,X; rts (patch 2) |
Backdash (0x26) invuln is by design via script hurtbox idx 0 — unrelated mechanism.
Patch 2 = build/sms_dashfix.bps (stacks with patch 1 via .ips or sms_both.bps); see patch_notes_dashfix.md.

## Box-index writer + dash i-frames (patch 6, OPTIONAL)
| Address | Label | Comment |
|---|---|---|
| $C0:9CA4-9CE1 | box_writer_batch | per-frame loop over objects X=0x1000..0x1180 (+0x80); reads 4-byte anim-frame entry via ($10),Y [Y=+0x05*4], writes +0x18/+0x40(hitbox)/+0x41(hurtbox)/+0x42(collbox) |
| $C0:9CCD | sta $41,X | THE hurtbox-idx write. Empty hurtbox idx 0 = invulnerable (how backdash/anims get i-frames) |
| player+0x5D | dash frame ctr | the 66-recognizer timer; runs 1..14 across a forward dash (act 0x60) — usable as the dash frame index |
| $C1:BE85 | dashinvuln stub | patch 6: hook 0x9CCD → jsl; for Uranus(+0=6) fwd-dash(+1=0x60) with +0x5D in window, stz +0x41 (empty hurtbox = strike i-frames). Off by default. |
Patch 6 = build/sms_dashinvuln.bps (strike-only mid-dash i-frames, ~frames 5-10, tunable --lo/--hi); see patch_notes.md "Patch 6".

## Palettes + title (patch 3) — Big Zam extraction
| Address (file) | Label | Comment |
|---|---|---|
| 0x884B | pal_load_1P hook | sprntgd PATCH_PAL 1P palette-map redirect |
| 0x8998 | pal_load_2P hook | 2P palette-map redirect |
| 0xA630 | charsel_confirm hook | JSL $E8:000A palette-select + default-stage-select |
| 0x280000 ($E8) | pal code+data block | code @0x28000A; per-char palettes @0x281000+0x1000*id; slot=0x80 [flag,pad,icon@8,char@10,proj@30] BGR555 |
| 0x2A0000 (Big Zam) | BZ palette donor | slots 2-11 = 10 extras/char extracted for our patch |
| 0xFFC0 | header title | "…S FrenchName " (11 chars) |
Selection: face button confirms + picks color (A=0,B=1,Y=2,X=3; L+ =4-7; R+ =8-15; Start+ =16-31).
Bundled random-stage-default rider kept as-is. Build: tools/mkpatch3.py. Notes: patch_notes_palettes.md.

## Title-screen graphics (investigated, NOT patched)
Title BG1 tilemap @VRAM word 0; subtitle = tiles 0x10D-0x15F (rows 13-14); credit block =
baked graphic tiles 0x0C1-0x11C (rows 23-26), NOT a reusable font. Title gfx LZSS-decompressed
by $C0:916B (src longptr DP$00, dst DP$03); subtitle blob src=C41660->7EA000 (identical clean/BZ).
BZ overlays custom letter tiles via its custom code region (file 0x1E38-0x4CAC). On-screen text =
from-scratch graphics hack; deferred. Header-title identification shipped instead.

## Title-screen subtitle patch (patch 4)
| Address | Label | Comment |
|---|---|---|
| $C3:B81F (file 0x3B81F) | title_load_tail | JSL $80:8C43 (DMAs all title gfx to VRAM) then PLB;RTL — hook site |
| $80:8C43 | title_gfx_dma | performs the VRAM DMAs of loaded title blocks |
| $C0:916B / $919F | lzss_decompress | title CHR LZSS; subtitle blob src C41660 -> WRAM $7E:A000 staging (identical clean/BZ) |
| VRAM CHR base | word 0x2000 | BG1; tile T CHR at VRAM word 0x2000 + T*16 (tile 0x10D -> 0x30D0) |
| subtitle tiles | 0x10D-0x10F,0x11D-0x11F,0x120-0x12F,0x130-0x13F,0x140-0x141,0x150-0x151 | 42 tiles, rows 13-14, palette 0 (idx1 red / idx2 pink / idx3 white) |
| appended bank $E8/$E9 | title stub+tiles | 195B DMA stub (calls $808C43 then 6 DMA runs) + 1344B custom tiles |
Text "FrenchName ver. 0.4" white-core/red-outline. Build: tools/mkpatch4.py + tools/texttiles.py.
Mockup-validated (subtitle band pixel-identical). Notes: patch_notes_title.md.

## Forward-dash distance (patch 5)
| Address | Label | Comment |
|---|---|---|
| $C1:88E9 (file 0x188E9) | dash_xspeed | LDA #$0B00 (11.0px/f) -> patch5 LDA #$0480 (4.5px/f); neutral dash 121px->59px |
Dash duration (14f) is state-driven, not velocity — halving speed halves distance while
keeping ALL frame timing, so the 2HP>66 infinite is preserved exactly (dash stops on
contact in the loop). Byte-disjoint from patch 2's reversal hook (0x188ED/EE). Backdash
(0x26, separate handler) unchanged. Build: tools/mkpatch5.py. Notes: patch_notes.md / patch_notes_title? -> patch 5 section.
Demo of the frame-perfect 1f-link infinite: tools/demo_infinite.lua (GUI playback).

## Pluto 5HP hitbox (patch 7, OPTIONAL)
| Address | Label | Comment |
|---|---|---|
| $8A:F0C1 | pluto_hit_table | Pluto's hitbox table (file 0xAF0C1); box N at +N*8, fmt [x_off_r,w_r,x_off_l,w_l,y_off,h,flags,?] |
| hit[0x03] | pluto_5hp_active | 5HP overhead active phase (act 0x46); y_off=-109 h=54 -> spans -109..-55 (high, whiffs crouchers). Exclusive to 5HP. |
| file 0xAF0DE | 5HP box height | patch 7 raises 54->62 (bottom -47) => hits all crouchers except Chibi (crouch top -46); 64 = incl Chibi |
5HP is two phases: act 0x44 startup (boxes 01/04/14) -> act 0x46 active (box 0x03). Crouch
hurtbox tops (y): Mars -60, Uranus -59/Pluto -59, Neptune -58, Moon -56, Mercury/Jupiter -54,
Venus -49, Chibi -46. Patch 7 = build/sms_pluto5hp.bps; see patch_notes.md "Patch 7".

## Throw / throw-tech machinery (patch 8 research — closes the "throws unmapped" gap)
| Address | Label | Comment |
|---|---|---|
| $C1:0612 | throw_connect | on grab: victim +0x01=0x1C (Held), victim +0x46=0xA0, thrower +0x46=0xE0, victim +0x06=0x80, +0x30..35/+0x02 cleared; ~8-frame engine freeze follows |
| $C1:06E5 | throw_script_interp | runs a throw-hold script: 8-byte entries indexed by thrower +0x07 (steps by 2 per anim step). Entry: [victim_pose, drag_x lo/hi, drag_y lo/hi, byte5, byte6→thrower+0x78, swap_flag]. byte0=0xFF marks a header entry → toss path $C1:07E5 (byte1-4 = toss x/y velocity, byte5 = damage) |
| $C1:07CF | tech_sampler | per non-frozen frame of hold steps with entry byte5≠0: if victim +0x50 & 0xF0 (fresh attack press, latched at 30Hz) → inc thrower +0x56 (mash counter) |
| $C1:0823 | toss_decision | thrower +0x56 >= 2 → victim act 0x23 (tech) + HALF damage (lsr), else act 0x1D + full damage. Threshold global; per-throw variance = sampling steps only |
| +0x56 (thrower) | mash_counter | zeroed by the per-char hold handler at throw start (Venus: $C1:772C `stz $56,X`) |
| $C1:770F | venus_throwhold_handler | act 0x58 (hold) state proc; script `ldy #$6C53 / jsr $06E5`; act 0x59 = toss |
| $C1:6C53 (file 0x16C53) | venus_throw_script | header (dmg 0x16=22, toss vel) + hold entries 1-5 (steps 02-0A). byte5=01 on entries 1,2 only → 6f sampling window (t=61,70-75). Patch 8: entry3 byte5 (file 0x16C70) 00→01 → 13f (t=61,70-82) |
| $C1:5A07 (file 0x15A07) | jupiter_throw_script | standard reference: entries 1,2 sample but steps are longer → 15f window (t=61,70-84); toss headers at $5A67/$5A77 (dmg 0x1C=28) |
All `ldy #$imm / jsr $06E5` throw-script call sites in bank $C1 (one per char/throw):
Moon $2884/$28AC, Mercury $38EE/$3916/$3926, Mars $4925/$495D/$496D, Jupiter $5A07/$5A3F/$5A67/$5A77,
Venus $6C53, Uranus $7B59/$7B81 (+specials $7BB1..$7C39), Neptune $8F19/$8F41 (file = 0x10000+addr).
Tools: tools/techsweep.lua (window/threshold measurement), tools/techfind.lua (instrumentation).

## In-match HUD rendering (patch 10 RE, 2026-07-16)
| Address | Label | Comment |
|---|---|---|
| $C0:D5E8 (file 0x00D5E8) | hud_producer | main-loop HUD tick, **scanline 101, once/frame (0 misses/200f)**: animates displayed HP $0800/$0801 toward struct HP $1049/$10C9, computes bar+timer tiles into WRAM staging $0806-$0815, decrements timer $0802. First bytes `C2 10 E2 20` (rep#$10;sep#$20). |
| $C0:D56F (file 0x00D56F) | hud_uploader | **NMI/vblank, scanline 237**, called via JSL from NMI ($E0:D4xx): flushes staging entries ($0806/$080A/$080E, each = VRAM addr + tiles) to VRAM port $2116/$2118, zeroes the addr after. First bytes `C2 30 AD 06 08` (rep#$30;lda $0806). |
| $7E:0800 / $0801 | disp_hp_p1/p2 | displayed HP (drains toward struct HP); written only by hud_producer $C0:D5FD/$D643 |
| $7E:0802 | timer_bcd | round timer; decremented at $C0:D68D |
| $7E:0806-$0815 | hud_stage | staging: $0806/$0808 P1-bar (addr,tile), $080A/$080C P2-bar, $080E-$0815 timer (2 digits × top/bottom) |
| $7E:0816-$08FF | FREE WRAM | HUD page tail, **zero accesses** over probe — patch-10 combo state + staging |
| digit tiles | 0x2C50+N (top) / 0x2C60+N (bottom) | big 2-tall digits 0-9, palette 0x2C, in BG1 HUD CHR; timer draws them via `adc #$2C50`/`adc #$0010` |
| HUD tilemap | VRAM word $1000 base | rows 3-4 HP bars, row 5 nameplates, timer at cells $10AF/B0 (top) $10CF/D0 (bottom); **rows 0,1,2,7 and most of row 6 are blank (tile $2000)** — free cells for a combo counter |
Combo/status counting logic proven in tools/training/{combo,labels}.lua (reads +0x01 act, +0x49 HP; true-chain = defender never actionable between hits). Probes: tools/probe_hudre/hudnmi/upl/ctx/vram.lua.

## In-match status labels (patch 10 --events labels)
| Item | Value | Comment |
|---|---|---|
| BG3 CHR base | word $5000 | HUD is BG3, 2bpp (mode 1); tile T CHR at word $5000+T*8 |
| glyph CHR slots | tiles 0xC7-0xDF | free (zero across 5 matchups); patch-10 uploads the label font here, tilemap word = 0x2C00|tile |
| nameplate font | A=0x70..Z=0x89 | fixed tile-id layout BUT glyphs are matchup-loaded; **G(0x76) is in no character name** — hence a custom uploaded font |
| digit tiles | 0x50-0x59 top / 0x60-0x69 bottom | big 2-tall HUD digits (timer/combo counter) |
| label state | $0900 (P1) / $0908 (P2) | prevAct,conRec,hardRec,movePhase,hpShadow,labelId,labelTTL,shown (8 bytes) |
| glyph-load flag | $0910 | re-armed when both labels idle (survives per-match CHR reload) |
| label glyph staging | $0920 (L) / $0940 (R) | dirty + 8 tile words |
| label tilemap cells | $10E5-$10EC (L) / $10F2-$10F9 (R) | row 7, disjoint from combo-counter cells |
| free WRAM | $0900-$09FF | zero accesses over 400 active frames — patch-10 label scratch |
Detection mirrors tools/training/labels.lua (GC/MEATY/REVERSAL/PUNISH/TECH); runs in the
producer stub $C0:D5E8 (no new hooks). Perf: +2.62% CPU, frame-identical (zero lag). Tools:
tools/hudfont.py (glyphs), tools/test_labels.lua (oracle), tools/perf_patch10.lua (lag suite).

## Native training mode (patch 11 RE, 2026-07-16) — all verified on clean ROM, Mesen headless

| Addr / fact | Meaning |
|---|---|
| $7E:1B10 title menu | **2 cols x 3 rows** (nav table $C0:A29D+cursor*4 confirmed): left col 0/1/2, right col 3/**4=Practice**/5. Reach Practice: down (0->1), right (1->4). The old "6 vertical entries" reading was wrong. |
| $7E:008D values | VS 1P-vs-2P match = **01**; native training = **04**; attract demo = **05**; training w/ damage = **05**. Poking $8D 4->5 mid-match enables damage (vendor semantic CONFIRMED on this game). |
| mode 4 hit rule | Hits fully connect in mode 4 (attacker +0x43 latch set, defender hitstun act 0x12, hitstop 8) — **only the HP subtraction is gated**. Mode 5 = same + damage. Blocks/combos/throws all work natively in 4. |
| $7E:0070 | = **4 while in any match** (VS and training), 0 outside. In-match qualifier for gates ($008D alone is ambiguous at training char-select, which is already mode 4). |
| $7E:01FA | 0x80 = match running; **0xE4 = movelist open** (Start toggles it). **Select exits the training match** (~60f fade, $0070->0). |
| L / R shoulders | **No observable effect in-match** (WRAM-diff clean) — free as patch-11 menu trigger. |
| HUD producer $C0:D5E8 | **NEVER executes in a training match** (mode 4 or 5): no HUD drawn, no timer decrement ($0802-04 stay 0), no bar latching. Patch-10's counter therefore never rendered in training. Uploader $C0:D56F DOES run every frame (NMI, scanline 237 — same NMI as joy_read $80:8353, joy first). |
| TM ($212C) | Training match mainScreenLayers = **0x13 (BG3 off)**; VS = 0x17. Game writes TM only at scene setup (0 writes over 40f in-match). CGRAM identical to VS (HUD palettes loaded, BG3 pal 3 usable); BG3 digit CHR loaded; free window 0xC7-0xDF all-zero. **To show BG3 UI in training: force TM=0x17 during vblank while visible, restore 0x13.** mode1Bg3Priority=1, BG3 scroll 0/0. |
| BG3 tilemap in mode 4 | Rows 8-15 write-test survived 160f of fighting (game never writes them in-match); rows 9-16 hold invisible stale cells (BG3 off) — safe to overwrite; on exit the game wipes the map to zeros. |
| KO in mode-5 training | hp=0 -> KD acts -> act 0x1F at ~+66f; **no round-end flow ever fires** ($0070/$008D unchanged, game runs on). KO-refill can act any time during the KD. |
| Injection @ $80:8373 | Overwriting P2 held word $5E/$5F at the point after joy_read stores held words but before edge calc: game derives press edges itself next frame (**no need to touch $60-$67**); +0x50 latch follows at 30Hz; down-back blocks; alternating HK yields fresh presses every 2f; back/neutral/back fires the 44 backdash (act 0x26) on wakeup — **no action force-writes needed**. |
| Bank $7F | Boot clears all 64K once; scene-load/round-intro uses **$7F:0000-5FFF**; steady-state match traffic ZERO. **$7F:F000-$7FFF = patch-11 state home.** |
| WRAM $0816-$09FF | Heavily touched in native training (the VS-mode zero-access result does NOT transfer). Do not use for training-mode state. |
| traces/training_p11.mss | Clean-ROM native training match savestate (Uranus vs Jupiter, mode 4), made by tools/probe_p11_nav.lua. |

## Special-move dispatch & the misfire/ochame mechanic (patch 12 RE, 2026-07-17)

| Addr / fact | Meaning |
|---|---|
| $C1:0B49 | **special-move dispatcher**: entered with X = fighter struct, Y = the special's 8-byte record (bank $C1, read via phk/plb). Runs for EVERY recognized special. |
| special record layout | +0 attackID, +1 variant (0=LP 1=HP), +2/+3 ?, +4/5 ?, **+6 = misfire act ID** (0 = this special can never misfire), +7 strength-ish. Records found at e.g. Neptune $C1:9DF6/9DFD, Chibi $C1:BDF0/BDF7. |
| the ochame roll | in $C1:0B49: if record+6 ≠ 0 and fighter +0x75 (ochame) ≠ 0: `Y = $90 & 15; if table[$C1:0AF5 + Y] < ochame → MISFIRE`. On misfire: act word $00 |= 0xFF00 (marker), and the ACT SET is simply record+6 via $C1:0224 (`sta $01,X / stz $02,X`). Roll verified live: ochame=0xFF makes ~1/3 of Neptune 214LP whiff into act 0x66. |
| $7E:0090 | **RNG byte** (low nibble consumed by the misfire roll). |
| $C1:0AF5 | 16-entry misfire threshold table (indexed by rand&15, compared against ochame). |
| misfire acts (per char, LP-version = record+6 of the first special) | Moon **0x6A**, Mercury **0x65**, Mars **0x66**, Jupiter **0x63**, Venus **0x5F**, Uranus **0x65**, Neptune **0x66**, Pluto **0x62**, ChibiMoon **0x63** (HP variants = +1; Mars also 0x6C, Venus also 0x65/0x66 on her 2nd special). Chibi's matches the vendor tool's "Chibi 63-64 Misfire" note — cross-validated. |
| misfire act behavior (forced from standing, all 9 audited) | plays the fizzle anim then chains into 0x2A (embarrassed) then neutral, ~103-113f total, no hitbox — EXCEPT **Jupiter (0x63/0x64): her fizzled thunder has a real attack box** (authentic native behavior; her taunt can hit point-blank). Universal fallbacks: 0x2A = 71f embarrassed; 0x27 = 132f slip→down→standup→embarrassed. |
| $008D = 2 | **1P-vs-COM match** (new mode value; $0070==4 there too). CPU-driven pads carry no L/R bits (900f watch) — an L-triggered feature needs no mode gate. |

## Damage application & round flow (patch 13 RE, 2026-07-17)

| Addr / fact | Meaning |
|---|---|
| strike/chip damage apply | **8 identical sites in bank $C0** (one per on-hit-table variant), file offsets 0xC09C, 0xC16F, 0xC216, 0xC2C5, 0xC47E, 0xC551, 0xC5F8, 0xC6A7: `lda $0049,Y / sec / sbc $00 / sta $0049,Y / cmp #$90` — Y = defender struct, **damage staged in DP $00**, D register = 0 at all sites (absolute $0000 reads it). Observed mapping: 0xC16F = stand-hit, 0xC09C = crouch-hit, 0xC216 = blocked-melee (chip=0 but still flows through), 0xC47E = projectile hit, 0xC6A7 = projectile chip. |
| chip damage | EXISTS for specials: blocked Deep Submerge chips 2 (vs 8 on hit); **blocked normals chip 0** (the value in $00 is 0, the apply site still runs). |
| throw damage apply | full: `$C1:082F` (`lda $0049,Y / sec / sbc $05` — damage in **DP $05**; cmp #$90 BEFORE sta); teched: `$C1:084D` (`lda $05 / lsr / eor #$FF / inc / clc / adc $0049,Y` = add negated half). Mode-4 skip checks `$8D` just above each. |
| $C0:D055 / $C0:D081 | executes **once per landed hit**; the 16×16 matrix is (evidence) a **damage-variance table** — identical 2LP dealt 1..6 damage across RNG phases (fixed input timing = deterministic rolls, which is why suites see stable values). ACS stats +0x70/+0x71/+0x48 pokes showed NO effect distinguishable from this variance at damage time. |
| VS round transition | KO -> defender 0x1F, winner victory act 0x24 (~+300f), then **both structs re-init on the SAME frame: both hp -> max AND both acts -> 0** (that pair is the round-reset signature; no intro act plays). `$0070/$01FA/$008D` unchanged across the whole transition. `$080C` incremented 0->1 on P1's round win (round-win counter candidate; $080D 00->0x60 alongside). |

## Patch 13 v3 addenda (2026-07-17)

| Fact | Detail |
|---|---|
| attack-class at +0x44 | lights 0x00-0x03, heavy normals 0x04-0x07, specials 0x08/0x0C, supers/desperations >=0x12; projectile slots carry their own +0x44 (fireball = 0x08). The 8 damage-apply sites split: 0xC09C/0xC16F/0xC216/0xC2C5 = melee paths, 0xC47E/0xC551/0xC5F8/0xC6A7 = projectile paths. DP $02 at apply = hitstun (not a class flag). |
| ACS +0x73 buff_special | REALLY scales special damage: Neptune 214LP 8 -> 10/14/16 at stat 1/3/7 (values >7 misbehave; boost-only from the VS default 0 — cannot nerf below baseline). +0x74 (secret) showed no effect on a regular special (presumably desperation-only; untested). |
| third throw-damage site $C1:0D61 | per-tick HOLD throws (Moon 4x5, Mars 12x2, Chibi) drain HP here; standard toss throws use $C1:083C/$C1:085E (Mercury/Jupiter/Venus/Uranus/Neptune). Pluto's grab did not trigger with fwd+HP in the census (unresolved). |

## A.C.S. stat system — decoded (2026-07-18; **full reference: docs/sms_acs_system.md**)

**CORRECTS the earlier "ACS stats show no damage-time effect" note (patch 13 RE) — that
sweep was drowned by the damage variance; reload-per-sample methodology shows real effects.**

| Var | Name | Measured effect |
|---|---|---|
| +0x70 | buff_attack | boosts the owner's **NORMAL** damage (jab 2 -> 3 @1-3, 4 @7); no effect on specials |
| +0x71 | buff_defense | reduces **ALL** damage the owner takes (jab 2 -> 1 @3; fireball 8 -> 5 @3, 4 @7) |
| +0x72 | buff_health | no live effect on damage taken; presumed load-time max-HP (untested at char load) |
| +0x73 | buff_special | boosts the owner's **SPECIAL** damage (fireball 8 -> 10/14/16 @1/3/7); no effect on normals; values >7 misbehave |
| +0x74 | buff_secret | no effect on regular specials (presumed desperation-only; unverified — no scripted desperation trigger yet) |
| +0x75 | buff_ochame | misfire chance via threshold[$C1:0AF5 + (rand&15)] < ochame |
| +0x48 | first_hit_defense | from the char manifest; earlier sweep showed nothing above variance (re-test with controlled method pending) |

**The damage formula, unified ($C0:D055/D081):** `final = matrix[base_damage_class][8 + modifier & 15]`
— the 16x16 matrix at $C0:D081 has rows = base damage (row max ≈ 2x base at col 0,
decaying to ≈ base/4 at col 15), **column 8 = neutral**, each column ≈ ±12%. The modifier
mixes the RNG jitter (the per-hit variance) with stat shifts: attacker's +0x70 (normals)
or +0x73 (specials) shift LEFT (stronger), defender's +0x71 shifts RIGHT (weaker).
Stats cannot push damage below the row's column-15 floor or above the column-0 cap.

**Ochame threshold table $C1:0AF5** = `00 01 02 02 03 03 04 04 FF FF FF FF FF FF FF FF`
(indexed rand&15; entry < ochame -> misfire). Effective ochame range **0-5**: rates
6.25% / 12.5% / 25% / 25% / 37.5% / **50% (cap — half the slots are 0xFF, never-misfire)**.

### Throw-toss apply site (patch 13 v3.2)
- `$C1:082F` (file 0x1082F) — full-throw toss damage apply: `lda $0049,Y / sec / sbc $05`
  (identical shape+conventions to the tick site $C1:0D54; Y = victim struct, damage DP $05,
  D=0). Fires once per completed throw; thrower +0x44 at that moment = 0 for every normal
  throw, 0x18 for Uranus's desperation toss (the only desperation using this path) —
  the class byte is the discriminator patch 13 v3.2 gates on.
- Desperation act chains / classes (probe_p13f_desp, clean ROM): Moon 6D-70 (proj 48),
  Mercury ..6F strike 48 @0x12, Mars 74-75 proj 32, Jupiter 72-74 strike 48 @0x14,
  Venus 69 strike 37 @0x12, Uranus 71-79 rush(18×1-2,+10)+toss 32 @0x18 = 67 (51 vs
  crouch: fewer rush hits connect), Neptune (input 6236236HP) 70-73 strike 37 @0x12
  hp-gated (the 236236 chain 69-6F is her regular ungated super, 19 @0x08/0x0C),
  Pluto 6A-6C strike 3 + 12 drain ticks 45 @0x18, Chibi 6B-6D air proj 7×6-8 = 52.
  Crouch-defender damage: strikes UP via the crouch on-hit tables (Merc/Jup 48→62,
  Venus 37→48, Pluto opener 3→4, Neptune 37=), projectiles per-hit unchanged, multi-hit
  moves lose hits (Uranus 67→51, Chibi 52→24). Full table: sms_acs_system.md §6b.
- Posture-not-hitbox: defender posture state at impact selects the on-hit table variant
  (CDD5/CE15…D015). Head-box damage bonus REFUTED (Moon's desperation projectile poked
  to forehead/torso/shin flight heights of a standing defender: 48 at all three; Uranus
  rush per-hit values identical stand-vs-crouch). Air hits = stand-class value
  (Merc/Jup 48 on rising defender); PREJUMP (act 0x05) = crouch-class (Venus 48 not 37).
  Venus desperation has an anti-air projectile-path component (act 0x6A, 37).

### Counter-hit + hit-zone probes (probe_hitzone.lua)
- Counter-hit bonus: defender inside an attack/misfire act at impact -> ~+33-50% damage
  (col shift), flat through startup+recovery of that act; expires at act 0x2A chain.
  Roll-matched pairs: 8/10->12/14, 7/9->11/12, 6->9 (taunt act 0x6A, depths 15f & 25f).
- No head/body damage split: ALIFT rig (pin attacker y to ground−N during the swing)
  moves contact 12/24px up a standing defender -> identical damage, same roll.
- Uranus proximity 5HP: far act 0x43 dmg 8/10; near act 0x45 dmg 9/12 (range<=34).
- Melee apply-site selection is per-(attack, defender posture): Uranus standing normals
  -> C09C-site (write pc 80C0A5), her crouch normals vs standing defender -> C16F-site
  (write pc 80C178), crouch-vs-crouch -> C09C; Moon/Jupiter 5HP -> C16F.
- Moon 5HP (mirror, moon_vs_moon) deterministic 6 at this rig's fixed timing.

### Desperation punish damage (probe_p13f_desp DTAUNT rig, v0.16 L0)
- Counter-hit on desperations (defender mid-taunt-act): Moon 48->72, Mercury 48->72,
  Mars 32->48 (projectile path counters too), Jupiter 48->72, Venus 37->62,
  Neptune 37->62, Uranus 67->67 (rush opener at row floor; rest hit hitstun),
  Pluto 48->50 (opener 3->5; drain ticks immune), Chibi 52->54 (first barrage hit
  8->10). First-hit-only rule: hitstun acts 0x11/0x13 are not counter-eligible.
- RESOLVED: the damage matrix is 64x16 (file 0xD081-0xD480, cap 0x48=72), not 16x16.
  Live reader = 16-bit load at $80:D07B (the $D055 routine executes from BANK $80 —
  exec-watch $80:D055 not $C0:D055). Row 48 = shared single-hit desperation row;
  per-move base columns: Jup/Merc/Moon c8(48), Venus/Nept c9(37), Mars c10(32).
  Counter-hit = exactly -2 columns; crouch defender = -1 column (desperations);
  desperation hits show no RNG column jitter.
- Consolidated damage reference: docs/sms_damage_system.md.

### ACS defense scope correction (maintainer review, 2026-07-18)
- +0x71 buff_defense reduces MATRIX-path damage only. Verified at defense 7:
  normal throw toss 20 -> 20 (unchanged); Pluto desperation opener 3 -> 1 (reduced)
  while all 12 drain ticks byte-identical (45). Throw toss/tech/ticks bypass $D055.

### Command-grab specials (SPDs) + column wrap (2026-07-18)
- Uranus SPD 6321478HK: acts 68/6A/6C/6E/70/71, grab at ~t+2, single TOSS 32 at
  $C1:082F with thrower +0x44 = 0. Jupiter SPD 6321478HP: acts 6E/70/71, airborne
  carry (victim y -72px) draining 5 ticks x6 = 30 via $C1:0D54, holder +0x44 = 0.
  Probe input needs 2f/step (3f -> a normal comes out). Immune to ACS defense 7 and
  to Guts L3 (class gate can't see them) -- byte-identical verified.
- Column wrap: (mod+8)&15 has no clamp ($80:D062). Defense 7 on a weak-rolled heavy
  (col >= 9) wraps to col 0-1: measured 8 -> 23 roll-matched. Safe defense range <= 6.

### Input recognizers (2026-07-19)
- SPD/360: set-detector — all 4 cardinals within ~20f, any order, LAST must be up(8),
  button may follow on neutral (buffered). Diagonals irrelevant. 6248 = minimal SPD.
- Desperations: strict ordered matcher incl. diagonals (any drop -> normal comes out),
  trailing extras ok, per-step timeout ~12-15f (Pluto full input works spread over 72f).
- Uranus normal throw = hold-type (tick path, ~22 total), unlike Neptune/Moon tosses.

### Desperation chip (2026-07-19)
- Chip = hit/4 floor-1 per connecting hit through the normal matrix sites (blockstun
  acts 0C/0E at write). Moon desperation = flagged NO-chip (0, write skipped; blockstun
  t33-164). Multi-hit-on-block: Jupiter 1->3 (36 chip), Mars 1->4 (32 = full). Uranus
  rush has LOWS: standing block collapses (66+grab), crouch-block holds (11, no grab).
- Pluto Dimension Danse = STRIKE-THROW confirmed: blocked (either guard) -> 1 chip,
  grab never triggers (cinematic gated on the opener CONNECTING).

### Special-move record tables — full dump (2026-07-19)
Per-char misfire-capable specials, bank $C1, 7-byte records
[attackID/class, variant(0=LP-ish,1=HP-ish), b2-b5 payload, misfire act]. The record+0
index is GLOBAL and doubles as the move's +0x44 attack class. SPDs, supers and
desperations are NOT in these tables (separate recognizers); trailing 6-byte 0x31-0x33
records are a different (universal?) structure, unmapped.
- Moon    @C1:373E: idx 0A (6A/6B), 0B (6C/6C), 0C var0-only (no misfire)  -> 3 specials
- Mercury @C1:4778: idx 0E (6B/6C), 0D (65/66)                              -> 2
- Mars    @C1:5851: idx 0F (66/67), 10 (6C/6D), 11 var1-only (no misfire)   -> 3
- Jupiter @C1:6AD0: idx 12 (63/64), 13 (69/6A)                              -> 2
- Venus   @C1:79BD: idx 14 (5F/60), 15 (65/66), 16 var0-only (no misfire)   -> 3
- Uranus  @C1:8D6A: idx 17 (65/66)                                          -> 1
- Neptune @C1:9DF6: idx 18 (66/67)                                          -> 1 (Deep Submerge 214P, presumed)
- Pluto   @C1:AE33: idx 19 (62/63)                                          -> 1
- Chibi   @C1:BDF0: idx 1A (63/64), 1B var1-only (no misfire)               -> 2
NOTE: outer-senshi special classes 0x17-0x1B sit INSIDE the >=0x12 band previously
labeled 'desperations' — the class taxonomy is really 'high specials+desperations'.
MISFIRE_SETS in mkpatch12/13 was harvest-limited: tables add Moon 0B/0C, Mercury 0E,
Mars 10/11, Jupiter 13, Venus 16, Chibi 1B beyond the harvested sets.

### Uranus movement + 2HK (2026-07-19, LOGFD rig)
- Forward dash (Shadow Dash, 66): act 0x60 (character-special act space), 14f + 5f skid
  (act 09), ~149px gross at ~10.6 px/f, dash hurtbox idx 0x4F (vulnerable).
- Back dash 44: act 0x26 (universal), 14f, -36px, hurt idx 0x00 ALL 14 frames
  (fully invulnerable) - patch-2/6 fact trace-confirmed.
- 2HK slide: act 0x59, startup 8f, active hb idx 0x0F ~38f, slide +67-79px, low,
  knockdown, hurtbox idx 0x39 (low profile) during; dmg rolls 8 (wiki 10).

### Neptune kit (2026-07-19)
- Deep Submerge 214P: acts 62/64 (LP) 63/65 (HP), dmg 8/10 (wiki exact), rec idx 18.
- Splash Edge 623P: DP, NOT dispatcher-recognized (no REC fires — like SPDs/desps).
  LP act 68: 3f startup, INVULN (hu=00) frame 1 through actives, 1 hit. HP acts 69->6B:
  4f, invuln phase 1, 2 hits 11+8; rising phase vulnerable (hu 3C). Resolves the old
  '236236 super' = sloppy Splash Edge HP.
- Neck Throw 4/6HP: toss 20 acts 5D-5F, techable, AIR version identical (verified x3).
- c.HK: 2 hits acts 4A/4B, hit2 OVERHEAD (crouch-block opened, 13 = wiki faceHit —
  that column = vs-crouch posture value). Blockstun acts: 0C stand, 0D crouch-block,
  0E stand-2nd, 0F crouch-hit... (taxonomy growing).
- Dragon Rise: deterministic 37 (r48c9) all ranges, chip 9 single; wiki 48 / 12x2
  unreproduced (adjacent columns + unknown second chip) — flagged.

### Jupiter kit (2026-07-19)
- Supreme Thunder [4]6P: rec idx 12, acts 61/62, charge 25-39f min, proj 13/16, KD.
- Coconut Cyclone j.632P: rec idx 13, NO hitbox in flight — ground-impact only
  (hit at floor height, ~140px out for HP), 12 dmg, hugely plus (wiki +34~+59).
- Giant Swing 6248P: LP carry act 0x6F 4x6=24 (range 64), HP 0x70 5x6=30 (56).
  LP act was missing from p14 GRAB_ACTS -> fixed v0.19.
- Double Axel 236K: acts 6B/6C, 3f/5f startup, STEERABLE ~±1.5px/f holding 4/6
  (neutral = stationary), spin hurtboxes 44-48 top at -34px vs -76 standing = upper
  half invulnerable (dodges all measured fireballs).
- Supreme Thunder flies at -68px: whiffs ALL crouchers (crouch tops max -60, Mars) —
  crouch avoids it entirely, verified vs Venus.
- Power Bomb c.4/6HP: toss 28 techable (air version per wiki; rig got j.HP x3).
- Lightning Strike chip: wiki 12x3 = our 3x12 blocked measurement, exact convergence.

### Fireball guard levels (maintainer QA, 2026-07-19)
- World Shaking: blocks BOTH standing and crouching (chip 2 each; dact 0C/0D) despite
  the ground-wave sprite; hits crouchers 9. Mid/any — 'hits low' folk memory refuted.
- Deep Submerge: arc descends (-62px contact at range 40 -> -30px at 110); Mid at all
  ranges (stand/crouch block + crouch contact all normal). 32px contact swing, same 8
  damage = more contact-zone-irrelevance evidence.

### Pluto kit (2026-07-19)
- Dead Scream 41236P: rec idx 19, LP act 60 traveling 12; HP act 61 STATIC ~80px ahead
  (whiffs <=22px), 14, alive 50f+ (wiki 53 active / 82 recovery).
- Strict Sweep [4]6K: acts 65->66/67, TRUE overhead both (crouch-guard fails), moves
  +138px, active-phase hurtboxes -113..-71 = LOWER-half invulnerable (lows whiff).
  No dispatcher REC (charge moves = non-dispatcher family like DPs/360s... except
  Supreme Thunder WAS rec idx 12 — so charge != non-dispatcher universally; Strict
  Sweep specifically fires no REC).
- Throw c.4/6HK: HOLD-type 5x4=20 (wiki 22), act 5C, untechable. 5th hold-thrower.
- c.HP: stand-block blocks; plain-crouch Moon hit 14; crouch-BLOCK Moon WHIFFS (guard
  pose lowers hurtbox!); crouch-block Mars full hit (true overhead). Patch-7 target.
- Blockstun/guard-pose taxonomy: crouch-guard pose hurtbox != plain crouch hurtbox,
  per character.

### Death rule + Pluto prose round (2026-07-19)
- DEATH = HP UNDERFLOW, not zero: chip 1 vs hp 1 -> 0 and ALIVE (normal blockstun);
  chip 2 vs hp 1 -> 0xFF -> KO chain (dact 1A->1E->1F + corpse-hp zeroing write).
  Chip kills iff chip > hp. 0-HP survivor dies to any next hit incl. chip 1.
- DS LP whiffs point-blank too (verified 22px). Pluto backdash: 20f hu=00 invuln
  (per-char; Uranus 14f), 37px. Wiki 'distance 100' units unknown.
- c.HP wiki-prose croucher list omits Moon (we hit crouching Moon 14; patch-7 agrees).
- Act 0x21 observed on hp-poke to 1 (danger/low-hp reaction act?) - unmapped.

### Mars kit (2026-07-19)
- Fire Soul Bird 41236P: rec 0F, acts 64/65, 10/13, rising arc (contact -65px @70).
- Snake Fire 41236K: rec 10, acts 6A/6B, 10/12 wiki-exact, ground-level, hard KD.
  P/K fireball pair on one motion.
- Fire Heel Drop 214K: NO rec; LK acts 70/72 2hits 8+12; HK 71/73 single 18 (class
  0x10!); MID not overhead (both guards block, chip 7); double-hits on block.
- Throws: Hundred-Slap c.4/6HP = hold 12x2=24 untech (the patch-13 lore throw);
  Frankensteiner c.4/6HK toss 24 gnd / 28 AIR (stronger airborne, wiki-exact both).
- Record 0x11 (var-1, no misfire) matches no move — unused/hidden special? Open.

### Record 0x11 solved: desperation records ARE in the tables (2026-07-19)
- Single-variant misfire-00 records = DESPERATION records: Mars 0x11 (Snake Flare,
  fires REC @C1:586D live), Moon 0x0C (@C1:375A), Venus 0x16 (@C1:79D9), Chibi 0x1B
  presumed. Dispatch template: lda #act / jsr $04DA (act stager) / if $02,X==0:
  ldy #rec / jsr $0B49 / jmp $0204. Mars's desperation handler C1:583C (act 0x75),
  reached via branch at C1:5890 (act-machine: lda $01,X / asl / bpl -> 583C).
- Live special handlers, same template: FSB-LP C1:55F5 (act 64, rec 5851), FSB-HP
  C1:5626 (act 65, rec 5858), Snake-LK C1:568B (act 6A, rec 585F).
- Revised dispatcher-special counts: Moon/Mercury/Mars/Jupiter/Venus 2 each,
  Uranus/Neptune/Pluto/Chibi 1 each. Mercury/Jupiter/Uranus/Neptune/Pluto desperation
  records NOT in the walked windows — location open.
- Dispel -r arg gotcha: treats ranges oddly (misread our offsets); trust direct
  python byte dumps + hand-decode for short stretches.

### Venus kit (2026-07-19)
- Crescent Beam 236P: rec 14, acts 5D/5E, 8/10 wiki-exact, -68px flight = whiffs ALL
  crouchers (like Supreme Thunder).
- Wink Chain Sword [2]8P: rec 15, acts 63/64, pillar at fixed 32/64px (spawn distance
  = record byte 2!), MID both guards (chip 2), wiki recovery 3/7 = +30~+34 on block.
  Rig lesson: DEFBLOCKAT needed (early block-hold walks out of pillar spot).
- Love-Me Chain 623P: DP-family no-REC, acts 67/68, multi-hit 23/22, no invuln.
- Throws: Huracanrana c.4/6HP toss 22 techable (airborne carry); Machine Gun Knee
  c.4/6HK HOLD 5x4=20 untech +41 oki. Hold-throws = all on HK button so far except
  Mars (HP) and Moon/Chibi (?) - pattern note.
- Desperation name: Chain Explosive; wiki 48/chip 12x5 vs our 37/9 (flagged).

### Moon kit (2026-07-19)
- MTA 236P: rec 0A, acts 63/64, 10/12 wiki-exact, -56px flight, Mid.
- MSHA j.214P: rec 0B, HORIZONTAL at cast height (slot y = her y at release),
  ~40px backward recoil on cast; never reached grounded in rig; wiki High 8/10.
- Sonic Cry [2]8P: no-REC strike, acts 68/69, LP multi 3x6+, HP 12(x23 wiki);
  charge minimum LONGER than Venus's (per-char charge times).
- Throws: Headbutt c.4/6HP HOLD 4x5=20 untech +41; Rabbit Flip c.4/6HK toss 20/24 air.
- Dash Jump 66: act 0x60, ~30f, ~200px leap, crosses through opponent.
- 2HK: hurtbox tops -44/-50 (vs -82) = ducks -68/-56 fireballs; act 59, boxes 2B/2C.
- Silver Crystal Operation: 48 wiki-exact; wiki chip 12xN CONTRADICTED (we measure 0).

### Moon prose round (2026-07-19)
- Sonic Cry HP: hu=00 for ~9f startup (t72-80 trace) -> invulnerable reversal ✓.
- Backdash-cancel VERIFIED: act 26 -> Heart act 65 at +8f, slot 0B spawns at -80px
  (vs -164 jump cast), backward momentum carried; wiki +28/+8. Backdash self-cancels
  (17f window, x4 max). Moon-specific cancel system.
- MSHA HP grows mid-flight (prose); dash-jump 66 buffer ~15f (accident hazard).
- Mercury fireball community name: 'Bubbles' (from Moon page prose).
- SCO chip: wiki table 12xN AND prose 'good chip' both contradicted by measured 0.

### Mercury kit (2026-07-19)
- Bubble Spray [4]6P: rec 0D, 8/10 wiki-exact, -56px, LP ~1.7px/f slow float.
- Aqua Mirage 2369P (NOT 236 — the 9 is mandatory, exhaustively verified): rec 0E,
  acts 69/6A, 12/14 wiki-exact, rises from floor.
- Reverse Break Step 623K: no-REC, acts 5F/60, ~12f invuln THROUGH first active
  (maintainer's 'maybe none' corrected), HK chip 3x15.
- DDT c.4/6HP: toss 24/28-air wiki-exact (3rd air-stronger throw), only throw.
- Water Bullet: 12f startup invuln + hurtbox-less ACTIVE phase (hb 11/12 with hu=00),
  ~6f vulnerable gap between. Triangle jump wiki-listed (untested).

### Chibi kit (2026-07-19) — compendium COMPLETE
- PSHA [4]6P: rec 1A, acts 61/62, 10/12 wiki-exact, -52px.
- Swinging Marshmallow j.2K: no-REC air strike, acts 65/66, 8/10 wiki-exact,
  overhead+KD, backdash-cancelable.
- Throw c.4/6HP: HOLD 10x2=20 untech (fastest tick cadence ~4f), only throw.
- Backdash: 26f hu=00 VERIFIED (longest; Uranus 14/Pluto 20/Chibi 26), self-cancels
  frame 26 -> infinite invincible chain (unique). Double jump through frame 27.
- Luna P (rec 1B): figure-8 anchored to cast spot, eats projectiles, 27f guaranteed
  action, backdash-cancelable (wiki prose).

### Chibi extras (maintainer round 2, 2026-07-19)
- 2HK slide: act 0x58, hb 0x0E ~40f traveling active, ~102px (longest slide; Uranus
  67-79px), 9 dmg wiki-exact, low/KD.
- 5LP DOUBLE-PLAY quirk CONFIRMED: act 0x40 (hb window t+1..3) chains to act 0x41 with
  the SAME hitbox out again (t+17..21), on hit AND whiff; damage once (hitstun covers
  window 2, but window 2 is a real hitbox); second hitbox persists ~2f into act 0x00
  (outlives the move). Programming-mishap class finding.

### Guard-cancel criterion tests (2026-07-19)
- GC rig: P1 holds back, P2 (DBTN/DPH in p13f probe now) heavies P1 into blockstun,
  P1 inputs the tool mid-stun. GC = blockstun act 0C/0E -> move act directly.
- Uranus Shadow Dash: 0E -> 0x60 at input completion mid-stun = GC-ABLE -> SPECIAL.
- Moon Dash Jump: same, GC-ABLE -> SPECIAL (wiki prose confirmed).
- Jupiter ordinary forward dash (control): input eaten, stun runs full -> NOT special.
- Criterion (maintainer): GC-able <=> special. Both GC dashes are act 0x60 in
  char-special act space - structure and behavior agree.

### Double jump window + air-block nonexistence (2026-07-19)
- Chibi DJ: act 0x5C, legal window ~15-27f of jump; tap fires same-frame in window;
  HOLD auto-fires at window opening (= buffer-to-first-legal-frame); post-27 tap eaten.
- NO AIR BLOCKING: same WS wave blocked on the landing frame (dact 0C at t=59, back
  held) and HIT clean when contact was airborne (dact 13). Blocking is grounded-only
  -> air GC impossible -> GC criterion applies to grounded tools only.

### Double-jump window precision + height (2026-07-19)
- Input window: taps accepted up to t=36 (fires t=37); t=37 eaten. Hold fires t=31.
  Wiki 'frame 27' = last fire frame from jump input (t=11).
- Height: fire heights 92-95px (apex plateau spans the whole window); DJ adds fixed
  ~86px arc -> peaks 177-180px (3px spread = negligible). Early-vs-late shifts peak
  and landing ~6f later - a timing tool, not a height tool.

### GC-gate jank search (maintainer brainstorm, 2026-07-19) — gate is CLEAN
- Crouch blockstun 0D/0F/0E: GC-able (Shadow Dash fired mid-chain) — both postures OK.
- Hitstun 13: not cancelable. 0x2A tail: not cancelable (71f taunt tail, input eaten).
- Proximity pose 0C (pre-contact): NOT a lock — drops to act 00 on stick release even
  with threat active; nothing to cancel. Dashing out of it ate the punch -> act 0x16
  observed = hit-out-of-forward-dash reaction (new act ID).
- Air: no air block -> no air stun -> no air GC; hitstun (only air stun) uncancelable.
  CONCLUSION: GC gate = exactly the post-contact guard-stun acts, nothing else.
- Probe gained LPRESS (performer L at ph) + DDOWN (attacker holds down) options.

### System-wide wiki cross-check (2026-07-19)
- Death-underflow rule independently on wiki ('live on 0 health'). Convergence.
- GC gate (wiki): specials/desperations/backdash/forward-dash after 9f blockstop,
  buffered to f10. BACKDASH-GC VERIFIED (act 26 from blockstun). Pluto/Uranus
  desperations GC-able against after 1f blockstop (wiki, untested).
- ONLY Uranus & Moon have forward dashes (Jupiter 66 = walking, verified). Reframes
  the earlier GC control test.
- GC backdash = ENHANCED: ~2-2.5x neutral distance at same duration (Uranus 83 vs 36,
  Pluto 74-90 vs 37, Chibi 66-97 vs 36; pushback drift muddies exacts). Wiki's
  backdash-distance column = the GC values; NEUTRAL backdash ~36px universal.
  Wiki Uranus BD row (154/15f = her fwd dash) = suspected duplication error.
- Throw tech semantics: window STARTS grab+6f, lasts per-char (Venus 6f outlier =
  patch 8 target; 14-19f others). Reconciles p8cal boundary (12/14) exactly.
  Tech-table absentees = our hold-throw list (full taxonomy cross-validation).
  Throws: -1 range facing left; air-OK throws more vertical range grounded.
- Prejump/landing 5f universal, no throw invuln, landing blocks after 1f (matches
  our landing-block observation), specials/backdash cancel prejump+landing after 1f.

### Wiki-facts verification round (2026-07-19)
- GC gate: <=3f (Neptune 214-prebuffered fired contact+3). Wiki '9f blockstop,
  buffer to f10' REFUTED. Backdash-GC floor +5 = tap-tap input mechanics, and
  both edges must be fresh (<15f apart) — stale held-back breaks the double-tap.
- GC out of blocked Pluto desperation: works (+9, input-limited); '1f exception'
  subsumed by the immediate gate.
- Prejump: throw-vulnerable VERIFIED (act 05 grabbed frame 2); backdash-cancel
  VERIFIED (05->26 grounded); normal-cancel refuted-as-designed (button eaten).
- Throw -1-range-left + air-OK vertical range: below rig precision, wiki-only.
- Uranus HP throw measured: acts 5B/5C/5D, toss 24 (wiki-exact) — second throw done.
- Defender pre-contact backdash evades desperations outright (accidental demo).

### T1 closed: dispatcher = projectile system (2026-07-19)
- Mercury/Jupiter/Uranus/Neptune/Pluto desperations fired with ZERO dispatcher RECs
  (all five connected, known damage values) -> their records never existed.
- Unification: $C1:0B49 records = projectile-move parameters (payload b4/b5 =
  velocity/arc: C0FF arcs, 0000 flat; Wink b2 = spawn distance). Non-projectile
  specials are pure act-machine. Only projectile specials can misfire.
- Suite +7 tests: static-desperation-records (4x7 bytes), death-underflow pair
  (chip1-vs-1hp survives at 0 / chip2 underflow-KOs), gc-gate-immediate (<=4f),
  gc-backdash, prejump-throw-vulnerable. clean=31, v0.19=49 ALL PASS.
- prejump-backdash-cancel regression test attempted and DROPPED: the 5f cancel
  window + 30Hz input-phase makes a scripted 1f-tap test inherently flaky (wrong
  phase -> back-jump act 0x08). Fact stays verified (manual rig); not suite-locked.

### T2 closed: modifier composition disassembled (2026-07-19)
- 11 handlers 0xCAED-0xCD6D (6 jmp hit + 5 jsr tail), template: practice-4 bypass ->
  mod = counter(-2 if def+0x18 bit0) + def+0x48 + def+0x71 - att($70/$73/$74)
  [- 1 in dec_a variants]; row = att+0x45; -> $D055.
- NO RNG IN DAMAGE. def+0x48 = first-hit defense (init 1, cleared on first hit by
  16-bit stz $47,X at $C1:0E51 — zeroes +0x47/+0x48 together). All 'roll pairs' =
  d48 1 vs 0. Wiki damage|faceHit columns = the same pair.
- jsr tails: chip = dmg>>2 floor 1 (in code); 3 desperation tails CLAMP damage to
  remaining HP (cannot-kill mechanism — Dimension Dance no-chip-kill etc.).
- Counter-hit = def+0x18 bit0 -> lda #$FE. Practice mode-4 no-damage exit $CD6A in
  every handler. P1 +0x48 load site 0x883E (char init).

### T3 closed: ACS residuals (2026-07-19)
- ACS staging: P1 $1D00 block (stats $1D08-0D), P2 $1D10 (stats $1D18-1D); menu writer
  ~$80:B0BD; loaders $C0:879B (P1) / ~0x8920 (P2).
- +0x72: MAX HP = 0x60 + 8*health -> $1049 + $104A at load; $104A readers: 0x8A7D
  (round refill), 0xD77C/0xD7CE (HUD bar scaling), 0xE398.
- +0x76: per-entity update-vector selector (C1:0010/0026 reads, players from $1D01).
- +0x48: manifest-sourced at 0x883E (via $E0:0238 ptr), value 1 measured.
- Projectile spawn copies caster +0x70/+0x73 into slot (C1:0BC0-0BDB).

### T4 closed: act taxonomy (2026-07-19)
- 0x21 = DANGER-entry act, threshold hp <= 0x18 EXACT on first entry (0x19 no-fire
  from fresh state = desperation-gate threshold). SUBTLETY: once danger has been
  entered, a latch persists after healing above threshold — later hp DROPS re-fire
  0x21 even to values > 0x18 (0x60->0x19 fired after a prior danger visit). Suite
  locks only the clean positive (fires at 0x18).
- Air hit at low altitude -> 0x11 (same as stand); 0x16 = dash-hit specific.
- Blockstun 0C/0E and hitstun 11/13 are ALTERNATING PAIRS (anim retrigger).
- Reaction-type handler table @ C1:0E84 (2-byte entries; handlers set knockback +
  reaction act). Full enumeration deferred.

### T5 closed (2026-07-19)
- Clock trigger VERIFIED: timer $7E:0802 (frame) /0803 (ones) /0804 (tens); poke
  9s -> full-HP desperation fires (Jupiter 48). Gate = hp<=0x18 OR clock<10s.
- Wiki-vs-ours damage offset UNIFIED: all systematic diffs = d48 state (ours fresh=1,
  wiki depleted=0). Venus/Neptune chip at d48=0 = 12 = wiki-exact. Multi-chip COUNTS
  (x2/x5) still unreproduced - flagged.
- MSHA hits GROUNDED standing targets via backdash-cast (-80px shot alt); jump casts
  always overfly. Wiki 'High' explained.

### Housekeeping round (2026-07-19)
- p9 behavioral test added (dual-mode): DS vs crouching Chibi hit-frame t=35 patched
  vs t=43 vanilla (the box-tracks-ball fix, 8f earlier + higher contact).
- Suite FULL mode implemented (FULL=true): 6 remaining desperation-crouch checks +
  3 chip signatures. clean=36 / clean-FULL=46 / v0.19=55.
- Engine-rule locks (GC gate, backdash-GC, prejump-throw, death-underflow) confirmed
  present since the T1 batch. Community reporting of findings/gaps: maintainer done.

### T6 closed (2026-07-19)
- Throw asymmetry VERIFIED pixel-exact via FREEZEPOS rig (per-frame position+subpixel
  pokes): Uranus HK 48px right-facing / 47px left-facing, whiff at +1px each.
- Vertical grab envelopes: Rabbit Flip (air-OK) 32-39px lift tolerance; Headbutt
  (ground-only) <2px. FREEZEY rig.
- Air Power Bomb: 6 attempts -> air normals; adjacency window eludes scripting
  (asymmetry vs Moon/Mars/Mercury air throws which worked first try) - rig-limited.
- Triangle jump: position pokes re-clamped into camera view; max-separation boundary
  is NOT a wall for the wall-jump; true corner needs a legit camera walk - rig-limited.
- Suite +2: base-throw-range-asymmetry, base-airok-throw-vertical-range.

### RE residuals closed (2026-07-19)
- Reaction table C1:0E85 FULLY ENUMERATED: 3 posture sub-tables x 13 levels; handler
  template +0x3A pushback | +0x32/34 launch | +0x46 flag 0x20/0xA0 | act via $10A9.
  New acts: 0x10, 0x14 (in-table, unobserved), 0x27 (misfire trip), 0x0A (turnaround).
- Danger check $C1:0AA9: lda #$18/cmp $49,X/bmi/act 0x21 (neutral-entry call).
- Shared ochame roll $C1:0AB9: RNG $90 & 0x0F -> table $0AF5 vs +0x75 -> act 0x27 +
  flag 0xA0. The combat RNG consumer.
- Multi-chip x2/x5 = CORNER values, reproduced via FREEZEDEF (Venus 5x12, Neptune 2x12).
- d48 per-character: Jupiter 1, Neptune 2 (verified via 6-vs-8 first hit); others
  ambiguous in mid-match saves. Players' +0x76 uniformly 0.
- Ochame-inflicting-taunt idea: REJECTED by maintainer (net negative for enjoyment).

### MEATY label removed (2026-07-20)
- Pad-test verdict: the MEATY status label read as noise/backseat-coaching in live play
  (at best strange, at times detrimental) -> removed from BOTH surfaces:
  - Lua overlay: tools/training/labels.lua (COLORS entry, lastConstrained tracker, the
    on.connect fire); training_test T4 flipped to a NEGATIVE check (no label on the
    frame-perfect infinite) - PASS.
  - Patch 10b: mkpatch10.py LABELS id 4 retired (ids 1/2/3/5 stable), detection block
    excised from the producer stub, M/Y glyphs drop from the font. Rebuilt
    sms_combolabels.bps; v0.21 ALLPATCHES chain diff vs v0.20 confined to the p10 bank,
    title tiles, hook target bytes + checksum (verified byte-level).
- The meaty DETECTION RULE (hit <=2f after defender left constraint) stays documented in
  sms_engine_internals.md - it's engine knowledge, only the display is gone.
- tools/test_labels_cfg.lua rewritten as a committed PUNISH scenario (the old untracked
  debug cfg sampled t=300-301, far outside the 48f label TTL - could never pass).
- Suites: v0.21 = 59 ALL PASS, clean = 41 ALL PASS, T4/T5/T8 PASS, in-ROM PUNISH
  oracle PASS (ROM=yes Lua=yes).

### L+R training-menu report investigated (2026-07-20)
- User report: L+R no longer opens the p11 menu on the all-patches ROM. NOT reproduced
  on the delivered v0.21 image (62ffb174): fresh-boot Practice entry, L/R press skews
  0/2/6/10f, movelist open/close, random power-on RAM, and damage-on(mode 5)+KO all
  toggle the menu (probe_p11_lr.lua, probe_p11_ko_lr.lua; menu renders identical to the
  pre-change build, screenshot-compared). BPS round-trips byte-exact. Gate recap:
  $8D in {4,5(+DMGFLAG A5)} && $0070==4 && $01FA==0x80.
- REAL defect found while investigating: patch_index claimed bundles are "rebuildable
  by chaining the standalones (order-free)" - FALSE. All bank-appending standalones
  (4,10,11,12,13,14) target the same first-free bank $E8 (verified: every one's only
  expanded-bank payload is $E8), so chained BPS application (checksum override needed)
  clobbers earlier patches' code banks - killing e.g. exactly the p11 L+R stub.
  patch_index corrected; custom combos must chain the mkpatchN.py builders.
- probe_p11_lr autopilot note: Practice char-select needs P1 to ALSO confirm the
  dummy's char (P2 pad inert); the old probe_p11_nav step list stalls there on
  current builds and its sf>600 fallback saves a NON-match state (it clobbered
  traces/training_p11.mss once - restored from git; re-save a fresh one if needed).
