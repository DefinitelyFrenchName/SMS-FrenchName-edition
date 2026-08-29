# The data architecture of Sailor Moon S

**What this is.** A map of *where the game's data lives and what shape it is* —
organised by the four memories the console gives you (ROM, work RAM, video RAM,
audio RAM) rather than by the order this project discovered things. Read it to
answer "where would that be stored, and what would I be looking at?"

**How it relates to the other docs.** `sms_engine_internals.md` explains how each
subsystem *behaves*; this file explains how the data is *laid out*.
`annotations.md` is the flat address phone book. `patch_notes.md` records what we
changed. When those disagree with this file, they are older: everything here was
re-measured on 2026-08-08 unless it says otherwise.

Clean ROM SHA-1 `bc0e29ee383574443226695215496eb0d09aaa1c`.

---

## 0. The one thing to understand first

**This engine is data-driven.** Very little of the game's behaviour is written as
per-character code. Instead, generic interpreters walk **records**: a character is
a manifest, a set of box tables, four animation tables and a palette; a move is a
script whose steps set box indices and durations; a menu screen is a compressed
tilemap plus a list of upload jobs; a throw is a table indexed by which button you
pressed. The engine reads those and does the same thing to everybody.

Two consequences run through everything below:

* **Most "features" are data edits.** Changing a stage's name, a hitbox, a throw's
  direction or a menu's language is writing bytes into a record — no code.
  This is why a 14-patch project has so few hooks.
* **A character can ship with the wrong data and the engine will faithfully do the
  wrong thing.** Saturn's two ground throws were on each other's buttons for
  thirty years because her close-throw table's records were swapped. The engine
  was never wrong.

The corollary for anyone reading a table: **find the interpreter before trusting
your reading of the data.** Every format below was confirmed by watching the code
consume it, and the ones that were not are marked as such.

---

## 1. The address model

HiROM + FastROM, headerless. The whole mapping reduces to one rule:

```
file offset = SNES address & 0x3FFFFF
```

| SNES banks | What they are |
|---|---|
| `$C0-$FF` | the cartridge, mapped straight through — file banks `$00-$3F` |
| `$80-$BF` | **FastROM mirror** of the same data |
| `$00-$3F` | the slow mirror, plus WRAM `$0000-$1FFF` at the bottom of each bank |
| `$7E-$7F` | the 128 KB of work RAM, addressed in full |

Three practical consequences, each of which has cost this project time:

* **The same routine has three names.** `$C0:D055` and `$80:D055` are one
  routine; the game usually *executes* from the `$80` mirror even where docs write
  `$C0`. An exec-watch on the wrong mirror sees nothing — and "the probe saw
  nothing" reads exactly like "the game doesn't do this".
* **Low WRAM is visible twice.** `$7E:1000` and `$00:1000` are the same byte.
  Memory callbacks must watch the right view or they silently never fire.
* **Bank `$EE` and friends have no WRAM mirror.** A data list placed there and
  handed to a routine that writes the OAM shadow with plain absolute stores
  vanishes; it needs the `$AE` alias.

### If that rule is not obvious yet — the long version

Two different spaces are in play, and the rule converts between them.

The cartridge is a **file**: 2.5 MB of bytes numbered `0` to `0x27FFFF`. The CPU
never sees a file. It sees an **address space** of 256 banks of 64 KB, which also
contains RAM and hardware registers. "The mapping" is just the question *which
byte of the file appears at which CPU address?* — and the cartridge's own wiring
answers it. There were two common conventions, LoROM and HiROM; this game is
HiROM, so a full 64 KB slab of the file appears in each bank.

`& 0x3FFFFF` therefore means **"throw away everything above the low 22 bits, and
what is left is the position in the file"**. Twenty-two bits because a HiROM
cartridge tops out at 4 MB, and that is all it takes to name any byte of one.
Worked out on the damage-matrix lookup:

```
$C0:D055  ->  0xC0D055 & 0x3FFFFF  =  0x00D055  ->  c2 30 85 02 a5 00
$80:D055  ->  0x80D055 & 0x3FFFFF  =  0x00D055  ->  c2 30 85 02 a5 00
$40:D055  ->  0x40D055 & 0x3FFFFF  =  0x00D055  ->  c2 30 85 02 a5 00
```

**Those are not three copies. They are one set of bytes, visible at three
addresses.** The high bits choose which window you look through, not which byte
you get; being wired into the address space several times over was normal on this
console.

The game prefers the `$80` window because it is **faster**: the SNES reads the
cartridge at 2.68 MHz through most windows and at 3.58 MHz through banks
`$80-$FF` when the cartridge asks for it — which this one does, its map-mode byte
being `$31`, HiROM *and* FastROM. About a third quicker, for free.

And that is where the cost lands. **Breakpoints and watches are keyed to an
address, not to a byte.** Break on `$C0:D055` and the CPU will execute those exact
bytes through `$80:D055` all day without tripping it; the probe prints nothing,
and nothing looks identical to "the game never calls this". Low WRAM carries the
same trap, visible as both `$7E:1000` and `$00:1000`.

One assumption the rule makes: **no copier header.** Some dumps carry an extra
512 bytes at the front, added by the hardware that made them; against one of
those, every offset in this document is wrong by 512. The SHA-1 above is what
pins that down.

### The cartridge header (file `0xFFC0`)

| Field | Value | Note |
|---|---|---|
| title | `ｾｰﾗｰﾑｰﾝSｼｭﾔｸｿｳﾀﾞﾂｾﾝ` | Shift-JIS **half-width katakana**, not ASCII. Patch 3 overwrites it with `…S FrenchName` as the ROM's ID tag |
| map mode | `$31` | HiROM + FastROM |
| rom size | `$0C` → 4096 KB | **declared**, a power-of-two ceiling |
| actual size | `0x280000` = **2.5 MB** | 40 banks, `$C0-$E7`, 20 megabit |
| country | `$00` | Japan |
| checksum / complement | `0785` / `F87A` | XOR = `FFFF`, valid |

That gap between the declared 4 MB and the actual 2.5 MB is load-bearing: it is
why every bank-appending patch can grow the image past `$E7` and still boot. The
first free bank is therefore **`$E8`**, which is why *every* standalone patch
targets it — and why chaining standalone BPS files corrupts them all.

---

## 2. Map 1 — the ROM

40 banks. Roughly: code and tables at the bottom, then a long run of graphics,
then the manifests and audio at the top.

