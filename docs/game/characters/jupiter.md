# Jupiter — per-character ROM map

**charID 4** · セーラージュピター · clean ROM `bc0e29ee…` · file offset = SNES & `0x3FFFFF`

> **Generated** by `tools/mkcharmap.py` — every address on this page is read out
> of the cartridge, not transcribed. Do not hand-edit. The engine-wide map these
> addresses hang off (the object struct, the box format, the damage pipeline) is
> [`../sms_data_architecture.md`](../sms_data_architecture.md).

## Where she begins — the manifest

| | SNES | file |
|---|---|---|
| manifest record | `$E0027C` | `0x20027C` |
| palette 0 | `$E0063E` | `0x20063E` |
| palette 1 | `$E0065E` | `0x20065E` |
| win-icon palette | `$E008F6` | `0x2008F6` |
| object palette | `$E0081E` | `0x20081E` |
| sprite-CHR payload | `$E22EC0` | `0x222EC0` |

**First-hit defense: `1`** — the manifest's first byte, loaded into struct
`+0x48`. It is worth one damage-matrix column until she is first hit each round,
and it is the whole of what used to be read as damage randomness.

### Her palettes

Palette 0 — `#6a6a6a` `#202020` `#6a2000` `#e67b52` `#ff9c7b` `#ffc5c5` `#185208` `#419c18` `#2020b4` `#ff8bff` `#6a6ad5` `#b48bff` `#ff52d5` `#207300` `#c55a31` `#ffffff`

Palette 1 — `#000000` `#201820` `#6a2000` `#e67b52` `#ff9c7b` `#ffc5c5` `#312094` `#7362ff` `#2020b4` `#ffd520` `#6a6ad5` `#b48bff` `#ff8318` `#6252d5` `#c55a31` `#ffffff`

Indices 0-5 (grey, outline, four skin tones) and 15 (white) are shared across the
roster; **6-11 are the costume ramp**, and they are what makes this character look
like herself.

## Collision boxes — bank `$8A`

| Table | SNES | file | entries |
|---|---|---|---|
| attack (hit) | `$8A:D621` | `0x0AD621` | 26 × 8 B |
| hurt (body+head pairs) | `$8A:D6F1` | `0x0AD6F1` | 104 × 16 B |
| collision (push) | `$8A:DD71` | `0x0ADD71` | 6 × 8 B |

Indexed live every frame by struct `+0x40` / `+0x41` / `+0x42`. Extracted and
decoded for all nine in [`../sms_all_boxes.json`](../sms_all_boxes.json).

## Animation — her four id-indexed layers

| Layer | Table entry | Her data |
|---|---|---|
| action scripts | `$C0:0000 + 4*2` | act table at `$C0:09D6` |
| pose records | `$84:809C + 4*2` | `$84:8684`, **122 poses** × 4 B |
| cel tables | `$CB:0000 + 4*4` | pose→cel `$CB:094A`, records `$CB:0A3E`, **113 cels** × 5 B |
| OAM sprite layout | `$84:8000 + 4*3` | `$878000` |

A pose record is `[class][hit idx][hurt idx][coll idx]`, so **the pose is what puts
her hitboxes on screen**; a cel record is `[src24][len16]`, a raw CHR block DMA'd
straight to VRAM.

*(The act table's entry count is deliberately not published: entries may point
below the table, so no static derivation for it survived checking.)*

## Her code — the proc block

`$C1:5886`, **4740 bytes**, reached through the object dispatch
`jsr ($00A6,X)` with `X = 4*2`.

**Close-throw tables** (4 × 8 B, indexed by attack button; the record's last byte
is the thrower's act): `$C1:59C7`, `$C1:59E7`.

**Throw-hold scripts** (8 B per step; a step whose byte 5 is non-zero samples the
victim's mashing): `$C1:5A07`, `$C1:5A3F`, `$C1:5A67`, `$C1:5A77`.

**Cancellable light-recovery acts:** `42 47 53 57` — the frames this game's links
live in.

## Sound and menus

| | |
|---|---|
| in-match voice sound ids | `64`-`67` (id = 49 + (charID−1)×5) |
| BRR directory (ARAM) | `$34C0 + 3*32` = `$3520` |
| BRR directory (ROM) | `$E4:2D24` |
| character-select voice | bank id `25` |
| movelist tilemap | `$E27410` (compressed, codec 1 → BG3 map) |

## Further reading

* Her moves, damages and desperation: [`../sms_specials.md`](../sms_specials.md)
* How any of these systems works: [`../sms_data_architecture.md`](../sms_data_architecture.md)
* The flat address reference: [`../annotations.md`](../annotations.md)

