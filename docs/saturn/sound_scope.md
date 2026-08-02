# SMS audio: scope for importing Saturn's voice [P 08-02]

Scoping only — nothing here is implemented. Written because the remaining sfx
work (her three throw shouts, her win laugh, the "Yoroshiku" on select) are all
**voice samples**, which is the difference between substituting an SMS effect
(done, v0.12.7) and sounding like Saturn.

## How SMS gets audio into the APU

Standard IPL upload (`$BBAA` handshake at `$C0:EBD4`). The per-block loader is
**`$C0:EC5E`**: entered with a bank id in A, it computes `A*6` and reads a
6-byte record from a table at **`$C0:ECE7`** — two 3-byte source pointers, the
second often `$FFFFFF` (none). Both point into bank **`$E7`**, the audio data
bank.

Blocks are in IPL format, `[size16][dest16][data…]` repeated, terminated by a
zero-size chunk whose "dest" is the entry point (`$0800`). Bank `$E7` holds 36
of them.

## ARAM map (measured live, `tools/saturn/probe_aram.lua`)

| ARAM | contents |
|---|---|
| `$2800`-`$3338` | sequence data, swapped per scene (≤ `0xB38`) |
| **`$3400`** | **BRR sample directory**, 64 entries × 4 bytes (start, loop) |
| `$3800`-`$8DFF` | resident instrument samples (directory 0-31) |
| `$8E00`-`$9B92` | swappable sample, directory entry **32**, per scene (≤ `0xD92`) |
| `$B700`-`$FE8B` | further sample banks, directory entries **48-63** |

Two facts decide the shape of any implementation:

1. **ARAM is FULL.** Samples run to `$FE8B`; the only zero run of ≥1 KB in the
   whole 64 KB is 64 bytes at `$FFC0`. There is nowhere to simply *add* a
   sample — anything new must displace something or reuse a swap slot.
2. **Directory entries 33-47 are unused** (they hold nonsense start/loop
   values). So there are free *slots*, just no free *space*.

The game already swaps sample banks per scene, so the machinery to load
different samples exists — that is the lever, not free memory.

## Lead: per-fighter voice banks

Directory entries 48-55 and 56-63 mirror each other, starting at `$B700` and
`$DB00` respectively with matching sizes. That is consistent with **two voice
banks, one per fighter**, loaded per match. If it holds, Saturn's voice belongs
in the bank for whichever player is using her — which is the same shape as the
graphics work (per-character asset selected by id) and would reuse the lesson
that the SHELL can be any of the nine.

**Unconfirmed.** Verify by diffing ARAM between two matchups with different
characters.

## Super S side

Its CPU-side uploader is **not** byte-identical to SMS's (searched for SMS's
`$C0:EC5E` loader, the `$BBAA` handshake and the port ping — none present). So
the two games do **not** share the audio engine, unlike every graphics
structure so far, which have matched every time. That does not block a sample
lift — BRR is BRR, and what matters is the sample data plus its loop point —
but it does mean nothing can be assumed by analogy here, which is exactly the
assumption that has cost time elsewhere in this project.

## Open questions, in the order they should be answered

1. Are `$B700`/`$DB00` really per-fighter voice banks? (ARAM diff between two
   matchups — cheap, one probe.)
2. Where is the character → voice-bank mapping? The `$C0:ECE7` table is
   scene-indexed, not character-indexed, so there is another table.
3. Where are Super S's voice samples, and which ids do her scripts request for
   the throw shout, the win laugh and the select "Yoroshiku"?
4. Is the sfx trigger path (sound id → sample id) table-driven and extensible?
5. If a bank must be displaced: what is safe to drop, and does the size budget
   fit her samples?

## Effort and risk

Phases 1-2 (questions 1-3) are ordinary RE of the kind already done repeatedly
here, and are low risk. Phase 3 — injecting a sample and pointing a directory
entry at it — is new ground: it touches a full ARAM with no slack, and a wrong
loop point or a displaced instrument is audible immediately. It should be
attempted only after 1-3 are answered, and it is the point at which this stops
being cheap.

The interim substitutes shipped in v0.12.7 (heavy whoosh on the throws, silence
on the win) keep the character playable and honest-sounding meanwhile.
