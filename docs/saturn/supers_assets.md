# supers_assets.md — Super S EXTRA ASSETS (stages / music / etc.) for SMS

> **Doc separation rule (maintainer, 2026-07-30):** everything about integrating
> Super S assets OTHER than Sailor Saturn herself lives HERE. Saturn-the-character
> (moves, boxes, frame data, balance) lives in `saturn_notes.md`. Shared engine/ROM
> facts live in `supers_map.md`.

Status: NICE-TO-HAVE milestone — **feasibility exploration DONE (2026-07-31,
v0.11.5 session)**, port not started. Verdict: **feasible, moderate effort**
(details in §Stage-port feasibility below).

## Inventory targets

- **Stages**: Super S stage list, per-stage assets (BG CHR/tilemaps/palettes),
  stage-select table (SMS side: patch 3's `$E8:0000` default-stage table + the
  `#$0009` random modulus are the known SMS integration points).
- **Music**: track list; SMS side: the charID→track map precedent is
  `vendor/sms-training-mode/asm/charatheme.asm` (9 entries — Saturn's theme needs a
  10th). Super S sound engine vs SMS sound engine compatibility: UNKNOWN.
- **Observed so far** (incidental): the Saturn-vs-Uranus fixture runs on a Super S
  city stage that has no SMS equivalent (see `traces/saturn/saturn_vs_uranus_supers.png`);
  Super S title/menus structurally identical to SMS (`traces/titlevram_supers_700.png`).

## ROM-space policy

Current headroom in the SMS image is ample (~1 MB under the 4 MB HiROM ceiling,
`feasibility.md`). If asset integration ever needs more: the maintainer has
pre-authorized CONSIDERING full story-mode removal (as the "tournament edition" of
SMS does) **but executing it requires EXPLICIT approval per instance** — never
remove story content on space grounds without asking first.


## Super S compressed-asset inventory [P 07-31]

The graphics LZSS + job table decoded for the effect tiles (supers_map §LZSS;
Python decompressor `tools/saturn/supers_lz.py`) covers EVERY compressed asset
in the game — 114 valid entries in the job table ($80:EEF1), enumerated:

| Job idx | Asset | Shape |
|---|---|---|
| 0-27 | **STAGES** — ~9-10 triplets `[tileset→VRAM $2000 (big, 0x15xx-0x2Bxx tokens), tilemap→$0000, tilemap→$0800]` | idx 18-20 = the stage in the Saturn-vs-Uranus fixture |
| 31-47 | char-select / HUD / UI sheets | |
| 48-57 / 58-67 | per-char EFFECT sheets, P1 (VRAM $6A00) / P2 ($7300) | idx 47+id / 57+id; Saturn = 57/67 |
| 77-82 | six ~equal small sheets (win-screen fonts?) | |
| 84-86 | report-card screens | |
| 91-100 / 101-110 | ten per-char sheets × two VRAM dests — **portraits** | id-indexed; useful for the char-select portrait task! |
| 111-119 | more UI / stage-adjacent | |

Everything above is extractable TODAY with `supers_lz.lz_decompress`.

## Stage port — WORKING [P 08-02]

A Super S stage now renders in SMS, on **Sailor Pluto's slot (stage 2, the
space-time door)** — the maintainer's pick, because tournaments only play that
stage by mutual agreement, so it is the cheapest slot to lose whatever we
eventually add. Builder: `tools/saturn/mkstage_port.py` (stacks on any ROM,
`--stacked`); it needs no work on either game's codec, in either direction.

### SMS's asset chain (all traced live)

```
$7E:008E           scene id * 2 (forcing it at $C0:8586 summons any stage)
$E0:017A + id*2 -> scene script: [record ids ... $FF][palette ids ... $FF]
$E0:02DC + k*6     asset record k: [src24][vram16][flag8]
$C0:853D           loader: DP $00 = src, $02 = src bank, $03 = vram, A = flag;
                   flag 0 or >= $7E -> $C0:8E9A (multi-mode codec, dest in WRAM)
                   otherwise        -> $C0:916B (the other codec) then a DMA
$C0:9287/$C0:92AD  the two VRAM-DMA helpers (DP $30-$36 / DP $00-$06)
$E0:0390 + p*6     palette record: [start_colour][src16][bank][count16] — RAW,
                   copied into the CGRAM shadow $7E:0500 by a WRAM gadget
```

