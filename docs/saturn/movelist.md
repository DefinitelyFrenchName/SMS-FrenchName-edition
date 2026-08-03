# Saturn's movelist (task #41) — DONE [P 08-03]

**Status: SHIPPED in v0.13.2**, verified in-emulator on two shells with the
vanilla path unchanged. She has her own list: SAILOR SATURN, サイレンス バスター
(236+P), プレス クラッシャー (JUMP中 632+K), デス リボン レボリューション
(214+P). Not yet seen by the maintainer in normal play. Everything about how SMS
picks and draws a character's movelist is now known and measured, including the
exact per-player hook to use. What is NOT solved is producing HER data — and the
approach the maintainer preferred (lift it from Super S) is ruled out, for a
reason worth recording.

## How SMS draws a movelist

The list lives on **BG3**, invisible in Practice because TM = 0x13; **Start**
flips it on (`$01FA` 0x80 → 0xE4). It is staged during the **match load**, not
at the Start press — an earlier note said Start "restages the entire layer on
every press", which is true of the layer but does not go through the asset path:
a Start press produces no asset load and no DMA at all (measured).

The per-character data is a **compressed asset selected by charID**:

```
$E0:021A + charID*3     nine 3-byte pointers into bank $E2 (the movelist table)
    1 Moon    $E2:6F40      6 Uranus  $E2:7790
    2 Mercury $E2:70D0      7 Neptune $E2:78E0
    3 Mars    $E2:7270      8 Pluto   $E2:7A20
    4 Jupiter $E2:7410      9 Chibi   $E2:7B60
    5 Venus   $E2:7610
```

each ~320-400 bytes, expanded by **`$C0:916B`** into the staging buffer
`$7F:0000` and DMA'd (0x800 bytes) to VRAM by `$C0:9287`. Both players are
staged, to different tilemaps:

```
$C0:8B44   lda $1000 / and #$00FF / *3 -> X
$C0:8B53   lda $E0021A,X -> $00        <- P1's movelist pointer
$C0:8B59   lda $E0021C,X -> $02
           $03 = $1000 (VRAM dest) ; jsr $916B
$C0:8B6E   lda $1080 ... same, X from P2's charID
$C0:8B7B   lda $E0021A,X -> $00        <- P2's movelist pointer
           $03 = $1400 ; jsr $916B
```

**That is an ideal hook.** The two reads are 4 bytes each (`lda long,X` = a
JSL-sized instruction), and each sits in a block that took the charID from
*that player's own struct* — so a Saturn override is per player with no shell
dependency, exactly the shape that worked for the voice. Hook the SECOND read of
each pair (`$C0:8B59` / `$C0:8B81`) and a stub can set both `$00` and `$02`.

**There is no free tenth table row**: entry 10 would start at `$E0:0238`, which
is the manifest pointer table. Her pointer has to come from the hook, not a row.

Layout facts for authoring: the font is **8x16** — every text line occupies two
tile rows, the lower being the upper + 0x10 — and the entry count is **variable**
(Moon has 3 moves, Uranus 2), so a longer list is not itself a problem.

## Why it cannot be lifted from Super S

The two games share every graphics *structure* looked at so far, but **not this
code**. Super S contains neither `$C0:916B`'s routine (searched by its opening
32 bytes) nor the movelist loader's distinctive shape (`lda #$1000 / sta $03 /
lda #$1001 / sta $05 / jsr`). The existing LZSS decoder (`supers_lz.py`, the
`$C0:EE30` codec) also cannot decode these blobs — `$C0:916B` is the *other*
codec, a mode-dispatched one with a table at `$C0:914D`.

So her list has to be produced in SMS's own format. This is the first Saturn
asset where the two games genuinely diverge, and it is worth noting because the
project's working assumption — "graphics structures match every time" — has held
until now and quietly shaped the plan for this task.

## The codec — SOLVED [P 08-03]

`tools/saturn/sms_lz.py` decodes and encodes it. **All nine vanilla movelists
decode to exactly 0x800 bytes, and both encoders round-trip**, so path 1 is open:
her list can be real data like everyone else's, and the VRAM-blit fallback is not
needed.

Format, hand-decoded from `$C0:919F` and confirmed byte-exact against a live
staging dump:

