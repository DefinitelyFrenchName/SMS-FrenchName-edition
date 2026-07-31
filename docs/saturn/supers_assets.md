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
