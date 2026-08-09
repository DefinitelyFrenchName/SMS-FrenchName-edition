# The sound system — how a Super Famicom cartridge makes a fighter shout

**What this is.** How *Bishoujo Senshi Sailor Moon S: Jougai Rantou!?* gets audio
out of a cartridge and into the SPC700: where the sample data lives, how it
reaches the sound chip, how a sound id becomes a note, and why **every fighter's
voice is pitched by its own table entry**. Written to be liftable by anyone
hacking this game.

**Ground truth.** Clean ROM SHA-1 `bc0e29ee383574443226695215496eb0d09aaa1c`.
Everything below was **re-measured out of the cartridge on 2026-08-09** — the
tables were read, the SPC700 code was disassembled (`tools/saturn/spc700dis.py`),
and the numbers in this file are the ones that came back, not the ones the
earlier working notes carried. Three of those notes turned out to be off; they
are flagged ⚠ where they appear.

**Where this came from.** The audio system was reverse-engineered while porting a
character's voice in from *Super S* — the blow-by-blow, including the wrong turns,
is `docs/project/saturn/sound_scope.md`. This file is the result with the project
removed. The `tools/checkdocs.py` assertions that keep it honest are named at the
end.

⚠ **One structural caveat, stated once.** The APU is a separate computer with its
own 64 KB of memory (ARAM). Everything in ROM is checkable by reading the
cartridge; everything *in ARAM at runtime* is only observable on a running APU,
and this document marks those claims **[live]**. The saving grace is §3: the
driver and all its tables are **stored in ROM at a fixed offset**, so most of what
looks like an ARAM fact is really a ROM fact wearing a different address.

---

## 1. The chain, end to end

```
ROM bank $E5-$E7          the audio payload: driver, sequences, BRR samples
  │
  │  $C0:EBD4   handshake — wait for the IPL's $BBAA on ports $2140/$2141
  │  $C0:EC5E   block loader — bank id in A, ×6 into the table below
  │  $C0:ECE7   40 records × 6 bytes: [src24][src24], $FFFFFF = "none"
  ▼
ARAM (64 KB, the APU's own memory)
  │  driver code + sequences + the sample directory + the BRR samples
  ▼
SPC700 driver
  │  sound id ─► sfx table ─► sequence ─► note + instrument
  │  note ─► octave/semitone ─► pitch word          (§4)
  │  instrument ─► SRCN + ADSR + tuning             (§5)
  ▼
DSP voices 0-7   (8 logical music channels + 8 sfx, mapped onto them)
```

Two consequences worth having before touching anything:

* **Adding a sound is not adding a sample.** ARAM is full — the largest zero run
  in the whole 64 KB is 64 bytes **[live]**. Anything new displaces something or
  reuses one of the swap slots the game already uses per scene.
* **But retuning a sound is one byte**, and it is in ROM. See §6.

---

## 2. Getting the audio across ($C0:EBD4, $C0:EC5E, $C0:ECE7)

The upload is the stock IPL protocol. `$C0:EBD4` writes `$E2E2` to `$2142` and
spins until port `$2140` reads back `$BBAA`, with a `$1000`-iteration timeout that
retries rather than hanging:

```
C0/EBD4  rep #$30 / ldx #$1000 / ldy #$BBAA / lda #$E2E2
C0/EBDF  sta $2142        ; poke
C0/EBE2  cmp $2142        ; ...and wait for the IPL to answer
C0/EBE7  cpy $2140        ;    $BBAA = "ready"
```

`$C0:EC5E` takes a **bank id** in A, computes `A*6` (`asl / sta $00 / asl / adc
$00`) and reads a 6-byte record from **`$C0:ECE7`**: two 24-bit pointers, the
second usually `$FFFFFF` meaning "only one block". Each block is IPL-format —
`[size16][dest16][data…]`, repeated, terminated by a zero-size chunk whose
"destination" is the entry point.

**The table has 40 records** (`$C0:ECE7-$EDD6`), and the ids divide by job:

| Bank ids | Where the data lives | What they are |
|---|---|---|
| 2-21 | bank `$E7` | the driver, the music/sequence sets, the resident instruments |
| **22-30** | banks `$E6`/`$E7` | **the nine character-select voices**, one per fighter — id = `21 + charID` (§7) |
| 31-39 | bank `$E5` | further sample sets |

⚠ Earlier notes said "bank `$E7` holds 36 blocks" and stopped the table at 22
records. Both were artifacts of where the scan gave up: a record whose first
pointer is `$00FFFF` is a legal hole, not the end of the table.

---

## 3. The driver is in the cartridge, at a fixed offset

This is the fact that makes the rest of this document checkable:

```
file offset = ARAM address + 0x23F804          (SNES $E3:F804)
```

Every table the driver uses — the sfx table, the sequences, the semitone table —
is therefore a normal ROM address you can read, diff and patch. To read the code:

