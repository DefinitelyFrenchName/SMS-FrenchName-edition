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

### Field fixes [P 08-02]

Three problems reported from play, two fixed:

1. **Sprites behind the stage** (only the fighters' upper bodies visible).
   Tilemap entry bit `$2000` is the per-tile priority bit, and Super S leans on
   it far harder than SMS: this stage sets it on 336 and 948 of 2048 entries,
   where SMS's own stage 2 uses 0 and 192. Under SMS's setup those tiles draw
   in FRONT of the fighters. The builder now strips the bit from ported
   tilemaps (`STRIP_PRIORITY`), which is what a fighting-game background wants.
2. **Continuous drift and a wrong resting offset.** The per-stage scroll
   routine is chosen through a pointer table at **`$C0:B32B`**:
   `+$00 $C0:B40A` (BG1 = camera, BG2 = camera/4), `+$02 $C0:B42F` (the
   mirror), `+$08 $C0:B454` (camera minus a counter decremented ~6/frame — the
   space-time vortex). Stage 2 selects the vortex, and the port inherited it.
   The builder repoints that entry to `$B40A`; measured safe, because stages
   0/1/3 keep their exact previous scroll (only stage 2 selects `+$08`).
   > The per-stage SELECTOR byte is still unlocated — a 10-byte table at
   > `$C0:B317` looks exactly like it and its values line up with the measured
   > per-stage behaviour, but patching it changes nothing, so the real index
   > lives elsewhere. Repointing the shared routine entry is equivalent here
   > only because a single stage uses it.
3. **The two tilemaps were on SWAPPED PLANES** — fixed. Both games store their
   stage tilemaps at the same VRAM addresses (`$0000` and `$0800`), so a
   straight copy looked right; but the games' BG tilemap-base registers are
   reversed, so Super S's far map landed on SMS's near plane. That one fault
   produced three symptoms at once: the sky/horizon drawn IN FRONT of the
   palace, the far layer framed wrong (it was being scrolled at the near
   plane's rate), and the apparent width change. The builder now swaps the two
   tilemaps between planes (`SWAP_MAPS`), after which the stage renders with
   sky behind, palace in front of it, and fighters in front of everything.

   *(Superseded diagnosis, kept because the reasoning was wrong in an
   instructive way: with the vortex removed the palace went out of frame and
   the offline renders — palace at map rows 0-10, floor at rows 9-13 — made a
   VERTICAL offset look like the cause. It was not; the plane assignment was.
   A horizontal re-framing knob `MAP1_SHIFT` remains but is unused at 0.)* With the vortex gone
   the palace is out of view. Rendering both tilemaps offline shows why: the
   palace occupies map ROWS 0-10 while the near layer's floor is rows 9-13, so
   it is the far plane's VERTICAL offset that is off, not the horizontal one (a
   horizontal rotation was tried and did not help; the knob `MAP1_SHIFT`
   remains for when it is useful). The fix needs BG2VOFS measured
   (`$210E`/`$2110`) and then either a row rotation of the far map or a small
   custom scroll routine in the appended bank.

Net: the stage is stable and correctly layered, and looks like a clean moonlit
terrace — with its palace skyline still to be brought back into frame.

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



## #43 — the ported stage's vertical slide: DIAGNOSED and FIXED [P 08-03]

Field report: on the ported stage only, during a jump the shadows and the
opponent slide toward the bottom of the screen and return on landing. Two earlier
sessions failed to reproduce it — the character never jumped — so nothing had
ever been measured. It has now been measured on the RIGHT scene
(`STAGE=2 … probe_sms_stagejump.lua`, which forces `$7E:008E` at `$C0:8586`; the
first run measured scene `$00` while believing it had the ported one), root-caused,
fixed, and the fix verified.

### The scroll model (measured, not inferred)

There is a scroll block at `$7E:0A00`:

    $0A00/$0A02   camera x / camera y (16-bit, signed)
    $0A18/$0A1A   BG1 h / v      $0A1C/$0A1E   BG2 h / v
    $0A20..$0A27  the remaining two pairs (BG3/BG4 — the HUD planes here, held at 0)

A per-stage routine fills that block each frame, selected through the pointer
table at `$C0:B32B`:

    $C0:B40A (stage 0)   BG1 = camera/4 on BOTH axes, BG2 = 0
    $C0:B42F (stage 1)   the mirror of it
    $C0:B454 (stage 2)   BG1 = camera 1:1 on both axes, BG2 = camera − a vortex counter

**Objects are placed at the FULL camera.** Proven with the animation controlled
for: holding the standing dummy's idle pose constant (act/step/tick/frame all
equal) her top sprite Y is 89 at `camY = 0` and 100–101 at `camY = −11/−12` —
`topY + camY` is constant at +89 across the whole jump. So anything a plane does
*not* do with the full camera, everything standing on that plane slides against.