```
$C0 ██████░░░░  engine core: char load, hit resolution, damage tables, HUD,
                the decompressor, the DMA uploaders, action scripts
$C1 ███████░░░  object update + per-character proc blocks + throw scripts/records
                (and the only verified-free code hole, at the very end)
$C2 ███████░░░  code / data
$C3 ██████░░░░  the FRONT END: menu screens, asset job table, cluster loaders,
                stage-name pointer tables, the kana font block
$C4 ██████░░░░  menu payloads: the menu font sheet, stage-name records,
                option-value records
$C5 ████████░░  graphics
$C6 ████████░░  graphics (incl. the font sheet laid out as a grid)
$C7 ███████░░░  the kanji font block + menu graphics
$C8 ███████░░░  ⎫
...             ⎬ character and stage graphics — the bulk of the cartridge
$DB ███████░░░  ⎭
$DC ██░░░░░░░░  sparse
$DD ████░░░░░░  sparse
$DE █████░░░░░  sparse
$DF ███░░░░░░░  the bank-$DF SCREEN ENGINE (win/report card, tournament) + its blobs
$E0 ████████░░  character MANIFESTS + palettes  ← the roster's index
$E1 █████████░  data (densest bank in the image)
$E2 █████░░░░░  compressed effect tiles
$E3 █░░░░░░░░░  nearly empty (12% used)
$E4 ███████░░░  audio data
$E5 █████████░  audio data
$E6 ████████░░  audio data
$E7 ███████░░░  audio data — the last vanilla bank
────────────────────────────────────────────────────────────────────────
$E8+            FREE. Every appended-bank patch starts here.
```

Bars are measured fill (bytes that are neither `00` nor `FF`); they say how
*packed* a bank is, not what is in it.

**Bank `$8A` is the exception worth knowing by heart.** It is a mirror of file
bank `$0A`, and it holds every collision box in the game — see §5.

### How bank `$C1` is divided — the proc dispatch

The one piece of genuinely per-character *code* in the game is reached through a
28-entry table at **`$C1:00A6`**, called as `jsr ($00A6,X)` with `X = id × 2`.
That table is what carves the bank up, and it gives every character's proc block
an exact address rather than the estimate the docs used to carry:

| id | Character | Proc block | Size |
|---|---|---|---|
| 1 | Moon | `$C1:270B` | 4206 B |
| 2 | Mercury | `$C1:3779` | 4141 B |
| 3 | Mars | `$C1:47A6` | 4320 B |
| 4 | Jupiter | `$C1:5886` | 4740 B |
| 5 | Venus | `$C1:6B0A` | 3816 B |
| 6 | **Uranus** | **`$C1:79F2`** | 5040 B |
| 7 | Neptune | `$C1:8DA2` | 4200 B |
| 8 | Pluto | `$C1:9E0A` | 4157 B |
| 9 | Chibi Moon | `$C1:AE47` | ~4025 B |

Ids 10-27 hold the eighteen object/projectile procs; id 0 and 28+ are `0000` and
guarded against. The cross-check that this is right: every per-character anchor
the project already knew — Uranus's dash handler `$C1:88C8`, her throw table
`$C1:7B39`, Mars's `$583C` — falls inside its own character's block.

---

## 3. Map 2 — work RAM

128 KB, and the game uses about a third of it. Low WRAM (`$7E:0000-$1FFF`) is the
part that matters: it is mirrored into bank `$00`, so all the game's code reaches
it with short addressing, and **direct page is 0 in essentially all game code** —
which is why `$8D` and `$7E:008D` are the same byte written two ways.

```
$0000 ┌──────────────────────────────────────┐
      │ direct page — the engine's registers │  D=0, so DP $8D == $7E:008D
$0100 ├──────────────────────────────────────┤
      │ stack (by convention; never probed)  │
$0200 ├──────────────────────────────────────┤
      │ OAM shadow        → DMA'd to $2104   │  every frame
$0500 ├──────────────────────────────────────┤
      │ CGRAM shadow, 512B → DMA'd whole     │  every frame: a one-shot
      │                                      │  colour poke is overwritten
$0800 ├──────────────────────────────────────┤
      │ HUD: displayed HP, timer, tile stage │  $0800-$0815
      │ ── $0816-$09FF FREE in VS matches ── │  ⚠ NOT free in Practice
$0A00 ├──────────────────────────────────────┤
      │ camera scroll X/Y                    │
$0B00 │ OBJ draw-order list                  │
$1000 ├──────────────────────────────────────┤
      │ ★ OBJECT POOL — 16 slots × 0x80      │  $1000 P1  $1080 P2
      │                                      │  $1100/$1180 projectiles
      │                                      │  $1200-$17FF unmapped
$1800 ├──────────────────────────────────────┤
      │ menus: cursors, stage index, ACS     │  $1B10 title menu
      │ staging ($1D00/$1D10), job index     │  $1C18 asset job index
      │ ($1C18), menu state ($1F5A-$1F63)    │  $1D00/$1D10 ACS stats
$2000 └──────────────────────────────────────┘
```

The direct page is where the engine keeps its working state, and a handful of
those bytes are the ones every patch in this project ends up reading:

| DP | Meaning |
|---|---|
| `$5C-$5F` | joypad held words P1/P2; `$60/$62` press edges; `$64-$67` previous frame |
| `$70` | **in-match flag** — 4 while any match runs (VS *and* Practice), 0 outside |
| `$78` | global one-shot sound id → APU port 2 |
| `$88` | current object base **in the proc dispatch only** — during script interpretation it holds whatever object last set it |
| `$8A` | menu state (`$05` = the A.C.S. screen) |
| `$8D` | **game mode**: 0 story · 1 VS · 2 vs-COM · 4 Practice · 5 Practice-with-damage *and* the attract demo |
| `$8E` | stage id (word) |
| `$8F` | **scene sprite-attribute byte** — `0x18` puts fighters at OBJ priority 3, `0x10` at 2 |
| `$90` | RNG — consumed by the ochame/misfire roll, and **by nothing in damage** |
| `$00`, `$05` | where damage is staged for the apply sites (strike/chip, throw) |

Above `$2000`, WRAM is mostly staging buffers — data on its way from ROM to
VRAM. The important ones:

| Region | Contents |
|---|---|
| `$7E:2000` | generic decompression target for menu assets |
| `$7E:6A00` | the per-character payload the char loader expands — **the compressed effect tiles**, not the animation data (an old note said otherwise) |
| `$7E:C000` | menu font staging: `$C4:2590` lands here, then DMAs to VRAM. Its ceiling is `$4000` bytes, because more runs off the end of bank `$7E` |
| `$7E:1900+`, `$7E:3640+` | two staging areas whose **fillers are unfound** — they are written by block moves, which per-byte write watches never see |
| `$7F:C000-$FFFF` | the variable-text engine's font: `$C2:4580`, codec 1, 512 units of `$20` (record `$C3:BE30`). ⚠ **`$7F:DC00+` is inside this buffer**, not a separate staging area — it is `$C000 + $1C00`, the blank high-code region, which is why nothing was ever seen filling it. Older notes call it patch 16's blocker; it was not |
| `$7F:0000-$5FFF` | scene-load scratch |
| `$7F:6000+` | **free** — zero steady-state traffic. Patches 11/13/14/100 keep their state here |

---

## 4. The object struct — the centre of the engine

Everything that moves is one of these: both fighters, both projectiles, and even
the report-card portrait. Sixteen `0x80`-byte slots from `$1000`.

