# Menu translation — groundwork

**Decision (maintainer, 2026-08-03): this is a STANDALONE PATCH, not a Saturn
feature.** It goes in the main patch line (next free number is **16**), builds
from clean like every other `mkpatchN.py`, and must be usable with or without
Saturn. The maintainer supplies the translations, including shorthand where a
string has to fit a fixed cell count — so what this document exists to give back
is the **budget per string** and the **cost of the glyphs a translation needs**.

Status: mechanism identified and one screen fully inventoried. The ROM storage
location is still open (see § Open).

## How menu text is drawn

Measured with `tools/probe_menu_survey.lua` (screenshot + all four BG tilemaps +
the whole of VRAM at each capture point, plus every decompressor call).

* Text is **16×16 glyphs**, each one a 2×2 block of 8×8 tiles. A glyph whose
  top-left tile is `T` occupies `T`, `T+1`, `T+0x10`, `T+0x11` — i.e. the CHR
  sheet is 16 tiles wide and a glyph row is `0x20` tiles. Glyph *n* of a row
  starts at `row*0x20 + n*2`.
* The text sits in an ordinary **tilemap** — on the button-config screen, BG1
  (`map $0000`, `chr $2000` word = byte `$4000`), with the background pattern on
  BG3. Palette is per-cell in the tilemap attribute, so one string can be
  recoloured without touching its glyphs.
* Repetition proves a shared font rather than baked art: `パンチ` is the same
  three glyph indices in both `弱パンチ` and `強パンチ`, and `モード` is the same
  three in `マニュアル…モード` and `必殺モード`.
* One exception on that screen: the `PRESS "SELECT" TO ACS` banner is a
  **pre-composed strip of half-width (8×16) letters** at tiles `$380-$38F` +
  `$3A0-$3A5`, laid out in reading order. Half-width letters therefore exist in
  the game and are worth reusing — they double the characters available in a
  given cell width.

**Consequence for translation:** editing a string = editing tile indices in a
tilemap. That is the same job as Saturn's movelist (`docs/saturn/movelist.md`),
for which the tooling already exists.

## The font is a REDUCED alphabet — this is the cost driver

Rendered from live VRAM (`tools/saturn/render_chr.py` for raw tiles; the 16×16
composer used for the reading below is in the probe's write-up).

* Kana: a full katakana set (plus dakuten/handakuten forms and small kana).
* Kanji: a small, purpose-built set — `十番川神王州水海商店社編公園必殺街噴集部時空扉火数残`
  — i.e. exactly the characters the game's own strings need (stage names like
  十番街 / 噴水公園 / 商店街, and 必殺 for the special-move row).
* **Latin capitals, 16×16 (`$20A` onward): A B C D E G H I K L M N O P R T U V W X Y.**
  **Missing: F, J, Q, S, Z.** A second style at `$264-$26E` holds A B X Y L R —
  those are the *button* labels, not an alphabet.
* Digits 0-9 in two styles; a few symbols (`◆ ▶ ー`), and `メ タ 夜 昼 強 弱 勝 あ`.

Missing **S** means almost no English sentence is writable from the existing
16×16 set, so a translation patch **must author glyphs**. That is a solved
problem here — the movelist patch already authors tilemaps from this game's own
font — but it means the patch owns a small CHR budget as well as tilemaps, and
the free slots in the sheet need counting before promising a full alphabet.

## Inventoried: the VS button-config screen

Cell counts are **glyph cells** (16×16). A string may grow into adjacent blank
cells on its row; the numbers below are what the vanilla string occupies, not a
hard ceiling — the ceiling needs the screen's layout checked case by case.

| String | Meaning | Cells | Note |
|---|---|---|---|
| `モード` | MODE | 3 | row header |
| `マニュアル` | MANUAL | 5 | the widest value on the screen |
| `オート` | AUTO | 3 | removed by patch 15; still drawn in vanilla |
| `弱パンチ` | light punch | 4 | |
| `強パンチ` | heavy punch | 4 | |
| `弱キック` | light kick | 4 | |
| `強キック` | heavy kick | 4 | |
| `必殺モード` | special mode | 5 | appears twice (one per player) |
| `1P` / `CP` | player labels | 2 each | full-width Latin + digit |
| `PRESS "SELECT" TO ACS` | | 22 half-width | pre-composed strip, `$380`+ |

Other screens seen but not yet inventoried: title, the intro cutscene, and
**`プレイヤーセレクト`** (player select, 9 cells).


