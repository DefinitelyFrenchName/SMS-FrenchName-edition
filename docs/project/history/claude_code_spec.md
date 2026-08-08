> **SUPERSEDED (moved to docs/project/history/ 2026-07-30, issue #55).** This is the ORIGINAL
> project brief, kept as a record of how the ROM map was derived. Its setup
> instructions are obsolete: there is no `./assets/` — the vendor Lua lives in
> `vendor/sms-training-mode/` and ROM location is resolved by `tools/smspaths.py`.
> Current operational docs: HANDOFF.md, docs/project/patch_index.md, docs/game/sms_engine_internals.md.

# Claude Code spec — SMS (SFC) animation-script reversing: Uranus frame data

## Goal
Locate and document, at ROM byte level, the animation scripts that produce
startup/active/recovery for every Sailor Uranus move in
Bishoujo Senshi Sailor Moon S: Jougai Rantou!? (Japan), SHA-1 bc0e29ee…aaa1c.
"Done" = a table mapping each Action ID → ROM offset of its script, script format
spec (opcode/field layout), and per-move frame counts that match the Dustloop wiki
values and in-emulator observation.

## Inputs (place in ./assets/)
- Clean ROM (verified hash above)
- sms_quickref.md (the address card; superseded in detail by sms_data_architecture.md)
- extract_sms_hitboxes.py
- Clone: github.com/sprntgd/Bishoujo-Senshi-Sailor-Moon-S-Jougai-Rantou-Shuyaku-Soudatsusen-Training-Mode

## Known anchors (do not re-derive)
- Player structs $7E:1000/1080 (+0x40/41/42 box indices, +0x01 action, +0x02/06/07 counters)
- Box tables bank $8A (ptr tables $8A:C1F1/C229/C23D); Uranus = char 6
- Per-frame object update: JSL $C1:0000 (state procs ~$C1:122A, $C1:15BD)
- Char load $C0:879B reads manifest ptr table $E0:0238+id*2; one manifest pointer's
  payload is copied/expanded to $7E:6A00 by $C0:916B — suspect animation/sprite data

## Environment
- Build Mesen2 headless (Linux) for Lua-scripted tracing, or BizHawk under mono.
- 65816 disassembler: pelrun/Dispel (builds with plain make), or write a Python one.
- Keep a running annotations file (addr → label/comment), committed after every session.

## Plan
1. **Dynamic first.** Boot ROM in emulator, pick Uranus (P1). Lua: log writes to
   $7E:1040/1041/1042 and $7E:1001/1002/1006/1007 with PC of the writing instruction
   (memory write callbacks). Perform 5A (standing light) once. The writer PC lands
   inside the animation interpreter — this single trace likely answers everything.
2. Disassemble around that PC (bank $C1 expected). Identify how the script pointer is
   formed: per-character Action-ID → script pointer table (ROM) vs data staged at
   $7E:6A00. If $6A00: reverse $C0:916B (copy or RLE/LZ decompress) to map WRAM back
   to ROM source; the manifest at [$E0:0238+0x0C] gives the per-character source.
3. Derive the script format: expect per-step records {sprite frame, duration,
   hitbox idx, hurtbox idx, sfx/movement flags, next/loop}. Confirm by correlating
   logged (+0x40 value, tick count) sequences against raw bytes.
4. Enumerate Uranus's Action IDs 0x2B..~0x64 (attacks; see Lua action list for
   universal states), extract each script, compute startup (ticks until +0x40 != 0),
   active (ticks with != 0), recovery (remaining until neutral/cancel window).
5. Validate ≥5 moves against Dustloop SMS frame data and against frame-advance
   observation. Note the engine's 30Hz update quirk if counts differ by 2×.
6. Deliver: format spec, per-move table (Action ID, ROM offset, startup/active/
   recovery, hitbox indices used), and a Python extractor mirroring
   extract_sms_hitboxes.py.

## Pitfalls
- The game processes attacks starting the frame AFTER action start (Lua comments).
- P2 uses mirrored X handling (+0x09); box entries carry separate L/R x-offsets.
- Hit table at $8A:C1F1 has 28 entries: 10 chars + projectile object types (objects
  $1100/$1180 use the same code path with their own "chara" IDs).
- Some Action IDs are shared/universal (walk, jump, hitstun) — scripts may live in a
  common table, with character tables only for attacks.