```bash
python3 - <<'PY'          # carve the driver image out of the ROM
import sys; sys.path.insert(0,'tools')
from smspaths import clean_rom
rom = open(clean_rom(),'rb').read()
open('/tmp/aram.bin','wb').write(rom[0x23F804:0x23F804+0x10000])
PY
python3 tools/saturn/spc700dis.py --at 0x0C35 --len 90 /tmp/aram.bin
```

`spc700dis.py` is a full 256-opcode SPC700 disassembler with `--trace` (follow
flow) and `--refs` (who touches an address). Nothing else in the tree reads
SPC code — `Dispel` is 65816 only.

---

## 4. From a sound id to a pitch

```
sound id   ─►  sfx table  $13D6 + (id-1)*4  =  [seq_lo, seq_hi, priority, channel]
                          95 usable ids; past that the table runs into sequence data
sequence   ─►  [command, ptr_lo, ptr_hi, TRANSPOSE, instrument, volL, volR, …]
$0B1E      ─►  copies TRANSPOSE to $0240+X and instrument to $0250+X   (X = channel)
$10A0      ─►  note = <sequence byte> - $74 + $0240+X        ← the transpose lands here
$0D6D      ─►  octave = note/12, semitone = note%12
               pitch = semitone_table[$0DF5] interpolated, >> (6 - octave),
               then scaled by the channel's tuning word ($0410 / $0420 + X)
```

The **semitone table at ARAM `$0DF5`** is thirteen 16-bit words:

```
2143 2270 2405 2548 2700 2860 3030 3211 3402 3604 3818 4045 4286
```

Each is 1.0594× the one before — 2^(1/12), equal temperament, with the thirteenth
entry exactly double the first so the interpolation has an octave to work in.

⚠ **`$131D` and `$1327` are not a pitch routine.** A probe that samples the PC
during playback lands on them constantly, and an earlier note concluded pitch was
emitted from one place shared with the music and therefore untargetable. They are
the `INC Y` instructions inside an unrolled **DSP shadow flush** at `$12F4`, which
pushes seven registers per voice and computes nothing. Pitch is decided by the
sequence data long before it gets there.

---

## 5. Instruments, and the split that matters

`$0C35` turns the sequence's instrument byte into DSP settings, and it takes one
of two roads:

```
0C36  MOV A,$0250+X      ; the instrument byte
0C39  CMP A,#$30
0C3B  BCC $0C5B          ; < $30 → the instrument-record path
      ── ≥ $30 ────────────────────────────────────────────────
0C3D  MOV $0280+X,A      ; SRCN = the instrument byte ITSELF
0C40  MOV A,#$FF → ADSR1        (fixed)
0C45  MOV A,#$E0 → ADSR2        (fixed)
0C4F  MOV A,#$02 → $0420+X      ┐ tuning, fixed: the bytes are $17 and $02
0C54  MOV A,#$17 → $0410+X      ┘
      ── < $30 ────────────────────────────────────────────────
0C5B  6-byte record at ARAM $3700 + inst*6:
      [srcn, ADSR1, ADSR2, GAIN, tune_lo, tune_hi]
```

So **instruments below `$30` are musical** — they get their own envelope and
tuning from a record — and **instruments from `$30` up are raw sample slots**:
the byte *is* the BRR directory entry, the envelope is hardcoded, and every one
of them shares a single tuning constant. Voices are all in the second group,
which is why a voice can only be retuned by moving its note.

---

## 6. Voices: five sounds a fighter, and a transpose byte each

Each fighter owns **five sound ids** and **eight BRR directory entries**:

```
sound ids           49 + (charID-1)*5     … five consecutive
directory entries   48 + (charID-1)*8     … eight: four samples, twice
```

The eight are four samples duplicated for the two player sides — the
directory's ROM source (`$E4:2CC4 + (charID-1)*32`) makes this plain. Uranus's:

| entry | start | loop | side |
|---|---|---|---|
| 88-91 | `$B700`, `$BCCD`, `$C975`, `$D0D7` | … | **P1's** voice bank |
| 92-95 | `$DB00`, `$E0CD`, `$ED75`, `$F4D7` | … | P2's, the same samples again |

A sequence names the P1 entry; the driver plays the copy belonging to the side
that made the sound.

### The transpose table — measured, all nine

Every voice sound carries its own signed **transpose byte**, and the values are
different per character, because the samples were recorded at different pitches
and the transpose is what puts them back in tune:

| charID | fighter | sound ids | instruments (BRR directory) | transposes, in id order |
|---|---|---|---|---|
| 1 | Moon | 49-53 | `$30 $31 $32 $33` `$30` | `-2 -2 -1 -3` `+1` |
| 2 | Mercury | 54-58 | `$38 $39 $3A $3B` `$30` | `-3 +1 -3 -3` `-2` |
| 3 | Mars | 59-63 | `$40 $41 $42 $43` `$30` | `+0 -4 +0 -2` `+1` |
| 4 | Jupiter | 64-68 | `$48 $49 $4A $4B` `$30` | `+0 -1 +0 -6` `+0` |
| 5 | Venus | 69-73 | `$50 $51 $52 $53` `$30` | `-2 -2 -6 -2` `+2` |
| 6 | Uranus | 74-78 | `$58 $59 $5A $5B` `$30` | `-2 -2 -2 -5` `+1` |
| 7 | Neptune | 79-83 | `$60 $61 $62 $63` `$30` | `-4 +0 -4 -1` `+4` |
| 8 | Pluto | 84-88 | `$68 $69 $6A $6B` `$30` | `-2 -1 +1 +0` `+2` |
| 9 | Chibi Moon | 89-93 | `$70 $71 $72 $73` `$00` | `+1 -2 -2 -4` `+0` |

The fifth column of each row is set apart because the fifth sound is the odd one
(below). The range across the roster is **-6 to +4 semitones**, and no two
fighters carry the same set.

Uranus in full, as the worked example:

```
id 74  seq $1DAE  transpose -2  instrument $58 (dir 88)
id 75  seq $1DB9  transpose -2  instrument $59 (dir 89)
id 76  seq $1DC4  transpose -2  instrument $5A (dir 90)
id 77  seq $1DCF  transpose -5  instrument $5B (dir 91)
id 78  seq $1DDA  transpose +1  instrument $30 (dir 48)   ← not hers
```

**Two things fall out of that table.** First, *retuning a fighter's voice is one
byte per sound*, in ROM, at a known address — which is exactly what this project's
patch 101 does for its imported character. Second, **every fighter's fifth sound
points at instrument `$30`**, the first slot of the voice bank rather than one of
their own — except Chibi Moon's, which points at instrument `$00` and so takes
the musical path of §5 entirely. Nobody has identified what that fifth sound is;
it is recorded here because it is the kind of exception that eats an afternoon.

---

## 7. The character-select voice is a different mechanism

The line a fighter says on the select screen is not a sound id at all. `$C0:AE75`
holds a **bank id** per character:

```
$C0:AE75:  00 16 17 18 19 1A 1B 1C 1D 1E        ← id = 21 + charID
```

That id goes to the block loader of §2, which uploads a whole sample block. So the
select voice is chosen by *loading different data*, while the in-match voices are
chosen by *playing a different id from data already resident*. Two mechanisms, and
knowing which is which is the difference between a one-byte edit and a re-upload.

---

## 8. ARAM at runtime [live]

Measured on a running APU, not derivable from the cartridge:

| ARAM | contents |
|---|---|
| `$0800`- | the driver's entry point and code |
| `$2800`-`$3338` | sequence data, swapped per scene |
| **`$3400`** | the BRR sample **directory**, 4 bytes per entry (start, loop) |
| `$3700` | instrument records, 6 bytes each (§5) |
| `$3800`-`$8DFF` | resident instrument samples |
| `$8E00`-`$9B92` | one swappable sample slot, per scene |
| `$B700`-… | **P1's voice bank** — directory entries 48+ |
| `$DB00`-… | **P2's voice bank** — the same samples again |

The largest run of zeros in the whole 64 KB is **64 bytes**. There is no free
ARAM; there are free directory *slots* (entries 33-47 hold nonsense), which is a
different thing.

---

## 9. What is not known

* What the fifth voice sound of each fighter is (§6).
* Whether anything reads the tuning pair `$0410`/`$0420` as a 16-bit word in the
  order the two `MOV`s write it — the bytes are `$17` and `$02`, and this file
  deliberately does not print a combined value it has not verified.
* The music side: sequence commands beyond the header bytes named in §4 are not
  decoded. Nothing this project needed required them.
* Bank ids 0, 1 and 4 have `$00FFFF` in both pointer slots. They are holes in the
  table rather than blocks, but nothing confirms they were never used.

---

## 10. What is checked, and where

`tools/checkdocs.py` re-derives the ROM-side claims here against the cartridge:
the handshake and loader byte patterns, the block table's extent and its
select-voice ids, the driver's `0x23F804` home, the semitone table's ratios, the
sfx table's usable range, and the full per-character voice census — ids,
directory entries and transposes, all nine fighters. The **[live]** ARAM claims in
§8 are not, and cannot be, checked from the cartridge; they come from
`tools/saturn/probe_aram.lua` against a running APU.

Related: `sms_engine_internals.md` §3 (when in the frame sound is triggered),
`docs/project/saturn/sound_scope.md` (the investigation, and the port that
motivated it), `docs/project/patch_notes.md` § Patch 101 (a transpose edit in
practice).