## SOLVED (2026-08-04): the code -> glyph table, and screens are readable as text

`docs/saturn/movelist.md` recorded "Still missing: the code -> glyph table". It
exists now — `tools/menufont_table.py`, with `tools/menufont.py` to build and
check it. This closes Open items 1 and 3 below and corrects two facts.

**Glyph layout.** A menu glyph is 16x16 = 2x2 tiles in a **16-tile-wide sheet**:
top row `code, code+1`, bottom row `code+16, code+17`. Codes step by 2 along a
row; rows of glyphs are 0x20 apart. (The obvious guess — four consecutive tiles —
renders every cell as the TOP halves of two adjacent glyphs stacked, which is
exactly what the first contact sheet showed.)

**The two blocks land at different VRAM bases**, which is why block codes and the
codes seen on screen differ:

| block | ROM | VRAM base | check |
|---|---|---|---|
| kana / general | `$C3:48D0` (608 tiles) | `+$0A0` | Latin `A` = block `$16A` -> `$20A`, the code the survey saw |
| kanji | `$C7:07F0` (182 tiles) | `+$300` | blank run at block `$068` -> `$368`, the blanks the survey saw |

**The full-width alphabet is 22 of 26. Missing: `J`, `Q`, `S`, `Z` — and that is
the complete list**, verified by rendering every glyph in both blocks.

**Half-width Latin also exists**, but only as the pre-composed
`PRESS "SELECT" TO ACS` strip (kanji block `$080+`). Rendering it a tile at a
time shows the letters ARE individually addressable — 1 tile wide, 2 tall — so
**P R E S L C T O A** are available at 8x16. Two consequences: half-width text
would DOUBLE a label's character budget if the layout tolerates it, and the
half-width `S` is a faithful model for drawing the full-width one.

**CORRECTION — `F` is NOT missing.** It exists at kana block `$228` (VRAM `$2C8`)
in the DIGIT style, alongside `6 7 8 9`. The "Missing: F, J, Q, S, Z" below came
from a survey that never rendered the digit run. **Four letters have to be
authored, not five: J, Q, S, Z.**

**CORRECTION — free glyph slots.** Measured with `menufont.py blanks`: **1** in
the kana block (`$000`) and **9** in the kanji block (`$068-$06E`, `$0A6-$0AE`) =
**10 usable without relocating anything** — comfortably more than the four
letters needed. The survey's "sixteen at `$3C0-$3EE`" are *past the end* of the
kanji block: unwritten VRAM, not slots either block can fill. Using those needs
the block extended and relocated, which `mkkanji.py` already does.

**Screens decode to text.** `menufont.py decode-map` decompresses a screen
tilemap and prints every string with its row, column and **cell budget**:

```
$ python3 tools/menufont.py decode-map          # VS button-config, $C3:7C00
row  col  cells  text
  3    4      2  1P                 3   24      2  2P
  5    1      5  マニュアル          5   13      3  モード
  7   12      4  弱パンチ            9   12      4  強パンチ
 11   12      4  弱キック           13   12      4  強キック
 15   10      6  弱必殺モード       17   10      6  強必殺モード
 21   12      4  ステージ
 23    4     12  クリスタルトーキョー◆タ
```

That output IS the validation: those are the strings the game shows, so the table
is confirmed against reality rather than eyeballed. The `[A] [B] [X] [Y]` cells
are the button-label style, not letters.

**Two alignment facts, both paid for:** glyph rows start at map **row 1**, not 0
(row 0 holds bottom halves); and a screen **mixes alignments** — full-width text
sits on the even column grid while the button labels sit one tile left, so a
fixed even-column read shows their right halves as unmapped codes. The decoder
therefore scans columns singly and closes a run on a blank cell.

**Still needed from the maintainer:** the translations themselves. Everything
else for a first screen is now mechanical — the budgets above are the constraint
to write to, and the codec (`sms_lz.py`) already encodes as well as decodes.

## The asset table, and how many text screens there actually are (2026-08-04)

The compressed-asset job table is at **`$C3:BE02`** — 10-byte records,
`[src24][dest24][u16][u16]`, **59 of them**, listing every compressed asset with
its destination. (The earlier note said `$C3:BEE0`; that address lands mid-record.
The kana/kanji/tilemap sources all fall on the `$BE02` stride, which is what pins
it.) Walking the table beats brute-forcing a bank: it found **21 blocks that
decode to exactly 0x800** — a 32x32 tilemap, i.e. a screen — where a single-bank
scan had found six.