### Root cause

The port replaced stage 2's vortex routine with **stage 0's** (`$C0:B32F`:
`B454` → `B40A`) to kill the vortex's continuous horizontal drift. That trade
also dropped the VERTICAL from 1:1 to a quarter rate. Measured on the ported
scene, at the apex of a jump:

    camera y      −12 px
    objects       −12 px   (fighters, shadows: 1:1)
    BG1 (ground)   −3 px   (camera/4)
    BG2 (sky)       0

Nine pixels of disagreement, appearing over ~20 frames and undone on landing —
exactly "slides toward the bottom of the screen and returns".

Vanilla stage 0 does the identical thing (same routine): its trace, its OAM and
its WRAM globals are **byte-identical** to the ported stage's across the same
jump. It is not reported as a bug there because that stage's ground is a flat
grass field with no feature at the fighters' feet, while the ported stage has a
hard perspective floor line exactly there. So the port did not invent the
behaviour; it inherited it onto art that shows it.

### Fix

`mkstage_port.py`, `GROUND_TRACKS_CAMERA = True` (default): instead of
repointing `$C0:B32F`, the **vortex routine's body at `$C0:B454` is rewritten in
place** (35 bytes, code region ends at `$B4C0`; its HDMA data table starts at
`$B4C1` and is untouched) with B40A's horizontal treatment and stage 2's own 1:1
vertical:

    rep #$20 / lda $0A00 / sta $0A24 / lsr / lsr / sta $0A18 / sta $0A20 / stz $0A1C
             / lda $0A02 / sta $0A1A  ← the fix: BG1 v = camera, 1:1
                         / sta $0A22 / sta $0A26 / stz $0A1E / rts

Only stage 2 can see it: the pointer table contains exactly one `B454` entry,
the per-stage selector maps a single stage onto it, and stage 2 demonstrably
executes it (rewriting the body changed the ported stage's scroll). The pointer
at `$C0:B32F` is now left alone.

**Verified.** BG1's vscroll follows camY 1:1 through the jump; the background's
measured pixel shift goes from +3 to **+11**, equal to the sprites' +11 (frames
118 → 145, `traces/saturn/stagejump_{cam2,fix2,ship2}_*.png`); scene `$00` on the
same ROM is byte-identical before and after, so no other stage moved; regression
**57/57 ALL PASS** on `SailorMoonS_REFsaturn_v0.13.3-hidden-stage.sfc`. The
camera clamps at −12 px however high the fighter goes, so the 1:1 ground can
never scroll far enough to expose the tilemap's wrap.

### Round 2 — the PALACE rate (field, 2026-08-03)

The slide was confirmed gone, with one thing left: the palace. Two captures at
the same jump apex, Super S vs ours, showed Super S's palace shifted a fraction
of the way while ours moved with the ground — "the crescent on the central dome
becomes visible but not entirely, and an extra light gray band appears above the
ground".