```
      ┌0──────1──────2──────3──────4──────5──────6──────7──────┐
 +00  │ WHO AND WHAT STATE           │ POSE / ANIMATION        │
      │ charID actID step  step  act │ pose  tick  frame       │
 +08  │ pal   face  ── cel pointers and sizes ──────────────── │
 +10  │ ...                          │ flags class             │
 +18  │ act flags                    │ (unmapped)              │
 +20  │ ★ X POSITION (32-bit subpixel, pixel byte at +0x21)     │
 +28  │ screen pos    │ (unmapped)                              │
 +30  │ ★ VELOCITY  X vel │ Y vel │ gravity │ ... │ pushback    │
 +38  │ ...                                                     │
 +40  │ ★ BOXES: hit │ hurt │ coll │ connected │ atkID │ dmg    │  ← the four
 +48  │ d48   HP    maxHP  │ ...  │ hitstop │ ...               │     bytes a
 +50  │ ★ INPUT: held │ cmd │ btns │ cmd │ flags │ ... │ mash   │     patch
 +58  │ ── command recognizer timer/state pairs ($5B-$68) ───── │     usually
 +60  │ ...  (+0x5D = the 66 dash's timer AND its frame 1..14)  │     wants
 +68  │ ...                                                     │
 +70  │ ★ A.C.S. STATS: atk def hp spc sec och │ upd │ strength │
 +78  │ sound id │ (unmapped)                                   │
      └────────────────────────────────────────────────────────┘
```

The fields worth knowing by name:

| Off | Field | Why it matters |
|---|---|---|
| `+0x00` | charID / **object type id** | 1-9 are fighters; **10-27 are projectile types**. A projectile picks its box table by its OWN id, not its owner's |
| `+0x01` | actionID | 0x00-0x2A universal (idle, walk, blockstun, hitstun, knockdown, KO…), 0x2B+ per-character |
| `+0x05` | pose id | indexes the sprite list. An out-of-range pose makes the emitter read a garbage sprite COUNT and flood OAM — the signature of a corrupted throw |
| `+0x08` | palette + priority | OAM attribute is this byte `<< 1`; projectiles get 2 or 3 **by slot**, not by character |
| `+0x18` | action flags | **bit0 = "this act is an attack"** — the engine's own discriminator, and the right test to use instead of `act ≥ 0x2B` |
| `+0x40/41/42` | hit / hurt / coll box index | rewritten every frame from animation data by `$C0:9CCD` |
| `+0x41` = 0 | **invulnerable** | not a flag — an empty hurtbox |
| `+0x44` | attackID / strength class | `(id>>1)*4` indexes the on-hit tables |
| `+0x45` | damage | the **row** into the damage matrix |
| `+0x46` | hurt state | ≥0x80 untargetable, 0xA0 knocked down, 0xE0 thrower during a grab |
| `+0x48` | **first-hit defense** | manifest-loaded, worth +1 matrix column until first hit, then cleared. This is the "damage randomness" that isn't |
| `+0x49/4A` | HP / max HP | base `0x60`; max = `0x60 + 8×ACS health` |
| `+0x4D` | hitstop countdown | animation ticks stall while nonzero; frame data excludes these frames |
| `+0x50` | buttons held | `1` back `2` fwd `4` down `8` up `0x10` LP `0x20` LK `0x40` HP `0x80` HK — **press bits latch at 30 Hz**, so mashing yields ~1 press per 2 frames |
| `+0x56` | throw mash counter | on the THROWER; ≥2 and the victim techs |
| `+0x5B-0x68` | recognizer timer/state pairs | the motion inputs live here; `+0x5D` doubles as the dash's frame counter |
| `+0x70-0x75` | the six A.C.S. stats | attack, defense, health, special, secret, ochame |
| `+0x77` | action strength | 7 LP, 8 LK, 9 HP, 10 HK. The button map is **Y=LP X=HP B=LK A=HK** |

About a third of the struct is still unmapped (`0x19-0x1F`, `0x2B-0x2F`,
`0x3B-0x3F`, `0x57-0x5A`, `0x69-0x6F`, `0x79-0x7F` among others) — listed here as
unknown rather than guessed at.

---

## 5. Box data — the one table you will read most

Three pointer tables sit next to each other in bank `$8A`, each indexed by
`id * 2`:

| Table | SNES | Entries | Indexed by |
|---|---|---|---|
| hit (attack) | `$8A:C1F1` | **28** | struct `+0x40` |
| hurt | `$8A:C229` | 10 | struct `+0x41` |
| collision (push) | `$8A:C23D` | 10 | struct `+0x42` |

They are `0x14` bytes apart — the hurt table ends exactly where the coll table
begins. That adjacency is not trivia: **only the hit table was widened to 28
entries** for projectiles, so indexing hurt or coll by a projectile's object id
runs straight off the end into the neighbouring table's bytes. Gameplay never
notices (nothing reads a projectile's hurtbox), but a tool that draws one renders
a flickering phantom from unrelated data.

Per character the three tables are **contiguous**, and the characters follow each
other in roster order:

| Character | hit | hurt | coll |
|---|---|---|---|
| Moon | `$8A:C251` ×17 | `$8A:C2D9` ×89 | `$8A:C869` ×6 |
| Mercury | `$8A:C899` ×22 | `$8A:C949` ×87 | `$8A:CEB9` ×6 |
| Mars | `$8A:CEE9` ×33 | `$8A:CFF1` ×96 | `$8A:D5F1` ×6 |
| Jupiter | `$8A:D621` ×26 | `$8A:D6F1` ×104 | `$8A:DD71` ×6 |
| Venus | `$8A:DDA1` ×18 | `$8A:DE31` ×88 | `$8A:E3B1` ×6 |
| Uranus | `$8A:E3E1` ×21 | `$8A:E489` ×81 | `$8A:E999` ×6 |
| Neptune | `$8A:E9C9` ×25 | `$8A:EA91` ×96 | `$8A:F091` ×6 |
| Pluto | `$8A:F0C1` ×21 | `$8A:F169` ×77 | `$8A:F639` ×6 |
| Chibi Moon | `$8A:F669` ×16 | `$8A:F6E9` ×76 | `$8A:FBA9` ×6 |

Then the projectile/object tables run from `$8A:FBD9` to `$8A:FDA1` — **9 distinct
tables shared by object ids 10-27** (several ids point at the same table).

Every box is 8 bytes:

```
 0     1     2     3     4        5    6      7
 x_off_R  w_R  x_off_L  w_L  y_off(s)  h   flags  (unused)

 origin is at the character's FEET, +y is DOWN, so y_off is normally negative.
 h == 0 or w == 0 means "no box". Facing picks the (x_off, w) pair.
 flags: bit0 = H, bit1 = L, bit2 = J  (guard height / jump property)
```

A **hurt entry is two boxes** (16 bytes): body then head. There is no damage
difference between them — contact zone does not affect damage in this engine.

**Invulnerability is the absence of a box, not a flag:** hurtbox index 0 is an
empty pair, and that is exactly how the backdash is invincible for all 14 of its
frames.

---

## 6. Character manifests — the roster's index

`$E0:0238 + id*2` holds a 16-bit pointer into bank `$E0`. That record is where a
character begins:

| Character | id | manifest | first-hit defense | palette 0 |
|---|---|---|---|---|
| Moon | 1 | `$E0:024C` | 0 | `$E0:057E` |
| Uranus | 6 | `$E0:029C` | 0 | `$E0:06BE` |
| Neptune | 7 | `$E0:02AC` | **2** | `$E0:06FE` |
| Pluto | 8 | `$E0:02BC` | 0 | `$E0:073E` |

The record is **16 bytes: one defense byte and five 24-bit pointers** — and it is
smaller than the docs used to claim, because a character has only **two** body
palettes, not four:

```
+0x00  1B   first-hit defense      -> struct +0x48
+0x01  3B   body palette 0    (0x20 bytes -> CGRAM staging $0600)
+0x04  3B   body palette 1    (the alternate; the confirm button picks via $1D02)
+0x07  3B   a 4-colour palette (8 bytes -> $0530)
+0x0A  3B   the object palette (0x20 bytes -> $0640)
+0x0D  3B   the LZ payload    -> her compressed sprite CHR
```

⚠ **Where that payload lands is a long-standing doc error.** The ROM map and
`annotations.md` both say it is "copied/expanded to WRAM `$7E:6A00`". Read at the
call site, the `$6A00` is a **VRAM word address**: the loader decompresses into
staging and DMAs to VRAM, and the payload is compressed sprite CHR rather than
anything animation-logical. The same idiom appears in the movelist loader, where
`$1000` is plainly the BG3 tilemap's VRAM address. *(Disassembly-derived this
session; not yet confirmed by watching it run — worth a probe before anyone
relies on it.)*