**But only ONE of the 21 is a text screen:** `$C3:7C00`, the VS button-config.
The other twenty are GRAPHICS tilemaps — their tile codes fall in the same range,
so decoding them through the font table yields plausible-looking kana that is
simply noise. Two exceptions are useful rather than noise: **`$C6:05C0` and
`$C6:7A40` are the font sheet laid out as a grid**, and `$C6:7A40` reproduces the
alphabet order exactly as transcribed (`ABC / DEGHIKLM / NOPRTUVW / XY...`) —
an independent confirmation of the table.

So `プレイヤーセレクト` and the title text are **not** in these compressed maps and
still need locating. That is the next piece of work on this patch.

## Translation budget — VS button-config screen (`$C3:7C00`)

`free L` = blank cells contiguous to the left; `free R` is 0 for every row
because UI border art sits immediately right of each label. `max` = what the
string can grow to without moving anything else.

| string | row | col | cells | free L | max |
|---|---|---|---|---|---|
| `1P` / `2P` | 3 | 4 / 24 | 2 | 4 / 16 | 6 / 18 |
| `マニュアル` (x2) | 5 | 1 / 21 | 5 | 1 / 2 | 6 / 7 |
| `モード` | 5 | 13 | 3 | 2 | 5 |
| `弱パンチ` | 7 | 12 | 4 | 5 | 9 |
| `強パンチ` | 9 | 12 | 4 | 5 | 9 |
| `弱キック` | 11 | 12 | 4 | 5 | 9 |
| `強キック` | 13 | 12 | 4 | 5 | 9 |
| `弱必殺モード` | 15 | 10 | 6 | 3 | 9 |
| `強必殺モード` | 17 | 10 | 6 | 3 | 9 |
| `ステージ` | 21 | 12 | 4 | 12 | 16 |
| stage name | 23 | 4 | 12 | 4 | 16 |

**One cell = one full-width 16x16 glyph = ONE Latin capital.** There is no
recombinable half-width Latin: the only half-width text in the font is the
pre-composed `PRESS "SELECT" TO ACS` strip, which cannot be taken apart. So an
English label is limited to its `max` in letters — e.g. MODE (4) fits 5,
MANUAL (6) fits 6, and the four button labels have 9 each.

⚠ **`S` is one of the four letters that must be authored** (with J, Q, Z), and
almost every English candidate here needs it — STAGE, PRESS, SPECIAL. Authoring
those four is therefore a prerequisite, not a nicety. There is room: 10 free
glyph slots, four needed.


## The maintainer's first translation set — checked (2026-08-04)

| target | fits? | needs authoring |
|---|---|---|
| `LP` `HP` `LK` `HK` | yes (9 cells each) | — |
| `L.SP` `H.SP` | yes (9 cells) | **`S` and `.`** |
| `1P` / `2P` | unchanged, no work | — |
| `MODE` (4, max 5) | yes | — |
| `MANUAL` (6, max 6) | yes, EXACTLY — no slack | — |
| `STAGE` (5, max 16) | yes | **`S`** |

**There is no period glyph in the font.** The only symbols are `◆ ▶ ー メ 夕`.
So `L.SP`/`H.SP` need TWO new glyphs, not one — `S` and `.`. Still comfortable:
10 free slots, and this set needs 2 (or 5 if J/Q/Z are authored at the same time).

⚠ **`MANUAL` may not stay put.** It is a *value*, not a label — vanilla toggles it
with `オート`, which patch 15 removes. The tilemap holds the INITIAL state only;
if the mode-row handler redraws the value at runtime it will overwrite a
tilemap-only edit. The handler is known (`$C3:A863/A87A/A880`, patch 15's edit
site) so this is checkable, but it must be checked before promising the string.

### The ten stage names

Decoded from the name table (`$C3:B5AD` -> records in bank `$C4`). Each record is
24 words = **12 glyphs max**, the name centred by zero padding — so an English
name has **12 full-width cells**, one letter each.

| # | Japanese | note |
|---|---|---|
| 0 | クリスタルトーキョー◆夕 | Crystal Tokyo, evening |
| 1 | シルバーミレニアム | Silver Millennium |
| 2 | 時空の扉 | the space-time door (the slot the Saturn stage port takes) |
| 3 | 海王州公園 | |
| 4 | 噴水公園◆昼 | fountain park, day |
| 5 | 十番商店街 | |
| 6 | 火川神社 | |
| 7 | クリスタルトーキョー◆夜 | Crystal Tokyo, night |
| 8 | 噴水公園◆夜 | fountain park, night |
| 9 | なかよし編集部 | |