Ten stages, each **three consecutive records**: tiles -> VRAM `$2000`, tilemap
-> `$0000`, tilemap -> `$0800`. Scene *i* uses palette ids `1+i` (BG rows 2-7,
0xC0 bytes) and `0x0B+i` (one OBJ row, 0x20 bytes). Stage identification is in
`traces/saturn/stage_g*.png`; **stage 2 is Pluto's door**, and note it shares
its TILESET with stage 1 — only the tilemaps differ — so an override has to be
keyed on the records, never on the tileset address.

### Super S is the same engine

Same shapes, different addresses: scene scripts at `$E0:AB22`, palette records
at `$E0:AC7A`, and its **asset records ARE the LZ job table** (`supers_lz` job
index == record index). Its stage tilesets decompress to 0x1F40-0x5F60 bytes —
all inside SMS's 0x6000 window — and its tilemaps are exactly 0x1000, so a
stage transplants without resizing anything.

### How the port works

* **Art** — the three records are repointed at RAW (already decompressed) Super
  S data in an appended bank, each blob prefixed with a 2-byte length. A stub
  recognises that bank and DMAs it straight from ROM to VRAM, skipping both the
  decompressor and the `$7F` staging buffer.
* **Palette** — SMS's palette blocks are raw already, so Super S's are simply
  written over stage 2's. No hook, no code.

The hook is 7 bytes at **`$C0:8561`** (`cmp #$7E / bcs $8568 / jmp $916B`
becomes `jml stub` + NOPs); the stub reproduces both vanilla continuations
exactly, so every other asset in the game loads byte-for-byte as before.

Three traps, all paid for once:

1. **Hook the loader, not the decompressor.** The first attempt hooked
   `$C0:916B`. That entry is reached from five places in *different accumulator
   widths*; with A 16-bit the stub mis-parses its own code, runs off into the
   appended bank and BRKs into the engine's trap loop (`$C0:FFAE bra *` — worth
   knowing: that address spinning means the game trapped). At `$C0:8561` the
   width is fixed by a `sep #$20` six instructions earlier and only asset
   records pass through.
2. **Come back in the `$80` bank view, not `$C0`.** The loader's continuation
   calls a WRAM gadget (`jsr $0080`, the palette copier), which only exists
   where `$0000-$7FFF` is the system area. Returning with PB=`$C0` hung the
   load right after the third stage asset. For the same reason the stub cannot
   end in its own `rts` (that keeps PB) — it jumps to the vanilla `rts` at
   `$80:92AC`.
3. **Don't borrow `$C0:9287`.** That helper takes its source from DP `$30-$36`,
   and the bank byte `$36` is shared state the vanilla path never re-sets (it
   is `$7F` for the whole load). Writing our bank there sent the NEXT vanilla
   asset's DMA into the appended bank. The stub programs the DMA registers
   itself and touches no DP state.

### Status and what is left

Verified in-emulator: the ported stage renders with correct art and palette,
stages 0/1/5 are unchanged on the same ROM, and the regression suite is 42/42.
Source stage is one constant (`SUPERS_SCENE`, default 1 = the moonlit terrace
with the Elysion palace skyline).

Remaining polish, all in the same family: **the per-stage BG CONFIG is still
SMS's** — mode, scroll/parallax registers, colour-math and windows, plus the
ground line. That is visible as a magenta band on the left of the ported stage,
left over from how SMS dresses the space-time door. Music also stays SMS's
(a real track port is its own project).

## Report-card portrait — located [P 08-01]

Goal: show Saturn's portrait on the post-match REPORT CARD (she currently shows
the shell character's, since the card reads the SELECTED char id, not the
in-match struct id — confirmed: poking the struct changes nothing).

Findings (probe `tools/saturn/probe_cardportrait.lua`, VS flow → two KOs →
card detected by `$1E05==0xFF && $0070==0`, VRAM dumped and diffed between two
different winners):

- **Portrait tiles = VRAM `$0000-$087B` (tiles `$000-$043`, ~2.1 KB)** — the
  only meaningful per-winner difference on the card (a second small region,
  `$50E0-$51BE`, is the label strip).
