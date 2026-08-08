# Pluto — per-character ROM map

**charID 8** · セーラープルート · clean ROM `bc0e29ee…` · file offset = SNES & `0x3FFFFF`

> **Generated** by `tools/mkcharmap.py` — every address on this page is read out
> of the cartridge, not transcribed. Do not hand-edit. The engine-wide map these
> addresses hang off (the object struct, the box format, the damage pipeline) is
> [`../sms_data_architecture.md`](../sms_data_architecture.md).

## Where she begins — the manifest

| | SNES | file |
|---|---|---|
| manifest record | `$E002BC` | `0x2002BC` |
| palette 0 | `$E0073E` | `0x20073E` |
| palette 1 | `$E0075E` | `0x20075E` |
| win-icon palette | `$E00916` | `0x200916` |
| object palette | `$E0089E` | `0x20089E` |
| sprite-CHR payload | `$E25B10` | `0x225B10` |

**First-hit defense: `0`** — the manifest's first byte, loaded into struct
`+0x48`. It is worth one damage-matrix column until she is first hit each round,
and it is the whole of what used to be read as damage randomness.

### Her palettes

Palette 0 — `#838383` `#000000` `#6a2000` `#e67b52` `#ff9c7b` `#ffc5c5` `#002000` `#009400` `#202062` `#414194` `#6a6ad5` `#b48bff` `#d50000` `#313131` `#b44120` `#ffffff`

Palette 1 — `#6a6a6a` `#201841` `#6a2000` `#e67b52` `#ff9c7b` `#ffc5c5` `#001808` `#008310` `#41186a` `#733994` `#bd8bde` `#dec5ff` `#d50000` `#52298b` `#c55a31` `#ffffff`

Indices 0-5 (grey, outline, four skin tones) and 15 (white) are shared across the
roster; **6-11 are the costume ramp**, and they are what makes this character look
like herself.

## Collision boxes — bank `$8A`

| Table | SNES | file | entries |
|---|---|---|---|
| attack (hit) | `$8A:F0C1` | `0x0AF0C1` | 21 × 8 B |
| hurt (body+head pairs) | `$8A:F169` | `0x0AF169` | 77 × 16 B |
| collision (push) | `$8A:F639` | `0x0AF639` | 6 × 8 B |

Indexed live every frame by struct `+0x40` / `+0x41` / `+0x42`. Extracted and
decoded for all nine in [`../sms_all_boxes.json`](../sms_all_boxes.json).

## Animation — her four id-indexed layers

| Layer | Table entry | Her data |
|---|---|---|
| action scripts | `$C0:0000 + 8*2` | act table at `$C0:1655` |
| pose records | `$84:809C + 8*2` | `$84:8E28`, **105 poses** × 4 B |
| cel tables | `$CB:0000 + 8*4` | pose→cel `$CB:15AF`, records `$CB:1681`, **92 cels** × 5 B |
| OAM sprite layout | `$84:8000 + 8*3` | `$898000` |

A pose record is `[class][hit idx][hurt idx][coll idx]`, so **the pose is what puts
her hitboxes on screen**; a cel record is `[src24][len16]`, a raw CHR block DMA'd
straight to VRAM.

*(The act table's entry count is deliberately not published: entries may point
below the table, so no static derivation for it survived checking.)*

## Her code — the proc block

`$C1:9E0A`, **4157 bytes**, reached through the object dispatch
`jsr ($00A6,X)` with `X = 8*2`.

**Close-throw tables** (4 × 8 B, indexed by attack button; the record's last byte
is the thrower's act): `$C1:9F33`.

**Cancellable light-recovery acts:** `41 49 55 59` — the frames this game's links
live in.

## Sound and menus

| | |
|---|---|
| in-match voice sound ids | `84`-`87` (id = 49 + (charID−1)×5) |
| BRR directory (ARAM) | `$34C0 + 7*32` = `$35A0` |
| BRR directory (ROM) | `$E4:2DA4` |
| character-select voice | bank id `29` |
| movelist tilemap | `$E27A20` (compressed, codec 1 → BG3 map) |

## Further reading

* Her moves, damages and desperation: [`../sms_specials.md`](../sms_specials.md)
* How any of these systems works: [`../sms_data_architecture.md`](../sms_data_architecture.md)
* The flat address reference: [`../annotations.md`](../annotations.md)