Reading note: the day/evening/night marker after `◆` is `昼`/`夕`/`夜`. The
evening one renders almost identically to katakana `タ`, and the table maps that
code to `タ`; `夕` is the reading that makes sense against the `昼`/`夜` pair.

⚠ 12 cells is tight for these: "CRYSTAL TOKYO" is 13 with the space. Abbreviation
or a dropped space will be needed, and almost every candidate needs `S`.


## Open (items 1 and 3 CLOSED — see above)

1. **Where the text lives in ROM.** Neither the CHR nor the tilemap is stored
   raw (searched the clean ROM for both), and the front-end does **not** reach
   `$C0:916B` — the movelist/stage decompressor — on its way to these screens:
   hooking it across a whole boot-to-menu walk catches 8 loads, all of them the
   match load. So the menus use a different path, and finding it is the next
   step. Suggested probe: log VRAM DMA (`$420B` with the channel registers)
   during the config screen and work back to the source.
2. **Full screen inventory.** Needs scripted navigation per menu; the survey
   probe takes a `KEYS="down:260 a:300"` script for exactly that.
3. **Free CHR slots** in the font sheet, which bound how many new glyphs a
   translation can add without relocating anything.

## The tournament edition does NOT translate the menus

Checked, because it was the obvious place to borrow from. `SMS_BZE_TE.sfc`
differs from its Big Zam base in 7324 bytes: code at `$C0:1FEC-2051`,
`$C0:AA55/AA6C/AAF8-ABC5` (the character-select nav tables), `$C3` (the
button-config screen — the AUTO removal that patch 15 reproduces), and one
graphics run at `$C4:0001-1CA5`. Its player-select screen still reads
`プレイヤーセレクト` in-game. So there is nothing to lift; the translation is
authored from scratch.

## Tooling

`tools/probe_menu_survey.lua` — walks the front-end and writes, per capture
point, `traces/menu/<TAG>_<frame>.png`, `.map` (four tilemap windows + layer
bases + BG mode) and `.chr` (all 64 KB of VRAM), plus a log of every
decompressor call with its source and VRAM destination.

```bash
TAG=clean ROM=<rom> tools/run.sh tools/probe_menu_survey.lua 300
TAG=cfg EVERY=1200 UNTIL=1200 ROM=<rom> tools/run.sh tools/probe_menu_survey.lua 300
KEYS="down:260 a:300" ...        # scripted navigation to reach a specific menu
```

Gotcha paid for here: a **flat `tools/` script bootstraps `sms_env.lua` with
`/sms_env.lua`** — only `tools/saturn/` ones use `/../`. Getting it wrong makes
the script fail to load with no error and no output at all, which reads exactly
like the emulator ignoring it.

## The button-mapping screen is a COMPRESSED tilemap — and we own the codec

Found while chasing the stage name (2026-08-03), and it changes the shape of the
translation patch too.

* The screen is **not** drawn by CPU writes to `$2118` (none fire) and its text
  is **not** in ROM in any plain encoding — searched the captured glyph codes as
  words, low bytes, `tile>>1` and `tile-0x100`, all zero hits.
* It is **DMA'd in**, and the block is **compressed**: `$C3:7C00` decodes to
  exactly **0x800** bytes with `tools/saturn/sms_lz.py` — the same `$C0:916B`
  codec as the movelists, which that tool already **encodes** as well as decodes.
  (The apparent plain hit at `$C3:7CAB` was literal bytes showing through inside
  the compressed stream.)
* The decoded map is the screen: `PRESS "SELECT" TO ACS` at rows 1-2, the `1P` /
  `2P` headers, the six button rows, **`ステージ` at row 21** and a stage name at
  row 23.
* Only **six** blocks in bank `$C3` decode to 0x800, and just one is this screen
  — so there is a single template, and the per-stage name is written over row 23
  at runtime. That matches the DMA log: once the screen is up, the code issues a
  long run of **4-byte** transfers (two tilemap words = one glyph's top row,
  then its bottom row), sourced from bank `$83`.

So renaming a stage is the same class of job as Saturn's movelist, with the same
tooling. What is still missing is the **source of the per-stage name string** —
the bank-`$83` run the drawing code walks. That is the one thing to find next;
everything around it is now known.

Note the harness cannot reach this screen: it appears in **2P VS**, and the
probes' VS flow fades from character select straight into the match, while the
flow that does land on the screen is 1P-vs-COM, where the name is absent (its
row 21/23 are simply not drawn). The maintainer's captures are the evidence that
the name is there in 2P VS.