- It is **NOT DMA'd**: during the card build the only DMAs are the in-match cel
  streams and the two win-name-plate transfers we already hook. The portrait
  arrives via direct `$2118` writes from **`$9F:84E8`** — i.e. SMS's OWN
  decompressor (bank `$9F`, the LZ-cousin whose backref idiom was spotted at
  `$1F:95C2`/`$1F:A08F`) streaming decompressed data STRAIGHT INTO VRAM, with
  no `$7F` staging buffer. That is why the effect-tile "staging override"
  trick does not apply here.

### The card's portrait chain — DECODED [P 08-01]

    $C0:A1C6  jsl $9F:964F              ; report-card screen routine
      $9F:9670  lda #$96BC / jsr $83E1  ; shared card art (same for every winner)
      $9F:944D                          ; per-player portraits
        reads $1000 (P1) and $1080 (P2) — at card time these hold a portrait
        CODE, not the struct id: Moon 0x06, Jupiter 0x0C, Chibimoon 0x10,
        Uranus 0x16 (measured)
        $9F:9487  sec / sbc #$0006 / (A + A>>1) -> Y     ; 3-byte stride
                  lda $94C2,Y / lda $94C3,Y -> $00/$01   ; 24-bit source ptr
                  lda #$0000 / jsl $80:8DEC              ; upload
    Table: **`$9F:94C2`, 3-byte pointers, 9 real entries** ->
    `$C8:32DA, 38BA, 3E28, 43EA, 4A38, 509D, 58DB, 5F52, 6664`
    (entry index = (code - 6) / 2; entries 9+ are not table data).
    Second portrait goes to VRAM `$0800` (word) via `$03` = 0x0800 in `$944D`.

**Blocker for the repoint route:** those streams are compressed in **SMS's own
format**, which is NOT the Super S LZSS (`supers_lz.lz_decompress` fails on
`$C8:32DA`). So repointing needs Saturn's portrait encoded in SMS's format,
i.e. RE the bank-`$9F` decompressor enough to write an encoder — a
literal-only encoder is likely enough if the format has a literal-run token
(the Super S one does). Otherwise the agreed fallback: let the vanilla upload
run and blit our tiles over VRAM `$0000` afterwards (raw tiles, no encoder
needed).

Also worth noting: because `$944D` keys off `$1000`/`$1080`, a Saturn winner
currently shows the SHELL character's portrait — the same shell-id mechanism
that makes the rest of the port work; whichever route we take needs the
per-player Saturn flag consulted at that point.


## Card portrait — plumbing DONE, art conversion REMAINS [P 08-01, v0.12.0]

Implemented behind `SATURN_PORTRAIT=1` (OFF in shipped builds):

- Wrapper stub at `$EE:C900` replaces the loader call at `$9F:949F`
  (`jsl $80:8DEC`). It stashes the destination from DP `$03` **before** calling
  the loader (the loader uses `$00-$0E` as workspace — reading `$03` afterwards
  gives garbage, which cost one bring-up cycle), runs the vanilla upload, then
  for a flagged Saturn blits her tiles over the same VRAM window
  (`$0000` P1 / `$0800` P2) with a forced blank around the transfer.
- **Proven working**: after the blit, the card's VRAM window matches her
  decompressed Super S portrait **2080/2080 bytes**.

Why it is not enabled: **the two games' portraits are different artwork in a
different tile arrangement.** Cross-check: none of Super S's ten portrait jobs
matches SMS's own Uranus card art above noise (best 292/2144 ≈ 13%), so
dropping her Super S portrait into SMS's card window renders scrambled.

### Art conversion — SOLVED via capture [P 08-01]

The portrait is **not a tilemapped background**: it is a fixed composition of
**31 SPRITES** (16x16 and 8x8, OBJ tiles `$00-$43`, OBJ palette 0 = CGRAM row
8) at hard-coded screen positions, identical for every character — only the
tile pixels and palette change. Read the composition straight out of OAM on a
card frame (`probe_cardsaturn.lua` dumps OAM/VRAM/CGRAM/PPU regs).