Measured both, per band, between rest and apex (`shift` correlation on the
probe's own screenshots):

| band | Super S | v0.13.3 | v0.13.4 |
|---|---|---|---|
| palace / dome | **+4** | +11 | **+3** |
| ground / plaza | ~0 | +12 (register-exact) | +12 |

**How Super S does it: per SCANLINE, not per plane.** `probe_supers_stagejump.lua`
(same measurement, Super S's own VS flow, scene forced at `$80:8530`) shows the
whole stage on ONE plane, and at the apex `HDMAEN` gains **channel 5 feeding
`$210E` (BG1VOFS) from a table at `$00:0A50`** — a per-scanline vertical scroll
that gives the palace band and the ground band different offsets on the same
tilemap. At rest that channel is absent. SMS has no such machinery on its own
stages (a vanilla stage shows `HDMAEN=06`, two dummy channels), so the port
cannot inherit it.

**What we do instead: split by PLANE.** The data allows it because Super S marks
the ground — and only the ground — with the per-tile priority bit, in a clean
band of whole rows (map rows 21-25, full width). So `PLANE_SPLIT` in
`mkstage_port.py` cuts the source into:

* **BG1 = the ground alone**, at camera **1:1** — the fighters stay planted,
  which is what the maintainer asked for and is better than *either* original
  (Super S's own ground does not move at all).
* **BG2 = sky + palace**, at camera **/4** — Super S's rate for that band.

Horizontal is camera/4 on both planes, so the two can never drift sideways
against each other. This supersedes `MERGE_GROUND` + `SWAP_MAPS`.

**The trap it cost:** the palace is in the SECOND source map, not the first, and
the first (sky) has no blank cells — so a "fill the gaps" merge silently threw
the entire palace away and the stage rendered as bare sky with one dome at the
edge. The second map now wins wherever it has a tile. Ordering matters more than
it looks: nothing errored, the build was byte-consistent, and only a screenshot
caught it.

Verified: palace +3 vs Super S's +4, ground 1:1 by register, composition correct
at rest on two builds, regression **57/57** on
`SailorMoonS_REFsaturn_v0.13.4-hidden-stage.sfc`.

### Round 3 — CORRECTED: the scene script's tail (2026-08-03)

Round 3 as first written is **wrong** and the build it produced (v0.13.5) broke
scrolling speed and input in the field. It is superseded by this, which is
simpler than anything before it. The maintainer's steer is what found it: **SMS
already ships this stage** — scene 1 is its own Silver Millennium, the same
palace over the same plaza — so instead of reasoning about what SMS "cannot do",
read what it already does.

**SMS's own Silver Millennium composes the stage exactly like Super S:**

    BG1 priority 0   sky          BG1 fixed (h=0, v=0)
    BG2 priority 1   palace       BG2 camera/4 both axes
    BG1 priority 1   ground

with the fighters drawn **over** the priority-1 ground, boots and shadows
intact. Which contradicted the port's founding assumption — that a priority-1 BG
tile must cover an OBJ-priority-2 sprite — so the assumption was measured
instead of assumed: on SMS's own stage 1 the fighters are at **OBJ priority 3**;
on stage 2, the slot the port targets, they are at **2**. Nine of ten SMS stages
use 3. Stage 2 is the only one that does not, and it is the one we build on.

**Where that comes from.** The scene script is not two lists but four parts, read
at `$C0:85C8-$85FC`:

    [record ids .. FF][palette ids .. FF][third list .. FF][$6F][$8F][$A2]

`$8F` is the sprite-attribute byte, mirrored into each player's `+0x08`: `0x18`
= fighters at OBJ priority 3, `0x10` = priority 2. Stage 1's tail reads
`a0 18 0a`, Super S scene 1's reads `a0 18 00`, stage 2's reads `50 10 0f`. The
port copied records and palettes and never carried the tail — so the ported art
ran under the one configuration in the game that puts the fighters *below* the
background's priority tiles.

That single byte is the whole saga. At priority 2 the castle covered the
characters (the first field report), so the port stripped the priority bits;
stripped, three layers had to share two depths, so the palace could not have its
own parallax without either burying the sky or blacking out its own edges — and
every fix since has been paying interest on that.

**The port now carries `$8F` (0x10 -> 0x18) and does nothing else clever:**
priority bits kept verbatim, no layer merge, no plane swap, no tile compositing,
no rewritten scroll routine. The stage-2 scroll entry is simply repointed at
**`$C0:B42F`** — the routine SMS's own Silver Millennium uses.

Only `$8F` is copied. Porting the third list and the other two tail bytes as
well **hangs the round load** (measured: the match never starts) — they are
SMS-side ids, exactly like the record and palette ids, which is why those have
always been kept as SMS's with only their data repointed.

Acceptance, against SMS's own version of the same stage:

| | SMS scene 1 | our port |
|---|---|---|
| BG1 (sky+ground) | `0,0` fixed | `0,0` fixed |
| BG2 (palace) | `16, camera/4` | `16, camera/4` |
| sprite priority | 3 | 3 |
| black pixels over the palace | 270 | 270 |

Regression 57/57 on `SailorMoonS_REFsaturn_v0.13.6-hidden-stage.sfc`.

Note what this also means: making the ground track the camera 1:1 (v0.13.3/4)
was a deviation from **both** originals — SMS's own stage keeps its sky+ground
plane completely still during a jump and drifts only the palace. That code is
gone.

### What the earlier rounds got wrong, and why

* **"A priority-1 BG tile always covers the fighters."** True only at OBJ
  priority 2, which is a per-stage setting, not an engine constant. Measuring
  one stage and generalising cost four rounds of increasingly clever
  workarounds — merging layers, splitting planes, compositing tiles — all of
  them working around a byte.
* **Reading the game's own data beats reasoning about its limits.** Every
  question in this task — layer split, priority use, scroll rates, sprite
  priority — was answerable by dumping SMS's own version of the same stage.
* **A 64x32 tilemap is TWO 32x32 screens** (right half at +0x800), not 64-entry
  rows; reading it wrong made three analyses of these maps contradict each other.
  `cell_off()` documents it.

### Still open, deliberately: the HORIZONTAL rate

Walking is the same question on the other axis, and it was measured too: over a
58 px walk the camera moves ~28 px and BG1 moves ~7 (camera/4), so the fighters
slide over the ground horizontally as well. That is *also* vanilla stage-0
behaviour, it is not in the field report, and it is far less legible on a
repeating floor pattern — so it is left alone. Making it 1:1 is a one-word change
(drop the two `lsr`s), and it is what vanilla stage 2 did. Maintainer's call.

### Probe traps this cost, all worth remembering

1. **`$01FA == $80` does not mean the players can act.** The round is live but the
   fighters are still in their entrance (act `$22`), and even at neutral the pads
   do nothing while the "GO!" banner is up. Waiting ~120 frames past neutral is
   what finally produced a jump. The old note that "p1y never leaves `$00C0`" was
   this, not an input fault: the pad autopoll and the engine's own held word both
   read `$0800` (Up) the whole time while nothing happened.
2. **BG scroll registers cannot be shadowed.** `$210D`-`$2114` are write-only and
   a write-callback approach captures *nothing at all*. Mesen exposes the real
   values — but `emu.getState()` returns a **FLAT table with dotted string keys**
   (`ppu.layers[0].vscroll`), not nested tables, so indexing it as nested yields
   nil silently.
3. **A nil in a step function fails invisibly.** The logging step threw on that
   nil, and the probe reported "done" having written only its header — which
   looks exactly like "the game did nothing". Read defensively in step functions.
4. **Do not measure a moving character against a moving background by pixel
   correlation.** The first pass "showed" sprites at +11 and background at +3 on
   BOTH stages and nearly buried the finding, because the standing dummy's idle
   bob is worth ±8 px of apparent shift. The measurement only became evidence once
   it was taken from OAM with her animation state held equal.
5. **The layer that fails to track is not always the one that was re-cut.** The
   working hypothesis was that the port's layer re-cut had left the ground on a
   plane that does not follow the camera. It had not: the ground is on BG1, the
   only plane that follows at all. The fault was the RATE, inherited from a
   routine borrowed off another stage.

## Porting the other Super S stages (2026-08-03)

`SUPERS_SCENE` is now an environment variable, so one build per stage:

```bash
SUPERS_SCENE=9 python3 tools/saturn/mkstage_port.py "$CLEAN" build/saturn/sms_stage_s9.sfc
```

Every Super S scene, identified by capture (`probe_supers_stagejump.lua` per
scene, contact sheet), with the SMS scroll routine that matches what Super S
itself does to the two planes — measured, not guessed:

| scene | stage | Super S scroll | SMS routine |
|---|---|---|---|
| 0 | **Dead Moon Circus, day** | BG1 camera/4, BG2 fixed | `$C0:B40A` |
| 1 | **Silver Millennium** (ported) | BG1 fixed, BG2 camera/4 | `$C0:B42F` |
| 2 | space-time door | — | (SMS has its own) |
| 3 | harbour at sunset | | |
| 4 | fountain / park | | |
| 5 | game centre | | |
| 6 | shrine | | |
| 7 | ice crystals | | |
| 8 | **Silent Throne of the Messiah** | BG1 fixed, BG2 h drifts +1/frame | keep SMS's **vortex** `$C0:B454` — the only stock routine that drifts a plane |
| 9 | **Dead Moon Circus, night** | BG1 camera/4, BG2 fixed | `$C0:B40A` |

All three new stages carry `$8F = 0x18` in their own script tails, so the port's
tail copy gives them OBJ priority 3 with no extra work, and their priority bits
go in verbatim.

**Only `$8F` may be carried across.** `$A2` was tested and it **hangs the round
load** (the match never starts) exactly as the third list does — both are
SMS-side ids, like the record and palette ids. So a ported stage inherits SMS
stage 2's `$A2`/third-list configuration, whatever those select.

Verified: all three load and render, and the day stage is **pixel-identical** to
Super S's own frame (mean sky colour equal, and the full CGRAM differs only in
the HUD and OBJ rows — i.e. the fighters, which differ by cast).

### Still open on these

* **Which SMS slots to sacrifice.** All three test ROMs replace stage 2 so they
  can be looked at without deciding; shipping more than one needs a slot each.
* **BGM.** Not yet answered. The obvious probe cannot answer it: forcing
  `$7E:008E` at `$C0:8586` changes the stage *after* the music has been chosen,
  so every forced-stage run plays the same track. Answering it means finding
  where the scene id is chosen in the first place and whether the music id is
  derived from the same place.
* **Stage names.** Two Silver Millenniums now exist; the maintainer wants the
  ported one marked (e.g. "light"). Where SMS displays a stage name at all is
  not yet established.

### Add a stage, or swap one? (measured 2026-08-03)

**Swapping is data-only; adding is a project.** Evidence:

* The scene pointer table at `$E0:017A` is **exactly 10 entries** and the scene
  scripts start immediately after it, at `$018E` — the same "table sized to the
  roster, followed straight away by live data" pattern as the nine-wide
  character tables (`memory_and_shell.md`). An 11th pointer overwrites scene 0's
  script, so it means relocating the table and repointing its reader.
* The asset records the stages use are `0-29` (three per stage, contiguous);
  records `30+` are already in use for other assets (`vram $30E0/$C0E0`). A new
  stage needs three more record slots, so the record table would have to grow or
  move too.
* And the stage is **chosen at character select** — `$7E:008E` is written from
  `$C0:A47A` during that phase — so an 11th id would also need that selection
  code to be able to produce it.

So a swap costs nothing but the slot; an addition costs a table relocation, a
record-table change, and a change to how a stage is picked. Worth revisiting
only if more than one Super S stage is wanted.

### Stage names

The maintainer reports the stage name is printed at the bottom of the
**button-mapping screen**, between character select and the fight — the same
screen `docs/menu_text.md` inventories for the translation patch. The harness's
VS flow does not pass through it (it pokes the character ids and the transition
fades straight into the match), and the blind Start-mash flow that *did* reach
it is 1P-vs-COM, whose capture shows no name. So the name table is not located
yet; reaching that screen in the right mode is the next step.

Note the naming problem only exists for ONE of the four candidates: replacing
the space-time door with Super S's Silver Millennium puts two Silver
Millenniums in the game (SMS's own is stage 1), which is what needs the "light"
marker. Dead Moon Circus or the Silent Throne clash with nothing.
