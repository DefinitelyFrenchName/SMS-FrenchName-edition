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
