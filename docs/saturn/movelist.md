# Saturn's movelist (task #41) — mechanism fully mapped [P 08-03]

**Status: RE complete, implementation not started.** Everything about how SMS
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

## Two ways forward

1. **Decode `$C0:916B` enough to EMIT a stream.** The blobs are visibly
   part-literal (the tilemap words are readable in the clear: Uranus's begins
   `… b0 34 90 34 98 34 9a 34 9d …` = "SAILOR…"), so this is an LZ-family codec
   with a literal path. If it has a raw/all-literal mode, authoring her list
   needs no compressor at all — just the tilemap and the 8-byte pointer hook.
   This is the clean outcome: her list becomes real data like everyone else's.
2. **Blit over VRAM after the vanilla expand** — the fallback the card portrait
   took when her art could not be re-encoded. No codec work; costs a hook that
   runs when the list is staged (and possibly re-runs, since Start restages the
   layer) plus up to 0x800 bytes of tilemap.

Path 1 should be tried first and is likely cheap; path 2 is the guaranteed
fallback.

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
| 3 | デス リボン レボリューション (DESU RIBON REBORYUUSHON) | 214 + P | `$6A` -> `$6C`, CMD arg `0x24` |

Notation should follow the vanilla convention: motion numbers as arrow glyphs,
and P/K as the large and small Ⓟ/Ⓚ icons.

> **One point to confirm.** The transcription gives move 3 as "214 + HP or LK".
> Everything else says P: her 214 special is the one whose CMD arg maps to the
> sample the maintainer identified as "214P", and the engine acts for it sit in
> the same P-starter group as the 236. Almost certainly "HP or LP"; worth one
> look at the capture before it is set in tiles.

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
