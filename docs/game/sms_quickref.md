# Quick reference — the addresses worth knowing by heart

The one-page card. Every entry is a pointer into a longer document; nothing is
explained here. Clean Japan ROM, SHA-1 `bc0e29ee383574443226695215496eb0d09aaa1c`
(No-Intro dump, no copier header, HiROM + FastROM).

```
file offset = SNES address & 0x3FFFFF
```

**Roster:** 1 Moon · 2 Mercury · 3 Mars · 4 Jupiter · 5 Venus · 6 Uranus ·
7 Neptune · 8 Pluto · 9 Chibi Moon. Saturn is a *Super S* character with no data
in this ROM. Per-fighter addresses: [`characters/`](characters/).

## Objects

| | |
|---|---|
| player structs | `$7E:1000` P1 · `$7E:1080` P2 |
| projectile slots | `$7E:1100` P1's · `$7E:1180` P2's |
| the bytes you will reach for | `+0x01` act · `+0x40/41/42` hit/hurt/coll index · `+0x44` attackID · `+0x45` damage row · `+0x48` first-hit defense · `+0x49` HP · `+0x4D` hitstop · `+0x50` buttons |
| **invulnerable** | `+0x41 == 0` — an empty hurtbox, not a flag |

Full struct, byte by byte: [`sms_data_architecture.md`](sms_data_architecture.md) §4.

## Boxes — bank `$8A`, read live every frame

| Table | SNES | file | entry |
|---|---|---|---|
| attack | `$8A:C1F1` | `0xAC1F1` | 8 B, index `+0x40` |
| hurt | `$8A:C229` | `0xAC229` | 16 B (body+head), index `+0x41` |
| collision | `$8A:C23D` | `0xAC23D` | 8 B, index `+0x42` |

`[x_off_R, w_R, x_off_L, w_L, y_off signed, h, flags, unused]`; origin at the
feet, +y down. Only the attack table was widened to 28 entries for projectiles.
Extracted data: [`sms_all_boxes.json`](sms_all_boxes.json).

## Combat

| | |
|---|---|
| hit checks | `$C0:BFC0` players · `$C0:C352` vs projectiles · `$C0:C745` push |
| box-overlap tests | `$C0:C959` / `$C0:C9DF` (DB = `$8A`) |
| on-hit records | `$C0:CDD5` + nine siblings, stride `0x40` — `[dmg, hitstun, level, flags]`, index `(attackID>>1)*4` |
| **hitstop / level dispatch** | `$C0:CD75`, `$C0:CD95`, `$C0:CDB5` — three 16-word jump tables selecting the modifier handler |
| modifier handlers | 11 near-identical, file `0xCAED-0xCD6D` |
| matrix lookup / matrix | `$C0:D055` / `$C0:D081` (64 × 16) |
| reaction dispatch | `$C1:0E85` (posture × hit level) |
| box-index writer | `$C0:9CCD` (batch `$C0:9CA4`) |
| object update | `JSL $C1:0000`; per-character procs via `jsr ($00A6,X)` |

⚠ The on-hit tables are **global, indexed by strength class** — editing hitstun
there changes every character's move of that class.

## Loading

| | |
|---|---|
| character load | `$C0:879B` |
| manifest pointers | `$E0:0238 + id*2` → 16 B record (defense byte + five 24-bit pointers) |
| animation layers | scripts `$C0:0000` · poses `$84:809C` · cels `$CB:0000` · OAM lists `$84:8000` |
| decompress / DMA | `$80:927D` / `$80:92AD`; asset job records via `$C3:BCCD` and `$C3:BCFF` |

## Free space

`$C1:BE09` (63 B) and `$C1:BE85` (69 B) in ROM · appended banks from **`$E8`** ·
WRAM `$0816-$09FF` (VS only) and `$7F:6000+` · VRAM CHR `0xC7-0xDF` in a match,
tiles `$5C0-$5FF` on a menu · CGRAM OBJ row 7 · **ARAM: none**.

## Where the long answers are

| Question | Document |
|---|---|
| where data lives, what shape it is | [`sms_data_architecture.md`](sms_data_architecture.md) |
| how a subsystem behaves and why | [`sms_engine_internals.md`](sms_engine_internals.md) |
| the exact address of anything | [`annotations.md`](annotations.md) |
| damage, end to end | [`sms_damage_system.md`](sms_damage_system.md) |
| A.C.S. stats and the matrix | [`sms_acs_system.md`](sms_acs_system.md) |
| menus, fonts, text | [`menu_system.md`](menu_system.md) |
| one fighter's addresses | [`characters/`](characters/) |

## Provenance

The community work this project was built on top of, and validated against:

* **sprntgd's** *Bishoujo-Senshi-Sailor-Moon-S … Training-Mode* (GitHub) — the
  training-mode Lua that supplied the original RAM map and box-table addresses,
  its colour-edit patcher, and WLA-DX hook examples.
* **The Big Zam Edition** hack — works by code hooks and expanded banks
  `$E8-$EA` rather than in-place table edits; its diff was used to validate the
  method, and patches 3 and 4 lift its palettes and credit line.
* **Dustloop's SMS wiki** — community frame data, used to sanity-check
  measurements (and, in the end, to explain a systematic offset: their numbers
  were measured mid-match, ours on fresh defenders, which is the first-hit
  defense byte).
