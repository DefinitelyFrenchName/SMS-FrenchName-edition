# Sailor Moon S (SFC) — ROM map for Uranus frame/hitbox data

> **This file is the project's original ROM map, and it is misnamed.** Only one
> section of it is Uranus-specific (her three box tables); everything else — the
> struct, the box format, the damage tables, the loader, the animation pipeline —
> is engine-wide, and it reads "Uranus" only because the project began as a
> Uranus-only effort. Kept under its published name rather than renamed.
>
> * whole-game picture, in depth: [`sms_data_architecture.md`](sms_data_architecture.md)
> * **the same addresses for any other fighter**: [`characters/`](characters/) —
>   one generated page each, measured from the ROM

Verified against the clean Japan ROM, SHA-1 `bc0e29ee383574443226695215496eb0d09aaa1c`
(No-Intro verified dump; no copier header; HiROM + FastROM; file offset = SNES address & 0x3FFFFF).

## Character IDs
1 Moon · 2 Mercury · 3 Mars · 4 Jupiter · 5 Venus · **6 Uranus** · 7 Neptune · 8 Pluto · 9 Chibimoon · (10 Saturn = Super S carry-over — NOT in this game, tables undefined)

## Player object (WRAM, 0x80 bytes each)
P1 `$7E:1000` · P2 `$7E:1080` · P1 projectile `$7E:1100` · P2 projectile `$7E:1180`

| Offset | Meaning |
|---|---|
| +0x00 | Character ID |
| +0x01 | Action ID (move/state — full list in sprntgd's SailorMoonS.lua) |
| +0x02 | Action-started / step counter |
| +0x06/07 | Action tick / frame counter |
| +0x09 | Facing (flip X) |
| +0x21 | X position (px byte of 32-bit subpixel at +0x20) |
| +0x25 | Y position |
| +0x30/32/34 | X vel / Y vel / gravity |
| +0x40 | **Attack hitbox index** (0 = none) |
| +0x41 | **Hurtbox pair index** |
| +0x42 | **Collision (push) box index** |
| +0x43 | attack_connected latch (NOT hitstop — that is +0x4D; resolved, see sms_engine_internals.md §objects) |
| +0x44 | Attack ID (indexes damage tables) |
| +0x46 | Hurt state |
| +0x48 | First-hit defense (loaded from char manifest) |
| +0x49/4A | HP / Max HP |

## Hitbox data (read directly from ROM every frame, bank $8A)
Pointer tables (16-bit offsets within bank $8A), indexed by `chara_id*2`:

| Table | SNES | File | Entry size |
|---|---|---|---|
| Attack hitboxes | `$8A:C1F1` | `0xAC1F1` | 8 bytes, index = player+0x40 |
| Hurtboxes | `$8A:C229` | `0xAC229` | 16 bytes (2×8: body+head), index = player+0x41 |
| Collision | `$8A:C23D` | `0xAC23D` | 8 bytes, index = player+0x42 |

Box entry: `[x_off_R, width_R, x_off_L, width_L, y_off(signed), height, flags, unused]`
(height 0 ⇒ no box; offsets relative to the player origin at the feet).

### Uranus (id 6)
| Data | SNES | File | Size |
|---|---|---|---|
| Attack hitboxes | `$8A:E3E1` | **`0xAE3E1`** | 0xA8 = 21 entries |
| Hurtboxes | `$8A:E489` | **`0xAE489`** | 0x510 = 81 pairs |
| Collision boxes | `$8A:E999` | **`0xAE999`** | 0x30 = 6 entries |

(Other characters' regions are contiguous; see extract script output for all.)

## Hit resolution & damage (bank $C0)
- Hit-check pass: `$C0:BFC0` (players), `$C0:C352` (vs projectiles), `$C0:C745` (push/collision).
  Reads the bank-$8A tables above with DB=$8A; box-overlap tests at `$C0:C959`/`$C0:C9DF`.
- **Damage tables**: on hit, `(player+0x44)>>1 × 4` indexes 4-byte entries
  `[damage, hitstun, hit-level, flags]` in a table family at `$C0:CDD5`, with variants at
  `$C0:CE15, CE55, CE95, **CED5**, CF15, CF55, CF95, CFD5, D015` (standing/crouching/air/projectile
  cases). **Ten tables at a stride of `0x40`** — `$C0:CED5` was missing from this list until
  2026-08-08; the arithmetic confirms the count, since `CDD5 + 10*0x40` lands exactly on the
  lookup routine `$D055`.
- Damage scaling: 16×16 matrix at `$C0:D081`, looked up via `$C0:D055`.
- Hitstop dispatch jump tables: `$C0:CD75 / CD95 / CDB5`.

## Character load (bank $C0)
- Load routine `$C0:879B`: reads per-character manifest pointer from **`$E0:0238 + id*2`**
  (file `0x200238`). Manifest: first-hit defense byte, 4 palette pointers (3B each),
  win-icon ptr, object-palette ptr, then a pointer whose data is copied/expanded to
  WRAM `$7E:6A00` via `$C0:916B` (per-character animation/sprite data).

## The animation pipeline — SINCE MAPPED (2026-07-30)
This section used to read "not yet mapped". It is, and the layers were live-verified
(`tools/saturn/probe_sms_animtables.lua`, 241/241 ALL PASS):

| Layer | SMS location |
|---|---|
| action scripts (per-step durations, box indices) | `$C0:0000` |
| pose records | `$84:809C` |
| cel tables | `$CB:0000` |
| OAM sprite-layout table (the 4th layer, found with the Saturn port) | `$84:8000` |

Per-character **proc blocks** also exist in bank `$C1` (~4.3 KB each) — an earlier
"the engine is entirely data-driven, no handler block" reading was a
baseline-contaminated measurement. The object update system at `$C1:0000` (state
processors `$C1:122A`, `$C1:15BD`) is what runs them each frame.

Timing work in practice is still done by **frame-advance measurement**, not by reading
these tables — every timing claim in this project was validated in-emulator. Dustloop's
FGC-derived frame data is the sanity check; the ROM-static version matters only when you
need the authoritative byte to patch (as patch 1 did).

> **Scope note.** This file describes the **clean ROM**. Saturn (charID 10) has no data
> here and never will; she is content this project ADDS from Super S in the Rev. SS
> builds — `docs/project/saturn/`.

## Community resources used
- sprntgd/Bishoujo-Senshi-Sailor-Moon-S-...-Training-Mode (GitHub): training-mode Lua
  (RAM map, hitbox table addresses), color-edit patcher, WLA-DX hook sources.
- Big Zam Edition hack: works via code hooks + expanded banks $E8–$EA (0x280000+),
  not in-place table edits; its diff was used to validate methodology only.