* a **16-bit control word, LSB first**, refilled as consumed;
* **bit 1 = LITERAL** — copy one byte from the stream;
* **bit 0 = BACK-REFERENCE**, whose form the next control bit picks:
  * **0 = short**: two more control bits give L, count = L + 2; then one stream
    byte D gives distance = D - 256 (-256..-1);
  * **1 = long**: a 16-bit word `w`; count = `(hi & 7) + 2`, distance =
    `(0xE0 | (hi >> 3)) << 8 | lo` as signed 16-bit (-8192..-1). When
    `hi & 7 == 0` an extra byte `n` follows: **0 ends the stream**, 1 is a no-op,
    otherwise count = n + 1;
* copies are byte-at-a-time and overlap-safe, so a distance of -2 is the RLE that
  fills a mostly-blank tilemap.

**The one trap, and it cost the most time here.** The refill happens *inside* the
bit fetch: the ROM does `lsr / dey / bne`, so when the 16th bit is extracted the
next control word is read **before that bit is acted on**. The two refill bytes
therefore land in the stream AHEAD of the payload the 16th bit selects. A decoder
that refills lazily on the next fetch reads the control word as a literal and
desynchronises — which is exactly what happened, and it decoded 0x14F bytes
perfectly first, which made it look like a data problem rather than an ordering
one. The encoder has to simulate the same timing, so `_emit` walks the ops and
splices each control word in at the moment a word empties.

Two encoders are provided:

| | Moon | Uranus | vs vanilla |
|---|---|---|---|
| `encode_literal` (every byte a literal) | 2309 | 2309 | ~7x |
| `encode` (literals + distance -2 RLE) | 581 | 404 | vanilla 400/336 |

Even the naive one is fine — appended banks are free and the DMA length comes
from how much was written, not from the stream size — but the RLE version lands
close enough to vanilla to be tidy.

## The font, and how her list is built

The BG3 CHR base is **word `$5000` = byte `$A000`** (read from the PPU, after
inferring it from tile codes gave contradictory answers — `$210C` is the
authority, not arithmetic). With that, the tables read straight off a rendered
sheet (`tools/saturn/render_chr.py`):

* **roman caps** — a REDUCED alphabet: `$090`-`$099` = A-J, `$09A`-`$09E` = L-P,
  `$09F` = R, `$0B0`-`$0B4` = S-W, `$0B5` = Y, `$0B6` = `!`. There is no K, Q, X
  or Z, which is why the letter codes look irregular. SATURN needs S A T U R N —
  all present.
* **katakana** — gojuon-ordered, `code = $100 + (i//16)*$20 + (i%16)`, confirmed
  against vanilla text (ワ=`$14B`, ル=`$148`, キ=`$106`, シ=`$10B`).
* **dakuten/handakuten** — a reduced set at `$14E`,`$14F`,`$160`-`$16C`:
  ガ グ ゴ ジ ズ ダ デ ド バ ビ ブ ボ パ ピ プ.
* **small kana** — ィ ェ ャ ュ ョ ッ ー at `$180`-`$186`.
* **input icons**, 2 tiles wide: ⬇ `$1A4`, ↘ `$1A6`, ➡ `$1A8`, ✚ `$1AA`,
  中 `$1A0`, JUMP `$1AC`+`$1AE`, Ⓟ `$1C4` / Ⓟ小 `$1C2`, Ⓚ `$1C6` / Ⓚ小 `$1C0`,
  "or" `$1CA`. **There are no left or up arrows** — ⬅ ↙ ⬆ are the same glyphs
  flipped, and flipping a 2-tile glyph also SWAPS ITS HALVES (vanilla writes
  `1A7|H 1A6|H` for ↙).

`tools/saturn/mkmovelist.py` builds her 0x800 tilemap from a text spec, starting
from **Moon's** list because she is the only vanilla character with three moves,
so the frame and row positions already fit. Only the text rows are rewritten —
the 右向きの時 line is left exactly as it is, being identical for all nine.

**The one non-obvious byte: priority.** Body text is attribute `$2D`, not `$0D`.
`$2105` has the mode-1 BG3-priority bit set, so a BG3 tile *without* priority
renders behind the stage. Building with `$0D` produced a movelist whose title
appeared and whose body was invisible — and it only showed up on a bright stage,
which is exactly the kind of thing that ships.

## Wiring

Her compressed list (595 bytes) sits in the voice bank at `$F9:3400`, and the
two table reads are replaced by JSLs to stubs that substitute her pointer when
that player's Saturn flag or latch is set:

    $C0:8B59  lda $E0021C,X  ->  jsl $F9:3700   (P1)
    $C0:8B81  lda $E0021C,X  ->  jsl $F9:3740   (P2)

