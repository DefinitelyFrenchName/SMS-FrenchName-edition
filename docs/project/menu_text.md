# Patch 16 — the menu-translation working record

**This is the project's log, not the reference.** It is how the menu system was
worked out, in the order it happened: the measurements, the dead ends, the
corrections of earlier entries in this same file, the maintainer's string
choices, and what each build shipped. Entries are dated and later ones supersede
earlier ones in place.

**For how the system WORKS, read [`../game/menu_system.md`](../game/menu_system.md)**
— the glyph format, the font sheets, the two screen engines, the runtime text
writers, the VRAM rules and the cell budgets, stated once and cleanly. That file
is knowledge of the retail ROM and is reusable by anyone; this one is only
meaningful to this project. Where the two overlap, **the game doc is
authoritative** — if a mechanism here reads differently, it is an older entry
that the game doc has since tidied.

Patch 16's current status and gates are in
[`patch_index.md`](patch_index.md) and [`patch_notes.md`](patch_notes.md)
§ Patch 16; what to do next is in [`NEXT_SESSION.md`](NEXT_SESSION.md).

---


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
tilemap. That is the same job as Saturn's movelist (`docs/project/saturn/movelist.md`),
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

`docs/project/saturn/movelist.md` recorded "Still missing: the code -> glyph table". It
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

**Glyph-slot budget, counted as the sheet is arranged (2026-08-04).** A glyph is
2x2 tiles at `(t, t+1, t+16, t+17)`, so a HALF-width glyph needs `(t, t+16)` and a
FULL-width one needs two adjacent half-slots. In place, without relocating:
`kana $0A0-$0A1` (2 half-slots) + `kanji $368-$36F` (8) = **10 half-slots = 5
full-width glyphs**. Enough for `S` + `.` full-width and `Y` + `K` half-width
(6 of 10) with four to spare — but NOT enough to also finish J/Q/Z at full width.
Beyond that the kanji block must be extended, which `mkkanji.py` already does
(it added the stage kanji in v0.14.0); the survey read VRAM `$3C0-$3EE` as blank,
~57 tiles of apparent headroom, which is evidence rather than proof.

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
its destination.

