# SMS audio: importing Saturn's voice [P 08-02 … 08-03]

> **STATUS: DONE and verified in v0.13.0 — read "PHASE 3" at the bottom first.**
> It is the implementation and the corrected model; everything above it is the
> investigation that got there, kept because two of its conclusions turned out to
> be wrong in instructive ways (both are flagged in place).

Written because the remaining sfx work (her three throw shouts, her win laugh,
the "Yoroshiku" on select) are all **voice samples**, which is the difference
between substituting an SMS effect (v0.12.7) and sounding like Saturn.

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

> **PARTLY WRONG — corrected in Phase 3.** True for the BANK; wrong about the
> DIRECTORY. The ids resolve through a per-character BRR directory that is
> resident from boot and describes *that character's* sample boundaries, so
> loading her bank under a shell's ids plays her audio cut at the shell's offsets.
> The directory has to be patched too. See "PHASE 3" below.

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

### The samples, IDENTIFIED by the maintainer [P 08-02]

| entry | size | what it is |
|---|---|---|
| 28 | `0x237` | throw shout |
| 29 | `0x4C8` | possibly the looping KO cry (unsure) |
| **30** | `0x546` | **win laugh** |
| **31** | `0xB49` | **236P** |
| **32** | `0xE07` | **214P** |
| **33** | `0x816` | **j.632K** |
| 34 | `0x8CA` | unidentified |

The four bolded ones are exactly the field requests — and SMS's slot holds
exactly four samples, which is a lucky fit in COUNT. **Not in size:**

    the four requested   9900 bytes
    SMS per-fighter slot 9099 bytes  ($B700-$DA8B)
    over by               801 bytes  (8%)

Trimming silence does not save it: measured across all four, the quiet tails
come to only **72 bytes**. These samples are packed tight.

**"Yoroshiku" is NOT in the per-character bank** — the maintainer confirmed it
is absent from all seven. So the select voice lives in whatever sample set the
CHARACTER-SELECT screen loads, which is a separate find.

### Three ways to fit, for the maintainer to choose

1. **Drop the win laugh** (`0x546` = 1350 B) — the other three fit with room to
   spare. Costs the minor request; the laugh stays silent as it is today.
2. **Truncate one sample.** 729 bytes is about 0.16 s at the likely playback
   rate; taken off the end of 214P (the longest, ~0.58 s) all four survive with
   a slight clip.
3. ~~**Use the unclaimed region** `$9B92`-`$B6FF` (7022 bytes).~~ **RULED OUT —
   it is live data.** See below; this is the option that would have bitten us.

### Why option 3 is dead, and the protocol that caught it

The region looked free and passed two independent checks:

* **No audio block can reach it.** Parsing all 48 block pointers in the
  `$C0:ECE7` table gives only five ARAM destinations ever written — `$2800`,
  `$3480`, `$3500`, `$8E00`, `$B700` — and the largest `$8E00` upload ends
  *exactly* at `$9B92`, where the region starts.
* **It is not the echo buffer.** Byte-identical across three stages with
  different music; echo content would vary with the audio.

Both passed, and it still is not free. The check that settled it was
**provenance**: probing the region's bytes against the ROM finds them, in a
clean linear mapping —

    ARAM $9ED2 <- ROM $E4:96DE      (ARAM offset - 0x7F4)
    ARAM $A1D2 <- ROM $E4:99DE
    ...          7 of 7 probes traced back

So roughly 7 KB is deliberately uploaded from bank **`$E4`** into `$9B92`-`$B6FF`
by a path outside the audio table. It is resident data — which is exactly why
it looked static and unreferenced. Claiming it would have corrupted whatever
uses it, in some context we had not exercised.

**Lesson for reuse:** "nothing points at it and it never changes" is not
evidence that memory is free. Ask where the bytes CAME FROM. On a console where
everything is uploaded from ROM, provenance is decisive and cheap.

### Revised recommendation

In-match the real ceiling is P2's bank at `$DB00`, so P1 gets
`$B700`-`$DB00` = **9216 bytes**; the four requested need 9900, over by **684**.
(Note the table does contain a 0x2706 = 9990-byte block for `$B700`, so the
UPLOAD path handles her size fine — the limit is purely the P2 collision.)

### DECIDED [P 08-02]: spread the cut over the three PROJECTILES only

Rendered both candidates and the maintainer judged them by ear:

* **3-way (chosen)** — 26 blocks (52 ms) off each projectile, laugh untouched.
  Verdict: j.632K "indistinguishable", 214P "barely different", 236P "audibly
  shorter but doesn't feel cut". **9198 bytes, 18 spare.**