`tools/saturn/mkportrait.py` does the conversion:
  * `--render` redraws the composition from VRAM+OAM+CGRAM dumps — used to
    validate the model (it reproduces SMS's Uranus portrait exactly);
  * `--convert` samples a 1:1 capture through that same composition, quantises
    to 16 colours and emits tiles at the matching tile numbers plus a palette.
Source art: the maintainer's 1:1 Mesen capture of Super S's card,
`mockups/saturn_win.png`. Both games place the portrait at the same screen
position, so no sampling offset is needed (an auto-align pass was tried and
rejected — the patterned lilac background defeats a "not-background" cue and a
dark-pixel cue drags the frame onto her hair).

**Status: her portrait renders correctly on SMS's card** (`SATURN_PORTRAIT=1`;
see `mockups/saturn_card_ingame.png`). Composition, pose and glaive are right.

### The sprite-list selector — SOLVED [P 08-02, v0.12.1]

**The composition is PER-CHARACTER, not universal.** Layout census (sprite
count, bounding box), measured by dumping OAM at the card for several winners:
`Moon 18 / 66x64`, `Mercury 26 / 63x64`, `Mars 16 / 64x64`,
`Uranus 31 / 71x72`. Each character's portrait ships with a sprite layout
shaped to that character's silhouette, so feeding Saturn's art through the
shell's layout CLIPS everything outside his outline — exactly what the
maintainer saw (lower-left hair/face and the glaive's Y-piece missing). Uranus
is already the LARGEST of the four, so re-shelling cannot fix it: she needs her
own list.

**Where the list comes from.** It is not a stored literal (which is why
grepping for `CBEC`/`C595` found nothing) — the renderer reads it out of the
portrait OBJECT's own fields, every frame:

```
$C0:9E86   lda $64,X / sta $12 / lda $66,X / sta $14     ; list pointer -> $12/$14
$C0:9E8E   lda [$12] / sta $00 / inc $12                 ; count byte
           ... anchor x -> $01, y -> $03, tile/attr base #$3000 -> $06
$C0:9EA6   lda $66,X / pha / plb                         ; list bank -> DB
$C0:9EAE   jsr $9B17 (normal) or $9BCB (X-flip)          ; the card uses X-flip
```

At the card, the object is the P1 struct slot itself: `$1000 +0x00 = $16`
(the portrait code, not the char id), `+0x64/65 = $CBEC`, `+0x66 = $9F`.

**Record format** (6 bytes each, after a 1-byte count), decoded from the
emitter at `$C0:9BCB`:

| byte | meaning |
|---|---|
| 0 | x offset, signed — used by the NORMAL emitter (`$9B17`) |
| 1 | x offset, signed — used by the X-FLIP emitter (`$9BCB`), the card's |
| 2 | y offset, signed |
| 3 | unused (padding — the emitter never reads it) |
| 4 | tile number |
| 5 | attribute |

Screen position = anchor + offset, with the card's anchor at x=`$34`, y=`$78`.
Bytes 4-5 are read as ONE word (`attr<<8 | tile`); bit `$0800` (attr bit 3) is
a **size flag** that the emitter consumes — it sets the OAM high-table size bit
and is stripped (`and #$F7FF`) before the caller's base (`#$3000` = priority 3,
palette 0) is added. So vanilla's `$48` = X-flip + 16x16, and 8x8 sprites want
`$40`. Offsets that put a sprite off-screen are skipped, and the emitter stops
at OAM slot 128 (`cpx #$0200` at `$C0:9C63`).

