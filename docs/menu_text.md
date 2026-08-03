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

## Open

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
