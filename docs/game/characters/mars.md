# Mars — per-character ROM map

**charID 3** · セーラーマーズ · clean ROM `bc0e29ee…` · file offset = SNES & `0x3FFFFF`

> **Generated** by `tools/mkcharmap.py` — every address on this page is read out
> of the cartridge, not transcribed. Do not hand-edit. The engine-wide map these
> addresses hang off (the object struct, the box format, the damage pipeline) is
> [`../sms_data_architecture.md`](../sms_data_architecture.md).

## Where she begins — the manifest

| | SNES | file |
|---|---|---|
| manifest record | `$E0026C` | `0x20026C` |
| palette 0 | `$E005FE` | `0x2005FE` |
| palette 1 | `$E0061E` | `0x20061E` |
| win-icon palette | `$E008EE` | `0x2008EE` |
| object palette | `$E007FE` | `0x2007FE` |
| sprite-CHR payload | `$E223A0` | `0x2223A0` |

**First-hit defense: `0`** — the manifest's first byte, loaded into struct
`+0x48`. It is worth one damage-matrix column until she is first hit each round,
and it is the whole of what used to be read as damage randomness.

### Her palettes

Palette 0 — `#6a6a6a` `#202020` `#6a2000` `#e67b52` `#ff9c7b` `#ffc5c5` `#5a0073` `#521008` `#41086a` `#7329b4` `#ac73d5` `#eebdff` `#c50020` `#ff3939` `#c55a31` `#ffffff`

Palette 1 — `#6ab46a` `#201829` `#6a2000` `#e67b52` `#ff9c7b` `#ffc5c5` `#5a0073` `#29398b` `#41086a` `#7329b4` `#ac73d5` `#eebdff` `#4183f6` `#7bb4ff` `#c55a31` `#ffffff`

Indices 0-5 (grey, outline, four skin tones) and 15 (white) are shared across the
roster; **6-11 are the costume ramp**, and they are what makes this character look
like herself.

## Collision boxes — bank `$8A`

| Table | SNES | file | entries |
|---|---|---|---|
| attack (hit) | `$8A:CEE9` | `0x0ACEE9` | 33 × 8 B |
| hurt (body+head pairs) | `$8A:CFF1` | `0x0ACFF1` | 96 × 16 B |
| collision (push) | `$8A:D5F1` | `0x0AD5F1` | 6 × 8 B |

Indexed live every frame by struct `+0x40` / `+0x41` / `+0x42`. Extracted and
decoded for all nine in [`../sms_all_boxes.json`](../sms_all_boxes.json).

## Animation — her four id-indexed layers

| Layer | Table entry | Her data |
|---|---|---|
| action scripts | `$C0:0000 + 3*2` | act table at `$C0:06A5` |
| pose records | `$84:809C + 3*2` | `$84:8490`, **125 poses** × 4 B |
| cel tables | `$CB:0000 + 3*4` | pose→cel `$CB:0616`, records `$CB:0710`, **114 cels** × 5 B |
| OAM sprite layout | `$84:8000 + 3*3` | `$868000` |

A pose record is `[class][hit idx][hurt idx][coll idx]`, so **the pose is what puts
her hitboxes on screen**; a cel record is `[src24][len16]`, a raw CHR block DMA'd
straight to VRAM.

*(The act table's entry count is deliberately not published: entries may point
below the table, so no static derivation for it survived checking.)*

## Her code — the proc block

`$C1:47A6`, **4320 bytes**, reached through the object dispatch
`jsr ($00A6,X)` with `X = 3*2`.

**Close-throw tables** (4 × 8 B, indexed by attack button; the record's last byte
is the thrower's act): `$C1:48E5`, `$C1:4905`.

**Throw-hold scripts** (8 B per step; a step whose byte 5 is non-zero samples the
victim's mashing): `$C1:4925`.

**Toss records** (`[$FF][X vel 8.8][Y vel 8.8][damage]`, read by `$C1:07E5`; X is the
**forward** velocity and is negated when she faces left): `$C1:495D` (x +2.50, y -5.50, 24 dmg), `$C1:496D` (x +2.50, y -5.50, 28 dmg).

**Cancellable light-recovery acts:** `42 49 55 59` — the frames this game's links
live in.

## Sound and menus

| | |
|---|---|
| in-match voice sound ids | `59`-`62` (id = 49 + (charID−1)×5) |
| BRR directory (ARAM) | `$34C0 + 2*32` = `$3500` |
| BRR directory (ROM) | `$E4:2D04` |
| character-select voice | bank id `24` |
| movelist tilemap | `$E27270` (compressed, codec 1 → BG3 map) |

## Further reading

* Her moves, damages and desperation: [`../sms_specials.md`](../sms_specials.md)
* How any of these systems works: [`../sms_data_architecture.md`](../sms_data_architecture.md)
* The flat address reference: [`../annotations.md`](../annotations.md)

