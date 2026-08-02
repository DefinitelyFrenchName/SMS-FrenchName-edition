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

## PHASE 1 RESULTS [P 08-02] — the lever exists and the table has room

**Per-fighter voice banks: CONFIRMED.** ARAM diffed across three matchups
(Uranus-vs-Uranus, Moon-vs-Mars, Uranus-vs-Mars): changing only P2 alters only
`$DB00`+, changing only P1 alters only `$B700`+. So

    $B700 = P1's voice bank (directory entries 48-55)
    $DB00 = P2's voice bank (directory entries 56-63)

about **9 KB per fighter** — a comfortable budget for her samples.

**Where the banks come from.** Not the `$C0:EC5E` indexed loader that serves
music: catching the IPL data-port writes live shows the match-time upload comes
from bank **`$E5`**. That bank holds **8 blocks of ~8 KB, every one targeting
ARAM `$B700`** — the per-character voice banks.

**How a character selects one.** They are entries **31-38 of the SAME table at
`$C0:ECE7`** (6-byte records, two 3-byte source pointers; the second is
`$FFFFFF` here). Entry 39 is `$E6:0000`, plausibly the ninth character. **Entry
40 onward is zeros** — the table simply ends, so an entry can be APPENDED for
Saturn without moving anything.

**How sounds are triggered.** Per frame, `$C0:D4F5` sends three bytes to the
APU: P1's sound id from its struct `+0x78` (`$1078`) to port 0, P2's from
`$10F8` to port 1, and the global one-shot `$78` to port 2 — the same `$78` our
CMD stub already writes.

> **Not two id spaces.** An earlier phrasing here said ids are "per player",
> which wrongly implies different addressing for P1 and P2. The id VALUES are
> the same for both; what is per player is the delivery PORT, and therefore
> which resident bank the SPC resolves that id against. Verified on a mirror
> match: P1's and P2's regions hold the same four samples with identical sizes
> and are byte-identical for 92% of their length (the tail is stale data past
> P2's shorter upload) — so the same character sounds the same in either slot,
> which matches play experience.

The consequence for us:

> If Saturn's voice bank is loaded for her player, she keeps using the SAME
> sound ids and simply speaks in her own voice. No id remapping is needed.

So the shape of the work is now: append her voice block, append a table entry,
and make the loader pick her entry when the Saturn flag is set — structurally
the same redirect as the card portrait, and with the same shell caveat (she can
be summoned over any of the nine).

**Still open from Phase 1:** every `$E5` block targets `$B700`, yet P2's bank
lands at `$DB00` — so either the loader patches the destination for P2 or the
driver relocates it. That must be understood before injecting, since Saturn
must work in either slot.

## PHASE 2 PROGRESS [P 08-02] — her audio is locatable, her sample map is not

Super S's ARAM was dumped mid-match and every region matched back to a verbatim
ROM source (samples are uploaded uncompressed, so a byte search finds them):

| ARAM | ROM source |
|---|---|
| `$1F00`-`$4AFF` | `$E9:0D6D` |
| `$5B00`-`$66FF` | `$E9:EF14` |
| **`$7B00`-`$AAFF`** | **`$EF:5C7F`** — the per-character region |
| `$AC00`-`$B6FF` | `$ED:2ADF` |
| `$B700`-`$EFFF` | `$EE:7605` |

Note `$B700` is the same address SMS uses for a voice bank, so the two drivers
share memory-layout conventions even though their uploaders differ.

Diffing ARAM between **P1 = Saturn** and **P1 = Uranus** (same opponent) gives
37 differing runs, nearly all inside `$7B00`-`$AAFF` and each matching verbatim
into ROM around `$EF:5688`-`$EF:6829`. So **her audio data is in bank `$EF`**
and the diff identifies exactly which byte ranges are hers.

**SUPER S'S SAMPLE DIRECTORY: FOUND at ARAM `$1E00`.** Located by scanning for
a page whose entries are ordered, contiguous and land inside the known sample
regions (the earlier "most directory-like page" heuristic was too loose and
returned `$FA00`, where every entry had start == loop).

Diffing the directory between a **P1 = Saturn** run and a **P1 = Uranus** run
isolates the per-character voice samples exactly: **entries 28-34 change,
everything else is identical**. So Super S keeps **7 voice samples per
character**; Saturn's span ARAM `$7500`-`$AB75`, about **13.6 KB**:

| entry | ARAM | size |
|---|---|---|
| 28 | `$7500` | `0x237` |
| 29 | `$7737` | `0x4C8` |
| 30 | `$7BFF` | `0x546` |
| 31 | `$8145` | `0xB49` |
| 32 | `$8C8E` | `0xE07` |
| 33 | `$9A95` | `0x816` |
| 34 | `$A2AB` | `0x8CA` |

All seven decode cleanly with proper end flags (`tools/saturn/brr.py`), so the
bytes and loop points are in hand — extraction is solved.

**THE REAL CONSTRAINT, now measurable.** SMS's per-fighter slot holds **4
samples in ~9 KB** (its voice directory is a second table at ARAM `$3500`,
entries 0-3 = P1's region, 4-7 = P2's). Saturn's Super S set is **7 samples in
13.6 KB**. Her voice therefore does NOT fit as-is: a subset must be chosen —
realistically the throw shout, the laugh, the select line, and one hit grunt.

**What is still missing.** Super S's per-character audio is NOT the clean
single ~8 KB bank SMS uses — the differing ranges are scattered (0x80-0x1D0
bytes each), which is consistent with individual samples rather than one block.
Extracting them needs Super S's **sample directory** (start + loop per sample),
which is not located yet: the "most directory-like page" heuristic returned a
false positive (`$FA00`, every entry with start == loop). The DSP `$5D` DIR
register would give it directly but is not exposed through the ARAM dump.

Without that, individual samples cannot be cut with correct loop points — and a
wrong loop point on a voice sample is an audible buzz, not a subtle flaw.

**Next, in order:** (a) ~~find the DIR page~~ **done — `$1E00`**; (b) identify
which of the seven is the throw shout, the laugh and the "Yoroshiku" — they are
decoded to WAV in `build/saturn/voice/` for a listener to name, since that is an
ear question, not a disassembly one; (c) pick the subset that fits 4 slots /
9 KB; (d) only then attempt injection.

## Open questions, in the order they should be answered

1. ~~Are `$B700`/`$DB00` per-fighter voice banks?~~ **ANSWERED: yes.**
2. ~~Where is the character → voice-bank mapping?~~ **ANSWERED: entries 31-38
   of `$C0:ECE7`**, sources in bank `$E5`, and the table has free space after
   entry 39.
2b. **NEW:** how does P2's bank reach `$DB00` when every block says `$B700`?
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