Decoded, Uranus's (`$E0:029C`): `00 | $E0:06BE | $E0:06DE | $E0:0906 | $E0:085E |
$E2:44C0`. The payloads are 0x6F0-0xD40 bytes — far too small to be sprite
sheets, which is the clue that the cels live elsewhere entirely (§9).

That **first byte is a real balance value hiding in plain sight**: it is the
defender's first-hit defense, worth one damage-matrix column until the character
is first hit that round. The full census, decoded from all nine manifests:
**Jupiter 1, Neptune 2, everyone else 0** — which matches the two values that had
been measured live, and closes an open question the damage doc had left to "needs
boot-fresh rounds".

This one byte is the mechanism behind every "damage varies randomly" reading this
project ever made. **There is no RNG in damage.**

### The palettes are the character

A character palette is 16 colours, BGR555, and they are structured identically
across the roster:

```
 index  0      1        2  3  4  5        6 … 11            12 13    14      15
        grey   outline  skin ramp         COSTUME RAMP      accents  shared  white
```

Only indices 6-11 differ meaningfully between characters — that ramp *is* the
character's identity on screen, which is why re-hueing it is how this project
authors new palette slots. Uranus's, read out of `$E0:06BE`:

`#6a6a6a` `#202020` `#6a2000` `#e67b52` `#ff9c7b` `#ffc5c5` **`#081083` `#0820ac`
`#394abd` `#6a7bd5` `#9cace6` `#cddeff`** `#ffb46a` `#ffd573` `#c55a31` `#ffffff`

---

## 7. Map 3 — video memory

VRAM is the one memory whose layout **changes completely between a match and a
menu**, which is the single biggest source of wasted debugging time in this
project.

### In a match (BG mode 1)

```
VRAM word
$0000  ┌─────────────────────────────┐
       │ BG1 tilemap (stage)         │
$0800  │ BG2 tilemap (stage)         │
$1000  │ BG3 tilemap ── THE HUD ──   │ rows 3-4 bars, 5 nameplates + timer,
       │                             │ 6-7 the round-won badges
$2000  ├─────────────────────────────┤
       │ BG1 + BG2 CHR (stage art)   │ 4bpp
$5000  ├─────────────────────────────┤
       │ BG3 CHR (2bpp): digits at   │ tile 0x50/0x60 = the timer's glyphs
       │ 0x50-0x69, A-Z at 0x70-0x89 │ ⚠ the full alphabet IS resident
       │ ── 0xC7-0xDF FREE (25) ──   │ patches 10/11 put fonts here; Saturn's
       │ 0xE0-0xFF round-won badges  │ badge takes 0xCE/CF/DE/DF (Super S's own)
$6000  ├─────────────────────────────┤  ← OBJ name base
       │ P1 cels $6000  P2 cels $6500│ DMA'd from ROM per frame, uncompressed
       │ P1 fx $6A00    P2 fx $7300  │ per-character effect sheets
$7000  │ (second OBJ name table)     │
$8000  └─────────────────────────────┘
```

* A tilemap word is `flip<<14 | prio<<13 | palette<<10 | tile`. The HUD writes
  `0x2C00 | tile` — priority bit set, palette 3 — and because `mode1Bg3Priority`
  is on, **those tiles draw above the sprites**. That is what makes an in-match
  text overlay possible without touching the sprite engine.
* **Layer enable (`$212C`) is written only at scene setup**: `0x17` in VS,
  `0x13` in Practice (BG3 off, because BG3 there holds the pre-staged movelist —
  Start just flips the layer on).
* ⚠ **Address a sprite tile through the OBJ name base**, never as `tile * 32`.
  Getting this wrong once produced an entire "root signature" measured out of
  unrelated VRAM.
* ⚠ **Sprite lists are emitted on alternate frames.** Trigger a capture on the
  thing you want to see, not on a frame delay.

### On a menu screen

```
VRAM tile
$0200  ← BG1 CHR base, so:  MAP tile = VRAM tile − $200
$0400  ┌─────────────────────────────┐
       │ the menu font sheet         │ $C4:2590 (418 tiles) staged in $7E:C000
$05B5  │ ...ends here                │ transfer: vram $4000 len $3480
$05C0  │ ── FREE: 64 tiles ──        │ = 32 half-width glyphs. Patch 16's home
$0600  ├─────────────────────────────┤
       │ screen art                  │
$0738  │ ── FREE: 136 tiles ──       │
$07C0  └─────────────────────────────┘
```

`$5C0-$5FF` is free on **every** menu screen and first used at match load — a
pass for menu text, and a fail for anything that must survive into gameplay. The
probe that established this is worth copying: it snapshots *and* write-watches,
because **DMA never surfaces as a CPU write callback**. The write watch saw zero
writes while the snapshots caught 1416 bytes arriving.

⚠ **A screen transition clears all 64 KB of VRAM** (a fixed-source DMA with
`len $0000` = 65536) and the destination screen then reloads only its own asset
list. "It was in VRAM a moment ago" proves nothing about the next screen.

### Colour

256 colours as 16 rows of 16 — rows 0-7 for backgrounds, 8-15 for sprites. The
engine keeps a **512-byte CGRAM shadow at `$7E:0500` and DMAs the whole thing
every frame**, so a one-shot colour poke is erased by the engine's own refill,
invisibly, since that refill is a DMA.