> ⚠ **CORRECTED TWICE since this was written (2026-08-08).** The record layout is
> `[vram16][len16][src24][dest24]` (see "The upload length — SOLVED" below), **and
> the count and base are both artifacts of the flat scan**: there are **74
> records** spanning `$C3:BD61-$C3:C04B`, reached through two pointer tables —
> `$C3:BCCD` (25 entries, all `0x800` tilemaps) and `$C3:BCFF` (49 entries, CHR
> and text sheets), disjoint, 25 + 49 = 74. Scanning at a 10-byte stride from
> `$BE02`/`$BE08` finds only the last stretch and silently misses the 16 records
> before it. Walk the pointer tables. (`mkpatch16.py`'s `REC0`/`NRECS` is that
> same scan window; it works because the records it needs are inside it.) (The earlier note said `$C3:BEE0`; that address lands mid-record.
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


## Stage names — the maintainer's translations, validated (2026-08-04)

All eleven check out at **12 full-width cells**, needing only two glyphs drawn.
Machine-checked with `tools/menutext_check.py stages` (budget, glyph
availability, and the centred tile encoding a patch would write).

| # | Japanese | English | cells |
|---|---|---|---|
| 0 | クリスタルトーキョー◆夕 | `CR. TOKYO ◆夕` | 12 |
| 1 | シルバーミレニアム | `S. MILLENIUM` | 12 |
| 2 | 時空の扉 | `TIME DOOR` | 9 |
| 3 | 海王州公園 | `KAIOSHU PARK` | 12 |
| 4 | 噴水公園◆昼 | `FOUNTAIN ◆昼` | 11 |
| 5 | 十番商店街 | `SHOP. STREET` | 12 |
| 6 | 火川神社 | `SHRINE` | 6 |
| 7 | クリスタルトーキョー◆夜 | `CR. TOKYO ◆夜` | 12 |
| 8 | 噴水公園◆夜 | `FOUNTAIN ◆夜` | 11 |
| 9 | なかよし編集部 | `EDITOR. DEPT` | 12 |
| — | (Saturn build, over stage 2) | `SLNT. THRONE` | 12 |

**To author: `S` and `.` only** — 4 of the 10 free half-slots, no relocation, and
no half-width glyphs needed. The day/evening/night markers are kept as-is, so
`◆`, `昼`, `夕`, `夜` are all existing glyphs.

Two notes for the maintainer, neither blocking:

* **`MILLENIUM` is missing an N** — the English is MILLENNIUM. The correct
  spelling makes the string 13 cells (`S. MILLENNIUM`), one over budget, so this
  looks like a deliberate trade rather than a slip; recorded so it is a choice
  and not a surprise later. `SILVER MLLNM` and `S. MILLENN.` also fit if either
  reads better.
* **`SHRINE`** drops 火川 (Hikawa). `HIKAWA SHRINE` is 13 and does not fit;
  `HIKAWA SH.` (10) would if the shrine's name matters more than the word.

**Table correction found while validating:** `$22E` is the EVENING marker `夕`,
not katakana `タ`. The letterforms are near-identical, but katakana `タ` has its
own slot at `$102`, and `$22E` sits in the marker group beside `◆`, pairing with
`昼`/`夜` on the other stages. The first pass mislabelled it, which made stage 0
fail its own check.


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

## HALF-WIDTH: the reuse premise is FALSE — measured 2026-08-04

The plan recorded above ("Half-width Latin already EXISTS — the
`PRESS "SELECT" TO ACS` strip is individually addressable, 1 tile wide and 2
tall, giving **P R E S L C T O A**") does not survive contact with the pixels.
**There are no reusable half-width letters in this game.**

Measured straight from ROM — no emulator needed, the block is
`$C7:07F0` and `tools/saturn/sms_lz.py` round-trips it:

* The strip's 22 slots hold **22 distinct glyphs — zero duplicates**, even though
  the string repeats S four times and E, T, C and `"` twice each. A per-letter
  font could not do that.
* Rendering the strip as one continuous 176 px banner shows why: the ink forms
  **five word-shaped runs** (widths 40, 25, 29, 16, 24 px), **every one of which
  spans tile boundaries**. Blank columns fall at all eight positions within a
  tile, not at position 0 or 7.

So the banner is **proportionally-spaced artwork that happens to be stored as
tiles**, not a font. No tile contains exactly one letter, so nothing can be
lifted from it. A half-width alphabet has to be **authored from scratch, all 26
letters** — the same job as the movelist font, at a different size.

### The good news: there is room, and more than expected

The font block does **not** load at tile `$300`. That is `mkkanji.py`'s
block-relative numbering; in VRAM it lands at **tile `$500`**, verified by an
exact byte match of all 182 tiles (`$500-$5B5`).

A census over **all 192 VRAM captures** in `traces/menu/` (every screen the
survey visited) gives the tiles free in *every* one:

| region | tiles | note |
|---|---|---|
| `$5C0-$5FF` | **64** | immediately above the font block — the natural extension |
| `$738-$7BF` | **136** | a second, larger run further up |
| four small runs below `$101` | 30 | fragmented, not useful for a font |

**This confirms the survey's `$3C0-$3EE` suspicion** — that was block-relative
for VRAM `$5C0-$5EE` — and on a much bigger sample than the original reading.

### The budget, and it fits

A half-width glyph is 1 tile wide × 2 tall = **2 tiles**.

    26 uppercase letters          52 tiles
    digits 0-9                    20 tiles
    a working punctuation set     ~14 tiles
    ------------------------------------------
    full set                      ~86 tiles

`$5C0-$5FF` alone (64 tiles) holds **32 half-width glyphs — the 26 letters with 6
to spare**. Digits and punctuation would take the second run at `$738`, or the
existing full-width digits can be reused since numbers rarely need narrowing.
Extending the block is already a solved mechanism: `mkkanji.py` decompresses,
inserts, re-encodes and relocates it, which is how v0.14.0 added the stage kanji.

### What is NOT yet proven

"Free in 192 captures" is stronger evidence than the original reading, but it is
still **evidence, not proof** — the captures only cover the screens the survey
visited. Before authoring into `$5C0-$5FF`, watch VRAM writes in that range over
a full boot → title → select → match → KO → win session, the same way
`probe_sms_freetable.lua` cleared the audio table's spare records. This project
has already been burned once by a region that passed "nothing points at it" and
was still live.

### What this does to the decision

Half-width is still worth having — it doubles the characters per cell, and the
room exists. But it is **authoring 26 glyphs, not harvesting 9**, so the cost is
squarely in drawing legible 8×16 capitals in this game's style, not in finding
space. The full-width route (`S` and `.` to author, no relocation) remains much
cheaper and is still the fastest path to a first shipping screen.

### The Big Zam edition as a SOURCE OF LETTERFORMS (maintainer lead, 2026-08-04)

The maintainer pointed out that BZ's title screen renders its menu items
(TRAINING / OPTIONS / TOURNAMENT) in **narrow English letters** rather than
full-width kana. Worth chasing, because it is a different question from the one
this file already closed ("BZ does not TRANSLATE the menus" — true, and
irrelevant to whether its own tiles carry usable letterforms).

**What is established:**

* **BZ changes nothing in the normal asset path.** Both font blocks
  (`$C3:48D0` kana, `$C7:07F0` kanji) are **byte-identical** to clean, and so are
  **all 59 records** of the compressed-asset job table at `$C3:BE02` — same
  sources, same destinations, same decompressed payloads. So BZ's Latin is not
  a font it swapped in; it is injected into VRAM at runtime, which matches
  `mkpatch4.py`'s note that the credit tiles exist "only in a packed/injected
  form, hence the VRAM extraction".
* **BZ's title screen does carry Latin**, at VRAM `$2C2-$2FC` (the
  "©MOONLIGHT FIGHT SOCIETY" credit line patch 4 already lifts) and in at least
  two further text rows at `$300+`. ⚠ Note the numbering: `mkpatch4.py` counts
  tiles from the title screen's char base `$200`, so its "tile `0x0C2`" is VRAM
  tile **`$2C2`**. Rendering at `$0C2` shows blank and looks like a dead end.
* **These are proportional artwork too.** Objectively: the credit line has 19 ink
  runs of which **15 span tile boundaries**; the narrow row has 19 runs, **15
  spanning**, with run widths of 5-12 px. So BZ's letters are no more
  individually addressable than SMS's `PRESS "SELECT"` banner.

**Why the lead is still valuable.** Not as a font to reference, but as a
**source of shapes**. The letterforms are extractable pixel-wise from a VRAM
capture and can be re-cut onto a tile grid — which turns "design 26 half-width
capitals from nothing" into "trace and re-cut existing ones that already look
right in this game". It also settles the aesthetic question the maintainer would
otherwise have to judge blind: narrow Latin at this size demonstrably reads on
this hardware, because a shipped hack does it.

**NOT yet done — the strings the maintainer named are still unseen.** Every BZ
capture in `traces/` is from the attract/logo phase (`mode $00`, bgmode 0/1,
intro scroll DMAs); two scripted walks with Start presses never reached the
mode-select menu. So TRAINING / OPTIONS / TOURNAMENT have not actually been
captured, and the letter inventory below is what the CREDIT LINE alone offers:

    from "MOONLIGHT FIGHT SOCIETY":  C E F G H I L M N O S T Y   (13 of 26)

Reaching the menu would add at least **A P R U** (TRAINING, OPTIONS,
TOURNAMENT), taking it to ~17. The remaining nine (B D J K Q V W X Z) would have
to be drawn to match — which is the same job as before, but with a style
reference and two thirds of the alphabet already solved.

**Next step:** a working navigation script to BZ's mode-select menu, then the
same tile-alignment + letter-segmentation pass run here. `probe_menu_survey.lua`
takes `KEYS="start:900 …"`; the two attempts recorded above did not advance the
screen, so the walk needs checking against what BZ actually wants (it may need
the attract loop to finish, or a different button).

## CORRECTION + FOUND: the TOURNAMENT EDITION has a real half-width font

Everything in the section above was measured against **`sailor moon s big zam
edition (hack).sfc`** — which is *not* the Tournament Edition. The maintainer
caught it. The TE is a separate ROM, **`SMS_BZE_TE.sfc`**
(sha1 `3cc5c0dfe54b6ec16d06923e8e9d3eff2a434e82`, 3 MB), and `smspaths.py` has no
accessor for it, which is how the mistake happened.

The BZ findings still stand *for BZ* (its font blocks and all 59 asset records are
identical to clean; its title Latin is proportional artwork). But the TE is
different in the way that matters.

### TE has a tile-aligned half-width Latin font, on screen, today

Captured with `ROM=<TE> OUT=te tools/run.sh tools/probe_title_vram.lua 120`
(frame 700 is the one with the menu). Two things had to be got right to see it:

1. **Polarity.** These cells are drawn as a FILLED cell (colour 1) with the
   letter in the other indices. Rendering "any non-zero" shows solid blocks and
   hides the glyphs completely. Ink = non-zero **and != 1**.
2. **The alignment rule.** A font row is one whose ink runs sit on a *consistent*
   8 px grid — not one whose runs start at multiples of 8. TE's glyphs carry a
   1 px left bearing, so every run starts at offset **1**: `starts_mod8=[1]`, a
   single value, which is a perfect grid. The stricter rule rejected the real
   font on the first pass.

With both right, `tools/te_halfwidth.py rows` classifies the title screen:

| tile row | verdict | starts mod 8 | glyph widths |
|---|---|---|---|
| `$300`, `$320`, `$3A0` | art | 5-7 distinct offsets | 10-12 px |
| **`$340`/`$350`** | **FONT** | **[1]** | 5-6 px |
| **`$380`/`$390`** | **FONT** | [0, 1] | 4-6 px |

and **row `$340` decodes letter by letter as**

    T O U R N A M E N T   M O D E

`tools/te_halfwidth.py extract` pulls **16 distinct 8×16 glyphs** to
`docs/game/te_halfwidth.json` (bitmaps + tile ids, labels left null for a human pass).

### What this changes

The premise is alive again, in a better form than the original: half-width Latin
does not have to be authored from nothing, and does not have to be traced out of
proportional artwork either. A **shipped, tile-aligned, correctly-styled font
exists in a ROM this project already has on disk**, and it is directly liftable —
the same lift patch 4 already does for the credit line, and patch 3 for palettes.

### Next steps

1. **Label the 16 glyphs** against the on-screen strings — that turns
   `te_halfwidth.json` into a code→glyph table, the half-width twin of
   `menufont_table.py`.
2. **Find the rest of the alphabet.** TOURNAMENT MODE + row `$380` gives a subset;
   TE's other screens (options, the tournament brackets) very likely carry more.
   Capture them the same way rather than assuming — the rows above are one screen.
3. **Add a `te_rom()` accessor to `smspaths.py`** so this ROM is addressable by
   name and nobody repeats the BZ/TE mix-up.
4. The VRAM space question is unchanged and still open: `$5C0-$5FF` is free in
   all 192 clean captures, but that is evidence, not proof — write-watch it before
   authoring into it.

### The TE half-width font, labelled — and its metrics for matching

Two of the title's font rows decode cleanly:

    row $340   ! T O U R N A M E N T   M O D E
    row $380   O P T I O N S

which labels 15 of the 16 extracted glyphs (`docs/game/te_halfwidth.json`). A third
row, `$360`, is visibly the same face (`P R A C/G T I/J ? E`) but the classifier
still calls it art because two of its runs merge — worth a second pass, it should
add **C** and probably **G**.

**Confirmed letters: A D E I M N O P R S T U — 12 of 26.**
**Missing: B C F G H J K L Q V W X Y Z.**

So the TE alone does not give a full alphabet, as expected from three menu words.

**Metrics, for identifying it against a stock font** (the maintainer's hypothesis
is that this may be a common SNES half-width Latin set, in which case a complete
alphabet can be sourced elsewhere and matched):

| property | value |
|---|---|
| cell | **8 × 16 px** — 1 tile wide, 2 tall |
| ink extent | x = 0..6 (**7 px** wide), y = 2..13 |
| cap height | **12 px** |
| left bearing | 0 px on row `$380`, **1 px** on rows `$340`/`$360` — the rows sit on different sub-grids |
| stems | **2 px left, 1 px right** — asymmetric |
| colours | **3 indices (3, 4, 5)** over fill colour 1 |

⚠ Two of those matter for any matching attempt. The face is **not 1-bit**: it uses
three shades, and the asymmetric stems are a deliberate emboss/shadow, not a
rendering artefact. A stock 1-bit RPG font would match the *shapes* but not the
shading, so a lift from elsewhere would need re-shading to sit next to these — or
the TE glyphs re-flattened to match the donor. Worth deciding which direction
before drawing anything.

The other consequence: because the shading is baked per glyph, these cells are
**palette-dependent**. Whatever CGRAM row the menu screen uses has to carry
compatible shades, which is a separate check from the VRAM space question.

### Does the TE font match vanilla SMS's banner letters? NO — measured

Worth asking, because if TE's font were SMS's own half-width face merely
re-gridded, it would be stylistically native and the aesthetic question would
answer itself. It is not.

Method: translation-aligned **intersection-over-union on ink pixels**, calibrated
against controls before being believed.

| comparison | IoU |
|---|---|
| **control** — same TE letter, different tile/sub-grid (`O` `$343` vs `$384`, `N` `$346` vs `$385`) | **100%** |
| **control** — different TE letters | mean 64%, max 89% (`U` vs `O`, genuinely similar shapes) |
| **TE glyphs vs the vanilla `PRESS "SELECT"` banner** | **47-72%** |

Every TE glyph scores in the range that *different letters* occupy, nowhere near
the 100% that the same letter reaches. Corroborating: the vanilla banner uses all
**16 colour indices** (a gradient ramp) against TE's **3**. Cap height is the same
11 px in both, which is why they look related at a glance — but the letterforms
are not the same design.

⚠ **Metric trap, paid for here.** The first attempt scored raw pixel agreement
over the glyph box and produced *inverted* results — same letter 43-48%,
different letters up to 95%. Background pixels dominate that measure, and a 1 px
sub-grid shift destroys it. Any shape comparison here needs ink-only IoU with a
translation search, and needs the same-letter/different-letter controls run
first or the numbers mean nothing.

**Consequence.** TE's half-width font is **foreign to SMS** — it was not derived
from anything in the base game. That makes the maintainer's "standard SNES
half-width set" hypothesis *more* likely, not less: the face came from somewhere,
and if that somewhere is a common font, the complete alphabet is findable. The
metrics table above plus the 12 confirmed glyphs in `docs/game/te_halfwidth.json` are
what a candidate should be tested against — using IoU with controls, not eyeball.

## CONDENSING SMS's OWN CAPITALS: viable — measured 2026-08-04

The licence-free option: SMS already contains **21 Latin capitals** (A B C D E G
H I K L M N O P R T U V W X Y — missing F J Q S Z). Condensing those 16x16 glyphs
to half width would give a native, in-style, licence-clean alphabet. Tested.

### First, the addressing — this cost several wrong turns

`docs/project/menu_text.md` records the capitals at "**$20A** onward". That is a **VRAM
address on a screen that displays them**, not a block offset, and the kana block
does not load at a fixed base:

| | |
|---|---|
| Latin `A` in the kana block (`$C3:48D0`) | block tile **`$16A`** |
| screens showing Latin load that block at base | **`$0A0`** (hence VRAM `$20A`) |
| the button-config screen loads it at base | **`$2A0`** — so `$20A` there is unrelated artwork |

Chasing `$20A` across captures therefore finds gradients, borders and katakana in
turn, all of which happened. `tools/menufont_table.py` had the answer the whole
time and states it explicitly ("Latin 'A' is block $16A and the screens use
$20A"). **Read the derived table before re-deriving from captures.**

Two supporting corrections: the kanji block loads at VRAM **`$500`**, and asset
**#22** (`$C3:6D30`) supplies VRAM `$200`+ on the config screen — both located by
searching captures for decompressed block bytes, which is the reliable way to pin
a base and needs no DMA log.

### The result: AND-of-column-pairs is the method

Three 16→8 reductions tried on all 21 capitals:

| method | verdict |
|---|---|
| **AND of each column pair** | **best** — 2 px stems, 3-4 px counters, letters stay open |
| OR of each column pair | too heavy; stems go 3 px and counters close up (M, W, X turn to mush) |
| drop odd columns | workable but noisier than AND |

**AND lands on 2 px stems inside ~6-7 px of ink — the same weight as TE's
half-width font, which is already proven legible on this hardware.** That is the
key number: the condensed capitals are not merely readable, they match the weight
of a face shipped in a real hack.

**Quality, honestly:** of the 21, roughly 17 come out clean. **M, W and X** need
hand touch-up — their middle diagonals thin to 1 px and read raggedly — and `A`'s
apex is slightly off. So the job is ~4 glyphs to repair plus **5 to author**
(F J Q S Z), against 26 from scratch or a licence question.

### Why this is now the leading option

No licence surface at all — it is the game's own art, the same basis on which
this project already reuses BZ palettes and Super S assets. Natively in style, so
no reconciling a foreign face against the kana. And the authored remainder is
small enough to be a quick win rather than a project.

### A complete half-width A-Z now exists — `tools/mkhalfwidth.py`

Built from the three sources the condensing test implied:

| source | count | which |
|---|---|---|
| **condensed** from the game's own capitals (AND of column pairs) | 17 | B C D E G H I K L N O P R T U V Y |
| **repaired** — diagonals thinned to 1 px under AND | 4 | A M W X |
| **authored** to match the condensed siblings | 5 | F J Q S Z |

`sheet` renders the alphabet, `text "MANUAL"` renders a string at true size,
`export` writes `docs/project/halfwidth_caps.json`. Nothing is committed that isn't ours:
the condensed glyphs are a mechanical reduction of the game's own art, the same
basis as every other asset reuse in this project.

### The budget answer — which was the point of the whole exercise

| string | half-width cells | equals full-width cells | vanilla had |
|---|---|---|---|
| `MODE` | 4 | 2 | 3 (`モード`) |
| `STAGE` | 5 | 2.5 | — |
| `MANUAL` | 6 | **3** | 5 (`マニュアル`) |
| `TOURNAMENT` | 10 | 5 | — |

**Every validated string fits inside its existing cell budget with room to
spare** — `MANUAL`, the widest value on the VS screen, needs 3 of the 5 cells the
Japanese occupies. That is the case for half-width in one line: it is not a
marginal gain, it removes the budget problem entirely.

### Honest weak spots

* **M is the weakest glyph.** The source face has a 2 px left stem and 1 px right
  (an emboss, shared with TE), and at half width that asymmetry reads as lopsided
  in a word. Worth a second pass by eye.
* **N**'s diagonal is slightly noisy, and **U**'s right stem is thin for the same
  emboss reason.
* The five authored glyphs are first drafts matched to the condensed band, not
  final art. `S` and `Q` in particular deserve a look at true size on screen.

None of these block anything — they are polish on a set that already renders
readable words.

### Still the gate, unchanged

`$5C0-$5FF` (64 tiles, enough for 32 half-width glyphs) is free in all 192 clean
VRAM captures, but that is **evidence, not proof**. Write-watch that range over a
full boot -> title -> select -> match -> KO -> win session before authoring into
it, the same way `probe_sms_freetable.lua` cleared the audio table's spares.

## VRAM space: GATE PASSED, with a caveat that matters — 2026-08-04

`tools/probe_vram_free.lua` turns "free in 192 captures" into a real answer by
running a **full session** — boot, intro, mode select, character select, a match
with damage on, a KO and the win screen — and testing the range two ways at once.

**Result for `$5C0-$5FF`:**

| phase | state |
|---|---|
| boot / intro | zero |
| mode select | zero |
| character select | zero |
| **match load** | **1416 of 2048 bytes go non-zero** |

**Verdict: free on every MENU screen; first used at match load.** For a menu font
that is a **pass** — the match replaces VRAM wholesale and the glyphs are
re-uploaded whenever a menu is drawn again. It would NOT be safe for anything
that has to persist into gameplay, and the probe says so rather than printing a
bare "free".

### The part worth remembering

**The write watch saw ZERO writes. The snapshots caught all 1416 bytes.**

VRAM is filled by DMA, and DMA does not surface as a CPU write callback. A probe
built only on a write watch would have reported this range pristine through a
full match and been completely wrong. That is the same class of error as the
earlier "a probe that reports nothing is usually broken" cases, and it is why
this probe carries both mechanisms and cross-checks them: if the watch is silent
while a snapshot goes dirty, the watch is what is broken.

The first attempt also timed out at the title because the navigation was
hand-rolled; the autopilot is now lifted verbatim from the probes known to reach
a match. Reuse the working flow rather than writing a new one.

## The font upload path — FOUND 2026-08-04

Patch 16's font install builds correctly but its extra tiles never reach VRAM.
The upload route is now identified, after several wrong turns worth recording.

**It is DMA, set up from direct page.** Two near-identical routines stage a
transfer and fire it:

    $C0:9287   ldy #$18 / sty $4301        ; dest = $2118 (VRAM data)
               lda $30 / sta $2116         ; VRAM address
               lda $32 / sta $4305         ; LENGTH
               lda $34 / sta $4302         ; source address
               ldy $36 / sty $4304         ; source bank
               ldy #$01 / sty $4300 / sty $420B
    $C0:92AD   the same, reading direct page $00/$02/$04/$06 instead of $30+

So **the transfer length lives in direct page `$02` (or `$32`)** at the moment of
the trigger — not in the asset job table, which is why bumping that record's
`u16b` changed nothing.

Related: `$C0:92F7` drives uploads from a **6-byte record table at `$E0:00B4`**
(index = id*6), composing a VRAM word address as `record[+0] * 2 + $0500`.

### Why three probes in a row found nothing

1. **`$2116`/`$2117` hooked without a bank.** Mesen's `snesMemory` is the full
   24-bit bus; the game writes `$80:2116`. Bank-0 hooks catch nothing.
2. **The window was watched, but not the total.** Two runs printed a confident
   zero while the hook was dead. The probe now prints the unconditional count
   first — a dead hook must never again look like "the game does not do this".
3. **The DMA logger filtered on `emu.read($4301)`.** Those registers are
   WRITE-ONLY, so reading back the destination returns nothing useful and the
   font transfer was discarded by the filter. Only 39 transfers survived it, all
   small ones that happened to read as `$18`.

The lesson common to all three: **verify the instrument against a known-present
signal before believing an absence.** A 16544-write signal was there the whole
time.

### Next step, concrete

Hook the DMA trigger (`$420B`, all mirrors) and read **direct page `$00`-`$07`**
at that instant rather than the DMA registers. That yields the true VRAM address,
length and source of every transfer, including the font's. Then trace what sets
the length for the font block — that is the value patch 16 has to change.

### Why the extra tiles never arrive — ANSWERED

With the probe filtered to the real uploader (`$C0:92D2`), the menu screen is
built by **50 transfers**, and the font's VRAM region is covered by exactly one:

    vram word $4000   len $3480 bytes   src $7E:C000

`$3480` bytes = `$1A40` words, so that transfer fills VRAM words `$4000-$5A40`,
i.e. tiles `$400-$5A4`. **No transfer in the whole screen build touches word
`$5C00` or above.**

That is the answer. Patch 16 extends the *compressed block*, which does make the
decompressed sheet bigger — but nothing then carries the extra bytes to VRAM,
because the transfer that covers this region has a fixed length that stops short
of the new tiles. It also independently confirms the earlier observation that
VRAM simply ends at tile `$5B5` on the patched ROM.

**So the patch needs two changes, not one:**

1. the block extension (done), and
2. the **transfer length** for the region — the value staged in direct page `$02`
   for the `$7E:C000 -> $4000` upload — has to grow to cover the new tiles, with
   the decompressed font laid out contiguously in WRAM so the longer transfer
   picks it up.

That length is written from the routine that stages the transfer, so the next
step is to find what feeds DP `$02` there — a constant in the caller, or a field
in whatever table drives these 50 uploads. Once that value is patchable, the
glyphs reach VRAM and the tilemap edits can begin.

Not a dead end: a bounded, located problem with the instrument now trustworthy.

## The upload length — SOLVED 2026-08-05, and the record layout was wrong

Patch 16's step 1 works: the 26 half-width glyphs reach VRAM tiles `$5C0-$5FF`
on the button-config screen and render as a legible A-Z, read back **out of
VRAM** rather than out of the build.

### The asset record layout in the notes above is WRONG

A record is **not** `[src24][dest24][u16][u16]`. It is

    [vram16][len16][src24][dest24]        10 bytes, table starts $C3:BE08

so a block's upload **length sits 2 bytes BEFORE its src pointer**, not 8 bytes
after it. That single off-by-one-record is why every earlier attempt to grow the
transfer "changed nothing": the write landed in the *next* record and quietly
lengthened an unrelated upload.

Proof, not inference: parsed this way, **27 of the 58 records match a transfer
observed on the config screen exactly** (vram, len and dest all three), and the
rest are simply records that screen does not run. Parsed the old way, none line
up — the pairing only worked if you took record N's `(vram,len)` with record
N+1's `dest`, which is the same statement as the corrected layout.

The field is a **byte count**, not words: the font record carries `$3480` and its
measured DMA covers `$1A40` words.

### Which record, and the ceiling

| | |
|---|---|
| font sheet the menu screens load | `$C4:2590`, 418 tiles, → `$7E:C000` → VRAM `$400` |
| its record | #27, at `$C3:BF16` |
| **the length field** | **`$C3:BF18`** — `$3480` → `$4000` |
| ceiling | `$4000`. The source is `$7E:C000`, so a longer transfer runs off the end of bank `$7E` and wraps. |

`$4000` bytes = `$2000` words = VRAM `$4000-$6000` = tiles `$400-$5FF`, which is
exactly the free region this document already proved out.

### The kanji block is a dead end for this screen

Earlier builds extended the **kanji** block (`$C7:07F0`, VRAM `$500`) and tested
on the config screen — where **no transfer to VRAM `$5000` happens at all**. Those
glyphs could never have appeared there however the length was set. Whatever
screen does load the kanji block is a separate question; the config screen's own
sheet is `$C4:2590`, and that is what `mkpatch16.py` now extends.

### How it was verified

`tools/probe_menu_vram.lua` dumps the region **on the font transfer**, not at the
end of the run — a dump taken on the final screen reads identical on clean and
patched ROMs, because a later, smaller upload has already overwritten it.

* **Positive control** (`POKE=1`): stamp a pattern into the source buffer past
  the vanilla transfer's end. **0/256** bytes arrive on clean, **256/256** with
  the length raised. Comparing clean against a length-only change without this
  proves nothing — both source and destination are zero out there, so the dumps
  come back identical either way.
* **On the built ROM**: VRAM `$5C0-$5FF` holds **52 of 64** non-blank tiles —
  exactly 26 letters x 2 tiles — against **0** on clean.

Next: the tilemap edits. The glyph → VRAM tile map is written to
`docs/project/halfwidth_tiles.json` by the builder.

## Options screen: WORKS — labels translated (2026-08-06; field-confirmed same day)

**Field report (maintainer, 2026-08-06):** legibility "excellent"; repeated
entry/exit and value cycling clean; other menu screens confirmed untouched.
One observation, accepted as-is: the letters render with a slightly wobbly
bottom alignment — that is per-letter baseline variance from the condensation
in `mkhalfwidth.py` (the glyphs are consistent in the sheet), and the
maintainer likes the effect ("a fun, childish look"), so it stays. The flat,
unshaded ink also stays — it reads better than the shaded full-width font at
this size.

**Strings (maintainer, 2026-08-05)** and the measured fields. Labels start at map
column 4, values occupy columns 22-27. A half-width glyph is **one map column**
(a full-width one is two), so the budgets are **18 columns for a label, 6 for a
value**. Every proposed string fits:

| label | English | cols | | value | English | cols |
|---|---|---|---|---|---|---|
| COMレベル | COM LEVEL | 9/18 | | ふつう | NORMAL | 6/6 |
| せいげんじかん | TIMER | 5/18 | | むずかしい | HARD | 4/6 |
| BGM | BGM | 3/18 | | なかよし | FRIEND | 6/6 |
| こうかおん | SFX | 3/18 | | やさしい | EASY | 4/6 |
| おんせい | VOICES | 6/18 | | あり | YES | 3/6 |
| おしまい | EXIT | 4/18 | | なし | NO | 2/6 |

`NORMAL` and `FRIEND` are **exact fits**; `STD` and `PAL` are the maintainer's
fallbacks if they turn out to need a trailing blank.

**Where the screen lives.** Its tilemap is **asset record 19** (`src $C3:69F0` ->
`$7E:2000` -> VRAM `$0000`), a 0x800-byte 32x32 map — identified by searching
every asset block for the exact map words of the `COMレベル` row, not guessed.
Entry = `attr | tile`, tile is 10 bits; **BG1 CHR base is word `$2000` = tile
`$200`, so MAP tile = VRAM tile - `$200`** (half-width A-Z therefore land at map
tiles `$3C0-$3E9`, inside the field); a glyph is two map rows with
`bottom = top + $10`; labels carry attr `$0C00`, values `$1000`.

**The old blocker is SOLVED (2026-08-06), and the diagnosis rewrote the record
of what was happening.** The designated dump (`tools/probe_p16_options_buf.lua`)
showed the staging buffer `$7E:C000` holds the glyph block both at the transfer
instant and after Options settles — the stale-buffer/ordering theory is dead.
The real mechanism, watched with a per-frame VRAM census and an unfiltered DMA
log:

* the glyphs DID reach VRAM — at **main-menu entry** (the `vram $4000 len $4000
  src $7E:C000` transfer earlier attributed to Options runs there);
* the transition into Options **clears all 64KB of VRAM** (fixed-source DMA,
  `len $0000` = 65536, kicked at `$80:8191`) — census 52/64 → 0/64;
* Options then runs its own loader — straight-line code at `$C3:A4DD..A50F`,
  `lda #idx*2 / sta $1C18 / jsr $824E|$825B` per record — whose six records do
  **not** include the font record. Nothing else touches tiles `$5C0-$5FF`, so
  they simply stay blank. (Its Japanese text comes from a separate big sheet,
  `$C3:48D0` → tiles `$2C0-$529`, not from the menu font.)

**Asset-record plumbing** (clean ROM, bank `$C3`, executes from the `$03`
mirror so `$1C18` hits WRAM): pointer tables at `$C3:BCCD` ("A", 25 entries)
and `$C3:BCFF` ("B", 49 entries) map a record index to a 10-byte record;
`$1C18` = index×2. The font record `$C3:BF16` (flat-scan "#27") is **B index
15**. `$C3:82CA` = decompress (`JSL $80:927D`, DP `$00-$05` src24/dest24) then
DMA (`JSL $80:92AD`, DP `$00-$06` vram/len/src24) — both primitives JSL-able.

**The fix (in `mkpatch16.py`, always on):** the cluster's first load
(`lda #$003E / sta $1C18`, file `0x03A4DD`) becomes `JSL` to a 60-byte stub in
the appended bank that replays the two primitives with build-time constants —
decompress the extended font into `$7E:C000`, DMA it to `$4000` — then re-arms
idx 31 and returns. Order matters and is preserved: the font runs FIRST, so the
text-sheet record keeps winning their overlap at tiles `$400-$529`; the glyphs
at `$5C0-$5FF` overlap nothing on this screen. Verified: census goes 0/64 →
52/64 at the stub's transfer and stays there settled; with `SMS_P16_OPTIONS=1`
the six labels render in English (screenshot-checked); the button-config screen
re-verifies green on the hooked build (52/64 + the `POKE=1` positive control).

## Screen census — all four priority screens reached and mapped (2026-08-06)

`tools/probe_p16_screens.lua` (routes `win`/`acs`/`tournament`) drives each
screen and logs its loader (`$1C18` writes with PC — **watch the WRAM memtype,
not bus `$7E1C18`: the clusters execute from the `$03` mirror**), its uploads,
and the `$5C0-$5FF` glyph census. Results:

| screen | loader | glyphs `$5C0+` | translatable text |
|---|---|---|---|
| main menu | cluster `$C3:B76B` (runs font record B15) | **52/64** | menu items (baked art) |
| Options | cluster `$C3:A4DD` + patch 16 hook | **52/64** | DONE (labels + values) |
| vs-COM setup | cluster `$C3:B852` | 0 | — |
| char select (vs-COM) | cluster `$C3:AF8A` (text sheet `$2A00` + kanji `$5000`) | 0 | names etc. |
| VS config | no own cluster (keeps char select's VRAM + its compressed tilemap) | 0 | rows: モード/…パンチ/…キック/必殺モード, ステージ names |
| A.C.S. | cluster `$C3:9CF2` + own small font (`$4000` len `$0E00`) | 0 | stat wheel 必殺技/攻撃/体力/防御/おちゃめ, prompt sentence |
| Win = REPORT CARD | **bank `$DF` loader** (`$DF:83CE` writes `$1C18`), no `$80:92D2` uploads | 0 | KOタイム/HITすう/ダメージ/勝ちすう/ベスト (values numeric) |
| Tournament (select + bracket) | **bank `$DF` loader** (same) | 0 | プレイヤーセレクト, per-line char names, brackets' セーラー〜 VS 〜 |

⚠ **The `52/64` census figures in this file are the 26-letter measurement.** Re-measured
2026-08-08 the number is **56/64**: the set is now 29 glyphs (A-Z plus comma, hyphen and
apostrophe, authored for the stage names) and three of them have a blank half. Expect the
count to move again whenever a glyph is added — it is a census, not a constant.

**STATUS (2026-08-06, late): tournament select names, REPORT CARD labels,
stage names, the whole VS config screen, AND the ACS wheel are DONE.**
Build gates: `SMS_P16_OPTIONS` (Options), `SMS_P16_DF` (tournament select +
report card), `SMS_P16_STAGES` (stage names + config rows + MANUAL/AUTO
records + the char-select glyph hook), `SMS_P16_ACS` (wheel labels,
raster — needs STAGES). ACS trap paid for: the runtime prompt bar
references the blank \$5C0 tiles through another BG's CHR base, so NO glyph
hook on that screen (raster labels need none). Deferred: ACS name card +
prompt, and the bracket VS names. PLAYER SELECT shipped (queued 19th row
record); Saturn stage name shipped behind `SMS_P16_SATURN=1` (default off).
**Bracket VS names — SOLVED 2026-08-10, and the 08-06 hypothesis below was
wrong in every particular.** There is **no runtime builder**, the names are
**not in the codec-2 blob**, and they are **not at rows 4-5 of the `$7000`
map**. They are eighteen ordinary `$80:8C43` records in ROM, drawn straight
from bank `$DF`:

| | left side | right side |
|---|---|---|
| first record | `$DF:E119` | `$DF:E38F` |
| vmadd | `$7CE0` | `$7CF0` |
| count / stride | 9 chars, `$46` | 9 chars, `$46` |

Header `[vmadd][len $0020][rows 2]`, attr `$20xx`, and a glyph is **8×16 —
top tile `t`, bottom `t+$10`**, the same shape as our half-width set. The
left name is right-aligned, the right one left-aligned, and tiles
`4A`/`4B`/`4C` (+`5A`/`5B`/`5C`) are the **VS graphic** spanning the two
16-column blocks. Measured live on the bracket at f1897, matching the ROM
records byte for byte:

```
$7CE0 .. .. .. .. .. .. .. 01 02 03 04 05 06 07 .. 4A
$7D00 .. .. .. .. .. .. .. 11 12 13 14 15 16 17 .. 5A
$7CF0 4B 4C .. 01 02 03 04 05 06 07 .. .. .. .. .. ..
$7D10 5B 5C .. 11 12 13 14 15 16 17 .. .. .. .. .. ..
```

⚠ **Why it stayed unsolved for four days: every instrument was pointed at the
wrong address.** `VSWATCH` watches VRAM words `$7040-$70DF` and the names are
at `$7CE0`; `dump7f` captured map words `$7000-$77FF`, which also excludes
them. A write watch cannot see them either way — they arrive by DMA — but the
dumps would have shown them at any time. `dump7f` now also captures words
`$7C00-$7DFF`, the font region `$200-$33F`, and logs the four name rows
directly (`NAMEROW` lines).

`$C7:3BBD` **is** the bracket map (script `$DF:A43E` entry [4], codec 2 →
`$7000`) — the blob is real, it simply does not contain the names; the records
overlay it afterwards. The old "baked as Moon-vs-Moon" reading came from
observing Moon vs Moon on a bracket nobody had seeded: both entrants really
are character 0 there, so both records really do hold tiles `01-07`.

⚠⚠ **CORRECTED 2026-08-11 — the bracket work has been aimed at the wrong
sheet, and that is the whole reason the glyphs never appeared.** The plate is on
**BG3**, and BG3 does not read the sheet this patch edits.

Measured from the PPU at the bracket (`probe_p16_screens.lua` now logs it):
mode 1; BG1 tilemap `$7000` chr `$2000`; BG2 tilemap `$7800` chr `$2000`;
**BG3 tilemap `$7C00` chr `$5000`**. The 18 records write to
`$7CE0`/`$7CF0`/`$7D00`/`$7D10`, which is inside BG3's tilemap — so the plate
reads BG3's CHR at word `$5000`, **2bpp** in mode 1. Entry [1] uploads the
**4bpp** BG1/BG2 sheet at `$2000`, which the tree uses and the plate never
touches.

Corroboration, all live: the BG3 sheet (VRAM byte `$A000`) holds 512 2bpp tiles
whose non-blank runs end at **`$0F9`** — exactly the id range the 18 records
reference (`$01-$07` names, `$11-$17` their bottoms, `$4A-$4C`/`$5A-$5C` the VS
graphic). BG3 tile `$01`/`$11` rendered as 2bpp is the kana pair; the `$2000`
sheet's tile `$01` rendered as 4bpp is a *different* glyph. Two sheets; the
records index the other one.

**The real target** is entry **e3** of script `$DF:A43E`: `src $C7:44D1, flag 00,
dest VRAM word $5000` — a **codec-2** blob. Free space is not the constraint:
BG3 tiles **`$0FA-$1FF`** (262) are unused.

⚠ **Entry stride is not fixed.** `$DF:8441` does an extra `inc $28` when
flag ≠ 0, so codec-1 entries are **8** bytes and codec-2 entries **7**. A fixed-7
walk desyncs after the first codec-1 entry and prints plausible garbage for every
entry after it (it did, here, first try). The useful corollary: a codec-1 entry's
`len16` does **not** overlap the next entry, so len and vmadd are free to change.

The two routes out, neither free: **(a)** give the script a 7th entry — codec 1,
our own `sms_lz` stream of just the 36 glyph tiles, vmadd `$5800`, len `$240` —
which needs the script relocated (inserting 8 bytes shifts phases 2 and 3) and
the caller's `lda #$A43E` repointed, but **no codec-2 work at all**; or **(b)**
convert e3 to codec 1 and supply the whole 8 KB sheet, which needs a codec-2
*decoder* to get the vanilla sheet out of the ROM (baking a VRAM dump would be
one moment's measurement promoted to source data).

⚠ **And the instrument that said "codec 1 never runs on the tournament route"
was lying.** `DECOMPWATCH`'s callback opened with `pcall(emu.getState)` and
returned early when it threw — which it always does inside a memory callback
(trap 8). It fired every time and refused to speak. Rewritten to read the direct
page only, and moved to `$80:8DEC`, the single decompression entry point (the
`$DF` runner calls it once, from `$DF:8422`, for every entry; `A & 0xFF` there
picks codec 1 `$80:919F` or codec 2 `$80:8E9A`). It now logs all 11
decompressions on the route, including the repoint taking effect.

**Glyph delivery, as originally planned (this describes the WRONG sheet — kept
because the mechanism it documents is accurate for BG1/BG2):** script
`$DF:A43E` entry [1] is
`codec1 src $C2:27E0 vmadd $2000 len $1400` — the small font, 320 tiles at
VRAM tile `$200`. The blob decompresses to **135 tiles**, so the upload's tail
is whatever the staging buffer already held; the live font region measures 222
non-blank tiles across `$201-$29F` and `$301-$33F`. **Still to measure before
authoring:** the BG CHR base (every "tile `$2xx`" statement so far assumes
`$200`) and which of those tiles are genuinely free. `$C2:27E0` is referenced
four times — `$DF:96C4` (`$2000`), `$DF:9B2F` (`$1000`), `$DF:A446` (`$2000`)
and a codec-2 use at `$C3:BD9E` — so bumping only `$A43E`'s len still holds.

**Earlier same-day status: tournament select names AND the REPORT CARD
labels DONE** — built by `mkpatch16.py` under `SMS_P16_DF=1`, verified
in-emulator (select shows "1P MOON" in the kana's teal; the report card
renders KO TIME/HIT COUNT/DAMAGE/BEST/WIN COUNT in both boxes with numbers
and colors intact; regression 45/45). Implementation notes live as comments
in the builder; the traps paid for on the way: script entry[4] on the select
screen decompresses OVER VRAM $500+ after the sheet upload (the glyph block
therefore sits padded at the $5C0 window), and the kana ink on these screens
is colour 1, not the menu font's 7. Remaining on the $DF side: bracket
names, プレイヤーセレクト header (codec-2 base map), the unidentified fourth
script ($DF:9B27).

Consequences:
* **Win and Tournament share ONE system — the bank-`$DF` screen engine — and
  it is now DECODED (2026-08-06, same session):**
  - Nine screens, each a straight-line caller (`lda #script / jsr $DF:83E1`;
    callers at `$DF:8021/8C41/8CBA/932F/9673/99CB/9C57/A10E/A401`). A script
    has three phases: (1) asset entries `[src24][flag][dest24]` (decompress
    only) or `[src24][flag][vmadd16][len16]` (decompress to `$7F:0000` +
    DMA at `$DF:84C2`); (2) small copies; (3) menu-item descriptors at
    `$7E:0F00+n*$10`.
  - **Two codecs**: flag≠0 blobs go through `$80:8DEC` → `jsr $919F` = the
    familiar `sms_lz` (so the shared big text sheet `$C3:48D0` is
    re-encodable with existing tools); flag=0 blobs (incl. VRAM-dest
    tilemaps) use a SECOND decompressor at `$80:8E9A` — not yet reversed.
  - **Win/REPORT CARD** (script `DF:96BC`): the text lives in a tilemap blob
    `$C8:703C` (codec 2) decompressed to `$7F:0000`, match numbers inserted
    at runtime, uploaded once (`$DF:8534`, `vmadd $7000 len $0800`).
    Rendered from the RAM dump against the `$C3:48D0` sheet (tile = cell&3FF
    − `$A0`) it reads exactly the screen's text. **Edit path that avoids
    codec 2: stub between decompress and upload** (same place the numbers go
    in) rewriting the label cells.
  - **Tournament select rows** are built per frame: 39-word text blocks
    (`[vmadd][len][rows][cells…]`) copied from a pointer table at
    `$DF:8EAC` (blocks `$DF:9000-$9280`, UNCOMPRESSED — trivially editable)
    into `$7F:8000+n*$80`, row positions from `$DF:8EC0`, drawn by the same
    renderer as the Options values. ⚠ Script `DF:9405` is NOT the bracket
    (that is `DF:A43E`) — it is the STORY PRE-FIGHT PORTRAIT screen, found
    the hard way: the sheet-extension build bumped its upload length and the
    maintainer field-reported stray letters on that screen's background
    plane (blank-but-referenced, third instance). Fixed 2026-08-06: only
    the select ($DF:8D24) and report ($DF:96CC) entries are repointed; the
    portrait screen verified clean via the probe's story route. That screen
    also draws セーラー〜 VS 〜 name cells — same family as the bracket for
    a future pass.
  - **The `$C3:48D0` sheet has a full-width Latin alphabet (missing Q, S, Z)
    + two digit sets** — S is needed by nearly every planned string (BEST,
    MARS, VENUS, SAILOR…), so glyph authoring is required either way; the
    plan is to install the half-width A-Z into free tiles of that sheet so
    every `$DF`/`$C3` text screen shares one font and the maintainer's
    longer strings fit.
* The `$C3`-cluster screens (char select, config, ACS) can each get the font
  by the same per-cluster hook Options got, when their text edits are ready.
* ⚠ **Attribution correction:** step 1's "glyphs reach VRAM on the
  button-config screen" was measured on the MAIN MENU — `probe_menu_vram`'s
  route ends at mode-select and its `TRIG=$4000` fires on the menu-entry
  transfer. The verification itself stands (the glyphs do reach VRAM and
  render); only the screen name was wrong. The config screen has NO glyphs
  and no font record of its own.
* Reaching the Win screen headless: vs-COM has **no round clock** (displays
  00, never ticks) and the COM guards jabs indefinitely; **throw damage is
  chip-class and chip never kills** (a throw at 1 HP leaves the victim lying
  at 0 HP forever — an engine state normal play can't produce). What works:
  pin P2 to 2 HP and fish for counter-hits with the 4f jab while the COM
  attacks; strikes underflow-kill normally. HP pins must use the per-A.C.S.
  max (`$104A`), not a constant.

### The ACS prompt bar — attempted, mechanism found, NOT a tilemap job

Attempted 2026-08-06 at the maintainer's "if you feel like it". It is not
map data at all, and two plausible-looking leads were disproved by
measurement before the real one appeared:

* the every-frame DMA `vmadd $5000 len $0800 src $80:1000` is **not** the
  prompt — `$7E:1000` is a 2bpp *drawing buffer* for the stat hexagon, and
  its writers (`$C3:8489` clear, `$C3:85E7`/`$85F8` OR/AND plot) are a
  **Bresenham line renderer** (`$C3:8500-85A5`). That is the wheel graph.
* the prompt is not in BG1's or BG2's live maps either (dumped both).

What it actually is: **a dynamic glyph blitter** — single glyphs uploaded
`$20` bytes at a time to BG3 CHR (`vmadd $5800+`) by the queue-driven
routine at `$80:9583` (WRAM `$1C80` src / `$1C82` bank / `$1C8E` vmadd,
dispatched via `$1C90`), with BG3 map cells pointing at the uploaded tiles.
The glyph bytes come from a staging area at `$7F:DC00+`, which a per-byte
write watch never sees — so it is filled by `mvn` or a WRAM-to-WRAM DMA.
This is the game's variable-text engine (the same class of machinery the
story dialogue would use), which is why the name can be substituted.

**NEXT (a session of its own):** find the filler of `$7F:DC00+` (exec-watch
`$80:9583`'s caller and walk back, or watch `$420B` with a WRAM B-bus
target), which yields the FONT source; then the string encoding and the
name-substitution site. Only then is an English prompt authorable — and it
would want proportional glyphs, since this engine is not tile-grid bound.
Until then the Japanese prompt stays, which the maintainer has accepted.

**Maintainer-supplied strings (2026-08-06) — the full set for every censused
screen:**

* **REPORT CARD:** KOタイム → KO TIME, HITすう → HIT COUNT (HITS if short),
  ダメージ → DAMAGE (DMG if short), 勝ちすう → WIN COUNT (WINS if short),
  ベスト → BEST. With half-width installed the long forms fit; short forms
  are the full-width fallback.
* **Tournament select rows (12 chars):** MOON, MERCURY, MARS, JUPITER,
  VENUS, URANUS, NEPTUNE, PLUTO, CHIBI.
* **Bracket names:** short style — MOON VS MARS etc. (all sailor names
  possible, not just the two shown).
* **プレイヤーセレクト header → PLAYER SELECT.**
* **A.C.S. wheel:** 攻撃 → ATK, 防御 → DEF, ? → DESP, 体力 → HP,
  必殺技 → SP, おちゃめ → SILLY. Prompt line
  「<名前>の好きな能力をあげてね ▶N」 → `RAISE <NAME>'S STATS` — ⚠ the name
  is substituted per selected character, so the prompt edit must preserve the
  name-insertion mechanism (or bake per-character strings).
* **VS config rows:** モード → MODE, 弱パンチ/強パンチ → LP / HP,
  弱キック/強キック → LK / HK, 弱必殺モード/強必殺モード → LSP / HSP,
  ステージ → STAGE, マニュアル → MANUAL (オート removed by p15 in refs).
* **Stage names — DONE in CAPS (maintainer's ruling, 2026-08-06;
  `SMS_P16_STAGES=1`):** CRYSTAL TOKYO, EVENING / SILVER MILLENIUM /
  SPACE-TIME DOOR / KAIOUSHUU PARK / FOUNTAIN PARK, DAY / JUUBAN SHOPPING
  STREET / HIKAWA SHRINE / CRYSTAL TOKYO, NIGHT / FOUNTAIN PARK, NIGHT /
  NAKAYOSHI EDITORIAL DEPT (trimmed to the 24-column budget; the Saturn
  build's SILENT THRONE OF MESSIAH pending its own builder). Mechanism: the
  20 records in bank `$C4` (10 stages x normal/highlight, `$66` apart,
  stride `$CC`, `[vmadd $02E4][len $30][rows 2]`) rewritten centred with
  per-record attrs; comma/hyphen/apostrophe authored as half-width glyphs
  (slots `$5EA-$5EC`); the config screen gets the glyph block via a hook on
  the char-select cluster's first load (`$C3:AF8A` -> stub DMA of an
  uncompressed 64-tile copy to VRAM `$5C0`, ink 1). Verified in-emulator:
  the stage row renders CRYSTAL TOKYO, EVENING, cycles to FOUNTAIN PARK,
  DAY at stage 4, highlight state exercised; regression 45/45.
  ⚠ The stage-row cursor index `$1800` is a WORD index (stage row = 14).

**Values: SOLVED the same day (2026-08-06) — the runtime writer is found and
the records are plain data.** The draw path is `$80:8C43` (JSL): DP `$74/$76`
points at a self-describing record `[vmadd16][len16][rows16][cells…]` in bank
`$C4`, DMA'd row by row to the BG1 tilemap (2 rows × 10 cells at cols 20-29,
`vmadd $00B4` = the COM row, `$0114` = TIMER). One record per value **per
highlight state**, selected by four pointer tables — `$C3:A44F` (COM, shown
state) / `$A45B` (COM, other state) / `$A463` + `$A457` (TIMER likewise) —
indexed by WRAM `$1B14`/`$1B16` = value×2; attr `$1000` = highlighted,
`$0C00` = not. Value order, identified by rendering the cells from the
screen's own text sheet: COM なかよし/やさしい/ふつう/むずかしい (indices
0-3), TIMER あり/なし. BGM/SFX/VOICES are numeric — nothing to translate.
Because the records are **uncompressed** and are the single source for both
the initial draw and every redraw, the translation is an in-place cell edit
of all 12 records (`OPT_VALUES` in `mkpatch16.py`, same `SMS_P16_OPTIONS`
gate; English centred in the 10-cell field, each record keeping its own
attr). Verified: NORMAL/YES on the settled screen AND after a cursor move
(both highlight-state record sets exercised in-emulator); all 12 records
render the intended strings when decoded from the built ROM.