### Renaming a stage: what is known, and the one link still missing

* **Kanji CAN be authored.** The live menu font sheet has **20 completely blank
  16x16 glyph slots** — four immediately after the kanji block (`$368`-`$36E`)
  and sixteen at `$3C0`-`$3EE`. 沈黙のメシアの玉座 needs four new characters
  (沈, 黙, 玉, 座 — の, メ, シ, ア already exist), so it fits with room to spare.
  Kanji is therefore the maintainer's first choice AND the affordable one.
* **The static template** is the compressed block at `$C3:7C00` (0x800 bytes,
  `sms_lz.py` round-trips it), carrying `ステージ` at row 21.
* **The variable text is staged in WRAM.** Each glyph reaches VRAM as an 8-byte
  DMA (two tilemap words for the top row, two for the bottom) issued by
  `$80:8C96`, sourced from `$83:1900`+ — which is **not ROM**: banks `$80`-`$BF`
  mirror WRAM at `$0000`-`$1FFF`, so that is the WRAM buffer at `$7E:1900`.
* **The buffer is filled before the screen appears** — write callbacks on
  `$7E:1906`/`$00:1906` across the whole screen catch nothing, so it arrives by
  block move (MVN or DMA), which byte-write callbacks do not see.

So the remaining link is the ROM source that fills `$7E:1900+`. Next probe:
watch for the block move itself (execution around `$80:8C96`'s caller, or an MVN
whose destination is `$7E:19xx`) rather than per-byte writes.

## FOUND: the stage-name table

The maintainer confirmed the screen appears in 2P VS, 1P-vs-COM **and** training,
and that the stage there is *selectable* — which is what cracked it, because a
selectable stage means a selection variable. The chain:

* `$7E:1838` holds the **selected stage**. Three sites copy it into the scene id
  (`$C3:BB84`, `$C3:BB9A`, `$C3:BBC3` — `lda $1838 / sta $8E`).
* Two sites index tables with it: `ldx $1838 / lda $B5C1,X` and
  `ldx $1838 / lda $B5AD,X`, both loading bank `$C4` as the data bank. So:

      $C3:B5AD   10 words -> per-stage name record, palette 3
      $C3:B5C1   10 words -> the same names, palette 4

* The records live in bank `$C4`, **0xCC bytes apart**, each a 6-byte header
  (`e4 02 30 00 02 00`), padding, then the name as **tilemap words, two per
  glyph (T, T+1)**, terminated by `0000`.

Stage 2's record at `$C4:5C30` reads

    48 0F 49 0F  4A 0F 4B 0F  02 0D 03 0D  4C 0F 4D 0F  00 00
    時 (348)     空 (34A)     の (102)     扉 (34C)

— **時空の扉**, exactly the maintainer's capture. All ten decode sanely (stages 0
and 7 are 25 glyphs, the two Dead-Moon-style long names; most are 4-6).

### Renaming is now a data edit

Write new glyph words into the stage's record in **both** tables (palette 3 at
`$C4:5C30`, palette 4 at `$C4:5C96` for stage 2). Each record has 0xCC bytes and
a 4-glyph name uses ~38, so length is not a constraint.

For **沈黙のメシアの玉座** four glyphs are missing from the font — 沈, 黙, 玉,
座 (の, メ, シ, ア all exist) — and the sheet has **20 free 16x16 slots**, four of
them (`$368`-`$36E`) immediately after the existing kanji block. So the
maintainer's first choice, kanji, is also affordable: author four tiles, write
two records.

Still to locate for that: the ROM source of the menu font sheet, so the four new
glyphs can be added to it.

### Record layout — CORRECTED after it crashed the game