Censused over a full match, only OBJ rows **0, 1, 2 and 4** are ever drawn.
Row 7 is all zeros and never loaded — which is precisely why the Saturn port
moved her projectiles there. And each character ships **exactly two** palettes;
the other two pointers in the manifest are the icon and effect palettes, not
character colours.

---

## 8. Map 4 — audio memory

> The audio system end to end — how these 64 KB get filled, how a sound id becomes
> a note, and where each fighter's voice pitch is decided — is
> [`sms_sound_system.md`](sms_sound_system.md).

The APU has its own 64 KB, and it is **full**: the largest run of zeros in the
whole of ARAM is 64 bytes.

```
ARAM
$0800  driver (its ROM home is file offset = ARAM + 0x23F804)
$2800  sequence data — swapped per scene
$3400  BRR sample directory, 64 entries × [start16, loop16]
$34C0  ★ the nine-character VOICE DIRECTORY, boot-resident,
       $34C0 + (charID-1)*32 — ROM source $E4:2CC4 + (charID-1)*32
$3800  resident instrument samples
$8E00  swappable sample slot (per scene)
$9B92  ~7 KB that looks free and is not (trap 2)
$B700  ★ P1's VOICE BANK   (directory entries 48-55)
$DB00  ★ P2's VOICE BANK   (directory entries 56-63)
$FE8B  end of samples
```

Two facts explain most of the audio architecture. First, **a fighter's voice is
uploaded per player, not per character** — the same nine-character directory is
resident from boot, but the actual samples for the two fighters on screen are
streamed into two fixed banks. Second, **pitch is per-sound note data, not a
per-sample rate**: each sound's sequence header carries a transpose byte at
`seq+3` worth one semitone per unit. That is the whole mechanism behind patch 101
— and the reason it cannot fix two characters at once, since the transpose lives
in a shared sequence.

---

## 9. The record catalogue

Every format below is followed by a real example decoded out of the clean ROM,
because a layout without a worked example is a hypothesis.

### Box entry — 8 bytes

```
[x_off_R][w_R][x_off_L][w_L][y_off signed][h][flags][unused]
```
Origin at the feet, +y down. `h == 0` or `w == 0` = no box. `flags` bit0 H,
bit1 L, bit2 J. A **hurt entry is two of these** (16 bytes): body, then head —
and the head box carries no damage difference, contact zone does not affect
damage in this engine.

### On-hit record — 4 bytes, indexed by `(attackID >> 1) * 4`

```
[damage][hitstun][hit level][flags]
```

`$C0:CDD5` and its **nine** sibling tables select on (attack, defender posture) —
`CDD5, CE15, CE55, CE95, CED5, CF15, CF55, CF95, CFD5, D015`, ten in all at a
stride of `0x40`. ⚠ Older docs list nine and omit **`$C0:CED5`**; the arithmetic
settles it, since `CDD5 + 10 × 0x40` lands exactly on the lookup routine at
`$D055`. Decoded:

| idx | attackID | damage | hitstun | level |
|---|---|---|---|---|
| 0 | 0/1 | 6 | 8 | 1 |
| 2 | 4/5 | 10 | 8 | 2 |
| 4 | 8/9 | 14 | 8 | 2 |
| 7 | 14/15 | 24 | 8 | 2 |

⚠ These tables are **global, indexed by strength class, not by character**.
Editing hitstun here changes every character's move of that class — which is why
this project has never patched them.

### The damage matrix — 64 rows × 16 columns at `$C0:D081`

`final = MATRIX[attacker+0x45][(modifier + 8) & 15]`. Column 8 is neutral, lower
columns are stronger. Row 8 reads:

```
col   0   1   2   3   4   5   6   7   8   9  10  11  12  13  14  15
     17  16  16  16  15  14  12  10 [ 8]  6   5   5   4   4   4   4
```

The modifier is composed by eleven near-identical handlers at file
`0xCAED-0xCD6D`: counter-hit shifts it −2 columns, the defender's first-hit
defense +1, A.C.S. attack/special shift left, A.C.S. defense right. **Nothing in
that chain reads the RNG.**

### Character manifest — pointer at `$E0:0238 + id*2`

```
[first-hit defense byte][palette ptr ×24][win icon ptr24][obj palette ptr24][payload ptr24]
```
Records are `0x10` apart. Each character ships **two** character palettes; the
remaining pointers are the icon and effect palettes.

### Compressed-asset job record — 10 bytes

```
[vram16][len16][src24][dest24]
```

There are **74 records**, spanning `$C3:BD61-$C3:C04B`, reached through **two
pointer tables**: `$C3:BCCD` (25 entries, every one a `0x800`-byte 32×32 tilemap)
and `$C3:BCFF` (49 entries, the CHR and big text sheets). The two are disjoint —
25 + 49 = 74 distinct addresses, verified. A screen names a record by writing
`index × 2` into `$1C18`.

⚠ **Older docs say "58 records at `$C3:BE08`" (or 59 at `$C3:BE02`). That is an
artifact of the discovery method**: a flat 10-byte-stride scan from `$BE08`
finds the last contiguous stretch and silently misses the 16 records before it.
Walk the pointer tables instead.

### The OTHER job table — in-match assets, `$E0:0000`

⚠ **The `$C3` records are not the only asset system, and the in-match HUD does not
come from them.** A second, simpler table sits at **`$E0:0000`** with **6-byte
entries**:

```
[src16][srcbank][vram16][flags]
```

It is the same shape `tools/saturn/supers_lz.py` documents for Super S's
`$80:EEF1`. Entry 0 is the **in-match BG3 CHR sheet** — `sms_lz`-compressed at
**`$E0:21E6`**, `0xF31` bytes in, `0x2000` out (512 tiles), uploaded to VRAM word
`$5000`; entry 1 is the HUD tilemap, to word `$1000`.

⚠ **There is no length field in the record.** The transfer is sized by how much
the decoder wrote, so editing one of these sheets means the re-encoded stream
must still expand to exactly the same size — the size is the contract, not the
compressed length. (`tools/saturn/sms_lz.py`'s `encode_lz` exists for this: the
older `encode` is literals plus one RLE trick and *expanded* this sheet from
`0xF31` to `0x1B95`, which would have forced a relocation.)

Two facts worth having when hunting art in this game: this sheet is where the
timer digits (`$50`-`$69`), the nameplate alphabet (`$70`-`$89`) and the eight
round-won medallions (`$E0`-`$FF`) live, and the free window `$C7`-`$DF` is
**empty in the sheet itself**, not merely empty in VRAM. And **Super S ships the
same 512-tile sheet RAW at `$E0:D2B8`** — 503 of 512 tiles byte-identical — which
is why no compressed-stream search finds the donor's copy.

⚠ **An asset can be named by more than one record**, which matters to anything
that relocates one. Ten sources are referenced twice — including **`$C3:48D0`,
the big text sheet**, uploaded to VRAM `$2C00` by record `$C3:BEBC` and to
`$2A00` by `$C3:BEE4`; the other nine pairs are the same block sent to `$4000`
on one screen and `$3000` on another. Repointing the record you happened to find
leaves the other pointing at the original block. That is benign when the original
survives (the second screen simply keeps the vanilla asset) and corrupting when
it does not — which is why patch 16 relocates rather than edits in place, and why
the screens it has *not* repointed need their own glyph-delivery hook.

