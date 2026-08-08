# Moon — per-character ROM map

**charID 1** · セーラームーン · clean ROM `bc0e29ee…` · file offset = SNES & `0x3FFFFF`

> **Generated** by `tools/mkcharmap.py` — every address on this page is read out
> of the cartridge, not transcribed. Do not hand-edit. The engine-wide map these
> addresses hang off (the object struct, the box format, the damage pipeline) is
> [`../sms_data_architecture.md`](../sms_data_architecture.md).

## Where she begins — the manifest

| | SNES | file |
|---|---|---|
| manifest record | `$E0024C` | `0x20024C` |
| palette 0 | `$E0057E` | `0x20057E` |
| palette 1 | `$E0059E` | `0x20059E` |
| win-icon palette | `$E008DE` | `0x2008DE` |
| object palette | `$E007BE` | `0x2007BE` |
| sprite-CHR payload | `$E20F70` | `0x220F70` |

**First-hit defense: `0`** — the manifest's first byte, loaded into struct
`+0x48`. It is worth one damage-matrix column until she is first hit each round,
and it is the whole of what used to be read as damage randomness.

### Her palettes

Palette 0 — `#838383` `#292929` `#6a2000` `#e67b52` `#ff9c7b` `#ffc5c5` `#ff6a00` `#ffd500` `#00008b` `#2041d5` `#6a6ad5` `#b48bff` `#d50000` `#ff416a` `#c55a31` `#ffffff`

Palette 1 — `#838383` `#202020` `#6a2000` `#e67b52` `#ff9c7b` `#ffc5c5` `#ff6a00` `#ffd500` `#731008` `#cd1808` `#f65239` `#ff836a` `#8b1000` `#cd1008` `#c55a31` `#ffffff`

Indices 0-5 (grey, outline, four skin tones) and 15 (white) are shared across the
roster; **6-11 are the costume ramp**, and they are what makes this character look
like herself.

## Collision boxes — bank `$8A`

| Table | SNES | file | entries |
|---|---|---|---|
| attack (hit) | `$8A:C251` | `0x0AC251` | 17 × 8 B |
| hurt (body+head pairs) | `$8A:C2D9` | `0x0AC2D9` | 89 × 16 B |
| collision (push) | `$8A:C869` | `0x0AC869` | 6 × 8 B |

Indexed live every frame by struct `+0x40` / `+0x41` / `+0x42`. Extracted and
decoded for all nine in [`../sms_all_boxes.json`](../sms_all_boxes.json).

## Animation — her four id-indexed layers

| Layer | Table entry | Her data |
|---|---|---|
| action scripts | `$C0:0000 + 1*2` | act table at `$C0:0068` |
| pose records | `$84:809C + 1*2` | `$84:80D4`, **122 poses** × 4 B |
| cel tables | `$CB:0000 + 1*4` | pose→cel `$CB:0028`, records `$CB:011C`, **103 cels** × 5 B |
| OAM sprite layout | `$84:8000 + 1*3` | `$858000` |

A pose record is `[class][hit idx][hurt idx][coll idx]`, so **the pose is what puts
her hitboxes on screen**; a cel record is `[src24][len16]`, a raw CHR block DMA'd
straight to VRAM.

*(The act table's entry count is deliberately not published: entries may point
below the table, so no static derivation for it survived checking.)*

## Her code — the proc block

`$C1:270B`, **4206 bytes**, reached through the object dispatch
`jsr ($00A6,X)` with `X = 1*2`.

**Close-throw tables** (4 × 8 B, indexed by attack button; the record's last byte
is the thrower's act): `$C1:2844`, `$C1:2864`.

**Toss records** (`[$FF][X vel 8.8][Y vel 8.8][damage]`, read by `$C1:07E5`; X is the
**forward** velocity and is negated when she faces left): `$C1:2884` (x +5.50, y -4.00, 20 dmg), `$C1:28AC` (x +5.50, y -4.00, 24 dmg).

**Cancellable light-recovery acts:** `42 48 54 58` — the frames this game's links
live in.

## Sound and menus

| | |
|---|---|
| in-match voice sound ids | `49`-`52` (id = 49 + (charID−1)×5) |
| BRR directory (ARAM) | `$34C0 + 0*32` = `$34C0` |
| BRR directory (ROM) | `$E4:2CC4` |
| character-select voice | bank id `22` |
| movelist tilemap | `$E26F40` (compressed, codec 1 → BG3 map) |

## Further reading

* Her moves, damages and desperation: [`../sms_specials.md`](../sms_specials.md)
* How any of these systems works: [`../sms_data_architecture.md`](../sms_data_architecture.md)
* The flat address reference: [`../annotations.md`](../annotations.md)

