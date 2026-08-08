# Uranus — per-character ROM map

**charID 6** · セーラーウラヌス · clean ROM `bc0e29ee…` · file offset = SNES & `0x3FFFFF`

> **Generated** by `tools/mkcharmap.py` — every address on this page is read out
> of the cartridge, not transcribed. Do not hand-edit. The engine-wide map these
> addresses hang off (the object struct, the box format, the damage pipeline) is
> [`../sms_data_architecture.md`](../sms_data_architecture.md).

## Where she begins — the manifest

| | SNES | file |
|---|---|---|
| manifest record | `$E0029C` | `0x20029C` |
| palette 0 | `$E006BE` | `0x2006BE` |
| palette 1 | `$E006DE` | `0x2006DE` |
| win-icon palette | `$E00906` | `0x200906` |
| object palette | `$E0085E` | `0x20085E` |
| sprite-CHR payload | `$E244C0` | `0x2244C0` |

**First-hit defense: `0`** — the manifest's first byte, loaded into struct
`+0x48`. It is worth one damage-matrix column until she is first hit each round,
and it is the whole of what used to be read as damage randomness.

### Her palettes

Palette 0 — `#6a6a6a` `#202020` `#6a2000` `#e67b52` `#ff9c7b` `#ffc5c5` `#081083` `#0820ac` `#394abd` `#6a7bd5` `#9cace6` `#cddeff` `#ffb46a` `#ffd573` `#c55a31` `#ffffff`

Palette 1 — `#5a0073` `#101010` `#6a2000` `#e67b52` `#ff9c7b` `#ffc5c5` `#202020` `#393939` `#525252` `#6a6a6a` `#a4a4a4` `#cdcdcd` `#ffb46a` `#ffd573` `#c55a31` `#ffffff`

Indices 0-5 (grey, outline, four skin tones) and 15 (white) are shared across the
roster; **6-11 are the costume ramp**, and they are what makes this character look
like herself.

## Collision boxes — bank `$8A`

| Table | SNES | file | entries |
|---|---|---|---|
| attack (hit) | `$8A:E3E1` | `0x0AE3E1` | 21 × 8 B |
| hurt (body+head pairs) | `$8A:E489` | `0x0AE489` | 81 × 16 B |
| collision (push) | `$8A:E999` | `0x0AE999` | 6 × 8 B |

Indexed live every frame by struct `+0x40` / `+0x41` / `+0x42`. Extracted and
decoded for all nine in [`../sms_all_boxes.json`](../sms_all_boxes.json).

## Animation — her four id-indexed layers

| Layer | Table entry | Her data |
|---|---|---|
| action scripts | `$C0:0000 + 6*2` | act table at `$C0:0FF1` |
| pose records | `$84:809C + 6*2` | `$84:8A44`, **115 poses** × 4 B |
| cel tables | `$CB:0000 + 6*4` | pose→cel `$CB:0F76`, records `$CB:105C`, **99 cels** × 5 B |
| OAM sprite layout | `$84:8000 + 6*3` | `$8A8000` |

A pose record is `[class][hit idx][hurt idx][coll idx]`, so **the pose is what puts
her hitboxes on screen**; a cel record is `[src24][len16]`, a raw CHR block DMA'd
straight to VRAM.

*(The act table's entry count is deliberately not published: entries may point
below the table, so no static derivation for it survived checking.)*

## Her code — the proc block

`$C1:79F2`, **5040 bytes**, reached through the object dispatch
`jsr ($00A6,X)` with `X = 6*2`.

**Close-throw tables** (4 × 8 B, indexed by attack button; the record's last byte
is the thrower's act): `$C1:7B39`.

**Throw-hold scripts** (8 B per step; a step whose byte 5 is non-zero samples the
victim's mashing): `$C1:7B59`, `$C1:7B81`, `$C1:7BB1`, `$C1:7BC9`, `$C1:7BF1`, `$C1:7C19`, `$C1:7C29`, `$C1:7C39`.

**Cancellable light-recovery acts:** `42 48 54 58` — the frames this game's links
live in.

## Sound and menus

| | |
|---|---|
| in-match voice sound ids | `74`-`77` (id = 49 + (charID−1)×5) |
| BRR directory (ARAM) | `$34C0 + 5*32` = `$3560` |
| BRR directory (ROM) | `$E4:2D64` |
| character-select voice | bank id `27` |
| movelist tilemap | `$E27790` (compressed, codec 1 → BG3 map) |

## Further reading

* Her moves, damages and desperation: [`../sms_specials.md`](../sms_specials.md)
* How any of these systems works: [`../sms_data_architecture.md`](../sms_data_architecture.md)
* The flat address reference: [`../annotations.md`](../annotations.md)