⚠ **The length sits two bytes BEFORE the source pointer.** Reading it the other
way round pairs record N's length with record N+1's source, which is exactly the
mistake that made three attempts to grow a transfer "change nothing" — they were
silently lengthening an unrelated upload. Decoded, the menu font's record:

```
$C3:BF16   vram $4000   len $3480   src $C4:2590   dest $7E:C000
```

Patch 16 changes exactly one field of that record — `len` to `$4000` — and that
is the entire font-install mechanism.

### Stage-name record — `0x66` bytes, stride `0xCC`, in bank `$C4`

```
+0x00  header  e4 02 30 00 02 00      (0x30 = a row field's size)
+0x06  TOP row     exactly 24 words   ← 12 glyphs max
+0x36  BOTTOM row  exactly 24 words   ← the same glyphs + 0x10
```

**There is no terminator.** The name is *centred* by leading and trailing zero
words. Stage 2 decoded — eight zero words, then the name, then eight more:

```
top: 0000 ×8  0F48 0F49 0F4A 0F4B  0D02 0D03  0F4C 0F4D  0000 ×8
              時                   の         扉
bot: 0000 ×8  0F58 0F59 0F5A 0F5B  0D12 0D13  0F5C 0F5D  0000 ×8   (= top + $10)
```

⚠ **A run of zeros after a string is not evidence of a terminator.** Read as
"start at the first glyph, stop at `0000`", this record looks terminated — and a
build made on that reading wrote a longer name straight through the bottom row
and into the next stage's header, corrupting the screen and hanging the game a
second after stage select. Two records side by side would have shown the padding
immediately.

### Runtime text record — drawn by `$80:8C43`

```
[vmadd16][len16][rows16][cells…]
```

Self-describing and **uncompressed**, in bank `$C4`, one record per value per
highlight state. This is how the option values and the tournament rows are drawn,
and it is why a tilemap-only edit of a *value* gets overwritten: the tilemap holds
the initial state, this record holds every redraw.

### Normals record — 3 bytes, four per table

`[distance threshold, far act, close act]`, read by `$C1:0459`. Four records per
table, indexed by the fresh attack-button bit in the high nibble of `+0x50` (falling
back to `+0x52`) in the **same order the throw table uses** — `0x10`→LP, `0x20`→LK,
`0x40`→HP, `0x80`→HK. The distance is `abs(opponent +0x21 − self +0x21)` from
`$C1:0439`; threshold ≥ distance selects the close act, else the far act, and a
threshold of `255` means the button has no proximity variant.

⚠ **One table per STANCE, not one per character.** Each act handler passes the table
for its own stance, which is the entire mechanism behind command normals — there is
no direction-keyed table anywhere. Uranus: standing `$C1:7AF5`, crouching `$C1:7B01`,
neutral jump `$C1:7B0D`, directional jump `$C1:7B19` (neutral and directional jumps
genuinely differ). Full worked example and the per-act census:
`sms_engine_internals.md` §7.x.

### Special-start entry — 1 word, 8-12 per table

`[flags, act]` (low byte = flags, high byte = act), read by the special starter
`$C1:0952`/`$C1:0958`, indexed `(pending nibble − 2) × 2`. Flags: `01` ground-only
(`+0x16` bit7 SET), `02` air-only, `04` own projectile slot must be free, `08`
desperation gate. **Membership in this table is what makes a move a special** — see
`sms_specials.md` § "Where 'special' is encoded". One table per character, bounded by
the throw table the same handler passes to `$C1:055A`.

### Throw records

Three separate data structures decide what a throw does, which is why a character
can have all three wrong independently:

**1. Which throw comes out** — a 4 × 8-byte table indexed by attack button
(`$C1:055A`; `0x10`→LP, `0x20`→LK, `0x40`→**HP**, `0x80`→**HK**). Structurally it
is the box entry again, with `flags`/`unused` replaced by a gate and an act:

```
+0 gate   $FF = this button has no throw; low 2 bits test the opponent's state
+1..+4    the range box, one (x_off, w) pair per facing
+5..+6    y_off, height
+7 act    the THROWER's action ID
```

Uranus's (`$C1:7B39`): LP and LK are `FF` — no throw. HP is
`03 00 28 D8 28 D0 30 5B` — no state condition, reach 1..40 px forward, act `$5B`.
HK is `01 …` — the gate requires the opponent's `+0x16` bit 7 *set*.

**2. Where the victim goes** — a toss record read by `$C1:07E5`:
`[$FF marker][X vel 8.8][Y vel 8.8][damage]`. X is **negated when the thrower
faces left**, so the record always holds the *forward* velocity. Uranus's
(`$C1:7B81`) is `FF 80 01 80 FA 18` — X `+$0180`, Y `−$0580`, damage 24. A
negative X here means the throw comes out backwards on 6 and forwards on 4, which
is exactly the fault Saturn shipped with.

**3. How escapable it is** — the hold script, 8 bytes per step (`$C1:06E5`):
`[victim pose][drag X 8.8][drag Y 8.8][mash sampling][sfx][swap]`. **A step whose
byte 5 is non-zero samples the victim's mashing that frame.**

Teching is mash-counted, not a one-press window: the sampler increments the
**thrower's** `+0x56`, and at the toss `≥ 2` sends the victim to the tech act at
half damage. The threshold is global; the only per-throw variable is how many
steps sample. Patch 8 changes one byte of one script.

### Animation — four id-indexed layers, and how they chain

This is the heart of the data-driven design, so it is worth following all the way
through. Four tables, each indexed by the object's id:

| Layer | Table | Entries | A record is |
|---|---|---|---|
| action scripts | `$C0:0000` | 28 | a **byte stream** of animation steps (below) |
| pose records | `$84:809C` | 28 | **4 bytes**: `[class][hit idx][hurt idx][coll idx]` |
| cel tables | `$CB:0000` | **10 — roster only** | `[pose→cel ptr][cel-record ptr]` |
| OAM sprite layout | `$84:8000` | 28 | `[ptr16][bank]` → per-pose sprite lists |

**The action-script step**, walked by the interpreter at `$C0:A05C`:

```
d & 0xC0 == 0x00   STEP   2 bytes [d][pose]   this pose for d+1 frames
d & 0xC0 == 0x40   LOOP   1 byte              restart the script
d & 0xC0 == 0x80   HOLD   1 byte              freeze on the last pose
```

⚠ The loop command **ignores its operand** — the interpreter is `stz $07,X`, so it
always restarts at step 0. (An extractor in `tools/` records the operand as a
target; it is never used.)

**The pose record is where a move's hitboxes actually come from.** Its first byte
is the class that lands in struct `+0x18` — the "this is an attack" bit — and the
other three are the box indices copied into `+0x40/41/42` every frame.

#### The whole chain, in one move

Uranus's crouching light punch (act `0x53`), read end to end out of the ROM:

