# The menu, font and text system

**What this is.** How *Bishoujo Senshi Sailor Moon S* draws every screen outside a
match: the glyph format, the two font sheets, the asset pipeline that uploads
them, the two independent screen engines, and the runtime writers that lay text
over the top. Knowledge of the retail ROM — nothing here is about any patch.

Companion to [`sms_data_architecture.md`](sms_data_architecture.md), which covers
the asset-record format and the codecs as part of the whole-cartridge picture;
this file is the front end in depth. The blow-by-blow discovery record, with the
dead ends and the decisions that came out of them, is this project's own
[`../project/menu_text.md`](../project/menu_text.md).

---

## 1. A glyph is four tiles

Menu text is **16×16 glyphs, each a 2×2 block of 8×8 tiles**, in a sheet that is
**16 tiles wide**. For a glyph whose code is `T`:

```
        T      T+1          codes step by 2 along a row
      T+$10   T+$11         glyph rows are $20 tiles apart
```

So odd tile-rows hold only the bottom halves of the row above. A **half-width**
glyph is one tile wide and two tall — `(t, t+$10)` — and costs one map column
where a full-width glyph costs two.

Text lives in an ordinary **tilemap**, so a cell is the standard SNES word
(`flip<<14 | prio<<13 | palette<<10 | tile`) and one string can be recoloured
without touching its glyphs. That repetition is also how we know it is a shared
font rather than baked art: `パンチ` is the same three glyph codes inside both
`弱パンチ` and `強パンチ`.

⚠ **Two alignment facts.** Glyph rows start at map **row 1**, not row 0 (row 0
holds bottom halves), and a screen may **mix alignments** — full-width text sits
on the even column grid while button labels sit one tile left. A fixed
even-column read shows the labels' right halves as unmapped codes.

## 2. The two font sheets, and where they land

| Block | ROM | Size | Loads at VRAM tile |
|---|---|---|---|
| kana + general (Latin, digits, symbols) | `$C3:48D0` | 608 tiles | base **`+$0A0`** on most screens |
| kanji | `$C7:07F0` | 182 tiles | **`$500`** (`$500-$5B5`) |
| the menu font sheet | `$C4:2590` | 418 tiles | `$400`, staged through `$7E:C000` |

⚠ **A glyph's code is not a fixed address.** The kana block does not load at a
constant base: Latin `A` is block tile `$16A`, which appears at VRAM `$20A` on
screens that load the block at `$0A0` — and the VS button-config screen loads the
same block at `$2A0`, where `$20A` is unrelated artwork. Chasing a screen-observed
code across captures finds gradients and katakana in turn. Read the code→glyph
table (`tools/menufont_table.py`) rather than re-deriving from a capture.

**Addressing rule for tilemap work:** BG1's CHR base is word `$2000` = tile
`$200`, so **map tile = VRAM tile − `$200`**, and a glyph occupies two map rows
with `bottom = top + $10`.

### What the font actually contains

* A full katakana set with dakuten/handakuten and small kana.
* A small, purpose-built kanji set — exactly what the game's own strings need
  (`十番川神王州水海商店社編公園必殺街噴集部時空扉火数残`).
* **Latin capitals, 22 of 26 — missing J, Q, S, Z.** (`F` exists, in the digit
  style, which an early survey missed.) A second style at `$264-$26E` holds
  A B X Y L R: those are *button* labels, not an alphabet.
* Digits in two styles, and a few symbols (`◆ ▶ ー`) plus `メ タ 夜 昼 強 弱 勝 あ`.

**There is no reusable half-width Latin.** The `PRESS "SELECT" TO ACS` banner
looks like one and is not: its 22 slots hold **22 distinct glyphs with zero
duplicates**, for a string that repeats S four times, and its ink forms
word-shaped runs that cross tile boundaries at every offset. It is proportional
artwork that happens to be stored as tiles. Nothing can be lifted from it.

*(A real tile-aligned half-width font does exist in the Big Zam **Tournament
Edition** ROM — 8×16, 7 px ink, 12 px cap height, three shades over a filled
cell. Measured against the vanilla banner by ink IoU it is a different design,
not a re-grid of it. Extracted glyphs: [`te_halfwidth.json`](te_halfwidth.json).)*

## 3. How a screen gets built

Two independent engines. Which one a screen uses decides everything about how you
edit it.

### Engine A — the `$C3` clusters (most screens)

