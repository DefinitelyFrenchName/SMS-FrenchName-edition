# Mercury — per-character ROM map

**charID 2** · セーラーマーキュリー · clean ROM `bc0e29ee…` · file offset = SNES & `0x3FFFFF`

> **Generated** by `tools/mkcharmap.py` — every address on this page is read out
> of the cartridge, not transcribed. Do not hand-edit. The engine-wide map these
> addresses hang off (the object struct, the box format, the damage pipeline) is
> [`../sms_data_architecture.md`](../sms_data_architecture.md).

## Where she begins — the manifest

| | SNES | file |
|---|---|---|
| manifest record | `$E0025C` | `0x20025C` |
| palette 0 | `$E005BE` | `0x2005BE` |
| palette 1 | `$E005DE` | `0x2005DE` |
| win-icon palette | `$E008E6` | `0x2008E6` |
| object palette | `$E007DE` | `0x2007DE` |
| sprite-CHR payload | `$E21660` | `0x221660` |

**First-hit defense: `0`** — the manifest's first byte, loaded into struct
`+0x48`. It is worth one damage-matrix column until she is first hit each round,
and it is the whole of what used to be read as damage randomness.

### Her palettes

Palette 0 — `#6a6a6a` `#181818` `#6a2000` `#e67b52` `#ff9c7b` `#ffc5c5` `#c55a31` `#008b8b` `#2020b4` `#4141d5` `#6a6ad5` `#b48bff` `#b42020` `#ff416a` `#00006a` `#ffffff`

Palette 1 — `#6a6a6a` `#000000` `#6a2000` `#e67b52` `#ff9c7b` `#ffc5c5` `#c55a31` `#008b8b` `#202020` `#414152` `#73738b` `#9494c5` `#b42020` `#ff416a` `#00006a` `#ffffff`

Indices 0-5 (grey, outline, four skin tones) and 15 (white) are shared across the
roster; **6-11 are the costume ramp**, and they are what makes this character look
like herself.

## Collision boxes — bank `$8A`

| Table | SNES | file | entries |
|---|---|---|---|
| attack (hit) | `$8A:C899` | `0x0AC899` | 22 × 8 B |
| hurt (body+head pairs) | `$8A:C949` | `0x0AC949` | 87 × 16 B |
| collision (push) | `$8A:CEB9` | `0x0ACEB9` | 6 × 8 B |

Indexed live every frame by struct `+0x40` / `+0x41` / `+0x42`. Extracted and
decoded for all nine in [`../sms_all_boxes.json`](../sms_all_boxes.json).

## Animation — her four id-indexed layers

| Layer | Table entry | Her data |
|---|---|---|
| action scripts | `$C0:0000 + 2*2` | act table at `$C0:03C0` |
| pose records | `$84:809C + 2*2` | `$84:82BC`, **117 poses** × 4 B |
| cel tables | `$CB:0000 + 2*4` | pose→cel `$CB:031F`, records `$CB:0409`, **105 cels** × 5 B |
| OAM sprite layout | `$84:8000 + 2*3` | `$85BF66` |

A pose record is `[class][hit idx][hurt idx][coll idx]`, so **the pose is what puts
her hitboxes on screen**; a cel record is `[src24][len16]`, a raw CHR block DMA'd
straight to VRAM.

*(The act table's entry count is deliberately not published: entries may point
below the table, so no static derivation for it survived checking.)*

## Her code — the proc block

`$C1:3779`, **4141 bytes**, reached through the object dispatch
`jsr ($00A6,X)` with `X = 2*2`.

**Close-throw tables** (4 × 8 B, indexed by attack button; the record's last byte
is the thrower's act): `$C1:38AE`, `$C1:38CE`.

**Throw-hold scripts** (8 B per step; a step whose byte 5 is non-zero samples the
victim's mashing): `$C1:38EE`.

**Toss records** (`[$FF][X vel 8.8][Y vel 8.8][damage]`, read by `$C1:07E5`; X is the
**forward** velocity and is negated when she faces left): `$C1:3916` (x +1.50, y -5.00, 24 dmg), `$C1:3926` (x +1.50, y -5.00, 28 dmg).

**Cancellable light-recovery acts:** `41 46 53 57` — the frames this game's links
live in.

## Sound and menus

| | |
|---|---|
| in-match voice sound ids | `54`-`57` (id = 49 + (charID−1)×5) |
| BRR directory (ARAM) | `$34C0 + 1*32` = `$34E0` |
| BRR directory (ROM) | `$E4:2CE4` |
| character-select voice | bank id `23` |
| movelist tilemap | `$E270D0` (compressed, codec 1 → BG3 map) |

## Further reading

* Her moves, damages and desperation: [`../sms_specials.md`](../sms_specials.md)
* How any of these systems works: [`../sms_data_architecture.md`](../sms_data_architecture.md)
* The flat address reference: [`../annotations.md`](../annotations.md)

