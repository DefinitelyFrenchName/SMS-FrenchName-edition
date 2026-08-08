# Chibi Moon — per-character ROM map

**charID 9** · ちびムーン · clean ROM `bc0e29ee…` · file offset = SNES & `0x3FFFFF`

> **Generated** by `tools/mkcharmap.py` — every address on this page is read out
> of the cartridge, not transcribed. Do not hand-edit. The engine-wide map these
> addresses hang off (the object struct, the box format, the damage pipeline) is
> [`../sms_data_architecture.md`](../sms_data_architecture.md).

## Where she begins — the manifest

| | SNES | file |
|---|---|---|
| manifest record | `$E002CC` | `0x2002CC` |
| palette 0 | `$E0077E` | `0x20077E` |
| palette 1 | `$E0079E` | `0x20079E` |
| win-icon palette | `$E0091E` | `0x20091E` |
| object palette | `$E008BE` | `0x2008BE` |
| sprite-CHR payload | `$E26590` | `0x226590` |

**First-hit defense: `0`** — the manifest's first byte, loaded into struct
`+0x48`. It is worth one damage-matrix column until she is first hit each round,
and it is the whole of what used to be read as damage randomness.

### Her palettes

Palette 0 — `#6a6a6a` `#522010` `#6a2000` `#e67b52` `#ff9c7b` `#ffc5c5` `#e61839` `#ff739c` `#ffacd5` `#083183` `#8394e6` `#c5d5ff` `#ffd5f6` `#ffa4c5` `#c55a31` `#ffffff`

Palette 1 — `#6a6a6a` `#7b3910` `#6a2000` `#e67b52` `#ff9c7b` `#ffc5c5` `#ff9c31` `#ffd552` `#ffffa4` `#083183` `#8394e6` `#c5d5ff` `#ffd5f6` `#ffa4c5` `#c55a31` `#ffffff`

Indices 0-5 (grey, outline, four skin tones) and 15 (white) are shared across the
roster; **6-11 are the costume ramp**, and they are what makes this character look
like herself.

## Collision boxes — bank `$8A`

| Table | SNES | file | entries |
|---|---|---|---|
| attack (hit) | `$8A:F669` | `0x0AF669` | 16 × 8 B |
| hurt (body+head pairs) | `$8A:F6E9` | `0x0AF6E9` | 76 × 16 B |
| collision (push) | `$8A:FBA9` | `0x0AFBA9` | 6 × 8 B |

Indexed live every frame by struct `+0x40` / `+0x41` / `+0x42`. Extracted and
decoded for all nine in [`../sms_all_boxes.json`](../sms_all_boxes.json).

## Animation — her four id-indexed layers

| Layer | Table entry | Her data |
|---|---|---|
| action scripts | `$C0:0000 + 9*2` | act table at `$C0:1954` |
| pose records | `$84:809C + 9*2` | `$84:8FCC`, **103 poses** × 4 B |
| cel tables | `$CB:0000 + 9*4` | pose→cel `$CB:184D`, records `$CB:191B`, **85 cels** × 5 B |
| OAM sprite layout | `$84:8000 + 9*3` | `$86C44F` |

A pose record is `[class][hit idx][hurt idx][coll idx]`, so **the pose is what puts
her hitboxes on screen**; a cel record is `[src24][len16]`, a raw CHR block DMA'd
straight to VRAM.

*(The act table's entry count is deliberately not published: entries may point
below the table, so no static derivation for it survived checking.)*

## Her code — the proc block

`$C1:AE47`, **4025 bytes**, reached through the object dispatch
`jsr ($00A6,X)` with `X = 9*2`.

**Close-throw tables** (4 × 8 B, indexed by attack button; the record's last byte
is the thrower's act): `$C1:AF72`.

**Cancellable light-recovery acts:** `41 47 53 57` — the frames this game's links
live in.

## Sound and menus

| | |
|---|---|
| in-match voice sound ids | `89`-`92` (id = 49 + (charID−1)×5) |
| BRR directory (ARAM) | `$34C0 + 8*32` = `$35C0` |
| BRR directory (ROM) | `$E4:2DC4` |
| character-select voice | bank id `30` |
| movelist tilemap | `$E27B60` (compressed, codec 1 → BG3 map) |

## Further reading

* Her moves, damages and desperation: [`../sms_specials.md`](../sms_specials.md)
* How any of these systems works: [`../sms_data_architecture.md`](../sms_data_architecture.md)
* The flat address reference: [`../annotations.md`](../annotations.md)