```
1. act table for id 6      $C0:0000 + 6*2        -> $C0:0FF1
2. script for act 0x53     $C0:0FF1 + 0x53*2     -> $C0:122C
                                                    02 35 | 03 36 | 80
                                                    3f pose $35, 4f pose $36, hold
3. pose record 0x36        $84:809C + 6*2 -> $84:8A44, + 0x36*4
                                                    09 0A 2C 02
                                                    class 9 · hit $0A · hurt $2C · coll $02
4. hit box 0x0A            $8A:C1F1 + 6*2 -> $8A:E3E1, + 0x0A*8
                                                    FC 37 CD 37 CC 14 03 00
                                                    x -4 w 55 · y -52 h 20 · hits high+low
```

Four table reads, no code. Pose `0x35` — the startup — carries hit index `00`,
which is exactly how a startup frame is expressed: **a pose with no attack box.**
Change the `02` in step 1 and you have changed her startup; that is the entire
mechanism behind this project's frame-data patches.

**Cel records** (the graphics) are 5 bytes, `[src24][size16]` — a raw CHR block
and its length, DMA'd straight to VRAM. **Sprite-layout lists** are a count byte
followed by 6-byte records, `[x, x_flipped, y, attr, tile, attr_flipped]`. That
leading count is why a bad pose id is catastrophic rather than merely wrong: the
emitter reads a garbage length and floods OAM — the signature of the Saturn throw
corruption.

⚠ Byte 3 of a sprite record is **not unused**, as `annotations.md` has it: the
unflipped emitter reads bytes 3-4 as (attr, tile), the flipped one reads bytes 4-5
as (tile, attr). Two emitters, two attribute bytes.

### The two compression codecs

| | Codec 1 | Codec 2 |
|---|---|---|
| entry | `$C0:916B` / `$80:927D` | `$80:8E9A` |
| used for | movelists, menu tilemaps, font blocks, stage art | the bank-`$DF` screen engine's tilemaps |
| status | **fully decoded and re-encodable** (`tools/saturn/sms_lz.py`; all nine vanilla movelists round-trip to exactly `0x800`) | **not decoded.** The whole record is one sentence — tile-unit, XOR row filters, a 2-bit command stream — and no implementation exists. Nothing shipped needs it |

⚠ Our encoder is weaker than the original's: even an *untouched* block re-encodes
larger. So an edited block is always **relocated into an appended bank** and its
record repointed, never written back in place.

---

## 10. The four pipelines

### A. Loading a character

```
charID
  └─ $E0:0238 + id*2 ─────────────► manifest record (bank $E0)
        ├─ first-hit defense byte ─► struct +0x48
        ├─ palette pointers ───────► CGRAM shadow $7E:0500  ─DMA every frame─► CGRAM
        ├─ win icon / obj palette
        └─ payload pointer ────────► $C0:916B decompress ──► $7E:6A00
                                                              └─DMA─► VRAM effect tiles
  box tables are NOT copied: $8A:C1F1/C229/C23D are read straight out of ROM
  every frame, indexed by the struct's own +0x40/41/42.
```

The load site is `$C0:879B` (P1; P2 has its twin). Note what *doesn't* happen:
no per-character code is selected, and the boxes are never staged anywhere —
which is why editing bank `$8A` changes the game with no hooks at all.

### B. One frame

Disassembled 2026-08-09, not inferred — the loop is straight-line code and this is
its call list. Six sibling phase loops share it (`$C0:E21A` entrance, **`$C0:E255`
the round**, `E2E2`, `E30F`, `E41E`, `E8D3`); a phase differs by which stages it
leaves out.

```
NMI  $00:FFEA ─► $C0:FFA6 ─► $80:98DB ─► jmp ($98FD,X)  per game state
 └─ in match, $C0:D4C9:  queued transfers $8448 · OAM+CGRAM shadows $80:9EF5
                         · HUD uploader $D56F · pads $8353 ─► $5C-$5F, $60/$62
                         · sets DP $6C ────────────────────────────┐
                                                                   │ releases
main loop $C0:E255, one pass = one frame                           ▼
 ├─ $80:8386  wait for vblank (spins on DP $6C)
 ├─ $C0:E071  pause / start          ├─ $C0:9633  input + camera snapshot
 ├─ $C1:0E26  APPLY REACTIONS  ── the pending code left on +0x47 LAST frame,
 │             through the posture x level dispatch $C1:0E85 ─► an act
 ├─ $80:A05C  animation scripts ─► duration +0x06, pose +0x05
 ├─ $80:9C96  poses ─► boxes    ─► class +0x18, indices +0x40/41/42 ($C0:9CCD)
 ├─ $C1:2584  effect pool ($1200)     ├─ $C1:16EE  projectile pool ($1100/$1180)
 ├─ $C1:0000  OBJECT UPDATE ── jsr ($00A6,X) by id ─► each character's proc,
 │             and it is IN THERE that hits are detected (below)
 ├─ $80:9FB8  resolve cels      ├─ $C0:8BCB  world ─► screen (+0x28)
 ├─ $C0:9CE2  build the draw list at $0B00
 ├─ $80:9A0E  emit sprites ─► OAM shadow $7E:0200
 ├─ $C0:D5E8  HUD producer ─► staging $0806-$0815   (never runs in Practice)
 ├─ $C0:DB35  round state   ├─ $C0:B321  stage scroll (jmp ($B32B,X) on $8E)
 ├─ $C0:8CAF  ─  ├─ $C0:8BF9  advance the RNG (DP $90)
 └─ bra $E255
```