A screen's loader is straight-line code: per asset, `lda #index*2 / sta $1C18 /
jsr`. The index selects a 10-byte job record — `[vram16][len16][src24][dest24]`,
described in the architecture doc — through one of two pointer tables
(`$C3:BCCD`, 25 entries, all `0x800` tilemaps; `$C3:BCFF`, 49 entries, CHR and
big sheets). `$C3:82CA` then decompresses the source into WRAM and DMAs it to
VRAM.

| Screen | Loader |
|---|---|
| main menu | cluster `$C3:B76B` |
| Options | cluster `$C3:A4DD` |
| vs-COM setup | cluster `$C3:B852` |
| character select | cluster `$C3:AF8A` |
| VS button-config | *no cluster of its own* — keeps char-select's VRAM plus its own compressed tilemap `$C3:7C00` |
| A.C.S. | cluster `$C3:9CF2`, plus its own small font at `$4000` |
| post-match winner | cluster `$C3:99DB`, reached from `$C3:97E1`. Keyed on `$1B10`, which this screen loads with the **winner's** charID (`$1E14` = match_winner). Loads the same nine per-character portrait+name blobs the A.C.S. screen does, but to VRAM word `$3000`; its BG1 map is `$C6:3A50`. ⚠ No probe route reaches it |

### Engine B — the bank-`$DF` screen engine (win/report card, tournament)

Bypasses the job table, the `$C3` clusters and the shared uploader entirely.
**Eight** screens, each a straight-line caller (`lda #script / jsr $DF:83E1`),
executing from the `$9F` mirror so 16-bit destinations land in WRAM. A script has
three phases:

```
[u8 n][asset entries]    flag != 0 : [src24][flag][vmadd16][len16]  codec 1 -> $7F:0000 -> DMA
                         flag == 0 : [src24][flag][dest24]          codec 2 -> WRAM, no DMA
[u8 n][small copies]     [src24][dest16][n]   n = 32-byte units (palettes)
[u8 n][descriptors]      7 bytes -> entity structs $7E:1000 + k*$80
```

The flag byte is the codec discriminator, at `$80:8DEC`. **Codec 1 is fully
decoded and re-encodable; codec 2 is not decoded at all** — see the architecture
doc §9. That single fact decides the edit strategy for any `$DF` screen: work on
the *decompressed* form, with a stub between decompress and upload.

## 4. Text drawn at runtime, over the top

Three mechanisms put variable text on a screen after its tilemap is up. A
tilemap-only edit of something drawn by any of them gets overwritten.

**Self-describing tilemap records**, drawn by `$80:8C43` one DMA per row and
selected by pointer tables per value *per highlight state*. They are
uncompressed, in bank `$C4`, and they are the single source for both the initial
draw and every redraw — which is why a tilemap-only edit of a *value* does not
stick. This carries the Options values, the VS config's MANUAL/AUTO and the
tournament name rows. Byte layout: `sms_data_architecture.md` §9.

The Options screen's selectors read theirs from four overlapping windows onto one
12-word array at **`$C3:A44F`** — `$C3:A44F` (COM level), `$C3:A457`, `$C3:A45B`
and `$C3:A463`, indexed by `$1B14`/`$1B16` = value × 2. Twelve records, two per
value per highlight state, each `len $14` over `rows 2`.

**Stage names** — `ldx $1838` indexes two 10-entry tables, `$C3:B5AD` (palette 3)
and `$C3:B5C1` (palette 4), into fixed-size records in bank `$C4`: a header, then
a 24-word top row and a 24-word bottom row that is the top plus `$10`. Layout and
a decoded example: `sms_data_architecture.md` §9. Two consequences belong here,
though, because they bite at the screen level — a name is **12 full-width glyphs
maximum** whatever the row's free space suggests, and:

⚠ **There is no terminator.** The name is *centred* by leading and trailing zero
words, and a run of zeros after a string is not evidence of one. Reading it as
terminated — start at the first glyph, stop at `0000` — writes a longer name
straight through the bottom row into the next record's header; that build
corrupted the screen and hung the game a second after stage select.

**A dynamic glyph blitter** — `$80:9583`, queue-driven (`$1C80` src, `$1C82`
bank, `$1C8E` vmadd, dispatch `$1C90`), uploading single glyphs `$20` bytes at a
time into BG3 CHR with map cells pointing at them. **This is the game's
variable-text engine**, and it is now decoded: the font is `$C2:4580`, codec 1,
staged as 512 units of `$20` at **`$7F:C000`** by asset record `$C3:BE30`
(`00 58 00 10 80 45 c2 00 c0 7f` = vram `$5800`, len `$1000`, src `$C2:4580`,
dest `$7F:C000`) — which is why a per-byte write watch never saw it arrive, and
why `$7F:DC00+` looked like an unfound staging area: `$DC00` is simply
`$C000 + $1C00`, inside that buffer, in the blank high-code region. A unit is a
**16×8 strip** (two 8×8 tiles side by side). `$FC` terminates, `$FF` is a
newline, `$00` is a space. The glyph address is *computed*, not stored:
`$7F:C000 + rowtab[(code & $F8) >> 2] + (code & 7) * $20`. ⚠ The two addresses
for that arithmetic (routine `$C2:B9CD`, rowtab `$C2:BA2D`) are **inherited from
the 2026-08-11 prompt work and were not re-derived here** — `$C2:B9CD` does not
decode to a plausible entry under a fresh 8-bit framing, so treat them as filed,
not measured, until someone reads them with the flags the caller actually sets.