The first reading of this was wrong and the build made from it (v0.13.8)
**corrupted the screen and hung the game about a second after the stage was
selected**. The real layout:

    +0x00  header  `e4 02 30 00 02 00`   (0x30 = a row field's size)
    +0x06  TOP row     exactly 24 words, ALWAYS
    +0x36  BOTTOM row  exactly 24 words, ALWAYS   (the same glyphs + 0x10)
    = 0x66 bytes per record

**There is no terminator.** The name is *centred* in its 24-word field by
leading and trailing ZERO words. That is what fooled the first reading: stage
2's four glyphs sit at +0x16 only because eight zero words precede them, so
"read from +0x16 until 0000" looked exactly like a terminated string starting
there. Writing a longer name from +0x16 then ran through the bottom row, and the
second row ran past the end of the record into the NEXT stage's header.

24 words = **12 glyphs maximum**, so 沈黙のメシアの玉座 (9) still fits.

A glyph contributes two words per row — `(T, T+1)` on top, `(T+0x10, T+0x11)`
below — each OR'd with the record's own palette bits, which the writer reads
from the field rather than assuming.

**Lesson:** a run of zeros after a string is not evidence of a terminator. Two
records side by side would have shown the padding immediately — stage 1's name
is *nine* glyphs with three zero words of padding each side, and reading it the
same way returned seven.

`mkstage_port.py` writes it: `STAGE_NAME` (env-overridable) plus a `GLYPH` table
of tile codes read off the font sheet. It refuses a character the font lacks
rather than drawing a wrong glyph.

**Proof-of-concept shipped in v0.13.9** (v0.13.8 is the broken one — discard it): the ported stage is named
**サイレントメシア**, written with glyphs the font already has, so the edit can be
confirmed on a pad before any tile authoring. Verified in the built ROM by
decoding both records back (top rows read サイレントメシア in palettes 3 and 4;
bottom rows are exactly top + 0x10), and the only bytes touched in that region
are inside the two stage-2 records.

Next, for the real name: author 沈, 黙, 玉, 座 into four of the sheet's 20 free
slots and extend `GLYPH`. That needs the ROM source of the menu font, still to
be located.

### CONFIRMED in the field (2026-08-03)

v0.13.9's rename "reads correctly and cause no side effect I could trigger" —
so the record layout above is right and the mechanism is proven end to end.

### DONE — the kanji name (v0.14.0)

The stage is named **沈黙のメシアの玉座**. What it took, and where the font lives:

* **The menu font is TWO compressed blocks**, same codec as everything else:
  `$C3:48D0` (kana and general glyphs, 0x4C00 bytes) and **`$C7:07F0` (the kanji,
  0x16C0 bytes, tiles based at 0x300** — a tile's data is at
  `(tile - 0x300) * 32`).
* Finding them: the CHR is staged in WRAM before upload, and the writer at
  `$C0:91C7` is the decompressor's literal store. Its documented entry `$C0:916B`
  is NOT the one this path uses, so a hook there never fires — hooking the loop
  setup at **`$C0:91A0`** instead logs every call with its source and
  destination. The screen's own loads are `$C3:6D30`, `$C3:48D0`, `$C7:07F0`,
  `$C3:7C00`, `$C6:0000`, all to `$7E:2000`.
* The job table that feeds it is at `$C3:BEE0`+: records of
  `[src24][dest24][…][flag]`. The kanji block's source is the **only** `F0 07 C7`
  in the ROM, at **`$C3:BEF2`**.
* **The block must be relocated, not patched in place** — our encoder is weaker
  than the original's, so even the *untouched* block re-encodes to 0x13AD against
  the original 0xD5B. `mkkanji.py` decompresses it, writes the new glyphs into
  blank slots, re-encodes, appends it to the port's bank and rewrites the three
  pointer bytes.
* **The glyphs** (`mkkanji.py`) are rendered from Hiragino at 16x16 and styled
  like the game's own kanji: a colour-1 outline with the stroke interior running
  a light vertical ramp.

Verified: the relocated block is byte-identical to the original except exactly
the 16 tiles of the four new glyphs; in live VRAM the new slots are populated and
時/空/扉/サ/の/メ are untouched; and the name record renders 沈黙のメシアの玉座
against the live font. Regression 57/57.

Everything below was the groundwork.

#### Historical: what was left before v0.14.0

Only the font. `沈黙のメシアの玉座` needs 沈, 黙, 玉, 座 authored into four of the
sheet's 20 free 16x16 slots (four sit at `$368`-`$36E`, right after the existing
kanji), then four entries added to `GLYPH` and the string changed.

The font is **not** stored raw and **not** DMA'd from ROM: logging every VRAM DMA
from boot shows the CHR arriving in 0x40-byte chunks from a **WRAM staging
buffer at `$7E:3640`+**. So the chain is `ROM -> (decompress) -> $7E:3640 ->
VRAM`, and the open question is the one link at the front: what fills `$7E:3640`.
Next probe: catch the block move or decompressor call that writes it, the same
way `$C3:7C00` was found for the tilemap.

Tooling note: `probe_menu_survey.lua` takes `MINLEN` to filter the DMA log to
large transfers.
