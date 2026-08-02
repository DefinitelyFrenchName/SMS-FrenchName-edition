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

## Stage-port feasibility [P 07-31]

**Super S side: solved.** Assets enumerate + decompress cleanly (above).
Remaining per-stage unknowns are the CONFIG tables (BG mode/scroll planes,
ground line, palette source, music id) — engine tables, findable by diffing
two stage loads with the LZJOB/DMA tracer (probe_staging_dump2 pattern).

**SMS side: the loader differs.** SMS does NOT carry the Super S decompressor
(no `JSL $00:00C8`, no MVN gadget): its match-load path decompresses manifest
payloads via `$C0:916B` into `$7E:6A00` AND stages `$7F:0000` DMAs from a
different resident routine (backref idiom found in bank $DF — same family,
format unverified). Two viable injection routes:

1. **Staging-override (RECOMMENDED — proven pattern):** exactly how Saturn's
   effect tiles ship: hook the stage-load DMA kick, override the `$7F` staging
   with RAW decompressed data from appended banks. No SMS-format re-encode, no
   SMS-decompressor RE. Cost: raw size (~16-24 KB/stage) — even the combined
   REFsaturn ROM has banks $F9-$FF free (~450 KB) = room for every Super S
   stage uncompressed.
2. Native-format conversion: RE the SMS decompressor (likely an LZSS cousin)
   and re-encode at build time. Cleaner, more work, zero extra footprint.

**Stage select/config integration:** the stage id feeds per-stage engine
tables (sizes/counts unknown) — widening to extra ids is the same
roster-widening surgery done five times already (boxes/poses/cels/charsel/
win screen). Known SMS entry points: the VS-config stage select, patch 3's
default-stage table + `#$0009` random modulus.

**Music:** separate SPC-side domain, unassessed. Fallback that costs nothing:
ported stages reuse an SMS track. A real track port (sequence + samples)
would be its own exploration.

**Effort estimate:** proof-of-concept (ONE stage, art via staging-override,
SMS music, reachable by replacing an existing stage id) ≈ 2-3 focused
sessions; full integration (own stage-select ids, all stages, polish) ≈ that
again. No blockers identified.


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

**Remaining #1: the composition is PER-CHARACTER, not universal.** Measured by
dumping OAM on two different winners: Uranus's portrait uses **31 sprites**
spanning x 19-90 / y 48-120, Moon's uses **18** spanning x 20-86 / y 56-120 —
different counts, positions and tile numbers. Each character's portrait ships
with a sprite layout shaped to that character's silhouette. Feeding Saturn's
art through Uranus's layout (what v0.12.0 does) therefore CLIPS everything
outside his outline — the maintainer saw exactly this: her lower-left hair/face
and the glaive's Y-piece missing, because her portrait fills nearly a full
square while his silhouette does not. **The layout source is a per-character SPRITE LIST fed to the standard OAM
emitter** — the same `$80:9B17`/`$9BCB` family the in-match renderer uses.
Measured live at the card (`probe_cardsaturn.lua`, gated on the card state):
Uranus draws from a list at `$9F:CBED` with count `$1F` (31), Moon from
`$9F:C595` count `$12` (18), both anchored at x=`$34`, y=`$78` via the X-flip
emitter. Those pointers are **computed, not stored** (neither value appears as
a literal anywhere in the ROM), so the selector still has to be traced — watch
`$12/$13/$14` during the card's DRAW phase (the loader reuses `$12`, so the
watch must be gated past it) or disassemble the card's draw loop.

Per-character layout census (sprite count, bounding box):
`Moon 18 / 66x64`, `Mercury 26 / 63x64`, `Mars 16 / 64x64`,
`Uranus 31 / 71x72`. Uranus — already our shell — is the **largest**, so
presenting her as a different character cannot fix the clipping: she needs a
custom list. Sketch: ~81 8x8 sprites in a 9x9 grid (72x72 px) using tiles
`$00-$50`, which stays inside the P1 tile budget (P2's portrait starts at tile
128) and inside the 32-sprites-per-scanline limit at 9 per line.

**Remaining #2: the palette.** The card's portrait colours are CGRAM row 8, and
neither a direct CGRAM DMA nor seeding the `$7E:0600` OBJ-palette shadow
sticks (2/32 bytes survive) — the card re-uploads row 8 from somewhere else.
Next step is one probe: watch `$2121/$2122` writes during the card build, find
the writer and its source, and inject there. Until then the feature stays
gated off (the art shows with the shell character's colours).