⚠ **There is no runtime name substitution.** The A.C.S. prompt is nine
pre-written strings behind a 4-byte pointer table at `$C2:C1CA`, and the name
card beside it is not this engine at all — it is per-character baked art (see
`../project/menu_text.md` § "The A.C.S. name card"). Story dialogue has not been
checked against this engine.

## 5. VRAM on a menu screen

```
tile $0200   ← BG1 CHR base, so MAP tile = VRAM tile − $200
     $0400   the menu font sheet ($C4:2590, 418 tiles, via $7E:C000)
     $05B6   ─ ends here
     $05C0   FREE — 64 tiles = 32 half-width glyphs
     $0600   screen art
     $0738   FREE — 136 tiles
```

`$5C0-$5FF` is free on **every** menu screen and **first used at match load**
(1416 of 2048 bytes go non-zero) — safe for menu text, unsafe for anything that
must survive into gameplay.

⚠ Three laws this system enforces, each paid for:

1. **A screen transition can clear all 64 KB of VRAM** — a fixed-source DMA with
   `len $0000` = 65536 at `$80:8191` — after which the destination screen reloads
   only its own asset list. "It was in VRAM a moment ago" proves nothing.
2. **Blank ≠ unreferenced.** A screen can reference blank tiles through another
   BG's CHR base; three separate screens do. Uploading glyphs into a window that
   *looks* free can therefore corrupt a bar of text elsewhere on that screen.
3. **DMA never surfaces as a CPU write callback.** A write-watch on a VRAM range
   saw zero writes across a whole match while snapshots caught 1416 bytes
   arriving. Any freedom claim needs both instruments.

## 6. Cell budgets (VS button-config, `$C3:7C00`)

What the vanilla strings occupy, and what they can grow to without moving
anything else. One cell = one full-width glyph = two half-width.

| String | row | cells | max |
|---|---|---|---|
| `1P` / `2P` | 3 | 2 | 6 / 18 |
| `マニュアル` (×2) | 5 | 5 | 6 / 7 |
| `モード` | 5 | 3 | 5 |
| `弱パンチ` / `強パンチ` | 7 / 9 | 4 | 9 |
| `弱キック` / `強キック` | 11 / 13 | 4 | 9 |
| `弱必殺モード` / `強必殺モード` | 15 / 17 | 6 | 9 |
| `ステージ` | 21 | 4 | 16 |
| stage name | 23 | 12 | 16 |

Stage-name records are 24 words = **12 full-width glyphs maximum**, whatever the
row's free space suggests.

## 7. Tools that speak this system

| Tool | Does |
|---|---|
| `tools/menufont.py` | `sheet` / `blanks` / `decode-map` — renders the sheet, counts free slots, and **decodes a screen's tilemap back into readable strings with their cell budgets** |
| `tools/menufont_table.py` | the validated code → glyph table |
| `tools/saturn/sms_lz.py` | codec 1, decode **and** encode |
| `tools/te_halfwidth.py` | extracts the Tournament Edition's half-width font |
| `tools/probe_menu_survey.lua` | walks the front end capturing screenshots, all four tilemaps and all of VRAM per screen |
| `tools/probe_menu_vram.lua` | dumps a VRAM range **on the font transfer** — not at the end of a run, when a later upload has already overwritten it |
| `tools/probe_p16_screens.lua` | drives the win / A.C.S. / tournament screens and logs each one's loader and uploads |

⚠ `decode-map` is the fastest way to read a screen: it prints every string with
row, column and budget, and that output is its own validation — those are the
strings the game shows.

⚠ **Our codec-1 encoder is weaker than the original's**: even an untouched block
re-encodes larger (the kanji block, `0xD5B` original, comes back `0x13AD`). An
edited block must be **relocated** and its record repointed, never written back
in place — *unless the re-encoded stream is measured to fit*. `sms_lz.encode_lz`
(the optimal parse added for Saturn's round-won badge) does beat the vanilla
stream on some blocks, and two have now shipped in place: the A.C.S. text font
(6470 B into 6736) and all nine A.C.S. name-card blobs (tightest fit 58 bytes
spare). The rule is therefore **relocate unless the builder asserts the fit at
build time**; `decompress_ex` returns the vanilla stream's length for exactly
that assert. Never write back on the assumption that it fits.
