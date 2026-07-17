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
| +0x00 | charID | 1=Moon…6=Uranus…10=Saturn | ground truth |
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
| +0x43 | hitstop? | per CLAUDE.md; training Lua instead marks +0x4D hitstop | both, unresolved |
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
select a character headlessly.

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