**Her list** (`tools/saturn/mkportrait.py --card`): her portrait occupies
x 8-96 / y 40-120 in the capture — bigger than the vanilla box (x 19-90 /
y 48-120), which is precisely the clipping. We keep the Super S screen
coordinates 1:1 (both games' cards share the layout) and rebuild the
composition out of **8x8 sprites**, which need no tile-grid alignment, so only
cells that actually contain art cost a sprite AND a tile: **67 sprites / 67
tiles** out of 110 candidate cells. That fits both budgets (OAM stops at 128;
P2's portrait starts at tile 128) and peaks at 11 sprites per scanline, well
under 32. The background is masked by flood-filling the card's PATTERNED
lavender backdrop inward from a padded border — by connectivity, not by colour
match, so pixels inside her that share a colour with the pattern survive.

**The hook** (`SATURN_PORTRAIT=1`): `$C0:9E86`'s 8 bytes become `jsl $EE:CA00`
+ 4 NOPs. The stub replays the displaced loads, then substitutes our own list
when *both*: the pointer being loaded is `$9F:CBEC` (that identifies the report
card unambiguously — nothing in-match can trip it), and the **winning player's**
Saturn flag (`$7F:F100`/`F101`) is `$A5`.
`$C0:9EA6`'s `lda $66,X` becomes `lda $14` (same 2 bytes) so the data bank
follows the substituted pointer instead of re-reading the object field.

> **WRAM-mirror trap (cost a full debug cycle).** `$14` becomes the emitter's
> DATA BANK, and the emitter writes the OAM shadow with plain absolute stores
> (`sta $0200,X`). Bank `$EE` is `$C0-$FF` = pure ROM with no WRAM mirror, so
> every one of those stores went to ROM and the portrait vanished COMPLETELY —
> the list was being read correctly the whole time. The fix is to hand the
> emitter the `$80-$BF` alias of the same ROM (`$AE:8000-$FFFF` == `$EE:8000-$FFFF`).
> Vanilla gets this for free by living in `$9F`. Any future data handed to a
> vanilla routine that stores through DB must use the alias.

> **The card carries no player identity.** It builds the winner's portrait
> through the `$1000` slot and uploads it to VRAM `$0000` *whoever won* — so
> both the obvious keys (the object slot `X`, and the upload destination the
> tile wrapper used) are constants, not the player. Keying on either shows
> Saturn's portrait on a card won by the OTHER player whenever that player is
> Uranus, our shell — reproduced: "2P WIN" over Saturn's face in a
> Saturn-vs-Uranus match. The winner is **`$7E:1E14`** (`1` = P1, `2` = P2),
> found by diffing all 8 KB of WRAM at the card between a P1 win and a P2 win
> (65 bytes differ; `$1E14` is the one that reads as a player number). Both
> hooks — tile blit and sprite list — now gate on it, so they can never
> disagree.

### The palette — SOLVED [P 08-02, v0.12.1]

The card's portrait colours are **CGRAM row 8** (colours 128-143 = OBJ palette
0), and the card is the only thing on screen using OBJ palette 0 — verified by
dumping OAM at the card: the 67 visible sprites are all ours, nothing else to
recolour.

CGRAM is never written colour-by-colour during the card: the engine DMAs the
**whole 512-byte shadow at `$7E:0500`** into CGRAM every frame (`$80:849F`,
also `$80:8216`), so the shadow is the only lever. Row 8 lives at `$7E:0600`.

The trap: **a one-shot copy does not stick.** Seeding `$7E:0600` from the
card-load wrapper leaves only a couple of bytes alive by the time the card is
on screen, and a write-callback watch on `$7E:0600-060F` catches **no** foreign
writer — because the engine's own refill is itself a transfer, invisible to
write callbacks. Rather than hunt it, we re-seed from the sprite-list stub,
which the renderer calls **once per drawn frame** while the portrait is up and
which already knows it is Saturn's card; it runs before vblank, so it always
wins the race. Confirmed: CGRAM `$100-$11F` at the card equals our palette
byte-for-byte, and it is the ONLY part of CGRAM that differs from the same
build with the palette hook removed (30 of 512 bytes).

Art palette: 16 distinct colours in her portrait, one quantised away
(15 + transparent), so the card is effectively colour-exact.

**Status: DONE.** `SATURN_PORTRAIT` is ON by default from v0.12.1; the whole
chain (tiles, layout, palette) is per-player flag-gated, so a card won by any
other character is byte-identical to vanilla.

#### Regenerating the art

```
python3 tools/saturn/mkportrait.py --card mockups/saturn_win.png \
    build/saturn/portrait_list.bin build/saturn/portrait_saturn.bin \
    build/saturn/portrait_saturn.pal
```
Input is a 1:1 (256x224, no scaling/filtering) capture of Super S's report
card. `--render` redraws a composition from VRAM+OAM+CGRAM dumps and is what
validated the model in the first place (it reproduces SMS's Uranus portrait
exactly). Both games place the card at the same screen coordinates, so the
capture is sampled with no offset.

#### Known limits

- Only the **P1** portrait slot is styled; if a future screen ever shows two
  card portraits at once, the per-frame palette re-seed would impose Saturn's
  row 8 on both.
- The hook at `$C0:9E86` is on the generic sprite-list renderer, so the added
  compare chain runs for every listed object in-match. It exits on the first
  compare (list bank != `$9F`) — order of 1% of a frame.