⚠ **Hit resolution is not a stage of the loop.** `$80:BFBB` (whose body is the
`$C0:BFC0` this doc used to call the hit check) has **192 call sites and every one
of them is in bank `$C1`** — the characters' own procs call it while they run,
inside stage 9. The same holds for projectile collision `$80:C352` (22 sites) and
push `$80:C745` (1, from the update's head). That is the mechanism behind the two
things everyone trips over: an attack is resolved by the attacker's code, and the
victim's reaction is applied at the TOP OF THE NEXT PASS, one frame later. The
damage the hit does is subtracted at one of the **8 apply sites** (§9), which are
inside that same stage for the same reason.

Two more things to know before hooking here. **The HUD producer never runs in
Practice mode** — hook it and your code is dead in the mode people train in. And
**attacks are not processed on an action's step 0**, so the engine's effective
timing is one frame later than the action's start.

A drawn version of everything above, generated from the same disassembly:
<https://definitelyfrenchname.github.io/SMS-FrenchName-edition/frame.html> (`tools/mkenginepage.py`).

### C. Building a menu screen

```
screen entry
  ├─ (often) a full VRAM clear: fixed-source DMA, len $0000 = 65536, $80:8191
  └─ the screen's own cluster: straight-line code, per record:
        lda #idx*2 / sta $1C18 / jsr
             └─ $C3:BCCD (A, 25 entries) or $C3:BCFF (B, 49) ──► 10-byte record
                  ├─ $80:927D decompress  src24 ──► dest24 (WRAM staging)
                  └─ $80:92AD DMA         vram16, len16 ◄── the staging buffer
```

The bank-`$DF` screen engine (the win/report card and the tournament screens)
**bypasses this entirely**: nine straight-line scripts, its own asset entries, its
own DMA at `$DF:84C2`, and a second codec. Two systems, one front end — which is
why translating "the menus" was really translating two different machines.

### D. Making a sound

```
ROM bank id ──► 6-byte record at $C0:ECE7 ──► IPL blocks ──► ARAM
                                                  └─ $C0:EC5E adds DP $10 to every
                                                     destination — that one bias is
                                                     how P2's bank lands at $DB00
per frame: $C0:D4F5 sends three bytes
     P1 struct +0x78 ──► APU port 0
     P2 struct +0x78 ──► APU port 1   (with ora #$80 — a +4 directory shift)
     DP $78 (global)  ──► APU port 2
sound id ──► directory entry ($34C0 + (charID-1)*32) ──► BRR sample
         └─ the sequence header's byte at seq+3 is the TRANSPOSE: one semitone per unit
```

---

## 11. Where there is room

Any change that needs more than a few bytes has to go somewhere. The inventory,
measured:

| Space | Size | Notes |
|---|---|---|
| **Appended banks `$E8+`** | unlimited-ish | The vanilla image ends at `$E7` and the header declares a 4 MB ceiling, so appending banks is free and legal. This is where every non-trivial patch puts its code |
| ROM hole `$C1:BE09-BE47` | **63 bytes** | The classic "free code hole". Patches 1 and 2 live here (`$BE20`, `$BE2A`) |
| ROM hole `$C1:BE85-BEC9` | **69 bytes** | Patch 6 lives here |
| WRAM `$0816-$09FF` | 490 bytes | **VS matches only** — native Practice uses the whole range. Patch 10's state |
| WRAM `$7F:6000-$DBFF` | ~31 KB | Untouched in steady-state play. Patches 11/13/14/100 keep state here, reached with long addressing or the `$2180-83` WMDATA port the game never uses |
| VRAM BG3 CHR `0xC7-0xDF` | 25 tiles | Free in every matchup; where patches 10 and 11 upload their fonts |
| VRAM menu tiles `$5C0-$5FF` | 64 tiles | Free on every menu screen, overwritten at match load. Patch 16's half-width alphabet |
| VRAM menu tiles `$738-$7BF` | 136 tiles | Free in every capture; unused so far |
| CGRAM OBJ row 7 | 16 colours | Never loaded, never drawn — the Saturn port's projectile palette |
| ROM hole `$E4:D297` | **9,334 bytes** | The **largest zero region in the image**, by a factor of 24, and in no project doc until now. Unclaimed: by this project's own discipline it needs a read-watch before anyone builds on it |
| **ARAM** | **~0** | The largest zero run in the APU's 64 KB is 64 bytes. Audio is the one hard wall; adding a voice means displacing one |

⚠ Two rules this project learned the expensive way, both about "free":

* **Unreferenced and unchanging is not free.** A 7 KB ARAM region passed both
  tests and was still live — proven only by finding its bytes in ROM bank `$E4`.
  On this console everything was uploaded from somewhere; ask where it came from.
* **A write-watch cannot prove a region is free**, because DMA does not surface
  as a CPU write. Snapshot as well, and cross-check the two.

---

## 12. Reading this yourself

Three habits make the difference between reading these structures and guessing
at them:

1. **Find the interpreter before trusting the data.** A run of zeros after a
   string looks exactly like a terminator; in the stage-name records it was
   centring padding, and reading it as a terminator produced a build that hung
   the game one second after stage select. Two records side by side would have
   shown it immediately.
2. **Verify the instrument against a known-present signal.** Three separate
   probes in this project reported "the game never does this" while hooked to
   the wrong bank, filtering on a write-only register, or dead on a thrown error.
   A 16,544-write signal was there the whole time. Prove the harness sees
   something before you conclude the game does nothing.
3. **Count the sites in the image you ship, not the clean ROM.** "There are
   exactly two reads of this table" was true of the vanilla ROM and false of the
   build, which carries a full copy of bank `$C1` — and the difference was a
   corruption bug that survived four sessions.

---

---

## 13. The holes — what is genuinely not known

A map that hides its gaps is worse than no map. These are the parts of the
cartridge this project cannot yet read, listed so nobody re-derives the same
dead ends:

| What | Where | State |
|---|---|---|
| **Codec 2** | `$80:8E9A` | **Not decoded.** Everything known fits in a sentence: tile-unit, XOR row filters, a 2-bit command stream. No implementation exists. It carries the report-card tilemap, the bracket VS-names blob and the win-card portraits, and it is the reason patch 16's last two screens are blocked. The shipped workaround is to edit its output in WRAM, between decompress and upload |
| **Story dialogue's text path** | unmeasured | The variable-text engine (blitter `$80:9583`) is itself decoded — font `$C2:4580` staged at `$7F:C000`, computed glyph address at `$C2:B9CD`, `$FC`/`$FF`/`$00` syntax, strings behind pointer tables — see `menu_system.md` §4. What has *not* been checked is whether story dialogue uses it. ⚠ It substitutes no names: the A.C.S. prompt is nine pre-written strings |
| ~180 KB of graphics | `$DC:3D80` – `$DE:FFFF` | After the last fighter cel. Almost certainly object/effect/hitspark cels, but the cel pointer table is roster-only, so object cels resolve through some other path |
| 21.5 KB of sparse data | `$C0:2800-7FFF` | A strict `0x80`-byte texture; rendered and checked — not CHR, not code. The tail of bank `$C1` has the identical texture. Same producer, unidentified format |
| Bank `$E3` | most of it | Data, 87% `00`/`FF`, and no pointer into it has been found |
| A second BRR directory | `$E4:F70D` | A byte-identical restart of character 1's record. Purpose unknown |
| One `$DF` screen script | `$DF:9B27` | Which screen it draws is unidentified |
| ~a third of the object struct | `+0x19-0x1F`, `+0x2B-0x2F`, `+0x3B-0x3F`, `+0x57-0x5A`, `+0x69-0x6F`, `+0x7B-0x7F` | Unmapped. ⚠ **`+0x79/+0x7A` was in this list and is not unmapped**: it is a 16-bit per-object hit counter capped at 999, written at every hit-resolution fork and both throw sites and re-initialised at round load (sites in `annotations.md`). Measured 2026-08-24 by a decoded write census plus a full-session watch, after a build had already parked a timer there — which is what "unmapped" invites |
| WRAM | `$0100-$01F9`, `$0420-$07FF`, `$0C00-$0FFF`, most of `$1200-$1FFF` | Unmapped, including the object pool's slots 4-15 — nothing in the project names a user for them |

Two smaller ones worth recording because they look like answers and are not: the
seven orphan bytes at `$C3:BD93` sit inside the asset-record pool and are
referenced by nothing, and the `$E4` zero hole above is *inferred from bytes
alone* — this project has been wrong about exactly that kind of evidence before.