* 4-way (rejected) — 40 ms off all four including the laugh. It does improve
  the projectiles, but the laugh is the SHORTEST sample, so an equal-BYTES cut
  costs it the largest PROPORTION (13% vs 5%) and it "goes from a 3 part laugh
  to a 2 part laugh". Not worth it.

The lesson worth keeping: equal byte cuts are not equal proportional cuts, and
the shortest sample pays the most. Arithmetic picked the 4-way; listening
picked the 3-way.

**`tools/saturn/extract_saturn_voice.py`** now builds the approved set straight
from the Super S ROM (no trace-dump dependency): the ARAM->ROM mapping is
linear, **file offset = ARAM + `0x2EE17F`**, verified on all four samples. It
emits `saturn_voice.brr` (the bank for ARAM `$B700`) and `saturn_voice.dir`
(four directory entries for ARAM `$3500`), asserting the end flag is moved and
the budget is respected:

    entry 30 win_laugh  ARAM $B700 +0x546
    entry 31 236P       ARAM $BC46 +0xa5f
    entry 32 214P       ARAM $C6A5 +0xd1d
    entry 33 j632K      ARAM $D3C2 +0x72c

### Playback rate: RESOLVED at ~8 kHz [P 08-02]

Worth recording because it looked like an open risk and was actually an
artefact of my own rendering. The identification batch was written at
**11025 Hz** and the maintainer reported every sample "notably too high"; the
A/B batches were written at **8000 Hz** and he reported those as "the correct
pitch". Same bytes, different WAV header — so:

    her samples play at ~8000 Hz
    SNES DSP rate = 32000 * P / 0x1000, so the pitch register is about $0400

SMS's own voice samples decode to plausible durations at the same 8 kHz
(Uranus: 0.33 s, 0.60 s, 0.28 s), which is the encouraging answer for
injection — if both games voice at ~8 kHz, her samples need no resampling and
the existing per-sound pitch will be right. **CONFIRMED by the maintainer** (2026-08-02): SMS's own Uranus voices sound
correct at 8 kHz, so both games voice alike and **no resampling is needed**.

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

---

## PHASE 3 — SHE SPEAKS. Injection implemented and verified [P 08-03]

Shipped in **saturn-smoke v0.13.0**. `SATURN_VOICE=0` builds without it.

### What the earlier phases had wrong

Phase 1 concluded that loading her bank was enough because "the id values are
the same for both players". The id values *are* the same for both players — but
they are **not** the same across characters, and that is the part that matters.
Measured (`probe_sms_voiceid.lua`, reading the DSP's SRCN register for the voice
that actually starts):

    sound id 49 + (charID-1)*5 + k    ->  directory entry 48 + (charID-1)*8 + k
    k = 0..3;  k = 4 falls back to entry 48;  ids past 93 are dead

and P2's id reaches the driver with bit 7 set (`ora #$80` at `$C0:D500`), which
adds 4 to the entry. So each character has its own five ids and its own eight
directory entries — four describing its samples inside P1's `$B700` bank, four
describing the same samples at `$DB00`.

That directory is **not uploaded per match**. It is a complete nine-character
table, resident from boot, at

    ARAM $34C0 + (charID-1)*32        source: ROM $E4:2CC4 + (charID-1)*32

(DSP DIR = page `$34`.) Its 32-byte records are 8 entries of `[start16, loop16]`;
the samples are one-shots, so "loop" is only ever the sample's end.

### And the piece that was genuinely open

> "every `$E5` block targets `$B700`, yet P2's bank lands at `$DB00` — so either
> the loader patches the destination for P2 or the driver relocates it."

**The loader relocates it.** `$C0:EC5E` is a second uploader that adds direct-page
`$10` to every block's ARAM destination, and zeroes `$10` before reading the
terminator so the driver entry point (`$0800`) is never offset. The two call
sites are:

    P1  $C0:88D9   lda $1D00 / clc / adc #$1E / jsl $80:EB4B      (verbatim)
    P2  $C0:8A24   $10 = $2400 …  lda $1D03 / adc #$1E / jsl $80:EC5E

That relocation knob is what makes the implementation cheap: the same stream
serves both players for the samples, and a `$10` of `$0010` steers her directory
block from `$34C0` to `$34D0`.

### The implementation

Five IPL streams live in her appended voice bank, reached through five spare
records in the audio table:

| table id | stream | ARAM |
|---|---|---|
| 47 | her 9198-byte sample bank | `$B700` (+`$2400` for P2) |
| 48 | her 4 directory entries, `$B700`-based | `$34C0` |
| 49 | her 4 directory entries, `$DB00`-based | `$34C0` +`$10` → `$34D0` |
| 50 | char 1's vanilla P1 half (restore) | `$34C0` |
| 51 | char 1's vanilla P2 half (restore) | `$34D0` |

**Spare records.** The loaders index the table with an 8-bit id (`$ECE7 + 6n`);
vanilla ids stop at 39, and `$C0:EE00-EE3F` is a 64-byte zero run that ids 47-57
address. Before claiming it: a full boot → title → select → match → KO → win
session read it **zero times** (`probe_sms_freetable.lua`), and the builder
asserts each record is still zero. This is the same question the ARAM region
failed in Phase 2, asked the same way.

**Whose ids.** She uses **char 1's** (49-52) on whichever side she is playing,
and the build overwrites char 1's half-record *for that player only*. The two
halves of a record are per player and can never both belong to her opponent: a
P1 Moon cannot coexist with a P1 Saturn, and a P2 Moon reads entries 4-7, which
we never touch when she is P1. So one fixed id set covers all nine shells with no
per-shell code — which is how this dodges the "test it with two shells" trap
rather than paying it again.

**Restoring.** Because the directory is boot-resident, a Saturn match would
otherwise leave Moon voicing from her offsets for the rest of the session. The
same hooks put char 1's record back on any non-Saturn load, gated on a DIRTY flag
(`$7F:F107`/`F108`), so vanilla play is untouched and no upload happens unless we
actually dirtied something.

**Requesting.** Her CMD args `0x22-0x25` now write `arg + 0x0F` (= ids 49-52) to
the running object's `+0x78` with a bare `sta $78,X`: the script interpreter is a
loop over objects (`$C0:A05C  ldx #$1000 … adc #$0080 … cpx #$1800`), so X is
already the object base and DP is 0. An earlier attempt did `ldx $88` first, on
the assumption that `$88` is the current object the way it is in the proc helper.
It is not — at CMD time it holds whatever object last set it (measured: a
constant `$1080`), so her voice came out of P2's slot while she was P1.
Clobbering X was the entire bug (`probe_sms_cmdwho.lua`).

### Which sound is which — settled from Super S, not by ear

Super S's command handler (`$80:FBB4`) reads a word per command id from a table
at `$80:FC32 → $FC48`, and the **low byte is the BRR directory entry**:

    cmd $22 -> entry 30   win laugh
    cmd $23 -> entry 31   236P
    cmd $24 -> entry 32   214P
    cmd $25 -> entry 33   j.632K

Our `id = arg + 0x0F` reproduces that ordering exactly against her extracted
bank. This also explains an observation that looked wrong: arg `0x25` fires
during the **ground** specials too (measured: 236 runs act `$6E`→`$70`, 214 runs
act `$6A`→`$6C`, and both second phases request `0x25`). That is Super S's own
behaviour, not a porting error — sample 33 is the release cue as well as the
air move's.

### Acceptance

All on `SailorMoonS_REFsaturn_v0.13.0-hidden.sfc` (`3b835d0c…`):

| probe | result |
|---|---|
| `probe_sms_voicecheck.lua` PLAYER=0 | 8/8 — her 9198 bytes byte-identical at `$B700`, her directory at `$34C0`, opponent's half untouched, ids 49-52 → entries 48-51 |
| `probe_sms_voicecheck.lua` PLAYER=1 | 8/8 — same at `$DB00` / `$34D0`, ids → entries 52-55 |
| `probe_sms_voicerestore.lua` P1/P2 | 4/4 each — a dirtied half is restored to char 1's record and the flag cleared |
| `probe_sms_voicefire.lua` | her specials request 50/51/52 into **P1's** slot while she is P1 |
| `probe_sms_saturn_smoke.lua` | 228/228 |
| `tools/test_regression.lua` | ALL PASS (57) |

**What is not proven here.** Nobody has *listened* to it yet. The plumbing is
verified structurally (right bytes, right addresses, right directory entries,
right player) and the sample content was approved earlier by ear, but whether
each cue lands where it should in play is a field question. The two-real-matches
restore scenario is also assembled from two halves — "a Saturn match sets DIRTY
and installs her offsets" (voicecheck) plus "a dirty directory is restored on the
next ordinary load" (voicerestore) — because ending a VS match from the autopilot
proved unreliable.