The stub sets `$00` to her pointer and returns her bank in A, which is exactly
what the instruction it replaced fed the caller; the non-Saturn path performs the
original `lda` and returns.

## Acceptance

| case | result |
|---|---|
| Saturn over the **Uranus** shell | expands from `$F9:3400`; staged tilemap byte-identical to the authored one |
| Saturn over the **Moon** shell | identical — the shell is irrelevant |
| nobody armed | the vanilla `$E2:7790` list, unchanged |
| in-game screenshot | `traces/saturn/movelist_satml2.png` — all three moves render |
| regression / smoke / voice / select-voice | ALL PASS (57) / 228+228 / 8+8 / 4+4 |

## Her content — SUPPLIED by the maintainer [P 08-03]

From the Super S capture (`traces/saturn/supers_movelist_saturn.png`) plus his
transcription. Layout matches SMS's exactly: a title line, then three moves, each
a katakana name with its input notation on the line below.

Title line — `SAILOR SATURN` in roman caps, left; `右向きの時` ("when facing
right") in kanji, right. **That right-hand line is identical in all nine vanilla
lists**, so it is lifted from any of them rather than authored.

| # | Name (katakana) | Input | Engine act (measured, v0.13.0) |
|---|---|---|---|
| 1 | サイレンス バスター (SAIRENSU BASUTAA) | 236 + P | `$6E` -> `$70`, CMD arg `0x23` |
| 2 | プレス クラッシャー (PURESU KURASSHAA) | JUMP中 632 + K | air special |
| 3 | デス リボン レボリューション (DESU RIBON REBORYUUSHON) | 214 + HP or LP | `$6A` -> `$6C`, CMD arg `0x24` |

Notation should follow the vanilla convention: motion numbers as arrow glyphs,
and P/K as the large and small Ⓟ/Ⓚ icons.

> Move 3's input was first transcribed as "HP or LK"; the maintainer confirmed
> (2026-08-03) it is **HP or LP**, which matches the engine — its CMD arg maps to
> the sample identified as "214P" and its acts sit in the same P-starter group as
> the 236.

**Feasibility of the content is settled**: every glyph class she needs is already
drawn by the vanilla lists — roman caps and the `右向きの時` line in all nine,
katakana throughout, arrows and Ⓟ/Ⓚ icons throughout, and **`JUMP中` in Moon's**
(which also proves the roman `JUMP` and the kanji `中` are both in the font).
Three entries is also within the vanilla range: Moon already has three.

## The tilemap format (decoded)

Authoring her list means emitting this, so it is worth having exactly:

* the map is the standard 32-entry-wide SNES BG tilemap at VRAM byte `$2000`
  (word `$1000`), 0x800 bytes, DMA'd whole;
* each entry is a normal tilemap word — bits 0-9 tile, 10-12 palette, 13
  priority, 14-15 flips — stored little-endian;
* text is **8x16**: every line occupies two tile rows, and the lower row's tile
  is always the upper row's **+ 0x10**;
* the title name uses **palette 5** with priority set (attribute byte `$34`),
  the move text and the input icons use **palette 3** (attribute byte `$0D`);
* input-notation glyphs are two tiles wide each (e.g. Uranus's first input row
  runs `$1A8 $1A9 $1A6 $1A7 $1A4 $1A5 …`).

Worked example, Uranus's title row at map offset `$140`:

    b0 34  90 34  98 34  9a 34  9d 34  9f 34  b2 34  9f 34  90 34  9c 34  b2 34  b0 34
    S      A      I      L      O      R      U      R      A      N      U      S

**Still missing: the code -> glyph table.** The font's CHR window has not been
pinned down — inferring it from the tile codes and the VRAM dump gave
inconsistent answers (the letters resolve cleanly at one base, the `$1xx`
katakana codes do not, which means the base assumption is wrong rather than the
codes). The reliable way is to read the BG3 CHR base out of the emulator's PPU
state while the list is on screen, then render the sheet from there and read the
glyphs off it. `tools/saturn/render_chr.py` does the rendering already.

## Probes

`probe_sms_movelist.lua` (asset loads + `$01FA` + VRAM/WRAM dumps),
`probe_sms_mlwriter.lua` (the DMA helper's real source, the staging buffer, and
the expand calls — this is the one that found the table).
