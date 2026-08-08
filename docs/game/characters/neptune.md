# Neptune — per-character ROM map

**charID 7** · セーラーネプチューン · clean ROM `bc0e29ee…` · file offset = SNES & `0x3FFFFF`

> **Generated** by `tools/mkcharmap.py` — every address on this page is read out
> of the cartridge, not transcribed. Do not hand-edit. The engine-wide map these
> addresses hang off (the object struct, the box format, the damage pipeline) is
> [`../sms_data_architecture.md`](../sms_data_architecture.md).

## Where she begins — the manifest

| | SNES | file |
|---|---|---|
| manifest record | `$E002AC` | `0x2002AC` |
| palette 0 | `$E006FE` | `0x2006FE` |
| palette 1 | `$E0071E` | `0x20071E` |
| win-icon palette | `$E0090E` | `0x20090E` |
| object palette | `$E0087E` | `0x20087E` |
| sprite-CHR payload | `$E250A0` | `0x2250A0` |

**First-hit defense: `2`** — the manifest's first byte, loaded into struct
`+0x48`. It is worth one damage-matrix column until she is first hit each round,
and it is the whole of what used to be read as damage randomness.

### Her palettes

Palette 0 — `#6a6a6a` `#202020` `#6a2000` `#e67b52` `#ff9c7b` `#ffc5c5` `#004a52` `#007b7b` `#2020b4` `#4141d5` `#6a6ad5` `#b48bff` `#d50000` `#00316a` `#c55a31` `#ffffff`

Palette 1 — `#6a6a6a` `#000008` `#6a2000` `#e67b52` `#ff9c7b` `#ffc5c5` `#004a52` `#007b7b` `#314a31` `#5a735a` `#839c83` `#bdd5bd` `#d50000` `#000000` `#c55a31` `#ffffff`

Indices 0-5 (grey, outline, four skin tones) and 15 (white) are shared across the
roster; **6-11 are the costume ramp**, and they are what makes this character look
like herself.

## Collision boxes — bank `$8A`

| Table | SNES | file | entries |
|---|---|---|---|
| attack (hit) | `$8A:E9C9` | `0x0AE9C9` | 25 × 8 B |
| hurt (body+head pairs) | `$8A:EA91` | `0x0AEA91` | 96 × 16 B |
| collision (push) | `$8A:F091` | `0x0AF091` | 6 × 8 B |

Indexed live every frame by struct `+0x40` / `+0x41` / `+0x42`. Extracted and
decoded for all nine in [`../sms_all_boxes.json`](../sms_all_boxes.json).

## Animation — her four id-indexed layers

| Layer | Table entry | Her data |
|---|---|---|
| action scripts | `$C0:0000 + 7*2` | act table at `$C0:1330` |
| pose records | `$84:809C + 7*2` | `$84:8C10`, **134 poses** × 4 B |
| cel tables | `$CB:0000 + 7*4` | pose→cel `$CB:124B`, records `$CB:1357`, **120 cels** × 5 B |
| OAM sprite layout | `$84:8000 + 7*3` | `$8492D4` |

A pose record is `[class][hit idx][hurt idx][coll idx]`, so **the pose is what puts
her hitboxes on screen**; a cel record is `[src24][len16]`, a raw CHR block DMA'd
straight to VRAM.

*(The act table's entry count is deliberately not published: entries may point
below the table, so no static derivation for it survived checking.)*

## Her code — the proc block

`$C1:8DA2`, **4200 bytes**, reached through the object dispatch
`jsr ($00A6,X)` with `X = 7*2`.

**Close-throw tables** (4 × 8 B, indexed by attack button; the record's last byte
is the thrower's act): `$C1:8ED9`, `$C1:8EF9`.

**Throw-hold scripts** (8 B per step; a step whose byte 5 is non-zero samples the
victim's mashing): `$C1:8F19`.

**Toss records** (`[$FF][X vel 8.8][Y vel 8.8][damage]`, read by `$C1:07E5`; X is the
**forward** velocity and is negated when she faces left): `$C1:8F41` (x +1.50, y -5.50, 20 dmg).

**Cancellable light-recovery acts:** `41 45 56 5A` — the frames this game's links
live in.

## Sound and menus

| | |
|---|---|
| in-match voice sound ids | `79`-`82` (id = 49 + (charID−1)×5) |
| BRR directory (ARAM) | `$34C0 + 6*32` = `$3580` |
| BRR directory (ROM) | `$E4:2D84` |
| character-select voice | bank id `28` |
| movelist tilemap | `$E278E0` (compressed, codec 1 → BG3 map) |

## Further reading

* Her moves, damages and desperation: [`../sms_specials.md`](../sms_specials.md)
* How any of these systems works: [`../sms_data_architecture.md`](../sms_data_architecture.md)
* The flat address reference: [`../annotations.md`](../annotations.md)

