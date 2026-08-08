# Venus — per-character ROM map

**charID 5** · セーラーヴィーナス · clean ROM `bc0e29ee…` · file offset = SNES & `0x3FFFFF`

> **Generated** by `tools/mkcharmap.py` — every address on this page is read out
> of the cartridge, not transcribed. Do not hand-edit. The engine-wide map these
> addresses hang off (the object struct, the box format, the damage pipeline) is
> [`../sms_data_architecture.md`](../sms_data_architecture.md).

## Where she begins — the manifest

| | SNES | file |
|---|---|---|
| manifest record | `$E0028C` | `0x20028C` |
| palette 0 | `$E0067E` | `0x20067E` |
| palette 1 | `$E0069E` | `0x20069E` |
| win-icon palette | `$E008FE` | `0x2008FE` |
| object palette | `$E0083E` | `0x20083E` |
| sprite-CHR payload | `$E23A90` | `0x223A90` |

**First-hit defense: `0`** — the manifest's first byte, loaded into struct
`+0x48`. It is worth one damage-matrix column until she is first hit each round,
and it is the whole of what used to be read as damage randomness.

### Her palettes

Palette 0 — `#6a6a6a` `#202020` `#6a2000` `#e67b52` `#ff9c7b` `#ffc5c5` `#ff6a00` `#ffd500` `#00008b` `#2041d5` `#6a6ad5` `#b48bff` `#d50000` `#ff8b00` `#c55a31` `#ffffff`

Palette 1 — `#6a6a6a` `#202020` `#6a2000` `#e67b52` `#ff9c7b` `#ffc5c5` `#ff6a00` `#ffd500` `#942008` `#c53141` `#ee6273` `#ff94a4` `#ff5273` `#ff8b00` `#c55a31` `#ffffff`

Indices 0-5 (grey, outline, four skin tones) and 15 (white) are shared across the
roster; **6-11 are the costume ramp**, and they are what makes this character look
like herself.

## Collision boxes — bank `$8A`

| Table | SNES | file | entries |
|---|---|---|---|
| attack (hit) | `$8A:DDA1` | `0x0ADDA1` | 18 × 8 B |
| hurt (body+head pairs) | `$8A:DE31` | `0x0ADE31` | 88 × 16 B |
| collision (push) | `$8A:E3B1` | `0x0AE3B1` | 6 × 8 B |

Indexed live every frame by struct `+0x40` / `+0x41` / `+0x42`. Extracted and
decoded for all nine in [`../sms_all_boxes.json`](../sms_all_boxes.json).

## Animation — her four id-indexed layers

| Layer | Table entry | Her data |
|---|---|---|
| action scripts | `$C0:0000 + 5*2` | act table at `$C0:0D28` |
| pose records | `$84:809C + 5*2` | `$84:886C`, **118 poses** × 4 B |
| cel tables | `$CB:0000 + 5*4` | pose→cel `$CB:0C73`, records `$CB:0D5F`, **107 cels** × 5 B |
| OAM sprite layout | `$84:8000 + 5*3` | `$888000` |

A pose record is `[class][hit idx][hurt idx][coll idx]`, so **the pose is what puts
her hitboxes on screen**; a cel record is `[src24][len16]`, a raw CHR block DMA'd
straight to VRAM.

*(The act table's entry count is deliberately not published: entries may point
below the table, so no static derivation for it survived checking.)*

## Her code — the proc block

`$C1:6B0A`, **3816 bytes**, reached through the object dispatch
`jsr ($00A6,X)` with `X = 5*2`.

**Close-throw tables** (4 × 8 B, indexed by attack button; the record's last byte
is the thrower's act): `$C1:6C33`.

**Toss records** (`[$FF][X vel 8.8][Y vel 8.8][damage]`, read by `$C1:07E5`; X is the
**forward** velocity and is negated when she faces left): `$C1:6C53` (x +3.50, y -5.50, 22 dmg).

**Cancellable light-recovery acts:** `41 45 51 55` — the frames this game's links
live in.

## Sound and menus

| | |
|---|---|
| in-match voice sound ids | `69`-`72` (id = 49 + (charID−1)×5) |
| BRR directory (ARAM) | `$34C0 + 4*32` = `$3540` |
| BRR directory (ROM) | `$E4:2D44` |
| character-select voice | bank id `26` |
| movelist tilemap | `$E27610` (compressed, codec 1 → BG3 map) |

## Further reading

* Her moves, damages and desperation: [`../sms_specials.md`](../sms_specials.md)
* How any of these systems works: [`../sms_data_architecture.md`](../sms_data_architecture.md)
* The flat address reference: [`../annotations.md`](../annotations.md)

